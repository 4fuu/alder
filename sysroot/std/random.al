module std.random

import core.num { u64_max, u32_max }

// The Milestone 8 randomness surface (docs/api/std.random-v1.md), seeded
// generator half, staged while two bootstrap gaps close:
//
// 1. Bitwise operators: `^` (and `&`, `|`, `~`) are specified
//    (docs/syntax.md, docs/language-semantics.md) but unimplemented; the
//    lexer rejects `^` and `~` outright and `&` and `|` do not parse as
//    binary operators. SplitMix64 is fixed by the snapshot contract and its
//    mixing step needs XOR. A verified-compiling stand-in (per-bit
//    arithmetic XOR) proved the rest of the module, including exact test
//    vectors; this file keeps the operator spellings that land.
// 2. `Rng.fill` takes an exclusive view argument on an inherent method:
//    a `mut buffer: MutSlice(U8)` parameter rejects the call with
//    diagnostic 101 unless the argument is a whole mutable local binding,
//    and the non-mut spelling rejects the indexed write with 103; the
//    identical trait method accepts both. `fill` keeps its frozen
//    signature and waits for the inherent-method path to match traits.
//
// The snapshot's OS forms (`fill`, `u64`, `u32`, `range_u64`, and
// `range_u32` on the module) additionally take the `std.io` capability and
// land with `std.io` v1; the `Rng` half takes no capability so tests and
// simulations stay deterministic by construction.
//
// `Rng` is SplitMix64 mixing over a single-word state with unbiased range
// reduction. Two generators seeded alike draw identical sequences on every
// target and in every process; the state layout stays private and no
// equality, hash, or display is public in v1. Range draws use rejection
// against the incomplete final block of the 64-bit stream, so every value in
// `low .. high - 1` is equally likely and no modulo bias exists. An empty or
// inverted range is an invariant violation and terminates through the
// ordinary checked-integer path: an inverted range fails the checked
// subtraction and an empty range fails the checked remainder.

/// A seeded deterministic generator. Pure value state: copying a generator
/// copies its stream position, and drawing mutates a uniquely owned
/// generator in place.
pub type Rng {
    state: U64
}

impl Rng {
    /// Deterministic seeding: the same seed produces the same sequence
    /// everywhere, forever.
    fn seeded(seed: U64) -> Rng {
        return Rng(state: seed)
    }

    /// The next 64 bits of the stream.
    fn next_u64(mut self) -> U64 {
        let advanced = self.state.add_wrapping(11400714819323198485)
        self.state = advanced
        return mix(advanced)
    }

    /// The next 32 bits of the stream: the high word of the next 64.
    fn next_u32(mut self) -> U32 {
        return (self.next_u64() >> 32).to_u32_wrapping()
    }

    /// The next value uniform over `low .. high - 1` by rejection, so the
    /// distribution carries no modulo bias. An empty or inverted range
    /// terminates through the invariant path.
    fn range_u64(mut self, low: U64, high: U64) -> U64 {
        let span = high - low
        let zone = u64_max() - u64_max() % span
        var picked: U64 = 0
        var spinning: Bool = true
        while spinning {
            let drawn = self.next_u64()
            if drawn < zone {
                picked = low + drawn % span
                spinning = false
            }
        }
        return picked
    }

    /// Uniform over `low .. high - 1`, same contract as `range_u64`.
    fn range_u32(mut self, low: U32, high: U32) -> U32 {
        let span = high - low
        let zone = u32_max() - u32_max() % span
        var picked: U32 = 0
        var spinning: Bool = true
        while spinning {
            let drawn = self.next_u32()
            if drawn < zone {
                picked = low + drawn % span
                spinning = false
            }
        }
        return picked
    }

    /// Fills `buffer` from the stream, eight bytes per draw, least
    /// significant byte first, with one final draw covering the tail.
    /// Deterministic given the seed.
    fn fill(mut self, mut buffer: MutSlice(U8)) -> Unit {
        var at: U64 = 0
        let total = buffer.len()
        while at + 8 <= total {
            let drawn = self.next_u64()
            buffer[at] = drawn.to_u8_wrapping()
            buffer[at + 1] = (drawn >> 8).to_u8_wrapping()
            buffer[at + 2] = (drawn >> 16).to_u8_wrapping()
            buffer[at + 3] = (drawn >> 24).to_u8_wrapping()
            buffer[at + 4] = (drawn >> 32).to_u8_wrapping()
            buffer[at + 5] = (drawn >> 40).to_u8_wrapping()
            buffer[at + 6] = (drawn >> 48).to_u8_wrapping()
            buffer[at + 7] = (drawn >> 56).to_u8_wrapping()
            at = at + 8
        }
        let rest = total - at
        if rest > 0 {
            let drawn = self.next_u64()
            var tail: U64 = 0
            while tail < rest {
                buffer[at + tail] = (drawn >> (tail * 8)).to_u8_wrapping()
                tail = tail + 1
            }
        }
    }
}

/// One SplitMix64 mixing step over the already-advanced state.
fn mix(advanced: U64) -> U64 {
    var z = advanced ^ (advanced >> 30)
    z = z.mul_wrapping(13787848793156543929)
    z = z ^ (z >> 27)
    z = z.mul_wrapping(10723151780598845931)
    return z ^ (z >> 31)
}
