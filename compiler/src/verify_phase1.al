fn mir_vop_produces(op: U64) -> Bool {
    return !(op == mir_op_store() || op == mir_op_domain_reset() || op == mir_op_domain_destroy() || op == mir_op_cleanup_disarm() || op == mir_op_cleanup_scope_run() || op == mir_op_cleanup_scope_end() || op == mir_op_table_view_end())
}
fn mir_vop_checked(op: U64) -> Bool {
    return op == mir_op_alloc_checked() || (op >= mir_op_int_add_checked() && op <= mir_op_int_shr_checked()) || op == mir_op_slice_index_checked() || op == mir_op_slice_range_checked() || op == mir_op_enum_payload_checked()
}
fn mir_vop_required_mask(op: U64) -> U64 {
    // bits: a=1, b=2, c=4, place=8, type=16, target=32, name=64.
    if op == mir_op_load() { return 8 }
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
    if op == mir_op_slice_index_checked() { return 3 }
    if op == mir_op_slice_range_checked() { return 7 }
    if op == mir_op_enum_payload_checked() { return 65 }
    if op == mir_op_enum_construct() { return 80 }
    if op == mir_op_table_insert() || op == mir_op_table_lookup() || op == mir_op_table_lookup_mut() || op == mir_op_table_remove() { return 3 }
    if op == mir_op_table_view_end() { return 1 }
    if op >= mir_op_int_trunc() && op <= mir_op_float_from_int() { return 17 }
    if op == mir_op_const_get() || op == mir_op_call() || op == mir_op_ffi_call_unsafe() { return 32 }
    return 0
}
fn mir_vphase1(d: Domain, store: MirStore, version: U64, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let phase = mir_verify_phase_integrity()
    let type_count = __s0_buffer_len(MirTypeRec, store.types)
    let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
    if version < 1 || version > mir_format_version() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_version(), 0, 0, 0, 0, 0, 0, 0, 1, version, mir_format_version())) }
    if type_count < mir_primitive_type_count() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_missing_primitives(), 0, 0, 0, 0, 0, 0, 0, mir_primitive_type_count(), type_count, 0)) }
    var at: U64 = 0
    while at < type_count {
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        let id = at + 1
        if at < mir_primitive_type_count() {
            if t.kind != mir_type_kind_primitive() || t.name_start != 0 || t.name_end != 0 || t.elem != 0 || t.ok_type != 0 || t.err_type != 0 || t.first_part != 0 || t.part_count != 0 || t.result_type != 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), 0, 0, 0, 0, 0, id, id, 0, t.kind, 0)) }
        } else {
            if t.kind > mir_type_kind_table_mut_view() || t.kind == mir_type_kind_primitive() {
                out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_kind(), 0, 0, 0, 0, 0, id, id, mir_type_kind_table_mut_view(), t.kind, 0))
            } else {
                let named = t.name_start != t.name_end
                let named_kind = t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum()
                if (named_kind && !named) || (!named_kind && named) || (named && !mir_vname_valid(store, t.name_start, t.name_end, true)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), 0, 0, 0, 0, 0, id, id, 0, 0, 0)) }
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
        var prior: U64 = 0
        while prior < at { let p = __s0_buffer_get(MirConstRec, store.constants, prior)
if mir_vname_equal(store, item.name_start, item.name_end, p.name_start, p.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_duplicate_name(), 0, 0, 0, 0, 0, 0, at + 1, 0, 0, prior + 1))
prior = at }
prior = prior + 1 }
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
        if mir_vblock_index(store, at + 1, 1) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_missing_block(), at + 1, 0, 0, 0, 0, 0, at + 1, 1, 0, 0)) }
        at = at + 1
    }
    // Every owner-local table is checked directly; builders are not trusted.
    at = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let p = __s0_buffer_get(MirParamRec, store.params, at)
        if !mir_vfunction_exists(store, p.function) || (p.kind != mir_param_function() && p.kind != mir_param_block()) || (p.kind == mir_param_function() && p.block != 0) || (p.kind == mir_param_block() && mir_vblock_index(store, p.function, p.block) == 0) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), p.function, p.block, 0, 0, 0, 0, at + 1, 0, p.kind, 0)) }
        if !mir_vname_valid(store, p.name_start, p.name_end, false) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), p.function, p.block, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        var expected: U64 = 0
var scan: U64 = 0
        while scan < at { let q = __s0_buffer_get(MirParamRec, store.params, scan)
if q.kind == p.kind && q.function == p.function && q.block == p.block { expected = expected + 1 }
scan = scan + 1 }
        if p.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), p.function, p.block, 0, 0, 0, 0, at + 1, expected, p.ordinal, 0)) }
        let vi = mir_vvalue_index(store, p.function, p.value)
        if vi == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), p.function, p.block, 0, 0, 0, 0, at + 1, 1, 0, p.value)) } else { let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
var want = mir_value_def_function_param()
if p.kind == mir_param_block() { want = mir_value_def_block_param() }
if v.def_kind != want || v.block != p.block || v.item != p.ordinal + 1 || v.value_type != p.param_type { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), p.function, p.block, 0, 0, 0, 0, at + 1, want, v.def_kind, p.value)) } }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let item = __s0_buffer_get(MirLocalRec, store.locals, at)
var expected: U64 = 0
var scan: U64 = 0
        while scan < at { if __s0_buffer_get(MirLocalRec, store.locals, scan).function == item.function { expected = expected + 1 }
scan = scan + 1 }
        if !mir_vfunction_exists(store, item.function) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), item.function, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        if item.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), item.function, 0, 0, 0, 0, 0, at + 1, expected, item.ordinal, 0)) }
        if !mir_vname_valid(store, item.name_start, item.name_end, false) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), item.function, 0, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let item = __s0_buffer_get(MirBlockRec, store.blocks, at)
var expected: U64 = 0
var scan: U64 = 0
        while scan < at { if __s0_buffer_get(MirBlockRec, store.blocks, scan).function == item.function { expected = expected + 1 }
scan = scan + 1 }
        if !mir_vfunction_exists(store, item.function) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), item.function, item.ordinal + 1, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        if item.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), item.function, item.ordinal + 1, 0, 0, 0, 0, at + 1, expected, item.ordinal, 0)) }
        if !mir_vname_valid(store, item.name_start, item.name_end, true) || mir_vname_word(store, item.name_start, item.name_end, "else") { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), item.function, item.ordinal + 1, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let v = __s0_buffer_get(MirValueRec, store.values, at)
var expected: U64 = 0
var scan: U64 = 0
        while scan < at { if __s0_buffer_get(MirValueRec, store.values, scan).function == v.function { expected = expected + 1 }
scan = scan + 1 }
        if !mir_vfunction_exists(store, v.function) || v.def_kind > mir_value_def_switch_case() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, v.def_kind, 0)) }
        if v.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), v.function, v.block, 0, 0, 0, 0, at + 1, expected, v.ordinal, 0)) }
        if !mir_vname_valid(store, v.name_start, v.name_end, false) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_name(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, 0, 0)) }
        if v.def_kind != mir_value_def_function_param() && mir_vblock_index(store, v.function, v.block) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), v.function, v.block, 0, 0, 0, 0, at + 1, 0, 0, v.block)) }
        at = at + 1
    }
    // Instructions, places, and terminators use only range-checked lookups.
    at = 0
    while at < __s0_buffer_len(MirPlaceRec, store.places) {
        let p = __s0_buffer_get(MirPlaceRec, store.places, at)
        if !mir_vfunction_exists(store, p.function) || p.kind > mir_place_deref() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, mir_place_deref(), p.kind, 0)) }
        if p.kind == mir_place_local() && mir_vlocal_index(store, p.function, p.local) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.local)) }
        if p.kind == mir_place_field() && (!mir_vid_valid(p.base, __s0_buffer_len(MirPlaceRec, store.places)) || !mir_vname_valid(store, p.field_start, p.field_end, true)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.base)) }
        if p.kind == mir_place_deref() && mir_vvalue_index(store, p.function, p.deref_value) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.deref_value)) }
        if p.kind == mir_place_field() { var next = p.base
var steps: U64 = 0
while mir_vid_valid(next, __s0_buffer_len(MirPlaceRec, store.places)) && steps <= __s0_buffer_len(MirPlaceRec, store.places) { let base = __s0_buffer_get(MirPlaceRec, store.places, next - 1)
if base.function != p.function { steps = __s0_buffer_len(MirPlaceRec, store.places) + 2 } else { if base.kind == mir_place_field() { next = base.base } else { next = 0 } }
steps = steps + 1 }
if steps > __s0_buffer_len(MirPlaceRec, store.places) + 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_place(), p.function, 0, 0, 0, 0, 0, at + 1, 0, 0, p.base)) } }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let i = __s0_buffer_get(MirInstrRec, store.instructions, at)
let id = at + 1
var expected: U64 = 0
var scan: U64 = 0
        while scan < at { let q = __s0_buffer_get(MirInstrRec, store.instructions, scan)
if q.function == i.function && q.block == i.block { expected = expected + 1 }
scan = scan + 1 }
        if !mir_vfunction_exists(store, i.function) || mir_vblock_index(store, i.function, i.block) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), i.function, i.block, id, 0, 0, 0, id, 0, 0, 0)) }
        if i.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), i.function, i.block, id, 0, 0, 0, id, expected, i.ordinal, 0)) }
        if i.op > mir_op_ffi_call_unsafe() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_kind(), i.function, i.block, id, 0, 0, 0, id, mir_op_ffi_call_unsafe(), i.op, 0)) } else {
            var produces = mir_vop_produces(i.op)
            let has_result = i.result != 0
            if i.op == mir_op_call() && mir_vid_valid(i.target, function_count) && __s0_buffer_get(MirFunctionRec, store.functions, i.target - 1).result_type == mir_type_unit() { produces = has_result }
            if i.op == mir_op_ffi_call_unsafe() && mir_vid_valid(i.target, __s0_buffer_len(MirImportRec, store.imports)) && __s0_buffer_get(MirImportRec, store.imports, i.target - 1).result_type == mir_type_unit() { produces = has_result }
            if (produces && !has_result) || (!produces && has_result) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_result(), i.function, i.block, id, 0, 0, 0, id, 0, i.result, 0)) }
            let fail_count = mir_vcount_operands(store, mir_operand_checked_edge_arg(), id, 0)
let has_fail = i.target != 0
            let checked = mir_vop_checked(i.op)
            if (checked && !has_fail) || (!checked && has_fail) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_failure_edge(), i.function, i.block, id, 0, 0, 0, id, 0, fail_count, 0)) }
            let mask = mir_vop_required_mask(i.op)
            if ((mask % 2 == 1) && i.a == 0) || (((mask / 2) % 2 == 1) && i.b == 0) || (((mask / 4) % 2 == 1) && i.c == 0) || (((mask / 8) % 2 == 1) && i.place == 0) || (((mask / 16) % 2 == 1) && i.type_op == 0) || (((mask / 32) % 2 == 1) && i.target == 0) || (((mask / 64) % 2 == 1) && i.name_start == i.name_end) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), i.function, i.block, id, 0, 0, 0, id, mask, 0, 0)) }
            if (i.a != 0 && mir_vvalue_index(store, i.function, i.a) == 0) || (i.b != 0 && mir_vvalue_index(store, i.function, i.b) == 0) || (i.c != 0 && mir_vvalue_index(store, i.function, i.c) == 0) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.a)) }
            if i.place != 0 && !mir_vid_valid(i.place, __s0_buffer_len(MirPlaceRec, store.places)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.place)) }
            if ((mask / 16) % 2 == 1) && !mir_vtype_exists(store, i.type_op) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, i.type_op, id, 0, 0, i.type_op)) }
            if (i.op == mir_op_call() || i.op == mir_op_cleanup_push()) && !mir_vid_valid(i.target, function_count) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.target)) }
            if i.op == mir_op_ffi_call_unsafe() && !mir_vid_valid(i.target, __s0_buffer_len(MirImportRec, store.imports)) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), i.function, i.block, id, 0, 0, 0, id, 0, 0, i.target)) }
            if i.result != 0 { let vi = mir_vvalue_index(store, i.function, i.result)
if vi == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), i.function, i.block, id, 0, 0, 0, id, 1, 0, i.result)) } else { let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if v.def_kind != mir_value_def_instruction() || v.block != i.block || v.item != i.ordinal + 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), i.function, i.block, id, 0, 0, 0, id, i.ordinal + 1, v.item, i.result)) } } }
            if i.op == mir_op_alloc_checked() && version < 3 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_version_gate(), i.function, i.block, id, 0, 0, 0, id, 3, version, 0)) }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirTermRec, store.terminators) {
        let t = __s0_buffer_get(MirTermRec, store.terminators, at)
let id = at + 1
        if !mir_vfunction_exists(store, t.function) || mir_vblock_index(store, t.function, t.block) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), t.function, t.block, 0, id, 0, 0, id, 0, 0, 0)) }
        if t.kind > mir_term_panic() { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_kind(), t.function, t.block, 0, id, 0, 0, id, mir_term_panic(), t.kind, 0)) }
        if t.kind == mir_term_panic() && (version < 2 || t.value != 0) { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_version_gate(), t.function, t.block, 0, id, 0, 0, id, 2, version, t.value)) }
        if t.kind == mir_term_fail() && t.value == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_shape(), t.function, t.block, 0, id, 0, 0, id, 1, 0, 0)) }
        at = at + 1
    }
    // Exactly one terminator per block.
    at = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) { let b = __s0_buffer_get(MirBlockRec, store.blocks, at)
var count: U64 = 0
var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == b.function && t.block == b.ordinal + 1 { count = count + 1 }
ti = ti + 1 }
if count != 1 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reciprocal(), b.function, b.ordinal + 1, 0, 0, 0, 0, at + 1, 1, count, 0)) }
at = at + 1 }
    // Flattened operands validate kind, owner, contiguous ordinal, and values.
    at = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let o = __s0_buffer_get(MirOperandRec, store.operands, at)
let id = at + 1
var owner_ok = true
        if o.kind < mir_operand_type_part() || o.kind > mir_operand_aggregate_field() { owner_ok = false }
        if o.kind == mir_operand_type_part() { owner_ok = mir_vtype_exists(store, o.owner) }
        if o.kind == mir_operand_import_param() { owner_ok = mir_vid_valid(o.owner, __s0_buffer_len(MirImportRec, store.imports)) }
        if o.kind == mir_operand_instruction() || o.kind == mir_operand_checked_edge_arg() || o.kind == mir_operand_aggregate_field() { owner_ok = mir_vid_valid(o.owner, __s0_buffer_len(MirInstrRec, store.instructions)) }
        if o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case() { owner_ok = mir_vid_valid(o.owner, __s0_buffer_len(MirTermRec, store.terminators)) }
        if o.kind == mir_operand_switch_case_arg() { owner_ok = mir_vid_valid(o.owner, __s0_buffer_len(MirOperandRec, store.operands)) && __s0_buffer_get(MirOperandRec, store.operands, o.owner - 1).kind == mir_operand_switch_case() }
        if !owner_ok { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_owner(), 0, 0, 0, 0, id, 0, id, 0, o.kind, o.owner)) } else {
            var expected: U64 = 0
var scan: U64 = 0
            while scan < at { let q = __s0_buffer_get(MirOperandRec, store.operands, scan)
if q.kind == o.kind && q.owner == o.owner && q.edge == o.edge { expected = expected + 1 }
scan = scan + 1 }
            if o.ordinal != expected { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_ordinal(), 0, 0, 0, 0, id, 0, id, expected, o.ordinal, o.owner)) }
            var owner_function: U64 = 0
            if o.kind == mir_operand_instruction() || o.kind == mir_operand_checked_edge_arg() || o.kind == mir_operand_aggregate_field() { owner_function = __s0_buffer_get(MirInstrRec, store.instructions, o.owner - 1).function }
            if o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case() { owner_function = __s0_buffer_get(MirTermRec, store.terminators, o.owner - 1).function }
            if o.kind == mir_operand_switch_case_arg() { let c = __s0_buffer_get(MirOperandRec, store.operands, o.owner - 1)
owner_function = __s0_buffer_get(MirTermRec, store.terminators, c.owner - 1).function }
            if o.value != 0 && owner_function != 0 && mir_vvalue_index(store, owner_function, o.value) == 0 { out = try mir_vadd(d, out, mir_vdiag(phase, mir_vdiag_bad_reference(), owner_function, 0, 0, 0, id, 0, id, 0, 0, o.value)) }
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
