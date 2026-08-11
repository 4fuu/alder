package frontend

import (
	"strconv"
	"strings"
)

// typeKind classifies a checked concrete type.
type typeKind uint8

const (
	tPrim typeKind = iota
	tSlice
	tAlloc // alloc result: a mutable reference to the first element
	tOption
	tResult
	tMap
	tBuffer
	tS0Error
	tStruct
	tEnum
	tDomain
	tDomainMark
	tCleanupScope
	tCleanupID
	tPtr
	tTypeParam // an unresolved generic type parameter (checking only)
)

// primType identifies a primitive.
type primType uint8

const (
	pBool primType = iota
	pI8
	pI16
	pI32
	pI64
	pU8
	pU16
	pU32
	pU64
	pF32
	pF64
	pUnit
)

// primNames mirrors primType in order.
var primNames = [...]string{
	"Bool", "I8", "I16", "I32", "I64", "U8", "U16", "U32", "U64", "F32", "F64", "Unit",
}

// typeDecl and variantType are declared in check.go.

// Type is a checked, concrete source type. Structs and enums are
// monomorphized: every Type references a typeDecl plus concrete arguments.
type Type struct {
	kind typeKind
	prim primType

	elem *Type // tSlice, tAlloc, tPtr, tOption
	ok   *Type // tResult
	err  *Type // tResult
	key  *Type // tMap
	val  *Type // tMap

	decl *typeDecl // tStruct, tEnum
	args []*Type   // monomorphization arguments (tStruct, tEnum)

	name string // type parameter name (tTypeParam)
}

// prim returns the primitive type.
func prim(p primType) *Type { return &Type{kind: tPrim, prim: p} }

// typeParam returns an unresolved generic parameter type.
func typeParam(name string) *Type { return &Type{kind: tTypeParam, name: name} }

func (t *Type) isTypeParam() bool { return t != nil && t.kind == tTypeParam }

// concrete reports recursively whether a type is safe to pass to lowering.
func (t *Type) concrete() bool {
	if t == nil || t.kind == tTypeParam {
		return false
	}
	switch t.kind {
	case tSlice, tAlloc, tPtr, tOption, tBuffer:
		return t.elem.concrete()
	case tResult:
		return t.ok.concrete() && t.err.concrete()
	case tMap:
		return t.key.concrete() && t.val.concrete()
	case tStruct, tEnum:
		if t.decl == nil || len(t.args) != len(t.decl.params) {
			return false
		}
		for _, arg := range t.args {
			if !arg.concrete() {
				return false
			}
		}
	}
	return true
}

// isInt reports whether the type is an integer type.
func (t *Type) isInt() bool {
	if t == nil || t.kind != tPrim {
		return false
	}
	switch t.prim {
	case pI8, pI16, pI32, pI64, pU8, pU16, pU32, pU64:
		return true
	}
	return false
}

func (t *Type) isFloat() bool {
	return t != nil && t.kind == tPrim && (t.prim == pF32 || t.prim == pF64)
}

func (t *Type) isSigned() bool {
	switch t.prim {
	case pI8, pI16, pI32, pI64:
		return true
	}
	return false
}

func (t *Type) isUnsigned() bool {
	switch t.prim {
	case pU8, pU16, pU32, pU64:
		return true
	}
	return false
}

// intWidth returns the width of an integer type in bits (0 for non-ints).
func (t *Type) intWidth() int {
	switch t.prim {
	case pI8, pU8:
		return 8
	case pI16, pU16:
		return 16
	case pI32, pU32:
		return 32
	case pI64, pU64:
		return 64
	}
	return 0
}

// display renders the type for diagnostics and source-level messages.
func (t *Type) display() string {
	if t == nil {
		return "<missing type>"
	}
	switch t.kind {
	case tPrim:
		return primNames[t.prim]
	case tSlice:
		return "[" + t.elem.display() + "]"
	case tAlloc:
		return "[" + t.elem.display() + "] (allocated)"
	case tOption:
		return "Option(" + t.elem.display() + ")"
	case tResult:
		return "Result(" + t.ok.display() + ", " + t.err.display() + ")"
	case tMap:
		return "Map(" + t.key.display() + ", " + t.val.display() + ")"
	case tBuffer:
		return "__s0_Buffer(" + t.elem.display() + ")"
	case tS0Error:
		return "__s0_Error"
	case tStruct:
		if len(t.args) == 0 {
			return t.decl.decl.Name
		}
		parts := make([]string, 0, len(t.args))
		for _, a := range t.args {
			parts = append(parts, a.display())
		}
		return t.decl.decl.Name + "(" + strings.Join(parts, ", ") + ")"
	case tEnum:
		if len(t.args) == 0 {
			return t.decl.decl.Name
		}
		parts := make([]string, 0, len(t.args))
		for _, a := range t.args {
			parts = append(parts, a.display())
		}
		return t.decl.decl.Name + "(" + strings.Join(parts, ", ") + ")"
	case tDomain:
		return "Domain"
	case tDomainMark:
		return "DomainMark"
	case tPtr:
		return "Ptr(" + t.elem.display() + ")"
	case tTypeParam:
		return t.name
	}
	return "<unknown type>"
}

// mangledName is the deterministic MIR-safe name of a type: declaration
// names joined with argument counts, so different applications can never
// collide (Pair(A.B, C) versus Pair(A, B.C)). Source identifiers cannot
// contain dots, so generated names never collide with user names.
func (t *Type) mangledName() string {
	if t == nil {
		return "<none>"
	}
	switch t.kind {
	case tStruct, tEnum:
		parts := make([]string, 0, len(t.args)+2)
		parts = append(parts, t.decl.decl.Name, "c"+strconv.Itoa(len(t.args)))
		for _, a := range t.args {
			parts = append(parts, a.mangledName())
		}
		return strings.Join(parts, ".")
	case tSlice:
		return "Slice.c1." + t.elem.mangledName()
	case tAlloc:
		return "AllocRef.c1." + t.elem.mangledName()
	case tOption:
		return "Option.c1." + t.elem.mangledName()
	case tResult:
		return "Result.c2." + t.ok.mangledName() + "." + t.err.mangledName()
	case tMap:
		return "Map.c2." + t.key.mangledName() + "." + t.val.mangledName()
	case tBuffer:
		return "__s0_Buffer.c1." + t.elem.mangledName()
	case tS0Error:
		return "__s0_Error"
	case tPtr:
		return "Ptr.c1." + t.elem.mangledName()
	case tPrim:
		return primNames[t.prim]
	case tDomain:
		return "Domain"
	case tDomainMark:
		return "DomainMark"
	case tTypeParam:
		return t.name
	}
	return "<unknown>"
}

// enumLike reports whether the type supports variants: a declared enum,
// Option, or Result.
func (t *Type) enumLike() bool {
	return t != nil && (t.kind == tEnum || t.kind == tOption || t.kind == tResult || t.kind == tS0Error)
}

// variantsOf returns the variants of an enum-like type.
func (t *Type) variantsOf() []*variantType {
	switch t.kind {
	case tEnum:
		return t.decl.variants
	case tOption:
		return []*variantType{{name: "None"}, {name: "Some", payload: t.elem}}
	case tResult:
		return []*variantType{{name: "Ok", payload: t.ok}, {name: "Err", payload: t.err}}
	case tS0Error:
		return []*variantType{{name: "OutOfMemory"}, {name: "Limit"}}
	}
	return nil
}

// variantByName resolves a variant of an enum-like type.
func (t *Type) variantByName(name string) *variantType {
	for _, v := range t.variantsOf() {
		if v.name == name {
			return v
		}
	}
	return nil
}

// containsSlice reports whether the type contains a slice or allocated
// reference anywhere (nested through structs, enums, options, results).
func (t *Type) containsSlice() bool {
	if t == nil {
		return false
	}
	switch t.kind {
	case tSlice, tAlloc, tMap, tBuffer, tDomain, tDomainMark, tCleanupScope, tCleanupID, tPtr:
		return true
	case tOption:
		return t.elem.containsSlice()
	case tResult:
		return t.ok.containsSlice() || t.err.containsSlice()
	case tStruct:
		bindings := structBindings(t)
		for _, f := range t.decl.fields {
			if substType(f, bindings).containsSlice() {
				return true
			}
		}
		return false
	case tEnum:
		bindings := structBindings(t)
		for _, v := range t.decl.variants {
			if v.payload != nil && substType(v.payload, bindings).containsSlice() {
				return true
			}
		}
		return false
	}
	return false
}

// copyTrivial reports whether a value of the type can be stored through a
// dereference place under the current MIR rules: no slices, references, or tables
// anywhere inside.
func (t *Type) copyTrivial() bool {
	return !t.containsSlice()
}

// mapKeyOK reports whether the type may be a Map key: unsigned integers,
// Bool, or structs/enums composed of those.
func (t *Type) mapKeyOK() bool {
	if t == nil {
		return false
	}
	switch t.kind {
	case tPrim:
		return t.prim == pBool || t.isUnsigned()
	case tStruct:
		bindings := structBindings(t)
		for _, f := range t.decl.fields {
			if !substType(f, bindings).mapKeyOK() {
				return false
			}
		}
		return true
	case tEnum:
		bindings := structBindings(t)
		for _, v := range t.decl.variants {
			if v.payload != nil && !substType(v.payload, bindings).mapKeyOK() {
				return false
			}
		}
		return true
	}
	return false
}

// typeEqual reports structural equality of two checked types.
func typeEqual(a, b *Type) bool {
	if a == nil || b == nil {
		return a == b
	}
	if a.kind != b.kind {
		return false
	}
	switch a.kind {
	case tPrim:
		return a.prim == b.prim
	case tSlice, tAlloc, tPtr, tOption, tBuffer:
		return typeEqual(a.elem, b.elem)
	case tResult:
		return typeEqual(a.ok, b.ok) && typeEqual(a.err, b.err)
	case tMap:
		return typeEqual(a.key, b.key) && typeEqual(a.val, b.val)
	case tStruct, tEnum:
		if a.decl != b.decl || len(a.args) != len(b.args) {
			return false
		}
		for i := range a.args {
			if !typeEqual(a.args[i], b.args[i]) {
				return false
			}
		}
		return true
	case tDomain, tDomainMark, tCleanupScope, tCleanupID, tS0Error:
		return true
	case tTypeParam:
		return a.name == b.name
	}
	return false
}

// unify binds type parameters against concrete types. Returns false on a
// conflict; bindings accumulate in out.
func unify(pattern, actual *Type, out map[string]*Type) bool {
	if pattern == nil || actual == nil {
		return pattern == actual
	}
	if pattern.isTypeParam() {
		if bound, ok := out[pattern.name]; ok {
			return typeEqual(bound, actual)
		}
		out[pattern.name] = actual
		return true
	}
	if pattern.kind != actual.kind {
		return false
	}
	switch pattern.kind {
	case tPrim:
		return pattern.prim == actual.prim
	case tSlice, tAlloc, tPtr, tOption, tBuffer:
		return unify(pattern.elem, actual.elem, out)
	case tResult:
		return unify(pattern.ok, actual.ok, out) && unify(pattern.err, actual.err, out)
	case tMap:
		return unify(pattern.key, actual.key, out) && unify(pattern.val, actual.val, out)
	case tStruct, tEnum:
		if pattern.decl != actual.decl || len(pattern.args) != len(actual.args) {
			return false
		}
		for i := range pattern.args {
			if !unify(pattern.args[i], actual.args[i], out) {
				return false
			}
		}
		return true
	case tDomain, tDomainMark, tCleanupScope, tCleanupID, tS0Error:
		return true
	case tTypeParam:
		return pattern.name == actual.name
	}
	return false
}

// substType replaces type parameters using bindings.
func substType(t *Type, bindings map[string]*Type) *Type {
	if t == nil {
		return nil
	}
	if t.isTypeParam() {
		if b, ok := bindings[t.name]; ok {
			return b
		}
		return t
	}
	switch t.kind {
	case tSlice:
		return &Type{kind: tSlice, elem: substType(t.elem, bindings)}
	case tAlloc:
		return &Type{kind: tAlloc, elem: substType(t.elem, bindings)}
	case tOption:
		return &Type{kind: tOption, elem: substType(t.elem, bindings)}
	case tResult:
		return &Type{kind: tResult, ok: substType(t.ok, bindings), err: substType(t.err, bindings)}
	case tMap:
		return &Type{kind: tMap, key: substType(t.key, bindings), val: substType(t.val, bindings)}
	case tBuffer:
		return &Type{kind: tBuffer, elem: substType(t.elem, bindings)}
	case tPtr:
		return &Type{kind: tPtr, elem: substType(t.elem, bindings)}
	case tStruct, tEnum:
		args := make([]*Type, len(t.args))
		for i, a := range t.args {
			args[i] = substType(a, bindings)
		}
		return &Type{kind: t.kind, decl: t.decl, args: args}
	}
	return t
}

func structBindings(t *Type) map[string]*Type {
	bindings := make(map[string]*Type)
	if t == nil || t.decl == nil {
		return bindings
	}
	for i, p := range t.decl.params {
		if i < len(t.args) {
			bindings[p] = t.args[i]
		}
	}
	return bindings
}
