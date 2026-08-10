package verify

import "github.com/4fuu/aster/mir"

// successors returns every block that can follow b: terminator targets and
// checked-operation failure edges, in declaration order.
func successors(f *mir.Function, b *mir.Block) []mir.BlockId {
	var out []mir.BlockId
	for i := range b.Instrs {
		if t := b.Instrs[i].FailTarget; t != mir.NoBlock {
			out = append(out, t)
		}
	}
	switch b.Term.Kind {
	case mir.TermJump:
		out = append(out, b.Term.Target)
	case mir.TermBranch:
		out = append(out, b.Term.Then, b.Term.Else)
	case mir.TermSwitch:
		for i := range b.Term.Cases {
			out = append(out, b.Term.Cases[i].Target)
		}
	}
	return out
}

// reachable returns a per-block bit set marking blocks reachable from the
// entry block (block 0).
func reachable(f *mir.Function) []bool {
	n := len(f.Blocks)
	seen := make([]bool, n)
	if n == 0 {
		return seen
	}
	seen[0] = true
	queue := []mir.BlockId{0}
	for len(queue) > 0 {
		b := queue[0]
		queue = queue[1:]
		for _, s := range successors(f, f.Blocks[b]) {
			if int(s) < n && !seen[s] {
				seen[s] = true
				queue = append(queue, s)
			}
		}
	}
	return seen
}

// dominators returns, for each block, the set of blocks that dominate it
// (including itself). Blocks unreachable from the entry dominate only
// themselves. The result is a dense boolean matrix indexed by BlockId.
func dominators(f *mir.Function) [][]bool {
	n := len(f.Blocks)
	dom := make([][]bool, n)
	if n == 0 {
		return dom
	}
	all := make([]bool, n)
	for i := range all {
		all[i] = true
	}
	for i := range dom {
		dom[i] = make([]bool, n)
	}
	dom[0][0] = true
	changed := true
	for changed {
		changed = false
		for b := 1; b < n; b++ {
			next := make([]bool, n)
			copy(next, all)
			first := true
			for _, p := range preds(f, mir.BlockId(b)) {
				if first {
					copy(next, dom[p])
					first = false
				} else {
					for i := 0; i < n; i++ {
						next[i] = next[i] && dom[p][i]
					}
				}
			}
			if first {
				// No predecessors: unreachable, dominates only itself.
				for i := range next {
					next[i] = false
				}
				next[b] = true
			} else {
				next[b] = true
			}
			if !equalBools(next, dom[b]) {
				dom[b] = next
				changed = true
			}
		}
	}
	return dom
}

func preds(f *mir.Function, b mir.BlockId) []mir.BlockId {
	var out []mir.BlockId
	for i, p := range f.Blocks {
		for _, s := range successors(f, p) {
			if s == b {
				out = append(out, mir.BlockId(i))
			}
		}
	}
	return out
}

func equalBools(a, b []bool) bool {
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// inCycle reports whether the block lies on a cycle (it can reach itself).
func inCycle(f *mir.Function, b mir.BlockId) bool {
	n := len(f.Blocks)
	seen := make([]bool, n)
	queue := successors(f, f.Blocks[b])
	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]
		if cur == b {
			return true
		}
		if int(cur) >= n || seen[cur] {
			continue
		}
		seen[cur] = true
		queue = append(queue, successors(f, f.Blocks[cur])...)
	}
	return false
}

// dominatesSite reports whether a definition at (defBlock, defInstr) dominates
// a use site at (useBlock, useInstr). Within one block, a definition must
// precede the use; a block parameter (defInstr < 0) dominates the whole block.
// useInstr == len(block.Instrs) represents the terminator.
func dominatesSite(dom [][]bool, defBlock mir.BlockId, defInstr int, useBlock mir.BlockId, useInstr int) bool {
	if defBlock == useBlock {
		return defInstr < 0 || defInstr < useInstr
	}
	return int(defBlock) < len(dom) && dom[useBlock][defBlock]
}

// useSite is one value use within a function.
type useSite struct {
	value  mir.ValueId
	block  mir.BlockId
	instr  int // instruction index, or -1 for the terminator
	swCase int // switch case index for case edge arguments, otherwise -1
}

// collectUses returns every value use in the function in deterministic order:
// per block, instructions in order, then the terminator.
func collectUses(f *mir.Function) []useSite {
	var out []useSite
	add := func(v mir.ValueId, b mir.BlockId, instr, swCase int) {
		if v != mir.NoValue {
			out = append(out, useSite{value: v, block: b, instr: instr, swCase: swCase})
		}
	}
	for bi, b := range f.Blocks {
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			addPlace(&out, f, in, bi, ii)
			for _, v := range []mir.ValueId{
				in.StoreVal, in.Mark, in.Count, in.CopyVal, in.Scope, in.CleanupID,
				in.A, in.B, in.Index, in.Lo, in.Hi, in.EnumValue, in.Payload,
				in.Table, in.ID, in.TableVal, in.View,
			} {
				add(v, mir.BlockId(bi), ii, -1)
			}
			for _, v := range in.CleanupArgs {
				add(v, mir.BlockId(bi), ii, -1)
			}
			for _, v := range in.Args {
				add(v, mir.BlockId(bi), ii, -1)
			}
			for _, v := range in.FailArgs {
				add(v, mir.BlockId(bi), ii, -1)
			}
			for _, af := range in.AggFields {
				add(af.Value, mir.BlockId(bi), ii, -1)
			}
		}
		b := mir.BlockId(bi)
		switch f.Blocks[bi].Term.Kind {
		case mir.TermJump:
			for _, v := range f.Blocks[bi].Term.Args {
				add(v, b, -1, -1)
			}
		case mir.TermBranch:
			add(f.Blocks[bi].Term.Cond, b, -1, -1)
			for _, v := range f.Blocks[bi].Term.ThenArgs {
				add(v, b, -1, -1)
			}
			for _, v := range f.Blocks[bi].Term.ElseArgs {
				add(v, b, -1, -1)
			}
		case mir.TermSwitch:
			add(f.Blocks[bi].Term.Value, b, -1, -1)
			for ci, c := range f.Blocks[bi].Term.Cases {
				for _, v := range c.Args {
					add(v, b, -1, ci)
				}
			}
		case mir.TermReturn, mir.TermFail:
			add(f.Blocks[bi].Term.Result, b, -1, -1)
		}
	}
	return out
}

func addPlace(out *[]useSite, f *mir.Function, in *mir.Instr, bi, ii int) {
	var walk func(p *mir.Place)
	walk = func(p *mir.Place) {
		if p == nil {
			return
		}
		switch p.Kind {
		case mir.PlaceField:
			walk(p.Base)
		case mir.PlaceDeref:
			*out = append(*out, useSite{value: p.Deref, block: mir.BlockId(bi), instr: ii, swCase: -1})
		}
	}
	walk(&in.Place)
}

// valueName returns the printable name of a value for diagnostics.
func valueName(f *mir.Function, v mir.ValueId) string {
	if int(v) >= len(f.Values) {
		return "<invalid value>"
	}
	return "%" + f.Values[v].Name
}
