# Alder Language Semantics

Design status: **Frozen for Alder 1.0**

Availability: **Partially implemented; see Alder S0**

Syntax: [Surface Syntax](syntax.md)

This document defines the observable behavior of the frozen core. Storage,
resource, and identity details are expanded in
[Memory and Resources](memory-and-resources.md).

## Semantic categories

Alder deliberately has three categories rather than applying one ownership
rule to every type.

### Copyable values

Primitives, records, enums, `String`, `Bytes`, arrays, `Vec(T)`, `Map(K, V)`,
`Set(T)`, and other finite value structures are copyable when their components
are copyable.

Copying produces an observationally independent value. Implementations may
share immutable representation, use copy-on-write, elide the copy, or construct
directly in the destination. Mutating one value must not mutate another value
created by assignment, argument passing, capture, or return.

Values do not expose source-invalidating moves.

### Affine owners

Exactly-once resources, `Table(T)`, foreign owned handles, task groups, task
handles, and a record or enum containing any such owner are affine. They have
one owning binding and cannot be copied. Implementing the compiler-recognized
`Cleanup` trait also makes a type affine.

Passing an owner to an ordinary parameter borrows it only for that call.
`mut` grants exclusive call access. `take` transfers ownership. Returning an
owner transfers it to the caller. An owner must be returned, transferred,
explicitly consumed, or cleaned by `using`; silently dropping or overwriting it
is rejected.

This limited affine rule is the safety boundary for resources and identity. It
does not turn ordinary values into a move-oriented language.

### Scoped capabilities

Immutable slices, mutable slices, table views, and similar accesses are tied to
an owner and a lexical access scope. A direct immutable slice result is allowed
when lowering can materialize caller-result storage; the same holds for an
ordinary aggregate result (record, enum, `Option`, `Result`, or array) whose
scoped parts are all immutable slices, which lowering materializes piecewise
into caller-result storage. Mutable views and aggregates containing them
cannot be returned, and a view-holding aggregate cannot be stored into a
local binding, call argument, match scrutinee, or cleanup initializer.
Capabilities cannot otherwise
be stored in longer-lived values, retained by unknown code, or used after
invalidation. Mutable capabilities are exclusive.

No user-written lifetime parameters are required in Alder 1.0.

## Binding and mutation

`let` prevents rebinding. `var` permits rebinding and place assignment for
ordinary values. Rebinding does not change the value semantics of assignment.

Affine owners expose explicit owner methods. A `mut self` method acquires
exclusive access to the owner for the call; this does not rebind its local
name. Because the owner cannot be copied, the compiler can reject overlapping
access without exposing a general borrow language.

A non-self `mut` parameter follows the same exclusive-borrow rule. It is
legal for affine owners and scoped capabilities, and for copyable values only
when the parameter's type is a type parameter constrained by a trait with at
least one `mut self` requirement (the iterator-cursor case). The argument
must then be a mutable place: a `var` binding, an owner, or another `mut`
parameter forwarding the cursor. A `let`-bound copyable argument is rejected
because the callee would advance a discarded copy instead of the caller's
value.

Mutation through a mutable slice or table view is allowed only while its
exclusive scope is active. The base owner cannot be relocated, removed,
destroyed, or accessed incompatibly during that scope.

## Evaluation order

Source evaluation is deterministic and left-to-right:

1. call arguments;
2. record fields in written construction order;
3. unary operands;
4. binary operands;
5. index base, then index;
6. range base, lower bound, then upper bound;
7. interpolation expressions;
8. assignment base/place components, then right-hand side, then the store;
9. cleanup registrations in source order.

`&&` and `||` evaluate the left operand first and evaluate the right operand
only when required. Pattern arms are selected in source order where patterns
can overlap. Generated C must preserve these rules with explicit temporaries.

## Numeric semantics

### Types and literals

Alder has only exact-width numeric types:

```text
I8 I16 I32 I64
U8 U16 U32 U64
F32 F64
```

There is no target-width `Int`. Collection lengths and indices use `U64`; a
backend checks representability before conversion to a narrower target
`size_t`.

Integer literals are arbitrary-precision semantic values until adapted. With
an expected integer type, the literal must fit exactly. With no expected type,
it defaults to `I64`. Float literals analogously adapt and default to `F64`.

### Arithmetic

Integer add, subtract, multiply, divide, and remainder are checked for their
numeric failure conditions. Failure is an unrecoverable invariant failure
unless an explicitly fallible API is used. Division fails on zero and signed
minimum divided by `-1`.

Left shift operates on the fixed-width bit pattern and checks only the count;
signed right shift is arithmetic, unsigned right shift logical. Shift counts
must be nonnegative and smaller than the source width.

Bitwise `&`, `|`, `^`, and `~` operate on the fixed-width representation.

Float `+`, `-`, `*`, and `/` on `F32` and `F64` follow IEEE 754 in the default
non-stop mode and never fail: overflow produces the signed infinity, underflow
is gradual, and division by zero is defined — the quotient is the signed
infinity with the sign of the XOR of the operand signs, and NaN when both
operands are zero or either operand is NaN. Float comparison and equality
follow IEEE 754: NaN compares unordered with every operand, and the two zeros
compare equal (decision D026).

### Conversions

There are no implicit width, signedness, integer/float, or C ABI conversions.

An infallible widening conversion may use `Target(value)` only when every value
of the source type is representable in the target. Potentially failing
conversions use `Target.try_from(value) -> Result(Target, ConvertError)`.
Explicit bit-pattern or wrapping behavior uses named operations such as
`Target.wrapping_from(value)` and `wrapping_add`; it is never selected by
context.

`F32` and `F64` require IEEE-754 binary32 and binary64 target support in the
initial language. Alder does not promise to preserve NaN payloads or honor
ambient foreign changes to the C floating-point rounding mode.

## Boolean logic and equality

Conditions require `Bool`; there is no truthiness.

Equality is defined for:

- booleans and numeric primitives;
- strings by exact UTF-8 bytes, with no implicit Unicode normalization;
- bytes by exact bytes;
- IDs by type, table identity, slot, and generation;
- records and enums only when every component has equality;
- builtin `Option` and `Result` by implicit tag first and then by payload,
  when every component has equality.

Floating equality follows IEEE-754 comparison behavior, including NaN.
Resources, tables, views, function values, and raw pointers do not receive
ordinary structural equality. `c.is_null(pointer)` is the one safe raw-pointer
observation; pointer-to-pointer equality, ordering, arithmetic, and dereference
remain explicit unsafe C operations.

Ordering is defined for numeric primitives and exact byte/string lexical APIs.
General user-defined comparison waits for the trait contract.

## Text, bytes, and sequences

`String` is an immutable sequence of valid UTF-8 code units. Equality and
hashing use exact UTF-8 bytes; normalization is an explicit library operation.
Integer indexing is not defined on `String`. APIs separately expose byte views,
Unicode scalar iteration, and any future grapheme facilities.

`Bytes` is an immutable arbitrary byte value. `Array(T, N)` is a fixed-size
value. `[T]` is an immutable scoped view of contiguous elements.
`MutSlice(T)` is an exclusive mutable scoped view. `Vec(T)` is a growable value
collection. `Map(K, V)` and `Set(T)` are insertion-ordered value collections
with trait-defined hashing and equality; neither is S0's fixed bootstrap map.

Copying an owned collection has value semantics. An implementation may avoid
eager copies through proven uniqueness or immutable sharing, but later mutation
must remain independent and potentially linear copy costs must be visible to
diagnostics/profiling where they cross owners. `Map`/`Set` iteration is insertion
order; replacing an existing map value preserves its position, while removing
and later reinserting a key places it at the end. Hash randomization cannot
change observable order.

## Algebraic data and matching

Records are nominal products. Enums are nominal sums with zero or one payload
per variant. `Option(T)` and `Result(T, E)` are ordinary built-in algebraic
types:

```text
Option(T) = None | Some(T)
Result(T, E) = Ok(T) | Err(E)
```

`T?` is exactly `Option(T)`, not a nullable reference representation.

Matching an algebraic value is exhaustive. A wildcard covers all remaining
variants. Payload bindings are immutable. Matching an affine enum consumes its
owned scrutinee if an owner payload is extracted; a temporary can be consumed
directly, while an owned local is unavailable afterward. Borrow-only pattern
tests such as `if let` cannot let an affine payload escape their access scope.
A `match` arm may carry an `if` guard evaluated after its pattern matches; a
false guard continues with the next arm, a guarded arm does not count toward
exhaustiveness, and a guard cannot consume a binding.
An arm body may instead diverge with `return`, which is checked against the
function's result type and leaves the match without producing a value; the
match's type comes only from its value-producing arms, so at least one arm
must produce a value. The type, not a general `move` expression, exposes this rare consumption.
The `let payload = option else ...` extraction form consumes an affine option
and transfers its payload, while it copies a copyable payload.

## Recoverable errors

`Result(T, E)` is the sole ordinary recoverable-error mechanism. There are no
hidden exceptions.

For `try expression`:

- `Ok(value)` evaluates to `value`;
- `Err(error)` returns `Err(error)` from the current function;
- the current function must return `Result(_, E)` with exactly the same `E` in
  Alder 1.0.

When `E` contains relocatable collection storage, failed `try` propagation
materializes the complete `Err(E)` value in caller-result storage before local
cleanup and function-domain destruction.

Error adaptation uses an explicit `map_error` call or another ordinary
conversion; it is never implicit. The standard convention is that each module
defines its own precise error enum, wraps a lower-level error as a variant
payload instead of re-exporting it, and reports that payload through the
`Error` trait's `cause` method (an `ErrorReport`, D025), so diagnostics can print the whole chain. `try` does not catch bounds, overflow,
infallible allocation, or C contract violations. If `T` is affine, `try`
consumes the `Result(T, E)` and transfers the `Ok` owner into its result binding.

## Unrecoverable failure

Failed checked invariants, an infallible allocation API exhausting storage,
identity exhaustion, verifier-impossible runtime states, and violated runtime
contracts terminate the process with a deterministic diagnostic/status.

This failure is not catchable, does not fabricate a `Result`, and does not
promise stack unwinding. The implementation may run more cleanup before abort
than the language guarantees, but safe code cannot rely on it.

Operations for which exhaustion or capacity is expected expose explicit
fallible APIs such as `try_reserve` and return `Result`.

## Functions, methods, and generics

Function calls use value semantics for copyable values and call-scoped borrows
for affine owners. A callee cannot retain a borrowed owner or capability.

Inherent methods are statically selected from the receiver's nominal type and
monomorphized. Dot-call syntax does not perform open-ended extension lookup or
runtime dispatch.

Compile-time `type` parameters are inferred and monomorphized before executable
MIR. Type values do not exist at runtime merely because source code was
generic. Recursive specialization must produce a finite set of concrete
instances; specialization-expanding polymorphic recursion is rejected.

User-defined traits and capturing closures are required by Alder 1.0 and obey
the static coherence and capture rules in
[Traits and Closures](traits-and-closures.md). Dynamic trait objects remain
outside 1.0.

## Control flow

Functions evaluate statements in source order. `return` exits explicitly.
Every reachable path in a non-`Unit` function returns a value. A `Unit`
function may fall through. `()` is the sole `Unit` value and a bare `return`
returns it.

`if`, `while`, and `for` are statements. Loops have `break` and `continue`, but
do not produce values in the core. `match` is an expression and may be used as
an expression statement when its effects are intentional.

`for` infers `IntoIterator(IteratorType, Item)` and requires
`IteratorType: Iterator(Item)`. The standard library provides coherent
implementations for arrays, slices, mutable slices, vectors, ordered map
key/value views, sets, strings by Unicode scalar, and integer ranges. Iteration
over an affine owner borrows unless an API explicitly returns an owning
iterator.

## Source modules

Modules are compile-time namespaces and dependency units, not native ABI
boundaries. Imports are acyclic in Alder 1.0. Whole-program inference,
monomorphization, and C generation remain allowed. Module declaration order and
input file order do not change meaning, diagnostics, MIR, or generated C.

See [Modules and Builds](modules-and-builds.md).

## I/O capabilities and task semantics

There is no `async fn`. Code that waits on the host receives an I/O capability
through a compile-time type parameter bounded by `Io`, `BlockingIo`, or
`AsyncIo`. Whether a call may suspend is decided from signatures and bounds
during checking; each monomorphized instance then lowers either to direct code
(every capability is `BlockingIo`) or to a verified state machine. A bare call
always runs to completion before the caller continues; only a standard task
operation given a direct `Pending(T)` call starts concurrent work. Function
values never suspend.

Every spawned task belongs to a lexical `TaskGroup`. Ordinary inputs are
independent values, affine inputs transfer only through visible `take`
parameters, and mutable/scoped capabilities do not implicitly cross a task
boundary. A result-bearing task handle must be awaited on normal paths; a
unit-returning started child is joined by the group. Group exit joins normally
or cancels and joins during an exiting control path. Cancellation is a
structured control effect rather than a user exception or fabricated result.

Safe task code is data-race-free, but scheduling and independent I/O completion
order are not deterministic. Channels and synchronization owners define their
own observable ordering. See [Async and Structured Concurrency](async.md).

## Unsafe boundary

Safe semantics end at `unsafe c` and any later explicitly unsafe primitive.
Unsafe code may manipulate raw C values but cannot claim a safe Alder value
without validating that value's invariants. The compiler still checks syntax,
types, control flow, and the declared ABI inside an unsafe block.

Unsafety is lexical and reviewable; it does not become a property inferred from
an entire module or function. See [C Interoperability](c-interop.md).
