# Alder S0 Bootstrap Language

Design status: **Bootstrap-only contract**

Availability: **Implemented by the Go Stage 0 frontend and the source-bootstrapped Alder compiler**

This document isolates the implemented bootstrap language from the Alder 1.0
design. A rule in this file is not a permanent language decision unless a 1.0
document also states it.

There are currently two implementation profiles:

- the Go `frontend` package implements the complete Milestone 4 S0 pipeline to
  verified MIR and C11;
- `compiler/src/*.al` is the source-bootstrapped Alder implementation. Its
  lexer and parser cover the current S0 syntax; its checker and lowering cover
  the sealed S0 boundary, and its complete-verifier-gated C generator covers
  the current scalar/CFG and resource MIR slice. Its explicit-source driver
  implements the same `check` and `compile --emit=mir|c` request, diagnostic,
  status, and output contract as the Go bootstrap. MIR and C bytes are emitted
  only after complete V1–V10 verification; C generation also completes its
  supported-operation preflight before writing.

Neither profile is a usable Alder 1.0 compiler. The two profiles differ in one
place: the Alder compiler registers a `using` in a loop body for that
iteration's scope, while the frozen Go Stage 0 frontend still rejects the
declaration, so the shared rejection fixture is exercised against Go only.

## Compilation model

S0 accepts one or more explicitly supplied `.al` files. The driver validates
canonical slash-relative logical paths, sorts by UTF-8 path bytes, and forms one
global compilation unit. The compiler core never scans directories.

All C import, type-constructor, variant, and function names share a global
namespace. S0 has no `module`, package, ordinary Alder import, visibility,
manifest, separate compilation, or C header binding. The 1.0 replacement is
[Modules, Packages, and Builds](modules-and-builds.md).

The Go pipeline is:

```text
explicit source set
    -> lossless-enough lexer/parser AST
    -> checking, inference, and monomorphization
    -> deterministic MIR
    -> full MIR verifier
    -> deterministic conservative C11
```

Invalid MIR is a frontend bug and is never repaired by the backend.

## Declarations

The implemented top-level forms are:

```alder
import c strlen: fn(Ptr(U8)) -> U64

type Pair(T: type) {
    value: T
}

type Counter {
    value: U64
}

enum Maybe(T: type) {
    Some(value: T)
    None
}

fn identity(T: type, value: T) -> T {
    return value
}

export c fn process_bytes(
    data: c.ConstPtr(c.UChar),
    length: c.Size,
) -> c.Int {
    return c.Zero(c.Int)
}

impl Counter {
    fn get(self) -> U64 {
        return self.value
    }
}
```

Generic compile-time parameters must be the leading `type` parameters. Type
application and explicit specialization use `Name(...)`. A call either omits
all type arguments and infers them from runtime arguments/expected result, or
supplies all of them. Monomorphization completes before MIR.

Function parameters use ordinary copy/borrow semantics by default. `mut`
permits mutation through a mutable argument or receiver, while `take`
transfers an affine value and invalidates the source on that path. Inherent
`impl Type { ... }` blocks provide `self`, `mut self`, and `take self`
receivers plus associated functions. They do not provide extension methods.
The owner domain of a borrowed place is a compiler-internal MIR contract, not
source syntax: a hidden `domain_handle` parameter follows each `safe_mut`
parameter in MIR, and source programs never name or annotate it.

The source-bootstrapped compiler additionally implements intentional C
exports: a top-level `export c fn` declaration defines a non-static C symbol
named by the Alder function. Its signature is restricted to C ABI types:
`c.*` raw scalars, `c.Ptr(T)`/`c.ConstPtr(T)` over a bound C type, and a
verified bound scalar or record by value; a `Unit` result maps to C `void`
and is written as `Unit` in source. Any other signature type is diagnostic
221; a generic, receiver-bearing, or otherwise invalid signature, a reserved
or invalid C symbol, and an export named `main` are 222; and an export whose
symbol equals a raw `import c` fn's C spelling is 223. The Go Stage 0
frontend does not parse this form. `compile --emit=header` prints the
matching deterministic header after verification.

Milestone 7.5 adds the static trait surface of
[Traits and Closures](traits-and-closures.md) up to constraint gating:

- `trait Name(Params) { ... }` declares a trait; each parameter carries its
  constraints in `Params` itself (`trait Collect(Item: type(Iterator(Item)))
  { ... }`). Method
  requirements are `fn` signatures; a requirement with a body carries a
  default implementation. `Self` names the implementing type inside a trait
  or one of its implementations. Trait and impl methods may declare their
  own leading `type` parameters; an implementation method must declare
  exactly as many as its requirement, and they match positionally. Method
  type parameters are recorded in the trait's scope, so their names must be
  unique across the whole trait and they resolve throughout it; explicit
  specialization follows the receiver (`box.combine(U64, 3)`). Defaulted
  requirements synthesize for every trait: a materialized method resolves
  the trait's parameters as the concrete trait arguments of its own
  implementation.
- `impl Trait(Arguments) for Type { ... }` implements a trait for a
  non-generic declared record or enum type with concrete trait arguments.
  Methods are ordinary functions; their bodies are checked and lowered even
  before trait-method dispatch exists.
- `impl(Param: type(Constraints), ...) Trait for Type(Arguments) { ... }`
  declares a generic implementation (D024): the parameter list reuses the
  declaration parameter form, every listed parameter must appear in the
  implementing type's arguments, an implementing type that is a bare
  parameter of its own list is rejected, and the implementing type's own
  parameter constraints must be restated on the matching parameters
  (`impl(I: type(Io)) Reader for File(I)`); additional constraints are
  allowed. Constraint arguments and the trait application resolve in the
  implementation's scope, so parameters may appear in any order. Methods of
  a generic implementation are checked per concrete instance and their
  bodies never resolve the parameters abstractly.
- `impl(Param: type(Constraints), ...) Type(Arguments) { ... }` declares a
  generic inherent implementation with the same parameter rules. Its methods
  and associated functions are instance-only as well; the receiver type of a
  method call and the argument and expected-result types of an associated
  function bind the parameters, and a call that leaves one unbound is
  rejected.
- Constraints are written on the type parameter itself (D024):
  `T: type` is unconstrained, and `T: type(Order)`, `K: type(Eq, Hash)`, and
  `I: type(Iterator(T))` attach the listed traits to the parameter in
  function, record, enum, trait, and method signatures. There is no `where`
  clause and no `+` between traits; a `where` after a signature is rejected
  with the syntax diagnostic `SYN0001` kind 24. Constraint arguments resolve
  in the declaration's scope across the whole parameter list, so a
  constraint may name a parameter declared before or after it
  (`IntoIterator(IteratorType, Item)` keeps that order).
- The builtin standard traits `Eq`, `Hash`, `Order`, `Display`,
  `Iterator(Item)`, `IntoIterator(IteratorType, Item)`, and `Cleanup` exist
  without source declarations. `Error` is a prelude trait with a defaulted
  `cause` method and the prelude `ErrorReport` value; its source-backed
  prelude contract is documented in
  [`core.error`](api/core.error-v1.md).
- Coherence holds per compilation unit: exactly one implementation may exist
  for a concrete trait application. Orphan-rule enforcement across a package
  graph waits for the module system.
- Instantiating a constrained generic function requires an implementation for
  every constraint; the lookup uses one impl index built after collection.
  The coherence key is the concrete (trait, implementing type, trait
  arguments) combination. A generic implementation is conditional: it
  satisfies the constraint when its head unifies with the concrete
  implementing type and its own constraints hold for the arguments that
  unification binds, and a type parameter satisfies the constraints its own
  declaration lists.
- Every implementation is validated: required methods must be present with
  exactly the trait's receiver mode, runtime arity, and substituted
  parameter/result types, and impl methods that match no requirement are
  rejected. Generic impl methods are not supported yet; defaulted methods
  are materialized as ordinary impl methods and dispatch statically.
- Structural `Eq` and `Hash` implementations are synthesized by the
  language for `Bool`, signed and unsigned integers, `String`, `Bytes`, and
  non-generic records and enums whose every component supports them, so
  `K: type(Eq, Hash)` accepts those types. `==` and `!=` dispatch to that
  synthesized implementation: integers and `Bool` compare as primitives,
  `String` and `Bytes` compare byte-wise, and records and enums decompose
  into their components; a type outside the synthesized domain is rejected
  with a diagnostic. Floating `==`/`!=` remain operator-only IEEE-754
  comparisons (D026): NaN is not reflexive, so floats are not in structural
  `Eq`/`Hash`. Map and Set keys remain unsigned in M8 even though signed
  integers now participate in `Eq`/`Hash`. Builtin `Option` and `Result`
  decompose the same way: they compare by implicit tag first (none/some,
  ok/err) and then by
  payload, accepted exactly when every component type supports the
  structural domain. Per
  [Traits and Closures](traits-and-closures.md), "A type cannot override
  structural `==` with a surprising user implementation": user `impl Eq`
  and `impl Hash` blocks are rejected. The synthesized methods are not
  directly callable yet; they become callable with the ordered collections.
- Structural `Order` implementations are synthesized by the language for
  the closed scalar domain: unsigned integers `U8`, `U16`, `U32`, and
  `U64`, `Bool` (false orders below true), `String`, and `Bytes`
  (both byte-lexicographic, shorter prefixes first). The trait has the
  single requirement `fn less(self, other: Self) -> Bool`, and the
  synthesized method is directly callable as `x.less(y)`; `T: type(Order)`
  accepts exactly the domain types, and any other receiver or instantiation
  is rejected with a diagnostic. Signed integers, floats, and composites
  join only if a later decision widens the domain; user `impl Order`
  blocks are rejected like `Eq` and `Hash`.
- The builtin `Display` trait has the single requirement
  `fn display(self) -> String`, and the language provides the
  implementation for the scalar formatting domain: `Bool`, the signed and
  unsigned integers (decimal, signed values with `-`), and `String` (the
  string itself). The method is directly callable as `x.display()`.
  Unlike the structural traits, user `impl Display` blocks are accepted
  for declared record and enum types and participate in coherence and the
  generic per-instance re-check like any trait implementation. A receiver
  or generic instantiation outside the domain without a user
  implementation (floats, `Bytes`, composites) is rejected with a
  diagnostic; widening the domain waits for a later decision.
- Trait-method dispatch is static: a dot-call resolves inherent methods
  first, then the unique trait implementation providing that method name for
  the receiver's concrete type. Because generic bodies are checked per
  concrete instance, a constrained call site dispatches to that instance's
  implementation with no vtable; resolved impl methods lower as ordinary
  monomorphized functions named `<method><owner-symbol-id>`, including
  methods with their own type parameters instantiated per call site.
- A non-self `mut` parameter is legal for affine owners, scoped
  capabilities, and a copyable type parameter constrained by a trait with at
  least one `mut self` requirement (the builtin `Iterator` or a user trait).
  The call-site argument must be a mutable place: a `var` binding, an owner,
  a field or element path of one of those, or another `mut` parameter
  forwarding the cursor. A `let`-bound copyable argument is rejected, because
  the callee would advance a discarded copy.

Closures and function values are partially implemented as Milestone 7.5
work in progress:

- `fn(A, B) -> R` is a checked function type usable in annotations,
  parameters, results, and bindings. A parameter may be borrowed with
  `fn(mut T) -> R`; the mode is part of the type and never converts to or from
  `fn(T) -> R`. `take` is not spellable in a function type, and a closure
  literal declares only plain parameters. A named non-generic function in value
  position is a function reference, and a call whose callee is a
  function-typed binding is an indirect call; both lower through
  `fn.value`/`call.value` and run under the generated strict C11.
- A closure literal `fn(name: Type, ...) => expr` or
  `fn(name: Type, ...) -> R { ... }` creates a function value. Parameter
  types are required; the arrow form infers its result type from the body
  expression. Reads of enclosing `let`/`var` locals are independent value
  snapshots taken at creation: captures resolve as hidden trailing
  immutable parameters of a compiler-generated thunk function, so writes to
  a capture are rejected as writes to an immutable binding, and only
  ordinary snapshot values may be captured: primitives, `String`, `Bytes`,
  arrays, `Vec(T)`, `Map(K, V)`, `Set(T)`, records and enums over them, and
  function values. A storage-backed capture is copied into the environment's
  domain at creation and deep-copied into a destination domain when the
  closure escapes, and function-valued captures are retained recursively.
  Affine owners are still rejected. A scoped capability (a slice or view) may
  be captured only by a closure that provably does not escape the scope that
  owns it: every read of the value in that scope must be a call through it or
  an argument at a parameter the callee's per-instance summary proves
  non-retaining, and the restriction carries through captured closures. The
  thunk ABI is
  `(declared parameters, opaque environment pointer)`; capture-free closures
  are plain function values.
- A literal nested inside another literal captures transitively: the outer
  environment carries every value the inner body reads, including values the
  outer literal never reads itself. An outer literal whose body nests another
  literal records the domain that owns its environment in the record, and its
  thunk allocates the inner environment in that domain. Closure creation
  inside a `while` loop is carried by the immutable environment snapshot.
- Every closure body has a domain: a capturing closure's environment record
  carries the domain that owns it, and a closure with no captures takes the
  caller's domain as its leading hidden parameter, like a named function
  value. A body may therefore copy or allocate storage and return it.
- A view created in a loop iteration is created and read inside that
  iteration, so nothing crosses the backedge: `let s = v.slice(0, 2)` in a
  `while` or `for` body, a view of a vector the loop reassigns, and a
  table-view arm (`match t.get(id)` or `match t.get_mut(id)`) inside a loop
  body all work. A view cannot be *assigned* inside a loop body, because the
  target slot survives the backedge and the next iteration could read a
  header the loop has since relocated; bind the view where it is created.
  Diagnostic 154 rejects the assignment.
- Known limits of this slice: parameter type inference from the expected
  function type is not implemented; malformed closure shapes are rejected
  with diagnostic 147; a closure that captures a scoped capability and
  escapes is rejected with diagnostic 152, and creating one inside a loop
  body is rejected with diagnostic 153 until the phase-6 loop-store rule
  accepts a view-carrying environment record.

Default-method dispatch and trait-backed collections are not implemented yet
and remain later Milestone 7.5 work.

The hosted entry results are `Unit`, `I32`, `Result(Unit, E)`, and
`Result(I32, E)` where `E` implements `Display`; a generated adapter maps them
to the fixed C host shim. The `root: Domain` parameter form remains available
only under the private bootstrap profile (see below); ordinary programs use
the parameterless form and receive the hidden root domain through inferred
storage. Entry argument-slice forms remain outside this adapter.

## Lexical and layout rules

S0 source is UTF-8, semicolon-free, and case-sensitive. Identifiers use ASCII
letters/digits/underscore and may not begin with the reserved `__s0_` prefix.
`//` and non-nesting `/* ... */` comments are supported.

Physical newlines separate top-level declarations, fields, variants,
statements, and match arms. Expressions cannot cross an outer physical newline
but can continue inside `()`, `[]`, or expression braces. Parenthesized lists
use commas and allow one trailing comma. Fields, variants, and match arms use
newlines rather than commas.

The parser erases grouping nodes from its semantic tree while the token stream
retains delimiters.

## Implemented types

Primitives:

```text
Bool
I8 I16 I32 I64
U8 U16 U32 U64
F32 F64
Unit
```

Composite/bootstrap types:

- `[T]` slice;
- `Array(T, N)` fixed array;
- distinct owned `String` and `Bytes` values;
- `Option(T)` and `Result(T, E)`;
- nominal generic records and zero/unary-payload enums;
- fixed-capacity bootstrap `Map(K, V)`;
- raw `Ptr(T)` for C imports;
- temporary `Domain`, `DomainMark`, `__s0_Buffer(T)`, and `__s0_Error`.

The bootstrap-only types above (and the fixed `Map`) are private to the
bootstrap profile; ordinary programs reach `String`, `Bytes`, `Array(T, N)`,
`Vec(T)`, `[T]`, and `MutSlice(T)` instead.

`String` requires valid UTF-8 and `Bytes` preserves arbitrary bytes. Neither is
an integer-indexable slice. Compiler implementation sources temporarily use the
reserved private `__s0_String` slice bridge for byte-oriented bootstrap work;
ordinary source does not share that identity. The S0 map, buffer, domain, and
pointer rules are not the 1.0 `Map`, `Vec`, inferred-storage, or C binding
contracts.

Current representation restrictions reject mutable-view and other
non-materializable lifetime-bearing values in aggregate storage, aggregate
view results whose scoped leaves are not all immutable slices, infinite value
recursion, unsupported map keys/values,
unsupported C signatures, and specialization-expanding polymorphic recursion.
Ordinary aggregates may declare immutable-view fields and return them: M7.3
lowering materializes such results into caller-result storage, while local
bindings, arguments, match scrutinees, and cleanup initializers still reject
view-holding aggregates. The exact restrictions are pinned by `frontend`
acceptance/rejection tests and
the active Alder checker conformance harness.

## Statements and expressions

Implemented statements:

```text
let, var, assignment
if / else if / else
while
for name in slice
return
using name = value with cleanup_function
using name = value
block
match expression statement
```

An `else if` chain is an `else` whose block holds one nested `if` statement, so
a chain obeys the ordinary block and statement rules at every level.

The second `using` form is the M7.5 public surface: it accepts a `Table(T)`
owner (registering the builtin release), any affine nominal type implementing
`Cleanup` (registering the concrete instance of its trait method), or a
`Vec(T)` of `Cleanup` owners (registering a per-element drain). The
`with cleanup_function` clause stays the bootstrap-private bridge.

`break` and `continue` jump to the exit and the next iteration of the
innermost enclosing loop; `continue` in a `for` still runs the index step, and
both are rejected outside a loop, in a closure body, and in a table-view match
arm. A `using` registration inside a loop body is rejected, so neither jump can
cross a cleanup scope. Assignment targets are restricted to the implemented
identifier/field/index shapes. Growing or replacing relocatable storage
through a field of a `mut self` receiver or a `mut` parameter allocates in the
domain that owns the borrowed place. A local uses the function's frame domain;
a value read from a borrowed field is an ordinary value copy in that domain,
and a value stored back into a borrowed field is materialized in the field's
owner domain first. Every non-`Unit` function path returns explicitly.

Implemented expressions include:

- integer, float, Boolean, string/bytes, fixed-array, and `()` literals; the
  `()` literal has type `Unit` and may appear as a return operand, a `Unit`
  argument, or an absent variant payload such as `Ok(())`. It cannot be bound
  and a standalone `()` statement is rejected with diagnostic 331; only a
  `Unit`-result call may stand alone;
- unary `-`, `!`, and `~`;
- checked arithmetic, shifts, bitwise `&`/`|`/`^`, comparisons, equality for
  supported primitives, and short-circuit Boolean operators;
- named builtin overflow methods on the eight integer types:
  `add_checked`/`sub_checked`/`mul_checked` yield `Option(T)` (`none` on
  overflow, `some` with the wrapped result otherwise), `*_saturating` clamp
  at the type's boundary, and `*_wrapping` wrap on the two's-complement
  pattern;
- mutable views are formed from places: a local binding, a `mut` parameter,
  or a field or element path of one. `slice_mut` and `subview` read a field
  or element receiver as its collection header, and writes through the view
  land in that place's existing storage. A view is still rejected from a call
  result or another temporary, and it cannot escape its owning scope;
  immutable views may be formed from any place, since they only read;
- named builtin byte-sequence methods on `String` and `Bytes`: `len()` is
  the byte count, `byte(index) -> U8` rejects an index at or above the
  length through the panic path, `concat(other) -> Self` joins two sequences
  of the same type, `slice(lo, hi) -> Self` rejects an inverted or
  out-of-range range through the panic path, `String.to_bytes()` reinterprets
  the string's bytes without copying, and
  `Bytes.to_string_checked() -> Option(String)` validates UTF-8 and yields
  `none` on invalid input. These names apply only when the receiver type is
  `String` or `Bytes` (a literal included); on every other type the name is
  resolved like an ordinary method, so user impls may declare methods named
  `len` or `to_bytes`, and a call with such a name on a type that provides
  neither a builtin receiver nor an impl method is rejected with a dedicated
  diagnostic naming the builtin method. A `[U8]` view also carries
  `to_bytes() -> Bytes`, which copies the view's bytes into fresh storage, so
  `Array(U8, N).slice(...)` and `Vec(U8).slice(...)` produce an owning `Bytes`
  without aliasing the view's owner; a view of any other element type is
  rejected with its own diagnostic;
- named builtin conversion methods on the eight integer types: `to_T()` for
  widening pairs is total (widening means `T` is wider and the receiver is
  unsigned or both types are signed), while `to_T_checked() -> Option(T)` and
  `to_T_wrapping() -> T` exist for every other pair, the checked form
  yielding `none` for a receiver value that does not fit `T` and the wrapping
  form truncating to the target width on the two's-complement pattern. The
  lossy bare form, identity conversions, and the checked or wrapping form on
  a widening pair are rejected (kinds 251, 252, and 253);
- named builtin C scalar conversion methods between `c.*` scalars and Alder
  numerics: `c.*` integer scalars carry `to_i8` .. `to_u64` in bare,
  `_checked`, and `_wrapping` forms (bare accepted only where the pair is
  lossless on every target, including `c.Char` whose width and signedness
  are target properties), `c.Float` carries `to_f32` and `to_f64`, and
  `c.Double` carries `to_f64`; Alder integers carry `to_c_char` through
  `to_c_ptrdiff` in the same three forms, and the float specials are
  `F32.to_c_float`, `F64.to_c_double`, and `F64.to_c_float_checked() ->
  Option(c.Float)`. Any other conversion name on such a receiver is rejected
  with kind 205. See [C Interoperability](c-interop.md);
- `Option(T).take()` on a mutable place moves the current option value out and
  stores `none` back into the same place; the payload may be affine and is
  transferred to the returned value. `take` is a parameter-mode keyword, so a
  member position after a dot is the only place it names a method. A `let`
  binding is rejected as an immutable place, and a non-place receiver is
  rejected with kind 310;
- calls, record/variant construction, field access, index and range;
- exhaustive `match` over enums, `Option`, and `Result`, including statement
  arms (`=> { ... }`) whose bodies may hold ordinary statements, diverging
  expression arms (`=> return ...`, where the return is checked against the
  function result type and control never reaches the match join), and `if`
  guards: the guard runs after the pattern matches, a false guard continues
  with the next arm, a guarded arm never counts toward exhaustiveness, and a
  guard only borrows its bindings (kinds 148 and 149). The arms of one match
  share one body form: diverging arms do not mix with `=> { ... }` block
  arms (kind 135), a table-view match rejects them (kind 133), and a match
  whose every arm diverges has no value and is rejected (kind 305);
- prefix `try`: in a function returning `Result`, the operand is `Result`
  with the same error type; in a function returning `Option`, the operand is
  `Option` with the same payload type and `none` early-returns from the
  function;
- inside `unsafe c { ... }`: one direct imported call, one C record field
  read `rec.field`, or one C record field write `rec.field = value` through
  a `var` local holding a verified by-value C record; the field forms are
  rejected with kinds 206-209 outside those shapes;
- M7.5 table identity: `Table(T)` over concrete ordinary values (including
  vec-bearing records),
  `Table.new(T)`, `t.insert(value) -> T.Id`, `t.remove(id) -> Bool`, and
  `t.get(id)`/`t.get_mut(id)` consumed only as a match scrutinee, where the
  `Some` arm binds a scoped view usable for field reads (and field writes
  through `get_mut`) inside a straight-line fail-free arm body. Inserting an
  element snapshots it into the table's domain: a still-live source is
  deep-copied there at insert, and a source dead after the insert transfers
  its storage instead, so stored owning elements survive the inserting
  function; reads of the table itself are borrows and never copy it;
- the callback-free `using name = Table.new(T)` registration, whose owner is
  cleanup-covered at every exit and disarmed on transfer;
- call-scoped C buffer borrows: inside `unsafe c`, a `Bytes`, `[U8]`, or
  `MutSlice(U8)` argument may stand for a raw fn parameter declared
  `c.ConstPtr(T)` or `c.Ptr(T)` with a byte-addressable pointee (`c.Char`,
  `c.SChar`, `c.UChar`, or an opaque type). The pointer is valid only for the
  call, the buffer is never moved, immutable buffers satisfy only `c.ConstPtr`,
  one buffer may not be borrowed mutably twice in a call (kind 215), a
  non-byte pointee is kind 213, and an immutable buffer for a mutable pointer
  is kind 214. An empty buffer still passes a valid address through the
  runtime dummy. The length is the caller's responsibility inside the unsafe
  block;
- zero-initialized C boundary values: `c.Zero(T)` takes a `c.*` scalar or a
  bound scalar or record type member (bare when exactly one binding block
  declares it, or `alias.Name`) and yields a zero-initialized copyable value
  in ordinary code. Record fields still require `unsafe c`; an opaque member,
  a pointer type, an unknown or ambiguous name, and a wrong argument count are
  kind 216;
- out-parameter addresses: `c.addr(place)` is admitted only as a direct raw
  call argument inside `unsafe c` and names a local variable or field path of
  one whose type is the declared pointee. `c.Ptr` requires a `var` binding
  with no live view of its root, `c.ConstPtr` any local place without a
  mutable view, and the pointer never becomes an Alder value. Every other
  use, type mismatch, immutable or non-local place, and conflicting live view
  are kind 217;
- pointer member access: inside `unsafe c`, `ptr.field` reads through a local
  holding `c.Ptr(Rec)` or `c.ConstPtr(Rec)` over a verified record, and
  `ptr.field = value` writes through `c.Ptr` only (kind 219 for a const
  pointer);
- `c.load(ptr)` and `c.store(ptr, value)`: whole-value C memory access behind
  one pointer, available only inside `unsafe c`. `c.load` takes `c.Ptr(T)` or
  `c.ConstPtr(T)` and yields `T`; `c.store` takes `c.Ptr(T)` and a value of
  exactly `T` and yields `Unit`. A non-pointer or opaque-pointee argument and
  a wrong argument count are kind 218, a const-pointer write is 219, and a
  mismatched stored value is 220. No null, alignment, or lifetime check is
  emitted: those are the unsafe caller's obligation;
- `c.CString`: a string literal builds the bare owner infallibly and an
  interior NUL in that literal is rejected at compile time (kind 210), while
  any other `String` or `Bytes` value yields `Option(c.CString)` with `none`
  for an interior NUL, so `using name = try c.CString(text)` composes with
  Option propagation. The `Bytes` form copies exact bytes without a UTF-8
  requirement; a wrong argument count is kind 211 and an argument that is
  neither `String` nor `Bytes` is kind 212. `owner.ptr()` borrows the buffer as `c.ConstPtr(c.Char)`
  without consuming the owner, and a `using` registration releases the
  buffer exactly once. A registered owner that leaves its scope (plain
  return, aggregate or `Option`/`Result` construction, `take` argument, or
  match scrutinee) is disarmed from that scope and owned by the receiver;
- M7.5 resource composition: affine owners transfer into aggregate
  construction (records, enums, `Option`, `Result`, fixed arrays), affine
  scrutinees are consumed as a whole, and parts leave an aggregate only by
  transferring the whole aggregate or registering it with `using`. A `take
  self` method may additionally move its own direct fields out one at a time
  (`return self.field`, `let x = self.field`, or a `take` argument); each such
  move transfers that sub-owner, the whole owner becomes unusable afterwards,
  and every affine field must be moved or registered before exit. A borrowed
  receiver cannot move a field; code 308 names the rejection;
- `Vec(T)` over a `Cleanup` owner: elements enter by transfer through
  `push`/`from_array`, element reads and views are rejected, a vector grows
  only through a plain local binding, and a registration drains every element
  at scope exit;
- record field construction privacy: record fields default to module-private
  and a field is constructible from another module only when marked `pub`
  (diagnostic 309). A public record with any non-`pub` field is therefore an
  opaque-construction boundary, which is how `HostFile` keeps its descriptor
  unforgeable. Field *reads* remain unrestricted in S0; read privacy is a
  recorded gap in ROADMAP.

A binding block may also declare `callback type Name = "spelling" (params)
-> result` for a C function-pointer typedef. Only `unsafe c` may call
`c.CallbackOwner.register(set, clear, wait, target, context)`; it returns
`Option` of a compiler-owned affine owner, copies the C ABI context into
stable owner storage, and its `using` cleanup clears, waits, then frees. A
nonzero clear terminates with status 101. Callbacks from foreign threads are
outside this surface until the ABI/thread slice.

 Inside `unsafe c`, a
`c.callback(name)` argument supplies a nonretained callback for one raw call;
the target must be a top-level, non-generic, noncapturing function with the
bound C ABI signature. Callback values are not first-class Alder values:
outside that argument, `c.callback` is diagnostic 225, a target mismatch is
224, and a non-bare target is 227.

Closures, ordered `Map`/`Set`, modules, `pub`, async, and the 1.0 standard
library are absent.

## Temporary memory and cleanup bridges

S0 exposes the following names only under the **private bootstrap profile**
(request flag `--bootstrap-private` on the `alder` CLI or the matching host
request bit). An ordinary compilation rejects every one of them with a stable
`bootstrap type/operation ... is private to the compiler's bootstrap sources`
diagnostic, because ordinary programs construct values through inferred
storage (M7.3):

```text
__s0_domain_create
__s0_alloc
__s0_domain_mark
__s0_domain_reset
__s0_domain_destroy
__s0_map_create
__s0_buffer_new
__s0_buffer_len
__s0_buffer_append
__s0_buffer_get
__s0_buffer_set
__s0_buffer_slice
```

The same boundary covers the `Domain` and `DomainMark` types, the fixed
`Map(K, V)` type with its `Get`/`Set`/`Remove` operations, `__s0_Error`,
`__s0_Buffer(T)`, `__s0_String`, the `fn main(root: Domain)` entry form, and
since M8 the narrow direct C import `import c name: fn(...) -> T` (header
binding blocks replaced it on the public surface); a parameterless
`fn main() -> I32` remains the ordinary hosted entry. The
profile exists only so `compiler/src/*.al`, `bootstrap/spike/*.al`, and the
test fixtures that still exercise these runtime mechanisms can compile. The
flag itself is not a supported language feature and is removed together with
the bootstrap bridges; ordinary user programs must not depend on it.

These names directly exercise MIR/runtime mechanisms needed by bootstrap
compiler code. They are reserved and must not appear in public 1.0 APIs.

`__s0_Buffer(T)` is a growable plain-value bootstrap buffer with recoverable
initial/growth allocation failure. It is not persistent value-semantic
`Vec(T)`. `__s0_buffer_set(T, buffer, index, value)` mutates the shared backing
slot in place and panics on an out-of-range index; aliases observe the write.
The fixed map has capacity 16 and deliberately narrow key/value rules. Neither
may be standardized by accident.

`using name = expression with CleanupFn` was the MIR callback bridge. Since
M7.5 it is bootstrap-private like the other bridges: an ordinary compilation
rejects it, because the public form is `using name = expression`, which
selects the builtin Table release or the owner's `Cleanup` implementation. It
runs cleanup in reverse order on normal exit, return, failed `try`, and
checked failure in the detecting function.

The Alder-written S0 checker now resolves `CleanupFn` as a nongeneric user
function with exactly one runtime parameter whose concrete type exactly equals
the initializer type and whose result is `Unit`. The binding is lexical. A
cleanup may contain nested blocks and loops, and nested cleanups are supported
outside loops; declaring a cleanup while already inside a loop remains rejected
because that scope could begin repeatedly while active.

## Failure behavior

Recoverable source failures use `Result` and `try`. Checked arithmetic, shift,
index/range, allocation contract, and fixed-map invariant failures clean active
scopes in the detecting function and terminate. They do not fabricate a result
or unwind caller frames.

MIR 3 `alloc.checked` and the private buffer expose recoverable OOM where the
bootstrap compiler specifically needs it. This is implementation evidence for
the 1.0 fallible-allocation contract, not a general S0 allocation API.

### Expression nesting limit

The S0 parser rejects an expression nested deeper than 64 levels with the
normal syntax diagnostic `SYN0001` kind 19. Nesting is counted for parenthesised
expressions, call arguments, index expressions, array literals and match arms,
and separately for the length of a single operator chain, because a chain of
`a + b + c + ...` builds one left-nested node per operator.

The limit exists because the parser, the checker and lowering all recurse over
the same tree. Without it, deeply nested input exhausted the native stack and
killed the compiler with a segmentation fault; the host raises `RLIMIT_STACK` to
64 MiB, which still only reached roughly 150 levels. Rejecting the input keeps
the failure a normal diagnostic instead of a crash. The limit is far above real
source: the deepest expression in `compiler/src` nests 16 unclosed parentheses,
and the longest operator chain on one line is 13 operators.

This limit covers expression nesting only. Block and statement nesting is not
capped, because `parse_block` and `parse_statement` do not thread `depth`; that
is a known gap rather than a deliberate exclusion.

## C bridge

Since M8 the narrow direct C import is part of the private bootstrap
profile (see "Temporary memory and cleanup bridges"):
ordinary modules declare C surface through header binding blocks, and an
ordinary `import c name: fn(...) -> T` is rejected with the stable
bootstrap-private diagnostic. Under the private profile the form still
behaves as follows.

S0 declares one concrete symbol:

```alder
import c note: fn(I64) -> Unit
```

Parameters/results are restricted to primitives and `Ptr(primitive)`. A symbol
is callable only as one direct root call inside `unsafe c`. That one-symbol
form does not read headers, describe records, verify ownership/retention, or
support retained callbacks; exports and retained-callback contracts are the
broader C interop surface described in [C Interoperability](c-interop.md).

## Current Alder-written port boundary

`compiler/src/*.al` is the fixed explicit compiler source root. At the time of
this document split, it contains:

- source/token storage and a lossless lexer;
- a parser for current S0 declarations, expressions, control flow, match, and
  unsafe calls;
- declaration collection and a growing checker for names, generic type shapes,
  aggregate members, representation cycles/restrictions, import/function
  signatures, lexical blocks, assignments, and synchronous `if`/`while`/slice
  `for` control flow. Binding initializers, assignment right-hand sides,
  conditions, sequences, indices, and returns accept recursively nested S0 unary
  and binary operators over parameter/local identifiers, Boolean literals,
  integer literals, and decoded string literals, plus direct calls with
  all-or-none explicit or inferred generic arguments, generic record
  constructors, expected-type generic enum variants, and direct
  imported calls and verified-record field reads and writes inside
  `unsafe c`. Checked bodies also retain exhaustive enum,
  `Option`, and `Result` matches (including expression statements), concrete
  builtin constructors, and exact-error-type `try` records;
- deterministic concrete function specialization closure. Instances are keyed
  by declaration ID and ordered canonical concrete type IDs, registered before
  body checking, and checked in first-discovery FIFO order. Same-instance and
  finite concrete mutual recursion are accepted; a recursive chain whose type
  arguments are proper structural subterms is finite and accepted, while
  specialization-expanding active polymorphic recursion is rejected with
  diagnostic 59 naming the callee;
- private deterministic manifest v14 records used by Go conformance tests. It
  includes a canonical source-span table and stable checker diagnostic
  code/primary/related/note rendering independent of the eventual CLI envelope.

The fixed production entry drives those implemented slices from source loading
through checking, lowering, and complete verification. Failed source phases
produce stable human or version-1 JSON diagnostics derived from their canonical
records; their private manifests remain conformance-test protocols only.
`check` emits no artifact, while `compile` emits MIR or C according to the
shared bootstrap CLI contract. Malformed checked/lowered state, verifier
rejection, and C preflight rejection emit no artifact bytes. This remains a
bootstrap subset, not an Alder 1.0 claim. Its fixed-point source-bootstrap
evidence and regeneration procedure are recorded in the
[Roadmap](../ROADMAP.md) and
[compiler source inventory](../bootstrap/compiler-source-inventory.md).

Integer literal checking keeps the literal as decimal digit text and compares
it against per-type bounds, so the port accepts every `U64` value and the
`I64` minimum instead of inheriting Stage 0's signed host-storage limit.
Quoted literals default to `String`; an expected `Bytes` type preserves the
decoded bytes exactly, including NUL and invalid UTF-8. `\xNN` consumes exactly
two hexadecimal digits. Invalid UTF-8 is rejected only in `String` context.
The operator slice covers unary `-` and `!`, checked integer arithmetic and
shifts, integer comparison and equality, short-circuit Boolean operators, and
the float operators: the six comparisons plus binary `+`, `-`, `*`, and `/` on
same-type `F32`/`F64` operands follow IEEE-754 semantics (decision D026: no
failure edge, signed-infinity overflow, and division by zero defined as the
signed infinity, NaN for 0/0), all with the Go Stage 0 operand rules. Float
`%` and unary minus applied to a float still reject with diagnostics 37 and
31. An `F32`-typed float literal must denote a value the binary32 format
represents exactly: a magnitude beyond `F32`'s range rejects with diagnostic
255, and any other literal rounding would change — including one that lands
on a subnormal or zero — rejects with 256, so the written decimal digits name
the stored value; `F64` literals accept any finite value. Direct calls support concrete and
generic user functions, generic records, variants resolved through a concrete
expected enum, unary-payload inference through declared generic enums, and one
direct C-import root in `unsafe c`; record fields are checked and stored in
declaration order. Inherent methods support ordinary, mutable, and taking
receivers; associated functions and same-named methods on distinct owner types
resolve to distinct concrete symbols. Explicit type arguments are all-or-none
and use the same postfix call tree as runtime arguments. A `MutSlice(T)` binding may be introduced by `let` or `var`: `let` prevents
reassignment of the descriptor but not mutation through the view, and the
binding must still be formed directly by `slice_mut` or `subview`. A
`MutSlice(T)` parameter is mutable through the view whether or not its
declaration repeats `mut`. A `let`-bound view or a newly formed
`slice_mut`/`subview` result satisfies an exclusive-view parameter; a newly
formed view must be the final runtime argument, and taking `slice_mut` or
`subview` still requires a mutable owner binding.

Checked places are chains over one root local:
a name, a field of any place, and a slice index of any place, so `a`, `a.b`,
`a[i]`, `a.b.c`, `a.b[i]`, and `a[i].b` are all assignable. Roots and fields
retain stable semantic IDs, and concrete generic field types are substituted
before checking the right-hand side. A mutating collection or table operation
resolves its receiver the same way, so `b.items.push(x)`, `b.items[i] = x`, a
`Map`/`Set` `insert`/`remove`, and a `Table` operation work through a field of
a local or of a `mut self` receiver, through a nested field path, and through
an element of a field; the grown collection header is written back through
that place. A view taken through a field excludes mutation of the binding that
owns it. Lexical environments do not leak block,
branch, loop, or `for` element bindings. Non-`Unit` functions must return on
every path, statements after a guaranteed return are rejected before their
contents, and conservative loops fall through. `using` cleanup facts cover
lexical fallthrough, return, failed `try`, `break`, and `continue`. Current
lowering walks the checked site environment to run only active callbacks,
exactly once in reverse lexical order, on those exits; a checked failure while
a registration is active runs the registrations it crosses before the process
terminates with status 101. A registration inside a loop body belongs to that iteration's scope, so
it runs at the end of the iteration and on every exit that leaves it, and a
loop-body binding is re-established by each iteration.
Unannotated let/var bindings infer scalar types from supported literals,
identifiers, and unary/binary expressions.

The checked model interns types by kind, semantic target, and ordered canonical
argument IDs. Primitive targets are fixed, repeated applications share one
canonical record, and public `String`, `Bytes`, and `[U8]` retain distinct
identities. The private `__s0_String` bridge alone retains slice-of-`U8`
compatibility for compiler implementation sources. Concrete checked bodies use
stable parameter/local binding IDs, a persistent lexical-environment chain,
postorder expression records, flattened ordered child ranges, and private block,
statement-link, statement, and assignment-place records. The Alder lowering
package consumes these records with canonical Z spans and source bytes, never
parser nodes, links, or kinds. It emits the current scalar, call, aggregate,
place, and structured-control MIR slice or rejects the model without output;
it does not infer types or repair CFG. Generic
function signatures and bodies are owned by stable concrete instance IDs;
direct call targets name those instances. Aggregate applications, expression
types, instance signatures, and checked instance bodies are concrete at this
boundary. Stable annotations retain declaration/variant IDs and canonical
checked types without introducing MIR identities.

Every concrete checked S0 body has exactly one root block, including an
empty `Unit` body. A syntax form outside this supported S0 contract receives one
stable boundary diagnostic; it no longer causes partial body records to be
silently discarded as a successful check. Later Alder 1.0 expressions and
language facilities remain incomplete. Consult [Roadmap](../ROADMAP.md) and
executable tests for the exact implemented boundary.

## Removal gates

Bootstrap bridges are removed when their 1.0 owners exist. Since M7.3 slice 3
they are reachable only under the private bootstrap profile rather than in
ordinary programs:

| Bootstrap construct | Removed after |
|---|---|
| global explicit source namespace | module/build graph works |
| private `__s0_String = [U8]` | compiler byte-oriented internals migrate to M7.1 views under M7.3 storage inference |
| fixed S0 `Map` | standard insertion-ordered `Map` works |
| `__s0_Buffer` | ordinary source `Vec`/builders work |
| explicit `Domain`/`DomainMark` | storage inference is verified |
| callback `using ... with ...` | affine `Cleanup` selection works (the clause is profile-gated since M7.5) |
| direct `import c name` | header binding blocks work (profile-gated since M8; the form remains only for the compiler's own host shims) |
| temporary `main` signatures | project targets and standard host entry work |

S0 remains frozen except for correctness and work needed to reach the
self-hosted compiler. It must not grow into a second permanent language.
