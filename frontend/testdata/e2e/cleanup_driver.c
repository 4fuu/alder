#include "gen.c"
#include <stdio.h>

static int64_t g_count = 0;

void counter(int64_t v) {
    g_count += v;
}

int64_t read_counter(void) {
    return g_count;
}

int main(void) {
    int result = (int)aster_fn_main_IDX();
    if (g_count != 10) { return 99; }
    return result;
}
