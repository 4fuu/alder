/* Local-lane tests: a pool task and a local-lane task exchange wakeups
 * through the same token, local activations always run on the one local
 * thread, and that thread persists across executor runs. */
#include "alder.h"

#include <pthread.h>
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

static bool configure(uint32_t workers, bool local) {
    AlderExecutorConfig config;
    config.workers = workers;
    config.blocking_workers = 0;
    config.local_lane = local;
    return alder_executor_configure(&config);
}

static uint64_t test_now_value = 0;

static uint64_t test_base(void) {
    test_now_value += UINT64_C(1000000);
    return test_now_value;
}

static uint64_t test_now(void *context) {
    (void)context;
    return test_now_value;
}

static AlderExecutorHooks base_hooks(uint64_t base) {
    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    test_now_value = base;
    hooks.now = test_now;
    return hooks;
}

typedef struct {
    AlderDomain domain;
    void *frame;
    uint64_t id;
} RootTask;

static bool root_init(RootTask *root, AlderTaskLane lane, AlderStepFn step,
                      size_t frame_size, uint64_t group) {
    memset(root, 0, sizeof *root);
    if (!alder_domain_init(&root->domain, NULL)) {
        return false;
    }
    root->frame = alder_domain_alloc(&root->domain, frame_size,
                                     _Alignof(max_align_t));
    if (root->frame == NULL) {
        return false;
    }
    memset(root->frame, 0, frame_size);
    AlderTask *task = alder_task_create_on_lane(group, lane, step, root->frame,
                                                &root->domain);
    root->id = alder_task_handle(task);
    alder_task_start(task);
    return true;
}

static void root_release(RootTask *root) {
    alder_task_release(root->id);
    alder_domain_destroy(&root->domain);
}

/* ------------------------------------------------------------------ */
/* Cross-lane wakeup and confinement                                   */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    pthread_t threads[2];
    uint32_t thread_count;
    bool woken;
    uint64_t out;
} LocalFrame;

static void record_thread(pthread_t *threads, uint32_t *count) {
    if (*count < 2) {
        threads[*count] = pthread_self();
        *count += 1;
    }
}

static AlderStepStatus local_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    LocalFrame *frame = (LocalFrame *)frame_ptr;
    record_thread(frame->threads, &frame->thread_count);
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_IO);
        return ALDER_STEP_PARK;
    }
    frame->woken = true;
    frame->out = UINT64_C(7);
    return ALDER_STEP_DONE;
}

typedef struct {
    uint32_t state;
    uint64_t local_id;
    uint64_t deadline;
    uint64_t out;
} WakerFrame;

static AlderStepStatus waker_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    WakerFrame *frame = (WakerFrame *)frame_ptr;
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_TIMER);
        if (!alder_timer_at(alder_task_wakeup(), frame->deadline)) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    alder_task_wake_id(frame->local_id);
    frame->out = UINT64_C(1);
    return ALDER_STEP_DONE;
}

typedef struct {
    uint32_t state;
    bool waiting;
    uint64_t local_id;
    uint64_t waker_id;
    LocalFrame *local_frame;
    WakerFrame *waker_frame;
    AlderDomain local_domain;
    AlderDomain waker_domain;
    pthread_t root_thread;
    uint32_t local_thread_count;
    pthread_t local_threads[2];
    bool local_woken;
    uint64_t local_out;
    uint64_t waker_out;
    uint64_t out;
} LaneRootFrame;

static AlderStepStatus lane_root_step(AlderTask *task, AlderDomain *results,
                                      void *frame_ptr,
                                      AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    LaneRootFrame *frame = (LaneRootFrame *)frame_ptr;
    for (;;) {
        if (frame->state == 0) {
            frame->root_thread = pthread_self();
            if (!alder_domain_init(&frame->local_domain, frame_domain) ||
                !alder_domain_init(&frame->waker_domain, frame_domain)) {
                return ALDER_STEP_CANCELLED;
            }
            frame->local_frame = (LocalFrame *)alder_domain_alloc(
                &frame->local_domain, sizeof *frame->local_frame,
                _Alignof(LocalFrame));
            frame->waker_frame = (WakerFrame *)alder_domain_alloc(
                &frame->waker_domain, sizeof *frame->waker_frame,
                _Alignof(WakerFrame));
            if (frame->local_frame == NULL || frame->waker_frame == NULL) {
                return ALDER_STEP_CANCELLED;
            }
            memset(frame->local_frame, 0, sizeof *frame->local_frame);
            memset(frame->waker_frame, 0, sizeof *frame->waker_frame);
            frame->waker_frame->deadline = test_now_value + UINT64_C(1);

            AlderTask *local = alder_task_create_on_lane(
                UINT64_C(31), ALDER_LANE_LOCAL, local_step, frame->local_frame,
                &frame->local_domain);
            frame->local_id = alder_task_handle(local);
            alder_task_start(local);
            frame->waker_frame->local_id = frame->local_id;

            AlderTask *waker = alder_task_create(
                UINT64_C(31), waker_step, frame->waker_frame,
                &frame->waker_domain);
            frame->waker_id = alder_task_handle(waker);
            alder_task_start(waker);
            frame->state = 1;
            frame->waiting = false;
        }
        if (frame->state == 1) {
            if (!frame->waiting) {
                if (!alder_task_await(frame->local_id)) {
                    frame->waiting = true;
                    alder_task_wait_reason(ALDER_WAIT_TASK);
                    return ALDER_STEP_PARK;
                }
                frame->waiting = true;
            }
            frame->local_thread_count = frame->local_frame->thread_count;
            for (uint32_t i = 0; i < 2; i++) {
                frame->local_threads[i] = frame->local_frame->threads[i];
            }
            frame->local_woken = frame->local_frame->woken;
            frame->local_out = frame->local_frame->out;
            alder_task_release(frame->local_id);
            alder_domain_destroy(&frame->local_domain);
            frame->local_frame = NULL;
            frame->waiting = false;
            frame->state = 2;
            continue;
        }
        if (frame->state == 2) {
            if (!frame->waiting) {
                if (!alder_task_await(frame->waker_id)) {
                    frame->waiting = true;
                    alder_task_wait_reason(ALDER_WAIT_TASK);
                    return ALDER_STEP_PARK;
                }
                frame->waiting = true;
            }
            frame->waker_out = frame->waker_frame->out;
            alder_task_release(frame->waker_id);
            alder_domain_destroy(&frame->waker_domain);
            frame->waker_frame = NULL;
            frame->waiting = false;
            frame->state = 3;
            frame->out = frame->local_out + frame->waker_out;
            return ALDER_STEP_DONE;
        }
        return ALDER_STEP_CANCELLED;
    }
}

static void test_cross_lane_wakeup(void) {
    CHECK(configure(2, true));
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, ALDER_LANE_POOL, lane_root_step,
                    sizeof(LaneRootFrame), UINT64_C(30)));
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    LaneRootFrame *frame = (LaneRootFrame *)root.frame;
    CHECK(frame->local_thread_count == 2);
    CHECK(frame->local_woken);
    CHECK(frame->local_out == UINT64_C(7));
    CHECK(frame->waker_out == UINT64_C(1));
    CHECK(frame->out == UINT64_C(8));
    CHECK(pthread_equal(frame->local_threads[0], frame->local_threads[1]));
    CHECK(!pthread_equal(frame->local_threads[0], frame->root_thread));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));
}

/* ------------------------------------------------------------------ */
/* A local task keeps its thread across executor runs                  */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    pthread_t threads[2];
    uint32_t thread_count;
    uint64_t out;
} LocalParkFrame;

static AlderStepStatus local_park_step(AlderTask *task, AlderDomain *results,
                                       void *frame_ptr,
                                       AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    LocalParkFrame *frame = (LocalParkFrame *)frame_ptr;
    record_thread(frame->threads, &frame->thread_count);
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_IO);
        return ALDER_STEP_PARK;
    }
    frame->out = UINT64_C(11);
    return ALDER_STEP_DONE;
}

static void test_local_lane_across_runs(void) {
    CHECK(configure(1, true));
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, ALDER_LANE_LOCAL, local_park_step,
                    sizeof(LocalParkFrame), UINT64_C(32)));
    LocalParkFrame *frame = (LocalParkFrame *)root.frame;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(!alder_executor_run(&hooks));
    CHECK(frame->thread_count == 1);
    pthread_t first_thread = frame->threads[0];
    alder_task_wake_id(root.id);
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->thread_count == 2);
    CHECK(frame->out == UINT64_C(11));
    CHECK(pthread_equal(first_thread, frame->threads[1]));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));
}

int main(void) {
    test_cross_lane_wakeup();
    test_local_lane_across_runs();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("task lanes runtime: ok\n");
    return 0;
}
