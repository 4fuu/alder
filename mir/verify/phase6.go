package verify

import (
	"fmt"
	"strings"

	"github.com/4fuu/alder/mir"
)

type defKey struct {
	blk mir.BlockId
	in  int
}
type domainRoot struct {
	handle   mir.ValueId
	allocBlk mir.BlockId
	allocIn  int
	param    int
}
type domainInfo struct {
	deps map[defKey]bool
	// parents contains strict ancestor domain origins. deps is exact identity
	// (possibly several alternatives at a join); keeping these sets separate
	// prevents destroying a child from destroying its parent.
	parents map[defKey]bool
	roots   map[domainRoot]bool
	params  map[int]bool
}

type resourceState struct {
	dead         map[defKey]bool
	invalid      map[domainRoot]bool
	invalidMarks map[mir.ValueId]bool
}

func phase6Domains(m *mir.Module, effects []functionEffect, cleanups []*cleanupAnalysis, domainInfos [][]domainInfo) []Error {
	var errs []Error
	for fi, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		info := domainInfos[fi]
		errs = append(errs, rejectLoopCarriedLocals(m, f, info, effects[fi])...)
		var cleanup *cleanupAnalysis
		if fi < len(cleanups) {
			cleanup = cleanups[fi]
		}
		cfg := buildPointCFG(f)
		ins := solveResourceStates(m, f, info, effects, cleanup, cfg)
		reach := reachable(f)
		for bi, b := range f.Blocks {
			if !reach[bi] {
				continue
			}
			st := cloneResource(ins[bi])
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				loc := locInstr(f, b, ii, in)
				if in.Op == mir.OpStore {
					if _, deref := placeDerefRoot(&in.Place); deref {
						if stored, ok := f.ValueType(in.StoreVal); ok && typeRequiresLocalStore(m, stored) {
							errs = append(errs, Error{Loc: loc, Msg: "lifetime-bearing values may not be stored through dereference places in the current MIR profile"})
						}
					}
				}
				if in.Op == mir.OpCleanupScopeRun {
					errs = append(errs, checkAndApplyCleanupRun(m, f, mir.BlockId(bi), ii, info, effects, cleanup, cfg, &st)...)
				} else {
					for _, v := range instructionUses(in) {
						if valueInvalid(info, v, st) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("use of %s after reset or destruction of its domain", valueName(f, v))})
							break
						}
					}
					if (in.Op == mir.OpDomainDestroy || in.Op == mir.OpDomainReset) && domainDead(info, in.Domain, st) {
						errs = append(errs, Error{Loc: loc, Msg: "domain may already be destroyed on an incoming path"})
					}
					if in.Op == mir.OpDomainReset && !markMatches(info, f, in.Mark, in.Domain) {
						errs = append(errs, Error{Loc: loc, Msg: "reset mark does not correspond to the domain"})
					}
					applyResourceEffect(m, f, mir.BlockId(bi), ii, in, info, effects, cleanup, cfg, &st)
				}
			}
			if (b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail) && b.Term.Result != mir.NoValue {
				if valueInvalid(info, b.Term.Result, st) {
					errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("%s of invalid value %s", b.Term.Kind, valueName(f, b.Term.Result))})
				}
				if int(b.Term.Result) < len(info) && escapesLocal(info, info[b.Term.Result]) {
					errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("%s of %s escapes storage from a function-local domain", b.Term.Kind, valueName(f, b.Term.Result))})
				}
			}
		}
	}
	return errs
}

func solveResourceStates(m *mir.Module, f *mir.Function, info []domainInfo, effects []functionEffect, cleanup *cleanupAnalysis, cfg *pointCFG) []resourceState {
	in := make([]resourceState, len(f.Blocks))
	seen := make([]bool, len(f.Blocks))
	seen[0] = true
	queue := []mir.BlockId{0}
	queued := make([]bool, len(f.Blocks))
	queued[0] = true
	add := func(t mir.BlockId, s resourceState) {
		if int(t) >= len(in) {
			return
		}
		if mergeResource(&in[t], s) || !seen[t] {
			seen[t] = true
			if !queued[t] {
				queued[t] = true
				queue = append(queue, t)
			}
		}
	}
	for len(queue) > 0 {
		bi := queue[0]
		queue = queue[1:]
		queued[bi] = false
		st := cloneResource(in[bi])
		b := f.Blocks[bi]
		for ii := range b.Instrs {
			x := &b.Instrs[ii]
			if x.FailTarget != mir.NoBlock {
				add(x.FailTarget, st)
			}
			applyResourceEffect(m, f, bi, ii, x, info, effects, cleanup, cfg, &st)
		}
		switch b.Term.Kind {
		case mir.TermJump:
			add(b.Term.Target, st)
		case mir.TermBranch:
			add(b.Term.Then, st)
			add(b.Term.Else, st)
		case mir.TermSwitch:
			for _, c := range b.Term.Cases {
				add(c.Target, st)
			}
		}
	}
	return in
}

func applyResourceEffect(m *mir.Module, f *mir.Function, bi mir.BlockId, ii int, in *mir.Instr, info []domainInfo, effects []functionEffect, cleanup *cleanupAnalysis, cfg *pointCFG, st *resourceState) {
	kill := func(v mir.ValueId, reset bool, mark mir.ValueId) {
		applyDomainInvalidation(m, f, info, v, reset, mark, cfg, st)
	}
	switch in.Op {
	case mir.OpDomainCreate:
		ensureResource(st)
		delete(st.dead, defKey{blk: bi, in: ii})
	case mir.OpDomainMark:
		ensureResource(st)
		delete(st.invalidMarks, in.Result)
	case mir.OpAlloc, mir.OpAllocChecked, mir.OpCopyToDomain, mir.OpTableCreate:
		clearProducedRoots(info, in.Result, bi, ii, st)
	case mir.OpDomainDestroy:
		kill(in.Domain, false, mir.NoValue)
	case mir.OpDomainReset:
		kill(in.Domain, true, in.Mark)
	case mir.OpCall:
		if int(in.Callee) < len(effects) {
			for p, yes := range effects[in.Callee].destroys {
				if yes && p < len(in.Args) {
					kill(in.Args[p], false, mir.NoValue)
				}
			}
			for p, yes := range effects[in.Callee].resets {
				if yes && p < len(in.Args) {
					kill(in.Args[p], true, mir.NoValue)
				}
			}
			clearProducedRoots(info, in.Result, bi, ii, st)
		}
	case mir.OpCleanupScopeRun:
		sets := cleanup.activeEntrySetsAtRun(cleanupSite{bi, ii})
		if len(sets) == 0 {
			return
		}
		var merged resourceState
		for _, entries := range sets {
			branch := cloneResource(*st)
			for i := len(entries) - 1; i >= 0; i-- {
				applyCleanupEntryEffect(m, f, info, effects, entries[i], cfg, &branch)
			}
			mergeResource(&merged, branch)
		}
		*st = merged
	}
}

func applyCleanupEntryEffect(m *mir.Module, f *mir.Function, info []domainInfo, effects []functionEffect, e cleanupEntry, cfg *pointCFG, st *resourceState) {
	if int(e.Callback) >= len(effects) {
		return
	}
	for p, yes := range effects[e.Callback].destroys {
		if yes && p < len(e.Args) {
			applyDomainInvalidation(m, f, info, e.Args[p], false, mir.NoValue, cfg, st)
		}
	}
	for p, yes := range effects[e.Callback].resets {
		if yes && p < len(e.Args) {
			applyDomainInvalidation(m, f, info, e.Args[p], true, mir.NoValue, cfg, st)
		}
	}
}

func clearProducedRoots(info []domainInfo, result mir.ValueId, bi mir.BlockId, ii int, st *resourceState) {
	if result == mir.NoValue || int(result) >= len(info) {
		return
	}
	ensureResource(st)
	for r := range info[result].roots {
		if r.param < 0 && r.allocBlk == bi && r.allocIn == ii {
			delete(st.invalid, r)
		}
	}
}

func checkAndApplyCleanupRun(m *mir.Module, f *mir.Function, bi mir.BlockId, ii int, info []domainInfo, effects []functionEffect, cleanup *cleanupAnalysis, cfg *pointCFG, st *resourceState) []Error {
	loc := locInstr(f, f.Blocks[bi], ii, &f.Blocks[bi].Instrs[ii])
	var errs []Error
	seenErrors := make(map[string]bool)
	var merged resourceState
	sets := cleanup.activeEntrySetsAtRun(cleanupSite{blk: bi, in: ii})
	for _, entries := range sets {
		branch := cloneResource(*st)
		for i := len(entries) - 1; i >= 0; i-- {
			e := entries[i]
			for _, v := range e.Args {
				if valueInvalid(info, v, branch) {
					msg := fmt.Sprintf("cleanup callback uses %s after reset or destruction of its domain", valueName(f, v))
					if !seenErrors[msg] {
						errs = append(errs, Error{Loc: loc, Msg: msg})
						seenErrors[msg] = true
					}
					break
				}
			}
			if int(e.Callback) >= len(effects) {
				continue
			}
			effect := effects[e.Callback]
			for p, yes := range effect.destroys {
				if !yes || p >= len(e.Args) {
					continue
				}
				if domainDead(info, e.Args[p], branch) {
					msg := fmt.Sprintf("cleanup callback may destroy %s more than once", valueName(f, e.Args[p]))
					if !seenErrors[msg] {
						errs = append(errs, Error{Loc: loc, Msg: msg})
						seenErrors[msg] = true
					}
				}
				applyDomainInvalidation(m, f, info, e.Args[p], false, mir.NoValue, cfg, &branch)
			}
			for p, yes := range effect.resets {
				if yes && p < len(e.Args) {
					applyDomainInvalidation(m, f, info, e.Args[p], true, mir.NoValue, cfg, &branch)
				}
			}
		}
		mergeResource(&merged, branch)
	}
	if len(sets) != 0 {
		*st = merged
	}
	return errs
}

func applyDomainInvalidation(m *mir.Module, f *mir.Function, info []domainInfo, v mir.ValueId, reset bool, mark mir.ValueId, cfg *pointCFG, st *resourceState) {
	if int(v) >= len(info) {
		return
	}
	ensureResource(st)
	roots := allRoots(info)
	if !reset {
		for d := range info[v].deps {
			st.dead[d] = true
		}
		for r := range roots {
			if rootInDomain(info, r, v) {
				st.invalid[r] = true
			}
		}
		invalidateDomainMarks(f, info, v, st)
		return
	}
	md := markPoint(f, mark)
	for r := range roots {
		if rootInDomain(info, r, v) && rootAfterMark(cfg, r, md) {
			st.invalid[r] = true
		}
	}
	// Runtime table inserts and growth allocate storage that is not represented
	// by separate MIR values. The current MIR profile therefore conservatively invalidates every
	// table in the reset domain instead of allowing hidden post-mark storage to
	// survive through a stale table handle.
	for vi, value := range f.Values {
		if !containsKind(m, value.Type, mir.TypeTable) {
			continue
		}
		for r := range info[vi].roots {
			if rootInDomain(info, r, v) {
				st.invalid[r] = true
			}
		}
	}
	// A successful reset consumes all outstanding marks for this domain. This
	// matches the runtime epoch and prevents an unconditional MIR reset from
	// reaching a runtime-rejected, temporally stale mark.
	invalidateDomainMarks(f, info, v, st)
}

func invalidateDomainMarks(f *mir.Function, info []domainInfo, domain mir.ValueId, st *resourceState) {
	for vi := range f.Values {
		mark := mir.ValueId(vi)
		markDomain, ok := directMarkDomain(f, mark)
		if ok && domainsMayAlias(info, markDomain, domain) {
			st.invalidMarks[mark] = true
		}
	}
}

func directMarkDomain(f *mir.Function, mark mir.ValueId) (mir.ValueId, bool) {
	if int(mark) >= len(f.Values) {
		return mir.NoValue, false
	}
	d := f.Values[mark].Def
	if d.Kind != mir.ValueDefInstr || int(d.Block) >= len(f.Blocks) ||
		d.Instr < 0 || d.Instr >= len(f.Blocks[d.Block].Instrs) {
		return mir.NoValue, false
	}
	in := f.Blocks[d.Block].Instrs[d.Instr]
	return in.Domain, in.Op == mir.OpDomainMark
}

func domainsMayAlias(info []domainInfo, a, b mir.ValueId) bool {
	if int(a) >= len(info) || int(b) >= len(info) {
		return false
	}
	for x := range info[a].deps {
		for y := range info[b].deps {
			if domainDepsMayAlias(x, y) {
				return true
			}
		}
	}
	return false
}

// updateDomainInfo advances an analysis to the fixed point for the current
// function effects. Both the effects and domain facts are monotonic, so effect
// inference can retain this state instead of rebuilding every set from scratch
// on each interprocedural pass.
func updateDomainInfo(m *mir.Module, f *mir.Function, effects []functionEffect, info []domainInfo) {
	loadStores := aliasingStores(f)
	paramEdges := incomingEdgeArgs(f)
	changed := true
	for changed {
		changed = false
		for vi := range info {
			if transferDomain(m, f, mir.ValueId(vi), info, paramEdges, effects, loadStores, &info[vi]) {
				changed = true
			}
		}
	}
}

func transferDomain(m *mir.Module, f *mir.Function, vid mir.ValueId, info []domainInfo, edges map[mir.ValueId][]mir.ValueId, effects []functionEffect, loadStores [][]mir.ValueId, out *domainInfo) bool {
	v := &f.Values[vid]
	changed := false
	merge := func(x mir.ValueId) {
		if int(x) < len(info) {
			changed = mergeInfo(out, info[x]) || changed
		}
	}
	if v.Def.Kind == mir.ValueDefFuncParam {
		pindex := funcParamIndex(f, vid)
		changed = addParam(out, pindex) || changed
		if typeContainsRef(m, v.Type) {
			for p, x := range f.Params {
				if containsKind(m, x.Type, mir.TypeDomainHandle) {
					changed = addDep(out, defKey{blk: mir.NoBlock, in: p}) || changed
				}
			}
			changed = addRoot(out, domainRoot{handle: vid, param: pindex}) || changed
		}
		if containsKind(m, v.Type, mir.TypeDomainHandle) {
			changed = addDep(out, defKey{blk: mir.NoBlock, in: pindex}) || changed
		}
		return changed
	}
	if v.Def.Kind == mir.ValueDefBlockParam {
		for _, a := range edges[vid] {
			merge(a)
		}
		return changed
	}
	if v.Def.Kind == mir.ValueDefSwitchCase {
		if int(v.Def.Block) < len(f.Blocks) {
			merge(f.Blocks[v.Def.Block].Term.Value)
		}
		return changed
	}
	if v.Def.Kind != mir.ValueDefInstr || int(v.Def.Block) >= len(f.Blocks) {
		return changed
	}
	in := &f.Blocks[v.Def.Block].Instrs[v.Def.Instr]
	switch in.Op {
	case mir.OpDomainCreate:
		if int(in.Domain) < len(info) {
			for d := range info[in.Domain].deps {
				changed = addParent(out, d) || changed
			}
			for d := range info[in.Domain].parents {
				changed = addParent(out, d) || changed
			}
		}
		changed = addDep(out, defKey{v.Def.Block, v.Def.Instr}) || changed
	case mir.OpAlloc, mir.OpAllocChecked, mir.OpCopyToDomain, mir.OpTableCreate:
		merge(in.Domain)
		if in.Op == mir.OpCopyToDomain {
			merge(in.CopyVal)
		}
		changed = addRoot(out, domainRoot{handle: in.Domain, allocBlk: v.Def.Block, allocIn: v.Def.Instr, param: -1}) || changed
	case mir.OpLoad:
		if in.Place.Kind == mir.PlaceDeref {
			merge(in.Place.Deref)
		}
		for _, stored := range loadStores[vid] {
			merge(stored)
		}
	case mir.OpAggregateConstruct:
		for _, x := range in.AggFields {
			merge(x.Value)
		}
	case mir.OpEnumConstruct:
		merge(in.Payload)
	case mir.OpEnumPayloadChecked:
		merge(in.EnumValue)
	case mir.OpSliceIndexChecked, mir.OpSliceRangeChecked:
		merge(in.Slice)
	case mir.OpArrayIndexChecked:
		merge(in.Array)
	case mir.OpTableLookup, mir.OpTableLookupMut:
		merge(in.Table)
	case mir.OpCall:
		if int(in.Callee) < len(effects) {
			e := effects[in.Callee]
			for p, yes := range e.resultFrom {
				if yes && p < len(in.Args) {
					merge(in.Args[p])
				}
			}
			for p, yes := range e.resultAlloc {
				if yes && p < len(in.Args) {
					merge(in.Args[p])
					changed = addRoot(out, domainRoot{handle: in.Args[p], allocBlk: v.Def.Block, allocIn: v.Def.Instr, param: -1}) || changed
				}
			}
		}
	}
	return changed
}

func instructionUses(in *mir.Instr) []mir.ValueId { return instrValueOperands(in) }
func isDomainType(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && m.Types[t].Kind == mir.TypeDomainHandle
}
func typeContainsRef(m *mir.Module, t mir.TypeId) bool {
	return containsKind(m, t, mir.TypeSafeRef) || containsKind(m, t, mir.TypeSafeMut) ||
		containsKind(m, t, mir.TypeSlice) || containsKind(m, t, mir.TypeTable)
}
func typeRequiresLocalStore(m *mir.Module, t mir.TypeId) bool {
	for _, kind := range []mir.TypeKind{
		mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeSlice, mir.TypeTable,
		mir.TypeDomainHandle, mir.TypeDomainMark,
	} {
		if containsKind(m, t, kind) {
			return true
		}
	}
	return false
}
func addDep(i *domainInfo, d defKey) bool {
	if i.deps == nil {
		i.deps = map[defKey]bool{}
	}
	if i.deps[d] {
		return false
	}
	i.deps[d] = true
	return true
}
func addParent(i *domainInfo, d defKey) bool {
	if i.parents == nil {
		i.parents = map[defKey]bool{}
	}
	if i.parents[d] {
		return false
	}
	i.parents[d] = true
	return true
}
func addRoot(i *domainInfo, r domainRoot) bool {
	if i.roots == nil {
		i.roots = map[domainRoot]bool{}
	}
	if i.roots[r] {
		return false
	}
	i.roots[r] = true
	return true
}
func addParam(i *domainInfo, p int) bool {
	if i.params == nil {
		i.params = map[int]bool{}
	}
	if i.params[p] {
		return false
	}
	i.params[p] = true
	return true
}
func mergeInfo(a *domainInfo, b domainInfo) bool {
	changed := false
	for x := range b.deps {
		changed = addDep(a, x) || changed
	}
	for x := range b.parents {
		changed = addParent(a, x) || changed
	}
	for x := range b.roots {
		changed = addRoot(a, x) || changed
	}
	for x := range b.params {
		changed = addParam(a, x) || changed
	}
	return changed
}
func allRoots(info []domainInfo) map[domainRoot]bool {
	r := map[domainRoot]bool{}
	for _, i := range info {
		for x := range i.roots {
			r[x] = true
		}
	}
	return r
}
func rootInDomain(info []domainInfo, r domainRoot, v mir.ValueId) bool {
	if int(r.handle) >= len(info) || int(v) >= len(info) {
		return false
	}
	for d := range info[r.handle].deps {
		for candidate := range info[v].deps {
			if domainDepsMayAlias(d, candidate) {
				return true
			}
		}
	}
	for d := range info[r.handle].parents {
		for candidate := range info[v].deps {
			if domainDepsMayAlias(d, candidate) {
				return true
			}
		}
	}
	return false
}
func escapesLocal(info []domainInfo, i domainInfo) bool {
	for r := range i.roots {
		if r.param < 0 && int(r.handle) < len(info) {
			for d := range info[r.handle].deps {
				if d.blk != mir.NoBlock {
					return true
				}
			}
		}
	}
	return false
}
func valueInvalid(info []domainInfo, v mir.ValueId, s resourceState) bool {
	if int(v) >= len(info) {
		return false
	}
	if s.invalidMarks[v] {
		return true
	}
	if anyDomainDepDead(info[v].deps, s) || anyDomainDepDead(info[v].parents, s) {
		return true
	}
	for r := range info[v].roots {
		if s.invalid[r] {
			return true
		}
	}
	return false
}

func funcParamIndex(f *mir.Function, v mir.ValueId) int {
	// Function parameters are the leading ValueIds by MIR construction. Do not
	// use ValueDef.Param: AddFunction intentionally does not assign it.
	for i := range f.Params {
		if mir.ValueId(i) == v {
			return i
		}
	}
	return len(f.Params)
}

func incomingEdgeArgs(f *mir.Function) map[mir.ValueId][]mir.ValueId {
	out := make(map[mir.ValueId][]mir.ValueId)
	params := make([][]mir.ValueId, len(f.Blocks))
	for i, b := range f.Blocks {
		params[i] = make([]mir.ValueId, len(b.Params))
	}
	for vi, v := range f.Values {
		if v.Def.Kind == mir.ValueDefBlockParam && int(v.Def.Block) < len(params) && v.Def.Param < len(params[v.Def.Block]) {
			params[v.Def.Block][v.Def.Param] = mir.ValueId(vi)
		}
	}
	add := func(target mir.BlockId, args []mir.ValueId) {
		if int(target) >= len(params) {
			return
		}
		for i, src := range args {
			if i >= len(params[target]) {
				break
			}
			dst := params[target][i]
			out[dst] = append(out[dst], src)
		}
	}
	for _, b := range f.Blocks {
		for i := range b.Instrs {
			if t := b.Instrs[i].FailTarget; t != mir.NoBlock {
				add(t, b.Instrs[i].FailArgs)
			}
		}
		switch b.Term.Kind {
		case mir.TermJump:
			add(b.Term.Target, b.Term.Args)
		case mir.TermBranch:
			add(b.Term.Then, b.Term.ThenArgs)
			add(b.Term.Else, b.Term.ElseArgs)
		case mir.TermSwitch:
			for _, c := range b.Term.Cases {
				add(c.Target, c.Args)
			}
		}
	}
	return out
}

func allEdgeArgsTo(b *mir.Block, target mir.BlockId) [][]mir.ValueId {
	var out [][]mir.ValueId
	for i := range b.Instrs {
		if b.Instrs[i].FailTarget == target {
			out = append(out, b.Instrs[i].FailArgs)
		}
	}
	switch b.Term.Kind {
	case mir.TermJump:
		if b.Term.Target == target {
			out = append(out, b.Term.Args)
		}
	case mir.TermBranch:
		if b.Term.Then == target {
			out = append(out, b.Term.ThenArgs)
		}
		if b.Term.Else == target {
			out = append(out, b.Term.ElseArgs)
		}
	case mir.TermSwitch:
		for _, c := range b.Term.Cases {
			if c.Target == target {
				out = append(out, c.Args)
			}
		}
	}
	return out
}

func rejectLoopCarriedLocals(m *mir.Module, f *mir.Function, info []domainInfo, effect functionEffect) []Error {
	var errs []Error
	for bi, b := range f.Blocks {
		var reaches []bool
		for vi, v := range f.Values {
			if v.Def.Kind != mir.ValueDefBlockParam || int(v.Def.Block) != bi {
				continue
			}
			if reaches == nil {
				reaches = reachableFrom(f, mir.BlockId(bi))
			}
			for pi, p := range f.Blocks {
				if !reaches[pi] {
					continue
				}
				for _, args := range allEdgeArgsTo(p, mir.BlockId(bi)) {
					if v.Def.Param >= len(args) || int(args[v.Def.Param]) >= len(info) {
						continue
					}
					i := info[args[v.Def.Param]]
					local := false
					for d := range i.deps {
						local = local || d.blk != mir.NoBlock
					}
					for r := range i.roots {
						local = local || r.param < 0
					}
					if local {
						errs = append(errs, Error{Loc: locBlock(f, b), Msg: fmt.Sprintf("block parameter %s carries a function-local domain handle or reference across a backedge", valueName(f, mir.ValueId(vi)))})
					}
				}
			}
		}
	}
	for bi, b := range f.Blocks {
		if !inCycle(f, mir.BlockId(bi)) {
			continue
		}
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpStore || int(in.StoreVal) >= len(info) || !hasLocalDomainProvenance(info[in.StoreVal]) {
				continue
			}
			if stableParameterDomainLoopStore(m, f, info, effect, in) {
				continue
			}
			errs = append(errs, Error{
				Loc: locInstr(f, b, ii, in),
				Msg: fmt.Sprintf("store of %s carries a function-local domain handle or reference across a loop backedge", valueName(f, in.StoreVal)),
			})
		}
	}
	return errs
}

// stableParameterDomainLoopStore permits a mutable local descriptor to be
// updated in a loop when every dynamic allocation it can name belongs to an
// external domain that this function never resets or destroys through verified
// MIR effects. Repeated static allocation sites are safe in that case because
// every produced allocation remains live for the entire call. Local domains
// remain forbidden: their per-site C slots and dynamic identities must not be
// conflated across iterations. As elsewhere in the verifier, unsafe foreign
// code is responsible for honoring the declared safe boundary.
func stableParameterDomainLoopStore(m *mir.Module, f *mir.Function, info []domainInfo, effect functionEffect, in *mir.Instr) bool {
	if _, ok := localPlaceKey(&in.Place); !ok {
		return false
	}
	for _, yes := range effect.destroys {
		if yes {
			return false
		}
	}
	for _, yes := range effect.resets {
		if yes {
			return false
		}
	}
	valueInfo := info[in.StoreVal]
	for d := range valueInfo.deps {
		if d.blk != mir.NoBlock {
			return false
		}
	}
	localRoot := false
	for root := range valueInfo.roots {
		if root.param >= 0 {
			continue
		}
		localRoot = true
		if int(root.handle) >= len(info) {
			return false
		}
		handleInfo := info[root.handle]
		for d := range handleInfo.deps {
			if d.blk != mir.NoBlock {
				return false
			}
		}
		ownedByParameterDomain := false
		for p := range handleInfo.params {
			if p < 0 || p >= len(f.Params) || !isDomainType(m, f.Params[p].Type) {
				return false
			}
			ownedByParameterDomain = true
		}
		if !ownedByParameterDomain {
			return false
		}
	}
	return localRoot
}

func hasLocalDomainProvenance(i domainInfo) bool {
	for d := range i.deps {
		if d.blk != mir.NoBlock {
			return true
		}
	}
	for r := range i.roots {
		if r.param < 0 {
			return true
		}
	}
	return false
}
func domainDead(info []domainInfo, v mir.ValueId, s resourceState) bool {
	if int(v) >= len(info) {
		return false
	}
	return anyDomainDepDead(info[v].deps, s)
}
func anyDomainDepDead(deps map[defKey]bool, s resourceState) bool {
	for d := range deps {
		for dead := range s.dead {
			if domainDepsMayAlias(d, dead) {
				return true
			}
		}
	}
	return false
}
func domainDepsMayAlias(a, b defKey) bool {
	return a == b || a.blk == mir.NoBlock && b.blk == mir.NoBlock
}
func ensureResource(s *resourceState) {
	if s.dead == nil {
		s.dead = map[defKey]bool{}
	}
	if s.invalid == nil {
		s.invalid = map[domainRoot]bool{}
	}
	if s.invalidMarks == nil {
		s.invalidMarks = map[mir.ValueId]bool{}
	}
}
func cloneResource(s resourceState) resourceState {
	n := resourceState{}
	ensureResource(&n)
	for x := range s.dead {
		n.dead[x] = true
	}
	for x := range s.invalid {
		n.invalid[x] = true
	}
	for x := range s.invalidMarks {
		n.invalidMarks[x] = true
	}
	return n
}
func mergeResource(a *resourceState, b resourceState) bool {
	ensureResource(a)
	c := false
	for x := range b.dead {
		if !a.dead[x] {
			a.dead[x] = true
			c = true
		}
	}
	for x := range b.invalid {
		if !a.invalid[x] {
			a.invalid[x] = true
			c = true
		}
	}
	for x := range b.invalidMarks {
		if !a.invalidMarks[x] {
			a.invalidMarks[x] = true
			c = true
		}
	}
	return c
}
func markPoint(f *mir.Function, v mir.ValueId) defKey {
	if int(v) < len(f.Values) {
		d := f.Values[v].Def
		return defKey{d.Block, d.Instr}
	}
	return defKey{mir.NoBlock, -1}
}
func markMatches(info []domainInfo, f *mir.Function, mark, domain mir.ValueId) bool {
	markDomain, ok := directMarkDomain(f, mark)
	if !ok {
		return false
	}
	if int(markDomain) >= len(info) || int(domain) >= len(info) {
		return false
	}
	if len(info[markDomain].deps) != len(info[domain].deps) {
		return false
	}
	for k := range info[markDomain].deps {
		if !info[domain].deps[k] {
			return false
		}
	}
	return true
}
func rootAfterMark(g *pointCFG, r domainRoot, m defKey) bool {
	if m.blk == mir.NoBlock {
		return true
	}
	if g == nil || int(m.blk) >= len(g.boundary) || int(r.allocBlk) >= len(g.boundary) {
		return true
	}
	return g.dominates(g.boundary[r.allocBlk][r.allocIn], g.boundary[m.blk][m.in+1])
}
func placesMayAlias(a, b *mir.Place) bool {
	ka, oka := placePath(a)
	kb, okb := placePath(b)
	if !oka || !okb {
		return true
	}
	return ka == kb || strings.HasPrefix(ka, kb+".") || strings.HasPrefix(kb, ka+".")
}
func placePath(p *mir.Place) (string, bool) {
	if p == nil {
		return "", false
	}
	if p.Kind == mir.PlaceLocal {
		return fmt.Sprintf("%d", p.Local), true
	}
	if p.Kind == mir.PlaceField {
		b, ok := placePath(p.Base)
		return b + "." + p.Field, ok
	}
	return "", false
}
