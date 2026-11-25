/*
 * Alder minimal C runtime implementation.
 *
 * Portable C11, compiled with the project's strict warning set. The runtime
 * never relies on signed overflow, unspecified evaluation order,
 * strict-aliasing violations, unaligned typed access, or compiler
 * extensions. Representation-preserving transfers use memcpy.
 *
 * Storage layout:
 *  - a domain owns a singly linked list of segments; each segment is one
 *    heap block holding a header followed by a 16-aligned data area;
 *  - allocations bump through the data area with per-allocation alignment;
 *  - segments double up to ALDER_MAX_SEGMENT; larger requests get a
 *    dedicated segment of exactly the needed size;
 *  - reset truncates the marked segment and frees every later segment;
 *  - destroy frees all segments, recursively destroys children, and
 *    unregisters the domain from its parent.
 */
#include "alder.h"

#include <math.h>
#include <pthread.h>

#if defined(__STDC_NO_ATOMICS__)
#error "Alder runtime requires C11 <stdatomic.h> for foreign-thread entry"
#endif
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ALDER_MAGIC ((uint32_t)0x414c4452u) /* "ALDR" */

#define ALDER_MIN_SEGMENT ((size_t)8192)
#define ALDER_MAX_SEGMENT ((size_t)(1u << 20)) /* 1 MiB */
#define ALDER_SEGMENT_ALIGN ((size_t)16)

typedef struct AlderSegment {
    struct AlderSegment *next;
    uint64_t serial;
    size_t capacity; /* usable bytes in the data area */
    size_t used;     /* bytes consumed from the data area */
} AlderSegment;

struct AlderTableSlot {
    uint64_t generation; /* 0 means empty */
    uint8_t *elem;
};

struct AlderCleanupEntry {
    AlderCleanupEntry *next;
    AlderCleanupFn fn;
    AlderStepFn step;
    void *context;
    bool armed;
};

/* Serial allocation is shared by independent root domains entering from
 * foreign threads, so it uses C11 atomics. Structured concurrency remains out
 * of scope. */
static atomic_size_t g_live_allocations = ATOMIC_VAR_INIT(0);
static atomic_uint_fast64_t g_next_domain_serial = ATOMIC_VAR_INIT(1); /* 0 denotes exhaustion/invalid */
static atomic_uint_fast64_t g_next_segment_serial = ATOMIC_VAR_INIT(1);
static atomic_uint_fast64_t g_next_table_serial = ATOMIC_VAR_INIT(1); /* 0 is never a valid serial */

#if defined(ALDER_RUNTIME_TESTING)
static uint64_t g_test_domain_allocations_before_failure = UINT64_MAX;
static uint64_t g_table_slot_limit = 0;

void alder_runtime_test_fail_domain_alloc_after(uint64_t allowed_calls) {
    g_test_domain_allocations_before_failure = allowed_calls;
}

void alder_runtime_test_clear_domain_alloc_failure(void) {
    g_test_domain_allocations_before_failure = UINT64_MAX;
}

void alder_runtime_test_exhaust_segment_identities(void) {
    atomic_store_explicit(&g_next_segment_serial, 0, memory_order_relaxed);
}

void alder_runtime_test_set_table_slot_limit(uint64_t slots) {
    g_table_slot_limit = slots;
}
#endif

static void *rt_malloc(size_t size) {
    void *p = malloc(size);
    if (p != NULL) {
        (void)atomic_fetch_add_explicit(&g_live_allocations, 1, memory_order_relaxed);
    }
    return p;
}

static void rt_free(void *p) {
    if (p != NULL) {
        (void)atomic_fetch_sub_explicit(&g_live_allocations, 1, memory_order_relaxed);
        free(p);
    }
}

size_t alder_runtime_live_allocations(void) {
    return atomic_load_explicit(&g_live_allocations, memory_order_relaxed);
}

uint8_t alder_c_buffer_dummy[1] = {0};

#include <execinfo.h>
_Noreturn void alder_runtime_panic(const char *message) {
    void *frames[32];
    int n = backtrace(frames, 32);
    (void)fflush(NULL);
    fputs("alder runtime panic: ", stderr);
    fputs(message != NULL ? message : "(null)", stderr);
    fputc('\n', stderr);
    backtrace_symbols_fd(frames, n, 2);
    (void)fflush(stderr);
    _Exit(101);
}

static bool align_is_valid(size_t align) {
    return align != 0 && (align & (align - 1)) == 0;
}

static bool take_unique_serial(atomic_uint_fast64_t *next, uint64_t *out) {
    uint_fast64_t current = atomic_load_explicit(next, memory_order_relaxed);
    for (;;) {
        if (current == 0) {
            return false;
        }
        uint_fast64_t following = current == UINT64_MAX ? 0 : current + 1;
        if (atomic_compare_exchange_weak_explicit(next, &current, following,
                                                  memory_order_relaxed,
                                                  memory_order_relaxed)) {
            *out = (uint64_t)current;
            return true;
        }
    }
}

static uintptr_t align_up(uintptr_t addr, size_t align) {
    uintptr_t a = (uintptr_t)align;
    return (addr + (a - 1)) & ~(a - 1);
}

static uint8_t *segment_data(AlderSegment *seg) {
    return (uint8_t *)align_up((uintptr_t)(seg + 1), ALDER_SEGMENT_ALIGN);
}

/* ------------------------------------------------------------------ */
/* Storage domains                                                     */
/* ------------------------------------------------------------------ */

AlderCallbackOwner *alder_callback_owner_new(size_t context_size) {
    AlderCallbackOwner *owner;
    if (context_size == 0 || context_size > SIZE_MAX - sizeof(AlderCallbackOwner)) { return NULL; }
    owner = (AlderCallbackOwner *)calloc(1, sizeof(AlderCallbackOwner) + context_size);
    return owner;
}

void *alder_callback_owner_context(AlderCallbackOwner *owner) {
    if (owner == NULL) { alder_runtime_panic("callback owner is null"); }
    return (void *)owner->alder_context;
}

void alder_callback_owner_free(AlderCallbackOwner *owner) {
    free(owner);
}

bool alder_domain_init(AlderDomain *domain, AlderDomain *parent) {
    if (domain == NULL || domain->magic == ALDER_MAGIC) {
        return false; /* NULL or double init */
    }
    if (parent != NULL && parent->magic != ALDER_MAGIC) {
        return false;
    }
    uint64_t serial;
    if (!take_unique_serial(&g_next_domain_serial, &serial)) {
        return false;
    }
    *domain = (AlderDomain){0};
    domain->magic = ALDER_MAGIC;
    domain->serial = serial;
    domain->reset_epoch = 1;
    domain->parent = parent;
    if (parent != NULL) {
        domain->next_sibling = parent->children_head;
        parent->children_head = domain;
    }
    return true;
}

static AlderSegment *new_segment(size_t capacity) {
    size_t slack = ALDER_SEGMENT_ALIGN - 1;
    size_t alloc_size = capacity + sizeof(AlderSegment) + slack;
    if (alloc_size < capacity) {
        return NULL; /* overflow */
    }
    if (atomic_load_explicit(&g_next_segment_serial, memory_order_relaxed) == 0) {
        return NULL;
    }
    AlderSegment *seg = (AlderSegment *)rt_malloc(alloc_size);
    if (seg == NULL) {
        return NULL;
    }
    seg->next = NULL;
    (void)take_unique_serial(&g_next_segment_serial, &seg->serial);
    seg->capacity = capacity;
    seg->used = 0;
    return seg;
}

void *alder_domain_alloc(AlderDomain *domain, size_t size, size_t align) {
    if (domain == NULL || domain->magic != ALDER_MAGIC) {
        return NULL;
    }
    if (!align_is_valid(align)) {
        return NULL;
    }
    if (size == 0) {
        size = 1;
    }
    if (size > (size_t)-1 - (align - 1)) {
        return NULL; /* alignment slack overflows */
    }
#if defined(ALDER_RUNTIME_TESTING)
    if (g_test_domain_allocations_before_failure == 0) {
        return NULL;
    }
    if (g_test_domain_allocations_before_failure != UINT64_MAX) {
        g_test_domain_allocations_before_failure -= 1;
    }
#endif
    AlderSegment *seg = domain->segments_tail;
    for (;;) {
        if (seg != NULL) {
            uint8_t *data = segment_data(seg);
            uintptr_t ptr = align_up((uintptr_t)(data + seg->used), align);
            size_t start = (size_t)(ptr - (uintptr_t)data);
            if (start <= seg->capacity && size <= seg->capacity - start) {
                seg->used = start + size;
                return (void *)ptr;
            }
        }
        /* Grow: dedicated large segment or a doubling regular segment. */
        size_t needed = size + (align - 1);
        size_t capacity;
        if (needed > ALDER_MAX_SEGMENT) {
            capacity = needed; /* large allocation: exact-size segment */
        } else {
            size_t prev = (seg != NULL) ? seg->capacity : 0;
            size_t grown = prev > ALDER_MAX_SEGMENT / 2 ? ALDER_MAX_SEGMENT
                                                        : prev * 2;
            capacity = grown < ALDER_MIN_SEGMENT ? ALDER_MIN_SEGMENT : grown;
            if (capacity < needed) {
                capacity = needed;
            }
        }
        AlderSegment *fresh = new_segment(capacity);
        if (fresh == NULL) {
            return NULL; /* out of memory; domain unchanged */
        }
        if (seg == NULL) {
            domain->segments_head = fresh;
        } else {
            seg->next = fresh;
        }
        domain->segments_tail = fresh;
        domain->segment_count += 1;
        seg = fresh;
        /* Retry the allocation in the fresh segment. */
    }
}

AlderDomainMark alder_domain_mark(AlderDomain *domain) {
    AlderDomainMark mark = {0, 0, 0, 0};
    if (domain != NULL && domain->magic == ALDER_MAGIC) {
        mark.domain_serial = domain->serial;
        mark.reset_epoch = domain->reset_epoch;
        if (domain->segments_tail != NULL) {
            mark.segment_serial = domain->segments_tail->serial;
            mark.offset = domain->segments_tail->used;
        }
    }
    return mark;
}

bool alder_domain_reset(AlderDomain *domain, AlderDomainMark mark) {
    if (domain == NULL || domain->magic != ALDER_MAGIC) {
        return false;
    }
    if (mark.domain_serial != domain->serial ||
        mark.reset_epoch != domain->reset_epoch ||
        domain->reset_epoch == UINT64_MAX) {
        return false;
    }
    AlderSegment *seg = NULL;
    if (mark.segment_serial != 0) {
        seg = domain->segments_head;
        while (seg != NULL && seg->serial != mark.segment_serial) {
            seg = seg->next;
        }
        if (seg == NULL || mark.offset > seg->used) {
            return false;
        }
    } else if (mark.offset != 0) {
        return false;
    }
    AlderSegment *victim = (seg == NULL) ? domain->segments_head : seg->next;
    while (victim != NULL) {
        AlderSegment *next = victim->next;
        rt_free(victim);
        domain->segment_count -= 1;
        victim = next;
    }
    if (seg == NULL) {
        domain->segments_head = NULL;
        domain->segments_tail = NULL;
    } else {
        seg->next = NULL;
        seg->used = mark.offset;
        domain->segments_tail = seg;
    }
    domain->reset_epoch += 1;
    return true;
}

void alder_domain_destroy(AlderDomain *domain) {
    if (domain == NULL || domain->magic != ALDER_MAGIC) {
        return; /* no-op: uninitialized or already destroyed */
    }
    /* Children cannot outlive their parent. */
    AlderDomain *child = domain->children_head;
    while (child != NULL) {
        AlderDomain *next = child->next_sibling;
        alder_domain_destroy(child);
        child = next;
    }
    AlderSegment *seg = domain->segments_head;
    while (seg != NULL) {
        AlderSegment *next = seg->next;
        rt_free(seg);
        seg = next;
    }
    /* Unregister from the parent. */
    if (domain->parent != NULL) {
        AlderDomain **link = &domain->parent->children_head;
        while (*link != NULL && *link != domain) {
            link = &(*link)->next_sibling;
        }
        if (*link == domain) {
            *link = domain->next_sibling;
        }
    }
    *domain = (AlderDomain){0};
}

/* ------------------------------------------------------------------ */
/* Slices and bounds                                                   */
/* ------------------------------------------------------------------ */

/* alder_vec_construct_checked, alder_slice_index_checked,
 * alder_slice_range_checked, alder_i64_from_twos_bits and every checked
 * integer helper are static inline in alder.h; see the note there. */

bool alder_i64_from_f64(double v, int64_t *out) {
    if (out == NULL || v != v || v < -9223372036854775808.0 ||
        v >= 9223372036854775808.0) {
        return false;
    }
    *out = (int64_t)v; /* in-range conversion is defined */
    return true;
}

bool alder_u64_from_f64(double v, uint64_t *out) {
    if (out == NULL || v != v || v < 0.0 ||
        v >= 18446744073709551616.0) {
        return false;
    }
    *out = (uint64_t)v; /* in-range conversion is defined */
    return true;
}

/*
 * IEEE-754 float division with a defined zero divisor. Plain C11 leaves
 * x/0 undefined (Annex F defines it only under __STDC_IEC_559__, which is
 * not reliably defined on every tier-1 toolchain), so the generated
 * backend never emits a bare division: this helper branches on the divisor
 * and produces the IEEE result directly, signed infinity carrying the XOR
 * of the operand signs, NaN for 0/0 and for NaN operands. With a nonzero
 * divisor the plain division is defined and computes the IEEE quotient.
 */
double alder_f64_div(double a, double b) {
    if (b == 0.0) {
        if (a == 0.0 || a != a) {
            return (double)NAN;
        }
        if (signbit(a) != signbit(b)) {
            return -(double)INFINITY;
        }
        return (double)INFINITY;
    }
    return a / b;
}

float alder_f32_div(float a, float b) {
    if (b == 0.0f) {
        if (a == 0.0f || a != a) {
            return (float)NAN;
        }
        if (signbit(a) != signbit(b)) {
            return -(float)INFINITY;
        }
        return (float)INFINITY;
    }
    return a / b;
}

/* ------------------------------------------------------------------ */
/* Scoped cleanup                                                      */
/* ------------------------------------------------------------------ */

bool alder_cleanup_scope_begin(AlderCleanupScope *scope) {
    if (scope == NULL || scope->active) {
        return false;
    }
    scope->armed_head = NULL;
    scope->spent_head = NULL;
    scope->ran = false;
    scope->active = true;
    scope->cursor = false;
    return true;
}

bool alder_cleanup_scope_begin_adopting(AlderCleanupScope *scope) {
    if (scope == NULL) {
        return false;
    }
    if (scope->active) {
        return true;
    }
    scope->armed_head = NULL;
    scope->spent_head = NULL;
    scope->ran = false;
    scope->active = true;
    scope->cursor = false;
    return true;
}

static bool cleanup_push_entry(AlderCleanupScope *scope, AlderCleanupFn fn,
                               AlderStepFn step, void *context,
                               AlderCleanupId *out_id) {
    if (scope == NULL || !scope->active || out_id == NULL ||
        (fn == NULL && step == NULL)) {
        return false;
    }
    AlderCleanupEntry *entry = (AlderCleanupEntry *)rt_malloc(sizeof *entry);
    if (entry == NULL) {
        return false;
    }
    entry->fn = fn;
    entry->step = step;
    entry->context = context;
    entry->armed = true;
    entry->next = scope->armed_head; /* newest first: reverse registration
                                        order at run time */
    scope->armed_head = entry;
    *out_id = entry;
    return true;
}

bool alder_cleanup_push(AlderCleanupScope *scope, AlderCleanupFn fn,
                        void *context, AlderCleanupId *out_id) {
    return cleanup_push_entry(scope, fn, NULL, context, out_id);
}

bool alder_cleanup_push_step(AlderCleanupScope *scope, AlderStepFn driver,
                             void *context, AlderCleanupId *out_id) {
    return cleanup_push_entry(scope, NULL, driver, context, out_id);
}

bool alder_cleanup_disarm(AlderCleanupId id) {
    if (id == NULL || !id->armed) {
        return false;
    }
    id->armed = false;
    return true;
}

/* Move every remaining armed entry to the spent list. */
static void cleanup_spend_armed(AlderCleanupScope *scope) {
    if (scope->armed_head != NULL) {
        AlderCleanupEntry *tail = scope->armed_head;
        while (tail->next != NULL) {
            tail = tail->next;
        }
        tail->next = scope->spent_head;
        scope->spent_head = scope->armed_head;
        scope->armed_head = NULL;
    }
    scope->ran = true;
}

bool alder_cleanup_run(AlderCleanupScope *scope) {
    if (scope == NULL || !scope->active) {
        return false;
    }
    if (scope->cursor) {
        alder_runtime_panic("cleanup.run after a cleanup cursor");
    }
    AlderCleanupEntry *entry = scope->armed_head;
    while (entry != NULL) {
        AlderCleanupEntry *next = entry->next;
        if (entry->armed) {
            if (entry->step != NULL) {
                alder_runtime_panic("cleanup.run with a suspending entry");
            }
            entry->armed = false;
            entry->fn(entry->context);
        }
        entry = next;
    }
    /* Everything executed or skipped becomes spent; a later run has nothing
     * to execute, so every entry runs at most once. The spent list must be
     * preserved across runs so entries of earlier runs are still freed. */
    cleanup_spend_armed(scope);
    return true;
}

/* Consume disarmed entries and return the next armed entry, or NULL. */
static AlderCleanupEntry *cleanup_peek(AlderCleanupScope *scope) {
    while (scope->armed_head != NULL && !scope->armed_head->armed) {
        AlderCleanupEntry *skip = scope->armed_head;
        scope->armed_head = skip->next;
        skip->next = scope->spent_head;
        scope->spent_head = skip;
    }
    return scope->armed_head;
}

static bool cleanup_cursor(AlderCleanupScope *scope, AlderCleanupFn *fn,
                           AlderStepFn *step, void **context) {
    if (scope == NULL || !scope->active || context == NULL) {
        return false;
    }
    scope->cursor = true;
    AlderCleanupEntry *entry = cleanup_peek(scope);
    if (entry == NULL) {
        scope->ran = true;
        return false;
    }
    if (fn != NULL) {
        if (entry->step != NULL) {
            return false;
        }
        if (entry->fn == NULL) {
            alder_runtime_panic("cleanup entry has no hook");
        }
        *fn = entry->fn;
    } else {
        if (step == NULL || entry->step == NULL) {
            return false;
        }
        *step = entry->step;
    }
    *context = entry->context;
    entry->armed = false;
    scope->armed_head = entry->next;
    entry->next = scope->spent_head;
    scope->spent_head = entry;
    return true;
}

bool alder_cleanup_scope_next(AlderCleanupScope *scope, AlderCleanupFn *fn,
                              void **context) {
    if (fn == NULL) {
        return false;
    }
    return cleanup_cursor(scope, fn, NULL, context);
}

bool alder_cleanup_scope_next_step(AlderCleanupScope *scope,
                                   AlderStepFn *driver, void **context) {
    if (driver == NULL) {
        return false;
    }
    return cleanup_cursor(scope, NULL, driver, context);
}

bool alder_cleanup_end(AlderCleanupScope *scope) {
    if (scope == NULL || !scope->active) {
        return false;
    }
    bool ok = scope->ran && scope->armed_head == NULL;
    if (!ok) {
        /* Contract violation: run must precede end. Move leftovers to spent
         * and free everything so nothing leaks. */
        cleanup_spend_armed(scope);
    }
    AlderCleanupEntry *entry = scope->spent_head;
    while (entry != NULL) {
        AlderCleanupEntry *next = entry->next;
        rt_free(entry);
        entry = next;
    }
    scope->spent_head = NULL;
    scope->armed_head = NULL;
    scope->active = false;
    scope->cursor = false;
    return ok;
}

/* ------------------------------------------------------------------ */
/* Task runtime                                                        */
/* ------------------------------------------------------------------ */

/*
 * Executor architecture.
 *
 * The default configuration runs the gate 9.2 single-worker loop inline on
 * the thread that calls alder_executor_run. A configured executor runs:
 *
 *  - N pool workers sharing one FIFO lane; a task is dequeued by exactly one
 *    worker and owned by it until the task suspends or completes, so frames
 *    and activation stacks need no per-access locking;
 *  - one persistent local-lane thread for thread-affine tasks; a task's lane
 *    is fixed at creation and every local resumption runs on that thread;
 *  - one timer thread per run that owns the timer heap;
 *  - a fixed blocking pool whose workers persist across runs, because a
 *    cancellation may release a task while its C call is still running.
 *
 * Wakeups are always delivered through the task's stable latch. In threaded
 * mode a winning wakeup also pushes the wakeup token on a lock-free MPSC
 * list; a worker drains that list under the queue lock and routes each token
 * to the lane recorded in its task. The lane/queue links, latch, and timer
 * links are C11 atomics. The pool workers may pick up different tasks in a
 * different order on every run; results are deterministic whenever the
 * program itself orders its observations.
 */
#define ALDER_ACTIVATION_BLOCK ((size_t)32)
#define ALDER_EXECUTOR_MAX_WORKERS ((uint32_t)64)
#define ALDER_EXECUTOR_MAX_BLOCKING ((uint32_t)32)

typedef enum {
    ALDER_TASK_CREATED = 0,
    ALDER_TASK_RUNNABLE = 1,
    ALDER_TASK_RUNNING = 2,
    ALDER_TASK_PARKED = 3,
    ALDER_TASK_DONE = 4
} AlderTaskState;

typedef struct AlderActivation {
    AlderStepFn step;
    void *frame;
    AlderDomain *domain;
} AlderActivation;

typedef struct AlderActivationBlock {
    struct AlderActivationBlock *previous;
    size_t count;
    AlderActivation entries[ALDER_ACTIVATION_BLOCK];
} AlderActivationBlock;

typedef struct AlderLane {
    AlderTask *head;
    AlderTask *tail;
} AlderLane;

typedef struct AlderPoolWorker {
    pthread_t thread;
    bool started;
    bool idle;
    AlderLane *lane;
} AlderPoolWorker;

typedef struct AlderTimer AlderTimer;
typedef struct AlderBlockingEntry AlderBlockingEntry;
typedef struct AlderGroup AlderGroup;
typedef struct AlderTaskSlot AlderTaskSlot;

typedef enum {
    ALDER_TIMER_INSERT = 0,
    ALDER_TIMER_CANCEL_TASK = 1,
    ALDER_TIMER_ADVANCE = 2
} AlderTimerRequestKind;

typedef struct AlderTimerRequest {
    struct AlderTimerRequest *next;
    AlderTimerRequestKind kind;
    AlderTimer *timer;
    AlderTask *task;
    size_t fired;
    bool done;
} AlderTimerRequest;

struct AlderWakeup {
    atomic_bool latch;
    AlderTask *task;
    _Atomic(AlderWakeup *) signal_next;
};

struct AlderGroup {
    AlderGroup *next;
    AlderTask *head;
    uint64_t id;
};

struct AlderTaskSlot {
    AlderTask *task;
    uint32_t generation;
    uint32_t next_free;
};

struct AlderTimer {
    uint64_t deadline;
    uint64_t task_id;
    AlderWakeup *wakeup;
    AlderTask *task;
    size_t heap_index;
    _Atomic(AlderTimer *) task_prev;
    _Atomic(AlderTimer *) task_next;
    atomic_bool active;
    AlderTimerRequest request;
};

struct AlderBlockingEntry {
    AlderBlockingEntry *next;
    AlderTask *task;
    AlderBlockingFn fn;
    void *context;
    bool cancelled;
    bool shielded;
};

struct AlderTask {
    AlderWakeup wakeup;
    uint64_t id;
    AlderGroup *group;
    AlderTask *group_prev;
    AlderTask *group_next;
    atomic_int state;
    atomic_bool cancel_requested;
    atomic_bool queued;
    atomic_uint refs;
    uint32_t shield_depth;
    uint32_t wait_reason;
    uint32_t slot_index;
    AlderLane *lane;
    AlderActivationBlock *base;
    AlderActivationBlock *top_block;
    size_t depth;
    AlderTimer *timers_head;
    atomic_size_t timer_count;
    AlderTask *awaiter;
    bool awaited;
    AlderTask *awaiting;
    AlderStepFn pending_step;
    void *pending_frame;
    AlderDomain *pending_domain;
    bool pending_call;
    _Atomic(AlderTask *) run_next;
    bool released;
    AlderBlockingEntry *blocking_entry;
};

static _Thread_local AlderTask *g_current_task;

/* Default single-worker run queue. The same run_next link is reused by the
 * threaded lane queues. */
static atomic_flag g_run_lock = ATOMIC_FLAG_INIT;
static AlderTask *g_run_head;
static AlderTask *g_run_tail;

/* Task registry and groups. All mutations are serialized so pool workers and
 * the coordinator may create, resolve, and release concurrently. */
static pthread_mutex_t g_registry_lock = PTHREAD_MUTEX_INITIALIZER;
static AlderTaskSlot *g_task_slots;
static size_t g_task_slot_count;
static size_t g_task_slot_capacity;
static uint32_t g_task_free_head = UINT32_MAX;
static size_t g_live_tasks;
static uint32_t g_next_task_generation = 1;
static AlderGroup *g_groups;

/* Threaded executor state. */
static pthread_mutex_t g_queue_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_work_cond = PTHREAD_COND_INITIALIZER;
static pthread_cond_t g_idle_cond = PTHREAD_COND_INITIALIZER;
static _Atomic(AlderWakeup *) g_signal_head;
static AlderLane g_pool_lane;
static AlderLane g_local_lane;
static AlderPoolWorker g_pool_workers[ALDER_EXECUTOR_MAX_WORKERS];
static AlderPoolWorker g_local_worker;
static uint32_t g_pool_worker_count;
static bool g_executor_active;
static bool g_worker_stop;
static bool g_local_started;
static bool g_local_stop;
static pthread_t g_local_thread;
static bool g_threaded;
static AlderExecutorConfig g_config;

/* Timer heap. The inline executor owns it on the calling thread; in threaded
 * mode the timer thread owns it for the duration of a run. */
static AlderTimer **g_timer_heap;
static size_t g_timer_count;
static size_t g_timer_capacity;
static atomic_uint_fast64_t g_clock;
static atomic_bool g_executor_running;

/* Timer thread request channel. */
static pthread_mutex_t g_timer_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_timer_cond = PTHREAD_COND_INITIALIZER;
static pthread_cond_t g_timer_done_cond = PTHREAD_COND_INITIALIZER;
static AlderTimerRequest *g_timer_requests_head;
static AlderTimerRequest *g_timer_requests_tail;
static pthread_t g_timer_thread;
static bool g_timer_stop;
static bool g_timer_service_live;

/* Bounded blocking pool. Its workers persist across executor runs. */
static pthread_mutex_t g_blocking_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_blocking_cond = PTHREAD_COND_INITIALIZER;
static AlderBlockingEntry *g_blocking_head;
static AlderBlockingEntry *g_blocking_tail;
static pthread_t g_blocking_threads[ALDER_EXECUTOR_MAX_BLOCKING];
static uint32_t g_blocking_thread_count;
static size_t g_blocking_inflight;
static bool g_blocking_stop;


static AlderTask *current_task_checked(const char *message) {
    if (g_current_task == NULL) {
        alder_runtime_panic(message);
    }
    return g_current_task;
}

static uint64_t clock_load(void) {
    return (uint64_t)atomic_load_explicit(&g_clock, memory_order_relaxed);
}

static void clock_raise(uint64_t value) {
    uint_fast64_t current =
        atomic_load_explicit(&g_clock, memory_order_relaxed);
    while ((uint64_t)current < value) {
        if (atomic_compare_exchange_weak_explicit(
                &g_clock, &current, (uint_fast64_t)value,
                memory_order_relaxed, memory_order_relaxed)) {
            return;
        }
    }
}

static void task_free(AlderTask *task) {
    if (task->base != NULL || task->top_block != NULL || task->depth != 0) {
        alder_runtime_panic("task freed with a live activation stack");
    }
    if (task->timers_head != NULL ||
        atomic_load_explicit(&task->timer_count, memory_order_acquire) != 0) {
        alder_runtime_panic("task freed with a live registration");
    }
    if (task->pending_call) {
        alder_runtime_panic("task freed with a published callee");
    }
    if (task->blocking_entry != NULL) {
        alder_runtime_panic("task freed with a pending blocking entry");
    }
    rt_free(task);
}

/* Every owner, timer, in-flight blocking entry, and transient id operation
 * holds one reference. The spawner's reference is dropped by
 * alder_task_release; the record is freed by whichever holder drops last. */
static void task_ref(AlderTask *task) {
    (void)atomic_fetch_add_explicit(&task->refs, 1, memory_order_relaxed);
}

static void task_unref(AlderTask *task) {
    if (atomic_fetch_sub_explicit(&task->refs, 1, memory_order_acq_rel) == 1) {
        task_free(task);
    }
}

static void run_queue_push(AlderTask *task) {
    atomic_store_explicit(&task->run_next, NULL, memory_order_relaxed);
    while (atomic_flag_test_and_set_explicit(&g_run_lock, memory_order_acquire)) {
        /* spin */
    }
    if (g_run_tail == NULL) {
        g_run_head = task;
        g_run_tail = task;
    } else {
        atomic_store_explicit(&g_run_tail->run_next, task,
                              memory_order_release);
        g_run_tail = task;
    }
    atomic_flag_clear_explicit(&g_run_lock, memory_order_release);
}

static AlderTask *run_queue_pop(void) {
    while (atomic_flag_test_and_set_explicit(&g_run_lock, memory_order_acquire)) {
        /* spin */
    }
    AlderTask *task = g_run_head;
    if (task != NULL) {
        g_run_head = atomic_load_explicit(&task->run_next,
                                          memory_order_acquire);
        if (g_run_head == NULL) {
            g_run_tail = NULL;
        }
        atomic_store_explicit(&task->run_next, NULL, memory_order_relaxed);
    }
    atomic_flag_clear_explicit(&g_run_lock, memory_order_release);
    return task;
}

/* Lane operations run under g_queue_lock; the links stay atomic so the
 * wakeup token and timer paths can document their ordering without turning
 * every traversal into a lock acquisition. */
static void lane_push_locked(AlderLane *lane, AlderTask *task) {
    atomic_store_explicit(&task->run_next, NULL, memory_order_relaxed);
    if (lane->tail == NULL) {
        lane->head = task;
        lane->tail = task;
        return;
    }
    atomic_store_explicit(&lane->tail->run_next, task, memory_order_release);
    lane->tail = task;
}

static AlderTask *lane_pop_locked(AlderLane *lane) {
    AlderTask *task = lane->head;
    if (task == NULL) {
        return NULL;
    }
    AlderTask *next =
        atomic_load_explicit(&task->run_next, memory_order_acquire);
    lane->head = next;
    if (next == NULL) {
        lane->tail = NULL;
    }
    atomic_store_explicit(&task->run_next, NULL, memory_order_relaxed);
    return task;
}

static bool lane_empty_locked(const AlderLane *lane) {
    return lane->head == NULL;
}

static bool all_workers_idle_locked(void) {
    for (uint32_t i = 0; i < g_pool_worker_count; i++) {
        if (!g_pool_workers[i].idle) {
            return false;
        }
    }
    if (g_local_started && !g_local_worker.idle) {
        return false;
    }
    return true;
}

/* Drain the MPSC wakeup-token list and route each token to its lane. Called
 * with g_queue_lock held, which also serializes drainers. */
static void signal_drain_locked(void) {
    AlderWakeup *head =
        atomic_exchange_explicit(&g_signal_head, NULL, memory_order_acquire);
    if (head == NULL) {
        return;
    }
    AlderWakeup *reversed = NULL;
    while (head != NULL) {
        AlderWakeup *next = atomic_load_explicit(&head->signal_next,
                                                 memory_order_acquire);
        atomic_store_explicit(&head->signal_next, reversed,
                              memory_order_relaxed);
        reversed = head;
        head = next;
    }
    bool pushed = false;
    AlderWakeup *wakeup = reversed;
    while (wakeup != NULL) {
        AlderWakeup *next = atomic_load_explicit(&wakeup->signal_next,
                                                 memory_order_relaxed);
        AlderTask *task = wakeup->task;
        if (task != NULL &&
            atomic_load_explicit(&task->state, memory_order_acquire) ==
                ALDER_TASK_RUNNABLE) {
            bool expected = false;
            if (atomic_compare_exchange_strong_explicit(
                    &task->queued, &expected, true, memory_order_seq_cst,
                    memory_order_seq_cst)) {
                lane_push_locked(task->lane, task);
                pushed = true;
            }
        }
        atomic_store_explicit(&wakeup->signal_next, NULL, memory_order_relaxed);
        wakeup = next;
    }
    if (pushed) {
        pthread_cond_broadcast(&g_work_cond);
    }
}

/* Make a task runnable through its fixed lane. Inline mode keeps the gate 9.2
 * run queue exactly; threaded mode serializes lane insertion on the queue
 * lock and wakes a worker. */
static void executor_enqueue(AlderTask *task) {
    if (!g_threaded) {
        run_queue_push(task);
        return;
    }
    pthread_mutex_lock(&g_queue_lock);
    bool expected = false;
    if (atomic_compare_exchange_strong_explicit(
            &task->queued, &expected, true, memory_order_seq_cst,
            memory_order_seq_cst)) {
        lane_push_locked(task->lane, task);
        pthread_cond_broadcast(&g_work_cond);
    }
    pthread_mutex_unlock(&g_queue_lock);
}


static bool task_transition(AlderTask *task, int from, int to) {
    int expected = from;
    return atomic_compare_exchange_strong_explicit(
        &task->state, &expected, to, memory_order_seq_cst, memory_order_seq_cst);
}

static void task_enqueue_from(AlderTask *task, int from) {
    if (!task_transition(task, from, ALDER_TASK_RUNNABLE)) {
        alder_runtime_panic("task state transition failed");
    }
    executor_enqueue(task);
}

static AlderActivation *task_top(AlderTask *task) {
    if (task->top_block == NULL || task->top_block->count == 0) {
        alder_runtime_panic("task activation stack underflow");
    }
    return &task->top_block->entries[task->top_block->count - 1];
}

static void task_push(AlderTask *task, AlderStepFn step, void *frame,
                      AlderDomain *domain) {
    if (step == NULL || frame == NULL || domain == NULL) {
        alder_runtime_panic("task activation with a null field");
    }
    if (task->top_block == NULL ||
        task->top_block->count == ALDER_ACTIVATION_BLOCK) {
        AlderActivationBlock *block =
            (AlderActivationBlock *)rt_malloc(sizeof *block);
        if (block == NULL) {
            alder_runtime_panic("task activation allocation failure");
        }
        block->previous = task->top_block;
        block->count = 0;
        task->top_block = block;
        if (task->base == NULL) {
            task->base = block;
        }
    }
    AlderActivation *activation =
        &task->top_block->entries[task->top_block->count];
    activation->step = step;
    activation->frame = frame;
    activation->domain = domain;
    task->top_block->count += 1;
    task->depth += 1;
}

static void task_pop(AlderTask *task) {
    if (task->top_block == NULL || task->depth == 0) {
        alder_runtime_panic("task activation stack underflow");
    }
    AlderActivationBlock *block = task->top_block;
    block->count -= 1;
    task->depth -= 1;
    if (block->count == 0) {
        AlderActivationBlock *previous = block->previous;
        if (task->base == block) {
            task->base = previous;
        }
        task->top_block = previous;
        rt_free(block);
    }
}

static void task_slot_grow(void) {
    size_t next_capacity = g_task_slot_capacity == 0
                               ? (size_t)16
                               : g_task_slot_capacity * (size_t)2;
    if (next_capacity < g_task_slot_capacity ||
        next_capacity > SIZE_MAX / sizeof(AlderTaskSlot)) {
        alder_runtime_panic("task identity space exhausted");
    }
    AlderTaskSlot *slots =
        (AlderTaskSlot *)rt_malloc(next_capacity * sizeof *slots);
    if (slots == NULL) {
        alder_runtime_panic("task identity allocation failure");
    }
    if (g_task_slot_count > 0) {
        memcpy(slots, g_task_slots, g_task_slot_count * sizeof *slots);
    }
    for (size_t i = g_task_slot_count; i < next_capacity; i++) {
        slots[i].task = NULL;
        slots[i].generation = 0;
        slots[i].next_free = UINT32_MAX;
    }
    rt_free(g_task_slots);
    g_task_slots = slots;
    g_task_slot_capacity = next_capacity;
}

static void task_registry_insert(AlderTask *task) {
    size_t slot_index = 0;
    if (g_task_free_head != UINT32_MAX) {
        slot_index = (size_t)g_task_free_head;
        g_task_free_head = g_task_slots[slot_index].next_free;
    } else {
        if (g_task_slot_count == g_task_slot_capacity) {
            task_slot_grow();
        }
        if (g_task_slot_count >= (size_t)UINT32_MAX) {
            alder_runtime_panic("task identity space exhausted");
        }
        slot_index = g_task_slot_count;
        g_task_slot_count += 1;
    }
    AlderTaskSlot *slot = &g_task_slots[slot_index];
    uint32_t generation = g_next_task_generation;
    if (generation == 0) {
        alder_runtime_panic("task identity space exhausted");
    }
    g_next_task_generation = (uint32_t)(generation + 1u);
    slot->generation = generation;
    slot->task = task;
    slot->next_free = UINT32_MAX;
    task->slot_index = (uint32_t)slot_index;
    task->id = ((uint64_t)generation << 32) | (uint64_t)(slot_index + 1);
    g_live_tasks += 1;
}

static AlderTask *task_resolve(uint64_t id, const char *message) {
    if (id == 0) {
        alder_runtime_panic(message);
    }
    uint32_t index = (uint32_t)(id & UINT64_C(0xffffffff));
    uint32_t generation = (uint32_t)(id >> 32);
    if (index == 0) {
        alder_runtime_panic(message);
    }
    size_t slot_index = (size_t)index - 1;
    if (slot_index >= g_task_slot_count) {
        alder_runtime_panic(message);
    }
    AlderTaskSlot *slot = &g_task_slots[slot_index];
    if (slot->task == NULL || slot->generation != generation) {
        alder_runtime_panic(message);
    }
    return slot->task;
}

/* Resolve a generational id for a transient operation and retain the record
 * across the release of g_registry_lock. The caller drops the reference with
 * task_unref after it has finished touching the task. */
static AlderTask *task_resolve_retained(uint64_t id, const char *message) {
    AlderTask *task = task_resolve(id, message);
    task_ref(task);
    return task;
}

static void task_registry_remove(AlderTask *task) {
    AlderTaskSlot *slot = &g_task_slots[task->slot_index];
    slot->task = NULL;
    slot->next_free = g_task_free_head;
    g_task_free_head = task->slot_index;
    task->slot_index = UINT32_MAX;
    if (g_live_tasks == 0) {
        alder_runtime_panic("task registry underflow");
    }
    g_live_tasks -= 1;
    if (g_live_tasks == 0) {
        rt_free(g_task_slots);
        g_task_slots = NULL;
        g_task_slot_count = 0;
        g_task_slot_capacity = 0;
        g_task_free_head = UINT32_MAX;
    }
}

static AlderGroup *group_get(uint64_t id) {
    AlderGroup *group = g_groups;
    while (group != NULL) {
        if (group->id == id) {
            return group;
        }
        group = group->next;
    }
    group = (AlderGroup *)rt_malloc(sizeof *group);
    if (group == NULL) {
        alder_runtime_panic("task group allocation failure");
    }
    group->id = id;
    group->head = NULL;
    group->next = g_groups;
    g_groups = group;
    return group;
}

static void group_remove_if_empty(AlderGroup *group) {
    if (group->head != NULL) {
        return;
    }
    AlderGroup **link = &g_groups;
    while (*link != NULL) {
        if (*link == group) {
            *link = group->next;
            rt_free(group);
            return;
        }
        link = &(*link)->next;
    }
    alder_runtime_panic("task group link missing");
}

static void group_link(AlderGroup *group, AlderTask *task) {
    task->group = group;
    task->group_prev = NULL;
    task->group_next = group->head;
    if (group->head != NULL) {
        group->head->group_prev = task;
    }
    group->head = task;
}

static void group_unlink(AlderTask *task) {
    AlderGroup *group = task->group;
    if (task->group_prev != NULL) {
        task->group_prev->group_next = task->group_next;
    } else {
        group->head = task->group_next;
    }
    if (task->group_next != NULL) {
        task->group_next->group_prev = task->group_prev;
    }
    task->group = NULL;
    task->group_prev = NULL;
    task->group_next = NULL;
    group_remove_if_empty(group);
}

static bool timer_less(const AlderTimer *left, const AlderTimer *right) {
    if (left->deadline != right->deadline) {
        return left->deadline < right->deadline;
    }
    return left->task_id < right->task_id;
}

static void timer_swap(size_t left, size_t right) {
    AlderTimer *temporary = g_timer_heap[left];
    g_timer_heap[left] = g_timer_heap[right];
    g_timer_heap[right] = temporary;
    g_timer_heap[left]->heap_index = left;
    g_timer_heap[right]->heap_index = right;
}

static void timer_sift_up(size_t index) {
    while (index > 0) {
        size_t parent = (index - 1) / 2;
        if (!timer_less(g_timer_heap[index], g_timer_heap[parent])) {
            break;
        }
        timer_swap(index, parent);
        index = parent;
    }
}

static void timer_sift_down(size_t index) {
    for (;;) {
        size_t left = index * 2 + 1;
        size_t right = left + 1;
        size_t best = index;
        if (left < g_timer_count &&
            timer_less(g_timer_heap[left], g_timer_heap[best])) {
            best = left;
        }
        if (right < g_timer_count &&
            timer_less(g_timer_heap[right], g_timer_heap[best])) {
            best = right;
        }
        if (best == index) {
            break;
        }
        timer_swap(index, best);
        index = best;
    }
}

static void timer_heap_insert(AlderTimer *timer) {
    if (g_timer_count == g_timer_capacity) {
        size_t next_capacity = g_timer_capacity == 0
                                   ? (size_t)16
                                   : g_timer_capacity * (size_t)2;
        if (next_capacity < g_timer_capacity ||
            next_capacity > SIZE_MAX / sizeof(AlderTimer *)) {
            alder_runtime_panic("timer heap capacity exhausted");
        }
        AlderTimer **heap =
            (AlderTimer **)rt_malloc(next_capacity * sizeof *heap);
        if (heap == NULL) {
            alder_runtime_panic("timer heap allocation failure");
        }
        if (g_timer_count > 0) {
            memcpy(heap, g_timer_heap, g_timer_count * sizeof *heap);
        }
        rt_free(g_timer_heap);
        g_timer_heap = heap;
        g_timer_capacity = next_capacity;
    }
    timer->heap_index = g_timer_count;
    atomic_store_explicit(&timer->active, true, memory_order_release);
    g_timer_heap[g_timer_count] = timer;
    g_timer_count += 1;
    timer_sift_up(timer->heap_index);
}

static AlderTimer *timer_heap_remove_at(size_t index) {
    AlderTimer *removed = g_timer_heap[index];
    size_t last = g_timer_count - 1;
    if (index != last) {
        g_timer_heap[index] = g_timer_heap[last];
        g_timer_heap[index]->heap_index = index;
    }
    g_timer_count = last;
    removed->heap_index = SIZE_MAX;
    atomic_store_explicit(&removed->active, false, memory_order_release);
    if (index < g_timer_count) {
        timer_sift_down(index);
        timer_sift_up(index);
    }
    return removed;
}

/* Timer-list links are atomic because a timer can be cancelled or fired while
 * its task runs on another worker. The list itself is serialized by the timer
 * owner (the inline executor or g_timer_lock). */
static void task_timer_link(AlderTask *task, AlderTimer *timer) {
    timer->task = task;
    atomic_store_explicit(&timer->task_prev, NULL, memory_order_relaxed);
    atomic_store_explicit(&timer->task_next, task->timers_head,
                          memory_order_release);
    if (task->timers_head != NULL) {
        atomic_store_explicit(&task->timers_head->task_prev, timer,
                              memory_order_release);
    }
    task->timers_head = timer;
}

static void task_timer_unlink(AlderTimer *timer) {
    AlderTask *task = timer->task;
    AlderTimer *previous =
        atomic_load_explicit(&timer->task_prev, memory_order_acquire);
    AlderTimer *next = atomic_load_explicit(&timer->task_next,
                                            memory_order_acquire);
    if (previous != NULL) {
        atomic_store_explicit(&previous->task_next, next,
                              memory_order_release);
    } else {
        task->timers_head = next;
    }
    if (next != NULL) {
        atomic_store_explicit(&next->task_prev, previous,
                              memory_order_release);
    }
    timer->task = NULL;
    atomic_store_explicit(&timer->task_prev, NULL, memory_order_relaxed);
    atomic_store_explicit(&timer->task_next, NULL, memory_order_relaxed);
}

/* Unlink a timer from its task list, drop the registration reference, and
 * free it. The caller has already removed it from the heap when active. */
static void timer_finish(AlderTimer *timer) {
    AlderTask *task = timer->task;
    if (task == NULL) {
        rt_free(timer);
        return;
    }
    task_timer_unlink(timer);
    rt_free(timer);
    (void)atomic_fetch_sub_explicit(&task->timer_count, 1,
                                    memory_order_acq_rel);
    task_unref(task);
}

/* Inline-mode timer teardown: the executing thread owns the heap. */
static void timer_destroy(AlderTimer *timer) {
    if (atomic_load_explicit(&timer->active, memory_order_acquire)) {
        (void)timer_heap_remove_at(timer->heap_index);
    }
    timer_finish(timer);
}

/* Remove every due timer from the heap and signal it. The timer owner (the
 * inline executor or the timer thread) is the only caller; it raises the
 * virtual clock to the earliest deadline exactly like the gate 9.2 loop. */
static size_t timer_fire_due(void) {
    if (g_timer_count == 0) {
        return 0;
    }
    clock_raise(g_timer_heap[0]->deadline);
    uint64_t clock = clock_load();
    size_t fired = 0;
    while (g_timer_count > 0 && g_timer_heap[0]->deadline <= clock) {
        AlderTimer *due = timer_heap_remove_at(0);
        AlderWakeup *wakeup = due->wakeup;
        AlderTask *task = due->task;
        task_timer_unlink(due);
        alder_wakeup_signal(wakeup);
        rt_free(due);
        (void)atomic_fetch_sub_explicit(&task->timer_count, 1,
                                        memory_order_acq_rel);
        task_unref(task);
        fired += 1;
    }
    return fired;
}

static void timer_request_push_locked(AlderTimerRequest *request) {
    request->next = NULL;
    if (g_timer_requests_tail == NULL) {
        g_timer_requests_head = request;
    } else {
        g_timer_requests_tail->next = request;
    }
    g_timer_requests_tail = request;
    pthread_cond_broadcast(&g_timer_cond);
}

/* Process one timer request. The timer thread holds g_timer_lock for the
 * whole call, so the heap and the per-task timer lists have one owner while
 * a request runs. A completed task waits here until its registrations are
 * gone, which preserves alder_task_release's drained-registration rule. */
static void timer_process_request(AlderTimerRequest *request) {
    switch (request->kind) {
    case ALDER_TIMER_INSERT:
        timer_heap_insert(request->timer);
        break;
    case ALDER_TIMER_CANCEL_TASK: {
        AlderTask *task = request->task;
        while (task->timers_head != NULL) {
            AlderTimer *timer = task->timers_head;
            if (atomic_load_explicit(&timer->active, memory_order_acquire)) {
                (void)timer_heap_remove_at(timer->heap_index);
            }
            timer_finish(timer);
        }
        break;
    }
    case ALDER_TIMER_ADVANCE:
        request->fired = timer_fire_due();
        break;
    default:
        alder_runtime_panic("timer request with an invalid kind");
    }
}

static void *timer_thread_main(void *context) {
    (void)context;
    pthread_mutex_lock(&g_timer_lock);
    for (;;) {
        while (g_timer_requests_head == NULL && !g_timer_stop) {
            pthread_cond_wait(&g_timer_cond, &g_timer_lock);
        }
        if (g_timer_requests_head == NULL && g_timer_stop) {
            break;
        }
        AlderTimerRequest *request = g_timer_requests_head;
        g_timer_requests_head = request->next;
        if (g_timer_requests_head == NULL) {
            g_timer_requests_tail = NULL;
        }
        request->next = NULL;
        bool synchronous = request->kind != ALDER_TIMER_INSERT;
        timer_process_request(request);
        if (synchronous) {
            request->done = true;
            pthread_cond_broadcast(&g_timer_done_cond);
        }
    }
    pthread_mutex_unlock(&g_timer_lock);
    return NULL;
}

static void timer_service_start(void) {
    pthread_mutex_lock(&g_timer_lock);
    g_timer_requests_head = NULL;
    g_timer_requests_tail = NULL;
    g_timer_stop = false;
    g_timer_service_live = true;
    pthread_mutex_unlock(&g_timer_lock);
    if (pthread_create(&g_timer_thread, NULL, timer_thread_main, NULL) != 0) {
        alder_runtime_panic("timer thread creation failure");
    }
}

static void timer_service_stop(void) {
    pthread_mutex_lock(&g_timer_lock);
    g_timer_stop = true;
    pthread_cond_broadcast(&g_timer_cond);
    pthread_mutex_unlock(&g_timer_lock);
    if (pthread_join(g_timer_thread, NULL) != 0) {
        alder_runtime_panic("timer thread join failure");
    }
    pthread_mutex_lock(&g_timer_lock);
    g_timer_service_live = false;
    pthread_mutex_unlock(&g_timer_lock);
}

static void timer_service_cancel(AlderTask *task) {
    if (!g_threaded) {
        while (task->timers_head != NULL) {
            timer_destroy(task->timers_head);
        }
        return;
    }
    pthread_mutex_lock(&g_timer_lock);
    if (!g_timer_service_live) {
        while (task->timers_head != NULL) {
            timer_destroy(task->timers_head);
        }
        pthread_mutex_unlock(&g_timer_lock);
        return;
    }
    AlderTimerRequest request;
    memset(&request, 0, sizeof request);
    request.kind = ALDER_TIMER_CANCEL_TASK;
    request.task = task;
    timer_request_push_locked(&request);
    while (!request.done) {
        pthread_cond_wait(&g_timer_done_cond, &g_timer_lock);
    }
    pthread_mutex_unlock(&g_timer_lock);
}

static size_t timer_service_advance(void) {
    if (!g_threaded) {
        return timer_fire_due();
    }
    pthread_mutex_lock(&g_timer_lock);
    if (!g_timer_service_live) {
        size_t fired = timer_fire_due();
        pthread_mutex_unlock(&g_timer_lock);
        return fired;
    }
    AlderTimerRequest request;
    memset(&request, 0, sizeof request);
    request.kind = ALDER_TIMER_ADVANCE;
    timer_request_push_locked(&request);
    while (!request.done) {
        pthread_cond_wait(&g_timer_done_cond, &g_timer_lock);
    }
    size_t fired = request.fired;
    pthread_mutex_unlock(&g_timer_lock);
    return fired;
}

static void task_park(AlderTask *task) {
    if (atomic_exchange_explicit(&task->wakeup.latch, false,
                                 memory_order_seq_cst)) {
        task_enqueue_from(task, ALDER_TASK_RUNNING);
        return;
    }
    if (!task_transition(task, ALDER_TASK_RUNNING, ALDER_TASK_PARKED)) {
        return;
    }
    if (atomic_exchange_explicit(&task->wakeup.latch, false,
                                 memory_order_seq_cst)) {
        int expected = ALDER_TASK_PARKED;
        if (atomic_compare_exchange_strong_explicit(
                &task->state, &expected, ALDER_TASK_RUNNABLE,
                memory_order_seq_cst, memory_order_seq_cst)) {
            executor_enqueue(task);
        }
    }
}

static void task_complete(AlderTask *task) {
    timer_service_cancel(task);
    AlderTask *waiter = NULL;
    pthread_mutex_lock(&g_registry_lock);
    if (task->awaiting != NULL) {
        task->awaiting->awaiter = NULL;
        task->awaiting = NULL;
    }
    task->wait_reason = ALDER_WAIT_NONE;
    if (task->awaiter != NULL) {
        waiter = task->awaiter;
        task->awaiter = NULL;
        waiter->awaiting = NULL;
    }
    /* Publishing DONE last under the registry lock lets a spawner release the
     * record as soon as it observes completion: no completing worker touches
     * the record after this store and the unlock. */
    atomic_store_explicit(&task->state, ALDER_TASK_DONE,
                          memory_order_release);
    pthread_mutex_unlock(&g_registry_lock);
    if (waiter != NULL) {
        alder_wakeup_signal(&waiter->wakeup);
    }
}

static void executor_run_task(AlderTask *task) {
    for (;;) {
        AlderActivation *activation = task_top(task);
        AlderStepStatus status = activation->step(
            task, activation->domain, activation->frame, activation->domain);
        switch (status) {
        case ALDER_STEP_DONE:
            if (task->pending_call) {
                alder_runtime_panic("task.call publication without a call status");
            }
            if (task->depth == 1) {
                if (task->shield_depth != 0) {
                    alder_runtime_panic("task root done with a raised shield");
                }
                task_pop(task);
                task_complete(task);
            } else {
                task_pop(task);
                task_enqueue_from(task, ALDER_TASK_RUNNING);
            }
            return;
        case ALDER_STEP_CALL: {
            if (!task->pending_call) {
                alder_runtime_panic("step.call without a task.call publication");
            }
            AlderStepFn callee = task->pending_step;
            void *callee_frame = task->pending_frame;
            AlderDomain *callee_domain = task->pending_domain;
            task->pending_step = NULL;
            task->pending_frame = NULL;
            task->pending_domain = NULL;
            task->pending_call = false;
            task_push(task, callee, callee_frame, callee_domain);
            continue;
        }
        case ALDER_STEP_PARK:
            if (task->pending_call) {
                alder_runtime_panic("task.call publication without a call status");
            }
            task_park(task);
            return;
        case ALDER_STEP_CANCELLED:
            if (task->pending_call) {
                alder_runtime_panic("task.call publication without a call status");
            }
            if (task->depth == 1) {
                task_pop(task);
                task_complete(task);
            } else {
                task_pop(task);
                task_enqueue_from(task, ALDER_TASK_RUNNING);
            }
            return;
        default:
            alder_runtime_panic("step returned an invalid status");
        }
    }
}

/* 0 = retry, 1 = all complete, 2 = quiescent. The caller holds
 * g_registry_lock. Threaded callers also hold g_queue_lock and pass
 * recover=true so a runnable task whose wakeup token is still in flight can
 * be routed to its lane without waiting for another drain. */
static int executor_scan_locked(size_t *blocked_count, bool recover) {
    bool retry = false;
    size_t blocked = 0;
    for (size_t i = 0; i < g_task_slot_count; i++) {
        AlderTask *task = g_task_slots[i].task;
        if (task == NULL) {
            continue;
        }
        int state = atomic_load_explicit(&task->state, memory_order_seq_cst);
        if (state == ALDER_TASK_DONE) {
            continue;
        }
        if (state == ALDER_TASK_RUNNABLE) {
            retry = true;
            if (recover) {
                bool expected = false;
                if (atomic_compare_exchange_strong_explicit(
                        &task->queued, &expected, true, memory_order_seq_cst,
                        memory_order_seq_cst)) {
                    lane_push_locked(task->lane, task);
                }
            }
            continue;
        }
        if (state == ALDER_TASK_PARKED &&
            atomic_load_explicit(&task->wakeup.latch, memory_order_seq_cst)) {
            retry = true;
            if (recover) {
                int expected = ALDER_TASK_PARKED;
                if (atomic_compare_exchange_strong_explicit(
                        &task->state, &expected, ALDER_TASK_RUNNABLE,
                        memory_order_seq_cst, memory_order_seq_cst)) {
                    bool queued = false;
                    if (atomic_compare_exchange_strong_explicit(
                            &task->queued, &queued, true, memory_order_seq_cst,
                            memory_order_seq_cst)) {
                        lane_push_locked(task->lane, task);
                    }
                }
            }
            continue;
        }
        if (recover && state == ALDER_TASK_RUNNING) {
            alder_runtime_panic("executor task left running");
        }
        blocked += 1;
    }
    *blocked_count = blocked;
    if (retry) {
        return 0;
    }
    if (blocked == 0) {
        return 1;
    }
    return 2;
}

static int blocked_compare(const void *left, const void *right) {
    const AlderBlockedTask *a = (const AlderBlockedTask *)left;
    const AlderBlockedTask *b = (const AlderBlockedTask *)right;
    if (a->task_id < b->task_id) {
        return -1;
    }
    if (a->task_id > b->task_id) {
        return 1;
    }
    return 0;
}

static void executor_report_idle(const AlderExecutorHooks *hooks,
                                 size_t count) {
    if (hooks == NULL || hooks->on_idle == NULL || count == 0) {
        return;
    }
    if (count > SIZE_MAX / sizeof(AlderBlockedTask)) {
        alder_runtime_panic("executor idle report is too large");
    }
    AlderBlockedTask *blocked =
        (AlderBlockedTask *)rt_malloc(count * sizeof *blocked);
    if (blocked == NULL) {
        alder_runtime_panic("executor idle report allocation failure");
    }
    size_t used = 0;
    pthread_mutex_lock(&g_registry_lock);
    for (size_t i = 0; i < g_task_slot_count && used < count; i++) {
        AlderTask *task = g_task_slots[i].task;
        if (task == NULL) {
            continue;
        }
        int state = atomic_load_explicit(&task->state, memory_order_seq_cst);
        if (state == ALDER_TASK_DONE) {
            continue;
        }
        if (state == ALDER_TASK_RUNNABLE) {
            continue;
        }
        if (state == ALDER_TASK_PARKED &&
            atomic_load_explicit(&task->wakeup.latch, memory_order_seq_cst)) {
            continue;
        }
        blocked[used].task_id = task->id;
        blocked[used].wait_reason = task->wait_reason;
        used += 1;
    }
    pthread_mutex_unlock(&g_registry_lock);
    if (used > 0) {
        qsort(blocked, used, sizeof *blocked, blocked_compare);
        hooks->on_idle(hooks->context, blocked, used);
    }
    rt_free(blocked);
}

static void executor_seed_clock(const AlderExecutorHooks *hooks) {
    if (hooks != NULL && hooks->now != NULL) {
        clock_raise(hooks->now(hooks->context));
    }
}

static void executor_enter(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(
            &g_executor_running, &expected, true, memory_order_seq_cst,
            memory_order_seq_cst)) {
        alder_runtime_panic("executor.run re-entered");
    }
}

static void executor_leave(void) {
    atomic_store_explicit(&g_executor_running, false, memory_order_seq_cst);
}

static void executor_free_empty_timer_heap(void) {
    if (g_timer_count == 0 && g_timer_heap != NULL) {
        rt_free(g_timer_heap);
        g_timer_heap = NULL;
        g_timer_capacity = 0;
    }
}

static bool executor_run_threaded(const AlderExecutorHooks *hooks);

bool alder_executor_run(const AlderExecutorHooks *hooks) {
    if (g_threaded) {
        return executor_run_threaded(hooks);
    }
    executor_enter();
    executor_seed_clock(hooks);
    bool all_done = false;
    for (;;) {
        executor_seed_clock(hooks);
        AlderTask *task = run_queue_pop();
        if (task == NULL) {
            if (g_timer_count > 0) {
                (void)timer_fire_due();
                continue;
            }
            size_t blocked_count = 0;
            pthread_mutex_lock(&g_registry_lock);
            int idle = executor_scan_locked(&blocked_count, false);
            pthread_mutex_unlock(&g_registry_lock);
            if (idle == 0) {
                continue;
            }
            if (idle == 1) {
                all_done = true;
                break;
            }
            executor_report_idle(hooks, blocked_count);
            all_done = false;
            break;
        }
        if (!task_transition(task, ALDER_TASK_RUNNABLE, ALDER_TASK_RUNNING)) {
            alder_runtime_panic("executor dequeued a non-runnable task");
        }
        (void)atomic_exchange_explicit(&task->wakeup.latch, false,
                                       memory_order_seq_cst);
        task->wait_reason = ALDER_WAIT_NONE;
        g_current_task = task;
        executor_run_task(task);
        g_current_task = NULL;
    }
    executor_free_empty_timer_heap();
    executor_leave();
    return all_done;
}

/* ------------------------------------------------------------------ */
/* Threaded pool, local lane, and blocking pool                        */
/* ------------------------------------------------------------------ */

static AlderTask *executor_pop(AlderPoolWorker *worker) {
    pthread_mutex_lock(&g_queue_lock);
    for (;;) {
        if (g_worker_stop) {
            worker->idle = false;
            pthread_mutex_unlock(&g_queue_lock);
            return NULL;
        }
        signal_drain_locked();
        AlderTask *task = lane_pop_locked(worker->lane);
        if (task != NULL) {
            atomic_store_explicit(&task->queued, false, memory_order_seq_cst);
            worker->idle = false;
            pthread_mutex_unlock(&g_queue_lock);
            return task;
        }
        worker->idle = true;
        if (all_workers_idle_locked()) {
            pthread_cond_broadcast(&g_idle_cond);
        }
        pthread_cond_wait(&g_work_cond, &g_queue_lock);
        worker->idle = false;
    }
}

static void *pool_worker_main(void *context) {
    AlderPoolWorker *worker = (AlderPoolWorker *)context;
    for (;;) {
        AlderTask *task = executor_pop(worker);
        if (task == NULL) {
            return NULL;
        }
        if (!task_transition(task, ALDER_TASK_RUNNABLE, ALDER_TASK_RUNNING)) {
            alder_runtime_panic("executor dequeued a non-runnable task");
        }
        (void)atomic_exchange_explicit(&task->wakeup.latch, false,
                                       memory_order_seq_cst);
        task->wait_reason = ALDER_WAIT_NONE;
        g_current_task = task;
        executor_run_task(task);
        g_current_task = NULL;
    }
}

/* The local lane is a single persistent thread. It runs only while an
 * executor run is active, so local tasks keep one OS thread across runs
 * without executing outside alder_executor_run. */
static AlderTask *local_lane_pop(AlderPoolWorker *worker) {
    pthread_mutex_lock(&g_queue_lock);
    for (;;) {
        if (g_local_stop) {
            worker->idle = true;
            pthread_mutex_unlock(&g_queue_lock);
            return NULL;
        }
        if (g_executor_active) {
            signal_drain_locked();
            AlderTask *task = lane_pop_locked(&g_local_lane);
            if (task != NULL) {
                atomic_store_explicit(&task->queued, false,
                                      memory_order_seq_cst);
                worker->idle = false;
                pthread_mutex_unlock(&g_queue_lock);
                return task;
            }
        }
        worker->idle = true;
        if (all_workers_idle_locked()) {
            pthread_cond_broadcast(&g_idle_cond);
        }
        pthread_cond_wait(&g_work_cond, &g_queue_lock);
        worker->idle = false;
    }
}

static void *local_worker_main(void *context) {
    AlderPoolWorker *worker = (AlderPoolWorker *)context;
    for (;;) {
        AlderTask *task = local_lane_pop(worker);
        if (task == NULL) {
            return NULL;
        }
        if (!task_transition(task, ALDER_TASK_RUNNABLE, ALDER_TASK_RUNNING)) {
            alder_runtime_panic("local executor dequeued a non-runnable task");
        }
        (void)atomic_exchange_explicit(&task->wakeup.latch, false,
                                       memory_order_seq_cst);
        task->wait_reason = ALDER_WAIT_NONE;
        g_current_task = task;
        executor_run_task(task);
        g_current_task = NULL;
    }
}

static void local_lane_start(void) {
    pthread_mutex_lock(&g_queue_lock);
    g_local_stop = false;
    g_local_started = true;
    g_local_worker.idle = false;
    g_local_worker.lane = &g_local_lane;
    pthread_mutex_unlock(&g_queue_lock);
    if (pthread_create(&g_local_thread, NULL, local_worker_main,
                       &g_local_worker) != 0) {
        alder_runtime_panic("local lane thread creation failure");
    }
}

static void local_lane_stop(void) {
    pthread_mutex_lock(&g_queue_lock);
    if (!g_local_started) {
        pthread_mutex_unlock(&g_queue_lock);
        return;
    }
    g_local_stop = true;
    pthread_cond_broadcast(&g_work_cond);
    pthread_mutex_unlock(&g_queue_lock);
    if (pthread_join(g_local_thread, NULL) != 0) {
        alder_runtime_panic("local lane thread join failure");
    }
    pthread_mutex_lock(&g_queue_lock);
    g_local_started = false;
    g_local_worker.idle = true;
    pthread_mutex_unlock(&g_queue_lock);
}

static void executor_start_pool_workers(void) {
    for (uint32_t i = 0; i < g_pool_worker_count; i++) {
        if (pthread_create(&g_pool_workers[i].thread, NULL, pool_worker_main,
                           &g_pool_workers[i]) != 0) {
            alder_runtime_panic("executor worker creation failure");
        }
    }
}

static void executor_join_pool_workers(void) {
    for (uint32_t i = 0; i < g_pool_worker_count; i++) {
        if (g_pool_workers[i].started) {
            if (pthread_join(g_pool_workers[i].thread, NULL) != 0) {
                alder_runtime_panic("executor worker join failure");
            }
        }
    }
    pthread_mutex_lock(&g_queue_lock);
    for (uint32_t i = 0; i < g_pool_worker_count; i++) {
        g_pool_workers[i].started = false;
    }
    g_pool_worker_count = 0;
    pthread_mutex_unlock(&g_queue_lock);
}

static bool executor_run_threaded(const AlderExecutorHooks *hooks) {
    executor_enter();
    executor_seed_clock(hooks);
    timer_service_start();
    pthread_mutex_lock(&g_queue_lock);
    g_executor_active = true;
    g_worker_stop = false;
    g_pool_worker_count = g_config.workers;
    for (uint32_t i = 0; i < g_pool_worker_count; i++) {
        g_pool_workers[i].started = true;
        g_pool_workers[i].idle = false;
        g_pool_workers[i].lane = &g_pool_lane;
    }
    /* The persistent local-lane thread may already be waiting; a run that
     * starts with local work must wake it. */
    pthread_cond_broadcast(&g_work_cond);
    pthread_mutex_unlock(&g_queue_lock);
    executor_start_pool_workers();
    bool all_done = false;
    for (;;) {
        executor_seed_clock(hooks);
        pthread_mutex_lock(&g_queue_lock);
        for (;;) {
            signal_drain_locked();
            if (!all_workers_idle_locked() ||
                !lane_empty_locked(&g_pool_lane) ||
                !lane_empty_locked(&g_local_lane)) {
                pthread_cond_wait(&g_idle_cond, &g_queue_lock);
                continue;
            }
            break;
        }
        size_t blocked_count = 0;
        pthread_mutex_lock(&g_registry_lock);
        int idle = executor_scan_locked(&blocked_count, true);
        pthread_mutex_unlock(&g_registry_lock);
        if (idle == 0) {
            pthread_cond_broadcast(&g_work_cond);
            pthread_mutex_unlock(&g_queue_lock);
            continue;
        }
        pthread_mutex_unlock(&g_queue_lock);
        if (idle == 1) {
            all_done = true;
            break;
        }
        if (timer_service_advance() > 0) {
            continue;
        }
        executor_report_idle(hooks, blocked_count);
        all_done = false;
        break;
    }
    pthread_mutex_lock(&g_queue_lock);
    g_worker_stop = true;
    g_executor_active = false;
    pthread_cond_broadcast(&g_work_cond);
    pthread_mutex_unlock(&g_queue_lock);
    executor_join_pool_workers();
    timer_service_stop();
    executor_free_empty_timer_heap();
    executor_leave();
    return all_done;
}

/* ------------------------------------------------------------------ */
/* Blocking pool                                                       */
/* ------------------------------------------------------------------ */

static void *blocking_worker_main(void *context) {
    (void)context;
    pthread_mutex_lock(&g_blocking_lock);
    for (;;) {
        while (g_blocking_head == NULL && !g_blocking_stop) {
            pthread_cond_wait(&g_blocking_cond, &g_blocking_lock);
        }
        if (g_blocking_head == NULL && g_blocking_stop) {
            break;
        }
        AlderBlockingEntry *entry = g_blocking_head;
        g_blocking_head = entry->next;
        if (g_blocking_head == NULL) {
            g_blocking_tail = NULL;
        }
        AlderTask *task = entry->task;
        if (task->blocking_entry == entry) {
            task->blocking_entry = NULL;
        }
        bool cancelled = entry->cancelled;
        pthread_mutex_unlock(&g_blocking_lock);
        if (!cancelled) {
            entry->fn(entry->context);
        }
        alder_wakeup_signal(&task->wakeup);
        task_unref(task);
        rt_free(entry);
        pthread_mutex_lock(&g_blocking_lock);
        if (g_blocking_inflight == 0) {
            alder_runtime_panic("blocking pool completion underflow");
        }
        g_blocking_inflight -= 1;
        pthread_cond_broadcast(&g_blocking_cond);
    }
    pthread_mutex_unlock(&g_blocking_lock);
    return NULL;
}

static void blocking_pool_start(uint32_t count) {
    pthread_mutex_lock(&g_blocking_lock);
    g_blocking_stop = false;
    g_blocking_thread_count = count;
    g_blocking_head = NULL;
    g_blocking_tail = NULL;
    g_blocking_inflight = 0;
    pthread_mutex_unlock(&g_blocking_lock);
    for (uint32_t i = 0; i < count; i++) {
        if (pthread_create(&g_blocking_threads[i], NULL, blocking_worker_main,
                           NULL) != 0) {
            alder_runtime_panic("blocking worker creation failure");
        }
    }
}

static void blocking_pool_stop(void) {
    pthread_mutex_lock(&g_blocking_lock);
    uint32_t count = g_blocking_thread_count;
    if (count == 0) {
        pthread_mutex_unlock(&g_blocking_lock);
        return;
    }
    if (g_blocking_inflight != 0) {
        pthread_mutex_unlock(&g_blocking_lock);
        alder_runtime_panic("blocking pool stopped with a live entry");
    }
    g_blocking_stop = true;
    pthread_cond_broadcast(&g_blocking_cond);
    pthread_mutex_unlock(&g_blocking_lock);
    for (uint32_t i = 0; i < count; i++) {
        if (pthread_join(g_blocking_threads[i], NULL) != 0) {
            alder_runtime_panic("blocking worker join failure");
        }
    }
    pthread_mutex_lock(&g_blocking_lock);
    g_blocking_thread_count = 0;
    pthread_mutex_unlock(&g_blocking_lock);
}

bool alder_task_blocking(AlderBlockingFn fn, void *context) {
    AlderTask *task = current_task_checked("task.blocking outside a step");
    if (fn == NULL) {
        alder_runtime_panic("task.blocking with a null entry");
    }
    pthread_mutex_lock(&g_blocking_lock);
    if (g_blocking_thread_count == 0) {
        pthread_mutex_unlock(&g_blocking_lock);
        return false;
    }
    if (task->blocking_entry != NULL) {
        pthread_mutex_unlock(&g_blocking_lock);
        alder_runtime_panic("task.blocking with an entry already pending");
    }
    AlderBlockingEntry *entry =
        (AlderBlockingEntry *)rt_malloc(sizeof *entry);
    if (entry == NULL) {
        alder_runtime_panic("task.blocking allocation failure");
    }
    entry->next = NULL;
    entry->task = task;
    entry->fn = fn;
    entry->context = context;
    entry->shielded = task->shield_depth > 0;
    entry->cancelled =
        !entry->shielded &&
        atomic_load_explicit(&task->cancel_requested, memory_order_seq_cst);
    task->blocking_entry = entry;
    task_ref(task);
    g_blocking_inflight += 1;
    if (g_blocking_tail == NULL) {
        g_blocking_head = entry;
    } else {
        g_blocking_tail->next = entry;
    }
    g_blocking_tail = entry;
    pthread_cond_broadcast(&g_blocking_cond);
    pthread_mutex_unlock(&g_blocking_lock);
    return true;
}

bool alder_executor_configure(const AlderExecutorConfig *config) {
    if (atomic_load_explicit(&g_executor_running, memory_order_acquire)) {
        return false;
    }
    pthread_mutex_lock(&g_blocking_lock);
    bool blocking_busy = g_blocking_inflight != 0;
    pthread_mutex_unlock(&g_blocking_lock);
    if (blocking_busy) {
        return false;
    }
    pthread_mutex_lock(&g_registry_lock);
    bool live = g_live_tasks != 0;
    pthread_mutex_unlock(&g_registry_lock);
    if (live) {
        return false;
    }
    pthread_mutex_lock(&g_timer_lock);
    bool timers = g_timer_count != 0;
    pthread_mutex_unlock(&g_timer_lock);
    if (timers) {
        return false;
    }
    pthread_mutex_lock(&g_queue_lock);
    bool queued = !lane_empty_locked(&g_pool_lane) ||
                  !lane_empty_locked(&g_local_lane);
    bool active = g_executor_active;
    pthread_mutex_unlock(&g_queue_lock);
    if (queued || active) {
        return false;
    }
    if (config != NULL &&
        (config->workers == 0 ||
         config->workers > ALDER_EXECUTOR_MAX_WORKERS ||
         config->blocking_workers > ALDER_EXECUTOR_MAX_BLOCKING)) {
        return false;
    }
    local_lane_stop();
    blocking_pool_stop();
    if (config == NULL) {
        g_config = (AlderExecutorConfig){0};
        g_threaded = false;
        return true;
    }
    g_config = *config;
    g_threaded = true;
    if (g_config.local_lane) {
        local_lane_start();
    }
    if (g_config.blocking_workers != 0) {
        blocking_pool_start(g_config.blocking_workers);
    }
    return true;
}

AlderTask *alder_task_create_on_lane(uint64_t group, AlderTaskLane lane,
                                     AlderStepFn step, void *frame,
                                     AlderDomain *domain) {
    if (step == NULL || frame == NULL || domain == NULL) {
        alder_runtime_panic("task.create with a null activation");
    }
    if (lane != ALDER_LANE_POOL && lane != ALDER_LANE_LOCAL) {
        alder_runtime_panic("task.create with an invalid lane");
    }
    if (lane == ALDER_LANE_LOCAL && !(g_threaded && g_config.local_lane)) {
        alder_runtime_panic("task.create on an unconfigured local lane");
    }
    AlderTask *task = (AlderTask *)rt_malloc(sizeof *task);
    if (task == NULL) {
        alder_runtime_panic("task.create allocation failure");
    }
    memset(task, 0, sizeof *task);
    atomic_init(&task->state, ALDER_TASK_CREATED);
    atomic_init(&task->cancel_requested, false);
    atomic_init(&task->queued, false);
    atomic_init(&task->refs, 1);
    atomic_init(&task->timer_count, 0);
    atomic_init(&task->wakeup.latch, false);
    atomic_init(&task->wakeup.signal_next, NULL);
    atomic_init(&task->run_next, NULL);
    task->wakeup.task = task;
    task->wait_reason = ALDER_WAIT_NONE;
    task->slot_index = UINT32_MAX;
    task->lane = lane == ALDER_LANE_LOCAL ? &g_local_lane : &g_pool_lane;
    pthread_mutex_lock(&g_registry_lock);
    task_registry_insert(task);
    AlderGroup *task_group = group_get(group);
    group_link(task_group, task);
    pthread_mutex_unlock(&g_registry_lock);
    task_push(task, step, frame, domain);
    return task;
}

AlderTask *alder_task_create(uint64_t group, AlderStepFn step, void *frame,
                             AlderDomain *domain) {
    return alder_task_create_on_lane(group, ALDER_LANE_POOL, step, frame,
                                     domain);
}

void alder_task_start(AlderTask *task) {
    if (task == NULL) {
        alder_runtime_panic("task.start of a null task");
    }
    if (!task_transition(task, ALDER_TASK_CREATED, ALDER_TASK_RUNNABLE)) {
        alder_runtime_panic("task.start of a task that is not created");
    }
    executor_enqueue(task);
}

void alder_task_call(AlderTask *task, AlderStepFn callee, void *frame,
                     AlderDomain *domain) {
    AlderTask *current = current_task_checked("task.call outside a step");
    if (task != current) {
        alder_runtime_panic("task.call for another task");
    }
    if (callee == NULL || frame == NULL || domain == NULL) {
        alder_runtime_panic("task.call with a null activation");
    }
    if (current->pending_call) {
        alder_runtime_panic("task.call published twice");
    }
    current->pending_step = callee;
    current->pending_frame = frame;
    current->pending_domain = domain;
    current->pending_call = true;
}

AlderWakeup *alder_task_wakeup(void) {
    return &current_task_checked("task.wakeup outside a step")->wakeup;
}

void alder_wakeup_signal(AlderWakeup *wakeup) {
    if (wakeup == NULL || wakeup->task == NULL) {
        return;
    }
    AlderTask *task = wakeup->task;
    atomic_store_explicit(&wakeup->latch, true, memory_order_seq_cst);
    int expected = ALDER_TASK_PARKED;
    if (!atomic_compare_exchange_strong_explicit(
            &task->state, &expected, ALDER_TASK_RUNNABLE,
            memory_order_seq_cst, memory_order_seq_cst)) {
        return;
    }
    if (!g_threaded) {
        run_queue_push(task);
        return;
    }
    AlderWakeup *head =
        atomic_load_explicit(&g_signal_head, memory_order_relaxed);
    for (;;) {
        atomic_store_explicit(&wakeup->signal_next, head,
                              memory_order_relaxed);
        if (atomic_compare_exchange_weak_explicit(
                &g_signal_head, &head, wakeup, memory_order_release,
                memory_order_relaxed)) {
            break;
        }
    }
    pthread_mutex_lock(&g_queue_lock);
    pthread_cond_broadcast(&g_work_cond);
    pthread_mutex_unlock(&g_queue_lock);
}

void alder_task_wake_id(uint64_t task) {
    pthread_mutex_lock(&g_registry_lock);
    AlderTask *target = task_resolve_retained(
        task, "task.wake_id of a released or foreign id");
    pthread_mutex_unlock(&g_registry_lock);
    alder_wakeup_signal(&target->wakeup);
    task_unref(target);
}

void alder_task_yield(void) {
    AlderTask *current = current_task_checked("task.yield outside a step");
    atomic_store_explicit(&current->wakeup.latch, true,
                          memory_order_seq_cst);
}

void alder_task_wait_reason(uint32_t reason) {
    AlderTask *current =
        current_task_checked("task.wait_reason outside a step");
    current->wait_reason = reason;
}

bool alder_task_cancelled(void) {
    AlderTask *current =
        current_task_checked("task.cancelled outside a step");
    if (current->shield_depth > 0) {
        return false;
    }
    return atomic_load_explicit(&current->cancel_requested,
                                memory_order_seq_cst);
}

void alder_task_shield_push(void) {
    AlderTask *current =
        current_task_checked("task.shield_push outside a step");
    if (current->shield_depth == UINT32_MAX) {
        alder_runtime_panic("task shield depth exhausted");
    }
    current->shield_depth += 1;
}

void alder_task_shield_pop(void) {
    AlderTask *current =
        current_task_checked("task.shield_pop outside a step");
    if (current->shield_depth == 0) {
        alder_runtime_panic("task.shield_pop at depth zero");
    }
    current->shield_depth -= 1;
}

bool alder_timer_at(AlderWakeup *wakeup, uint64_t deadline) {
    if (wakeup == NULL || wakeup->task == NULL) {
        alder_runtime_panic("timer.at with a null wakeup");
    }
    if (deadline == UINT64_MAX) {
        return false;
    }
    AlderTask *target = wakeup->task;
    if (atomic_load_explicit(&target->state, memory_order_seq_cst) ==
        ALDER_TASK_DONE) {
        alder_runtime_panic("timer.at for a completed task");
    }
    if (deadline <= clock_load()) {
        alder_wakeup_signal(wakeup);
        return true;
    }
    AlderTimer *timer = (AlderTimer *)rt_malloc(sizeof *timer);
    if (timer == NULL) {
        alder_runtime_panic("timer.at allocation failure");
    }
    timer->deadline = deadline;
    timer->task_id = target->id;
    timer->wakeup = wakeup;
    timer->task = NULL;
    timer->heap_index = SIZE_MAX;
    atomic_init(&timer->task_prev, NULL);
    atomic_init(&timer->task_next, NULL);
    atomic_init(&timer->active, false);
    memset(&timer->request, 0, sizeof timer->request);
    timer->request.kind = ALDER_TIMER_INSERT;
    timer->request.timer = timer;
    timer->request.done = true;
    if (!g_threaded) {
        task_timer_link(target, timer);
        (void)atomic_fetch_add_explicit(&target->timer_count, 1,
                                        memory_order_acq_rel);
        task_ref(target);
        timer_heap_insert(timer);
        return true;
    }
    pthread_mutex_lock(&g_timer_lock);
    task_timer_link(target, timer);
    (void)atomic_fetch_add_explicit(&target->timer_count, 1,
                                    memory_order_acq_rel);
    task_ref(target);
    if (g_timer_service_live) {
        timer_request_push_locked(&timer->request);
    } else {
        timer_heap_insert(timer);
    }
    pthread_mutex_unlock(&g_timer_lock);
    return true;
}

bool alder_task_await(uint64_t child) {
    AlderTask *parent = current_task_checked("task.await outside a step");
    pthread_mutex_lock(&g_registry_lock);
    AlderTask *target =
        task_resolve_retained(child, "task.await of a released or foreign id");
    if (target == parent) {
        alder_runtime_panic("task.await of the current task");
    }
    if (parent->awaiting != NULL) {
        alder_runtime_panic("task.await while already awaiting");
    }
    if (target->awaited) {
        alder_runtime_panic("task.await of a task awaited twice");
    }
    target->awaited = true;
    if (atomic_load_explicit(&target->state, memory_order_seq_cst) ==
        ALDER_TASK_DONE) {
        pthread_mutex_unlock(&g_registry_lock);
        task_unref(target);
        return true;
    }
    target->awaiter = parent;
    parent->awaiting = target;
    pthread_mutex_unlock(&g_registry_lock);
    task_unref(target);
    return false;
}

void alder_task_cancel(uint64_t task) {
    pthread_mutex_lock(&g_registry_lock);
    AlderTask *target = task_resolve_retained(
        task, "task.cancel of a released or foreign id");
    pthread_mutex_unlock(&g_registry_lock);
    atomic_store_explicit(&target->cancel_requested, true,
                          memory_order_seq_cst);
    pthread_mutex_lock(&g_blocking_lock);
    AlderBlockingEntry *entry = target->blocking_entry;
    if (entry != NULL && !entry->shielded) {
        entry->cancelled = true;
    }
    pthread_mutex_unlock(&g_blocking_lock);
    alder_wakeup_signal(&target->wakeup);
    task_unref(target);
}

void alder_task_release(uint64_t task) {
    pthread_mutex_lock(&g_registry_lock);
    AlderTask *target =
        task_resolve(task, "task.release of a released or foreign id");
    if (target == g_current_task) {
        alder_runtime_panic("task.release of the current task");
    }
    if (atomic_load_explicit(&target->timer_count, memory_order_acquire) != 0) {
        alder_runtime_panic("task.release with a live registration");
    }
    if (target->depth != 0 || target->top_block != NULL ||
        target->base != NULL) {
        alder_runtime_panic("task.release with a live activation stack");
    }
    if (atomic_load_explicit(&target->state, memory_order_seq_cst) !=
        ALDER_TASK_DONE) {
        alder_runtime_panic("task.release of a live task");
    }
    if (target->pending_call) {
        alder_runtime_panic("task.release with a published callee");
    }
    if (target->awaiting != NULL) {
        alder_runtime_panic("task.release while awaiting a child");
    }
    if (target->awaiter != NULL) {
        alder_runtime_panic("task.release of a task another task awaits");
    }
    target->released = true;
    group_unlink(target);
    task_registry_remove(target);
    pthread_mutex_unlock(&g_registry_lock);
    task_unref(target);
}

uint64_t alder_task_id(void) {
    return current_task_checked("task.id outside a step")->id;
}

uint64_t alder_task_handle(AlderTask *task) {
    if (task == NULL) {
        alder_runtime_panic("task.handle of a null task");
    }
    return task->id;
}

/* ------------------------------------------------------------------ */
/* C strings                                                           */
/* ------------------------------------------------------------------ */

/*
 * c.CString buffers are plain malloc blocks holding the Alder bytes plus a
 * terminating NUL, freed by exactly one release. The make helper scans for
 * an interior NUL and reports it separately from allocation failure so the
 * generated code can distinguish a none option from the checked edge.
 * Status convention: 0 copied (buffer stored through out), 1 interior NUL
 * (out untouched), negative allocation failure.
 */
int alder_cstring_make(const uint8_t *data, uint64_t len, char **out) {
    if (out == NULL) {
        return -1;
    }
    *out = NULL;
    for (uint64_t i = 0; i < len; i++) {
        if (data[i] == 0) {
            return 1;
        }
    }
    char *buffer = (char *)rt_malloc((size_t)len + 1);
    if (buffer == NULL) {
        return -1;
    }
    if (len != 0) {
        memcpy(buffer, data, (size_t)len);
    }
    buffer[len] = '\0';
    *out = buffer;
    return 0;
}

/*
 * Build a c.CString from bytes the checker proved interior-NUL free, so the
 * only failure is allocation (NULL).
 */
char *alder_cstring_make_lit(const uint8_t *data, uint64_t len) {
    char *buffer = (char *)rt_malloc((size_t)len + 1);
    if (buffer != NULL) {
        if (len != 0) {
            memcpy(buffer, data, (size_t)len);
        }
        buffer[len] = '\0';
    }
    return buffer;
}

/* Free one c.CString buffer. Passing NULL is allowed and does nothing. */
void alder_cstring_release(char *buffer) {
    rt_free(buffer);
}

/* ------------------------------------------------------------------ */
/* Generational tables                                                 */
/* ------------------------------------------------------------------ */

static const uint64_t TABLE_INITIAL_CAPACITY = 8;

bool alder_table_init(AlderTable *table, AlderDomain *domain,
                      uint64_t elem_size, uint64_t elem_align) {
    if (table == NULL || table->serial != 0 || domain == NULL ||
        domain->magic != ALDER_MAGIC || elem_size == 0 ||
        elem_size > (uint64_t)SIZE_MAX || elem_align > (uint64_t)SIZE_MAX ||
        !align_is_valid((size_t)elem_align) || atomic_load_explicit(&g_next_table_serial, memory_order_relaxed) == 0) {
        return false;
    }
    AlderTableSlot *slots = (AlderTableSlot *)alder_domain_alloc(
        domain, (size_t)(TABLE_INITIAL_CAPACITY * sizeof(AlderTableSlot)),
        (size_t)_Alignof(AlderTableSlot));
    if (slots == NULL) {
        return false;
    }
    memset(slots, 0,
           (size_t)(TABLE_INITIAL_CAPACITY * sizeof(AlderTableSlot)));
    AlderTable fresh = {0};
    (void)take_unique_serial(&g_next_table_serial, &fresh.serial);
    fresh.capacity = TABLE_INITIAL_CAPACITY;
    fresh.elem_size = elem_size;
    fresh.elem_align = elem_align;
    fresh.domain_serial = domain->serial;
    fresh.domain_epoch = domain->reset_epoch;
    fresh.domain = domain;
    fresh.slots = slots;
    *table = fresh;
    return true;
}

static bool table_is_live(const AlderTable *table) {
    return table != NULL && table->serial != 0 && table->domain != NULL &&
           table->domain->magic == ALDER_MAGIC &&
           table->domain->serial == table->domain_serial &&
           table->domain->reset_epoch == table->domain_epoch;
}

static bool table_grow(AlderTable *table) {
    if (table->capacity > UINT64_MAX / 2) {
        return false;
    }
    uint64_t new_capacity = table->capacity * 2;
    if (new_capacity > (uint64_t)(SIZE_MAX / sizeof(AlderTableSlot))) {
        return false; /* overflow */
    }
    /* Test/diagnostic slot limit (alder_runtime_test_set_table_slot_limit):
       refuse growth past the configured slot budget so capacity-policy paths
       are deterministically reachable in tests. Zero means unlimited, which
       is the shipped behavior. The limit exists only in testing builds, so
       the shipped runtime carries neither the state nor the check. */
#if defined(ALDER_RUNTIME_TESTING)
    if (g_table_slot_limit != 0 && new_capacity > g_table_slot_limit) {
        return false;
    }
#endif
    size_t slot_bytes = (size_t)new_capacity * sizeof(AlderTableSlot);
    AlderTableSlot *fresh = (AlderTableSlot *)alder_domain_alloc(
        table->domain, slot_bytes, (size_t)_Alignof(AlderTableSlot));
    if (fresh == NULL) {
        return false; /* out of memory; table unchanged */
    }
    memcpy(fresh, table->slots,
           (size_t)table->capacity * sizeof(AlderTableSlot));
    memset(fresh + table->capacity, 0,
           (size_t)(new_capacity - table->capacity) *
               sizeof(AlderTableSlot));
    table->slots = fresh;
    table->capacity = new_capacity;
    return true;
}

bool alder_table_insert(AlderTable *table, const void *elem,
                        AlderTableId *out_id) {
    if (!table_is_live(table) || elem == NULL || out_id == NULL ||
        table->generation_counter == UINT64_MAX) {
        return false;
    }
    if (table->count == table->capacity && !table_grow(table)) {
        return false;
    }
    /* A free slot exists because capacity > count. */
    uint64_t slot_index = UINT64_MAX;
    for (uint64_t i = 0; i < table->capacity; i++) {
        if (table->slots[i].generation == 0) {
            slot_index = i;
            break;
        }
    }
    if (slot_index == UINT64_MAX) {
        return false; /* invariant broken: cannot happen */
    }
    uint8_t *storage = (uint8_t *)alder_domain_alloc(
        table->domain, (size_t)table->elem_size, (size_t)table->elem_align);
    if (storage == NULL) {
        return false;
    }
    memcpy(storage, elem, (size_t)table->elem_size);
    table->generation_counter += 1;
    table->slots[slot_index].generation = table->generation_counter;
    table->slots[slot_index].elem = storage;
    table->count += 1;
    out_id->table_serial = table->serial;
    out_id->slot = slot_index;
    out_id->generation = table->generation_counter;
    return true;
}

/* Shared validation: table identity (serial and live domain), slot bounds,
 * occupancy, and generation. The element storage of a stale id is never
 * touched. */
static bool table_validate(const AlderTable *table, AlderTableId id,
                           AlderTableSlot **out_slot) {
    if (!table_is_live(table)) {
        return false;
    }
    if (id.table_serial != table->serial) {
        return false;
    }
    if (id.slot >= table->capacity) {
        return false;
    }
    AlderTableSlot *slot = &table->slots[id.slot];
    if (slot->generation == 0 || slot->generation != id.generation) {
        return false;
    }
    *out_slot = slot;
    return true;
}

bool alder_table_lookup(AlderTable *table, AlderTableId id, void **out_elem) {
    AlderTableSlot *slot = NULL;
    if (out_elem == NULL || !table_validate(table, id, &slot)) {
        return false;
    }
    *out_elem = slot->elem;
    return true;
}

bool alder_table_lookup_mut(AlderTable *table, AlderTableId id,
                            void **out_elem) {
    return alder_table_lookup(table, id, out_elem);
}

bool alder_table_remove(AlderTable *table, AlderTableId id) {
    AlderTableSlot *slot = NULL;
    if (!table_validate(table, id, &slot)) {
        return false;
    }
    /* The slot becomes reusable with a fresh generation; the element
     * storage stays in the domain until reset or destroy. */
    slot->generation = 0;
    slot->elem = NULL;
    table->count -= 1;
    return true;
}

/* Hosted program arguments. The driver installs the process vector once
 * before Alder code runs; these globals are read-only afterwards and are
 * deliberately single-threaded, matching the hosted-entry contract. A NULL
 * vector or a nonpositive count leaves the accessors empty. */
static int alder_host_argc;
static char **alder_host_argv;

void alder_host_set_args(int argc, char **argv) {
    if (argc <= 0 || argv == NULL) {
        alder_host_argc = 0;
        alder_host_argv = NULL;
        return;
    }
    alder_host_argc = argc;
    alder_host_argv = argv;
}

int alder_host_arg_count(void) {
    return alder_host_argc;
}

const char *alder_host_arg(int index) {
    if (index < 0 || index >= alder_host_argc || alder_host_argv == NULL) {
        return NULL;
    }
    return alder_host_argv[index];
}

/* ------------------------------------------------------------------ */
/* Structural hashing                                                  */
/* ------------------------------------------------------------------ */

static uint64_t alder_hash_rotate_left(uint64_t value, uint64_t bits) {
    return (value << bits) | (value >> (UINT64_C(64) - bits));
}

static void alder_hash_round(AlderHashState *state) {
    state->v0 += state->v1;
    state->v1 = alder_hash_rotate_left(state->v1, UINT64_C(13));
    state->v1 ^= state->v0;
    state->v0 = alder_hash_rotate_left(state->v0, UINT64_C(32));
    state->v2 += state->v3;
    state->v3 = alder_hash_rotate_left(state->v3, UINT64_C(16));
    state->v3 ^= state->v2;
    state->v0 += state->v3;
    state->v3 = alder_hash_rotate_left(state->v3, UINT64_C(21));
    state->v3 ^= state->v0;
    state->v2 += state->v1;
    state->v1 = alder_hash_rotate_left(state->v1, UINT64_C(17));
    state->v1 ^= state->v2;
    state->v2 = alder_hash_rotate_left(state->v2, UINT64_C(32));
}

static void alder_hash_rounds(AlderHashState *state, unsigned rounds) {
    unsigned at;
    for (at = 0; at < rounds; at++) {
        alder_hash_round(state);
    }
}

void alder_hash_init(AlderHashState *state, uint64_t k0, uint64_t k1) {
    state->v0 = k0 ^ UINT64_C(0x736f6d6570736575);
    state->v1 = k1 ^ UINT64_C(0x646f72616e646f6d);
    state->v2 = k0 ^ UINT64_C(0x6c7967656e657261);
    state->v3 = k1 ^ UINT64_C(0x7465646279746573);
    state->total = UINT64_C(0);
    state->tail = UINT64_C(0);
}

static void alder_hash_compress(AlderHashState *state) {
    state->v3 ^= state->tail;
    alder_hash_rounds(state, 1U);
    state->v0 ^= state->tail;
    state->tail = UINT64_C(0);
}

void alder_hash_write_uint(AlderHashState *state, uint64_t value, uint64_t width) {
    uint64_t at;
    for (at = UINT64_C(0); at < width; at++) {
        state->tail |= (value & UINT64_C(0xff)) << ((state->total % UINT64_C(8)) * UINT64_C(8));
        state->total += UINT64_C(1);
        if (state->total % UINT64_C(8) == UINT64_C(0)) {
            alder_hash_compress(state);
        }
        value >>= UINT64_C(8);
    }
}

void alder_hash_write_u64(AlderHashState *state, uint64_t value) {
    alder_hash_write_uint(state, value, UINT64_C(8));
}

void alder_hash_write_bytes(AlderHashState *state, const uint8_t *data, uint64_t len) {
    uint64_t at;
    for (at = UINT64_C(0); at < len; at++) {
        alder_hash_write_uint(state, (uint64_t)data[at], UINT64_C(1));
    }
}

uint64_t alder_hash_finish(const AlderHashState *state) {
    AlderHashState final = *state;
    final.v3 ^= (final.total << UINT64_C(56)) | final.tail;
    alder_hash_rounds(&final, 1U);
    final.v0 ^= (final.total << UINT64_C(56)) | final.tail;
    final.v2 ^= UINT64_C(0xff);
    alder_hash_rounds(&final, 3U);
    return final.v0 ^ final.v1 ^ final.v2 ^ final.v3;
}
