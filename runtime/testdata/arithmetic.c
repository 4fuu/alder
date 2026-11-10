/* Boundary tests for every checked arithmetic helper and the defined
 * float-to-integer conversions. */
#include "alder.h"

#include <math.h>
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

#define CHECK_OK(op, a, b, want)                                         \
    do {                                                                   \
        int64_t got = 0;                                                   \
        CHECK(alder_i64_##op((a), (b), &got));                             \
        CHECK(got == (want));                                              \
    } while (0)

#define CHECK_FAIL(op, a, b)                                               \
    do {                                                                   \
        int64_t got = 12345;                                               \
        CHECK(!alder_i64_##op((a), (b), &got));                            \
        CHECK(got == 12345); /* output untouched on failure */             \
    } while (0)

#define CHECK_OK_U(op, a, b, want)                                         \
    do {                                                                   \
        uint64_t got = 0;                                                  \
        CHECK(alder_u64_##op((a), (b), &got));                             \
        CHECK(got == (want));                                              \
    } while (0)

#define CHECK_FAIL_U(op, a, b)                                             \
    do {                                                                   \
        uint64_t got = 12345;                                              \
        CHECK(!alder_u64_##op((a), (b), &got));                            \
        CHECK(got == 12345);                                               \
    } while (0)

#define CHECK_I64(op, a, b, want)                                          \
    do {                                                                   \
        CHECK(alder_i64_##op((a), (b)) == (want));                         \
    } while (0)

#define CHECK_U64(op, a, b, want)                                          \
    do {                                                                   \
        CHECK(alder_u64_##op((a), (b)) == (want));                         \
    } while (0)

static void test_i64_add(void) {
    CHECK_OK(add_checked, 1, 2, 3);
    CHECK_OK(add_checked, INT64_MAX, 0, INT64_MAX);
    CHECK_OK(add_checked, INT64_MIN, 0, INT64_MIN);
    CHECK_OK(add_checked, -1, 1, 0);
    CHECK_OK(add_checked, INT64_MAX - 1, 1, INT64_MAX);
    CHECK_OK(add_checked, INT64_MIN + 1, -1, INT64_MIN);
    CHECK_FAIL(add_checked, INT64_MAX, 1);
    CHECK_FAIL(add_checked, INT64_MIN, -1);
    CHECK_FAIL(add_checked, INT64_MAX, INT64_MAX);
    CHECK_FAIL(add_checked, INT64_MIN, INT64_MIN);
}

static void test_i64_sub(void) {
    CHECK_OK(sub_checked, 5, 2, 3);
    CHECK_OK(sub_checked, INT64_MIN, 0, INT64_MIN);
    CHECK_OK(sub_checked, INT64_MIN, -1, INT64_MIN + 1);
    CHECK_FAIL(sub_checked, INT64_MAX, -1);
    CHECK_FAIL(sub_checked, INT64_MIN, 1); /* INT64_MIN - 1 overflows */
    CHECK_FAIL(sub_checked, 0, INT64_MIN); /* 0 - INT64_MIN overflows */
    CHECK_OK(sub_checked, 0, INT64_MAX, -INT64_MAX);
    CHECK_OK(sub_checked, -5, -5, 0);
}

static void test_i64_mul(void) {
    CHECK_OK(mul_checked, 3, 4, 12);
    CHECK_OK(mul_checked, 0, INT64_MAX, 0);
    CHECK_OK(mul_checked, 0, INT64_MIN, 0);
    CHECK_OK(mul_checked, -1, 1, -1);
    CHECK_OK(mul_checked, INT64_MAX, 1, INT64_MAX);
    CHECK_OK(mul_checked, INT64_MIN, 1, INT64_MIN);
    CHECK_OK(mul_checked, 3037000499LL, 3037000499LL, 9223372030926249001LL);
    CHECK_FAIL(mul_checked, INT64_MIN, -1);
    CHECK_FAIL(mul_checked, -1, INT64_MIN);
    CHECK_FAIL(mul_checked, INT64_MAX, 2);
    CHECK_FAIL(mul_checked, INT64_MIN, 2);
    CHECK_FAIL(mul_checked, 3037000500LL, 3037000500LL); /* just over 2^63 */
}

static void test_i64_div(void) {
    CHECK_OK(div_checked, 10, 2, 5);
    CHECK_OK(div_checked, -10, 3, -3); /* truncation toward zero */
    CHECK_OK(div_checked, INT64_MIN, 1, INT64_MIN);
    CHECK_OK(div_checked, INT64_MAX, -1, -INT64_MAX);
    CHECK_FAIL(div_checked, 1, 0);
    CHECK_FAIL(div_checked, 0, 0);
    CHECK_FAIL(div_checked, INT64_MIN, -1);
}

static void test_i64_shifts(void) {
    CHECK_OK(shl_checked, 1, 0, 1);
    CHECK_OK(shl_checked, 1, 63, INT64_MIN);
    CHECK_OK(shl_checked, INT64_MIN, 1, 0);
    CHECK_OK(shl_checked, -1, 1, -2);
    CHECK_FAIL(shl_checked, 1, 64);
    CHECK_FAIL(shl_checked, 1, -1);
    CHECK_OK(shr_checked, 8, 1, 4);
    CHECK_OK(shr_checked, -8, 1, -4); /* arithmetic */
    CHECK_OK(shr_checked, INT64_MIN, 63, -1);
    CHECK_OK(shr_checked, -1, 63, -1);
    CHECK_OK(shr_checked, 1, 63, 0);
    CHECK_FAIL(shr_checked, 1, 64);
    CHECK_FAIL(shr_checked, 1, -1);
}

static void test_u64_ops(void) {
    CHECK_OK_U(add_checked, 1, 2, 3);
    CHECK_OK_U(add_checked, UINT64_MAX, 0, UINT64_MAX);
    CHECK_FAIL_U(add_checked, UINT64_MAX, 1);
    CHECK_OK_U(sub_checked, 5, 2, 3);
    CHECK_OK_U(sub_checked, 0, 0, 0);
    CHECK_FAIL_U(sub_checked, 0, 1);
    CHECK_OK_U(mul_checked, 0, UINT64_MAX, 0);
    CHECK_OK_U(mul_checked, 1, UINT64_MAX, UINT64_MAX);
    CHECK_OK_U(mul_checked, 4294967295u, 4294967295u, 18446744065119617025ull);
    CHECK_FAIL_U(mul_checked, 4294967296u, 4294967296u); /* 2^64 wraps */
    CHECK_FAIL_U(mul_checked, UINT64_MAX, 2);
    CHECK_OK_U(div_checked, 10, 2, 5);
    CHECK_OK_U(div_checked, 0, 1, 0);
    CHECK_FAIL_U(div_checked, 1, 0);
    CHECK_OK_U(shl_checked, 1, 63, 0x8000000000000000ull);
    CHECK_OK_U(shl_checked, 1, 63, 0x8000000000000000ull);
    CHECK_FAIL_U(shl_checked, 1, 64);
    CHECK_OK_U(shr_checked, 0x8000000000000000ull, 63, 1); /* logical */
    CHECK_OK_U(shr_checked, 0x8000000000000000ull, 0, 0x8000000000000000ull);
    CHECK_FAIL_U(shr_checked, 1, 64);
}

static void test_i64_saturating(void) {
    CHECK_I64(add_saturating, 1, 2, 3);
    CHECK_I64(add_saturating, INT64_MAX, 1, INT64_MAX);
    CHECK_I64(add_saturating, INT64_MIN, -1, INT64_MIN);
    CHECK_I64(add_saturating, INT64_MAX, INT64_MAX, INT64_MAX);
    CHECK_I64(add_saturating, INT64_MIN, INT64_MIN, INT64_MIN);
    CHECK_I64(sub_saturating, 5, 2, 3);
    CHECK_I64(sub_saturating, INT64_MIN, 1, INT64_MIN);
    CHECK_I64(sub_saturating, INT64_MAX, -1, INT64_MAX);
    CHECK_I64(sub_saturating, 0, INT64_MIN, INT64_MAX);
    CHECK_I64(mul_saturating, 3, 4, 12);
    CHECK_I64(mul_saturating, -3, 4, -12);
    CHECK_I64(mul_saturating, INT64_MIN, -1, INT64_MAX);
    CHECK_I64(mul_saturating, -1, INT64_MIN, INT64_MAX);
    CHECK_I64(mul_saturating, INT64_MIN, 2, INT64_MIN);
    CHECK_I64(mul_saturating, INT64_MAX, 2, INT64_MAX);
    CHECK_I64(mul_saturating, 3037000500LL, 3037000500LL, INT64_MAX);
    CHECK_I64(mul_saturating, -3037000500LL, 3037000500LL, INT64_MIN);
    CHECK_I64(mul_saturating, 0, INT64_MIN, 0);
}

static void test_u64_saturating(void) {
    CHECK_U64(add_saturating, 1, 2, 3);
    CHECK_U64(add_saturating, UINT64_MAX, 1, UINT64_MAX);
    CHECK_U64(sub_saturating, 5, 2, 3);
    CHECK_U64(sub_saturating, 0, 1, 0);
    CHECK_U64(sub_saturating, UINT64_MAX, UINT64_MAX, 0);
    CHECK_U64(mul_saturating, 3, 4, 12);
    CHECK_U64(mul_saturating, UINT64_MAX, 2, UINT64_MAX);
    CHECK_U64(mul_saturating, 4294967296ull, 4294967296ull, UINT64_MAX);
    CHECK_U64(mul_saturating, 0, UINT64_MAX, 0);
}

static void test_i64_wrapping(void) {
    CHECK_I64(add_wrapping, 1, 2, 3);
    CHECK_I64(add_wrapping, INT64_MAX, 1, INT64_MIN);
    CHECK_I64(add_wrapping, INT64_MIN, -1, INT64_MAX);
    CHECK_I64(sub_wrapping, 5, 2, 3);
    CHECK_I64(sub_wrapping, INT64_MIN, 1, INT64_MAX);
    CHECK_I64(sub_wrapping, INT64_MAX, -1, INT64_MIN);
    CHECK_I64(mul_wrapping, 3, 4, 12);
    CHECK_I64(mul_wrapping, INT64_MIN, -1, INT64_MIN);
    CHECK_I64(mul_wrapping, -1, 1, -1);
    CHECK_I64(mul_wrapping, 4611686018427387904LL, 4, 0); /* 2^62 * 4 wraps */
    CHECK_I64(mul_wrapping, 0, INT64_MIN, 0);
}

static void test_u64_wrapping(void) {
    CHECK_U64(add_wrapping, 1, 2, 3);
    CHECK_U64(add_wrapping, UINT64_MAX, 1, 0);
    CHECK_U64(sub_wrapping, 5, 2, 3);
    CHECK_U64(sub_wrapping, 0, 1, UINT64_MAX);
    CHECK_U64(mul_wrapping, 3, 4, 12);
    CHECK_U64(mul_wrapping, 4294967296ull, 4294967296ull, 0);
    CHECK_U64(mul_wrapping, UINT64_MAX, UINT64_MAX, 1);
}

static void test_float_conversions(void) {
    int64_t i64 = 0;
    uint64_t u64 = 0;
    CHECK(alder_i64_from_f64(0.0, &i64) && i64 == 0);
    CHECK(alder_i64_from_f64(-2.5, &i64) && i64 == -2); /* truncation */
    CHECK(alder_i64_from_f64(2.9, &i64) && i64 == 2);
    CHECK(alder_i64_from_f64(-9223372036854775808.0, &i64) && i64 == INT64_MIN);
    CHECK(alder_i64_from_f64(9223372036854773760.0, &i64)); /* 2^63 - 2048 */
    CHECK(!alder_i64_from_f64(9223372036854775808.0, &i64));   /* >= 2^63 */
    CHECK(!alder_i64_from_f64(-9223372036854777856.0, &i64));  /* < -2^63 */
#ifdef INFINITY
    CHECK(!alder_i64_from_f64(INFINITY, &i64));
    CHECK(!alder_i64_from_f64(-INFINITY, &i64));
#endif
#ifdef NAN
    CHECK(!alder_i64_from_f64(NAN, &i64));
#endif

    CHECK(alder_u64_from_f64(0.0, &u64) && u64 == 0);
    CHECK(alder_u64_from_f64(3.9, &u64) && u64 == 3);
    CHECK(alder_u64_from_f64(18446744073709549568.0, &u64)); /* < 2^64 */
    CHECK(!alder_u64_from_f64(-1.0, &u64));
    CHECK(!alder_u64_from_f64(18446744073709551616.0, &u64)); /* >= 2^64 */
#ifdef NAN
    CHECK(!alder_u64_from_f64(NAN, &u64));
#endif
    CHECK(!alder_i64_from_f64(1.0, NULL));
    CHECK(!alder_u64_from_f64(1.0, NULL));
}

static void test_null_outputs(void) {
    CHECK(!alder_i64_add_checked(1, 2, NULL));
    CHECK(!alder_i64_sub_checked(1, 2, NULL));
    CHECK(!alder_i64_mul_checked(1, 2, NULL));
    CHECK(!alder_i64_div_checked(1, 2, NULL));
    CHECK(!alder_i64_shl_checked(1, 2, NULL));
    CHECK(!alder_i64_shr_checked(1, 2, NULL));
    CHECK(!alder_u64_add_checked(1, 2, NULL));
    CHECK(!alder_u64_sub_checked(1, 2, NULL));
    CHECK(!alder_u64_mul_checked(1, 2, NULL));
    CHECK(!alder_u64_div_checked(1, 2, NULL));
    CHECK(!alder_u64_shl_checked(1, 2, NULL));
    CHECK(!alder_u64_shr_checked(1, 2, NULL));
}

int main(void) {
    test_i64_add();
    test_i64_sub();
    test_i64_mul();
    test_i64_div();
    test_i64_shifts();
    test_u64_ops();
    test_i64_saturating();
    test_u64_saturating();
    test_i64_wrapping();
    test_u64_wrapping();
    test_float_conversions();
    test_null_outputs();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
