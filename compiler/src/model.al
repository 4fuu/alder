type SourceRec {
    path_start: U64
    path_end: U64
    text_start: U64
    text_end: U64
}

// Token kinds mirror the Go Stage 0 lexer: 0 EOF, 1 identifier/keyword,
// 2 integer, 3 float, 4 decoded string, and 5 punctuation. Keyword IDs are the
// declaration-order IDs 1..19 in frontend/lexer.go; zero means not a keyword.
type TokenRec {
    source: U64
    kind: U64
    keyword: U64
    start: U64
    end: U64
    leading_start: U64
    leading_end: U64
    value_start: U64
    value_end: U64
}

// Lexical diagnostic kinds retain the stable LEX0001 message variant:
// 1 semicolon, 2 unexpected character, 3 invalid exponent, 4 invalid escape,
// 5 unterminated string, and 6 unterminated block comment.
type LexDiagRec {
    kind: U64
    source: U64
    start: U64
    end: U64
}

// Parser syntax kinds are stable for the M5.4 declaration/type slice:
// 1 import, 2 struct, 3 enum, 4 name type, 5 slice type, 6 applied type,
// 7 type parameter, 8 field, 9 variant, 10 imported function signature, and
// 11 enum payload label. Top-level declaration IDs are recorded separately in
// ParseStore.roots in canonical source order; they are never inferred by kind.
// IDs into nodes and links are 1-based; zero means absent. Links are stored in
// reverse source order so records remain append-only and copy-trivial.
type SyntaxRec {
    kind: U64
    source: U64
    start: U64
    end: U64
    name_start: U64
    name_end: U64
    children: U64
}

type SyntaxLinkRec {
    node: U64
    next: U64
}

// Parser diagnostic kinds are stable only for this bootstrap slice (they are
// not the final public diagnostic schema): 1 expected declaration, 2 fn is
// unsupported at this gate, 3 expected identifier, 4 expected punctuation or
// keyword, 5 expected type, 6 bad enum payload label, 7 top-level separator,
// 8 struct-field separator, and 9 enum-variant separator.
type ParseDiagRec {
    kind: U64
    source: U64
    start: U64
    end: U64
}

type State {
    paths: __s0_Buffer(U8)
    texts: __s0_Buffer(U8)
    values: __s0_Buffer(U8)
    sources: __s0_Buffer(SourceRec)
    tokens: __s0_Buffer(TokenRec)
    diagnostics: __s0_Buffer(LexDiagRec)
}

enum LexResult {
    Good(value: State)
    Bad(value: State)
}
