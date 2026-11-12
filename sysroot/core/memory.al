module core.memory

// The Milestone 8.1 size and alignment queries for generic code
// (docs/api/core.memory-v1.md). Both functions are compile-time facts about
// the checked type argument, not runtime calls: the compiler reads the target
// C compiler's sizeof/_Alignof for the lowered representation of each
// concrete instantiation. The module allocates nothing and exposes no raw
// memory operation.
//
// Unit is the one fixed by-contract exception to the lowered representation:
// it occupies no bytes and has alignment 1, even though the C backend spells
// its storage as uint8_t. Every other answer follows the target compiler and
// is therefore a fact about this build, not a promise of a stable
// cross-target ABI.

/// The size in bytes of the lowered representation of `T`. `Unit` is 0.
pub fn size_of(T: type) -> U64 {
    return 0
}

/// The alignment in bytes of the lowered representation of `T`. `Unit` is 1.
pub fn align_of(T: type) -> U64 {
    return 1
}
