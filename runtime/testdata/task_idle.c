/* Idle reporting: a live task parked with no wakeup registration and no timer
 * must reach on_idle with the blocked set. */
#include "alder.h"

#include <stdbool.h>
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

typedef struct {
    uint32_t state;
} IdleFrame;

static AlderStepStatus idle_step(AlderTask *task, AlderDomain *results,
                                 void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    if (alder_task_cancelled()) {
        return ALDER_STEP_CANCELLED;
    }
    alder_task_wait_reason(ALDER_WAIT_TASK);
    return ALDER_STEP_PARK;
}

static size_t seen_count = 0;
static uint64_t seen_id = 0;
static uint32_t seen_reason = 0;

static void on_idle(void *context, const AlderBlockedTask *blocked, size_t count) {
    (void)context;
    seen_count = count;
    if (count != 0) {
        seen_id = blocked[0].task_id;
        seen_reason = blocked[0].wait_reason;
    }
}

int main(void) {
    AlderDomain domain;
    CHECK(alder_domain_init(&domain, NULL));
    void *frame = alder_domain_alloc(&domain, sizeof(IdleFrame), _Alignof(max_align_t));
    CHECK(frame != NULL);
    memset(frame, 0, sizeof(IdleFrame));
    AlderTask *task = alder_task_create(UINT64_C(0), idle_step, frame, &domain);
    CHECK(task != NULL);
    uint64_t id = alder_task_handle(task);
    alder_task_start(task);

    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    hooks.context = NULL;
    hooks.on_idle = on_idle;
    CHECK(!alder_executor_run(&hooks));
    CHECK(seen_count == 1);
    CHECK(seen_id == id);
    CHECK(seen_reason == ALDER_WAIT_TASK);

    alder_task_cancel(id);
    CHECK(alder_executor_run(NULL));
    alder_task_release(id);
    alder_domain_destroy(&domain);
    return failures == 0 ? 0 : 1;
}
