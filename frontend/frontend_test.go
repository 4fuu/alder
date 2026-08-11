package frontend

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

func compileStr(t *testing.T, src string) *mir.Module {
	t.Helper()
	m, err := Compile(src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}
	if errs := verify.Module(m); len(errs) > 0 {
		t.Fatalf("lowered MIR failed verification:\n%s", verify.Errors(errs).String())
	}
	return m
}

func TestSplitSourceErrorClassifiesInternalASTErrors(t *testing.T) {
	source := &astError{msg: "ordinary source failure"}
	_, gotSource, gotInternal := splitSourceError(source)
	if gotSource != source || gotInternal != nil {
		t.Fatalf("source error classified as source=%v internal=%v", gotSource, gotInternal)
	}

	internal := &astError{msg: "internal: broken invariant"}
	_, gotSource, gotInternal = splitSourceError(internal)
	if gotSource != nil || gotInternal != internal {
		t.Fatalf("internal error classified as source=%v internal=%v", gotSource, gotInternal)
	}
}

func TestRecursiveSourceRoundTripsWithoutFunctionReordering(t *testing.T) {
	m := compileStr(t, `
fn even(n: U64) -> Bool {
    if n == 0 { return true }
    return odd(n - 1)
}
fn odd(n: U64) -> Bool {
    if n == 0 { return false }
    return even(n - 1)
}
fn main() -> I32 {
    if even(10) { return 0 }
    return 1
}
`)
	for i, name := range []string{"even", "odd", "main"} {
		id, ok := m.Function(name)
		if !ok || int(id) != i {
			t.Fatalf("function %q ID = %d, %v; want %d", name, id, ok, i)
		}
	}
	printed := mir.Print(m)
	reparsed, err := mir.Parse(printed)
	if err != nil {
		t.Fatalf("parse recursive frontend MIR: %v\n%s", err, printed)
	}
	if errs := verify.Module(reparsed); len(errs) != 0 {
		t.Fatalf("verify recursive frontend MIR:\n%s", verify.Errors(errs).String())
	}
	if got := mir.Print(reparsed); got != printed {
		t.Fatalf("recursive MIR did not reach a print fixed point\n--- first ---\n%s\n--- second ---\n%s", printed, got)
	}
}

func TestStandaloneMinusLexesAsUnaryAndBinaryOperator(t *testing.T) {
	compileStr(t, `
fn negate(x: I32) -> I32 { return -x }
fn main() -> I32 {
    let x: I32 = 2
    return x - x
}
`)
}

func TestGenericBodyTypesAndExpectedResultInference(t *testing.T) {
	src := `
fn identity(T: type, x: T) -> T {
    let y: T = x
    return identity(T, y)
}
fn empty(T: type) -> Option(T) { return None
 }
fn main() -> I32 {
    let x: Option(I64) = empty()
    let y = identity(I64, 1)
    return 0
}
`
	compileStr(t, src)
}

func TestGenericInferenceThroughUnaryEnumConstructors(t *testing.T) {
	compileStr(t, `
enum Box(T: type) {
    Boxed(value: T)
}
fn optionID(T: type, x: Option(T)) -> Option(T) { return x
}
fn okID(T: type, x: Result(T, I32)) -> Result(T, I32) { return x
}
fn errID(T: type, x: Result(I32, T)) -> Result(I32, T) { return x
}
fn boxID(T: type, x: Box(T)) -> Box(T) { return x
}
fn main() -> I32 {
    let a = optionID(Some(1))
    let b = okID(Ok(2))
    let c = errID(Err(3))
    let d = boxID(Boxed(4))
    return 0
}
`)
}

func TestCompileTimeTypeParametersMustComeFirst(t *testing.T) {
	_, err := Compile(`
fn bad(x: I64, T: type) -> T { return x
}
`)
	if err == nil || !strings.Contains(err.Error(), "compile-time type parameters must precede runtime parameters") {
		t.Fatalf("expected parameter-order diagnostic, got %v", err)
	}
}

func TestCheckedFailureDoesNotRequireFabricatedResult(t *testing.T) {
	m := compileStr(t, `
fn retain(s: String, n: U64) -> String {
    let checked = n + 1
    return s
}
fn main() -> I32 { return 0 }
`)
	text := mir.Print(m)
	if !strings.Contains(text, "panic\n") || strings.Contains(text, "fail ") {
		t.Fatalf("checked failure did not use valueless panic:\n%s", text)
	}
}

func TestGenericCallsRejectPartialExplicitArguments(t *testing.T) {
	src := `
fn choose(A: type, B: type, a: A, b: B) -> A { return a
 }
fn main() -> I32 { let x = choose(I64, 1, true)
 return 0
 }
`
	_, err := Compile(src)
	if err == nil || !strings.Contains(err.Error(), "either zero or all 2 type arguments") {
		t.Fatalf("expected partial type argument diagnostic, got %v", err)
	}
}

func TestPolymorphicRecursionRejected(t *testing.T) {
	src := `
fn recurse(T: type, x: T) -> Unit { recurse(Option(T), Some(x))
 }
fn main() -> I32 { recurse(I64, 1)
 return 0
 }
`
	_, err := Compile(src)
	if err == nil || !strings.Contains(err.Error(), "unsupported polymorphic recursion") {
		t.Fatalf("expected polymorphic recursion diagnostic, got %v", err)
	}
}

func TestReturningIfElseLowersToVerifiedMIR(t *testing.T) {
	compileStr(t, `
fn choose(c: Bool) -> I64 {
    if c {
        return 1
    } else {
        return 2
    }
}
fn main() -> I32 {
    if choose(true) != 1 {
        return 1
    }
    return 0
}
`)
}

func TestGenericAggregateRestrictionsUseConcreteFields(t *testing.T) {
	compileStr(t, `
type Key(T: type) {
    value: T
}
fn use(K: type, V: type, m: Map(K, V)) -> Unit {
}
fn main(d: Domain) -> I32 {
    let m = __s0_map_create(Map(Key(U64), I64), d)
    use(Key(U64), I64, m)
    return 0
}
`)

	_, err := Compile(`
type Box(T: type) {
    value: T
}
fn main(d: Domain) -> I32 {
    let storage = __s0_alloc(Box(String), d, 1)
    return 0
}
`)
	if err == nil || !strings.Contains(err.Error(), "copy-trivial") {
		t.Fatalf("expected concrete generic allocation restriction, got %v", err)
	}

	_, err = Compile(`
fn make(K: type, V: type, d: Domain) -> Map(K, V) {
    return __s0_map_create(Map(K, V), d)
}
fn main(d: Domain) -> I32 {
    let m = make(I64, I64, d)
    return 0
}
`)
	if err == nil || !strings.Contains(err.Error(), "Map key type I64 is not supported") {
		t.Fatalf("expected invalid concrete generic map key rejection, got %v", err)
	}

	_, err = Compile(`
type Box(T: type) {
    value: T
}
fn main() -> I32 {
    let value: Box = Box(value: 1)
    return 0
}
`)
	if err == nil || !strings.Contains(err.Error(), `"Box" expects 1 type arguments, got 0`) {
		t.Fatalf("expected bare generic type rejection, got %v", err)
	}

	_, err = Compile(`
type Outer {
    bad: Inner(String)
}
type Inner(T: type) {
    values: [T]
}
fn main() -> I32 {
    return 0
}
`)
	if err == nil || !strings.Contains(err.Error(), "contains a slice or reference") {
		t.Fatalf("expected forward generic nested-slice rejection, got %v", err)
	}
}

func TestChainedCallsRejected(t *testing.T) {
	tests := []string{
		"fn f(x: I64) -> I64 { return x }\nfn main() -> I64 { return f(1)(2) }",
		"fn main(d: Domain) -> I32 {\n let m = __s0_map_create(Map(U64, I64), d)\n Set(m, 1, 1)(2)\n return 0\n}",
		"type Pair(T: type) { value: T }\nfn main() -> I32 {\n let p = Pair(I64)(value: 1)(value: 2)\n return 0\n}",
	}
	for _, src := range tests {
		_, err := Compile(src)
		if err == nil || !strings.Contains(err.Error(), "chained calls") {
			t.Fatalf("expected chained-call rejection, got %v", err)
		}
	}
}

// TestSmokeBasic compiles a small program through the whole pipeline.
func TestSmokeBasic(t *testing.T) {
	src := `
fn add(a: I64, b: I64) -> I64 {
    return a + b
}

fn main() -> I32 {
    let x = add(20, 22)
    if x != 42 {
        return 1
    }
    return 0
}
`
	m := compileStr(t, src)
	if len(m.Functions) != 2 {
		t.Fatalf("expected 2 functions, got %d", len(m.Functions))
	}
	out := mir.Print(m)
	if !strings.Contains(out, "fn @add") || !strings.Contains(out, "int.add.checked") {
		t.Fatalf("unexpected MIR:\n%s", out)
	}
}

// TestSmokeStructEnum exercises structs, enums, and match.
func TestSmokeStructEnum(t *testing.T) {
	src := `
type Point {
    x: I64
    y: I64
}

enum Shape {
    Circle(radius: I64)
    Dot
}

fn area(s: Shape) -> I64 {
    return match s {
        Circle(r) => r * r
        Dot => 0
    }
}

fn main() -> I32 {
    let p = Point(x: 3, y: 4)
    if p.x + p.y != 7 {
        return 1
    }
    if area(Circle(5)) != 25 {
        return 2
    }
    if area(Dot) != 0 {
        return 3
    }
    return 0
}
`
	compileStr(t, src)
}

// TestSmokeOptionResult exercises Option/Result and try.
func TestSmokeOptionResult(t *testing.T) {
	src := `
fn half(n: I64) -> Option(I64) {
    if n % 2 == 0 {
        return Some(n / 2)
    }
    return None
}

fn checked(n: I64, d: I64) -> Result(I64, I64) {
    if d == 0 {
        return Err(1)
    }
    return Ok(n / d)
}

fn propagate(d: I64) -> Result(I64, I64) {
    let q = try checked(10, d)
    return Ok(q)
}

fn main() -> I32 {
    let h = half(8)
    if match h {
        Some(v) => v
        None => 0
    } != 4 {
        return 1
    }
    let p = propagate(0)
    if match p {
        Ok(v) => v
        Err(e) => e
    } != 1 {
        return 2
    }
    return 0
}
`
	compileStr(t, src)
}

// TestSmokeDomainSlice exercises domains, alloc, and slices.
func TestSmokeDomainSlice(t *testing.T) {
	src := `
fn fill(d: Domain, n: U64) -> I64 {
    let buf = __s0_alloc(I64, d, n)
    var i: U64 = 0
    while i < n {
        buf[i] = 3
        i = i + 1
    }
    return buf[0]
}

fn main(d: Domain) -> I32 {
    let v = fill(d, 4)
    if v != 3 {
        return 1
    }
    return 0
}
`
	compileStr(t, src)
}

// TestSmokeGeneric exercises generic functions and inference.
func TestSmokeGeneric(t *testing.T) {
	src := `
fn identity(T: type, x: T) -> T {
    return x
}

fn twice(A: type, x: A, y: A) -> A {
    return x
}

fn main() -> I32 {
    if identity(7) != 7 {
        return 1
    }
    if identity(I64, 8) != 8 {
        return 2
    }
    if twice(1, 2) != 1 {
        return 3
    }
    return 0
}
`
	compileStr(t, src)
}

// TestSmokeMap exercises map construction and lookups.
func TestSmokeMap(t *testing.T) {
	src := `
fn main(d: Domain) -> I32 {
    var m = __s0_map_create(Map(U64, I64), d)
    Set(m, 1, 100)
    Set(m, 2, 200)
    let a = Get(m, 1)
    if match a {
        Some(v) => v
        None => 0
    } != 100 {
        return 1
    }
    let b = Get(m, 3)
    if match b {
        Some(v) => v
        None => 0
    } != 0 {
        return 2
    }
    let r = Remove(m, 2)
    if !r {
        return 3
    }
    let c = Get(m, 2)
    if match c {
        Some(v) => v
        None => 1
    } != 1 {
        return 4
    }
    return 0
}
`
	compileStr(t, src)
}

// TestSmokeCleanup exercises scoped cleanup with an observable side effect.
func TestSmokeCleanup(t *testing.T) {
	src := `
import c counter: fn(I64) -> Unit

fn close(x: I64) -> Unit {
    unsafe c { counter(x) }
}

fn main() -> I32 {
    using h = 5 with close
    return 0
}
`
	compileStr(t, src)
}

func TestM4SurfaceSyntax(t *testing.T) {
	compileStr(t, `
import c value: fn() -> I64
type Pair {
    first: I64
    second: I64
}
enum E {
    Has(value: I64)
    Empty
}
fn main() -> I32 {
    let p = Pair(
        second: unsafe c { value() },
        first: 1,
    )
	let sum = (
		1 +
		2
	)
    return 0
}
`)

	rejects := []struct {
		name, src, want string
	}{
		{"semicolon", "fn main() -> I32 { return 0; }", "semicolons are not allowed"},
		{"same line", "fn main() -> I32 {\n let x = 1 return x\n}", "physical line break"},
		{"same-line declarations", "type A {} type B {}", "declarations must be separated"},
		{"expression before operator line break", "fn main() -> I32 {\n let x = 1\n + 2\n return 0\n}", "only inside delimiters"},
		{"expression after operator line break", "fn main() -> I32 {\n let x = 1 +\n 2\n return 0\n}", "only inside delimiters"},
		{"postfix line break", "fn f(x: I64) -> I64 { return x }\nfn main() -> I32 {\n let x = f\n (1)\n return 0\n}", "only inside delimiters"},
		{"braced comma", "type T { a: I64, b: I64 }", "separated by line breaks"},
		{"field without separator after multiline type", "type T {\n a: Map(\n  U64,\n  I64\n ) b: I64\n}", "fields must be separated"},
		{"positional record", "type T { a: I64 }\nfn main() -> I32 {\n let x = T(1)\n return 0\n}", "requires named fields"},
		{"unlabeled payload", "enum E { Bad(I64) }", "requires a label"},
		{"import outside unsafe", "import c f: fn() -> I64\nfn main() -> I32 {\n let x = f()\n return 0\n}", "only be called inside unsafe c"},
		{"user call inside unsafe", "fn f() -> I64 { return 1 }\nfn main() -> I32 {\n let x = unsafe c { f() }\n return 0\n}", "direct call to an imported C symbol"},
		{"nested call inside unsafe", "import c f: fn(I64) -> I64\nfn value() -> I64 { return 1 }\nfn main() -> I32 {\n let x = unsafe c { f(value()) }\n return 0\n}", "cannot contain nested calls"},
		{"reserved prefix", "fn __s0_user() -> I32 { return 0 }", "reserved function name"},
		{"old storage alias", "fn main(d: Domain) -> I32 {\n let x = Alloc(I64, d, 1)\n return 0\n}", "unknown function or type \"Alloc\""},
	}
	for _, tc := range rejects {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Compile(tc.src)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want diagnostic containing %q", err, tc.want)
			}
		})
	}
}

func TestLexicalBindingsDoNotEscape(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"branch", `if true {
 let hidden = 1
 }
 return hidden
`},
		{"block", `{
 let hidden = 1
 }
 return hidden
`},
		{"for", `for hidden in "x" { }
 return hidden
`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Compile("fn main() -> I64 { " + tt.body + " }")
			if err == nil || !strings.Contains(err.Error(), `unknown name "hidden"`) {
				t.Fatalf("expected escaped binding rejection, got %v", err)
			}
		})
	}
}

func TestDisjointBlocksMayReuseBindings(t *testing.T) {
	compileStr(t, `
fn main() -> I64 {
    {
 let value = 1
 }
    {
 let value = 2
 }
    if true {
 let branch = 3
 } else {
 let branch = 4
 }
    return 0
}
`)
}

func TestScopedCleanupMIRVerifiesOnFallthroughAndFailure(t *testing.T) {
	m := compileStr(t, `
fn close(x: I64) -> Unit { }
fn main(n: I64, s: String) -> I64 {
    using outer = 1 with close
    if n > 0 {
        using inner = 2 with close
        let checked = n + 1
    }
    {
 using indexed = 3 with close
 let value = s[9]
 }
    return 0
}
`)
	text := mir.Print(m)
	if strings.Count(text, "cleanup.scope.run") < 3 || strings.Count(text, "panic\n") < 2 {
		t.Fatalf("expected scoped normal and failure cleanup paths in MIR:\n%s", text)
	}
}

// TestSmokeString exercises string literals and iteration.
func TestSmokeString(t *testing.T) {
	src := `
fn main() -> I32 {
    let s = "hello"
    if len(s) != 5 {
        return 1
    }
    if s[1] != 101 {
        return 2
    }
    var sum: U64 = 0
    for c in s {
        sum = sum + 1
    }
    if sum != 5 {
        return 3
    }
    let tail = range(s, 1, 3)
    if len(tail) != 2 {
        return 4
    }
    return 0
}
`
	compileStr(t, src)
}
