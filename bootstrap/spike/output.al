fn out(byte: U8) -> Bool { return unsafe c { alderhost_stdout_byte(byte) } }

fn out_bytes(bytes: __s0_Buffer(U8), at: U64, end: U64) -> Bool {
    if at == end { return true }
    let view = __s0_buffer_slice(U8, bytes)
    if !out(view[at]) { return false }
    return out_bytes(bytes, at + 1, end)
}

fn out_string(value: __s0_String, at: U64) -> Bool {
    if at == len(value) { return true }
    if !out(value[at]) { return false }
    return out_string(value, at + 1)
}

fn out_u64(value: U64) -> Bool {
    if value >= 10 {
        if !out_u64(value / 10) { return false }
    }
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

fn out_path(state: State, source: U64) -> Bool {
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    return out_bytes(state.paths, rec.path_start, rec.path_end)
}

fn sources_output(state: State, at: U64) -> Bool {
    if at == __s0_buffer_len(SourceRec, state.sources) { return true }
    let rec = __s0_buffer_get(SourceRec, state.sources, at)
    if !out_string("S ", 0) || !out_u64(at) || !out(32) || !out_path(state, at) || !out(32) || !out_u64(rec.text_end - rec.text_start) || !out(10) { return false }
    return sources_output(state, at + 1)
}

fn decls_output(state: State, at: U64) -> Bool {
    if at == __s0_buffer_len(DeclRec, state.decls) { return true }
    let item = __s0_buffer_get(DeclRec, state.decls, at)
    if !out_string("D ", 0) || !out_u64(at + 1) || !out(32) || !out_bytes(state.names, item.name_start, item.name_end) || !out(32) || !out_path(state, item.source) || !out(32) || !out_u64(item.start) || !out(32) || !out_u64(item.end) || !out(10) { return false }
    return decls_output(state, at + 1)
}

fn use_target_output(state: State, item: UseRec) -> Bool {
    let target = find_decl(state, item.name_start, item.name_end, 0)
    if target == __s0_buffer_len(DeclRec, state.decls) { return out_u64(0) }
    return out_u64(target + 1)
}

fn uses_output(state: State, at: U64) -> Bool {
    if at == __s0_buffer_len(UseRec, state.uses) { return true }
    let item = __s0_buffer_get(UseRec, state.uses, at)
    if !out_string("U ", 0) || !out_u64(at + 1) || !out(32) || !out_bytes(state.names, item.name_start, item.name_end) || !out(32) || !out_path(state, item.source) || !out(32) || !out_u64(item.start) || !out(32) || !out_u64(item.end) || !out(32) || !use_target_output(state, item) || !out(10) { return false }
    return uses_output(state, at + 1)
}

fn diags_output(state: State, at: U64) -> Bool {
    if at == __s0_buffer_len(DiagRec, state.diags) { return true }
    let item = __s0_buffer_get(DiagRec, state.diags, at)
    if !out_string("E E00", 0) || !out_u64(item.code) || !out(32) || !out_path(state, item.source) || !out(32) || !out_u64(item.start) || !out(32) || !out_u64(item.end) { return false }
    if item.code == 2 {
        if !out_string(" related ", 0) || !out_path(state, item.related_source) || !out(32) || !out_u64(item.related_start) || !out(32) || !out_u64(item.related_end) { return false }
    }
    if !out(10) { return false }
    return diags_output(state, at + 1)
}

fn emit(state: State) -> Bool {
    if !out_string("ALDER-DECL-MANIFEST 1\n", 0) { return false }
    if !sources_output(state, 0) { return false }
    if !decls_output(state, 0) { return false }
    if !uses_output(state, 0) { return false }
    if !diags_output(state, 0) { return false }
    return out_string("END\n", 0)
}
