module std.text

// The Milestone 8 text foundation over the builtin UTF-8 `String` and
// arbitrary `Bytes`: checked validation with the failing byte offset,
// scalar decoding and counting, exact-byte search, split, and replace, the
// checked bytes-to-text conversion, and the functional `StringBuilder`.
// Case mapping and Unicode normalization join a later snapshot amendment
// with the toolchain-versioned Unicode tables.
//
// String values are UTF-8 text by construction: the checker validates every
// string literal, and the only builtin bridge from bytes revalidates. The
// scalar functions therefore treat their argument as valid text; the decode
// walk stays total anyway, so the functions degrade to the valid prefix
// rather than panic if that invariant is ever widened.
//
// `StringBuilder` is a value with functional updates: every `push_*` returns
// a new builder and the caller rebinds, because a method cannot assign
// through `self` yet. Its storage therefore rebuilds on each push, a known
// cost that the byte-buffer bridge replaces when it lands.

import std.bytes { of_byte, empty }

/// Failure of a checked text operation.
pub enum TextError {
    /// The bytes held an invalid UTF-8 sequence starting at this offset.
    InvalidUtf8(at: U64)
    /// The scalar is not a Unicode scalar value (a surrogate or above
    /// U+10FFFF) and has no UTF-8 encoding.
    InvalidScalar(value: U32)
}

/// One decoded Unicode scalar value and its encoded byte length.
pub type Scalar {
    pub value: U32
    pub size: U64
}

/// Validates `data` as UTF-8: the number of scalar values it encodes, or
/// the byte offset where the first invalid sequence starts. Overlong
/// encodings, surrogate encodings, anything above U+10FFFF, truncated
/// sequences, and stray continuation bytes are all invalid.
pub fn validate(data: Bytes) -> Result(U64, TextError) {
    let size = data.len()
    var at: U64 = 0
    var count: U64 = 0
    while at < size {
        match decode(data, at) {
            Ok(scalar) => {
                count = count + 1
                at = at + scalar.size
            }
            Err(failed) => { return Err(InvalidUtf8(failed)) }
        }
    }
    return Ok(count)
}

/// The text for bytes known to be UTF-8: the checked bytes-to-text
/// conversion with the failing offset in the error.
pub fn from_utf8(data: Bytes) -> Result(String, TextError) {
    match validate(data) {
        Ok(_) => {}
        Err(failure) => { return Err(failure) }
    }
    // The builtin bridge validates again and cannot fail for bytes
    // `validate` accepted; the `None` branch is unreachable here.
    let text = data.to_string_checked()
    var out: Result(String, TextError) = Err(InvalidUtf8(0))
    match text {
        Some(value) => { out = Ok(value) }
        None => {}
    }
    return out
}

/// The scalar starting at byte offset `at`: `None` when `at` is out of
/// bounds or points into the middle of a sequence.
pub fn scalar_at(text: String, at: U64) -> Option(Scalar) {
    let data = text.to_bytes()
    if at >= data.len() {
        return None
    }
    return decode_or_none(data, at)
}

/// The number of scalar values in the text.
pub fn scalar_count(text: String) -> U64 {
    let data = text.to_bytes()
    let size = data.len()
    var at: U64 = 0
    var count: U64 = 0
    while at < size {
        match decode(data, at) {
            Ok(scalar) => {
                count = count + 1
                at = at + scalar.size
            }
            Err(_) => { return count }
        }
    }
    return count
}

/// Every scalar value in the text, in order.
pub fn scalars(text: String) -> Vec(U32) {
    let data = text.to_bytes()
    let size = data.len()
    var out: Vec(U32) = Vec.new(U32)
    var at: U64 = 0
    while at < size {
        match decode(data, at) {
            Ok(scalar) => {
                out.push(scalar.value)
                at = at + scalar.size
            }
            Err(_) => { return out }
        }
    }
    return out
}

/// The first byte offset of `needle` in `text`, `None` when absent. An
/// empty `needle` matches at offset zero.
pub fn find(text: String, needle: String) -> Option(U64) {
    return find_from(text, needle, 0)
}

/// The first byte offset of `needle` at or after `from`, `None` when
/// absent. Matching is exact bytes: no case folding, no normalization, and
/// matches may begin anywhere, including inside a multi-byte sequence.
pub fn find_from(text: String, needle: String, from: U64) -> Option(U64) {
    let size = text.len()
    let width = needle.len()
    if from > size {
        return None
    }
    if width == 0 {
        return Some(from)
    }
    let data = text.to_bytes()
    let piece = needle.to_bytes()
    var at: U64 = from
    while at + width <= size {
        if bytes_match(data, piece, at) {
            return Some(at)
        }
        at = at + 1
    }
    return None
}

/// Whether `needle` matches byte for byte at `at`. The caller guarantees
/// `at + needle.len()` stays within `data`.
fn bytes_match(data: Bytes, needle: Bytes, at: U64) -> Bool {
    let width = needle.len()
    var index: U64 = 0
    while index < width {
        if data.byte(at + index) != needle.byte(index) {
            return false
        }
        index = index + 1
    }
    return true
}

/// Splits `text` at every non-overlapping occurrence of `sep`, in order,
/// with the separators removed and empty pieces kept. An empty `sep`
/// yields the whole text as one piece.
pub fn split(text: String, sep: String) -> Vec(String) {
    let width = sep.len()
    var out: Vec(String) = Vec.new(String)
    if width == 0 {
        out.push(text)
        return out
    }
    var from: U64 = 0
    var searching: Bool = true
    while searching {
        let hit = find_from(text, sep, from)
        match hit {
            Some(at) => {
                out.push(text.slice(from, at))
                from = at + width
            }
            None => {
                searching = false
                out.push(text.slice(from, text.len()))
            }
        }
    }
    return out
}

/// Replaces every non-overlapping occurrence of `from` with `to`, scanning
/// left to right. An empty `from` returns the text unchanged.
pub fn replace(text: String, from: String, to: String) -> String {
    let width = from.len()
    if width == 0 {
        return text
    }
    var out: String = ""
    var at: U64 = 0
    var searching: Bool = true
    while searching {
        let hit = find_from(text, from, at)
        match hit {
            Some(found) => {
                out = out.concat(text.slice(at, found))
                out = out.concat(to)
                at = found + width
            }
            None => {
                searching = false
                out = out.concat(text.slice(at, text.len()))
            }
        }
    }
    return out
}

/// One growable text accumulator with functional updates. Pushed content
/// must be valid UTF-8, so `finish` is total.
pub type StringBuilder {
    data: String
}

impl StringBuilder {
    /// The empty builder.
    fn new() -> StringBuilder {
        return StringBuilder(data: "")
    }

    /// The number of bytes accumulated so far.
    fn len(self) -> U64 {
        return self.data.len()
    }

    /// Appends text.
    fn push_text(self, text: String) -> StringBuilder {
        return StringBuilder(data: self.data.concat(text))
    }

    /// Appends bytes as text: `Err` when the bytes are not valid UTF-8.
    fn push_utf8(self, data: Bytes) -> Result(StringBuilder, TextError) {
        match validate(data) {
            Ok(_) => {}
            Err(failure) => { return Err(failure) }
        }
        // The builtin bridge validates again and cannot fail for bytes
        // `validate` accepted; `None` is unreachable here.
        let text = data.to_string_checked()
        return match text {
            Some(value) => Ok(StringBuilder(data: self.data.concat(value)))
            None => Err(InvalidUtf8(0))
        }
    }

    /// Appends one scalar value's UTF-8 encoding: `Err` for a surrogate or
    /// a value above U+10FFFF.
    fn push_scalar(self, value: U32) -> Result(StringBuilder, TextError) {
        return match encode_scalar(value) {
            Ok(text) => Ok(StringBuilder(data: self.data.concat(text)))
            Err(failure) => Err(failure)
        }
    }

    /// The accumulated text.
    fn finish(self) -> String {
        return self.data
    }
}

/// Builds the byte sequence holding exactly the value `v` carries. Every
/// value is already within one byte by construction at each call site, so
/// the wrapping conversion is exact; the checked form would only restate
/// the callers' proofs.
fn unit_of(v: U64) -> Bytes {
    return of_byte(v.to_u8_wrapping())
}

/// The UTF-8 encoding of one scalar value.
fn encode_scalar(value: U32) -> Result(String, TextError) {
    let wide = value.to_u64()
    if wide > 1114111 {
        return Err(InvalidScalar(value))
    }
    if wide >= 55296 && wide <= 57343 {
        return Err(InvalidScalar(value))
    }
    var out: Bytes = empty()
    if wide < 128 {
        out = out.concat(unit_of(wide))
    } else {
        if wide < 2048 {
            out = out.concat(unit_of(wide / 64 + 192))
            out = out.concat(unit_of(wide % 64 + 128))
        } else {
            if wide < 65536 {
                out = out.concat(unit_of(wide / 4096 + 224))
                out = out.concat(unit_of(wide / 64 % 64 + 128))
                out = out.concat(unit_of(wide % 64 + 128))
            } else {
                out = out.concat(unit_of(wide / 262144 + 240))
                out = out.concat(unit_of(wide / 4096 % 64 + 128))
                out = out.concat(unit_of(wide / 64 % 64 + 128))
                out = out.concat(unit_of(wide % 64 + 128))
            }
        }
    }
    return from_utf8(out)
}

/// Decodes the scalar starting at byte offset `at`: the scalar value and
/// its encoded length, or the offset where an invalid sequence starts.
/// Overlong encodings, surrogate encodings, anything above U+10FFFF,
/// truncated sequences, and stray continuation bytes are all invalid.
fn decode(data: Bytes, at: U64) -> Result(Scalar, U64) {
    let size = data.len()
    if at >= size {
        return Err(at)
    }
    let lead = data.byte(at).to_u64()
    if lead < 128 {
        return Ok(Scalar(value: lead.to_u32_wrapping(), size: 1))
    }
    // 0x80..0xC1 cannot start a scalar: continuation bytes in lead
    // position, and the overlong two-byte encodings.
    if lead < 194 {
        return Err(at)
    }
    if lead < 224 {
        let second = continuation(data, at, 1)
        if second > 63 {
            return Err(at)
        }
        return Ok(Scalar(value: ((lead - 192) * 64 + second).to_u32_wrapping(), size: 2))
    }
    // 0xF5..0xFF cannot start a scalar: nothing above U+10FFFF encodes.
    if lead > 244 {
        return Err(at)
    }
    let second = continuation(data, at, 1)
    if second > 63 {
        return Err(at)
    }
    if lead < 240 {
        let third = continuation(data, at, 2)
        if third > 63 {
            return Err(at)
        }
        // E0 must start at A0 (no overlong), ED must end at 9F (no
        // surrogates); the other leads take any continuation.
        if lead == 224 && second < 32 {
            return Err(at)
        }
        if lead == 237 && second > 31 {
            return Err(at)
        }
        let value = (lead - 224) * 4096 + second * 64 + third
        return Ok(Scalar(value: value.to_u32_wrapping(), size: 3))
    }
    let third = continuation(data, at, 2)
    if third > 63 {
        return Err(at)
    }
    let fourth = continuation(data, at, 3)
    if fourth > 63 {
        return Err(at)
    }
    // F0 must start at 90 (no overlong), F4 must end at 8F (nothing above
    // U+10FFFF); the other leads take any continuation.
    if lead == 240 && second < 16 {
        return Err(at)
    }
    if lead == 244 && second > 15 {
        return Err(at)
    }
    let value = (lead - 240) * 262144 + second * 4096 + third * 64 + fourth
    return Ok(Scalar(value: value.to_u32_wrapping(), size: 4))
}

/// The six payload bits of the continuation byte `k` steps past `at`, or
/// 256 when that byte is missing or not a continuation byte: a sentinel no
/// valid payload can equal.
fn continuation(data: Bytes, at: U64, k: U64) -> U64 {
    let size = data.len()
    if at + k >= size {
        return 256
    }
    let one = data.byte(at + k).to_u64()
    if one < 128 || one > 191 {
        return 256
    }
    return one - 128
}

/// The scalar at `at`, or `None` when the offset is out of bounds or not a
/// scalar start.
fn decode_or_none(data: Bytes, at: U64) -> Option(Scalar) {
    return match decode(data, at) {
        Ok(scalar) => Some(scalar)
        Err(_) => None
    }
}
