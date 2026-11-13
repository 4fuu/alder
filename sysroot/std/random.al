module std.random

import core.hash { RandomState }
import core.num { u64_max, u32_max }
import std.io { Io }

// The Milestone 8 randomness surface (docs/api/std.random-v1.md). The module
// forms take the `std.io` capability and read host entropy; the seeded `Rng`
// half takes no capability, so tests and simulations stay deterministic by
// construction.
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

/// One process-randomized SipHash key pair from host entropy. This constructor
/// lives here, not in `core.hash`, so the core module stays below std and
/// takes no I/O capability. The key words are assembled least significant
/// byte first, matching the SipHash key order.
pub fn random_state(I: type(Io), io: I) -> RandomState {
    var bytes: Array(U8, 16) = [
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    ]
    io.random_bytes(bytes.slice_mut(0, 16))
    var k0 = bytes[0].to_u64()
    k0 = k0 | (bytes[1].to_u64() << 8)
    k0 = k0 | (bytes[2].to_u64() << 16)
    k0 = k0 | (bytes[3].to_u64() << 24)
    k0 = k0 | (bytes[4].to_u64() << 32)
    k0 = k0 | (bytes[5].to_u64() << 40)
    k0 = k0 | (bytes[6].to_u64() << 48)
    k0 = k0 | (bytes[7].to_u64() << 56)
    var k1 = bytes[8].to_u64()
    k1 = k1 | (bytes[9].to_u64() << 8)
    k1 = k1 | (bytes[10].to_u64() << 16)
    k1 = k1 | (bytes[11].to_u64() << 24)
    k1 = k1 | (bytes[12].to_u64() << 32)
    k1 = k1 | (bytes[13].to_u64() << 40)
    k1 = k1 | (bytes[14].to_u64() << 48)
    k1 = k1 | (bytes[15].to_u64() << 56)
    return RandomState.from_words(k0, k1)
}

/// Fills `buffer` with unpredictable bytes from the operating system through
/// the capability. Randomness is essential for the security properties
/// callers rely on, so a host failure terminates through the invariant path.
pub fn fill(I: type(Io), io: I, buffer: MutSlice(U8)) -> Unit {
    io.random_bytes(buffer)
    return
}

/// One unpredictable `U64` from the operating system, assembled from eight
/// entropy bytes least significant first.
pub fn u64(I: type(Io), io: I) -> U64 {
    var bytes: Array(U8, 8) = [0, 0, 0, 0, 0, 0, 0, 0]
    io.random_bytes(bytes.slice_mut(0, 8))
    var value = bytes[0].to_u64()
    value = value | (bytes[1].to_u64() << 8)
    value = value | (bytes[2].to_u64() << 16)
    value = value | (bytes[3].to_u64() << 24)
    value = value | (bytes[4].to_u64() << 32)
    value = value | (bytes[5].to_u64() << 40)
    value = value | (bytes[6].to_u64() << 48)
    value = value | (bytes[7].to_u64() << 56)
    return value
}

/// One unpredictable `U32` from the operating system, assembled from four
/// entropy bytes least significant first.
pub fn u32(I: type(Io), io: I) -> U32 {
    var bytes: Array(U8, 4) = [0, 0, 0, 0]
    io.random_bytes(bytes.slice_mut(0, 4))
    var value = bytes[0].to_u32()
    value = value | (bytes[1].to_u32() << 8)
    value = value | (bytes[2].to_u32() << 16)
    value = value | (bytes[3].to_u32() << 24)
    return value
}

/// One unpredictable value uniform over `low .. high - 1` by rejection, so
/// the distribution carries no modulo bias. An empty or inverted range
/// terminates through the invariant path.
pub fn range_u64(I: type(Io), io: I, low: U64, high: U64) -> U64 {
    let span = high - low
    let zone = u64_max() - u64_max() % span
    var picked: U64 = 0
    var spinning: Bool = true
    while spinning {
        let drawn = u64(io)
        if drawn < zone {
            picked = low + drawn % span
            spinning = false
        }
    }
    return picked
}

/// One unpredictable value uniform over `low .. high - 1`, same contract as
/// `range_u64`.
pub fn range_u32(I: type(Io), io: I, low: U32, high: U32) -> U32 {
    let span = high - low
    let zone = u32_max() - u32_max() % span
    var picked: U32 = 0
    var spinning: Bool = true
    while spinning {
        let drawn = u32(io)
        if drawn < zone {
            picked = low + drawn % span
            spinning = false
        }
    }
    return picked
}

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
    fn fill(mut self, buffer: MutSlice(U8)) -> Unit {
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
