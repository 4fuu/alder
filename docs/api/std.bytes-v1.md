# `std.bytes` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for byte sequence construction,
search, split, sorted search, little- and big-endian integer coding, and the
hex and Base64 codecs. It is normative together with the executable example
[`examples/std.bytes-v1.al`](examples/std.bytes-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The
module lives at `<sysroot>/std/bytes.al`.

The module is pure computation: it never observes the host, so no function
takes a capability. It depends on no other std module, so it sits at the
bottom of the std module graph.

## Signatures

```alder
module std.bytes

/// Failure of a checked bytes operation.
pub enum BytesError {
    /// A read, write, or slice went past the end of the sequence.
    OutOfBounds
    /// A decode step met input outside the codec's alphabet or framing.
    InvalidEncoding
}

/// One growable byte accumulator with functional updates.
pub type BytesBuilder {
    data: Bytes
}

impl BytesBuilder {
    /// The empty builder.
    fn new() -> BytesBuilder
    /// The number of bytes accumulated so far.
    fn len(self) -> U64
    /// Appends one byte value.
    fn push_byte(self, value: U8) -> BytesBuilder
    /// Appends a whole sequence.
    fn push_bytes(self, data: Bytes) -> BytesBuilder
    /// The accumulated sequence.
    fn finish(self) -> Bytes
}

/// The one-byte sequence holding `value`.
pub fn of_byte(value: U8) -> Bytes
/// The empty sequence.
pub fn empty() -> Bytes

/// The first byte offset of `needle` in `data`, `None` when absent. An
/// empty `needle` matches at offset zero.
pub fn find(data: Bytes, needle: Bytes) -> Option(U64)
/// The first byte offset of `needle` at or after `from`, `None` when
/// absent.
pub fn find_from(data: Bytes, needle: Bytes, from: U64) -> Option(U64)
/// Splits `data` at every non-overlapping occurrence of `sep`, in order,
/// with the separators removed and empty pieces kept. An empty `sep`
/// yields the whole sequence as one piece.
pub fn split(data: Bytes, sep: Bytes) -> Vec(Bytes)
/// Searches a sequence sorted ascending: the leftmost offset of `needle`,
/// or `Err(insertion_point)` where it would keep the order.
pub fn binary_search(sorted: Bytes, needle: U8) -> Result(U64, U64)

/// Reads an unsigned integer in the given endianness starting at `at`;
/// `Err(OutOfBounds)` when fewer than the width's bytes remain.
pub fn read_u16_le(data: Bytes, at: U64) -> Result(U16, BytesError)
pub fn read_u32_le(data: Bytes, at: U64) -> Result(U32, BytesError)
pub fn read_u64_le(data: Bytes, at: U64) -> Result(U64, BytesError)
pub fn read_u16_be(data: Bytes, at: U64) -> Result(U16, BytesError)
pub fn read_u32_be(data: Bytes, at: U64) -> Result(U32, BytesError)
pub fn read_u64_be(data: Bytes, at: U64) -> Result(U64, BytesError)

/// The value's representation in the given endianness, exactly the width's
/// byte count.
pub fn u16_le_bytes(value: U16) -> Bytes
pub fn u32_le_bytes(value: U32) -> Bytes
pub fn u64_le_bytes(value: U64) -> Bytes
pub fn u16_be_bytes(value: U16) -> Bytes
pub fn u32_be_bytes(value: U32) -> Bytes
pub fn u64_be_bytes(value: U64) -> Bytes

/// Lowercase hex: two digits per byte, so the output length is exactly
/// twice the input length.
pub fn hex_encode(data: Bytes) -> String
/// Decodes uppercase or lowercase hex: `Err(InvalidEncoding)` on odd
/// length or a character outside `0-9a-fA-F`.
pub fn hex_decode(text: String) -> Result(Bytes, BytesError)

/// Standard Base64 (RFC 4648) with `=` padding: the output length is a
/// multiple of four.
pub fn base64_encode(data: Bytes) -> String
/// Decodes standard Base64 strictly: the length must be a multiple of
/// four, padding may appear only at the end, the padding count must leave
/// no whole unused character, and unused trailing bits must be zero.
pub fn base64_decode(text: String) -> Result(Bytes, BytesError)
```

## Contracts

- Sequences are byte-exact: search, split, and binary search compare bytes
  with no encoding or case interpretation. A match may begin anywhere,
  including inside a multi-byte UTF-8 sequence; bytes carry no text
  meaning.
- Every function is total against its input: no function panics,
  terminates, or reads anything but its arguments. Every function is pure:
  no capability, no host observation, same result for the same inputs.
- `binary_search` requires ascending order; on a miss it reports the
  insertion point that keeps the order, the same position where the value
  would sit among equal neighbors.
- The endian readers reject short input with `OutOfBounds` and never read
  past the sequence; the writers emit exactly the width's byte count. A
  read at an offset followed by the matching write reproduces the value, so
  each pair is an inverse within its width.
- `hex_encode` emits lowercase and `hex_decode` accepts both cases,
  rejecting odd length and out-of-alphabet characters with
  `InvalidEncoding`.
- Base64 uses the standard alphabet and padding exactly (RFC 4648): encode
  emits `=` padding; decode is strict and rejects multiple padding
  characters, padding before the final group, unused characters, and
  nonzero unused bits with `InvalidEncoding`. `base64_decode` inverts
  `base64_encode`.
- `BytesBuilder` updates are functional: every `push_*` returns a new
  builder because a method cannot assign through `self` yet. Its storage
  rebuilds on each push, a known cost documented until the byte-buffer
  bridge replaces the concat backing.

## Example

The example below is the complete content that lands as
`examples/std.bytes-v1.al` with the implementation commit. It pins the RFC
4648 vectors, the endian round-trips, hex, search, split, and the builder,
and returns a deterministic checksum.

```alder
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
```

## Dependencies and sequencing

- Depends on no other std module; `std.text` builds on it, so the module
  graph stays acyclic with `std.bytes` at the bottom.
- The example's `match`-free assertions use the builtin `Option` and
  `Result` equality the checker accepts today; comparisons of floating
  payloads stay rejected (diagnostic 303) and never appear here because the
  module has no floating types.
- A byte-buffer-backed builder storage replaces the concat backing when the
  byte-buffer bridge lands, changing cost, not behavior. A typed read
  family wider than `U64` (128-bit values) waits for a language integer
  wider than `U64` and is out of scope for v1.
- The signed-integer read and write family joins a v2 amendment with the
  sign-handling conversions the module needs; unsigned coding covers v1's
  contract.
