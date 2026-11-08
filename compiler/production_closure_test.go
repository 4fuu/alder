package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M7.5 closures in generic bodies: every instance of a generic body that
// contains a closure literal materializes its own thunk, so captures carry
// the instance's concrete types. The production driver pins two
// instantiations of each shape end to end through strict C11.

const m75GenericClosureProgram = `type Cell {
    v: U64
}

fn apply(T: type, f: fn(T) -> T, value: T) -> T {
    return f(value)
}

fn layer(T: type, seed: U64) -> U64 {
    let rebased = fn(x: U64) => x + seed
    return rebased(seed)
}

fn keep(T: type, value: T) -> T {
    let same = fn() -> T { return value }
    return same()
}

fn thread(T: type, value: T) -> T {
    let same = fn(x: T) => x
    return apply(T, same, value)
}

fn main() -> I32 {
    if layer(U64, 3) != 6 { return 1 }
    if layer(Cell, 4) != 8 { return 2 }
    if keep(U64, 7) != 7 { return 3 }
    let cell = keep(Cell, Cell(v: 5))
    if cell.v != 5 { return 4 }
    if thread(U64, 9) != 9 { return 5 }
    let other = thread(Cell, Cell(v: 11))
    if other.v != 11 { return 6 }
    return 0
}
`

// A capturing closure returned from its creating function must keep its
// environment alive for the caller. The scratch vector allocation between the
// return and the call would reuse a freed environment block and give a wrong
// answer, not just a sanitizer report, if the environment were destroyed with
// the creating frame.
const m75ClosureEscapeProgram = `fn make(seed: U64) -> fn(U64) -> U64 {
    let f = fn(x: U64) => x + seed
    return f
}
fn main() -> I32 {
    let f = make(4)
    var scratch = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        scratch.push(999)
        i = i + 1
    }
    if f(1) != 5 { return 1 }
    return 0
}
`

// Closures created per iteration carry distinct snapshots. Reading them back
// through a second loop carries function values across a backedge, which the
// phase-6 loop rule accepts because their environments are immutable shared
// records whose domain outlives the loop.
const m75LoopClosureProgram = `fn identity(x: U64) -> U64 { return x }
fn main() -> I32 {
    var fns = Vec.new(fn(U64) -> U64)
    var i: U64 = 0
    while i < 3 {
        let bump = fn(x: U64) => x + i
        fns.push(bump)
        i = i + 1
    }
    var total: U64 = 0
    var k: U64 = 0
    while k < fns.len() {
        let found = fns.get(k)
        let f = match found {
            Some(g) => g
            None => identity
        }
        total = total + f(10)
        k = k + 1
    }
    if total != 33 { return 1 }
    return 0
}
`

// A closure that escapes through one, two, and three returns stays valid
// because every return retains its environment into the caller's domain. An
// intervening vector allocation between each return and its call reuses a
// freed environment block, so a missing retain gives a wrong answer and not
// only a sanitizer report.
const m75RetainChainProgram = `fn inner(seed: U64) -> fn(U64) -> U64 {
    let f = fn(x: U64) => x + seed
    return f
}
fn middle(seed: U64) -> fn(U64) -> U64 {
    let g = inner(seed)
    var pad = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad.push(999)
        i = i + 1
    }
    return g
}
fn outer(seed: U64) -> fn(U64) -> U64 {
    let h = middle(seed)
    var pad = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad.push(777)
        i = i + 1
    }
    return h
}
fn main() -> I32 {
    let a = inner(4)
    var pad_a = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad_a.push(1)
        i = i + 1
    }
    if a(1) != 5 { return 1 }
    let b = middle(5)
    var pad_b = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_b.push(2)
        i = i + 1
    }
    if b(1) != 6 { return 2 }
    let c = outer(6)
    var pad_c = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_c.push(3)
        i = i + 1
    }
    if c(1) != 7 { return 3 }
    return 0
}
`

// A closure carried in a record and in a vector, and a named function value
// (retain NULL), each returned through two levels. The copy helpers retain
// every function-valued field and element, and the named value's hook rewrites
// its captured domain to the destination domain.
const m75RetainContainerProgram = `type Holder {
    f: fn(U64) -> U64
}
fn make_holder(seed: U64) -> Holder {
    let f = fn(x: U64) => x + seed
    return Holder(f: f)
}
fn holder_level1(seed: U64) -> Holder {
    let h = make_holder(seed)
    return h
}
fn holder_level2(seed: U64) -> Holder {
    let h = holder_level1(seed)
    return h
}
fn make_vec(seed: U64) -> Vec(fn(U64) -> U64) {
    var v = Vec.new(fn(U64) -> U64)
    v.push(fn(x: U64) => x + seed)
    return v
}
fn vec_level1(seed: U64) -> Vec(fn(U64) -> U64) {
    let v = make_vec(seed)
    return v
}
fn vec_level2(seed: U64) -> Vec(fn(U64) -> U64) {
    let v = vec_level1(seed)
    return v
}
fn plus_one(x: U64) -> U64 { return x + 1 }
fn named() -> fn(U64) -> U64 {
    let f = plus_one
    return f
}
fn named_level1() -> fn(U64) -> U64 {
    let f = named()
    return f
}
fn named_level2() -> fn(U64) -> U64 {
    let f = named_level1()
    return f
}
fn main() -> I32 {
    let h = holder_level2(5)
    var pad_a = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad_a.push(999)
        i = i + 1
    }
    let hf = h.f
    if hf(2) != 7 { return 1 }
    let v = vec_level2(6)
    var pad_b = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_b.push(888)
        i = i + 1
    }
    let found = v.get(0)
    let g = match found {
        Some(x) => x
        None => plus_one
    }
    if g(2) != 8 { return 2 }
    let n = named_level2()
    var pad_c = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_c.push(777)
        i = i + 1
    }
    if n(2) != 3 { return 3 }
    return 0
}
`

func TestM75ClosureProductionQualification(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)

	for _, program := range []struct {
		name, source string
	}{
		{"m75-generic-closures", m75GenericClosureProgram},
		{"m75-closure-escape", m75ClosureEscapeProgram},
		{"m75-loop-closures", m75LoopClosureProgram},
		{"m75-retain-chains", m75RetainChainProgram},
		{"m75-retain-containers", m75RetainContainerProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name + ".al": program.source}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name+".al")
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 5\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name+".al")
			if repeat != mirText {
				t.Fatalf("%s MIR changed across processes", program.name)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name+".al")
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			if strings.Contains(cResult.stdout, "__s0_") {
				t.Fatalf("%s generated C exposes bootstrap names", program.name)
			}
			compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
		})
	}
}

// closureSanitizersSupported probes whether the host toolchain can build and
// run ASan/UBSan binaries.
func closureSanitizersSupported(t *testing.T, cc string) bool {
	t.Helper()
	dir := t.TempDir()
	probe := filepath.Join(dir, "probe.c")
	if err := os.WriteFile(probe, []byte("int main(void) { return 0; }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(dir, "probe.exe")
	if out, err := exec.Command(cc, "-fsanitize=address,undefined", probe, "-o", exe).CombinedOutput(); err != nil {
		t.Logf("sanitizer build unsupported on this host: %v\n%s", err, out)
		return false
	}
	if out, err := exec.Command(exe).CombinedOutput(); err != nil {
		t.Logf("sanitizer run unsupported on this host: %v\n%s", err, out)
		return false
	}
	return true
}

// TestM75ClosureProductionSanitizers reruns the closure programs under
// ASan/UBSan when the host toolchain supports them. A dangling closure
// environment is a use-after-free that strict C11 alone cannot see.
func TestM75ClosureProductionSanitizers(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	if !closureSanitizersSupported(t, cc) {
		t.Skip("ASan/UBSan not supported by this host toolchain")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	sanitizer := []string{"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer"}
	runtimeObject := filepath.Join(t.TempDir(), "alder-san.o")
	runtimeArgs := append(append([]string{}, strictC11Flags()...), sanitizer...)
	runtimeArgs = append(runtimeArgs, "-I", filepath.Join(root, "runtime", "c"),
		"-c", filepath.Join(root, "runtime", "c", "alder.c"), "-o", runtimeObject)
	if out, err := exec.Command(cc, runtimeArgs...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized runtime compile: %v\n%s", err, out)
	}

	const driverText = `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	for _, program := range []struct {
		name, source string
	}{
		{"m75-generic-closures", m75GenericClosureProgram},
		{"m75-closure-escape", m75ClosureEscapeProgram},
		{"m75-loop-closures", m75LoopClosureProgram},
		{"m75-retain-chains", m75RetainChainProgram},
		{"m75-retain-containers", m75RetainContainerProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name + ".al": program.source}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name+".al")
			if cResult.status != 0 || cResult.stderr != "" {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			dir := t.TempDir()
			cfile := filepath.Join(dir, "program.c")
			driver := filepath.Join(dir, "driver.c")
			binary := filepath.Join(dir, "program")
			if err := os.WriteFile(cfile, []byte(cResult.stdout), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(driver, []byte(driverText), 0o644); err != nil {
				t.Fatal(err)
			}
			args := append(append([]string{}, strictC11Flags()...), sanitizer...)
			args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"),
				cfile, driver, runtimeObject, "-o", binary)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("%s sanitized generated C compile: %v\n%s", program.name, err, out)
			}
			cmd := exec.Command(binary)
			cmd.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=0")
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("%s sanitized run: %v\n%s", program.name, err, out)
			}
		})
	}
}
