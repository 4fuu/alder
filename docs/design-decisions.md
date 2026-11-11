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

### D005A — Inferred result and function placement domains

Status: **M7.3 slice 2; complete surface migration remains in slice 3**

Lowering prepends and threads a hidden caller-result domain through ordinary
source functions, methods, calls, recursion, and cleanup callbacks. Each
ordinary function creates a nested function domain and destroys it on every
exit. The checked-source storage facts and `StoragePlan` select between these
domains for Vec allocation, growth, and copies; returned values are copied to
caller-result storage where required. Direct immutable slices are returned by
materializing independent caller-result storage. `Vec` still carries no domain
and semantic copies remain verifier-visible eager deep copies. Slice 3 retains
the private bootstrap-storage and full value/view-surface migration.

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
`try` propagates errors. Invariant panic terminates the process immediately
with status 101 and does not unwind or promise recovery.

### D009 — One cleanup construct

Status: **Frozen 1.0**

`using` selects the infallible `Cleanup` hook of an affine owner. Normal flow,
return, `try`, loop exit, and structured cancellation clean in reverse order.
A hook whose receiver holds a suspending I/O capability may suspend; there is
no separate `AsyncCleanup` trait. There is no second general `defer`
construct; the C2y defer TS (ISO/IEC TS 25755) is weaker than `using` and does
not affect generated C11.

### D010 — Static coherent traits

Status: **Frozen 1.0**

Traits provide monomorphized constraints with package-level orphan/coherence
rules, generic trait parameters, and default methods. Dynamic trait objects,
specialization, and operator overloading are outside 1.0.

### D011 — Explicit safe closure capture

Status: **Frozen 1.0**

Closures copy ordinary read captures. Mutable locals and affine owners are not
implicitly captured. Shared mutable task state uses explicit scoped owners.

### D012 — Structured concurrency with per-instance suspension

Status: **Frozen 1.0** (amended 2026-11: replaces `async fn` coloring)

Code that waits on the host receives an explicit I/O capability through a
compile-time type parameter bounded by `Io`, `BlockingIo`, or `AsyncIo`.
Checking uses the bounds, so suspension rules are local and decided before
monomorphization. Lowering uses the concrete instance: `BlockingIo` instances
are direct code and other instances are verified state machines. There is no
`async fn`; `await` only consumes a `Task(T)`. Function values never suspend.
`TaskGroup`, scoped task handles, cancellation cleanup, async I/O, and
multithread/local executors are required for 1.0, and one standard library
serves blocking and evented programs. Detached fire-and-forget tasks are
absent.

Rationale: Zig's `std.Io` (0.16, 2026) showed the capability-parameter surface
works, but it resolves the color at runtime and has no stackless backend.
Effekt's type-directed selective CPS showed per-function selection of direct
and suspending code. Alder monomorphizes before MIR, has no trait objects, and
needs no separate compilation, so it can make the selection statically. The
remaining costs are threading `io` through signatures and duplicated instances;
code size is measured as a release budget.

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

Retained sugar includes `T?`, prefix `try`, `if let`/`while let`, `match`-arm
`if` guards, method-dot calls, interpolation, `for`, and `using`. Alder rejects
competing generic syntax, postfix error `?`, truthiness, implicit conversion,
arbitrary operator grammar, implicit tail returns, generators, callback sugar
such as Gleam's `use`, and detached-task syntax.

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

### D021 — Native UI is an official package after 1.0

Status: **Deferred**

A native desktop UI toolkit is planned as an official Git package, not a `std`
module, and its development starts only after Alder 1.0. The reference design
is the native UI of [MyGo](https://github.com/egoist/mygo) (MIT): a view is a
function of application state rebuilt each frame, element identity keys
per-element state across frames, flexbox and grid layout produce a
platform-independent display list, and a deterministic CPU rasterizer plus a
windowless tester render and drive views without a display. GPU renderers,
platform text engines, input methods, and accessibility bridges sit behind
that boundary. Linux comes first. Keeping it outside `std` keeps 1.0
qualification and compatibility promises independent of three desktop
platforms' UI stacks. See the [Roadmap](../ROADMAP.md#post-10-native-ui-package).

### D022 — The toolchain is CLI-first and agent-friendly

Status: **Frozen 1.0**

Every toolchain capability, including semantic navigation and API lookup, is
available as a noninteractive `alder` command; the LSP wraps the same queries.
Default output is compact text that a model can act on in one round trip: a
diagnostic states its direct cause, related locations, and a concrete fix when
one is known. `alder explain` adds background only. Output beyond a size limit
shows its head and tail and writes the complete text to a reported file.
Every public declaration needs a doc comment whose first line is a one-sentence
summary, so API queries can list one line per item. See
[Modules and Builds](modules-and-builds.md#cli-output-contract).

### D023 — Uniquely owned values update in place

Status: **Frozen 1.0**

A mutating collection or builder operation on a value the compiler proves
uniquely owned (no other live binding, capture, or view of its storage) updates
in place; otherwise it copies first. Uniqueness is proven statically from
bindings, views, and storage placement, with no reference count. Value
semantics are unchanged. Each copy site and its reason are reported by tooling,
because a silently lost in-place update is a large, invisible regression (Roc
hit a roughly thousandfold slowdown this way in 2026). Precedents: Koka
Perceus/FBIP and Lean 4 reset/reuse.

### D024 — Trait constraints are written on the type parameter

Status: **Frozen 1.0**

A trait constraint is part of the compile-time type parameter it constrains:
`T: type` declares an unconstrained type parameter, and `T: type(Order)` or
`K: type(Eq, Hash)` declares one that every instantiation must satisfy. There is
no `where` clause and no `+` constraint operator.

One spelling rule covers the whole type surface: lowercase keywords form a kind
of type and take their parts in parentheses (`fn(I64) -> String` is a function
type, `type(Eq, Hash)` is a constrained metatype), and capitalized names are
nominal types and traits applied with `Name(...)` (`Vec(T)`,
`Iterator(Item)`). `type` stays lowercase because a type parameter exists only
at compile time; a capitalized `Type` would read as a runtime library value.

A constraint may name any type parameter of the same parameter list, in either
order, so `IteratorType: type(Iterator(Item))` may precede `Item: type`.
Constraint arguments resolve in the declaration's scope. Method type
parameters use the same form.

A generic implementation declares its parameters right after `impl`, in the
same form: `impl(I: type(Io)) Reader for File(I)` and
`impl(Source: type(Reader)) BufReader(Source) { ... }`. An implementation for
a non-generic type has no list. Every listed parameter must appear in the
implementing type, and the implementing type must be a nominal type applied
to parameters or concrete types; an implementation for a bare parameter
(`impl(T: type(X)) Y for T`) is not part of Alder 1.0. An implementation
restates the constraints its type declares and may add more; a missing one is
rejected rather than implied. Coherence is unchanged: two implementations whose
implementing types can unify for the same trait application are rejected.

Rationale: a constraint can only name one parameter (`Param: Trait`), so a
separate clause adds a second place to read a signature without adding
expressive power, and it is the one spelling in the language that is neither a
keyword form nor a parenthesized application.

### D025 — `Error.cause` returns a report, payloads stay typed

Status: **Frozen 1.0**

`Error` is a builtin prelude trait like `Cleanup`:

```alder
trait Error {
    fn cause(self) -> Option(ErrorReport) {
        return None
    }
}
```

`ErrorReport` is a prelude value holding the displayed text of one error and
of every cause below it, built by `ErrorReport.of(E: type(Error, Display),
error: E)`, which recurses through `cause`. A module error keeps each wrapped
lower-level error as a typed variant payload that callers reach by `match`;
`cause` returns the report of whichever payload the current variant wraps, so
an error that can wrap several different lower-level error types still reports
its whole chain. `program error:` output prints the report one cause per line.

Rationale: Alder 1.0 has no trait objects and no trait inheritance, so a typed
`cause` result can name only one cause type and breaks for errors that wrap
several; a report needs neither feature, and typed access stays with the
variant payload where the error-taxonomy rules already put it.

### D026 — Float arithmetic is IEEE 754 with a defined zero divisor

Status: **Milestone 8**

The binary operators `+`, `-`, `*`, and `/` on `F32` and `F64` are IEEE 754
binary operations in the default non-stop mode: they never take a failure
edge, overflow produces the signed infinity, underflow is gradual, and
division by zero is defined rather than an error — the quotient is the
signed infinity whose sign is the XOR of the operand signs, and NaN when both
operands are zero or either operand is NaN. Comparisons follow IEEE 754: NaN
compares unordered with every operand (`==` is false, `!=` is true), and the
two zeros compare equal.

Generated C never emits a bare float division: `float.div` lowers through the
runtime helpers `alder_f64_div`/`alder_f32_div`, which branch on the divisor
and build the IEEE result directly. ISO C11 leaves `x/0` undefined, and Annex
F defines it only where `__STDC_IEC_559__` is defined; that macro is not
reliably defined on every tier-1 toolchain (for example Apple clang), so the
backend does not gate on it. Floating-point contraction is disabled both in
the compiler's strict build flags (`-ffp-contract=off`) and in every
generated program (`#pragma STDC FP_CONTRACT OFF`, preceded by a GCC-only
diagnostic-ignore because GCC does not implement the pragma and warns under
`-Wunknown-pragmas`), so `a * b + c` always computes and rounds as written.
Alder still does not promise NaN payloads, FTZ/denormal control, or honoring
ambient foreign changes to the rounding mode.

Rationale: the C interop exact-value conversion tests and the standard
library's `math` helpers need exact, predictable float results on every
supported toolchain. Relying on Annex F would leave division silently
undefined on common toolchains, and contraction is the one compiler license
that can legally change `a * b + c` without any diagnostic.

## Bootstrap decisions

- Go is the temporary Stage 0 implementation language.
- `Domain`, `DomainMark`, `__s0_*`, fixed-capacity S0 Map, S0 Buffer,
  private `__s0_String = [U8]`, callback-bearing `using`, global source sets,
  and direct C symbol declarations are removal-gated bridges.
- Since M7.3 slice 3 the bootstrap bridges are compiler-private: an ordinary
  compilation rejects them, and only the private bootstrap profile
  (`--bootstrap-private`) keeps them available for `compiler/src`, the
  bootstrap spike, and bridge test fixtures. The public language constructs
  ordinary values through inferred storage, and the profile flag itself is
  removed together with the bridges.
- Self-hosting and fixed-point source bootstrap precede broad implementation
  of the 1.0 product profile, but they do not narrow that profile.

## Deferred decisions

The project deliberately defers LLVM/other backends, JIT/REPL, package
registry and semver solving, macro/compile-time execution, dynamic trait
objects, detached tasks, stable native Alder ABI, and broad debugger/IDE
refactoring. See [Open Questions](open-questions.md) for nonblocking follow-up
choices.
