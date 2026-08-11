package cgen

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// runFixtures pairs each behavior fixture with its C driver. The driver
// includes the generated translation unit ("gen.c"), so static functions and
// type definitions are visible to it.
var runFixtures = []struct {
	mir    string
	driver string
}{
	{"checked", "checked_driver.c"},
	{"loop", "loop_driver.c"},
	{"enum", "enum_driver.c"},
	{"domain", "domain_driver.c"},
	{"cleanup", "cleanup_driver.c"},
	{"table", "table_driver.c"},
	{"cfg", "cfg_driver.c"},
}

// runArgs builds the strict compile command for a behavior fixture: the
// generated file, the driver, and the runtime.
func runArgs(gen, driver string) []string {
	return []string{
		"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
		"-Wshadow", "-Wconversion",
		"-I", filepath.Dir(gen),
		"-I", filepath.Join("..", "runtime", "c"),
		gen, driver, filepath.Join("..", "runtime", "c", "aster.c"),
	}
}

// generateRun writes the generated C of a run fixture and returns its path.
func generateRun(t *testing.T, name string) string {
	t.Helper()
	path := filepath.Join("testdata", "run", name+".mir")
	if name == "cfg" {
		path = goldenMirPath(name) // cfg is a shared MIR golden
	}
	dir := t.TempDir()
	gen := filepath.Join(dir, "gen.c")
	if err := os.WriteFile(gen, []byte(generatePath(t, path)), 0o644); err != nil {
		t.Fatal(err)
	}
	return gen
}

// TestRunFixtures compiles each behavior fixture with its driver under the
// strict warning set and runs it, requiring exit code 0.
func TestRunFixtures(t *testing.T) {
	cc := findCompiler(t)
	for _, rf := range runFixtures {
		rf := rf
		t.Run(rf.mir, func(t *testing.T) {
			gen := generateRun(t, rf.mir)
			exe := filepath.Join(t.TempDir(), rf.mir+".exe")
			args := runArgs(gen, filepath.Join("testdata", "run", rf.driver))
			args = append(args, "-o", exe)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("compile %s failed: %v\n%s", rf.mir, err, out)
			}
			if out, err := exec.Command(exe).CombinedOutput(); err != nil {
				t.Fatalf("run %s failed: %v\n%s", rf.mir, err, out)
			}
		})
	}
}

// TestRunFixturesSanitizers reruns the behavior fixtures under ASan/UBSan
// when the host toolchain supports them, and skips otherwise.
func TestRunFixturesSanitizers(t *testing.T) {
	cc := findCompiler(t)
	if !sanitizersSupported(t, cc) {
		t.Skip("ASan/UBSan not supported by this host toolchain")
	}
	for _, rf := range runFixtures {
		rf := rf
		t.Run(rf.mir, func(t *testing.T) {
			gen := generateRun(t, rf.mir)
			exe := filepath.Join(t.TempDir(), rf.mir+".exe")
			args := runArgs(gen, filepath.Join("testdata", "run", rf.driver))
			args = append(args,
				"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer",
				"-o", exe)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("sanitizer compile %s failed: %v\n%s", rf.mir, err, out)
			}
			if out, err := exec.Command(exe).CombinedOutput(); err != nil {
				t.Fatalf("sanitizer run %s failed: %v\n%s", rf.mir, err, out)
			}
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
