# Aster Language Design

Status: exploratory design draft

This document describes the intended user-facing model. It is not yet a normative language specification. Examples illustrate design direction and may change as MIR and runtime experiments expose constraints.

## Goals

Aster aims to combine:

- memory safety without tracing garbage collection;
- predictable native performance;
- direct and explicit C interoperability;
- deterministic cleanup of external resources;
- modern algebraic types, pattern matching, generics, and structured concurrency;
- syntax that does not routinely expose per-object ownership or lifetime machinery.

## Non-Goals

Aster does not initially attempt to provide:

- immediate reclamation for every arbitrary object graph;
- safe, unchecked access to arbitrary C APIs;
- implicit shared mutable state across tasks;
- hidden reference counting as a universal escape mechanism;
- a user-visible choice among many allocators in ordinary code;
- compatibility with every C undefined or implementation-defined behavior.

## Safety Boundary

Safe Aster code should prevent:

- null dereferences;
- out-of-bounds access;
- use after free;
- stale identity resolving to a different object;
- double cleanup of scoped resources;
- data races between structured tasks.

Operations involving raw C pointers, unverified external lifetime contracts, or arbitrary foreign mutation require an explicit `unsafe c` boundary. Safety outside that boundary depends on the wrapper correctly validating and encapsulating the result.

## Ordinary Values

Ordinary data uses value semantics:

```aster
type User {
    name: String
    age: Int
}

let user = User(name: "Lin", age: 24)
let label = "{user.name}: {user.age}"
```

The surface language does not invalidate a variable merely because its value was passed or assigned. Implementations may elide copies, construct directly in a destination, or share immutable representation when the observable semantics remain unchanged.

Cross-domain copies must be measurable by compiler diagnostics or profiling. The implementation must not silently introduce unbounded graph copies as a general escape strategy.

## Compile-Time Type Values and Generics

`type` is the compile-time metatype of Aster types. A concrete type is a compile-time value whose type is `type`:

```aster
Int: type
String: type
```

A generic type declaration is a type constructor. It accepts leading `type` parameters and produces a concrete type:

```aster
type Pair(A: type, B: type) {
    first: A
    second: B
}

Pair: fn(type, type) -> type
Pair(Int, String): type
```

Type application uses the same parenthesized application syntax as function calls:

```aster
let pair: Pair(Int, String)
let users: Table(User)
let result: Result(User, IoError)
```

Aster does not use angle brackets or square brackets for generic application. Built-in sequence syntax such as `[User]` remains dedicated syntax rather than generic application.

Generic functions declare compile-time type parameters in the ordinary parameter list, before runtime parameters:

```aster
fn identity(T: type, value: T) -> T {
    return value
}

fn map(
    A: type,
    B: type,
    values: [A],
    transform: fn(A) -> B,
) -> [B] {
    var result: [B]

    for value in values {
        result.push(transform(value))
    }

    return result
}
```

A call may omit the complete leading sequence of type arguments when all of them can be inferred from runtime arguments and the expected result type:

```aster
let number = identity(42)
let names = map(users, fn(user) => user.name)
```

When inference is insufficient or the caller wants an explicit specialization, type values are passed as ordinary leading compile-time arguments:

```aster
let number = identity(Int, 42)
let names = map(User, String, users, fn(user) => user.name)
```

The initial language does not support partially supplying an inferred type-argument prefix. A later placeholder syntax may be considered only if real programs demonstrate the need.

Traits are intended to refine `type` rather than introduce a separate generic parameter grammar. If `Ordered` is a trait, `T: Ordered` means that `T` is a compile-time type value satisfying that constraint:

```aster
fn max(T: Ordered, a: T, b: T) -> T {
    if a.compare(b) == .greater {
        return a
    }

    return b
}
```

Trait semantics are not required for the initial bootstrap subset, but this constraint model is reserved by the generic syntax.

Type values are erased before executable MIR. Type inference and monomorphization produce concrete `TypeId` values, concrete functions, and concrete layouts before the C backend runs. `type` does not imply runtime reflection or a runtime type descriptor; explicit runtime reflection, if added later, uses a separate `TypeInfo` value.

The initial language also does not allow arbitrary user functions to synthesize and return `type`. Generic declarations are sufficient for the first type-construction model and avoid requiring a general compile-time interpreter or dependent type system.

## Hierarchical Storage Domains

Functions, loops, task groups, requests, and selected containers establish hierarchical storage domains. The compiler places an allocation in the smallest domain proven to outlive all of its uses.

```aster
fn summarize(data: Bytes) -> Result(Summary, Error) {
    let document = try Json.parse(data)
    let words = document["content"].as_string().words()

    return Summary(
        title: document["title"].as_string().to_string(),
        word_count: words.count(),
    )
}
```

The JSON tree and iterator are temporary. The returned `Summary` is constructed in caller-provided result storage. On return, the temporary domain is reclaimed in bulk.

If analysis cannot prove a shorter lifetime, storage is placed in a statically enclosing domain. The fallback is bounded retention, not an unchecked dangling reference.

### Segmented Domains

A domain may contain multiple segments:

- resettable segments for loop iterations or compiler phases;
- independent segments for large allocations;
- result segments whose lifetime is selected by the caller;
- container segments that can be incrementally rebuilt.

Segmentation mitigates the traditional arena problem where one small surviving object retains unrelated large temporary allocations. It does not claim perfect individual reclamation.

## Objects with Identity

Long-lived objects that require stable identity and independent insertion or removal live in `Table(T)`:

```aster
type Player {
    name: String
    health: Int
    target: Player.Id?
}

let players = Table(Player)()
let alice = players.insert(Player(name: "Alice", health: 100))
let bob = players.insert(Player(name: "Bob", health: 80, target: alice))
```

`Player.Id` contains a table identity, slot, and generation. Removing an object invalidates existing IDs. Reusing the slot increments its generation, so an old ID cannot resolve to the new value.

```aster
players.remove(alice)

if let player = players[alice] {
    // This block is not entered.
}
```

Table access produces a scoped view. A view cannot be stored beyond the operation during which the table guarantees its validity. Ordinary code should encounter this rule through natural access scopes rather than explicit lifetime parameters.

Graphs use IDs rather than persistent interior addresses:

```aster
type Node {
    label: String
    edges: [Node.Id]
}
```

Cycles do not affect reclamation because IDs do not count references. The table determines which objects exist.

## Scoped Resources

External resources use deterministic lexical cleanup:

```aster
fn copy(from: Path, to: Path) -> Result(Unit, IoError) {
    using input = try File.open(from)
    using output = try File.create(to)

    try input.copy_to(output)
}
```

Cleanup runs in reverse registration order on normal return, error propagation, panic recovery where supported, and task cancellation. The exact interaction with unrecoverable process termination remains outside the guarantee.

## Errors and Optional Values

Aster uses explicit algebraic values rather than hidden exceptions and null:

```aster
enum LoadError {
    NotFound(path: Path)
    InvalidFormat(line: Int)
}

fn load(path: Path) -> Result(Config, LoadError) {
    let text = try File.read_text(path)
    return try Config.parse(text)
}
```

Optional values use `T?` and are handled with `if let`, `match`, or `else`:

```aster
let user = users.find(id)
    else return Err(NotFound(id))
```

## Structured Concurrency

Child tasks normally cannot outlive their lexical task group:

```aster
let reports = try taskgroup scans {
    for path in paths {
        scans.spawn {
            try await scan_file(path)
        }
    }

    return try await scans.results()
}
```

The group completes only after children finish or are cancelled and cleaned up. This bounds task-local storage and permits safe access to immutable parent data without per-value ownership transfer.

A detached task creates an independent domain. Captured immutable values may require a cross-domain copy, which must be visible in tooling. Mutable local views cannot be detached.

## C Interoperability

C headers are intended to be importable with C ABI layout and calling conventions:

```aster
import c "fastwords.h" as fastwords

fn count_words(bytes: Bytes) -> Result(Int, WordError) {
    let result = unsafe c {
        fastwords.fastwords_count(bytes.ptr, bytes.len)
    }

    if result < 0 {
        return Err(WordError(result))
    }

    return Ok(result)
}
```

The initial C backend may delegate difficult target-specific declarations to the system C compiler, but the Aster frontend still needs enough imported type information to type-check safe wrappers.

Foreign functions that retain pointers require explicit pin, copy, or foreign-owner wrappers. A temporary domain reference must never be passed under a contract that permits retention after the call.

## Example: Document Index

```aster
type Document {
    path: Path
    title: String
    links: [Document.Id]
}

type Index {
    documents: Table(Document)
    by_path: Map(Path, Document.Id)
}

async fn build_index(paths: [Path]) -> Result(Index, Error) {
    let scanned = try taskgroup scans {
        for path in paths {
            scans.spawn {
                using file = try File.open(path)
                let source = try file.read_text()
                return try Markdown.scan(path, source)
            }
        }

        return try await scans.results()
    }

    var index = Index(
        documents: Table(Document)(),
        by_path: Map(Path, Document.Id)(),
    )

    for item in scanned {
        let id = index.documents.insert(Document(
            path: item.path,
            title: item.title,
            links: [],
        ))
        index.by_path[item.path] = id
    }

    for item in scanned {
        let id = index.by_path.get(item.path) else continue
        let links = item.link_paths
            .filter_map { path => index.by_path.get(path) }
            .collect()

        index.documents.update(id) { document =>
            document.links = links
        }
    }

    return Ok(index)
}
```

The scan tasks release file contents and parser data when each task domain ends. Intermediate scan results live through index construction. Documents are constructed in table storage and linked through stable IDs.

## Milestone 4 Bootstrap Subset (Aster S0)

Status: normative for the implemented Go Stage 0 frontend

M4 defines the smallest source surface that can still exercise every backend
mechanism end to end. Everything below is implemented by the `frontend` Go
package: deterministic source text -> fully typed and monomorphized program
-> verified MIR 1 -> C11. Everything not listed here is rejected with a
diagnostic, never silently ignored.

### Modules and compilation units

A module is one source file containing, in any order:

- `import c <name>: fn(<params>) -> <result>` declarations (one per line);
- `type` and `enum` declarations;
- `fn` declarations.

All names are module-global; there are no namespaces, packages, or separate
compilation units. Source identifiers use `[a-zA-Z_][a-zA-Z0-9_]*`; dots and
other punctuation are reserved for the grammar. The frontend reserves nothing
else: generated MIR entities use dotted names such as `map.get.I64.I64`,
which source identifiers cannot spell.

The compilation pipeline is: lex -> parse (AST) -> typecheck with inference
and monomorphization (typed AST) -> deterministic MIR emission -> the
`mir/verify` gate -> the `cgen` C11 backend. Type inference and
monomorphization complete before any backend MIR exists. MIR is never
repaired: a program whose lowered MIR fails verification is a frontend bug.

### Types

Primitives: `Bool`, `I8`, `I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`,
`F32`, `F64`, `Unit`. There are no implicit conversions; every adaptation is
explicit in the type rules below.

Composite types:

- `[T]` is a slice of `T`; `String` is sugar for `[U8]`;
- `Option(T)` and `Result(T, E)` are the built-in enum-like types with
  implicit variants `None`/`Some(T)` and `Ok(T)`/`Err(E)`;
- `Map(K, V)` is the built-in open-addressed hash map (fixed capacity 16);
- `Domain` is a storage-domain handle; `Ptr(T)` is a raw C pointer usable
  only at FFI boundaries;
- `type Name(A: type, B: type) { f: A; g: B }` declares a generic struct;
  `enum Name(T: type) { V, W(T) }` declares a generic enum. Non-generic
  declarations omit the parameter list.

Type application uses parenthesized syntax like calls: `Pair(I64, String)`
is a type. The checker resolves `Name(...)` by the callee's kind: a type
constructor application, a function call, a struct construction, or an enum
variant construction. Struct construction is positional and must cover every
field in declaration order. Enum variants carry at most one payload; a
variant with several payloads is rejected.

Restrictions (each with a diagnostic):

- struct fields, enum payloads, and slice element types are plain value
  types; slices and references may not be nested in them (`[String]` is
  rejected) because MIR 1 forbids lifetime-bearing stores through dereference
  places;
- value-type recursion (direct or indirect, including through `Option`) is
  rejected as an infinite layout;
- `Map` keys must be unsigned integers, `Bool`, or structs/enums composed of
  those, so hashing and equality are defined structurally; signed and float
  keys are rejected;
- `Map` values must be copy-trivial (no nested slices, strings, or
  references);
- `Alloc(T, d, n)` results are mutable references: they support `len`,
  indexing, ranges, and iteration, and their elements may be assigned, but
  they may not be passed where a `[T]` parameter is required;
- `Ptr(T)` values may only be FFI results, FFI arguments, and function
  results;
- a full map has no growth: `Set` on a full map fails the function;
- domains always have a parent: `Domain(p)` creates a child of `p`, and a
  root domain comes from the environment (the C driver in tests);
- domain marks may not be bound to `let`/`var`; `Reset(d, Mark(d))` uses the
  mark directly, because MIR 1 requires the reset mark to be the direct
  `domain.mark` result;
- function-typed values are not part of the subset (no higher-order
  functions);
- strings compare by length and bytes only; `==` on strings is rejected
  (MIR 1 has no structural comparison).

### Expressions

- literals: integers (decimal, default `I64`), floats (default `F64`),
  `true`/`false`, strings (bytes, `\n \t \r \\ \" \0` escapes);
- integer and float literals adapt to an expected numeric type and are
  range-checked; `-9223372036854775808` is accepted as `I64` minimum;
- unary `-` (checked subtraction from zero; not on unsigned), unary `!`;
- binary `+ - * / % << >>` (checked, same-type operands; `%` is the
  truncating remainder and fails exactly when division fails), comparisons
  `== != < <= > >=` on same-type integers or same-type floats, and
  short-circuit `&&` / `||` on `Bool`;
- bitwise operators are absent from the subset (documented MIR gap);
- `len(x)` (slice length, `U64`), `x[i]` (checked index, `U64`; out of
  bounds fails the function with a zero result value, the MIR 1 fail-edge
  convention), `range(x, lo, hi)` (checked bounds, same failure semantics);
- calls: user functions, builtins, and imports; generic calls may supply the
  leading compile-time type arguments explicitly (`identity(I64, 3)`) or
  omit them when the remaining runtime arguments infer them
  (`identity(3)`);
- field access `e.f` and indexing `e[i]` on any expression;
- struct construction `Name(args)`; variant construction `Variant` or
  `Variant(arg)` where the variant name resolves against the expected enum
  type (`Some(3)`, `None`, `Ok(v)`, `Err(e)`, `Circle(5)`);
- `match e { V(x) => expr, V => expr, _ => expr }` is an expression; arms
  must cover every variant or include `_`; every arm has one type;
- `try expr` inside a function returning `Result(A, E)`: on `Err(e)` the
  function fails with `Err(e)`; the error type must match `E` exactly;
- builtins: `Domain(p)`, `Mark(d)`, `Reset(d, m)`, `Destroy(d)`,
  `Alloc(T, d, n)`, `Map(K, V)(d)`, `Get(m, k)`, `Set(m, k, v)`,
  `Remove(m, k)`.

`if` / `else`, `while`, and `for x in xs` (over slices, `x` is an element
copy) are statements; `for` and `while` have no `break` or `continue`.
`match` may also appear as an expression statement. Other pure expressions
as statements are rejected. Checked operations (arithmetic, shifts, indexes,
ranges) that fail at runtime fail the current function with a zero value of
its result type; the fail value is a diagnostic convention, and the MIR 1
text format requires the result type to be materializable as a zero value,
so functions whose result contains slices, references, or maps cannot
contain checked operations.

### Variables and places

- `let x: T = e` declares an immutable binding (annotation optional when the
  initializer's type is inferable); `var x: T = e` declares a mutable one;
- `x = e` reassigns a `var` (also `x.f = e`, `x[i] = e`, `x[i].f = e`);
  `let`-bound names and enum payload bindings are immutable;
- every block of a function must return on all paths (the final statement
  must be `return`, an `if`/`else` whose branches both return, a `match`
  whose arms all return, or a block ending in one); a `Unit` function may
  fall off the end.

### Scoped cleanup

`using x = expr with CleanupFn` registers cleanup on a value: the
`CleanupFn` must take exactly one parameter of the expression's type and
return `Unit`. The frontend opens a scope at the `using` statement and
emits `Run` + `End` before every subsequent exit (return or failed `try`),
in reverse registration order, on exactly the paths that opened the scope.
This is the only cleanup surface in the subset: MIR 1 requires cleanup
handles to have direct instruction-result SSA identity, so they cannot
cross source-level bindings, and the low-level scope API is not exposed.
`using` inside a loop is rejected (a scope cannot re-begin while active).

### C FFI

`import c strlen: fn(Ptr(U8)) -> U64` declares a C symbol with a concrete
signature; the name is the C symbol. FFI parameter and result types are
restricted to primitives and `Ptr(T)`. Calls lower to `ffi.call.unsafe`
with the backend's symbol-safety checks.

### Diagnostics and acceptance boundary

All diagnostics are deterministic, carry line and column, and are pinned by
rejection tests. The frontend rejects (non-exhaustive list): syntax errors;
unknown names and variants; type mismatches; non-matching `try` error
types; wrong `using` callbacks; mutating immutable bindings; out-of-range
literals; non-exhaustive `match`; fall-through on non-`Unit` functions;
`Map` key/value violations; nested-slice types; value-type cycles;
unsupported FFI signatures; and every restriction listed above. Programs
that type-check lower to MIR that must pass `mir/verify` unchanged.

Acceptance evidence for M4: accept fixtures with pinned printed-MIR goldens,
rejection fixtures with pinned diagnostics, end-to-end source-to-C11
compile-and-run programs under the strict warning set, and in-process and
cross-process determinism checks.

## Open Design Questions

1. What is the smallest useful storage-domain inference algorithm for the bootstrap subset?
2. Which cross-domain value operations are semantic copies, and which are implementation optimizations?
3. How should table views interact with nested mutation and concurrent access?
4. What cleanup guarantees apply to panic and cancellation during cleanup itself?
5. Which C layouts, bit-fields, variadic calls, and callbacks are supported initially?
6. How should detached task capture costs be constrained and reported?
7. Which bounds and overflow checks may be removed by MIR verification or optimization?

These questions should be resolved through MIR definitions and executable fixtures before surface syntax is treated as stable.
