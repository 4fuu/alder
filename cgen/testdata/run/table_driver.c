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

    /* Pass the table through an ordinary identity helper, grow it past its
     * initial eight slots, mutate through the returned identity, and observe
     * the ninth insertion from the caller's continued table identity. */
    CHECK(aster_fn_repeat_table_site_1(&root, 3) == 0);
    CHECK(aster_fn_table_ops_2(&root, 7, 3) == 3);
    CHECK(aster_fn_table_ops_2(&root, -5, 100) == 100);

    aster_domain_destroy(&root);
    CHECK(aster_runtime_live_allocations() == 0u);

    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
