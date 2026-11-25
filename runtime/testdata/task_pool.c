/* Threaded executor tests: a multi-worker pool with deterministic results,
 * timer ordering under the threaded single-worker pool, quiescence reporting,
 * and leak-free task cycles. */
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

static bool configure(uint32_t workers, uint32_t blocking, bool local) {
    AlderExecutorConfig config;
    config.workers = workers;
    config.blocking_workers = blocking;
    config.local_lane = local;
    return alder_executor_configure(&config);
}

static char run_log[64];
static size_t run_log_len = 0;

static void log_clear(void) {
    run_log[0] = '\0';
    run_log_len = 0;
}

static void log_char(char tag) {
    if (run_log_len + 1 < sizeof(run_log)) {
        run_log[run_log_len] = tag;
        run_log_len += 1;
        run_log[run_log_len] = '\0';
    }
}

static bool log_is(const char *expected) {
    return strcmp(run_log, expected) == 0;
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

/* ------------------------------------------------------------------ */
/* Configuration contracts                                             */
/* ------------------------------------------------------------------ */

typedef struct {
    bool rejected;
} ConfigFrame;

typedef struct {
    uint64_t value;
    uint64_t out;
} ConfigDoneFrame;

static AlderStepStatus config_done_step(AlderTask *task, AlderDomain *results,
                                        void *frame_ptr,
                                        AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ConfigDoneFrame *frame = (ConfigDoneFrame *)frame_ptr;
    frame->out = frame->value + UINT64_C(1);
    return ALDER_STEP_DONE;
}

static AlderStepStatus config_step(AlderTask *task, AlderDomain *results,
                                   void *frame_ptr,
                                   AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ConfigFrame *frame = (ConfigFrame *)frame_ptr;
    frame->rejected = !alder_executor_configure(NULL);
    return ALDER_STEP_DONE;
}

static void test_configure_contract(void) {
    AlderExecutorConfig config;
    config.workers = 0;
    config.blocking_workers = 0;
    config.local_lane = false;
    CHECK(!alder_executor_configure(&config));
    config.workers = 65;
    CHECK(!alder_executor_configure(&config));
    config.workers = 1;
    config.blocking_workers = 33;
    CHECK(!alder_executor_configure(&config));

    CHECK(configure(1, 0, false));
    RootTask live;
    CHECK(root_init(&live, config_done_step, sizeof(ConfigDoneFrame),
                    UINT64_C(27)));
    ConfigDoneFrame *live_frame = (ConfigDoneFrame *)live.frame;
    live_frame->value = UINT64_C(3);
    CHECK(!alder_executor_configure(NULL));
    AlderExecutorHooks hooks = base_hooks(test_base());
    CHECK(alder_executor_run(&hooks));
    CHECK(live_frame->out == UINT64_C(4));
    root_release(&live);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));

    CHECK(configure(1, 0, false));
    RootTask during;
    CHECK(root_init(&during, config_step, sizeof(ConfigFrame),
                    UINT64_C(28)));
    CHECK(alder_executor_run(&hooks));
    ConfigFrame *during_frame = (ConfigFrame *)during.frame;
    CHECK(during_frame->rejected);
    root_release(&during);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));
}

/* ------------------------------------------------------------------ */
/* Multi-worker results                                                */
/* ------------------------------------------------------------------ */

enum { POOL_CHILDREN = 8 };

typedef struct {
    uint32_t state;
    uint64_t value;
    uint64_t deadline;
    uint64_t out;
} PoolChildFrame;

typedef struct {
    uint32_t state;
    bool waiting;
    uint64_t sum;
    uint64_t child_ids[POOL_CHILDREN];
    PoolChildFrame *children[POOL_CHILDREN];
    AlderDomain domains[POOL_CHILDREN];
    uint64_t out;
} PoolRootFrame;

static AlderStepStatus pool_child_step(AlderTask *task, AlderDomain *results,
                                       void *frame_ptr,
                                       AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    PoolChildFrame *frame = (PoolChildFrame *)frame_ptr;
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_TIMER);
        if (!alder_timer_at(alder_task_wakeup(), frame->deadline)) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    frame->out = frame->value * UINT64_C(3) + UINT64_C(1);
    return ALDER_STEP_DONE;
}

static AlderStepStatus pool_root_step(AlderTask *task, AlderDomain *results,
                                      void *frame_ptr,
                                      AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    PoolRootFrame *frame = (PoolRootFrame *)frame_ptr;
    for (;;) {
        if (frame->state == 0) {
            for (uint32_t i = 0; i < POOL_CHILDREN; i++) {
                if (!alder_domain_init(&frame->domains[i], frame_domain)) {
                    return ALDER_STEP_CANCELLED;
                }
                frame->children[i] = (PoolChildFrame *)alder_domain_alloc(
                    &frame->domains[i], sizeof *frame->children[i],
                    _Alignof(PoolChildFrame));
                if (frame->children[i] == NULL) {
                    return ALDER_STEP_CANCELLED;
                }
                memset(frame->children[i], 0, sizeof *frame->children[i]);
                frame->children[i]->value = (uint64_t)(i + 1);
                frame->children[i]->deadline =
                    test_now_value + (uint64_t)(i % 3) + UINT64_C(1);
                AlderTask *child = alder_task_create(
                    UINT64_C(21), pool_child_step, frame->children[i],
                    &frame->domains[i]);
                frame->child_ids[i] = alder_task_handle(child);
                alder_task_start(child);
            }
            frame->state = 1;
            frame->waiting = false;
        }
        if (frame->state > POOL_CHILDREN) {
            frame->out = frame->sum;
            return ALDER_STEP_DONE;
        }
        uint32_t index = frame->state - 1;
        if (!frame->waiting) {
            if (!alder_task_await(frame->child_ids[index])) {
                frame->waiting = true;
                alder_task_wait_reason(ALDER_WAIT_TASK);
                return ALDER_STEP_PARK;
            }
            frame->waiting = true;
        }
        frame->sum += frame->children[index]->out;
        alder_task_release(frame->child_ids[index]);
        alder_domain_destroy(&frame->domains[index]);
        frame->children[index] = NULL;
        frame->waiting = false;
        frame->state += 1;
    }
}

static void test_pool_results(void) {
    CHECK(configure(4, 0, false));
    for (uint32_t iteration = 0; iteration < 8; iteration++) {
        uint64_t base = test_base();
        RootTask root;
        CHECK(root_init(&root, pool_root_step, sizeof(PoolRootFrame),
                        UINT64_C(20)));
        AlderExecutorHooks hooks = base_hooks(base);
        CHECK(alder_executor_run(&hooks));
        PoolRootFrame *frame = (PoolRootFrame *)root.frame;
        uint64_t expected = 0;
        for (uint32_t i = 0; i < POOL_CHILDREN; i++) {
            expected += ((uint64_t)(i + 1)) * UINT64_C(3) + UINT64_C(1);
        }
        CHECK(frame->out == expected);
        CHECK(root.id != 0);
        root_release(&root);
        CHECK(alder_runtime_live_allocations() == 0u);
    }
    CHECK(alder_executor_configure(NULL));
}

/* ------------------------------------------------------------------ */
/* Deterministic timer ordering in the threaded single-worker pool     */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    uint64_t deadline;
    char tag;
} TagTimerFrame;

static AlderStepStatus tag_timer_step(AlderTask *task, AlderDomain *results,
                                      void *frame_ptr,
                                      AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    TagTimerFrame *frame = (TagTimerFrame *)frame_ptr;
    if (frame->state == 0) {
        frame->state = 1;
        if (!alder_timer_at(alder_task_wakeup(), frame->deadline)) {
            return ALDER_STEP_CANCELLED;
        }
        alder_task_wait_reason(ALDER_WAIT_TIMER);
        return ALDER_STEP_PARK;
    }
    log_char(frame->tag);
    return ALDER_STEP_DONE;
}

static void run_timer_order(uint64_t base, uint64_t first_delay,
                            uint64_t second_delay, uint64_t third_delay,
                            const char *expected) {
    RootTask first;
    RootTask second;
    RootTask third;
    CHECK(root_init(&first, tag_timer_step, sizeof(TagTimerFrame),
                    UINT64_C(22)));
    CHECK(root_init(&second, tag_timer_step, sizeof(TagTimerFrame),
                    UINT64_C(22)));
    CHECK(root_init(&third, tag_timer_step, sizeof(TagTimerFrame),
                    UINT64_C(22)));
    TagTimerFrame *first_frame = (TagTimerFrame *)first.frame;
    TagTimerFrame *second_frame = (TagTimerFrame *)second.frame;
    TagTimerFrame *third_frame = (TagTimerFrame *)third.frame;
    first_frame->deadline = base + first_delay;
    first_frame->tag = 'a';
    second_frame->deadline = base + second_delay;
    second_frame->tag = 'b';
    third_frame->deadline = base + third_delay;
    third_frame->tag = 'c';
    log_clear();
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is(expected));
    root_release(&first);
    root_release(&second);
    root_release(&third);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* A resumed tag records a second letter, exposing queue order. */
typedef struct {
    uint32_t state;
    uint64_t deadline;
    char before;
    char after;
} ResumeOrderFrame;

static AlderStepStatus resume_order_step(AlderTask *task, AlderDomain *results,
                                         void *frame_ptr,
                                         AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ResumeOrderFrame *frame = (ResumeOrderFrame *)frame_ptr;
    if (frame->state == 0) {
        log_char(frame->before);
        frame->state = 1;
        if (!alder_timer_at(alder_task_wakeup(), frame->deadline)) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    log_char(frame->after);
    return ALDER_STEP_DONE;
}

static void run_resume_order(uint64_t base) {
    RootTask first;
    RootTask second;
    CHECK(root_init(&first, resume_order_step, sizeof(ResumeOrderFrame),
                    UINT64_C(23)));
    CHECK(root_init(&second, resume_order_step, sizeof(ResumeOrderFrame),
                    UINT64_C(23)));
    ResumeOrderFrame *first_frame = (ResumeOrderFrame *)first.frame;
    ResumeOrderFrame *second_frame = (ResumeOrderFrame *)second.frame;
    first_frame->deadline = base;
    first_frame->before = 'w';
    first_frame->after = 'W';
    second_frame->deadline = base + UINT64_C(100);
    second_frame->before = 'l';
    second_frame->after = 'L';
    log_clear();
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is("wlWL"));
    root_release(&first);
    root_release(&second);
    CHECK(alder_runtime_live_allocations() == 0u);
}

typedef struct {
    uint32_t state;
    char tag;
} YieldFrame;

static AlderStepStatus yield_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    YieldFrame *frame = (YieldFrame *)frame_ptr;
    if (frame->state == 0) {
        log_char(frame->tag);
        frame->state = 1;
        alder_task_yield();
        return ALDER_STEP_PARK;
    }
    log_char((char)(frame->tag - 'a' + 'A'));
    return ALDER_STEP_DONE;
}

static AlderStepStatus done_tag_step(AlderTask *task, AlderDomain *results,
                                     void *frame_ptr,
                                     AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    YieldFrame *frame = (YieldFrame *)frame_ptr;
    log_char(frame->tag);
    return ALDER_STEP_DONE;
}

static void test_pool_timer_order(void) {
    CHECK(configure(1, 0, true));
    run_timer_order(test_base(), UINT64_C(10), UINT64_C(10), UINT64_C(20),
                    "abc");
    run_timer_order(test_base(), UINT64_C(20), UINT64_C(10), UINT64_C(15),
                    "bca");
    run_resume_order(test_base());
    RootTask first;
    RootTask second;
    CHECK(root_init(&first, yield_step, sizeof(YieldFrame), UINT64_C(24)));
    CHECK(root_init(&second, done_tag_step, sizeof(YieldFrame), UINT64_C(24)));
    YieldFrame *first_frame = (YieldFrame *)first.frame;
    YieldFrame *second_frame = (YieldFrame *)second.frame;
    first_frame->tag = 'a';
    second_frame->tag = 'b';
    log_clear();
    AlderExecutorHooks hooks = base_hooks(test_base());
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is("abA"));
    root_release(&first);
    root_release(&second);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));
}

/* ------------------------------------------------------------------ */
/* Quiescence and cross-thread wakeup                                  */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    uint32_t reason;
} IdleFrame;

static AlderStepStatus idle_step(AlderTask *task, AlderDomain *results,
                                 void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    IdleFrame *frame = (IdleFrame *)frame_ptr;
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(frame->reason);
        return ALDER_STEP_PARK;
    }
    if (alder_task_cancelled()) {
        return ALDER_STEP_CANCELLED;
    }
    return ALDER_STEP_DONE;
}

static size_t idle_report_calls = 0;
static size_t idle_report_count = 0;
static uint32_t idle_report_reason = ALDER_WAIT_NONE;

static void idle_report(void *context, const AlderBlockedTask *blocked,
                        size_t count) {
    (void)context;
    idle_report_calls += 1;
    idle_report_count = count;
    if (count > 0) {
        idle_report_reason = blocked[0].wait_reason;
    }
}

static void test_pool_quiescence(void) {
    CHECK(configure(2, 0, false));
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, idle_step, sizeof(IdleFrame), UINT64_C(25)));
    IdleFrame *frame = (IdleFrame *)root.frame;
    frame->reason = ALDER_WAIT_IO;
    idle_report_calls = 0;
    idle_report_count = 0;
    AlderExecutorHooks hooks = base_hooks(base);
    hooks.on_idle = idle_report;
    CHECK(!alder_executor_run(&hooks));
    CHECK(idle_report_calls == 1);
    CHECK(idle_report_count == 1);
    CHECK(idle_report_reason == ALDER_WAIT_IO);
    alder_task_wake_id(root.id);
    CHECK(alder_executor_run(&hooks));
    CHECK(idle_report_calls == 1);
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
    CHECK(alder_executor_configure(NULL));
}

/* ------------------------------------------------------------------ */
/* Repeated pool cycles                                                */
/* ------------------------------------------------------------------ */

typedef struct {
    uint64_t value;
    uint64_t out;
} DoneFrame;

static AlderStepStatus done_step(AlderTask *task, AlderDomain *results,
                                 void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    DoneFrame *frame = (DoneFrame *)frame_ptr;
    frame->out = frame->value + UINT64_C(1);
    return ALDER_STEP_DONE;
}

static void test_pool_leak_cycles(void) {
    CHECK(configure(4, 0, false));
    for (uint32_t iteration = 0; iteration < 25; iteration++) {
        RootTask root;
        CHECK(root_init(&root, done_step, sizeof(DoneFrame), UINT64_C(26)));
        DoneFrame *frame = (DoneFrame *)root.frame;
        frame->value = (uint64_t)iteration;
        AlderExecutorHooks hooks = base_hooks(test_base());
        CHECK(alder_executor_run(&hooks));
        CHECK(frame->out == (uint64_t)iteration + UINT64_C(1));
        root_release(&root);
        CHECK(alder_runtime_live_allocations() == 0u);
    }
    CHECK(alder_executor_configure(NULL));
    CHECK(alder_runtime_live_allocations() == 0u);
}

int main(void) {
    test_configure_contract();
    test_pool_results();
    test_pool_timer_order();
    test_pool_quiescence();
    test_pool_leak_cycles();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("task pool runtime: ok\n");
    return 0;
}
