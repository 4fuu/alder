#include "gen.c"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); failures++; } } while (0)

int main(void) {
    AsterSlice empty = {NULL, 0};
    AsterSlice invalid = {NULL, 1};
    const uint8_t expected_nul[] = {'a', 0, '7', 'z'};
    const uint8_t expected_octal[] = {'b', 1, '8', 'z'};
    CHECK(aster_fn_swap_loop_0(0) == 10);
    CHECK(aster_fn_swap_loop_0(1) == 17);
    CHECK(aster_fn_swap_loop_0(2) == 10);
    CHECK(aster_fn_range_1(empty, 0) == 0u);
    CHECK(aster_fn_range_1(invalid, 1) == 0u);
    AsterSlice nul = aster_fn_nul_bytes_2();
    AsterSlice octal = aster_fn_octal_bytes_3();
    CHECK(nul.len == sizeof expected_nul);
    CHECK(octal.len == sizeof expected_octal);
    CHECK(memcmp(nul.data, expected_nul, sizeof expected_nul) == 0);
    CHECK(memcmp(octal.data, expected_octal, sizeof expected_octal) == 0);
    return failures != 0;
}
