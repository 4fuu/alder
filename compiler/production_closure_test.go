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

// Nested closure literals. The inner literal captures the outer closure's
// parameter and a value only the inner literal reads, so the outer
// environment carries the transitive capture; the outer environment records
// the domain it lives in, so the thunk allocates the inner environment beside
// it. The arrow form infers the outer result type from a nested literal, and
// the deep shape nests three levels.
const m75NestedClosureProgram = `fn make(base: U64) -> fn(U64) -> fn(U64) -> U64 {
    let outer = fn(delta: U64) -> fn(U64) -> U64 {
        let inner = fn(x: U64) -> U64 { return x + base + delta }
        return inner
    }
    return outer
}
fn transitive(seed: U64) -> fn() -> fn() -> U64 {
    let outer = fn() -> fn() -> U64 {
        let inner = fn() -> U64 { return seed + 1 }
        return inner
    }
    return outer
}
type Box {
    v: U64
}
fn record_capture(b: Box) -> fn() -> fn() -> U64 {
    let outer = fn() -> fn() -> U64 {
        let inner = fn() -> U64 { return b.v + 1 }
        return inner
    }
    return outer
}
fn arrow(seed: U64) -> fn() -> fn(U64) -> U64 {
    let outer = fn() => fn(x: U64) => x + seed
    return outer
}
fn deep(a: U64) -> fn(U64) -> fn(U64) -> fn(U64) -> U64 {
    let level1 = fn(b: U64) -> fn(U64) -> fn(U64) -> U64 {
        let level2 = fn(c: U64) -> fn(U64) -> U64 {
            let level3 = fn(x: U64) -> U64 { return x + a + b + c }
            return level3
        }
        return level2
    }
    return level1
}
fn main() -> I32 {
    let outer = make(10)
    var pad_a = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad_a.push(1)
        i = i + 1
    }
    let inner = outer(5)
    var pad_b = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_b.push(2)
        i = i + 1
    }
    if inner(2) != 17 { return 1 }
    let t = transitive(4)
    var pad_c = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_c.push(3)
        i = i + 1
    }
    let u = t()
    var pad_d = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_d.push(4)
        i = i + 1
    }
    if u() != 5 { return 2 }
    let r = record_capture(Box(v: 41))
    var pad_g = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_g.push(7)
        i = i + 1
    }
    let ri = r()
    if ri() != 42 { return 5 }
    let af = arrow(6)
    var pad_e = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_e.push(5)
        i = i + 1
    }
    let ag = af()
    if ag(3) != 9 { return 3 }
    let d1 = deep(1)
    let d2 = d1(2)
    let d3 = d2(3)
    var pad_f = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_f.push(6)
        i = i + 1
    }
    if d3(4) != 10 { return 4 }
    return 0
}
`

// A closure may capture a scoped capability when it provably does not escape:
// every read of the value in the owning scope is the callee of a call through
// it. The environment record then holds the view header, so the closure reads
// the original storage; an intervening allocation between creation and the
// call would expose a dangling copy. The shapes cover a direct local call, a
// nested literal whose inner capture is called through an outer local call,
// and a second view of the same vector.
const m75ScopedCaptureProgram = `fn one(seed: U64) -> Vec(U64) {
    var v = Vec.new(U64)
    v.push(seed)
    v.push(seed + 1)
    v.push(seed + 2)
    return v
}
fn view_total(seed: U64) -> U64 {
    let v = one(seed)
    let s = v.slice(0, 3)
    let sum = fn() -> U64 { return s.len() + s[0] + s[1] + s[2] }
    var pad = Vec.new(U64)
    var i: U64 = 0
    while i < 16 {
        pad.push(i)
        i = i + 1
    }
    return sum()
}
fn nested_view_total(seed: U64) -> U64 {
    let v = one(seed)
    let s = v.slice(1, 3)
    let inner = fn() -> U64 { return s.len() + s[0] }
    let outer = fn() -> U64 { return inner() + 10 }
    var pad = Vec.new(U64)
    var i: U64 = 0
    while i < 16 {
        pad.push(i)
        i = i + 1
    }
    return outer()
}
fn tail_len(seed: U64) -> U64 {
    let v = one(seed)
    let s = v.slice(2, 3)
    let only = fn() -> U64 { return s.len() * 100 + s[0] }
    return only()
}
fn main() -> I32 {
    if view_total(10) != 36 { return 1 }
    if nested_view_total(10) != 23 { return 2 }
    if tail_len(10) != 112 { return 3 }
    return 0
}
`

// A scoped-capability capture may also be passed to a parameter that the
// callee provably does not retain: the checker's per-instance retain summary
// proves it from the callee's body, transitively through forwards and
// recursive cycles, and the closure is only used during the call. The shapes
// cover a two-level forward, a literal argument, a method parameter, and a
// recursive callee, each after an intervening allocation so a dangling
// environment would give a wrong answer.
const m75HigherOrderScopedProgram = `fn one(seed: U64) -> Vec(U64) {
    var v = Vec.new(U64)
    v.push(seed)
    v.push(seed + 1)
    return v
}
fn pad(n: U64) -> U64 {
    var v = Vec.new(U64)
    var i: U64 = 0
    while i < n {
        v.push(i)
        i = i + 1
    }
    return v.len()
}
fn apply(f: fn() -> U64) -> U64 {
    return f()
}
fn apply2(f: fn() -> U64) -> U64 {
    return apply(f)
}
fn walk(f: fn(U64) -> U64, n: U64) -> U64 {
    if n == 0 { return f(0) }
    return walk(f, n - 1) + f(n)
}
type Runner {
    base: U64
}
impl Runner {
    fn run(self, f: fn(U64) -> U64, n: U64) -> U64 { return f(n) + self.base }
}
fn through_calls(seed: U64) -> U64 {
    let v = one(seed)
    let s = v.slice(0, 2)
    let g = fn() -> U64 { return s.len() + s[0] }
    let filled = pad(16)
    return apply2(g) + g() + filled - filled
}
fn through_literal(seed: U64) -> U64 {
    let v = one(seed)
    let s = v.slice(0, 2)
    let filled = pad(16)
    return apply2(fn() -> U64 { return s.len() + s[1] }) + filled - filled
}
fn through_method(seed: U64) -> U64 {
    let runner = Runner(base: 5)
    let v = one(seed)
    let s = v.slice(0, 2)
    let g = fn(x: U64) -> U64 { return x + s.len() }
    let filled = pad(16)
    return runner.run(g, 30) + filled - filled
}
fn through_recursion(seed: U64) -> U64 {
    let v = one(seed)
    let s = v.slice(0, 2)
    let g = fn(x: U64) -> U64 { return x + s.len() }
    let filled = pad(16)
    return walk(g, 2) + filled - filled
}
fn main() -> I32 {
    if through_calls(40) != 84 { return 1 }
    if through_literal(40) != 43 { return 2 }
    if through_method(40) != 37 { return 3 }
    if through_recursion(40) != 9 { return 4 }
    return 0
}
`

// Captures of ordinary storage-backed values are independent snapshots. The
// closure sees the length, map entry, and record element it captured even
// after the source is mutated, each call follows an intervening allocation,
// and the shapes cover a closure returned through two levels, a closure
// stored in a vector inside a loop with a per-iteration capture, a closure
// capturing another closure, and a captured string.
const m75CaptureSnapshotProgram = `type Holder {
    items: Vec(U64)
}
fn one(seed: U64) -> Vec(U64) {
    var v = Vec.new(U64)
    v.push(seed)
    return v
}
fn zero() -> U64 { return 0 }
fn ignore(s: String) -> U64 { return 0 }
fn snapshot_vec(seed: U64) -> fn() -> U64 {
    var v = Vec.new(U64)
    v.push(seed)
    let f = fn() -> U64 { return v.len() }
    v.push(seed + 1)
    return f
}
fn snapshot_map(seed: U64) -> fn() -> U64 {
    var m = Map.new(String, U64)
    m.insert("a", seed)
    let f = fn() -> U64 {
        let found = m.get("a")
        return match found {
            Some(x) => x
            None => 0
        }
    }
    m.insert("a", seed + 1)
    return f
}
fn snapshot_holder(seed: U64) -> fn() -> U64 {
    let h = Holder(items: one(seed))
    let f = fn() -> U64 {
        let found = h.items.get(0)
        return match found {
            Some(x) => x
            None => 0
        }
    }
    return f
}
fn snapshot_string(s: String) -> fn() -> String {
    let f = fn() -> String { return s }
    return f
}
fn captured_closure(seed: U64) -> fn(U64) -> U64 {
    let inner = fn(x: U64) => x + seed
    let outer = fn(x: U64) => inner(x) + 1
    return outer
}
fn two_levels(seed: U64) -> fn() -> U64 {
    let f = snapshot_vec(seed)
    var pad = Vec.new(U64)
    var i: U64 = 0
    while i < 8 {
        pad.push(i)
        i = i + 1
    }
    return f
}
fn loop_closures(base: U64) -> Vec(fn() -> U64) {
    var fns = Vec.new(fn() -> U64)
    var i: U64 = 0
    while i < 3 {
        var v = Vec.new(U64)
        v.push(base + i)
        let f = fn() -> U64 {
            let found = v.get(0)
            return match found {
                Some(x) => x
                None => 0
            }
        }
        fns.push(f)
        v.push(99)
        i = i + 1
    }
    return fns
}
fn main() -> I32 {
    let a = snapshot_vec(3)
    var pad_a = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad_a.push(1)
        i = i + 1
    }
    if a() != 1 { return 1 }
    let b = snapshot_map(4)
    var pad_b = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_b.push(2)
        i = i + 1
    }
    if b() != 4 { return 2 }
    let h = snapshot_holder(5)
    var pad_c = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_c.push(3)
        i = i + 1
    }
    if h() != 5 { return 3 }
    let s = snapshot_string("hello")
    let t = s()
    if ignore(t) != 0 { return 4 }
    let c = captured_closure(6)
    var pad_d = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_d.push(4)
        i = i + 1
    }
    if c(1) != 8 { return 5 }
    let d = two_levels(7)
    var pad_e = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_e.push(5)
        i = i + 1
    }
    if d() != 1 { return 6 }
    let fns = loop_closures(10)
    var pad_f = Vec.new(U64)
    i = 0
    while i < 64 {
        pad_f.push(6)
        i = i + 1
    }
    var total: U64 = 0
    var k: U64 = 0
    while k < fns.len() {
        let found = fns.get(k)
        let g = match found {
            Some(x) => x
            None => zero
        }
        total = total + g()
        k = k + 1
    }
    if total != 33 { return 7 }
    return 0
}
`

// A closure with no captures whose body allocates storage needs a domain of
// its own. It takes the caller's domain as a leading hidden parameter, like a
// named function value, so the body can build and return a vector. The shapes
// cover a local closure, one returned from its creating function, and one
// stored in a vector inside a loop.
const m75CaptureFreeAllocationProgram = `fn make_adder() -> fn(U64) -> Vec(U64) {
    let build = fn(n: U64) -> Vec(U64) {
        var v = Vec.new(U64)
        v.push(n)
        return v
    }
    return build
}
fn make_stored() -> Vec(fn(U64) -> Vec(U64)) {
    var fns = Vec.new(fn(U64) -> Vec(U64))
    var i: U64 = 0
    while i < 2 {
        let build = fn(n: U64) -> Vec(U64) {
            var v = Vec.new(U64)
            v.push(n)
            v.push(n + 1)
            return v
        }
        fns.push(build)
        i = i + 1
    }
    return fns
}
fn main() -> I32 {
    let local = fn(n: U64) -> Vec(U64) {
        var v = Vec.new(U64)
        v.push(n)
        return v
    }
    let one = local(3)
    if one.len() != 1 { return 1 }
    let made = make_adder()
    var pad = Vec.new(U64)
    var i: U64 = 0
    while i < 64 {
        pad.push(1)
        i = i + 1
    }
    let two = made(7)
    if two.len() != 1 { return 2 }
    let fns = make_stored()
    var pad2 = Vec.new(U64)
    i = 0
    while i < 64 {
        pad2.push(2)
        i = i + 1
    }
    let found = fns.get(1)
    let g = match found {
        Some(x) => x
        None => local
    }
    let three = g(9)
    if three.len() != 2 { return 3 }
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
		{"m75-nested-closures", m75NestedClosureProgram},
		{"m75-capture-snapshots", m75CaptureSnapshotProgram},
		{"m75-capture-free-allocation", m75CaptureFreeAllocationProgram},
		{"m75-scoped-captures", m75ScopedCaptureProgram},
		{"m75-higher-order-scoped", m75HigherOrderScopedProgram},
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
		{"m75-nested-closures", m75NestedClosureProgram},
		{"m75-capture-snapshots", m75CaptureSnapshotProgram},
		{"m75-capture-free-allocation", m75CaptureFreeAllocationProgram},
		{"m75-scoped-captures", m75ScopedCaptureProgram},
		{"m75-higher-order-scoped", m75HigherOrderScopedProgram},
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
