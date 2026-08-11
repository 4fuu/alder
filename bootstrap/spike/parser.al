fn alpha(byte: U8) -> Bool {
    return (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
}

fn digit(byte: U8) -> Bool { return byte >= 48 && byte <= 57 }
fn ident(byte: U8) -> Bool { return alpha(byte) || digit(byte) }
fn space(byte: U8) -> Bool { return byte == 32 || byte == 9 || byte == 13 }

fn skip_space(text: __s0_Buffer(U8), at: U64, end: U64) -> U64 {
    if at == end { return at }
    if !space(__s0_buffer_get(U8, text, at)) { return at }
    return skip_space(text, at + 1, end)
}

fn scan_ident(text: __s0_Buffer(U8), at: U64, end: U64) -> U64 {
    if at == end { return at }
    if !ident(__s0_buffer_get(U8, text, at)) { return at }
    return scan_ident(text, at + 1, end)
}

fn bytes_equal(bytes: __s0_Buffer(U8), a: U64, ae: U64, b: U64, be: U64) -> Bool {
    if ae - a != be - b { return false }
    return bytes_equal_at(bytes, a, ae, b)
}

fn bytes_equal_at(bytes: __s0_Buffer(U8), a: U64, ae: U64, b: U64) -> Bool {
    if a == ae { return true }
    if __s0_buffer_get(U8, bytes, a) != __s0_buffer_get(U8, bytes, b) { return false }
    return bytes_equal_at(bytes, a + 1, ae, b + 1)
}

fn copy_name(d: Domain, names: __s0_Buffer(U8), text: __s0_Buffer(U8), at: U64, end: U64) -> Result(__s0_Buffer(U8), __s0_Error) {
    if at == end { return Ok(names) }
    let next = try __s0_buffer_append(U8, d, names, __s0_buffer_get(U8, text, at))
    return copy_name(d, next, text, at + 1, end)
}

fn add_diag(d: Domain, state: State, code: U64, source: U64, start: U64, end: U64, rs: U64, rb: U64, re: U64) -> Result(State, __s0_Error) {
    let item = DiagRec(code: code, source: source, start: start, end: end, related_source: rs, related_start: rb, related_end: re)
    let diags = try __s0_buffer_append(DiagRec, d, state.diags, item)
    return Ok(State(paths: state.paths, texts: state.texts, names: state.names, sources: state.sources, decls: state.decls, uses: state.uses, diags: diags))
}

fn add_statement(d: Domain, state: State, source: U64, line_start: U64, line_end: U64) -> Result(State, __s0_Error) {
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    let at = skip_space(state.texts, rec.text_start + line_start, rec.text_start + line_end)
    let end = rec.text_start + line_end
    if at == end { return Ok(state) }
    let keyword_end = scan_ident(state.texts, at, end)
    let name_at = skip_space(state.texts, keyword_end, end)
    if keyword_end == at || name_at == keyword_end || name_at == end || !alpha(__s0_buffer_get(U8, state.texts, name_at)) {
        return add_diag(d, state, 1, source, at - rec.text_start, line_end, 0, 0, 0)
    }
    let name_end = scan_ident(state.texts, name_at, end)
    if skip_space(state.texts, name_end, end) != end {
        return add_diag(d, state, 1, source, name_end - rec.text_start, line_end, 0, 0, 0)
    }
    let is_def = keyword_end - at == 3 && __s0_buffer_get(U8, state.texts, at) == 100 && __s0_buffer_get(U8, state.texts, at + 1) == 101 && __s0_buffer_get(U8, state.texts, at + 2) == 102
    let is_use = keyword_end - at == 3 && __s0_buffer_get(U8, state.texts, at) == 117 && __s0_buffer_get(U8, state.texts, at + 1) == 115 && __s0_buffer_get(U8, state.texts, at + 2) == 101
    if !is_def && !is_use {
        return add_diag(d, state, 1, source, at - rec.text_start, keyword_end - rec.text_start, 0, 0, 0)
    }
    let names_start = __s0_buffer_len(U8, state.names)
    let names = try copy_name(d, state.names, state.texts, name_at, name_end)
    let names_end = __s0_buffer_len(U8, names)
    if is_def {
        let item = DeclRec(source: source, start: name_at - rec.text_start, end: name_end - rec.text_start, name_start: names_start, name_end: names_end)
        let decls = try __s0_buffer_append(DeclRec, d, state.decls, item)
        return Ok(State(paths: state.paths, texts: state.texts, names: names, sources: state.sources, decls: decls, uses: state.uses, diags: state.diags))
    }
    let item = UseRec(source: source, start: name_at - rec.text_start, end: name_end - rec.text_start, name_start: names_start, name_end: names_end)
    let uses = try __s0_buffer_append(UseRec, d, state.uses, item)
    return Ok(State(paths: state.paths, texts: state.texts, names: names, sources: state.sources, decls: state.decls, uses: uses, diags: state.diags))
}

fn line_is_begin(text: __s0_Buffer(U8), at: U64, end: U64) -> Bool {
    return end - at == 5 && __s0_buffer_get(U8, text, at) == 98 && __s0_buffer_get(U8, text, at + 1) == 101 && __s0_buffer_get(U8, text, at + 2) == 103 && __s0_buffer_get(U8, text, at + 3) == 105 && __s0_buffer_get(U8, text, at + 4) == 110
}

fn line_is_end(text: __s0_Buffer(U8), at: U64, end: U64) -> Bool {
    return end - at == 3 && __s0_buffer_get(U8, text, at) == 101 && __s0_buffer_get(U8, text, at + 1) == 110 && __s0_buffer_get(U8, text, at + 2) == 100
}

fn parse_line_and_continue(d: Domain, state: State, source: U64, line: U64, line_end: U64, next_at: U64, end: U64, depth: U64) -> Result(State, __s0_Error) {
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    let absolute_end = rec.text_start + line_end
    let at = skip_space(state.texts, rec.text_start + line, absolute_end)
    let trimmed_end = trim_space_end(state.texts, at, absolute_end)
    if at == trimmed_end { return parse_lines(d, state, source, next_at, next_at, end, depth) }
    if line_is_begin(state.texts, at, trimmed_end) {
        return parse_lines(d, state, source, next_at, next_at, end, depth + 1)
    }
    if line_is_end(state.texts, at, trimmed_end) {
        if depth == 0 {
            let diagnosed = try add_diag(d, state, 4, source, at - rec.text_start, trimmed_end - rec.text_start, 0, 0, 0)
            return parse_lines(d, diagnosed, source, next_at, next_at, end, depth)
        }
        return parse_lines(d, state, source, next_at, next_at, end, depth - 1)
    }
    let parsed = try add_statement(d, state, source, line, line_end)
    return parse_lines(d, parsed, source, next_at, next_at, end, depth)
}

fn trim_space_end(text: __s0_Buffer(U8), start: U64, end: U64) -> U64 {
    if start == end { return end }
    if !space(__s0_buffer_get(U8, text, end - 1)) { return end }
    return trim_space_end(text, start, end - 1)
}

fn parse_lines(d: Domain, state: State, source: U64, at: U64, line: U64, end: U64, depth: U64) -> Result(State, __s0_Error) {
    if at == end {
        if line != end { return parse_line_and_continue(d, state, source, line, end, end, end, depth) }
        if depth != 0 { return add_diag(d, state, 4, source, end, end, 0, 0, 0) }
        return Ok(state)
    }
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    if __s0_buffer_get(U8, state.texts, rec.text_start + at) == 10 {
        return parse_line_and_continue(d, state, source, line, at, at + 1, end, depth)
    }
    return parse_lines(d, state, source, at + 1, line, end, depth)
}

fn parse_sources(d: Domain, state: State, source: U64) -> Result(State, __s0_Error) {
    if source == __s0_buffer_len(SourceRec, state.sources) { return Ok(state) }
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    let next = try parse_lines(d, state, source, 0, 0, rec.text_end - rec.text_start, 0)
    return parse_sources(d, next, source + 1)
}

fn find_decl(state: State, ns: U64, ne: U64, at: U64) -> U64 {
    if at == __s0_buffer_len(DeclRec, state.decls) { return at }
    let item = __s0_buffer_get(DeclRec, state.decls, at)
    if bytes_equal(state.names, ns, ne, item.name_start, item.name_end) { return at }
    return find_decl(state, ns, ne, at + 1)
}

fn resolve_decls(d: Domain, state: State, at: U64) -> Result(State, __s0_Error) {
    if at == __s0_buffer_len(DeclRec, state.decls) { return Ok(state) }
    let item = __s0_buffer_get(DeclRec, state.decls, at)
    let first = find_decl(state, item.name_start, item.name_end, 0)
    if first != at {
        let prior = __s0_buffer_get(DeclRec, state.decls, first)
        let next = try add_diag(d, state, 2, item.source, item.start, item.end, prior.source, prior.start, prior.end)
        return resolve_decls(d, next, at + 1)
    }
    return resolve_decls(d, state, at + 1)
}

fn resolve_uses(d: Domain, state: State, at: U64) -> Result(State, __s0_Error) {
    if at == __s0_buffer_len(UseRec, state.uses) { return Ok(state) }
    let item = __s0_buffer_get(UseRec, state.uses, at)
    let target = find_decl(state, item.name_start, item.name_end, 0)
    if target == __s0_buffer_len(DeclRec, state.decls) {
        let next = try add_diag(d, state, 3, item.source, item.start, item.end, 0, 0, 0)
        return resolve_uses(d, next, at + 1)
    }
    return resolve_uses(d, state, at + 1)
}
