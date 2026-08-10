# Aster MIR

Status: initial design contract

Aster MIR is the typed, source-independent contract between semantic analysis and code generation. The current project exists primarily to make this contract precise and executable.

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
- optional source-span tables used only for diagnostics.

A function contains:

- typed parameters;
- local slots;
- basic blocks;
- SSA-like temporary values;
- block parameters rather than implicit phi nodes;
- exactly one terminator per block.

Mutable language variables lower to explicit places and stores. Pure computed temporaries are single-assignment values. Aster has no MIR `move` operation that invalidates a source value.

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
BlockId
ValueId
LocalId
DomainId
CleanupId
SpanId
```

Printed ordering must not depend on host-language map iteration, pointer values, allocation addresses, or traversal races.

## Initial Type Vocabulary

The first MIR subset should include:

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

`safe_ref(TypeId)` and `safe_mut(TypeId)` are checked references associated with a valid storage or table access scope. `raw_ptr(TypeId)` may only be produced or consumed by operations explicitly marked unsafe or by narrowly defined runtime intrinsics.

The exact string and dynamic-array representations belong to the runtime ABI, not the semantic type system.

## Places and Values

A place identifies mutable storage:

```text
local %name
field place, field_index
index place, checked_index
deref safe_reference
```

A value is an immutable result of an instruction. Loading a place produces a value; storing consumes a value as an operand but does not invalidate other source-level names.

Unsafe raw-pointer dereference is never represented as an ordinary safe place.

## Control Flow

Initial terminators:

```text
jump block(arguments...)
branch condition, then_block, else_block
switch value, cases..., default_block
return value
fail error_value
unreachable
```

Block arguments must exactly match target block parameter types. Every reachable block must terminate. `unreachable` is valid only when the verifier can identify a semantic reason or when it is inside an explicit unsafe boundary.

## Storage-Domain Operations

Initial operations:

```text
domain.create parent -> domain_handle
domain.mark domain -> domain_mark
domain.reset domain, domain_mark
domain.destroy domain
alloc domain, element_type, count -> safe_mut(element_type)
construct destination, aggregate_operands...
copy_to_domain destination_domain, value -> value
```

Required invariants:

- a child domain cannot outlive its parent;
- reset invalidates storage allocated after the corresponding mark;
- no safe reference may be used after its domain reset or destruction;
- a returned reference or aggregate containing references must be valid in the caller-visible result domain;
- destruction occurs at most once on each reachable path;
- raw pointers derived from domain storage cannot be retained across reset or destruction under a safe foreign-call contract.

The initial verifier may conservatively reject or retain storage when precise placement is unavailable. It must never accept a dangling safe reference.

## Cleanup Operations

Initial cleanup model:

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

## Checked Operations

Safe MIR distinguishes operations with defined failure behavior:

```text
int.add.checked
int.sub.checked
int.mul.checked
int.div.checked
int.shift.checked
slice.index.checked
slice.range.checked
enum.payload.checked
```

The failure edge or result is explicit. A later MIR optimization may replace a checked operation only after proving the condition cannot fail.

## Generational Table Operations

Initial operations:

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

## Calls and C FFI

Ordinary calls use typed MIR signatures:

```text
call function(arguments...) -> result
```

Foreign calls are explicit:

```text
ffi.call.unsafe c_declaration(arguments...) -> result
```

Imported declarations record:

- C spelling or generated shim symbol;
- calling convention;
- parameter and result layout;
- const and mutability information available from the header;
- whether a wrapper asserts that pointers are retained or not retained;
- required cleanup function when known.

MIR verification cannot prove arbitrary foreign behavior. It verifies only that unsafe entry is explicit and that safe wrapper claims are internally consistent.

## Textual MIR Sketch

The syntax below is illustrative and will be revised when the parser is implemented:

```text
fn @summarize(%result_domain: domain_handle, %data: slice(u8))
    -> result(@Summary, @Error) {
  local %cleanup: cleanup_scope
  local %temp: domain_handle

bb0:
  %cleanup = cleanup.scope.begin
  %temp = domain.create %result_domain
  %temp_cleanup = cleanup.push %cleanup, @domain.destroy, (%temp)

  %parsed = call @json.parse(%temp, %data)
  switch %parsed {
    ok(%document) -> bb1(%document)
    err(%error) -> bb_error(%error)
  }

bb1(%document: @DocumentView):
  %title_view = call @document.title(%document)
  %title = call @string.copy_to_domain(%result_domain, %title_view)
  %words = call @document.word_count(%document)
  %summary = aggregate @Summary { title: %title, words: %words }
  cleanup.scope.run %cleanup
  cleanup.scope.end %cleanup
  return ok(%summary)

bb_error(%error: @Error):
  cleanup.scope.run %cleanup
  cleanup.scope.end %cleanup
  return err(%error)
}
```

## Verifier Phases

The verifier should run explicit, independently testable phases:

1. declaration and ID integrity;
2. type and layout well-formedness;
3. CFG target and block-argument validation;
4. dominance and value availability;
5. place and mutability rules;
6. domain nesting and escape validation;
7. cleanup balance and exit validation;
8. table view and invalidation validation;
9. safe/raw pointer boundary validation;
10. backend precondition validation.

Diagnostics must be stable and must identify the relevant function, block, operation, and source span when one exists.

## Versioning

Textual MIR will gain an explicit format version before external fixtures are treated as stable. During bootstrap, incompatible changes are allowed but must update:

- this document;
- parser/printer golden files;
- verifier tests;
- C backend snapshots affected by the change.

MIR must not acquire LLVM-specific types, attributes, exception models, or pointer assumptions during the current project phase.

## Open Questions

- Whether domain placement is complete before MIR or represented as constraints within early MIR.
- Whether cleanup should remain explicit instructions or lower into canonical CFG before backend consumption.
- Whether table views require lexical MIR scopes or can be proven solely through dataflow.
- Which aggregate copies are semantic and which can be represented as destination construction.
- Whether a small MIR interpreter materially improves differential backend testing.
