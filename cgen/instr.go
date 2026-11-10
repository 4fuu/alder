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
