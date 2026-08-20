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
				if !g.dominates(useNode, g.boundary[v.Def.Block][0]) {
					errs = append(errs, availabilityError(f, u, v))
				}
			case mir.ValueDefInstr:
				// A checked result exists only at the success boundary after it.
				if !g.dominates(useNode, g.boundary[v.Def.Block][v.Def.Instr+1]) {
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
				if !g.dominates(useNode, defNode) {
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
	leafIndex := make(map[string]int)
	// Track only leaves that a load can observe. The full local universe can be
	// enormous in compiler-generated functions, while leaves that are never
	// loaded cannot affect this analysis or any diagnostic.
	for _, b := range f.Blocks {
		for i := range b.Instrs {
			in := &b.Instrs[i]
			if in.Op != mir.OpLoad && in.Op != mir.OpBorrow && in.Op != mir.OpBorrowMut {
				continue
			}
			key, keyOK := localPlaceKey(&in.Place)
			t, typeOK := m.PlaceType(f, &in.Place)
			if keyOK && typeOK {
				indexInitializedLeaves(m, t, key, leafIndex)
			}
		}
	}
	words := (len(leafIndex) + 63) / 64
	universe := make([]uint64, words)
	for i := 0; i < len(leafIndex); i++ {
		universe[i/64] |= uint64(1) << uint(i%64)
	}
	afterStore := make(map[int][]uint64)
	for bi, b := range f.Blocks {
		for i := range b.Instrs {
			in := &b.Instrs[i]
			if in.Op != mir.OpStore {
				continue
			}
			key, keyOK := localPlaceKey(&in.Place)
			t, typeOK := m.PlaceType(f, &in.Place)
			if keyOK && typeOK {
				bits := make([]uint64, words)
				setInitializedLeafBits(m, t, key, leafIndex, bits)
				afterStore[g.boundary[bi][i+1]] = bits
			}
		}
	}
	state := make([][]uint64, n)
	for v := 0; v < n; v++ {
		if reach[v] && v != entry {
			state[v] = append([]uint64(nil), universe...)
		}
	}
	for changed := true; changed; {
		changed = false
		for v := 0; v < n; v++ {
			if !reach[v] || v == entry {
				continue
			}
			var next []uint64
			havePred := false
			for _, p := range g.preds[v] {
				if !reach[p] {
					continue
				}
				if !havePred {
					next = make([]uint64, words)
					copy(next, state[p])
					havePred = true
				} else {
					for i := range next {
						if i < len(state[p]) {
							next[i] &= state[p][i]
						} else {
							next[i] = 0
						}
					}
				}
			}
			if added := afterStore[v]; added != nil {
				if next == nil {
					next = make([]uint64, words)
				}
				for i := range next {
					next[i] |= added[i]
				}
			}
			if !equalInitBits(next, state[v]) {
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
			if in.Op != mir.OpLoad && in.Op != mir.OpBorrow && in.Op != mir.OpBorrowMut {
				continue
			}
			key, ok := localPlaceKey(&in.Place)
			t, typeOK := m.PlaceType(f, &in.Place)
			if ok && typeOK && !initializedLeafBits(m, t, key, leafIndex, state[g.boundary[bi][i]]) {
				errs = append(errs, Error{Loc: locInstr(f, b, i, in), Msg: "load from local place that is not definitely initialized"})
			}
		}
	}
	return errs
}

func indexInitializedLeaves(m *mir.Module, t mir.TypeId, key string, indexes map[string]int) {
	ty := &m.Types[t]
	if ty.Kind != mir.TypeAggregate || len(ty.Fields) == 0 {
		if _, ok := indexes[key]; !ok {
			indexes[key] = len(indexes)
		}
		return
	}
	for _, field := range ty.Fields {
		indexInitializedLeaves(m, field.Type, key+"\x00"+field.Name, indexes)
	}
}

func setInitializedLeafBits(m *mir.Module, t mir.TypeId, key string, indexes map[string]int, bits []uint64) {
	ty := &m.Types[t]
	if ty.Kind != mir.TypeAggregate || len(ty.Fields) == 0 {
		if i, ok := indexes[key]; ok {
			bits[i/64] |= uint64(1) << uint(i%64)
		}
		return
	}
	for _, field := range ty.Fields {
		setInitializedLeafBits(m, field.Type, key+"\x00"+field.Name, indexes, bits)
	}
}

func initializedLeafBits(m *mir.Module, t mir.TypeId, key string, indexes map[string]int, bits []uint64) bool {
	ty := &m.Types[t]
	if ty.Kind != mir.TypeAggregate || len(ty.Fields) == 0 {
		i, ok := indexes[key]
		return !ok || i/64 < len(bits) && bits[i/64]&(uint64(1)<<uint(i%64)) != 0
	}
	for _, field := range ty.Fields {
		if !initializedLeafBits(m, field.Type, key+"\x00"+field.Name, indexes, bits) {
			return false
		}
	}
	return true
}

func equalInitBits(a, b []uint64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
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
