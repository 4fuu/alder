# Alder

Alder is an experimental native programming language designed to be safe,
fast, simple, modern, batteries-included, and directly interoperable with C.
Safe Alder uses value semantics, inferred storage, deterministic resources, and
structured concurrency without a tracing garbage collector or routine
Rust-style lifetime syntax.

The project is currently in the **design and bootstrap phase**. The Alder 1.0
target is documented, but there is no complete usable compiler, standard
library, async runtime, package toolchain, or stable release yet.

## Repository Status

The repository has executable Go implementations of versioned Alder MIR and
its verifier, a minimal C runtime, deterministic verified-MIR-to-C11 lowering,
and the deliberately small Alder S0 bootstrap frontend. S0 covers a tested
multi-source global compilation subset with generics, records, unary-payload
enums, `match`, slices/bridge `String`, `Option`/`Result`, temporary map/storage/
cleanup facilities, and direct C symbols inside `unsafe c`.

Milestone 5.4 is active: `compiler/src/*.al` is an in-progress Alder port of
the compiler. Its lossless lexer and S0 parser are substantially represented,
while semantic checking covers only preparatory declaration/signature and
narrow body slices. General checking, inference, monomorphization, MIR
construction, verifier/backend ports, self-hosted execution, fixed point, and
the 1.0 language remain incomplete. See [Alder S0](docs/s0-language.md) and
[Roadmap](ROADMAP.md) for the exact boundary and evidence.

## Bootstrap CLI

The current Go bootstrap exposes the verified explicit-source-set S0 pipeline
through one deliberately narrow executable:

```text
alder check [--format=human|json] <logical-path.al>...
alder compile [--format=human|json] [--emit=mir|c] [-o logical-output] <logical-path.al>...
```

Logical paths are canonical slash-relative workspace paths. Inputs are explicit
and sorted; the core does not scan directories or provide packages. JSON mode
writes exactly one versioned envelope to stdout and does not mix in human
diagnostics or raw artifacts. Exit statuses are 0 for success, 1 for source
diagnostics, 2 for usage/request errors, 3 for I/O failures, and 4 for
internal/backend failures. C program output uses the separately linked
`bootstrap/alder_host.c` shim and the headers in `bootstrap/` and `runtime/c/`.
This is bootstrap infrastructure for the documented S0 subset, not a production
compiler or claim that the full language is implemented.

## Current Priority

Implementation follows the shortest safe path:

- finish the Alder-written compiler core through the existing verified
  MIR-to-C11 path;
- establish repeatable fixed-point source bootstrap without Go;
- then implement the already documented Alder 1.0 gates in dependency order:
  modules/builds, complete language/memory model, C bindings and standard
  library, async runtime, tooling, Git packages, xmake integration, and release
  qualification.

Nonblocking diagnostic/test polish can be scheduled at its owning milestone,
but known miscompilation, unsafe behavior, nondeterminism, malformed accepted
state, or compiler-scale nontermination remains a bootstrap blocker.

The following are outside Alder 1.0 rather than merely postponed bootstrap
work:

- LLVM or another native-code backend;
- JIT compilation;
- a package registry and general semver solver;
- macros/general compile-time execution;
- dynamic trait objects and detached tasks;
- a stable native Alder ABI.

LLVM must not be added as an optional dependency or parallel backend during the current phase. A future backend proposal must begin from a stable MIR contract and separate project decision.

## Design Direction

Alder does not expose Rust-style per-object ownership, moves, borrow chains, or routine lifetime annotations. Instead, it combines:

- **value semantics** for ordinary data;
- **compile-time `type` values and `Name(...)` type constructors** for generics;
- **inferred hierarchical storage domains** for temporary and result data;
- **segmented regions** to reduce avoidable retention;
- **generational `T.Id` values and `Table(T)`** for long-lived objects with identity;
- **scoped cleanup** for files, sockets, locks, and transactions;
- **`async fn`, `await`, and structured task groups** to bound task lifetimes;
- **explicit `unsafe c` boundaries** for operations the language cannot prove safe.

When the compiler cannot prove that storage can be reclaimed early, the default failure mode is retention until the nearest enclosing domain ends. Complex code should degrade to measurable memory cost, not memory unsafety or pervasive type-system complexity.

The Alder 1.0 design is a frozen implementation target, but it can still change
through an explicit design decision before release. A documented feature is not
available until executable acceptance and rejection tests demonstrate it.

## Compiler Plan

The production architecture keeps one verified path; Go is only the Stage 0
implementation:

```text
Alder source or MIR fixture
        |
        v
Typed, monomorphized source model / HIR
        |
        v
Alder MIR
        |
        v
Verified Alder MIR
        |
        v
Conservative C11 + small C runtime
        |
        v
System C compiler
```

The repository is now moving toward an Alder-written compiler over this path.
Go is a temporary bootstrap implementation language, not the permanent
compiler architecture.

## Alder 1.0 Target

The 1.0 release is not only a self-hosted compiler. It requires static traits,
safe closures, inferred storage, `Table(T)` identity, `async fn`/`await`,
structured cancellation, C header bindings and exports, deterministic modules
and builds, exact-revision Git packages, managed xmake/xrepo native
dependencies, an offline batteries-included standard library (including
networking, HTTP/TLS, and JSON), formatter/test/doc tools, baseline LSP, and
multi-platform qualification. The complete gate is
[Alder 1.0](docs/alder-1.0.md).

## Repository Documents

- [Alder 1.0](docs/alder-1.0.md) defines the release/product gate.
- [Language Design](docs/language-design.md) indexes the user-facing model.
- [Surface Syntax](docs/syntax.md) and
  [Language Semantics](docs/language-semantics.md) define source behavior.
- [Memory and Resources](docs/memory-and-resources.md),
  [Traits and Closures](docs/traits-and-closures.md), and
  [Async](docs/async.md) define safety, abstraction, and concurrency.
- [C Interoperability](docs/c-interop.md),
  [Modules and Builds](docs/modules-and-builds.md), and
  [Standard Library](docs/standard-library.md) define the 1.0 integration and
  distribution contracts.
- [Alder S0](docs/s0-language.md) defines only the implemented bootstrap subset.
- [Alder MIR](docs/mir.md) defines the initial intermediate representation and its invariants.
- [C11 Backend](docs/c-backend.md) defines lowering rules and C undefined-behavior constraints.
- [Roadmap](ROADMAP.md) records active milestones, deferred work, and self-hosting criteria.
- [Contributing](CONTRIBUTING.md) defines project and engineering standards.

Documents and code comments in this repository are written in English. Frozen
1.0 examples are design contracts, not claims that S0 currently parses them.

## One-Sentence Summary

> Reclaim local data in batches, keep long-lived identity in containers, make safety a semantic guarantee, and leave memory tuning to the compiler and profiler rather than the everyday type system.
