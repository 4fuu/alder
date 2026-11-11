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
	// The canonical Milestone 1 fixture remains a stable MIR 1 artifact.
	m.FormatVersion = LegacyFormatVersion
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
	if got := Print(m); got != "mir 6\n" {
		t.Errorf("empty module printed %q", got)
	}
	m.AddConst("k", TypeI64, ConstValue{Kind: ConstInt, Int: -5})
	m.AddConst("f", TypeF64, ConstValue{Kind: ConstFloat, Float: 1.5})
	m.AddConst("b", TypeBool, ConstValue{Kind: ConstBool, Bool: true})
	m.AddConst("s", m.String(), ConstValue{Kind: ConstString, String: "he\"llo"})
	m.AddConst("u", TypeUnit, ConstValue{Kind: ConstUnit})
	got := Print(m)
	want := "mir 6\n\nconst @k: i64 = -5\n\nconst @f: f64 = 1.5\n\nconst @b: bool = true\n\nconst @s: string = \"he\\\"llo\"\n\nconst @u: unit = ()\n"
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
	want := "mir 6\n\nfn @t(%c: bool, %o: option(i64)) {\nbb0:\n  switch %o {\n    some(%p) -> bb1(%p)\n    default -> bb2\n  }\n\nbb1(%p: i64):\n  return\n\nbb2:\n  unreachable\n}\n"
	if got != want {
		t.Errorf("terminator printing mismatch:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

func TestPrintClosureFormat(t *testing.T) {
	text := `mir 5

type @Env {
  n: u64
}

const @c_one: u64 = 1

fn @apply(%f: function(fn(u64) -> u64, @Env), %x: u64) -> u64 {
bb0:
  %r = call.value %f(%x)
  return %r
}

fn @plain(%g: function(fn(u64) -> u64)) -> u64 {
bb0:
  %one = const.get @c_one
  %r = call.value %g(%one)
  return %r
}
`
	m, err := Parse(text)
	if err != nil {
		t.Fatalf("parse closure format: %v", err)
	}
	again := Print(m)
	if again != text {
		t.Fatalf("closure format round trip:\n--- got ---\n%s\n--- want ---\n%s", again, text)
	}
	m2, err := Parse(again)
	if err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if _, ok := m2.Function("apply"); !ok {
		t.Fatal("apply missing after round trip")
	}
}

func TestPrintStrEq(t *testing.T) {
	text := `mir 5

fn @same(%a: string, %b: string) -> bool {
bb0:
  %r = str.eq %a, %b
  return %r
}
`
	m, err := Parse(text)
	if err != nil {
		t.Fatalf("parse str.eq: %v", err)
	}
	if got := Print(m); got != text {
		t.Fatalf("str.eq round trip:\n%s", got)
	}
}

func TestPrintFnValue(t *testing.T) {
	text := `mir 5

const @c_one: u64 = 1

fn @get() -> u64 {
bb0:
  %one = const.get @c_one
  return %one
}

fn @make() -> function(fn() -> u64) {
bb0:
  %f = fn.value @get
  return %f
}
`
	m, err := Parse(text)
	if err != nil {
		t.Fatalf("parse fn.value: %v", err)
	}
	if got := Print(m); got != text {
		t.Fatalf("fn.value round trip:\n%s", got)
	}
}

func TestPrintFnValueDomainMarker(t *testing.T) {
	text := `mir 5

const @c_one: u64 = 1

fn @scale(%dom: domain_handle, %x: u64) -> u64 {
bb0:
  return %x
}

fn @main(%d: domain_handle) -> u64 {
bb0:
  %f = fn.value @scale(%d) domain
  %z = const.get @c_one
  return %z
}
`
	m, err := Parse(text)
	if err != nil {
		t.Fatalf("parse fn.value domain marker: %v", err)
	}
	if got := Print(m); got != text {
		t.Fatalf("fn.value domain marker round trip:\n%s", got)
	}
	id, ok := m.Function("main")
	if !ok {
		t.Fatalf("main function missing")
	}
	if m.Functions[id].Blocks[0].Instrs[0].TypeOp != FnValueDomainMarker {
		t.Fatalf("fn.value domain marker did not parse as the sentinel")
	}
}

func TestPrintBindingBlocks(t *testing.T) {
	m := NewModule()
	timeT := m.AddCNamed("Time", "time_t", CClassScalar, nil)
	file := m.AddCNamed("File", "FILE", CClassOpaque, nil)
	rec := m.AddCNamed("Timespec", "struct timespec", CClassRecord, []Field{
		{Name: "seconds", Type: timeT, CName: "tv_sec"},
		{Name: "nanos", Type: m.CRaw(CScalarLong), CName: "tv_nsec"},
	})
	block := m.AddBinding("ctime", "time.h")
	b := &m.Bindings[block]
	b.Types = append(b.Types, timeT, file, rec)
	b.Funcs = append(b.Funcs,
		BindingFunc{Name: "get", CName: "timespec_get", Sig: FuncSig{Params: []TypeId{m.CPtr(rec), m.CRaw(CScalarInt)}, Result: m.CRaw(CScalarInt), Env: NoType}},
		BindingFunc{Name: "close", CName: "close", Sig: FuncSig{Params: []TypeId{m.CPtr(file)}, Result: m.CRaw(CScalarInt), Env: NoType}},
	)
	b.Consts = append(b.Consts, BindingConst{Name: "BUFSIZ", CName: "BUFSIZ", Type: m.CRaw(CScalarInt)})

	f := m.AddFunction("main", nil, TypeUnit)
	bb := f.AddBlock("bb0", nil)
	bb.SetTerm(Terminator{Kind: TermReturn, Result: NoValue})

	want := `mir 6

binding @ctime "time.h" {
  c_type scalar @Time = "time_t"
  c_type opaque @File = "FILE"
  c_type record @Timespec = "struct timespec" { seconds: @Time = "tv_sec", nanos: c_long = "tv_nsec" }
  c_fn @get = "timespec_get"(c_ptr(@Timespec), c_int) -> c_int
  c_fn @close(c_ptr(@File)) -> c_int
  c_const @BUFSIZ: c_int
}

fn @main() {
bb0:
  return
}
`
	if got := Print(m); got != want {
		t.Fatalf("binding block printing:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	parsed, err := Parse(want)
	if err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if again := Print(parsed); again != want {
		t.Fatalf("binding block round trip:\n%s", again)
	}
}

func TestPrintBindingUnsafeOps(t *testing.T) {
	m := NewModule()
	file := m.AddCNamed("File", "FILE", CClassOpaque, nil)
	block := m.AddBinding("stdio", "stdio.h")
	b := &m.Bindings[block]
	b.Types = append(b.Types, file)
	b.Funcs = append(b.Funcs, BindingFunc{Name: "open", CName: "fopen", Sig: FuncSig{
		Params: []TypeId{m.CConstPtr(m.CRaw(CScalarChar)), m.CConstPtr(m.CRaw(CScalarChar))},
		Result: m.CPtr(file), Env: NoType,
	}})
	f := m.AddFunction("main", []Param{{Name: "path", Type: m.CConstPtr(m.CRaw(CScalarChar))}}, TypeUnit)
	bb := f.AddBlock("bb0", nil)
	handle := addResultNamed(t, m, f, bb, "v0", Instr{Op: OpCBindingCall, CBinding: 0, Args: []ValueId{0, 0}})
	flag := addResultNamed(t, m, f, bb, "v1", Instr{Op: OpCIsNull, A: handle})
	_ = flag
	bb.SetTerm(Terminator{Kind: TermReturn, Result: NoValue})

	want := `mir 6

binding @stdio "stdio.h" {
  c_type opaque @File = "FILE"
  c_fn @open = "fopen"(c_const_ptr(c_char), c_const_ptr(c_char)) -> c_ptr(@File)
}

fn @main(%path: c_const_ptr(c_char)) {
bb0:
  %v0 = c.call.unsafe @stdio.open(%path, %path)
  %v1 = c.is_null %v0
  return
}
`
	if got := Print(m); got != want {
		t.Fatalf("binding op printing:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	parsed, err := Parse(want)
	if err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if again := Print(parsed); again != want {
		t.Fatalf("binding op round trip:\n%s", again)
	}
}

func TestRejectVersion5BindingSyntax(t *testing.T) {
	if _, err := Parse("mir 5\n\nbinding @c \"t.h\" {\n}\n"); err == nil {
		t.Fatal("version 5 must reject binding blocks")
	}
	if _, err := Parse("mir 5\n\nfn @f() -> c_int {\nbb0:\n  return\n}\n"); err == nil {
		t.Fatal("version 5 must reject c_* types")
	}
}

func TestPrintBindingFieldOps(t *testing.T) {
	m := NewModule()
	stamp := m.AddCNamed("Stamp", "struct stamp", CClassRecord, []Field{
		{Name: "seconds", Type: m.CRaw(CScalarLong), CName: "tv_sec"},
		{Name: "nanos", Type: m.CRaw(CScalarLong), CName: "tv_nsec"},
	})
	block := m.AddBinding("sys", "time.h")
	b := &m.Bindings[block]
	b.Types = append(b.Types, stamp)
	b.Funcs = append(b.Funcs, BindingFunc{Name: "zero", CName: "make_stamp", Sig: FuncSig{
		Params: nil, Result: stamp, Env: NoType,
	}})
	f := m.AddFunction("main", []Param{}, TypeUnit)
	bb := f.AddBlock("bb0", nil)
	rec := addResultNamed(t, m, f, bb, "v0", Instr{Op: OpCBindingCall, CBinding: 0})
	loc := f.AddLocal("rec", stamp)
	set := Instr{Op: OpCFieldSet, Result: NoValue, A: rec, Place: Place{Kind: PlaceLocal, Local: loc}, CField: "nanos"}
	bb.AddInstr(set)
	flag := addResultNamed(t, m, f, bb, "v1", Instr{Op: OpCFieldGet, A: rec, CField: "seconds"})
	_ = flag
	bb.SetTerm(Terminator{Kind: TermReturn, Result: NoValue})

	want := `mir 6

binding @sys "time.h" {
  c_type record @Stamp = "struct stamp" { seconds: c_long = "tv_sec", nanos: c_long = "tv_nsec" }
  c_fn @zero = "make_stamp"() -> @Stamp
}

fn @main() {
  local %rec: @Stamp

bb0:
  %v0 = c.call.unsafe @sys.zero()
  c.field.set nanos local %rec, %v0
  %v1 = c.field.get seconds(%v0)
  return
}
`
	if got := Print(m); got != want {
		t.Fatalf("binding field op printing:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	parsed, err := Parse(want)
	if err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if again := Print(parsed); again != want {
		t.Fatalf("binding field op round trip:\n%s", again)
	}
}
