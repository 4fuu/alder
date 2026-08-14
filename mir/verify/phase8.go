package verify

import (
	"fmt"
	"strings"

	"github.com/4fuu/alder/mir"
)

// A table origin is either a formal table parameter or a stable local site.
// Calls returning a newly-created table use the call site as their stable site.
type tableOrigin struct{ param, block, instr int }
type tableOrigins map[tableOrigin]bool

func isTableType(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && m.Types[t].Kind == mir.TypeTable
}

func placeLocalRoot(p *mir.Place) (mir.LocalId, bool) {
	if p == nil {
		return 0, false
	}
	if p.Kind == mir.PlaceLocal {
		return p.Local, true
	}
	if p.Kind == mir.PlaceField {
		return placeLocalRoot(p.Base)
	}
	return 0, false
}

// aliasingStores computes the store values that may feed each load. Places are
// immutable MIR structure, so every fixed-point analysis can share this work.
func aliasingStores(f *mir.Function) [][]mir.ValueId {
	type storedPlace struct {
		value mir.ValueId
		path  string
		ok    bool
	}
	stores := make(map[mir.LocalId][]storedPlace)
	var unknownStores []storedPlace
	var allStores []storedPlace
	for _, b := range f.Blocks {
		for j := range b.Instrs {
			s := &b.Instrs[j]
			if s.Op == mir.OpStore {
				path, ok := placePath(&s.Place)
				stored := storedPlace{value: s.StoreVal, path: path, ok: ok}
				allStores = append(allStores, stored)
				if root, rootOK := placeLocalRoot(&s.Place); rootOK {
					stores[root] = append(stores[root], stored)
				} else {
					unknownStores = append(unknownStores, stored)
				}
			}
		}
	}
	result := make([][]mir.ValueId, len(f.Values))
	for vi := range f.Values {
		v := &f.Values[vi]
		if v.Def.Kind != mir.ValueDefInstr {
			continue
		}
		in := &f.Blocks[v.Def.Block].Instrs[v.Def.Instr]
		if in.Op != mir.OpLoad {
			continue
		}
		loadPath, loadOK := placePath(&in.Place)
		var candidates []storedPlace
		if root, rootOK := placeLocalRoot(&in.Place); rootOK {
			candidates = append(candidates, unknownStores...)
			candidates = append(candidates, stores[root]...)
		} else {
			candidates = allStores
		}
		for _, store := range candidates {
			if !loadOK || !store.ok || loadPath == store.path ||
				strings.HasPrefix(loadPath, store.path+".") ||
				strings.HasPrefix(store.path, loadPath+".") {
				result[vi] = append(result[vi], store.value)
			}
		}
	}
	return result
}

func computeTableInfo(m *mir.Module, f *mir.Function, effects []functionEffect) []tableOrigins {
	info := make([]tableOrigins, len(f.Values))
	loadStores := aliasingStores(f)
	merge := func(dst tableOrigins, src tableOrigins) {
		for o := range src {
			dst[o] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for vi := range f.Values {
			v := &f.Values[vi]
			next := tableOrigins{}
			add := func(x mir.ValueId) {
				if int(x) < len(info) {
					merge(next, info[x])
				}
			}
			switch v.Def.Kind {
			case mir.ValueDefFuncParam:
				if containsKind(m, v.Type, mir.TypeTable) {
					next[tableOrigin{param: funcParamIndex(f, mir.ValueId(vi)), block: -1, instr: -1}] = true
				}
			case mir.ValueDefBlockParam:
				for _, p := range f.Blocks {
					for _, a := range allEdgeArgsTo(p, v.Def.Block) {
						if v.Def.Param < len(a) {
							add(a[v.Def.Param])
						}
					}
				}
			case mir.ValueDefSwitchCase:
				add(f.Blocks[v.Def.Block].Term.Value)
			case mir.ValueDefInstr:
				in := &f.Blocks[v.Def.Block].Instrs[v.Def.Instr]
				switch in.Op {
				case mir.OpTableCreate:
					next[tableOrigin{param: -1, block: int(v.Def.Block), instr: v.Def.Instr}] = true
				case mir.OpLoad:
					if root, ok := placeDerefRoot(&in.Place); ok {
						add(root)
					}
					for _, stored := range loadStores[vi] {
						add(stored)
					}
				case mir.OpAggregateConstruct:
					for _, x := range in.AggFields {
						add(x.Value)
					}
				case mir.OpEnumConstruct:
					add(in.Payload)
				case mir.OpEnumPayloadChecked:
					add(in.EnumValue)
				case mir.OpCall:
					if int(in.Callee) < len(effects) {
						e := effects[in.Callee]
						for p, yes := range e.tableResultFrom {
							if yes && p < len(in.Args) {
								add(in.Args[p])
							}
						}
						if e.tableResultLocal {
							next[tableOrigin{param: -1, block: int(v.Def.Block), instr: v.Def.Instr}] = true
						}
					}
				}
			}
			if len(next) != len(info[vi]) {
				info[vi] = next
				changed = true
				continue
			}
			for o := range next {
				if !info[vi][o] {
					info[vi] = next
					changed = true
					break
				}
			}
		}
	}
	return info
}

func originsOverlap(a, b tableOrigins) bool {
	for x := range a {
		for y := range b {
			if x == y || x.param >= 0 && y.param >= 0 {
				return true
			}
		}
	}
	return false
}

func phase8Tables(m *mir.Module) []Error {
	effects := computeFunctionEffects(m)
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		info := computeTableInfo(m, f, effects)
		uses := collectUses(f)
		cleanup, _ := analyzeCleanupFunction(m, f)
		// Returning a local/new table is deliberately represented by a stable call
		// site origin. This is conservative (different executions may alias only
		// with themselves) but never drops identity.
		for vi := range f.Values {
			v := &f.Values[vi]
			if !isLookupOption(m, v.Type) || v.Def.Kind != mir.ValueDefInstr {
				continue
			}
			b := f.Blocks[v.Def.Block]
			lookup := &b.Instrs[v.Def.Instr]
			if lookup.Op != mir.OpTableLookup && lookup.Op != mir.OpTableLookupMut {
				continue
			}
			consumers := []useSite{}
			for _, u := range uses {
				if u.value == mir.ValueId(vi) && u.block == v.Def.Block && (lookupSwitchConsumesSome(b, mir.ValueId(vi), u) || u.instr >= 0 && b.Instrs[u.instr].Op == mir.OpEnumPayloadChecked && b.Instrs[u.instr].Variant == "some") {
					consumers = append(consumers, u)
				}
			}
			if len(consumers) != 1 {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("table lookup result %%%s must be consumed exactly once by switch or checked some extraction", v.Name)})
				continue
			}
			end := len(b.Instrs)
			if consumers[0].instr >= 0 {
				end = consumers[0].instr
			}
			for i := v.Def.Instr + 1; i < end; i++ {
				if b.Instrs[i].FailTarget != mir.NoBlock {
					errs = append(errs, Error{Loc: locInstr(f, b, i, &b.Instrs[i]), Msg: fmt.Sprintf("checked failure edge may bypass consumption of table lookup result %%%s", v.Name)})
				}
				if mutationOf(m, f, b, i, info, effects, cleanup, info[lookup.Table]) {
					errs = append(errs, Error{Loc: locInstr(f, b, i, &b.Instrs[i]), Msg: fmt.Sprintf("table mutation runs before lookup result %%%s is consumed", v.Name)})
				}
			}
		}
		for vi := range f.Values {
			v := &f.Values[vi]
			if !isViewType(m, v.Type) {
				continue
			}
			region, source, start, ok := directView(f, v, info)
			if !ok {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("table view %%%s is not produced by a table lookup", v.Name)})
				continue
			}
			end := -1
			for _, u := range uses {
				if u.value != mir.ValueId(vi) {
					continue
				}
				if u.block != region {
					errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("table view %%%s used outside its access region", v.Name)})
					continue
				}
				isEnd := u.instr >= 0 && f.Blocks[region].Instrs[u.instr].Op == mir.OpTableViewEnd
				if isEnd {
					if end >= 0 {
						errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("table view %%%s is ended more than once", v.Name)})
					}
					end = u.instr
				} else if end >= 0 && (u.instr < 0 || u.instr > end) {
					errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("table view %%%s is used after table.view.end", v.Name)})
				}
			}
			if end < 0 {
				errs = append(errs, Error{Loc: locFunc(f), Msg: fmt.Sprintf("table view %%%s is never ended", v.Name)})
				continue
			}
			b := f.Blocks[region]
			for i := start + 1; i < end; i++ {
				if b.Instrs[i].FailTarget != mir.NoBlock {
					errs = append(errs, Error{Loc: locInstr(f, b, i, &b.Instrs[i]), Msg: fmt.Sprintf("checked failure edge may bypass table.view.end for %%%s", v.Name)})
				}
				if mutationOf(m, f, b, i, info, effects, cleanup, source) {
					errs = append(errs, Error{Loc: locInstr(f, b, i, &b.Instrs[i]), Msg: fmt.Sprintf("table mutation runs while a view of the table is active (%%%s)", v.Name)})
				}
			}
		}
	}
	return errs
}

func isLookupOption(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && m.Types[t].Kind == mir.TypeOption && isViewType(m, m.Types[t].Elem)
}
func isViewType(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && (m.Types[t].Kind == mir.TypeTableView || m.Types[t].Kind == mir.TypeTableMutView)
}

func lookupSwitchConsumesSome(b *mir.Block, value mir.ValueId, u useSite) bool {
	if u.instr >= 0 || b.Term.Kind != mir.TermSwitch || b.Term.Value != value {
		return false
	}
	for _, c := range b.Term.Cases {
		if c.Variant == "some" && c.Binding != mir.NoValue {
			return true
		}
	}
	return false
}

func directView(f *mir.Function, v *mir.Value, info []tableOrigins) (mir.BlockId, tableOrigins, int, bool) {
	if v.Def.Kind == mir.ValueDefSwitchCase {
		b := f.Blocks[v.Def.Block]
		if v.Def.Case < 0 || v.Def.Case >= len(b.Term.Cases) || b.Term.Cases[v.Def.Case].Variant != "some" || b.Term.Cases[v.Def.Case].Binding == mir.NoValue {
			return mir.NoBlock, nil, 0, false
		}
		opt := b.Term.Value
		if int(opt) < len(f.Values) {
			ov := &f.Values[opt]
			if ov.Def.Kind == mir.ValueDefInstr {
				in := &f.Blocks[ov.Def.Block].Instrs[ov.Def.Instr]
				if in.Op == mir.OpTableLookup || in.Op == mir.OpTableLookupMut {
					return b.Term.Cases[v.Def.Case].Target, info[in.Table], -1, true
				}
			}
		}
	}
	if v.Def.Kind == mir.ValueDefInstr {
		in := &f.Blocks[v.Def.Block].Instrs[v.Def.Instr]
		if in.Op == mir.OpEnumPayloadChecked && in.Variant == "some" {
			ov := &f.Values[in.EnumValue]
			if ov.Def.Kind == mir.ValueDefInstr {
				lk := &f.Blocks[ov.Def.Block].Instrs[ov.Def.Instr]
				if lk.Op == mir.OpTableLookup || lk.Op == mir.OpTableLookupMut {
					return v.Def.Block, info[lk.Table], v.Def.Instr, true
				}
			}
		}
	}
	return mir.NoBlock, nil, 0, false
}

func mutationOf(m *mir.Module, f *mir.Function, b *mir.Block, i int, info []tableOrigins, effects []functionEffect, cleanup *cleanupAnalysis, want tableOrigins) bool {
	in := &b.Instrs[i]
	if (in.Op == mir.OpTableInsert || in.Op == mir.OpTableRemove) && originsOverlap(info[in.Table], want) {
		return true
	}
	if in.Op == mir.OpCall && int(in.Callee) < len(effects) {
		for p, yes := range effects[in.Callee].tableMutates {
			if yes && p < len(in.Args) && originsOverlap(info[in.Args[p]], want) {
				return true
			}
		}
	}
	if in.Op == mir.OpCleanupScopeRun {
		for _, e := range cleanup.activeEntriesAtRun(cleanupSite{blockIndexOf(f, b), i}) {
			if int(e.Callback) < len(effects) {
				for p, yes := range effects[e.Callback].tableMutates {
					if yes && p < len(e.Args) && originsOverlap(info[e.Args[p]], want) {
						return true
					}
				}
			}
		}
	}
	return false
}
