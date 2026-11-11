package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// Pointer member access and whole-value memory reuse deref and field places:
// a c_ptr or c_const_ptr deref yields the pointee, a verified c_named record
// field selects by Alder name, and only c_ptr places are mutable. The
// fixtures pin the accepted shapes and the two rejected ones.
func TestCPtrPlaceOpsAccepted(t *testing.T) {
	const text = `mir 6

binding @posix "cptrmem.h" {
  c_type record @Pair = "struct cptr_pair" { first: c_long, second: c_long }
}

fn @fields(%p: c_ptr(@Pair), %c: c_const_ptr(@Pair), %n: c_long) -> c_long {
entry:
  %a = load field(deref %p, first)
  store field(deref %p, second), %n
  %b = load field(deref %c, first)
  %w = load deref %p
  store deref %p, %w
  %x = load deref %c
  return %a
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
	if !strings.Contains(printed, "load field(deref %p, first)") || !strings.Contains(printed, "store deref %p, %w") {
		t.Fatalf("printed module lost the pointer places:\n%s", printed)
	}
}

func TestCPtrPlaceOpsRejected(t *testing.T) {
	cases := []struct {
		name, body, want string
	}{
		{
			"store-through-const",
			`  %w = load deref %p
  store deref %c, %w
  return %w
`,
			"store target is read-only",
		},
		{
			"field-of-non-record-pointer",
			`  %a = load field(deref %q, first)
  return %a
`,
			"place is not well-formed",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			text := `mir 6

binding @posix "cptrmem.h" {
  c_type record @Pair = "struct cptr_pair" { first: c_long, second: c_long }
}

fn @fields(%p: c_ptr(@Pair), %c: c_const_ptr(@Pair), %q: c_ptr(c_long)) -> c_long {
entry:
` + tc.body + `}
`
			m, err := mir.Parse(text)
			if err != nil {
				t.Fatalf("parse fixture: %v\n%s", err, text)
			}
			errs := Module(m)
			if len(errs) == 0 {
				t.Fatalf("fixture accepted:\n%s", text)
			}
			if got := Errors(errs).String(); !strings.Contains(got, tc.want) {
				t.Fatalf("diagnostic: got %q, want %q", got, tc.want)
			}
		})
	}
}
