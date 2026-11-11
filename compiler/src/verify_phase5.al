// Phase 5 is deliberately a pure checker.  V1--V4 have already established
// record ownership, references, ordinals, result reciprocity, and CFG shape.
type MirVTypeResult {
    valid: Bool
    type_id: U64
}

fn mir_v5_value_type(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let at = mir_vindex_value(indexes, function, value)
    if at == 0 { return 0 }
    return __s0_buffer_get(MirValueRec, store.values, at - 1).value_type
}
fn mir_v5_is_int(t: U64) -> Bool { return t >= mir_type_i8() && t <= mir_type_u64() }
fn mir_v5_is_float(t: U64) -> Bool { return t == mir_type_f32() || t == mir_type_f64() }

// World of a c.num conversion endpoint: 1 an Alder primitive, 2 a c_raw
// scalar, 0 anything else.
fn mir_v5_c_num_world(store: MirStore, t: U64) -> U64 {
    if t == 0 || t > __s0_buffer_len(MirTypeRec, store.types) { return 0 }
    if t >= mir_type_i8() && t <= mir_type_u64() { return 1 }
    if t == mir_type_f32() || t == mir_type_f64() { return 1 }
    let rec = __s0_buffer_get(MirTypeRec, store.types, t - 1)
    if rec.kind == mir_type_kind_c_raw() && rec.length <= 14 { return 2 }
    return 0
}

// Numeric class of a c.num conversion endpoint: 1 integer, 2 IEEE single,
// 3 IEEE double, 0 anything else. c_raw lengths 13 and 14 (size_t,
// ptrdiff_t) are integer scalars like the fixed-width C integers. The
// Alder integer primitives are the fixed type ids i8..u64.
fn mir_v5_c_num_class(store: MirStore, t: U64) -> U64 {
    if t == 0 || t > __s0_buffer_len(MirTypeRec, store.types) { return 0 }
    if t >= mir_type_i8() && t <= mir_type_u64() { return 1 }
    if t == mir_type_f32() { return 2 }
    if t == mir_type_f64() { return 3 }
    let rec = __s0_buffer_get(MirTypeRec, store.types, t - 1)
    if rec.kind == mir_type_kind_c_raw() {
        if rec.length <= 10 || rec.length == 13 || rec.length == 14 { return 1 }
        if rec.length == 11 { return 2 }
        if rec.length == 12 { return 3 }
        return 0
    }
    return 0
}

// Pair legality for one c.num conversion (source, target): 1 integer
// across the boundary, 2 float same precision, 3 float widening
// (c.Float -> F64), 0 anything else. The two endpoints must live on
// opposite sides of the C boundary.
fn mir_v5_c_num_pair(store: MirStore, source: U64, target: U64) -> U64 {
    let sw = mir_v5_c_num_world(store, source)
    let tw = mir_v5_c_num_world(store, target)
    if sw == 0 || tw == 0 || sw == tw { return 0 }
    let sc = mir_v5_c_num_class(store, source)
    let tc = mir_v5_c_num_class(store, target)
    if sc == 1 && tc == 1 { return 1 }
    if sc == 2 && tc == 3 { return 3 }
    if sc == tc { return 2 }
    return 0
}

// Result typing for c.num.try/wrap/cast. type_op names the target: an
// option(E) for the try form (E is the payload type), the bare target for
// wrap and cast. try narrows or converts integers and narrows IEEE double
// to single; wrap converts integers; cast accepts the total pairs the
// checker can produce: every integer pair plus same-precision and
// widening float pairs.
fn mir_v5_c_num_result(store: MirStore, indexes: MirVIndexes, x: MirInstrRec, ta: U64) -> MirVTypeResult {
    if x.type_op == 0 || x.type_op > __s0_buffer_len(MirTypeRec, store.types) { return MirVTypeResult(valid: false, type_id: 0) }
    let named = __s0_buffer_get(MirTypeRec, store.types, x.type_op - 1)
    if x.op == mir_op_c_num_try() {
        if named.kind != mir_type_kind_option() { return MirVTypeResult(valid: false, type_id: 0) }
        let sc = mir_v5_c_num_class(store, ta)
        let tc = mir_v5_c_num_class(store, named.elem)
        if mir_v5_c_num_pair(store, ta, named.elem) == 1 { return MirVTypeResult(valid: true, type_id: x.type_op) }
        if sc == 3 && tc == 2 { return MirVTypeResult(valid: true, type_id: x.type_op) }
        return MirVTypeResult(valid: false, type_id: 0)
    }
    let pair = mir_v5_c_num_pair(store, ta, x.type_op)
    if x.op == mir_op_c_num_wrap() { return MirVTypeResult(valid: pair == 1, type_id: x.type_op) }
    return MirVTypeResult(valid: pair != 0, type_id: x.type_op)
}

// Field resolution for c.field.get/set on a record-class c_named type:
// returns the field's type id, 0 when the type is not a record or the
// instruction name names no c_field part.
fn mir_v5_c_field_lookup(store: MirStore, indexes: MirVIndexes, t: U64, ns: U64, ne: U64) -> U64 {
    if t == 0 || t > __s0_buffer_len(MirTypeRec, store.types) { return 0 }
    let rec = __s0_buffer_get(MirTypeRec, store.types, t - 1)
    if rec.kind != mir_type_kind_c_named() || rec.c_class != mir_c_class_record() { return 0 }
    let total = mir_vindex_type_part_count(indexes, t)
    var at: U64 = 0
    while at < total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, t, at) - 1)
        if part.kind == mir_type_part_c_field() && mir_vname_equal(store, ns, ne, part.name_start, part.name_end) { return part.part_type }
        at = at + 1
    }
    return 0
}

// Result typing for c.field.get: the field's type, valid only when the
// name resolves on a record operand.
fn mir_v5_c_field_result(store: MirStore, indexes: MirVIndexes, x: MirInstrRec, ta: U64) -> MirVTypeResult {
    let ft = mir_v5_c_field_lookup(store, indexes, ta, x.name_start, x.name_end)
    return MirVTypeResult(valid: ft != 0, type_id: ft)
}

// Result typing for the c_string constructors and borrow: make_lit yields
// the c_string singleton from a String operand, make yields option(c_string)
// from a String operand, and ptr borrows the c_string owner and yields
// c_const_ptr(c_char).
fn mir_v5_c_string_result(store: MirStore, indexes: MirVIndexes, x: MirInstrRec, ta: U64) -> MirVTypeResult {
    let cstring = mir_v5_find_kind(indexes, mir_type_kind_c_string())
    if x.op == mir_op_c_string_make_lit() {
        if mir_vtype_kind(store, ta) != mir_type_kind_string() { return MirVTypeResult(valid: false, type_id: 0) }
        return MirVTypeResult(valid: cstring != 0, type_id: cstring)
    }
    if x.op == mir_op_c_string_make() {
        if mir_vtype_kind(store, ta) != mir_type_kind_string() { return MirVTypeResult(valid: false, type_id: 0) }
        return MirVTypeResult(valid: cstring != 0, type_id: mir_v5_find_unary(indexes, mir_type_kind_option(), cstring))
    }
    if mir_vtype_kind(store, ta) != mir_type_kind_c_string() { return MirVTypeResult(valid: false, type_id: 0) }
    let cchar = mir_v5_find_c_raw(store, 0)
    let result = mir_v5_find_unary(indexes, mir_type_kind_c_const_ptr(), cchar)
    return MirVTypeResult(valid: cchar != 0 && result != 0, type_id: result)
}

// Find the c_raw type carrying one C scalar id; 0 when absent. The verifier
// keeps no length-keyed type index, and the vocabulary has at most a handful
// of raw types per module.
fn mir_v5_find_c_raw(store: MirStore, scalar: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let rec = __s0_buffer_get(MirTypeRec, store.types, at)
        if rec.kind == mir_type_kind_c_raw() && rec.length == scalar { return at + 1 }
        at = at + 1
    }
    return 0
}

// Operand grammar for the c_string vocabulary: the constructors consume a
// String value; the borrow and the release consume the c_string owner.
// Release is validated here because it produces no result for the inference
// check to reject.
fn mir_v5_c_string_operands(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), x: MirInstrRec, id: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var result = out
    var want: U64 = mir_type_kind_c_string()
    if x.op == mir_op_c_string_make_lit() || x.op == mir_op_c_string_make() { want = mir_type_kind_string() }
    let at = mir_v5_value_type(store, indexes, x.function, x.a)
    if mir_vtype_kind(store, at) != want {
        result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, want, mir_vtype_kind(store, at), x.a)
    }
    return Ok(result)
}

fn mir_v5_is_enum(store: MirStore, t: U64) -> Bool { let k = mir_vtype_kind(store, t)
return k == mir_type_kind_enum() || k == mir_type_kind_option() || k == mir_type_kind_result() }
fn mir_v5_width(t: U64) -> U64 { if t == mir_type_i8() || t == mir_type_u8() { return 8 }
if t == mir_type_i16() || t == mir_type_u16() { return 16 }
if t == mir_type_i32() || t == mir_type_u32() { return 32 }
if t == mir_type_i64() || t == mir_type_u64() { return 64 }
return 0 }
fn mir_v5_signed(t: U64) -> Bool { return t >= mir_type_i8() && t <= mir_type_i64() }
fn mir_v5_elem(store: MirStore, t: U64) -> U64 { let k = mir_vtype_kind(store, t)
if k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_vec() { return __s0_buffer_get(MirTypeRec, store.types, t - 1).elem }
return 0 }
fn mir_v5_array_type(store: MirStore, t: U64) -> U64 {
    if mir_vtype_kind(store, t) == mir_type_kind_array() { return t }
    if mir_vtype_kind(store, t) == mir_type_kind_safe_mut() {
        let elem = __s0_buffer_get(MirTypeRec, store.types, t - 1).elem
        if mir_vtype_kind(store, elem) == mir_type_kind_array() { return elem }
    }
    return 0
}
fn mir_v5_array_view_type(store: MirStore, t: U64) -> U64 {
    if mir_vtype_kind(store, t) == mir_type_kind_array() { return t }
    if mir_vtype_kind(store, t) == mir_type_kind_safe_ref() || mir_vtype_kind(store, t) == mir_type_kind_safe_mut() {
        let elem = __s0_buffer_get(MirTypeRec, store.types, t - 1).elem
        if mir_vtype_kind(store, elem) == mir_type_kind_array() { return elem }
    }
    return 0
}
fn mir_v5_find_unary(indexes: MirVIndexes, kind: U64, elem: U64) -> U64 { return mir_vindex_type_unary(indexes, kind, elem) }
fn mir_v5_find_result(indexes: MirVIndexes, ok: U64, err: U64) -> U64 { return mir_vindex_type_result(indexes, ok, err) }
fn mir_v5_find_kind(indexes: MirVIndexes, kind: U64) -> U64 { return mir_vindex_type_kind(indexes, kind) }
fn mir_v5_const_type(store: MirStore, indexes: MirVIndexes, start: U64, end: U64) -> U64 { let at = mir_vindex_const(store, indexes, start, end)
if at == 0 { return 0 }
return __s0_buffer_get(MirConstRec, store.constants, at - 1).const_type }
fn mir_v5_param_type(store: MirStore, indexes: MirVIndexes, function: U64, block: U64, kind: U64, ordinal: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if p.block == block && p.kind == kind && p.ordinal == ordinal { return p.param_type }
        at = at + 1
    }
    return 0
}
fn mir_v5_function_param_count(store: MirStore, indexes: MirVIndexes, function: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var want: U64 = 0
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if p.kind == mir_param_function() { want = want + 1 }
        at = at + 1
    }
    return want
}
fn mir_v5_type_part_count(store: MirStore, indexes: MirVIndexes, owner: U64, kind: U64) -> U64 {
    let total = mir_vindex_type_part_count(indexes, owner)
    var count: U64 = 0
    var at: U64 = 0
    while at < total {
        if __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, owner, at) - 1).kind == kind { count = count + 1 }
        at = at + 1
    }
    return count
}
// Per-owner operand list helpers.  The instruction/aggregate/checked-edge,
// terminator/switch-case, and switch-case-arg kinds are covered by the operand
// indexes; import parameters are not indexed but are rare (one per FFI
// parameter), so those queries keep the legacy linear scan.
fn mir_v5_operand_count(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64) -> U64 {
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() {
        let total = mir_vindex_op_instr_count(indexes, owner)
        var count: U64 = 0
        var at: U64 = 0
        while at < total {
            let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, owner, at) - 1)
            if o.kind == kind && o.edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() {
        let total = mir_vindex_op_term_count(indexes, owner)
        var count: U64 = 0
        var at: U64 = 0
        while at < total {
            let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, owner, at) - 1)
            if o.kind == kind && o.edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    if kind == mir_operand_switch_case_arg() {
        let total = mir_vindex_op_case_count(indexes, owner)
        var count: U64 = 0
        var at: U64 = 0
        while at < total {
            if __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_case(indexes, owner, at) - 1).edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let o = __s0_buffer_get(MirOperandRec, store.operands, at)
        if o.kind == kind && o.owner == owner && o.edge == edge { count = count + 1 }
        at = at + 1
    }
    return count
}
fn mir_v5_operand(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 {
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() {
        let total = mir_vindex_op_instr_count(indexes, owner)
        var at: U64 = 0
        while at < total {
            let oid = mir_vindex_op_instr(indexes, owner, at)
            let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
            if o.kind == kind && o.edge == edge && o.ordinal == ordinal { return oid }
            at = at + 1
        }
        return 0
    }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() {
        let total = mir_vindex_op_term_count(indexes, owner)
        var at: U64 = 0
        while at < total {
            let oid = mir_vindex_op_term(indexes, owner, at)
            let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
            if o.kind == kind && o.edge == edge && o.ordinal == ordinal { return oid }
            at = at + 1
        }
        return 0
    }
    if kind == mir_operand_switch_case_arg() {
        let total = mir_vindex_op_case_count(indexes, owner)
        var at: U64 = 0
        while at < total {
            let oid = mir_vindex_op_case(indexes, owner, at)
            let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
            if o.edge == edge && o.ordinal == ordinal { return oid }
            at = at + 1
        }
        return 0
    }
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let o = __s0_buffer_get(MirOperandRec, store.operands, at)
        if o.kind == kind && o.owner == owner && o.edge == edge && o.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_v5_place_type(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> MirVTypeResult {
    if place == 0 || place > __s0_buffer_len(MirPlaceRec, store.places) { return MirVTypeResult(valid: false, type_id: 0) }
    let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if p.function != function { return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_local() { let li = mir_vindex_local(indexes, function, p.local)
if li == 0 { return MirVTypeResult(valid: false, type_id: 0) }
return MirVTypeResult(valid: true, type_id: __s0_buffer_get(MirLocalRec, store.locals, li - 1).local_type) }
    if p.kind == mir_place_deref() { let t = mir_v5_value_type(store, indexes, function, p.deref_value)
let k = mir_vtype_kind(store, t)
if k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_table_view() || k == mir_type_kind_table_mut_view() { return MirVTypeResult(valid: true, type_id: __s0_buffer_get(MirTypeRec, store.types, t - 1).elem) }
return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_field() { let base = mir_v5_place_type(store, indexes, function, p.base)
if !base.valid || mir_vtype_kind(store, base.type_id) != mir_type_kind_aggregate() { return MirVTypeResult(valid: false, type_id: 0) }
let total = mir_vindex_type_part_count(indexes, base.type_id)
var at: U64 = 0
while at < total {
    let f = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, base.type_id, at) - 1)
    if f.kind == mir_type_part_field() && mir_vname_equal(store, p.field_start, p.field_end, f.name_start, f.name_end) { return MirVTypeResult(valid: true, type_id: f.part_type) }
    at = at + 1
}
    }
    return MirVTypeResult(valid: false, type_id: 0)
}
fn mir_v5_place_mutable(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> Bool { if place == 0 || place > __s0_buffer_len(MirPlaceRec, store.places) { return false }
let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if p.kind == mir_place_local() { return true }
if p.kind == mir_place_field() { return mir_v5_place_mutable(store, indexes, function, p.base) }
if p.kind == mir_place_deref() { let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, function, p.deref_value))
return k == mir_type_kind_safe_mut() || k == mir_type_kind_table_mut_view() }
return false }

fn mir_v5_bad(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, f: U64, b: U64, i: U64, t: U64, o: U64, expected: U64, actual: U64, reference: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    return mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), kind, f, b, i, t, o, actual, 0, expected, actual, reference))
}
fn mir_v5_expect(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, operand: U64, value: U64, want: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { let got = mir_v5_value_type(store, indexes, f, value)
if got != want { return mir_v5_bad(d, out, mir_vdiag_bad_operand_type(), f, b, i, t, operand, want, got, value) }
return Ok(out) }

// The value type of a slice-checked's high bound, held as the first ordered
// instruction operand (the a/b/c slots carry domain, sequence, and low).
fn mir_v5_ordered_operand_type(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64) -> U64 {
    let oi = mir_v5_operand(store, indexes, mir_operand_instruction(), instruction, 0, 0)
    if oi == 0 { return 0 }
    let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
    return mir_v5_value_type(store, indexes, function, o.value)
}
fn mir_v5_edge(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, kind: U64, owner: U64, edge: U64, target: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
let count = mir_v5_operand_count(store, indexes, kind, owner, edge)
var n: U64 = 0
while n < count { let oi = mir_v5_operand(store, indexes, kind, owner, edge, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
result = try mir_v5_expect(d, store, indexes, result, f, b, i, t, oi, o.value, mir_v5_param_type(store, indexes, f, target, mir_param_block(), n))
n = n + 1 }
return Ok(result) }

fn mir_v5_args_match(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64, target: U64, import_call: Bool) -> Bool {
    let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
    var want: U64 = 0
    if import_call { want = mir_v5_operand_count(store, indexes, mir_operand_import_param(), target, 0) } else { want = mir_v5_function_param_count(store, indexes, target) }
    if got != want { return false }
    var ordinal: U64 = 0
    while ordinal < got {
        let argument = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal) - 1)
        var expected: U64 = 0
        if import_call { expected = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, indexes, mir_operand_import_param(), target, 0, ordinal) - 1).operand_type } else { expected = mir_v5_param_type(store, indexes, target, 0, mir_param_function(), ordinal) }
        if mir_v5_value_type(store, indexes, function, argument.value) != expected { return false }
        ordinal = ordinal + 1
    }
    return true
}

// C binding-call arguments match declared parameter types exactly, with the
// one mutable-to-const widening c_ptr(E) -> c_const_ptr(E).
fn mir_v5_binding_arg_ok(store: MirStore, got: U64, want: U64) -> Bool {
    if got == want { return true }
    if !mir_vtype_exists(store, got) || !mir_vtype_exists(store, want) { return false }
    let g = __s0_buffer_get(MirTypeRec, store.types, got - 1)
    let w = __s0_buffer_get(MirTypeRec, store.types, want - 1)
    if g.kind != mir_type_kind_c_ptr() || w.kind != mir_type_kind_c_const_ptr() { return false }
    return g.elem == w.elem
}

fn mir_v5_binding_args_match(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64, target: U64) -> Bool {
    let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
    let want = mir_v5_operand_count(store, indexes, mir_operand_binding_param(), target, 0)
    if got != want { return false }
    var ordinal: U64 = 0
    while ordinal < got {
        let argument = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal) - 1)
        let expected = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, indexes, mir_operand_binding_param(), target, 0, ordinal) - 1).operand_type
        if !mir_v5_binding_arg_ok(store, mir_v5_value_type(store, indexes, function, argument.value), expected) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_is_raw_pointer(store: MirStore, t: U64) -> Bool {
    if !mir_vtype_exists(store, t) { return false }
    let kind = mir_vtype_kind(store, t)
    return kind == mir_type_kind_raw_ptr() || kind == mir_type_kind_c_ptr() || kind == mir_type_kind_c_const_ptr()
}

fn mir_v5_aggregate_matches(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64, type_id: U64) -> Bool {
    let kind = mir_vtype_kind(store, type_id)
    if kind != mir_type_kind_aggregate() && kind != mir_type_kind_array() { return false }
    let count = mir_v5_operand_count(store, indexes, mir_operand_aggregate_field(), instruction, 0)
    if kind == mir_type_kind_array() {
        let array = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
        if count != array.length { return false }
        var element: U64 = 0
        while element < count {
            let item = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, indexes, mir_operand_aggregate_field(), instruction, 0, element) - 1)
            if item.name_start != item.name_end || mir_v5_value_type(store, indexes, function, item.value) != array.elem { return false }
            element = element + 1
        }
        return true
    }
    if count != mir_v5_type_part_count(store, indexes, type_id, mir_type_part_field()) { return false }
    var ordinal: U64 = 0
    while ordinal < count {
        let field = __s0_buffer_get(MirOperandRec, store.operands, mir_v5_operand(store, indexes, mir_operand_aggregate_field(), instruction, 0, ordinal) - 1)
        var found: U64 = 0
        let total = mir_vindex_type_part_count(indexes, type_id)
        var at: U64 = 0
        while at < total {
            let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
            if part.kind == mir_type_part_field() && mir_vname_equal(store, field.name_start, field.name_end, part.name_start, part.name_end) { found = part.part_type }
            at = at + 1
        }
        if found == 0 || mir_v5_value_type(store, indexes, function, field.value) != found { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_infer(store: MirStore, indexes: MirVIndexes, id: U64, x: MirInstrRec) -> MirVTypeResult {
    let ta = mir_v5_value_type(store, indexes, x.function, x.a)
    let tb = mir_v5_value_type(store, indexes, x.function, x.b)
    if x.op == mir_op_load() { return mir_v5_place_type(store, indexes, x.function, x.place) }
    if x.op == mir_op_borrow() { let p = mir_v5_place_type(store, indexes, x.function, x.place)
return MirVTypeResult(valid: p.valid, type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_ref(), p.type_id)) }
    if x.op == mir_op_borrow_mut() { let p = mir_v5_place_type(store, indexes, x.function, x.place)
return MirVTypeResult(valid: p.valid, type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), p.type_id)) }
    if x.op == mir_op_aggregate_construct() { return MirVTypeResult(valid: mir_v5_aggregate_matches(store, indexes, x.function, id, x.type_op), type_id: x.type_op) }
    if x.op == mir_op_domain_create() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()), type_id: mir_v5_find_kind(indexes, mir_type_kind_domain_handle())) }
    if x.op == mir_op_domain_mark() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()), type_id: mir_v5_find_kind(indexes, mir_type_kind_domain_mark())) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && tb == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), x.type_op)) }
    if x.op == mir_op_copy_to_domain() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()), type_id: tb) }
    if x.op == mir_op_cleanup_scope_begin() { return MirVTypeResult(valid: true, type_id: mir_v5_find_kind(indexes, mir_type_kind_cleanup_scope())) }
    if x.op == mir_op_cleanup_push() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_cleanup_scope()) && __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type == mir_type_unit() && mir_v5_args_match(store, indexes, x.function, id, x.target, false), type_id: mir_v5_find_kind(indexes, mir_type_kind_cleanup_id())) }
    if x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: ta) }
    if x.op >= mir_op_int_add_try() && x.op <= mir_op_int_mul_wrapping() { let pair = mir_v5_is_int(ta) && ta == tb
    if x.op <= mir_op_int_mul_try() { return MirVTypeResult(valid: pair, type_id: mir_v5_find_unary(indexes, mir_type_kind_option(), ta)) }
    return MirVTypeResult(valid: pair, type_id: ta) }
    if x.op >= mir_op_c_num_try() && x.op <= mir_op_c_num_cast() { return mir_v5_c_num_result(store, indexes, x, ta) }
    if x.op == mir_op_c_field_get() { return mir_v5_c_field_result(store, indexes, x, ta) }
    if x.op == mir_op_c_string_make_lit() || x.op == mir_op_c_string_make() || x.op == mir_op_c_string_ptr() { return mir_v5_c_string_result(store, indexes, x, ta) }
    if x.op == mir_op_slice_len() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0, type_id: mir_type_u64()) }
    if x.op == mir_op_slice_index_checked() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0 && tb == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_array_index_checked() { let array = mir_v5_array_type(store, ta)
    if array == 0 { return MirVTypeResult(valid: false, type_id: 0) }
    return MirVTypeResult(valid: tb == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), __s0_buffer_get(MirTypeRec, store.types, array - 1).elem)) }
    if x.op == mir_op_slice_range_checked() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0 && tb == mir_type_u64() && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_vec_new() { return MirVTypeResult(valid: mir_vtype_kind(store, x.type_op) == mir_type_kind_vec(), type_id: x.type_op) }
    if x.op == mir_op_vec_construct_checked() { let k = mir_vtype_kind(store, ta)
        let elem = mir_v5_elem(store, ta)
        return MirVTypeResult(valid: (k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut()) && tb == mir_type_u64() && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_vec(), elem)) }
    if x.op == mir_op_vec_grow_checked() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec() && tb == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64(), type_id: ta) }
    if x.op == mir_op_vec_len() || x.op == mir_op_vec_capacity() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec(), type_id: mir_type_u64()) }
    if x.op == mir_op_vec_storage() || x.op == mir_op_vec_as_mut_slice() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_vec_as_slice() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec(), type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_array_as_slice() { let array = mir_v5_array_view_type(store, ta)
        if array == 0 { return MirVTypeResult(valid: false, type_id: 0) }
        return MirVTypeResult(valid: true, type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), __s0_buffer_get(MirTypeRec, store.types, array - 1).elem)) }
    if x.op == mir_op_enum_payload_checked() { let p = mir_vcase_payload(store, indexes, ta, x.name_start, x.name_end)
return MirVTypeResult(valid: mir_v5_is_enum(store, ta) && p != 0 && p != mir_type_unit(), type_id: p) }
    if x.op == mir_op_enum_construct() { let payload = mir_vcase_payload(store, indexes, x.type_op, x.name_start, x.name_end)
return MirVTypeResult(valid: mir_v5_is_enum(store, x.type_op) && payload != 0 && ((payload == mir_type_unit() && x.a == 0) || (payload != mir_type_unit() && ta == payload)), type_id: x.type_op) }
    if x.op == mir_op_table_create() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()), type_id: mir_v5_find_unary(indexes, mir_type_kind_table(), x.type_op)) }
    if x.op == mir_op_table_insert() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == elem, type_id: mir_v5_find_unary(indexes, mir_type_kind_id(), elem)) }
    if x.op == mir_op_table_insert_try() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
let id_type = mir_v5_find_unary(indexes, mir_type_kind_id(), elem)
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == elem, type_id: mir_v5_find_result(indexes, id_type, elem)) }
    if x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
var view_kind = mir_type_kind_table_view()
if x.op == mir_op_table_lookup_mut() { view_kind = mir_type_kind_table_mut_view() }
let view = mir_v5_find_unary(indexes, view_kind, elem)
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == mir_v5_find_unary(indexes, mir_type_kind_id(), elem), type_id: mir_v5_find_unary(indexes, mir_type_kind_option(), view)) }
    if x.op == mir_op_table_remove() { let elem = __s0_buffer_get(MirTypeRec, store.types, ta - 1).elem
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == mir_v5_find_unary(indexes, mir_type_kind_id(), elem), type_id: mir_type_bool()) }
    if x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { return MirVTypeResult(valid: mir_v5_is_float(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op >= mir_op_float_add() && x.op <= mir_op_float_div() { return MirVTypeResult(valid: mir_v5_is_float(ta) && ta == tb, type_id: ta) }
    if x.op == mir_op_int_trunc() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_zext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_sext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_float_convert() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_int_from_float() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_int(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_float_from_int() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_int_convert_checked() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_int(x.type_op), type_id: mir_v5_find_unary(indexes, mir_type_kind_option(), x.type_op)) }
    if x.op == mir_op_int_convert_wrap() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_int(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_const_get() { let ct = mir_v5_const_type(store, indexes, x.name_start, x.name_end)
return MirVTypeResult(valid: ct != 0, type_id: ct) }
    if x.op == mir_op_call() { return MirVTypeResult(valid: mir_v5_args_match(store, indexes, x.function, id, x.target, false), type_id: __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type) }
    if x.op == mir_op_call_value() { if ta == 0 || mir_vtype_kind(store, ta) != mir_type_kind_function() { return MirVTypeResult(valid: false, type_id: 0) }
return MirVTypeResult(valid: mir_v5_call_value_args_match(store, indexes, x.function, id, ta), type_id: __s0_buffer_get(MirTypeRec, store.types, ta - 1).result_type) }
    if x.op == mir_op_str_eq() { return MirVTypeResult(valid: (mir_vtype_kind(store, ta) == mir_type_kind_string() || mir_vtype_kind(store, ta) == mir_type_kind_bytes()) && tb == ta, type_id: mir_type_bool()) }
    if x.op == mir_op_str_order_lt() { return MirVTypeResult(valid: (mir_vtype_kind(store, ta) == mir_type_kind_string() || mir_vtype_kind(store, ta) == mir_type_kind_bytes()) && tb == ta, type_id: mir_type_bool()) }
    if x.op == mir_op_str_display() { let vb = mir_v5_value_type(store, indexes, x.function, x.b)
    let seq = vb == mir_type_bool() || vb == mir_type_i64() || vb == mir_type_u64()
    return MirVTypeResult(valid: seq, type_id: mir_v5_find_kind(indexes, mir_type_kind_string())) }
    if x.op == mir_op_str_len() || x.op == mir_op_str_to_bytes() { let seq = mir_vtype_kind(store, ta) == mir_type_kind_string() || mir_vtype_kind(store, ta) == mir_type_kind_bytes()
    if x.op == mir_op_str_len() { return MirVTypeResult(valid: seq, type_id: mir_type_u64()) }
    return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_string(), type_id: mir_v5_find_kind(indexes, mir_type_kind_bytes())) }
    if x.op == mir_op_str_byte_checked() { return MirVTypeResult(valid: (mir_vtype_kind(store, ta) == mir_type_kind_string() || mir_vtype_kind(store, ta) == mir_type_kind_bytes()) && tb == mir_type_u64(), type_id: mir_type_u8()) }
    if x.op == mir_op_str_concat() { let tc = mir_v5_value_type(store, indexes, x.function, x.c)
return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && (mir_vtype_kind(store, tb) == mir_type_kind_string() || mir_vtype_kind(store, tb) == mir_type_kind_bytes()) && tc == tb, type_id: tb) }
    if x.op == mir_op_str_slice_checked() { let tc = mir_v5_value_type(store, indexes, x.function, x.c)
return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && (mir_vtype_kind(store, tb) == mir_type_kind_string() || mir_vtype_kind(store, tb) == mir_type_kind_bytes()) && tc == mir_type_u64() && mir_v5_ordered_operand_type(store, indexes, x.function, id) == mir_type_u64(), type_id: tb) }
    if x.op == mir_op_str_from_bytes() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && mir_vtype_kind(store, tb) == mir_type_kind_bytes(), type_id: mir_v5_find_unary(indexes, mir_type_kind_option(), mir_v5_find_kind(indexes, mir_type_kind_string()))) }
    if x.op == mir_op_fn_value() { if x.target == 0 || x.target > __s0_buffer_len(MirFunctionRec, store.functions) { return MirVTypeResult(valid: false, type_id: 0) }
let callee = __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1)
var param_total = mir_v5_function_param_count(store, indexes, x.target)
var param_base: U64 = 0
// The function value's type erases the environment: {code, env} values
// carry the environment opaquely, and closures and plain references of the
// same signature share one value type. A closure thunk's trailing parameter
// is the environment record supplied by the environment operand, not by
// callers of the function value. The marker instead names a storage-model
// target: its leading parameter is the hidden domain, supplied through the
// environment operand, so the erased type covers the parameters after it.
if x.a != 0 && param_total > 0 && x.type_op != mir_fn_value_domain_marker() { param_total = param_total - 1 }
if x.type_op == mir_fn_value_domain_marker() {
    if x.a == 0 || param_total == 0 { return MirVTypeResult(valid: false, type_id: 0) }
    let first_param = mir_v5_param_type(store, indexes, x.target, 0, mir_param_function(), 0)
    if first_param == 0 || __s0_buffer_get(MirTypeRec, store.types, first_param - 1).kind != mir_type_kind_domain_handle() { return MirVTypeResult(valid: false, type_id: 0) }
    let env_type = mir_v5_value_type(store, indexes, x.function, x.a)
    if env_type == 0 || __s0_buffer_get(MirTypeRec, store.types, env_type - 1).kind != mir_type_kind_domain_handle() { return MirVTypeResult(valid: false, type_id: 0) }
    param_base = 1
    param_total = param_total - 1
}
let found = mir_v5_find_function_type_based(store, indexes, x.target, param_base, param_total, callee.result_type, 0)
return MirVTypeResult(valid: found != 0, type_id: found) }
    if x.op == mir_op_ffi_call_unsafe() { return MirVTypeResult(valid: mir_v5_args_match(store, indexes, x.function, id, x.target, true), type_id: __s0_buffer_get(MirImportRec, store.imports, x.target - 1).result_type) }
    if x.op == mir_op_c_binding_call() {
        if x.target == 0 || x.target > __s0_buffer_len(MirBindingFnRec, store.binding_funcs) { return MirVTypeResult(valid: false, type_id: 0) }
        return MirVTypeResult(valid: mir_v5_binding_args_match(store, indexes, x.function, id, x.target), type_id: __s0_buffer_get(MirBindingFnRec, store.binding_funcs, x.target - 1).result_type)
    }
    if x.op == mir_op_c_is_null() { return MirVTypeResult(valid: x.a != 0 && mir_v5_is_raw_pointer(store, mir_v5_value_type(store, indexes, x.function, x.a)), type_id: mir_type_bool()) }
    return MirVTypeResult(valid: false, type_id: 0)
}

// Ordinal lookup of one typed part of a function type.
fn mir_v5_type_part(store: MirStore, owner: U64, kind: U64, ordinal: U64) -> MirTypePartRec {
    var at: U64 = 0
    var seen: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if part.owner == owner && part.kind == kind {
            if seen == ordinal { return part }
            seen = seen + 1
        }
        at = at + 1
    }
    return MirTypePartRec(kind: 0, owner: 0, ordinal: 0, name_start: 0, name_end: 0, part_type: 0, c_name_start: 0, c_name_end: 0)
}

// fn.value's result type is the interned function type whose parameters,
// result, and optional environment part match the target function plus the
// environment operand. Verification only looks it up; lowering interns it.
fn mir_v5_find_function_type(store: MirStore, indexes: MirVIndexes, target: U64, param_total: U64, result_type: U64, env_type: U64) -> U64 {
    return mir_v5_find_function_type_based(store, indexes, target, 0, param_total, result_type, env_type)
}

fn mir_v5_find_function_type_based(store: MirStore, indexes: MirVIndexes, target: U64, param_base: U64, param_total: U64, result_type: U64, env_type: U64) -> U64 {
    var at = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        if t.kind == mir_type_kind_function() && t.result_type == result_type {
            let parts = mir_vindex_type_part_count(indexes, at + 1)
            let env_count = mir_type_part_count(store, at + 1, mir_type_part_function_env())
            var want_env: U64 = 1
            if env_type == 0 { want_env = 0 }
            if env_count == want_env {
                var matches = true
                var ordinal: U64 = 0
                while ordinal < param_total {
                    let part = mir_v5_type_part(store, at + 1, mir_type_part_function_param(), ordinal)
                    let want = mir_v5_param_type(store, indexes, target, 0, mir_param_function(), param_base + ordinal)
                    if part.part_type != want { matches = false }
                    ordinal = ordinal + 1
                }
                if parts != param_total + want_env { matches = false }
                if matches && env_type != 0 {
                    let env_part = mir_v5_type_part(store, at + 1, mir_type_part_function_env(), 0)
                    if env_part.part_type != env_type { matches = false }
                }
                if matches { return at + 1 }
            }
        }
        at = at + 1
    }
    return 0
}

// call.value has no static callee: the declared function type drives both
// the argument count and the argument types.
fn mir_v5_call_value_args_match(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64, fn_type: U64) -> Bool {
    let part_count = __s0_buffer_get(MirTypeRec, store.types, fn_type - 1).part_count
    let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
    if got != part_count { return false }
    var ordinal: U64 = 0
    while ordinal < got {
        let argument = mir_v5_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal)
        let expected = mir_v5_type_part(store, fn_type, mir_type_part_function_param(), ordinal).part_type
        if mir_v5_value_type(store, indexes, function, __s0_buffer_get(MirOperandRec, store.operands, argument - 1).value) != expected { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_check_args(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), x: MirInstrRec, id: U64, target: U64, import_call: Bool) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), id, 0)
var want: U64 = 0
if import_call { want = mir_v5_operand_count(store, indexes, mir_operand_import_param(), target, 0) } else { want = mir_v5_function_param_count(store, indexes, target) }
if got != want { return mir_v5_bad(d, result, mir_vdiag_bad_argument_count(), x.function, x.block, id, 0, 0, want, got, target) }
var n: U64 = 0
while n < got { let oi = mir_v5_operand(store, indexes, mir_operand_instruction(), id, 0, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
var expected: U64 = 0
if import_call { let pi = mir_v5_operand(store, indexes, mir_operand_import_param(), target, 0, n)
expected = __s0_buffer_get(MirOperandRec, store.operands, pi - 1).operand_type } else { expected = mir_v5_param_type(store, indexes, target, 0, mir_param_function(), n) }
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, oi, o.value, expected)
n = n + 1 }
return Ok(result) }

fn mir_v5_check_binding_args(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), x: MirInstrRec, id: U64, target: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), id, 0)
let want = mir_v5_operand_count(store, indexes, mir_operand_binding_param(), target, 0)
if got != want { return mir_v5_bad(d, result, mir_vdiag_bad_argument_count(), x.function, x.block, id, 0, 0, want, got, target) }
var n: U64 = 0
while n < got { let oi = mir_v5_operand(store, indexes, mir_operand_instruction(), id, 0, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
let pi = mir_v5_operand(store, indexes, mir_operand_binding_param(), target, 0, n)
let expected = __s0_buffer_get(MirOperandRec, store.operands, pi - 1).operand_type
if !mir_v5_binding_arg_ok(store, mir_v5_value_type(store, indexes, x.function, o.value), expected) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, oi, expected, mir_v5_value_type(store, indexes, x.function, o.value), o.value) }
n = n + 1 }
return Ok(result) }

fn mir_v5_instruction(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), id: U64, x: MirInstrRec) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var result = out
let baseline = __s0_buffer_len(MirVerifyDiagRec, out)
    if x.op == mir_op_load() || x.op == mir_op_store() || x.op == mir_op_borrow() || x.op == mir_op_borrow_mut() { let p = mir_v5_place_type(store, indexes, x.function, x.place)
if !p.valid { result = try mir_v5_bad(d, result, mir_vdiag_bad_place_type(), x.function, x.block, id, 0, x.place, 0, 0, x.place) } else { if x.op == mir_op_store() || x.op == mir_op_borrow_mut() { if !mir_v5_place_mutable(store, indexes, x.function, x.place) { result = try mir_v5_bad(d, result, mir_vdiag_readonly_place(), x.function, x.block, id, 0, x.place, 0, p.type_id, x.place) }
if x.op == mir_op_store() {
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, p.type_id) } } } }
    if x.op == mir_op_aggregate_construct() { var fields = mir_v5_type_part_count(store, indexes, x.type_op, mir_type_part_field())
if mir_vtype_kind(store, x.type_op) == mir_type_kind_array() { fields = __s0_buffer_get(MirTypeRec, store.types, x.type_op - 1).length }
let got = mir_v5_operand_count(store, indexes, mir_operand_aggregate_field(), id, 0)
if (mir_vtype_kind(store, x.type_op) != mir_type_kind_aggregate() && mir_vtype_kind(store, x.type_op) != mir_type_kind_array()) || got != fields { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, 0, fields, got, x.type_op) } else { var n: U64 = 0
while n < got { let oi = mir_v5_operand(store, indexes, mir_operand_aggregate_field(), id, 0, n)
let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
if mir_vtype_kind(store, x.type_op) == mir_type_kind_array() {
if o.name_start != o.name_end { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, oi, n, o.ordinal, x.type_op) }
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, oi, o.value, __s0_buffer_get(MirTypeRec, store.types, x.type_op - 1).elem) }
let total = mir_vindex_type_part_count(indexes, x.type_op)
var pi: U64 = 0
while pi < total { let pid = mir_vindex_type_part(indexes, x.type_op, pi)
let p = __s0_buffer_get(MirTypePartRec, store.type_parts, pid - 1)
if p.kind == mir_type_part_field() && p.ordinal == n { if !mir_vname_equal(store, o.name_start, o.name_end, p.name_start, p.name_end) { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, oi, n, o.ordinal, pid) }
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, oi, o.value, p.part_type) }
pi = pi + 1 }
n = n + 1 } } }
    if x.op == mir_op_domain_create() || x.op == mir_op_domain_mark() || x.op == mir_op_domain_destroy() || x.op == mir_op_table_create() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle())) }
    if x.op == mir_op_domain_reset() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle()))
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_v5_find_kind(indexes, mir_type_kind_domain_mark())) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle()))
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
    if x.op == mir_op_copy_to_domain() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle())) }
    if x.op == mir_op_cleanup_push() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_cleanup_scope()))
result = try mir_v5_check_args(d, store, indexes, result, x, id, x.target, false)
if __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type != mir_type_unit() { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, mir_type_unit(), __s0_buffer_get(MirFunctionRec, store.functions, x.target - 1).result_type, x.target) } }
    if x.op == mir_op_cleanup_disarm() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_cleanup_id())) }
    if x.op == mir_op_cleanup_scope_run() || x.op == mir_op_cleanup_scope_end() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_cleanup_scope())) }
    if (x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked()) || (x.op >= mir_op_int_add_try() && x.op <= mir_op_int_mul_wrapping()) || (x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge()) { let ta = mir_v5_value_type(store, indexes, x.function, x.a)
let tb = mir_v5_value_type(store, indexes, x.function, x.b)
if !mir_v5_is_int(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { let ta = mir_v5_value_type(store, indexes, x.function, x.a)
let tb = mir_v5_value_type(store, indexes, x.function, x.b)
if !mir_v5_is_float(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op >= mir_op_float_add() && x.op <= mir_op_float_div() { let ta = mir_v5_value_type(store, indexes, x.function, x.a)
let tb = mir_v5_value_type(store, indexes, x.function, x.b)
if !mir_v5_is_float(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op == mir_op_slice_len() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() { if mir_v5_elem(store, mir_v5_value_type(store, indexes, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_slice(), mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)), x.a) }
if x.op != mir_op_slice_len() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
if x.op == mir_op_slice_range_checked() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) } }
    if x.op == mir_op_array_index_checked() { if mir_v5_array_type(store, mir_v5_value_type(store, indexes, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_array(), mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)), x.a) }
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
    if x.op == mir_op_vec_new() { if mir_vtype_kind(store, x.type_op) != mir_type_kind_vec() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_vtype_kind(store, x.type_op), x.type_op) } }
    if x.op == mir_op_vec_construct_checked() { let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a))
        if k != mir_type_kind_slice() && k != mir_type_kind_safe_ref() && k != mir_type_kind_safe_mut() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_slice(), k, x.a) }
        result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64())
        result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) }
    if x.op == mir_op_vec_grow_checked() { if mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)) != mir_type_kind_vec() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)), x.a) }
        result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_v5_find_kind(indexes, mir_type_kind_domain_handle()))
        result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) }
    if x.op >= mir_op_vec_len() && x.op <= mir_op_vec_as_mut_slice() { if mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)) != mir_type_kind_vec() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)), x.a) } }
    if x.op == mir_op_array_as_slice() { if mir_v5_array_view_type(store, mir_v5_value_type(store, indexes, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_array(), mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)), x.a) } }
    if x.op == mir_op_enum_payload_checked() || x.op == mir_op_enum_construct() { var et = mir_v5_value_type(store, indexes, x.function, x.a)
if x.op == mir_op_enum_construct() { et = x.type_op }
let payload = mir_vcase_payload(store, indexes, et, x.name_start, x.name_end)
if !mir_v5_is_enum(store, et) || payload == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_variant(), x.function, x.block, id, 0, 0, et, 0, et) } else { if x.op == mir_op_enum_construct() { if payload == mir_type_unit() && x.a != 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_variant(), x.function, x.block, id, 0, 0, 0, mir_v5_value_type(store, indexes, x.function, x.a), et) }
if payload != mir_type_unit() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, payload) } } } }
    if (x.op >= mir_op_table_insert() && x.op <= mir_op_table_remove()) || x.op == mir_op_table_insert_try() { let table = mir_v5_value_type(store, indexes, x.function, x.a)
if mir_vtype_kind(store, table) != mir_type_kind_table() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_table(), mir_vtype_kind(store, table), x.a) } else { let elem = __s0_buffer_get(MirTypeRec, store.types, table - 1).elem
var want = mir_v5_find_unary(indexes, mir_type_kind_id(), elem)
if x.op == mir_op_table_insert() || x.op == mir_op_table_insert_try() { want = elem }
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, want) } }
    if x.op == mir_op_table_view_end() { let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a))
if k != mir_type_kind_table_view() && k != mir_type_kind_table_mut_view() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_table_view(), k, x.a) } }
    if x.op >= mir_op_int_trunc() && x.op <= mir_op_float_from_int() { let ta = mir_v5_value_type(store, indexes, x.function, x.a)
var valid = true
if x.op == mir_op_int_trunc() { valid = mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta) }
if x.op == mir_op_int_zext() { valid = mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta) }
if x.op == mir_op_int_sext() { valid = mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta) }
if x.op == mir_op_float_convert() { valid = mir_v5_is_float(ta) && mir_v5_is_float(x.type_op) }
if x.op == mir_op_int_from_float() { valid = mir_v5_is_float(ta) && mir_v5_is_int(x.type_op) }
if x.op == mir_op_float_from_int() { valid = mir_v5_is_int(ta) && mir_v5_is_float(x.type_op) }
if !valid { result = try mir_v5_bad(d, result, mir_vdiag_bad_conversion(), x.function, x.block, id, 0, 0, x.type_op, ta, x.a) } }
    if x.op == mir_op_int_convert_checked() || x.op == mir_op_int_convert_wrap() { let ta = mir_v5_value_type(store, indexes, x.function, x.a)
if !(mir_v5_is_int(ta) && mir_v5_is_int(x.type_op)) { result = try mir_v5_bad(d, result, mir_vdiag_bad_conversion(), x.function, x.block, id, 0, 0, x.type_op, ta, x.a) } }
    if x.op == mir_op_call() { result = try mir_v5_check_args(d, store, indexes, result, x, id, x.target, false) }
    if x.op == mir_op_ffi_call_unsafe() { result = try mir_v5_check_args(d, store, indexes, result, x, id, x.target, true) }
    if x.op == mir_op_c_binding_call() {
        if x.target == 0 || x.target > __s0_buffer_len(MirBindingFnRec, store.binding_funcs) { result = try mir_v5_bad(d, result, mir_vdiag_bad_owner(), x.function, x.block, id, 0, 0, 0, x.target, x.target) }
        else { result = try mir_v5_check_binding_args(d, store, indexes, result, x, id, x.target) }
    }
    if x.op == mir_op_c_is_null() && !mir_v5_is_raw_pointer(store, mir_v5_value_type(store, indexes, x.function, x.a)) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_c_ptr(), mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)), x.a) }
    if x.op == mir_op_c_field_get() || x.op == mir_op_c_field_set() { result = try mir_v5_c_field_operands(d, store, indexes, result, x, id) }
    if x.op == mir_op_c_string_make_lit() || x.op == mir_op_c_string_make() || x.op == mir_op_c_string_ptr() || x.op == mir_op_c_string_release() { result = try mir_v5_c_string_operands(d, store, indexes, result, x, id) }
    if x.op == mir_op_str_len() || x.op == mir_op_str_to_bytes() || x.op == mir_op_str_byte_checked() { let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a))
if k != mir_type_kind_string() && k != mir_type_kind_bytes() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_string(), k, x.a) }
if x.op == mir_op_str_byte_checked() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) } }
    if x.op == mir_op_str_to_bytes() && mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.a)) == mir_type_kind_bytes() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_string(), mir_type_kind_bytes(), x.a) }
    if x.op == mir_op_str_concat() || x.op == mir_op_str_slice_checked() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle()))
let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.b))
if k != mir_type_kind_string() && k != mir_type_kind_bytes() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_string(), k, x.b) } }
    if x.op == mir_op_str_concat() { let b_type = mir_v5_value_type(store, indexes, x.function, x.b)
let c_type = mir_v5_value_type(store, indexes, x.function, x.c)
let ck = mir_vtype_kind(store, c_type)
if ck != mir_type_kind_string() && ck != mir_type_kind_bytes() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, b_type, c_type, x.c) } else if c_type != b_type { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, b_type, c_type, x.c) } }
    if x.op == mir_op_str_slice_checked() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64())
let oi = mir_v5_operand(store, indexes, mir_operand_instruction(), id, 0, 0)
if oi != 0 { let o = __s0_buffer_get(MirOperandRec, store.operands, oi - 1)
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, oi, o.value, mir_type_u64()) } }
    if x.op == mir_op_str_from_bytes() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle()))
let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, x.function, x.b))
if k != mir_type_kind_bytes() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_bytes(), k, x.b) } }
    if x.op == mir_op_str_display() { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, mir_v5_find_kind(indexes, mir_type_kind_domain_handle()))
let dk = mir_v5_value_type(store, indexes, x.function, x.b)
if dk != mir_type_bool() && dk != mir_type_i64() && dk != mir_type_u64() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_i64(), dk, x.b) } }
    if mir_vop_checked(x.op) { result = try mir_v5_edge(d, store, indexes, result, x.function, x.block, id, 0, mir_operand_checked_edge_arg(), id, 0, x.target) }
    if x.result != 0 { let inferred = mir_v5_infer(store, indexes, id, x)
let stored = mir_v5_value_type(store, indexes, x.function, x.result)
if !inferred.valid { if __s0_buffer_len(MirVerifyDiagRec, result) == baseline { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, 0, stored, x.result) } } else { if stored != inferred.type_id { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, inferred.type_id, stored, x.result) } } }
    return Ok(result)
}

// Grammar for c.field.get/set. The read form resolves the named field on
// the record operand's type; the write form resolves it on the target
// place's type and checks the stored value against the field's type.
fn mir_v5_c_field_operands(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), x: MirInstrRec, id: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
    var record_type: U64 = 0
    if x.op == mir_op_c_field_get() {
        record_type = mir_v5_value_type(store, indexes, x.function, x.a)
    } else {
        if x.place == 0 || x.place > __s0_buffer_len(MirPlaceRec, store.places) { return Ok(result) }
        let placed = mir_v5_place_type(store, indexes, x.function, x.place)
        if !placed.valid { return Ok(result) }
        record_type = placed.type_id
    }
    let ft = mir_v5_c_field_lookup(store, indexes, record_type, x.name_start, x.name_end)
    if ft == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_c_named(), mir_vtype_kind(store, record_type), x.a) }
    if x.op == mir_op_c_field_set() && ft != 0 { result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, 0, x.a, ft) }
    return Ok(result)
}

fn mir_v5_terminator(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), id: U64, t: MirTermRec) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var result = out
    if t.kind == mir_term_branch() { result = try mir_v5_expect(d, store, indexes, result, t.function, t.block, 0, id, 0, t.value, mir_type_bool())
result = try mir_v5_edge(d, store, indexes, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_then(), t.then_block)
result = try mir_v5_edge(d, store, indexes, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_else(), t.else_block) }
    if t.kind == mir_term_jump() { result = try mir_v5_edge(d, store, indexes, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_jump(), t.target) }
    if t.kind == mir_term_switch() { let et = mir_v5_value_type(store, indexes, t.function, t.value)
if !mir_v5_is_enum(store, et) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), t.function, t.block, 0, id, 0, mir_type_kind_enum(), mir_vtype_kind(store, et), t.value) }
let ccount = mir_vindex_op_term_count(indexes, id)
var at: U64 = 0
while at < ccount {
    let cid = mir_vindex_op_term(indexes, id, at)
    let c = __s0_buffer_get(MirOperandRec, store.operands, cid - 1)
    if c.kind == mir_operand_switch_case() { if c.name_start != c.name_end && c.value != 0 { result = try mir_v5_expect(d, store, indexes, result, t.function, t.block, 0, id, cid, c.value, mir_vcase_payload(store, indexes, et, c.name_start, c.name_end)) }
result = try mir_v5_edge(d, store, indexes, result, t.function, t.block, 0, id, mir_operand_switch_case_arg(), cid, 0, c.target) }
    at = at + 1
} }
    if t.kind == mir_term_return() || t.kind == mir_term_fail() { let want = __s0_buffer_get(MirFunctionRec, store.functions, t.function - 1).result_type
if t.value == 0 { if want != mir_type_unit() { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), t.function, t.block, 0, id, 0, mir_type_unit(), want, t.function) } } else { result = try mir_v5_expect(d, store, indexes, result, t.function, t.block, 0, id, 0, t.value, want) } }
    return Ok(result)
}

fn mir_vphase5(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        // Parameter and switch binding types are not inferred and must
        // themselves carry a valid type, matching the Go verifier's first pass.
        var value: U64 = 1
        while mir_vindex_value(indexes, function, value) != 0 {
            let vi = mir_vindex_value(indexes, function, value)
            let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
            if (v.def_kind == mir_value_def_block_param() || v.def_kind == mir_value_def_switch_case()) && !mir_vtype_exists(store, v.value_type) { out = try mir_v5_bad(d, out, mir_vdiag_invalid_value_type(), v.function, v.block, 0, 0, 0, 0, v.value_type, vi) }
            value = value + 1
        }
        let bcount = mir_vindex_block_count(indexes, function)
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ordinal: U64 = 0
            while ordinal < icount {
                let ii = mir_vindex_instr(indexes, function, block, ordinal)
                out = try mir_v5_instruction(d, store, indexes, out, ii, __s0_buffer_get(MirInstrRec, store.instructions, ii - 1))
                ordinal = ordinal + 1
            }
            let term_id = mir_vindex_term(indexes, function, block)
            if term_id != 0 { out = try mir_v5_terminator(d, store, indexes, out, term_id, __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)) }
            block = block + 1
        }
        function = function + 1
    }
    return Ok(out)
}
