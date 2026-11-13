// One lexical name visible to the dotted-callee heuristic. The binding buffer
// keeps its history; binding_count restores the visible prefix at block, arm,
// closure, and function exits, and a later binding reuses the first restored
// slot so a shadow in an inner scope never affects a dotted call after that
// scope. source/start/end are the declared word.
type ParseBindingRec {
    source: U64
    start: U64
    end: U64
}

type ParseStore {
    nodes: __s0_Buffer(SyntaxRec)
    links: __s0_Buffer(SyntaxLinkRec)
    roots: __s0_Buffer(U64)
    diagnostics: __s0_Buffer(ParseDiagRec)
    bindings: __s0_Buffer(ParseBindingRec)
    binding_count: U64
}

type ParseCursor {
    token: U64
    store: ParseStore
}

type ParseValue {
    cursor: ParseCursor
    node: U64
}

enum ParseStep {
    Parsed(value: ParseValue)
    Rejected(value: ParseCursor)
}

type ParseOutput {
    state: State
    store: ParseStore
}

enum ParseResult {
    ParseGood(value: ParseOutput)
    ParseBad(value: ParseOutput)
    ParseLexBad(value: ParseOutput)
}

fn parse_step_bad(step: ParseStep) -> Bool {
    return match step {
        Rejected(value) => true
        Parsed(value) => false
    }
}

fn parse_step_value(step: ParseStep) -> ParseValue {
    return match step {
        Parsed(value) => value
        Rejected(value) => ParseValue(cursor: value, node: 0)
    }
}

fn parse_step_cursor(step: ParseStep) -> ParseCursor {
    return match step {
        Parsed(value) => value.cursor
        Rejected(value) => value
    }
}

fn parse_token(state: State, cursor: ParseCursor) -> TokenRec {
    return __s0_buffer_get(TokenRec, state.tokens, cursor.token)
}

fn token_text(state: State, token: TokenRec, text: __s0_String) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, token.source)
    return source_word(state, source, token.start, token.end, text)
}

fn token_punct(state: State, cursor: ParseCursor, text: __s0_String) -> Bool {
    let token = parse_token(state, cursor)
    return token.kind == 5 && token_text(state, token, text)
}

fn token_ident(state: State, cursor: ParseCursor) -> Bool {
    let token = parse_token(state, cursor)
    return token.kind == 1 && token.keyword == 0
}

fn line_break_before(state: State, cursor: ParseCursor) -> Bool {
    let token = parse_token(state, cursor)
    let source = __s0_buffer_get(SourceRec, state.sources, token.source)
    var at = token.leading_start
    while at < token.leading_end {
        if text_byte(state, source, at) == 10 { return true }
        at = at + 1
    }
    return false
}

fn reject_parse(d: Domain, state: State, cursor: ParseCursor, kind: U64) -> Result(ParseStep, __s0_Error) {
    let token = parse_token(state, cursor)
    let diag = ParseDiagRec(kind: kind, source: token.source, start: token.start, end: token.end)
    let diagnostics = try __s0_buffer_append(ParseDiagRec, d, cursor.store.diagnostics, diag)
    let store = ParseStore(nodes: cursor.store.nodes, links: cursor.store.links, roots: cursor.store.roots, diagnostics: diagnostics, bindings: cursor.store.bindings, binding_count: cursor.store.binding_count)
    return Ok(Rejected(ParseCursor(token: cursor.token, store: store)))
}

fn add_syntax(d: Domain, cursor: ParseCursor, kind: U64, token: U64, source: U64, start: U64, end: U64, name_start: U64, name_end: U64, children: U64) -> Result(ParseValue, __s0_Error) {
    let rec = SyntaxRec(kind: kind, token: token, source: source, start: start, end: end, name_start: name_start, name_end: name_end, children: children)
    let nodes = try __s0_buffer_append(SyntaxRec, d, cursor.store.nodes, rec)
    let store = ParseStore(nodes: nodes, links: cursor.store.links, roots: cursor.store.roots, diagnostics: cursor.store.diagnostics, bindings: cursor.store.bindings, binding_count: cursor.store.binding_count)
    return Ok(ParseValue(cursor: ParseCursor(token: cursor.token, store: store), node: __s0_buffer_len(SyntaxRec, nodes)))
}

fn add_link(d: Domain, cursor: ParseCursor, node: U64, next: U64) -> Result(ParseCursor, __s0_Error) {
    let links = try __s0_buffer_append(SyntaxLinkRec, d, cursor.store.links, SyntaxLinkRec(node: node, next: next))
    let store = ParseStore(nodes: cursor.store.nodes, links: links, roots: cursor.store.roots, diagnostics: cursor.store.diagnostics, bindings: cursor.store.bindings, binding_count: cursor.store.binding_count)
    return Ok(ParseCursor(token: cursor.token, store: store))
}

fn add_root(d: Domain, cursor: ParseCursor, node: U64) -> Result(ParseCursor, __s0_Error) {
    let roots = try __s0_buffer_append(U64, d, cursor.store.roots, node)
    let store = ParseStore(nodes: cursor.store.nodes, links: cursor.store.links, roots: roots, diagnostics: cursor.store.diagnostics, bindings: cursor.store.bindings, binding_count: cursor.store.binding_count)
    return Ok(ParseCursor(token: cursor.token, store: store))
}

// parse_add_binding records one lexical name for the dotted-callee heuristic.
// The binding is visible until the enclosing block, arm, closure, or function
// restores binding_count; the visible prefix is scanned for an exact match.
fn parse_add_binding(d: Domain, cursor: ParseCursor, token: TokenRec) -> Result(ParseCursor, __s0_Error) {
    let rec = ParseBindingRec(source: token.source, start: token.start, end: token.end)
    var bindings = cursor.store.bindings
    if cursor.store.binding_count < __s0_buffer_len(ParseBindingRec, bindings) {
        // A function or block exit restores binding_count without truncating
        // the append-only buffer. Reuse that visible slot so a stale binding
        // from an earlier scope cannot become visible again when a later local
        // grows the count past it.
        __s0_buffer_set(ParseBindingRec, bindings, cursor.store.binding_count, rec)
    } else {
        bindings = try __s0_buffer_append(ParseBindingRec, d, bindings, rec)
    }
    let store = ParseStore(nodes: cursor.store.nodes, links: cursor.store.links, roots: cursor.store.roots, diagnostics: cursor.store.diagnostics, bindings: bindings, binding_count: cursor.store.binding_count + 1)
    return Ok(ParseCursor(token: cursor.token, store: store))
}

fn parse_restore_bindings(store: ParseStore, count: U64) -> ParseStore {
    return ParseStore(nodes: store.nodes, links: store.links, roots: store.roots, diagnostics: store.diagnostics, bindings: store.bindings, binding_count: count)
}

// parse_binding_shadows reports whether the base word names a local or
// parameter visible in the current parse scope. A lexical binding must win
// over a bare import namespace of the same spelling.
fn parse_binding_shadows(state: State, store: ParseStore, base: SyntaxRec) -> Bool {
    var at: U64 = 0
    while at < store.binding_count {
        let binding = __s0_buffer_get(ParseBindingRec, store.bindings, at)
        if binding.source == base.source && binding.end - binding.start == base.name_end - base.name_start {
            let source = __s0_buffer_get(SourceRec, state.sources, base.source)
            var equal = true
            var offset: U64 = 0
            while offset < base.name_end - base.name_start {
                if text_byte(state, source, binding.start + offset) != text_byte(state, source, base.name_start + offset) { equal = false }
                offset = offset + 1
            }
            if equal { return true }
        }
        at = at + 1
    }
    return false
}

fn expect_punct(d: Domain, state: State, cursor: ParseCursor, text: __s0_String) -> Result(ParseStep, __s0_Error) {
    if !token_punct(state, cursor, text) { return reject_parse(d, state, cursor, 4) }
    return Ok(Parsed(ParseValue(cursor: ParseCursor(token: cursor.token + 1, store: cursor.store), node: 0)))
}

fn parse_type(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let first = parse_token(state, initial)
    // `fn(A, B) -> R` is the function type. The children are the parameter
    // types followed by the result type.
    if first.kind == 1 && first.keyword == 4 {
        let fn_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        let open = try expect_punct(d, state, fn_cursor, "(")
        if parse_step_bad(open) { return Ok(open) }
        var cursor = parse_step_cursor(open)
        var children: U64 = 0
        if !token_punct(state, cursor, ")") {
            var more = true
            while more {
                // A function-type parameter may be borrowed: `fn(mut T) -> R`.
                // The checker recovers the modes from the parameter tokens.
                let first_param = parse_token(state, cursor)
                if first_param.kind == 1 && first_param.keyword == 24 { return reject_parse(d, state, cursor, 50) }
                if first_param.kind == 1 && first_param.keyword == 23 {
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                }
                let param = try parse_type(d, state, cursor)
                if parse_step_bad(param) { return Ok(param) }
                let value = parse_step_value(param)
                cursor = try add_link(d, value.cursor, value.node, children)
                children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                if token_punct(state, cursor, ",") {
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                    if token_punct(state, cursor, ")") { more = false }
                } else { more = false }
            }
        }
        let close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_cursor(close)
        let arrow = try expect_punct(d, state, cursor, "->")
        if parse_step_bad(arrow) { return Ok(arrow) }
        cursor = parse_step_cursor(arrow)
        let result = try parse_type(d, state, cursor)
        if parse_step_bad(result) { return Ok(result) }
        let rv = parse_step_value(result)
        cursor = try add_link(d, rv.cursor, rv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, rv.node - 1).end
        let node = try add_syntax(d, cursor, 57, initial.token + 2, first.source, first.start, end, 0, 0, children)
        return Ok(Parsed(node))
    }
    // `Self` is a keyword type reference resolved against the enclosing trait
    // declaration or trait implementation by the checker.
    if first.kind == 1 && first.keyword == 29 {
        let node = try add_syntax(d, ParseCursor(token: initial.token + 1, store: initial.store), 56, initial.token + 1, first.source, first.start, first.end, first.start, first.end, 0)
        return Ok(Parsed(node))
    }
    if token_punct(state, initial, "[") {
        let inner = try parse_type(d, state, ParseCursor(token: initial.token + 1, store: initial.store))
        if parse_step_bad(inner) { return Ok(inner) }
        let value = parse_step_value(inner)
        let close = try expect_punct(d, state, value.cursor, "]")
        if parse_step_bad(close) { return Ok(close) }
        var cursor = parse_step_value(close).cursor
        cursor = try add_link(d, cursor, value.node, 0)
        let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
        let node = try add_syntax(d, cursor, 5, initial.token + 1, first.source, first.start, end, 0, 0, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        return Ok(Parsed(node))
    }
    if !token_ident(state, initial) { return reject_parse(d, state, initial, 5) }
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var last = first
    while token_punct(state, cursor, ".") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
        last = parse_token(state, cursor)
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    }
    if !token_punct(state, cursor, "(") {
        let node = try add_syntax(d, cursor, 4, initial.token + 1, first.source, first.start, last.end, first.start, last.end, 0)
        return Ok(Parsed(node))
    }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var children: U64 = 0
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            var arg: ParseStep = Rejected(cursor)
            let arg_token = parse_token(state, cursor)
            if arg_token.kind == 2 {
                let node = try add_syntax(d, ParseCursor(token: cursor.token + 1, store: cursor.store), 20, cursor.token + 1, arg_token.source, arg_token.start, arg_token.end, 0, 0, 0)
                arg = Parsed(node)
            } else { arg = try parse_type(d, state, cursor) }
            if parse_step_bad(arg) { return Ok(arg) }
            let value = parse_step_value(arg)
            cursor = try add_link(d, value.cursor, value.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, ")")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_value(close).cursor
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    // The applied head may be module-qualified (`fs.TempFile(I)`); its name
    // span covers every dot-separated segment, as the non-generic type form
    // already does. Only the first segment would resolve as a bare name.
    let node = try add_syntax(d, cursor, 6, initial.token + 1, first.source, first.start, end, first.start, last.end, children)
    return Ok(Parsed(node))
}

fn parse_named_item(d: Domain, state: State, initial: ParseCursor, kind: U64, payload: Bool) -> Result(ParseStep, __s0_Error) {
    if !token_ident(state, initial) { return reject_parse(d, state, initial, 3) }
    let name = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var item_children: U64 = 0
    if kind == 9 && !payload {
        let variant = try add_syntax(d, cursor, kind, initial.token + 1, name.source, name.start, name.end, name.start, name.end, 0)
        return Ok(Parsed(variant))
    }
    if payload {
        if !token_punct(state, cursor, "(") { return reject_parse(d, state, cursor, 4) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 6) }
        let label = parse_token(state, cursor)
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 6) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let label_node = try add_syntax(d, cursor, 11, cursor.token - 1, label.source, label.start, label.end, label.start, label.end, 0)
        cursor = try add_link(d, label_node.cursor, label_node.node, 0)
        item_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    } else {
        if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 4) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    }
    let ty = try parse_type(d, state, cursor)
    if parse_step_bad(ty) { return Ok(ty) }
    let value = parse_step_value(ty)
    cursor = value.cursor
    if payload {
        let close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_value(close).cursor
    }
    cursor = try add_link(d, cursor, value.node, item_children)
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, kind, initial.token + 1, name.source, name.start, end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
    return Ok(Parsed(node))
}

fn expression_precedence(state: State, cursor: ParseCursor) -> U64 {
    if token_punct(state, cursor, "||") { return 1 }
    if token_punct(state, cursor, "&&") { return 2 }
    if token_punct(state, cursor, "==") || token_punct(state, cursor, "!=") { return 3 }
    if token_punct(state, cursor, "<") || token_punct(state, cursor, "<=") || token_punct(state, cursor, ">") || token_punct(state, cursor, ">=") { return 4 }
    if token_punct(state, cursor, "|") { return 5 }
    if token_punct(state, cursor, "^") { return 6 }
    if token_punct(state, cursor, "&") { return 7 }
    if token_punct(state, cursor, "<<") || token_punct(state, cursor, ">>") { return 8 }
    if token_punct(state, cursor, "+") || token_punct(state, cursor, "-") { return 9 }
    if token_punct(state, cursor, "*") || token_punct(state, cursor, "/") || token_punct(state, cursor, "%") { return 10 }
    return 0
}

fn expression_line_ok(state: State, cursor: ParseCursor, depth: U64) -> Bool {
    return depth != 0 || !line_break_before(state, cursor)
}

// Bootstrap nesting limit. Every recursive descent that can grow without
// bound funnels through here: parenthesised expressions, call arguments,
// index expressions, array literals and match arms raise `depth`, and a
// single operator chain builds one left-nested node per iteration. Without a
// cap, deeply nested input exhausts the native stack and segfaults the
// compiler; the checker and lowering recurse over the same tree, so bounding
// the parser also bounds them. The limit is far above any real source and far
// below the observed stack exhaustion point (roughly 150 levels).
fn parse_depth_limit() -> U64 { return 64 }

fn parse_depth_reject(d: Domain, state: State, cursor: ParseCursor) -> Result(ParseStep, __s0_Error) {
    return reject_parse(d, state, cursor, 19)
}

fn parse_match_arm(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let pattern = parse_token(state, initial)
    let wildcard = token_ident(state, initial) && token_text(state, pattern, "_")
    if !token_ident(state, initial) { return reject_parse(d, state, initial, 15) }
    let binding_base = initial.store.binding_count
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var children: U64 = 0
    var name_start: U64 = pattern.start
    var name_end: U64 = pattern.end
    if wildcard {
        name_start = 0
        name_end = 0
    } else {
        if token_punct(state, cursor, "(") {
            let binding_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if !token_ident(state, binding_cursor) { return reject_parse(d, state, binding_cursor, 3) }
            let binding = parse_token(state, binding_cursor)
            cursor = ParseCursor(token: binding_cursor.token + 1, store: binding_cursor.store)
            let close = try expect_punct(d, state, cursor, ")")
            if parse_step_bad(close) { return Ok(close) }
            cursor = parse_step_cursor(close)
            let binding_node = try add_syntax(d, cursor, 39, binding_cursor.token + 1, binding.source, binding.start, binding.end, binding.start, binding.end, 0)
            cursor = try parse_add_binding(d, binding_node.cursor, binding)
            cursor = try add_link(d, cursor, binding_node.node, 0)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        }
    }
    // A match arm may carry an `if` guard between its pattern and the arrow:
    // the guard is evaluated after the pattern matches and before the body,
    // and a false guard continues matching with the next arm (D018).
    var guard_node: U64 = 0
    let guard_token = parse_token(state, cursor)
    if guard_token.kind == 1 && guard_token.keyword == 7 {
        let guard_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let guard_step = try parse_expression(d, state, guard_cursor, depth)
        if parse_step_bad(guard_step) { return Ok(guard_step) }
        guard_node = parse_step_value(guard_step).node
        cursor = parse_step_value(guard_step).cursor
    }
    let arrow = try expect_punct(d, state, cursor, "=>")
    if parse_step_bad(arrow) { return Ok(arrow) }
    // An arm body is one expression, a `{ ... }` statement block for the
    // statement form of match used by table-view arms, or a diverging
    // `return` statement that produces no value.
    var body: ParseStep = Rejected(parse_step_cursor(arrow))
    let body_token = parse_token(state, parse_step_cursor(arrow))
    if token_punct(state, parse_step_cursor(arrow), "\{") {
        body = try parse_block(d, state, parse_step_cursor(arrow))
    } else if body_token.kind == 1 && body_token.keyword == 12 {
        body = try parse_return_statement(d, state, parse_step_cursor(arrow), depth)
    } else {
        body = try parse_expression(d, state, parse_step_cursor(arrow), depth)
    }
    if parse_step_bad(body) { return Ok(body) }
    let value = parse_step_value(body)
    if guard_node != 0 {
        // Arm children stay reverse source ordered: the body leads, then the
        // guard, then the variant binding.
        let guard_link = try add_link(d, value.cursor, guard_node, children)
        let guard_link_id = __s0_buffer_len(SyntaxLinkRec, guard_link.store.links)
        cursor = try add_link(d, guard_link, value.node, guard_link_id)
    } else {
        cursor = try add_link(d, value.cursor, value.node, children)
    }
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let arm_cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, binding_base))
    let arm = try add_syntax(d, arm_cursor, 38, initial.token + 1, pattern.source, pattern.start, end, name_start, name_end, __s0_buffer_len(SyntaxLinkRec, arm_cursor.store.links))
    return Ok(Parsed(arm))
}

fn parse_match(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    let value_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !expression_line_ok(state, value_cursor, depth) { return reject_parse(d, state, value_cursor, 13) }
    let scrutinee = try parse_unary(d, state, value_cursor, depth)
    if parse_step_bad(scrutinee) { return Ok(scrutinee) }
    let sv = parse_step_value(scrutinee)
    let open = try expect_punct(d, state, sv.cursor, "\{")
    if parse_step_bad(open) { return Ok(open) }
    var cursor = try add_link(d, parse_step_cursor(open), sv.node, 0)
    var children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    while !token_punct(state, cursor, "}") {
        let arm = try parse_match_arm(d, state, cursor, depth + 1)
        if parse_step_bad(arm) { return Ok(arm) }
        let av = parse_step_value(arm)
        cursor = try add_link(d, av.cursor, av.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if token_punct(state, cursor, ",") || token_punct(state, cursor, ";") { return reject_parse(d, state, cursor, 16) }
        if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 16) }
    }
    let close = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let node = try add_syntax(d, cursor, 37, initial.token + 1, start.source, start.start, close.end, 0, 0, children)
    return Ok(Parsed(node))
}

// parse_return_statement parses one `return` statement node, with the
// optional value expression on the same line. The match-arm body shares this
// node so a diverging arm (`=> return ...`) carries the same shape as the
// statement form and the checker sees one return-statement kind.
fn parse_return_statement(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var children: U64 = 0
    var end = start.end
    if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) {
        let expr = try parse_expression(d, state, cursor, depth)
        if parse_step_bad(expr) { return Ok(expr) }
        let ev = parse_step_value(expr)
        cursor = try add_link(d, ev.cursor, ev.node, 0)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, ev.node - 1).end
    }
    let node = try add_syntax(d, cursor, 18, initial.token + 1, start.source, start.start, end, 0, 0, children)
    return Ok(Parsed(node))
}

fn parse_unsafe_c(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) || !token_text(state, parse_token(state, cursor), "c") { return reject_parse(d, state, cursor, 17) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let open = try expect_punct(d, state, cursor, "\{")
    if parse_step_bad(open) { return Ok(open) }
    let expr = try parse_expression(d, state, parse_step_cursor(open), depth + 1)
    if parse_step_bad(expr) { return Ok(expr) }
    let value = parse_step_value(expr)
    let rec = __s0_buffer_get(SyntaxRec, value.cursor.store.nodes, value.node - 1)
    // Inside the braces: a direct call, a field read, or a field write.
    // The write form is an assignment-shaped selector; its right-hand side
    // must stay on the same line as the selector.
    var end_cursor = value.cursor
    if rec.kind == 29 {
        if token_punct(state, end_cursor, "=") {
            let rhs_cursor = ParseCursor(token: end_cursor.token + 1, store: end_cursor.store)
            if !expression_line_ok(state, rhs_cursor, depth) { return reject_parse(d, state, rhs_cursor, 13) }
            let rhs = try parse_expression(d, state, rhs_cursor, depth + 1)
            if parse_step_bad(rhs) { return Ok(rhs) }
            let written = parse_step_value(rhs)
            end_cursor = written.cursor
            let head = try add_link(d, ParseCursor(token: end_cursor.token + 1, store: end_cursor.store), value.node, 0)
            let head_id = __s0_buffer_len(SyntaxLinkRec, head.store.links)
            cursor = try add_link(d, head, written.node, head_id)
        } else {
            cursor = try add_link(d, ParseCursor(token: end_cursor.token + 1, store: end_cursor.store), value.node, 0)
        }
    } else {
        if rec.kind != 27 { return reject_parse(d, state, initial, 30) }
        cursor = try add_link(d, ParseCursor(token: end_cursor.token + 1, store: end_cursor.store), value.node, 0)
    }
    if !token_punct(state, end_cursor, "}") { return reject_parse(d, state, end_cursor, 18) }
    let close = parse_token(state, end_cursor)
    let node = try add_syntax(d, cursor, 36, initial.token + 1, start.source, start.start, close.end, 0, 0, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
    return Ok(Parsed(node))
}

fn parse_array_literal(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let open = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var children: U64 = 0
    if !token_punct(state, cursor, "]") {
        var more = true
        while more {
            let element = try parse_expression(d, state, cursor, depth + 1)
            if parse_step_bad(element) { return Ok(element) }
            let value = parse_step_value(element)
            cursor = try add_link(d, value.cursor, value.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, "]") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, "]")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 50, initial.token + 1, open.source, open.start, end, 0, 0, children)
    return Ok(Parsed(node))
}

// A closure literal shares its opening `fn (...)` with the function type.
// Scanning the balanced parameter list decides: a `:` at nesting depth one
// introduces a named parameter (types never name parameters), and after the
// closing parenthesis a closure body starts with `=>` or `{`, while the type
// form continues with `->` alone.
fn closure_literal_ahead(state: State, initial: ParseCursor) -> Bool {
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_punct(state, cursor, "(") { return false }
    var depth: U64 = 1
    var named = false
    var scanning = true
    while scanning {
        let token = parse_token(state, ParseCursor(token: cursor.token + 1, store: cursor.store))
        if token.kind == 0 { return false }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if token.kind == 5 {
            if token_text(state, token, "(") { depth = depth + 1 }
            if token_text(state, token, ")") {
                depth = depth - 1
                if depth == 0 { scanning = false }
            }
            if depth == 1 && token_text(state, token, ":") { named = true }
        }
    }
    let after = parse_token(state, ParseCursor(token: cursor.token + 1, store: cursor.store))
    if after.kind != 5 { return false }
    if token_text(state, after, "=>") { return true }
    if token_text(state, after, "\{") { return true }
    if token_text(state, after, "->") {
        if named { return true }
        // An annotated braced closure continues with `{` after the result
        // type; the bare type form ends there. Scan the result type's token
        // extent and look one token past it.
        var scan = cursor.token + 2
        var nest: U64 = 0
        var scanning_type = true
        while scanning_type {
            let step = parse_token(state, ParseCursor(token: scan, store: cursor.store))
            if step.kind == 0 { return false }
            if nest == 0 && step.kind == 5 {
                if token_text(state, step, "(") || token_text(state, step, "[") { nest = nest + 1 }
                else { if token_text(state, step, "\{") { return true }
                    // A result type may itself be `fn(...) -> ...`, so an
                    // arrow at the top level continues the type rather than
                    // ending the scan.
                    if token_text(state, step, "->") { scan = scan + 1 } else {
                    if token_text(state, step, ",") { scan = scan + 1 } else {
                    if token_text(state, step, "=>") { return true }
                    return false } } }
            } else {
                if nest != 0 && step.kind == 5 {
                    if token_text(state, step, "(") || token_text(state, step, "[") { nest = nest + 1 }
                    if token_text(state, step, ")") || token_text(state, step, "]") { nest = nest - 1 }
                }
            }
            scan = scan + 1
        }
        return false
    }
    return false
}

// `fn (name: Type, ...) => expr` and `fn (name: Type, ...) -> R { ... }` are
// closure literals (kind 58). Children are the kind-13 parameter nodes, the
// result type node when annotated, and the body (an expression for the arrow
// form, a kind-14 block for the braced form).
fn parse_closure(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    let open = try expect_punct(d, state, cursor, "(")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_cursor(open)
    let binding_base = cursor.store.binding_count
    var children: U64 = 0
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            let param_head = parse_token(state, cursor)
            if param_head.kind == 1 && (param_head.keyword == 23 || param_head.keyword == 24) { return reject_parse(d, state, cursor, 51) }
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            let colon_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let colon = try expect_punct(d, state, colon_cursor, ":")
            if parse_step_bad(colon) { return Ok(colon) }
            cursor = parse_step_cursor(colon)
            let ty = try parse_type(d, state, cursor)
            if parse_step_bad(ty) { return Ok(ty) }
            let tv = parse_step_value(ty)
            let linked = try add_link(d, tv.cursor, tv.node, 0)
            let pnode = try add_syntax(d, linked, 13, colon_cursor.token, param.source, param.start, __s0_buffer_get(SyntaxRec, linked.store.nodes, tv.node - 1).end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
            cursor = try add_link(d, pnode.cursor, pnode.node, children)
            cursor = try parse_add_binding(d, cursor, param)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, ")")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    if token_punct(state, cursor, "=>") {
        let body = try parse_expression(d, state, ParseCursor(token: cursor.token + 1, store: cursor.store), depth)
        if parse_step_bad(body) { return Ok(body) }
        let value = parse_step_value(body)
        // The arrow body is an implicit return statement inside a block, so
        // the closure node has the same [params..., (result)?, block] shape
        // as the braced form and checks through the ordinary function-body
        // path.
        let wrapped = try add_link(d, value.cursor, value.node, 0)
        let statement = try add_syntax(d, wrapped, 18, value.cursor.token + 1, start.source, start.start, __s0_buffer_get(SyntaxRec, wrapped.store.nodes, value.node - 1).end, 0, 0, __s0_buffer_len(SyntaxLinkRec, wrapped.store.links))
        let block_linked = try add_link(d, statement.cursor, statement.node, 0)
        let block = try add_syntax(d, block_linked, 14, value.cursor.token + 1, start.source, start.start, __s0_buffer_get(SyntaxRec, block_linked.store.nodes, value.node - 1).end, 0, 0, __s0_buffer_len(SyntaxLinkRec, block_linked.store.links))
        cursor = try add_link(d, block.cursor, block.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, block.node - 1).end
        cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, binding_base))
        let node = try add_syntax(d, cursor, 58, initial.token + 2, start.source, start.start, end, start.start, start.end, children)
        return Ok(Parsed(node))
    }
    if token_punct(state, cursor, "->") {
        let result = try parse_type(d, state, ParseCursor(token: cursor.token + 1, store: cursor.store))
        if parse_step_bad(result) { return Ok(result) }
        let rv = parse_step_value(result)
        cursor = try add_link(d, rv.cursor, rv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let block = try parse_block(d, state, cursor)
        if parse_step_bad(block) { return Ok(block) }
        let bv = parse_step_value(block)
        cursor = try add_link(d, bv.cursor, bv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1).end
        cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, binding_base))
        let node = try add_syntax(d, cursor, 58, initial.token + 2, start.source, start.start, end, start.start, start.end, children)
        return Ok(Parsed(node))
    }
    let block = try parse_block(d, state, cursor)
    if parse_step_bad(block) { return Ok(block) }
    let bv = parse_step_value(block)
    cursor = try add_link(d, bv.cursor, bv.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    let end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1).end
    cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, binding_base))
    let node = try add_syntax(d, cursor, 58, initial.token + 2, start.source, start.start, end, start.start, start.end, children)
    return Ok(Parsed(node))
}

// Interpolation expressions are deliberately narrower than ordinary
// expressions: they are brace-free and quote-free so the first closing brace
// ends the interpolation without a nesting stack. This scan rejects a brace,
// a string literal, and every keyword except the value words before the
// ordinary expression parser runs, so the rejection is one parse diagnostic
// instead of an unrelated downstream parse failure.
fn interpolation_tokens_ok(state: State, cursor: ParseCursor) -> U64 {
    var at = cursor.token
    while at < __s0_buffer_len(TokenRec, state.tokens) {
        let token = __s0_buffer_get(TokenRec, state.tokens, at)
        if token.kind == 0 { return 0 }
        let item = ParseCursor(token: at, store: cursor.store)
        if token_punct(state, item, "}") { return 1 }
        if token.kind == 4 { return 2 }
        if token_punct(state, item, "\{") || token_punct(state, item, "=") || token_punct(state, item, "=>") || token_punct(state, item, "->") { return 2 }
        if token.kind == 1 {
            let keyword = token.keyword
            if !(keyword == 0 || keyword == 16 || keyword == 17 || keyword == 18 || keyword == 26 || keyword == 29) { return 2 }
        }
        at = at + 1
    }
    return 0
}

// parse_interpolation consumes the segment tokens around one string
// interpolation, wraps each embedded expression in a kind-68 display part,
// and links literal segments and display parts in source order. The lexer
// guarantees the token shape; the checks here turn a malformed interpolation
// into parse diagnostics 52 and 53.
fn parse_interpolation(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    var cursor = initial
    var children: U64 = 0
    var first = true
    var saw_interpolation = false
    var seg_end = parse_token(state, cursor).end
    var more = true
    while more {
        let token = parse_token(state, cursor)
        if token.kind == 4 && (first || token.start == seg_end) {
            let literal = try add_syntax(d, cursor, 22, cursor.token + 1, token.source, token.start, token.end, 0, 0, 0)
            cursor = ParseCursor(token: cursor.token + 1, store: literal.cursor.store)
            cursor = try add_link(d, cursor, literal.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            seg_end = token.end
            first = false
        }
        if token_punct(state, cursor, "\{") && parse_token(state, cursor).start == seg_end {
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let scan = interpolation_tokens_ok(state, cursor)
            if scan == 0 { return reject_parse(d, state, cursor, 53) }
            if scan == 2 { return reject_parse(d, state, cursor, 52) }
            if token_punct(state, cursor, "}") { return reject_parse(d, state, cursor, 52) }
            let expression = try parse_expression(d, state, cursor, depth + 1)
            if parse_step_bad(expression) { return Ok(expression) }
            let value = parse_step_value(expression)
            if !token_punct(state, value.cursor, "}") { return reject_parse(d, state, value.cursor, 53) }
            let close = parse_token(state, value.cursor)
            var after = ParseCursor(token: value.cursor.token + 1, store: value.cursor.store)
            let expression_node = __s0_buffer_get(SyntaxRec, after.store.nodes, value.node - 1)
            after = try add_link(d, after, value.node, 0)
            let part = try add_syntax(d, after, 68, expression_node.token, expression_node.source, expression_node.start, expression_node.end, 0, 0, __s0_buffer_len(SyntaxLinkRec, after.store.links))
            cursor = ParseCursor(token: part.cursor.token, store: part.cursor.store)
            cursor = try add_link(d, cursor, part.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            seg_end = close.end
            saw_interpolation = true
        } else {
            more = false
        }
    }
    if !saw_interpolation { return reject_parse(d, state, initial, 52) }
    let start = parse_token(state, initial)
    let node = try add_syntax(d, cursor, 67, initial.token + 1, start.source, start.start, seg_end, 0, 0, children)
    return Ok(Parsed(node))
}

fn parse_primary(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let token = parse_token(state, initial)
    if depth > parse_depth_limit() { return parse_depth_reject(d, state, initial) }
    // `fn(A, B) -> R` is the function type and may appear wherever a type
    // expression is an operand; parse_type builds the same node kind. A
    // closure literal also starts with `fn (...)`, so the parenthesized list
    // is scanned ahead: named parameters or a body introducer mean a
    // closure (kind 58), otherwise it is the type form.
    if token.kind == 1 && token.keyword == 4 {
        let next = ParseCursor(token: initial.token + 1, store: initial.store)
        if token_punct(state, next, "(") {
            if closure_literal_ahead(state, initial) { return parse_closure(d, state, initial, depth) }
            return parse_type(d, state, initial)
        }
    }
    if token.keyword == 13 { return parse_match(d, state, initial, depth) }
    if token.keyword == 19 { return parse_unsafe_c(d, state, initial, depth) }
    if token_punct(state, initial, "[") { return parse_array_literal(d, state, initial, depth) }
    if token.kind == 4 {
        let next = ParseCursor(token: initial.token + 1, store: initial.store)
        if token_punct(state, next, "\{") && parse_token(state, next).start == token.end { return parse_interpolation(d, state, initial, depth) }
    }
    var kind: U64 = 0
    if token.kind == 2 { kind = 20 }
    if token.kind == 3 { kind = 21 }
    if token.kind == 4 { kind = 22 }
    if token.kind == 1 && (token.keyword == 17 || token.keyword == 18) { kind = 23 }
    if token_ident(state, initial) || token.keyword == 26 { kind = 24 }
    if kind != 0 {
        let names = kind == 24
        var name_start: U64 = 0
        var name_end: U64 = 0
        if names {
            name_start = token.start
            name_end = token.end
        }
        let node = try add_syntax(d, ParseCursor(token: initial.token + 1, store: initial.store), kind, initial.token + 1, token.source, token.start, token.end, name_start, name_end, 0)
        return Ok(Parsed(node))
    }
    if token.keyword == 16 {
        let cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if !expression_line_ok(state, cursor, depth) { return reject_parse(d, state, cursor, 13) }
        let operand = try parse_unary(d, state, cursor, depth)
        if parse_step_bad(operand) { return Ok(operand) }
        let value = parse_step_value(operand)
        let linked = try add_link(d, value.cursor, value.node, 0)
        let child = __s0_buffer_get(SyntaxRec, linked.store.nodes, value.node - 1)
        let node = try add_syntax(d, linked, 31, initial.token + 1, token.source, token.start, child.end, token.start, token.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
        return Ok(Parsed(node))
    }
    if token_punct(state, initial, "(") {
        let unit_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if token_punct(state, unit_cursor, ")") {
            let close = parse_token(state, unit_cursor)
            let cursor = ParseCursor(token: unit_cursor.token + 1, store: initial.store)
            let node = try add_syntax(d, cursor, 66, initial.token + 1, token.source, token.start, close.end, 0, 0, 0)
            return Ok(Parsed(node))
        }
        let inside = try parse_expression(d, state, ParseCursor(token: initial.token + 1, store: initial.store), depth + 1)
        if parse_step_bad(inside) { return Ok(inside) }
        let value = parse_step_value(inside)
        let close = try expect_punct(d, state, value.cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        return Ok(Parsed(ParseValue(cursor: parse_step_cursor(close), node: value.node)))
    }
    return reject_parse(d, state, initial, 12)
}

// dotted_callee_associated decides whether a dotted call callee names an
// associated function through a type instead of a method on a value: the
// leftmost segment of the dotted chain must be a plain word that starts
// uppercase or matches the namespace a bare import binds. The caller uses
// the answer to keep the dotted base out of the call's runtime arguments,
// so the qualified form `bytes.BytesBuilder.new()` behaves exactly like
// the two-segment form `BytesBuilder.new()`.
// Whether an import root binds selected names instead of a module namespace.
// A selected import (`import a.b { Name }`) binds no namespace, so a dotted
// call whose base happens to share the module's final component is a method
// call on that binding, not an associated call through the module.
fn import_root_has_selected(state: State, parse: ParseStore, root: SyntaxRec) -> Bool {
    var link = root.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        if __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1).kind == 43 { return true }
        link = item.next
    }
    return false
}

fn dotted_callee_associated(state: State, cursor: ParseCursor, callee: SyntaxRec) -> Bool {
    var base = callee
    while base.kind == 29 && base.children != 0 {
        let base_link = __s0_buffer_get(SyntaxLinkRec, cursor.store.links, base.children - 1)
        base = __s0_buffer_get(SyntaxRec, cursor.store.nodes, base_link.node - 1)
    }
    if base.kind != 24 { return false }
    if parse_binding_shadows(state, cursor.store, base) { return false }
    let source = __s0_buffer_get(SourceRec, state.sources, base.source)
    let first = text_byte(state, source, base.name_start)
    if first >= 65 && first <= 90 { return true }
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, cursor.store.roots) {
        let root = __s0_buffer_get(SyntaxRec, cursor.store.nodes, __s0_buffer_get(U64, cursor.store.roots, root_at) - 1)
        if root.source == base.source && (root.kind == 41 || root.kind == 42) && !import_root_has_selected(state, cursor.store, root) {
            var candidate_start = root.name_start
            var candidate_end = root.name_end
            var path_at = root.name_start
            while path_at < root.name_end {
                if text_byte(state, source, path_at) == 46 { candidate_start = path_at + 1 }
                path_at = path_at + 1
            }
            var child_link = root.children
            while child_link != 0 {
                let child = __s0_buffer_get(SyntaxLinkRec, cursor.store.links, child_link - 1)
                let child_node = __s0_buffer_get(SyntaxRec, cursor.store.nodes, child.node - 1)
                if child_node.kind == 44 {
                    candidate_start = child_node.name_start
                    candidate_end = child_node.name_end
                }
                child_link = child.next
            }
            if candidate_end - candidate_start == base.name_end - base.name_start {
                var equal = true
                var name_at: U64 = 0
                while name_at < base.name_end - base.name_start {
                    if text_byte(state, source, candidate_start + name_at) != text_byte(state, source, base.name_start + name_at) { equal = false }
                    name_at = name_at + 1
                }
                if equal { return true }
            }
        }
        root_at = root_at + 1
    }
    return false
}

fn parse_postfix(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let primary = try parse_primary(d, state, initial, depth)
    if parse_step_bad(primary) { return Ok(primary) }
    var value = parse_step_value(primary)
    var more = true
    while more {
        let mark = parse_token(state, value.cursor)
        if token_punct(state, value.cursor, "(") {
            if !expression_line_ok(state, value.cursor, depth) { return reject_parse(d, state, value.cursor, 13) }
            var cursor = ParseCursor(token: value.cursor.token + 1, store: value.cursor.store)
            cursor = try add_link(d, cursor, value.node, 0)
            var children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            let callee = __s0_buffer_get(SyntaxRec, cursor.store.nodes, value.node - 1)
            if callee.kind == 29 {
                let base_link = __s0_buffer_get(SyntaxLinkRec, cursor.store.links, callee.children - 1)
                if !dotted_callee_associated(state, cursor, callee) {
                    cursor = try add_link(d, cursor, base_link.node, children)
                    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                }
            }
            if !token_punct(state, cursor, ")") {
                var args = true
                while args {
                    var arg: ParseStep = Rejected(cursor)
                    let first = parse_token(state, cursor)
                    let peek = ParseCursor(token: cursor.token + 1, store: cursor.store)
                    if token_ident(state, cursor) && token_punct(state, peek, ":") {
                        let parsed = try parse_expression(d, state, ParseCursor(token: cursor.token + 2, store: cursor.store), depth + 1)
                        if parse_step_bad(parsed) { return Ok(parsed) }
                        let item = parse_step_value(parsed)
                        let linked = try add_link(d, item.cursor, item.node, 0)
                        let rec = __s0_buffer_get(SyntaxRec, linked.store.nodes, item.node - 1)
                        let named = try add_syntax(d, linked, 28, cursor.token + 1, first.source, first.start, rec.end, first.start, first.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
                        arg = Parsed(named)
                    } else { arg = try parse_expression(d, state, cursor, depth + 1) }
                    if parse_step_bad(arg) { return Ok(arg) }
                    let av = parse_step_value(arg)
                    cursor = try add_link(d, av.cursor, av.node, children)
                    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                    if token_punct(state, cursor, ",") {
                        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                        if token_punct(state, cursor, ")") { args = false }
                    } else { args = false }
                }
            }
            let close = try expect_punct(d, state, cursor, ")")
            if parse_step_bad(close) { return Ok(close) }
            cursor = parse_step_cursor(close)
            let base = __s0_buffer_get(SyntaxRec, cursor.store.nodes, value.node - 1)
            value = try add_syntax(d, cursor, 27, value.cursor.token + 1, mark.source, base.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, 0, 0, children)
        } else {
            if token_punct(state, value.cursor, ".") {
                if !expression_line_ok(state, value.cursor, depth) { return reject_parse(d, state, value.cursor, 13) }
                let name_cursor = ParseCursor(token: value.cursor.token + 1, store: value.cursor.store)
                // `take` is a parameter-mode keyword, but it is also the
                // builtin Option.take method name. A member position after a
                // dot is unambiguous, so the keyword is accepted there.
                let member_keyword = parse_token(state, name_cursor).keyword
                if !token_ident(state, name_cursor) && member_keyword != 24 { return reject_parse(d, state, name_cursor, 3) }
                let name = parse_token(state, name_cursor)
                var cursor = ParseCursor(token: name_cursor.token + 1, store: name_cursor.store)
                cursor = try add_link(d, cursor, value.node, 0)
                let base = __s0_buffer_get(SyntaxRec, cursor.store.nodes, value.node - 1)
                value = try add_syntax(d, cursor, 29, value.cursor.token + 1, mark.source, base.start, name.end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
            } else {
                if token_punct(state, value.cursor, "[") {
                    if !expression_line_ok(state, value.cursor, depth) { return reject_parse(d, state, value.cursor, 13) }
                    let index = try parse_expression(d, state, ParseCursor(token: value.cursor.token + 1, store: value.cursor.store), depth + 1)
                    if parse_step_bad(index) { return Ok(index) }
                    let iv = parse_step_value(index)
                    let close = try expect_punct(d, state, iv.cursor, "]")
                    if parse_step_bad(close) { return Ok(close) }
                    var cursor = parse_step_cursor(close)
                    cursor = try add_link(d, cursor, value.node, 0)
                    let children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                    cursor = try add_link(d, cursor, iv.node, children)
                    let base = __s0_buffer_get(SyntaxRec, cursor.store.nodes, value.node - 1)
                    value = try add_syntax(d, cursor, 30, value.cursor.token + 1, mark.source, base.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, 0, 0, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
                } else { more = false }
            }
        }
    }
    return Ok(Parsed(value))
}

fn parse_unary(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let token = parse_token(state, initial)
    if token_punct(state, initial, "-") || token_punct(state, initial, "!") || token_punct(state, initial, "~") {
        let cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if !expression_line_ok(state, cursor, depth) { return reject_parse(d, state, cursor, 13) }
        let operand = try parse_unary(d, state, cursor, depth)
        if parse_step_bad(operand) { return Ok(operand) }
        let value = parse_step_value(operand)
        let linked = try add_link(d, value.cursor, value.node, 0)
        let child = __s0_buffer_get(SyntaxRec, linked.store.nodes, value.node - 1)
        let node = try add_syntax(d, linked, 25, initial.token + 1, token.source, token.start, child.end, token.start, token.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
        return Ok(Parsed(node))
    }
    return parse_postfix(d, state, initial, depth)
}

fn parse_binary(d: Domain, state: State, initial: ParseCursor, depth: U64, minimum: U64) -> Result(ParseStep, __s0_Error) {
    let first = try parse_unary(d, state, initial, depth)
    if parse_step_bad(first) { return Ok(first) }
    var value = parse_step_value(first)
    var more = true
    var chain: U64 = 0
    while more {
        let precedence = expression_precedence(state, value.cursor)
        if precedence == 0 || precedence < minimum { more = false } else {
            chain = chain + 1
            if chain > parse_depth_limit() { return parse_depth_reject(d, state, value.cursor) }
            if !expression_line_ok(state, value.cursor, depth) { return reject_parse(d, state, value.cursor, 13) }
            let operator_cursor = value.cursor
            let operator = parse_token(state, operator_cursor)
            let right_cursor = ParseCursor(token: operator_cursor.token + 1, store: operator_cursor.store)
            if !expression_line_ok(state, right_cursor, depth) { return reject_parse(d, state, right_cursor, 13) }
            let right = try parse_binary(d, state, right_cursor, depth, precedence + 1)
            if parse_step_bad(right) { return Ok(right) }
            let rv = parse_step_value(right)
            var cursor = try add_link(d, rv.cursor, value.node, 0)
            let children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            cursor = try add_link(d, cursor, rv.node, children)
            let left = __s0_buffer_get(SyntaxRec, cursor.store.nodes, value.node - 1)
            let right_rec = __s0_buffer_get(SyntaxRec, cursor.store.nodes, rv.node - 1)
            value = try add_syntax(d, cursor, 26, operator_cursor.token + 1, operator.source, left.start, right_rec.end, operator.start, operator.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        }
    }
    return Ok(Parsed(value))
}

fn parse_expression(d: Domain, state: State, cursor: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    return parse_binary(d, state, cursor, depth, 1)
}

// An assignment target is a name or any chain of field and index projections
// rooted at one name: `a`, `a.b`, `a[0]`, `a.b.c`, `a.b[0]`, and `a[0].b[1]`
// all store into a place the checker resolves. Anything else, such as a call
// or an operator result, is not a place.
fn assignment_target(store: ParseStore, node_id: U64) -> Bool {
    let node = __s0_buffer_get(SyntaxRec, store.nodes, node_id - 1)
    if node.kind == 24 { return true }
    if node.kind != 29 && node.kind != 30 { return false }
    let head = __s0_buffer_get(SyntaxLinkRec, store.links, node.children - 1)
    var base_link = head
    if node.kind == 30 { base_link = __s0_buffer_get(SyntaxLinkRec, store.links, head.next - 1) }
    return assignment_target(store, base_link.node)
}

fn parse_statement(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    if start.keyword == 7 || start.keyword == 9 {
        var kind: U64 = 32
        if start.keyword == 9 { kind = 33 }
        let condition_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if !expression_line_ok(state, condition_cursor, 0) { return reject_parse(d, state, condition_cursor, 13) }
        let condition = try parse_expression(d, state, condition_cursor, 0)
        if parse_step_bad(condition) { return Ok(condition) }
        let cv = parse_step_value(condition)
        let body = try parse_block(d, state, cv.cursor)
        if parse_step_bad(body) { return Ok(body) }
        let bv = parse_step_value(body)
        var cursor = try add_link(d, bv.cursor, cv.node, 0)
        var children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        cursor = try add_link(d, cursor, bv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        var end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1).end
        if kind == 32 && parse_token(state, cursor).keyword == 8 {
            let else_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            var alternative: ParseStep = Rejected(else_cursor)
            if parse_token(state, else_cursor).keyword == 7 {
                // `else if` is an else whose block holds one nested if
                // statement; the chain nests through this same rule.
                let nested = try parse_statement(d, state, else_cursor)
                if parse_step_bad(nested) { return Ok(nested) }
                let nv = parse_step_value(nested)
                let nested_end = __s0_buffer_get(SyntaxRec, nv.cursor.store.nodes, nv.node - 1).end
                let if_token = parse_token(state, else_cursor)
                var block_cursor = try add_link(d, ParseCursor(token: nv.cursor.token, store: nv.cursor.store), nv.node, 0)
                let block_children = __s0_buffer_len(SyntaxLinkRec, block_cursor.store.links)
                let block_node = try add_syntax(d, block_cursor, 14, else_cursor.token + 1, if_token.source, if_token.start, nested_end, 0, 0, block_children)
                alternative = Parsed(block_node)
            } else {
                alternative = try parse_block(d, state, else_cursor)
            }
            if parse_step_bad(alternative) { return Ok(alternative) }
            let av = parse_step_value(alternative)
            cursor = try add_link(d, av.cursor, av.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, av.node - 1).end
        }
        let node = try add_syntax(d, cursor, kind, initial.token + 1, start.source, start.start, end, 0, 0, children)
        return Ok(Parsed(node))
    }
    if start.keyword == 10 {
        let name_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if !token_ident(state, name_cursor) { return reject_parse(d, state, name_cursor, 3) }
        let name = parse_token(state, name_cursor)
        var cursor = ParseCursor(token: name_cursor.token + 1, store: name_cursor.store)
        if parse_token(state, cursor).keyword != 11 { return reject_parse(d, state, cursor, 4) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !expression_line_ok(state, cursor, 0) { return reject_parse(d, state, cursor, 13) }
        let sequence = try parse_expression(d, state, cursor, 0)
        if parse_step_bad(sequence) { return Ok(sequence) }
        let sv = parse_step_value(sequence)
        let binding_base = sv.cursor.store.binding_count
        let loop_binding = try parse_add_binding(d, sv.cursor, name)
        let body = try parse_block(d, state, loop_binding)
        if parse_step_bad(body) { return Ok(body) }
        let bv = parse_step_value(body)
        var body_cursor = bv.cursor
        body_cursor = ParseCursor(token: body_cursor.token, store: parse_restore_bindings(body_cursor.store, binding_base))
        body_cursor = try add_link(d, body_cursor, sv.node, 0)
        let children = __s0_buffer_len(SyntaxLinkRec, body_cursor.store.links)
        body_cursor = try add_link(d, body_cursor, bv.node, children)
        let node = try add_syntax(d, body_cursor, 34, initial.token + 1, start.source, start.start, __s0_buffer_get(SyntaxRec, body_cursor.store.nodes, bv.node - 1).end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, body_cursor.store.links))
        return Ok(Parsed(node))
    }
    if start.keyword == 14 {
        let name_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if !token_ident(state, name_cursor) { return reject_parse(d, state, name_cursor, 3) }
        let name = parse_token(state, name_cursor)
        let equals = try expect_punct(d, state, ParseCursor(token: name_cursor.token + 1, store: name_cursor.store), "=")
        if parse_step_bad(equals) { return Ok(equals) }
        var cursor = parse_step_cursor(equals)
        if !expression_line_ok(state, cursor, 0) { return reject_parse(d, state, cursor, 13) }
        let expr = try parse_expression(d, state, cursor, 0)
        if parse_step_bad(expr) { return Ok(expr) }
        let ev = parse_step_value(expr)
        cursor = ev.cursor
        var end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, ev.node - 1).end
        // The `with cleanup_function` clause is the bootstrap-private bridge
        // form; the M7.5 public form registers the builtin owner cleanup and
        // ends the statement after the initializer. The initializer links
        // exactly once in either shape.
        if parse_token(state, cursor).keyword == 15 {
            let with_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if !expression_line_ok(state, with_cursor, 0) { return reject_parse(d, state, with_cursor, 13) }
            if !token_ident(state, with_cursor) { return reject_parse(d, state, with_cursor, 3) }
            let cleanup = parse_token(state, with_cursor)
            let cleanup_node = try add_syntax(d, ParseCursor(token: with_cursor.token + 1, store: with_cursor.store), 24, with_cursor.token + 1, cleanup.source, cleanup.start, cleanup.end, cleanup.start, cleanup.end, 0)
            cursor = try add_link(d, cleanup_node.cursor, ev.node, 0)
            let children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            cursor = try add_link(d, cursor, cleanup_node.node, children)
            end = cleanup.end
        } else {
            cursor = try add_link(d, cursor, ev.node, 0)
        }
        let node = try add_syntax(d, cursor, 35, initial.token + 1, start.source, start.start, end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        let bound = try parse_add_binding(d, node.cursor, name)
        return Ok(Parsed(ParseValue(cursor: bound, node: node.node)))
    }
    if start.keyword == 5 || start.keyword == 6 {
        var kind: U64 = 15
        if start.keyword == 6 { kind = 16 }
        let name_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        if !token_ident(state, name_cursor) { return reject_parse(d, state, name_cursor, 3) }
        let name = parse_token(state, name_cursor)
        var cursor = ParseCursor(token: name_cursor.token + 1, store: name_cursor.store)
        var children: U64 = 0
        if token_punct(state, cursor, ":") {
            let ty = try parse_type(d, state, ParseCursor(token: cursor.token + 1, store: cursor.store))
            if parse_step_bad(ty) { return Ok(ty) }
            let tv = parse_step_value(ty)
            cursor = try add_link(d, tv.cursor, tv.node, 0)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        }
        let equals = try expect_punct(d, state, cursor, "=")
        if parse_step_bad(equals) { return Ok(equals) }
        cursor = parse_step_cursor(equals)
        if !expression_line_ok(state, cursor, 0) { return reject_parse(d, state, cursor, 13) }
        let expr = try parse_expression(d, state, cursor, 0)
        if parse_step_bad(expr) { return Ok(expr) }
        let ev = parse_step_value(expr)
        cursor = try add_link(d, ev.cursor, ev.node, children)
        let rec = __s0_buffer_get(SyntaxRec, cursor.store.nodes, ev.node - 1)
        let node = try add_syntax(d, cursor, kind, initial.token + 1, start.source, start.start, rec.end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        let bound = try parse_add_binding(d, node.cursor, name)
        return Ok(Parsed(ParseValue(cursor: bound, node: node.node)))
    }
    if start.keyword == 12 {
        return parse_return_statement(d, state, initial, 0)
    }
    if start.keyword == 30 || start.keyword == 31 {
        // break and continue carry no value and take no argument; a following
        // expression is a line-separation error like any other.
        var kind: U64 = 59
        if start.keyword == 31 { kind = 60 }
        let node = try add_syntax(d, ParseCursor(token: initial.token + 1, store: initial.store), kind, initial.token + 1, start.source, start.start, start.end, 0, 0, 0)
        return Ok(Parsed(node))
    }
    if token_punct(state, initial, "\{") { return parse_block(d, state, initial) }
    let expr = try parse_expression(d, state, initial, 0)
    if parse_step_bad(expr) { return Ok(expr) }
    let ev = parse_step_value(expr)
    if token_punct(state, ev.cursor, "=") {
        if !assignment_target(ev.cursor.store, ev.node) { return reject_parse(d, state, initial, 14) }
        let assignment = parse_token(state, ev.cursor)
        let after = ParseCursor(token: ev.cursor.token + 1, store: ev.cursor.store)
        if !expression_line_ok(state, after, 0) { return reject_parse(d, state, after, 13) }
        let rhs = try parse_expression(d, state, after, 0)
        if parse_step_bad(rhs) { return Ok(rhs) }
        let rv = parse_step_value(rhs)
        var cursor = try add_link(d, rv.cursor, ev.node, 0)
        let children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        cursor = try add_link(d, cursor, rv.node, children)
        let rec = __s0_buffer_get(SyntaxRec, cursor.store.nodes, rv.node - 1)
        let node = try add_syntax(d, cursor, 17, ev.cursor.token + 1, start.source, start.start, rec.end, assignment.start, assignment.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        return Ok(Parsed(node))
    }
    let linked = try add_link(d, ev.cursor, ev.node, 0)
    let end = parse_token(state, ParseCursor(token: ev.cursor.token - 1, store: ev.cursor.store)).end
    let node = try add_syntax(d, linked, 19, initial.token + 1, start.source, start.start, end, 0, 0, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
    return Ok(Parsed(node))
}

fn parse_block(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    if !token_punct(state, initial, "\{") { return reject_parse(d, state, initial, 4) }
    let binding_base = initial.store.binding_count
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var children: U64 = 0
    while !token_punct(state, cursor, "}") {
        if parse_token(state, cursor).kind == 0 { return reject_parse(d, state, cursor, 4) }
        let stmt = try parse_statement(d, state, cursor)
        if parse_step_bad(stmt) { return Ok(stmt) }
        let value = parse_step_value(stmt)
        cursor = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 11) }
    }
    let close = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: parse_restore_bindings(cursor.store, binding_base))
    let node = try add_syntax(d, cursor, 14, initial.token + 1, start.source, start.start, close.end, 0, 0, children)
    return Ok(Parsed(node))
}

// One type-parameter annotation is `Name: type` or, constrained, `Name:
// type(Trait, ...)` (D024). The trait applications inside the parentheses are
// the parameter's constraints and link as the kind-7 node's children in
// source order; a bare `Name: type` stays unconstrained. Each application is
// an ordinary type node, so `Iterator(Item)` is an applied type. Only `,` and
// `)` continue the list; a constraint may name any parameter of the same
// declaration, including ones declared later in the list.
fn parse_type_param(d: Domain, state: State, param: TokenRec, colon: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let checked = try expect_punct(d, state, colon, ":")
    if parse_step_bad(checked) { return Ok(checked) }
    let after = parse_step_cursor(checked)
    if parse_token(state, after).keyword != 2 { return reject_parse(d, state, after, 4) }
    var cursor = ParseCursor(token: after.token + 1, store: after.store)
    var children: U64 = 0
    if token_punct(state, cursor, "(") {
        let open = try expect_punct(d, state, cursor, "(")
        if parse_step_bad(open) { return Ok(open) }
        cursor = parse_step_cursor(open)
        if !token_punct(state, cursor, ")") {
            var more = true
            while more {
                let application = try parse_type(d, state, cursor)
                if parse_step_bad(application) { return Ok(application) }
                let value = parse_step_value(application)
                cursor = try add_link(d, value.cursor, value.node, children)
                children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                if token_punct(state, cursor, ",") {
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                    if token_punct(state, cursor, ")") { more = false }
                } else { more = false }
            }
        }
        let close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_cursor(close)
    }
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 7, colon.token, param.source, param.start, end, param.start, param.end, children)
    return Ok(Parsed(node))
}

// Trait method requirements look like functions, but the body is optional:
// a present body is the default implementation used by impls that omit the
// method. Receivers are always the trait's `Self` node.
fn parse_trait_method(d: Domain, state: State, initial: ParseCursor, receiver_type: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let open = try expect_punct(d, state, cursor, "(")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_cursor(open)
    let binding_base = cursor.store.binding_count
    var children: U64 = 0
    var runtime = false
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            var parameter_kind: U64 = 13
            if parse_token(state, cursor).keyword == 23 {
                parameter_kind = 47
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            } else {
                if parse_token(state, cursor).keyword == 24 {
                    parameter_kind = 48
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                }
            }
            let receiver = parse_token(state, cursor).keyword == 26
            if !token_ident(state, cursor) && !receiver { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            var pnode: ParseValue = ParseValue(cursor: cursor, node: 0)
            if receiver {
                if runtime { return reject_parse(d, state, cursor, 10) }
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                let owner = __s0_buffer_get(SyntaxRec, cursor.store.nodes, receiver_type - 1)
                let copied = try add_syntax(d, cursor, owner.kind, owner.token, owner.source, owner.start, owner.end, owner.name_start, owner.name_end, owner.children)
                let linked = try add_link(d, copied.cursor, copied.node, 0)
                pnode = try add_syntax(d, linked, parameter_kind, cursor.token, param.source, param.start, param.end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
                runtime = true
            } else {
                let colon_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                let colon = try expect_punct(d, state, colon_cursor, ":")
                if parse_step_bad(colon) { return Ok(colon) }
                cursor = parse_step_cursor(colon)
                if parse_token(state, cursor).keyword == 2 {
                    if runtime { return reject_parse(d, state, ParseCursor(token: colon_cursor.token - 1, store: colon_cursor.store), 10) }
                    let typed = try parse_type_param(d, state, param, colon_cursor)
                    if parse_step_bad(typed) { return Ok(typed) }
                    pnode = parse_step_value(typed)
                } else {
                    let ty = try parse_type(d, state, cursor)
                    if parse_step_bad(ty) { return Ok(ty) }
                    let tv = parse_step_value(ty)
                    let linked = try add_link(d, tv.cursor, tv.node, 0)
                    pnode = try add_syntax(d, linked, parameter_kind, colon_cursor.token, param.source, param.start, __s0_buffer_get(SyntaxRec, linked.store.nodes, tv.node - 1).end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
                    runtime = true
                }
            }
            cursor = try add_link(d, pnode.cursor, pnode.node, children)
            let parameter_node = __s0_buffer_get(SyntaxRec, cursor.store.nodes, pnode.node - 1)
            if parameter_node.kind == 13 || parameter_node.kind == 47 || parameter_node.kind == 48 { cursor = try parse_add_binding(d, cursor, param) }
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, ")")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    let arrow = try expect_punct(d, state, cursor, "->")
    if parse_step_bad(arrow) { return Ok(arrow) }
    let result = try parse_type(d, state, parse_step_cursor(arrow))
    if parse_step_bad(result) { return Ok(result) }
    let rv = parse_step_value(result)
    cursor = try add_link(d, rv.cursor, rv.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    if parse_token(state, cursor).keyword == 28 { return reject_parse(d, state, cursor, 24) }
    var end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    if token_punct(state, cursor, "\{") {
        let body = try parse_block(d, state, cursor)
        if parse_step_bad(body) { return Ok(body) }
        let bv = parse_step_value(body)
        cursor = try add_link(d, bv.cursor, bv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let block = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1)
        end = block.end
    }
    cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, binding_base))
    let node = try add_syntax(d, cursor, 51, initial.token + 1, start.source, start.start, end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_trait(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var children: U64 = 0
    if token_punct(state, cursor, "(") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        var more = true
        while more {
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let typed = try parse_type_param(d, state, param, cursor)
            if parse_step_bad(typed) { return Ok(typed) }
            let pnode = parse_step_value(typed)
            cursor = try add_link(d, pnode.cursor, pnode.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
        let close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_cursor(close)
    }
    if parse_token(state, cursor).keyword == 28 { return reject_parse(d, state, cursor, 24) }
    let open = try expect_punct(d, state, cursor, "\{")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_cursor(open)
    // The `Self` reference node is synthesized once per trait; every method
    // receiver copies it so the checker can resolve `Self` uniformly.
    let self_node = try add_syntax(d, cursor, 56, cursor.token, name.source, name.start, name.end, name.start, name.end, 0)
    cursor = self_node.cursor
    while !token_punct(state, cursor, "}") {
        if parse_token(state, cursor).keyword != 4 { return reject_parse(d, state, cursor, 4) }
        let method = try parse_trait_method(d, state, cursor, self_node.node)
        if parse_step_bad(method) { return Ok(method) }
        let value = parse_step_value(method)
        cursor = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 7) }
    }
    let close = try expect_punct(d, state, cursor, "}")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    let node = try add_syntax(d, cursor, 50, initial.token + 1, start.source, start.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_function_owned(d: Domain, state: State, initial: ParseCursor, receiver_type: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let open = try expect_punct(d, state, cursor, "(")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_cursor(open)
    let binding_base = cursor.store.binding_count
    var children: U64 = 0
    var runtime = false
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            var parameter_kind: U64 = 13
            if parse_token(state, cursor).keyword == 23 {
                parameter_kind = 47
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            } else {
                if parse_token(state, cursor).keyword == 24 {
                    parameter_kind = 48
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                }
            }
            let receiver = parse_token(state, cursor).keyword == 26
            if !token_ident(state, cursor) && !receiver { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            var pnode: ParseValue = ParseValue(cursor: cursor, node: 0)
            if receiver {
                if receiver_type == 0 || runtime { return reject_parse(d, state, cursor, 10) }
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                let owner = __s0_buffer_get(SyntaxRec, cursor.store.nodes, receiver_type - 1)
                let copied = try add_syntax(d, cursor, owner.kind, owner.token, owner.source, owner.start, owner.end, owner.name_start, owner.name_end, owner.children)
                let linked = try add_link(d, copied.cursor, copied.node, 0)
                pnode = try add_syntax(d, linked, parameter_kind, cursor.token, param.source, param.start, param.end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
                runtime = true
            } else {
            let colon_cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let colon = try expect_punct(d, state, colon_cursor, ":")
            if parse_step_bad(colon) { return Ok(colon) }
            cursor = parse_step_cursor(colon)
            if parse_token(state, cursor).keyword == 2 {
                if parameter_kind != 13 { return reject_parse(d, state, ParseCursor(token: colon_cursor.token - 1, store: cursor.store), 10) }
                if runtime { return reject_parse(d, state, ParseCursor(token: colon_cursor.token - 1, store: cursor.store), 10) }
                let typed = try parse_type_param(d, state, param, colon_cursor)
                if parse_step_bad(typed) { return Ok(typed) }
                pnode = parse_step_value(typed)
            } else {
                let ty = try parse_type(d, state, cursor)
                if parse_step_bad(ty) { return Ok(ty) }
                let tv = parse_step_value(ty)
                let linked = try add_link(d, tv.cursor, tv.node, 0)
                pnode = try add_syntax(d, linked, parameter_kind, colon_cursor.token, param.source, param.start, __s0_buffer_get(SyntaxRec, linked.store.nodes, tv.node - 1).end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
                runtime = true
            }
            }
            cursor = try add_link(d, pnode.cursor, pnode.node, children)
            let parameter_node = __s0_buffer_get(SyntaxRec, cursor.store.nodes, pnode.node - 1)
            if parameter_node.kind == 13 || parameter_node.kind == 47 || parameter_node.kind == 48 { cursor = try parse_add_binding(d, cursor, param) }
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, ")")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    let arrow = try expect_punct(d, state, cursor, "->")
    if parse_step_bad(arrow) { return Ok(arrow) }
    let result = try parse_type(d, state, parse_step_cursor(arrow))
    if parse_step_bad(result) { return Ok(result) }
    let rv = parse_step_value(result)
    cursor = try add_link(d, rv.cursor, rv.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    if parse_token(state, cursor).keyword == 28 { return reject_parse(d, state, cursor, 24) }
    let body = try parse_block(d, state, cursor)
    if parse_step_bad(body) { return Ok(body) }
    let bv = parse_step_value(body)
    cursor = try add_link(d, bv.cursor, bv.node, children)
    cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, binding_base))
    let block = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1)
    let node = try add_syntax(d, cursor, 12, initial.token + 1, start.source, start.start, block.end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
    return Ok(Parsed(node))
}

fn parse_function(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    return parse_function_owned(d, state, initial, 0)
}

// `export c fn name(...) -> T { ... }` is the C export surface. The parsed
// node is the ordinary kind-12 function declaration, so symbols, signatures,
// bodies, lowering, and verification treat it like any other function; the
// two export tokens stay in the token stream and the symbol pass records the
// exported flag from them.
fn parse_export_c_fn(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) || !token_text(state, parse_token(state, cursor), "c") { return reject_parse(d, state, cursor, 35) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if parse_token(state, cursor).keyword != 4 { return reject_parse(d, state, cursor, 35) }
    return parse_function(d, state, cursor)
}

fn parse_impl(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    // `impl(Param: type(Constraint), ...) Trait for Type` and
    // `impl(Param: type(Constraint), ...) Type(Param)` declare a generic
    // implementation. The parameter list parses exactly like a trait's list;
    // its links chain ahead of the trait or owner application, so the
    // parameter nodes sit at the end of the impl node's child chain (the
    // walkers skip them).
    var chained: U64 = 0
    if token_punct(state, cursor, "(") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        var more = true
        while more {
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let typed = try parse_type_param(d, state, param, cursor)
            if parse_step_bad(typed) { return Ok(typed) }
            let pnode = parse_step_value(typed)
            cursor = try add_link(d, pnode.cursor, pnode.node, chained)
            chained = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
        let param_close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(param_close) { return Ok(param_close) }
        cursor = parse_step_cursor(param_close)
    }
    let owner = try parse_type(d, state, cursor)
    if parse_step_bad(owner) { return Ok(owner) }
    let owner_value = parse_step_value(owner)
    cursor = owner_value.cursor
    // `impl Trait(Arguments) for Type { ... }` declares a trait
    // implementation; the trait application is linked first and the
    // implemented type second, so both stay reachable from the impl node.
    if parse_token(state, cursor).keyword == 10 {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        cursor = try add_link(d, cursor, owner_value.node, chained)
        var trait_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let impl_type = try parse_type(d, state, cursor)
        if parse_step_bad(impl_type) { return Ok(impl_type) }
        let impl_value = parse_step_value(impl_type)
        cursor = try add_link(d, impl_value.cursor, impl_value.node, trait_children)
        trait_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if parse_token(state, cursor).keyword == 28 { return reject_parse(d, state, cursor, 24) }
        let trait_open = try expect_punct(d, state, cursor, "\{")
        if parse_step_bad(trait_open) { return Ok(trait_open) }
        cursor = parse_step_cursor(trait_open)
        while !token_punct(state, cursor, "}") {
            if parse_token(state, cursor).keyword != 4 { return reject_parse(d, state, cursor, 4) }
            let method = try parse_function_owned(d, state, cursor, impl_value.node)
            if parse_step_bad(method) { return Ok(method) }
            let value = parse_step_value(method)
            cursor = try add_root(d, value.cursor, value.node)
            cursor = try add_link(d, cursor, value.node, trait_children)
            trait_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 7) }
        }
        let trait_close = try expect_punct(d, state, cursor, "}")
        if parse_step_bad(trait_close) { return Ok(trait_close) }
        cursor = parse_step_cursor(trait_close)
        let trait_head = __s0_buffer_get(SyntaxRec, cursor.store.nodes, owner_value.node - 1)
        let trait_node = try add_syntax(d, cursor, 53, initial.token + 1, start.source, start.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, trait_head.name_start, trait_head.name_end, trait_children)
        return Ok(Parsed(trait_node))
    }
    let open = try expect_punct(d, state, cursor, "\{")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_cursor(open)
    cursor = try add_link(d, cursor, owner_value.node, chained)
    var children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    while !token_punct(state, cursor, "}") {
        if parse_token(state, cursor).keyword != 4 { return reject_parse(d, state, cursor, 4) }
        let method = try parse_function_owned(d, state, cursor, owner_value.node)
        if parse_step_bad(method) { return Ok(method) }
        let value = parse_step_value(method)
        cursor = try add_root(d, value.cursor, value.node)
        cursor = try add_link(d, cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 7) }
    }
    let close = try expect_punct(d, state, cursor, "}")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    let owner_node = __s0_buffer_get(SyntaxRec, cursor.store.nodes, owner_value.node - 1)
    let node = try add_syntax(d, cursor, 49, initial.token + 1, start.source, start.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, owner_node.name_start, owner_node.name_end, children)
    return Ok(Parsed(node))
}

fn parse_module_path(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    if !token_ident(state, initial) { return reject_parse(d, state, initial, 3) }
    let first = parse_token(state, initial)
    var last = first
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    while token_punct(state, cursor, ".") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
        last = parse_token(state, cursor)
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    }
    let path = try add_syntax(d, cursor, 46, initial.token + 1, first.source, first.start, last.end, first.start, last.end, 0)
    return Ok(Parsed(path))
}

fn parse_module_decl(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    let path = try parse_module_path(d, state, ParseCursor(token: initial.token + 1, store: initial.store))
    if parse_step_bad(path) { return Ok(path) }
    let value = parse_step_value(path)
    let path_node = __s0_buffer_get(SyntaxRec, value.cursor.store.nodes, value.node - 1)
    let linked = try add_link(d, value.cursor, value.node, 0)
    let node = try add_syntax(d, linked, 40, initial.token + 1, start.source, start.start, path_node.end, path_node.name_start, path_node.name_end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
    return Ok(Parsed(node))
}

// C binding blocks: `import c "header.h" as name { ... }`. The block node
// (kind 61) names its alias and links the header string first, then members
// in source order. Members are kind 62 c type, 63 raw fn, and 64 c const; a
// record type member links its kind-65 fields after the spelling string.
// Member spellings are kind-22 string-literal nodes, so the checker reads
// their decoded bytes through the string token's value range. `raw`, `const`,
// `scalar`, `opaque`, and `record` are plain identifiers here, not keywords:
// no other declaration position accepts strings, so dispatch is unambiguous.
fn parse_binding_block(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) || !token_text(state, parse_token(state, cursor), "c") { return reject_parse(d, state, cursor, 21) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if parse_token(state, cursor).kind != 4 { return reject_parse(d, state, cursor, 20) }
    let header = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let header_node = try add_syntax(d, cursor, 22, cursor.token, header.source, header.start, header.end, 0, 0, 0)
    let header_link = try add_link(d, header_node.cursor, header_node.node, 0)
    var children: U64 = __s0_buffer_len(SyntaxLinkRec, header_link.store.links)
    cursor = header_link
    if parse_token(state, cursor).keyword != 22 { return reject_parse(d, state, cursor, 21) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let alias = parse_token(state, cursor)
    let alias_token = cursor.token + 1
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_punct(state, cursor, "\{") { return reject_parse(d, state, cursor, 9) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var first = true
    while !token_punct(state, cursor, "}") {
        if !first && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 21) }
        first = false
        let member = try parse_c_binding_member(d, state, cursor)
        if parse_step_bad(member) { return Ok(member) }
        let value = parse_step_value(member)
        let linked = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, linked.store.links)
        cursor = linked
        if token_punct(state, cursor, ",") || token_punct(state, cursor, ";") { return reject_parse(d, state, cursor, 21) }
    }
    let close = try expect_punct(d, state, cursor, "}")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 61, alias_token, start.source, start.start, end, alias.start, alias.end, children)
    return Ok(Parsed(node))
}

fn parse_c_binding_member(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    if !token_ident(state, initial) { return reject_parse(d, state, initial, 21) }
    let word = parse_token(state, initial)
    if token_text(state, word, "scalar") { return parse_c_type_member(d, state, initial, 0) }
    if token_text(state, word, "opaque") { return parse_c_type_member(d, state, initial, 1) }
    if token_text(state, word, "record") { return parse_c_type_member(d, state, initial, 2) }
    if token_text(state, word, "callback") { return parse_c_callback_member(d, state, initial) }
    if token_text(state, word, "raw") { return parse_c_fn_member(d, state, initial) }
    if token_text(state, word, "const") { return parse_c_const_member(d, state, initial) }
    return reject_parse(d, state, initial, 21)
}

fn parse_c_spelling(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    if parse_token(state, initial).kind != 4 { return reject_parse(d, state, initial, 20) }
    let spelling = parse_token(state, initial)
    let cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    let node = try add_syntax(d, cursor, 22, cursor.token, spelling.source, spelling.start, spelling.end, 0, 0, 0)
    return Ok(Parsed(node))
}

fn parse_c_type_member(d: Domain, state: State, initial: ParseCursor, class: U64) -> Result(ParseStep, __s0_Error) {
    let class_token = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !(parse_token(state, cursor).kind == 1 && parse_token(state, cursor).keyword == 2) { return reject_parse(d, state, cursor, 21) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    let name_token = cursor.token + 1
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_punct(state, cursor, "=") { return reject_parse(d, state, cursor, 8) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let spelling = try parse_c_spelling(d, state, cursor)
    if parse_step_bad(spelling) { return Ok(spelling) }
    let value = parse_step_value(spelling)
    let linked = try add_link(d, value.cursor, value.node, 0)
    var children: U64 = __s0_buffer_len(SyntaxLinkRec, linked.store.links)
    cursor = linked
    if class == 2 {
        if !token_punct(state, cursor, "\{") { return reject_parse(d, state, cursor, 9) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if token_punct(state, cursor, "}") { return reject_parse(d, state, cursor, 21) }
        var first = true
        while token_ident(state, cursor) {
            if !first && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, 23) }
            first = false
            let field = try parse_c_field(d, state, cursor)
            if parse_step_bad(field) { return Ok(field) }
            let item = parse_step_value(field)
            let field_link = try add_link(d, item.cursor, item.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, field_link.store.links)
            cursor = field_link
            if token_punct(state, cursor, ",") || token_punct(state, cursor, ";") { return reject_parse(d, state, cursor, 23) }
        }
        let close = try expect_punct(d, state, cursor, "}")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_cursor(close)
    }
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 62, name_token, class_token.source, class_token.start, end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_c_field(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let name = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 8) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let type_step = try parse_type(d, state, cursor)
    if parse_step_bad(type_step) { return Ok(type_step) }
    let value = parse_step_value(type_step)
    let type_node = __s0_buffer_get(SyntaxRec, value.cursor.store.nodes, value.node - 1)
    let linked = try add_link(d, value.cursor, value.node, 0)
    var children: U64 = __s0_buffer_len(SyntaxLinkRec, linked.store.links)
    var end = type_node.end
    cursor = linked
    if token_punct(state, cursor, "=") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let spelling = try parse_c_spelling(d, state, cursor)
        if parse_step_bad(spelling) { return Ok(spelling) }
        let item = parse_step_value(spelling)
        let spelling_link = try add_link(d, item.cursor, item.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, spelling_link.store.links)
        let spelling_node = __s0_buffer_get(SyntaxRec, spelling_link.store.nodes, item.node - 1)
        end = spelling_node.end
        cursor = spelling_link
    }
    let node = try add_syntax(d, cursor, 65, initial.token + 1, name.source, name.start, end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_c_fn_member(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let raw_token = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !(parse_token(state, cursor).kind == 1 && parse_token(state, cursor).keyword == 4) { return reject_parse(d, state, cursor, 21) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    let name_token = cursor.token + 1
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var children: U64 = 0
    if token_punct(state, cursor, "=") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let spelling = try parse_c_spelling(d, state, cursor)
        if parse_step_bad(spelling) { return Ok(spelling) }
        let value = parse_step_value(spelling)
        let linked = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, linked.store.links)
        cursor = linked
    }
    if !token_punct(state, cursor, "(") { return reject_parse(d, state, cursor, 11) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            let param_token = cursor.token + 1
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 8) }
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let type_step = try parse_type(d, state, cursor)
            if parse_step_bad(type_step) { return Ok(type_step) }
            let value = parse_step_value(type_step)
            let type_cursor = try add_link(d, value.cursor, value.node, 0)
            let param_node = try add_syntax(d, type_cursor, 13, param_token, param.source, param.start, param.end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, type_cursor.store.links))
            let param_link = try add_link(d, param_node.cursor, param_node.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, param_link.store.links)
            cursor = param_link
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, ")")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    if !token_punct(state, cursor, "->") { return reject_parse(d, state, cursor, 14) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let result = try parse_type(d, state, cursor)
    if parse_step_bad(result) { return Ok(result) }
    let result_value = parse_step_value(result)
    let result_link = try add_link(d, result_value.cursor, result_value.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, result_link.store.links)
    cursor = result_link
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 63, name_token, raw_token.source, raw_token.start, end, name.start, name.end, children)
    return Ok(Parsed(node))
}

// `callback type Name = "spelling" (parameter: Type, ...) -> Result` binds a
// C function-pointer typedef. The spelling is the chain tail and the result is
// the chain head, so the shared binding-spelling and backward child walks
// apply unchanged.
fn parse_c_callback_member(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let callback_token = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !(parse_token(state, cursor).kind == 1 && parse_token(state, cursor).keyword == 2) { return reject_parse(d, state, cursor, 31) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    let name_token = cursor.token + 1
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_punct(state, cursor, "=") { return reject_parse(d, state, cursor, 8) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let spelling = try parse_c_spelling(d, state, cursor)
    if parse_step_bad(spelling) { return Ok(spelling) }
    let spelling_value = parse_step_value(spelling)
    let spelling_link = try add_link(d, spelling_value.cursor, spelling_value.node, 0)
    var children: U64 = __s0_buffer_len(SyntaxLinkRec, spelling_link.store.links)
    cursor = spelling_link
    if !token_punct(state, cursor, "(") { return reject_parse(d, state, cursor, 11) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            let param_token = cursor.token + 1
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 8) }
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let type_step = try parse_type(d, state, cursor)
            if parse_step_bad(type_step) { return Ok(type_step) }
            let value = parse_step_value(type_step)
            let type_cursor = try add_link(d, value.cursor, value.node, 0)
            let param_node = try add_syntax(d, type_cursor, 13, param_token, param.source, param.start, param.end, param.start, param.end, __s0_buffer_len(SyntaxLinkRec, type_cursor.store.links))
            let param_link = try add_link(d, param_node.cursor, param_node.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, param_link.store.links)
            cursor = param_link
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
    }
    let close = try expect_punct(d, state, cursor, ")")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_cursor(close)
    if !token_punct(state, cursor, "->") { return reject_parse(d, state, cursor, 14) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let result = try parse_type(d, state, cursor)
    if parse_step_bad(result) { return Ok(result) }
    let result_value = parse_step_value(result)
    let result_link = try add_link(d, result_value.cursor, result_value.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, result_link.store.links)
    cursor = result_link
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 66, name_token, callback_token.source, callback_token.start, end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_c_const_member(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let const_token = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    let name_token = cursor.token + 1
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var children: U64 = 0
    var end = name.end
    if token_punct(state, cursor, "=") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let spelling = try parse_c_spelling(d, state, cursor)
        if parse_step_bad(spelling) { return Ok(spelling) }
        let value = parse_step_value(spelling)
        let spelling_link = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, spelling_link.store.links)
        let spelling_node = __s0_buffer_get(SyntaxRec, spelling_link.store.nodes, value.node - 1)
        end = spelling_node.end
        cursor = spelling_link
    }
    if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 8) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let type_step = try parse_type(d, state, cursor)
    if parse_step_bad(type_step) { return Ok(type_step) }
    let value = parse_step_value(type_step)
    let type_node = __s0_buffer_get(SyntaxRec, value.cursor.store.nodes, value.node - 1)
    let type_link = try add_link(d, value.cursor, value.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, type_link.store.links)
    let node = try add_syntax(d, type_link, 64, name_token, const_token.source, const_token.start, type_node.end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_module_import(d: Domain, state: State, initial: ParseCursor, public: Bool) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    let path = try parse_module_path(d, state, ParseCursor(token: initial.token + 1, store: initial.store))
    if parse_step_bad(path) { return Ok(path) }
    let path_value = parse_step_value(path)
    let path_node = __s0_buffer_get(SyntaxRec, path_value.cursor.store.nodes, path_value.node - 1)
    var cursor = try add_link(d, path_value.cursor, path_value.node, 0)
    var children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    var end = path_node.end
    if parse_token(state, cursor).keyword == 22 {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
        let alias = parse_token(state, cursor)
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let alias_node = try add_syntax(d, cursor, 44, cursor.token, alias.source, alias.start, alias.end, alias.start, alias.end, 0)
        cursor = try add_link(d, alias_node.cursor, alias_node.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        end = alias.end
    } else {
        if token_punct(state, cursor, "\{") {
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if token_punct(state, cursor, "}") { return reject_parse(d, state, cursor, 3) }
            var more = true
            while more {
                if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
                let selected = parse_token(state, cursor)
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                let selected_node = try add_syntax(d, cursor, 43, cursor.token, selected.source, selected.start, selected.end, selected.start, selected.end, 0)
                cursor = try add_link(d, selected_node.cursor, selected_node.node, children)
                children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                if token_punct(state, cursor, ",") {
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                    if token_punct(state, cursor, "}") { more = false }
                } else { more = false }
            }
            let close = try expect_punct(d, state, cursor, "}")
            if parse_step_bad(close) { return Ok(close) }
            cursor = parse_step_cursor(close)
            end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
        }
    }
    var kind: U64 = 41
    if public { kind = 42 }
    let node = try add_syntax(d, cursor, kind, initial.token + 1, start.source, start.start, end, path_node.name_start, path_node.name_end, children)
    return Ok(Parsed(node))
}

fn parse_public_decl(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    let next = ParseCursor(token: initial.token + 1, store: initial.store)
    if parse_token(state, next).keyword == 1 {
        let third = ParseCursor(token: next.token + 1, store: next.store)
        let binding = token_ident(state, third) && token_text(state, parse_token(state, third), "c") && parse_token(state, ParseCursor(token: third.token + 1, store: third.store)).kind == 4
        if binding { return reject_parse(d, state, next, 22) }
        return parse_module_import(d, state, next, true)
    }
    let declaration = try parse_decl(d, state, next)
    if parse_step_bad(declaration) { return Ok(declaration) }
    let value = parse_step_value(declaration)
    let declared = __s0_buffer_get(SyntaxRec, value.cursor.store.nodes, value.node - 1)
    if declared.kind != 2 && declared.kind != 3 && declared.kind != 12 && declared.kind != 50 { return reject_parse(d, state, next, 1) }
    let linked = try add_link(d, value.cursor, value.node, 0)
    let node = try add_syntax(d, linked, 45, initial.token + 1, start.source, start.start, declared.end, declared.name_start, declared.name_end, __s0_buffer_len(SyntaxLinkRec, linked.store.links))
    return Ok(Parsed(node))
}

fn parse_decl(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    if start.keyword == 32 { return parse_export_c_fn(d, state, initial) }
    if start.keyword == 20 { return parse_module_decl(d, state, initial) }
    if start.keyword == 21 { return parse_public_decl(d, state, initial) }
    if start.keyword == 25 { return parse_impl(d, state, initial) }
    if start.keyword == 27 { return parse_trait(d, state, initial) }
    let is_import = start.keyword == 1
    let is_struct = start.keyword == 2
    let is_enum = start.keyword == 3
    if start.keyword == 4 { return parse_function(d, state, initial) }
    if !is_import && !is_struct && !is_enum { return reject_parse(d, state, initial, 1) }
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if is_import {
        let c_binding = token_ident(state, cursor) && token_text(state, parse_token(state, cursor), "c") && parse_token(state, ParseCursor(token: cursor.token + 1, store: cursor.store)).kind == 4
        if c_binding {
            let block = try parse_binding_block(d, state, initial)
            if parse_step_bad(block) { return Ok(block) }
            return Ok(block)
        }
        let c_import = token_ident(state, cursor) && token_text(state, parse_token(state, cursor), "c") && token_ident(state, ParseCursor(token: cursor.token + 1, store: cursor.store)) && token_punct(state, ParseCursor(token: cursor.token + 2, store: cursor.store), ":")
        if !c_import { return parse_module_import(d, state, initial, false) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
        let name = parse_token(state, cursor)
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let colon = try expect_punct(d, state, cursor, ":")
        if parse_step_bad(colon) { return Ok(colon) }
        cursor = parse_step_value(colon).cursor
        if parse_token(state, cursor).keyword != 4 { return reject_parse(d, state, cursor, 4) }
        let fn_token = parse_token(state, cursor)
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        let open = try expect_punct(d, state, cursor, "(")
        if parse_step_bad(open) { return Ok(open) }
        cursor = parse_step_value(open).cursor
        var children: U64 = 0
        if !token_punct(state, cursor, ")") {
            var more = true
            while more {
                let param = try parse_type(d, state, cursor)
                if parse_step_bad(param) { return Ok(param) }
                let value = parse_step_value(param)
                cursor = try add_link(d, value.cursor, value.node, children)
                children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
                if token_punct(state, cursor, ",") {
                    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                    if token_punct(state, cursor, ")") { more = false }
                } else { more = false }
            }
        }
        let close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_value(close).cursor
        let arrow = try expect_punct(d, state, cursor, "->")
        if parse_step_bad(arrow) { return Ok(arrow) }
        cursor = parse_step_value(arrow).cursor
        let result = try parse_type(d, state, cursor)
        if parse_step_bad(result) { return Ok(result) }
        let result_value = parse_step_value(result)
        cursor = try add_link(d, result_value.cursor, result_value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let sig = try add_syntax(d, cursor, 10, initial.token + 5, fn_token.source, fn_token.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, 0, 0, children)
        cursor = try add_link(d, sig.cursor, sig.node, 0)
        let decl = try add_syntax(d, cursor, 1, initial.token + 1, start.source, start.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        return Ok(Parsed(decl))
    }
    if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
    let name = parse_token(state, cursor)
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var children: U64 = 0
    if token_punct(state, cursor, "(") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        var more = true
        while more {
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            let param = parse_token(state, cursor)
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let typed = try parse_type_param(d, state, param, cursor)
            if parse_step_bad(typed) { return Ok(typed) }
            let pnode = parse_step_value(typed)
            cursor = try add_link(d, pnode.cursor, pnode.node, children)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            if token_punct(state, cursor, ",") {
                cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
                if token_punct(state, cursor, ")") { more = false }
            } else { more = false }
        }
        let close = try expect_punct(d, state, cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        cursor = parse_step_value(close).cursor
    }
    if parse_token(state, cursor).keyword == 28 { return reject_parse(d, state, cursor, 24) }
    let open = try expect_punct(d, state, cursor, "\{")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_value(open).cursor
    while token_ident(state, cursor) || (!is_enum && parse_token(state, cursor).keyword == 21) {
        var item_kind: U64 = 8
        if is_enum { item_kind = 9 }
        if !is_enum && parse_token(state, cursor).keyword == 21 {
            // A `pub` record field is visible outside its module for
            // construction. Fields default to module-private.
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
            item_kind = 62
        }
        let payload = is_enum && token_punct(state, ParseCursor(token: cursor.token + 1, store: cursor.store), "(")
        let item = try parse_named_item(d, state, cursor, item_kind, payload)
        if parse_step_bad(item) { return Ok(item) }
        let value = parse_step_value(item)
        cursor = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if token_punct(state, cursor, ",") || token_punct(state, cursor, ";") { return reject_parse(d, state, cursor, item_kind) }
        if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) { return reject_parse(d, state, cursor, item_kind) }
    }
    let close = try expect_punct(d, state, cursor, "}")
    if parse_step_bad(close) { return Ok(close) }
    cursor = parse_step_value(close).cursor
    var decl_kind: U64 = 2
    if is_enum { decl_kind = 3 }
    let node = try add_syntax(d, cursor, decl_kind, initial.token + 1, start.source, start.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, name.start, name.end, children)
    return Ok(Parsed(node))
}

fn parse_source_tokens(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    var cursor = initial
    while parse_token(state, cursor).kind != 0 {
        let decl = try parse_decl(d, state, cursor)
        if parse_step_bad(decl) { return Ok(decl) }
        let value = parse_step_value(decl)
        cursor = try add_root(d, value.cursor, value.node)
        if parse_token(state, cursor).kind != 0 && !line_break_before(state, cursor) {
            return reject_parse(d, state, cursor, 7)
        }
    }
    return Ok(Parsed(ParseValue(cursor: ParseCursor(token: cursor.token + 1, store: cursor.store), node: 0)))
}

// Sources are lexed and parsed one at a time in canonical host order so the
// earliest source failure wins even when its phase differs from a later one.
fn parse_sources(d: Domain, initial: State, store: ParseStore) -> Result(ParseResult, __s0_Error) {
    var state = initial
    var cursor = ParseCursor(token: 0, store: store)
    var source: U64 = 0
    while source < __s0_buffer_len(SourceRec, state.sources) {
        let lexed = try lex_source(d, state, source)
        if lex_result_failed(lexed) {
            let failed = lex_result_state(lexed)
            return Ok(ParseLexBad(ParseOutput(state: failed, store: cursor.store)))
        }
        state = lex_result_state(lexed)
        // Bindings are append-only across sources so their source ids stay
        // comparable, but a source's lexical scope starts after every binding
        // parsed from an earlier source. Starting the visible prefix at the
        // buffer end keeps an earlier module's locals from hiding this
        // source's parameters and locals that share a name with an import
        // namespace (`iter.next()` where `iter: I` shadows `core.iter`).
        cursor = ParseCursor(token: cursor.token, store: parse_restore_bindings(cursor.store, __s0_buffer_len(ParseBindingRec, cursor.store.bindings)))
        let parsed = try parse_source_tokens(d, state, cursor)
        if parse_step_bad(parsed) {
            return Ok(ParseBad(ParseOutput(state: state, store: parse_step_cursor(parsed).store)))
        }
        cursor = parse_step_cursor(parsed)
        source = source + 1
    }
    return Ok(ParseGood(ParseOutput(state: state, store: cursor.store)))
}

fn emit_parse_manifest(state: State, store: ParseStore) -> Bool {
    if !out_string("ALDER-PARSER-MANIFEST 1\n") || !emit_sources(state) { return false }
    if !out_string("T ") || !out_u64(__s0_buffer_len(TokenRec, state.tokens)) || !out(10) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, store.roots) {
        if !out_string("R ") || !out_u64(at) || !out(32) || !out_u64(__s0_buffer_get(U64, store.roots, at)) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SyntaxRec, store.nodes) {
        let node = __s0_buffer_get(SyntaxRec, store.nodes, at)
        let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
        if !out_string("N ") || !out_u64(at + 1) || !out(32) || !out_u64(node.kind) || !out(32) || !out_u64(node.token) || !out(32) || !out_u64(token.source) || !out(32) || !out_u64(token.start) || !out(32) || !out_u64(token.end) || !out(32) || !out_path(state, node.source) || !out(32) || !out_u64(node.start) || !out(32) || !out_u64(node.end) || !out(32) || !out_u64(node.name_start) || !out(32) || !out_u64(node.name_end) || !out(32) || !out_u64(node.children) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SyntaxLinkRec, store.links) {
        let link = __s0_buffer_get(SyntaxLinkRec, store.links, at)
        if !out_string("L ") || !out_u64(at + 1) || !out(32) || !out_u64(link.node) || !out(32) || !out_u64(link.next) || !out(10) { return false }
        at = at + 1
    }
    if __s0_buffer_len(ParseDiagRec, store.diagnostics) != 0 {
        let diag = __s0_buffer_get(ParseDiagRec, store.diagnostics, 0)
        if !out_string("D SYN0001 ") || !out_u64(diag.kind) || !out(32) || !out_path(state, diag.source) || !out(32) || !out_u64(diag.start) || !out(32) || !out_u64(diag.end) || !out(10) { return false }
    }
    return out_string("END\n")
}
