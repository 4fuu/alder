package mir

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func goldenFiles(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join("testdata", "golden", "*.mir"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("no golden fixtures found")
	}
	return files
}

func allMIRFixtureFiles(t *testing.T) []string {
	t.Helper()
	var files []string
	for _, dir := range []string{
		filepath.Join("testdata", "golden"),
		filepath.Join("verify", "testdata", "verify", "accept"),
		filepath.Join("verify", "testdata", "verify", "reject"),
	} {
		got, err := filepath.Glob(filepath.Join(dir, "*.mir"))
		if err != nil {
			t.Fatal(err)
		}
		files = append(files, got...)
	}
	if len(files) == 0 {
		t.Fatal("no MIR fixtures found")
	}
	sort.Strings(files)
	return files
}

// TestGoldenRoundTrip pins the printer to the golden files and checks that
// parse-print-parse is stable: printing a parsed module reproduces the file
// byte for byte, and re-parsing the printed text yields the same text again.
func TestGoldenRoundTrip(t *testing.T) {
	for _, path := range goldenFiles(t) {
		name := filepath.Base(path)
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m1, err := Parse(string(text))
		if err != nil {
			t.Fatalf("%s: parse: %v", name, err)
		}
		out1 := Print(m1)
		if out1 != string(text) {
			t.Errorf("%s: print(parse(x)) != x\n--- got ---\n%s\n--- want ---\n%s", name, out1, text)
			continue
		}
		m2, err := Parse(out1)
		if err != nil {
			t.Fatalf("%s: reparse: %v", name, err)
		}
		out2 := Print(m2)
		if out2 != out1 {
			t.Errorf("%s: parse-print-parse not stable\n--- first ---\n%s\n--- second ---\n%s", name, out1, out2)
		}
	}
}

// TestU64ConstPatternRoundTrip pins the u64 constant representation: the
// signed field holds the 64-bit pattern and the printed form is the
// pattern's unsigned decimal.
func TestU64ConstPatternRoundTrip(t *testing.T) {
	text := "mir 1\n\nconst @max: u64 = 18446744073709551615\nconst @small: u64 = 5\nfn @f() -> u64 {\nbb0:\n  %x = const.get @max\n  %s = const.get @small\n  %y = int.add.wrapping %x, %s\n  return %y\n}\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if got := m.Constants[0].Value.Int; got != -1 {
		t.Fatalf("u64 max pattern: got %d, want -1", got)
	}
	out := Print(m)
	if !strings.Contains(out, "const @max: u64 = 18446744073709551615") {
		t.Fatalf("printed u64 max: %s", out)
	}
	if strings.Contains(out, "const @small: u64 = -") {
		t.Fatalf("small u64 const printed signed: %s", out)
	}
	m2, err := Parse(out)
	if err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if Print(m2) != out {
		t.Fatalf("parse-print-parse not stable:\n%s\n---\n%s", out, Print(m2))
	}
}

// TestParsePrintParseIterated runs the parse-print cycle repeatedly and
// requires stability from the first printed output onward.
func TestParsePrintParseIterated(t *testing.T) {
	for _, path := range allMIRFixtureFiles(t) {
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		prev := string(text)
		for i := 0; i < 5; i++ {
			m, err := Parse(prev)
			if err != nil {
				t.Fatalf("%s: iteration %d: %v", path, i, err)
			}
			prev = Print(m)
		}
		m, err := Parse(prev)
		if err != nil {
			t.Fatalf("%s: final parse: %v", path, err)
		}
		if got := Print(m); got != prev {
			t.Errorf("%s: output drifted across parse-print cycles", path)
		}
	}
}

func TestPanicParsePrintParse(t *testing.T) {
	const text = "mir 2\n\nfn @f() {\nbb0:\n  panic\n}\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(m); got != text {
		t.Fatalf("printed panic differs:\n%s", got)
	}
	reparsed, err := Parse(Print(m))
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(reparsed); got != text {
		t.Fatalf("reprinted panic differs:\n%s", got)
	}
}

func TestAllocCheckedParsePrintParse(t *testing.T) {
	const text = "mir 3\n\nfn @f(%d: domain_handle, %n: u64, %x: i64, %y: i64) -> i64 {\nbb0:\n  %p = alloc.checked %d, u8, %n else bb1(%y, %x)\n  return %x\n\nbb1(%a: i64, %b: i64):\n  return %a\n}\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(m); got != text {
		t.Fatalf("printed alloc.checked differs:\n%s", got)
	}
	reparsed, err := Parse(Print(m))
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(reparsed); got != text {
		t.Fatalf("reprinted alloc.checked differs:\n%s", got)
	}
}

func TestArrayParsePrintParse(t *testing.T) {
	const text = "mir 3\n\nfn @array_ops(%x: i64, %y: i64, %i: u64) -> array(i64, 2) {\nbb0:\n  %a = aggregate.construct array(i64, 2) { %x, %y }\n  %p = array.index.checked %a, %i else bb_fail\n  store deref %p, %x\n  return %a\n\nbb_fail:\n  panic\n}\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(m); got != text {
		t.Fatalf("printed array MIR differs:\n%s", got)
	}
	arrayType := m.Functions[0].Result
	if m.Types[arrayType].Kind != TypeArray || m.Types[arrayType].Elem != TypeI64 || m.Types[arrayType].Length != 2 {
		t.Fatalf("parsed array type = %+v", m.Types[arrayType])
	}
}

// TestParseValueIDs verifies that parsing assigns deterministic IDs: the same
// text parses to modules whose printed forms and value identities agree.
func TestSliceToBytesParsePrintParse(t *testing.T) {
	const text = "mir 6\n\nfn @f(%d: domain_handle, %v: slice(u8)) -> bytes {\nbb0:\n  %b = slice.to_bytes %d, %v else bb_fail\n  return %b\n\nbb_fail:\n  panic\n}\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(m); got != text {
		t.Fatalf("printed slice.to_bytes differs:\n%s", got)
	}
	reparsed, err := Parse(Print(m))
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(reparsed); got != text {
		t.Fatalf("reprinted slice.to_bytes differs:\n%s", got)
	}
}

func TestParseValueIDs(t *testing.T) {
	text := `mir 1

fn @f(%a: i64, %b: i64) -> i64 {
bb0:
  %sum = int.add.checked %a, %b else bb1
  return %sum

bb1:
  %z = const.get @k
  return %z
}
`
	// The const must be declared before use; add it to the text.
	text = "mir 1\n\nconst @k: i64 = 0\n" + strings.TrimPrefix(text, "mir 1\n")
	m1, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	m2, err := Parse(Print(m1))
	if err != nil {
		t.Fatal(err)
	}
	f1, f2 := m1.Functions[0], m2.Functions[0]
	if len(f1.Values) != len(f2.Values) {
		t.Fatalf("value counts differ: %d vs %d", len(f1.Values), len(f2.Values))
	}
	for i := range f1.Values {
		if f1.Values[i].Name != f2.Values[i].Name || f1.Values[i].Type != f2.Values[i].Type {
			t.Errorf("value %d differs: %+v vs %+v", i, f1.Values[i], f2.Values[i])
		}
	}
	if f1.Blocks[0].Instrs[0].Result != ValueId(2) {
		t.Errorf("first instruction result = %d, want 2", f1.Blocks[0].Instrs[0].Result)
	}
}

// TestParseCommentAndLayout checks that '#' comments are ignored and that
// layout does not change meaning.
func TestParseCommentAndLayout(t *testing.T) {
	text := `mir 1

const @k: i64 = 1
# a comment line
type @T {   # trailing comment
  x: i64
}
fn @f() -> i64 {
  local %l: i64
bb0:
  %c = const.get @k
  return %c
}
`
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if m.Functions[0].Result != TypeI64 || m.Functions[0].Locals[0].Name != "l" {
		t.Error("parsed function shape mismatch")
	}
	if got := Print(m); !strings.Contains(got, "const @k: i64 = 1") {
		t.Errorf("printed module missing const:\n%s", got)
	}
	canonical := Print(m)
	reparsed, err := Parse(canonical)
	if err != nil {
		t.Fatalf("canonical output did not parse: %v", err)
	}
	if got := Print(reparsed); got != canonical {
		t.Errorf("noncanonical input did not reach a print fixed point\n--- first ---\n%s\n--- second ---\n%s", canonical, got)
	}
}

var invalidParseTests = []struct {
	name string
	text string
	want string // expected error substring
}{
	{"missing version", "type @T {}", "expected 'mir <version>'"},
	{"bad version", "mir x\n", "expected a format version number"},
	{"unsupported version", "mir 99\n", "unsupported format version 99"},
	{"panic in legacy version", "mir 1\nfn @f() {\nbb0:\n  panic\n}\n", "panic requires MIR format version 2"},
	{"alloc.checked in format 2", "mir 2\nfn @f(%d: domain_handle, %n: u64) {\nbb0:\n  %p = alloc.checked %d, u8, %n else bb1\n  return\nbb1:\n  return\n}\n", "alloc.checked requires MIR format version 3"},
	{"vec in format 3", "mir 3\nfn @f(%v: vec(u8)) {\nbb0:\n  return\n}\n", "vec requires MIR format version 4"},
	{"unknown declaration", "mir 1\nwat\n", "expected a declaration"},
	{"duplicate type", "mir 1\ntype @T {}\ntype @T {}\n", "duplicate type @T"},
	{"empty function", "mir 1\nfn @f() {}\n", "function must contain at least one block"},
	{"duplicate block", "mir 1\nfn @f() {\nbb0:\n  return\nbb0:\n  return\n}\n", "duplicate block"},
	{"unknown type", "mir 1\nfn @f(%x: @Nope) {\nbb0:\n  return\n}\n", "unknown type @Nope"},
	{"unknown value", "mir 1\nconst @k: i64 = 1\nfn @f() {\nbb0:\n  %y = const.get @k\n  %z = int.add.checked %x, %y else bb0\n  return\n}\n", "unknown value %x"},
	{"duplicate value", "mir 1\nconst @k: i64 = 1\nfn @f() {\nbb0:\n  %a = const.get @k\n  %a = const.get @k\n  return\n}\n", "duplicate value %a"},
	{"duplicate local", "mir 1\nfn @f() {\n  local %slot: i64\n  local %slot: i64\nbb0:\n  return\n}\n", "duplicate local %slot"},
	{"unknown local", "mir 1\nfn @f() {\nbb0:\n  %v = load local %nope\n  return\n}\n", "unknown local %nope"},
	{"unknown block", "mir 1\nfn @f() {\nbb0:\n  jump bb_nope\n}\n", "unknown block"},
	{"unknown function", "mir 1\nfn @f() {\nbb0:\n  %x = call @nope()\n  return\n}\n", "unknown function @nope"},
	{"unknown import", "mir 1\nfn @f() {\nbb0:\n  %x = ffi.call.unsafe @nope()\n  return\n}\n", "unknown import @nope"},
	{"unknown const", "mir 1\nfn @f() {\nbb0:\n  %x = const.get @nope\n  return\n}\n", "unknown constant @nope"},
	{"no terminator", "mir 1\nconst @k: i64 = 1\nfn @f() {\nbb0:\n  %x = const.get @k\n}\n", "has no terminator"},
	{"instruction after terminator", "mir 1\nconst @k: i64 = 1\nfn @f() {\nbb0:\n  return\n  %x = const.get @k\n}\n", "after a terminator"},
	{"second terminator", "mir 1\nfn @f() {\nbb0:\n  return\n  fail %x\n}\n", "after a terminator"},
	{"binding on non-producing op", "mir 1\nconst @k: i64 = 1\nfn @f() {\n  local %l: i64\nbb0:\n  %y = const.get @k\n  %x = store local %l, %y\n  return\n}\n", "produces no value"},
	{"missing binding on producing op", "mir 1\nfn @f() {\nbb0:\n  cleanup.scope.begin\n  return\n}\n", "produces a value"},
	{"checked op without else", "mir 1\nfn @f(%a: i64) {\nbb0:\n  %s = int.add.checked %a, %a\n  return\n}\n", "requires an 'else' failure edge"},
	{"unknown operation", "mir 1\nfn @f() {\nbb0:\n  frobnicate\n  return\n}\n", "unknown operation"},
	{"unterminated string", "mir 1\nconst @k: i64 = \"abc\n", "unterminated string literal"},
	{"bad string escape", "mir 1\nconst @k: i64 = \"\\q\"\n", "invalid string literal"},
	{"int out of range", "mir 1\nconst @k: i64 = 99999999999999999999\n", "out of range"},
	{"incomplete dotted name", "mir 1\nfn @f() {\nbb0:\n  %x = const.get @k.\n  return\n}\nconst @k: i64 = 1\n", "incomplete segment"},
	{"reserved block name", "mir 1\nfn @f() {\nelse:\n  return\n}\n", "reserved"},
	{"reserved variant name", "mir 1\nenum @E {\n  default\n}\n", "reserved"},
	{"unterminated body", "mir 1\nfn @f() {\nbb0:\n  return\n", "unterminated function body"},
	{"garbage after module", "mir 1\n)\n", "expected a declaration"},
	{"bad place", "mir 1\nfn @f() {\nbb0:\n  %v = load frob\n  return\n}\n", "expected a place"},
	{"bad const value", "mir 1\nconst @k: i64 = nope\n", "expected a constant value"},
}

// TestInvalidParseFixtures checks deterministic rejection of malformed input.
func TestInvalidParseFixtures(t *testing.T) {
	for _, tc := range invalidParseTests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(tc.text)
			if err == nil {
				t.Fatalf("parse succeeded; want error containing %q", tc.want)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error %q does not contain %q", err, tc.want)
			}
			// Errors must be deterministic across parses.
			_, err2 := Parse(tc.text)
			if err2 == nil || err2.Error() != err.Error() {
				t.Fatalf("error not deterministic: %q vs %q", err, err2)
			}
		})
	}
}

// TestParseErrorPosition checks that errors carry a line number.
func TestParseErrorPosition(t *testing.T) {
	_, err := Parse("mir 1\n\n\nfn @f() {\nbb0:\n  %x = const.get @nope\n  return\n}\n")
	if err == nil || !strings.HasPrefix(err.Error(), "line 6, column ") {
		t.Fatalf("error missing position: %v", err)
	}
}

func TestParsePredeclaresFunctionHeaders(t *testing.T) {
	text := `mir 1
fn @first() {
bb0:
  call @first()
  call @second()
  return
}
fn @second() {
bb0:
  call @first()
  return
}
fn @cleanup_user() {
bb0:
  %scope = cleanup.scope.begin
  %id = cleanup.push %scope, @later_cleanup, ()
  cleanup.scope.run %scope
  cleanup.scope.end %scope
  return
}
fn @later_cleanup() {
bb0:
  return
}
`
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	for i, name := range []string{"first", "second", "cleanup_user", "later_cleanup"} {
		id, ok := m.Function(name)
		if !ok || id != FunctionId(i) {
			t.Fatalf("function @%s ID = %d, %v; want %d", name, id, ok, i)
		}
	}
	first := m.Functions[0].Blocks[0].Instrs
	if first[0].Callee != 0 || first[1].Callee != 1 {
		t.Fatalf("self/forward callees = %d, %d; want 0, 1", first[0].Callee, first[1].Callee)
	}
	if got := m.Functions[2].Blocks[0].Instrs[1].CleanupFn; got != 3 {
		t.Fatalf("forward cleanup callback = %d, want 3", got)
	}
	printed := Print(m)
	reparsed, err := Parse(printed)
	if err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if got := Print(reparsed); got != printed {
		t.Fatalf("printing did not reach a fixed point\nfirst:\n%s\nsecond:\n%s", printed, got)
	}
}

func TestFunctionPredeclarationBoundaries(t *testing.T) {
	tests := []struct {
		name string
		text string
		want string
	}{
		{"unknown call", "mir 1\nfn @f() {\nbb0:\n  call @missing()\n  return\n}\n", "unknown function @missing"},
		{"unknown cleanup callback", "mir 1\nfn @f() {\nbb0:\n  %s = cleanup.scope.begin\n  %id = cleanup.push %s, @missing, ()\n  return\n}\n", "unknown function @missing"},
		{"duplicate header", "mir 1\nfn @f() {\nbb0:\n  return\n}\nfn @f() {\nbb0:\n  return\n}\n", "duplicate function @f"},
		{"forward type", "mir 1\nfn @f() {\n  local %x: @T\nbb0:\n  return\n}\ntype @T {}\n", "unknown type @T"},
		{"forward constant", "mir 1\nfn @f() -> i64 {\nbb0:\n  %x = const.get @k\n  return %x\n}\nconst @k: i64 = 1\n", "unknown constant @k"},
		{"forward import", "mir 1\nfn @f() {\nbb0:\n  ffi.call.unsafe @puts()\n  return\n}\nimport @puts: fn() -> unit\n", "unknown import @puts"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(tc.text)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Parse error = %v, want substring %q", err, tc.want)
			}
		})
	}
}

func TestParseOwnedStringAndBytesTypes(t *testing.T) {
	const text = "mir 3\n\nconst @s: string = \"hi\"\n\nconst @b: bytes = \"\\000\\200\\377\"\n"
	const want = "mir 3\n\nconst @s: string = \"hi\"\n\nconst @b: bytes = \"\\x00\\x80\\xff\"\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(m); got != want {
		t.Fatalf("round trip mismatch:\n%s", got)
	}
	if m.Types[m.Constants[0].Type].Kind != TypeString || m.Types[m.Constants[1].Type].Kind != TypeBytes {
		t.Fatal("string and bytes did not parse as distinct leaf types")
	}
}

func TestParseVecTypeAndOperations(t *testing.T) {
	const text = "mir 4\n\nfn @vec(%storage: safe_mut(i64), %len: u64, %capacity: u64) -> vec(i64) {\nbb0:\n  %v = vec.construct.checked %storage, %len, %capacity else bad\n  %n = vec.len %v\n  %s = vec.as_slice %v\n  return %v\n\nbad:\n  %empty = vec.new vec(i64)\n  return %empty\n}\n"
	m, err := Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if got := Print(m); got != text {
		t.Fatalf("round trip mismatch:\n%s", got)
	}
	if m.Types[m.Functions[0].Result].Kind != TypeVec {
		t.Fatal("result did not parse as vec")
	}
}
