# `core.collection` Public Signature Snapshot v1

Status: **Milestone 7.1 frozen snapshot**

This is the first versioned public snapshot for the Milestone 7.1 `Vec(T)`
surface. It is normative together with the executable example in
[`examples/core.collection-v1.al`](examples/core.collection-v1.al).

## Signatures

The generic `T` in this snapshot must be recursively copyable. `N` is the
compile-time length carried by the argument's `Array(T, N)` type; it is inferred
and is not a new user-defined const-generic facility.

```alder
impl Vec(T) {
    pub fn new(T: type) -> Vec(T)
    pub fn from_array(T: type, values: Array(T, N)) -> Vec(T)

    pub fn len(self) -> U64
    pub fn push(mut self, value: T)
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
that case and `Some(independent_value)` otherwise. Indexed reads, `get`,
assignment, parameter passing, and return preserve ordinary value semantics;
nested vectors and vectors inside arrays, options, results, records, or enums
are copied recursively into independent storage.

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

M7.1 rejects `Vec(T)` deterministically when `T` is affine or scoped, including
through a nested aggregate. Affine-element cleanup and transfer are owned by
Milestone 7.5, not this snapshot.
