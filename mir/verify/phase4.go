package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase4Dominance checks dominance and value availability: every use of a
// value must be dominated by its definition, with positional ordering inside
// one block, and switch case bindings may only be used in blocks dominated by
// the case target (or as arguments of their own case edge).
func phase4Dominance(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		g := buildPointCFG(f)
		reach := reachable(f)
		uses := collectUses(f)
		for _, u := range uses {
			if int(u.value) >= len(f.Values) || !reach[u.block] {
				continue
			}
			usePos := u.instr
			if usePos < 0 {
				usePos = len(f.Blocks[u.block].Instrs)
			}
			useNode := g.boundary[u.block][usePos]
			v := &f.Values[u.value]
			switch v.Def.Kind {
			case mir.ValueDefFuncParam:
				// Always available.
			case mir.ValueDefBlockParam:
				if !g.dom[useNode][g.boundary[v.Def.Block][0]] {
					errs = append(errs, availabilityError(f, u, v))
				}
			case mir.ValueDefInstr:
				// A checked result exists only at the success boundary after it.
				if !g.dom[useNode][g.boundary[v.Def.Block][v.Def.Instr+1]] {
					errs = append(errs, availabilityError(f, u, v))
				}
			case mir.ValueDefSwitchCase:
				// Arguments of the defining case's own edge are allowed.
				if u.block == v.Def.Block && u.swCase == v.Def.Case {
					continue
				}
				if int(v.Def.Block) >= len(f.Blocks) {
					continue
				}
				cases := f.Blocks[v.Def.Block].Term.Cases
				if v.Def.Case < 0 || v.Def.Case >= len(cases) {
					continue
				}
				defNode := g.edge[pointEdge{v.Def.Block, edgeSwitch, v.Def.Case}]
				if !g.dom[useNode][defNode] {
					errs = append(errs, availabilityError(f, u, v))
				}
			}
		}
	}
	return errs
}

func availabilityError(f *mir.Function, u useSite, v *mir.Value) Error {
	return Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("use of %%%s is not dominated by its definition", v.Name)}
}
