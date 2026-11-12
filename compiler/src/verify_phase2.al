fn mir_vutf8_continuation(value: U8) -> Bool { return value >= 128 && value <= 191 }

fn mir_vutf8_valid(values: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        let first = __s0_buffer_get(U8, values, at)
        if first < 128 { at = at + 1 }
        else { if first >= 194 && first <= 223 && at + 1 < end && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 1)) { at = at + 2 }
        else { if first == 224 && at + 2 < end && __s0_buffer_get(U8, values, at + 1) >= 160 && __s0_buffer_get(U8, values, at + 1) <= 191 && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 2)) { at = at + 3 }
        else { if ((first >= 225 && first <= 236) || (first >= 238 && first <= 239)) && at + 2 < end && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 1)) && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 2)) { at = at + 3 }
        else { if first == 237 && at + 2 < end && __s0_buffer_get(U8, values, at + 1) >= 128 && __s0_buffer_get(U8, values, at + 1) <= 159 && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 2)) { at = at + 3 }
        else { if first == 240 && at + 3 < end && __s0_buffer_get(U8, values, at + 1) >= 144 && __s0_buffer_get(U8, values, at + 1) <= 191 && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 2)) && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 3)) { at = at + 4 }
        else { if first >= 241 && first <= 243 && at + 3 < end && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 1)) && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 2)) && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 3)) { at = at + 4 }
        else { if first == 244 && at + 3 < end && __s0_buffer_get(U8, values, at + 1) >= 128 && __s0_buffer_get(U8, values, at + 1) <= 143 && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 2)) && mir_vutf8_continuation(__s0_buffer_get(U8, values, at + 3)) { at = at + 4 }
        else { return false } } } } } } } }
    }
    return true
}

fn mir_vappend_type_children(d: Domain, store: MirStore, indexes: MirVIndexes, work: __s0_Buffer(U64), id: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    if !mir_vtype_exists(store, id) { return Ok(work) }
    var out = work
    let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() || t.kind == mir_type_kind_array() || t.kind == mir_type_kind_vec() { out = try __s0_buffer_append(U64, d, out, t.elem) }
    if t.kind == mir_type_kind_result() { out = try __s0_buffer_append(U64, d, out, t.ok_type)
out = try __s0_buffer_append(U64, d, out, t.err_type) }
    // Function parameter parts are the owner's type-part list filtered to the
    // function-parameter kind; the index list is in ascending store order.
    if t.kind == mir_type_kind_function() { let count = mir_vindex_type_part_count(indexes, id)
var p: U64 = 0
while p < count { let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, id, p) - 1)
if part.kind == mir_type_part_function_param() { out = try __s0_buffer_append(U64, d, out, part.part_type) }
p = p + 1 }
out = try __s0_buffer_append(U64, d, out, t.result_type) }
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() { let count = mir_vindex_type_part_count(indexes, id)
var p: U64 = 0
while p < count { out = try __s0_buffer_append(U64, d, out, __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, id, p) - 1).part_type)
p = p + 1 } }
    if t.kind == mir_type_kind_c_ptr() || t.kind == mir_type_kind_c_const_ptr() { out = try __s0_buffer_append(U64, d, out, t.elem) }
    if t.kind == mir_type_kind_c_named() && t.c_class == mir_c_class_record() { let count = mir_vindex_type_part_count(indexes, id)
var p: U64 = 0
while p < count { let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, id, p) - 1)
if part.kind == mir_type_part_c_field() { out = try __s0_buffer_append(U64, d, out, part.part_type) }
p = p + 1 } }
    return Ok(out)
}
fn mir_vtype_has_forbidden(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64) -> Result(U64, __s0_Error) {
    // The verdict per root is a pure function of the frozen type graph; the
    // memo records the first forbidden kind each walk reports, so results are
    // unchanged while repeat walks disappear.
    return mir_vmemo_forbidden(d, store, indexes, root)
}
// A c_field part is valid only on a c_named type with the record class;
// opaque and other classes carry no record fields.
fn mir_vpart_c_field_owner_ok(store: MirStore, owner: U64) -> Bool {
    let rec = __s0_buffer_get(MirTypeRec, store.types, owner - 1)
    return rec.kind == mir_type_kind_c_named() && rec.c_class == mir_c_class_record()
}

fn mir_vtype_cycles(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64) -> Result(Bool, __s0_Error) {
    var work = try __s0_buffer_new(U64, d)
    work = try mir_vappend_type_children(d, store, indexes, work, root)
    let tcount = __s0_buffer_len(MirTypeRec, store.types)
    var seen = __s0_alloc(U64, d, tcount + 1)
    var z: U64 = 0
    while z <= tcount { seen[z] = 0
        z = z + 1 }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        if id == root { return Ok(true) }
        if id >= 1 && id <= tcount && seen[id] == 0 {
            seen[id] = 1
            work = try mir_vappend_type_children(d, store, indexes, work, id)
        }
        at = at + 1
    }
    return Ok(false)
}
fn mir_vint_fits(t: U64, value: I64) -> Bool {
    if t == mir_type_i8() { return value >= -128 && value <= 127 }
    if t == mir_type_i16() { return value >= -32768 && value <= 32767 }
    if t == mir_type_i32() { return value >= -2147483648 && value <= 2147483647 }
    if t == mir_type_i64() { return true }
    if t == mir_type_u8() { return value >= 0 && value <= 255 }
    if t == mir_type_u16() { return value >= 0 && value <= 65535 }
    if t == mir_type_u32() { return value >= 0 && value <= 4294967295 }
    if t == mir_type_u64() { return true }
    return false
}
fn mir_vfloat_finite(bits: U64) -> Bool { return (bits / 4503599627370496) % 2048 != 2047 }
fn mir_vfloat_exact_f32(bits: U64) -> Bool {
    let exponent = (bits / 4503599627370496) % 2048
    let fraction = bits % 4503599627370496
    if exponent == 0 { return fraction == 0 }
    if exponent < 874 || exponent > 1150 { return false }
    var trailing: U64 = 29
    if exponent < 897 {
        let normal_min: U64 = 897
        trailing = trailing + (normal_min - exponent)
    }
    var divisor: U64 = 1
var at: U64 = 0
    while at < trailing { divisor = divisor * 2
at = at + 1 }
    return fraction % divisor == 0
}
// A function that carries domain handles pairs every safe_mut parameter with
// the owner domain parameter that follows it. Functions outside the storage
// model have no domain parameter and need no owner.
fn mir_v2_param_is_env(store: MirStore, indexes: MirVIndexes, function: U64, ordinal: U64) -> Bool {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let parameter = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if parameter.kind == mir_param_function() && parameter.ordinal == ordinal { return mir_vname_word(store, parameter.name_start, parameter.name_end, "alder_env") }
        at = at + 1
    }
    return false
}

fn mir_v2_owner_pairs(store: MirStore, indexes: MirVIndexes, function: U64) -> Bool {
    let count = mir_v5_function_param_count(store, indexes, function)
    var has_domain = false
    var at: U64 = 0
    while at < count {
        let parameter_type = mir_v5_param_type(store, indexes, function, 0, mir_param_function(), at)
        if mir_vtype_kind(store, parameter_type) == mir_type_kind_domain_handle() { has_domain = true }
        at = at + 1
    }
    if !has_domain { return true }
    at = 0
    while at < count {
        let parameter_type = mir_v5_param_type(store, indexes, function, 0, mir_param_function(), at)
        if mir_vtype_kind(store, parameter_type) == mir_type_kind_safe_mut() && !mir_v2_param_is_env(store, indexes, function, at) {
            if at + 1 >= count { return false }
            let owner_type = mir_v5_param_type(store, indexes, function, 0, mir_param_function(), at + 1)
            if mir_vtype_kind(store, owner_type) != mir_type_kind_domain_handle() { return false }
        }
        at = at + 1
    }
    return true
}

// Function types used by fn.value and call.value follow the same pairing, so
// an indirect call can pass the owner domain after its safe_mut argument.
fn mir_v2_function_type_owner_pairs(store: MirStore, indexes: MirVIndexes, type_id: U64) -> Bool {
    let total = mir_vindex_type_part_count(indexes, type_id)
    var has_domain = false
    var at: U64 = 0
    while at < total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if part.kind == mir_type_part_function_param() && mir_vtype_kind(store, part.part_type) == mir_type_kind_domain_handle() { has_domain = true }
        at = at + 1
    }
    if !has_domain { return true }
    var pending = false
    at = 0
    while at < total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if part.kind == mir_type_part_function_param() {
            let part_kind = mir_vtype_kind(store, part.part_type)
            if pending {
                if part_kind != mir_type_kind_domain_handle() { return false }
                pending = false
            } else {
                if part_kind == mir_type_kind_safe_mut() { pending = true }
            }
        }
        at = at + 1
    }
    return !pending
}

// A C export signature is a C ABI signature. It never carries a safe_mut
// parameter (and therefore never carries the owner domain paired with one).
fn mir_v2_export_safe(store: MirStore, indexes: MirVIndexes, function: U64) -> Bool {
    if !__s0_buffer_get(MirFunctionRec, store.functions, function - 1).c_export { return true }
    let count = mir_v5_function_param_count(store, indexes, function)
    var at: U64 = 0
    while at < count {
        let parameter_type = mir_v5_param_type(store, indexes, function, 0, mir_param_function(), at)
        if mir_vtype_kind(store, parameter_type) == mir_type_kind_safe_mut() { return false }
        at = at + 1
    }
    return true
}

fn mir_vdecl_type(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), function: U64, block: U64, declaration: U64, type_id: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var result = out
    if !mir_vtype_exists(store, type_id) { return mir_vadd(d, result, mir_vdiag(mir_verify_phase_types(), mir_vdiag_bad_signature(), function, block, 0, 0, 0, type_id, declaration, 0, 0, type_id)) }
    let forbidden = try mir_vtype_has_forbidden(d, store, indexes, type_id)
    if forbidden != 0 { result = try mir_vadd(d, result, mir_vdiag(mir_verify_phase_types(), mir_vdiag_ephemeral_type(), function, block, 0, 0, 0, type_id, declaration, 0, forbidden - 1, type_id)) }
    return Ok(result)
}
fn mir_vphase2(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_types()
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let id = at + 1
let t = __s0_buffer_get(MirTypeRec, store.types, at)
        if try mir_vtype_cycles(d, store, indexes, id) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_type_cycle(), 0, 0, 0, 0, 0, id, id, 0, 0, id)) }
        if t.kind == mir_type_kind_enum() { let part_total = mir_vindex_type_part_count(indexes, id)
var variant_count: U64 = 0
var pv: U64 = 0
while pv < part_total { if __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, id, pv) - 1).kind == mir_type_part_variant() { variant_count = variant_count + 1 }
pv = pv + 1 }
if variant_count == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_empty_enum(), 0, 0, 0, 0, 0, id, id, 1, 0, 0)) } }
        if (t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() || t.kind == mir_type_kind_array() || t.kind == mir_type_kind_vec()) && !mir_vtype_exists(store, t.elem) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, id, id, 0, 0, t.elem)) }
        if t.kind == mir_type_kind_result() && (!mir_vtype_exists(store, t.ok_type) || !mir_vtype_exists(store, t.err_type)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, id, id, 0, 0, t.ok_type)) }
        if t.kind == mir_type_kind_function() && !mir_vtype_exists(store, t.result_type) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_signature(), 0, 0, 0, 0, 0, id, id, 0, 0, t.result_type)) }
        if t.kind == mir_type_kind_function() && !mir_v2_function_type_owner_pairs(store, indexes, id) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_signature(), 0, 0, 0, 0, 0, id, id, 0, 0, id)) }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let p = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
var expected: U64 = 0
var scan: U64 = 0
        while scan < at { let q = __s0_buffer_get(MirTypePartRec, store.type_parts, scan)
if q.owner == p.owner && q.kind == p.kind { expected = expected + 1 }
scan = scan + 1 }
        if !mir_vtype_exists(store, p.owner) || !mir_vtype_exists(store, p.part_type) || p.kind < mir_type_part_field() || (p.kind > mir_type_part_function_env() && p.kind != mir_type_part_c_field()) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, p.owner, at + 1, 0, p.kind, p.part_type)) }
        else {
            if p.kind == mir_type_part_c_field() {
                if !mir_vpart_c_field_owner_ok(store, p.owner) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, p.owner, at + 1, 0, p.kind, p.part_type)) }
            }
        }
        if p.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), 0, 0, 0, 0, 0, p.owner, at + 1, expected, p.ordinal, 0)) }
        if p.kind != mir_type_part_function_param() && p.kind != mir_type_part_function_env() {
            if !mir_vname_valid(store, p.name_start, p.name_end, true) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), 0, 0, 0, 0, 0, p.owner, at + 1, 0, 0, 0)) }
            if p.kind == mir_type_part_variant() && mir_vname_word(store, p.name_start, p.name_end, "default") { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_reserved_member(), 0, 0, 0, 0, 0, p.owner, at + 1, 0, 0, 0)) }
            scan = 0
            while scan < at { let q = __s0_buffer_get(MirTypePartRec, store.type_parts, scan)
if q.owner == p.owner && q.kind == p.kind && mir_vname_equal(store, p.name_start, p.name_end, q.name_start, q.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_member(), 0, 0, 0, 0, 0, p.owner, at + 1, 0, 0, scan + 1))
scan = at }
scan = scan + 1 }
        }
        out = try mir_vdecl_type(d, store, indexes, out, 0, 0, at + 1, p.part_type)
        at = at + 1
    }
    // Constants retain exact bit-level payloads.
    at = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let c = __s0_buffer_get(MirConstRec, store.constants, at)
var valid = mir_vtype_exists(store, c.const_type) && c.kind <= mir_const_string()
        if c.kind == mir_const_unit() { valid = valid && c.const_type == mir_type_unit() }
        if c.kind == mir_const_bool() { valid = valid && c.const_type == mir_type_bool() && c.bool_value <= 1 }
        if c.kind == mir_const_int() { valid = valid && mir_vint_fits(c.const_type, c.int_value) }
        if c.kind == mir_const_float() { valid = valid && (c.const_type == mir_type_f32() || c.const_type == mir_type_f64()) && mir_vfloat_finite(c.float_bits)
if c.const_type == mir_type_f32() { valid = valid && mir_vfloat_exact_f32(c.float_bits) } }
        if c.kind == mir_const_string() {
            let type_kind = mir_vtype_kind(store, c.const_type)
            let bootstrap_string = type_kind == mir_type_kind_slice() && __s0_buffer_get(MirTypeRec, store.types, c.const_type - 1).elem == mir_type_u8()
            valid = valid && (type_kind == mir_type_kind_string() || type_kind == mir_type_kind_bytes() || bootstrap_string) && mir_vrange_valid(c.string_start, c.string_end, __s0_buffer_len(U8, store.names))
            if valid && type_kind == mir_type_kind_string() { valid = mir_vutf8_valid(store.names, c.string_start, c.string_end) }
        }
        if !valid { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_constant(), 0, 0, 0, 0, 0, c.const_type, at + 1, 0, c.kind, 0)) }
        at = at + 1
    }
    // Import and function signatures, locals, parameters, and block parameters.
    at = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) { let item = __s0_buffer_get(MirImportRec, store.imports, at)
out = try mir_vdecl_type(d, store, indexes, out, 0, 0, at + 1, item.result_type)
at = at + 1 }
    at = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) { let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
out = try mir_vdecl_type(d, store, indexes, out, at + 1, 0, at + 1, item.result_type)
if mir_vtype_kind(store, item.result_type) == mir_type_kind_domain_handle() || mir_vtype_kind(store, item.result_type) == mir_type_kind_domain_mark() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_domain_result(), at + 1, 0, 0, 0, 0, item.result_type, at + 1, 0, 0, 0)) }
if !mir_v2_owner_pairs(store, indexes, at + 1) || !mir_v2_export_safe(store, indexes, at + 1) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_signature(), at + 1, 0, 0, 0, 0, 0, at + 1, 0, 0, at + 1)) }
at = at + 1 }
    at = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, at)
if o.kind == mir_operand_import_param() { out = try mir_vdecl_type(d, store, indexes, out, 0, 0, at + 1, o.operand_type) }
at = at + 1 }
    at = 0
    while at < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, at)
out = try mir_vdecl_type(d, store, indexes, out, p.function, p.block, at + 1, p.param_type)
at = at + 1 }
    at = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) { let l = __s0_buffer_get(MirLocalRec, store.locals, at)
out = try mir_vdecl_type(d, store, indexes, out, l.function, 0, at + 1, l.local_type)
at = at + 1 }
    return Ok(out)
}
