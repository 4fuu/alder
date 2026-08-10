# C11 Backend

Status: initial backend contract

The first Aster backend emits conservative, portable, inspectable C11. Its purpose is to validate Aster MIR semantics and provide a bootstrap path, not to make C the semantic definition of Aster.

LLVM and other native backends are outside the current scope.

## Pipeline

```text
verified Aster MIR
        |
        v
backend-specific naming and layout
        |
        v
deterministic C11 translation unit
        |
        +---- minimal Aster C runtime
        |
        v
Clang or GCC
```

Only verified MIR may reach code generation. The backend must not silently repair invalid domain, cleanup, type, or table-view behavior.

## Monomorphized Input

The C backend never implements source generics directly. Compile-time `type` parameters are inferred and monomorphized before backend MIR, so every input function, aggregate, table element, and calling convention has a concrete `TypeId` and layout.

Generated C does not receive hidden runtime type arguments merely because the source used generics. Runtime metadata is emitted only for a separate, explicit reflection feature if one is introduced later. Specialized declaration names and ordering must derive from canonical type and function IDs so repeated builds remain deterministic.

## Priorities

In order:

1. preserve defined Aster behavior;
2. avoid C undefined behavior for all safe MIR;
3. generate deterministic output;
4. remain inspectable during semantic debugging;
5. compile on common C11 compilers;
6. optimize only after measurements and semantic tests exist.

## C Dialect

Generated and handwritten runtime code targets C11. Platform-specific extensions may be isolated behind runtime configuration headers, but portable generated code must not require GNU statement expressions, nested functions, or compiler-specific object models.

The initial supported compilers are expected to be recent Clang and GCC. Exact minimum versions will be pinned when executable code exists.

## Evaluation Order

C leaves the order of many subexpressions unspecified. MIR operations with side effects must lower through explicit temporaries and statements.

Aster MIR:

```text
%a = call @left()
%b = call @right()
%sum = int.add.checked %a, %b
```

Generated C must preserve the sequence:

```c
int64_t aster_tmp_a = aster_left();
int64_t aster_tmp_b = aster_right();
int64_t aster_tmp_sum;
if (aster_i64_add_checked(aster_tmp_a, aster_tmp_b, &aster_tmp_sum)) {
    goto aster_overflow;
}
```

It must not combine these into a C expression whose evaluation order differs from MIR.

## Integer Semantics

Generated C must not use undefined signed overflow to implement Aster arithmetic. The Milestone 2 runtime provides checked 64-bit helpers (`aster_i64_*` and `aster_u64_*` in `runtime/c/aster.h`) for add, sub, mul, div, and shifts, plus defined float-to-integer conversions. Narrower MIR integer types lower by promoting operands to 64 bits, computing with the checked helpers, and range-checking the result against the narrow type; the narrow operation fails exactly when the promoted computation or the range check fails.

Shift semantics are defined on the two's-complement bit pattern: left shifts wrap, right shifts are arithmetic for signed values and logical for unsigned. All helpers fail on shift counts below zero or at or above the bit width. Division fails on division by zero and on `INT64_MIN / -1`.

Depending on the final language rule, checked operations lower to:

- the runtime helpers above;
- explicit range checks;
- carefully specified unsigned arithmetic followed by conversion.

The backend must also define lowering for:

- division by zero;
- minimum signed value divided by `-1`;
- shifts greater than or equal to bit width;
- narrowing conversions;
- float-to-integer conversions outside the destination range.

No optimization may assume a checked failure is impossible unless a MIR proof or canonical optimization removed the check first.

## Pointers, Aliasing, and Alignment

Safe MIR references are not arbitrary C pointers. Their lowering must preserve:

- valid lifetime;
- required bounds;
- alignment;
- mutability and view constraints;
- provenance assumptions required by the selected C compilers.

Rules:

- do not perform out-of-object pointer arithmetic merely to compare or cache an address;
- do not cast and dereference a pointer at a stricter alignment than the source guarantees;
- do not type-pun through incompatible lvalues;
- use `memcpy` for unaligned or representation-preserving transfers where necessary;
- do not emit `restrict` until MIR proves the required non-aliasing contract;
- keep raw foreign pointers distinct from safe references in generated helper APIs.

## Bounds Checks

Slice indexing lowers to an explicit check before address calculation:

```c
if (index >= slice.len) {
    goto aster_bounds_failure;
}
value = slice.data[index];
```

The backend must avoid performing invalid pointer arithmetic before the check. A check may disappear only when an earlier MIR pass has proved and removed it.

## Storage Domains

The Milestone 2 runtime ABI is pinned in `runtime/c/aster.h`; the detailed
contracts below are the canonical reference.

```c
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct AsterDomain AsterDomain;   /* layout is ABI, fields internal */
typedef struct {
    void *segment;
    size_t offset;
} AsterDomainMark;

bool aster_domain_init(AsterDomain *domain, AsterDomain *parent);
void *aster_domain_alloc(AsterDomain *domain, size_t size, size_t align);
AsterDomainMark aster_domain_mark(AsterDomain *domain);
bool aster_domain_reset(AsterDomain *domain, AsterDomainMark mark);
void aster_domain_destroy(AsterDomain *domain);
size_t aster_runtime_live_allocations(void);
```

Failure contracts:

- `aster_domain_init` returns false for a double init or an uninitialized or
destroyed parent; the struct must be zero-initialized or freshly destroyed;
- `aster_domain_alloc` returns NULL when the domain is not initialized, the
alignment is not a power of two (or zero), size plus alignment slack
overflows `size_t`, or memory is exhausted. A zero size allocates one byte;
- `aster_domain_reset` returns false for a destroyed domain, a `{NULL, 0}`
mark on a non-empty domain, a mark whose segment is no longer active, or a
mark whose offset exceeds the segment frontier;
- `aster_domain_destroy` is a no-op on uninitialized or already-destroyed
domains; destroying a parent recursively destroys its children.

Lifetime contracts:

- domain structs are caller-owned; the runtime never frees them;
- a child domain cannot outlive its parent: destroying the parent destroys
children first, so any later child destroy is a no-op;
- allocations stay valid until the domain is reset past them or destroyed;
- reset releases every segment after the marked one; pointers into released
storage become invalid, and the MIR verifier prevents their use;
- marks are validated by segment-list membership before any dereference, so
a stale mark into memory the heap already returned to the operating system
is rejected instead of crashing.

Implementation policy: segments are single heap blocks (header plus a
16-aligned data area); allocations bump with per-allocation alignment;
regular segments double up to 1 MiB; larger requests receive a dedicated
exact-size segment. The runtime tracks its live heap blocks in one counter
so tests can prove leak-free create/reset/destroy cycles without a leak
sanitizer.

## Cleanup Lowering

MIR cleanup scopes lower to explicit, visible control flow. The runtime side
(`AsterCleanupScope`, `aster_cleanup_scope_begin/push/disarm/run/end` in
`runtime/c/aster.h`) owns the entry list: pushes register a function pointer
and context, `run` executes armed entries in reverse registration order,
each exactly once, and `end` frees every entry. `end` returns false (and
still releases entries) when the scope was not run or still has armed
entries; the MIR verifier requires run before end on every exit path, so
that state is a contract violation.

Generated C must guarantee reverse order and at-most-once cleanup. C `goto`
is a backend mechanism and does not appear in MIR semantics.

## Generational Tables

The Milestone 2 ABI is `AsterTable` plus `AsterTableId { table_serial, slot,
generation }` and `aster_table_init/insert/lookup/lookup_mut/remove` in
`runtime/c/aster.h`. The table serial comes from a global counter, so an id
never resolves against an unrelated table even when a fresh table reuses the
same address; slot generations are unique within a table's lifetime, so a
removed slot never reuses a generation and stale ids cannot resolve to a
replacement object.

Lookup performs, in order:

1. table identity validation (serial match, live domain);
2. slot bounds validation;
3. occupancy validation;
4. generation comparison;
5. creation of a scoped view (a pointer to the element storage).

Element storage and the slot array are allocated from the table's domain;
removal marks the slot empty but leaves element storage in the domain until
reset or destroy. M2 tables never compact, so a view stays valid memory
until the domain releases it. `table.view.end` lowers to nothing in M2; the
verifier enforces view discipline. Compaction may update slot-to-storage
mappings while preserving IDs; it must not run while an incompatible view
is active, and it is deferred.

## C Interoperability

Imported headers may be included directly in generated C or accessed through generated C shims. The chosen strategy must preserve target ABI without allowing C declarations to leak into MIR semantics.

The backend must distinguish:

- a pointer valid only for the duration of the call;
- a pointer that C may retain;
- memory returned by C with a required release function;
- nullable C pointers;
- C strings and pointer-plus-length buffers;
- callbacks whose lifetime extends beyond the initiating call.

Only explicit `ffi.call.unsafe` MIR operations may invoke arbitrary imported functions.

## Deterministic Output

Generated C must be independent of:

- host memory addresses;
- Go map iteration order;
- absolute checkout paths;
- thread scheduling;
- temporary filenames;
- nondeterministic hash seeds.

Declarations should use stable ID or source order, with deterministic tie-breaking. Generated names should be based on stable module, symbol, and numeric IDs.

An `--emit-c` mode should produce readable output suitable for review. Readability is secondary to correctness but is an important bootstrap diagnostic tool.

## Testing Strategy

The backend requires:

- generated-C golden tests;
- compile-only tests under strict warnings;
- compile-and-run behavior tests;
- ASan and UBSan runs where available;
- boundary tests for every checked arithmetic operation;
- stale-ID and table-compaction tests;
- cleanup tests for success and each failure edge;
- C FFI fixtures covering temporary, retained, nullable, and externally freed pointers;
- deterministic-output tests across repeated processes.

When a MIR interpreter exists, generated C should be differentially tested against it. The interpreter is optional until evidence shows that it materially improves semantic validation.

## Explicitly Deferred

- LLVM IR generation;
- target-specific vector intrinsics beyond isolated runtime helpers;
- exception unwinding integration;
- link-time optimization orchestration;
- direct object-file emission;
- debug metadata beyond practical `#line` support;
- aggressive C source optimization.
