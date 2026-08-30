fn storage_error() -> I32 {
    return driver_storage_error()
}

fn finish_cgen(generated: Bool) -> I32 {
    if !generated {
        if driver_output_failed() { return driver_failure(3, "io", "cannot write compiler output") }
        return driver_internal_error()
    }
    if !driver_artifact_finish() { return driver_failure(3, "io", "cannot write compiler output") }
    return 0
}

fn run_cgen(d: Domain, mir: MirStore, verified: MirVerifyCompleteOutput) -> I32 {
    return match cgen_generate_verified(d, mir, verified) {
        Err(error) => storage_error()
        Ok(generated) => finish_cgen(generated)
    }
}

fn finish_verify(d: Domain, mir: MirStore, result: MirVerifyCompleteOutput) -> I32 {
    if !result.complete { return driver_failure(4, "internal", "internal compiler failure: verification refused") }
    if driver_command() == 1 { return driver_success_check() }
    if driver_command() == 2 {
        if !driver_artifact_start("mir") { return driver_failure(3, "io", "cannot write compiler output") }
        if !mir_print(mir) {
            if driver_output_failed() { return driver_failure(3, "io", "cannot write compiler output") }
            return driver_internal_error()
        }
        if !driver_artifact_finish() { return driver_failure(3, "io", "cannot write compiler output") }
        return 0
    }
    if !driver_artifact_start("c") { return driver_failure(3, "io", "cannot write compiler output") }
    return run_cgen(d, mir, result)
}

fn run_verify(d: Domain, mir: MirStore) -> I32 {
    var hosted = false
    if driver_command() == 3 && (!project_mode() || project_binary()) { hosted = true }
    return match mir_verify_complete(d, mir, 4, hosted) {
        Err(error) => storage_error()
        Ok(result) => finish_verify(d, mir, result)
    }
}

fn finish_lower(d: Domain, result: LowerResult) -> I32 {
    return match result {
        LowerBad => driver_failure(4, "internal", "internal compiler failure: lowering refused")
        LowerModelBad => driver_failure(4, "internal", "internal compiler failure: lowering model refused")
        LowerGood(mir) => run_verify(d, mir)
    }
}

fn run_lower(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> I32 {
    return match checked_spans(d, parse) {
        Err(error) => storage_error()
        Ok(spans) => match lower_checked(d, state, spans, store) {
            Err(error) => storage_error()
            Ok(result) => finish_lower(d, result)
        }
    }
}

fn finish_check_bad(state: State, parse: ParseStore, store: CheckStore) -> I32 {
    return driver_check_diagnostic(state, parse, store)
}

fn finish_check(d: Domain, state: State, parse: ParseStore, result: CheckResult) -> I32 {
    return match result {
        CheckGood(store) => run_lower(d, state, parse, store)
        CheckBad(store) => finish_check_bad(state, parse, store)
    }
}

fn run_check(d: Domain, output: ParseOutput, store: CheckStore) -> I32 {
    return match check_parsed(d, output.state, output.store, store) {
        Err(error) => storage_error()
        Ok(result) => finish_check(d, output.state, output.store, result)
    }
}

fn init_check_diagnostics(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec), locals: Vec(LocalRec), environments: Vec(EnvironmentRec), expressions: Vec(CheckedExprRec), call_annotations: Vec(CallAnnotationRec), expression_children: Vec(CheckedExprChildRec), returns: Vec(CheckedReturnRec)) -> I32 {
    let blocks = Vec.new(CheckedBlockRec)
    let links = Vec.new(CheckedStatementLinkRec)
    let statements = Vec.new(CheckedStatementRec)
    let places = Vec.new(CheckedPlaceRec)
    let matches = Vec.new(CheckedMatchRec)
    let arms = Vec.new(CheckedMatchArmRec)
    let tries = Vec.new(CheckedTryRec)
    let cleanups = Vec.new(CheckedCleanupRec)
    let diagnostics = Vec.new(CheckDiagRec)
    let use_indexes = Vec.new(CheckerUseIndexRec)
    let use_order = Vec.new(U64)
    return run_check(d, output, CheckStore(symbols: symbols, type_params: type_params, types: types, type_args: type_args, type_annotations: type_annotations, uses: uses, indexes: CheckerIndexes(uses: use_indexes, use_order: use_order, complete: false), locals: locals, environments: environments, expressions: expressions, call_annotations: call_annotations, expression_children: expression_children, returns: returns, control: CheckedControlStore(blocks: blocks, statement_links: links, statements: statements, places: places, matches: matches, match_arms: arms, tries: tries, cleanups: cleanups), diagnostics: diagnostics))
}

fn init_check_returns(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec), locals: Vec(LocalRec), environments: Vec(EnvironmentRec), expressions: Vec(CheckedExprRec), call_annotations: Vec(CallAnnotationRec), expression_children: Vec(CheckedExprChildRec)) -> I32 {
    return init_check_diagnostics(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions, call_annotations, expression_children, Vec.new(CheckedReturnRec))
}

fn init_check_expression_children(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec), locals: Vec(LocalRec), environments: Vec(EnvironmentRec), expressions: Vec(CheckedExprRec), call_annotations: Vec(CallAnnotationRec)) -> I32 {
    return init_check_returns(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions, call_annotations, Vec.new(CheckedExprChildRec))
}

fn init_check_call_annotations(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec), locals: Vec(LocalRec), environments: Vec(EnvironmentRec), expressions: Vec(CheckedExprRec)) -> I32 {
    return init_check_expression_children(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions, Vec.new(CallAnnotationRec))
}

fn init_check_expressions(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec), locals: Vec(LocalRec), environments: Vec(EnvironmentRec)) -> I32 {
    return init_check_call_annotations(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, Vec.new(CheckedExprRec))
}

fn init_check_environments(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec), locals: Vec(LocalRec)) -> I32 {
    return init_check_expressions(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, Vec.new(EnvironmentRec))
}

fn init_check_locals(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec), uses: Vec(DeclTypeUseRec)) -> I32 {
    return init_check_environments(d, output, symbols, type_params, types, type_args, type_annotations, uses, Vec.new(LocalRec))
}

fn init_check_uses(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64), type_annotations: Vec(CheckedTypeAnnotationRec)) -> I32 {
    return init_check_locals(d, output, symbols, type_params, types, type_args, type_annotations, Vec.new(DeclTypeUseRec))
}

fn init_check_type_args(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec)) -> I32 {
    return init_check_type_annotations(d, output, symbols, type_params, types, Vec.new(U64))
}

fn init_check_type_annotations(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec), types: Vec(CheckedTypeRec), type_args: Vec(U64)) -> I32 {
    return init_check_uses(d, output, symbols, type_params, types, type_args, Vec.new(CheckedTypeAnnotationRec))
}

fn init_check_types(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec), type_params: Vec(TypeParamRec)) -> I32 {
    return init_check_type_args(d, output, symbols, type_params, Vec.new(CheckedTypeRec))
}

fn init_check_type_params(d: Domain, output: ParseOutput, symbols: Vec(SymbolRec)) -> I32 {
    return init_check_types(d, output, symbols, Vec.new(TypeParamRec))
}

fn init_check_symbols(d: Domain, output: ParseOutput) -> I32 {
    return init_check_type_params(d, output, Vec.new(SymbolRec))
}

fn finish_parse(d: Domain, result: ParseResult) -> I32 {
    return match result {
        ParseGood(output) => init_check_symbols(d, output)
        ParseBad(output) => finish_parse_failure(output.state, output.store)
        ParseLexBad(output) => finish_lex_failure(output.state, output.store)
    }
}

fn finish_parse_failure(state: State, store: ParseStore) -> I32 {
    return driver_parse_diagnostic(state, store)
}

fn finish_lex_failure(state: State, store: ParseStore) -> I32 {
    return driver_lex_diagnostic(state, store)
}

fn run_parse(d: Domain, state: State, store: ParseStore) -> I32 {
    return match parse_sources(d, state, store) {
        Err(error) => storage_error()
        Ok(result) => finish_parse(d, result)
    }
}

fn init_parse_diagnostics(d: Domain, state: State, nodes: Vec(SyntaxRec), links: Vec(SyntaxLinkRec), roots: Vec(U64)) -> I32 {
    return run_parse(d, state, ParseStore(nodes: nodes, links: links, roots: roots, diagnostics: Vec.new(ParseDiagRec)))
}

fn init_parse_roots(d: Domain, state: State, nodes: Vec(SyntaxRec), links: Vec(SyntaxLinkRec)) -> I32 {
    return init_parse_diagnostics(d, state, nodes, links, Vec.new(U64))
}

fn init_parse_links(d: Domain, state: State, nodes: Vec(SyntaxRec)) -> I32 {
    return init_parse_roots(d, state, nodes, Vec.new(SyntaxLinkRec))
}

fn init_parse_nodes(d: Domain, state: State) -> I32 {
    return init_parse_links(d, state, Vec.new(SyntaxRec))
}

fn run(d: Domain, state: State) -> I32 {
    return match load_sources(d, state) {
        Err(error) => storage_error()
        Ok(loaded) => init_parse_nodes(d, loaded)
    }
}

fn init_diagnostics(d: Domain, paths: Vec(U8), texts: Vec(U8), values: Vec(U8), sources: Vec(SourceRec), tokens: Vec(TokenRec)) -> I32 {
    return run(d, State(paths: paths, texts: texts, values: values, sources: sources, tokens: tokens, diagnostics: Vec.new(LexDiagRec)))
}

fn init_tokens(d: Domain, paths: Vec(U8), texts: Vec(U8), values: Vec(U8), sources: Vec(SourceRec)) -> I32 {
    return init_diagnostics(d, paths, texts, values, sources, Vec.new(TokenRec))
}

fn init_sources(d: Domain, paths: Vec(U8), texts: Vec(U8), values: Vec(U8)) -> I32 {
    return init_tokens(d, paths, texts, values, Vec.new(SourceRec))
}

fn init_values(d: Domain, paths: Vec(U8), texts: Vec(U8)) -> I32 {
    return init_sources(d, paths, texts, Vec.new(U8))
}

fn init_texts(d: Domain, paths: Vec(U8)) -> I32 {
    return init_values(d, paths, Vec.new(U8))
}

fn project_compile_prepared(d: Domain) -> I32 {
    return init_texts(d, Vec.new(U8))
}

fn main(d: Domain) -> I32 {
    if project_mode() { return project_prepare(d) }
    return project_compile_prepared(d)
}
