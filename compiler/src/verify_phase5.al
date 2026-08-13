// Phase 5 is deliberately a pure checker.  V1--V4 have already established
// record ownership, references, ordinals, result reciprocity, and CFG shape.
type MirVTypeResult {
    valid: Bool
    type_id: U64
}

fn mir_v5_value_type(store: MirStore, function: U64, value: U64) -> U64 {
    let at = mir_vvalue_index(store, function, value)
    if at == 0 { return 0 }
    return __s0_buffer_get(MirValueRec, store.values, at - 1).value_type
}
fn mir_v5_is_int(t: U64) -> Bool { return t >= mir_type_i8() && t <= mir_type_u64() }
fn mir_v5_is_float(t: U64) -> Bool { return t == mir_type_f32() || t == mir_type_f64() }
fn mir_v5_is_enum(store: MirStore, t: U64) -> Bool { let k = mir_vtype_kind(store, t)
return k == mir_type_kind_enum() || k == mir_type_kind_option() || k == mir_type_kind_result() }
fn mir_v5_width(t: U64) -> U64 { if t == mir_type_i8() || t == mir_type_u8() { return 8 }
if t == mir_type_i16() || t == mir_type_u16() { return 16 }
if t == mir_type_i32() || t == mir_type_u32() { return 32 }
if t == mir_type_i64() || t == mir_type_u64() { return 64 }
return 0 }
fn mir_v5_signed(t: U64) -> Bool { return t >= mir_type_i8() && t <= mir_type_i64() }
fn mir_v5_elem(store: MirStore, t: U64) -> U64 { let k = mir_vtype_kind(store, t)
if k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() { return __s0_buffer_get(MirTypeRec, store.types, t - 1).elem }
return 0 }
fn mir_v5_find_unary(store: MirStore, kind: U64, elem: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirTypeRec, store.types) { let t = __s0_buffer_get(MirTypeRec, store.types, at)
if t.kind == kind && t.elem == elem { return at + 1 }
at = at + 1 }
return 0 }
fn mir_v5_find_kind(store: MirStore, kind: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirTypeRec, store.types) { if __s0_buffer_get(MirTypeRec, store.types, at).kind == kind { return at + 1 }
at = at + 1 }
return 0 }
fn mir_v5_const_type(store: MirStore, start: U64, end: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirConstRec, store.constants) { let c = __s0_buffer_get(MirConstRec, store.constants, at)
if mir_vname_equal(store, start, end, c.name_start, c.name_end) { return c.const_type }
at = at + 1 }
return 0 }
fn mir_v5_param_type(store: MirStore, function: U64, block: U64, kind: U64, ordinal: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, at)
if p.function == function && p.block == block && p.kind == kind && p.ordinal == ordinal { return p.param_type }
at = at + 1 }
return 0 }
fn mir_v5_operand(store: MirStore, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, at)
if o.kind == kind && o.owner == owner && o.edge == edge && o.ordinal == ordinal { return at + 1 }
at = at + 1 }
return 0 }

fn mir_v5_place_type(store: MirStore, function: U64, place: U64) -> MirVTypeResult {
    if place == 0 || place > __s0_buffer_len(MirPlaceRec, store.places) { return MirVTypeResult(valid: false, type_id: 0) }
    let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if p.function != function { return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_local() { let li = mir_vlocal_index(store, function, p.local)
if li == 0 { return MirVTypeResult(valid: false, type_id: 0) }
return MirVTypeResult(valid: true, type_id: __s0_buffer_get(MirLocalRec, store.locals, li - 1).local_type) }
    if p.kind == mir_place_deref() { let t = mir_v5_value_type(store, function, p.deref_value)
let k = mir_vtype_kind(store, t)
if k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_table_view() || k == mir_type_kind_table_mut_view() { return MirVTypeResult(valid: true, type_id: __s0_buffer_get(MirTypeRec, store.types, t - 1).elem) }
return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_field() { let base = mir_v5_place_type(store, function, p.base)
if !base.valid || mir_vtype_kind(store, base.type_id) != mir_type_kind_aggregate() { return MirVTypeResult(valid: false, type_id: 0) }
var at: U64 = 0
while at < __s0_buffer_len(MirTypePartRec, store.type_parts) { let f = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
if f.owner == base.type_id && f.kind == mir_type_part_field() && mir_vname_equal(store, p.field_start, p.field_end, f.name_start, f.name_end) { return MirVTypeResult(valid: true, type_id: f.part_type) }
at = at + 1 }
    }
    return MirVTypeResult(valid: false, type_id: 0)
}
fn mir_v5_place_mutable(store: MirStore, function: U64, place: U64) -> Bool { if place == 0 || place > __s0_buffer_len(MirPlaceRec, store.places) { return false }
let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if p.kind == mir_place_local() { return true }
if p.kind == mir_place_field() { return mir_v5_place_mutable(store, function, p.base) }
if p.kind == mir_place_deref() { let k = mir_vtype_kind(store, mir_v5_value_type(store, function, p.deref_value))
return k == mir_type_kind_safe_mut() || k == mir_type_kind_table_mut_view() }
return false }

fn mir_v5_bad(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, f: U64, b: U64, i: U64, t: U64, o: U64, expected: U64, actual: U64, reference: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    return mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), kind, f, b, i, t, o, actual, 0, expected, actual, reference))
}
fn mir_v5_expect(d: Domain, store: MirStore, out: __s0_Buffer(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, operand: U64, value: U64, want: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { let got = mir_v5_value_type(store, f, value)
if got != want { return mir_v5_bad(d, out, mir_vdiag_bad_operand_type(), f, b, i, t, operand, want, got, value) }
return Ok(out) }
fn mir_v5_edge(d: Domain, store: MirStore, out: __s0_Buffer(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, kind: U64, owner: U64, edge: U64, target: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
let count = mir_vcount_operands(store, kind, owner, edge)
var n: U64 = 0
while n < count { let oi = mir_v5_operand(store, kind, owner, edge, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
result = try mir_v5_expect(d, store, result, f, b, i, t, oi, o.value, mir_v5_param_type(store, f, target, mir_param_block(), n))
n = n + 1 }
return Ok(result) }

fn mir_v5_args_match(store: MirStore, function: U64, instruction: U64, target: U64, import_call: Bool) -> Bool {
    let got = mir_vcount_operands(store, mir_operand_instruction(), instruction, 0)
    var want: U64 = 0
    if import_call { want = mir_vcount_operands(store, mir_operand_import_param(), target, 0) } else { want = mir_vcount_params(store, target, 0, mir_param_function()) }
    if got != want { return false }
    var ordinal: U64 = 0
    while ordinal < got {
        let argument = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, mir_operand_instruction(), instruction, 0, ordinal) - 1)
        var expected: U64 = 0
        if import_call { expected = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, mir_operand_import_param(), target, 0, ordinal) - 1).operand_type } else { expected = mir_v5_param_type(store, target, 0, mir_param_function(), ordinal) }
        if mir_v5_value_type(store, function, argument.value) != expected { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_aggregate_matches(store: MirStore, function: U64, instruction: U64, type_id: U64) -> Bool {
    if mir_vtype_kind(store, type_id) != mir_type_kind_aggregate() { return false }
    let count = mir_vcount_operands(store, mir_operand_aggregate_field(), instruction, 0)
    if count != mir_vcount_type_parts(store, type_id, mir_type_part_field()) { return false }
    var ordinal: U64 = 0
    while ordinal < count {
        let field = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, mir_operand_aggregate_field(), instruction, 0, ordinal) - 1)
        var found: U64 = 0
        var at: U64 = 0
        while at < __s0_buffer_len(MirTypePartRec, store.type_parts) { let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
if part.owner == type_id && part.kind == mir_type_part_field() && mir_vname_equal(store, field.name_start, field.name_end, part.name_start, part.name_end) { found = part.part_type }
at = at + 1 }
        if found == 0 || mir_v5_value_type(store, function, field.value) != found { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_infer(store: MirStore, id: U64, x: MirInstrRec) -> MirVTypeResult {
    let ta = mir_v5_value_type(store, x.function, x.a)
    let tb = mir_v5_value_type(store, x.function, x.b)
    if x.op == mir_op_load() { return mir_v5_place_type(store, x.function, x.place) }
    if x.op == mir_op_aggregate_construct() { return MirVTypeResult(valid: mir_v5_aggregate_matches(store, x.function, id, x.type_op), type_id: x.type_op) }
    if x.op == mir_op_domain_create() { return MirVTypeResult(valid: ta == mir_v5_find_kind(store, mir_type_kind_domain_handle()), type_id: mir_v5_find_kind(store, mir_type_kind_domain_handle())) }
    if x.op == mir_op_domain_mark() { return MirVTypeResult(valid: ta == mir_v5_find_kind(store, mir_type_kind_domain_handle()), type_id: mir_v5_find_kind(store, mir_type_kind_domain_mark())) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() { return MirVTypeResult(valid: ta == mir_v5_find_kind(store, mir_type_kind_domain_handle()) && tb == mir_type_u64(), type_id: mir_v5_find_unary(store, mir_type_kind_safe_mut(), x.type_op)) }
    if x.op == mir_op_copy_to_domain() { return MirVTypeResult(valid: ta == mir_v5_find_kind(store, mir_type_kind_domain_handle()), type_id: tb) }
    if x.op == mir_op_cleanup_scope_begin() { return MirVTypeResult(valid: true, type_id: mir_v5_find_kind(store, mir_type_kind_cleanup_scope())) }
    if x.op == mir_op_cleanup_push() { return MirVTypeResult(valid: ta == mir_v5_find_kind(store, mir_type_kind_cleanup_scope()) && __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type == mir_type_unit() && mir_v5_args_match(store, x.function, id, x.target, false), type_id: mir_v5_find_kind(store, mir_type_kind_cleanup_id())) }
    if x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: ta) }
    if x.op == mir_op_slice_len() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0, type_id: mir_type_u64()) }
    if x.op == mir_op_slice_index_checked() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0 && tb == mir_type_u64(), type_id: mir_v5_find_unary(store, mir_type_kind_safe_mut(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_slice_range_checked() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0 && tb == mir_type_u64() && mir_v5_value_type(store, x.function, x.c) == mir_type_u64(), type_id: mir_v5_find_unary(store, mir_type_kind_slice(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_enum_payload_checked() { let p = mir_vcase_payload(store, ta, x.name_start, x.name_end)
return MirVTypeResult(valid: mir_v5_is_enum(store, ta) && p != 0 && p != mir_type_unit(), type_id: p) }
    if x.op == mir_op_enum_construct() { let payload = mir_vcase_payload(store, x.type_op, x.name_start, x.name_end)
return MirVTypeResult(valid: mir_v5_is_enum(store, x.type_op) && payload != 0 && ((payload == mir_type_unit() && x.a == 0) || (payload != mir_type_unit() && ta == payload)), type_id: x.type_op) }
    if x.op == mir_op_table_create() { return MirVTypeResult(valid: ta == mir_v5_find_kind(store, mir_type_kind_domain_handle()), type_id: mir_v5_find_unary(store, mir_type_kind_table(), x.type_op)) }
    if x.op == mir_op_table_insert() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == elem, type_id: mir_v5_find_unary(store, mir_type_kind_id(), elem)) }
    if x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
var view_kind = mir_type_kind_table_view()
if x.op == mir_op_table_lookup_mut() { view_kind = mir_type_kind_table_mut_view() }
let view = mir_v5_find_unary(store, view_kind, elem)
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == mir_v5_find_unary(store, mir_type_kind_id(), elem), type_id: mir_v5_find_unary(store, mir_type_kind_option(), view)) }
    if x.op == mir_op_table_remove() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == mir_v5_find_unary(store, mir_type_kind_id(), elem), type_id: mir_type_bool()) }
    if x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { return MirVTypeResult(valid: mir_v5_is_float(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op == mir_op_int_trunc() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_zext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_sext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_float_convert() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_int_from_float() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_int(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_float_from_int() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_const_get() { let ct = mir_v5_const_type(store, x.name_start, x.name_end)
return MirVTypeResult(valid: ct != 0, type_id: ct) }
    if x.op == mir_op_call() { return MirVTypeResult(valid: mir_v5_args_match(store, x.function, id, x.target, false), type_id: __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type) }
    if x.op == mir_op_ffi_call_unsafe() { return MirVTypeResult(valid: mir_v5_args_match(store, x.function, id, x.target, true), type_id: __s0_buffer_get(MirImportRec, store.imports, x.target - 1).result_type) }
    return MirVTypeResult(valid: false, type_id: 0)
}

fn mir_v5_check_args(d: Domain, store: MirStore, out: __s0_Buffer(MirVerifyDiagRec), x: MirInstrRec, id: U64, target: U64, import_call: Bool) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
let got = mir_vcount_operands(store, mir_operand_instruction(), id, 0)
var want: U64 = 0
if import_call { want = mir_vcount_operands(store, mir_operand_import_param(), target, 0) } else { want = mir_vcount_params(store, target, 0, mir_param_function()) }
if got != want { return mir_v5_bad(d, result, mir_vdiag_bad_argument_count(), x.function, x.block, id, 0, 0, want, got, target) }
var n: U64 = 0
while n < got { let oi = mir_v5_operand(store, mir_operand_instruction(), id, 0, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
var expected: U64 = 0
if import_call { let pi = mir_v5_operand(store, mir_operand_import_param(), target, 0, n)
expected = __s0_buffer_get(MirOperandRec, store.operands, pi - 1).operand_type } else { expected = mir_v5_param_type(store, target, 0, mir_param_function(), n) }
result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, oi, o.value, expected)
n = n + 1 }
return Ok(result) }

fn mir_v5_instruction(d: Domain, store: MirStore, out: __s0_Buffer(MirVerifyDiagRec), id: U64, x: MirInstrRec) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var result = out
let baseline = __s0_buffer_len(MirVerifyDiagRec, out)
let handle = mir_v5_find_kind(store, mir_type_kind_domain_handle())
let mark = mir_v5_find_kind(store, mir_type_kind_domain_mark())
let scope = mir_v5_find_kind(store, mir_type_kind_cleanup_scope())
let cleanup_id = mir_v5_find_kind(store, mir_type_kind_cleanup_id())
    if x.op == mir_op_load() || x.op == mir_op_store() { let p = mir_v5_place_type(store, x.function, x.place)
if !p.valid { result = try mir_v5_bad(d, result, mir_vdiag_bad_place_type(), x.function, x.block, id, 0, x.place, 0, 0, x.place) } else { if x.op == mir_op_store() { if !mir_v5_place_mutable(store, x.function, x.place) { result = try mir_v5_bad(d, result, mir_vdiag_readonly_place(), x.function, x.block, id, 0, x.place, 0, p.type_id, x.place) }
result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, p.type_id) } } }
    if x.op == mir_op_aggregate_construct() { let fields = mir_vcount_type_parts(store, x.type_op, mir_type_part_field())
let got = mir_vcount_operands(store, mir_operand_aggregate_field(), id, 0)
if mir_vtype_kind(store, x.type_op) != mir_type_kind_aggregate() || got != fields { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, 0, fields, got, x.type_op) } else { var n: U64 = 0
while n < got { let oi = mir_v5_operand(store, mir_operand_aggregate_field(), id, 0, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
var pi: U64 = 0
while pi < __s0_buffer_len(MirTypePartRec, store.type_parts) { let p = __s0_buffer_get(MirTypePartRec, store.type_parts, pi)
if p.owner == x.type_op && p.kind == mir_type_part_field() && p.ordinal == n { if !mir_vname_equal(store, o.name_start, o.name_end, p.name_start, p.name_end) { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, oi, n, o.ordinal, pi + 1) }
result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, oi, o.value, p.part_type) }
pi = pi + 1 }
n = n + 1 } } }
    if x.op == mir_op_domain_create() || x.op == mir_op_domain_mark() || x.op == mir_op_domain_destroy() || x.op == mir_op_table_create() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, handle) }
    if x.op == mir_op_domain_reset() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, handle)
result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.b, mark) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, handle)
result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
    if x.op == mir_op_copy_to_domain() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, handle) }
    if x.op == mir_op_cleanup_push() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, scope)
result = try mir_v5_check_args(d, store, result, x, id, x.target, false)
if __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type != mir_type_unit() { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, mir_type_unit(), __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type, x.target) } }
    if x.op == mir_op_cleanup_disarm() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, cleanup_id) }
    if x.op == mir_op_cleanup_scope_run() || x.op == mir_op_cleanup_scope_end() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, scope) }
    if (x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked()) || (x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge()) { let ta = mir_v5_value_type(store, x.function, x.a)
let tb = mir_v5_value_type(store, x.function, x.b)
if !mir_v5_is_int(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { let ta = mir_v5_value_type(store, x.function, x.a)
let tb = mir_v5_value_type(store, x.function, x.b)
if !mir_v5_is_float(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op == mir_op_slice_len() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() { if mir_v5_elem(store, mir_v5_value_type(store, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_slice(), mir_vtype_kind(store, mir_v5_value_type(store, x.function, x.a)), x.a) }
if x.op != mir_op_slice_len() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
if x.op == mir_op_slice_range_checked() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) } }
    if x.op == mir_op_enum_payload_checked() || x.op == mir_op_enum_construct() { var et = mir_v5_value_type(store, x.function, x.a)
if x.op == mir_op_enum_construct() { et = x.type_op }
let payload = mir_vcase_payload(store, et, x.name_start, x.name_end)
if !mir_v5_is_enum(store, et) || payload == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_variant(), x.function, x.block, id, 0, 0, et, 0, et) } else { if x.op == mir_op_enum_construct() { if payload == mir_type_unit() && x.a != 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_variant(), x.function, x.block, id, 0, 0, 0, mir_v5_value_type(store, x.function, x.a), et) }
if payload != mir_type_unit() { result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.a, payload) } } } }
    if x.op >= mir_op_table_insert() && x.op <= mir_op_table_remove() { let table = mir_v5_value_type(store, x.function, x.a)
if mir_vtype_kind(store, table) != mir_type_kind_table() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_table(), mir_vtype_kind(store, table), x.a) } else { let elem = __s0_buffer_get(MirTypeRec, store.types, table - 1).elem
var want = mir_v5_find_unary(store, mir_type_kind_id(), elem)
if x.op == mir_op_table_insert() { want = elem }
result = try mir_v5_expect(d, store, result, x.function, x.block, id, 0, 0, x.b, want) } }
    if x.op == mir_op_table_view_end() { let k = mir_vtype_kind(store, mir_v5_value_type(store, x.function, x.a))
if k != mir_type_kind_table_view() && k != mir_type_kind_table_mut_view() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_table_view(), k, x.a) } }
    if x.op >= mir_op_int_trunc() && x.op <= mir_op_float_from_int() { let ta = mir_v5_value_type(store, x.function, x.a)
var valid = true
if x.op == mir_op_int_trunc() { valid = mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta) }
if x.op == mir_op_int_zext() { valid = mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta) }
if x.op == mir_op_int_sext() { valid = mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta) }
if x.op == mir_op_float_convert() { valid = mir_v5_is_float(ta) && mir_v5_is_float(x.type_op) }
if x.op == mir_op_int_from_float() { valid = mir_v5_is_float(ta) && mir_v5_is_int(x.type_op) }
if x.op == mir_op_float_from_int() { valid = mir_v5_is_int(ta) && mir_v5_is_float(x.type_op) }
if !valid { result = try mir_v5_bad(d, result, mir_vdiag_bad_conversion(), x.function, x.block, id, 0, 0, x.type_op, ta, x.a) } }
    if x.op == mir_op_call() { result = try mir_v5_check_args(d, store, result, x, id, x.target, false) }
    if x.op == mir_op_ffi_call_unsafe() { result = try mir_v5_check_args(d, store, result, x, id, x.target, true) }
    if mir_vop_checked(x.op) { result = try mir_v5_edge(d, store, result, x.function, x.block, id, 0, mir_operand_checked_edge_arg(), id, 0, x.target) }
    if x.result != 0 { let inferred = mir_v5_infer(store, id, x)
let stored = mir_v5_value_type(store, x.function, x.result)
if !inferred.valid { if __s0_buffer_len(MirVerifyDiagRec, result) == baseline { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, 0, stored, x.result) } } else { if stored != inferred.type_id { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, inferred.type_id, stored, x.result) } } }
    return Ok(result)
}

fn mir_v5_terminator(d: Domain, store: MirStore, out: __s0_Buffer(MirVerifyDiagRec), id: U64, t: MirTermRec) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
    if t.kind == mir_term_branch() { result = try mir_v5_expect(d, store, result, t.function, t.block, 0, id, 0, t.value, mir_type_bool())
result = try mir_v5_edge(d, store, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_then(), t.then_block)
result = try mir_v5_edge(d, store, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_else(), t.else_block) }
    if t.kind == mir_term_jump() { result = try mir_v5_edge(d, store, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_jump(), t.target) }
    if t.kind == mir_term_switch() { let et = mir_v5_value_type(store, t.function, t.value)
if !mir_v5_is_enum(store, et) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), t.function, t.block, 0, id, 0, mir_type_kind_enum(), mir_vtype_kind(store, et), t.value) }
var at: U64 = 0
while at < __s0_buffer_len(MirOperandRec, store.operands) { let c = __s0_buffer_get(MirOperandRec, store.operands, at)
if c.kind == mir_operand_switch_case() && c.owner == id { if c.name_start != c.name_end && c.value != 0 { result = try mir_v5_expect(d, store, result, t.function, t.block, 0, id, at + 1, c.value, mir_vcase_payload(store, et, c.name_start, c.name_end)) }
result = try mir_v5_edge(d, store, result, t.function, t.block, 0, id, mir_operand_switch_case_arg(), at + 1, 0, c.target) }
at = at + 1 } }
    if t.kind == mir_term_return() || t.kind == mir_term_fail() { let want = __s0_buffer_get(MirFunctionRec, store.functions, t.function - 1).result_type
if t.value == 0 { if want != mir_type_unit() { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), t.function, t.block, 0, id, 0, mir_type_unit(), want, t.function) } } else { result = try mir_v5_expect(d, store, result, t.function, t.block, 0, id, 0, t.value, want) } }
    return Ok(result)
}

fn mir_vphase5(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        // Parameter and switch binding types are not inferred and must
        // themselves carry a valid type, matching the Go verifier's first pass.
        var vi: U64 = 0
        while vi < __s0_buffer_len(MirValueRec, store.values) { let v = __s0_buffer_get(MirValueRec, store.values, vi)
if v.function == function && (v.def_kind == mir_value_def_block_param() || v.def_kind == mir_value_def_switch_case()) && !mir_vtype_exists(store, v.value_type) { out = try mir_v5_bad(d, out, mir_vdiag_invalid_value_type(), v.function, v.block, 0, 0, 0, 0, v.value_type, vi + 1) }
vi = vi + 1 }
        var block: U64 = 1
        while mir_vblock_index(store, function, block) != 0 {
            var ordinal: U64 = 0
            while ordinal < mir_vp4_instruction_count(store, function, block) { let ii = mir_vp4_instruction_at(store, function, block, ordinal)
out = try mir_v5_instruction(d, store, out, ii, __s0_buffer_get(MirInstrRec, store.instructions, ii - 1))
ordinal = ordinal + 1 }
            var ti: U64 = 0
            while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && t.block == block { out = try mir_v5_terminator(d, store, out, ti + 1, t) }
ti = ti + 1 }
            block = block + 1
        }
        function = function + 1
    }
    return Ok(out)
}
