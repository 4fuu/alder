# `core.iter` Public Signature Snapshot v1

Status: **Milestone 8.1 frozen snapshot; installed implementation**

This is the versioned public snapshot for the static iterator layer. It is
normative together with the executable example in
[`examples/core.iter-v1.al`](examples/core.iter-v1.al). The module lives at
`<sysroot>/core/iter.al`.

Snapshot v1 covers the part of `core.iter` that needs no `for` desugaring,
trait objects, associated types, or runner support. The `Iterator(Item)` and
`IntoIterator(IteratorType, Item)` traits are builtin static traits: every
operation resolves and monomorphizes before MIR.

## Signatures

```alder
module core.iter

type SliceIter(T: type) {
    values: [T]
    at: U64
}

type VecIter(T: type) {
    values: [T]
    at: U64
}

type BytesIter {
    data: Bytes
    at: U64
}

type Indexed(T: type) {
    pub index: U64
    pub value: T
}

type Pair(A: type, B: type) {
    pub first: A
    pub second: B
}

pub fn slice_iter(T: type, values: [T]) -> SliceIter(T)
pub fn vec_iter(T: type, values: Vec(T)) -> VecIter(T)
pub fn bytes_iter(data: Bytes) -> BytesIter
pub fn mut_slice_iter(T: type, values: MutSlice(T)) -> VecIter(T)
pub fn set_iter(T: type, value: Set(T)) -> VecIter(T)
pub fn map_iter(K: type, V: type, value: Map(K, V)) -> ZipIter(VecIter(K), VecIter(V), K, V)

impl SliceIter(T) {
    pub fn to_vec(self) -> Vec(T)
}

impl VecIter(T) {
    pub fn to_vec(self) -> Vec(T)
}

impl Iterator(T) for SliceIter(T) {
    pub fn next(mut self) -> Option(T)
}

impl Iterator(T) for VecIter(T) {
    pub fn next(mut self) -> Option(T)
}

impl Iterator(U8) for BytesIter {
    pub fn next(mut self) -> Option(U8)
}

type MapIter(I: type, T: type, U: type)
type FilterIter(I: type, T: type)
type FilterMapIter(I: type, T: type, U: type)
type EnumerateIter(I: type, T: type)
type TakeIter(I: type, T: type)
type SkipIter(I: type, T: type)
type ChainIter(A: type, B: type, T: type)
type ZipIter(A: type, B: type, T: type, U: type)

pub fn map(I: type(Iterator(T)), T: type, U: type, iterator: I, f: fn(T) -> U) -> MapIter(I, T, U)
pub fn filter(I: type(Iterator(T)), T: type, iterator: I, keep: fn(T) -> Bool) -> FilterIter(I, T)
pub fn filter_map(I: type(Iterator(T)), T: type, U: type, iterator: I, f: fn(T) -> Option(U)) -> FilterMapIter(I, T, U)
pub fn enumerate(I: type(Iterator(T)), T: type, iterator: I) -> EnumerateIter(I, T)
pub fn take_count(I: type(Iterator(T)), T: type, iterator: I, count: U64) -> TakeIter(I, T)
pub fn skip(I: type(Iterator(T)), T: type, iterator: I, count: U64) -> SkipIter(I, T)
pub fn chain(A: type(Iterator(T)), B: type(Iterator(T)), T: type, first: A, second: B) -> ChainIter(A, B, T)
pub fn zip(A: type(Iterator(T)), B: type(Iterator(U)), T: type, U: type, first: A, second: B) -> ZipIter(A, B, T, U)

pub fn to_vec(I: type(Iterator(T)), T: type, mut iterator: I) -> Vec(T)
pub fn fold(I: type(Iterator(T)), T: type, A: type, mut iterator: I, initial: A, f: fn(A, T) -> A) -> A
pub fn for_each(I: type(Iterator(T)), T: type, mut iterator: I, f: fn(T) -> Unit) -> Unit
pub fn count(I: type(Iterator(T)), T: type, mut iterator: I) -> U64
pub fn any(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Bool
pub fn all(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Bool
pub fn find(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Option(T)
pub fn position(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Option(U64)
```

`T` and every adapter item must be recursively copyable. Affine `Cleanup`
owners are outside this snapshot: an iterator over affine elements is rejected
rather than duplicating an owner or guessing a transfer point. `take_count` is
the public spelling because `take` is reserved. `Indexed(T)` carries its
zero-based position and value; `Pair(A, B)` carries the two `zip` values.

## `IntoIterator` and construction

The checker materializes the builtin `.into_iterator()` surface for these
receivers, in this item shape:

| Receiver | Item | Constructor |
|---|---|---|
| `Array(T, N)` | `T`, source order | `slice_iter(T, value)` |
| `[T]` | `T`, source order | `slice_iter(T, value)` |
| read-only `MutSlice(T)` | `T`, source order | `mut_slice_iter(T, value)` |
| `Bytes` | `U8`, byte order | `bytes_iter(value)` |
| `Vec(T)` | `T`, source order | `vec_iter(T, value)` |
| `Map(K, V)` | `Pair(K, V)`, insertion order; `first` is the key, `second` the value | `map_iter(K, V, value)` |
| `Set(T)` | `T`, insertion order | `set_iter(T, value)` |

The module must be imported. Nominal receivers keep their own inherent or
trait `into_iterator` method; a user `impl IntoIterator(...)` is ordinary
static dispatch.

`SliceIter` and `VecIter` store an immutable `[T]` view, not an owned `Vec`.
`BytesIter` stores a copied `Bytes` value. Constructing any of these
iterators materializes the input into caller-result storage. That copies
O(n) elements and allocates O(n) caller-result storage: constructing an
iterator is **not** zero-copy and not O(1) borrowing. Later source mutation
does not affect the iterator; the iterator observes the input as it was at
construction.

The receiver-specific construction cost is:

- an array or immutable slice materializes one `[T]` view;
- a read-only `MutSlice` copies its elements through `get` into a fresh
  `Vec`, then materializes that vector as a `VecIter` view (O(n) elements and
  two materialization steps);
- `Bytes` copies the byte value into `BytesIter`;
- `Vec` materializes its view;
- `Map` takes independent `keys()` and `values()` snapshots and zips them, so
  it allocates and copies both sequences; insertion order and the
  replacement-keeps-position rule are preserved;
- `Set` takes an `items()` snapshot and materializes it as a `VecIter`.

The read-only `MutSlice` surface yields copied `T` values. It does not expose
mutable element views; exclusive `MutSlice`/`IterMut` iteration remains
deferred. A `MutSlice` receiver is still subject to the ordinary mutable-view
place rules: the builtin constructor borrows it mutably and does not retain the
view.

`Map` and `Set` iteration currently requires keys, values, and elements
without storage-backed parts. The existing `keys`, `values`, and `items`
snapshot APIs reject `String`, `Bytes`, `Vec`, and other storage-backed parts
with diagnostic 129, and `map_iter`/`set_iter` inherit that boundary. This is
the same temporary collection restriction documented in the
[`core.collection` v1 snapshot](core.collection-v1.md), not a weakening of the
long-term structural domain. Copyable scalar and record/enum domains iterate
normally.

Each adapter constructor returns a view-bearing aggregate and therefore
applies the same return materialization to its inner iterator, copying the
remaining elements again. A chain of `k` adapters can copy O(k·n) elements
during construction. Iteration itself is lazy and does not copy.
`take_count` and `skip` still materialize the full inner view at construction;
they do not copy only the selected range. `chain` and `zip` materialize both
inputs. A direct constructor call from a borrowed `[T]` follows the same
view-return and materialization rules.

A capturing closure passed to an adapter is retained by the adapter value.
Ordinary copyable captures are allowed. A closure that captures a scoped view
and escapes into the adapter is rejected by the existing closure rule with
diagnostic 152; the adapter does not weaken or bypass that check.

`for value in sequence` remains the builtin array/slice/`Vec` fast path. This
snapshot does **not** desugar `for` through `IntoIterator`; `for` over an
adapter or cursor is deferred with the frontend that replaces S0. Users drive
a cursor with `next` or the terminals below.

## Adapters

Adapters are lazy and consume the source iterator by value. They return data
values, not trait objects, and each adapter has a concrete `Iterator`
implementation:

- `map` applies a transform to each value;
- `filter` keeps values whose predicate is true;
- `filter_map` applies a transform returning `Option(U)` and drops `None`;
- `enumerate` attaches zero-based positions as `Indexed(T)`;
- `take_count` stops after at most `count` values;
- `skip` drops at most `count` values before yielding;
- `chain` yields the first iterator to exhaustion, then the second;
- `zip` yields `Pair(A, B)` and terminates at the shorter input in either
  direction.

Closures are ordinary function values. A capturing closure carries its
compiler-generated environment exactly as elsewhere in the language; adapters
store the function value in a field and call it later. A closure that captures
a scoped view must still satisfy the existing non-escaping closure rule.

## Terminals

Terminals consume a mutable cursor because `Iterator.next` is a `mut self`
method. Bind the cursor with `var`, or forward a `mut` parameter:

```alder
var cursor = values.into_iterator()
if iter.count(cursor) != 3 { return 1 }
```

`to_vec` collects the remaining values into a fresh `Vec(T)`. `fold` threads
an accumulator, `for_each` runs an effect for each value, `count` counts the
remaining values, `any`/`all` short-circuit, `find` returns the first matching
value as `Option(T)`, and `position` returns its zero-based position as
`Option(U64)`. The inherent `to_vec` methods on `SliceIter` and `VecIter` are
shorthands for the same collection rule.

## Deferred work

The following are outside snapshot v1 and recorded in the Milestone 8.1
roadmap: `for`/`IntoIterator` desugaring; `String` scalar iteration; exclusive
`MutSlice`/`IterMut` iteration (read-only `MutSlice` iteration is installed
above); double-ended iteration and reversal; a `collect`/`FromIterator`
protocol beyond the installed `to_vec`; adapters outside the list above; trait
objects; associated types; and any lazy adapter that requires a new checker,
lowering, or MIR operation.

The [standard library guide](../standard-library.md#iteration) records the
same boundary and the deferred surface.
