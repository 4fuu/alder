package verify

import (
	"fmt"

	"github.com/4fuu/alder/mir"
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
		errs = append(errs, definiteLocalInitialization(m, f, g)...)
	}
	return errs
}

// definiteLocalInitialization is a forward must analysis over instruction
// boundaries. Reachable non-entry points start at the optimistic top set and
// converge downward by predecessor intersection. The empty entry state still
// prevents a loop backedge from initializing its own first iteration.
func definiteLocalInitialization(m *mir.Module, f *mir.Function, g *pointCFG) []Error {
	type initSet map[string]bool
	n := len(g.preds)
	succ := make([][]int, n)
	for v, ps := range g.preds {
		for _, p := range ps {
			succ[p] = append(succ[p], v)
		}
	}
	reach := make([]bool, n)
	entry := g.boundary[0][0]
	reach[entry] = true
	queue := []int{entry}
	for len(queue) != 0 {
		v := queue[0]
		queue = queue[1:]
		for _, s := range succ[v] {
			if !reach[s] {
				reach[s] = true
				queue = append(queue, s)
			}
		}
	}
	afterStore := make(map[int]*mir.Place)
	for bi, b := range f.Blocks {
		for i := range b.Instrs {
			if b.Instrs[i].Op == mir.OpStore {
				afterStore[g.boundary[bi][i+1]] = &b.Instrs[i].Place
			}
		}
	}
	universe := make(initSet)
	// Track only leaves that a load can observe. The full local universe can be
	// enormous in compiler-generated functions, while leaves that are never
	// loaded cannot affect this analysis or any diagnostic.
	for _, b := range f.Blocks {
		for i := range b.Instrs {
			in := &b.Instrs[i]
			if in.Op != mir.OpLoad {
				continue
			}
			key, keyOK := localPlaceKey(&in.Place)
			t, typeOK := m.PlaceType(f, &in.Place)
			if keyOK && typeOK {
				addInitializedLeaves(m, t, key, universe, nil)
			}
		}
	}
	state := make([]initSet, n)
	for v := 0; v < n; v++ {
		if reach[v] && v != entry {
			state[v] = cloneInitSet(universe)
		}
	}
	for changed := true; changed; {
		changed = false
		for v := 0; v < n; v++ {
			if !reach[v] || v == entry {
				continue
			}
			var next initSet
			for _, p := range g.preds[v] {
				if !reach[p] {
					continue
				}
				if next == nil {
					next = cloneInitSet(state[p])
				} else {
					for k := range next {
						if !state[p][k] {
							delete(next, k)
						}
					}
				}
			}
			if place := afterStore[v]; place != nil {
				if key, ok := localPlaceKey(place); ok {
					if t, typeOK := m.PlaceType(f, place); typeOK {
						if next == nil {
							next = make(initSet)
						}
						addInitializedLeaves(m, t, key, next, universe)
					}
				}
			}
			if !equalInitSet(next, state[v]) {
				state[v] = next
				changed = true
			}
		}
	}
	var errs []Error
	for bi, b := range f.Blocks {
		if !reach[g.boundary[bi][0]] {
			continue
		}
		for i := range b.Instrs {
			in := &b.Instrs[i]
			if in.Op != mir.OpLoad {
				continue
			}
			key, ok := localPlaceKey(&in.Place)
			t, typeOK := m.PlaceType(f, &in.Place)
			if ok && typeOK && !initializedLeaves(m, t, key, state[g.boundary[bi][i]]) {
				errs = append(errs, Error{Loc: locInstr(f, b, i, in), Msg: "load from local place that is not definitely initialized"})
			}
		}
	}
	return errs
}

func cloneInitSet(src map[string]bool) map[string]bool {
	dst := make(map[string]bool, len(src))
	for k := range src {
		dst[k] = true
	}
	return dst
}

func equalInitSet(a, b map[string]bool) bool {
	if len(a) != len(b) {
		return false
	}
	for k := range a {
		if !b[k] {
			return false
		}
	}
	return true
}

func localPlaceKey(p *mir.Place) (string, bool) {
	switch p.Kind {
	case mir.PlaceLocal:
		return fmt.Sprintf("%d", p.Local), true
	case mir.PlaceField:
		if p.Base == nil {
			return "", false
		}
		base, ok := localPlaceKey(p.Base)
		return base + "\x00" + p.Field, ok
	default:
		return "", false
	}
}

func addInitializedLeaves(m *mir.Module, t mir.TypeId, key string, set, filter map[string]bool) {
	ty := &m.Types[t]
	if ty.Kind != mir.TypeAggregate || len(ty.Fields) == 0 {
		if filter == nil || filter[key] {
			set[key] = true
		}
		return
	}
	for _, field := range ty.Fields {
		addInitializedLeaves(m, field.Type, key+"\x00"+field.Name, set, filter)
	}
}

func initializedLeaves(m *mir.Module, t mir.TypeId, key string, set map[string]bool) bool {
	ty := &m.Types[t]
	if ty.Kind != mir.TypeAggregate || len(ty.Fields) == 0 {
		return set[key]
	}
	for _, field := range ty.Fields {
		if !initializedLeaves(m, field.Type, key+"\x00"+field.Name, set) {
			return false
		}
	}
	return true
}

func availabilityError(f *mir.Function, u useSite, v *mir.Value) Error {
	return Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("use of %%%s is not dominated by its definition", v.Name)}
}
