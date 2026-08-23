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

impl MutSlice(T) {
    pub fn len(self) -> U64
    pub fn get(self, index: U64) -> Option(T)
    pub fn subview(mut self, start: U64, end: U64) -> MutSlice(T)
}
```

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
multi-argument call. Views may not be returned, placed in a record, array,
variant, or other ordinary aggregate or collection, or otherwise escape their
lexical owner scope. Cases requiring a returned view or an allocation/view to
survive an inner candidate domain remain rejected until Milestone 7.3 proves
placement or safe outer retention. M7.1 does not infer or spell source
lifetimes.
