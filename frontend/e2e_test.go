package frontend

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// e2eFixtures are the end-to-end source programs. Each must define main
// returning I32 (0 = success). A fixture may declare a `main(d: Domain)`
// parameter; the driver provides a root domain. Optional FFI symbols are
// provided by the per-fixture C driver file.
var e2eFixtures = []struct {
	src    string
	driver string // C driver content; "default" generates a plain driver
}{
	{"arith", "default"},
	{"structs", "default"},
	{"enums", "default"},
	{"option", "default"},
	{"strings", "default"},
	{"generic", "default"},
	{"domains", "default"},
	{"maps", "default"},
	{"cleanup", "cleanup_driver.c"},
	{"ffi", "ffi_driver.c"},
}

// compileAndGenerate compiles source text and lowers it to C, requiring the
// lowered MIR to pass the verifier unchanged.
func compileAndGenerate(t *testing.T, src string) (string, *mir.Module) {
	t.Helper()
	m, err := Compile(src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}
	if errs := verify.Module(m); len(errs) > 0 {
		t.Fatalf("lowered MIR failed verification:\n%s", verify.Errors(errs).String())
	}
	out, err := generateC(m)
	if err != nil {
		t.Fatalf("cgen: %v", err)
	}
	return out, m
}

// defaultDriver builds a driver that runs main (with a root domain when the
// first parameter is a domain) and returns its result.
func defaultDriver(m *mir.Module) (string, error) {
	id, ok := m.Function("main")
	if !ok {
		return "", fmt.Errorf("fixture has no main function")
	}
	f := m.Functions[id]
	var call string
	if len(f.Params) > 0 && f.Params[0].Type == m.DomainHandle() {
		call = fmt.Sprintf("alder_fn_main_%d(&alder_root)", id)
	} else {
		call = fmt.Sprintf("alder_fn_main_%d()", id)
	}
	return fmt.Sprintf(`#include "gen.c"
#include <stdio.h>
int main(void) {
    int result = 0;
    AlderDomain alder_root;
    if (!alder_domain_init(&alder_root, NULL)) { return 97; }
    result = (int)%s;
    alder_domain_destroy(&alder_root);
    if (alder_runtime_live_allocations() != (size_t)0) { return 98; }
    return result;
}
`, call), nil
}

// generateC lowers a verified module to C11 through the cgen backend.
func generateC(m *mir.Module) (string, error) {
	return cgen.Generate(m)
}

func writeFiles(t *testing.T, name, gen, driver string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	genPath := filepath.Join(dir, "gen.c")
	driverPath := filepath.Join(dir, name+"_driver.c")
	if err := os.WriteFile(genPath, []byte(gen), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(driverPath, []byte(driver), 0o644); err != nil {
		t.Fatal(err)
	}
	return genPath, driverPath
}

// TestE2E compiles each source fixture end to end: source -> typed and
// monomorphized -> verified MIR -> strict C11 -> run.
func TestE2E(t *testing.T) {
	for _, cc := range findCCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			for _, e2e := range e2eFixtures {
				e2e := e2e
				t.Run(e2e.src, func(t *testing.T) {
					src := readFixture(t, filepath.Join("testdata", "e2e", e2e.src+".al"))
					gen, m := compileAndGenerate(t, src)
					driver := ""
					if e2e.driver == "default" {
						d, err := defaultDriver(m)
						if err != nil {
							t.Fatal(err)
						}
						driver = d
					} else {
						driver = readFixture(t, filepath.Join("testdata", "e2e", e2e.driver))
						// The driver template references the entry function by
						// its deterministic id.
						id, ok := m.Function("main")
						if !ok {
							t.Fatal("fixture has no main function")
						}
						driver = strings.ReplaceAll(driver, "alder_fn_main_IDX", fmt.Sprintf("alder_fn_main_%d", id))
					}
					genPath, driverPath := writeFiles(t, e2e.src, gen, driver)
					exe := filepath.Join(t.TempDir(), e2e.src+".exe")
					args := []string{
						"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
						"-Wshadow", "-Wconversion",
						"-I", filepath.Dir(genPath),
						"-I", filepath.Join("..", "runtime", "c"),
						genPath, driverPath, filepath.Join("..", "runtime", "c", "alder.c"),
						"-o", exe,
					}
					if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
						t.Fatalf("strict compile failed: %v\n%s", err, out)
					}
					if out, err := exec.Command(exe).CombinedOutput(); err != nil {
						t.Fatalf("run failed: %v\n%s", err, out)
					}
				})
			}
		})
	}
}

func TestCheckedFailureRunsCurrentFunctionCleanupThenPanics(t *testing.T) {
	src := `
import c note: fn(I64) -> Unit
fn cleanup(x: I64) -> Unit { unsafe c { note(x) } }
fn main() -> I32 {
    using outer = 1 with cleanup
    using inner = 2 with cleanup
    let zero: I64 = 0
    let checked = 1 / zero
    return 0
}
`
	gen, m := compileAndGenerate(t, src)
	id, ok := m.Function("main")
	if !ok {
		t.Fatal("fixture has no main function")
	}
	driver := fmt.Sprintf(`#include "gen.c"
#include <stdio.h>
void note(int64_t x) { (void)fprintf(stderr, "cleanup:%%lld\n", (long long)x); }
int main(void) { return (int)alder_fn_main_%d(); }
`, id)
	for _, cc := range findCCompilers(t) {
		genPath, driverPath := writeFiles(t, "checked_panic", gen, driver)
		exe := filepath.Join(t.TempDir(), "checked_panic.exe")
		args := []string{
			"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
			"-Wshadow", "-Wconversion",
			"-I", filepath.Dir(genPath),
			"-I", filepath.Join("..", "runtime", "c"),
			genPath, driverPath, filepath.Join("..", "runtime", "c", "alder.c"),
			"-o", exe,
		}
		if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
			t.Fatalf("strict compile failed: %v\n%s", err, out)
		}
		out, err := exec.Command(exe).CombinedOutput()
		if err == nil {
			t.Fatal("checked failure exited successfully")
		}
		text := string(out)
		inner := strings.Index(text, "cleanup:2")
		outer := strings.Index(text, "cleanup:1")
		panicMessage := strings.Index(text, "alder runtime panic: checked operation failed")
		if inner < 0 || outer <= inner || panicMessage <= outer {
			t.Fatalf("cleanup/panic order mismatch:\n%s", text)
		}
	}
}

func TestCheckedBoundaryFailuresPanic(t *testing.T) {
	tests := []struct {
		name string
		src  string
	}{
		{
			name: "u8_overflow",
			src: `
fn main() -> I32 {
    var n: U8 = 200
    n = n + 100
    return 0
}
`,
		},
		{
			name: "map_capacity",
			src: `
fn main(d: Domain) -> I32 {
    var m = __s0_map_create(Map(U64, U64), d)
    var i: U64 = 0
    while i < 17 {
        Set(m, i, i)
        i = i + 1
    }
    return 0
}
`,
		},
	}
	for _, cc := range findCCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			for _, tc := range tests {
				tc := tc
				t.Run(tc.name, func(t *testing.T) {
					gen, m := compileAndGenerate(t, tc.src)
					driver, err := defaultDriver(m)
					if err != nil {
						t.Fatal(err)
					}
					genPath, driverPath := writeFiles(t, tc.name, gen, driver)
					exe := filepath.Join(t.TempDir(), tc.name+".exe")
					args := []string{
						"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
						"-Wshadow", "-Wconversion",
						"-I", filepath.Dir(genPath),
						"-I", filepath.Join("..", "runtime", "c"),
						genPath, driverPath, filepath.Join("..", "runtime", "c", "alder.c"),
						"-o", exe,
					}
					if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
						t.Fatalf("strict compile failed: %v\n%s", err, out)
					}
					out, err := exec.Command(exe).CombinedOutput()
					if err == nil {
						t.Fatal("checked boundary failure exited successfully")
					}
					if text := string(out); !strings.Contains(text, "alder runtime panic: checked operation failed") {
						t.Fatalf("missing checked-failure panic message:\n%s", text)
					}
				})
			}
		})
	}
}

// TestE2ERoundTrip prints each fixture's MIR, re-parses it, and verifies the
// printed form is stable and valid.
func TestE2ERoundTrip(t *testing.T) {
	for _, e2e := range e2eFixtures {
		e2e := e2e
		t.Run(e2e.src, func(t *testing.T) {
			src := readFixture(t, filepath.Join("testdata", "e2e", e2e.src+".al"))
			m, err := Compile(src)
			if err != nil {
				t.Fatal(err)
			}
			text := mir.Print(m)
			m2, err := mir.Parse(text)
			if err != nil {
				t.Fatalf("re-parse failed: %v\n%s", err, text)
			}
			if errs := verify.Module(m2); len(errs) > 0 {
				t.Fatalf("re-parsed MIR failed verification:\n%s", verify.Errors(errs).String())
			}
			if mir.Print(m2) != text {
				t.Fatal("printed MIR is not a fixed point")
			}
		})
	}
}

func findCCompilers(t *testing.T) []string {
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
		t.Skip("no C compiler found; e2e tests skipped")
	}
	return found
}

func readFixture(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
