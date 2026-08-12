# Alder S0 Bootstrap Language

Design status: **Bootstrap-only contract**

Availability: **Implemented by the Go Stage 0 frontend; the Alder-written frontend port is incomplete**

This document isolates the implemented bootstrap language from the Alder 1.0
design. A rule in this file is not a permanent language decision unless a 1.0
document also states it.

There are currently two implementation profiles:

- the Go `frontend` package implements the complete Milestone 4 S0 pipeline to
  verified MIR and C11;
- `compiler/src/*.al` is the in-progress Alder port. Its lexer and parser cover
  the current S0 syntax, while its checker and lowering are still partial.

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

enum Maybe(T: type) {
    Some(value: T)
    None
}

fn identity(T: type, value: T) -> T {
    return value
}
```

Generic compile-time parameters must be the leading `type` parameters. Type
application and explicit specialization use `Name(...)`. A call either omits
all type arguments and infers them from runtime arguments/expected result, or
supplies all of them. Monomorphization completes before MIR.

The hosted entry forms are temporarily `fn main() -> I32` and
`fn main(root: Domain) -> I32`. They adapt to the fixed generated C host shim
and are not the 1.0 entry contract.

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
- `String`, currently semantic sugar for `[U8]`;
- `Option(T)` and `Result(T, E)`;
- nominal generic records and zero/unary-payload enums;
- fixed-capacity bootstrap `Map(K, V)`;
- raw `Ptr(T)` for C imports;
- temporary `Domain`, `DomainMark`, `__s0_Buffer(T)`, and `__s0_Error`.

The S0 `String`, map, buffer, domain, and pointer rules are not the 1.0
`String`, `Map`, `Vec`, inferred-storage, or C binding contracts.

Current representation restrictions reject nested lifetime-bearing values in
aggregate storage, infinite value recursion, unsupported map keys/values,
unsupported C signatures, and specialization-expanding polymorphic recursion.
The exact restrictions are pinned by `frontend` acceptance/rejection tests and
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
block
match expression statement
```

`while`/`for` do not yet support `break` or `continue`. Assignment targets are
restricted to the implemented identifier/field/index shapes. Every non-`Unit`
function path returns explicitly.

Implemented expressions include:

- integer, float, Boolean, and string literals;
- unary `-` and `!`;
- checked arithmetic, shifts, comparisons, equality for supported primitives,
  and short-circuit Boolean operators;
- calls, record/variant construction, field access, index and range;
- exhaustive `match` over enums, `Option`, and `Result`;
- prefix `try` with the exact same error type;
- a single direct imported call in `unsafe c { ... }`;
- S0 domain, allocation, buffer, and map intrinsics.

Bitwise source operators, methods, traits, closures, fixed arrays, ordinary
owned vectors, table identity, modules, `pub`, async, and the 1.0 standard
library are absent.

## Temporary memory and cleanup bridges

S0 exposes:

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
__s0_buffer_slice
```

These names directly exercise MIR/runtime mechanisms needed by bootstrap
compiler code. They are reserved and must not appear in public 1.0 APIs.

`__s0_Buffer(T)` is a growable plain-value bootstrap buffer with recoverable
initial/growth allocation failure. It is not persistent value-semantic
`Vec(T)`. The fixed map has capacity 16 and deliberately narrow key/value
rules. Neither may be standardized by accident.

`using name = expression with CleanupFn` reflects the current MIR callback
bridge. It runs cleanup in reverse order on normal exit, return, failed `try`,
and checked failure in the detecting function. The 1.0 form is
`using name = expression`, selected by `Cleanup`.

## Failure behavior

Recoverable source failures use `Result` and `try`. Checked arithmetic, shift,
index/range, allocation contract, and fixed-map invariant failures clean active
scopes in the detecting function and terminate. They do not fabricate a result
or unwind caller frames.

MIR 3 `alloc.checked` and the private buffer expose recoverable OOM where the
bootstrap compiler specifically needs it. This is implementation evidence for
the 1.0 fallible-allocation contract, not a general S0 allocation API.

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
  signatures, and only a narrow initial function-return body slice;
- private deterministic manifests used by Go conformance tests.

General body checking, all literals/expressions, inference, monomorphization,
MIR construction, verifier/backend ports, and self-hosted execution are still
incomplete. Consult [Roadmap](../ROADMAP.md) and executable tests for the exact
latest slice.

## Removal gates

Bootstrap bridges are removed when their 1.0 owners exist:

| Bootstrap construct | Removed after |
|---|---|
| global explicit source namespace | module/build graph works |
| `String = [U8]` | owned UTF-8 `String` and views work |
| fixed S0 `Map` | standard insertion-ordered `Map` works |
| `__s0_Buffer` | ordinary source `Vec`/builders work |
| explicit `Domain`/`DomainMark` | storage inference is verified |
| callback `using ... with ...` | affine `Cleanup` selection works |
| direct `import c name` | header binding blocks work |
| temporary `main` signatures | project targets and standard host entry work |

S0 remains frozen except for correctness and work needed to reach the
self-hosted compiler. It must not grow into a second permanent language.
