module hello.std_bytes_example

import std.bytes { BytesBuilder, binary_search, base64_decode, base64_encode, empty, find, find_from, hex_decode, hex_encode, of_byte, read_u16_be, read_u16_le, read_u32_le, read_u32_be, read_u64_be, read_u64_le, split, u16_be_bytes, u16_le_bytes, u32_be_bytes, u32_le_bytes, u64_be_bytes, u64_le_bytes }

// The executable std.bytes v1 snapshot example. Fixed inputs only; every
// stage contributes a deterministic share of the returned checksum.

pub fn std_bytes_example() -> U64 {
    var total: U64 = 0

    // Construction and search.
    let one: Bytes = of_byte(102)
    let pair: Bytes = "\x66\x6f"
    if find(pair, one) == Some(0) { total = total + 1 }
    if find_from(pair, one, 1) == None { total = total + 2 }
    let pieces = split("\x00a\x00b\x00", "\x00")
    if pieces.len() == 4 { total = total + 4 }
    if binary_search("\x05\x0a\x14", 10) == Ok(1) { total = total + 8 }
    if binary_search("\x05\x0a\x14", 8) == Err(1) { total = total + 16 }

    // The little-endian pair is an inverse within its width.
    let stored = u64_le_bytes(16909060)
    if stored == "\x04\x03\x02\x01\x00\x00\x00\x00" { total = total + 32 }
    if read_u32_le(stored, 0) == Ok(16909060) { total = total + 64 }
    if read_u16_le(stored, 1) == Ok(515) { total = total + 128 }
    if read_u32_le(stored, 6) == Err(OutOfBounds) { total = total + 256 }
    if u16_be_bytes(4660) == "\x12\x34" { total = total + 512 }
    if u64_be_bytes(16909060) == "\x00\x00\x00\x00\x01\x02\x03\x04" { total = total + 1024 }
    if read_u16_be(u16_be_bytes(4660), 0) == Ok(4660) { total = total + 2048 }

    // Hex: lowercase out, both cases in, odd length rejected.
    if hex_encode("\xde\xad\xbe\xef") == "deadbeef" { total = total + 4096 }
    if hex_decode("DEADBEEF") == Ok("\xde\xad\xbe\xef") { total = total + 8192 }
    if hex_decode("abc") == Err(InvalidEncoding) { total = total + 16384 }

    // Standard Base64 with padding, pinned by RFC 4648.
    if base64_encode(empty()) == "" { total = total + 32768 }
    if base64_encode(one) == "Zg==" { total = total + 65536 }
    if base64_encode(pair) == "Zm8=" { total = total + 131072 }
    if base64_encode("foo") == "Zm9v" { total = total + 262144 }
    if base64_encode("foobar") == "Zm9vYmFy" { total = total + 524288 }
    if base64_decode("Zm8=") == Ok(pair) { total = total + 1048576 }
    if base64_decode("Zm9vYg=") == Err(InvalidEncoding) { total = total + 2097152 }

    // The builder accumulates bytes and sequences functionally.
    var built = BytesBuilder.new()
    built = built.push_byte(1)
    built = built.push_bytes(one)
    if built.finish() == "\x01\x66" { total = total + 4194304 }

    return total
}
