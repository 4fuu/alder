/* Driver for convert.mir: the integer conversion ops. The checked forms keep
 * in-range values and yield the empty option exactly outside the target
 * range, probed at every width edge here (127/128, 255/256, the i32 and u32
 * limits, UINT64_MAX); the wrapping forms keep the value's low bits at the
 * target width in two's complement. */
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

static void check_opt_i64(AlderTy12 opt, int want_some, int64_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_i8(AlderTy13 opt, int want_some, int8_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_u8(AlderTy14 opt, int want_some, uint8_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_u64(AlderTy15 opt, int want_some, uint64_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

int main(void) {
    /* checked widening of u32 into i64 is exact at both ends. */
    check_opt_i64(alder_fn_to_i64_checked_0(0u), 1, 0);
    check_opt_i64(alder_fn_to_i64_checked_0(4294967295u), 1, 4294967295);

    /* checked sign-changing conversion of u64 into i64: INT64_MAX itself is
     * the last accepted value, everything above is outside. */
    check_opt_i64(alder_fn_to_i64_checked_u64_1(0u), 1, 0);
    check_opt_i64(alder_fn_to_i64_checked_u64_1(4294967295u), 1, 4294967295);
    check_opt_i64(alder_fn_to_i64_checked_u64_1(9223372036854775807u), 1, 9223372036854775807);
    check_opt_i64(alder_fn_to_i64_checked_u64_1(9223372036854775808u), 0, 0);
    check_opt_i64(alder_fn_to_i64_checked_u64_1(18446744073709551615u), 0, 0);

    /* checked narrowing of u64 into i8: the boundary sits between 127 and
     * 128, and every value above it is outside. */
    check_opt_i8(alder_fn_to_i8_checked_2(0u), 1, 0);
    check_opt_i8(alder_fn_to_i8_checked_2(127u), 1, 127);
    check_opt_i8(alder_fn_to_i8_checked_2(128u), 0, 0);
    check_opt_i8(alder_fn_to_i8_checked_2(18446744073709551615u), 0, 0);

    /* checked sign-changing conversion of i32 into u8: negatives are out,
     * 255 and 256 straddle the boundary. */
    check_opt_u8(alder_fn_to_u8_checked_3(-1), 0, 0);
    check_opt_u8(alder_fn_to_u8_checked_3(0), 1, 0);
    check_opt_u8(alder_fn_to_u8_checked_3(255), 1, 255);
    check_opt_u8(alder_fn_to_u8_checked_3(256), 0, 0);
    check_opt_u8(alder_fn_to_u8_checked_3(-2147483648), 0, 0);
    check_opt_u8(alder_fn_to_u8_checked_3(2147483647), 0, 0);

    /* checked widening of i32 into u64 accepts exactly the non-negative
     * values. */
    check_opt_u64(alder_fn_to_u64_checked_4(-1), 0, 0);
    check_opt_u64(alder_fn_to_u64_checked_4(0), 1, 0);
    check_opt_u64(alder_fn_to_u64_checked_4(2147483647), 1, 2147483647);

    /* wrapping keeps the low bits, in two's complement at the target
     * width. */
    CHECK(alder_fn_wrap_u8_5(255u) == 255);
    CHECK(alder_fn_wrap_u8_5(256u) == 0);
    CHECK(alder_fn_wrap_u8_5(18446744073709551615u) == 255);
    CHECK(alder_fn_wrap_i8_6(127u) == 127);
    CHECK(alder_fn_wrap_i8_6(128u) == -128);
    CHECK(alder_fn_wrap_i8_6(255u) == -1);
    CHECK(alder_fn_wrap_i8_6(256u) == 0);
    CHECK(alder_fn_wrap_i8_6(18446744073709551615u) == -1);
    CHECK(alder_fn_wrap_u32_7(-1) == 4294967295u);
    CHECK(alder_fn_wrap_u32_7(4294967296) == 0);
    CHECK(alder_fn_wrap_u32_7(2147483648) == 2147483648u);
    CHECK(alder_fn_wrap_i32_8(2147483647u) == 2147483647);
    CHECK(alder_fn_wrap_i32_8(2147483648u) == -2147483647 - 1);
    CHECK(alder_fn_wrap_i32_8(4294967295u) == -1);

    if (failures != 0) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    return 0;
}
