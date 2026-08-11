package mir

import "strconv"

// OpKind identifies a MIR instruction operation.
type OpKind uint8

const (
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
	case OpIntAddChecked, OpIntSubChecked, OpIntMulChecked, OpIntDivChecked,
		OpIntShlChecked, OpIntShrChecked, OpSliceIndexChecked, OpSliceRangeChecked,
		OpEnumPayloadChecked:
		return true
	}
	return false
}
