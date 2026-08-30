// Point-level phase-4 verification for the flat MIR store.  Points are encoded
// as (block, instruction boundary); checked failure edges are represented by
// their source boundary, so an instruction result is unavailable on its own
// failure edge.  All table walks use the per-function MirVIndexes built by the
// caller; only mir_vphase4_point_dominates (called from phase 6 with the
// store-only signature) retains full-table scans.
type MirVP4Use {
    value: U64
    block: U64
    instruction: U64
    terminator: U64
    operand: U64
    switch_case: U64
}

// Full-table scans retained for mir_vphase4_point_dominates only, which
// receives no indexes from its phase-6 caller.
fn mir_vp4_scan_instr_count(store: MirStore, function: U64, block: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < (store.instructions).len() {
        let i = (store.instructions)[at]
        if i.function == function && i.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}
fn mir_vp4_scan_instr(store: MirStore, function: U64, block: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < (store.instructions).len() {
        let i = (store.instructions)[at]
        if i.function == function && i.block == block && i.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_vp4_use(d: Domain, uses: Vec(MirVP4Use), value: U64, block: U64, instruction: U64, terminator: U64, operand: U64, switch_case: U64) -> Result(Vec(MirVP4Use), __s0_Error) {
    if value == 0 { return Ok(uses) }
    return Ok(try vec_appended(MirVP4Use, uses, MirVP4Use(value: value, block: block, instruction: instruction, terminator: terminator, operand: operand, switch_case: switch_case)))
}
fn mir_vp4_place_uses(d: Domain, store: MirStore, uses0: Vec(MirVP4Use), block: U64, instruction: U64, place: U64) -> Result(Vec(MirVP4Use), __s0_Error) {
    var uses = uses0
    var current = place
    var steps: U64 = 0
    while current != 0 && steps <= (store.places).len() {
        let p = (store.places)[current - 1]
        if p.kind == mir_place_deref() { return mir_vp4_use(d, uses, p.deref_value, block, instruction, 0, 0, 0) }
        if p.kind != mir_place_field() { return Ok(uses) }
        current = p.base
        steps = steps + 1
    }
    return Ok(uses)
}
fn mir_vp4_direct_uses(d: Domain, uses0: Vec(MirVP4Use), i: MirInstrRec, id: U64) -> Result(Vec(MirVP4Use), __s0_Error) {
    var uses = uses0
    if i.op == mir_op_store() || i.op == mir_op_domain_create() || i.op == mir_op_domain_mark() || i.op == mir_op_domain_destroy() || i.op == mir_op_cleanup_push() || i.op == mir_op_cleanup_disarm() || i.op == mir_op_cleanup_scope_run() || i.op == mir_op_cleanup_scope_end() || i.op == mir_op_slice_len() || i.op == mir_op_enum_payload_checked() || i.op == mir_op_enum_construct() || i.op == mir_op_table_create() || i.op == mir_op_table_view_end() || (i.op >= mir_op_int_trunc() && i.op <= mir_op_float_from_int()) || (i.op >= mir_op_vec_len() && i.op <= mir_op_vec_as_mut_slice()) || i.op == mir_op_array_as_slice() || i.op == mir_op_bytes_as_slice() || i.op == mir_op_string_as_bytes() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0) }
    if i.op == mir_op_domain_reset() || i.op == mir_op_alloc() || i.op == mir_op_alloc_checked() || i.op == mir_op_copy_to_domain() || i.op == mir_op_copy_to_domain_try() || i.op == mir_op_bytes_try_from_vec() || (i.op >= mir_op_int_add_checked() && i.op <= mir_op_int_shr_checked()) || i.op == mir_op_slice_index_checked() || i.op == mir_op_array_index_checked() || (i.op >= mir_op_table_insert() && i.op <= mir_op_table_remove()) || (i.op >= mir_op_int_eq() && i.op <= mir_op_float_ge()) { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0) }
    if i.op == mir_op_slice_range_checked() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.b, i.block, id, 0, 0, 0)
uses = try mir_vp4_use(d, uses, i.c, i.block, id, 0, 0, 0) }
    if i.op == mir_op_vec_construct_checked() || i.op == mir_op_vec_grow_checked() || i.op == mir_op_vec_try_grow() { uses = try mir_vp4_use(d, uses, i.a, i.block, id, 0, 0, 0)
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
fn mir_vp4_collect_uses_into(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, initial: Vec(MirVP4Use)) -> Result(Vec(MirVP4Use), __s0_Error) {
    var uses = initial
    var block: U64 = 1
    while block <= mir_vindex_block_count(indexes, function) {
        let icount = mir_vindex_instr_count(indexes, function, block)
        var ordinal: U64 = 0
        while ordinal < icount {
            let id = mir_vindex_instr(indexes, function, block, ordinal)
            if id != 0 {
                let i = (store.instructions)[id - 1]
                uses = try mir_vp4_place_uses(d, store, uses, block, id, i.place)
                if (i.op == mir_op_load() || i.op == mir_op_store() || i.op == mir_op_borrow() || i.op == mir_op_borrow_mut()) && (store.places)[i.place - 1].kind == mir_place_deref() { uses = try mir_vp4_use(d, uses, (store.places)[i.place - 1].deref_value, block, id, 0, 0, 0) }
                uses = try mir_vp4_direct_uses(d, uses, i, id)
                var pass: U64 = 0
                while pass < 3 {
                    var kind = mir_operand_instruction()
                    if pass == 1 { kind = mir_operand_aggregate_field() }
                    if pass == 2 { kind = mir_operand_checked_edge_arg() }
                    var belongs = i.op == mir_op_cleanup_push() || i.op == mir_op_call() || i.op == mir_op_ffi_call_unsafe()
                    if pass == 1 { belongs = i.op == mir_op_aggregate_construct() }
                    if pass == 2 { belongs = mir_vop_checked(i.op) }
                    if belongs {
                        let ocount = mir_vindex_op_instr_count(indexes, id)
                        var oi: U64 = 0
                        while oi < ocount {
                            let oid = mir_vindex_op_instr(indexes, id, oi)
                            let o = (store.operands)[oid - 1]
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
            let t = (store.terminators)[term_id - 1]
            uses = try mir_vp4_use(d, uses, t.value, block, 0, term_id, 0, 0)
            let ocount = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < ocount {
                let oid = mir_vindex_op_term(indexes, term_id, oi)
                let o = (store.operands)[oid - 1]
                if o.kind == mir_operand_terminator_arg() { uses = try mir_vp4_use(d, uses, o.value, block, 0, term_id, oid, 0) }
                if o.kind == mir_operand_switch_case() {
                    let ccount = mir_vindex_op_case_count(indexes, oid)
                    var ai: U64 = 0
                    while ai < ccount {
                        let aid = mir_vindex_op_case(indexes, oid, ai)
                        let a = (store.operands)[aid - 1]
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

fn mir_vp4_collect_uses(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(Vec(MirVP4Use), __s0_Error) {
    let initial = Vec.new(MirVP4Use)
    return mir_vp4_collect_uses_into(d, store, indexes, function, initial)
}

type MirVP4UseInventory {
    function_start: Vec(U64)
    function_count: Vec(U64)
    instruction_start: Vec(U64)
    instruction_count: Vec(U64)
    value_start: Vec(U64)
    value_count: Vec(U64)
    value_use_ids: Vec(U64)
    uses: Vec(MirVP4Use)
}

fn mir_vp4_use_inventory_build(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirVP4UseInventory, __s0_Error) {
    var function_start = Vec.new(U64)
    var function_count = Vec.new(U64)
    var uses = Vec.new(MirVP4Use)
    var function: U64 = 1
    while function <= (store.functions).len() {
        let start = (uses).len()
        try function_start.try_push(start)
        uses = try mir_vp4_collect_uses_into(d, store, indexes, function, uses)
        try function_count.try_push((uses).len() - start)
        function = function + 1
    }
    let instruction_total = (store.instructions).len()
    var instruction_first = __s0_alloc(U64, d, instruction_total + 1)
    var instruction_uses = __s0_alloc(U64, d, instruction_total + 1)
    var at: U64 = 0
    while at <= instruction_total { instruction_first[at] = 0
        instruction_uses[at] = 0
        at = at + 1 }
    at = 0
    while at < (uses).len() {
        let use = uses[at]
        if use.instruction != 0 && use.instruction <= instruction_total {
            if instruction_uses[use.instruction] == 0 { instruction_first[use.instruction] = at }
            instruction_uses[use.instruction] = instruction_uses[use.instruction] + 1
        }
        at = at + 1
    }
    var instruction_start = Vec.new(U64)
    var instruction_count = Vec.new(U64)
    at = 1
    while at <= instruction_total {
        try instruction_start.try_push(instruction_first[at])
        try instruction_count.try_push(instruction_uses[at])
        at = at + 1
    }
    let value_total = (store.values).len()
    var counts = __s0_alloc(U64, d, value_total + 1)
    var starts = __s0_alloc(U64, d, value_total + 1)
    var seen = __s0_alloc(U64, d, value_total + 1)
    at = 0
    while at <= value_total { counts[at] = 0
        starts[at] = 0
        seen[at] = 0
        at = at + 1 }
    function = 1
    while function <= (store.functions).len() {
        let start = function_start[function - 1]
        let count = function_count[function - 1]
        at = 0
        while at < count {
            let use = uses[start + at]
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
    while function <= (store.functions).len() {
        let start = function_start[function - 1]
        let count = function_count[function - 1]
        at = 0
        while at < count {
            let use_id = start + at
            let use = uses[use_id]
            let value = mir_vindex_value(indexes, function, use.value)
            if value != 0 { ids[starts[value] + seen[value]] = use_id + 1
                seen[value] = seen[value] + 1 }
            at = at + 1
        }
        function = function + 1
    }
    var value_start = Vec.new(U64)
    var value_count = Vec.new(U64)
    at = 1
    while at <= value_total { try value_start.try_push(starts[at])
        try value_count.try_push(counts[at])
        at = at + 1 }
    var value_use_ids = Vec.new(U64)
    at = 0
    while at < total { try value_use_ids.try_push(ids[at])
        at = at + 1 }
    return Ok(MirVP4UseInventory(function_start: function_start, function_count: function_count, instruction_start: instruction_start, instruction_count: instruction_count, value_start: value_start, value_count: value_count, value_use_ids: value_use_ids, uses: uses))
}

type MirVP4Point {
    block: U64
    position: U64
}
fn mir_vp4_point_seen(points: Vec(MirVP4Point), block: U64, position: U64) -> Bool { var at: U64 = 0
while at < (points).len() { let p = points[at]
if p.block == block && p.position == position { return true }
at = at + 1 }
return false }
fn mir_vp4_push_point(d: Domain, store: MirStore, function: U64, queue: Vec(MirVP4Point), block: U64, position: U64, suppress_block: U64, suppress_position: U64) -> Result(Vec(MirVP4Point), __s0_Error) {
    if block == suppress_block && position == suppress_position { return Ok(queue) }
    if mir_vblock_index(store, function, block) == 0 || position > mir_vp4_scan_instr_count(store, function, block) { return Ok(queue) }
    return Ok(try vec_appended(MirVP4Point, queue, MirVP4Point(block: block, position: position)))
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
    var queue = Vec.new(MirVP4Point)
    var seen = Vec.new(MirVP4Point)
    queue = try mir_vp4_push_point(d, store, function, queue, 1, 0, suppress_block, suppress_position)
    var q: U64 = 0
    while q < (queue).len() {
        let p = queue[q]
        if !mir_vp4_point_seen(seen, p.block, p.position) {
            if p.block == use_block && p.position == use_position { return Ok(false) }
            try seen.try_push(p)
            let count = mir_vp4_scan_instr_count(store, function, p.block)
            if p.position < count {
                let ins = (store.instructions)[mir_vp4_scan_instr(store, function, p.block, p.position) - 1]
                queue = try mir_vp4_push_point(d, store, function, queue, p.block, p.position + 1, suppress_block, suppress_position)
                if mir_vop_checked(ins.op) { queue = try mir_vp4_push_point(d, store, function, queue, ins.target, 0, suppress_block, suppress_position) }
            } else {
                var ti: U64 = 0
                while ti < (store.terminators).len() { let t = (store.terminators)[ti]
                    if t.function == function && t.block == p.block {
                        if t.kind == mir_term_jump() { queue = try mir_vp4_push_point(d, store, function, queue, t.target, 0, suppress_block, suppress_position) }
                        if t.kind == mir_term_branch() { queue = try mir_vp4_push_point(d, store, function, queue, t.then_block, 0, suppress_block, suppress_position)
queue = try mir_vp4_push_point(d, store, function, queue, t.else_block, 0, suppress_block, suppress_position) }
                        if t.kind == mir_term_switch() { var oi: U64 = 0
while oi < (store.operands).len() { let c = (store.operands)[oi]
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
let p = (store.places)[place - 1]
if p.kind == mir_place_local() { return p.local }
if p.kind != mir_place_field() { return 0 }
return mir_vp4_place_root(store, p.base) }
fn mir_vp4_place_depth(store: MirStore, place: U64) -> U64 { let p = (store.places)[place - 1]
if p.kind == mir_place_local() { return 0 }
return mir_vp4_place_depth(store, p.base) + 1 }
fn mir_vp4_place_component(store: MirStore, place: U64, ordinal: U64) -> U64 { let p = (store.places)[place - 1]
if ordinal + 1 == mir_vp4_place_depth(store, place) { return place }
return mir_vp4_place_component(store, p.base, ordinal) }
fn mir_vp4_place_type(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> U64 { let p = (store.places)[place - 1]
if p.kind == mir_place_local() { return (store.locals)[mir_vindex_local(indexes, function, p.local) - 1].local_type }
let base = mir_vp4_place_type(store, indexes, function, p.base)
let pcount = mir_vindex_type_part_count(indexes, base)
var at: U64 = 0
while at < pcount { let pid = mir_vindex_type_part(indexes, base, at)
let f = (store.type_parts)[pid - 1]
if f.kind == mir_type_part_field() && mir_vname_equal(store, p.field_start, p.field_end, f.name_start, f.name_end) { return f.part_type }
at = at + 1 }
return 0 }
// suffix contains canonical type-part IDs for fields below the loaded place.
fn mir_vp4_store_covers(store: MirStore, indexes: MirVIndexes, store_place: U64, load_place: U64, load_root: U64, load_depth: U64, suffix: Vec(U64)) -> Bool {
    if store_place != 0 && store_place == load_place { return true }
    if (indexes.place_root)[store_place - 1] != load_root { return false }
    let sd = (indexes.place_depth)[store_place - 1]
    let ld = load_depth
    if sd > ld + (suffix).len() { return false }
    var n: U64 = 0
    while n < sd { let sp = (store.places)[mir_vp4_place_component(store, store_place, n) - 1]
        if n < ld { let lp = (store.places)[mir_vp4_place_component(store, load_place, n) - 1]
if !mir_vname_equal(store, sp.field_start, sp.field_end, lp.field_start, lp.field_end) { return false } }
        else { let fp = (store.type_parts)[suffix[n - ld] - 1]
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
fn mir_vp4_init_function(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, function: U64, reach: Vec(U64), initial: Vec(MirVerifyDiagRec)) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let node_count = cfg.node_count
    var seen = __s0_alloc(U64, d, node_count + 1)
    var queue = __s0_alloc(U64, d, node_count + 1)
    var instruction_at = __s0_alloc(U64, d, node_count + 1)
    let queue_base = node_count + 1
    var z: U64 = 0
    while z <= node_count { seen[z] = 0
        instruction_at[z] = 0
        z = z + 1 }
    var indexed_block: U64 = 1
    while indexed_block <= cfg.block_count {
        let indexed_count = (cfg.block_instr_count)[indexed_block - 1]
        let indexed_base = (cfg.boundary_offset)[indexed_block - 1]
        var indexed_position: U64 = 0
        while indexed_position < indexed_count {
            instruction_at[indexed_base + indexed_position] = mir_vindex_instr(indexes, function, indexed_block, indexed_position)
            indexed_position = indexed_position + 1
        }
        indexed_block = indexed_block + 1
    }
    var stamp: U64 = 0
    var block: U64 = 1
    while block <= cfg.block_count {
        if mir_vseen_block(reach, block) {
            let icount = (cfg.block_instr_count)[block - 1]
            let block_base = (cfg.boundary_offset)[block - 1]
            var position: U64 = 0
            while position < icount {
                let iid = instruction_at[block_base + position]
                if iid != 0 {
                    let ins = (store.instructions)[iid - 1]
                    if ins.op == mir_op_load() || ins.op == mir_op_borrow() || ins.op == mir_op_borrow_mut() {
                        let load_root = (indexes.place_root)[ins.place - 1]
                        let load_depth = (indexes.place_depth)[ins.place - 1]
                        if load_root != 0 {
                            let ty = mir_vp4_place_type(store, indexes, function, ins.place)
                            var work = Vec.new(MirVP4InitWork)
                            try work.try_push(MirVP4InitWork(type_id: ty, parent: 0, part: 0))
                            var q: U64 = 0
                            var failing = false
                            while q < (work).len() && !failing {
                                let entry = work[q]
                                let fields = mir_vindex_type_field_count(indexes, entry.type_id)
                                if mir_vtype_kind(store, entry.type_id) != mir_type_kind_aggregate() || fields == 0 {
                                    // Rebuild this leaf's suffix root-first from the parent chain.
                                    var chain = Vec.new(U64)
                                    var cur = q
                                    while cur != 0 { let e = work[cur]
                                        try chain.try_push(e.part)
                                        cur = e.parent }
                                    var suffix = Vec.new(U64)
                                    var k = (chain).len()
                                    while k > 0 { try suffix.try_push(chain[k - 1])
                                        k = k - 1 }
                                    // A covering store earlier in this block
                                    // necessarily dominates the load because
                                    // MIR edges enter only at block boundaries.
                                    var initialized_here = false
                                    var prior_position = position
                                    while prior_position > 0 && !initialized_here { prior_position = prior_position - 1
                                        let prior_id = instruction_at[block_base + prior_position]
                                        let prior = (store.instructions)[prior_id - 1]
                                        if prior.op == mir_op_store() && mir_vp4_store_covers(store, indexes, prior.place, ins.place, load_root, load_depth, suffix) { initialized_here = true }
                                    }
                                    if !initialized_here {
                                        // Stamped reachability BFS for this leaf.
                                        stamp = stamp + 1
                                        var queue_count: U64 = 1
                                        queue[0] = queue_base
                                        seen[(cfg.boundary_offset)[0]] = stamp
                                        var qq: U64 = 0
                                        var reached = false
                                        while qq < queue_count && !reached {
                                        let encoded = queue[qq]
                                        let point_block = encoded / queue_base
                                        let point_position = encoded % queue_base
                                        if point_block == block && point_position == position { reached = true } else {
                                            let count = (cfg.block_instr_count)[point_block - 1]
                                            if point_position < count {
                                                let step_node = (cfg.boundary_offset)[point_block - 1] + point_position
                                                let step = (store.instructions)[instruction_at[step_node] - 1]
                                                if !(step.op == mir_op_store() && mir_vp4_store_covers(store, indexes, step.place, ins.place, load_root, load_depth, suffix)) { let next_position = point_position + 1
                                                    let next_node = (cfg.boundary_offset)[point_block - 1] + next_position
                                                    if seen[next_node] != stamp { seen[next_node] = stamp
                                                        queue[queue_count] = point_block * queue_base + next_position
                                                        queue_count = queue_count + 1 } }
                                                if mir_vop_checked(step.op) && step.target >= 1 && step.target <= cfg.block_count { let next_node = (cfg.boundary_offset)[step.target - 1]
                                                    if seen[next_node] != stamp { seen[next_node] = stamp
                                                        queue[queue_count] = step.target * queue_base
                                                        queue_count = queue_count + 1 } }
                                            } else {
                                                let term_id = mir_vindex_term(indexes, function, point_block)
                                                if term_id != 0 {
                                                    let t = (store.terminators)[term_id - 1]
                                                    if t.kind == mir_term_jump() && t.target >= 1 && t.target <= cfg.block_count { let next_node = (cfg.boundary_offset)[t.target - 1]
                                                        if seen[next_node] != stamp { seen[next_node] = stamp
                                                            queue[queue_count] = t.target * queue_base
                                                            queue_count = queue_count + 1 } }
                                                    if t.kind == mir_term_branch() {
                                                        if t.then_block >= 1 && t.then_block <= cfg.block_count { let next_node = (cfg.boundary_offset)[t.then_block - 1]
                                                            if seen[next_node] != stamp { seen[next_node] = stamp
                                                                queue[queue_count] = t.then_block * queue_base
                                                                queue_count = queue_count + 1 } }
                                                        if t.else_block >= 1 && t.else_block <= cfg.block_count { let next_node = (cfg.boundary_offset)[t.else_block - 1]
                                                            if seen[next_node] != stamp { seen[next_node] = stamp
                                                                queue[queue_count] = t.else_block * queue_base
                                                                queue_count = queue_count + 1 } }
                                                    }
                                                    if t.kind == mir_term_switch() { let ccount = mir_vindex_op_term_count(indexes, term_id)
                                                        var at2: U64 = 0
                                                        while at2 < ccount { let case_id = mir_vindex_op_term(indexes, term_id, at2)
                                                            let c = (store.operands)[case_id - 1]
                                                            if c.kind == mir_operand_switch_case() && c.target >= 1 && c.target <= cfg.block_count { let next_node = (cfg.boundary_offset)[c.target - 1]
                                                                if seen[next_node] != stamp { seen[next_node] = stamp
                                                                    queue[queue_count] = c.target * queue_base
                                                                    queue_count = queue_count + 1 } }
                                                            at2 = at2 + 1
                                                        } }
                                                    }
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
let f = (store.type_parts)[pid - 1]
if f.kind == mir_type_part_field() && f.ordinal == ordinal { found = pid }
at = at + 1 }
                                        try work.try_push(MirVP4InitWork(type_id: (store.type_parts)[found - 1].part_type, parent: q, part: found))
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

fn mir_vphase4_with_uses(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, initial: Vec(MirVerifyDiagRec)) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var function: U64 = 1
    while function <= (store.functions).len() {
        let reach = try mir_vreachable(d, store, indexes, function)
        let cfg = try mir_vp4_cfg_build(d, store, indexes, function)
        let dom = try mir_vp4_dom_build(d, cfg)
        let use_start = (inventory.function_start)[function - 1]
        let use_count = (inventory.function_count)[function - 1]
        var at: U64 = 0
        while at < use_count {
            let u = (inventory.uses)[use_start + at]
            if mir_vseen_block(reach, u.block) {
                let vi = mir_vindex_value(indexes, function, u.value)
                if vi != 0 {
                    let value = (store.values)[vi - 1]
                    var use_pos = mir_vindex_instr_count(indexes, function, u.block)
                    if u.instruction != 0 { use_pos = (store.instructions)[u.instruction - 1].ordinal }
                    var dominated = value.def_kind == mir_value_def_function_param()
                    if value.def_kind == mir_value_def_switch_case() && value.block == u.block && value.item == u.switch_case { dominated = true }
                    if !dominated { dominated = mir_vp4_avail_dominates(cfg, dom, value.def_kind, value.block, value.item, u.block, use_pos) }
                    if !dominated { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_dominance(), mir_vdiag_not_dominated(), function, u.block, u.instruction, u.terminator, u.operand, value.value_type, vi, 0, 0, u.value)) }
                }
            }
            at = at + 1
        }
        out = try mir_vp4_init_function(d, store, indexes, cfg, function, reach, out)
        function = function + 1
    }
    return Ok(out)
}

fn mir_vphase4(d: Domain, store: MirStore, indexes: MirVIndexes, initial: Vec(MirVerifyDiagRec)) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    let inventory = try mir_vp4_use_inventory_build(d, store, indexes)
    return mir_vphase4_with_uses(d, store, indexes, inventory, initial)
}
