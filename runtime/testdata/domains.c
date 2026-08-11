/* Storage-domain behavior tests: lifecycle, alignment, marks, resets,
 * parent/child destruction, invalid inputs, and leak-free cycles. */
#include "alder.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

static void test_lifecycle(void) {
    AlderDomain d = {0};
    CHECK(alder_domain_init(&d, NULL));
    CHECK(!alder_domain_init(&d, NULL)); /* double init rejected */

    void *a = alder_domain_alloc(&d, 100, 8);
    CHECK(a != NULL);
    CHECK(((uintptr_t)a & 7u) == 0u);
    void *b = alder_domain_alloc(&d, 100, 64);
    CHECK(b != NULL);
    CHECK(((uintptr_t)b & 63u) == 0u);
    void *c = alder_domain_alloc(&d, 100, 4096);
    CHECK(c != NULL);
    CHECK(((uintptr_t)c & 4095u) == 0u);

    /* Mark, allocate more, reset: post-mark storage is released. */
    AlderDomainMark m = alder_domain_mark(&d);
    CHECK(m.segment_serial != 0u);
    void *post = alder_domain_alloc(&d, 64, 8);
    CHECK(post != NULL);
    CHECK(alder_domain_reset(&d, m));
    CHECK(alder_domain_alloc(&d, 64, 8) != NULL);

    alder_domain_destroy(&d);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_marks(void) {
    AlderDomain d = {0};
    CHECK(alder_domain_init(&d, NULL));

    /* A mark before the first allocation resets the domain to empty. */
    AlderDomainMark m1 = alder_domain_mark(&d);
    CHECK(m1.domain_serial == d.serial);
    CHECK(m1.reset_epoch == d.reset_epoch);
    CHECK(m1.segment_serial == 0u);
    CHECK(m1.offset == 0u);
    CHECK(alder_domain_alloc(&d, 32, 8) != NULL);
    CHECK(alder_domain_reset(&d, m1));
    CHECK(d.segments_head == NULL && d.segments_tail == NULL);
    CHECK(!alder_domain_reset(&d, m1)); /* reset consumes the mark epoch */

    /* A zero/forged mark never belongs to an initialized domain. */
    AlderDomainMark zero = {0};
    CHECK(!alder_domain_reset(&d, zero));
    CHECK(alder_domain_alloc(&d, 32, 8) != NULL);

    /* A mark from a segment released by an earlier reset is rejected. */
    AlderDomainMark m2 = alder_domain_mark(&d);
    void *large = alder_domain_alloc(&d, (size_t)2u * 1024u * 1024u, 16);
    CHECK(large != NULL);
    AlderDomainMark m3 = alder_domain_mark(&d);
    CHECK(m3.segment_serial != m2.segment_serial);
    CHECK(alder_domain_reset(&d, m2));  /* frees the large segment */
    CHECK(!alder_domain_reset(&d, m3)); /* stale mark */

    /* A mark of another domain is rejected. */
    AlderDomain other = {0};
    CHECK(alder_domain_init(&other, NULL));
    CHECK(alder_domain_alloc(&other, 16, 8) != NULL);
    AlderDomainMark foreign = alder_domain_mark(&other);
    CHECK(!alder_domain_reset(&d, foreign));
    alder_domain_destroy(&other);

    /* Rewinding to a mark consumes it and every other mark in that epoch. */
    AlderDomainMark earlier = alder_domain_mark(&d);
    CHECK(alder_domain_alloc(&d, 128, 8) != NULL);
    CHECK(alder_domain_alloc(&d, 128, 8) != NULL);
    CHECK(alder_domain_reset(&d, earlier));
    CHECK(!alder_domain_reset(&d, earlier));

    alder_domain_destroy(&d);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_parent_child(void) {
    AlderDomain root = {0};
    AlderDomain child = {0};
    AlderDomain grandchild = {0};
    CHECK(alder_domain_init(&root, NULL));
    CHECK(alder_domain_init(&child, &root));
    CHECK(alder_domain_init(&grandchild, &child));

    /* init against a destroyed parent fails. */
    AlderDomain dead = {0};
    CHECK(alder_domain_init(&dead, NULL));
    alder_domain_destroy(&dead);
    AlderDomain orphan = {0};
    CHECK(!alder_domain_init(&orphan, &dead));

    /* Destroying the root destroys children with it; later destroys are
     * no-ops. */
    alder_domain_destroy(&root);
    alder_domain_destroy(&child);
    alder_domain_destroy(&grandchild);
    alder_domain_destroy(&root);
    CHECK(alder_runtime_live_allocations() == 0u);

    /* Domains can be re-initialized after destroy. */
    CHECK(alder_domain_init(&root, NULL));
    alder_domain_destroy(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_invalid(void) {
    AlderDomain d = {0};
    CHECK(alder_domain_init(&d, NULL));

    /* Bad alignments. */
    CHECK(alder_domain_alloc(&d, 16, 0) == NULL);
    CHECK(alder_domain_alloc(&d, 16, 3) == NULL);
    CHECK(alder_domain_alloc(&d, 16, 17) == NULL);
    /* Overflowing sizes. */
    CHECK(alder_domain_alloc(&d, (size_t)-1, 16) == NULL);
    CHECK(alder_domain_alloc(&d, (size_t)-1 - 100, 128) == NULL);
    CHECK(alder_domain_alloc(&d, (size_t)-1, 0) == NULL); /* align first */

    /* Operations on a destroyed domain fail cleanly. */
    alder_domain_destroy(&d);
    CHECK(alder_domain_alloc(&d, 16, 8) == NULL);
    AlderDomainMark m = alder_domain_mark(&d);
    CHECK(m.domain_serial == 0u);
    CHECK(m.segment_serial == 0u);
    CHECK(!alder_domain_reset(&d, m));
    CHECK(alder_domain_init(&d, NULL)); /* re-init works */
    alder_domain_destroy(&d);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_segmentation(void) {
    AlderDomain d = {0};
    CHECK(alder_domain_init(&d, NULL));

    /* Many small allocations must span multiple regular segments. */
    CHECK(alder_domain_alloc(&d, 16, 8) != NULL); /* ensure a first segment */
    AlderDomainMark before = alder_domain_mark(&d);
    for (int i = 0; i < 2000; i++) {
        CHECK(alder_domain_alloc(&d, 64, 8) != NULL);
    }
    AlderDomainMark after = alder_domain_mark(&d);
    CHECK(alder_domain_reset(&d, before));
    /* Large allocations get dedicated segments and remain valid. */
    void *big1 = alder_domain_alloc(&d, (size_t)3u * 1024u * 1024u, 16);
    void *big2 = alder_domain_alloc(&d, (size_t)3u * 1024u * 1024u, 4096);
    CHECK(big1 != NULL);
    CHECK(big2 != NULL);
    CHECK(((uintptr_t)big2 & 4095u) == 0u);
    CHECK(alder_domain_reset(&d, after) == false); /* after is stale now */
    alder_domain_destroy(&d);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_cycles(void) {
    for (int i = 0; i < 1000; i++) {
        AlderDomain d = {0};
        CHECK(alder_domain_init(&d, NULL));
        for (int j = 0; j < 50; j++) {
            CHECK(alder_domain_alloc(&d, (size_t)(j * 37 + 1), 16) != NULL);
        }
        AlderDomainMark m = alder_domain_mark(&d);
        for (int j = 0; j < 10; j++) {
            CHECK(alder_domain_alloc(&d, 256, 32) != NULL);
        }
        CHECK(alder_domain_reset(&d, m));
        for (int j = 0; j < 10; j++) {
            CHECK(alder_domain_alloc(&d, 256, 32) != NULL);
        }
        alder_domain_destroy(&d);
        if (alder_runtime_live_allocations() != 0u) {
            fprintf(stderr, "FAIL: live allocations after cycle %d: %zu\n", i,
                    alder_runtime_live_allocations());
            failures += 1;
            break;
        }
    }
}

int main(void) {
    test_lifecycle();
    test_marks();
    test_parent_child();
    test_invalid();
    test_segmentation();
    test_cycles();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
