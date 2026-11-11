package frontend

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The total bitwise family: & | ^ are same-type integer binaries and ~ is the
// integer complement. None carries a failure edge. Precedence follows
// docs/syntax.md: shift binds tighter than &, then ^, then |.
func TestBitwiseOperationsAccepted(t *testing.T) {
	m := compileStr(t, `
fn main() -> I32 {
    let a: U64 = 12
    let b: U64 = 10
    let c = a & b
    let d = a | b
    let e = a ^ b
    let f = ~a
    if c != 8 { return 1 }
    if d != 14 { return 2 }
    if e != 6 { return 3 }
    if f == a { return 4 }
    return 0
}
`)
	printed := strings.TrimSpace(mir.Print(m))
	order := []string{"int.and", "int.or", "int.xor", "int.not"}
	at := 0
	for _, name := range order {
		next := strings.Index(printed[at:], name)
		if next < 0 {
			t.Fatalf("printed MIR is missing %s after offset %d:\n%s", name, at, printed)
		}
		at += next + len(name)
	}
	for _, line := range strings.Split(printed, "\n") {
		if strings.Contains(line, "int.and") || strings.Contains(line, "int.or") ||
			strings.Contains(line, "int.xor") || strings.Contains(line, "int.not") {
			if strings.Contains(line, " else") {
				t.Fatalf("total bitwise operation printed a failure edge: %s", line)
			}
		}
	}
}

func TestBitwisePrecedenceLowersTightestFirst(t *testing.T) {
	m := compileStr(t, `
fn main() -> I32 {
    let one: U32 = 1
    let two: U32 = 2
    let three: U32 = 3
    let four: U32 = 4
    let value = one | two ^ three & four << 1
    return 0
}
`)
	printed := mir.Print(m)
	// The tree is 1 | (2 ^ (3 & (4 << 1))), so the printed instruction order
	// is shl, and, xor, or.
	order := []string{"int.shl.checked", "int.and", "int.xor", "int.or"}
	at := 0
	for _, name := range order {
		next := strings.Index(printed[at:], name)
		if next < 0 {
			t.Fatalf("printed MIR is missing %s after offset %d:\n%s", name, at, printed)
		}
		at += next + len(name)
	}
}

func TestBitwiseRejections(t *testing.T) {
	cases := []struct {
		name, source, want string
	}{
		{
			"bool operand",
			"fn main() -> I32 {\n    let a = true & false\n    return 0\n}\n",
			"operator & requires integer operands, got Bool",
		},
		{
			"float operands",
			"fn main() -> I32 {\n    let a = 1.0 | 2.0\n    return 0\n}\n",
			"operator | requires integer operands, got F64",
		},
		{
			"mixed integer widths",
			"fn main() -> I32 {\n    let a: U8 = 1\n    let b: U64 = 2\n    let c = a ^ b\n    return 0\n}\n",
			"operand: type mismatch: expected U8, got U64",
		},
		{
			"bool complement",
			"fn main() -> I32 {\n    let a = ~true\n    return 0\n}\n",
			"operator ~ requires an integer operand, got Bool",
		},
		{
			"float complement",
			"fn main() -> I32 {\n    let a = ~1.0\n    return 0\n}\n",
			"operator ~ requires an integer operand, got F64",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			_, err := Compile(tc.source)
			if err == nil {
				t.Fatalf("source accepted, want rejection containing %q", tc.want)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %q, want containing %q", err, tc.want)
			}
		})
	}
}
