/* Driver for cbuffer.mir: a call-scoped buffer borrow passes the buffer's
 * data pointer to C, and an empty buffer with a null data pointer still
 * passes the runtime's non-null one-byte dummy, which both fixture
 * functions require even at count zero. */
#include "gen.c"

#include <stdint.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(cond)                                                         \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                  \
        }                                                                   \
    } while (0)

int main(void) {
    uint8_t bytes[4] = {1, 2, 3, 4};
    AlderSlice view = { bytes, 4 };

    /* A MutSlice borrow fills the caller's storage in place. */
    CHECK(alder_fn_fill_0(view, 4) == (size_t)4);
    CHECK(bytes[0] == 7 && bytes[1] == 7 && bytes[2] == 7 && bytes[3] == 7);

    /* An immutable slice borrow reads it. */
    bytes[0] = 1;
    bytes[1] = 2;
    bytes[2] = 3;
    bytes[3] = 4;
    CHECK(alder_fn_sum_slice_1(view, 4) == (size_t)10);

    /* An owned Bytes value borrows the same way. */
    AlderBytes owned = { bytes, 4 };
    CHECK(alder_fn_sum_bytes_2(owned, 4) == (size_t)10);

    /* An empty buffer with a null data pointer must not reach C as NULL. */
    AlderSlice empty = { NULL, 0 };
    CHECK(alder_fn_fill_0(empty, 0) == (size_t)0);
    CHECK(alder_fn_sum_slice_1(empty, 0) == (size_t)0);
    AlderBytes empty_owned = { NULL, 0 };
    CHECK(alder_fn_sum_bytes_2(empty_owned, 0) == (size_t)0);

    return failures == 0 ? 0 : 1;
}
