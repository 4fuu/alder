/* Driver for table.mir: generational table inserts, views, mutation through
 * a mut view, removal, and stale-id rejection. */
#include "gen.c"

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

int main(void) {
    AsterDomain root = {0};
    CHECK(aster_domain_init(&root, NULL));

    /* Insert 7 and 3; read 7, write it into 3's slot through the mut view,
     * remove 7's slot, verify the stale id is gone, and read 3 back. */
    CHECK(aster_fn_table_ops_0(&root, 7, 3) == 7);
    CHECK(aster_fn_table_ops_0(&root, -5, 100) == -5);

    aster_domain_destroy(&root);
    CHECK(aster_runtime_live_allocations() == 0u);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
