// Declaration and hosted-program skeleton over flat MIR 3 records. Instruction
// bodies and the production generator entry deliberately remain unavailable.

fn cgen_import_param(store: MirStore, owner: U64, ordinal: U64) -> MirOperandRec {
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let item = __s0_buffer_get(MirOperandRec, store.operands, at)
        if item.kind == mir_operand_import_param() && item.owner == owner && item.ordinal == ordinal { return item }
        at = at + 1
    }
    return __s0_buffer_get(MirOperandRec, store.operands, 0)
}

fn cgen_function_param(store: MirStore, owner: U64, ordinal: U64) -> MirParamRec {
    var at: U64 = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let item = __s0_buffer_get(MirParamRec, store.params, at)
        if item.kind == mir_param_function() && item.function == owner && item.ordinal == ordinal { return item }
        at = at + 1
    }
    return __s0_buffer_get(MirParamRec, store.params, 0)
}

fn cgen_emit_function_name(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    var out = try cgen_put(d, initial, "alder_fn_")
    out = try cgen_put_name_fragment(d, out, store, item.name_start, item.name_end)
    out = try cgen_put(d, out, "_")
    return cgen_put_u64(d, out, function - 1)
}

fn cgen_emit_function_params(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let count = mir_param_group_count(store, mir_param_function(), function, 0)
    var ordinal: U64 = 0
    var wrote = false
    while ordinal < count {
        let item = cgen_function_param(store, function, ordinal)
        if item.param_type != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            out = try cgen_put_type(d, out, store, item.param_type)
            out = try cgen_put(d, out, " alder_v")
            out = try cgen_put_u64(d, out, ordinal)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    if !wrote { out = try cgen_put(d, out, "void") }
    return Ok(out)
}

fn cgen_emit_constants(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let item = __s0_buffer_get(MirConstRec, store.constants, at)
        if item.kind == mir_const_unit() {
            out = try cgen_put(d, out, "/* unit constant alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " has no storage. */\n")
        }
        if item.kind == mir_const_bool() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const bool alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = ")
            if item.bool_value == 0 { out = try cgen_put(d, out, "false") } else { out = try cgen_put(d, out, "true") }
            out = try cgen_put(d, out, ";\n")
        }
        if item.kind == mir_const_int() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const ")
            out = try cgen_put_type(d, out, store, item.const_type)
            out = try cgen_put(d, out, " alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, item.const_type)
            out = try cgen_put(d, out, ")")
            out = try cgen_put_i64(d, out, item.int_value)
            out = try cgen_put(d, out, ";\n")
        }
        if item.kind == mir_const_float() {
            // The skeleton retains exact IEEE payloads without host float
            // formatting. Body lowering will materialize the typed value.
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const uint64_t alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, "_bits = UINT64_C(")
            out = try cgen_put_u64(d, out, item.float_bits)
            out = try cgen_put(d, out, ");\n")
        }
        if item.kind == mir_const_string() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED uint8_t alder_str_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, "[] = \"")
            out = try cgen_put_c_bytes(d, out, store.names, item.string_start, item.string_end)
            out = try cgen_put(d, out, "\";\n")
        }
        at = at + 1
    }
    if __s0_buffer_len(MirConstRec, store.constants) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_imports(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let item = __s0_buffer_get(MirImportRec, store.imports, at)
        if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
        out = try cgen_put(d, out, " (")
        out = try cgen_put_name(d, out, store, item.name_start, item.name_end)
        out = try cgen_put(d, out, ")(")
        let count = mir_operand_count(store, mir_operand_import_param(), at + 1, 0)
        var ordinal: U64 = 0
        var wrote = false
        while ordinal < count {
            let param = cgen_import_param(store, at + 1, ordinal)
            if param.operand_type != mir_type_unit() {
                if wrote { out = try cgen_put(d, out, ", ") }
                out = try cgen_put_type(d, out, store, param.operand_type)
                wrote = true
            }
            ordinal = ordinal + 1
        }
        if !wrote { out = try cgen_put(d, out, "void") }
        out = try cgen_put(d, out, ");\n")
        at = at + 1
    }
    if __s0_buffer_len(MirImportRec, store.imports) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_functions(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
        out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED ")
        if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
        out = try cgen_put(d, out, " ")
        out = try cgen_emit_function_name(d, out, store, at + 1)
        out = try cgen_put(d, out, "(")
        out = try cgen_emit_function_params(d, out, store, at + 1)
        out = try cgen_put(d, out, ");\n")
        at = at + 1
    }
    if __s0_buffer_len(MirFunctionRec, store.functions) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_host_entry(d: Domain, initial: CgenWriter, store: MirStore, main: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "int32_t alder_program_entry(void *host_context) {\n  if (host_context == NULL) { return ALDER_PROGRAM_FAILURE_STATUS; }\n")
    let count = mir_param_group_count(store, mir_param_function(), main, 0)
    if count == 0 {
        out = try cgen_put(d, out, "  return ")
        out = try cgen_emit_function_name(d, out, store, main)
        out = try cgen_put(d, out, "();\n")
    } else {
        out = try cgen_put(d, out, "  AlderDomain alder_root = {0};\n  int32_t alder_status;\n  if (!alder_domain_init(&alder_root, NULL)) { return ALDER_PROGRAM_FAILURE_STATUS; }\n  alder_status = ")
        out = try cgen_emit_function_name(d, out, store, main)
        out = try cgen_put(d, out, "(&alder_root);\n  alder_domain_destroy(&alder_root);\n  return alder_status;\n")
    }
    return cgen_put(d, out, "}\n")
}

fn cgen_build_declaration_skeleton(d: Domain, store: MirStore, verified: MirVerifyCompleteOutput) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder declaration-only C11 backend skeleton. */\n/* Production generation remains gated on MIR verifier V10. */\n#include \"alder.h\"\n")
    if verified.hosted { out = try cgen_put(d, out, "#include \"alder_host.h\"\n") }
    out = try cgen_put(d, out, "#include <float.h>\n#include <string.h>\n\n")
    out = try cgen_emit_types(d, out, store)
    out = try cgen_emit_constants(d, out, store)
    out = try cgen_emit_functions(d, out, store)
    out = try cgen_emit_imports(d, out, store)
    if verified.hosted { out = try cgen_emit_host_entry(d, out, store, verified.entry) }
    return Ok(out)
}

// Available declaration-only API. Complete V1-V10 authorization happens before
// allocation of the output buffer; the verified hosted and entry fields alone
// select the program adapter. There is intentionally no cgen_generate entry.
fn cgen_write_declaration_skeleton(d: Domain, store: MirStore, version: U64, hosted: Bool) -> Result(Bool, __s0_Error) {
    let verified = try mir_verify_complete(d, store, version, hosted)
    if !verified.complete { return Ok(false) }
    let writer = try cgen_build_declaration_skeleton(d, store, verified)
    return Ok(cgen_flush(writer))
}
