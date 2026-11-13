package verify

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// TestGoldenAcceptance verifies that every golden fixture is accepted. The
// golden files exercise the full documented vocabulary; testdata/verify/accept
// holds additional targeted acceptance fixtures.
func TestGoldenAcceptance(t *testing.T) {
	var files []string
	for _, dir := range []string{
		filepath.Join("..", "testdata", "golden"),
		filepath.Join("testdata", "verify", "accept"),
	} {
		got, err := filepath.Glob(filepath.Join(dir, "*.mir"))
		if err != nil {
			t.Fatal(err)
		}
		files = append(files, got...)
	}
	if len(files) == 0 {
		t.Fatal("no acceptance fixtures found")
	}
	for _, path := range files {
		name := filepath.Base(path)
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m, err := mir.Parse(string(text))
		if err != nil {
			t.Fatalf("%s: parse: %v", name, err)
		}
		if errs := Module(m); len(errs) > 0 {
			t.Errorf("%s: unexpected diagnostics:\n%s", name, Errors(errs).String())
		}
	}
}

// TestRejectFixtures checks rejection fixtures with pinned diagnostics: each
// testdata/verify/reject/*.mir file has a sibling .err file with the exact
// expected diagnostics, one per line.
func TestRejectFixtures(t *testing.T) {
	files, err := filepath.Glob(filepath.Join("testdata", "verify", "reject", "*.mir"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("no rejection fixtures found")
	}
	for _, path := range files {
		name := filepath.Base(path)
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m, err := mir.Parse(string(text))
		if err != nil {
			t.Fatalf("%s: fixture must parse: %v", name, err)
		}
		got := Errors(Module(m)).String()
		errPath := strings.TrimSuffix(path, ".mir") + ".err"
		wantBytes, err := os.ReadFile(errPath)
		if err != nil {
			t.Fatalf("%s: missing .err file (got diagnostics:\n%s)", name, got)
		}
		want := strings.TrimSuffix(string(wantBytes), "\n")
		if got != want {
			t.Errorf("%s: diagnostics mismatch\n--- got ---\n%s\n--- want ---\n%s", name, got, want)
		}
		// Diagnostics must be deterministic across runs.
		if got2 := Errors(Module(m)).String(); got2 != got {
			t.Errorf("%s: diagnostics not deterministic", name)
		}
	}
}

// TestAPIRejections covers integrity violations that the textual parser
// cannot express (malformed value definitions, missing failure edges, result
// binding mismatches).
func TestAPIRejections(t *testing.T) {
	legacyVec := mir.NewModule()
	legacyVec.FormatVersion = mir.AllocCheckedFormatVersion
	legacyVec.Vec(mir.TypeU8)
	if errs := Module(legacyVec); !containsMsg(errs, "vec type requires MIR format version 4") {
		t.Errorf("legacy vec type not rejected:\n%s", Errors(errs).String())
	}

	// Checked operation without a failure edge.
	m := mir.NewModule()
	f := m.AddFunction("f", nil, mir.TypeI64)
	b := f.AddBlock("bb0", nil)
	b.AddInstr(mir.Instr{Op: mir.OpIntAddChecked, Result: mir.NoValue, FailTarget: mir.NoBlock})
	b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs := Module(m)
	if !containsMsg(errs, "checked operation requires an 'else' failure edge") {
		t.Errorf("missing else edge not reported:\n%s", Errors(errs).String())
	}

	// Recoverable allocation is also a checked operation and requires an edge.
	allocModule := mir.NewModule()
	allocFn := allocModule.AddFunction("alloc", []mir.Param{
		{Name: "d", Type: allocModule.DomainHandle()},
		{Name: "n", Type: mir.TypeU64},
	}, mir.TypeUnit)
	allocBlock := allocFn.AddBlock("bb0", nil)
	allocResult := allocFn.AddValue("p", allocModule.SafeMut(mir.TypeU8), mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	allocBlock.AddInstr(mir.Instr{
		Op: mir.OpAllocChecked, Result: allocResult, Domain: 0, TypeOp: mir.TypeU8, Count: 1, FailTarget: mir.NoBlock,
	})
	allocBlock.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(allocModule)
	if !containsMsg(errs, "checked operation requires an 'else' failure edge") {
		t.Errorf("alloc.checked missing else edge not reported:\n%s", Errors(errs).String())
	}

	// The fn.value domain marker is legal only on fn.value; on any other
	// instruction the shape check rejects it.
	marked := mir.NewModule()
	mf := marked.AddFunction("f", []mir.Param{{Name: "d", Type: mir.TypeI64}}, mir.TypeUnit)
	mb := mf.AddBlock("bb0", nil)
	one := mf.AddValue("one", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefFuncParam, Param: 0})
	mb.AddInstr(mir.Instr{Op: mir.OpIntAddChecked, Result: mir.NoValue, A: one, FailTarget: mir.NoBlock, TypeOp: mir.FnValueDomainMarker})
	mb.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(marked)
	if !containsMsg(errs, "fn.value domain marker on a non-fn.value instruction") {
		t.Errorf("marker on a non-fn.value instruction not rejected:\n%s", Errors(errs).String())
	}

	// A producing instruction that binds no result.
	m2 := mir.NewModule()
	f2 := m2.AddFunction("g", nil, mir.TypeUnit)
	b2 := f2.AddBlock("bb0", nil)
	b2.AddInstr(mir.Instr{Op: mir.OpDomainCreate, Result: mir.NoValue, Domain: 0})
	b2.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m2)
	if !containsMsg(errs, "binds no result") {
		t.Errorf("unbound producing instruction not reported:\n%s", Errors(errs).String())
	}

	// A value whose definition index does not match the instruction result.
	m3 := mir.NewModule()
	f3 := m3.AddFunction("h", nil, mir.TypeUnit)
	b3 := f3.AddBlock("bb0", nil)
	v0 := f3.AddValue("x", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	v1 := f3.AddValue("y", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 1})
	// Instruction 0 binds v1, so v0's claim that it defines instruction 0 is stale.
	b3.AddInstr(mir.Instr{Op: mir.OpConstGet, Const: "k", Result: v1})
	_ = v0
	b3.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m3)
	if !containsMsg(errs, "instruction result does not reference this value") {
		t.Errorf("stale value definition not reported:\n%s", Errors(errs).String())
	}

	// A type cycle: @A contains @B contains @A. Textual cycles cannot be
	// expressed because declarations must precede uses, so build via API.
	m4 := mir.NewModule()
	aID := m4.AddAggregate("A", nil)
	bID := m4.AddAggregate("B", nil)
	m4.Types[aID].Fields = []mir.Field{{Name: "b", Type: bID}}
	m4.Types[bID].Fields = []mir.Field{{Name: "a", Type: aID}}
	f4 := m4.AddFunction("cyc", nil, mir.TypeUnit)
	f4.AddBlock("bb0", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m4)
	if !containsMsg(errs, "type contains itself") {
		t.Errorf("type cycle not reported:\n%s", Errors(errs).String())
	}

	// A stored result type that contradicts the inferred type.
	m5 := mir.NewModule()
	m5.AddConst("k", mir.TypeI64, mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	f5 := m5.AddFunction("rm", nil, mir.TypeUnit)
	b5 := f5.AddBlock("bb0", nil)
	v5 := f5.AddValue("x", m5.Slice(mir.TypeU8), mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	b5.AddInstr(mir.Instr{Op: mir.OpConstGet, Const: "k", Result: v5, FailTarget: mir.NoBlock})
	b5.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	errs = Module(m5)
	if !containsMsg(errs, "result type mismatch: stored slice(u8), expected i64") {
		t.Errorf("result type mismatch not reported:\n%s", Errors(errs).String())
	}
}

func TestArrayConstructRejections(t *testing.T) {
	for _, tc := range []struct {
		name  string
		type2 mir.TypeId
		want  string
	}{
		{"wrong count", mir.TypeI64, "aggregate.construct: expected 2 elements, got 1"},
		{"wrong element type", mir.TypeBool, "aggregate.construct element 1: expected i64, got bool"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := mir.NewModule()
			arr := m.Array(mir.TypeI64, 2)
			f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}, {Name: "y", Type: tc.type2}}, arr)
			b := f.AddBlock("bb0", nil)
			fields := []mir.AggField{{Value: 0}}
			if tc.name != "wrong count" {
				fields = append(fields, mir.AggField{Value: 1})
			}
			v := f.AddValue("a", arr, mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
			b.AddInstr(mir.Instr{Op: mir.OpAggregateConstruct, Result: v, AggType: arr, AggFields: fields, FailTarget: mir.NoBlock})
			b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: v})
			if errs := Module(m); !containsMsg(errs, tc.want) {
				t.Fatalf("missing %q diagnostic:\n%s", tc.want, Errors(errs).String())
			}
		})
	}
}

func TestAllocCheckedResultUnavailableOnFailure(t *testing.T) {
	m := mir.NewModule()
	f := m.AddFunction("f", []mir.Param{
		{Name: "d", Type: m.DomainHandle()},
		{Name: "n", Type: mir.TypeU64},
	}, mir.TypeUnit)
	entry := f.AddBlock("entry", nil)
	failure := f.AddBlock("failure", []mir.Param{{Name: "p", Type: m.SafeMut(mir.TypeU8)}})
	result := f.AddValue("allocation", m.SafeMut(mir.TypeU8), mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
	entry.AddInstr(mir.Instr{
		Op:         mir.OpAllocChecked,
		Result:     result,
		Domain:     0,
		TypeOp:     mir.TypeU8,
		Count:      1,
		FailTarget: 1,
		FailArgs:   []mir.ValueId{result},
	})
	entry.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	failure.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})

	errs := Module(m)
	if !containsMsg(errs, "use of %allocation is not dominated by its definition") {
		t.Fatalf("alloc.checked result was available on its failure edge:\n%s", Errors(errs).String())
	}
}

func TestPointCFGDominatesUsesImmediateDominators(t *testing.T) {
	preds := [][]int{
		nil,    // 0 entry
		{0},    // 1
		{1},    // 2 success after checked op
		{1},    // 3 failure edge
		{2, 3}, // 4 join
		nil,    // 5 unreachable
	}
	g := &pointCFG{preds: preds, entry: 0}
	g.idom = computeIdoms(preds, 0)
	g.indexDominatorTree()
	if !g.dominates(2, 0) || !g.dominates(3, 1) || g.dominates(3, 2) {
		t.Fatalf("idom query failed: idom=%v in=%v out=%v", g.idom, g.domIn, g.domOut)
	}
	if !g.dominates(5, 5) || g.dominates(4, 5) || g.dominates(5, 0) {
		t.Fatal("unreachable node must dominate only itself")
	}
}

func TestMalformedTypeAndPlaceAPIRejections(t *testing.T) {
	t.Run("missing primitive type table", func(t *testing.T) {
		errs := Module(&mir.Module{FormatVersion: 1})
		if !containsMsg(errs, "canonical primitive slots") {
			t.Fatalf("missing primitive table not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("unknown type kind", func(t *testing.T) {
		m := mir.NewModule()
		m.Types = append(m.Types, mir.Type{Kind: mir.TypeKind(255)})
		errs := Module(m)
		if !containsMsg(errs, "unknown type kind 255") {
			t.Fatalf("unknown type kind not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("primitive outside canonical slots", func(t *testing.T) {
		m := mir.NewModule()
		m.Types = append(m.Types, mir.Type{Kind: mir.TypePrimitive})
		errs := Module(m)
		if !containsMsg(errs, "primitive type appears outside") {
			t.Fatalf("extra primitive not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("invalid function type signature", func(t *testing.T) {
		m := mir.NewModule()
		m.FunctionType(mir.FuncSig{Params: []mir.TypeId{mir.NoType}, Result: mir.TypeUnit})
		errs := Module(m)
		if !containsMsg(errs, "parameter type out of range") {
			t.Fatalf("invalid function type signature not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("invalid local type", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", nil, mir.TypeUnit)
		f.AddLocal("bad", mir.TypeId(999))
		f.AddBlock("entry", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "local %bad type out of range") {
			t.Fatalf("invalid local type not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("invalid block parameter type", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", nil, mir.TypeUnit)
		f.AddBlock("entry", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		f.AddBlock("dead", []mir.Param{{Name: "bad", Type: mir.TypeId(999)}}).
			SetTerm(mir.Terminator{Kind: mir.TermUnreachable, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "block parameter %bad type out of range") {
			t.Fatalf("invalid block parameter type not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("panic operand", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		f.AddBlock("entry", nil).SetTerm(mir.Terminator{Kind: mir.TermPanic, Result: 0})
		errs := Module(m)
		if !containsMsg(errs, "panic may not have an operand") {
			t.Fatalf("panic operand not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("panic in legacy format", func(t *testing.T) {
		m := mir.NewModule()
		m.FormatVersion = mir.LegacyFormatVersion
		f := m.AddFunction("f", nil, mir.TypeUnit)
		f.AddBlock("entry", nil).SetTerm(mir.Terminator{Kind: mir.TermPanic, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "panic requires MIR format version 2") {
			t.Fatalf("legacy panic not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("cycle through structural type", func(t *testing.T) {
		m := mir.NewModule()
		a := m.AddAggregate("A", nil)
		wrapped := m.Option(a)
		m.Types[a].Fields = []mir.Field{{Name: "next", Type: wrapped}}
		errs := Module(m)
		if !containsMsg(errs, "type contains itself") {
			t.Fatalf("structural type cycle not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("cyclic place", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		b := f.AddBlock("entry", nil)
		p := &mir.Place{Kind: mir.PlaceField, Field: "x"}
		p.Base = p
		b.AddInstr(mir.Instr{Op: mir.OpStore, Place: *p, StoreVal: 0, Result: mir.NoValue})
		b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "cyclic place") {
			t.Fatalf("cyclic place not reported:\n%s", Errors(errs).String())
		}
		if _, ok := m.PlaceType(f, p); ok {
			t.Fatal("PlaceType accepted a cyclic place")
		}
	})

	t.Run("unknown place kind", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		b := f.AddBlock("entry", nil)
		b.AddInstr(mir.Instr{
			Op:       mir.OpStore,
			Place:    mir.Place{Kind: mir.PlaceKind(255)},
			StoreVal: 0,
			Result:   mir.NoValue,
		})
		b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "unknown place kind 255") {
			t.Fatalf("unknown place kind not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("missing branch condition", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", nil, mir.TypeUnit)
		entry := f.AddBlock("entry", nil)
		f.AddBlock("done", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		entry.SetTerm(mir.Terminator{Kind: mir.TermBranch, Cond: mir.NoValue, Then: 1, Else: 1})
		errs := Module(m)
		if !containsMsg(errs, "branch condition is missing") {
			t.Fatalf("missing branch condition not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("missing call and failure arguments", func(t *testing.T) {
		m := mir.NewModule()
		callee := m.AddFunction("callee", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		callee.AddBlock("entry", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		entry := f.AddBlock("entry", nil)
		failed := f.AddBlock("failed", []mir.Param{{Name: "x", Type: mir.TypeI64}})
		failed.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		entry.AddInstr(mir.Instr{Op: mir.OpCall, Result: mir.NoValue, Callee: 0, Args: []mir.ValueId{mir.NoValue}, FailTarget: mir.NoBlock})
		entry.AddInstr(mir.Instr{
			Op:         mir.OpIntAddChecked,
			Result:     mir.NoValue,
			A:          0,
			B:          0,
			FailTarget: 1,
			FailArgs:   []mir.ValueId{mir.NoValue},
		})
		entry.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "call argument 0 is missing") || !containsMsg(errs, "failure argument is missing") {
			t.Fatalf("missing call/failure arguments not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("forged block parameter value type", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		entry := f.AddBlock("entry", nil)
		f.AddBlock("next", []mir.Param{{Name: "x", Type: mir.TypeI64}}).
			SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		f.Values[1].Type = m.SafeMut(mir.TypeU8)
		entry.SetTerm(mir.Terminator{Kind: mir.TermJump, Target: 1, Args: []mir.ValueId{0}})
		errs := Module(m)
		if !containsMsg(errs, "value type does not match its block parameter") {
			t.Fatalf("forged block parameter type not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("uninferable producing instruction", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("f", []mir.Param{{Name: "x", Type: mir.TypeI64}}, mir.TypeUnit)
		b := f.AddBlock("entry", nil)
		result := f.AddValue("id", m.ID(mir.TypeI64), mir.ValueDef{Kind: mir.ValueDefInstr, Block: 0, Instr: 0})
		b.AddInstr(mir.Instr{Op: mir.OpTableInsert, Result: result, Table: 0, TableVal: 0, FailTarget: mir.NoBlock})
		b.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "cannot infer result type") {
			t.Fatalf("uninferable producing instruction not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("default switch binding", func(t *testing.T) {
		m := mir.NewModule()
		option := m.Option(mir.TypeI64)
		f := m.AddFunction("f", []mir.Param{{Name: "value", Type: option}}, mir.TypeUnit)
		entry := f.AddBlock("entry", nil)
		f.AddBlock("done", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		binding := f.AddValue("binding", mir.TypeI64, mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: 0, Case: 0})
		entry.SetTerm(mir.Terminator{
			Kind:  mir.TermSwitch,
			Value: 0,
			Cases: []mir.SwitchCase{{Variant: "", Binding: binding, Target: 1}},
		})
		errs := Module(m)
		if !containsMsg(errs, "default switch case may not bind") {
			t.Fatalf("default switch binding not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("invalid public API name", func(t *testing.T) {
		m := mir.NewModule()
		f := m.AddFunction("not a name", nil, mir.TypeUnit)
		f.AddBlock("entry", nil).SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
		errs := Module(m)
		if !containsMsg(errs, "invalid function name") {
			t.Fatalf("invalid function name not reported:\n%s", Errors(errs).String())
		}
	})

	t.Run("non-finite float constant", func(t *testing.T) {
		m := mir.NewModule()
		m.AddConst("bad", mir.TypeF64, mir.ConstValue{Kind: mir.ConstFloat, Float: math.Inf(1)})
		errs := Module(m)
		if !containsMsg(errs, "float constant must be finite") {
			t.Fatalf("non-finite float not reported:\n%s", Errors(errs).String())
		}
	})
}

func TestPhase9NestedRawPointers(t *testing.T) {
	const header = `mir 1

type @Box {
  ptr: raw_ptr(u8)
}

`
	tests := []struct {
		name string
		body string
	}{
		{
			name: "store",
			body: `fn @f(%box: @Box) {
  local %saved: @Box

entry:
  store local %saved, %box
  return
}
`,
		},
		{
			name: "ordinary call",
			body: `fn @sink(%box: @Box) {
entry:
  return
}

fn @f(%box: @Box) {
entry:
  call @sink(%box)
  return
}
`,
		},
		{
			name: "block argument",
			body: `fn @f(%box: @Box) {
entry:
  jump next(%box)
next(%forwarded: @Box):
  return
}
`,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			m, err := mir.Parse(header + tc.body)
			if err != nil {
				t.Fatal(err)
			}
			errs := Module(m)
			if !containsMsg(errs, "may only cross explicit unsafe boundaries") {
				t.Fatalf("nested raw pointer use accepted:\n%s", Errors(errs).String())
			}
		})
	}

	t.Run("return boundary", func(t *testing.T) {
		m, err := mir.Parse(header + `fn @identity(%box: @Box) -> @Box {
entry:
  return %box
}
`)
		if err != nil {
			t.Fatal(err)
		}
		if errs := Module(m); len(errs) != 0 {
			t.Fatalf("explicit return boundary rejected:\n%s", Errors(errs).String())
		}
	})
}

func containsMsg(errs []Error, substr string) bool {
	for _, e := range errs {
		if strings.Contains(e.String(), substr) {
			return true
		}
	}
	return false
}

func TestAPIBuiltRecursivePrintParseVerify(t *testing.T) {
	m := mir.NewModule()
	m.FormatVersion = 1
	a := m.AddFunction("a", nil, mir.TypeUnit)
	b := m.AddFunction("b", nil, mir.TypeUnit)
	ab := a.AddBlock("entry", nil)
	ab.AddInstr(mir.Instr{Op: mir.OpCall, Result: mir.NoValue, Callee: 1, FailTarget: mir.NoBlock})
	ab.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})
	bb := b.AddBlock("entry", nil)
	bb.AddInstr(mir.Instr{Op: mir.OpCall, Result: mir.NoValue, Callee: 0, FailTarget: mir.NoBlock})
	bb.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: mir.NoValue})

	parsed, err := mir.Parse(mir.Print(m))
	if err != nil {
		t.Fatalf("parse recursive API module: %v", err)
	}
	if errs := Module(parsed); len(errs) != 0 {
		t.Fatalf("verify recursive API module:\n%s", Errors(errs).String())
	}
}

func TestOwnedStringAndBytesConstants(t *testing.T) {
	m := mir.NewModule()
	m.AddConst("utf8", m.String(), mir.ConstValue{Kind: mir.ConstString, String: "\x00\x7f\xc2\x80\xf4\x8f\xbf\xbf"})
	m.AddConst("bytes", m.Bytes(), mir.ConstValue{Kind: mir.ConstString, String: "\x00\x80\xff"})
	if errs := Module(m); len(errs) != 0 {
		t.Fatalf("valid constants rejected:\n%s", Errors(errs).String())
	}

	m.AddConst("invalid_utf8", m.String(), mir.ConstValue{Kind: mir.ConstString, String: "\x80"})
	if errs := Module(m); !containsMsg(errs, "string constant must contain valid UTF-8") {
		t.Fatalf("invalid UTF-8 not rejected:\n%s", Errors(errs).String())
	}

	// The private source-bootstrap string lowers to slice(u8) until M7.3, so
	// MIR continues to admit that internal constant representation.
	bootstrap := mir.NewModule()
	bootstrap.AddConst("private", bootstrap.Slice(mir.TypeU8), mir.ConstValue{Kind: mir.ConstString, String: "x"})
	if errs := Module(bootstrap); len(errs) != 0 {
		t.Fatalf("private bootstrap string rejected:\n%s", Errors(errs).String())
	}

	incompatible := mir.NewModule()
	incompatible.AddConst("bad", incompatible.Slice(mir.TypeU16), mir.ConstValue{Kind: mir.ConstString, String: "x"})
	if errs := Module(incompatible); !containsMsg(errs, "byte-sequence constant has incompatible type") {
		t.Fatalf("incompatible constant not rejected:\n%s", Errors(errs).String())
	}
}

func TestClosureFormatOps(t *testing.T) {
	if errs := Module(mustParse(t, `mir 5

const @c_one: u64 = 1

fn @apply(%f: function(fn(u64) -> u64), %x: u64) -> u64 {
bb0:
  %r = call.value %f(%x)
  return %r
}
`)); len(errs) != 0 {
		t.Fatalf("call.value accepted module rejected: %s", Errors(errs).String())
	}
	if errs := Module(mustParse(t, `mir 5

fn @ignore(%x: u64) {
bb0:
  return
}

fn @apply(%f: function(fn(u64) -> unit), %x: u64) {
bb0:
  call.value %f(%x)
  return
}
`)); len(errs) != 0 {
		t.Fatalf("unit call.value without a result rejected: %s", Errors(errs).String())
	}
	if _, err := mir.Parse(`mir 5

fn @apply(%f: function(fn(u64) -> u64), %x: u64) {
bb0:
  call.value %f(%x)
  return
}
`); err == nil || !strings.Contains(err.Error(), "produces a value; bind it") {
		t.Fatalf("non-unit call.value without a result not rejected: %v", err)
	}
	if errs := Module(mustParse(t, `mir 5

fn @apply(%f: function(fn(u64) -> u64), %x: i64) -> u64 {
bb0:
  %r = call.value %f(%x)
  return %r
}
`)); len(errs) == 0 || !containsMsg(errs, "call.value argument 0") {
		t.Fatalf("call.value argument mismatch not reported:\n%s", Errors(errs).String())
	}
	if errs := Module(mustParse(t, `mir 5

fn @eq(%a: string, %b: string) -> bool {
bb0:
  %r = str.eq %a, %b
  return %r
}
`)); len(errs) != 0 {
		t.Fatalf("str.eq accepted module rejected:\n%s", Errors(errs).String())
	}
	if errs := Module(mustParse(t, `mir 5

fn @eq(%a: string, %b: u64) -> bool {
bb0:
  %r = str.eq %a, %b
  return %r
}
`)); len(errs) == 0 || !containsMsg(errs, "str.eq operands must have the same type") {
		t.Fatalf("str.eq mismatched operands not reported:\n%s", Errors(errs).String())
	}
	if _, err := mir.Parse(`mir 4

fn @apply(%f: function(fn(u64) -> u64), %x: u64) -> u64 {
bb0:
  %r = call.value %f(%x)
  return %r
}
`); err == nil || !strings.Contains(err.Error(), "requires MIR format version 5") {
		t.Fatalf("call.value in format 4 not rejected: %v", err)
	}
}

func mustParse(t *testing.T, text string) *mir.Module {
	t.Helper()
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v\n%s", err, text)
	}
	return m
}

func TestNoreturnCallAllowsReachableUnreachable(t *testing.T) {
	text := `mir 6

fn @panic() noreturn {
bb0:
  return
}

fn @caller() {
bb0:
  call @panic()
  unreachable
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	if errs := Module(m); len(errs) != 0 {
		t.Fatalf("noreturn call should admit unreachable: %s", Errors(errs).String())
	}

	plain := strings.Replace(text, "fn @panic() noreturn {", "fn @panic() {", 1)
	m, err = mir.Parse(plain)
	if err != nil {
		t.Fatal(err)
	}
	errs := Module(m)
	if len(errs) == 0 || !strings.Contains(Errors(errs).String(), "unreachable terminator in a reachable block") {
		t.Fatalf("unmarked callee should reject reachable unreachable: %v", errs)
	}
}
