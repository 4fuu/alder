package verify

import "github.com/4fuu/aster/mir"

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
	for changed := true; changed; {
		changed = false
		for fi, f := range m.Functions {
			if f == nil || len(f.Blocks) == 0 {
				continue
			}
			info := computeDomainInfo(m, f, out)
			tables := computeTableInfo(m, f, out)
			cleanup, _ := analyzeCleanupFunction(m, f)
			e := &out[fi]
			for bi, b := range f.Blocks {
				for ii := range b.Instrs {
					in := &b.Instrs[ii]
					if in.Op == mir.OpDomainDestroy {
						changed = addParamDeps(e.destroys, info, in.Domain) || changed
					} else if in.Op == mir.OpDomainReset {
						changed = addParamDeps(e.resets, info, in.Domain) || changed
					}
					if in.Op == mir.OpTableInsert || in.Op == mir.OpTableRemove {
						changed = addTableParamDeps(e.tableMutates, tables, in.Table) || changed
					}
					if in.Op == mir.OpCall && int(in.Callee) < len(out) {
						ce := out[in.Callee]
						for pi, yes := range ce.destroys {
							if yes && pi < len(in.Args) {
								changed = addParamDeps(e.destroys, info, in.Args[pi]) || changed
							}
						}
						for pi, yes := range ce.resets {
							if yes && pi < len(in.Args) {
								changed = addParamDeps(e.resets, info, in.Args[pi]) || changed
							}
						}
						for pi, yes := range ce.tableMutates {
							if yes && pi < len(in.Args) {
								changed = addTableParamDeps(e.tableMutates, tables, in.Args[pi]) || changed
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
									changed = addParamDeps(e.destroys, info, entry.Args[pi]) || changed
								}
							}
							for pi, yes := range out[entry.Callback].resets {
								if yes && pi < len(entry.Args) {
									changed = addParamDeps(e.resets, info, entry.Args[pi]) || changed
								}
							}
							for pi, yes := range out[entry.Callback].tableMutates {
								if yes && pi < len(entry.Args) {
									changed = addTableParamDeps(e.tableMutates, tables, entry.Args[pi]) || changed
								}
							}
						}
					}
				}
				if (b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail) && b.Term.Result != mir.NoValue && int(b.Term.Result) < len(info) {
					for p := range info[b.Term.Result].params {
						if p < len(e.resultFrom) && !e.resultFrom[p] {
							e.resultFrom[p] = true
							changed = true
						}
					}
					for r := range info[b.Term.Result].roots {
						if r.param >= 0 {
							continue
						}
						for p := range info[r.handle].params {
							if p < len(e.resultAlloc) && !e.resultAlloc[p] {
								e.resultAlloc[p] = true
								changed = true
							}
						}
					}
				}
				if (b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail) && b.Term.Result != mir.NoValue && int(b.Term.Result) < len(tables) && containsKind(m, f.Values[b.Term.Result].Type, mir.TypeTable) {
					for o := range tables[b.Term.Result] {
						if o.param >= 0 && o.param < len(e.tableResultFrom) && !e.tableResultFrom[o.param] {
							e.tableResultFrom[o.param] = true
							changed = true
						}
						if o.param < 0 && !e.tableResultLocal {
							e.tableResultLocal = true
							changed = true
						}
					}
				}
			}
		}
	}
	return out
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
