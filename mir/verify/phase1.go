package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase1Integrity checks declaration and ID integrity: format version,
// well-formed type table entries, unique names, in-range references, and
// consistent value definitions.
func phase1Integrity(m *mir.Module) []Error {
	var errs []Error
	if m.FormatVersion != 1 {
		errs = append(errs, Error{Msg: fmt.Sprintf("unsupported format version %d (expected 1)", m.FormatVersion)})
	}
	for i, t := range m.Types {
		id := mir.TypeId(i)
		if id < mir.NumPrimitiveTypes {
			if t.Kind != mir.TypePrimitive {
				errs = append(errs, Error{Loc: typeLoc(m, id), Msg: fmt.Sprintf("primitive slot holds kind %v", t.Kind)})
			}
			continue
		}
		if t.Name == "" {
			if t.Kind == mir.TypeAggregate || t.Kind == mir.TypeEnum {
				errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "aggregate and enum types must be named"})
			}
		} else if t.Kind != mir.TypeAggregate && t.Kind != mir.TypeEnum {
			errs = append(errs, Error{Loc: fmt.Sprintf("type @%s", t.Name), Msg: fmt.Sprintf("named type holds kind %v", t.Kind)})
		}
	}
	for i, t := range m.Types {
		if t.Name == "" {
			continue
		}
		for j := i + 1; j < len(m.Types); j++ {
			if m.Types[j].Name == t.Name {
				errs = append(errs, Error{Loc: fmt.Sprintf("type @%s", t.Name), Msg: "duplicate type name"})
				break
			}
		}
	}
	for i := 1; i < len(m.Imports); i++ {
		for j := 0; j < i; j++ {
			if m.Imports[j].Name == m.Imports[i].Name {
				errs = append(errs, Error{Loc: fmt.Sprintf("import @%s", m.Imports[i].Name), Msg: "duplicate import name"})
				break
			}
		}
	}
	for i := 1; i < len(m.Constants); i++ {
		for j := 0; j < i; j++ {
			if m.Constants[j].Name == m.Constants[i].Name {
				errs = append(errs, Error{Loc: fmt.Sprintf("const @%s", m.Constants[i].Name), Msg: "duplicate constant name"})
				break
			}
		}
	}
	for i, f := range m.Functions {
		if f == nil {
			errs = append(errs, Error{Loc: fmt.Sprintf("function slot %d", i), Msg: "nil function"})
			continue
		}
		for j := i + 1; j < len(m.Functions); j++ {
			if m.Functions[j] != nil && m.Functions[j].Name == f.Name {
				errs = append(errs, Error{Loc: locFunc(f), Msg: "duplicate function name"})
				break
			}
		}
		errs = append(errs, checkFunction(m, f)...)
	}
	return errs
}

func typeLoc(m *mir.Module, id mir.TypeId) string {
	if int(id) < len(m.Types) && m.Types[id].Name != "" {
		return "type @" + m.Types[id].Name
	}
	return fmt.Sprintf("type slot %d", id)
}

func checkFunction(m *mir.Module, f *mir.Function) []Error {
	var errs []Error
	for i := 1; i < len(f.Params); i++ {
		for j := 0; j < i; j++ {
			if f.Params[j].Name == f.Params[i].Name {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("duplicate parameter name %%%s", f.Params[i].Name)})
				break
			}
		}
	}
	for i := 1; i < len(f.Locals); i++ {
		for j := 0; j < i; j++ {
			if f.Locals[j].Name == f.Locals[i].Name {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("duplicate local name %%%s", f.Locals[i].Name)})
				break
			}
		}
	}
	for i, b := range f.Blocks {
		if b == nil {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("nil block at slot %d", i)})
			continue
		}
		for j := i + 1; j < len(f.Blocks); j++ {
			if f.Blocks[j] != nil && f.Blocks[j].Name == b.Name {
				errs = append(errs, Error{Loc: locBlock(f, b), Msg: "duplicate block name"})
				break
			}
		}
		for j := 1; j < len(b.Params); j++ {
			for k := 0; k < j; k++ {
				if b.Params[k].Name == b.Params[j].Name {
					errs = append(errs, Error{Loc: locBlock(f, b), Msg: fmt.Sprintf("duplicate block parameter name %%%s", b.Params[j].Name)})
					break
				}
			}
		}
	}
	if len(f.Blocks) == 0 {
		errs = append(errs, Error{Loc: locFunc(f), Msg: "function has no blocks"})
		return errs
	}
	// Value name uniqueness and definition integrity.
	seen := make(map[string]bool, len(f.Values))
	for vi, v := range f.Values {
		if seen[v.Name] {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("duplicate value name %%%s", v.Name)})
		}
		seen[v.Name] = true
		errs = append(errs, checkValueDef(m, f, mir.ValueId(vi), &v)...)
	}
	for bi, b := range f.Blocks {
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			errs = append(errs, checkInstr(m, f, b, bi, ii, in)...)
		}
		errs = append(errs, checkTerm(m, f, b, bi)...)
	}
	return errs
}

func checkValueDef(m *mir.Module, f *mir.Function, id mir.ValueId, v *mir.Value) []Error {
	var errs []Error
	loc := func() string { return locFunc(f) + ": value " + valueName(f, id) }
	switch v.Def.Kind {
	case mir.ValueDefFuncParam:
		return nil
	case mir.ValueDefBlockParam:
		if int(v.Def.Block) >= len(f.Blocks) {
			return []Error{{Loc: loc(), Msg: "definition block out of range"}}
		}
		b := f.Blocks[v.Def.Block]
		if v.Def.Param < 0 || v.Def.Param >= len(b.Params) {
			return []Error{{Loc: loc(), Msg: "block parameter index out of range"}}
		}
		if b.Params[v.Def.Param].Name != v.Name {
			errs = append(errs, Error{Loc: loc(), Msg: "value name does not match its block parameter"})
		}
	case mir.ValueDefInstr:
		if int(v.Def.Block) >= len(f.Blocks) {
			return []Error{{Loc: loc(), Msg: "definition block out of range"}}
		}
		b := f.Blocks[v.Def.Block]
		if v.Def.Instr < 0 || v.Def.Instr >= len(b.Instrs) {
			return []Error{{Loc: loc(), Msg: "instruction index out of range"}}
		}
		if b.Instrs[v.Def.Instr].Result != id {
			errs = append(errs, Error{Loc: loc(), Msg: "instruction result does not reference this value"})
		}
	case mir.ValueDefSwitchCase:
		if int(v.Def.Block) >= len(f.Blocks) {
			return []Error{{Loc: loc(), Msg: "definition block out of range"}}
		}
		b := f.Blocks[v.Def.Block]
		if v.Def.Case < 0 || v.Def.Case >= len(b.Term.Cases) {
			return []Error{{Loc: loc(), Msg: "switch case index out of range"}}
		}
		if b.Term.Cases[v.Def.Case].Binding != id {
			errs = append(errs, Error{Loc: loc(), Msg: "switch case binding does not reference this value"})
		}
	default:
		errs = append(errs, Error{Loc: loc(), Msg: fmt.Sprintf("unknown value definition kind %d", v.Def.Kind)})
	}
	return errs
}

func checkInstr(m *mir.Module, f *mir.Function, b *mir.Block, bi, ii int, in *mir.Instr) []Error {
	var errs []Error
	loc := locInstr(f, b, ii, in)
	if in.Op.ProducesResult() {
		if in.Result == mir.NoValue {
			if !droppableResult(m, in) {
				errs = append(errs, Error{Loc: loc, Msg: "operation produces a value but binds no result"})
			}
		}
	} else if in.Result != mir.NoValue {
		errs = append(errs, Error{Loc: loc, Msg: "operation produces no value but binds a result"})
	}
	if in.Op.HasFailEdge() {
		if in.FailTarget == mir.NoBlock {
			errs = append(errs, Error{Loc: loc, Msg: "checked operation requires an 'else' failure edge"})
		}
	} else if in.FailTarget != mir.NoBlock {
		errs = append(errs, Error{Loc: loc, Msg: "operation has an 'else' failure edge but is not checked"})
	}
	// Value operand ranges: each operation has a fixed operand shape.
	for _, v := range instrValueOperands(in) {
		if v != mir.NoValue && int(v) >= len(f.Values) {
			errs = append(errs, Error{Loc: loc, Msg: "operand out of range"})
		}
	}
	if in.FailTarget != mir.NoBlock {
		for _, v := range in.FailArgs {
			if v != mir.NoValue && int(v) >= len(f.Values) {
				errs = append(errs, Error{Loc: loc, Msg: "failure argument out of range"})
			}
		}
	}
	if in.Op == mir.OpLoad || in.Op == mir.OpStore {
		if in.Place.Kind == mir.PlaceLocal && int(in.Place.Local) >= len(f.Locals) {
			errs = append(errs, Error{Loc: loc, Msg: "place local out of range"})
		}
		if in.Place.Kind == mir.PlaceDeref && int(in.Place.Deref) >= len(f.Values) {
			errs = append(errs, Error{Loc: loc, Msg: "place deref operand out of range"})
		}
		if in.Place.Kind == mir.PlaceField && in.Place.Base == nil {
			errs = append(errs, Error{Loc: loc, Msg: "field place has no base"})
		}
	}
	if in.Op == mir.OpCall && int(in.Callee) >= len(m.Functions) {
		errs = append(errs, Error{Loc: loc, Msg: "callee out of range"})
	}
	if in.Op == mir.OpFFICallUnsafe && int(in.FFIImport) >= len(m.Imports) {
		errs = append(errs, Error{Loc: loc, Msg: "import out of range"})
	}
	if in.Op == mir.OpCleanupPush && int(in.CleanupFn) >= len(m.Functions) {
		errs = append(errs, Error{Loc: loc, Msg: "cleanup function out of range"})
	}
	if in.Op == mir.OpConstGet && !constExists(m, in.Const) {
		errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("unknown constant @%s", in.Const)})
	}
	if in.Op == mir.OpAggregateConstruct && !m.ValidType(in.AggType) {
		errs = append(errs, Error{Loc: loc, Msg: "aggregate type out of range"})
	}
	for _, op := range []mir.OpKind{mir.OpAlloc, mir.OpTableCreate, mir.OpEnumConstruct,
		mir.OpIntTrunc, mir.OpIntZext, mir.OpIntSext, mir.OpFloatConvert,
		mir.OpIntFromFloat, mir.OpFloatFromInt} {
		if in.Op == op && !m.ValidType(in.TypeOp) {
			errs = append(errs, Error{Loc: loc, Msg: "type operand out of range"})
		}
	}
	return errs
}

// instrValueOperands returns the value operands of an instruction according to
// its operation shape. Non-producing and zero-valued fields are ignored.
func instrValueOperands(in *mir.Instr) []mir.ValueId {
	var out []mir.ValueId
	add := func(v mir.ValueId) {
		if v != mir.NoValue {
			out = append(out, v)
		}
	}
	switch in.Op {
	case mir.OpLoad:
		if in.Place.Kind == mir.PlaceDeref {
			add(in.Place.Deref)
		}
	case mir.OpStore:
		if in.Place.Kind == mir.PlaceDeref {
			add(in.Place.Deref)
		}
		add(in.StoreVal)
	case mir.OpAggregateConstruct:
		for _, af := range in.AggFields {
			add(af.Value)
		}
	case mir.OpDomainCreate, mir.OpDomainMark, mir.OpDomainDestroy:
		add(in.Domain)
	case mir.OpDomainReset:
		add(in.Domain)
		add(in.Mark)
	case mir.OpAlloc:
		add(in.Domain)
		add(in.Count)
	case mir.OpCopyToDomain:
		add(in.Domain)
		add(in.CopyVal)
	case mir.OpCleanupPush:
		add(in.Scope)
		for _, v := range in.CleanupArgs {
			add(v)
		}
	case mir.OpCleanupDisarm:
		add(in.CleanupID)
	case mir.OpCleanupScopeRun, mir.OpCleanupScopeEnd:
		add(in.Scope)
	case mir.OpIntAddChecked, mir.OpIntSubChecked, mir.OpIntMulChecked,
		mir.OpIntDivChecked, mir.OpIntShiftChecked,
		mir.OpIntEq, mir.OpIntNe, mir.OpIntLt, mir.OpIntLe, mir.OpIntGt, mir.OpIntGe,
		mir.OpFloatEq, mir.OpFloatNe, mir.OpFloatLt, mir.OpFloatLe, mir.OpFloatGt, mir.OpFloatGe:
		add(in.A)
		add(in.B)
	case mir.OpSliceLen:
		add(in.Slice)
	case mir.OpSliceIndexChecked:
		add(in.Slice)
		add(in.Index)
	case mir.OpSliceRangeChecked:
		add(in.Slice)
		add(in.Lo)
		add(in.Hi)
	case mir.OpEnumPayloadChecked:
		add(in.EnumValue)
	case mir.OpEnumConstruct:
		add(in.Payload)
	case mir.OpTableCreate:
		add(in.Domain)
	case mir.OpTableInsert:
		add(in.Table)
		add(in.TableVal)
	case mir.OpTableLookup, mir.OpTableLookupMut, mir.OpTableRemove:
		add(in.Table)
		add(in.ID)
	case mir.OpTableViewEnd:
		add(in.View)
	case mir.OpIntTrunc, mir.OpIntZext, mir.OpIntSext, mir.OpFloatConvert,
		mir.OpIntFromFloat, mir.OpFloatFromInt:
		add(in.A)
	case mir.OpCall, mir.OpFFICallUnsafe:
		for _, v := range in.Args {
			add(v)
		}
	}
	return out
}

// droppableResult reports whether a producing but unbound instruction is
// allowed: a call or FFI call whose callee or import result type is unit.
func droppableResult(m *mir.Module, in *mir.Instr) bool {
	switch in.Op {
	case mir.OpCall:
		return int(in.Callee) < len(m.Functions) && m.Functions[in.Callee].Result == mir.TypeUnit
	case mir.OpFFICallUnsafe:
		return int(in.FFIImport) < len(m.Imports) && m.Imports[in.FFIImport].Sig.Result == mir.TypeUnit
	}
	return false
}

func constExists(m *mir.Module, name string) bool {
	_, ok := m.ConstDecl(name)
	return ok
}

func checkTerm(m *mir.Module, f *mir.Function, b *mir.Block, bi int) []Error {
	var errs []Error
	loc := locTerm(f, b)
	checkVal := func(v mir.ValueId, what string) {
		if v != mir.NoValue && int(v) >= len(f.Values) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s out of range", what)})
		}
	}
	switch b.Term.Kind {
	case mir.TermJump:
		for _, v := range b.Term.Args {
			checkVal(v, "jump argument")
		}
	case mir.TermBranch:
		checkVal(b.Term.Cond, "branch condition")
		for _, v := range b.Term.ThenArgs {
			checkVal(v, "branch argument")
		}
		for _, v := range b.Term.ElseArgs {
			checkVal(v, "branch argument")
		}
	case mir.TermSwitch:
		checkVal(b.Term.Value, "switch operand")
		for _, c := range b.Term.Cases {
			for _, v := range c.Args {
				checkVal(v, "switch argument")
			}
		}
	case mir.TermFail:
		checkVal(b.Term.Result, "fail operand")
	case mir.TermReturn:
		checkVal(b.Term.Result, "return operand")
	}
	return errs
}
