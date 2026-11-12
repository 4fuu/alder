package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 borrowed-field storage restriction. A `mut self` receiver or a `mut`
// parameter borrows the caller's storage, but a Vec/String/Bytes/collection
// header stored through a field is allocated in the current call's domain.
// Diagnostic 333 rejects that shape until per-mut-parameter provenance lands.
// Literals, empty collections, None, and aggregates of those stay accepted.

func borrowedStorageSafeProgram() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"safe\"\nversion = \"0.1.0\"\n[targets.safe]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module safe.main

type Inner {
    items: Vec(U8)
}

type Bag {
    inner: Inner
    label: String
    count: U64
    opt: Option(Vec(U8))
}

impl Bag {
    fn new() -> Bag {
        return Bag(inner: Inner(items: Vec.new(U8)), label: "empty", count: 0, opt: None)
    }

    fn reset(mut self) -> Unit {
        self.inner = Inner(items: Vec.new(U8))
        self.label = "ready"
        self.count = 0
        self.opt = None
        return ()
    }

    fn set_some(mut self) -> Unit {
        self.opt = Some(Vec.new(U8))
        return ()
    }

    fn scalar(mut self) -> Unit {
        self.count = self.count + 1
        return ()
    }

    fn add(self, byte: U8) -> Bag {
        var items = self.inner.items
        items.push(byte)
        var opt = self.opt
        return Bag(inner: Inner(items: items), label: self.label, count: self.count, opt: opt)
    }

    fn first(self) -> U8 {
        if self.inner.items.len() == 0 { return 0 }
        return self.inner.items[0]
    }
}

fn main() -> I32 {
    var b = Bag.new()
    b.reset()
    if b.label.len() != 5 { return 1 }
    if b.inner.items.len() != 0 { return 2 }
    b.set_some()
    b.scalar()
    if b.count != 1 { return 3 }
    b = b.add(66)
    if b.inner.items.len() != 1 { return 4 }
    if b.first() != 66 { return 5 }
    return 0
}
`,
	}
}

const borrowedStoragePushSource = `module reject.main

type Buf {
    data: Vec(U8)
}

impl Buf {
    fn new() -> Buf { return Buf(data: Vec.new(U8)) }
    fn add(mut self, byte: U8) -> Unit {
        self.data.push(byte)
        return ()
    }
}

fn main() -> I32 {
    var b = Buf.new()
    b.add(65)
    return 0
}
`

const borrowedStorageAssignLocalSource = `module reject.main

type Bag {
    data: Vec(U8)
}

impl Bag {
    fn new() -> Bag { return Bag(data: Vec.new(U8)) }
    fn replace(mut self) -> Unit {
        var next: Vec(U8) = Vec.new(U8)
        next.push(1)
        self.data = next
        return ()
    }
}

fn main() -> I32 {
    var b = Bag.new()
    b.replace()
    return 0
}
`

const borrowedStorageMapInsertSource = `module reject.main

type Registry {
    counts: Map(U64, U64)
}

impl Registry {
    fn new() -> Registry { return Registry(counts: Map.new(U64, U64)) }
    fn add(mut self) -> Unit {
        self.counts.insert(1, 2)
        return ()
    }
}

fn main() -> I32 {
    var r = Registry.new()
    r.add()
    return 0
}
`

const borrowedStorageSetInsertSource = `module reject.main

type Registry {
    names: Set(U64)
}

impl Registry {
    fn new() -> Registry { return Registry(names: Set.new(U64)) }
    fn add(mut self) -> Unit {
        self.names.insert(1)
        return ()
    }
}

fn main() -> I32 {
    var r = Registry.new()
    r.add()
    return 0
}
`

const borrowedStorageFieldCopySource = `module reject.main

type Bag {
    data: Vec(U8)
    other: Vec(U8)
}

impl Bag {
    fn new() -> Bag { return Bag(data: Vec.new(U8), other: Vec.new(U8)) }
    fn copy_other(mut self) -> Unit {
        self.data = self.other
        return ()
    }
}

fn main() -> I32 {
    var b = Bag.new()
    b.copy_other()
    return 0
}
`

func TestM8BorrowedFieldStorageQualification(t *testing.T) {
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
	env := sysrootEnv(filepath.Join(root, "sysroot"))

	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, borrowedStorageSafeProgram(), "run")
	if run != (productionResult{}) {
		t.Fatalf("safe borrowed-field behavior run failed: %+v", run)
	}

	generated := filepath.Join(dir, "build", "x86_64-unknown-linux-gnu", "debug", "safe", "safe.c")
	source, err := os.ReadFile(generated)
	if err != nil {
		t.Fatalf("read generated safe program: %v", err)
	}
	runSanitizedGeneratedProgram(t, cc, root, string(source))

	rejections := []struct {
		name, source string
	}{
		{"mut-self-push", borrowedStoragePushSource},
		{"assign-local-vector", borrowedStorageAssignLocalSource},
		{"map-insert-field", borrowedStorageMapInsertSource},
		{"set-insert-field", borrowedStorageSetInsertSource},
		{"field-read-assignment", borrowedStorageFieldCopySource},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run(rejection.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": rejection.source}, "check", "reject.al")
			if result.status != 1 || result.stdout != "" {
				t.Fatalf("%s: result: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, "[SEM0001]") || !strings.Contains(result.stderr, "functional builder convention") {
				t.Fatalf("%s: diagnostic does not name the borrowed-field rule: %q", rejection.name, result.stderr)
			}
		})
	}
}

func runSanitizedProject(t *testing.T, cc, root, dir, target string) {
	t.Helper()
	generated := filepath.Join(dir, "build", "x86_64-unknown-linux-gnu", "debug", target, target+".c")
	source, err := os.ReadFile(generated)
	if err != nil {
		t.Fatalf("read generated %s program: %v", target, err)
	}
	runSanitizedGeneratedProgram(t, cc, root, string(source))
}

func runSanitizedGeneratedProgram(t *testing.T, cc, root, generated string) {
	t.Helper()
	dir := t.TempDir()
	cfile := filepath.Join(dir, "program.c")
	driver := filepath.Join(dir, "driver.c")
	runtimeObject := filepath.Join(dir, "alder-asan.o")
	exe := filepath.Join(dir, "program")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	const driverText = `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	if err := os.WriteFile(driver, []byte(driverText), 0o644); err != nil {
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
		cfile, driver, runtimeObject, "-o", exe)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized generated compile: %v\n%s", err, output)
	}
	command := exec.Command(exe)
	command.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=0")
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("sanitized safe program run: %v\n%s", err, output)
	}
}
