#include "gen.c"
#include <stdio.h>

static int64_t g_value = 0;

uint64_t magic(uint64_t v) {
    return v + 2;
}

void store(int64_t v) {
    g_value = v;
}

int64_t load(void) {
    return g_value;
}

int main(void) {
    return (int)alder_fn_main_IDX();
}
