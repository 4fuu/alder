package verify

import (
	"fmt"

	"github.com/4fuu/alder/mir"
)

// phase5Typing checks place well-formedness and mutability, instruction
// operand and result types, terminator operand types, and edge argument types
// against target block parameters. It also compares stored result types
// against the types inferred from the operation.
func phase5Typing(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		for vi, value := range f.Values {
			if (value.Def.Kind == mir.ValueDefBlockParam || value.Def.Kind == mir.ValueDefSwitchCase) && !m.ValidType(value.Type) {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("value %s has no valid type", valueName(f, mir.ValueId(vi)))})
			}
		}
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for i := range b.Instrs {
				errs = append(errs, checkInstrTypes(m, f, b, i, &b.Instrs[i])...)
			}
			errs = append(errs, checkTermTypes(m, f, b)...)
		}
	}
	return errs
}

// typeChecker bundles the per-instruction diagnostic helpers.
type typeChecker struct {
	errs []Error
	loc  string
	m    *mir.Module
	f    *mir.Function
}

func (c *typeChecker) expect(v mir.ValueId, what string, ok func(mir.TypeId) bool, wantDesc string) {
	t, found := c.f.ValueType(v)
	if !found || t == mir.NoType {
		return // out of range or unknown: reported elsewhere
	}
	if !ok(t) {
		c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("%s: expected %s, got %s", what, wantDesc, c.m.TypeString(t))})
	}
}

func (c *typeChecker) expectExact(v mir.ValueId, what string, want mir.TypeId) {
	t, found := c.f.ValueType(v)
	if !found || t == mir.NoType {
		return
	}
	if t != want {
		c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("%s: expected %s, got %s", what, c.m.TypeString(want), c.m.TypeString(t))})
	}
}

func (c *typeChecker) expectSamePair(a, b mir.ValueId, what string, ok func(mir.TypeId) bool, wantDesc string) {
	ta, foundA := c.f.ValueType(a)
	tb, foundB := c.f.ValueType(b)
	if !foundA || !foundB || ta == mir.NoType || tb == mir.NoType {
		return
	}
	if !ok(ta) {
		c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("%s: expected %s, got %s", what, wantDesc, c.m.TypeString(ta))})
		return
	}
	if ta != tb {
		c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("%s: operand types differ: %s and %s", what, c.m.TypeString(ta), c.m.TypeString(tb))})
	}
}

func checkInstrTypes(m *mir.Module, f *mir.Function, b *mir.Block, i int, in *mir.Instr) []Error {
	c := &typeChecker{loc: locInstr(f, b, i, in), m: m, f: f}
	errBaseline := len(c.errs)

	switch in.Op {
	case mir.OpLoad, mir.OpBorrow, mir.OpBorrowMut:
		if _, ok := m.PlaceType(f, &in.Place); !ok {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "place is not well-formed"})
		}
		if in.Op == mir.OpBorrowMut && !placeMutable(m, f, &in.Place) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "mutable borrow target is read-only"})
		}

	case mir.OpStore:
		pt, ok := m.PlaceType(f, &in.Place)
		if !ok {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "place is not well-formed"})
			break
		}
		if !placeMutable(m, f, &in.Place) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "store target is read-only"})
		}
		c.expectExact(in.StoreVal, "store value", pt)

	case mir.OpAggregateConstruct:
		if !m.ValidType(in.AggType) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "aggregate type operand is not an aggregate or array"})
			break
		}
		decl := &m.Types[in.AggType]
		if decl.Kind == mir.TypeArray {
			if uint64(len(in.AggFields)) != decl.Length {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("aggregate.construct: expected %d elements, got %d", decl.Length, len(in.AggFields))})
				break
			}
			for j, elem := range in.AggFields {
				c.expectExact(elem.Value, fmt.Sprintf("aggregate.construct element %d", j), decl.Elem)
			}
			break
		}
		if decl.Kind != mir.TypeAggregate {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "aggregate type operand is not an aggregate or array"})
			break
		}
		if len(in.AggFields) != len(decl.Fields) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("aggregate.construct: expected %d fields, got %d", len(decl.Fields), len(in.AggFields))})
			break
		}
		for j, af := range in.AggFields {
			if af.Name != decl.Fields[j].Name {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("aggregate.construct: field %d: expected %q, got %q (fields must follow declaration order)", j, decl.Fields[j].Name, af.Name)})
				break
			}
			c.expectExact(af.Value, fmt.Sprintf("aggregate.construct field %q", af.Name), decl.Fields[j].Type)
		}

	case mir.OpDomainCreate, mir.OpDomainMark, mir.OpDomainDestroy, mir.OpTableCreate:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())

	case mir.OpDomainReset:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		c.expectExact(in.Mark, "mark operand", m.DomainMark())

	case mir.OpAlloc, mir.OpAllocChecked:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		c.expectExact(in.Count, "count operand", mir.TypeU64)
		if !m.ValidType(in.TypeOp) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "element type operand is out of range"})
		}

	case mir.OpCopyToDomain:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		// Result type equals the copied operand's type; checked below.

	case mir.OpCleanupScopeBegin:
		// no operands

	case mir.OpCleanupPush:
		c.expectExact(in.Scope, "scope operand", m.CleanupScope())
		if int(in.CleanupFn) < len(m.Functions) {
			callee := m.Functions[in.CleanupFn]
			if callee.Result != mir.TypeUnit {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("cleanup function @%s must return unit", callee.Name)})
			}
			if len(in.CleanupArgs) != len(callee.Params) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("cleanup.push: expected %d arguments, got %d", len(callee.Params), len(in.CleanupArgs))})
			} else {
				for j, a := range in.CleanupArgs {
					c.expectExact(a, fmt.Sprintf("cleanup argument %d", j), callee.Params[j].Type)
				}
			}
		}

	case mir.OpCleanupDisarm:
		c.expectExact(in.CleanupID, "cleanup id operand", m.CleanupID())

	case mir.OpCleanupScopeRun, mir.OpCleanupScopeEnd:
		c.expectExact(in.Scope, "scope operand", m.CleanupScope())

	case mir.OpIntAddChecked, mir.OpIntSubChecked, mir.OpIntMulChecked, mir.OpIntDivChecked, mir.OpIntShlChecked, mir.OpIntShrChecked:
		c.expectSamePair(in.A, in.B, "integer operand", mir.IsIntType, "an integer")

	case mir.OpIntAddTry, mir.OpIntSubTry, mir.OpIntMulTry,
		mir.OpIntAddSaturating, mir.OpIntSubSaturating, mir.OpIntMulSaturating,
		mir.OpIntAddWrapping, mir.OpIntSubWrapping, mir.OpIntMulWrapping:
		c.expectSamePair(in.A, in.B, "integer operand", mir.IsIntType, "an integer")

	case mir.OpSliceLen:
		c.expect(in.Slice, "slice operand", func(t mir.TypeId) bool {
			_, ok := m.ElemType(t)
			return ok
		}, "a slice, safe_ref, or safe_mut")

	case mir.OpSliceIndexChecked:
		c.expect(in.Slice, "slice operand", func(t mir.TypeId) bool {
			_, ok := m.ElemType(t)
			return ok
		}, "a slice, safe_ref, or safe_mut")
		c.expectExact(in.Index, "index operand", mir.TypeU64)

	case mir.OpArrayIndexChecked:
		c.expect(in.Array, "array operand", func(t mir.TypeId) bool {
			if !m.ValidType(t) {
				return false
			}
			if m.Types[t].Kind == mir.TypeSafeMut {
				t = m.Types[t].Elem
			}
			return m.ValidType(t) && m.Types[t].Kind == mir.TypeArray
		}, "an array or safe_mut(array)")
		c.expectExact(in.Index, "index operand", mir.TypeU64)

	case mir.OpArrayAsSlice:
		c.expect(in.Array, "array operand", func(t mir.TypeId) bool {
			if !m.ValidType(t) {
				return false
			}
			if m.Types[t].Kind == mir.TypeSafeRef || m.Types[t].Kind == mir.TypeSafeMut {
				t = m.Types[t].Elem
			}
			return m.ValidType(t) && m.Types[t].Kind == mir.TypeArray
		}, "an array, safe_ref(array), or safe_mut(array)")

	case mir.OpSliceRangeChecked:
		c.expect(in.Slice, "slice operand", func(t mir.TypeId) bool {
			_, ok := m.ElemType(t)
			return ok
		}, "a slice, safe_ref, or safe_mut")
		c.expectExact(in.Lo, "low operand", mir.TypeU64)
		c.expectExact(in.Hi, "high operand", mir.TypeU64)

	case mir.OpEnumPayloadChecked:
		if t, ok := f.ValueType(in.EnumValue); ok && t != mir.NoType {
			if !m.IsEnumLike(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("enum operand: expected an enum, option, or result, got %s", m.TypeString(t))})
			} else if _, ok := m.VariantIndex(t, in.Variant); !ok {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("unknown variant %q for %s", in.Variant, m.TypeString(t))})
			}
		}

	case mir.OpEnumConstruct:
		if !m.ValidType(in.TypeOp) || !m.IsEnumLike(in.TypeOp) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "type operand is not an enum, option, or result"})
			break
		}
		idx, ok := m.VariantIndex(in.TypeOp, in.Variant)
		if !ok {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("unknown variant %q for %s", in.Variant, m.TypeString(in.TypeOp))})
			break
		}
		payload, _ := m.VariantPayload(in.TypeOp, idx)
		if payload == mir.TypeUnit {
			if in.Payload != mir.NoValue {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("variant %q has no payload", in.Variant)})
			}
		} else if in.Payload == mir.NoValue {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("variant %q requires a payload", in.Variant)})
		} else {
			c.expectExact(in.Payload, "variant payload", payload)
		}

	case mir.OpTableInsert:
		if elem, ok := tableElem(m, f, in.Table); ok {
			c.expectExact(in.TableVal, "insert value", elem)
		}

	case mir.OpTableInsertTry:
		if elem, ok := tableElem(m, f, in.Table); ok {
			c.expectExact(in.TableVal, "insert value", elem)
		}

	case mir.OpTableLookup, mir.OpTableLookupMut, mir.OpTableRemove:
		if elem, ok := tableElem(m, f, in.Table); ok {
			c.expectExact(in.ID, "id operand", m.ID(elem))
		}

	case mir.OpTableViewEnd:
		if t, ok := f.ValueType(in.View); ok && t != mir.NoType && m.ValidType(t) {
			k := m.Types[t].Kind
			if k != mir.TypeTableView && k != mir.TypeTableMutView {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("view operand: expected a table view, got %s", m.TypeString(t))})
			}
		}

	case mir.OpIntEq, mir.OpIntNe, mir.OpIntLt, mir.OpIntLe, mir.OpIntGt, mir.OpIntGe:
		c.expectSamePair(in.A, in.B, "integer operand", mir.IsIntType, "an integer")

	case mir.OpFloatEq, mir.OpFloatNe, mir.OpFloatLt, mir.OpFloatLe, mir.OpFloatGt, mir.OpFloatGe:
		c.expectSamePair(in.A, in.B, "float operand", mir.IsFloatType, "a float")

	case mir.OpFloatAdd, mir.OpFloatSub, mir.OpFloatMul, mir.OpFloatDiv:
		c.expectSamePair(in.A, in.B, "float operand", mir.IsFloatType, "a float")

	case mir.OpIntTrunc:
		c.expect(in.A, "integer operand", mir.IsIntType, "an integer")
		if t, ok := f.ValueType(in.A); ok && t != mir.NoType && mir.IsIntType(t) && m.ValidType(in.TypeOp) && mir.IsIntType(in.TypeOp) {
			if signedness(t) != signedness(in.TypeOp) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.trunc requires the same signedness"})
			} else if intWidth(in.TypeOp) >= intWidth(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.trunc result type must be narrower"})
			}
		}
	case mir.OpIntZext:
		c.expect(in.A, "integer operand", mir.IsIntType, "an integer")
		if t, ok := f.ValueType(in.A); ok && t != mir.NoType && mir.IsIntType(t) && m.ValidType(in.TypeOp) && mir.IsIntType(in.TypeOp) {
			if signedness(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.zext requires an unsigned source"})
			} else if intWidth(in.TypeOp) <= intWidth(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.zext result type must be wider"})
			}
		}
	case mir.OpIntSext:
		c.expect(in.A, "integer operand", mir.IsIntType, "an integer")
		if t, ok := f.ValueType(in.A); ok && t != mir.NoType && mir.IsIntType(t) && m.ValidType(in.TypeOp) && mir.IsIntType(in.TypeOp) {
			if !signedness(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.sext requires a signed source"})
			} else if intWidth(in.TypeOp) <= intWidth(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.sext result type must be wider"})
			}
		}
	case mir.OpIntConvertChecked, mir.OpIntConvertWrap:
		// Conversion methods accept any integer pair at the MIR level; the
		// checker restricts which pairs each method name may produce.
		c.expect(in.A, "integer operand", mir.IsIntType, "an integer")
		if m.ValidType(in.TypeOp) && !mir.IsIntType(in.TypeOp) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "conversion method result type must be an integer"})
		}
	case mir.OpFloatConvert:
		c.expect(in.A, "float operand", mir.IsFloatType, "a float")
		if m.ValidType(in.TypeOp) && !mir.IsFloatType(in.TypeOp) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "float.convert result type must be f32 or f64"})
		}
	case mir.OpIntFromFloat:
		c.expect(in.A, "float operand", mir.IsFloatType, "a float")
		if m.ValidType(in.TypeOp) && !mir.IsIntType(in.TypeOp) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "int.from_float result type must be an integer"})
		}
	case mir.OpFloatFromInt:
		c.expect(in.A, "integer operand", mir.IsIntType, "an integer")
		if m.ValidType(in.TypeOp) && !mir.IsFloatType(in.TypeOp) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "float.from_int result type must be f32 or f64"})
		}

	case mir.OpCNumTry:
		ta, ok := f.ValueType(in.A)
		if !ok || ta == mir.NoType || !m.ValidType(in.TypeOp) || m.Types[in.TypeOp].Kind != mir.TypeOption {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.num.try result type must be option(T) of a C-boundary numeric"})
			break
		}
		elem := m.Types[in.TypeOp].Elem
		class := mir.CNumPairClass(m, ta, elem)
		narrow := mir.CNumClassOf(m, ta) == 3 && mir.CNumClassOf(m, elem) == 2
		if class != 1 && !narrow {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.num.try must cross the C boundary between an integer and an integer or narrow a double to a float"})
		}

	case mir.OpCNumWrap, mir.OpCNumCast:
		ta, ok := f.ValueType(in.A)
		if !ok || ta == mir.NoType || !m.ValidType(in.TypeOp) {
			break
		}
		class := mir.CNumPairClass(m, ta, in.TypeOp)
		if in.Op == mir.OpCNumWrap && class != 1 {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.num.wrap must cross the C boundary between two integers"})
		}
		if in.Op == mir.OpCNumCast && class == 0 {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.num.cast must cross the C boundary between matching numeric kinds"})
		}

	case mir.OpConstGet:
		// Constant existence is checked in phase 1; result type below.

	case mir.OpCall:
		if int(in.Callee) < len(m.Functions) {
			callee := m.Functions[in.Callee]
			if len(in.Args) != len(callee.Params) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("call @%s: expected %d arguments, got %d", callee.Name, len(callee.Params), len(in.Args))})
			} else {
				for j, a := range in.Args {
					c.expectExact(a, fmt.Sprintf("call argument %d", j), callee.Params[j].Type)
				}
			}
		}

	case mir.OpCallValue:
		ft, ok := f.ValueType(in.A)
		if ok && m.ValidType(ft) && m.Types[ft].Kind == mir.TypeFunction {
			sig := m.Types[ft].Sig
			if len(in.Args) != len(sig.Params) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("call.value: expected %d arguments, got %d", len(sig.Params), len(in.Args))})
			} else {
				for j, a := range in.Args {
					c.expectExact(a, fmt.Sprintf("call.value argument %d", j), sig.Params[j])
				}
			}
		} else {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "call.value function operand must have a function type"})
		}

	case mir.OpFnValue:
		// Result typing is derived in InferResultType; the target function
		// existence is checked in phase 1.

	case mir.OpStrEq:
		ta, _ := f.ValueType(in.A)
		tb, _ := f.ValueType(in.B)
		stringLike := func(t mir.TypeId) bool {
			return m.ValidType(t) && (m.Types[t].Kind == mir.TypeString || m.Types[t].Kind == mir.TypeBytes)
		}
		if !stringLike(ta) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "str.eq operands must be string or bytes"})
		} else if tb != ta {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "str.eq operands must have the same type"})
		}

	case mir.OpStrLen, mir.OpStrByteChecked, mir.OpStrToBytes:
		c.expect(in.A, "byte-sequence operand", func(t mir.TypeId) bool {
			return m.ValidType(t) && (m.Types[t].Kind == mir.TypeString || m.Types[t].Kind == mir.TypeBytes)
		}, "string or bytes")
		if in.Op == mir.OpStrByteChecked {
			c.expectExact(in.B, "index operand", mir.TypeU64)
		}
		if in.Op == mir.OpStrToBytes {
			if t, ok := f.ValueType(in.A); ok && m.ValidType(t) && m.Types[t].Kind != mir.TypeString {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "str.to_bytes operand must be string, not bytes"})
			}
		}

	case mir.OpStrConcat:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		c.expect(in.A, "byte-sequence operand", func(t mir.TypeId) bool {
			return m.ValidType(t) && (m.Types[t].Kind == mir.TypeString || m.Types[t].Kind == mir.TypeBytes)
		}, "string or bytes")
		c.expectSamePair(in.A, in.B, "byte-sequence operand", func(t mir.TypeId) bool {
			return m.ValidType(t) && (m.Types[t].Kind == mir.TypeString || m.Types[t].Kind == mir.TypeBytes)
		}, "string or bytes")

	case mir.OpStrSliceChecked:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		c.expect(in.A, "byte-sequence operand", func(t mir.TypeId) bool {
			return m.ValidType(t) && (m.Types[t].Kind == mir.TypeString || m.Types[t].Kind == mir.TypeBytes)
		}, "string or bytes")
		c.expectExact(in.Lo, "low operand", mir.TypeU64)
		c.expectExact(in.Hi, "high operand", mir.TypeU64)

	case mir.OpStrFromBytes:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		c.expect(in.A, "bytes operand", func(t mir.TypeId) bool {
			return m.ValidType(t) && m.Types[t].Kind == mir.TypeBytes
		}, "bytes")

	case mir.OpStrDisplay:
		c.expectExact(in.Domain, "domain operand", m.DomainHandle())
		c.expect(in.A, "display operand", func(t mir.TypeId) bool {
			return t == mir.TypeBool || t == mir.TypeI64 || t == mir.TypeU64
		}, "bool, i64, or u64")

	case mir.OpFFICallUnsafe:
		if int(in.FFIImport) < len(m.Imports) {
			imp := &m.Imports[in.FFIImport]
			if len(in.Args) != len(imp.Sig.Params) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("ffi.call.unsafe @%s: expected %d arguments, got %d", imp.Name, len(imp.Sig.Params), len(in.Args))})
			} else {
				for j, a := range in.Args {
					c.expectExact(a, fmt.Sprintf("ffi argument %d", j), imp.Sig.Params[j])
				}
			}
		}

	case mir.OpCBindingCall:
		_, fn, ok := m.BindingFuncAt(in.CBinding)
		if ok {
			if len(in.Args) != len(fn.Sig.Params) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("c.call.unsafe @%s: expected %d arguments, got %d", fn.Name, len(fn.Sig.Params), len(in.Args))})
			} else {
				for j, a := range in.Args {
					if t, ok := f.ValueType(a); !ok || !m.BindingArgCompatible(t, fn.Sig.Params[j]) {
						want := m.TypeString(fn.Sig.Params[j])
						got := "unknown"
						if t, ok := f.ValueType(a); ok {
							got = m.TypeString(t)
						}
						c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("c argument %d: expected %s, got %s", j, want, got)})
					}
				}
			}
		}

	case mir.OpCIsNull:
		if in.A != mir.NoValue {
			if t, ok := f.ValueType(in.A); !ok || !m.IsRawPointerType(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.is_null operand must be a raw C pointer"})
			}
		}
	case mir.OpStrOrderLt:
		ta, _ := f.ValueType(in.A)
		tb, _ := f.ValueType(in.B)
		stringLike := func(t mir.TypeId) bool {
			return m.ValidType(t) && (m.Types[t].Kind == mir.TypeString || m.Types[t].Kind == mir.TypeBytes)
		}
		if !stringLike(ta) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "str.order_lt operands must be string or bytes"})
		} else if tb != ta {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "str.order_lt operands must have the same type"})
		}

	case mir.OpCFieldGet, mir.OpCFieldSet:
		if in.Op == mir.OpCFieldGet {
			_, _, ok := m.CNamedRecordField(f, in.A, in.CField)
			if !ok {
				if t, tok := f.ValueType(in.A); tok && m.ValidType(t) && m.Types[t].Kind == mir.TypeCNamed && m.Types[t].CClass == mir.CClassRecord {
					c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("c.field %q is not a field of record @%s", in.CField, m.Types[t].Name)})
				} else {
					c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.field operand must be a record-class c_type value"})
				}
			}
			break
		}
		// The write form targets a place holding the record: the place
		// must be mutable and the stored value must have the field's type.
		pt, ok := m.PlaceType(f, &in.Place)
		if !ok {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.field.set place is not well-formed"})
			break
		}
		if !m.ValidType(pt) || m.Types[pt].Kind != mir.TypeCNamed || m.Types[pt].CClass != mir.CClassRecord {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.field.set place must hold a record-class c_type"})
			break
		}
		if !placeMutable(m, f, &in.Place) {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: "c.field.set target is read-only"})
		}
		var field *mir.Field
		for i := range m.Types[pt].Fields {
			if m.Types[pt].Fields[i].Name == in.CField {
				field = &m.Types[pt].Fields[i]
				break
			}
		}
		if field == nil {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("c.field %q is not a field of record @%s", in.CField, m.Types[pt].Name)})
			break
		}
		if t, tok := f.ValueType(in.A); tok && t != field.Type {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("c.field.set %q: expected %s, got %s", in.CField, m.TypeString(field.Type), m.TypeString(t))})
		}
	}

	// Checked failure edge arguments must match the failure target parameters.
	if in.FailTarget != mir.NoBlock && int(in.FailTarget) < len(f.Blocks) {
		checkEdgeArgTypes(c, f.Blocks[in.FailTarget], in.FailArgs)
	}

	// Stored result type must match the inferred result type.
	if in.Result != mir.NoValue {
		expected, ok := m.InferResultType(f, in)
		stored, found := f.ValueType(in.Result)
		if !ok {
			if len(c.errs) == errBaseline {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: "cannot infer result type from instruction operands"})
			}
		} else if found && stored == mir.NoType {
			// Only report the missing type when this instruction produced no
			// other errors; otherwise the operand checks explain the cause.
			if len(c.errs) == errBaseline {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("result value %s has no stored type", valueName(f, in.Result))})
			}
		} else if found && stored != expected {
			c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("result type mismatch: stored %s, expected %s", m.TypeString(stored), m.TypeString(expected))})
		}
	}
	return c.errs
}

func checkEdgeArgTypes(c *typeChecker, target *mir.Block, args []mir.ValueId) {
	if target == nil {
		return
	}
	if len(args) != len(target.Params) {
		return // count reported in phase 3
	}
	for j, a := range args {
		c.expectExact(a, fmt.Sprintf("edge argument %d", j), target.Params[j].Type)
	}
}

// placeMutable reports whether a store may target the place: locals and
// fields of mutable places are mutable; derefs of safe_ref and table_view are
// read-only.
func placeMutable(m *mir.Module, f *mir.Function, p *mir.Place) bool {
	switch p.Kind {
	case mir.PlaceLocal:
		return true
	case mir.PlaceField:
		return p.Base != nil && placeMutable(m, f, p.Base)
	case mir.PlaceDeref:
		if t, ok := f.ValueType(p.Deref); ok && m.ValidType(t) {
			return m.Types[t].Kind == mir.TypeSafeMut || m.Types[t].Kind == mir.TypeTableMutView
		}
	}
	return false
}

func tableElem(m *mir.Module, f *mir.Function, v mir.ValueId) (mir.TypeId, bool) {
	t, ok := f.ValueType(v)
	if !ok || !m.ValidType(t) || m.Types[t].Kind != mir.TypeTable {
		return mir.NoType, false
	}
	return m.Types[t].Elem, true
}

func signedness(t mir.TypeId) bool {
	return t >= mir.TypeI8 && t <= mir.TypeI64
}

func intWidth(t mir.TypeId) int {
	switch t {
	case mir.TypeI8, mir.TypeU8:
		return 8
	case mir.TypeI16, mir.TypeU16:
		return 16
	case mir.TypeI32, mir.TypeU32:
		return 32
	case mir.TypeI64, mir.TypeU64:
		return 64
	}
	return 0
}

func checkTermTypes(m *mir.Module, f *mir.Function, b *mir.Block) []Error {
	c := &typeChecker{loc: locTerm(f, b), m: m, f: f}
	switch b.Term.Kind {
	case mir.TermBranch:
		c.expectExact(b.Term.Cond, "branch condition", mir.TypeBool)
		checkEdgeArgTypes(c, targetBlock(f, b.Term.Then), b.Term.ThenArgs)
		checkEdgeArgTypes(c, targetBlock(f, b.Term.Else), b.Term.ElseArgs)

	case mir.TermJump:
		checkEdgeArgTypes(c, targetBlock(f, b.Term.Target), b.Term.Args)

	case mir.TermSwitch:
		if t, ok := f.ValueType(b.Term.Value); ok && t != mir.NoType {
			if !m.IsEnumLike(t) {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("switch operand: expected an enum, option, or result, got %s", m.TypeString(t))})
			} else {
				for i := range b.Term.Cases {
					cs := &b.Term.Cases[i]
					if cs.Variant == "" || cs.Binding == mir.NoValue {
						continue
					}
					idx, exists := m.VariantIndex(t, cs.Variant)
					if !exists {
						continue // reported in Phase 3
					}
					payload, _ := m.VariantPayload(t, idx)
					c.expectExact(cs.Binding, fmt.Sprintf("switch case %q payload binding", cs.Variant), payload)
				}
			}
		}
		for i := range b.Term.Cases {
			checkEdgeArgTypes(c, targetBlock(f, b.Term.Cases[i].Target), b.Term.Cases[i].Args)
		}

	case mir.TermReturn, mir.TermFail:
		if b.Term.Result == mir.NoValue {
			if f.Result != mir.TypeUnit {
				c.errs = append(c.errs, Error{Loc: c.loc, Msg: fmt.Sprintf("%s without a value requires result type unit, got %s", b.Term.Kind, m.TypeString(f.Result))})
			}
		} else {
			c.expectExact(b.Term.Result, fmt.Sprintf("%s operand", b.Term.Kind), f.Result)
		}
	}
	return c.errs
}

func targetBlock(f *mir.Function, id mir.BlockId) *mir.Block {
	if int(id) >= len(f.Blocks) {
		return nil
	}
	return f.Blocks[id]
}
