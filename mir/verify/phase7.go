package verify

import (
	"encoding/binary"
	"fmt"
	"sort"

	"github.com/4fuu/alder/mir"
)

type cleanupSite struct {
	blk mir.BlockId
	in  int
}

type cleanupStatus uint8

const (
	cleanupAbsent cleanupStatus = iota
	cleanupOpen
	cleanupRun
	cleanupEnded
)

// cleanupEntry describes one registration site. Registrations are identified
// by their push result, not by callback/argument equality.
type cleanupEntry struct {
	Push     cleanupSite
	ID       mir.ValueId
	Callback mir.FunctionId
	Args     []mir.ValueId
}

// cleanupAnalysis is the Phase 7 result consumed by later analyses. The union
// supports may-effect summaries; the ordered alternatives preserve path
// correlation and runtime LIFO order for resource checking.
type cleanupAnalysis struct {
	activeAtRun     map[cleanupSite][]cleanupEntry
	activeSetsAtRun map[cleanupSite]map[string][]cleanupEntry
}

func (a *cleanupAnalysis) activeEntriesAtRun(site cleanupSite) []cleanupEntry {
	if a == nil {
		return nil
	}
	return a.activeAtRun[site]
}

func (a *cleanupAnalysis) activeEntrySetsAtRun(site cleanupSite) [][]cleanupEntry {
	if a == nil {
		return nil
	}
	sets := a.activeSetsAtRun[site]
	keys := make([]string, 0, len(sets))
	for key := range sets {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	out := make([][]cleanupEntry, 0, len(keys))
	for _, key := range keys {
		out = append(out, sets[key])
	}
	return out
}

type cleanupConfig struct {
	status cleanupStatus
	// active encodes registration-site indexes in runtime push order. A string
	// keeps configurations comparable while preserving path-specific LIFO.
	active string
}

func phase7Cleanup(m *mir.Module) []Error {
	var errs []Error
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		_, es := analyzeCleanupFunction(m, f)
		errs = append(errs, es...)
	}
	return errs
}

func analyzeCleanupFunction(m *mir.Module, f *mir.Function) (*cleanupAnalysis, []Error) {
	result := &cleanupAnalysis{
		activeAtRun:     make(map[cleanupSite][]cleanupEntry),
		activeSetsAtRun: make(map[cleanupSite]map[string][]cleanupEntry),
	}
	var errs []Error
	for vi := range f.Values {
		scope := mir.ValueId(vi)
		t := f.Values[vi].Type
		if !m.ValidType(t) || m.Types[t].Kind != mir.TypeCleanupScope {
			continue
		}
		def := f.Values[vi].Def
		if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) || f.Blocks[def.Block].Instrs[def.Instr].Op != mir.OpCleanupScopeBegin {
			continue
		}
		var entries []cleanupEntry
		entryIndex := make(map[mir.ValueId]int)
		for bi, b := range f.Blocks {
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				if in.Op == mir.OpCleanupPush && in.Scope == scope {
					entryIndex[in.Result] = len(entries)
					entries = append(entries, cleanupEntry{Push: cleanupSite{mir.BlockId(bi), ii}, ID: in.Result, Callback: in.CleanupFn, Args: append([]mir.ValueId(nil), in.CleanupArgs...)})
				}
			}
		}
		es := analyzeOneScope(f, scope, entries, entryIndex, result)
		errs = append(errs, es...)
	}
	return result, errs
}

func analyzeOneScope(f *mir.Function, scope mir.ValueId, entries []cleanupEntry, entryIndex map[mir.ValueId]int, out *cleanupAnalysis) []Error {
	var errs []Error
	sets := make([]map[cleanupConfig]bool, len(f.Blocks))
	for i := range sets {
		sets[i] = make(map[cleanupConfig]bool)
	}
	sets[0][cleanupConfig{status: cleanupAbsent}] = true
	queued := make([]bool, len(f.Blocks))
	queued[0] = true
	queue := []mir.BlockId{0}
	invalid := make(map[cleanupSite]string)
	exitOpen := make(map[mir.BlockId]bool)
	add := func(target mir.BlockId, configs map[cleanupConfig]bool) {
		changed := false
		for c := range configs {
			if !sets[target][c] {
				sets[target][c] = true
				changed = true
			}
		}
		if changed && !queued[target] {
			queued[target] = true
			queue = append(queue, target)
		}
	}
	for len(queue) > 0 {
		bi := queue[0]
		queue = queue[1:]
		queued[bi] = false
		cur := cloneConfigs(sets[bi])
		b := f.Blocks[bi]
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.FailTarget != mir.NoBlock {
				add(in.FailTarget, cur)
			} // failure occurs before the instruction effect
			site := cleanupSite{bi, ii}
			next := make(map[cleanupConfig]bool)
			for c := range cur {
				n := c
				valid := true
				invalidMsg := ""
				switch in.Op {
				case mir.OpCleanupScopeBegin:
					if in.Result == scope {
						valid = c.status == cleanupAbsent || c.status == cleanupEnded
						if valid {
							n.status = cleanupOpen
							n.active = ""
						}
					}
				case mir.OpCleanupPush:
					if in.Scope == scope {
						idx := entryIndex[in.Result]
						valid = c.status == cleanupOpen && !cleanupActiveContains(c.active, idx)
						if valid {
							n.active = cleanupActiveAppend(c.active, idx)
						} else if c.status == cleanupOpen {
							invalidMsg = "cleanup.push cannot execute again while its previous registration is active"
						}
					}
				case mir.OpCleanupDisarm:
					if idx, ok := entryIndex[in.CleanupID]; ok {
						var found bool
						n.active, found = cleanupActiveRemove(c.active, idx)
						valid = c.status == cleanupOpen && found
						if valid {
							// n.active was updated above.
						} else {
							n.active = c.active
						}
					}
				case mir.OpCleanupScopeRun:
					if in.Scope == scope {
						valid = c.status == cleanupOpen
						if valid {
							n.status = cleanupRun
							recordActiveSet(out, site, c.active, entries)
						}
					}
				case mir.OpCleanupScopeEnd:
					if in.Scope == scope {
						valid = c.status == cleanupRun
						if valid {
							n.status = cleanupEnded
							n.active = ""
						}
					}
				}
				if !valid {
					if invalidMsg == "" {
						invalidMsg = cleanupInvalidMessage(in.Op, f.Values[scope].Name)
					}
					if old := invalid[site]; old == "" || invalidMsg < old {
						invalid[site] = invalidMsg
					}
				} else {
					next[n] = true
				}
			}
			cur = next
		}
		if b.Term.Kind == mir.TermReturn || b.Term.Kind == mir.TermFail || b.Term.Kind == mir.TermPanic {
			for c := range cur {
				if c.status == cleanupOpen || c.status == cleanupRun {
					exitOpen[bi] = true
				}
			}
		}
		switch b.Term.Kind {
		case mir.TermJump:
			add(b.Term.Target, cur)
		case mir.TermBranch:
			add(b.Term.Then, cur)
			add(b.Term.Else, cur)
		case mir.TermSwitch:
			for _, c := range b.Term.Cases {
				add(c.Target, cur)
			}
		}
	}
	for bi, b := range f.Blocks {
		for ii := range b.Instrs {
			site := cleanupSite{mir.BlockId(bi), ii}
			if msg, ok := invalid[site]; ok {
				errs = append(errs, Error{Loc: siteLoc(f, site), Msg: msg})
			}
		}
		if exitOpen[mir.BlockId(bi)] {
			errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("exit leaves cleanup scope %%%s open or running", f.Values[scope].Name)})
		}
	}
	return errs
}

func cleanupInvalidMessage(op mir.OpKind, name string) string {
	switch op {
	case mir.OpCleanupScopeBegin:
		return fmt.Sprintf("cleanup.scope.begin of %%%s occurs while the scope is still active", name)
	case mir.OpCleanupPush:
		return fmt.Sprintf("cleanup.push requires open cleanup scope %%%s on every path", name)
	case mir.OpCleanupDisarm:
		return "cleanup.disarm requires an entry that is active on every path"
	case mir.OpCleanupScopeRun:
		return fmt.Sprintf("cleanup.scope.run requires open cleanup scope %%%s on every path", name)
	case mir.OpCleanupScopeEnd:
		return fmt.Sprintf("cleanup.scope.end requires run cleanup scope %%%s on every path", name)
	}
	return "invalid cleanup state"
}

func cloneConfigs(in map[cleanupConfig]bool) map[cleanupConfig]bool {
	out := make(map[cleanupConfig]bool, len(in))
	for c := range in {
		out[c] = true
	}
	return out
}

func cleanupActiveAppend(active string, index int) string {
	var encoded [4]byte
	binary.BigEndian.PutUint32(encoded[:], uint32(index))
	return active + string(encoded[:])
}

func cleanupActiveContains(active string, index int) bool {
	for i := 0; i+4 <= len(active); i += 4 {
		if int(binary.BigEndian.Uint32([]byte(active[i:i+4]))) == index {
			return true
		}
	}
	return false
}

func cleanupActiveRemove(active string, index int) (string, bool) {
	for i := 0; i+4 <= len(active); i += 4 {
		if int(binary.BigEndian.Uint32([]byte(active[i:i+4]))) == index {
			return active[:i] + active[i+4:], true
		}
	}
	return active, false
}

func cleanupActiveIndexes(active string) []int {
	indexes := make([]int, 0, len(active)/4)
	for i := 0; i+4 <= len(active); i += 4 {
		indexes = append(indexes, int(binary.BigEndian.Uint32([]byte(active[i:i+4]))))
	}
	return indexes
}

func recordActiveSet(a *cleanupAnalysis, site cleanupSite, active string, entries []cleanupEntry) {
	if a.activeSetsAtRun[site] == nil {
		a.activeSetsAtRun[site] = make(map[string][]cleanupEntry)
	}
	if _, exists := a.activeSetsAtRun[site][active]; exists {
		return
	}
	set := make([]cleanupEntry, 0, len(active)/4)
	for _, index := range cleanupActiveIndexes(active) {
		set = append(set, entries[index])
		appendActive(a, site, entries[index])
	}
	a.activeSetsAtRun[site][active] = set
}

func appendActive(a *cleanupAnalysis, site cleanupSite, e cleanupEntry) {
	for _, old := range a.activeAtRun[site] {
		if old.ID == e.ID {
			return
		}
	}
	a.activeAtRun[site] = append(a.activeAtRun[site], e)
	sort.Slice(a.activeAtRun[site], func(i, j int) bool {
		x, y := a.activeAtRun[site][i].Push, a.activeAtRun[site][j].Push
		return x.blk < y.blk || x.blk == y.blk && x.in < y.in
	})
}
func siteLoc(f *mir.Function, s cleanupSite) string {
	return locInstr(f, f.Blocks[s.blk], s.in, &f.Blocks[s.blk].Instrs[s.in])
}
