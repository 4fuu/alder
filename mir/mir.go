package mir

import "strconv"

const (
	// LegacyFormatVersion is the original MIR format, retained for existing
	// fixtures. It does not include the panic terminator.
	LegacyFormatVersion = 1
	// PanicFormatVersion introduced the valueless panic terminator.
	PanicFormatVersion = 2
	// AllocCheckedFormatVersion introduced recoverably fallible allocation.
	AllocCheckedFormatVersion = 3
	// CurrentFormatVersion is the format emitted by newly constructed modules.
	CurrentFormatVersion = AllocCheckedFormatVersion
)

// Module is a complete MIR unit: type declarations, imported C declarations,
// constants, and functions. Optional source-span tables are reserved for the
// future frontend and do not yet appear in the textual format.
type Module struct {
	// FormatVersion is the textual MIR format version.
	FormatVersion int
	// Types is the module type table; TypeId values index it.
	Types []Type
	// Imports lists imported C declarations; ImportId values index it.
	Imports []ImportDecl
	// Constants lists named module constants.
	Constants []ConstDecl
	// Functions lists functions in declaration order; FunctionId values index it.
	Functions []*Function
}

// ImportDecl is an imported C declaration. In the initial vocabulary the
// import name is also the C symbol; retention, const, and cleanup claims are
// deferred to a later MIR version.
type ImportDecl struct {
	Name string
	Sig  FuncSig
}

// ConstKind classifies a constant value.
type ConstKind uint8

const (
	ConstUnit ConstKind = iota
	ConstBool
	ConstInt
	ConstFloat
	ConstString
)

// ConstValue is the value of a module constant.
type ConstValue struct {
	Kind   ConstKind
	Bool   bool
	Int    int64
	Float  float64
	String string
}

// ConstDecl is a named module constant. Instructions materialize constants
// with const.get; the initial vocabulary has no immediate operands.
type ConstDecl struct {
	Name  string
	Type  TypeId
	Value ConstValue
}

// Function is a MIR function: typed parameters, local slots, basic blocks
// with SSA-like temporaries, and block parameters instead of phi nodes.
type Function struct {
	Name   string
	Params []Param
	Result TypeId
	Locals []Local
	Blocks []*Block
	Values []Value
}

// Param is a typed parameter of a function or block.
type Param struct {
	Name string
	Type TypeId
}

// Local is a mutable local slot; LocalId values index Function.Locals.
type Local struct {
	Name string
	Type TypeId
}

// Block is a basic block with exactly one terminator.
type Block struct {
	Name   string
	Params []Param
	Instrs []Instr
	Term   Terminator
}

// ValueDefKind describes how a value is defined.
type ValueDefKind uint8

const (
	// ValueDefFuncParam: a function parameter; dominates the whole function.
	ValueDefFuncParam ValueDefKind = iota
	// ValueDefBlockParam: a block parameter (Def.Param indexes Block.Params).
	ValueDefBlockParam
	// ValueDefInstr: an instruction result (Def.Instr indexes Block.Instrs).
	ValueDefInstr
	// ValueDefSwitchCase: a switch case payload binding (Def.Case indexes
	// Terminator.Cases).
	ValueDefSwitchCase
)

// ValueDef locates a value definition within a function.
type ValueDef struct {
	Kind  ValueDefKind
	Block BlockId
	Instr int // ValueDefInstr
	Param int // ValueDefBlockParam
	Case  int // ValueDefSwitchCase
}

// Value is an SSA-like temporary. Type is NoType when no static type is known;
// the parser stores NoType for best-effort parses of malformed input and the
// verifier rejects such values.
type Value struct {
	Name string
	Type TypeId
	Def  ValueDef
}

// ValueType returns the type of a value.
func (f *Function) ValueType(id ValueId) (TypeId, bool) {
	if int(id) >= len(f.Values) {
		return NoType, false
	}
	return f.Values[id].Type, true
}

// PlaceKind classifies a place.
type PlaceKind uint8

const (
	// PlaceLocal: a local slot.
	PlaceLocal PlaceKind = iota
	// PlaceField: a named aggregate field of a base place.
	PlaceField
	// PlaceDeref: dereference of a checked reference value (safe_ref,
	// safe_mut, or a table view).
	PlaceDeref
)

// Place identifies readable or mutable storage. The initial vocabulary has no
// unchecked index place: checked element access uses slice.index.checked,
// which yields a checked reference that deref places consume.
type Place struct {
	Kind  PlaceKind
	Local LocalId // PlaceLocal
	Base  *Place  // PlaceField
	Field string  // PlaceField
	Deref ValueId // PlaceDeref
}

// Instr is one instruction. Operand fields are operation-specific; the
// verifier checks that the fields used by an operation are present and
// well-typed.
type Instr struct {
	Op     OpKind
	Result ValueId // NoValue when the operation produces no value

	// load / store
	Place    Place
	StoreVal ValueId

	// aggregate.construct
	AggType   TypeId
	AggFields []AggField

	// domain.create / mark / reset / destroy / alloc / alloc.checked / copy_to_domain
	Domain  ValueId
	Mark    ValueId
	TypeOp  TypeId // alloc element type, table.create element type, enum.construct and conversion result type
	Count   ValueId
	CopyVal ValueId

	// cleanup.scope.begin / push / disarm / run / end
	Scope       ValueId
	CleanupFn   FunctionId
	CleanupArgs []ValueId
	CleanupID   ValueId

	// int / float / slice / enum operands
	A         ValueId
	B         ValueId
	Slice     ValueId
	Index     ValueId
	Lo        ValueId
	Hi        ValueId
	EnumValue ValueId
	Variant   string
	Payload   ValueId // NoValue when the variant has a unit payload

	// tables
	Table    ValueId
	ID       ValueId
	TableVal ValueId
	View     ValueId

	// const.get / call / ffi.call.unsafe
	Const     string
	Callee    FunctionId
	FFIImport ImportId
	Args      []ValueId

	// Checked operations: the explicit failure edge. Required for checked
	// operations and forbidden for all others.
	FailTarget BlockId // NoBlock when absent
	FailArgs   []ValueId
}

// AggField is one named field operand of aggregate.construct.
type AggField struct {
	Name  string
	Value ValueId
}

// TermKind classifies a block terminator.
type TermKind uint8

const (
	TermJump TermKind = iota
	TermBranch
	TermSwitch
	TermReturn
	TermFail
	TermUnreachable
	TermPanic
)

// String returns the canonical textual name of the terminator kind.
func (k TermKind) String() string {
	switch k {
	case TermJump:
		return "jump"
	case TermBranch:
		return "branch"
	case TermSwitch:
		return "switch"
	case TermReturn:
		return "return"
	case TermFail:
		return "fail"
	case TermUnreachable:
		return "unreachable"
	case TermPanic:
		return "panic"
	}
	return "terminator(" + strconv.Itoa(int(k)) + ")"
}

// SwitchCase is one case of a switch terminator. Binding is the payload value
// defined by the case (NoValue when the case binds no payload). A case with an
// empty Variant is the default case; the verifier allows at most one.
// Exhaustiveness: a switch must cover every variant of its operand type or
// contain a default case.
type SwitchCase struct {
	Variant string
	Binding ValueId
	Target  BlockId
	Args    []ValueId
}

// Terminator is the single terminator of a block. Operand fields are
// kind-specific; the verifier checks their presence and types.
type Terminator struct {
	Kind TermKind

	// jump
	Target BlockId
	Args   []ValueId

	// branch
	Cond     ValueId
	Then     BlockId
	ThenArgs []ValueId
	Else     BlockId
	ElseArgs []ValueId

	// switch
	Value ValueId
	Cases []SwitchCase

	// return / fail (panic and unreachable are valueless)
	Result ValueId // NoValue for a unit return without an operand
}

// AddImport appends an imported C declaration and returns its ImportId.
func (m *Module) AddImport(name string, sig FuncSig) ImportId {
	m.Imports = append(m.Imports, ImportDecl{Name: name, Sig: sig})
	return ImportId(len(m.Imports) - 1)
}

// AddConst appends a named constant declaration.
func (m *Module) AddConst(name string, typ TypeId, v ConstValue) {
	m.Constants = append(m.Constants, ConstDecl{Name: name, Type: typ, Value: v})
}

// AddFunction appends a function and returns it. Function parameters are
// registered as the leading values of the function.
func (m *Module) AddFunction(name string, params []Param, result TypeId) *Function {
	f := &Function{Name: name, Params: params, Result: result}
	for _, p := range params {
		f.Values = append(f.Values, Value{Name: p.Name, Type: p.Type, Def: ValueDef{Kind: ValueDefFuncParam}})
	}
	m.Functions = append(m.Functions, f)
	return f
}

// AddLocal appends a local slot and returns its LocalId.
func (f *Function) AddLocal(name string, typ TypeId) LocalId {
	f.Locals = append(f.Locals, Local{Name: name, Type: typ})
	return LocalId(len(f.Locals) - 1)
}

// AddBlock appends a block and returns it. Block parameters are registered as
// values whose definitions are the block itself.
func (f *Function) AddBlock(name string, params []Param) *Block {
	b := &Block{Name: name, Params: params}
	id := BlockId(len(f.Blocks))
	for i, p := range params {
		f.Values = append(f.Values, Value{Name: p.Name, Type: p.Type, Def: ValueDef{Kind: ValueDefBlockParam, Block: id, Param: i}})
	}
	f.Blocks = append(f.Blocks, b)
	return b
}

// AddValue appends a value and returns its ValueId.
func (f *Function) AddValue(name string, typ TypeId, def ValueDef) ValueId {
	f.Values = append(f.Values, Value{Name: name, Type: typ, Def: def})
	return ValueId(len(f.Values) - 1)
}

// AddInstr appends an instruction to a block.
func (b *Block) AddInstr(in Instr) {
	b.Instrs = append(b.Instrs, in)
}

// SetTerm sets the block terminator.
func (b *Block) SetTerm(t Terminator) {
	b.Term = t
}
