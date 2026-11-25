/* Task runtime tests: the pinned step trampoline and task ABI, the
 * single-worker executor, park/resume, call handoff, timers, cancellation
 * with shielded reverse-order cleanup, await, release lifetime, deep call
 * chains, leak-free cycles, and quiescence reporting. */
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

static char run_log[1024];
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

/* A monotonic virtual-time base keeps every test's deadlines ahead of any
 * clock advance left by an earlier test in the same process. */
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
/* Basic completion                                                    */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
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

static void test_done_and_cycles(void) {
    uint64_t previous_id = 0;
    for (int iteration = 0; iteration < 100; iteration++) {
        RootTask root;
        CHECK(root_init(&root, done_step, sizeof(DoneFrame), UINT64_C(7)));
        DoneFrame *frame = (DoneFrame *)root.frame;
        frame->value = (uint64_t)iteration;
        AlderExecutorHooks hooks = base_hooks(test_base());
        CHECK(alder_executor_run(&hooks));
        CHECK(frame->out == (uint64_t)iteration + UINT64_C(1));
        CHECK(root.id != 0);
        CHECK(root.id != previous_id);
        previous_id = root.id;
        root_release(&root);
        CHECK(alder_runtime_live_allocations() == 0u);
    }
}

/* ------------------------------------------------------------------ */
/* Park and resume on a timer                                          */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    uint64_t deadline;
    uint64_t value;
    uint64_t out;
} TimerFrame;

static AlderStepStatus timer_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    TimerFrame *frame = (TimerFrame *)frame_ptr;
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_TIMER);
        if (!alder_timer_at(alder_task_wakeup(), frame->deadline)) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    frame->out = frame->value + UINT64_C(5);
    return ALDER_STEP_DONE;
}

static void test_park_resume(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, timer_step, sizeof(TimerFrame), UINT64_C(1)));
    TimerFrame *frame = (TimerFrame *)root.frame;
    frame->deadline = base + UINT64_C(10);
    frame->value = UINT64_C(37);
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->out == UINT64_C(42));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* ------------------------------------------------------------------ */
/* Timer range and wake-before-park                                    */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    bool rejected_max;
    bool accepted_now;
} RangeFrame;

static AlderStepStatus range_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    RangeFrame *frame = (RangeFrame *)frame_ptr;
    frame->rejected_max =
        !alder_timer_at(alder_task_wakeup(), UINT64_MAX);
    frame->accepted_now =
        alder_timer_at(alder_task_wakeup(), test_now_value);
    return ALDER_STEP_DONE;
}

static void test_timer_range(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, range_step, sizeof(RangeFrame), UINT64_C(2)));
    RangeFrame *frame = (RangeFrame *)root.frame;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->rejected_max);
    CHECK(frame->accepted_now);
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

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

static void test_wake_before_park(void) {
    uint64_t base = test_base();
    RootTask first;
    RootTask second;
    CHECK(root_init(&first, tag_timer_step, sizeof(TagTimerFrame), UINT64_C(3)));
    CHECK(root_init(&second, tag_timer_step, sizeof(TagTimerFrame), UINT64_C(3)));
    TagTimerFrame *first_frame = (TagTimerFrame *)first.frame;
    TagTimerFrame *second_frame = (TagTimerFrame *)second.frame;
    first_frame->deadline = base;
    first_frame->tag = 'w';
    second_frame->deadline = base + UINT64_C(100);
    second_frame->tag = 'l';
    log_clear();
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    /* The already-due timer keeps the first task runnable, so it resumes
     * before the idle executor advances the clock to the second deadline. */
    CHECK(log_is("wl"));
    root_release(&first);
    root_release(&second);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* A resumed tag records a second letter, so the order is observable. */
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

static void test_wake_before_park_order(void) {
    uint64_t base = test_base();
    RootTask first;
    RootTask second;
    CHECK(root_init(&first, resume_order_step, sizeof(ResumeOrderFrame),
                    UINT64_C(4)));
    CHECK(root_init(&second, resume_order_step, sizeof(ResumeOrderFrame),
                    UINT64_C(4)));
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

/* ------------------------------------------------------------------ */
/* Yield and deterministic timer ordering                              */
/* ------------------------------------------------------------------ */

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

static AlderStepStatus tag_done_step(AlderTask *task, AlderDomain *results,
                                     void *frame_ptr,
                                     AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    YieldFrame *frame = (YieldFrame *)frame_ptr;
    log_char(frame->tag);
    return ALDER_STEP_DONE;
}

static void test_yield(void) {
    RootTask first;
    RootTask second;
    CHECK(root_init(&first, yield_step, sizeof(YieldFrame), UINT64_C(5)));
    CHECK(root_init(&second, tag_done_step, sizeof(YieldFrame), UINT64_C(5)));
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
}

static AlderStepStatus ordered_timer_step(AlderTask *task,
                                          AlderDomain *results,
                                          void *frame_ptr,
                                          AlderDomain *frame_domain) {
    return tag_timer_step(task, results, frame_ptr, frame_domain);
}

static void run_ordering(uint64_t base, uint64_t first_delay,
                         uint64_t second_delay, uint64_t third_delay,
                         const char *expected) {
    RootTask first;
    RootTask second;
    RootTask third;
    CHECK(root_init(&first, ordered_timer_step, sizeof(TagTimerFrame),
                    UINT64_C(6)));
    CHECK(root_init(&second, ordered_timer_step, sizeof(TagTimerFrame),
                    UINT64_C(6)));
    CHECK(root_init(&third, ordered_timer_step, sizeof(TagTimerFrame),
                    UINT64_C(6)));
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

static void test_timer_order(void) {
    /* Equal deadlines use task-id order; later deadlines follow. */
    run_ordering(test_base(), UINT64_C(10), UINT64_C(10), UINT64_C(20), "abc");
    run_ordering(test_base(), UINT64_C(20), UINT64_C(10), UINT64_C(15), "bca");
}

/* ------------------------------------------------------------------ */
/* Call handoff and result copy                                        */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    uint64_t value;
    uint64_t out;
} ChildFrame;

static AlderStepStatus child_done_step(AlderTask *task, AlderDomain *results,
                                       void *frame_ptr,
                                       AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ChildFrame *frame = (ChildFrame *)frame_ptr;
    frame->out = frame->value * UINT64_C(2);
    return ALDER_STEP_DONE;
}

typedef struct {
    uint32_t state;
    uint64_t value;
    uint64_t out;
    ChildFrame *child_frame;
    AlderDomain child_domain;
} CallFrame;

static AlderStepStatus call_parent_step(AlderTask *task, AlderDomain *results,
                                        void *frame_ptr,
                                        AlderDomain *frame_domain) {
    (void)results;
    CallFrame *frame = (CallFrame *)frame_ptr;
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
        frame->child_frame->value = frame->value;
        alder_task_call(task, child_done_step, frame->child_frame,
                        &frame->child_domain);
        frame->state = 1;
        return ALDER_STEP_CALL;
    }
    frame->out = frame->child_frame->out + UINT64_C(1);
    alder_domain_destroy(&frame->child_domain);
    frame->child_frame = NULL;
    return ALDER_STEP_DONE;
}

static void test_call_handoff(void) {
    RootTask root;
    CHECK(root_init(&root, call_parent_step, sizeof(CallFrame), UINT64_C(8)));
    CallFrame *frame = (CallFrame *)root.frame;
    frame->value = UINT64_C(20);
    AlderExecutorHooks hooks = base_hooks(test_base());
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->out == UINT64_C(41));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* ------------------------------------------------------------------ */
/* Deep call chains                                                    */
/* ------------------------------------------------------------------ */

typedef struct ChainFrame {
    uint32_t state;
    uint32_t depth;
    uint32_t limit;
    uint64_t out;
    struct ChainFrame *child;
    AlderDomain child_domain;
} ChainFrame;

static uintptr_t stack_probe_min = 0;
static uintptr_t stack_probe_max = 0;

/* Address Sanitizer gives instrumented frames a rotating fake stack, which
 * says nothing about real worker stack growth. This helper keeps its frame
 * on the real stack so the probe measures the executor's stack depth. */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((no_sanitize_address))
#endif
static uintptr_t stack_probe(void) {
    volatile unsigned char marker = 0;
    return (uintptr_t)&marker;
}

static AlderStepStatus chain_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)results;
    ChainFrame *frame = (ChainFrame *)frame_ptr;
    uintptr_t probe = stack_probe();
    if (stack_probe_min == 0 || probe < stack_probe_min) {
        stack_probe_min = probe;
    }
    if (probe > stack_probe_max) {
        stack_probe_max = probe;
    }
    if (frame->state == 0) {
        if (frame->depth == frame->limit) {
            frame->out = 0;
            return ALDER_STEP_DONE;
        }
        if (!alder_domain_init(&frame->child_domain, frame_domain)) {
            return ALDER_STEP_CANCELLED;
        }
        frame->child = (ChainFrame *)alder_domain_alloc(
            &frame->child_domain, sizeof *frame->child,
            _Alignof(ChainFrame));
        if (frame->child == NULL) {
            return ALDER_STEP_CANCELLED;
        }
        memset(frame->child, 0, sizeof *frame->child);
        frame->child->depth = frame->depth + 1;
        frame->child->limit = frame->limit;
        alder_task_call(task, chain_step, frame->child, &frame->child_domain);
        frame->state = 1;
        return ALDER_STEP_CALL;
    }
    frame->out = frame->child->out + UINT64_C(1);
    alder_domain_destroy(&frame->child_domain);
    frame->child = NULL;
    return ALDER_STEP_DONE;
}

static void test_deep_chain(void) {
    enum { DEPTH = 2500 };
    RootTask root;
    CHECK(root_init(&root, chain_step, sizeof(ChainFrame), UINT64_C(9)));
    ChainFrame *frame = (ChainFrame *)root.frame;
    frame->depth = 0;
    frame->limit = (uint32_t)DEPTH;
    stack_probe_min = 0;
    stack_probe_max = 0;
    AlderExecutorHooks hooks = base_hooks(test_base());
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->out == (uint64_t)DEPTH);
    CHECK(stack_probe_min != 0);
    CHECK(stack_probe_max - stack_probe_min < (uintptr_t)65536);
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* ------------------------------------------------------------------ */
/* Cancellation unwind, reverse cleanup, shielded teardown             */
/* ------------------------------------------------------------------ */

static bool shield_saw_cancelled = false;
static bool unshield_saw_cancelled = false;
static bool state3_saw_cancelled = true;
static bool park_in_teardown = false;

typedef struct CancelFrame {
    uint32_t state;
    char tag;
    char cleanup_tags[3];
    AlderCleanupScope scope;
    struct CancelFrame *child;
    AlderDomain child_domain;
    bool cancelled;
    uint64_t out;
} CancelFrame;

static void cleanup_record(void *context) {
    log_char(*(const char *)context);
}

static AlderStepStatus cancel_teardown(CancelFrame *frame,
                                       AlderDomain *frame_domain);

static AlderStepStatus cancel_step(AlderTask *task, AlderDomain *results,
                                   void *frame_ptr, AlderDomain *frame_domain) {
    (void)results;
    CancelFrame *frame = (CancelFrame *)frame_ptr;
    if (frame->state == 3) {
        state3_saw_cancelled = alder_task_cancelled();
        alder_task_shield_pop();
        unshield_saw_cancelled = alder_task_cancelled();
        frame->cancelled = true;
        return ALDER_STEP_CANCELLED;
    }
    if (frame->state == 0) {
        if (!alder_cleanup_scope_begin_adopting(&frame->scope)) {
            return ALDER_STEP_CANCELLED;
        }
        AlderCleanupId id;
        char first_tag = (char)('1' + ('c' - frame->tag) * 2);
        char second_tag = (char)(first_tag + 1);
        frame->cleanup_tags[0] = first_tag;
        frame->cleanup_tags[1] = second_tag;
        if (!alder_cleanup_push(&frame->scope, cleanup_record,
                                &frame->cleanup_tags[0], &id)) {
            return ALDER_STEP_CANCELLED;
        }
        if (!alder_cleanup_push(&frame->scope, cleanup_record,
                                &frame->cleanup_tags[1], &id)) {
            return ALDER_STEP_CANCELLED;
        }
        if (frame->tag != 'c') {
            if (!alder_domain_init(&frame->child_domain, frame_domain)) {
                return ALDER_STEP_CANCELLED;
            }
            frame->child = (CancelFrame *)alder_domain_alloc(
                &frame->child_domain, sizeof *frame->child,
                _Alignof(CancelFrame));
            if (frame->child == NULL) {
                return ALDER_STEP_CANCELLED;
            }
            memset(frame->child, 0, sizeof *frame->child);
            frame->child->tag = (char)(frame->tag + 1);
            alder_task_call(task, cancel_step, frame->child,
                            &frame->child_domain);
            frame->state = 1;
            return ALDER_STEP_CALL;
        }
        frame->state = 2;
        alder_task_wait_reason(ALDER_WAIT_IO);
        return ALDER_STEP_PARK;
    }
    if (frame->state == 1) {
        if (alder_task_cancelled()) {
            return cancel_teardown(frame, frame_domain);
        }
        frame->out = frame->child->out + UINT64_C(1);
        alder_domain_destroy(&frame->child_domain);
        frame->child = NULL;
        AlderCleanupFn fn;
        void *context;
        while (alder_cleanup_scope_next(&frame->scope, &fn, &context)) {
            fn(context);
        }
        (void)alder_cleanup_end(&frame->scope);
        return ALDER_STEP_DONE;
    }
    /* state 2: the deepest activation resumed from its external park. */
    if (alder_task_cancelled()) {
        return cancel_teardown(frame, frame_domain);
    }
    AlderCleanupFn fn;
    void *context;
    while (alder_cleanup_scope_next(&frame->scope, &fn, &context)) {
        fn(context);
    }
    (void)alder_cleanup_end(&frame->scope);
    frame->out = 0;
    return ALDER_STEP_DONE;
}

static AlderStepStatus cancel_teardown(CancelFrame *frame,
                                       AlderDomain *frame_domain) {
    (void)frame_domain;
    if (frame->child != NULL) {
        alder_domain_destroy(&frame->child_domain);
        frame->child = NULL;
    }
    alder_task_shield_push();
    if (alder_task_cancelled()) {
        return ALDER_STEP_CANCELLED;
    }
    AlderCleanupFn fn;
    void *context;
    while (alder_cleanup_scope_next(&frame->scope, &fn, &context)) {
        fn(context);
    }
    if (!alder_cleanup_end(&frame->scope)) {
        return ALDER_STEP_CANCELLED;
    }
    if (park_in_teardown && frame->tag == 'c' && frame->state == 2) {
        frame->state = 3;
        shield_saw_cancelled = alder_task_cancelled();
        if (!alder_timer_at(alder_task_wakeup(),
                            test_now_value + UINT64_C(50))) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    alder_task_shield_pop();
    frame->cancelled = true;
    return ALDER_STEP_CANCELLED;
}

static void test_cancellation_unwind(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, cancel_step, sizeof(CancelFrame), UINT64_C(10)));
    CancelFrame *frame = (CancelFrame *)root.frame;
    frame->tag = 'a';
    log_clear();
    park_in_teardown = false;
    shield_saw_cancelled = true;
    unshield_saw_cancelled = false;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(!alder_executor_run(&hooks));
    alder_task_cancel(root.id);
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is("214365"));
    CHECK(frame->cancelled);
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* The deepest teardown parks while shielded; state 3 pops the shield. */
static void test_cancellation_shielded_park(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, cancel_step, sizeof(CancelFrame), UINT64_C(11)));
    CancelFrame *frame = (CancelFrame *)root.frame;
    frame->tag = 'a';
    log_clear();
    park_in_teardown = true;
    shield_saw_cancelled = true;
    unshield_saw_cancelled = false;
    state3_saw_cancelled = true;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(!alder_executor_run(&hooks));
    alder_task_cancel(root.id);
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is("214365"));
    CHECK(frame->cancelled);
    CHECK(!shield_saw_cancelled);
    CHECK(!state3_saw_cancelled);
    CHECK(unshield_saw_cancelled);
    park_in_teardown = false;
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* ------------------------------------------------------------------ */
/* Await handoff                                                       */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    uint64_t out;
    bool cancelled;
} AwaitChildFrame;

static AlderStepStatus await_child_step(AlderTask *task, AlderDomain *results,
                                        void *frame_ptr,
                                        AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    AwaitChildFrame *frame = (AwaitChildFrame *)frame_ptr;
    if (frame->state == 0) {
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_TASK);
        return ALDER_STEP_PARK;
    }
    if (alder_task_cancelled()) {
        frame->cancelled = true;
        return ALDER_STEP_CANCELLED;
    }
    frame->out = UINT64_C(77);
    return ALDER_STEP_DONE;
}

typedef struct {
    uint32_t state;
    uint64_t child_id;
    AwaitChildFrame *child_frame;
    AlderDomain child_domain;
    uint64_t child_out;
    bool child_cancelled;
    uint64_t out;
} AwaitParentFrame;

static AlderStepStatus await_parent_step(AlderTask *task, AlderDomain *results,
                                         void *frame_ptr,
                                         AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    AwaitParentFrame *frame = (AwaitParentFrame *)frame_ptr;
    if (frame->state == 0) {
        if (!alder_domain_init(&frame->child_domain, frame_domain)) {
            return ALDER_STEP_CANCELLED;
        }
        frame->child_frame = (AwaitChildFrame *)alder_domain_alloc(
            &frame->child_domain, sizeof *frame->child_frame,
            _Alignof(AwaitChildFrame));
        if (frame->child_frame == NULL) {
            return ALDER_STEP_CANCELLED;
        }
        memset(frame->child_frame, 0, sizeof *frame->child_frame);
        AlderTask *child = alder_task_create(UINT64_C(12), await_child_step,
                                             frame->child_frame,
                                             &frame->child_domain);
        frame->child_id = alder_task_handle(child);
        alder_task_start(child);
        if (alder_task_await(frame->child_id)) {
            frame->child_out = frame->child_frame->out;
            frame->child_cancelled = frame->child_frame->cancelled;
            alder_task_release(frame->child_id);
            alder_domain_destroy(&frame->child_domain);
            frame->child_frame = NULL;
            frame->out = frame->child_cancelled
                             ? UINT64_C(999)
                             : frame->child_out + UINT64_C(1);
            return ALDER_STEP_DONE;
        }
        frame->state = 1;
        alder_task_wait_reason(ALDER_WAIT_TASK);
        return ALDER_STEP_PARK;
    }
    frame->child_out = frame->child_frame->out;
    frame->child_cancelled = frame->child_frame->cancelled;
    alder_task_release(frame->child_id);
    alder_domain_destroy(&frame->child_domain);
    frame->child_frame = NULL;
    frame->out = frame->child_cancelled ? UINT64_C(999)
                                        : frame->child_out + UINT64_C(1);
    return ALDER_STEP_DONE;
}

static void test_await_cancelled_child(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, await_parent_step, sizeof(AwaitParentFrame),
                    UINT64_C(13)));
    AwaitParentFrame *frame = (AwaitParentFrame *)root.frame;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(!alder_executor_run(&hooks));
    CHECK(frame->child_id != 0);
    alder_task_cancel(frame->child_id);
    CHECK(alder_executor_run(&hooks));
    CHECK(frame->child_cancelled);
    CHECK(frame->child_out == 0);
    CHECK(frame->out == UINT64_C(999));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

typedef struct {
    uint32_t state;
    uint64_t out;
} ReadyChildFrame;

static AlderStepStatus ready_child_step(AlderTask *task, AlderDomain *results,
                                        void *frame_ptr,
                                        AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ReadyChildFrame *frame = (ReadyChildFrame *)frame_ptr;
    frame->out = UINT64_C(55);
    return ALDER_STEP_DONE;
}

typedef struct {
    uint32_t state;
    uint64_t child_id;
    ReadyChildFrame *child_frame;
    uint64_t out;
} ReadyParentFrame;

static AlderStepStatus ready_parent_step(AlderTask *task, AlderDomain *results,
                                         void *frame_ptr,
                                         AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    ReadyParentFrame *frame = (ReadyParentFrame *)frame_ptr;
    if (alder_task_await(frame->child_id)) {
        frame->out = frame->child_frame->out + UINT64_C(1);
        return ALDER_STEP_DONE;
    }
    return ALDER_STEP_PARK;
}

static void test_await_complete_child(void) {
    uint64_t base = test_base();
    RootTask child;
    CHECK(root_init(&child, ready_child_step, sizeof(ReadyChildFrame),
                    UINT64_C(14)));
    ReadyChildFrame *child_frame = (ReadyChildFrame *)child.frame;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(child_frame->out == UINT64_C(55));

    RootTask parent;
    CHECK(root_init(&parent, ready_parent_step, sizeof(ReadyParentFrame),
                    UINT64_C(14)));
    ReadyParentFrame *parent_frame = (ReadyParentFrame *)parent.frame;
    parent_frame->child_id = child.id;
    parent_frame->child_frame = child_frame;
    CHECK(alder_executor_run(&hooks));
    CHECK(parent_frame->out == UINT64_C(56));
    root_release(&parent);
    root_release(&child);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* ------------------------------------------------------------------ */
/* Quiescence and wait reasons                                         */
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

static size_t idle_report_count = 0;
static size_t idle_report_calls = 0;
static uint64_t idle_report_ids[8];
static uint32_t idle_report_reasons[8];

static void idle_report(void *context, const AlderBlockedTask *blocked,
                        size_t count) {
    (void)context;
    idle_report_calls += 1;
    idle_report_count = count;
    for (size_t i = 0; i < count && i < 8; i++) {
        idle_report_ids[i] = blocked[i].task_id;
        idle_report_reasons[i] = blocked[i].wait_reason;
    }
}

static void test_wake_id(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, idle_step, sizeof(IdleFrame), UINT64_C(18)));
    IdleFrame *frame = (IdleFrame *)root.frame;
    frame->reason = ALDER_WAIT_IO;
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(!alder_executor_run(&hooks));
    alder_task_wake_id(root.id);
    CHECK(alder_executor_run(&hooks));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_quiescence(void) {
    uint64_t base = test_base();
    RootTask first;
    RootTask second;
    CHECK(root_init(&first, idle_step, sizeof(IdleFrame), UINT64_C(15)));
    CHECK(root_init(&second, idle_step, sizeof(IdleFrame), UINT64_C(15)));
    IdleFrame *first_frame = (IdleFrame *)first.frame;
    IdleFrame *second_frame = (IdleFrame *)second.frame;
    first_frame->reason = ALDER_WAIT_CHANNEL;
    second_frame->reason = ALDER_WAIT_TASK;
    idle_report_count = 0;
    idle_report_calls = 0;
    AlderExecutorHooks hooks = base_hooks(base);
    hooks.on_idle = idle_report;
    CHECK(!alder_executor_run(&hooks));
    CHECK(idle_report_calls == 1);
    CHECK(idle_report_count == 2);
    if (idle_report_count == 2) {
        CHECK(idle_report_ids[0] < idle_report_ids[1]);
        CHECK(idle_report_reasons[0] == ALDER_WAIT_CHANNEL);
        CHECK(idle_report_reasons[1] == ALDER_WAIT_TASK);
    }
    alder_task_cancel(first.id);
    alder_task_cancel(second.id);
    CHECK(alder_executor_run(&hooks));
    CHECK(idle_report_calls == 1);
    root_release(&first);
    root_release(&second);
    CHECK(alder_runtime_live_allocations() == 0u);
}

/* ------------------------------------------------------------------ */
/* Cleanup cursor and a suspending cleanup driver                      */
/* ------------------------------------------------------------------ */

typedef struct {
    uint32_t state;
    char tag;
} DriverFrame;

static AlderStepStatus cleanup_driver_step(AlderTask *task,
                                           AlderDomain *results,
                                           void *frame_ptr,
                                           AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    DriverFrame *frame = (DriverFrame *)frame_ptr;
    if (frame->state == 0) {
        log_char(frame->tag);
        frame->state = 1;
        if (!alder_timer_at(alder_task_wakeup(),
                            test_now_value + UINT64_C(5))) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    log_char('d');
    return ALDER_STEP_DONE;
}

typedef struct {
    uint32_t state;
    AlderCleanupScope scope;
    char tags[3];
    DriverFrame *driver_frame;
    AlderDomain driver_domain;
    uint64_t out;
} CursorFrame;

static AlderStepStatus cursor_run(AlderTask *task, CursorFrame *frame,
                                  AlderDomain *frame_domain) {
    for (;;) {
        AlderCleanupFn fn;
        void *context;
        if (alder_cleanup_scope_next(&frame->scope, &fn, &context)) {
            fn(context);
            continue;
        }
        AlderStepFn driver;
        void *driver_context;
        if (alder_cleanup_scope_next_step(&frame->scope, &driver,
                                          &driver_context)) {
            if (frame->driver_frame == NULL) {
                if (!alder_domain_init(&frame->driver_domain, frame_domain)) {
                    return ALDER_STEP_CANCELLED;
                }
                frame->driver_frame = (DriverFrame *)alder_domain_alloc(
                    &frame->driver_domain, sizeof *frame->driver_frame,
                    _Alignof(DriverFrame));
                if (frame->driver_frame == NULL) {
                    return ALDER_STEP_CANCELLED;
                }
                memset(frame->driver_frame, 0, sizeof *frame->driver_frame);
                frame->driver_frame->tag = *(const char *)driver_context;
            }
            alder_task_call(task, driver, frame->driver_frame,
                            &frame->driver_domain);
            frame->state = 2;
            return ALDER_STEP_CALL;
        }
        break;
    }
    if (!alder_cleanup_end(&frame->scope)) {
        return ALDER_STEP_CANCELLED;
    }
    if (frame->driver_frame != NULL) {
        alder_domain_destroy(&frame->driver_domain);
        frame->driver_frame = NULL;
    }
    frame->out = UINT64_C(1);
    return ALDER_STEP_DONE;
}

static AlderStepStatus cursor_step(AlderTask *task, AlderDomain *results,
                                   void *frame_ptr, AlderDomain *frame_domain) {
    (void)results;
    CursorFrame *frame = (CursorFrame *)frame_ptr;
    if (frame->state == 0) {
        if (!alder_cleanup_scope_begin_adopting(&frame->scope)) {
            return ALDER_STEP_CANCELLED;
        }
        frame->tags[0] = 'B';
        frame->tags[1] = 'D';
        frame->tags[2] = 'A';
        AlderCleanupId id;
        if (!alder_cleanup_push(&frame->scope, cleanup_record,
                                &frame->tags[2], &id)) {
            return ALDER_STEP_CANCELLED;
        }
        if (!alder_cleanup_push_step(&frame->scope, cleanup_driver_step,
                                     &frame->tags[1], &id)) {
            return ALDER_STEP_CANCELLED;
        }
        if (!alder_cleanup_push(&frame->scope, cleanup_record,
                                &frame->tags[0], &id)) {
            return ALDER_STEP_CANCELLED;
        }
        frame->state = 1;
        return cursor_run(task, frame, frame_domain);
    }
    if (frame->state == 2) {
        alder_domain_destroy(&frame->driver_domain);
        frame->driver_frame = NULL;
        frame->state = 1;
        return cursor_run(task, frame, frame_domain);
    }
    return ALDER_STEP_CANCELLED;
}

static void test_cleanup_cursor(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, cursor_step, sizeof(CursorFrame), UINT64_C(16)));
    CursorFrame *frame = (CursorFrame *)root.frame;
    log_clear();
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is("BDdA"));
    CHECK(frame->out == UINT64_C(1));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

typedef struct {
    uint32_t state;
    AlderCleanupScope scope;
    char tag;
    uint64_t out;
} AdoptFrame;

static AlderStepStatus adopt_step(AlderTask *task, AlderDomain *results,
                                  void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    AdoptFrame *frame = (AdoptFrame *)frame_ptr;
    if (frame->state == 0) {
        if (!alder_cleanup_scope_begin_adopting(&frame->scope)) {
            return ALDER_STEP_CANCELLED;
        }
        AlderCleanupId id;
        frame->tag = 'x';
        if (!alder_cleanup_push(&frame->scope, cleanup_record, &frame->tag,
                                &id)) {
            return ALDER_STEP_CANCELLED;
        }
        frame->state = 1;
        if (!alder_timer_at(alder_task_wakeup(),
                            test_now_value + UINT64_C(1))) {
            return ALDER_STEP_CANCELLED;
        }
        return ALDER_STEP_PARK;
    }
    if (!alder_cleanup_scope_begin_adopting(&frame->scope)) {
        return ALDER_STEP_CANCELLED;
    }
    AlderCleanupFn fn;
    void *context;
    if (!alder_cleanup_scope_next(&frame->scope, &fn, &context)) {
        return ALDER_STEP_CANCELLED;
    }
    fn(context);
    if (alder_cleanup_scope_next(&frame->scope, &fn, &context)) {
        return ALDER_STEP_CANCELLED;
    }
    if (!alder_cleanup_end(&frame->scope)) {
        return ALDER_STEP_CANCELLED;
    }
    frame->out = UINT64_C(2);
    return ALDER_STEP_DONE;
}

static void test_adopting_begin(void) {
    uint64_t base = test_base();
    RootTask root;
    CHECK(root_init(&root, adopt_step, sizeof(AdoptFrame), UINT64_C(17)));
    AdoptFrame *frame = (AdoptFrame *)root.frame;
    log_clear();
    AlderExecutorHooks hooks = base_hooks(base);
    CHECK(alder_executor_run(&hooks));
    CHECK(log_is("x"));
    CHECK(frame->out == UINT64_C(2));
    root_release(&root);
    CHECK(alder_runtime_live_allocations() == 0u);
}

static void test_cleanup_cursor_plain(void) {
    AlderCleanupScope scope;
    memset(&scope, 0, sizeof scope);
    CHECK(alder_cleanup_scope_begin_adopting(&scope));
    CHECK(alder_cleanup_scope_begin_adopting(&scope));
    char tags[3] = {'x', 'y', 'z'};
    AlderCleanupId id_x;
    AlderCleanupId id_y;
    AlderCleanupId id_z;
    CHECK(alder_cleanup_push(&scope, cleanup_record, &tags[0], &id_x));
    CHECK(alder_cleanup_push(&scope, cleanup_record, &tags[1], &id_y));
    CHECK(alder_cleanup_push(&scope, cleanup_record, &tags[2], &id_z));
    CHECK(alder_cleanup_disarm(id_y));
    log_clear();
    AlderCleanupFn fn;
    void *context;
    CHECK(alder_cleanup_scope_next(&scope, &fn, &context));
    fn(context);
    CHECK(alder_cleanup_scope_next(&scope, &fn, &context));
    fn(context);
    CHECK(!alder_cleanup_scope_next(&scope, &fn, &context));
    AlderStepFn driver;
    CHECK(!alder_cleanup_scope_next_step(&scope, &driver, &context));
    CHECK(alder_cleanup_end(&scope));
    CHECK(log_is("zx"));
    CHECK(alder_runtime_live_allocations() == 0u);
}

int main(void) {
    test_done_and_cycles();
    test_park_resume();
    test_timer_range();
    test_wake_before_park();
    test_wake_before_park_order();
    test_yield();
    test_timer_order();
    test_call_handoff();
    test_deep_chain();
    test_cancellation_unwind();
    test_cancellation_shielded_park();
    test_await_cancelled_child();
    test_await_complete_child();
    test_wake_id();
    test_quiescence();
    test_cleanup_cursor();
    test_adopting_begin();
    test_cleanup_cursor_plain();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("task runtime: ok\n");
    return 0;
}
