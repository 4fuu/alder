/* Bounded blocking-pool tests: a parked task resumes from C completion, a
 * cancelled task's record is retained until C returns, task and frame
 * storage can be released while C is still running, and repeated cycles are
 * leak-free. */
#define _POSIX_C_SOURCE 200809L

#include "alder.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures += 1;                                                 \
        }                                                                  \
    } while (0)

static bool configure(uint32_t workers, uint32_t blocking) {
    AlderExecutorConfig config;
    config.workers = workers;
    config.blocking_workers = blocking;
    config.local_lane = false;
    return alder_executor_configure(&config);
}

static void short_sleep(void) {
    struct timespec delay;
    delay.tv_sec = 0;
    delay.tv_nsec = 1000000L;
    (void)nanosleep(&delay, NULL);
}

/* ------------------------------------------------------------------ */
/* C gate shared by the blocking calls                                 */
/* ------------------------------------------------------------------ */

static pthread_mutex_t gate_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_cond = PTHREAD_COND_INITIALIZER;
static bool gate_open;
static bool gate_started;
static bool gate_finished;
static uint32_t gate_calls;
static uint32_t gate_completions;

static void gate_reset(void) {
    pthread_mutex_lock(&gate_lock);
    gate_open = false;
    gate_started = false;
    gate_finished = false;
    gate_calls = 0;
    gate_completions = 0;
    pthread_mutex_unlock(&gate_lock);
}

static void gate_entry(void *context) {
    (void)context;
    pthread_mutex_lock(&gate_lock);
    gate_calls += 1;
    gate_started = true;
    pthread_cond_broadcast(&gate_cond);
    while (!gate_open) {
        pthread_cond_wait(&gate_cond, &gate_lock);
    }
    pthread_mutex_unlock(&gate_lock);
    pthread_mutex_lock(&gate_lock);
    gate_finished = true;
    gate_completions += 1;
    pthread_cond_broadcast(&gate_cond);
    pthread_mutex_unlock(&gate_lock);
}

static void gate_wait_started(void) {
    pthread_mutex_lock(&gate_lock);
    while (!gate_started) {
        pthread_cond_wait(&gate_cond, &gate_lock);
    }
    pthread_mutex_unlock(&gate_lock);
}

static void gate_wait_calls(uint32_t calls) {
    pthread_mutex_lock(&gate_lock);
    while (gate_calls < calls) {
        pthread_cond_wait(&gate_cond, &gate_lock);
    }
    pthread_mutex_unlock(&gate_lock);
}

static void gate_release(void) {
    pthread_mutex_lock(&gate_lock);
    gate_open = true;
    pthread_cond_broadcast(&gate_cond);
    pthread_mutex_unlock(&gate_lock);
}

static void gate_wait_finished(void) {
    pthread_mutex_lock(&gate_lock);
    while (!gate_finished) {
        pthread_cond_wait(&gate_cond, &gate_lock);
    }
    pthread_mutex_unlock(&gate_lock);
}

static bool wait_live_zero(void) {
    for (uint32_t attempt = 0; attempt < 2000; attempt++) {
        if (alder_runtime_live_allocations() == 0u) {
            return true;
        }
        short_sleep();
    }
    return alder_runtime_live_allocations() == 0u;
}

/* The entry frees itself and drops its retain before decrementing the
 * in-flight count, so reconfiguring can trail the live-allocation check. */
static bool configure_default(void) {
    for (uint32_t attempt = 0; attempt < 2000; attempt++) {
        if (alder_executor_configure(NULL)) {
            return true;
        }
        short_sleep();
    }
    return alder_executor_configure(NULL);
}

static bool run_until_done(const AlderExecutorHooks *hooks) {
    for (uint32_t attempt = 0; attempt < 2000; attempt++) {
        if (alder_executor_run(hooks)) {
            return true;
        }
        short_sleep();
    }
    return alder_executor_run(hooks);
}

/* ------------------------------------------------------------------ */
/* Frames                                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    bool supported;
    bool cancelled;
    uint64_t out;
} ChildFrame;

typedef struct {
    uint32_t state;
    bool waiting;
    uint64_t child_id;
    ChildFrame *child_frame;
    AlderDomain child_domain;
    bool supported;
    bool cancelled;
    uint64_t out;
} RootFrame;

typedef struct {
    AlderDomain domain;
    void *frame;
    uint64_t id;
} RootTask;

static bool root_init(RootTask *root, AlderStepFn step, size_t frame_size,
                      uint64_t group) {
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
    AlderTask *task = alder_task_create(group, step, root->frame, &root->domain);
    root->id = alder_task_handle(task);
    alder_task_start(task);
    return true;
}

static void root_release(RootTask *root) {
    alder_task_release(root->id);
    alder_domain_destroy(&root->domain);
}

static AlderStepStatus child_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ChildFrame *frame = (ChildFrame *)frame_ptr;
    if (frame->state == 0) {
        if (!alder_task_blocking(gate_entry, NULL)) {
            frame->supported = false;
            frame->out = UINT64_C(0);
            return ALDER_STEP_DONE;
        }
        frame->supported = true;
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_BLOCKING);
        return ALDER_STEP_PARK;
    }
    if (alder_task_cancelled()) {
        frame->cancelled = true;
        return ALDER_STEP_CANCELLED;
    }
    frame->out = UINT64_C(42);
    return ALDER_STEP_DONE;
}

static AlderStepStatus root_step(AlderTask *task, AlderDomain *results,
                                 void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    RootFrame *frame = (RootFrame *)frame_ptr;
    if (frame->state == 0) {
        if (!alder_domain_init(&frame->child_domain, frame_domain)) {
            return ALDER_STEP_CANCELLED;
        }
        frame->child_frame = (ChildFrame *)alder_domain_alloc(
            &frame->child_domain, sizeof *frame->child_frame,
            _Alignof(ChildFrame));
        if (frame->child_frame == NULL) {
            return ALDER_STEP_CANCELLED;
        }
        memset(frame->child_frame, 0, sizeof *frame->child_frame);
        AlderTask *child = alder_task_create(
            UINT64_C(41), child_step, frame->child_frame, &frame->child_domain);
        frame->child_id = alder_task_handle(child);
        alder_task_start(child);
        frame->state = 1;
        frame->waiting = false;
    }
    if (frame->state == 1) {
        if (!frame->waiting) {
            if (!alder_task_await(frame->child_id)) {
                frame->waiting = true;
                alder_task_wait_reason(ALDER_WAIT_TASK);
                return ALDER_STEP_PARK;
            }
            frame->waiting = true;
        }
        frame->supported = frame->child_frame->supported;
        frame->cancelled = frame->child_frame->cancelled;
        frame->out = frame->child_frame->cancelled
                         ? UINT64_C(999)
                         : frame->child_frame->out;
        alder_task_release(frame->child_id);
        alder_domain_destroy(&frame->child_domain);
        frame->child_frame = NULL;
        frame->state = 2;
        return ALDER_STEP_DONE;
    }
    return ALDER_STEP_CANCELLED;
}

/* A simpler root used only when the blocking pool is disabled. */
typedef struct {
    uint32_t state;
    bool rejected;
    uint64_t out;
} RejectFrame;

static AlderStepStatus reject_step(AlderTask *task, AlderDomain *results,
                                   void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    RejectFrame *frame = (RejectFrame *)frame_ptr;
    frame->rejected = !alder_task_blocking(gate_entry, NULL);
    frame->out = UINT64_C(1);
    return ALDER_STEP_DONE;
}

/* ------------------------------------------------------------------ */
/* Normal completion and repeated cycles                               */
/* ------------------------------------------------------------------ */

static void run_success_cycle(uint64_t group) {
    uint32_t calls_before;
    uint32_t completions_before;
    pthread_mutex_lock(&gate_lock);
    calls_before = gate_calls;
    completions_before = gate_completions;
    pthread_mutex_unlock(&gate_lock);

    RootTask root;
    CHECK(root_init(&root, root_step, sizeof(RootFrame), group));
    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    /* A plain blocking call parks the child; the root is also parked, so the
     * first run must report quiescence and leave the C call running. */
    CHECK(!alder_executor_run(&hooks));
    gate_wait_started();
    gate_release();
    CHECK(run_until_done(&hooks));
    RootFrame *frame = (RootFrame *)root.frame;
    CHECK(frame->supported);
    CHECK(!frame->cancelled);
    CHECK(frame->out == UINT64_C(42));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);

    pthread_mutex_lock(&gate_lock);
    CHECK(gate_calls == calls_before + 1u);
    CHECK(gate_completions == completions_before + 1u);
    pthread_mutex_unlock(&gate_lock);
    gate_reset();
}

static void test_blocking_success(void) {
    CHECK(configure(1, 2));
    gate_reset();
    for (uint32_t iteration = 0; iteration < 10; iteration++) {
        run_success_cycle(UINT64_C(40));
    }
    CHECK(configure_default());
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_blocking_fixed_workers(void) {
    enum { ENTRIES = 3, WORKERS = 2 };
    CHECK(configure(1, WORKERS));
    gate_reset();
    RootTask roots[ENTRIES];
    for (uint32_t i = 0; i < ENTRIES; i++) {
        CHECK(root_init(&roots[i], root_step, sizeof(RootFrame),
                        UINT64_C(44) + (uint64_t)i));
    }
    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    CHECK(!alder_executor_run(&hooks));
    gate_wait_calls(WORKERS);
    short_sleep();
    pthread_mutex_lock(&gate_lock);
    /* The pool has exactly two workers, so the third queued entry cannot
     * enter C while the first two are still gated. */
    CHECK(gate_calls == (uint32_t)WORKERS);
    pthread_mutex_unlock(&gate_lock);
    gate_release();
    CHECK(run_until_done(&hooks));
    for (uint32_t i = 0; i < ENTRIES; i++) {
        RootFrame *frame = (RootFrame *)roots[i].frame;
        CHECK(frame->supported);
        CHECK(!frame->cancelled);
        CHECK(frame->out == UINT64_C(42));
        root_release(&roots[i]);
    }
    CHECK(alder_runtime_live_allocations() == 0u);
    pthread_mutex_lock(&gate_lock);
    CHECK(gate_calls == (uint32_t)ENTRIES);
    CHECK(gate_completions == (uint32_t)ENTRIES);
    pthread_mutex_unlock(&gate_lock);
    CHECK(configure_default());
}

/* ------------------------------------------------------------------ */
/* Cancellation while C is still running                               */
/* ------------------------------------------------------------------ */

static void test_blocking_cancel_retain(void) {
    CHECK(configure(1, 1));
    gate_reset();
    RootTask root;
    CHECK(root_init(&root, root_step, sizeof(RootFrame), UINT64_C(42)));
    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    CHECK(!alder_executor_run(&hooks));
    RootFrame *frame = (RootFrame *)root.frame;
    gate_wait_started();
    CHECK(gate_calls == 1u);

    alder_task_cancel(frame->child_id);
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->supported);
    CHECK(frame->cancelled);
    CHECK(frame->out == UINT64_C(999));
    root_release(&root);
    /* The child and root are released and their domains destroyed, but C is
     * still inside the blocking entry. The entry's retain keeps the task
     * record and wakeup token alive, so this is not a leak and the eventual
     * signal cannot touch freed memory. */
    CHECK(alder_runtime_live_allocations() > 0u);

    gate_release();
    gate_wait_finished();
    CHECK(wait_live_zero());
    pthread_mutex_lock(&gate_lock);
    CHECK(gate_completions == 1u);
    pthread_mutex_unlock(&gate_lock);
    CHECK(configure_default());
}

/* ------------------------------------------------------------------ */
/* Pool disabled                                                       */
/* ------------------------------------------------------------------ */

static void test_blocking_disabled(void) {
    CHECK(configure(1, 0));
    RootTask root;
    CHECK(root_init(&root, reject_step, sizeof(RejectFrame), UINT64_C(43)));
    AlderExecutorHooks hooks;
    memset(&hooks, 0, sizeof hooks);
    CHECK(alder_executor_run(&hooks));
    RejectFrame *frame = (RejectFrame *)root.frame;
    CHECK(frame->rejected);
    CHECK(frame->out == UINT64_C(1));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));
}

int main(void) {
    test_blocking_success();
    test_blocking_fixed_workers();
    test_blocking_cancel_retain();
    test_blocking_disabled();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("task blocking runtime: ok\n");
    return 0;
}
