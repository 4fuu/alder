fn storage_error() -> I32 {
    let text = "alder compiler: storage failure\n"
    var at: U64 = 0
    while at < len(text) {
        if !unsafe c { alderhost_stderr_byte(text[at]) } { return 3 }
        at = at + 1
    }
    return 3
}

fn finish(result: LexResult) -> I32 {
    return match result {
        Good(state) => finish_state(state, false)
        Bad(state) => finish_state(state, true)
    }
}

fn finish_state(state: State, failed: Bool) -> I32 {
    if !emit(state) { return 4 }
    if failed { return 1 }
    return 0
}

fn run(d: Domain, state: State) -> I32 {
    return match load_sources(d, state) {
        Err(error) => storage_error()
        Ok(loaded) => match lex_sources(d, loaded, 0) {
            Err(error) => storage_error()
            Ok(result) => finish(result)
        }
    }
}

fn init_diagnostics(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec), tokens: __s0_Buffer(TokenRec)) -> I32 {
    return match __s0_buffer_new(LexDiagRec, d) {
        Err(error) => storage_error()
        Ok(diagnostics) => run(d, State(paths: paths, texts: texts, values: values, sources: sources, tokens: tokens, diagnostics: diagnostics))
    }
}

fn init_tokens(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec)) -> I32 {
    return match __s0_buffer_new(TokenRec, d) {
        Err(error) => storage_error()
        Ok(tokens) => init_diagnostics(d, paths, texts, values, sources, tokens)
    }
}

fn init_sources(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8)) -> I32 {
    return match __s0_buffer_new(SourceRec, d) {
        Err(error) => storage_error()
        Ok(sources) => init_tokens(d, paths, texts, values, sources)
    }
}

fn init_values(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8)) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_error()
        Ok(values) => init_sources(d, paths, texts, values)
    }
}

fn init_texts(d: Domain, paths: __s0_Buffer(U8)) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_error()
        Ok(texts) => init_values(d, paths, texts)
    }
}

fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_error()
        Ok(paths) => init_texts(d, paths)
    }
}
