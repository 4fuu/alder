package cgen

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// goldenSources are the MIR inputs whose generated C is pinned in
// testdata/golden. The shared MIR goldens live in ../mir/testdata/golden.
var goldenSources = []string{
	"arithmetic",
	"summarize",
	"tables",
	"domains",
	"extract",
	"ffi",
	"cfg",
}

func goldenMirPath(name string) string {
	return filepath.Join("..", "mir", "testdata", "golden", name+".mir")
}

// generatePath parses a MIR file and generates its C.
func generatePath(t *testing.T, path string) string {
	t.Helper()
	text, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	m, err := mir.Parse(string(text))
	if err != nil {
		t.Fatalf("%s: parse: %v", path, err)
	}
	out, err := Generate(m)
	if err != nil {
		t.Fatalf("%s: generate: %v", path, err)
	}
	return out
}

func generateFixture(t *testing.T, name string) string {
	t.Helper()
	return generatePath(t, goldenMirPath(name))
}

func TestRejectsMismatchedLoadResultTypeWithNoOutput(t *testing.T) {
	m := mir.NewModule()
	m.AddConst("source", mir.TypeI64, mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	f := m.AddFunction("bad_load", nil, mir.TypeUnit)
	b := f.AddBlock("bb0", nil)
	local := f.AddLocal("slot", mir.TypeI64)
	source := f.AddValue("source", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	b.AddInstr(mir.Instr{Op: mir.OpConstGet, Result: source, Const: "source", FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpStore, Result: mir.NoValue, Place: mir.Place{Kind: mir.PlaceLocal, Local: local}, StoreVal: source, FailTarget: mir.NoBlock})
	loaded := f.AddValue("loaded", mir.TypeBool, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 2})
	b.AddInstr(mir.Instr{Op: mir.OpLoad, Result: loaded, Place: mir.Place{Kind: mir.PlaceLocal, Local: local}, FailTarget: mir.NoBlock})
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})

	out, err := Generate(m)
	if err == nil || !strings.Contains(err.Error(), "result type mismatch: stored bool, expected i64") {
		t.Fatalf("mismatched load result was not rejected by V5: %v", err)
	}
	if out != "" {
		t.Fatalf("mismatched load result emitted C:\n%s", out)
	}
}

// TestGolden pins the generated C for every golden fixture. Set
// ALDER_UPDATE_GOLDEN=1 to regenerate the committed files.
func TestGolden(t *testing.T) {
	update := os.Getenv("ALDER_UPDATE_GOLDEN") == "1"
	for _, name := range goldenSources {
		name := name
		t.Run(name, func(t *testing.T) {
			got := generateFixture(t, name)
			path := filepath.Join("testdata", "golden", name+".c")
			if update {
				if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("missing golden %s (run with ALDER_UPDATE_GOLDEN=1): %v", path, err)
			}
			if got != string(want) {
				t.Errorf("generated C differs from %s\n--- got ---\n%s\n--- want ---\n%s", path, got, want)
			}
		})
	}
}

// TestStrictCompile compiles every generated golden under the strict warning
// set (syntax-only: drivers are not part of the module output).
func TestStrictCompile(t *testing.T) {
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			for _, name := range goldenSources {
				name := name
				t.Run(name, func(t *testing.T) {
					t.Parallel()
					gen := writeGenerated(t, name)
					out, err := exec.Command(cc, strictArgs(gen)...).CombinedOutput()
					if err != nil {
						t.Fatalf("strict compile of %s failed: %v\n%s", name, err, out)
					}
				})
			}
		})
	}
}

func TestPanicTerminatorStrictCompile(t *testing.T) {
	m, err := mir.Parse("mir 2\nfn @f() {\nentry:\n  panic\n}\n")
	if err != nil {
		t.Fatal(err)
	}
	out, err := Generate(m)
	if err != nil {
		t.Fatal(err)
	}
	const call = `alder_runtime_panic("checked operation failed");`
	if strings.Count(out, call) != 1 {
		t.Fatalf("generated C contains fixed panic call %d times, want 1:\n%s", strings.Count(out, call), out)
	}
	for _, cc := range findCompilers(t) {
		gen := filepath.Join(t.TempDir(), "panic.c")
		if err := os.WriteFile(gen, []byte(out), 0o644); err != nil {
			t.Fatal(err)
		}
		if got, err := exec.Command(cc, strictArgs(gen)...).CombinedOutput(); err != nil {
			t.Fatalf("strict compile failed: %v\n%s", err, got)
		}
	}
}

// TestRegressionStrictCompile covers valid declarations and SSA shapes which
// intentionally need no emitted C storage.
func TestRegressionStrictCompile(t *testing.T) {
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			out := generatePath(t, filepath.Join("testdata", "strict.mir"))
			gen := filepath.Join(t.TempDir(), "strict.c")
			if err := os.WriteFile(gen, []byte(out), 0o644); err != nil {
				t.Fatal(err)
			}
			if got, err := exec.Command(cc, strictArgs(gen)...).CombinedOutput(); err != nil {
				t.Fatalf("strict regression compile failed: %v\n%s", err, got)
			}
		})
	}
}

// writeGenerated writes the generated C for a fixture to a temp file and
// returns its path.
func writeGenerated(t *testing.T, name string) string {
	t.Helper()
	dir := t.TempDir()
	gen := filepath.Join(dir, name+".c")
	if err := os.WriteFile(gen, []byte(generateFixture(t, name)), 0o644); err != nil {
		t.Fatal(err)
	}
	return gen
}

// strictArgs returns the canonical strict C11 warning flags for compiling a
// generated file.
func strictArgs(gen string) []string {
	return []string{
		"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
		"-Wshadow", "-Wconversion",
		"-I", filepath.Join("..", "runtime", "c"),
		"-fsyntax-only", gen,
	}
}

// TestGenerateRejectsUnverified checks the verified-only gate: invalid
// modules must be refused with the verifier diagnostics, never lowered.
func TestGenerateRejectsUnverified(t *testing.T) {
	// A checked operation without a failure edge (API-built module).
	m := mir.NewModule()
	f := m.AddFunction("bad", nil, mir.TypeI64)
	f.AddBlock("bb0", nil).AddInstr(mir.Instr{Op: mir.OpIntAddChecked, Result: mir.NoValue, FailTarget: mir.NoBlock})
	f.Blocks[0].SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	_, err := Generate(m)
	if err == nil || !strings.Contains(err.Error(), "checked operation requires an 'else' failure edge") {
		t.Fatalf("unverified module accepted: %v", err)
	}

	// copy_to_domain recursively materializes non-trivial slice elements.
	text := `mir 1

fn @copy(%d: domain_handle, %s: slice(slice(u8))) -> slice(slice(u8)) {
bb0:
  %r = copy_to_domain %d, %s
  return %r
}
`
	m2, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = Generate(m2); err != nil {
		t.Fatalf("recursive copy_to_domain rejected: %v", err)
	}

	// The internal trusted generation path still keeps its copyability contract:
	// identity-bearing children must not be hidden by aggregate triviality.
	identity := `mir 4
type @P {
  value: u64
}
type @Mixed {
  value: u64
  table: table(@P)
}
fn @copy(%d: domain_handle, %value: @Mixed) {
entry:
  %copy = copy_to_domain %d, %value
  return
}
`
	m3, err := mir.Parse(identity)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = generate(m3, mir.NoFunction, false); err == nil || !strings.Contains(err.Error(), "identity-bearing type is not relocatable") {
		t.Fatalf("trusted Cgen accepted identity-bearing aggregate copy: %v", err)
	}
}

// TestGenerateRejectsUnsafeExternalNames pins the backend-safe subset of MIR
// import names. API construction is intentional: punctuation is representable
// in the model even when textual MIR tokenization would reject it earlier.
func TestGenerateRejectsUnsafeExternalNames(t *testing.T) {
	for _, name := range []string{
		"has.dot",    // punctuation
		"return",     // C keyword
		"alder_call", // generated/backend prefix
		"uint64_t",   // token introduced by the runtime header
		"bool",       // object-like macro introduced by the runtime header
		"FLT_MAX",    // macro-style token introduced by a generated include
		"offsetof",   // function-like macro introduced by the runtime header
		"memcpy",     // function declared by a generated include
		"strlen",     // function declared by a generated include
		"main",       // special hosted C entry-point identifier
	} {
		name := name
		t.Run(name, func(t *testing.T) {
			m := mir.NewModule()
			m.AddImport(name, mir.FuncSig{Result: mir.TypeUnit})
			if _, err := Generate(m); err == nil || !strings.Contains(err.Error(), "C symbol must be a non-reserved C identifier") {
				t.Fatalf("unsafe C external name %q accepted: %v", name, err)
			}
		})
	}
}

// TestAPIAggregateForwardOrderingStrictCompile covers API-built type tables,
// where an earlier declaration can refer to a later aggregate by stable ID.
// Function types are included both in aggregate fields and function ABI.
func TestAPIAggregateForwardOrderingStrictCompile(t *testing.T) {
	m := mir.NewModule()
	earlier := m.AddAggregate("Earlier", nil)
	later := m.AddAggregate("Later", []mir.Field{{Name: "value", Type: mir.TypeI32}})
	callback := m.FunctionType(mir.FuncSig{Params: []mir.TypeId{later}, Result: mir.TypeI32})
	m.Types[earlier].Fields = []mir.Field{
		{Name: "later", Type: later},
		{Name: "callback", Type: callback},
	}
	m.AddImport("external_callback", mir.FuncSig{Params: []mir.TypeId{callback, earlier}, Result: later})

	out, err := Generate(m)
	if err != nil {
		t.Fatalf("generate API-built forward type graph: %v", err)
	}
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			gen := filepath.Join(t.TempDir(), "api_types.c")
			if err := os.WriteFile(gen, []byte(out), 0o644); err != nil {
				t.Fatal(err)
			}
			if got, err := exec.Command(cc, strictArgs(gen)...).CombinedOutput(); err != nil {
				t.Fatalf("strict compile of API-built forward types failed: %v\n%s", err, got)
			}
		})
	}
}

func findCompilers(t *testing.T) []string {
	t.Helper()
	var found []string
	seen := make(map[string]bool)
	for _, name := range []string{"gcc", "clang"} {
		if path, err := exec.LookPath(name); err == nil {
			key, err := filepath.EvalSymlinks(path)
			if err != nil {
				key = path
			}
			key = strings.ToLower(filepath.Clean(key))
			if !seen[key] {
				seen[key] = true
				found = append(found, path)
			}
		}
	}
	if len(found) == 0 {
		if path, err := exec.LookPath("cc"); err == nil {
			found = append(found, path)
		}
	}
	if len(found) == 0 {
		t.Skip("no C compiler found (gcc, clang, or fallback cc); backend tests skipped")
	}
	for _, path := range found {
		t.Logf("C compiler: %s", path)
	}
	return found
}
