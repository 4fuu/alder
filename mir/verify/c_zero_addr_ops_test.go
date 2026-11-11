package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// c.zero and c.addr: a zero-initialized by-value C boundary value and the
// address of a local place as a declared C pointer for one raw call
// argument. The fixtures pin the textual format, the type rules, the
// local-root requirement, and the printer round trip.
func TestCZeroAddrOpsAccepted(t *testing.T) {
	const text = `mir 6

binding @posix "caddr.h" {
  c_type record @Pair = "struct caddr_pair" { first: c_long, second: c_long }
  c_fn @fill = "caddr_fill"(c_ptr(@Pair), c_long) -> c_int
}

fn @main() -> c_int {
  local %pair: @Pair

entry:
  %z = c.zero @Pair
  store local %pair, %z
  %p = c.addr local %pair, c_ptr(@Pair)
  %q = c.addr local %pair, c_const_ptr(@Pair)
  %zero = c.zero c_long
  %rc = c.call.unsafe @posix.fill(%p, %zero)
  return %rc
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
	if !strings.Contains(printed, "c.zero @Pair") {
		t.Fatalf("printed module lost the zero type:\n%s", printed)
	}
	if !strings.Contains(printed, "c.addr local %pair, c_const_ptr(@Pair)") {
		t.Fatalf("printed module lost the address typing:\n%s", printed)
	}
}

func TestCZeroAddrOpsRejected(t *testing.T) {
	cases := []struct {
		name, body, want string
	}{
		{
			"zero-non-bound-type",
			`  %bad = c.zero string
  %zero = c.zero c_long
  %p = c.addr local %pair, c_const_ptr(@Pair)
  %rc = c.call.unsafe @posix.fill(%p, %zero)
  return %rc
`,
			"c.zero type is not a by-value C scalar or record",
		},
		{
			"addr-pointee-mismatch",
			`  %p = c.addr local %pair, c_ptr(c_long)
  %rc = c.call.unsafe @posix.reset(%p)
  return %rc
`,
			"place type does not match the C pointer pointee",
		},
		{
			"addr-non-local-root",
			`  %p = c.addr deref %v, c_ptr(c_int)
  %rc = c.call.unsafe @posix.down(%p)
  return %rc
`,
			"c.addr place must be rooted at a local",
		},
		{
			"addr-non-pointer-type",
			`  %p = c.addr local %pair, c_long
  %zero = c.zero c_long
  %p2 = c.addr local %pair, c_const_ptr(@Pair)
  %rc = c.call.unsafe @posix.fill(%p2, %zero)
  return %rc
`,
			"c.addr type is not a C pointer",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			text := `mir 6

binding @posix "caddr.h" {
  c_type record @Pair = "struct caddr_pair" { first: c_long, second: c_long }
  c_fn @fill = "caddr_fill"(c_ptr(@Pair), c_long) -> c_int
  c_fn @reset = "caddr_reset"(c_ptr(c_long)) -> c_int
  c_fn @down = "caddr_down"(c_ptr(c_int)) -> c_int
}

fn @main(%v: safe_mut(c_int)) -> c_int {
  local %pair: @Pair

entry:
  %z = c.zero @Pair
  store local %pair, %z
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
