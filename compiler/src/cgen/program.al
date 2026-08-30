// Declaration and hosted-program skeleton over flat MIR 4 records. Instruction
// bodies and the production generator entry deliberately remain unavailable.

fn cgen_import_param(store: MirStore, owner: U64, ordinal: U64) -> MirOperandRec {
    var at: U64 = 0
    while at < (store.operands).len() {
        let item = (store.operands)[at]
        if item.kind == mir_operand_import_param() && item.owner == owner && item.ordinal == ordinal { return item }
        at = at + 1
    }
    return (store.operands)[0]
}

fn cgen_function_param(store: MirStore, indexes: MirVIndexes, owner: U64, ordinal: U64) -> MirParamRec {
    let count = mir_vindex_param_count(indexes, owner)
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, owner, at)
        if id != 0 {
            let item = (store.params)[id - 1]
            if item.kind == mir_param_function() && item.ordinal == ordinal { return item }
        }
        at = at + 1
    }
    return (store.params)[0]
}

fn cgen_function_param_count(store: MirStore, indexes: MirVIndexes, function: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var total: U64 = 0
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, function, at)
        if id != 0 {
            let item = (store.params)[id - 1]
            if item.kind == mir_param_function() { total = total + 1 }
        }
        at = at + 1
    }
    return total
}

fn cgen_emit_function_name(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = (store.functions)[function - 1]
    var out = try cgen_put(d, initial, "alder_fn_")
    out = try cgen_put_name_fragment(d, out, store, item.name_start, item.name_end)
    out = try cgen_put(d, out, "_")
    return cgen_put_u64(d, out, function - 1)
}

fn cgen_emit_function_params(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let count = cgen_function_param_count(store, indexes, function)
    var ordinal: U64 = 0
    var wrote = false
    while ordinal < count {
        let item = cgen_function_param(store, indexes, function, ordinal)
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
    while at < (store.constants).len() {
        let item = (store.constants)[at]
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
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const ")
            if item.const_type == mir_type_f32() { out = try cgen_put(d, out, "uint32_t") } else { out = try cgen_put(d, out, "uint64_t") }
            out = try cgen_put(d, out, " alder_const_")
            out = try cgen_put_u64(d, out, at)
            if item.const_type == mir_type_f32() { out = try cgen_put(d, out, "_bits = UINT32_C(") } else { out = try cgen_put(d, out, "_bits = UINT64_C(") }
            out = try cgen_put_u64(d, out, item.float_bits)
            out = try cgen_put(d, out, ");\n")
        }
        if item.kind == mir_const_string() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED ")
            if mir_vtype_kind(store, item.const_type) != mir_type_kind_slice() { out = try cgen_put(d, out, "const ") }
            out = try cgen_put(d, out, "uint8_t alder_str_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, "[] = {")
            var byte_at = item.string_start
            if byte_at == item.string_end { out = try cgen_put(d, out, "UINT8_C(0)") }
            while byte_at < item.string_end {
                if byte_at != item.string_start { out = try cgen_put(d, out, ", ") }
                out = try cgen_put(d, out, "UINT8_C(")
                out = try cgen_put_u64(d, out, cgen_u8_to_u64((store.names)[byte_at]))
                out = try cgen_put(d, out, ")")
                byte_at = byte_at + 1
            }
            out = try cgen_put(d, out, "};\n")
        }
        at = at + 1
    }
    if (store.constants).len() > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_imports(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < (store.imports).len() {
        let item = (store.imports)[at]
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
    if (store.imports).len() > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_functions(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < (store.functions).len() {
        let item = (store.functions)[at]
        out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED ")
        if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
        out = try cgen_put(d, out, " ")
        out = try cgen_emit_function_name(d, out, store, at + 1)
        out = try cgen_put(d, out, "(")
        out = try cgen_emit_function_params(d, out, store, indexes, at + 1)
        out = try cgen_put(d, out, ");\n")
        at = at + 1
    }
    if (store.functions).len() > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_host_entry(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, main: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "int32_t alder_program_entry(void *host_context) {\n  if (host_context == NULL) { return ALDER_PROGRAM_FAILURE_STATUS; }\n")
    let count = cgen_function_param_count(store, indexes, main)
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

fn cgen_emit_cleanup_sites(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    var wrote = false
    while at < (store.instructions).len() {
        let item = (store.instructions)[at]
        if item.op == mir_op_cleanup_push() {
            let count = cgen_operand_count(store, indexes, mir_operand_instruction(), at + 1, 0)
            out = try cgen_put(d, out, "typedef struct AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " {\n")
            var ordinal: U64 = 0
            var field: U64 = 0
            while ordinal < count {
                let parameter = cgen_function_param(store, indexes, item.target, ordinal)
                if parameter.param_type != mir_type_unit() {
                    out = try cgen_put(d, out, "  ")
                    out = try cgen_put_type(d, out, store, parameter.param_type)
                    out = try cgen_put(d, out, " alder_f")
                    out = try cgen_put_u64(d, out, field)
                    out = try cgen_put(d, out, ";\n")
                    field = field + 1
                }
                ordinal = ordinal + 1
            }
            if field == 0 { out = try cgen_put(d, out, "  uint8_t alder_empty;\n") }
            out = try cgen_put(d, out, "} AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, ";\nstatic ALDER_MAYBE_UNUSED void alder_cleanup_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, "(void *alder_ctx) {\n")
            if field == 0 { out = try cgen_put(d, out, "  (void)alder_ctx;\n") } else { out = try cgen_put(d, out, "  AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " *alder_c = (AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " *)alder_ctx;\n") }
            out = try cgen_put(d, out, "  ")
            out = try cgen_emit_function_name(d, out, store, item.target)
            out = try cgen_put(d, out, "(")
            ordinal = 0
            field = 0
            var first = true
            while ordinal < count {
                let parameter = cgen_function_param(store, indexes, item.target, ordinal)
                if parameter.param_type != mir_type_unit() {
                    if !first { out = try cgen_put(d, out, ", ") }
                    out = try cgen_put(d, out, "alder_c->alder_f")
                    out = try cgen_put_u64(d, out, field)
                    field = field + 1
                    first = false
                }
                ordinal = ordinal + 1
            }
            out = try cgen_put(d, out, ");\n}\n")
            wrote = true
        }
        at = at + 1
    }
    if wrote { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_copy_helper_body(d: Domain, initial: CgenWriter, store: MirStore, type_id: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let item = (store.types)[type_id - 1]
    if item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() || item.kind == mir_type_kind_vec() {
        out = try cgen_put(d, out, "  uint64_t alder_t;\n  if (!alder_u64_mul_checked(alder_v.len, (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, item.elem)
        out = try cgen_put(d, out, "), &alder_t)) { return (uint8_t)2; }\n  if (alder_t > (uint64_t)SIZE_MAX) { return (uint8_t)2; }\n  if (alder_v.len > (uint64_t)0) {\n    if (alder_v.data == NULL) { alder_runtime_panic(\"copy_to_domain: null source\"); }\n    void *alder_p = alder_domain_alloc(alder_d, (size_t)alder_t, _Alignof(")
        out = try cgen_put_type(d, out, store, item.elem)
        out = try cgen_put(d, out, "));\n    if (alder_p == NULL) { return (uint8_t)1; }\n")
        if cgen_copy_trivial(store, item.elem) { out = try cgen_put(d, out, "    memcpy(alder_p, alder_v.data, (size_t)alder_t);\n") } else { out = try cgen_put(d, out, "    for (uint64_t alder_i = (uint64_t)0; alder_i < alder_v.len; alder_i++) { uint8_t alder_s = alder_try_copy_ty")
            out = try cgen_put_u64(d, out, item.elem - 1)
            out = try cgen_put(d, out, "(alder_d, ((")
            out = try cgen_put_type(d, out, store, item.elem)
            out = try cgen_put(d, out, " *)alder_v.data)[alder_i], &((")
            out = try cgen_put_type(d, out, store, item.elem)
            out = try cgen_put(d, out, " *)alder_p)[alder_i]); if (alder_s != (uint8_t)0) { return alder_s; } }\n") }
        out = try cgen_put(d, out, "    alder_v.data = alder_p;\n  }\n")
        if item.kind == mir_type_kind_vec() { out = try cgen_put(d, out, "  alder_v.capacity = alder_v.len;\n") }
    }
    if item.kind == mir_type_kind_array() && !cgen_copy_trivial(store, item.elem) {
        out = try cgen_put(d, out, "  for (uint64_t alder_i = (uint64_t)0; alder_i < (uint64_t)")
        out = try cgen_put_u64(d, out, item.length)
        out = try cgen_put(d, out, "; alder_i++) {\n    uint8_t alder_s = alder_try_copy_ty")
        out = try cgen_put_u64(d, out, item.elem - 1)
        out = try cgen_put(d, out, "(alder_d, alder_v.alder_e[alder_i], &alder_v.alder_e[alder_i]);\n    if (alder_s != (uint8_t)0) { return alder_s; }\n  }\n")
    }
    if item.kind == mir_type_kind_aggregate() || item.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if item.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, type_id, kind) {
            let child = cgen_type_part(store, type_id, kind, ordinal).part_type
            if child != mir_type_unit() && !cgen_copy_trivial(store, child) {
                if item.kind == mir_type_kind_enum() { out = try cgen_put(d, out, "  if (alder_v.alder_tag == (uint32_t)")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ") {\n  ") }
                out = try cgen_put(d, out, "  { uint8_t alder_s = alder_try_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_v.")
                if item.kind == mir_type_kind_aggregate() { out = try cgen_put(d, out, "alder_f") } else { out = try cgen_put(d, out, "alder_u.alder_p") }
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ", &alder_v.")
                if item.kind == mir_type_kind_aggregate() { out = try cgen_put(d, out, "alder_f") } else { out = try cgen_put(d, out, "alder_u.alder_p") }
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, "); if (alder_s != (uint8_t)0) { return alder_s; } }\n")
                if item.kind == mir_type_kind_enum() { out = try cgen_put(d, out, "  }\n") }
            }
            ordinal = ordinal + 1
        }
    }
    if item.kind == mir_type_kind_option() || item.kind == mir_type_kind_result() {
        var ordinal: U64 = 0
        while ordinal < 2 {
            let child = cgen_variant_payload(store, type_id, ordinal)
            if child != mir_type_unit() && !cgen_copy_trivial(store, child) {
                out = try cgen_put(d, out, "  if (alder_v.alder_tag == (uint32_t)")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ") {\n    uint8_t alder_s = alder_try_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_v.alder_u.alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ", &alder_v.alder_u.alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ");\n    if (alder_s != (uint8_t)0) { return alder_s; }\n  }\n")
            }
            ordinal = ordinal + 1
        }
    }
    return cgen_put(d, out, "  *alder_out = alder_v;\n  return (uint8_t)0;\n}\n")
}

fn cgen_emit_copy_type(d: Domain, initial: CgenTypeState, store: MirStore, type_id: U64) -> Result(CgenTypeState, __s0_Error) {
    if cgen_copy_trivial(store, type_id) || cgen_emitted(initial.emitted, type_id) { return Ok(initial) }
    var state = initial
    let item = (store.types)[type_id - 1]
    if item.kind == mir_type_kind_aggregate() || item.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if item.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, type_id, kind) { state = try cgen_emit_copy_type(d, state, store, cgen_type_part(store, type_id, kind, ordinal).part_type)
        ordinal = ordinal + 1 }
    }
    if item.kind == mir_type_kind_option() || item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() || item.kind == mir_type_kind_vec() || item.kind == mir_type_kind_array() { state = try cgen_emit_copy_type(d, state, store, item.elem) }
    if item.kind == mir_type_kind_result() { state = try cgen_emit_copy_type(d, state, store, item.ok_type)
    state = try cgen_emit_copy_type(d, state, store, item.err_type) }
    var out = try cgen_put(d, state.writer, "static ALDER_MAYBE_UNUSED uint8_t alder_try_copy_ty")
    out = try cgen_put_u64(d, out, type_id - 1)
    out = try cgen_put(d, out, "(AlderDomain *alder_d, ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_v, ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " *alder_out) {\n")
    out = try cgen_emit_copy_helper_body(d, out, store, type_id)
    out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_copy_ty")
    out = try cgen_put_u64(d, out, type_id - 1)
    out = try cgen_put(d, out, "(AlderDomain *alder_d, ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_v) {\n  ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_out;\n  uint8_t alder_s = alder_try_copy_ty")
    out = try cgen_put_u64(d, out, type_id - 1)
    out = try cgen_put(d, out, "(alder_d, alder_v, &alder_out);\n  if (alder_s == (uint8_t)1) { alder_runtime_panic(\"copy_to_domain: out of memory\"); }\n  if (alder_s != (uint8_t)0) { alder_runtime_panic(\"copy_to_domain: size limit\"); }\n  return alder_out;\n}\n")
    let emitted = try vec_appended(U64, state.emitted, type_id)
    return Ok(CgenTypeState(writer: out, emitted: emitted))
}

fn cgen_emit_copy_helpers(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    let emitted = Vec.new(U64)
    var state = CgenTypeState(writer: initial, emitted: emitted)
    var at: U64 = 0
    while at < (store.instructions).len() {
        let item = (store.instructions)[at]
        if item.op == mir_op_copy_to_domain() || item.op == mir_op_copy_to_domain_try() { state = try cgen_emit_copy_type(d, state, store, cgen_value_type(store, indexes, item.function, item.b)) }
        if item.op == mir_op_vec_grow_checked() || item.op == mir_op_vec_try_grow() { let vec_type = cgen_value_type(store, indexes, item.function, item.a)
            state = try cgen_emit_copy_type(d, state, store, (store.types)[vec_type - 1].elem) }
        at = at + 1
    }
    if (state.emitted).len() > 0 { state.writer = try cgen_put(d, state.writer, "\n") }
    return Ok(state.writer)
}

fn cgen_build_declaration_skeleton(d: Domain, store: MirStore, verified: MirVerifyCompleteOutput) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder declaration-only C11 backend skeleton. */\n/* Production generation remains gated on MIR verifier V10. */\n#include \"alder.h\"\n")
    if verified.hosted { out = try cgen_put(d, out, "#include \"alder_host.h\"\n") }
    out = try cgen_put(d, out, "#include <float.h>\n#include <string.h>\n\n")
    let indexes = try mir_vindex_build(d, store)
    out = try cgen_emit_types(d, out, store)
    out = try cgen_emit_constants(d, out, store)
    out = try cgen_emit_functions(d, out, store, indexes)
    out = try cgen_emit_imports(d, out, store)
    if verified.hosted { out = try cgen_emit_host_entry(d, out, store, indexes, verified.entry) }
    return Ok(out)
}

fn cgen_build(d: Domain, store: MirStore, indexes: MirVIndexes, verified: MirVerifyCompleteOutput) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder C11 backend. Do not edit. */\n/* Source: complete-verifier-gated Alder MIR 4. */\n#include \"alder.h\"\n")
    if verified.hosted { out = try cgen_put(d, out, "#include \"alder_host.h\"\n") }
    out = try cgen_put(d, out, "#include <float.h>\n#include <string.h>\n\n")
    out = try cgen_emit_types(d, out, store)
    out = try cgen_emit_constants(d, out, store)
    out = try cgen_emit_functions(d, out, store, indexes)
    out = try cgen_emit_imports(d, out, store)
    out = try cgen_emit_cleanup_sites(d, out, store, indexes)
    out = try cgen_emit_copy_helpers(d, out, store, indexes)
    out = try cgen_emit_bodies(d, out, store)
    if verified.hosted { out = try cgen_emit_host_entry(d, out, store, indexes, verified.entry) }
    return Ok(out)
}

// Internal production entry for an already verified module. The unsupported
// operation preflight still finishes before the output buffer is allocated.
fn cgen_generate_verified(d: Domain, store: MirStore, verified: MirVerifyCompleteOutput) -> Result(Bool, __s0_Error) {
    if !verified.complete { return Ok(false) }
    let indexes = try mir_vindex_build(d, store)
    if !cgen_supported(store, indexes) { return Ok(false) }
    let writer = try cgen_build(d, store, indexes, verified)
    return Ok(cgen_flush(writer))
}

// Direct callers retain the complete verification gate.
fn cgen_generate(d: Domain, store: MirStore, version: U64, hosted: Bool) -> Result(Bool, __s0_Error) {
    let verified = try mir_verify_complete(d, store, version, hosted)
    return cgen_generate_verified(d, store, verified)
}

// Retained declaration-only conformance API. Complete V1-V10 authorization
// happens before allocation of the output buffer; the verified hosted and
// entry fields alone select the program adapter.
fn cgen_write_declaration_skeleton(d: Domain, store: MirStore, version: U64, hosted: Bool) -> Result(Bool, __s0_Error) {
    let verified = try mir_verify_complete(d, store, version, hosted)
    if !verified.complete { return Ok(false) }
    let writer = try cgen_build_declaration_skeleton(d, store, verified)
    return Ok(cgen_flush(writer))
}
