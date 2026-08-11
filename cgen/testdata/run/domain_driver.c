/* Driver for domain.mir: domain create/alloc/mark/reset/destroy and
 * copy_to_domain, with leak checks. */
#include "gen.c"

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

int main(void) {
    AlderDomain root = {0};
    CHECK(alder_domain_init(&root, NULL));

    uint8_t data[3] = {7, 8, 9};
    AlderSlice s = {data, 3};
    AlderSlice out = alder_fn_build_0(&root, s);
    CHECK(out.len == 3);
    CHECK(out.data != NULL);
    CHECK(memcmp(out.data, data, 3) == 0);

    /* The copied bytes live in the root domain, so they survive the
     * function's internal destroy and reset. */
    uint8_t *bytes = (uint8_t *)out.data;
    CHECK(bytes[0] == 7 && bytes[1] == 8 && bytes[2] == 9);

    /* Empty input yields an empty result without crashing. */
    AlderSlice empty = {NULL, 0};
    AlderSlice out2 = alder_fn_build_0(&root, empty);
    CHECK(out2.len == 0);

    /* The function destroyed its internal domain; the root and all copied
     * storage are released with it. */
    alder_domain_destroy(&root);
    CHECK(alder_runtime_live_allocations() == 0u);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
