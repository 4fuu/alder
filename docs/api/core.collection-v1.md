# `core.collection` Public Signature Snapshot v1

Status: **Milestone 7.1 frozen snapshot, extended by the Milestone 8
ordered-collection addition**

This is the first versioned public snapshot for the Milestone 7.1 `Vec(T)`
surface, extended below with the Milestone 8 insertion-ordered `Map(K, V)` and
`Set(T)` surfaces. It is normative together with the executable example in
[`examples/core.collection-v1.al`](examples/core.collection-v1.al).

## Signatures

The generic `T` in this snapshot must be recursively copyable, except for the Milestone 7.5 affine `Vec(T)` extension described below. `N` is the
compile-time length carried by the argument's `Array(T, N)` type; it is inferred
and is not a new user-defined const-generic facility.

```alder
impl Vec(T) {
    pub fn new(T: type) -> Vec(T)
    pub fn from_array(T: type, values: Array(T, N)) -> Vec(T)

    pub fn len(self) -> U64
    pub fn push(mut self, value: T)
    pub fn pop(mut self) -> Option(T)
    pub fn get(self, index: U64) -> Option(T)
    pub fn slice(self, start: U64, end: U64) -> [T]
    pub fn slice_mut(mut self, start: U64, end: U64) -> MutSlice(T)
}
```

The exact calls are `Vec.new(T)` and `Vec.from_array(T, values)`. Both spell the
compile-time element argument explicitly and methods use ordinary dot-call
syntax.

`Vec(T)` supports checked index expressions and indexed mutation:

```alder
let value: T = values[index]
values[index] = replacement
```

Index syntax terminates if `index >= values.len()`. `get` returns `None` for
that case and `Some(independent_value)` otherwise. `pop` is total: it returns
`None` for an empty vector and otherwise returns the last element, shortening
the vector by one. Indexed reads, `get`, assignment, parameter passing, and
return preserve ordinary value semantics; nested vectors and vectors inside
arrays, options, results, records, or enums are copied recursively into
independent storage.

## Growth and placement

`new` starts with length and capacity zero. `from_array` starts with length and
capacity `N`. A `push` into full storage chooses capacity 4 when the old
capacity is zero and otherwise doubles the old capacity. It then allocates the
new storage and copies existing elements in ascending index order before
appending the new element. Length, capacity doubling, and
`capacity * sizeof(T)` are checked as `U64`; conversion to C `size_t` is also
checked. Overflow, an unrepresentable C allocation size, or allocation failure
terminates through the ordinary invariant-failure path without changing
language semantics or invoking C undefined behavior.

Milestone 7.1 uses eager deep copy. A copied vector's capacity equals its
length; subsequent growth follows the rule above. The representation is a
plain data/length/capacity value and does not contain a domain, allocator,
reference count, or bootstrap `__s0_*` value.

The compiler privately prepends a caller-result domain to every lowered
ordinary source function, method, source call, recursive call, and cleanup
callback. Each ordinary function creates a nested function domain and destroys
it on every exit. The checked-source `StoragePlan` selects the smallest safe
one of these domains for vector allocation, growth, and copies; returned values
are copied into caller-result storage when needed. Hosted entry creates the
outer root and destroys it after the source entry returns. A source
`main(root: Domain)` binds that source parameter to the same hidden MIR value;
that entry form is private to the compiler's bootstrap profile, so ordinary
programs use the parameterless `main` and still receive the hidden MIR root.
Unhosted generated functions keep the explicit hidden MIR parameter. Source
signatures, calls, and vector representations do not expose this mechanism.

Milestone 7.5 extends `Vec(T)` to affine `Cleanup` owners. Such elements enter
by transfer through `push`/`from_array`, leave by transfer through `pop`, and
are rejected for `get` and views because a read would duplicate an owner. A
vector over affine elements is itself affine; `using` registration drains its
remaining elements at scope exit, and a registered vector is immutable, so pop
must happen before registration. Scoped element types remain rejected.

## Milestone 8 addition: insertion-ordered `Map` and `Set`

The Milestone 8 ordered-collection addition extends this snapshot with the
insertion-ordered `Map(K, V)` and `Set(T)` builtin surfaces. They are ordinary
value collections: copies are independent, keys and elements are compared with
the language-provided structural equality and hashing domain, and iteration
order is insertion order.

```alder
impl Map(K, V) {
    pub fn new(K: type, V: type) -> Map(K, V)

    pub fn insert(mut self, key: K, value: V) -> Bool
    pub fn get(self, key: K) -> Option(V)
    pub fn remove(mut self, key: K) -> Bool
    pub fn len(self) -> U64
    pub fn keys(self) -> Vec(K)
    pub fn values(self) -> Vec(V)
}

impl Set(T) {
    pub fn new(T: type) -> Set(T)

    pub fn insert(mut self, value: T) -> Bool
    pub fn contains(self, value: T) -> Bool
    pub fn remove(mut self, value: T) -> Bool
    pub fn len(self) -> U64
    pub fn items(self) -> Vec(T)
}
```

The exact calls are `Map.new(K, V)` and `Set.new(T)`, spelling the type
arguments explicitly. `insert` returns whether the key or element was newly
inserted; inserting an existing map key replaces the value and keeps the key's
position. `remove` reports whether the key or element was present, and removal
compacts the remaining entries in insertion order, so reinserting a removed
key places it at the end. `keys`, `values`, and `items` return an owned
`Vec` snapshot of the current order; later mutations do not change a returned
snapshot.

`K` for `Map` and `T` for `Set` must be in the structural equality and hashing
domain: unsigned integers, `Bool`, `String`, `Bytes`, and non-generic records
and enums whose every component supports them. Signed integers participate in
structural `Eq`/`Hash` but remain outside the M8 Map/Set key domain as a
deliberate restriction. Types outside that domain are rejected with diagnostic
127. `V` and `T` must be recursively copyable
(diagnostic 128); a collection value with storage-backed parts is copied
independently on every read.

Today the operations that move stored values out of the collection — `remove`
on either type and the `keys`, `values`, and `items` snapshots — require
provenance-free types, so they reject keys, values, or elements with
storage-backed parts such as `String`, `Bytes`, or `Vec` with diagnostic 129
until the move loop can carry them. `insert`, `get`, `contains`, and `len`
accept those types: a `Map(String, U64)` inserts and reads `String` keys today.
This restriction is a documented temporary boundary of this snapshot, not part
of the long-term contract; the long-term contract is the full structural
domain everywhere.

Like `Vec` before its Milestone 7.5 extension, the ordered collections reject affine and scoped element types and
terminate on checked growth arithmetic through the ordinary invariant-failure
path. The snapshot example
[`examples/core.collection-v1.al`](examples/core.collection-v1.al) pins the
`Vec` surface together with replace-preserves-position, reinsertion-at-end,
snapshot ordering, and set duplicate collapse; its checksum is normative.
