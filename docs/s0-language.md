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

Neither profile is a usable Alder 1.0 compiler.

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

Milestone 7.5 adds the static trait surface of
[Traits and Closures](traits-and-closures.md) up to constraint gating:

- `trait Name(Params) where ... { ... }` declares a trait. Method
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
- `where Param: Trait + Trait, ...` constraints may follow function,
  record, enum, and trait signatures. Constraint arguments resolve in the
  declaration's scope.
- The builtin standard traits `Eq`, `Hash`, `Iterator(Item)`,
  `IntoIterator(IteratorType, Item)`, and `Cleanup` exist
  without source declarations; `Order`, `Display`, and `Error` are reserved
  names without implementations until their APIs are designed with the
  standard library.
- Coherence holds per compilation unit: exactly one implementation may exist
  for a concrete trait application. Orphan-rule enforcement across a package
  graph waits for the module system.
- Instantiating a constrained generic function requires an implementation for
  every constraint; the lookup uses one impl index built after collection.
  The coherence key is the concrete (trait, implementing type, trait
  arguments) combination.
- Every implementation is validated: required methods must be present with
  exactly the trait's receiver mode, runtime arity, and substituted
  parameter/result types, and impl methods that match no requirement are
  rejected. Generic impl methods are not supported yet; defaulted methods
  are materialized as ordinary impl methods and dispatch statically.
- Structural `Eq` and `Hash` implementations are synthesized by the
  language for unsigned integers, `Bool`, `String`, `Bytes`, and
  non-generic records and enums whose every component supports them, so
  `where K: Eq + Hash` accepts those types. Per
  [Traits and Closures](traits-and-closures.md), "A type cannot override
  structural `==` with a surprising user implementation": user `impl Eq`
  and `impl Hash` blocks are rejected. The synthesized methods are not
  directly callable yet; they become callable with the ordered collections.
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
  or another `mut` parameter forwarding the cursor. A `let`-bound copyable
  argument is rejected, because the callee would advance a discarded copy.

Closures and function values are partially implemented as Milestone 7.5
work in progress:

- `fn(A, B) -> R` is a checked function type usable in annotations,
  parameters, results, and bindings. A named non-generic function in value
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
  Affine owners and scoped capabilities (slices and views) are still
  rejected. The thunk ABI is `(declared parameters, opaque
  environment pointer)`; capture-free closures are plain function values.
- A literal nested inside another literal captures transitively: the outer
  environment carries every value the inner body reads, including values the
  outer literal never reads itself. An outer literal whose body nests another
  literal records the domain that owns its environment in the record, and its
  thunk allocates the inner environment in that domain. Closure creation
  inside a `while` loop is carried by the immutable environment snapshot.
- Known limits of this slice: parameter type inference from the expected
  function type is not implemented; malformed closure shapes are rejected
  with diagnostic 147; capturing a scoped capability (a slice or view) is
  rejected with diagnostic 145 until escape-proving capture lands, and a
  closure with no captures whose body allocates storage still needs an
  environment domain.

Default-method dispatch and trait-backed collections are not implemented yet
and remain later Milestone 7.5 work.

The hosted entry forms are temporarily `fn main() -> I32` and
`fn main(root: Domain) -> I32`. They adapt to the fixed generated C host shim
and are not the 1.0 entry contract. The `root: Domain` parameter form is
available only under the private bootstrap profile (see below); ordinary
programs always use the parameterless form and receive the hidden root
domain through inferred storage.

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
if / else
while
for name in slice
return
using name = value with cleanup_function
using name = value
block
match expression statement
```

The second `using` form is the M7.5 public surface: it accepts a `Table(T)`
owner (registering the builtin release), any affine nominal type implementing
`Cleanup` (registering its trait method), or a `Vec(T)` of `Cleanup` owners
(registering a per-element drain). The `with cleanup_function` clause stays
the bootstrap-private bridge.

`break` and `continue` jump to the exit and the next iteration of the
innermost enclosing loop; `continue` in a `for` still runs the index step, and
both are rejected outside a loop, in a closure body, and in a table-view match
arm. A `using` registration inside a loop body is rejected, so neither jump can
cross a cleanup scope. Assignment targets are restricted to the implemented
identifier/field/index shapes. Every non-`Unit` function path returns
explicitly.

Implemented expressions include:

- integer, float, Boolean, string/bytes, and fixed-array literals;
- unary `-` and `!`;
- checked arithmetic, shifts, comparisons, equality for supported primitives,
  and short-circuit Boolean operators;
- calls, record/variant construction, field access, index and range;
- exhaustive `match` over enums, `Option`, and `Result`, including statement
  arms (`=> { ... }`) whose bodies may hold ordinary statements, and `if`
  guards: the guard runs after the pattern matches, a false guard continues
  with the next arm, a guarded arm never counts toward exhaustiveness, and a
  guard only borrows its bindings (kinds 148 and 149);
- prefix `try` with the exact same error type;
- a single direct imported call in `unsafe c { ... }`;
- M7.5 table identity: `Table(T)` over concrete copyable elements,
  `Table.new(T)`, `t.insert(value) -> T.Id`, `t.remove(id) -> Bool`, and
  `t.get(id)`/`t.get_mut(id)` consumed only as a match scrutinee, where the
  `Some` arm binds a scoped view usable for field reads (and field writes
  through `get_mut`) inside a straight-line fail-free arm body;
- the callback-free `using name = Table.new(T)` registration, whose owner is
  cleanup-covered at every exit and disarmed on transfer;
- M7.5 resource composition: affine owners transfer into aggregate
  construction (records, enums, `Option`, `Result`, fixed arrays), affine
  scrutinees are consumed as a whole, and parts leave an aggregate only by
  transferring the whole aggregate or registering it with `using`;
- `Vec(T)` over a `Cleanup` owner: elements enter by transfer through
  `push`/`from_array`, element reads and views are rejected, a vector grows
  only through a plain local binding, and a registration drains every element
  at scope exit.

Bitwise source operators, closures, ordered `Map`/`Set`, modules, `pub`,
async, and the 1.0 standard library are absent.

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
`__s0_Buffer(T)`, `__s0_String`, and the `fn main(root: Domain)` entry form;
a parameterless `fn main() -> I32` remains the ordinary hosted entry. The
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

S0 declares one concrete symbol:

```alder
import c note: fn(I64) -> Unit
```

Parameters/results are restricted to primitives and `Ptr(primitive)`. A symbol
is callable only as one direct root call inside `unsafe c`. S0 does not read
headers, describe records, verify ownership/retention, export Alder functions,
or support retained callbacks. See [C Interoperability](c-interop.md).

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
  imported calls inside `unsafe c`. Checked bodies also retain exhaustive enum,
  `Option`, and `Result` matches (including expression statements), concrete
  builtin constructors, and exact-error-type `try` records;
- deterministic concrete function specialization closure. Instances are keyed
  by declaration ID and ordered canonical concrete type IDs, registered before
  body checking, and checked in first-discovery FIFO order. Same-instance and
  finite concrete mutual recursion are accepted; specialization-expanding
  active polymorphic recursion is rejected;
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
shifts, integer/float comparison and equality, and short-circuit Boolean
operators with the Go Stage 0 operand rules. Direct calls support concrete and
generic user functions, generic records, variants resolved through a concrete
expected enum, unary-payload inference through declared generic enums, and one
direct C-import root in `unsafe c`; record fields are checked and stored in
declaration order. Inherent methods support ordinary, mutable, and taking
receivers; associated functions and same-named methods on distinct owner types
resolve to distinct concrete symbols. Explicit type arguments are all-or-none
and use the same postfix call tree as runtime arguments. Checked places cover mutable locals and
struct fields plus slice indices and indexed struct fields; roots and fields
retain stable semantic IDs, and concrete generic field types are substituted
before checking the right-hand side. Lexical environments do not leak block,
branch, loop, or `for` element bindings. Non-`Unit` functions must return on
every path, statements after a guaranteed return are rejected before their
contents, and conservative loops fall through. `using` cleanup facts cover
lexical fallthrough, return, and failed `try`. Current lowering walks the
checked site environment to run only active callbacks, exactly once in reverse
lexical order, on those exits. The declaration is rejected anywhere under a
loop.
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
| direct `import c name` | header binding blocks work |
| temporary `main` signatures | project targets and standard host entry work |

S0 remains frozen except for correctness and work needed to reach the
self-hosted compiler. It must not grow into a second permanent language.
