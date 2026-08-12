package compiler

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

var mirVerifySourceManifest = []string{
	"mir_model.al",
	"mir_build.al",
	"verify_model.al",
	"verify_analysis.al",
	"verify_phase1.al",
	"verify_phase2.al",
	"verify_phase3.al",
}

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

fn run_cases(d: Domain, initial: MirStore) -> Result(Bool, __s0_Error) {
    let valid_store = try minimal(d, initial, mir_type_unit(), false)
    let valid = try mir_verify_1_3(d, valid_store, 3)
    if !emit_verification(0, valid) { return Ok(false) }

    let empty_types = try __s0_buffer_new(MirTypeRec, d)
    let phase1 = try mir_verify_1_3(d, mir_with_types(valid_store, empty_types), 3)
    if !emit_verification(1, phase1) { return Ok(false) }

    let phase2_store = try minimal(d, initial, 999, false)
    let phase2 = try mir_verify_1_3(d, phase2_store, 3)
    if !emit_verification(2, phase2) { return Ok(false) }

    let phase3_store = try minimal(d, initial, mir_type_unit(), true)
    let phase3 = try mir_verify_1_3(d, phase3_store, 3)
    if !emit_verification(3, phase3) { return Ok(false) }

    let fail_fast = try mir_verify_1_3(d, phase2_store, 99)
    if !emit_verification(4, fail_fast) { return Ok(false) }
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

func TestAlderMIRVerifierPhasesOneThroughThree(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var sources []frontend.Source
	for i, name := range mirVerifySourceManifest {
		text, readErr := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if readErr != nil {
			t.Fatal(readErr)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	sources = append(sources, frontend.Source{ID: frontend.SourceID(len(sources) + 1), Path: "compiler/test/mir_verify_main.al", Text: mirVerifyWrapper})

	compiled, err := Compile(Request{Sources: sources, Emit: EmitMIR})
	if err != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		t.Fatalf("compile verifier wrapper: result=%+v error=%v", compiled, err)
	}
	module, err := mir.Parse(compiled.Artifact.Text)
	if err != nil {
		t.Fatalf("parse verifier wrapper MIR: %v", err)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify verifier wrapper MIR: %s", verify.Errors(diagnostics).String())
	}
	generated, err := cgen.GenerateProgram(module)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "verifier.c")
	exe := filepath.Join(dir, "verifier.exe")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	compileGeneratedProgram(t, cc, root, cfile, filepath.Join(root, "bootstrap", "alder_host.c"), exe)

	want := "V 0 0\nV 1 1\nD 1 2 0 0 0 0 0 0 0 12 0 0\nV 2 1\nD 2 21 1 0 0 0 0 999 1 0 0 999\nV 3 1\nD 3 25 1 1 0 0 0 0 0 0 1 0\nV 4 1\nD 1 1 0 0 0 0 0 0 0 1 99 3\n"
	var baseline string
	for i := 0; i < 3; i++ {
		cmd := exec.Command(exe)
		cmd.Dir = t.TempDir()
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil || stderr.Len() != 0 {
			t.Fatalf("run verifier wrapper %d: %v stderr=%q", i, err, stderr.String())
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
