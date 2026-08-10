# Roadmap

This roadmap separates committed near-term work from longer-term direction. Dates are intentionally omitted until implementation velocity and semantic risk are better understood.

## Project Principles

1. Validate semantics before optimizing them.
2. Keep one production path during bootstrap: Aster MIR to C11.
3. Make unsafe behavior explicit and locally auditable.
4. Prefer deterministic, inspectable compiler output.
5. Do not expand the user-facing memory model to fix isolated performance cases.
6. Start self-hosting as soon as a small Aster subset can express the compiler; do not first build a complete compiler in Go.

## Active Scope

### Milestone 0: Design Baseline

Status: **in progress**

Deliverables:

- document language goals, non-goals, and unresolved semantics;
- document compile-time `type` values, type application, inference, and the monomorphization boundary;
- define the first versioned Aster MIR vocabulary;
- define the C11 lowering contract and undefined-behavior policy;
- establish repository, contribution, and orb lifecycle standards;
- choose representative validation programs.

Exit criteria:

- every initial MIR operation has a documented type and effect;
- storage-domain and cleanup invariants can be checked without consulting source syntax;
- the C backend document explains how safe MIR avoids C undefined behavior;
- open questions are explicit rather than hidden behind examples.

### Milestone 1: MIR Toolkit

Status: **planned**

Deliverables:

- a small Go module with no unnecessary third-party dependencies;
- in-memory MIR types using stable integer IDs rather than pointer-linked compiler graphs;
- deterministic textual MIR parser and printer;
- MIR verifier with source-independent diagnostics;
- golden tests and invalid-MIR tests.

Initial verifier responsibilities:

- type consistency;
- valid control-flow targets and block arguments;
- dominance and value availability;
- storage-domain nesting and reference escape rules;
- balanced cleanup and domain termination;
- separation of safe references from raw C pointers;
- valid generational table operations.

Exit criteria:

- parse-print-parse is stable;
- malformed fixtures fail with deterministic diagnostics;
- map iteration, process addresses, and temporary paths cannot affect output;
- the MIR package can be used without the future source frontend.

### Milestone 2: Minimal Runtime

Status: **planned**

Deliverables:

- portable C11 storage-domain primitives;
- marks, resets, segmented allocation, and large-allocation handling;
- scoped cleanup registration and reverse-order execution;
- checked arithmetic and bounds helpers;
- a minimal generational table implementation;
- ASan and UBSan validation where supported.

Exit criteria:

- all runtime APIs have explicit failure and lifetime contracts;
- repeated domain create/reset/destroy tests are leak-free under supported sanitizers;
- stale generational IDs never resolve to reused objects;
- cleanup runs exactly once across success and failure paths.

### Milestone 3: C11 Backend

Status: **planned**

Deliverables:

- deterministic MIR-to-C lowering;
- explicit sequencing of all side effects;
- structured cleanup lowered to visible C control flow;
- portable representations for MIR values and aggregates;
- C ABI declarations and small safe-wrapper fixtures;
- compilation tests with Clang and GCC where available;
- differential execution tests between MIR interpretation and generated C, if a MIR interpreter is justified.

Exit criteria:

- safe MIR fixtures compile without warnings under the project's strict warning set;
- generated programs pass runtime and sanitizer tests;
- signed overflow, shifts, indexing, aliasing, alignment, and evaluation order have defined lowering rules;
- generated C remains inspectable and independent of host-specific absolute paths.

## Next Direction: Minimal Frontend and Self-Hosting

This work begins only after the active MIR and C backend milestones are coherent.

### Milestone 4: Bootstrap Language Subset

Candidate subset:

- modules and functions;
- primitive values, structs, enums, and pattern matching;
- arrays, slices, strings, maps, `Option`, and `Result`;
- compile-time `type` parameters and parenthesized type constructors;
- generic inference and monomorphization before backend MIR;
- storage domains and scoped cleanup;
- C FFI;
- enough diagnostics to build the compiler itself.

Async, advanced traits, macros, and broad standard-library work are not prerequisites for the first self-host.

### Milestone 5: Self-Hosted Compiler

Bootstrap stages:

1. `aster0`, written in Go, compiles the Aster compiler to C11.
2. A system C compiler builds that C as `aster1`.
3. `aster1` compiles the same Aster compiler sources as `aster2`.
4. Stable MIR or C output is compared between stages.
5. A generated, auditable `bootstrap/aster.c` is committed for source distribution.

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
