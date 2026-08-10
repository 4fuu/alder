package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase9Pointers checks the safe/raw pointer boundary: raw_ptr values may only
// be consumed as FFI call arguments or returned at function boundaries. Any
// other use (stores, safe calls, block arguments, aggregates, arithmetic) is
// rejected.
func phase9Pointers(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		for _, u := range collectUses(f) {
			if int(u.value) >= len(f.Values) {
				continue
			}
			if !isRawPtrType(m, f.Values[u.value].Type) {
				continue
			}
			if rawUseAllowed(m, f, u) {
				continue
			}
			errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("raw pointer %s may only cross explicit unsafe boundaries", valueName(f, u.value))})
		}
	}
	return errs
}

func isRawPtrType(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && m.Types[t].Kind == mir.TypeRawPtr
}

// rawUseAllowed reports whether a use site of a raw pointer is an explicit
// boundary: an FFI call argument or a return/fail operand.
func rawUseAllowed(m *mir.Module, f *mir.Function, u useSite) bool {
	if u.instr < 0 {
		b := f.Blocks[u.block]
		return (b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail) && b.Term.Result == u.value
	}
	in := &f.Blocks[u.block].Instrs[u.instr]
	if in.Op == mir.OpFFICallUnsafe {
		for _, a := range in.Args {
			if a == u.value {
				return true
			}
		}
	}
	return false
}
