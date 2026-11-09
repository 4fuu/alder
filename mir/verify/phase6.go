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
	envRecords := closureEnvRecords(m)
	for fi, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		info := domainInfos[fi]
		errs = append(errs, rejectLoopCarriedLocals(m, f, info, effects[fi], effects, envRecords)...)
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
						if stored, ok := f.ValueType(in.StoreVal); ok && typeRequiresLocalStore(m, stored, envRecords) {
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
	free := provenanceFreeTypes(m)
	changed := true
	for changed {
		changed = false
		for vi := range info {
			if transferDomain(m, f, mir.ValueId(vi), info, paramEdges, effects, loadStores, free, &info[vi]) {
				changed = true
			}
		}
	}
}

// provenanceFreeTypes memoizes, per module type, whether a value of that type
// can carry storage-domain provenance at all. A type is provenance-free when
// it contains no slice, view, reference, pointer, handle, vec, table, string,
// bytes, or function part at any depth: loading such a value copies plain
// bits with no lifetime tie to the storage it was read from.
func provenanceFreeTypes(m *mir.Module) []bool {
	free := make([]bool, len(m.Types))
	visiting := make([]bool, len(m.Types))
	var walk func(t mir.TypeId) bool
	walk = func(t mir.TypeId) bool {
		if !m.ValidType(t) {
			return false
		}
		if free[t] {
			return true
		}
		if visiting[t] {
			return false
		}
		visiting[t] = true
		ok := false
		switch m.Types[t].Kind {
		case mir.TypeOption, mir.TypeArray:
			ok = walk(m.Types[t].Elem)
		case mir.TypeResult:
			ok = walk(m.Types[t].OK) && walk(m.Types[t].Err)
		case mir.TypeAggregate:
			ok = true
			for _, fld := range m.Types[t].Fields {
				if !walk(fld.Type) {
					ok = false
					break
				}
			}
		case mir.TypeEnum:
			ok = true
			for _, v := range m.Types[t].Variants {
				if !walk(v.Payload) {
					ok = false
					break
				}
			}
		case mir.TypeSlice, mir.TypeVec, mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeRawPtr, mir.TypeTable,
			mir.TypeID, mir.TypeTableView, mir.TypeTableMutView, mir.TypeFunction, mir.TypeString,
			mir.TypeBytes, mir.TypeDomainHandle, mir.TypeDomainMark, mir.TypeCleanupScope, mir.TypeCleanupID:
			// Containers, references, handles, and text carry storage or
			// identity provenance no matter what their element is.
			ok = false
		default:
			ok = true
		}
		visiting[t] = false
		free[t] = ok
		return ok
	}
	for t := range m.Types {
		walk(mir.TypeId(t))
	}
	return free
}

func transferDomain(m *mir.Module, f *mir.Function, vid mir.ValueId, info []domainInfo, edges map[mir.ValueId][]mir.ValueId, effects []functionEffect, loadStores [][]mir.ValueId, free []bool, out *domainInfo) bool {
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
		// copy_to_domain materializes an independent value. Its lifetime is
		// rooted only in the destination domain; retaining source provenance
		// would incorrectly invalidate the copy when an inner source domain
		// is destroyed. A function value's copy is complete because the
		// backend's retain hook allocates a fresh environment in the
		// destination domain, so the same rule applies to it.
		changed = addRoot(out, domainRoot{handle: in.Domain, allocBlk: v.Def.Block, allocIn: v.Def.Instr, param: -1}) || changed
	case mir.OpLoad:
		if int(v.Type) < len(free) && free[v.Type] {
			// A load of a provenance-free type copies plain bits. The value
			// has no lifetime tie to the storage domain it was read from, so
			// it can flow through loops and locals without tracking that
			// domain: a later reset or destroy of the domain cannot dangle
			// plain bits. Storage-carrying types keep the merges below.
			return changed
		}
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
	case mir.OpVecConstructChecked, mir.OpVecLen, mir.OpVecCapacity, mir.OpVecStorage, mir.OpVecAsSlice, mir.OpVecAsMutSlice:
		merge(in.Slice)
	case mir.OpVecGrowChecked:
		merge(in.Domain)
		merge(in.Slice)
	case mir.OpArrayIndexChecked:
		merge(in.Array)
	case mir.OpArrayAsSlice:
		merge(in.Array)
	case mir.OpTableLookup, mir.OpTableLookupMut:
		merge(in.Table)
	case mir.OpTableInsertTry:
		// The Err payload is the element value handed back to the caller, so
		// the result shares the element operand's provenance. The Ok payload
		// is a plain identity value with no storage of its own.
		merge(in.TableVal)
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
	case mir.OpCallValue:
		// The callee is unknown at verification time, so the result is
		// conservatively derived from the function value (its environment may
		// carry provenance) and from every argument.
		merge(in.A)
		for _, a := range in.Args {
			merge(a)
		}
	case mir.OpFnValue:
		// A function value's provenance is its environment's provenance.
		merge(in.A)
	}
	return changed
}

func instructionUses(in *mir.Instr) []mir.ValueId { return instrValueOperands(in) }
func isDomainType(m *mir.Module, t mir.TypeId) bool {
	return m.ValidType(t) && m.Types[t].Kind == mir.TypeDomainHandle
}
func typeContainsRef(m *mir.Module, t mir.TypeId) bool {
	return containsKind(m, t, mir.TypeSafeRef) || containsKind(m, t, mir.TypeSafeMut) ||
		containsKind(m, t, mir.TypeSlice) || containsKind(m, t, mir.TypeVec) || containsKind(m, t, mir.TypeTable)
}
func typeRequiresLocalStore(m *mir.Module, t mir.TypeId, envRecords map[mir.TypeId]bool) bool {
	for _, kind := range []mir.TypeKind{
		mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeSlice, mir.TypeTable,
		mir.TypeDomainHandle, mir.TypeDomainMark,
	} {
		// A closure environment record may carry the domain that owns it and
		// a captured scoped capability. The retain hook rewrites the domain
		// field when the record moves domains, the record never outlives its
		// domain, and a captured view is kept alive by the checker's escape
		// rule, so those fields are safe behind the dereference store that
		// installs the record.
		if envRecords[t] && (kind == mir.TypeDomainHandle || kind == mir.TypeSafeRef || kind == mir.TypeSafeMut || kind == mir.TypeSlice) {
			continue
		}
		if containsKind(m, t, kind) {
			return true
		}
	}
	return false
}

// closureEnvRecords returns the aggregate types used as fn.value environments.
func closureEnvRecords(m *mir.Module) map[mir.TypeId]bool {
	envs := map[mir.TypeId]bool{}
	for _, f := range m.Functions {
		if f == nil {
			continue
		}
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for i := range b.Instrs {
				in := &b.Instrs[i]
				if in.Op != mir.OpFnValue || in.A == mir.NoValue {
					continue
				}
				t, ok := f.ValueType(in.A)
				if !ok || !m.ValidType(t) {
					continue
				}
				ty := &m.Types[t]
				switch ty.Kind {
				case mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeSlice:
					if m.ValidType(ty.Elem) && m.Types[ty.Elem].Kind == mir.TypeAggregate {
						envs[ty.Elem] = true
					}
				}
			}
		}
	}
	return envs
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

// loopKill records one domain death site inside a function: a direct
// destroy or reset, or a call argument a callee effect may destroy or reset.
type loopKill struct {
	blk   mir.BlockId
	value mir.ValueId
}

// collectLoopKills gathers the per-function kill sites once, so each
// loop-carried store or parameter checks them without rescanning the module.
func collectLoopKills(f *mir.Function, effects []functionEffect) []loopKill {
	var kills []loopKill
	for bi, b := range f.Blocks {
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op == mir.OpDomainDestroy || in.Op == mir.OpDomainReset {
				kills = append(kills, loopKill{blk: mir.BlockId(bi), value: in.Domain})
			}
			if in.Op == mir.OpCall && int(in.Callee) < len(effects) {
				e := effects[in.Callee]
				for p, yes := range e.destroys {
					if yes && p < len(in.Args) {
						kills = append(kills, loopKill{blk: mir.BlockId(bi), value: in.Args[p]})
					}
				}
				for p, yes := range e.resets {
					if yes && p < len(in.Args) {
						kills = append(kills, loopKill{blk: mir.BlockId(bi), value: in.Args[p]})
					}
				}
			}
		}
	}
	return kills
}

// loopKeyKilled reports whether a domain identity key dies at a collected
// kill site in a loop block that the carrying site can reach. Two
// parameter-domain keys with no defining block alias conservatively, matching
// the dep-aliasing rule used elsewhere.
func loopKeyKilled(f *mir.Function, info []domainInfo, reaches func(from, to mir.BlockId) bool, kills []loopKill, from mir.BlockId, key defKey) bool {
	for _, k := range kills {
		if !inCycleFor(f, k.blk) || !reaches(from, k.blk) {
			continue
		}
		for d := range info[k.value].deps {
			if d == key || d.blk == mir.NoBlock && key.blk == mir.NoBlock {
				return true
			}
		}
	}
	return false
}

// loopCarryOwnerType reports whether a type is an owning value whose
// loop-carried storage the survival rule may reason about: it contains an
// owning collection (vec, array, or aggregate/enum/option of owners) and no
// capability or handle kind (slices, references, domain handles and marks,
// table owners and views, raw pointers). Capability-typed values keep the
// conservative loop rules: views alias memory owned elsewhere and are
// lexically scoped by design, and handles are the resource discipline
// itself.
func loopCarryOwnerType(m *mir.Module, t mir.TypeId, envRecords map[mir.TypeId]bool) bool {
	if int(t) >= len(m.Types) {
		return true
	}
	// The map is per query and only ever memoizes an owning verdict: a
	// capability verdict unwinds the whole walk immediately, so the type that
	// produced it is never asked about again inside this call.
	seen := map[mir.TypeId]bool{}
	var walk func(t mir.TypeId) bool
	walk = func(t mir.TypeId) bool {
		if int(t) >= len(m.Types) || seen[t] || t == 0 {
			return true
		}
		seen[t] = true
		switch m.Types[t].Kind {
		case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeDomainHandle,
			mir.TypeDomainMark, mir.TypeTable, mir.TypeTableView, mir.TypeTableMutView,
			mir.TypeRawPtr, mir.TypeCleanupScope, mir.TypeCleanupID:
			return false
		default:
			if e := m.Types[t].Elem; e != 0 {
				if !walk(e) {
					return false
				}
			}
			if o := m.Types[t].OK; o != 0 {
				if !walk(o) {
					return false
				}
			}
			if e := m.Types[t].Err; e != 0 {
				if !walk(e) {
					return false
				}
			}
			for _, field := range m.Types[t].Fields {
				if field.Type != 0 {
					// A closure environment record's domain field names the
					// domain that owns the record, not a borrowed capability,
					// so the record is still an owning value.
					if envRecords[t] && m.Types[field.Type].Kind == mir.TypeDomainHandle {
						continue
					}
					if !walk(field.Type) {
						return false
					}
				}
			}
			for _, variant := range m.Types[t].Variants {
				if variant.Payload != 0 {
					if !walk(variant.Payload) {
						return false
					}
				}
			}
			return true
		}
	}
	return walk(t)
}

// inCycleFor reports whether a block lies on a cycle: plain reachability
// always includes the start block, so self-reachability needs a dedicated
// check.
func inCycleFor(f *mir.Function, b mir.BlockId) bool {
	if int(b) >= len(f.Blocks) {
		return false
	}
	return inCycle(f, b)
}

// loopSameCycle reports whether a block lies in the same cycle as the loop
// block being checked. "On some cycle" is not enough: a domain created inside
// a different, already finished loop is carried across this loop's backedge
// unchanged, and only a domain created inside THIS loop is per-iteration.
func loopSameCycle(reaches func(from, to mir.BlockId) bool, anchor, block mir.BlockId) bool {
	if block == mir.NoBlock {
		return false
	}
	if block == anchor {
		return true
	}
	return reaches(anchor, block) && reaches(block, anchor)
}

// loopInBody reports whether the loop header dominates the block, which is
// what makes a definition re-execute once per iteration of that loop. A
// cycle test cannot answer this: a for loop nested inside a while body shares
// the while loop's cycle, yet a value the nested loop carries is defined once
// per outer iteration, not once per inner one.
func loopInBody(dom [][]bool, header, block mir.BlockId) bool {
	if block == mir.NoBlock {
		return false
	}
	if block == header {
		return true
	}
	return int(block) < len(dom) && dom[block][header]
}

// loopValueDies is the precise half of the loop rules: a carried value dies
// inside its loop when it depends on a domain created in the loop, or when a
// destroy or reset inside the loop invalidates one of its domain identities
// (a reset also invalidates descendants, which parent facts record). Entry
// domains created before the loop and destroyed only after it survive, which
// is what makes loop-carried collection headers legal.
func loopValueDies(f *mir.Function, info []domainInfo, reaches func(from, to mir.BlockId) bool, kills []loopKill, dom [][]bool, anchor, from mir.BlockId, v mir.ValueId, shared bool) bool {
	if int(v) >= len(info) {
		return false
	}
	vi := info[v]
	for d := range vi.deps {
		if d.blk != mir.NoBlock && loopInBody(dom, anchor, d.blk) {
			return true
		}
		if loopKeyKilled(f, info, reaches, kills, from, d) {
			return true
		}
	}
	for p := range vi.parents {
		if loopKeyKilled(f, info, reaches, kills, from, p) {
			return true
		}
	}
	for r := range vi.roots {
		// An allocation produced inside THIS loop is per-iteration for an
		// owning value: carrying it around the backedge conflates iterations,
		// so it stays forbidden. A shared function environment is immutable
		// and copyable, so the allocation site alone does not condemn it; a
		// domain death inside the loop still does.
		if !shared && r.param < 0 && r.allocBlk != mir.NoBlock && loopInBody(dom, anchor, r.allocBlk) {
			return true
		}
		if r.param < 0 && int(r.handle) < len(info) {
			for d := range info[r.handle].deps {
				if loopKeyKilled(f, info, reaches, kills, from, d) {
					return true
				}
			}
			for p := range info[r.handle].parents {
				if loopKeyKilled(f, info, reaches, kills, from, p) {
					return true
				}
			}
		}
	}
	return false
}

// envSnapshotType reports whether a type is a copyable snapshot that may
// contain function values and nothing that owns or aliases mutable storage.
// Such a value shares immutable environment records, so carrying it across a
// backedge transfers no ownership and cannot conflate iterations; the
// environment still dies with its owning domain, which the death checks keep
// enforcing.
func envSnapshotType(m *mir.Module, t mir.TypeId) bool {
	hasEnv, blocked := envSnapshotScan(m, t, 0)
	return hasEnv && !blocked
}

func envSnapshotScan(m *mir.Module, t mir.TypeId, depth int) (hasEnv, blocked bool) {
	if t == 0 || int(t) >= len(m.Types) || depth > 8 {
		return false, true
	}
	ty := &m.Types[t]
	switch ty.Kind {
	case mir.TypeFunction:
		return true, false
	case mir.TypePrimitive:
		return false, false
	case mir.TypeAggregate, mir.TypeEnum, mir.TypeOption, mir.TypeResult, mir.TypeArray:
	default:
		return false, true
	}
	children := make([]mir.TypeId, 0, 2+len(ty.Fields)+len(ty.Variants))
	if ty.Elem != 0 {
		children = append(children, ty.Elem)
	}
	if ty.OK != 0 {
		children = append(children, ty.OK)
	}
	if ty.Err != 0 {
		children = append(children, ty.Err)
	}
	for _, field := range ty.Fields {
		if field.Type != 0 {
			children = append(children, field.Type)
		}
	}
	for _, variant := range ty.Variants {
		if variant.Payload != 0 {
			children = append(children, variant.Payload)
		}
	}
	for _, child := range children {
		childEnv, childBlocked := envSnapshotScan(m, child, depth+1)
		hasEnv = hasEnv || childEnv
		blocked = blocked || childBlocked
	}
	return hasEnv, blocked
}

func rejectLoopCarriedLocals(m *mir.Module, f *mir.Function, info []domainInfo, effect functionEffect, effects []functionEffect, envRecords map[mir.TypeId]bool) []Error {
	// Dominance answers "does this loop re-execute the definition" for the
	// loop-carried parameter rule; the store rule below keeps the coarser
	// same-cycle test because it has no loop header to hand.
	dom := dominators(f)
	var errs []Error
	kills := collectLoopKills(f, effects)
	reachCache := make(map[mir.BlockId][]bool, len(f.Blocks))
	reachesFor := func(from, to mir.BlockId) bool {
		if int(from) >= len(f.Blocks) || int(to) >= len(f.Blocks) {
			return false
		}
		reached, ok := reachCache[from]
		if !ok {
			reached = reachableFrom(f, from)
			reachCache[from] = reached
		}
		return reached[int(to)]
	}
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
					dies := true
					if int(args[v.Def.Param]) < len(f.Values) {
						carriedType := f.Values[args[v.Def.Param]].Type
						if envSnapshotType(m, carriedType) {
							dies = loopValueDies(f, info, reachesFor, kills, dom, mir.BlockId(bi), mir.BlockId(bi), args[v.Def.Param], true)
						} else if loopCarryOwnerType(m, carriedType, envRecords) {
							dies = loopValueDies(f, info, reachesFor, kills, dom, mir.BlockId(bi), mir.BlockId(bi), args[v.Def.Param], false)
						}
					}
					if local && dies {
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
			// A capability-typed value must be stored into a local place; an
			// owner may also be stored through a projection. The stability
			// test below is the same for both.
			requireLocalPlace := !loopCarryOwnerType(m, f.Values[in.StoreVal].Type, envRecords)
			if stableLoopStore(m, f, info, effect, in, reachesFor, kills, mir.BlockId(bi), requireLocalPlace) {
				continue
			}
			errs = append(errs, Error{
				Loc: locInstr(f, b, ii, in),
				Msg: fmt.Sprintf("store of %s carries a function-local domain handle or reference across a loop backedge", valueName(f, in.StoreVal)),
			})
		}
	}
	// A view read inside a loop must be redefined in the same iteration, or
	// the loop must not be able to move the storage it views. A view header is
	// not an owning value: a later iteration that reads a header stored by an
	// earlier one dangles as soon as the loop grows, removes from, or replaces
	// the owner, and the domain surviving the loop does not prevent that.
	for bi, b := range f.Blocks {
		if !inCycle(f, mir.BlockId(bi)) {
			continue
		}
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpLoad || int(in.Result) >= len(f.Values) || !viewStorageType(m, f.Values[in.Result].Type) {
				continue
			}
			if _, ok := localPlaceKey(&in.Place); !ok {
				continue
			}
			parameterRooted := false
			for root := range info[in.Result].roots {
				if root.param >= 0 {
					parameterRooted = true
				}
			}
			if parameterRooted {
				continue
			}
			if loopRedefinesPlace(f, dom, reachesFor, mir.BlockId(bi), ii, &in.Place) {
				continue
			}
			base := viewBaseOf(m, f, in.Result, 0)
			if base.kind == viewBaseStable {
				continue
			}
			if base.kind == viewBaseLocal && !loopRelocatesBase(m, f, reachesFor, mir.BlockId(bi), base.local) {
				continue
			}
			errs = append(errs, Error{
				Loc: locInstr(f, b, ii, in),
				Msg: fmt.Sprintf("read of %s reads a view across a loop backedge; the view must be created in the iteration that reads it or its storage must not move in the loop", valueName(f, in.Result)),
			})
		}
	}
	return errs
}

// stableLoopStore permits a store inside a loop cycle whose value's domain
// provenance is local to the function when every domain it can name survives
// the loop: either the store writes a local place and every root is owned by a
// domain parameter, or the owning domain is created before the loop and no
// destroy or reset inside the loop's blocks invalidates it. Repeated static
// allocation sites are safe in that case because every produced allocation
// remains live for the entire call, and a pre-loop local domain dies only at
// the function's exits. Local domains created or invalidated inside the loop
// remain forbidden: their per-site C slots and dynamic identities must not be
// conflated across iterations. As elsewhere in the verifier, unsafe foreign
// code is responsible for honoring the declared safe boundary.
//
// A capability-typed value (a view) additionally has to be stored into a local
// place. Its root is the domain that owns the viewed storage; that domain
// surviving the loop is what keeps the header valid across iterations, and the
// source-level view rules keep the storage itself alive while a view exists, so
// the verifier's own job here is only to prevent domain identity conflation
// across the backedge.
func stableLoopStore(m *mir.Module, f *mir.Function, info []domainInfo, effect functionEffect, in *mir.Instr, reaches func(from, to mir.BlockId) bool, kills []loopKill, block mir.BlockId, requireLocalPlace bool) bool {
	if requireLocalPlace {
		if _, ok := localPlaceKey(&in.Place); !ok {
			return false
		}
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
		if d.blk != mir.NoBlock && (loopSameCycle(reaches, block, d.blk) || loopKeyKilled(f, info, reaches, kills, block, d)) {
			return false
		}
	}
	for root := range valueInfo.roots {
		if root.param >= 0 {
			continue
		}
		if int(root.handle) >= len(info) {
			return false
		}
		handleInfo := info[root.handle]
		// A local root is stable when its owning domain survives the whole
		// loop: either the parameter-domain path below still applies, or the
		// domain is created before the loop and no destroy or reset inside
		// the loop's blocks invalidates it.
		ownedByParameterDomain := false
		for p := range handleInfo.params {
			if p < 0 || p >= len(f.Params) || !isDomainType(m, f.Params[p].Type) {
				continue
			}
			ownedByParameterDomain = true
		}
		if ownedByParameterDomain {
			continue
		}
		for d := range handleInfo.deps {
			if d.blk != mir.NoBlock && loopSameCycle(reaches, block, d.blk) {
				return false
			}
			if loopKeyKilled(f, info, reaches, kills, block, d) {
				return false
			}
		}
		for p := range handleInfo.parents {
			if loopKeyKilled(f, info, reaches, kills, block, p) {
				return false
			}
		}
	}
	// A value with no failing check is stable: its storage domains all
	// outlive the loop, whether they arrive as roots or as surviving
	// domain-identity deps (the loop-carried collection header case).
	return true
}

// viewStorageType reports whether a type is a scoped view whose header points
// into storage this frame does not own.
func viewStorageType(m *mir.Module, t mir.TypeId) bool {
	if int(t) >= len(m.Types) {
		return false
	}
	switch m.Types[t].Kind {
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
		return true
	}
	return false
}

// viewBase kinds: where the storage a view header points into lives.
const (
	viewBaseUnknown = iota // the walk cannot name the storage
	viewBaseLocal          // a local slot of this frame holds it
	viewBaseStable         // storage no frame operation can relocate
)

// viewBase names the storage a view header points into.
type viewBase struct {
	kind  int
	local mir.LocalId
}

// viewBaseOf walks a view value back to the storage it views. A value that
// owns storage is its own base; a view is followed through as_slice, slice
// range and index, and a load from a view slot follows every value stored into
// that slot. A parameter, a constant, an allocation, and a call result are
// storage this frame cannot relocate, so they count as stable. The walk reports
// unknown when the storage arrives from an unclassifiable definition, the slot
// has more than one possible base, or the chain is not one this rule follows.
func viewBaseOf(m *mir.Module, f *mir.Function, v mir.ValueId, depth int) viewBase {
	if depth > 16 || int(v) >= len(f.Values) {
		return viewBase{kind: viewBaseUnknown}
	}
	def := f.Values[v].Def
	switch def.Kind {
	case mir.ValueDefFuncParam, mir.ValueDefBlockParam:
		return viewBase{kind: viewBaseStable}
	case mir.ValueDefSwitchCase:
		if int(def.Block) >= len(f.Blocks) {
			return viewBase{kind: viewBaseUnknown}
		}
		return viewBaseOf(m, f, f.Blocks[def.Block].Term.Value, depth+1)
	case mir.ValueDefInstr:
	default:
		return viewBase{kind: viewBaseUnknown}
	}
	if int(def.Block) >= len(f.Blocks) || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return viewBase{kind: viewBaseUnknown}
	}
	in := &f.Blocks[def.Block].Instrs[def.Instr]
	switch in.Op {
	case mir.OpLoad:
		if in.Place.Kind != mir.PlaceLocal {
			return viewBase{kind: viewBaseUnknown}
		}
		if !viewStorageType(m, f.Values[v].Type) {
			return viewBase{kind: viewBaseLocal, local: in.Place.Local}
		}
		key, ok := localPlaceKey(&in.Place)
		if !ok {
			return viewBase{kind: viewBaseUnknown}
		}
		root, rootOK := placeRootLocal(&in.Place)
		if !rootOK {
			return viewBase{kind: viewBaseUnknown}
		}
		var found viewBase
		any := false
		for bi := range f.Blocks {
			for ii := range f.Blocks[bi].Instrs {
				store := &f.Blocks[bi].Instrs[ii]
				if store.Op != mir.OpStore {
					continue
				}
				if storeRoot, ok := placeRootLocal(&store.Place); !ok || storeRoot != root {
					continue
				}
				if storeKey, ok := localPlaceKey(&store.Place); !ok || storeKey != key {
					continue
				}
				base := viewBaseOf(m, f, store.StoreVal, depth+1)
				if base.kind == viewBaseUnknown || (any && base != found) {
					return viewBase{kind: viewBaseUnknown}
				}
				found = base
				any = true
			}
		}
		if any {
			return found
		}
		return viewBase{kind: viewBaseUnknown}
	case mir.OpVecAsSlice, mir.OpVecAsMutSlice, mir.OpSliceRangeChecked, mir.OpSliceIndexChecked:
		return viewBaseOf(m, f, in.Slice, depth+1)
	case mir.OpArrayAsSlice:
		return viewBaseOf(m, f, in.Array, depth+1)
	case mir.OpAlloc, mir.OpAllocChecked, mir.OpVecNew, mir.OpVecConstructChecked, mir.OpVecGrowChecked,
		mir.OpCopyToDomain, mir.OpTableCreate, mir.OpConstGet, mir.OpCall, mir.OpCallValue:
		return viewBase{kind: viewBaseStable}
	}
	return viewBase{kind: viewBaseUnknown}
}

// loopRelocatesBase reports whether a cycle that contains `block` can relocate
// or replace the storage local `base` names: a vector grow whose operand
// derives from it, a store into it, or a call that receives it (a callee may
// grow storage through an exclusive argument). Element writes do not move the
// storage and are not included.
func loopRelocatesBase(m *mir.Module, f *mir.Function, reaches func(from, to mir.BlockId) bool, block mir.BlockId, base mir.LocalId) bool {
	for bi := range f.Blocks {
		if !loopSameCycle(reaches, block, mir.BlockId(bi)) {
			continue
		}
		for ii := range f.Blocks[bi].Instrs {
			in := &f.Blocks[bi].Instrs[ii]
			switch in.Op {
			case mir.OpVecGrowChecked:
				if b := viewBaseOf(m, f, in.Slice, 0); b.kind == viewBaseLocal && b.local == base {
					return true
				}
			case mir.OpStore:
				if b, ok := placeRootLocal(&in.Place); ok && b == base {
					return true
				}
			case mir.OpCall, mir.OpCallValue:
				for _, arg := range in.Args {
					if b := viewBaseOf(m, f, arg, 0); b.kind == viewBaseLocal && b.local == base {
						return true
					}
				}
			}
		}
	}
	return false
}

// loopRedefinesPlace reports whether a store to the same place dominates the
// load, which makes the read see a view created in the same iteration. A store
// in the load's own block has to precede it.
func loopRedefinesPlace(f *mir.Function, dom [][]bool, reaches func(from, to mir.BlockId) bool, block mir.BlockId, index int, place *mir.Place) bool {
	key, ok := localPlaceKey(place)
	if !ok {
		return false
	}
	for bi := range f.Blocks {
		if !loopSameCycle(reaches, block, mir.BlockId(bi)) {
			continue
		}
		for ii := range f.Blocks[bi].Instrs {
			in := &f.Blocks[bi].Instrs[ii]
			if in.Op != mir.OpStore {
				continue
			}
			if storeKey, ok := localPlaceKey(&in.Place); !ok || storeKey != key {
				continue
			}
			if mir.BlockId(bi) == block {
				if ii < index {
					return true
				}
				continue
			}
			if loopInBody(dom, mir.BlockId(bi), block) {
				return true
			}
		}
	}
	return false
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
