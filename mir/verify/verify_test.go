package verify

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/aster/mir"
)

// TestGoldenAcceptance verifies that every golden fixture is accepted. The
// golden files exercise the full documented vocabulary; testdata/verify/accept
// holds additional targeted acceptance fixtures.
func TestGoldenAcceptance(t *testing.T) {
	var files []string
	for _, dir := range []string{
		filepath.Join("..", "testdata", "golden"),
		filepath.Join("testdata", "verify", "accept"),
	} {
		got, err := filepath.Glob(filepath.Join(dir, "*.mir"))
		if err != nil {
			t.Fatal(err)
		}
		files = append(files, got...)
	}
	if len(files) == 0 {
		t.Fatal("no acceptance fixtures found")
	}
	for _, path := range files {
		name := filepath.Base(path)
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m, err := mir.Parse(string(text))
		if err != nil {
			t.Fatalf("%s: parse: %v", name, err)
		}
		if errs := Module(m); len(errs) > 0 {
			t.Errorf("%s: unexpected diagnostics:\n%s", name, Errors(errs).String())
		}
	}
}

// TestRejectFixtures checks rejection fixtures with pinned diagnostics: each
// testdata/verify/reject/*.mir file has a sibling .err file with the exact
// expected diagnostics, one per line.
func TestRejectFixtures(t *testing.T) {
	files, err := filepath.Glob(filepath.Join("testdata", "verify", "reject", "*.mir"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("no rejection fixtures found")
	}
	for _, path := range files {
		name := filepath.Base(path)
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m, err := mir.Parse(string(text))
		if err != nil {
			t.Fatalf("%s: fixture must parse: %v", name, err)
		}
		got := Errors(Module(m)).String()
		errPath := strings.TrimSuffix(path, ".mir") + ".err"
		wantBytes, err := os.ReadFile(errPath)
		if err != nil {
			t.Fatalf("%s: missing .err file (got diagnostics:\n%s)", name, got)
		}
		want := strings.TrimSuffix(string(wantBytes), "\n")
		if got != want {
			t.Errorf("%s: diagnostics mismatch\n--- got ---\n%s\n--- want ---\n%s", name, got, want)
		}
		// Diagnostics must be deterministic across runs.
		if got2 := Errors(Module(m)).String(); got2 != got {
			t.Errorf("%s: diagnostics not deterministic", name)
		}
	}
}

// TestAPIRejections covers integrity violations that the textual parser
// cannot express (malformed value definitions, missing failure edges, result
// binding mismatches).
func TestAPIRejections(t *testing.T) {
	// Checked operation without a failure edge.
	m := mir.NewModule()
	f := m.AddFunction("f", nil, mir.TypeI64)
	b := f.AddBlock("bb0", nil)
	b.AddInstr(mir.Instr{Op: mir.OpIntAddChecked, Result: mir.NoValue, FailTarget: mir.NoBlock})
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs := Module(m)
	if !containsMsg(errs, "checked operation requires an 'else' failure edge") {
		t.Errorf("missing else edge not reported:\n%s", Errors(errs).String())
	}

	// A producing instruction that binds no result.
	m2 := mir.NewModule()
	f2 := m2.AddFunction("g", nil, mir.TypeUnit)
	b2 := f2.AddBlock("bb0", nil)
	b2.AddInstr(mir.Instr{Op: mir.OpDomainCreate, Result: mir.NoValue, Domain: 0})
	b2.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m2)
	if !containsMsg(errs, "binds no result") {
		t.Errorf("unbound producing instruction not reported:\n%s", Errors(errs).String())
	}

	// A value whose definition index does not match the instruction result.
	m3 := mir.NewModule()
	f3 := m3.AddFunction("h", nil, mir.TypeUnit)
	b3 := f3.AddBlock("bb0", nil)
	v0 := f3.AddValue("x", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	v1 := f3.AddValue("y", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 1})
	// Instruction 0 binds v1, so v0's claim that it defines instruction 0 is stale.
	b3.AddInstr(mir.Instr{Op: mir.OpConstGet, Const: "k", Result: v1})
	_ = v0
	b3.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m3)
	if !containsMsg(errs, "instruction result does not reference this value") {
		t.Errorf("stale value definition not reported:\n%s", Errors(errs).String())
	}

	// A type cycle: @A contains @B contains @A. Textual cycles cannot be
	// expressed because declarations must precede uses, so build via API.
	m4 := mir.NewModule()
	aID := m4.AddAggregate("A", nil)
	bID := m4.AddAggregate("B", nil)
	m4.Types[aID].Fields = []mir.Field{{Name: "b", Type: bID}}
	m4.Types[bID].Fields = []mir.Field{{Name: "a", Type: aID}}
	f4 := m4.AddFunction("cyc", nil, mir.TypeUnit)
	f4.AddBlock("bb0", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m4)
	if !containsMsg(errs, "type contains itself") {
		t.Errorf("type cycle not reported:\n%s", Errors(errs).String())
	}

	// A stored result type that contradicts the inferred type.
	m5 := mir.NewModule()
	m5.AddConst("k", mir.TypeI64, mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	f5 := m5.AddFunction("rm", nil, mir.TypeUnit)
	b5 := f5.AddBlock("bb0", nil)
	v5 := f5.AddValue("x", m5.Slice(mir.TypeU8), mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	b5.AddInstr(mir.Instr{Op: mir.OpConstGet, Const: "k", Result: v5})
	b5.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m5)
	if !containsMsg(errs, "result type mismatch: stored slice(u8), expected i64") {
		t.Errorf("result type mismatch not reported:\n%s", Errors(errs).String())
	}
}

func containsMsg(errs []Error, substr string) bool {
	for _, e := range errs {
		if strings.Contains(e.String(), substr) {
			return true
		}
	}
	return false
}
