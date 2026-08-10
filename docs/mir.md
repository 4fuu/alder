# Aster MIR

Status: versioned contract with a working Go toolkit

Aster MIR is the typed, source-independent contract between semantic analysis and code generation. The `mir` Go package implements the in-memory representation, the deterministic textual printer and parser, and the type inference shared by the parser and the verifier. The verifier lives in `mir/verify`.

MIR must express Aster semantics without depending on C syntax or a future native backend. The C11 backend is a consumer, not the definition, of MIR.

## Design Requirements

MIR must be:

- typed;
- deterministic to print and parse;
- explicit about control flow and side effects;
- explicit about storage domains and cleanup;
- verifiable before code generation;
- suitable for direct, conservative lowering to C11;
- independent of LLVM concepts;
- expressive enough for future self-hosting.

## Structural Model

A module contains:

- type declarations;
- imported C declarations;
- constants;
- functions;
- optional source-span tables (reserved; attachment arrives with the frontend).

A function contains:

- typed parameters (registered as the leading function values);
- local slots;
- basic blocks;
- SSA-like temporary values;
- block parameters rather than implicit phi nodes;
- exactly one terminator per block.

Mutable language variables lower to explicit places and stores. Pure computed temporaries are single-assignment values. Aster has no MIR `move` operation that invalidates a source value.

Values are defined by function parameters, block parameters, instruction results, and switch case payload bindings. A value may be used only where its definition dominates the use (see Verifier Phases). Calls and FFI calls whose result type is `unit` may be left unbound; every other producing operation must bind its result.

## Generic Boundary

Surface and HIR generic declarations use compile-time `type` values and parenthesized type application such as `Table(User)` and `Result(User, Error)`. Type inference and monomorphization occur before backend MIR is produced.

Executable MIR contains:

- no `type` values or type-valued parameters;
- no unresolved generic function bodies;
- no runtime type arguments introduced solely for generics;
- only canonical concrete `TypeId` values, concrete layouts, and concrete function instances.

Parameterized MIR type notation also uses parentheses. Angle brackets and square brackets are not generic application syntax in either surface examples or textual MIR.

## Identity and Ordering

Compiler objects use stable numeric IDs:

```text
TypeId
FunctionId
ImportId
BlockId
ValueId
LocalId
DomainId      (reserved)
CleanupId     (reserved)
SpanId        (reserved)
```

`DomainId`, `CleanupId`, and `SpanId` are reserved parts of the identity vocabulary and are not yet used by operations. Printed ordering must not depend on host-language map iteration, pointer values, allocation addresses, or traversal races. Within a function, value IDs are assigned in textual or construction order: function parameters, then per block in order its parameters, instruction results, and switch case bindings.

## Initial Type Vocabulary

```text
unit
bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
aggregate(TypeId)
enum(TypeId)
option(TypeId)
result(TypeId, TypeId)
slice(TypeId)
safe_ref(TypeId)
safe_mut(TypeId)
raw_ptr(TypeId)
function(Signature)
domain_handle
domain_mark
cleanup_scope
cleanup_id
table(TypeId)
id(TypeId)
table_view(TypeId)
table_mut_view(TypeId)
```

The canonical primitives occupy fixed `TypeId` slots 0 through 11 in every module. Named aggregates and enums are table entries; anonymous structural types are interned by shape, so identical textual types share one `TypeId`. The singleton types (`domain_handle`, `domain_mark`, `cleanup_scope`, `cleanup_id`) each intern to one entry.

`safe_ref(T)` and `safe_mut(T)` are checked references associated with a valid storage or table access scope. `raw_ptr(T)` may only be produced or consumed by operations explicitly marked unsafe or by narrowly defined runtime intrinsics. Strings are `slice(u8)` at the MIR level.

The exact string and dynamic-array representations belong to the runtime ABI, not the semantic type system.

## Places and Values

A place identifies mutable storage:

```text
local %name
field place, field_name
deref checked_reference_value
```

`deref` accepts `safe_ref`, `safe_mut`, `table_view`, and `table_mut_view` values. A place is mutable when it is a local, a field of a mutable place, or a deref of a `safe_mut` or `table_mut_view`; derefs of `safe_ref` and `table_view` are read-only.

The initial vocabulary has no unchecked index place. Checked element access uses `slice.index.checked`, which yields a checked reference that `deref` places consume.

A value is an immutable result of an instruction. `load` reads a place and produces a value; `store` writes a value into a place and does not invalidate other source-level names. Unsafe raw-pointer dereference is never represented as an ordinary safe place.

## Control Flow

Terminators:

```text
jump block(arguments...)
branch condition, then_block, else_block
switch value { cases..., default? }
return [value]
fail value
unreachable
```

- Block arguments must exactly match target block parameter types.
- A switch dispatches on an enum-like value: a declared enum, an option (`none`, `some`), or a result (`ok`, `err`). A case may bind the variant payload as a new value; the case `default` (represented as a case with an empty variant name) is allowed at most once. A switch must cover every variant of its operand type or contain a default case.
- `return` and `fail` both exit with a value of the function's result type; `fail` marks the failure path. A `return` without an operand returns `unit`.
- `unreachable` is valid only in blocks that are unreachable from the entry block. Reachable blocks must not terminate with `unreachable`.
- Every statement starts a new line; the parser rejects statements that do not.

## Storage-Domain Operations

```text
domain.create parent -> domain_handle
domain.mark domain -> domain_mark
domain.reset domain, domain_mark
domain.destroy domain
alloc domain, element_type, count -> safe_mut(element_type)
copy_to_domain destination_domain, value -> value
```

`alloc` counts are `u64`. Aggregate values are built with `aggregate.construct` and written into places with `store`; the earlier `construct destination, operands` form was folded into these two operations during the format revision.

Required invariants:

- a child domain cannot outlive its parent;
- reset invalidates storage allocated after the corresponding mark;
- no safe reference may be used after its domain reset or destruction;
- a returned reference or aggregate containing references must be valid in the caller-visible result domain;
- destruction occurs at most once on each reachable path;
- raw pointers derived from domain storage cannot be retained across reset or destruction under a safe foreign-call contract.

The initial verifier correlates invalidation by SSA handle derivation (see Verifier Phases). It must never accept a dangling safe reference.

## Cleanup Operations

```text
cleanup.scope.begin -> cleanup_scope
cleanup.push scope, function(arguments...) -> cleanup_id
cleanup.disarm cleanup_id
cleanup.scope.run scope
cleanup.scope.end scope
```

Properties:

- active entries run in reverse registration order;
- each entry runs at most once;
- success, error, and cancellation exits converge through explicit cleanup control flow;
- cleanup effects are visible to the verifier and backend;
- backend-specific C `goto` structure does not leak into MIR.

The cleanup function of `cleanup.push` must have result type `unit`.

## Checked Operations

Safe MIR distinguishes operations with defined failure behavior. Every checked operation carries an explicit `else` failure edge with optional edge arguments; a checked operation without an `else` edge is rejected.

```text
int.add.checked a, b else edge
int.sub.checked a, b else edge
int.mul.checked a, b else edge
int.div.checked a, b else edge
int.shift.checked a, b else edge
slice.index.checked slice_or_ref, index else edge -> safe_mut(elem)
slice.range.checked slice_or_ref, lo, hi else edge -> slice(elem)
enum.payload.checked value, variant else edge -> payload
```

Checked integer operations require both operands to have the same integer type. `slice.index.checked` and `slice.range.checked` accept `slice(T)`, `safe_ref(T)`, and `safe_mut(T)` bases with `u64` indices; `slice.index.checked` yields a checked mutable element reference. `enum.payload.checked` requires a variant with a non-unit payload.

A later MIR optimization may replace a checked operation only after proving the condition cannot fail.

## Comparisons and Conversions

Comparisons require operands of the same type and produce `bool`:

```text
int.eq int.ne int.lt int.le int.gt int.ge
float.eq float.ne float.lt float.le float.gt float.ge
```

Conversions take a value and an explicit result type operand:

```text
int.trunc value, T   (same signedness, narrower)
int.zext value, T    (unsigned, wider)
int.sext value, T    (signed, wider)
float.convert value, T
int.from_float value, T
float.from_int value, T
```

`slice.len slice_or_ref -> u64` reports an element count.

## Generational Table Operations

```text
table.create element_type, domain -> table(element_type)
table.insert table, value -> id(element_type)
table.lookup table, id -> option(table_view(element_type))
table.lookup_mut table, id -> option(table_mut_view(element_type))
table.remove table, id -> bool
table.view.end view
```

Required invariants:

- IDs are associated with a specific table identity and element type;
- removal increments or otherwise invalidates the slot generation before reuse;
- stale IDs cannot resolve to a replacement object;
- table views cannot outlive the operation or access scope that stabilizes their slot;
- compaction may relocate values without changing valid IDs;
- mutation that could invalidate a view is rejected or sequenced after the view ends.

## Constants

Modules declare named constants; instructions materialize them with `const.get`. The initial vocabulary has no immediate operands.

```text
const @name: type = literal
```

Constant types are `unit`, `bool`, integer and float primitives, and `slice(u8)` string literals. Integer literals are decimal `i64`-range values; floats print with shortest-round-trip formatting.

## Calls and C FFI

```text
call function(arguments...) -> result
ffi.call.unsafe import(arguments...) -> result
```

Imported declarations currently record the import name (also the C symbol) and a concrete signature. Retention, const, and cleanup claims for foreign pointers are deferred to a later MIR version; until then, safe wrappers carry that responsibility.

MIR verification cannot prove arbitrary foreign behavior. It verifies only that unsafe entry is explicit and that safe wrapper claims are internally consistent.

## Textual MIR

The textual format is versioned (`mir 1`) and is the canonical fixture format. The parser requires declarations before uses, one statement per line, and deterministic name resolution; the printer reproduces the format byte for byte, so parse-print-parse is stable. `#` starts a line comment.

```text
module   := "mir" version (typeDecl | enumDecl | constDecl | importDecl | fnDecl)*
typeDecl := "type" "@" name "{" (ident ":" type)* "}"
enumDecl := "enum" "@" name "{" (ident ["(" type ")"])* "}"
constDecl:= "const" "@" name ":" type "=" literal
importDecl:= "import" "@" name ":" "fn" "(" type* ")" "->" type
fnDecl   := "fn" "@" name "(" params ")" ["->" type] "{" localDecl* block+ "}"
localDecl:= "local" "%" name ":" type
block    := ident ["(" params ")"] ":" (instr | terminator)*
instr    := ["%" name "="] op operands
terminator:= "jump" blockref
           | "branch" value "," blockref "," blockref
           | "switch" value "{" (variant ["(" "%" name ")"] "->" blockref)* ["default" "->" blockref] "}"
           | "return" [value]
           | "fail" value
           | "unreachable"
blockref := ident ["(" value* ")"]
place    := "local" "%" name | "field" "(" place "," ident ")" | "deref" value
type     := primitive | "@" name | structural type | singleton
```

Checked operations append `else blockref` on the same line. Types print and parse in the canonical forms shown throughout this document (`slice(u8)`, `result(@Summary, @LoadError)`, `function(fn(i64) -> bool)`, and so on).

The `summarize` fixture in `mir/testdata/golden/summarize.mir` is the canonical worked example; the remaining golden fixtures cover tables, arithmetic, domains, FFI, and enum extraction.

## Verifier Phases

The verifier (`mir/verify`) runs explicit, independently testable phases:

1. declaration and ID integrity;
2. type and layout well-formedness;
3. CFG target and block-argument validation;
4. dominance and value availability;
5. place, mutability, and instruction typing;
6. domain nesting and escape validation;
7. cleanup balance and exit validation;
8. table view and invalidation validation;
9. safe/raw pointer boundary validation;
10. backend precondition validation.

Initial conservative rules:

- reference-containing values may flow through SSA values and `deref` places; the verifier tracks storage derivation through allocations, copies, table operations, aggregate and enum construction, loads, block parameters, and switch bindings, and rejects uses after a dominating reset or destruction of the derived domain;
- returned values must not contain references derived from function-local domains;
- `unreachable` terminators are accepted only in blocks unreachable from the entry block;
- table views are ephemeral: every use of a view must stay in its defining block, and a `table.view.end` must follow all other uses;
- `raw_ptr` values may only cross explicit unsafe boundaries: FFI calls, function boundaries, and returns;
- `alloc` and `table.create` element types must be plain value types without handles, cleanup identifiers, views, or raw pointers, recursively.

Diagnostics must be stable and must identify the relevant function, block, operation, and source span when one exists. The current verifier reports function, block, and operation; spans arrive with the frontend.

## Versioning

Textual MIR carries an explicit format version (`mir 1`); external fixtures are stable from this version on. Incompatible changes must update:

- this document;
- parser/printer golden files;
- verifier tests;
- C backend snapshots affected by the change.

MIR must not acquire LLVM-specific types, attributes, exception models, or pointer assumptions during the current project phase.

## Open Questions

- Whether domain placement is complete before MIR or represented as constraints within early MIR.
- Whether cleanup should remain explicit instructions or lower into canonical CFG before backend consumption.
- Whether table views require lexical MIR scopes or can be proven solely through dataflow (the initial verifier restricts views to their defining block).
- Which aggregate copies are semantic and which can be represented as destination construction.
- Whether a small MIR interpreter materially improves differential backend testing.
- Whether checked-index places return, and how mutable slice element access should be typed (the initial vocabulary uses `slice.index.checked` plus `deref`).
- How import retention, const, and cleanup claims should be recorded.
- How `unreachable` should be justified when failure edges are provably impossible.
