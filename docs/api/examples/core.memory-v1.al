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
