// Stable numeric diagnostics for the independent MIR verifier. Diagnostics
// retain numeric facts only; adapters own wording and output.
fn mir_verify_phase_integrity() -> U64 { return 1 }
fn mir_verify_phase_types() -> U64 { return 2 }
fn mir_verify_phase_cfg() -> U64 { return 3 }
fn mir_verify_phase_dominance() -> U64 { return 4 }
fn mir_vdiag_bad_version() -> U64 { return 1 }
fn mir_vdiag_missing_primitives() -> U64 { return 2 }
fn mir_vdiag_bad_kind() -> U64 { return 3 }
fn mir_vdiag_bad_name() -> U64 { return 4 }
fn mir_vdiag_duplicate_name() -> U64 { return 5 }
fn mir_vdiag_bad_owner() -> U64 { return 6 }
fn mir_vdiag_bad_ordinal() -> U64 { return 7 }
fn mir_vdiag_bad_reference() -> U64 { return 8 }
fn mir_vdiag_bad_reciprocal() -> U64 { return 9 }
fn mir_vdiag_missing_block() -> U64 { return 10 }
fn mir_vdiag_bad_shape() -> U64 { return 11 }
fn mir_vdiag_bad_result() -> U64 { return 12 }
fn mir_vdiag_bad_failure_edge() -> U64 { return 13 }
fn mir_vdiag_bad_place() -> U64 { return 14 }
fn mir_vdiag_version_gate() -> U64 { return 15 }
fn mir_vdiag_bad_type_child() -> U64 { return 16 }
fn mir_vdiag_empty_enum() -> U64 { return 17 }
fn mir_vdiag_duplicate_member() -> U64 { return 18 }
fn mir_vdiag_reserved_member() -> U64 { return 19 }
fn mir_vdiag_type_cycle() -> U64 { return 20 }
fn mir_vdiag_bad_signature() -> U64 { return 21 }
fn mir_vdiag_bad_constant() -> U64 { return 22 }
fn mir_vdiag_ephemeral_type() -> U64 { return 23 }
fn mir_vdiag_domain_result() -> U64 { return 24 }
fn mir_vdiag_entry_params() -> U64 { return 25 }
fn mir_vdiag_missing_target() -> U64 { return 26 }
fn mir_vdiag_foreign_target() -> U64 { return 27 }
fn mir_vdiag_edge_arity() -> U64 { return 28 }
fn mir_vdiag_empty_switch() -> U64 { return 29 }
fn mir_vdiag_duplicate_default() -> U64 { return 30 }
fn mir_vdiag_default_binding() -> U64 { return 31 }
fn mir_vdiag_duplicate_case() -> U64 { return 32 }
fn mir_vdiag_unknown_case() -> U64 { return 33 }
fn mir_vdiag_unit_binding() -> U64 { return 34 }
fn mir_vdiag_nonexhaustive_switch() -> U64 { return 35 }
fn mir_vdiag_reachable_unreachable() -> U64 { return 36 }
fn mir_vdiag_not_dominated() -> U64 { return 37 }
fn mir_vdiag_uninitialized_load() -> U64 { return 38 }
// All IDs use the frozen external 1-based contract. Zero means no context.
// detail fields are append-only small numeric expected/actual/reference facts.
type MirVerifyDiagRec {
    phase: U64
    kind: U64
    function: U64
    block: U64
    instruction: U64
    terminator: U64
    operand: U64
    type_id: U64
    declaration: U64
    expected: U64
    actual: U64
    reference: U64
}
type MirVerifyOutput {
    diagnostics: __s0_Buffer(MirVerifyDiagRec)
}
fn mir_vdiag(phase: U64, kind: U64, function: U64, block: U64, instruction: U64, terminator: U64, operand: U64, type_id: U64, declaration: U64, expected: U64, actual: U64, reference: U64) -> MirVerifyDiagRec {
    return MirVerifyDiagRec(phase: phase, kind: kind, function: function, block: block, instruction: instruction, terminator: terminator, operand: operand, type_id: type_id, declaration: declaration, expected: expected, actual: actual, reference: reference)
}
