package cgen

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// hash.value initializes one runtime SipHash state, writes the canonical
// value, and finishes it.
func TestHashValueEmission(t *testing.T) {
	m := mir.NewModule()
	m.AddConst("k0", mir.TypeU64, mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	m.AddConst("k1", mir.TypeU64, mir.ConstValue{Kind: mir.ConstInt, Int: 2})
	m.AddConst("v", mir.TypeU64, mir.ConstValue{Kind: mir.ConstInt, Int: 7})
	f := m.AddFunction("hash_it", nil, mir.TypeU64)
	b := f.AddBlock("bb0", nil)
	k0 := f.AddValue("k0", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	k1 := f.AddValue("k1", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 1})
	v := f.AddValue("v", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 2})
	out := f.AddValue("out", mir.TypeU64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 3})
	b.AddInstr(mir.Instr{Op: mir.OpConstGet, Result: k0, Const: "k0", FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpConstGet, Result: k1, Const: "k1", FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpConstGet, Result: v, Const: "v", FailTarget: mir.NoBlock})
	b.AddInstr(mir.Instr{Op: mir.OpHashValue, Result: out, A: k0, B: k1, HashVal: v, TypeOp: mir.TypeU64, FailTarget: mir.NoBlock})
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: out})

	generated, err := Generate(m)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	for _, want := range []string{
		"AlderHashState alder_h",
		"alder_hash_init(",
		"alder_hash_write_uint(",
		"alder_hash_finish(",
	} {
		if !strings.Contains(generated, want) {
			t.Fatalf("generated C lacks %q:\n%s", want, generated)
		}
	}
}
