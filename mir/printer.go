package mir

import (
	"strconv"
	"strings"
)

// Print renders the module in the deterministic textual MIR format. Output
// order derives from declaration and ID order only; it never depends on map
// iteration, memory addresses, or host paths.
func Print(m *Module) string {
	var b strings.Builder
	b.WriteString("mir ")
	b.WriteString(strconv.Itoa(m.FormatVersion))
	b.WriteString("\n")

	for i := NumPrimitiveTypes; i < TypeId(len(m.Types)); i++ {
		t := &m.Types[i]
		switch t.Kind {
		case TypeAggregate:
			b.WriteString("\ntype @" + t.Name + " {\n")
			for _, fld := range t.Fields {
				b.WriteString("  " + fld.Name + ": " + m.TypeString(fld.Type) + "\n")
			}
			b.WriteString("}\n")
		case TypeEnum:
			b.WriteString("\nenum @" + t.Name + " {\n")
			for _, v := range t.Variants {
				b.WriteString("  " + v.Name)
				if v.Payload != TypeUnit {
					b.WriteString("(" + m.TypeString(v.Payload) + ")")
				}
				b.WriteString("\n")
			}
			b.WriteString("}\n")
		}
	}

	for _, c := range m.Constants {
		b.WriteString("\nconst @" + c.Name + ": " + m.TypeString(c.Type) + " = ")
		printConstValueFor(&b, c.Value, c.Type)
		b.WriteString("\n")
	}

	for _, imp := range m.Imports {
		b.WriteString("\nimport @" + imp.Name + ": ")
		printSig(&b, m, imp.Sig)
		b.WriteString("\n")
	}

	for bi := range m.Bindings {
		bind := &m.Bindings[bi]
		b.WriteString("\nbinding @" + bind.Name + " " + strconv.Quote(bind.Header) + " {\n")
		for _, id := range bind.Types {
			ty := &m.Types[id]
			b.WriteString("  c_type ")
			switch ty.CClass {
			case CClassScalar:
				b.WriteString("scalar ")
			case CClassOpaque:
				b.WriteString("opaque ")
			case CClassRecord:
				b.WriteString("record ")
			}
			b.WriteString("@" + ty.Name + " = " + strconv.Quote(ty.CName))
			if ty.CClass == CClassRecord {
				b.WriteString(" {")
				for i, fld := range ty.Fields {
					if i > 0 {
						b.WriteString(",")
					}
					b.WriteString(" " + fld.Name + ": " + m.TypeString(fld.Type))
					if fld.CName != fld.Name {
						b.WriteString(" = " + strconv.Quote(fld.CName))
					}
				}
				if len(ty.Fields) > 0 {
					b.WriteString(" ")
				}
				b.WriteString("}")
			}
			b.WriteString("\n")
		}
		for _, fn := range bind.Funcs {
			b.WriteString("  c_fn @" + fn.Name)
			if fn.CName != fn.Name {
				b.WriteString(" = " + strconv.Quote(fn.CName))
			}
			b.WriteString("(")
			for i, p := range fn.Sig.Params {
				if i > 0 {
					b.WriteString(", ")
				}
				b.WriteString(m.TypeString(p))
			}
			b.WriteString(") -> " + m.TypeString(fn.Sig.Result) + "\n")
		}
		for _, c := range bind.Consts {
			b.WriteString("  c_const @" + c.Name)
			if c.CName != c.Name {
				b.WriteString(" = " + strconv.Quote(c.CName))
			}
			b.WriteString(": " + m.TypeString(c.Type) + "\n")
		}
		b.WriteString("}\n")
	}

	for _, f := range m.Functions {
		if f == nil {
			continue
		}
		b.WriteString("\nfn @" + f.Name + "(")
		printParams(&b, m, f.Params)
		b.WriteString(")")
		if f.Result != TypeUnit {
			b.WriteString(" -> " + m.TypeString(f.Result))
		}
		b.WriteString(" {\n")
		for _, l := range f.Locals {
			b.WriteString("  local %" + l.Name + ": " + m.TypeString(l.Type) + "\n")
		}
		if len(f.Locals) > 0 {
			b.WriteString("\n")
		}
		for i, blk := range f.Blocks {
			if blk != nil {
				if i > 0 {
					b.WriteString("\n")
				}
				printBlock(&b, m, f, blk)
			}
		}
		b.WriteString("}\n")
	}
	return b.String()
}

func printParams(b *strings.Builder, m *Module, params []Param) {
	for i, p := range params {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString("%" + p.Name + ": " + m.TypeString(p.Type))
	}
}

func printSig(b *strings.Builder, m *Module, sig FuncSig) {
	b.WriteString("fn(")
	for i, p := range sig.Params {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(m.TypeString(p))
	}
	b.WriteString(") -> ")
	b.WriteString(m.TypeString(sig.Result))
}

// printConstValueFor renders a constant value. A u64 constant stores its
// 64-bit pattern in the signed Int field; the printed form is the unsigned
// decimal of that pattern so the text matches the source-level value.
func printConstValueFor(b *strings.Builder, v ConstValue, t TypeId) {
	switch v.Kind {
	case ConstUnit:
		b.WriteString("()")
	case ConstBool:
		if v.Bool {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	case ConstInt:
		if t == TypeU64 {
			b.WriteString(strconv.FormatUint(uint64(v.Int), 10))
		} else {
			b.WriteString(strconv.FormatInt(v.Int, 10))
		}
	case ConstFloat:
		b.WriteString(strconv.FormatFloat(v.Float, 'g', -1, 64))
	case ConstString:
		b.WriteString(strconv.Quote(v.String))
	}
}

func printBlock(b *strings.Builder, m *Module, f *Function, blk *Block) {
	b.WriteString(blk.Name)
	if len(blk.Params) > 0 {
		b.WriteString("(")
		printParams(b, m, blk.Params)
		b.WriteString(")")
	}
	b.WriteString(":\n")
	for i := range blk.Instrs {
		printInstr(b, m, f, &blk.Instrs[i])
	}
	printTerm(b, m, f, &blk.Term)
}

func valueName(f *Function, v ValueId) string {
	if int(v) >= len(f.Values) {
		return "<invalid value>"
	}
	return "%" + f.Values[v].Name
}

func fnName(m *Module, id FunctionId) string {
	if int(id) >= len(m.Functions) {
		return "<invalid function>"
	}
	return m.Functions[id].Name
}

func importName(m *Module, id ImportId) string {
	if int(id) >= len(m.Imports) {
		return "<invalid import>"
	}
	return m.Imports[id].Name
}

// bindingFuncName renders a flattened block-major binding-function index as
// its "@block.function" reference.
func bindingFuncName(m *Module, index int) string {
	block, fn, ok := m.BindingFuncAt(index)
	if !ok {
		return "<invalid binding function>"
	}
	return m.Bindings[block].Name + "." + fn.Name
}

func blockName(f *Function, id BlockId) string {
	if int(id) >= len(f.Blocks) {
		return "<invalid block>"
	}
	return f.Blocks[id].Name
}

func printBlockRef(b *strings.Builder, f *Function, id BlockId, args []ValueId) {
	b.WriteString(blockName(f, id))
	if len(args) > 0 {
		b.WriteString("(")
		for i, a := range args {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(valueName(f, a))
		}
		b.WriteString(")")
	}
}

func printFailEdge(b *strings.Builder, f *Function, in *Instr) {
	if in.FailTarget != NoBlock {
		b.WriteString(" else ")
		printBlockRef(b, f, in.FailTarget, in.FailArgs)
	}
}

func printPlace(m *Module, f *Function, p *Place) string {
	switch p.Kind {
	case PlaceLocal:
		if int(p.Local) >= len(f.Locals) {
			return "<invalid local>"
		}
		return "local %" + f.Locals[p.Local].Name
	case PlaceField:
		if p.Base == nil {
			return "<invalid place>"
		}
		return "field(" + printPlace(m, f, p.Base) + ", " + p.Field + ")"
	case PlaceDeref:
		return "deref " + valueName(f, p.Deref)
	}
	return "<invalid place>"
}

func printArgs(b *strings.Builder, f *Function, args []ValueId) {
	for i, a := range args {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(valueName(f, a))
	}
}

func printInstr(b *strings.Builder, m *Module, f *Function, in *Instr) {
	b.WriteString("  ")
	if in.Result != NoValue {
		b.WriteString(valueName(f, in.Result) + " = ")
	}
	b.WriteString(in.Op.String())
	switch in.Op {
	case OpLoad, OpBorrow, OpBorrowMut:
		b.WriteString(" " + printPlace(m, f, &in.Place))

	case OpStore:
		b.WriteString(" " + printPlace(m, f, &in.Place) + ", " + valueName(f, in.StoreVal))

	case OpAggregateConstruct:
		b.WriteString(" " + m.TypeString(in.AggType) + " { ")
		for i, af := range in.AggFields {
			if i > 0 {
				b.WriteString(", ")
			}
			if m.Types[in.AggType].Kind == TypeArray {
				b.WriteString(valueName(f, af.Value))
			} else {
				b.WriteString(af.Name + ": " + valueName(f, af.Value))
			}
		}
		b.WriteString(" }")

	case OpDomainCreate, OpDomainMark, OpDomainDestroy:
		b.WriteString(" " + valueName(f, in.Domain))

	case OpDomainReset:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + valueName(f, in.Mark))

	case OpAlloc, OpAllocChecked:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + m.TypeString(in.TypeOp) + ", " + valueName(f, in.Count))
		if in.Op == OpAllocChecked {
			printFailEdge(b, f, in)
		}

	case OpCopyToDomain:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + valueName(f, in.CopyVal))

	case OpCleanupScopeBegin:
		// no operands

	case OpCleanupPush:
		b.WriteString(" " + valueName(f, in.Scope) + ", @" + fnName(m, in.CleanupFn) + ", (")
		printArgs(b, f, in.CleanupArgs)
		b.WriteString(")")

	case OpCleanupDisarm:
		b.WriteString(" " + valueName(f, in.CleanupID))

	case OpCleanupScopeRun, OpCleanupScopeEnd:
		b.WriteString(" " + valueName(f, in.Scope))

	case OpIntAddChecked, OpIntSubChecked, OpIntMulChecked, OpIntDivChecked, OpIntShlChecked, OpIntShrChecked:
		b.WriteString(" " + valueName(f, in.A) + ", " + valueName(f, in.B))
		printFailEdge(b, f, in)

	case OpIntAddTry, OpIntSubTry, OpIntMulTry,
		OpIntAddSaturating, OpIntSubSaturating, OpIntMulSaturating,
		OpIntAddWrapping, OpIntSubWrapping, OpIntMulWrapping,
		OpFloatAdd, OpFloatSub, OpFloatMul, OpFloatDiv:
		b.WriteString(" " + valueName(f, in.A) + ", " + valueName(f, in.B))

	case OpSliceLen:
		b.WriteString(" " + valueName(f, in.Slice))

	case OpSliceIndexChecked:
		b.WriteString(" " + valueName(f, in.Slice) + ", " + valueName(f, in.Index))
		printFailEdge(b, f, in)

	case OpArrayIndexChecked:
		b.WriteString(" " + valueName(f, in.Array) + ", " + valueName(f, in.Index))
		printFailEdge(b, f, in)

	case OpSliceRangeChecked:
		b.WriteString(" " + valueName(f, in.Slice) + ", " + valueName(f, in.Lo) + ", " + valueName(f, in.Hi))
		printFailEdge(b, f, in)
	case OpVecNew:
		b.WriteString(" " + m.TypeString(in.TypeOp))
	case OpVecConstructChecked:
		b.WriteString(" " + valueName(f, in.Slice) + ", " + valueName(f, in.Lo) + ", " + valueName(f, in.Capacity))
		printFailEdge(b, f, in)
	case OpVecGrowChecked:
		b.WriteString(" " + valueName(f, in.Slice) + ", " + valueName(f, in.Domain) + ", " + valueName(f, in.Capacity))
		printFailEdge(b, f, in)
	case OpVecLen, OpVecCapacity, OpVecStorage, OpVecAsSlice, OpVecAsMutSlice:
		b.WriteString(" " + valueName(f, in.Slice))
	case OpArrayAsSlice:
		b.WriteString(" " + valueName(f, in.Array))

	case OpEnumPayloadChecked:
		b.WriteString(" " + valueName(f, in.EnumValue) + ", " + in.Variant)
		printFailEdge(b, f, in)

	case OpEnumConstruct:
		b.WriteString(" " + m.TypeString(in.TypeOp) + ", " + in.Variant)
		if in.Payload != NoValue {
			b.WriteString(", " + valueName(f, in.Payload))
		}

	case OpTableCreate:
		b.WriteString(" " + m.TypeString(in.TypeOp) + ", " + valueName(f, in.Domain))

	case OpTableInsert:
		b.WriteString(" " + valueName(f, in.Table) + ", " + valueName(f, in.TableVal))

	case OpTableInsertTry:
		b.WriteString(" " + valueName(f, in.Table) + ", " + valueName(f, in.TableVal))

	case OpTableLookup, OpTableLookupMut, OpTableRemove:
		b.WriteString(" " + valueName(f, in.Table) + ", " + valueName(f, in.ID))

	case OpTableViewEnd:
		b.WriteString(" " + valueName(f, in.View))

	case OpIntEq, OpIntNe, OpIntLt, OpIntLe, OpIntGt, OpIntGe,
		OpFloatEq, OpFloatNe, OpFloatLt, OpFloatLe, OpFloatGt, OpFloatGe:
		b.WriteString(" " + valueName(f, in.A) + ", " + valueName(f, in.B))

	case OpIntTrunc, OpIntZext, OpIntSext, OpFloatConvert, OpIntFromFloat, OpFloatFromInt,
		OpIntConvertChecked, OpIntConvertWrap:
		b.WriteString(" " + valueName(f, in.A) + ", " + m.TypeString(in.TypeOp))

	case OpCNumTry, OpCNumWrap, OpCNumCast:
		b.WriteString(" " + valueName(f, in.A) + ", " + m.TypeString(in.TypeOp))

	case OpCFieldGet:
		b.WriteString(" " + in.CField + "(" + valueName(f, in.A) + ")")

	case OpCFieldSet:
		b.WriteString(" " + in.CField + " " + printPlace(m, f, &in.Place) + ", " + valueName(f, in.A))

	case OpCStringMakeLit, OpCStringMake, OpCStringPtr, OpCStringRelease:
		b.WriteString(" " + valueName(f, in.A))

	case OpConstGet:
		b.WriteString(" @" + in.Const)

	case OpCall:
		b.WriteString(" @" + fnName(m, in.Callee) + "(")
		printArgs(b, f, in.Args)
		b.WriteString(")")

	case OpFFICallUnsafe:
		b.WriteString(" @" + importName(m, in.FFIImport) + "(")
		printArgs(b, f, in.Args)
		b.WriteString(")")
	case OpCBindingCall:
		b.WriteString(" @" + bindingFuncName(m, in.CBinding) + "(")
		printArgs(b, f, in.Args)
		b.WriteString(")")
	case OpCIsNull:
		b.WriteString(" " + valueName(f, in.A))
	case OpCallValue:
		b.WriteString(" " + valueName(f, in.A) + "(")
		printArgs(b, f, in.Args)
		b.WriteString(")")
	case OpStrEq:
		b.WriteString(" " + valueName(f, in.A) + ", " + valueName(f, in.B))
	case OpStrOrderLt:
		b.WriteString(" " + valueName(f, in.A) + ", " + valueName(f, in.B))
	case OpStrLen, OpStrToBytes:
		b.WriteString(" " + valueName(f, in.A))
	case OpStrByteChecked:
		b.WriteString(" " + valueName(f, in.A) + ", " + valueName(f, in.B))
		printFailEdge(b, f, in)
	case OpStrConcat:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + valueName(f, in.A) + ", " + valueName(f, in.B))
		printFailEdge(b, f, in)
	case OpStrSliceChecked:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + valueName(f, in.A) + ", " + valueName(f, in.Lo) + ", " + valueName(f, in.Hi))
		printFailEdge(b, f, in)
	case OpStrFromBytes:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + valueName(f, in.A))
		printFailEdge(b, f, in)
	case OpStrDisplay:
		b.WriteString(" " + valueName(f, in.Domain) + ", " + valueName(f, in.A))
		printFailEdge(b, f, in)
	case OpFnValue:
		b.WriteString(" @" + fnName(m, in.Callee))
		if in.A != NoValue {
			b.WriteString("(" + valueName(f, in.A) + ")")
		}
		if in.TypeOp == FnValueDomainMarker {
			b.WriteString(" domain")
		}
	}
	b.WriteString("\n")
}

func printTerm(b *strings.Builder, m *Module, f *Function, t *Terminator) {
	b.WriteString("  ")
	switch t.Kind {
	case TermJump:
		b.WriteString("jump ")
		printBlockRef(b, f, t.Target, t.Args)

	case TermBranch:
		b.WriteString("branch " + valueName(f, t.Cond) + ", ")
		printBlockRef(b, f, t.Then, t.ThenArgs)
		b.WriteString(", ")
		printBlockRef(b, f, t.Else, t.ElseArgs)

	case TermSwitch:
		b.WriteString("switch " + valueName(f, t.Value) + " {\n")
		for _, c := range t.Cases {
			b.WriteString("    ")
			if c.Variant == "" {
				b.WriteString("default")
			} else {
				b.WriteString(c.Variant)
				if c.Binding != NoValue {
					b.WriteString("(" + valueName(f, c.Binding) + ")")
				}
			}
			b.WriteString(" -> ")
			printBlockRef(b, f, c.Target, c.Args)
			b.WriteString("\n")
		}
		b.WriteString("  }")

	case TermReturn:
		b.WriteString("return")
		if t.Result != NoValue {
			b.WriteString(" " + valueName(f, t.Result))
		}

	case TermFail:
		b.WriteString("fail " + valueName(f, t.Result))

	case TermPanic:
		b.WriteString("panic")

	case TermUnreachable:
		b.WriteString("unreachable")
	}
	b.WriteString("\n")
}
