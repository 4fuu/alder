# `std.parse` Public Signature Snapshot v1

Status: **Milestone 8.1 frozen snapshot; byte cursor and scalar token parsers implemented**

This is the versioned public snapshot for the byte-oriented parsing
foundation. It is normative together with the executable example
[`examples/std.parse-v1.al`](examples/std.parse-v1.al), which lands in the
module's implementation commit. The module lives at `<sysroot>/std/parse.al`
and is imported explicitly; it is not part of the prelude.

The module owns a cursor over exact bytes, half-open byte ranges, positioned
failures, and the common scalar token forms. Positions are computed only when
an error is reported, so the hot path stores one offset. Scalar parsers do not
skip whitespace; callers use `skip_whitespace` explicitly, which preserves
`core.num`'s exact-decimal contract. `take` is a reserved parameter keyword in
Alder, so the buffer-consuming cursor method is named `take_bytes`.

## Signatures

```alder
module std.parse

import core.num as num

/// A half-open byte range: start is inclusive, end is exclusive.
pub type Span {
    pub start: U64
    pub end: U64
}

/// A byte offset plus 1-based line and column. Offsets are 0-based. Lines
/// advance on LF only; columns count bytes, not Unicode scalars.
pub type Position {
    pub offset: U64
    pub line: U64
    pub column: U64
}

/// Failure of a checked parse. `at` is the first byte that did not fit.
pub type ParseError {
    pub at: Position
    pub kind: ParseErrorKind
}

/// The parse failure categories. Integer failures carry the exact
/// `core.num.ParseIntError` category; the token start is in `ParseError.at`.
pub enum ParseErrorKind {
    /// The cursor was already at the end, or an operation ran past it.
    UnexpectedEnd
    /// A required byte did not match. `at` points at the byte that was
    /// found; a read at end is `UnexpectedEnd`.
    UnexpectedByte(expected: U8)
    /// A decimal integer had no digit after its optional sign.
    ExpectedDigit
    /// An ASCII word did not start with a letter or underscore.
    ExpectedWord
    /// The token was not `true` or `false`.
    InvalidLiteral
    /// `core.num` rejected the token.
    InvalidInteger(error: num.ParseIntError)
    /// A whole-input helper found bytes after the parsed value.
    TrailingInput
}

/// A cursor over owned bytes. The cursor owns its input; positions are
/// relative to the start of that input.
pub type Cursor {
    // private: data, at
}

/// A parsed value and the byte range and cursor that produced it.
/// Invariant: `span.end == cursor.offset()`.
pub type Step(T: type) {
    pub value: T
    pub span: Span
    pub cursor: Cursor
}

impl Cursor {
    /// A cursor at offset 0 over `data`.
    fn bytes(data: Bytes) -> Cursor
    /// A cursor at offset 0 over the exact bytes of `text`.
    fn text(text: String) -> Cursor

    /// The current byte offset.
    fn offset(self) -> U64
    /// The line and column for the current offset. This scans the prefix on
    /// demand; parsing itself stores only the offset.
    fn position(self) -> Position
    /// Whether the cursor is at the end of its input.
    fn at_end(self) -> Bool

    /// The byte at the cursor, or `None` at end.
    fn peek(self) -> Option(U8)
    /// The byte `ahead` bytes after the cursor, or `None` past the end.
    fn peek_at(self, ahead: U64) -> Option(U8)
    /// Every remaining byte, without advancing.
    fn rest(self) -> Bytes

    /// Advances exactly `count` bytes, or fails at the current position.
    fn advance(self, count: U64) -> Result(Cursor, ParseError)
    /// Consumes exactly `count` bytes and returns them with their span.
    fn take_bytes(self, count: U64) -> Result(Step(Bytes), ParseError)
    /// Skips ASCII space, tab, CR, and LF. Unicode whitespace is not skipped.
    fn skip_whitespace(self) -> Cursor
    /// Consumes one required byte.
    fn expect_byte(self, expected: U8) -> Result(Cursor, ParseError)

    /// Exact decimal U64. One optional leading `+` is accepted; `-` is
    /// rejected through `InvalidInteger(MinusOnUnsigned)`. No whitespace is
    /// skipped, so `12,` parses `12` and leaves the comma.
    fn parse_u64(self) -> Result(Step(U64), ParseError)

    /// Exact decimal I64 with one optional leading `+` or `-`.
    fn parse_i64(self) -> Result(Step(I64), ParseError)

    /// Exact lowercase `true` or `false`; the whole ASCII word must match.
    fn parse_bool(self) -> Result(Step(Bool), ParseError)

    /// One non-empty ASCII identifier: `[A-Za-z_][A-Za-z0-9_]*`.
    fn parse_word(self) -> Result(Step(String), ParseError)
}

/// Whole-input convenience forms. They do not skip whitespace and reject
/// trailing bytes with `TrailingInput`.
pub fn parse_u64(text: String) -> Result(U64, ParseError)
pub fn parse_i64(text: String) -> Result(I64, ParseError)
pub fn parse_bool(text: String) -> Result(Bool, ParseError)
pub fn parse_word(text: String) -> Result(String, ParseError)
```

Use the module namespace when calling both the cursor methods and the
whole-input helpers, as the example does. The helper names match the cursor
method names; a selected import of a helper and an unqualified method call can
make the method name resolve to the free function instead.

## Semantics

- A `Cursor` is a value. Every consuming operation returns the new cursor in
  the result; callers rebind. This matches the functional builders already in
  `std.bytes` and `std.text`.
- `Span` is half-open. A `Step` always has `span.end == cursor.offset()`.
  Successful scalar parsers do not skip leading whitespace; `skip_whitespace`
  is explicit. This preserves `core.num`'s exact-decimal rule.
- Integer parsing scans one optional sign and then ASCII digits. It stops at
  the first non-digit, so a caller can parse `12,` as `12` and then
  `expect_byte(44)`. The token is passed to `core.num.parse_u64` or
  `core.num.parse_i64`; `std.parse` does not duplicate the overflow or
  two's-complement logic. `InvalidInteger.at` is the token start; `core.num`
  supplies the category. Because the frozen `core.num` API accepts `String`,
  each integer parse materializes one token `String`; this is the known
  allocation cost of reusing that contract rather than adding a second
  integer parser.
- `parse_bool` and `parse_word` consume the maximal ASCII word. `truex` is
  `InvalidLiteral`, not `true` plus `x`. Uppercase and non-ASCII letters are
  not accepted in v1.
- `Position` is computed on demand by scanning the prefix to the current
  offset. The hot parsing loop stores only an offset; errors are cold. Line
  starts at 1, column at 1, LF increments the line and resets the column, and
  other bytes including CR and tab advance the column by one. Offset 0 and
  empty input are 1:1.
- Every failure is a value in `Result`; no parse path panics or allocates an
  error string. `rest`/`take_bytes` copy bytes; scalar parsing itself does not
  allocate except the `String` returned by `parse_word` and the token
  `String` described above.
- `Cursor` owns its input. Parsing a sliced input restarts positions at that
  slice; sub-cursors with inherited positions are not in v1.

Example composition:

```alder
import std.parse as parse

type Pair {
    left: U64
    right: U64
}

fn parse_pair(text: String) -> Result(Pair, parse.ParseError) {
    let first = try parse.Cursor.text(text).parse_u64()
    let second = try first.cursor.skip_whitespace().parse_u64()
    if !second.cursor.at_end() {
        return Err(parse.ParseError(at: second.cursor.position(), kind: TrailingInput))
    }
    return Ok(Pair(left: first.value, right: second.value))
}
```

## Out of scope

The following are deliberately outside v1 and remain for later milestones or
additive snapshots:

- JSON, YAML, TOML, CSV, and every other data-format grammar or schema;
- typed conversion from a generic value tree;
- streaming parsers, buffering, or `std.io` integration;
- quoted strings, escape sequences, comments, and key/value record grammars;
- Unicode whitespace, Unicode identifiers, normalization, and locale rules;
- floating-point, date/time, IP address, and duration parsing;
- a `Parser` trait, closures, or combinator objects.

## Verification

The production qualification test compiles and runs a program that checks the
cursor primitives, exact spans, LF/CRLF positions, integer limits and overflow,
minus-on-unsigned, trailing input, whole-input helpers, boolean words, invalid
words, and every error path. The executable example is run by the docs API
suite. There are no checker, MIR, lowering, verifier, or cgen cases in this
snapshot.
