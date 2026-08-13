// Phase 9 permits values whose type recursively contains raw_ptr only at the
// two explicit unsafe boundaries owned by MIR 3: unsafe FFI arguments and a
// function return/fail operand. The complete V4 use inventory keeps places,
// edge arguments, aggregates, safe calls, and nested raw values on one stable
// declaration-ordered path.
fn mir_v9_use_allowed(store: MirStore, function: U64, use: MirVP4Use) -> Bool {
    if use.instruction != 0 {
        let instruction = __s0_buffer_get(MirInstrRec, store.instructions, use.instruction - 1)
        return instruction.function == function && instruction.op == mir_op_ffi_call_unsafe() && use.operand != 0
    }
    if use.terminator != 0 {
        let term = __s0_buffer_get(MirTermRec, store.terminators, use.terminator - 1)
        return (term.kind == mir_term_return() || term.kind == mir_term_fail()) && term.value == use.value
    }
    return false
}

fn mir_v9_function(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec), function: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    let uses = try mir_vp4_collect_uses(d, store, function)
        var at: U64 = 0
        while at < __s0_buffer_len(MirVP4Use, uses) {
            let use = __s0_buffer_get(MirVP4Use, uses, at)
            let type_id = mir_v5_value_type(store, function, use.value)
            if try mir_v6_type_contains(d, store, type_id, mir_type_kind_raw_ptr()) {
                if !mir_v9_use_allowed(store, function, use) {
                    out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_pointers(), mir_vdiag_raw_boundary(), function, use.block, use.instruction, use.terminator, use.operand, type_id, 0, 0, 0, use.value))
                }
            }
            at = at + 1
        }
    return Ok(out)
}

fn mir_vphase9(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) { out = try mir_v9_function(d, store, out, function)
function = function + 1 }
    return Ok(out)
}
