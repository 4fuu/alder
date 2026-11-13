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
