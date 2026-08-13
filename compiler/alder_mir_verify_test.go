package compiler

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const mirVerifyWrapper = `
import c alderhost_stdout_byte: fn(U8) -> Bool

fn vout(byte: U8) -> Bool { return unsafe c { alderhost_stdout_byte(byte) } }
fn vdigit(value: U64) -> Bool {
    if value == 0 { return vout(48) }
    if value == 1 { return vout(49) }
    if value == 2 { return vout(50) }
    if value == 3 { return vout(51) }
    if value == 4 { return vout(52) }
    if value == 5 { return vout(53) }
    if value == 6 { return vout(54) }
    if value == 7 { return vout(55) }
    if value == 8 { return vout(56) }
    return vout(57)
}
fn vu64(value: U64) -> Bool {
    if value >= 10 { if !vu64(value / 10) { return false } }
    return vdigit(value % 10)
}
fn vf(value: U64) -> Bool { return vout(32) && vu64(value) }

fn emit_verification(label: U64, result: MirVerifyOutput) -> Bool {
    if !vout(86) || !vf(label) || !vf(__s0_buffer_len(MirVerifyDiagRec, result.diagnostics)) || !vout(10) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(MirVerifyDiagRec, result.diagnostics) {
        let item = __s0_buffer_get(MirVerifyDiagRec, result.diagnostics, at)
        if !vout(68) || !vf(item.phase) || !vf(item.kind) || !vf(item.function) || !vf(item.block) || !vf(item.instruction) || !vf(item.terminator) || !vf(item.operand) || !vf(item.type_id) || !vf(item.declaration) || !vf(item.expected) || !vf(item.actual) || !vf(item.reference) || !vout(10) { return false }
        at = at + 1
    }
    return true
}

fn expect_verification(label: U64, result: MirVerifyOutput, expected: MirVerifyDiagRec) -> Bool {
    if __s0_buffer_len(MirVerifyDiagRec, result.diagnostics) != 1 { return emit_verification(label, result) }
    let item = __s0_buffer_get(MirVerifyDiagRec, result.diagnostics, 0)
    if item.phase != expected.phase || item.kind != expected.kind || item.function != expected.function || item.block != expected.block || item.instruction != expected.instruction || item.terminator != expected.terminator || item.operand != expected.operand || item.type_id != expected.type_id || item.declaration != expected.declaration || item.expected != expected.expected || item.actual != expected.actual || item.reference != expected.reference { return emit_verification(label, result) }
    return vout(69) && vf(label) && vf(item.phase) && vf(item.kind) && vout(10)
}

fn minimal(d: Domain, initial: MirStore, result_type: U64, with_entry_param: Bool) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "f", result_type)
    let block = try mir_add_block(d, function.store, function.id, 0, "entry")
    var store = block.store
    if with_entry_param {
        let parameter = try mir_add_block_param(d, store, function.id, block.id, 0, "x", mir_type_u64())
        store = parameter.store
    }
    let term = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(term.store)
}

fn call_fixture(d: Domain, initial: MirStore, result_type: U64, bind: Bool, ffi: Bool) -> Result(MirStore, __s0_Error) {
    var store = initial
    var target: U64 = 1
    if ffi {
        let imported = try mir_add_import(d, store, "callee", result_type)
        store = imported.store
        target = imported.id
    } else {
        let callee = try mir_add_function(d, store, "callee", result_type)
        let callee_block = try mir_add_block(d, callee.store, callee.id, 0, "entry")
        let callee_term = try mir_add_terminator(d, callee_block.store, MirTermRec(function: callee.id, block: callee_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
        store = callee_term.store
        target = callee.id
    }
    let caller = try mir_add_function(d, store, "caller", mir_type_unit())
    let block = try mir_add_block(d, caller.store, caller.id, 0, "entry")
    store = block.store
    var result: U64 = 0
    if bind {
        let value = try mir_add_value(d, store, caller.id, "result", result_type, mir_value_def_instruction(), block.id, 1)
        store = value.store
        result = value.id
    }
    var op = mir_op_call()
    if ffi { op = mir_op_ffi_call_unsafe() }
    let instruction = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 0, op: op, result: result, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: target, name_start: 0, name_end: 0))
    let term = try mir_add_terminator(d, instruction.store, MirTermRec(function: caller.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(term.store)
}

fn jump_fixture(d: Domain, initial: MirStore, target: U64) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "jumping", mir_type_unit())
    let entry = try mir_add_block(d, function.store, function.id, 0, "entry")
    let destination = try mir_add_block(d, entry.store, function.id, 1, "destination")
    let parameter = try mir_add_block_param(d, destination.store, function.id, destination.id, 0, "x", mir_type_u64())
    let jump = try mir_add_terminator(d, parameter.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_jump(), value: 0, target: target, then_block: 0, else_block: 0))
    let done = try mir_add_terminator(d, jump.store, MirTermRec(function: function.id, block: destination.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn switch_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let option = try mir_intern_type(d, initial, mir_type_kind_option(), mir_type_u64(), 0, 0, empty, 0)
    let function = try mir_add_function(d, option.store, "switching", mir_type_unit())
    let parameter = try mir_add_function_param(d, function.store, function.id, 0, "choice", option.type_id)
    let entry = try mir_add_block(d, parameter.store, function.id, 0, "entry")
    let first = try mir_add_block(d, entry.store, function.id, 1, "first")
    let second = try mir_add_block(d, first.store, function.id, 2, "second")
    var store = second.store
    var binding: U64 = 0
    if mode == 4 || mode == 5 {
        let value = try mir_add_value(d, store, function.id, "payload", mir_type_unit(), mir_value_def_switch_case(), entry.id, 1)
        store = value.store
        binding = value.id
    }
    let dispatch = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_switch(), value: parameter.id, target: 0, then_block: 0, else_block: 0))
    let first_term = try mir_add_terminator(d, dispatch.store, MirTermRec(function: function.id, block: first.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let second_term = try mir_add_terminator(d, first_term.store, MirTermRec(function: function.id, block: second.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    store = second_term.store
    if mode == 1 || mode == 3 || mode == 5 {
        let named = try mir_append_name(d, store, "none")
        var value: U64 = 0
        if mode == 5 { value = binding }
        let one = try mir_add_operand(d, named.store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 0, edge: 0, value: value, target: first.id, operand_type: 0, name_start: named.start, name_end: named.end))
        store = one.store
    }
    if mode == 1 {
        let named = try mir_append_name(d, store, "none")
        let two = try mir_add_operand(d, named.store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 1, edge: 0, value: 0, target: second.id, operand_type: 0, name_start: named.start, name_end: named.end))
        store = two.store
    }
    if mode == 1 || mode == 5 {
        var ordinal: U64 = 1
        if mode == 1 { ordinal = 2 }
        let fallback = try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: ordinal, edge: 0, value: 0, target: second.id, operand_type: 0, name_start: 0, name_end: 0))
        store = fallback.store
    }
    if mode == 2 {
        let one = try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 0, edge: 0, value: 0, target: first.id, operand_type: 0, name_start: 0, name_end: 0))
        let two = try mir_add_operand(d, one.store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 1, edge: 0, value: 0, target: second.id, operand_type: 0, name_start: 0, name_end: 0))
        store = two.store
    }
    if mode == 4 {
        let fallback = try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 0, edge: 0, value: binding, target: first.id, operand_type: 0, name_start: 0, name_end: 0))
        store = fallback.store
    }
    return Ok(store)
}

fn dominance_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "dominance", mir_type_u64())
    let entry = try mir_add_block(d, function.store, function.id, 0, "entry")
    let later = try mir_add_block(d, entry.store, function.id, 1, "later")
    let parameter = try mir_add_block_param(d, later.store, function.id, later.id, 0, "x", mir_type_u64())
    let first = try mir_add_terminator(d, parameter.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: parameter.id, target: 0, then_block: 0, else_block: 0))
    let second = try mir_add_terminator(d, first.store, MirTermRec(function: function.id, block: later.id, kind: mir_term_return(), value: parameter.id, target: 0, then_block: 0, else_block: 0))
    return Ok(second.store)
}

fn initialization_fixture(d: Domain, initial: MirStore, initialize: Bool) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "initialization", mir_type_u64())
    let source = try mir_add_function_param(d, function.store, function.id, 0, "source", mir_type_u64())
    let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
    let local = try mir_add_local(d, entry.store, function.id, 0, "slot", mir_type_u64())
    let place = try mir_add_place(d, local.store, MirPlaceRec(function: function.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    var store = place.store
    var ordinal: U64 = 0
    if initialize {
        let write = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_store(), result: 0, place: place.id, type_op: 0, a: source.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
        store = write.store
        ordinal = ordinal + 1
    }
    let loaded = try mir_add_value(d, store, function.id, "loaded", mir_type_u64(), mir_value_def_instruction(), entry.id, ordinal + 1)
    let read = try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let done = try mir_add_terminator(d, read.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: loaded.id, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn checked_position_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "checked_position", mir_type_u64())
    let left = try mir_add_function_param(d, function.store, function.id, 0, "left", mir_type_u64())
    let right = try mir_add_function_param(d, left.store, function.id, 1, "right", mir_type_u64())
    let entry = try mir_add_block(d, right.store, function.id, 0, "entry")
    let failure = try mir_add_block(d, entry.store, function.id, 1, "failure")
    let error_value = try mir_add_block_param(d, failure.store, function.id, failure.id, 0, "error_value", mir_type_u64())
    let sum = try mir_add_value(d, error_value.store, function.id, "sum", mir_type_u64(), mir_value_def_instruction(), entry.id, 1)
    let checked = try mir_add_instruction(d, sum.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_int_add_checked(), result: sum.id, place: 0, type_op: 0, a: left.id, b: right.id, c: 0, target: failure.id, name_start: 0, name_end: 0))
    let fail_arg = try mir_add_operand(d, checked.store, MirOperandRec(kind: mir_operand_checked_edge_arg(), owner: checked.id, ordinal: 0, edge: 0, value: sum.id, target: failure.id, operand_type: 0, name_start: 0, name_end: 0))
    let success = try mir_add_terminator(d, fail_arg.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: sum.id, target: 0, then_block: 0, else_block: 0))
    let failed = try mir_add_terminator(d, success.store, MirTermRec(function: function.id, block: failure.id, kind: mir_term_return(), value: error_value.id, target: 0, then_block: 0, else_block: 0))
    return Ok(failed.store)
}

fn run_cases(d: Domain, initial: MirStore) -> Result(Bool, __s0_Error) {
    let valid_store = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
    let valid = try mir_verify_module(d, valid_store, 3)
    if !emit_verification(0, valid) { return Ok(false) }

    let empty_types = try __s0_buffer_new(MirTypeRec, d)
    let phase1 = try mir_verify_module(d, mir_with_types(valid_store, empty_types), 3)
    if !emit_verification(1, phase1) { return Ok(false) }

    let phase2_store = try minimal(d, try mir_store_new(d), 999, false)
    let phase2 = try mir_verify_module(d, phase2_store, 3)
    if !emit_verification(2, phase2) { return Ok(false) }

    let phase3_store = try minimal(d, try mir_store_new(d), mir_type_unit(), true)
    let phase3 = try mir_verify_module(d, phase3_store, 3)
    if !emit_verification(3, phase3) { return Ok(false) }

    let fail_fast = try mir_verify_module(d, phase2_store, 99)
    if !emit_verification(4, fail_fast) { return Ok(false) }

    let forged_base = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
    let entry = __s0_buffer_get(MirBlockRec, forged_base.blocks, 0)
    let forged_values = try __s0_buffer_append(MirValueRec, d, forged_base.values, MirValueRec(function: 1, ordinal: 0, name_start: entry.name_start, name_end: entry.name_end, value_type: mir_type_unit(), def_kind: mir_value_def_instruction(), block: 1, item: 1))
    let forged = try mir_verify_module(d, mir_with_values(forged_base, forged_values), 3)
    if !expect_verification(5, forged, mir_vdiag(1, mir_vdiag_bad_reciprocal(), 1, 1, 0, 0, 0, 0, 1, 1, 0, 1)) { return Ok(false) }

    let cyclic_base = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
    let cyclic_entry = __s0_buffer_get(MirBlockRec, cyclic_base.blocks, 0)
    let cyclic_places = try __s0_buffer_append(MirPlaceRec, d, cyclic_base.places, MirPlaceRec(function: 1, kind: mir_place_field(), local: 0, base: 1, field_start: cyclic_entry.name_start, field_end: cyclic_entry.name_end, deref_value: 0))
    let cyclic = try mir_verify_module(d, mir_with_places(cyclic_base, cyclic_places), 3)
    if !expect_verification(6, cyclic, mir_vdiag(1, mir_vdiag_bad_place(), 1, 0, 0, 0, 0, 0, 1, 0, 0, 1)) { return Ok(false) }

    let bad_child_base = try mir_store_new(d)
    let bad_child_types = try __s0_buffer_append(MirTypeRec, d, bad_child_base.types, MirTypeRec(kind: mir_type_kind_slice(), name_start: 0, name_end: 0, elem: 999, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0))
    let bad_child = try mir_verify_module(d, mir_with_types(bad_child_base, bad_child_types), 3)
    if !expect_verification(7, bad_child, mir_vdiag(2, mir_vdiag_bad_type_child(), 0, 0, 0, 0, 0, 13, 13, 0, 0, 999)) { return Ok(false) }

    let enum_step = try mir_add_named_type(d, try mir_store_new(d), mir_type_kind_enum(), "E")
    let empty_enum = try mir_verify_module(d, enum_step.store, 3)
    if !expect_verification(8, empty_enum, mir_vdiag(2, mir_vdiag_empty_enum(), 0, 0, 0, 0, 0, enum_step.type_id, enum_step.type_id, 1, 0, 0)) { return Ok(false) }

    let cycle_step = try mir_add_named_type(d, try mir_store_new(d), mir_type_kind_aggregate(), "A")
    let cycle_store = try mir_add_type_part(d, cycle_step.store, mir_type_part_field(), cycle_step.type_id, 0, "self", cycle_step.type_id)
    let cycle = try mir_verify_module(d, cycle_store, 3)
    if !expect_verification(9, cycle, mir_vdiag(2, mir_vdiag_type_cycle(), 0, 0, 0, 0, 0, cycle_step.type_id, cycle_step.type_id, 0, 0, cycle_step.type_id)) { return Ok(false) }

    let range_const = try mir_add_const(d, try mir_store_new(d), "large", mir_type_u8(), mir_const_int(), 0, 300, 0, "")
    let bad_const = try mir_verify_module(d, range_const.store, 3)
    if !expect_verification(10, bad_const, mir_vdiag(2, mir_vdiag_bad_constant(), 0, 0, 0, 0, 0, mir_type_u8(), 1, 0, mir_const_int(), 0)) { return Ok(false) }

    let no_parts = try __s0_buffer_new(U64, d)
    let view_step = try mir_intern_type(d, try mir_store_new(d), mir_type_kind_table_view(), mir_type_u8(), 0, 0, no_parts, 0)
    let view_function = try minimal(d, view_step.store, view_step.type_id, false)
    let bad_view = try mir_verify_module(d, view_function, 3)
    if !expect_verification(11, bad_view, mir_vdiag(2, mir_vdiag_ephemeral_type(), 1, 0, 0, 0, 0, view_step.type_id, 1, 0, mir_type_kind_table_view(), view_step.type_id)) { return Ok(false) }

    let unreachable_base = try mir_store_new(d)
    let unreachable_function = try mir_add_function(d, unreachable_base, "unreachable", mir_type_unit())
    let unreachable_block = try mir_add_block(d, unreachable_function.store, unreachable_function.id, 0, "entry")
    let unreachable_term = try mir_add_terminator(d, unreachable_block.store, MirTermRec(function: unreachable_function.id, block: unreachable_block.id, kind: mir_term_unreachable(), value: 0, target: 0, then_block: 0, else_block: 0))
    let only_unreachable = unreachable_term.store
    let reachable = try mir_verify_module(d, only_unreachable, 3)
    if !expect_verification(12, reachable, mir_vdiag(3, mir_vdiag_reachable_unreachable(), 1, 1, 0, 1, 0, 0, 0, 0, 0, 0)) { return Ok(false) }

    let unit_call = try call_fixture(d, try mir_store_new(d), mir_type_unit(), false, false)
    let unit_call_result = try mir_verify_module(d, unit_call, 3)
    if !emit_verification(13, unit_call_result) { return Ok(false) }
    let bound_unit_call = try call_fixture(d, try mir_store_new(d), mir_type_unit(), true, false)
    let bound_unit_result = try mir_verify_module(d, bound_unit_call, 3)
    if !emit_verification(14, bound_unit_result) { return Ok(false) }
    let unit_ffi = try call_fixture(d, try mir_store_new(d), mir_type_unit(), false, true)
    let unit_ffi_result = try mir_verify_module(d, unit_ffi, 3)
    if !emit_verification(15, unit_ffi_result) { return Ok(false) }
    let missing_result_call = try call_fixture(d, try mir_store_new(d), mir_type_u64(), false, false)
    let missing_result = try mir_verify_module(d, missing_result_call, 3)
    if !expect_verification(16, missing_result, mir_vdiag(1, mir_vdiag_bad_result(), 2, 1, 1, 0, 0, 0, 1, 0, 0, 0)) { return Ok(false) }

    let short_edge = try jump_fixture(d, try mir_store_new(d), 2)
    let arity = try mir_verify_module(d, short_edge, 3)
    if !expect_verification(17, arity, mir_vdiag(3, mir_vdiag_edge_arity(), 1, 1, 0, 1, 0, 0, 0, 1, 0, 2)) { return Ok(false) }
    let foreign_edge = try jump_fixture(d, try mir_store_new(d), 99)
    let foreign = try mir_verify_module(d, foreign_edge, 3)
    if !expect_verification(18, foreign, mir_vdiag(3, mir_vdiag_foreign_target(), 1, 1, 0, 1, 0, 0, 0, 0, 0, 99)) { return Ok(false) }

    let duplicate_switch = try switch_fixture(d, try mir_store_new(d), 1)
    let duplicate = try mir_verify_module(d, duplicate_switch, 3)
    if !expect_verification(19, duplicate, mir_vdiag(3, mir_vdiag_duplicate_case(), 1, 1, 0, 1, 2, 13, 0, 0, 0, 1)) { return Ok(false) }
    let defaults_switch = try switch_fixture(d, try mir_store_new(d), 2)
    let defaults = try mir_verify_module(d, defaults_switch, 3)
    if !expect_verification(20, defaults, mir_vdiag(3, mir_vdiag_duplicate_default(), 1, 1, 0, 1, 0, 13, 0, 1, 2, 0)) { return Ok(false) }
    let partial_switch = try switch_fixture(d, try mir_store_new(d), 3)
    let partial = try mir_verify_module(d, partial_switch, 3)
    if !expect_verification(21, partial, mir_vdiag(3, mir_vdiag_nonexhaustive_switch(), 1, 1, 0, 1, 0, 13, 0, 0, 0, 0)) { return Ok(false) }
    let bound_default_switch = try switch_fixture(d, try mir_store_new(d), 4)
    let bound_default = try mir_verify_module(d, bound_default_switch, 3)
    if !expect_verification(22, bound_default, mir_vdiag(3, mir_vdiag_default_binding(), 1, 1, 0, 1, 1, 13, 0, 0, 0, 2)) { return Ok(false) }
    let unit_binding_switch = try switch_fixture(d, try mir_store_new(d), 5)
    let unit_binding = try mir_verify_module(d, unit_binding_switch, 3)
    if !expect_verification(23, unit_binding, mir_vdiag(3, mir_vdiag_unit_binding(), 1, 1, 0, 1, 1, 13, 0, 0, 0, 2)) { return Ok(false) }

    let duplicate_base = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
    let local_name = try mir_append_name(d, duplicate_base, "slot")
    var duplicate_locals = try __s0_buffer_append(MirLocalRec, d, local_name.store.locals, MirLocalRec(function: 1, ordinal: 0, name_start: local_name.start, name_end: local_name.end, local_type: mir_type_u64()))
    duplicate_locals = try __s0_buffer_append(MirLocalRec, d, duplicate_locals, MirLocalRec(function: 1, ordinal: 0, name_start: local_name.start, name_end: local_name.end, local_type: mir_type_u64()))
    let duplicate_local = try mir_verify_module(d, mir_with_locals(local_name.store, duplicate_locals), 3)
    if !expect_verification(24, duplicate_local, mir_vdiag(1, mir_vdiag_bad_ordinal(), 1, 0, 0, 0, 0, 0, 2, 1, 0, 0)) { return Ok(false) }

    let orphan_base = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
    let orphan_operands = try __s0_buffer_append(MirOperandRec, d, orphan_base.operands, MirOperandRec(kind: mir_operand_instruction(), owner: 99, ordinal: 0, edge: 0, value: 0, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    let orphan_operand = try mir_verify_module(d, mir_with_operands(orphan_base, orphan_operands), 3)
    if !expect_verification(25, orphan_operand, mir_vdiag(1, mir_vdiag_bad_owner(), 0, 0, 0, 0, 1, 0, 1, 0, mir_operand_instruction(), 99)) { return Ok(false) }

    let imported = try mir_add_import(d, try mir_store_new(d), "foreign", mir_type_unit())
    let bad_import_store = try mir_add_import_param(d, imported.store, imported.id, 0, 999)
    let bad_import = try mir_verify_module(d, bad_import_store, 3)
    if !expect_verification(26, bad_import, mir_vdiag(2, mir_vdiag_bad_signature(), 0, 0, 0, 0, 0, 999, 1, 0, 0, 999)) { return Ok(false) }

    let aggregate = try mir_add_named_type(d, try mir_store_new(d), mir_type_kind_aggregate(), "Pair")
    let field_one = try mir_add_type_part(d, aggregate.store, mir_type_part_field(), aggregate.type_id, 0, "value", mir_type_u64())
    let field_two = try mir_add_type_part(d, field_one, mir_type_part_field(), aggregate.type_id, 1, "value", mir_type_u64())
    let duplicate_field = try mir_verify_module(d, field_two, 3)
    if !expect_verification(27, duplicate_field, mir_vdiag(2, mir_vdiag_duplicate_member(), 0, 0, 0, 0, 0, aggregate.type_id, 2, 0, 0, 1)) { return Ok(false) }

    let missing_edge = try jump_fixture(d, try mir_store_new(d), 0)
    let missing_target = try mir_verify_module(d, missing_edge, 3)
    if !expect_verification(28, missing_target, mir_vdiag(3, mir_vdiag_missing_target(), 1, 1, 0, 1, 0, 0, 0, 0, 0, 0)) { return Ok(false) }

    let malformed_base = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
    var malformed_terms = try __s0_buffer_new(MirTermRec, d)
    malformed_terms = try __s0_buffer_append(MirTermRec, d, malformed_terms, MirTermRec(function: 1, block: 1, kind: mir_term_branch(), value: 0, target: 0, then_block: 1, else_block: 1))
    let malformed_term = try mir_verify_module(d, mir_with_terminators(malformed_base, malformed_terms), 3)
    if !expect_verification(29, malformed_term, mir_vdiag(1, mir_vdiag_bad_shape(), 1, 1, 0, 1, 0, 0, 1, 1, 0, 0)) { return Ok(false) }

    let dominance = try mir_verify_module(d, try dominance_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(30, dominance, mir_vdiag(4, mir_vdiag_not_dominated(), 1, 1, 0, 1, 0, mir_type_u64(), 1, 0, 0, 1)) { return Ok(false) }
    let uninitialized = try mir_verify_module(d, try initialization_fixture(d, try mir_store_new(d), false), 3)
    if !expect_verification(31, uninitialized, mir_vdiag(4, mir_vdiag_uninitialized_load(), 1, 1, 1, 0, 1, mir_type_u64(), 0, 0, 0, 1)) { return Ok(false) }
    let initialized = try mir_verify_module(d, try initialization_fixture(d, try mir_store_new(d), true), 3)
    if !emit_verification(32, initialized) { return Ok(false) }
    let checked_position = try mir_verify_module(d, try checked_position_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(33, checked_position, mir_vdiag(4, mir_vdiag_not_dominated(), 1, 1, 1, 0, 1, mir_type_u64(), 4, 0, 0, 4)) { return Ok(false) }
    return Ok(true)
}

fn written_status(written: Bool) -> I32 {
    if written { return 0 }
    return 4
}

fn main(d: Domain) -> I32 {
    return match mir_store_new(d) {
        Err(error) => 3
        Ok(store) => match run_cases(d, store) {
            Err(error) => 3
            Ok(written) => written_status(written)
        }
    }
}
`

func runMIRVerifierConformance(t *testing.T, exe string) {
	want := "V 0 0\nV 1 1\nD 1 2 0 0 0 0 0 0 0 12 0 0\nV 2 1\nD 2 21 1 0 0 0 0 999 1 0 0 999\nV 3 1\nD 3 25 1 1 0 0 0 0 0 0 1 0\nV 4 1\nD 1 1 0 0 0 0 0 0 0 1 99 3\nE 5 1 9\nE 6 1 14\nE 7 2 16\nE 8 2 17\nE 9 2 20\nE 10 2 22\nE 11 2 23\nE 12 3 36\nV 13 0\nV 14 0\nV 15 0\nE 16 1 12\nE 17 3 28\nE 18 3 27\nE 19 3 32\nE 20 3 30\nE 21 3 35\nE 22 3 31\nE 23 3 34\nE 24 1 7\nE 25 1 6\nE 26 2 21\nE 27 2 18\nE 28 3 26\nE 29 1 11\nE 30 4 37\nE 31 4 38\nV 32 0\nE 33 4 37\n"
	var baseline string
	for i := 0; i < 3; i++ {
		dir := t.TempDir()
		const sentinel = "!alder-core-verifier"
		if err := os.WriteFile(filepath.Join(dir, sentinel), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command(exe, sentinel)
		cmd.Dir = dir
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil || stderr.Len() != 0 {
			t.Fatalf("run verifier wrapper %d: %v stderr=%q stdout=%q", i, err, stderr.String(), stdout.String())
		}
		if output := stdout.String(); output != want {
			t.Fatalf("verifier manifest mismatch\nwant:\n%s\ngot:\n%s", want, output)
		} else if i == 0 {
			baseline = output
		} else if output != baseline {
			t.Fatal("verifier manifest changed across processes or working directories")
		}
	}
	if strings.Contains(baseline, "D 3 21") {
		t.Fatal("phase-2 diagnostic escaped first-phase fail-fast")
	}
}
