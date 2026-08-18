package verify

import "github.com/4fuu/alder/mir"

// pointCFG is a control-flow graph over instruction boundaries. boundary[b][i]
// is the point before instruction i (and boundary[b][len(Instrs)] is before
// the terminator). Every control-flow edge has its own node, preserving the
// identity of parallel edges.
type pointCFG struct {
	boundary [][]int
	edge     map[pointEdge]int
	preds    [][]int
	entry    int
	idom     []int
	domIn    []int
	domOut   []int
}

type pointEdge struct {
	block       mir.BlockId
	kind, index int
}

const (
	edgeFailure = iota
	edgeJump
	edgeThen
	edgeElse
	edgeSwitch
)

func buildPointCFG(f *mir.Function) *pointCFG {
	g := &pointCFG{boundary: make([][]int, len(f.Blocks)), edge: make(map[pointEdge]int)}
	addNode := func() int { g.preds = append(g.preds, nil); return len(g.preds) - 1 }
	for bi, b := range f.Blocks {
		g.boundary[bi] = make([]int, len(b.Instrs)+1)
		for i := range g.boundary[bi] {
			g.boundary[bi][i] = addNode()
		}
	}
	addEdgeNode := func(k pointEdge, from int, target mir.BlockId) {
		n := addNode()
		g.edge[k] = n
		g.preds[n] = append(g.preds[n], from)
		g.preds[g.boundary[target][0]] = append(g.preds[g.boundary[target][0]], n)
	}
	for bi, b := range f.Blocks {
		for i := range b.Instrs {
			g.preds[g.boundary[bi][i+1]] = append(g.preds[g.boundary[bi][i+1]], g.boundary[bi][i])
			if b.Instrs[i].FailTarget != mir.NoBlock {
				addEdgeNode(pointEdge{mir.BlockId(bi), edgeFailure, i}, g.boundary[bi][i], b.Instrs[i].FailTarget)
			}
		}
		end := g.boundary[bi][len(b.Instrs)]
		switch b.Term.Kind {
		case mir.TermJump:
			addEdgeNode(pointEdge{mir.BlockId(bi), edgeJump, 0}, end, b.Term.Target)
		case mir.TermBranch:
			addEdgeNode(pointEdge{mir.BlockId(bi), edgeThen, 0}, end, b.Term.Then)
			addEdgeNode(pointEdge{mir.BlockId(bi), edgeElse, 0}, end, b.Term.Else)
		case mir.TermSwitch:
			for i, c := range b.Term.Cases {
				addEdgeNode(pointEdge{mir.BlockId(bi), edgeSwitch, i}, end, c.Target)
			}
		}
	}
	g.entry = g.boundary[0][0]
	g.idom = computeIdoms(g.preds, g.entry)
	g.indexDominatorTree()
	return g
}

// computeIdoms returns the immediate dominator of each node using the
// Cooper/Harvey/Kennedy iterative algorithm. Unreachable nodes keep idom -1;
// the entry dominates itself.
func computeIdoms(preds [][]int, entry int) []int {
	n := len(preds)
	succ := make([][]int, n)
	for v, ps := range preds {
		for _, p := range ps {
			succ[p] = append(succ[p], v)
		}
	}
	seen := make([]bool, n)
	rpo := make([]int, 0, n)
	var dfs func(int)
	dfs = func(v int) {
		seen[v] = true
		for _, s := range succ[v] {
			if !seen[s] {
				dfs(s)
			}
		}
		rpo = append(rpo, v)
	}
	dfs(entry)
	for i, j := 0, len(rpo)-1; i < j; i, j = i+1, j-1 {
		rpo[i], rpo[j] = rpo[j], rpo[i]
	}
	rpoIndex := make([]int, n)
	for i := range rpoIndex {
		rpoIndex[i] = -1
	}
	for i, v := range rpo {
		rpoIndex[v] = i
	}
	idom := make([]int, n)
	for i := range idom {
		idom[i] = -1
	}
	idom[entry] = entry
	changed := true
	for changed {
		changed = false
		for _, b := range rpo[1:] {
			newIdom := -1
			for _, p := range preds[b] {
				if idom[p] < 0 {
					continue
				}
				if newIdom < 0 {
					newIdom = p
				} else {
					newIdom = intersectIdom(p, newIdom, idom, rpoIndex)
				}
			}
			if newIdom >= 0 && idom[b] != newIdom {
				idom[b] = newIdom
				changed = true
			}
		}
	}
	return idom
}

func intersectIdom(b1, b2 int, idom, rpoIndex []int) int {
	for b1 != b2 {
		for rpoIndex[b1] > rpoIndex[b2] {
			b1 = idom[b1]
		}
		for rpoIndex[b2] > rpoIndex[b1] {
			b2 = idom[b2]
		}
	}
	return b1
}

// indexDominatorTree assigns Euler-tour in/out times so dominates is O(1).
func (g *pointCFG) indexDominatorTree() {
	n := len(g.idom)
	children := make([][]int, n)
	for v, p := range g.idom {
		if p >= 0 && v != p {
			children[p] = append(children[p], v)
		}
	}
	g.domIn = make([]int, n)
	g.domOut = make([]int, n)
	stamp := 0
	var dfs func(int)
	dfs = func(v int) {
		stamp++
		g.domIn[v] = stamp
		for _, c := range children[v] {
			dfs(c)
		}
		g.domOut[v] = stamp
	}
	if g.entry >= 0 && g.entry < n && g.idom[g.entry] >= 0 {
		dfs(g.entry)
	}
}

// dominates reports whether def dominates use. Unreachable nodes are treated
// as dominating only themselves, matching the previous dataflow result for
// nodes with no predecessors.
func (g *pointCFG) dominates(use, def int) bool {
	if use == def {
		return true
	}
	if use < 0 || def < 0 || use >= len(g.domIn) || def >= len(g.domIn) {
		return false
	}
	if g.domIn[use] == 0 || g.domIn[def] == 0 {
		return false
	}
	return g.domIn[def] <= g.domIn[use] && g.domOut[use] <= g.domOut[def]
}

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
	return reachableFrom(f, 0)
}

// reachableFrom returns a per-block bit set marking blocks reachable from
// from (including from itself).
func reachableFrom(f *mir.Function, from mir.BlockId) []bool {
	n := len(f.Blocks)
	seen := make([]bool, n)
	if int(from) >= n {
		return seen
	}
	seen[from] = true
	queue := []mir.BlockId{from}
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

// dominatesWithEdges is dominatesSite plus the failure-edge positional rule:
// a definition in block B dominates a use in another block U only when some
// edge from B positioned after the definition can reach U. Checked-operation
// failure edges exit their block mid-way, so instructions after the edge do
// not dominate the failure target.
func dominatesWithEdges(f *mir.Function, dom [][]bool, defBlk mir.BlockId, defIn int, useBlk mir.BlockId, useIn int) bool {
	if defBlk == useBlk {
		return defIn < 0 || defIn < useIn
	}
	if int(defBlk) >= len(dom) || !dom[useBlk][defBlk] {
		return false
	}
	return edgeAfterCanReach(f, defBlk, defIn, useBlk)
}

// edgeAfterCanReach reports whether an edge from block b at a position after
// pos leads transitively to block target. The terminator sits after every
// instruction, so terminator edges always qualify.
func edgeAfterCanReach(f *mir.Function, b mir.BlockId, pos int, target mir.BlockId) bool {
	blk := f.Blocks[b]
	for i := range blk.Instrs {
		t := blk.Instrs[i].FailTarget
		if t == mir.NoBlock || i <= pos {
			continue
		}
		if t == target || canReachBlock(f, t, target) {
			return true
		}
	}
	switch blk.Term.Kind {
	case mir.TermJump:
		return blk.Term.Target == target || canReachBlock(f, blk.Term.Target, target)
	case mir.TermBranch:
		return (blk.Term.Then == target || canReachBlock(f, blk.Term.Then, target)) ||
			(blk.Term.Else == target || canReachBlock(f, blk.Term.Else, target))
	case mir.TermSwitch:
		for i := range blk.Term.Cases {
			t := blk.Term.Cases[i].Target
			if t == target || canReachBlock(f, t, target) {
				return true
			}
		}
	}
	return false
}

// canReachBlock reports whether block from can reach block target through
// CFG edges (including itself).
func canReachBlock(f *mir.Function, from, target mir.BlockId) bool {
	if from == target {
		return true
	}
	n := len(f.Blocks)
	seen := make([]bool, n)
	queue := []mir.BlockId{from}
	for len(queue) > 0 {
		b := queue[0]
		queue = queue[1:]
		if int(b) >= n || seen[b] {
			continue
		}
		seen[b] = true
		for _, s := range successors(f, f.Blocks[b]) {
			if s == target {
				return true
			}
			if int(s) < n && !seen[s] {
				queue = append(queue, s)
			}
		}
	}
	return false
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
			for _, v := range instrValueOperands(in) {
				add(v, mir.BlockId(bi), ii, -1)
			}
			if in.FailTarget != mir.NoBlock {
				for _, v := range in.FailArgs {
					add(v, mir.BlockId(bi), ii, -1)
				}
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
	seen := make(map[*mir.Place]bool)
	for p := &in.Place; p != nil && !seen[p]; {
		seen[p] = true
		switch p.Kind {
		case mir.PlaceField:
			p = p.Base
			continue
		case mir.PlaceDeref:
			*out = append(*out, useSite{value: p.Deref, block: mir.BlockId(bi), instr: ii, swCase: -1})
		}
		return
	}
}

// placeDerefRoot returns the checked reference at the root of a dereference-
// based place. It is iterative so malformed API input cannot recurse forever.
func placeDerefRoot(p *mir.Place) (mir.ValueId, bool) {
	seen := make(map[*mir.Place]bool)
	for p != nil && !seen[p] {
		seen[p] = true
		switch p.Kind {
		case mir.PlaceField:
			p = p.Base
		case mir.PlaceDeref:
			return p.Deref, true
		default:
			return mir.NoValue, false
		}
	}
	return mir.NoValue, false
}

// useSiteLoc renders the location of a value use for diagnostics.
func useSiteLoc(f *mir.Function, u useSite) string {
	loc := locFunc(f) + ": block " + f.Blocks[u.block].Name
	if u.instr >= 0 {
		loc += ": op " + f.Blocks[u.block].Instrs[u.instr].Op.String()
	} else {
		loc += ": terminator " + f.Blocks[u.block].Term.Kind.String()
	}
	return loc
}

// blockIndexOf returns the ID of a block within its function.
func blockIndexOf(f *mir.Function, want *mir.Block) mir.BlockId {
	for i, b := range f.Blocks {
		if b == want {
			return mir.BlockId(i)
		}
	}
	return mir.NoBlock
}

// edgeArgsTo returns the argument list of the edge from block b to target,
// or nil when no such edge exists.
func edgeArgsTo(f *mir.Function, b *mir.Block, target mir.BlockId) []mir.ValueId {
	for i := range b.Instrs {
		if b.Instrs[i].FailTarget == target {
			return b.Instrs[i].FailArgs
		}
	}
	switch b.Term.Kind {
	case mir.TermJump:
		if b.Term.Target == target {
			return b.Term.Args
		}
	case mir.TermBranch:
		if b.Term.Then == target {
			return b.Term.ThenArgs
		}
		if b.Term.Else == target {
			return b.Term.ElseArgs
		}
	case mir.TermSwitch:
		for i := range b.Term.Cases {
			if b.Term.Cases[i].Target == target {
				return b.Term.Cases[i].Args
			}
		}
	}
	return nil
}

// placeRootLocal returns the local slot a place ultimately reads or writes,
// or false when the place is deref-based.
func placeRootLocal(p *mir.Place) (mir.LocalId, bool) {
	switch p.Kind {
	case mir.PlaceLocal:
		return p.Local, true
	case mir.PlaceField:
		if p.Base != nil {
			return placeRootLocal(p.Base)
		}
	}
	return mir.NoLocal, false
}

// valueName returns the printable name of a value for diagnostics.
func valueName(f *mir.Function, v mir.ValueId) string {
	if int(v) >= len(f.Values) {
		return "<invalid value>"
	}
	return "%" + f.Values[v].Name
}
