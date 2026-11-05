package compiler

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// M7.5 slice 2: static trait dispatch through generic monomorphization. The
// program implements one user trait for two record types and calls the trait
// method both through a constrained generic function (resolved per concrete
// instance) and directly on a concrete receiver. The generated C must run
// with the expected dispatch results. Alder-only: the Go oracle frontend
// does not implement the trait surface.
func runAlderM75LowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"traits.al": `type UserCursor {
    row: U64
}

type AdminCursor {
    row: U64
}

trait Walker(Item: type) {
    fn next(self) -> Option(Item)
}

impl Walker(U64) for UserCursor {
    fn next(self) -> Option(U64) {
        if self.row == 0 { return None }
        return Some(self.row)
    }
}

impl Walker(U64) for AdminCursor {
    fn next(self) -> Option(U64) {
        return Some(self.row + 100)
    }
}

fn take_first(W: type, walker: W) -> U64
where W: Walker(U64) {
    let value = walker.next()
    return match value {
        Some(v) => v
        None => 0
    }
}

fn main() -> I32 {
    let user = UserCursor(row: 3)
    let admin = AdminCursor(row: 4)
    if take_first(UserCursor, user) != 3 { return 1 }
    if take_first(AdminCursor, admin) != 104 { return 2 }
    let value = admin.next()
    return match value {
        Some(v) => 0
        None => 3
    }
}
`}
	first := runLowerCompiler(t, exe, files, []string{"traits.al"})
	second := runLowerCompiler(t, exe, files, []string{"traits.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("lowered trait dispatch MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify lowered trait MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("trait dispatch MIR has no main function")
	}
	// Generic instances lower as the declaration name plus the owning symbol
	// id, e.g. take_first8; both receiver types must produce one instance.
	foundInstances := 0
	for id := range module.Functions {
		name := module.Functions[id].Name
		if len(name) > len("take_first") && name[:len("take_first")] == "take_first" {
			foundInstances++
		}
	}
	if foundInstances != 2 {
		t.Fatalf("trait dispatch MIR has %d take_first instances, want 2", foundInstances)
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"traits.al"})
	if repeat := runResourceCgenCompiler(t, exe, files, []string{"traits.al"}); !bytes.Equal(generated, repeat) {
		t.Fatal("Alder-written trait dispatch C changed across processes")
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "traits.c")
	program := filepath.Join(dir, "traits.exe")
	// The parameterless hosted entry takes no domain argument.
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of trait dispatch: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run trait dispatch behavior: %v\n%s", err, output)
	}
	t.Logf("trait dispatch program exited cleanly under strict C11")
}

// runLowerCompilerPublic runs the lower conformance entry without the
// private bootstrap profile: ordered Map/Set fixtures use the public types,
// so the Map( heuristic in runLowerCompiler must not fire for them.
func runLowerCompilerPublic(t *testing.T, exe string, files map[string]string, order []string) []byte {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "!alder-core-lower"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	args := append([]string{"!alder-core-lower"}, order...)
	cmd := conformanceCommand(exe, args...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), "TMPDIR="+t.TempDir())
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("run public lower compiler: %v\nstdout:\n%s\nstderr:\n%s", err, stdout.Bytes(), stderr.Bytes())
	}
	if stderr.Len() != 0 {
		t.Fatalf("public lower compiler wrote stderr: %s", stderr.Bytes())
	}
	return stdout.Bytes()
}

// M7.5 verifier-slice: scalar loads in loops. The phase-6 provenance rule
// now treats loads of storage-free types as plain bits, so ordinary source
// loops can bind Vec elements to locals. This pins the Alder-written
// verifier's rule end to end through lowering, verification, generated
// strict C11, and execution. Alder-only: the Go oracle frontend lowers
// through the Go verifier, which has its own mirror fixtures.
func runAlderVecLoopLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"vec-loop.al": `fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(3)
    values.push(4)
    var total: U64 = 0
    var at: U64 = 0
    while at < values.len() {
        let found = values.get(at)
        let item = match found {
            Some(v) => v
            None => 0
        }
        total = total + item
        at = at + 1
    }
    if total != 7 { return 1 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"vec-loop.al"})
	second := runLowerCompiler(t, exe, files, []string{"vec-loop.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("vec loop MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse vec loop MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify vec loop MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("vec loop MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"vec-loop.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "vec-loop.c")
	program := filepath.Join(dir, "vec-loop.exe")
	// main owns vector storage, so the hosted entry takes the root domain.
	driver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; int32_t status = alder_fn_main_%d(&root); alder_domain_destroy(&root); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of vec loop: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run vec loop behavior: %v\n%s", err, output)
	}
	t.Logf("vec loop program exited cleanly under strict C11")
}

// M7.5 C5b function values: a non-generic function name in value position,
// a fn(...) -> ... typed parameter, and an indirect call all lower through
// fn.value/call.value and run under strict C11. Alder-only.
func runAlderFnValueLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"fnvalue.al": `fn apply(f: fn(U64) -> U64, value: U64) -> U64 {
    return f(value)
}

fn double(x: U64) -> U64 {
    return x + x
}

fn inc(x: U64) -> U64 {
    return x + 1
}

fn pick(first: Bool, f: fn(U64) -> U64, g: fn(U64) -> U64) -> fn(U64) -> U64 {
    if first { return f }
    return g
}

fn main() -> I32 {
    let referenced = double
    if referenced(4) != 8 { return 1 }
    if apply(referenced, 3) != 6 { return 2 }
    if apply(inc, 10) != 11 { return 3 }
    let chosen = pick(true, double, inc)
    if chosen(5) != 10 { return 4 }
    let other = pick(false, double, inc)
    if other(5) != 6 { return 5 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"fnvalue.al"})
	second := runLowerCompiler(t, exe, files, []string{"fnvalue.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("fn value MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse fn value MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify fn value MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("fn value MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"fnvalue.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "fnvalue.c")
	program := filepath.Join(dir, "fnvalue.exe")
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of fn values: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run fn value behavior: %v\n%s", err, output)
	}
	t.Logf("fn value program exited cleanly under strict C11")
}

// M7.5 default-method dispatch: a dot-call on a receiver whose impl omits a
// defaulted requirement dispatches to the materialized default body, pinned
// through generated strict C11 alongside overridden methods. Alder-only.
func runAlderDefaultMethodLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"defaults.al": `type Box {
    v: U64
}

trait Getter {
    fn fetch(self) -> U64 {
        return 7
    }
    fn stamped(self) -> U64
}

impl Getter for Box {
    fn stamped(self) -> U64 {
        return self.v + 100
    }
}

trait Marked {
    fn marked(self) -> U64 {
        return 11
    }
}

impl Marked for Box {
}

fn main() -> I32 {
    let box = Box(v: 1)
    if box.fetch() != 7 { return 1 }
    if box.stamped() != 101 { return 2 }
    if box.marked() != 11 { return 3 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"defaults.al"})
	second := runLowerCompiler(t, exe, files, []string{"defaults.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("default-method MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse default-method MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify default-method MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("default-method MIR has no main function")
	}
	generated := runResourceCgenCompilerPublic(t, exe, files, []string{"defaults.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "defaults.c")
	program := filepath.Join(dir, "defaults.exe")
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of default methods: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run default-method behavior: %v\n%s", err, output)
	}
	t.Logf("default-method program exited cleanly under strict C11")
}

// M7.5 C5b closures: fn-literal expressions with read-only snapshot captures
// of ordinary values, arrow and braced bodies, and calls through the closure
// value all lower through fn.value/call.value with environment records and
// run under strict C11. Alder-only.
func runAlderClosureLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"closures.al": `type Point {
    x: U64
    y: U64
}

fn build() -> fn(I64) -> Bool {
    let minimum = 10
    return fn(value: I64) => value >= minimum
}

fn main() -> I32 {
    let accepted = build()
    if accepted(2) { return 1 }
    if !accepted(12) { return 2 }
    let base = Point(x: 3, y: 4)
    let scaled = fn(p: Point) -> U64 {
        return p.x * base.x + p.y * base.y
    }
    if scaled(Point(x: 2, y: 2)) != 14 { return 3 }
    let plain = fn(x: U64) => x + 1
    if plain(41) != 42 { return 4 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"closures.al"})
	second := runLowerCompiler(t, exe, files, []string{"closures.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("closure MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse closure MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify closure MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("closure MIR has no main function")
	}
	generated := runResourceCgenCompilerPublic(t, exe, files, []string{"closures.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "closures.c")
	program := filepath.Join(dir, "closures.exe")
	// main owns the closure environment storage, so the hosted entry takes
	// the root domain.
	driver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; int32_t status = alder_fn_main_%d(&root); alder_domain_destroy(&root); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of closures: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run closure behavior: %v\n%s", err, output)
	}
	t.Logf("closure program exited cleanly under strict C11")
}

// runResourceCgenCompilerPublic is runResourceCgenCompiler without the
// private-profile heuristic, for public ordered Map/Set fixtures.
func runResourceCgenCompilerPublic(t *testing.T, exe string, files map[string]string, order []string) []byte {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "!alder-core-cgen-resources"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	args := append([]string{"!alder-core-cgen-resources"}, order...)
	cmd := conformanceCommand(exe, args...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), "TMPDIR="+t.TempDir())
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("run public Alder resource C generator: %v\nstdout:\n%s\nstderr:\n%s", err, stdout.Bytes(), stderr.Bytes())
	}
	if stderr.Len() != 0 || stdout.Len() == 0 {
		t.Fatalf("public Alder resource C generator produced invalid streams: stdout=%d stderr=%s", stdout.Len(), stderr.Bytes())
	}
	return stdout.Bytes()
}

// M7.5 C4: ordered Map/Set lower end to end through generated strict C11.
// The program exercises creation, insert with in-place replacement, get with
// Some/None results, structural record keys, Vec values with deep copies,
// and Set insert/contains/len. Alder-only: the Go oracle frontend does not
// implement the ordered collections.
func runAlderM75OrderedLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"ordered.al": `type Key {
    a: U64
    b: Bool
}

fn fetch(scores: Map(U64, U64), key: U64) -> U64 {
    let found = scores.get(key)
    return match found {
        Some(v) => v
        None => 0
    }
}

fn main() -> I32 {
    var scores = Map.new(U64, U64)
    if scores.len() != 0 { return 1 }
    if !scores.insert(1, 10) { return 2 }
    if !scores.insert(2, 20) { return 3 }
    if scores.insert(2, 25) { return 4 }
    if scores.len() != 2 { return 5 }
    if fetch(scores, 2) != 25 { return 6 }
    if fetch(scores, 9) != 0 { return 7 }
    var by_key = Map.new(Key, U64)
    if !by_key.insert(Key(a: 1, b: true), 7) { return 8 }
    if by_key.insert(Key(a: 1, b: true), 9) { return 9 }
    if by_key.len() != 1 { return 10 }
    let keyed = by_key.get(Key(a: 1, b: true))
    let key_value = match keyed {
        Some(v) => v
        None => 0
    }
    if key_value != 9 { return 11 }
    var lists = Map.new(U64, Vec(U64))
    var empty = Vec.new(U64)
    if !lists.insert(1, empty) { return 12 }
    var grown = Vec.new(U64)
    grown.push(5)
    grown.push(6)
    if lists.insert(1, grown) { return 13 }
    let fetched = lists.get(1)
    let fetched_len = match fetched {
        Some(v) => v.len()
        None => 0
    }
    if fetched_len != 2 { return 14 }
    grown.push(7)
    let after = lists.get(1)
    let after_len = match after {
        Some(v) => v.len()
        None => 0
    }
    if after_len != 2 { return 15 }
    var seen = Set.new(U64)
    if seen.len() != 0 { return 16 }
    if !seen.insert(1) { return 17 }
    if seen.insert(1) { return 18 }
    if !seen.insert(2) { return 19 }
    if seen.len() != 2 { return 20 }
    if !seen.contains(2) { return 21 }
    if seen.contains(9) { return 22 }
    // Insertion order: replacement keeps position, removal compacts in
    // order, and reinsertion moves the key to the end.
    var ordered = Map.new(U64, U64)
    if !ordered.insert(1, 10) { return 23 }
    if !ordered.insert(2, 20) { return 24 }
    if !ordered.insert(3, 30) { return 25 }
    if ordered.insert(2, 25) { return 26 }
    let after_replace = ordered.keys()
    if after_replace.len() != 3 { return 27 }
    let first = after_replace.get(0)
    let first_key = match first {
        Some(v) => v
        None => 0
    }
    if first_key != 1 { return 28 }
    let second = after_replace.get(1)
    let second_key = match second {
        Some(v) => v
        None => 0
    }
    if second_key != 2 { return 29 }
    let replaced_value = ordered.get(2)
    let replaced = match replaced_value {
        Some(v) => v
        None => 0
    }
    if replaced != 25 { return 30 }
    if !ordered.remove(1) { return 31 }
    if ordered.remove(9) { return 32 }
    if ordered.len() != 2 { return 33 }
    let after_remove = ordered.keys()
    let third = after_remove.get(0)
    let third_key = match third {
        Some(v) => v
        None => 0
    }
    if third_key != 2 { return 34 }
    let values = ordered.values()
    let value_zero = values.get(0)
    let value_zero_item = match value_zero {
        Some(v) => v
        None => 0
    }
    if value_zero_item != 25 { return 35 }
    if !ordered.insert(1, 11) { return 36 }
    let after_reinsert = ordered.keys()
    if after_reinsert.len() != 3 { return 37 }
    let tail = after_reinsert.get(2)
    let tail_key = match tail {
        Some(v) => v
        None => 0
    }
    if tail_key != 1 { return 38 }
    if !seen.remove(1) { return 39 }
    let items = seen.items()
    if items.len() != 1 { return 40 }
    let only = items.get(0)
    let only_item = match only {
        Some(v) => v
        None => 0
    }
    if only_item != 2 { return 41 }
    var names = Map.new(String, U64)
    if !names.insert("alpha", 1) { return 42 }
    if names.insert("alpha", 2) { return 43 }
    if !names.insert("beta", 3) { return 44 }
    if !names.insert("gamma", 4) { return 45 }
    if names.len() != 3 { return 46 }
    let alpha = names.get("alpha")
    let alpha_value = match alpha {
        Some(v) => v
        None => 0
    }
    if alpha_value != 2 { return 47 }
    let delta = names.get("delta")
    let delta_seen = match delta {
        Some(v) => v
        None => 9
    }
    if delta_seen != 9 { return 48 }
    return 0
}
`}
	first := runLowerCompilerPublic(t, exe, files, []string{"ordered.al"})
	second := runLowerCompilerPublic(t, exe, files, []string{"ordered.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("ordered collections MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse ordered collections MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify ordered collections MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("ordered collections MIR has no main function")
	}
	generated := runResourceCgenCompilerPublic(t, exe, files, []string{"ordered.al"})
	if repeat := runResourceCgenCompilerPublic(t, exe, files, []string{"ordered.al"}); !bytes.Equal(generated, repeat) {
		t.Fatal("Alder-written ordered collections C changed across processes")
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "ordered.c")
	program := filepath.Join(dir, "ordered.exe")
	// main owns map/set storage, so the hosted entry takes the root domain.
	driver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; int32_t status = alder_fn_main_%d(&root); alder_domain_destroy(&root); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of ordered collections: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run ordered collections behavior: %v\n%s", err, output)
	}
	t.Logf("ordered collections program exited cleanly under strict C11")
}
