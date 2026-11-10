package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The M8 integer conversion methods: int.convert.checked widens into
// option(T) (none out of range, some in range) and int.convert.wrap keeps
// the value's low bits at the target width, both carrying the target type in
// the type slot with no failure edge. The total to_T lowers to int.zext or
// int.sext, which the existing conversion rules already pin. These fixtures
// exercise the textual format, the verifier, and the printer round trip for
// the two new operations. The operations ride MIR format 6.
const convertOpsHeader = `mir 6
`

func TestConvertOpsAccepted(t *testing.T) {
	const text = convertOpsHeader + `
fn @conv(%u: u32, %s: i64, %b: i8) -> option(i64) {
entry:
  %wide = int.convert.checked %u, i64
  %wrap = int.convert.wrap %s, u8
  %up = int.zext %wrap, u64
  %sn = int.sext %b, i64
  return %wide
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v\n%s", err, text)
	}
	if errs := Module(m); len(errs) != 0 {
		t.Fatalf("module rejected:\n%s", Errors(errs).String())
	}
	printed := mir.Print(m)
	if _, err := mir.Parse(printed); err != nil {
		t.Fatalf("reparse printed module: %v\n%s", err, printed)
	}
	for _, name := range []string{
		"int.convert.checked", "int.convert.wrap",
	} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
}

func TestConvertOpsRejected(t *testing.T) {
	cases := []struct {
		name string
		text string
	}{
		{
			"checked-on-string",
			convertOpsHeader + `
fn @conv(%t: string) -> option(i64) {
entry:
  %r = int.convert.checked %t, i64
  return %r
}
`,
		},
		{
			"checked-non-integer-target",
			convertOpsHeader + `
fn @conv(%u: u32) -> option(f32) {
entry:
  %r = int.convert.checked %u, f32
  return %r
}
`,
		},
		{
			"checked-missing-target",
			convertOpsHeader + `
fn @conv(%u: u32) -> option(i64) {
entry:
  %r = int.convert.checked %u
  return %r
}
`,
		},
		{
			"checked-result-not-option",
			convertOpsHeader + `
fn @conv(%u: u32) -> i64 {
entry:
  %r = int.convert.checked %u, i64
  return %r
}
`,
		},
		{
			"wrap-non-integer-target",
			convertOpsHeader + `
fn @conv(%u: u32) -> string {
entry:
  %r = int.convert.wrap %u, string
  return %r
}
`,
		},
		{
			"wrap-string-value",
			convertOpsHeader + `
fn @conv(%t: string) -> u8 {
entry:
  %r = int.convert.wrap %t, u8
  return %r
}
`,
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			m, err := mir.Parse(tc.text)
			if err != nil {
				return
			}
			if errs := Module(m); len(errs) == 0 {
				t.Fatalf("fixture accepted:\n%s", tc.text)
			}
		})
	}
}

func TestConvertOpsInference(t *testing.T) {
	const text = convertOpsHeader + `
fn @conv(%u: u32, %s: i8) -> option(i64) {
entry:
  %r = int.convert.checked %u, i64
  %w = int.convert.wrap %s, u8
  return %r
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v\n%s", err, text)
	}
	fn := m.Functions[0]
	checked := fn.Blocks[0].Instrs[0]
	wrap := fn.Blocks[0].Instrs[1]
	got, ok := m.InferResultType(fn, &checked)
	if !ok || got != m.Option(mir.TypeI64) {
		t.Fatalf("checked inference: got %v ok=%v, want option(i64)", got, ok)
	}
	got, ok = m.InferResultType(fn, &wrap)
	if !ok || got != mir.TypeU8 {
		t.Fatalf("wrap inference: got %v ok=%v, want u8", got, ok)
	}
}

// The M8 C-boundary conversion operations: c.num.try wraps an integer
// crossing of the Alder/C boundary (or an f64 to c_float narrowing) into
// option(T), c.num.wrap keeps an integer crossing's low bits at the target
// width, and c.num.cast moves between pairs that cannot lose value bits
// (integer crossings and float pairs that preserve precision, including the
// widening c_float to f64). The type operand of c.num.try is the whole
// option type; the wrap and cast operands are the target scalar. The
// endpoints must live on opposite sides of the boundary, so an operation
// between two Alder types or two c scalars is invalid.
const cNumOpsHeader = `mir 6
`

func TestCNumOpsAccepted(t *testing.T) {
	const text = cNumOpsHeader + `
fn @cconv(%u: u32, %i: i32, %f: f64, %cf: c_float) -> option(c_size) {
entry:
  %t = c.num.try %u, option(c_size)
  %w = c.num.wrap %i, c_ushort
  %k = c.num.cast %cf, f64
  %n = c.num.try %f, option(c_float)
  return %t
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v\n%s", err, text)
	}
	if errs := Module(m); len(errs) != 0 {
		t.Fatalf("module rejected:\n%s", Errors(errs).String())
	}
	printed := mir.Print(m)
	if _, err := mir.Parse(printed); err != nil {
		t.Fatalf("reparse printed module: %v\n%s", err, printed)
	}
	for _, name := range []string{
		"c.num.try", "c.num.wrap", "c.num.cast",
	} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
}

func TestCNumOpsRejected(t *testing.T) {
	cases := []struct {
		name string
		text string
	}{
		{
			"try-same-world",
			cNumOpsHeader + `
fn @conv(%u: u32) -> option(i64) {
entry:
  %r = c.num.try %u, option(i64)
  return %r
}
`,
		},
		{
			"try-result-not-option",
			cNumOpsHeader + `
fn @conv(%u: u32) -> c_size {
entry:
  %r = c.num.try %u, c_size
  return %r
}
`,
		},
		{
			"try-widening-float",
			cNumOpsHeader + `
fn @conv(%f: f32) -> option(c_double) {
entry:
  %r = c.num.try %f, option(c_double)
  return %r
}
`,
		},
		{
			"try-string-value",
			cNumOpsHeader + `
fn @conv(%s: string) -> option(c_size) {
entry:
  %r = c.num.try %s, option(c_size)
  return %r
}
`,
		},
		{
			"wrap-float-pair",
			cNumOpsHeader + `
fn @conv(%f: f64) -> c_float {
entry:
  %r = c.num.wrap %f, c_float
  return %r
}
`,
		},
		{
			"wrap-same-world",
			cNumOpsHeader + `
fn @conv(%u: u32) -> u8 {
entry:
  %r = c.num.wrap %u, u8
  return %r
}
`,
		},
		{
			"cast-same-world",
			cNumOpsHeader + `
fn @conv(%u: u32) -> i64 {
entry:
  %r = c.num.cast %u, i64
  return %r
}
`,
		},
		{
			"cast-narrowing-float",
			cNumOpsHeader + `
fn @conv(%f: f64) -> c_float {
entry:
  %r = c.num.cast %f, c_float
  return %r
}
`,
		},
		{
			"cast-string",
			cNumOpsHeader + `
fn @conv(%s: string) -> c_size {
entry:
  %r = c.num.cast %s, c_size
  return %r
}
`,
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			m, err := mir.Parse(tc.text)
			if err != nil {
				return
			}
			if errs := Module(m); len(errs) == 0 {
				t.Fatalf("fixture accepted:\n%s", tc.text)
			}
		})
	}
}

func TestCNumOpsInference(t *testing.T) {
	const text = cNumOpsHeader + `
fn @conv(%u: u32, %i: i32, %cf: c_float) -> option(c_size) {
entry:
  %t = c.num.try %u, option(c_size)
  %w = c.num.wrap %i, c_ushort
  %k = c.num.cast %cf, f64
  return %t
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v\n%s", err, text)
	}
	fn := m.Functions[0]
	try := fn.Blocks[0].Instrs[0]
	wrap := fn.Blocks[0].Instrs[1]
	cast := fn.Blocks[0].Instrs[2]
	got, ok := m.InferResultType(fn, &try)
	if !ok || got != m.Option(m.CRaw(uint64(mir.CScalarSize))) {
		t.Fatalf("try inference: got %v ok=%v, want option(c_size)", got, ok)
	}
	got, ok = m.InferResultType(fn, &wrap)
	if !ok || got != m.CRaw(uint64(mir.CScalarUShort)) {
		t.Fatalf("wrap inference: got %v ok=%v, want c_ushort", got, ok)
	}
	got, ok = m.InferResultType(fn, &cast)
	if !ok || got != mir.TypeF64 {
		t.Fatalf("cast inference: got %v ok=%v, want f64", got, ok)
	}
}
