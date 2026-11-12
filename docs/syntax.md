# Alder Surface Syntax

Design status: **Frozen for Alder 1.0**

Availability: **Partially implemented by Alder S0**

Implemented subset: [Alder S0](s0-language.md)

This document defines the intended surface grammar. It deliberately favors one
familiar spelling for each concept. It does not claim that the current parser
accepts every construct.

## Lexical conventions

- Source is UTF-8.
- Core identifiers use `[a-zA-Z_][a-zA-Z0-9_]*`. Unicode identifiers may be
  reconsidered after normalization and tooling rules exist.
- Identifiers beginning with `__` are reserved to the implementation.
- Keywords and names are case-sensitive.
- Types and enum variants conventionally begin with an uppercase letter;
  values, functions, fields, and modules conventionally use lowercase.
- `//` starts a line comment. `/* ... */` is a non-nesting block comment.
- `///` starts a doc comment for the declaration that follows it, or for the
  module when it precedes the `module` header. Doc comments are Markdown; the
  first line is a one-sentence summary. Public declarations require one; see
  [Modules and Builds](modules-and-builds.md#documentation-requirements).
- Semicolons are not part of ordinary Alder syntax.

Physical newlines separate top-level declarations, record fields, enum
variants, statements, and match arms. Commas separate items inside `()`, `[]`,
and explicit import lists. A trailing comma is allowed.

An expression may continue across a newline while enclosed by `()`, `[]`, or
an expression-owned brace construct. A multiline call chain must therefore be
parenthesized rather than relying on a leading dot:

```alder
let names = (
    users
        .filter(active)
        .map(name)
)
```

## Modules and imports

Frozen syntax; not implemented in S0:

```alder
module compiler.parser

import compiler.token
import compiler.syntax as syntax
import compiler.diagnostic { Diagnostic, Range }
```

`module` appears once before imports. `import path` binds the final path
component as a namespace; `as` chooses another namespace; an explicit member
list imports only those names. Wildcard imports are not part of the core.

C uses a separate binding form described in [C Interoperability](c-interop.md):

```alder
import c "stdio.h" as stdio {
    opaque type File = "FILE"
    raw fn close = "fclose"(file: c.Ptr(File)) -> c.Int
}
```

## Visibility and declarations

Declarations are module-private unless prefixed by `pub`:

```alder
pub type User {
    pub name: String
    pub age: U32
    internal_tag: U64
}

pub enum LookupError {
    NotFound(name: String)
    InvalidQuery
}

const default_limit: U64 = 100

pub fn lookup(name: String) -> Result(User, LookupError) {
    // ...
}
```

Top-level declaration forms are:

```text
module, import
type, enum
const
fn
trait
impl
export c fn
test
```

There are no mutable globals or executable top-level initializers. Trait
declarations, `impl Trait(Arguments) for Type` blocks, trait constraints,
and static trait-method dispatch through generic monomorphization are
implemented; closures and async contracts are not implemented in S0 and are
defined in [Traits and Closures](traits-and-closures.md) and
[Async and Structured Concurrency](async.md).

`type Name { ... }` is the single record declaration spelling. Alder does not
also use `struct`. Transparent aliases and opaque newtype syntax are deferred.

Record fields are module-private unless marked `pub`. A public record can be
constructed outside its module only when every required field is public;
private fields therefore provide an opaque-construction boundary. Variants of
a public enum are public as a set so exhaustive matching has one stable
meaning.

## Types

Primitive types:

```text
Bool
I8 I16 I32 I64
U8 U16 U32 U64
F32 F64
Unit
```

There is no platform-sized Alder `Int` or `UInt`.

Core type forms:

```alder
User                    // nominal type
Array(User, 16)         // fixed-size value array
[User]                  // immutable scoped slice
MutSlice(User)          // exclusive scoped mutable slice
Vec(User)               // growable value collection
Map(String, User.Id)    // value map
Set(String)             // value set
Option(User)
User?                   // exact sugar for Option(User)
Result(User, LoadError)
Table(User)
User.Id
fn(User) -> String
```

`Array(T, N)` is the one built-in fixed-array constructor. `N` is a
compile-time `U64` literal or constant. Alder 1.0 does not generalize this into
user-defined const generics or dependent types.

`String` is immutable valid UTF-8. `Bytes` is an immutable arbitrary byte
value. They are not aliases for `[U8]`; S0's narrower representation is a
bootstrap-only rule.

## Records and enums

Records have named fields:

```alder
type Point {
    x: F64
    y: F64
}

let origin = Point(x: 0.0, y: 0.0)
```

Construction names every field exactly once. Written field order is arbitrary;
evaluation follows written order. Default fields and record update syntax are
deferred.

Each enum variant has either no payload or one labeled payload:

```alder
enum Shape {
    Empty
    Circle(radius: F64)
    Rectangle(size: Size)
}

let shape = Circle(2.0)
```

The payload label documents the declaration; construction and patterns use the
single payload position. A record payload is used when a variant needs several
named values. Multi-payload and anonymous-record variant sugar are deferred.

An unqualified variant is accepted only when the expected enum type makes it
unambiguous. Qualification uses `Type.Variant`, for example
`LookupError.NotFound(name)`. When the type comes from another module, the
import's namespace prefix goes before the type: `process.PipeMode.Piped` or
`process.ProcessError.Platform(info)`.

## Compile-time type parameters

`type` is the compile-time metatype. Generic declarations use leading ordinary
parameters whose type is `type`:

```alder
type Pair(A: type, B: type) {
    first: A
    second: B
}

fn identity(T: type, value: T) -> T {
    return value
}
```

Type application and explicit specialization use only parentheses:

```alder
Pair(I64, String)
identity(I64, 42)
```

Angle brackets and square brackets are never generic application syntax.
Callers either omit the complete leading type-argument sequence or provide it
completely. Partial explicit prefixes are rejected.

A static trait constraint is written on the type parameter it constrains, as
the traits listed inside `type(...)` (D024):

```alder
fn sorted(T: type(Order), values: [T]) -> Vec(T) {
    // ...
}

type Index(K: type(Eq, Hash), V: type) {
    entries: Map(K, V)
}
```

`T: type` is unconstrained. A constraint may name any type parameter of the
same list. There is no `where` clause and no `+` between traits. One spelling
rule covers the type surface: lowercase keywords form a kind of type and take
their parts in parentheses (`fn(A) -> R`, `type(Order)`), and capitalized
names are nominal types and traits applied with `Name(...)`. See
[Traits and Closures](traits-and-closures.md).

## Functions and parameters

```alder
fn add(a: I64, b: I64) -> I64 {
    return a + b
}

fn log(message: String) {
    print(message)
}
```

Parameters and non-`Unit` results have explicit types. Omitting the result is
exactly `-> Unit`. Non-`Unit` functions explicitly return on every path. Alder
does not use universal tail-expression returns in the core.

Ordinary parameters receive copyable values. Affine owners are borrowed for
the call by default. Rare ownership and exclusive-access modes are explicit:

```alder
fn inspect(file: File) -> Result(Info, IoError)       // non-retaining borrow
fn update(mut table: Table(User), id: User.Id)       // exclusive call borrow
fn install(take file: File) -> InstalledFile         // ownership transfer
```

`mut` and `take` are limited capability modes, not general reference types.
They do not introduce user-written lifetimes. A call has no extra move marker:
passing an owner to a parameter visibly declared `take` consumes the local;
passing it to an ordinary or `mut` parameter borrows it for that call.

Named arguments are used for record construction, not ordinary function calls.
Default arguments, source-level variadic functions, and overload sets are not
part of the core.

## Bindings and assignment

```alder
let name = "Alder"
let count: U64 = 0
var index: U64 = 0

index = index + 1
point.x = 1.0
items[position] = value
```

- `let` cannot be rebound.
- `var` can be rebound and permits ordinary value-place assignment.
- Both require an initializer.
- Assignment is a statement, never an expression.
- An affine owner cannot be overwritten; it must be consumed, returned, or
  cleaned up explicitly.
- Calling an explicitly mutating owner method does not rebind its local name.

Destructuring bindings are deferred. Pattern bindings exist in `match` and
`if let` arms.

## Literals

Frozen literal forms:

```alder
()
true
false
123
-42
1_000_000
0xff
0b1010
1.5
"hello\n"
"{user.name}: {user.age}"
[1, 2, 3]
```

`()` is the sole value of type `Unit`. It does not introduce general tuple
syntax; records provide named products. A bare `return` returns `()`. The
literal is a value, not a statement: only a `Unit`-result call may stand alone,
so a bare `()` statement is rejected.

Integer literals are arbitrary-precision during checking, adapt to an expected
integer type when representable, and otherwise default to `I64`. The
`-9223372036854775808` form is valid for `I64`; the sign is semantically unary
even if a lexer stores the token compactly. Float literals adapt to `F32` or
`F64` and otherwise default to `F64`.

String interpolation uses `Display`. An array literal `[a, b]` produces
`Array(T, 2)` after checking every element against one type. An empty array
literal requires an expected `Array(T, 0)` type. Arrays and vectors borrow as
`[T]` for a call; constructing an owned vector remains explicit, for example
`Vec.from_array(U64, [1, 2, 3])`. `Vec.new(T)` names the element type when no
value argument can infer it. The exact implemented collection and view calls
are frozen in the [`core.collection`](api/core.collection-v1.md) and
[`core.slice`](api/core.slice-v1.md) snapshots. Raw strings, character
literals, user-defined suffixes, and collection comprehensions are deferred.

## Expressions and precedence

From tightest to loosest:

```text
postfix:         call, field, index
unary:           - ! ~
multiplicative:  * / %
additive:        + -
shift:           << >>
bitwise-and:     &
bitwise-xor:     ^
bitwise-or:      |
comparison:      < <= > >=
equality:        == !=
logical-and:     &&
logical-or:      ||
```

Binary operators are left-associative. Comparisons do not chain. `&&` and
`||` short-circuit. Operator operands have no implicit numeric conversion.
Users cannot define operators or precedence in the core.

## Control flow

```alder
if ready {
    run()
} else if waiting {
    wait()
} else {
    stop()
}

while condition {
    step()
}

for item in items {
    consume(item)
}
```

Conditions are `Bool`; there is no truthiness. `if`, `while`, and `for` are
statements. `break` and `continue` are allowed in loops but carry no values.
There is no C-style three-clause `for`, labeled flow, implicit switch
fallthrough, or `goto`.

## Pattern matching

`match` is an expression and must be exhaustive for algebraic values:

```alder
let name = match result {
    Ok(value) => value.name
    Err(error) => return Err(error)
}
```

Core patterns are:

```text
_                 wildcard
Variant           valueless variant
Variant(name)     one payload binding
true / false      Boolean literal
integer literal   integer literal where implemented
```

Bindings are immutable and scoped to the arm. A wildcard completes
exhaustiveness.

An arm may add an `if` guard after its pattern:

```alder
let label = match response {
    Ok(body) if body.is_empty() => "empty"
    Ok(_) => "ok"
    Err(_) => "failed"
}
```

The guard is a `Bool` expression evaluated after the pattern matches, with the
arm's bindings in scope. When it is false, matching continues with the next
arm. A guarded arm never counts toward exhaustiveness. A guard only borrows the
bindings; it cannot consume an affine payload. Or-patterns, record/slice
destructuring, and range patterns are deferred.

`if let` is exact one-pattern-match sugar:

```alder
if let Some(user) = users.get(id) {
    print(user.name)
}
```

The optional extraction form is also frozen:

```alder
let user = users.get(id)
    else return Err(NotFound(id))
```

The `else` branch must diverge with `return`, `break`, `continue`, or
unrecoverable termination.

`let value = option else ...` extracts by value. It copies a copyable payload.
If `Option(T)` is affine because `T` is affine, it consumes the option and
transfers the payload into `value`; the original option is unavailable after
the statement. In contrast, `if let` is a scoped pattern test and only borrows
an affine payload, which cannot escape its arm.

`while let` repeats a one-pattern match:

```alder
while let Some(message) = try inbox.receive() {
    handle(message)
}
```

Matching an affine enum consumes its owned scrutinee when a payload owner is
extracted. The type makes that consumption visible; Alder does not add a
general `move` expression. Matching a temporary or the result of `try` is the
common resource case.

## Errors and cleanup syntax

```alder
let text = try File.read_text(io, path)
using file = try File.open(io, path)
```

`try` applies only to `Result(T, E)` and propagates the same error type from the
current function. Alder does not use postfix `?` for error propagation because
`T?` already denotes optional types and `try` is explicit.

`using` binds one affine resource and registers its type-defined `Cleanup`
hook. The hook is infallible and consumes the owner; it may suspend when the
owner holds a suspending I/O capability. Cleanup behavior is frozen in
[Memory and Resources](memory-and-resources.md).

There is no general `defer` in the core.

## Methods

Inherent methods are statically resolved and monomorphized:

```alder
impl User {
    fn label(self) -> String {
        return "{self.name}: {self.age}"
    }

    fn rename(mut self, name: String) {
        self.name = name
    }

    fn into_bytes(take self) -> Bytes {
        return encode(self)
    }
}
```

- `self` is a non-retaining read borrow.
- `mut self` is an exclusive call borrow.
- `take self` consumes an affine owner.
- Methods exist only in the owning nominal type's inherent `impl` blocks.
- There are no extension-method searches, runtime lookup, overload sets, or
  method values in the core.

Associated functions omit `self` and are called as `File.open(io, path)` —
with the type named bare or through an import's namespace prefix, as in
`bytes.BytesBuilder.new()`. Opaque
library values and affine owners use named associated constructors such as
`TaskGroup.new()` and `Table.new(Player)`; a type is not implicitly callable
merely because it has no public fields. Record construction remains
`Point(x: 1.0, y: 2.0)` and an empty public record may use `Marker()`.

Trait implementations use `impl Trait(Arguments) for Type`; their static
coherence and supported surface are defined in
[Traits and Closures](traits-and-closures.md).

## Closures and concurrency

Expression and block closures use anonymous `fn` syntax:

```alder
fn(value: I64) => value + 1

fn(user: User) -> String {
    return user.name
}
```

Parameter/result types may be inferred from an expected function type. Ordinary
read captures are value snapshots. Implicit mutable or affine capture is
rejected; see [Traits and Closures](traits-and-closures.md).

There is no `async fn`. Code that waits on the host takes an I/O capability
through an ordinary compile-time type parameter:

```alder
fn fetch(I: type(AsyncIo), io: I, url: Url) -> Result(Bytes, HttpError) {
    using tasks = TaskGroup.new(io)
    let response = tasks.spawn(http.get(io, url))
    let bytes = try await response
    return Ok(bytes)
}
```

The argument of `spawn`, `start`, and the other standard task operations must
be a direct call; it runs as the child task. `await` applies only to a
`Task(T)` handle. Prefix operators compose right-to-left, so `try await task`
awaits first and then propagates its `Result`. Task handles and groups are
affine. There is no detached-task syntax. See
[Async and Structured Concurrency](async.md).

## `unsafe c`

```alder
let raw = unsafe c {
    stdio.fopen(path, mode)
}
```

The block contains one root C operation. The callee names a `raw fn` member
bare, when exactly one binding block declares that member name, or qualified
as `alias.member`. Arguments are evaluated before that operation in source
order. A `Unit`-result call may stand alone as a statement; any other binding
call result must be used. `c.is_null(pointer)` is the one safe observation and
is checked outside `unsafe c` too. `unsafe c` does not disable Alder type
checking and does not make the result safe; validation and encapsulation
happen in the surrounding wrapper. See [C Interoperability](c-interop.md).

## Syntax intentionally absent

The frozen core has no:

- `<T>` or `[T]` generic application;
- implicit return from arbitrary tail expressions;
- postfix error propagation operator;
- implicit truthiness or implicit numeric conversion;
- assignment expressions, `++`, `--`, ternary `?:`, comma operator, or `goto`;
- class syntax, inheritance, or implicit dynamic dispatch;
- general ownership/lifetime annotation language;
- user-defined operator grammar;
- macros or arbitrary compile-time functions returning `type`;
- dynamic trait-object syntax or implementation specialization;
- detached tasks;
- source package/dependency syntax.
