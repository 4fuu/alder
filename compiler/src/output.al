fn out(byte: U8) -> Bool { return unsafe c { alderhost_stdout_byte(byte) } }

fn out_string(value: String) -> Bool {
    var at: U64 = 0
    while at < len(value) {
        if !out(value[at]) { return false }
        at = at + 1
    }
    return true
}

fn out_u64(value: U64) -> Bool {
    if value >= 10 { if !out_u64(value / 10) { return false } }
    return out_digit(value % 10)
}

fn out_digit(value: U64) -> Bool {
    if value == 0 { return out(48) }
    if value == 1 { return out(49) }
    if value == 2 { return out(50) }
    if value == 3 { return out(51) }
    if value == 4 { return out(52) }
    if value == 5 { return out(53) }
    if value == 6 { return out(54) }
    if value == 7 { return out(55) }
    if value == 8 { return out(56) }
    return out(57)
}

fn out_bytes(bytes: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if !out(__s0_buffer_get(U8, bytes, at)) { return false }
        at = at + 1
    }
    return true
}

fn out_hex_nibble(value: U8) -> Bool {
    if value == 0 { return out(48) }
    if value == 1 { return out(49) }
    if value == 2 { return out(50) }
    if value == 3 { return out(51) }
    if value == 4 { return out(52) }
    if value == 5 { return out(53) }
    if value == 6 { return out(54) }
    if value == 7 { return out(55) }
    if value == 8 { return out(56) }
    if value == 9 { return out(57) }
    if value == 10 { return out(97) }
    if value == 11 { return out(98) }
    if value == 12 { return out(99) }
    if value == 13 { return out(100) }
    if value == 14 { return out(101) }
    return out(102)
}

fn out_hex(bytes: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        let byte = __s0_buffer_get(U8, bytes, at)
        if !out_hex_nibble(byte / 16) || !out_hex_nibble(byte % 16) { return false }
        at = at + 1
    }
    return true
}

fn out_path(state: State, source: U64) -> Bool {
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    return out_bytes(state.paths, rec.path_start, rec.path_end)
}

fn emit_sources(state: State) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(SourceRec, state.sources) {
        let source = __s0_buffer_get(SourceRec, state.sources, at)
        if !out_string("S ") || !out_u64(at) || !out(32) || !out_path(state, at) || !out(32) || !out_u64(source.text_end - source.text_start) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_tokens(state: State) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(TokenRec, state.tokens) {
        let token = __s0_buffer_get(TokenRec, state.tokens, at)
        if !out_string("T ") || !out_u64(token.source) || !out(32) || !out_u64(token.kind) || !out(32) || !out_u64(token.keyword) || !out(32) || !out_u64(token.start) || !out(32) || !out_u64(token.end) || !out(32) || !out_u64(token.leading_start) || !out(32) || !out_u64(token.leading_end) || !out(32) || !out_hex(state.values, token.value_start, token.value_end) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_diagnostics(state: State) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(LexDiagRec, state.diagnostics) {
        let diag = __s0_buffer_get(LexDiagRec, state.diagnostics, at)
        if !out_string("D LEX0001 ") || !out_u64(diag.kind) || !out(32) || !out_path(state, diag.source) || !out(32) || !out_u64(diag.start) || !out(32) || !out_u64(diag.end) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit(state: State) -> Bool {
    if !out_string("ALDER-TOKEN-MANIFEST 1\n") || !emit_sources(state) || !emit_tokens(state) || !emit_diagnostics(state) { return false }
    return out_string("END\n")
}
