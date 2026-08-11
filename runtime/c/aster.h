/*
 * Aster minimal C runtime ABI.
 *
 * Portable C11. This header is the contract between verified Aster MIR
 * lowering and the runtime; docs/c-backend.md owns the detailed failure and
 * lifetime contracts and the undefined-behavior policy. All functions are
 * usable from ordinary C11 and never depend on host addresses or paths.
 *
 * Conventions:
 *  - every function that can fail returns bool (or NULL) and leaves output
 *    parameters untouched on failure, unless stated otherwise;
 *  - structures are caller-owned: the runtime allocates and frees only its
 *    own internal storage, never the caller's structs;
 *  - the runtime assumes a single-threaded process for now (structured
 *    concurrency is outside the current scope).
 */
#ifndef ASTER_RUNTIME_H
#define ASTER_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Storage domains                                                     */
/* ------------------------------------------------------------------ */

/* Segment internals; only referenced through the opaque pointer in
 * AsterDomain and through domain marks. */
typedef struct AsterSegment AsterSegment;

/*
 * Caller-owned domain storage. The layout is part of the ABI because
 * generated code and tests embed the struct; treat the fields as internal.
 * The struct must be zero-initialized or freshly destroyed before
 * aster_domain_init. The runtime never frees the struct itself.
 */
struct AsterDomain {
    uint32_t magic;
    uint64_t serial;
    uint64_t reset_epoch;
    struct AsterDomain *parent;
    struct AsterDomain *children_head;
    struct AsterDomain *next_sibling;
    AsterSegment *segments_head;
    AsterSegment *segments_tail;
    size_t segment_count;
};
typedef struct AsterDomain AsterDomain;

/* A resettable frontier of one domain epoch. Integer identities avoid retaining
 * or comparing pointers after segment storage has been released. */
typedef struct {
    uint64_t domain_serial;
    uint64_t reset_epoch;
    uint64_t segment_serial; /* zero denotes the frontier before all segments */
    size_t offset;
} AsterDomainMark;

/*
 * Initialize a domain. The struct must be zero-initialized or freshly
 * destroyed. parent may be NULL (a root domain) or an initialized domain; a
 * child domain cannot outlive its parent. Returns false when the struct is
 * already initialized, the parent is not initialized, or the process-wide
 * domain identity namespace is exhausted.
 */
bool aster_domain_init(AsterDomain *domain, AsterDomain *parent);

/*
 * Allocate size bytes aligned to align (a power of two) in the domain.
 * Returns NULL on failure: uninitialized or destroyed domain, align not a
 * power of two (or zero), size/alignment overflow, or out of memory.
 * Exhaustion of the segment identity namespace is also reported as failure.
 * size == 0 allocates one byte. Allocations stay valid until the domain is
 * reset past them or destroyed; the returned pointer is never NULL on success
 * and must not be freed by the caller.
 */
void *aster_domain_alloc(AsterDomain *domain, size_t size, size_t align);

/*
 * Return the current allocation frontier. A mark of an uninitialized or
 * destroyed domain has zero identities and is never accepted by reset.
 */
AsterDomainMark aster_domain_mark(AsterDomain *domain);

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
bool aster_domain_reset(AsterDomain *domain, AsterDomainMark mark);

/*
 * Release all storage of the domain, recursively destroy its child domains
 * (children cannot outlive their parent), and unregister it from its
 * parent. Destroying an uninitialized or already-destroyed domain is a
 * no-op. The struct is caller-owned and may be re-initialized afterwards.
 */
void aster_domain_destroy(AsterDomain *domain);

/* Number of heap blocks currently owned by the runtime (segments and
 * cleanup entries). Tests use it to prove leak-free domain lifecycles. */
size_t aster_runtime_live_allocations(void);

/* ------------------------------------------------------------------ */
/* Slices and bounds                                                   */
/* ------------------------------------------------------------------ */

/* Dynamic-array ABI: a possibly-null data pointer and an element count.
 * slice, safe_ref, and safe_mut values share this representation. */
typedef struct {
    void *data;
    uint64_t len;
} AsterSlice;

/* Bounds checks used by slice.index.checked and slice.range.checked. A NULL
 * data pointer is valid only for a zero-length slice; its sole valid range is
 * [0, 0), while indexing and every range of {NULL, len>0} fail. */
bool aster_slice_index_checked(AsterSlice slice, uint64_t index);
bool aster_slice_range_checked(AsterSlice slice, uint64_t lo, uint64_t hi);

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
bool aster_i64_add_checked(int64_t a, int64_t b, int64_t *out);
bool aster_i64_sub_checked(int64_t a, int64_t b, int64_t *out);
bool aster_i64_mul_checked(int64_t a, int64_t b, int64_t *out);
bool aster_i64_div_checked(int64_t a, int64_t b, int64_t *out);
bool aster_i64_shl_checked(int64_t a, int64_t b, int64_t *out);
bool aster_i64_shr_checked(int64_t a, int64_t b, int64_t *out);
bool aster_u64_add_checked(uint64_t a, uint64_t b, uint64_t *out);
bool aster_u64_sub_checked(uint64_t a, uint64_t b, uint64_t *out);
bool aster_u64_mul_checked(uint64_t a, uint64_t b, uint64_t *out);
bool aster_u64_div_checked(uint64_t a, uint64_t b, uint64_t *out);
bool aster_u64_shl_checked(uint64_t a, uint64_t b, uint64_t *out);
bool aster_u64_shr_checked(uint64_t a, uint64_t b, uint64_t *out);

/*
 * Defined float-to-integer conversion for int.from_float lowering. Returns
 * false for NaN and for values outside the destination range (truncation
 * toward zero inside the range). Narrow destinations range-check the
 * 64-bit result.
 */
bool aster_i64_from_f64(double v, int64_t *out);
bool aster_u64_from_f64(double v, uint64_t *out);

/* ------------------------------------------------------------------ */
/* Scoped cleanup                                                      */
/* ------------------------------------------------------------------ */

typedef void (*AsterCleanupFn)(void *context);

typedef struct AsterCleanupEntry AsterCleanupEntry;
typedef AsterCleanupEntry *AsterCleanupId;

/* Caller-owned scope; must be zero-initialized or freshly ended before
 * aster_cleanup_scope_begin. Entries are heap-allocated by the runtime and
 * freed at aster_cleanup_end. */
typedef struct AsterCleanupScope {
    AsterCleanupEntry *armed_head;
    AsterCleanupEntry *spent_head;
    bool ran;
    bool active;
} AsterCleanupScope;

/* Activate a scope. Returns false when the scope is already active. */
bool aster_cleanup_scope_begin(AsterCleanupScope *scope);

/*
 * Register a cleanup entry. The context must stay valid until the scope
 * runs or the entry is disarmed. Returns false on an inactive scope, a NULL
 * fn or out_id, or out of memory.
 */
bool aster_cleanup_push(AsterCleanupScope *scope, AsterCleanupFn fn,
                        void *context, AsterCleanupId *out_id);

/*
 * Disarm an armed entry so the next run skips it. Returns false for a NULL
 * or already-disarmed id. Disarming an id whose scope already ran or ended
 * is a contract violation (the MIR verifier rejects it).
 */
bool aster_cleanup_disarm(AsterCleanupId id);

/*
 * Execute the armed entries of the scope in reverse registration order,
 * each exactly once, then mark them spent. Returns false when the scope is
 * inactive. Pushing or disarming during a run is a contract violation.
 */
bool aster_cleanup_run(AsterCleanupScope *scope);

/*
 * Close a scope and free all of its entries. Returns false when the scope
 * was not run or still has armed entries (contract violation: the MIR
 * verifier requires run before end); entries are still released so nothing
 * leaks.
 */
bool aster_cleanup_end(AsterCleanupScope *scope);

/* ------------------------------------------------------------------ */
/* Generational tables                                                 */
/* ------------------------------------------------------------------ */

/* Slot internals; referenced through the opaque pointer in AsterTable. */
typedef struct AsterTableSlot AsterTableSlot;

/*
 * Caller-owned table storage. The layout is part of the ABI because
 * generated code and tests embed the struct; treat the fields as internal.
 * The struct must be zero-initialized before aster_table_init. After its
 * domain is reset or destroyed, the old table is invalid and the caller may
 * explicitly zero the struct before initializing a new table in it. The
 * runtime never frees the struct itself.
 */
struct AsterTable {
    uint64_t serial;
    uint64_t capacity;
    uint64_t count;
    uint64_t elem_size;
    uint64_t elem_align;
    uint64_t generation_counter;
    uint64_t domain_serial;
    uint64_t domain_epoch;
    struct AsterDomain *domain;
    AsterTableSlot *slots;
};
typedef struct AsterTable AsterTable;

/* Typed id(elem) value: the table serial, the slot, and the generation at
 * insert time. The serial is globally unique, so an id can never resolve
 * against an unrelated table, even one that reuses the same address. */
typedef struct {
    uint64_t table_serial;
    uint64_t slot;
    uint64_t generation;
} AsterTableId;

/*
 * Initialize a table whose element storage lives in domain. Returns false
 * when the domain is not initialized, elem_size is zero, elem_align is not
 * a power of two, or the initial slot array cannot be allocated. The struct
 * is caller-owned; every successful reset or destruction of its domain
 * invalidates the table (the MIR verifier prevents such uses). Values not
 * representable as size_t and exhausted runtime identity namespaces also
 * fail without modifying the table.
 */
bool aster_table_init(AsterTable *table, AsterDomain *domain,
                      uint64_t elem_size, uint64_t elem_align);

/*
 * Copy elem into table storage and return its fresh id. Returns false on an
 * invalid table, a NULL elem or out_id, or out of memory. Generation values
 * are unique within the table's lifetime, so a removed slot never reuses a
 * previous generation; insertion permanently fails after that namespace is
 * exhausted.
 */
bool aster_table_insert(AsterTable *table, const void *elem,
                        AsterTableId *out_id);

/*
 * Resolve an id to the element storage (the scoped view). Validation
 * order: table identity, slot bounds, occupancy, generation. Returns false
 * for a stale id, an id of another table, or an invalid table. The element
 * pointer stays valid memory until the domain releases it; M2 tables never
 * compact.
 */
bool aster_table_lookup(AsterTable *table, AsterTableId id, void **out_elem);
bool aster_table_lookup_mut(AsterTable *table, AsterTableId id,
                            void **out_elem);

/*
 * Remove the object: the slot becomes empty and can be reused with a fresh
 * generation, so stale ids never resolve to the replacement. Element
 * storage is reclaimed by the domain, not here. Returns false for an
 * invalid or stale id.
 */
bool aster_table_remove(AsterTable *table, AsterTableId id);

/* ------------------------------------------------------------------ */
/* Diagnostics                                                         */
/* ------------------------------------------------------------------ */

/*
 * Terminate the process with a message on stderr. Used by generated code
 * for unchecked runtime failures (out-of-memory, identity exhaustion,
 * unreachable execution, out-of-range float-to-int conversion). Checked MIR
 * operations never reach this function. Never returns.
 */
_Noreturn void aster_runtime_panic(const char *message);

/*
 * Mark declarations that may legitimately go unused in a translation unit:
 * generated static helpers are only referenced by some drivers. Portable
 * C11 has no unused attribute, so the marker is a no-op outside GCC/Clang.
 */
#if defined(__GNUC__) || defined(__clang__)
#define ASTER_MAYBE_UNUSED __attribute__((unused))
#else
#define ASTER_MAYBE_UNUSED
#endif

#ifdef __cplusplus
}
#endif

#endif /* ASTER_RUNTIME_H */
