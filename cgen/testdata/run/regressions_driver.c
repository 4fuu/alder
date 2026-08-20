#include "gen.c"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); failures++; } } while (0)

int main(void) {
    AlderSlice empty = {NULL, 0};
    AlderSlice invalid = {NULL, 1};
    const uint8_t expected_nul[] = {'a', 0, '7', 'z', 128, 255};
    const uint8_t expected_octal[] = {'b', 1, '8', 'z'};
    CHECK(alder_fn_swap_loop_0(0) == 10);
    CHECK(alder_fn_swap_loop_0(1) == 17);
    CHECK(alder_fn_swap_loop_0(2) == 10);
    CHECK(alder_fn_range_1(empty, 0) == 0u);
    CHECK(alder_fn_range_1(invalid, 1) == 0u);
    AlderBytes nul = alder_fn_nul_bytes_2();
    AlderBytes octal = alder_fn_octal_bytes_3();
	AlderBytes copied = alder_fn_copy_bytes_4(nul);
	AlderBytes empty_bytes = alder_fn_empty_bytes_5();
    CHECK(nul.len == sizeof expected_nul);
    CHECK(octal.len == sizeof expected_octal);
    CHECK(memcmp(nul.data, expected_nul, sizeof expected_nul) == 0);
    CHECK(memcmp(octal.data, expected_octal, sizeof expected_octal) == 0);
	CHECK(copied.data == nul.data && copied.len == nul.len);
	CHECK(empty_bytes.data != NULL && empty_bytes.len == 0u);
    return failures != 0;
}
