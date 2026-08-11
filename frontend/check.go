package frontend

import (
	"fmt"
	"strings"
)

// annInfo annotates a checked expression with its concrete type and, for
// calls, the resolved callee.
type annInfo struct {
	typ  *Type
	call *callAnn
}

// callAnn describes a resolved call (or variant identifier).
type callAnn struct {
	kind         callKind
	fn           *checkedFn   // callUser
	builtin      string       // callBuiltin
	importName   string       // callImport
	ctorType     *Type        // callStruct, callMap (construction target)
	variant      *variantType // callVariant (resolved variant)
	enumType     *Type        // callVariant (the variant's enum type)
	explicitArgs int          // leading type arguments consumed at the call site
}

type callKind uint8

const (
	callUser callKind = iota
	callBuiltin
	callImport
	callStruct
	callMap
	callVariant
)

// checkedFn is one concrete function instantiation.
type checkedFn struct {
	decl     *FnDecl
	typeArgs []*Type
	name     string // MIR name (decl name plus mangled args)
	params   []*Type
	result   *Type
	checked  bool // body checking completed
}

// binding is a checked name binding in a function.
type binding struct {
	mut  bool
	typ  *Type
	kind bindKind
}

type bindKind uint8

const (
	bindLocal bindKind = iota
	bindParam
)

// builtinFnNames are reserved in the value namespace. Cleanup is exposed
// through the using statement only: the MIR 1 cleanup handles require
// direct instruction-result SSA identity, so the low-level scope API cannot
// cross source-level bindings.
var builtinFnNames = []string{
	"len", "range", "Alloc", "Domain", "Mark", "Reset", "Destroy",
	"Get", "Set", "Remove",
}

// builtinTypeNames are reserved in the type namespace.
var builtinTypeNames = []string{
	"Bool", "I8", "I16", "I32", "I64", "U8", "U16", "U32", "U64",
	"F32", "F64", "Unit", "String", "Option", "Result", "Map", "Ptr",
	"Domain", "DomainMark",
}

// variantReserved are reserved in the value namespace.
var variantReserved = []string{"None", "Some", "Ok", "Err"}

// typeEnv is the type-parameter scope of a generic declaration.
type typeEnv map[string]*Type

// typeDecl is the checked form of a struct or enum declaration.
type typeDecl struct {
	decl       *TypeDecl
	params     []string
	fields     []*Type // tStruct (patterns; concrete after instantiation)
	variants   []*variantType
	fieldMap   map[string]int
	variantMap map[string]int
}

// variantType is a checked enum variant.
type variantType struct {
	name    string
	payload *Type // nil for a no-payload variant
}

// checkSig is a checked import signature.
type checkSig struct {
	Params []*Type
	Result *Type
}

// checker type-checks and monomorphizes a module.
type checker struct {
	types      map[string]*typeDecl
	typeOrder  []*typeDecl
	fns        map[string]*FnDecl
	imports    map[string]*ImportDecl
	importSigs map[string]*checkSig
	builtins   map[string]bool

	checked   []*checkedFn
	fnCache   map[string]*checkedFn
	typeCache map[string]*Type

	ann map[*checkedFn]map[Expr]*annInfo
}

// checkModule type-checks and monomorphizes all declarations.
func checkModule(decls []Decl) (*checkedModule, error) {
	c := &checker{
		types:      make(map[string]*typeDecl),
		fns:        make(map[string]*FnDecl),
		imports:    make(map[string]*ImportDecl),
		importSigs: make(map[string]*checkSig),
		builtins:   make(map[string]bool),
		fnCache:    make(map[string]*checkedFn),
		typeCache:  make(map[string]*Type),
		ann:        make(map[*checkedFn]map[Expr]*annInfo),
	}
	for _, n := range builtinFnNames {
		c.builtins[n] = true
	}

	// Pass 1: collect declarations.
	for _, d := range decls {
		switch dd := d.(type) {
		case *ImportDecl:
			if _, dup := c.imports[dd.Name]; dup {
				return nil, diag(dd.P, "duplicate import name %q", dd.Name)
			}
			if isReservedValueName(dd.Name, c) {
				return nil, diag(dd.P, "import name %q is reserved", dd.Name)
			}
			c.imports[dd.Name] = dd
		case *TypeDecl:
			if _, dup := c.types[dd.Name]; dup || builtinTypeName(dd.Name) {
				return nil, diag(dd.P, "duplicate or reserved type name %q", dd.Name)
			}
			td := &typeDecl{
				decl:       dd,
				params:     dd.Params,
				fieldMap:   make(map[string]int),
				variantMap: make(map[string]int),
			}
			c.types[dd.Name] = td
			c.typeOrder = append(c.typeOrder, td)
		case *FnDecl:
			if _, dup := c.fns[dd.Name]; dup || c.builtins[dd.Name] {
				return nil, diag(dd.P, "duplicate or reserved function name %q", dd.Name)
			}
			for _, n := range variantReserved {
				if dd.Name == n {
					return nil, diag(dd.P, "function name %q is reserved", dd.Name)
				}
			}
			c.fns[dd.Name] = dd
		}
	}

	// Pass 2: check type declarations and reject value-type cycles.
	for _, td := range c.typeOrder {
		tps := make(typeEnv)
		for _, p := range td.params {
			if tps[p] != nil {
				return nil, diag(td.decl.P, "duplicate type parameter %q", p)
			}
			tps[p] = typeParam(p)
		}
		if err := c.checkTypeDecl(td, tps); err != nil {
			return nil, err
		}
	}
	if err := c.rejectTypeCycles(); err != nil {
		return nil, err
	}

	// Pass 3: check imports.
	for _, d := range decls {
		imp, ok := d.(*ImportDecl)
		if !ok {
			continue
		}
		sig, err := c.checkImport(imp)
		if err != nil {
			return nil, err
		}
		c.importSigs[imp.Name] = sig
	}

	// Pass 4: instantiate every non-generic function in source order.
	for _, d := range decls {
		fn, ok := d.(*FnDecl)
		if !ok {
			continue
		}
		if len(fn.Params) > 0 && fn.Params[0].Kind == paramType {
			continue
		}
		if _, err := c.instantiate(fn, nil); err != nil {
			return nil, err
		}
	}
	return &checkedModule{fns: c.checked, ann: c.ann, imports: c.importSigs}, nil
}

func builtinTypeName(name string) bool {
	for _, n := range builtinTypeNames {
		if n == name {
			return true
		}
	}
	return false
}

// isReservedValueName reports whether a value name collides with a type or
// builtin name.
func isReservedValueName(name string, c *checker) bool {
	if c.types[name] != nil || builtinTypeName(name) || c.builtins[name] {
		return true
	}
	for _, n := range variantReserved {
		if n == name {
			return true
		}
	}
	return false
}

func diag(p pos, format string, args ...any) error {
	return &astError{line: p.line, col: p.col, msg: fmt.Sprintf(format, args...)}
}

// checkTypeDecl resolves field and variant types against the type
// parameters.
func (c *checker) checkTypeDecl(td *typeDecl, tps typeEnv) error {
	if td.decl.IsEnum {
		for i, v := range td.decl.Variants {
			if _, dup := td.variantMap[v.Name]; dup {
				return diag(td.decl.P, "duplicate variant %q in enum %q", v.Name, td.decl.Name)
			}
			td.variantMap[v.Name] = i
			var payload *Type
			if v.Payload != nil {
				p, err := c.resolveType(v.Payload, tps)
				if err != nil {
					return err
				}
				payload = p
			}
			td.variants = append(td.variants, &variantType{name: v.Name, payload: payload})
		}
		if len(td.variants) == 0 {
			return diag(td.decl.P, "enum %q has no variants", td.decl.Name)
		}
		return nil
	}
	for i, f := range td.decl.Fields {
		if _, dup := td.fieldMap[f.Name]; dup {
			return diag(td.decl.P, "duplicate field %q in type %q", f.Name, td.decl.Name)
		}
		td.fieldMap[f.Name] = i
		ft, err := c.resolveType(f.Type, tps)
		if err != nil {
			return err
		}
		if ft.kind == tSlice && ft.elem.containsSlice() {
			return diag(td.decl.P, "slice element type %s contains a slice or reference in field %q (M4 restriction)", ft.elem.display(), f.Name)
		}
		td.fields = append(td.fields, ft)
	}
	return nil
}

// rejectTypeCycles rejects value-type recursion through a decl-level DFS
// over the resolved field and variant types.
func (c *checker) rejectTypeCycles() error {
	const (
		white = 0
		gray  = 1
		black = 2
	)
	color := make(map[*typeDecl]int)
	var visit func(td *typeDecl) error
	visit = func(td *typeDecl) error {
		switch color[td] {
		case gray:
			return diag(td.decl.P, "type %q participates in a value-type cycle", td.decl.Name)
		case black:
			return nil
		}
		color[td] = gray
		refs := make(map[*typeDecl]bool)
		var addRef func(t *Type)
		addRef = func(t *Type) {
			if t == nil {
				return
			}
			switch t.kind {
			case tStruct, tEnum:
				if t.decl != nil {
					refs[t.decl] = true
				}
			case tOption:
				addRef(t.elem)
			case tResult:
				addRef(t.ok)
				addRef(t.err)
			case tMap:
				addRef(t.key)
				addRef(t.val)
			}
		}
		for _, f := range td.fields {
			addRef(f)
		}
		for _, v := range td.variants {
			if v.payload != nil {
				addRef(v.payload)
			}
		}
		for ref := range refs {
			if err := visit(ref); err != nil {
				return err
			}
		}
		color[td] = black
		return nil
	}
	for _, td := range c.typeOrder {
		if err := visit(td); err != nil {
			return err
		}
	}
	return nil
}

// checkImport validates an import signature: primitives and Ptr(primitive)
// only, resolved to concrete types.
func (c *checker) checkImport(imp *ImportDecl) (*checkSig, error) {
	resolve := func(t TypeExpr, what string) (*Type, error) {
		if pt, ok := t.(*PrimType); ok {
			if p, isPrim := primOf(pt.Name); isPrim {
				return prim(p), nil
			}
		}
		if at, ok := t.(*AppType); ok && at.Name == "Ptr" && len(at.Args) == 1 {
			if inner, ok := at.Args[0].(*PrimType); ok {
				if p, isPrim := primOf(inner.Name); isPrim {
					return &Type{kind: tPtr, elem: prim(p)}, nil
				}
			}
		}
		return nil, diag(imp.P, "import %q: %s must be a primitive or Ptr(primitive)", imp.Name, what)
	}
	sig := &checkSig{}
	for _, p := range imp.Sig.Params {
		t, err := resolve(p, "parameter type")
		if err != nil {
			return nil, err
		}
		sig.Params = append(sig.Params, t)
	}
	r, err := resolve(imp.Sig.Result, "result type")
	if err != nil {
		return nil, err
	}
	sig.Result = r
	return sig, nil
}

// primOf maps a primitive type name; ok=false for non-primitives.
func primOf(name string) (primType, bool) {
	for i, n := range primNames {
		if n == name {
			return primType(i), true
		}
	}
	return 0, false
}

// resolveType resolves a type expression in a type-parameter scope.
func (c *checker) resolveType(e TypeExpr, tps typeEnv) (*Type, error) {
	switch t := e.(type) {
	case *PrimType:
		if t.Name == "String" {
			return &Type{kind: tSlice, elem: prim(pU8)}, nil
		}
		if p, ok := primOf(t.Name); ok {
			return prim(p), nil
		}
		switch t.Name {
		case "Domain":
			return &Type{kind: tDomain}, nil
		case "DomainMark":
			return &Type{kind: tDomainMark}, nil
		}
		if tp, ok := tps[t.Name]; ok {
			return tp, nil
		}
		if td := c.types[t.Name]; td != nil {
			return c.structType(td, nil, t.P), nil
		}
		return nil, diag(t.P, "unknown type %q", t.Name)
	case *SliceType:
		elem, err := c.resolveType(t.Elem, tps)
		if err != nil {
			return nil, err
		}
		if elem.containsSlice() {
			return nil, diag(t.P, "slice element type %s contains a slice or reference (M4 restriction)", elem.display())
		}
		return &Type{kind: tSlice, elem: elem}, nil
	case *AppType:
		args := make([]*Type, 0, len(t.Args))
		for _, a := range t.Args {
			at, err := c.resolveType(a, tps)
			if err != nil {
				return nil, err
			}
			args = append(args, at)
		}
		return c.resolveApp(t.Name, args, t.P)
	}
	return nil, diag(e.typePos(), "invalid type")
}

// resolveApp applies a named type constructor to concrete-or-pattern
// arguments.
func (c *checker) resolveApp(name string, args []*Type, p pos) (*Type, error) {
	switch name {
	case "Option":
		if len(args) != 1 {
			return nil, diag(p, "Option expects 1 type argument, got %d", len(args))
		}
		return &Type{kind: tOption, elem: args[0]}, nil
	case "Result":
		if len(args) != 2 {
			return nil, diag(p, "Result expects 2 type arguments, got %d", len(args))
		}
		return &Type{kind: tResult, ok: args[0], err: args[1]}, nil
	case "Map":
		if len(args) != 2 {
			return nil, diag(p, "Map expects 2 type arguments, got %d", len(args))
		}
		if !args[0].mapKeyOK() {
			return nil, diag(p, "Map key type %s is not supported (unsigned integers, Bool, and structs/enums of those only)", args[0].display())
		}
		if !args[1].copyTrivial() {
			return nil, diag(p, "Map value type %s must be copy-trivial (no slices or references)", args[1].display())
		}
		return &Type{kind: tMap, key: args[0], val: args[1]}, nil
	case "Ptr":
		if len(args) != 1 {
			return nil, diag(p, "Ptr expects 1 type argument, got %d", len(args))
		}
		return &Type{kind: tPtr, elem: args[0]}, nil
	}
	td := c.types[name]
	if td == nil {
		return nil, diag(p, "unknown type constructor %q", name)
	}
	if len(args) != len(td.params) {
		return nil, diag(p, "%q expects %d type arguments, got %d", name, len(td.params), len(args))
	}
	for _, a := range args {
		if a.kind == tSlice && a.elem.containsSlice() {
			return nil, diag(p, "slice element type %s contains a slice or reference (M4 restriction)", a.elem.display())
		}
	}
	concrete := true
	for _, a := range args {
		if a.isTypeParam() {
			concrete = false
		}
	}
	if concrete {
		return c.structType(td, args, p), nil
	}
	return &Type{kind: structKindOf(td), decl: td, args: args}, nil
}

func structKindOf(td *typeDecl) typeKind {
	if td.decl.IsEnum {
		return tEnum
	}
	return tStruct
}

// structType returns the cached monomorphized struct or enum type.
func (c *checker) structType(td *typeDecl, args []*Type, p pos) *Type {
	key := typeKey(td.decl.Name, args)
	if t, ok := c.typeCache[key]; ok {
		return t
	}
	t := &Type{kind: structKindOf(td), decl: td, args: args}
	c.typeCache[key] = t
	return t
}

// typeKey builds a collision-free cache key for an instantiation. Mangled
// names contain only identifier characters; commas are unambiguous.
func typeKey(name string, args []*Type) string {
	var b strings.Builder
	b.WriteString(name)
	for _, a := range args {
		b.WriteString(",")
		b.WriteString(a.mangledName())
	}
	return b.String()
}

// instantiate creates (or returns) the checked instantiation of a function.
func (c *checker) instantiate(fn *FnDecl, typeArgs []*Type) (*checkedFn, error) {
	key := typeKey(fn.Name, typeArgs)
	if cf, ok := c.fnCache[key]; ok {
		return cf, nil
	}
	var tpNames []string
	tps := make(typeEnv)
	for _, p := range fn.Params {
		if p.Kind == paramType {
			tpNames = append(tpNames, p.Name)
			tps[p.Name] = typeParam(p.Name)
		}
	}
	if len(typeArgs) != len(tpNames) {
		return nil, diag(fn.P, "internal: wrong type argument count for %q", fn.Name)
	}
	bindings := make(map[string]*Type)
	for i, n := range tpNames {
		bindings[n] = typeArgs[i]
	}
	cf := &checkedFn{
		decl:     fn,
		typeArgs: typeArgs,
		name:     fnKeyName(fn.Name, typeArgs),
	}
	// Register before checking the body so recursion resolves.
	c.fnCache[key] = cf
	c.checked = append(c.checked, cf)

	for _, p := range fn.Params {
		if p.Kind == paramType {
			continue
		}
		pt, err := c.resolveType(p.Type, tps)
		if err != nil {
			return nil, err
		}
		pt = substType(pt, bindings)
		if pt.isTypeParam() {
			return nil, diag(p.Type.typePos(), "type parameter %q is not bound in function %q", pt.name, fn.Name)
		}
		cf.params = append(cf.params, pt)
	}
	result, err := c.resolveType(fn.Result, tps)
	if err != nil {
		return nil, err
	}
	cf.result = substType(result, bindings)
	if cf.result.isTypeParam() {
		return nil, diag(fn.Result.typePos(), "type parameter %q is not bound in function %q", cf.result.name, fn.Name)
	}
	if err := c.checkBody(cf, bindings); err != nil {
		return nil, err
	}
	cf.checked = true
	return cf, nil
}

// fnKeyName is the MIR name of an instantiation: the source name plus
// dot-joined mangled arguments.
func fnKeyName(name string, args []*Type) string {
	if len(args) == 0 {
		return name
	}
	parts := make([]string, 0, len(args)+1)
	parts = append(parts, name)
	for _, a := range args {
		parts = append(parts, a.mangledName())
	}
	return strings.Join(parts, ".")
}

// bodyChecker checks one function body.
type bodyChecker struct {
	c      *checker
	cf     *checkedFn
	env    map[string]*binding
	inLoop bool
	ann    map[Expr]*annInfo
	result *Type
}

func (k *bodyChecker) note(e Expr, t *Type) { k.ann[e] = &annInfo{typ: t} }
func (k *bodyChecker) noteCall(e Expr, t *Type, ca *callAnn) {
	k.ann[e] = &annInfo{typ: t, call: ca}
}

// checkBody checks a function body and records annotations.
func (c *checker) checkBody(cf *checkedFn, bindings map[string]*Type) error {
	env := make(map[string]*binding)
	seen := make(map[string]bool)
	pi := 0
	for _, p := range cf.decl.Params {
		if p.Kind == paramType {
			continue
		}
		if seen[p.Name] {
			return diag(p.Type.typePos(), "duplicate parameter name %q", p.Name)
		}
		seen[p.Name] = true
		if isReservedValueName(p.Name, c) {
			return diag(p.Type.typePos(), "parameter name %q is reserved", p.Name)
		}
		env[p.Name] = &binding{kind: bindParam, typ: cf.params[pi]}
		pi++
	}
	ann := make(map[Expr]*annInfo)
	c.ann[cf] = ann
	k := &bodyChecker{c: c, cf: cf, env: env, ann: ann, result: cf.result}
	if err := k.checkBlock(cf.decl.Body); err != nil {
		return err
	}
	if cf.result == nil || cf.result.kind != tPrim || cf.result.prim != pUnit {
		if !guaranteesReturn(cf.decl.Body) {
			return diag(cf.decl.Body.P, "function %q may fall off the end without returning a value", cf.decl.Name)
		}
	}
	return nil
}

// guaranteesReturn reports whether a block's statements guarantee a return
// on every path.
func guaranteesReturn(b *Block) bool {
	for _, s := range b.Stmts {
		if stmtGuaranteesReturn(s) {
			return true
		}
	}
	return false
}

func stmtGuaranteesReturn(s Stmt) bool {
	switch st := s.(type) {
	case *ReturnStmt:
		return true
	case *Block:
		return guaranteesReturn(st)
	case *IfStmt:
		return st.Else != nil && guaranteesReturn(st.Then) && guaranteesReturn(st.Else)
	case *ExprStmt:
		if m, ok := st.X.(*Match); ok {
			for _, arm := range m.Arms {
				if !exprGuaranteesReturn(arm.Body) {
					return false
				}
			}
			return len(m.Arms) > 0
		}
	}
	return false
}

func exprGuaranteesReturn(e Expr) bool {
	switch x := e.(type) {
	case *Match:
		for _, arm := range x.Arms {
			if !exprGuaranteesReturn(arm.Body) {
				return false
			}
		}
		return len(x.Arms) > 0
	}
	return false
}

// checkBlock checks a statement list. Statements after a guaranteed return
// are unreachable.
func (k *bodyChecker) checkBlock(b *Block) error {
	for i, s := range b.Stmts {
		if i > 0 && stmtGuaranteesReturn(b.Stmts[i-1]) {
			return diag(s.stmtPos(), "unreachable statement")
		}
		if err := k.checkStmt(s); err != nil {
			return err
		}
	}
	return nil
}

func (k *bodyChecker) checkStmt(s Stmt) error {
	switch st := s.(type) {
	case *Let:
		if isReservedValueName(st.Name, k.c) {
			return diag(st.P, "binding name %q is reserved", st.Name)
		}
		var typ *Type
		if st.Type != nil {
			t, err := k.c.resolveType(st.Type, nil)
			if err != nil {
				return err
			}
			if t.isTypeParam() {
				return diag(st.Type.typePos(), "type parameter %q cannot appear in an annotation here", t.name)
			}
			typ = t
		}
		vt, err := k.checkExpr(st.Value, typ)
		if err != nil {
			return err
		}
		if typ == nil {
			typ = vt
		} else if !typeEqual(typ, vt) {
			return k.mismatch(st.P, "binding", typ, vt)
		}
		if typ.kind == tPrim && typ.prim == pUnit {
			return diag(st.P, "Unit values cannot be bound; use a statement")
		}
		if typ.kind == tDomainMark {
			return diag(st.P, "domain marks cannot be bound; use them directly (MIR 1 requires the reset mark to be the direct domain.mark result)")
		}
		if _, dup := k.env[st.Name]; dup {
			return diag(st.P, "name %q is already bound in this function", st.Name)
		}
		k.env[st.Name] = &binding{mut: st.Var, typ: typ, kind: bindLocal}
		return nil

	case *Assign:
		b, ok := k.env[st.Target.Name]
		if !ok {
			return diag(st.P, "unknown name %q", st.Target.Name)
		}
		if !b.mut && st.Target.Index == nil {
			return diag(st.P, "cannot assign to immutable binding %q", st.Target.Name)
		}
		if st.Target.Index != nil {
			elem, err := k.sliceElem(st.P, b.typ)
			if err != nil {
				return err
			}
			if !elem.copyTrivial() {
				return diag(st.P, "element type %s is not copy-trivial; index assignment is not available (M4 restriction)", elem.display())
			}
			it, err := k.checkExpr(st.Target.Index, prim(pU64))
			if err != nil {
				return err
			}
			if it.kind != tPrim || it.prim != pU64 {
				return k.mismatch(st.P, "index", prim(pU64), it)
			}
			if st.Target.Field != "" {
				if elem.kind != tStruct {
					return diag(st.P, "element type %s is not a struct", elem.display())
				}
				idx, ok := elem.decl.fieldMap[st.Target.Field]
				if !ok {
					return diag(st.P, "unknown field %q of %s", st.Target.Field, elem.display())
				}
				ft := substType(elem.decl.fields[idx], structBindings(elem))
				vt, err := k.checkExpr(st.Value, ft)
				if err != nil {
					return err
				}
				if !typeEqual(ft, vt) {
					return k.mismatch(st.P, "field assignment", ft, vt)
				}
				return nil
			}
			vt, err := k.checkExpr(st.Value, elem)
			if err != nil {
				return err
			}
			if !typeEqual(elem, vt) {
				return k.mismatch(st.P, "index assignment", elem, vt)
			}
			return nil
		}
		if st.Target.Field != "" {
			if b.typ.kind != tStruct {
				return diag(st.P, "name %q is not a struct", st.Target.Name)
			}
			idx, ok := b.typ.decl.fieldMap[st.Target.Field]
			if !ok {
				return diag(st.P, "unknown field %q of %s", st.Target.Field, b.typ.display())
			}
			ft := substType(b.typ.decl.fields[idx], structBindings(b.typ))
			vt, err := k.checkExpr(st.Value, ft)
			if err != nil {
				return err
			}
			if !typeEqual(ft, vt) {
				return k.mismatch(st.P, "field assignment", ft, vt)
			}
			return nil
		}
		vt, err := k.checkExpr(st.Value, b.typ)
		if err != nil {
			return err
		}
		if !typeEqual(b.typ, vt) {
			return k.mismatch(st.P, "assignment", b.typ, vt)
		}
		return nil

	case *IfStmt:
		ct, err := k.checkExpr(st.Cond, nil)
		if err != nil {
			return err
		}
		if ct.kind != tPrim || ct.prim != pBool {
			return k.mismatch(st.P, "condition", prim(pBool), ct)
		}
		if err := k.checkBlock(st.Then); err != nil {
			return err
		}
		if st.Else != nil {
			return k.checkBlock(st.Else)
		}
		return nil

	case *WhileStmt:
		ct, err := k.checkExpr(st.Cond, nil)
		if err != nil {
			return err
		}
		if ct.kind != tPrim || ct.prim != pBool {
			return k.mismatch(st.P, "condition", prim(pBool), ct)
		}
		wasLoop := k.inLoop
		k.inLoop = true
		err = k.checkBlock(st.Body)
		k.inLoop = wasLoop
		return err

	case *ForStmt:
		if isReservedValueName(st.Name, k.c) {
			return diag(st.P, "binding name %q is reserved", st.Name)
		}
		stt, err := k.checkExpr(st.Seq, nil)
		if err != nil {
			return err
		}
		elem, err := k.sliceElem(st.P, stt)
		if err != nil {
			return err
		}
		if _, dup := k.env[st.Name]; dup {
			return diag(st.P, "name %q is already bound in this function", st.Name)
		}
		k.env[st.Name] = &binding{typ: elem}
		wasLoop := k.inLoop
		k.inLoop = true
		err = k.checkBlock(st.Body)
		k.inLoop = wasLoop
		return err

	case *UsingStmt:
		if isReservedValueName(st.Name, k.c) {
			return diag(st.P, "binding name %q is reserved", st.Name)
		}
		if k.inLoop {
			return diag(st.P, "using inside a loop is rejected (a cleanup scope cannot re-begin while active)")
		}
		vt, err := k.checkExpr(st.Value, nil)
		if err != nil {
			return err
		}
		fn := k.c.fns[st.Cleanup]
		if fn == nil {
			return diag(st.P, "unknown cleanup function %q", st.Cleanup)
		}
		if len(fn.Params) == 0 || fn.Params[0].Kind == paramType || len(fn.Params) != 1 {
			return diag(st.P, "cleanup function %q must take exactly one runtime parameter", st.Cleanup)
		}
		cf, err := k.c.instantiate(fn, nil)
		if err != nil {
			return err
		}
		if len(cf.params) != 1 || !typeEqual(cf.params[0], vt) {
			return k.mismatch(st.P, "cleanup function parameter", vt, cf.params[0])
		}
		if cf.result.kind != tPrim || cf.result.prim != pUnit {
			return diag(st.P, "cleanup function %q must return Unit", st.Cleanup)
		}
		if _, dup := k.env[st.Name]; dup {
			return diag(st.P, "name %q is already bound in this function", st.Name)
		}
		k.env[st.Name] = &binding{typ: vt}
		return nil

	case *ReturnStmt:
		if st.Value == nil {
			if k.result.kind != tPrim || k.result.prim != pUnit {
				return diag(st.P, "return without a value in a function returning %s", k.result.display())
			}
			return nil
		}
		vt, err := k.checkExpr(st.Value, k.result)
		if err != nil {
			return err
		}
		if !typeEqual(vt, k.result) {
			return k.mismatch(st.P, "return", k.result, vt)
		}
		return nil

	case *ExprStmt:
		switch st.X.(type) {
		case *Call, *Match:
			_, err := k.checkExpr(st.X, nil)
			return err
		}
		return diag(st.P, "expression statement has no effect (only calls and match may be statements)")

	case *Block:
		return k.checkBlock(st)
	}
	return nil
}

func (k *bodyChecker) mismatch(p pos, what string, want, got *Type) error {
	if want != nil && want.kind == tSlice && got != nil && got.kind == tAlloc {
		return diag(p, "%s: allocated slice cannot be used where %s is required", what, want.display())
	}
	return diag(p, "%s: type mismatch: expected %s, got %s", what, want.display(), got.display())
}

// sliceElem returns the element type of a slice or allocated slice.
func (k *bodyChecker) sliceElem(p pos, t *Type) (*Type, error) {
	if t == nil || (t.kind != tSlice && t.kind != tAlloc) {
		return nil, diag(p, "expected a slice, got %s", t.display())
	}
	return t.elem, nil
}

// checkExpr checks an expression with an optional expected type and returns
// its concrete type. Constructor expressions resolve against the expected
// type; integer and float literals adapt to it.
func (k *bodyChecker) checkExpr(e Expr, expected *Type) (*Type, error) {
	switch x := e.(type) {
	case *IntLit:
		t := prim(pI64)
		if expected != nil && expected.isInt() {
			t = expected
		}
		if err := checkIntRange(x, t); err != nil {
			return nil, err
		}
		k.note(e, t)
		return t, nil

	case *FloatLit:
		t := prim(pF64)
		if expected != nil && expected.isFloat() {
			t = expected
		}
		if t.prim == pF32 && (x.Value > 3.4028234663852886e38 || x.Value < -3.4028234663852886e38) {
			return nil, diag(x.P, "float literal %g is out of range for F32", x.Value)
		}
		k.note(e, t)
		return t, nil

	case *StrLit:
		t := &Type{kind: tSlice, elem: prim(pU8)}
		k.note(e, t)
		return t, nil

	case *BoolLit:
		k.note(e, prim(pBool))
		return prim(pBool), nil

	case *Ident:
		if b, ok := k.env[x.Name]; ok {
			k.note(e, b.typ)
			return b.typ, nil
		}
		if expected != nil && expected.enumLike() {
			if v := expected.variantByName(x.Name); v != nil && v.payload == nil {
				k.noteCall(e, expected, &callAnn{kind: callVariant, variant: v, enumType: expected})
				return expected, nil
			}
		}
		if k.c.types[x.Name] != nil || builtinTypeName(x.Name) {
			return nil, diag(x.P, "%q is a type, not a value", x.Name)
		}
		if k.c.fns[x.Name] != nil {
			return nil, diag(x.P, "function %q must be called", x.Name)
		}
		return nil, diag(x.P, "unknown name %q", x.Name)

	case *Unary:
		var exp *Type
		if x.Op == "-" && expected != nil && expected.isInt() {
			exp = expected
		}
		xt, err := k.checkExpr(x.X, exp)
		if err != nil {
			return nil, err
		}
		if x.Op == "!" {
			if xt.kind != tPrim || xt.prim != pBool {
				return nil, k.mismatch(x.P, "logical not", prim(pBool), xt)
			}
			k.note(e, prim(pBool))
			return prim(pBool), nil
		}
		if xt.isInt() {
			if !xt.isSigned() {
				return nil, diag(x.P, "cannot negate unsigned type %s", xt.display())
			}
			k.note(e, xt)
			return xt, nil
		}
		return nil, diag(x.P, "cannot negate %s (float arithmetic is not available in MIR 1)", xt.display())

	case *Binary:
		return k.checkBinary(x)

	case *Field:
		bt, err := k.checkExpr(x.Base, nil)
		if err != nil {
			return nil, err
		}
		if bt.kind != tStruct {
			return nil, diag(x.P, "field access on non-struct type %s", bt.display())
		}
		idx, ok := bt.decl.fieldMap[x.Name]
		if !ok {
			return nil, diag(x.P, "unknown field %q of %s", x.Name, bt.display())
		}
		ft := substType(bt.decl.fields[idx], structBindings(bt))
		k.note(e, ft)
		return ft, nil

	case *Index:
		bt, err := k.checkExpr(x.Base, nil)
		if err != nil {
			return nil, err
		}
		elem, err := k.sliceElem(x.P, bt)
		if err != nil {
			return nil, err
		}
		it, err := k.checkExpr(x.Index, prim(pU64))
		if err != nil {
			return nil, err
		}
		if it.kind != tPrim || it.prim != pU64 {
			return nil, k.mismatch(x.P, "index", prim(pU64), it)
		}
		k.note(e, elem)
		return elem, nil

	case *Call:
		return k.checkCall(x, expected)

	case *Match:
		return k.checkMatch(x, expected)

	case *Try:
		if k.result == nil || k.result.kind != tResult {
			return nil, diag(x.P, "try requires a function returning Result")
		}
		xt, err := k.checkExpr(x.X, nil)
		if err != nil {
			return nil, err
		}
		if xt.kind != tResult {
			return nil, diag(x.P, "try requires a Result expression, got %s", xt.display())
		}
		if !typeEqual(xt.err, k.result.err) {
			return nil, diag(x.P, "try error type %s does not match function error type %s", xt.err.display(), k.result.err.display())
		}
		k.note(e, xt.ok)
		return xt.ok, nil
	}
	return nil, diag(e.exprPos(), "invalid expression")
}

func checkIntRange(x *IntLit, t *Type) error {
	width := t.intWidth()
	signed := t.isSigned()
	v := x.Value
	if v < 0 {
		if !signed {
			return diag(x.P, "literal %d is out of range for %s", v, t.display())
		}
		if v == -9223372036854775808 && width == 64 {
			return nil // negated 2^63 is I64 minimum
		}
		lim := int64(-1) << (width - 1)
		if v < lim {
			return diag(x.P, "literal %d is out of range for %s", v, t.display())
		}
		return nil
	}
	var max uint64
	switch width {
	case 8:
		max = 0x7f
		if !signed {
			max = 0xff
		}
	case 16:
		max = 0x7fff
		if !signed {
			max = 0xffff
		}
	case 32:
		max = 0x7fffffff
		if !signed {
			max = 0xffffffff
		}
	case 64:
		if signed {
			max = 0x7fffffffffffffff
		} else {
			max = 0xffffffffffffffff
		}
	}
	if uint64(v) > max {
		return diag(x.P, "literal %d is out of range for %s", v, t.display())
	}
	return nil
}

func (k *bodyChecker) checkBinary(x *Binary) (*Type, error) {
	switch x.Op {
	case "&&", "||":
		xt, err := k.checkExpr(x.X, nil)
		if err != nil {
			return nil, err
		}
		yt, err := k.checkExpr(x.Y, nil)
		if err != nil {
			return nil, err
		}
		if xt.kind != tPrim || xt.prim != pBool || yt.kind != tPrim || yt.prim != pBool {
			return nil, diag(x.P, "operator %s requires Bool operands", x.Op)
		}
		k.note(x, prim(pBool))
		return prim(pBool), nil
	}
	xt, err := k.checkExpr(x.X, nil)
	if err != nil {
		return nil, err
	}
	switch x.Op {
	case "<<", ">>":
		if !xt.isInt() {
			return nil, diag(x.P, "operator %s requires an integer left operand", x.Op)
		}
		yt, err := k.checkExpr(x.Y, xt)
		if err != nil {
			return nil, err
		}
		if !typeEqual(xt, yt) {
			return nil, k.mismatch(x.P, "shift count", xt, yt)
		}
		k.note(x, xt)
		return xt, nil
	case "==", "!=", "<", "<=", ">", ">=":
		yt, err := k.checkExpr(x.Y, xt)
		if err != nil {
			return nil, err
		}
		if !typeEqual(xt, yt) {
			return nil, k.mismatch(x.P, "comparison", xt, yt)
		}
		if !xt.isInt() && !xt.isFloat() {
			return nil, diag(x.P, "comparison requires integers or floats, got %s", xt.display())
		}
		k.note(x, prim(pBool))
		return prim(pBool), nil
	}
	if !xt.isInt() {
		return nil, diag(x.P, "operator %s requires integer operands (float arithmetic is not available in MIR 1)", x.Op)
	}
	yt, err := k.checkExpr(x.Y, xt)
	if err != nil {
		return nil, err
	}
	if !typeEqual(xt, yt) {
		return nil, k.mismatch(x.P, "operand", xt, yt)
	}
	k.note(x, xt)
	return xt, nil
}

// callHead extracts the head name of a callee expression: the leading
// identifier of an Ident or Call chain.
type callHeadInfo struct {
	name string
}

func callHead(e Expr) *callHeadInfo {
	switch c := e.(type) {
	case *Ident:
		return &callHeadInfo{name: c.Name}
	case *Call:
		return callHead(c.Callee)
	}
	return nil
}

// checkCall resolves and checks a call.
func (k *bodyChecker) checkCall(x *Call, expected *Type) (*Type, error) {
	head := callHead(x.Callee)
	if head == nil {
		return nil, diag(x.P, "invalid call target")
	}
	name := head.name

	if fn := k.c.fns[name]; fn != nil {
		return k.checkUserCall(x, fn)
	}
	// Builtin functions win over same-named builtin type names (Domain).
	if k.c.builtins[name] {
		return k.checkBuiltinCall(x, name)
	}
	if k.c.types[name] != nil || builtinTypeName(name) {
		return k.checkTypeConstruction(x, name, expected)
	}
	if sig, ok := k.c.importSigs[name]; ok {
		if len(sig.Params) != len(x.Args) {
			return nil, diag(x.P, "import %q: expected %d arguments, got %d", name, len(sig.Params), len(x.Args))
		}
		for i, arg := range x.Args {
			at, err := k.checkExpr(arg, sig.Params[i])
			if err != nil {
				return nil, err
			}
			if !typeEqual(sig.Params[i], at) {
				return nil, k.mismatch(arg.exprPos(), "import argument", sig.Params[i], at)
			}
		}
		k.noteCall(x, sig.Result, &callAnn{kind: callImport, importName: name})
		return sig.Result, nil
	}
	// Variant construction against the expected type.
	if expected != nil && expected.enumLike() {
		if v := expected.variantByName(name); v != nil {
			payload := v.payload
			if payload != nil {
				payload = substType(payload, structBindings(expected))
			}
			if payload == nil {
				return nil, diag(x.P, "variant %q carries no payload", name)
			}
			if len(x.Args) != 1 {
				return nil, diag(x.P, "variant %q expects 1 payload argument, got %d", name, len(x.Args))
			}
			at, err := k.checkExpr(x.Args[0], payload)
			if err != nil {
				return nil, err
			}
			if !typeEqual(payload, at) {
				return nil, k.mismatch(x.P, "variant payload", payload, at)
			}
			k.noteCall(x, expected, &callAnn{kind: callVariant, variant: v, enumType: expected})
			return expected, nil
		}
	}
	return nil, diag(x.P, "unknown function or type %q", name)
}

// checkUserCall handles calls to declared functions with explicit type
// arguments and inference. Arguments whose parameter pattern is already
// bound are checked directly against the concrete type (which resolves
// constructor expressions such as Some(3)); the rest are self-checked and
// unified to infer the remaining type parameters.
func (k *bodyChecker) checkUserCall(x *Call, fn *FnDecl) (*Type, error) {
	tpCount := 0
	var tpNames []string
	for _, p := range fn.Params {
		if p.Kind == paramType {
			tpCount++
			tpNames = append(tpNames, p.Name)
		}
	}
	var typeArgs []*Type
	rest := x.Args
	if tpCount > 0 {
		consumed := 0
		for consumed < tpCount && len(rest) > 0 && k.isTypeArgExpr(rest[0]) {
			ta, err := k.typeArgOf(rest[0])
			if err != nil {
				return nil, err
			}
			typeArgs = append(typeArgs, ta)
			rest = rest[1:]
			consumed++
		}
		if len(rest) > 0 && k.isTypeArgExpr(rest[0]) {
			return nil, diag(rest[0].exprPos(), "too many type arguments for %q", fn.Name)
		}
	}
	patterns := declRuntimePatterns(k.c, fn)
	if len(patterns) != len(rest) {
		return nil, diag(x.P, "call %q: expected %d arguments, got %d", fn.Name, len(patterns), len(rest))
	}

	bindings := make(map[string]*Type)
	for i, n := range tpNames {
		if i < len(typeArgs) {
			bindings[n] = typeArgs[i]
		}
	}
	// Pass 1: bound patterns check their arguments directly; unbound
	// patterns self-check and unify.
	for i, arg := range rest {
		pattern := patterns[i]
		if patternBound(pattern, bindings) {
			exp := substType(pattern, bindings)
			at, err := k.checkExpr(arg, exp)
			if err != nil {
				return nil, err
			}
			if !typeEqual(exp, at) {
				return nil, k.mismatch(arg.exprPos(), "call argument", exp, at)
			}
			continue
		}
		at, err := k.checkExpr(arg, nil)
		if err != nil {
			if len(bindings) < tpCount {
				return nil, diag(x.P, "cannot infer the type parameters of %q from this argument; supply explicit type arguments", fn.Name)
			}
			return nil, err
		}
		if !unify(pattern, at, bindings) {
			return nil, k.mismatch(arg.exprPos(), "call argument", pattern, at)
		}
	}

	// Resolve the full type argument list in declaration order.
	full := make([]*Type, 0, tpCount)
	for _, n := range tpNames {
		b, ok := bindings[n]
		if !ok || b.isTypeParam() {
			return nil, diag(x.P, "cannot infer type parameter %q of %q; supply explicit type arguments", n, fn.Name)
		}
		full = append(full, b)
	}
	cf, err := k.c.instantiate(fn, full)
	if err != nil {
		return nil, err
	}
	// Pass 2: re-check every argument against the concrete parameter types.
	for i, arg := range rest {
		at, err := k.checkExpr(arg, cf.params[i])
		if err != nil {
			return nil, err
		}
		if !typeEqual(cf.params[i], at) {
			return nil, k.mismatch(arg.exprPos(), "call argument", cf.params[i], at)
		}
	}
	k.noteCall(x, cf.result, &callAnn{kind: callUser, fn: cf, explicitArgs: len(typeArgs)})
	return cf.result, nil
}

// patternBound reports whether every type parameter in a pattern is bound.
func patternBound(t *Type, bindings map[string]*Type) bool {
	if t == nil {
		return true
	}
	if t.isTypeParam() {
		_, ok := bindings[t.name]
		return ok
	}
	switch t.kind {
	case tSlice, tAlloc, tPtr, tOption:
		return patternBound(t.elem, bindings)
	case tResult:
		return patternBound(t.ok, bindings) && patternBound(t.err, bindings)
	case tMap:
		return patternBound(t.key, bindings) && patternBound(t.val, bindings)
	case tStruct, tEnum:
		for _, a := range t.args {
			if !patternBound(a, bindings) {
				return false
			}
		}
		return true
	}
	return true
}

// declRuntimePatterns returns the runtime parameter types of a function
// declaration as patterns (with type parameters intact).
func declRuntimePatterns(c *checker, fn *FnDecl) []*Type {
	tps := make(typeEnv)
	for _, p := range fn.Params {
		if p.Kind == paramType {
			tps[p.Name] = typeParam(p.Name)
		}
	}
	var out []*Type
	for _, p := range fn.Params {
		if p.Kind == paramType {
			continue
		}
		t, err := c.resolveType(p.Type, tps)
		if err != nil {
			out = append(out, typeParam("?"))
			continue
		}
		out = append(out, t)
	}
	return out
}

// isTypeArgExpr reports whether an argument parses as an explicit type
// argument: a type name, or a non-empty application of type expressions.
func (k *bodyChecker) isTypeArgExpr(e Expr) bool {
	switch x := e.(type) {
	case *Ident:
		return k.c.types[x.Name] != nil || builtinTypeName(x.Name)
	case *Call:
		head := callHead(x)
		if head == nil {
			return false
		}
		if !(k.c.types[head.name] != nil || builtinTypeName(head.name)) {
			return false
		}
		if len(x.Args) == 0 {
			return false
		}
		for _, a := range x.Args {
			if !k.isTypeArgExpr(a) {
				return false
			}
		}
		return true
	}
	return false
}

// typeArgOf resolves an explicit type-argument expression to a type.
func (k *bodyChecker) typeArgOf(e Expr) (*Type, error) {
	switch x := e.(type) {
	case *Ident:
		return k.c.resolveType(&PrimType{P: x.P, Name: x.Name}, nil)
	case *Call:
		head := callHead(x)
		if head == nil {
			return nil, diag(x.P, "invalid type argument")
		}
		var args []*Type
		for _, a := range x.Args {
			ta, err := k.typeArgOf(a)
			if err != nil {
				return nil, err
			}
			args = append(args, ta)
		}
		return k.c.resolveApp(head.name, args, x.P)
	}
	return nil, diag(e.exprPos(), "invalid type argument")
}

// checkTypeConstruction handles Name(args) where Name is a type: a type
// application used as a construction target, or a construction.
func (k *bodyChecker) checkTypeConstruction(x *Call, name string, expected *Type) (*Type, error) {
	if inner, ok := x.Callee.(*Call); ok {
		head := callHead(inner.Callee)
		if head == nil {
			return nil, diag(x.P, "invalid construction target")
		}
		var args []*Type
		for _, a := range inner.Args {
			at, err := k.typeArgOf(a)
			if err != nil {
				return nil, err
			}
			args = append(args, at)
		}
		ty, err := k.c.resolveApp(head.name, args, inner.P)
		if err != nil {
			return nil, err
		}
		return k.checkConstruction(x, ty)
	}
	td := k.c.types[name]
	if td == nil {
		return nil, diag(x.P, "%q is a type, not a value", name)
	}
	if len(td.params) > 0 {
		// Generic construction: infer type arguments from the fields.
		bindings := make(map[string]*Type)
		if len(x.Args) != len(td.decl.Fields) {
			return nil, diag(x.P, "%q expects %d fields, got %d", name, len(td.decl.Fields), len(x.Args))
		}
		for i, arg := range x.Args {
			at, err := k.checkExpr(arg, nil)
			if err != nil {
				return nil, err
			}
			if !unify(td.fields[i], at, bindings) {
				return nil, k.mismatch(arg.exprPos(), "field", td.fields[i], at)
			}
		}
		args := make([]*Type, 0, len(td.params))
		for _, p := range td.params {
			b, ok := bindings[p]
			if !ok {
				return nil, diag(x.P, "cannot infer type parameter %q of %q", p, name)
			}
			args = append(args, b)
		}
		ty := k.c.structType(td, args, x.P)
		return k.checkConstruction(x, ty)
	}
	ty := k.c.structType(td, nil, x.P)
	return k.checkConstruction(x, ty)
}

// checkConstruction checks a struct or map construction.
func (k *bodyChecker) checkConstruction(x *Call, ty *Type) (*Type, error) {
	switch ty.kind {
	case tStruct:
		if len(x.Args) != len(ty.decl.decl.Fields) {
			return nil, diag(x.P, "%q expects %d fields, got %d", ty.decl.decl.Name, len(ty.decl.decl.Fields), len(x.Args))
		}
		bindings := structBindings(ty)
		for i, arg := range x.Args {
			ft := substType(ty.decl.fields[i], bindings)
			at, err := k.checkExpr(arg, ft)
			if err != nil {
				return nil, err
			}
			if !typeEqual(ft, at) {
				return nil, k.mismatch(arg.exprPos(), "field", ft, at)
			}
		}
		k.noteCall(x, ty, &callAnn{kind: callStruct, ctorType: ty})
		return ty, nil
	case tMap:
		if len(x.Args) != 1 {
			return nil, diag(x.P, "Map construction expects 1 domain argument, got %d", len(x.Args))
		}
		dt, err := k.checkExpr(x.Args[0], &Type{kind: tDomain})
		if err != nil {
			return nil, err
		}
		if dt.kind != tDomain {
			return nil, k.mismatch(x.P, "map domain", &Type{kind: tDomain}, dt)
		}
		k.noteCall(x, ty, &callAnn{kind: callMap, ctorType: ty})
		return ty, nil
	}
	return nil, diag(x.P, "cannot construct %s", ty.display())
}

// checkMatch checks a match expression.
func (k *bodyChecker) checkMatch(x *Match, expected *Type) (*Type, error) {
	vt, err := k.checkExpr(x.Value, nil)
	if err != nil {
		return nil, err
	}
	if !vt.enumLike() {
		return nil, diag(x.P, "match requires an enum, Option, or Result, got %s", vt.display())
	}
	variants := vt.variantsOf()
	covered := make(map[string]bool)
	hasWildcard := false
	var armType *Type
	checkArm := func(body Expr) error {
		exp := expected
		if armType != nil {
			exp = armType
		}
		at, err := k.checkExpr(body, exp)
		if err != nil {
			return err
		}
		if armType == nil {
			armType = at
		} else if !typeEqual(armType, at) {
			return k.mismatch(body.exprPos(), "match arm", armType, at)
		}
		return nil
	}
	for _, arm := range x.Arms {
		if arm.Variant == "" {
			hasWildcard = true
			if err := checkArm(arm.Body); err != nil {
				return nil, err
			}
			continue
		}
		v := vt.variantByName(arm.Variant)
		if v == nil {
			return nil, diag(x.P, "unknown variant %q for %s", arm.Variant, vt.display())
		}
		if covered[arm.Variant] {
			return nil, diag(x.P, "duplicate variant %q in match", arm.Variant)
		}
		covered[arm.Variant] = true
		if v.payload != nil {
			if arm.Bind == "" {
				return nil, diag(x.P, "variant %q carries a payload; bind it with a name", arm.Variant)
			}
			if isReservedValueName(arm.Bind, k.c) {
				return nil, diag(x.P, "binding name %q is reserved", arm.Bind)
			}
			if _, dup := k.env[arm.Bind]; dup {
				return nil, diag(x.P, "name %q is already bound in this function", arm.Bind)
			}
			k.env[arm.Bind] = &binding{typ: substType(v.payload, structBindings(vt))}
			err := checkArm(arm.Body)
			delete(k.env, arm.Bind)
			if err != nil {
				return nil, err
			}
			continue
		}
		if arm.Bind != "" {
			return nil, diag(x.P, "variant %q carries no payload; remove the binding", arm.Variant)
		}
		if err := checkArm(arm.Body); err != nil {
			return nil, err
		}
	}
	if armType == nil {
		return nil, diag(x.P, "match has no arms")
	}
	if !hasWildcard {
		for _, v := range variants {
			if !covered[v.name] {
				return nil, diag(x.P, "match is not exhaustive: variant %q of %s is not covered", v.name, vt.display())
			}
		}
	}
	k.note(x, armType)
	return armType, nil
}

// checkBuiltinCall checks a builtin call.
func (k *bodyChecker) checkBuiltinCall(x *Call, name string) (*Type, error) {
	args := x.Args
	expect := func(n int) error {
		if len(args) != n {
			return diag(x.P, "%q expects %d arguments, got %d", name, n, len(args))
		}
		return nil
	}
	checkDomain := func(i int) (*Type, error) {
		t, err := k.checkExpr(args[i], &Type{kind: tDomain})
		if err != nil {
			return nil, err
		}
		if t.kind != tDomain {
			return nil, k.mismatch(args[i].exprPos(), "domain", &Type{kind: tDomain}, t)
		}
		return t, nil
	}
	switch name {
	case "len":
		if err := expect(1); err != nil {
			return nil, err
		}
		t, err := k.checkExpr(args[0], nil)
		if err != nil {
			return nil, err
		}
		if _, err := k.sliceElem(args[0].exprPos(), t); err != nil {
			return nil, err
		}
		k.noteCall(x, prim(pU64), &callAnn{kind: callBuiltin, builtin: name})
		return prim(pU64), nil

	case "range":
		if err := expect(3); err != nil {
			return nil, err
		}
		t, err := k.checkExpr(args[0], nil)
		if err != nil {
			return nil, err
		}
		elem, err := k.sliceElem(args[0].exprPos(), t)
		if err != nil {
			return nil, err
		}
		for i := 1; i <= 2; i++ {
			it, err := k.checkExpr(args[i], prim(pU64))
			if err != nil {
				return nil, err
			}
			if it.kind != tPrim || it.prim != pU64 {
				return nil, k.mismatch(args[i].exprPos(), "range bound", prim(pU64), it)
			}
		}
		rt := &Type{kind: tSlice, elem: elem}
		k.noteCall(x, rt, &callAnn{kind: callBuiltin, builtin: name})
		return rt, nil

	case "Alloc":
		// Alloc(T, d, n): explicit type argument first.
		if len(args) != 3 {
			return nil, diag(x.P, "Alloc expects 3 arguments: Alloc(T, domain, count)")
		}
		ta, err := k.typeArgOf(args[0])
		if err != nil {
			return nil, err
		}
		if !ta.copyTrivial() {
			return nil, diag(args[0].exprPos(), "Alloc element type %s must be copy-trivial (no slices or references)", ta.display())
		}
		if _, err := checkDomain(1); err != nil {
			return nil, err
		}
		nt, err := k.checkExpr(args[2], prim(pU64))
		if err != nil {
			return nil, err
		}
		if nt.kind != tPrim || nt.prim != pU64 {
			return nil, k.mismatch(args[2].exprPos(), "allocation count", prim(pU64), nt)
		}
		rt := &Type{kind: tAlloc, elem: ta}
		k.noteCall(x, rt, &callAnn{kind: callBuiltin, builtin: name})
		return rt, nil

	case "Domain":
		if err := expect(1); err != nil {
			return nil, err
		}
		if _, err := checkDomain(0); err != nil {
			return nil, err
		}
		k.noteCall(x, &Type{kind: tDomain}, &callAnn{kind: callBuiltin, builtin: name})
		return &Type{kind: tDomain}, nil

	case "Mark":
		if err := expect(1); err != nil {
			return nil, err
		}
		if _, err := checkDomain(0); err != nil {
			return nil, err
		}
		k.noteCall(x, &Type{kind: tDomainMark}, &callAnn{kind: callBuiltin, builtin: name})
		return &Type{kind: tDomainMark}, nil

	case "Reset":
		if err := expect(2); err != nil {
			return nil, err
		}
		if _, err := checkDomain(0); err != nil {
			return nil, err
		}
		mt, err := k.checkExpr(args[1], &Type{kind: tDomainMark})
		if err != nil {
			return nil, err
		}
		if mt.kind != tDomainMark {
			return nil, k.mismatch(args[1].exprPos(), "mark", &Type{kind: tDomainMark}, mt)
		}
		k.noteCall(x, prim(pUnit), &callAnn{kind: callBuiltin, builtin: name})
		return prim(pUnit), nil

	case "Destroy":
		if err := expect(1); err != nil {
			return nil, err
		}
		if _, err := checkDomain(0); err != nil {
			return nil, err
		}
		k.noteCall(x, prim(pUnit), &callAnn{kind: callBuiltin, builtin: name})
		return prim(pUnit), nil

	case "Get", "Set", "Remove":
		return k.checkMapCall(x, name)
	}
	return nil, diag(x.P, "unknown builtin %q", name)
}

// checkMapCall checks Get/Set/Remove with type-parameter inference.
func (k *bodyChecker) checkMapCall(x *Call, name string) (*Type, error) {
	var sig []*Type
	var result *Type
	switch name {
	case "Get":
		sig = []*Type{
			{kind: tMap, key: typeParam("K"), val: typeParam("V")},
			typeParam("K"),
		}
		result = &Type{kind: tOption, elem: typeParam("V")}
	case "Set":
		sig = []*Type{
			{kind: tMap, key: typeParam("K"), val: typeParam("V")},
			typeParam("K"),
			typeParam("V"),
		}
		result = prim(pUnit)
	case "Remove":
		sig = []*Type{
			{kind: tMap, key: typeParam("K"), val: typeParam("V")},
			typeParam("K"),
		}
		result = prim(pBool)
	}
	// Explicit type arguments: Get(K, V, m, k).
	rest := x.Args
	var explicit []*Type
	for len(explicit) < 2 && len(rest) > 0 && k.isTypeArgExpr(rest[0]) {
		ta, err := k.typeArgOf(rest[0])
		if err != nil {
			return nil, err
		}
		explicit = append(explicit, ta)
		rest = rest[1:]
	}
	if len(rest) > 0 && k.isTypeArgExpr(rest[0]) {
		return nil, diag(rest[0].exprPos(), "too many type arguments for %q", name)
	}
	bindings := make(map[string]*Type)
	if len(explicit) > 0 {
		bindings["K"] = explicit[0]
		if len(explicit) > 1 {
			bindings["V"] = explicit[1]
		}
	}
	if len(rest) != len(sig) {
		return nil, diag(x.P, "%q expects %d arguments, got %d", name, len(sig), len(rest))
	}
	// Pass 1: bound patterns check their arguments directly; unbound
	// patterns self-check and unify.
	for i, arg := range rest {
		pattern := sig[i]
		if patternBound(pattern, bindings) {
			exp := substType(pattern, bindings)
			at, err := k.checkExpr(arg, exp)
			if err != nil {
				return nil, err
			}
			if !typeEqual(exp, at) {
				return nil, k.mismatch(arg.exprPos(), "argument", exp, at)
			}
			continue
		}
		at, err := k.checkExpr(arg, nil)
		if err != nil {
			return nil, err
		}
		if !unify(pattern, at, bindings) {
			return nil, k.mismatch(arg.exprPos(), "argument", pattern, at)
		}
	}
	if bindings["K"] == nil || bindings["K"].isTypeParam() {
		return nil, diag(x.P, "cannot infer map key type for %q", name)
	}
	if bindings["V"] == nil || bindings["V"].isTypeParam() {
		return nil, diag(x.P, "cannot infer map value type for %q", name)
	}
	res := substType(result, bindings)
	// Pass 2: re-check every argument against the concrete types.
	for i, arg := range rest {
		at, err := k.checkExpr(arg, substType(sig[i], bindings))
		if err != nil {
			return nil, err
		}
		if !typeEqual(substType(sig[i], bindings), at) {
			return nil, k.mismatch(arg.exprPos(), "argument", substType(sig[i], bindings), at)
		}
	}
	k.noteCall(x, res, &callAnn{kind: callBuiltin, builtin: name})
	return res, nil
}
