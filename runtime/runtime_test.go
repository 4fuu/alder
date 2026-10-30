// Package runtime tests the minimal Alder C11 runtime by compiling and
// running strict-warning C11 test programs with the system C compiler, and
// by running them under ASan/UBSan when the host toolchain supports it.
package runtime

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// strictFlags is the canonical strict C11 warning set for handwritten runtime
// and generated code. Keep synchronized with AGENTS.md and CONTRIBUTING.md.
var strictFlags = []string{
	"-std=c11",
	"-Wall", "-Wextra", "-Werror", "-pedantic",
	"-Wshadow", "-Wconversion",
}

// testPrograms are the runtime behavior test programs, one per runtime area.
// Each program is added to this list as its runtime section lands.
var testPrograms = []string{"domains", "arithmetic", "bounds", "cleanup", "table"}

func findCompiler(t *testing.T) string {
	t.Helper()
	for _, name := range []string{"gcc", "cc", "clang"} {
		if path, err := exec.LookPath(name); err == nil {
			t.Logf("C compiler: %s", path)
			return path
		}
	}
	t.Skip("no C compiler found (gcc, cc, or clang); runtime tests skipped")
	return ""
}

// buildRuntimeObject compiles the runtime once under the strict warning set
// and returns the object path, so the behavior fixtures link the runtime
// instead of recompiling the same source for every case. Call it from a
// top-level test and pass the path down: the object lives in that test's
// temporary directory, which outlives its parallel subtests. extra must carry
// the same flags the caller links with, so a sanitizer run links a sanitized
// runtime rather than silently dropping instrumentation.
func buildRuntimeObject(t *testing.T, cc string, extra ...string) string {
	t.Helper()
	object := filepath.Join(t.TempDir(), "alder.o")
	args := append(append([]string{}, strictFlags...), extra...)
	args = append(args, "-I", filepath.Join("c"), "-c", filepath.Join("c", "alder.c"), "-o", object)
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of the runtime: %v\n%s", err, out)
	}
	return object
}

func compileAndRun(t *testing.T, cc, object, name string, extra ...string) {
	t.Helper()
	dir := t.TempDir()
	exe := filepath.Join(dir, name+".exe")
	args := []string{}
	args = append(args, strictFlags...)
	args = append(args, extra...)
	args = append(args, "-I", filepath.Join("c"),
		filepath.Join("testdata", name+".c"),
		object, "-o", exe)
	out, err := exec.Command(cc, args...).CombinedOutput()
	if err != nil {
		t.Fatalf("compile %s.c failed: %v\n%s", name, err, out)
	}
	run, err := exec.Command(exe).CombinedOutput()
	if err != nil {
		t.Fatalf("run %s failed: %v\n%s", name, err, run)
	}
	if len(run) > 0 {
		t.Logf("%s output: %s", name, run)
	}
}

// TestRuntimePanic checks that alder_runtime_panic prints a message and exits
// nonzero (the harness normally requires exit code 0).
func TestRuntimePanic(t *testing.T) {
	cc := findCompiler(t)
	dir := t.TempDir()
	exe := filepath.Join(dir, "panic.exe")
	args := []string{}
	args = append(args, strictFlags...)
	args = append(args, "-I", filepath.Join("c"),
		filepath.Join("testdata", "panic.c"),
		filepath.Join("c", "alder.c"), "-o", exe)
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile panic.c failed: %v\n%s", err, out)
	}
	out, err := exec.Command(exe).CombinedOutput()
	if err == nil {
		t.Fatal("panic program exited zero")
	}
	if !strings.Contains(string(out), "intentional panic") {
		t.Fatalf("panic message missing from output: %s", out)
	}
}

// TestRuntimePrograms compiles and runs every behavior test under the strict
// warning set.
func TestRuntimePrograms(t *testing.T) {
	cc := findCompiler(t)
	object := buildRuntimeObject(t, cc)
	for _, name := range testPrograms {
		name := name
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			compileAndRun(t, cc, object, name)
		})
	}
}

// sanitizersSupported probes whether the host toolchain can build and run
// ASan/UBSan binaries.
func sanitizersSupported(t *testing.T, cc string) bool {
	t.Helper()
	dir := t.TempDir()
	probe := filepath.Join(dir, "probe.c")
	if err := os.WriteFile(probe, []byte("int main(void) { return 0; }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(dir, "probe.exe")
	args := []string{"-fsanitize=address,undefined", probe, "-o", exe}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Logf("sanitizer build unsupported on this host: %v\n%s", err, out)
		return false
	}
	if out, err := exec.Command(exe).CombinedOutput(); err != nil {
		t.Logf("sanitizer run unsupported on this host: %v\n%s", err, out)
		return false
	}
	return true
}

// TestRuntimeSanitizers reruns every behavior test under ASan/UBSan when the
// host toolchain supports them, and skips otherwise.
func TestRuntimeSanitizers(t *testing.T) {
	cc := findCompiler(t)
	if !sanitizersSupported(t, cc) {
		t.Skip("ASan/UBSan not supported by this host toolchain")
	}
	object := buildRuntimeObject(t, cc, "-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer")
	for _, name := range testPrograms {
		name := name
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			compileAndRun(t, cc, object, name,
				"-fsanitize=address,undefined",
				"-g", "-fno-omit-frame-pointer")
		})
	}
}
