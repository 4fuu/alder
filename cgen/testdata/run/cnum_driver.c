/* Driver for cnum.mir: the C-boundary conversion ops. The checked integer
 * forms keep in-range values and yield the empty option exactly outside the
 * target range, probed at the limit macros (INT8_MIN/MAX, INT64_MAX); the
 * wrapping forms keep the low bits at the target width; the cast forms move
 * value-preserving pairs; the checked float narrowing accepts exactly the
 * finite magnitudes float can represent. */
#include "gen.c"

#include <math.h>
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

static void check_opt_i8(AlderTy15 opt, int want_some, int8_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_i64(AlderTy17 opt, int want_some, int64_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_u8(AlderTy19 opt, int want_some, uint8_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_f32(AlderTy24 opt, int want_some, float want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

static void check_opt_u32(AlderTy26 opt, int want_some, uint32_t want) {
    CHECK(opt.alder_tag == (uint32_t)(want_some ? 1 : 0));
    if (want_some != 0) {
        CHECK(opt.alder_u.alder_p1 == want);
    }
}

int main(void) {
    /* u32 into c_size is total on every target Alder supports, so the
     * checked form is statically always some. */
    AlderTy13 wide = alder_fn_try_u32_size_0(0u);
    CHECK(wide.alder_tag == 1);
    CHECK(wide.alder_u.alder_p1 == 0);
    wide = alder_fn_try_u32_size_0(4294967295u);
    CHECK(wide.alder_tag == 1);
    CHECK(wide.alder_u.alder_p1 == 4294967295u);

    /* c_int into i8: the limits straddle exactly. */
    check_opt_i8(alder_fn_try_cint_i8_1(-129), 0, 0);
    check_opt_i8(alder_fn_try_cint_i8_1(-128), 1, -128);
    check_opt_i8(alder_fn_try_cint_i8_1(0), 1, 0);
    check_opt_i8(alder_fn_try_cint_i8_1(127), 1, 127);
    check_opt_i8(alder_fn_try_cint_i8_1(128), 0, 0);
    check_opt_i8(alder_fn_try_cint_i8_1(-2147483647 - 1), 0, 0);
    check_opt_i8(alder_fn_try_cint_i8_1(2147483647), 0, 0);

    /* c_ulong into i64: UINT64_MAX above INT64_MAX is out, INT64_MAX itself
     * is the last accepted value. */
    check_opt_i64(alder_fn_try_culong_i64_2(0uL), 1, 0);
    check_opt_i64(alder_fn_try_culong_i64_2(9223372036854775807uL), 1, 9223372036854775807LL);
    check_opt_i64(alder_fn_try_culong_i64_2(9223372036854775808uL), 0, 0);
    check_opt_i64(alder_fn_try_culong_i64_2(18446744073709551615uL), 0, 0);

    /* c_char's signedness is target-dependent, so the check stays runtime:
     * non-negative values pass, negative ones (any byte above 127 where char
     * is signed) are out. */
    check_opt_u8(alder_fn_try_cchar_u8_3((char)0), 1, 0);
    check_opt_u8(alder_fn_try_cchar_u8_3((char)65), 1, 65);
    check_opt_u8(alder_fn_try_cchar_u8_3((char)127), 1, 127);
    check_opt_u8(alder_fn_try_cchar_u8_3((char)-1), 0, 0);

    /* wrapping keeps the low bits at the target width. */
    CHECK(alder_fn_wrap_i16_cushort_4(-1) == 65535);
    CHECK(alder_fn_wrap_i16_cushort_4(258) == 258);
    CHECK(alder_fn_wrap_i16_cushort_4(-32768) == 32768);
    CHECK(alder_fn_wrap_i16_cushort_4(32767) == 32767);
    CHECK(alder_fn_wrap_i32_cschar_5(127) == 127);
    CHECK(alder_fn_wrap_i32_cschar_5(128) == -128);
    CHECK(alder_fn_wrap_i32_cschar_5(200) == -56);
    CHECK(alder_fn_wrap_i32_cschar_5(-1) == -1);

    /* value-preserving casts are plain moves. */
    CHECK(alder_fn_cast_u32_culong_6(0u) == 0uL);
    CHECK(alder_fn_cast_u32_culong_6(4294967295u) == 4294967295uL);
    CHECK(alder_fn_cast_f32_cfloat_7(0.5f) == 0.5f);
    CHECK(alder_fn_cast_cdouble_f64_8(3.25) == 3.25);

    /* f64 into c_float: exact values stay, NaN and magnitudes beyond
     * float's range yield none. */
    check_opt_f32(alder_fn_try_f64_cfloat_9(1.5), 1, 1.5f);
    check_opt_f32(alder_fn_try_f64_cfloat_9(-2.0), 1, -2.0f);
    check_opt_f32(alder_fn_try_f64_cfloat_9(1e300), 0, 0);
    check_opt_f32(alder_fn_try_f64_cfloat_9(-1e300), 0, 0);
    check_opt_f32(alder_fn_try_f64_cfloat_9((double)NAN), 0, 0);
    check_opt_f32(alder_fn_try_f64_cfloat_9(-(double)INFINITY), 0, 0);

    /* c_llong into c_uint: negatives are out, UINT32_MAX is the last
     * accepted value. */
    check_opt_u32(alder_fn_try_cllong_cuint_10(-1), 0, 0);
    check_opt_u32(alder_fn_try_cllong_cuint_10(0), 1, 0);
    check_opt_u32(alder_fn_try_cllong_cuint_10(4294967295), 1, 4294967295u);
    check_opt_u32(alder_fn_try_cllong_cuint_10(4294967296), 0, 0);

    /* c_long into c_ulong: the only rejection is the negative range, since
     * every non-negative long fits. */
    {
        AlderTy27 up = alder_fn_try_clong_culong_11(-1);
        CHECK(up.alder_tag == 0);
        up = alder_fn_try_clong_culong_11(9223372036854775807L);
        CHECK(up.alder_tag == 1);
        CHECK(up.alder_u.alder_p1 == 9223372036854775807uL);
    }

    if (failures != 0) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    return 0;
}
