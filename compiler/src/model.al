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

// The checker records below are the private M5.4 declaration-resolution and
// initial body model, not a public diagnostic or serialization schema.
// Symbol, syntax, type-parameter, checked-type, and type-argument references
// are stable 1-based IDs; zero means absent. Source indices and byte ranges are
// zero-based. Checked type arguments occupy one flat buffer and are selected
// by first_arg/arg_count.
type SymbolRec {
    kind: U64
    node: U64
    source: U64
    name_start: U64
    name_end: U64
    type_arity: U64
    // Function declarations use kind 12. Concrete generic function instances
    // use kind 13 and retain their declaration, ordered canonical arguments,
    // and discovery parent. A nongeneric kind-12 function is its own instance.
    declaration: U64
    first_instance_arg: U64
    instance_arg_count: U64
    discovery_parent: U64
}

type TypeParamRec {
    owner: U64
    node: U64
    source: U64
    name_start: U64
    name_end: U64
}

// Checked type kinds: 1 primitive, 3 Domain, 4 DomainMark, 5 __s0_Error,
// 6 type parameter, 7 declared type, 8 slice, 9 Option, 10 Result, 11 Map,
// 12 Ptr, and 13 __s0_Buffer. Primitive targets 1..12 identify Bool, I8,
// I16, I32, I64, U8, U16, U32, U64, F32, F64, and Unit directly. String is
// normalized to the canonical slice-of-U8 structure. Canonical records have no
// source ownership (syntax is zero); source occurrences are retained by
// CheckedTypeAnnotationRec.
type CheckedTypeRec {
    kind: U64
    syntax: U64
    target: U64
    first_arg: U64
    arg_count: U64
}

type CheckedTypeAnnotationRec {
    owner: U64
    syntax: U64
    checked_type: U64
}

// Canonical manifest-v14 Z spans are the only syntax-derived lowering input.
// Their 1-based IDs match checked syntax references; parser kinds, tokens,
// links, and child structure are deliberately absent.
type CheckedSpanRec {
    source: U64
    start: U64
    end: U64
    name_start: U64
    name_end: U64
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

// Checked expressions form an append-only postorder graph per concrete function
// instance. Kinds 1..5 are runtime parameters, Bool literals, integer literals,
// decoded string literals, and locals. parameter_use names the stable LocalRec
// binding for kinds 1 and 5; bool_value is used only by kind 2. Kinds 6 and 7
// are unary and binary. Kind 20 is a float literal and kind 21 is a concrete
// field projection whose parameter_use names the declaration-field use.
// Kinds 12 and 13 are checked match and Result try;
// parameter_use names their lowering-facing CheckedMatchRec/CheckedTryRec.
// Ordered children are stored in one
// flattened child buffer rather than encoded by operator arity.
// Kinds 8..11 are direct user calls, concrete record constructors, concrete
// enum variants, and direct C-import calls. Their annotation is a stable
// CallAnnotationRec ID; the annotation names declaration semantic IDs and
// canonical checked types, never source spellings or later MIR IDs.
// Operator IDs are 1 `-`, 2 `!`, 3 `+`, 4 `-`, 5 `*`, 6 `/`, 7 `%`, 8 `<<`,
// 9 `>>`, 10 `==`, 11 `!=`, 12 `<`, 13 `<=`, 14 `>`, 15 `>=`, 16 `&&`, and
// 17 `||`. Child IDs always precede their parent. A root has site_kind 1 for a
// binding initializer, 2 for an assignment RHS, or 3 for a return, and
// 4 for an expression statement; site_syntax names that statement and children
// have a zero site. This makes
// ownership deterministic even where no separate checked statement record yet
// exists. Literal text stays in its token; range is proven against full-width
// decimal bounds, including U64 maximum and signed minima. These records remain
// structurally complete on CheckBad.
type CheckedExprRec {
    owner: U64
    syntax: U64
    kind: U64
    checked_type: U64
    parameter_use: U64
    bool_value: U64
    left: U64
    right: U64
    annotation: U64
    first_child: U64
    child_count: U64
    operator: U64
    site_kind: U64
    site_syntax: U64
}

type CheckedExprChildRec {
    expression: U64
}

// Call annotation kinds: 1 direct user function, 2 direct C import, 3 concrete
// struct constructor, 4 concrete enum variant, and 5 S0 builtin. target is the SymbolRec ID
// of a concrete function instance for kind 1, a declaration for kinds 2..3,
// and the owning enum SymbolRec ID for kind 4. variant_use is
// zero except for kind 4, where it is the stable role-2 DeclTypeUseRec ID.
// checked_type is the concrete function/import result or constructed type.
// builtin is zero for kinds 1..4 and a stable builtin identity for kind 5.
type CallAnnotationRec {
    owner: U64
    kind: U64
    target: U64
    checked_type: U64
    variant_use: U64
    builtin: U64
}

type CheckedReturnRec {
    owner: U64
    syntax: U64
    expression: U64
    result_use: U64
}

// Checked control records are the lowering-facing source model. Blocks retain
// their persistent entry environment and a reverse source-order statement
// chain. Statements name checked expressions, stable bindings and assignment
// places, and child blocks without introducing MIR blocks or control-flow IDs.
// Statement kinds mirror supported syntax: 1 let, 2 var, 3 assignment,
// 4 return, 5 expression, 6 block, 7 if, 8 while, 9 for, and 10 using.
type CheckedBlockRec {
    owner: U64
    syntax: U64
    environment: U64
    statements: U64
    guaranteed_return: U64
}

type CheckedStatementLinkRec {
    statement: U64
    next: U64
}

type CheckedStatementRec {
    owner: U64
    syntax: U64
    kind: U64
    environment: U64
    expression: U64
    place: U64
    binding: U64
    body: U64
    alternative: U64
}

// Place kinds are 1 local, 2 struct field, 3 slice index, and 4 indexed struct
// field. root is a stable LocalRec ID, field is a declaration-ordinal
// DeclTypeUseRec ID, index is a checked U64 expression, and checked_type is the
// concrete value accepted by the store.
type CheckedPlaceRec {
    owner: U64
    syntax: U64
    kind: U64
    root: U64
    field: U64
    index: U64
    checked_type: U64
}

// Match and try records are lowering-facing source semantics. They retain only
// concrete checker IDs: owners, canonical types, expressions, bindings,
// environments, declaration variant uses, and syntax. variant_kind is 0 for a
// declared enum variant, 1 None, 2 Some, 3 Ok, 4 Err, 5 OutOfMemory, 6 Limit,
// and 7 wildcard. Declared variants carry variant_use; builtins and wildcard do
// not. Arm bodies are checked expressions, including statement-form matches.
// Expression kinds 14..17 are concrete None, Some, Ok, and Err constructors;
// payload constructors own exactly one ordered expression child.
type CheckedMatchRec {
    owner: U64
    syntax: U64
    scrutinee: U64
    scrutinee_type: U64
    checked_type: U64
    first_arm: U64
    arm_count: U64
}

type CheckedMatchArmRec {
    owner: U64
    syntax: U64
    checked_match: U64
    variant_use: U64
    variant_kind: U64
    binding: U64
    environment: U64
    body: U64
}

type CheckedTryRec {
    owner: U64
    syntax: U64
    expression: U64
    result_type: U64
    ok_type: U64
    error_type: U64
}

// A cleanup record is owned by one concrete function instance and one using
// statement. environment is the lexical environment before the binding is
// introduced; binding and initializer are concrete checker IDs, and callback
// is the concrete nongeneric function instance. The exit facts tell lowering
// that this scope must run on lexical fallthrough, return, and Result `try`
// propagation without predicting MIR blocks or CFG IDs.
type CheckedCleanupRec {
    owner: U64
    syntax: U64
    environment: U64
    binding: U64
    initializer: U64
    callback: U64
    normal_exit: U64
    return_exit: U64
    try_exit: U64
}

type CheckedControlStore {
    blocks: __s0_Buffer(CheckedBlockRec)
    statement_links: __s0_Buffer(CheckedStatementLinkRec)
    statements: __s0_Buffer(CheckedStatementRec)
    places: __s0_Buffer(CheckedPlaceRec)
    matches: __s0_Buffer(CheckedMatchRec)
    match_arms: __s0_Buffer(CheckedMatchArmRec)
    tries: __s0_Buffer(CheckedTryRec)
    cleanups: __s0_Buffer(CheckedCleanupRec)
}

// Bindings are recorded per function in canonical declaration order. kind is 1
// for a runtime parameter or 2 for a local/for element; syntax identifies the
// declaration, mutable is 0 (let/parameter/for) or 1 (var), and checked_type is
// canonical.
type LocalRec {
    owner: U64
    kind: U64
    syntax: U64
    source: U64
    name_start: U64
    name_end: U64
    mutable: U64
    checked_type: U64
}

// Each persistent environment either adds one binding to its parent or, when
// binding is zero, restores a lexical-scope snapshot. This permits nested and
// sibling blocks to retain stable histories without leaking bindings.
type EnvironmentRec {
    owner: U64
    parent: U64
    binding: U64
}

// Private diagnostic kinds: 1 duplicate declaration, 2 reserved declaration,
// 3 duplicate type parameter, 4 unknown type, 5 wrong type arity, 6 duplicate
// struct field, 7 duplicate enum variant, 8 empty enum, 9 value-type cycle,
// 10 nested/reference slice element, 11 non-copy-trivial buffer element,
// 12 inadmissible Map key, 13 non-copy-trivial Map value, and 14 recursive
// declared type whose active specialization changes, and 15 unsupported C
// import signature type, 16 duplicate function runtime parameter, and 17
// reserved function runtime parameter name. Return-only body diagnostics are
// 18 unknown identifier, 19 return type mismatch, 20 valued-result function
// returning without a value, and 21 integer literal out of range for the
// declared result type. Binding and assignment diagnostics are 22 reserved
// binding name, 23 binding type mismatch, 24 assignment type mismatch, 25 Unit
// value bound, 26 domain mark bound, 27 duplicate binding in function, and 28
// assignment to an immutable binding. Operator diagnostics are 29 logical-not
// operand mismatch, 30 unsigned negation, 31 unsupported negation, 32 Bool
// operator operands, 33 noninteger shift left operand, 34 shift-count mismatch,
// 35 comparison operand mismatch, 36 unsupported comparison operands, 37
// noninteger arithmetic operands, and 38 arithmetic operand mismatch.
// Concrete-call diagnostics are 39 bare function value, 40 unknown or
// non-callable call target, 41 wrong direct-function arity, 42 direct-function
// argument mismatch, 43 record positional argument, 44 unknown record field,
// 45 duplicate record field, 46 missing record field, 47 payload variant used
// bare, 48 valueless variant called, 49 wrong variant payload arity, 50 variant
// payload mismatch, 51 C import called outside unsafe-c, 52 invalid unsafe-c
// root target, 53 nested call/unsafe-c in an unsafe argument, 54 wrong import
// arity, and 55 import argument mismatch. Generic inference diagnostics are
// 56 partial or excess explicit type arguments, 57 unresolved inference,
// 58 conflicting repeated binding, 59 expanding polymorphic recursion,
// 60 non-struct field root, 61 unknown assignment field, 62 non-slice index
// root, 63 non-U64 index, 64 non-copy-trivial indexed element, 65 non-Bool
// condition, 66 unsupported for sequence, 67 valued function fallthrough,
// 68 unreachable statement, and 69 using under a loop. Match/try diagnostics:
// 70 non-enum match, 71 unknown variant, 72 duplicate variant, 73 payload not
// bound, 74 valueless variant bound, 75 reserved arm binding, 76 duplicate arm
// binding, 77 arm type mismatch, 78 no arms, 79 nonexhaustive match, 80 try in
// a non-Result function, 81 try of a non-Result expression, and 82 try error
// type mismatch. Cleanup diagnostics are 83 unknown cleanup function, 84
// cleanup function not having exactly one concrete runtime parameter, 85
// cleanup parameter mismatch, and 86 cleanup result not Unit. Code 87 is the
// deterministic boundary rejection for syntax outside the supported S0 body
// contract. kind is the stable checker diagnostic code. The primary range is
// source/start/end; the optional related range is owned by this record and is
// rendered with a stable note selected by kind, independently of any CLI.
type CheckDiagRec {
    kind: U64
    source: U64
    start: U64
    end: U64
    related_source: U64
    related_start: U64
    related_end: U64
    detail_a: U64
    detail_b: U64
    detail_c: U64
    detail_d: U64
}

type DiagnosticTypeRec {
    kind: U64
    target: U64
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
