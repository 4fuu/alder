/* Driver for float.mir: the plain IEEE-754 float arithmetic and comparison
 * operations. Division goes through the runtime helper, so a zero divisor
 * yields the IEEE signed infinity (sign XOR of the operands) or NaN for
 * 0/0 instead of the undefined plain C11 division; comparisons are IEEE
 * (NaN is unordered, signed zeros compare equal). */
#include "gen.c"

#include <float.h>
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

int main(void) {
    /* exact sums, differences, products, quotients. */
    CHECK(alder_fn_f64_add_0(0.5, 0.25) == 0.75);
    CHECK(alder_fn_f64_sub_1(2.5, 0.5) == 2.0);
    CHECK(alder_fn_f64_mul_2(1.5, 2.0) == 3.0);
    CHECK(alder_fn_f64_div_3(1.0, 4.0) == 0.25);

    /* zero divisor: +Inf, -Inf by sign XOR, NaN for 0/0. */
    CHECK(alder_fn_f64_div_3(1.0, 0.0) == INFINITY);
    CHECK(alder_fn_f64_div_3(1.0, -0.0) == -INFINITY);
    CHECK(alder_fn_f64_div_3(-1.0, 0.0) == -INFINITY);
    CHECK(alder_fn_f64_div_3(-1.0, -0.0) == INFINITY);
    CHECK(alder_fn_f64_div_3(0.0, 0.0) != alder_fn_f64_div_3(0.0, 0.0));
    CHECK(isnan(alder_fn_f64_div_3(0.0, 0.0)));
    /* Inf survives a finite divisor. */
    CHECK(alder_fn_f64_div_3(INFINITY, 2.0) == INFINITY);
    /* overflow to +Inf, under the finite maximum. */
    CHECK(alder_fn_f64_mul_2(DBL_MAX, 10.0) == INFINITY);

    /* the F32 division path selects the single-precision helper. */
    CHECK(alder_fn_f32_div_4(1.0f, 0.0f) == INFINITY);
    CHECK(alder_fn_f32_div_4(1.0f, -0.0f) == -INFINITY);
    CHECK(alder_fn_f32_add_5(0.5f, 0.25f) == 0.75f);

    /* IEEE comparisons: finite operands. */
    CHECK(alder_fn_f64_eq_6(1.5, 1.5));
    CHECK(!alder_fn_f64_eq_6(1.5, 2.5));
    CHECK(alder_fn_f64_ne_7(1.5, 2.5));
    CHECK(alder_fn_f64_lt_8(1.5, 2.5));
    CHECK(!alder_fn_f64_lt_8(2.5, 1.5));
    CHECK(alder_fn_f64_le_9(2.5, 2.5));
    CHECK(alder_fn_f64_gt_10(2.5, 1.5));
    CHECK(alder_fn_f64_ge_11(2.5, 2.5));
    /* signed zeros compare equal. */
    CHECK(alder_fn_f64_eq_6(0.0, -0.0));
    /* NaN is unordered: == and the orderings are false, != is true. */
    {
        double nan = alder_fn_f64_div_3(0.0, 0.0);
        CHECK(!alder_fn_f64_eq_6(nan, nan));
        CHECK(alder_fn_f64_ne_7(nan, nan));
        CHECK(!alder_fn_f64_lt_8(nan, 1.0));
        CHECK(!alder_fn_f64_le_9(nan, 1.0));
        CHECK(!alder_fn_f64_gt_10(nan, 1.0));
        CHECK(!alder_fn_f64_ge_11(nan, 1.0));
        CHECK(!alder_fn_f64_lt_8(1.0, nan));
        CHECK(!alder_fn_f64_eq_6(1.0, nan));
        CHECK(alder_fn_f64_ne_7(1.0, nan));
    }

    if (failures != 0) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    return 0;
}
