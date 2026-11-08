// Stable C names, declaration safety checks, and MIR type layout emission.

type CgenTypeState {
    writer: CgenWriter
    emitted: __s0_Buffer(U64)
}

fn cgen_put_type(d: Domain, writer: CgenWriter, store: MirStore, id: U64) -> Result(CgenWriter, __s0_Error) {
    if id == mir_type_unit() || id == mir_type_u8() { return cgen_put(d, writer, "uint8_t") }
    if id == mir_type_bool() { return cgen_put(d, writer, "bool") }
    if id == mir_type_i8() { return cgen_put(d, writer, "int8_t") }
    if id == mir_type_i16() { return cgen_put(d, writer, "int16_t") }
    if id == mir_type_i32() { return cgen_put(d, writer, "int32_t") }
    if id == mir_type_i64() { return cgen_put(d, writer, "int64_t") }
    if id == mir_type_u16() { return cgen_put(d, writer, "uint16_t") }
    if id == mir_type_u32() { return cgen_put(d, writer, "uint32_t") }
    if id == mir_type_u64() { return cgen_put(d, writer, "uint64_t") }
    if id == mir_type_f32() { return cgen_put(d, writer, "float") }
    if id == mir_type_f64() { return cgen_put(d, writer, "double") }
    let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() || t.kind == mir_type_kind_option() || t.kind == mir_type_kind_result() || t.kind == mir_type_kind_array() { let out = try cgen_put(d, writer, "AlderTy")
    return cgen_put_u64(d, out, id - 1) }
    if t.kind == mir_type_kind_string() { return cgen_put(d, writer, "AlderString") }
    if t.kind == mir_type_kind_bytes() { return cgen_put(d, writer, "AlderBytes") }
    if t.kind == mir_type_kind_vec() { return cgen_put(d, writer, "AlderVec") }
    if t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() { return cgen_put(d, writer, "AlderSlice") }
    if t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() { return cgen_put(d, writer, "void *") }
    if t.kind == mir_type_kind_function() { let out = try cgen_put(d, writer, "AlderFnTy")
    return cgen_put_u64(d, out, id - 1) }
    if t.kind == mir_type_kind_domain_handle() { return cgen_put(d, writer, "AlderDomain *") }
    if t.kind == mir_type_kind_domain_mark() { return cgen_put(d, writer, "AlderDomainMark") }
    if t.kind == mir_type_kind_cleanup_scope() { return cgen_put(d, writer, "AlderCleanupScope *") }
    if t.kind == mir_type_kind_cleanup_id() { return cgen_put(d, writer, "AlderCleanupId") }
    if t.kind == mir_type_kind_table() { return cgen_put(d, writer, "AlderTable *") }
    return cgen_put(d, writer, "AlderTableId")
}

fn cgen_emitted(ids: __s0_Buffer(U64), id: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(U64, ids) {
        if __s0_buffer_get(U64, ids, at) == id { return true }
        at = at + 1
    }
    return false
}

fn cgen_type_part(store: MirStore, owner: U64, kind: U64, ordinal: U64) -> MirTypePartRec {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if part.owner == owner && part.kind == kind && part.ordinal == ordinal { return part }
        at = at + 1
    }
    return __s0_buffer_get(MirTypePartRec, store.type_parts, 0)
}

fn cgen_emit_type(d: Domain, initial: CgenTypeState, store: MirStore, id: U64) -> Result(CgenTypeState, __s0_Error) {
    if id <= mir_primitive_type_count() || cgen_emitted(initial.emitted, id) { return Ok(initial) }
    var state = initial
    let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if t.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, id, kind) {
            state = try cgen_emit_type(d, state, store, cgen_type_part(store, id, kind, ordinal).part_type)
            ordinal = ordinal + 1
        }
    }
    if t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() || t.kind == mir_type_kind_array() { state = try cgen_emit_type(d, state, store, t.elem) }
    if t.kind == mir_type_kind_result() { state = try cgen_emit_type(d, state, store, t.ok_type)
    state = try cgen_emit_type(d, state, store, t.err_type) }
    if t.kind == mir_type_kind_function() {
        let param_count = mir_type_part_count(store, id, mir_type_part_function_param())
        var ordinal: U64 = 0
        while ordinal < param_count { state = try cgen_emit_type(d, state, store, cgen_type_part(store, id, mir_type_part_function_param(), ordinal).part_type)
        ordinal = ordinal + 1 }
        state = try cgen_emit_type(d, state, store, t.result_type)
        if mir_type_part_count(store, id, mir_type_part_function_env()) != 0 { state = try cgen_emit_type(d, state, store, cgen_type_part(store, id, mir_type_part_function_env(), 0).part_type) }
    }
    var writer = state.writer
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() || t.kind == mir_type_kind_option() || t.kind == mir_type_kind_result() || t.kind == mir_type_kind_array() { writer = try cgen_emit_struct(d, writer, store, id, t) }
    if t.kind == mir_type_kind_function() { writer = try cgen_emit_function_type(d, writer, store, id, t) }
    let emitted = try __s0_buffer_append(U64, d, state.emitted, id)
    return Ok(CgenTypeState(writer: writer, emitted: emitted))
}

fn cgen_emit_function_type(d: Domain, initial: CgenWriter, store: MirStore, id: U64, t: MirTypeRec) -> Result(CgenWriter, __s0_Error) {
    // A function value is {code, env, retain}; the code pointer takes the
    // declared parameters plus the opaque environment pointer. The retain
    // hook materializes a complete environment in a destination domain for
    // copy_to_domain: a closure's environment record, or the destination
    // domain itself for a named function value's captured domain.
    var out = try cgen_put(d, initial, "typedef struct AlderFnTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, " AlderFnTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, ";\ntypedef ")
    if t.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, t.result_type) }
    out = try cgen_put(d, out, " (*AlderFnTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, "_code)(")
    let param_count = mir_type_part_count(store, id, mir_type_part_function_param())
    var ordinal: U64 = 0
    var wrote = false
    while ordinal < param_count {
        let part = cgen_type_part(store, id, mir_type_part_function_param(), ordinal)
        if part.part_type != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            out = try cgen_put_type(d, out, store, part.part_type)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    if wrote { out = try cgen_put(d, out, ", ") }
    out = try cgen_put(d, out, "void *alder_env);\nstruct AlderFnTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, " { AlderFnTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, "_code code; void *env; void *(*retain)(AlderDomain *, void *); };\n")
    return Ok(out)
}

fn cgen_emit_struct(d: Domain, initial: CgenWriter, store: MirStore, id: U64, t: MirTypeRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() { out = try cgen_put(d, out, "/* @")
    out = try cgen_put_name(d, out, store, t.name_start, t.name_end)
    out = try cgen_put(d, out, " */\n") }
    out = try cgen_put(d, out, "struct AlderTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, " {\n")
    if t.kind == mir_type_kind_array() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_type(d, out, store, t.elem)
        out = try cgen_put(d, out, " alder_e[")
        var storage = t.length
        if storage == 0 { storage = 1 }
        out = try cgen_put_u64(d, out, storage)
        out = try cgen_put(d, out, "];\n")
    } else { if t.kind == mir_type_kind_aggregate() {
        let count = mir_type_part_count(store, id, mir_type_part_field())
        if count == 0 { out = try cgen_put(d, out, "  uint8_t alder_empty;\n") }
        var ordinal: U64 = 0
        while ordinal < count {
            let part = cgen_type_part(store, id, mir_type_part_field(), ordinal)
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_type(d, out, store, part.part_type)
            out = try cgen_put(d, out, " alder_f")
            out = try cgen_put_u64(d, out, ordinal)
            out = try cgen_put(d, out, ";\n")
            ordinal = ordinal + 1
        }
    } else {
        var payloads: U64 = 0
        var count: U64 = 2
        var kind = mir_type_part_variant()
        if t.kind == mir_type_kind_enum() { count = mir_type_part_count(store, id, kind) }
        var ordinal: U64 = 0
        while ordinal < count {
            var payload = mir_type_unit()
            if t.kind == mir_type_kind_enum() { payload = cgen_type_part(store, id, kind, ordinal).part_type }
            if t.kind == mir_type_kind_option() && ordinal == 1 { payload = t.elem }
            if t.kind == mir_type_kind_result() && ordinal == 0 { payload = t.ok_type }
            if t.kind == mir_type_kind_result() && ordinal == 1 { payload = t.err_type }
            if payload != mir_type_unit() { payloads = payloads + 1 }
            ordinal = ordinal + 1
        }
        if payloads > 0 {
            out = try cgen_put(d, out, "  union {\n")
            ordinal = 0
            while ordinal < count {
                var payload = mir_type_unit()
                if t.kind == mir_type_kind_enum() { payload = cgen_type_part(store, id, kind, ordinal).part_type }
                if t.kind == mir_type_kind_option() && ordinal == 1 { payload = t.elem }
                if t.kind == mir_type_kind_result() && ordinal == 0 { payload = t.ok_type }
                if t.kind == mir_type_kind_result() && ordinal == 1 { payload = t.err_type }
                if payload != mir_type_unit() { out = try cgen_put(d, out, "    ")
                out = try cgen_put_type(d, out, store, payload)
                out = try cgen_put(d, out, " alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ";\n") }
                ordinal = ordinal + 1
            }
            out = try cgen_put(d, out, "  } alder_u;\n")
        }
        out = try cgen_put(d, out, "  uint32_t alder_tag;\n")
    } }
    return cgen_put(d, out, "};\n")
}

fn cgen_emit_types(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = mir_primitive_type_count()
    var has_string = false
    var has_bytes = false
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let kind = __s0_buffer_get(MirTypeRec, store.types, at).kind
        if kind == mir_type_kind_string() { has_string = true }
        if kind == mir_type_kind_bytes() { has_bytes = true }
        at = at + 1
    }
    if has_string {
        out = try cgen_put(d, out, "typedef struct { const uint8_t *data; uint64_t len; } AlderString;\n")
        out = try cgen_put(d, out, "static bool ALDER_MAYBE_UNUSED alder_string_eq(AlderString alder_a, AlderString alder_b) {\n")
        out = try cgen_put(d, out, "  if (alder_a.len != alder_b.len) { return false; }\n")
        out = try cgen_put(d, out, "  return alder_a.len == UINT64_C(0) || memcmp(alder_a.data, alder_b.data, (size_t)alder_a.len) == 0;\n")
        out = try cgen_put(d, out, "}\n")
    }
    if has_bytes {
        out = try cgen_put(d, out, "typedef struct { const uint8_t *data; uint64_t len; } AlderBytes;\n")
        out = try cgen_put(d, out, "static bool ALDER_MAYBE_UNUSED alder_bytes_eq(AlderBytes alder_a, AlderBytes alder_b) {\n")
        out = try cgen_put(d, out, "  if (alder_a.len != alder_b.len) { return false; }\n")
        out = try cgen_put(d, out, "  return alder_a.len == UINT64_C(0) || memcmp(alder_a.data, alder_b.data, (size_t)alder_a.len) == 0;\n")
        out = try cgen_put(d, out, "}\n")
    }
    if has_string || has_bytes { out = try cgen_put(d, out, "\n") }
    at = mir_primitive_type_count()
    var records = false
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() || t.kind == mir_type_kind_option() || t.kind == mir_type_kind_result() || t.kind == mir_type_kind_array() { out = try cgen_put(d, out, "typedef struct AlderTy")
        out = try cgen_put_u64(d, out, at)
        out = try cgen_put(d, out, " AlderTy")
        out = try cgen_put_u64(d, out, at)
        out = try cgen_put(d, out, ";\n")
        records = true }
        at = at + 1
    }
    if records { out = try cgen_put(d, out, "\n") }
    let emitted = try __s0_buffer_new(U64, d)
    var state = CgenTypeState(writer: out, emitted: emitted)
    at = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        state = try cgen_emit_type(d, state, store, at + 1)
        at = at + 1
    }
    return Ok(state.writer)
}
