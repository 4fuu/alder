fn storage_error(at: U64) -> Bool {
    let text = "alder spike: storage failure\n"
    if at == len(text) { return true }
    if !unsafe c { alderhost_stderr_byte(text[at]) } { return false }
    return storage_error(at + 1)
}

fn run(d: Domain, initial: State) -> I32 {
    let count = unsafe c { alderhost_source_count() }
    return match load_sources(d, initial, 0, count) {
        Err(error) => storage_status()
        Ok(loaded) => match parse_sources(d, loaded, 0) {
            Err(error) => storage_status()
            Ok(parsed) => match resolve_decls(d, parsed, 0) {
                Err(error) => storage_status()
                Ok(with_dups) => match resolve_uses(d, with_dups, 0) {
                    Err(error) => storage_status()
                    Ok(done) => finish(done)
                }
            }
        }
    }
}

fn finish(state: State) -> I32 {
    if !emit(state) { return 4 }
    if __s0_buffer_len(DiagRec, state.diags) != 0 { return 2 }
    return 0
}

fn storage_status() -> I32 {
    let ignored = storage_error(0)
    if ignored { return 3 }
    return 3
}

fn init_uses(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), names: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec), decls: __s0_Buffer(DeclRec)) -> I32 {
    return match __s0_buffer_new(UseRec, d) {
        Err(error) => storage_status()
        Ok(uses) => match __s0_buffer_new(DiagRec, d) {
            Err(error) => storage_status()
            Ok(diags) => run(d, State(paths: paths, texts: texts, names: names, sources: sources, decls: decls, uses: uses, diags: diags))
        }
    }
}

fn init_decls(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), names: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec)) -> I32 {
    return match __s0_buffer_new(DeclRec, d) {
        Err(error) => storage_status()
        Ok(decls) => init_uses(d, paths, texts, names, sources, decls)
    }
}

fn init_sources(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), names: __s0_Buffer(U8)) -> I32 {
    return match __s0_buffer_new(SourceRec, d) {
        Err(error) => storage_status()
        Ok(sources) => init_decls(d, paths, texts, names, sources)
    }
}

fn init_names(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8)) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_status()
        Ok(names) => init_sources(d, paths, texts, names)
    }
}

fn init_texts(d: Domain, paths: __s0_Buffer(U8)) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_status()
        Ok(texts) => init_names(d, paths, texts)
    }
}

fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_status()
        Ok(paths) => init_texts(d, paths)
    }
}
