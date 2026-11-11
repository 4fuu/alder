package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The call-scoped buffer borrow: bytes or a u8 slice lowers to the declared
// C pointer type for one call. The fixtures exercise the textual format, the
// verifier operand and pointee rules, and the printer round trip.
func TestCBufferOpsAccepted(t *testing.T) {
	const text = `mir 6

fn @borrow(%v: slice(u8), %d: bytes) -> c_const_ptr(c_char) {
entry:
  %p = c.buffer.ptr %v, c_const_ptr(c_char)
  %q = c.buffer.ptr %d, c_const_ptr(c_char)
  return %q
}

fn @borrow_mut(%v: slice(u8)) -> c_ptr(c_char) {
entry:
  %p = c.buffer.ptr %v, c_ptr(c_char)
  return %p
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
	if !strings.Contains(printed, "c.buffer.ptr %v, c_const_ptr(c_char)") {
		t.Fatalf("printed module lost the borrow typing:\n%s", printed)
	}
}

func TestCBufferOpsRejected(t *testing.T) {
	cases := []struct {
		name, body, want string
	}{
		{
			"non-buffer-operand",
			`  %p = c.buffer.ptr %n, c_const_ptr(c_char)
  return %p
`,
			"buffer operand",
		},
		{
			"wide-pointee",
			`  %p = c.buffer.ptr %v, c_const_ptr(c_int)
  return %v
`,
			"pointee is not byte-addressable",
		},
		{
			"non-pointer-result",
			`  %p = c.buffer.ptr %v, c_char
  return %v
`,
			"result type is not a C pointer",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			text := `mir 6

fn @borrow(%v: slice(u8), %n: i64) -> c_const_ptr(c_char) {
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
