# `core.collection` Public Signature Snapshot v2

Status: **Milestone 7.3 additive snapshot**

This snapshot adds recoverable capacity operations and owned byte conversion
to the frozen [v1 collection surface](core.collection-v1.md). V1 signatures and
their ordinary value semantics remain unchanged.

## Capacity errors

```alder
pub enum CapacityError {
    OutOfMemory
    Limit
}
```

`OutOfMemory` means the allocator could not provide storage. `Limit` means
checked length, capacity, byte-size, or host `size_t` representation would
overflow. The variants and their distinction are stable.

## Additive signatures

```alder
impl Vec(T) {
    pub fn try_reserve(mut self, additional: U64) -> Result(Unit, CapacityError)
    pub fn try_push(mut self, value: T) -> Result(Unit, CapacityError)
}

impl Bytes {
    pub fn try_from_vec(values: Vec(U8)) -> Result(Bytes, CapacityError)
    pub fn as_slice(self) -> [U8]
}

impl String {
    pub fn as_bytes(self) -> [U8]
}
```

`Vec.push` remains infallible at the type level and terminates on allocation or
capacity failure. The `try_*` operations instead return `CapacityError`.

Every failed `try_reserve` or `try_push` leaves the receiver's length,
capacity, elements, backing identity, and existing-view validity unchanged.
The same receiver may be retried. This transaction includes recursive
relocation of nested vectors, immutable views, arrays, options, results,
records, and variants: nested allocation failure is returned, not converted to
panic after outer growth succeeds. Successful operations preserve ordinary
value independence and invalidate conflicting views under the same static
rules as `push`.

`Bytes.try_from_vec` always creates independent immutable byte storage; later
mutation of the input vector cannot affect the result. `Bytes.as_slice` and
`String.as_bytes` create immutable scoped byte views. They do not enable
integer indexing on `Bytes` or `String` themselves. String bytes are valid
UTF-8 because `String` construction remains validated; byte-to-string
validation is outside this minimal additive snapshot.

Storage domains remain compiler-inferred and absent from every signature and
representation above.
