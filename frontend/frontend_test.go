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

func compileStrPrivate(t *testing.T, src string) *mir.Module {
	t.Helper()
	m, err := CompilePrivate(src)
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
	compileStrPrivate(t, `
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

	_, err := CompilePrivate(`
type Box(T: type) {
    value: T
}
type Wrapped {
    text: [U8]
}
fn main(d: Domain) -> I32 {
    let storage = __s0_alloc(Box(Wrapped), d, 1)
    return 0
}
`)
	if err == nil || !strings.Contains(err.Error(), "copy-trivial") {
		t.Fatalf("expected concrete generic allocation restriction, got %v", err)
	}

	_, err = CompilePrivate(`
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
    bad: Inner([U8])
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
	tests := []struct {
		src     string
		private bool
	}{
		{src: "fn f(x: I64) -> I64 { return x }\nfn main() -> I64 { return f(1)(2) }"},
		{src: "fn main(d: Domain) -> I32 {\n let m = __s0_map_create(Map(U64, I64), d)\n Set(m, 1, 1)(2)\n return 0\n}", private: true},
		{src: "type Pair(T: type) { value: T }\nfn main() -> I32 {\n let p = Pair(I64)(value: 1)(value: 2)\n return 0\n}"},
	}
	for _, tc := range tests {
		compile := Compile
		if tc.private {
			compile = CompilePrivate
		}
		_, err := compile(tc.src)
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

// TestSmokeDomainSlice exercises domains, alloc, and slices under the
// private bootstrap profile.
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
	compileStrPrivate(t, src)
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

// TestSmokeMap exercises map construction and lookups under the private
// bootstrap profile.
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
	compileStrPrivate(t, src)
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
		private         bool
	}{
		{"semicolon", "fn main() -> I32 { return 0; }", "semicolons are not allowed", false},
		{"same line", "fn main() -> I32 {\n let x = 1 return x\n}", "physical line break", false},
		{"same-line declarations", "type A {} type B {}", "declarations must be separated", false},
		{"expression before operator line break", "fn main() -> I32 {\n let x = 1\n + 2\n return 0\n}", "only inside delimiters", false},
		{"expression after operator line break", "fn main() -> I32 {\n let x = 1 +\n 2\n return 0\n}", "only inside delimiters", false},
		{"postfix line break", "fn f(x: I64) -> I64 { return x }\nfn main() -> I32 {\n let x = f\n (1)\n return 0\n}", "only inside delimiters", false},
		{"braced comma", "type T { a: I64, b: I64 }", "separated by line breaks", false},
		{"field without separator after multiline type", "type T {\n a: Map(\n  U64,\n  I64\n ) b: I64\n}", "fields must be separated", false},
		{"positional record", "type T { a: I64 }\nfn main() -> I32 {\n let x = T(1)\n return 0\n}", "requires named fields", false},
		{"unlabeled payload", "enum E { Bad(I64) }", "requires a label", false},
		{"quoted match wildcard", "fn main() -> I32 {\n return match 0 {\n  \"_\" => 0\n }\n}", "variant name or \"_\"", false},
		{"import outside unsafe", "import c f: fn() -> I64\nfn main() -> I32 {\n let x = f()\n return 0\n}", "only be called inside unsafe c", false},
		{"user call inside unsafe", "fn f() -> I64 { return 1 }\nfn main() -> I32 {\n let x = unsafe c { f() }\n return 0\n}", "direct call to an imported C symbol", false},
		{"nested call inside unsafe", "import c f: fn(I64) -> I64\nfn value() -> I64 { return 1 }\nfn main() -> I32 {\n let x = unsafe c { f(value()) }\n return 0\n}", "cannot contain nested calls", false},
		{"reserved prefix", "fn __s0_user() -> I32 { return 0 }", "reserved function name", false},
		{"old storage alias", "fn main(d: Domain) -> I32 {\n let x = Alloc(I64, d, 1)\n return 0\n}", "unknown function or type \"Alloc\"", true},
	}
	for _, tc := range rejects {
		t.Run(tc.name, func(t *testing.T) {
			compile := Compile
			if tc.private {
				compile = CompilePrivate
			}
			_, err := compile(tc.src)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want diagnostic containing %q", err, tc.want)
			}
		})
	}
}

func TestLexicalBindingsDoNotEscape(t *testing.T) {
	tests := []struct {
		name   string
		params string
		body   string
	}{
		{"branch", "", `if true {
 let hidden = 1
 }
 return hidden
`},
		{"block", "", `{
 let hidden = 1
 }
 return hidden
`},
		{"for", "s: [U8]", `for hidden in s { }
 return hidden
`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Compile("fn main(" + tt.params + ") -> I64 { " + tt.body + " }")
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
fn main(n: I64, s: [U8]) -> I64 {
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

func TestBraceEscapeDecodesToLiteralBraces(t *testing.T) {
	m := compileStr(t, `fn main() -> I32 {
    let text: String = "\{left\} and \{right\}"
    return 0
}`)
	found := false
	for _, constant := range m.Constants {
		if constant.Value.Kind == mir.ConstString && constant.Value.String == "{left} and {right}" {
			found = true
		}
	}
	if !found {
		t.Fatalf("escaped brace string constant not found in %+v", m.Constants)
	}
}

// TestSmokeString exercises distinct String and Bytes value flow.
func TestSmokeString(t *testing.T) {
	src := `
fn string_identity(value: String) -> String { return value }
fn bytes_identity(value: Bytes) -> Bytes { return value }
fn main() -> I32 {
    let text = string_identity("hello")
    let raw: Bytes = bytes_identity("\x00\x80\xff")
    let empty_text: String = ""
    let empty_raw: Bytes = ""
    return 0
}
`
	compileStr(t, src)
}

func TestStringAndBytesContracts(t *testing.T) {
	m := compileStr(t, `
fn identity(T: type, value: T) -> T { return value }
fn main() -> I32 {
    let inferred = "text"
    let text: String = identity("")
    let raw: Bytes = identity("")
    return 0
}
`)
	text := mir.Print(m)
	for _, want := range []string{
		"const @lit.str.c0: string = \"text\"",
		"const @lit.str.c1: string = \"\"",
		"const @lit.str.c2: bytes = \"\"",
		"fn @identity.String(%value: string) -> string",
		"fn @identity.Bytes(%value: bytes) -> bytes",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("String/Bytes MIR is missing %q:\n%s", want, text)
		}
	}

	invalidUTF8 := string([]byte{0xff})
	if _, err := Compile("fn bad() -> String { return \"" + invalidUTF8 + "\" }"); err == nil || !strings.Contains(err.Error(), "String literal is not valid UTF-8") {
		t.Fatalf("invalid UTF-8 String diagnostic = %v", err)
	}
	compileStr(t, "fn raw() -> Bytes { return \""+invalidUTF8+"\" }")

	rejections := []struct {
		src  string
		want string
	}{
		{`fn bad(value: Bytes) -> String { return value }`, "expected String, got Bytes"},
		{`fn bad(value: [U8]) -> String { return value }`, "expected String, got [U8]"},
		{`fn bad(value: String) -> Bytes { return value }`, "expected Bytes, got String"},
		{`fn bad(value: String) -> U8 { return value[0] }`, "expected a slice, got String"},
		{`fn bad(value: Bytes) -> U8 { return value[0] }`, "expected a slice, got Bytes"},
	}
	for _, tc := range rejections {
		if _, err := Compile(tc.src); err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("Compile(%q) = %v, want %q", tc.src, err, tc.want)
		}
	}
}

func TestHexEscapeRequiresTwoDigits(t *testing.T) {
	for _, escape := range []string{`\x`, `\x0`, `\x0g`, `\xg0`} {
		src := `fn bad() -> Bytes { return "` + escape + `" }`
		if _, err := Compile(src); err == nil || !strings.Contains(err.Error(), `invalid escape \x (expected two hexadecimal digits)`) {
			t.Errorf("escape %q diagnostic = %v", escape, err)
		}
	}
}

func TestBootstrapBufferRejectsInvalidSurfaceUses(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want string
	}{
		{
			name: "slice element",
			src: `
type SliceBox { value: [U8] }
fn main(d: Domain) -> I32 {
    let b = __s0_buffer_new(SliceBox, d)
    return 0
}
`,
			want: "buffer element type SliceBox must be copy-trivial",
		},
		{
			name: "nested reference element",
			src: `
type Wrapped { text: [U8] }
fn main(d: Domain) -> I32 {
    let b = __s0_buffer_new(Wrapped, d)
    return 0
}
`,
			want: "buffer element type Wrapped must be copy-trivial",
		},
		{
			name: "mismatched explicit type",
			src:  `fn bad(b: __s0_Buffer(U64)) -> U64 { return __s0_buffer_len(U8, b) }`,
			want: "expected __s0_Buffer(U8), got __s0_Buffer(U64)",
		},
		{
			name: "mismatched value",
			src:  `fn bad(d: Domain, b: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) { return __s0_buffer_append(U64, d, b, true) }`,
			want: "expected U64, got Bool",
		},
		{
			name: "non-u64 index",
			src:  `fn bad(b: __s0_Buffer(U64), i: I64) -> U64 { return __s0_buffer_get(U64, b, i) }`,
			want: "expected U64, got I64",
		},
		{
			name: "set non-u64 index",
			src:  `fn bad(b: __s0_Buffer(U64), i: I64) -> Unit { __s0_buffer_set(U64, b, i, 1) }`,
			want: "expected U64, got I64",
		},
		{
			name: "set mismatched value",
			src:  `fn bad(b: __s0_Buffer(U64)) -> Unit { __s0_buffer_set(U64, b, 0, false) }`,
			want: "expected U64, got Bool",
		},
		{
			name: "non-domain allocation",
			src: `
fn main(d: Bool) -> I32 {
    let b = __s0_buffer_new(U64, d)
    return 0
}
`,
			want: "expected Domain, got Bool",
		},
		{
			name: "opaque field",
			src:  `fn bad(b: __s0_Buffer(U64)) -> U64 { return b.len }`,
			want: "field access on non-struct type __s0_Buffer(U64)",
		},
		{
			name: "wrong arity",
			src:  `fn bad(b: __s0_Buffer(U64)) -> U64 { return __s0_buffer_len(U64) }`,
			want: `"__s0_buffer_len" expects 2 arguments, got 1`,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := CompilePrivate(tc.src)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want diagnostic containing %q", err, tc.want)
			}
		})
	}
}
