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

fn take_first(W: type(Walker(U64)), walker: W) -> U64 {
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

// M7.5 generic implementation parameter lists (D024 second part): one trait
// implemented for a generic record through an `impl(I: type(Io))` head, and
// a second implementation whose method dispatches to the first through the
// instance. The program must lower, verify, compile under the strict C11
// set, and run with the expected dispatch results. Alder-only: the Go
// oracle frontend does not implement the trait surface.
func runAlderGenericImplLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"generic-impl.al": `trait Io {
}

trait Reader {
    fn read(self) -> U64
}

trait Preview {
    fn preview(self) -> U64
}

type Token {
}

type File(I: type(Io)) {
    id: I
}

impl Io for Token {
}

impl(I: type(Io)) Reader for File(I) {
    fn read(self) -> U64 {
        return 42
    }
}

impl(I: type(Io)) Preview for File(I) {
    fn preview(self) -> U64 {
        let direct = self.read()
        return direct + 1
    }
}

fn main() -> I32 {
    let file = File(id: Token())
    if file.read() != 42 { return 1 }
    if file.preview() != 43 { return 2 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"generic-impl.al"})
	second := runLowerCompiler(t, exe, files, []string{"generic-impl.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("lowered generic impl MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify lowered generic impl MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("generic impl MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"generic-impl.al"})
	if repeat := runResourceCgenCompiler(t, exe, files, []string{"generic-impl.al"}); !bytes.Equal(generated, repeat) {
		t.Fatal("Alder-written generic impl C changed across processes")
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
	file := filepath.Join(dir, "generic-impl.c")
	program := filepath.Join(dir, "generic-impl.exe")
	// The parameterless hosted entry takes no domain argument.
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of generic impl dispatch: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run generic impl dispatch behavior: %v\n%s", err, output)
	}
	t.Logf("generic impl dispatch program exited cleanly under strict C11")
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
    // Ordered-builtin results compare directly as Eq operands: their
    // lowering joins through block parameters, so each operand spills in
    // the block where its value is defined before the structural walk.
    if seen.contains(2) == false { return 49 }
    if seen.contains(9) != false { return 50 }
    if seen.remove(2) == false { return 51 }
    if seen.len() != 0 { return 52 }
    if names.insert("delta", 5) == false { return 53 }
    if names.len() != 4 { return 54 }
    if scores.get(9) != None { return 55 }
    if scores.get(2) == None { return 56 }
    // For-in over a method-result sequence: the sequence expression
    // terminates the entry block and its value lives in the block that
    // finishes the projection loop, so the loop-head jump must leave that
    // block. A named sequence binding lowers in place and pins the
    // unchanged path, and an empty method result must make zero trips.
    var key_total: U64 = 0
    for k in ordered.keys() {
        key_total = key_total + k
    }
    if key_total != 6 { return 57 }
    var value_total: U64 = 0
    for v in ordered.values() {
        value_total = value_total + v
    }
    if value_total != 66 { return 58 }
    var named_total: U64 = 0
    let key_copy = ordered.keys()
    for k in key_copy {
        named_total = named_total + k
    }
    if named_total != 6 { return 59 }
    if !seen.insert(7) { return 60 }
    var item_total: U64 = 0
    var trips: U64 = 0
    for item in seen.items() {
        item_total = item_total + item
        trips = trips + 1
    }
    if item_total != 7 { return 61 }
    if trips != 1 { return 62 }
    var emptied = Set.new(U64)
    var zero_trips: U64 = 0
    for item in emptied.items() {
        zero_trips = zero_trips + 1
    }
    if zero_trips != 0 { return 63 }
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

// Rule-89 mut cursors end to end: the docs' drain example shape (S0 has no
// `while let`, so the loop is the recursive form used across M7.5) with a
// copyable cursor. The mut parameter borrows the caller's var binding, so
// the second drain must start where the first ended instead of re-reading a
// copy. Alder-only: the Go oracle frontend does not implement the trait
// surface.
func runAlderM75MutCursorLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"mut-cursor.al": `type Cursor {
    at: U64
}

impl Iterator(U64) for Cursor {
    fn next(mut self) -> Option(U64) {
        if self.at < 3 {
            let value = self.at
            self.at = self.at + 1
            return Some(value)
        }
        return None
    }
}

fn drain(I: type(Iterator(T)), T: type, mut iterator: I, total: U64) -> U64 {
    return match iterator.next() {
        Some(value) => drain(I, T, iterator, total + value)
        None => total
    }
}

fn main() -> I32 {
    var cursor = Cursor(at: 0)
    let first = drain(Cursor, U64, cursor, 0)
    if first != 3 { return 1 }
    let second = drain(Cursor, U64, cursor, 0)
    if second != 0 { return 2 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"mut-cursor.al"})
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse mut-cursor MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify mut-cursor MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("mut-cursor MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"mut-cursor.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "mut-cursor.c")
	program := filepath.Join(dir, "mut-cursor.exe")
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of mut-cursor drain: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run mut-cursor drain behavior: %v\n%s", err, output)
	}
	t.Logf("mut-cursor drain program exited cleanly under strict C11")
}

// Constrained type parameters end to end: constraints on a trait, a record,
// an enum, and a trait method, with a constraint naming a later parameter of
// the same list. Dispatch through the constrained generics must run and
// produce the expected results. Alder-only: the Go oracle frontend does not
// implement the trait surface.
func runAlderConstrainedShapesLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"constrained-shapes.al": `type Tag {
    id: U64
}

trait Show {
    fn show(self) -> U64
}

impl Show for Tag {
    fn show(self) -> U64 { return self.id }
}

type Boxed(K: type(Show)) {
    inner: K
}

enum Wrap(T: type(Show)) {
    Held(value: T)
    Empty
}

trait Carrier(Carried: type(Show)) {
    fn carry(self) -> Carried
}

impl Carrier(Tag) for Tag {
    fn carry(self) -> Tag {
        return self
    }
}

fn describe(C: type(Carrier(Item)), Item: type(Show), c: C) -> U64 {
    return c.carry().show()
}

trait Maker {
    fn make(New: type(Show), self, seed: New) -> New
}

impl Maker for Tag {
    fn make(New: type(Show), self, seed: New) -> New {
        return seed
    }
}

fn use_maker(M: type(Maker), New: type(Show), m: M, seed: New) -> New {
    return m.make(New, seed)
}

fn main() -> I32 {
    let tag = Tag(id: 7)
    let boxed = Boxed(inner: tag)
    if boxed.inner.show() != 7 { return 1 }
    let wrap: Wrap(Tag) = Held(tag)
    let shown = match wrap {
        Held(value) => value.show()
        Empty => 0
    }
    if shown != 7 { return 2 }
    if describe(Tag, Tag, tag) != 7 { return 3 }
    let made = tag.make(Tag, tag)
    if made.show() != 7 { return 4 }
    let made2 = use_maker(Tag, Tag, tag, tag)
    if made2.show() != 7 { return 5 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"constrained-shapes.al"})
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse constrained-shapes MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify constrained-shapes MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("constrained-shapes MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"constrained-shapes.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "constrained-shapes.c")
	program := filepath.Join(dir, "constrained-shapes.exe")
	// The parameterless hosted entry takes no domain argument.
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of constrained shapes: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run constrained shapes behavior: %v\n%s", err, output)
	}
	t.Logf("constrained shapes program exited cleanly under strict C11")
}

// Generic trait methods end to end: a requirement with its own type
// parameters, the matching impl method, and direct dot-calls with inferred
// and explicit type arguments. Alder-only: the Go oracle frontend does not
// implement the trait surface.
func runAlderM75GenericMethodLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"generic-methods.al": `type Box {
    v: U64
}

trait Combine(Item: type) {
    fn combine(A: type, self, other: A) -> A
}

impl Combine(U64) for Box {
    fn combine(A: type, self, other: A) -> A {
        return other
    }
}

fn main() -> I32 {
    let box = Box(v: 5)
    if box.combine(U64, 3) != 3 { return 1 }
    if box.combine(4) != 4 { return 2 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"generic-methods.al"})
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse generic-method MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify generic-method MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("generic-method MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"generic-methods.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "generic-methods.c")
	program := filepath.Join(dir, "generic-methods.exe")
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of generic trait methods: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run generic trait method behavior: %v\n%s", err, output)
	}
	t.Logf("generic trait method program exited cleanly under strict C11")
}

// Generic-trait default methods end to end: one defaulted requirement whose
// result is the trait's parameter, materialized for two implementations with
// different trait arguments. The default body calls the overridden method,
// the materialized result type is the impl's concrete argument, and both the
// direct dot-call and dispatch through a constrained generic function run
// under strict C11. Alder-only: the Go oracle frontend does not implement
// the trait surface.
func runAlderGenericTraitDefaultLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"generic-trait-defaults.al": `type NumBox {
    n: U64
}

type TextBox {
    t: String
}

trait Produce(Out: type) {
    fn produce(self) -> Out
    fn identity_default(self) -> Out {
        return self.produce()
    }
}

impl Produce(U64) for NumBox {
    fn produce(self) -> U64 { return self.n }
}

impl Produce(String) for TextBox {
    fn produce(self) -> String { return self.t }
}

fn through(P: type(Produce(O)), O: type, p: P) -> O {
    return p.identity_default()
}

fn main() -> I32 {
    let num = NumBox(n: 7)
    if num.identity_default() != 7 { return 1 }
    if through(NumBox, U64, num) != 7 { return 2 }
    var seen = Map.new(String, U64)
    let text = TextBox(t: "hey")
    if !seen.insert(text.identity_default(), 5) { return 3 }
    let found = seen.get("hey")
    let got = match found {
        Some(v) => v
        None => 0
    }
    if got != 5 { return 4 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"generic-trait-defaults.al"})
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse generic-trait-default MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify generic-trait-default MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("generic-trait-default MIR has no main function")
	}
	// Both materializations lower as distinct functions.
	materialized := 0
	for id := range module.Functions {
		name := module.Functions[id].Name
		if len(name) > len("identity_default") && name[:len("identity_default")] == "identity_default" {
			materialized++
		}
	}
	if materialized != 2 {
		t.Fatalf("generic-trait-default MIR has %d identity_default materializations, want 2", materialized)
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"generic-trait-defaults.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "generic-trait-defaults.c")
	program := filepath.Join(dir, "generic-trait-defaults.exe")
	driver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; int32_t status = alder_fn_main_%d(&root); alder_domain_destroy(&root); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of generic-trait defaults: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run generic-trait default behavior: %v\n%s", err, output)
	}
	t.Logf("generic-trait default program exited cleanly under strict C11")
}

// Domain-carrying function values end to end: in the storage model every
// plain function carries a hidden leading domain parameter, so a function
// reference wraps the current domain into the value's environment and the
// C forwarder passes it as the target's first argument. Named functions and
// closures mix in one function, a function value threads into a constrained
// generic call, and a value created in a helper or a nested block is called
// after that scope returned — sound because every domain in a public-source
// program descends from the main entry's domain, which outlives every
// frame. Alder-only: the Go oracle frontend does not implement the storage
// model's fn-value surface.
func runAlderFnValueDomainLowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"fn-value-domain.al": `fn scale(x: U64) -> U64 { return x + 1 }
fn twice_apply(f: fn(U64) -> U64, v: U64) -> U64 {
    return f(f(v))
}
fn outer(T: type, f: fn(U64) -> U64, seed: U64) -> U64 {
    return f(seed + 1)
}
type Holder { cb: fn(U64) -> U64 }
fn make_holder(seed: U64) -> Holder {
    return Holder(cb: scale)
}
fn call_it(h: Holder) -> U64 {
    let f = h.cb
    return f(4)
}
fn main() -> I32 {
    if twice_apply(scale, 1) != 3 { return 1 }
    let offset: U64 = 5
    let shifted = fn(x: U64) => x + offset
    if twice_apply(shifted, 1) != 11 { return 2 }
    if outer(U64, scale, 3) != 5 { return 3 }
    if call_it(make_holder(2)) != 5 { return 4 }
    var keep = Vec.new(Holder)
    {
        let h = Holder(cb: scale)
        keep.push(h)
    }
    if keep.len() != 1 { return 5 }
    let first = keep.get(0)
    let got = match first {
        Some(h) => call_it(h)
        None => 0
    }
    if got != 5 { return 6 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"fn-value-domain.al"})
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse fn-value-domain MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify fn-value-domain MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("fn-value-domain MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"fn-value-domain.al"})
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "fn-value-domain.c")
	program := filepath.Join(dir, "fn-value-domain.exe")
	// The program owns heap storage: the driver creates the root domain and
	// passes it to the hosted main, whose parameter aliases it.
	driver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; int32_t status = alder_fn_main_%d(&root); alder_domain_destroy(&root); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of fn-value domain program: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run fn-value domain behavior: %v\n%s", err, output)
	}
	t.Logf("fn-value domain program exited cleanly under strict C11")
}

// M8 Eq dispatch: `==` and `!=` beyond the primitive integer comparison.
// The operators compare Bool, String, and Bytes byte-wise, records
// field-wise, enums by tag and payload, and generic applications over Eq
// components, reusing the Map-key structural walk. Option and Result are
// not Eq yet: the checker rejects them with the Eq diagnostic instead of
// lowering them. Alder-only: the Go oracle frontend has no operator mirror
// for the structural families.
func runAlderEqOperatorBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"eq-operators.al": `type Point {
    x: U64
    y: U64
}

type Wrap(T: type(Eq)) {
    value: T
}

enum Shape {
    Empty
    Pair(at: Point)
}

fn main() -> I32 {
    if 3 != 3 { return 1 }
    if 4 == 5 { return 2 }
    if true == false { return 3 }
    if true != true { return 4 }
    if "abc" != "abc" { return 5 }
    if "abc" == "abd" { return 6 }
    if "abc".to_bytes() != "abc".to_bytes() { return 7 }
    if "abc".to_bytes() == "abd".to_bytes() { return 8 }
    let a = Point(x: 1, y: 2)
    let b = Point(x: 1, y: 2)
    let c = Point(x: 1, y: 3)
    if a != b { return 9 }
    if a == c { return 10 }
    let e1: Shape = Empty
    let e2: Shape = Empty
    if e1 != e2 { return 11 }
    let q1: Shape = Pair(a)
    if e1 == q1 { return 12 }
    let q2: Shape = Pair(c)
    let p1: Shape = Pair(a)
    let p2: Shape = Pair(b)
    if p1 != p2 { return 13 }
    if p1 == q2 { return 14 }
    let w1 = Wrap(value: a)
    let w2 = Wrap(value: b)
    if w1 != w2 { return 15 }
    let w3 = Wrap(value: c)
    if w1 == w3 { return 16 }
    let s5: Option(U64) = Some(5)
    let s5b: Option(U64) = Some(5)
    let s6: Option(U64) = Some(6)
    let n: Option(U64) = None
    let nb: Option(U64) = None
    if s5 != s5b { return 17 }
    if s5 == s6 { return 18 }
    if s5 == n { return 19 }
    if n == s5 { return 20 }
    if n != nb { return 21 }
    let ok1: Result(U64, U64) = Ok(7)
    let ok1b: Result(U64, U64) = Ok(7)
    let ok8: Result(U64, U64) = Ok(8)
    let err1: Result(U64, U64) = Err(1)
    let err1b: Result(U64, U64) = Err(1)
    let err2: Result(U64, U64) = Err(2)
    if ok1 != ok1b { return 22 }
    if ok1 == ok8 { return 23 }
    if err1 != err1b { return 24 }
    if err1 == err2 { return 25 }
    if ok1 == err1 { return 26 }
    if err1 == ok1 { return 27 }
    let o1: Option(Point) = Some(a)
    let o2: Option(Point) = Some(b)
    let o3: Option(Point) = Some(c)
    if o1 != o2 { return 28 }
    if o1 == o3 { return 29 }
    let nested1: Result(Option(U64), U64) = Ok(Some(9))
    let nested2: Result(Option(U64), U64) = Ok(Some(9))
    let nested3: Result(Option(U64), U64) = Ok(None)
    if nested1 != nested2 { return 30 }
    if nested1 == nested3 { return 31 }
    return 0
}
`}
	first := runLowerCompiler(t, exe, files, []string{"eq-operators.al"})
	second := runLowerCompiler(t, exe, files, []string{"eq-operators.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("lowered Eq operator MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify lowered Eq operator MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("Eq operator MIR has no main function")
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"eq-operators.al"})
	if repeat := runResourceCgenCompiler(t, exe, files, []string{"eq-operators.al"}); !bytes.Equal(generated, repeat) {
		t.Fatal("Alder-written Eq operator C changed across processes")
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
	file := filepath.Join(dir, "eq-operators.c")
	program := filepath.Join(dir, "eq-operators.exe")
	// The parameterless hosted entry takes no domain argument.
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of Eq operator dispatch: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run Eq operator behavior: %v\n%s", err, output)
	}
	t.Logf("Eq operator program exited cleanly under strict C11")
}
