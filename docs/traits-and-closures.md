# Alder Traits and Closures

Design status: **Frozen for Alder 1.0**

Availability: **Trait declarations, coherence, constraint resolution, closures, and function values are implemented (M7.5). `Cleanup` selection through `using` and its affine typing are implemented; there is no separate `AsyncCleanup` trait, and a `Cleanup` hook's ability to suspend arrives with the concurrency runtime's suspending capabilities in Milestone 9.**

Traits provide static library abstraction without changing Alder into a
runtime object system. Closures provide familiar higher-order APIs without
implicit shared mutable capture.

## Trait model

A trait constrains a compile-time type value. Trait calls are resolved during
checking and monomorphized before backend MIR. Alder 1.0 does not require a
vtable, runtime type descriptor, or dynamic dispatch for trait use.

```alder
trait Iterator(Item: type) {
    fn next(mut self) -> Option(Item)
}

fn drain(I: type(Iterator(T)), T: type, mut iterator: I) {
    while let Some(value) = iterator.next() {
        consume(value)
    }
}
```

Trait parameters use the same compile-time `type` values and parenthesized
application model as other generics. `Self` names the implementing type.
Required methods are public by contract. A trait may provide a default method
body that uses only its declared requirements.

`mut` remains an exclusive call borrow; it never mutates a copy. A non-self
`mut` parameter is legal for affine owners and scoped capabilities, and for
copyable values in exactly one shape: the parameter's type is a type parameter
whose constraint names a trait with at least one `mut self`
requirement, as `I` does above. At the call site the argument must be a
mutable place — a `var` binding, an owner, or another `mut` parameter
forwarding the cursor — so `iterator.next()` in the example advances the
caller's cursor. Passing a `let`-bound copyable cursor is rejected: it would
advance a discarded copy. (The `while let` loop shape shown above is the 1.0
source form; the current S0 profile expresses the same drain recursively
until `while let` lands with the frontend that replaces S0.)

Iteration keeps this model without associated types:

```alder
trait IntoIterator(IteratorType: type(Iterator(Item)), Item: type) {
    fn into_iterator(self) -> IteratorType
}
```

`for value in expression` asks inference for the unique applicable
`IntoIterator(IteratorType, Item)` implementation. Users see no type arguments
in the loop; generic libraries may name them when necessary.

The 1.0 trait surface supports:

- method and associated-function requirements;
- compile-time type parameters on traits and methods;
- constraints written on the type parameters of traits, nominal types,
  functions, and methods (`T: type(Order)`, D024), and on generic
  implementations once their parameter list is settled;
- default method bodies;
- multiple independent trait constraints.

It does not support associated types, trait inheritance, negative impls,
specialization, variadic generic packs, or dynamic trait objects. Generic
trait parameters cover the initial iterator and conversion cases without a
second type-selection mechanism.

## Implementations and coherence

```alder
impl Iterator(User) for UserCursor {
    fn next(mut self) -> Option(User) {
        // ...
    }
}
```

An implementation is legal only in the package that defines the trait or the
package that defines the implementing nominal type. There is exactly one
applicable implementation for a concrete trait/type combination in a complete
package graph. Overlapping blanket implementations and specialization are
rejected.

Implementation lookup uses no import order or source order. The compiler emits
a deterministic conflict diagnostic naming both package identities. Private
impls do not exist; an impl's availability follows the visibility of its trait
and type.

Primitive and structural implementations are supplied by the language or
`core`. Records, enums, arrays, vectors, maps, and sets receive structural
equality and hashing when all required components support them. A type cannot
override structural `==` with a surprising user implementation. User-defined
operators are not trait sugar in 1.0.

## Standard traits

The 1.0 prelude includes or re-exports:

- `Eq` and `Hash` for equality and hash containers;
- `Order` for explicit total ordering APIs;
- `Iterator(Item)` and `IntoIterator(IteratorType, Item)` for `for` and
  collection APIs;
- `Display` for user-facing formatting;
- `Error` for application error reporting;
- `Cleanup` for the infallible automatic hook selected by `using`;
- `Io`, `BlockingIo`, and `AsyncIo` for I/O capabilities (defined by `std.io`
  and recognized by the compiler for suspension checking and lowering);
- conversion traits used only by explicit named conversion APIs.

`Cleanup` is compiler-recognized because affine drop checking must know that a
resource is consumed on every normal exit. Its method is equivalent to:

```alder
trait Cleanup {
    fn cleanup(take self)
}
```

It cannot return a recoverable error. A resource exposes a separate consuming
`finish` or `close` method when the caller must observe an error; that method
releases the owner on both success and failure.

There is no separate asynchronous cleanup trait. A hook whose receiver holds a
suspending I/O capability, such as `TaskGroup(I)` joining its children, may
suspend; its scope exit is then potentially suspending and cancellation-shielded
as defined in [Memory and Resources](memory-and-resources.md) and
[Async and Structured Concurrency](async.md).

A trait's doc comment may contain a `# Missing implementation` section. When
no implementation applies, the diagnostic prints that section's first paragraph
after the direct cause, with `{Self}` and trait-parameter names substituted:

```alder
/// Types that can be compared for equality.
///
/// # Missing implementation
///
/// `{Self}` has no `==`. Records and enums get structural equality when every
/// field is `Eq`.
trait Eq { ... }
```

The section is documentation only and has no effect on semantics; Alder 1.0
adds no attribute syntax.

Task transfer safety is a compiler-derived structural property, not a trait
that safe user code can assert manually. This prevents an incorrect impl from
introducing data races.

## Constraint syntax

Type parameters remain ordinary leading `type` parameters. A constraint is
written on the parameter it constrains, as the list of traits inside
`type(...)` (D024):

```alder
fn sorted(T: type(Order), values: [T]) -> Vec(T) {
    // ...
}

type Index(K: type(Eq, Hash), V: type) {
    entries: Map(K, V)
}
```

`T: type` is unconstrained; `type(A, B)` requires every listed trait. A trait
with arguments is applied as usual: `I: type(Iterator(T))`. A constraint may
name any type parameter of the same list, before or after it. There is no
`where` clause and no `+` between traits.

The spelling follows one rule: lowercase keywords form a kind of type and take
their parts in parentheses (`fn(A) -> R`, `type(Order)`); capitalized names are
nominal types and traits applied with `Name(...)`.

Application remains `sorted(I64, values)` or inferred `sorted(values)`. Alder
does not add `<>` generic syntax merely because a declaration has constraints.

## Closure syntax and capture

A closure uses function syntax without a name:

```alder
let minimum = 10
let accepted = values.filter(fn(value: I64) => value >= minimum)
```

Parameter types may be inferred from the expected function type. A braced body
uses ordinary explicit returns:

```alder
let render = fn(user: User) -> String {
    return "{user.name}: {user.age}"
}
```

Read captures of ordinary values are independent value snapshots made when the
closure is created. Ordinary values include primitives, `String`, `Bytes`,
arrays, `Vec(T)`, `Map(K, V)`, `Set(T)`, records and enums over them, and
function values; a storage-backed capture is deep-copied into the closure's
environment, so mutating the source afterwards does not change what the
closure sees, and a function-valued capture is retained recursively. The
compiler may elide physical copies while preserving that behavior, and it
reports a copy site with its reason when it does not. A closure containing
only copyable captures is itself a copyable value.

A closure may also capture a scoped capability — an immutable slice or a
mutable view — but only when it provably does not escape the scope that owns
it. Every read of such a closure value in the enclosing function must be the
callee of a call through that value, so the value cannot be returned, stored in
a vector or record, or passed to a parameter that may retain it, and the
compiler rejects any other use with diagnostic 152. The restriction is
transitive: a closure that captures such a closure inherits it, so handing an
inner view-capturing closure to an escaping outer one is rejected too. The
environment holds the view header rather than a copy, so the closure reads the
original storage, and the escape rule keeps the owner alive for the closure's
whole life. Creating such a closure inside a loop body is not supported yet:
phase 6's loop-store rule classifies the environment record as a capability, so
the checker rejects the shape with diagnostic 153 instead of accepting a
program the verifier would refuse, and the limitation is listed in the
roadmap.

A closure that captures a scoped capability may also be passed to a parameter
that the callee provably does not retain, which is what makes the ordinary
higher-order call `values.filter(fn(value: I64) => value > 0)` work. The
compiler summarizes each function instance once per compile: a parameter is
non-retaining only when every use of it in the callee's body is a call through
the value or an argument forwarded to a parameter that is itself
non-retaining. Recursion settles by a monotone fixpoint over the instance call
graph, so a parameter of a recursive cycle stays non-retaining only when every
use in the cycle calls it or forwards it. Every use the summary cannot prove
safe makes the parameter retaining: returning the value, storing it, capturing
it in another closure, copying it to another domain, passing it to an import or
an `unsafe c` call, passing it to an unresolved call target, passing it as an
argument of a call through a function value, or forwarding it to a retaining
parameter. Passing a view-capturing closure to a retaining parameter is
rejected with diagnostic 152, and the callee's body keeps the same guarantee
in its own frame: a non-retaining parameter never reaches a return, a store, a
capture, or a cross-domain copy.

Alder 1.0 deliberately rejects:

- implicit capture of a mutable local for shared mutation;
- implicit capture of an affine owner;
- a closure escaping a captured scoped capability;
- concurrent use of a mutable capture without an explicit synchronization
  owner.

An API that needs ownership transfer accepts a named function plus explicit
arguments, or an affine callable object with a visible `take` parameter. This
keeps rare resource transfer explicit instead of adding routine per-expression
move syntax. Shared mutation uses a task-group channel, lock, or atomic rather
than a magic closure environment.

## Function values and ABI

Function and closure types use `fn(A, B) -> R`. Function values never suspend:
a closure body, or a named function used as a value, cannot contain a
potentially suspending call. APIs that take suspending work accept a named
function through a compile-time parameter or a standard `Pending(T)` call; see
[Async and Structured Concurrency](async.md). Noncapturing functions can
coerce to a function value. Capturing closures have compiler-generated
environments and are ordinary Alder values subject to their captured
categories.

Function values have no stable C representation. C callbacks use the explicit
function/context conventions in [C Interoperability](c-interop.md). No closure
environment crosses a C boundary unless a binding wrapper owns an explicit
retained callback registration.

## Deliberate limits

Trait objects, runtime reflection, higher-kinded type parameters,
specialization, arbitrary operator overloading, implicit mutable captures, and
escaping affine closure captures are outside Alder 1.0. These limits preserve
coherent static dispatch, simple monomorphization, and reviewable resource
ownership while supporting the standard library's required abstractions.
