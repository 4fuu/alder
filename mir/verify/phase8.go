package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase8Tables checks generational table view discipline: every view value is
// produced by a table lookup, all of its uses stay in its access region (the
// defining block, or the case target block for switch bindings), exactly one
// table.view.end closes it after all other uses, and table.remove never runs
// while a view of the same table is active in its block.
func phase8Tables(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		uses := collectUses(f)
		for vi := range f.Values {
			v := &f.Values[vi]
			if !isViewType(m, v.Type) {
				continue
			}
			name := "%" + v.Name
			region, ok := viewRegion(f, v)
			if !ok {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("table view %s is not produced by a table lookup", name)})
				continue
			}
			endPos := -1
			ended := false
			for _, u := range uses {
				if u.value != mir.ValueId(vi) {
					continue
				}
				if u.block != region {
					errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("table view %s used outside its access region", name)})
					continue
				}
				usePos := u.instr
				if usePos < 0 {
					usePos = len(f.Blocks[u.block].Instrs)
				}
				isEnd := u.instr >= 0 && f.Blocks[u.block].Instrs[u.instr].Op == mir.OpTableViewEnd
				if isEnd {
					if ended {
						errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("table view %s is ended more than once", name)})
					}
					ended = true
					endPos = usePos
				} else {
					if endPos >= 0 && usePos > endPos {
						errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("table view %s is used after table.view.end", name)})
					}
				}
			}
			if !ended {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("table view %s is never ended", name)})
			}
		}

		// table.remove must not run while a view of the same table is active.
		for _, b := range f.Blocks {
			bi := blockIndexOf(f, b)
			for ri := range b.Instrs {
				in := &b.Instrs[ri]
				if in.Op != mir.OpTableRemove {
					continue
				}
				for vi := range f.Values {
					v := &f.Values[vi]
					if !isViewType(m, v.Type) {
						continue
					}
					region, ok := viewRegion(f, v)
					if !ok || region != bi {
						continue
					}
					tbl, ok := viewTable(m, f, v)
					if !ok || tbl != in.Table {
						continue
					}
					activeFrom := -1
					if v.Def.Kind == mir.ValueDefInstr {
						activeFrom = v.Def.Instr
					}
					if activeFrom >= ri {
						continue
					}
					// The view must not already be ended before the remove.
					endPos := -1
					for _, u := range uses {
						if u.value == mir.ValueId(vi) && u.block == region && u.instr >= 0 &&
							b.Instrs[u.instr].Op == mir.OpTableViewEnd {
							endPos = u.instr
						}
					}
					if endPos < 0 || endPos > ri {
						errs = append(errs, Error{Loc: locInstr(f, b, ri, in), Msg: fmt.Sprintf("table.remove runs while a view of the table is active (%s)", "%"+f.Values[vi].Name)})
					}
				}
			}
		}
	}
	return errs
}

func isViewType(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && (m.Types[t].Kind == mir.TypeTableView || m.Types[t].Kind == mir.TypeTableMutView)
}

// viewRegion returns the block where a view value may be used: its defining
// block, or the case target block when the view is a switch case binding.
func viewRegion(f *mir.Function, v *mir.Value) (mir.BlockId, bool) {
	switch v.Def.Kind {
	case mir.ValueDefInstr:
		if int(v.Def.Block) < len(f.Blocks) {
			return v.Def.Block, true
		}
	case mir.ValueDefSwitchCase:
		if int(v.Def.Block) < len(f.Blocks) {
			cases := f.Blocks[v.Def.Block].Term.Cases
			if v.Def.Case >= 0 && v.Def.Case < len(cases) {
				return cases[v.Def.Case].Target, true
			}
		}
	}
	return mir.NoBlock, false
}

// viewTable returns the table operand a view value was produced from: the
// lookup operand for instruction-defined views, or the lookup behind the
// switch operand for case-binding views.
func viewTable(m *mir.Module, f *mir.Function, v *mir.Value) (mir.ValueId, bool) {
	var in *mir.Instr
	switch v.Def.Kind {
	case mir.ValueDefInstr:
		if int(v.Def.Block) < len(f.Blocks) {
			b := f.Blocks[v.Def.Block]
			if v.Def.Instr >= 0 && v.Def.Instr < len(b.Instrs) {
				in = &b.Instrs[v.Def.Instr]
			}
		}
	case mir.ValueDefSwitchCase:
		if int(v.Def.Block) < len(f.Blocks) {
			b := f.Blocks[v.Def.Block]
			if int(b.Term.Value) < len(f.Values) {
				return viewTable(m, f, &f.Values[b.Term.Value])
			}
		}
	}
	if in != nil && (in.Op == mir.OpTableLookup || in.Op == mir.OpTableLookupMut) {
		return in.Table, true
	}
	return mir.NoValue, false
}
