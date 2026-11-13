package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Vec.pop is the total move-out primitive: a copyable element is returned by
// value and leaves the vector one shorter; an affine element transfers out and
// is not cleaned again by the remaining vector drain.
func TestVecPopProduction(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)

	t.Run("copyable", func(t *testing.T) {
		files := map[string]string{
			"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
			"src/main.al": `module hello.main

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    values.push(3)
    values[0] = 42
    if values[0] != 42 { return 10 }
    match values.pop() {
        Some(value) => { if value != 3 { return 1 } }
        None => { return 2 }
    }
    if values.len() != 2 { return 3 }
    match values.pop() {
        Some(value) => { if value != 2 { return 4 } }
        None => { return 5 }
    }
    match values.pop() {
        Some(value) => { if value != 42 { return 6 } }
        None => { return 7 }
    }
    if values.len() != 0 { return 8 }
    match values.pop() {
        Some(_) => { return 9 }
        None => {}
    }
    return 0
}
`,
		}
		result := runProductionCompiler(t, exe, files, "run")
		if result != (productionResult{}) {
			t.Fatalf("copyable Vec.pop failed: %+v", result)
		}
	})

	t.Run("affine-cleanup-once", func(t *testing.T) {
		source := `import c counter: fn(U64) -> Unit
type Res {
    n: U64
}
impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}
fn make(n: U64) -> Res { return Res(n: n) }
fn main() -> I32 {
    let values = Vec.new(Res)
    values.push(make(10))
    values.push(make(20))
    values.push(make(30))
    var ok = true
    match values.pop() {
        Some(owner) => { using held = owner }
        None => { ok = false }
    }
    if values.len() != 2 { ok = false }
    match values.pop() {
        Some(owner) => { using held = owner }
        None => { ok = false }
    }
    using rest = values
    if ok { return 0 }
    return 4
}
`
		files := map[string]string{"m75-vec-pop.al": source}
		generated := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=c", "m75-vec-pop.al")
		if generated.status != 0 || generated.stderr != "" {
			t.Fatalf("affine Vec.pop compile: %+v stderr=%s", generated, generated.stderr)
		}
		const driver = `#include "alder_host.h"
#include <stdint.h>
static uint64_t g_count = 0;
static uint64_t g_sum = 0;
void counter(uint64_t v) { g_count++; g_sum += v; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (g_count != 3) { return 97; }
    if (g_sum != 60) { return 98; }
    return result;
}
`
		runtimeObject := buildRuntimeObject(t, cc, root)
		compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, generated.stdout, driver, 0)
		runSanitizedPopArtifact(t, cc, root, generated.stdout, driver)
	})

	t.Run("affine-field-place", func(t *testing.T) {
		// A pop through a field of a mut-self receiver must shorten the
		// caller-owned vector. Reading the receiver as a value would write a
		// header pointing into the method frame's temporary domain.
		source := `import c counter: fn(U64) -> Unit
type Res { n: U64 }
impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}
fn make(n: U64) -> Res { return Res(n: n) }
type Boxed { values: Vec(Res) }
impl Boxed {
    fn pop(mut self) -> Option(Res) { return self.values.pop() }
}
impl Cleanup for Boxed {
    fn cleanup(take self) -> Unit {
        using values = self.values
        return
    }
}
fn main() -> I32 {
    let values = Vec.new(Res)
    values.push(make(1))
    values.push(make(2))
    let boxed = Boxed(values: values)
    var ok = true
    match boxed.pop() {
        Some(owner) => { using item = owner }
        None => { ok = false }
    }
    using rest = boxed
    if ok { return 0 }
    return 1
}
`
		files := map[string]string{"m75-vec-pop-field.al": source}
		generated := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=c", "m75-vec-pop-field.al")
		if generated.status != 0 || generated.stderr != "" {
			t.Fatalf("field Vec.pop compile: %+v stderr=%s", generated, generated.stderr)
		}
		const driver = `#include "alder_host.h"
#include <stdint.h>
static uint64_t g_count = 0;
static uint64_t g_sum = 0;
void counter(uint64_t v) { g_count++; g_sum += v; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (g_count != 2) { return 97; }
    if (g_sum != 3) { return 98; }
    return result;
}
`
		runtimeObject := buildRuntimeObject(t, cc, root)
		compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, generated.stdout, driver, 0)
		runSanitizedPopArtifact(t, cc, root, generated.stdout, driver)
	})

	t.Run("registered-affine-rejected", func(t *testing.T) {
		source := `type Res { n: U64 }
impl Cleanup for Res { fn cleanup(take self) -> Unit { return } }
fn main() -> I32 {
    using values = Vec.new(Res)
    values.pop()
    return 0
}
`
		result := runProductionCompiler(t, exe, map[string]string{"reject.al": source}, "check", "reject.al")
		if result.status == 0 || !strings.Contains(result.stderr, "a registered vector owner is immutable") {
			t.Fatalf("registered affine Vec.pop: %+v stderr=%s", result, result.stderr)
		}
	})
}

// runSanitizedPopArtifact rebuilds the generated program and the runtime under
// ASan/UBSan. The counter driver still checks exactly-once cleanup; the
// sanitizers catch a double free or use-after-free that the counter cannot.
func runSanitizedPopArtifact(t *testing.T, cc, root, generated, driver string) {
	t.Helper()
	dir := t.TempDir()
	cfile := filepath.Join(dir, "program.c")
	driverFile := filepath.Join(dir, "driver.c")
	runtimeObject := filepath.Join(dir, "alder-asan.o")
	exe := filepath.Join(dir, "program")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(driverFile, []byte(driver), 0o644); err != nil {
		t.Fatal(err)
	}
	sanitizer := []string{"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer"}
	runtimeArgs := append(append([]string{}, strictC11Flags()...), sanitizer...)
	runtimeArgs = append(runtimeArgs, "-I", filepath.Join(root, "runtime", "c"),
		"-c", filepath.Join(root, "runtime", "c", "alder.c"), "-o", runtimeObject)
	if output, err := exec.Command(cc, runtimeArgs...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized runtime compile: %v\n%s", err, output)
	}
	args := append(append([]string{}, strictC11Flags()...), sanitizer...)
	args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"),
		cfile, driverFile, runtimeObject, "-o", exe)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized generated compile: %v\n%s", err, output)
	}
	command := exec.Command(exe)
	command.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=0")
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("sanitized Vec.pop run: %v\n%s", err, output)
	}
}
