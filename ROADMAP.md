# Roadmap

This roadmap separates committed near-term work from longer-term direction. Dates are intentionally omitted until implementation velocity and semantic risk are better understood.

## Project Principles

1. Validate semantics before optimizing them.
2. Keep one production path during bootstrap: Alder MIR to C11.
3. Make unsafe behavior explicit and locally auditable.
4. Prefer deterministic, inspectable compiler output.
5. Do not expand the user-facing memory model to fix isolated performance cases.
6. Start self-hosting as soon as a small Alder subset can express the compiler; do not first build a complete compiler in Go.

## Active Scope

### Milestone 0: Design Baseline

Status: **in progress**

Deliverables:

- document language goals, non-goals, and unresolved semantics;
- document compile-time `type` values, type application, inference, and the monomorphization boundary;
- define the first versioned Alder MIR vocabulary;
- define the C11 lowering contract and undefined-behavior policy;
- establish repository, contribution, and orb lifecycle standards;
- choose representative validation programs.

Exit criteria:

- every initial MIR operation has a documented type and effect;
- storage-domain and cleanup invariants can be checked without consulting source syntax;
- the C backend document explains how safe MIR avoids C undefined behavior;
- open questions are explicit rather than hidden behind examples.

### Milestone 1: MIR Toolkit

Status: **complete**

Deliverables:

- a small Go module with no unnecessary third-party dependencies (`mir` and `mir/verify`);
- in-memory MIR types using stable integer IDs rather than pointer-linked compiler graphs;
- deterministic textual MIR parser and printer (format version 1, pinned by golden fixtures);
- MIR verifier with source-independent diagnostics covering all ten documented phases;
- golden tests and invalid-MIR tests with pinned diagnostics.

Exit-criteria evidence:

- parse-print-parse reaches a stable canonical form across all golden, verifier-acceptance, and verifier-rejection fixtures;
- malformed textual and public-API-built modules fail without panics and with deterministic diagnostics;
- the verifier covers all ten documented phases, including instruction-boundary failure edges, interprocedural domain and table effects, path-sensitive cleanup, and unsafe-boundary checks;
- a cross-process pipeline harness compares byte-for-byte output from isolated processes with different working and temporary directories;
- golden, acceptance, rejection, determinism, race, and vet checks pass without a future source frontend.

MIR 1 intentionally retains documented conservative restrictions where exact
provenance is not representable, including direct SSA identity for cleanup
handles, possible aliasing between external table or domain parameters, and no
lifetime-bearing stores through dereference places. A MIR interpreter for
differential backend testing remains an open question until the C backend
exists; it is not required for this milestone.

### Milestone 2: Minimal Runtime

Status: **complete**

Deliverables (implemented in `runtime/c/alder.h` and `runtime/c/alder.c`):

- portable C11 storage-domain primitives: init/alloc/mark/reset/destroy with parent-child tracking;
- epoch-scoped marks, resets to the empty frontier, segmented bump allocation (doubling regular segments up to 1 MiB, dedicated exact-size large segments), alignment and overflow/OOM handling;
- scoped cleanup: begin/push/disarm/run/end with reverse-order, at-most-once execution;
- checked arithmetic, explicit left/right shifts, division, and bounds helpers for the 64-bit MIR operations, plus defined float-to-integer conversions;
- a minimal generational table: non-wrapping serial identity, slot generations, domain-reset epochs, growth, and stale-id rejection;
- strict-warning compile-and-run tests for every area, with ASan/UBSan reruns when the host toolchain supports them.

Exit-criteria evidence:

- every runtime API carries an explicit failure and lifetime contract in `runtime/c/alder.h` and `docs/c-backend.md`;
- repeated domain create/reset/destroy cycles are leak-free: a live-allocation counter proves zero retained heap blocks on every tested host, and the same suites rerun under ASan/UBSan where the toolchain supports them (the current mingw-w64 host lacks libasan/libubsan, so those runs skip);
- empty-frontier reset, consumed-mark rejection, and stable integer mark identities are pinned by runtime and verifier tests;
- stale generational IDs never resolve to reused objects: slot reuse always assigns a fresh generation, ids carry a non-wrapping table serial, and reset/destroy/re-init changes the owning domain identity or epoch;
- cleanup runs exactly once across success and failure paths: reverse-order execution, disarmed skipping, and contract-violation handling are pinned by tests.

### Milestone 3: C11 Backend

Status: **complete**

Deliverables (implemented in the `cgen` package):

- deterministic MIR-to-C11 lowering with ID-based naming, erased unit values, and parallel block-parameter copies at every edge;
- explicit sequencing of all side effects as statements, with instruction-local temporaries;
- dependency-ordered aggregate, enum, option, result, and function-pointer types with collision-free ordinal fields and portable empty aggregates;
- checked operations with 64-bit runtime helpers, promotion plus range checks for narrow widths, portable arithmetic right shifts, and checked slice bounds, nullability, and `size_t` conversion;
- domains, scoped cleanup with generated adapters and per-site contexts, identity-preserving domain-backed tables, and generated per-type `copy_to_domain` helpers;
- C ABI declarations for backend-safe imported symbols and generated functions;
- compile-and-run behavior fixtures with drivers under the strict warning set;
- deterministic output pinned in-process and across isolated processes.

Exit-criteria evidence:

- every golden fixture compiles without warnings under the strict warning set (`-std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion`);
- generated programs pass runtime behavior tests (all integer widths with operation-specific 8/64-bit boundaries and intermediate-width overflow/shift cases, guarded float narrowing, loops and parallel edges, enum/option/result dispatch, domains with marks and resets, cleanup exactly-once on success and failure paths, table aliasing and growth, stale-id rejection, null-slice ranges, and string-byte preservation);
- signed overflow, shifts, indexing, aliasing, alignment, and evaluation order have defined lowering rules in `docs/c-backend.md`;
- generated C is inspectable and independent of host paths, verified by cross-process determinism tests;
- ASan/UBSan reruns probe the host toolchain and skip when unsupported (the current mingw-w64 host lacks libasan/libubsan);
- unverified modules, uninitialized local loads, unsafe external names, and non-copyable `copy_to_domain` targets are rejected with diagnostics.

A MIR interpreter for differential testing remains an open question; the compile-and-run fixtures provide the behavioral evidence, so the interpreter is not required for this milestone.

### Milestone 4: Bootstrap Language Subset

Status: **complete**

Deliverables (implemented in the `frontend` Go package):

- a deterministic lexer, parser, type checker, and MIR emitter for the
  single-file source subset defined in `docs/language-design.md` (Alder S0):
  functions, primitives, structs, enums with `match`, slices and `String`,
  `Option`/`Result` with `try`, a fixed-capacity `Map` helper, bootstrap
  domain intrinsics, callback-bearing `using` cleanup, and direct concrete C
  symbol declarations called through `unsafe c`;
- compile-time `type` parameters with parenthesized application syntax,
  inference from runtime arguments and expected results, all-or-none explicit
  type arguments, rejection of specialization-expanding polymorphic
  recursion, and complete monomorphization before any backend MIR exists;
- deterministic diagnostics with line and column, pinned by rejection
  fixtures;
- a reorder pass emitting callees before callers so the printed MIR round
  trips through the single-pass MIR 1 text parser (call cycles are left in
  instantiation order and documented as unrepresentable in the text format).

The `__s0_domain_create`, `__s0_alloc`, `__s0_domain_mark`,
`__s0_domain_reset`, `__s0_domain_destroy`, and `__s0_map_create` names, the
`Domain`/`DomainMark` types, and `using x = expr with CleanupFn` are temporary
MIR 1 bootstrap bridges. They do not implement or replace the intended
compiler-inferred storage, `Table(T)`/generational `T.Id`, and resource-owned
cleanup model. S0 has no fixed arrays, source modules, header importing,
storage inference, table surface, structured concurrency, traits, closures,
or methods, and is not a complete language frontend.

Exit-criteria evidence:

- ten end-to-end source programs (arith, structs, enums, option, strings,
  generic, domains, maps, cleanup, ffi) compile through the full pipeline to
  verified MIR and then to strict-warning C11, compile with the canonical
  strict warning set, and pass runtime behavior checks (including a map with
  struct keys, 14-entry probe stress, and observable FFI-backed cleanup
  ordering);
- accept fixtures pin the printed MIR; rejection fixtures pin diagnostics
  covering syntax, typing, mutability, generics, map restrictions,
  cycles, match exhaustiveness, `try` error matching, `using` discipline,
  and the MIR 1 restrictions (direct marks, direct cleanup handles,
  materializable fail values, callee-before-caller ordering);
- printed MIR re-parses and re-verifies for every end-to-end fixture;
- in-process and cross-process determinism checks cover the printed MIR and
  the generated C;
- ASan/UBSan reruns are not available on the current mingw-w64 host
  (missing libasan/libubsan), so sanitizer coverage is reported as skipped.

This evidence covers the documented representative S0-to-MIR-to-C11 path; it
does not claim that S0 exercises every backend mechanism.

## Milestone 5: Self-Hosted Compiler

Bootstrap stages:

1. `alder0`, written in Go, compiles the Alder compiler to C11.
2. A system C compiler builds that C as `alder1`.
3. `alder1` compiles the same Alder compiler sources as `alder2`.
4. Stable MIR or C output is compared between stages.
5. A generated, auditable `bootstrap/alder.c` is committed for source distribution.

After repeatable self-hosting, the Go bootstrap compiler is frozen except for correctness and bootstrap maintenance.

## Deferred Work

The following items are not part of the current implementation scope:

- LLVM, Cranelift, QBE, or direct machine-code backends;
- JIT and REPL execution engines;
- package registry and dependency solver;
- language server and debugger integration;
- macros and compile-time execution;
- advanced optimization pipelines;
- stable ABI promises beyond intentional C interfaces;
- production readiness or performance claims.

## LLVM Reconsideration Gate

LLVM may be reconsidered only after:

- MIR semantics are versioned and tested;
- the C backend passes representative correctness suites;
- self-hosting needs or measured workloads demonstrate a concrete limitation;
- a proposal defines dependency, versioning, distribution, debug-info, and differential-testing costs.

Until then, changes must not add LLVM libraries, bindings, conditional build flags, or LLVM-specific assumptions to MIR.

## Representative Validation Programs

The memory model should eventually be exercised by:

1. a parser with many phase-local allocations;
2. a request-style workload with one bounded top-level domain;
3. an entity graph using `Table(T)` and generational IDs;
4. a structured concurrent file scanner;
5. a small C library wrapper that tests pointer, length, error, and cleanup contracts.
