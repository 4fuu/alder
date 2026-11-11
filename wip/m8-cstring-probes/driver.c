#include <stdio.h>
extern int alder_program_entry(int *context);
extern long alder_runtime_live_allocations(void);
int main(void) {
    int context = 0;
    long before = alder_runtime_live_allocations();
    int rc = (int)alder_program_entry(&context);
    long after = alder_runtime_live_allocations();
    fprintf(stderr, "rc=%d live_before=%ld live_after=%ld\n", rc, before, after);
    if (rc != 0) { return rc; }
    if (before != after) { return 2; }
    return 0;
}
