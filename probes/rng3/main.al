module hello.main

import std.random

pub fn main() -> I32 {
    var rng = random.Rng.seeded(42)
    let first = rng.next_u64()
    if first == 0 { return 1 }
    return 0
}
