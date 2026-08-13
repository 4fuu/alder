// Phase 6 ports the Go verifier's finite domain/provenance and resource
// lattices over flat MIR IDs. Facts are append-only sets scanned in stable
// function/value/declaration order; no invalid input is normalized or repaired.
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

fn mir_v6_fact_has(facts: __s0_Buffer(MirV6Fact), item: MirV6Fact) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6Fact, facts) { let x = __s0_buffer_get(MirV6Fact, facts, at)
if x.function == item.function && x.value == item.value && x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
at = at + 1 }
return false }
fn mir_v6_fact_add(d: Domain, facts: __s0_Buffer(MirV6Fact), item: MirV6Fact) -> Result(__s0_Buffer(MirV6Fact), __s0_Error) { if mir_v6_fact_has(facts, item) { return Ok(facts) }
return __s0_buffer_append(MirV6Fact, d, facts, item) }
fn mir_v6_effect_has(effects: __s0_Buffer(MirV6Effect), function: U64, parameter: U64, kind: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6Effect, effects) { let x = __s0_buffer_get(MirV6Effect, effects, at)
if x.function == function && x.parameter == parameter && x.kind == kind { return true }
at = at + 1 }
return false }
fn mir_v6_effect_add(d: Domain, effects: __s0_Buffer(MirV6Effect), function: U64, parameter: U64, kind: U64) -> Result(__s0_Buffer(MirV6Effect), __s0_Error) { if mir_v6_effect_has(effects, function, parameter, kind) { return Ok(effects) }
return __s0_buffer_append(MirV6Effect, d, effects, MirV6Effect(function: function, parameter: parameter, kind: kind)) }
fn mir_v6_merge_value(d: Domain, facts0: __s0_Buffer(MirV6Fact), function: U64, target: U64, source: U64) -> Result(__s0_Buffer(MirV6Fact), __s0_Error) { var facts = facts0
var at: U64 = 0
while at < __s0_buffer_len(MirV6Fact, facts0) { let x = __s0_buffer_get(MirV6Fact, facts0, at)
if x.function == function && x.value == source { facts = try mir_v6_fact_add(d, facts, MirV6Fact(function: function, value: target, kind: x.kind, a: x.a, b: x.b, c: x.c)) }
at = at + 1 }
return Ok(facts) }

fn mir_v6_type_contains(d: Domain, store: MirStore, root: U64, wanted: U64) -> Result(Bool, __s0_Error) { var work = try __s0_buffer_new(U64, d)
var seen = try __s0_buffer_new(U64, d)
work = try __s0_buffer_append(U64, d, work, root)
var at: U64 = 0
while at < __s0_buffer_len(U64, work) { let id = __s0_buffer_get(U64, work, at)
var known = false
var s: U64 = 0
while s < __s0_buffer_len(U64, seen) { if __s0_buffer_get(U64, seen, s) == id { known = true }
s = s + 1 }
if !known && mir_vtype_exists(store, id) { if mir_vtype_kind(store, id) == wanted { return Ok(true) }
seen = try __s0_buffer_append(U64, d, seen, id)
work = try mir_vappend_type_children(d, store, work, id) }
at = at + 1 }
return Ok(false) }
fn mir_v6_type_reference(d: Domain, store: MirStore, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_contains(d, store, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if try mir_v6_type_contains(d, store, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if try mir_v6_type_contains(d, store, type_id, mir_type_kind_slice()) { return Ok(true) }
return mir_v6_type_contains(d, store, type_id, mir_type_kind_table()) }
fn mir_v6_type_local_store(d: Domain, store: MirStore, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_reference(d, store, type_id) { return Ok(true) }
if try mir_v6_type_contains(d, store, type_id, mir_type_kind_domain_handle()) { return Ok(true) }
return mir_v6_type_contains(d, store, type_id, mir_type_kind_domain_mark()) }

fn mir_v6_instruction_for_value(store: MirStore, value: MirValueRec) -> U64 { if value.def_kind != mir_value_def_instruction() { return 0 }
return mir_vp4_instruction_at(store, value.function, value.block, value.item - 1) }
fn mir_v6_function_param_ordinal(store: MirStore, function: U64, value: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, at)
if p.function == function && p.kind == mir_param_function() && p.value == value { return p.ordinal + 1 }
at = at + 1 }
return 0 }
fn mir_v6_operand_value(store: MirStore, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 { let oi = mir_v5_operand(store, kind, owner, edge, ordinal)
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

fn mir_v6_transfer_value(d: Domain, store: MirStore, analysis0: MirV6Analysis, function: U64, value_id: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
let vi = mir_vvalue_index(store, function, value_id)
let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if value.def_kind == mir_value_def_function_param() { let parameter = mir_v6_function_param_ordinal(store, function, value_id)
analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_param(), a: parameter, b: 0, c: 0))
if try mir_v6_type_reference(d, store, value.value_type) { var pi: U64 = 0
while pi < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, pi)
if p.function == function && p.kind == mir_param_function() && mir_vtype_kind(store, p.param_type) == mir_type_kind_domain_handle() { analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: p.ordinal + 1, c: 0)) }
pi = pi + 1 }
analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: value_id, b: 0, c: parameter)) }
if mir_vtype_kind(store, value.value_type) == mir_type_kind_domain_handle() { analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: parameter, c: 0)) }
return Ok(analysis) }
if value.def_kind == mir_value_def_block_param() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
if o.target == value.block && o.ordinal + 1 == value.item && (o.kind == mir_operand_checked_edge_arg() || o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case_arg()) { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, o.value) }
oi = oi + 1 }
return Ok(analysis) }
if value.def_kind == mir_value_def_switch_case() { var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && t.block == value.block { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, t.value) }
ti = ti + 1 }
return Ok(analysis) }
let iid = mir_v6_instruction_for_value(store, value)
if iid == 0 { return Ok(analysis) }
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_domain_create() { var at: U64 = 0
while at < __s0_buffer_len(MirV6Fact, analysis.facts) { let f = __s0_buffer_get(MirV6Fact, analysis.facts, at)
if f.function == function && f.value == x.a && (f.kind == mir_v6_fact_dep() || f.kind == mir_v6_fact_parent()) { analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_parent(), a: f.a, b: f.b, c: f.c)) }
at = at + 1 }
analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: x.block, b: x.ordinal + 1, c: 0)) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, x.a)
if x.op == mir_op_copy_to_domain() { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, x.b) }
analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: x.a, b: x.block, c: x.ordinal + 1)) }
if x.op == mir_op_load() { let p = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
if p.kind == mir_place_deref() { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, p.deref_value) }
var at: U64 = 0
while at < __s0_buffer_len(MirInstrRec, store.instructions) { let s = __s0_buffer_get(MirInstrRec, store.instructions, at)
if s.function == function && s.op == mir_op_store() && mir_v6_places_alias(store, x.place, s.place) { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, s.a) }
at = at + 1 } }
if x.op == mir_op_aggregate_construct() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
if o.kind == mir_operand_aggregate_field() && o.owner == iid { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, o.value) }
oi = oi + 1 } }
if x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, x.a) }
if x.op == mir_op_call() { var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == x.target && (effect.kind == mir_v6_effect_result_from() || effect.kind == mir_v6_effect_result_alloc()) { let arg = mir_v6_operand_value(store, mir_operand_instruction(), iid, 0, effect.parameter - 1)
analysis.facts = try mir_v6_merge_value(d, analysis.facts, function, value_id, arg)
if effect.kind == mir_v6_effect_result_alloc() { analysis.facts = try mir_v6_fact_add(d, analysis.facts, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: arg, b: x.block, c: x.ordinal + 1)) } }
e = e + 1 } }
return Ok(analysis) }

fn mir_v6_add_param_effects(d: Domain, facts: __s0_Buffer(MirV6Fact), effects0: __s0_Buffer(MirV6Effect), function: U64, value: U64, kind: U64) -> Result(__s0_Buffer(MirV6Effect), __s0_Error) { var effects = effects0
var at: U64 = 0
while at < __s0_buffer_len(MirV6Fact, facts) { let f = __s0_buffer_get(MirV6Fact, facts, at)
if f.function == function && f.value == value && f.kind == mir_v6_fact_param() { effects = try mir_v6_effect_add(d, effects, function, f.a, kind) }
at = at + 1 }
return Ok(effects) }
fn mir_v6_add_cleanup_effects(d: Domain, store: MirStore, cleanup: MirV7Analysis, analysis0: MirV6Analysis, function: U64, active0: U64) -> Result(MirV6Analysis, __s0_Error) { var analysis = analysis0
var active = active0
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vvalue_index(store, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == push.target && (effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset()) { let arg = mir_v6_operand_value(store, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
analysis.effects = try mir_v6_add_param_effects(d, analysis.facts, analysis.effects, function, arg, effect.kind) }
e = e + 1 } } }
active = node.parent }
return Ok(analysis) }

fn mir_v6_compute(d: Domain, store: MirStore, cleanup: MirV7Analysis) -> Result(MirV6Analysis, __s0_Error) { var analysis = MirV6Analysis(facts: try __s0_buffer_new(MirV6Fact, d), effects: try __s0_buffer_new(MirV6Effect, d))
var changed = true
while changed { let before_facts = __s0_buffer_len(MirV6Fact, analysis.facts)
let before_effects = __s0_buffer_len(MirV6Effect, analysis.effects)
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { var value: U64 = 1
while mir_vvalue_index(store, function, value) != 0 { analysis = try mir_v6_transfer_value(d, store, analysis, function, value)
value = value + 1 }
var ii: U64 = 0
while ii < __s0_buffer_len(MirInstrRec, store.instructions) { let x = __s0_buffer_get(MirInstrRec, store.instructions, ii)
if x.function == function { if x.op == mir_op_domain_destroy() { analysis.effects = try mir_v6_add_param_effects(d, analysis.facts, analysis.effects, function, x.a, mir_v6_effect_destroy()) }
if x.op == mir_op_domain_reset() { analysis.effects = try mir_v6_add_param_effects(d, analysis.facts, analysis.effects, function, x.a, mir_v6_effect_reset()) }
if x.op == mir_op_call() { var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == x.target && (effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset()) { let arg = mir_v6_operand_value(store, mir_operand_instruction(), ii + 1, 0, effect.parameter - 1)
analysis.effects = try mir_v6_add_param_effects(d, analysis.facts, analysis.effects, function, arg, effect.kind) }
e = e + 1 } }
if x.op == mir_op_cleanup_scope_run() { var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == ii + 1 { analysis = try mir_v6_add_cleanup_effects(d, store, cleanup, analysis, function, set.active) }
si = si + 1 } } }
ii = ii + 1 }
var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { var f: U64 = 0
while f < __s0_buffer_len(MirV6Fact, analysis.facts) { let fact = __s0_buffer_get(MirV6Fact, analysis.facts, f)
if fact.function == function && fact.value == t.value && fact.kind == mir_v6_fact_param() { analysis.effects = try mir_v6_effect_add(d, analysis.effects, function, fact.a, mir_v6_effect_result_from()) }
if fact.function == function && fact.value == t.value && fact.kind == mir_v6_fact_root() && fact.b != 0 { var h: U64 = 0
while h < __s0_buffer_len(MirV6Fact, analysis.facts) { let owner = __s0_buffer_get(MirV6Fact, analysis.facts, h)
if owner.function == function && owner.value == fact.a && owner.kind == mir_v6_fact_param() { analysis.effects = try mir_v6_effect_add(d, analysis.effects, function, owner.a, mir_v6_effect_result_alloc()) }
h = h + 1 } }
f = f + 1 } }
ti = ti + 1 }
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
fn mir_v6_value_invalid(facts: __s0_Buffer(MirV6Fact), state: __s0_Buffer(MirV6StateFact), function: U64, value: U64) -> Bool { var s: U64 = 0
while s < __s0_buffer_len(MirV6StateFact, state) { let dead = __s0_buffer_get(MirV6StateFact, state, s)
if dead.kind == mir_v6_state_mark() && dead.a == value { return true }
var f: U64 = 0
while f < __s0_buffer_len(MirV6Fact, facts) { let fact = __s0_buffer_get(MirV6Fact, facts, f)
if fact.function == function && fact.value == value { if (fact.kind == mir_v6_fact_dep() || fact.kind == mir_v6_fact_parent()) && dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
if fact.kind == mir_v6_fact_root() && dead.kind == mir_v6_state_root() && fact.a == dead.a && fact.b == dead.b && fact.c == dead.c { return true } }
f = f + 1 }
s = s + 1 }
return false }
fn mir_v6_domain_dead(facts: __s0_Buffer(MirV6Fact), state: __s0_Buffer(MirV6StateFact), function: U64, value: U64) -> Bool { var f: U64 = 0
while f < __s0_buffer_len(MirV6Fact, facts) { let fact = __s0_buffer_get(MirV6Fact, facts, f)
if fact.function == function && fact.value == value && fact.kind == mir_v6_fact_dep() { var s: U64 = 0
while s < __s0_buffer_len(MirV6StateFact, state) { let dead = __s0_buffer_get(MirV6StateFact, state, s)
if dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
s = s + 1 } }
f = f + 1 }
return false }
fn mir_v6_domains_alias(facts: __s0_Buffer(MirV6Fact), function: U64, a: U64, b: U64) -> Bool { var x: U64 = 0
while x < __s0_buffer_len(MirV6Fact, facts) { let left = __s0_buffer_get(MirV6Fact, facts, x)
if left.function == function && left.value == a && left.kind == mir_v6_fact_dep() { var y: U64 = 0
while y < __s0_buffer_len(MirV6Fact, facts) { let right = __s0_buffer_get(MirV6Fact, facts, y)
if right.function == function && right.value == b && right.kind == mir_v6_fact_dep() && (left.a == right.a && left.b == right.b || left.a == 0 && right.a == 0) { return true }
y = y + 1 } }
x = x + 1 }
return false }
fn mir_v6_root_in_domain(facts: __s0_Buffer(MirV6Fact), function: U64, root: MirV6Fact, domain: U64) -> Bool { var h: U64 = 0
while h < __s0_buffer_len(MirV6Fact, facts) { let owner = __s0_buffer_get(MirV6Fact, facts, h)
if owner.function == function && owner.value == root.a && (owner.kind == mir_v6_fact_dep() || owner.kind == mir_v6_fact_parent()) { var d: U64 = 0
while d < __s0_buffer_len(MirV6Fact, facts) { let candidate = __s0_buffer_get(MirV6Fact, facts, d)
if candidate.function == function && candidate.value == domain && candidate.kind == mir_v6_fact_dep() && (owner.a == candidate.a && owner.b == candidate.b || owner.a == 0 && candidate.a == 0) { return true }
d = d + 1 } }
h = h + 1 }
return false }
fn mir_v6_mark_domain(store: MirStore, function: U64, mark: U64) -> U64 { let vi = mir_vvalue_index(store, function, mark)
if vi == 0 { return 0 }
let iid = mir_v6_instruction_for_value(store, __s0_buffer_get(MirValueRec, store.values, vi - 1))
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
fn mir_v6_root_after_mark(d: Domain, store: MirStore, function: U64, root: MirV6Fact, mark: U64) -> Result(Bool, __s0_Error) {
    if root.b == 0 { return Ok(true) }
    let mi = mir_vvalue_index(store, function, mark)
    if mi == 0 { return Ok(true) }
    let mv = __s0_buffer_get(MirValueRec, store.values, mi - 1)
    return mir_vphase4_point_dominates(d, store, function, mv.def_kind, mv.block, mv.item, root.b, root.c - 1)
}
fn mir_v6_invalidate(d: Domain, store: MirStore, facts: __s0_Buffer(MirV6Fact), state0: __s0_Buffer(MirV6StateFact), function: U64, domain: U64, reset: Bool, mark: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) {
    var state = state0
    if !reset { var f: U64 = 0
while f < __s0_buffer_len(MirV6Fact, facts) { let fact = __s0_buffer_get(MirV6Fact, facts, f)
if fact.function == function && fact.value == domain && fact.kind == mir_v6_fact_dep() { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_dead(), a: fact.a, b: fact.b, c: 0)) }
f = f + 1 } }
    var r: U64 = 0
    while r < __s0_buffer_len(MirV6Fact, facts) { let root = __s0_buffer_get(MirV6Fact, facts, r)
if root.function == function && root.kind == mir_v6_fact_root() && mir_v6_root_in_domain(facts, function, root, domain) { if !reset { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_root(), a: root.a, b: root.b, c: root.c)) } else { if try mir_v6_root_after_mark(d, store, function, root, mark) { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_root(), a: root.a, b: root.b, c: root.c)) } } }
r = r + 1 }
    var vi: U64 = 1
    while mir_vvalue_index(store, function, vi) != 0 { let md = mir_v6_mark_domain(store, function, vi)
if md != 0 && mir_v6_domains_alias(facts, function, md, domain) { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_mark(), a: vi, b: 0, c: 0)) }
vi = vi + 1 }
    return Ok(state)
}
fn mir_v6_apply_cleanup_entry(d: Domain, store: MirStore, analysis: MirV6Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, entry: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = state0
let vi = mir_vvalue_index(store, function, entry)
if vi == 0 { return Ok(state) }
let push_id = mir_v6_instruction_for_value(store, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id == 0 { return Ok(state) }
let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == push.target && (effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset()) { let arg = mir_v6_operand_value(store, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, analysis.facts, state, function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 }
return Ok(state) }
fn mir_v6_apply_cleanup(d: Domain, store: MirStore, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), iid: U64, function: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var merged = try __s0_buffer_new(MirV6StateFact, d)
var found = false
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { found = true
var branch = state0
var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
branch = try mir_v6_apply_cleanup_entry(d, store, analysis, branch, function, node.entry)
active = node.parent }
var bi: U64 = 0
while bi < __s0_buffer_len(MirV6StateFact, branch) { merged = try mir_v6_state_add(d, merged, __s0_buffer_get(MirV6StateFact, branch, bi))
bi = bi + 1 } }
si = si + 1 }
if found { return Ok(merged) }
return Ok(state0) }
fn mir_v6_apply(d: Domain, store: MirStore, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), iid: U64, x: MirInstrRec) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = state0
if x.op == mir_op_domain_create() { state = try mir_v6_clear_dead(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_mark() { state = try mir_v6_clear_mark(d, state, x.result) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_call() { state = try mir_v6_clear_produced(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_destroy() { state = try mir_v6_invalidate(d, store, analysis.facts, state, x.function, x.a, false, 0) }
if x.op == mir_op_domain_reset() { state = try mir_v6_invalidate(d, store, analysis.facts, state, x.function, x.a, true, x.b) }
if x.op == mir_op_call() { var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == x.target && (effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset()) { let arg = mir_v6_operand_value(store, mir_operand_instruction(), iid, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, analysis.facts, state, x.function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 } }
if x.op == mir_op_cleanup_scope_run() { state = try mir_v6_apply_cleanup(d, store, analysis, cleanup, state, iid, x.function) }
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
fn mir_v6_successors(d: Domain, store: MirStore, function: U64, block: U64, out0: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) { var out = out0
var ii: U64 = 0
while ii < __s0_buffer_len(MirInstrRec, store.instructions) { let x = __s0_buffer_get(MirInstrRec, store.instructions, ii)
if x.function == function && x.block == block && mir_vop_checked(x.op) { out = try __s0_buffer_append(U64, d, out, x.target) }
ii = ii + 1 }
var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && t.block == block { if t.kind == mir_term_jump() { out = try __s0_buffer_append(U64, d, out, t.target) }
if t.kind == mir_term_branch() { out = try __s0_buffer_append(U64, d, out, t.then_block)
out = try __s0_buffer_append(U64, d, out, t.else_block) }
if t.kind == mir_term_switch() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let c = __s0_buffer_get(MirOperandRec, store.operands, oi)
if c.kind == mir_operand_switch_case() && c.owner == ti + 1 { out = try __s0_buffer_append(U64, d, out, c.target) }
oi = oi + 1 } } }
ti = ti + 1 }
return Ok(out) }
fn mir_v6_solve_states(d: Domain, store: MirStore, analysis: MirV6Analysis, cleanup: MirV7Analysis, function: U64) -> Result(__s0_Buffer(MirV6EntryFact), __s0_Error) { var entries = try __s0_buffer_new(MirV6EntryFact, d)
let reachable = try mir_vreachable(d, store, function)
var changed = true
while changed { let before = __s0_buffer_len(MirV6EntryFact, entries)
var block: U64 = 1
while mir_vblock_index(store, function, block) != 0 { if mir_vseen_block(reachable, block) { var state = try mir_v6_entry_state(d, entries, block)
var ordinal: U64 = 0
while ordinal < mir_vp4_instruction_count(store, function, block) { let iid = mir_vp4_instruction_at(store, function, block, ordinal)
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if mir_vop_checked(x.op) { entries = try mir_v6_entry_merge(d, entries, x.target, state) }
state = try mir_v6_apply(d, store, analysis, cleanup, state, iid, x)
ordinal = ordinal + 1 }
let successors = try mir_v6_successors(d, store, function, block, try __s0_buffer_new(U64, d))
var si: U64 = 0
while si < __s0_buffer_len(U64, successors) { let target = __s0_buffer_get(U64, successors, si)
// Checked successors already received the pre-instruction state above.
var checked = false
var xi: U64 = 0
while xi < __s0_buffer_len(MirInstrRec, store.instructions) { let q = __s0_buffer_get(MirInstrRec, store.instructions, xi)
if q.function == function && q.block == block && mir_vop_checked(q.op) && q.target == target { checked = true }
xi = xi + 1 }
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
fn mir_v6_reachability(d: Domain, store: MirStore, function: U64) -> Result(__s0_Buffer(MirV6ReachFact), __s0_Error) { var reach = try __s0_buffer_new(MirV6ReachFact, d)
var from: U64 = 1
while mir_vblock_index(store, function, from) != 0 { var queue = try mir_v6_successors(d, store, function, from, try __s0_buffer_new(U64, d))
var q: U64 = 0
while q < __s0_buffer_len(U64, queue) { let to = __s0_buffer_get(U64, queue, q)
if !mir_v6_reach_has(reach, from, to) { reach = try __s0_buffer_append(MirV6ReachFact, d, reach, MirV6ReachFact(from: from, to: to))
queue = try mir_v6_successors(d, store, function, to, queue) }
q = q + 1 }
from = from + 1 }
return Ok(reach) }
fn mir_v6_local_provenance(facts: __s0_Buffer(MirV6Fact), function: U64, value: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6Fact, facts) { let x = __s0_buffer_get(MirV6Fact, facts, at)
if x.function == function && x.value == value && ((x.kind == mir_v6_fact_dep() && x.a != 0) || (x.kind == mir_v6_fact_root() && x.b != 0)) { return true }
at = at + 1 }
return false }
fn mir_v6_stable_loop_store(store: MirStore, analysis: MirV6Analysis, function: U64, value: U64, place: U64) -> Bool { if mir_v6_place_deref(store, place) { return false }
var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == function && (effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset()) { return false }
e = e + 1 }
var local_root = false
var f: U64 = 0
while f < __s0_buffer_len(MirV6Fact, analysis.facts) { let fact = __s0_buffer_get(MirV6Fact, analysis.facts, f)
if fact.function == function && fact.value == value { if fact.kind == mir_v6_fact_dep() && fact.a != 0 { return false }
if fact.kind == mir_v6_fact_root() && fact.b != 0 { local_root = true
var parameter_domain = false
var h: U64 = 0
while h < __s0_buffer_len(MirV6Fact, analysis.facts) { let owner = __s0_buffer_get(MirV6Fact, analysis.facts, h)
if owner.function == function && owner.value == fact.a { if owner.kind == mir_v6_fact_dep() && owner.a != 0 { return false }
if owner.kind == mir_v6_fact_param() { let vi = mir_vvalue_index(store, function, fact.a)
if vi != 0 && mir_vtype_kind(store, __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type) == mir_type_kind_domain_handle() { parameter_domain = true } } }
h = h + 1 }
if !parameter_domain { return false } } }
f = f + 1 }
return local_root }
fn mir_v6_escapes_local(facts: __s0_Buffer(MirV6Fact), function: U64, value: U64) -> Bool { var r: U64 = 0
while r < __s0_buffer_len(MirV6Fact, facts) { let root = __s0_buffer_get(MirV6Fact, facts, r)
if root.function == function && root.value == value && root.kind == mir_v6_fact_root() && root.b != 0 { var h: U64 = 0
while h < __s0_buffer_len(MirV6Fact, facts) { let owner = __s0_buffer_get(MirV6Fact, facts, h)
if owner.function == function && owner.value == root.a && owner.kind == mir_v6_fact_dep() && owner.a != 0 { return true }
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
fn mir_v6_check_cleanup(d: Domain, store: MirStore, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, block: U64, iid: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { var branch = state0
var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vvalue_index(store, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var oi: U64 = 0
var arg = mir_v6_operand_value(store, mir_operand_instruction(), push_id, 0, oi)
var invalid = false
while arg != 0 { if !invalid && mir_v6_value_invalid(analysis.facts, branch, function, arg) { invalid = true
if !mir_v6_bad_has(out, mir_vdiag_invalid_resource_use(), function, iid, arg) { let operand_id = mir_v5_operand(store, mir_operand_instruction(), push_id, 0, oi)
out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_use(), function, block, iid, 0, operand_id, arg) } }
oi = oi + 1
arg = mir_v6_operand_value(store, mir_operand_instruction(), push_id, 0, oi) }
var e: U64 = 0
while e < __s0_buffer_len(MirV6Effect, analysis.effects) { let effect = __s0_buffer_get(MirV6Effect, analysis.effects, e)
if effect.function == push.target && effect.kind == mir_v6_effect_destroy() { let domain = mir_v6_operand_value(store, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
if mir_v6_domain_dead(analysis.facts, branch, function, domain) && !mir_v6_bad_has(out, mir_vdiag_dead_domain(), function, iid, domain) { out = try mir_v6_bad(d, out, mir_vdiag_dead_domain(), function, block, iid, 0, 0, domain) } }
e = e + 1 }
branch = try mir_v6_apply_cleanup_entry(d, store, analysis, branch, function, node.entry) } }
active = node.parent } }
si = si + 1 }
return Ok(out) }

fn mir_v6_check_loops(d: Domain, store: MirStore, analysis: MirV6Analysis, function: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
let reach = try mir_v6_reachability(d, store, function)
var pi: U64 = 0
while pi < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, pi)
if p.function == function && p.kind == mir_param_block() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
if o.target == p.block && o.ordinal == p.ordinal && (o.kind == mir_operand_checked_edge_arg() || o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case_arg()) { var source: U64 = 0
if o.kind == mir_operand_checked_edge_arg() { source = __s0_buffer_get(MirInstrRec, store.instructions, o.owner - 1).block }
if o.kind == mir_operand_terminator_arg() { source = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1).block }
if o.kind == mir_operand_switch_case_arg() { let c = __s0_buffer_get(MirOperandRec, store.operands, o.owner - 1)
source = __s0_buffer_get(MirTermRec, store.terminators, c.owner - 1).block }
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis.facts, function, o.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oi + 1, p.value) } }
oi = oi + 1 } }
pi = pi + 1 }
var ii: U64 = 0
while ii < __s0_buffer_len(MirInstrRec, store.instructions) { let x = __s0_buffer_get(MirInstrRec, store.instructions, ii)
if x.function == function && x.op == mir_op_store() && mir_v6_reach_has(reach, x.block, x.block) && mir_v6_local_provenance(analysis.facts, function, x.a) && !mir_v6_stable_loop_store(store, analysis, function, x.a, x.place) { out = try mir_v6_bad(d, out, mir_vdiag_loop_store_resource(), function, x.block, ii + 1, 0, x.place, x.a) }
ii = ii + 1 }
return Ok(out) }

fn mir_vphase6(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = initial
let cleanup = try mir_v7_analyze(d, store, try __s0_buffer_new(MirVerifyDiagRec, d))
let analysis = try mir_v6_compute(d, store, cleanup)
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { out = try mir_v6_check_loops(d, store, analysis, function, out)
let entries = try mir_v6_solve_states(d, store, analysis, cleanup, function)
let reachable = try mir_vreachable(d, store, function)
let uses = try mir_vp4_collect_uses(d, store, function)
var block: U64 = 1
while mir_vblock_index(store, function, block) != 0 { if mir_vseen_block(reachable, block) { var state = try mir_v6_entry_state(d, entries, block)
var ordinal: U64 = 0
while ordinal < mir_vp4_instruction_count(store, function, block) { let iid = mir_vp4_instruction_at(store, function, block, ordinal)
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_store() && mir_v6_place_deref(store, x.place) { let value_type = mir_v5_value_type(store, function, x.a)
if try mir_v6_type_local_store(d, store, value_type) { out = try mir_v6_bad(d, out, mir_vdiag_lifetime_deref_store(), function, block, iid, 0, x.place, x.a) } }
if x.op == mir_op_cleanup_scope_run() { out = try mir_v6_check_cleanup(d, store, analysis, cleanup, state, function, block, iid, out) }
var invalid = false
var ui: U64 = 0
while ui < __s0_buffer_len(MirVP4Use, uses) { let use = __s0_buffer_get(MirVP4Use, uses, ui)
if !invalid && use.instruction == iid && mir_v6_value_invalid(analysis.facts, state, function, use.value) { invalid = true
out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_use(), function, block, iid, 0, use.operand, use.value) }
ui = ui + 1 }
if (x.op == mir_op_domain_destroy() || x.op == mir_op_domain_reset()) && mir_v6_domain_dead(analysis.facts, state, function, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_dead_domain(), function, block, iid, 0, 0, x.a) }
if x.op == mir_op_domain_reset() { let marked = mir_v6_mark_domain(store, function, x.b)
if marked == 0 || !mir_v6_domains_alias(analysis.facts, function, marked, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_mark_domain_mismatch(), function, block, iid, 0, 0, x.b) } }
state = try mir_v6_apply(d, store, analysis, cleanup, state, iid, x)
ordinal = ordinal + 1 }
var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && t.block == block && (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { if mir_v6_value_invalid(analysis.facts, state, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_exit(), function, block, 0, ti + 1, 0, t.value) }
if mir_v6_escapes_local(analysis.facts, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_local_domain_escape(), function, block, 0, ti + 1, 0, t.value) } }
ti = ti + 1 } }
block = block + 1 }
function = function + 1 }
return Ok(out) }
