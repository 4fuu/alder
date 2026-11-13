# `core.hash` Public Signature Snapshot v1

Status: **Milestone 8.1 frozen snapshot; structural hashing and keyed builders implemented**

This is the versioned public snapshot for stable structural hashing. It is
normative together with the executable example
[`examples/core.hash-v1.al`](examples/core.hash-v1.al). The module lives at
`<sysroot>/core/hash.al` and is imported explicitly; it is not part of the
prelude.

`core.hash` defines one stable 64-bit hash over the same structural domain as
the synthesized `Eq` and `Hash` traits: `Bool`, signed and unsigned integers,
`String`, `Bytes`, `Option`/`Result` over those components, and records or
enums whose every component is in the domain. Floats, pointers, views,
collections, and other identity-bearing values stay outside the domain and are
rejected with diagnostic 347. No user `impl Eq` or `impl Hash` is accepted;
structural synthesis remains the only source of the domain.

## Algorithm

The digest is SipHash-1-3 with the canonical encoding below and a 128-bit key.
`hash` uses the fixed zero key, so it is process-independent. `hash_with` uses
the caller's `RandomState`, which is what attack-facing maps pass.

The canonical stream contains no padding, pointers, object identities, or
field names:

- `Bool`: one byte, 0 or 1.
- signed and unsigned integers: their exact width in little-endian byte order;
  signed values use the two's-complement bit pattern.
- `String` and `Bytes`: a `U64` little-endian length, then exactly that many
  bytes.
- `Option`: a one-byte tag (`none` 0, `some` 1), then the payload when present.
- `Result`: a one-byte tag (`ok` 0, `err` 1), then the payload.
- records: fields in declaration order, with no tag or separator.
- enums: a `U64` little-endian variant ordinal, then the payload when present.
- `Unit`: no bytes. It is not itself in the hash domain.

The structural encoding is deliberately independent of the Alder MIR layout,
so record padding and compiler-private field order never affect the digest.

## Signatures

```alder
module core.hash

/// One 128-bit SipHash key. The fields are private; use `seeded`, `from_words`,
/// or the OS-backed builder in `std.random`.
pub type RandomState {
    // private: k0, k1
}

impl RandomState {
    /// Deterministic 128-bit key expansion from one seed. The first word is
    /// SplitMix64(seed); the second is SplitMix64(first).
    fn seeded(seed: U64) -> RandomState
    /// The low-level key constructor used by the OS-backed builder in
    /// `std.random`. Word order is the SipHash key order.
    fn from_words(k0: U64, k1: U64) -> RandomState
    /// A fresh SipHash-1-3 accumulator for this key.
    fn hasher(self) -> Hasher
    fn first_word(self) -> U64
    fn second_word(self) -> U64
}

/// One copyable SipHash-1-3 accumulator.
pub type Hasher {
    // private state
}

impl Hasher {
    /// A hasher keyed by `RandomState.seeded(seed)`.
    fn seeded(seed: U64) -> Hasher
    /// Appends one byte.
    fn write_u8(mut self, one: U8) -> Unit
    /// Appends a 16-bit little-endian value.
    fn write_u16(mut self, value: U16) -> Unit
    /// Appends a 32-bit little-endian value.
    fn write_u32(mut self, value: U32) -> Unit
    /// Appends a 64-bit little-endian value.
    fn write_u64(mut self, value: U64) -> Unit
    /// Appends every byte of `data`.
    fn write_bytes(mut self, data: Bytes) -> Unit
    /// Completes SipHash-1-3. The accumulator is unchanged.
    fn finish(self) -> U64
}

/// The structural hash under the fixed zero key.
pub fn hash(T: type(Eq, Hash), value: T) -> U64

/// The structural hash under one `RandomState` key.
pub fn hash_with(T: type(Eq, Hash), state: RandomState, value: T) -> U64
```

## Keyed builders

`std.random.random_state(I: type(Io), io: I) -> core.hash.RandomState` reads
16 host entropy bytes through `io.random_bytes` and assembles two
little-endian key words. `core.hash` has no dependency on `std.io` or any
other `std` module; the capability-bearing constructor lives in `std.random`
because randomness is the std layer's concern.

`RandomState.seeded` is deterministic across targets and processes. It is
appropriate for tests, simulations, and reproducibility. It is not a
cryptographic key-derivation function. The OS-backed builder is the
attack-facing source.

## Diagnostics

- 347: the `hash` or `hash_with` type argument is outside the structural
  domain. The diagnostic names the excluded categories and points at the
  trait declaration.
- A wrong argument type or arity uses the ordinary call diagnostics; the
  structural hash does not introduce an implicit conversion.

## Example

The example below is the complete content of
`examples/core.hash-v1.al`. The checksum is independent of host entropy and
of MIR layout.

```alder
module hello.core_hash_example

import core.hash { hash_with, RandomState }

// The executable core.hash v1 snapshot example. The manual Hasher stream and
// the structural hash must agree for the same canonical bytes.
pub fn core_hash_example() -> U64 {
    let state = RandomState.seeded(42)
    var h = state.hasher()
    h.write_u64(7)
    let manual = h.finish()
    if manual != hash_with(state, 7) { return 1 }
    return manual % 100000
}
```
