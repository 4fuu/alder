module core.num

// The Milestone 8 integer foundation helpers: exact type limits and the
// explicit overflow-mode forms of absolute value. Every limit is the exact
// boundary of its type; every helper is total, deterministic, and free of
// OS access.
//
// Overflow behavior is always explicit in the name, matching the builtin
// method surface: `*_checked` yields None instead of overflowing, and
// `*_wrapping` wraps on the two's-complement pattern.
//
// Later snapshots add the checked division and remainder pairs, explicit
// widening and narrowing conversions, and the parse and format foundations.
// Conversions need a source-level conversion primitive the language does not
// expose yet; parse and format need the String and Bytes byte surface.

/// The smallest I8 value.
pub fn i8_min() -> I8 {
    return -128
}

/// The largest I8 value.
pub fn i8_max() -> I8 {
    return 127
}

/// The smallest I16 value.
pub fn i16_min() -> I16 {
    return -32768
}

/// The largest I16 value.
pub fn i16_max() -> I16 {
    return 32767
}

/// The smallest I32 value.
pub fn i32_min() -> I32 {
    return -2147483648
}

/// The largest I32 value.
pub fn i32_max() -> I32 {
    return 2147483647
}

/// The smallest I64 value.
pub fn i64_min() -> I64 {
    return -9223372036854775808
}

/// The largest I64 value.
pub fn i64_max() -> I64 {
    return 9223372036854775807
}

/// The largest U8 value; the smallest is the literal 0.
pub fn u8_max() -> U8 {
    return 255
}

/// The largest U16 value; the smallest is the literal 0.
pub fn u16_max() -> U16 {
    return 65535
}

/// The largest U32 value; the smallest is the literal 0.
pub fn u32_max() -> U32 {
    return 4294967295
}

/// The largest U64 value; the smallest is the literal 0.
pub fn u64_max() -> U64 {
    return 18446744073709551615
}

/// Absolute value with the checked overflow mode: None exactly for the
/// type's minimum, whose negation has no positive representative.
pub fn i8_abs_checked(value: I8) -> Option(I8) {
    if value < 0 {
        let zero: I8 = 0
        return zero.sub_checked(value)
    }
    return Some(value)
}

/// Absolute value with the checked overflow mode: None exactly for the
/// type's minimum, whose negation has no positive representative.
pub fn i16_abs_checked(value: I16) -> Option(I16) {
    if value < 0 {
        let zero: I16 = 0
        return zero.sub_checked(value)
    }
    return Some(value)
}

/// Absolute value with the checked overflow mode: None exactly for the
/// type's minimum, whose negation has no positive representative.
pub fn i32_abs_checked(value: I32) -> Option(I32) {
    if value < 0 {
        let zero: I32 = 0
        return zero.sub_checked(value)
    }
    return Some(value)
}

/// Absolute value with the checked overflow mode: None exactly for the
/// type's minimum, whose negation has no positive representative.
pub fn i64_abs_checked(value: I64) -> Option(I64) {
    if value < 0 {
        let zero: I64 = 0
        return zero.sub_checked(value)
    }
    return Some(value)
}

/// Absolute value with the wrapping overflow mode: the negation of the
/// type's minimum wraps back to the minimum itself.
pub fn i8_abs_wrapping(value: I8) -> I8 {
    if value < 0 {
        let zero: I8 = 0
        return zero.sub_wrapping(value)
    }
    return value
}

/// Absolute value with the wrapping overflow mode: the negation of the
/// type's minimum wraps back to the minimum itself.
pub fn i16_abs_wrapping(value: I16) -> I16 {
    if value < 0 {
        let zero: I16 = 0
        return zero.sub_wrapping(value)
    }
    return value
}

/// Absolute value with the wrapping overflow mode: the negation of the
/// type's minimum wraps back to the minimum itself.
pub fn i32_abs_wrapping(value: I32) -> I32 {
    if value < 0 {
        let zero: I32 = 0
        return zero.sub_wrapping(value)
    }
    return value
}

/// Absolute value with the wrapping overflow mode: the negation of the
/// type's minimum wraps back to the minimum itself.
pub fn i64_abs_wrapping(value: I64) -> I64 {
    if value < 0 {
        let zero: I64 = 0
        return zero.sub_wrapping(value)
    }
    return value
}
