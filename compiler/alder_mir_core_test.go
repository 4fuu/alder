package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

const mirCoreWrapper = `
import c alderhost_stdout_byte: fn(U8) -> Bool

fn mout(byte: U8) -> Bool { return unsafe c { alderhost_stdout_byte(byte) } }
fn mout_digit(value: U64) -> Bool {
    if value == 0 { return mout(48) }
    if value == 1 { return mout(49) }
    if value == 2 { return mout(50) }
    if value == 3 { return mout(51) }
    if value == 4 { return mout(52) }
    if value == 5 { return mout(53) }
    if value == 6 { return mout(54) }
    if value == 7 { return mout(55) }
    if value == 8 { return mout(56) }
    return mout(57)
}
fn mout_u64(value: U64) -> Bool {
    if value >= 10 { if !mout_u64(value / 10) { return false } }
    return mout_digit(value % 10)
}
fn mfield(value: U64) -> Bool { return mout(32) && mout_u64(value) }

fn build_representative(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    var store = initial
    let empty = try __s0_buffer_new(U64, d)
    let slice = try mir_intern_type(d, store, mir_type_kind_slice(), mir_type_u8(), 0, 0, empty, 0)
    store = slice.store
    let same_slice = try mir_intern_type(d, store, mir_type_kind_slice(), mir_type_u8(), 0, 0, empty, 0)
    store = same_slice.store
    let result = try mir_intern_type(d, store, mir_type_kind_result(), 0, mir_type_u64(), mir_type_bool(), empty, 0)
    store = result.store
    var signature = try __s0_buffer_append(U64, d, empty, mir_type_u64())
    signature = try __s0_buffer_append(U64, d, signature, mir_type_u8())
    let function_type = try mir_intern_type(d, store, mir_type_kind_function(), 0, 0, 0, signature, mir_type_bool())
    store = function_type.store
    let pair = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "Pair")
    store = try mir_add_type_part(d, pair.store, mir_type_part_field(), pair.type_id, 0, "value", mir_type_u64())
    let imported = try mir_add_import(d, store, "foreign", mir_type_u64())
    store = try mir_add_import_param(d, imported.store, imported.id, 0, mir_type_u64())
    let constant = try mir_add_const(d, store, "seven", mir_type_u64(), mir_const_int(), 0, 7, 0, "")
    store = constant.store
    let sum = try mir_add_function(d, store, "sum", mir_type_u64())
    store = sum.store
    let x = try mir_add_function_param(d, store, sum.id, 0, "x", mir_type_u64())
    store = x.store
    let slot = try mir_add_local(d, store, sum.id, 0, "slot", mir_type_u64())
    store = slot.store
    let entry = try mir_add_block(d, store, sum.id, 0, "entry")
    store = entry.store
    let y = try mir_add_block_param(d, store, sum.id, entry.id, 0, "y", mir_type_u64())
    store = y.store
    let place = try mir_add_place(d, store, MirPlaceRec(function: sum.id, kind: mir_place_local(), local: slot.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    store = place.store
    let added = try mir_add_value(d, store, sum.id, "added", mir_type_u64(), mir_value_def_instruction(), entry.id, 1)
    store = added.store
    let instruction = MirInstrRec(function: sum.id, block: entry.id, ordinal: 0, op: mir_op_int_add_checked(), result: added.id, place: 0, type_op: 0, a: x.id, b: y.id, c: 0, target: 0, name_start: 0, name_end: 0)
    let instruction_step = try mir_add_instruction(d, store, instruction)
    store = instruction_step.store
    let term = try mir_add_terminator(d, store, MirTermRec(function: sum.id, block: entry.id, kind: mir_term_return(), value: added.id, target: 0, then_block: 0, else_block: 0))
    store = term.store
    let helper = try mir_add_function(d, store, "helper", mir_type_unit())
    return Ok(helper.store)
}

fn emit_contract_range(first: U64, end: U64) -> Bool {
    var at = first
    while at < end {
        if !mfield(at) { return false }
        at = at + 1
    }
    return mout(10)
}

fn emit_contract() -> Bool {
    if !mout(75) || !mfield(mir_format_version()) || !mout(10) { return false }
    if !mout(84) || !mout(75) || !emit_contract_range(mir_type_kind_primitive(), mir_type_kind_vec() + 1) { return false }
    if !mout(80) || !mout(82) || !emit_contract_range(mir_type_unit(), mir_type_f64() + 1) { return false }
    if !mout(80) || !mout(84) || !emit_contract_range(mir_type_part_field(), mir_type_part_function_param() + 1) { return false }
    if !mout(67) || !mout(75) || !emit_contract_range(mir_const_unit(), mir_const_string() + 1) { return false }
    if !mout(80) || !mout(75) || !emit_contract_range(mir_param_function(), mir_param_block() + 1) { return false }
    if !mout(86) || !mout(68) || !emit_contract_range(mir_value_def_function_param(), mir_value_def_switch_case() + 1) { return false }
    if !mout(80) || !mout(76) || !emit_contract_range(mir_place_local(), mir_place_deref() + 1) { return false }
    if !mout(79) || !mout(80) || !emit_contract_range(mir_op_load(), mir_op_array_as_slice() + 1) { return false }
    if !mout(84) || !mout(77) || !emit_contract_range(mir_term_jump(), mir_term_panic() + 1) { return false }
    return mout(79) && mout(75) && emit_contract_range(mir_operand_type_part(), mir_operand_aggregate_field() + 1)
}

fn emit_operand_record(id: U64, rec: MirOperandRec) -> Bool {
    return mout(79) && mfield(id) && mfield(rec.kind) && mfield(rec.owner) && mfield(rec.ordinal) && mfield(rec.edge) && mfield(rec.value) && mfield(rec.target) && mfield(rec.operand_type) && mout(10)
}

fn emit_valid_flattened_records(store: MirStore) -> Bool {
    let type_id = __s0_buffer_len(MirTypeRec, store.types)
    let instruction_id = __s0_buffer_len(MirInstrRec, store.instructions)
    let term_id = __s0_buffer_len(MirTermRec, store.terminators)
    let case_id = __s0_buffer_len(MirOperandRec, store.operands) + 5
    let type_part = MirOperandRec(kind: mir_operand_type_part(), owner: type_id, ordinal: 0, edge: 0, value: 0, target: 0, operand_type: mir_type_u64(), name_start: 0, name_end: 0)
    let instruction = MirOperandRec(kind: mir_operand_instruction(), owner: instruction_id, ordinal: 0, edge: 0, value: 1, target: 0, operand_type: 0, name_start: 0, name_end: 0)
    let failure = MirOperandRec(kind: mir_operand_checked_edge_arg(), owner: instruction_id, ordinal: 0, edge: 0, value: 1, target: 1, operand_type: 0, name_start: 0, name_end: 0)
    let term = MirOperandRec(kind: mir_operand_terminator_arg(), owner: term_id, ordinal: 0, edge: mir_edge_jump(), value: 1, target: 1, operand_type: 0, name_start: 0, name_end: 0)
    let switch_case = MirOperandRec(kind: mir_operand_switch_case(), owner: term_id, ordinal: 0, edge: 0, value: 0, target: 1, operand_type: 0, name_start: 0, name_end: 0)
    let case_arg = MirOperandRec(kind: mir_operand_switch_case_arg(), owner: case_id, ordinal: 0, edge: 0, value: 1, target: 1, operand_type: 0, name_start: 0, name_end: 0)
    let field = MirOperandRec(kind: mir_operand_aggregate_field(), owner: instruction_id, ordinal: 0, edge: 0, value: 1, target: 0, operand_type: 0, name_start: 0, name_end: 0)
    if !emit_operand_record(2, type_part) || !emit_operand_record(3, instruction) || !emit_operand_record(4, failure) || !emit_operand_record(5, term) { return false }
    return emit_operand_record(6, switch_case) && emit_operand_record(7, case_arg) && emit_operand_record(8, field)
}

// These are direct raw-record fixtures, not builder failures. Their malformed
// identities and ordinals must survive unchanged for later verifier tests.
fn emit_malformed_records() -> Bool {
    let duplicate_a = MirLocalRec(function: 1, ordinal: 0, name_start: 0, name_end: 0, local_type: mir_type_u64())
    let duplicate_b = MirLocalRec(function: 1, ordinal: 0, name_start: 0, name_end: 0, local_type: mir_type_u64())
    let gap = MirLocalRec(function: 1, ordinal: 2, name_start: 0, name_end: 0, local_type: mir_type_u64())
    let orphan_value = MirValueRec(function: 1, ordinal: 0, name_start: 0, name_end: 0, value_type: mir_type_u64(), def_kind: mir_value_def_instruction(), block: 1, item: 9)
    let wrong_instruction = MirInstrRec(function: 2, block: 1, ordinal: 0, op: mir_op_load(), result: 1, place: 0, type_op: 0, a: 0, b: 0, c: 0, target: 0, name_start: 0, name_end: 0)
    let duplicate_edge_a = MirOperandRec(kind: mir_operand_terminator_arg(), owner: 1, ordinal: 0, edge: mir_edge_then(), value: 1, target: 2, operand_type: 0, name_start: 0, name_end: 0)
    let duplicate_edge_b = MirOperandRec(kind: mir_operand_terminator_arg(), owner: 1, ordinal: 0, edge: mir_edge_then(), value: 2, target: 2, operand_type: 0, name_start: 0, name_end: 0)
    let wrong_owner = MirOperandRec(kind: mir_operand_switch_case_arg(), owner: 999, ordinal: 0, edge: 0, value: 1, target: 2, operand_type: 0, name_start: 0, name_end: 0)
    let bad_boundary = MirTypeRec(kind: mir_type_kind_function(), name_start: 0, name_end: 0, elem: 0, ok_type: 0, err_type: 0, first_part: 999, part_count: 2, result_type: mir_type_unit(), length: 0)
    if !mout(88) || !mfield(1) || !mfield(duplicate_a.function) || !mfield(duplicate_a.ordinal) || !mout(10) { return false }
    if !mout(88) || !mfield(1) || !mfield(duplicate_b.function) || !mfield(duplicate_b.ordinal) || !mout(10) { return false }
    if !mout(88) || !mfield(1) || !mfield(gap.function) || !mfield(gap.ordinal) || !mout(10) { return false }
    if !mout(88) || !mfield(2) || !mfield(orphan_value.function) || !mfield(orphan_value.block) || !mfield(orphan_value.item) || !mout(10) { return false }
    if !mout(88) || !mfield(3) || !mfield(wrong_instruction.function) || !mfield(wrong_instruction.block) || !mfield(wrong_instruction.result) || !mout(10) { return false }
    if !mout(88) || !mfield(4) || !mfield(duplicate_edge_a.kind) || !mfield(duplicate_edge_a.owner) || !mfield(duplicate_edge_a.ordinal) || !mfield(duplicate_edge_a.edge) || !mout(10) { return false }
    if !mout(88) || !mfield(4) || !mfield(duplicate_edge_b.kind) || !mfield(duplicate_edge_b.owner) || !mfield(duplicate_edge_b.ordinal) || !mfield(duplicate_edge_b.edge) || !mout(10) { return false }
    if !mout(88) || !mfield(4) || !mfield(wrong_owner.kind) || !mfield(wrong_owner.owner) || !mfield(wrong_owner.ordinal) || !mfield(wrong_owner.edge) || !mout(10) { return false }
    return mout(88) && mfield(5) && mfield(bad_boundary.kind) && mfield(bad_boundary.first_part) && mfield(bad_boundary.part_count) && mout(10)
}

fn emit_representative(store: MirStore) -> Bool {
    if !mout(65) || !mout(76) || !mout(68) || !mout(69) || !mout(82) || !mout(45) || !mout(77) || !mout(73) || !mout(82) || !mout(45) || !mout(67) || !mout(79) || !mout(78) || !mout(84) || !mout(82) || !mout(65) || !mout(67) || !mout(84) || !mout(32) || !mout(52) || !mout(10) || !emit_contract() { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let rec = __s0_buffer_get(MirTypeRec, store.types, at)
        if !mout(84) || !mfield(at + 1) || !mfield(rec.kind) || !mfield(rec.elem) || !mfield(rec.ok_type) || !mfield(rec.err_type) || !mfield(rec.part_count) || !mfield(rec.result_type) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if !mout(82) || !mfield(at + 1) || !mfield(rec.owner) || !mfield(rec.kind) || !mfield(rec.ordinal) || !mfield(rec.part_type) || !mout(10) { return false }
        at = at + 1
    }
    if !mout(68) || !mfield(__s0_buffer_len(MirImportRec, store.imports)) || !mfield(__s0_buffer_len(MirConstRec, store.constants)) || !mfield(__s0_buffer_len(MirFunctionRec, store.functions)) || !mfield(__s0_buffer_len(MirParamRec, store.params)) || !mfield(__s0_buffer_len(MirLocalRec, store.locals)) || !mfield(__s0_buffer_len(MirBlockRec, store.blocks)) || !mfield(__s0_buffer_len(MirValueRec, store.values)) || !mfield(__s0_buffer_len(MirPlaceRec, store.places)) || !mfield(__s0_buffer_len(MirInstrRec, store.instructions)) || !mfield(__s0_buffer_len(MirTermRec, store.terminators)) || !mfield(__s0_buffer_len(MirOperandRec, store.operands)) || !mout(10) { return false }
    at = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, at)
        if !mout(70) || !mfield(at + 1) || !mfield(rec.result_type) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let rec = __s0_buffer_get(MirParamRec, store.params, at)
        if !mout(81) || !mfield(rec.kind) || !mfield(rec.function) || !mfield(rec.block) || !mfield(rec.ordinal) || !mfield(rec.value) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, at)
        if !mout(76) || !mfield(rec.function) || !mfield(rec.ordinal) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, at)
        if !mout(66) || !mfield(rec.function) || !mfield(rec.ordinal + 1) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let rec = __s0_buffer_get(MirValueRec, store.values, at)
        if !mout(86) || !mfield(rec.function) || !mfield(rec.ordinal + 1) || !mfield(rec.def_kind) || !mfield(rec.block) || !mfield(rec.item) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirPlaceRec, store.places) {
        let rec = __s0_buffer_get(MirPlaceRec, store.places, at)
        if !mout(80) || !mfield(at + 1) || !mfield(rec.function) || !mfield(rec.kind) || !mfield(rec.local) || !mfield(rec.base) || !mfield(rec.deref_value) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if !mout(73) || !mfield(at + 1) || !mfield(rec.function) || !mfield(rec.block) || !mfield(rec.ordinal) || !mfield(rec.op) || !mfield(rec.result) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirTermRec, store.terminators) {
        let rec = __s0_buffer_get(MirTermRec, store.terminators, at)
        if !mout(90) || !mfield(at + 1) || !mfield(rec.function) || !mfield(rec.block) || !mfield(rec.kind) || !mfield(rec.value) || !mfield(rec.target) || !mout(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
        if !mout(79) || !mfield(at + 1) || !mfield(rec.kind) || !mfield(rec.owner) || !mfield(rec.ordinal) || !mfield(rec.edge) || !mfield(rec.value) || !mfield(rec.target) || !mfield(rec.operand_type) || !mout(10) { return false }
        at = at + 1
    }
    if !emit_valid_flattened_records(store) { return false }
    if !emit_malformed_records() { return false }
    return mout(69) && mout(78) && mout(68) && mout(10)
}

fn built(d: Domain, store: MirStore) -> I32 {
    if emit_representative(store) { return 0 }
    return 4
}
fn main(d: Domain) -> I32 { return match mir_store_new(d) {
    Err(error) => 3
    Ok(store) => match build_representative(d, store) {
        Err(error) => 3
        Ok(done) => built(d, done)
    }
} }
`

func TestAlderMIRCoreConformance(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}

	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	read := func(name string, id frontend.SourceID) frontend.Source {
		b, readErr := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if readErr != nil {
			t.Fatal(readErr)
		}
		return frontend.Source{ID: id, Path: "compiler/src/" + name, Text: string(b)}
	}
	model := read("mir_model.al", 1)
	build := read("mir_build.al", 2)
	wrapper := frontend.Source{ID: 3, Path: "compiler/test/mir_core_main.al", Text: mirCoreWrapper}
	orders := [][]frontend.Source{{model, build, wrapper}, {wrapper, build, model}}
	artifacts := make([]string, len(orders))
	for i, sources := range orders {
		result, compileErr := Compile(Request{Sources: sources, Emit: EmitMIR})
		if compileErr != nil || result.Artifact == nil || len(result.Diagnostics) != 0 {
			t.Fatalf("compile MIR core order %d: result=%+v error=%v", i, result, compileErr)
		}
		artifacts[i] = result.Artifact.Text
	}
	if artifacts[0] != artifacts[1] {
		t.Fatal("MIR core changed with source permutation")
	}
	module, err := mir.Parse(artifacts[0])
	if err != nil {
		t.Fatalf("parse emitted MIR core MIR: %v", err)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify emitted MIR core MIR: %s", verify.Errors(diagnostics).String())
	}
	generated, err := cgen.GenerateProgram(module)
	if err != nil {
		t.Fatalf("generate MIR core C: %v", err)
	}
	dir := t.TempDir()
	cf := filepath.Join(dir, "mir-core.c")
	exe := filepath.Join(dir, "mir-core.exe")
	if err := os.WriteFile(cf, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-DALDER_HOST_CONFORMANCE", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cf, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, compileErr := exec.Command(cc, args...).CombinedOutput(); compileErr != nil {
		t.Fatalf("strict C11 compile: %v\n%s", compileErr, output)
	}
	want := "ALDER-MIR-CONTRACT 4\n" +
		"K 4\n" +
		"TK 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21\n" +
		"PR 1 2 3 4 5 6 7 8 9 10 11 12\n" +
		"PT 1 2 3\nCK 0 1 2 3 4\nPK 1 2\nVD 0 1 2 3\nPL 0 1 2\n" +
		"OP 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64\n" +
		"TM 0 1 2 3 4 5 6\nOK 1 2 3 4 5 6 7 8\n" +
		"T 1 0 0 0 0 0 0\nT 2 0 0 0 0 0 0\nT 3 0 0 0 0 0 0\nT 4 0 0 0 0 0 0\n" +
		"T 5 0 0 0 0 0 0\nT 6 0 0 0 0 0 0\nT 7 0 0 0 0 0 0\nT 8 0 0 0 0 0 0\n" +
		"T 9 0 0 0 0 0 0\nT 10 0 0 0 0 0 0\nT 11 0 0 0 0 0 0\nT 12 0 0 0 0 0 0\n" +
		"T 13 5 7 0 0 0 0\nT 14 4 0 10 2 0 0\nT 15 9 0 0 0 2 2\nT 16 1 0 0 0 0 0\n" +
		"R 1 15 3 0 10\nR 2 15 3 1 7\nR 3 16 1 0 10\n" +
		"D 1 1 2 2 1 1 3 1 1 1 1\nF 1 10\nF 2 1\n" +
		"Q 1 1 0 0 1\nQ 2 1 1 0 2\nL 1 0\nB 1 1\n" +
		"V 1 1 0 0 1\nV 1 2 1 1 1\nV 1 3 2 1 1\n" +
		"P 1 1 0 1 0 0\nI 1 1 1 0 15 3\nZ 1 1 1 3 3 0\n" +
		"O 1 2 1 0 0 0 0 10\nO 2 1 16 0 0 0 0 10\nO 3 3 1 0 0 1 0 0\nO 4 4 1 0 0 1 1 0\nO 5 5 1 0 0 1 1 0\nO 6 6 1 0 0 0 1 0\nO 7 7 6 0 0 1 1 0\nO 8 8 1 0 0 1 0 0\n" +
		"X 1 1 0\nX 1 1 0\nX 1 1 2\nX 2 1 1 9\nX 3 2 1 1\nX 4 5 1 0 1\nX 4 5 1 0 1\nX 4 7 999 0 0\nX 5 9 999 2\nEND\n"
	for i := 0; i < 2; i++ {
		output, runErr := conformanceCommand(exe).CombinedOutput()
		if runErr != nil {
			t.Fatalf("run MIR core wrapper %d: %v\n%s", i, runErr, output)
		}
		validateMIRContractManifest(t, string(output))
		if string(output) != want {
			t.Fatalf("MIR core manifest mismatch\nwant:\n%s\ngot:\n%s", want, output)
		}
	}
}

func validateMIRContractManifest(t *testing.T, text string) {
	t.Helper()
	want := map[string]struct {
		start int
		count int
	}{
		"TK": {0, int(mir.TypeVec) + 1},
		"PR": {1, int(mir.NumPrimitiveTypes)},
		"PT": {1, 3},
		"CK": {int(mir.ConstUnit), int(mir.ConstString) + 1},
		"PK": {1, 2},
		"VD": {int(mir.ValueDefFuncParam), int(mir.ValueDefSwitchCase) + 1},
		"PL": {int(mir.PlaceLocal), int(mir.PlaceDeref) + 1},
		"OP": {int(mir.OpLoad), int(mir.OpArrayAsSlice) + 1},
		"TM": {int(mir.TermJump), int(mir.TermPanic) + 1},
		"OK": {1, 8},
	}
	seen := make(map[string]bool, len(want))
	lines := strings.Split(text, "\n")
	if len(lines) < 12 || lines[0] != "ALDER-MIR-CONTRACT 4" || lines[1] != "K 4" {
		t.Fatalf("invalid MIR contract manifest envelope:\n%s", text)
	}
	for _, line := range lines[2:12] {
		fields := strings.Fields(line)
		spec, ok := want[fields[0]]
		if !ok || seen[fields[0]] || len(fields) != spec.count+1 {
			t.Fatalf("invalid MIR numeric contract row %q", line)
		}
		seen[fields[0]] = true
		for i, field := range fields[1:] {
			value, err := strconv.Atoi(field)
			if err != nil || value != spec.start+i {
				t.Fatalf("MIR numeric contract row %s[%d] = %q, want %d", fields[0], i, field, spec.start+i)
			}
		}
	}
	for tag := range want {
		if !seen[tag] {
			t.Fatalf("MIR numeric contract missing %s row", tag)
		}
	}
	operandKinds := make(map[int]bool)
	malformed := make(map[string]int)
	for _, line := range lines[12:] {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		switch fields[0] {
		case "O":
			if len(fields) != 9 {
				t.Fatalf("invalid operand row %q", line)
			}
			kind, err := strconv.Atoi(fields[2])
			if err != nil {
				t.Fatalf("invalid operand kind in %q", line)
			}
			operandKinds[kind] = true
		case "X":
			malformed[strings.Join(fields[1:], " ")]++
		}
	}
	for kind := 1; kind <= 8; kind++ {
		if !operandKinds[kind] {
			t.Fatalf("representative manifest does not exercise operand kind %d", kind)
		}
	}
	// Duplicate/gapped ordinals, orphan reciprocal links, conflicting owners,
	// duplicate edge ordinals, wrong owners, and invalid part boundaries are
	// decoded as-is rather than repaired by the Alder builders.
	wantMalformed := map[string]int{
		"1 1 0": 2, "1 1 2": 1, "2 1 1 9": 1, "3 2 1 1": 1,
		"4 5 1 0 1": 2, "4 7 999 0 0": 1, "5 9 999 2": 1,
	}
	for fixture, count := range wantMalformed {
		if malformed[fixture] != count {
			t.Fatalf("malformed fixture %q count = %d, want %d", fixture, malformed[fixture], count)
		}
	}
}
