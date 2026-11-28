/*
 * Toolchain-owned C binding shims for the std.task and std.test SimIo
 * surfaces.
 *
 * The task runtime entries use the reserved alder_ namespace, so Alder source
 * cannot bind them directly. This header wraps each entry in a static inline
 * function with a binding-safe name. Header-only static inline definitions add
 * no link symbol.
 *
 * SimIo's idle diagnostic is installed as the executor's default hook record:
 * a program entry that calls alder_executor_run(NULL) then still receives the
 * deterministic deadlock report. The report text is fixed by the std.test
 * snapshot and is not data.
 */
#ifndef ALDER_TASK_SHIM_H
#define ALDER_TASK_SHIM_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "alder.h"
#include "alder_panic.h"

static inline unsigned long long task_group_new(void) { return (unsigned long long)alder_group_create(); }

static inline void task_group_cancel(unsigned long long group) {
    alder_group_cancel(group);
}

static inline unsigned long long task_group_next(unsigned long long group) {
    return (unsigned long long)alder_group_next(group);
}

static inline void task_group_release(unsigned long long group) {
    alder_group_release(group);
}

static inline bool task_await(unsigned long long child) {
    return alder_task_await(child);
}

/* Register the await and set the current latch when the child is already
 * complete, so the following park marker is a no-op instead of a lost
 * wakeup. */
static inline int task_await_parkable(unsigned long long child) {
    bool ready = alder_task_await(child);
    if (ready) {
        alder_wakeup_signal(alder_task_wakeup());
    }
    return ready ? 1 : 0;
}

static inline void task_cancel(unsigned long long child) {
    alder_task_cancel(child);
}

static inline void task_release_spawned(unsigned long long child) {
    alder_task_release_spawned(child);
}

static inline void task_own_domain(unsigned long long child) {
    alder_task_own_domain(child);
}

static inline AlderSlice task_await_result_slice(unsigned long long offset) {
    return alder_task_await_result_slice((uint64_t)offset);
}

static inline int task_awaited_cancelled(void) {
    return alder_task_awaited_cancelled() ? 1 : 0;
}

static inline void task_release_awaited(void) {
    alder_task_release_awaited();
}

static inline void task_yield_current(void) { alder_task_yield(); }

#endif /* ALDER_TASK_SHIM_H */
