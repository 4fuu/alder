/*
 * Alder minimal C runtime ABI.
 *
 * Portable C11. This header is the contract between verified Alder MIR
 * lowering and the runtime; docs/c-backend.md owns the detailed failure and
 * lifetime contracts and the undefined-behavior policy. All functions are
 * usable from ordinary C11 and never depend on host addresses or paths.
 *
 * Conventions:
 *  - every function that can fail returns bool (or NULL) and leaves output
 *    parameters untouched on failure, unless stated otherwise;
 *  - structures are caller-owned: the runtime allocates and frees only its
 *    own internal storage, never the caller's structs;
 *  - independent root domains may be entered from foreign threads; the
 *    runtime's live-allocation counter and identity serials are C11 atomics.
 *    Structured concurrency and shared mutable state remain outside this
 *    contract.
 */
#ifndef ALDER_RUNTIME_H
#define ALDER_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <limits.h>
#include <float.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Storage domains                                                     */
/* ------------------------------------------------------------------ */

/* Segment internals; only referenced through the opaque pointer in
 * AlderDomain and through domain marks. */
typedef struct AlderSegment AlderSegment;

/*
 * Caller-owned domain storage. The layout is part of the ABI because
 * generated code and tests embed the struct; treat the fields as internal.
 * The struct must be zero-initialized or freshly destroyed before
 * alder_domain_init. The runtime never frees the struct itself.
 */
struct AlderDomain {
    uint32_t magic;
    uint64_t serial;
    uint64_t reset_epoch;
    struct AlderDomain *parent;
    struct AlderDomain *children_head;
    struct AlderDomain *next_sibling;
    AlderSegment *segments_head;
    AlderSegment *segments_tail;
    size_t segment_count;
};
typedef struct AlderDomain AlderDomain;

/* A resettable frontier of one domain epoch. Integer identities avoid retaining
 * or comparing pointers after segment storage has been released. */
typedef struct {
    uint64_t domain_serial;
    uint64_t reset_epoch;
    uint64_t segment_serial; /* zero denotes the frontier before all segments */
    size_t offset;
} AlderDomainMark;

/*
 * Initialize a domain. The struct must be zero-initialized or freshly
 * destroyed. parent may be NULL (a root domain) or an initialized domain; a
 * child domain cannot outlive its parent. Returns false when the struct is
 * already initialized, the parent is not initialized, or the process-wide
 * domain identity namespace is exhausted.
 */
/*
 * A retained callback owner: one heap allocation holds the owner header and a
 * copied context block. The context address is stable when the owner value is
 * moved between Alder bindings; alder_callback_owner_free releases both after
 * the C registration has been unregistered and drained.
 */
typedef struct AlderCallbackOwner {
    max_align_t alder_align;
    unsigned char alder_context[];
} AlderCallbackOwner;

AlderCallbackOwner *alder_callback_owner_new(size_t context_size);
void *alder_callback_owner_context(AlderCallbackOwner *owner);
void alder_callback_owner_free(AlderCallbackOwner *owner);

bool alder_domain_init(AlderDomain *domain, AlderDomain *parent);

/*
 * Allocate size bytes aligned to align (a power of two) in the domain.
 * Returns NULL on failure: uninitialized or destroyed domain, align not a
 * power of two (or zero), size/alignment overflow, or out of memory.
 * Exhaustion of the segment identity namespace is also reported as failure.
 * size == 0 allocates one byte. Allocations stay valid until the domain is
 * reset past them or destroyed; the returned pointer is never NULL on success
 * and must not be freed by the caller.
 */
void *alder_domain_alloc(AlderDomain *domain, size_t size, size_t align);

/*
 * Return the current allocation frontier. A mark of an uninitialized or
 * destroyed domain has zero identities and is never accepted by reset.
 */
AlderDomainMark alder_domain_mark(AlderDomain *domain);

/*
 * Truncate the domain to the mark: storage allocated after the mark is
 * released. Returns false when the domain is not initialized or the mark
 * does not belong to the domain's current reset epoch with a valid segment
 * and offset. A mark made before the first allocation resets the domain to
 * empty. Every successful reset consumes all marks from the previous epoch.
 * Exhaustion of the reset-epoch namespace also returns false without changing
 * the domain.
 * Pointers into released storage become invalid; the MIR verifier prevents
 * their use.
 */
bool alder_domain_reset(AlderDomain *domain, AlderDomainMark mark);

/*
 * Release all storage of the domain, recursively destroy its child domains
 * (children cannot outlive their parent), and unregister it from its
 * parent. Destroying an uninitialized or already-destroyed domain is a
 * no-op. The struct is caller-owned and may be re-initialized afterwards.
 */
void alder_domain_destroy(AlderDomain *domain);

/* Number of heap blocks currently owned by the runtime (segments and
 * cleanup entries). Tests use it to prove leak-free domain lifecycles. */
size_t alder_runtime_live_allocations(void);

/*
 * Call-scoped buffer borrows pass a pointer for the duration of one foreign
 * call. An empty Alder buffer may have a null data pointer, and C library
 * entry points such as memcpy and read reject or misuse a null pointer even
 * with a zero count, so the generated code substitutes this writable
 * one-byte storage. The dummy is not owned by any Alder value and must never
 * be retained by the callee.
 */
extern uint8_t alder_c_buffer_dummy[1];

/* Test-only deterministic domain-allocation failure injection. Production
 * builds expose neither these symbols nor their state. Allow N eligible calls
 * to alder_domain_alloc, then fail subsequent calls until the hook is cleared. */
#if defined(ALDER_RUNTIME_TESTING)
void alder_runtime_test_fail_domain_alloc_after(uint64_t allowed_calls);
void alder_runtime_test_clear_domain_alloc_failure(void);
/* Irreversibly force identity exhaustion for the remainder of the test process. */
void alder_runtime_test_exhaust_segment_identities(void);
/* Deterministic table-capacity limit for tests and diagnostics: refuse table
 * growth that would take the slot array past `slots` entries, so insertion
 * into a full table fails. Zero (the default) means unlimited shipped
 * behavior. Not part of the language surface and unreachable from Alder
 * source; production builds expose neither the symbol nor its state. */
void alder_runtime_test_set_table_slot_limit(uint64_t slots);
#endif

/* ------------------------------------------------------------------ */
/* Slices and bounds                                                   */
/* ------------------------------------------------------------------ */

/* Dynamic-array ABI: a possibly-null data pointer and an element count.
 * slice, safe_ref, and safe_mut values share this representation. */
typedef struct {
    void *data;
    uint64_t len;
} AlderSlice;

/* Owned growable-vector ABI. Ownership metadata belongs to static MIR
 * provenance; it is deliberately absent from this value representation. */
typedef struct {
    void *data;
    uint64_t len;
    uint64_t capacity;
} AlderVec;

/*
 * The leaf helpers below are defined here as static inline rather than in
 * runtime/c/alder.c so that the generated compiler C, which includes this
 * header, can inline them. Generated code performs tens of billions of
 * bounds checks and checked integer operations per self-compilation, so an
 * out-of-line call per operation dominated the profile. The bodies are
 * byte-for-byte the ones that used to live in the runtime source, and the
 * checks and trap behaviour are unchanged: every failure still returns false
 * and still panics through alder_runtime_panic at the call site.
 */

static inline bool alder_i64_from_twos_bits(uint64_t bits, int64_t *out) {
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

static inline bool alder_vec_construct_checked(AlderSlice storage, uint64_t len,
                                               uint64_t capacity, AlderVec *out) {
    if (out == NULL || len > capacity || capacity > storage.len ||
        (capacity != 0 && storage.data == NULL)) {
        return false;
    }
    *out = (AlderVec){storage.data, len, capacity};
    return true;
}

/* Bounds checks used by slice.index.checked and slice.range.checked. A NULL
 * data pointer is valid only for a zero-length slice; its sole valid range is
 * [0, 0), while indexing and every range of {NULL, len>0} fail. */
static inline bool alder_slice_index_checked(AlderSlice slice, uint64_t index) {
    return slice.data != NULL && index < slice.len;
}

static inline bool alder_slice_range_checked(AlderSlice slice, uint64_t lo, uint64_t hi) {
    return lo <= hi && hi <= slice.len &&
           (slice.data != NULL || slice.len == 0);
}

/* ------------------------------------------------------------------ */
/* Checked integer arithmetic                                          */
/* ------------------------------------------------------------------ */

/*
 * Checked helpers for the 64-bit MIR integer operations. Each returns false
 * and leaves *out untouched when out is NULL or the operation would fail: signed
 * add/sub/mul overflow, division by zero, INT64_MIN / -1, shifts by a
 * negative or >= 64 count. Narrow non-shift MIR operations promote to 64 bits
 * and range-check the result. Narrow shifts must instead check against their
 * source width and mask or sign-extend at that width before using these helpers
 * (documented in docs/c-backend.md).
 * Shift semantics: left shifts wrap (two's complement bit pattern);
 * right shifts are arithmetic for signed values and logical for unsigned.
 */
static inline bool alder_i64_add_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || (b > 0 && a > INT64_MAX - b) ||
        (b < 0 && a < INT64_MIN - b)) {
        return false;
    }
    *out = a + b;
    return true;
}

static inline bool alder_i64_sub_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || (b > 0 && a < INT64_MIN + b) ||
        (b < 0 && a > INT64_MAX + b)) {
        return false;
    }
    *out = a - b;
    return true;
}

static inline bool alder_i64_mul_checked(int64_t a, int64_t b, int64_t *out) {
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
    return alder_i64_from_twos_bits(prod, out);
}

static inline bool alder_i64_div_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || b == 0 || (a == INT64_MIN && b == -1)) {
        return false;
    }
    *out = a / b;
    return true;
}

static inline bool alder_i64_shl_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || b < 0 || b >= 64) {
        return false;
    }
    uint64_t r = (uint64_t)a << (unsigned)b; /* unsigned shift is defined */
    return alder_i64_from_twos_bits(r, out);
}

static inline bool alder_i64_shr_checked(int64_t a, int64_t b, int64_t *out) {
    if (out == NULL || b < 0 || b >= 64) {
        return false;
    }
    uint64_t u = (uint64_t)a >> (unsigned)b;
    if (a < 0 && b > 0) {
        /* Arithmetic shift: sign-extend the shifted-out bits. */
        u |= ~(UINT64_MAX >> (unsigned)b);
    }
    return alder_i64_from_twos_bits(u, out);
}

static inline bool alder_u64_add_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || a > UINT64_MAX - b) {
        return false;
    }
    *out = a + b;
    return true;
}

static inline bool alder_u64_sub_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || a < b) {
        return false;
    }
    *out = a - b;
    return true;
}

static inline bool alder_u64_mul_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || (a != 0 && b > UINT64_MAX / a)) {
        return false;
    }
    *out = a * b;
    return true;
}

static inline bool alder_u64_div_checked(uint64_t a, uint64_t b, uint64_t *out) {
    (void)a;
    if (out == NULL || b == 0) {
        return false;
    }
    *out = a / b;
    return true;
}

static inline bool alder_u64_shl_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || b >= 64) {
        return false;
    }
    *out = a << (unsigned)b;
    return true;
}

static inline bool alder_u64_shr_checked(uint64_t a, uint64_t b, uint64_t *out) {
    if (out == NULL || b >= 64) {
        return false;
    }
    *out = a >> (unsigned)b;
    return true;
}

/*
 * Saturating helpers for the non-terminating integer arithmetic. Each returns
 * the clamped result at 64-bit bounds; narrower widths clamp against their own
 * bounds in generated code, which matches saturation at that width exactly
 * because the 64-bit result stays on the same side of the narrow bound.
 * Signed arithmetic stays defined: overflow is detected with the same
 * predicates the checked helpers use, never via signed overflow.
 */
static inline int64_t alder_i64_add_saturating(int64_t a, int64_t b) {
    if (b > 0 && a > INT64_MAX - b) {
        return INT64_MAX;
    }
    if (b < 0 && a < INT64_MIN - b) {
        return INT64_MIN;
    }
    return a + b;
}

static inline int64_t alder_i64_sub_saturating(int64_t a, int64_t b) {
    if (b < 0 && a > INT64_MAX + b) {
        return INT64_MAX;
    }
    if (b > 0 && a < INT64_MIN + b) {
        return INT64_MIN;
    }
    return a - b;
}

static inline int64_t alder_i64_mul_saturating(int64_t a, int64_t b) {
    if (a == 0 || b == 0) {
        return 0;
    }
    if ((a == INT64_MIN && b == -1) || (a == -1 && b == INT64_MIN)) {
        return INT64_MAX;
    }
    bool neg = (a < 0) != (b < 0);
    uint64_t ua = a < 0 ? (uint64_t)0 - (uint64_t)a : (uint64_t)a;
    uint64_t ub = b < 0 ? (uint64_t)0 - (uint64_t)b : (uint64_t)b;
    uint64_t limit = neg ? ((uint64_t)INT64_MAX + (uint64_t)1)
                         : (uint64_t)INT64_MAX;
    if (ua > limit / ub) {
        return neg ? INT64_MIN : INT64_MAX;
    }
    uint64_t prod = ua * ub;
    if (neg) {
        prod = (uint64_t)0 - prod; /* two's complement negation, defined in
                                      unsigned arithmetic */
    }
    int64_t out = 0;
    if (!alder_i64_from_twos_bits(prod, &out)) {
        return neg ? INT64_MIN : INT64_MAX;
    }
    return out;
}

static inline uint64_t alder_u64_add_saturating(uint64_t a, uint64_t b) {
    if (a > UINT64_MAX - b) {
        return UINT64_MAX;
    }
    return a + b;
}

static inline uint64_t alder_u64_sub_saturating(uint64_t a, uint64_t b) {
    if (a < b) {
        return 0;
    }
    return a - b;
}

static inline uint64_t alder_u64_mul_saturating(uint64_t a, uint64_t b) {
    if (a != 0 && b > UINT64_MAX / a) {
        return UINT64_MAX;
    }
    return a * b;
}

/*
 * Wrapping helpers: two's complement arithmetic modulo 2^64. Signed wrapping
 * computes in unsigned arithmetic (defined for every operand pair) and reads
 * the bit pattern back, so no signed operation overflows.
 */
static inline int64_t alder_i64_add_wrapping(int64_t a, int64_t b) {
    int64_t out = 0;
    if (!alder_i64_from_twos_bits((uint64_t)a + (uint64_t)b, &out)) {
        return 0;
    }
    return out;
}

static inline int64_t alder_i64_sub_wrapping(int64_t a, int64_t b) {
    int64_t out = 0;
    if (!alder_i64_from_twos_bits((uint64_t)a - (uint64_t)b, &out)) {
        return 0;
    }
    return out;
}

static inline int64_t alder_i64_mul_wrapping(int64_t a, int64_t b) {
    int64_t out = 0;
    if (!alder_i64_from_twos_bits((uint64_t)a * (uint64_t)b, &out)) {
        return 0;
    }
    return out;
}

static inline uint64_t alder_u64_add_wrapping(uint64_t a, uint64_t b) {
    return a + b;
}

static inline uint64_t alder_u64_sub_wrapping(uint64_t a, uint64_t b) {
    return a - b;
}

static inline uint64_t alder_u64_mul_wrapping(uint64_t a, uint64_t b) {
    return a * b;
}

/* ------------------------------------------------------------------ */
/* Byte sequences                                                      */
/* ------------------------------------------------------------------ */

/*
 * Strict UTF-8 validation of len bytes at data, used by str.from_bytes
 * lowering. Rejects invalid leading and continuation bytes, truncated
 * sequences, overlong encodings, surrogate code points, and code points
 * beyond U+10FFFF. Embedded NUL bytes are ordinary data. data may be NULL
 * only when len is zero.
 */
static inline bool alder_string_utf8_valid(const uint8_t *data, uint64_t len) {
    if (len == 0) {
        return true;
    }
    if (data == NULL) {
        return false;
    }
    uint64_t i = 0;
    while (i < len) {
        uint8_t b0 = data[i];
        uint32_t cp;
        uint64_t seq;
        if (b0 < 0x80u) {
            i++;
            continue;
        } else if ((b0 & 0xE0u) == 0xC0u) {
            cp = (uint32_t)(b0 & 0x1Fu);
            seq = 2;
        } else if ((b0 & 0xF0u) == 0xE0u) {
            cp = (uint32_t)(b0 & 0x0Fu);
            seq = 3;
        } else if ((b0 & 0xF8u) == 0xF0u) {
            cp = (uint32_t)(b0 & 0x07u);
            seq = 4;
        } else {
            return false;
        }
        if (len - i < seq) {
            return false;
        }
        for (uint64_t j = 1; j < seq; j++) {
            uint8_t bj = data[i + j];
            if ((bj & 0xC0u) != 0x80u) {
                return false;
            }
            cp = (cp << 6) | (uint32_t)(bj & 0x3Fu);
        }
        i += seq;
        /* Reject overlong encodings, surrogates, and out-of-range values. */
        if ((seq == 2 && cp < 0x80u) || (seq == 3 && cp < 0x800u) ||
            (seq == 4 && cp < 0x10000u) || cp > 0x10FFFFu ||
            (cp >= 0xD800u && cp <= 0xDFFFu)) {
            return false;
        }
    }
    return true;
}

/*
 * Defined float-to-integer conversion for int.from_float lowering. Returns
 * false for NaN and for values outside the destination range (truncation
 * toward zero inside the range). Narrow destinations range-check the
 * 64-bit result.
 */
bool alder_i64_from_f64(double v, int64_t *out);
bool alder_u64_from_f64(double v, uint64_t *out);

/*
 * IEEE-754 division with a defined zero divisor for float.div lowering.
 * A zero divisor yields the IEEE result: signed infinity with the XOR of
 * the operand signs, or NaN for 0/0 and NaN operands. A nonzero divisor
 * performs the plain defined division.
 */
double alder_f64_div(double a, double b);
float alder_f32_div(float a, float b);

/* ------------------------------------------------------------------ */
/* Scoped cleanup                                                      */
/* ------------------------------------------------------------------ */

typedef void (*AlderCleanupFn)(void *context);

typedef struct AlderCleanupEntry AlderCleanupEntry;
typedef AlderCleanupEntry *AlderCleanupId;

/* Caller-owned scope; must be zero-initialized or freshly ended before
 * alder_cleanup_scope_begin. Entries are heap-allocated by the runtime and
 * freed at alder_cleanup_end. */
typedef struct AlderCleanupScope {
    AlderCleanupEntry *armed_head;
    AlderCleanupEntry *spent_head;
    bool ran;
    bool active;
} AlderCleanupScope;

/* Activate a scope. Returns false when the scope is already active. */
bool alder_cleanup_scope_begin(AlderCleanupScope *scope);

/*
 * Register a cleanup entry. The context must stay valid until the scope
 * runs or the entry is disarmed. Returns false on an inactive scope, a NULL
 * fn or out_id, or out of memory.
 */
bool alder_cleanup_push(AlderCleanupScope *scope, AlderCleanupFn fn,
                        void *context, AlderCleanupId *out_id);

/*
 * Disarm an armed entry so the next run skips it. Returns false for a NULL
 * or already-disarmed id. Disarming an id whose scope already ran or ended
 * is a contract violation (the MIR verifier rejects it).
 */
bool alder_cleanup_disarm(AlderCleanupId id);

/*
 * Execute the armed entries of the scope in reverse registration order,
 * each exactly once, then mark them spent. Returns false when the scope is
 * inactive. Pushing or disarming during a run is a contract violation.
 */
bool alder_cleanup_run(AlderCleanupScope *scope);

/*
 * Close a scope and free all of its entries. Returns false when the scope
 * was not run or still has armed entries (contract violation: the MIR
 * verifier requires run before end); entries are still released so nothing
 * leaks.
 */
bool alder_cleanup_end(AlderCleanupScope *scope);

/* ------------------------------------------------------------------ */
/* Generational tables                                                 */
/* ------------------------------------------------------------------ */

/* Slot internals; referenced through the opaque pointer in AlderTable. */
typedef struct AlderTableSlot AlderTableSlot;

/*
 * Caller-owned table storage. The layout is part of the ABI because
 * generated code and tests embed the struct; treat the fields as internal.
 * The struct must be zero-initialized before alder_table_init. After its
 * domain is reset or destroyed, the old table is invalid and the caller may
 * explicitly zero the struct before initializing a new table in it. The
 * runtime never frees the struct itself.
 */
struct AlderTable {
    uint64_t serial;
    uint64_t capacity;
    uint64_t count;
    uint64_t elem_size;
    uint64_t elem_align;
    uint64_t generation_counter;
    uint64_t domain_serial;
    uint64_t domain_epoch;
    struct AlderDomain *domain;
    AlderTableSlot *slots;
};
typedef struct AlderTable AlderTable;

/* Typed id(elem) value: the table serial, the slot, and the generation at
 * insert time. The serial is globally unique, so an id can never resolve
 * against an unrelated table, even one that reuses the same address. */
typedef struct {
    uint64_t table_serial;
    uint64_t slot;
    uint64_t generation;
} AlderTableId;

/*
 * Initialize a table whose element storage lives in domain. Returns false
 * when the domain is not initialized, elem_size is zero, elem_align is not
 * a power of two, or the initial slot array cannot be allocated. The struct
 * is caller-owned; every successful reset or destruction of its domain
 * invalidates the table (the MIR verifier prevents such uses). Values not
 * representable as size_t and exhausted runtime identity namespaces also
 * fail without modifying the table.
 */
bool alder_table_init(AlderTable *table, AlderDomain *domain,
                      uint64_t elem_size, uint64_t elem_align);

/*
 * Copy elem into table storage and return its fresh id. Returns false on an
 * invalid table, a NULL elem or out_id, or out of memory. Generation values
 * are unique within the table's lifetime, so a removed slot never reuses a
 * previous generation; insertion permanently fails after that namespace is
 * exhausted.
 */
bool alder_table_insert(AlderTable *table, const void *elem,
                        AlderTableId *out_id);

/*
 * Resolve an id to the element storage (the scoped view). Validation
 * order: table identity, slot bounds, occupancy, generation. Returns false
 * for a stale id, an id of another table, or an invalid table. The element
 * pointer stays valid memory until the domain releases it; M2 tables never
 * compact.
 */
bool alder_table_lookup(AlderTable *table, AlderTableId id, void **out_elem);
bool alder_table_lookup_mut(AlderTable *table, AlderTableId id,
                            void **out_elem);

/*
 * Remove the object: the slot becomes empty and can be reused with a fresh
 * generation, so stale ids never resolve to the replacement. Element
 * storage is reclaimed by the domain, not here. Returns false for an
 * invalid or stale id.
 */
bool alder_table_remove(AlderTable *table, AlderTableId id);

/* ------------------------------------------------------------------ */
/* Diagnostics                                                         */
/* ------------------------------------------------------------------ */

/*
 * Terminate the process with status 101 and a message on stderr. Used by
 * generated code for unchecked runtime failures (out-of-memory, identity exhaustion,
 * unreachable execution, out-of-range float-to-int conversion). Checked MIR
 * operations never reach this function. Never returns.
 */
_Noreturn void alder_runtime_panic(const char *message);

/*
 * Mark declarations that may legitimately go unused in a translation unit:
 * generated static helpers are only referenced by some drivers. Portable
 * C11 has no unused attribute, so the marker is a no-op outside GCC/Clang.
 */
#if defined(__GNUC__) || defined(__clang__)
#define ALDER_MAYBE_UNUSED __attribute__((unused))
#else
#define ALDER_MAYBE_UNUSED
#endif

/*
 * c.CString construction and release: a malloc-owned NUL-terminated copy of
 * Alder text. alder_cstring_make scans for an interior NUL and reports 1
 * without touching *out; 0 means *out holds the fresh buffer; negative
 * means allocation failure. alder_cstring_make_lit skips the scan (the
 * checker proves the bytes interior-NUL free) and returns NULL only on
 * allocation failure. alder_cstring_release frees the buffer once.
 */
int alder_cstring_make(const uint8_t *data, uint64_t len, char **out);
char *alder_cstring_make_lit(const uint8_t *data, uint64_t len);
void alder_cstring_release(char *buffer);

#ifdef __cplusplus
}
#endif

#endif /* ALDER_RUNTIME_H */
