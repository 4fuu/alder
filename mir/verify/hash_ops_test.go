package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// hash.value takes two u64 key words and one structural value, and produces
// u64. The printer round trip pins the textual form; a float value is outside
// the structural domain and must be rejected.
func TestHashValueOpsAccepted(t *testing.T) {
	const text = `mir 6

const @k0: u64 = 1
const @k1: u64 = 2
const @v: u64 = 7

fn @main() -> u64 {
entry:
  %k0 = const.get @k0
  %k1 = const.get @k1
  %v = const.get @v
  %h = hash.value %k0, %k1, %v, u64
  return %h
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
	if !strings.Contains(printed, "hash.value %k0, %k1, %v, u64") {
		t.Fatalf("printed module lost the hash operands:\n%s", printed)
	}
}

func TestHashValueOpsRejected(t *testing.T) {
	const text = `mir 6

const @k0: u64 = 1
const @k1: u64 = 2
const @v: f64 = 1.5

fn @main() -> u64 {
entry:
  %k0 = const.get @k0
  %k1 = const.get @k1
  %v = const.get @v
  %h = hash.value %k0, %k1, %v, f64
  return %h
}

`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v", err)
	}
	errs := Module(m)
	if len(errs) == 0 || !strings.Contains(Errors(errs).String(), "structural hash domain") {
		t.Fatalf("float hash value was not rejected: %v", errs)
	}
}
