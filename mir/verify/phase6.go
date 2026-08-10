package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase6Domains checks storage-domain nesting and reference escape rules:
// no use of storage after a dominating reset or destruction of its domain, no
// returned value that escapes function-local storage, child domains that
// cannot outlive their parents, destruction at most once per path, and reset
// marks that correspond to their domain.
//
// Derivation is tracked to a fixpoint: every value records the domain.create
// definitions its storage depends on (deps) and the allocation sites that
// introduced reference storage (roots). Handles loaded from places carry the
// deps of every stored value, so invalidation correlates through place
// aliasing.
// invalidation is one reset or destruction instruction with its position.
type invalidation struct {
	destroy bool
	handle  mir.ValueId
	mark    mir.ValueId
	blk     mir.BlockId
	in      int
}

func phase6Domains(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		dom := dominators(f)
		reach := reachable(f)
		info := computeDomainInfo(f)

		// Reset-mark correspondence and invalidation instruction list.
		var invals []invalidation
		for bi, b := range f.Blocks {
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				switch in.Op {
				case mir.OpDomainDestroy:
					invals = append(invals, invalidation{destroy: true, handle: in.Domain, blk: mir.BlockId(bi), in: ii})
				case mir.OpDomainReset:
					invals = append(invals, invalidation{handle: in.Domain, mark: in.Mark, blk: mir.BlockId(bi), in: ii})
					if !isMarkOf(f, in.Mark, in.Domain) {
						errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "reset mark does not correspond to the domain"})
					}
				}
			}
		}

		// Returned values must not escape function-local storage.
		for _, b := range f.Blocks {
			t := &b.Term
			if (t.Kind == mir.TermReturn || t.Kind == mir.TermFail) && t.Result != mir.NoValue && int(t.Result) < len(info) {
				if escapesLocal(info, info[t.Result]) {
					errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("%s of %s escapes storage from a function-local domain", t.Kind, valueName(f, t.Result))})
				}
			}
		}

		// Uses after a dominating reset or destruction.
		for _, u := range collectUses(f) {
			if int(u.value) >= len(info) || !reach[u.block] {
				continue
			}
			usePos := u.instr
			if usePos < 0 {
				usePos = len(f.Blocks[u.block].Instrs)
			}
			for _, iv := range invals {
				if !dominatesWithEdges(f, dom, iv.blk, iv.in, u.block, usePos) {
					continue
				}
				if iv.destroy {
					if depsIntersect(info, iv.handle, u.value) {
						errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("use of %s after destruction of its domain", valueName(f, u.value))})
						break
					}
				} else if resetInvalidates(m, f, dom, info, iv, u.value) {
					errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("use of %s after reset of its domain", valueName(f, u.value))})
					break
				}
			}
		}
	}
	return errs
}

// isMarkOf reports whether the mark value is defined by domain.mark on
// exactly the given handle value.
func isMarkOf(f *mir.Function, mark, handle mir.ValueId) bool {
	if int(mark) >= len(f.Values) {
		return false
	}
	def := f.Values[mark].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) {
		return false
	}
	b := f.Blocks[def.Block]
	if def.Instr < 0 || def.Instr >= len(b.Instrs) {
		return false
	}
	in := &b.Instrs[def.Instr]
	return in.Op == mir.OpDomainMark && in.Domain == handle
}

// depsIntersect reports whether the storage of value v depends on the same
// function-local domain as handle h. External (parameter) domains have no
// recorded deps and never invalidate.
func depsIntersect(info []domainInfo, h, v mir.ValueId) bool {
	if int(h) >= len(info) || int(v) >= len(info) || len(info[h].deps) == 0 {
		return false
	}
	for d := range info[h].deps {
		if info[v].deps[d] {
			return true
		}
	}
	return false
}

// resetInvalidates reports whether a reset invalidates a value: some
// allocation root of the value lives in the reset domain and was allocated
// after the mark.
func resetInvalidates(m *mir.Module, f *mir.Function, dom [][]bool, info []domainInfo, iv invalidation, v mir.ValueId) bool {
	if int(v) >= len(info) || len(info[iv.handle].deps) == 0 {
		return false
	}
	markDef := f.Values[iv.mark].Def
	for r := range info[v].roots {
		if !depsIntersect(info, iv.handle, r.handle) {
			continue
		}
		if dominatesWithEdges(f, dom, markDef.Block, markDef.Instr, r.allocBlk, r.allocIn) {
			return true
		}
	}
	return false
}

// escapesLocal reports whether a returned value contains reference storage
// allocated in a function-local domain. Roots whose handle comes from a
// parameter are caller-owned and may be returned.
func escapesLocal(info []domainInfo, inf domainInfo) bool {
	for r := range inf.roots {
		if int(r.handle) < len(info) && len(info[r.handle].deps) > 0 {
			return true
		}
	}
	return false
}

// defKey identifies one instruction by block and index.
type defKey struct {
	blk mir.BlockId
	in  int
}

// domainRoot is one allocation site that introduced reference storage.
type domainRoot struct {
	handle   mir.ValueId
	allocBlk mir.BlockId
	allocIn  int
}

// domainInfo records the storage derivation of one value.
type domainInfo struct {
	deps  map[defKey]bool
	roots map[domainRoot]bool
}

// computeDomainInfo runs the derivation fixpoint over all values of the
// function: function parameters are external; block parameters and local
// loads accumulate what was stored or passed into them; allocation
// instructions introduce roots; pass-through operations propagate.
func computeDomainInfo(f *mir.Function) []domainInfo {
	n := len(f.Values)
	info := make([]domainInfo, n)

	stored := make(map[mir.LocalId][]mir.ValueId)
	for _, b := range f.Blocks {
		for i := range b.Instrs {
			in := &b.Instrs[i]
			if in.Op == mir.OpStore {
				if l, ok := placeRootLocal(&in.Place); ok {
					stored[l] = append(stored[l], in.StoreVal)
				}
			}
		}
	}

	paramValue := make(map[[2]int]mir.ValueId)
	for vi, v := range f.Values {
		if v.Def.Kind == mir.ValueDefBlockParam {
			paramValue[[2]int{int(v.Def.Block), v.Def.Param}] = mir.ValueId(vi)
		}
	}
	paramEdges := make(map[mir.ValueId][]mir.ValueId)
	for bi, b := range f.Blocks {
		for pi := range b.Params {
			vid, ok := paramValue[[2]int{bi, pi}]
			if !ok {
				continue
			}
			for _, pred := range f.Blocks {
				if args := edgeArgsTo(f, pred, mir.BlockId(bi)); args != nil && pi < len(args) {
					paramEdges[vid] = append(paramEdges[vid], args[pi])
				}
			}
		}
	}

	changed := true
	for changed {
		changed = false
		for vi := range info {
			next := transfer(f, mir.ValueId(vi), &f.Values[vi], info, stored, paramEdges)
			if !sameInfo(next, info[vi]) {
				info[vi] = next
				changed = true
			}
		}
	}
	return info
}

func transfer(f *mir.Function, vid mir.ValueId, v *mir.Value, info []domainInfo,
	stored map[mir.LocalId][]mir.ValueId, paramEdges map[mir.ValueId][]mir.ValueId) domainInfo {

	empty := domainInfo{}
	merge := func(dst *domainInfo, src domainInfo) {
		for d := range src.deps {
			if dst.deps == nil {
				dst.deps = make(map[defKey]bool)
			}
			dst.deps[d] = true
		}
		for r := range src.roots {
			if dst.roots == nil {
				dst.roots = make(map[domainRoot]bool)
			}
			dst.roots[r] = true
		}
	}
	copyOf := func(src domainInfo) domainInfo {
		var out domainInfo
		merge(&out, src)
		return out
	}

	switch v.Def.Kind {
	case mir.ValueDefFuncParam:
		return empty

	case mir.ValueDefBlockParam:
		var out domainInfo
		for _, a := range paramEdges[vid] {
			if int(a) < len(info) {
				merge(&out, info[a])
			}
		}
		return out

	case mir.ValueDefSwitchCase:
		if int(v.Def.Block) < len(f.Blocks) {
			b := f.Blocks[v.Def.Block]
			if v.Def.Case >= 0 && v.Def.Case < len(b.Term.Cases) {
				if int(b.Term.Value) < len(info) {
					return info[b.Term.Value]
				}
			}
		}
		return empty

	case mir.ValueDefInstr:
		if int(v.Def.Block) >= len(f.Blocks) {
			return empty
		}
		b := f.Blocks[v.Def.Block]
		if v.Def.Instr < 0 || v.Def.Instr >= len(b.Instrs) {
			return empty
		}
		in := &b.Instrs[v.Def.Instr]
		switch in.Op {
		case mir.OpDomainCreate:
			out := copyOf(info[in.Domain])
			if out.deps == nil {
				out.deps = make(map[defKey]bool)
			}
			out.deps[defKey{blk: v.Def.Block, in: v.Def.Instr}] = true
			return out

		case mir.OpAlloc, mir.OpCopyToDomain, mir.OpTableCreate:
			out := copyOf(info[in.Domain])
			if out.roots == nil {
				out.roots = make(map[domainRoot]bool)
			}
			out.roots[domainRoot{handle: in.Domain, allocBlk: v.Def.Block, allocIn: v.Def.Instr}] = true
			return out

		case mir.OpLoad:
			if in.Place.Kind == mir.PlaceDeref {
				if int(in.Place.Deref) < len(info) {
					return info[in.Place.Deref]
				}
				return empty
			}
			if l, ok := placeRootLocal(&in.Place); ok {
				var out domainInfo
				for _, sv := range stored[l] {
					if int(sv) < len(info) {
						merge(&out, info[sv])
					}
				}
				return out
			}
			return empty

		case mir.OpAggregateConstruct:
			var out domainInfo
			for _, af := range in.AggFields {
				if int(af.Value) < len(info) {
					merge(&out, info[af.Value])
				}
			}
			return out

		case mir.OpEnumConstruct:
			if in.Payload != mir.NoValue && int(in.Payload) < len(info) {
				return info[in.Payload]
			}
			return empty

		case mir.OpEnumPayloadChecked:
			if int(in.EnumValue) < len(info) {
				return info[in.EnumValue]
			}
			return empty

		case mir.OpSliceIndexChecked, mir.OpSliceRangeChecked:
			if int(in.Slice) < len(info) {
				return info[in.Slice]
			}
			return empty

		case mir.OpTableLookup, mir.OpTableLookupMut:
			if int(in.Table) < len(info) {
				return info[in.Table]
			}
			return empty
		}
		return empty
	}
	return empty
}

func sameInfo(a, b domainInfo) bool {
	if len(a.deps) != len(b.deps) || len(a.roots) != len(b.roots) {
		return false
	}
	for d := range a.deps {
		if !b.deps[d] {
			return false
		}
	}
	for r := range a.roots {
		if !b.roots[r] {
			return false
		}
	}
	return true
}
