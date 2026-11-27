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
- A switch dispatches on an enum-like value: a declared enum, an option (`none`, `some`), or a result (`ok`, `err`). A case may bind the variant payload as a new value; a payload whose type is `unit` has no value to bind and must be written without a binding. The case `default` (represented as a case with an empty variant name) is allowed at most once. A switch must cover every variant of its operand type or contain a default case.
- `return` and `fail` both exit with a value of the function's result type; `fail` marks the failure path. A `return` without an operand returns `unit`.
- `panic` is a MIR 2 valueless, successor-less checked-failure exit. A checked
  edge may reach it only after explicit cleanup of current-function cleanup
  scopes; it does not unwind caller frames. MIR 1 modules cannot contain this
  terminator.
- `unreachable` is valid only in blocks that are unreachable from the entry block, except that a reachable block may terminate with it after a call to a function marked `noreturn`. A function record may carry the attribute, printed after the result as `fn @name(...) noreturn {`. Lowering marks the resolved `core.panic.panic` function; the call itself performs the process termination, and the terminator states that its continuation cannot be reached.
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

### Borrowed-place owner domains

A `safe_mut(T)` parameter borrows the caller's place. In a function that
carries any `domain_handle` parameter, every `safe_mut` parameter is followed
immediately by a `domain_handle` owner parameter. Direct calls and indirect
`call.value` calls pass the owner after the corresponding borrowed argument;
function types used by `fn.value` and `call.value` use the same pairing.
Delegation forwards the same owner value, so a field path of a borrowed
receiver keeps the domain that owns the root place.

The owner domain is the domain that owns the place's relocatable storage.
Lowering records it per checked local: a `mut` parameter or `mut self` receiver
uses the hidden owner value; a take parameter of an affine type owns a
frame-local value and grows in the callee function domain, while a copyable
take parameter receives an ordinary copy; a by-value parameter's storage
remains in the caller's active domain until the callee materializes a copy; and
an ordinary local uses the frame domain. Growth uses the owner of the value actually
stored, and replacing a relocatable field through a borrowed place copies the
value into that place's owner with `copy_to_domain` before the store. A returned
value still goes through caller-result copying, and a caller-result local uses
the caller-result domain for a later growth.

A local always keeps one owner for its function, so a structured join never
mixes runtime owners: the frame domain is the nearest domain that dominates
both paths, and a value that may escape is copied to caller-result storage at
the return. The D023 report records the value copies that materialize a local
from a borrowed field. Diagnostic 333 and the functional-builder workaround are
retired.

A C export signature never carries a `safe_mut` parameter or an owner domain;
the verifier rejects a `c_export` function with a borrowed parameter. Callback
trampolines likewise cross the C ABI with no `mut` or owner parameter. The
owner relation is a compiler-internal MIR contract, not a source lifetime
annotation, and `vec(T)` still carries no domain.

## Cleanup Operations

```text
cleanup.scope.begin -> cleanup_scope
cleanup.push scope, function(arguments...) [place local %x] -> cleanup_id
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

A nominal `Cleanup` hook is registered with `place local %x`, naming the
owner's local slot. `cleanup.scope.run` loads that local immediately before
each hook invocation, so the hook observes the owner's value at scope exit
rather than a copy captured at registration. This is what makes a `mut self`
method's updates visible to cleanup:

```text
%id = cleanup.push %scope, @cleanup, (%owner) place local %held
...
%ref = borrow_mut local %held
call @poke(%ref, %value)     ; the hook sees the updated %held
cleanup.scope.run %scope
```

The place must be a local of the registering function, or a frame field of a
suspending instance whose registration spans a suspension point (see
[Suspending Instances and Step Frames](#suspending-instances-and-step-frames)),
and its type must match
the hook's owner parameter, which is the last argument (a hook emitted for a
function with storage carries a hidden leading domain parameter). A whole-local
store to a registered place while the registration is active is rejected: it
would replace the value the hook loads and abandon the old owner. Field stores
through a `borrow_mut` remain legal. Builtin releases (table and `c_string`
shells, and the per-element `Vec` drain) do not carry a place and keep their
registration-time capture semantics.

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

## Integer Overflow Methods

MIR 6 also exposes the integer overflow modes as ordinary operations 71-79,
produced only by named builtin method calls on integer receivers
(`add_checked`, `sub_checked`, `mul_checked`, and their `saturating` and
`wrapping` forms):

```text
int.add.try a, b -> option(T)
int.sub.try a, b -> option(T)
int.mul.try a, b -> option(T)
int.add.sat a, b -> T
int.sub.sat a, b -> T
int.mul.sat a, b -> T
int.add.wrap a, b -> T
int.sub.wrap a, b -> T
int.mul.wrap a, b -> T
```

All nine take two operands of the same integer type and none may fail: the
`try` forms yield `none` on overflow and `some` with the wrapped result
otherwise, the `sat` forms clamp at the type's boundary, and the `wrap`
forms wrap on the two's-complement pattern. Unlike `int.add.checked`, these
operations are total and carry no failure edge. The verifier rejects them on
mismatched operand types, non-integer operand types, and `try` results not
consumed as `option(T)` of the operand type.

## Total Bitwise Operations

MIR 6 exposes the total bitwise family as operations 103-106:

```text
int.and a, b    int.or a, b    int.xor a, b    int.not a
```

Both binary operands share one integer type and the result carries that type;
`int.not` is the unary complement of its integer operand. All four operate on
the type's fixed-width two's-complement representation and none carries a
failure edge. The verifier rejects mismatched operand types, non-integer
operands, and a failure edge attached to any of them. The CString slice
claims 98-101 and `str.display` is 102, so the bitwise family starts at 103;
later slices take new numbers from their reserved ranges instead of
renumbering these operations.

## Float Arithmetic

MIR 6 exposes the plain IEEE-754 float arithmetic as operations 91-94:

```text
float.add a, b    float.sub a, b    float.mul a, b    float.div a, b
```

Both operands share one `f64` or one `f32` type and the result carries that
type. None of the operations carries a failure edge, and none ever fails:
`float.add`, `float.sub`, and `float.mul` compute the IEEE result for every
operand pair, and `float.div` is defined for a zero divisor — the quotient is
the signed infinity with the XOR of the operand signs, and NaN when both
operands are zero or either operand is NaN (decision D026). The C backend
realizes the zero-divisor contract through the `alder_f64_div`/`alder_f32_div`
runtime helpers; the verifier rejects the operations on mismatched or
non-float operand types. Comparisons on the same types are `float.eq` through
`float.ge` in the comparisons section below.

## Byte-Sequence Methods

MIR 6 also exposes the byte-sequence surface as operations 80-85, produced
only by named builtin method calls on `string` and `bytes` receivers (`len`,
`byte`, `concat`, `slice`, `to_bytes`, and `to_string_checked`):

```text
str.len a -> u64
str.byte.checked a, b else edge -> u8
str.concat domain, a, b else edge -> T
str.slice.checked domain, a, lo, hi else edge -> T
str.to_bytes a -> bytes
str.from_bytes domain, a else edge -> option(string)
```

A `string` is a sequence of UTF-8 bytes and `bytes` is a sequence of raw
bytes; every length and index below counts bytes. The receiver type `T` of
`str.concat` and `str.slice.checked` is the operand type: both operands of
`str.concat` and the `str.slice.checked` base must have that same type, and
`str.byte.checked` and `str.slice.checked` take `u64` indices. `str.len`
reports the byte count. `str.byte.checked` fails when the index is at least
the length. `str.slice.checked` fails when `lo > hi` or `hi` exceeds the
length. `str.concat` and `str.slice.checked` allocate a fresh sequence of
type `T` in the domain and fail only when that allocation fails.
`str.to_bytes` reinterprets a string's bytes without copying and cannot
fail. `str.from_bytes` validates UTF-8: invalid input yields `none` as an
ordinary value, while only allocation failure takes the failure edge; a
`some` payload owns a fresh copy of the bytes in the domain. The verifier
rejects these operations on non-sequence operand types, on mismatched
sequence operand types within one operation, on non-`u64` indices, and on
`str.from_bytes` results not consumed as `option(string)`.

## Integer Conversion Methods

MIR 6 also exposes the integer conversion surface as operations 86 and 87,
produced only by named builtin method calls on integer receivers
(`to_T_checked` and `to_T_wrapping`):

```text
int.convert.checked a else edge -> option(T)
int.convert.wrap a -> T
```

Both take a value operand of any integer type and an explicit target type
operand `T`, mirroring `int.trunc`/`int.zext`/`int.sext`; the checker only
produces them for pairs where some receiver value does not fit `T`
(the total widening pairs lower to the existing `int.zext`, `int.sext`,
and `int.trunc` operations instead). `int.convert.checked` yields `some`
when the receiver value fits `T` and `none` otherwise, filling the option
payload through the same defined-cast shapes as the total forms;
`int.convert.wrap` always produces the low bits of the receiver on the
two's-complement pattern and cannot fail. The verifier rejects these
operations on non-integer operands, on a non-`option` result type for
`int.convert.checked`, and on `int.convert.wrap` results not equal to the
target type.

## C Scalar Conversion Methods

MIR 6 exposes the C-boundary scalar conversions as operations 88, 89, and 90,
produced only by named builtin method calls on receivers that live on one
side of the C boundary:

```text
c.num.try value, option(E)   (checked form; E is the scalar target)
c.num.wrap value, E          (wrapping form; integers only)
c.num.cast value, E          (total bare form)
```

The value operand has an Alder numeric type (`i8`..`u64`, `f32`, `f64`) or a
`c_raw` scalar; the target has the other kind. The endpoints must live on
opposite sides of the boundary and carry matching numeric classes: integer to
integer, `c_float` to `f32` (or the reverse), `c_double` to `f64` (or the
reverse), or the widening `c_float` to `f64`. `c.num.try` additionally
carries the whole option type as its target and accepts the checked integer
pairs plus the one narrowing float pair (`c_double` to `f32`); `c.num.wrap`
accepts only integer pairs; `c.num.cast` accepts every verified pair. The
verifier rejects operations whose endpoints share a world, mix numeric
classes, use a non-option result for `c.num.try`, or pair a target that does
not match the class rule above. The checker never emits a total-bare pair
that is lossy on some target: those calls become `c.num.try` or are rejected
at the source level.

## Ordering Comparison

MIR 6 also exposes the Order domain's sequence comparison as operation 91,
produced only by the builtin `less` method call on `string` or `bytes`
receivers:

```text
str.order_lt a, b -> bool
```

Both operands must have the same sequence type: `string` compares UTF-8
bytes and `bytes` compares raw bytes, both in unsigned byte-lexicographic
order with the shorter prefix ordering first, so an empty operand orders
before every non-empty operand of its type. The operation cannot fail and
produces `bool`. Integer and `bool` receivers of the builtin `less` call
lower to the existing `int.lt` and branch shapes instead; the verifier
rejects `str.order_lt` on non-sequence operand types, on mismatched
sequence operand types within one operation, and on results not of type
`bool`.

## C-String Ownership

MIR 6 exposes the `c.CString` surface as operations 98-101, produced only by
the `c.CString` constructor and the owner's `ptr` borrow:

```text
c.string.make_lit a else edge -> c_string
c.string.make a else edge -> option(c_string)
c.string.ptr a -> c_const_ptr(c_char)
c.string.release a
```

Slot `a` is a `string` value for `make_lit`, a `string` or `bytes` value for
`make`, and a `c_string` value for `ptr` and `release`. `make_lit` copies a
String the checker proved free of interior NUL bytes, so the operation's only
failure is allocation; `make` scans arbitrary text or exact bytes, produces
`none` when an interior NUL is found, and takes the same allocation-failure
edge on success paths. Both
constructors are checked operations and therefore require the explicit
`else` edge. `ptr` borrows the NUL-terminated buffer for the owner's
lifetime without consuming it and yields `c_const_ptr(c_char)`, which is why
several borrows may compose in one call sequence. `release` frees the
buffer and binds no result; lowering emits it only inside the synthesized
per-type cleanup shell that a `using` registration pushes, so a program
cannot spell a release directly.

A registered `c_string` owner is an affine resource: transferring it out of
its scope (a plain return, an aggregate or `Option`/`Result` constructor, a
`take` argument, or a match scrutinee) emits `cleanup.disarm` for its entry
on that path before the owner leaves. The scope still runs its remaining
entries at exit; a disarmed entry never runs. The verifier requires a disarm
entry to be active on every path that reaches it.

The verifier rejects `make_lit` with a non-`string` slot, `make` with a slot
that is neither `string` nor `bytes`, `ptr` with
a non-`c_string` slot, `release` with a slot that is not a `c_string`, a
`release` that binds a result, a `make` result that is not
`option(c_string)`, a `make_lit` result that is not `c_string`, and a `ptr`
result that is not `c_const_ptr(c_char)`.

## Call-Scoped Buffer Borrows

MIR 6 exposes the call-scoped buffer borrow as operation 107, produced only
as a raw binding-call argument:

```text
c.buffer.ptr a, P
```

Slot `a` is a `bytes` value or a `slice(u8)`/`safe_mut(u8)` value, and the
type operand `P` is the declared `c_ptr(T)` or `c_const_ptr(T)` parameter type.
`T` must be a byte-addressable C pointee: `c_raw` with a char-width scalar
(`c_char`, `c_schar`, `c_uchar`) or an opaque `c_named` type. The operation
reads the buffer's data pointer, binds no failure edge, and produces `P`.

MIR does not distinguish an immutable `[U8]` view from `MutSlice(U8)`: both
lower to `slice(u8)`. The checker owns the rule that an immutable buffer can
satisfy only `c_const_ptr(T)` and that one buffer is not borrowed mutably
twice in a call. The verifier checks the operand and pointee shapes. The C
backend substitutes the runtime's non-null one-byte dummy when the buffer's
data pointer is null, so an empty buffer still reaches C as a valid address.
The pointer is valid only for the call; no other operation may consume it or
store it as an ordinary value.

## Byte-View Conversion

MIR 6 exposes the byte-view conversion as operation 120:

```text
slice.to_bytes domain, view else edge -> bytes
```

`view` is a `slice(u8)` value and the result is a fresh `bytes` value holding a
copy of the view's bytes in the domain. The operation reads the view's data
pointer and length, allocates the copy, and takes its failure edge only when
that allocation fails; an empty view allocates the runtime's one-byte
non-null buffer like every other empty owning sequence. The verifier rejects a
view of any other element type, a domain operand that is not a
`domain_handle`, and a result that is not `bytes`.

## Retained Callback Owners

MIR 6 exposes retained callback registrations as operations 112 and 114:

```text
c.callback.owner.register @function, set_binding, clear_binding, wait_binding, context, owner_type
c.callback.owner.release owner, clear_binding, wait_binding, owner_type
```

The register result is `option(owner)` for the callback-owner type; the
`owner_type` records the copied context type as `elem` and the callback
function-pointer type as `result_type`. The three binding operands are raw fn
declarations. The release form is emitted only inside the synthesized release
function for a `using` registration. `c_callback_owner(context, callback)`
prints as a type, and the owner's context address is stable across owner moves.

## Pointer Places

Pointer member access and whole-value C memory reuse the existing `deref` and
`field` places instead of adding operations. A `deref` place whose value has
type `c_ptr(T)` or `c_const_ptr(T)` denotes the pointee, and a `field` place
over a `c_named` record class resolves its field by Alder name through the
record's `c_field` parts. A `c_ptr` deref is a mutable place and a
`c_const_ptr` deref is read-only, so `store` through a const pointer deref is
rejected. `load` yields the pointee value, `store` writes one, and the C
backend emits `(*p)` with a const-qualified pointee for `c_const_ptr` and the
verified C field spelling for a named field. No null check is emitted: the
program is responsible for a non-null, aligned pointer whose storage lives
across the access.

## Zero-Initialized C Values and Local Addresses

MIR 6 exposes `c.Zero` and `c.addr` as operations 109 and 110:

```text
c.zero T
c.addr place, P
```

`c.zero` takes only its type operand `T`, which must be a `c_raw` scalar or a
by-value `c_named` scalar or record, and produces that type. The C backend
emits a compound literal `(T){0}` for a record and the literal `0` for a
scalar, so every record member is zeroed by C semantics. The verifier rejects
any other type operand.

`c.addr` forms the address of a place under the declared C pointer type `P`.
`P` is `c_ptr(T)` or `c_const_ptr(T)`, the place's own type must be exactly
`T`, and the place must walk back through fields to a local; a `c_ptr(T)`
target additionally requires a mutable place. The result is `P`. The pointer
is a raw call argument for one call and never an ordinary value. The
verifier rejects a pointee mismatch, a type operand that is not a C pointer, a
place that is not rooted at a local, and a read-only place for `c_ptr`.
Nullity, alignment, and lifetime are the unsafe caller's obligation: the
operation emits no null check.

## Size and Alignment Queries

MIR 6 exposes `core.memory` queries as operations 113 and 115:

```text
type.size T
type.align T
```

Both operations take one valid lowered type operand `T` and produce `u64`.
They are compile-time facts about the target C representation: the C backend
emits `(uint64_t)sizeof(T)` or `(uint64_t)_Alignof(T)` for the lowered type.
`Unit` is the fixed exception, emitted as the literal `0` for size and `1` for
alignment even though its C storage spelling is `uint8_t`. The verifier rejects
a missing or out-of-range type operand. The operations carry no value operand,
no failure edge, and no runtime work.

## Structural Hashing

MIR 6 exposes the `core.hash` structural hash as operation 116:

```text
hash.value key0, key1, value, T
```

`key0` and `key1` are `u64` SipHash key words, `value` is a value of the
concrete structural type `T`, and the result is `u64`. The verifier requires
`T` to lie in the structural hash domain: `Bool`, signed and unsigned
integers, `String`, `Bytes`, `Option`/`Result` over that domain, and records
or enums whose components are in it. Floats, pointers, views, collections,
and identity-bearing resources are rejected. The C backend writes the
canonical encoding from [the core.hash snapshot](api/core.hash-v1.md)
through the runtime SipHash-1-3 helpers; no padding or pointer value enters
the stream.

## C Callback Values

MIR 6 exposes one nonretained callback construction as operation 111:

```text
c.callback.make @function, callback_type -> callback
```

The target is a function ID and the type operand is a callback-class
`c_named` type whose C spelling is a function-pointer typedef. The result is
the callback value passed as one raw-call argument; it is never stored. The
verifier requires a valid target function and a callback-class `c_named`
result. The C backend emits a static trampoline for each distinct pair and
uses its address as the value. Bindings print callback members as
`c_type callback @Name = "spelling"`.

## Text Display

MIR 6 exposes the Display domain's formatting as operation 102, produced
only by the builtin `display` method call on a domain receiver:

```text
str.display a, b -> string
```

Slot `a` holds the domain handle and slot `b` holds the value, which the
verifier checks against the widened operand types `bool`, `i64`, or `u64`:
the lowering extends signed receivers to `i64`, unsigned receivers to
`u64`, and keeps `bool` raw, so `I8`-`I32`, `U8`-`U32`, and the 64-bit
scalars all reach one operation. The operation always produces a fresh
`string` owned by the domain and carries a checked edge that fires when
the result allocation fails. `String` receivers of the builtin `display`
call lower to the receiver value itself, so no `str.display` instruction
exists for them. The verifier rejects `str.display` on a domain operand
that is not the domain handle, on value operands outside `bool`, `i64`,
and `u64`, and on results not of type `string`.

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
table.insert.try table, value -> result(id(element_type), element_type)
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

`table.insert.try` carries no failure edge: exhaustion or the capacity policy
surfaces as the result value, whose `ok` payload is the fresh id and whose
`err` payload is the element value handed back to the caller. The verifier
therefore treats the result's lifetime as derived from the element operand
(not from the table), and `table.insert.try` counts as a table mutation for
the live-view rules exactly like `table.insert` and `table.remove`.

## Constants

Modules declare named constants; instructions materialize them with `const.get`. The initial vocabulary has no immediate operands.

```text
const @name: type = literal
```

Constant types are `unit`, `bool`, integer and float primitives, `string`, and
`bytes`; private source-bootstrap constants may additionally use `slice(u8)`.
Integer literals are decimal `i64`-range values; floats print with
shortest-round-trip formatting. An `f32` constant must be finite and exactly
representable in binary32; the verifier rejects any other bit pattern, and
the source checker enforces the same rule on `F32`-typed float literals
(diagnostics 255 and 256), so a literal never rounds silently. Quoted
`string` payloads must be valid UTF-8,
while quoted `bytes` payloads preserve every decoded byte.

`u64` constants carry the full unsigned range. Values that fit `i64` print
and parse as ordinary decimals; values outside the `i64` range are stored as
their 64-bit two's-complement pattern and print as the unsigned decimal
reading of that pattern, and the parsers accept unsigned decimals up to
2^64-1 for `u64` constants only.

## Calls and C FFI

```text
call function(arguments...) -> result
ffi.call.unsafe import(arguments...) -> result
```

Imported declarations currently record the import name (also the C symbol) and a concrete signature. The C backend accepts only backend-safe C identifiers: C keywords, generated/runtime prefixes, names beginning with `_`, macro-style uppercase names, header tokens such as `bool` and `offsetof`, functions declared by always-included headers, `main`, and names ending in the reserved typedef suffix `_t` are rejected. The accepted name is emitted unchanged, never sanitized into a potentially colliding symbol. Retention, const, and cleanup claims for foreign pointers are deferred to a later MIR version; until then, safe wrappers carry that responsibility.

A source-level `export c fn` adds no MIR operation and no textual marker. The
lowered function keeps its ordinary ID-derived name; the compiler records its
source symbol and export intent as function metadata, and the C backend uses
that metadata to emit a non-static wrapper under the Alder name. Verification
and the printed MIR contract are therefore unchanged by exports.

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

A closure environment record is one aggregate per site and records the domain
that owns it as its first field; the thunk loads that field in its prologue and
uses it as its active and result domain, so a nested environment or a storage
copy is materialized beside the outer record instead of in a frame domain the
thunk does not have. A closure with no captures has no environment record, so
its thunk takes the caller's domain as a leading hidden parameter, the same way
a named function value carries it. A capture that carries storage is
deep-copied into that domain at creation and into the destination domain when
the record is retained; a function-valued capture is retained recursively. For
the loop-survival rule such a record is an owning value: its domain field names
the domain that owns the record, not a borrowed capability. Three conservative
rules are narrowed for such a record and for nothing else: a domain handle in a
dereference store is accepted when the stored value is an aggregate used as a
`fn.value` environment, `alloc` of that aggregate is accepted, and the
local-store rule that confines a type containing a `slice`, `safe_ref`, or
`safe_mut` to a local place no longer applies to the record. This is sound
because the record is allocated in the domain its field names, every
cross-domain move goes through the retain hook, which rewrites the field to the
destination domain, and the record never outlives its domain; the field is only
ever used as an allocation parent. The third narrowing is sound because a
captured view is a header, not owned storage: the checker accepts such a
capture only when the closure cannot escape the scope that owns the viewed
storage, so the storage outlives every call the closure value can reach, and
the record's view field is never dereferenced after that scope ends.

A function value that leaves its creating frame is retained.
`copy_to_domain` of a function type produces a complete, independent value in
the destination domain through the backend's per-environment retain hook, so
the copy severs the source's provenance exactly as it does for a slice, a
vector, or an aggregate. This is sound only because the hook makes the copy
complete: it allocates a fresh environment record in the destination domain,
rewrites a captured domain handle to that domain, and retains every
function-valued capture recursively. Closure captures are storage-free apart
from a captured view, which is a header copied as a header, so a shallow record
copy of the remaining fields is complete. A function value
returned without such a copy still shares its environment, so phase 6 rejects
the exit when the environment's owning domain was destroyed.

## Suspending Instances and Step Frames

A monomorphized function instance whose concrete capability types are all
`BlockingIo` keeps the direct lowering. Every other instance is a *suspending
instance* and lowers to one frame record plus one step function before backend
MIR. The split adds no suspension terminator and no new control-flow form: a
step function is an ordinary MIR function, suspending is an ordinary `return`,
and resuming is an ordinary re-entry dispatched on the frame's state tag. The
representation family is fixed by
[D029](design-decisions.md#d029--suspension-lowers-to-plain-cfg-mir-before-the-c-backend);
the C side of the contract is in
[C11 Backend](c-backend.md#step-trampolines-and-the-task-runtime).

### Step function and status type

For a suspending instance `@<instance>` the lowering emits three declarations
with reserved, collision-free names. The reserved prefix `__alder_step.` is
compiler-owned and reserved against ordinary source, like `__s0_`:

```text
enum  @__alder_step.state.<instance>   { entry, resume0, resume1, ... }
type  @__alder_step.frame.<instance>   { ... }
fn    @__alder_step.run.<instance>(...) -> @__alder_step.status
```

One module-level status enum is emitted when a module contains step functions:

```text
enum @__alder_step.status {
  done
  call
  park
  cancelled
}
```

The variant order is fixed as `done`, `call`, `park`, `cancelled`; the C
status values 0 through 3 use the same order, so the thunk's mapping is a
direct tag read rather than a name comparison.

The step function has exactly this MIR signature:

```text
fn @__alder_step.run.<instance>(
    %d: domain_handle,
    %frame: safe_mut(@__alder_step.frame.<instance>),
    %frame_owner: domain_handle,
) -> @__alder_step.status
```

- `%d` is the activation's own storage domain. It is the leading hidden
  domain required by the ordinary storage model, so result copies and fresh
  allocations use it.
- `%frame` is the one-element checked reference to the activation's frame
  record. It follows the ordinary borrowed-place pairing rule: the next
  parameter is the domain that owns the frame.
- `%frame_owner` is the activation domain that owns the frame. For a step
  activation `%d` and `%frame_owner` are the same handle; the lowering passes
  the same value twice because the storage-model convention and the
  borrowed-place owner rule are separate contracts.

The result variants are:

- `done`: the activation finished. Its result value is in the frame's `out`
  field. The executor pops the activation; the caller, if any, reads `out`.
- `call`: the activation prepared a callee activation and yielded. The frame
  has stored the callee frame reference and owner domain in the suspension
  point's `x<i>` and `y<i>` fields, and the frame state is `resume<i>`. The
  generated trampoline publishes the callee; the executor pushes it and runs
  it. The caller is not resumed until the callee returns `done`.
- `park`: the activation is waiting for an external wakeup. The caller has
  already registered the task's wakeup token with the operation that will
  signal it. The executor parks the task; a wakeup makes the task runnable
  again and re-enters the same activation at its saved state.
- `cancelled`: the activation observed cancellation and completed its teardown
  without a user result. `out` is not initialized. The executor pops the
  activation and keeps the task's cancel flag; the caller is resumed at the
  state's cancellation edge, never on the value path.

A step function never calls another step function. Every potentially
suspending call is a `call` handoff to the executor's activation stack, so
logical recursion consumes task storage, not worker C stack. Ordinary
non-suspending calls remain ordinary `call` instructions inside one
activation.

The generated C trampoline is one static function per step function with the
pinned `AlderStepFn` signature and a stable symbol
`alder_step_<name-fragment>_<function-id>`, matching the ordinary function
naming convention with a distinct prefix.
It adapts the opaque frame pointer to the typed frame, calls the internal
static MIR body, maps the status enum to `AlderStepStatus`, and, for `call`,
uses the state tag to publish the callee thunk, frame, and domain. The state
table is derived mechanically from the frame layout and the state enum; it is
not extra MIR.

### Frame records

`@__alder_step.frame.<instance>` is an ordinary aggregate type with fields in
this exact order. Omitted groups produce no field:

1. `state`: `@__alder_step.state.<instance>`. Always first.
2. `p<i>`: one field per source parameter after monomorphization, in
   declaration order. The hidden leading domain parameter is not a source
   parameter. A borrowed parameter is followed immediately by
   `o<i>: domain_handle`, its owner domain.
3. `x<i>`: one per call-handoff suspension point, in source order over the
   call-handoff points only (dense over call points, independent of the state
   numbering), a `safe_mut(@__alder_step.frame.<callee>)` reference to the
   callee frame.
4. `y<i>`: for the same points, the callee activation's `domain_handle`.
   `x<i>` and `y<i>` are adjacent and in call-handoff source order. A park
   point saves no pair; the binding between a state and its pair is the pair
   its suspend block saves, never the resume suffix.
5. `d<i>`: one `domain_handle` for each `domain.create` site whose handle is
   live across a suspension point, in create-site order.
6. `l<i>`: one field per MIR local live across a suspension point, in MIR
   local-ID order.
7. `v<i>`: one field per SSA temporary live across a suspension point, in
   MIR value-ID order.
8. `c<i>`: one `cleanup_id` live across a suspension point, in registration
   site order.
9. `s<i>`: one `cleanup_scope` for each frame-resident `cleanup.scope.begin`
   site whose scope spans a suspension point, in begin-site order.
10. `out`: the instance's result type. Always last.

`<i>` in a field name is its zero-based decimal index, so the literal names are
`p0`, `p1`, `o0`, `x0`, `y0`, `d0`, `l0`, `v0`, `c0`, `s0`, and `out`; state
variants use the same spelling (`entry`, `resume0`, `resume1`, ...). A
unit-typed source parameter is omitted from the frame, matching the C ABI rule
that drops unit parameters. A borrowed parameter's `p<i>`/`o<i>` pair is the
step's parameter pair: the verifier applies the ordinary borrowed-place and
owner-domain rules to the pair, including when the step forwards the borrowed
value to a call.

"Live across a suspension point" means a path from the point's resume block to
a use exists with no intervening redefinition. Locals and temporaries that are
not live across any suspension point stay ordinary step-function locals and
do not appear in the frame.

Suspension point numbering is source order after monomorphization: the
evaluation order of potentially suspending calls, `await`s, channel
operations, and suspending cleanup hooks in the function body. A call that can
never suspend is not a suspension point. Nested blocks and match arms are
numbered by their source position, not by visit order of the lowering.

Hidden, non-MIR frame slots follow the MIR-visible fields in the generated C
struct, in this order:

- `alder_domain_<site>`: one inline `AlderDomain` for every frame-resident
  `domain.create` site, in site order;
- `alder_scope_<site>`: one inline `AlderCleanupScope` for every
  frame-resident `cleanup.scope.begin` site, in site order.

These slots are the existing hidden per-site objects relocated from the C
function frame into the frame record. They are not MIR values: the domain
handle `d<i>` points at its slot, and the cleanup handle produced by the
adopting `cleanup.scope.begin` points at its slot. Their names and order are
deterministic and inspectable in the generated C.

Frame allocation and ownership:

- The caller of a step activation creates the callee activation domain as a
  child of its own activation domain (`domain.create %frame_owner`), allocates
  the callee frame in that domain with
  `alloc %child_domain, @__alder_step.frame.<callee>, %one`, initializes
  `state` to `entry` and the parameter fields, and stores the frame reference
  in its own `x<i>` and `y<i>` fields.
- A spawned task's root frame is allocated the same way by the spawn site in a
  child domain of the spawning activation domain; the task runtime borrows
  both until `alder_task_release`.
- Frames are never embedded by value, never returned, and never stored in
  another aggregate, vector, or table. One activation owns exactly one frame
  in exactly one activation domain.
- When a call activation returns `done`, its caller copies `out` into its own
  domain with `copy_to_domain`, then destroys the callee activation domain.
  When the activation is canceled, the caller destroys the callee domain after
  the callee has finished its own teardown and been popped. The transfer
  follows the ordinary caller-result rules: relocatable values are
  materialized in the caller domain, copy-trivial and move-delivered values
  are bit-copied, and the callee's return path disarms the owner it returns.

An activation domain lives exactly as long as its activation. Nested
non-suspending calls and loops keep their own hidden domains under the
existing storage rules, so their transient storage is reclaimed before the
activation ends. A value that the inference retains in the activation domain
is reported as retained storage (D004) and is reclaimed when the activation
ends; a long-lived task therefore measures its retained activation storage
under gate 9.8 rather than silently accumulating unmeasured memory.

For this purpose the frame record is the only aggregate exempt from the
ordinary declaration, allocation, and dereference-store restrictions on
`safe_mut`, `safe_ref`, `slice`, `domain_handle`, `domain_mark`,
`cleanup_id`, and `cleanup_scope` fields, and it may not be used as any other
value type. Section "Frame access and verification" pins the exact rules.

### State numbering and dispatch

The state enum is numbered in this order:

1. `entry` (ordinal 0);
2. `resume0`, `resume1`, ... one per suspension point in the source order of
   the section above;
3. `cleanup0`, `cleanup1`, ... one per suspension point that occurs inside a
   cancellation or scope-exit teardown region, ordered by the resuming state
   they belong to (ascending) and then by reverse registration order within
   that teardown.

The caller initializes `state` to `entry` before the first step. Every step
function begins with one dispatch block:

```text
bb0:
  %s = load field(deref %frame, state)
  switch %s {
    entry -> bb_entry
    resume0 -> bb_resume0
    ...
  }
```

`bb0` has no other predecessor, so it dominates every branch, and the frame
parameters `%d`, `%frame`, and `%frame_owner` are available everywhere. A
resume block has exactly one predecessor, the dispatch case, and no other
edge may target it.

Each suspension point has a canonical suspend block and a canonical resume
block. A call handoff stores the state and the saved fields in frame field
order and returns `call`:

```text
bb_suspend_<i>:
  %s = enum.construct @__alder_step.state.<instance>, resume<i>
  store field(deref %frame, state), %s
  store field(deref %frame, x<i>), %callee_frame
  store field(deref %frame, y<i>), %callee_domain
  ...store d*, l*, v*, c* fields in frame field order...
  %st = enum.construct @__alder_step.status, call
  return %st
```

A park point stores the same kind of state and saved fields and returns
`park`; it has no `x<i>`/`y<i>` fields. A resume block checks cancellation,
loads the saved fields its suspend block stored, in the same field order, and
continues:

```text
bb_resume_<i>:
  %c = c.call.unsafe @task_cancelled()
  branch %c, bb_cancel_<i>, bb_after_<i>

bb_after_<i>:
  ...load x<i>, y<i>, d*, l*, v*, c* in frame field order...
```

The verifier checks each state's store list and load list are equal as ordered
field sets. The lowering has no freedom to store a different set on different
paths to the same suspension point; a conditional save is represented by two
suspension points. This makes the cross-state initialization contract
syntactic rather than a general dataflow problem.

The state also selects the callee in the generated trampoline: state
`resume<i>` with a call-type point maps to the step thunk whose frame type is
the element type of `x<i>`, passing `x<i>` and `y<i>`. The lowering records
that callee FunctionId in the step's metadata, so the mapping is an ID lookup,
not a name match. A `call` return from any other state is a lowering contract
violation reported by the trampoline.

### Frame access and verification

The frame record is an aggregate type with one legal use: the trailing
`safe_mut` parameter of exactly one step function, plus `alloc` inside step
functions and spawn lowering. The verifier recognizes a step function by the
reserved name and the pinned three-parameter signature; a
`@__alder_step.frame.*` type that is not the frame of exactly one such
function, or a step function with a different signature shape, is rejected.
The verifier adds these rules; they accept new shapes and do not change the
meaning of any existing MIR 6 module:

- the frame record may contain slice and checked-reference views, domain
  handles, domain marks, and cleanup-id fields; the ordinary aggregate
  declaration restrictions for those kinds do not apply to it. Ephemeral
  table views remain excluded: they cannot complete a table access region
  across a suspension;
- `alloc %d, @__alder_step.frame.<instance>, %n` is accepted with `%n == 1`
  even though the element type recursively contains view and handle kinds.
  Two allocation patterns are legal inside a step function: a call handoff
  allocates the callee frame in a child domain of the allocating step's
  activation domain and stores the reference once into the allocating step's
  own `x<i>`; a spawn site allocates the spawned root frame in a child domain
  of the allocating step's activation domain and consumes the reference as
  the frame operand of `task.spawn`, with no `x<i>` store. An alloc outside
  both patterns, or outside a step function, is rejected;
- `load` and `store` through a frame field place are accepted for every field
  type. A handle-typed load keeps the direct identity anchored to the
  (activation, field) pair; it is not a new dynamic identity on every entry.
  A view-typed field keeps the provenance of the value stored into it;
- a frame field place may not be aliased out into an ordinary local, aggregate,
  vector, table, or function result, and a frame record may not escape its
  activation; a value loaded from a frame field follows the ordinary rules for
  its type;
- `x<i>`/`y<i>` is a borrowed-place pair whose owner is `y<i>`. The frame
  itself lives in `%frame_owner`, but the view points into the child
  activation domain `y<i>`; the verifier tracks the pair separately from the
  frame's own owner, exactly like a `safe_mut` parameter and its owner;
- `domain.create` and `cleanup.scope.begin` sites in a step function are
  frame-resident when their value spans a suspension. `domain.create` is
  executed once by the state that creates it and its handle is saved in
  `d<i>`. A frame-resident `cleanup.scope.begin` is emitted at the scope's
  lexical start and again at the start of every resume block lexically inside
  that scope, in outer-to-inner scope order. Each emission is the same
  adopting begin on the same frame slot: it initializes the scope on the
  first entry and returns the existing frame-resident scope on a resume.
  Every emission stores its result into the scope's `s<i>` field before use,
  and the verifier anchors all emissions storing the same `s<i>` to one
  dynamic scope, so the handle dominates the segment's uses and the lexical
  `cleanup.scope.run`/`end` still execute at the source scope's exit. The
  anchor is the field, not an SSA store count: the canonical save-list store
  of `s<i>` at a suspend block and the adopting-begin stores at every resume
  or `cleanup<j>` teardown state lexically inside the scope all belong to that
  one dynamic scope. `cleanup<j>` states re-adopt the scopes they are inside
  exactly like resume states, in outer-to-inner order. `s<i>` participates in
  the state-indexed save/load equality like every other saved field; the
  equality is over ordered field sets, so a field stored more than once in
  one suspend block (the begin's own store plus the save-list store) counts
  once in that block's save set;
- the frame is the activation's stable storage across states. A frame field
  of a capability or handle kind may be carried across a state as a local
  place, subject to the state-indexed store/load equality above and to the
  ordinary invalidation rules for a reset or destroy that reaches it. A load
  from a frame field is accepted when the matching suspend block stores that
  field in its canonical save list; the verifier seeds the resume state with
  exactly that list, so no general cross-state dataflow is required;
- a domain handle stored in `d<i>` is invalid after its domain is destroyed
  on every path, exactly like any other handle. The verifier's per-state
  tracking replaces the single-function C-slot assumption: the frame slot is
  stable storage for the activation, re-initialized in place when the source
  re-creates it, not a C stack slot whose address changes per call;
- a cleanup scope spanning a state keeps its registrations in the runtime
  entry list. The verifier records, per state, the active cleanup-scope
  fields and registered cleanup ids, and a resume begins in the recorded
  state. A registration whose owner spans a state names a frame field as its
  `cleanup.push` place, so the runtime context points into the frame and the
  hook observes the value the frame holds at scope exit. `cleanup.scope.run`
  must still precede `cleanup.scope.end` on every exit path, and reverse order
  and at-most-once are checked against the recorded list;
- the step function's `return` always returns a status variant. A state is
  call-type exactly when its suspend block saves an `x<i>`/`y<i>` pair, and
  park-type otherwise; the classification reads the saved pair, including for
  `cleanup<j>` states, and never infers the kind from the resume suffix.
  `call` requires the current state to be a call-type `resume<i>` or
  `cleanup<j>` with matching `x<i>` and `y<i>`; `park` requires a park-type
  `resume<i>` or `cleanup<j>`; `done` requires `out` to be initialized on every
  path that reaches it; `cancelled` requires no `out` and is reachable only
  from a cancellation teardown path. A `cleanup<j>` state is the suspension
  point of a suspending cleanup entry and follows the same dispatch,
  save/load equality, and cancellation-check rules as a `resume<i>` state;
- the cancellation check at a resume or cleanup-resume block entry is a
  binding call resolved to the runtime's `alder_task_cancelled` entry. The
  verifier recognizes cancellation observation by that resolved binding
  target, never by user spelling;
- `%frame` is used only as the base of `deref` field places; it may not be
  returned, stored, or passed as an operand.

These rules make the frame representation independent of C syntax. The
independent Alder MIR 4 encoding is unchanged: a frame is an ordinary
aggregate, its fields are ordinary type parts, and the state is an ordinary
enum value.

### Suspend and wakeup protocol

Every suspension point follows the same sequence:

1. Before starting the operation, the step checks cancellation. A canceled
   task branches to the state's teardown entry and starts no new operation.
2. The operation registers the current task's wakeup token with the runtime
   or the host shim. Registration happens before the operation can complete,
   so a completion that races the step sets the task's wakeup latch instead
   of being lost.
3. The step stores its state and saved fields and returns `park` or `call`.
4. The executor parks the task, or keeps it runnable when the latch was
   already set ("wake before park"). A wakeup only makes the task runnable;
   it never resumes a frame by itself. The top activation is re-entered at
   its state, and the resume block observes the operation's result or
   cancellation.

Mechanism-specific rules:

- **Park marker.** `alder_task_park()` is a compiler-recognized runtime
  binding that marks a park suspension point. The wrapper registers the
  wakeup first, then calls the marker; the splitter lowers that call to the
  canonical park save and `return park`, and no C call to it is ever emitted.
  The runtime declares it but does not define it. A marker call without a
  prior wakeup registration, or outside a step function, is a contract
  violation. The verifier recognizes the marker by its resolved binding
  target, exactly like the cancellation observation. The checker admits the
  marker as the second runtime-namespace binding exception (after
  `alder_task_cancelled`) and records the call as a park suspension fact for
  the splitter; the registration-precedes-marker order remains a lowering
  and runtime contract.
- **Capability operations.** A capability wrapper written against `I: Io`
  lowers its suspending instance to a step function whose leaf calls the
  host shim: start the operation and register the token, then `park`; on
  resume, poll or finish the operation and write its result. The shim owns
  the host-specific handle and the cancel/join contract. A completion may
  signal from a foreign thread through the thread-safe wakeup token.
- **`await Task(T)`.** The parent calls `alder_task_await(task_id)`, which
  registers the parent as a waiter on the child task record and returns
  either "already complete" or "pending". Pending returns `park`. The child's
  completion signals the parent. On resume the parent reads the child root
  frame's `out` through its saved `x<i>` reference, copies it into its own
  domain with `copy_to_domain`, calls `alder_task_release`, and destroys the
  child activation domain. A canceled child delivers no value; the parent
  takes its cancellation edge instead of loading `out`.
- **Sleeps and timers.** `alder_timer_at(token, deadline)` registers an
  absolute deadline in executor-clock units. The timer queue signals the
  token at the deadline. A sleep that is already due signals immediately,
  which is the wake-before-park case. Cancellation removes the waiter or
  leaves an already-fired timer inert; the task record is not freed while a
  timer entry can still name it.
- **Channels.** A blocked sender or receiver enqueues a waiter holding its
  generational task id in the channel's group-owned state, then `park`s. The
  matching peer dequeues and signals the waiter through its task id after the
  queue update. A resumed
  operation retries its state, so a spurious or cancellation wake cannot
  corrupt the FIFO. Closing a channel signals every waiter; each resumes
  into its explicit closed result.
- **Cancellation.** `alder_task_cancelled()` is the only cancellation
  observation. It is checked at the entry of every resume block, before every
  call or park handoff, and by the explicit `check_cancel` checkpoint. A
  canceled task runs its teardown from the state it was in and returns
  `cancelled`; it never resumes user code after a suspension with the cancel
  flag set.

A wakeup token is one stable address inside the task record. It is valid from
task creation until the runtime has removed every registration and the task
record is released. Signalling is idempotent; a signal after the task is
already runnable only sets the latch.

### Cancellation, cleanup, and shielded teardown

Cancellation unwinds the activation stack from the top down. The top
activation observes the flag, runs its teardown, returns `cancelled`, and is
popped; then its caller observes the cancellation edge, destroys the released
callee domain, runs its own teardown, and is popped. The shield is task-wide,
so a `cancelled` return can only be produced while the caller's shield depth
is also zero; the caller's cancellation check therefore observes the flag and
cannot fall through to a value path. This is the reverse order of
activation, and within one frame it is the reverse registration order of the
cleanup scopes and their entries.

Teardown is entered with the task's shield raised:

- `alder_task_shield_push`/`pop` maintain a depth in the task record, not in a
  frame. The depth survives `park` and `call`, so a cleanup hook that joins
  children can suspend and resume while still shielded.
- While the depth is positive, `alder_task_cancelled()` reports false. The
  task may still terminate on an invariant failure; the shield suppresses
  repeated cancellation, not failure.
- The teardown path releases a completed callee activation domain, runs the
  frame's cleanup scopes innermost first, and only then pops its own
  activation. A scope's entries run in reverse registration order and at most
  once; `cleanup.scope.run` is a suspension point when a hook may suspend, and
  its cursor lives in the frame-resident scope object, so a suspended run
  resumes at the next entry rather than restarting. The splitter expands such
  a run into a cursor loop with one `cleanup<j>` state per suspending entry: a
  non-suspending entry runs in the current segment, a suspending entry is a
  call or park activation, and the run resumes at the next entry. A run with
  no suspending entries keeps the single instruction.
- A group's cleanup hook cancels its children, joins them, and releases their
  task records and activation domains. The join is a suspending call inside
  the shielded teardown. A child whose foreign operation cannot be interrupted
  keeps its state alive until C returns; the domain and task record are not
  freed before that.
- A capability operation's teardown drives its shim to a terminal state
  (completed, canceled, or joined) before the leaf activation returns `done`.
  The shim owns its host context and never points into the activation domain;
  if it needs a copy of a frame value it copies it into group-owned state. An
  uninterruptible C call therefore parks the shielded teardown until it
  returns instead of leaving a token that outlives the task.

No path frees a frame, an activation domain, or a task record while an
activation can still name it: the callee domain is destroyed only after the
callee activation has been popped and its result copied; the task record is
released only after its activation stack is empty, all wakeup and timer
registrations are removed, and any blocking-pool retain is released.

### Recursion

Recursion under one concrete capability is ordinary recursion of the same
suspending instance. Every call allocates a fresh activation domain and frame
in task storage; frames are never shared or reused by an activation. The
executor's activation stack grows and shrinks on the heap, so worker C stack
use stays constant with logical depth. The cost of a call is one frame record
plus one activation domain. A wakeup re-enters only the top activation at its
saved state; completion then propagates up the stack one popped activation
per executor round.

A recursive instance's frame references itself: its call-handoff field is
`x<i>: safe_mut(@__alder_step.frame.<self>)`. A frame aggregate may therefore
reference its own type through a `safe_mut` field, and the frame's name is in
scope inside its own declaration. This self-reference is reserved to
`@__alder_step.frame.*` types; it does not generalize to user aggregates, and
the verifier applies the ordinary frame rules to the self-referential field.

Recursion that changes the capability type is specialization-expanding and is
rejected before monomorphization, so it never produces a new step instance.

### Worked example

Source, with one potentially suspending call:

```text
fn size(I: type(Io), io: I, path: Path) -> Result(U64, IoError) {
    let text = try std.fs.read_text(io, path)
    return Ok(text.len())
}
```

The `Blocking` instance is direct MIR. The callee is the non-suspending
`read_text.Blocking` instance; the `try` is a switch on its result; `str.len`
and enum construction follow. Runtime calls and elided callee bodies are
written as `call @...` in these sketches; the real module reaches runtime
entries through binding blocks and `c.call.unsafe`. Supporting type,
constant, binding, and callee declarations are elided; the instruction,
terminator, place, and type spellings shown are the printed forms, and long
function headers are wrapped here for readability (the printer emits one
line).

```text
mir 6

const @one: u64 = 1

fn @read_text.Blocking(%d: domain_handle, %io: @Blocking, %path: @Path) -> result(string, @IoError) {
bb0:
  panic
}

fn @size.Blocking(%d: domain_handle, %io: @Blocking, %path: @Path) -> result(u64, @IoError) {
bb0:
  %r = call @read_text.Blocking(%d, %io, %path)
  switch %r {
    err(%e) -> bb_err
    ok(%text) -> bb_ok
  }

bb_err:
  %f = enum.construct result(u64, @IoError), err, %e
  fail %f

bb_ok:
  %n = str.len %text
  %o = enum.construct result(u64, @IoError), ok, %n
  return %o
}
```

The `Evented` instance is a step function. The frame carries the state, the
two parameters, the callee reference and owner, and `out`:

```text
enum @__alder_step.status {
  done
  call
  park
  cancelled
}

enum @__alder_step.state.size.Evented {
  entry
  resume0
}

enum @__alder_step.state.read_text.Evented {
  entry
  resume0
}

type @__alder_step.frame.read_text.Evented {
  state: @__alder_step.state.read_text.Evented
  p0: @Evented
  p1: @Path
  out: result(string, @IoError)
}

type @__alder_step.frame.size.Evented {
  state: @__alder_step.state.size.Evented
  p0: @Evented
  p1: @Path
  x0: safe_mut(@__alder_step.frame.read_text.Evented)
  y0: domain_handle
  out: result(u64, @IoError)
}
```

```text
fn @__alder_step.run.size.Evented(%d: domain_handle,
    %frame: safe_mut(@__alder_step.frame.size.Evented),
    %frame_owner: domain_handle) -> @__alder_step.status {
bb0:
  %state = load field(deref %frame, state)
  switch %state {
    entry -> bb_entry
    resume0 -> bb_resume0
  }

bb_entry:
  %cancelled = call @task_cancelled()
  branch %cancelled, bb_cancel0, bb_call0

bb_call0:
  %one = const.get @one
  %child_domain = domain.create %frame_owner
  %child = alloc %child_domain, @__alder_step.frame.read_text.Evented, %one
  %p0 = load field(deref %frame, p0)
  store field(deref %child, p0), %p0
  %p1 = load field(deref %frame, p1)
  store field(deref %child, p1), %p1
  %entry = enum.construct @__alder_step.state.read_text.Evented, entry
  store field(deref %child, state), %entry
  %resume = enum.construct @__alder_step.state.size.Evented, resume0
  store field(deref %frame, state), %resume
  store field(deref %frame, x0), %child
  store field(deref %frame, y0), %child_domain
  %call = enum.construct @__alder_step.status, call
  return %call

bb_resume0:
  %cancelled0 = call @task_cancelled()
  branch %cancelled0, bb_cancel1, bb_join

bb_join:
  %child0 = load field(deref %frame, x0)
  %r = load field(deref %child0, out)
  %own = copy_to_domain %d, %r
  %child_domain0 = load field(deref %frame, y0)
  domain.destroy %child_domain0
  switch %own {
    err(%e) -> bb_join_err
    ok(%text) -> bb_join_ok
  }

bb_join_err:
  %fe = enum.construct result(u64, @IoError), err, %e
  store field(deref %frame, out), %fe
  %done_err = enum.construct @__alder_step.status, done
  return %done_err

bb_join_ok:
  %n = str.len %text
  %fo = enum.construct result(u64, @IoError), ok, %n
  store field(deref %frame, out), %fo
  %done_ok = enum.construct @__alder_step.status, done
  return %done_ok

bb_cancel0:
  %st_cancel0 = enum.construct @__alder_step.status, cancelled
  return %st_cancel0

bb_cancel1:
  %child_domain1 = load field(deref %frame, y0)
  domain.destroy %child_domain1
  %st_cancel1 = enum.construct @__alder_step.status, cancelled
  return %st_cancel1
}
```

`bb_cancel1` is the teardown from `resume0`: the callee activation has already
been popped by the executor, so the callee domain can be destroyed. Teardown
would also run the frame's cleanup scopes in reverse order and raise the task
shield; the sketch omits those operations because this function has no
`using` registrations. The leaf `read_text.Evented` step is the park-only
case: its `bb_entry` starts the shim and returns `park` after storing
`resume0`, and its `bb_resume0` polls the shim, writes `out`, and returns
`done`.

### Operations and versioning

The frame and step representation itself needs **no new MIR operation and no
new format version**. It is written entirely in existing `mir 6` syntax:
frames are ordinary aggregates, states are ordinary enums, dispatch is
`switch`, suspension is `return`, and frame access is `load`/`store` through
`deref` field places. The only additions are verifier acceptance rules for
the reserved frame shape and the lowering convention for the generated
trampoline; both preserve the meaning of existing modules. New golden
fixtures for the direct and step instances are `mir 6` fixtures.

The task surface adds one operation, in `mir 7`:

```text
task.spawn %group, @__alder_step.run.<instance>, %frame, %domain -> u64
```

`%group` is a runtime group id (`u64`) produced by the `std.task` group
binding; the group record owns the child list and cancellation state, and its
public API lands with gate 9.4. The target is a step function whose
frame type is the element type of `%frame`; `%frame` is the one-element
`safe_mut` allocated in `%domain`; `%domain` is the activation domain.
Verification requires the group to be `u64`, the domain to be a
`domain_handle`, the frame to be exactly the target's `safe_mut` frame view,
and that view to be the direct `alloc` result with the constant count 1 in
that same domain. The
operation creates a task record, pushes the target as its root activation,
makes the task runnable, and returns a generational task id. At the C level it
lowers to `alder_task_create`, then `alder_task_start`, then
`alder_task_handle(task)`; the id comes from
`uint64_t alder_task_handle(AlderTask *task)`, called on the task record
returned by create. It is not `alder_task_id`, which observes the current
step's task and would return the spawner's id instead of the child's. The
two-phase form exists so the runtime can keep the task unrunnable while the
spawner initializes the frame, and `task.spawn` performs both phases in one
MIR instruction. In the gate 9.2 foundation the runtime keeps only an opaque
group id and a lazily created internal list for release unlinking; it applies
no group cancellation or join policy. Gate 9.4 owns the group record and its
create/cancel/join surface. The task record borrows `%domain` and
`%frame` until `alder_task_release`; the spawner keeps ownership and destroys
the domain after release. The borrow is a safe-wrapper and lowering contract,
not a new verifier fact: `release` is an ordinary binding, so the verifier
keeps the values live, and the lowering never allocates, resets, or destroys a
spawned activation domain from the spawner while the task is live. A
test-build domain check reports a violation of that contract. `task.spawn` is needed
because the handoff passes `safe_mut` and `domain_handle` values that no
verified C binding can name. For each `Pending(T)` argument the checker
preserves the checked callee's resolved `FunctionId` and the ordered argument
expression links in the call annotation, while the argument's checked
expression remains the declaration-only `Pending` placeholder so the parent
never evaluates the child body. Lowering consumes the preserved callee and
argument links to construct the child frame and emit `task.spawn`; the
placeholder semantics and the task-transfer rules are unchanged. `await`, `release`, `cancel`, `yield`, sleep,
channel, and shield operations are ordinary bindings over C scalar values and
task ids and add no MIR operation. `task.spawn` lands through the versioning
process with the `Pending(T)` typing surface in gate 9.4; gate 9.2 exercises
the `alder_task_create`/`alder_task_start`/`alder_task_handle` C ABI directly.
The worked example above contains no spawn site and stays `mir 6`.

## Textual MIR

The newest textual format is `mir 7`; the parser and verifier retain legacy
`mir 1` through `mir 6` support. Each version admits only its documented
features, so a module under an older header is rejected rather than silently
changed. Function headers are predeclared
in textual order before function bodies are parsed, so calls and cleanup
callbacks may name the current function or any later function; `FunctionId`
values remain textual declaration order. Named types, constants, and imports
still require declaration before use, including from function bodies. The
parser otherwise requires declarations before uses, one statement per line,
and deterministic name resolution. The printer preserves the parsed version
and emits `mir 7` only when a module contains `task.spawn`; a module without
the operation keeps the `mir 6` header, and newly constructed modules default
to `mir 6`. Printing a
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
- Domain identity and parent ancestry are tracked separately: destroying a child does not destroy its parent, while destroying a parent invalidates descendant handles and allocations. The current MIR profile permits create/allocate/destroy wholly within each loop iteration, but conservatively rejects function-local domain handles and references carried through block arguments across a backedge. A cyclic local-place store may carry allocations owned by a function-parameter domain, or by a local domain that the loop cannot invalidate, when the current function never resets or destroys that domain through verified MIR effects inside the loop's blocks; every such allocation remains live for the whole loop, so repeated static allocation roots cannot revive an invalid alias. A capability-typed value (a `slice`, `safe_ref`, or `safe_mut`) additionally has to be stored into a local place, and its root is the domain that owns the viewed storage. Local domains created or destroyed inside the loop's own blocks remain rejected, because their per-site C slots and dynamic identities must not be conflated across iterations. As at every `ffi.call.unsafe`, foreign code remains responsible for preserving any domain lifetime promised by its safe wrapper.
- The loop rules are death-precise for owning values: a carried value whose type contains no capability or handle kind (no slice, view, reference, pointer, table owner or view, domain handle or mark, cleanup scope or id — the `loopCarryOwnerType` classifier) is rejected only when its storage actually dies inside the loop, namely when a domain it derives from was created inside the loop, or a destroy or reset that may alias one of its domain identities (including ancestors, through parent facts) executes in a loop block the carrying site can reach. A domain created before the loop and destroyed only at the function's exits survives, which is what makes loop-carried collection headers (`store local` of a rebuilt `vec` header, and `vec`-typed loop parameters) legal; per-iteration parameter-domain allocations carried as block parameters stay rejected because carrying one conflates iterations. "Inside the loop" is measured against the loop under check, not against any cycle in the function: a domain or an allocation produced inside an enclosing or an earlier, already finished loop is carried across this loop's backedge unchanged, so it is not per-iteration here. A `vec`-typed loop parameter is rejected only when the loop header dominates the block that creates its domain or its storage; the store rule, which has no header to hand, measures the same question from the storing block instead, so it keeps the coarser same-cycle test. Capability-typed values use the same store rule as owning values with one extra requirement, a local place, and they add the view read rule below. A copyable snapshot that may contain function values and nothing that owns or aliases mutable storage (a function type, or an option, result, array, aggregate, or enum over plain bits and such snapshots) is exempt from the per-iteration allocation clause: its function environments are immutable shared records, so carrying one across a backedge transfers no ownership, while a destroy or reset that reaches an environment's domain inside the loop still rejects it. This is the D023-adjacent soundness line: ownership may be carried where its backing provably outlives the loop; capabilities may not.
- A view header is not an owning value, so a surviving domain is not enough for it: the storage it points into must not move. Phase 6 therefore rejects a `slice`, `safe_ref`, or `safe_mut` load inside a loop cycle unless one of two conditions holds. The first, and the one this profile proves for generated code, is that a store to the same local place inside the same cycle dominates the load: the header is redefined before every read on each iteration, so no iteration reads a header stored by an earlier one and the value is dead at the backedge. The second is that the loop cannot relocate the storage the header points into: the view is walked back through `vec.as_slice`, `array.as_slice`, `borrow`, `borrow_mut`, `slice.range.checked`, `slice.index.checked`, switch payloads, and the stores of its slot to the local that holds it. A collection header loaded from a field or element place is traced through that place's base, so a view formed from `self.buffer` resolves to the parameter or local behind the field. The cycle is then required to contain no `vec.grow.checked` deriving from that base, no store into it, and no call receiving it, since a callee may grow storage through an exclusive argument. A view whose storage is a parameter, a constant, an allocation, a field of a parameter, or a call result is stable in this sense and needs no redefinition, which keeps a view created before a loop and read inside it legal. A parameter-rooted view is exempt. A table-view arm needs neither condition: `table.lookup` and `table.lookup_mut` open a region that the checker confines to one straight-line match arm with no fallible operation, so the payload is consumed inside the iteration that created it and no header crosses the backedge; the arm inside a `while` body is legal once cleanup registration runs on the loop's panic path;
- Domain marks keep direct SSA identity. Reset consumes all marks corresponding to the reset domain, and a later `domain.mark` produces a fresh runtime-epoch mark;
- Ordinary functions may not return `domain_handle` or `domain_mark` in the current MIR profile. Their result identity and parent relation cannot yet be represented by function-effect summaries, so Phase 2 rejects such signatures rather than losing provenance at a call.
- local-place provenance distinguishes field paths. Dereference-based memory has no general alias declaration in the current MIR profile, so Phase 6 conservatively treats dereference stores as possible sources for dereference loads;
- returned values must not contain references derived from function-local domains;
- a function value's environment is a domain allocation, and `copy_to_domain` of a function type is complete: the C backend's retain hook allocates a fresh environment in the destination domain, rewrites a captured domain handle, and retains function-valued captures recursively, so the copy severs the source's provenance like any other independently materialized value. A function value returned without such a copy keeps the source's provenance, so a return after its environment's owning domain was destroyed is rejected at the return exit;
- `unreachable` terminators are accepted only in blocks unreachable from the entry block;
- table identities originate at function table parameters and `table.create` sites and are preserved through block parameters, memory, aggregate/enum values, and ordinary calls. A call returning a newly-created table receives a stable call-site identity;
- any domain reset invalidates tables that may be owned by that domain, even when the table was created before the mark. This conservative rule prevents hidden element or slot allocations made after the mark from surviving behind a stale table handle;
- a table lookup result is consumed exactly once, in its defining block, by a `some` switch binding or checked `some` payload extraction. From lookup until extraction, and from successful extraction through `table.view.end`, insert, insert.try, remove, and ordinary-call or active-cleanup effects that may mutate the same table are forbidden. The checked extraction failure edge observes the pre-extraction state and a switch `none` path has no view to end;
- table views are ephemeral: every use of a view must stay in its access block, exactly one `table.view.end` follows all other uses, and neither insert nor remove of the same table may occur while any related view remains active;
- `raw_ptr` values may only cross explicit unsafe boundaries: FFI calls, function boundaries, and returns;
- `alloc` and `table.create` element types must be plain value types without handles, cleanup identifiers, views, or raw pointers, recursively.

Diagnostics must be stable and must identify the relevant function, block, operation, and source span when one exists. The current verifier reports function, block, and operation; spans arrive with the frontend.

## Binding Blocks and C Types

MIR 6 records C binding declarations as module-level binding blocks, printed
after imports and constants and before functions. One block names one logical
header and carries three flat declaration lists:

```text
binding @ctime "time.h" {
  c_type scalar @Time = "time_t"
  c_type opaque @File = "FILE"
  c_type record @Timespec = "struct timespec" { seconds: @Time = "tv_sec", nanos: c_long = "tv_nsec" }
  c_fn @get = "timespec_get"(c_ptr(@Timespec), c_int) -> c_int
  c_fn @close(c_ptr(@File)) -> c_int
  c_const @BUFSIZ: c_int
}
```

- `c_type` declares one named C binding type. The class is `scalar` (a C
  typedef or enum used as a value), `opaque` (used behind pointers only), or
  `record` (a complete non-bitfield struct or union used by value). A record's
  braced member list maps each Alder field name to its MIR type and, after
  `=`, the C field spelling; a missing spelling requires the names to match.
- `c_fn` declares one C function: an Alder name, an explicit C spelling after
  `=` (omitted when the names match), the parameter types, and the result
  type. Signatures carry no environment: binding calls never capture.
- `c_const` declares one object-like integer constant with an optional C
  spelling after `=` and its representable type.

The `c_*` type vocabulary is disjoint from Alder numerics: `c_raw` with a
`c_scalar` payload ids 0..14 (`c_char`, `c_schar`, `c_uchar`, `c_short`,
`c_ushort`, `c_int`, `c_uint`, `c_long`, `c_ulong`, `c_llong`, `c_ullong`,
`c_float`, `c_double`, `c_size`, `c_ptrdiff`), `c_ptr(T)` and
`c_const_ptr(T)` raw pointers, and `c_named` for `c_type` members. Binding
types appear only inside binding declarations and on the unsafe boundary;
ordinary typed code may not name them (phase 9), and they cannot be element
types of Alder aggregates or copied through Alder aggregate rules
(phase 10).

Two operations consume bindings directly, and two more consume record fields:

- `c.call.unsafe` (op 69) performs one root call to a `c_fn`. Its `target`
  holds the flat binding-function index (block-major, in declaration order
  across the module's binding blocks); its arguments must match the declared
  signature exactly, except that `c_ptr(E)` widens to `c_const_ptr(E)`. A
  unit-result binding call may drop its result; any other dropped result is
  rejected. The call requires `unsafe` and is rejected in verifiable
  (non-unsafe) context by phase 5.
- `c.is_null` (op 70) observes a raw pointer for nullity and yields `bool`.
  It is the only operation besides explicit boundaries allowed to consume a
  `raw_ptr` value (phase 9).
- `c.field.get` (op 96) reads one field of a by-value C record. Its `a`
  operand is a value of `c_named` record class, its target type is the
  declared field type, and its name is the Alder field spelling of a
  `c_field` part of that record; the verifier rejects an unknown field name,
  a non-record receiver, or a target that does not match the field's declared
  type. It produces a value.
- `c.field.set` (op 97) writes one field of a by-value C record held in a
  place. Its place must be a local of `c_named` record class, its `a` operand
  must have the declared field type, and its name selects the same `c_field`
  part as `c.field.get`. It binds no result.

Binding operand kinds: a `c.call.unsafe` argument is `binding_param` (9)
whose `operand_type` is the declared parameter type and whose owner is the
flat binding-function index, or `binding_type` (10) whose owner is the
binding block and whose `operand_type` must be a `c_named` member of that
block. A record's C field mapping is a `c_field` type part (part kind 5)
whose name is the Alder field name and whose own C name is the spelling.

The verifier's structural rules for bindings:

- binding, member, and function names are Alder identifiers without leading
  underscores, without reserved words, and without the runtime-reserved
  `alder_` prefixes; C spellings are free header identifiers and may carry
  `struct `/`union `/`enum ` tags for records and `TIME_`-style macro spellings
  for constants;
- names and C spellings are unique within their block; blocks have unique
  names and headers within a module;
- record fields are leaf types only (scalars, pointers, named members), and
  an opaque member may not be used by value;
- the printed form round-trips, and every binding list is printed in
  declaration order, deterministic across processes.

## Versioning

Textual MIR carries an explicit format version. `mir 1` remains a stable legacy
format; `mir 2` adds only valueless `panic`; `mir 3` adds `alloc.checked`;
`mir 4` adds `vec(T)` and the minimal Vec operations; `mir 5` adds
function-type environments, `fn.value`, and `call.value`; `mir 6` adds C
binding blocks, the `c_*` raw type vocabulary, `c.call.unsafe`,
`c.is_null`, the integer overflow method operations (71-79), the
byte-sequence method operations (80-85), the integer conversion method
operations (86-87), the C scalar conversion method operations (88-90), the float arithmetic
operations (91-94), the ordering comparison operation (95), the C
record field operations (96-97), the C-string ownership operations (98-101),
the display operation (102), the total bitwise operations (103-106), and the
call-scoped buffer borrow (107). `mir 7` adds the task surface's single new
operation, `task.spawn` (108), pinned in
[Suspending Instances and Step Frames](#suspending-instances-and-step-frames);
it changes nothing else in the format. Step frames,
state enums, and the direct/step split use only `mir 6` syntax, so a module
containing them but no spawn site stays `mir 6`.
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
