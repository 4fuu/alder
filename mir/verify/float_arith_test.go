package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The plain IEEE-754 float arithmetic operations: float.add, float.sub,
// float.mul, and float.div both carry one shared float type and produce it,
// none carries a failure edge, and float.div is defined for a zero divisor
// (signed infinity by sign XOR, NaN for 0/0), realized by the C backend's
// runtime helper rather than a bare C division. These fixtures exercise the
// textual format, the verifier, and the printer round trip for the four
// operations. Comparisons already had float.eq through float.ge.
const floatArithHeader = `mir 6
`

func TestFloatArithAccepted(t *testing.T) {
	const text = floatArithHeader + `
fn @f64_arith(%a: f64, %b: f64) -> f64 {
entry:
  %sum = float.add %a, %b
  %diff = float.sub %a, %b
  %prod = float.mul %a, %b
  %quot = float.div %a, %b
  return %quot
}
fn @f32_arith(%a: f32, %b: f32) -> f32 {
entry:
  %sum = float.add %a, %b
  return %sum
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
		"float.add", "float.sub", "float.mul", "float.div",
	} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
}

func TestFloatArithRejected(t *testing.T) {
	cases := []struct {
		name string
		text string
	}{
		{
			"mixed-width-operands",
			floatArithHeader + `
fn @f(%a: f64, %b: f32) -> f64 {
entry:
  %sum = float.add %a, %b
  return %sum
}
`,
		},
		{
			"integer-operands",
			floatArithHeader + `
fn @f(%a: i32, %b: i32) -> i32 {
entry:
  %sum = float.add %a, %b
  return %sum
}
`,
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			m, err := mir.Parse(tc.text)
			if err != nil {
				t.Fatalf("parse fixture: %v\n%s", err, tc.text)
			}
			errs := Module(m)
			if len(errs) == 0 {
				t.Fatalf("invalid float arithmetic accepted:\n%s", tc.text)
			}
		})
	}
}
