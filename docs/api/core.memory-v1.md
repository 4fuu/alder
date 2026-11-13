# `core.memory` Public Signature Snapshot v1

Status: **Milestone 8.1 frozen snapshot; size and alignment queries implemented**

This is the versioned public snapshot for safe layout queries. It is normative
together with the executable example
[`examples/core.memory-v1.al`](examples/core.memory-v1.al). The module lives at
`<sysroot>/core/memory.al` and is imported explicitly; it is not part of the
prelude.

`core.memory` answers the two questions generic code needs before it can reason
about values it does not name: how many bytes the lowered representation
occupies and what alignment that representation requires. It allocates no
memory, exposes no pointer, and performs no runtime call. The answers are
facts about the target C compiler and the lowered representation for one
concrete instantiation.

## Signatures

```alder
module core.memory

/// The size in bytes of the lowered representation of `T`. `Unit` is 0.
pub fn size_of(T: type) -> U64

/// The alignment in bytes of the lowered representation of `T`. `Unit` is 1.
pub fn align_of(T: type) -> U64
```

## Contracts

- Both functions take exactly one concrete type argument. A call whose argument
  is not a type, has the wrong arity, or leaves the type unresolved is semantic
  diagnostic 346.
- The result is the target C compiler's `sizeof`/`_Alignof` for the type as the
  C backend lowers it. This is a property of the build, not a stable
  cross-target ABI promise. A consumer that needs a fixed width uses the
  exact-width integer types; a consumer that needs to match a C type uses the
  binding's declared type.
- `Unit` is the one fixed exception: its size is 0 and its alignment is 1 even
  though the C backend gives its storage the `uint8_t` spelling.
- The query is a compile-time fact per monomorphized instance. A generic body
  may write `size_of(T)` or `align_of(T)`; each concrete instance answers for
  its own substituted `T`.
- Records, enums, arrays, strings, bytes, vectors, builtin `Option`/`Result`,
  and ordinary scalar types use the lowered representation. A zero-length
  `Array(T, 0)` lowers to a one-element native C array because portable C11 has
  no zero-length arrays, so its answer is that wrapper's size and alignment
  (for example, `Array(U64, 0)` has size 8 and alignment 8), not zero. That is
  a fact about the target representation, like every other answer here, and
  not a zero-size Alder rule. The query does not inspect padding bytes, and no
  Alder layout engine is added.
- Neither function is an allocation primitive. `core.memory` exposes no raw
  allocation, no pointer arithmetic, and no lifetime operation.

## Example

The example below is the complete content of
`examples/core.memory-v1.al`. The checksum uses only fixed-width 64-bit
answers, so it is stable on the project's 64-bit hosted targets.

```alder
module hello.core_memory_example

import core.memory { size_of, align_of }

// The executable core.memory v1 snapshot example. The checksum mixes the
// fixed 64-bit answers and the Unit exception; record padding is exercised
// but not folded into the stable value.
pub fn core_memory_example() -> U64 {
    var total = size_of(U64) * 10 + align_of(U64)
    total = total + size_of(Unit) + align_of(Unit)
    if size_of(U8) != 1 { return 1 }
    if size_of(U16) != 2 { return 2 }
    if size_of(U32) != 4 { return 3 }
    return total
}
```
