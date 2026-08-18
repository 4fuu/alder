// Phase 8 enforces the lexical access regions created by table lookups.  The
// flat verifier deliberately scans stable IDs instead of constructing pointer
// graphs; V1-V7 have already established every reciprocal and type invariant.
fn mir_v8_diag(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, block: U64, instruction: U64, terminator: U64, reference: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    return mir_vadd(d, out, mir_vdiag(mir_verify_phase_tables(), kind, function, block, instruction, terminator, 0, 0, 0, 0, 0, reference))
}
fn mir_v8_instr_for_value(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let vi = mir_vindex_value(indexes, function, value)
    if vi == 0 { return 0 }
    let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
    if v.def_kind != mir_value_def_instruction() { return 0 }
    return mir_v6_instruction_for_value(store, indexes, v)
}
fn mir_v8_is_view(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Bool {
    let vi = mir_vindex_value(indexes, function, value)
    if vi == 0 { return false }
    let kind = mir_vtype_kind(store, __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type)
    return kind == mir_type_kind_table_view() || kind == mir_type_kind_table_mut_view()
}
fn mir_v8_same_use(a: MirVP4Use, b: MirVP4Use) -> Bool {
    return a.value == b.value && a.block == b.block && a.instruction == b.instruction && a.terminator == b.terminator && a.operand == b.operand && a.switch_case == b.switch_case
}
fn mir_v8_same_table(facts: __s0_Buffer(MirV6Fact), function: U64, a: U64, b: U64) -> Bool {
    var x: U64 = 0
    while x < __s0_buffer_len(MirV6Fact, facts) { let left = __s0_buffer_get(MirV6Fact, facts, x)
        if left.function == function && left.value == a && left.kind == mir_v6_fact_root() { var y: U64 = 0
            while y < __s0_buffer_len(MirV6Fact, facts) { let right = __s0_buffer_get(MirV6Fact, facts, y)
                if right.function == function && right.value == b && right.kind == mir_v6_fact_root() && ((left.b == 0 && right.b == 0) || (left.a == right.a && left.b == right.b && left.c == right.c)) { return true }
                y = y + 1 } }
        x = x + 1 }
    return false
}
type MirV8Effect {
    function: U64
    parameter: U64
}
fn mir_v8_effect_has(effects: __s0_Buffer(MirV8Effect), function: U64, parameter: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV8Effect, effects) { let effect = __s0_buffer_get(MirV8Effect, effects, at)
if effect.function == function && effect.parameter == parameter { return true }
at = at + 1 }
return false }
fn mir_v8_add_effects(d: Domain, facts: __s0_Buffer(MirV6Fact), effects0: __s0_Buffer(MirV8Effect), function: U64, value: U64) -> Result(__s0_Buffer(MirV8Effect), __s0_Error) { var effects = effects0
var at: U64 = 0
while at < __s0_buffer_len(MirV6Fact, facts) { let fact = __s0_buffer_get(MirV6Fact, facts, at)
if fact.function == function && fact.value == value && fact.kind == mir_v6_fact_root() && fact.b == 0 && fact.c != 0 && !mir_v8_effect_has(effects, function, fact.c) { effects = try __s0_buffer_append(MirV8Effect, d, effects, MirV8Effect(function: function, parameter: fact.c)) }
at = at + 1 }
return Ok(effects) }
fn mir_v8_cleanup_effects(d: Domain, store: MirStore, indexes: MirVIndexes, facts: __s0_Buffer(MirV6Fact), cleanup: MirV7Analysis, effects0: __s0_Buffer(MirV8Effect), function: U64, iid: U64) -> Result(__s0_Buffer(MirV8Effect), __s0_Error) { var effects = effects0
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e: U64 = 0
while e < __s0_buffer_len(MirV8Effect, effects0) { let effect = __s0_buffer_get(MirV8Effect, effects0, e)
if effect.function == push.target { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
effects = try mir_v8_add_effects(d, facts, effects, function, arg) }
e = e + 1 } } }
active = node.parent } }
si = si + 1 }
return Ok(effects) }
fn mir_v8_compute_effects(d: Domain, store: MirStore, indexes: MirVIndexes, facts: __s0_Buffer(MirV6Fact), cleanup: MirV7Analysis) -> Result(__s0_Buffer(MirV8Effect), __s0_Error) { var effects = try __s0_buffer_new(MirV8Effect, d)
var changed = true
while changed { let before = __s0_buffer_len(MirV8Effect, effects)
var iid: U64 = 1
while iid <= __s0_buffer_len(MirInstrRec, store.instructions) { let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_table_insert() || x.op == mir_op_table_remove() { effects = try mir_v8_add_effects(d, facts, effects, x.function, x.a) }
if x.op == mir_op_call() { var e: U64 = 0
while e < __s0_buffer_len(MirV8Effect, effects) { let effect = __s0_buffer_get(MirV8Effect, effects, e)
if effect.function == x.target { effects = try mir_v8_add_effects(d, facts, effects, x.function, mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)) }
e = e + 1 } }
if x.op == mir_op_cleanup_scope_run() { effects = try mir_v8_cleanup_effects(d, store, indexes, facts, cleanup, effects, x.function, iid) }
iid = iid + 1 }
changed = before != __s0_buffer_len(MirV8Effect, effects) }
return Ok(effects) }
fn mir_v8_cleanup_mutates(store: MirStore, indexes: MirVIndexes, facts: __s0_Buffer(MirV6Fact), cleanup: MirV7Analysis, effects: __s0_Buffer(MirV8Effect), function: U64, iid: U64, table: U64) -> Bool { var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e: U64 = 0
while e < __s0_buffer_len(MirV8Effect, effects) { let effect = __s0_buffer_get(MirV8Effect, effects, e)
if effect.function == push.target && mir_v8_same_table(facts, function, mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1), table) { return true }
e = e + 1 } } }
active = node.parent } }
si = si + 1 }
return false }
fn mir_v8_mutates(store: MirStore, indexes: MirVIndexes, facts: __s0_Buffer(MirV6Fact), cleanup: MirV7Analysis, effects: __s0_Buffer(MirV8Effect), function: U64, iid: U64, table: U64) -> Bool {
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if (x.op == mir_op_table_insert() || x.op == mir_op_table_remove()) && mir_v8_same_table(facts, function, x.a, table) { return true }
    if x.op == mir_op_call() { var e: U64 = 0
        while e < __s0_buffer_len(MirV8Effect, effects) { let effect = __s0_buffer_get(MirV8Effect, effects, e)
            if effect.function == x.target && mir_v8_same_table(facts, function, mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1), table) { return true }
            e = e + 1 } }
    if x.op == mir_op_cleanup_scope_run() { return mir_v8_cleanup_mutates(store, indexes, facts, cleanup, effects, function, iid, table) }
    return false
}
fn mir_v8_function(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, facts: __s0_Buffer(MirV6Fact), cleanup: MirV7Analysis, effects: __s0_Buffer(MirV8Effect), initial: __s0_Buffer(MirVerifyDiagRec), function: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var value: U64 = 1
        while mir_vindex_value(indexes, function, value) != 0 { let vi = mir_vindex_value(indexes, function, value)
            let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
            let iid = mir_v8_instr_for_value(store, indexes, function, value)
            if iid != 0 { let lookup = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if lookup.op == mir_op_table_lookup() || lookup.op == mir_op_table_lookup_mut() { var consumers: U64 = 0
                    var end_instruction: U64 = 0
                    let use_start = __s0_buffer_get(U64, inventory.value_start, vi - 1)
                    let use_count = __s0_buffer_get(U64, inventory.value_count, vi - 1)
                    var ui: U64 = 0
                    while ui < use_count { let use_id = __s0_buffer_get(U64, inventory.value_use_ids, use_start + ui)
                        let use = __s0_buffer_get(MirVP4Use, inventory.uses, use_id - 1)
                        if use.value == value { if use.instruction != 0 { let consumer = __s0_buffer_get(MirInstrRec, store.instructions, use.instruction - 1)
                                if consumer.op == mir_op_enum_payload_checked() && mir_vname_word(store, consumer.name_start, consumer.name_end, "some") { consumers = consumers + 1
                                    end_instruction = use.instruction } }
                            if use.terminator != 0 { let term = __s0_buffer_get(MirTermRec, store.terminators, use.terminator - 1)
                                if term.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, use.terminator)
                                    var ci: U64 = 0
                                    while ci < total {
                                        let case = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, use.terminator, ci) - 1)
                                        if case.kind == mir_operand_switch_case() && case.value != 0 && mir_vname_word(store, case.name_start, case.name_end, "some") { consumers = consumers + 1 }
                                        ci = ci + 1
                                    } } } }
                        ui = ui + 1 }
                    if consumers != 1 { out = try mir_v8_diag(d, out, mir_vdiag_table_lookup_consumption(), function, lookup.block, 0, 0, value) }
                    if consumers == 1 && end_instruction != 0 { var scan = iid + 1
                        while scan < end_instruction { let between = __s0_buffer_get(MirInstrRec, store.instructions, scan - 1)
                            if between.function == function && between.block == lookup.block { if mir_vop_checked(between.op) { out = try mir_v8_diag(d, out, mir_vdiag_table_failure_bypass(), function, lookup.block, scan, 0, value) }
                                if mir_v8_mutates(store, indexes, facts, cleanup, effects, function, scan, lookup.a) { out = try mir_v8_diag(d, out, mir_vdiag_table_mutation_before_consume(), function, lookup.block, scan, 0, value) } }
                            scan = scan + 1 } } }
            }
            if mir_v8_is_view(store, indexes, function, value) { var source: U64 = 0
                var region = v.block
                var start_instruction: U64 = 0
                if iid != 0 { let extract = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                    if extract.op == mir_op_enum_payload_checked() { let lookup_id = mir_v8_instr_for_value(store, indexes, function, extract.a)
                        if lookup_id != 0 { let lookup = __s0_buffer_get(MirInstrRec, store.instructions, lookup_id - 1)
                            if lookup.op == mir_op_table_lookup() || lookup.op == mir_op_table_lookup_mut() { source = lookup.a
                                start_instruction = iid } } } }
                if v.def_kind == mir_value_def_switch_case() { let term_id = mir_vindex_term(indexes, function, v.block)
                    if term_id != 0 {
                        let term = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
                        if term.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
                            var ci: U64 = 0
                            while ci < total {
                                let case = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, ci) - 1)
                                if case.kind == mir_operand_switch_case() && case.ordinal + 1 == v.item && case.value == value && mir_vname_word(store, case.name_start, case.name_end, "some") { let lookup_id = mir_v8_instr_for_value(store, indexes, function, term.value)
                                    if lookup_id != 0 { let lookup = __s0_buffer_get(MirInstrRec, store.instructions, lookup_id - 1)
                                        if lookup.op == mir_op_table_lookup() || lookup.op == mir_op_table_lookup_mut() { source = lookup.a
                                            region = case.target } } }
                                ci = ci + 1
                            } }
                    } }
                var ends: U64 = 0
                var end_id: U64 = 0
                var ui2: U64 = 0
                var prior_use: U64 = 0
                let view_use_start = __s0_buffer_get(U64, inventory.value_start, vi - 1)
                let view_use_count = __s0_buffer_get(U64, inventory.value_count, vi - 1)
                while ui2 < view_use_count { let site_id = __s0_buffer_get(U64, inventory.value_use_ids, view_use_start + ui2)
                    let site = __s0_buffer_get(MirVP4Use, inventory.uses, site_id - 1)
                    if site.value == value { var duplicate = false
                        if prior_use != 0 { duplicate = mir_v8_same_use(__s0_buffer_get(MirVP4Use, inventory.uses, prior_use - 1), site) }
                        prior_use = site_id
                        if !duplicate { if site.block != region { out = try mir_v8_diag(d, out, mir_vdiag_table_view_region(), function, site.block, site.instruction, site.terminator, value) }
                            if site.instruction != 0 { let use = __s0_buffer_get(MirInstrRec, store.instructions, site.instruction - 1)
                                if use.op == mir_op_table_view_end() { if ends != 0 { out = try mir_v8_diag(d, out, mir_vdiag_table_view_end_count(), function, use.block, site.instruction, 0, value) }
                                    ends = ends + 1
                                    end_id = site.instruction } else { if end_id != 0 && use.block == region && use.ordinal > __s0_buffer_get(MirInstrRec, store.instructions, end_id - 1).ordinal { out = try mir_v8_diag(d, out, mir_vdiag_table_view_after_end(), function, use.block, site.instruction, 0, value) } } } } }
                    ui2 = ui2 + 1 }
                if source == 0 { out = try mir_v8_diag(d, out, mir_vdiag_table_view_source(), function, region, 0, 0, value) }
                if ends == 0 { out = try mir_v8_diag(d, out, mir_vdiag_table_view_end_count(), function, region, 0, 0, value) }
                if source != 0 && ends == 1 { var scan2 = start_instruction + 1
                    while scan2 < end_id { let active = __s0_buffer_get(MirInstrRec, store.instructions, scan2 - 1)
                        if active.function == function && active.block == region { if mir_vop_checked(active.op) { out = try mir_v8_diag(d, out, mir_vdiag_table_view_failure_bypass(), function, region, scan2, 0, value) }
                            if mir_v8_mutates(store, indexes, facts, cleanup, effects, function, scan2, source) { out = try mir_v8_diag(d, out, mir_vdiag_table_view_active_mutation(), function, region, scan2, 0, value) } }
                        scan2 = scan2 + 1 } }
            }
            value = value + 1 }
    return Ok(out)
}

fn mir_vphase8_with(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, initial: __s0_Buffer(MirVerifyDiagRec), cleanup: MirV7Analysis, provenance: MirV6Analysis) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
let effects = try mir_v8_compute_effects(d, store, indexes, provenance.facts, cleanup)
var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) { out = try mir_v8_function(d, store, indexes, inventory, provenance.facts, cleanup, effects, out, function)
function = function + 1 }
    return Ok(out)
}

fn mir_vphase8(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
let cleanup = try mir_v7_analyze(d, store, indexes, initial)
let provenance = try mir_v6_compute(d, store, indexes, cleanup)
let inventory = try mir_vp4_use_inventory_build(d, store, indexes)
return mir_vphase8_with(d, store, indexes, inventory, initial, cleanup, provenance) }
