/*
 * Aster minimal C runtime implementation.
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
 *  - segments double up to ASTER_MAX_SEGMENT; larger requests get a
 *    dedicated segment of exactly the needed size;
 *  - reset truncates the marked segment and frees every later segment;
 *  - destroy frees all segments, recursively destroys children, and
 *    unregisters the domain from its parent.
 */
#include "aster.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ASTER_MAGIC ((uint32_t)0x41535452u) /* "ASTR" */

#define ASTER_MIN_SEGMENT ((size_t)8192)
#define ASTER_MAX_SEGMENT ((size_t)(1u << 20)) /* 1 MiB */
#define ASTER_SEGMENT_ALIGN ((size_t)16)

typedef struct AsterSegment {
    struct AsterSegment *next;
    uint64_t serial;
    size_t capacity; /* usable bytes in the data area */
    size_t used;     /* bytes consumed from the data area */
} AsterSegment;

struct AsterTableSlot {
    uint64_t generation; /* 0 means empty */
    uint8_t *elem;
};

struct AsterCleanupEntry {
    AsterCleanupEntry *next;
    AsterCleanupFn fn;
    void *context;
    bool armed;
};

/* Single-threaded by design (structured concurrency is out of scope). */
static size_t g_live_allocations = 0;
static uint64_t g_next_domain_serial = 1; /* 0 denotes exhaustion/invalid */
static uint64_t g_next_segment_serial = 1;
static uint64_t g_next_table_serial = 1; /* 0 is never a valid serial */

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

size_t aster_runtime_live_allocations(void) {
    return g_live_allocations;
}

_Noreturn void aster_runtime_panic(const char *message) {
    fputs("aster runtime panic: ", stderr);
    fputs(message != NULL ? message : "(null)", stderr);
    fputc('\n', stderr);
    abort();
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

static uint8_t *segment_data(AsterSegment *seg) {
    return (uint8_t *)align_up((uintptr_t)(seg + 1), ASTER_SEGMENT_ALIGN);
}

/* ------------------------------------------------------------------ */
/* Storage domains                                                     */
/* ------------------------------------------------------------------ */

bool aster_domain_init(AsterDomain *domain, AsterDomain *parent) {
    if (domain == NULL || domain->magic == ASTER_MAGIC) {
        return false; /* NULL or double init */
    }
    if (parent != NULL && parent->magic != ASTER_MAGIC) {
        return false;
    }
    uint64_t serial;
    if (!take_unique_serial(&g_next_domain_serial, &serial)) {
        return false;
    }
    *domain = (AsterDomain){0};
    domain->magic = ASTER_MAGIC;
    domain->serial = serial;
    domain->reset_epoch = 1;
    domain->parent = parent;
    if (parent != NULL) {
        domain->next_sibling = parent->children_head;
        parent->children_head = domain;
    }
    return true;
}

static AsterSegment *new_segment(size_t capacity) {
    size_t slack = ASTER_SEGMENT_ALIGN - 1;
    size_t alloc_size = capacity + sizeof(AsterSegment) + slack;
    if (alloc_size < capacity) {
        return NULL; /* overflow */
    }
    if (g_next_segment_serial == 0) {
        return NULL;
    }
    AsterSegment *seg = (AsterSegment *)rt_malloc(alloc_size);
    if (seg == NULL) {
        return NULL;
    }
    seg->next = NULL;
    (void)take_unique_serial(&g_next_segment_serial, &seg->serial);
    seg->capacity = capacity;
    seg->used = 0;
    return seg;
}

void *aster_domain_alloc(AsterDomain *domain, size_t size, size_t align) {
    if (domain == NULL || domain->magic != ASTER_MAGIC) {
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
    AsterSegment *seg = domain->segments_tail;
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
        if (needed > ASTER_MAX_SEGMENT) {
            capacity = needed; /* large allocation: exact-size segment */
        } else {
            size_t prev = (seg != NULL) ? seg->capacity : 0;
            size_t grown = prev > ASTER_MAX_SEGMENT / 2 ? ASTER_MAX_SEGMENT
                                                        : prev * 2;
            capacity = grown < ASTER_MIN_SEGMENT ? ASTER_MIN_SEGMENT : grown;
            if (capacity < needed) {
                capacity = needed;
            }
        }
        AsterSegment *fresh = new_segment(capacity);
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

AsterDomainMark aster_domain_mark(AsterDomain *domain) {
    AsterDomainMark mark = {0, 0, 0, 0};
    if (domain != NULL && domain->magic == ASTER_MAGIC) {
        mark.domain_serial = domain->serial;
        mark.reset_epoch = domain->reset_epoch;
        if (domain->segments_tail != NULL) {
            mark.segment_serial = domain->segments_tail->serial;
            mark.offset = domain->segments_tail->used;
        }
    }
    return mark;
}

bool aster_domain_reset(AsterDomain *domain, AsterDomainMark mark) {
    if (domain == NULL || domain->magic != ASTER_MAGIC) {
        return false;
    }
    if (mark.domain_serial != domain->serial ||
        mark.reset_epoch != domain->reset_epoch ||
        domain->reset_epoch == UINT64_MAX) {
        return false;
    }
    AsterSegment *seg = NULL;
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
    AsterSegment *victim = (seg == NULL) ? domain->segments_head : seg->next;
    while (victim != NULL) {
        AsterSegment *next = victim->next;
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

void aster_domain_destroy(AsterDomain *domain) {
    if (domain == NULL || domain->magic != ASTER_MAGIC) {
        return; /* no-op: uninitialized or already destroyed */
    }
    /* Children cannot outlive their parent. */
    AsterDomain *child = domain->children_head;
    while (child != NULL) {
        AsterDomain *next = child->next_sibling;
        aster_domain_destroy(child);
        child = next;
    }
    AsterSegment *seg = domain->segments_head;
    while (seg != NULL) {
        AsterSegment *next = seg->next;
        rt_free(seg);
        seg = next;
    }
    /* Unregister from the parent. */
    if (domain->parent != NULL) {
        AsterDomain **link = &domain->parent->children_head;
        while (*link != NULL && *link != domain) {
            link = &(*link)->next_sibling;
        }
        if (*link == domain) {
            *link = domain->next_sibling;
        }
    }
    *domain = (AsterDomain){0};
}

/* ------------------------------------------------------------------ */
/* Slices and bounds                                                   */
/* ------------------------------------------------------------------ */

bool aster_slice_index_checked(AsterSlice slice, uint64_t index) {
    return index < slice.len;
}

bool aster_slice_range_checked(AsterSlice slice, uint64_t lo, uint64_t hi) {
    return lo <= hi && hi <= slice.len;
}

/* ------------------------------------------------------------------ */
/* Checked integer arithmetic                                          */
/* ------------------------------------------------------------------ */

static bool i64_from_twos_bits(uint64_t bits, int64_t *out) {
    if (out == NULL) {
        return false;
    }
    if (bits <= (uint64_t)INT64_MAX) {
        *out = (int64_t)bits;
        return true;
    }
    uint64_t magnitude = (uint64_t)0 - bits;
    if (magnitude == (uint64_t)INT64_MAX + 1u) {
        *out = INT64_MIN;
    } else {
        *out = -(int64_t)magnitude;
    }
    return true;
}

bool aster_i64_add_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || (b > 0 && a > INT64_MAX - b) ||
        (b < 0 && a < INT64_MIN - b)) {
        return false;
    }
    *out = a + b;
    return true;
}

bool aster_i64_sub_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || (b > 0 && a < INT64_MIN + b) ||
        (b < 0 && a > INT64_MAX + b)) {
        return false;
    }
    *out = a - b;
    return true;
}

bool aster_i64_mul_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL) {
        return false;
    }
    if (a == 0 || b == 0) {
        *out = 0;
        return true;
    }
    if ((a == INT64_MIN && b == -1) || (a == -1 && b == INT64_MIN)) {
        return false;
    }
    bool neg = (a < 0) != (b < 0);
    uint64_t ua = a < 0 ? (uint64_t)0 - (uint64_t)a : (uint64_t)a;
    uint64_t ub = b < 0 ? (uint64_t)0 - (uint64_t)b : (uint64_t)b;
    uint64_t limit = neg ? ((uint64_t)INT64_MAX + (uint64_t)1)
                         : (uint64_t)INT64_MAX;
    if (ua > limit / ub) {
        return false;
    }
    uint64_t prod = ua * ub;
    if (neg) {
        prod = (uint64_t)0 - prod; /* two's complement negation, defined in
                                      unsigned arithmetic */
    }
    return i64_from_twos_bits(prod, out);
}

bool aster_i64_div_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || b == 0 || (a == INT64_MIN && b == -1)) {
        return false;
    }
    *out = a / b;
    return true;
}

bool aster_i64_shl_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || b < 0 || b >= 64) {
        return false;
    }
    uint64_t r = (uint64_t)a << (unsigned)b; /* unsigned shift is defined */
    return i64_from_twos_bits(r, out);
}

bool aster_i64_shr_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || b < 0 || b >= 64) {
        return false;
    }
    uint64_t u = (uint64_t)a >> (unsigned)b;
    if (a < 0 && b > 0) {
        /* Arithmetic shift: sign-extend the shifted-out bits. */
        u |= ~(UINT64_MAX >> (unsigned)b);
    }
    return i64_from_twos_bits(u, out);
}

bool aster_u64_add_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || a > UINT64_MAX - b) {
        return false;
    }
    *out = a + b;
    return true;
}

bool aster_u64_sub_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || a < b) {
        return false;
    }
    *out = a - b;
    return true;
}

bool aster_u64_mul_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || (a != 0 && b > UINT64_MAX / a)) {
        return false;
    }
    *out = a * b;
    return true;
}

bool aster_u64_div_checked(uint64_t a, uint64_t b, uint64_t *out) {
    (void)a;
    if (out == NULL || b == 0) {
        return false;
    }
    *out = a / b;
    return true;
}

bool aster_u64_shl_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || b >= 64) {
        return false;
    }
    *out = a << (unsigned)b;
    return true;
}

bool aster_u64_shr_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || b >= 64) {
        return false;
    }
    *out = a >> (unsigned)b;
    return true;
}

bool aster_i64_from_f64(double v, int64_t *out) {
    if (out == NULL || v != v || v < -9223372036854775808.0 ||
        v >= 9223372036854775808.0) {
        return false;
    }
    *out = (int64_t)v; /* in-range conversion is defined */
    return true;
}

bool aster_u64_from_f64(double v, uint64_t *out) {
    if (out == NULL || v != v || v < 0.0 ||
        v >= 18446744073709551616.0) {
        return false;
    }
    *out = (uint64_t)v; /* in-range conversion is defined */
    return true;
}

/* ------------------------------------------------------------------ */
/* Scoped cleanup                                                      */
/* ------------------------------------------------------------------ */

bool aster_cleanup_scope_begin(AsterCleanupScope *scope) {
    if (scope == NULL || scope->active) {
        return false;
    }
    scope->armed_head = NULL;
    scope->spent_head = NULL;
    scope->ran = false;
    scope->active = true;
    return true;
}

bool aster_cleanup_push(AsterCleanupScope *scope, AsterCleanupFn fn,
                        void *context, AsterCleanupId *out_id) {
    if (scope == NULL || !scope->active || fn == NULL || out_id == NULL) {
        return false;
    }
    AsterCleanupEntry *entry = (AsterCleanupEntry *)rt_malloc(sizeof *entry);
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

bool aster_cleanup_disarm(AsterCleanupId id) {
    if (id == NULL || !id->armed) {
        return false;
    }
    id->armed = false;
    return true;
}

bool aster_cleanup_run(AsterCleanupScope *scope) {
    if (scope == NULL || !scope->active) {
        return false;
    }
    AsterCleanupEntry *entry = scope->armed_head;
    while (entry != NULL) {
        AsterCleanupEntry *next = entry->next;
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
        AsterCleanupEntry *tail = scope->armed_head;
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

bool aster_cleanup_end(AsterCleanupScope *scope) {
    if (scope == NULL || !scope->active) {
        return false;
    }
    bool ok = scope->ran && scope->armed_head == NULL;
    if (!ok) {
        /* Contract violation: run must precede end. Move leftovers to spent
         * and free everything so nothing leaks. */
        AsterCleanupEntry *head = scope->armed_head;
        if (head != NULL) {
            AsterCleanupEntry *tail = head;
            while (tail->next != NULL) {
                tail = tail->next;
            }
            tail->next = scope->spent_head;
            scope->spent_head = head;
            scope->armed_head = NULL;
        }
    }
    AsterCleanupEntry *entry = scope->spent_head;
    while (entry != NULL) {
        AsterCleanupEntry *next = entry->next;
        rt_free(entry);
        entry = next;
    }
    scope->spent_head = NULL;
    scope->active = false;
    return ok;
}

/* ------------------------------------------------------------------ */
/* Generational tables                                                 */
/* ------------------------------------------------------------------ */

static const uint64_t TABLE_INITIAL_CAPACITY = 8;

bool aster_table_init(AsterTable *table, AsterDomain *domain,
                      uint64_t elem_size, uint64_t elem_align) {
    if (table == NULL || table->serial != 0 || domain == NULL ||
        domain->magic != ASTER_MAGIC || elem_size == 0 ||
        elem_size > (uint64_t)SIZE_MAX || elem_align > (uint64_t)SIZE_MAX ||
        !align_is_valid((size_t)elem_align) || g_next_table_serial == 0) {
        return false;
    }
    AsterTableSlot *slots = (AsterTableSlot *)aster_domain_alloc(
        domain, (size_t)(TABLE_INITIAL_CAPACITY * sizeof(AsterTableSlot)),
        (size_t)_Alignof(AsterTableSlot));
    if (slots == NULL) {
        return false;
    }
    memset(slots, 0,
           (size_t)(TABLE_INITIAL_CAPACITY * sizeof(AsterTableSlot)));
    AsterTable fresh = {0};
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

static bool table_is_live(const AsterTable *table) {
    return table != NULL && table->serial != 0 && table->domain != NULL &&
           table->domain->magic == ASTER_MAGIC &&
           table->domain->serial == table->domain_serial &&
           table->domain->reset_epoch == table->domain_epoch;
}

static bool table_grow(AsterTable *table) {
    if (table->capacity > UINT64_MAX / 2) {
        return false;
    }
    uint64_t new_capacity = table->capacity * 2;
    if (new_capacity > (uint64_t)(SIZE_MAX / sizeof(AsterTableSlot))) {
        return false; /* overflow */
    }
    size_t slot_bytes = (size_t)new_capacity * sizeof(AsterTableSlot);
    AsterTableSlot *fresh = (AsterTableSlot *)aster_domain_alloc(
        table->domain, slot_bytes, (size_t)_Alignof(AsterTableSlot));
    if (fresh == NULL) {
        return false; /* out of memory; table unchanged */
    }
    memcpy(fresh, table->slots,
           (size_t)table->capacity * sizeof(AsterTableSlot));
    memset(fresh + table->capacity, 0,
           (size_t)(new_capacity - table->capacity) *
               sizeof(AsterTableSlot));
    table->slots = fresh;
    table->capacity = new_capacity;
    return true;
}

bool aster_table_insert(AsterTable *table, const void *elem,
                        AsterTableId *out_id) {
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
    uint8_t *storage = (uint8_t *)aster_domain_alloc(
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
static bool table_validate(const AsterTable *table, AsterTableId id,
                           AsterTableSlot **out_slot) {
    if (!table_is_live(table)) {
        return false;
    }
    if (id.table_serial != table->serial) {
        return false;
    }
    if (id.slot >= table->capacity) {
        return false;
    }
    AsterTableSlot *slot = &table->slots[id.slot];
    if (slot->generation == 0 || slot->generation != id.generation) {
        return false;
    }
    *out_slot = slot;
    return true;
}

bool aster_table_lookup(AsterTable *table, AsterTableId id, void **out_elem) {
    AsterTableSlot *slot = NULL;
    if (out_elem == NULL || !table_validate(table, id, &slot)) {
        return false;
    }
    *out_elem = slot->elem;
    return true;
}

bool aster_table_lookup_mut(AsterTable *table, AsterTableId id,
                            void **out_elem) {
    return aster_table_lookup(table, id, out_elem);
}

bool aster_table_remove(AsterTable *table, AsterTableId id) {
    AsterTableSlot *slot = NULL;
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
