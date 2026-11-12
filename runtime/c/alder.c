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
    void *context;
    bool armed;
};

/* Single-threaded by design (structured concurrency is out of scope). */
static size_t g_live_allocations = 0;
static uint64_t g_next_domain_serial = 1; /* 0 denotes exhaustion/invalid */
static uint64_t g_next_segment_serial = 1;
static uint64_t g_next_table_serial = 1; /* 0 is never a valid serial */

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
    g_next_segment_serial = 0;
}

void alder_runtime_test_set_table_slot_limit(uint64_t slots) {
    g_table_slot_limit = slots;
}
#endif

static void *rt_malloc(size_t size) {
    void *p = malloc(size);
    if (p != NULL) {
        g_live_allocations += 1;
    }
    return p;
}

static void rt_free(void *p) {
    if (p != NULL) {
        g_live_allocations -= 1;
        free(p);
    }
}

size_t alder_runtime_live_allocations(void) {
    return g_live_allocations;
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

static bool take_unique_serial(uint64_t *next, uint64_t *out) {
    if (*next == 0) {
        return false;
    }
    *out = *next;
    *next = (*next == UINT64_MAX) ? 0 : *next + 1;
    return true;
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
    if (g_next_segment_serial == 0) {
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
    return true;
}

bool alder_cleanup_push(AlderCleanupScope *scope, AlderCleanupFn fn,
                        void *context, AlderCleanupId *out_id) {
    if (scope == NULL || !scope->active || fn == NULL || out_id == NULL) {
        return false;
    }
    AlderCleanupEntry *entry = (AlderCleanupEntry *)rt_malloc(sizeof *entry);
    if (entry == NULL) {
        return false;
    }
    entry->fn = fn;
    entry->context = context;
    entry->armed = true;
    entry->next = scope->armed_head; /* newest first: reverse registration
                                        order at run time */
    scope->armed_head = entry;
    *out_id = entry;
    return true;
}

bool alder_cleanup_disarm(AlderCleanupId id) {
    if (id == NULL || !id->armed) {
        return false;
    }
    id->armed = false;
    return true;
}

bool alder_cleanup_run(AlderCleanupScope *scope) {
    if (scope == NULL || !scope->active) {
        return false;
    }
    AlderCleanupEntry *entry = scope->armed_head;
    while (entry != NULL) {
        AlderCleanupEntry *next = entry->next;
        if (entry->armed) {
            entry->armed = false;
            entry->fn(entry->context);
        }
        entry = next;
    }
    /* Everything executed or skipped becomes spent; a later run has nothing
     * to execute, so every entry runs at most once. The spent list must be
     * preserved across runs so entries of earlier runs are still freed. */
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
    return true;
}

bool alder_cleanup_end(AlderCleanupScope *scope) {
    if (scope == NULL || !scope->active) {
        return false;
    }
    bool ok = scope->ran && scope->armed_head == NULL;
    if (!ok) {
        /* Contract violation: run must precede end. Move leftovers to spent
         * and free everything so nothing leaks. */
        AlderCleanupEntry *head = scope->armed_head;
        if (head != NULL) {
            AlderCleanupEntry *tail = head;
            while (tail->next != NULL) {
                tail = tail->next;
            }
            tail->next = scope->spent_head;
            scope->spent_head = head;
            scope->armed_head = NULL;
        }
    }
    AlderCleanupEntry *entry = scope->spent_head;
    while (entry != NULL) {
        AlderCleanupEntry *next = entry->next;
        rt_free(entry);
        entry = next;
    }
    scope->spent_head = NULL;
    scope->active = false;
    return ok;
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
        !align_is_valid((size_t)elem_align) || g_next_table_serial == 0) {
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
