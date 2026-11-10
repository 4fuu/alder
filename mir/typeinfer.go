package mir

// PlaceType returns the type of a place, or false when the place is not
// well-formed: an unknown local, a field of a non-aggregate, an unknown field
// name, or a deref of a value that is not a checked reference.
func (m *Module) PlaceType(f *Function, p *Place) (TypeId, bool) {
	if m == nil || f == nil || p == nil {
		return NoType, false
	}
	var fields []string
	seen := make(map[*Place]bool)
	for {
		if p == nil || seen[p] {
			return NoType, false
		}
		seen[p] = true
		switch p.Kind {
		case PlaceField:
			fields = append(fields, p.Field)
			p = p.Base
			continue
		case PlaceLocal:
			if int(p.Local) >= len(f.Locals) {
				return NoType, false
			}
			return m.fieldPathType(f.Locals[p.Local].Type, fields)
		case PlaceDeref:
			t, ok := f.ValueType(p.Deref)
			if !ok || !m.ValidType(t) {
				return NoType, false
			}
			switch m.Types[t].Kind {
			case TypeSafeRef, TypeSafeMut, TypeTableView, TypeTableMutView:
				return m.fieldPathType(m.Types[t].Elem, fields)
			}
			return NoType, false
		default:
			return NoType, false
		}
	}
}

func (m *Module) fieldPathType(t TypeId, fields []string) (TypeId, bool) {
	for i := len(fields) - 1; i >= 0; i-- {
		if !m.ValidType(t) || m.Types[t].Kind != TypeAggregate {
			return NoType, false
		}
		found := false
		for _, fld := range m.Types[t].Fields {
			if fld.Name == fields[i] {
				t = fld.Type
				found = true
				break
			}
		}
		if !found {
			return NoType, false
		}
	}
	return t, true
}

// IsIntType reports whether t is one of the integer primitive types.
func IsIntType(t TypeId) bool {
	return t >= TypeI8 && t <= TypeU64
}

// IsFloatType reports whether t is f32 or f64.
func IsFloatType(t TypeId) bool {
	return t == TypeF32 || t == TypeF64
}

// intSigned reports whether an integer primitive is signed.
func intSigned(t TypeId) bool {
	return t >= TypeI8 && t <= TypeI64
}

// intWidth returns the bit width of an integer primitive.
func intWidth(t TypeId) int {
	switch t {
	case TypeI8, TypeU8:
		return 8
	case TypeI16, TypeU16:
		return 16
	case TypeI32, TypeU32:
		return 32
	case TypeI64, TypeU64:
		return 64
	}
	return 0
}

// CNumWorldOf classifies a c.num conversion endpoint's world: 1 an Alder
// numeric primitive, 2 a c_raw scalar, 0 anything else.
func CNumWorldOf(m *Module, t TypeId) int {
	if IsIntType(t) || IsFloatType(t) {
		return 1
	}
	if m.ValidType(t) && m.Types[t].Kind == TypeCRaw {
		return 2
	}
	return 0
}

// CNumClassOf classifies a c.num conversion endpoint's numeric class:
// 1 integer, 2 IEEE single, 3 IEEE double, 0 anything else. c_raw size_t
// and ptrdiff_t are integer scalars like the fixed-width C integers.
func CNumClassOf(m *Module, t TypeId) int {
	if IsIntType(t) {
		return 1
	}
	if t == TypeF32 {
		return 2
	}
	if t == TypeF64 {
		return 3
	}
	if m.ValidType(t) && m.Types[t].Kind == TypeCRaw {
		switch id := m.Types[t].Length; {
		case id <= CScalarULongLong || id == CScalarSize || id == CScalarPtrdiff:
			return 1
		case id == CScalarFloat:
			return 2
		case id == CScalarDouble:
			return 3
		}
	}
	return 0
}

// CNumPairClass classifies one C-boundary conversion pair: 0 invalid,
// 1 integer across the boundary, 2 float same precision, 3 float widening
// (c.Float -> F64). The two endpoints must live on opposite sides of the
// boundary.
func CNumPairClass(m *Module, source, target TypeId) int {
	sw := CNumWorldOf(m, source)
	tw := CNumWorldOf(m, target)
	if sw == 0 || tw == 0 || sw == tw {
		return 0
	}
	sc := CNumClassOf(m, source)
	tc := CNumClassOf(m, target)
	if sc == 1 && tc == 1 {
		return 1
	}
	if sc == 2 && tc == 3 {
		return 3
	}
	if sc == tc {
		return 2
	}
	return 0
}

// InferResultType computes the result type of a value-producing instruction
// from its operands, or false when the instruction is not well-typed. The
// parser uses this to build typed values; the verifier uses it to validate
// stored value types. Non-producing operations return false.
func (m *Module) InferResultType(f *Function, in *Instr) (TypeId, bool) {
	switch in.Op {
	case OpLoad:
		return m.PlaceType(f, &in.Place)
	case OpBorrow, OpBorrowMut:
		placeType, ok := m.PlaceType(f, &in.Place)
		if !ok {
			return NoType, false
		}
		if in.Op == OpBorrow {
			return m.SafeRef(placeType), true
		}
		return m.SafeMut(placeType), true

	case OpAggregateConstruct:
		if !m.ValidType(in.AggType) {
			return NoType, false
		}
		decl := &m.Types[in.AggType]
		if decl.Kind == TypeArray {
			if uint64(len(in.AggFields)) != decl.Length {
				return NoType, false
			}
			for _, af := range in.AggFields {
				if vt, ok := f.ValueType(af.Value); !ok || vt != decl.Elem {
					return NoType, false
				}
			}
			return in.AggType, true
		}
		if decl.Kind != TypeAggregate {
			return NoType, false
		}
		if len(in.AggFields) != len(decl.Fields) {
			return NoType, false
		}
		for _, af := range in.AggFields {
			ft, ok := declField(decl, af.Name)
			if !ok {
				return NoType, false
			}
			if vt, ok := f.ValueType(af.Value); !ok || vt != ft {
				return NoType, false
			}
		}
		return in.AggType, true

	case OpDomainCreate:
		if !m.isHandleType(f, in.Domain) {
			return NoType, false
		}
		return m.DomainHandle(), true
	case OpDomainMark:
		if !m.isHandleType(f, in.Domain) {
			return NoType, false
		}
		return m.DomainMark(), true
	case OpAlloc, OpAllocChecked:
		if !m.isHandleType(f, in.Domain) || !m.isU64(f, in.Count) || !m.ValidType(in.TypeOp) {
			return NoType, false
		}
		return m.SafeMut(in.TypeOp), true
	case OpCopyToDomain:
		if !m.isHandleType(f, in.Domain) {
			return NoType, false
		}
		return f.ValueType(in.CopyVal)

	case OpCleanupScopeBegin:
		return m.CleanupScope(), true
	case OpCleanupPush:
		if !m.isType(f, in.Scope, m.CleanupScope()) || int(in.CleanupFn) >= len(m.Functions) {
			return NoType, false
		}
		callee := m.Functions[in.CleanupFn]
		if callee == nil {
			return NoType, false
		}
		if callee.Result != TypeUnit || len(in.CleanupArgs) != len(callee.Params) {
			return NoType, false
		}
		for i, a := range in.CleanupArgs {
			if vt, ok := f.ValueType(a); !ok || vt != callee.Params[i].Type {
				return NoType, false
			}
		}
		return m.CleanupID(), true

	case OpIntAddChecked, OpIntSubChecked, OpIntMulChecked, OpIntDivChecked, OpIntShlChecked, OpIntShrChecked:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) {
			return NoType, false
		}
		if tb, ok := f.ValueType(in.B); !ok || tb != ta {
			return NoType, false
		}
		return ta, true

	case OpIntAddTry, OpIntSubTry, OpIntMulTry, OpIntAddSaturating, OpIntSubSaturating, OpIntMulSaturating,
		OpIntAddWrapping, OpIntSubWrapping, OpIntMulWrapping:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) {
			return NoType, false
		}
		if tb, ok := f.ValueType(in.B); !ok || tb != ta {
			return NoType, false
		}
		if in.Op <= OpIntMulTry {
			return m.Option(ta), true
		}
		return ta, true

	case OpSliceLen:
		if _, ok := m.operandElemType(f, in.Slice); !ok {
			return NoType, false
		}
		return TypeU64, true
	case OpSliceIndexChecked:
		elem, ok := m.operandElemType(f, in.Slice)
		if !ok || !m.isU64(f, in.Index) {
			return NoType, false
		}
		return m.SafeMut(elem), true
	case OpArrayIndexChecked:
		t, ok := f.ValueType(in.Array)
		if !ok || !m.ValidType(t) || !m.isU64(f, in.Index) {
			return NoType, false
		}
		if m.Types[t].Kind == TypeSafeMut {
			t = m.Types[t].Elem
		}
		if !m.ValidType(t) || m.Types[t].Kind != TypeArray {
			return NoType, false
		}
		return m.SafeMut(m.Types[t].Elem), true
	case OpSliceRangeChecked:
		elem, ok := m.operandElemType(f, in.Slice)
		if !ok || !m.isU64(f, in.Lo) || !m.isU64(f, in.Hi) {
			return NoType, false
		}
		return m.Slice(elem), true
	case OpVecNew:
		if !m.ValidType(in.TypeOp) || m.Types[in.TypeOp].Kind != TypeVec {
			return NoType, false
		}
		return in.TypeOp, true
	case OpVecConstructChecked:
		elem, ok := m.operandElemType(f, in.Slice)
		if !ok || !m.isU64(f, in.Lo) || !m.isU64(f, in.Capacity) {
			return NoType, false
		}
		return m.Vec(elem), true
	case OpVecGrowChecked:
		t, ok := f.ValueType(in.Slice)
		if !ok || !m.ValidType(t) || m.Types[t].Kind != TypeVec || !m.isHandleType(f, in.Domain) || !m.isU64(f, in.Capacity) {
			return NoType, false
		}
		return t, true
	case OpVecLen, OpVecCapacity:
		t, ok := f.ValueType(in.Slice)
		if !ok || !m.ValidType(t) || m.Types[t].Kind != TypeVec {
			return NoType, false
		}
		return TypeU64, true
	case OpVecStorage, OpVecAsMutSlice:
		t, ok := f.ValueType(in.Slice)
		if !ok || !m.ValidType(t) || m.Types[t].Kind != TypeVec {
			return NoType, false
		}
		return m.SafeMut(m.Types[t].Elem), true
	case OpVecAsSlice:
		t, ok := f.ValueType(in.Slice)
		if !ok || !m.ValidType(t) || m.Types[t].Kind != TypeVec {
			return NoType, false
		}
		return m.Slice(m.Types[t].Elem), true
	case OpArrayAsSlice:
		t, ok := f.ValueType(in.Array)
		if !ok || !m.ValidType(t) {
			return NoType, false
		}
		if m.Types[t].Kind == TypeSafeRef || m.Types[t].Kind == TypeSafeMut {
			t = m.Types[t].Elem
		}
		if !m.ValidType(t) || m.Types[t].Kind != TypeArray {
			return NoType, false
		}
		return m.Slice(m.Types[t].Elem), true
	case OpEnumPayloadChecked:
		t, ok := f.ValueType(in.EnumValue)
		if !ok {
			return NoType, false
		}
		idx, ok := m.VariantIndex(t, in.Variant)
		if !ok {
			return NoType, false
		}
		payload, ok := m.VariantPayload(t, idx)
		if !ok || payload == TypeUnit {
			return NoType, false
		}
		return payload, true
	case OpEnumConstruct:
		if !m.ValidType(in.TypeOp) || !m.IsEnumLike(in.TypeOp) {
			return NoType, false
		}
		idx, ok := m.VariantIndex(in.TypeOp, in.Variant)
		if !ok {
			return NoType, false
		}
		payload, _ := m.VariantPayload(in.TypeOp, idx)
		if payload == TypeUnit {
			if in.Payload != NoValue {
				return NoType, false
			}
		} else if vt, ok := f.ValueType(in.Payload); !ok || vt != payload {
			return NoType, false
		}
		return in.TypeOp, true

	case OpTableCreate:
		if !m.isHandleType(f, in.Domain) || !m.ValidType(in.TypeOp) {
			return NoType, false
		}
		return m.Table(in.TypeOp), true
	case OpTableInsert:
		elem, ok := m.tableElem(f, in.Table)
		if !ok {
			return NoType, false
		}
		if vt, ok := f.ValueType(in.TableVal); !ok || vt != elem {
			return NoType, false
		}
		return m.ID(elem), true
	case OpTableInsertTry:
		elem, ok := m.tableElem(f, in.Table)
		if !ok {
			return NoType, false
		}
		if vt, ok := f.ValueType(in.TableVal); !ok || vt != elem {
			return NoType, false
		}
		// Ok carries the fresh id; Err carries the element value back to the
		// caller, so an affine element would stay owned by its caller.
		return m.Result(m.ID(elem), elem), true
	case OpTableLookup, OpTableLookupMut:
		elem, ok := m.tableElem(f, in.Table)
		if !ok {
			return NoType, false
		}
		if vt, ok := f.ValueType(in.ID); !ok || vt != m.ID(elem) {
			return NoType, false
		}
		if in.Op == OpTableLookup {
			return m.Option(m.TableView(elem)), true
		}
		return m.Option(m.TableMutView(elem)), true
	case OpTableRemove:
		elem, ok := m.tableElem(f, in.Table)
		if !ok {
			return NoType, false
		}
		if vt, ok := f.ValueType(in.ID); !ok || vt != m.ID(elem) {
			return NoType, false
		}
		return TypeBool, true

	case OpIntEq, OpIntNe, OpIntLt, OpIntLe, OpIntGt, OpIntGe:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) {
			return NoType, false
		}
		if tb, ok := f.ValueType(in.B); !ok || tb != ta {
			return NoType, false
		}
		return TypeBool, true

	case OpStrEq:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(ta) || (m.Types[ta].Kind != TypeString && m.Types[ta].Kind != TypeBytes) {
			return NoType, false
		}
		if tb, ok := f.ValueType(in.B); !ok || tb != ta {
			return NoType, false
		}
		return TypeBool, true

	case OpStrLen, OpStrByteChecked, OpStrToBytes:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(ta) || (m.Types[ta].Kind != TypeString && m.Types[ta].Kind != TypeBytes) {
			return NoType, false
		}
		switch in.Op {
		case OpStrLen:
			return TypeU64, true
		case OpStrToBytes:
			if m.Types[ta].Kind != TypeString {
				return NoType, false
			}
			return m.Bytes(), true
		default:
			if !m.isU64(f, in.B) {
				return NoType, false
			}
			return TypeU8, true
		}

	case OpStrConcat, OpStrSliceChecked, OpStrFromBytes:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(ta) || (m.Types[ta].Kind != TypeString && m.Types[ta].Kind != TypeBytes) {
			return NoType, false
		}
		if !m.isHandleType(f, in.Domain) {
			return NoType, false
		}
		switch in.Op {
		case OpStrConcat:
			if tb, ok := f.ValueType(in.B); !ok || tb != ta {
				return NoType, false
			}
			return ta, true
		case OpStrSliceChecked:
			if !m.isU64(f, in.Lo) || !m.isU64(f, in.Hi) {
				return NoType, false
			}
			return ta, true
		default:
			if m.Types[ta].Kind != TypeBytes {
				return NoType, false
			}
			return m.Option(m.String()), true
		}

	case OpCallValue:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(ta) || m.Types[ta].Kind != TypeFunction {
			return NoType, false
		}
		return m.Types[ta].Sig.Result, true

	case OpFnValue:
		if int(in.Callee) >= len(m.Functions) || m.Functions[in.Callee] == nil {
			return NoType, false
		}
		callee := m.Functions[in.Callee]
		// The function value's type erases the environment: {code, env}
		// values carry the environment opaquely, so closures and plain
		// references of the same signature share one value type. The
		// environment operand's own type still feeds provenance in phase 6.
		sig := FuncSig{Result: callee.Result, Env: NoType}
		params := callee.Params
		// A closure thunk's trailing parameter is the environment record;
		// it is supplied by the environment operand, not by callers of the
		// function value.
		if in.A != NoValue && in.TypeOp != FnValueDomainMarker && len(params) > 0 {
			params = params[:len(params)-1]
		}
		// The domain marker instead names a storage-model target: its
		// leading parameter is the hidden domain supplied through the
		// environment operand, so the erased type covers the parameters
		// after it.
		if in.TypeOp == FnValueDomainMarker {
			if in.A == NoValue || len(params) == 0 {
				return NoType, false
			}
			if m.Types[params[0].Type].Kind != TypeDomainHandle {
				return NoType, false
			}
			if ta, ok := f.ValueType(in.A); !ok || !m.ValidType(ta) || m.Types[ta].Kind != TypeDomainHandle {
				return NoType, false
			}
			params = params[1:]
		}
		for _, p := range params {
			sig.Params = append(sig.Params, p.Type)
		}
		return m.FunctionType(sig), true

	case OpFloatEq, OpFloatNe, OpFloatLt, OpFloatLe, OpFloatGt, OpFloatGe:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsFloatType(ta) {
			return NoType, false
		}
		if tb, ok := f.ValueType(in.B); !ok || tb != ta {
			return NoType, false
		}
		return TypeBool, true

	case OpIntTrunc:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) || !m.ValidType(in.TypeOp) || !IsIntType(in.TypeOp) ||
			intSigned(ta) != intSigned(in.TypeOp) || intWidth(in.TypeOp) >= intWidth(ta) {
			return NoType, false
		}
		return in.TypeOp, true
	case OpIntZext:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) || !m.ValidType(in.TypeOp) || !IsIntType(in.TypeOp) ||
			intSigned(ta) || intWidth(in.TypeOp) <= intWidth(ta) {
			return NoType, false
		}
		return in.TypeOp, true
	case OpIntSext:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) || !m.ValidType(in.TypeOp) || !IsIntType(in.TypeOp) ||
			!intSigned(ta) || intWidth(in.TypeOp) <= intWidth(ta) {
			return NoType, false
		}
		return in.TypeOp, true
	case OpIntConvertChecked, OpIntConvertWrap:
		// Conversion methods: the value and the target type must both be
		// integers. The pair legality (total, lossy, or identity) is a
		// source-language contract the checker enforces; MIR accepts any
		// integer pair and defines the semantics for each.
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) || !m.ValidType(in.TypeOp) || !IsIntType(in.TypeOp) {
			return NoType, false
		}
		if in.Op == OpIntConvertChecked {
			return m.Option(in.TypeOp), true
		}
		return in.TypeOp, true
	case OpFloatConvert:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsFloatType(ta) || !m.ValidType(in.TypeOp) || !IsFloatType(in.TypeOp) {
			return NoType, false
		}
		return in.TypeOp, true
	case OpIntFromFloat:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsFloatType(ta) || !m.ValidType(in.TypeOp) || !IsIntType(in.TypeOp) {
			return NoType, false
		}
		return in.TypeOp, true
	case OpFloatFromInt:
		ta, ok := f.ValueType(in.A)
		if !ok || !IsIntType(ta) || !m.ValidType(in.TypeOp) || !IsFloatType(in.TypeOp) {
			return NoType, false
		}
		return in.TypeOp, true

	case OpCNumTry:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(in.TypeOp) || m.Types[in.TypeOp].Kind != TypeOption {
			return NoType, false
		}
		class := CNumPairClass(m, ta, m.Types[in.TypeOp].Elem)
		if class == 1 || (CNumClassOf(m, ta) == 3 && CNumClassOf(m, m.Types[in.TypeOp].Elem) == 2) {
			return in.TypeOp, true
		}
		return NoType, false
	case OpCNumWrap:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(in.TypeOp) || CNumPairClass(m, ta, in.TypeOp) != 1 {
			return NoType, false
		}
		return in.TypeOp, true
	case OpCNumCast:
		ta, ok := f.ValueType(in.A)
		if !ok || !m.ValidType(in.TypeOp) || CNumPairClass(m, ta, in.TypeOp) == 0 {
			return NoType, false
		}
		return in.TypeOp, true

	case OpConstGet:
		c, ok := m.ConstDecl(in.Const)
		if !ok {
			return NoType, false
		}
		return c.Type, true

	case OpCall:
		if int(in.Callee) >= len(m.Functions) {
			return NoType, false
		}
		callee := m.Functions[in.Callee]
		if callee == nil {
			return NoType, false
		}
		if len(in.Args) != len(callee.Params) {
			return NoType, false
		}
		for i, a := range in.Args {
			if vt, ok := f.ValueType(a); !ok || vt != callee.Params[i].Type {
				return NoType, false
			}
		}
		return callee.Result, true

	case OpFFICallUnsafe:
		if int(in.FFIImport) >= len(m.Imports) {
			return NoType, false
		}
		imp := &m.Imports[in.FFIImport]
		if len(in.Args) != len(imp.Sig.Params) {
			return NoType, false
		}
		for i, a := range in.Args {
			if vt, ok := f.ValueType(a); !ok || vt != imp.Sig.Params[i] {
				return NoType, false
			}
		}
		return imp.Sig.Result, true

	case OpCBindingCall:
		_, fn, ok := m.BindingFuncAt(in.CBinding)
		if !ok {
			return NoType, false
		}
		if len(in.Args) != len(fn.Sig.Params) {
			return NoType, false
		}
		for i, a := range in.Args {
			if vt, ok := f.ValueType(a); !ok || !m.BindingArgCompatible(vt, fn.Sig.Params[i]) {
				return NoType, false
			}
		}
		return fn.Sig.Result, true

	case OpCIsNull:
		if in.A == NoValue {
			return NoType, false
		}
		if vt, ok := f.ValueType(in.A); ok && m.IsRawPointerType(vt) {
			return TypeBool, true
		}
		return NoType, false
	}
	return NoType, false
}

// isRawPointerType reports whether t is a raw C pointer token or the legacy
// bootstrap raw_ptr type.
func (m *Module) IsRawPointerType(t TypeId) bool {
	if !m.ValidType(t) {
		return false
	}
	switch m.Types[t].Kind {
	case TypeRawPtr, TypeCPtr, TypeCConstPtr:
		return true
	}
	return false
}

// BindingArgCompatible reports whether a value of type arg may be passed to a
// binding declaration parameter of type want. Types must match exactly, with
// one widening: c_ptr(E) passes where c_const_ptr(E) is declared, mirroring
// C's mutable-to-const pointer conversion.
func (m *Module) BindingArgCompatible(arg, want TypeId) bool {
	if arg == want {
		return true
	}
	if !m.ValidType(arg) || !m.ValidType(want) {
		return false
	}
	at, wt := m.Types[arg], m.Types[want]
	if at.Kind != TypeCPtr || wt.Kind != TypeCConstPtr {
		return false
	}
	return at.Elem == wt.Elem
}

func declField(t *Type, name string) (TypeId, bool) {
	for _, fld := range t.Fields {
		if fld.Name == name {
			return fld.Type, true
		}
	}
	return NoType, false
}

// isHandleType reports whether a value has the singleton domain_handle type.
func (m *Module) isHandleType(f *Function, v ValueId) bool {
	t, ok := f.ValueType(v)
	return ok && t == m.DomainHandle()
}

// isU64 reports whether a value has type u64.
func (m *Module) isU64(f *Function, v ValueId) bool {
	t, ok := f.ValueType(v)
	return ok && t == TypeU64
}

// isType reports whether a value has exactly the given type.
func (m *Module) isType(f *Function, v ValueId, want TypeId) bool {
	t, ok := f.ValueType(v)
	return ok && t == want
}

// tableElem returns the element type of a table-typed value.
func (m *Module) tableElem(f *Function, v ValueId) (TypeId, bool) {
	t, ok := f.ValueType(v)
	if !ok || !m.ValidType(t) || m.Types[t].Kind != TypeTable {
		return NoType, false
	}
	return m.Types[t].Elem, true
}

// operandElemType returns the element type of a slice, safe_ref, or safe_mut
// operand used by slice operations.
func (m *Module) operandElemType(f *Function, v ValueId) (TypeId, bool) {
	t, ok := f.ValueType(v)
	if !ok {
		return NoType, false
	}
	return m.ElemType(t)
}
