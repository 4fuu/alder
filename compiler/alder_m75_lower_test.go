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
