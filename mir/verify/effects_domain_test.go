package verify

import (
	"testing"

	"github.com/4fuu/alder/mir"
)

// These tests intentionally use non-leading parameters. AddFunction leaves
// ValueDef.Param zeroed, so they guard the public builder as well as parsing.
func TestEffectsUseLeadingValueIDAsParameterIndex(t *testing.T) {
	m := mir.NewModule()
	f := m.AddFunction("destroy_second", []mir.Param{{Name: "n", Type: mir.TypeI64}, {Name: "d", Type: m.DomainHandle()}}, mir.TypeUnit)
	b := f.AddBlock("entry", nil)
	b.AddInstr(mir.Instr{Op: mir.OpDomainDestroy, Domain: 1})
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	e := computeFunctionEffects(m)
	if e[0].destroys[0] || !e[0].destroys[1] {
		t.Fatalf("destroy summary = %v, want only parameter 1", e[0].destroys)
	}
}

func TestReferencePassthroughUsesNonzeroParameter(t *testing.T) {
	m := mir.NewModule()
	ref := m.SafeRef(mir.TypeI64)
	f := m.AddFunction("pass", []mir.Param{{Name: "n", Type: mir.TypeI64}, {Name: "r", Type: ref}}, ref)
	b := f.AddBlock("entry", nil)
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: 1})
	e := computeFunctionEffects(m)
	if e[0].resultFrom[0] || !e[0].resultFrom[1] {
		t.Fatalf("result summary = %v, want only parameter 1", e[0].resultFrom)
	}
}

func TestChildIdentityIsNotParentAliasInSummary(t *testing.T) {
	text := `mir 1
fn @local_child(%n: i64, %parent: domain_handle) {
entry:
  %child = domain.create %parent
  domain.destroy %child
  return
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	e := computeFunctionEffects(m)
	if e[0].destroys[1] {
		t.Fatal("destroying a local child was summarized as destroying its parent")
	}
}
