fn mir_v3_op_count(read: MirV3Read, kind: U64, owner: U64, edge: U64) -> U64 {
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() {
        let total = read.op_instr_count[owner - 1]
        var count: U64 = 0
        var at: U64 = 0
        while at < total {
            let o = read.operands[mir_v3_op_instr(read, owner, at) - 1]
            if o.kind == kind && o.edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() {
        let total = read.op_term_count[owner - 1]
        var count: U64 = 0
        var at: U64 = 0
        while at < total {
            let o = read.operands[mir_v3_op_term(read, owner, at) - 1]
            if o.kind == kind && o.edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    if kind == mir_operand_switch_case_arg() {
        let total = read.op_case_count[owner - 1]
        var count: U64 = 0
        var at: U64 = 0
        while at < total {
            if read.operands[mir_v3_op_case(read, owner, at) - 1].edge == edge { count = count + 1 }
            at = at + 1
        }
        return count
    }
    return 0
}
fn mir_v3_block_param_count(read: MirV3Read, function: U64, block: U64) -> U64 {
    let count = mir_v3_param_count(read, function)
    var want: U64 = 0
    var at: U64 = 0
    while at < count {
        let p = read.params[mir_v3_param(read, function, at) - 1]
        if p.kind == mir_param_block() && p.block == block { want = want + 1 }
        at = at + 1
    }
    return want
}
fn mir_vtarget_check(d: Domain, read: MirV3Read, out: Vec(MirVerifyDiagRec), function: U64, block: U64, instruction: U64, terminator: U64, operand: U64, target: U64, got: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    var result = out
    if target == 0 { return mir_vadd(d, result, mir_vdiag(mir_verify_phase_cfg(), mir_vdiag_missing_target(), function, block, instruction, terminator, operand, 0, 0, 0, 0, 0)) }
    let target_index = mir_v3_block(read, function, target)
    if target_index == 0 { return mir_vadd(d, result, mir_vdiag(mir_verify_phase_cfg(), mir_vdiag_foreign_target(), function, block, instruction, terminator, operand, 0, 0, 0, 0, target)) }
    let want = mir_v3_block_param_count(read, function, target)
    if got != want { result = try mir_vadd(d, result, mir_vdiag(mir_verify_phase_cfg(), mir_vdiag_edge_arity(), function, block, instruction, terminator, operand, 0, 0, want, got, target)) }
    return Ok(result)
}
fn mir_v3_name_equal(read: MirV3Read, a_start: U64, a_end: U64, b_start: U64, b_end: U64) -> Bool {
    if !mir_vrange_valid(a_start, a_end, len(read.names)) || !mir_vrange_valid(b_start, b_end, len(read.names)) { return false }
    if a_end - a_start != b_end - b_start { return false }
    var at: U64 = 0
    while at < a_end - a_start { if read.names[a_start + at] != read.names[b_start + at] { return false }
    at = at + 1 }
    return true
}
fn mir_v3_name_word(read: MirV3Read, start: U64, end: U64, word: [U8]) -> Bool {
    if !mir_vrange_valid(start, end, len(read.names)) || end - start != len(word) { return false }
    var at: U64 = 0
    while at < len(word) { if read.names[start + at] != word[at] { return false }
    at = at + 1 }
    return true
}
fn mir_v3_type_kind(read: MirV3Read, id: U64) -> U64 {
    if id == 0 || id > len(read.types) { return 999 }
    return read.types[id - 1].kind
}
fn mir_vcase_known_read(read: MirV3Read, type_id: U64, start: U64, end: U64) -> Bool {
    let kind = mir_v3_type_kind(read, type_id)
    if kind == mir_type_kind_option() { return mir_v3_name_word(read, start, end, "none") || mir_v3_name_word(read, start, end, "some") }
    if kind == mir_type_kind_result() { return mir_v3_name_word(read, start, end, "ok") || mir_v3_name_word(read, start, end, "err") }
    if kind != mir_type_kind_enum() { return false }
    let count = read.tp_count[type_id - 1]
    var at: U64 = 0
    while at < count {
        let p = read.type_parts[mir_v3_type_part(read, type_id, at) - 1]
        if p.kind == mir_type_part_variant() && mir_v3_name_equal(read, start, end, p.name_start, p.name_end) { return true }
        at = at + 1
    }
    return false
}
fn mir_vcase_payload_read(read: MirV3Read, type_id: U64, start: U64, end: U64) -> U64 {
    let kind = mir_v3_type_kind(read, type_id)
    if kind == mir_type_kind_option() { if mir_v3_name_word(read, start, end, "none") { return mir_type_unit() }
return read.types[type_id - 1].elem }
    if kind == mir_type_kind_result() { if mir_v3_name_word(read, start, end, "ok") { return read.types[type_id - 1].ok_type }
return read.types[type_id - 1].err_type }
    let count = read.tp_count[type_id - 1]
    var at: U64 = 0
    while at < count {
        let p = read.type_parts[mir_v3_type_part(read, type_id, at) - 1]
        if p.kind == mir_type_part_variant() && mir_v3_name_equal(read, start, end, p.name_start, p.name_end) { return p.part_type }
        at = at + 1
    }
    return 0
}
fn mir_vswitch_exhaustive_read(read: MirV3Read, term_id: U64, type_id: U64) -> Bool {
    let kind = mir_v3_type_kind(read, type_id)
    if kind == mir_type_kind_option() { var none = false
var some = false
let ccount = read.op_term_count[term_id - 1]
var at: U64 = 0
while at < ccount { let c = read.operands[mir_v3_op_term(read, term_id, at) - 1]
if c.kind == mir_operand_switch_case() { if c.name_start == c.name_end { return true }
if mir_v3_name_word(read, c.name_start, c.name_end, "none") { none = true }
if mir_v3_name_word(read, c.name_start, c.name_end, "some") { some = true } }
at = at + 1 }
return none && some }
    if kind == mir_type_kind_result() { var ok = false
var err = false
let ccount = read.op_term_count[term_id - 1]
var at: U64 = 0
while at < ccount { let c = read.operands[mir_v3_op_term(read, term_id, at) - 1]
if c.kind == mir_operand_switch_case() { if c.name_start == c.name_end { return true }
if mir_v3_name_word(read, c.name_start, c.name_end, "ok") { ok = true }
if mir_v3_name_word(read, c.name_start, c.name_end, "err") { err = true } }
at = at + 1 }
return ok && err }
    if kind != mir_type_kind_enum() { return true }
    let vcount = read.tp_count[type_id - 1]
    var p: U64 = 0
    while p < vcount {
        let variant = read.type_parts[mir_v3_type_part(read, type_id, p) - 1]
        if variant.kind == mir_type_part_variant() { var found = false
let ccount = read.op_term_count[term_id - 1]
var at: U64 = 0
while at < ccount { let c = read.operands[mir_v3_op_term(read, term_id, at) - 1]
if c.kind == mir_operand_switch_case() { if c.name_start == c.name_end { return true }
if mir_v3_name_equal(read, c.name_start, c.name_end, variant.name_start, variant.name_end) { found = true } }
at = at + 1 }
if !found { return false } }
        p = p + 1
    }
    return true
}
fn mir_vcase_known(store: MirStore, indexes: MirVIndexes, type_id: U64, start: U64, end: U64) -> Bool {
    let kind = mir_vtype_kind(store, type_id)
    if kind == mir_type_kind_option() { return mir_vname_word(store, start, end, "none") || mir_vname_word(store, start, end, "some") }
    if kind == mir_type_kind_result() { return mir_vname_word(store, start, end, "ok") || mir_vname_word(store, start, end, "err") }
    if kind != mir_type_kind_enum() { return false }
    let count = mir_vindex_type_part_count(indexes, type_id)
    var at: U64 = 0
    while at < count {
        let p = (store.type_parts)[mir_vindex_type_part(indexes, type_id, at) - 1]
        if p.kind == mir_type_part_variant() && mir_vname_equal(store, start, end, p.name_start, p.name_end) { return true }
        at = at + 1
    }
    return false
}
fn mir_vcase_payload(store: MirStore, indexes: MirVIndexes, type_id: U64, start: U64, end: U64) -> U64 {
    let kind = mir_vtype_kind(store, type_id)
    if kind == mir_type_kind_option() { if mir_vname_word(store, start, end, "none") { return mir_type_unit() }
    return (store.types)[type_id - 1].elem }
    if kind == mir_type_kind_result() { if mir_vname_word(store, start, end, "ok") { return (store.types)[type_id - 1].ok_type }
    return (store.types)[type_id - 1].err_type }
    let count = mir_vindex_type_part_count(indexes, type_id)
    var at: U64 = 0
    while at < count {
        let p = (store.type_parts)[mir_vindex_type_part(indexes, type_id, at) - 1]
        if p.kind == mir_type_part_variant() && mir_vname_equal(store, start, end, p.name_start, p.name_end) { return p.part_type }
        at = at + 1
    }
    return 0
}
fn mir_vreachable_read(d: Domain, read: MirV3Read, function: U64) -> Result(Vec(U64), __s0_Error) {
    var queue = Vec.new(U64)
    var seen = Vec.new(U64)
    try queue.try_push(1)
    var at: U64 = 0
    while at < (queue).len() {
        let block = queue[at]
var known = false
var s: U64 = 0
        while s < (seen).len() { if seen[s] == block { known = true }
s = s + 1 }
        if !known && mir_v3_block(read, function, block) != 0 {
            try seen.try_push(block)
            // Checked successors in instruction storage order.
            let icount = mir_v3_instr_count(read, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_v3_instr(read, function, block, ii)
                let i = read.instructions[iid - 1]
                if mir_vop_checked(i.op) && mir_v3_block(read, function, i.target) != 0 { try queue.try_push(i.target) }
                ii = ii + 1
            }
            // Then terminator successors, with switch cases in operand order.
            let term_id = mir_v3_term(read, function, block)
            if term_id != 0 {
                let t = read.terminators[term_id - 1]
                if t.kind == mir_term_jump() { try queue.try_push(t.target) }
                if t.kind == mir_term_branch() { try queue.try_push(t.then_block)
try queue.try_push(t.else_block) }
                if t.kind == mir_term_switch() {
                    let ccount = read.op_term_count[term_id - 1]
                    var ci: U64 = 0
                    while ci < ccount {
                        let c = read.operands[mir_v3_op_term(read, term_id, ci) - 1]
                        if c.kind == mir_operand_switch_case() { try queue.try_push(c.target) }
                        ci = ci + 1
                    }
                }
            }
        }
        at = at + 1
    }
    return Ok(seen)
}
fn mir_vreachable(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(Vec(U64), __s0_Error) {
    var queue = Vec.new(U64)
    var seen = Vec.new(U64)
    try queue.try_push(1)
    var at: U64 = 0
    while at < (queue).len() {
        let block = queue[at]
        var known = false
        var s: U64 = 0
        while s < (seen).len() { if seen[s] == block { known = true }
        s = s + 1 }
        if !known && mir_vindex_block(indexes, function, block) != 0 {
            try seen.try_push(block)
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, block, ii)
                let i = (store.instructions)[iid - 1]
                if mir_vop_checked(i.op) && mir_vindex_block(indexes, function, i.target) != 0 { try queue.try_push(i.target) }
                ii = ii + 1
            }
            let term_id = mir_vindex_term(indexes, function, block)
            if term_id != 0 {
                let t = (store.terminators)[term_id - 1]
                if t.kind == mir_term_jump() { try queue.try_push(t.target) }
                if t.kind == mir_term_branch() { try queue.try_push(t.then_block)
                try queue.try_push(t.else_block) }
                if t.kind == mir_term_switch() {
                    let ccount = mir_vindex_op_term_count(indexes, term_id)
                    var ci: U64 = 0
                    while ci < ccount {
                        let c = (store.operands)[mir_vindex_op_term(indexes, term_id, ci) - 1]
                        if c.kind == mir_operand_switch_case() { try queue.try_push(c.target) }
                        ci = ci + 1
                    }
                }
            }
        }
        at = at + 1
    }
    return Ok(seen)
}
fn mir_vseen_block_view(seen: [U64], block: U64) -> Bool { var at: U64 = 0
while at < len(seen) { if seen[at] == block { return true }
at = at + 1 }
return false }
fn mir_vseen_block(seen: Vec(U64), block: U64) -> Bool { var at: U64 = 0
while at < (seen).len() { if seen[at] == block { return true }
at = at + 1 }
return false }
fn mir_vphase3_read(d: Domain, initial: Vec(MirVerifyDiagRec), read: MirV3Read) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_cfg()
    var function: U64 = 1
    while function <= len(read.functions) {
        let entry_params = mir_v3_block_param_count(read, function, 1)
        if entry_params != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_entry_params(), function, 1, 0, 0, 0, 0, 0, 0, entry_params, 0)) }
        let reach = try mir_vreachable_read(d, read, function)
        let reached = reach.slice(0, (reach).len())
        let bcount = read.block_count[function - 1]
        // Checked instructions in instruction storage order first.
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_v3_instr_count(read, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_v3_instr(read, function, block, ii)
                let i = read.instructions[iid - 1]
                if mir_vop_checked(i.op) { out = try mir_vtarget_check(d, read, out, function, i.block, iid, 0, 0, i.target, mir_v3_op_count(read, mir_operand_checked_edge_arg(), iid, 0)) }
                ii = ii + 1
            }
            block = block + 1
        }
        // Then terminators in terminator storage order.
        block = 1
        while block <= bcount {
            let term_id = mir_v3_term(read, function, block)
            if term_id != 0 {
                let t = read.terminators[term_id - 1]
                if t.kind == mir_term_jump() { out = try mir_vtarget_check(d, read, out, function, t.block, 0, term_id, 0, t.target, mir_v3_op_count(read, mir_operand_terminator_arg(), term_id, mir_edge_jump())) }
                if t.kind == mir_term_branch() { out = try mir_vtarget_check(d, read, out, function, t.block, 0, term_id, 0, t.then_block, mir_v3_op_count(read, mir_operand_terminator_arg(), term_id, mir_edge_then()))
out = try mir_vtarget_check(d, read, out, function, t.block, 0, term_id, 0, t.else_block, mir_v3_op_count(read, mir_operand_terminator_arg(), term_id, mir_edge_else())) }
                if t.kind == mir_term_switch() {
                    let count = mir_v3_op_count(read, mir_operand_switch_case(), term_id, 0)
                    if count == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_empty_switch(), function, t.block, 0, term_id, 0, 0, 0, 1, 0, 0)) }
                    var defaults: U64 = 0
var value_type: U64 = 0
let vi = mir_v3_value(read, function, t.value)
if vi != 0 { value_type = read.values[vi - 1].value_type }
                    let ccount = read.op_term_count[term_id - 1]
                    var ci: U64 = 0
                    while ci < ccount {
                        let cid = mir_v3_op_term(read, term_id, ci)
                        let c = read.operands[cid - 1]
                        if c.kind == mir_operand_switch_case() {
                            if c.name_start == c.name_end { defaults = defaults + 1
if c.value != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_default_binding(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, c.value)) } } else {
                                var prior: U64 = 0
while prior < ci { let pid = mir_v3_op_term(read, term_id, prior)
if pid < cid { let p = read.operands[pid - 1]
if p.kind == mir_operand_switch_case() && mir_v3_name_equal(read, c.name_start, c.name_end, p.name_start, p.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_case(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, pid))
prior = ci } }
prior = prior + 1 }
                                if !mir_vcase_known_read(read, value_type, c.name_start, c.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_unknown_case(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, 0)) } else { if c.value != 0 && mir_vcase_payload_read(read, value_type, c.name_start, c.name_end) == mir_type_unit() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_unit_binding(), function, t.block, 0, term_id, cid, value_type, 0, 0, 0, c.value)) } }
                            }
                            out = try mir_vtarget_check(d, read, out, function, t.block, 0, term_id, cid, c.target, mir_v3_op_count(read, mir_operand_switch_case_arg(), cid, 0))
                        }
                        ci = ci + 1
                    }
                    if defaults > 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_default(), function, t.block, 0, term_id, 0, value_type, 0, 1, defaults, 0)) }
                    if defaults == 0 && !mir_vswitch_exhaustive_read(read, term_id, value_type) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_nonexhaustive_switch(), function, t.block, 0, term_id, 0, value_type, 0, 0, 0, 0)) }
                }
                if t.kind == mir_term_unreachable() && mir_vseen_block_view(reached, t.block) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_reachable_unreachable(), function, t.block, 0, term_id, 0, 0, 0, 0, 0, 0)) }
            }
            block = block + 1
        }
        function = function + 1
    }
    return Ok(out)
}
fn mir_verify_module(d: Domain, store: MirStore, version: U64) -> Result(MirVerifyOutput, __s0_Error) {
    var diagnostics = Vec.new(MirVerifyDiagRec)
    diagnostics = try mir_vphase1(d, store, version, diagnostics)
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let indexes = try mir_vindex_build(d, store)
    diagnostics = try mir_vphase2(d, store, indexes, diagnostics)
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let v3_names = store.names
    let v3_types = store.types
    let v3_type_parts = store.type_parts
    let v3_functions = store.functions
    let v3_params = store.params
    let v3_values = store.values
    let v3_instructions = store.instructions
    let v3_terminators = store.terminators
    let v3_operands = store.operands
    let v3_block_pos = indexes.block_pos
    let v3_block_span = indexes.block_span
    let v3_block_count = indexes.block_count
    let v3_value_pos = indexes.value_pos
    let v3_value_span = indexes.value_span
    let v3_value_count = indexes.value_count
    let v3_instr_span = indexes.instr_span
    let v3_instr_count = indexes.instr_count
    let v3_instr_off = indexes.instr_off
    let v3_instr_ids = indexes.instr_ids
    let v3_param_span = indexes.param_span
    let v3_param_ids = indexes.param_ids
    let v3_term_pos = indexes.term_pos
    let v3_term_span = indexes.term_span
    let v3_op_instr_start = indexes.op_instr_start
    let v3_op_instr_count = indexes.op_instr_count
    let v3_op_instr_ids = indexes.op_instr_ids
    let v3_op_term_start = indexes.op_term_start
    let v3_op_term_count = indexes.op_term_count
    let v3_op_term_ids = indexes.op_term_ids
    let v3_op_case_start = indexes.op_case_start
    let v3_op_case_count = indexes.op_case_count
    let v3_op_case_ids = indexes.op_case_ids
    let v3_tp_start = indexes.tp_start
    let v3_tp_count = indexes.tp_count
    let v3_tp_ids = indexes.tp_ids
    diagnostics = try mir_vphase3_read(d, diagnostics, MirV3Read(names: v3_names.slice(0, (v3_names).len()), types: v3_types.slice(0, (v3_types).len()), type_parts: v3_type_parts.slice(0, (v3_type_parts).len()), functions: v3_functions.slice(0, (v3_functions).len()), params: v3_params.slice(0, (v3_params).len()), values: v3_values.slice(0, (v3_values).len()), instructions: v3_instructions.slice(0, (v3_instructions).len()), terminators: v3_terminators.slice(0, (v3_terminators).len()), operands: v3_operands.slice(0, (v3_operands).len()), block_pos: v3_block_pos.slice(0, (v3_block_pos).len()), block_span: v3_block_span.slice(0, (v3_block_span).len()), block_count: v3_block_count.slice(0, (v3_block_count).len()), value_pos: v3_value_pos.slice(0, (v3_value_pos).len()), value_span: v3_value_span.slice(0, (v3_value_span).len()), value_count: v3_value_count.slice(0, (v3_value_count).len()), instr_span: v3_instr_span.slice(0, (v3_instr_span).len()), instr_count: v3_instr_count.slice(0, (v3_instr_count).len()), instr_off: v3_instr_off.slice(0, (v3_instr_off).len()), instr_ids: v3_instr_ids.slice(0, (v3_instr_ids).len()), param_span: v3_param_span.slice(0, (v3_param_span).len()), param_ids: v3_param_ids.slice(0, (v3_param_ids).len()), term_pos: v3_term_pos.slice(0, (v3_term_pos).len()), term_span: v3_term_span.slice(0, (v3_term_span).len()), op_instr_start: v3_op_instr_start.slice(0, (v3_op_instr_start).len()), op_instr_count: v3_op_instr_count.slice(0, (v3_op_instr_count).len()), op_instr_ids: v3_op_instr_ids.slice(0, (v3_op_instr_ids).len()), op_term_start: v3_op_term_start.slice(0, (v3_op_term_start).len()), op_term_count: v3_op_term_count.slice(0, (v3_op_term_count).len()), op_term_ids: v3_op_term_ids.slice(0, (v3_op_term_ids).len()), op_case_start: v3_op_case_start.slice(0, (v3_op_case_start).len()), op_case_count: v3_op_case_count.slice(0, (v3_op_case_count).len()), op_case_ids: v3_op_case_ids.slice(0, (v3_op_case_ids).len()), tp_start: v3_tp_start.slice(0, (v3_tp_start).len()), tp_count: v3_tp_count.slice(0, (v3_tp_count).len()), tp_ids: v3_tp_ids.slice(0, (v3_tp_ids).len())))
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let uses = try mir_vp4_use_inventory_build(d, store, indexes)
    diagnostics = try mir_vphase4_with_uses(d, store, indexes, uses, diagnostics)
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let v5_imports = store.imports
    let v5_constants = store.constants
    let v5_locals = store.locals
    let v5_places = store.places
    let v5_local_pos = indexes.local_pos
    let v5_local_span = indexes.local_span
    let v5_local_count = indexes.local_count
    let v5_const_slot = indexes.const_slot
    let v5_type_first = indexes.type_first
    let v5_type_unary = indexes.type_unary
    diagnostics = try mir_vphase5_read(d, diagnostics, MirV5Read(base: MirV3Read(names: v3_names.slice(0, (v3_names).len()), types: v3_types.slice(0, (v3_types).len()), type_parts: v3_type_parts.slice(0, (v3_type_parts).len()), functions: v3_functions.slice(0, (v3_functions).len()), params: v3_params.slice(0, (v3_params).len()), values: v3_values.slice(0, (v3_values).len()), instructions: v3_instructions.slice(0, (v3_instructions).len()), terminators: v3_terminators.slice(0, (v3_terminators).len()), operands: v3_operands.slice(0, (v3_operands).len()), block_pos: v3_block_pos.slice(0, (v3_block_pos).len()), block_span: v3_block_span.slice(0, (v3_block_span).len()), block_count: v3_block_count.slice(0, (v3_block_count).len()), value_pos: v3_value_pos.slice(0, (v3_value_pos).len()), value_span: v3_value_span.slice(0, (v3_value_span).len()), value_count: v3_value_count.slice(0, (v3_value_count).len()), instr_span: v3_instr_span.slice(0, (v3_instr_span).len()), instr_count: v3_instr_count.slice(0, (v3_instr_count).len()), instr_off: v3_instr_off.slice(0, (v3_instr_off).len()), instr_ids: v3_instr_ids.slice(0, (v3_instr_ids).len()), param_span: v3_param_span.slice(0, (v3_param_span).len()), param_ids: v3_param_ids.slice(0, (v3_param_ids).len()), term_pos: v3_term_pos.slice(0, (v3_term_pos).len()), term_span: v3_term_span.slice(0, (v3_term_span).len()), op_instr_start: v3_op_instr_start.slice(0, (v3_op_instr_start).len()), op_instr_count: v3_op_instr_count.slice(0, (v3_op_instr_count).len()), op_instr_ids: v3_op_instr_ids.slice(0, (v3_op_instr_ids).len()), op_term_start: v3_op_term_start.slice(0, (v3_op_term_start).len()), op_term_count: v3_op_term_count.slice(0, (v3_op_term_count).len()), op_term_ids: v3_op_term_ids.slice(0, (v3_op_term_ids).len()), op_case_start: v3_op_case_start.slice(0, (v3_op_case_start).len()), op_case_count: v3_op_case_count.slice(0, (v3_op_case_count).len()), op_case_ids: v3_op_case_ids.slice(0, (v3_op_case_ids).len()), tp_start: v3_tp_start.slice(0, (v3_tp_start).len()), tp_count: v3_tp_count.slice(0, (v3_tp_count).len()), tp_ids: v3_tp_ids.slice(0, (v3_tp_ids).len())), imports: v5_imports.slice(0, (v5_imports).len()), constants: v5_constants.slice(0, (v5_constants).len()), locals: v5_locals.slice(0, (v5_locals).len()), places: v5_places.slice(0, (v5_places).len()), local_pos: v5_local_pos.slice(0, (v5_local_pos).len()), local_span: v5_local_span.slice(0, (v5_local_span).len()), local_count: v5_local_count.slice(0, (v5_local_count).len()), const_slot: v5_const_slot.slice(0, (v5_const_slot).len()), type_first: v5_type_first.slice(0, (v5_type_first).len()), type_unary: v5_type_unary.slice(0, (v5_type_unary).len())))
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    let cleanup = try mir_v7_analyze(d, store, indexes, Vec.new(MirVerifyDiagRec))
    let provenance = try mir_v6_compute(d, store, indexes, cleanup)
    diagnostics = try mir_vphase6_with(d, store, indexes, uses, diagnostics, cleanup, provenance)
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = cleanup.diagnostics
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase8_with(d, store, indexes, uses, diagnostics, cleanup, provenance)
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase9_with_uses(d, store, indexes, uses, diagnostics)
    if (diagnostics).len() != 0 { return Ok(MirVerifyOutput(diagnostics: diagnostics)) }
    diagnostics = try mir_vphase10(d, store, indexes, diagnostics)
    return Ok(MirVerifyOutput(diagnostics: diagnostics))
}
type MirV3Read {
    names: [U8]
    types: [MirTypeRec]
    type_parts: [MirTypePartRec]
    functions: [MirFunctionRec]
    params: [MirParamRec]
    values: [MirValueRec]
    instructions: [MirInstrRec]
    terminators: [MirTermRec]
    operands: [MirOperandRec]
    block_pos: [U64]
    block_span: [U64]
    block_count: [U64]
    value_pos: [U64]
    value_span: [U64]
    value_count: [U64]
    instr_span: [U64]
    instr_count: [U64]
    instr_off: [U64]
    instr_ids: [U64]
    param_span: [U64]
    param_ids: [U64]
    term_pos: [U64]
    term_span: [U64]
    op_instr_start: [U64]
    op_instr_count: [U64]
    op_instr_ids: [U64]
    op_term_start: [U64]
    op_term_count: [U64]
    op_term_ids: [U64]
    op_case_start: [U64]
    op_case_count: [U64]
    op_case_ids: [U64]
    tp_start: [U64]
    tp_count: [U64]
    tp_ids: [U64]
}

fn mir_v3_block(read: MirV3Read, function: U64, block: U64) -> U64 {
    if function == 0 || function > len(read.block_count) { return 0 }
    if block == 0 || block > read.block_count[function - 1] { return 0 }
    return read.block_pos[read.block_span[function - 1] + block - 1]
}
fn mir_v3_value(read: MirV3Read, function: U64, value: U64) -> U64 {
    if function == 0 || function > len(read.value_count) { return 0 }
    if value == 0 || value > read.value_count[function - 1] { return 0 }
    return read.value_pos[read.value_span[function - 1] + value - 1]
}
fn mir_v3_instr_count(read: MirV3Read, function: U64, block: U64) -> U64 {
    if mir_v3_block(read, function, block) == 0 { return 0 }
    return read.instr_count[read.block_span[function - 1] + block - 1]
}
fn mir_v3_instr(read: MirV3Read, function: U64, block: U64, ordinal: U64) -> U64 {
    if ordinal >= mir_v3_instr_count(read, function, block) { return 0 }
    let slot = read.block_span[function - 1] + block - 1
    return read.instr_ids[read.instr_span[function - 1] + read.instr_off[slot] + ordinal]
}
fn mir_v3_term(read: MirV3Read, function: U64, block: U64) -> U64 {
    if mir_v3_block(read, function, block) == 0 { return 0 }
    return read.term_pos[read.term_span[function - 1] + block - 1]
}
fn mir_v3_param_count(read: MirV3Read, function: U64) -> U64 {
    if function == 0 || function > len(read.param_span) { return 0 }
    if function < len(read.param_span) { return read.param_span[function] - read.param_span[function - 1] }
    return len(read.param_ids) - read.param_span[function - 1]
}
fn mir_v3_param(read: MirV3Read, function: U64, at: U64) -> U64 {
    if at >= mir_v3_param_count(read, function) { return 0 }
    return read.param_ids[read.param_span[function - 1] + at]
}
fn mir_v3_op_instr(read: MirV3Read, owner: U64, at: U64) -> U64 { return read.op_instr_ids[read.op_instr_start[owner - 1] + at] }
fn mir_v3_op_term(read: MirV3Read, owner: U64, at: U64) -> U64 { return read.op_term_ids[read.op_term_start[owner - 1] + at] }
fn mir_v3_op_case(read: MirV3Read, owner: U64, at: U64) -> U64 { return read.op_case_ids[read.op_case_start[owner - 1] + at] }
fn mir_v3_type_part(read: MirV3Read, owner: U64, at: U64) -> U64 { return read.tp_ids[read.tp_start[owner - 1] + at] }
