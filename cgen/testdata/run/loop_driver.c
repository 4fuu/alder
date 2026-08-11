/* Driver for loop.mir: a loop over a slice with locals, comparisons, and
 * checked element access. */
#include "gen.c"

#include <stdint.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

int main(void) {
    int64_t data[4] = {1, 2, 3, 4};
    AlderSlice s = {data, 4};
    CHECK(alder_fn_sum_0(s) == 10);

    AlderSlice empty = {NULL, 0};
    CHECK(alder_fn_sum_0(empty) == 0);

    int64_t one[1] = {42};
    AlderSlice single = {one, 1};
    CHECK(alder_fn_sum_0(single) == 42);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
