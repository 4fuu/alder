module core.format

// Pure-Alder formatting contracts. This module never observes the host and
// never allocates outside the ordinary String/Vec value domain. The hosted
// float formatter and the StringBuilder convenience layer live in std.format;
// this module owns the specs, padding, and integer rendering.

/// Horizontal alignment of a formatted value within its width.
pub enum Align {
    Left
    Right
    Center
}

/// Sign policy for nonnegative integers.
pub enum Sign {
    Auto
    Plus
    Space
}

/// The value presentation requested by a FormatSpec. Integer renderers accept
/// Default, Decimal, HexLower, HexUpper, Binary, and Octal; float renderers in
/// std.format accept Default, General, Fixed, and Scientific.
pub enum FormatKind {
    Default
    Decimal
    HexLower
    HexUpper
    Binary
    Octal
    General
    Fixed
    Scientific
}

/// A formatting request. Width counts Unicode scalar values, not bytes, so
/// padding non-ASCII text aligns by character. Fill is one ASCII graphic byte
/// (0x20 through 0x7e). Precision is meaningful only to the float renderers.
pub type FormatSpec {
    pub width: U64
    pub fill: U8
    pub align: Align
    pub sign: Sign
    pub alternate: Bool
    pub zero_pad: Bool
    pub precision: Option(U64)
    pub kind: FormatKind
}

pub enum FormatError {
    /// Fill was not one ASCII graphic byte.
    InvalidFill
    /// The kind is not accepted by this formatter.
    InvalidKind
    /// The formatter does not support this otherwise valid feature.
    Unsupported
}

impl FormatSpec {
    /// No padding, decimal integers, automatic sign, and no precision.
    fn plain() -> FormatSpec {
        return FormatSpec(width: 0, fill: 32, align: Right, sign: Auto, alternate: false, zero_pad: false, precision: None, kind: Default)
    }
}

fn scalar_count(data: Bytes) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < data.len() {
        let byte = data.byte(at)
        if byte & 192 != 128 { count = count + 1 }
        at = at + 1
    }
    return count
}

fn ascii_string(data: Vec(U8)) -> String {
    let size = data.len()
    return match data.slice(0, size).to_bytes().to_string_checked() {
        Some(text) => text
        None => ""
    }
}

fn valid_fill(spec: FormatSpec) -> Bool {
    return spec.fill >= 32 && spec.fill <= 126
}

/// Pads `text` to `spec.width` scalar values with `spec.fill`. The extra
/// column of an odd center gap goes on the right. Alignment is ignored when
/// the text is already at least the requested width.
pub fn pad(text: String, spec: FormatSpec) -> Result(String, FormatError) {
    if !valid_fill(spec) { return Err(FormatError.InvalidFill) }
    let data = text.to_bytes()
    let count = scalar_count(data)
    if spec.width <= count {
        return match data.to_string_checked() {
            Some(value) => Ok(value)
            None => Err(FormatError.Unsupported)
        }
    }
    let total = spec.width - count
    var left: U64 = 0
    var right: U64 = 0
    if spec.align == Left { right = total }
    if spec.align == Right { left = total }
    if spec.align == Center {
        left = total / 2
        right = total - left
    }
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < left {
        out.push(spec.fill)
        at = at + 1
    }
    at = 0
    while at < data.len() {
        out.push(data.byte(at))
        at = at + 1
    }
    at = 0
    while at < right {
        out.push(spec.fill)
        at = at + 1
    }
    return Ok(ascii_string(out))
}

fn integer_digits(value: U64, base: U64, upper: Bool) -> Vec(U8) {
    var digits: Vec(U8) = Vec.new(U8)
    if value == 0 { digits.push(48) } else {
        var current = value
        while current != 0 {
            let digit = (current % base).to_u8_wrapping()
            var byte: U8 = 0
            if digit < 10 {
                let offset: U8 = 48
                byte = offset + digit
            } else {
                var offset: U8 = 65
                if !upper { offset = 97 }
                byte = offset + (digit - 10)
            }
            digits.push(byte)
            current = current / base
        }
    }
    return digits
}

fn integer_body(value: U64, spec: FormatSpec) -> Result(Vec(U8), FormatError) {
    var base: U64 = 10
    var upper = false
    var prefix: Vec(U8) = Vec.new(U8)
    if spec.kind == Decimal || spec.kind == Default { base = 10 }
    else if spec.kind == HexLower { base = 16
        if spec.alternate { prefix.push(48)
            prefix.push(120) } }
    else if spec.kind == HexUpper { base = 16
        upper = true
        if spec.alternate { prefix.push(48)
            prefix.push(88) } }
    else if spec.kind == Binary { base = 2
        if spec.alternate { prefix.push(48)
            prefix.push(98) } }
    else if spec.kind == Octal { base = 8
        if spec.alternate { prefix.push(48)
            prefix.push(111) } }
    else { return Err(FormatError.InvalidKind) }
    if spec.precision != None { return Err(FormatError.Unsupported) }
    var body: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < prefix.len() {
        body.push(prefix[at])
        at = at + 1
    }
    let digits = integer_digits(value, base, upper)
    var index = digits.len()
    while index > 0 {
        body.push(digits[index - 1])
        index = index - 1
    }
    return Ok(body)
}

fn format_unsigned(value: U64, spec: FormatSpec, sign: U8) -> Result(String, FormatError) {
    if !valid_fill(spec) { return Err(FormatError.InvalidFill) }
    let body = try integer_body(value, spec)
    let body_count = body.len()
    var sign_count: U64 = 0
    if sign != 0 { sign_count = 1 }
    let total = sign_count + body_count
    if spec.width <= total { return Ok(ascii_string(apply_sign(sign, body))) }
    if spec.zero_pad && spec.align == Right {
        var out: Vec(U8) = Vec.new(U8)
        if sign != 0 { out.push(sign) }
        var zeros = spec.width - total
        while zeros > 0 {
            out.push(48)
            zeros = zeros - 1
        }
        var at: U64 = 0
        while at < body_count {
            out.push(body[at])
            at = at + 1
        }
        return Ok(ascii_string(out))
    }
    return pad(ascii_string(apply_sign(sign, body)), spec)
}

fn apply_sign(sign: U8, body: Vec(U8)) -> Vec(U8) {
    var out: Vec(U8) = Vec.new(U8)
    if sign != 0 { out.push(sign) }
    var at: U64 = 0
    while at < body.len() {
        out.push(body[at])
        at = at + 1
    }
    return out
}

fn positive_sign(spec: FormatSpec) -> U8 {
    if spec.sign == Plus { return 43 }
    if spec.sign == Space { return 32 }
    return 0
}

/// Formats an unsigned integer in decimal or an alternate base.
pub fn format_u64(value: U64, spec: FormatSpec) -> Result(String, FormatError) {
    return format_unsigned(value, spec, positive_sign(spec))
}

/// Formats a signed integer in decimal or an alternate base. The magnitude of
/// I64 min is computed without signed overflow.
pub fn format_i64(value: I64, spec: FormatSpec) -> Result(String, FormatError) {
    var sign = positive_sign(spec)
    var magnitude = value.to_u64_wrapping()
    if value < 0 {
        sign = 45
        let zero: U64 = 0
        magnitude = zero.sub_wrapping(magnitude)
    }
    return format_unsigned(magnitude, spec, sign)
}
