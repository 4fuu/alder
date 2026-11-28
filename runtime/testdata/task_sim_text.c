/* SimIo deadlock text shape: the header-only idle hook panics with the fixed
 * first line and one blocked-task line per live blocked task. */
#include "std/c/sim_shim.h"

#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t state;
} IdleFrame;

static AlderStepStatus idle_step(AlderTask *task, AlderDomain *results,
                                 void *frame, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame;
    (void)frame_domain;
    return ALDER_STEP_PARK;
}

int main(void) {
    AlderDomain domain;
    if (!alder_domain_init(&domain, NULL)) {
        return 2;
    }
    void *frame = alder_domain_alloc(&domain, sizeof(IdleFrame), _Alignof(max_align_t));
    if (frame == NULL) {
        return 2;
    }
    memset(frame, 0, sizeof(IdleFrame));
    AlderTask *task = alder_task_create(UINT64_C(0), idle_step, frame, &domain);
    if (task == NULL) {
        return 2;
    }
    AlderBlockedTask blocked[1];
    blocked[0].task_id = alder_task_handle(task);
    blocked[0].wait_reason = ALDER_WAIT_TASK;
    task_sim_idle(NULL, blocked, 1);
    return 3;
}
