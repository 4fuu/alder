# Aster

Aster is an experimental systems programming language designed around predictable native performance, memory safety without tracing garbage collection, direct C interoperability, and a small user-facing memory model.

The project is currently in the **design and bootstrap phase**. There is no usable compiler or stable language specification yet.

## Repository Status

Milestone 1 (MIR toolkit) is complete. The `mir` and `mir/verify` Go packages provide a versioned textual format (`mir 1`), a deterministic parser and printer, and a ten-phase verifier with pinned acceptance and rejection fixtures. Parse/print fixed-point, malformed public-API input, cross-process determinism, and race-tested verifier behavior are covered by executable tests. Milestone 2 (minimal runtime) is complete: the portable C11 runtime in `runtime/c` provides storage domains with marks and resets, scoped cleanup, checked arithmetic and bounds helpers, and a generational table, all covered by strict-warning compile-and-run tests. `docs/mir.md` and `docs/c-backend.md` are the contracts; `ROADMAP.md` records status, evidence, and the deliberately conservative MIR 1 restrictions.

## Current Scope

The active implementation scope is deliberately narrow:

- define a typed Aster MIR;
- implement MIR construction, verification, and deterministic printing;
- lower verified MIR to conservative C11;
- provide the minimal C runtime required by storage domains, checked operations, cleanup, and generational tables;
- validate the model with focused executable fixtures.

The following work is explicitly deferred:

- LLVM or another native-code backend;
- JIT compilation;
- a production package manager;
- an LSP or IDE integration;
- a complete standard library;
- optimization work not required to validate semantics.

LLVM must not be added as an optional dependency or parallel backend during the current phase. A future backend proposal must begin from a stable MIR contract and separate project decision.

## Design Direction

Aster does not expose Rust-style per-object ownership, moves, borrow chains, or routine lifetime annotations. Instead, it combines:

- **value semantics** for ordinary data;
- **compile-time `type` values and `Name(...)` type constructors** for generics;
- **inferred hierarchical storage domains** for temporary and result data;
- **segmented regions** to reduce avoidable retention;
- **generational `T.Id` values and `Table(T)`** for long-lived objects with identity;
- **scoped cleanup** for files, sockets, locks, and transactions;
- **structured concurrency** to bound task lifetimes;
- **explicit `unsafe c` boundaries** for operations the language cannot prove safe.

When the compiler cannot prove that storage can be reclaimed early, the default failure mode is retention until the nearest enclosing domain ends. Complex code should degrade to measurable memory cost, not memory unsafety or pervasive type-system complexity.

The design is exploratory. Claims about safety and performance remain hypotheses until the MIR, runtime, and representative programs validate them.

## Compiler Plan

The initial bootstrap tools will be written in Go and emit C11:

```text
Aster source or MIR fixture
        |
        v
Typed HIR (when the first frontend exists)
        |
        v
Aster MIR
        |
        v
Verified Aster MIR
        |
        v
Conservative C11 + small C runtime
        |
        v
System C compiler
```

The repository will move toward self-hosting after the MIR and C backend are coherent enough to support a small bootstrap subset. Go is a temporary bootstrap implementation language, not the permanent compiler architecture.

## Repository Documents

- [Language Design](docs/language-design.md) describes the current language model.
- [Aster MIR](docs/mir.md) defines the initial intermediate representation and its invariants.
- [C11 Backend](docs/c-backend.md) defines lowering rules and C undefined-behavior constraints.
- [Roadmap](ROADMAP.md) records active milestones, deferred work, and self-hosting criteria.
- [Contributing](CONTRIBUTING.md) defines project and engineering standards.

Documents and code comments in this repository are written in English. Surface syntax shown in design documents is illustrative until the grammar is versioned.

## One-Sentence Summary

> Reclaim local data in batches, keep long-lived identity in containers, make safety a semantic guarantee, and leave memory tuning to the compiler and profiler rather than the everyday type system.
