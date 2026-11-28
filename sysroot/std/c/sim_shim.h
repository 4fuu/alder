/*
 * Toolchain-owned C binding shims for the std.test SimIo surface.
 *
 * SimIo binds its own header so std.task and std.test can be imported in one
 * module; the shared task entries stay in std/c/task_shim.h, which this
 * header includes once.
 */
#ifndef ALDER_SIM_SHIM_H
#define ALDER_SIM_SHIM_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "std/c/task_shim.h"

/* Lowering marker: the splitter removes this call and emits the canonical
 * park save. The runtime provides no definition. */
void alder_task_park(void);

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

#endif /* ALDER_SIM_SHIM_H */
