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

Values are defined by function parameters, block parameters, instruction results, and switch case payload bindings. Textual value names must be unique within a function; the same name may be used in different functions. A value may be used only where its definition dominates the use (see Verifier Phases). Calls and FFI calls whose result type is `unit` may be left unbound; every other producing operation must bind its result.

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

### Independent Alder MIR 4 encoding

The bootstrap compiler's independent flat model in `compiler/src/mir_model.al`
uses external 1-based `U64` identities so that zero uniformly means absent. A
nonzero module-table identity converts to a Go MIR slice index by subtracting
one. The twelve primitive types therefore have fixed external IDs 1 through 12
in this order: `unit`, `bool`, `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`,
`u64`, `f32`, `f64`. Type, constant, value-definition, place, operation, and
terminator kinds retain the exact zero-based numeric values of the Go model;
the Alder-only type-part, parameter, and flattened-operand kinds are explicitly
numbered by named functions in that file. The independent model's format
version is exactly 4.

Function-local Go IDs are encoded as ordinal + 1. Consumers resolve a block,
value, or local by scanning its flat buffer for the owning function and the
zero-based ordinal. Parameters, blocks, locals, values, instructions within a
block, the one terminator for each block, and every ordered child family must
have contiguous ordinals beginning at zero. Global flat record identities
(including instruction, terminator, operand, and type-part records) are buffer
index + 1. Append order is deterministic but is not evidence of validity.

The following ownership rules are part of the encoding contract:

- function parameters are owned by a function, have block zero, and point to
  leading function values; block parameters additionally own a logical block
  ID. Each parameter and value definition links reciprocally, with the value's
  `item` storing parameter ordinal + 1;
- import parameters are `import_param` operand records owned by an Import ID;
  their `operand_type` fields, in ordinal order, plus the import record's result
  type form the signature;
- locals, blocks, values, and places name their owning function. An instruction
  names both that function and one of its blocks; its ordinal is local to the
  block. An instruction result and its value definition link reciprocally, with
  `item` storing instruction ordinal + 1;
- exactly one terminator record names each function/block pair. Terminator edge
  arguments are owned by the global terminator-record ID. Their `edge` is 0 for
  jump, 1 for branch-then, and 2 for branch-else, so equal branch targets remain
  unambiguous;
- instruction operands, checked failure-edge arguments, and aggregate fields
  are owned by the global instruction-record ID. Checked arguments also repeat
  the failure target. Aggregate fields carry their field name and value in
  declaration order;
- switch cases are owned by the global switch-terminator ID. Their optional
  payload binding links reciprocally to a switch-case value definition whose
  `item` stores case ordinal + 1. A switch-case argument is owned by the global
  switch-case operand ID and repeats that case's target;
- aggregate fields and enum variants are `MirTypePartRec` records owned by the
  named Type ID. Membership is the owner scan and ordinals are contiguous per
  owner and part kind. Anonymous function types additionally carry a
  `first_part`/`part_count` boundary which must exactly cover their reciprocal
  function-parameter parts.

Consumers validate in-range IDs, owners, boundaries, contiguous ordinals,
single ownership, and every reciprocal link. Builders remain append-only data
constructors: they neither verify nor repair malformed raw records, which must
remain observable for deterministic verifier rejection tests.

The bootstrap compiler's Alder textual printer implements this consumer
validation and emits the canonical MIR 4 spelling directly from the independent
store. It does not read source files or retain host paths. Its float output uses
a narrow host formatting primitive with the same finite, shortest-round-trip
contract as Go's `strconv.FormatFloat(value, 'g', -1, 64)`; non-finite constant
bits are rejected before output. This printer is not a MIR parser or the
independent Alder verifier.

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
vec(TypeId)
array(TypeId, Length)
string
bytes
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

`vec(T)` is an owned growable vector represented by `{data, len, capacity}`. `vec.new vec(T)` creates an empty value. `vec.construct.checked storage, len, capacity else edge` validates `len <= capacity <= storage.len`; `vec.grow.checked vec, domain, capacity else edge` reallocates with checked sizing. `vec.len`, `vec.capacity`, `vec.storage`, `vec.as_slice`, and `vec.as_mut_slice` expose its bounds and views. For relocatable values, `copy_to_domain` recursively materializes slices, vectors, arrays, and aggregate children, sets copied vector capacity to its length, and gives the result independent destination-domain provenance. Domain, table, cleanup, raw-pointer, and other identity-bearing resource/capability types are rejected rather than assigned false independent provenance.

`array.as_slice` converts an array value or a checked reference to an array into
an immutable contiguous view. Source-level mutable-view exclusivity remains a
frontend invariant; the C representation is shared with `slice(T)`.

`safe_ref(T)` and `safe_mut(T)` are checked references associated with a valid storage or table access scope. `raw_ptr(T)` may only be produced or consumed by operations explicitly marked unsafe or by narrowly defined runtime intrinsics. `string` and `bytes` are distinct owned byte-sequence value types; `string` constants must contain valid UTF-8, while `bytes` constants preserve arbitrary bytes. The private source-bootstrap `__s0_String` may still lower to `slice(u8)` until the M7.3 migration gate, but public `String` and `Bytes` do not.

`array(T, N)` is a fixed-length value type. Array assignment and return copy all elements and produce an independent value. The C backend represents it as a wrapper struct containing a native C element array, preserving these value semantics under ordinary C assignment and return.

The exact string, bytes, and dynamic-array layouts belong to the runtime ABI, not the semantic type system.

## Places and Values

A place identifies mutable storage:

```text
local %name
field place, field_name
deref checked_reference_value
```

`deref` accepts `safe_ref`, `safe_mut`, `table_view`, and `table_mut_view` values. A place is mutable when it is a local, a field of a mutable place, or a deref of a `safe_mut` or `table_mut_view`; derefs of `safe_ref` and `table_view` are read-only.

The initial vocabulary has no unchecked index place. Checked element access uses `slice.index.checked`, which yields a checked reference that `deref` places consume.

A value is an immutable result of an instruction. `load` reads a place and
produces a value; `store` writes a value into a place and does not invalidate
other source-level names. `borrow place` and `borrow_mut place` produce
`safe_ref(T)` and `safe_mut(T)` respectively for a place of type `T`;
`borrow_mut` requires a mutable place. Both borrows observe the place for
definite-initialization purposes. Unsafe raw-pointer dereference is never
represented as an ordinary safe place. Every reachable load or borrow from a
local or one of its fields requires that place to be definitely initialized on
every incoming path. Storing a whole aggregate initializes all of its fields;
storing every field is equivalent at control-flow joins. A store reached only
through a loop backedge cannot initialize the first iteration.

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
alloc.checked domain, element_type, count else failure_block -> safe_mut(element_type)
copy_to_domain destination_domain, value -> value
```

Allocation counts are `u64`. `alloc` traps on every preparation or runtime
failure. `alloc.checked` instead takes the standard explicit failure edge; that
edge observes the pre-instruction resource state, while success produces a
slice whose provenance is the supplied domain. Aggregate values are built with
`aggregate.construct` and written into places with `store`; the earlier
`construct destination, operands` form was folded into these two operations
during the format revision. Array construction uses
`aggregate.construct array(T, N) { value, ... }` with exactly `N` operands,
each of type `T`.

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
array.index.checked array_or_safe_mut_array, index else edge -> safe_mut(elem)
slice.range.checked slice_or_ref, lo, hi else edge -> slice(elem)
enum.payload.checked value, variant else edge -> payload
```

Checked integer operations require both operands to have the same integer type. `int.shl.checked` is a wrapping left shift on the integer's bit pattern; `int.shr.checked` is arithmetic for signed operands and logical for unsigned operands. Both fail when the shift count is negative or at least the operand width. `slice.index.checked` and `slice.range.checked` accept `slice(T)`, `safe_ref(T)`, and `safe_mut(T)` bases with `u64` indices; `slice.index.checked` yields a checked mutable element reference. `array.index.checked` accepts `array(T, N)` or `safe_mut(array(T, N))` and a `u64` index, fails when the index is at least `N`, and yields `safe_mut(T)`. A null data pointer is valid only for a zero-length slice: `[0, 0)` succeeds without pointer arithmetic, while indexing it and every operation on `{null, len > 0}` fail. `enum.payload.checked` requires a variant with a non-unit payload.

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

Constant types are `unit`, `bool`, integer and float primitives, `string`, and
`bytes`; private source-bootstrap constants may additionally use `slice(u8)`.
Integer literals are decimal `i64`-range values; floats print with
shortest-round-trip formatting. Quoted `string` payloads must be valid UTF-8,
while quoted `bytes` payloads preserve every decoded byte.

## Calls and C FFI

```text
call function(arguments...) -> result
ffi.call.unsafe import(arguments...) -> result
```

Imported declarations currently record the import name (also the C symbol) and a concrete signature. The C backend accepts only backend-safe C identifiers: C keywords, generated/runtime prefixes, names beginning with `_`, macro-style uppercase names, header tokens such as `bool` and `offsetof`, functions declared by always-included headers, `main`, and names ending in the reserved typedef suffix `_t` are rejected. The accepted name is emitted unchanged, never sanitized into a potentially colliding symbol. Retention, const, and cleanup claims for foreign pointers are deferred to a later MIR version; until then, safe wrappers carry that responsibility.

MIR verification cannot prove arbitrary foreign behavior. It verifies only that unsafe entry is explicit and that safe wrapper claims are internally consistent.

## Function Values

`fn.value` makes a `{code, env}` pair: the target function plus an optional
environment operand, called through `call.value` with the declared runtime
arguments (MIR 5). The erased function type covers the declared parameters
and the result only; the environment rides opaquely in the value.

Two shapes extend the erased signature:

- a closure thunk's trailing parameter is the environment record, supplied
  by the environment operand, and the erased type omits it;
- in the storage model every plain function carries a hidden leading
  `domain_handle` parameter. When `fn.value` targets such a function, its
  environment operand carries the referencing function's own domain and the
  instruction's `type_op` holds the domain marker (the sentinel constant far
  above every real type id). The erased type then covers the parameters
  after the hidden domain, and phase-5 typing requires both that the
  callee's leading parameter is a `domain_handle` and that the environment
  operand is domain-typed.

The domain marker is legal only on `fn.value` and requires the environment
operand; the verifier rejects it on any other operation (no other operation
reads a type near the sentinel, so the value identifies the marker
unambiguously) and rejects a marked `fn.value` whose callee lacks the hidden
domain parameter. The C backend's forwarder wrapper casts the trailing
environment argument to `AlderDomain *` and passes it as the target's first
argument, exactly as a direct call threads the caller's domain.

Lifetime: the environment domain is the referencing function's own domain
parameter, and every storage domain in a compiled program descends from the
host entry's domain, which outlives every frame that can observe the value.
Phase 6 merges the environment operand's domain provenance into the fn value
and into every `call.value` result, so the value and its results carry the
captured domain's provenance through the existing lattice.

A closure environment record is one aggregate per site. A record whose thunk
may copy or allocate storage, or whose body contains another literal, records
the domain that owns the record as its first field, and the thunk loads that
field in its prologue and uses it as its active and result domain, so a nested
environment or a storage copy is materialized beside the outer record instead
of in a frame domain the thunk does not have. A capture that carries storage is
deep-copied into that domain at creation and into the destination domain when
the record is retained; a function-valued capture is retained recursively. For
the loop-survival rule such a record is an owning value: its domain field names
the domain that owns the record, not a borrowed capability. Two conservative
rules are narrowed for such a record and for nothing else: a domain handle in a
dereference store is accepted when the stored value is an aggregate used as a
`fn.value` environment, and `alloc` of that aggregate is accepted. This is
sound because the record is allocated in the domain its field names, every
cross-domain move goes through the retain hook, which rewrites the field to the
destination domain, and the record never outlives its domain; the field is only
ever used as an allocation parent.

A function value that leaves its creating frame is retained.
`copy_to_domain` of a function type produces a complete, independent value in
the destination domain through the backend's per-environment retain hook, so
the copy severs the source's provenance exactly as it does for a slice, a
vector, or an aggregate. This is sound only because the hook makes the copy
complete: it allocates a fresh environment record in the destination domain,
rewrites a captured domain handle to that domain, and retains every
function-valued capture recursively. Closure captures are storage-free, so a
shallow record copy of the remaining fields is complete. A function value
returned without such a copy still shares its environment, so phase 6 rejects
the exit when the environment's owning domain was destroyed.

## Textual MIR

The current textual format is `mir 4`; the parser and verifier retain legacy
`mir 1`, `mir 2`, and `mir 3` support. MIR 2 adds the `panic` terminator, MIR 3
adds `alloc.checked`, and MIR 4 adds Vec, so use under an older header is rejected
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

The `panic` production is available in MIR 2 and later.

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

The independent Alder implementation provides all ten phases over raw
`MirStore` records with stable numeric diagnostics and first-failing-phase
orchestration. Phase 4 includes instruction-boundary dominance, checked
failure-edge positions, all flat value-use forms, and field-sensitive definite
local initialization. Phase 5 types every current instruction, place and
projection, operand and result, ordinary and checked edge, call and import call,
aggregate and enum operation, and terminator without coercion or repair. Phase
6 provides domain identity and strict ancestry, allocation provenance,
path-sensitive reset/destroy invalidation, interprocedural lifetime effects,
function-boundary and loop rules, and dereference-store restrictions. Phase 7
adds path-correlated cleanup scope state, registration identity and
LIFO order, checked-failure and exit invariants, and repeatable per-iteration
lifecycles. Phase 8 consumes the V6 provenance and V7 cleanup contracts to check
table lookup consumption, identity, aliases, mutations, and lexical view
regions. Phase 9 checks every V4 use of recursively raw-pointer-bearing values
and permits consumption only as an unsafe FFI argument or return/fail operand.
Phase 10 checks conservative C11 allocation/table element restrictions and C
external names.

`mir_verify_complete(d, store, version, hosted)` is the explicit final gate. A
consumer may emit bytes only when its `MirVerifyCompleteOutput.complete` field
is true. For `hosted == true`, success also guarantees one `main` returning
`i32` with either no parameters or one `domain_handle` parameter, and `entry`
is that function's external 1-based ID. Unhosted success has `entry == 0`, and
every failure has `entry == 0` regardless of whether entry discovery preceded
the failing signature check. Duplicate function names, including duplicate
`main`, remain V1 representation errors rather than V10 entry errors. Failure
preserves the first failing phase diagnostics, sets `complete` false, and never
repairs the store. This contract makes all verifier phases available;
the Alder production source entry now uses its complete result as the sole MIR
output gate. The final M5.4 driver now routes verified source MIR through the
existing complete-verifier and supported-operation-gated C generator.
Because the frozen flat store contains no module header record,
`mir_verify_module` receives the MIR format version alongside the store; the
store's IDs, kinds, ownership, and type-part encoding remain unchanged.

Initial conservative rules:

- `cleanup_scope` and `cleanup_id` handles keep direct SSA identity: they may only be cleanup instruction results and direct operands, and may not appear in function signatures, aggregate or enum fields/payloads, block parameters, locals, or load/store propagation;
- reachable local loads require path-sensitive definite initialization. Field stores initialize only their aggregate subtree, predecessor states intersect at joins, and checked-operation failure edges observe the pre-operation state;
- cleanup analysis preserves path-specific registration alternatives and runtime registration order. Phase 6 consumes those alternatives at each run, validates callback arguments against the state before each LIFO invocation, and applies callback reset/destroy effects without flattening mutually exclusive registrations. A static `cleanup.push` site may execute again only after its preceding dynamic registration has been disarmed or its scope has run and ended; this keeps one SSA cleanup ID unambiguous while allowing a complete begin/push/run/end lifecycle to repeat in a loop;
- reference-containing values may flow through SSA values and `deref` places; the verifier tracks storage derivation through allocations, copies, table operations, aggregate and enum construction, loads, block parameters, and switch bindings, and rejects a use when the value may have been reset or destroyed on any reachable incoming path. A load of a provenance-free type is exempt from that derivation: a type is provenance-free when it contains no slice, view, reference, pointer, vec, table, string, bytes, domain handle or mark, cleanup scope or id, or function part at any depth, so its values are plain bits (primitives, and options, results, arrays, aggregates, and enums over plain bits). Loading such a value copies bits with no lifetime tie to the storage it was read from — a later reset or destroy of that storage can free the backing allocation but cannot change or dangle the loaded bits — so the load inherits no domain provenance and its result may be stored through locals and loop backedges freely. Loads of storage-carrying types keep the full derivation and remain subject to the cyclic-store rules below;
- domain and reference lifetime effects are propagated through ordinary calls and active cleanup callbacks by deterministic whole-module fixed-point summaries; recursive call graphs are supported;
- at a function boundary, a reference-containing parameter is conservatively allowed to depend on any `domain_handle` parameter. A caller's more precise provenance is retained when mapping call results and effects;
- externally supplied domain handles and tables may alias other compatible parameters unless local provenance proves distinct identities. To avoid unsummarized interprocedural memory writes, the current MIR profile rejects storing values that recursively contain safe references, slices, tables, domain handles, or domain marks through a dereference-based place; local-place stores remain supported and field-sensitive;
- Phase 6 resource state is path-sensitive and joins with a conservative union. Checked-operation failure edges observe the state before the checked instruction's effect;
- Domain identity and parent ancestry are tracked separately: destroying a child does not destroy its parent, while destroying a parent invalidates descendant handles and allocations. The current MIR profile permits create/allocate/destroy wholly within each loop iteration, but conservatively rejects function-local domain handles and references carried through block arguments across a backedge. A cyclic local-place store may carry allocations owned only by function-parameter domains when the current function never resets or destroys any parameter domain through verified MIR effects; every such allocation remains live for the call, so repeated static allocation roots cannot revive an invalid alias. Local-domain values and cyclic stores in functions that may invalidate a parameter domain remain rejected. As at every `ffi.call.unsafe`, foreign code remains responsible for preserving any domain lifetime promised by its safe wrapper.
- The loop rules are death-precise for owning values: a carried value whose type contains no capability or handle kind (no slice, view, reference, pointer, table owner or view, domain handle or mark, cleanup scope or id — the `loopCarryOwnerType` classifier) is rejected only when its storage actually dies inside the loop, namely when a domain it derives from was created inside the loop, or a destroy or reset that may alias one of its domain identities (including ancestors, through parent facts) executes in a loop block the carrying site can reach. A domain created before the loop and destroyed only at the function's exits survives, which is what makes loop-carried collection headers (`store local` of a rebuilt `vec` header, and `vec`-typed loop parameters) legal; per-iteration parameter-domain allocations carried as block parameters stay rejected because carrying one conflates iterations. "Inside the loop" is measured against the loop under check, not against any cycle in the function: a domain or an allocation produced inside an enclosing or an earlier, already finished loop is carried across this loop's backedge unchanged, so it is not per-iteration here. A `vec`-typed loop parameter is rejected only when the loop header dominates the block that creates its domain or its storage; the store rule, which has no header to hand, measures the same question from the storing block instead, so it keeps the coarser same-cycle test. Capability-typed values keep the conservative rules above. A copyable snapshot that may contain function values and nothing that owns or aliases mutable storage (a function type, or an option, result, array, aggregate, or enum over plain bits and such snapshots) is exempt from the per-iteration allocation clause: its function environments are immutable shared records, so carrying one across a backedge transfers no ownership, while a destroy or reset that reaches an environment's domain inside the loop still rejects it. This is the D023-adjacent soundness line: ownership may be carried where its backing provably outlives the loop; capabilities may not.
- Domain marks keep direct SSA identity. Reset consumes all marks corresponding to the reset domain, and a later `domain.mark` produces a fresh runtime-epoch mark;
- Ordinary functions may not return `domain_handle` or `domain_mark` in the current MIR profile. Their result identity and parent relation cannot yet be represented by function-effect summaries, so Phase 2 rejects such signatures rather than losing provenance at a call.
- local-place provenance distinguishes field paths. Dereference-based memory has no general alias declaration in the current MIR profile, so Phase 6 conservatively treats dereference stores as possible sources for dereference loads;
- returned values must not contain references derived from function-local domains;
- a function value's environment is a domain allocation, and `copy_to_domain` of a function type is complete: the C backend's retain hook allocates a fresh environment in the destination domain, rewrites a captured domain handle, and retains function-valued captures recursively, so the copy severs the source's provenance like any other independently materialized value. A function value returned without such a copy keeps the source's provenance, so a return after its environment's owning domain was destroyed is rejected at the return exit;
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
format; `mir 2` adds only valueless `panic`; `mir 3` adds `alloc.checked`; and
current `mir 4` adds `vec(T)` and the minimal Vec operations.
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
