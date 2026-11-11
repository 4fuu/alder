/* Driver for bitwise.mir: the total & | ^ ~ family over unsigned and signed
 * widths. The generated C applies the operators to the unsigned type of the
 * operand width, so every bit pattern is defined; signed results transfer the
 * pattern by memcpy. */
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
    CHECK(alder_fn_and_u8_0(0xABU, 0x0FU) == 0x0BU);
    CHECK(alder_fn_or_u8_1(0x80U, 0x01U) == 0x81U);
    CHECK(alder_fn_xor_u8_2(0xFFU, 0x0FU) == 0xF0U);
    CHECK(alder_fn_not_u8_3(0xF0U) == 0x0FU);

    CHECK(alder_fn_and_i8_4(-1, 15) == 15);
    CHECK(alder_fn_and_i8_4(-128, 127) == 0);
    CHECK(alder_fn_not_i8_5(-2) == 1);
    CHECK(alder_fn_not_i8_5(127) == -128);

    CHECK(alder_fn_and_u64_6(UINT64_MAX, 0xFFU) == 0xFFU);
    CHECK(alder_fn_not_u64_7(0) == UINT64_MAX);
    CHECK(alder_fn_not_u64_7(UINT64_MAX) == 0);

    CHECK(alder_fn_and_i64_8(-1, 255) == 255);
    CHECK(alder_fn_not_i64_9(INT64_MIN) == INT64_MAX);
    CHECK(alder_fn_not_i64_9(-1) == 0);
    CHECK(alder_fn_or_i64_10(INT64_MIN, 1) == INT64_MIN + 1);
    CHECK(alder_fn_xor_i64_11(-1, 0) == -1);
    CHECK(alder_fn_xor_i64_11(-1, -1) == 0);

    if (failures != 0) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    return 0;
}
