package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// std.collection v1 amendment: Deque and BinaryHeap. The fixture compiles the
// committed sysroot source as a second input, so the test sees the same module
// body the installed sysroot ships while still linking a C counter around the
// affine deque.
func TestProductionCollectionDequeHeap(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	collection, err := os.ReadFile(filepath.Join(root, "sysroot", "std", "collection.al"))
	if err != nil {
		t.Fatal(err)
	}
	runtimeObject := buildRuntimeObject(t, cc, root)

	t.Run("copyable", func(t *testing.T) {
		files := map[string]string{
			"std/collection.al": string(collection),
			"main.al":           collectionCopyableProgram,
		}
		generated := runProductionCompiler(t, exe, files, "compile", "--emit=c", "main.al", "std/collection.al")
		if generated.status != 0 || generated.stderr != "" {
			t.Fatalf("copyable Deque/heap compile: %+v stderr=%s", generated, generated.stderr)
		}
		compileAndRunProductionArtifact(t, cc, root, runtimeObject, generated.stdout, 0)
	})

	t.Run("affine-cleanup-once", func(t *testing.T) {
		files := map[string]string{
			"std/collection.al": string(collection),
			"main.al":           collectionAffineProgram,
		}
		generated := runProductionCompiler(t, exe, files, "compile", "--bootstrap-private", "--emit=c", "main.al", "std/collection.al")
		if generated.status != 0 || generated.stderr != "" {
			t.Fatalf("affine Deque compile: %+v stderr=%s", generated, generated.stderr)
		}
		const driver = `#include "alder_host.h"
#include <stdint.h>
static uint64_t g_count = 0;
static uint64_t g_sum = 0;
void counter(uint64_t v) { g_count++; g_sum += v; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (g_count != 9) { return 97; }
    if (g_sum != 36) { return 98; }
    return result;
}
`
		compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, generated.stdout, driver, 0)
		runSanitizedCollectionArtifact(t, cc, root, generated.stdout, driver, "affine Deque")
	})

	rejections := []struct {
		name, source, want string
	}{
		{
			"using-copyable-deque",
			`import std.collection { Deque }
fn main() -> I32 {
    let made: Deque(U64) = Deque.new()
    using d = made
    return 0
}
`,
			"type does not implement a trait required here",
		},
		{
			"peek-affine-deque",
			`import std.collection { Deque }
type Res { n: U64 }
impl Cleanup for Res { fn cleanup(take self) -> Unit { return } }
fn make(n: U64) -> Res { return Res(n: n) }
fn main() -> I32 {
    let made: Deque(Res) = Deque.new()
    using d = made
    let first = make(1)
    d.push_front(first)
    match d.peek_front() {
        Some(owner) => { using held = owner }
        None => {}
    }
    return 0
}
`,
			"a Vec of affine elements supports push, pop, and len only",
		},
		{
			"heap-without-order",
			`import std.collection { BinaryHeap }
type Res { n: U64 }
fn main() -> I32 {
    var heap: BinaryHeap(Res) = BinaryHeap.new()
    return 0
}
`,
			"type does not implement a trait required here",
		},
	}
	for _, rejection := range rejections {
		t.Run(rejection.name, func(t *testing.T) {
			files := map[string]string{"std/collection.al": string(collection), "main.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "main.al", "std/collection.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("%s was not rejected as expected: %+v stderr=%s", rejection.name, result, result.stderr)
			}
		})
	}
}

// runSanitizedCollectionArtifact rebuilds the generated program and the
// runtime under ASan/UBSan. The counter driver still proves exactly-once
// cleanup; the sanitizers catch a double free or use-after-free that a count
// alone could miss.
func runSanitizedCollectionArtifact(t *testing.T, cc, root, generated, driver, label string) {
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
		t.Fatalf("%s sanitized runtime compile: %v\n%s", label, err, output)
	}
	args := append(append([]string{}, strictC11Flags()...), sanitizer...)
	args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"),
		cfile, driverFile, runtimeObject, "-o", exe)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("%s sanitized generated compile: %v\n%s", label, err, output)
	}
	command := exec.Command(exe)
	command.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=0")
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("%s sanitized run: %v\n%s", label, err, output)
	}
}

const collectionCopyableProgram = `import std.collection { BinaryHeap, Deque }

pub fn main() -> I32 {
    var d: Deque(U64) = Deque.new()
    if !d.is_empty() { return 1 }
    d.push_back(2)
    d.push_back(3)
    d.push_front(1)
    if d.len() != 3 { return 2 }
    match d.peek_front() {
        Some(value) => { if value != 1 { return 3 } }
        None => { return 4 }
    }
    match d.peek_back() {
        Some(value) => { if value != 3 { return 5 } }
        None => { return 6 }
    }
    match d.pop_front() {
        Some(value) => { if value != 1 { return 7 } }
        None => { return 8 }
    }
    match d.pop_back() {
        Some(value) => { if value != 3 { return 9 } }
        None => { return 10 }
    }
    match d.pop_front() {
        Some(value) => { if value != 2 { return 11 } }
        None => { return 12 }
    }
    if !d.is_empty() { return 13 }
    match d.pop_back() {
        Some(_) => { return 14 }
        None => {}
    }
    d.push_back(10)
    d.push_back(20)
    d.push_back(30)
    d.push_front(9)
    d.push_front(8)
    match d.pop_back() {
        Some(value) => { if value != 30 { return 15 } }
        None => { return 16 }
    }
    match d.pop_front() {
        Some(value) => { if value != 8 { return 17 } }
        None => { return 18 }
    }
    match d.pop_back() {
        Some(value) => { if value != 20 { return 19 } }
        None => { return 20 }
    }
    match d.pop_front() {
        Some(value) => { if value != 9 { return 21 } }
        None => { return 22 }
    }
    match d.pop_front() {
        Some(value) => { if value != 10 { return 23 } }
        None => { return 24 }
    }
    if !d.is_empty() { return 25 }

    var heap: BinaryHeap(U64) = BinaryHeap.new()
    heap.push(5)
    heap.push(1)
    heap.push(4)
    heap.push(2)
    heap.push(3)
    heap.push(0)
    heap.push(6)
    if heap.len() != 7 { return 30 }
    match heap.peek() {
        Some(value) => { if value != 0 { return 31 } }
        None => { return 32 }
    }
    var want: U64 = 0
    while want < 7 {
        match heap.pop() {
            Some(value) => { if value != want { return 33 } }
            None => { return 34 }
        }
        want = want + 1
    }
    match heap.pop() {
        Some(_) => { return 35 }
        None => {}
    }

    var max_heap: BinaryHeap(U64) = BinaryHeap.max()
    max_heap.push(2)
    max_heap.push(5)
    max_heap.push(5)
    max_heap.push(1)
    max_heap.push(4)
    var previous: U64 = 6
    while max_heap.len() > 0 {
        match max_heap.pop() {
            Some(value) => {
                if value > previous { return 36 }
                previous = value
            }
            None => { return 37 }
        }
    }
    if previous != 1 { return 38 }
    return 0
}
`

const collectionAffineProgram = `import std.collection { Deque }
import c counter: fn(U64) -> Unit

type Res { n: U64 }
impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}
fn make(n: U64) -> Res { return Res(n: n) }

pub fn main() -> I32 {
    let created: Deque(Res) = Deque.new()
    using d = created
    let a0 = make(0)
    let a1 = make(1)
    let a2 = make(2)
    d.push_front(a0)
    d.push_front(a1)
    d.push_back(a2)
    match d.pop_back() {
        Some(owner) => {
            using held = owner
            if held.n != 2 { return 1 }
        }
        None => { return 2 }
    }
    match d.pop_front() {
        Some(owner) => {
            using held = owner
            if held.n != 1 { return 3 }
        }
        None => { return 4 }
    }
    match d.pop_front() {
        Some(owner) => {
            using held = owner
            if held.n != 0 { return 5 }
        }
        None => { return 6 }
    }
    if !d.is_empty() { return 7 }

    let b3 = make(3)
    let b4 = make(4)
    let b5 = make(5)
    d.push_front(b3)
    d.push_front(b4)
    d.push_front(b5)
    match d.pop_back() {
        Some(owner) => {
            using held = owner
            if held.n != 3 { return 8 }
        }
        None => { return 9 }
    }
    match d.pop_front() {
        Some(owner) => {
            using held = owner
            if held.n != 5 { return 10 }
        }
        None => { return 11 }
    }
    match d.pop_front() {
        Some(owner) => {
            using held = owner
            if held.n != 4 { return 12 }
        }
        None => { return 13 }
    }

    let c6 = make(6)
    let c7 = make(7)
    let c8 = make(8)
    d.push_back(c6)
    d.push_back(c7)
    d.push_front(c8)
    match d.pop_front() {
        Some(owner) => {
            using held = owner
            if held.n != 8 { return 14 }
        }
        None => { return 15 }
    }
    match d.pop_back() {
        Some(owner) => {
            using held = owner
            if held.n != 7 { return 16 }
        }
        None => { return 17 }
    }
    match d.pop_back() {
        Some(owner) => {
            using held = owner
            if held.n != 6 { return 18 }
        }
        None => { return 19 }
    }
    return 0
}
`
