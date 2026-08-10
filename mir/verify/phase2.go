package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase2Types checks type and layout well-formedness: in-range children,
// unique field and variant names, no type cycles, no ephemeral types in
// declaration positions, and constant values that fit their declared types.
func phase2Types(m *mir.Module) []Error {
	var errs []Error
	for i := range m.Types {
		id := mir.TypeId(i)
		errs = append(errs, checkTypeEntry(m, id, &m.Types[i])...)
	}
	for i := range m.Types {
		errs = append(errs, checkTypeCycle(m, mir.TypeId(i), &m.Types[i])...)
	}
	for _, c := range m.Constants {
		errs = append(errs, checkConst(m, &c)...)
	}
	for i := range m.Imports {
		errs = append(errs, checkSigDecl(m, fmt.Sprintf("import @%s", m.Imports[i].Name), m.Imports[i].Sig)...)
	}
	for _, f := range m.Functions {
		if f == nil {
			continue
		}
		loc := locFunc(f)
		errs = append(errs, checkSigDecl(m, loc, FuncSigOf(f))...)
		for _, l := range f.Locals {
			errs = append(errs, checkDeclType(m, loc, "local %"+l.Name, l.Type)...)
		}
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for _, p := range b.Params {
				errs = append(errs, checkDeclType(m, locBlock(f, b), "block parameter %"+p.Name, p.Type)...)
			}
		}
	}
	return errs
}

// FuncSigOf adapts a function to a signature for type checks.
func FuncSigOf(f *mir.Function) mir.FuncSig {
	params := make([]mir.TypeId, len(f.Params))
	for i, p := range f.Params {
		params[i] = p.Type
	}
	return mir.FuncSig{Params: params, Result: f.Result}
}

func checkTypeEntry(m *mir.Module, id mir.TypeId, t *mir.Type) []Error {
	var errs []Error
	loc := typeLoc(m, id)
	if !m.ValidType(id) {
		return nil // out-of-range entries cannot be referenced
	}
	checkChild := func(child mir.TypeId, what string) {
		if !m.ValidType(child) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s type out of range", what)})
		}
	}
	switch t.Kind {
	case mir.TypeAggregate:
		seen := make(map[string]bool, len(t.Fields))
		for _, fld := range t.Fields {
			if fld.Name == "" {
				errs = append(errs, Error{Loc: loc, Msg: "aggregate field has an empty name"})
				continue
			}
			if seen[fld.Name] {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("duplicate field name %q", fld.Name)})
			}
			seen[fld.Name] = true
			checkChild(fld.Type, fmt.Sprintf("field %q", fld.Name))
		}
	case mir.TypeEnum:
		if len(t.Variants) == 0 {
			errs = append(errs, Error{Loc: loc, Msg: "enum has no variants"})
		}
		seen := make(map[string]bool, len(t.Variants))
		for _, v := range t.Variants {
			if v.Name == "" {
				errs = append(errs, Error{Loc: loc, Msg: "variant has an empty name"})
				continue
			}
			if v.Name == "default" {
				errs = append(errs, Error{Loc: loc, Msg: "variant name \"default\" is reserved"})
			}
			if seen[v.Name] {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("duplicate variant name %q", v.Name)})
			}
			seen[v.Name] = true
			checkChild(v.Payload, fmt.Sprintf("variant %q payload", v.Name))
		}
	case mir.TypeOption, mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut,
		mir.TypeRawPtr, mir.TypeTable, mir.TypeID, mir.TypeTableView, mir.TypeTableMutView:
		checkChild(t.Elem, "element")
	case mir.TypeResult:
		checkChild(t.OK, "ok payload")
		checkChild(t.Err, "err payload")
	case mir.TypeFunction:
		checkSigTypes(m, loc, t.Sig)
	}
	return errs
}

func checkSigTypes(m *mir.Module, loc string, sig mir.FuncSig) []Error {
	var errs []Error
	for _, p := range sig.Params {
		if !m.ValidType(p) {
			errs = append(errs, Error{Loc: loc, Msg: "parameter type out of range"})
		}
	}
	if !m.ValidType(sig.Result) {
		errs = append(errs, Error{Loc: loc, Msg: "result type out of range"})
	}
	return errs
}

// checkSigDecl checks a signature used in a declaration position: in-range
// types and no ephemeral view types in parameters or results.
func checkSigDecl(m *mir.Module, loc string, sig mir.FuncSig) []Error {
	errs := checkSigTypes(m, loc, sig)
	for i, p := range sig.Params {
		errs = append(errs, checkDeclType(m, loc, fmt.Sprintf("parameter %d", i), p)...)
	}
	errs = append(errs, checkDeclType(m, loc, "result type", sig.Result)...)
	return errs
}

// checkDeclType rejects ephemeral types in declaration positions: table views
// may only appear as instruction results and operands, never in fields,
// payloads, signatures, locals, or parameters.
func checkDeclType(m *mir.Module, loc, what string, t mir.TypeId) []Error {
	if !m.ValidType(t) {
		return nil // reported elsewhere
	}
	if containsKind(m, t, mir.TypeTableView) || containsKind(m, t, mir.TypeTableMutView) {
		return []Error{{Loc: loc, Msg: fmt.Sprintf("%s: table views are ephemeral and may not appear in declarations", what)}}
	}
	return nil
}

// containsKind reports whether the type tree contains the given kind. Type
// cycles are rejected by the cycle check, which runs before any walk.
func containsKind(m *mir.Module, t mir.TypeId, kind mir.TypeKind) bool {
	if !m.ValidType(t) {
		return false
	}
	ty := &m.Types[t]
	if ty.Kind == kind {
		return true
	}
	switch ty.Kind {
	case mir.TypeOption, mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut,
		mir.TypeRawPtr, mir.TypeTable, mir.TypeID, mir.TypeTableView, mir.TypeTableMutView:
		return containsKind(m, ty.Elem, kind)
	case mir.TypeResult:
		return containsKind(m, ty.OK, kind) || containsKind(m, ty.Err, kind)
	case mir.TypeAggregate:
		for _, fld := range ty.Fields {
			if containsKind(m, fld.Type, kind) {
				return true
			}
		}
	case mir.TypeEnum:
		for _, v := range ty.Variants {
			if containsKind(m, v.Payload, kind) {
				return true
			}
		}
	case mir.TypeFunction:
		for _, p := range ty.Sig.Params {
			if containsKind(m, p, kind) {
				return true
			}
		}
		return containsKind(m, ty.Sig.Result, kind)
	}
	return false
}

// checkTypeCycle rejects named types that contain themselves transitively.
func checkTypeCycle(m *mir.Module, root mir.TypeId, t *mir.Type) []Error {
	if t.Name == "" {
		return nil
	}
	// DFS over named children; a cycle returns to root.
	var walk func(id mir.TypeId, path []string) bool
	walk = func(id mir.TypeId, path []string) bool {
		if !m.ValidType(id) {
			return false
		}
		ty := &m.Types[id]
		if ty.Kind == mir.TypeAggregate {
			for _, fld := range ty.Fields {
				if m.ValidType(fld.Type) && m.Types[fld.Type].Name != "" {
					if fld.Type == root {
						return true
					}
					if walk(fld.Type, path) {
						return true
					}
				}
			}
		}
		if ty.Kind == mir.TypeEnum {
			for _, v := range ty.Variants {
				if m.ValidType(v.Payload) && m.Types[v.Payload].Name != "" {
					if v.Payload == root {
						return true
					}
					if walk(v.Payload, path) {
						return true
					}
				}
			}
		}
		return false
	}
	if walk(root, nil) {
		return []Error{{Loc: typeLoc(m, root), Msg: "type contains itself"}}
	}
	return nil
}

func checkConst(m *mir.Module, c *mir.ConstDecl) []Error {
	loc := "const @" + c.Name
	if !m.ValidType(c.Type) {
		return []Error{{Loc: loc, Msg: "constant type out of range"}}
	}
	switch c.Value.Kind {
	case mir.ConstUnit:
		if c.Type != mir.TypeUnit {
			return []Error{{Loc: loc, Msg: "unit constant must have type unit"}}
		}
	case mir.ConstBool:
		if c.Type != mir.TypeBool {
			return []Error{{Loc: loc, Msg: "bool constant must have type bool"}}
		}
	case mir.ConstInt:
		if !mir.IsIntType(c.Type) {
			return []Error{{Loc: loc, Msg: "integer constant must have an integer type"}}
		}
		if !intFits(c.Type, c.Value.Int) {
			return []Error{{Loc: loc, Msg: fmt.Sprintf("integer constant %d out of range for %s", c.Value.Int, m.TypeString(c.Type))}}
		}
	case mir.ConstFloat:
		if !mir.IsFloatType(c.Type) {
			return []Error{{Loc: loc, Msg: "float constant must have type f32 or f64"}}
		}
		if c.Type == mir.TypeF32 {
			f := float64(float32(c.Value.Float))
			if f != c.Value.Float {
				return []Error{{Loc: loc, Msg: "float constant does not fit f32"}}
			}
		}
	case mir.ConstString:
		if c.Type != m.Slice(mir.TypeU8) {
			return []Error{{Loc: loc, Msg: "string constant must have type slice(u8)"}}
		}
	default:
		return []Error{{Loc: loc, Msg: fmt.Sprintf("unknown constant kind %d", c.Value.Kind)}}
	}
	return nil
}

func intFits(t mir.TypeId, v int64) bool {
	switch t {
	case mir.TypeI8:
		return v >= -128 && v <= 127
	case mir.TypeI16:
		return v >= -32768 && v <= 32767
	case mir.TypeI32:
		return v >= -2147483648 && v <= 2147483647
	case mir.TypeI64:
		return true
	case mir.TypeU8:
		return v >= 0 && v <= 255
	case mir.TypeU16:
		return v >= 0 && v <= 65535
	case mir.TypeU32:
		return v >= 0 && v <= 4294967295
	case mir.TypeU64:
		return v >= 0
	}
	return false
}
