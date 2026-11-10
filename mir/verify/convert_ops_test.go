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
