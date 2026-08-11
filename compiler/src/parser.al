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

fn token_text(state: State, token: TokenRec, text: String) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, token.source)
    return source_word(state, source, token.start, token.end, text)
}

fn token_punct(state: State, cursor: ParseCursor, text: String) -> Bool {
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

fn expect_punct(d: Domain, state: State, cursor: ParseCursor, text: String) -> Result(ParseStep, __s0_Error) {
    if !token_punct(state, cursor, text) { return reject_parse(d, state, cursor, 4) }
    return Ok(Parsed(ParseValue(cursor: ParseCursor(token: cursor.token + 1, store: cursor.store), node: 0)))
}

fn parse_type(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let first = parse_token(state, initial)
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
    if !token_punct(state, cursor, "(") {
        let node = try add_syntax(d, cursor, 4, initial.token + 1, first.source, first.start, first.end, first.start, first.end, 0)
        return Ok(Parsed(node))
    }
    cursor = ParseCursor(token: cursor.token + 1, store: cursor.store)
    var children: U64 = 0
    if !token_punct(state, cursor, ")") {
        var more = true
        while more {
            let arg = try parse_type(d, state, cursor)
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

fn parse_decl(d: Domain, state: State, initial: ParseCursor) -> Result(ParseStep, __s0_Error) {
    let start = parse_token(state, initial)
    if start.keyword == 4 { return reject_parse(d, state, initial, 2) }
    let is_import = start.keyword == 1
    let is_struct = start.keyword == 2
    let is_enum = start.keyword == 3
    if !is_import && !is_struct && !is_enum { return reject_parse(d, state, initial, 1) }
    var cursor = ParseCursor(token: initial.token + 1, store: initial.store)
    if is_import {
        if !token_ident(state, cursor) || !token_text(state, parse_token(state, cursor), "c") { return reject_parse(d, state, cursor, 4) }
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
            let pnode = try add_syntax(d, cursor, 7, cursor.token - 2, param.source, param.start, param.end, param.start, param.end, 0)
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
