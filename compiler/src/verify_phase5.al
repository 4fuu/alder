// Phase 5 is deliberately a pure checker.  V1--V4 have already established
// record ownership, references, ordinals, result reciprocity, and CFG shape.
type MirVTypeResult {
    valid: Bool
    type_id: U64
}

// Phase 5 receives verifier input as immutable views so its per-instruction
// queries do not copy the growing module store or indexes. Diagnostics remain
// owned and committed by the instruction/terminator traversal.
type MirV5Read {
    base: MirV3Read
    imports: [MirImportRec]
    constants: [MirConstRec]
    locals: [MirLocalRec]
    places: [MirPlaceRec]
    local_pos: [U64]
    local_span: [U64]
    local_count: [U64]
    const_slot: [U64]
    type_first: [U64]
    type_unary: [U64]
}

fn mir_v5_read_local(read: MirV5Read, function: U64, local: U64) -> U64 {
    if function == 0 || function > len(read.local_count) { return 0 }
    if local == 0 || local > read.local_count[function - 1] { return 0 }
    return read.local_pos[read.local_span[function - 1] + local - 1]
}
fn mir_v5_read_kind(read: MirV5Read, kind: U64) -> U64 {
    if kind >= len(read.type_first) { return 0 }
    return read.type_first[kind]
}
fn mir_v5_read_unary(read: MirV5Read, kind: U64, elem: U64) -> U64 {
    let kind_count = len(read.type_first)
    if kind_count == 0 { return 0 }
    let type_count = len(read.type_unary) / kind_count
    if kind >= kind_count || elem == 0 || elem > type_count { return 0 }
    return read.type_unary[kind * type_count + elem - 1]
}

fn mir_v5_value_type(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let at = mir_vindex_value(indexes, function, value)
    if at == 0 { return 0 }
    return (store.values)[at - 1].value_type
}
fn mir_v5_value_type_read(read: MirV5Read, function: U64, value: U64) -> U64 {
    let at = mir_v3_value(read.base, function, value)
    if at == 0 { return 0 }
    return read.base.values[at - 1].value_type
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
fn mir_v5_is_enum_read(read: MirV5Read, t: U64) -> Bool { let k = mir_v3_type_kind(read.base, t)
return k == mir_type_kind_enum() || k == mir_type_kind_option() || k == mir_type_kind_result() }
fn mir_v5_elem_read(read: MirV5Read, t: U64) -> U64 { let k = mir_v3_type_kind(read.base, t)
if k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_vec() { return read.base.types[t - 1].elem }
return 0 }
fn mir_v5_array_type_read(read: MirV5Read, t: U64) -> U64 {
    if mir_v3_type_kind(read.base, t) == mir_type_kind_array() { return t }
    if mir_v3_type_kind(read.base, t) == mir_type_kind_safe_mut() {
        let elem = read.base.types[t - 1].elem
        if mir_v3_type_kind(read.base, elem) == mir_type_kind_array() { return elem }
    }
    return 0
}
fn mir_v5_array_view_type_read(read: MirV5Read, t: U64) -> U64 {
    if mir_v3_type_kind(read.base, t) == mir_type_kind_array() { return t }
    if mir_v3_type_kind(read.base, t) == mir_type_kind_safe_ref() || mir_v3_type_kind(read.base, t) == mir_type_kind_safe_mut() {
        let elem = read.base.types[t - 1].elem
        if mir_v3_type_kind(read.base, elem) == mir_type_kind_array() { return elem }
    }
    return 0
}
fn mir_v5_find_result_read(read: MirV5Read, ok_type: U64, err_type: U64) -> U64 {
    var at: U64 = 0
    while at < len(read.base.types) { let item = read.base.types[at]
        if item.kind == mir_type_kind_result() && item.ok_type == ok_type && item.err_type == err_type { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_v5_elem(store: MirStore, t: U64) -> U64 { let k = mir_vtype_kind(store, t)
if k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_vec() { return (store.types)[t - 1].elem }
return 0 }
fn mir_v5_array_type(store: MirStore, t: U64) -> U64 {
    if mir_vtype_kind(store, t) == mir_type_kind_array() { return t }
    if mir_vtype_kind(store, t) == mir_type_kind_safe_mut() {
        let elem = (store.types)[t - 1].elem
        if mir_vtype_kind(store, elem) == mir_type_kind_array() { return elem }
    }
    return 0
}
fn mir_v5_array_view_type(store: MirStore, t: U64) -> U64 {
    if mir_vtype_kind(store, t) == mir_type_kind_array() { return t }
    if mir_vtype_kind(store, t) == mir_type_kind_safe_ref() || mir_vtype_kind(store, t) == mir_type_kind_safe_mut() {
        let elem = (store.types)[t - 1].elem
        if mir_vtype_kind(store, elem) == mir_type_kind_array() { return elem }
    }
    return 0
}
fn mir_v5_find_unary(indexes: MirVIndexes, kind: U64, elem: U64) -> U64 { return mir_vindex_type_unary(indexes, kind, elem) }
fn mir_v5_find_kind(indexes: MirVIndexes, kind: U64) -> U64 { return mir_vindex_type_kind(indexes, kind) }
fn mir_v5_find_result(store: MirStore, ok_type: U64, err_type: U64) -> U64 {
    var at: U64 = 0
    while at < (store.types).len() {
        let item = (store.types)[at]
        if item.kind == mir_type_kind_result() && item.ok_type == ok_type && item.err_type == err_type { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_v5_capacity_error(store: MirStore, type_id: U64) -> Bool {
    if mir_vtype_kind(store, type_id) != mir_type_kind_enum() { return false }
    let item = (store.types)[type_id - 1]
    if !mir_vname_word(store, item.name_start, item.name_end, "CapacityError") { return false }
    var oom = false
    var limit = false
    var count: U64 = 0
    var at: U64 = 0
    while at < (store.type_parts).len() {
        let part = (store.type_parts)[at]
        if part.owner == type_id && part.kind == mir_type_part_variant() {
            if part.part_type != mir_type_unit() { return false }
            if mir_vname_word(store, part.name_start, part.name_end, "OutOfMemory") { oom = true }
            else { if mir_vname_word(store, part.name_start, part.name_end, "Limit") { limit = true }
            else { return false } }
            count = count + 1
        }
        at = at + 1
    }
    return count == 2 && oom && limit
}
fn mir_v5_capacity_error_read(read: MirV5Read, type_id: U64) -> Bool {
    if mir_v3_type_kind(read.base, type_id) != mir_type_kind_enum() { return false }
    let item = read.base.types[type_id - 1]
    if !mir_v3_name_word(read.base, item.name_start, item.name_end, "CapacityError") { return false }
    var oom = false
    var limit = false
    var count: U64 = 0
    var at: U64 = 0
    while at < len(read.base.type_parts) {
        let part = read.base.type_parts[at]
        if part.owner == type_id && part.kind == mir_type_part_variant() {
            if part.part_type != mir_type_unit() { return false }
            if mir_v3_name_word(read.base, part.name_start, part.name_end, "OutOfMemory") { oom = true }
            else { if mir_v3_name_word(read.base, part.name_start, part.name_end, "Limit") { limit = true }
            else { return false } }
            count = count + 1
        }
        at = at + 1
    }
    return count == 2 && oom && limit
}
fn mir_v5_const_type(store: MirStore, indexes: MirVIndexes, start: U64, end: U64) -> U64 { let at = mir_vindex_const(store, indexes, start, end)
if at == 0 { return 0 }
return (store.constants)[at - 1].const_type }
fn mir_v5_const_type_read(read: MirV5Read, start: U64, end: U64) -> U64 {
    var at: U64 = 0
    while at < len(read.constants) { let item = read.constants[at]
        if mir_v3_name_equal(read.base, start, end, item.name_start, item.name_end) { return item.const_type }
        at = at + 1
    }
    return 0
}
fn mir_v5_param_type(store: MirStore, indexes: MirVIndexes, function: U64, block: U64, kind: U64, ordinal: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let p = (store.params)[mir_vindex_param(indexes, function, at) - 1]
        if p.block == block && p.kind == kind && p.ordinal == ordinal { return p.param_type }
        at = at + 1
    }
    return 0
}
fn mir_v5_param_type_read(read: MirV5Read, function: U64, block: U64, kind: U64, ordinal: U64) -> U64 {
    let count = mir_v3_param_count(read.base, function)
    var at: U64 = 0
    while at < count {
        let p = read.base.params[mir_v3_param(read.base, function, at) - 1]
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
        let p = (store.params)[mir_vindex_param(indexes, function, at) - 1]
        if p.kind == mir_param_function() { want = want + 1 }
        at = at + 1
    }
    return want
}
fn mir_v5_function_param_count_read(read: MirV5Read, function: U64) -> U64 {
    let count = mir_v3_param_count(read.base, function)
    var want: U64 = 0
    var at: U64 = 0
    while at < count {
        if read.base.params[mir_v3_param(read.base, function, at) - 1].kind == mir_param_function() { want = want + 1 }
        at = at + 1
    }
    return want
}
fn mir_v5_type_part_count(store: MirStore, indexes: MirVIndexes, owner: U64, kind: U64) -> U64 {
    let total = mir_vindex_type_part_count(indexes, owner)
    var count: U64 = 0
    var at: U64 = 0
    while at < total {
        if (store.type_parts)[mir_vindex_type_part(indexes, owner, at) - 1].kind == kind { count = count + 1 }
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
            let o = (store.operands)[mir_vindex_op_instr(indexes, owner, at) - 1]
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
            let o = (store.operands)[mir_vindex_op_term(indexes, owner, at) - 1]
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
            if (store.operands)[mir_vindex_op_case(indexes, owner, at) - 1].edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < (store.operands).len() {
        let o = (store.operands)[at]
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
            let o = (store.operands)[oid - 1]
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
            let o = (store.operands)[oid - 1]
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
            let o = (store.operands)[oid - 1]
            if o.edge == edge && o.ordinal == ordinal { return oid }
            at = at + 1
        }
        return 0
    }
    var at: U64 = 0
    while at < (store.operands).len() {
        let o = (store.operands)[at]
        if o.kind == kind && o.owner == owner && o.edge == edge && o.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_v5_operand_count_read(read: MirV5Read, kind: U64, owner: U64, edge: U64) -> U64 {
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() {
        let total = read.base.op_instr_count[owner - 1]
        var count: U64 = 0
        var at: U64 = 0
        while at < total { let o = read.base.operands[mir_v3_op_instr(read.base, owner, at) - 1]
            if o.kind == kind && o.edge == edge { count = count + 1 }
            at = at + 1 }
        return count
    }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() {
        let total = read.base.op_term_count[owner - 1]
        var count: U64 = 0
        var at: U64 = 0
        while at < total { let o = read.base.operands[mir_v3_op_term(read.base, owner, at) - 1]
            if o.kind == kind && o.edge == edge { count = count + 1 }
            at = at + 1 }
        return count
    }
    if kind == mir_operand_switch_case_arg() {
        let total = read.base.op_case_count[owner - 1]
        var count: U64 = 0
        var at: U64 = 0
        while at < total { if read.base.operands[mir_v3_op_case(read.base, owner, at) - 1].edge == edge { count = count + 1 }
            at = at + 1 }
        return count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < len(read.base.operands) { let o = read.base.operands[at]
        if o.kind == kind && o.owner == owner && o.edge == edge { count = count + 1 }
        at = at + 1 }
    return count
}
fn mir_v5_operand_read(read: MirV5Read, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 {
    var total: U64 = 0
    var family: U64 = 0
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() { total = read.base.op_instr_count[owner - 1]
    family = 1 }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() { total = read.base.op_term_count[owner - 1]
    family = 2 }
    if kind == mir_operand_switch_case_arg() { total = read.base.op_case_count[owner - 1]
    family = 3 }
    var at: U64 = 0
    while at < total {
        var oid: U64 = 0
        if family == 1 { oid = mir_v3_op_instr(read.base, owner, at) }
        if family == 2 { oid = mir_v3_op_term(read.base, owner, at) }
        if family == 3 { oid = mir_v3_op_case(read.base, owner, at) }
        let o = read.base.operands[oid - 1]
        if (family == 3 || o.kind == kind) && o.edge == edge && o.ordinal == ordinal { return oid }
        at = at + 1
    }
    if family != 0 { return 0 }
    at = 0
    while at < len(read.base.operands) { let o = read.base.operands[at]
        if o.kind == kind && o.owner == owner && o.edge == edge && o.ordinal == ordinal { return at + 1 }
        at = at + 1 }
    return 0
}

fn mir_v5_place_type(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> MirVTypeResult {
    if place == 0 || place > (store.places).len() { return MirVTypeResult(valid: false, type_id: 0) }
    let p = (store.places)[place - 1]
    if p.function != function { return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_local() { let li = mir_vindex_local(indexes, function, p.local)
if li == 0 { return MirVTypeResult(valid: false, type_id: 0) }
return MirVTypeResult(valid: true, type_id: (store.locals)[li - 1].local_type) }
    if p.kind == mir_place_deref() { let t = mir_v5_value_type(store, indexes, function, p.deref_value)
let k = mir_vtype_kind(store, t)
if k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_table_view() || k == mir_type_kind_table_mut_view() { return MirVTypeResult(valid: true, type_id: (store.types)[t - 1].elem) }
return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_field() { let base = mir_v5_place_type(store, indexes, function, p.base)
if !base.valid || mir_vtype_kind(store, base.type_id) != mir_type_kind_aggregate() { return MirVTypeResult(valid: false, type_id: 0) }
let total = mir_vindex_type_part_count(indexes, base.type_id)
var at: U64 = 0
while at < total {
    let f = (store.type_parts)[mir_vindex_type_part(indexes, base.type_id, at) - 1]
    if f.kind == mir_type_part_field() && mir_vname_equal(store, p.field_start, p.field_end, f.name_start, f.name_end) { return MirVTypeResult(valid: true, type_id: f.part_type) }
    at = at + 1
}
    }
    return MirVTypeResult(valid: false, type_id: 0)
}
fn mir_v5_place_mutable(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> Bool { if place == 0 || place > (store.places).len() { return false }
let p = (store.places)[place - 1]
if p.kind == mir_place_local() { return true }
if p.kind == mir_place_field() { return mir_v5_place_mutable(store, indexes, function, p.base) }
if p.kind == mir_place_deref() { let k = mir_vtype_kind(store, mir_v5_value_type(store, indexes, function, p.deref_value))
return k == mir_type_kind_safe_mut() || k == mir_type_kind_table_mut_view() }
return false }

fn mir_v5_place_type_read(read: MirV5Read, function: U64, place: U64) -> MirVTypeResult {
    if place == 0 || place > len(read.places) { return MirVTypeResult(valid: false, type_id: 0) }
    let p = read.places[place - 1]
    if p.function != function { return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_local() { let li = mir_v5_read_local(read, function, p.local)
    if li == 0 { return MirVTypeResult(valid: false, type_id: 0) }
    return MirVTypeResult(valid: true, type_id: read.locals[li - 1].local_type) }
    if p.kind == mir_place_deref() { let t = mir_v5_value_type_read(read, function, p.deref_value)
    let k = mir_v3_type_kind(read.base, t)
    if k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut() || k == mir_type_kind_table_view() || k == mir_type_kind_table_mut_view() { return MirVTypeResult(valid: true, type_id: read.base.types[t - 1].elem) }
    return MirVTypeResult(valid: false, type_id: 0) }
    if p.kind == mir_place_field() { let base = mir_v5_place_type_read(read, function, p.base)
    if !base.valid || mir_v3_type_kind(read.base, base.type_id) != mir_type_kind_aggregate() { return MirVTypeResult(valid: false, type_id: 0) }
    let total = read.base.tp_count[base.type_id - 1]
    var at: U64 = 0
    while at < total { let f = read.base.type_parts[mir_v3_type_part(read.base, base.type_id, at) - 1]
        if f.kind == mir_type_part_field() && mir_v3_name_equal(read.base, p.field_start, p.field_end, f.name_start, f.name_end) { return MirVTypeResult(valid: true, type_id: f.part_type) }
        at = at + 1 }
    }
    return MirVTypeResult(valid: false, type_id: 0)
}
fn mir_v5_place_mutable_read(read: MirV5Read, function: U64, place: U64) -> Bool {
    if place == 0 || place > len(read.places) { return false }
    let p = read.places[place - 1]
    if p.kind == mir_place_local() { return true }
    if p.kind == mir_place_field() { return mir_v5_place_mutable_read(read, function, p.base) }
    if p.kind == mir_place_deref() { let k = mir_v3_type_kind(read.base, mir_v5_value_type_read(read, function, p.deref_value))
    return k == mir_type_kind_safe_mut() || k == mir_type_kind_table_mut_view() }
    return false
}

fn mir_v5_bad(d: Domain, out: Vec(MirVerifyDiagRec), kind: U64, f: U64, b: U64, i: U64, t: U64, o: U64, expected: U64, actual: U64, reference: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    return mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), kind, f, b, i, t, o, actual, 0, expected, actual, reference))
}
fn mir_v5_expect(d: Domain, store: MirStore, indexes: MirVIndexes, out: Vec(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, operand: U64, value: U64, want: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { let got = mir_v5_value_type(store, indexes, f, value)
if got != want { return mir_v5_bad(d, out, mir_vdiag_bad_operand_type(), f, b, i, t, operand, want, got, value) }
return Ok(out) }
fn mir_v5_edge(d: Domain, store: MirStore, indexes: MirVIndexes, out: Vec(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, kind: U64, owner: U64, edge: U64, target: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var result = out
let count = mir_v5_operand_count(store, indexes, kind, owner, edge)
var n: U64 = 0
while n < count { let oi = mir_v5_operand(store, indexes, kind, owner, edge, n)
let o = (store.operands)[oi - 1]
result = try mir_v5_expect(d, store, indexes, result, f, b, i, t, oi, o.value, mir_v5_param_type(store, indexes, f, target, mir_param_block(), n))
n = n + 1 }
return Ok(result) }
fn mir_v5_expect_read(d: Domain, read: MirV5Read, out: Vec(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, operand: U64, value: U64, want: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { let got = mir_v5_value_type_read(read, f, value)
if got != want { return mir_v5_bad(d, out, mir_vdiag_bad_operand_type(), f, b, i, t, operand, want, got, value) }
return Ok(out) }
fn mir_v5_edge_read(d: Domain, read: MirV5Read, out: Vec(MirVerifyDiagRec), f: U64, b: U64, i: U64, t: U64, kind: U64, owner: U64, edge: U64, target: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var result = out
let count = mir_v5_operand_count_read(read, kind, owner, edge)
var n: U64 = 0
while n < count { let oi = mir_v5_operand_read(read, kind, owner, edge, n)
let o = read.base.operands[oi - 1]
result = try mir_v5_expect_read(d, read, result, f, b, i, t, oi, o.value, mir_v5_param_type_read(read, f, target, mir_param_block(), n))
n = n + 1 }
return Ok(result) }

fn mir_v5_args_match(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64, target: U64, import_call: Bool) -> Bool {
    let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
    var want: U64 = 0
    if import_call { want = mir_v5_operand_count(store, indexes, mir_operand_import_param(), target, 0) } else { want = mir_v5_function_param_count(store, indexes, target) }
    if got != want { return false }
    var ordinal: U64 = 0
    while ordinal < got {
        let argument = (store.operands)[mir_v5_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal) - 1]
        var expected: U64 = 0
        if import_call { expected = (store.operands)[mir_v5_operand(store, indexes, mir_operand_import_param(), target, 0, ordinal) - 1].operand_type } else { expected = mir_v5_param_type(store, indexes, target, 0, mir_param_function(), ordinal) }
        if mir_v5_value_type(store, indexes, function, argument.value) != expected { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_aggregate_matches(store: MirStore, indexes: MirVIndexes, function: U64, instruction: U64, type_id: U64) -> Bool {
    let kind = mir_vtype_kind(store, type_id)
    if kind != mir_type_kind_aggregate() && kind != mir_type_kind_array() { return false }
    let count = mir_v5_operand_count(store, indexes, mir_operand_aggregate_field(), instruction, 0)
    if kind == mir_type_kind_array() {
        let array = (store.types)[type_id - 1]
        if count != array.length { return false }
        var element: U64 = 0
        while element < count {
            let item = (store.operands)[mir_v5_operand(store, indexes, mir_operand_aggregate_field(), instruction, 0, element) - 1]
            if item.name_start != item.name_end || mir_v5_value_type(store, indexes, function, item.value) != array.elem { return false }
            element = element + 1
        }
        return true
    }
    if count != mir_v5_type_part_count(store, indexes, type_id, mir_type_part_field()) { return false }
    var ordinal: U64 = 0
    while ordinal < count {
        let field = (store.operands)[mir_v5_operand(store, indexes, mir_operand_aggregate_field(), instruction, 0, ordinal) - 1]
        var found: U64 = 0
        let total = mir_vindex_type_part_count(indexes, type_id)
        var at: U64 = 0
        while at < total {
            let part = (store.type_parts)[mir_vindex_type_part(indexes, type_id, at) - 1]
            if part.kind == mir_type_part_field() && mir_vname_equal(store, field.name_start, field.name_end, part.name_start, part.name_end) { found = part.part_type }
            at = at + 1
        }
        if found == 0 || mir_v5_value_type(store, indexes, function, field.value) != found { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_v5_args_match_read(read: MirV5Read, function: U64, instruction: U64, target: U64, import_call: Bool) -> Bool {
    let got = mir_v5_operand_count_read(read, mir_operand_instruction(), instruction, 0)
    var want: U64 = 0
    if import_call { want = mir_v5_operand_count_read(read, mir_operand_import_param(), target, 0) } else { want = mir_v5_function_param_count_read(read, target) }
    if got != want { return false }
    var ordinal: U64 = 0
    while ordinal < got {
        let argument = read.base.operands[mir_v5_operand_read(read, mir_operand_instruction(), instruction, 0, ordinal) - 1]
        var expected: U64 = 0
        if import_call { expected = read.base.operands[mir_v5_operand_read(read, mir_operand_import_param(), target, 0, ordinal) - 1].operand_type } else { expected = mir_v5_param_type_read(read, target, 0, mir_param_function(), ordinal) }
        if mir_v5_value_type_read(read, function, argument.value) != expected { return false }
        ordinal = ordinal + 1
    }
    return true
}
fn mir_v5_type_part_count_read(read: MirV5Read, owner: U64, kind: U64) -> U64 {
    let total = read.base.tp_count[owner - 1]
    var count: U64 = 0
    var at: U64 = 0
    while at < total { if read.base.type_parts[mir_v3_type_part(read.base, owner, at) - 1].kind == kind { count = count + 1 }
    at = at + 1 }
    return count
}
fn mir_v5_aggregate_matches_read(read: MirV5Read, function: U64, instruction: U64, type_id: U64) -> Bool {
    let kind = mir_v3_type_kind(read.base, type_id)
    if kind != mir_type_kind_aggregate() && kind != mir_type_kind_array() { return false }
    let count = mir_v5_operand_count_read(read, mir_operand_aggregate_field(), instruction, 0)
    if kind == mir_type_kind_array() {
        let array = read.base.types[type_id - 1]
        if count != array.length { return false }
        var element: U64 = 0
        while element < count { let item = read.base.operands[mir_v5_operand_read(read, mir_operand_aggregate_field(), instruction, 0, element) - 1]
            if item.name_start != item.name_end || mir_v5_value_type_read(read, function, item.value) != array.elem { return false }
            element = element + 1 }
        return true
    }
    if count != mir_v5_type_part_count_read(read, type_id, mir_type_part_field()) { return false }
    var ordinal: U64 = 0
    while ordinal < count {
        let field = read.base.operands[mir_v5_operand_read(read, mir_operand_aggregate_field(), instruction, 0, ordinal) - 1]
        var found: U64 = 0
        let total = read.base.tp_count[type_id - 1]
        var at: U64 = 0
        while at < total { let part = read.base.type_parts[mir_v3_type_part(read.base, type_id, at) - 1]
            if part.kind == mir_type_part_field() && mir_v3_name_equal(read.base, field.name_start, field.name_end, part.name_start, part.name_end) { found = part.part_type }
            at = at + 1
        }
        if found == 0 || mir_v5_value_type_read(read, function, field.value) != found { return false }
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
    if x.op == mir_op_copy_to_domain_try() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && mir_v5_capacity_error(store, x.type_op), type_id: mir_v5_find_result(store, tb, x.type_op)) }
    if x.op == mir_op_cleanup_scope_begin() { return MirVTypeResult(valid: true, type_id: mir_v5_find_kind(indexes, mir_type_kind_cleanup_scope())) }
    if x.op == mir_op_cleanup_push() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_cleanup_scope()) && (store.functions)[x.target - 1].result_type == mir_type_unit() && mir_v5_args_match(store, indexes, x.function, id, x.target, false), type_id: mir_v5_find_kind(indexes, mir_type_kind_cleanup_id())) }
    if x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: ta) }
    if x.op == mir_op_slice_len() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0, type_id: mir_type_u64()) }
    if x.op == mir_op_slice_index_checked() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0 && tb == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_array_index_checked() { let array = mir_v5_array_type(store, ta)
    if array == 0 { return MirVTypeResult(valid: false, type_id: 0) }
    return MirVTypeResult(valid: tb == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), (store.types)[array - 1].elem)) }
    if x.op == mir_op_slice_range_checked() { return MirVTypeResult(valid: mir_v5_elem(store, ta) != 0 && tb == mir_type_u64() && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_vec_new() { return MirVTypeResult(valid: mir_vtype_kind(store, x.type_op) == mir_type_kind_vec(), type_id: x.type_op) }
    if x.op == mir_op_vec_construct_checked() { let k = mir_vtype_kind(store, ta)
        let elem = mir_v5_elem(store, ta)
        return MirVTypeResult(valid: (k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut()) && tb == mir_type_u64() && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64(), type_id: mir_v5_find_unary(indexes, mir_type_kind_vec(), elem)) }
    if x.op == mir_op_vec_grow_checked() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec() && tb == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64(), type_id: ta) }
    if x.op == mir_op_vec_try_grow() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec() && tb == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && mir_v5_value_type(store, indexes, x.function, x.c) == mir_type_u64() && mir_v5_capacity_error(store, x.type_op), type_id: mir_v5_find_result(store, ta, x.type_op)) }
    if x.op == mir_op_vec_len() || x.op == mir_op_vec_capacity() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec(), type_id: mir_type_u64()) }
    if x.op == mir_op_vec_storage() || x.op == mir_op_vec_as_mut_slice() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec(), type_id: mir_v5_find_unary(indexes, mir_type_kind_safe_mut(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_vec_as_slice() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_vec(), type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), mir_v5_elem(store, ta))) }
    if x.op == mir_op_array_as_slice() { let array = mir_v5_array_view_type(store, ta)
        if array == 0 { return MirVTypeResult(valid: false, type_id: 0) }
        return MirVTypeResult(valid: true, type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), (store.types)[array - 1].elem)) }
    if x.op == mir_op_bytes_as_slice() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_bytes(), type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), mir_type_u8())) }
    if x.op == mir_op_string_as_bytes() { return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_string(), type_id: mir_v5_find_unary(indexes, mir_type_kind_slice(), mir_type_u8())) }
    if x.op == mir_op_bytes_try_from_vec() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()) && mir_vtype_kind(store, tb) == mir_type_kind_vec() && mir_v5_elem(store, tb) == mir_type_u8() && mir_v5_capacity_error(store, x.type_op), type_id: mir_v5_find_result(store, mir_v5_find_kind(indexes, mir_type_kind_bytes()), x.type_op)) }
    if x.op == mir_op_enum_payload_checked() { let p = mir_vcase_payload(store, indexes, ta, x.name_start, x.name_end)
return MirVTypeResult(valid: mir_v5_is_enum(store, ta) && p != 0 && p != mir_type_unit(), type_id: p) }
    if x.op == mir_op_enum_construct() { let payload = mir_vcase_payload(store, indexes, x.type_op, x.name_start, x.name_end)
return MirVTypeResult(valid: mir_v5_is_enum(store, x.type_op) && payload != 0 && ((payload == mir_type_unit() && x.a == 0) || (payload != mir_type_unit() && ta == payload)), type_id: x.type_op) }
    if x.op == mir_op_table_create() { return MirVTypeResult(valid: ta == mir_v5_find_kind(indexes, mir_type_kind_domain_handle()), type_id: mir_v5_find_unary(indexes, mir_type_kind_table(), x.type_op)) }
    if x.op == mir_op_table_insert() { let elem = (store.types)[ta - 1].elem
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == elem, type_id: mir_v5_find_unary(indexes, mir_type_kind_id(), elem)) }
    if x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { let elem = (store.types)[ta - 1].elem
var view_kind = mir_type_kind_table_view()
if x.op == mir_op_table_lookup_mut() { view_kind = mir_type_kind_table_mut_view() }
let view = mir_v5_find_unary(indexes, view_kind, elem)
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == mir_v5_find_unary(indexes, mir_type_kind_id(), elem), type_id: mir_v5_find_unary(indexes, mir_type_kind_option(), view)) }
    if x.op == mir_op_table_remove() { let elem = (store.types)[ta - 1].elem
return MirVTypeResult(valid: mir_vtype_kind(store, ta) == mir_type_kind_table() && tb == mir_v5_find_unary(indexes, mir_type_kind_id(), elem), type_id: mir_type_bool()) }
    if x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { return MirVTypeResult(valid: mir_v5_is_float(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op == mir_op_int_trunc() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_zext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_sext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_float_convert() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_int_from_float() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_int(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_float_from_int() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_const_get() { let ct = mir_v5_const_type(store, indexes, x.name_start, x.name_end)
return MirVTypeResult(valid: ct != 0, type_id: ct) }
    if x.op == mir_op_call() { return MirVTypeResult(valid: mir_v5_args_match(store, indexes, x.function, id, x.target, false), type_id: (store.functions)[x.target - 1].result_type) }
    if x.op == mir_op_ffi_call_unsafe() { return MirVTypeResult(valid: mir_v5_args_match(store, indexes, x.function, id, x.target, true), type_id: (store.imports)[x.target - 1].result_type) }
    return MirVTypeResult(valid: false, type_id: 0)
}

fn mir_v5_infer_read(read: MirV5Read, id: U64, x: MirInstrRec) -> MirVTypeResult {
    let ta = mir_v5_value_type_read(read, x.function, x.a)
    let tb = mir_v5_value_type_read(read, x.function, x.b)
    if x.op == mir_op_load() { return mir_v5_place_type_read(read, x.function, x.place) }
    if x.op == mir_op_borrow() { let p = mir_v5_place_type_read(read, x.function, x.place)
    return MirVTypeResult(valid: p.valid, type_id: mir_v5_read_unary(read, mir_type_kind_safe_ref(), p.type_id)) }
    if x.op == mir_op_borrow_mut() { let p = mir_v5_place_type_read(read, x.function, x.place)
    return MirVTypeResult(valid: p.valid, type_id: mir_v5_read_unary(read, mir_type_kind_safe_mut(), p.type_id)) }
    if x.op == mir_op_aggregate_construct() { return MirVTypeResult(valid: mir_v5_aggregate_matches_read(read, x.function, id, x.type_op), type_id: x.type_op) }
    if x.op == mir_op_domain_create() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()), type_id: mir_v5_read_kind(read, mir_type_kind_domain_handle())) }
    if x.op == mir_op_domain_mark() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()), type_id: mir_v5_read_kind(read, mir_type_kind_domain_mark())) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()) && tb == mir_type_u64(), type_id: mir_v5_read_unary(read, mir_type_kind_safe_mut(), x.type_op)) }
    if x.op == mir_op_copy_to_domain() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()), type_id: tb) }
    if x.op == mir_op_copy_to_domain_try() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()) && mir_v5_capacity_error_read(read, x.type_op), type_id: mir_v5_find_result_read(read, tb, x.type_op)) }
    if x.op == mir_op_cleanup_scope_begin() { return MirVTypeResult(valid: true, type_id: mir_v5_read_kind(read, mir_type_kind_cleanup_scope())) }
    if x.op == mir_op_cleanup_push() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_cleanup_scope()) && read.base.functions[x.target - 1].result_type == mir_type_unit() && mir_v5_args_match_read(read, x.function, id, x.target, false), type_id: mir_v5_read_kind(read, mir_type_kind_cleanup_id())) }
    if x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: ta) }
    if x.op == mir_op_slice_len() { return MirVTypeResult(valid: mir_v5_elem_read(read, ta) != 0, type_id: mir_type_u64()) }
    if x.op == mir_op_slice_index_checked() { return MirVTypeResult(valid: mir_v5_elem_read(read, ta) != 0 && tb == mir_type_u64(), type_id: mir_v5_read_unary(read, mir_type_kind_safe_mut(), mir_v5_elem_read(read, ta))) }
    if x.op == mir_op_array_index_checked() { let array = mir_v5_array_type_read(read, ta)
    if array == 0 { return MirVTypeResult(valid: false, type_id: 0) }
    return MirVTypeResult(valid: tb == mir_type_u64(), type_id: mir_v5_read_unary(read, mir_type_kind_safe_mut(), read.base.types[array - 1].elem)) }
    if x.op == mir_op_slice_range_checked() { return MirVTypeResult(valid: mir_v5_elem_read(read, ta) != 0 && tb == mir_type_u64() && mir_v5_value_type_read(read, x.function, x.c) == mir_type_u64(), type_id: mir_v5_read_unary(read, mir_type_kind_slice(), mir_v5_elem_read(read, ta))) }
    if x.op == mir_op_vec_new() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, x.type_op) == mir_type_kind_vec(), type_id: x.type_op) }
    if x.op == mir_op_vec_construct_checked() { let k = mir_v3_type_kind(read.base, ta)
        let elem = mir_v5_elem_read(read, ta)
        return MirVTypeResult(valid: (k == mir_type_kind_slice() || k == mir_type_kind_safe_ref() || k == mir_type_kind_safe_mut()) && tb == mir_type_u64() && mir_v5_value_type_read(read, x.function, x.c) == mir_type_u64(), type_id: mir_v5_read_unary(read, mir_type_kind_vec(), elem)) }
    if x.op == mir_op_vec_grow_checked() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_vec() && tb == mir_v5_read_kind(read, mir_type_kind_domain_handle()) && mir_v5_value_type_read(read, x.function, x.c) == mir_type_u64(), type_id: ta) }
    if x.op == mir_op_vec_try_grow() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_vec() && tb == mir_v5_read_kind(read, mir_type_kind_domain_handle()) && mir_v5_value_type_read(read, x.function, x.c) == mir_type_u64() && mir_v5_capacity_error_read(read, x.type_op), type_id: mir_v5_find_result_read(read, ta, x.type_op)) }
    if x.op == mir_op_vec_len() || x.op == mir_op_vec_capacity() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_vec(), type_id: mir_type_u64()) }
    if x.op == mir_op_vec_storage() || x.op == mir_op_vec_as_mut_slice() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_vec(), type_id: mir_v5_read_unary(read, mir_type_kind_safe_mut(), mir_v5_elem_read(read, ta))) }
    if x.op == mir_op_vec_as_slice() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_vec(), type_id: mir_v5_read_unary(read, mir_type_kind_slice(), mir_v5_elem_read(read, ta))) }
    if x.op == mir_op_array_as_slice() { let array = mir_v5_array_view_type_read(read, ta)
        if array == 0 { return MirVTypeResult(valid: false, type_id: 0) }
        return MirVTypeResult(valid: true, type_id: mir_v5_read_unary(read, mir_type_kind_slice(), read.base.types[array - 1].elem)) }
    if x.op == mir_op_bytes_as_slice() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_bytes(), type_id: mir_v5_read_unary(read, mir_type_kind_slice(), mir_type_u8())) }
    if x.op == mir_op_string_as_bytes() { return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_string(), type_id: mir_v5_read_unary(read, mir_type_kind_slice(), mir_type_u8())) }
    if x.op == mir_op_bytes_try_from_vec() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()) && mir_v3_type_kind(read.base, tb) == mir_type_kind_vec() && mir_v5_elem_read(read, tb) == mir_type_u8() && mir_v5_capacity_error_read(read, x.type_op), type_id: mir_v5_find_result_read(read, mir_v5_read_kind(read, mir_type_kind_bytes()), x.type_op)) }
    if x.op == mir_op_enum_payload_checked() { let p = mir_vcase_payload_read(read.base, ta, x.name_start, x.name_end)
    return MirVTypeResult(valid: mir_v5_is_enum_read(read, ta) && p != 0 && p != mir_type_unit(), type_id: p) }
    if x.op == mir_op_enum_construct() { let payload = mir_vcase_payload_read(read.base, x.type_op, x.name_start, x.name_end)
    return MirVTypeResult(valid: mir_v5_is_enum_read(read, x.type_op) && payload != 0 && ((payload == mir_type_unit() && x.a == 0) || (payload != mir_type_unit() && ta == payload)), type_id: x.type_op) }
    if x.op == mir_op_table_create() { return MirVTypeResult(valid: ta == mir_v5_read_kind(read, mir_type_kind_domain_handle()), type_id: mir_v5_read_unary(read, mir_type_kind_table(), x.type_op)) }
    if x.op == mir_op_table_insert() { let elem = read.base.types[ta - 1].elem
    return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_table() && tb == elem, type_id: mir_v5_read_unary(read, mir_type_kind_id(), elem)) }
    if x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { let elem = read.base.types[ta - 1].elem
    var view_kind = mir_type_kind_table_view()
    if x.op == mir_op_table_lookup_mut() { view_kind = mir_type_kind_table_mut_view() }
    let view = mir_v5_read_unary(read, view_kind, elem)
    return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_table() && tb == mir_v5_read_unary(read, mir_type_kind_id(), elem), type_id: mir_v5_read_unary(read, mir_type_kind_option(), view)) }
    if x.op == mir_op_table_remove() { let elem = read.base.types[ta - 1].elem
    return MirVTypeResult(valid: mir_v3_type_kind(read.base, ta) == mir_type_kind_table() && tb == mir_v5_read_unary(read, mir_type_kind_id(), elem), type_id: mir_type_bool()) }
    if x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge() { return MirVTypeResult(valid: mir_v5_is_int(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { return MirVTypeResult(valid: mir_v5_is_float(ta) && ta == tb, type_id: mir_type_bool()) }
    if x.op == mir_op_int_trunc() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_zext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_int_sext() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta), type_id: x.type_op) }
    if x.op == mir_op_float_convert() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_int_from_float() { return MirVTypeResult(valid: mir_v5_is_float(ta) && mir_v5_is_int(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_float_from_int() { return MirVTypeResult(valid: mir_v5_is_int(ta) && mir_v5_is_float(x.type_op), type_id: x.type_op) }
    if x.op == mir_op_const_get() { let ct = mir_v5_const_type_read(read, x.name_start, x.name_end)
    return MirVTypeResult(valid: ct != 0, type_id: ct) }
    if x.op == mir_op_call() { return MirVTypeResult(valid: mir_v5_args_match_read(read, x.function, id, x.target, false), type_id: read.base.functions[x.target - 1].result_type) }
    if x.op == mir_op_ffi_call_unsafe() { return MirVTypeResult(valid: mir_v5_args_match_read(read, x.function, id, x.target, true), type_id: read.imports[x.target - 1].result_type) }
    return MirVTypeResult(valid: false, type_id: 0)
}

fn mir_v5_check_args(d: Domain, store: MirStore, indexes: MirVIndexes, out: Vec(MirVerifyDiagRec), x: MirInstrRec, id: U64, target: U64, import_call: Bool) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var result = out
let got = mir_v5_operand_count(store, indexes, mir_operand_instruction(), id, 0)
var want: U64 = 0
if import_call { want = mir_v5_operand_count(store, indexes, mir_operand_import_param(), target, 0) } else { want = mir_v5_function_param_count(store, indexes, target) }
if got != want { return mir_v5_bad(d, result, mir_vdiag_bad_argument_count(), x.function, x.block, id, 0, 0, want, got, target) }
var n: U64 = 0
while n < got { let oi = mir_v5_operand(store, indexes, mir_operand_instruction(), id, 0, n)
let o = (store.operands)[oi - 1]
var expected: U64 = 0
if import_call { let pi = mir_v5_operand(store, indexes, mir_operand_import_param(), target, 0, n)
expected = (store.operands)[pi - 1].operand_type } else { expected = mir_v5_param_type(store, indexes, target, 0, mir_param_function(), n) }
result = try mir_v5_expect(d, store, indexes, result, x.function, x.block, id, 0, oi, o.value, expected)
n = n + 1 }
return Ok(result) }
fn mir_v5_check_args_read(d: Domain, read: MirV5Read, out: Vec(MirVerifyDiagRec), x: MirInstrRec, id: U64, target: U64, import_call: Bool) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var result = out
let got = mir_v5_operand_count_read(read, mir_operand_instruction(), id, 0)
var want: U64 = 0
if import_call { want = mir_v5_operand_count_read(read, mir_operand_import_param(), target, 0) } else { want = mir_v5_function_param_count_read(read, target) }
if got != want { return mir_v5_bad(d, result, mir_vdiag_bad_argument_count(), x.function, x.block, id, 0, 0, want, got, target) }
var n: U64 = 0
while n < got { let oi = mir_v5_operand_read(read, mir_operand_instruction(), id, 0, n)
let o = read.base.operands[oi - 1]
var expected: U64 = 0
if import_call { let pi = mir_v5_operand_read(read, mir_operand_import_param(), target, 0, n)
expected = read.base.operands[pi - 1].operand_type } else { expected = mir_v5_param_type_read(read, target, 0, mir_param_function(), n) }
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, oi, o.value, expected)
n = n + 1 }
return Ok(result) }

fn mir_v5_instruction_read(d: Domain, read: MirV5Read, out: Vec(MirVerifyDiagRec), id: U64, x: MirInstrRec) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    var result = out
let baseline = (out).len()
    if x.op == mir_op_load() || x.op == mir_op_store() || x.op == mir_op_borrow() || x.op == mir_op_borrow_mut() { let p = mir_v5_place_type_read(read, x.function, x.place)
if !p.valid { result = try mir_v5_bad(d, result, mir_vdiag_bad_place_type(), x.function, x.block, id, 0, x.place, 0, 0, x.place) } else { if x.op == mir_op_store() || x.op == mir_op_borrow_mut() { if !mir_v5_place_mutable_read(read, x.function, x.place) { result = try mir_v5_bad(d, result, mir_vdiag_readonly_place(), x.function, x.block, id, 0, x.place, 0, p.type_id, x.place) }
if x.op == mir_op_store() {
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, p.type_id) } } } }
    if x.op == mir_op_aggregate_construct() { var fields = mir_v5_type_part_count_read(read, x.type_op, mir_type_part_field())
if mir_v3_type_kind(read.base, x.type_op) == mir_type_kind_array() { fields = read.base.types[x.type_op - 1].length }
let got = mir_v5_operand_count_read(read, mir_operand_aggregate_field(), id, 0)
if (mir_v3_type_kind(read.base, x.type_op) != mir_type_kind_aggregate() && mir_v3_type_kind(read.base, x.type_op) != mir_type_kind_array()) || got != fields { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, 0, fields, got, x.type_op) } else { var n: U64 = 0
while n < got { let oi = mir_v5_operand_read(read, mir_operand_aggregate_field(), id, 0, n)
let o = read.base.operands[oi - 1]
if mir_v3_type_kind(read.base, x.type_op) == mir_type_kind_array() {
if o.name_start != o.name_end { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, oi, n, o.ordinal, x.type_op) }
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, oi, o.value, read.base.types[x.type_op - 1].elem) }
let total = read.base.tp_count[x.type_op - 1]
var pi: U64 = 0
while pi < total { let pid = mir_v3_type_part(read.base, x.type_op, pi)
let p = read.base.type_parts[pid - 1]
if p.kind == mir_type_part_field() && p.ordinal == n { if !mir_v3_name_equal(read.base, o.name_start, o.name_end, p.name_start, p.name_end) { result = try mir_v5_bad(d, result, mir_vdiag_bad_aggregate(), x.function, x.block, id, 0, oi, n, o.ordinal, pid) }
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, oi, o.value, p.part_type) }
pi = pi + 1 }
n = n + 1 } } }
    if x.op == mir_op_domain_create() || x.op == mir_op_domain_mark() || x.op == mir_op_domain_destroy() || x.op == mir_op_table_create() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_domain_handle())) }
    if x.op == mir_op_domain_reset() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_domain_handle()))
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_v5_read_kind(read, mir_type_kind_domain_mark())) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_domain_handle()))
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
    if x.op == mir_op_copy_to_domain() || x.op == mir_op_copy_to_domain_try() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_domain_handle()))
        if x.op == mir_op_copy_to_domain_try() && !mir_v5_capacity_error_read(read, x.type_op) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, 0, x.type_op, x.type_op) } }
    if x.op == mir_op_cleanup_push() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_cleanup_scope()))
result = try mir_v5_check_args_read(d, read, result, x, id, x.target, false)
if read.base.functions[x.target - 1].result_type != mir_type_unit() { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, mir_type_unit(), read.base.functions[x.target - 1].result_type, x.target) } }
    if x.op == mir_op_cleanup_disarm() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_cleanup_id())) }
    if x.op == mir_op_cleanup_scope_run() || x.op == mir_op_cleanup_scope_end() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_cleanup_scope())) }
    if (x.op >= mir_op_int_add_checked() && x.op <= mir_op_int_shr_checked()) || (x.op >= mir_op_int_eq() && x.op <= mir_op_int_ge()) { let ta = mir_v5_value_type_read(read, x.function, x.a)
let tb = mir_v5_value_type_read(read, x.function, x.b)
if !mir_v5_is_int(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op >= mir_op_float_eq() && x.op <= mir_op_float_ge() { let ta = mir_v5_value_type_read(read, x.function, x.a)
let tb = mir_v5_value_type_read(read, x.function, x.b)
if !mir_v5_is_float(ta) || ta != tb { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, ta, tb, x.b) } }
    if x.op == mir_op_slice_len() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() { if mir_v5_elem_read(read, mir_v5_value_type_read(read, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_slice(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) }
if x.op != mir_op_slice_len() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
if x.op == mir_op_slice_range_checked() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) } }
    if x.op == mir_op_array_index_checked() { if mir_v5_array_type_read(read, mir_v5_value_type_read(read, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_array(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) }
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64()) }
    if x.op == mir_op_vec_new() { if mir_v3_type_kind(read.base, x.type_op) != mir_type_kind_vec() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_v3_type_kind(read.base, x.type_op), x.type_op) } }
    if x.op == mir_op_vec_construct_checked() { let k = mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a))
        if k != mir_type_kind_slice() && k != mir_type_kind_safe_ref() && k != mir_type_kind_safe_mut() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_slice(), k, x.a) }
        result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_type_u64())
        result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) }
    if x.op == mir_op_vec_grow_checked() { if mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)) != mir_type_kind_vec() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) }
        result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_v5_read_kind(read, mir_type_kind_domain_handle()))
        result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) }
    if x.op == mir_op_vec_try_grow() { if mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)) != mir_type_kind_vec() || !mir_v5_capacity_error_read(read, x.type_op) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) }
        result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, mir_v5_read_kind(read, mir_type_kind_domain_handle()))
        result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.c, mir_type_u64()) }
    if x.op >= mir_op_vec_len() && x.op <= mir_op_vec_as_mut_slice() { if mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)) != mir_type_kind_vec() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) } }
    if x.op == mir_op_array_as_slice() { if mir_v5_array_view_type_read(read, mir_v5_value_type_read(read, x.function, x.a)) == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_array(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) } }
    if x.op == mir_op_bytes_as_slice() && mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)) != mir_type_kind_bytes() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_bytes(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) }
    if x.op == mir_op_string_as_bytes() && mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)) != mir_type_kind_string() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_string(), mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a)), x.a) }
    if x.op == mir_op_bytes_try_from_vec() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, mir_v5_read_kind(read, mir_type_kind_domain_handle()))
        let vec_type = mir_v5_value_type_read(read, x.function, x.b)
        if mir_v3_type_kind(read.base, vec_type) != mir_type_kind_vec() || mir_v5_elem_read(read, vec_type) != mir_type_u8() || !mir_v5_capacity_error_read(read, x.type_op) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_vec(), mir_v3_type_kind(read.base, vec_type), x.b) } }
    if x.op == mir_op_enum_payload_checked() || x.op == mir_op_enum_construct() { var et = mir_v5_value_type_read(read, x.function, x.a)
if x.op == mir_op_enum_construct() { et = x.type_op }
let payload = mir_vcase_payload_read(read.base, et, x.name_start, x.name_end)
if !mir_v5_is_enum_read(read, et) || payload == 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_variant(), x.function, x.block, id, 0, 0, et, 0, et) } else { if x.op == mir_op_enum_construct() { if payload == mir_type_unit() && x.a != 0 { result = try mir_v5_bad(d, result, mir_vdiag_bad_variant(), x.function, x.block, id, 0, 0, 0, mir_v5_value_type_read(read, x.function, x.a), et) }
if payload != mir_type_unit() { result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.a, payload) } } } }
    if x.op >= mir_op_table_insert() && x.op <= mir_op_table_remove() { let table = mir_v5_value_type_read(read, x.function, x.a)
if mir_v3_type_kind(read.base, table) != mir_type_kind_table() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_table(), mir_v3_type_kind(read.base, table), x.a) } else { let elem = read.base.types[table - 1].elem
var want = mir_v5_read_unary(read, mir_type_kind_id(), elem)
if x.op == mir_op_table_insert() { want = elem }
result = try mir_v5_expect_read(d, read, result, x.function, x.block, id, 0, 0, x.b, want) } }
    if x.op == mir_op_table_view_end() { let k = mir_v3_type_kind(read.base, mir_v5_value_type_read(read, x.function, x.a))
if k != mir_type_kind_table_view() && k != mir_type_kind_table_mut_view() { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), x.function, x.block, id, 0, 0, mir_type_kind_table_view(), k, x.a) } }
    if x.op >= mir_op_int_trunc() && x.op <= mir_op_float_from_int() { let ta = mir_v5_value_type_read(read, x.function, x.a)
var valid = true
if x.op == mir_op_int_trunc() { valid = mir_v5_is_int(ta) && mir_v5_is_int(x.type_op) && ((mir_v5_signed(ta) && mir_v5_signed(x.type_op)) || (!mir_v5_signed(ta) && !mir_v5_signed(x.type_op))) && mir_v5_width(x.type_op) < mir_v5_width(ta) }
if x.op == mir_op_int_zext() { valid = mir_v5_is_int(ta) && !mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta) }
if x.op == mir_op_int_sext() { valid = mir_v5_is_int(ta) && mir_v5_signed(ta) && mir_v5_is_int(x.type_op) && mir_v5_width(x.type_op) > mir_v5_width(ta) }
if x.op == mir_op_float_convert() { valid = mir_v5_is_float(ta) && mir_v5_is_float(x.type_op) }
if x.op == mir_op_int_from_float() { valid = mir_v5_is_float(ta) && mir_v5_is_int(x.type_op) }
if x.op == mir_op_float_from_int() { valid = mir_v5_is_int(ta) && mir_v5_is_float(x.type_op) }
if !valid { result = try mir_v5_bad(d, result, mir_vdiag_bad_conversion(), x.function, x.block, id, 0, 0, x.type_op, ta, x.a) } }
    if x.op == mir_op_call() { result = try mir_v5_check_args_read(d, read, result, x, id, x.target, false) }
    if x.op == mir_op_ffi_call_unsafe() { result = try mir_v5_check_args_read(d, read, result, x, id, x.target, true) }
    if mir_vop_checked(x.op) { result = try mir_v5_edge_read(d, read, result, x.function, x.block, id, 0, mir_operand_checked_edge_arg(), id, 0, x.target) }
    if x.result != 0 { let inferred = mir_v5_infer_read(read, id, x)
let stored = mir_v5_value_type_read(read, x.function, x.result)
if !inferred.valid { if (result).len() == baseline { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, 0, stored, x.result) } } else { if stored != inferred.type_id { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), x.function, x.block, id, 0, 0, inferred.type_id, stored, x.result) } } }
    return Ok(result)
}

fn mir_v5_terminator_read(d: Domain, read: MirV5Read, out: Vec(MirVerifyDiagRec), id: U64, t: MirTermRec) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var result = out
    if t.kind == mir_term_branch() { result = try mir_v5_expect_read(d, read, result, t.function, t.block, 0, id, 0, t.value, mir_type_bool())
result = try mir_v5_edge_read(d, read, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_then(), t.then_block)
result = try mir_v5_edge_read(d, read, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_else(), t.else_block) }
    if t.kind == mir_term_jump() { result = try mir_v5_edge_read(d, read, result, t.function, t.block, 0, id, mir_operand_terminator_arg(), id, mir_edge_jump(), t.target) }
    if t.kind == mir_term_switch() { let et = mir_v5_value_type_read(read, t.function, t.value)
if !mir_v5_is_enum_read(read, et) { result = try mir_v5_bad(d, result, mir_vdiag_bad_operand_type(), t.function, t.block, 0, id, 0, mir_type_kind_enum(), mir_v3_type_kind(read.base, et), t.value) }
let ccount = read.base.op_term_count[id - 1]
var at: U64 = 0
while at < ccount {
    let cid = mir_v3_op_term(read.base, id, at)
    let c = read.base.operands[cid - 1]
    if c.kind == mir_operand_switch_case() { if c.name_start != c.name_end && c.value != 0 { result = try mir_v5_expect_read(d, read, result, t.function, t.block, 0, id, cid, c.value, mir_vcase_payload_read(read.base, et, c.name_start, c.name_end)) }
result = try mir_v5_edge_read(d, read, result, t.function, t.block, 0, id, mir_operand_switch_case_arg(), cid, 0, c.target) }
    at = at + 1
} }
    if t.kind == mir_term_return() || t.kind == mir_term_fail() { let want = read.base.functions[t.function - 1].result_type
if t.value == 0 { if want != mir_type_unit() { result = try mir_v5_bad(d, result, mir_vdiag_bad_result_type(), t.function, t.block, 0, id, 0, mir_type_unit(), want, t.function) } } else { result = try mir_v5_expect_read(d, read, result, t.function, t.block, 0, id, 0, t.value, want) } }
    return Ok(result)
}

fn mir_vphase5_read(d: Domain, initial: Vec(MirVerifyDiagRec), read: MirV5Read) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var function: U64 = 1
    while function <= len(read.base.functions) {
        // Parameter and switch binding types are not inferred and must
        // themselves carry a valid type, matching the Go verifier's first pass.
        var value: U64 = 1
        while mir_v3_value(read.base, function, value) != 0 {
            let vi = mir_v3_value(read.base, function, value)
            let v = read.base.values[vi - 1]
            if (v.def_kind == mir_value_def_block_param() || v.def_kind == mir_value_def_switch_case()) && mir_v3_type_kind(read.base, v.value_type) == 999 { out = try mir_v5_bad(d, out, mir_vdiag_invalid_value_type(), v.function, v.block, 0, 0, 0, 0, v.value_type, vi) }
            value = value + 1
        }
        let bcount = read.base.block_count[function - 1]
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_v3_instr_count(read.base, function, block)
            var ordinal: U64 = 0
            while ordinal < icount {
                let ii = mir_v3_instr(read.base, function, block, ordinal)
                out = try mir_v5_instruction_read(d, read, out, ii, read.base.instructions[ii - 1])
                ordinal = ordinal + 1
            }
            let term_id = mir_v3_term(read.base, function, block)
            if term_id != 0 { out = try mir_v5_terminator_read(d, read, out, term_id, read.base.terminators[term_id - 1]) }
            block = block + 1
        }
        function = function + 1
    }
    return Ok(out)
}
