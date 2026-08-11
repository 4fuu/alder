package cgen

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/aster/mir"
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

func generateFixture(t *testing.T, name string) string {
	t.Helper()
	text, err := os.ReadFile(goldenMirPath(name))
	if err != nil {
		t.Fatal(err)
	}
	m, err := mir.Parse(string(text))
	if err != nil {
		t.Fatalf("%s: parse: %v", name, err)
	}
	out, err := Generate(m)
	if err != nil {
		t.Fatalf("%s: generate: %v", name, err)
	}
	return out
}

// TestGolden pins the generated C for every golden fixture. Set
// ASTER_UPDATE_GOLDEN=1 to regenerate the committed files.
func TestGolden(t *testing.T) {
	update := os.Getenv("ASTER_UPDATE_GOLDEN") == "1"
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
				t.Fatalf("missing golden %s (run with ASTER_UPDATE_GOLDEN=1): %v", path, err)
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
	cc := findCompiler(t)
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

func findCompiler(t *testing.T) string {
	t.Helper()
	for _, name := range []string{"gcc", "cc", "clang"} {
		if path, err := exec.LookPath(name); err == nil {
			t.Logf("C compiler: %s", path)
			return path
		}
	}
	t.Skip("no C compiler found (gcc, cc, or clang); backend tests skipped")
	return ""
}
