package compiler

import (
	"bytes"
	"os"
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

fn emit_complete(label: U64, result: MirVerifyCompleteOutput) -> Bool {
    var complete: U64 = 0
    var hosted: U64 = 0
    if result.complete { complete = 1 }
    if result.hosted { hosted = 1 }
    if !vout(67) || !vf(label) || !vf(__s0_buffer_len(MirVerifyDiagRec, result.diagnostics)) || !vf(complete) || !vf(hosted) || !vf(result.entry) || !vout(10) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(MirVerifyDiagRec, result.diagnostics) {
        let item = __s0_buffer_get(MirVerifyDiagRec, result.diagnostics, at)
        if !vout(68) || !vf(item.phase) || !vf(item.kind) || !vf(item.function) || !vf(item.block) || !vf(item.instruction) || !vf(item.terminator) || !vf(item.operand) || !vf(item.type_id) || !vf(item.declaration) || !vf(item.expected) || !vf(item.actual) || !vf(item.reference) || !vout(10) { return false }
        at = at + 1
    }
    return true
}

fn expect_complete(label: U64, result: MirVerifyCompleteOutput, complete: Bool, hosted: Bool, entry: U64, phase: U64, kind: U64) -> Bool {
	var actual_complete: U64 = 0
	var want_complete: U64 = 0
	var actual_hosted: U64 = 0
	var want_hosted: U64 = 0
	if result.complete { actual_complete = 1 }
	if complete { want_complete = 1 }
	if result.hosted { actual_hosted = 1 }
	if hosted { want_hosted = 1 }
	if actual_complete != want_complete || actual_hosted != want_hosted || result.entry != entry { return emit_complete(label, result) }
    if phase == 0 {
        if __s0_buffer_len(MirVerifyDiagRec, result.diagnostics) != 0 { return emit_complete(label, result) }
    } else {
        if __s0_buffer_len(MirVerifyDiagRec, result.diagnostics) == 0 { return emit_complete(label, result) }
        let first = __s0_buffer_get(MirVerifyDiagRec, result.diagnostics, 0)
        if first.phase != phase || first.kind != kind { return emit_complete(label, result) }
    }
    return emit_complete(label, result)
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

fn duplicate_value_name_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "duplicate_values", mir_type_unit())
    let first = try mir_add_function_param(d, function.store, function.id, 0, "first", mir_type_u64())
    let second = try mir_add_function_param(d, first.store, function.id, 1, "second", mir_type_u64())
    let block = try mir_add_block(d, second.store, function.id, 0, "entry")
    let term = try mir_add_terminator(d, block.store, MirTermRec(function: function.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let first_value = __s0_buffer_get(MirValueRec, term.store.values, 0)
    let second_value = __s0_buffer_get(MirValueRec, term.store.values, 1)
    var values = try __s0_buffer_new(MirValueRec, d)
    values = try __s0_buffer_append(MirValueRec, d, values, first_value)
    values = try __s0_buffer_append(MirValueRec, d, values, MirValueRec(function: second_value.function, ordinal: second_value.ordinal, name_start: first_value.name_start, name_end: first_value.name_end, value_type: second_value.value_type, def_kind: second_value.def_kind, block: second_value.block, item: second_value.item))
    return Ok(mir_with_values(term.store, values))
}

// Function-value operation fixtures for the format-5 ops, following the
// cross-function value-names template for the valid-store wiring. Mode 0
// accepts fn.value feeding call.value plus str.eq over two string
// constants; mode 1 points fn.value at a missing function; mode 2 calls a
// non-function value; mode 3 compares non-string operands; mode 4 compares
// string against bytes.
fn fn_value_ops_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    var store = initial
    let empty = try __s0_buffer_new(U64, d)
    let string_type = try mir_intern_type(d, store, mir_type_kind_string(), 0, 0, 0, empty, 0)
    store = string_type.store
    let bytes_type = try mir_intern_type(d, store, mir_type_kind_bytes(), 0, 0, 0, empty, 0)
    store = bytes_type.store
    let text = try mir_add_const(d, store, "lit", string_type.type_id, mir_const_string(), 0, 0, 0, "a")
    store = text.store
    let bytes = try mir_add_const(d, store, "litb", bytes_type.type_id, mir_const_string(), 0, 0, 0, "a")
    store = bytes.store
    let target = try mir_add_function(d, store, "callee", mir_type_u64())
    store = target.store
    let param = try mir_add_function_param(d, store, target.id, 0, "value", mir_type_u64())
    store = param.store
    let entry = try mir_add_block(d, store, target.id, 0, "entry")
    store = entry.store
    let term = try mir_add_terminator(d, store, MirTermRec(function: target.id, block: entry.id, kind: mir_term_return(), value: param.id, target: 0, then_block: 0, else_block: 0))
    store = term.store
    let caller = try mir_add_function(d, store, "caller", mir_type_unit())
    store = caller.store
    let argument = try mir_add_function_param(d, store, caller.id, 0, "argument", mir_type_u64())
    store = argument.store
    let block = try mir_add_block(d, store, caller.id, 0, "entry")
    store = block.store
    var params = try __s0_buffer_new(U64, d)
    params = try __s0_buffer_append(U64, d, params, mir_type_u64())
    let fn_type = try mir_intern_function_type(d, store, params, mir_type_u64(), 0)
    store = fn_type.store
    let made = try mir_add_value(d, store, caller.id, "made", fn_type.type_id, mir_value_def_instruction(), block.id, 1)
    store = made.store
    var made_target = target.id
    if mode == 1 { made_target = 99 }
    let made_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 0, op: mir_op_fn_value(), result: made.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: made_target, name_start: 0, name_end: 0))
    store = made_instr.store
    let called = try mir_add_value(d, store, caller.id, "called", mir_type_u64(), mir_value_def_instruction(), block.id, 2)
    store = called.store
    var call_operand = made.id
    if mode == 2 { call_operand = argument.id }
    let call_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 1, op: mir_op_call_value(), result: called.id, place: 0, type_op: 0, a: call_operand, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    store = call_instr.store
    let call_arg = try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_instruction(), owner: call_instr.id, ordinal: 0, edge: 0, value: argument.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    store = call_arg.store
    if mode == 0 || mode == 3 || mode == 4 {
        let left = try mir_add_value(d, store, caller.id, "left", string_type.type_id, mir_value_def_instruction(), block.id, 3)
        store = left.store
        let text_const = __s0_buffer_get(MirConstRec, store.constants, text.id - 1)
        let left_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 2, op: mir_op_const_get(), result: left.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: text_const.name_start, name_end: text_const.name_end))
        store = left_instr.store
        var right_type = string_type.type_id
        if mode == 4 { right_type = bytes_type.type_id }
        let right = try mir_add_value(d, store, caller.id, "right", right_type, mir_value_def_instruction(), block.id, 4)
        store = right.store
        var right_const_id = text.id
        if mode == 4 { right_const_id = bytes.id }
        let right_const = __s0_buffer_get(MirConstRec, store.constants, right_const_id - 1)
        let right_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 3, op: mir_op_const_get(), result: right.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: right_const.name_start, name_end: right_const.name_end))
        store = right_instr.store
        let compared = try mir_add_value(d, store, caller.id, "compared", mir_type_bool(), mir_value_def_instruction(), block.id, 5)
        store = compared.store
        var compare_left = left.id
        if mode == 3 { compare_left = argument.id }
        let compare_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 4, op: mir_op_str_eq(), result: compared.id, place: 0, type_op: 0, a: compare_left, b: right.id, c: 0, target: 0, name_start: 0, name_end: 0))
        store = compare_instr.store
    }
    let final = try mir_add_terminator(d, store, MirTermRec(function: caller.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(final.store)
}

// fn.value with the domain marker: mode 0 accepts a marked reference to a
// storage-model callee (leading domain parameter) that is called through
// call.value; mode 1 marks a callee whose leading parameter is not a
// domain; mode 2 marks a reference without the environment operand; mode 3
// puts the marker on a str.eq instead of a fn.value.
fn fn_value_domain_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    var store = initial
    let empty = try __s0_buffer_new(U64, d)
    let domain_type = try mir_intern_type(d, store, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    store = domain_type.store
    let target = try mir_add_function(d, store, "callee", mir_type_u64())
    store = target.store
    var first_type = domain_type.type_id
    if mode == 1 { first_type = mir_type_u64() }
    let dom_param = try mir_add_function_param(d, store, target.id, 0, "dom", first_type)
    store = dom_param.store
    let value_param = try mir_add_function_param(d, store, target.id, 1, "value", mir_type_u64())
    store = value_param.store
    let entry = try mir_add_block(d, store, target.id, 0, "entry")
    store = entry.store
    let term = try mir_add_terminator(d, store, MirTermRec(function: target.id, block: entry.id, kind: mir_term_return(), value: value_param.id, target: 0, then_block: 0, else_block: 0))
    store = term.store
    let caller = try mir_add_function(d, store, "caller", mir_type_unit())
    store = caller.store
    let caller_dom = try mir_add_function_param(d, store, caller.id, 0, "dom", domain_type.type_id)
    store = caller_dom.store
    let block = try mir_add_block(d, store, caller.id, 0, "entry")
    store = block.store
    var params = try __s0_buffer_new(U64, d)
    params = try __s0_buffer_append(U64, d, params, mir_type_u64())
    let fn_type = try mir_intern_function_type(d, store, params, mir_type_u64(), 0)
    store = fn_type.store
    let made = try mir_add_value(d, store, caller.id, "made", fn_type.type_id, mir_value_def_instruction(), block.id, 1)
    store = made.store
    var env_value = caller_dom.id
    if mode == 2 { env_value = 0 }
    let made_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 0, op: mir_op_fn_value(), result: made.id, place: 0, type_op: mir_fn_value_domain_marker(), a: env_value, b: 0, c: 0, target: target.id, name_start: 0, name_end: 0))
    store = made_instr.store
    if mode == 3 {
        let left = try mir_add_value(d, store, caller.id, "left", mir_type_bool(), mir_value_def_instruction(), block.id, 2)
        store = left.store
        let str_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 1, op: mir_op_str_eq(), result: left.id, place: 0, type_op: mir_fn_value_domain_marker(), a: caller_dom.id, b: caller_dom.id, c: 0, target: 0, name_start: 0, name_end: 0))
        store = str_instr.store
    } else {
        let called = try mir_add_value(d, store, caller.id, "called", mir_type_u64(), mir_value_def_instruction(), block.id, 2)
        store = called.store
        let call_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 1, op: mir_op_call_value(), result: called.id, place: 0, type_op: 0, a: made.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
        store = call_instr.store
        let const_made = try mir_add_const(d, store, "unit_arg", mir_type_u64(), mir_const_int(), 0, 1, 0, "")
        store = const_made.store
        let const_rec = __s0_buffer_get(MirConstRec, store.constants, const_made.id - 1)
        let arg = try mir_add_value(d, store, caller.id, "arg", mir_type_u64(), mir_value_def_instruction(), block.id, 3)
        store = arg.store
        let arg_instr = try mir_add_instruction(d, store, MirInstrRec(function: caller.id, block: block.id, ordinal: 2, op: mir_op_const_get(), result: arg.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: const_rec.name_start, name_end: const_rec.name_end))
        store = arg_instr.store
        let operand = try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_instruction(), owner: call_instr.id, ordinal: 0, edge: 0, value: arg.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
        store = operand.store
    }
    let final = try mir_add_terminator(d, store, MirTermRec(function: caller.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(final.store)
}

fn cross_function_value_names_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let first = try mir_add_function(d, initial, "first", mir_type_unit())
    let first_value = try mir_add_function_param(d, first.store, first.id, 0, "shared", mir_type_u64())
    let first_block = try mir_add_block(d, first_value.store, first.id, 0, "entry")
    let first_term = try mir_add_terminator(d, first_block.store, MirTermRec(function: first.id, block: first_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let second = try mir_add_function(d, first_term.store, "second", mir_type_unit())
    let second_value = try mir_add_function_param(d, second.store, second.id, 0, "shared", mir_type_u64())
    let second_block = try mir_add_block(d, second_value.store, second.id, 0, "entry")
    let second_term = try mir_add_terminator(d, second_block.store, MirTermRec(function: second.id, block: second_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(second_term.store)
}

fn duplicate_local_name_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "duplicate_locals", mir_type_unit())
    let block = try mir_add_block(d, function.store, function.id, 0, "entry")
    let first = try mir_add_local(d, block.store, function.id, 0, "slot", mir_type_u64())
    let second = try mir_add_local(d, first.store, function.id, 1, "slot", mir_type_u64())
    let term = try mir_add_terminator(d, second.store, MirTermRec(function: function.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(term.store)
}

fn cross_function_local_names_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let first = try mir_add_function(d, initial, "first", mir_type_unit())
    let first_block = try mir_add_block(d, first.store, first.id, 0, "entry")
    let first_local = try mir_add_local(d, first_block.store, first.id, 0, "shared", mir_type_u64())
    let first_term = try mir_add_terminator(d, first_local.store, MirTermRec(function: first.id, block: first_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let second = try mir_add_function(d, first_term.store, "second", mir_type_unit())
    let second_block = try mir_add_block(d, second.store, second.id, 0, "entry")
    let second_local = try mir_add_local(d, second_block.store, second.id, 0, "shared", mir_type_u64())
    let second_term = try mir_add_terminator(d, second_local.store, MirTermRec(function: second.id, block: second_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(second_term.store)
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

fn bad_store_type_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "bad_store", mir_type_unit())
    let source = try mir_add_function_param(d, function.store, function.id, 0, "source", mir_type_bool())
    let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
    let local = try mir_add_local(d, entry.store, function.id, 0, "slot", mir_type_u64())
    let place = try mir_add_place(d, local.store, MirPlaceRec(function: function.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    let write = try mir_add_instruction(d, place.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_store(), result: 0, place: place.id, type_op: 0, a: source.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let done = try mir_add_terminator(d, write.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn bad_result_type_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let function = try mir_add_function(d, initial, "bad_result", mir_type_u64())
    let source = try mir_add_function_param(d, function.store, function.id, 0, "source", mir_type_bool())
    let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
    let local = try mir_add_local(d, entry.store, function.id, 0, "slot", mir_type_bool())
    let place = try mir_add_place(d, local.store, MirPlaceRec(function: function.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    let write = try mir_add_instruction(d, place.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_store(), result: 0, place: place.id, type_op: 0, a: source.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let result = try mir_add_value(d, write.store, function.id, "loaded", mir_type_u64(), mir_value_def_instruction(), entry.id, 2)
    let load = try mir_add_instruction(d, result.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_load(), result: result.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let done = try mir_add_terminator(d, load.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: result.id, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn bad_call_arity_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let callee = try mir_add_function(d, initial, "callee", mir_type_unit())
    let parameter = try mir_add_function_param(d, callee.store, callee.id, 0, "value", mir_type_u64())
    let callee_entry = try mir_add_block(d, parameter.store, callee.id, 0, "entry")
    let callee_done = try mir_add_terminator(d, callee_entry.store, MirTermRec(function: callee.id, block: callee_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let caller = try mir_add_function(d, callee_done.store, "caller", mir_type_unit())
    let caller_entry = try mir_add_block(d, caller.store, caller.id, 0, "entry")
    let call = try mir_add_instruction(d, caller_entry.store, MirInstrRec(function: caller.id, block: caller_entry.id, ordinal: 0, op: mir_op_call(), result: 0, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: callee.id, name_start: 0, name_end: 0))
    let done = try mir_add_terminator(d, call.store, MirTermRec(function: caller.id, block: caller_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn readonly_store_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let reference = try mir_intern_type(d, initial, mir_type_kind_safe_ref(), mir_type_u64(), 0, 0, empty, 0)
    let function = try mir_add_function(d, reference.store, "readonly_store", mir_type_unit())
    let target = try mir_add_function_param(d, function.store, function.id, 0, "target", reference.type_id)
    let source = try mir_add_function_param(d, target.store, function.id, 1, "source", mir_type_u64())
    let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
    let place = try mir_add_place(d, entry.store, MirPlaceRec(function: function.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: target.id))
    let write = try mir_add_instruction(d, place.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_store(), result: 0, place: place.id, type_op: 0, a: source.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let done = try mir_add_terminator(d, write.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn bad_aggregate_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    let aggregate = try mir_add_named_type(d, initial, mir_type_kind_aggregate(), "Box")
    let field = try mir_add_type_part(d, aggregate.store, mir_type_part_field(), aggregate.type_id, 0, "value", mir_type_u64())
    let function = try mir_add_function(d, field, "bad_aggregate", aggregate.type_id)
    let source = try mir_add_function_param(d, function.store, function.id, 0, "source", mir_type_u64())
    let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
    let result = try mir_add_value(d, entry.store, function.id, "box", aggregate.type_id, mir_value_def_instruction(), entry.id, 1)
    let named = try mir_append_name(d, result.store, "other")
    let construct = try mir_add_instruction(d, named.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_aggregate_construct(), result: result.id, place: 0, type_op: aggregate.type_id, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let operand = try mir_add_operand(d, construct.store, MirOperandRec(kind: mir_operand_aggregate_field(), owner: construct.id, ordinal: 0, edge: 0, value: source.id, target: 0, operand_type: 0, name_start: named.start, name_end: named.end))
    let done = try mir_add_terminator(d, operand.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: result.id, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn closure_env_escape_fixture(d: Domain, initial: MirStore, retained: Bool, nests: Bool) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    let env_type = try mir_add_named_type(d, handle.store, mir_type_kind_aggregate(), "Env")
    // A literal whose body contains another literal records the domain that
    // owns its environment first; the seed capture follows.
    var fields = env_type.store
    var seed_ordinal: U64 = 0
    if nests {
        fields = try mir_add_type_part(d, fields, mir_type_part_field(), env_type.type_id, 0, "alder_env_domain", handle.type_id)
        seed_ordinal = 1
    }
    let field = try mir_add_type_part(d, fields, mir_type_part_field(), env_type.type_id, seed_ordinal, "seed", mir_type_u64())
    let env_ref = try mir_intern_type(d, field, mir_type_kind_safe_mut(), env_type.type_id, 0, 0, empty, 0)
    let thunk = try mir_add_function(d, env_ref.store, "thunk", mir_type_u64())
    let tx = try mir_add_function_param(d, thunk.store, thunk.id, 0, "x", mir_type_u64())
    let te = try mir_add_function_param(d, tx.store, thunk.id, 1, "env", env_ref.type_id)
    let tentry = try mir_add_block(d, te.store, thunk.id, 0, "entry")
    let tret = try mir_add_terminator(d, tentry.store, MirTermRec(function: thunk.id, block: tentry.id, kind: mir_term_return(), value: tx.id, target: 0, then_block: 0, else_block: 0))
    var params = try __s0_buffer_new(U64, d)
    params = try __s0_buffer_append(U64, d, params, mir_type_u64())
    let fn_type = try mir_intern_function_type(d, tret.store, params, mir_type_u64(), 0)
    let make = try mir_add_function(d, fn_type.store, "make", fn_type.type_id)
    let mdom = try mir_add_function_param(d, make.store, make.id, 0, "domain", handle.type_id)
    let mseed = try mir_add_function_param(d, mdom.store, make.id, 1, "seed", mir_type_u64())
    let entry = try mir_add_block(d, mseed.store, make.id, 0, "entry")
    let child = try mir_add_value(d, entry.store, make.id, "child", handle.type_id, mir_value_def_instruction(), entry.id, 1)
    let create = try mir_add_instruction(d, child.store, MirInstrRec(function: make.id, block: entry.id, ordinal: 0, op: mir_op_domain_create(), result: child.id, place: 0, type_op: 0, a: mdom.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let record = try mir_add_value(d, create.store, make.id, "record", env_type.type_id, mir_value_def_instruction(), entry.id, 2)
    let construct = try mir_add_instruction(d, record.store, MirInstrRec(function: make.id, block: entry.id, ordinal: 1, op: mir_op_aggregate_construct(), result: record.id, place: 0, type_op: env_type.type_id, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    var operands = construct.store
    if nests {
        let domain_name = try mir_append_name(d, operands, "alder_env_domain")
        let domain_operand = try mir_add_operand(d, domain_name.store, MirOperandRec(kind: mir_operand_aggregate_field(), owner: construct.id, ordinal: 0, edge: 0, value: child.id, target: 0, operand_type: 0, name_start: domain_name.start, name_end: domain_name.end))
        operands = domain_operand.store
    }
    let seed_name = try mir_append_name(d, operands, "seed")
    let operand = try mir_add_operand(d, seed_name.store, MirOperandRec(kind: mir_operand_aggregate_field(), owner: construct.id, ordinal: seed_ordinal, edge: 0, value: mseed.id, target: 0, operand_type: 0, name_start: seed_name.start, name_end: seed_name.end))
    // A nesting record needs no cross-domain copy: its domain field gives the
    // stored value provenance. Every other record is copied into the creating
    // child domain.
    var stored_value = record.id
    var tail_store = operand.store
    var next_ordinal: U64 = 2
    if !nests {
        let copied = try mir_add_value(d, operand.store, make.id, "copied", env_type.type_id, mir_value_def_instruction(), entry.id, 3)
        let copy_instr = try mir_add_instruction(d, copied.store, MirInstrRec(function: make.id, block: entry.id, ordinal: 2, op: mir_op_copy_to_domain(), result: copied.id, place: 0, type_op: 0, a: child.id, b: record.id, c: 0, target: 0, name_start: 0, name_end: 0))
        stored_value = copied.id
        tail_store = copy_instr.store
        next_ordinal = 3
    }
    let one = try mir_add_const(d, tail_store, "one", mir_type_u64(), mir_const_int(), 0, 1, 0, "")
    let one_rec = __s0_buffer_get(MirConstRec, one.store.constants, one.id - 1)
    let size = try mir_add_value(d, one.store, make.id, "size", mir_type_u64(), mir_value_def_instruction(), entry.id, next_ordinal + 1)
    let size_instr = try mir_add_instruction(d, size.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal, op: mir_op_const_get(), result: size.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: one_rec.name_start, name_end: one_rec.name_end))
    let slot = try mir_add_value(d, size_instr.store, make.id, "slot", env_ref.type_id, mir_value_def_instruction(), entry.id, next_ordinal + 2)
    let alloc_instr = try mir_add_instruction(d, slot.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal + 1, op: mir_op_alloc(), result: slot.id, place: 0, type_op: env_type.type_id, a: child.id, b: size.id, c: 0, target: 0, name_start: 0, name_end: 0))
    let slot_place = try mir_add_place(d, alloc_instr.store, MirPlaceRec(function: make.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: slot.id))
    let stored = try mir_add_instruction(d, slot_place.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal + 2, op: mir_op_store(), result: 0, place: slot_place.id, type_op: 0, a: stored_value, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let value = try mir_add_value(d, stored.store, make.id, "value", fn_type.type_id, mir_value_def_instruction(), entry.id, next_ordinal + 4)
    let make_value = try mir_add_instruction(d, value.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal + 3, op: mir_op_fn_value(), result: value.id, place: 0, type_op: 0, a: slot.id, b: 0, c: 0, target: thunk.id, name_start: 0, name_end: 0))
    // A retaining copy into the caller domain makes the escape complete; a
    // bare return still shares the environment of the destroyed child domain.
    var returned = value.id
    var tail = make_value
    var destroy_ordinal: U64 = next_ordinal + 4
    if retained {
        let local = try mir_add_local(d, make_value.store, make.id, 0, "f", fn_type.type_id)
        let local_place = try mir_add_place(d, local.store, MirPlaceRec(function: make.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        let stored_local = try mir_add_instruction(d, local_place.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal + 4, op: mir_op_store(), result: 0, place: local_place.id, type_op: 0, a: value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
        let loaded = try mir_add_value(d, stored_local.store, make.id, "loaded", fn_type.type_id, mir_value_def_instruction(), entry.id, next_ordinal + 6)
        let load_instr = try mir_add_instruction(d, loaded.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal + 5, op: mir_op_load(), result: loaded.id, place: local_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
        let result = try mir_add_value(d, load_instr.store, make.id, "result", fn_type.type_id, mir_value_def_instruction(), entry.id, next_ordinal + 7)
        let copy_out = try mir_add_instruction(d, result.store, MirInstrRec(function: make.id, block: entry.id, ordinal: next_ordinal + 6, op: mir_op_copy_to_domain(), result: result.id, place: 0, type_op: 0, a: mdom.id, b: loaded.id, c: 0, target: 0, name_start: 0, name_end: 0))
        returned = result.id
        tail = copy_out
        destroy_ordinal = next_ordinal + 7
    }
    let destroy = try mir_add_instruction(d, tail.store, MirInstrRec(function: make.id, block: entry.id, ordinal: destroy_ordinal, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: child.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let done = try mir_add_terminator(d, destroy.store, MirTermRec(function: make.id, block: entry.id, kind: mir_term_return(), value: returned, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn domain_lifetime_fixture(d: Domain, initial: MirStore, invalidate: Bool) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle_step = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    let reference = try mir_intern_type(d, handle_step.store, mir_type_kind_safe_mut(), mir_type_u8(), 0, 0, empty, 0)
    let handle = handle_step.type_id
    let function = try mir_add_function(d, reference.store, "domain_lifetime", mir_type_unit())
    let root = try mir_add_function_param(d, function.store, function.id, 0, "root", handle)
    let size = try mir_add_function_param(d, root.store, function.id, 1, "size", mir_type_u64())
    let entry = try mir_add_block(d, size.store, function.id, 0, "entry")
    let domain_value = try mir_add_value(d, entry.store, function.id, "domain", handle, mir_value_def_instruction(), entry.id, 1)
    let create = try mir_add_instruction(d, domain_value.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_domain_create(), result: domain_value.id, place: 0, type_op: 0, a: root.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let pointer = try mir_add_value(d, create.store, function.id, "pointer", reference.type_id, mir_value_def_instruction(), entry.id, 2)
    let allocate = try mir_add_instruction(d, pointer.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_alloc(), result: pointer.id, place: 0, type_op: mir_type_u8(), a: domain_value.id, b: size.id, c: 0, target: 0, name_start: 0, name_end: 0))
    var store = allocate.store
    var ordinal: U64 = 2
    if invalidate { let destroy = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: domain_value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
store = destroy.store
ordinal = ordinal + 1 }
    let place = try mir_add_place(d, store, MirPlaceRec(function: function.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: pointer.id))
    let loaded = try mir_add_value(d, place.store, function.id, "loaded", mir_type_u8(), mir_value_def_instruction(), entry.id, ordinal + 1)
    let read = try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    ordinal = ordinal + 1
    store = read.store
    if !invalidate { let destroy = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: domain_value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
store = destroy.store }
    let done = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

fn cleanup_fixture(d: Domain, initial: MirStore, close: Bool) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let scope_step = try mir_intern_type(d, initial, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
    let function = try mir_add_function(d, scope_step.store, "cleanup", mir_type_unit())
    let entry = try mir_add_block(d, function.store, function.id, 0, "entry")
    let scope = try mir_add_value(d, entry.store, function.id, "scope", scope_step.type_id, mir_value_def_instruction(), entry.id, 1)
    let begin = try mir_add_instruction(d, scope.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_cleanup_scope_begin(), result: scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    var store = begin.store
    if close { let run = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_cleanup_scope_run(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
let end = try mir_add_instruction(d, run.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 2, op: mir_op_cleanup_scope_end(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
store = end.store }
    let done = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(done.store)
}

// Modes: 1 destroys and 2 resets through the callback; 3 checks a deferred
// safe-reference argument after its domain has already been destroyed.
fn cleanup_callback_effect_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle_step = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    let mark_step = try mir_intern_type(d, handle_step.store, mir_type_kind_domain_mark(), 0, 0, 0, empty, 0)
    let ref_step = try mir_intern_type(d, mark_step.store, mir_type_kind_safe_mut(), mir_type_u8(), 0, 0, empty, 0)
    let scope_step = try mir_intern_type(d, ref_step.store, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
    let cleanup_step = try mir_intern_type(d, scope_step.store, mir_type_kind_cleanup_id(), 0, 0, 0, empty, 0)
    var callback_type = handle_step.type_id
    if mode == 3 { callback_type = ref_step.type_id }
    let callback = try mir_add_function(d, cleanup_step.store, "callback", mir_type_unit())
    let callback_arg = try mir_add_function_param(d, callback.store, callback.id, 0, "argument", callback_type)
    let callback_entry = try mir_add_block(d, callback_arg.store, callback.id, 0, "entry")
    var store = callback_entry.store
    if mode == 1 { store = (try mir_add_instruction(d, store, MirInstrRec(function: callback.id, block: callback_entry.id, ordinal: 0, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: callback_arg.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store }
    if mode == 2 { let mark = try mir_add_value(d, store, callback.id, "mark", mark_step.type_id, mir_value_def_instruction(), callback_entry.id, 1)
let marked = try mir_add_instruction(d, mark.store, MirInstrRec(function: callback.id, block: callback_entry.id, ordinal: 0, op: mir_op_domain_mark(), result: mark.id, place: 0, type_op: 0, a: callback_arg.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
store = (try mir_add_instruction(d, marked.store, MirInstrRec(function: callback.id, block: callback_entry.id, ordinal: 1, op: mir_op_domain_reset(), result: 0, place: 0, type_op: 0, a: callback_arg.id, b: mark.id, c: 0, target: 0, name_start: 0, name_end: 0))).store }
    if mode == 3 { let place = try mir_add_place(d, store, MirPlaceRec(function: callback.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: callback_arg.id))
let loaded = try mir_add_value(d, place.store, callback.id, "loaded", mir_type_u8(), mir_value_def_instruction(), callback_entry.id, 1)
store = (try mir_add_instruction(d, loaded.store, MirInstrRec(function: callback.id, block: callback_entry.id, ordinal: 0, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store }
    store = (try mir_add_terminator(d, store, MirTermRec(function: callback.id, block: callback_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store
	if mode != 3 {
		let wrapper = try mir_add_function(d, store, "wrapper", mir_type_unit())
		let wrapper_domain = try mir_add_function_param(d, wrapper.store, wrapper.id, 0, "domain", handle_step.type_id)
		let wrapper_entry = try mir_add_block(d, wrapper_domain.store, wrapper.id, 0, "entry")
		let wrapper_scope = try mir_add_value(d, wrapper_entry.store, wrapper.id, "scope", scope_step.type_id, mir_value_def_instruction(), wrapper_entry.id, 1)
		let wrapper_begin = try mir_add_instruction(d, wrapper_scope.store, MirInstrRec(function: wrapper.id, block: wrapper_entry.id, ordinal: 0, op: mir_op_cleanup_scope_begin(), result: wrapper_scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		let wrapper_cleanup = try mir_add_value(d, wrapper_begin.store, wrapper.id, "cleanup", cleanup_step.type_id, mir_value_def_instruction(), wrapper_entry.id, 2)
		let wrapper_push = try mir_add_instruction(d, wrapper_cleanup.store, MirInstrRec(function: wrapper.id, block: wrapper_entry.id, ordinal: 1, op: mir_op_cleanup_push(), result: wrapper_cleanup.id, place: 0, type_op: 0, a: wrapper_scope.id, b: 0, c: 0, target: callback.id, name_start: 0, name_end: 0))
		let wrapper_arg = try mir_add_operand(d, wrapper_push.store, MirOperandRec(kind: mir_operand_instruction(), owner: wrapper_push.id, ordinal: 0, edge: 0, value: wrapper_domain.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
		let wrapper_run = try mir_add_instruction(d, wrapper_arg.store, MirInstrRec(function: wrapper.id, block: wrapper_entry.id, ordinal: 2, op: mir_op_cleanup_scope_run(), result: 0, place: 0, type_op: 0, a: wrapper_scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		let wrapper_end = try mir_add_instruction(d, wrapper_run.store, MirInstrRec(function: wrapper.id, block: wrapper_entry.id, ordinal: 3, op: mir_op_cleanup_scope_end(), result: 0, place: 0, type_op: 0, a: wrapper_scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		let wrapper_done = try mir_add_terminator(d, wrapper_end.store, MirTermRec(function: wrapper.id, block: wrapper_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
		let caller = try mir_add_function(d, wrapper_done.store, "caller", mir_type_unit())
		let caller_domain = try mir_add_function_param(d, caller.store, caller.id, 0, "domain", handle_step.type_id)
		let caller_size = try mir_add_function_param(d, caller_domain.store, caller.id, 1, "size", mir_type_u64())
		let caller_entry = try mir_add_block(d, caller_size.store, caller.id, 0, "entry")
		let caller_pointer = try mir_add_value(d, caller_entry.store, caller.id, "pointer", ref_step.type_id, mir_value_def_instruction(), caller_entry.id, 1)
		let caller_alloc = try mir_add_instruction(d, caller_pointer.store, MirInstrRec(function: caller.id, block: caller_entry.id, ordinal: 0, op: mir_op_alloc(), result: caller_pointer.id, place: 0, type_op: mir_type_u8(), a: caller_domain.id, b: caller_size.id, c: 0, target: 0, name_start: 0, name_end: 0))
		let call = try mir_add_instruction(d, caller_alloc.store, MirInstrRec(function: caller.id, block: caller_entry.id, ordinal: 1, op: mir_op_call(), result: 0, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: wrapper.id, name_start: 0, name_end: 0))
		let call_arg = try mir_add_operand(d, call.store, MirOperandRec(kind: mir_operand_instruction(), owner: call.id, ordinal: 0, edge: 0, value: caller_domain.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
		let caller_place = try mir_add_place(d, call_arg.store, MirPlaceRec(function: caller.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: caller_pointer.id))
		let caller_loaded = try mir_add_value(d, caller_place.store, caller.id, "loaded", mir_type_u8(), mir_value_def_instruction(), caller_entry.id, 3)
		let caller_load = try mir_add_instruction(d, caller_loaded.store, MirInstrRec(function: caller.id, block: caller_entry.id, ordinal: 2, op: mir_op_load(), result: caller_loaded.id, place: caller_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		return Ok((try mir_add_terminator(d, caller_load.store, MirTermRec(function: caller.id, block: caller_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
	}
    let function = try mir_add_function(d, store, "cleanup_effect", mir_type_unit())
    let domain = try mir_add_function_param(d, function.store, function.id, 0, "domain", handle_step.type_id)
    let size = try mir_add_function_param(d, domain.store, function.id, 1, "size", mir_type_u64())
    let entry = try mir_add_block(d, size.store, function.id, 0, "entry")
    let pointer = try mir_add_value(d, entry.store, function.id, "pointer", ref_step.type_id, mir_value_def_instruction(), entry.id, 1)
    let allocate = try mir_add_instruction(d, pointer.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_alloc(), result: pointer.id, place: 0, type_op: mir_type_u8(), a: domain.id, b: size.id, c: 0, target: 0, name_start: 0, name_end: 0))
    let scope = try mir_add_value(d, allocate.store, function.id, "scope", scope_step.type_id, mir_value_def_instruction(), entry.id, 2)
    let begin = try mir_add_instruction(d, scope.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_cleanup_scope_begin(), result: scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let cleanup = try mir_add_value(d, begin.store, function.id, "cleanup", cleanup_step.type_id, mir_value_def_instruction(), entry.id, 3)
    let push = try mir_add_instruction(d, cleanup.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 2, op: mir_op_cleanup_push(), result: cleanup.id, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: callback.id, name_start: 0, name_end: 0))
    let push_arg = try mir_add_operand(d, push.store, MirOperandRec(kind: mir_operand_instruction(), owner: push.id, ordinal: 0, edge: 0, value: pointer.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    var ordinal: U64 = 3
    store = push_arg.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: domain.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
	ordinal = ordinal + 1
    let run = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_cleanup_scope_run(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let end = try mir_add_instruction(d, run.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal + 1, op: mir_op_cleanup_scope_end(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    store = end.store
    return Ok((try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}

fn cleanup_join_fixture(d: Domain, initial: MirStore, use_after: Bool) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle_step = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    let ref_step = try mir_intern_type(d, handle_step.store, mir_type_kind_safe_mut(), mir_type_u8(), 0, 0, empty, 0)
    let scope_step = try mir_intern_type(d, ref_step.store, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
    let cleanup_step = try mir_intern_type(d, scope_step.store, mir_type_kind_cleanup_id(), 0, 0, 0, empty, 0)
    let callback = try mir_add_function(d, cleanup_step.store, "destroy", mir_type_unit())
    let callback_domain = try mir_add_function_param(d, callback.store, callback.id, 0, "domain", handle_step.type_id)
    let callback_entry = try mir_add_block(d, callback_domain.store, callback.id, 0, "entry")
    let destroy = try mir_add_instruction(d, callback_entry.store, MirInstrRec(function: callback.id, block: callback_entry.id, ordinal: 0, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: callback_domain.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let callback_done = try mir_add_terminator(d, destroy.store, MirTermRec(function: callback.id, block: callback_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let function = try mir_add_function(d, callback_done.store, "join", mir_type_unit())
    let domain = try mir_add_function_param(d, function.store, function.id, 0, "domain", handle_step.type_id)
    let size = try mir_add_function_param(d, domain.store, function.id, 1, "size", mir_type_u64())
    let choose = try mir_add_function_param(d, size.store, function.id, 2, "choose", mir_type_bool())
    let entry = try mir_add_block(d, choose.store, function.id, 0, "entry")
    let left = try mir_add_block(d, entry.store, function.id, 1, "left")
    let right = try mir_add_block(d, left.store, function.id, 2, "right")
    let join = try mir_add_block(d, right.store, function.id, 3, "join")
    let pointer = try mir_add_value(d, join.store, function.id, "pointer", ref_step.type_id, mir_value_def_instruction(), entry.id, 1)
    let allocate = try mir_add_instruction(d, pointer.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_alloc(), result: pointer.id, place: 0, type_op: mir_type_u8(), a: domain.id, b: size.id, c: 0, target: 0, name_start: 0, name_end: 0))
    let scope = try mir_add_value(d, allocate.store, function.id, "scope", scope_step.type_id, mir_value_def_instruction(), entry.id, 2)
    let begin = try mir_add_instruction(d, scope.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_cleanup_scope_begin(), result: scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let branch = try mir_add_terminator(d, begin.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_branch(), value: choose.id, target: 0, then_block: left.id, else_block: right.id))
    let left_id = try mir_add_value(d, branch.store, function.id, "left_cleanup", cleanup_step.type_id, mir_value_def_instruction(), left.id, 1)
    let left_push = try mir_add_instruction(d, left_id.store, MirInstrRec(function: function.id, block: left.id, ordinal: 0, op: mir_op_cleanup_push(), result: left_id.id, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: callback.id, name_start: 0, name_end: 0))
    let left_arg = try mir_add_operand(d, left_push.store, MirOperandRec(kind: mir_operand_instruction(), owner: left_push.id, ordinal: 0, edge: 0, value: domain.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    let left_done = try mir_add_terminator(d, left_arg.store, MirTermRec(function: function.id, block: left.id, kind: mir_term_jump(), value: 0, target: join.id, then_block: 0, else_block: 0))
    let right_id = try mir_add_value(d, left_done.store, function.id, "right_cleanup", cleanup_step.type_id, mir_value_def_instruction(), right.id, 1)
    let right_push = try mir_add_instruction(d, right_id.store, MirInstrRec(function: function.id, block: right.id, ordinal: 0, op: mir_op_cleanup_push(), result: right_id.id, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: callback.id, name_start: 0, name_end: 0))
    let right_arg = try mir_add_operand(d, right_push.store, MirOperandRec(kind: mir_operand_instruction(), owner: right_push.id, ordinal: 0, edge: 0, value: domain.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    let right_done = try mir_add_terminator(d, right_arg.store, MirTermRec(function: function.id, block: right.id, kind: mir_term_jump(), value: 0, target: join.id, then_block: 0, else_block: 0))
    let run = try mir_add_instruction(d, right_done.store, MirInstrRec(function: function.id, block: join.id, ordinal: 0, op: mir_op_cleanup_scope_run(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let end = try mir_add_instruction(d, run.store, MirInstrRec(function: function.id, block: join.id, ordinal: 1, op: mir_op_cleanup_scope_end(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    var store = end.store
    if use_after { let place = try mir_add_place(d, store, MirPlaceRec(function: function.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: pointer.id))
let loaded = try mir_add_value(d, place.store, function.id, "loaded", mir_type_u8(), mir_value_def_instruction(), join.id, 3)
store = (try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: join.id, ordinal: 2, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store }
    return Ok((try mir_add_terminator(d, store, MirTermRec(function: function.id, block: join.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}

fn cleanup_lifo_fixture(d: Domain, initial: MirStore, parent_last: Bool) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle_step = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    let scope_step = try mir_intern_type(d, handle_step.store, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
    let cleanup_step = try mir_intern_type(d, scope_step.store, mir_type_kind_cleanup_id(), 0, 0, 0, empty, 0)
    let callback = try mir_add_function(d, cleanup_step.store, "destroy", mir_type_unit())
    let callback_domain = try mir_add_function_param(d, callback.store, callback.id, 0, "domain", handle_step.type_id)
    let callback_entry = try mir_add_block(d, callback_domain.store, callback.id, 0, "entry")
    let destroy = try mir_add_instruction(d, callback_entry.store, MirInstrRec(function: callback.id, block: callback_entry.id, ordinal: 0, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: callback_domain.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let callback_done = try mir_add_terminator(d, destroy.store, MirTermRec(function: callback.id, block: callback_entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let function = try mir_add_function(d, callback_done.store, "lifo", mir_type_unit())
    let parent = try mir_add_function_param(d, function.store, function.id, 0, "parent", handle_step.type_id)
    let entry = try mir_add_block(d, parent.store, function.id, 0, "entry")
    let child = try mir_add_value(d, entry.store, function.id, "child", handle_step.type_id, mir_value_def_instruction(), entry.id, 1)
    let create = try mir_add_instruction(d, child.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_domain_create(), result: child.id, place: 0, type_op: 0, a: parent.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let scope = try mir_add_value(d, create.store, function.id, "scope", scope_step.type_id, mir_value_def_instruction(), entry.id, 2)
    let begin = try mir_add_instruction(d, scope.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_cleanup_scope_begin(), result: scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let first_id = try mir_add_value(d, begin.store, function.id, "first", cleanup_step.type_id, mir_value_def_instruction(), entry.id, 3)
    let first_push = try mir_add_instruction(d, first_id.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 2, op: mir_op_cleanup_push(), result: first_id.id, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: callback.id, name_start: 0, name_end: 0))
    var first_arg_value = parent.id
    if parent_last { first_arg_value = child.id }
    let first_arg = try mir_add_operand(d, first_push.store, MirOperandRec(kind: mir_operand_instruction(), owner: first_push.id, ordinal: 0, edge: 0, value: first_arg_value, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    let second_id = try mir_add_value(d, first_arg.store, function.id, "second", cleanup_step.type_id, mir_value_def_instruction(), entry.id, 4)
    let second_push = try mir_add_instruction(d, second_id.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 3, op: mir_op_cleanup_push(), result: second_id.id, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: callback.id, name_start: 0, name_end: 0))
    var second_arg_value = child.id
    if parent_last { second_arg_value = parent.id }
    let second_arg = try mir_add_operand(d, second_push.store, MirOperandRec(kind: mir_operand_instruction(), owner: second_push.id, ordinal: 0, edge: 0, value: second_arg_value, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    let run = try mir_add_instruction(d, second_arg.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 4, op: mir_op_cleanup_scope_run(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let end = try mir_add_instruction(d, run.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 5, op: mir_op_cleanup_scope_end(), result: 0, place: 0, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    return Ok((try mir_add_terminator(d, end.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}

// mode 0 is valid; 1 misses and 3 duplicates lookup consumption; 2 mutates an
// active view; 4 misses and 5 duplicates view.end; 6 uses a view after end; 7
// mutates before consumption; 8/9 add failure bypass before consume/end; 10
// has two distinct uses after end; and 11 mutates an active view through
// table.insert.try, which counts as a mutation exactly like table.insert.
fn table_v8_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let row = try mir_add_named_type(d, initial, mir_type_kind_aggregate(), "Row")
    let field = try mir_add_type_part(d, row.store, mir_type_part_field(), row.type_id, 0, "x", mir_type_u64())
    let table = try mir_intern_type(d, field, mir_type_kind_table(), row.type_id, 0, 0, empty, 0)
    let id = try mir_intern_type(d, table.store, mir_type_kind_id(), row.type_id, 0, 0, empty, 0)
    let view = try mir_intern_type(d, id.store, mir_type_kind_table_view(), row.type_id, 0, 0, empty, 0)
    let option = try mir_intern_type(d, view.store, mir_type_kind_option(), view.type_id, 0, 0, empty, 0)
    let function = try mir_add_function(d, option.store, "table_case", mir_type_unit())
    let table_arg = try mir_add_function_param(d, function.store, function.id, 0, "table", table.type_id)
    let id_arg = try mir_add_function_param(d, table_arg.store, function.id, 1, "id", id.type_id)
    let row_arg = try mir_add_function_param(d, id_arg.store, function.id, 2, "row", row.type_id)
    var parameter_store = row_arg.store
	var number: U64 = 0
	if mode == 8 || mode == 9 {
		let number_arg = try mir_add_function_param(d, parameter_store, function.id, 3, "number", mir_type_u64())
		parameter_store = number_arg.store
		number = number_arg.id
	}
	let entry = try mir_add_block(d, parameter_store, function.id, 0, "entry")
    let failed = try mir_add_block(d, entry.store, function.id, 1, "failed")
    let found = try mir_add_value(d, failed.store, function.id, "found", option.type_id, mir_value_def_instruction(), entry.id, 1)
    let lookup = try mir_add_instruction(d, found.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_table_lookup(), result: found.id, place: 0, type_op: 0, a: table_arg.id, b: id_arg.id, c: 0, target: 0, name_start: 0, name_end: 0))
    var store = lookup.store
    var ordinal: U64 = 1
	if mode == 7 {
		let inserted = try mir_add_value(d, store, function.id, "inserted", id.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
		let insert = try mir_add_instruction(d, inserted.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_insert(), result: inserted.id, place: 0, type_op: 0, a: table_arg.id, b: row_arg.id, c: 0, target: 0, name_start: 0, name_end: 0))
		store = insert.store
		ordinal = ordinal + 1
	}
	if mode == 8 {
		let sum = try mir_add_value(d, store, function.id, "sum", mir_type_u64(), mir_value_def_instruction(), entry.id, ordinal + 1)
		let checked = try mir_add_instruction(d, sum.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_int_add_checked(), result: sum.id, place: 0, type_op: 0, a: number, b: number, c: 0, target: failed.id, name_start: 0, name_end: 0))
		store = checked.store
		ordinal = ordinal + 1
	}
    if mode != 1 {
        let value = try mir_add_value(d, store, function.id, "view", view.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
        let named = try mir_append_name(d, value.store, "some")
        let extract = try mir_add_instruction(d, named.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_enum_payload_checked(), result: value.id, place: 0, type_op: 0, a: found.id, b: 0, c: 0, target: failed.id, name_start: named.start, name_end: named.end))
        store = extract.store
        ordinal = ordinal + 1
        if mode == 2 {
            let inserted = try mir_add_value(d, store, function.id, "inserted", id.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
            let insert = try mir_add_instruction(d, inserted.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_insert(), result: inserted.id, place: 0, type_op: 0, a: table_arg.id, b: row_arg.id, c: 0, target: 0, name_start: 0, name_end: 0))
            store = insert.store
            ordinal = ordinal + 1
        }
        if mode == 11 {
            // table.insert.try counts as a table mutation while the view is
            // live, exactly like table.insert at the same position.
            let tried_type = try mir_intern_type(d, store, mir_type_kind_result(), 0, id.type_id, row.type_id, empty, 0)
            let tried = try mir_add_value(d, tried_type.store, function.id, "tried", tried_type.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
            let insert = try mir_add_instruction(d, tried.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_insert_try(), result: tried.id, place: 0, type_op: 0, a: table_arg.id, b: row_arg.id, c: 0, target: 0, name_start: 0, name_end: 0))
            store = insert.store
            ordinal = ordinal + 1
        }
		if mode == 9 {
			let sum = try mir_add_value(d, store, function.id, "sum", mir_type_u64(), mir_value_def_instruction(), entry.id, ordinal + 1)
			let checked = try mir_add_instruction(d, sum.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_int_add_checked(), result: sum.id, place: 0, type_op: 0, a: number, b: number, c: 0, target: failed.id, name_start: 0, name_end: 0))
			store = checked.store
			ordinal = ordinal + 1
		}
		if mode != 4 {
			let ended = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_view_end(), result: 0, place: 0, type_op: 0, a: value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
			store = ended.store
			ordinal = ordinal + 1
		}
		if mode == 5 {
			let ended_again = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_view_end(), result: 0, place: 0, type_op: 0, a: value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
			store = ended_again.store
			ordinal = ordinal + 1
		}
		if mode == 6 || mode == 10 {
			let place = try mir_add_place(d, store, MirPlaceRec(function: function.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: value.id))
			let loaded = try mir_add_value(d, place.store, function.id, "loaded", row.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
			let load = try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
			store = load.store
			ordinal = ordinal + 1
			if mode == 10 {
				let loaded_again = try mir_add_value(d, store, function.id, "loaded_again", row.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
				let load_again = try mir_add_instruction(d, loaded_again.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_load(), result: loaded_again.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
				store = load_again.store
			}
		}
		if mode == 3 {
			let value2 = try mir_add_value(d, store, function.id, "view2", view.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
			let named2 = try mir_append_name(d, value2.store, "some")
			let extract2 = try mir_add_instruction(d, named2.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_enum_payload_checked(), result: value2.id, place: 0, type_op: 0, a: found.id, b: 0, c: 0, target: failed.id, name_start: named2.start, name_end: named2.end))
			let end2 = try mir_add_instruction(d, extract2.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal + 1, op: mir_op_table_view_end(), result: 0, place: 0, type_op: 0, a: value2.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
			store = end2.store
		}
    }
    let done = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let failed_done = try mir_add_terminator(d, done.store, MirTermRec(function: function.id, block: failed.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(failed_done.store)
}

// Modes 0/1/2 mutate the source, a distinct created table, or the source after
// lookup through a callee result. They pin stable table identities and result
// provenance without adding another executable harness.
fn table_identity_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
	let empty = try __s0_buffer_new(U64, d)
	let handle = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
	let row = try mir_add_named_type(d, handle.store, mir_type_kind_aggregate(), "IdentityRow")
	let field = try mir_add_type_part(d, row.store, mir_type_part_field(), row.type_id, 0, "x", mir_type_u64())
	let table = try mir_intern_type(d, field, mir_type_kind_table(), row.type_id, 0, 0, empty, 0)
	let id = try mir_intern_type(d, table.store, mir_type_kind_id(), row.type_id, 0, 0, empty, 0)
	let view = try mir_intern_type(d, id.store, mir_type_kind_table_view(), row.type_id, 0, 0, empty, 0)
	let option = try mir_intern_type(d, view.store, mir_type_kind_option(), view.type_id, 0, 0, empty, 0)
	var store = option.store
	var pass_id: U64 = 0
	if mode == 2 {
		let pass = try mir_add_function(d, store, "pass_table", table.type_id)
		let parameter = try mir_add_function_param(d, pass.store, pass.id, 0, "table", table.type_id)
		let block = try mir_add_block(d, parameter.store, pass.id, 0, "entry")
		store = (try mir_add_terminator(d, block.store, MirTermRec(function: pass.id, block: block.id, kind: mir_term_return(), value: parameter.id, target: 0, then_block: 0, else_block: 0))).store
		pass_id = pass.id
	}
	let function = try mir_add_function(d, store, "table_identity", mir_type_unit())
	let domain = try mir_add_function_param(d, function.store, function.id, 0, "domain", handle.type_id)
	let source = try mir_add_function_param(d, domain.store, function.id, 1, "table", table.type_id)
	let key = try mir_add_function_param(d, source.store, function.id, 2, "id", id.type_id)
	let item = try mir_add_function_param(d, key.store, function.id, 3, "row", row.type_id)
	let entry = try mir_add_block(d, item.store, function.id, 0, "entry")
	let failed = try mir_add_block(d, entry.store, function.id, 1, "failed")
	store = failed.store
	var ordinal: U64 = 0
	var lookup_table = source.id
	var mutation_table = source.id
	if mode == 1 {
		let fresh = try mir_add_value(d, store, function.id, "fresh", table.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
		store = (try mir_add_instruction(d, fresh.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_create(), result: fresh.id, place: 0, type_op: row.type_id, a: domain.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
		mutation_table = fresh.id
		ordinal = ordinal + 1
	}
	if mode == 2 {
		let alias = try mir_add_value(d, store, function.id, "alias", table.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
		let call = try mir_add_instruction(d, alias.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_call(), result: alias.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: pass_id, name_start: 0, name_end: 0))
		store = (try mir_add_operand(d, call.store, MirOperandRec(kind: mir_operand_instruction(), owner: call.id, ordinal: 0, edge: 0, value: source.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store
		lookup_table = alias.id
		ordinal = ordinal + 1
	}
	let found = try mir_add_value(d, store, function.id, "found", option.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
	let lookup = try mir_add_instruction(d, found.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_lookup(), result: found.id, place: 0, type_op: 0, a: lookup_table, b: key.id, c: 0, target: 0, name_start: 0, name_end: 0))
	ordinal = ordinal + 1
	let value = try mir_add_value(d, lookup.store, function.id, "view", view.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
	let named = try mir_append_name(d, value.store, "some")
	let extract = try mir_add_instruction(d, named.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_enum_payload_checked(), result: value.id, place: 0, type_op: 0, a: found.id, b: 0, c: 0, target: failed.id, name_start: named.start, name_end: named.end))
	ordinal = ordinal + 1
	let inserted = try mir_add_value(d, extract.store, function.id, "inserted", id.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
	let insert = try mir_add_instruction(d, inserted.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_table_insert(), result: inserted.id, place: 0, type_op: 0, a: mutation_table, b: item.id, c: 0, target: 0, name_start: 0, name_end: 0))
	let ended = try mir_add_instruction(d, insert.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal + 1, op: mir_op_table_view_end(), result: 0, place: 0, type_op: 0, a: value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
	let done = try mir_add_terminator(d, ended.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
	return Ok((try mir_add_terminator(d, done.store, MirTermRec(function: function.id, block: failed.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}

// Modes 0/1/2 forward a table directly, through a local load/store, or through
// aggregate construction plus a field load. All then mutate the original while
// the block-parameter alias has an active view.
fn table_alias_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
	let empty = try __s0_buffer_new(U64, d)
	let row = try mir_add_named_type(d, initial, mir_type_kind_aggregate(), "AliasRow")
	let row_field = try mir_add_type_part(d, row.store, mir_type_part_field(), row.type_id, 0, "x", mir_type_u64())
	let table = try mir_intern_type(d, row_field, mir_type_kind_table(), row.type_id, 0, 0, empty, 0)
	let id = try mir_intern_type(d, table.store, mir_type_kind_id(), row.type_id, 0, 0, empty, 0)
	let view = try mir_intern_type(d, id.store, mir_type_kind_table_view(), row.type_id, 0, 0, empty, 0)
	let option = try mir_intern_type(d, view.store, mir_type_kind_option(), view.type_id, 0, 0, empty, 0)
	let holder = try mir_add_named_type(d, option.store, mir_type_kind_aggregate(), "TableHolder")
	let holder_field = try mir_add_type_part(d, holder.store, mir_type_part_field(), holder.type_id, 0, "table", table.type_id)
	let function = try mir_add_function(d, holder_field, "table_alias", mir_type_unit())
	let source = try mir_add_function_param(d, function.store, function.id, 0, "source", table.type_id)
	let key = try mir_add_function_param(d, source.store, function.id, 1, "id", id.type_id)
	let item = try mir_add_function_param(d, key.store, function.id, 2, "row", row.type_id)
	let entry = try mir_add_block(d, item.store, function.id, 0, "entry")
	let active = try mir_add_block(d, entry.store, function.id, 1, "active")
	let alias_param = try mir_add_block_param(d, active.store, function.id, active.id, 0, "alias", table.type_id)
	let failed = try mir_add_block(d, alias_param.store, function.id, 2, "failed")
	var store = failed.store
	var alias = source.id
	var ordinal: U64 = 0
	if mode == 1 {
		let local = try mir_add_local(d, store, function.id, 0, "slot", table.type_id)
		let place = try mir_add_place(d, local.store, MirPlaceRec(function: function.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
		let write = try mir_add_instruction(d, place.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_store(), result: 0, place: place.id, type_op: 0, a: source.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		ordinal = ordinal + 1
		let loaded = try mir_add_value(d, write.store, function.id, "loaded", table.type_id, mir_value_def_instruction(), entry.id, ordinal + 1)
		store = (try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: entry.id, ordinal: ordinal, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
		alias = loaded.id
	}
	if mode == 2 {
		let local = try mir_add_local(d, store, function.id, 0, "holder", holder.type_id)
		let local_place = try mir_add_place(d, local.store, MirPlaceRec(function: function.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
		let aggregate = try mir_add_value(d, local_place.store, function.id, "holder", holder.type_id, mir_value_def_instruction(), entry.id, 1)
		let name = try mir_append_name(d, aggregate.store, "table")
		let construct = try mir_add_instruction(d, name.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_aggregate_construct(), result: aggregate.id, place: 0, type_op: holder.type_id, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		let field_operand = try mir_add_operand(d, construct.store, MirOperandRec(kind: mir_operand_aggregate_field(), owner: construct.id, ordinal: 0, edge: 0, value: source.id, target: 0, operand_type: 0, name_start: name.start, name_end: name.end))
		let write = try mir_add_instruction(d, field_operand.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_store(), result: 0, place: local_place.id, type_op: 0, a: aggregate.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		let field_place = try mir_add_place(d, write.store, MirPlaceRec(function: function.id, kind: mir_place_field(), local: 0, base: local_place.id, field_start: name.start, field_end: name.end, deref_value: 0))
		let loaded = try mir_add_value(d, field_place.store, function.id, "loaded", table.type_id, mir_value_def_instruction(), entry.id, 3)
		store = (try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 2, op: mir_op_load(), result: loaded.id, place: field_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
		alias = loaded.id
	}
	let jump = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_jump(), value: 0, target: active.id, then_block: 0, else_block: 0))
	let edge = try mir_add_operand(d, jump.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: jump.id, ordinal: 0, edge: 0, value: alias, target: active.id, operand_type: 0, name_start: 0, name_end: 0))
	let found = try mir_add_value(d, edge.store, function.id, "found", option.type_id, mir_value_def_instruction(), active.id, 1)
	let lookup = try mir_add_instruction(d, found.store, MirInstrRec(function: function.id, block: active.id, ordinal: 0, op: mir_op_table_lookup(), result: found.id, place: 0, type_op: 0, a: alias_param.id, b: key.id, c: 0, target: 0, name_start: 0, name_end: 0))
	let value = try mir_add_value(d, lookup.store, function.id, "view", view.type_id, mir_value_def_instruction(), active.id, 2)
	let some = try mir_append_name(d, value.store, "some")
	let extract = try mir_add_instruction(d, some.store, MirInstrRec(function: function.id, block: active.id, ordinal: 1, op: mir_op_enum_payload_checked(), result: value.id, place: 0, type_op: 0, a: found.id, b: 0, c: 0, target: failed.id, name_start: some.start, name_end: some.end))
	let inserted = try mir_add_value(d, extract.store, function.id, "inserted", id.type_id, mir_value_def_instruction(), active.id, 3)
	let insert = try mir_add_instruction(d, inserted.store, MirInstrRec(function: function.id, block: active.id, ordinal: 2, op: mir_op_table_insert(), result: inserted.id, place: 0, type_op: 0, a: source.id, b: item.id, c: 0, target: 0, name_start: 0, name_end: 0))
	let ended = try mir_add_instruction(d, insert.store, MirInstrRec(function: function.id, block: active.id, ordinal: 3, op: mir_op_table_view_end(), result: 0, place: 0, type_op: 0, a: value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
	let done = try mir_add_terminator(d, ended.store, MirTermRec(function: function.id, block: active.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
	return Ok((try mir_add_terminator(d, done.store, MirTermRec(function: function.id, block: failed.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}

// mode 0 crosses only unsafe FFI/return boundaries; 1 uses a safe call, 2 a
// store, and 3 an edge. nested wraps raw_ptr in option.
fn raw_v9_fixture(d: Domain, initial: MirStore, mode: U64, nested: Bool) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let raw = try mir_intern_type(d, initial, mir_type_kind_raw_ptr(), mir_type_u8(), 0, 0, empty, 0)
    var value_type = raw.type_id
    var store = raw.store
    if nested { let option = try mir_intern_type(d, store, mir_type_kind_option(), raw.type_id, 0, 0, empty, 0)
        store = option.store
        value_type = option.type_id }
    let imported = try mir_add_import(d, store, "foreign", value_type)
    store = try mir_add_import_param(d, imported.store, imported.id, 0, value_type)
    var callee_id: U64 = 0
    if mode == 1 { let callee = try mir_add_function(d, store, "safe", mir_type_unit())
        let parameter = try mir_add_function_param(d, callee.store, callee.id, 0, "raw", value_type)
        let block = try mir_add_block(d, parameter.store, callee.id, 0, "entry")
        store = (try mir_add_terminator(d, block.store, MirTermRec(function: callee.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store
        callee_id = callee.id }
    let function = try mir_add_function(d, store, "raw_case", value_type)
    let source = try mir_add_function_param(d, function.store, function.id, 0, "source", value_type)
    let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
    let returned = try mir_add_value(d, entry.store, function.id, "returned", value_type, mir_value_def_instruction(), entry.id, 1)
    let ffi = try mir_add_instruction(d, returned.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_ffi_call_unsafe(), result: returned.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: imported.id, name_start: 0, name_end: 0))
    let ffi_arg = try mir_add_operand(d, ffi.store, MirOperandRec(kind: mir_operand_instruction(), owner: ffi.id, ordinal: 0, edge: 0, value: source.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    store = ffi_arg.store
    if mode == 1 { let call = try mir_add_instruction(d, store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_call(), result: 0, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: callee_id, name_start: 0, name_end: 0))
        store = (try mir_add_operand(d, call.store, MirOperandRec(kind: mir_operand_instruction(), owner: call.id, ordinal: 0, edge: 0, value: returned.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store }
    if mode == 2 { let local = try mir_add_local(d, store, function.id, 0, "slot", value_type)
        let place = try mir_add_place(d, local.store, MirPlaceRec(function: function.id, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        store = (try mir_add_instruction(d, place.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 1, op: mir_op_store(), result: 0, place: place.id, type_op: 0, a: returned.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store }
    if mode == 3 { let target = try mir_add_block(d, store, function.id, 1, "target")
        let parameter = try mir_add_block_param(d, target.store, function.id, target.id, 0, "raw", value_type)
        let jump = try mir_add_terminator(d, parameter.store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_jump(), value: 0, target: target.id, then_block: 0, else_block: 0))
        let edge = try mir_add_operand(d, jump.store, MirOperandRec(kind: mir_operand_terminator_arg(), owner: jump.id, ordinal: 0, edge: 0, value: returned.id, target: target.id, operand_type: 0, name_start: 0, name_end: 0))
        return Ok((try mir_add_terminator(d, edge.store, MirTermRec(function: function.id, block: target.id, kind: mir_term_return(), value: parameter.id, target: 0, then_block: 0, else_block: 0))).store) }
    return Ok((try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: returned.id, target: 0, then_block: 0, else_block: 0))).store)
}

// Modes 0/1 isolate aggregate and place uses owned by V9. Modes 2/3 are raw
// arithmetic/conversion shapes whose malformed typing remains owned by V5.
fn raw_inventory_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
	let empty = try __s0_buffer_new(U64, d)
	let raw = try mir_intern_type(d, initial, mir_type_kind_raw_ptr(), mir_type_u8(), 0, 0, empty, 0)
	var result_type = mir_type_unit()
	var store = raw.store
	var box_type: U64 = 0
	if mode == 0 {
		let box = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "RawBox")
		store = try mir_add_type_part(d, box.store, mir_type_part_field(), box.type_id, 0, "pointer", raw.type_id)
		box_type = box.type_id
		result_type = box.type_id
	}
	let function = try mir_add_function(d, store, "raw_inventory", result_type)
	let source = try mir_add_function_param(d, function.store, function.id, 0, "source", raw.type_id)
	let entry = try mir_add_block(d, source.store, function.id, 0, "entry")
	store = entry.store
	var returned: U64 = 0
	if mode == 0 {
		let box = try mir_add_value(d, store, function.id, "box", box_type, mir_value_def_instruction(), entry.id, 1)
		let field = try mir_append_name(d, box.store, "pointer")
		let construct = try mir_add_instruction(d, field.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_aggregate_construct(), result: box.id, place: 0, type_op: box_type, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
		store = (try mir_add_operand(d, construct.store, MirOperandRec(kind: mir_operand_aggregate_field(), owner: construct.id, ordinal: 0, edge: 0, value: source.id, target: 0, operand_type: 0, name_start: field.start, name_end: field.end))).store
		returned = box.id
	}
	if mode == 1 {
		let place = try mir_add_place(d, store, MirPlaceRec(function: function.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: source.id))
		let loaded = try mir_add_value(d, place.store, function.id, "loaded", mir_type_u8(), mir_value_def_instruction(), entry.id, 1)
		store = (try mir_add_instruction(d, loaded.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_load(), result: loaded.id, place: place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
	}
	if mode == 2 {
		let compared = try mir_add_value(d, store, function.id, "compared", mir_type_bool(), mir_value_def_instruction(), entry.id, 1)
		store = (try mir_add_instruction(d, compared.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_int_eq(), result: compared.id, place: 0, type_op: 0, a: source.id, b: source.id, c: 0, target: 0, name_start: 0, name_end: 0))).store
	}
	if mode == 3 {
		let converted = try mir_add_value(d, store, function.id, "converted", mir_type_u8(), mir_value_def_instruction(), entry.id, 1)
		store = (try mir_add_instruction(d, converted.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_int_trunc(), result: converted.id, place: 0, type_op: mir_type_u8(), a: source.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
	}
	return Ok((try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: returned, target: 0, then_block: 0, else_block: 0))).store)
}

fn backend_names_fixture(d: Domain, initial: MirStore, reserved: Bool) -> Result(MirStore, __s0_Error) {
	var store = initial
	if reserved {
		store = (try mir_add_import(d, store, "return", mir_type_unit())).store
		store = (try mir_add_import(d, store, "alder_call", mir_type_unit())).store
		store = (try mir_add_import(d, store, "uint64_t", mir_type_unit())).store
		store = (try mir_add_import(d, store, "FLT_MAX", mir_type_unit())).store
		store = (try mir_add_import(d, store, "memcpy", mir_type_unit())).store
	} else {
		store = (try mir_add_import(d, store, "alderhost_call", mir_type_unit())).store
		store = (try mir_add_import(d, store, "alderx", mir_type_unit())).store
		store = (try mir_add_import(d, store, "Alde", mir_type_unit())).store
		store = (try mir_add_import(d, store, "uint64_t2", mir_type_unit())).store
		store = (try mir_add_import(d, store, "Flt_Max", mir_type_unit())).store
		store = (try mir_add_import(d, store, "memcpy2", mir_type_unit())).store
	}
	return Ok(store)
}

// Modes 0/1/2 cover recursive alloc, alloc.checked, and table element checks;
// mode 3 rejects identity-bearing copy_to_domain input, while mode 4 checks
// deterministic first-kind selection for a mixed domain/table aggregate.
fn backend_element_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
	let empty = try __s0_buffer_new(U64, d)
	let handle = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
	let nested = try mir_intern_type(d, handle.store, mir_type_kind_option(), handle.type_id, 0, 0, empty, 0)
	let box = try mir_add_named_type(d, nested.store, mir_type_kind_aggregate(), "NestedHandle")
	let field = try mir_add_type_part(d, box.store, mir_type_part_field(), box.type_id, 0, "value", nested.type_id)
	let pointer = try mir_intern_type(d, field, mir_type_kind_safe_mut(), box.type_id, 0, 0, empty, 0)
	let table = try mir_intern_type(d, pointer.store, mir_type_kind_table(), box.type_id, 0, 0, empty, 0)
	let mixed = try mir_add_named_type(d, table.store, mir_type_kind_aggregate(), "MixedIdentity")
	let mixed_domain = try mir_add_type_part(d, mixed.store, mir_type_part_field(), mixed.type_id, 0, "domain", handle.type_id)
	let mixed_table = try mir_add_type_part(d, mixed_domain, mir_type_part_field(), mixed.type_id, 1, "table", table.type_id)
	let function = try mir_add_function(d, mixed_table, "backend_element", mir_type_unit())
	let domain = try mir_add_function_param(d, function.store, function.id, 0, "domain", handle.type_id)
	let size = try mir_add_function_param(d, domain.store, function.id, 1, "size", mir_type_u64())
	let entry = try mir_add_block(d, size.store, function.id, 0, "entry")
	let failed = try mir_add_block(d, entry.store, function.id, 1, "failed")
	var store = failed.store
	if mode == 3 {
		let value = try mir_add_value(d, store, function.id, "copy", handle.type_id, mir_value_def_instruction(), entry.id, 1)
		store = (try mir_add_instruction(d, value.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_copy_to_domain(), result: value.id, place: 0, type_op: 0, a: domain.id, b: domain.id, c: 0, target: 0, name_start: 0, name_end: 0))).store
	} else {
		if mode == 4 {
			let source = try mir_add_function_param(d, store, function.id, 2, "mixed", mixed.type_id)
			let value = try mir_add_value(d, source.store, function.id, "copy", mixed.type_id, mir_value_def_instruction(), entry.id, 1)
			store = (try mir_add_instruction(d, value.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_copy_to_domain(), result: value.id, place: 0, type_op: 0, a: domain.id, b: source.id, c: 0, target: 0, name_start: 0, name_end: 0))).store
		} else {
			if mode == 2 {
				let value = try mir_add_value(d, store, function.id, "table", table.type_id, mir_value_def_instruction(), entry.id, 1)
				store = (try mir_add_instruction(d, value.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: mir_op_table_create(), result: value.id, place: 0, type_op: box.type_id, a: domain.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
			} else {
				let value = try mir_add_value(d, store, function.id, "pointer", pointer.type_id, mir_value_def_instruction(), entry.id, 1)
				var op = mir_op_alloc()
				var target: U64 = 0
				if mode == 1 { op = mir_op_alloc_checked()
					target = failed.id }
				store = (try mir_add_instruction(d, value.store, MirInstrRec(function: function.id, block: entry.id, ordinal: 0, op: op, result: value.id, place: 0, type_op: box.type_id, a: domain.id, b: size.id, c: 0, target: target, name_start: 0, name_end: 0))).store
			}
		}
	}
	let done = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
	return Ok((try mir_add_terminator(d, done.store, MirTermRec(function: function.id, block: failed.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store)
}

fn hosted_fixture(d: Domain, initial: MirStore, name: __s0_String, result_type: U64, params: U64) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    var base = handle.store
    var constant_id: U64 = 0
    if result_type == mir_type_i32() { if __s0_buffer_len(MirConstRec, base.constants) == 0 { let constant = try mir_add_const(d, base, "status", mir_type_i32(), mir_const_int(), 0, 0, 0, "")
            base = constant.store
            constant_id = constant.id } else { constant_id = 1 } }
    let function = try mir_add_function(d, base, name, result_type)
    var store = function.store
    if params >= 1 { var param_type = handle.type_id
        if params != 1 { param_type = mir_type_u64() }
        store = (try mir_add_function_param(d, store, function.id, 0, "domain", param_type)).store }
    if params >= 2 { store = (try mir_add_function_param(d, store, function.id, 1, "extra", mir_type_u64())).store }
    let block = try mir_add_block(d, store, function.id, 0, "entry")
    store = block.store
    var returned: U64 = 0
    if result_type == mir_type_i32() { let value = try mir_add_value(d, store, function.id, "status", mir_type_i32(), mir_value_def_instruction(), block.id, 1)
        let named = try mir_append_name(d, value.store, "status")
        let get = try mir_add_instruction(d, named.store, MirInstrRec(function: function.id, block: block.id, ordinal: 0, op: mir_op_const_get(), result: value.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: constant_id, name_start: named.start, name_end: named.end))
        store = get.store
        returned = value.id }
    return Ok((try mir_add_terminator(d, store, MirTermRec(function: function.id, block: block.id, kind: mir_term_return(), value: returned, target: 0, then_block: 0, else_block: 0))).store)
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
    let bad_child_types = try __s0_buffer_append(MirTypeRec, d, bad_child_base.types, MirTypeRec(kind: mir_type_kind_slice(), name_start: 0, name_end: 0, elem: 999, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: 0, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar()))
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

    let duplicate_local_names = try duplicate_local_name_fixture(d, try mir_store_new(d))
    if !expect_verification(94, try mir_verify_module(d, duplicate_local_names, 3), mir_vdiag(1, mir_vdiag_duplicate_name(), 1, 0, 0, 0, 0, 0, 2, 0, 0, 1)) { return Ok(false) }
    let rejected_locals = try mir_verify_complete(d, duplicate_local_names, 3, false)
    if !expect_complete(95, rejected_locals, false, false, 0, 1, mir_vdiag_duplicate_name()) { return Ok(false) }
    if !expect_complete(96, try mir_verify_complete(d, try cross_function_local_names_fixture(d, try mir_store_new(d)), 3, false), true, false, 0, 0, 0) { return Ok(false) }

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
    let bad_store_type = try mir_verify_module(d, try bad_store_type_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(34, bad_store_type, mir_vdiag(5, mir_vdiag_bad_operand_type(), 1, 1, 1, 0, 0, mir_type_bool(), 0, mir_type_u64(), mir_type_bool(), 1)) { return Ok(false) }
    let bad_result_type = try mir_verify_module(d, try bad_result_type_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(35, bad_result_type, mir_vdiag(5, mir_vdiag_bad_result_type(), 1, 1, 2, 0, 0, mir_type_u64(), 0, mir_type_bool(), mir_type_u64(), 2)) { return Ok(false) }
    let bad_call_arity = try mir_verify_module(d, try bad_call_arity_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(36, bad_call_arity, mir_vdiag(5, mir_vdiag_bad_argument_count(), 2, 1, 1, 0, 0, 0, 0, 1, 0, 1)) { return Ok(false) }
    let readonly_store = try mir_verify_module(d, try readonly_store_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(37, readonly_store, mir_vdiag(5, mir_vdiag_readonly_place(), 1, 1, 1, 0, 1, mir_type_u64(), 0, 0, mir_type_u64(), 1)) { return Ok(false) }
    let bad_aggregate = try mir_verify_module(d, try bad_aggregate_fixture(d, try mir_store_new(d)), 3)
    if !expect_verification(38, bad_aggregate, mir_vdiag(5, mir_vdiag_bad_aggregate(), 1, 1, 1, 0, 1, 0, 0, 0, 0, 1)) { return Ok(false) }
    let domain_live = try mir_verify_module(d, try domain_lifetime_fixture(d, try mir_store_new(d), false), 3)
    if !emit_verification(39, domain_live) { return Ok(false) }
    let domain_dead = try mir_verify_module(d, try domain_lifetime_fixture(d, try mir_store_new(d), true), 3)
    if !expect_verification(40, domain_dead, mir_vdiag(6, mir_vdiag_invalid_resource_use(), 1, 1, 4, 0, 0, 0, 0, 0, 0, 4)) { return Ok(false) }
    let cleanup_closed = try mir_verify_module(d, try cleanup_fixture(d, try mir_store_new(d), true), 3)
    if !emit_verification(41, cleanup_closed) { return Ok(false) }
    let cleanup_open = try mir_verify_module(d, try cleanup_fixture(d, try mir_store_new(d), false), 3)
    if !expect_verification(42, cleanup_open, mir_vdiag(7, mir_vdiag_cleanup_exit(), 1, 1, 0, 1, 0, 0, 0, 0, 0, 1)) { return Ok(false) }
    let cleanup_destroy = try mir_verify_module(d, try cleanup_callback_effect_fixture(d, try mir_store_new(d), 1), 3)
    if !expect_verification(43, cleanup_destroy, mir_vdiag(6, mir_vdiag_invalid_resource_use(), 3, 1, 8, 0, 0, 0, 0, 0, 0, 3)) { return Ok(false) }
    let cleanup_reset = try mir_verify_module(d, try cleanup_callback_effect_fixture(d, try mir_store_new(d), 2), 3)
    if !expect_verification(44, cleanup_reset, mir_vdiag(6, mir_vdiag_invalid_resource_use(), 3, 1, 9, 0, 0, 0, 0, 0, 0, 3)) { return Ok(false) }
    let cleanup_argument = try mir_verify_module(d, try cleanup_callback_effect_fixture(d, try mir_store_new(d), 3), 3)
    if !expect_verification(45, cleanup_argument, mir_vdiag(6, mir_vdiag_invalid_resource_use(), 2, 1, 6, 0, 1, 0, 0, 0, 0, 3)) { return Ok(false) }
    let cleanup_join = try mir_verify_module(d, try cleanup_join_fixture(d, try mir_store_new(d), false), 3)
    if !emit_verification(46, cleanup_join) { return Ok(false) }
    let cleanup_join_use = try mir_verify_module(d, try cleanup_join_fixture(d, try mir_store_new(d), true), 3)
    if !expect_verification(47, cleanup_join_use, mir_vdiag(6, mir_vdiag_invalid_resource_use(), 2, 4, 8, 0, 0, 0, 0, 0, 0, 4)) { return Ok(false) }
    let cleanup_lifo = try mir_verify_module(d, try cleanup_lifo_fixture(d, try mir_store_new(d), false), 3)
    if !emit_verification(48, cleanup_lifo) { return Ok(false) }
    let cleanup_bad_lifo = try mir_verify_module(d, try cleanup_lifo_fixture(d, try mir_store_new(d), true), 3)
    if !expect_verification(49, cleanup_bad_lifo, mir_vdiag(6, mir_vdiag_invalid_resource_use(), 2, 1, 6, 0, 1, 0, 0, 0, 0, 2)) { return Ok(false) }

    let table_ok = try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 0), 3)
    if !emit_verification(50, table_ok) { return Ok(false) }
    let table_unconsumed = try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 1), 3)
    if !emit_verification(51, table_unconsumed) { return Ok(false) }
    let table_mutation = try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 2), 3)
    if !emit_verification(52, table_mutation) { return Ok(false) }
    let table_raw_base = try table_v8_fixture(d, try mir_store_new(d), 1)
    let no_table_terms = try __s0_buffer_new(MirTermRec, d)
    let table_fail_fast = try mir_verify_module(d, mir_with_terminators(table_raw_base, no_table_terms), 3)
    if !emit_verification(53, table_fail_fast) { return Ok(false) }

    let raw_ok = try mir_verify_module(d, try raw_v9_fixture(d, try mir_store_new(d), 0, false), 3)
    if !emit_verification(54, raw_ok) { return Ok(false) }
    let raw_safe = try mir_verify_module(d, try raw_v9_fixture(d, try mir_store_new(d), 1, false), 3)
    if !emit_verification(55, raw_safe) { return Ok(false) }
    let raw_store = try mir_verify_module(d, try raw_v9_fixture(d, try mir_store_new(d), 2, false), 3)
    if !emit_verification(56, raw_store) { return Ok(false) }
    let raw_edge = try mir_verify_module(d, try raw_v9_fixture(d, try mir_store_new(d), 3, false), 3)
    if !emit_verification(57, raw_edge) { return Ok(false) }
    let raw_nested = try mir_verify_module(d, try raw_v9_fixture(d, try mir_store_new(d), 2, true), 3)
    if !emit_verification(58, raw_nested) { return Ok(false) }
    let raw_fail_fast = try mir_verify_module(d, phase2_store, 3)
    if !emit_verification(59, raw_fail_fast) { return Ok(false) }

    let unhosted = try mir_verify_complete(d, valid_store, 3, false)
    if !expect_complete(60, unhosted, true, false, 0, 0, 0) { return Ok(false) }
    let hosted_zero_store = try hosted_fixture(d, try mir_store_new(d), "main", mir_type_i32(), 0)
    let hosted_zero = try mir_verify_complete(d, hosted_zero_store, 3, true)
    if !expect_complete(61, hosted_zero, true, true, 1, 0, 0) { return Ok(false) }
    let hosted_domain = try mir_verify_complete(d, try hosted_fixture(d, try mir_store_new(d), "main", mir_type_i32(), 1), 3, true)
    if !expect_complete(62, hosted_domain, true, true, 1, 0, 0) { return Ok(false) }
    let bad_c_import = try mir_add_import(d, try mir_store_new(d), "main", mir_type_unit())
    let bad_c = try mir_verify_complete(d, bad_c_import.store, 3, false)
    if !emit_complete(63, bad_c) { return Ok(false) }
    let empty_v10 = try __s0_buffer_new(U64, d)
    let handle_v10 = try mir_intern_type(d, try mir_store_new(d), mir_type_kind_domain_handle(), 0, 0, 0, empty_v10, 0)
    let safe_handle = try mir_intern_type(d, handle_v10.store, mir_type_kind_safe_mut(), handle_v10.type_id, 0, 0, empty_v10, 0)
    let alloc_fn = try mir_add_function(d, safe_handle.store, "allocate", mir_type_unit())
    let alloc_domain = try mir_add_function_param(d, alloc_fn.store, alloc_fn.id, 0, "domain", handle_v10.type_id)
    let alloc_size = try mir_add_function_param(d, alloc_domain.store, alloc_fn.id, 1, "size", mir_type_u64())
    let alloc_block = try mir_add_block(d, alloc_size.store, alloc_fn.id, 0, "entry")
    let alloc_value = try mir_add_value(d, alloc_block.store, alloc_fn.id, "pointer", safe_handle.type_id, mir_value_def_instruction(), alloc_block.id, 1)
    let forbidden_alloc = try mir_add_instruction(d, alloc_value.store, MirInstrRec(function: alloc_fn.id, block: alloc_block.id, ordinal: 0, op: mir_op_alloc(), result: alloc_value.id, place: 0, type_op: handle_v10.type_id, a: alloc_domain.id, b: alloc_size.id, c: 0, target: 0, name_start: 0, name_end: 0))
    let alloc_done = try mir_add_terminator(d, forbidden_alloc.store, MirTermRec(function: alloc_fn.id, block: alloc_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    let bad_alloc = try mir_verify_complete(d, alloc_done.store, 3, false)
    if !emit_complete(64, bad_alloc) { return Ok(false) }
    let missing = try mir_verify_complete(d, valid_store, 3, true)
    if !expect_complete(65, missing, false, true, 0, 10, mir_vdiag_missing_entry()) { return Ok(false) }
    let duplicate_first = try hosted_fixture(d, try mir_store_new(d), "main", mir_type_i32(), 0)
    let duplicate_store = try hosted_fixture(d, duplicate_first, "main", mir_type_i32(), 0)
    let duplicate_entry = try mir_verify_complete(d, duplicate_store, 3, true)
    if !expect_complete(66, duplicate_entry, false, true, 0, 1, mir_vdiag_duplicate_name()) { return Ok(false) }
    let bad_entry_result = try mir_verify_complete(d, try hosted_fixture(d, try mir_store_new(d), "main", mir_type_unit(), 0), 3, true)
    if !expect_complete(67, bad_entry_result, false, true, 0, 10, mir_vdiag_entry_result()) { return Ok(false) }
    let bad_entry_param = try mir_verify_complete(d, try hosted_fixture(d, try mir_store_new(d), "main", mir_type_i32(), 2), 3, true)
    if !expect_complete(68, bad_entry_param, false, true, 0, 10, mir_vdiag_entry_signature()) { return Ok(false) }
    let complete_fail_fast = try mir_verify_complete(d, phase2_store, 3, true)
    if !expect_complete(69, complete_fail_fast, false, true, 0, 2, mir_vdiag_bad_signature()) { return Ok(false) }
    let table_handle = try mir_intern_type(d, handle_v10.store, mir_type_kind_table(), handle_v10.type_id, 0, 0, empty_v10, 0)
    let table_fn = try mir_add_function(d, table_handle.store, "table", mir_type_unit())
    let table_domain = try mir_add_function_param(d, table_fn.store, table_fn.id, 0, "domain", handle_v10.type_id)
    let table_block = try mir_add_block(d, table_domain.store, table_fn.id, 0, "entry")
    let table_value = try mir_add_value(d, table_block.store, table_fn.id, "table", table_handle.type_id, mir_value_def_instruction(), table_block.id, 1)
    let forbidden_table = try mir_add_instruction(d, table_value.store, MirInstrRec(function: table_fn.id, block: table_block.id, ordinal: 0, op: mir_op_table_create(), result: table_value.id, place: 0, type_op: handle_v10.type_id, a: table_domain.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))
    let table_done = try mir_add_terminator(d, forbidden_table.store, MirTermRec(function: table_fn.id, block: table_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    if !emit_complete(70, try mir_verify_complete(d, table_done.store, 3, false)) { return Ok(false) }
    let reused_unhosted = try mir_verify_complete(d, hosted_zero_store, 3, false)
    if !expect_complete(71, reused_unhosted, true, false, 0, 0, 0) { return Ok(false) }
    let bad_version = try mir_verify_complete(d, hosted_zero_store, 99, true)
    if !expect_complete(72, bad_version, false, true, 0, 1, mir_vdiag_bad_version()) { return Ok(false) }
	if !emit_verification(73, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 3), 3)) { return Ok(false) }
	if !emit_verification(74, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 4), 3)) { return Ok(false) }
	if !emit_verification(75, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 5), 3)) { return Ok(false) }
	if !emit_verification(76, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 6), 3)) { return Ok(false) }
	if !emit_verification(77, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 7), 3)) { return Ok(false) }
	if !emit_verification(78, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 8), 3)) { return Ok(false) }
	if !emit_verification(79, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 9), 3)) { return Ok(false) }
	if !emit_verification(80, try mir_verify_module(d, try raw_inventory_fixture(d, try mir_store_new(d), 0), 3)) { return Ok(false) }
	if !emit_verification(81, try mir_verify_module(d, try raw_inventory_fixture(d, try mir_store_new(d), 1), 3)) { return Ok(false) }
	if !emit_verification(82, try mir_verify_module(d, try raw_inventory_fixture(d, try mir_store_new(d), 2), 3)) { return Ok(false) }
	if !emit_verification(83, try mir_verify_module(d, try raw_inventory_fixture(d, try mir_store_new(d), 3), 3)) { return Ok(false) }
	if !emit_complete(84, try mir_verify_complete(d, try backend_names_fixture(d, try mir_store_new(d), true), 3, false)) { return Ok(false) }
	if !expect_complete(85, try mir_verify_complete(d, try backend_names_fixture(d, try mir_store_new(d), false), 3, false), true, false, 0, 0, 0) { return Ok(false) }
	if !emit_complete(86, try mir_verify_complete(d, try backend_element_fixture(d, try mir_store_new(d), 0), 3, false)) { return Ok(false) }
	if !emit_complete(87, try mir_verify_complete(d, try backend_element_fixture(d, try mir_store_new(d), 1), 3, false)) { return Ok(false) }
	if !emit_complete(88, try mir_verify_complete(d, try backend_element_fixture(d, try mir_store_new(d), 2), 3, false)) { return Ok(false) }
	if !emit_verification(89, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 10), 3)) { return Ok(false) }
	let hosted_later_base = try minimal(d, try mir_store_new(d), mir_type_unit(), false)
	let hosted_later_store = try hosted_fixture(d, hosted_later_base, "main", mir_type_i32(), 0)
	if !expect_complete(90, try mir_verify_complete(d, hosted_later_store, 3, true), true, true, 2, 0, 0) { return Ok(false) }
	let duplicate_values = try duplicate_value_name_fixture(d, try mir_store_new(d))
	if !expect_verification(91, try mir_verify_module(d, duplicate_values, 3), mir_vdiag(1, mir_vdiag_duplicate_name(), 1, 0, 0, 0, 0, 0, 2, 0, 0, 1)) { return Ok(false) }
	let rejected_values = try mir_verify_complete(d, duplicate_values, 3, false)
	if !expect_complete(92, rejected_values, false, false, 0, 1, mir_vdiag_duplicate_name()) { return Ok(false) }
	if !emit_complete(97, try mir_verify_complete(d, try backend_element_fixture(d, try mir_store_new(d), 3), 3, false)) { return Ok(false) }
	if !emit_complete(98, try mir_verify_complete(d, try backend_element_fixture(d, try mir_store_new(d), 4), 3, false)) { return Ok(false) }
	// Mirror the production fail-shut MIR authorization. Any accidental MIR or C
	// bytes from these rejection checks make the exact process output fail.
	if rejected_values.complete { if mir_print(d, duplicate_values) { return Ok(false) } }
	if try cgen_generate(d, duplicate_values, 3, false) { return Ok(false) }
	if !expect_complete(93, try mir_verify_complete(d, try cross_function_value_names_fixture(d, try mir_store_new(d)), 3, false), true, false, 0, 0, 0) { return Ok(false) }
	if !emit_complete(100, try mir_verify_complete(d, try fn_value_ops_fixture(d, try mir_store_new(d), 0), 5, false)) { return Ok(false) }
	if !emit_complete(101, try mir_verify_complete(d, try fn_value_ops_fixture(d, try mir_store_new(d), 1), 5, false)) { return Ok(false) }
	if !emit_complete(102, try mir_verify_complete(d, try fn_value_ops_fixture(d, try mir_store_new(d), 2), 5, false)) { return Ok(false) }
	if !emit_complete(103, try mir_verify_complete(d, try fn_value_ops_fixture(d, try mir_store_new(d), 3), 5, false)) { return Ok(false) }
	if !emit_complete(104, try mir_verify_complete(d, try fn_value_ops_fixture(d, try mir_store_new(d), 4), 5, false)) { return Ok(false) }
    if !emit_complete(105, try mir_verify_complete(d, try fn_value_domain_fixture(d, try mir_store_new(d), 0), 5, false)) { return Ok(false) }
    if !emit_complete(106, try mir_verify_complete(d, try fn_value_domain_fixture(d, try mir_store_new(d), 1), 5, false)) { return Ok(false) }
    if !emit_complete(107, try mir_verify_complete(d, try fn_value_domain_fixture(d, try mir_store_new(d), 2), 5, false)) { return Ok(false) }
    if !emit_complete(108, try mir_verify_complete(d, try fn_value_domain_fixture(d, try mir_store_new(d), 3), 5, false)) { return Ok(false) }
    if !emit_verification(109, try mir_verify_module(d, try closure_env_escape_fixture(d, try mir_store_new(d), false, false), 5)) { return Ok(false) }
    if !emit_complete(110, try mir_verify_complete(d, try closure_env_escape_fixture(d, try mir_store_new(d), true, false), 5, false)) { return Ok(false) }
    if !emit_complete(111, try mir_verify_complete(d, try closure_env_escape_fixture(d, try mir_store_new(d), true, true), 5, false)) { return Ok(false) }
    // Phase-6 refusal: the scratch probe fails, and the fallback re-run must
    // report the exact same diagnostic record byte for byte.
    if !emit_complete(113, try mir_verify_complete(d, try closure_env_escape_fixture(d, try mir_store_new(d), false, false), 5, false)) { return Ok(false) }
    // Mode 11 introduces table.insert.try, which the format-version gate
    // only accepts at version 4 or later, so this case verifies at the
    // current format version instead of the harness's usual 3.
    if !emit_verification(112, try mir_verify_module(d, try table_v8_fixture(d, try mir_store_new(d), 11), 5)) { return Ok(false) }

    if !emit_verification(200, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 0), 6)) { return Ok(false) }
    if !emit_verification(201, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 1), 6)) { return Ok(false) }
    if !emit_verification(202, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 2), 6)) { return Ok(false) }
    if !emit_verification(203, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 3), 6)) { return Ok(false) }
    if !emit_verification(204, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 4), 6)) { return Ok(false) }
    if !emit_verification(205, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 5), 6)) { return Ok(false) }
    if !emit_verification(206, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 6), 6)) { return Ok(false) }
    if !emit_verification(207, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 7), 6)) { return Ok(false) }
    if !emit_verification(208, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 8), 6)) { return Ok(false) }
    if !emit_verification(209, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 9), 6)) { return Ok(false) }
    if !emit_verification(210, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 10), 6)) { return Ok(false) }
    if !emit_verification(211, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 11), 6)) { return Ok(false) }
    if !emit_verification(212, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 12), 6)) { return Ok(false) }
    if !emit_verification(213, try mir_verify_module(d, try frame_fixture(d, try mir_store_new(d), 13), 6)) { return Ok(false) }
    if !emit_verification(214, try mir_verify_module(d, try frame_cursor_fixture(d, try mir_store_new(d), 0), 6)) { return Ok(false) }
    if !emit_verification(215, try mir_verify_module(d, try frame_cursor_fixture(d, try mir_store_new(d), 1), 6)) { return Ok(false) }
    if !emit_verification(216, try mir_verify_module(d, try frame_cursor_fixture(d, try mir_store_new(d), 2), 6)) { return Ok(false) }
    return Ok(true)
}


// frame_fixture builds a minimal park-type step module for the frame
// acceptance rules. Modes mutate one declaration or instruction so each rule
// has a focused acceptance or rejection case.
//   0 valid park step
//   1 two-parameter step signature
//   2 status enum without park
//   3 state enum without resume0
//   4 frame fields state/out/p0
//   5 orphan frame and state
//   6 local of safe_mut(frame)
//   7 call return from the park point
//   8 done without storing out
//   9 cancelled after storing out
//  10 dispatch block missing the state switch
//  11 step frame passed as a call operand
//  12 borrow of a frame field place
//  13 duplicate resume0 suspend block
fn frame_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    var store = handle.store
    let status = try mir_add_named_type(d, store, mir_type_kind_enum(), "__alder_step.status")
    store = try mir_add_type_part(d, status.store, mir_type_part_variant(), status.type_id, 0, "done", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), status.type_id, 1, "call", mir_type_unit())
    if mode != 2 { store = try mir_add_type_part(d, store, mir_type_part_variant(), status.type_id, 2, "park", mir_type_unit()) }
    var next_status: U64 = 2
    if mode != 2 { next_status = 3 }
    store = try mir_add_type_part(d, store, mir_type_part_variant(), status.type_id, next_status, "cancelled", mir_type_unit())
    let state = try mir_add_named_type(d, store, mir_type_kind_enum(), "__alder_step.state.x.Evented")
    store = try mir_add_type_part(d, state.store, mir_type_part_variant(), state.type_id, 0, "entry", mir_type_unit())
    if mode != 3 { store = try mir_add_type_part(d, store, mir_type_part_variant(), state.type_id, 1, "resume0", mir_type_unit()) }
    if mode == 3 { store = try mir_add_type_part(d, store, mir_type_part_variant(), state.type_id, 1, "resume1", mir_type_unit()) }
    let frame = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "__alder_step.frame.x.Evented")
    store = frame.store
    if mode == 4 {
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 0, "state", state.type_id)
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 1, "out", mir_type_u64())
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 2, "p0", mir_type_u64())
    } else {
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 0, "state", state.type_id)
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 1, "p0", mir_type_u64())
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 2, "out", mir_type_u64())
    }
    let frame_view = try mir_intern_type(d, store, mir_type_kind_safe_mut(), frame.type_id, 0, 0, empty, 0)
    store = frame_view.store
    if mode == 5 {
        let orphan_state = try mir_add_named_type(d, store, mir_type_kind_enum(), "__alder_step.state.orphan.Evented")
        store = try mir_add_type_part(d, orphan_state.store, mir_type_part_variant(), orphan_state.type_id, 0, "entry", mir_type_unit())
        let orphan = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "__alder_step.frame.orphan.Evented")
        store = try mir_add_type_part(d, orphan.store, mir_type_part_field(), orphan.type_id, 0, "state", orphan_state.type_id)
        store = try mir_add_type_part(d, store, mir_type_part_field(), orphan.type_id, 1, "p0", mir_type_u64())
        store = try mir_add_type_part(d, store, mir_type_part_field(), orphan.type_id, 2, "out", mir_type_u64())
    }
    let false_const = try mir_add_const(d, store, "false", mir_type_bool(), mir_const_bool(), 0, 0, 0, "")
    store = false_const.store
    let false_rec = __s0_buffer_get(MirConstRec, store.constants, false_const.id - 1)
    let runtime_binding = try mir_add_binding(d, store, "runtime", "alder.h")
    store = runtime_binding.store
    let cancel_binding = try mir_add_binding_fn(d, store, runtime_binding.id, "task_cancelled", "alder_task_cancelled", mir_type_bool())
    store = cancel_binding.store
    let cancel = try mir_add_function(d, store, "task_cancelled", mir_type_bool())
    store = cancel.store
    let cancel_entry = try mir_add_block(d, store, cancel.id, 0, "entry")
    let cancel_value = try mir_add_value(d, cancel_entry.store, cancel.id, "f", mir_type_bool(), mir_value_def_instruction(), cancel_entry.id, 1)
    let cancel_get = try mir_add_instruction(d, cancel_value.store, MirInstrRec(function: cancel.id, block: cancel_entry.id, ordinal: 0, op: mir_op_const_get(), result: cancel_value.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: false_rec.name_start, name_end: false_rec.name_end))
    store = (try mir_add_terminator(d, cancel_get.store, MirTermRec(function: cancel.id, block: cancel_entry.id, kind: mir_term_return(), value: cancel_value.id, target: 0, then_block: 0, else_block: 0))).store
    let step = try mir_add_function(d, store, "__alder_step.run.x.Evented", status.type_id)
    store = step.store
    let pd = try mir_add_function_param(d, store, step.id, 0, "d", handle.type_id)
    let pf = try mir_add_function_param(d, pd.store, step.id, 1, "frame", frame_view.type_id)
    store = pf.store
    var owner_value: U64 = 0
    if mode != 1 { let po = try mir_add_function_param(d, store, step.id, 2, "frame_owner", handle.type_id)
        store = po.store
        owner_value = po.id }
    if mode == 6 { store = (try mir_add_local(d, store, step.id, 0, "held", frame_view.type_id)).store }
    let bb0 = try mir_add_block(d, store, step.id, 0, "bb0")
    let bb_entry = try mir_add_block(d, bb0.store, step.id, 1, "bb_entry")
    let bb_park = try mir_add_block(d, bb_entry.store, step.id, 2, "bb_park")
    let bb_resume = try mir_add_block(d, bb_park.store, step.id, 3, "bb_resume0")
    let bb_after = try mir_add_block(d, bb_resume.store, step.id, 4, "bb_after")
    let bb_cancel0 = try mir_add_block(d, bb_after.store, step.id, 5, "bb_cancel0")
    let bb_cancel1 = try mir_add_block(d, bb_cancel0.store, step.id, 6, "bb_cancel1")
    store = bb_cancel1.store
    let state_name = try mir_append_name(d, store, "state")
    store = state_name.store
    let frame_deref = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: pf.id))
    store = frame_deref.store
    let state_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: state_name.start, field_end: state_name.end, deref_value: 0))
    store = state_place.store
    let p0_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: 0, field_end: 0, deref_value: 0))
    store = p0_place.store
    let out_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: 0, field_end: 0, deref_value: 0))
    store = out_place.store
    // Resolve field name ranges by appending the canonical names once more:
    // type-part names are compared by range, so the place records need the
    // same bytes. mir_add_type_part appended them already; repeat the names
    // and patch the place field ranges below.
    let p0_name = try mir_append_name(d, store, "p0")
    store = p0_name.store
    let out_name = try mir_append_name(d, store, "out")
    store = out_name.store
    // The appended ranges are at the end of the name buffer; patch the two
    // places and the state place field range via their existing records.
    var places = store.places
    let p0_rec = __s0_buffer_get(MirPlaceRec, places, p0_place.id - 1)
    __s0_buffer_set(MirPlaceRec, places, p0_place.id - 1, MirPlaceRec(function: p0_rec.function, kind: p0_rec.kind, local: p0_rec.local, base: p0_rec.base, field_start: p0_name.start, field_end: p0_name.end, deref_value: 0))
    let out_rec = __s0_buffer_get(MirPlaceRec, places, out_place.id - 1)
    __s0_buffer_set(MirPlaceRec, places, out_place.id - 1, MirPlaceRec(function: out_rec.function, kind: out_rec.kind, local: out_rec.local, base: out_rec.base, field_start: out_name.start, field_end: out_name.end, deref_value: 0))
    store = mir_with_places(store, places)
    var state_load_id: U64 = 0
    if mode != 10 { let state_load = try mir_add_value(d, store, step.id, "state_value", state.type_id, mir_value_def_instruction(), bb0.id, 1)
        store = state_load.store
        state_load_id = state_load.id }
    var ord: U64 = 0
    var resume_name = try mir_append_name(d, store, "resume0")
    if mode == 3 { resume_name = try mir_append_name(d, store, "resume1") }
    store = resume_name.store
    if mode != 10 {
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb0.id, ordinal: 0, op: mir_op_load(), result: state_load_id, place: state_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        let dispatch = try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb0.id, kind: mir_term_switch(), value: state_load_id, target: 0, then_block: 0, else_block: 0))
        store = dispatch.store
        let entry_name = try mir_append_name(d, store, "entry")
        store = entry_name.store
        store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 0, edge: 0, value: 0, target: bb_entry.id, operand_type: 0, name_start: entry_name.start, name_end: entry_name.end))).store
        if mode != 3 { store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 1, edge: 0, value: 0, target: bb_resume.id, operand_type: 0, name_start: resume_name.start, name_end: resume_name.end))).store }
    } else {
        store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb0.id, kind: mir_term_jump(), value: 0, target: bb_entry.id, then_block: 0, else_block: 0))).store
    }
    // bb_entry: cancellation check then park.
    let cancelled = try mir_add_value(d, store, step.id, "cancelled", mir_type_bool(), mir_value_def_instruction(), bb_entry.id, 1)
    store = cancelled.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_entry.id, ordinal: 0, op: mir_op_c_binding_call(), result: cancelled.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: cancel_binding.id, name_start: 0, name_end: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_entry.id, kind: mir_term_branch(), value: cancelled.id, target: 0, then_block: bb_cancel0.id, else_block: bb_park.id))).store
    // bb_park: save resume0 and return park (or call in mode 7).
    let resume_state = try mir_add_value(d, store, step.id, "resume", state.type_id, mir_value_def_instruction(), bb_park.id, 1)
    store = resume_state.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_park.id, ordinal: 0, op: mir_op_enum_construct(), result: resume_state.id, place: 0, type_op: state.type_id, a: 0, b: 0, c: 0, target: 0, name_start: resume_name.start, name_end: resume_name.end))).store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_park.id, ordinal: 1, op: mir_op_store(), result: 0, place: state_place.id, type_op: 0, a: resume_state.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let park_status = try mir_add_value(d, store, step.id, "park_status", status.type_id, mir_value_def_instruction(), bb_park.id, 3)
    store = park_status.store
    let park_name = try mir_append_name(d, store, "park")
    store = park_name.store
    let call_name = try mir_append_name(d, store, "call")
    store = call_name.store
    var park_variant = park_name
    if mode == 7 { park_variant = call_name }
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_park.id, ordinal: 2, op: mir_op_enum_construct(), result: park_status.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: park_variant.start, name_end: park_variant.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_park.id, kind: mir_term_return(), value: park_status.id, target: 0, then_block: 0, else_block: 0))).store
    // bb_resume0: cancellation check then done.
    let cancelled0 = try mir_add_value(d, store, step.id, "cancelled0", mir_type_bool(), mir_value_def_instruction(), bb_resume.id, 1)
    store = cancelled0.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_resume.id, ordinal: 0, op: mir_op_c_binding_call(), result: cancelled0.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: cancel_binding.id, name_start: 0, name_end: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_resume.id, kind: mir_term_branch(), value: cancelled0.id, target: 0, then_block: bb_cancel1.id, else_block: bb_after.id))).store
    // bb_after: load p0 and store out.
    let p0_value = try mir_add_value(d, store, step.id, "p0_value", mir_type_u64(), mir_value_def_instruction(), bb_after.id, 1)
    store = p0_value.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: 0, op: mir_op_load(), result: p0_value.id, place: p0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    var after_ord: U64 = 1
    if mode != 8 { store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_store(), result: 0, place: out_place.id, type_op: 0, a: p0_value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        after_ord = after_ord + 1 }
    if mode == 11 { let call_value = try mir_add_value(d, store, step.id, "leak", mir_type_bool(), mir_value_def_instruction(), bb_after.id, after_ord + 1)
        store = call_value.store
        let bad_call = try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_c_binding_call(), result: call_value.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: cancel_binding.id, name_start: 0, name_end: 0))
        store = bad_call.store
        store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_instruction(), owner: bad_call.id, ordinal: 0, edge: 0, value: pf.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store
        after_ord = after_ord + 1 }
    if mode == 12 { let view_type = try mir_intern_type(d, store, mir_type_kind_safe_mut(), mir_type_u64(), 0, 0, empty, 0)
        store = view_type.store
        let borrowed = try mir_add_value(d, store, step.id, "borrowed", view_type.type_id, mir_value_def_instruction(), bb_after.id, after_ord + 1)
        store = borrowed.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_borrow_mut(), result: borrowed.id, place: p0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        after_ord = after_ord + 1 }
    let done_status = try mir_add_value(d, store, step.id, "done_status", status.type_id, mir_value_def_instruction(), bb_after.id, after_ord + 1)
    store = done_status.store
    let done_name = try mir_append_name(d, store, "done")
    store = done_name.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_enum_construct(), result: done_status.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: done_name.start, name_end: done_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_after.id, kind: mir_term_return(), value: done_status.id, target: 0, then_block: 0, else_block: 0))).store
    // Cancellation blocks.
    if mode == 9 { let cp0 = try mir_add_value(d, store, step.id, "cp0", mir_type_u64(), mir_value_def_instruction(), bb_cancel0.id, 1)
        store = cp0.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_cancel0.id, ordinal: 0, op: mir_op_load(), result: cp0.id, place: p0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_cancel0.id, ordinal: 1, op: mir_op_store(), result: 0, place: out_place.id, type_op: 0, a: cp0.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store }
    var cancel0_ordinal: U64 = 0
    if mode == 9 { cancel0_ordinal = 2 }
    let st0 = try mir_add_value(d, store, step.id, "st0", status.type_id, mir_value_def_instruction(), bb_cancel0.id, cancel0_ordinal + 1)
    store = st0.store
    let cancel_name = try mir_append_name(d, store, "cancelled")
    store = cancel_name.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_cancel0.id, ordinal: cancel0_ordinal, op: mir_op_enum_construct(), result: st0.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: cancel_name.start, name_end: cancel_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_cancel0.id, kind: mir_term_return(), value: st0.id, target: 0, then_block: 0, else_block: 0))).store
    let st1 = try mir_add_value(d, store, step.id, "st1", status.type_id, mir_value_def_instruction(), bb_cancel1.id, 1)
    store = st1.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_cancel1.id, ordinal: 0, op: mir_op_enum_construct(), result: st1.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: cancel_name.start, name_end: cancel_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_cancel1.id, kind: mir_term_return(), value: st1.id, target: 0, then_block: 0, else_block: 0))).store
    if mode == 13 { let alt = try mir_add_block(d, store, step.id, 7, "bb_alt_suspend")
        store = alt.store
        let alt_resume = try mir_add_value(d, store, step.id, "alt_resume", state.type_id, mir_value_def_instruction(), alt.id, 1)
        store = alt_resume.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: alt.id, ordinal: 0, op: mir_op_enum_construct(), result: alt_resume.id, place: 0, type_op: state.type_id, a: 0, b: 0, c: 0, target: 0, name_start: resume_name.start, name_end: resume_name.end))).store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: alt.id, ordinal: 1, op: mir_op_store(), result: 0, place: state_place.id, type_op: 0, a: alt_resume.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        let alt_park = try mir_add_value(d, store, step.id, "alt_park", status.type_id, mir_value_def_instruction(), alt.id, 3)
        store = alt_park.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: alt.id, ordinal: 2, op: mir_op_enum_construct(), result: alt_park.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: park_name.start, name_end: park_name.end))).store
        store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: alt.id, kind: mir_term_return(), value: alt_park.id, target: 0, then_block: 0, else_block: 0))).store }
    return Ok(store)
}



// frame_cursor_fixture builds a suspending cleanup cursor whose frame-resident
// scope is anchored in s0. Mode 0 parks, mode 1 hands off a call with x0/y0,
// and mode 2 re-enters the scope through unsaved s1.
fn frame_cursor_fixture(d: Domain, initial: MirStore, mode: U64) -> Result(MirStore, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let handle = try mir_intern_type(d, initial, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    var store = handle.store
    let cleanup_id_type = try mir_intern_type(d, store, mir_type_kind_cleanup_id(), 0, 0, 0, empty, 0)
    store = cleanup_id_type.store
    let cleanup_scope_type = try mir_intern_type(d, store, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
    store = cleanup_scope_type.store
    let status = try mir_add_named_type(d, store, mir_type_kind_enum(), "__alder_step.status")
    store = try mir_add_type_part(d, status.store, mir_type_part_variant(), status.type_id, 0, "done", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), status.type_id, 1, "call", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), status.type_id, 2, "park", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), status.type_id, 3, "cancelled", mir_type_unit())
    let state = try mir_add_named_type(d, store, mir_type_kind_enum(), "__alder_step.state.cursor.Evented")
    store = try mir_add_type_part(d, state.store, mir_type_part_variant(), state.type_id, 0, "entry", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), state.type_id, 1, "cleanup0", mir_type_unit())
    let leaf_state = try mir_add_named_type(d, store, mir_type_kind_enum(), "__alder_step.state.leaf.Evented")
    store = try mir_add_type_part(d, leaf_state.store, mir_type_part_variant(), leaf_state.type_id, 0, "entry", mir_type_unit())
    let leaf_frame = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "__alder_step.frame.leaf.Evented")
    store = try mir_add_type_part(d, leaf_frame.store, mir_type_part_field(), leaf_frame.type_id, 0, "state", leaf_state.type_id)
    store = try mir_add_type_part(d, store, mir_type_part_field(), leaf_frame.type_id, 1, "p0", mir_type_u64())
    store = try mir_add_type_part(d, store, mir_type_part_field(), leaf_frame.type_id, 2, "out", mir_type_u64())
    let leaf_view = try mir_intern_type(d, store, mir_type_kind_safe_mut(), leaf_frame.type_id, 0, 0, empty, 0)
    store = leaf_view.store
    let frame = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "__alder_step.frame.cursor.Evented")
    store = frame.store
    store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 0, "state", state.type_id)
    store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, 1, "p0", mir_type_u64())
    var ordinal: U64 = 2
    if mode == 1 {
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, ordinal, "x0", leaf_view.type_id)
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, ordinal + 1, "y0", handle.type_id)
        ordinal = ordinal + 2
    }
    store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, ordinal, "c0", cleanup_id_type.type_id)
    store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, ordinal + 1, "s0", cleanup_scope_type.type_id)
    ordinal = ordinal + 2
    if mode == 2 {
        store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, ordinal, "s1", cleanup_scope_type.type_id)
        ordinal = ordinal + 1
    }
    store = try mir_add_type_part(d, store, mir_type_part_field(), frame.type_id, ordinal, "out", mir_type_u64())
    let frame_view = try mir_intern_type(d, store, mir_type_kind_safe_mut(), frame.type_id, 0, 0, empty, 0)
    store = frame_view.store
    let runtime_binding = try mir_add_binding(d, store, "runtime", "alder.h")
    store = runtime_binding.store
    let cancel_binding = try mir_add_binding_fn(d, store, runtime_binding.id, "task_cancelled", "alder_task_cancelled", mir_type_bool())
    store = cancel_binding.store
    let one_const = try mir_add_const(d, store, "one", mir_type_u64(), mir_const_int(), 0, 1, 0, "")
    store = one_const.store
    let one_rec = __s0_buffer_get(MirConstRec, store.constants, one_const.id - 1)
    let leaf_step = try mir_add_function(d, store, "__alder_step.run.leaf.Evented", status.type_id)
    store = leaf_step.store
    let lpd = try mir_add_function_param(d, store, leaf_step.id, 0, "d", handle.type_id)
    let lpf = try mir_add_function_param(d, lpd.store, leaf_step.id, 1, "frame", leaf_view.type_id)
    let lpo = try mir_add_function_param(d, lpf.store, leaf_step.id, 2, "frame_owner", handle.type_id)
    store = lpo.store
    let lbb0 = try mir_add_block(d, store, leaf_step.id, 0, "bb0")
    let lbb_entry = try mir_add_block(d, lbb0.store, leaf_step.id, 1, "bb_entry")
    let lbb_done = try mir_add_block(d, lbb_entry.store, leaf_step.id, 2, "bb_done")
    let lbb_cancel = try mir_add_block(d, lbb_done.store, leaf_step.id, 3, "bb_cancel")
    store = lbb_cancel.store
    let leaf_state_name = try mir_append_name(d, store, "state")
    store = leaf_state_name.store
    let leaf_p0_name = try mir_append_name(d, store, "p0")
    store = leaf_p0_name.store
    let leaf_out_name = try mir_append_name(d, store, "out")
    store = leaf_out_name.store
    let leaf_entry_name = try mir_append_name(d, store, "entry")
    store = leaf_entry_name.store
    let leaf_deref = try mir_add_place(d, store, MirPlaceRec(function: leaf_step.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: lpf.id))
    store = leaf_deref.store
    let leaf_state_place = try mir_add_place(d, store, MirPlaceRec(function: leaf_step.id, kind: mir_place_field(), local: 0, base: leaf_deref.id, field_start: leaf_state_name.start, field_end: leaf_state_name.end, deref_value: 0))
    store = leaf_state_place.store
    let leaf_p0_place = try mir_add_place(d, store, MirPlaceRec(function: leaf_step.id, kind: mir_place_field(), local: 0, base: leaf_deref.id, field_start: leaf_p0_name.start, field_end: leaf_p0_name.end, deref_value: 0))
    store = leaf_p0_place.store
    let leaf_out_place = try mir_add_place(d, store, MirPlaceRec(function: leaf_step.id, kind: mir_place_field(), local: 0, base: leaf_deref.id, field_start: leaf_out_name.start, field_end: leaf_out_name.end, deref_value: 0))
    store = leaf_out_place.store
    let leaf_state_value = try mir_add_value(d, store, leaf_step.id, "state_value", leaf_state.type_id, mir_value_def_instruction(), lbb0.id, 1)
    store = leaf_state_value.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: leaf_step.id, block: lbb0.id, ordinal: 0, op: mir_op_load(), result: leaf_state_value.id, place: leaf_state_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let leaf_dispatch = try mir_add_terminator(d, store, MirTermRec(function: leaf_step.id, block: lbb0.id, kind: mir_term_switch(), value: leaf_state_value.id, target: 0, then_block: 0, else_block: 0))
    store = leaf_dispatch.store
    store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: leaf_dispatch.id, ordinal: 0, edge: 0, value: 0, target: lbb_entry.id, operand_type: 0, name_start: leaf_entry_name.start, name_end: leaf_entry_name.end))).store
    let leaf_cancelled = try mir_add_value(d, store, leaf_step.id, "cancelled", mir_type_bool(), mir_value_def_instruction(), lbb_entry.id, 1)
    store = leaf_cancelled.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: leaf_step.id, block: lbb_entry.id, ordinal: 0, op: mir_op_c_binding_call(), result: leaf_cancelled.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: cancel_binding.id, name_start: 0, name_end: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: leaf_step.id, block: lbb_entry.id, kind: mir_term_branch(), value: leaf_cancelled.id, target: 0, then_block: lbb_cancel.id, else_block: lbb_done.id))).store
    let leaf_p0 = try mir_add_value(d, store, leaf_step.id, "p0_value", mir_type_u64(), mir_value_def_instruction(), lbb_done.id, 1)
    store = leaf_p0.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: leaf_step.id, block: lbb_done.id, ordinal: 0, op: mir_op_load(), result: leaf_p0.id, place: leaf_p0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: leaf_step.id, block: lbb_done.id, ordinal: 1, op: mir_op_store(), result: 0, place: leaf_out_place.id, type_op: 0, a: leaf_p0.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let leaf_done = try mir_add_value(d, store, leaf_step.id, "done", status.type_id, mir_value_def_instruction(), lbb_done.id, 3)
    store = leaf_done.store
    let leaf_done_name = try mir_append_name(d, store, "done")
    store = leaf_done_name.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: leaf_step.id, block: lbb_done.id, ordinal: 2, op: mir_op_enum_construct(), result: leaf_done.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: leaf_done_name.start, name_end: leaf_done_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: leaf_step.id, block: lbb_done.id, kind: mir_term_return(), value: leaf_done.id, target: 0, then_block: 0, else_block: 0))).store
    let leaf_cancel_name = try mir_append_name(d, store, "cancelled")
    store = leaf_cancel_name.store
    let leaf_st = try mir_add_value(d, store, leaf_step.id, "st", status.type_id, mir_value_def_instruction(), lbb_cancel.id, 1)
    store = leaf_st.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: leaf_step.id, block: lbb_cancel.id, ordinal: 0, op: mir_op_enum_construct(), result: leaf_st.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: leaf_cancel_name.start, name_end: leaf_cancel_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: leaf_step.id, block: lbb_cancel.id, kind: mir_term_return(), value: leaf_st.id, target: 0, then_block: 0, else_block: 0))).store
    let hook = try mir_add_function(d, store, "hook", mir_type_unit())
    store = hook.store
    let hook_param = try mir_add_function_param(d, store, hook.id, 0, "owner", mir_type_u64())
    store = hook_param.store
    let hook_block = try mir_add_block(d, store, hook.id, 0, "bb0")
    store = (try mir_add_terminator(d, hook_block.store, MirTermRec(function: hook.id, block: hook_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))).store
    let step = try mir_add_function(d, store, "__alder_step.run.cursor.Evented", status.type_id)
    store = step.store
    let pd = try mir_add_function_param(d, store, step.id, 0, "d", handle.type_id)
    let pf = try mir_add_function_param(d, pd.store, step.id, 1, "frame", frame_view.type_id)
    let po = try mir_add_function_param(d, pf.store, step.id, 2, "frame_owner", handle.type_id)
    store = po.store
    let bb0 = try mir_add_block(d, store, step.id, 0, "bb0")
    let bb_entry = try mir_add_block(d, bb0.store, step.id, 1, "bb_entry")
    let bb_setup = try mir_add_block(d, bb_entry.store, step.id, 2, "bb_setup")
    let bb_resume = try mir_add_block(d, bb_setup.store, step.id, 3, "bb_resume")
    let bb_after = try mir_add_block(d, bb_resume.store, step.id, 4, "bb_after")
    let bb_cancel0 = try mir_add_block(d, bb_after.store, step.id, 5, "bb_cancel0")
    let bb_cancel1 = try mir_add_block(d, bb_cancel0.store, step.id, 6, "bb_cancel1")
    store = bb_cancel1.store
    let state_name = try mir_append_name(d, store, "state")
    store = state_name.store
    let p0_name = try mir_append_name(d, store, "p0")
    store = p0_name.store
    let x0_name = try mir_append_name(d, store, "x0")
    store = x0_name.store
    let y0_name = try mir_append_name(d, store, "y0")
    store = y0_name.store
    let c0_name = try mir_append_name(d, store, "c0")
    store = c0_name.store
    let s0_name = try mir_append_name(d, store, "s0")
    store = s0_name.store
    let s1_name = try mir_append_name(d, store, "s1")
    store = s1_name.store
    let out_name = try mir_append_name(d, store, "out")
    store = out_name.store
    let frame_deref = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: pf.id))
    store = frame_deref.store
    let state_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: state_name.start, field_end: state_name.end, deref_value: 0))
    store = state_place.store
    let p0_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: p0_name.start, field_end: p0_name.end, deref_value: 0))
    store = p0_place.store
    let x0_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: x0_name.start, field_end: x0_name.end, deref_value: 0))
    store = x0_place.store
    let y0_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: y0_name.start, field_end: y0_name.end, deref_value: 0))
    store = y0_place.store
    let c0_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: c0_name.start, field_end: c0_name.end, deref_value: 0))
    store = c0_place.store
    let s0_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: s0_name.start, field_end: s0_name.end, deref_value: 0))
    store = s0_place.store
    let s1_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: s1_name.start, field_end: s1_name.end, deref_value: 0))
    store = s1_place.store
    let out_place = try mir_add_place(d, store, MirPlaceRec(function: step.id, kind: mir_place_field(), local: 0, base: frame_deref.id, field_start: out_name.start, field_end: out_name.end, deref_value: 0))
    store = out_place.store
    let entry_name = try mir_append_name(d, store, "entry")
    store = entry_name.store
    let cleanup_name = try mir_append_name(d, store, "cleanup0")
    store = cleanup_name.store
    let state_value = try mir_add_value(d, store, step.id, "state_value", state.type_id, mir_value_def_instruction(), bb0.id, 1)
    store = state_value.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb0.id, ordinal: 0, op: mir_op_load(), result: state_value.id, place: state_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    let dispatch = try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb0.id, kind: mir_term_switch(), value: state_value.id, target: 0, then_block: 0, else_block: 0))
    store = dispatch.store
    store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 0, edge: 0, value: 0, target: bb_entry.id, operand_type: 0, name_start: entry_name.start, name_end: entry_name.end))).store
    store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_switch_case(), owner: dispatch.id, ordinal: 1, edge: 0, value: 0, target: bb_resume.id, operand_type: 0, name_start: cleanup_name.start, name_end: cleanup_name.end))).store
    // Entry cancellation check.
    let cancelled = try mir_add_value(d, store, step.id, "cancelled", mir_type_bool(), mir_value_def_instruction(), bb_entry.id, 1)
    store = cancelled.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_entry.id, ordinal: 0, op: mir_op_c_binding_call(), result: cancelled.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: cancel_binding.id, name_start: 0, name_end: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_entry.id, kind: mir_term_branch(), value: cancelled.id, target: 0, then_block: bb_cancel0.id, else_block: bb_setup.id))).store
    // Setup: save state, optional callee pair, anchor the scope, register, suspend.
    let p0 = try mir_add_value(d, store, step.id, "p0_value", mir_type_u64(), mir_value_def_instruction(), bb_setup.id, 1)
    store = p0.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: 0, op: mir_op_load(), result: p0.id, place: p0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    var setup_ord: U64 = 1
    var child_value: U64 = 0
    var child_domain_value: U64 = 0
    if mode == 1 {
        let one = try mir_add_value(d, store, step.id, "one", mir_type_u64(), mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
        store = one.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_const_get(), result: one.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: one_rec.name_start, name_end: one_rec.name_end))).store
        setup_ord = setup_ord + 1
        let child_domain = try mir_add_value(d, store, step.id, "child_domain", handle.type_id, mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
        store = child_domain.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_domain_create(), result: child_domain.id, place: 0, type_op: 0, a: po.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        setup_ord = setup_ord + 1
        let child = try mir_add_value(d, store, step.id, "child", leaf_view.type_id, mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
        store = child.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_alloc(), result: child.id, place: 0, type_op: leaf_frame.type_id, a: child_domain.id, b: one.id, c: 0, target: 0, name_start: 0, name_end: 0))).store
        setup_ord = setup_ord + 1
        child_value = child.id
        child_domain_value = child_domain.id
    }
    let cleanup_state = try mir_add_value(d, store, step.id, "cleanup_state", state.type_id, mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
    store = cleanup_state.store
    let cleanup_variant = try mir_append_name(d, store, "cleanup0")
    store = cleanup_variant.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_enum_construct(), result: cleanup_state.id, place: 0, type_op: state.type_id, a: 0, b: 0, c: 0, target: 0, name_start: cleanup_variant.start, name_end: cleanup_variant.end))).store
    setup_ord = setup_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_store(), result: 0, place: state_place.id, type_op: 0, a: cleanup_state.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    setup_ord = setup_ord + 1
    if mode == 1 {
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_store(), result: 0, place: x0_place.id, type_op: 0, a: child_value, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        setup_ord = setup_ord + 1
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_store(), result: 0, place: y0_place.id, type_op: 0, a: child_domain_value, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        setup_ord = setup_ord + 1
    }
    let scope = try mir_add_value(d, store, step.id, "scope", cleanup_scope_type.type_id, mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
    store = scope.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_cleanup_scope_begin(), result: scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    setup_ord = setup_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_store(), result: 0, place: s0_place.id, type_op: 0, a: scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    setup_ord = setup_ord + 1
    let cleanup_id = try mir_add_value(d, store, step.id, "cleanup_id", cleanup_id_type.type_id, mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
    store = cleanup_id.store
    let push = try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_cleanup_push(), result: cleanup_id.id, place: p0_place.id, type_op: 0, a: scope.id, b: 0, c: 0, target: hook.id, name_start: 0, name_end: 0))
    store = push.store
    store = (try mir_add_operand(d, store, MirOperandRec(kind: mir_operand_instruction(), owner: push.id, ordinal: 0, edge: 0, value: p0.id, target: 0, operand_type: 0, name_start: 0, name_end: 0))).store
    setup_ord = setup_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_store(), result: 0, place: c0_place.id, type_op: 0, a: cleanup_id.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    setup_ord = setup_ord + 1
    let suspend = try mir_add_value(d, store, step.id, "suspend", status.type_id, mir_value_def_instruction(), bb_setup.id, setup_ord + 1)
    store = suspend.store
    var suspend_name = try mir_append_name(d, store, "park")
    store = suspend_name.store
    if mode == 1 { suspend_name = try mir_append_name(d, store, "call")
        store = suspend_name.store }
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_setup.id, ordinal: setup_ord, op: mir_op_enum_construct(), result: suspend.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: suspend_name.start, name_end: suspend_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_setup.id, kind: mir_term_return(), value: suspend.id, target: 0, then_block: 0, else_block: 0))).store
    // Resume: cancellation check then reload the saved cursor state.
    let cancelled0 = try mir_add_value(d, store, step.id, "cancelled0", mir_type_bool(), mir_value_def_instruction(), bb_resume.id, 1)
    store = cancelled0.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_resume.id, ordinal: 0, op: mir_op_c_binding_call(), result: cancelled0.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: cancel_binding.id, name_start: 0, name_end: 0))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_resume.id, kind: mir_term_branch(), value: cancelled0.id, target: 0, then_block: bb_cancel1.id, else_block: bb_after.id))).store
    var after_ord: U64 = 0
    var x0_value: U64 = 0
    var y0_value: U64 = 0
    if mode == 1 {
        let xv = try mir_add_value(d, store, step.id, "x0_value", leaf_view.type_id, mir_value_def_instruction(), bb_after.id, 1)
        store = xv.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: 0, op: mir_op_load(), result: xv.id, place: x0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        after_ord = 1
        let yv = try mir_add_value(d, store, step.id, "y0_value", handle.type_id, mir_value_def_instruction(), bb_after.id, 2)
        store = yv.store
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: 1, op: mir_op_load(), result: yv.id, place: y0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        after_ord = 2
        x0_value = xv.id
        y0_value = yv.id
    }
    let c0_value = try mir_add_value(d, store, step.id, "c0_value", cleanup_id_type.type_id, mir_value_def_instruction(), bb_after.id, after_ord + 1)
    store = c0_value.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_load(), result: c0_value.id, place: c0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    let s0_value = try mir_add_value(d, store, step.id, "s0_value", cleanup_scope_type.type_id, mir_value_def_instruction(), bb_after.id, after_ord + 1)
    store = s0_value.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_load(), result: s0_value.id, place: s0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    let resume_scope = try mir_add_value(d, store, step.id, "resume_scope", cleanup_scope_type.type_id, mir_value_def_instruction(), bb_after.id, after_ord + 1)
    store = resume_scope.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_cleanup_scope_begin(), result: resume_scope.id, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    var anchor_place = s0_place.id
    if mode == 2 { anchor_place = s1_place.id }
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_store(), result: 0, place: anchor_place, type_op: 0, a: resume_scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_cleanup_disarm(), result: 0, place: 0, type_op: 0, a: c0_value.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_cleanup_scope_run(), result: 0, place: 0, type_op: 0, a: resume_scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_cleanup_scope_end(), result: 0, place: 0, type_op: 0, a: resume_scope.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    if mode == 1 {
        store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_domain_destroy(), result: 0, place: 0, type_op: 0, a: y0_value, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
        after_ord = after_ord + 1
    }
    let p0_after = try mir_add_value(d, store, step.id, "p0_after", mir_type_u64(), mir_value_def_instruction(), bb_after.id, after_ord + 1)
    store = p0_after.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_load(), result: p0_after.id, place: p0_place.id, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_store(), result: 0, place: out_place.id, type_op: 0, a: p0_after.id, b: 0, c: 0, target: 0, name_start: 0, name_end: 0))).store
    after_ord = after_ord + 1
    let done = try mir_add_value(d, store, step.id, "done", status.type_id, mir_value_def_instruction(), bb_after.id, after_ord + 1)
    store = done.store
    let done_name = try mir_append_name(d, store, "done")
    store = done_name.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_after.id, ordinal: after_ord, op: mir_op_enum_construct(), result: done.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: done_name.start, name_end: done_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_after.id, kind: mir_term_return(), value: done.id, target: 0, then_block: 0, else_block: 0))).store
    let cancel_name = try mir_append_name(d, store, "cancelled")
    store = cancel_name.store
    let st0 = try mir_add_value(d, store, step.id, "st0", status.type_id, mir_value_def_instruction(), bb_cancel0.id, 1)
    store = st0.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_cancel0.id, ordinal: 0, op: mir_op_enum_construct(), result: st0.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: cancel_name.start, name_end: cancel_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_cancel0.id, kind: mir_term_return(), value: st0.id, target: 0, then_block: 0, else_block: 0))).store
    let st1 = try mir_add_value(d, store, step.id, "st1", status.type_id, mir_value_def_instruction(), bb_cancel1.id, 1)
    store = st1.store
    store = (try mir_add_instruction(d, store, MirInstrRec(function: step.id, block: bb_cancel1.id, ordinal: 0, op: mir_op_enum_construct(), result: st1.id, place: 0, type_op: status.type_id, a: 0, b: 0, c: 0, target: 0, name_start: cancel_name.start, name_end: cancel_name.end))).store
    store = (try mir_add_terminator(d, store, MirTermRec(function: step.id, block: bb_cancel1.id, kind: mir_term_return(), value: st1.id, target: 0, then_block: 0, else_block: 0))).store
    return Ok(store)
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
	want := "V 0 0\nV 1 1\nD 1 2 0 0 0 0 0 0 0 12 0 0\nV 2 1\nD 2 21 1 0 0 0 0 999 1 0 0 999\nV 3 1\nD 3 25 1 1 0 0 0 0 0 0 1 0\nV 4 1\nD 1 1 0 0 0 0 0 0 0 1 99 7\nE 5 1 9\nE 6 1 14\nE 7 2 16\nE 8 2 17\nE 9 2 20\nE 10 2 22\nE 11 2 23\nE 12 3 36\nV 13 0\nV 14 0\nV 15 0\nE 16 1 12\nE 17 3 28\nE 18 3 27\nE 19 3 32\nE 20 3 30\nE 21 3 35\nE 22 3 31\nE 23 3 34\nE 24 1 7\nE 25 1 6\nE 26 2 21\nE 27 2 18\nE 28 3 26\nE 29 1 11\nE 30 4 37\nE 31 4 38\nV 32 0\nE 33 4 37\nE 34 5 40\nE 35 5 41\nE 36 5 44\nE 37 5 43\nE 38 5 45\nV 39 0\nE 40 6 49\nV 41 0\nE 42 7 57\nE 43 6 49\nE 44 6 49\nE 45 6 49\nV 46 0\nE 47 6 49\nV 48 0\nE 49 6 49\nV 50 0\nV 51 1\nD 8 58 1 1 0 0 0 0 0 0 0 4\nV 52 1\nD 8 66 1 1 3 0 0 0 0 0 0 5\nV 53 2\nD 1 9 1 1 0 0 0 0 1 1 0 0\nD 1 9 1 2 0 0 0 0 2 1 0 0\nV 54 0\nV 55 1\nD 9 67 2 1 2 0 3 13 0 0 0 2\nV 56 1\nD 9 67 1 1 2 0 0 13 0 0 0 2\nV 57 1\nD 9 67 1 1 0 1 3 13 0 0 0 2\nV 58 1\nD 9 67 1 1 2 0 0 14 0 0 0 2\nV 59 1\nD 2 21 1 0 0 0 0 999 1 0 0 999\nC 60 0 1 0 0\nC 61 0 1 1 1\nC 62 0 1 1 1\nC 63 1 0 0 0\nD 10 68 0 0 0 0 0 0 1 0 0 1\nC 64 1 0 0 0\nD 10 69 1 1 1 0 0 13 0 0 10 13\nC 65 1 0 1 0\nD 10 70 0 0 0 0 0 0 0 1 0 0\nC 66 1 0 1 0\nD 1 5 2 0 0 0 0 0 2 0 0 1\nC 67 1 0 1 1\nD 10 72 1 0 0 0 0 1 1 5 1 1\nC 68 1 0 1 1\nD 10 73 1 0 0 0 0 0 1 1 2 1\nC 69 1 0 1 0\nD 2 21 1 0 0 0 0 999 1 0 0 999\nC 70 1 0 0 0\nD 10 69 1 1 1 0 0 13 0 0 10 13\n"
	want = strings.ReplaceAll(want, "C 67 1 0 1 1\n", "C 67 1 0 1 0\n")
	want = strings.ReplaceAll(want, "C 68 1 0 1 1\n", "C 68 1 0 1 0\n")
	want = strings.Replace(want, "E 24 1 7\nE 25 1 6\n", "V 24 2\nD 1 7 1 0 0 0 0 0 2 1 0 0\nD 1 5 1 0 0 0 0 0 2 0 0 1\nE 94 1 5\nC 95 1 0 0 0\nD 1 5 1 0 0 0 0 0 2 0 0 1\nC 96 0 1 0 0\nE 25 1 6\n", 1)
	want += "C 71 0 1 0 0\nC 72 1 0 1 0\nD 1 1 0 0 0 0 0 0 0 1 99 7\nV 73 1\nD 8 58 1 1 0 0 0 0 0 0 0 4\nV 74 1\nD 8 63 1 1 0 0 0 0 0 0 0 5\nV 75 1\nD 8 63 1 1 4 0 0 0 0 0 0 5\nV 76 1\nD 8 64 1 1 4 0 0 0 0 0 0 5\nV 77 1\nD 8 60 1 1 2 0 0 0 0 0 0 4\nV 78 1\nD 8 59 1 1 2 0 0 0 0 0 0 5\nV 79 1\nD 8 65 1 1 3 0 0 0 0 0 0 6\nV 80 1\nD 9 67 1 1 1 0 1 13 0 0 0 1\nV 81 1\nD 5 42 1 1 1 0 1 0 0 0 0 1\nV 82 1\nD 5 40 1 1 1 0 0 13 0 13 13 1\nV 83 1\nD 5 47 1 1 1 0 0 13 0 7 13 1\nC 84 5 0 0 0\nD 10 68 0 0 0 0 0 0 1 0 0 1\nD 10 68 0 0 0 0 0 0 2 0 0 2\nD 10 68 0 0 0 0 0 0 3 0 0 3\nD 10 68 0 0 0 0 0 0 4 0 0 4\nD 10 68 0 0 0 0 0 0 5 0 0 5\nC 85 0 1 0 0\nC 86 1 0 0 0\nD 10 69 1 1 1 0 0 15 0 0 10 15\nC 87 1 0 0 0\nD 10 69 1 1 1 0 0 15 0 0 10 15\nC 88 1 0 0 0\nD 10 69 1 1 1 0 0 15 0 0 10 15\n"
	want += "V 89 2\nD 8 64 1 1 4 0 0 0 0 0 0 5\nD 8 64 1 1 5 0 0 0 0 0 0 5\nC 90 0 1 1 2\n"
	want += "E 91 1 5\nC 92 1 0 0 0\nD 1 5 1 0 0 0 0 0 2 0 0 1\nC 97 1 0 0 0\nD 10 74 1 1 1 0 0 13 0 0 10 13\nC 98 1 0 0 0\nD 10 74 1 1 1 0 0 18 0 0 10 18\nC 93 0 1 0 0\nC 100 0 1 0 0\nC 101 1 0 0 0\nD 5 41 2 1 1 0 0 15 0 0 15 2\nC 102 1 0 0 0\nD 5 41 2 1 2 0 0 10 0 0 10 3\nC 103 1 0 0 0\nD 5 41 2 1 5 0 0 2 0 0 2 6\nC 104 1 0 0 0\nD 5 41 2 1 5 0 0 2 0 0 2 6\nC 105 0 1 0 0\nC 106 1 0 0 0\nD 5 41 2 1 1 0 0 14 0 0 14 2\nC 107 1 0 0 0\nD 1 11 2 1 1 0 0 0 1 2147483647 0 0\nC 108 1 0 0 0\nD 1 11 2 1 2 0 0 0 2 2147483647 0 0\nV 109 2\nD 6 52 2 1 0 2 0 0 0 0 0 8\nD 6 53 2 1 0 2 0 0 0 0 0 8\nC 110 0 1 0 0\nC 111 0 1 0 0\nC 113 2 0 0 0\nD 6 52 2 1 0 2 0 0 0 0 0 8\nD 6 53 2 1 0 2 0 0 0 0 0 8\n"
	want += "V 112 1\nD 8 66 1 1 3 0 0 0 0 0 0 5\n"
	want += "V 200 0\nV 201 5\nD 2 21 2 0 0 0 0 0 2 0 0 2\nD 2 76 2 0 0 0 0 0 2 0 0 0\nD 2 80 0 0 0 0 0 16 16 0 0 0\nD 2 77 0 0 0 0 0 14 14 0 0 0\nD 2 89 2 0 0 0 0 17 2 0 0 0\nV 202 1\nD 2 77 0 0 0 0 0 14 14 0 0 0\nV 203 1\nD 2 78 0 0 0 0 0 15 15 0 0 0\nV 204 1\nD 2 79 0 0 0 0 0 16 16 0 0 0\nV 205 1\nD 2 80 0 0 0 0 0 19 19 0 0 0\nV 206 1\nD 2 89 2 0 0 0 0 17 1 0 0 0\nV 207 1\nD 6 94 2 3 0 4 0 0 2 0 0 1\nV 208 1\nD 6 96 2 5 0 6 0 0 2 0 0 0\nV 209 1\nD 6 97 2 6 0 7 0 0 2 0 0 0\nV 210 1\nD 6 90 2 1 0 0 0 0 2 0 0 0\nV 211 2\nD 5 44 2 5 10 0 0 1 0 0 1 1\nD 5 86 2 5 10 0 0 0 0 0 0 0\nV 212 1\nD 5 87 2 5 10 0 3 0 8 0 0 0\nV 213 1\nD 6 91 2 8 14 0 0 0 2 0 0 2\nV 214 0\nV 215 0\nV 216 1\nD 7 102 3 4 0 0 0 0 3 0 0 2\n"

	var baseline string
	for i := 0; i < 3; i++ {
		dir := t.TempDir()
		const sentinel = "!alder-core-verifier"
		if err := os.WriteFile(filepath.Join(dir, sentinel), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		cmd := conformanceCommand(exe, sentinel)
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
