package mir

import (
	"strconv"
	"strings"
)

// TypeKind classifies a Type table entry.
type TypeKind uint8

const (
	// TypePrimitive marks the canonical primitive slots (unit, bool, ints,
	// floats). The specific primitive is implied by the TypeId.
	TypePrimitive TypeKind = iota
	// TypeAggregate is a named aggregate declaration.
	TypeAggregate
	// TypeEnum is a named enum declaration.
	TypeEnum
	// TypeOption is the option(T) structural type with implicit variants
	// none (unit payload) and some (T payload).
	TypeOption
	// TypeResult is the result(T, E) structural type with implicit variants
	// ok (T payload) and err (E payload).
	TypeResult
	// TypeSlice is the slice(T) dynamic-array type.
	TypeSlice
	// TypeSafeRef is a checked, read-only reference to T.
	TypeSafeRef
	// TypeSafeMut is a checked, mutable reference to T.
	TypeSafeMut
	// TypeRawPtr is a raw C pointer to T, restricted to unsafe boundaries.
	TypeRawPtr
	// TypeFunction is the function(Signature) type.
	TypeFunction
	// TypeDomainHandle is a runtime storage-domain handle.
	TypeDomainHandle
	// TypeDomainMark is a resettable domain mark.
	TypeDomainMark
	// TypeCleanupScope is a runtime cleanup scope.
	TypeCleanupScope
	// TypeCleanupID identifies one registered cleanup entry.
	TypeCleanupID
	// TypeTable is the generational table(T) type.
	TypeTable
	// TypeID is the generational id(T) type.
	TypeID
	// TypeTableView is a scoped read-only view of one table element.
	TypeTableView
	// TypeTableMutView is a scoped mutable view of one table element.
	TypeTableMutView
	// TypeArray is the array(T, N) fixed-length value type.
	TypeArray
	// TypeString is an immutable, UTF-8 encoded owned string value.
	TypeString
	// TypeBytes is an immutable owned byte-sequence value.
	TypeBytes
	// TypeVec is an owned growable vector value.
	TypeVec
)

// Canonical primitive TypeIds occupy the first slots of every module type
// table. Their kinds are TypePrimitive and their meaning is implied by the
// slot.
const (
	TypeUnit TypeId = iota
	TypeBool
	TypeI8
	TypeI16
	TypeI32
	TypeI64
	TypeU8
	TypeU16
	TypeU32
	TypeU64
	TypeF32
	TypeF64
	// NumPrimitiveTypes is the number of canonical primitive slots.
	NumPrimitiveTypes
)

// primitiveNames mirrors the canonical primitive slots in order.
var primitiveNames = [NumPrimitiveTypes]string{
	"unit", "bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64",
}

// PrimitiveName returns the textual name of a canonical primitive TypeId.
func PrimitiveName(t TypeId) (string, bool) {
	if t < NumPrimitiveTypes {
		return primitiveNames[t], true
	}
	return "", false
}

// Field is a named aggregate field.
type Field struct {
	Name string
	Type TypeId
}

// Variant is an enum variant. Payload is TypeUnit when the variant carries no
// payload.
type Variant struct {
	Name    string
	Payload TypeId
}

// FuncSig is a concrete function signature: parameters, result type, and
// the closure environment type. Env is NoType for plain functions and the
// environment payload type for closures.
type FuncSig struct {
	Params []TypeId
	Result TypeId
	Env    TypeId
}

// Type is one entry of a Module type table.
type Type struct {
	Kind     TypeKind
	Name     string    // non-empty for named aggregate and enum declarations
	Fields   []Field   // TypeAggregate
	Variants []Variant // TypeEnum
	Elem     TypeId    // option, slice, safe_ref, safe_mut, raw_ptr, table, id, table_view, table_mut_view, array
	Length   uint64    // TypeArray
	OK       TypeId    // TypeResult
	Err      TypeId    // TypeResult
	Sig      FuncSig   // TypeFunction
}

// ValidType reports whether t is a defined type of the module.
func (m *Module) ValidType(t TypeId) bool {
	return int(t) < len(m.Types)
}

// TypeString returns the deterministic textual form of a type.
func (m *Module) TypeString(t TypeId) string {
	if name, ok := PrimitiveName(t); ok {
		return name
	}
	if !m.ValidType(t) {
		return "<invalid type " + strconv.FormatUint(uint64(t), 10) + ">"
	}
	ty := &m.Types[t]
	switch ty.Kind {
	case TypeAggregate, TypeEnum:
		return "@" + ty.Name
	case TypeOption:
		return "option(" + m.TypeString(ty.Elem) + ")"
	case TypeResult:
		return "result(" + m.TypeString(ty.OK) + ", " + m.TypeString(ty.Err) + ")"
	case TypeSlice:
		return "slice(" + m.TypeString(ty.Elem) + ")"
	case TypeSafeRef:
		return "safe_ref(" + m.TypeString(ty.Elem) + ")"
	case TypeSafeMut:
		return "safe_mut(" + m.TypeString(ty.Elem) + ")"
	case TypeRawPtr:
		return "raw_ptr(" + m.TypeString(ty.Elem) + ")"
	case TypeFunction:
		var b strings.Builder
		b.WriteString("function(fn(")
		for i, p := range ty.Sig.Params {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(m.TypeString(p))
		}
		b.WriteString(") -> ")
		b.WriteString(m.TypeString(ty.Sig.Result))
		if ty.Sig.Env != NoType {
			b.WriteString(", ")
			b.WriteString(m.TypeString(ty.Sig.Env))
		}
		b.WriteString(")")
		return b.String()
	case TypeDomainHandle:
		return "domain_handle"
	case TypeDomainMark:
		return "domain_mark"
	case TypeCleanupScope:
		return "cleanup_scope"
	case TypeCleanupID:
		return "cleanup_id"
	case TypeTable:
		return "table(" + m.TypeString(ty.Elem) + ")"
	case TypeID:
		return "id(" + m.TypeString(ty.Elem) + ")"
	case TypeTableView:
		return "table_view(" + m.TypeString(ty.Elem) + ")"
	case TypeTableMutView:
		return "table_mut_view(" + m.TypeString(ty.Elem) + ")"
	case TypeArray:
		return "array(" + m.TypeString(ty.Elem) + ", " + strconv.FormatUint(ty.Length, 10) + ")"
	case TypeString:
		return "string"
	case TypeBytes:
		return "bytes"
	case TypeVec:
		return "vec(" + m.TypeString(ty.Elem) + ")"
	}
	return "<invalid kind " + strconv.Itoa(int(ty.Kind)) + ">"
}

// VariantsOf returns the variants of an enum-like type: the declared variants
// of an enum, none/some for option, and ok/err for result.
func (m *Module) VariantsOf(t TypeId) ([]Variant, bool) {
	if !m.ValidType(t) {
		return nil, false
	}
	switch m.Types[t].Kind {
	case TypeEnum:
		return m.Types[t].Variants, true
	case TypeOption:
		return []Variant{{Name: "none", Payload: TypeUnit}, {Name: "some", Payload: m.Types[t].Elem}}, true
	case TypeResult:
		return []Variant{{Name: "ok", Payload: m.Types[t].OK}, {Name: "err", Payload: m.Types[t].Err}}, true
	}
	return nil, false
}

// IsEnumLike reports whether t can be dispatched and constructed through named
// variants: a declared enum, an option, or a result type.
func (m *Module) IsEnumLike(t TypeId) bool {
	_, ok := m.VariantsOf(t)
	return ok
}

// VariantIndex resolves a variant name within an enum-like type.
func (m *Module) VariantIndex(t TypeId, name string) (int, bool) {
	vs, ok := m.VariantsOf(t)
	if !ok {
		return 0, false
	}
	for i, v := range vs {
		if v.Name == name {
			return i, true
		}
	}
	return 0, false
}

// VariantPayload returns the payload type of variant i of an enum-like type
// (TypeUnit when the variant carries no payload).
func (m *Module) VariantPayload(t TypeId, i int) (TypeId, bool) {
	vs, ok := m.VariantsOf(t)
	if !ok || i < 0 || i >= len(vs) {
		return NoType, false
	}
	return vs[i].Payload, true
}

// ElemType returns the element type of a slice, vector, safe_ref, or safe_mut type.
func (m *Module) ElemType(t TypeId) (TypeId, bool) {
	if !m.ValidType(t) {
		return NoType, false
	}
	switch m.Types[t].Kind {
	case TypeSlice, TypeSafeRef, TypeSafeMut, TypeVec:
		return m.Types[t].Elem, true
	}
	return NoType, false
}

// NamedType resolves a named aggregate or enum declaration by name.
func (m *Module) NamedType(name string) (TypeId, bool) {
	for i := NumPrimitiveTypes; i < TypeId(len(m.Types)); i++ {
		t := &m.Types[i]
		if (t.Kind == TypeAggregate || t.Kind == TypeEnum) && t.Name == name {
			return i, true
		}
	}
	return NoType, false
}

// Function resolves a function by name.
func (m *Module) Function(name string) (FunctionId, bool) {
	for i, f := range m.Functions {
		if f.Name == name {
			return FunctionId(i), true
		}
	}
	return NoFunction, false
}

// Import resolves an imported C declaration by name.
func (m *Module) Import(name string) (ImportId, bool) {
	for i, imp := range m.Imports {
		if imp.Name == name {
			return ImportId(i), true
		}
	}
	return NoImport, false
}

// ConstDecl resolves a module constant by name.
func (m *Module) ConstDecl(name string) (*ConstDecl, bool) {
	for i := range m.Constants {
		if m.Constants[i].Name == name {
			return &m.Constants[i], true
		}
	}
	return nil, false
}

// intern returns the TypeId of an existing anonymous type with the same shape
// as the candidate, or appends a new entry filled by fill. Named declarations
// are appended by AddAggregate and AddEnum without deduplication; the verifier
// rejects duplicate names.
func (m *Module) intern(kind TypeKind, match func(*Type) bool, fill func(*Type)) TypeId {
	for i := NumPrimitiveTypes; i < TypeId(len(m.Types)); i++ {
		t := &m.Types[i]
		if t.Kind == kind && match(t) {
			return i
		}
	}
	m.Types = append(m.Types, Type{Kind: kind})
	fill(&m.Types[len(m.Types)-1])
	return TypeId(len(m.Types) - 1)
}

func sigEqual(a, b FuncSig) bool {
	if a.Env != b.Env {
		return false
	}
	if a.Result != b.Result || len(a.Params) != len(b.Params) {
		return false
	}
	for i := range a.Params {
		if a.Params[i] != b.Params[i] {
			return false
		}
	}
	return true
}

// NewModule returns an empty module with the canonical primitive type slots
// and the current format version.
func NewModule() *Module {
	m := &Module{FormatVersion: CurrentFormatVersion}
	for i := TypeId(0); i < NumPrimitiveTypes; i++ {
		m.Types = append(m.Types, Type{Kind: TypePrimitive})
	}
	return m
}

// AddAggregate appends a named aggregate declaration and returns its TypeId.
func (m *Module) AddAggregate(name string, fields []Field) TypeId {
	m.Types = append(m.Types, Type{Kind: TypeAggregate, Name: name, Fields: fields})
	return TypeId(len(m.Types) - 1)
}

// AddEnum appends a named enum declaration and returns its TypeId.
func (m *Module) AddEnum(name string, variants []Variant) TypeId {
	m.Types = append(m.Types, Type{Kind: TypeEnum, Name: name, Variants: variants})
	return TypeId(len(m.Types) - 1)
}

// Option interns and returns option(elem).
func (m *Module) Option(elem TypeId) TypeId {
	return m.intern(TypeOption, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// Result interns and returns result(ok, err).
func (m *Module) Result(ok, err TypeId) TypeId {
	return m.intern(TypeResult, func(t *Type) bool { return t.OK == ok && t.Err == err }, func(t *Type) { t.OK = ok; t.Err = err })
}

// Slice interns and returns slice(elem).
func (m *Module) Slice(elem TypeId) TypeId {
	return m.intern(TypeSlice, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// Vec interns and returns vec(elem).
func (m *Module) Vec(elem TypeId) TypeId {
	return m.intern(TypeVec, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// Array interns and returns array(elem, length).
func (m *Module) Array(elem TypeId, length uint64) TypeId {
	return m.intern(TypeArray, func(t *Type) bool { return t.Elem == elem && t.Length == length }, func(t *Type) { t.Elem = elem; t.Length = length })
}

// String interns and returns the string leaf type.
func (m *Module) String() TypeId {
	return m.intern(TypeString, func(*Type) bool { return true }, func(*Type) {})
}

// Bytes interns and returns the bytes leaf type.
func (m *Module) Bytes() TypeId {
	return m.intern(TypeBytes, func(*Type) bool { return true }, func(*Type) {})
}

// SafeRef interns and returns safe_ref(elem).
func (m *Module) SafeRef(elem TypeId) TypeId {
	return m.intern(TypeSafeRef, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// SafeMut interns and returns safe_mut(elem).
func (m *Module) SafeMut(elem TypeId) TypeId {
	return m.intern(TypeSafeMut, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// RawPtr interns and returns raw_ptr(elem).
func (m *Module) RawPtr(elem TypeId) TypeId {
	return m.intern(TypeRawPtr, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// FunctionType interns and returns function(sig).
func (m *Module) FunctionType(sig FuncSig) TypeId {
	return m.intern(TypeFunction, func(t *Type) bool { return sigEqual(t.Sig, sig) }, func(t *Type) { t.Sig = sig })
}

// Table interns and returns table(elem).
func (m *Module) Table(elem TypeId) TypeId {
	return m.intern(TypeTable, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// ID interns and returns id(elem).
func (m *Module) ID(elem TypeId) TypeId {
	return m.intern(TypeID, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// TableView interns and returns table_view(elem).
func (m *Module) TableView(elem TypeId) TypeId {
	return m.intern(TypeTableView, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// TableMutView interns and returns table_mut_view(elem).
func (m *Module) TableMutView(elem TypeId) TypeId {
	return m.intern(TypeTableMutView, func(t *Type) bool { return t.Elem == elem }, func(t *Type) { t.Elem = elem })
}

// DomainHandle returns the singleton domain_handle type.
func (m *Module) DomainHandle() TypeId {
	return m.intern(TypeDomainHandle, func(*Type) bool { return true }, func(*Type) {})
}

// DomainMark returns the singleton domain_mark type.
func (m *Module) DomainMark() TypeId {
	return m.intern(TypeDomainMark, func(*Type) bool { return true }, func(*Type) {})
}

// CleanupScope returns the singleton cleanup_scope type.
func (m *Module) CleanupScope() TypeId {
	return m.intern(TypeCleanupScope, func(*Type) bool { return true }, func(*Type) {})
}

// CleanupID returns the singleton cleanup_id type.
func (m *Module) CleanupID() TypeId {
	return m.intern(TypeCleanupID, func(*Type) bool { return true }, func(*Type) {})
}
