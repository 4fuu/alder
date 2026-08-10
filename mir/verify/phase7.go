package verify

import (
	"fmt"

	"github.com/4fuu/aster/mir"
)

// phase7Cleanup checks cleanup balance and exit validation: every exit is
// dominated by a cleanup.scope.end of every open scope, ends are preceded by
// a run, ends never execute twice on one path, pushes and disarms precede the
// scope's run, entries are not registered after the scope ends, and duplicate
// cleanup registrations are rejected unless one of the pair is disarmed.
// cleanupSite is one instruction position.
type cleanupSite struct {
	blk mir.BlockId
	in  int
}

func phase7Cleanup(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		dom := dominators(f)
		reach := reachable(f)

		begin := make(map[mir.ValueId]cleanupSite)
		runs := make(map[mir.ValueId][]cleanupSite)
		ends := make(map[mir.ValueId][]cleanupSite)
		disarmed := make(map[mir.ValueId]bool)
		for bi, b := range f.Blocks {
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				switch in.Op {
				case mir.OpCleanupScopeBegin:
					if in.Result != mir.NoValue {
						begin[in.Result] = cleanupSite{blk: mir.BlockId(bi), in: ii}
					}
				case mir.OpCleanupScopeRun:
					runs[in.Scope] = append(runs[in.Scope], cleanupSite{blk: mir.BlockId(bi), in: ii})
				case mir.OpCleanupScopeEnd:
					ends[in.Scope] = append(ends[in.Scope], cleanupSite{blk: mir.BlockId(bi), in: ii})
				case mir.OpCleanupDisarm:
					disarmed[in.CleanupID] = true
				}
			}
		}

		// Deterministic per-scope walk in value order.
		for vi, v := range f.Values {
			bgn, ok := begin[mir.ValueId(vi)]
			if !ok || v.Type != m.CleanupScope() {
				continue
			}
			name := "%" + v.Name
			es := ends[mir.ValueId(vi)]
			// A scope that ends must be run first, and must not end twice on
			// one path or inside a loop.
			for ei, e := range es {
				if !anyDominates(f, runs[mir.ValueId(vi)], dom, e) {
					errs = append(errs, Error{Loc: siteLoc(f, e), Msg: fmt.Sprintf("cleanup.scope.end of %s is not preceded by cleanup.scope.run", name)})
				}
				if inCycle(f, e.blk) {
					errs = append(errs, Error{Loc: siteLoc(f, e), Msg: fmt.Sprintf("cleanup.scope.end of %s inside a loop", name)})
				}
				for _, e2 := range es[ei+1:] {
					if dominatesWithEdges(f, dom, e.blk, e.in, e2.blk, e2.in) || dominatesWithEdges(f, dom, e2.blk, e2.in, e.blk, e.in) {
						errs = append(errs, Error{Loc: siteLoc(f, e2), Msg: fmt.Sprintf("cleanup.scope.end of %s runs more than once on one path", name)})
					}
				}
			}

			// Every exit must pass through an end of every open scope.
			for _, b := range f.Blocks {
				t := &b.Term
				if t.Kind != mir.TermReturn && t.Kind != mir.TermFail {
					continue
				}
				bi := blockIndexOf(f, b)
				exitPos := len(b.Instrs)
				if !dominatesWithEdges(f, dom, bgn.blk, bgn.in, bi, exitPos) {
					continue // scope not open here
				}
				covered := false
				for _, e := range es {
					if dominatesWithEdges(f, dom, e.blk, e.in, bi, exitPos) {
						covered = true
						break
					}
				}
				if !covered {
					errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("exit leaves cleanup scope %s open", name)})
				}
			}

			// Uses of the scope value after an end.
			for _, u := range collectUses(f) {
				if u.value != mir.ValueId(vi) || !reach[u.block] {
					continue
				}
				usePos := u.instr
				if usePos < 0 {
					usePos = len(f.Blocks[u.block].Instrs)
				}
				for _, e := range es {
					if dominatesWithEdges(f, dom, e.blk, e.in, u.block, usePos) {
						errs = append(errs, Error{Loc: useSiteLoc(f, u), Msg: fmt.Sprintf("use of %s after cleanup.scope.end", name)})
						break
					}
				}
			}

			// Push and disarm discipline for this scope.
			var pushes []*mir.Instr
			for _, b := range f.Blocks {
				for ii := range b.Instrs {
					in := &b.Instrs[ii]
					if in.Op != mir.OpCleanupPush || in.Scope != mir.ValueId(vi) {
						continue
					}
					loc := locInstr(f, b, ii, in)
					for _, e := range es {
						if dominatesWithEdges(f, dom, e.blk, e.in, blockIndexOf(f, b), ii) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("cleanup.push after cleanup.scope.end of %s", name)})
						}
					}
					for _, r := range runs[mir.ValueId(vi)] {
						if dominatesWithEdges(f, dom, r.blk, r.in, blockIndexOf(f, b), ii) {
							errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("cleanup.push after cleanup.scope.run may never execute (%s)", name)})
						}
					}
					pushes = append(pushes, in)
				}
			}
			for pi, p1 := range pushes {
				for _, p2 := range pushes[pi+1:] {
					if p1.CleanupFn != p2.CleanupFn || !sameArgs(p1.CleanupArgs, p2.CleanupArgs) {
						continue
					}
					if !disarmed[p1.Result] && !disarmed[p2.Result] {
						fnName := "@<invalid>"
						if int(p1.CleanupFn) < len(m.Functions) {
							fnName = "@" + m.Functions[p1.CleanupFn].Name
						}
						errs = append(errs, Error{Loc: locForInstr(f, p2), Msg: fmt.Sprintf("duplicate cleanup registration of %s", fnName)})
					}
				}
			}
		}

		// Disarms must reference a cleanup entry and precede the scope run.
		for _, b := range f.Blocks {
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				if in.Op != mir.OpCleanupDisarm {
					continue
				}
				loc := locInstr(f, b, ii, in)
				push, ok := pushOf(f, in.CleanupID)
				if !ok {
					errs = append(errs, Error{Loc: loc, Msg: "cleanup.disarm operand is not a cleanup entry"})
					continue
				}
				for _, r := range runs[push.Scope] {
					if dominatesWithEdges(f, dom, r.blk, r.in, blockIndexOf(f, b), ii) {
						errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("cleanup.disarm after cleanup.scope.run of %%%s", f.Values[push.Scope].Name)})
					}
				}
			}
		}
	}
	return errs
}

func anyDominates(f *mir.Function, sites []cleanupSite, dom [][]bool, use cleanupSite) bool {
	for _, s := range sites {
		if dominatesWithEdges(f, dom, s.blk, s.in, use.blk, use.in) {
			return true
		}
	}
	return false
}

func siteLoc(f *mir.Function, s cleanupSite) string {
	return locInstr(f, f.Blocks[s.blk], s.in, &f.Blocks[s.blk].Instrs[s.in])
}

func locForInstr(f *mir.Function, want *mir.Instr) string {
	for _, b := range f.Blocks {
		for ii := range b.Instrs {
			if &b.Instrs[ii] == want {
				return locInstr(f, b, ii, want)
			}
		}
	}
	return locFunc(f)
}

// pushOf returns the cleanup.push instruction that defined the cleanup id.
func pushOf(f *mir.Function, id mir.ValueId) (*mir.Instr, bool) {
	if int(id) >= len(f.Values) {
		return nil, false
	}
	def := f.Values[id].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) {
		return nil, false
	}
	b := f.Blocks[def.Block]
	if def.Instr < 0 || def.Instr >= len(b.Instrs) {
		return nil, false
	}
	in := &b.Instrs[def.Instr]
	if in.Op != mir.OpCleanupPush {
		return nil, false
	}
	return in, true
}

func sameArgs(a, b []mir.ValueId) bool {
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
