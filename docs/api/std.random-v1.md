# `std.random` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; OS and seeded halves implemented**

This is the versioned public snapshot for randomness. It is normative together
with the executable example
[`examples/std.random-v1.al`](examples/std.random-v1.al). The module lives at
`<sysroot>/std/random.al`; both the OS forms and the seeded `Rng` half are
installed.

Snapshot v1 covers OS randomness through the capability and a seeded
deterministic generator with unbiased ranges. OS randomness observes host
nondeterminism, so it takes the capability; the seeded generator is pure and
takes none, which is what makes simulation and test code deterministic. The
public surfaces are written once against `I: type(Io)`.

## Signatures

```alder
module std.random

import std.io { Io }

impl random {
    /// Fills `buffer` with unpredictable bytes from the operating system
    /// through the capability. Randomness is essential for the security
    /// properties callers rely on, so a host failure terminates through the
    /// invariant path instead of returning an error.
    pub fn fill(I: type(Io), io: I, buffer: MutSlice(U8))
    /// One unpredictable `U64` from the operating system.
    pub fn u64(I: type(Io), io: I) -> U64
    /// One unpredictable `U32` from the operating system.
    pub fn u32(I: type(Io), io: I) -> U32
    /// One unpredictable value uniform over `low .. high - 1`. The range
    /// must be nonempty (`low < high`); an empty or inverted range
    /// terminates through the invariant path.
    pub fn range_u64(I: type(Io), io: I, low: U64, high: U64) -> U64
    /// One unpredictable value uniform over `low .. high - 1`, same
    /// contract as `range_u64`.
    pub fn range_u32(I: type(Io), io: I, low: U32, high: U32) -> U32
}

/// A seeded deterministic generator (SplitMix64 mixing with unbiased range
/// reduction). Pure value state: copying a generator copies its stream
/// position, and drawing mutates a uniquely owned generator in place. Two
/// generators seeded with the same seed produce the same sequence on every
/// target and in every process.
pub type Rng {
    // private: state
}

impl Rng {
    /// Deterministic seeding: the same seed produces the same sequence
    /// everywhere, forever.
    pub fn seeded(seed: U64) -> Rng
    /// The next 64 bits of the stream.
    pub fn next_u64(mut self) -> U64
    /// The next 32 bits of the stream.
    pub fn next_u32(mut self) -> U32
    /// The next value uniform over `low .. high - 1` by rejection, so the
    /// distribution carries no modulo bias. An empty or inverted range
    /// terminates through the invariant path.
    pub fn range_u64(mut self, low: U64, high: U64) -> U64
    /// Uniform over `low .. high - 1`, same contract.
    pub fn range_u32(mut self, low: U32, high: U32) -> U32
    /// Fills `buffer` from the stream. Deterministic given the seed.
    pub fn fill(mut self, buffer: MutSlice(U8))
}
```

Equality, `Hash`, and `Display` for `Rng` are not public in v1; generator
state is opaque by contract, and tests assert drawn sequences, not state
layout.

## Contracts

- OS randomness flows through the capability and is written once against
  `I: type(Io)`; a `Blocking` instantiation lowers to a direct host call
  and a future `AsyncIo` instantiation suspends at the same call.
- The seeded generator is pure Alder: no host call, no capability, no
  platform dependence. It exists so tests and simulations get determinism by
  construction; it is not a cryptographic primitive and the contracts say so.
- Range draws are unbiased on both the OS and seeded forms (rejection
  sampling), so every value in `low .. high - 1` is equally likely.
- `fill` and `range_*` on both forms treat empty or inverted ranges as
  invariant violations; callers that need an empty-range-tolerant draw check
  the range first.
- Behavior tests seed fixed values, never the OS source, so failures
  reproduce byte-for-byte.
- Tests that exercise OS randomness assert shape only (length, bounds,
  non-equality of successive draws), never values.

## Example

The example below is the complete content of
`examples/std.random-v1.al`. Deterministic
contributions come from the seeded generator; OS randomness contributes only
shape, so the checksum is stable.

```alder
module hello.std_random_example

import std.io { Blocking }
import std.random

// The executable std.random v1 snapshot example. Seeded draws dominate the
// checksum; OS randomness contributes shape checks only.

pub fn std_random_example(io: Blocking) -> U64 {
    var total: U64 = 0

    // Deterministic seeded sequence: fixed seed, fixed draws.
    var rng = random.Rng.seeded(42)
    let first = rng.next_u64()
    let second = rng.next_u64()
    if first != second { total = total + 1 }
    total = total + first % 1000
    total = total + second % 1000

    // Same seed, same sequence.
    var twin = random.Rng.seeded(42)
    let twin_first = twin.next_u64()
    if twin_first == first { total = total + 10 }

    // Unbiased bounded draws stay in range and are deterministic.
    var dice = random.Rng.seeded(7)
    var rolls: U64 = 0
    var at: U64 = 0
    while at < 20 {
        let roll = dice.range_u64(1, 7)
        if roll >= 1 && roll <= 6 { rolls = rolls + roll }
        at = at + 1
    }
    total = total + rolls

    // Seeded fill reproduces byte-for-byte.
    var filler = random.Rng.seeded(99)
    var a: Array(U8, 8) = [0, 0, 0, 0, 0, 0, 0, 0]
    let left = a.slice_mut(0, 8)
    filler.fill(left)
    var again = random.Rng.seeded(99)
    var b: Array(U8, 8) = [0, 0, 0, 0, 0, 0, 0, 0]
    let right = b.slice_mut(0, 8)
    again.fill(right)
    var same = true
    var index: U64 = 0
    while index < 8 {
        if left[index] != right[index] { same = false }
        index = index + 1
    }
    if same { total = total + 100 }

    // OS randomness: shape only, never values. Drawing both forms is the
    // exercise; the contribution does not depend on the drawn value.
    let os_a = random.u64(io)
    let os_b = random.u32(io)
    total = total + 1000
    let rolled = random.range_u64(io, 5, 10)
    if rolled >= 5 && rolled < 10 { total = total + 10000 }

    return total
}
```

## Dependencies

- Builds on the `std.io` capability (`random_bytes`) for the OS forms.
- The SplitMix64 core uses the landed builtin overflow methods
  (`add_wrapping`, `mul_wrapping`, and siblings on the eight integer types),
  and the example uses the settled total conversion methods (`to_u64()` and
  family).
- The example avoids string building, interpolation, and `while let`.
