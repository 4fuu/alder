package verify

import (
	"strings"
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

func TestCopyToOuterDomainSeversInnerProvenance(t *testing.T) {
	text := `mir 4
const @one: u64 = 1
fn @copy(%root: domain_handle) -> safe_mut(u8) {
entry:
  %child = domain.create %root
  %one = const.get @one
  %source = alloc %child, u8, %one
  %copy = copy_to_domain %root, %source
  domain.destroy %child
  return %copy
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if errs := Module(m); len(errs) != 0 {
		t.Fatalf("independent outer-domain copy rejected:\n%s", Errors(errs).String())
	}
}

func TestCopyToDomainRejectsIdentityBearingSource(t *testing.T) {
	text := `mir 4
const @one: u64 = 1
fn @copy(%root: domain_handle) {
entry:
  %child = domain.create %root
  %copy = copy_to_domain %root, %child
  domain.destroy %child
  %one = const.get @one
  %value = alloc %copy, u8, %one
  return
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	errs := Module(m)
	if got := Errors(errs).String(); !strings.Contains(got, "copy_to_domain source type may not contain domain_handle") {
		t.Fatalf("identity-bearing copy diagnostic = %q", got)
	}
}

func TestCopyToDomainForbiddenKindOrder(t *testing.T) {
	text := `mir 4
type @P {
  value: u64
}
type @Mixed {
  table: table(@P)
  domain: domain_handle
}
fn @copy(%root: domain_handle, %value: @Mixed) {
entry:
  %copy = copy_to_domain %root, %value
  return
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	errs := phase10Backend(m)
	if len(errs) != 1 || !strings.Contains(errs[0].Msg, "may not contain domain_handle") {
		t.Fatalf("mixed identity-bearing copy diagnostics = %v", errs)
	}
}
