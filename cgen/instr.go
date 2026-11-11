package cgen

import (
	"strconv"
	"strings"

	"github.com/4fuu/alder/mir"
)

// place returns the C lvalue expression of a place.
func (g *gen) place(p *mir.Place) string {
	switch p.Kind {
	case mir.PlaceLocal:
		return "alder_l" + strconv.Itoa(int(p.Local))
	case mir.PlaceField:
		return g.place(p.Base) + "." + g.fieldName(p.Base, p.Field)
	case mir.PlaceDeref:
		t, ok := g.f.ValueType(p.Deref)
		if !ok || !g.m.ValidType(t) {
			return "<invalid deref>"
		}
		elem := g.m.Types[t].Elem
		base := g.valueExpr(p.Deref)
		switch g.m.Types[t].Kind {
		case mir.TypeSafeRef, mir.TypeSafeMut:
			base += ".data"
		}
		return "(*(" + g.cType(elem) + " *)" + base + ")"
	}
	return "<invalid place>"
}

// failBody emits the body of a checked operation's failure edge:
// block-parameter assignments followed by the goto.
func (g *gen) failBody(in *mir.Instr) string {
	return g.edgeBody(in.FailTarget, in.FailArgs)
}

// edgeBody stages edge arguments before assigning block parameters. MIR edge
// arguments are parallel copies, so direct sequential assignments would
// clobber sources on swaps and other cycles.
func (g *gen) edgeBody(target mir.BlockId, args []mir.ValueId) string {
	var b strings.Builder
	b.WriteString("{ ")
	edge := g.edgeUsed
	g.edgeUsed++
	type stagedArg struct {
		dest mir.ValueId
		temp string
	}
	var staged []stagedArg
	if int(target) < len(g.f.Blocks) {
		for i, arg := range args {
			dest, ok := g.paramValues[[2]int{int(target), i}]
			if !ok {
				continue
			}
			t, _ := g.f.ValueType(dest)
			if t == mir.TypeUnit {
				continue
			}
			temp := "alder_edge_" + strconv.Itoa(edge) + "_" + strconv.Itoa(i)
			b.WriteString(g.cType(t) + " " + temp + " = " + g.valueExpr(arg) + "; ")
			staged = append(staged, stagedArg{dest: dest, temp: temp})
		}
	}
	for _, arg := range staged {
		b.WriteString(g.val(arg.dest) + " = " + arg.temp + "; ")
	}
	b.WriteString("goto alder_b" + strconv.Itoa(int(target)) + "; }")
	return b.String()
}

// emitInstr lowers one instruction to explicit, sequenced C statements.
func (g *gen) emitInstr(b *strings.Builder, blk *mir.Block, in *mir.Instr) {
	switch in.Op {
	case mir.OpLoad:
		if t, _ := g.f.ValueType(in.Result); t != mir.TypeUnit {
			b.WriteString("  " + g.val(in.Result) + " = " + g.place(&in.Place) + ";\n")
		}
	case mir.OpBorrow, mir.OpBorrowMut:
		b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ (void *)&" + g.place(&in.Place) + ", (uint64_t)1 };\n")

	case mir.OpStore:
		b.WriteString("  " + g.place(&in.Place) + " = " + g.valueExpr(in.StoreVal) + ";\n")

	case mir.OpAggregateConstruct:
		if g.m.Types[in.AggType].Kind == mir.TypeArray {
			if len(in.AggFields) == 0 {
				b.WriteString("  " + g.val(in.Result) + " = (AlderTy" + strconv.Itoa(int(in.AggType)) + "){0};\n")
				break
			}
			b.WriteString("  " + g.val(in.Result) + " = (AlderTy" + strconv.Itoa(int(in.AggType)) + "){ .alder_e = {")
			for i, elem := range in.AggFields {
				if i > 0 {
					b.WriteString(", ")
				}
				b.WriteString(g.valueExpr(elem.Value))
			}
			b.WriteString("} };\n")
			break
		}
		if len(in.AggFields) == 0 {
			b.WriteString("  " + g.val(in.Result) + " = (AlderTy" + strconv.Itoa(int(in.AggType)) + "){0};\n")
			break
		}
		b.WriteString("  " + g.val(in.Result) + " = (AlderTy" + strconv.Itoa(int(in.AggType)) + "){")
		for i, af := range in.AggFields {
			if i > 0 {
				b.WriteString(", ")
			}
			field, _ := g.aggregateFieldIndex(in.AggType, af.Name)
			b.WriteString(".alder_f" + strconv.Itoa(field) + " = " + g.valueExpr(af.Value))
		}
		b.WriteString("};\n")

	case mir.OpDomainCreate:
		b.WriteString("  if (!alder_domain_init(&alder_domain_" + strconv.Itoa(g.domainUsed) +
			", " + g.valueExpr(in.Domain) + ")) { alder_runtime_panic(\"domain.create failed\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = &alder_domain_" + strconv.Itoa(g.domainUsed) + ";\n")
		g.domainUsed++

	case mir.OpDomainMark:
		b.WriteString("  " + g.val(in.Result) + " = alder_domain_mark(" + g.valueExpr(in.Domain) + ");\n")

	case mir.OpDomainReset:
		b.WriteString("  if (!alder_domain_reset(" + g.valueExpr(in.Domain) + ", " + g.valueExpr(in.Mark) +
			")) { alder_runtime_panic(\"domain.reset failed\"); }\n")

	case mir.OpDomainDestroy:
		b.WriteString("  alder_domain_destroy(" + g.valueExpr(in.Domain) + ");\n")

	case mir.OpAlloc:
		elem := in.TypeOp
		b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
		b.WriteString("  if (!alder_u64_mul_checked(" + g.valueExpr(in.Count) + ", " +
			g.typeSize(elem) + ", &" + g.tmp(in, "") + ")) { alder_runtime_panic(\"alloc: size overflow\"); }\n")
		b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)SIZE_MAX) { alder_runtime_panic(\"alloc: size exceeds size_t\"); }\n")
		b.WriteString("  void *" + g.tmp(in, "p") + " = alder_domain_alloc(" + g.valueExpr(in.Domain) +
			", (size_t)" + g.tmp(in, "") + ", (size_t)" + g.typeAlign(elem) + ");\n")
		b.WriteString("  if (" + g.tmp(in, "p") + " == NULL) { alder_runtime_panic(\"alloc: out of memory\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ " + g.tmp(in, "p") + ", " +
			g.valueExpr(in.Count) + " };\n")

	case mir.OpAllocChecked:
		elem := in.TypeOp
		b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
		b.WriteString("  if (!alder_u64_mul_checked(" + g.valueExpr(in.Count) + ", " +
			g.typeSize(elem) + ", &" + g.tmp(in, "") + ")) " + g.failBody(in) + "\n")
		b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)SIZE_MAX) " + g.failBody(in) + "\n")
		b.WriteString("  void *" + g.tmp(in, "p") + " = alder_domain_alloc(" + g.valueExpr(in.Domain) +
			", (size_t)" + g.tmp(in, "") + ", (size_t)" + g.typeAlign(elem) + ");\n")
		b.WriteString("  if (" + g.tmp(in, "p") + " == NULL) " + g.failBody(in) + "\n")
		b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ " + g.tmp(in, "p") + ", " +
			g.valueExpr(in.Count) + " };\n")

	case mir.OpCopyToDomain:
		t, ok := g.f.ValueType(in.CopyVal)
		if t == mir.TypeUnit {
			break
		}
		if ok && g.copyTrivial(t) {
			b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.CopyVal) + ";\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = alder_copy_ty" + strconv.Itoa(int(t)) +
				"(" + g.valueExpr(in.Domain) + ", " + g.valueExpr(in.CopyVal) + ", 1);\n")
		}

	case mir.OpCleanupScopeBegin:
		b.WriteString("  if (!alder_cleanup_scope_begin(&alder_scope_" + strconv.Itoa(g.scopeUsed) +
			")) { alder_runtime_panic(\"cleanup.scope.begin failed\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = &alder_scope_" + strconv.Itoa(g.scopeUsed) + ";\n")
		g.scopeUsed++

	case mir.OpCleanupPush:
		idx := g.pushSites[[3]int{int(fnIndexOf(g.m, g.f)), int(blockIndexOf(g.f, blk)), instrIndexOf(blk, in)}]
		callee := g.m.Functions[in.CleanupFn]
		arg := 0
		for ai, a := range in.CleanupArgs {
			if callee.Params[ai].Type == mir.TypeUnit {
				continue
			}
			b.WriteString("  alder_ctx_" + strconv.Itoa(idx) + ".alder_f" + strconv.Itoa(arg) +
				" = " + g.valueExpr(a) + ";\n")
			arg++
		}
		b.WriteString("  if (!alder_cleanup_push(" + g.valueExpr(in.Scope) + ", alder_cleanup_" +
			strconv.Itoa(idx) + ", &alder_ctx_" + strconv.Itoa(idx) + ", &" + g.val(in.Result) +
			")) { alder_runtime_panic(\"cleanup.push failed\"); }\n")

	case mir.OpCleanupDisarm:
		b.WriteString("  if (!alder_cleanup_disarm(" + g.valueExpr(in.CleanupID) +
			")) { alder_runtime_panic(\"cleanup.disarm failed\"); }\n")

	case mir.OpCleanupScopeRun:
		b.WriteString("  if (!alder_cleanup_run(" + g.valueExpr(in.Scope) +
			")) { alder_runtime_panic(\"cleanup.scope.run failed\"); }\n")

	case mir.OpCleanupScopeEnd:
		b.WriteString("  if (!alder_cleanup_end(" + g.valueExpr(in.Scope) +
			")) { alder_runtime_panic(\"cleanup.scope.end failed\"); }\n")

	case mir.OpIntAddChecked, mir.OpIntSubChecked, mir.OpIntMulChecked,
		mir.OpIntDivChecked, mir.OpIntShlChecked, mir.OpIntShrChecked:
		g.emitIntChecked(b, in)

	case mir.OpIntAddTry, mir.OpIntSubTry, mir.OpIntMulTry,
		mir.OpIntAddSaturating, mir.OpIntSubSaturating, mir.OpIntMulSaturating,
		mir.OpIntAddWrapping, mir.OpIntSubWrapping, mir.OpIntMulWrapping:
		g.emitIntMode(b, in)

	case mir.OpFloatAdd, mir.OpFloatSub, mir.OpFloatMul, mir.OpFloatDiv:
		g.emitFloatBinary(b, in)

	case mir.OpIntAnd, mir.OpIntOr, mir.OpIntXor, mir.OpIntNot:
		g.emitIntBitwise(b, in)

	case mir.OpSliceLen:
		b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.Slice) + ".len;\n")

	case mir.OpSliceIndexChecked:
		g.emitSliceIndex(b, in)

	case mir.OpArrayIndexChecked:
		t, _ := g.f.ValueType(in.Array)
		direct := g.m.Types[t].Kind == mir.TypeArray
		if !direct {
			t = g.m.Types[t].Elem
		}
		length := g.m.Types[t].Length
		b.WriteString("  if (" + g.valueExpr(in.Index) + " >= (uint64_t)" + strconv.FormatUint(length, 10) + ") { " + g.failBody(in) + " }\n")
		if direct {
			b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ (void *)&" + g.valueExpr(in.Array) + ".alder_e[" + g.valueExpr(in.Index) + "], (uint64_t)1 };\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ (void *)&((AlderTy" + strconv.Itoa(int(t)) + " *)" + g.valueExpr(in.Array) + ".data)->alder_e[" + g.valueExpr(in.Index) + "], (uint64_t)1 };\n")
		}

	case mir.OpArrayAsSlice:
		t, _ := g.f.ValueType(in.Array)
		direct := g.m.Types[t].Kind == mir.TypeArray
		if !direct {
			t = g.m.Types[t].Elem
		}
		length := g.m.Types[t].Length
		if direct {
			b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ (void *)" + g.valueExpr(in.Array) + ".alder_e, (uint64_t)" + strconv.FormatUint(length, 10) + " };\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ (void *)((AlderTy" + strconv.Itoa(int(t)) + " *)" + g.valueExpr(in.Array) + ".data)->alder_e, (uint64_t)" + strconv.FormatUint(length, 10) + " };\n")
		}

	case mir.OpSliceRangeChecked:
		g.emitSliceRange(b, in)

	case mir.OpVecNew:
		b.WriteString("  " + g.val(in.Result) + " = (AlderVec){ NULL, (uint64_t)0, (uint64_t)0 };\n")
	case mir.OpVecConstructChecked:
		b.WriteString("  if (!alder_vec_construct_checked(" + g.valueExpr(in.Slice) + ", " + g.valueExpr(in.Lo) + ", " + g.valueExpr(in.Capacity) + ", &" + g.val(in.Result) + ")) " + g.failBody(in) + "\n")
	case mir.OpVecGrowChecked:
		t, _ := g.f.ValueType(in.Slice)
		elem := g.m.Types[t].Elem
		b.WriteString("  if (" + g.valueExpr(in.Capacity) + " < " + g.valueExpr(in.Slice) + ".len) " + g.failBody(in) + "\n")
		b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
		b.WriteString("  if (!alder_u64_mul_checked(" + g.valueExpr(in.Capacity) + ", " + g.typeSize(elem) + ", &" + g.tmp(in, "") + ") || " + g.tmp(in, "") + " > (uint64_t)SIZE_MAX) " + g.failBody(in) + "\n")
		b.WriteString("  if (" + g.valueExpr(in.Slice) + ".len != (uint64_t)0 && " + g.valueExpr(in.Slice) + ".data == NULL) " + g.failBody(in) + "\n")
		b.WriteString("  void *" + g.tmp(in, "p") + " = alder_domain_alloc(" + g.valueExpr(in.Domain) + ", (size_t)" + g.tmp(in, "") + ", (size_t)" + g.typeAlign(elem) + ");\n")
		b.WriteString("  if (" + g.tmp(in, "p") + " == NULL) " + g.failBody(in) + "\n")
		b.WriteString("  uint64_t " + g.tmp(in, "n") + ";\n")
		b.WriteString("  if (!alder_u64_mul_checked(" + g.valueExpr(in.Slice) + ".len, " + g.typeSize(elem) + ", &" + g.tmp(in, "n") + ") || " + g.tmp(in, "n") + " > (uint64_t)SIZE_MAX) " + g.failBody(in) + "\n")
		if g.copyTrivial(elem) {
			b.WriteString("  if (" + g.tmp(in, "n") + " != (uint64_t)0) { memcpy(" + g.tmp(in, "p") + ", " + g.valueExpr(in.Slice) + ".data, (size_t)" + g.tmp(in, "n") + "); }\n")
		} else {
			b.WriteString("  for (uint64_t alder_i = (uint64_t)0; alder_i < " + g.valueExpr(in.Slice) + ".len; alder_i++) { ((" + g.cType(elem) + " *)" + g.tmp(in, "p") + ")[alder_i] = " + g.copyCall(elem) + "(" + g.valueExpr(in.Domain) + ", ((" + g.cType(elem) + " *)" + g.valueExpr(in.Slice) + ".data)[alder_i], 0); }\n")
		}
		b.WriteString("  " + g.val(in.Result) + " = (AlderVec){ " + g.tmp(in, "p") + ", " + g.valueExpr(in.Slice) + ".len, " + g.valueExpr(in.Capacity) + " };\n")
	case mir.OpVecLen:
		b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.Slice) + ".len;\n")
	case mir.OpVecCapacity:
		b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.Slice) + ".capacity;\n")
	case mir.OpVecStorage:
		b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ " + g.valueExpr(in.Slice) + ".data, " + g.valueExpr(in.Slice) + ".capacity };\n")
	case mir.OpVecAsSlice, mir.OpVecAsMutSlice:
		b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ " + g.valueExpr(in.Slice) + ".data, " + g.valueExpr(in.Slice) + ".len };\n")

	case mir.OpEnumPayloadChecked:
		t, _ := g.f.ValueType(in.EnumValue)
		idx, _ := g.m.VariantIndex(t, in.Variant)
		b.WriteString("  if (" + g.valueExpr(in.EnumValue) + ".alder_tag != (uint32_t)" + strconv.Itoa(idx) +
			") { " + g.failBody(in) + " }\n")
		payload, _ := g.m.VariantPayload(t, idx)
		if payload != mir.TypeUnit {
			b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.EnumValue) + ".alder_u.alder_p" +
				strconv.Itoa(idx) + ";\n")
		}

	case mir.OpEnumConstruct:
		idx, _ := g.m.VariantIndex(in.TypeOp, in.Variant)
		b.WriteString("  " + g.val(in.Result) + ".alder_tag = (uint32_t)" + strconv.Itoa(idx) + ";\n")
		payload, _ := g.m.VariantPayload(in.TypeOp, idx)
		if payload != mir.TypeUnit {
			b.WriteString("  " + g.val(in.Result) + ".alder_u.alder_p" + strconv.Itoa(idx) +
				" = " + g.valueExpr(in.Payload) + ";\n")
		}

	case mir.OpTableCreate:
		b.WriteString("  void *" + g.tmp(in, "p") + " = alder_domain_alloc(" + g.valueExpr(in.Domain) +
			", sizeof(AlderTable), _Alignof(AlderTable));\n")
		b.WriteString("  if (" + g.tmp(in, "p") + " == NULL) { alder_runtime_panic(\"table.create: out of memory\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = (AlderTable *)" + g.tmp(in, "p") + ";\n")
		b.WriteString("  *" + g.val(in.Result) + " = (AlderTable){0};\n")
		b.WriteString("  if (!alder_table_init(" + g.val(in.Result) + ", " + g.valueExpr(in.Domain) +
			", " + g.typeSize(in.TypeOp) + ", " + g.typeAlign(in.TypeOp) +
			")) { alder_runtime_panic(\"table.create failed\"); }\n")

	case mir.OpTableInsert:
		elemType, _ := g.f.ValueType(in.TableVal)
		elemAddr := "&" + g.val(in.TableVal)
		if elemType == mir.TypeUnit {
			b.WriteString("  uint8_t " + g.tmp(in, "u") + " = (uint8_t)0;\n")
			elemAddr = "&" + g.tmp(in, "u")
		}
		// A storage-bearing element is deep-copied into the table's own
		// domain first: the slot memcpy only duplicates the element struct,
		// so internal storage must already live where the table does, or it
		// would die with this function's storage domain while the table
		// outlives it.
		if elemType != mir.TypeUnit && !g.copyTrivial(elemType) {
			b.WriteString("  " + g.cType(elemType) + " " + g.tmp(in, "e") + " = " +
				g.copyCall(elemType) + "(" + g.valueExpr(in.Table) + "->domain, " +
				g.valueExpr(in.TableVal) + ", 1);\n")
			elemAddr = "&" + g.tmp(in, "e")
		}
		b.WriteString("  if (!alder_table_insert(" + g.valueExpr(in.Table) + ", " + elemAddr +
			", &" + g.val(in.Result) + ")) { alder_runtime_panic(\"table.insert failed\"); }\n")

	case mir.OpTableInsertTry:
		// table.insert.try <table>, <elem> -> result(id(elem), elem). No
		// failure edge: exhaustion or the slot-limit policy is the Err
		// payload, which carries the element value back to the caller.
		elemType, _ := g.f.ValueType(in.TableVal)
		elemAddr := "&" + g.val(in.TableVal)
		if elemType == mir.TypeUnit {
			b.WriteString("  uint8_t " + g.tmp(in, "u") + " = (uint8_t)0;\n")
			elemAddr = "&" + g.tmp(in, "u")
		}
		// Storage-bearing elements are deep-copied into the table's own
		// domain before the insert, like the panicking insert; a failed
		// insert never uses the copy, because the Err payload carries the
		// caller-owned element operand instead.
		if elemType != mir.TypeUnit && !g.copyTrivial(elemType) {
			b.WriteString("  " + g.cType(elemType) + " " + g.tmp(in, "e") + " = " +
				g.copyCall(elemType) + "(" + g.valueExpr(in.Table) + "->domain, " +
				g.valueExpr(in.TableVal) + ", 1);\n")
			elemAddr = "&" + g.tmp(in, "e")
		}
		rt, _ := g.f.ValueType(in.Result)
		okIdx, _ := g.m.VariantIndex(rt, "ok")
		errIdx, _ := g.m.VariantIndex(rt, "err")
		b.WriteString("  AlderTableId " + g.tmp(in, "id") + ";\n")
		b.WriteString("  if (alder_table_insert(" + g.valueExpr(in.Table) + ", " + elemAddr +
			", &" + g.tmp(in, "id") + ")) {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)" + strconv.Itoa(okIdx) + ";\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_u.alder_p" + strconv.Itoa(okIdx) + " = " + g.tmp(in, "id") + ";\n")
		b.WriteString("  } else {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)" + strconv.Itoa(errIdx) + ";\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_u.alder_p" + strconv.Itoa(errIdx) + " = " + g.val(in.TableVal) + ";\n")
		b.WriteString("  }\n")

	case mir.OpTableLookup, mir.OpTableLookupMut:
		t, _ := g.f.ValueType(in.Table)
		elem := g.m.Types[t].Elem
		// option(table_view(elem)): tag 0 = none, tag 1 = some(view).
		b.WriteString("  void *" + g.tmp(in, "") + ";\n")
		b.WriteString("  if (alder_table_lookup" + lookupSuffix(in.Op) + "(" + g.valueExpr(in.Table) +
			", " + g.valueExpr(in.ID) + ", &" + g.tmp(in, "") + ")) {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)1;\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_u.alder_p1 = " + g.tmp(in, "") + ";\n")
		b.WriteString("  } else {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)0;\n")
		b.WriteString("  }\n")
		_ = elem

	case mir.OpTableRemove:
		b.WriteString("  " + g.val(in.Result) + " = alder_table_remove(" + g.valueExpr(in.Table) +
			", " + g.valueExpr(in.ID) + ");\n")

	case mir.OpTableViewEnd:
		b.WriteString("  (void)" + g.valueExpr(in.View) + ";\n")

	case mir.OpIntEq, mir.OpIntNe, mir.OpIntLt, mir.OpIntLe, mir.OpIntGt, mir.OpIntGe,
		mir.OpFloatEq, mir.OpFloatNe, mir.OpFloatLt, mir.OpFloatLe, mir.OpFloatGt, mir.OpFloatGe:
		b.WriteString("  " + g.val(in.Result) + " = (bool)(" + g.valueExpr(in.A) + " " +
			cmpOp(in.Op) + " " + g.valueExpr(in.B) + ");\n")

	case mir.OpIntTrunc:
		g.emitTrunc(b, in)

	case mir.OpIntZext, mir.OpIntSext, mir.OpFloatFromInt:
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.valueExpr(in.A) + ";\n")

	case mir.OpFloatConvert:
		g.emitFloatConvert(b, in)

	case mir.OpIntFromFloat:
		g.emitFromFloat(b, in)

	case mir.OpConstGet:
		g.emitConstGet(b, in)

	case mir.OpCall:
		callee := g.m.Functions[in.Callee]
		b.WriteString("  ")
		if callee.Result != mir.TypeUnit {
			b.WriteString(g.val(in.Result) + " = ")
		}
		b.WriteString(g.fnName(in.Callee) + "(")
		g.callArgs(b, callee, in.Args)
		b.WriteString(");\n")

	case mir.OpCallValue:
		ft, ok := g.f.ValueType(in.A)
		if !ok || !g.m.ValidType(ft) || g.m.Types[ft].Kind != mir.TypeFunction {
			// Verifier rejects this; keep generation total anyway.
			b.WriteString("  /* call.value without a function type */\n")
			break
		}
		sig := g.m.Types[ft].Sig
		b.WriteString("  ")
		if sig.Result != mir.TypeUnit {
			b.WriteString(g.val(in.Result) + " = ")
		}
		b.WriteString(g.valueExpr(in.A) + ".code(")
		first := true
		for i, a := range in.Args {
			if sig.Params[i] == mir.TypeUnit {
				continue
			}
			if !first {
				b.WriteString(", ")
			}
			first = false
			b.WriteString(g.valueExpr(a))
		}
		if !first {
			b.WriteString(", ")
		}
		b.WriteString(g.valueExpr(in.A) + ".env);\n")

	case mir.OpFnValue:
		ft, ok := g.f.ValueType(in.Result)
		if !ok || !g.m.ValidType(ft) || g.m.Types[ft].Kind != mir.TypeFunction {
			b.WriteString("  /* fn.value without a function type */\n")
			break
		}
		n := strconv.Itoa(int(ft))
		marker := 0
		if in.TypeOp == mir.FnValueDomainMarker {
			marker = 1
		}
		site := [3]int{int(in.Callee), int(ft), marker}
		known := false
		for _, existing := range g.fnValues {
			if existing == site {
				known = true
				break
			}
		}
		if !known {
			g.fnValues = append(g.fnValues, site)
		}
		env := "NULL"
		if in.A != mir.NoValue {
			// The environment member is an opaque pointer; a reference-typed
			// environment value (the closure's record reference) passes its
			// data pointer.
			env = g.valueExpr(in.A)
			if t, ok := g.f.ValueType(in.A); ok && g.m.ValidType(t) {
				switch g.m.Types[t].Kind {
				case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
					env += ".data"
				}
			}
		}
		retain := "NULL"
		if agg := g.fnEnvAggregate(g.f, in.A); agg != 0 {
			retain = "alder_env_retain_ty" + strconv.Itoa(int(agg))
		} else if in.A != mir.NoValue && in.TypeOp == mir.FnValueDomainMarker {
			retain = "alder_env_retain_domain"
		}
		b.WriteString("  " + g.val(in.Result) + " = (AlderFnTy" + n + "){alder_fnwrap_" + strconv.Itoa(int(in.Callee)) + "_" + n + ", (void *)" + env + ", " + retain + "};\n")

	case mir.OpStrEq:
		ta, _ := g.f.ValueType(in.A)
		helper := "alder_string_eq"
		if g.m.ValidType(ta) && g.m.Types[ta].Kind == mir.TypeBytes {
			helper = "alder_bytes_eq"
		}
		b.WriteString("  " + g.val(in.Result) + " = " + helper + "(" + g.valueExpr(in.A) + ", " + g.valueExpr(in.B) + ");\n")

	case mir.OpStrOrderLt:
		ta, _ := g.f.ValueType(in.A)
		helper := "alder_string_lt"
		if g.m.ValidType(ta) && g.m.Types[ta].Kind == mir.TypeBytes {
			helper = "alder_bytes_lt"
		}
		b.WriteString("  " + g.val(in.Result) + " = " + helper + "(" + g.valueExpr(in.A) + ", " + g.valueExpr(in.B) + ");\n")

	case mir.OpStrDisplay:
		// The operand arrives widened to bool/i64/u64 by the lowering, so the
		// helper choice reads the operand's own MIR type. Only the integer
		// helpers allocate; a NULL data pointer routes to the checked edge.
		ta, _ := g.f.ValueType(in.A)
		helper := "alder_string_from_i64"
		if ta == mir.TypeBool {
			helper = "alder_string_from_bool"
		} else if ta == mir.TypeU64 {
			helper = "alder_string_from_u64"
		}
		s := g.tmp(in, "s")
		b.WriteString("  AlderString " + s + " = " + helper + "(" + g.valueExpr(in.Domain) + ", " + g.valueExpr(in.A) + ");\n")
		b.WriteString("  if (" + s + ".data == NULL) " + g.failBody(in) + "\n")
		b.WriteString("  " + g.val(in.Result) + " = " + s + ";\n")

	case mir.OpStrLen:
		b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.A) + ".len;\n")

	case mir.OpStrByteChecked:
		b.WriteString("  if (" + g.valueExpr(in.B) + " >= " + g.valueExpr(in.A) + ".len) { " + g.failBody(in) + " }\n")
		b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.A) + ".data[" + g.valueExpr(in.B) + "];\n")

	case mir.OpStrConcat, mir.OpStrSliceChecked, mir.OpStrFromBytes:
		g.emitStrOwned(b, in)

	case mir.OpStrToBytes:
		b.WriteString("  " + g.val(in.Result) + " = (AlderBytes){ " + g.valueExpr(in.A) + ".data, " + g.valueExpr(in.A) + ".len };\n")

	case mir.OpIntConvertChecked:
		g.emitIntConvertChecked(b, in)

	case mir.OpIntConvertWrap:
		g.emitTrunc(b, in)

	case mir.OpCNumTry, mir.OpCNumWrap, mir.OpCNumCast:
		g.emitCNumConvert(b, in)

	case mir.OpFFICallUnsafe:
		imp := &g.m.Imports[in.FFIImport]
		b.WriteString("  ")
		if imp.Sig.Result != mir.TypeUnit {
			b.WriteString(g.val(in.Result) + " = ")
		}
		b.WriteString("(" + imp.Name + ")(")
		first := true
		for i, a := range in.Args {
			if imp.Sig.Params[i] == mir.TypeUnit {
				continue
			}
			if !first {
				b.WriteString(", ")
			}
			first = false
			b.WriteString(g.valueExpr(a))
		}
		b.WriteString(");\n")

	case mir.OpCBindingCall:
		_, fn, ok := g.m.BindingFuncAt(in.CBinding)
		if !ok {
			b.WriteString("  /* unreachable binding call */\n")
			break
		}
		b.WriteString("  ")
		if fn.Sig.Result != mir.TypeUnit {
			b.WriteString(g.val(in.Result) + " = ")
		}
		b.WriteString("(" + fn.CName + ")(")
		first := true
		for i, a := range in.Args {
			if fn.Sig.Params[i] == mir.TypeUnit {
				continue
			}
			if !first {
				b.WriteString(", ")
			}
			first = false
			b.WriteString(g.valueExpr(a))
		}
		b.WriteString(");\n")

	case mir.OpCIsNull:
		b.WriteString("  " + g.val(in.Result) + " = (bool)((" + g.valueExpr(in.A) + ") == (void *)0);\n")

	case mir.OpCBufferPtr:
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.valueExpr(in.A) + ".data;\n")
		b.WriteString("  if (" + g.val(in.Result) + " == NULL) { " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")alder_c_buffer_dummy; }\n")

	case mir.OpCStringMakeLit, mir.OpCStringMake, mir.OpCStringPtr, mir.OpCStringRelease:
		g.emitCStringOp(b, in)

	case mir.OpCFieldGet, mir.OpCFieldSet:
		g.emitCFieldAccess(b, in)
	}
}

func lookupSuffix(op mir.OpKind) string {
	if op == mir.OpTableLookupMut {
		return "_mut"
	}
	return ""
}

func (g *gen) aggregateFieldIndex(t mir.TypeId, name string) (int, bool) {
	if !g.m.ValidType(t) || g.m.Types[t].Kind != mir.TypeAggregate {
		return 0, false
	}
	for i, field := range g.m.Types[t].Fields {
		if field.Name == name {
			return i, true
		}
	}
	return 0, false
}

func instrIndexOf(blk *mir.Block, want *mir.Instr) int {
	for i := range blk.Instrs {
		if &blk.Instrs[i] == want {
			return i
		}
	}
	return -1
}

func cmpOp(op mir.OpKind) string {
	switch op {
	case mir.OpIntEq, mir.OpFloatEq:
		return "=="
	case mir.OpIntNe, mir.OpFloatNe:
		return "!="
	case mir.OpIntLt, mir.OpFloatLt:
		return "<"
	case mir.OpIntLe, mir.OpFloatLe:
		return "<="
	case mir.OpIntGt, mir.OpFloatGt:
		return ">"
	case mir.OpIntGe, mir.OpFloatGe:
		return ">="
	}
	return "?"
}

// callArgs writes the argument expressions of a call, skipping unit
// parameters.
func (g *gen) callArgs(b *strings.Builder, callee *mir.Function, args []mir.ValueId) {
	first := true
	for i, a := range args {
		if callee.Params[i].Type == mir.TypeUnit {
			continue
		}
		if !first {
			b.WriteString(", ")
		}
		first = false
		b.WriteString(g.valueExpr(a))
	}
}

// intWidth returns the width and signedness of an integer type.
func intInfo(t mir.TypeId) (width int, signed bool) {
	switch t {
	case mir.TypeI8:
		return 8, true
	case mir.TypeI16:
		return 16, true
	case mir.TypeI32:
		return 32, true
	case mir.TypeI64:
		return 64, true
	case mir.TypeU8:
		return 8, false
	case mir.TypeU16:
		return 16, false
	case mir.TypeU32:
		return 32, false
	case mir.TypeU64:
		return 64, false
	}
	return 0, false
}

// emitIntChecked lowers a checked integer operation. 64-bit operations call
// the runtime helper; narrower operations promote to 64 bits, compute with
// the helper, and range-check the result. Narrow shifts check the count
// against the source width and compute at that width.
func (g *gen) emitIntChecked(b *strings.Builder, in *mir.Instr) {
	t, _ := g.f.ValueType(in.A)
	width, signed := intInfo(t)
	op := in.Op
	if op == mir.OpIntShlChecked || op == mir.OpIntShrChecked {
		g.emitShiftChecked(b, in, width, signed)
		return
	}
	helper := "alder_u64_"
	opName := ""
	switch op {
	case mir.OpIntAddChecked:
		opName = "add_checked"
	case mir.OpIntSubChecked:
		opName = "sub_checked"
	case mir.OpIntMulChecked:
		opName = "mul_checked"
	case mir.OpIntDivChecked:
		opName = "div_checked"
	}
	if signed {
		helper = "alder_i64_"
	}
	// 64-bit operations call the runtime helper directly.
	if width == 64 {
		b.WriteString("  if (!" + helper + opName + "(" + g.valueExpr(in.A) + ", " + g.valueExpr(in.B) +
			", &" + g.val(in.Result) + ")) { " + g.failBody(in) + " }\n")
		return
	}
	// Narrow: promote to 64 bits, compute with the helper, and range-check.
	srcCast := g.cType(t)
	b.WriteString("  " + signed64Name(signed) + " " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!" + helper + opName + "((" + srcCast + ")" + g.valueExpr(in.A) + ", (" +
		srcCast + ")" + g.valueExpr(in.B) + ", &" + g.tmp(in, "") + ")) { " + g.failBody(in) + " }\n")
	if signed {
		limits, limitu := intLimits(width)
		b.WriteString("  if (" + g.tmp(in, "") + " < (int64_t)" + limits + " || " +
			g.tmp(in, "") + " > (int64_t)" + limitu + ") { " + g.failBody(in) + " }\n")
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(t) + ")" + g.tmp(in, "") + ";\n")
	} else {
		limit := uintLimit(width)
		b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)" + limit + ") { " + g.failBody(in) + " }\n")
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(t) + ")" + g.tmp(in, "") + ";\n")
	}
}

// emitFloatBinary lowers the plain IEEE-754 float arithmetic. Division goes
// through the runtime helper so a zero divisor yields the IEEE signed
// infinity or NaN result instead of the undefined plain C11 division; the
// other operations emit plain C arithmetic under the translation unit's
// FP_CONTRACT OFF pragma.
func (g *gen) emitFloatBinary(b *strings.Builder, in *mir.Instr) {
	if in.Op == mir.OpFloatDiv {
		helper := "alder_f32_div"
		if t, ok := g.f.ValueType(in.A); ok && t == mir.TypeF64 {
			helper = "alder_f64_div"
		}
		b.WriteString("  " + g.val(in.Result) + " = " + helper + "(" +
			g.valueExpr(in.A) + ", " + g.valueExpr(in.B) + ");\n")
		return
	}
	arith := "+"
	switch in.Op {
	case mir.OpFloatSub:
		arith = "-"
	case mir.OpFloatMul:
		arith = "*"
	}
	b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.A) + " " + arith + " " + g.valueExpr(in.B) + ";\n")
}

// emitIntBitwise lowers the total bitwise operations over the fixed-width
// two's-complement representation. The C operators are applied to the
// unsigned type of the operand width, which is fully defined for every bit
// pattern; a signed result then receives that bit pattern by memcpy so no
// implementation-defined signed conversion is involved.
func (g *gen) emitIntBitwise(b *strings.Builder, in *mir.Instr) {
	t, _ := g.f.ValueType(in.A)
	width, signed := intInfo(t)
	u := "uint" + strconv.Itoa(width) + "_t"
	not := in.Op == mir.OpIntNot
	opName := "&"
	if not {
		opName = "~"
	} else {
		switch in.Op {
		case mir.OpIntOr:
			opName = "|"
		case mir.OpIntXor:
			opName = "^"
		}
	}
	expr := ""
	if not {
		expr = opName + "(" + u + ")" + g.valueExpr(in.A)
	} else {
		expr = "(" + u + ")" + g.valueExpr(in.A) + " " + opName + " (" + u + ")" + g.valueExpr(in.B)
	}
	if signed {
		tmp := g.tmp(in, "u")
		// The narrow C operators promote to int; cast the promoted result back
		// to the width type so the initializer is not an implicit narrowing
		// conversion under clang's -Wimplicit-int-conversion.
		b.WriteString("  " + u + " " + tmp + " = (" + u + ")(" + expr + ");\n")
		b.WriteString("  memcpy(&" + g.val(in.Result) + ", &" + tmp + ", sizeof(" + tmp + "));\n")
		return
	}
	b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(t) + ")(" + expr + ");\n")
}

// emitIntMode lowers the non-terminating integer arithmetic: the try forms
// build an option (none on overflow), the saturating forms clamp at the type
// bounds, and the wrapping forms wrap modulo 2^width. All of them compute in
// 64 bits with the runtime helpers, so signed arithmetic stays defined; narrow
// widths then clamp or truncate against their own bounds, which matches
// saturating or wrapping at that width exactly: saturating at 64 bits keeps
// the value on the same side of the narrow bound, and truncation keeps the
// low bits the width-w wrap produces.
func (g *gen) emitIntMode(b *strings.Builder, in *mir.Instr) {
	t, _ := g.f.ValueType(in.A)
	width, signed := intInfo(t)
	helper := "alder_u64_"
	opName := ""
	tryForm := false
	switch in.Op {
	case mir.OpIntAddTry:
		opName, tryForm = "add_checked", true
	case mir.OpIntSubTry:
		opName, tryForm = "sub_checked", true
	case mir.OpIntMulTry:
		opName, tryForm = "mul_checked", true
	case mir.OpIntAddSaturating:
		opName = "add_saturating"
	case mir.OpIntSubSaturating:
		opName = "sub_saturating"
	case mir.OpIntMulSaturating:
		opName = "mul_saturating"
	case mir.OpIntAddWrapping:
		opName = "add_wrapping"
	case mir.OpIntSubWrapping:
		opName = "sub_wrapping"
	case mir.OpIntMulWrapping:
		opName = "mul_wrapping"
	}
	if signed {
		helper = "alder_i64_"
	}
	srcCast := g.cType(t)
	a := g.valueExpr(in.A)
	bArg := g.valueExpr(in.B)
	narrowA := "(" + srcCast + ")" + a
	narrowB := "(" + srcCast + ")" + bArg
	if width == 64 {
		if tryForm {
			// option(T): none is tag 0 with no payload, some is tag 1
			// carrying the payload; the failed helper leaves the payload
			// slot untouched, which none never reads.
			b.WriteString("  " + g.val(in.Result) + ".alder_tag = (uint32_t)(" + helper + opName +
				"(" + a + ", " + bArg + ", &" + g.val(in.Result) + ".alder_u.alder_p1) ? 1u : 0u);\n")
			return
		}
		b.WriteString("  " + g.val(in.Result) + " = " + helper + opName + "(" + a + ", " + bArg + ");\n")
		return
	}
	// Narrow: compute in 64 bits, then clamp or truncate at the width.
	tmp := g.tmp(in, "")
	if tryForm {
		// Narrow try: the widened operands cannot overflow 64 bits, so
		// plain 64-bit arithmetic needs no checked helper; the width
		// check below alone decides none versus some. Each operand is
		// widened to 64 bits BEFORE the arithmetic: a narrow cast alone
		// would let C compute the operation in the operands' promoted
		// 32-bit int width, where i32 signed subtraction overflows
		// (undefined) and u32 wraparound silently corrupts the value.
		wide := "int64_t"
		if !signed {
			wide = "uint64_t"
		}
		op := "+"
		switch in.Op {
		case mir.OpIntSubTry:
			op = "-"
		case mir.OpIntMulTry:
			op = "*"
		}
		b.WriteString("  " + signed64Name(signed) + " " + tmp + " = " + wide + "((" + srcCast + ")" + a + ") " + op +
			" " + wide + "((" + srcCast + ")" + bArg + ");\n")
	} else {
		b.WriteString("  " + signed64Name(signed) + " " + tmp + " = " + helper + opName +
			"(" + narrowA + ", " + narrowB + ");\n")
	}
	if tryForm {
		overflow := tmp + " > (uint64_t)" + uintLimit(width)
		if signed {
			lo, hi := intLimits(width)
			overflow = tmp + " < (int64_t)" + lo + " || " + tmp + " > (int64_t)" + hi
		}
		b.WriteString("  if (" + overflow + ") {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)0;\n")
		b.WriteString("  } else {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)1;\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_u.alder_p1 = (" + g.cType(t) + ")" + tmp + ";\n")
		b.WriteString("  }\n")
		return
	}
	if in.Op == mir.OpIntAddSaturating || in.Op == mir.OpIntSubSaturating || in.Op == mir.OpIntMulSaturating {
		clamp := tmp + " > (uint64_t)" + uintLimit(width)
		clampValue := uintLimit(width)
		if signed {
			lo, hi := intLimits(width)
			b.WriteString("  if (" + tmp + " > (int64_t)" + hi + ") {\n")
			b.WriteString("    " + g.val(in.Result) + " = (" + g.cType(t) + ")" + hi + ";\n")
			b.WriteString("  } else if (" + tmp + " < (int64_t)" + lo + ") {\n")
			b.WriteString("    " + g.val(in.Result) + " = (" + g.cType(t) + ")" + lo + ";\n")
			b.WriteString("  } else {\n")
			b.WriteString("    " + g.val(in.Result) + " = (" + g.cType(t) + ")" + tmp + ";\n")
			b.WriteString("  }\n")
			return
		}
		b.WriteString("  if (" + clamp + ") {\n")
		b.WriteString("    " + g.val(in.Result) + " = (" + g.cType(t) + ")" + clampValue + ";\n")
		b.WriteString("  } else {\n")
		b.WriteString("    " + g.val(in.Result) + " = (" + g.cType(t) + ")" + tmp + ";\n")
		b.WriteString("  }\n")
		return
	}
	// Wrapping: truncating the 64-bit wrap result to the narrow type keeps
	// exactly the low bits the width-w wrap produces.
	b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(t) + ")" + tmp + ";\n")
}

// emitStrOwned lowers the byte-sequence operations that build domain-owned
// storage: str.concat, str.slice.checked, and str.from_bytes. All three fail
// to the checked edge when the bytes cannot be produced: allocation failure
// for concat and the slice, invalid UTF-8 or allocation failure for
// from_bytes. The result is always a fresh AlderString or AlderBytes whose
// data pointer is non-NULL, so later reads and copies never test it.
func (g *gen) emitStrOwned(b *strings.Builder, in *mir.Instr) {
	fail := g.failBody(in)
	a := g.valueExpr(in.A)
	p := g.tmp(in, "p")
	switch in.Op {
	case mir.OpStrConcat:
		result := "AlderString"
		if t, ok := g.f.ValueType(in.Result); ok && g.m.ValidType(t) && g.m.Types[t].Kind == mir.TypeBytes {
			result = "AlderBytes"
		}
		n := g.tmp(in, "n")
		bArg := g.valueExpr(in.B)
		b.WriteString("  uint64_t " + n + ";\n")
		b.WriteString("  if (!alder_u64_add_checked(" + a + ".len, " + bArg + ".len, &" + n + ") || " + n + " > (uint64_t)SIZE_MAX) " + fail + "\n")
		b.WriteString("  void *" + p + " = alder_domain_alloc(" + g.valueExpr(in.Domain) + ", (size_t)" + n + ", (size_t)1);\n")
		b.WriteString("  if (" + p + " == NULL) " + fail + "\n")
		b.WriteString("  if (" + a + ".len != (uint64_t)0) { memcpy(" + p + ", " + a + ".data, (size_t)" + a + ".len); }\n")
		b.WriteString("  if (" + bArg + ".len != (uint64_t)0) { memcpy((uint8_t *)" + p + " + " + a + ".len, " + bArg + ".data, (size_t)" + bArg + ".len); }\n")
		b.WriteString("  " + g.val(in.Result) + " = (" + result + "){ (const uint8_t *)" + p + ", " + n + " };\n")
	case mir.OpStrSliceChecked:
		lo := g.valueExpr(in.Lo)
		hi := g.valueExpr(in.Hi)
		result, _ := g.f.ValueType(in.A)
		n := g.tmp(in, "n")
		b.WriteString("  uint64_t " + n + ";\n")
		b.WriteString("  if (" + lo + " > " + hi + " || " + hi + " > " + a + ".len) " + fail + "\n")
		b.WriteString("  " + n + " = " + hi + " - " + lo + ";\n")
		b.WriteString("  void *" + p + " = alder_domain_alloc(" + g.valueExpr(in.Domain) + ", (size_t)" + n + ", (size_t)1);\n")
		b.WriteString("  if (" + p + " == NULL) " + fail + "\n")
		b.WriteString("  if (" + n + " != (uint64_t)0) { memcpy(" + p + ", " + a + ".data + " + lo + ", (size_t)" + n + "); }\n")
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(result) + "){ (const uint8_t *)" + p + ", " + n + " };\n")
	default: // mir.OpStrFromBytes
		// The result value is option(string): none on invalid UTF-8, some
		// carrying the fresh string otherwise. Only allocation failure
		// takes the instruction's failure edge.
		b.WriteString("  if (!alder_string_utf8_valid(" + a + ".data, " + a + ".len)) {\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)0;\n")
		b.WriteString("  } else {\n")
		b.WriteString("    void *" + p + " = alder_domain_alloc(" + g.valueExpr(in.Domain) + ", (size_t)" + a + ".len, (size_t)1);\n")
		b.WriteString("    if (" + p + " == NULL) " + fail + "\n")
		b.WriteString("    if (" + a + ".len != (uint64_t)0) { memcpy(" + p + ", " + a + ".data, (size_t)" + a + ".len); }\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_u.alder_p1 = (AlderString){ (const uint8_t *)" + p + ", " + a + ".len };\n")
		b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)1;\n")
		b.WriteString("  }\n")
	}
}

// emitShiftChecked lowers int.shl.checked and int.shr.checked.
func (g *gen) emitShiftChecked(b *strings.Builder, in *mir.Instr, width int, signed bool) {
	fail := g.failBody(in)
	shl := in.Op == mir.OpIntShlChecked
	if width == 64 {
		helper := "alder_u64_sh"
		if signed {
			helper = "alder_i64_sh"
		}
		if shl {
			helper += "l_checked"
		} else {
			helper += "r_checked"
		}
		b.WriteString("  if (!" + helper + "(" + g.valueExpr(in.A) + ", " + g.valueExpr(in.B) +
			", &" + g.val(in.Result) + ")) { " + fail + " }\n")
		return
	}
	// Narrow: check the count against the source width, then compute at that
	// width. Unsigned targets wrap by casting; signed targets transfer the
	// two's-complement bit pattern with memcpy.
	if signed {
		b.WriteString("  if (" + g.valueExpr(in.B) + " < 0 || " + g.valueExpr(in.B) + " >= " +
			strconv.Itoa(width) + ") { " + fail + " }\n")
	} else {
		b.WriteString("  if (" + g.valueExpr(in.B) + " >= " + strconv.Itoa(width) + ") { " + fail + " }\n")
	}
	u := "uint" + strconv.Itoa(width) + "_t"
	if !signed {
		if shl {
			b.WriteString("  " + g.val(in.Result) + " = (" + u + ")(((uint64_t)(" + u + ")" +
				g.valueExpr(in.A) + ") << (unsigned)" + g.valueExpr(in.B) + ");\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = (" + u + ")((uint64_t)(" + u + ")" +
				g.valueExpr(in.A) + " >> (unsigned)" + g.valueExpr(in.B) + ");\n")
		}
		return
	}
	if shl {
		b.WriteString("  " + u + " " + g.tmp(in, "") + " = (" + u + ")(((uint64_t)(" + u + ")" +
			g.valueExpr(in.A) + ") << (unsigned)" + g.valueExpr(in.B) + ");\n")
		b.WriteString("  memcpy(&" + g.val(in.Result) + ", &" + g.tmp(in, "") + ", sizeof(" + g.tmp(in, "") + "));\n")
	} else {
		b.WriteString("  uint64_t " + g.tmp(in, "") + " = (uint64_t)(" + u + ")" +
			g.valueExpr(in.A) + " >> (unsigned)" + g.valueExpr(in.B) + ";\n")
		b.WriteString("  if (" + g.valueExpr(in.A) + " < 0 && " + g.valueExpr(in.B) + " > 0) {\n")
		b.WriteString("    " + g.tmp(in, "") + " |= (UINT64_MAX << (unsigned)(" + strconv.Itoa(width) +
			" - " + g.valueExpr(in.B) + ")) & (uint64_t)" + uintLimit(width) + ";\n")
		b.WriteString("  }\n")
		b.WriteString("  " + u + " " + g.tmp(in, "u") + " = (" + u + ")" + g.tmp(in, "") + ";\n")
		b.WriteString("  memcpy(&" + g.val(in.Result) + ", &" + g.tmp(in, "u") + ", sizeof(" + g.tmp(in, "u") + "));\n")
	}
}

// signed64Name returns the promoted 64-bit temporary type of an integer.
func signed64Name(signed bool) string {
	if signed {
		return "int64_t"
	}
	return "uint64_t"
}

// intLimits returns the stdint limit names for a signed narrow width.
func intLimits(width int) (string, string) {
	switch width {
	case 8:
		return "INT8_MIN", "INT8_MAX"
	case 16:
		return "INT16_MIN", "INT16_MAX"
	case 32:
		return "INT32_MIN", "INT32_MAX"
	}
	return "INT64_MIN", "INT64_MAX"
}

// uintLimit returns the stdint limit name for an unsigned narrow width.
func uintLimit(width int) string {
	switch width {
	case 8:
		return "UINT8_MAX"
	case 16:
		return "UINT16_MAX"
	case 32:
		return "UINT32_MAX"
	}
	return "UINT64_MAX"
}

func typeOfOperand(f *mir.Function, v mir.ValueId) mir.TypeId {
	t, _ := f.ValueType(v)
	return t
}

// emitSliceIndex lowers slice.index.checked to a bounds check, a checked
// byte offset, and a one-element slice.
func (g *gen) emitSliceIndex(b *strings.Builder, in *mir.Instr) {
	elem := g.sliceElemType(in.Slice)
	fail := g.failBody(in)
	b.WriteString("  if (!alder_slice_index_checked(" + g.valueExpr(in.Slice) + ", " + g.valueExpr(in.Index) +
		")) { " + fail + " }\n")
	b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!alder_u64_mul_checked(" + g.valueExpr(in.Index) + ", " + g.typeSize(elem) +
		", &" + g.tmp(in, "") + ")) { " + fail + " }\n")
	b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)SIZE_MAX) { " + fail + " }\n")
	b.WriteString("  void *" + g.tmp(in, "p") + " = " + g.valueExpr(in.Slice) + ".data;\n")
	b.WriteString("  if (" + g.tmp(in, "") + " != (uint64_t)0) {\n")
	b.WriteString("    " + g.tmp(in, "p") + " = (void *)((uint8_t *)" + g.tmp(in, "p") +
		" + (size_t)" + g.tmp(in, "") + ");\n")
	b.WriteString("  }\n")
	b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ " + g.tmp(in, "p") + ", (uint64_t)1 };\n")
}

// emitSliceRange lowers slice.range.checked to a bounds check and a
// sub-slice with a checked byte offset.
func (g *gen) emitSliceRange(b *strings.Builder, in *mir.Instr) {
	elem := g.sliceElemType(in.Slice)
	fail := g.failBody(in)
	b.WriteString("  if (!alder_slice_range_checked(" + g.valueExpr(in.Slice) + ", " + g.valueExpr(in.Lo) +
		", " + g.valueExpr(in.Hi) + ")) { " + fail + " }\n")
	b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!alder_u64_mul_checked(" + g.valueExpr(in.Lo) + ", " + g.typeSize(elem) +
		", &" + g.tmp(in, "") + ")) { " + fail + " }\n")
	b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)SIZE_MAX) { " + fail + " }\n")
	b.WriteString("  void *" + g.tmp(in, "p") + " = " + g.valueExpr(in.Slice) + ".data;\n")
	b.WriteString("  if (" + g.tmp(in, "") + " != (uint64_t)0) {\n")
	b.WriteString("    " + g.tmp(in, "p") + " = (void *)((uint8_t *)" + g.tmp(in, "p") +
		" + (size_t)" + g.tmp(in, "") + ");\n")
	b.WriteString("  }\n")
	b.WriteString("  " + g.val(in.Result) + " = (AlderSlice){ " + g.tmp(in, "p") + ", (uint64_t)(" +
		g.valueExpr(in.Hi) + " - " + g.valueExpr(in.Lo) + ") };\n")
}

// sliceElemType returns the element type of a slice-like operand.
func (g *gen) sliceElemType(v mir.ValueId) mir.TypeId {
	t, ok := g.f.ValueType(v)
	if !ok || !g.m.ValidType(t) {
		return mir.TypeU8
	}
	return g.m.Types[t].Elem
}

// emitTrunc lowers int.trunc: unsigned targets wrap by casting; signed
// targets transfer the two's-complement bit pattern with memcpy.
func (g *gen) emitTrunc(b *strings.Builder, in *mir.Instr) {
	_, signed := intInfo(in.TypeOp)
	u := "uint" + strconv.Itoa(intWidthOf(in.TypeOp)) + "_t"
	if !signed {
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.valueExpr(in.A) + ";\n")
		return
	}
	b.WriteString("  " + u + " " + g.tmp(in, "") + " = (" + u + ")" + g.valueExpr(in.A) + ";\n")
	b.WriteString("  memcpy(&" + g.val(in.Result) + ", &" + g.tmp(in, "") + ", sizeof(" + g.tmp(in, "") + "));\n")
}

func intWidthOf(t mir.TypeId) int {
	w, _ := intInfo(t)
	return w
}

// emitIntConvertChecked lowers int.convert.checked. The value is widened to
// 64 bits with its own signedness (always defined), range-checked against
// the target bounds, and the option payload is filled only in range: the
// payload cast then preserves the value. A signed target compares against
// its signed limits; a signed source into an unsigned target also rejects
// negatives, with the negative-to-unsigned comparison done after an explicit
// uint64_t cast, whose conversion is defined modulo. For u64 into i64 the
// limit comparison itself stays in uint64_t so no limit is narrowed.
func (g *gen) emitIntConvertChecked(b *strings.Builder, in *mir.Instr) {
	src, _ := g.f.ValueType(in.A)
	_, srcSigned := intInfo(src)
	tWidth, tSigned := intInfo(in.TypeOp)
	tmp := g.tmp(in, "c")
	b.WriteString("  " + signed64Name(srcSigned) + " " + tmp + " = (" + signed64Name(srcSigned) + ")" + g.valueExpr(in.A) + ";\n")
	var cond string
	if tSigned {
		minName, maxName := intLimits(tWidth)
		if srcSigned {
			cond = tmp + " < (int64_t)" + minName + " || " + tmp + " > (int64_t)" + maxName
		} else {
			cond = tmp + " > (uint64_t)" + maxName
		}
	} else {
		if srcSigned {
			cond = tmp + " < 0 || (uint64_t)" + tmp + " > (uint64_t)" + uintLimit(tWidth)
		} else {
			cond = tmp + " > (uint64_t)" + uintLimit(tWidth)
		}
	}
	b.WriteString("  if (" + cond + ") {\n")
	b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)0;\n")
	b.WriteString("  } else {\n")
	b.WriteString("    " + g.val(in.Result) + ".alder_u.alder_p1 = (" + g.cType(in.TypeOp) + ")" + tmp + ";\n")
	b.WriteString("    " + g.val(in.Result) + ".alder_tag = (uint32_t)1;\n")
	b.WriteString("  }\n")
}

// cConvScalarID maps a conversion endpoint to its c scalar id, 15 for an
// Alder primitive or another kind. The id order matches CScalar: 0 char,
// 1 signed char, 2 unsigned char, 3 short, 4 unsigned short, 5 int,
// 6 unsigned int, 7 long, 8 unsigned long, 9 long long, 10 unsigned
// long long, 11 float, 12 double, 13 size_t, 14 ptrdiff_t.
func cConvScalarID(m *mir.Module, t mir.TypeId) uint64 {
	if m.ValidType(t) && m.Types[t].Kind == mir.TypeCRaw {
		return m.Types[t].Length
	}
	return 15
}

// cConvAlderTarget returns the Alder primitive target of a conversion
// endpoint: 2..11 for the integer and float primitives (I8..U64, then F32,
// F64), 0 for anything else. The decode mirrors the checker's alder_index
// encoding (target - 2).
func cConvAlderTarget(t mir.TypeId) uint64 {
	if t >= mir.TypeI8 && t <= mir.TypeI64 {
		return uint64(t) - uint64(mir.TypeI8) + 2
	}
	if t >= mir.TypeU8 && t <= mir.TypeU64 {
		return uint64(t) - uint64(mir.TypeU8) + 6
	}
	if t == mir.TypeF32 {
		return 10
	}
	if t == mir.TypeF64 {
		return 11
	}
	return 0
}

// cConvIntWidth returns the bit width of one conversion endpoint's integer
// side, 0 when the endpoint is not an integer. c.Char counts as 8 bits: its
// signedness is what stays unknown, never its width.
func cConvIntWidth(m *mir.Module, t mir.TypeId) int {
	if mir.IsIntType(t) {
		w, _ := intInfo(t)
		return w
	}
	switch cConvScalarID(m, t) {
	case 0, 1, 2:
		return 8
	case 3, 4:
		return 16
	case 5, 6:
		return 32
	case 7, 8, 9, 10, 13, 14:
		return 64
	}
	return 0
}

// cConvSigned reports whether one conversion endpoint's integer side is
// signed. c.Char returns false: its signedness is target-dependent, and the
// callers that need to know test for it separately.
func cConvSigned(m *mir.Module, t mir.TypeId) bool {
	if mir.IsIntType(t) {
		_, signed := intInfo(t)
		return signed
	}
	switch cConvScalarID(m, t) {
	case 1, 3, 5, 7, 9, 14:
		return true
	}
	return false
}

// cConvU64Wide reports whether one conversion endpoint's integer side must
// widen into uint64_t: exactly the 64-bit unsigned scalars, whose values do
// not fit int64_t.
func cConvU64Wide(m *mir.Module, t mir.TypeId) bool {
	if t == mir.TypeU64 {
		return true
	}
	switch cConvScalarID(m, t) {
	case 8, 10, 13:
		return true
	}
	return false
}

// cConvFloatClass returns the IEEE class of a conversion endpoint: 1 single,
// 2 double, 0 not a float.
func cConvFloatClass(m *mir.Module, t mir.TypeId) int {
	switch t {
	case mir.TypeF32:
		return 1
	case mir.TypeF64:
		return 2
	}
	switch cConvScalarID(m, t) {
	case 11:
		return 1
	case 12:
		return 2
	}
	return 0
}

// cConvIntTotal reports whether the conversion is lossless on every target
// Alder supports, so the checked form is statically always some. Mirrors the
// checker's c_convert_total: same-sign needs a target at least as wide,
// unsigned into signed needs a strictly wider target, signed into unsigned
// is never total. c.Char's target-dependent signedness keeps the runtime
// check even where both platforms happen to be lossless: only the strictly
// wider signed targets are total either way.
func cConvIntTotal(m *mir.Module, src, dst mir.TypeId) bool {
	srcC := cConvScalarID(m, src)
	dstC := cConvScalarID(m, dst)
	if srcC == 0 {
		if dstC != 15 {
			return false
		}
		at := cConvAlderTarget(dst)
		return at == 3 || at == 4 || at == 5
	}
	if dstC == 0 {
		return false
	}
	srcWidth := cConvIntWidth(m, src)
	dstWidth := cConvIntWidth(m, dst)
	if srcWidth == 0 || dstWidth == 0 {
		return false
	}
	srcSigned := cConvSigned(m, src)
	dstSigned := cConvSigned(m, dst)
	if srcSigned == dstSigned {
		return dstWidth >= srcWidth
	}
	if !srcSigned && dstSigned {
		return dstWidth > srcWidth
	}
	return false
}

// cConvLimit returns the C spelling of one conversion endpoint's limit
// macro: the c raw scalars use their own macros (CHAR for the
// target-dependent char, SIZE and PTRDIFF for the 64-bit typedefs); Alder
// integer targets use the fixed-width macros. The caller applies any
// widening cast.
func cConvLimit(m *mir.Module, dst mir.TypeId, minimum bool) string {
	switch cConvScalarID(m, dst) {
	case 0:
		if minimum {
			return "CHAR_MIN"
		}
		return "CHAR_MAX"
	case 1:
		if minimum {
			return "INT8_MIN"
		}
		return "INT8_MAX"
	case 2:
		return "UINT8_MAX"
	case 3:
		if minimum {
			return "INT16_MIN"
		}
		return "INT16_MAX"
	case 4:
		return "UINT16_MAX"
	case 5:
		if minimum {
			return "INT32_MIN"
		}
		return "INT32_MAX"
	case 6:
		return "UINT32_MAX"
	case 7:
		if minimum {
			return "LONG_MIN"
		}
		return "LONG_MAX"
	case 8:
		return "ULONG_MAX"
	case 9:
		if minimum {
			return "LLONG_MIN"
		}
		return "LLONG_MAX"
	case 10:
		return "ULLONG_MAX"
	case 13:
		return "SIZE_MAX"
	case 14:
		if minimum {
			return "PTRDIFF_MIN"
		}
		return "PTRDIFF_MAX"
	}
	width, signed := intInfo(dst)
	if signed {
		min, max := intLimits(width)
		if minimum {
			return min
		}
		return max
	}
	return uintLimit(width)
}

// cConvCompare renders the in-range condition of a checked integer C
// conversion. tmp holds the source widened to 64 bits with its own
// signedness. A uint64_t tmp compares against the target maximum alone;
// signed targets compare minimum and maximum in int64_t, so no negative
// value wraps before the maximum check; unsigned targets reject negatives
// first and then compare the maximum in uint64_t. The statically always-true
// shapes never reach here because cConvIntTotal handles those pairs without
// a comparison, and the unsigned 64-bit maximum needs no comparison at all.
func (g *gen) cConvCompare(src, dst mir.TypeId, tmp string) string {
	if cConvU64Wide(g.m, src) {
		return "(uint64_t)" + tmp + " <= (uint64_t)" + cConvLimit(g.m, dst, false)
	}
	srcChar := cConvScalarID(g.m, src) == 0
	srcMayNeg := cConvSigned(g.m, src) || srcChar
	if cConvSigned(g.m, dst) {
		if srcMayNeg {
			return tmp + " >= (int64_t)" + cConvLimit(g.m, dst, true) + " && (int64_t)" + tmp +
				" <= (int64_t)" + cConvLimit(g.m, dst, false)
		}
		return "(int64_t)" + tmp + " <= (int64_t)" + cConvLimit(g.m, dst, false)
	}
	if srcMayNeg {
		return tmp + " >= 0 && (uint64_t)" + tmp + " <= (uint64_t)" + cConvLimit(g.m, dst, false)
	}
	return "(uint64_t)" + tmp + " <= (uint64_t)" + cConvLimit(g.m, dst, false)
}

// emitCFieldAccess lowers the C-boundary record field operations. The
// record operand renders as its declared C spelling, so the access is an
// ordinary C member read or write through the verified binding's field
// spelling.
func (g *gen) emitCFieldAccess(b *strings.Builder, in *mir.Instr) {
	if in.Op == mir.OpCFieldSet {
		// The write form targets a place holding the record: an ordinary
		// C member assignment through the verified binding's field
		// spelling.
		field, ok := g.cFieldAtPlace(&in.Place, in.CField)
		if !ok {
			b.WriteString("  /* unreachable c.field.set */\n")
			return
		}
		b.WriteString("  " + g.place(&in.Place) + "." + field.CName + " = " + g.valueExpr(in.A) + ";\n")
		return
	}
	_, field, ok := g.m.CNamedRecordField(g.f, in.A, in.CField)
	if !ok {
		b.WriteString("  /* unreachable c.field */\n")
		return
	}
	b.WriteString("  " + g.val(in.Result) + " = " + g.valueExpr(in.A) + "." + field.CName + ";\n")
}

// cFieldAtPlace resolves the field declaration of the record type a place
// holds, for the write form.
func (g *gen) cFieldAtPlace(p *mir.Place, name string) (mir.Field, bool) {
	t, ok := g.m.PlaceType(g.f, p)
	if !ok || !g.m.ValidType(t) || g.m.Types[t].Kind != mir.TypeCNamed || g.m.Types[t].CClass != mir.CClassRecord {
		return mir.Field{}, false
	}
	for _, tf := range g.m.Types[t].Fields {
		if tf.Name == name {
			return tf, true
		}
	}
	return mir.Field{}, false
}

// emitCNumConvert lowers the C-boundary conversion operations. Integer
// crossings widen into 64 bits with their own signedness and either cast
// directly (wrap, cast, or a total pair) or range-check into the option
// (try). Float pairs cast directly except the f64 to c_float narrowing,
// whose checked form compares in double against float's limits so NaN and
// out-of-range magnitudes yield none without a value conversion.
func (g *gen) emitCNumConvert(b *strings.Builder, in *mir.Instr) {
	src, _ := g.f.ValueType(in.A)
	dst := in.TypeOp
	if in.Op == mir.OpCNumTry {
		// The try form carries the whole option(E) type; the scalar target
		// is its payload.
		if g.m.ValidType(dst) && g.m.Types[dst].Kind == mir.TypeOption {
			dst = g.m.Types[dst].Elem
		}
	}
	if cConvFloatClass(g.m, src) != 0 {
		if in.Op == mir.OpCNumTry {
			tmp := g.tmp(in, "")
			v := g.valueExpr(in.A)
			b.WriteString("  double " + tmp + " = " + v + ";\n")
			b.WriteString("  " + g.val(in.Result) + ".alder_tag = (" + tmp + " >= -(double)FLT_MAX && " + tmp +
				" <= (double)FLT_MAX) ? (uint32_t)1 : (uint32_t)0;\n")
			b.WriteString("  if (" + g.val(in.Result) + ".alder_tag) { " + g.val(in.Result) + ".alder_u.alder_p1 = (float)" + tmp + "; }\n")
			return
		}
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(dst) + ")" + g.valueExpr(in.A) + ";\n")
		return
	}
	if in.Op != mir.OpCNumTry {
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(dst) + ")" + g.valueExpr(in.A) + ";\n")
		return
	}
	if cConvIntTotal(g.m, src, dst) {
		// The pair is lossless on every target: an always-some result needs
		// no comparison, and a comparison here would be tautological under
		// -Wtype-limits.
		b.WriteString("  " + g.val(in.Result) + ".alder_tag = (uint32_t)1;\n")
		b.WriteString("  " + g.val(in.Result) + ".alder_u.alder_p1 = (" + g.cType(dst) + ")" + g.valueExpr(in.A) + ";\n")
		return
	}
	wide := "int64_t"
	if cConvU64Wide(g.m, src) {
		wide = "uint64_t"
	}
	tmp := g.tmp(in, "")
	b.WriteString("  " + wide + " " + tmp + " = (" + wide + ")(" + g.cType(src) + ")" + g.valueExpr(in.A) + ";\n")
	b.WriteString("  " + g.val(in.Result) + ".alder_tag = (" + g.cConvCompare(src, dst, tmp) + ") ? (uint32_t)1 : (uint32_t)0;\n")
	b.WriteString("  if (" + g.val(in.Result) + ".alder_tag) { " + g.val(in.Result) + ".alder_u.alder_p1 = (" +
		g.cType(dst) + ")" + tmp + "; }\n")
}

// emitFloatConvert avoids C11's undefined out-of-range real conversion. MIR
// float narrowing is unchecked, so non-finite or out-of-range f64 values use
// the backend's fixed panic policy rather than reaching a C cast.
func (g *gen) emitFloatConvert(b *strings.Builder, in *mir.Instr) {
	source, _ := g.f.ValueType(in.A)
	if source == mir.TypeF64 && in.TypeOp == mir.TypeF32 {
		v := g.valueExpr(in.A)
		b.WriteString("  if (" + v + " != " + v + " || " + v + " > (double)FLT_MAX || " +
			v + " < -(double)FLT_MAX) { alder_runtime_panic(\"float.convert: out of range\"); }\n")
	}
	b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.valueExpr(in.A) + ";\n")
}

// emitFromFloat lowers int.from_float. The 64-bit target uses the defined
// runtime conversion and panics on out-of-range values; narrower targets
// range-check the 64-bit result.
func (g *gen) emitFromFloat(b *strings.Builder, in *mir.Instr) {
	_, signed := intInfo(in.TypeOp)
	width := intWidthOf(in.TypeOp)
	helper := "alder_u64_from_f64"
	if signed {
		helper = "alder_i64_from_f64"
	}
	if width == 64 {
		b.WriteString("  if (!" + helper + "(" + g.valueExpr(in.A) + ", &" + g.val(in.Result) +
			")) { alder_runtime_panic(\"int.from_float: out of range\"); }\n")
		return
	}
	b.WriteString("  " + signed64Name(signed) + " " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!" + helper + "(" + g.valueExpr(in.A) + ", &" + g.tmp(in, "") +
		")) { alder_runtime_panic(\"int.from_float: out of range\"); }\n")
	if signed {
		limits, limitu := intLimits(width)
		b.WriteString("  if (" + g.tmp(in, "") + " < (int64_t)" + limits + " || " +
			g.tmp(in, "") + " > (int64_t)" + limitu + ") { alder_runtime_panic(\"int.from_float: out of range\"); }\n")
	} else {
		limit := uintLimit(width)
		b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)" + limit +
			") { alder_runtime_panic(\"int.from_float: out of range\"); }\n")
	}
	b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.tmp(in, "") + ";\n")
}

// emitConstGet lowers const.get: scalars inline, strings reference static
// storage, and unit values disappear.
func (g *gen) emitConstGet(b *strings.Builder, in *mir.Instr) {
	c, ok := g.m.ConstDecl(in.Const)
	if !ok {
		b.WriteString("  /* unknown constant @" + in.Const + " */\n")
		return
	}
	if c.Type == mir.TypeUnit {
		return // unit values lower to the literal 0
	}
	switch c.Value.Kind {
	case mir.ConstBool:
		if c.Value.Bool {
			b.WriteString("  " + g.val(in.Result) + " = true;\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = false;\n")
		}
	case mir.ConstInt:
		if c.Type == mir.TypeU64 && c.Value.Int < 0 {
			// The signed field holds the 64-bit pattern of a value above
			// INT64_MAX; the unsigned decimal of the pattern renders it
			// without relying on an out-of-range conversion.
			b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(c.Type) + ")(" +
				strconv.FormatUint(uint64(c.Value.Int), 10) + "ULL);\n")
			return
		}
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(c.Type) + ")(" +
			intLiteral(c.Value.Int) + ");\n")
	case mir.ConstFloat:
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(c.Type) + ")(" +
			floatLiteral(c.Value.Float) + ");\n")
	case mir.ConstString:
		idx := g.strConsts[c.Name]
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(c.Type) + "){ alder_str_" +
			strconv.Itoa(idx) + ", (uint64_t)" + strconv.Itoa(len(c.Value.String)) + " };\n")
	}
}

// intLiteral renders an int64 constant; INT64_MIN needs the portable
// two-literal form because its positive magnitude has no long long literal.
func intLiteral(v int64) string {
	if v == -9223372036854775808 {
		return "-9223372036854775807LL - 1"
	}
	return strconv.FormatInt(v, 10) + "LL"
}

// floatLiteral renders a double constant in a form valid in C, preserving
// negative zero.
func floatLiteral(v float64) string {
	s := strconv.FormatFloat(v, 'g', -1, 64)
	if s == "-0" {
		return "-0.0"
	}
	return s
}

// emitTerm lowers the block terminator.
func (g *gen) emitTerm(b *strings.Builder, blk *mir.Block) {
	t := &blk.Term
	switch t.Kind {
	case mir.TermJump:
		b.WriteString("  " + g.edgeBody(t.Target, t.Args) + "\n")

	case mir.TermBranch:
		b.WriteString("  if (" + g.valueExpr(t.Cond) + ") " + g.edgeBody(t.Then, t.ThenArgs) +
			" else " + g.edgeBody(t.Else, t.ElseArgs) + "\n")

	case mir.TermSwitch:
		b.WriteString("  switch (" + g.valueExpr(t.Value) + ".alder_tag) {\n")
		for _, c := range t.Cases {
			if c.Variant == "" {
				b.WriteString("  default:\n")
			} else {
				idx, _ := g.m.VariantIndex(typeOfOperand(g.f, t.Value), c.Variant)
				b.WriteString("  case (uint32_t)" + strconv.Itoa(idx) + ":\n")
				if c.Binding != mir.NoValue {
					if bindingType, _ := g.f.ValueType(c.Binding); bindingType != mir.TypeUnit {
						b.WriteString("    " + g.val(c.Binding) + " = " + g.valueExpr(t.Value) +
							".alder_u.alder_p" + strconv.Itoa(idx) + ";\n")
					}
				}
			}
			b.WriteString("    " + g.edgeBody(c.Target, c.Args) + "\n")
		}
		b.WriteString("  }\n")

	case mir.TermReturn, mir.TermFail:
		if g.f.Result == mir.TypeUnit {
			b.WriteString("  return;\n")
		} else {
			b.WriteString("  return " + g.valueExpr(t.Result) + ";\n")
		}

	case mir.TermPanic:
		b.WriteString("  alder_runtime_panic(\"checked operation failed\");\n")

	case mir.TermUnreachable:
		b.WriteString("  alder_runtime_panic(\"unreachable\");\n")
	}
}

// emitCStringOp emits the c_string construction and release vocabulary.
// make_lit and make call runtime helpers that scan and copy the Alder bytes
// into a fresh malloc buffer: make_lit bytes are checker-proven interior-NUL
// free, so its only failure is allocation (the checked edge); make reports
// interior NUL as a none option through the status convention (0 copied, 1
// interior NUL, -1 allocation failure). ptr borrows the buffer pointer, and
// release frees it exactly once.
func (g *gen) emitCStringOp(b *strings.Builder, in *mir.Instr) {
	fail := g.failBody(in)
	str := g.valueExpr(in.A)
	res := g.val(in.Result)
	switch in.Op {
	case mir.OpCStringMakeLit:
		p := g.tmp(in, "cs")
		b.WriteString("  char *" + p + " = alder_cstring_make_lit(" + str + ".data, " + str + ".len);\n")
		b.WriteString("  if (" + p + " == NULL) " + fail + "\n")
		b.WriteString("  " + res + " = " + p + ";\n")
	case mir.OpCStringMake:
		p := g.tmp(in, "cs")
		st := g.tmp(in, "st")
		b.WriteString("  char *" + p + ";\n")
		b.WriteString("  int " + st + " = alder_cstring_make(" + str + ".data, " + str + ".len, &" + p + ");\n")
		b.WriteString("  if (" + st + " < 0) " + fail + "\n")
		b.WriteString("  if (" + st + " == 0) {\n")
		b.WriteString("    " + res + ".alder_u.alder_p1 = " + p + ";\n")
		b.WriteString("    " + res + ".alder_tag = (uint32_t)1;\n")
		b.WriteString("  } else {\n")
		b.WriteString("    " + res + ".alder_tag = (uint32_t)0;\n")
		b.WriteString("  }\n")
	case mir.OpCStringPtr:
		b.WriteString("  " + res + " = " + str + ";\n")
	default: // mir.OpCStringRelease
		b.WriteString("  alder_cstring_release(" + str + ");\n")
	}
}
