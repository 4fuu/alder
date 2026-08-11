/* Slice bounds-check helper tests. */
#include "aster.h"

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

static void test_index_checked(void) {
    uint8_t storage[16] = {0};
    AsterSlice s = {storage, 16};
    CHECK(aster_slice_index_checked(s, 0));
    CHECK(aster_slice_index_checked(s, 15));
    CHECK(!aster_slice_index_checked(s, 16));
    CHECK(!aster_slice_index_checked(s, UINT64_MAX));

    AsterSlice empty = {NULL, 0};
    CHECK(!aster_slice_index_checked(empty, 0));
    CHECK(!aster_slice_index_checked(empty, UINT64_MAX));
}

static void test_range_checked(void) {
    uint8_t storage[16] = {0};
    AsterSlice s = {storage, 16};
    CHECK(aster_slice_range_checked(s, 0, 0));
    CHECK(aster_slice_range_checked(s, 0, 16));
    CHECK(aster_slice_range_checked(s, 8, 8));
    CHECK(aster_slice_range_checked(s, 8, 16));
    CHECK(!aster_slice_range_checked(s, 8, 17));
    CHECK(!aster_slice_range_checked(s, 17, 17));
    CHECK(!aster_slice_range_checked(s, 9, 8)); /* lo > hi */
    CHECK(!aster_slice_range_checked(s, 0, UINT64_MAX));

    AsterSlice empty = {NULL, 0};
    CHECK(aster_slice_range_checked(empty, 0, 0));
    CHECK(!aster_slice_range_checked(empty, 0, 1));

    AsterSlice invalid = {NULL, 4};
    CHECK(!aster_slice_range_checked(invalid, 0, 0));
    CHECK(!aster_slice_range_checked(invalid, 0, 1));
    CHECK(!aster_slice_range_checked(invalid, 1, 1));
    CHECK(!aster_slice_range_checked(invalid, 0, 4));
}

int main(void) {
    test_index_checked();
    test_range_checked();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
