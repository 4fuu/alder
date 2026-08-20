fn mir_vop_produces(op: U64) -> Bool {
    return !(op == mir_op_store() || op == mir_op_domain_reset() || op == mir_op_domain_destroy() || op == mir_op_cleanup_disarm() || op == mir_op_cleanup_scope_run() || op == mir_op_cleanup_scope_end() || op == mir_op_table_view_end())
}
fn mir_vop_checked(op: U64) -> Bool {
    return op == mir_op_alloc_checked() || (op >= mir_op_int_add_checked() && op <= mir_op_int_shr_checked()) || op == mir_op_slice_index_checked() || op == mir_op_slice_range_checked() || op == mir_op_array_index_checked() || op == mir_op_enum_payload_checked()
}
fn mir_vop_required_mask(op: U64) -> U64 {
    // bits: a=1, b=2, c=4, place=8, type=16, target=32, name=64.
    if op == mir_op_load() || op == mir_op_borrow() || op == mir_op_borrow_mut() { return 8 }
    if op == mir_op_store() { return 9 }
    if op == mir_op_aggregate_construct() { return 16 }
    if op == mir_op_domain_create() || op == mir_op_domain_mark() || op == mir_op_domain_destroy() || op == mir_op_table_create() { return 1 }
    if op == mir_op_domain_reset() { return 3 }
    if op == mir_op_alloc() || op == mir_op_alloc_checked() { return 19 }
    if op == mir_op_copy_to_domain() { return 3 }
    if op == mir_op_cleanup_push() { return 33 }
    if op == mir_op_cleanup_disarm() || op == mir_op_cleanup_scope_run() || op == mir_op_cleanup_scope_end() { return 1 }
    if (op >= mir_op_int_add_checked() && op <= mir_op_int_shr_checked()) || (op >= mir_op_int_eq() && op <= mir_op_float_ge()) { return 3 }
    if op == mir_op_slice_len() { return 1 }
    if op == mir_op_slice_index_checked() || op == mir_op_array_index_checked() { return 3 }
    if op == mir_op_slice_range_checked() { return 7 }
    if op == mir_op_enum_payload_checked() { return 65 }
    if op == mir_op_enum_construct() { return 80 }
    if op == mir_op_table_insert() || op == mir_op_table_lookup() || op == mir_op_table_lookup_mut() || op == mir_op_table_remove() { return 3 }
    if op == mir_op_table_view_end() { return 1 }
    if op >= mir_op_int_trunc() && op <= mir_op_float_from_int() { return 17 }
    if op == mir_op_const_get() { return 64 }
    if op == mir_op_call() || op == mir_op_ffi_call_unsafe() { return 32 }
    return 0
}
// Flat (kind, owner) key for operand ordinal counting. Zero means the
// (kind, owner) pair is outside every owning table and keeps the legacy scan.
fn mir_v1q_operand_key(store: MirStore, o: MirOperandRec) -> U64 {
    let type_total = __s0_buffer_len(MirTypeRec, store.types)
    let import_total = __s0_buffer_len(MirImportRec, store.imports)
    let instr_total = __s0_buffer_len(MirInstrRec, store.instructions)
    let term_total = __s0_buffer_len(MirTermRec, store.terminators)
    let operand_total = __s0_buffer_len(MirOperandRec, store.operands)
    if o.kind == mir_operand_type_part() {
        if o.owner >= 1 && o.owner <= type_total { return o.owner }
        return 0
    }
    if o.kind == mir_operand_import_param() {
        if o.owner >= 1 && o.owner <= import_total { return type_total + o.owner }
        return 0
    }
    if o.kind == mir_operand_instruction() {
        if o.owner >= 1 && o.owner <= instr_total { return type_total + import_total + o.owner }
        return 0
    }
    if o.kind == mir_operand_checked_edge_arg() {
        if o.owner >= 1 && o.owner <= instr_total { return type_total + import_total + instr_total + o.owner }
        return 0
    }
    if o.kind == mir_operand_aggregate_field() {
        if o.owner >= 1 && o.owner <= instr_total { return type_total + import_total + instr_total * 2 + o.owner }
        return 0
    }
    if o.kind == mir_operand_terminator_arg() {
        if o.owner >= 1 && o.owner <= term_total { return type_total + import_total + instr_total * 3 + o.owner }
        return 0
    }
    if o.kind == mir_operand_switch_case() {
        if o.owner >= 1 && o.owner <= term_total { return type_total + import_total + instr_total * 3 + term_total + o.owner }
        return 0
    }
    if o.kind == mir_operand_switch_case_arg() {
        if o.owner >= 1 && o.owner <= operand_total { return type_total + import_total + instr_total * 3 + term_total * 2 + o.owner }
        return 0
    }
    return 0
}
fn mir_vphase1_types(d: Domain, store: MirStore, version: U64, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let type_count = __s0_buffer_len(MirTypeRec, store.types)
    if version < 1 || version > mir_format_version() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_version(), 0, 0, 0, 0, 0, 0, 0, 1, version, mir_format_version())) }
    if type_count < mir_primitive_type_count() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_missing_primitives(), 0, 0, 0, 0, 0, 0, 0, mir_primitive_type_count(), type_count, 0)) }
    var at: U64 = 0
    while at < type_count {
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        let id = at + 1
        if at < mir_primitive_type_count() {
            if t.kind != mir_type_kind_primitive() || t.name_start != 0 || t.name_end != 0 || t.elem != 0 || t.ok_type != 0 || t.err_type != 0 || t.first_part != 0 || t.part_count != 0 || t.result_type != 0 || t.length != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), 0, 0, 0, 0, 0, id, id, 0, t.kind, 0)) }
        } else {
            if t.kind > mir_type_kind_bytes() || t.kind == mir_type_kind_primitive() {
                out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_kind(), 0, 0, 0, 0, 0, id, id, mir_type_kind_bytes(), t.kind, 0))
            } else {
                let named = t.name_start != t.name_end
                let named_kind = t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum()
                if (named_kind && !named) || (!named_kind && named) || (named && !mir_vname_valid(store, t.name_start, t.name_end, true)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), 0, 0, 0, 0, 0, id, id, 0, 0, 0)) }
                let leaf = t.kind == mir_type_kind_string() || t.kind == mir_type_kind_bytes()
                if (t.kind != mir_type_kind_array() && t.length != 0) || (t.kind == mir_type_kind_array() && (t.elem == 0 || t.ok_type != 0 || t.err_type != 0 || t.first_part != 0 || t.part_count != 0 || t.result_type != 0)) || (leaf && (t.elem != 0 || t.ok_type != 0 || t.err_type != 0 || t.first_part != 0 || t.part_count != 0 || t.result_type != 0)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), 0, 0, 0, 0, 0, id, id, 0, t.kind, 0)) }
                var prior: U64 = mir_primitive_type_count()
                while named && prior < at {
                    let p = __s0_buffer_get(MirTypeRec, store.types, prior)
                    if mir_vname_equal(store, t.name_start, t.name_end, p.name_start, p.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), 0, 0, 0, 0, 0, id, id, 0, 0, prior + 1))
prior = at }
                    prior = prior + 1
                }
            }
        }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_declarations(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let constants = try mir_vindex_build_constants(d, store)
    // Per-function block segments: counting sort by function preserving store
    // order inside each segment. Only the missing-block probe uses them.
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    var b_counts = __s0_alloc(U64, d, function_count + 1)
    var bz: U64 = 0
    while bz <= function_count {
        b_counts[bz] = 0
        bz = bz + 1
    }
    var bat: U64 = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count { b_counts[bf] = b_counts[bf] + 1 }
        bat = bat + 1
    }
    var b_starts = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_starts[bz] = 0
        bz = bz + 1
    }
    var b_running: U64 = 0
    var bg: U64 = 1
    while bg <= function_count {
        b_starts[bg] = b_running
        b_running = b_running + b_counts[bg]
        bg = bg + 1
    }
    var b_ids = __s0_alloc(U64, d, b_running)
    bz = 0
    while bz < b_running {
        b_ids[bz] = 0
        bz = bz + 1
    }
    var b_cursor = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_cursor[bz] = 0
        bz = bz + 1
    }
    bat = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count {
            b_ids[b_starts[bf] + b_cursor[bf]] = bat + 1
            b_cursor[bf] = b_cursor[bf] + 1
        }
        bat = bat + 1
    }
    var at: U64 = 0
    // Module declarations: names and duplicates remain in storage order.
    at = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let item = __s0_buffer_get(MirImportRec, store.imports, at)
        if !mir_vname_valid(store, item.name_start, item.name_end, true) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), 0, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        var prior: U64 = 0
        while prior < at { let p = __s0_buffer_get(MirImportRec, store.imports, prior)
if mir_vname_equal(store, item.name_start, item.name_end, p.name_start, p.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), 0, 0, 0, 0, 0, 0, at + 1, 0, 0, prior + 1))
prior = at }
prior = prior + 1 }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let item = __s0_buffer_get(MirConstRec, store.constants, at)
        if !mir_vname_valid(store, item.name_start, item.name_end, true) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), 0, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        let prior = mir_vindex_const_slots(store, constants.slots, item.name_start, item.name_end)
        if prior != 0 && prior != at + 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), 0, 0, 0, 0, 0, 0, at + 1, 0, 0, prior)) }
        at = at + 1
    }
    at = 0
    while at < function_count {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
        if !mir_vname_valid(store, item.name_start, item.name_end, true) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), at + 1, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        var prior: U64 = 0
        while prior < at { let p = __s0_buffer_get(MirFunctionRec, store.functions, prior)
if mir_vname_equal(store, item.name_start, item.name_end, p.name_start, p.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), at + 1, 0, 0, 0, 0, 0, at + 1, 0, 0, prior + 1))
prior = at }
prior = prior + 1 }
        let bcount = b_counts[at + 1]
        var bk: U64 = 0
        var has_entry: U64 = 0
        while bk < bcount && has_entry == 0 {
            let bid = b_ids[b_starts[at + 1] + bk]
            if __s0_buffer_get(MirBlockRec, store.blocks, bid - 1).ordinal + 1 == 1 { has_entry = 1 }
            bk = bk + 1
        }
        if has_entry == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_missing_block(), at + 1, 0, 0, 0, 0, 0, at + 1, 1, 0, 0)) }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_params(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    // Dense ordinal block positions for block-owner presence.
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    var b_counts = __s0_alloc(U64, d, function_count + 1)
    var bz: U64 = 0
    while bz <= function_count {
        b_counts[bz] = 0
        bz = bz + 1
    }
    var bat: U64 = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count { b_counts[bf] = b_counts[bf] + 1 }
        bat = bat + 1
    }
    var b_starts = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_starts[bz] = 0
        bz = bz + 1
    }
    var b_running: U64 = 0
    var bg: U64 = 1
    while bg <= function_count {
        b_starts[bg] = b_running
        b_running = b_running + b_counts[bg]
        bg = bg + 1
    }
    var b_pos = __s0_alloc(U64, d, b_running)
    bz = 0
    while bz < b_running {
        b_pos[bz] = 0
        bz = bz + 1
    }
    bat = 0
    while bat < block_total {
        let brec = __s0_buffer_get(MirBlockRec, store.blocks, bat)
        let bf = brec.function
        if bf >= 1 && bf <= function_count && brec.ordinal < b_counts[bf] {
            let bslot = b_starts[bf] + brec.ordinal
            if b_pos[bslot] == 0 { b_pos[bslot] = bat + 1 }
        }
        bat = bat + 1
    }
    // Dense ordinal value positions for reciprocal value lookups.
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    var v_counts = __s0_alloc(U64, d, function_count + 1)
    var vz: U64 = 0
    while vz <= function_count {
        v_counts[vz] = 0
        vz = vz + 1
    }
    var vat: U64 = 0
    while vat < value_total {
        let vf = __s0_buffer_get(MirValueRec, store.values, vat).function
        if vf >= 1 && vf <= function_count { v_counts[vf] = v_counts[vf] + 1 }
        vat = vat + 1
    }
    var v_starts = __s0_alloc(U64, d, function_count + 1)
    vz = 0
    while vz <= function_count {
        v_starts[vz] = 0
        vz = vz + 1
    }
    var v_running: U64 = 0
    var vg: U64 = 1
    while vg <= function_count {
        v_starts[vg] = v_running
        v_running = v_running + v_counts[vg]
        vg = vg + 1
    }
    var v_pos = __s0_alloc(U64, d, v_running)
    vz = 0
    while vz < v_running {
        v_pos[vz] = 0
        vz = vz + 1
    }
    vat = 0
    while vat < value_total {
        let vrec = __s0_buffer_get(MirValueRec, store.values, vat)
        let vf = vrec.function
        if vf >= 1 && vf <= function_count && vrec.ordinal < v_counts[vf] {
            let vslot = v_starts[vf] + vrec.ordinal
            if v_pos[vslot] == 0 { v_pos[vslot] = vat + 1 }
        }
        vat = vat + 1
    }
    // Running (function, kind, block) counters for expected ordinals. Params
    // with invalid functions, unknown kinds, or out-of-range blocks keep the
    // legacy prior scan.
    let param_total = __s0_buffer_len(MirParamRec, store.params)
    let pe_total = (b_running + function_count) * 2
    var pe_seen = __s0_alloc(U64, d, pe_total + 1)
    var pez: U64 = 0
    while pez <= pe_total {
        pe_seen[pez] = 0
        pez = pez + 1
    }
    var at: U64 = 0
    // Every owner-local table is checked directly; builders are not trusted.
    at = 0
    while at < param_total {
        let p = __s0_buffer_get(MirParamRec, store.params, at)
        var block_ok = p.kind != mir_param_block()
        if p.kind == mir_param_block() {
            if p.function >= 1 && p.function <= function_count && p.block >= 1 && p.block <= b_counts[p.function] {
                block_ok = b_pos[b_starts[p.function] + p.block - 1] != 0
            } else {
                block_ok = mir_vblock_index(store, p.function, p.block) != 0
            }
        }
        if !mir_vfunction_exists(store, p.function) || (p.kind != mir_param_function() && p.kind != mir_param_block()) || (p.kind == mir_param_function() && p.block != 0) || !block_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), p.function, p.block, 0, 0, 0, 0, at + 1, 0, p.kind, 0)) }
        if !mir_vname_valid(store, p.name_start, p.name_end, false) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), p.function, p.block, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        var expected: U64 = 0
        if p.function >= 1 && p.function <= function_count {
            if (p.kind == mir_param_function() || p.kind == mir_param_block()) && p.block <= b_counts[p.function] {
                let pkey = (b_starts[p.function] + (p.function - 1) + p.block) * 2 + p.kind - 1
                expected = pe_seen[pkey]
                pe_seen[pkey] = expected + 1
            } else {
                var scan: U64 = 0
                while scan < at { let q = __s0_buffer_get(MirParamRec, store.params, scan)
if q.kind == p.kind && q.function == p.function && q.block == p.block { expected = expected + 1 }
scan = scan + 1 }
            }
        } else {
            var scan: U64 = 0
            while scan < at { let q = __s0_buffer_get(MirParamRec, store.params, scan)
if q.kind == p.kind && q.function == p.function && q.block == p.block { expected = expected + 1 }
scan = scan + 1 }
        }
        if p.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), p.function, p.block, 0, 0, 0, 0, at + 1, expected, p.ordinal, 0)) }
        var vi: U64 = 0
        if p.value == 0 { vi = 0 } else { if p.function >= 1 && p.function <= function_count && p.value >= 1 && p.value <= v_counts[p.function] {
            vi = v_pos[v_starts[p.function] + p.value - 1]
        } else {
            vi = mir_vvalue_index(store, p.function, p.value)
        } }
        if vi == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), p.function, p.block, 0, 0, 0, 0, at + 1, 1, 0, p.value)) } else { let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
var want = mir_value_def_function_param()
if p.kind == mir_param_block() { want = mir_value_def_block_param() }
if v.def_kind != want || v.block != p.block || v.item != p.ordinal + 1 || v.value_type != p.param_type { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), p.function, p.block, 0, 0, 0, 0, at + 1, want, v.def_kind, p.value)) } }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_locals(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let local_total = __s0_buffer_len(MirLocalRec, store.locals)
    var seen = __s0_alloc(U64, d, function_count + 1)
    var sz: U64 = 0
    while sz <= function_count {
        seen[sz] = 0
        sz = sz + 1
    }
    let local_names = try mir_vindex_build_local_names(d, store)
    var at: U64 = 0
    at = 0
    while at < local_total {
        let item = __s0_buffer_get(MirLocalRec, store.locals, at)
        var expected: U64 = 0
        if item.function >= 1 && item.function <= function_count {
            expected = seen[item.function]
            seen[item.function] = expected + 1
        } else {
            var scan: U64 = 0
            while scan < at { if __s0_buffer_get(MirLocalRec, store.locals, scan).function == item.function { expected = expected + 1 }
scan = scan + 1 }
        }
        if !mir_vfunction_exists(store, item.function) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), item.function, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        if item.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), item.function, 0, 0, 0, 0, 0, at + 1, expected, item.ordinal, 0)) }
        if !mir_vname_valid(store, item.name_start, item.name_end, false) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), item.function, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        var dup = mir_vindex_local_name(store, local_names, item.function, item.name_start, item.name_end)
        if dup == at + 1 { dup = 0 }
        if dup != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), item.function, 0, 0, 0, 0, 0, at + 1, 0, 0, dup)) }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_blocks(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    var seen = __s0_alloc(U64, d, function_count + 1)
    var sz: U64 = 0
    while sz <= function_count {
        seen[sz] = 0
        sz = sz + 1
    }
    var at: U64 = 0
    at = 0
    while at < block_total {
        let item = __s0_buffer_get(MirBlockRec, store.blocks, at)
        var expected: U64 = 0
        if item.function >= 1 && item.function <= function_count {
            expected = seen[item.function]
            seen[item.function] = expected + 1
        } else {
            var scan: U64 = 0
            while scan < at { if __s0_buffer_get(MirBlockRec, store.blocks, scan).function == item.function { expected = expected + 1 }
scan = scan + 1 }
        }
        if !mir_vfunction_exists(store, item.function) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), item.function, item.ordinal + 1, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        if item.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), item.function, item.ordinal + 1, 0, 0, 0, 0, at + 1, expected, item.ordinal, 0)) }
        if !mir_vname_valid(store, item.name_start, item.name_end, true) || mir_vname_word(store, item.name_start, item.name_end, "else") { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), item.function, item.ordinal + 1, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_values(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    let value_names = try mir_vindex_build_value_names(d, store)
    var seen = __s0_alloc(U64, d, function_count + 1)
    var sz: U64 = 0
    while sz <= function_count {
        seen[sz] = 0
        sz = sz + 1
    }
    // Dense ordinal block positions for block-reference presence.
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    var b_counts = __s0_alloc(U64, d, function_count + 1)
    var bz: U64 = 0
    while bz <= function_count {
        b_counts[bz] = 0
        bz = bz + 1
    }
    var bat: U64 = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count { b_counts[bf] = b_counts[bf] + 1 }
        bat = bat + 1
    }
    var b_starts = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_starts[bz] = 0
        bz = bz + 1
    }
    var b_running: U64 = 0
    var bg: U64 = 1
    while bg <= function_count {
        b_starts[bg] = b_running
        b_running = b_running + b_counts[bg]
        bg = bg + 1
    }
    var b_pos = __s0_alloc(U64, d, b_running)
    bz = 0
    while bz < b_running {
        b_pos[bz] = 0
        bz = bz + 1
    }
    bat = 0
    while bat < block_total {
        let brec = __s0_buffer_get(MirBlockRec, store.blocks, bat)
        let bf = brec.function
        if bf >= 1 && bf <= function_count && brec.ordinal < b_counts[bf] {
            let bslot = b_starts[bf] + brec.ordinal
            if b_pos[bslot] == 0 { b_pos[bslot] = bat + 1 }
        }
        bat = bat + 1
    }
    // Params keyed by (function, block) with block zero reserved for function
    // parameters, then by ordinal within the segment. Block zero and the
    // in-range block slots share one key space of b_running + function_count.
    let param_total = __s0_buffer_len(MirParamRec, store.params)
    let pkey_total = b_running + function_count
    var p2_counts = __s0_alloc(U64, d, pkey_total + 1)
    var pz: U64 = 0
    while pz <= pkey_total {
        p2_counts[pz] = 0
        pz = pz + 1
    }
    var pat: U64 = 0
    while pat < param_total {
        let prec = __s0_buffer_get(MirParamRec, store.params, pat)
        if prec.function >= 1 && prec.function <= function_count && prec.block <= b_counts[prec.function] {
            p2_counts[b_starts[prec.function] + (prec.function - 1) + prec.block] = p2_counts[b_starts[prec.function] + (prec.function - 1) + prec.block] + 1
        }
        pat = pat + 1
    }
    var p2_starts = __s0_alloc(U64, d, pkey_total + 1)
    pz = 0
    while pz <= pkey_total {
        p2_starts[pz] = 0
        pz = pz + 1
    }
    var p2_running: U64 = 0
    var pg: U64 = 0
    while pg <= pkey_total {
        p2_starts[pg] = p2_running
        p2_running = p2_running + p2_counts[pg]
        pg = pg + 1
    }
    var p2_pos = __s0_alloc(U64, d, p2_running)
    pz = 0
    while pz < p2_running {
        p2_pos[pz] = 0
        pz = pz + 1
    }
    var p2_coll = __s0_alloc(U64, d, p2_running)
    pz = 0
    while pz < p2_running {
        p2_coll[pz] = 0
        pz = pz + 1
    }
    pat = 0
    while pat < param_total {
        let prec = __s0_buffer_get(MirParamRec, store.params, pat)
        if prec.function >= 1 && prec.function <= function_count && prec.block <= b_counts[prec.function] {
            let pkey = b_starts[prec.function] + (prec.function - 1) + prec.block
            if prec.ordinal < p2_counts[pkey] {
                let pslot = p2_starts[pkey] + prec.ordinal
                if p2_pos[pslot] == 0 { p2_pos[pslot] = pat + 1 } else { p2_coll[pslot] = 1 }
            }
        }
        pat = pat + 1
    }
    // Instructions keyed by (function, block) slot and ordinal. Records with
    // out-of-range blocks or ordinals are never placed and keep the legacy
    // scans.
    let instr_total = __s0_buffer_len(MirInstrRec, store.instructions)
    var ord_counts = __s0_alloc(U64, d, b_running + 1)
    var oz: U64 = 0
    while oz <= b_running {
        ord_counts[oz] = 0
        oz = oz + 1
    }
    var iat: U64 = 0
    while iat < instr_total {
        let irec = __s0_buffer_get(MirInstrRec, store.instructions, iat)
        if irec.function >= 1 && irec.function <= function_count && irec.block >= 1 && irec.block <= b_counts[irec.function] {
            let ikey = b_starts[irec.function] + irec.block
            ord_counts[ikey] = ord_counts[ikey] + 1
        }
        iat = iat + 1
    }
    var ord_starts = __s0_alloc(U64, d, b_running + 1)
    oz = 0
    while oz <= b_running {
        ord_starts[oz] = 0
        oz = oz + 1
    }
    var ord_running: U64 = 0
    var ig: U64 = 1
    while ig <= b_running {
        ord_starts[ig] = ord_running
        ord_running = ord_running + ord_counts[ig]
        ig = ig + 1
    }
    var i_pos = __s0_alloc(U64, d, ord_running)
    oz = 0
    while oz < ord_running {
        i_pos[oz] = 0
        oz = oz + 1
    }
    var i_coll = __s0_alloc(U64, d, ord_running)
    oz = 0
    while oz < ord_running {
        i_coll[oz] = 0
        oz = oz + 1
    }
    iat = 0
    while iat < instr_total {
        let irec = __s0_buffer_get(MirInstrRec, store.instructions, iat)
        if irec.function >= 1 && irec.function <= function_count && irec.block >= 1 && irec.block <= b_counts[irec.function] {
            let ikey = b_starts[irec.function] + irec.block
            if irec.ordinal < ord_counts[ikey] {
                let islot = ord_starts[ikey] + irec.ordinal
                if i_pos[islot] == 0 { i_pos[islot] = iat + 1 } else { i_coll[islot] = 1 }
            }
        }
        iat = iat + 1
    }
    // Switch-case operands keyed by their owner terminator's (function,
    // block) slot and case ordinal. An operand whose owner is not a valid
    // terminator can never match a valid function value's reciprocal scan, so
    // excluding it is exact.
    let term_total = __s0_buffer_len(MirTermRec, store.terminators)
    let operand_total = __s0_buffer_len(MirOperandRec, store.operands)
    var s_counts = __s0_alloc(U64, d, b_running + 1)
    var sz2: U64 = 0
    while sz2 <= b_running {
        s_counts[sz2] = 0
        sz2 = sz2 + 1
    }
    var sat: U64 = 0
    while sat < operand_total {
        let so = __s0_buffer_get(MirOperandRec, store.operands, sat)
        if so.kind == mir_operand_switch_case() && mir_vid_valid(so.owner, term_total) {
            let sterm = __s0_buffer_get(MirTermRec, store.terminators, so.owner - 1)
            if sterm.function >= 1 && sterm.function <= function_count && sterm.block >= 1 && sterm.block <= b_counts[sterm.function] {
                let skey = b_starts[sterm.function] + sterm.block
                s_counts[skey] = s_counts[skey] + 1
            }
        }
        sat = sat + 1
    }
    var s_starts = __s0_alloc(U64, d, b_running + 1)
    sz2 = 0
    while sz2 <= b_running {
        s_starts[sz2] = 0
        sz2 = sz2 + 1
    }
    var s_running: U64 = 0
    var sg: U64 = 1
    while sg <= b_running {
        s_starts[sg] = s_running
        s_running = s_running + s_counts[sg]
        sg = sg + 1
    }
    var s_pos = __s0_alloc(U64, d, s_running)
    sz2 = 0
    while sz2 < s_running {
        s_pos[sz2] = 0
        sz2 = sz2 + 1
    }
    var s_coll = __s0_alloc(U64, d, s_running)
    sz2 = 0
    while sz2 < s_running {
        s_coll[sz2] = 0
        sz2 = sz2 + 1
    }
    sat = 0
    while sat < operand_total {
        let so = __s0_buffer_get(MirOperandRec, store.operands, sat)
        if so.kind == mir_operand_switch_case() && mir_vid_valid(so.owner, term_total) {
            let sterm = __s0_buffer_get(MirTermRec, store.terminators, so.owner - 1)
            if sterm.function >= 1 && sterm.function <= function_count && sterm.block >= 1 && sterm.block <= b_counts[sterm.function] {
                let skey = b_starts[sterm.function] + sterm.block
                if so.ordinal < s_counts[skey] {
                    let sslot = s_starts[skey] + so.ordinal
                    if s_pos[sslot] == 0 { s_pos[sslot] = sat + 1 } else { s_coll[sslot] = 1 }
                }
            }
        }
        sat = sat + 1
    }
    var at: U64 = 0
    at = 0
    while at < value_total {
        let v = __s0_buffer_get(MirValueRec, store.values, at)
        var expected: U64 = 0
        if v.function >= 1 && v.function <= function_count {
            expected = seen[v.function]
            seen[v.function] = expected + 1
        } else {
            var scan: U64 = 0
            while scan < at { if __s0_buffer_get(MirValueRec, store.values, scan).function == v.function { expected = expected + 1 }
scan = scan + 1 }
        }
        if !mir_vfunction_exists(store, v.function) || v.def_kind > mir_value_def_switch_case() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, v.def_kind, 0)) }
        if v.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), v.function, v.block, 0, 0, 0, 0, at + 1, expected, v.ordinal, 0)) }
        if !mir_vname_valid(store, v.name_start, v.name_end, false) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        let dup = mir_vindex_value_name(store, value_names, v.function, v.name_start, v.name_end)
        if dup != 0 && dup != at + 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, 0, dup)) }
        var block_ok = v.def_kind == mir_value_def_function_param()
        if !block_ok {
            if v.function >= 1 && v.function <= function_count && v.block >= 1 && v.block <= b_counts[v.function] {
                block_ok = b_pos[b_starts[v.function] + v.block - 1] != 0
            } else {
                block_ok = mir_vblock_index(store, v.function, v.block) != 0
            }
        }
        if !block_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, 0, v.block)) }
        var reciprocal: U64 = 0
        if v.def_kind == mir_value_def_function_param() || v.def_kind == mir_value_def_block_param() {
            if v.function >= 1 && v.function <= function_count && v.block <= b_counts[v.function] {
                let pkey = b_starts[v.function] + (v.function - 1) + v.block
                if v.item >= 1 && v.item <= p2_counts[pkey] {
                    let pslot = p2_starts[pkey] + v.item - 1
                    if p2_coll[pslot] == 0 {
                        let pid = p2_pos[pslot]
                        if pid != 0 {
                            let p = __s0_buffer_get(MirParamRec, store.params, pid - 1)
                            if p.value == v.ordinal + 1 { reciprocal = reciprocal + 1 }
                        }
                    } else { var pi: U64 = 0
while pi < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, pi)
if p.function == v.function && p.block == v.block && p.ordinal + 1 == v.item && p.value == v.ordinal + 1 { reciprocal = reciprocal + 1 }
pi = pi + 1 } }
                } else { var pi: U64 = 0
while pi < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, pi)
if p.function == v.function && p.block == v.block && p.ordinal + 1 == v.item && p.value == v.ordinal + 1 { reciprocal = reciprocal + 1 }
pi = pi + 1 } }
            } else { var pi: U64 = 0
while pi < __s0_buffer_len(MirParamRec, store.params) { let p = __s0_buffer_get(MirParamRec, store.params, pi)
if p.function == v.function && p.block == v.block && p.ordinal + 1 == v.item && p.value == v.ordinal + 1 { reciprocal = reciprocal + 1 }
pi = pi + 1 } }
        }
        if v.def_kind == mir_value_def_instruction() {
            if v.function >= 1 && v.function <= function_count && v.block >= 1 && v.block <= b_counts[v.function] {
                let ikey = b_starts[v.function] + v.block
                if v.item >= 1 && v.item <= ord_counts[ikey] {
                    let islot = ord_starts[ikey] + v.item - 1
                    if i_coll[islot] == 0 {
                        let iid = i_pos[islot]
                        if iid != 0 {
                            let ins = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                            if ins.result == v.ordinal + 1 { reciprocal = reciprocal + 1 }
                        }
                    } else { var ii: U64 = 0
while ii < __s0_buffer_len(MirInstrRec, store.instructions) { let i = __s0_buffer_get(MirInstrRec, store.instructions, ii)
if i.function == v.function && i.block == v.block && i.ordinal + 1 == v.item && i.result == v.ordinal + 1 { reciprocal = reciprocal + 1 }
ii = ii + 1 } }
                } else { var ii: U64 = 0
while ii < __s0_buffer_len(MirInstrRec, store.instructions) { let i = __s0_buffer_get(MirInstrRec, store.instructions, ii)
if i.function == v.function && i.block == v.block && i.ordinal + 1 == v.item && i.result == v.ordinal + 1 { reciprocal = reciprocal + 1 }
ii = ii + 1 } }
            } else { var ii: U64 = 0
while ii < __s0_buffer_len(MirInstrRec, store.instructions) { let i = __s0_buffer_get(MirInstrRec, store.instructions, ii)
if i.function == v.function && i.block == v.block && i.ordinal + 1 == v.item && i.result == v.ordinal + 1 { reciprocal = reciprocal + 1 }
ii = ii + 1 } }
        }
        if v.def_kind == mir_value_def_switch_case() {
            if v.function >= 1 && v.function <= function_count && v.block >= 1 && v.block <= b_counts[v.function] {
                let skey = b_starts[v.function] + v.block
                if v.item >= 1 && v.item <= s_counts[skey] {
                    let sslot = s_starts[skey] + v.item - 1
                    if s_coll[sslot] == 0 {
                        let sid = s_pos[sslot]
                        if sid != 0 {
                            let so = __s0_buffer_get(MirOperandRec, store.operands, sid - 1)
                            if so.value == v.ordinal + 1 { reciprocal = reciprocal + 1 }
                        }
                    } else { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
if o.kind == mir_operand_switch_case() && o.ordinal + 1 == v.item && o.value == v.ordinal + 1 && mir_vid_valid(o.owner, __s0_buffer_len(MirTermRec, store.terminators)) { let term = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1)
if term.function == v.function && term.block == v.block { reciprocal = reciprocal + 1 } }
oi = oi + 1 } }
                } else { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
if o.kind == mir_operand_switch_case() && o.ordinal + 1 == v.item && o.value == v.ordinal + 1 && mir_vid_valid(o.owner, __s0_buffer_len(MirTermRec, store.terminators)) { let term = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1)
if term.function == v.function && term.block == v.block { reciprocal = reciprocal + 1 } }
oi = oi + 1 } }
            } else { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let o = __s0_buffer_get(MirOperandRec, store.operands, oi)
if o.kind == mir_operand_switch_case() && o.ordinal + 1 == v.item && o.value == v.ordinal + 1 && mir_vid_valid(o.owner, __s0_buffer_len(MirTermRec, store.terminators)) { let term = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1)
if term.function == v.function && term.block == v.block { reciprocal = reciprocal + 1 } }
oi = oi + 1 } }
        }
        if reciprocal != 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), v.function, v.block, 0, 0, 0, 0, at + 1, 1, reciprocal, v.item)) }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_places(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let place_total = __s0_buffer_len(MirPlaceRec, store.places)
    // Dense ordinal local positions for local-reference presence.
    let local_total = __s0_buffer_len(MirLocalRec, store.locals)
    var l_counts = __s0_alloc(U64, d, function_count + 1)
    var lz: U64 = 0
    while lz <= function_count {
        l_counts[lz] = 0
        lz = lz + 1
    }
    var lat: U64 = 0
    while lat < local_total {
        let lf = __s0_buffer_get(MirLocalRec, store.locals, lat).function
        if lf >= 1 && lf <= function_count { l_counts[lf] = l_counts[lf] + 1 }
        lat = lat + 1
    }
    var l_starts = __s0_alloc(U64, d, function_count + 1)
    lz = 0
    while lz <= function_count {
        l_starts[lz] = 0
        lz = lz + 1
    }
    var l_running: U64 = 0
    var lg: U64 = 1
    while lg <= function_count {
        l_starts[lg] = l_running
        l_running = l_running + l_counts[lg]
        lg = lg + 1
    }
    var l_pos = __s0_alloc(U64, d, l_running)
    lz = 0
    while lz < l_running {
        l_pos[lz] = 0
        lz = lz + 1
    }
    lat = 0
    while lat < local_total {
        let lrec = __s0_buffer_get(MirLocalRec, store.locals, lat)
        let lf = lrec.function
        if lf >= 1 && lf <= function_count && lrec.ordinal < l_counts[lf] {
            let lslot = l_starts[lf] + lrec.ordinal
            if l_pos[lslot] == 0 { l_pos[lslot] = lat + 1 }
        }
        lat = lat + 1
    }
    // Dense ordinal value positions for deref-value presence.
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    var v_counts = __s0_alloc(U64, d, function_count + 1)
    var vz: U64 = 0
    while vz <= function_count {
        v_counts[vz] = 0
        vz = vz + 1
    }
    var vat: U64 = 0
    while vat < value_total {
        let vf = __s0_buffer_get(MirValueRec, store.values, vat).function
        if vf >= 1 && vf <= function_count { v_counts[vf] = v_counts[vf] + 1 }
        vat = vat + 1
    }
    var v_starts = __s0_alloc(U64, d, function_count + 1)
    vz = 0
    while vz <= function_count {
        v_starts[vz] = 0
        vz = vz + 1
    }
    var v_running: U64 = 0
    var vg: U64 = 1
    while vg <= function_count {
        v_starts[vg] = v_running
        v_running = v_running + v_counts[vg]
        vg = vg + 1
    }
    var v_pos = __s0_alloc(U64, d, v_running)
    vz = 0
    while vz < v_running {
        v_pos[vz] = 0
        vz = vz + 1
    }
    vat = 0
    while vat < value_total {
        let vrec = __s0_buffer_get(MirValueRec, store.values, vat)
        let vf = vrec.function
        if vf >= 1 && vf <= function_count && vrec.ordinal < v_counts[vf] {
            let vslot = v_starts[vf] + vrec.ordinal
            if v_pos[vslot] == 0 { v_pos[vslot] = vat + 1 }
        }
        vat = vat + 1
    }
    var at: U64 = 0
    // Instructions, places, and terminators use only range-checked lookups.
    at = 0
    while at < place_total {
        let p = __s0_buffer_get(MirPlaceRec, store.places, at)
        if !mir_vfunction_exists(store, p.function) || p.kind > mir_place_deref() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, mir_place_deref(), p.kind, 0)) }
        if p.kind == mir_place_local() {
            var local_ok = false
            if p.function >= 1 && p.function <= function_count && p.local >= 1 && p.local <= l_counts[p.function] {
                local_ok = l_pos[l_starts[p.function] + p.local - 1] != 0
            } else {
                local_ok = mir_vlocal_index(store, p.function, p.local) != 0
            }
            if !local_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.local)) }
        }
        if p.kind == mir_place_field() && (!mir_vid_valid(p.base, place_total) || !mir_vname_valid(store, p.field_start, p.field_end, true)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.base)) }
        if p.kind == mir_place_deref() {
            var value_ok = false
            if p.function >= 1 && p.function <= function_count && p.deref_value >= 1 && p.deref_value <= v_counts[p.function] {
                value_ok = v_pos[v_starts[p.function] + p.deref_value - 1] != 0
            } else {
                value_ok = mir_vvalue_index(store, p.function, p.deref_value) != 0
            }
            if !value_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.deref_value)) }
        }
        if p.kind == mir_place_field() { var next = p.base
var steps: U64 = 0
while mir_vid_valid(next, place_total) && steps <= place_total { let base = __s0_buffer_get(MirPlaceRec, store.places, next - 1)
if base.function != p.function { steps = place_total + 2 } else { if base.kind == mir_place_field() { next = base.base } else { next = 0 } }
steps = steps + 1 }
if steps > place_total { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.base)) } }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_instructions(d: Domain, store: MirStore, version: U64, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    // Dense ordinal block positions plus the (function, block) ordinal
    // counters keyed by segment base + block.
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    var b_counts = __s0_alloc(U64, d, function_count + 1)
    var bz: U64 = 0
    while bz <= function_count {
        b_counts[bz] = 0
        bz = bz + 1
    }
    var bat: U64 = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count { b_counts[bf] = b_counts[bf] + 1 }
        bat = bat + 1
    }
    var b_starts = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_starts[bz] = 0
        bz = bz + 1
    }
    var b_running: U64 = 0
    var bg: U64 = 1
    while bg <= function_count {
        b_starts[bg] = b_running
        b_running = b_running + b_counts[bg]
        bg = bg + 1
    }
    var b_pos = __s0_alloc(U64, d, b_running)
    bz = 0
    while bz < b_running {
        b_pos[bz] = 0
        bz = bz + 1
    }
    bat = 0
    while bat < block_total {
        let brec = __s0_buffer_get(MirBlockRec, store.blocks, bat)
        let bf = brec.function
        if bf >= 1 && bf <= function_count && brec.ordinal < b_counts[bf] {
            let bslot = b_starts[bf] + brec.ordinal
            if b_pos[bslot] == 0 { b_pos[bslot] = bat + 1 }
        }
        bat = bat + 1
    }
    let instr_total = __s0_buffer_len(MirInstrRec, store.instructions)
    var ord_counts = __s0_alloc(U64, d, b_running + 1)
    var oz: U64 = 0
    while oz <= b_running {
        ord_counts[oz] = 0
        oz = oz + 1
    }
    // Dense ordinal value positions for operand and result lookups.
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    var v_counts = __s0_alloc(U64, d, function_count + 1)
    var vz: U64 = 0
    while vz <= function_count {
        v_counts[vz] = 0
        vz = vz + 1
    }
    var vat: U64 = 0
    while vat < value_total {
        let vf = __s0_buffer_get(MirValueRec, store.values, vat).function
        if vf >= 1 && vf <= function_count { v_counts[vf] = v_counts[vf] + 1 }
        vat = vat + 1
    }
    var v_starts = __s0_alloc(U64, d, function_count + 1)
    vz = 0
    while vz <= function_count {
        v_starts[vz] = 0
        vz = vz + 1
    }
    var v_running: U64 = 0
    var vg: U64 = 1
    while vg <= function_count {
        v_starts[vg] = v_running
        v_running = v_running + v_counts[vg]
        vg = vg + 1
    }
    var v_pos = __s0_alloc(U64, d, v_running)
    vz = 0
    while vz < v_running {
        v_pos[vz] = 0
        vz = vz + 1
    }
    vat = 0
    while vat < value_total {
        let vrec = __s0_buffer_get(MirValueRec, store.values, vat)
        let vf = vrec.function
        if vf >= 1 && vf <= function_count && vrec.ordinal < v_counts[vf] {
            let vslot = v_starts[vf] + vrec.ordinal
            if v_pos[vslot] == 0 { v_pos[vslot] = vat + 1 }
        }
        vat = vat + 1
    }
    // Per-owner instruction counts for the checked failure-argument arity.
    let operand_total = __s0_buffer_len(MirOperandRec, store.operands)
    var fail_counts = __s0_alloc(U64, d, instr_total + 1)
    var fz: U64 = 0
    while fz <= instr_total {
        fail_counts[fz] = 0
        fz = fz + 1
    }
    var fat: U64 = 0
    while fat < operand_total {
        let fo = __s0_buffer_get(MirOperandRec, store.operands, fat)
        if fo.kind == mir_operand_checked_edge_arg() && fo.owner >= 1 && fo.owner <= instr_total && fo.edge == 0 { fail_counts[fo.owner] = fail_counts[fo.owner] + 1 }
        fat = fat + 1
    }
    var at: U64 = 0
    at = 0
    while at < instr_total {
        let i = __s0_buffer_get(MirInstrRec, store.instructions, at)
        let id = at + 1
        var expected: U64 = 0
        if i.function >= 1 && i.function <= function_count && i.block >= 1 && i.block <= b_counts[i.function] {
            let key = b_starts[i.function] + i.block
            expected = ord_counts[key]
            ord_counts[key] = expected + 1
        } else {
            var scan: U64 = 0
            while scan < at { let q = __s0_buffer_get(MirInstrRec, store.instructions, scan)
if q.function == i.function && q.block == i.block { expected = expected + 1 }
scan = scan + 1 }
        }
        var block_ok = false
        if i.function >= 1 && i.function <= function_count && i.block >= 1 && i.block <= b_counts[i.function] {
            block_ok = b_pos[b_starts[i.function] + i.block - 1] != 0
        } else {
            block_ok = mir_vblock_index(store, i.function, i.block) != 0
        }
        if !mir_vfunction_exists(store, i.function) || !block_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), i.function, i.block, id, 0, 0, 0, id, 0, 0, 0)) }
        if i.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), i.function, i.block, id, 0, 0, 0, id, expected, i.ordinal, 0)) }
        if i.op > mir_op_array_index_checked() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_kind(), i.function, i.block, id, 0, 0, 0, id, mir_op_array_index_checked(), i.op, 0)) } else {
            let produces = mir_vop_produces(i.op)
            let has_result = i.result != 0
            var droppable = false
            if i.op == mir_op_call() && mir_vid_valid(i.target, function_count) && __s0_buffer_get(MirFunctionRec, store.functions, i.target - 1).result_type == mir_type_unit() { droppable = true }
            if i.op == mir_op_ffi_call_unsafe() && mir_vid_valid(i.target, __s0_buffer_len(MirImportRec, store.imports)) && __s0_buffer_get(MirImportRec, store.imports, i.target - 1).result_type == mir_type_unit() { droppable = true }
            if (produces && !has_result && !droppable) || (!produces && has_result) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_result(), i.function, i.block, id, 0, 0, 0, id, 0, i.result, 0)) }
            let fail_count = fail_counts[id]
            let checked = mir_vop_checked(i.op)
            let has_fail = checked && i.target != 0
            if checked && !has_fail { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_failure_edge(), i.function, i.block, id, 0, 0, 0, id, 0, fail_count, 0)) }
            let mask = mir_vop_required_mask(i.op)
            if ((mask % 2 == 1) && i.a == 0) || (((mask / 2) % 2 == 1) && i.b == 0) || (((mask / 4) % 2 == 1) && i.c == 0) || (((mask / 8) % 2 == 1) && i.place == 0) || (((mask / 16) % 2 == 1) && i.type_op == 0) || (((mask / 32) % 2 == 1) && i.target == 0) || (((mask / 64) % 2 == 1) && i.name_start == i.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), i.function, i.block, id, 0, 0, 0, id, mask, 0, 0)) }
            var a_ok = i.a == 0
            var b_ok = i.b == 0
            var c_ok = i.c == 0
            if !a_ok {
                if i.function >= 1 && i.function <= function_count && i.a >= 1 && i.a <= v_counts[i.function] {
                    a_ok = v_pos[v_starts[i.function] + i.a - 1] != 0
                } else {
                    a_ok = mir_vvalue_index(store, i.function, i.a) != 0
                }
            }
            if !b_ok {
                if i.function >= 1 && i.function <= function_count && i.b >= 1 && i.b <= v_counts[i.function] {
                    b_ok = v_pos[v_starts[i.function] + i.b - 1] != 0
                } else {
                    b_ok = mir_vvalue_index(store, i.function, i.b) != 0
                }
            }
            if !c_ok {
                if i.function >= 1 && i.function <= function_count && i.c >= 1 && i.c <= v_counts[i.function] {
                    c_ok = v_pos[v_starts[i.function] + i.c - 1] != 0
                } else {
                    c_ok = mir_vvalue_index(store, i.function, i.c) != 0
                }
            }
            if !a_ok || !b_ok || !c_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.a)) }
            if i.place != 0 && !mir_vid_valid(i.place, __s0_buffer_len(MirPlaceRec, store.places)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.place)) }
            if ((mask / 16) % 2 == 1) && !mir_vtype_exists(store, i.type_op) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, i.type_op, id, 0, 0, i.type_op)) }
            if (i.op == mir_op_call() || i.op == mir_op_cleanup_push()) && !mir_vid_valid(i.target, function_count) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.target)) }
            if i.op == mir_op_ffi_call_unsafe() && !mir_vid_valid(i.target, __s0_buffer_len(MirImportRec, store.imports)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.target)) }
            if i.result != 0 { var vi: U64 = 0
                if i.function >= 1 && i.function <= function_count && i.result >= 1 && i.result <= v_counts[i.function] {
                    vi = v_pos[v_starts[i.function] + i.result - 1]
                } else {
                    vi = mir_vvalue_index(store, i.function, i.result)
                }
                if vi == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), i.function, i.block, id, 0, 0, 0, id, 1, 0, i.result)) } else { let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if v.def_kind != mir_value_def_instruction() || v.block != i.block || v.item != i.ordinal + 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), i.function, i.block, id, 0, 0, 0, id, i.ordinal + 1, v.item, i.result)) } } }
            if i.op == mir_op_alloc_checked() && version < 3 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_version_gate(), i.function, i.block, id, 0, 0, 0, id, 3, version, 0)) }
        }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_terminators(d: Domain, store: MirStore, version: U64, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let term_total = __s0_buffer_len(MirTermRec, store.terminators)
    // Per-function block segments for block-owner presence.
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    var b_counts = __s0_alloc(U64, d, function_count + 1)
    var bz: U64 = 0
    while bz <= function_count {
        b_counts[bz] = 0
        bz = bz + 1
    }
    var bat: U64 = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count { b_counts[bf] = b_counts[bf] + 1 }
        bat = bat + 1
    }
    var b_starts = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_starts[bz] = 0
        bz = bz + 1
    }
    var b_running: U64 = 0
    var bg: U64 = 1
    while bg <= function_count {
        b_starts[bg] = b_running
        b_running = b_running + b_counts[bg]
        bg = bg + 1
    }
    var b_pos = __s0_alloc(U64, d, b_running)
    bz = 0
    while bz < b_running {
        b_pos[bz] = 0
        bz = bz + 1
    }
    bat = 0
    while bat < block_total {
        let brec = __s0_buffer_get(MirBlockRec, store.blocks, bat)
        let bf = brec.function
        if bf >= 1 && bf <= function_count && brec.ordinal < b_counts[bf] {
            let bslot = b_starts[bf] + brec.ordinal
            if b_pos[bslot] == 0 { b_pos[bslot] = bat + 1 }
        }
        bat = bat + 1
    }
    // Dense ordinal value positions for value presence.
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    var v_counts = __s0_alloc(U64, d, function_count + 1)
    var vz: U64 = 0
    while vz <= function_count {
        v_counts[vz] = 0
        vz = vz + 1
    }
    var vat: U64 = 0
    while vat < value_total {
        let vf = __s0_buffer_get(MirValueRec, store.values, vat).function
        if vf >= 1 && vf <= function_count { v_counts[vf] = v_counts[vf] + 1 }
        vat = vat + 1
    }
    var v_starts = __s0_alloc(U64, d, function_count + 1)
    vz = 0
    while vz <= function_count {
        v_starts[vz] = 0
        vz = vz + 1
    }
    var v_running: U64 = 0
    var vg: U64 = 1
    while vg <= function_count {
        v_starts[vg] = v_running
        v_running = v_running + v_counts[vg]
        vg = vg + 1
    }
    var v_pos = __s0_alloc(U64, d, v_running)
    vz = 0
    while vz < v_running {
        v_pos[vz] = 0
        vz = vz + 1
    }
    vat = 0
    while vat < value_total {
        let vrec = __s0_buffer_get(MirValueRec, store.values, vat)
        let vf = vrec.function
        if vf >= 1 && vf <= function_count && vrec.ordinal < v_counts[vf] {
            let vslot = v_starts[vf] + vrec.ordinal
            if v_pos[vslot] == 0 { v_pos[vslot] = vat + 1 }
        }
        vat = vat + 1
    }
    var at: U64 = 0
    at = 0
    while at < term_total {
        let t = __s0_buffer_get(MirTermRec, store.terminators, at)
        let id = at + 1
        var block_ok = false
        if t.function >= 1 && t.function <= function_count && t.block >= 1 && t.block <= b_counts[t.function] {
            block_ok = b_pos[b_starts[t.function] + t.block - 1] != 0
        } else {
            block_ok = mir_vblock_index(store, t.function, t.block) != 0
        }
        if !mir_vfunction_exists(store, t.function) || !block_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), t.function, t.block, 0, id, 0, 0, id, 0, 0, 0)) }
        if t.kind > mir_term_panic() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_kind(), t.function, t.block, 0, id, 0, 0, id, mir_term_panic(), t.kind, 0)) }
        if (t.kind == mir_term_branch() || t.kind == mir_term_switch() || t.kind == mir_term_fail()) && t.value == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), t.function, t.block, 0, id, 0, 0, id, 1, 0, 0)) }
        if t.value != 0 {
            var value_ok = false
            if t.function >= 1 && t.function <= function_count && t.value >= 1 && t.value <= v_counts[t.function] {
                value_ok = v_pos[v_starts[t.function] + t.value - 1] != 0
            } else {
                value_ok = mir_vvalue_index(store, t.function, t.value) != 0
            }
            if !value_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), t.function, t.block, 0, id, 0, 0, id, 0, 0, t.value)) }
        }
        if t.kind == mir_term_panic() && (version < 2 || t.value != 0) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_version_gate(), t.function, t.block, 0, id, 0, 0, id, 2, version, t.value)) }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_block_terminators(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    // Per-function block counts and bases, then per-(function, block)
    // terminator counts keyed by segment base + block.
    var b_counts = __s0_alloc(U64, d, function_count + 1)
    var bz: U64 = 0
    while bz <= function_count {
        b_counts[bz] = 0
        bz = bz + 1
    }
    var bat: U64 = 0
    while bat < block_total {
        let bf = __s0_buffer_get(MirBlockRec, store.blocks, bat).function
        if bf >= 1 && bf <= function_count { b_counts[bf] = b_counts[bf] + 1 }
        bat = bat + 1
    }
    var b_starts = __s0_alloc(U64, d, function_count + 1)
    bz = 0
    while bz <= function_count {
        b_starts[bz] = 0
        bz = bz + 1
    }
    var b_running: U64 = 0
    var bg: U64 = 1
    while bg <= function_count {
        b_starts[bg] = b_running
        b_running = b_running + b_counts[bg]
        bg = bg + 1
    }
    let term_total = __s0_buffer_len(MirTermRec, store.terminators)
    var term_counts = __s0_alloc(U64, d, b_running + 1)
    var tz: U64 = 0
    while tz <= b_running {
        term_counts[tz] = 0
        tz = tz + 1
    }
    var tat: U64 = 0
    while tat < term_total {
        let tf = __s0_buffer_get(MirTermRec, store.terminators, tat)
        if tf.function >= 1 && tf.function <= function_count && tf.block >= 1 && tf.block <= b_counts[tf.function] {
            term_counts[b_starts[tf.function] + tf.block] = term_counts[b_starts[tf.function] + tf.block] + 1
        }
        tat = tat + 1
    }
    var at: U64 = 0
    // Exactly one terminator per block.
    at = 0
    while at < block_total {
        let b = __s0_buffer_get(MirBlockRec, store.blocks, at)
        var count: U64 = 0
        if b.function >= 1 && b.function <= function_count && b.ordinal + 1 <= b_counts[b.function] {
            count = term_counts[b_starts[b.function] + b.ordinal + 1]
        } else {
            var ti: U64 = 0
            while ti < term_total {
                let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
                if t.function == b.function && t.block == b.ordinal + 1 { count = count + 1 }
                ti = ti + 1
            }
        }
        if count != 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), b.function, b.ordinal + 1, 0, 0, 0, 0, at + 1, 1, count, 0)) }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1_operands(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    let operand_total = __s0_buffer_len(MirOperandRec, store.operands)
    let type_total = __s0_buffer_len(MirTypeRec, store.types)
    let import_total = __s0_buffer_len(MirImportRec, store.imports)
    let instr_total = __s0_buffer_len(MirInstrRec, store.instructions)
    let term_total = __s0_buffer_len(MirTermRec, store.terminators)
    let key_total = type_total + import_total + instr_total * 3 + term_total * 2 + operand_total
    // (kind, owner) segments for expected-ordinal counting. Every group keeps
    // store order, so counting ids below the current one with a matching edge
    // replicates the legacy prior scan exactly.
    var g_counts = __s0_alloc(U64, d, key_total + 1)
    var gz: U64 = 0
    while gz <= key_total {
        g_counts[gz] = 0
        gz = gz + 1
    }
    var gat: U64 = 0
    while gat < operand_total {
        let gkey = mir_v1q_operand_key(store, __s0_buffer_get(MirOperandRec, store.operands, gat))
        if gkey != 0 { g_counts[gkey] = g_counts[gkey] + 1 }
        gat = gat + 1
    }
    var g_starts = __s0_alloc(U64, d, key_total + 1)
    gz = 0
    while gz <= key_total {
        g_starts[gz] = 0
        gz = gz + 1
    }
    var g_running: U64 = 0
    var gg: U64 = 1
    while gg <= key_total {
        g_starts[gg] = g_running
        g_running = g_running + g_counts[gg]
        gg = gg + 1
    }
    var g_ids = __s0_alloc(U64, d, g_running)
    gz = 0
    while gz < g_running {
        g_ids[gz] = 0
        gz = gz + 1
    }
    var g_cursor = __s0_alloc(U64, d, key_total + 1)
    gz = 0
    while gz <= key_total {
        g_cursor[gz] = 0
        gz = gz + 1
    }
    gat = 0
    while gat < operand_total {
        let gkey = mir_v1q_operand_key(store, __s0_buffer_get(MirOperandRec, store.operands, gat))
        if gkey != 0 {
            g_ids[g_starts[gkey] + g_cursor[gkey]] = gat + 1
            g_cursor[gkey] = g_cursor[gkey] + 1
        }
        gat = gat + 1
    }
    // Per-function value segments for value presence.
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    var v_counts = __s0_alloc(U64, d, function_count + 1)
    var vz: U64 = 0
    while vz <= function_count {
        v_counts[vz] = 0
        vz = vz + 1
    }
    var vat: U64 = 0
    while vat < value_total {
        let vf = __s0_buffer_get(MirValueRec, store.values, vat).function
        if vf >= 1 && vf <= function_count { v_counts[vf] = v_counts[vf] + 1 }
        vat = vat + 1
    }
    var v_starts = __s0_alloc(U64, d, function_count + 1)
    vz = 0
    while vz <= function_count {
        v_starts[vz] = 0
        vz = vz + 1
    }
    var v_running: U64 = 0
    var vg: U64 = 1
    while vg <= function_count {
        v_starts[vg] = v_running
        v_running = v_running + v_counts[vg]
        vg = vg + 1
    }
    var v_pos = __s0_alloc(U64, d, v_running)
    vz = 0
    while vz < v_running {
        v_pos[vz] = 0
        vz = vz + 1
    }
    vat = 0
    while vat < value_total {
        let vrec = __s0_buffer_get(MirValueRec, store.values, vat)
        let vf = vrec.function
        if vf >= 1 && vf <= function_count && vrec.ordinal < v_counts[vf] {
            let vslot = v_starts[vf] + vrec.ordinal
            if v_pos[vslot] == 0 { v_pos[vslot] = vat + 1 }
        }
        vat = vat + 1
    }
    var at: U64 = 0
    // Flattened operands validate kind, owner, contiguous ordinal, and values.
    at = 0
    while at < operand_total {
        let o = __s0_buffer_get(MirOperandRec, store.operands, at)
        let id = at + 1
        var owner_ok = true
        if o.kind < mir_operand_type_part() || o.kind > mir_operand_aggregate_field() { owner_ok = false }
        if o.kind == mir_operand_type_part() { owner_ok = mir_vtype_exists(store, o.owner) }
        if o.kind == mir_operand_import_param() { owner_ok = mir_vid_valid(o.owner, import_total) }
        if o.kind == mir_operand_instruction() || o.kind == mir_operand_checked_edge_arg() || o.kind == mir_operand_aggregate_field() { owner_ok = mir_vid_valid(o.owner, instr_total) }
        if o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case() { owner_ok = mir_vid_valid(o.owner, term_total) }
        if o.kind == mir_operand_switch_case_arg() { owner_ok = mir_vid_valid(o.owner, operand_total) && __s0_buffer_get(MirOperandRec, store.operands, o.owner - 1).kind == mir_operand_switch_case() }
        if !owner_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), 0, 0, 0, 0, id, 0, id, 0, o.kind, o.owner)) } else {
            var expected: U64 = 0
            let gkey = mir_v1q_operand_key(store, o)
            if gkey != 0 {
                let gcount = g_counts[gkey]
                var gk: U64 = 0
                while gk < gcount {
                    let gid = g_ids[g_starts[gkey] + gk]
                    if gid < id {
                        let q = __s0_buffer_get(MirOperandRec, store.operands, gid - 1)
                        if q.edge == o.edge { expected = expected + 1 }
                    }
                    gk = gk + 1
                }
            } else {
                var scan: U64 = 0
                while scan < at { let q = __s0_buffer_get(MirOperandRec, store.operands, scan)
if q.kind == o.kind && q.owner == o.owner && q.edge == o.edge { expected = expected + 1 }
scan = scan + 1 }
            }
            if o.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), 0, 0, 0, 0, id, 0, id, expected, o.ordinal, o.owner)) }
            var owner_function: U64 = 0
            if o.kind == mir_operand_instruction() || o.kind == mir_operand_checked_edge_arg() || o.kind == mir_operand_aggregate_field() { owner_function = __s0_buffer_get(MirInstrRec, store.instructions, o.owner - 1).function }
            if o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case() { owner_function = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1).function }
            if o.kind == mir_operand_switch_case_arg() { let c = __s0_buffer_get(MirOperandRec, store.operands, o.owner - 1)
owner_function = __s0_buffer_get(MirTermRec, store.terminators, c.owner - 1).function }
            if o.value != 0 && owner_function != 0 {
                var value_ok = false
                if owner_function >= 1 && owner_function <= function_count && o.value >= 1 && o.value <= v_counts[owner_function] {
                    value_ok = v_pos[v_starts[owner_function] + o.value - 1] != 0
                } else {
                    value_ok = mir_vvalue_index(store, owner_function, o.value) != 0
                }
                if !value_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), owner_function, 0, 0, 0, id, 0, id, 0, 0, o.value)) }
            }
            if o.kind == mir_operand_checked_edge_arg() { let instruction = __s0_buffer_get(MirInstrRec, store.instructions, o.owner - 1)
if o.target != instruction.target { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), instruction.function, instruction.block, o.owner, 0, id, 0, id, instruction.target, o.target, o.owner)) } }
            if o.kind == mir_operand_terminator_arg() { let term = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1)
var target = term.target
if o.edge == mir_edge_then() { target = term.then_block }
if o.edge == mir_edge_else() { target = term.else_block }
if o.target != target { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), term.function, term.block, 0, o.owner, id, 0, id, target, o.target, o.owner)) } }
            if o.kind == mir_operand_switch_case_arg() { let c = __s0_buffer_get(MirOperandRec, store.operands, o.owner - 1)
if o.target != c.target { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), owner_function, 0, 0, c.owner, id, 0, id, c.target, o.target, o.owner)) } }
        }
        at = at + 1
    }
    return Ok(out)
}
fn mir_vphase1(d: Domain, store: MirStore, version: U64, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = try mir_vphase1_types(d, store, version, initial)
    out = try mir_vphase1_declarations(d, store, out)
    out = try mir_vphase1_params(d, store, out)
    out = try mir_vphase1_locals(d, store, out)
    out = try mir_vphase1_blocks(d, store, out)
    out = try mir_vphase1_values(d, store, out)
    out = try mir_vphase1_places(d, store, out)
    out = try mir_vphase1_instructions(d, store, version, out)
    out = try mir_vphase1_terminators(d, store, version, out)
    out = try mir_vphase1_block_terminators(d, store, out)
    out = try mir_vphase1_operands(d, store, out)
    return Ok(out)
}
