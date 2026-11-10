package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The M8 byte-sequence surface: len and to_bytes read their sequence value,
// byte.checked indexes with a u64 under an explicit failure edge, concat and
// slice.checked allocate a fresh sequence in a domain with the same typing
// rules as the integer checked ops, and from_bytes yields option(string).
// These fixtures exercise the textual format, the verifier, and the printer
// round trip for the new operations. The operations ride MIR format 6.
const strOpsHeader = `mir 6
`

func TestStrOpsAccepted(t *testing.T) {
	const text = strOpsHeader + `
const @idx: u64 = 1

fn @seq(%d: domain_handle, %t: string, %b: bytes) -> option(string) {
entry:
  %i = const.get @idx
  %l = str.len %t
  %c = str.concat %d, %t, %t else fail
  %s = str.slice.checked %d, %t, %i, %i else fail
  %r = str.byte.checked %t, %i else fail
  %a = str.to_bytes %t
  %f = str.from_bytes %d, %b else fail
  %cb = str.concat %d, %b, %b else fail
  return %f
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
	for _, name := range []string{
		"str.len", "str.byte.checked", "str.concat", "str.slice.checked",
		"str.to_bytes", "str.from_bytes",
	} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
}

func TestStrOpsRejected(t *testing.T) {
	cases := []struct {
		name string
		text string
	}{
		{
			"len-on-i64",
			strOpsHeader + `
fn @seq(%x: i64) -> u64 {
entry:
  %l = str.len %x
  return %l
}
`,
		},
		{
			"len-fail-edge",
			strOpsHeader + `
fn @seq(%t: string) -> u64 {
entry:
  %l = str.len %t else fail
  return %l
fail:
  panic
}
`,
		},
		{
			"byte-index-not-u64",
			strOpsHeader + `
fn @seq(%t: string, %x: i64) -> u8 {
entry:
  %r = str.byte.checked %t, %x else fail
  return %r
fail:
  panic
}
`,
		},
		{
			"byte-missing-fail-edge",
			strOpsHeader + `
fn @seq(%t: string, %i: u64) -> u8 {
entry:
  %r = str.byte.checked %t, %i
  return %r
}
`,
		},
		{
			"concat-mixed-types",
			strOpsHeader + `
fn @seq(%d: domain_handle, %t: string, %b: bytes) -> string {
entry:
  %c = str.concat %d, %t, %b else fail
  return %c
fail:
  panic
}
`,
		},
		{
			"concat-domain-not-handle",
			strOpsHeader + `
fn @seq(%t: string) -> string {
entry:
  %c = str.concat %t, %t, %t else fail
  return %c
fail:
  panic
}
`,
		},
		{
			"concat-missing-fail-edge",
			strOpsHeader + `
fn @seq(%d: domain_handle, %t: string) -> string {
entry:
  %c = str.concat %d, %t, %t
  return %c
}
`,
		},
		{
			"slice-hi-not-u64",
			strOpsHeader + `
const @idx: u64 = 1

fn @seq(%d: domain_handle, %t: string, %x: i64) -> string {
entry:
  %i = const.get @idx
  %s = str.slice.checked %d, %t, %i, %x else fail
  return %s
fail:
  panic
}
`,
		},
		{
			"slice-missing-hi-operand",
			strOpsHeader + `
const @idx: u64 = 1

fn @seq(%d: domain_handle, %t: string) -> string {
entry:
  %i = const.get @idx
  %s = str.slice.checked %d, %t, %i else fail
  return %s
fail:
  panic
}
`,
		},
		{
			"to-bytes-on-bytes",
			strOpsHeader + `
fn @seq(%b: bytes) -> bytes {
entry:
  %a = str.to_bytes %b
  return %a
}
`,
		},
		{
			"from-bytes-on-string",
			strOpsHeader + `
fn @seq(%d: domain_handle, %t: string) -> option(string) {
entry:
  %f = str.from_bytes %d, %t else fail
  return %f
fail:
  panic
}
`,
		},
	}
	for _, c := range cases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			// Missing failure edges are rejected at parse time; type errors
			// below reach the verifier. Either rejection passes the case.
			m, err := mir.Parse(c.text)
			if err != nil {
				return
			}
			if errs := Module(m); len(errs) == 0 {
				t.Fatalf("accept %s: module verified but should reject", c.name)
			}
		})
	}
}
