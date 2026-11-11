package verify

import (
	"fmt"

	"github.com/4fuu/alder/mir"
)

// phase1Integrity checks declaration and ID integrity: format version,
// well-formed type table entries, unique names, in-range references, and
// consistent value definitions.
func phase1Integrity(m *mir.Module) []Error {
	var errs []Error
	if m.FormatVersion < mir.LegacyFormatVersion || m.FormatVersion > mir.CurrentFormatVersion {
		errs = append(errs, Error{Msg: fmt.Sprintf("unsupported format version %d (supported: 1, 2, 3, 4, 5)", m.FormatVersion)})
	}
	if len(m.Types) < int(mir.NumPrimitiveTypes) {
		errs = append(errs, Error{Msg: fmt.Sprintf("type table has %d entries; expected at least %d canonical primitive slots", len(m.Types), mir.NumPrimitiveTypes)})
	}
	for i, t := range m.Types {
		id := mir.TypeId(i)
		if id < mir.NumPrimitiveTypes {
			if t.Kind != mir.TypePrimitive {
				errs = append(errs, Error{Loc: typeLoc(m, id), Msg: fmt.Sprintf("primitive slot holds kind %v", t.Kind)})
			}
			if t.Name != "" || len(t.Fields) != 0 || len(t.Variants) != 0 || t.Elem != mir.TypeUnit || t.Length != 0 ||
				t.OK != mir.TypeUnit || t.Err != mir.TypeUnit || len(t.Sig.Params) != 0 || t.Sig.Result != mir.TypeUnit {
				errs = append(errs, Error{Loc: typeLoc(m, id), Msg: "primitive slot contains non-canonical type data"})
			}
			continue
		}
		if t.Kind > mir.TypeCNamed {
			errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: fmt.Sprintf("unknown type kind %d", t.Kind)})
			continue
		}
		if t.Kind == mir.TypePrimitive {
			errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "primitive type appears outside the canonical primitive slots"})
			continue
		}
		if t.Kind >= mir.TypeCRaw && m.FormatVersion < mir.BindingFormatVersion {
			errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "C binding types require MIR format version 6"})
		}
		if t.Kind == mir.TypeVec && m.FormatVersion < mir.VecFormatVersion {
			errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "vec type requires MIR format version 4"})
		}
		if t.Kind == mir.TypeFunction && t.Sig.Env != mir.NoType && m.FormatVersion < mir.ClosureFormatVersion {
			errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "function environment requires MIR format version 5"})
		}
		if t.Name == "" {
			if t.Kind == mir.TypeAggregate || t.Kind == mir.TypeEnum {
				errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "aggregate and enum types must be named"})
			} else if t.Kind == mir.TypeCNamed {
				errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: "C binding types must be named"})
			}
		} else if t.Kind != mir.TypeAggregate && t.Kind != mir.TypeEnum && t.Kind != mir.TypeCNamed {
			errs = append(errs, Error{Loc: fmt.Sprintf("type @%s", t.Name), Msg: fmt.Sprintf("named type holds kind %v", t.Kind)})
		} else if !validMIRName(t.Name, true) {
			errs = append(errs, Error{Loc: fmt.Sprintf("type slot %d", i), Msg: fmt.Sprintf("invalid type name %q", t.Name)})
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
	for i := range m.Imports {
		if !validMIRName(m.Imports[i].Name, true) {
			errs = append(errs, Error{Loc: fmt.Sprintf("import slot %d", i), Msg: fmt.Sprintf("invalid import name %q", m.Imports[i].Name)})
		}
	}
	errs = append(errs, checkBindings(m)...)
	for i := 1; i < len(m.Constants); i++ {
		for j := 0; j < i; j++ {
			if m.Constants[j].Name == m.Constants[i].Name {
				errs = append(errs, Error{Loc: fmt.Sprintf("const @%s", m.Constants[i].Name), Msg: "duplicate constant name"})
				break
			}
		}
	}
	for i := range m.Constants {
		if !validMIRName(m.Constants[i].Name, true) {
			errs = append(errs, Error{Loc: fmt.Sprintf("constant slot %d", i), Msg: fmt.Sprintf("invalid constant name %q", m.Constants[i].Name)})
		}
	}
	for i, f := range m.Functions {
		if f == nil {
			errs = append(errs, Error{Loc: fmt.Sprintf("function slot %d", i), Msg: "nil function"})
			continue
		}
		if !validMIRName(f.Name, true) {
			errs = append(errs, Error{Loc: fmt.Sprintf("function slot %d", i), Msg: fmt.Sprintf("invalid function name %q", f.Name)})
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

func validMIRName(name string, dotted bool) bool {
	if name == "" {
		return false
	}
	start := true
	for i := 0; i < len(name); i++ {
		c := name[i]
		if dotted && c == '.' {
			if start || i == len(name)-1 {
				return false
			}
			start = true
			continue
		}
		letter := c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
		if start {
			if !letter {
				return false
			}
			start = false
			continue
		}
		if !letter && !(c >= '0' && c <= '9') {
			return false
		}
	}
	return !start
}

func checkFunction(m *mir.Module, f *mir.Function) []Error {
	var errs []Error
	if len(f.Values) < len(f.Params) {
		errs = append(errs, Error{Loc: locFunc(f), Msg: "function parameters are missing leading values"})
	}
	for i, p := range f.Params {
		if !validMIRName(p.Name, false) {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("invalid parameter name %q", p.Name)})
		}
		if i >= len(f.Values) {
			break
		}
		v := &f.Values[i]
		if v.Def.Kind != mir.ValueDefFuncParam || v.Name != p.Name || v.Type != p.Type {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("parameter %%%s does not match leading value %d", p.Name, i)})
		}
	}
	for i := len(f.Params); i < len(f.Values); i++ {
		if f.Values[i].Def.Kind == mir.ValueDefFuncParam {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("value %%%s is a forged function parameter", f.Values[i].Name)})
		}
	}
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
	for _, l := range f.Locals {
		if !validMIRName(l.Name, false) {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("invalid local name %q", l.Name)})
		}
	}
	for i, b := range f.Blocks {
		if b == nil {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("nil block at slot %d", i)})
			continue
		}
		if !validMIRName(b.Name, true) || b.Name == "else" {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("invalid or reserved block name %q", b.Name)})
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
		for _, p := range b.Params {
			if !validMIRName(p.Name, false) {
				errs = append(errs, Error{Loc: locBlock(f, b), Msg: fmt.Sprintf("invalid block parameter name %q", p.Name)})
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
		if !validMIRName(v.Name, false) {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("invalid value name %q", v.Name)})
		}
		if seen[v.Name] {
			errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("duplicate value name %%%s", v.Name)})
		}
		seen[v.Name] = true
		errs = append(errs, checkValueDef(m, f, mir.ValueId(vi), &v)...)
	}
	// Every defining site must point back to exactly one value. This catches
	// missing values as well as forged duplicate definitions.
	counts := make(map[string]int)
	for _, v := range f.Values {
		switch v.Def.Kind {
		case mir.ValueDefFuncParam:
			// Leading parameter correspondence was checked above.
		case mir.ValueDefBlockParam:
			counts[fmt.Sprintf("b:%d:%d", v.Def.Block, v.Def.Param)]++
		case mir.ValueDefInstr:
			counts[fmt.Sprintf("i:%d:%d", v.Def.Block, v.Def.Instr)]++
		case mir.ValueDefSwitchCase:
			counts[fmt.Sprintf("s:%d:%d", v.Def.Block, v.Def.Case)]++
		}
	}
	for bi, b := range f.Blocks {
		if b == nil {
			continue
		}
		for i := range b.Params {
			if counts[fmt.Sprintf("b:%d:%d", bi, i)] != 1 {
				errs = append(errs, Error{Loc: locBlock(f, b), Msg: fmt.Sprintf("block parameter %d must have exactly one value", i)})
			}
		}
		for i, in := range b.Instrs {
			if in.Result != mir.NoValue && counts[fmt.Sprintf("i:%d:%d", bi, i)] != 1 {
				errs = append(errs, Error{Loc: locInstr(f, b, i, &b.Instrs[i]), Msg: "instruction result must have exactly one value"})
			}
		}
		for i, c := range b.Term.Cases {
			if c.Binding != mir.NoValue && counts[fmt.Sprintf("s:%d:%d", bi, i)] != 1 {
				errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("switch binding %d must have exactly one value", i)})
			}
		}
	}
	for bi, b := range f.Blocks {
		if b == nil {
			continue
		}
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
		if b == nil {
			return []Error{{Loc: loc(), Msg: "definition block is nil"}}
		}
		if v.Def.Param < 0 || v.Def.Param >= len(b.Params) {
			return []Error{{Loc: loc(), Msg: "block parameter index out of range"}}
		}
		if b.Params[v.Def.Param].Name != v.Name {
			errs = append(errs, Error{Loc: loc(), Msg: "value name does not match its block parameter"})
		}
		if b.Params[v.Def.Param].Type != v.Type {
			errs = append(errs, Error{Loc: loc(), Msg: "value type does not match its block parameter"})
		}
	case mir.ValueDefInstr:
		if int(v.Def.Block) >= len(f.Blocks) {
			return []Error{{Loc: loc(), Msg: "definition block out of range"}}
		}
		b := f.Blocks[v.Def.Block]
		if b == nil {
			return []Error{{Loc: loc(), Msg: "definition block is nil"}}
		}
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
		if b == nil {
			return []Error{{Loc: loc(), Msg: "definition block is nil"}}
		}
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
	if in.Op > mir.OpCFieldSet {
		return []Error{{Loc: loc, Msg: fmt.Sprintf("unknown operation kind %d", in.Op)}}
	}
	// The fn.value domain marker is legal only on fn.value; no other op
	// reads a type in the boolean type slot, so the value identifies the
	// marker unambiguously.
	if in.TypeOp == mir.FnValueDomainMarker && in.Op != mir.OpFnValue {
		errs = append(errs, Error{Loc: loc, Msg: "fn.value domain marker on a non-fn.value instruction"})
	}
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
	if (in.Op == mir.OpCallValue || in.Op == mir.OpStrEq || in.Op == mir.OpFnValue) && m.FormatVersion < mir.ClosureFormatVersion {
		errs = append(errs, Error{Loc: loc, Msg: in.Op.String() + " requires MIR format version 5"})
	}
	// Value operand ranges: each operation has a fixed operand shape.
	errs = append(errs, checkRequiredInstrOperands(m, in, loc)...)
	for _, v := range instrValueOperands(in) {
		if v != mir.NoValue && int(v) >= len(f.Values) {
			errs = append(errs, Error{Loc: loc, Msg: "operand out of range"})
		}
	}
	if in.FailTarget != mir.NoBlock {
		for _, v := range in.FailArgs {
			if v == mir.NoValue {
				errs = append(errs, Error{Loc: loc, Msg: "failure argument is missing"})
			} else if int(v) >= len(f.Values) {
				errs = append(errs, Error{Loc: loc, Msg: "failure argument out of range"})
			}
		}
	}
	if in.Op == mir.OpLoad || in.Op == mir.OpStore || in.Op == mir.OpBorrow || in.Op == mir.OpBorrowMut || in.Op == mir.OpCFieldSet {
		errs = append(errs, checkPlaceIntegrity(f, &in.Place, loc)...)
	}
	if in.Op == mir.OpCall && (int(in.Callee) >= len(m.Functions) || m.Functions[in.Callee] == nil) {
		errs = append(errs, Error{Loc: loc, Msg: "callee is nil or out of range"})
	}
	if in.Op == mir.OpFFICallUnsafe && int(in.FFIImport) >= len(m.Imports) {
		errs = append(errs, Error{Loc: loc, Msg: "import out of range"})
	}
	if in.Op == mir.OpCBindingCall && (in.CBinding < 0 || in.CBinding >= m.BindingFuncCount()) {
		errs = append(errs, Error{Loc: loc, Msg: "binding function out of range"})
	}
	if in.Op == mir.OpCBindingCall && m.FormatVersion < mir.BindingFormatVersion {
		errs = append(errs, Error{Loc: loc, Msg: "c.call.unsafe requires MIR format version 6"})
	}
	if in.Op == mir.OpCIsNull && m.FormatVersion < mir.BindingFormatVersion {
		errs = append(errs, Error{Loc: loc, Msg: "c.is_null requires MIR format version 6"})
	}
	if in.Op == mir.OpCleanupPush && (int(in.CleanupFn) >= len(m.Functions) || m.Functions[in.CleanupFn] == nil) {
		errs = append(errs, Error{Loc: loc, Msg: "cleanup function is nil or out of range"})
	}
	if in.Op == mir.OpConstGet && !constExists(m, in.Const) {
		errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("unknown constant @%s", in.Const)})
	}
	if in.Op == mir.OpAggregateConstruct && !m.ValidType(in.AggType) {
		errs = append(errs, Error{Loc: loc, Msg: "aggregate type out of range"})
	}
	if in.Op == mir.OpAllocChecked && m.FormatVersion < mir.AllocCheckedFormatVersion {
		errs = append(errs, Error{Loc: loc, Msg: "alloc.checked requires MIR format version 3"})
	}
	for _, op := range []mir.OpKind{mir.OpAlloc, mir.OpAllocChecked, mir.OpTableCreate, mir.OpEnumConstruct,
		mir.OpVecNew,
		mir.OpIntTrunc, mir.OpIntZext, mir.OpIntSext, mir.OpFloatConvert,
		mir.OpIntFromFloat, mir.OpFloatFromInt, mir.OpIntConvertChecked, mir.OpIntConvertWrap,
		mir.OpCNumTry, mir.OpCNumWrap, mir.OpCNumCast} {
		if in.Op == op && !m.ValidType(in.TypeOp) {
			errs = append(errs, Error{Loc: loc, Msg: "type operand out of range"})
		}
	}
	if (in.Op == mir.OpCFieldGet || in.Op == mir.OpCFieldSet) && in.CField == "" {
		errs = append(errs, Error{Loc: loc, Msg: "c.field operation needs a record field name"})
	}
	return errs
}

func checkRequiredInstrOperands(m *mir.Module, in *mir.Instr, loc string) []Error {
	var errs []Error
	require := func(v mir.ValueId, what string) {
		if v == mir.NoValue {
			errs = append(errs, Error{Loc: loc, Msg: what + " is missing"})
		}
	}
	requireAll := func(values []mir.ValueId, what string) {
		for i, v := range values {
			if v == mir.NoValue {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s %d is missing", what, i)})
			}
		}
	}
	switch in.Op {
	case mir.OpStore:
		require(in.StoreVal, "store value")
	case mir.OpCallValue:
		require(in.A, "function operand")
		requireAll(in.Args, "call.value argument")
	case mir.OpStrEq:
		require(in.A, "left operand")
		require(in.B, "right operand")
	case mir.OpStrOrderLt:
		require(in.A, "left operand")
		require(in.B, "right operand")
	case mir.OpStrLen, mir.OpStrToBytes:
		require(in.A, "byte-sequence operand")
	case mir.OpStrByteChecked:
		require(in.A, "byte-sequence operand")
		require(in.B, "index operand")
	case mir.OpStrConcat:
		require(in.Domain, "domain operand")
		require(in.A, "left operand")
		require(in.B, "right operand")
	case mir.OpStrSliceChecked:
		require(in.Domain, "domain operand")
		require(in.A, "byte-sequence operand")
		require(in.Lo, "low operand")
		require(in.Hi, "high operand")
	case mir.OpStrFromBytes:
		require(in.Domain, "domain operand")
		require(in.A, "bytes operand")
	case mir.OpFnValue:
		if int(in.Callee) >= len(m.Functions) || m.Functions[in.Callee] == nil {
			errs = append(errs, Error{Loc: loc, Msg: "fn.value target is not a function"})
		}
		// The domain marker is legal only on fn.value, and it requires the
		// environment operand that carries the domain. No other op reads a
		// type in the boolean type slot, so the value identifies the marker
		// unambiguously.
		if in.TypeOp == mir.FnValueDomainMarker && in.A == mir.NoValue {
			errs = append(errs, Error{Loc: loc, Msg: "fn.value domain marker requires an environment operand"})
		}
	case mir.OpAggregateConstruct:
		for i, field := range in.AggFields {
			require(field.Value, fmt.Sprintf("aggregate field %d value", i))
		}
	case mir.OpDomainCreate, mir.OpDomainMark, mir.OpDomainDestroy, mir.OpTableCreate:
		require(in.Domain, "domain operand")
	case mir.OpDomainReset:
		require(in.Domain, "domain operand")
		require(in.Mark, "mark operand")
	case mir.OpAlloc, mir.OpAllocChecked:
		require(in.Domain, "domain operand")
		require(in.Count, "count operand")
	case mir.OpCopyToDomain:
		require(in.Domain, "domain operand")
		require(in.CopyVal, "copy value")
	case mir.OpCleanupPush:
		require(in.Scope, "scope operand")
		requireAll(in.CleanupArgs, "cleanup argument")
	case mir.OpCleanupDisarm:
		require(in.CleanupID, "cleanup id operand")
	case mir.OpCleanupScopeRun, mir.OpCleanupScopeEnd:
		require(in.Scope, "scope operand")
	case mir.OpIntAddChecked, mir.OpIntSubChecked, mir.OpIntMulChecked,
		mir.OpIntDivChecked, mir.OpIntShlChecked, mir.OpIntShrChecked,
		mir.OpIntAddTry, mir.OpIntSubTry, mir.OpIntMulTry,
		mir.OpIntAddSaturating, mir.OpIntSubSaturating, mir.OpIntMulSaturating,
		mir.OpIntAddWrapping, mir.OpIntSubWrapping, mir.OpIntMulWrapping,
		mir.OpIntEq, mir.OpIntNe, mir.OpIntLt, mir.OpIntLe, mir.OpIntGt, mir.OpIntGe,
		mir.OpFloatEq, mir.OpFloatNe, mir.OpFloatLt, mir.OpFloatLe, mir.OpFloatGt, mir.OpFloatGe,
		mir.OpFloatAdd, mir.OpFloatSub, mir.OpFloatMul, mir.OpFloatDiv:
		require(in.A, "left operand")
		require(in.B, "right operand")
	case mir.OpSliceLen:
		require(in.Slice, "slice operand")
	case mir.OpSliceIndexChecked:
		require(in.Slice, "slice operand")
		require(in.Index, "index operand")
	case mir.OpArrayIndexChecked:
		require(in.Array, "array operand")
		require(in.Index, "index operand")
	case mir.OpSliceRangeChecked:
		require(in.Slice, "slice operand")
		require(in.Lo, "low operand")
		require(in.Hi, "high operand")
	case mir.OpVecConstructChecked:
		require(in.Slice, "storage operand")
		require(in.Lo, "length operand")
		require(in.Capacity, "capacity operand")
	case mir.OpVecGrowChecked:
		require(in.Slice, "vec operand")
		require(in.Domain, "domain operand")
		require(in.Capacity, "capacity operand")
	case mir.OpVecLen, mir.OpVecCapacity, mir.OpVecStorage, mir.OpVecAsSlice, mir.OpVecAsMutSlice:
		require(in.Slice, "vec operand")
	case mir.OpArrayAsSlice:
		require(in.Array, "array operand")
	case mir.OpEnumPayloadChecked:
		require(in.EnumValue, "enum operand")
	case mir.OpTableInsert:
		require(in.Table, "table operand")
		require(in.TableVal, "insert value")
	case mir.OpTableInsertTry:
		require(in.Table, "table operand")
		require(in.TableVal, "insert value")
	case mir.OpTableLookup, mir.OpTableLookupMut, mir.OpTableRemove:
		require(in.Table, "table operand")
		require(in.ID, "id operand")
	case mir.OpTableViewEnd:
		require(in.View, "view operand")
	case mir.OpIntTrunc, mir.OpIntZext, mir.OpIntSext, mir.OpFloatConvert,
		mir.OpIntFromFloat, mir.OpFloatFromInt, mir.OpIntConvertChecked, mir.OpIntConvertWrap,
		mir.OpCNumTry, mir.OpCNumWrap, mir.OpCNumCast:
		require(in.A, "conversion operand")
	case mir.OpCall, mir.OpFFICallUnsafe, mir.OpCBindingCall:
		requireAll(in.Args, "call argument")
	case mir.OpCIsNull:
		require(in.A, "c.is_null operand")
	case mir.OpCFieldGet:
		require(in.A, "c.field.get record operand")
	case mir.OpCFieldSet:
		require(in.A, "c.field.set value operand")
	}
	return errs
}

func checkPlaceIntegrity(f *mir.Function, p *mir.Place, loc string) []Error {
	seen := make(map[*mir.Place]bool)
	for {
		if p == nil {
			return []Error{{Loc: loc, Msg: "field place has no base"}}
		}
		if seen[p] {
			return []Error{{Loc: loc, Msg: "cyclic place"}}
		}
		seen[p] = true
		switch p.Kind {
		case mir.PlaceLocal:
			if int(p.Local) >= len(f.Locals) {
				return []Error{{Loc: loc, Msg: "place local out of range"}}
			}
			return nil
		case mir.PlaceField:
			p = p.Base
		case mir.PlaceDeref:
			if int(p.Deref) >= len(f.Values) {
				return []Error{{Loc: loc, Msg: "place deref operand out of range"}}
			}
			return nil
		default:
			return []Error{{Loc: loc, Msg: fmt.Sprintf("unknown place kind %d", p.Kind)}}
		}
	}
}

// OperandValues returns the value operands of an instruction in a stable
// order, according to its operation shape. It is the shared view of operand
// presence used by the verifier and the C backend.
func OperandValues(in *mir.Instr) []mir.ValueId {
	return instrValueOperands(in)
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
	case mir.OpLoad, mir.OpBorrow, mir.OpBorrowMut:
		if in.Place.Kind == mir.PlaceDeref {
			add(in.Place.Deref)
		}
	case mir.OpStore:
		if in.Place.Kind == mir.PlaceDeref {
			add(in.Place.Deref)
		}
		add(in.StoreVal)
	case mir.OpCFieldSet:
		if in.Place.Kind == mir.PlaceDeref {
			add(in.Place.Deref)
		}
		add(in.A)
	case mir.OpAggregateConstruct:
		for _, af := range in.AggFields {
			add(af.Value)
		}
	case mir.OpDomainCreate, mir.OpDomainMark, mir.OpDomainDestroy:
		add(in.Domain)
	case mir.OpDomainReset:
		add(in.Domain)
		add(in.Mark)
	case mir.OpAlloc, mir.OpAllocChecked:
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
		mir.OpIntDivChecked, mir.OpIntShlChecked, mir.OpIntShrChecked,
		mir.OpIntAddTry, mir.OpIntSubTry, mir.OpIntMulTry,
		mir.OpIntAddSaturating, mir.OpIntSubSaturating, mir.OpIntMulSaturating,
		mir.OpIntAddWrapping, mir.OpIntSubWrapping, mir.OpIntMulWrapping,
		mir.OpIntEq, mir.OpIntNe, mir.OpIntLt, mir.OpIntLe, mir.OpIntGt, mir.OpIntGe,
		mir.OpFloatEq, mir.OpFloatNe, mir.OpFloatLt, mir.OpFloatLe, mir.OpFloatGt, mir.OpFloatGe,
		mir.OpFloatAdd, mir.OpFloatSub, mir.OpFloatMul, mir.OpFloatDiv:
		add(in.A)
		add(in.B)
	case mir.OpSliceLen:
		add(in.Slice)
	case mir.OpSliceIndexChecked:
		add(in.Slice)
		add(in.Index)
	case mir.OpArrayIndexChecked:
		add(in.Array)
		add(in.Index)
	case mir.OpSliceRangeChecked:
		add(in.Slice)
		add(in.Lo)
		add(in.Hi)
	case mir.OpVecConstructChecked:
		add(in.Slice)
		add(in.Lo)
		add(in.Capacity)
	case mir.OpVecGrowChecked:
		add(in.Slice)
		add(in.Domain)
		add(in.Capacity)
	case mir.OpCallValue:
		add(in.A)
		for _, v := range in.Args {
			add(v)
		}
	case mir.OpStrEq:
		add(in.A)
		add(in.B)
	case mir.OpStrOrderLt:
		add(in.A)
		add(in.B)
	case mir.OpStrLen, mir.OpStrToBytes:
		add(in.A)
	case mir.OpStrByteChecked:
		add(in.A)
		add(in.B)
	case mir.OpStrConcat:
		add(in.Domain)
		add(in.A)
		add(in.B)
	case mir.OpStrSliceChecked:
		add(in.Domain)
		add(in.A)
		add(in.Lo)
		add(in.Hi)
	case mir.OpStrFromBytes:
		add(in.Domain)
		add(in.A)
	case mir.OpFnValue:
		add(in.A)
	case mir.OpVecLen, mir.OpVecCapacity, mir.OpVecStorage, mir.OpVecAsSlice, mir.OpVecAsMutSlice:
		add(in.Slice)
	case mir.OpArrayAsSlice:
		add(in.Array)
	case mir.OpEnumPayloadChecked:
		add(in.EnumValue)
	case mir.OpEnumConstruct:
		add(in.Payload)
	case mir.OpTableCreate:
		add(in.Domain)
	case mir.OpTableInsert:
		add(in.Table)
		add(in.TableVal)
	case mir.OpTableInsertTry:
		add(in.Table)
		add(in.TableVal)
	case mir.OpTableLookup, mir.OpTableLookupMut, mir.OpTableRemove:
		add(in.Table)
		add(in.ID)
	case mir.OpTableViewEnd:
		add(in.View)
	case mir.OpIntTrunc, mir.OpIntZext, mir.OpIntSext, mir.OpFloatConvert,
		mir.OpIntFromFloat, mir.OpFloatFromInt, mir.OpIntConvertChecked, mir.OpIntConvertWrap,
		mir.OpCNumTry, mir.OpCNumWrap, mir.OpCNumCast:
		add(in.A)
	case mir.OpCFieldGet:
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
		return int(in.Callee) < len(m.Functions) && m.Functions[in.Callee] != nil && m.Functions[in.Callee].Result == mir.TypeUnit
	case mir.OpFFICallUnsafe:
		return int(in.FFIImport) < len(m.Imports) && m.Imports[in.FFIImport].Sig.Result == mir.TypeUnit
	case mir.OpCBindingCall:
		_, fn, ok := m.BindingFuncAt(in.CBinding)
		return ok && fn.Sig.Result == mir.TypeUnit
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
	if b.Term.Kind > mir.TermPanic {
		return []Error{{Loc: loc, Msg: fmt.Sprintf("unknown terminator kind %d", b.Term.Kind)}}
	}
	switch b.Term.Kind {
	case mir.TermJump:
		for _, v := range b.Term.Args {
			if v == mir.NoValue {
				errs = append(errs, Error{Loc: loc, Msg: "jump argument is missing"})
			}
			checkVal(v, "jump argument")
		}
	case mir.TermBranch:
		if b.Term.Cond == mir.NoValue {
			errs = append(errs, Error{Loc: loc, Msg: "branch condition is missing"})
		}
		checkVal(b.Term.Cond, "branch condition")
		for _, v := range b.Term.ThenArgs {
			if v == mir.NoValue {
				errs = append(errs, Error{Loc: loc, Msg: "branch argument is missing"})
			}
			checkVal(v, "branch argument")
		}
		for _, v := range b.Term.ElseArgs {
			if v == mir.NoValue {
				errs = append(errs, Error{Loc: loc, Msg: "branch argument is missing"})
			}
			checkVal(v, "branch argument")
		}
	case mir.TermSwitch:
		if b.Term.Value == mir.NoValue {
			errs = append(errs, Error{Loc: loc, Msg: "switch operand is missing"})
		}
		checkVal(b.Term.Value, "switch operand")
		for _, c := range b.Term.Cases {
			for _, v := range c.Args {
				if v == mir.NoValue {
					errs = append(errs, Error{Loc: loc, Msg: "switch argument is missing"})
				}
				checkVal(v, "switch argument")
			}
		}
	case mir.TermFail:
		if b.Term.Result == mir.NoValue {
			errs = append(errs, Error{Loc: loc, Msg: "fail operand is missing"})
		}
		checkVal(b.Term.Result, "fail operand")
	case mir.TermReturn:
		checkVal(b.Term.Result, "return operand")
	case mir.TermPanic:
		if m.FormatVersion < mir.PanicFormatVersion {
			errs = append(errs, Error{Loc: loc, Msg: "panic requires MIR format version 2"})
		}
		if b.Term.Result != mir.NoValue {
			errs = append(errs, Error{Loc: loc, Msg: "panic may not have an operand"})
		}
	}
	return errs
}

// checkBindings validates C binding blocks structurally: unique block and
// member names, valid names, well-formed member signatures, and every C
// binding type owned by exactly one block.
func checkBindings(m *mir.Module) []Error {
	var errs []Error
	if len(m.Bindings) == 0 {
		for i := range m.Types {
			if m.Types[i].Kind == mir.TypeCNamed {
				errs = append(errs, Error{Loc: fmt.Sprintf("type @%s", m.Types[i].Name), Msg: "C binding type has no binding block"})
			}
		}
		return errs
	}
	if m.FormatVersion < mir.BindingFormatVersion {
		errs = append(errs, Error{Loc: fmt.Sprintf("binding @%s", m.Bindings[0].Name), Msg: "binding blocks require MIR format version 6"})
	}
	owned := make(map[mir.TypeId]int)
	for bi := range m.Bindings {
		block := &m.Bindings[bi]
		loc := fmt.Sprintf("binding @%s", block.Name)
		if !validMIRName(block.Name, true) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("invalid binding name %q", block.Name)})
		}
		if block.Header == "" {
			errs = append(errs, Error{Loc: loc, Msg: "binding header is empty"})
		}
		for bj := 0; bj < bi; bj++ {
			if m.Bindings[bj].Name == block.Name {
				errs = append(errs, Error{Loc: loc, Msg: "duplicate binding name"})
				break
			}
		}
		for _, id := range block.Types {
			if !m.ValidType(id) || m.Types[id].Kind != mir.TypeCNamed {
				errs = append(errs, Error{Loc: loc, Msg: "binding type member is not a C binding type"})
				continue
			}
			if other, seen := owned[id]; seen {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("type @%s is also a member of binding @%s", m.Types[id].Name, m.Bindings[other].Name)})
				continue
			}
			owned[id] = bi
		}
		funcNames := make(map[string]bool, len(block.Funcs))
		for i := range block.Funcs {
			fn := &block.Funcs[i]
			if !validMIRName(fn.Name, true) {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("invalid binding function name %q", fn.Name)})
			}
			if funcNames[fn.Name] {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("duplicate binding function @%s", fn.Name)})
			}
			funcNames[fn.Name] = true
			if fn.Sig.Env != mir.NoType {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("binding function @%s carries an environment", fn.Name)})
			}
		}
		constNames := make(map[string]bool, len(block.Consts))
		for i := range block.Consts {
			c := &block.Consts[i]
			if !validMIRName(c.Name, true) {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("invalid binding constant name %q", c.Name)})
			}
			if constNames[c.Name] {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("duplicate binding constant @%s", c.Name)})
			}
			constNames[c.Name] = true
		}
	}
	return errs
}
