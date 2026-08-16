// Phase 6 ports the Go verifier's finite domain/provenance and resource
// lattices over flat MIR IDs. Facts are append-only sets; membership and
// per-value scans go through dense per-(function, value) bucket indexes
// (facts) and per-function bucket indexes (effects) that are rebuilt once
// per fixpoint iteration with function-local arrays and copied into buffers.
// A mid-iteration stale index only ever turns a dedup into a duplicate
// append, which no downstream boolean query can observe and the length-based
// changed test still terminates on (see mir_v6_rebuild_index).
fn mir_v6_fact_dep() -> U64 { return 1 }
fn mir_v6_fact_parent() -> U64 { return 2 }
fn mir_v6_fact_root() -> U64 { return 3 }
fn mir_v6_fact_param() -> U64 { return 4 }
fn mir_v6_effect_destroy() -> U64 { return 1 }
fn mir_v6_effect_reset() -> U64 { return 2 }
fn mir_v6_effect_result_from() -> U64 { return 3 }
fn mir_v6_effect_result_alloc() -> U64 { return 4 }
fn mir_v6_state_dead() -> U64 { return 1 }
fn mir_v6_state_root() -> U64 { return 2 }
fn mir_v6_state_mark() -> U64 { return 3 }

type MirV6Fact {
    function: U64
    value: U64
    kind: U64
    a: U64
    b: U64
    c: U64
}
type MirV6Effect {
    function: U64
    parameter: U64
    kind: U64
}
type MirV6Analysis {
    facts: __s0_Buffer(MirV6Fact)
    effects: __s0_Buffer(MirV6Effect)
    // fact_key_base[function - 1] is the linearized key offset of the
    // function's first value, so key = fact_key_base[function - 1] + value
    // maps each (function, value) pair to a dense slot in fact_span/fact_pos.
    fact_key_base: __s0_Buffer(U64)
    // fact_span[key] is the start position of key's bucket in fact_pos;
    // fact_span[key + 1] is its end (fact_span has a trailing sentinel).
    fact_span: __s0_Buffer(U64)
    fact_pos: __s0_Buffer(U64)
    // effect_span[function] / effect_span[function + 1] delimit the
    // function's effect bucket in effect_pos (trailing sentinel included).
    effect_span: __s0_Buffer(U64)
    effect_pos: __s0_Buffer(U64)
}
type MirV6StateFact {
    kind: U64
    a: U64
    b: U64
    c: U64
}
type MirV6EntryFact {
    block: U64
    state: MirV6StateFact
}
type MirV6ReachFact {
    from: U64
    to: U64
}

fn mir_v6_fact_start(analysis: MirV6Analysis, function: U64, value: U64) -> U64 { let kb = analysis.fact_key_base
if function == 0 || function > __s0_buffer_len(U64, kb) { return 0 }
let key = __s0_buffer_get(U64, kb, function - 1) + value
let span = analysis.fact_span
if key >= __s0_buffer_len(U64, span) - 1 { return 0 }
return __s0_buffer_get(U64, span, key) }
fn mir_v6_fact_end(analysis: MirV6Analysis, function: U64, value: U64) -> U64 { let kb = analysis.fact_key_base
if function == 0 || function > __s0_buffer_len(U64, kb) { return 0 }
let key = __s0_buffer_get(U64, kb, function - 1) + value
let span = analysis.fact_span
if key >= __s0_buffer_len(U64, span) - 1 { return 0 }
return __s0_buffer_get(U64, span, key + 1) }
fn mir_v6_effect_start(analysis: MirV6Analysis, function: U64) -> U64 { let span = analysis.effect_span
if function == 0 || function >= __s0_buffer_len(U64, span) { return 0 }
return __s0_buffer_get(U64, span, function) }
fn mir_v6_effect_end(analysis: MirV6Analysis, function: U64) -> U64 { let span = analysis.effect_span
if function == 0 || function >= __s0_buffer_len(U64, span) { return 0 }
return __s0_buffer_get(U64, span, function + 1) }
fn mir_v6_fact_at(analysis: MirV6Analysis, at: U64) -> MirV6Fact { return __s0_buffer_get(MirV6Fact, analysis.facts, __s0_buffer_get(U64, analysis.fact_pos, at) - 1) }
fn mir_v6_effect_at(analysis: MirV6Analysis, at: U64) -> MirV6Effect { return __s0_buffer_get(MirV6Effect, analysis.effects, __s0_buffer_get(U64, analysis.effect_pos, at) - 1) }

// Rebuilds the fact and effect buckets from the current buffers. One pass
// counts records per bucket into function-local arrays, a prefix pass fixes
// the start positions, and a placement pass writes each record id once; the
// results are copied into buffers for storage in the analysis record. The
// index is exact for the buffer contents at build time; appends made later in
// the same fixpoint iteration only make it stale, and a stale membership
// miss merely appends a duplicate that no query or diagnostic can observe.
// Once an iteration adds no new fact or effect, a fresh index makes every
// add hit, the lengths stop changing, and the loop terminates with an exact
// index that the per-function query passes can rely on.
fn mir_v6_rebuild_index(d: Domain, store: MirStore, indexes: MirVIndexes, analysis0: MirV6Analysis) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
let total = __s0_buffer_len(MirV6Fact, analysis.facts)
var key_base = __s0_alloc(U64, d, fcount + 1)
var z: U64 = 0
while z <= fcount { key_base[z] = 0
z = z + 1 }
var f: U64 = 1
while f <= fcount { key_base[f] = key_base[f - 1] + __s0_buffer_get(U64, indexes.value_count, f - 1)
f = f + 1 }
let total_keys = key_base[fcount]
var cnt = __s0_alloc(U64, d, total_keys + 2)
var base = __s0_alloc(U64, d, total_keys + 2)
var cursor = __s0_alloc(U64, d, total_keys + 2)
var k: U64 = 0
while k <= total_keys + 1 { cnt[k] = 0
base[k] = 0
cursor[k] = 0
k = k + 1 }
var i: U64 = 0
while i < total {
    let fact = __s0_buffer_get(MirV6Fact, analysis.facts, i)
    if fact.function >= 1 && fact.function <= fcount {
        let key = key_base[fact.function - 1] + fact.value
        if key >= 1 && key <= total_keys { cnt[key] = cnt[key] + 1 }
    }
    i = i + 1
}
k = 0
while k <= total_keys { base[k + 1] = base[k] + cnt[k]
k = k + 1 }
k = 0
while k <= total_keys + 1 { cursor[k] = base[k] + 0
k = k + 1 }
let pos = __s0_alloc(U64, d, total)
i = 0
while i < total {
    let fact = __s0_buffer_get(MirV6Fact, analysis.facts, i)
    if fact.function >= 1 && fact.function <= fcount {
        let key = key_base[fact.function - 1] + fact.value
        if key >= 1 && key <= total_keys { let slot = cursor[key]
pos[slot] = i + 1
cursor[key] = slot + 1 }
    }
    i = i + 1
}
var span = try __s0_buffer_new(U64, d)
k = 0
while k <= total_keys + 1 { span = try __s0_buffer_append(U64, d, span, base[k])
k = k + 1 }
var pos_buf = try __s0_buffer_new(U64, d)
var p: U64 = 0
while p < total { pos_buf = try __s0_buffer_append(U64, d, pos_buf, pos[p])
p = p + 1 }
var kb = try __s0_buffer_new(U64, d)
var f2: U64 = 0
while f2 < fcount { kb = try __s0_buffer_append(U64, d, kb, key_base[f2])
f2 = f2 + 1 }
analysis.fact_key_base = kb
analysis.fact_span = span
analysis.fact_pos = pos_buf
let etotal = __s0_buffer_len(MirV6Effect, analysis.effects)
var ecnt = __s0_alloc(U64, d, fcount + 1)
var ebase = __s0_alloc(U64, d, fcount + 2)
var ecursor = __s0_alloc(U64, d, fcount + 2)
var e: U64 = 0
while e <= fcount + 1 { if e <= fcount { ecnt[e] = 0 }
ebase[e] = 0
ecursor[e] = 0
e = e + 1 }
i = 0
while i < etotal {
    let effect = __s0_buffer_get(MirV6Effect, analysis.effects, i)
    if effect.function >= 1 && effect.function <= fcount { ecnt[effect.function] = ecnt[effect.function] + 1 }
    i = i + 1
}
f = 1
while f <= fcount + 1 { ebase[f] = ebase[f - 1] + ecnt[f - 1]
f = f + 1 }
e = 0
while e <= fcount + 1 { ecursor[e] = ebase[e] + 0
e = e + 1 }
let epos = __s0_alloc(U64, d, etotal)
i = 0
while i < etotal {
    let effect = __s0_buffer_get(MirV6Effect, analysis.effects, i)
    if effect.function >= 1 && effect.function <= fcount { let slot = ecursor[effect.function]
epos[slot] = i + 1
ecursor[effect.function] = slot + 1 }
    i = i + 1
}
var espan = try __s0_buffer_new(U64, d)
e = 0
while e <= fcount + 1 { espan = try __s0_buffer_append(U64, d, espan, ebase[e])
e = e + 1 }
var epos_buf = try __s0_buffer_new(U64, d)
p = 0
while p < etotal { epos_buf = try __s0_buffer_append(U64, d, epos_buf, epos[p])
p = p + 1 }
analysis.effect_span = espan
analysis.effect_pos = epos_buf
return Ok(analysis) }

fn mir_v6_fact_has(analysis: MirV6Analysis, item: MirV6Fact) -> Bool { var at = mir_v6_fact_start(analysis, item.function, item.value)
let end = mir_v6_fact_end(analysis, item.function, item.value)
while at < end { let x = mir_v6_fact_at(analysis, at)
if x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
at = at + 1 }
// Facts appended after the last rebuild are not in the buckets yet.
var tail = __s0_buffer_len(U64, analysis.fact_pos)
while tail < __s0_buffer_len(MirV6Fact, analysis.facts) {
    let x = __s0_buffer_get(MirV6Fact, analysis.facts, tail)
    if x.function == item.function && x.value == item.value && x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
    tail = tail + 1
}
return false }
fn mir_v6_fact_add(d: Domain, analysis0: MirV6Analysis, item: MirV6Fact) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
if mir_v6_fact_has(analysis, item) { return Ok(analysis) }
analysis.facts = try __s0_buffer_append(MirV6Fact, d, analysis.facts, item)
return Ok(analysis) }
fn mir_v6_effect_has(analysis: MirV6Analysis, function: U64, parameter: U64, kind: U64) -> Bool { var at = mir_v6_effect_start(analysis, function)
let end = mir_v6_effect_end(analysis, function)
while at < end { let x = mir_v6_effect_at(analysis, at)
if x.parameter == parameter && x.kind == kind { return true }
at = at + 1 }
var tail = __s0_buffer_len(U64, analysis.effect_pos)
while tail < __s0_buffer_len(MirV6Effect, analysis.effects) {
    let x = __s0_buffer_get(MirV6Effect, analysis.effects, tail)
    if x.function == function && x.parameter == parameter && x.kind == kind { return true }
    tail = tail + 1
}
return false }
fn mir_v6_effect_add(d: Domain, analysis0: MirV6Analysis, function: U64, parameter: U64, kind: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
if mir_v6_effect_has(analysis, function, parameter, kind) { return Ok(analysis) }
analysis.effects = try __s0_buffer_append(MirV6Effect, d, analysis.effects, MirV6Effect(function: function, parameter: parameter, kind: kind))
return Ok(analysis) }
fn mir_v6_merge_value(d: Domain, analysis0: MirV6Analysis, function: U64, target: U64, source: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
var at = mir_v6_fact_start(analysis, function, source)
let end = mir_v6_fact_end(analysis, function, source)
while at < end { let x = mir_v6_fact_at(analysis, at)
analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: target, kind: x.kind, a: x.a, b: x.b, c: x.c))
at = at + 1 }
return Ok(analysis) }

fn mir_v6_type_contains(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64, wanted: U64) -> Result(Bool, __s0_Error) { var work = try __s0_buffer_new(U64, d)
work = try __s0_buffer_append(U64, d, work, root)
// O(1) visited probe; the linear seen scan was quadratic on the dense type
// graph and ran once per value/use in phases 6, 9, and 10.
let tcount = __s0_buffer_len(MirTypeRec, store.types)
var seen = __s0_alloc(U64, d, tcount + 1)
var z: U64 = 0
while z <= tcount { seen[z] = 0
z = z + 1 }
var at: U64 = 0
while at < __s0_buffer_len(U64, work) { let id = __s0_buffer_get(U64, work, at)
if id >= 1 && id <= tcount && seen[id] == 0 { if mir_vtype_kind(store, id) == wanted { return Ok(true) }
seen[id] = 1
work = try mir_vappend_type_children(d, store, indexes, work, id) }
at = at + 1 }
return Ok(false) }
fn mir_v6_type_reference(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_slice()) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) }
fn mir_v6_type_local_store(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_reference(d, store, indexes, type_id) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_handle()) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_mark()) }

fn mir_v6_instruction_for_value(store: MirStore, indexes: MirVIndexes, value: MirValueRec) -> U64 { if value.def_kind != mir_value_def_instruction() { return 0 }
return mir_vindex_instr(indexes, value.function, value.block, value.item - 1) }
fn mir_v6_function_param_ordinal(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if p.kind == mir_param_function() && p.value == value { return p.ordinal + 1 }
        at = at + 1
    }
    return 0
}
fn mir_v6_operand_value(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 { let oi = mir_v5_operand(store, indexes, kind, owner, edge, ordinal)
if oi == 0 { return 0 }
return __s0_buffer_get(MirOperandRec, store.operands, oi - 1).value }
fn mir_v6_place_deref(store: MirStore, place: U64) -> Bool { var p = place
while p != 0 { let x = __s0_buffer_get(MirPlaceRec, store.places, p - 1)
if x.kind == mir_place_deref() { return true }
if x.kind != mir_place_field() { return false }
p = x.base }
return false }
fn mir_v6_places_alias(store: MirStore, a: U64, b: U64) -> Bool { let ad = mir_v6_place_deref(store, a)
let bd = mir_v6_place_deref(store, b)
if ad || bd { return ad && bd }
if mir_vp4_place_root(store, a) != mir_vp4_place_root(store, b) { return false }
let an = mir_vp4_place_depth(store, a)
let bn = mir_vp4_place_depth(store, b)
var n: U64 = 0
var limit = an
if bn < limit { limit = bn }
while n < limit { let ap = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, a, n) - 1)
let bp = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, b, n) - 1)
if !mir_vname_equal(store, ap.field_start, ap.field_end, bp.field_start, bp.field_end) { return false }
n = n + 1 }
return true }

fn mir_v6_transfer_value(d: Domain, store: MirStore, indexes: MirVIndexes, analysis0: MirV6Analysis, function: U64, value_id: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
let vi = mir_vindex_value(indexes, function, value_id)
let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if value.def_kind == mir_value_def_function_param() { let parameter = mir_v6_function_param_ordinal(store, indexes, function, value_id)
analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_param(), a: parameter, b: 0, c: 0))
if try mir_v6_type_reference(d, store, indexes, value.value_type) { let pcount = mir_vindex_param_count(indexes, function)
var pi: U64 = 0
while pi < pcount { let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, pi) - 1)
if p.kind == mir_param_function() && mir_vtype_kind(store, p.param_type) == mir_type_kind_domain_handle() { analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: p.ordinal + 1, c: 0)) }
pi = pi + 1 }
analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: value_id, b: 0, c: parameter)) }
if mir_vtype_kind(store, value.value_type) == mir_type_kind_domain_handle() { analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: parameter, c: 0)) }
return Ok(analysis) }
if value.def_kind == mir_value_def_block_param() {
    // Incoming edge operands of this block parameter, enumerated through the
    // per-owner operand indexes in instruction/terminator storage order.
    let bcount = mir_vindex_block_count(indexes, function)
    var b: U64 = 1
    while b <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, b)
        var ii: U64 = 0
        while ii < icount {
            let iid = mir_vindex_instr(indexes, function, b, ii)
            let total = mir_vindex_op_instr_count(indexes, iid)
            var oi: U64 = 0
            while oi < total {
                let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, oi) - 1)
                if o.kind == mir_operand_checked_edge_arg() && o.target == value.block && o.ordinal + 1 == value.item { analysis = try mir_v6_merge_value(d, analysis, function, value_id, o.value) }
                oi = oi + 1
            }
            ii = ii + 1
        }
        let term_id = mir_vindex_term(indexes, function, b)
        if term_id != 0 {
            let total = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < total {
                let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                if o.kind == mir_operand_terminator_arg() && o.target == value.block && o.ordinal + 1 == value.item { analysis = try mir_v6_merge_value(d, analysis, function, value_id, o.value) }
                oi = oi + 1
            }
            var ci: U64 = 0
            while ci < total {
                let cid = mir_vindex_op_term(indexes, term_id, ci)
                let c = __s0_buffer_get(MirOperandRec, store.operands, cid - 1)
                if c.kind == mir_operand_switch_case() {
                    let atotal = mir_vindex_op_case_count(indexes, cid)
                    var ai: U64 = 0
                    while ai < atotal {
                        let a = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_case(indexes, cid, ai) - 1)
                        if a.target == value.block && a.ordinal + 1 == value.item { analysis = try mir_v6_merge_value(d, analysis, function, value_id, a.value) }
                        ai = ai + 1
                    }
                }
                ci = ci + 1
            }
        }
        b = b + 1
    }
    return Ok(analysis)
}
if value.def_kind == mir_value_def_switch_case() { let term_id = mir_vindex_term(indexes, function, value.block)
if term_id != 0 { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
analysis = try mir_v6_merge_value(d, analysis, function, value_id, t.value) }
return Ok(analysis) }
let iid = mir_v6_instruction_for_value(store, indexes, value)
if iid == 0 { return Ok(analysis) }
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_domain_create() { var at = mir_v6_fact_start(analysis, function, x.a)
let dend = mir_v6_fact_end(analysis, function, x.a)
while at < dend { let f = mir_v6_fact_at(analysis, at)
if f.kind == mir_v6_fact_dep() || f.kind == mir_v6_fact_parent() { analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_parent(), a: f.a, b: f.b, c: f.c)) }
at = at + 1 }
analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: x.block, b: x.ordinal + 1, c: 0)) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() { analysis = try mir_v6_merge_value(d, analysis, function, value_id, x.a)
if x.op == mir_op_copy_to_domain() { analysis = try mir_v6_merge_value(d, analysis, function, value_id, x.b) }
analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: x.a, b: x.block, c: x.ordinal + 1)) }
if x.op == mir_op_load() { let p = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
if p.kind == mir_place_deref() { analysis = try mir_v6_merge_value(d, analysis, function, value_id, p.deref_value) }
// Aliasing stores of the function, enumerated block by block.
let bcount = mir_vindex_block_count(indexes, function)
var b: U64 = 1
while b <= bcount { let icount = mir_vindex_instr_count(indexes, function, b)
var ii: U64 = 0
while ii < icount { let sid = mir_vindex_instr(indexes, function, b, ii)
let s = __s0_buffer_get(MirInstrRec, store.instructions, sid - 1)
if s.op == mir_op_store() && mir_v6_places_alias(store, x.place, s.place) { analysis = try mir_v6_merge_value(d, analysis, function, value_id, s.a) }
ii = ii + 1 }
b = b + 1 } }
if x.op == mir_op_aggregate_construct() { let total = mir_vindex_op_instr_count(indexes, iid)
var oi: U64 = 0
while oi < total { let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, oi) - 1)
if o.kind == mir_operand_aggregate_field() { analysis = try mir_v6_merge_value(d, analysis, function, value_id, o.value) }
oi = oi + 1 } }
if x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { analysis = try mir_v6_merge_value(d, analysis, function, value_id, x.a) }
if x.op == mir_op_call() { var e = mir_v6_effect_start(analysis, x.target)
let eend = mir_v6_effect_end(analysis, x.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_result_from() || effect.kind == mir_v6_effect_result_alloc() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
analysis = try mir_v6_merge_value(d, analysis, function, value_id, arg)
if effect.kind == mir_v6_effect_result_alloc() { analysis = try mir_v6_fact_add(d, analysis, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: arg, b: x.block, c: x.ordinal + 1)) } }
e = e + 1 } }
return Ok(analysis) }

fn mir_v6_add_param_effects(d: Domain, analysis0: MirV6Analysis, function: U64, value: U64, kind: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
var at = mir_v6_fact_start(analysis, function, value)
let end = mir_v6_fact_end(analysis, function, value)
while at < end { let f = mir_v6_fact_at(analysis, at)
if f.kind == mir_v6_fact_param() { analysis = try mir_v6_effect_add(d, analysis, function, f.a, kind) }
at = at + 1 }
return Ok(analysis) }
fn mir_v6_add_cleanup_effects(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis, analysis0: MirV6Analysis, function: U64, active0: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
var active = active0
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e = mir_v6_effect_start(analysis, push.target)
let eend = mir_v6_effect_end(analysis, push.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
analysis = try mir_v6_add_param_effects(d, analysis, function, arg, effect.kind) }
e = e + 1 } } }
active = node.parent }
return Ok(analysis) }

fn mir_v6_compute(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis) -> Result(MirV6Analysis, __s0_Error) { var analysis = MirV6Analysis(facts: try __s0_buffer_new(MirV6Fact, d), effects: try __s0_buffer_new(MirV6Effect, d), fact_key_base: try __s0_buffer_new(U64, d), fact_span: try __s0_buffer_new(U64, d), fact_pos: try __s0_buffer_new(U64, d), effect_span: try __s0_buffer_new(U64, d), effect_pos: try __s0_buffer_new(U64, d))
var changed = true
var rounds: U64 = 0
while changed && rounds < 64 { rounds = rounds + 1
analysis = try mir_v6_rebuild_index(d, store, indexes, analysis)
let before_facts = __s0_buffer_len(MirV6Fact, analysis.facts)
let before_effects = __s0_buffer_len(MirV6Effect, analysis.effects)
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { var value: U64 = 1
while mir_vindex_value(indexes, function, value) != 0 { analysis = try mir_v6_transfer_value(d, store, indexes, analysis, function, value)
value = value + 1 }
let bcount = mir_vindex_block_count(indexes, function)
var block: U64 = 1
while block <= bcount {
    let icount = mir_vindex_instr_count(indexes, function, block)
    var ii: U64 = 0
    while ii < icount {
        let iid = mir_vindex_instr(indexes, function, block, ii)
        let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
        if x.op == mir_op_domain_destroy() { analysis = try mir_v6_add_param_effects(d, analysis, function, x.a, mir_v6_effect_destroy()) }
        if x.op == mir_op_domain_reset() { analysis = try mir_v6_add_param_effects(d, analysis, function, x.a, mir_v6_effect_reset()) }
        if x.op == mir_op_call() { var e = mir_v6_effect_start(analysis, x.target)
let eend = mir_v6_effect_end(analysis, x.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
analysis = try mir_v6_add_param_effects(d, analysis, function, arg, effect.kind) }
e = e + 1 } }
        if x.op == mir_op_cleanup_scope_run() { var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { analysis = try mir_v6_add_cleanup_effects(d, store, indexes, cleanup, analysis, function, set.active) }
si = si + 1 } }
        ii = ii + 1
    }
    let term_id = mir_vindex_term(indexes, function, block)
    if term_id != 0 {
        let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
        if (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { var f = mir_v6_fact_start(analysis, function, t.value)
let fend = mir_v6_fact_end(analysis, function, t.value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_param() { analysis = try mir_v6_effect_add(d, analysis, function, fact.a, mir_v6_effect_result_from()) }
if fact.kind == mir_v6_fact_root() && fact.b != 0 { var h = mir_v6_fact_start(analysis, function, fact.a)
let hend = mir_v6_fact_end(analysis, function, fact.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_param() { analysis = try mir_v6_effect_add(d, analysis, function, owner.a, mir_v6_effect_result_alloc()) }
h = h + 1 } }
f = f + 1 } }
    }
    block = block + 1
}
function = function + 1 }
changed = before_facts != __s0_buffer_len(MirV6Fact, analysis.facts) || before_effects != __s0_buffer_len(MirV6Effect, analysis.effects) }
return Ok(analysis) }

fn mir_v6_dep_alias(a: MirV6Fact, b: MirV6StateFact) -> Bool { return a.a == b.a && a.b == b.b || a.a == 0 && b.a == 0 }
fn mir_v6_state_has(state: __s0_Buffer(MirV6StateFact), item: MirV6StateFact) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
at = at + 1 }
return false }
fn mir_v6_state_add(d: Domain, state: __s0_Buffer(MirV6StateFact), item: MirV6StateFact) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { if mir_v6_state_has(state, item) { return Ok(state) }
return __s0_buffer_append(MirV6StateFact, d, state, item) }
fn mir_v6_value_invalid(analysis: MirV6Analysis, state: __s0_Buffer(MirV6StateFact), function: U64, value: U64) -> Bool { var s: U64 = 0
while s < __s0_buffer_len(MirV6StateFact, state) { let dead = __s0_buffer_get(MirV6StateFact, state, s)
if dead.kind == mir_v6_state_mark() && dead.a == value { return true }
var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if (fact.kind == mir_v6_fact_dep() || fact.kind == mir_v6_fact_parent()) && dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
if fact.kind == mir_v6_fact_root() && dead.kind == mir_v6_state_root() && fact.a == dead.a && fact.b == dead.b && fact.c == dead.c { return true }
f = f + 1 }
s = s + 1 }
return false }
fn mir_v6_domain_dead(analysis: MirV6Analysis, state: __s0_Buffer(MirV6StateFact), function: U64, value: U64) -> Bool { var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() { var s: U64 = 0
while s < __s0_buffer_len(MirV6StateFact, state) { let dead = __s0_buffer_get(MirV6StateFact, state, s)
if dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
s = s + 1 } }
f = f + 1 }
return false }
fn mir_v6_domains_alias(analysis: MirV6Analysis, function: U64, a: U64, b: U64) -> Bool { var x = mir_v6_fact_start(analysis, function, a)
let xend = mir_v6_fact_end(analysis, function, a)
while x < xend { let left = mir_v6_fact_at(analysis, x)
if left.kind == mir_v6_fact_dep() { var y = mir_v6_fact_start(analysis, function, b)
let yend = mir_v6_fact_end(analysis, function, b)
while y < yend { let right = mir_v6_fact_at(analysis, y)
if right.kind == mir_v6_fact_dep() && (left.a == right.a && left.b == right.b || left.a == 0 && right.a == 0) { return true }
y = y + 1 } }
x = x + 1 }
return false }
fn mir_v6_root_in_domain(analysis: MirV6Analysis, function: U64, root: MirV6Fact, domain: U64) -> Bool { var h = mir_v6_fact_start(analysis, function, root.a)
let hend = mir_v6_fact_end(analysis, function, root.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() || owner.kind == mir_v6_fact_parent() { var d = mir_v6_fact_start(analysis, function, domain)
let dend = mir_v6_fact_end(analysis, function, domain)
while d < dend { let candidate = mir_v6_fact_at(analysis, d)
if candidate.kind == mir_v6_fact_dep() && (owner.a == candidate.a && owner.b == candidate.b || owner.a == 0 && candidate.a == 0) { return true }
d = d + 1 } }
h = h + 1 }
return false }
fn mir_v6_mark_domain(store: MirStore, indexes: MirVIndexes, function: U64, mark: U64) -> U64 { let vi = mir_vindex_value(indexes, function, mark)
if vi == 0 { return 0 }
let iid = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if iid == 0 { return 0 }
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op != mir_op_domain_mark() { return 0 }
return x.a }
fn mir_v6_clear_produced(d: Domain, state: __s0_Buffer(MirV6StateFact), block: U64, ordinal: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var out = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !(x.kind == mir_v6_state_root() && x.b == block && x.c == ordinal + 1) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_clear_dead(d: Domain, state: __s0_Buffer(MirV6StateFact), block: U64, ordinal: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var out = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !(x.kind == mir_v6_state_dead() && x.a == block && x.b == ordinal + 1) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_clear_mark(d: Domain, state: __s0_Buffer(MirV6StateFact), mark: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var out = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !(x.kind == mir_v6_state_mark() && x.a == mark) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_root_after_mark(store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, root: MirV6Fact, mark: U64) -> Bool {
    if root.b == 0 { return true }
    let mi = mir_vindex_value(indexes, function, mark)
    if mi == 0 { return true }
    let mv = __s0_buffer_get(MirValueRec, store.values, mi - 1)
    // Availability dominance over the prebuilt point CFG replaces the old
    // per-call entry BFS.  A switch-case-defined mark is dominated at its own
    // case binding (phase 4's use-loop shortcut), matching the legacy point
    // walk that suppressed exactly that case edge.
    if mv.def_kind == mir_value_def_switch_case() && mv.block == root.b && mv.item == root.c { return true }
    return mir_vp4_avail_dominates(cfg, dom, mv.def_kind, mv.block, mv.item, root.b, root.c - 1)
}
fn mir_v6_invalidate(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, domain: U64, reset: Bool, mark: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) {
    var state = state0
    if !reset { var f = mir_v6_fact_start(analysis, function, domain)
let fend = mir_v6_fact_end(analysis, function, domain)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_dead(), a: fact.a, b: fact.b, c: 0)) }
f = f + 1 } }
    // Root facts of the function, enumerated through the per-value buckets.
    var v: U64 = 1
    while mir_vindex_value(indexes, function, v) != 0 {
        var r = mir_v6_fact_start(analysis, function, v)
        let rend = mir_v6_fact_end(analysis, function, v)
        while r < rend {
            let root = mir_v6_fact_at(analysis, r)
            if root.kind == mir_v6_fact_root() && mir_v6_root_in_domain(analysis, function, root, domain) {
                if !reset { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_root(), a: root.a, b: root.b, c: root.c)) }
                else { if mir_v6_root_after_mark(store, indexes, cfg, dom, function, root, mark) { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_root(), a: root.a, b: root.b, c: root.c)) } }
            }
            r = r + 1
        }
        v = v + 1
    }
    var vi: U64 = 1
    while mir_vindex_value(indexes, function, vi) != 0 { let md = mir_v6_mark_domain(store, indexes, function, vi)
if md != 0 && mir_v6_domains_alias(analysis, function, md, domain) { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_mark(), a: vi, b: 0, c: 0)) }
vi = vi + 1 }
    return Ok(state)
}
fn mir_v6_apply_cleanup_entry(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, entry: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = state0
let vi = mir_vindex_value(indexes, function, entry)
if vi == 0 { return Ok(state) }
let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id == 0 { return Ok(state) }
let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e = mir_v6_effect_start(analysis, push.target)
let eend = mir_v6_effect_end(analysis, push.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 }
return Ok(state) }
fn mir_v6_apply_cleanup(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), iid: U64, function: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var merged = try __s0_buffer_new(MirV6StateFact, d)
var found = false
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { found = true
var branch = state0
var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
branch = try mir_v6_apply_cleanup_entry(d, store, indexes, cfg, dom, analysis, branch, function, node.entry)
active = node.parent }
var bi: U64 = 0
while bi < __s0_buffer_len(MirV6StateFact, branch) { merged = try mir_v6_state_add(d, merged, __s0_buffer_get(MirV6StateFact, branch, bi))
bi = bi + 1 } }
si = si + 1 }
if found { return Ok(merged) }
return Ok(state0) }
fn mir_v6_apply(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), iid: U64, x: MirInstrRec) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = state0
if x.op == mir_op_domain_create() { state = try mir_v6_clear_dead(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_mark() { state = try mir_v6_clear_mark(d, state, x.result) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_call() { state = try mir_v6_clear_produced(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_destroy() { state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, x.function, x.a, false, 0) }
if x.op == mir_op_domain_reset() { state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, x.function, x.a, true, x.b) }
if x.op == mir_op_call() { var e = mir_v6_effect_start(analysis, x.target)
let eend = mir_v6_effect_end(analysis, x.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, x.function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 } }
if x.op == mir_op_cleanup_scope_run() { state = try mir_v6_apply_cleanup(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x.function) }
return Ok(state) }

fn mir_v6_entry_has(entries: __s0_Buffer(MirV6EntryFact), block: U64, state: MirV6StateFact) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6EntryFact, entries) { let x = __s0_buffer_get(MirV6EntryFact, entries, at)
if x.block == block && x.state.kind == state.kind && x.state.a == state.a && x.state.b == state.b && x.state.c == state.c { return true }
at = at + 1 }
return false }
fn mir_v6_entry_merge(d: Domain, entries0: __s0_Buffer(MirV6EntryFact), block: U64, state: __s0_Buffer(MirV6StateFact)) -> Result(__s0_Buffer(MirV6EntryFact), __s0_Error) { var entries = entries0
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !mir_v6_entry_has(entries, block, x) { entries = try __s0_buffer_append(MirV6EntryFact, d, entries, MirV6EntryFact(block: block, state: x)) }
at = at + 1 }
return Ok(entries) }
fn mir_v6_entry_state(d: Domain, entries: __s0_Buffer(MirV6EntryFact), block: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6EntryFact, entries) { let x = __s0_buffer_get(MirV6EntryFact, entries, at)
if x.block == block { state = try mir_v6_state_add(d, state, x.state) }
at = at + 1 }
return Ok(state) }
fn mir_v6_successors(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, block: U64, out0: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) { var out = out0
let icount = mir_vindex_instr_count(indexes, function, block)
var ii: U64 = 0
while ii < icount {
    let iid = mir_vindex_instr(indexes, function, block, ii)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if mir_vop_checked(x.op) { out = try __s0_buffer_append(U64, d, out, x.target) }
    ii = ii + 1
}
let term_id = mir_vindex_term(indexes, function, block)
if term_id != 0 {
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if t.kind == mir_term_jump() { out = try __s0_buffer_append(U64, d, out, t.target) }
    if t.kind == mir_term_branch() { out = try __s0_buffer_append(U64, d, out, t.then_block)
out = try __s0_buffer_append(U64, d, out, t.else_block) }
    if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
var oi: U64 = 0
while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
if c.kind == mir_operand_switch_case() { out = try __s0_buffer_append(U64, d, out, c.target) }
oi = oi + 1 } }
}
return Ok(out) }
fn mir_v6_solve_states(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, cleanup: MirV7Analysis, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64) -> Result(__s0_Buffer(MirV6EntryFact), __s0_Error) { var entries = try __s0_buffer_new(MirV6EntryFact, d)
let reachable = try mir_vreachable(d, store, indexes, function)
let bcount = mir_vindex_block_count(indexes, function)
var changed = true
while changed { let before = __s0_buffer_len(MirV6EntryFact, entries)
var block: U64 = 1
while block <= bcount { if mir_vseen_block(reachable, block) { var state = try mir_v6_entry_state(d, entries, block)
let icount = mir_vindex_instr_count(indexes, function, block)
var ordinal: U64 = 0
while ordinal < icount {
    let iid = mir_vindex_instr(indexes, function, block, ordinal)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if mir_vop_checked(x.op) { entries = try mir_v6_entry_merge(d, entries, x.target, state) }
    state = try mir_v6_apply(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x)
    ordinal = ordinal + 1
}
let successors = try mir_v6_successors(d, store, indexes, function, block, try __s0_buffer_new(U64, d))
var si: U64 = 0
while si < __s0_buffer_len(U64, successors) { let target = __s0_buffer_get(U64, successors, si)
// Checked successors already received the pre-instruction state above.
var checked = false
var xi: U64 = 0
while xi < icount {
    let q = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, block, xi) - 1)
    if mir_vop_checked(q.op) && q.target == target { checked = true }
    xi = xi + 1
}
if !checked { entries = try mir_v6_entry_merge(d, entries, target, state) }
si = si + 1 } }
block = block + 1 }
changed = before != __s0_buffer_len(MirV6EntryFact, entries) }
return Ok(entries) }

fn mir_v6_reach_has(reach: __s0_Buffer(MirV6ReachFact), from: U64, to: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6ReachFact, reach) { let x = __s0_buffer_get(MirV6ReachFact, reach, at)
if x.from == from && x.to == to { return true }
at = at + 1 }
return false }
fn mir_v6_reachability(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(__s0_Buffer(MirV6ReachFact), __s0_Error) { var reach = try __s0_buffer_new(MirV6ReachFact, d)
let bcount = mir_vindex_block_count(indexes, function)
var from: U64 = 1
while from <= bcount { var queue = try mir_v6_successors(d, store, indexes, function, from, try __s0_buffer_new(U64, d))
var q: U64 = 0
while q < __s0_buffer_len(U64, queue) { let to = __s0_buffer_get(U64, queue, q)
if !mir_v6_reach_has(reach, from, to) { reach = try __s0_buffer_append(MirV6ReachFact, d, reach, MirV6ReachFact(from: from, to: to))
queue = try mir_v6_successors(d, store, indexes, function, to, queue) }
q = q + 1 }
from = from + 1 }
return Ok(reach) }
fn mir_v6_local_provenance(analysis: MirV6Analysis, function: U64, value: U64) -> Bool { var at = mir_v6_fact_start(analysis, function, value)
let end = mir_v6_fact_end(analysis, function, value)
while at < end { let x = mir_v6_fact_at(analysis, at)
if (x.kind == mir_v6_fact_dep() && x.a != 0) || (x.kind == mir_v6_fact_root() && x.b != 0) { return true }
at = at + 1 }
return false }
fn mir_v6_stable_loop_store(store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, function: U64, value: U64, place: U64) -> Bool { if mir_v6_place_deref(store, place) { return false }
var e = mir_v6_effect_start(analysis, function)
let eend = mir_v6_effect_end(analysis, function)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { return false }
e = e + 1 }
var local_root = false
var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() && fact.a != 0 { return false }
if fact.kind == mir_v6_fact_root() && fact.b != 0 { local_root = true
var parameter_domain = false
var h = mir_v6_fact_start(analysis, function, fact.a)
let hend = mir_v6_fact_end(analysis, function, fact.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() && owner.a != 0 { return false }
if owner.kind == mir_v6_fact_param() { let vi = mir_vindex_value(indexes, function, fact.a)
if vi != 0 && mir_vtype_kind(store, __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type) == mir_type_kind_domain_handle() { parameter_domain = true } }
h = h + 1 }
if !parameter_domain { return false } }
f = f + 1 }
return local_root }
fn mir_v6_escapes_local(analysis: MirV6Analysis, function: U64, value: U64) -> Bool { var r = mir_v6_fact_start(analysis, function, value)
let rend = mir_v6_fact_end(analysis, function, value)
while r < rend { let root = mir_v6_fact_at(analysis, r)
if root.kind == mir_v6_fact_root() && root.b != 0 { var h = mir_v6_fact_start(analysis, function, root.a)
let hend = mir_v6_fact_end(analysis, function, root.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() && owner.a != 0 { return true }
h = h + 1 } }
r = r + 1 }
return false }
fn mir_v6_bad(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, block: U64, instruction: U64, terminator: U64, operand: U64, reference: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var type_id: U64 = 0
return mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), kind, function, block, instruction, terminator, operand, type_id, 0, 0, 0, reference)) }
fn mir_v6_bad_has(out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, instruction: U64, reference: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirVerifyDiagRec, out) { let x = __s0_buffer_get(MirVerifyDiagRec, out, at)
if x.phase == mir_verify_phase_domains() && x.kind == kind && x.function == function && x.instruction == instruction && x.reference == reference { return true }
at = at + 1 }
return false }
fn mir_v6_check_cleanup(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, block: U64, iid: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { var branch = state0
var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var oi: U64 = 0
var arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, oi)
var invalid = false
while arg != 0 { if !invalid && mir_v6_value_invalid(analysis, branch, function, arg) { invalid = true
if !mir_v6_bad_has(out, mir_vdiag_invalid_resource_use(), function, iid, arg) { let operand_id = mir_v5_operand(store, indexes, mir_operand_instruction(), push_id, 0, oi)
out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_use(), function, block, iid, 0, operand_id, arg) } }
oi = oi + 1
arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, oi) }
var e = mir_v6_effect_start(analysis, push.target)
let eend = mir_v6_effect_end(analysis, push.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() { let domain = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
if mir_v6_domain_dead(analysis, branch, function, domain) && !mir_v6_bad_has(out, mir_vdiag_dead_domain(), function, iid, domain) { out = try mir_v6_bad(d, out, mir_vdiag_dead_domain(), function, block, iid, 0, 0, domain) } }
e = e + 1 }
branch = try mir_v6_apply_cleanup_entry(d, store, indexes, cfg, dom, analysis, branch, function, node.entry) } }
active = node.parent } }
si = si + 1 }
return Ok(out) }
fn mir_v6_check_loops(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, function: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
let reach = try mir_v6_reachability(d, store, indexes, function)
let pcount = mir_vindex_param_count(indexes, function)
var pi: U64 = 0
while pi < pcount {
    let pid = mir_vindex_param(indexes, function, pi)
    let p = __s0_buffer_get(MirParamRec, store.params, pid - 1)
    if p.kind == mir_param_block() {
        // Incoming edge operands of this block parameter, enumerated through
        // the per-owner operand indexes in storage order.
        let bcount = mir_vindex_block_count(indexes, function)
        var b: U64 = 1
        while b <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, b)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, b, ii)
                let total = mir_vindex_op_instr_count(indexes, iid)
                var oi: U64 = 0
                while oi < total {
                    let oid = mir_vindex_op_instr(indexes, iid, oi)
                    let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
                    if o.kind == mir_operand_checked_edge_arg() && o.target == p.block && o.ordinal == p.ordinal { let source = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1).block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } }
                    oi = oi + 1
                }
                ii = ii + 1
            }
            let term_id = mir_vindex_term(indexes, function, b)
            if term_id != 0 {
                let total = mir_vindex_op_term_count(indexes, term_id)
                var oi: U64 = 0
                while oi < total {
                    let oid = mir_vindex_op_term(indexes, term_id, oi)
                    let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
                    if o.kind == mir_operand_terminator_arg() && o.target == p.block && o.ordinal == p.ordinal { let source = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1).block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } }
                    oi = oi + 1
                }
                var ci: U64 = 0
                while ci < total {
                    let cid = mir_vindex_op_term(indexes, term_id, ci)
                    let c = __s0_buffer_get(MirOperandRec, store.operands, cid - 1)
                    if c.kind == mir_operand_switch_case() {
                        let atotal = mir_vindex_op_case_count(indexes, cid)
                        var ai: U64 = 0
                        while ai < atotal {
                            let aid = mir_vindex_op_case(indexes, cid, ai)
                            let a = __s0_buffer_get(MirOperandRec, store.operands, aid - 1)
                            if a.target == p.block && a.ordinal == p.ordinal { let source = __s0_buffer_get(MirTermRec, store.terminators, __s0_buffer_get(MirOperandRec, store.operands, cid - 1).owner - 1).block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, a.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, aid, p.value) } }
                            ai = ai + 1
                        }
                    }
                    ci = ci + 1
                }
            }
            b = b + 1
        }
    }
    pi = pi + 1
}
// Loop-backedge stores, in instruction storage order.
let bcount = mir_vindex_block_count(indexes, function)
var b2: U64 = 1
while b2 <= bcount {
    let icount = mir_vindex_instr_count(indexes, function, b2)
    var ii: U64 = 0
    while ii < icount {
        let iid = mir_vindex_instr(indexes, function, b2, ii)
        let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
        if x.op == mir_op_store() && mir_v6_reach_has(reach, x.block, x.block) && mir_v6_local_provenance(analysis, function, x.a) && !mir_v6_stable_loop_store(store, indexes, analysis, function, x.a, x.place) { out = try mir_v6_bad(d, out, mir_vdiag_loop_store_resource(), function, x.block, iid, 0, x.place, x.a) }
        ii = ii + 1
    }
    b2 = b2 + 1
}
return Ok(out) }
fn mir_vphase6_with(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec), cleanup: MirV7Analysis, analysis: MirV6Analysis) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = initial
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { out = try mir_v6_check_loops(d, store, indexes, analysis, function, out)
// The point CFG and idom tree are built once per function; reset invalidation
// consults them per mark instead of running an entry BFS per call.
let cfg = try mir_vp4_cfg_build(d, store, indexes, function)
let dom = try mir_vp4_dom_build(d, cfg)
let entries = try mir_v6_solve_states(d, store, indexes, analysis, cleanup, cfg, dom, function)
let reachable = try mir_vreachable(d, store, indexes, function)
let uses = try mir_vp4_collect_uses(d, store, indexes, function)
let bcount = mir_vindex_block_count(indexes, function)
var block: U64 = 1
while block <= bcount { if mir_vseen_block(reachable, block) { var state = try mir_v6_entry_state(d, entries, block)
let icount = mir_vindex_instr_count(indexes, function, block)
var ordinal: U64 = 0
while ordinal < icount {
    let iid = mir_vindex_instr(indexes, function, block, ordinal)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op == mir_op_store() && mir_v6_place_deref(store, x.place) { let value_type = mir_v5_value_type(store, indexes, function, x.a)
if try mir_v6_type_local_store(d, store, indexes, value_type) { out = try mir_v6_bad(d, out, mir_vdiag_lifetime_deref_store(), function, block, iid, 0, x.place, x.a) } }
    if x.op == mir_op_cleanup_scope_run() { out = try mir_v6_check_cleanup(d, store, indexes, cfg, dom, analysis, cleanup, state, function, block, iid, out) }
    var invalid = false
    var ui: U64 = 0
    while ui < __s0_buffer_len(MirVP4Use, uses) { let use = __s0_buffer_get(MirVP4Use, uses, ui)
if !invalid && use.instruction == iid && mir_v6_value_invalid(analysis, state, function, use.value) { invalid = true
out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_use(), function, block, iid, 0, use.operand, use.value) }
ui = ui + 1 }
    if (x.op == mir_op_domain_destroy() || x.op == mir_op_domain_reset()) && mir_v6_domain_dead(analysis, state, function, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_dead_domain(), function, block, iid, 0, 0, x.a) }
    if x.op == mir_op_domain_reset() { let marked = mir_v6_mark_domain(store, indexes, function, x.b)
if marked == 0 || !mir_v6_domains_alias(analysis, function, marked, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_mark_domain_mismatch(), function, block, iid, 0, 0, x.b) } }
    state = try mir_v6_apply(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x)
    ordinal = ordinal + 1
}
let term_id = mir_vindex_term(indexes, function, block)
if term_id != 0 {
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { if mir_v6_value_invalid(analysis, state, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_exit(), function, block, 0, term_id, 0, t.value) }
if mir_v6_escapes_local(analysis, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_local_domain_escape(), function, block, 0, term_id, 0, t.value) } }
} }
block = block + 1 }
function = function + 1 }
return Ok(out) }
fn mir_vphase6(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
let cleanup = try mir_v7_analyze(d, store, indexes, try __s0_buffer_new(MirVerifyDiagRec, d))
let analysis = try mir_v6_compute(d, store, indexes, cleanup)
return mir_vphase6_with(d, store, indexes, initial, cleanup, analysis) }
