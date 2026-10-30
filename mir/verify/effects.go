package verify

import "github.com/4fuu/alder/mir"

// functionEffect is the finite, caller-visible lifetime contract inferred for
// a function.  All sets are indexed by formal parameter number.  Keeping the
// lattice finite makes recursive call graphs converge without call-graph
// ordering or map iteration.
type functionEffect struct {
	destroys         []bool
	resets           []bool
	resultFrom       []bool
	resultAlloc      []bool
	tableMutates     []bool
	tableResultFrom  []bool
	tableResultLocal bool
}

func computeFunctionEffects(m *mir.Module) []functionEffect {
	effects, _, _, _ := computeFunctionEffectsWithCleanup(m)
	return effects
}

func computeFunctionEffectsWithCleanup(m *mir.Module) ([]functionEffect, []*cleanupAnalysis, [][]domainInfo, []Error) {
	out := make([]functionEffect, len(m.Functions))
	for i, f := range m.Functions {
		if f != nil {
			out[i] = functionEffect{
				destroys:        make([]bool, len(f.Params)),
				resets:          make([]bool, len(f.Params)),
				resultFrom:      make([]bool, len(f.Params)),
				resultAlloc:     make([]bool, len(f.Params)),
				tableMutates:    make([]bool, len(f.Params)),
				tableResultFrom: make([]bool, len(f.Params)),
			}
		}
	}
	cleanups := make([]*cleanupAnalysis, len(m.Functions))
	domainInfos := make([][]domainInfo, len(m.Functions))
	var cleanupErrs []Error
	for i, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		domainInfos[i] = make([]domainInfo, len(f.Values))
		a, es := analyzeCleanupFunction(m, f)
		cleanups[i] = a
		cleanupErrs = append(cleanupErrs, es...)
	}
	// Effects and domain facts are monotone, so a function whose callees'
	// effects have not changed since it was last processed is already at its
	// fixpoint. Propagating along call edges instead of resweeping every
	// function reaches the same least fixpoint with far fewer transfers; the
	// Alder port of this analysis drives the same worklist.
	callers := effectCallerGraph(m, cleanups)
	queue := make([]int, 0, len(m.Functions))
	queued := make([]bool, len(m.Functions))
	for i := range m.Functions {
		queue = append(queue, i)
		queued[i] = true
	}
	for at := 0; at < len(queue); at++ {
		fi := queue[at]
		queued[fi] = false
		f := m.Functions[fi]
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		before := snapshotEffect(out[fi])
		fnChanged := false
		info := domainInfos[fi]
		updateDomainInfo(m, f, out, info)
		tables := computeTableInfo(m, f, out)
		cleanup := cleanups[fi]
		e := &out[fi]
		for bi, b := range f.Blocks {
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				if in.Op == mir.OpDomainDestroy {
					fnChanged = addParamDeps(e.destroys, info, in.Domain) || fnChanged
				} else if in.Op == mir.OpDomainReset {
					fnChanged = addParamDeps(e.resets, info, in.Domain) || fnChanged
				}
				if in.Op == mir.OpTableInsert || in.Op == mir.OpTableRemove {
					fnChanged = addTableParamDeps(e.tableMutates, tables, in.Table) || fnChanged
				}
				if in.Op == mir.OpCall && int(in.Callee) < len(out) {
					ce := out[in.Callee]
					for pi, yes := range ce.destroys {
						if yes && pi < len(in.Args) {
							fnChanged = addParamDeps(e.destroys, info, in.Args[pi]) || fnChanged
						}
					}
					for pi, yes := range ce.resets {
						if yes && pi < len(in.Args) {
							fnChanged = addParamDeps(e.resets, info, in.Args[pi]) || fnChanged
						}
					}
					for pi, yes := range ce.tableMutates {
						if yes && pi < len(in.Args) {
							fnChanged = addTableParamDeps(e.tableMutates, tables, in.Args[pi]) || fnChanged
						}
					}
				}
				if in.Op == mir.OpCleanupScopeRun {
					for _, entry := range cleanup.activeEntriesAtRun(cleanupSite{mir.BlockId(bi), ii}) {
						if int(entry.Callback) >= len(out) {
							continue
						}
						for pi, yes := range out[entry.Callback].destroys {
							if yes && pi < len(entry.Args) {
								fnChanged = addParamDeps(e.destroys, info, entry.Args[pi]) || fnChanged
							}
						}
						for pi, yes := range out[entry.Callback].resets {
							if yes && pi < len(entry.Args) {
								fnChanged = addParamDeps(e.resets, info, entry.Args[pi]) || fnChanged
							}
						}
						for pi, yes := range out[entry.Callback].tableMutates {
							if yes && pi < len(entry.Args) {
								fnChanged = addTableParamDeps(e.tableMutates, tables, entry.Args[pi]) || fnChanged
							}
						}
					}
				}
			}
			if (b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail) && b.Term.Result != mir.NoValue && int(b.Term.Result) < len(info) {
				for p := range info[b.Term.Result].params {
					if p < len(e.resultFrom) && !e.resultFrom[p] {
						e.resultFrom[p] = true
						fnChanged = true
					}
				}
				for r := range info[b.Term.Result].roots {
					if r.param >= 0 {
						continue
					}
					for p := range info[r.handle].params {
						if p < len(e.resultAlloc) && !e.resultAlloc[p] {
							e.resultAlloc[p] = true
							fnChanged = true
						}
					}
				}
			}
			if (b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail) && b.Term.Result != mir.NoValue && int(b.Term.Result) < len(tables) && containsKind(m, f.Values[b.Term.Result].Type, mir.TypeTable) {
				for o := range tables[b.Term.Result] {
					if o.param >= 0 && o.param < len(e.tableResultFrom) && !e.tableResultFrom[o.param] {
						e.tableResultFrom[o.param] = true
						fnChanged = true
					}
					if o.param < 0 && !e.tableResultLocal {
						e.tableResultLocal = true
						fnChanged = true
					}
				}
			}
		}
		if !effectsEqual(before, out[fi]) {
			for _, caller := range callers[fi] {
				if !queued[caller] {
					queued[caller] = true
					queue = append(queue, caller)
				}
			}
		}
	}
	return out, cleanups, domainInfos, cleanupErrs
}

// effectCallerGraph maps each callee to the functions whose inferred effects
// depend on it: direct calls and cleanup callbacks registered at a
// cleanup.scope.run. Callers are listed once per edge and in ascending
// function order, so the worklist that consumes the graph is deterministic.
func effectCallerGraph(m *mir.Module, cleanups []*cleanupAnalysis) map[int][]int {
	callers := make(map[int][]int, len(m.Functions))
	seen := make(map[[2]int]bool)
	add := func(callee, caller int) {
		if callee < 0 || callee >= len(m.Functions) {
			return
		}
		key := [2]int{callee, caller}
		if seen[key] {
			return
		}
		seen[key] = true
		callers[callee] = append(callers[callee], caller)
	}
	for fi, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		for _, b := range f.Blocks {
			for _, in := range b.Instrs {
				if in.Op == mir.OpCall {
					add(int(in.Callee), fi)
				}
			}
		}
		cleanup := cleanups[fi]
		if cleanup == nil {
			continue
		}
		for bi, b := range f.Blocks {
			for ii, in := range b.Instrs {
				if in.Op != mir.OpCleanupScopeRun {
					continue
				}
				for _, entry := range cleanup.activeEntriesAtRun(cleanupSite{mir.BlockId(bi), ii}) {
					add(int(entry.Callback), fi)
				}
			}
		}
	}
	return callers
}

// snapshotEffect copies an effect vector by value. functionEffect holds
// slices, so a plain struct copy would alias the same backing arrays and make
// every before/after comparison report "unchanged".
func snapshotEffect(e functionEffect) functionEffect {
	copyBits := func(s []bool) []bool {
		if s == nil {
			return nil
		}
		out := make([]bool, len(s))
		copy(out, s)
		return out
	}
	return functionEffect{
		destroys:         copyBits(e.destroys),
		resets:           copyBits(e.resets),
		resultFrom:       copyBits(e.resultFrom),
		resultAlloc:      copyBits(e.resultAlloc),
		tableMutates:     copyBits(e.tableMutates),
		tableResultFrom:  copyBits(e.tableResultFrom),
		tableResultLocal: e.tableResultLocal,
	}
}

// effectsEqual reports whether two effect vectors describe the same contract.
func effectsEqual(a, b functionEffect) bool {
	if a.tableResultLocal != b.tableResultLocal {
		return false
	}
	for _, pair := range [][2][]bool{
		{a.destroys, b.destroys},
		{a.resets, b.resets},
		{a.resultFrom, b.resultFrom},
		{a.resultAlloc, b.resultAlloc},
		{a.tableMutates, b.tableMutates},
		{a.tableResultFrom, b.tableResultFrom},
	} {
		if len(pair[0]) != len(pair[1]) {
			return false
		}
		for i := range pair[0] {
			if pair[0][i] != pair[1][i] {
				return false
			}
		}
	}
	return true
}

func addTableParamDeps(dst []bool, info []tableOrigins, v mir.ValueId) bool {
	if int(v) >= len(info) {
		return false
	}
	changed := false
	for o := range info[v] {
		if o.param >= 0 && o.param < len(dst) && !dst[o.param] {
			dst[o.param] = true
			changed = true
		}
	}
	return changed
}

func addParamDeps(dst []bool, info []domainInfo, v mir.ValueId) bool {
	if int(v) >= len(info) {
		return false
	}
	changed := false
	for p := range info[v].params {
		if p < len(dst) && !dst[p] {
			dst[p] = true
			changed = true
		}
	}
	return changed
}
