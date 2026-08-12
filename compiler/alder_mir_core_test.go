package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
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
    let slice = try mir_intern_type(d, store, 5, 7, 0, 0, empty, 0)
    store = slice.store
    let same_slice = try mir_intern_type(d, store, 5, 7, 0, 0, empty, 0)
    store = same_slice.store
    let result = try mir_intern_type(d, store, 4, 0, 10, 2, empty, 0)
    store = result.store
    var signature = try __s0_buffer_append(U64, d, empty, 10)
    signature = try __s0_buffer_append(U64, d, signature, 7)
    let function_type = try mir_intern_type(d, store, 9, 0, 0, 0, signature, 2)
    store = function_type.store
    let pair = try mir_add_named_type(d, store, 1, "Pair")
    store = try mir_add_type_part(d, pair.store, 1, pair.type_id, 0, "value", 10)
    let imported = try mir_add_import(d, store, "foreign", 10)
    store = imported.store
    let constant = try mir_add_const(d, store, "seven", 10, 2, 0, 7, 0, "")
    store = constant.store
    let sum = try mir_add_function(d, store, "sum", 10)
    store = sum.store
    let x = try mir_add_function_param(d, store, sum.id, 0, "x", 10)
    store = x.store
    let slot = try mir_add_local(d, store, sum.id, 0, "slot", 10)
    store = slot.store
    let entry = try mir_add_block(d, store, sum.id, 0, "entry")
    store = entry.store
    let y = try mir_add_block_param(d, store, sum.id, entry.id, 0, "y", 10)
    store = y.store
    let place = try mir_add_place(d, store, MirPlaceRec(function: sum.id, kind: 0, local: slot.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    store = place.store
    let added = try mir_add_value(d, store, sum.id, "added", 10, 2, entry.id, 1)
    store = added.store
    let instruction = MirInstrRec(function: sum.id, block: entry.id, ordinal: 0, op: 15, result: added.id, place: 0, type_op: 0, a: x.id, b: y.id, c: 0, target: 0, name_start: 0, name_end: 0)
    let instruction_step = try mir_add_instruction(d, store, instruction)
    store = instruction_step.store
    let term = try mir_add_terminator(d, store, MirTermRec(function: sum.id, block: entry.id, kind: 3, value: added.id, target: 0, then_block: 0, else_block: 0))
    store = term.store
    let helper = try mir_add_function(d, store, "helper", 1)
    return Ok(helper.store)
}

fn emit_representative(store: MirStore) -> Bool {
    if !mout(77) || !mout(73) || !mout(82) || !mout(45) || !mout(67) || !mout(79) || !mout(82) || !mout(69) || !mout(32) || !mout(49) || !mout(10) { return false }
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
    if !mout(68) || !mfield(__s0_buffer_len(MirImportRec, store.imports)) || !mfield(__s0_buffer_len(MirConstRec, store.constants)) || !mfield(__s0_buffer_len(MirFunctionRec, store.functions)) || !mfield(__s0_buffer_len(MirLocalRec, store.locals)) || !mfield(__s0_buffer_len(MirBlockRec, store.blocks)) || !mfield(__s0_buffer_len(MirValueRec, store.values)) || !mfield(__s0_buffer_len(MirPlaceRec, store.places)) || !mfield(__s0_buffer_len(MirInstrRec, store.instructions)) || !mfield(__s0_buffer_len(MirTermRec, store.terminators)) || !mout(10) { return false }
    at = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, at)
        if !mout(70) || !mfield(at + 1) || !mfield(rec.result_type) || !mout(10) { return false }
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
	artifacts := make([]map[EmitKind]string, len(orders))
	for i, sources := range orders {
		artifacts[i] = make(map[EmitKind]string)
		for _, emit := range []EmitKind{EmitMIR, EmitC} {
			result, compileErr := Compile(Request{Sources: sources, Emit: emit})
			if compileErr != nil || result.Artifact == nil || len(result.Diagnostics) != 0 {
				t.Fatalf("compile MIR core %s order %d: result=%+v error=%v", emit, i, result, compileErr)
			}
			artifacts[i][emit] = result.Artifact.Text
		}
	}
	for _, emit := range []EmitKind{EmitMIR, EmitC} {
		if artifacts[0][emit] != artifacts[1][emit] {
			t.Fatalf("MIR core %s changed with source permutation", emit)
		}
	}
	module, err := mir.Parse(artifacts[0][EmitMIR])
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
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cf, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, compileErr := exec.Command(cc, args...).CombinedOutput(); compileErr != nil {
		t.Fatalf("strict C11 compile: %v\n%s", compileErr, output)
	}
	want := "MIR-CORE 1\n" +
		"T 1 0 0 0 0 0 0\nT 2 0 0 0 0 0 0\nT 3 0 0 0 0 0 0\nT 4 0 0 0 0 0 0\n" +
		"T 5 0 0 0 0 0 0\nT 6 0 0 0 0 0 0\nT 7 0 0 0 0 0 0\nT 8 0 0 0 0 0 0\n" +
		"T 9 0 0 0 0 0 0\nT 10 0 0 0 0 0 0\nT 11 0 0 0 0 0 0\nT 12 0 0 0 0 0 0\n" +
		"T 13 5 7 0 0 0 0\nT 14 4 0 10 2 0 0\nT 15 9 0 0 0 2 2\nT 16 1 0 0 0 0 0\n" +
		"R 1 15 3 0 10\nR 2 15 3 1 7\nR 3 16 1 0 10\n" +
		"D 1 1 2 1 1 3 1 1 1\nF 1 10\nF 2 1\nB 1 1\nV 1 1 0 0 0\nV 1 2 1 1 0\nV 1 3 2 1 1\nEND\n"
	for i := 0; i < 2; i++ {
		output, runErr := exec.Command(exe).CombinedOutput()
		if runErr != nil {
			t.Fatalf("run MIR core wrapper %d: %v\n%s", i, runErr, output)
		}
		if string(output) != want {
			t.Fatalf("MIR core manifest mismatch\nwant:\n%s\ngot:\n%s", want, output)
		}
	}
}
