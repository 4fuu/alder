package cgen

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// type.size and type.align emit the target C compiler's sizeof/_Alignof for
// the lowered type, while unit keeps its fixed 0/1 answers.
func TestTypeQueryEmission(t *testing.T) {
	m := mir.NewModule()
	f := m.AddFunction("query", nil, mir.TypeU64)
	b := f.AddBlock("bb0", nil)
	size := f.AddValue("size", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	align := f.AddValue("align", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 1})
	unitSize := f.AddValue("unit_size", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 2})
	unitAlign := f.AddValue("unit_align", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 3})
	b.AddInstr(mir.Instr{Op: mir.OpTypeSize, Result: size, TypeOp: mir.TypeU64, FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpTypeAlign, Result: align, TypeOp: mir.TypeU64, FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpTypeSize, Result: unitSize, TypeOp: mir.TypeUnit, FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpTypeAlign, Result: unitAlign, TypeOp: mir.TypeUnit, FailTarget: mir.NoBlock})
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: align})

	out, err := Generate(m)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	for _, want := range []string{
		"sizeof(uint64_t)",
		"_Alignof(uint64_t)",
		"= UINT64_C(0);",
		"= UINT64_C(1);",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("generated C lacks %q:\n%s", want, out)
		}
	}
}
