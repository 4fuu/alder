fn mir_v3_op_count(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64) -> U64 {
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
    return 0
}
fn mir_v3_block_param_count(store: MirStore, indexes: MirVIndexes, function: U64, block: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var want: U64 = 0
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if p.kind == mir_param_block() && p.block == block { want = want + 1 }
        at = at + 1
    }
    return want
}
fn mir_vtarget_check(d: Domain, store: MirStore, indexes: MirVIndexes, out: __s0_Buffer(MirVerifyDiagRec), function: U64, block: U64, instruction: U64, terminator: U64, operand: U64, target: U64, got: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var result = out
    if target == 0 { return mir_vadd(d, result, mir_vdiag(mir_verify_phase_cfg(), mir_vdiag_missing_target(), function, block, instruction, terminator, operand, 0, 0, 0, 0, 0)) }
    let target_index = mir_vindex_block(indexes, function, target)
    if target_index == 0 { return mir_vadd(d, result, mir_vdiag(mir_verify_phase_cfg(), mir_vdiag_foreign_target(), function, block, instruction, terminator, operand, 0, 0, 0, 0, target)) }
    let want = mir_v3_block_param_count(store, indexes, function, target)
    if got != want { result = try mir_vadd(d, result, mir_vdiag(mir_verify_phase_cfg(), mir_vdiag_edge_arity(), function, block, instruction, terminator, operand, 0, 0, want, got, target)) }
    return Ok(result)
}
fn mir_vcase_known(store: MirStore, indexes: MirVIndexes, type_id: U64, start: U64, end: U64) -> Bool {
    let kind = mir_vtype_kind(store, type_id)
    if kind == mir_type_kind_option() { return mir_vname_word(store, start, end, "none") || mir_vname_word(store, start, end, "some") }
    if kind == mir_type_kind_result() { return mir_vname_word(store, start, end, "ok") || mir_vname_word(store, start, end, "err") }
    if kind != mir_type_kind_enum() { return false }
    let count = mir_vindex_type_part_count(indexes, type_id)
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if p.kind == mir_type_part_variant() && mir_vname_equal(store, start, end, p.name_start, p.name_end) { return true }
        at = at + 1
    }
    return false
}
fn mir_vcase_payload(store: MirStore, indexes: MirVIndexes, type_id: U64, start: U64, end: U64) -> U64 {
    let kind = mir_vtype_kind(store, type_id)
    if kind == mir_type_kind_option() { if mir_vname_word(store, start, end, "none") { return mir_type_unit() }
return __s0_buffer_get(MirTypeRec, store.types, type_id - 1).elem }
    if kind == mir_type_kind_result() { if mir_vname_word(store, start, end, "ok") { return __s0_buffer_get(MirTypeRec, store.types, type_id - 1).ok_type }
return __s0_buffer_get(MirTypeRec, store.types, type_id - 1).err_type }
    let count = mir_vindex_type_part_count(indexes, type_id)
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if p.kind == mir_type_part_variant() && mir_vname_equal(store, start, end, p.name_start, p.name_end) { return p.part_type }
        at = at + 1
    }
    return 0
}
fn mir_vswitch_exhaustive(store: MirStore, indexes: MirVIndexes, term_id: U64, type_id: U64) -> Bool {
    let kind = mir_vtype_kind(store, type_id)
    if kind == mir_type_kind_option() { var none = false
var some = false
let ccount = mir_vindex_op_term_count(indexes, term_id)
var at: U64 = 0
while at < ccount { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, at) - 1)
if c.kind == mir_operand_switch_case() { if c.name_start == c.name_end { return true }
if mir_vname_word(store, c.name_start, c.name_end, "none") { none = true }
if mir_vname_word(store, c.name_start, c.name_end, "some") { some = true } }
at = at + 1 }
return none && some }
    if kind == mir_type_kind_result() { var ok = false
var err = false
let ccount = mir_vindex_op_term_count(indexes, term_id)
var at: U64 = 0
while at < ccount { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, at) - 1)
if c.kind == mir_operand_switch_case() { if c.name_start == c.name_end { return true }
if mir_vname_word(store, c.name_start, c.name_end, "ok") { ok = true }
if mir_vname_word(store, c.name_start, c.name_end, "err") { err = true } }
at = at + 1 }
return ok && err }
    if kind != mir_type_kind_enum() { return true }
    let vcount = mir_vindex_type_part_count(indexes, type_id)
    var p: U64 = 0
    while p < vcount {
        let variant = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, p) - 1)
        if variant.kind == mir_type_part_variant() { var found = false
let ccount = mir_vindex_op_term_count(indexes, term_id)
var at: U64 = 0
while at < ccount { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, at) - 1)
if c.kind == mir_operand_switch_case() { if c.name_start == c.name_end { return true }
if mir_vname_equal(store, c.name_start, c.name_end, variant.name_start, variant.name_end) { found = true } }
at = at + 1 }
if !found { return false } }
        p = p + 1
    }
    return true
}
fn mir_vreachable(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    var queue = try __s0_buffer_new(U64, d)
    var seen = try __s0_buffer_new(U64, d)
    queue = try __s0_buffer_append(U64, d, queue, 1)
    var at: U64 = 0
    while at < __s0_buffer_len(U64, queue) {
        let block = __s0_buffer_get(U64, queue, at)
var known = false
var s: U64 = 0
        while s < __s0_buffer_len(U64, seen) { if __s0_buffer_get(U64, seen, s) == block { known = true }
s = s + 1 }
        if !known && mir_vindex_block(indexes, function, block) != 0 {
            seen = try __s0_buffer_append(U64, d, seen, block)
            // Checked successors in instruction storage order.
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, block, ii)
                let i = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if mir_vop_checked(i.op) && mir_vindex_block(indexes, function, i.target) != 0 { queue = try __s0_buffer_append(U64, d, queue, i.target) }
                ii = ii + 1
            }
            // Then terminator successors, with switch cases in operand order.
            let term_id = mir_vindex_term(indexes, function, block)
            if term_id != 0 {
                let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
                if t.kind == mir_term_jump() { queue = try __s0_buffer_append(U64, d, queue, t.target) }
                if t.kind == mir_term_branch() { queue = try __s0_buffer_append(U64, d, queue, t.then_block)
queue = try __s0_buffer_append(U64, d, queue, t.else_block) }
                if t.kind == mir_term_switch() {
                    let ccount = mir_vindex_op_term_count(indexes, term_id)
                    var ci: U64 = 0
                    while ci < ccount {
                        let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, ci) - 1)
                        if c.kind == mir_operand_switch_case() { queue = try __s0_buffer_append(U64, d, queue, c.target) }
                        ci = ci + 1
                    }
                }
            }
        }
        at = at + 1
    }
    return Ok(seen)
}
fn mir_vseen_block(seen: __s0_Buffer(U64), block: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(U64, seen) { if __s0_buffer_get(U64, seen, at) == block { return true }
at = at + 1 }
return false }
fn mir_vphase3(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_cfg()
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let entry_params = mir_v3_block_param_count(store, indexes, function, 1)
        if entry_params != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_entry_params(), function, 1, 0, 0, 0, 0, 0, 0, entry_params, 0)) }
        let reach = try mir_vreachable(d, store, indexes, function)
        let bcount = mir_vindex_block_count(indexes, function)
        // Checked instructions in instruction storage order first.
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, block, ii)
                let i = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if mir_vop_checked(i.op) { out = try mir_vtarget_check(d, store, indexes, out, function, i.block, iid, 0, 0, i.target, mir_v3_op_count(store, indexes, mir_operand_checked_edge_arg(), iid, 0)) }
                ii = ii + 1
            }
            block = block + 1
        }
        // Then terminators in terminator storage order.
        block = 1
        while block <= bcount {
            let term_id = mir_vindex_term(indexes, function, block)
            if term_id != 0 {
                let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
                if t.kind == mir_term_jump() { out = try mir_vtarget_check(d, store, indexes, out, function, t.block, 0, term_id, 0, t.target, mir_v3_op_count(store, indexes, mir_operand_terminator_arg(), term_id, mir_edge_jump())) }
                if t.kind == mir_term_branch() { out = try mir_vtarget_check(d, store, indexes, out, function, t.block, 0, term_id, 0, t.then_block, mir_v3_op_count(store, indexes, mir_operand_terminator_arg(), term_id, mir_edge_then()))
out = try mir_vtarget_check(d, store, indexes, out, function, t.block, 0, term_id, 0, t.else_block, mir_v3_op_count(store, indexes, mir_operand_terminator_arg(), term_id, mir_edge_else())) }
                if t.kind == mir_term_switch() {
                    let count = mir_v3_op_count(store, indexes, mir_operand_switch_case(), term_id, 0)
                    if count == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_empty_switch(), function, t.block, 0, term_id, 0, 0, 0, 1, 0, 0)) }
                    var defaults: U64 = 0
var value_type: U64 = 0
let vi = mir_vindex_value(indexes, function, t.value)
if vi != 0 { value_type = __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type }
                    let ccount = mir_vindex_op_term_count(indexes, term_id)
                    var ci: U64 = 0
                    while ci < ccount {
                        let cid = mir_vindex_op_term(indexes, term_id, ci)
                        let c = __s0_buffer_get(MirOperandRec, store.operands, cid - 1)
                        if c.kind == mir_operand_switch_case() {
                            if c.name_start == c.name_end { defaults = defaults + 1
if c.value != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_default_binding(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, c.value)) } } else {
                                var prior: U64 = 0
while prior < ci { let pid = mir_vindex_op_term(indexes, term_id, prior)
if pid < cid { let p = __s0_buffer_get(MirOperandRec, store.operands, pid - 1)
if p.kind == mir_operand_switch_case() && mir_vname_equal(store, c.name_start, c.name_end, p.name_start, p.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_case(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, pid))
prior = ci } }
prior = prior + 1 }
                                if !mir_vcase_known(store, indexes, value_type, c.name_start, c.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_unknown_case(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, 0)) } else { if c.value != 0 && mir_vcase_payload(store, indexes, value_type, c.name_start, c.name_end) == mir_type_unit() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_unit_binding(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, c.value)) } }
                            }
                            out = try mir_vtarget_check(d, store, indexes, out, function, t.block, 0, term_id, cid, c.target, mir_v3_op_count(store, indexes, mir_operand_switch_case_arg(), cid, 0))
                        }
                        ci = ci + 1
                    }
                    if defaults > 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_default(), function, t.block, 0, term_id, 0, value_type, 0, 1, defaults, 0)) }
                    if defaults == 0 && !mir_vswitch_exhaustive(store, indexes, term_id, value_type) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_nonexhaustive_switch(), function, t.block, 0, term_id, 0, value_type, 0, 0, 0, 0)) }
                }
                if t.kind == mir_term_unreachable() && mir_vseen_block(reach, t.block) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_reachable_unreachable(), function, t.block, 0, term_id, 0, 0, 0, 0, 0, 0)) }
            }
            block = block + 1
        }
        function = function + 1
    }
    return Ok(out)
}
fn mir_verify_module(d: Domain, store: MirStore, version: U64) -> Result(MirVerifyOutput, __s0_Error) {
    var diagnostics = try __s0_buffer_new(MirVerifyDiagRec, d)
    diagnostics = try mir_vphase1(d, store, version, diagnostics)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let indexes = try mir_vindex_build(d, store)
    diagnostics = try mir_vphase2(d, store, indexes, diagnostics)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase3(d, store, indexes, diagnostics)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase4(d, store, indexes, diagnostics)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase5(d, store, indexes, diagnostics)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let cleanup = try mir_v7_analyze(d, store, indexes, try __s0_buffer_new(MirVerifyDiagRec, d))
    let provenance = try mir_v6_compute(d, store, indexes, cleanup)
    diagnostics = try mir_vphase6_with(d, store, indexes, diagnostics, cleanup, provenance)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = cleanup.diagnostics
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase8_with(d, store, indexes, diagnostics, cleanup, provenance)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase9(d, store, indexes, diagnostics)
    if __s0_buffer_len(MirVerifyDiagRec, diagnostics) != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase10(d, store, indexes, diagnostics)
    return Ok(MirVerifyOutput(diagnostics: diagnostics))
}
