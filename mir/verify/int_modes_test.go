package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// The M8 non-terminating integer arithmetic: try forms type as option(T),
// saturating and wrapping forms type as T, and all nine operations require a
// same-type integer operand pair. These fixtures exercise the textual format,
// the verifier, and the printer round trip for the new operations.
const intModesHeader = `mir 1
`

func TestIntModesAccepted(t *testing.T) {
	const text = intModesHeader + `
fn @modes(%a: i64, %u: u64) -> option(i64) {
entry:
  %at = int.add.try %a, %a
  %st = int.sub.try %a, %a
  %mt = int.mul.try %a, %a
  %as = int.add.saturating %a, %a
  %ss = int.sub.saturating %a, %a
  %ms = int.mul.saturating %a, %a
  %aw = int.add.wrapping %a, %a
  %sw = int.sub.wrapping %a, %a
  %mw = int.mul.wrapping %a, %a
  %uw = int.add.wrapping %u, %u
  %ut = int.mul.try %u, %u
  %us = int.add.saturating %u, %u
  switch %st {
    some(%v) -> some
    none -> none
  }
some:
  %so = enum.construct option(i64), some, %v
  return %so
none:
  %n = enum.construct option(i64), none
  return %n
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
		"int.add.try", "int.sub.try", "int.mul.try",
		"int.add.saturating", "int.sub.saturating", "int.mul.saturating",
		"int.add.wrapping", "int.sub.wrapping", "int.mul.wrapping",
	} {
		if !strings.Contains(printed, name) {
			t.Fatalf("printed module lost %s:\n%s", name, printed)
		}
	}
	// The try forms carry no failure edge; the printer must not attach one.
	if strings.Contains(printed, "int.add.try %a, %a else") {
		t.Fatalf("try form printed a failure edge:\n%s", printed)
	}
}

func TestIntModesRejected(t *testing.T) {
	t.Run("mixed operand types", func(t *testing.T) {
		mustReject(t, intModesHeader+`
fn @f(%a: i64, %u: u64) {
entry:
  %x = int.add.try %a, %u
  return
}
`, "integer operand")
	})

	t.Run("float operand", func(t *testing.T) {
		mustReject(t, intModesHeader+`
fn @f(%a: f64) {
entry:
  %x = int.mul.saturating %a, %a
  return
}
`, "integer operand")
	})

	t.Run("try result returned as integer", func(t *testing.T) {
		mustReject(t, intModesHeader+`
fn @f(%a: i64) -> i64 {
entry:
  %x = int.add.try %a, %a
  return %x
}
`, "option(i64)")
	})

	t.Run("wrapping result returned as option", func(t *testing.T) {
		mustReject(t, intModesHeader+`
fn @f(%a: i64) -> option(i64) {
entry:
  %x = int.add.wrapping %a, %a
  return %x
}
`, "return operand")
	})
}
