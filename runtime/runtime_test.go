// Package runtime tests the minimal Aster C11 runtime by compiling and
// running strict-warning C11 test programs with the system C compiler, and
// by running them under ASan/UBSan when the host toolchain supports it.
package runtime

import (
	"os"
	"os/exec"
	"path/filepath"
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
var testPrograms = []string{"domains", "arithmetic", "bounds", "cleanup"}

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

// compileAndRun builds one test program with the strict warning set and runs
// it, failing the test on any compiler warning, build error, or nonzero exit.
func compileAndRun(t *testing.T, cc, name string, extra ...string) {
	t.Helper()
	dir := t.TempDir()
	exe := filepath.Join(dir, name+".exe")
	args := []string{}
	args = append(args, strictFlags...)
	args = append(args, extra...)
	args = append(args, "-I", filepath.Join("c"),
		filepath.Join("testdata", name+".c"),
		filepath.Join("c", "aster.c"), "-o", exe)
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

// TestRuntimePrograms compiles and runs every behavior test under the strict
// warning set.
func TestRuntimePrograms(t *testing.T) {
	cc := findCompiler(t)
	for _, name := range testPrograms {
		name := name
		t.Run(name, func(t *testing.T) {
			compileAndRun(t, cc, name)
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
	for _, name := range testPrograms {
		name := name
		t.Run(name, func(t *testing.T) {
			compileAndRun(t, cc, name,
				"-fsanitize=address,undefined",
				"-g", "-fno-omit-frame-pointer")
		})
	}
}
