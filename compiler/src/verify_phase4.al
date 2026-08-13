// Point-level phase-4 verification for the flat MIR store.  Points are encoded
// as (block, instruction boundary); checked failure edges are represented by
// their source boundary, so an instruction result is unavailable on its own
// failure edge.
type MirVP4Use {
    value: U64
    block: U64
    instruction: U64
    terminator: U64
    operand: U64
    switch_case: U64
}

fn mir_vp4_instruction_at(store: MirStore, function: U64, block: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let i = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if i.function == function && i.block == block && i.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_vp4_instruction_count(store: MirStore, function: U64, block: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let i = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if i.function == function && i.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}
fn mir_vp4_use(d: Domain, uses: __s0_Buffer(MirVP4Use), value: U64, block: U64, instruction: U64, terminator: U64, operand: U64, switch_case: U64) -> Result(__s0_Buffer(MirVP4Use), __s0_Error) {
    if value == 0 { return Ok(uses) }
    return __s0_buffer_append(MirVP4Use, d, uses, MirVP4Use(value: value, block: block, instruction: instruction, terminator: terminator, operand: operand, switch_case: switch_case))
}
fn mir_vp4_place_uses(d: Domain, store: MirStore, uses0: __s0_Buffer(MirVP4Use), block: U64, instruction: U64, place: U64) -> Result(__s0_Buffer(MirVP4Use), __s0_Error) {
    var uses = uses0
    var current = place
    var steps: U64 = 0
    while current != 0 && steps <= __s0_buffer_len(MirPlaceRec, store.places) {
        let p = __s0_buffer_get(MirPlaceRec, store.places, current - 1)
        if p.kind == mir_place_deref() { return mir_vp4_use(d, uses, p.deref_value, block, instruction, 0, 0, 0) }
        if p.kind != mir_place_field() { return Ok(uses) }
        current = p.base
        steps = steps + 1
    }
    return Ok(uses)
}
fn mir_vp4_direct_uses(d: Domain, uses0: __s0_Buffer(MirVP4Use), i: MirInstrRec, id: U64) -> Result(__s0_Buffer(MirVP4Use), __s0_Error) {
    var uses = uses0
    if i.op == mir_op_store() || i.op == mir_op_domain_create() || i.op == mir_op_domain_mark() || i.op == mir_op_domain_destroy() || i.op == mir_op_cleanup_push() || i.op == mir_op_cleanup_disarm() || i.op == mir_op_cleanup_scope_run() || i.op == mir_op_cleanup_scope_end() || i.op == mir_op_slice_len() || i.op == mir_op_enum_payload_checked() || i.op == mir_op_enum_construct() || i.op == mir_op_table_create() || i.op == mir_op_table_view_end() || (i.op >= mir_op_int_trunc() && i.op <= mir_op_float_from_int()) { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0) }
    if i.op == mir_op_domain_reset() || i.op == mir_op_alloc() || i.op == mir_op_alloc_checked() || i.op == mir_op_copy_to_domain() || (i.op >= mir_op_int_add_checked() && i.op <= mir_op_int_shr_checked()) || i.op == mir_op_slice_index_checked() || (i.op >= mir_op_table_insert() && i.op <= mir_op_table_remove()) || (i.op >= mir_op_int_eq() && i.op <= mir_op_float_ge()) { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0) }
    if i.op == mir_op_slice_range_checked() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.c, i.block, id, 0, 0, 0) }
    return Ok(uses)
}
fn mir_vp4_collect_uses(d: Domain, store: MirStore, function: U64) -> Result(__s0_Buffer(MirVP4Use), __s0_Error) {
    var uses = try __s0_buffer_new(MirVP4Use, d)
    var block: U64 = 1
    while mir_vblock_index(store, function, block) != 0 {
        var ordinal: U64 = 0
        while ordinal < mir_vp4_instruction_count(store, function, block) {
            let id = mir_vp4_instruction_at(store, function, block, ordinal)
            let i = __s0_buffer_get(MirInstrRec, store.instructions, id - 1)
            uses = try mir_vp4_place_uses(d, store, uses, block, id, i.place)
            if (i.op == mir_op_load() || i.op == mir_op_store()) && __s0_buffer_get(MirPlaceRec, store.places, i.place - 1).kind == mir_place_deref() { uses = try mir_vp4_use(d, uses, __s0_buffer_get(MirPlaceRec, store.places, i.place - 1).deref_value, block, id, 0, 0, 0) }
            uses = try mir_vp4_direct_uses(d, uses, i, id)
            var pass: U64 = 0
            while pass < 3 {
                var kind = mir_operand_instruction()
                if pass == 1 { kind = mir_operand_aggregate_field() }
                if pass == 2 { kind = mir_operand_checked_edge_arg() }
                    var oi: U64 = 0
                    while oi < __s0_buffer_len(MirOperandRec, store.operands) {
                        let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
                        var belongs = i.op == mir_op_cleanup_push() || i.op == mir_op_call() || i.op == mir_op_ffi_call_unsafe()
                        if pass == 1 { belongs = i.op == mir_op_aggregate_construct() }
                        if pass == 2 { belongs = mir_vop_checked(i.op) }
                        if belongs && o.kind == kind && o.owner == id { uses = try mir_vp4_use(d, uses, o.value, block, id, 0, oi + 1, 0) }
                        oi = oi + 1
                    }
                pass = pass + 1
            }
            ordinal = ordinal + 1
        }
        var ti: U64 = 0
        while ti < __s0_buffer_len(MirTermRec, store.terminators) {
            let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
            if t.function == function && t.block == block {
                uses = try mir_vp4_use(d, uses, t.value, block, 0, ti + 1, 0, 0)
                var oi: U64 = 0
                while oi < __s0_buffer_len(MirOperandRec, store.operands) {
                    let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
                    if o.kind == mir_operand_terminator_arg() && o.owner == ti + 1 { uses = try mir_vp4_use(d, uses, o.value, block, 0, ti + 1, oi + 1, 0) }
                    if o.kind == mir_operand_switch_case() && o.owner == ti + 1 {
                        var ai: U64 = 0
                        while ai < __s0_buffer_len(MirOperandRec, store.operands) {
                            let a = __s0_buffer_get(MirOperandRec, store.operands, ai)
                            if a.kind == mir_operand_switch_case_arg() && a.owner == oi + 1 { uses = try mir_vp4_use(d, uses, a.value, block, 0, ti + 1, ai + 1, o.ordinal + 1) }
                            ai = ai + 1
                        }
                    }
                    oi = oi + 1
                }
            }
            ti = ti + 1
        }
        block = block + 1
    }
    return Ok(uses)
}

type MirVP4Point {
    block: U64
    position: U64
}
fn mir_vp4_point_seen(points: __s0_Buffer(MirVP4Point), block: U64, position: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirVP4Point, points) { let p = __s0_buffer_get(MirVP4Point, points, at)
if p.block == block && p.position == position { return true }
at = at + 1 }
return false }
fn mir_vp4_push_point(d: Domain, store: MirStore, function: U64, queue: __s0_Buffer(MirVP4Point), block: U64, position: U64, suppress_block: U64, suppress_position: U64) -> Result(__s0_Buffer(MirVP4Point), __s0_Error) {
    if block == suppress_block && position == suppress_position { return Ok(queue) }
    if mir_vblock_index(store, function, block) == 0 || position > mir_vp4_instruction_count(store, function, block) { return Ok(queue) }
    return __s0_buffer_append(MirVP4Point, d, queue, MirVP4Point(block: block, position: position))
}
// A point dominates a use exactly when suppressing it makes the use
// unreachable. Checked failures leave from the boundary before the checked
// instruction; only success advances to its result boundary.
fn mir_vphase4_point_dominates(d: Domain, store: MirStore, function: U64, def_kind: U64, def_block: U64, def_item: U64, use_block: U64, use_position: U64) -> Result(Bool, __s0_Error) {
    var suppress_block = def_block
    var suppress_position: U64 = 0
    if def_kind == mir_value_def_instruction() { suppress_position = def_item }
    if def_kind == mir_value_def_switch_case() { suppress_block = 0 }
    if def_kind != mir_value_def_block_param() && def_kind != mir_value_def_instruction() && def_kind != mir_value_def_switch_case() { return Ok(false) }
    if def_kind != mir_value_def_switch_case() && def_block == use_block && suppress_position == use_position { return Ok(true) }
    var queue = try __s0_buffer_new(MirVP4Point, d)
    var seen = try __s0_buffer_new(MirVP4Point, d)
    queue = try mir_vp4_push_point(d, store, function, queue, 1, 0, suppress_block, suppress_position)
    var q: U64 = 0
    while q < __s0_buffer_len(MirVP4Point, queue) {
        let p = __s0_buffer_get(MirVP4Point, queue, q)
        if !mir_vp4_point_seen(seen, p.block, p.position) {
            if p.block == use_block && p.position == use_position { return Ok(false) }
            seen = try __s0_buffer_append(MirVP4Point, d, seen, p)
            let count = mir_vp4_instruction_count(store, function, p.block)
            if p.position < count {
                let ins = __s0_buffer_get(MirInstrRec, store.instructions, mir_vp4_instruction_at(store, function, p.block, p.position) - 1)
                queue = try mir_vp4_push_point(d, store, function, queue, p.block, p.position + 1, suppress_block, suppress_position)
                if mir_vop_checked(ins.op) { queue = try mir_vp4_push_point(d, store, function, queue, ins.target, 0, suppress_block, suppress_position) }
            } else {
                var ti: U64 = 0
                while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
                    if t.function == function && t.block == p.block {
                        if t.kind == mir_term_jump() { queue = try mir_vp4_push_point(d, store, function, queue, t.target, 0, suppress_block, suppress_position) }
                        if t.kind == mir_term_branch() { queue = try mir_vp4_push_point(d, store, function, queue, t.then_block, 0, suppress_block, suppress_position)
queue = try mir_vp4_push_point(d, store, function, queue, t.else_block, 0, suppress_block, suppress_position) }
                        if t.kind == mir_term_switch() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let c = __s0_buffer_get(MirOperandRec, store.operands, oi)
if c.kind == mir_operand_switch_case() && c.owner == ti + 1 && !(def_kind == mir_value_def_switch_case() && def_block == p.block && c.ordinal + 1 == def_item) { queue = try mir_vp4_push_point(d, store, function, queue, c.target, 0, suppress_block, suppress_position) }
oi = oi + 1 } }
                    }
                    ti = ti + 1
                }
            }
        }
        q = q + 1
    }
    return Ok(true)
}

fn mir_vp4_place_root(store: MirStore, place: U64) -> U64 { if place == 0 { return 0 }
let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if p.kind == mir_place_local() { return p.local }
if p.kind != mir_place_field() { return 0 }
return mir_vp4_place_root(store, p.base) }
fn mir_vp4_place_depth(store: MirStore, place: U64) -> U64 { let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if p.kind == mir_place_local() { return 0 }
return mir_vp4_place_depth(store, p.base) + 1 }
fn mir_vp4_place_component(store: MirStore, place: U64, ordinal: U64) -> U64 { let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if ordinal + 1 == mir_vp4_place_depth(store, place) { return place }
return mir_vp4_place_component(store, p.base, ordinal) }
fn mir_vp4_place_type(store: MirStore, function: U64, place: U64) -> U64 { let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if p.kind == mir_place_local() { return __s0_buffer_get(MirLocalRec, store.locals, mir_vlocal_index(store, function, p.local) - 1).local_type }
let base = mir_vp4_place_type(store, function, p.base)
var at: U64 = 0
while at < __s0_buffer_len(MirTypePartRec, store.type_parts) { let f = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
if f.owner == base && f.kind == mir_type_part_field() && mir_vname_equal(store, p.field_start, p.field_end, f.name_start, f.name_end) { return f.part_type }
at = at + 1 }
return 0 }
// suffix contains canonical type-part IDs for fields below the loaded place.
fn mir_vp4_store_covers(store: MirStore, store_place: U64, load_place: U64, suffix: __s0_Buffer(U64)) -> Bool {
    if mir_vp4_place_root(store, store_place) != mir_vp4_place_root(store, load_place) { return false }
    let sd = mir_vp4_place_depth(store, store_place)
    let ld = mir_vp4_place_depth(store, load_place)
    if sd > ld + __s0_buffer_len(U64, suffix) { return false }
    var n: U64 = 0
    while n < sd { let sp = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, store_place, n) - 1)
        if n < ld { let lp = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, load_place, n) - 1)
if !mir_vname_equal(store, sp.field_start, sp.field_end, lp.field_start, lp.field_end) { return false } }
        else { let fp = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, suffix, n - ld) - 1)
if !mir_vname_equal(store, sp.field_start, sp.field_end, fp.name_start, fp.name_end) { return false } }
        n = n + 1
    }
    return true
}
// This is the Boolean form of the forward must analysis: retain only paths on
// which the leaf is still uninitialized. A covering store kills its success
// transition, while its checked failure transition remains at the pre-store
// boundary.
fn mir_vp4_leaf_initialized(d: Domain, store: MirStore, function: U64, load_place: U64, suffix: __s0_Buffer(U64), use_block: U64, use_position: U64) -> Result(Bool, __s0_Error) {
    var queue = try __s0_buffer_new(MirVP4Point, d)
    var seen = try __s0_buffer_new(MirVP4Point, d)
    queue = try __s0_buffer_append(MirVP4Point, d, queue, MirVP4Point(block: 1, position: 0))
    var q: U64 = 0
    while q < __s0_buffer_len(MirVP4Point, queue) { let p = __s0_buffer_get(MirVP4Point, queue, q)
        if !mir_vp4_point_seen(seen, p.block, p.position) {
            if p.block == use_block && p.position == use_position { return Ok(false) }
            seen = try __s0_buffer_append(MirVP4Point, d, seen, p)
            let count = mir_vp4_instruction_count(store, function, p.block)
            if p.position < count { let ins = __s0_buffer_get(MirInstrRec, store.instructions, mir_vp4_instruction_at(store, function, p.block, p.position) - 1)
                if !(ins.op == mir_op_store() && mir_vp4_store_covers(store, ins.place, load_place, suffix)) { queue = try mir_vp4_push_point(d, store, function, queue, p.block, p.position + 1, 0, 0) }
                if mir_vop_checked(ins.op) { queue = try mir_vp4_push_point(d, store, function, queue, ins.target, 0, 0, 0) }
            } else { var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && t.block == p.block {
if t.kind == mir_term_jump() { queue = try mir_vp4_push_point(d, store, function, queue, t.target, 0, 0, 0) }
if t.kind == mir_term_branch() { queue = try mir_vp4_push_point(d, store, function, queue, t.then_block, 0, 0, 0)
queue = try mir_vp4_push_point(d, store, function, queue, t.else_block, 0, 0, 0) }
if t.kind == mir_term_switch() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let c = __s0_buffer_get(MirOperandRec, store.operands, oi)
if c.kind == mir_operand_switch_case() && c.owner == ti + 1 { queue = try mir_vp4_push_point(d, store, function, queue, c.target, 0, 0, 0) }
oi = oi + 1 } } }
ti = ti + 1 } }
        }
        q = q + 1
    }
    return Ok(true)
}
fn mir_vp4_type_initialized(d: Domain, store: MirStore, function: U64, load_place: U64, type_id: U64, suffix: __s0_Buffer(U64), block: U64, position: U64) -> Result(Bool, __s0_Error) {
    let fields = mir_vcount_type_parts(store, type_id, mir_type_part_field())
    if mir_vtype_kind(store, type_id) != mir_type_kind_aggregate() || fields == 0 { return mir_vp4_leaf_initialized(d, store, function, load_place, suffix, block, position) }
    var ordinal: U64 = 0
    while ordinal < fields { var at: U64 = 0
var found: U64 = 0
while at < __s0_buffer_len(MirTypePartRec, store.type_parts) { let f = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
if f.owner == type_id && f.kind == mir_type_part_field() && f.ordinal == ordinal { found = at + 1 }
at = at + 1 }
let child = try __s0_buffer_append(U64, d, suffix, found)
if !(try mir_vp4_type_initialized(d, store, function, load_place, __s0_buffer_get(MirTypePartRec, store.type_parts, found - 1).part_type, child, block, position)) { return Ok(false) }
ordinal = ordinal + 1 }
    return Ok(true)
}
fn mir_vphase4_initialization(d: Domain, store: MirStore, function: U64, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let reach = try mir_vreachable(d, store, function)
    var block: U64 = 1
    while mir_vblock_index(store, function, block) != 0 { if mir_vseen_block(reach, block) { var position: U64 = 0
while position < mir_vp4_instruction_count(store, function, block) { let iid = mir_vp4_instruction_at(store, function, block, position)
let ins = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if ins.op == mir_op_load() { let place = __s0_buffer_get(MirPlaceRec, store.places, ins.place - 1)
if place.kind != mir_place_deref() { let ty = mir_vp4_place_type(store, function, ins.place)
let suffix = try __s0_buffer_new(U64, d)
if !(try mir_vp4_type_initialized(d, store, function, ins.place, ty, suffix, block, position)) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_dominance(), mir_vdiag_uninitialized_load(), function, block, iid, 0, ins.place, ty, 0, 0, 0, ins.place)) } } }
position = position + 1 } }
block = block + 1 }
    return Ok(out)
}

fn mir_vphase4(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let reach = try mir_vreachable(d, store, function)
        let uses = try mir_vp4_collect_uses(d, store, function)
        var at: U64 = 0
        while at < __s0_buffer_len(MirVP4Use, uses) {
            let u = __s0_buffer_get(MirVP4Use, uses, at)
            if mir_vseen_block(reach, u.block) {
                let vi = mir_vvalue_index(store, function, u.value)
                let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
                var use_pos = mir_vp4_instruction_count(store, function, u.block)
                if u.instruction != 0 { use_pos = __s0_buffer_get(MirInstrRec, store.instructions, u.instruction - 1).ordinal }
                var dominated = value.def_kind == mir_value_def_function_param()
                if value.def_kind == mir_value_def_switch_case() && value.block == u.block && value.item == u.switch_case { dominated = true }
                if !dominated { dominated = try mir_vphase4_point_dominates(d, store, function, value.def_kind, value.block, value.item, u.block, use_pos) }
                if !dominated { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_dominance(), mir_vdiag_not_dominated(), function, u.block, u.instruction, u.terminator, u.operand, value.value_type, vi, 0, 0, u.value)) }
            }
            at = at + 1
        }
        out = try mir_vphase4_initialization(d, store, function, out)
        function = function + 1
    }
    return Ok(out)
}
