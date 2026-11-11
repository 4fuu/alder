package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The M8 c.CString ownership vocabulary: the two constructors consume a
// String and produce the bare owner or its Option, ptr borrows a c_string as
// c_const_ptr(c_char), and release consumes a c_string without a result. The
// fixtures exercise the textual format, the verifier operand rule, and the
// printer round trip.
func TestCStringOpsAccepted(t *testing.T) {
	const text = `mir 6

fn @cs(%d: domain_handle, %s: string) -> c_const_ptr(c_char) {
entry:
  %bare = c.string.make_lit %s else fail
  %made = c.string.make %s else fail
  %ptr = c.string.ptr %bare
  c.string.release %bare
  return %ptr
fail:
  panic
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
	for _, name := range []string{"c.string.make_lit", "c.string.make", "c.string.ptr", "c.string.release"} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
}

func TestCStringOpsRejected(t *testing.T) {
	cases := []struct {
		name, body, want string
	}{
		{
			"constructor-operand",
			`  %bare = c.string.make_lit %p else fail
  return %p
fail:
  panic
`,
			"c.string operand has the wrong type",
		},
		{
			"ptr-operand",
			`  %ptr = c.string.ptr %s
  return %ptr
`,
			"c.string operand has the wrong type",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			text := `mir 6

fn @cs(%s: string, %p: c_string) -> c_string {
entry:
` + tc.body + `}
`
			m, err := mir.Parse(text)
			if err != nil {
				t.Fatalf("parse fixture: %v\n%s", err, text)
			}
			errs := Module(m)
			if len(errs) == 0 {
				t.Fatalf("module accepted:\n%s", text)
			}
			if !strings.Contains(Errors(errs).String(), tc.want) {
				t.Fatalf("diagnostics: got\n%s\nwant %q", Errors(errs).String(), tc.want)
			}
		})
	}
}
