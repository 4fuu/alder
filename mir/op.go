package mir

import "strconv"

// OpKind identifies a MIR instruction operation.
type OpKind uint8

const (

	// FnValueDomainMarker is the type_op flag a fn.value carries when its
	// environment operand supplies the callee's hidden leading domain
	// parameter. The value sits far outside any real type id range so it can
	// Places and aggregates.
	OpLoad OpKind = iota
	OpStore
	OpAggregateConstruct

	// Storage domains.
	OpDomainCreate
	OpDomainMark
	OpDomainReset
	OpDomainDestroy
	OpAlloc
	OpAllocChecked
	OpCopyToDomain

	// Scoped cleanup.
	OpCleanupScopeBegin
	OpCleanupPush
	OpCleanupDisarm
	OpCleanupScopeRun
	OpCleanupScopeEnd

	// Checked operations with explicit failure edges.
	OpIntAddChecked
	OpIntSubChecked
	OpIntMulChecked
	OpIntDivChecked
	OpIntShlChecked
	OpIntShrChecked
	OpSliceLen
	OpSliceIndexChecked
	OpSliceRangeChecked
	OpEnumPayloadChecked
	OpEnumConstruct

	// Generational tables.
	OpTableCreate
	OpTableInsert
	OpTableLookup
	OpTableLookupMut
	OpTableRemove
	OpTableViewEnd

	// Comparisons (result type bool).
	OpIntEq
	OpIntNe
	OpIntLt
	OpIntLe
	OpIntGt
	OpIntGe
	OpFloatEq
	OpFloatNe
	OpFloatLt
	OpFloatLe
	OpFloatGt
	OpFloatGe

	// Conversions with an explicit result type operand.
	OpIntTrunc
	OpIntZext
	OpIntSext
	OpFloatConvert
	OpIntFromFloat
	OpFloatFromInt

	// Constants and calls.
	OpConstGet
	OpCall
	OpFFICallUnsafe
	OpBorrow
	OpBorrowMut
	OpArrayIndexChecked
	OpVecNew
	OpVecConstructChecked
	OpVecGrowChecked
	OpVecLen
	OpVecCapacity
	OpVecStorage
	OpVecAsSlice
	OpVecAsMutSlice
	OpArrayAsSlice
	OpCallValue
	OpStrEq
	OpFnValue
	// Fallible table insertion carries no failure edge: exhaustion and the
	// slot-limit policy surface as the Err payload of the result value.
	OpTableInsertTry
	// OpCBindingCall is one unsafe root call to a binding-block C function.
	// CBinding is the flattened block-major index into Module.Bindings.
	OpCBindingCall
	// OpCIsNull is the one safe raw-pointer observation: null test.
	OpCIsNull

	// Non-terminating integer arithmetic: the try forms produce option(T)
	// (none on overflow), the saturating forms clamp at the type bounds, and
	// the wrapping forms wrap modulo 2^width. None of them carries a failure
	// edge.
	OpIntAddTry
	OpIntSubTry
	OpIntMulTry
	OpIntAddSaturating
	OpIntSubSaturating
	OpIntMulSaturating
	OpIntAddWrapping
	OpIntSubWrapping
	OpIntMulWrapping

	// Byte-sequence surface over the owned string and bytes value types.
	// len and byte read expose the byte backing; concat and the checked
	// slice build fresh domain-owned storage; to_bytes reinterprets a
	// string's bytes; from_bytes validates UTF-8 and yields none on invalid
	// input, with allocation failure on the failure edge.
	OpStrLen
	OpStrByteChecked
	OpStrConcat
	OpStrSliceChecked
	OpStrToBytes
	OpStrFromBytes

	// Integer conversion methods (M8): produced only by named builtin
	// method calls on integer receivers (to_T_checked and to_T_wrapping;
	// the total to_T lowers to zext/sext). Both carry the target type in
	// the type slot; neither has a failure edge. checked yields none when
	// the value is outside the target range and some otherwise; wrap keeps
	// the value's low bits at the target width in two's complement.
	OpIntConvertChecked
	OpIntConvertWrap
	// Explicit conversions across the C boundary: try produces option(T)
	// (none when the value does not fit T on this target), wrap applies the
	// C cast modulo pattern, and cast covers the total pairs. All three read
	// one operand and name their target through TypeOp.
	OpCNumTry
	OpCNumWrap
	OpCNumCast

	// Plain IEEE-754 float arithmetic: both operands share one float type,
	// the result carries that type, and none of them carries a failure
	// edge. Division by zero is defined at the MIR level (signed infinity,
	// NaN for 0/0); the C backend realizes it through the runtime helper.
	OpFloatAdd
	OpFloatSub
	OpFloatMul
	OpFloatDiv

	// OpStrOrderLt reports whether the left String or Bytes value orders
	// strictly before the right one in unsigned byte-lexicographic order
	// with the shorter prefix ordering first.
	OpStrOrderLt
	// FnValueDomainMarker is the type_op flag a fn.value carries when its
	// environment operand supplies the callee's hidden leading domain
	// parameter. The value sits far outside any real type id range so it can
	// never collide with an op that reads type_op as a type.
	FnValueDomainMarker TypeId = 2147483647
)

// String returns the canonical textual name of the operation.
func (k OpKind) String() string {
	switch k {
	case OpLoad:
		return "load"
	case OpStore:
		return "store"
	case OpAggregateConstruct:
		return "aggregate.construct"
	case OpDomainCreate:
		return "domain.create"
	case OpDomainMark:
		return "domain.mark"
	case OpDomainReset:
		return "domain.reset"
	case OpDomainDestroy:
		return "domain.destroy"
	case OpAlloc:
		return "alloc"
	case OpAllocChecked:
		return "alloc.checked"
	case OpCopyToDomain:
		return "copy_to_domain"
	case OpCleanupScopeBegin:
		return "cleanup.scope.begin"
	case OpCleanupPush:
		return "cleanup.push"
	case OpCleanupDisarm:
		return "cleanup.disarm"
	case OpCleanupScopeRun:
		return "cleanup.scope.run"
	case OpCleanupScopeEnd:
		return "cleanup.scope.end"
	case OpIntAddChecked:
		return "int.add.checked"
	case OpIntSubChecked:
		return "int.sub.checked"
	case OpIntMulChecked:
		return "int.mul.checked"
	case OpIntDivChecked:
		return "int.div.checked"
	case OpIntShlChecked:
		return "int.shl.checked"
	case OpIntShrChecked:
		return "int.shr.checked"
	case OpSliceLen:
		return "slice.len"
	case OpSliceIndexChecked:
		return "slice.index.checked"
	case OpSliceRangeChecked:
		return "slice.range.checked"
	case OpEnumPayloadChecked:
		return "enum.payload.checked"
	case OpEnumConstruct:
		return "enum.construct"
	case OpTableCreate:
		return "table.create"
	case OpTableInsert:
		return "table.insert"
	case OpTableLookup:
		return "table.lookup"
	case OpTableLookupMut:
		return "table.lookup_mut"
	case OpTableRemove:
		return "table.remove"
	case OpTableViewEnd:
		return "table.view.end"
	case OpIntEq:
		return "int.eq"
	case OpIntNe:
		return "int.ne"
	case OpIntLt:
		return "int.lt"
	case OpIntLe:
		return "int.le"
	case OpIntGt:
		return "int.gt"
	case OpIntGe:
		return "int.ge"
	case OpFloatEq:
		return "float.eq"
	case OpFloatNe:
		return "float.ne"
	case OpFloatLt:
		return "float.lt"
	case OpFloatLe:
		return "float.le"
	case OpFloatGt:
		return "float.gt"
	case OpFloatGe:
		return "float.ge"
	case OpIntTrunc:
		return "int.trunc"
	case OpIntZext:
		return "int.zext"
	case OpIntSext:
		return "int.sext"
	case OpFloatConvert:
		return "float.convert"
	case OpIntFromFloat:
		return "int.from_float"
	case OpFloatFromInt:
		return "float.from_int"
	case OpConstGet:
		return "const.get"
	case OpCall:
		return "call"
	case OpFFICallUnsafe:
		return "ffi.call.unsafe"
	case OpBorrow:
		return "borrow"
	case OpBorrowMut:
		return "borrow_mut"
	case OpArrayIndexChecked:
		return "array.index.checked"
	case OpVecNew:
		return "vec.new"
	case OpVecConstructChecked:
		return "vec.construct.checked"
	case OpVecGrowChecked:
		return "vec.grow.checked"
	case OpVecLen:
		return "vec.len"
	case OpVecCapacity:
		return "vec.capacity"
	case OpVecStorage:
		return "vec.storage"
	case OpVecAsSlice:
		return "vec.as_slice"
	case OpVecAsMutSlice:
		return "vec.as_mut_slice"
	case OpArrayAsSlice:
		return "array.as_slice"
	case OpCallValue:
		return "call.value"
	case OpStrEq:
		return "str.eq"
	case OpFnValue:
		return "fn.value"
	case OpTableInsertTry:
		return "table.insert.try"
	case OpCBindingCall:
		return "c.call.unsafe"
	case OpCIsNull:
		return "c.is_null"
	case OpIntAddTry:
		return "int.add.try"
	case OpIntSubTry:
		return "int.sub.try"
	case OpIntMulTry:
		return "int.mul.try"
	case OpIntAddSaturating:
		return "int.add.saturating"
	case OpIntSubSaturating:
		return "int.sub.saturating"
	case OpIntMulSaturating:
		return "int.mul.saturating"
	case OpIntAddWrapping:
		return "int.add.wrapping"
	case OpIntSubWrapping:
		return "int.sub.wrapping"
	case OpIntMulWrapping:
		return "int.mul.wrapping"
	case OpStrLen:
		return "str.len"
	case OpStrByteChecked:
		return "str.byte.checked"
	case OpStrConcat:
		return "str.concat"
	case OpStrSliceChecked:
		return "str.slice.checked"
	case OpStrToBytes:
		return "str.to_bytes"
	case OpStrFromBytes:
		return "str.from_bytes"
	case OpIntConvertChecked:
		return "int.convert.checked"
	case OpIntConvertWrap:
		return "int.convert.wrap"
	case OpCNumTry:
		return "c.num.try"
	case OpCNumWrap:
		return "c.num.wrap"
	case OpCNumCast:
		return "c.num.cast"
	case OpFloatAdd:
		return "float.add"
	case OpFloatSub:
		return "float.sub"
	case OpFloatMul:
		return "float.mul"
	case OpFloatDiv:
		return "float.div"
	case OpStrOrderLt:
		return "str.order_lt"
	}
	return "op(" + strconv.Itoa(int(k)) + ")"
}

// ProducesResult reports whether the operation defines a result value.
func (k OpKind) ProducesResult() bool {
	switch k {
	case OpStore, OpDomainReset, OpDomainDestroy, OpCleanupDisarm,
		OpCleanupScopeRun, OpCleanupScopeEnd, OpTableViewEnd:
		return false
	}
	return true
}

// HasFailEdge reports whether the operation carries an explicit failure edge.
// Checked operations require the edge; all other operations forbid it.
func (k OpKind) HasFailEdge() bool {
	switch k {
	case OpAllocChecked, OpIntAddChecked, OpIntSubChecked, OpIntMulChecked, OpIntDivChecked,
		OpIntShlChecked, OpIntShrChecked, OpSliceIndexChecked, OpSliceRangeChecked,
		OpEnumPayloadChecked, OpArrayIndexChecked:
		return true
	case OpVecConstructChecked, OpVecGrowChecked:
		return true
	case OpStrByteChecked, OpStrConcat, OpStrSliceChecked, OpStrFromBytes:
		return true
	}
	return false
}
