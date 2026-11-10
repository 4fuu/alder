package cgen

import (
	"strconv"
	"strings"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// cType returns the C type of a MIR type.
func (g *gen) cType(t mir.TypeId) string {
	switch {
	case t == mir.TypeUnit:
		return "uint8_t"
	case t == mir.TypeBool:
		return "bool"
	case t == mir.TypeI8:
		return "int8_t"
	case t == mir.TypeI16:
		return "int16_t"
	case t == mir.TypeI32:
		return "int32_t"
	case t == mir.TypeI64:
		return "int64_t"
	case t == mir.TypeU8:
		return "uint8_t"
	case t == mir.TypeU16:
		return "uint16_t"
	case t == mir.TypeU32:
		return "uint32_t"
	case t == mir.TypeU64:
		return "uint64_t"
	case t == mir.TypeF32:
		return "float"
	case t == mir.TypeF64:
		return "double"
	}
	if !g.m.ValidType(t) {
		return "void"
	}
	ty := &g.m.Types[t]
	switch ty.Kind {
	case mir.TypeAggregate, mir.TypeEnum, mir.TypeOption, mir.TypeResult, mir.TypeArray:
		return "AlderTy" + strconv.Itoa(int(t))
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
		return "AlderSlice"
	case mir.TypeVec:
		return "AlderVec"
	case mir.TypeString:
		return "AlderString"
	case mir.TypeBytes:
		return "AlderBytes"
	case mir.TypeRawPtr:
		return "void *"
	case mir.TypeCRaw:
		switch ty.Length {
		case mir.CScalarChar:
			return "char"
		case mir.CScalarSChar:
			return "signed char"
		case mir.CScalarUChar:
			return "unsigned char"
		case mir.CScalarShort:
			return "short"
		case mir.CScalarUShort:
			return "unsigned short"
		case mir.CScalarInt:
			return "int"
		case mir.CScalarUInt:
			return "unsigned int"
		case mir.CScalarLong:
			return "long"
		case mir.CScalarULong:
			return "unsigned long"
		case mir.CScalarLongLong:
			return "long long"
		case mir.CScalarULongLong:
			return "unsigned long long"
		case mir.CScalarFloat:
			return "float"
		case mir.CScalarDouble:
			return "double"
		case mir.CScalarSize:
			return "size_t"
		case mir.CScalarPtrdiff:
			return "ptrdiff_t"
		}
		return "void"
	case mir.TypeCPtr:
		return g.cType(ty.Elem) + " *"
	case mir.TypeCConstPtr:
		return "const " + g.cType(ty.Elem) + " *"
	case mir.TypeCNamed:
		if ty.CName != "" {
			return ty.CName
		}
		return "void"
	case mir.TypeFunction:
		return "AlderFnTy" + strconv.Itoa(int(t))
	case mir.TypeDomainHandle:
		return "AlderDomain *"
	case mir.TypeDomainMark:
		return "AlderDomainMark"
	case mir.TypeCleanupScope:
		return "AlderCleanupScope *"
	case mir.TypeCleanupID:
		return "AlderCleanupId"
	case mir.TypeTable:
		return "AlderTable *"
	case mir.TypeID:
		return "AlderTableId"
	case mir.TypeTableView, mir.TypeTableMutView:
		return "void *"
	}
	return "void"
}

// typeSize returns a C constant expression for the byte size of a type.
// Structural types use sizeof of their C type; the verifier's backend
// preconditions keep handles, views, and raw pointers out of alloc and table
// element positions.
func (g *gen) typeSize(t mir.TypeId) string {
	return "(uint64_t)sizeof(" + g.cType(t) + ")"
}

// typeAlign returns a C constant expression for the alignment of a type.
func (g *gen) typeAlign(t mir.TypeId) string {
	return "(uint64_t)_Alignof(" + g.cType(t) + ")"
}

// val returns the C variable of a value.
func (g *gen) val(v mir.ValueId) string {
	return "alder_v" + strconv.Itoa(int(v))
}

// valueExpr returns a C expression for a MIR value. Unit values have no C
// variable; their single semantic value is materialized as a zero byte where
// an expression is required.
func (g *gen) valueExpr(v mir.ValueId) string {
	if t, ok := g.f.ValueType(v); ok && t == mir.TypeUnit {
		return "(uint8_t)0"
	}
	return g.val(v)
}

func (g *gen) fieldName(base *mir.Place, sourceName string) string {
	t, ok := g.m.PlaceType(g.f, base)
	if !ok || !g.m.ValidType(t) || g.m.Types[t].Kind != mir.TypeAggregate {
		return "alder_invalid_field"
	}
	for i, field := range g.m.Types[t].Fields {
		if field.Name == sourceName {
			return "alder_f" + strconv.Itoa(i)
		}
	}
	return "alder_invalid_field"
}

// tmp returns the name of the instruction-local temporary keyed by the
// result value, which is unique per function.
func (g *gen) tmp(in *mir.Instr, suffix string) string {
	return "alder_t" + strconv.Itoa(int(in.Result)) + suffix
}

// emitFunction lowers one function: declarations, hidden slots, blocks, and
// the terminator of each block.
func (g *gen) emitFunction(b *strings.Builder, f *mir.Function) {
	g.f = f
	g.paramValues = make(map[[2]int]mir.ValueId)
	for vi, v := range f.Values {
		if v.Def.Kind == mir.ValueDefBlockParam {
			g.paramValues[[2]int{int(v.Def.Block), v.Def.Param}] = mir.ValueId(vi)
		}
	}
	g.valueRead = make([]bool, len(f.Values))
	g.localRead = make([]bool, len(f.Locals))
	g.computeUses(f)
	g.domainUsed = 0
	g.scopeUsed = 0
	g.edgeUsed = 0
	fi := fnIndexOf(g.m, f)

	b.WriteString("static ALDER_MAYBE_UNUSED " + g.fnResultType(f) + " " +
		g.fnName(fnIndexOf(g.m, f)) + "(" + g.fnParams(f) + ") {\n")
	for vi, v := range f.Values {
		switch v.Def.Kind {
		case mir.ValueDefFuncParam:
			continue // already a C parameter
		}
		if v.Type == mir.TypeUnit {
			continue // unit values lower to the literal 0
		}
		b.WriteString("  ALDER_MAYBE_UNUSED " + g.cType(v.Type) + " " + g.val(mir.ValueId(vi)) + ";\n")
	}
	for li, l := range f.Locals {
		b.WriteString("  ALDER_MAYBE_UNUSED " + g.cType(l.Type) + " alder_l" + strconv.Itoa(li) + ";\n")
	}
	for i := 0; i < g.domainTotal[int(fi)]; i++ {
		b.WriteString("  AlderDomain alder_domain_" + strconv.Itoa(i) + " = {0};\n")
	}
	for i := 0; i < g.scopeTotal[int(fi)]; i++ {
		b.WriteString("  AlderCleanupScope alder_scope_" + strconv.Itoa(i) + " = {0};\n")
	}
	for _, s := range g.ctxSitesIn(f) {
		b.WriteString("  AlderCtx_" + strconv.Itoa(s) + " alder_ctx_" + strconv.Itoa(s) + " = {0};\n")
	}
	// Function parameters cannot carry indeterminate values, so an explicit
	// void use safely suppresses strict unused-parameter warnings.
	for vi := range f.Params {
		if f.Params[vi].Type != mir.TypeUnit && !g.valueRead[vi] {
			b.WriteString("  (void)" + g.val(mir.ValueId(vi)) + ";\n")
		}
	}
	b.WriteString("\n")

	for i, blk := range f.Blocks {
		if blk == nil {
			continue
		}
		// The entry block has no predecessors, so it needs no label; other
		// blocks get a label followed by a null statement, because C11 labels
		// must precede statements, not declarations. Dead blocks (never
		// jumped to) mark their label as possibly unused.
		if i > 0 {
			b.WriteString("alder_b" + strconv.Itoa(i) + ": ALDER_MAYBE_UNUSED ;\n")
		}
		for ii := range blk.Instrs {
			g.emitInstr(b, blk, &blk.Instrs[ii])
		}
		g.emitTerm(b, blk)
	}
	b.WriteString("}\n")
}

// ctxSitesIn returns the ctx indices of the cleanup.push sites of a function
// in instruction order.
func (g *gen) ctxSitesIn(f *mir.Function) []int {
	var out []int
	fi := fnIndexOf(g.m, f)
	for bi, blk := range f.Blocks {
		if blk == nil {
			continue
		}
		for ii := range blk.Instrs {
			if blk.Instrs[ii].Op == mir.OpCleanupPush {
				out = append(out, g.pushSites[[3]int{int(fi), bi, ii}])
			}
		}
	}
	return out
}

func fnIndexOf(m *mir.Module, f *mir.Function) mir.FunctionId {
	for i, g := range m.Functions {
		if g == f {
			return mir.FunctionId(i)
		}
	}
	return mir.NoFunction
}

func blockIndexOf(f *mir.Function, want *mir.Block) mir.BlockId {
	for i, b := range f.Blocks {
		if b == want {
			return mir.BlockId(i)
		}
	}
	return mir.NoBlock
}

// computeUses marks values and locals that are read anywhere, so the prologue
// can silence unused-variable warnings without changing behavior.
func (g *gen) computeUses(f *mir.Function) {
	markRead := func(v mir.ValueId) {
		if int(v) < len(g.valueRead) {
			g.valueRead[v] = true
		}
	}
	for _, blk := range f.Blocks {
		if blk == nil {
			continue
		}
		for ii := range blk.Instrs {
			in := &blk.Instrs[ii]
			for _, v := range verifyOperandValues(in) {
				markRead(v)
			}
			if in.Op == mir.OpLoad || in.Op == mir.OpStore || in.Op == mir.OpBorrow || in.Op == mir.OpBorrowMut {
				g.markPlaceReads(in.Place, in.Op != mir.OpStore)
			}
			if in.FailTarget != mir.NoBlock {
				for _, v := range in.FailArgs {
					markRead(v)
				}
			}
		}
		t := &blk.Term
		switch t.Kind {
		case mir.TermJump:
			for _, v := range t.Args {
				markRead(v)
			}
		case mir.TermBranch:
			markRead(t.Cond)
			for _, v := range t.ThenArgs {
				markRead(v)
			}
			for _, v := range t.ElseArgs {
				markRead(v)
			}
		case mir.TermSwitch:
			markRead(t.Value)
			for _, c := range t.Cases {
				for _, v := range c.Args {
					markRead(v)
				}
			}
		case mir.TermReturn, mir.TermFail:
			markRead(t.Result)
		}
	}
	// Block parameter values are read if their variable is assigned at any
	// edge; treat assignment as a use so edges never warn.
	for vi, v := range f.Values {
		if v.Def.Kind == mir.ValueDefBlockParam {
			g.valueRead[vi] = true
		}
	}
}

// markPlaceReads walks a place and records the local (for loads) or the
// deref value (for all accesses) as read.
func (g *gen) markPlaceReads(p mir.Place, isLoad bool) {
	walk := func(p *mir.Place) {}
	var rec func(p *mir.Place)
	rec = func(p *mir.Place) {
		if p == nil {
			return
		}
		switch p.Kind {
		case mir.PlaceLocal:
			if isLoad && int(p.Local) < len(g.localRead) {
				g.localRead[p.Local] = true
			}
		case mir.PlaceField:
			rec(p.Base)
		case mir.PlaceDeref:
			if int(p.Deref) < len(g.valueRead) {
				g.valueRead[p.Deref] = true
			}
		}
	}
	rec(&p)
	_ = walk
}

// verifyOperandValues returns the value operands of an instruction in a
// stable order, using the verifier's shared operand-shape table.
func verifyOperandValues(in *mir.Instr) []mir.ValueId {
	return verify.OperandValues(in)
}
