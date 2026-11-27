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

static inline int task_timer_in(unsigned long long delay) {
    return alder_timer_in((uint64_t)delay) ? 1 : 0;
}

static inline void task_timer_clear(void) { alder_timer_clear(); }

static inline unsigned long long task_clock_now(void) { return (unsigned long long)alder_executor_clock(); }

static inline int task_cancelled_now(void) {
    return alder_task_cancelled() ? 1 : 0;
}

static inline unsigned long long task_spawn_index(unsigned long long task) {
    return (unsigned long long)alder_task_spawn_index((uint64_t)task);
}

static inline unsigned long long task_current_id(void) { return (unsigned long long)alder_task_id(); }

static inline int task_write_stdout(const uint8_t *data, unsigned long long len) {
    if (len > (unsigned long long)SIZE_MAX) {
        return -1;
    }
    size_t written = fwrite(data, 1, (size_t)len, stdout);
    if (written != (size_t)len) {
        return -1;
    }
    if (fflush(stdout) != 0) {
        return -1;
    }
    return 0;
}

static inline int task_write_stderr(const uint8_t *data, unsigned long long len) {
    if (len > (unsigned long long)SIZE_MAX) {
        return -1;
    }
    size_t written = fwrite(data, 1, (size_t)len, stderr);
    if (written != (size_t)len) {
        return -1;
    }
    if (fflush(stderr) != 0) {
        return -1;
    }
    return 0;
}

#define ALDER_SIM_DEADLOCK_BUFFER 4096

static inline void task_sim_idle(void *context,
                                 const AlderBlockedTask *blocked,
                                 size_t count) {
    char text[ALDER_SIM_DEADLOCK_BUFFER];
    size_t at = 0;
    int written;
    (void)context;
    written = snprintf(text, sizeof text, "SimIo deadlock");
    if (written < 0 || (size_t)written >= sizeof text) {
        c_panic("SimIo deadlock");
    }
    at = (size_t)written;
    for (size_t i = 0; i < count; i++) {
        uint64_t index = alder_task_spawn_index(blocked[i].task_id);
        written = snprintf(text + at, sizeof text - at,
                           "\n  blocked task %llu",
                           (unsigned long long)index);
        if (written < 0 || (size_t)written >= sizeof text - at) {
            c_panic(text);
        }
        at += (size_t)written;
    }
    c_panic(text);
}

static inline void task_install_sim_hooks(void) {
    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    hooks.on_idle = task_sim_idle;
    alder_executor_set_default_hooks(&hooks);
}

/* SimIo generators live in a fixed process-local pool: a capability is
 * copyable and has no cleanup hook in the snapshot, so the pool keeps the
 * stream state stable without a heap allocation that no one could release. */
#define ALDER_SIM_RNG_SLOTS 64

static ALDER_MAYBE_UNUSED uint64_t
    alder_sim_rng_states[ALDER_SIM_RNG_SLOTS];
static ALDER_MAYBE_UNUSED size_t alder_sim_rng_used;

static inline unsigned long long sim_rng_new(unsigned long long seed) {
    if (alder_sim_rng_used >= (size_t)ALDER_SIM_RNG_SLOTS) {
        c_panic("SimIo random generator pool exhausted");
    }
    alder_sim_rng_used += 1;
    alder_sim_rng_states[alder_sim_rng_used - 1] = seed;
    return (unsigned long long)alder_sim_rng_used;
}

static inline uint64_t sim_rng_next(unsigned long long handle) {
    uint64_t z;
    if (handle == 0 || handle > (unsigned long long)alder_sim_rng_used) {
        c_panic("SimIo random generator is null");
    }
    alder_sim_rng_states[handle - 1] += UINT64_C(0x9e3779b97f4a7c15);
    z = alder_sim_rng_states[handle - 1];
    z = (z ^ (z >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94d049bb133111eb);
    return z ^ (z >> 31);
}

static inline void sim_rng_fill(unsigned long long handle, uint8_t *out, unsigned long long len) {
    uint64_t at = 0;
    if (out == NULL && len != 0) {
        c_panic("SimIo random buffer is null");
    }
    while (at < len) {
        uint64_t word = sim_rng_next(handle);
        uint64_t take = len - at;
        if (take > UINT64_C(8)) {
            take = UINT64_C(8);
        }
        for (uint64_t i = 0; i < take; i++) {
            out[at + i] = (uint8_t)(word >> (8 * i));
        }
        at += take;
    }
}

#endif /* ALDER_TASK_SHIM_H */
