module hello.main

import std.random { Rng }

pub fn main() -> I32 {
    // Deterministic seeded sequence: fixed seed, fixed draws.
    var rng = Rng.seeded(42)
    let first = rng.next_u64()
    let second = rng.next_u64()
    if first != 13679457532755275413 { return 1 }
    if second != 2949826092126892291 { return 2 }

    // Same seed, same sequence.
    var twin = Rng.seeded(42)
    let twin_first = twin.next_u64()
    if twin_first != first { return 3 }

    // Different seed, different stream.
    var other = Rng.seeded(43)
    let other_first = other.next_u64()
    if other_first == first { return 4 }

    // Unbiased bounded draws stay in range; the 20-roll sum is a fixed
    // value derived independently of the implementation.
    var dice = Rng.seeded(7)
    var rolls: U64 = 0
    var at: U64 = 0
    while at < 20 {
        let roll = dice.range_u64(1, 7)
        if roll < 1 || roll > 6 { return 5 }
        rolls = rolls + roll
        at = at + 1
    }
    if rolls != 71 { return 6 }

    // Full-range draws still work.
    let wide = dice.range_u64(0, 18446744073709551615)
    let wide_again = dice.range_u64(0, 18446744073709551615)

    // next_u32 determinism and bounds.
    var small = Rng.seeded(42)
    let a = small.next_u32()
    let b = small.next_u32()
    if a != (first >> 32).to_u32_wrapping() { return 7 }
    if b != (second >> 32).to_u32_wrapping() { return 8 }

    // range_u32 unbiasedness is structural; check bounds and a fixed sum.
    var u = Rng.seeded(5)
    var hits: U64 = 0
    var idx: U64 = 0
    while idx < 3 {
        let v = u.range_u32(0, 5)
        if v > 4 { return 9 }
        hits = hits + v.to_u64()
        idx = idx + 1
    }
    if hits != 8 { return 10 }

    // Seeded fill reproduces byte-for-byte, least significant byte first.
    var filler = Rng.seeded(99)
    let source: Array(U8, 8) = [0, 0, 0, 0, 0, 0, 0, 0]
    let left = source.slice_mut(0, 8)
    filler.fill(left)
    let wanted: Array(U8, 8) = [227, 107, 71, 76, 54, 169, 243, 66]
    var index: U64 = 0
    while index < 8 {
        if left[index] != wanted[index] { return 11 }
        index = index + 1
    }
    var again = Rng.seeded(99)
    let other_bytes: Array(U8, 8) = [0, 0, 0, 0, 0, 0, 0, 0]
    let right = other_bytes.slice_mut(0, 8)
    again.fill(right)
    index = 0
    while index < 8 {
        if left[index] != right[index] { return 12 }
        index = index + 1
    }

    // A longer fill crosses the eight-byte boundary and covers the tail.
    var tailer = Rng.seeded(1234)
    let bag: Array(U8, 21) = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let view = bag.slice_mut(0, 21)
    tailer.fill(view)

    // Value semantics: a copy keeps drawing the original stream position.
    var keeper = Rng.seeded(42)
    let kept_first = keeper.next_u64()
    if kept_first != first { return 13 }
    var copy = keeper
    let copy_next = copy.next_u64()
    let keeper_next = keeper.next_u64()
    if copy_next != second { return 14 }
    if keeper_next != 5139283748462763858 { return 15 }
    return 0
}
