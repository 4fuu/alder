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

/// Failure categories for exact decimal integer parsing.
pub enum ParseIntError {
    /// The input was empty.
    Empty
    /// A byte was not an ASCII decimal digit, or a sign had no digits after it.
    InvalidDigit
    /// A minus sign was used with an unsigned target.
    MinusOnUnsigned
    /// The magnitude does not fit the target type.
    Overflow
}

fn scan_magnitude(data: Bytes, start: U64, limit: U64) -> Result(U64, ParseIntError) {
    var value: U64 = 0
    var at = start
    while at < data.len() {
        let byte = data.byte(at)
        if byte < 48 || byte > 57 { return Err(ParseIntError.InvalidDigit) }
        let digit = (byte - 48).to_u64()
        let scaled = value.mul_checked(10)
        var scaled_value: U64 = 0
        match scaled {
            Some(next) => { scaled_value = next }
            None => { return Err(ParseIntError.Overflow) }
        }
        let added = scaled_value.add_checked(digit)
        var next_value: U64 = 0
        match added {
            Some(next) => { next_value = next }
            None => { return Err(ParseIntError.Overflow) }
        }
        if next_value > limit { return Err(ParseIntError.Overflow) }
        value = next_value
        at = at + 1
    }
    if at == start { return Err(ParseIntError.InvalidDigit) }
    return Ok(value)
}

/// Parses an unsigned decimal integer. Whitespace is not accepted; one
/// optional leading `+` is.
pub fn parse_u64(text: String) -> Result(U64, ParseIntError) {
    let data = text.to_bytes()
    if data.len() == 0 { return Err(ParseIntError.Empty) }
    let first = data.byte(0)
    var start: U64 = 0
    if first == 43 { start = 1 }
    if first == 45 { return Err(ParseIntError.MinusOnUnsigned) }
    if start == data.len() { return Err(ParseIntError.InvalidDigit) }
    return scan_magnitude(data, start, u64_max())
}

/// Parses a signed decimal integer. Whitespace is not accepted; one optional
/// leading `+` or `-` is.
pub fn parse_i64(text: String) -> Result(I64, ParseIntError) {
    let data = text.to_bytes()
    if data.len() == 0 { return Err(ParseIntError.Empty) }
    let first = data.byte(0)
    var negative = false
    var start: U64 = 0
    if first == 43 { start = 1 }
    if first == 45 {
        negative = true
        start = 1
    }
    if start == data.len() { return Err(ParseIntError.InvalidDigit) }
    var limit = u64_max() / 2
    if negative { limit = limit + 1 }
    let magnitude = try scan_magnitude(data, start, limit)
    if negative {
        let zero: U64 = 0
        return Ok(zero.sub_wrapping(magnitude).to_i64_wrapping())
    }
    return Ok(magnitude.to_i64_wrapping())
}
