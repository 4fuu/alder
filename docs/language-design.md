# Alder Language Design

Design status: **Frozen Alder 1.0 direction**

Availability: **Mixed; consult the support matrix**

Current implementation contract: [Alder S0](s0-language.md)

This document is the entry point for Alder's user-facing design. It separates
the intended language from the temporary bootstrap language and from the
current MIR/C implementation profile. A rule described as frozen is a target
for implementation; it is not a claim that the current compiler accepts it.

The repository and language are named **Alder**. Earlier design discussions
used the working name **Aster**; those references are historical and do not
name a second language.

## One-sentence design

> Alder is a small, batteries-included native language with ordinary value
> semantics, inferred storage, explicit errors, deterministic resources,
> structured concurrency and identity, and locally auditable C interoperability.

## Goals

Alder aims to provide:

- memory safety without a mandatory tracing garbage collector;
- predictable native performance and inspectable C11 output;
- familiar syntax with few concepts and little decorative sugar;
- ordinary values that do not expose routine moves, borrow chains, or lifetime
  parameters;
- deterministic cleanup for resources;
- algebraic data types, exhaustive matching, and monomorphized generics;
- statically coherent traits, safe closures, and structured concurrency
  without colored functions;
- a CLI-first toolchain whose compact output serves people and coding agents;
- direct C ABI access behind an explicit `unsafe c` boundary;
- deterministic modules, packages, builds, and diagnostics suitable for
  self-hosting and production tools;
- a version-matched standard library and toolchain usable offline after
  installation.

When the compiler cannot reclaim storage as early as it hoped, the safe
fallback is retention in a statically enclosing owner. Retention can be
expensive and, for a long-lived owner, unbounded; it is a measurable cost, not
a license to create dangling references or silently introduce GC/ARC.

## Deliberate exclusions from Alder 1.0

Alder 1.0 does not include:

- Rust-style routine ownership annotations, general user-written lifetimes, or
  per-expression move syntax;
- a platform-sized `Int` or implicit numeric conversions;
- catchable exceptions or panic recovery;
- class inheritance, implicit dynamic dispatch, or runtime generic arguments;
- arbitrary operator definitions, macros, or general compile-time execution;
- detached fire-and-forget tasks, and `async fn` function coloring;
- safe unchecked access to arbitrary C declarations;
- a package registry, publishing service, general semantic-version solver, or
  stable native Alder ABI;
- LLVM, a JIT, or a second production backend.

## Three contracts, not one

| Contract | Meaning | Owning document |
|---|---|---|
| Frozen Alder 1.0 | Intended user-facing product, semantics, syntax, library, and tools | [Alder 1.0](alder-1.0.md) and the language documents below |
| Alder S0 | Exact source subset accepted by the Go bootstrap | [Alder S0](s0-language.md) |
| MIR/C profile | Executable backend contract and current restrictions | [MIR](mir.md) and [C11 backend](c-backend.md) |

An implementation restriction does not become a language rule merely because
S0 or MIR currently needs it. Conversely, a frozen language rule is not usable
until executable code and tests demonstrate it.

## Core model

### Ordinary data is value data

Primitives, records, enums, strings, byte values, and value collections have
independent value semantics. Assignment, argument passing, and return do not
invalidate the source. The implementation may elide copies or share immutable
representation only when later mutation remains observationally independent.

Exactly-once resources and identity containers are deliberately different:

- resources, `Table(T)`, and foreign owned handles are **affine owners** and
  cannot be copied;
- `T.Id` is a small copyable identity token;
- slices and table accesses are scoped capabilities that cannot outlive the
  storage or access scope that produced them.

This narrow distinction keeps ownership out of ordinary programming while
still making resource cleanup and mutation safe.

### Storage is inferred

Safe code does not select allocators or pass ordinary domain handles. The
compiler and runtime may use hierarchical, segmented storage domains, direct
result construction, immutable sharing, or copies. The observable guarantees
are lifetime safety and value behavior, not a particular arena placement.

Long-lived objects with stable identity live in `Table(T)` and refer to one
another through generational `T.Id` values rather than persistent interior
pointers.

### Failure has two meanings

- Expected, recoverable failure is `Result(T, E)` and propagates with `try`.
- Absence is `Option(T)`, optionally written `T?`.
- Failed invariants, unchecked allocation failure, and runtime contract
  violations terminate the process. They are not hidden exceptions and are
  not catchable in Alder 1.0.

`using` guarantees reverse-order cleanup on normal scope exit, `return`, and
`try` propagation, plus structured task cancellation. Cleanup may suspend for
task-group teardown. No source-language stack-unwinding guarantee applies
after unrecoverable termination.

### C is explicit and local

C declarations are described by an explicit, target-aware binding contract.
Calling C and manipulating raw pointers requires a local `unsafe c` block;
the only safe raw-pointer observation is the standard null test. Safe wrappers
validate nullability, bounds, alignment, mutability, ownership, and lifetime
before exposing safe Alder values.

The system C compiler remains authoritative for header declarations and target
ABI details. Alder does not promise to safely infer arbitrary C ownership or
callback behavior from a header.

## Minimal sugar policy

The 1.0 language retains only sugar that removes frequent noise without adding
a second semantic model:

- `T?` for `Option(T)`;
- `try` for exact-error-type `Result` propagation;
- `if let` for a one-pattern match, and `if` guards on `match` arms;
- statically resolved method calls with `value.method(...)`;
- `while let` and `for value in values` over static iterator traits;
- string interpolation through `Display` (specified, not implemented in the
  current compiler);
- `using` for lexical resource cleanup;
- omission of `-> Unit`.

The 1.0 language does not add postfix error `?`, two generic syntaxes, implicit
truthiness, implicit numeric conversions, assignment expressions, C-style
`for`, `goto`, arbitrary operator overloading, or a second cleanup feature such
as `defer`.

## Document map

- [Alder 1.0](alder-1.0.md) is the release/product acceptance contract.
- [Surface Syntax](syntax.md) freezes the intended grammar and sugar.
- [Language Semantics](language-semantics.md) defines values, types, errors,
  evaluation order, methods, and the core semantic boundary.
- [Memory and Resources](memory-and-resources.md) defines inferred storage,
  affine owners, `Table(T)`, views, and cleanup.
- [Traits and Closures](traits-and-closures.md) defines static abstraction and
  safe capture.
- [Async and Structured Concurrency](async.md) defines I/O capabilities,
  per-instance suspension, task isolation, cancellation, and executors.
- [C Interoperability](c-interop.md) defines raw pointers, binding contracts,
  safe wrappers, and unsupported C features.
- [Modules and Builds](modules-and-builds.md) defines source modules,
  visibility, deterministic build plans, Git packages, and xmake integration.
- [Standard Library](standard-library.md) freezes the required 1.0 sysroot and
  batteries-included module families.
- [Examples](examples.md) gives complete examples using only frozen syntax and
  marks features not yet implemented.
- [Alder S0](s0-language.md) records the exact implemented bootstrap subset and
  its temporary bridges.
- [Design Decisions](design-decisions.md) is the stable decision register.
- [Open Questions](open-questions.md) contains only decisions that require
  implementation evidence or a later milestone.
- [Alder MIR](mir.md) and the [C11 Backend](c-backend.md) remain the executable
  intermediate and backend contracts.

## Support matrix

| Area | Frozen direction | Current evidence |
|---|---|---|
| Records, enums, functions, control flow | Yes | Implemented in S0 |
| `type` parameters and `Name(...)` generics | Yes | Implemented in S0; monomorphized before MIR |
| `Option`, `Result`, `try`, exhaustive `match` | Yes | Implemented in S0 |
| Exact-width numerics and checked operations | Yes | S0/MIR/C implemented, with current full-`U64` frontend limits documented in S0 |
| `String`, `Bytes`, arrays, slices, `Vec`, ordered `Map`/`Set` | Required for 1.0 | M7 implements fixed arrays and distinct owned `String`/`Bytes`; M7.1 implements `Vec`, immutable views, and exclusive mutable views; M7.5 implements the ordered `Map`/`Set` with insertion-ordered linear lookup |
| Inferred invisible storage | Required for 1.0 | Explicit bootstrap domains and MIR operations exist; inference is not implemented |
| `Table(T)` and `T.Id` | Required for 1.0 | M7.5 implements the source surface: `Table.new(T)`, `insert`, `remove`, `get`/`get_mut` scrutinee matches with staleness and overlap rejection, and callback-free `using` cleanup for table owners (concrete copyable elements; affine element composition is gated) |
| Resource-selected `using` | Required for 1.0 | S0 callback form is bootstrap-only |
| Inherent methods | Required for 1.0 | M7 implements inherent methods, associated functions, and receiver modes |
| Static traits and safe closures | Required for 1.0 | Not implemented in S0 |
| I/O capabilities, per-instance suspension, task groups, channels, cancellation | Required for 1.0 | Not implemented; current runtime is single-threaded |
| `match` guards | Required for 1.0 | Not implemented in S0 |
| CLI queries, `explain`, and required doc comments | Required for 1.0 | Not implemented; `alder check`/`compile` and three coarse diagnostic codes exist |
| C binding blocks, exports, callbacks, and safe wrappers | Required for 1.0 | S0 direct-symbol import is bootstrap-only |
| Source modules, `pub`, manifests, and deterministic build plans | Required for 1.0 | Not implemented; S0 uses one explicit global source set |
| Exact-revision Git packages and lockfile | Required for 1.0 | Not implemented |
| Managed xmake/xrepo external native executor/provider | Required default integration for 1.0; CLI and documented glue, no embedded engine | Not implemented or qualified; version selection pending; bootstrap/runtime/std retain xmake-free paths |
| Batteries-included `core`/`std` | Required for 1.0 | Only private runtime/bootstrap facilities exist |
| Formatter, test/doc tools, baseline LSP | Required distribution tools for 1.0 | Not implemented except narrow bootstrap CLI/service pieces |

## Naming and terminology

- Source files use `.al`.
- The language, compiler, runtime, and ABI prefixes use **Alder**.
- `S0` or “Stage 0” means the temporary Go bootstrap frontend.
- “Self-hosted compiler” means an Alder-written compiler built and executed
  through the verified MIR-to-C11 path; it does not imply that every frozen
  language feature is implemented.
- “Alder 1.0” means the full release gate in [Alder 1.0](alder-1.0.md), not only
  a self-hosted compiler.
- “Safe Alder” excludes behavior inside `unsafe c` and any explicit future
  unsafe facility.

## Change policy

A frozen rule may still change before a stable release, but it requires an
explicit update to [Design Decisions](design-decisions.md), every owning
contract, and the roadmap. Bootstrap convenience alone is not sufficient
rationale. A feature becomes “implemented” only when executable code and
focused acceptance and rejection tests demonstrate the stated contract.
