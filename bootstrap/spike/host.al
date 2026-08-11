import c alderhost_source_count: fn() -> U64
import c alderhost_source_path_len: fn(U64) -> U64
import c alderhost_source_path_byte: fn(U64, U64) -> U8
import c alderhost_source_text_len: fn(U64) -> U64
import c alderhost_source_text_byte: fn(U64, U64) -> U8
import c alderhost_stdout_byte: fn(U8) -> Bool
import c alderhost_stderr_byte: fn(U8) -> Bool

fn copy_path(d: Domain, b: __s0_Buffer(U8), source: U64, at: U64, end: U64) -> Result(__s0_Buffer(U8), __s0_Error) {
    if at == end { return Ok(b) }
    let byte = unsafe c { alderhost_source_path_byte(source, at) }
    let next = try __s0_buffer_append(U8, d, b, byte)
    return copy_path(d, next, source, at + 1, end)
}

fn copy_text(d: Domain, b: __s0_Buffer(U8), source: U64, at: U64, end: U64) -> Result(__s0_Buffer(U8), __s0_Error) {
    if at == end { return Ok(b) }
    let byte = unsafe c { alderhost_source_text_byte(source, at) }
    let next = try __s0_buffer_append(U8, d, b, byte)
    return copy_text(d, next, source, at + 1, end)
}

fn load_sources(d: Domain, state: State, source: U64, count: U64) -> Result(State, __s0_Error) {
    if source == count { return Ok(state) }
    let path_len = unsafe c { alderhost_source_path_len(source) }
    let text_len = unsafe c { alderhost_source_text_len(source) }
    let path_start = __s0_buffer_len(U8, state.paths)
    let paths = try copy_path(d, state.paths, source, 0, path_len)
    let text_start = __s0_buffer_len(U8, state.texts)
    let texts = try copy_text(d, state.texts, source, 0, text_len)
    let rec = SourceRec(path_start: path_start, path_end: path_start + path_len, text_start: text_start, text_end: text_start + text_len)
    let sources = try __s0_buffer_append(SourceRec, d, state.sources, rec)
    let next = State(paths: paths, texts: texts, names: state.names, sources: sources, decls: state.decls, uses: state.uses, diags: state.diags)
    return load_sources(d, next, source + 1, count)
}
