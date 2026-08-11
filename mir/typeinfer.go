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

// InferResultType computes the result type of a value-producing instruction
// from its operands, or false when the instruction is not well-typed. The
// parser uses this to build typed values; the verifier uses it to validate
// stored value types. Non-producing operations return false.
func (m *Module) InferResultType(f *Function, in *Instr) (TypeId, bool) {
	switch in.Op {
	case OpLoad:
		return m.PlaceType(f, &in.Place)

	case OpAggregateConstruct:
		if !m.ValidType(in.AggType) || m.Types[in.AggType].Kind != TypeAggregate {
			return NoType, false
		}
		decl := &m.Types[in.AggType]
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
	case OpSliceRangeChecked:
		elem, ok := m.operandElemType(f, in.Slice)
		if !ok || !m.isU64(f, in.Lo) || !m.isU64(f, in.Hi) {
			return NoType, false
		}
		return m.Slice(elem), true
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
	}
	return NoType, false
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
