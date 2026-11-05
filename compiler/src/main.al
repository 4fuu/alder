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
    return match mir_verify_complete(d, mir, mir_format_version(), hosted) {
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

fn init_check_diagnostics(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), environments: __s0_Buffer(EnvironmentRec), expressions: __s0_Buffer(CheckedExprRec), call_annotations: __s0_Buffer(CallAnnotationRec), expression_children: __s0_Buffer(CheckedExprChildRec), returns: __s0_Buffer(CheckedReturnRec)) -> I32 {
    return match __s0_buffer_new(CheckedBlockRec, d) {
        Err(error) => storage_error()
        Ok(blocks) => match __s0_buffer_new(CheckedStatementLinkRec, d) {
            Err(error) => storage_error()
            Ok(links) => match __s0_buffer_new(CheckedStatementRec, d) {
                Err(error) => storage_error()
                Ok(statements) => match __s0_buffer_new(CheckedPlaceRec, d) {
                    Err(error) => storage_error()
                    Ok(places) => match __s0_buffer_new(CheckedMatchRec, d) {
                        Err(error) => storage_error()
                        Ok(matches) => match __s0_buffer_new(CheckedMatchArmRec, d) {
                            Err(error) => storage_error()
                            Ok(arms) => match __s0_buffer_new(CheckedTryRec, d) {
                                Err(error) => storage_error()
                                Ok(tries) => match __s0_buffer_new(CheckedCleanupRec, d) {
                                    Err(error) => storage_error()
                                    Ok(cleanups) => match __s0_buffer_new(CheckDiagRec, d) {
                                        Err(error) => storage_error()
                                        Ok(diagnostics) => match __s0_buffer_new(CheckerUseIndexRec, d) {
                                            Err(error) => storage_error()
                                            Ok(use_indexes) => match __s0_buffer_new(U64, d) {
                                                Err(error) => storage_error()
                                                Ok(use_order) => match empty_trait_store(d) {
                                                Err(error) => storage_error()
                                                Ok(traits) => match empty_closure_store(d) {
                                                Err(error) => storage_error()
                                                Ok(closures) => run_check(d, output, CheckStore(symbols: symbols, type_params: type_params, types: types, type_args: type_args, type_annotations: type_annotations, uses: uses, indexes: CheckerIndexes(uses: use_indexes, use_order: use_order, complete: false), locals: locals, environments: environments, expressions: expressions, call_annotations: call_annotations, expression_children: expression_children, returns: returns, control: CheckedControlStore(blocks: blocks, statement_links: links, statements: statements, places: places, matches: matches, match_arms: arms, tries: tries, cleanups: cleanups), diagnostics: diagnostics, traits: traits, closures: closures))
                                            }
                                            }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn init_check_returns(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), environments: __s0_Buffer(EnvironmentRec), expressions: __s0_Buffer(CheckedExprRec), call_annotations: __s0_Buffer(CallAnnotationRec), expression_children: __s0_Buffer(CheckedExprChildRec)) -> I32 {
    return match __s0_buffer_new(CheckedReturnRec, d) {
        Err(error) => storage_error()
        Ok(returns) => init_check_diagnostics(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions, call_annotations, expression_children, returns)
    }
}

fn init_check_expression_children(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), environments: __s0_Buffer(EnvironmentRec), expressions: __s0_Buffer(CheckedExprRec), call_annotations: __s0_Buffer(CallAnnotationRec)) -> I32 {
    return match __s0_buffer_new(CheckedExprChildRec, d) {
        Err(error) => storage_error()
        Ok(children) => init_check_returns(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions, call_annotations, children)
    }
}

fn init_check_call_annotations(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), environments: __s0_Buffer(EnvironmentRec), expressions: __s0_Buffer(CheckedExprRec)) -> I32 {
    return match __s0_buffer_new(CallAnnotationRec, d) {
        Err(error) => storage_error()
        Ok(annotations) => init_check_expression_children(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions, annotations)
    }
}

fn init_check_expressions(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), environments: __s0_Buffer(EnvironmentRec)) -> I32 {
    return match __s0_buffer_new(CheckedExprRec, d) {
        Err(error) => storage_error()
        Ok(expressions) => init_check_call_annotations(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments, expressions)
    }
}

fn init_check_environments(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec)) -> I32 {
    return match __s0_buffer_new(EnvironmentRec, d) {
        Err(error) => storage_error()
        Ok(environments) => init_check_expressions(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals, environments)
    }
}

fn init_check_locals(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec)) -> I32 {
    return match __s0_buffer_new(LocalRec, d) {
        Err(error) => storage_error()
        Ok(locals) => init_check_environments(d, output, symbols, type_params, types, type_args, type_annotations, uses, locals)
    }
}

fn init_check_uses(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64), type_annotations: __s0_Buffer(CheckedTypeAnnotationRec)) -> I32 {
    return match __s0_buffer_new(DeclTypeUseRec, d) {
        Err(error) => storage_error()
        Ok(uses) => init_check_locals(d, output, symbols, type_params, types, type_args, type_annotations, uses)
    }
}

fn init_check_type_args(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec)) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => storage_error()
        Ok(type_args) => init_check_type_annotations(d, output, symbols, type_params, types, type_args)
    }
}

fn init_check_type_annotations(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), type_args: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_new(CheckedTypeAnnotationRec, d) {
        Err(error) => storage_error()
        Ok(annotations) => init_check_uses(d, output, symbols, type_params, types, type_args, annotations)
    }
}

fn init_check_types(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec), type_params: __s0_Buffer(TypeParamRec)) -> I32 {
    return match __s0_buffer_new(CheckedTypeRec, d) {
        Err(error) => storage_error()
        Ok(types) => init_check_type_args(d, output, symbols, type_params, types)
    }
}

fn init_check_type_params(d: Domain, output: ParseOutput, symbols: __s0_Buffer(SymbolRec)) -> I32 {
    return match __s0_buffer_new(TypeParamRec, d) {
        Err(error) => storage_error()
        Ok(type_params) => init_check_types(d, output, symbols, type_params)
    }
}

fn init_check_symbols(d: Domain, output: ParseOutput) -> I32 {
    return match __s0_buffer_new(SymbolRec, d) {
        Err(error) => storage_error()
        Ok(symbols) => init_check_type_params(d, output, symbols)
    }
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

fn init_parse_diagnostics(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec), roots: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_new(ParseDiagRec, d) {
        Err(error) => storage_error()
        Ok(diagnostics) => run_parse(d, state, ParseStore(nodes: nodes, links: links, roots: roots, diagnostics: diagnostics))
    }
}

fn init_parse_roots(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec)) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => storage_error()
        Ok(roots) => init_parse_diagnostics(d, state, nodes, links, roots)
    }
}

fn init_parse_links(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec)) -> I32 {
    return match __s0_buffer_new(SyntaxLinkRec, d) {
        Err(error) => storage_error()
        Ok(links) => init_parse_roots(d, state, nodes, links)
    }
}

fn init_parse_nodes(d: Domain, state: State) -> I32 {
    return match __s0_buffer_new(SyntaxRec, d) {
        Err(error) => storage_error()
        Ok(nodes) => init_parse_links(d, state, nodes)
    }
}

fn run(d: Domain, state: State) -> I32 {
    return match load_sources(d, state) {
        Err(error) => storage_error()
        Ok(loaded) => init_parse_nodes(d, loaded)
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

fn project_compile_prepared(d: Domain) -> I32 {
    return match __s0_buffer_new(U8, d) {
        Err(error) => storage_error()
        Ok(paths) => init_texts(d, paths)
    }
}

fn main(d: Domain) -> I32 {
    if project_mode() { return project_prepare(d) }
    return project_compile_prepared(d)
}
