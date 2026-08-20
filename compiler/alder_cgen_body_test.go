package compiler

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const cgenBodyWrapper = `
fn cgen_test_const(d: Domain, store: MirStore, function: U64, block: U64, ordinal: U64, name: __s0_String, type_id: U64) -> Result(MirBuildStep, __s0_Error) {
    let value = try mir_add_value(d, store, function, name, type_id, mir_value_def_instruction(), block, ordinal + 1)
    let named = try mir_append_name(d, value.store, name)
    let instruction = try mir_add_instruction(d, named.store, MirInstrRec(function: function, block: block, ordinal: ordinal, op: mir_op_const_get(), result: value.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: named.start, name_end: named.end))
    return Ok(MirBuildStep(store: instruction.store, id: value.id))
}

fn cgen_body_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    var store = initial
    store = (try mir_add_const(d, store, "zero", mir_type_i32(), mir_const_int(), 0, 0, 0, "")).store
    store = (try mir_add_const(d, store, "one", mir_type_i32(), mir_const_int(), 0, 1, 0, "")).store
    store = (try mir_add_const(d, store, "two", mir_type_i32(), mir_const_int(), 0, 2, 0, "")).store
    store = (try mir_add_const(d, store, "four", mir_type_i32(), mir_const_int(), 0, 4, 0, "")).store
    store = (try mir_add_const(d, store, "maximum", mir_type_i32(), mir_const_int(), 0, 2147483647, 0, "")).store

    let imported = try mir_add_import(d, store, "fixture_add_one", mir_type_i32())
    store = try mir_add_import_param(d, imported.store, imported.id, 0, mir_type_i32())
    let pair = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "Pair")
    store = try mir_add_type_part(d, pair.store, mir_type_part_field(), pair.type_id, 0, "value", mir_type_i32())
    let choice = try mir_add_named_type(d, store, mir_type_kind_enum(), "Choice")
    store = try mir_add_type_part(d, choice.store, mir_type_part_variant(), choice.type_id, 0, "None", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), choice.type_id, 1, "Some", mir_type_i32())
    let no_parts = try __s0_buffer_new(U64, d)
    let option = try mir_intern_type(d, store, mir_type_kind_option(), mir_type_i32(), 0, 0, no_parts, 0)
    let result = try mir_intern_type(d, option.store, mir_type_kind_result(), 0, mir_type_i32(), mir_type_i32(), no_parts, 0)
    store = result.store

    // A concrete generic specialization; executable MIR contains no type values.
    let identity = try mir_add_function(d, store, "identity.i32", mir_type_i32())
    let identity_value = try mir_add_function_param(d, identity.store, identity.id, 0, "value", mir_type_i32())
    let identity_entry = try mir_add_block(d, identity_value.store, identity.id, 0, "entry")
    store = (try mir_add_terminator(d, identity_entry.store, MirTermRec(function: identity.id, block: identity_entry.id, kind: mir_term_return(), value: identity_value.id, target: 0, then_block: 0, else_block: 0))).store

    // Executes the checked-failure edge: INT32_MAX + 1 must return zero.
    let overflow = try mir_add_function(d, store, "checked_failure", mir_type_i32())
    let overflow_entry = try mir_add_block(d, overflow.store, overflow.id, 0, "entry")
    let overflow_failed = try mir_add_block(d, overflow_entry.store, overflow.id, 1, "failed")
    let overflow_bad = try mir_add_block(d, overflow_failed.store, overflow.id, 2, "bad_success")
    let maximum = try cgen_test_const(d, overflow_bad.store, overflow.id, overflow_entry.id, 0, "maximum", mir_type_i32())
    let one_overflow = try cgen_test_const(d, maximum.store, overflow.id, overflow_entry.id, 1, "one", mir_type_i32())
    let overflow_sum = try mir_add_value(d, one_overflow.store, overflow.id, "sum", mir_type_i32(), mir_value_def_instruction(), overflow_entry.id, 3)
    let overflow_add = try mir_add_instruction(d, overflow_sum.store, MirInstrRec(function: overflow.id, block: overflow_entry.id, ordinal: 2, op: mir_op_int_add_checked(), result: overflow_sum.id, place: 0, type_op: 0, a: maximum.id, b: one_overflow.id, c: 0, target: overflow_failed.id, name_start: 0, name_end: 0))
    store = (try mir_add_terminator(d, overflow_add.store, MirTermRec(function: overflow.id, block: overflow_entry.id, kind: mir_term_jump(), value: 0, target: overflow_bad.id, then_block: 0, else_block: 0))).store
    let zero_overflow = try cgen_test_const(d, store, overflow.id, overflow_failed.id, 0, "zero", mir_type_i32())
    store = (try mir_add_terminator(d, zero_overflow.store, MirTermRec(function: overflow.id, block: overflow_failed.id, kind: mir_term_return(), value: zero_overflow.id, target: 0, then_block: 0, else_block: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: overflow.id, block: overflow_bad.id, kind: mir_term_return(), value: maximum.id, target: 0, then_block: 0, else_block: 0))).store

    let main = try mir_add_function(d, store, "main", mir_type_i32())
    let entry = try mir_add_block(d, main.store, main.id, 0, "entry")
    let loop = try mir_add_block(d, entry.store, main.id, 1, "loop")
    let body = try mir_add_block(d, loop.store, main.id, 2, "body")
    let after = try mir_add_block(d, body.store, main.id, 3, "after")
    let some_block = try mir_add_block(d, after.store, main.id, 4, "choice_some")
    let none_block = try mir_add_block(d, some_block.store, main.id, 5, "choice_none")
    let make_result = try mir_add_block(d, none_block.store, main.id, 6, "make_result")
    let ok_block = try mir_add_block(d, make_result.store, main.id, 7, "result_ok")
    let err_block = try mir_add_block(d, ok_block.store, main.id, 8, "result_err")
    let success = try mir_add_block(d, err_block.store, main.id, 9, "success")
    let failure = try mir_add_block(d, success.store, main.id, 10, "failure")
    let one = try cgen_test_const(d, failure.store, main.id, entry.id, 0, "one", mir_type_i32())
    let two = try cgen_test_const(d, one.store, main.id, entry.id, 1, "two", mir_type_i32())
    let zero = try cgen_test_const(d, two.store, main.id, entry.id, 2, "zero", mir_type_i32())
    let four = try cgen_test_const(d, zero.store, main.id, entry.id, 3, "four", mir_type_i32())
    let loop_current = try mir_add_block_param(d, four.store, main.id, loop.id, 0, "current", mir_type_i32())
    let loop_other = try mir_add_block_param(d, loop_current.store, main.id, loop.id, 1, "other", mir_type_i32())
    let enter = try mir_add_terminator(d, loop_other.store, MirTermRec(function: main.id, block: entry.id, kind: mir_term_jump(), value: 0, target: loop.id, then_block: 0, else_block: 0))
    let enter_current = try mir_add_operand(d, enter.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: enter.id, ordinal: 0, edge: mir_edge_jump(), value: one.id, target: loop.id, operand_type: 0, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, enter_current.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: enter.id, ordinal: 1, edge: mir_edge_jump(), value: two.id, target: loop.id, operand_type: 0, name_start: 0, name_end: 0))).store

    let loop_condition = try mir_add_value(d, store, main.id, "again", mir_type_bool(), mir_value_def_instruction(), loop.id, 1)
    let compare = try mir_add_instruction(d, loop_condition.store, MirInstrRec(function: main.id, block: loop.id, ordinal: 0, op: mir_op_int_lt(), result: loop_condition.id, place: 0, type_op: 0, a: loop_current.id, b: two.id, c: 0, target: 0, name_start: 0, name_end: 0))
    let loop_branch = try mir_add_terminator(d, compare.store, MirTermRec(function: main.id, block: loop.id, kind: mir_term_branch(), value: loop_condition.id, target: 0, then_block: body.id, else_block: after.id))
    let after_current = try mir_add_block_param(d, loop_branch.store, main.id, after.id, 0, "after_current", mir_type_i32())
    let after_other = try mir_add_block_param(d, after_current.store, main.id, after.id, 1, "after_other", mir_type_i32())
    let after_arg0 = try mir_add_operand(d, after_other.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: loop_branch.id, ordinal: 0, edge: mir_edge_else(), value: loop_current.id, target: after.id, operand_type: 0, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, after_arg0.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: loop_branch.id, ordinal: 1, edge: mir_edge_else(), value: loop_other.id, target: after.id, operand_type: 0, name_start: 0, name_end: 0))).store
    let cycle = try mir_add_terminator(d, store, MirTermRec(function: main.id, block: body.id, kind: mir_term_jump(), value: 0, target: loop.id, then_block: 0, else_block: 0))
    let cycle0 = try mir_add_operand(d, cycle.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: cycle.id, ordinal: 0, edge: mir_edge_jump(), value: loop_other.id, target: loop.id, operand_type: 0, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, cycle0.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: cycle.id, ordinal: 1, edge: mir_edge_jump(), value: loop_current.id, target: loop.id, operand_type: 0, name_start: 0, name_end: 0))).store

    let failed_value = try mir_add_block_param(d, store, main.id, failure.id, 0, "failure_value", mir_type_i32())
    let sum = try mir_add_value(d, failed_value.store, main.id, "sum", mir_type_i32(), mir_value_def_instruction(), after.id, 1)
    let checked = try mir_add_instruction(d, sum.store, MirInstrRec(function: main.id, block: after.id, ordinal: 0, op: mir_op_int_add_checked(), result: sum.id, place: 0, type_op: 0, a: after_current.id, b: after_other.id, c: 0, target: failure.id, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, checked.store, MirOperandRec(kind: mir_operand_checked_edge_arg(), owner: checked.id, ordinal: 0, edge: 0, value: zero.id, target: failure.id, operand_type: 0, name_start: 0, name_end: 0))).store
    let aggregate = try mir_add_value(d, store, main.id, "pair", pair.type_id, mir_value_def_instruction(), after.id, 2)
    let field_name = try mir_append_name(d, aggregate.store, "value")
    let construct = try mir_add_instruction(d, field_name.store, MirInstrRec(function: main.id, block: after.id, ordinal: 1, op: mir_op_aggregate_construct(), result: aggregate.id, place: 0, type_op: pair.type_id, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, construct.store, MirOperandRec(kind: mir_operand_aggregate_field(), owner: construct.id, ordinal: 0, edge: 0, value: sum.id, target: 0, operand_type: 0, name_start: field_name.start, name_end: field_name.end))).store
    let local = try mir_add_local(d, store, main.id, 0, "slot", pair.type_id)
    let local_place = try mir_add_place(d, local.store, MirPlaceRec(function: main.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    store = (try mir_add_instruction(d, local_place.store, MirInstrRec(function: main.id, block: after.id, ordinal: 2, op: mir_op_store(), result: 0, place: local_place.id, type_op: 0, a: aggregate.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let projected = try mir_add_place(d, store, MirPlaceRec(function: main.id, kind: mir_place_field(), local: 0, base: local_place.id, field_start: field_name.start, field_end: field_name.end, deref_value: 0))
    let loaded = try mir_add_value(d, projected.store, main.id, "loaded", mir_type_i32(), mir_value_def_instruction(), after.id, 4)
    store = (try mir_add_instruction(d, loaded.store, MirInstrRec(function: main.id, block: after.id, ordinal: 3, op: mir_op_load(), result: loaded.id, place: projected.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let option_value = try mir_add_value(d, store, main.id, "option", option.type_id, mir_value_def_instruction(), after.id, 5)
    let some_name = try mir_append_name(d, option_value.store, "some")
    store = (try mir_add_instruction(d, some_name.store, MirInstrRec(function: main.id, block: after.id, ordinal: 4, op: mir_op_enum_construct(), result: option_value.id, place: 0, type_op: option.type_id, a: loaded.id, b: 0, c: 0, target: 0, name_start: some_name.start, name_end: some_name.end))).store
    let option_payload = try mir_add_value(d, store, main.id, "option_payload", mir_type_i32(), mir_value_def_instruction(), after.id, 6)
    let some_extract_name = try mir_append_name(d, option_payload.store, "some")
    let extract = try mir_add_instruction(d, some_extract_name.store, MirInstrRec(function: main.id, block: after.id, ordinal: 5, op: mir_op_enum_payload_checked(), result: option_payload.id, place: 0, type_op: 0, a: option_value.id, b: 0, c: 0, target: failure.id, name_start: some_extract_name.start, name_end: some_extract_name.end))
    store = (try mir_add_operand(d, extract.store, MirOperandRec(kind: mir_operand_checked_edge_arg(), owner: extract.id, ordinal: 0, edge: 0, value: zero.id, target: failure.id, operand_type: 0, name_start: 0, name_end: 0))).store
    let choice_value = try mir_add_value(d, store, main.id, "choice", choice.type_id, mir_value_def_instruction(), after.id, 7)
    let choice_name = try mir_append_name(d, choice_value.store, "Some")
    store = (try mir_add_instruction(d, choice_name.store, MirInstrRec(function: main.id, block: after.id, ordinal: 6, op: mir_op_enum_construct(), result: choice_value.id, place: 0, type_op: choice.type_id, a: option_payload.id, b: 0, c: 0, target: 0, name_start: choice_name.start, name_end: choice_name.end))).store
    let choice_payload = try mir_add_value(d, store, main.id, "choice_payload", mir_type_i32(), mir_value_def_switch_case(), after.id, 2)
    let choice_switch = try mir_add_terminator(d, choice_payload.store, MirTermRec(function: main.id, block: after.id, kind: mir_term_switch(), value: choice_value.id, target: 0, then_block: 0, else_block: 0))
    let none_name = try mir_append_name(d, choice_switch.store, "None")
    let none_case = try mir_add_operand(d, none_name.store, MirOperandRec(kind: mir_operand_switch_case(), owner: choice_switch.id, ordinal: 0, edge: 0, value: 0, target: none_block.id, operand_type: 0, name_start: none_name.start, name_end: none_name.end))
    let choice_case_name = try mir_append_name(d, none_case.store, "Some")
    store = (try mir_add_operand(d, choice_case_name.store, MirOperandRec(kind: mir_operand_switch_case(), owner: choice_switch.id, ordinal: 1, edge: 0, value: choice_payload.id, target: some_block.id, operand_type: 0, name_start: choice_case_name.start, name_end: choice_case_name.end))).store

    let ffi_value = try mir_add_value(d, store, main.id, "ffi_value", mir_type_i32(), mir_value_def_instruction(), some_block.id, 1)
    let ffi = try mir_add_instruction(d, ffi_value.store, MirInstrRec(function: main.id, block: some_block.id, ordinal: 0, op: mir_op_ffi_call_unsafe(), result: ffi_value.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: imported.id, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, ffi.store, MirOperandRec(kind: mir_operand_instruction(), owner: ffi.id, ordinal: 0, edge: 0, value: choice_payload.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store
    let identity_result = try mir_add_value(d, store, main.id, "identity_result", mir_type_i32(), mir_value_def_instruction(), some_block.id, 2)
    let call_identity = try mir_add_instruction(d, identity_result.store, MirInstrRec(function: main.id, block: some_block.id, ordinal: 1, op: mir_op_call(), result: identity_result.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: identity.id, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, call_identity.store, MirOperandRec(kind: mir_operand_instruction(), owner: call_identity.id, ordinal: 0, edge: 0, value: ffi_value.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store
    let overflow_result = try mir_add_value(d, store, main.id, "overflow_result", mir_type_i32(), mir_value_def_instruction(), some_block.id, 3)
    store = (try mir_add_instruction(d, overflow_result.store, MirInstrRec(function: main.id, block: some_block.id, ordinal: 2, op: mir_op_call(), result: overflow_result.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: overflow.id, name_start: 0, name_end: 0))).store
    let failure_worked = try mir_add_value(d, store, main.id, "failure_worked", mir_type_bool(), mir_value_def_instruction(), some_block.id, 4)
    store = (try mir_add_instruction(d, failure_worked.store, MirInstrRec(function: main.id, block: some_block.id, ordinal: 3, op: mir_op_int_eq(), result: failure_worked.id, place: 0, type_op: 0, a: overflow_result.id, b: zero.id, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let failure_branch = try mir_add_terminator(d, store, MirTermRec(function: main.id, block: some_block.id, kind: mir_term_branch(), value: failure_worked.id, target: 0, then_block: make_result.id, else_block: failure.id))
    store = (try mir_add_operand(d, failure_branch.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: failure_branch.id, ordinal: 0, edge: mir_edge_else(), value: overflow_result.id, target: failure.id, operand_type: 0, name_start: 0, name_end: 0))).store
    let none_jump = try mir_add_terminator(d, store, MirTermRec(function: main.id, block: none_block.id, kind: mir_term_jump(), value: 0, target: failure.id, then_block: 0, else_block: 0))
    store = (try mir_add_operand(d, none_jump.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: none_jump.id, ordinal: 0, edge: mir_edge_jump(), value: zero.id, target: failure.id, operand_type: 0, name_start: 0, name_end: 0))).store

    let result_value = try mir_add_value(d, store, main.id, "result", result.type_id, mir_value_def_instruction(), make_result.id, 1)
    let ok_name = try mir_append_name(d, result_value.store, "ok")
    store = (try mir_add_instruction(d, ok_name.store, MirInstrRec(function: main.id, block: make_result.id, ordinal: 0, op: mir_op_enum_construct(), result: result_value.id, place: 0, type_op: result.type_id, a: identity_result.id, b: 0, c: 0, target: 0, name_start: ok_name.start, name_end: ok_name.end))).store
    let ok_payload = try mir_add_value(d, store, main.id, "ok_payload", mir_type_i32(), mir_value_def_switch_case(), make_result.id, 1)
    let err_payload = try mir_add_value(d, ok_payload.store, main.id, "err_payload", mir_type_i32(), mir_value_def_switch_case(), make_result.id, 2)
    let result_switch = try mir_add_terminator(d, err_payload.store, MirTermRec(function: main.id, block: make_result.id, kind: mir_term_switch(), value: result_value.id, target: 0, then_block: 0, else_block: 0))
    let ok_case_name = try mir_append_name(d, result_switch.store, "ok")
    let ok_case = try mir_add_operand(d, ok_case_name.store, MirOperandRec(kind: mir_operand_switch_case(), owner: result_switch.id, ordinal: 0, edge: 0, value: ok_payload.id, target: ok_block.id, operand_type: 0, name_start: ok_case_name.start, name_end: ok_case_name.end))
    let err_case_name = try mir_append_name(d, ok_case.store, "err")
    store = (try mir_add_operand(d, err_case_name.store, MirOperandRec(kind: mir_operand_switch_case(), owner: result_switch.id, ordinal: 1, edge: 0, value: err_payload.id, target: err_block.id, operand_type: 0, name_start: err_case_name.start, name_end: err_case_name.end))).store
    let final_ok = try mir_add_value(d, store, main.id, "final_ok", mir_type_bool(), mir_value_def_instruction(), ok_block.id, 1)
    store = (try mir_add_instruction(d, final_ok.store, MirInstrRec(function: main.id, block: ok_block.id, ordinal: 0, op: mir_op_int_eq(), result: final_ok.id, place: 0, type_op: 0, a: ok_payload.id, b: four.id, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let final_branch = try mir_add_terminator(d, store, MirTermRec(function: main.id, block: ok_block.id, kind: mir_term_branch(), value: final_ok.id, target: 0, then_block: success.id, else_block: failure.id))
    store = (try mir_add_operand(d, final_branch.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: final_branch.id, ordinal: 0, edge: mir_edge_else(), value: ok_payload.id, target: failure.id, operand_type: 0, name_start: 0, name_end: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: main.id, block: err_block.id, kind: mir_term_fail(), value: err_payload.id, target: 0, then_block: 0, else_block: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: main.id, block: success.id, kind: mir_term_return(), value: zero.id, target: 0, then_block: 0, else_block: 0))).store
    return Ok((try mir_add_terminator(d, store, MirTermRec(function: main.id, block: failure.id, kind: mir_term_fail(), value: failed_value.id, target: 0, then_block: 0, else_block: 0))).store)
}

fn cgen_ffi_result_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let load = try mir_add_import(d, initial, "fixture_load", mir_type_i32())
    let save = try mir_add_import(d, load.store, "fixture_store", mir_type_unit())
    var store = try mir_add_import_param(d, save.store, save.id, 0, mir_type_i32())
    let main = try mir_add_function(d, store, "main", mir_type_i32())
    let entry = try mir_add_block(d, main.store, main.id, 0, "entry")
    let loaded = try mir_add_value(d, entry.store, main.id, "loaded", mir_type_i32(), mir_value_def_instruction(), entry.id, 1)
    let load_call = try mir_add_instruction(d, loaded.store, MirInstrRec(function: main.id, block: entry.id, ordinal: 0, op: mir_op_ffi_call_unsafe(), result: loaded.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: load.id, name_start: 0, name_end: 0))
    let store_call = try mir_add_instruction(d, load_call.store, MirInstrRec(function: main.id, block: entry.id, ordinal: 1, op: mir_op_ffi_call_unsafe(), result: 0, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: save.id, name_start: 0, name_end: 0))
    store = (try mir_add_operand(d, store_call.store, MirOperandRec(kind: mir_operand_instruction(), owner: store_call.id, ordinal: 0, edge: 0, value: loaded.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store
    return Ok((try mir_add_terminator(d, store, MirTermRec(function: main.id, block: entry.id, kind: mir_term_return(), value: loaded.id, target: 0, then_block: 0, else_block: 0))).store)
}

fn cgen_unsupported_fixture(d: Domain, store: MirStore) -> Result(MirStore, __s0_Error) {
    let parts = try __s0_buffer_new(U64, d)
    let handle = try mir_intern_type(d, store, mir_type_kind_domain_handle(), 0, 0, 0, parts, 0)
    let bytes = try mir_intern_type(d, handle.store, mir_type_kind_slice(), mir_type_u8(), 0, 0, parts, 0)
    let nested = try mir_intern_type(d, bytes.store, mir_type_kind_slice(), bytes.type_id, 0, 0, parts, 0)
    let function = try mir_add_function(d, nested.store, "unsupported", mir_type_unit())
    let domain = try mir_add_function_param(d, function.store, function.id, 0, "domain", handle.type_id)
    let value = try mir_add_function_param(d, domain.store, function.id, 1, "value", nested.type_id)
    let block = try mir_add_block(d, value.store, function.id, 0, "entry")
    let copied = try mir_add_value(d, block.store, function.id, "copied", nested.type_id, mir_value_def_instruction(), block.id, 1)
    let copy = try mir_add_instruction(d, copied.store, MirInstrRec(function: function.id, block: block.id, ordinal: 0, op: mir_op_copy_to_domain(), result: copied.id, place: 0, type_op: 0, a: domain.id, b: value.id, c: 0, target: 0, name_start: 0, name_end: 0))
    return Ok((try mir_add_terminator(d, copy.store, MirTermRec(function: function.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}
`

func runCgenBodyConformance(t *testing.T, cc, root, exe string) {
	t.Helper()
	run := func(t *testing.T, mode string) string {
		t.Helper()
		dir := t.TempDir()
		for _, name := range []string{"!alder-core-cgen", mode} {
			if err := os.WriteFile(filepath.Join(dir, name), nil, 0o644); err != nil {
				t.Fatal(err)
			}
		}
		cmd := conformanceCommand(exe, "!alder-core-cgen", mode)
		cmd.Dir = dir
		output, err := cmd.Output()
		if err != nil {
			t.Fatalf("run body generator %q: %v", mode, err)
		}
		return string(output)
	}

	if verification := run(t, "!cgen-body-verify"); verification != "V 99 0\n" {
		t.Fatalf("body fixture failed verifier:\n%s", verification)
	}
	first := run(t, "!cgen-body")
	second := run(t, "!cgen-body")
	if first != second || first == "" {
		t.Fatal("body generation is empty or process-nondeterministic")
	}
	for _, fragment := range []string{
		"complete-verifier-gated Alder MIR 3",
		"alder_i64_add_checked",
		"alder_edge_5_",
		"alder_fn_identity_i32_0(alder_v",
		"(fixture_add_one)(alder_v",
		"switch (alder_v",
		".alder_u.alder_p1",
		"goto alder_b1",
		"return alder_v",
	} {
		if !strings.Contains(first, fragment) {
			t.Fatalf("generated body missing %q\n%s", fragment, first)
		}
	}
	if strings.Contains(first, "fixture_add_one)(alder_fn_") || strings.Contains(first, "alder_i64_add_checked(alder_fn_") {
		t.Fatal("generated C contains a nested side-effecting call expression")
	}
	if verification := run(t, "!cgen-ffi-result-verify"); verification != "V 97 0\n" {
		t.Fatalf("FFI result fixture failed verifier:\n%s", verification)
	}
	ffiFirst := run(t, "!cgen-ffi-result")
	ffiSecond := run(t, "!cgen-ffi-result")
	if ffiFirst == "" || ffiFirst != ffiSecond {
		t.Fatal("FFI result generation is empty or process-nondeterministic")
	}
	for _, fragment := range []string{"alder_v0 = (fixture_load)();", "(fixture_store)(alder_v0);"} {
		if !strings.Contains(ffiFirst, fragment) {
			t.Fatalf("generated FFI body missing %q\n%s", fragment, ffiFirst)
		}
	}
	if got := run(t, "!cgen-body-invalid"); got != "" {
		t.Fatalf("invalid MIR wrote %d bytes", len(got))
	}
	if verification := run(t, "!cgen-body-unsupported-verify"); verification != "V 98 0\n" {
		t.Fatalf("unsupported copy fixture failed verifier:\n%s", verification)
	}
	if got := run(t, "!cgen-body-unsupported"); got != "" {
		t.Fatalf("unsupported MIR wrote %d bytes", len(got))
	}

	dir := t.TempDir()
	cfile := filepath.Join(dir, "scalar-cfg.c")
	driver := filepath.Join(dir, "driver.c")
	program := filepath.Join(dir, "scalar-cfg.exe")
	if err := os.WriteFile(cfile, []byte(first), 0o644); err != nil {
		t.Fatal(err)
	}
	const driverSource = `#include "alder_host.h"
#include <stdint.h>
int32_t fixture_add_one(int32_t value) { return value + INT32_C(1); }
`
	if err := os.WriteFile(driver, []byte(driverSource), 0o644); err != nil {
		t.Fatal(err)
	}
	compileGeneratedProgram(t, cc, root, cfile, filepath.Join(root, "bootstrap", "alder_host.c"), program, "-DALDER_HOST_CONFORMANCE", driver)
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("scalar/CFG generated program: %v\n%s\n%s", err, output, first)
	}

	ffiCFile := filepath.Join(dir, "ffi-result.c")
	ffiDriver := filepath.Join(dir, "ffi-driver.c")
	ffiProgram := filepath.Join(dir, "ffi-result.exe")
	if err := os.WriteFile(ffiCFile, []byte(ffiFirst), 0o644); err != nil {
		t.Fatal(err)
	}
	const ffiDriverSource = `#include <stdint.h>
int32_t fixture_load(void) { return (int32_t)0; }
void fixture_store(int32_t value) { (void)value; }
`
	if err := os.WriteFile(ffiDriver, []byte(ffiDriverSource), 0o644); err != nil {
		t.Fatal(err)
	}
	compileGeneratedProgram(t, cc, root, ffiCFile, filepath.Join(root, "bootstrap", "alder_host.c"), ffiProgram, "-DALDER_HOST_CONFORMANCE", ffiDriver)
	if output, err := conformanceCommand(ffiProgram).CombinedOutput(); err != nil {
		t.Fatalf("FFI result generated program: %v\n%s\n%s", err, output, ffiFirst)
	}
}
