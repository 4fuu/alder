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
// provided by the per-fixture C driver file. Fixtures marked private still
// exercise the S0 bootstrap bridges as runtime implementation evidence and
// compile under the private bootstrap profile only.
var e2eFixtures = []struct {
	src     string
	driver  string // C driver content; "default" generates a plain driver
	private bool
}{
	{"arith", "default", false},
	{"else-if", "default", false},
	{"structs", "default", false},
	{"enums", "default", false},
	{"option", "default", false},
	{"strings", "default", false},
	{"generic", "default", false},
	{"domains", "default", true},
	{"maps", "default", true},
	{"buffer", "default", true},
	{"collections", "default", false},
	{"storage", "default", false},
	{"cleanup", "cleanup_driver.c", false},
	{"ffi", "ffi_driver.c", false},
}

// compileAndGenerate compiles source text and lowers it to C, requiring the
// lowered MIR to pass the verifier unchanged.
func compileAndGenerate(t *testing.T, src string) (string, *mir.Module) {
	return compileAndGenerateProfile(t, src, false)
}

// compileAndGeneratePrivate is compileAndGenerate under the private bootstrap
// profile.
func compileAndGeneratePrivate(t *testing.T, src string) (string, *mir.Module) {
	return compileAndGenerateProfile(t, src, true)
}

func compileAndGenerateProfile(t *testing.T, src string, bootstrapPrivate bool) (string, *mir.Module) {
	t.Helper()
	compile := Compile
	if bootstrapPrivate {
		compile = CompilePrivate
	}
	m, err := compile(src)
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

// buildRuntimeObject compiles the runtime once under the strict warning set
// and returns the object path, so the end-to-end fixtures link the runtime
// instead of recompiling the same source for every case. Call it from a
// top-level test and pass the path down: the object lives in that test's
// temporary directory, which outlives its parallel subtests. extra must carry
// the same flags the caller links with, because flags such as
// -DALDER_RUNTIME_TESTING select which runtime entry points exist.
func buildRuntimeObject(t *testing.T, cc string, extra ...string) string {
	t.Helper()
	object := filepath.Join(t.TempDir(), "alder.o")
	args := append([]string{
		"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
		"-Wshadow", "-Wconversion",
	}, extra...)
	args = append(args,
		"-I", filepath.Join("..", "runtime", "c"),
		"-c", filepath.Join("..", "runtime", "c", "alder.c"), "-o", object,
	)
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of the runtime: %v\n%s", err, out)
	}
	return object
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
			runtimeObject := buildRuntimeObject(t, cc)
			for _, e2e := range e2eFixtures {
				e2e := e2e
				t.Run(e2e.src, func(t *testing.T) {
					t.Parallel()
					src := readFixture(t, filepath.Join("testdata", "e2e", e2e.src+".al"))
					gen, m := compileAndGenerateProfile(t, src, e2e.private)
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
						genPath, driverPath, runtimeObject,
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
		runtimeObject := buildRuntimeObject(t, cc)
		genPath, driverPath := writeFiles(t, "checked_panic", gen, driver)
		exe := filepath.Join(t.TempDir(), "checked_panic.exe")
		args := []string{
			"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
			"-Wshadow", "-Wconversion",
			"-I", filepath.Dir(genPath),
			"-I", filepath.Join("..", "runtime", "c"),
			genPath, driverPath, runtimeObject,
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
		name    string
		src     string
		private bool
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
			name:    "map_capacity",
			private: true,
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
		{
			name:    "buffer_empty_get",
			private: true,
			src: `
fn read_empty(b: __s0_Buffer(U64)) -> I32 {
    let value = __s0_buffer_get(U64, b, 0)
    return 0
}
fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => 1
        Ok(empty) => read_empty(empty)
    }
}
`,
		},
		{
			name:    "buffer_empty_set",
			private: true,
			src: `
fn write_empty(b: __s0_Buffer(U64)) -> I32 {
    __s0_buffer_set(U64, b, 0, 7)
    return 0
}
fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => 1
        Ok(empty) => write_empty(empty)
    }
}
`,
		},
		{
			name:    "buffer_one_past_get",
			private: true,
			src: `
fn read_one_past(b: __s0_Buffer(U64)) -> I32 {
    let value = __s0_buffer_get(U64, b, 1)
    return 0
}
fn append_one(d: Domain, empty: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_append(U64, d, empty, 7) {
        Err(error) => 2
        Ok(one) => read_one_past(one)
    }
}
fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => 1
        Ok(empty) => append_one(d, empty)
    }
}
`,
		},
	}
	for _, cc := range findCCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			runtimeObject := buildRuntimeObject(t, cc)
			for _, tc := range tests {
				tc := tc
				t.Run(tc.name, func(t *testing.T) {
					t.Parallel()
					gen, m := compileAndGenerateProfile(t, tc.src, tc.private)
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
						genPath, driverPath, runtimeObject,
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

func TestBufferRecoverableAllocationFailuresAndLimit(t *testing.T) {
	src := `
fn check_old(b: __s0_Buffer(U64), i: U64) -> I32 {
    if __s0_buffer_len(U64, b) != 8 { return 21 }
    if i == 8 { return 20 }
    if __s0_buffer_get(U64, b, i) != i { return 22 }
    return check_old(b, i + 1)
}
fn check_grown(b: __s0_Buffer(U64), i: U64) -> I32 {
    if __s0_buffer_len(U64, b) != 9 { return 31 }
    if i == 9 { return 30 }
    if __s0_buffer_get(U64, b, i) != i { return 32 }
    return check_grown(b, i + 1)
}
fn classify_new(error: __s0_Error) -> I32 {
    return match error {
        OutOfMemory => 10
        Limit => 11
    }
}
fn classify_growth(error: __s0_Error, old: __s0_Buffer(U64)) -> I32 {
    return match error {
        OutOfMemory => check_old(old, 0)
        Limit => 23
    }
}
fn grow_once(d: Domain, full: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_append(U64, d, full, 8) {
        Err(error) => classify_growth(error, full)
        Ok(grown) => check_grown(grown, 0)
    }
}
fn fill(d: Domain, b: __s0_Buffer(U64), i: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    if i == 8 { return Ok(b) }
    let next = try __s0_buffer_append(U64, d, b, i)
    return fill(d, next, i + 1)
}
fn after_new(d: Domain, empty: __s0_Buffer(U64)) -> I32 {
    return match fill(d, empty, 0) {
        Err(error) => 12
        Ok(full) => grow_once(d, full)
    }
}
fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => classify_new(error)
        Ok(empty) => after_new(d, empty)
    }
}
`
	gen, m := compileAndGeneratePrivate(t, src)
	mainID, ok := m.Function("main")
	if !ok {
		t.Fatal("fixture has no main function")
	}
	newID, ok := m.Function("buffer.new.U64")
	if !ok {
		t.Fatal("fixture has no U64 buffer new helper")
	}
	appendID, ok := m.Function("buffer.append.U64")
	if !ok {
		t.Fatal("fixture has no U64 buffer append helper")
	}
	resultType := m.Functions[newID].Result
	if m.Functions[appendID].Result != resultType {
		t.Fatal("buffer new and append result types differ")
	}
	okVariant, ok := m.VariantIndex(resultType, "ok")
	if !ok {
		t.Fatal("buffer result has no ok variant")
	}
	errVariant, ok := m.VariantIndex(resultType, "err")
	if !ok {
		t.Fatal("buffer result has no err variant")
	}
	bufferType, ok := m.VariantPayload(resultType, okVariant)
	if !ok {
		t.Fatal("buffer result has no ok payload")
	}
	errorType, ok := m.VariantPayload(resultType, errVariant)
	if !ok {
		t.Fatal("buffer result has no err payload")
	}
	limitVariant, ok := m.VariantIndex(errorType, "Limit")
	if !ok {
		t.Fatal("bootstrap error has no Limit variant")
	}
	driver := fmt.Sprintf(`#include "gen.c"
#include <stdint.h>
int main(void) {
    AlderDomain root = {0};
    if (!alder_domain_init(&root, NULL)) { return 1; }

    alder_runtime_test_fail_domain_alloc_after((uint64_t)0);
    if (alder_fn_main_%d(&root) != (int32_t)10) { return 2; }

    alder_runtime_test_fail_domain_alloc_after((uint64_t)1);
    if (alder_fn_main_%d(&root) != (int32_t)20) { return 3; }

    alder_runtime_test_clear_domain_alloc_failure();
    if (alder_fn_main_%d(&root) != (int32_t)30) { return 4; }

    AlderTy%d initial = alder_fn_buffer_new_U64_%d(&root);
    if (initial.alder_tag != (uint32_t)%d) { return 5; }
    AlderTy%d malformed = initial.alder_u.alder_p%d;
    malformed.alder_f0.len = UINT64_MAX;
    malformed.alder_f1 = UINT64_MAX;
    alder_runtime_test_fail_domain_alloc_after((uint64_t)1);
    AlderTy%d limited = alder_fn_buffer_append_U64_%d(&root, malformed, (uint64_t)1);
    if (limited.alder_tag != (uint32_t)%d) { return 6; }
    if (limited.alder_u.alder_p%d.alder_tag != (uint32_t)%d) { return 7; }
    if (alder_domain_alloc(&root, (size_t)1, (size_t)1) == NULL) { return 8; }
    if (alder_domain_alloc(&root, (size_t)1, (size_t)1) != NULL) { return 9; }

    alder_runtime_test_clear_domain_alloc_failure();
    AlderDomain identity_root = {0};
    if (!alder_domain_init(&identity_root, NULL)) { return 10; }
    AlderDomainMark mark_before_identity_exhaustion = alder_domain_mark(&identity_root);
    AlderSegment *head_before_identity_exhaustion = identity_root.segments_head;
    AlderSegment *tail_before_identity_exhaustion = identity_root.segments_tail;
    size_t segments_before_identity_exhaustion = identity_root.segment_count;
    size_t live_before_identity_exhaustion = alder_runtime_live_allocations();
    alder_runtime_test_exhaust_segment_identities();
    if (alder_fn_main_%d(&identity_root) != (int32_t)10) { return 11; }
    AlderDomainMark mark_after_identity_exhaustion = alder_domain_mark(&identity_root);
    if (mark_after_identity_exhaustion.domain_serial != mark_before_identity_exhaustion.domain_serial ||
        mark_after_identity_exhaustion.reset_epoch != mark_before_identity_exhaustion.reset_epoch ||
        mark_after_identity_exhaustion.segment_serial != mark_before_identity_exhaustion.segment_serial ||
        mark_after_identity_exhaustion.offset != mark_before_identity_exhaustion.offset ||
        identity_root.segments_head != head_before_identity_exhaustion ||
        identity_root.segments_tail != tail_before_identity_exhaustion ||
        identity_root.segment_count != segments_before_identity_exhaustion) { return 12; }
    if (alder_runtime_live_allocations() != live_before_identity_exhaustion) { return 13; }
    if (alder_domain_alloc(&identity_root, (size_t)1, (size_t)1) != NULL) { return 14; }
    if (alder_runtime_live_allocations() != live_before_identity_exhaustion) { return 15; }

    alder_domain_destroy(&identity_root);
    alder_domain_destroy(&root);
    if (alder_runtime_live_allocations() != (size_t)0) { return 16; }
    return 0;
}
`, mainID, mainID, mainID, resultType, newID, okVariant,
		bufferType, okVariant, resultType, appendID, errVariant, errVariant, limitVariant, mainID)
	for _, cc := range findCCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			runtimeObject := buildRuntimeObject(t, cc, "-DALDER_RUNTIME_TESTING")
			genPath, driverPath := writeFiles(t, "buffer_failures", gen, driver)
			exe := filepath.Join(t.TempDir(), "buffer_failures.exe")
			args := []string{
				"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
				"-Wshadow", "-Wconversion", "-DALDER_RUNTIME_TESTING",
				"-I", filepath.Dir(genPath),
				"-I", filepath.Join("..", "runtime", "c"),
				genPath, driverPath, runtimeObject,
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
}

// TestE2ERoundTrip prints each fixture's MIR, re-parses it, and verifies the
// printed form is stable and valid.
func TestE2ERoundTrip(t *testing.T) {
	for _, e2e := range e2eFixtures {
		e2e := e2e
		t.Run(e2e.src, func(t *testing.T) {
			src := readFixture(t, filepath.Join("testdata", "e2e", e2e.src+".al"))
			compile := Compile
			if e2e.private {
				compile = CompilePrivate
			}
			m, err := compile(src)
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
