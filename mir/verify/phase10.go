package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase10Backend checks backend preconditions: alloc and table.create element
// types must be plain value types without handles, cleanup identifiers, table
// views, or raw pointers, recursively. Layout computation and ABI checks will
// grow here as the C backend matures.
func phase10Backend(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		for _, b := range f.Blocks {
			for i := range b.Instrs {
				in := &b.Instrs[i]
				loc := locInstr(f, b, i, in)
				switch in.Op {
				case mir.OpAlloc:
					for _, k := range []mir.TypeKind{mir.TypeDomainHandle, mir.TypeDomainMark,
						mir.TypeCleanupScope, mir.TypeCleanupID, mir.TypeTableView, mir.TypeTableMutView, mir.TypeRawPtr} {
						if containsKind(m, in.TypeOp, k) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("alloc element type may not contain %s", kindName(m, k))})
							break
						}
					}
				case mir.OpTableCreate:
					for _, k := range []mir.TypeKind{mir.TypeDomainHandle, mir.TypeDomainMark,
						mir.TypeCleanupScope, mir.TypeCleanupID, mir.TypeTableView, mir.TypeTableMutView, mir.TypeRawPtr} {
						if containsKind(m, in.TypeOp, k) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("table element type may not contain %s", kindName(m, k))})
							break
						}
					}
				}
			}
		}
	}
	return errs
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
	}
	return fmt.Sprintf("kind %d", k)
}
