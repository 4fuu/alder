module std.parse

// The Milestone 8.1 byte-oriented parsing foundation: a cursor over exact
// bytes, half-open byte ranges, positioned failures, and the common scalar
// token forms. Positions are computed only when an error is reported, so the
// hot path stores one offset. Scalar parsers do not skip whitespace; callers
// use `skip_whitespace` explicitly, which preserves `core.num`'s exact-decimal
// contract. Data formats, quoted or escaped strings, record grammars,
// streaming, Unicode whitespace, and a Parser trait are deliberately outside
// this snapshot.

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
    data: Bytes
    at: U64
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
    fn bytes(data: Bytes) -> Cursor {
        return Cursor(data: data, at: 0)
    }

    /// A cursor at offset 0 over the exact bytes of `text`.
    fn text(text: String) -> Cursor {
        return Cursor(data: text.to_bytes(), at: 0)
    }

    /// The current byte offset.
    fn offset(self) -> U64 {
        return self.at
    }

    /// The line and column for the current offset. This scans the prefix on
    /// demand; parsing itself stores only the offset.
    fn position(self) -> Position {
        var at: U64 = 0
        var line: U64 = 1
        var column: U64 = 1
        while at < self.at {
            let byte = self.data.byte(at)
            if byte == 10 {
                line = line + 1
                column = 1
            } else {
                column = column + 1
            }
            at = at + 1
        }
        return Position(offset: self.at, line: line, column: column)
    }

    /// Whether the cursor is at the end of its input.
    fn at_end(self) -> Bool {
        return self.at == self.data.len()
    }

    /// The byte at the cursor, or `None` at end.
    fn peek(self) -> Option(U8) {
        if self.at_end() { return None }
        return Some(self.data.byte(self.at))
    }

    /// The byte `ahead` bytes after the cursor, or `None` past the end.
    fn peek_at(self, ahead: U64) -> Option(U8) {
        let remaining = self.data.len() - self.at
        if ahead >= remaining { return None }
        return Some(self.data.byte(self.at + ahead))
    }

    /// Every remaining byte, without advancing.
    fn rest(self) -> Bytes {
        return self.data.slice(self.at, self.data.len())
    }

    /// Advances exactly `count` bytes, or fails at the current position.
    fn advance(self, count: U64) -> Result(Cursor, ParseError) {
        let remaining = self.data.len() - self.at
        if count > remaining {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.UnexpectedEnd))
        }
        return Ok(Cursor(data: self.data, at: self.at + count))
    }

    /// Consumes exactly `count` bytes and returns them with their span.
    fn take_bytes(self, count: U64) -> Result(Step(Bytes), ParseError) {
        let advanced = try self.advance(count)
        let value = self.data.slice(self.at, advanced.at)
        return Ok(Step(Bytes)(value: value, span: Span(start: self.at, end: advanced.at), cursor: advanced))
    }

    /// Skips ASCII space, tab, CR, and LF. Unicode whitespace is not skipped.
    fn skip_whitespace(self) -> Cursor {
        var at = self.at
        var skipping = true
        while skipping && at < self.data.len() {
            let byte = self.data.byte(at)
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 {
                at = at + 1
            } else {
                skipping = false
            }
        }
        return Cursor(data: self.data, at: at)
    }

    /// Consumes one required byte.
    fn expect_byte(self, expected: U8) -> Result(Cursor, ParseError) {
        if self.at_end() {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.UnexpectedEnd))
        }
        let found = self.data.byte(self.at)
        if found != expected {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.UnexpectedByte(expected)))
        }
        return Ok(Cursor(data: self.data, at: self.at + 1))
    }

    /// Exact decimal U64. One optional leading `+` is accepted; `-` is
    /// rejected through `InvalidInteger(MinusOnUnsigned)`. No whitespace is
    /// skipped, so `12,` parses `12` and leaves the comma.
    fn parse_u64(self) -> Result(Step(U64), ParseError) {
        let start = self.at
        if self.at_end() {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.UnexpectedEnd))
        }
        var end = self.at
        let first = self.data.byte(end)
        if first == 43 || first == 45 { end = end + 1 }
        let digits = end
        while end < self.data.len() && is_digit(self.data.byte(end)) {
            end = end + 1
        }
        if end == digits {
            return Err(ParseError(at: Cursor(data: self.data, at: digits).position(), kind: ParseErrorKind.ExpectedDigit))
        }
        let token = self.data.slice(start, end)
        var text: String = ""
        match token.to_string_checked() {
            Some(value) => { text = value }
            None => { return Err(ParseError(at: self.position(), kind: ParseErrorKind.ExpectedDigit)) }
        }
        return match num.parse_u64(text) {
            Ok(value) => Ok(Step(U64)(value: value, span: Span(start: start, end: end), cursor: Cursor(data: self.data, at: end)))
            Err(error) => Err(ParseError(at: self.position(), kind: ParseErrorKind.InvalidInteger(error)))
        }
    }

    /// Exact decimal I64 with one optional leading `+` or `-`.
    fn parse_i64(self) -> Result(Step(I64), ParseError) {
        let start = self.at
        if self.at_end() {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.UnexpectedEnd))
        }
        var end = self.at
        let first = self.data.byte(end)
        if first == 43 || first == 45 { end = end + 1 }
        let digits = end
        while end < self.data.len() && is_digit(self.data.byte(end)) {
            end = end + 1
        }
        if end == digits {
            return Err(ParseError(at: Cursor(data: self.data, at: digits).position(), kind: ParseErrorKind.ExpectedDigit))
        }
        let token = self.data.slice(start, end)
        var text: String = ""
        match token.to_string_checked() {
            Some(value) => { text = value }
            None => { return Err(ParseError(at: self.position(), kind: ParseErrorKind.ExpectedDigit)) }
        }
        return match num.parse_i64(text) {
            Ok(value) => Ok(Step(I64)(value: value, span: Span(start: start, end: end), cursor: Cursor(data: self.data, at: end)))
            Err(error) => Err(ParseError(at: self.position(), kind: ParseErrorKind.InvalidInteger(error)))
        }
    }

    /// Exact lowercase `true` or `false`; the whole ASCII word must match.
    fn parse_bool(self) -> Result(Step(Bool), ParseError) {
        let start = self.position()
        let word = try self.parse_word()
        if word.value == "true" {
            return Ok(Step(Bool)(value: true, span: word.span, cursor: word.cursor))
        }
        if word.value == "false" {
            return Ok(Step(Bool)(value: false, span: word.span, cursor: word.cursor))
        }
        return Err(ParseError(at: start, kind: ParseErrorKind.InvalidLiteral))
    }

    /// One non-empty ASCII identifier: `[A-Za-z_][A-Za-z0-9_]*`.
    fn parse_word(self) -> Result(Step(String), ParseError) {
        if self.at_end() {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.UnexpectedEnd))
        }
        if !word_start(self.data.byte(self.at)) {
            return Err(ParseError(at: self.position(), kind: ParseErrorKind.ExpectedWord))
        }
        var end = self.at + 1
        while end < self.data.len() && word_continue(self.data.byte(end)) {
            end = end + 1
        }
        let token = self.data.slice(self.at, end)
        var text: String = ""
        match token.to_string_checked() {
            Some(value) => { text = value }
            None => { return Err(ParseError(at: self.position(), kind: ParseErrorKind.ExpectedWord)) }
        }
        return Ok(Step(String)(value: text, span: Span(start: self.at, end: end), cursor: Cursor(data: self.data, at: end)))
    }
}

fn is_digit(byte: U8) -> Bool {
    return byte >= 48 && byte <= 57
}

fn word_start(byte: U8) -> Bool {
    if byte >= 65 && byte <= 90 { return true }
    if byte >= 97 && byte <= 122 { return true }
    return byte == 95
}

fn word_continue(byte: U8) -> Bool {
    return word_start(byte) || is_digit(byte)
}

/// Whole-input exact decimal U64. No whitespace is skipped.
pub fn parse_u64(text: String) -> Result(U64, ParseError) {
    let step = try Cursor.text(text).parse_u64()
    if !step.cursor.at_end() {
        return Err(ParseError(at: step.cursor.position(), kind: ParseErrorKind.TrailingInput))
    }
    return Ok(step.value)
}

/// Whole-input exact decimal I64. No whitespace is skipped.
pub fn parse_i64(text: String) -> Result(I64, ParseError) {
    let step = try Cursor.text(text).parse_i64()
    if !step.cursor.at_end() {
        return Err(ParseError(at: step.cursor.position(), kind: ParseErrorKind.TrailingInput))
    }
    return Ok(step.value)
}

/// Whole-input exact lowercase `true` or `false`.
pub fn parse_bool(text: String) -> Result(Bool, ParseError) {
    let step = try Cursor.text(text).parse_bool()
    if !step.cursor.at_end() {
        return Err(ParseError(at: step.cursor.position(), kind: ParseErrorKind.TrailingInput))
    }
    return Ok(step.value)
}

/// Whole-input one ASCII identifier.
pub fn parse_word(text: String) -> Result(String, ParseError) {
    let step = try Cursor.text(text).parse_word()
    if !step.cursor.at_end() {
        return Err(ParseError(at: step.cursor.position(), kind: ParseErrorKind.TrailingInput))
    }
    return Ok(step.value)
}
