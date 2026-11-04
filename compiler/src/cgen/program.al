// Declaration and hosted-program skeleton over flat MIR 4 records. Instruction
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

fn cgen_function_param(store: MirStore, indexes: MirVIndexes, owner: U64, ordinal: U64) -> MirParamRec {
    let count = mir_vindex_param_count(indexes, owner)
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, owner, at)
        if id != 0 {
            let item = __s0_buffer_get(MirParamRec, store.params, id - 1)
            if item.kind == mir_param_function() && item.ordinal == ordinal { return item }
        }
        at = at + 1
    }
    return __s0_buffer_get(MirParamRec, store.params, 0)
}

fn cgen_function_param_count(store: MirStore, indexes: MirVIndexes, function: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var total: U64 = 0
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, function, at)
        if id != 0 {
            let item = __s0_buffer_get(MirParamRec, store.params, id - 1)
            if item.kind == mir_param_function() { total = total + 1 }
        }
        at = at + 1
    }
    return total
}

fn cgen_emit_function_name(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
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
                out = try cgen_put_u64(d, out, cgen_u8_to_u64(__s0_buffer_get(U8, store.names, byte_at)))
                out = try cgen_put(d, out, ")")
                byte_at = byte_at + 1
            }
            out = try cgen_put(d, out, "};\n")
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

fn cgen_name_has_prefix(store: MirStore, start: U64, end: U64, prefix: __s0_String) -> Bool {
    if start >= end || len(prefix) == 0 || len(prefix) > end - start { return false }
    if end > __s0_buffer_len(U8, store.names) { return false }
    var at: U64 = 0
    while at < len(prefix) {
        if __s0_buffer_get(U8, store.names, start + at) != prefix[at] { return false }
        at = at + 1
    }
    return true
}

// The buffer accessor monomorphisations are tiny, and a compiler-sized program
// calls them billions of times, so the out-of-line call and its argument copy
// were a large fraction of run time. Declaring them `static inline` lets GCC
// inline them; the body, every bounds check and every trap is unchanged, and a
// `static inline` definition that GCC declines to inline is emitted exactly as
// the plain `static` one was.
fn cgen_function_inlinable(store: MirStore, function: U64) -> Bool {
    if function == 0 || function > __s0_buffer_len(MirFunctionRec, store.functions) { return false }
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    return cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_get_") || cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_len_") || cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_set_") || cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_slice_")
}

fn cgen_put_function_linkage(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    if cgen_function_inlinable(store, function) { return cgen_put(d, initial, "static inline ALDER_MAYBE_UNUSED ") }
    return cgen_put(d, initial, "static ALDER_MAYBE_UNUSED ")
}

fn cgen_emit_functions(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
        out = try cgen_put_function_linkage(d, out, store, at + 1)
        if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
        out = try cgen_put(d, out, " ")
        out = try cgen_emit_function_name(d, out, store, at + 1)
        out = try cgen_put(d, out, "(")
        out = try cgen_emit_function_params(d, out, store, indexes, at + 1)
        out = try cgen_put(d, out, ");\n")
        at = at + 1
    }
    if __s0_buffer_len(MirFunctionRec, store.functions) > 0 { out = try cgen_put(d, out, "\n") }
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
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
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
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() || item.kind == mir_type_kind_vec() {
        out = try cgen_put(d, out, "  uint64_t alder_t;\n  if (!alder_u64_mul_checked(alder_v.len, (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, item.elem)
        out = try cgen_put(d, out, "), &alder_t)) { alder_runtime_panic(\"copy_to_domain: size overflow\"); }\n  if (alder_t > (uint64_t)SIZE_MAX) { alder_runtime_panic(\"copy_to_domain: size exceeds size_t\"); }\n  if (alder_v.len > (uint64_t)0) {\n    if (alder_v.data == NULL) { alder_runtime_panic(\"copy_to_domain: null source\"); }\n    void *alder_p = alder_domain_alloc(alder_d, (size_t)alder_t, _Alignof(")
        out = try cgen_put_type(d, out, store, item.elem)
        out = try cgen_put(d, out, "));\n    if (alder_p == NULL) { alder_runtime_panic(\"copy_to_domain: out of memory\"); }\n")
        if cgen_copy_trivial(store, item.elem) { out = try cgen_put(d, out, "    memcpy(alder_p, alder_v.data, (size_t)alder_t);\n") } else { out = try cgen_put(d, out, "    for (uint64_t alder_i = (uint64_t)0; alder_i < alder_v.len; alder_i++) { ((")
            out = try cgen_put_type(d, out, store, item.elem)
            out = try cgen_put(d, out, " *)alder_p)[alder_i] = alder_copy_ty")
            out = try cgen_put_u64(d, out, item.elem - 1)
            out = try cgen_put(d, out, "(alder_d, ((")
            out = try cgen_put_type(d, out, store, item.elem)
            out = try cgen_put(d, out, " *)alder_v.data)[alder_i]); }\n") }
        out = try cgen_put(d, out, "    alder_v.data = alder_p;\n  }\n")
        if item.kind == mir_type_kind_vec() { out = try cgen_put(d, out, "  alder_v.capacity = alder_v.len;\n") }
    }
    if item.kind == mir_type_kind_array() && !cgen_copy_trivial(store, item.elem) {
        out = try cgen_put(d, out, "  for (uint64_t alder_i = (uint64_t)0; alder_i < (uint64_t)")
        out = try cgen_put_u64(d, out, item.length)
        out = try cgen_put(d, out, "; alder_i++) {\n    alder_v.alder_e[alder_i] = alder_copy_ty")
        out = try cgen_put_u64(d, out, item.elem - 1)
        out = try cgen_put(d, out, "(alder_d, alder_v.alder_e[alder_i]);\n  }\n")
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
                out = try cgen_put(d, out, "  alder_v.")
                if item.kind == mir_type_kind_aggregate() { out = try cgen_put(d, out, "alder_f") } else { out = try cgen_put(d, out, "alder_u.alder_p") }
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, " = alder_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_v.")
                if item.kind == mir_type_kind_aggregate() { out = try cgen_put(d, out, "alder_f") } else { out = try cgen_put(d, out, "alder_u.alder_p") }
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ");\n")
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
                out = try cgen_put(d, out, ") {\n    alder_v.alder_u.alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, " = alder_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_v.alder_u.alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ");\n  }\n")
            }
            ordinal = ordinal + 1
        }
    }
    return cgen_put(d, out, "  return alder_v;\n}\n")
}

fn cgen_emit_copy_type(d: Domain, initial: CgenTypeState, store: MirStore, type_id: U64) -> Result(CgenTypeState, __s0_Error) {
    if cgen_copy_trivial(store, type_id) || cgen_emitted(initial.emitted, type_id) { return Ok(initial) }
    var state = initial
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
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
    var out = try cgen_put(d, state.writer, "static ALDER_MAYBE_UNUSED ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_copy_ty")
    out = try cgen_put_u64(d, out, type_id - 1)
    out = try cgen_put(d, out, "(AlderDomain *alder_d, ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_v) {\n")
    out = try cgen_emit_copy_helper_body(d, out, store, type_id)
    let emitted = try __s0_buffer_append(U64, d, state.emitted, type_id)
    return Ok(CgenTypeState(writer: out, emitted: emitted))
}

fn cgen_emit_copy_helpers(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    let emitted = try __s0_buffer_new(U64, d)
    var state = CgenTypeState(writer: initial, emitted: emitted)
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_copy_to_domain() { state = try cgen_emit_copy_type(d, state, store, cgen_value_type(store, indexes, item.function, item.b)) }
        if item.op == mir_op_vec_grow_checked() { let vec_type = cgen_value_type(store, indexes, item.function, item.a)
            state = try cgen_emit_copy_type(d, state, store, __s0_buffer_get(MirTypeRec, store.types, vec_type - 1).elem) }
        at = at + 1
    }
    if __s0_buffer_len(U64, state.emitted) > 0 { state.writer = try cgen_put(d, state.writer, "\n") }
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

// One wrapper per distinct (target, function type) fn.value site, in first
// occurrence order: the value's code pointer type takes the declared
// parameters plus an opaque environment pointer, which ordinary functions
// do not, so the forwarder adapts the signature.
fn cgen_fn_value_sites(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(__s0_Buffer(U64), __s0_Error) {
    var sites = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_fn_value() {
            let fn_type = cgen_value_type(store, indexes, item.function, item.result)
            var known = false
            var site_at: U64 = 0
            while site_at + 1 < __s0_buffer_len(U64, sites) {
                if __s0_buffer_get(U64, sites, site_at) == item.target && __s0_buffer_get(U64, sites, site_at + 1) == fn_type { known = true }
                site_at = site_at + 2
            }
            if !known {
                sites = try __s0_buffer_append(U64, d, sites, item.target)
                sites = try __s0_buffer_append(U64, d, sites, fn_type)
            }
        }
        at = at + 1
    }
    return Ok(sites)
}

// One wrapper per distinct (target, function type) fn.value site, in first
// occurrence order: the value's code pointer type takes the declared
// parameters plus an opaque environment pointer, which ordinary functions
// do not, so the forwarder adapts the signature.
fn cgen_fn_wrapper_result(d: Domain, initial: CgenWriter, store: MirStore, result_type: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    if result_type == mir_type_unit() { return cgen_put(d, out, "void") }
    return cgen_put_type(d, out, store, result_type)
}

fn cgen_fn_wrapper_params(d: Domain, initial: CgenWriter, store: MirStore, fn_type: U64, named: Bool, env: Bool) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let param_total = mir_type_part_count(store, fn_type, mir_type_part_function_param())
    if env { out = try cgen_put(d, out, "(") }
    var wrote = false
    var ordinal: U64 = 0
    while ordinal < param_total {
        let part = cgen_type_part(store, fn_type, mir_type_part_function_param(), ordinal)
        if part.part_type != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            if named { out = try cgen_put_type(d, out, store, part.part_type)
            out = try cgen_put(d, out, " alder_p") }
            if !named { out = try cgen_put(d, out, "alder_p") }
            out = try cgen_put_u64(d, out, ordinal)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    if env {
        if wrote { out = try cgen_put(d, out, ", ") }
        out = try cgen_put(d, out, "void *alder_env)")
    }
    return Ok(out)
}

fn cgen_emit_fn_value_wrappers(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, sites: __s0_Buffer(U64)) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at + 1 < __s0_buffer_len(U64, sites) {
        let target = __s0_buffer_get(U64, sites, at)
        let fn_type = __s0_buffer_get(U64, sites, at + 1)
        let t = __s0_buffer_get(MirTypeRec, store.types, fn_type - 1)
        
        // Forward declaration.
        out = try cgen_put(d, out, "static ")
        out = try cgen_fn_wrapper_result(d, out, store, t.result_type)
        out = try cgen_fn_wrapper_name(d, out, target, fn_type)
        out = try cgen_fn_wrapper_params(d, out, store, fn_type, true, true)
        out = try cgen_put(d, out, ";\n")
        // Definition.
        out = try cgen_put(d, out, "static ")
        out = try cgen_fn_wrapper_result(d, out, store, t.result_type)
        out = try cgen_fn_wrapper_name(d, out, target, fn_type)
        out = try cgen_fn_wrapper_params(d, out, store, fn_type, true, true)
        out = try cgen_put(d, out, " {\n  (void)alder_env;\n  ")
        if t.result_type != mir_type_unit() { out = try cgen_put(d, out, "return ") }
        out = try cgen_emit_function_name(d, out, store, target)
        out = try cgen_put(d, out, "(")
        out = try cgen_fn_wrapper_params(d, out, store, fn_type, false, false)
        out = try cgen_put(d, out, ");\n}\n")
        at = at + 2
    }
    return Ok(out)
}

fn cgen_fn_wrapper_name(d: Domain, initial: CgenWriter, target: U64, fn_type: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, " alder_fnwrap_")
    out = try cgen_put_u64(d, out, target - 1)
    out = try cgen_put(d, out, "_")
    return cgen_put_u64(d, out, fn_type - 1)
}

fn cgen_build(d: Domain, store: MirStore, indexes: MirVIndexes, verified: MirVerifyCompleteOutput) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder C11 backend. Do not edit. */\n/* Source: complete-verifier-gated Alder MIR 5. */\n#include \"alder.h\"\n")
    if verified.hosted { out = try cgen_put(d, out, "#include \"alder_host.h\"\n") }
    out = try cgen_put(d, out, "#include <float.h>\n#include <string.h>\n\n")
    out = try cgen_emit_types(d, out, store)
    out = try cgen_emit_constants(d, out, store)
    out = try cgen_emit_functions(d, out, store, indexes)
    out = try cgen_emit_imports(d, out, store)
    out = try cgen_emit_cleanup_sites(d, out, store, indexes)
    out = try cgen_emit_copy_helpers(d, out, store, indexes)
    let fn_value_sites = try cgen_fn_value_sites(d, store, indexes)
    out = try cgen_emit_fn_value_wrappers(d, out, store, indexes, fn_value_sites)
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
