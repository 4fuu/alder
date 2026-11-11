package frontend

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// () is the sole Unit value. It is usable as a return operand, a Unit
// argument, and a unit-payload variant argument, but not as a binding value or
// a standalone statement.
func TestUnitLiteralAccepted(t *testing.T) {
	m := compileStr(t, `
fn accept(value: Unit) -> I32 {
    return 0
}
fn nothing() -> Unit {
    return ()
}
fn main() -> I32 {
    let ok: Result(Unit, I32) = Ok(())
    let some: Option(Unit) = Some(())
    if accept(()) != 0 { return 1 }
    nothing()
    return 0
}
`)
	printed := strings.TrimSpace(mir.Print(m))
	if !strings.Contains(printed, "const @lit.unit") {
		t.Fatalf("printed MIR is missing a unit constant:\n%s", printed)
	}
	if strings.Contains(printed, "enum.construct result(unit, i32), ok, %") {
		t.Fatalf("unit payload carried an operand:\n%s", printed)
	}
}

func TestUnitLiteralRejections(t *testing.T) {
	cases := []struct {
		name, source, want string
	}{
		{
			"standalone statement",
			"fn main() -> I32 {\n    ()\n    return 0\n}\n",
			"expression statement has no effect",
		},
		{
			"binding",
			"fn main() -> I32 {\n    let value: Unit = ()\n    return 0\n}\n",
			"Unit values cannot be bound",
		},
		{
			"non-unit argument",
			"fn accept(value: U64) -> I32 {\n    return 0\n}\nfn main() -> I32 {\n    return accept(())\n}\n",
			"unit value: type mismatch: expected U64, got Unit",
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
