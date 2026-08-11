# Alder MIR

Status: versioned contract with a working Go toolkit

Alder MIR is the typed, source-independent contract between semantic analysis and code generation. The `mir` Go package implements the in-memory representation, the deterministic textual printer and parser, and the type inference shared by the parser and the verifier. The verifier lives in `mir/verify`.

MIR must express Alder semantics without depending on C syntax or a future native backend. The C11 backend is a consumer, not the definition, of MIR.

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

Mutable language variables lower to explicit places and stores. Pure computed temporaries are single-assignment values. Alder has no MIR `move` operation that invalidates a source value.

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

A value is an immutable result of an instruction. `load` reads a place and produces a value; `store` writes a value into a place and does not invalidate other source-level names. Unsafe raw-pointer dereference is never represented as an ordinary safe place. Every reachable load from a local or one of its fields requires that place to be definitely initialized on every incoming path. Storing a whole aggregate initializes all of its fields; storing every field is equivalent at control-flow joins. A store reached only through a loop backedge cannot initialize the first iteration.

## Control Flow

Terminators:

```text
jump block(arguments...)
branch condition, then_block, else_block
switch value { cases..., default? }
return [value]
fail value
panic
unreachable
```

- Block arguments must exactly match target block parameter types.
- A switch dispatches on an enum-like value: a declared enum, an option (`none`, `some`), or a result (`ok`, `err`). A case may bind the variant payload as a new value; the case `default` (represented as a case with an empty variant name) is allowed at most once. A switch must cover every variant of its operand type or contain a default case.
- `return` and `fail` both exit with a value of the function's result type; `fail` marks the failure path. A `return` without an operand returns `unit`.
- `panic` is a MIR 2 valueless, successor-less checked-failure exit. A checked
  edge may reach it only after explicit cleanup of current-function cleanup
  scopes; it does not unwind caller frames. MIR 1 modules cannot contain this
  terminator.
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
- a mark made before the first allocation resets the domain to empty, and a
  successful reset consumes every outstanding mark for that domain epoch;
- the current MIR profile conservatively invalidates every table owned by a reset domain because
  table insertion and growth contain runtime allocations not represented as
  separate MIR values;
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
int.shl.checked a, b else edge
int.shr.checked a, b else edge
slice.index.checked slice_or_ref, index else edge -> safe_mut(elem)
slice.range.checked slice_or_ref, lo, hi else edge -> slice(elem)
enum.payload.checked value, variant else edge -> payload
```

Checked integer operations require both operands to have the same integer type. `int.shl.checked` is a wrapping left shift on the integer's bit pattern; `int.shr.checked` is arithmetic for signed operands and logical for unsigned operands. Both fail when the shift count is negative or at least the operand width. `slice.index.checked` and `slice.range.checked` accept `slice(T)`, `safe_ref(T)`, and `safe_mut(T)` bases with `u64` indices; `slice.index.checked` yields a checked mutable element reference. A null data pointer is valid only for a zero-length slice: `[0, 0)` succeeds without pointer arithmetic, while indexing it and every operation on `{null, len > 0}` fail. `enum.payload.checked` requires a variant with a non-unit payload.

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

`float.convert` from `f64` to `f32` terminates on NaN, infinity, or a finite value outside the `f32` range instead of executing an undefined C conversion. In-range conversion uses the target C11 `double`-to-`float` rounding behavior. `int.from_float` likewise terminates on NaN or a value outside the destination range; otherwise it truncates toward zero.

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

Imported declarations currently record the import name (also the C symbol) and a concrete signature. The C backend accepts only backend-safe C identifiers: C keywords, generated/runtime prefixes, names beginning with `_`, macro-style uppercase names, header tokens such as `bool` and `offsetof`, functions declared by always-included headers, `main`, and names ending in the reserved typedef suffix `_t` are rejected. The accepted name is emitted unchanged, never sanitized into a potentially colliding symbol. Retention, const, and cleanup claims for foreign pointers are deferred to a later MIR version; until then, safe wrappers carry that responsibility.

MIR verification cannot prove arbitrary foreign behavior. It verifies only that unsafe entry is explicit and that safe wrapper claims are internally consistent.

## Textual MIR

The current textual format is `mir 2`; the parser and verifier retain legacy
`mir 1` support for existing fixtures. MIR 2 differs from MIR 1 only by adding
the `panic` terminator, so a `mir 1` module containing `panic` is rejected
rather than silently changing the old format. Function headers are predeclared
in textual order before function bodies are parsed, so calls and cleanup
callbacks may name the current function or any later function; `FunctionId`
values remain textual declaration order. Named types, constants, and imports
still require declaration before use, including from function bodies. The
parser otherwise requires declarations before uses, one statement per line,
and deterministic name resolution. The printer preserves the parsed version
and emits the current version for newly constructed modules. Printing a
canonical golden fixture reproduces it byte for byte, while comments and
noncanonical layout are intentionally normalized. Parse-print-parse reaches a
stable fixed point for every MIR fixture. `#` starts a line comment.

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
           | "panic"
           | "unreachable"
blockref := ident ["(" value* ")"]
place    := "local" "%" name | "field" "(" place "," ident ")" | "deref" value
type     := primitive | "@" name | structural type | singleton
```

The `panic` production is available only in MIR 2.

Checked operations append `else blockref` on the same line. Types print and parse in the canonical forms shown throughout this document (`slice(u8)`, `result(@Summary, @LoadError)`, `function(fn(i64) -> bool)`, and so on).

The `summarize` fixture in `mir/testdata/golden/summarize.mir` is the canonical worked example; the remaining golden fixtures cover tables, arithmetic, domains, FFI, and enum extraction.

## Verifier Phases

The verifier (`mir/verify`) runs explicit, independently testable phases:

1. declaration and ID integrity;
2. type and layout well-formedness;
3. CFG target and block-argument validation;
4. dominance, value availability, and definite local initialization;
5. place, mutability, and instruction typing;
6. domain nesting and escape validation;
7. cleanup balance and exit validation;
8. table view and invalidation validation;
9. safe/raw pointer boundary validation;
10. backend precondition validation.

Initial conservative rules:

- `cleanup_scope` and `cleanup_id` handles keep direct SSA identity: they may only be cleanup instruction results and direct operands, and may not appear in function signatures, aggregate or enum fields/payloads, block parameters, locals, or load/store propagation;
- reachable local loads require path-sensitive definite initialization. Field stores initialize only their aggregate subtree, predecessor states intersect at joins, and checked-operation failure edges observe the pre-operation state;
- cleanup analysis preserves path-specific registration alternatives and runtime registration order. A static `cleanup.push` site may execute again only after its preceding dynamic registration has been disarmed or its scope has run and ended; this keeps one SSA cleanup ID unambiguous while allowing a complete begin/push/run/end lifecycle to repeat in a loop;
- reference-containing values may flow through SSA values and `deref` places; the verifier tracks storage derivation through allocations, copies, table operations, aggregate and enum construction, loads, block parameters, and switch bindings, and rejects a use when the value may have been reset or destroyed on any reachable incoming path;
- domain and reference lifetime effects are propagated through ordinary calls and active cleanup callbacks by deterministic whole-module fixed-point summaries; recursive call graphs are supported;
- at a function boundary, a reference-containing parameter is conservatively allowed to depend on any `domain_handle` parameter. A caller's more precise provenance is retained when mapping call results and effects;
- externally supplied domain handles and tables may alias other compatible parameters unless local provenance proves distinct identities. To avoid unsummarized interprocedural memory writes, the current MIR profile rejects storing values that recursively contain safe references, slices, tables, domain handles, or domain marks through a dereference-based place; local-place stores remain supported and field-sensitive;
- Phase 6 resource state is path-sensitive and joins with a conservative union. Checked-operation failure edges observe the state before the checked instruction's effect;
- Domain identity and parent ancestry are tracked separately: destroying a child does not destroy its parent, while destroying a parent invalidates descendant handles and allocations. The current MIR profile permits create/allocate/destroy wholly within each loop iteration, but conservatively rejects function-local domain handles and references carried through block arguments or stored from a cyclic block across a backedge; this avoids conflating dynamic instances of one static allocation site or reviving an older alias.
- Domain marks keep direct SSA identity. Reset consumes all marks corresponding to the reset domain, and a later `domain.mark` produces a fresh runtime-epoch mark;
- Ordinary functions may not return `domain_handle` or `domain_mark` in the current MIR profile. Their result identity and parent relation cannot yet be represented by function-effect summaries, so Phase 2 rejects such signatures rather than losing provenance at a call.
- local-place provenance distinguishes field paths. Dereference-based memory has no general alias declaration in the current MIR profile, so Phase 6 conservatively treats dereference stores as possible sources for dereference loads;
- returned values must not contain references derived from function-local domains;
- `unreachable` terminators are accepted only in blocks unreachable from the entry block;
- table identities originate at function table parameters and `table.create` sites and are preserved through block parameters, memory, aggregate/enum values, and ordinary calls. A call returning a newly-created table receives a stable call-site identity;
- any domain reset invalidates tables that may be owned by that domain, even when the table was created before the mark. This conservative rule prevents hidden element or slot allocations made after the mark from surviving behind a stale table handle;
- a table lookup result is consumed exactly once, in its defining block, by a `some` switch binding or checked `some` payload extraction. From lookup until extraction, and from successful extraction through `table.view.end`, insert, remove, and ordinary-call or active-cleanup effects that may mutate the same table are forbidden. The checked extraction failure edge observes the pre-extraction state and a switch `none` path has no view to end;
- table views are ephemeral: every use of a view must stay in its access block, exactly one `table.view.end` follows all other uses, and neither insert nor remove of the same table may occur while any related view remains active;
- `raw_ptr` values may only cross explicit unsafe boundaries: FFI calls, function boundaries, and returns;
- `alloc` and `table.create` element types must be plain value types without handles, cleanup identifiers, views, or raw pointers, recursively.

Diagnostics must be stable and must identify the relevant function, block, operation, and source span when one exists. The current verifier reports function, block, and operation; spans arrive with the frontend.

## Versioning

Textual MIR carries an explicit format version. `mir 1` remains a stable legacy
format; `mir 2` is current and adds only the valueless `panic` terminator.
Incompatible changes must use a new version and update:

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
