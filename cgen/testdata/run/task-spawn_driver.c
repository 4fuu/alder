/* Driver for task-spawn.mir: call the spawner step directly, run the spawned
 * leaf task to completion through the real task runtime, read its frame
 * result, then release the task and destroy the spawner-owned domain. */
#include "gen.c"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

int main(void) {
    AlderDomain root = {0};
    CHECK(alder_domain_init(&root, NULL));

    /* AlderTy16 is @__alder_step.frame.spawner and AlderTy12 is the status
     * enum in this fixture's declaration order. Fields: state, p0, p1, x0,
     * y0, out. */
    AlderTy16 *spawner =
        alder_domain_alloc(&root, sizeof *spawner, _Alignof(max_align_t));
    CHECK(spawner != NULL);
    if (spawner == NULL) {
        return 1;
    }
    memset(spawner, 0, sizeof *spawner);
    spawner->alder_f0.alder_tag = 0;          /* entry */
    spawner->alder_f1 = UINT64_C(41);         /* p0 seed */
    spawner->alder_f2 = UINT64_C(0xC0FFEE);   /* p1 group */

    AlderTy12 status = alder_fn___alder_step_run_spawner_1(
        &root, (AlderSlice){spawner, UINT64_C(1)}, &root);
    CHECK(status.alder_tag == 0); /* done */
    CHECK(spawner->alder_f5 != 0); /* out holds the child task id */

    CHECK(alder_executor_run(NULL));

    AlderTy14 *leaf = (AlderTy14 *)spawner->alder_f3.data;
    CHECK(leaf != NULL);
    if (leaf != NULL) {
        CHECK(leaf->alder_f2 == UINT64_C(41)); /* out */
    }

    alder_task_release(spawner->alder_f5);
    alder_domain_destroy((AlderDomain *)spawner->alder_f4);
    alder_domain_destroy(&root);
    CHECK(alder_runtime_live_allocations() == 0);
    return failures == 0 ? 0 : 1;
}
