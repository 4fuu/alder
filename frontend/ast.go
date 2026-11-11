package frontend

// pos is a source position (1-based legacy byte line and column) and the
// complete span of the token that established it.
type pos struct {
	line int
	col  int
	span Span
}

// Decl is a top-level declaration.
type Decl interface{ declPos() pos }

// ImportDecl declares an imported C symbol. The source name is the C symbol.
type ImportDecl struct {
	P    pos
	Name string
	Sig  FuncSigExpr
}

// FuncSigExpr is a concrete function signature over type expressions.
type FuncSigExpr struct {
	Params []TypeExpr
	Result TypeExpr
}

// TypeDecl is a struct or enum declaration, possibly generic.
type TypeDecl struct {
	P        pos
	Name     string
	IsEnum   bool
	Params   []string // type parameter names, in order
	Fields   []FieldDecl
	Variants []VariantDecl
}

// FieldDecl is one struct field.
type FieldDecl struct {
	Name string
	Type TypeExpr
}

// VariantDecl is one enum variant with at most one payload.
type VariantDecl struct {
	Name         string
	PayloadLabel string
	Payload      TypeExpr // nil when the variant has no payload
}

// FnDecl is a function declaration. Leading Params of Kind paramType are
// compile-time type parameters; the rest are runtime parameters.
type FnDecl struct {
	P      pos
	Name   string
	Params []ParamDecl
	Result TypeExpr
	Body   *Block
}

// ParamDecl is one function parameter.
type ParamDecl struct {
	Name string
	Kind paramKind
	Type TypeExpr // nil for paramType
}

type paramKind uint8

const (
	paramRuntime paramKind = iota
	paramType
)

func (d *ImportDecl) declPos() pos { return d.P }
func (d *TypeDecl) declPos() pos   { return d.P }
func (d *FnDecl) declPos() pos     { return d.P }

// TypeExpr is a source type expression.
type TypeExpr interface{ typePos() pos }

// PrimType names a primitive type: Bool, I8..U64, F32, F64, Unit, Domain,
// DomainMark, CleanupScope, CleanupID, or String.
type PrimType struct {
	P    pos
	Name string
}

// SliceType is [T].
type SliceType struct {
	P    pos
	Elem TypeExpr
}

// AppType is Name(Args): a generic type application (Option, Result, Map,
// Ptr, or a declared type constructor).
type AppType struct {
	P    pos
	Name string
	Args []TypeExpr
}

// ArrayLit is a fixed-length array value.
type ArrayLit struct {
	P     pos
	Elems []Expr
}

func (t *PrimType) typePos() pos  { return t.P }
func (t *SliceType) typePos() pos { return t.P }
func (t *AppType) typePos() pos   { return t.P }

// Expr is a typed-source expression.
type Expr interface{ exprPos() pos }

// IntLit is an integer literal; Value is the magnitude (up to 2^63).
type IntLit struct {
	P     pos
	Text  string
	Value int64
}

// FloatLit is a floating-point literal.
type FloatLit struct {
	P     pos
	Value float64
}

// StrLit is a string literal.
type StrLit struct {
	P     pos
	Value string
}

// BoolLit is true or false.
type BoolLit struct {
	P     pos
	Value bool
}

// Ident is a name reference: a variable, a no-payload variant constructor
// (None, Dot), or a bare type used as an explicit type argument.
type Ident struct {
	P    pos
	Name string
}

// Unary is -x or !x.
type Unary struct {
	P  pos
	Op string
	X  Expr
}

// Binary is an infix operation.
type Binary struct {
	P  pos
	Op string
	X  Expr
	Y  Expr
}

// Call is Name(args), Name(args)(args), Variant(arg), or a builtin call.
// Callee is an Ident or another Call (for applied generic constructors).
type Call struct {
	P      pos
	Callee Expr
	Args   []Expr
}

// NamedArg is a named record-construction argument.
type NamedArg struct {
	P     pos
	Name  string
	Value Expr
}

// UnsafeC is the sole source-level boundary for a direct C import call.
type UnsafeC struct {
	P    pos
	Call *Call
}

// Field is base.field.
type Field struct {
	P    pos
	Base Expr
	Name string
}

// Index is base[index].
type Index struct {
	P     pos
	Base  Expr
	Index Expr
}

// Match is match value { arms }.
type Match struct {
	P     pos
	Value Expr
	Arms  []MatchArm
}

// MatchArm is one match arm. Variant "" with Bind "" is the wildcard.
type MatchArm struct {
	Variant string
	Bind    string
	Body    Expr
}

// UnitLit is the sole Unit value, written ().
type UnitLit struct {
	P pos
}

// Try is try expr (error propagation).
type Try struct {
	P pos
	X Expr
}

func (e *IntLit) exprPos() pos   { return e.P }
func (e *UnitLit) exprPos() pos  { return e.P }
func (e *FloatLit) exprPos() pos { return e.P }
func (e *StrLit) exprPos() pos   { return e.P }
func (e *BoolLit) exprPos() pos  { return e.P }
func (e *Ident) exprPos() pos    { return e.P }
func (e *Unary) exprPos() pos    { return e.P }
func (e *Binary) exprPos() pos   { return e.P }
func (e *Call) exprPos() pos     { return e.P }
func (e *NamedArg) exprPos() pos { return e.P }
func (e *UnsafeC) exprPos() pos  { return e.P }
func (e *Field) exprPos() pos    { return e.P }
func (e *Index) exprPos() pos    { return e.P }
func (e *Match) exprPos() pos    { return e.P }
func (e *Try) exprPos() pos      { return e.P }
func (e *ArrayLit) exprPos() pos { return e.P }

// Stmt is a statement.
type Stmt interface{ stmtPos() pos }

// Let is let/var name [: T] = expr.
type Let struct {
	P     pos
	Var   bool
	Name  string
	Type  TypeExpr // nil when omitted
	Value Expr
}

// Assign is target = expr.
type Assign struct {
	P      pos
	Target AssignTarget
	Value  Expr
}

// AssignTarget is an assignment destination: name, name.f, name[i], or
// name[i].f.
type AssignTarget struct {
	P     pos
	Name  string
	Field string // "" when the target is the whole binding
	Index Expr   // nil when the target is a plain binding or field
}

// IfStmt is if cond { then } [else { else }].
type IfStmt struct {
	P    pos
	Cond Expr
	Then *Block
	Else *Block // nil when absent
}

// WhileStmt is while cond { body }.
type WhileStmt struct {
	P    pos
	Cond Expr
	Body *Block
}

// ForStmt is for name in seq { body }.
type ForStmt struct {
	P    pos
	Name string
	Seq  Expr
	Body *Block
}

// UsingStmt is using name = expr with CleanupFn.
type UsingStmt struct {
	P       pos
	Name    string
	Value   Expr
	Cleanup string
}

// ReturnStmt is return [expr].
type ReturnStmt struct {
	P     pos
	Value Expr // nil for a unit return
}

// ExprStmt is a call or match used as a statement.
type ExprStmt struct {
	P pos
	X Expr
}

// Block is a braced statement list.
type Block struct {
	P     pos
	Stmts []Stmt
}

func (s *Let) stmtPos() pos        { return s.P }
func (s *Assign) stmtPos() pos     { return s.P }
func (s *IfStmt) stmtPos() pos     { return s.P }
func (s *WhileStmt) stmtPos() pos  { return s.P }
func (s *ForStmt) stmtPos() pos    { return s.P }
func (s *UsingStmt) stmtPos() pos  { return s.P }
func (s *ReturnStmt) stmtPos() pos { return s.P }
func (s *ExprStmt) stmtPos() pos   { return s.P }
func (s *Block) stmtPos() pos      { return s.P }

// astError is a deterministic source diagnostic.
type astError struct {
	line    int
	col     int
	msg     string
	code    DiagnosticCode
	span    Span
	related []RelatedDiagnostic
	notes   []string
}

func (e *astError) Error() string {
	return formatDiag(e.line, e.col, e.msg)
}

func formatDiag(line, col int, msg string) string {
	return "line " + itoa(line) + ", column " + itoa(col) + ": " + msg
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	neg := v < 0
	if neg {
		v = -v
	}
	for v > 0 {
		i--
		b[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
