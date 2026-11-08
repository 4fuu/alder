package compiler

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// M7.5 slice 1: trait declarations, `where` constraints, trait
// implementations, coherence, and constraint-gated instantiation. These
// fixtures are Alder-only: the Go oracle frontend does not implement the
// trait surface, so they stay out of the shared comparison corpora.
func runAlderM75CheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"traits.al": `type UserCursor {
    row: U64
}

trait Walker(Item: type) {
    fn next(self) -> Option(Item)
    fn peek(self) -> Option(Item) {
        return None
    }
}

impl Walker(U64) for UserCursor {
    fn next(self) -> Option(U64) {
        if self.row == 0 { return None }
        return Some(self.row)
    }
}

fn drain(W: type, T: type, walker: W) -> U64
where W: Walker(T) {
    return 0
}

fn main() -> I32 {
    let cursor = UserCursor(row: 3)
    if drain(UserCursor, U64, cursor) != 0 { return 1 }
    return 0
}
`,
		"closures.al": `type Point {
    x: U64
    y: U64
}

fn main() -> I32 {
    let minimum = 10
    let accepted = fn(value: I64) => value >= minimum
    if accepted(12) { return 0 }
    if !accepted(2) { return 1 }
    let base = Point(x: 3, y: 4)
    let scaled = fn(p: Point) -> U64 {
        return p.x * base.x + p.y * base.y
    }
    if scaled(Point(x: 2, y: 2)) != 14 { return 2 }
    let plain = fn(x: U64) => x + 1
    if plain(41) != 42 { return 3 }
    let typed: fn() -> I64 = fn() => 9
    if typed() != 9 { return 4 }
    return 0
}
`,
		"defaults.al": `type Box {
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
`,
		"markers.al": `type Box {
    v: U64
}

trait Marker(A: type) {
}

impl Marker(U64) for Box {
}

fn use_mark(M: type, A: type, b: M) -> U64
where M: Marker(A) {
    return 0
}

fn main() -> I32 {
    let box = Box(v: 1)
    if use_mark(Box, U64, box) != 0 { return 1 }
    return 0
}
`,
		"trait-params.al": `trait IntoWalker(Iter: type, Item: type)
where Iter: Stepper(Item) {
    fn into_walker(self) -> Iter
}

trait Stepper(Item: type) {
    fn next(self) -> Option(Item)
}

fn main() -> I32 { return 0 }
`,
		"impl-body.al": `type Box {
    v: U64
}

trait Getter {
    fn get(self) -> U64
}

impl Getter for Box {
    fn get(self) -> U64 {
        return self.v
    }
}

fn main() -> I32 {
    let box = Box(v: 7)
    return 0
}
`,
		"structural-keys.al": `type Key {
    name: U64
    flag: Bool
}

enum Mode {
    Fast
    Slow(code: U32)
}

fn keyed(K: type, k: K) -> U64
where K: Eq + Hash {
    return 1
}

fn main() -> I32 {
    let key = Key(name: 7, flag: true)
    if keyed(Key, key) != 1 { return 1 }
    let mode: Mode = Slow(3)
    if keyed(Mode, mode) != 1 { return 2 }
    if keyed(U64, 5) != 1 { return 3 }
    if keyed(String, "x") != 1 { return 4 }
    return 0
}
`,
		"generic-methods.al": `type Box {
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

fn use_combine(C: type, I: type, c: C, extra: U64) -> U64
where C: Combine(I) {
    return c.combine(extra)
}

fn main() -> I32 {
    let box = Box(v: 5)
    if box.combine(U64, 3) != 3 { return 1 }
    if use_combine(Box, U64, box, 9) != 9 { return 2 }
    if box.combine(4) != 4 { return 3 }
    return 0
}
`,
		"fn-value-mix.al": `fn scale(x: U64) -> U64 { return x + 1 }
fn twice_apply(f: fn(U64) -> U64, v: U64) -> U64 {
    return f(f(v))
}
fn main() -> I32 {
    if twice_apply(scale, 1) != 3 { return 1 }
    let offset: U64 = 5
    let shifted = fn(x: U64) => x + offset
    if shifted(1) != 6 { return 2 }
    if twice_apply(shifted, 1) != 11 { return 3 }
    return 0
}
`,
		"fn-value-into-generic.al": `fn outer(T: type, f: fn(U64) -> U64, seed: U64) -> U64 {
    return f(seed + 1)
}
fn scale(x: U64) -> U64 { return x + 1 }
fn main() -> I32 {
    if outer(U64, scale, 3) != 5 { return 1 }
    return 0
}
`,
		"fn-value-escape.al": `fn scale(x: U64) -> U64 { return x + 1 }
type Holder { cb: fn(U64) -> U64 }
fn make_holder(seed: U64) -> Holder {
    return Holder(cb: scale)
}
fn call_it(h: Holder) -> U64 {
    let f = h.cb
    return f(4)
}
fn main() -> I32 {
    let made = make_holder(2)
    if call_it(made) != 5 { return 1 }
    var keep = Vec.new(Holder)
    {
        let h = Holder(cb: scale)
        keep.push(h)
    }
    if keep.len() != 1 { return 2 }
    let first = keep.get(0)
    let got = match first {
        Some(h) => call_it(h)
        None => 0
    }
    if got != 5 { return 3 }
    return 0
}
`,
		"generic-trait-defaults.al": `type NumBox {
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

fn through(P: type, O: type, p: P) -> O
where P: Produce(O) {
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
`,
		"defaulted-generic-method.al": `type Box {
    v: U64
}

trait Echo {
    fn echo(A: type, self, other: A) -> A {
        return other
    }
}

impl Echo for Box {
}

fn main() -> I32 {
    let box = Box(v: 5)
    if box.echo(3) != 3 { return 1 }
    if box.echo(U64, 4) != 4 { return 2 }
    return 0
}
`,
		"generic-closures.al": `type Cell {
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
`,
		"dispatch.al": `type UserCursor {
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
    return 0
}
`,
	}
	for name, source := range accept {
		t.Run("accept-"+name, func(t *testing.T) {
			files := map[string]string{name: source}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{name}, false), files)
			if len(manifest.diagnostics) != 0 {
				t.Fatalf("M7.5 acceptance diagnostics: %+v", manifest.diagnostics)
			}
		})
	}

	rejections := []struct {
		name, source string
		code         int
	}{
		{"fn-type-key-map", "fn main() -> I32 {\n    var m = Map.new(fn(U64) -> U64, U64)\n    return 0\n}\n", 127},
		{"indirect-call-arity", "fn double(x: U64) -> U64 { return x + x }\nfn main() -> I32 {\n    let f = double\n    if f(1, 2) != 2 { return 1 }\n    return 0\n}\n", 41},
		{"indirect-call-arg-type", "fn double(x: U64) -> U64 { return x + x }\nfn main() -> I32 {\n    let f = double\n    if f(true) != 2 { return 1 }\n    return 0\n}\n", 42},
		{"bare-generic-function", "fn pair(A: type, a: A) -> A { return a }\nfn main() -> I32 {\n    let f = pair\n    return 0\n}\n", 39},
		{"duplicate-impl", "type Box { v: U64 }\ntrait Mark { }\nimpl Mark for Box { }\nimpl Mark for Box { }\nfn main() -> I32 { return 0 }\n", 107},
		{"unknown-trait", "type Box { v: U64 }\nfn f(M: type, b: M) -> U64\nwhere M: Missing {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 108},
		{"trait-arity", "type Box { v: U64 }\ntrait Mark(A: type) { }\nfn f(M: type, b: M) -> U64\nwhere M: Mark {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 109},
		{"impl-target-application", "trait Mark { }\nimpl Mark for Vec(U64) { }\nfn main() -> I32 { return 0 }\n", 110},
		{"impl-target-unknown", "trait Mark { }\nimpl Mark for Missing { }\nfn main() -> I32 { return 0 }\n", 110},
		{"unsatisfied-constraint", "type Box { v: U64 }\ntrait Mark { }\nfn f(M: type, b: M) -> U64\nwhere M: Mark {\n    return 0\n}\nfn main() -> I32 {\n    if f(Box, Box(v: 1)) != 0 { return 1 }\n    return 0\n}\n", 111},
		{"constraint-unknown-param", "type Box { v: U64 }\ntrait Mark { }\nfn f(M: type, b: M) -> U64\nwhere X: Mark {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 112},
		{"impl-where", "type Box { v: U64 }\ntrait Mark { }\nimpl Mark for Box\nwhere Box: Mark {\n}\nfn main() -> I32 { return 0 }\n", 113},
		{"trait-as-type", "trait Mark { }\nfn f(m: Mark) -> U64 { return 0 }\nfn main() -> I32 { return 0 }\n", 114},
		{"self-outside-trait", "fn f(v: Self) -> U64 { return 0 }\nfn main() -> I32 { return 0 }\n", 117},
		{"ambiguous-method", "type Box { v: U64 }\ntrait A { fn fetch(self) -> U64 }\ntrait B { fn fetch(self) -> U64 }\nimpl A for Box { fn fetch(self) -> U64 { return self.v } }\nimpl B for Box { fn fetch(self) -> U64 { return self.v } }\nfn main() -> I32 {\n    let box = Box(v: 1)\n    if box.fetch() != 1 { return 1 }\n    return 0\n}\n", 119},
		{"missing-method", "type Box { v: U64 }\ntrait Getter {\n    fn fetch(self) -> U64\n}\nimpl Getter for Box {\n}\nfn main() -> I32 { return 0 }\n", 121},
		{"extra-method", "type Box { v: U64 }\ntrait Getter {\n    fn fetch(self) -> U64\n}\nimpl Getter for Box {\n    fn fetch(self) -> U64 { return self.v }\n    fn other(self) -> U64 { return 0 }\n}\nfn main() -> I32 { return 0 }\n", 122},
		{"signature-mismatch", "type Box { v: U64 }\ntrait Getter {\n    fn fetch(self) -> U64\n}\nimpl Getter for Box {\n    fn fetch(self) -> Bool { return true }\n}\nfn main() -> I32 { return 0 }\n", 123},
		{"user-eq-impl", "type Box { v: U64 }\nimpl Eq for Box {\n}\nfn main() -> I32 { return 0 }\n", 125},
		{"structural-method-call", "type Box { v: U64 }\nfn main() -> I32 {\n    let a = Box(v: 1)\n    let b = Box(v: 2)\n    if a.eq(b) { return 1 }\n    return 0\n}\n", 126},
		{"float-key-unsupported", "type Bad {\n    ratio: F64\n}\nfn keyed(K: type, k: K) -> U64\nwhere K: Eq + Hash {\n    return 1\n}\nfn main() -> I32 {\n    if keyed(Bad, Bad(ratio: 1.0)) != 1 { return 1 }\n    return 0\n}\n", 111},
		{"generic-method-arity-mismatch", "type Box { v: U64 }\ntrait Combine(Item: type) {\n    fn combine(A: type, self, other: A) -> A\n}\nimpl Combine(U64) for Box {\n    fn combine(self, other: U64) -> U64 { return other }\n}\nfn main() -> I32 { return 0 }\n", 123},
		{"generic-method-concrete-mismatch", "type Box { v: U64 }\ntrait Combine(Item: type) {\n    fn combine(A: type, self, other: A) -> A\n}\nimpl Combine(U64) for Box {\n    fn combine(A: type, self, other: U64) -> U64 { return other }\n}\nfn main() -> I32 { return 0 }\n", 123},
		{"generic-method-builtin-trait", "type Cursor { at: U64 }\nimpl Iterator(U64) for Cursor {\n    fn next(A: type, mut self) -> Option(U64) { return None }\n}\nfn main() -> I32 { return 0 }\n", 123},
		{"generic-method-name-reuse", "trait Two {\n    fn left(A: type, self, a: A) -> A\n    fn right(A: type, self, a: A) -> A\n}\nfn main() -> I32 { return 0 }\n", 3},
		{"generic-impl-method", "type Box { v: U64 }\ntrait Getter {\n    fn fetch(self) -> U64\n}\nimpl Getter for Box {\n    fn fetch(A: type, self) -> U64 { return self.v }\n}\nfn main() -> I32 { return 0 }\n", 123},
		{"closure-slice-capture", "fn capture(s: [U64]) -> fn() -> U64 {\n    let g = fn() -> U64 { return s.len() }\n    return g\n}\nfn main() -> I32 { return 0 }\n", 145},
		{"closure-affine-capture", "type Res {\n    n: U64\n}\nimpl Cleanup for Res {\n    fn cleanup(take self) -> Unit { return }\n}\nfn capture(r: Res) -> fn() -> U64 {\n    let g = fn() -> U64 { return r.n }\n    return g\n}\nfn main() -> I32 { return 0 }\n", 145},
		{"closure-write-capture", "fn main() -> I32 {\n    let total = 0\n    let bump = fn() -> I64 {\n        total = total + 1\n        return total\n    }\n    return 0\n}\n", 28},
	}
	for _, tc := range rejections {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name + ".al": tc.source}
			text := runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true)
			manifest := parseCheckerManifest(t, text, files)
			if len(manifest.diagnostics) != 1 {
				t.Fatalf("expected exactly one rejection diagnostic, got %+v", manifest.diagnostics)
			}
			if manifest.diagnostics[0].kind != tc.code {
				t.Fatalf("expected diagnostic kind %d, got %d", tc.code, manifest.diagnostics[0].kind)
			}
		})
	}
}

// runAlderCheckerPublic runs the checker conformance entry without the
// private bootstrap profile: ordered Map/Set fixtures use the public types,
// so the Map( heuristic in runAlderChecker must not fire for them.
func runAlderCheckerPublic(t *testing.T, exe string, files map[string]string, order []string, fail bool) string {
	t.Helper()
	d := t.TempDir()
	const sentinel = "!alder-core-checker"
	if err := os.WriteFile(filepath.Join(d, sentinel), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for n, s := range files {
		if e := os.WriteFile(filepath.Join(d, n), []byte(s), 0o644); e != nil {
			t.Fatal(e)
		}
	}
	args := append([]string{sentinel}, order...)
	cmd := conformanceCommand(exe, args...)
	cmd.Dir = d
	var out, stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	e := cmd.Run()
	if fail {
		var x *exec.ExitError
		if !errors.As(e, &x) || x.ExitCode() != 1 {
			t.Fatalf("run: %v %s", e, stderr.String())
		}
	} else if e != nil {
		t.Fatalf("run: %v %s\n%s", e, stderr.String(), out.String())
	}
	if stderr.Len() != 0 {
		t.Fatal(stderr.String())
	}
	return out.String()
}

// M7.5 C4: ordered public Map and Set. These fixtures are Alder-only: the
// Go oracle frontend does not implement the ordered collections, so they
// stay out of the shared comparison corpora.
func runAlderM75OrderedCheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"ordered.al": `type Key {
    a: U64
    b: Bool
}

enum Mode {
    Fast
    Slow(code: U32)
}

fn apply(f: fn(U64) -> U64, value: U64) -> U64 { return f(value) }

fn double(x: U64) -> U64 { return x + x }

fn main() -> I32 {
    var scores = Map.new(U64, U64)
    if !scores.insert(1, 10) { return 1 }
    var by_key = Map.new(Key, Vec(U64))
    var empty = Vec.new(U64)
    if !by_key.insert(Key(a: 1, b: true), empty) { return 2 }
    var modes = Map.new(Mode, U64)
    if !modes.insert(Slow(3), 4) { return 3 }
    var seen = Set.new(U64)
    if !seen.insert(7) { return 4 }
    if !seen.contains(7) { return 5 }
    if !seen.remove(7) { return 6 }
    if seen.contains(7) { return 7 }
    let order = scores.keys()
    let texts = scores.values()
    let elements = seen.items()
    var names = Map.new(String, U64)
    if !names.insert("alpha", 1) { return 8 }
    if names.insert("alpha", 2) { return 9 }
    if !names.insert("beta", 3) { return 10 }
    let found = names.get("alpha")
    let got = match found {
        Some(v) => v
        None => 0
    }
    if got != 2 { return 11 }
    let absent = names.get("gamma")
    let none_seen = match absent {
        Some(v) => v
        None => 1
    }
    if none_seen != 1 { return 12 }
    let referenced = double
    if apply(referenced, 3) != 6 { return 16 }
    if referenced(4) != 8 { return 17 }
    var tags = Set.new(Bytes)
    if !tags.insert("one") { return 13 }
    if !tags.contains("one") { return 14 }
    if tags.contains("two") { return 15 }
    return 0
}
`,
	}
	for name, source := range accept {
		t.Run("accept-"+name, func(t *testing.T) {
			files := map[string]string{name: source}
			manifest := parseCheckerManifest(t, runAlderCheckerPublic(t, exe, files, []string{name}, false), files)
			if len(manifest.diagnostics) != 0 {
				t.Fatalf("ordered acceptance diagnostics: %+v", manifest.diagnostics)
			}
		})
	}

	rejections := []struct {
		name, source string
		code         int
	}{
		{"map-key-float", "fn main() -> I32 {\n    var m = Map.new(F64, U64)\n    return 0\n}\n", 127},
		{"map-key-signed", "fn main() -> I32 {\n    var m = Map.new(I64, U64)\n    return 0\n}\n", 127},
		{"map-value-mut-slice", "fn main() -> I32 {\n    var m = Map.new(U64, MutSlice(U64))\n    return 0\n}\n", 128},
		{"map-value-map", "fn main() -> I32 {\n    var m = Map.new(U64, Map(U64, U64))\n    return 0\n}\n", 128},
		{"map-member-key", "type Bad {\n    m: Map(F64, U64)\n}\nfn main() -> I32 { return 0 }\n", 127},
		{"map-member-value", "type Bad {\n    m: Map(U64, [U8])\n}\nfn main() -> I32 { return 0 }\n", 128},
		{"set-member-element", "type Bad {\n    s: Set(F64)\n}\nfn main() -> I32 { return 0 }\n", 127},
		{"map-static-arity", "fn main() -> I32 {\n    var m = Map.new(U64)\n    return 0\n}\n", 144},
		{"set-static-arity", "fn main() -> I32 {\n    var s = Set.new(U64, U64)\n    return 0\n}\n", 144},
		{"map-get-arity", "fn main() -> I32 {\n    var m = Map.new(U64, U64)\n    let found = m.get()\n    return 0\n}\n", 144},
		{"map-insert-arity", "fn main() -> I32 {\n    var m = Map.new(U64, U64)\n    m.insert(1)\n    return 0\n}\n", 144},
		{"map-insert-immutable", "fn main() -> I32 {\n    let m = Map.new(U64, U64)\n    m.insert(1, 2)\n    return 0\n}\n", 101},
		{"map-unknown-method", "fn main() -> I32 {\n    var m = Map.new(U64, U64)\n    m.pop()\n    return 0\n}\n", 61},
		{"map-get-arg-type", "fn main() -> I32 {\n    var m = Map.new(U64, U64)\n    let found = m.get(true)\n    return 0\n}\n", 42},
		{"map-remove-immutable", "fn main() -> I32 {\n    let m = Map.new(U64, U64)\n    m.remove(1)\n    return 0\n}\n", 101},
		{"map-remove-arity", "fn main() -> I32 {\n    var m = Map.new(U64, U64)\n    m.remove()\n    return 0\n}\n", 144},
		{"map-keys-arity", "fn main() -> I32 {\n    var m = Map.new(U64, U64)\n    m.keys(1)\n    return 0\n}\n", 144},
		{"map-remove-storage-value", "fn main() -> I32 {\n    var m = Map.new(U64, Vec(U64))\n    m.remove(1)\n    return 0\n}\n", 129},
		{"map-remove-string-key", "fn main() -> I32 {\n    var m = Map.new(String, U64)\n    m.remove(\"x\")\n    return 0\n}\n", 129},
		{"map-keys-string-key", "fn main() -> I32 {\n    var m = Map.new(String, U64)\n    let ks = m.keys()\n    return 0\n}\n", 129},
		{"set-items-string-element", "fn main() -> I32 {\n    var s = Set.new(String)\n    let xs = s.items()\n    return 0\n}\n", 129},
		{"map-values-storage-value", "fn main() -> I32 {\n    var m = Map.new(U64, String)\n    let texts = m.values()\n    return 0\n}\n", 129},
		{"set-remove-arg-type", "fn main() -> I32 {\n    var s = Set.new(U64)\n    s.remove(true)\n    return 0\n}\n", 42},
	}
	for _, tc := range rejections {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name + ".al": tc.source}
			text := runAlderCheckerPublic(t, exe, files, []string{tc.name + ".al"}, true)
			manifest := parseCheckerManifest(t, text, files)
			if len(manifest.diagnostics) != 1 {
				t.Fatalf("expected exactly one rejection diagnostic, got %+v", manifest.diagnostics)
			}
			if manifest.diagnostics[0].kind != tc.code {
				t.Fatalf("expected diagnostic kind %d, got %d", tc.code, manifest.diagnostics[0].kind)
			}
		})
	}
}

// Rule 89 stays narrow: `mut` on a non-self parameter is an exclusive call
// borrow, legal for affine values, scoped capabilities, and — the one
// copyable exception — a type parameter constrained by a trait with at least
// one `mut self` requirement (the builtin Iterator or a user trait). At a
// call site the argument must be a mutable place: a var binding or another
// mut parameter forwarding the cursor. A let-bound copyable argument would
// advance a discarded copy and is rejected with 146.
func runAlderM75MutCursorCheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"mut-cursor.al": `type Cursor {
    at: U64
}

type Count {
    n: U64
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

trait Stepper(Item: type) {
    fn step(mut self) -> Item
}

impl Stepper(U64) for Count {
    fn step(mut self) -> U64 {
        let out = self.n
        self.n = self.n + 1
        return out
    }
}

fn drain(I: type, T: type, mut iterator: I, total: U64) -> U64
where I: Iterator(T) {
    return match iterator.next() {
        Some(value) => drain(I, T, iterator, total + value)
        None => total
    }
}

fn take_step(S: type, X: type, mut s: S) -> U64
where S: Stepper(X) {
    return s.step()
}

fn main() -> I32 {
    var cursor = Cursor(at: 0)
    if drain(Cursor, U64, cursor, 0) != 3 { return 1 }
    var count = Count(n: 7)
    if take_step(Count, U64, count) != 7 { return 2 }
    return 0
}
`,
	}
	for name, source := range accept {
		t.Run("accept-"+name, func(t *testing.T) {
			files := map[string]string{name: source}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{name}, false), files)
			if len(manifest.diagnostics) != 0 {
				t.Fatalf("mut-cursor acceptance diagnostics: %+v", manifest.diagnostics)
			}
		})
	}

	rejections := []struct {
		name, source string
		code         int
	}{
		{"mut-unconstrained-type-param", "fn bad(T: type, mut t: T) -> Unit {\n    return unit\n}\nfn main() -> I32 { return 0 }\n", 89},
		{"mut-plain-trait-constraint", "type Box { v: U64 }\ntrait Plain(A: type) {\n    fn peek(self) -> A\n}\nimpl Plain(U64) for Box {\n    fn peek(self) -> U64 { return self.v }\n}\nfn f(P: type, mut p: P) -> U64\nwhere P: Plain(U64) {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 89},
		{"mut-concrete-copyable", "fn f(mut value: U64) -> Unit {\n    return unit\n}\nfn main() -> I32 { return 0 }\n", 89},
		{"mut-cursor-let-argument", "type Cursor { at: U64 }\nimpl Iterator(U64) for Cursor {\n    fn next(mut self) -> Option(U64) {\n        return None\n    }\n}\nfn drain(I: type, T: type, mut iterator: I) -> U64\nwhere I: Iterator(T) {\n    return 0\n}\nfn main() -> I32 {\n    let cursor = Cursor(at: 0)\n    if drain(Cursor, U64, cursor) != 0 { return 1 }\n    return 0\n}\n", 146},
		{"mut-cursor-temporary-argument", "type Cursor { at: U64 }\nimpl Iterator(U64) for Cursor {\n    fn next(mut self) -> Option(U64) {\n        return None\n    }\n}\nfn drain(I: type, T: type, mut iterator: I) -> U64\nwhere I: Iterator(T) {\n    return 0\n}\nfn main() -> I32 {\n    if drain(Cursor, U64, Cursor(at: 0)) != 0 { return 1 }\n    return 0\n}\n", 146},
	}
	for _, tc := range rejections {
		t.Run("reject-"+tc.name, func(t *testing.T) {
			files := map[string]string{tc.name + ".al": tc.source}
			text := runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true)
			manifest := parseCheckerManifest(t, text, files)
			if len(manifest.diagnostics) != 1 {
				t.Fatalf("expected exactly one rejection diagnostic, got %+v", manifest.diagnostics)
			}
			if manifest.diagnostics[0].kind != tc.code {
				t.Fatalf("expected diagnostic kind %d, got %d", tc.code, manifest.diagnostics[0].kind)
			}
		})
	}
}
