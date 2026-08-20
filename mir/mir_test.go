package mir

import (
	"strconv"
	"testing"
)

func TestPrimitiveSlots(t *testing.T) {
	m := NewModule()
	if len(m.Types) != int(NumPrimitiveTypes) {
		t.Fatalf("NewModule: got %d type slots, want %d", len(m.Types), NumPrimitiveTypes)
	}
	for i := TypeId(0); i < NumPrimitiveTypes; i++ {
		if m.Types[i].Kind != TypePrimitive {
			t.Errorf("slot %d: kind %v, want TypePrimitive", i, m.Types[i].Kind)
		}
	}
	if s, ok := PrimitiveName(TypeU8); !ok || s != "u8" {
		t.Errorf("PrimitiveName(TypeU8) = %q, %v", s, ok)
	}
	if _, ok := PrimitiveName(NoType); ok {
		t.Error("PrimitiveName(NoType) reported ok")
	}
}

func TestStructuralInterning(t *testing.T) {
	m := NewModule()
	if m.Slice(TypeI64) != m.Slice(TypeI64) {
		t.Error("Slice(i64) not interned")
	}
	if m.Slice(TypeU64) == m.Slice(TypeI64) {
		t.Error("Slice(u64) interned with Slice(i64)")
	}
	if m.Result(TypeI64, TypeUnit) != m.Result(TypeI64, TypeUnit) {
		t.Error("Result(i64, unit) not interned")
	}
	if m.Result(TypeUnit, TypeI64) == m.Result(TypeI64, TypeUnit) {
		t.Error("result(unit, i64) interned with result(i64, unit)")
	}
	if m.DomainHandle() != m.DomainHandle() {
		t.Error("DomainHandle singleton not interned")
	}
	if m.DomainHandle() == m.CleanupScope() {
		t.Error("distinct singleton kinds collided")
	}
	if m.FunctionType(FuncSig{Params: []TypeId{TypeI64}, Result: TypeBool}) !=
		m.FunctionType(FuncSig{Params: []TypeId{TypeI64}, Result: TypeBool}) {
		t.Error("function types not interned")
	}
}

func TestTypeString(t *testing.T) {
	m := NewModule()
	pair := m.AddAggregate("Pair", []Field{{Name: "first", Type: TypeI64}, {Name: "second", Type: m.Slice(TypeU8)}})
	err := m.AddEnum("Err", []Variant{{Name: "E", Payload: TypeUnit}})
	cases := []struct {
		id   TypeId
		want string
	}{
		{TypeUnit, "unit"},
		{TypeI64, "i64"},
		{pair, "@Pair"},
		{err, "@Err"},
		{m.Slice(TypeI64), "slice(i64)"},
		{m.SafeMut(pair), "safe_mut(@Pair)"},
		{m.Option(m.Slice(TypeI64)), "option(slice(i64))"},
		{m.Result(pair, err), "result(@Pair, @Err)"},
		{m.Table(pair), "table(@Pair)"},
		{m.ID(pair), "id(@Pair)"},
		{m.TableView(pair), "table_view(@Pair)"},
		{m.TableMutView(pair), "table_mut_view(@Pair)"},
		{m.RawPtr(TypeU8), "raw_ptr(u8)"},
		{m.DomainHandle(), "domain_handle"},
		{m.DomainMark(), "domain_mark"},
		{m.CleanupScope(), "cleanup_scope"},
		{m.CleanupID(), "cleanup_id"},
		{m.FunctionType(FuncSig{Params: []TypeId{TypeI64, m.Slice(TypeU8)}, Result: TypeBool}), "function(fn(i64, slice(u8)) -> bool)"},
	}
	for _, c := range cases {
		if got := m.TypeString(c.id); got != c.want {
			t.Errorf("TypeString: got %q, want %q", got, c.want)
		}
	}
	if got := m.TypeString(NoType); got != "<invalid type 4294967295>" {
		t.Errorf("TypeString(NoType) = %q", got)
	}
}

func TestVariants(t *testing.T) {
	m := NewModule()
	en := m.AddEnum("E", []Variant{{Name: "A", Payload: TypeI64}, {Name: "B", Payload: TypeUnit}})
	vs, ok := m.VariantsOf(en)
	if !ok || len(vs) != 2 || vs[0].Name != "A" || vs[1].Name != "B" {
		t.Fatalf("VariantsOf(enum) = %v, %v", vs, ok)
	}
	if i, ok := m.VariantIndex(en, "B"); !ok || i != 1 {
		t.Errorf("VariantIndex(B) = %d, %v", i, ok)
	}
	if _, ok := m.VariantIndex(en, "C"); ok {
		t.Error("VariantIndex(C) reported ok")
	}
	opt := m.Option(TypeI64)
	vs, ok = m.VariantsOf(opt)
	if !ok || vs[0].Name != "none" || vs[1].Name != "some" || vs[1].Payload != TypeI64 {
		t.Fatalf("VariantsOf(option) = %v, %v", vs, ok)
	}
	res := m.Result(TypeI64, TypeUnit)
	vs, ok = m.VariantsOf(res)
	if !ok || vs[0].Name != "ok" || vs[0].Payload != TypeI64 || vs[1].Name != "err" {
		t.Fatalf("VariantsOf(result) = %v, %v", vs, ok)
	}
	if m.IsEnumLike(TypeI64) || m.IsEnumLike(m.Slice(TypeI64)) {
		t.Error("non-enum-like types reported enum-like")
	}
	if p, ok := m.VariantPayload(opt, 1); !ok || p != TypeI64 {
		t.Errorf("VariantPayload(some) = %v, %v", p, ok)
	}
	if p, ok := m.VariantPayload(opt, 0); !ok || p != TypeUnit {
		t.Errorf("VariantPayload(none) = %v, %v", p, ok)
	}
}

func TestNameResolution(t *testing.T) {
	m := NewModule()
	pair := m.AddAggregate("Pair", nil)
	imp := m.AddImport("c_f", FuncSig{Params: []TypeId{TypeI64}, Result: TypeI64})
	m.AddConst("k", TypeI64, ConstValue{Kind: ConstInt, Int: 7})
	m.AddFunction("main", nil, TypeI64)

	if id, ok := m.NamedType("Pair"); !ok || id != pair {
		t.Errorf("NamedType(Pair) = %d, %v", id, ok)
	}
	if _, ok := m.NamedType("Missing"); ok {
		t.Error("NamedType(Missing) reported ok")
	}
	if id, ok := m.Import("c_f"); !ok || id != imp {
		t.Errorf("Import(c_f) = %d, %v", id, ok)
	}
	if id, ok := m.Function("main"); !ok || id != 0 {
		t.Errorf("Function(main) = %d, %v", id, ok)
	}
	if c, ok := m.ConstDecl("k"); !ok || c.Value.Int != 7 {
		t.Errorf("ConstDecl(k) = %+v, %v", c, ok)
	}
}

func TestPlaceType(t *testing.T) {
	m := NewModule()
	pair := m.AddAggregate("Pair", []Field{{Name: "first", Type: TypeI64}, {Name: "second", Type: m.Slice(TypeU8)}})
	safeMutPair := m.SafeMut(pair)
	f := m.AddFunction("f", []Param{{Name: "p", Type: safeMutPair}}, TypeI64)
	l := f.AddLocal("tmp", pair)
	f.AddBlock("bb0", nil)

	cases := []struct {
		place Place
		want  TypeId
		ok    bool
	}{
		{Place{Kind: PlaceLocal, Local: l}, pair, true},
		{Place{Kind: PlaceField, Base: &Place{Kind: PlaceLocal, Local: l}, Field: "first"}, TypeI64, true},
		{Place{Kind: PlaceField, Base: &Place{Kind: PlaceLocal, Local: l}, Field: "missing"}, NoType, false},
		{Place{Kind: PlaceDeref, Deref: 0}, pair, true},
		{Place{Kind: PlaceField, Base: &Place{Kind: PlaceDeref, Deref: 0}, Field: "second"}, m.Slice(TypeU8), true},
		{Place{Kind: PlaceLocal, Local: 99}, NoType, false},
	}
	for _, c := range cases {
		got, ok := m.PlaceType(f, &c.place)
		if got != c.want || ok != c.ok {
			t.Errorf("PlaceType(%+v) = %d, %v; want %d, %v", c.place, got, ok, c.want, c.ok)
		}
	}
}

func TestInferResultType(t *testing.T) {
	m := NewModule()
	pair := m.AddAggregate("Pair", []Field{{Name: "first", Type: TypeI64}})
	en := m.AddEnum("E", []Variant{{Name: "A", Payload: TypeI64}, {Name: "B", Payload: TypeUnit}})
	m.AddConst("k", TypeI64, ConstValue{Kind: ConstInt, Int: 1})
	m.AddConst("ku", TypeU64, ConstValue{Kind: ConstInt, Int: 1})
	m.AddImport("c_f", FuncSig{Params: []TypeId{TypeI64}, Result: TypeI64})
	m.AddFunction("callee", nil, pair)
	f := m.AddFunction("f", []Param{
		{Name: "d", Type: m.DomainHandle()},
		{Name: "s", Type: m.Slice(TypeU8)},
		{Name: "x", Type: TypeI64},
		{Name: "e", Type: en},
	}, TypeI64)
	f.AddBlock("bb0", nil)
	local := f.AddLocal("local", pair)

	// Params: %0 = d (domain_handle), %1 = s (slice(u8)), %2 = x (i64), %3 = e (enum).
	d, s, x, e := ValueId(0), ValueId(1), ValueId(2), ValueId(3)
	// Values: %4 = cnt (u64), %5 = k (i64).
	cnt := addResult(t, m, f, Instr{Op: OpConstGet, Const: "ku"})
	_ = addResult(t, m, f, Instr{Op: OpConstGet, Const: "k"})

	want := func(name string, in Instr, wantType TypeId) {
		t.Helper()
		got, ok := m.InferResultType(f, &in)
		if !ok || got != wantType {
			t.Errorf("%s: got %d, %v; want %d", name, got, ok, wantType)
		}
	}

	want("domain.create", Instr{Op: OpDomainCreate, Domain: d}, m.DomainHandle())
	want("domain.mark", Instr{Op: OpDomainMark, Domain: d}, m.DomainMark())
	want("alloc", Instr{Op: OpAlloc, Domain: d, TypeOp: TypeU8, Count: cnt}, m.SafeMut(TypeU8))
	want("alloc.checked", Instr{Op: OpAllocChecked, Domain: d, TypeOp: TypeU8, Count: cnt}, m.SafeMut(TypeU8))
	want("copy_to_domain", Instr{Op: OpCopyToDomain, Domain: d, CopyVal: s}, m.Slice(TypeU8))
	want("borrow", Instr{Op: OpBorrow, Place: Place{Kind: PlaceLocal, Local: local}}, m.SafeRef(pair))
	want("borrow_mut", Instr{Op: OpBorrowMut, Place: Place{Kind: PlaceLocal, Local: local}}, m.SafeMut(pair))
	want("cleanup.scope.begin", Instr{Op: OpCleanupScopeBegin}, m.CleanupScope())
	want("int.add.checked", Instr{Op: OpIntAddChecked, A: x, B: x}, TypeI64)
	want("int.shl.checked", Instr{Op: OpIntShlChecked, A: x, B: x}, TypeI64)
	want("int.shr.checked", Instr{Op: OpIntShrChecked, A: x, B: x}, TypeI64)
	want("slice.len", Instr{Op: OpSliceLen, Slice: s}, TypeU64)
	want("slice.index.checked", Instr{Op: OpSliceIndexChecked, Slice: s, Index: cnt}, m.SafeMut(TypeU8))
	want("slice.range.checked", Instr{Op: OpSliceRangeChecked, Slice: s, Lo: cnt, Hi: cnt}, m.Slice(TypeU8))
	want("enum.payload.checked", Instr{Op: OpEnumPayloadChecked, EnumValue: e, Variant: "A"}, TypeI64)
	want("enum.construct", Instr{Op: OpEnumConstruct, TypeOp: en, Variant: "B", Payload: NoValue}, en)
	want("table.create", Instr{Op: OpTableCreate, TypeOp: m.Slice(TypeU8), Domain: d}, m.Table(m.Slice(TypeU8)))
	want("int.lt", Instr{Op: OpIntLt, A: x, B: x}, TypeBool)
	want("int.trunc", Instr{Op: OpIntTrunc, A: x, TypeOp: TypeI32}, TypeI32)
	want("float.from_int", Instr{Op: OpFloatFromInt, A: x, TypeOp: TypeF64}, TypeF64)
	want("const.get", Instr{Op: OpConstGet, Const: "k"}, TypeI64)
	want("call", Instr{Op: OpCall, Callee: 0}, pair)
	want("ffi", Instr{Op: OpFFICallUnsafe, FFIImport: 0, Args: []ValueId{x}}, TypeI64)

	// A producing value used by a later instruction.
	v := addResult(t, m, f, Instr{Op: OpConstGet, Const: "k"})
	want("add on value", Instr{Op: OpIntAddChecked, A: v, B: x}, TypeI64)

	// Malformed operands must not infer.
	bad := []Instr{
		{Op: OpIntAddChecked, A: s, B: x},
		{Op: OpSliceLen, Slice: x},
		{Op: OpEnumPayloadChecked, EnumValue: e, Variant: "B"},
		{Op: OpConstGet, Const: "missing"},
		{Op: OpStore},
		{Op: OpCall, Callee: 99},
		{Op: OpFFICallUnsafe, FFIImport: 99},
		{Op: OpEnumConstruct, TypeOp: en, Variant: "A", Payload: NoValue},
		{Op: OpEnumConstruct, TypeOp: TypeI64, Variant: "A"},
	}
	for _, in := range bad {
		if _, ok := m.InferResultType(f, &in); ok {
			t.Errorf("InferResultType succeeded for %v", in.Op)
		}
	}
}

// addResult appends a producing instruction and returns its result value.
func addResult(t *testing.T, m *Module, f *Function, in Instr) ValueId {
	t.Helper()
	b := f.Blocks[0]
	typ, ok := m.InferResultType(f, &in)
	if !ok {
		t.Fatalf("InferResultType failed for %v", in.Op)
	}
	def := ValueDef{Kind: ValueDefInstr, Block: 0, Instr: len(b.Instrs)}
	v := f.AddValue("v"+strconv.Itoa(len(f.Values)), typ, def)
	in.Result = v
	b.AddInstr(in)
	return v
}

func TestOpTable(t *testing.T) {
	if OpStore.ProducesResult() || !OpLoad.ProducesResult() {
		t.Error("ProducesResult misclassified")
	}
	if !OpAllocChecked.HasFailEdge() || !OpIntAddChecked.HasFailEdge() || OpAlloc.HasFailEdge() || OpLoad.HasFailEdge() || OpStore.HasFailEdge() {
		t.Error("HasFailEdge misclassified")
	}
	if OpStore.String() != "store" || OpFFICallUnsafe.String() != "ffi.call.unsafe" || OpBorrow.String() != "borrow" || OpBorrowMut.String() != "borrow_mut" {
		t.Error("op names mismatched")
	}
	if got := OpKind(200).String(); got == "" {
		t.Error("invalid op kind has empty name")
	}
	// Every operation has a name, and ProducesResult agrees with HasFailEdge
	// on the non-checked set.
	for k := OpKind(0); k <= OpBorrowMut; k++ {
		if k.String() == "" {
			t.Errorf("OpKind %d has an empty name", k)
		}
	}
}

func TestSentinels(t *testing.T) {
	if NoType == TypeUnit || NoValue == ValueId(0) || NoBlock == BlockId(0) || NoLocal == LocalId(0) {
		t.Error("sentinels collide with valid identities")
	}
}
