import c alderhost_source_count: fn() -> U64
import c alderhost_source_path_len: fn(U64) -> U64
import c alderhost_source_path_byte: fn(U64, U64) -> U8
import c alderhost_source_text_len: fn(U64) -> U64
import c alderhost_source_text_byte: fn(U64, U64) -> U8
import c alderhost_stdout_byte: fn(U8) -> Bool
import c alderhost_stdout_f64_bits: fn(U64) -> Bool
import c alderhost_decimal_f64_bits: fn(U64, U64, I64) -> U64
import c alderhost_stderr_byte: fn(U8) -> Bool
import c alderhost_project_entry_source: fn() -> U64

fn host_project_entry_source() -> U64 { return unsafe c { alderhost_project_entry_source() } }

fn copy_host_path(d: Domain, b: Vec(U8), source: U64, end: U64) -> Result(Vec(U8), __s0_Error) {
    var result = b
    var at: U64 = 0
    while at < end {
        try result.try_push(unsafe c { alderhost_source_path_byte(source, at) })
        at = at + 1
    }
    return Ok(result)
}

fn copy_host_text(d: Domain, b: Vec(U8), source: U64, end: U64) -> Result(Vec(U8), __s0_Error) {
    var result = b
    var at: U64 = 0
    while at < end {
        try result.try_push(unsafe c { alderhost_source_text_byte(source, at) })
        at = at + 1
    }
    return Ok(result)
}

fn load_sources(d: Domain, state: State) -> Result(State, __s0_Error) {
    var paths = state.paths
    var texts = state.texts
    var sources = state.sources
    let count = unsafe c { alderhost_source_count() }
    var source: U64 = 0
    while source < count {
        let path_len = unsafe c { alderhost_source_path_len(source) }
        let text_len = unsafe c { alderhost_source_text_len(source) }
        let path_start = (paths).len()
        paths = try copy_host_path(d, paths, source, path_len)
        let text_start = (texts).len()
        texts = try copy_host_text(d, texts, source, text_len)
        let rec = SourceRec(path_start: path_start, path_end: path_start + path_len, text_start: text_start, text_end: text_start + text_len)
        try sources.try_push(rec)
        source = source + 1
    }
    return Ok(State(paths: paths, texts: texts, values: state.values, sources: sources, tokens: state.tokens, diagnostics: state.diagnostics))
}
