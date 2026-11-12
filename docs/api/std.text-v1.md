# `std.text` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for UTF-8 validation, scalar decoding,
exact-byte search, split, replace, the checked bytes-to-text conversion, and
the text builder. It is normative together with the executable example
[`examples/std.text-v1.al`](examples/std.text-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/text.al`.

Snapshot v1 covers the text foundation that needs no Unicode tables:
validation with the failing byte offset, scalar decoding and counting,
exact-byte search/split/replace, checked conversion, and `StringBuilder`.
Case mapping and Unicode normalization join a v2 amendment together with the
toolchain-versioned Unicode tables they require; the tables ship with the
toolchain and report their version, per the 1.0 contract. The module is pure
computation: it never observes the host, so no function takes a capability.

## Signatures

```alder
module std.text

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
pub fn validate(data: Bytes) -> Result(U64, TextError)
/// The text for bytes known to be UTF-8: the checked bytes-to-text
/// conversion with the failing offset in the error.
pub fn from_utf8(data: Bytes) -> Result(String, TextError)
/// The scalar starting at byte offset `at`: `None` when `at` is out of
/// bounds or points into the middle of a sequence.
pub fn scalar_at(text: String, at: U64) -> Option(Scalar)
/// The number of scalar values in the text.
pub fn scalar_count(text: String) -> U64
/// Every scalar value in the text, in order.
pub fn scalars(text: String) -> Vec(U32)

/// The first byte offset of `needle` in `text`, `None` when absent. An
/// empty `needle` matches at offset zero.
pub fn find(text: String, needle: String) -> Option(U64)
/// The first byte offset of `needle` at or after `from`, `None` when
/// absent.
pub fn find_from(text: String, needle: String, from: U64) -> Option(U64)
/// Splits `text` at every non-overlapping occurrence of `sep`, in order,
/// with the separators removed and empty pieces kept. An empty `sep`
/// yields the whole text as one piece.
pub fn split(text: String, sep: String) -> Vec(String)
/// Replaces every non-overlapping occurrence of `from` with `to`, scanning
/// left to right. An empty `from` returns the text unchanged.
pub fn replace(text: String, from: String, to: String) -> String

/// One growable text accumulator with functional updates. Pushed content
/// must be valid UTF-8, so `finish` is total.
pub type StringBuilder {
    data: String
}

impl StringBuilder {
    /// The empty builder.
    fn new() -> StringBuilder
    /// The number of bytes accumulated so far.
    fn len(self) -> U64
    /// Appends text.
    fn push_text(self, text: String) -> StringBuilder
    /// Appends bytes as text: `Err` when the bytes are not valid UTF-8.
    fn push_utf8(self, data: Bytes) -> Result(StringBuilder, TextError)
    /// Appends one scalar value's UTF-8 encoding: `Err` for a surrogate or
    /// a value above U+10FFFF.
    fn push_scalar(self, value: U32) -> Result(StringBuilder, TextError)
    /// The accumulated text.
    fn finish(self) -> String
}
```

## Contracts

- `String` values are UTF-8 text by construction: the checker validates
  every string literal, and the only builtin bridge from bytes revalidates.
  The scalar functions treat their argument as valid text; the decode walk
  stays total anyway, so the functions degrade to the valid prefix rather
  than panic if that invariant is ever widened.
- `validate` rejects overlong encodings (`C0`/`C1` leads, `E0` below `A0`,
  `F0` below `90`), surrogate encodings (`ED` above `9F`), encodings above
  U+10FFFF (`F4` above `8F`, `F5`..`FF` leads), truncated sequences, and
  stray continuation bytes. The error offset is the first offending byte,
  the sequence start.
- Search, split, and replace are exact bytes: no case folding, no
  normalization, and a match may begin anywhere in the text, including
  inside a multi-byte sequence. Offsets are byte positions, not scalar
  indices; `String` indexing is never integer indexing, so all reads at an
  offset go through these checked functions or the checked builtin `slice`.
- Equality and hashing stay the builtin byte equality: `==` never
  normalizes, per the 1.0 text contract.
- Every function is total against its input: no function panics, terminates,
  or reads anything but its arguments. Every function is pure: no
  capability, no host observation, same result for the same inputs.
- `StringBuilder` updates are functional: every `push_*` returns a new
  builder because a method cannot assign through `self` yet. Its storage
  rebuilds on each push, a known cost documented until the byte-buffer
  bridge replaces the concat backing.
- The Unicode table version report arrives with the v2 amendment, together
  with the case-mapping and normalization functions the tables serve.

## Example

The example below is the complete content that lands as
`examples/std.text-v1.al` with the implementation commit. It validates,
decodes, searches, splits, replaces, and builds fixed text and returns a
deterministic checksum.

```alder
module hello.std_text_example

import std.bytes { of_byte }
import std.text { StringBuilder, validate, from_utf8, scalar_at, scalar_count, find, split, replace }

// The executable std.text v1 snapshot example. Fixed inputs only; every
// stage contributes a deterministic share of the returned checksum.

pub fn std_text_example() -> U64 {
    var total: U64 = 0

    // Validation counts scalars, with the offset on rejection.
    let value: Bytes = "h\xc3\xa9llo".to_bytes()
    var bad: Bool = false
    match validate(value) {
        Ok(count) => {
            if count == 5 { total = total + 1 }
        }
        Err(failure) => {
            match failure {
                InvalidUtf8(_) => { bad = true }
                InvalidScalar(_) => { bad = true }
            }
        }
    }
    if bad { total = total - 1000000 }

    // The offset in the error is the first offending byte.
    let cut: Bytes = "\xc3"
    var cut_at: U64 = 0
    var cut_bad: Bool = false
    match validate(cut) {
        Ok(_) => { cut_bad = true }
        Err(failure) => {
            match failure {
                InvalidUtf8(at) => { cut_at = at }
                InvalidScalar(_) => { cut_bad = true }
            }
        }
    }
    if cut_bad { total = total - 1000000 }
    if cut_at == 0 { total = total + 2 }

    // Scalars: the two-byte sequence decodes as one value of size two.
    var scalar_bad: Bool = false
    match scalar_at("h\xc3\xa9llo", 1) {
        Some(one) => {
            if one.value == 233 { total = total + 4 }
            if one.size == 2 { total = total + 8 }
        }
        None => { scalar_bad = true }
    }
    if scalar_bad { total = total - 1000000 }
    if scalar_count("h\xc3\xa9llo") == 5 { total = total + 16 }

    // Exact search, split, and replace.
    var found: U64 = 0
    var find_bad: Bool = false
    match find("hello world hello", "world") {
        Some(at) => { found = at }
        None => { find_bad = true }
    }
    if find_bad { total = total - 1000000 }
    if found == 6 { total = total + 32 }
    let pieces = split("a:b::c", ":")
    if pieces.len() == 4 { total = total + 64 }
    if replace("abcabc", "abc", "x") == "xx" { total = total + 128 }

    // The checked conversion round-trips text through bytes.
    var round_bad: Bool = false
    match from_utf8(value) {
        Ok(text) => {
            if text == "h\xc3\xa9llo" { total = total + 256 }
        }
        Err(_) => { round_bad = true }
    }
    if round_bad { total = total - 1000000 }

    // The builder appends text and one scalar; a surrogate is rejected.
    var built = StringBuilder.new()
    built = built.push_text("a")
    var push_bad: Bool = false
    match built.push_scalar(233) {
        Ok(next) => { built = next }
        Err(_) => { push_bad = true }
    }
    if push_bad { total = total - 1000000 }
    if built.finish() == "a\xc3\xa9" { total = total + 512 }
    var reject_value: U32 = 0
    var reject_bad: Bool = false
    match built.push_scalar(55296) {
        Ok(_) => { reject_bad = true }
        Err(failure) => {
            match failure {
                InvalidScalar(surrogate) => { reject_value = surrogate }
                InvalidUtf8(_) => { reject_bad = true }
            }
        }
    }
    if reject_bad { total = total - 1000000 }
    if reject_value == 55296 { total = total + 1024 }

    // Bytes stay available through std.bytes when needed.
    if of_byte(65) == "A".to_bytes() { total = total + 2048 }

    return total
}
```

## Dependencies and sequencing

- Builds on `std.bytes` for single-byte construction (`of_byte`) and the
  empty sequence; the module graph stays acyclic with `std.text` above
  `std.bytes`.
- The example avoids string building beyond the builder surface it
  documents, and its `match` arms are the statement form the compiler
  accepts today; the `let x = match ...` expression form in other snapshot
  examples lands with the expression-match work in the language thread.
- Case mapping and normalization wait for the toolchain-versioned Unicode
  tables (a Milestone 10 deliverable) and land as a v2 amendment of this
  snapshot; the table version report lands with them.
- A `BytesBuilder`-backed builder storage replaces the concat backing when
  the byte-buffer bridge lands, changing cost, not behavior.
