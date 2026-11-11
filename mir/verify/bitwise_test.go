package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The total bitwise family (MIR operations 103-106) operates on one integer
// type and carries no failure edge. These fixtures exercise the textual format,
// the verifier, and the printer round trip.
const bitwiseHeader = `mir 6
`

func TestBitwiseAccepted(t *testing.T) {
	const text = bitwiseHeader + `
fn @bits(%a: u8, %b: i64) -> u8 {
entry:
  %and = int.and %a, %a
  %or = int.or %a, %a
  %xor = int.xor %a, %a
  %not = int.not %a
  %wide = int.not %b
  %w = int.xor %wide, %wide
  return %and
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
	for _, name := range []string{"int.and", "int.or", "int.xor", "int.not"} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
	for _, line := range strings.Split(printed, "\n") {
		if (strings.Contains(line, "int.and") || strings.Contains(line, "int.or") ||
			strings.Contains(line, "int.xor") || strings.Contains(line, "int.not")) &&
			strings.Contains(line, " else") {
			t.Fatalf("total bitwise operation printed a failure edge: %s", line)
		}
	}
}

func TestBitwiseRejected(t *testing.T) {
	cases := []struct {
		name, text, want string
	}{
		{
			"binary mixed types",
			bitwiseHeader + `
fn @f(%a: i64, %u: u64) {
entry:
  %x = int.and %a, %u
  return
}
`,
			"integer operand",
		},
		{
			"binary float",
			bitwiseHeader + `
fn @f(%a: f64) {
entry:
  %x = int.xor %a, %a
  return
}
`,
			"integer operand",
		},
		{
			"complement float",
			bitwiseHeader + `
fn @f(%a: f64) {
entry:
  %x = int.not %a
  return
}
`,
			"expected an integer",
		},
		{
			"complement bool",
			bitwiseHeader + `
fn @f(%a: bool) {
entry:
  %x = int.not %a
  return
}
`,
			"expected an integer",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			mustReject(t, tc.text, tc.want)
		})
	}
}
