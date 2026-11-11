module hello.core_panic_example

import core.panic { assert, assert_eq, assert_ne }

// The executable core.panic v1 snapshot example. Every assertion passes, so
// the run is deterministic and returns a fixed checksum.
pub fn core_panic_example() -> U64 {
    var total: U64 = 0
    assert(true, "never printed")
    assert_eq(U64, 7, 7)
    assert_ne(U64, 7, 8)
    total = total + 1
    assert_eq(String, "alder", "alder")
    total = total + 10
    return total
}
