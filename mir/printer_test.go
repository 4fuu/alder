package mir

import (
	"os"
	"path/filepath"
	"testing"
)

// buildSummarizeModule constructs the module of testdata/golden/summarize.mir
// through the public API. It proves the API path and the textual path agree.
func buildSummarizeModule(t *testing.T) *Module {
	t.Helper()
	m := NewModule()
	summary := m.AddAggregate("Summary", []Field{
		{Name: "title", Type: m.Slice(TypeU8)},
		{Name: "words", Type: TypeI64},
	})
	loadErr := m.AddEnum("LoadError", []Variant{
		{Name: "NotFound", Payload: m.Slice(TypeU8)},
		{Name: "InvalidFormat", Payload: TypeI64},
	})
	m.AddConst("max_words", TypeI64, ConstValue{Kind: ConstInt, Int: 1000})
	m.AddImport("c_fastwords", FuncSig{Params: []TypeId{m.Slice(TypeU8)}, Result: TypeI64})

	destroy := m.AddFunction("domain.destroy", []Param{{Name: "d", Type: m.DomainHandle()}}, TypeUnit)
	destroyBlock := destroy.AddBlock("bb0", nil)
	destroyBlock.AddInstr(Instr{Op: OpDomainDestroy, Domain: 0, Result: NoValue})
	destroyBlock.SetTerm(Terminator{Kind: TermReturn, Result: NoValue})

	res := m.Result(summary, loadErr)
	f := m.AddFunction("summarize", []Param{
		{Name: "result_domain", Type: m.DomainHandle()},
		{Name: "data", Type: m.Slice(TypeU8)},
	}, res)
	f.AddLocal("temp", m.DomainHandle())
	bb0 := f.AddBlock("bb0", nil)

	// Function params are values %0 (%result_domain) and %1 (%data).
	rd, data := ValueId(0), ValueId(1)

	result := func(name string, in Instr) ValueId {
		t.Helper()
		return addResultNamed(t, m, f, bb0, name, in)
	}
	cleanup := result("cleanup", Instr{Op: OpCleanupScopeBegin})
	temp := result("temp", Instr{Op: OpDomainCreate, Domain: rd})
	result("temp_cleanup", Instr{Op: OpCleanupPush, Scope: cleanup, CleanupFn: 0, CleanupArgs: []ValueId{temp}})
	title := result("title", Instr{Op: OpCopyToDomain, Domain: rd, CopyVal: data})
	words := result("words", Instr{Op: OpFFICallUnsafe, FFIImport: 0, Args: []ValueId{data}})
	summaryV := result("summary", Instr{Op: OpAggregateConstruct, AggType: summary, AggFields: []AggField{
		{Name: "title", Value: title},
		{Name: "words", Value: words},
	}})
	okResult := result("ok_result", Instr{Op: OpEnumConstruct, TypeOp: res, Variant: "ok", Payload: summaryV})

	bb0.AddInstr(Instr{Op: OpCleanupScopeRun, Scope: cleanup, Result: NoValue})
	bb0.AddInstr(Instr{Op: OpCleanupScopeEnd, Scope: cleanup, Result: NoValue})
	bb0.SetTerm(Terminator{Kind: TermReturn, Result: okResult})
	return m
}

// addResultNamed appends a producing instruction to a specific block and
// returns its result value.
func addResultNamed(t *testing.T, m *Module, f *Function, b *Block, name string, in Instr) ValueId {
	t.Helper()
	typ, ok := m.InferResultType(f, &in)
	if !ok {
		t.Fatalf("InferResultType failed for %v", in.Op)
	}
	def := ValueDef{Kind: ValueDefInstr, Block: blockIndexOf(f, b), Instr: len(b.Instrs)}
	v := f.AddValue(name, typ, def)
	in.Result = v
	b.AddInstr(in)
	return v
}

func blockIndexOf(f *Function, want *Block) BlockId {
	for i, b := range f.Blocks {
		if b == want {
			return BlockId(i)
		}
	}
	return NoBlock
}

func TestPrintGoldenSummarize(t *testing.T) {
	m := buildSummarizeModule(t)
	got := Print(m)
	want, err := os.ReadFile(filepath.Join("testdata", "golden", "summarize.mir"))
	if err != nil {
		t.Fatal(err)
	}
	if got != string(want) {
		t.Errorf("API-built module does not match golden file.\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

func TestPrintDeterministic(t *testing.T) {
	m := buildSummarizeModule(t)
	first := Print(m)
	for i := 0; i < 20; i++ {
		if got := Print(m); got != first {
			t.Fatalf("Print output changed between runs (iteration %d)", i)
		}
	}
}

func TestPrintModuleSections(t *testing.T) {
	m := NewModule()
	if got := Print(m); got != "mir 1\n" {
		t.Errorf("empty module printed %q", got)
	}
	m.AddConst("k", TypeI64, ConstValue{Kind: ConstInt, Int: -5})
	m.AddConst("f", TypeF64, ConstValue{Kind: ConstFloat, Float: 1.5})
	m.AddConst("b", TypeBool, ConstValue{Kind: ConstBool, Bool: true})
	m.AddConst("s", m.Slice(TypeU8), ConstValue{Kind: ConstString, String: "he\"llo"})
	m.AddConst("u", TypeUnit, ConstValue{Kind: ConstUnit})
	got := Print(m)
	want := "mir 1\n\nconst @k: i64 = -5\n\nconst @f: f64 = 1.5\n\nconst @b: bool = true\n\nconst @s: slice(u8) = \"he\\\"llo\"\n\nconst @u: unit = ()\n"
	if got != want {
		t.Errorf("const printing mismatch:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

func TestPrintTerminators(t *testing.T) {
	m := NewModule()
	f := m.AddFunction("t", []Param{
		{Name: "c", Type: TypeBool},
		{Name: "o", Type: m.Option(TypeI64)},
	}, TypeUnit)
	bb0 := f.AddBlock("bb0", nil)
	f.AddBlock("bb1", []Param{{Name: "p", Type: TypeI64}})
	bb2 := f.AddBlock("bb2", nil)

	// Values: %0 = c, %1 = o; bb1's block parameter is %2 (named p).
	o := ValueId(1)
	bb0.SetTerm(Terminator{Kind: TermSwitch, Value: o, Cases: []SwitchCase{
		{Variant: "some", Binding: 2, Target: 1, Args: []ValueId{2}},
		{Variant: "", Target: 2},
	}})
	f.Blocks[1].SetTerm(Terminator{Kind: TermReturn, Result: NoValue})
	bb2.SetTerm(Terminator{Kind: TermUnreachable})

	got := Print(m)
	want := "mir 1\n\nfn @t(%c: bool, %o: option(i64)) {\nbb0:\n  switch %o {\n    some(%p) -> bb1(%p)\n    default -> bb2\n  }\n\nbb1(%p: i64):\n  return\n\nbb2:\n  unreachable\n}\n"
	if got != want {
		t.Errorf("terminator printing mismatch:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}
