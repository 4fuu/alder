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
