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

// This deliberately builds the flat records rather than exercising a second
// textual printer in the wrapper.  In particular, the failed first call proves
// that validation precedes output: any bytes from it make the final comparison
// fail.
const mirPrinterWrapper = `
import c alderhost_stdout_byte: fn(U8) -> Bool
import c alderhost_stdout_f64_bits: fn(U64) -> Bool

fn printer_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    var store = initial
    let no_parts = try __s0_buffer_new(U64, d)
    let string_type = try mir_intern_type(d, store, mir_type_kind_slice(), mir_type_u8(), 0, 0, no_parts, 0)
    store = string_type.store
    let lo = try mir_add_const(d, store, "min", mir_type_i64(), mir_const_int(), 0, -9223372036854775807 - 1, 0, "")
    store = lo.store
    let hi = try mir_add_const(d, store, "max", mir_type_i64(), mir_const_int(), 0, 9223372036854775807, 0, "")
    store = hi.store
    let tiny = try mir_add_const(d, store, "tiny", mir_type_f64(), mir_const_float(), 0, 0, 1, "")
    store = tiny.store
    let largest = try mir_add_const(d, store, "largest", mir_type_f64(), mir_const_float(), 0, 0, 9218868437227405311, "")
    store = largest.store
    let escaped = try mir_add_const(d, store, "escaped", string_type.type_id, mir_const_string(), 0, 0, 0, "a\n\t\r\\\"\0z")
    store = escaped.store
    let function = try mir_add_function(d, store, "main", mir_type_unit())
    store = function.store
    let block = try mir_add_block(d, store, function.id, 0, "bb0")
    store = block.store
    let term = try mir_add_terminator(d, store, MirTermRec(function: function.id, block: block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(term.store)
}

fn run_print(d: Domain, store: MirStore) -> Result(I32, __s0_Error) {
    // A raw invalid constant type must be rejected without writing "mir 3".
    let bad = try mir_add_const(d, store, "bad", 999, mir_const_int(), 0, 1, 0, "")
    if mir_print(bad.store) { return Ok(5) }
    let fixture = try printer_fixture(d, store)
    let duplicate_term = try mir_add_terminator(d, fixture, MirTermRec(function: 1, block: 1, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    if mir_print(duplicate_term.store) { return Ok(7) }
    let wrong_owner = try mir_add_operand(d, fixture, MirOperandRec(kind: mir_operand_instruction(), owner: 999, ordinal: 0, edge: 0, value: 0, target: 0, operand_type: 0, name_start: 0, name_end: 0))
    if mir_print(wrong_owner.store) { return Ok(8) }
    if mir_print(fixture) { return Ok(0) }
    return Ok(6)
}

fn main(d: Domain) -> I32 { return match mir_store_new(d) {
    Err(error) => 3
    Ok(store) => match run_print(d, store) {
        Err(error) => 4
        Ok(code) => code
    }
} }
`

func TestAlderMIRPrinterConformance(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	names := []string{"output.al", "model.al", "mir_model.al", "mir_build.al", "mir_print.al"}
	sources := make([]frontend.Source, 0, len(names)+1)
	for i, name := range names {
		text, readErr := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if readErr != nil {
			t.Fatal(readErr)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	sources = append(sources, frontend.Source{ID: 100, Path: "compiler/test/mir_printer_main.al", Text: mirPrinterWrapper})
	permuted := append([]frontend.Source(nil), sources...)
	for left, right := 0, len(permuted)-1; left < right; left, right = left+1, right-1 {
		permuted[left], permuted[right] = permuted[right], permuted[left]
	}

	// Compile the deliberately reversed closure; Compile's canonical logical
	// path ordering is independently permutation-tested by
	// TestMultiSourcePermutationsProduceIdenticalMIRAndC.
	result, compileErr := Compile(Request{Sources: permuted, Emit: EmitMIR})
	if compileErr != nil || result.Artifact == nil || len(result.Diagnostics) != 0 {
		t.Fatalf("compile source-permuted printer MIR: result=%+v error=%v", result, compileErr)
	}
	parsedWrapper, parseErr := mir.Parse(result.Artifact.Text)
	if parseErr != nil || len(verify.Module(parsedWrapper)) != 0 {
		t.Fatalf("invalid generated wrapper MIR: parse=%v verify=%v", parseErr, verify.Module(parsedWrapper))
	}
	generated, genErr := cgen.GenerateProgram(parsedWrapper)
	if genErr != nil {
		t.Fatalf("generate wrapper C: %v", genErr)
	}

	dir := t.TempDir()
	cfile, exe := filepath.Join(dir, "printer.c"), filepath.Join(dir, "printer.exe")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cfile, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, compileErr := exec.Command(cc, args...).CombinedOutput(); compileErr != nil {
		t.Fatalf("strict C11 compile: %v\n%s", compileErr, output)
	}

	wantSource := "mir 3\n\nconst @min: i64 = -9223372036854775808\n\nconst @max: i64 = 9223372036854775807\n\nconst @tiny: f64 = 5e-324\n\nconst @largest: f64 = 1.7976931348623157e+308\n\nconst @escaped: slice(u8) = \"a\\n\\t\\r\\\\\\\"\\x00z\"\n\nfn @main() {\nbb0:\n  return\n}\n"
	wantModule, err := mir.Parse(wantSource)
	if err != nil {
		t.Fatalf("parse canonical expectation: %v", err)
	}
	want := mir.Print(wantModule)
	for run := 0; run < 2; run++ {
		output, runErr := exec.Command(exe).Output()
		if runErr != nil {
			t.Fatalf("run printer %d: %v", run, runErr)
		}
		if string(output) != want {
			t.Fatalf("printer output mismatch on run %d\nwant:\n%s\ngot:\n%s", run, want, output)
		}
		parsed, parseErr := mir.Parse(string(output))
		if parseErr != nil {
			t.Fatalf("parse printer output: %v", parseErr)
		}
		if diagnostics := verify.Module(parsed); len(diagnostics) != 0 {
			t.Fatalf("verify printer output: %s", verify.Errors(diagnostics).String())
		}
		if got := mir.Print(parsed); got != string(output) {
			t.Fatalf("printer output is not canonical\nreprinted:\n%s", got)
		}
	}
}
