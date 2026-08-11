# C11 Backend

Status: Milestone 3 lowering contract with a working Go implementation

The Aster backend (`cgen` package) emits conservative, portable, inspectable C11 from verified Aster MIR. Its purpose is to validate Aster MIR semantics and provide a bootstrap path, not to make C the semantic definition of Aster.

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

Only verified MIR may reach code generation: `cgen.Generate` runs the full verifier and refuses invalid modules with the verifier diagnostics. The backend must not silently repair invalid domain, cleanup, type, or table-view behavior.

## Milestone 3 Lowering Contract

### Naming and layout

- generated identifiers derive from stable numeric IDs: `aster_v<N>` for values, `aster_l<N>` for locals, `aster_b<N>` for block labels, `AsterTy<N>` for struct types, `AsterFnTy<N>` for function-pointer typedefs, `aster_fn_<name>_<id>` for functions, `aster_copy_ty<N>` for copy helpers, `aster_str_<N>` for string constants, and `aster_domain_<N>`, `aster_scope_<N>`, `AsterCtx_<N>`, `aster_ctx_<N>`, `aster_cleanup_<N>` for hidden slots, contexts, and cleanup adapters;
- source aggregate field names never become C members: fields use declaration ordinals (`aster_f<N>`), preventing sanitized-name collisions. Types and copy helpers are emitted in stable dependency-first order, with forward typedefs for record-like types;
- all generated statics carry `ASTER_MAYBE_UNUSED` so drivers and dead MIR code compile under `-Werror`.

### Type mapping

- `unit` is represented by `(uint8_t)0` only where storage or an expression is required; unit SSA declarations and assignments are erased. It is `void` as a function result, while unit parameters and call arguments are omitted, which is exact because unit has exactly one value;
- `bool` maps to `bool`; integers to the exact-width `intN_t`/`uintN_t` (which C11 requires to be two's complement); floats to `float`/`double`;
- aggregates and enum-like types (declared enums, `option`, `result`) map to structs: fields in declaration order; enums are tagged unions with `uint32_t aster_tag` (variant index) and a union of non-unit payloads named `aster_p<index>`. An empty aggregate has one private byte because portable C11 has no empty structs;
- `slice`, `safe_ref`, and `safe_mut` share the runtime `AsterSlice { void *data; uint64_t len; }`; `table_view`/`table_mut_view` are `void *` pointers to element storage; `raw_ptr(T)` is `void *`; `domain_handle` is `AsterDomain *`; `domain_mark`, `cleanup_id`, and `id(T)` map to their runtime structs; `table(T)` is `AsterTable *`, preserving one mutable table identity through calls, locals, aggregates, and block parameters; `cleanup_scope` is `AsterCleanupScope *` pointing at a per-create-site slot;
- `function(Signature)` maps to an `AsterFnTy<N>` function-pointer typedef; an empty C parameter list is written as `(void)`.

### Values and control flow

- every non-unit MIR value becomes one C variable; block parameters are C variables assigned at every edge before the `goto`. Edge arguments are first captured in typed temporaries and then assigned to parameters, preserving MIR's parallel-copy semantics for swaps and cycles;
- blocks lower to labels (`aster_b<N>`); the entry block needs no label because it has no predecessors; dead blocks keep their code and `unreachable` lowers to `aster_runtime_panic("unreachable")`;
- `return` and `fail` both lower to `return <result>;` (the distinction is semantic, for diagnostics);
- switch dispatches on the tag with `case (uint32_t)<variant index>`; case payload bindings are assigned from the union before the edge assignments.

### Sequencing and side effects

- every MIR instruction lowers to one or more explicit C statements in order; instruction-local temporaries are declared at their use site;
- call arguments are reads of already-computed variables, so the unspecified C evaluation order of function arguments is unobservable;
- every value use is a simple lvalue read; there are no side-effecting expressions.

### Checked operations and failure edges

- 64-bit checked operations call the runtime helper and branch to the MIR failure edge on false;
- narrow non-shift operations promote operands to 64 bits, compute with the helper, range-check the result against the narrow limits, and cast; the narrow operation fails exactly when the promoted computation or the range check fails;
- narrow shifts check the count against the source width first (unsigned counts only against the width), then compute at that width: unsigned targets wrap by casting, signed left shifts transfer the width-bit two's-complement pattern with `memcpy`, and signed right shifts use unsigned shifting plus explicit sign-bit fill rather than C's implementation-defined signed `>>`;
- failure edges use the same parallel-copy temporaries as ordinary edges before the `goto`;
- `slice.index.checked` lowers to the runtime bounds check, a checked byte-offset multiply, a `SIZE_MAX` representability check, and a one-element `AsterSlice`; `slice.range.checked` lowers to the same checks and `hi - lo` length. `{NULL, 0}` accepts only `[0, 0)` and performs no pointer arithmetic; `{NULL, len>0}` is rejected as malformed;
- `int.trunc` to an unsigned target wraps by casting; to a signed target it transfers the two's-complement bit pattern with `memcpy`;
- `float.convert` from `f64` to `f32` checks NaN, infinity, and `FLT_MAX` bounds before casting; rejected values terminate rather than reaching C11 undefined behavior. `int.from_float` uses the defined runtime conversions; out-of-range or NaN values also terminate because both MIR operations are unchecked.

### Domains, cleanup, and tables

- `domain.create` initializes a hidden per-site `AsterDomain` slot and the handle value points to it; re-creating after destroy re-initializes the same slot, which is sound because MIR 1 forbids carrying handles across backedges;
- `domain.mark`/`reset`/`destroy` call the runtime directly; reset and destroy failures are contract violations and terminate;
- `alloc` lowers to a checked count-times-size multiply, a `SIZE_MAX` representability check, `aster_domain_alloc`, and a slice with the count; overflow and out-of-memory terminate;
- `copy_to_domain` is identity for copy-trivial types and calls a generated per-type copy helper otherwise; helpers deep-copy aggregates and enum payloads recursively and copy slice element bytes into the destination domain after checking `SIZE_MAX` and rejecting a non-empty null source. A slice whose element type contains references is rejected at generation time (M3 copies bytes, so a nested reference would be shared instead of copied);
- `cleanup.scope.begin` initializes a hidden per-site scope slot; `cleanup.push` fills a per-site context struct and registers a generated adapter; `disarm`, `run`, and `end` call the runtime and terminate on contract violations;
- `table.create` allocates a zeroed `AsterTable` header in the owning domain and returns its pointer. The header therefore survives an ordinary callee return, all aliases observe growth, and repeated execution of one create site receives fresh storage; `table.insert`/`lookup`/`lookup_mut`/`remove` call the runtime; lookups build the option view (`tag 1`/`0`) with explicit sequencing; `table.view.end` lowers to a no-op because M2 tables never compact and the verifier enforces view discipline.

### Calls and C ABI

- ordinary calls lower to direct calls of the generated static functions, with unit arguments omitted;
- `ffi.call.unsafe` lowers to the import symbol unchanged and parenthesizes it at declaration and call sites so a function-like macro cannot expand; the generated file declares every import prototype so calls are never implicit;
- import names double as C symbols and must be backend-safe C identifiers. The verifier rejects C keywords, leading underscores, generated/runtime prefixes, names ending `_t`, macro-style uppercase names, `main`, and identifiers declared by always-included headers; retention and cleanup claims remain deferred.

### Constants and strings

- scalar constants inline as typed literals (`INT64_MIN` uses the portable `(-9223372036854775807LL - 1)` form; negative zero prints as `-0.0`);
- string constants reference possibly-unused static byte arrays named by their module constant IDs; non-printable bytes use exactly three octal digits, so an immediately following digit cannot be consumed by the escape.

### Unchecked failure policy

Unchecked runtime failures (allocation failure, identity exhaustion, rejected float narrowing or float-to-int conversion, `unreachable` execution, and runtime contract violations the verifier already rejects) terminate the process with a fixed message via `aster_runtime_panic`. Checked MIR operations never reach it; they always branch to their explicit failure edge.

### Documented M3 limitations

- `copy_to_domain` of a slice whose elements contain references is rejected rather than copied shallowly;
- unit-typed function parameters are dropped from the C ABI (semantically exact);
- `fail` and `return` lower identically;
- MIR modules containing unused functions compile because generated statics are marked possibly-unused;
- a MIR interpreter for differential testing is not implemented; the compile-and-run fixtures provide the behavioral evidence.

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
if (!aster_i64_add_checked(aster_tmp_a, aster_tmp_b, &aster_tmp_sum)) {
    goto aster_overflow;
}
```

It must not combine these into a C expression whose evaluation order differs from MIR.

## Integer Semantics

Generated C must not use undefined signed overflow to implement Aster arithmetic. The Milestone 2 runtime provides checked 64-bit helpers (`aster_i64_*` and `aster_u64_*` in `runtime/c/aster.h`) for add, sub, mul, div, and the distinct `int.shl.checked` and `int.shr.checked` operations, plus defined float-to-integer conversions. Narrow non-shift MIR integer operations lower by promoting operands to 64 bits, computing with the checked helpers, and range-checking the result against the narrow type; the narrow operation fails exactly when the promoted computation or the range check fails.

Narrow shifts are width-aware and must not be implemented by blindly calling a 64-bit helper followed by a range check. The backend first rejects a count greater than or equal to the source width. Left shift masks the result to that width and reconstructs the signed value from the width-bit two's-complement pattern; unsigned right shift is logical, while signed right shift sign-extends from the source width. For example, `i8(127) shl i8(1)` produces `i8(-2)`, while either `i8` or `u8` shifted by eight takes its checked failure edge.

Shift semantics are defined on the two's-complement bit pattern: left shifts wrap, right shifts are arithmetic for signed values and logical for unsigned. The 64-bit helpers fail on shift counts below zero or at or above 64; narrow lowering applies the source-width check described above. Division fails on division by zero and on `INT64_MIN / -1`.

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
    uint64_t domain_serial;
    uint64_t reset_epoch;
    uint64_t segment_serial;
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

- `aster_domain_init` returns false for a double init, an uninitialized or
destroyed parent, or exhausted process-wide domain identities; the struct must
be zero-initialized or freshly destroyed;
- `aster_domain_alloc` returns NULL when the domain is not initialized, the
alignment is not a power of two (or zero), size plus alignment slack
overflows `size_t`, memory is exhausted, or stable segment identities are
exhausted. A zero size allocates one byte;
- `aster_domain_reset` returns false for a destroyed domain, an exhausted reset
epoch, a mark from another domain or an earlier reset epoch, a segment identity
that is no longer active, or an offset past the segment frontier;
- `aster_domain_destroy` is a no-op on uninitialized or already-destroyed
domains; destroying a parent recursively destroys its children.

Lifetime contracts:

- domain structs are caller-owned; the runtime never frees them;
- a child domain cannot outlive its parent: destroying the parent destroys
children first, so any later child destroy is a no-op;
- allocations stay valid until the domain is reset past them or destroyed;
- a mark made before the first allocation can reset a non-empty domain back to
empty;
- reset releases every segment after the marked one; pointers into released
storage become invalid, and the MIR verifier prevents their use;
- every successful reset consumes every mark from the previous domain epoch;
marks use stable integer identities rather than pointers into segment storage,
so released storage is never retained or compared through a stale pointer.

Implementation policy: domains and segments receive non-reusing process-wide
identities; namespace exhaustion is a permanent allocation failure rather than
wraparound. Segments are single heap blocks (header plus a 16-aligned data
area); allocations bump with per-allocation alignment; regular segments double
up to 1 MiB; larger requests receive a dedicated exact-size segment. The
runtime tracks its live heap blocks in one counter so tests can prove leak-free
create/reset/destroy cycles without a leak sanitizer.

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
`runtime/c/aster.h`. The table serial comes from a non-wrapping global counter,
so an id never resolves against an unrelated table even when a fresh table
reuses the same address; exhaustion permanently fails later initialization.
Slot generations likewise fail before wraparound, so a removed slot never
reuses a generation and stale ids cannot resolve to a replacement object.
Initialization validates `size_t` representability and publishes the caller's
table struct only after all fallible work succeeds.

Lookup performs, in order:

1. table identity validation (serial match, live domain);
2. slot bounds validation;
3. occupancy validation;
4. generation comparison;
5. creation of a scoped view (a pointer to the element storage).

Element storage and the slot array are allocated from the table's domain;
removal marks the slot empty but leaves element storage in the domain until
reset or destroy. Every successful domain reset changes the domain epoch and
invalidates all of its existing tables; MIR 1 enforces this conservatively
because inserts and slot growth contain hidden runtime allocations. M2 tables
never compact, so a view stays valid memory until the domain releases it.
`table.view.end` lowers to nothing in M2; the verifier enforces view discipline.
Compaction may update slot-to-storage mappings while preserving IDs; it must
not run while an incompatible view is active, and it is deferred.

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
