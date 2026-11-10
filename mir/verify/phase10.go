package verify

import (
	"fmt"
	"strings"

	"github.com/4fuu/alder/mir"
)

// phase10Backend checks backend preconditions: alloc and table.create element
// types must be plain value types without handles, cleanup identifiers, table
// views, or raw pointers, recursively. Layout computation and ABI checks will
// grow here as the C backend matures.
func phase10Backend(m *mir.Module) []Error {
	var errs []Error
	envRecords := closureEnvRecords(m)
	for i := range m.Imports {
		if !validCExternalName(m.Imports[i].Name) {
			errs = append(errs, Error{
				Loc: "import @" + m.Imports[i].Name,
				Msg: "C symbol must be a non-reserved C identifier",
			})
		}
	}
	for bi := range m.Bindings {
		block := &m.Bindings[bi]
		for i := range block.Funcs {
			if !validCBindingName(block.Funcs[i].CName) {
				errs = append(errs, Error{
					Loc: fmt.Sprintf("binding @%s function @%s", block.Name, block.Funcs[i].Name),
					Msg: "C spelling must be a non-reserved C identifier",
				})
			}
		}
		for i := range block.Consts {
			if !validCBindingName(block.Consts[i].CName) {
				errs = append(errs, Error{
					Loc: fmt.Sprintf("binding @%s constant @%s", block.Name, block.Consts[i].Name),
					Msg: "C spelling must be a non-reserved C identifier",
				})
			}
		}
		for _, id := range block.Types {
			errs = append(errs, checkCSpelling(m, block.Name, id)...)
		}
	}
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		for _, b := range f.Blocks {
			for i := range b.Instrs {
				in := &b.Instrs[i]
				loc := locInstr(f, b, i, in)
				switch in.Op {
				case mir.OpAlloc, mir.OpAllocChecked:
					for _, k := range []mir.TypeKind{mir.TypeDomainHandle, mir.TypeDomainMark,
						mir.TypeCleanupScope, mir.TypeCleanupID, mir.TypeTableView, mir.TypeTableMutView,
						mir.TypeRawPtr, mir.TypeCRaw, mir.TypeCPtr, mir.TypeCConstPtr, mir.TypeCNamed} {
						// A closure environment record records the domain
						// that owns it; the retain hook rewrites that field
						// when the record moves domains.
						if k == mir.TypeDomainHandle && envRecords[in.TypeOp] {
							continue
						}
						if containsKind(m, in.TypeOp, k) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("alloc element type may not contain %s", kindName(m, k))})
							break
						}
					}
				case mir.OpTableCreate:
					for _, k := range []mir.TypeKind{mir.TypeDomainHandle, mir.TypeDomainMark,
						mir.TypeCleanupScope, mir.TypeCleanupID, mir.TypeTableView, mir.TypeTableMutView,
						mir.TypeRawPtr, mir.TypeCRaw, mir.TypeCPtr, mir.TypeCConstPtr, mir.TypeCNamed} {
						if containsKind(m, in.TypeOp, k) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("table element type may not contain %s", kindName(m, k))})
							break
						}
					}
				case mir.OpCopyToDomain:
					t, ok := f.ValueType(in.CopyVal)
					if !ok {
						break
					}
					for _, k := range []mir.TypeKind{mir.TypeDomainHandle, mir.TypeDomainMark,
						mir.TypeCleanupScope, mir.TypeCleanupID, mir.TypeTable, mir.TypeTableView,
						mir.TypeTableMutView, mir.TypeRawPtr, mir.TypeCRaw, mir.TypeCPtr, mir.TypeCConstPtr, mir.TypeCNamed} {
						if containsKind(m, t, k) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("copy_to_domain source type may not contain %s", kindName(m, k))})
							break
						}
					}
				}
			}
		}
	}
	return errs
}

func validCExternalName(name string) bool {
	if name == "" || name[0] == '_' {
		return false
	}
	if len(name) >= 6 && (name[:6] == "alder_" || name[:6] == "ALDER_") ||
		len(name) >= 5 && name[:5] == "Alder" {
		return false
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		letter := c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
		if (i == 0 && !letter) || (i > 0 && !letter && !(c >= '0' && c <= '9')) {
			return false
		}
	}
	return !cKeywords[name] && !cHeaderIdentifier(name)
}

// validCBindingName validates a C spelling that appears in a binding block.
// Unlike emitted declarations, binding spellings only reference C names, so
// header-owned names such as time_t or FILE and macro-style constants such as
// CLOCKS_PER_SEC are legal; a wrong spelling is caught by the generated
// probes rather than a name policy. Still rejected: the empty name, a leading
// underscore (implementation namespace), non-identifier characters, C
// keywords, and the alder_-prefixed runtime namespace.
func validCBindingName(name string) bool {
	if name == "" || name[0] == '_' {
		return false
	}
	if len(name) >= 6 && (name[:6] == "alder_" || name[:6] == "ALDER_") ||
		len(name) >= 5 && name[:5] == "Alder" {
		return false
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		letter := c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
		if (i == 0 && !letter) || (i > 0 && !letter && !(c >= '0' && c <= '9')) {
			return false
		}
	}
	return !cKeywords[name]
}

// cHeaderIdentifier rejects names which occupy the ordinary identifier or
// macro namespace in headers included by every generated translation unit.
// The *_t suffix is deliberately conservative: it covers the exact-width and
// implementation-defined typedef families exposed by stddef.h/stdint.h.
func cHeaderIdentifier(name string) bool {
	if strings.HasSuffix(name, "_t") {
		return true
	}
	if cHeaderNames[name] {
		return true
	}
	macroStyle := name[0] >= 'A' && name[0] <= 'Z'
	for i := 1; macroStyle && i < len(name); i++ {
		c := name[i]
		macroStyle = c == '_' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9'
	}
	if macroStyle {
		return true
	}
	switch name {
	case "bool", "true", "false", "NULL", "offsetof":
		return true
	}
	return false
}

var cHeaderNames = map[string]bool{
	"main": true,
	// C11 string.h functions. Generated modules include string.h for memcpy.
	"memchr": true, "memcmp": true, "memcpy": true, "memmove": true,
	"memset": true, "strcat": true, "strchr": true, "strcmp": true,
	"strcoll": true, "strcpy": true, "strcspn": true, "strerror": true,
	"strlen": true, "strncat": true, "strncmp": true, "strncpy": true,
	"strpbrk": true, "strrchr": true, "strspn": true, "strstr": true,
	"strtok": true, "strxfrm": true,
}

var cKeywords = map[string]bool{
	"_Alignas": true, "_Alignof": true, "_Atomic": true, "_Bool": true,
	"_Complex": true, "_Generic": true, "_Imaginary": true, "_Noreturn": true,
	"_Static_assert": true, "_Thread_local": true, "auto": true, "break": true,
	"case": true, "char": true, "const": true, "continue": true, "default": true,
	"do": true, "double": true, "else": true, "enum": true, "extern": true,
	"float": true, "for": true, "goto": true, "if": true, "inline": true,
	"int": true, "long": true, "register": true, "restrict": true, "return": true,
	"short": true, "signed": true, "sizeof": true, "static": true, "struct": true,
	"switch": true, "typedef": true, "union": true, "unsigned": true, "void": true,
	"volatile": true, "while": true,
}

func kindName(m *mir.Module, k mir.TypeKind) string {
	switch k {
	case mir.TypeDomainHandle:
		return "domain_handle"
	case mir.TypeDomainMark:
		return "domain_mark"
	case mir.TypeCleanupScope:
		return "cleanup_scope"
	case mir.TypeCleanupID:
		return "cleanup_id"
	case mir.TypeTableView:
		return "table_view"
	case mir.TypeTableMutView:
		return "table_mut_view"
	case mir.TypeRawPtr:
		return "raw_ptr"
	case mir.TypeTable:
		return "table"
	}
	return fmt.Sprintf("kind %d", k)
}

// checkCSpelling validates a C binding type spelling: an identifier, or a
// struct/union/enum tag form.
func checkCSpelling(m *mir.Module, blockName string, id mir.TypeId) []Error {
	if !m.ValidType(id) || m.Types[id].Kind != mir.TypeCNamed {
		return nil
	}
	ty := &m.Types[id]
	loc := fmt.Sprintf("binding @%s type @%s", blockName, ty.Name)
	spelling := ty.CName
	keyword := ""
	for _, k := range []string{"struct", "union", "enum"} {
		if strings.HasPrefix(spelling, k+" ") {
			keyword = k
			spelling = spelling[len(k)+1:]
			break
		}
	}
	if keyword != "" && ty.CClass == mir.CClassScalar {
		return []Error{{Loc: loc, Msg: "scalar binding spelling may not use a " + keyword + " tag form"}}
	}
	if !validCBindingName(spelling) {
		return []Error{{Loc: loc, Msg: "C spelling must be a non-reserved C identifier"}}
	}
	for i, fld := range ty.Fields {
		if !validCBindingName(fld.CName) {
			return []Error{{Loc: fmt.Sprintf("%s field %d", loc, i), Msg: "C field spelling must be a non-reserved C identifier"}}
		}
	}
	return nil
}
