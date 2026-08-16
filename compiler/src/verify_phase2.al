fn mir_vappend_type_children(d: Domain, store: MirStore, indexes: MirVIndexes, work: __s0_Buffer(U64), id: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    if !mir_vtype_exists(store, id) { return Ok(work) }
    var out = work
    let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() { out = try __s0_buffer_append(U64, d, out, t.elem) }
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
    return Ok(out)
}
fn mir_vtype_has_forbidden(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64) -> Result(U64, __s0_Error) {
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    // O(1) visited probe instead of a linear seen scan; the type graph is
    // dense enough on the self-compile corpus that the scan dominated phase 2.
    let tcount = __s0_buffer_len(MirTypeRec, store.types)
    var seen = __s0_alloc(U64, d, tcount + 1)
    var z: U64 = 0
    while z <= tcount { seen[z] = 0
        z = z + 1 }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        if id >= 1 && id <= tcount && seen[id] == 0 {
            seen[id] = 1
            let kind = mir_vtype_kind(store, id)
            if kind == mir_type_kind_table_view() || kind == mir_type_kind_table_mut_view() || kind == mir_type_kind_cleanup_scope() || kind == mir_type_kind_cleanup_id() { return Ok(kind + 1) }
            work = try mir_vappend_type_children(d, store, indexes, work, id)
        }
        at = at + 1
    }
    return Ok(0)
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
    if t == mir_type_u64() { return value >= 0 }
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
        if (t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view()) && !mir_vtype_exists(store, t.elem) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, id, id, 0, 0, t.elem)) }
        if t.kind == mir_type_kind_result() && (!mir_vtype_exists(store, t.ok_type) || !mir_vtype_exists(store, t.err_type)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, id, id, 0, 0, t.ok_type)) }
        if t.kind == mir_type_kind_function() && !mir_vtype_exists(store, t.result_type) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_signature(), 0, 0, 0, 0, 0, id, id, 0, 0, t.result_type)) }
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
        if !mir_vtype_exists(store, p.owner) || !mir_vtype_exists(store, p.part_type) || p.kind < mir_type_part_field() || p.kind > mir_type_part_function_param() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, p.owner, at + 1, 0, p.kind, p.part_type)) }
        if p.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), 0, 0, 0, 0, 0, p.owner, at + 1, expected, p.ordinal, 0)) }
        if p.kind != mir_type_part_function_param() {
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
        if c.kind == mir_const_string() { valid = valid && mir_vtype_kind(store, c.const_type) == mir_type_kind_slice() && __s0_buffer_get(MirTypeRec, store.types, c.const_type - 1).elem == mir_type_u8() && mir_vrange_valid(c.string_start, c.string_end, __s0_buffer_len(U8, store.names)) }
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
