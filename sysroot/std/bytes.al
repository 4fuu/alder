module std.bytes

// The Milestone 8 byte-sequence foundation: search and split over exact
// bytes, one sorted-search primitive, fixed-width little- and big-endian
// reads, the matching byte forms for writes, checked hex and Base64 codecs,
// and the functional `BytesBuilder`. Everything here is pure computation:
// no C binding, no host access, no allocation beyond the result sequences.
// Operations are total against the host: out-of-range reads and malformed
// encodings return errors instead of panicking, and byte equality never
// normalizes or reinterprets content.
//
// `BytesBuilder` is a value with functional updates: every `push_*` returns
// a new builder and the caller rebinds, because a method cannot assign
// through `self` yet. Its storage therefore rebuilds on each push, a known
// cost that the byte-buffer bridge replaces when it lands.

/// Failure of a checked byte-sequence operation.
pub enum BytesError {
    /// A read ran past the end of the sequence.
    OutOfBounds
    /// Hex or Base64 text was malformed.
    InvalidEncoding
}

/// One growable byte accumulator with functional updates.
pub type BytesBuilder {
    data: Bytes
}

impl BytesBuilder {
    /// The empty builder.
    fn new() -> BytesBuilder {
        return BytesBuilder(data: empty())
    }

    /// The number of bytes accumulated so far.
    fn len(self) -> U64 {
        return self.data.len()
    }

    /// Appends one byte.
    fn push_byte(self, one: U8) -> BytesBuilder {
        return BytesBuilder(data: self.data.concat(of_byte(one)))
    }

    /// Appends every byte of `data`.
    fn push_bytes(self, data: Bytes) -> BytesBuilder {
        return BytesBuilder(data: self.data.concat(data))
    }

    /// The accumulated bytes.
    fn finish(self) -> Bytes {
        return self.data
    }
}

/// Builds the byte sequence holding exactly the values `v` carries. Every
/// value is already within one byte by construction at each call site, so
/// the wrapping conversion is exact; the checked form would only restate
/// the callers' proofs.
fn unit_of(v: U64) -> Bytes {
    return of_byte(v.to_u8_wrapping())
}

/// The byte sequence holding exactly one byte.
pub fn of_byte(one: U8) -> Bytes {
    return byte_table().slice(one.to_u64(), one.to_u64() + 1)
}

/// The empty byte sequence.
pub fn empty() -> Bytes {
    let nothing = ""
    return nothing.to_bytes()
}

/// Every byte value once, in order: the single-byte construction table.
/// Byte sequences carry arbitrary bytes, so the literal is data, not text.
fn byte_table() -> Bytes {
    let table: Bytes = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"
    return table
}

/// The first byte offset of `needle` in `data`, `None` when absent. An
/// empty `needle` matches at `from` itself.
pub fn find(data: Bytes, needle: Bytes) -> Option(U64) {
    return find_from(data, needle, 0)
}

/// The first byte offset of `needle` at or after `from`, `None` when
/// absent. Matching is exact bytes: nothing normalizes or reinterprets
/// content.
pub fn find_from(data: Bytes, needle: Bytes, from: U64) -> Option(U64) {
    let size = data.len()
    let width = needle.len()
    if from > size {
        return None
    }
    if width == 0 {
        return Some(from)
    }
    var at: U64 = from
    while at + width <= size {
        if bytes_match(data, needle, at) {
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

/// Splits `data` at every non-overlapping occurrence of `sep`, in order,
/// with the separators removed and empty pieces kept. An empty `sep`
/// yields the whole sequence as one piece.
pub fn split(data: Bytes, sep: Bytes) -> Vec(Bytes) {
    var out: Vec(Bytes) = Vec.new(Bytes)
    let width = sep.len()
    if width == 0 {
        out.push(data)
        return out
    }
    var from: U64 = 0
    var searching: Bool = true
    while searching {
        let hit = find_from(data, sep, from)
        match hit {
            Some(at) => {
                out.push(data.slice(from, at))
                from = at + width
            }
            None => {
                searching = false
                out.push(data.slice(from, data.len()))
            }
        }
    }
    return out
}

/// Binary search over bytes sorted ascending by value: the leftmost index
/// holding `needle`, or `Err` carrying the index where `needle` belongs.
pub fn binary_search(sorted: Bytes, needle: U8) -> Result(U64, U64) {
    let size = sorted.len()
    var low: U64 = 0
    var high: U64 = size
    while low < high {
        let mid = low + (high - low) / 2
        let value = sorted.byte(mid)
        if value < needle {
            low = mid + 1
        } else {
            high = mid
        }
    }
    if low < size {
        if sorted.byte(low) == needle {
            return Ok(low)
        }
    }
    return Err(low)
}

/// Reads one little-endian `U16` at byte offset `at`.
pub fn read_u16_le(data: Bytes, at: U64) -> Result(U16, BytesError) {
    if at + 2 > data.len() {
        return Err(OutOfBounds)
    }
    let low: U16 = data.byte(at).to_u16()
    let high: U16 = data.byte(at + 1).to_u16()
    return Ok(low + high * 256)
}

/// Reads one big-endian `U16` at byte offset `at`.
pub fn read_u16_be(data: Bytes, at: U64) -> Result(U16, BytesError) {
    if at + 2 > data.len() {
        return Err(OutOfBounds)
    }
    let low: U16 = data.byte(at).to_u16()
    let high: U16 = data.byte(at + 1).to_u16()
    return Ok(high + low * 256)
}

/// Reads one little-endian `U32` at byte offset `at`.
pub fn read_u32_le(data: Bytes, at: U64) -> Result(U32, BytesError) {
    if at + 4 > data.len() {
        return Err(OutOfBounds)
    }
    var value: U32 = data.byte(at).to_u32()
    var scale: U32 = 1
    var index: U64 = 1
    while index < 4 {
        let one: U32 = data.byte(at + index).to_u32()
        scale = scale * 256
        value = value + one * scale
        index = index + 1
    }
    return Ok(value)
}

/// Reads one big-endian `U32` at byte offset `at`.
pub fn read_u32_be(data: Bytes, at: U64) -> Result(U32, BytesError) {
    if at + 4 > data.len() {
        return Err(OutOfBounds)
    }
    var value: U32 = 0
    var index: U64 = 0
    while index < 4 {
        let one: U32 = data.byte(at + index).to_u32()
        value = value * 256 + one
        index = index + 1
    }
    return Ok(value)
}

/// Reads one little-endian `U64` at byte offset `at`.
pub fn read_u64_le(data: Bytes, at: U64) -> Result(U64, BytesError) {
    if at + 8 > data.len() {
        return Err(OutOfBounds)
    }
    var value: U64 = data.byte(at).to_u64()
    var scale: U64 = 1
    var index: U64 = 1
    while index < 8 {
        let one: U64 = data.byte(at + index).to_u64()
        scale = scale * 256
        value = value + one * scale
        index = index + 1
    }
    return Ok(value)
}

/// Reads one big-endian `U64` at byte offset `at`.
pub fn read_u64_be(data: Bytes, at: U64) -> Result(U64, BytesError) {
    if at + 8 > data.len() {
        return Err(OutOfBounds)
    }
    var value: U64 = 0
    var index: U64 = 0
    while index < 8 {
        let one: U64 = data.byte(at + index).to_u64()
        value = value * 256 + one
        index = index + 1
    }
    return Ok(value)
}

/// The two little-endian bytes of `value`.
pub fn u16_le_bytes(value: U16) -> Bytes {
    let wide = value.to_u64()
    return unit_of(wide % 256).concat(unit_of(wide / 256))
}

/// The two big-endian bytes of `value`.
pub fn u16_be_bytes(value: U16) -> Bytes {
    let wide = value.to_u64()
    return unit_of(wide / 256).concat(unit_of(wide % 256))
}

/// The four little-endian bytes of `value`.
pub fn u32_le_bytes(value: U32) -> Bytes {
    let wide = value.to_u64()
    var out: Bytes = unit_of(wide % 256)
    var rest = wide / 256
    var index: U64 = 1
    while index < 4 {
        out = out.concat(unit_of(rest % 256))
        rest = rest / 256
        index = index + 1
    }
    return out
}

/// The four big-endian bytes of `value`.
pub fn u32_be_bytes(value: U32) -> Bytes {
    let wide = value.to_u64()
    var out: Bytes = empty()
    var scale: U64 = 16777216
    while scale >= 1 {
        out = out.concat(unit_of(wide / scale % 256))
        scale = scale / 256
    }
    return out
}

/// The eight little-endian bytes of `value`.
pub fn u64_le_bytes(value: U64) -> Bytes {
    var out: Bytes = unit_of(value % 256)
    var rest = value / 256
    var index: U64 = 1
    while index < 8 {
        out = out.concat(unit_of(rest % 256))
        rest = rest / 256
        index = index + 1
    }
    return out
}

/// The eight big-endian bytes of `value`.
pub fn u64_be_bytes(value: U64) -> Bytes {
    var out: Bytes = empty()
    var scale: U64 = 72057594037927936
    while scale >= 1 {
        out = out.concat(unit_of(value / scale % 256))
        scale = scale / 256
    }
    return out
}

/// Lowercase hex with two characters per byte.
pub fn hex_encode(data: Bytes) -> String {
    let digits = "0123456789abcdef"
    let size = data.len()
    var out: String = ""
    var at: U64 = 0
    while at < size {
        let one = data.byte(at).to_u64()
        out = out.concat(digits.slice(one / 16, one / 16 + 1))
        out = out.concat(digits.slice(one % 16, one % 16 + 1))
        at = at + 1
    }
    return out
}

/// Decodes lowercase or uppercase hex, two characters per byte. Any other
/// character, or an odd length, is `InvalidEncoding`.
pub fn hex_decode(text: String) -> Result(Bytes, BytesError) {
    let size = text.len()
    if size % 2 == 1 {
        return Err(InvalidEncoding)
    }
    var out: Bytes = empty()
    var at: U64 = 0
    while at < size {
        var high: U64 = 0
        var low: U64 = 0
        var known: Bool = true
        match hex_value(text.byte(at)) {
            Some(value) => { high = value }
            None => { known = false }
        }
        if known {
            match hex_value(text.byte(at + 1)) {
                Some(value) => { low = value }
                None => { known = false }
            }
        }
        if !known {
            return Err(InvalidEncoding)
        }
        out = out.concat(unit_of(high * 16 + low))
        at = at + 2
    }
    return Ok(out)
}

/// The numeric value of one hexadecimal digit, upper or lower case.
fn hex_value(one: U8) -> Option(U64) {
    let raw = one.to_u64()
    if raw >= 48 && raw <= 57 {
        return Some(raw - 48)
    }
    if raw >= 97 && raw <= 102 {
        return Some(raw - 87)
    }
    if raw >= 65 && raw <= 70 {
        return Some(raw - 55)
    }
    return None
}

/// The standard Base64 alphabet, in encoding order.
fn base64_alphabet() -> String {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
}

/// The numeric value of one Base64 alphabet character, `None` for anything
/// else, `=` included: the padding is rejected by lookup, not by position.
fn base64_value(one: U8) -> Option(U64) {
    let alphabet = base64_alphabet()
    let size = alphabet.len()
    var at: U64 = 0
    while at < size {
        if alphabet.byte(at) == one {
            return Some(at)
        }
        at = at + 1
    }
    return None
}

/// Standard Base64 with `=` padding, three bytes to four characters.
pub fn base64_encode(data: Bytes) -> String {
    let alphabet = base64_alphabet()
    let size = data.len()
    var out: String = ""
    var at: U64 = 0
    while at + 3 <= size {
        let group = data.byte(at).to_u64() * 65536 + data.byte(at + 1).to_u64() * 256 + data.byte(at + 2).to_u64()
        out = out.concat(alphabet.slice(group / 262144 % 64, group / 262144 % 64 + 1))
        out = out.concat(alphabet.slice(group / 4096 % 64, group / 4096 % 64 + 1))
        out = out.concat(alphabet.slice(group / 64 % 64, group / 64 % 64 + 1))
        out = out.concat(alphabet.slice(group % 64, group % 64 + 1))
        at = at + 3
    }
    let rest = size - at
    if rest == 1 {
        let group = data.byte(at).to_u64() * 65536
        out = out.concat(alphabet.slice(group / 262144 % 64, group / 262144 % 64 + 1))
        out = out.concat(alphabet.slice(group / 4096 % 64, group / 4096 % 64 + 1))
        out = out.concat("==")
    }
    if rest == 2 {
        let group = data.byte(at).to_u64() * 65536 + data.byte(at + 1).to_u64() * 256
        out = out.concat(alphabet.slice(group / 262144 % 64, group / 262144 % 64 + 1))
        out = out.concat(alphabet.slice(group / 4096 % 64, group / 4096 % 64 + 1))
        out = out.concat(alphabet.slice(group / 64 % 64, group / 64 % 64 + 1))
        out = out.concat("=")
    }
    return out
}

/// Decodes standard Base64: exact multiples of four characters from the
/// alphabet with correct `=` padding and zero trailing bits. Anything else
/// is `InvalidEncoding`.
pub fn base64_decode(text: String) -> Result(Bytes, BytesError) {
    let size = text.len()
    if size % 4 != 0 {
        return Err(InvalidEncoding)
    }
    var out: Bytes = empty()
    var at: U64 = 0
    while at < size {
        // Padding sits only in the final two positions, and `=` is not in
        // the alphabet, so the value lookups reject it anywhere else.
        var pad: U64 = 0
        if text.byte(at + 3) == 61 {
            pad = 1
        }
        if text.byte(at + 2) == 61 {
            if pad == 0 {
                return Err(InvalidEncoding)
            }
            pad = 2
        }
        // Compose the full 24-bit group, filling the padded positions with
        // the zero characters they encode.
        var want: U64 = 4
        want = want - pad
        var digits: U64 = 0
        var index: U64 = 0
        while index < 4 {
            if index < want {
                var value: U64 = 0
                var known: Bool = false
                match base64_value(text.byte(at + index)) {
                    Some(found) => {
                        value = found
                        known = true
                    }
                    None => {}
                }
                if !known {
                    return Err(InvalidEncoding)
                }
                digits = digits * 64 + value
            } else {
                digits = digits * 64
            }
            index = index + 1
        }
        // The bits the padding replaced must be zero: with pad 1 the third
        // character's low two bits, with pad 2 the second character's low
        // four bits. Grouping left by the padded positions puts those bits
        // at `digits / 64` for the third and `digits / 4096` for the second
        // character; the low-bit masks of the composed value are always
        // zero and would accept anything.
        if pad >= 1 {
            if digits / 64 % 4 != 0 {
                return Err(InvalidEncoding)
            }
        }
        if pad == 2 {
            if digits / 4096 % 16 != 0 {
                return Err(InvalidEncoding)
            }
        }
        out = out.concat(unit_of(digits / 65536 % 256))
        if pad < 2 {
            out = out.concat(unit_of(digits / 256 % 256))
        }
        if pad < 1 {
            out = out.concat(unit_of(digits % 256))
        }
        at = at + 4
    }
    return Ok(out)
}
