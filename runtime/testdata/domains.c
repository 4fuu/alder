/* Storage-domain behavior tests: lifecycle, alignment, marks, resets,
 * parent/child destruction, invalid inputs, and leak-free cycles. */
#include "aster.h"

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
    AsterDomain d;
    CHECK(aster_domain_init(&d, NULL));
    CHECK(!aster_domain_init(&d, NULL)); /* double init rejected */

    void *a = aster_domain_alloc(&d, 100, 8);
    CHECK(a != NULL);
    CHECK(((uintptr_t)a & 7u) == 0u);
    void *b = aster_domain_alloc(&d, 100, 64);
    CHECK(b != NULL);
    CHECK(((uintptr_t)b & 63u) == 0u);
    void *c = aster_domain_alloc(&d, 100, 4096);
    CHECK(c != NULL);
    CHECK(((uintptr_t)c & 4095u) == 0u);

    /* Mark, allocate more, reset: post-mark storage is released. */
    AsterDomainMark m = aster_domain_mark(&d);
    CHECK(m.segment != NULL);
    void *post = aster_domain_alloc(&d, 64, 8);
    CHECK(post != NULL);
    CHECK(aster_domain_reset(&d, m));
    CHECK(aster_domain_alloc(&d, 64, 8) != NULL);

    aster_domain_destroy(&d);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_marks(void) {
    AsterDomain d;
    CHECK(aster_domain_init(&d, NULL));

    /* An empty domain marks {NULL, 0} and resets to it successfully. */
    AsterDomainMark m1 = aster_domain_mark(&d);
    CHECK(m1.segment == NULL);
    CHECK(m1.offset == 0u);
    CHECK(aster_domain_reset(&d, m1));

    /* {NULL, 0} cannot reset a non-empty domain. */
    CHECK(aster_domain_alloc(&d, 32, 8) != NULL);
    AsterDomainMark zero = {NULL, 0};
    CHECK(!aster_domain_reset(&d, zero));

    /* A mark from a segment released by an earlier reset is rejected. */
    AsterDomainMark m2 = aster_domain_mark(&d);
    void *large = aster_domain_alloc(&d, (size_t)2u * 1024u * 1024u, 16);
    CHECK(large != NULL);
    AsterDomainMark m3 = aster_domain_mark(&d);
    CHECK(m3.segment != m2.segment);
    CHECK(aster_domain_reset(&d, m2));  /* frees the large segment */
    CHECK(!aster_domain_reset(&d, m3)); /* stale mark */

    /* A mark of another domain is rejected. */
    AsterDomain other;
    CHECK(aster_domain_init(&other, NULL));
    CHECK(aster_domain_alloc(&other, 16, 8) != NULL);
    AsterDomainMark foreign = aster_domain_mark(&other);
    CHECK(!aster_domain_reset(&d, foreign));
    aster_domain_destroy(&other);

    /* Rewinding to an older mark of a still-active segment is allowed. */
    AsterDomainMark earlier = aster_domain_mark(&d);
    CHECK(aster_domain_alloc(&d, 128, 8) != NULL);
    CHECK(aster_domain_alloc(&d, 128, 8) != NULL);
    CHECK(aster_domain_reset(&d, earlier));

    aster_domain_destroy(&d);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_parent_child(void) {
    AsterDomain root;
    AsterDomain child;
    AsterDomain grandchild;
    CHECK(aster_domain_init(&root, NULL));
    CHECK(aster_domain_init(&child, &root));
    CHECK(aster_domain_init(&grandchild, &child));

    /* init against a destroyed parent fails. */
    AsterDomain dead;
    CHECK(aster_domain_init(&dead, NULL));
    aster_domain_destroy(&dead);
    AsterDomain orphan;
    CHECK(!aster_domain_init(&orphan, &dead));

    /* Destroying the root destroys children with it; later destroys are
     * no-ops. */
    aster_domain_destroy(&root);
    aster_domain_destroy(&child);
    aster_domain_destroy(&grandchild);
    aster_domain_destroy(&root);
    CHECK(aster_runtime_live_allocations() == 0u);

    /* Domains can be re-initialized after destroy. */
    CHECK(aster_domain_init(&root, NULL));
    aster_domain_destroy(&root);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_invalid(void) {
    AsterDomain d;
    CHECK(aster_domain_init(&d, NULL));

    /* Bad alignments. */
    CHECK(aster_domain_alloc(&d, 16, 0) == NULL);
    CHECK(aster_domain_alloc(&d, 16, 3) == NULL);
    CHECK(aster_domain_alloc(&d, 16, 17) == NULL);
    /* Overflowing sizes. */
    CHECK(aster_domain_alloc(&d, (size_t)-1, 16) == NULL);
    CHECK(aster_domain_alloc(&d, (size_t)-1 - 100, 128) == NULL);
    CHECK(aster_domain_alloc(&d, (size_t)-1, 0) == NULL); /* align first */

    /* Operations on a destroyed domain fail cleanly. */
    aster_domain_destroy(&d);
    CHECK(aster_domain_alloc(&d, 16, 8) == NULL);
    AsterDomainMark m = aster_domain_mark(&d);
    CHECK(m.segment == NULL);
    CHECK(!aster_domain_reset(&d, m));
    CHECK(aster_domain_init(&d, NULL)); /* re-init works */
    aster_domain_destroy(&d);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_segmentation(void) {
    AsterDomain d;
    CHECK(aster_domain_init(&d, NULL));

    /* Many small allocations must span multiple regular segments. */
    CHECK(aster_domain_alloc(&d, 16, 8) != NULL); /* ensure a first segment */
    AsterDomainMark before = aster_domain_mark(&d);
    for (int i = 0; i < 2000; i++) {
        CHECK(aster_domain_alloc(&d, 64, 8) != NULL);
    }
    AsterDomainMark after = aster_domain_mark(&d);
    CHECK(aster_domain_reset(&d, before));
    /* Large allocations get dedicated segments and remain valid. */
    void *big1 = aster_domain_alloc(&d, (size_t)3u * 1024u * 1024u, 16);
    void *big2 = aster_domain_alloc(&d, (size_t)3u * 1024u * 1024u, 4096);
    CHECK(big1 != NULL);
    CHECK(big2 != NULL);
    CHECK(((uintptr_t)big2 & 4095u) == 0u);
    CHECK(aster_domain_reset(&d, after) == false); /* after is stale now */
    aster_domain_destroy(&d);
    CHECK(aster_runtime_live_allocations() == 0u);
}

static void test_cycles(void) {
    for (int i = 0; i < 1000; i++) {
        AsterDomain d;
        CHECK(aster_domain_init(&d, NULL));
        for (int j = 0; j < 50; j++) {
            CHECK(aster_domain_alloc(&d, (size_t)(j * 37 + 1), 16) != NULL);
        }
        AsterDomainMark m = aster_domain_mark(&d);
        for (int j = 0; j < 10; j++) {
            CHECK(aster_domain_alloc(&d, 256, 32) != NULL);
        }
        CHECK(aster_domain_reset(&d, m));
        for (int j = 0; j < 10; j++) {
            CHECK(aster_domain_alloc(&d, 256, 32) != NULL);
        }
        aster_domain_destroy(&d);
        if (aster_runtime_live_allocations() != 0u) {
            fprintf(stderr, "FAIL: live allocations after cycle %d: %zu\n", i,
                    aster_runtime_live_allocations());
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
