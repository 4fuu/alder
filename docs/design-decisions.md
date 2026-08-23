# Alder Design Decision Register

This register summarizes accepted project-level choices. Detailed semantics
belong to the linked owning documents. A changed decision updates this file,
the owner, examples, roadmap, and tests in one review.

## Status meaning

- **Frozen 1.0**: implementation target unless explicitly amended.
- **Bootstrap**: temporary mechanism with a removal gate.
- **Deferred**: intentionally outside 1.0.

## Accepted decisions

### D001 — Alder name and `.al` sources

Status: **Frozen 1.0**

The language and project are Alder; sources use `.al`. “Aster” in early design
discussion is the former working name, not another language or compatibility
brand.

### D002 — One production backend

Status: **Frozen 1.0**

Verified Alder MIR lowers to conservative portable C11. LLVM, a JIT, and a
parallel native backend are outside 1.0. MIR defines semantics; C does not.

### D003 — Ordinary value semantics, narrow affine boundary

Status: **Frozen 1.0**

Ordinary data has independent value semantics without user-visible moves.
Exactly-once resources, identity containers, and structured-concurrency owners
are affine. Scoped views/capabilities cannot escape invalidation. There is no
general source lifetime language.

### D004 — Inferred storage with safe retention fallback

Status: **Frozen 1.0**

The compiler places ordinary allocations in hierarchical domains. Failure to
prove early reclamation retains storage in a safe outer domain and exposes the
cost to tooling. It never accepts dangling data or silently enables universal
ARC/GC.

### D005 — Container-owned long-lived identity

Status: **Frozen 1.0**

Long-lived identity uses affine `Table(T)` and copyable generational `T.Id`.
Graphs use IDs rather than persistent interior pointers. Views are scoped.

### D005A — M7.1 hidden borrowed placement domain

Status: **Bootstrap until Milestone 7.3**

Before placement inference, lowering prepends and threads one hidden borrowed
root/result domain through every ordinary source function, method, source call,
recursive call, and cleanup callback. Hosted entry owns that root; unhosted C
signatures retain the explicit hidden parameter. `Vec` does not contain a
domain and every semantic vector copy remains a verifier-visible eager deep
copy. Generated ordinary functions never reset or destroy the borrowed root.
Returned vectors are safe; returned views remain rejected until Milestone 7.3.

### D006 — One generic syntax

Status: **Frozen 1.0**

Compile-time type parameters are leading parameters of type `type`; application
is `Name(...)`; inference is all-or-none for the leading type sequence; source
generics are monomorphized before backend MIR. `<>` and `[]` are not competing
generic application syntaxes.

### D007 — Exact-width numeric semantics

Status: **Frozen 1.0**

Alder has explicit-width integers and IEEE binary floats, no platform `Int`, no
implicit numeric conversion, and checked default arithmetic. Explicit named
APIs provide fallible, wrapping, and saturating behavior.

### D008 — Algebraic errors, no hidden exceptions

Status: **Frozen 1.0**

Recoverable failures use `Result`; optional values use `Option`/`T?`; prefix
`try` propagates errors. Invariant panic terminates the process and does not
promise stack unwinding or recovery.

### D009 — One cleanup construct

Status: **Frozen 1.0**

`using` selects an infallible `Cleanup` hook, or `AsyncCleanup` in an async
scope, for an affine owner. Normal flow, return, `try`, loop exit, and
structured cancellation clean in reverse order. There is no second general
`defer` construct.

### D010 — Static coherent traits

Status: **Frozen 1.0**

Traits provide monomorphized constraints with package-level orphan/coherence
rules, generic trait parameters, and default methods. Dynamic trait objects,
specialization, and operator overloading are outside 1.0.

### D011 — Explicit safe closure capture

Status: **Frozen 1.0**

Closures copy ordinary read captures. Mutable locals and affine owners are not
implicitly captured. Shared mutable task state uses explicit scoped owners.

### D012 — Structured async before 1.0

Status: **Frozen 1.0**

`async fn`, `await`, `TaskGroup`, scoped task handles, cancellation cleanup,
async I/O, and multithread/local executors are required for 1.0. Detached
fire-and-forget tasks are absent.

### D013 — Explicit C trusted boundary

Status: **Frozen 1.0**

C headers remain ABI authority; Alder binding blocks are checked against them;
raw operations require local `unsafe c`; ordinary wrappers encode nullability,
bounds, ownership, retention, callbacks, blocking, and threading. Alder does
not claim to sanitize arbitrary linked C.

### D014 — One file, one module; private by default

Status: **Frozen 1.0**

File path and required `module` header agree. Imports are explicit and acyclic;
`pub` exports; wildcard imports are absent. The compiler core receives an
explicit canonical snapshot and never walks the filesystem.

### D015 — Exact Git packages before a registry

Status: **Frozen 1.0**

Local workspaces and exact-revision Git dependencies use an authoritative
content-verified `alder.lock`, immutable cache, and locked/offline/frozen modes.
Registry/publishing/general semver solving are deferred.

### D016 — xmake is a native provider, not Alder's semantic build system

Status: **Frozen 1.0**

Alder owns package identity and the deterministic build plan. Managed pinned
xmake/xrepo is the default replaceable C/C++ dependency provider. The bootstrap
and standard library do not require it.

### D017 — Batteries included in the toolchain sysroot

Status: **Frozen 1.0**

`core` plus hosted `std`, including collections, Unicode, files, processes,
time, random, async, networking, HTTP/TLS, JSON, tests, and C support, ship
offline with Alder 1.0.

### D018 — Small familiar sugar only

Status: **Frozen 1.0**

Retained sugar includes `T?`, prefix `try`, `if let`/`while let`, method-dot
calls, interpolation, `for`, and `using`. Alder rejects competing generic
syntax, postfix error `?`, truthiness, implicit conversion, arbitrary operator
grammar, implicit tail returns, and detached-task syntax.

### D019 — Cancellation never erases an await result

Status: **Frozen 1.0**

Runtime cancellation occurs only while the parent is already exiting or inside
a combinator that owns and joins private children. There is no arbitrary
`Task.cancel`; cooperative application cancellation is a scoped token reported
through an API's ordinary typed result.

### D020 — Package identity is content-and-dependency based

Status: **Frozen 1.0**

Semantic package identity contains package name, canonical source-tree hash,
and the sorted identities of resolved dependencies. Host paths, checkout
locations, credentials, and transport aliases are provenance rather than
semantic identity. Workspace inputs stay below an explicit snapshot root and
Git inputs use exact commits plus independently verified canonical trees.

## Bootstrap decisions

- Go is the temporary Stage 0 implementation language.
- `Domain`, `DomainMark`, `__s0_*`, fixed-capacity S0 Map, S0 Buffer,
  private `__s0_String = [U8]`, callback-bearing `using`, global source sets,
  and direct C symbol declarations are removal-gated bridges.
- Self-hosting and fixed-point source bootstrap precede broad implementation
  of the 1.0 product profile, but they do not narrow that profile.

## Deferred decisions

The project deliberately defers LLVM/other backends, JIT/REPL, package
registry and semver solving, macro/compile-time execution, dynamic trait
objects, detached tasks, stable native Alder ABI, and broad debugger/IDE
refactoring. See [Open Questions](open-questions.md) for nonblocking follow-up
choices.
