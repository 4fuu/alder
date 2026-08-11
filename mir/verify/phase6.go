package verify

import (
	"fmt"
	"strings"

	"github.com/4fuu/aster/mir"
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

func phase6Domains(m *mir.Module) []Error {
	effects := computeFunctionEffects(m)
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		info := computeDomainInfo(m, f, effects)
		errs = append(errs, rejectLoopCarriedLocals(f, info)...)
		cleanup, _ := analyzeCleanupFunction(m, f)
		ins := solveResourceStates(m, f, info, effects, cleanup)
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
							errs = append(errs, Error{Loc: loc, Msg: "lifetime-bearing values may not be stored through dereference places in MIR 1"})
						}
					}
				}
				if in.Op == mir.OpCleanupScopeRun {
					errs = append(errs, checkAndApplyCleanupRun(m, f, mir.BlockId(bi), ii, info, effects, cleanup, &st)...)
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
					applyResourceEffect(m, f, mir.BlockId(bi), ii, in, info, effects, cleanup, &st)
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

func solveResourceStates(m *mir.Module, f *mir.Function, info []domainInfo, effects []functionEffect, cleanup *cleanupAnalysis) []resourceState {
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
			applyResourceEffect(m, f, bi, ii, x, info, effects, cleanup, &st)
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

func applyResourceEffect(m *mir.Module, f *mir.Function, bi mir.BlockId, ii int, in *mir.Instr, info []domainInfo, effects []functionEffect, cleanup *cleanupAnalysis, st *resourceState) {
	kill := func(v mir.ValueId, reset bool, mark mir.ValueId) {
		applyDomainInvalidation(m, f, info, v, reset, mark, st)
	}
	switch in.Op {
	case mir.OpDomainCreate:
		ensureResource(st)
		delete(st.dead, defKey{blk: bi, in: ii})
	case mir.OpDomainMark:
		ensureResource(st)
		delete(st.invalidMarks, in.Result)
	case mir.OpAlloc, mir.OpCopyToDomain, mir.OpTableCreate:
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
				applyCleanupEntryEffect(m, f, info, effects, entries[i], &branch)
			}
			mergeResource(&merged, branch)
		}
		*st = merged
	}
}

func applyCleanupEntryEffect(m *mir.Module, f *mir.Function, info []domainInfo, effects []functionEffect, e cleanupEntry, st *resourceState) {
	if int(e.Callback) >= len(effects) {
		return
	}
	for p, yes := range effects[e.Callback].destroys {
		if yes && p < len(e.Args) {
			applyDomainInvalidation(m, f, info, e.Args[p], false, mir.NoValue, st)
		}
	}
	for p, yes := range effects[e.Callback].resets {
		if yes && p < len(e.Args) {
			applyDomainInvalidation(m, f, info, e.Args[p], true, mir.NoValue, st)
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

func checkAndApplyCleanupRun(m *mir.Module, f *mir.Function, bi mir.BlockId, ii int, info []domainInfo, effects []functionEffect, cleanup *cleanupAnalysis, st *resourceState) []Error {
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
				applyDomainInvalidation(m, f, info, e.Args[p], false, mir.NoValue, &branch)
			}
			for p, yes := range effect.resets {
				if yes && p < len(e.Args) {
					applyDomainInvalidation(m, f, info, e.Args[p], true, mir.NoValue, &branch)
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

func applyDomainInvalidation(m *mir.Module, f *mir.Function, info []domainInfo, v mir.ValueId, reset bool, mark mir.ValueId, st *resourceState) {
	if int(v) >= len(info) {
		return
	}
	ensureResource(st)
	if !reset {
		for d := range info[v].deps {
			st.dead[d] = true
		}
		for r := range allRoots(info) {
			if rootInDomain(info, r, v) {
				st.invalid[r] = true
			}
		}
		invalidateDomainMarks(f, info, v, st)
		return
	}
	md := markPoint(f, mark)
	for r := range allRoots(info) {
		if rootInDomain(info, r, v) && rootAfterMark(f, r, md) {
			st.invalid[r] = true
		}
	}
	// Runtime table inserts and growth allocate storage that is not represented
	// by separate MIR values. MIR 1 therefore conservatively invalidates every
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

func computeDomainInfo(m *mir.Module, f *mir.Function, effects []functionEffect) []domainInfo {
	info := make([]domainInfo, len(f.Values))
	paramEdges := make(map[mir.ValueId][]mir.ValueId)
	for vi, v := range f.Values {
		if v.Def.Kind == mir.ValueDefBlockParam {
			for _, p := range f.Blocks {
				for _, a := range allEdgeArgsTo(p, v.Def.Block) {
					if v.Def.Param >= len(a) {
						continue
					}
					paramEdges[mir.ValueId(vi)] = append(paramEdges[mir.ValueId(vi)], a[v.Def.Param])
				}
			}
		}
	}
	changed := true
	for changed {
		changed = false
		for vi := range info {
			n := transferDomain(m, f, mir.ValueId(vi), info, paramEdges, effects)
			if !sameInfo(n, info[vi]) {
				info[vi] = n
				changed = true
			}
		}
	}
	return info
}

func transferDomain(m *mir.Module, f *mir.Function, vid mir.ValueId, info []domainInfo, edges map[mir.ValueId][]mir.ValueId, effects []functionEffect) domainInfo {
	v := &f.Values[vid]
	var out domainInfo
	merge := func(x mir.ValueId) {
		if int(x) < len(info) {
			mergeInfo(&out, info[x])
		}
	}
	if v.Def.Kind == mir.ValueDefFuncParam {
		pindex := funcParamIndex(f, vid)
		out.params = map[int]bool{pindex: true}
		if typeContainsRef(m, v.Type) {
			for p, x := range f.Params {
				if containsKind(m, x.Type, mir.TypeDomainHandle) {
					addDep(&out, defKey{blk: mir.NoBlock, in: p})
				}
			}
			out.roots = map[domainRoot]bool{{handle: vid, param: pindex}: true}
		}
		if containsKind(m, v.Type, mir.TypeDomainHandle) {
			addDep(&out, defKey{blk: mir.NoBlock, in: pindex})
		}
		return out
	}
	if v.Def.Kind == mir.ValueDefBlockParam {
		for _, a := range edges[vid] {
			merge(a)
		}
		return out
	}
	if v.Def.Kind == mir.ValueDefSwitchCase {
		if int(v.Def.Block) < len(f.Blocks) {
			merge(f.Blocks[v.Def.Block].Term.Value)
		}
		return out
	}
	if v.Def.Kind != mir.ValueDefInstr || int(v.Def.Block) >= len(f.Blocks) {
		return out
	}
	in := &f.Blocks[v.Def.Block].Instrs[v.Def.Instr]
	switch in.Op {
	case mir.OpDomainCreate:
		if int(in.Domain) < len(info) {
			for d := range info[in.Domain].deps {
				addParent(&out, d)
			}
			for d := range info[in.Domain].parents {
				addParent(&out, d)
			}
		}
		addDep(&out, defKey{v.Def.Block, v.Def.Instr})
	case mir.OpAlloc, mir.OpCopyToDomain, mir.OpTableCreate:
		merge(in.Domain)
		if in.Op == mir.OpCopyToDomain {
			merge(in.CopyVal)
		}
		addRoot(&out, domainRoot{handle: in.Domain, allocBlk: v.Def.Block, allocIn: v.Def.Instr, param: -1})
	case mir.OpLoad:
		if in.Place.Kind == mir.PlaceDeref {
			merge(in.Place.Deref)
		}
		for _, b := range f.Blocks {
			for j := range b.Instrs {
				s := &b.Instrs[j]
				if s.Op == mir.OpStore && placesMayAlias(&in.Place, &s.Place) {
					merge(s.StoreVal)
				}
			}
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
					addRoot(&out, domainRoot{handle: in.Args[p], allocBlk: v.Def.Block, allocIn: v.Def.Instr, param: -1})
				}
			}
		}
	}
	return out
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
func addDep(i *domainInfo, d defKey) {
	if i.deps == nil {
		i.deps = map[defKey]bool{}
	}
	i.deps[d] = true
}
func addParent(i *domainInfo, d defKey) {
	if i.parents == nil {
		i.parents = map[defKey]bool{}
	}
	i.parents[d] = true
}
func addRoot(i *domainInfo, r domainRoot) {
	if i.roots == nil {
		i.roots = map[domainRoot]bool{}
	}
	i.roots[r] = true
}
func mergeInfo(a *domainInfo, b domainInfo) {
	for x := range b.deps {
		addDep(a, x)
	}
	for x := range b.parents {
		addParent(a, x)
	}
	for x := range b.roots {
		addRoot(a, x)
	}
	if len(b.params) > 0 && a.params == nil {
		a.params = map[int]bool{}
	}
	for x := range b.params {
		a.params[x] = true
	}
}
func sameInfo(a, b domainInfo) bool {
	if len(a.deps) != len(b.deps) || len(a.parents) != len(b.parents) || len(a.roots) != len(b.roots) || len(a.params) != len(b.params) {
		return false
	}
	for x := range a.deps {
		if !b.deps[x] {
			return false
		}
	}
	for x := range a.parents {
		if !b.parents[x] {
			return false
		}
	}
	for x := range a.roots {
		if !b.roots[x] {
			return false
		}
	}
	for x := range a.params {
		if !b.params[x] {
			return false
		}
	}
	return true
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

func rejectLoopCarriedLocals(f *mir.Function, info []domainInfo) []Error {
	var errs []Error
	for bi, b := range f.Blocks {
		for vi, v := range f.Values {
			if v.Def.Kind != mir.ValueDefBlockParam || int(v.Def.Block) != bi {
				continue
			}
			for pi, p := range f.Blocks {
				if !canReachBlock(f, mir.BlockId(bi), mir.BlockId(pi)) {
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
			errs = append(errs, Error{
				Loc: locInstr(f, b, ii, in),
				Msg: fmt.Sprintf("store of %s carries a function-local domain handle or reference across a loop backedge", valueName(f, in.StoreVal)),
			})
		}
	}
	return errs
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
func rootAfterMark(f *mir.Function, r domainRoot, m defKey) bool {
	if m.blk == mir.NoBlock {
		return true
	}
	g := buildPointCFG(f)
	if int(m.blk) >= len(g.boundary) || int(r.allocBlk) >= len(g.boundary) {
		return true
	}
	return g.dom[g.boundary[r.allocBlk][r.allocIn]][g.boundary[m.blk][m.in+1]]
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
