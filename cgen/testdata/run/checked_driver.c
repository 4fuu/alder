/* Driver for checked.mir: boundary behavior of every checked operation at
 * 64-bit and narrow widths, including failure edges. */
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
    /* i64: 10 and 2 -> sum 12, diff 10, prod 100, quot 50, shl 200,
     * shr 50. */
    CHECK(alder_fn_i64ops_0(10, 2) == 50);
    /* Overflow in add fails the whole chain. */
    CHECK(alder_fn_i64ops_0(INT64_MAX, 1) == 0);
    CHECK(alder_fn_i64ops_0(INT64_MIN, -1) == 0); /* INT64_MIN - 1 overflows */
    /* Division failure. */
    CHECK(alder_fn_i64ops_0(10, 0) == 0);
    CHECK(alder_fn_i64ops_0(INT64_MIN, -1) == 0);
    /* Shift count failure. */
    CHECK(alder_fn_i64ops_0(1, 64) == 0);
    CHECK(alder_fn_i64ops_0(1, -1) == 0);

    /* i8: 10 and 2 -> sum 12, diff 10, prod 100, quot 50, shl 200 wraps to
     * -56, arithmetic shr by 2 -> -14. */
    CHECK(alder_fn_i8ops_1(10, 2) == -14);
    /* Narrow range check: prod 100 * 100 overflows i8. */
    CHECK(alder_fn_i8ops_1(100, 100) == 0);
    /* Narrow shift count at or above the width fails. */
    CHECK(alder_fn_i8ops_1(1, 8) == 0);
    CHECK(alder_fn_i8ops_1(1, -1) == 0);
    /* i8 division: -128 / -1 would exceed 127. */
    CHECK(alder_fn_i8ops_1(-128, -1) == 0);

    /* u64: 10 and 2 -> 50. */
    CHECK(alder_fn_u64ops_2(10, 2) == 50);
    CHECK(alder_fn_u64ops_2(UINT64_MAX, 1) == 0); /* add wraps */
    CHECK(alder_fn_u64ops_2(10, 0) == 0);         /* division by zero */
    CHECK(alder_fn_u64ops_2(1, 64) == 0);         /* shift count */

    /* u8: 10 and 2 -> sum 12, diff 10, prod 100, quot 50, shl 200 wraps to
     * 200 & 0xff = 200? No: (uint8_t)200 = 200, logical shr -> 50. */
    CHECK(alder_fn_u8ops_3(10, 2) == 50);
    /* u8 range: 16 * 16 = 256 overflows. */
    CHECK(alder_fn_u8ops_3(16, 16) == 0);

    /* Intermediate widths use their exact checked ranges. */
    CHECK(alder_fn_i16add_4(30000, 2767) == 32767);
    CHECK(alder_fn_i16add_4(32767, 1) == 0);
    CHECK(alder_fn_u16add_5(65534u, 1u) == 65535u);
    CHECK(alder_fn_u16add_5(65535u, 1u) == 0u);
    CHECK(alder_fn_i32add_6(INT32_MAX - 1, 1) == INT32_MAX);
    CHECK(alder_fn_i32add_6(INT32_MAX, 1) == 0);
    CHECK(alder_fn_u32add_7(UINT32_MAX - 1u, 1u) == UINT32_MAX);
    CHECK(alder_fn_u32add_7(UINT32_MAX, 1u) == 0u);

    /* Signed right shift is arithmetic, including the two boundary counts. */
    CHECK(alder_fn_i16shr_8(-3, 0) == -3);
    CHECK(alder_fn_i16shr_8(-3, 15) == -1);
    CHECK(alder_fn_i32shr_9(-3, 0) == -3);
    CHECK(alder_fn_i32shr_9(-3, 31) == -1);

    /* Conversions: trunc to i32 wraps (0x1FFFFFFFF -> -1), sext and the
     * float round trip recover the original small values. */
    CHECK(alder_fn_convs_10(7, 7) == 7);
    CHECK(alder_fn_convs_10(-5, 5) == -5);
    /* Values that lose precision through the f32 round trip take the
     * failure edge (16777217 is not representable in f32). */
    CHECK(alder_fn_convs_10(16777217, 0xFFFFFFFFULL) == 0);
    CHECK(alder_fn_narrow_11(1.25) == 1.25f);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
