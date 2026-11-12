package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// type.size and type.align carry one lowered type operand and produce u64.
// The printer round trip pins the spelling, and a zero type operand is
// rejected by the verifier rather than reaching the C backend.
func TestTypeQueryOpsAccepted(t *testing.T) {
	const text = `mir 6

fn @main() -> u64 {
entry:
  %size = type.size u64
  %align = type.align u64
  %unit_size = type.size unit
  %unit_align = type.align unit
  %sum = int.add.wrapping %size, %align
  %sum2 = int.add.wrapping %sum, %unit_size
  %sum3 = int.add.wrapping %sum2, %unit_align
  return %sum3
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
	if !strings.Contains(printed, "type.size u64") || !strings.Contains(printed, "type.align unit") {
		t.Fatalf("printed module lost the query spellings:\n%s", printed)
	}
}

func TestTypeQueryOpsRejected(t *testing.T) {
	const text = `mir 6

fn @main() -> u64 {
entry:
  %size = type.size u64
  return %size
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v", err)
	}
	m.Functions[0].Blocks[0].Instrs[0].TypeOp = mir.TypeId(len(m.Types))
	errs := Module(m)
	if len(errs) == 0 || !strings.Contains(Errors(errs).String(), "type operand is out of range") {
		t.Fatalf("zero type operand was not rejected: %v", errs)
	}
}
