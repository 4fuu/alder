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

	// copy_to_domain of a slice whose elements contain references: the M3
	// backend copies slice element bytes, so it must refuse this honestly.
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
	_, err = Generate(m2)
	if err == nil || !strings.Contains(err.Error(), "slice elements must be copy-trivial") {
		t.Fatalf("non-copyable copy_to_domain accepted: %v", err)
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
