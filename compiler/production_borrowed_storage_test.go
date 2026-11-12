package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// Borrowed-place provenance: growth and relocatable replacement through a
// `mut self` receiver or `mut` parameter allocate in the domain that owns the
// caller's place. These shapes were rejected by the interim diagnostic 333;
// every one now compiles and runs clean under ASan/UBSan.

const borrowedStoragePushSource = `type Buf {
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
    if b.data.len() != 1 { return 1 }
    if b.data[0] != 65 { return 2 }
    return 0
}
`

const borrowedStorageAssignLocalSource = `type Bag {
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
    if b.data.len() != 1 { return 1 }
    if b.data[0] != 1 { return 2 }
    return 0
}
`

const borrowedStorageMapInsertSource = `type Registry {
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
    if r.counts.len() != 1 { return 1 }
    return 0
}
`

const borrowedStorageSetInsertSource = `type Registry {
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
    if r.names.len() != 1 { return 1 }
    return 0
}
`

const borrowedStorageFieldCopySource = `type Bag {
    data: Vec(U8)
    other: Vec(U8)
}

impl Bag {
    fn new() -> Bag { return Bag(data: Vec.new(U8), other: Vec.new(U8)) }
    fn copy_other(mut self) -> Unit {
        self.data = self.other
        self.data.push(9)
        return ()
    }
}

fn main() -> I32 {
    var b = Bag.new()
    b.copy_other()
    if b.data.len() != 1 { return 1 }
    if b.other.len() != 0 { return 2 }
    return 0
}
`

// A borrowed owner follows a `mut` parameter through delegation: the inner
// call receives the outer call's owner domain, not the forwarding frame.
const borrowedStorageDelegateSource = `type Buf {
    data: Vec(U8)
}

impl Cleanup for Buf {
    fn cleanup(take self) -> Unit { return () }
}

fn append(mut buf: Buf, byte: U8) -> Unit {
    buf.data.push(byte)
    return ()
}

fn forward(mut buf: Buf, byte: U8) -> Unit {
    append(buf, byte)
    return ()
}

fn main() -> I32 {
    using b = Buf(data: Vec.from_array(U8, [1]))
    forward(b, 65)
    if b.data.len() != 2 { return 1 }
    if b.data[1] != 65 { return 2 }
    return 0
}
`

// A local receives vectors from a branch, then grows the joined value. The
// local owns its frame domain, so the growth is retained there and the later
// store into the borrowed field copies into the caller's domain.
const borrowedStorageJoinSource = `type Bag {
    data: Vec(U8)
}

impl Bag {
    fn new() -> Bag { return Bag(data: Vec.new(U8)) }
    fn choose(mut self, left: Bool, a: Vec(U8), b: Vec(U8)) -> Unit {
        var next = Vec.new(U8)
        if left { next = a } else { next = b }
        next.push(7)
        self.data = next
        return ()
    }
}

fn main() -> I32 {
    var bag = Bag.new()
    var a = Vec.new(U8)
    a.push(1)
    var b = Vec.new(U8)
    b.push(2)
    bag.choose(true, a, b)
    if bag.data.len() != 2 { return 1 }
    if bag.data[0] != 1 { return 2 }
    if bag.data[1] != 7 { return 3 }
    return 0
}
`

// A `take` parameter owns its value in the callee frame. Growing it there and
// returning it goes through the ordinary caller-result copy.
const borrowedStorageTakeSource = `type Holder {
    data: Vec(U8)
}

impl Cleanup for Holder {
    fn cleanup(take self) -> Unit { return () }
}

fn grow(take holder: Holder) -> Holder {
    holder.data.push(7)
    return holder
}

fn main() -> I32 {
    let holder = Holder(data: Vec.from_array(U8, [1]))
    using grown = grow(holder)
    if grown.data.len() != 2 { return 1 }
    if grown.data[0] != 1 { return 2 }
    if grown.data[1] != 7 { return 3 }
    return 0
}
`

func TestM8BorrowedFieldStorageQualification(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	programs := []struct {
		name, source string
	}{
		{"mut-self-push", borrowedStoragePushSource},
		{"assign-local-vector", borrowedStorageAssignLocalSource},
		{"map-insert-field", borrowedStorageMapInsertSource},
		{"set-insert-field", borrowedStorageSetInsertSource},
		{"field-read-assignment", borrowedStorageFieldCopySource},
		{"branch-join-local", borrowedStorageJoinSource},
		{"take-parameter-return", borrowedStorageTakeSource},
		{"delegated-mut-parameter", borrowedStorageDelegateSource},
	}
	for _, program := range programs {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompiler(t, exe, map[string]string{"accept.al": program.source}, "compile", "--emit=c", "accept.al")
			if result.status != 0 || result.stderr != "" {
				t.Fatalf("%s: result: %+v", program.name, result)
			}
			runSanitizedGeneratedProgram(t, cc, root, result.stdout)
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
		"-I", filepath.Join(root, "sysroot"), cfile, driver, runtimeObject, "-o", exe)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized generated compile: %v\n%s", err, output)
	}
	command := exec.Command(exe)
	command.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=0")
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("sanitized safe program run: %v\n%s", err, output)
	}
}
