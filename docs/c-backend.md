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

Generated C must not use undefined signed overflow to implement Aster arithmetic.

Depending on the final language rule, checked operations lower to:

- compiler builtins behind a portable runtime wrapper;
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

Initial runtime operations should have a small C ABI, conceptually:

```c
#include <stdbool.h>
#include <stddef.h>

typedef struct AsterDomain AsterDomain;
typedef struct {
    void *segment;
    size_t offset;
} AsterDomainMark;

bool aster_domain_init(AsterDomain *domain, AsterDomain *parent);
void *aster_domain_alloc(AsterDomain *domain, size_t size, size_t align);
AsterDomainMark aster_domain_mark(AsterDomain *domain);
void aster_domain_reset(AsterDomain *domain, AsterDomainMark mark);
void aster_domain_destroy(AsterDomain *domain);
```

The exact ABI is not yet fixed. All size and alignment calculations must be checked for overflow. Reset and destroy behavior must be testable under ASan and UBSan.

Result values should be constructed directly in caller-provided storage when MIR represents destination construction. The C backend should not introduce temporary aggregate copies merely for convenience.

## Cleanup Lowering

MIR cleanup scopes lower to explicit, visible control flow. An initial implementation may use one cleanup label per canonical scope:

```c
AsterResult result = ASTER_OK;
AsterFile file = {0};
bool file_active = false;

result = aster_file_open(path, &file);
if (result.failed) goto cleanup;
file_active = true;

/* body */

cleanup:
if (file_active) {
    aster_file_close(&file);
    file_active = false;
}
return result;
```

Generated control flow must guarantee reverse order and at-most-once cleanup. C `goto` is a backend mechanism and does not appear in MIR semantics.

## Generational Tables

The runtime representation must include enough identity to prevent a typed ID from resolving against an unrelated table or reused generation.

Lookup performs, in order:

1. table/type identity validation where represented at runtime;
2. slot bounds validation;
3. occupancy validation;
4. generation comparison;
5. creation of a scoped view.

Compaction may update slot-to-storage mappings while preserving IDs. It must not run while an incompatible view is active.

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
