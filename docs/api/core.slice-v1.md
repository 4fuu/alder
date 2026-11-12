# `core.slice` Public Signature Snapshot v1

Status: **Milestone 7.1 frozen snapshot**

This is the first versioned public snapshot for immutable `[T]` and exclusive
`MutSlice(T)` views. It is normative together with the executable example in
[`examples/core.slice-v1.al`](examples/core.slice-v1.al).

## Signatures

Arrays and vectors form half-open views with the same method names:

```alder
impl Array(T, N) {
    pub fn slice(self, start: U64, end: U64) -> [T]
    pub fn slice_mut(mut self, start: U64, end: U64) -> MutSlice(T)
}

impl [T] {
    pub fn len(self) -> U64
    pub fn get(self, index: U64) -> Option(T)
    pub fn slice(self, start: U64, end: U64) -> [T]
}

impl [U8] {
    pub fn to_bytes(self) -> Bytes
}

impl MutSlice(T) {
    pub fn len(self) -> U64
    pub fn get(self, index: U64) -> Option(T)
    pub fn subview(mut self, start: U64, end: U64) -> MutSlice(T)
}
```

A mutable view is formed from a place: a `let`/`var` local, a `mut`
parameter, or a field or element path of one. A field or element receiver is
read as its collection header, and writes through the view land in the place's
existing storage, not in a copy. A mutable view is not formed from a call
result or another temporary, and it cannot escape the function or block that
owns the viewed storage. Immutable views may also be formed from any field or
element place because they only read.

`[U8].to_bytes` copies the view's bytes into a fresh `Bytes` value, so the
result never aliases the view's owner; every other element type has no such
method. Because `Array(T, N)` and `Vec(T)` form `[T]` views with `slice`, the
conversion is reachable from both (`data.slice(1, 3).to_bytes()`).
`MutSlice(U8)` has no immutable view operation yet and therefore no
`to_bytes` of its own.

`Vec(T).slice` and `Vec(T).slice_mut` are frozen in the
[`core.collection` v1 snapshot](core.collection-v1.md). Every range is
half-open. Formation terminates unless `start <= end <= len`. Index syntax is
available on both view types and terminates out of bounds; indexed assignment
is available only on `MutSlice(T)`. `get` returns `None` out of bounds and an
independent `Some(T)` otherwise.

An `Array(T, N)` or `Vec(T)` argument also borrows as `[T]` when the exact
callee parameter type is `[T]`. This conversion exists only at a non-retaining
call boundary and is evaluated in the argument's source position, preserving
left-to-right call evaluation. It does not create an implicit owned vector or
expose a public domain.

## Lexical validity and exclusivity

M7.1 view lifetimes are lexical rather than last-use shortened:

- a local view remains active through the end of its source block;
- immutable views of one owner may overlap, and immutable owner reads remain
  available, but all owner mutation is rejected while any immutable view is
  active;
- a mutable view excludes every direct owner read, owner mutation, immutable
  view, and other mutable view until the mutable view's block ends;
- a mutable-view local must be formed directly by `slice_mut` or `subview`;
  copying or reassigning a `MutSlice(T)` descriptor is rejected rather than
  creating a second exclusive capability;
- `subview` temporarily reborrows its mutable receiver; the parent mutable view
  cannot be used while the subview is active;
- structural vector mutation, including `push` and growth, is therefore
  rejected while either kind of view is active;
- every capability use after a backing-domain reset or destruction is rejected
  by MIR verification, including invalidation of a vector's storage.

Views may be passed to another non-retaining `[T]` or `MutSlice(T)` parameter.
To keep argument evaluation deterministic without temporary descriptors being
invalidated before call entry, a mutable or newly formed/implicitly borrowed
view argument must be last; bind immutable views in a lexical block before a
multi-argument call. M7.3 slice 2 permits a direct immutable `[T]` result by
materializing deterministic caller-result storage before the function domain
ends. Mutable views and views nested in records, arrays, variants, or other
ordinary aggregates or collections remain non-escaping. No source lifetime
syntax is introduced; full value/view-surface migration remains in M7.3 slice
3.
