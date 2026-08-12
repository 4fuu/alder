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

// Parser syntax kinds are stable for the current M5.4 parser slices:
// 1 import, 2 struct, 3 enum, 4 name type, 5 slice type, 6 applied type,
// 7 type parameter, 8 field, 9 variant, 10 imported function signature, and
// 11 enum payload label, 12 function declaration, 13 runtime parameter,
// 14 block, 15 let, 16 var, 17 assignment, 18 return, 19 expression
// statement, 20 integer, 21 float, 22 string, 23 bool, 24 identifier,
// 25 unary, 26 binary, 27 call, 28 named argument, 29 field, 30 index, and
// 31 try, 32 if, 33 while, 34 for, 35 using, 36 unsafe-c, 37 match,
// 38 match arm, and 39 match binding. Function children are parameters, result,
// then body; binding children are optional type then initializer; assignment
// children are target then value. If children are condition, then block, then
// optional else block; while children are condition then body; for children are
// sequence then body. A using node names its bound value and has initializer
// then a kind-24 cleanup identifier child. Unsafe-c has its sole root call as
// child. Match children are unary scrutinee then arms; arm children are optional
// kind-39 payload binding then body. Variant arms name and tokenize the variant;
// wildcard arms tokenize `_` and have no name span. Control nodes tokenize their
// leading keyword; for/using names retain their binding spans. Match bindings
// and cleanup identifiers tokenize and name their identifier.
// Type-parameter nodes span the complete `Name: type` declaration and retain
// the name as their semantic token.
// Top-level declaration IDs are recorded separately in
// ParseStore.roots in canonical source order; they are never inferred by kind.
// Token IDs preserve the lossless lexical identity needed by later checking;
// numeric literal conversion and range checking are deliberately not parser
// responsibilities. IDs into tokens, nodes, and links are 1-based; zero means
// absent. Links are stored in reverse source order so records remain
// append-only and copy-trivial.
type SyntaxRec {
    kind: U64
    token: U64
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

// Parser diagnostic kinds are stable only for these bootstrap slices (they
// are not the final public diagnostic schema): 1 expected declaration,
// 2 reserved (formerly unsupported function), 3 expected identifier,
// 4 expected punctuation or keyword, 5 expected type, 6 bad enum payload
// label, 7 top-level separator, 8 struct-field separator, 9 enum-variant
// separator, 10 parameter ordering, 11 block/statement separator,
// 12 expected expression, 13 line continuation, and 14 invalid assignment
// target, 15 expected match pattern, 16 match-arm separator, 17 expected `c`
// after unsafe, and 18 unsafe-c requires exactly one root call and closing brace.
type ParseDiagRec {
    kind: U64
    source: U64
    start: U64
    end: U64
}

// The checker records below are the private M5.4 declaration-resolution
// model, not a public diagnostic or serialization schema. Symbol, syntax,
// type-parameter, checked-type, and type-argument references are stable
// 1-based IDs; zero means absent. Source indices and byte ranges are zero-based.
// Checked type arguments occupy one flat buffer and are selected by
// first_arg/arg_count.
type SymbolRec {
    kind: U64
    node: U64
    source: U64
    name_start: U64
    name_end: U64
    type_arity: U64
}

type TypeParamRec {
    owner: U64
    node: U64
    source: U64
    name_start: U64
    name_end: U64
}

// Checked type kinds: 1 primitive, 2 String, 3 Domain, 4 DomainMark,
// 5 __s0_Error, 6 type parameter, 7 declared type, 8 slice, 9 Option,
// 10 Result, 11 Map, 12 Ptr, and 13 __s0_Buffer.
type CheckedTypeRec {
    kind: U64
    syntax: U64
    target: U64
    first_arg: U64
    arg_count: U64
}

// Semantic declaration-item roles: 1 struct field, 2 enum variant (including
// valueless variants), 3 import parameter, 4 import result, 5 function runtime
// parameter, and 6 function result. The item ID is its 1-based buffer index.
// node is the owning wrapper syntax node; source and name ranges identify the
// semantic item name. Unnamed signature items use a zero name range. syntax and
// checked_type are both zero only for valueless enum variants.
type DeclTypeUseRec {
    owner: U64
    role: U64
    ordinal: U64
    node: U64
    source: U64
    name_start: U64
    name_end: U64
    syntax: U64
    checked_type: U64
}

// Private diagnostic kinds: 1 duplicate declaration, 2 reserved declaration,
// 3 duplicate type parameter, 4 unknown type, 5 wrong type arity, 6 duplicate
// struct field, 7 duplicate enum variant, 8 empty enum, 9 value-type cycle,
// 10 nested/reference slice element, 11 non-copy-trivial buffer element,
// 12 inadmissible Map key, 13 non-copy-trivial Map value, and 14 recursive
// declared type whose active specialization changes.
type CheckDiagRec {
    kind: U64
    source: U64
    start: U64
    end: U64
    related_source: U64
    related_start: U64
    related_end: U64
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
