type ParseStore {
    nodes: __s0_Buffer(SyntaxRec)
    links: __s0_Buffer(SyntaxLinkRec)
    roots: __s0_Buffer(U64)
    diagnostics: __s0_Buffer(ParseDiagRec)
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
    let store = ParseStore(nodes: cursor.store.nodes, links: cursor.store.links, roots: cursor.store.roots, diagnostics: diagnostics)
    return Ok(Rejected(ParseCursor(token: cursor.token, store: store)))
}

fn add_syntax(d: Domain, cursor: ParseCursor, kind: U64, token: U64, source: U64, start: U64, end: U64, name_start: U64, name_end: U64, children: U64) -> Result(ParseValue, __s0_Error) {
    let rec = SyntaxRec(kind: kind, token: token, source: source, start: start, end: end, name_start: name_start, name_end: name_end, children: children)
    let nodes = try __s0_buffer_append(SyntaxRec, d, cursor.store.nodes, rec)
    let store = ParseStore(nodes: nodes, links: cursor.store.links, roots: cursor.store.roots, diagnostics: cursor.store.diagnostics)
    return Ok(ParseValue(cursor: ParseCursor(token: cursor.token, store: store), node: __s0_buffer_len(SyntaxRec, nodes)))
}

fn add_link(d: Domain, cursor: ParseCursor, node: U64, next: U64) -> Result(ParseCursor, __s0_Error) {
    let links = try __s0_buffer_append(SyntaxLinkRec, d, cursor.store.links, SyntaxLinkRec(node: node, next: next))
    let store = ParseStore(nodes: cursor.store.nodes, links: links, roots: cursor.store.roots, diagnostics: cursor.store.diagnostics)
    return Ok(ParseCursor(token: cursor.token, store: store))
}

fn add_root(d: Domain, cursor: ParseCursor, node: U64) -> Result(ParseCursor, __s0_Error) {
    let roots = try __s0_buffer_append(U64, d, cursor.store.roots, node)
    let store = ParseStore(nodes: cursor.store.nodes, links: cursor.store.links, roots: roots, diagnostics: cursor.store.diagnostics)
    return Ok(ParseCursor(token: cursor.token, store: store))
}

fn expect_punct(d: Domain, state: State, cursor: ParseCursor, text: __s0_String) -> Result(ParseStep, __s0_Error) {
    if !token_punct(state, cursor, text) { return reject_parse(d, state, cursor, 4) }
    return Ok(Parsed(ParseValue(cursor: ParseCursor(token: cursor.token + 1, store: cursor.store), node: 0)))
}

fn parse_type(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let first = parse_token(state, initial)
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
    let node = try add_syntax(d, cursor, 6, initial.token + 1, first.source, first.start, end, first.start, first.end, children)
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
    if token_punct(state, cursor, "<<") || token_punct(state, cursor, ">>") { return 5 }
    if token_punct(state, cursor, "+") || token_punct(state, cursor, "-") { return 6 }
    if token_punct(state, cursor, "*") || token_punct(state, cursor, "/") || token_punct(state, cursor, "%") { return 7 }
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
            cursor = try add_link(d, binding_node.cursor, binding_node.node, 0)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        }
    }
    let arrow = try expect_punct(d, state, cursor, "=>")
    if parse_step_bad(arrow) { return Ok(arrow) }
    let body = try parse_expression(d, state, parse_step_cursor(arrow), depth)
    if parse_step_bad(body) { return Ok(body) }
    let value = parse_step_value(body)
    cursor = try add_link(d, value.cursor, value.node, children)
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let arm = try add_syntax(d, cursor, 38, initial.token + 1, pattern.source, pattern.start, end, name_start, name_end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
    return Ok(Parsed(arm))
}

fn parse_match(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    let value_cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !expression_line_ok(state, value_cursor, depth) { return reject_parse(d, state, value_cursor, 13) }
    let scrutinee = try parse_unary(d, state, value_cursor, depth)
    if parse_step_bad(scrutinee) { return Ok(scrutinee) }
    let sv = parse_step_value(scrutinee)
    let open = try expect_punct(d, state, sv.cursor, "{")
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

fn parse_unsafe_c(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if !token_ident(state, cursor) || !token_text(state, parse_token(state, cursor), "c") { return reject_parse(d, state, cursor, 17) }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let open = try expect_punct(d, state, cursor, "{")
    if parse_step_bad(open) { return Ok(open) }
    let expr = try parse_expression(d, state, parse_step_cursor(open), depth + 1)
    if parse_step_bad(expr) { return Ok(expr) }
    let value = parse_step_value(expr)
    let rec = __s0_buffer_get(SyntaxRec, value.cursor.store.nodes, value.node - 1)
    if rec.kind != 27 { return reject_parse(d, state, initial, 18) }
    if !token_punct(state, value.cursor, "}") { return reject_parse(d, state, value.cursor, 18) }
    let close = parse_token(state, value.cursor)
    cursor = try add_link(d, ParseCursor(token: value.cursor.token + 1, store: value.cursor.store), value.node, 0)
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

fn parse_primary(d: Domain, state: State, initial: ParseCursor, depth: U64) -> Result(ParseStep, __s0_Error) {
    let token = parse_token(state, initial)
    if depth > parse_depth_limit() { return parse_depth_reject(d, state, initial) }
    if token.keyword == 13 { return parse_match(d, state, initial, depth) }
    if token.keyword == 19 { return parse_unsafe_c(d, state, initial, depth) }
    if token_punct(state, initial, "[") { return parse_array_literal(d, state, initial, depth) }
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
        let inside = try parse_expression(d, state, ParseCursor(token: initial.token + 1, store: initial.store), depth + 1)
        if parse_step_bad(inside) { return Ok(inside) }
        let value = parse_step_value(inside)
        let close = try expect_punct(d, state, value.cursor, ")")
        if parse_step_bad(close) { return Ok(close) }
        return Ok(Parsed(ParseValue(cursor: parse_step_cursor(close), node: value.node)))
    }
    return reject_parse(d, state, initial, 12)
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
                let base = __s0_buffer_get(SyntaxRec, cursor.store.nodes, base_link.node - 1)
                let source = __s0_buffer_get(SourceRec, state.sources, base.source)
                var associated = false
                if base.kind == 24 {
                    let first = text_byte(state, source, base.name_start)
                    associated = first >= 65 && first <= 90
                    var root_at: U64 = 0
                    while root_at < __s0_buffer_len(U64, cursor.store.roots) {
                        let root = __s0_buffer_get(SyntaxRec, cursor.store.nodes, __s0_buffer_get(U64, cursor.store.roots, root_at) - 1)
                        if root.source == base.source && (root.kind == 41 || root.kind == 42) {
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
                                if equal { associated = true }
                            }
                        }
                        root_at = root_at + 1
                    }
                }
                if !associated {
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
                if !token_ident(state, name_cursor) { return reject_parse(d, state, name_cursor, 3) }
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
    if token_punct(state, initial, "-") || token_punct(state, initial, "!") {
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

fn assignment_target(store: ParseStore, node_id: U64) -> Bool {
    let node = __s0_buffer_get(SyntaxRec, store.nodes, node_id - 1)
    if node.kind == 24 { return true }
    if node.kind != 29 && node.kind != 30 { return false }
    let head = __s0_buffer_get(SyntaxLinkRec, store.links, node.children - 1)
    var base_link = head
    if node.kind == 30 { base_link = __s0_buffer_get(SyntaxLinkRec, store.links, head.next - 1) }
    let base = __s0_buffer_get(SyntaxRec, store.nodes, base_link.node - 1)
    if base.kind == 24 { return true }
    if node.kind != 29 || base.kind != 30 { return false }
    let index_head = __s0_buffer_get(SyntaxLinkRec, store.links, base.children - 1)
    let index_base = __s0_buffer_get(SyntaxLinkRec, store.links, index_head.next - 1)
    return __s0_buffer_get(SyntaxRec, store.nodes, index_base.node - 1).kind == 24
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
            let alternative = try parse_block(d, state, ParseCursor(token: cursor.token + 1, store: cursor.store))
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
        let body = try parse_block(d, state, sv.cursor)
        if parse_step_bad(body) { return Ok(body) }
        let bv = parse_step_value(body)
        cursor = try add_link(d, bv.cursor, sv.node, 0)
        let children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        cursor = try add_link(d, cursor, bv.node, children)
        let node = try add_syntax(d, cursor, 34, initial.token + 1, start.source, start.start, __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1).end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
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
        if parse_token(state, cursor).keyword != 15 { return reject_parse(d, state, cursor, 4) }
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        if !expression_line_ok(state, cursor, 0) { return reject_parse(d, state, cursor, 13) }
        if !token_ident(state, cursor) { return reject_parse(d, state, cursor, 3) }
        let cleanup = parse_token(state, cursor)
        let cleanup_node = try add_syntax(d, ParseCursor(token: cursor.token + 1, store: cursor.store), 24, cursor.token + 1, cleanup.source, cleanup.start, cleanup.end, cleanup.start, cleanup.end, 0)
        cursor = try add_link(d, cleanup_node.cursor, ev.node, 0)
        let children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        cursor = try add_link(d, cursor, cleanup_node.node, children)
        let node = try add_syntax(d, cursor, 35, initial.token + 1, start.source, start.start, cleanup.end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
        return Ok(Parsed(node))
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
        return Ok(Parsed(node))
    }
    if start.keyword == 12 {
        var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
        var children: U64 = 0
        var end = start.end
        if !token_punct(state, cursor, "}") && !line_break_before(state, cursor) {
            let expr = try parse_expression(d, state, cursor, 0)
            if parse_step_bad(expr) { return Ok(expr) }
            let ev = parse_step_value(expr)
            cursor = try add_link(d, ev.cursor, ev.node, 0)
            children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
            end = __s0_buffer_get(SyntaxRec, cursor.store.nodes, ev.node - 1).end
        }
        let node = try add_syntax(d, cursor, 18, initial.token + 1, start.source, start.start, end, 0, 0, children)
        return Ok(Parsed(node))
    }
    if token_punct(state, initial, "{") { return parse_block(d, state, initial) }
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
    if !token_punct(state, initial, "{") { return reject_parse(d, state, initial, 4) }
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
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    let node = try add_syntax(d, cursor, 14, initial.token + 1, start.source, start.start, close.end, 0, 0, children)
    return Ok(Parsed(node))
}

// A single `where` constraint is `Param: TraitApplication + TraitApplication`.
// The constraint node names the constrained parameter and carries the trait
// application type nodes as children.
fn parse_constraint(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    if !token_ident(state, initial) { return reject_parse(d, state, initial, 3) }
    let param = parse_token(state, initial)
    let colon = try expect_punct(d, state, ParseCursor(token: initial.token + 1, store: initial.store), ":")
    if parse_step_bad(colon) { return Ok(colon) }
    var cursor = parse_step_cursor(colon)
    var children: U64 = 0
    var application: ParseStep = Rejected(cursor)
    application = try parse_type(d, state, cursor)
    if parse_step_bad(application) { return Ok(application) }
    let first = parse_step_value(application)
    cursor = try add_link(d, first.cursor, first.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    while token_punct(state, cursor, "+") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        var next: ParseStep = Rejected(cursor)
        next = try parse_type(d, state, cursor)
        if parse_step_bad(next) { return Ok(next) }
        let value = parse_step_value(next)
        cursor = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    }
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 55, initial.token + 1, param.source, param.start, end, param.start, param.end, children)
    return Ok(Parsed(node))
}

// A `where` clause is a comma-separated constraint list following a
// declaration signature or head. The returned node keeps source order.
fn parse_where(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    var children: U64 = 0
    var constraint: ParseStep = Rejected(cursor)
    constraint = try parse_constraint(d, state, cursor)
    if parse_step_bad(constraint) { return Ok(constraint) }
    let first = parse_step_value(constraint)
    cursor = try add_link(d, first.cursor, first.node, children)
    children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    while token_punct(state, cursor, ",") {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        var next: ParseStep = Rejected(cursor)
        next = try parse_constraint(d, state, cursor)
        if parse_step_bad(next) { return Ok(next) }
        let value = parse_step_value(next)
        cursor = try add_link(d, value.cursor, value.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    }
    let end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    let node = try add_syntax(d, cursor, 52, initial.token + 1, start.source, start.start, end, 0, 0, children)
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
                    pnode = try add_syntax(d, ParseCursor(token: cursor.token + 1, store: cursor.store), 7, colon_cursor.token, param.source, param.start, parse_token(state, cursor).end, param.start, param.end, 0)
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
    if parse_token(state, cursor).keyword == 28 {
        let clause = try parse_where(d, state, cursor)
        if parse_step_bad(clause) { return Ok(clause) }
        let cv = parse_step_value(clause)
        cursor = try add_link(d, cv.cursor, cv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    }
    var end = parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end
    if token_punct(state, cursor, "{") {
        let body = try parse_block(d, state, cursor)
        if parse_step_bad(body) { return Ok(body) }
        let bv = parse_step_value(body)
        cursor = try add_link(d, bv.cursor, bv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let block = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1)
        end = block.end
    }
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
            if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 4) }
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if parse_token(state, cursor).keyword != 2 { return reject_parse(d, state, cursor, 4) }
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let pnode = try add_syntax(d, cursor, 7, cursor.token - 2, param.source, param.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, param.start, param.end, 0)
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
    if parse_token(state, cursor).keyword == 28 {
        let clause = try parse_where(d, state, cursor)
        if parse_step_bad(clause) { return Ok(clause) }
        let cv = parse_step_value(clause)
        cursor = try add_link(d, cv.cursor, cv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    }
    let open = try expect_punct(d, state, cursor, "{")
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
                pnode = try add_syntax(d, ParseCursor(token: cursor.token + 1, store: cursor.store), 7, colon_cursor.token, param.source, param.start, parse_token(state, cursor).end, param.start, param.end, 0)
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
    if parse_token(state, cursor).keyword == 28 {
        let clause = try parse_where(d, state, cursor)
        if parse_step_bad(clause) { return Ok(clause) }
        let cv = parse_step_value(clause)
        cursor = try add_link(d, cv.cursor, cv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    }
    let body = try parse_block(d, state, cursor)
    if parse_step_bad(body) { return Ok(body) }
    let bv = parse_step_value(body)
    cursor = try add_link(d, bv.cursor, bv.node, children)
    let block = __s0_buffer_get(SyntaxRec, cursor.store.nodes, bv.node - 1)
    let node = try add_syntax(d, cursor, 12, initial.token + 1, start.source, start.start, block.end, name.start, name.end, __s0_buffer_len(SyntaxLinkRec, cursor.store.links))
    return Ok(Parsed(node))
}

fn parse_function(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    return parse_function_owned(d, state, initial, 0)
}

fn parse_impl(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    let owner = try parse_type(d, state, ParseCursor(token: initial.token + 1, store: initial.store))
    if parse_step_bad(owner) { return Ok(owner) }
    let owner_value = parse_step_value(owner)
    var cursor = owner_value.cursor
    // `impl Trait(Arguments) for Type { ... }` declares a trait
    // implementation; the trait application is linked first and the
    // implemented type second, so both stay reachable from the impl node.
    if parse_token(state, cursor).keyword == 10 {
        cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
        cursor = try add_link(d, cursor, owner_value.node, 0)
        var trait_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        let impl_type = try parse_type(d, state, cursor)
        if parse_step_bad(impl_type) { return Ok(impl_type) }
        let impl_value = parse_step_value(impl_type)
        cursor = try add_link(d, impl_value.cursor, impl_value.node, trait_children)
        trait_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        if parse_token(state, cursor).keyword == 28 {
            let clause = try parse_where(d, state, cursor)
            if parse_step_bad(clause) { return Ok(clause) }
            let cv = parse_step_value(clause)
            cursor = try add_link(d, cv.cursor, cv.node, trait_children)
            trait_children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
        }
        let trait_open = try expect_punct(d, state, cursor, "{")
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
    let open = try expect_punct(d, state, cursor, "{")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_cursor(open)
    cursor = try add_link(d, cursor, owner_value.node, 0)
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
        if token_punct(state, cursor, "{") {
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
    if parse_token(state, next).keyword == 1 { return parse_module_import(d, state, next, true) }
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
            if !token_punct(state, cursor, ":") { return reject_parse(d, state, cursor, 4) }
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            if parse_token(state, cursor).keyword != 2 { return reject_parse(d, state, cursor, 4) }
            cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
            let pnode = try add_syntax(d, cursor, 7, cursor.token - 2, param.source, param.start, parse_token(state, ParseCursor(token: cursor.token - 1, store: cursor.store)).end, param.start, param.end, 0)
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
    if parse_token(state, cursor).keyword == 28 {
        let clause = try parse_where(d, state, cursor)
        if parse_step_bad(clause) { return Ok(clause) }
        let cv = parse_step_value(clause)
        cursor = try add_link(d, cv.cursor, cv.node, children)
        children = __s0_buffer_len(SyntaxLinkRec, cursor.store.links)
    }
    let open = try expect_punct(d, state, cursor, "{")
    if parse_step_bad(open) { return Ok(open) }
    cursor = parse_step_value(open).cursor
    while token_ident(state, cursor) {
        let payload = is_enum && token_punct(state, ParseCursor(token: cursor.token + 1, store: cursor.store), "(")
        var item_kind: U64 = 8
        if is_enum { item_kind = 9 }
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
