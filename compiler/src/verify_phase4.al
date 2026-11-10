// Phase-4 uninitialized-place verification for the flat MIR store.  Points are
// encoded as (block, instruction boundary); checked failure edges are
// represented by their source boundary, so an instruction result is
// unavailable on its own failure edge.  Every table walk uses the
// per-function MirVIndexes built by the caller; init_function additionally
// builds a per-function predecessor CSR so reachability stays local.
type MirVP4Use {
    value: U64
    block: U64
    instruction: U64
    terminator: U64
    operand: U64
    switch_case: U64
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
    if i.op == mir_op_store() || i.op == mir_op_domain_create() || i.op == mir_op_domain_mark() || i.op == mir_op_domain_destroy() || i.op == mir_op_cleanup_push() || i.op == mir_op_cleanup_disarm() || i.op == mir_op_cleanup_scope_run() || i.op == mir_op_cleanup_scope_end() || i.op == mir_op_slice_len() || i.op == mir_op_enum_payload_checked() || i.op == mir_op_enum_construct() || i.op == mir_op_table_create() || i.op == mir_op_table_view_end() || (i.op >= mir_op_int_trunc() && i.op <= mir_op_float_from_int()) || i.op == mir_op_int_convert_checked() || i.op == mir_op_int_convert_wrap() || (i.op >= mir_op_vec_len() && i.op <= mir_op_vec_as_mut_slice()) || i.op == mir_op_array_as_slice() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0) }
    if i.op == mir_op_domain_reset() || i.op == mir_op_alloc() || i.op == mir_op_alloc_checked() || i.op == mir_op_copy_to_domain() || (i.op >= mir_op_int_add_checked() && i.op <= mir_op_int_shr_checked()) || (i.op >= mir_op_int_add_try() && i.op <= mir_op_int_mul_wrapping()) || i.op == mir_op_slice_index_checked() || i.op == mir_op_array_index_checked() || (i.op >= mir_op_table_insert() && i.op <= mir_op_table_remove()) || i.op == mir_op_table_insert_try() || (i.op >= mir_op_int_eq() && i.op <= mir_op_float_ge()) { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0) }
    if i.op == mir_op_slice_range_checked() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.c, i.block, id, 0, 0, 0) }
    if i.op == mir_op_vec_construct_checked() || i.op == mir_op_vec_grow_checked() || i.op == mir_op_str_concat() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.c, i.block, id, 0, 0, 0) }
    if i.op == mir_op_str_len() || i.op == mir_op_str_to_bytes() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0) }
    if i.op == mir_op_str_byte_checked() || i.op == mir_op_str_from_bytes() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0) }
    if i.op == mir_op_str_slice_checked() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.c, i.block, id, 0, 0, 0) }
    return Ok(uses)
}
// Uses are emitted in the same order as the legacy full-table scans: per
// block, instruction ordinals ascending, each instruction's place uses, the
// load/store deref use, direct uses, then the operand passes grouped by kind
// (instruction, aggregate_field, checked_edge_arg) over the instruction's own
// operand list, then the block's single terminator with its argument uses and
// inline switch-case argument uses.
fn mir_vp4_collect_uses_into(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, initial: __s0_Buffer(MirVP4Use)) -> Result(__s0_Buffer(MirVP4Use), __s0_Error) {
    var uses = initial
    var block: U64 = 1
    while block <= mir_vindex_block_count(indexes, function) {
        let icount = mir_vindex_instr_count(indexes, function, block)
        var ordinal: U64 = 0
        while ordinal < icount {
            let id = mir_vindex_instr(indexes, function, block, ordinal)
            if id != 0 {
                let i = __s0_buffer_get(MirInstrRec, store.instructions, id - 1)
                uses = try mir_vp4_place_uses(d, store, uses, block, id, i.place)
                if (i.op == mir_op_load() || i.op == mir_op_store() || i.op == mir_op_borrow() || i.op == mir_op_borrow_mut()) && __s0_buffer_get(MirPlaceRec, store.places, i.place - 1).kind == mir_place_deref() { uses = try mir_vp4_use(d, uses, __s0_buffer_get(MirPlaceRec, store.places, i.place - 1).deref_value, block, id, 0, 0, 0) }
                uses = try mir_vp4_direct_uses(d, uses, i, id)
                var pass: U64 = 0
                while pass < 3 {
                    var kind = mir_operand_instruction()
                    if pass == 1 { kind = mir_operand_aggregate_field() }
                    if pass == 2 { kind = mir_operand_checked_edge_arg() }
                    var belongs = i.op == mir_op_cleanup_push() || i.op == mir_op_call() || i.op == mir_op_ffi_call_unsafe() || i.op == mir_op_str_slice_checked()
                    if pass == 1 { belongs = i.op == mir_op_aggregate_construct() }
                    if pass == 2 { belongs = mir_vop_checked(i.op) }
                    if belongs {
                        let ocount = mir_vindex_op_instr_count(indexes, id)
                        var oi: U64 = 0
                        while oi < ocount {
                            let oid = mir_vindex_op_instr(indexes, id, oi)
                            let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
                            if o.kind == kind { uses = try mir_vp4_use(d, uses, o.value, block, id, 0, oid, 0) }
                            oi = oi + 1
                        }
                    }
                    pass = pass + 1
                }
            }
            ordinal = ordinal + 1
        }
        let term_id = mir_vindex_term(indexes, function, block)
        if term_id != 0 {
            let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            uses = try mir_vp4_use(d, uses, t.value, block, 0, term_id, 0, 0)
            let ocount = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < ocount {
                let oid = mir_vindex_op_term(indexes, term_id, oi)
                let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
                if o.kind == mir_operand_terminator_arg() { uses = try mir_vp4_use(d, uses, o.value, block, 0, term_id, oid, 0) }
                if o.kind == mir_operand_switch_case() {
                    let ccount = mir_vindex_op_case_count(indexes, oid)
                    var ai: U64 = 0
                    while ai < ccount {
                        let aid = mir_vindex_op_case(indexes, oid, ai)
                        let a = __s0_buffer_get(MirOperandRec, store.operands, aid - 1)
                        uses = try mir_vp4_use(d, uses, a.value, block, 0, term_id, aid, o.ordinal + 1)
                        ai = ai + 1
                    }
                }
                oi = oi + 1
            }
        }
        block = block + 1
    }
    return Ok(uses)
}

fn mir_vp4_collect_uses(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(__s0_Buffer(MirVP4Use), __s0_Error) {
    let initial = try __s0_buffer_new(MirVP4Use, d)
    return mir_vp4_collect_uses_into(d, store, indexes, function, initial)
}

type MirVP4UseInventory {
    function_start: __s0_Buffer(U64)
    function_count: __s0_Buffer(U64)
    instruction_start: __s0_Buffer(U64)
    instruction_count: __s0_Buffer(U64)
    value_start: __s0_Buffer(U64)
    value_count: __s0_Buffer(U64)
    value_use_ids: __s0_Buffer(U64)
    uses: __s0_Buffer(MirVP4Use)
}

fn mir_vp4_use_inventory_build(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirVP4UseInventory, __s0_Error) {
    var function_start = try __s0_buffer_new(U64, d)
    var function_count = try __s0_buffer_new(U64, d)
    var uses = try __s0_buffer_new(MirVP4Use, d)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let start = __s0_buffer_len(MirVP4Use, uses)
        function_start = try __s0_buffer_append(U64, d, function_start, start)
        uses = try mir_vp4_collect_uses_into(d, store, indexes, function, uses)
        function_count = try __s0_buffer_append(U64, d, function_count, __s0_buffer_len(MirVP4Use, uses) - start)
        function = function + 1
    }
    let instruction_total = __s0_buffer_len(MirInstrRec, store.instructions)
    var instruction_first = __s0_alloc(U64, d, instruction_total + 1)
    var instruction_uses = __s0_alloc(U64, d, instruction_total + 1)
    var at: U64 = 0
    while at <= instruction_total { instruction_first[at] = 0
        instruction_uses[at] = 0
        at = at + 1 }
    at = 0
    while at < __s0_buffer_len(MirVP4Use, uses) {
        let use = __s0_buffer_get(MirVP4Use, uses, at)
        if use.instruction != 0 && use.instruction <= instruction_total {
            if instruction_uses[use.instruction] == 0 { instruction_first[use.instruction] = at }
            instruction_uses[use.instruction] = instruction_uses[use.instruction] + 1
        }
        at = at + 1
    }
    var instruction_start = try __s0_buffer_new(U64, d)
    var instruction_count = try __s0_buffer_new(U64, d)
    at = 1
    while at <= instruction_total {
        instruction_start = try __s0_buffer_append(U64, d, instruction_start, instruction_first[at])
        instruction_count = try __s0_buffer_append(U64, d, instruction_count, instruction_uses[at])
        at = at + 1
    }
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    var counts = __s0_alloc(U64, d, value_total + 1)
    var starts = __s0_alloc(U64, d, value_total + 1)
    var seen = __s0_alloc(U64, d, value_total + 1)
    at = 0
    while at <= value_total { counts[at] = 0
        starts[at] = 0
        seen[at] = 0
        at = at + 1 }
    function = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let start = __s0_buffer_get(U64, function_start, function - 1)
        let count = __s0_buffer_get(U64, function_count, function - 1)
        at = 0
        while at < count {
            let use = __s0_buffer_get(MirVP4Use, uses, start + at)
            let value = mir_vindex_value(indexes, function, use.value)
            if value != 0 { counts[value] = counts[value] + 1 }
            at = at + 1
        }
        function = function + 1
    }
    var total: U64 = 0
    at = 1
    while at <= value_total { starts[at] = total
        total = total + counts[at]
        at = at + 1 }
    var ids = __s0_alloc(U64, d, total + 1)
    at = 0
    while at < total { ids[at] = 0
        at = at + 1 }
    function = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let start = __s0_buffer_get(U64, function_start, function - 1)
        let count = __s0_buffer_get(U64, function_count, function - 1)
        at = 0
        while at < count {
            let use_id = start + at
            let use = __s0_buffer_get(MirVP4Use, uses, use_id)
            let value = mir_vindex_value(indexes, function, use.value)
            if value != 0 { ids[starts[value] + seen[value]] = use_id + 1
                seen[value] = seen[value] + 1 }
            at = at + 1
        }
        function = function + 1
    }
    var value_start = try __s0_buffer_new(U64, d)
    var value_count = try __s0_buffer_new(U64, d)
    at = 1
    while at <= value_total { value_start = try __s0_buffer_append(U64, d, value_start, starts[at])
        value_count = try __s0_buffer_append(U64, d, value_count, counts[at])
        at = at + 1 }
    var value_use_ids = try __s0_buffer_new(U64, d)
    at = 0
    while at < total { value_use_ids = try __s0_buffer_append(U64, d, value_use_ids, ids[at])
        at = at + 1 }
    return Ok(MirVP4UseInventory(function_start: function_start, function_count: function_count, instruction_start: instruction_start, instruction_count: instruction_count, value_start: value_start, value_count: value_count, value_use_ids: value_use_ids, uses: uses))
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
fn mir_vp4_place_type(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> U64 { let p = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
if p.kind == mir_place_local() { return __s0_buffer_get(MirLocalRec, store.locals, mir_vindex_local(indexes, function, p.local) - 1).local_type }
let base = mir_vp4_place_type(store, indexes, function, p.base)
let pcount = mir_vindex_type_part_count(indexes, base)
var at: U64 = 0
while at < pcount { let pid = mir_vindex_type_part(indexes, base, at)
let f = __s0_buffer_get(MirTypePartRec, store.type_parts, pid - 1)
if f.kind == mir_type_part_field() && mir_vname_equal(store, p.field_start, p.field_end, f.name_start, f.name_end) { return f.part_type }
at = at + 1 }
return 0 }
// suffix contains canonical type-part IDs for fields below the loaded place.
fn mir_vp4_store_covers(store: MirStore, indexes: MirVIndexes, store_place: U64, load_place: U64, load_root: U64, load_depth: U64, suffix: __s0_Buffer(U64)) -> Bool {
    if store_place != 0 && store_place == load_place { return true }
    if __s0_buffer_get(U64, indexes.place_root, store_place - 1) != load_root { return false }
    let sd = __s0_buffer_get(U64, indexes.place_depth, store_place - 1)
    let ld = load_depth
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

// Worklist entries for the per-load aggregate walk.  suffix buffers cannot be
// stored in buffer elements (references are rejected), so each entry links to
// the parent entry that selected it; part is the MirTypePartRec id appended by
// that selection step (0 for the root entry).  The leaf suffix is rebuilt by
// walking the chain.
type MirVP4InitWork {
    type_id: U64
    parent: U64
    part: U64
}
// Boolean must analysis for definite initialization: retain only paths on
// which the leaf is still uninitialized.  A covering store kills its success
// transition, while its checked failure transition remains at the pre-store
// boundary.  seen and the bounded point queue are per-function scratch arrays
// (node id = boundary_offset of the point's block plus its position); each leaf
// BFS uses a fresh stamp, so no immutable queue allocations survive a leaf.
fn mir_vp4_init_function(d: Domain, seen: __s0_Buffer(U64), queue: __s0_Buffer(U64), instruction_at: __s0_Buffer(U64), pred_start: __s0_Buffer(U64), pred_node: __s0_Buffer(U64), store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, function: U64, reach: __s0_Buffer(U64), initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let node_count = cfg.node_count
    let queue_base = node_count + 1
    // The caller owns these five buffers, sizes them from the point cfg, and
    // has already zeroed the slots this function uses, built instruction_at,
    // and prefixed pred_start to the start offsets of each node's
    // predecessor list in pred_node. This function only fills the
    // predecessor lists, restores the starts, and walks ancestors.
    var fill_block: U64 = 1
    while fill_block <= cfg.block_count {
        let fill_count = __s0_buffer_get(U64, cfg.block_instr_count, fill_block - 1)
        let fill_base = __s0_buffer_get(U64, cfg.boundary_offset, fill_block - 1)
        var fill_pos: U64 = 0
        while fill_pos < fill_count {
            let fill_iid = __s0_buffer_get(U64, instruction_at, fill_base + fill_pos)
            if fill_iid != 0 {
                let fill_ins = __s0_buffer_get(MirInstrRec, store.instructions, fill_iid - 1)
                let fill_source = fill_block * queue_base + fill_pos
                let slot = __s0_buffer_get(U64, pred_start, fill_base + fill_pos + 1)
                __s0_buffer_set(U64, pred_node, slot, fill_source)
                __s0_buffer_set(U64, pred_start, fill_base + fill_pos + 1, slot + 1)
                if mir_vop_checked(fill_ins.op) && fill_ins.target >= 1 && fill_ins.target <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, fill_ins.target - 1)
                    let tslot = __s0_buffer_get(U64, pred_start, node)
                    __s0_buffer_set(U64, pred_node, tslot, fill_source)
                    __s0_buffer_set(U64, pred_start, node, tslot + 1) }
            }
            fill_pos = fill_pos + 1
        }
        let fill_term = mir_vindex_term(indexes, function, fill_block)
        if fill_term != 0 {
            let t = __s0_buffer_get(MirTermRec, store.terminators, fill_term - 1)
            let fill_source = fill_block * queue_base + fill_count
            if t.kind == mir_term_jump() && t.target >= 1 && t.target <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, t.target - 1)
                let tslot = __s0_buffer_get(U64, pred_start, node)
                __s0_buffer_set(U64, pred_node, tslot, fill_source)
                __s0_buffer_set(U64, pred_start, node, tslot + 1) }
            if t.kind == mir_term_branch() {
                if t.then_block >= 1 && t.then_block <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, t.then_block - 1)
                    let tslot = __s0_buffer_get(U64, pred_start, node)
                    __s0_buffer_set(U64, pred_node, tslot, fill_source)
                    __s0_buffer_set(U64, pred_start, node, tslot + 1) }
                if t.else_block >= 1 && t.else_block <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, t.else_block - 1)
                    let tslot = __s0_buffer_get(U64, pred_start, node)
                    __s0_buffer_set(U64, pred_node, tslot, fill_source)
                    __s0_buffer_set(U64, pred_start, node, tslot + 1) }
            }
            if t.kind == mir_term_switch() { let case_count = mir_vindex_op_term_count(indexes, fill_term)
                var case_at: U64 = 0
                while case_at < case_count { let case_id = mir_vindex_op_term(indexes, fill_term, case_at)
                    let c = __s0_buffer_get(MirOperandRec, store.operands, case_id - 1)
                    if c.kind == mir_operand_switch_case() && c.target >= 1 && c.target <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, c.target - 1)
                        let tslot = __s0_buffer_get(U64, pred_start, node)
                        __s0_buffer_set(U64, pred_node, tslot, fill_source)
                        __s0_buffer_set(U64, pred_start, node, tslot + 1) }
                    case_at = case_at + 1
                } }
        }
        fill_block = fill_block + 1
    }
    var unfill: U64 = node_count + 1
    while unfill >= 1 { __s0_buffer_set(U64, pred_start, unfill, __s0_buffer_get(U64, pred_start, unfill - 1))
        unfill = unfill - 1 }
    __s0_buffer_set(U64, pred_start, 0, 0)
    var stamp: U64 = 0
    var block: U64 = 1
    while block <= cfg.block_count {
        if mir_vseen_block(reach, block) {
            let icount = __s0_buffer_get(U64, cfg.block_instr_count, block - 1)
            let block_base = __s0_buffer_get(U64, cfg.boundary_offset, block - 1)
            var position: U64 = 0
            while position < icount {
                let iid = __s0_buffer_get(U64, instruction_at, block_base + position)
                if iid != 0 {
                    let ins = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                    if ins.op == mir_op_load() || ins.op == mir_op_borrow() || ins.op == mir_op_borrow_mut() {
                        let load_root = __s0_buffer_get(U64, indexes.place_root, ins.place - 1)
                        let load_depth = __s0_buffer_get(U64, indexes.place_depth, ins.place - 1)
                        if load_root != 0 {
                            let ty = mir_vp4_place_type(store, indexes, function, ins.place)
                            var work = try __s0_buffer_new(MirVP4InitWork, d)
                            work = try __s0_buffer_append(MirVP4InitWork, d, work, MirVP4InitWork(type_id: ty, parent: 0, part: 0))
                            var q: U64 = 0
                            var failing = false
                            while q < __s0_buffer_len(MirVP4InitWork, work) && !failing {
                                let entry = __s0_buffer_get(MirVP4InitWork, work, q)
                                let fields = mir_vindex_type_field_count(indexes, entry.type_id)
                                if mir_vtype_kind(store, entry.type_id) != mir_type_kind_aggregate() || fields == 0 {
                                    // Rebuild this leaf's suffix root-first from the parent chain.
                                    var chain = try __s0_buffer_new(U64, d)
                                    var cur = q
                                    while cur != 0 { let e = __s0_buffer_get(MirVP4InitWork, work, cur)
                                        chain = try __s0_buffer_append(U64, d, chain, e.part)
                                        cur = e.parent }
                                    var suffix = try __s0_buffer_new(U64, d)
                                    var k = __s0_buffer_len(U64, chain)
                                    while k > 0 { suffix = try __s0_buffer_append(U64, d, suffix, __s0_buffer_get(U64, chain, k - 1))
                                        k = k - 1 }
                                    // A covering store earlier in this block
                                    // necessarily dominates the load because
                                    // MIR edges enter only at block boundaries.
                                    var initialized_here = false
                                    var prior_position = position
                                    while prior_position > 0 && !initialized_here { prior_position = prior_position - 1
                                        let prior_id = __s0_buffer_get(U64, instruction_at, block_base + prior_position)
                                        let prior = __s0_buffer_get(MirInstrRec, store.instructions, prior_id - 1)
                                        if prior.op == mir_op_store() && mir_vp4_store_covers(store, indexes, prior.place, ins.place, load_root, load_depth, suffix) { initialized_here = true }
                                    }
                                    if !initialized_here {
                                        // Stamped backward reachability for
                                        // this leaf: expand predecessors of the
                                        // load point over the per-function CSR
                                        // until the function entry appears,
                                        // skipping predecessors whose
                                        // instruction covers this leaf. A
                                        // covering transition cut in the forward
                                        // direction leaves its own continuation
                                        // unreachable, so reversing the
                                        // avoiding-cover walk visits exactly the
                                        // forward-reachable transitions and the
                                        // verdict is unchanged, while only
                                        // ancestors of the load point are
                                        // visited instead of the whole function.
                                        stamp = stamp + 1
                                        var queue_count: U64 = 1
                                        __s0_buffer_set(U64, queue, 0, block * queue_base + position)
                                        __s0_buffer_set(U64, seen, block_base + position, stamp)
                                        let entry_node = __s0_buffer_get(U64, cfg.boundary_offset, 0)
                                        var qq: U64 = 0
                                        var reached = false
                                        while qq < queue_count && !reached {
                                        let encoded = __s0_buffer_get(U64, queue, qq)
                                        let point_block = encoded / queue_base
                                        let point_position = encoded % queue_base
                                        let point_node = __s0_buffer_get(U64, cfg.boundary_offset, point_block - 1) + point_position
                                        if point_node == entry_node { reached = true } else {
                                            var pred_at = __s0_buffer_get(U64, pred_start, point_node)
                                            while pred_at < __s0_buffer_get(U64, pred_start, point_node + 1) && !reached {
                                                let pred = __s0_buffer_get(U64, pred_node, pred_at)
                                                let pred_block = pred / queue_base
                                                let pred_position = pred % queue_base
                                                let pred_node_id = __s0_buffer_get(U64, cfg.boundary_offset, pred_block - 1) + pred_position
                                                if __s0_buffer_get(U64, seen, pred_node_id) != stamp {
                                                    var blocked = false
                                                    if pred_position < __s0_buffer_get(U64, cfg.block_instr_count, pred_block - 1) {
                                                        let pred_iid = __s0_buffer_get(U64, instruction_at, pred_node_id)
                                                        if pred_iid != 0 {
                                                            let step = __s0_buffer_get(MirInstrRec, store.instructions, pred_iid - 1)
                                                            if step.op == mir_op_store() && mir_vp4_store_covers(store, indexes, step.place, ins.place, load_root, load_depth, suffix) { blocked = true }
                                                        }
                                                    }
                                                    if !blocked { __s0_buffer_set(U64, seen, pred_node_id, stamp)
                                                        __s0_buffer_set(U64, queue, queue_count, pred)
                                                        queue_count = queue_count + 1 }
                                                }
                                                pred_at = pred_at + 1
                                            }
                                        }
                                        qq = qq + 1
                                    }
                                        if reached { failing = true }
                                    }
                                } else {
                                    var ordinal: U64 = 0
                                    while ordinal < fields {
                                        var found: U64 = 0
                                        let pcount = mir_vindex_type_part_count(indexes, entry.type_id)
                                        var at: U64 = 0
                                        while at < pcount { let pid = mir_vindex_type_part(indexes, entry.type_id, at)
let f = __s0_buffer_get(MirTypePartRec, store.type_parts, pid - 1)
if f.kind == mir_type_part_field() && f.ordinal == ordinal { found = pid }
at = at + 1 }
                                        work = try __s0_buffer_append(MirVP4InitWork, d, work, MirVP4InitWork(type_id: __s0_buffer_get(MirTypePartRec, store.type_parts, found - 1).part_type, parent: q, part: found))
                                        ordinal = ordinal + 1
                                    }
                                }
                                q = q + 1
                            }
                            if failing { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_dominance(), mir_vdiag_uninitialized_load(), function, block, iid, 0, ins.place, ty, 0, 0, 0, ins.place)) }
                        }
                    }
                }
                position = position + 1
            }
        }
        block = block + 1
    }
    return Ok(out)
}

fn mir_vphase4_with_uses(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    // Plan-carried per-function verifier scratch for the init analysis: five
    // U64 buffers grown once to the largest function's needs and then
    // rewritten in place every function, so the tables stop accumulating in
    // the root domain. Sizes come from the point cfg; the predecessor edge
    // total comes from the same counting walk the fill relies on. Diagnostics
    // stay in the caller's domain and outlive the reuse.
    var v_seen = try __s0_buffer_new(U64, d)
    var v_queue = try __s0_buffer_new(U64, d)
    var v_instr = try __s0_buffer_new(U64, d)
    var v_pstart = try __s0_buffer_new(U64, d)
    var v_pnode = try __s0_buffer_new(U64, d)
    // The point cfg and dominator plans carry the same idea further: both
    // analyses rebuild roughly twenty arrays per function from the
    // never-reset root domain. The plans own every buffer the builders
    // touch; the builders grow them lazily, rewrite them in place per
    // function, and return the grown handles with each result for the next
    // function.
    var p_boundary = try __s0_buffer_new(U64, d)
    var p_bicount = try __s0_buffer_new(U64, d)
    var p_succ = try __s0_buffer_new(U64, d)
    var p_succ_start = try __s0_buffer_new(U64, d)
    var p_succ_count = try __s0_buffer_new(U64, d)
    var p_pred = try __s0_buffer_new(U64, d)
    var p_pred_start = try __s0_buffer_new(U64, d)
    var p_pred_count = try __s0_buffer_new(U64, d)
    var p_case_edge = try __s0_buffer_new(U64, d)
    var p_edge_from = try __s0_buffer_new(U64, d)
    var p_edge_to = try __s0_buffer_new(U64, d)
    var p_ecnt = try __s0_buffer_new(U64, d)
    var p_ebase = try __s0_buffer_new(U64, d)
    var p_eids = try __s0_buffer_new(U64, d)
    var p_eused = try __s0_buffer_new(U64, d)
    var cfg_plan = MirVP4CfgPlan(boundary_offset: p_boundary, block_instr_count: p_bicount, succ: p_succ, succ_start: p_succ_start, succ_count: p_succ_count, pred: p_pred, pred_start: p_pred_start, pred_count: p_pred_count, case_edge: p_case_edge, edge_from: p_edge_from, edge_to: p_edge_to, scratch_edge_cnt: p_ecnt, scratch_edge_base: p_ebase, scratch_edge_ids: p_eids, scratch_edge_used: p_eused)
    var q_idom = try __s0_buffer_new(U64, d)
    var q_rpo_index = try __s0_buffer_new(U64, d)
    var q_dom_in = try __s0_buffer_new(U64, d)
    var q_dom_out = try __s0_buffer_new(U64, d)
    var q_seen = try __s0_buffer_new(U64, d)
    var q_phase = try __s0_buffer_new(U64, d)
    var q_stack = try __s0_buffer_new(U64, d)
    var q_post = try __s0_buffer_new(U64, d)
    var q_rpo = try __s0_buffer_new(U64, d)
    var q_child_count = try __s0_buffer_new(U64, d)
    var q_counts = try __s0_buffer_new(U64, d)
    var q_child_start = try __s0_buffer_new(U64, d)
    var q_filled = try __s0_buffer_new(U64, d)
    var q_children = try __s0_buffer_new(U64, d)
    var q_estack = try __s0_buffer_new(U64, d)
    var q_edata = try __s0_buffer_new(U64, d)
    var dom_plan = MirVP4DomPlan(idom: q_idom, rpo_index: q_rpo_index, dom_in: q_dom_in, dom_out: q_dom_out, scratch_seen: q_seen, scratch_phase: q_phase, scratch_stack: q_stack, scratch_post: q_post, scratch_rpo: q_rpo, scratch_child_count: q_child_count, scratch_counts: q_counts, scratch_child_start: q_child_start, scratch_filled: q_filled, scratch_children: q_children, scratch_estack: q_estack, scratch_edata: q_edata)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let reach = try mir_vreachable(d, store, indexes, function)
        let cfg_built = try mir_vp4_cfg_build(cfg_plan, d, store, indexes, function)
        cfg_plan = cfg_built.plan
        let cfg = cfg_built.cfg
        let dom_built = try mir_vp4_dom_build(dom_plan, d, cfg)
        dom_plan = dom_built.plan
        let dom = dom_built.dom
        let node_count = cfg.node_count
        var grow = __s0_buffer_len(U64, v_seen)
        while grow < node_count + 1 { v_seen = try __s0_buffer_append(U64, d, v_seen, 0)
            grow = grow + 1 }
        grow = __s0_buffer_len(U64, v_queue)
        while grow < node_count + 1 { v_queue = try __s0_buffer_append(U64, d, v_queue, 0)
            grow = grow + 1 }
        grow = __s0_buffer_len(U64, v_instr)
        while grow < node_count + 1 { v_instr = try __s0_buffer_append(U64, d, v_instr, 0)
            grow = grow + 1 }
        grow = __s0_buffer_len(U64, v_pstart)
        while grow < node_count + 2 { v_pstart = try __s0_buffer_append(U64, d, v_pstart, 0)
            grow = grow + 1 }
        var z: U64 = 0
        while z <= node_count { __s0_buffer_set(U64, v_seen, z, 0)
            __s0_buffer_set(U64, v_instr, z, 0)
            z = z + 1 }
        var z2: U64 = 0
        while z2 <= node_count + 1 { __s0_buffer_set(U64, v_pstart, z2, 0)
            z2 = z2 + 1 }
        var indexed_block: U64 = 1
        while indexed_block <= cfg.block_count {
            let indexed_count = __s0_buffer_get(U64, cfg.block_instr_count, indexed_block - 1)
            let indexed_base = __s0_buffer_get(U64, cfg.boundary_offset, indexed_block - 1)
            var indexed_position: U64 = 0
            while indexed_position < indexed_count {
                __s0_buffer_set(U64, v_instr, indexed_base + indexed_position, mir_vindex_instr(indexes, function, indexed_block, indexed_position))
                indexed_position = indexed_position + 1
            }
            indexed_block = indexed_block + 1
        }
        // Count predecessor edges per point node, then prefix the buckets
        // into start offsets. The enumeration (block then position order,
        // fall-through, checked failure edge, terminator successors) is the
        // same one the fill pass replays, so the fill is deterministic.
        var count_block: U64 = 1
        while count_block <= cfg.block_count {
            let count_instr = __s0_buffer_get(U64, cfg.block_instr_count, count_block - 1)
            let count_base = __s0_buffer_get(U64, cfg.boundary_offset, count_block - 1)
            var count_pos: U64 = 0
            while count_pos < count_instr {
                let count_iid = __s0_buffer_get(U64, v_instr, count_base + count_pos)
                if count_iid != 0 {
                    let count_ins = __s0_buffer_get(MirInstrRec, store.instructions, count_iid - 1)
                    __s0_buffer_set(U64, v_pstart, count_base + count_pos + 1, __s0_buffer_get(U64, v_pstart, count_base + count_pos + 1) + 1)
                    if mir_vop_checked(count_ins.op) && count_ins.target >= 1 && count_ins.target <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, count_ins.target - 1)
                        __s0_buffer_set(U64, v_pstart, node, __s0_buffer_get(U64, v_pstart, node) + 1) }
                }
                count_pos = count_pos + 1
            }
            let count_term = mir_vindex_term(indexes, function, count_block)
            if count_term != 0 {
                let t = __s0_buffer_get(MirTermRec, store.terminators, count_term - 1)
                if t.kind == mir_term_jump() && t.target >= 1 && t.target <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, t.target - 1)
                    __s0_buffer_set(U64, v_pstart, node, __s0_buffer_get(U64, v_pstart, node) + 1) }
                if t.kind == mir_term_branch() {
                    if t.then_block >= 1 && t.then_block <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, t.then_block - 1)
                        __s0_buffer_set(U64, v_pstart, node, __s0_buffer_get(U64, v_pstart, node) + 1) }
                    if t.else_block >= 1 && t.else_block <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, t.else_block - 1)
                        __s0_buffer_set(U64, v_pstart, node, __s0_buffer_get(U64, v_pstart, node) + 1) }
                }
                if t.kind == mir_term_switch() { let case_count = mir_vindex_op_term_count(indexes, count_term)
                    var case_at: U64 = 0
                    while case_at < case_count { let case_id = mir_vindex_op_term(indexes, count_term, case_at)
                        let c = __s0_buffer_get(MirOperandRec, store.operands, case_id - 1)
                        if c.kind == mir_operand_switch_case() && c.target >= 1 && c.target <= cfg.block_count { let node = __s0_buffer_get(U64, cfg.boundary_offset, c.target - 1)
                            __s0_buffer_set(U64, v_pstart, node, __s0_buffer_get(U64, v_pstart, node) + 1) }
                        case_at = case_at + 1
                    } }
            }
            count_block = count_block + 1
        }
        var running: U64 = 0
        var prefix_at: U64 = 0
        while prefix_at <= node_count + 1 { let bucket = __s0_buffer_get(U64, v_pstart, prefix_at)
            __s0_buffer_set(U64, v_pstart, prefix_at, running)
            running = running + bucket
            prefix_at = prefix_at + 1 }
        grow = __s0_buffer_len(U64, v_pnode)
        while grow < running + 1 { v_pnode = try __s0_buffer_append(U64, d, v_pnode, 0)
            grow = grow + 1 }
        let use_start = __s0_buffer_get(U64, inventory.function_start, function - 1)
        let use_count = __s0_buffer_get(U64, inventory.function_count, function - 1)
        var at: U64 = 0
        while at < use_count {
            let u = __s0_buffer_get(MirVP4Use, inventory.uses, use_start + at)
            if mir_vseen_block(reach, u.block) {
                let vi = mir_vindex_value(indexes, function, u.value)
                if vi != 0 {
                    let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
                    var use_pos = mir_vindex_instr_count(indexes, function, u.block)
                    if u.instruction != 0 { use_pos = __s0_buffer_get(MirInstrRec, store.instructions, u.instruction - 1).ordinal }
                    var dominated = value.def_kind == mir_value_def_function_param()
                    if value.def_kind == mir_value_def_switch_case() && value.block == u.block && value.item == u.switch_case { dominated = true }
                    if !dominated { dominated = mir_vp4_avail_dominates(cfg, dom, value.def_kind, value.block, value.item, u.block, use_pos) }
                    if !dominated { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_dominance(), mir_vdiag_not_dominated(), function, u.block, u.instruction, u.terminator, u.operand, value.value_type, vi, 0, 0, u.value)) }
                }
            }
            at = at + 1
        }
        out = try mir_vp4_init_function(d, v_seen, v_queue, v_instr, v_pstart, v_pnode, store, indexes, cfg, function, reach, out)
        function = function + 1
    }
    return Ok(out)
}

fn mir_vphase4(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    let inventory = try mir_vp4_use_inventory_build(d, store, indexes)
    return mir_vphase4_with_uses(d, store, indexes, inventory, initial)
}
