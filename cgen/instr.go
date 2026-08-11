package cgen

import (
	"strconv"
	"strings"

	"github.com/4fuu/aster/mir"
)

// place returns the C lvalue expression of a place.
func (g *gen) place(p *mir.Place) string {
	switch p.Kind {
	case mir.PlaceLocal:
		return "aster_l" + strconv.Itoa(int(p.Local))
	case mir.PlaceField:
		return g.place(p.Base) + ".aster_f_" + sanitize(p.Field)
	case mir.PlaceDeref:
		t, ok := g.f.ValueType(p.Deref)
		if !ok || !g.m.ValidType(t) {
			return "<invalid deref>"
		}
		elem := g.m.Types[t].Elem
		base := g.val(p.Deref)
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

// edgeBody emits block-parameter assignments and the goto for an edge.
func (g *gen) edgeBody(target mir.BlockId, args []mir.ValueId) string {
	var b strings.Builder
	g.edgeAssigns(&b, target, args)
	b.WriteString("goto aster_b" + strconv.Itoa(int(target)) + ";")
	return b.String()
}

// edgeAssigns writes the parameter assignments of an edge.
func (g *gen) edgeAssigns(b *strings.Builder, target mir.BlockId, args []mir.ValueId) {
	if int(target) >= len(g.f.Blocks) {
		return
	}
	for i, a := range args {
		vid, ok := g.paramValues[[2]int{int(target), i}]
		if !ok {
			continue
		}
		b.WriteString("aster_v" + strconv.Itoa(int(vid)) + " = " + g.val(a) + "; ")
	}
}

// emitInstr lowers one instruction to explicit, sequenced C statements.
func (g *gen) emitInstr(b *strings.Builder, blk *mir.Block, in *mir.Instr) {
	switch in.Op {
	case mir.OpLoad:
		b.WriteString("  " + g.val(in.Result) + " = " + g.place(&in.Place) + ";\n")

	case mir.OpStore:
		b.WriteString("  " + g.place(&in.Place) + " = " + g.val(in.StoreVal) + ";\n")

	case mir.OpAggregateConstruct:
		b.WriteString("  " + g.val(in.Result) + " = (AsterTy" + strconv.Itoa(int(in.AggType)) + "){")
		for i, af := range in.AggFields {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(".aster_f_" + sanitize(af.Name) + " = " + g.val(af.Value))
		}
		b.WriteString("};\n")

	case mir.OpDomainCreate:
		b.WriteString("  if (!aster_domain_init(&aster_domain_" + strconv.Itoa(g.domainUsed) +
			", " + g.val(in.Domain) + ")) { aster_runtime_panic(\"domain.create failed\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = &aster_domain_" + strconv.Itoa(g.domainUsed) + ";\n")
		g.domainUsed++

	case mir.OpDomainMark:
		b.WriteString("  " + g.val(in.Result) + " = aster_domain_mark(" + g.val(in.Domain) + ");\n")

	case mir.OpDomainReset:
		b.WriteString("  if (!aster_domain_reset(" + g.val(in.Domain) + ", " + g.val(in.Mark) +
			")) { aster_runtime_panic(\"domain.reset failed\"); }\n")

	case mir.OpDomainDestroy:
		b.WriteString("  aster_domain_destroy(" + g.val(in.Domain) + ");\n")

	case mir.OpAlloc:
		elem := in.TypeOp
		b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
		b.WriteString("  if (!aster_u64_mul_checked(" + g.val(in.Count) + ", " +
			g.typeSize(elem) + ", &" + g.tmp(in, "") + ")) { aster_runtime_panic(\"alloc: size overflow\"); }\n")
		b.WriteString("  void *" + g.tmp(in, "p") + " = aster_domain_alloc(" + g.val(in.Domain) +
			", (size_t)" + g.tmp(in, "") + ", (size_t)" + g.typeAlign(elem) + ");\n")
		b.WriteString("  if (" + g.tmp(in, "p") + " == NULL) { aster_runtime_panic(\"alloc: out of memory\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = (AsterSlice){ " + g.tmp(in, "p") + ", " +
			g.val(in.Count) + " };\n")

	case mir.OpCopyToDomain:
		t, ok := g.f.ValueType(in.CopyVal)
		if ok && g.copyTrivial(t) {
			b.WriteString("  " + g.val(in.Result) + " = " + g.val(in.CopyVal) + ";\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = aster_copy_ty" + strconv.Itoa(int(t)) +
				"(" + g.val(in.Domain) + ", " + g.val(in.CopyVal) + ");\n")
		}

	case mir.OpCleanupScopeBegin:
		b.WriteString("  if (!aster_cleanup_scope_begin(&aster_scope_" + strconv.Itoa(g.scopeUsed) +
			")) { aster_runtime_panic(\"cleanup.scope.begin failed\"); }\n")
		b.WriteString("  " + g.val(in.Result) + " = &aster_scope_" + strconv.Itoa(g.scopeUsed) + ";\n")
		g.scopeUsed++

	case mir.OpCleanupPush:
		idx := g.pushSites[[3]int{int(fnIndexOf(g.m, g.f)), int(blockIndexOf(g.f, blk)), instrIndexOf(blk, in)}]
		callee := g.m.Functions[in.CleanupFn]
		arg := 0
		for ai, a := range in.CleanupArgs {
			if callee.Params[ai].Type == mir.TypeUnit {
				continue
			}
			b.WriteString("  aster_ctx_" + strconv.Itoa(idx) + ".aster_f" + strconv.Itoa(arg) +
				" = " + g.val(a) + ";\n")
			arg++
		}
		b.WriteString("  if (!aster_cleanup_push(" + g.val(in.Scope) + ", aster_cleanup_" +
			strconv.Itoa(idx) + ", &aster_ctx_" + strconv.Itoa(idx) + ", &" + g.val(in.Result) +
			")) { aster_runtime_panic(\"cleanup.push failed\"); }\n")

	case mir.OpCleanupDisarm:
		b.WriteString("  if (!aster_cleanup_disarm(" + g.val(in.CleanupID) +
			")) { aster_runtime_panic(\"cleanup.disarm failed\"); }\n")

	case mir.OpCleanupScopeRun:
		b.WriteString("  if (!aster_cleanup_run(" + g.val(in.Scope) +
			")) { aster_runtime_panic(\"cleanup.scope.run failed\"); }\n")

	case mir.OpCleanupScopeEnd:
		b.WriteString("  if (!aster_cleanup_end(" + g.val(in.Scope) +
			")) { aster_runtime_panic(\"cleanup.scope.end failed\"); }\n")

	case mir.OpIntAddChecked, mir.OpIntSubChecked, mir.OpIntMulChecked,
		mir.OpIntDivChecked, mir.OpIntShlChecked, mir.OpIntShrChecked:
		g.emitIntChecked(b, in)

	case mir.OpSliceLen:
		b.WriteString("  " + g.val(in.Result) + " = " + g.val(in.Slice) + ".len;\n")

	case mir.OpSliceIndexChecked:
		g.emitSliceIndex(b, in)

	case mir.OpSliceRangeChecked:
		g.emitSliceRange(b, in)

	case mir.OpEnumPayloadChecked:
		t, _ := g.f.ValueType(in.EnumValue)
		idx, _ := g.m.VariantIndex(t, in.Variant)
		b.WriteString("  if (" + g.val(in.EnumValue) + ".aster_tag != (uint32_t)" + strconv.Itoa(idx) +
			") { " + g.failBody(in) + " }\n")
		b.WriteString("  " + g.val(in.Result) + " = " + g.val(in.EnumValue) + ".aster_u.aster_p" +
			strconv.Itoa(idx) + ";\n")

	case mir.OpEnumConstruct:
		idx, _ := g.m.VariantIndex(in.TypeOp, in.Variant)
		b.WriteString("  " + g.val(in.Result) + ".aster_tag = (uint32_t)" + strconv.Itoa(idx) + ";\n")
		payload, _ := g.m.VariantPayload(in.TypeOp, idx)
		if payload != mir.TypeUnit {
			b.WriteString("  " + g.val(in.Result) + ".aster_u.aster_p" + strconv.Itoa(idx) +
				" = " + g.val(in.Payload) + ";\n")
		}

	case mir.OpTableCreate:
		b.WriteString("  if (!aster_table_init(&" + g.val(in.Result) + ", " + g.val(in.Domain) +
			", " + g.typeSize(in.TypeOp) + ", " + g.typeAlign(in.TypeOp) +
			")) { aster_runtime_panic(\"table.create failed\"); }\n")

	case mir.OpTableInsert:
		b.WriteString("  if (!aster_table_insert(&" + g.val(in.Table) + ", &" + g.val(in.TableVal) +
			", &" + g.val(in.Result) + ")) { aster_runtime_panic(\"table.insert failed\"); }\n")

	case mir.OpTableLookup, mir.OpTableLookupMut:
		t, _ := g.f.ValueType(in.Table)
		elem := g.m.Types[t].Elem
		// option(table_view(elem)): tag 0 = none, tag 1 = some(view).
		b.WriteString("  void *" + g.tmp(in, "") + ";\n")
		b.WriteString("  if (aster_table_lookup" + lookupSuffix(in.Op) + "(&" + g.val(in.Table) +
			", " + g.val(in.ID) + ", &" + g.tmp(in, "") + ")) {\n")
		b.WriteString("    " + g.val(in.Result) + ".aster_tag = (uint32_t)1;\n")
		b.WriteString("    " + g.val(in.Result) + ".aster_u.aster_p1 = " + g.tmp(in, "") + ";\n")
		b.WriteString("  } else {\n")
		b.WriteString("    " + g.val(in.Result) + ".aster_tag = (uint32_t)0;\n")
		b.WriteString("  }\n")
		_ = elem

	case mir.OpTableRemove:
		b.WriteString("  " + g.val(in.Result) + " = aster_table_remove(&" + g.val(in.Table) +
			", " + g.val(in.ID) + ");\n")

	case mir.OpTableViewEnd:
		b.WriteString("  (void)" + g.val(in.View) + ";\n")

	case mir.OpIntEq, mir.OpIntNe, mir.OpIntLt, mir.OpIntLe, mir.OpIntGt, mir.OpIntGe,
		mir.OpFloatEq, mir.OpFloatNe, mir.OpFloatLt, mir.OpFloatLe, mir.OpFloatGt, mir.OpFloatGe:
		b.WriteString("  " + g.val(in.Result) + " = (bool)(" + g.val(in.A) + " " +
			cmpOp(in.Op) + " " + g.val(in.B) + ");\n")

	case mir.OpIntTrunc:
		g.emitTrunc(b, in)

	case mir.OpIntZext, mir.OpIntSext, mir.OpFloatConvert, mir.OpFloatFromInt:
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.val(in.A) + ";\n")

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

	case mir.OpFFICallUnsafe:
		imp := &g.m.Imports[in.FFIImport]
		b.WriteString("  ")
		if imp.Sig.Result != mir.TypeUnit {
			b.WriteString(g.val(in.Result) + " = ")
		}
		b.WriteString(sanitize(imp.Name) + "(")
		for i, a := range in.Args {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(g.val(a))
		}
		b.WriteString(");\n")
	}
}

func lookupSuffix(op mir.OpKind) string {
	if op == mir.OpTableLookupMut {
		return "_mut"
	}
	return ""
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
		b.WriteString(g.val(a))
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
	helper := "aster_u64_"
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
		helper = "aster_i64_"
	}
	// 64-bit operations call the runtime helper directly.
	if width == 64 {
		b.WriteString("  if (!" + helper + opName + "(" + g.val(in.A) + ", " + g.val(in.B) +
			", &" + g.val(in.Result) + ")) { " + g.failBody(in) + " }\n")
		return
	}
	// Narrow: promote to 64 bits, compute with the helper, and range-check.
	srcCast := g.cType(t)
	b.WriteString("  " + signed64Name(signed) + " " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!" + helper + opName + "((" + srcCast + ")" + g.val(in.A) + ", (" +
		srcCast + ")" + g.val(in.B) + ", &" + g.tmp(in, "") + ")) { " + g.failBody(in) + " }\n")
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
		helper := "aster_u64_sh"
		if signed {
			helper = "aster_i64_sh"
		}
		if shl {
			helper += "l_checked"
		} else {
			helper += "r_checked"
		}
		b.WriteString("  if (!" + helper + "(" + g.val(in.A) + ", " + g.val(in.B) +
			", &" + g.val(in.Result) + ")) { " + fail + " }\n")
		return
	}
	// Narrow: check the count against the source width, then compute at that
	// width. Unsigned targets wrap by casting; signed targets transfer the
	// two's-complement bit pattern with memcpy.
	if signed {
		b.WriteString("  if (" + g.val(in.B) + " < 0 || " + g.val(in.B) + " >= " +
			strconv.Itoa(width) + ") { " + fail + " }\n")
	} else {
		b.WriteString("  if (" + g.val(in.B) + " >= " + strconv.Itoa(width) + ") { " + fail + " }\n")
	}
	u := "uint" + strconv.Itoa(width) + "_t"
	if !signed {
		if shl {
			b.WriteString("  " + g.val(in.Result) + " = (" + u + ")(((uint64_t)(" + u + ")" +
				g.val(in.A) + ") << (unsigned)" + g.val(in.B) + ");\n")
		} else {
			b.WriteString("  " + g.val(in.Result) + " = (" + u + ")((uint64_t)(" + u + ")" +
				g.val(in.A) + " >> (unsigned)" + g.val(in.B) + ");\n")
		}
		return
	}
	i := "int" + strconv.Itoa(width) + "_t"
	if shl {
		b.WriteString("  " + u + " " + g.tmp(in, "") + " = (" + u + ")(((uint64_t)(" + u + ")" +
			g.val(in.A) + ") << (unsigned)" + g.val(in.B) + ");\n")
		b.WriteString("  memcpy(&" + g.val(in.Result) + ", &" + g.tmp(in, "") + ", sizeof(" + g.tmp(in, "") + "));\n")
	} else {
		b.WriteString("  " + g.val(in.Result) + " = (" + i + ")((int64_t)(" + i + ")" +
			g.val(in.A) + " >> (unsigned)" + g.val(in.B) + ");\n")
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
	b.WriteString("  if (!aster_slice_index_checked(" + g.val(in.Slice) + ", " + g.val(in.Index) +
		")) { " + fail + " }\n")
	b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!aster_u64_mul_checked(" + g.val(in.Index) + ", " + g.typeSize(elem) +
		", &" + g.tmp(in, "") + ")) { " + fail + " }\n")
	b.WriteString("  " + g.val(in.Result) + " = (AsterSlice){ (void *)((uint8_t *)" +
		g.val(in.Slice) + ".data + (size_t)" + g.tmp(in, "") + "), (uint64_t)1 };\n")
}

// emitSliceRange lowers slice.range.checked to a bounds check and a
// sub-slice with a checked byte offset.
func (g *gen) emitSliceRange(b *strings.Builder, in *mir.Instr) {
	elem := g.sliceElemType(in.Slice)
	fail := g.failBody(in)
	b.WriteString("  if (!aster_slice_range_checked(" + g.val(in.Slice) + ", " + g.val(in.Lo) +
		", " + g.val(in.Hi) + ")) { " + fail + " }\n")
	b.WriteString("  uint64_t " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!aster_u64_mul_checked(" + g.val(in.Lo) + ", " + g.typeSize(elem) +
		", &" + g.tmp(in, "") + ")) { " + fail + " }\n")
	b.WriteString("  " + g.val(in.Result) + " = (AsterSlice){ (void *)((uint8_t *)" +
		g.val(in.Slice) + ".data + (size_t)" + g.tmp(in, "") + "), (uint64_t)(" +
		g.val(in.Hi) + " - " + g.val(in.Lo) + ") };\n")
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
		b.WriteString("  " + g.val(in.Result) + " = (" + g.cType(in.TypeOp) + ")" + g.val(in.A) + ";\n")
		return
	}
	b.WriteString("  " + u + " " + g.tmp(in, "") + " = (" + u + ")" + g.val(in.A) + ";\n")
	b.WriteString("  memcpy(&" + g.val(in.Result) + ", &" + g.tmp(in, "") + ", sizeof(" + g.tmp(in, "") + "));\n")
}

func intWidthOf(t mir.TypeId) int {
	w, _ := intInfo(t)
	return w
}

// emitFromFloat lowers int.from_float. The 64-bit target uses the defined
// runtime conversion and panics on out-of-range values; narrower targets
// range-check the 64-bit result.
func (g *gen) emitFromFloat(b *strings.Builder, in *mir.Instr) {
	_, signed := intInfo(in.TypeOp)
	width := intWidthOf(in.TypeOp)
	helper := "aster_u64_from_f64"
	if signed {
		helper = "aster_i64_from_f64"
	}
	if width == 64 {
		b.WriteString("  if (!" + helper + "(" + g.val(in.A) + ", &" + g.val(in.Result) +
			")) { aster_runtime_panic(\"int.from_float: out of range\"); }\n")
		return
	}
	b.WriteString("  " + signed64Name(signed) + " " + g.tmp(in, "") + ";\n")
	b.WriteString("  if (!" + helper + "(" + g.val(in.A) + ", &" + g.tmp(in, "") +
		")) { aster_runtime_panic(\"int.from_float: out of range\"); }\n")
	if signed {
		limits, limitu := intLimits(width)
		b.WriteString("  if (" + g.tmp(in, "") + " < (int64_t)" + limits + " || " +
			g.tmp(in, "") + " > (int64_t)" + limitu + ") { aster_runtime_panic(\"int.from_float: out of range\"); }\n")
	} else {
		limit := uintLimit(width)
		b.WriteString("  if (" + g.tmp(in, "") + " > (uint64_t)" + limit +
			") { aster_runtime_panic(\"int.from_float: out of range\"); }\n")
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
		b.WriteString("  " + g.val(in.Result) + " = (AsterSlice){ (void *)aster_str_" +
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
		b.WriteString("  if (" + g.val(t.Cond) + ") {\n")
		g.edgeAssigns(b, t.Then, t.ThenArgs)
		b.WriteString("    goto aster_b" + strconv.Itoa(int(t.Then)) + ";\n")
		b.WriteString("  } else {\n")
		g.edgeAssigns(b, t.Else, t.ElseArgs)
		b.WriteString("    goto aster_b" + strconv.Itoa(int(t.Else)) + ";\n")
		b.WriteString("  }\n")

	case mir.TermSwitch:
		b.WriteString("  switch (" + g.val(t.Value) + ".aster_tag) {\n")
		for _, c := range t.Cases {
			if c.Variant == "" {
				b.WriteString("  default:\n")
			} else {
				idx, _ := g.m.VariantIndex(typeOfOperand(g.f, t.Value), c.Variant)
				b.WriteString("  case (uint32_t)" + strconv.Itoa(idx) + ":\n")
				if c.Binding != mir.NoValue {
					b.WriteString("    " + g.val(c.Binding) + " = " + g.val(t.Value) +
						".aster_u.aster_p" + strconv.Itoa(idx) + ";\n")
				}
			}
			g.edgeAssigns(b, c.Target, c.Args)
			b.WriteString("    goto aster_b" + strconv.Itoa(int(c.Target)) + ";\n")
		}
		b.WriteString("  }\n")

	case mir.TermReturn, mir.TermFail:
		if g.f.Result == mir.TypeUnit {
			b.WriteString("  return;\n")
		} else {
			b.WriteString("  return " + g.val(t.Result) + ";\n")
		}

	case mir.TermUnreachable:
		b.WriteString("  aster_runtime_panic(\"unreachable\");\n")
	}
}
