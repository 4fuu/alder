package verify

import (
	"fmt"
	"strings"

	"github.com/4fuu/alder/mir"
)

// frameFlow is the state-indexed fact set for one step block. MustInit records
// fields that are initialized on every path; MayOut records whether out may
// have been written on any path. Variant is the ordinal of the state stored
// last on every path, or -1 when paths disagree or no state was stored.
type frameFlow struct {
	variant  int
	mustInit []bool
	mayOut   bool
}

func cloneFrameFlow(f frameFlow) frameFlow {
	return frameFlow{variant: f.variant, mustInit: append([]bool(nil), f.mustInit...), mayOut: f.mayOut}
}

func frameFlowEqual(a, b frameFlow) bool {
	if a.variant != b.variant || a.mayOut != b.mayOut || len(a.mustInit) != len(b.mustInit) {
		return false
	}
	for i := range a.mustInit {
		if a.mustInit[i] != b.mustInit[i] {
			return false
		}
	}
	return true
}

func mergeFrameFlow(dst *frameFlow, src frameFlow) bool {
	changed := false
	if dst.variant != src.variant {
		if dst.variant != -1 {
			dst.variant = -1
			changed = true
		}
	}
	if src.mayOut && !dst.mayOut {
		dst.mayOut = true
		changed = true
	}
	for i := range dst.mustInit {
		if dst.mustInit[i] && !src.mustInit[i] {
			dst.mustInit[i] = false
			changed = true
		}
	}
	return changed
}

// frameStateErrors validates the canonical dispatch, save, resume, and status
// protocol pinned by "State numbering and dispatch" and "Frame access and
// verification".
func frameStateErrors(m *mir.Module, inv *frameInventory) []Error {
	if inv == nil || len(inv.steps) == 0 {
		return nil
	}
	var errs []Error
	for _, step := range inv.steps {
		errs = append(errs, frameStepStateErrors(m, inv, step)...)
	}
	return errs
}

func frameStepStateErrors(m *mir.Module, inv *frameInventory, step *frameStepInfo) []Error {
	f := step.fn
	var errs []Error
	if len(f.Blocks) == 0 || f.Blocks[0] == nil {
		return []Error{{Loc: locFunc(f), Msg: "step function has no dispatch block"}}
	}
	dispatchBlock := f.Blocks[0]
	dispatchLoc := locBlock(f, dispatchBlock)
	// One dispatch block: load state, then switch on it with one case per
	// state variant and no default.
	dispatchOK := len(dispatchBlock.Instrs) == 1 && dispatchBlock.Instrs[0].Op == mir.OpLoad
	var stateLoad mir.ValueId = mir.NoValue
	if dispatchOK {
		in := &dispatchBlock.Instrs[0]
		field, deref, ok := frameFieldPlace(&in.Place)
		dispatchOK = ok && field == "state" && deref == step.frameParam
		stateLoad = in.Result
	}
	if !dispatchOK || dispatchBlock.Term.Kind != mir.TermSwitch || dispatchBlock.Term.Value != stateLoad {
		return []Error{{Loc: dispatchLoc, Msg: "step function must begin with one dispatch block that loads the frame state and switches on it"}}
	}
	dispatch := &dispatchBlock.Term
	if len(dispatch.Cases) != len(step.variants) {
		errs = append(errs, Error{Loc: dispatchLoc, Msg: "dispatch switch must list every state variant exactly once"})
	}
	seenVariant := make(map[string]bool)
	for _, c := range dispatch.Cases {
		if c.Variant == "" {
			errs = append(errs, Error{Loc: dispatchLoc, Msg: "dispatch switch may not have a default case"})
			continue
		}
		if _, ok := step.variantIdx[c.Variant]; !ok {
			continue // Phase 3 reports unknown variants.
		}
		if seenVariant[c.Variant] {
			errs = append(errs, Error{Loc: dispatchLoc, Msg: "dispatch switch must list every state variant exactly once"})
		}
		seenVariant[c.Variant] = true
		if len(c.Args) != 0 {
			errs = append(errs, Error{Loc: dispatchLoc, Msg: "dispatch case takes no block arguments"})
		}
	}
	for name := range step.variantIdx {
		if !seenVariant[name] {
			errs = append(errs, Error{Loc: dispatchLoc, Msg: "dispatch switch must list every state variant exactly once"})
			break
		}
	}
	// Resume and entry blocks have exactly one predecessor: the dispatch case.
	preds := framePredecessors(f)
	for _, variant := range step.variants {
		name := variant.Name
		target, ok := step.dispatch[name]
		if !ok || int(target) >= len(f.Blocks) || f.Blocks[target] == nil {
			continue
		}
		if len(preds[target]) != 1 || preds[target][0] != 0 {
			errs = append(errs, Error{Loc: locBlock(f, f.Blocks[target]), Msg: fmt.Sprintf("state %q target must have exactly one predecessor, the dispatch case", name)})
		}
	}
	// Save lists, one per non-entry state.
	save := make(map[string][]string)
	suspendBlock := make(map[string]mir.BlockId)
	for bi, b := range f.Blocks {
		if bi == 0 || b == nil {
			continue
		}
		stateStore := -1
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpStore {
				continue
			}
			field, deref, ok := frameFieldPlace(&in.Place)
			if !ok || deref != step.frameParam || field != "state" {
				continue
			}
			if stateStore >= 0 {
				errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a block stores the frame state more than once"})
				continue
			}
			stateStore = ii
			variant, ok := frameEnumVariant(f, in.StoreVal, step.stateType)
			if !ok {
				errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a stored frame state must construct a state enum variant"})
				continue
			}
			if variant == "entry" {
				errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a step may not store the entry state"})
				continue
			}
			if _, ok := step.variantIdx[variant]; !ok {
				continue
			}
			if _, dup := suspendBlock[variant]; dup {
				errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: fmt.Sprintf("state %s must have exactly one suspend block", variant)})
				continue
			}
			suspendBlock[variant] = mir.BlockId(bi)
			fields, listErr := frameSaveList(m, inv, f, step, b, stateStore)
			if listErr != "" {
				errs = append(errs, Error{Loc: locInstr(f, b, stateStore, &b.Instrs[stateStore]), Msg: listErr})
			}
			save[variant] = fields
			if b.Term.Kind != mir.TermReturn || b.Term.Result == mir.NoValue {
				errs = append(errs, Error{Loc: locTerm(f, b), Msg: "a suspend block must return a call or park status"})
				continue
			}
			status, ok := frameEnumVariant(f, b.Term.Result, inv.status)
			if !ok {
				errs = append(errs, Error{Loc: locTerm(f, b), Msg: "a step return must construct a status variant"})
				continue
			}
			if status != "call" && status != "park" {
				errs = append(errs, Error{Loc: locTerm(f, b), Msg: fmt.Sprintf("state %s suspend block must return call or park, got %s", variant, status)})
			}
		}
	}
	for _, variant := range step.variants {
		name := variant.Name
		if name == "entry" {
			continue
		}
		if _, ok := suspendBlock[name]; !ok {
			errs = append(errs, Error{Loc: dispatchLoc, Msg: fmt.Sprintf("state %s must have exactly one suspend block", name)})
		}
	}
	// Resume load lists must equal the save lists as ordered field sets.
	for _, variant := range step.variants {
		name := variant.Name
		if name == "entry" {
			continue
		}
		target, dispatched := step.dispatch[name]
		if !dispatched {
			continue
		}
		fields, ok := save[name]
		if !ok {
			continue
		}
		loads := frameResumeLoads(m, inv, f, step, target)
		if !frameSameFields(loads, fields) {
			errs = append(errs, Error{Loc: locBlock(f, f.Blocks[target]), Msg: fmt.Sprintf("state %s must load exactly the saved frame fields in frame order", name)})
		}
	}
	// Status and initialization dataflow.
	flowErrs, _ := frameStatusFlow(m, inv, step, save, suspendBlock)
	errs = append(errs, flowErrs...)
	return errs
}

// framePredecessors returns the predecessor block list of every block,
// including checked-failure edges.
func framePredecessors(f *mir.Function) [][]mir.BlockId {
	preds := make([][]mir.BlockId, len(f.Blocks))
	for bi, b := range f.Blocks {
		if b == nil {
			continue
		}
		addEdge := func(target mir.BlockId) {
			if int(target) < len(preds) {
				preds[target] = append(preds[target], mir.BlockId(bi))
			}
		}
		for ii := range b.Instrs {
			if b.Instrs[ii].FailTarget != mir.NoBlock {
				addEdge(b.Instrs[ii].FailTarget)
			}
		}
		switch b.Term.Kind {
		case mir.TermJump:
			addEdge(b.Term.Target)
		case mir.TermBranch:
			addEdge(b.Term.Then)
			addEdge(b.Term.Else)
		case mir.TermSwitch:
			for _, c := range b.Term.Cases {
				addEdge(c.Target)
			}
		}
	}
	return preds
}

// frameSaveList returns the own-frame fields a suspend block stores after its
// state, excluding state itself, in canonical frame order. A scope anchor
// store may precede the registration it enables, so scope fields are exempt
// from the physical store-order check.
func frameSaveList(m *mir.Module, inv *frameInventory, f *mir.Function, step *frameStepInfo, b *mir.Block, stateStore int) ([]string, string) {
	var fields []string
	seen := make(map[string]bool)
	lastIndex := -1
	orderErr := ""
	for ii := range b.Instrs {
		in := &b.Instrs[ii]
		if in.Op != mir.OpStore {
			continue
		}
		field, deref, ok := frameFieldPlace(&in.Place)
		if !ok || deref != step.frameParam {
			continue
		}
		fi, ok := step.frame.byName[field]
		if !ok {
			continue
		}
		kind := step.frame.fields[fi].kind
		if field == "state" {
			if ii != stateStore {
				return nil, "a block stores the frame state more than once"
			}
			continue
		}
		if ii < stateStore {
			// Stores before the state store initialize frame storage for the
			// segment; the canonical save list begins at the state store.
			continue
		}
		switch kind {
		case frameFieldCallee, frameFieldCalleeOwner, frameFieldDomain, frameFieldLocal, frameFieldTemp, frameFieldCleanup, frameFieldScope:
		case frameFieldOut:
			return fields, "a suspend block may not save the out field"
		default:
			return fields, fmt.Sprintf("a suspend block may not save frame field %q", field)
		}
		if seen[field] {
			// A field stored more than once in one suspend block counts once
			// in that block's save set.
			continue
		}
		if !isScopeField(step, fi) {
			if fi <= lastIndex && orderErr == "" {
				orderErr = "a suspend block must save frame fields in frame declaration order"
			}
			if fi > lastIndex {
				lastIndex = fi
			}
		}
		seen[field] = true
		fields = append(fields, field)
	}
	sortFrameFields(step, fields)
	return fields, orderErr
}

func isScopeField(step *frameStepInfo, fi int) bool {
	return fi >= 0 && fi < len(step.frame.fields) && step.frame.fields[fi].kind == frameFieldScope
}

// sortFrameFields orders a save list by frame declaration position. A scope
// anchor is stored before the registration it enables, so its store can
// precede a c<i> store; the canonical list remains in frame order.
func sortFrameFields(step *frameStepInfo, fields []string) {
	for i := 1; i < len(fields); i++ {
		for j := i; j > 0 && step.frame.byName[fields[j]] < step.frame.byName[fields[j-1]]; j-- {
			fields[j], fields[j-1] = fields[j-1], fields[j]
		}
	}
}

// frameResumeLoads returns the own-frame fields loaded on the canonical resume
// path: the dispatch target and the linear continuation that follows a
// cancellation check.
func frameResumeLoads(m *mir.Module, inv *frameInventory, f *mir.Function, step *frameStepInfo, target mir.BlockId) []string {
	var loads []string
	visited := make(map[mir.BlockId]bool)
	cur := target
	preds := framePredecessors(f)
	for int(cur) < len(f.Blocks) && f.Blocks[cur] != nil && !visited[cur] {
		visited[cur] = true
		b := f.Blocks[cur]
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpLoad {
				continue
			}
			field, deref, ok := frameFieldPlace(&in.Place)
			if !ok || deref != step.frameParam {
				continue
			}
			fi, ok := step.frame.byName[field]
			if !ok {
				continue
			}
			switch step.frame.fields[fi].kind {
			case frameFieldCallee, frameFieldCalleeOwner, frameFieldDomain, frameFieldLocal, frameFieldTemp, frameFieldCleanup, frameFieldScope:
				loads = append(loads, field)
			}
		}
		switch b.Term.Kind {
		case mir.TermJump:
			next := b.Term.Target
			if int(next) >= len(f.Blocks) || len(preds[next]) != 1 {
				return loads
			}
			cur = next
		case mir.TermBranch:
			if !frameCancelCond(m, f, b.Term.Cond) {
				return loads
			}
			next := b.Term.Else
			if int(next) >= len(f.Blocks) || len(preds[next]) != 1 || next == 0 {
				return loads
			}
			cur = next
		default:
			return loads
		}
	}
	return loads
}

func frameSameFields(a, b []string) bool {
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

// frameEnumVariant resolves a direct enum.construct of the given enum type.
func frameEnumVariant(f *mir.Function, v mir.ValueId, enumType mir.TypeId) (string, bool) {
	if int(v) >= len(f.Values) {
		return "", false
	}
	def := f.Values[v].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return "", false
	}
	in := &f.Blocks[def.Block].Instrs[def.Instr]
	if in.Op != mir.OpEnumConstruct || in.TypeOp != enumType {
		return "", false
	}
	return in.Variant, true
}

// frameCancelCond recognizes the pinned cancellation observation: a binding
// call whose resolved target is the runtime's alder_task_cancelled entry.
func frameCancelCond(m *mir.Module, f *mir.Function, v mir.ValueId) bool {
	if int(v) >= len(f.Values) {
		return false
	}
	def := f.Values[v].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return false
	}
	in := &f.Blocks[def.Block].Instrs[def.Instr]
	if in.Op == mir.OpCBindingCall {
		if _, fn, ok := m.BindingFuncAt(in.CBinding); ok {
			return fn.CName == "alder_task_cancelled"
		}
	}
	return false
}

// frameStatusFlow converges per-block state and initialization facts and then
// checks each return once in declaration order.
func frameStatusFlow(m *mir.Module, inv *frameInventory, step *frameStepInfo, save map[string][]string, suspendBlock map[string]mir.BlockId) ([]Error, []frameFlow) {
	f := step.fn
	info := step.frame
	fields := info.fields
	base := func() []bool {
		must := make([]bool, len(fields))
		for i, field := range fields {
			if field.kind == frameFieldParam || field.kind == frameFieldOwner || field.kind == frameFieldState {
				must[i] = true
			}
		}
		return must
	}
	in := make([]frameFlow, len(f.Blocks))
	seeded := make([]bool, len(f.Blocks))
	for i := range in {
		in[i].variant = -1
	}
	var queue []mir.BlockId
	queued := make([]bool, len(f.Blocks))
	enqueue := func(b mir.BlockId) {
		if int(b) < len(queued) && !queued[b] {
			queued[b] = true
			queue = append(queue, b)
		}
	}
	// Roots: the dispatch block itself and the state targets.
	if len(f.Blocks) > 0 {
		seeded[0] = true
		in[0] = frameFlow{variant: -1, mustInit: base()}
		enqueue(0)
	}
	seedTarget := func(name string, target mir.BlockId, suspendOut frameFlow, haveOut bool) {
		idx, ok := step.variantIdx[name]
		if !ok || int(target) >= len(f.Blocks) {
			return
		}
		seed := frameFlow{variant: idx, mustInit: base()}
		if name != "entry" {
			for _, field := range save[name] {
				if fi, ok := info.byName[field]; ok {
					seed.mustInit[fi] = true
				}
			}
			if haveOut {
				// out is stable frame storage and survives a suspension even
				// though it is not part of the canonical save list.
				if oi, ok := info.byName["out"]; ok {
					seed.mustInit[oi] = suspendOut.mustInit[oi]
				}
				seed.mayOut = suspendOut.mayOut
			}
		}
		if !seeded[target] || !frameFlowEqual(in[target], seed) {
			in[target] = seed
			seeded[target] = true
			enqueue(target)
		}
	}
	// The entry target is a fixed root; non-entry seeds follow their suspend
	// blocks and are refreshed as the worklist discovers them.
	if target, ok := step.dispatch["entry"]; ok {
		seedTarget("entry", target, frameFlow{}, false)
	}
	for len(queue) > 0 {
		bi := queue[0]
		queue = queue[1:]
		queued[bi] = false
		if int(bi) >= len(f.Blocks) || f.Blocks[bi] == nil {
			continue
		}
		out := cloneFrameFlow(in[bi])
		b := f.Blocks[bi]
		for ii := range b.Instrs {
			instr := &b.Instrs[ii]
			if instr.Op != mir.OpStore {
				continue
			}
			field, deref, ok := frameFieldPlace(&instr.Place)
			if !ok || deref != step.frameParam {
				continue
			}
			fi, ok := info.byName[field]
			if !ok {
				continue
			}
			out.mustInit[fi] = true
			if field == "out" {
				out.mayOut = true
			}
			if field == "state" {
				variant, ok := frameEnumVariant(f, instr.StoreVal, step.stateType)
				if ok {
					if idx, ok := step.variantIdx[variant]; ok {
						out.variant = idx
					}
				}
			}
		}
		// Refresh a resume root from its suspend block's settled out facts.
		if bi != 0 {
			for _, variant := range step.variants {
				name := variant.Name
				sb, ok := suspendBlock[name]
				if !ok || sb != bi {
					continue
				}
				target, ok := step.dispatch[name]
				if !ok {
					continue
				}
				seedTarget(name, target, out, true)
			}
		}
		switch b.Term.Kind {
		case mir.TermJump:
			framePropagate(in, seeded, f, b.Term.Target, out, enqueue)
		case mir.TermBranch:
			framePropagate(in, seeded, f, b.Term.Then, out, enqueue)
			framePropagate(in, seeded, f, b.Term.Else, out, enqueue)
		case mir.TermSwitch:
			for _, c := range b.Term.Cases {
				framePropagate(in, seeded, f, c.Target, out, enqueue)
			}
		}
	}
	// Check every return once, using the converged in-facts.
	teardown := frameTeardownBlocks(m, f)
	reachable := reachable(f)
	var errs []Error
	for bi, b := range f.Blocks {
		if b == nil || !reachable[bi] {
			continue
		}
		flow := cloneFrameFlow(in[bi])
		for ii := range b.Instrs {
			instr := &b.Instrs[ii]
			if instr.Op != mir.OpStore {
				continue
			}
			field, deref, ok := frameFieldPlace(&instr.Place)
			if !ok || deref != step.frameParam {
				continue
			}
			fi, ok := info.byName[field]
			if !ok {
				continue
			}
			flow.mustInit[fi] = true
			if field == "out" {
				flow.mayOut = true
			}
			if field == "state" {
				if variant, ok := frameEnumVariant(f, instr.StoreVal, step.stateType); ok {
					if idx, ok := step.variantIdx[variant]; ok {
						flow.variant = idx
					}
				}
			}
		}
		if b.Term.Kind != mir.TermReturn || b.Term.Result == mir.NoValue {
			continue
		}
		loc := locTerm(f, b)
		status, ok := frameEnumVariant(f, b.Term.Result, inv.status)
		if !ok {
			errs = append(errs, Error{Loc: loc, Msg: "a step return must construct a status variant"})
			continue
		}
		switch status {
		case "done":
			if oi, ok := info.byName["out"]; !ok || !flow.mustInit[oi] {
				errs = append(errs, Error{Loc: loc, Msg: "done requires out to be initialized on every path"})
			}
		case "call", "park":
			name := ""
			if flow.variant >= 0 {
				name = step.variants[flow.variant].Name
			}
			kind, index, ok := frameStateKind(name)
			if !ok {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("%s requires a resume or cleanup state on every path", status)})
				continue
			}
			if kind == "resume" {
				hasPair := index >= 0 && index < len(info.callPoint) && info.callPoint[index]
				if status == "call" {
					if !hasPair {
						errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("call requires a call-type resume state with matching x%d and y%d", index, index)})
						continue
					}
					if !frameHasFields(save[name], "x"+frameNumber(index), "y"+frameNumber(index)) {
						errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("call requires the suspend block to save x%d and y%d", index, index)})
					}
				} else if hasPair {
					errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("park requires a resume state without x%d and y%d", index, index)})
				}
				break
			}
			// A cleanup<j> state is the suspension point of a suspending
			// cleanup entry. Its x<i>/y<i> index is the suspension point, not
			// j, so the saved pair identifies the call handoff.
			pairs := frameSavedCalleePairs(info, save[name])
			if status == "call" {
				if len(pairs) == 0 {
					errs = append(errs, Error{Loc: loc, Msg: "call requires a cleanup state with matching saved x<i> and y<i>"})
				}
			} else if len(pairs) != 0 {
				errs = append(errs, Error{Loc: loc, Msg: "park requires a cleanup state without saved x<i> and y<i>"})
			}
		case "cancelled":
			if flow.mayOut {
				errs = append(errs, Error{Loc: loc, Msg: "cancelled requires out to remain uninitialized"})
			}
			if !teardown[bi] {
				errs = append(errs, Error{Loc: loc, Msg: "cancelled is reachable only from a cancellation teardown path"})
			}
		}
	}
	return errs, in
}

func framePropagate(in []frameFlow, seeded []bool, f *mir.Function, target mir.BlockId, out frameFlow, enqueue func(mir.BlockId)) {
	if int(target) >= len(in) || target == 0 {
		return
	}
	if !seeded[target] {
		in[target] = cloneFrameFlow(out)
		seeded[target] = true
		enqueue(target)
		return
	}
	if mergeFrameFlow(&in[target], out) {
		enqueue(target)
	}
}

func frameStateKind(name string) (string, int, bool) {
	for _, prefix := range []string{"resume", "cleanup"} {
		if !strings.HasPrefix(name, prefix) {
			continue
		}
		digits := name[len(prefix):]
		if digits == "" {
			return "", -1, false
		}
		index := 0
		for i := 0; i < len(digits); i++ {
			if digits[i] < '0' || digits[i] > '9' {
				return "", -1, false
			}
			index = index*10 + int(digits[i]-'0')
		}
		return prefix, index, true
	}
	return "", -1, false
}

// frameSavedCalleePairs returns the suspension-point indexes whose complete
// x<i>/y<i> pair is in the state's ordered save list.
func frameSavedCalleePairs(info *frameInfo, save []string) []int {
	var pairs []int
	for i := range info.callPoint {
		if info.callPoint[i] && frameHasFields(save, "x"+frameNumber(i), "y"+frameNumber(i)) {
			pairs = append(pairs, i)
		}
	}
	return pairs
}

func frameNumber(n int) string { return fmt.Sprintf("%d", n) }

func frameHasFields(fields []string, want ...string) bool {
	for _, w := range want {
		found := false
		for _, f := range fields {
			if f == w {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

// frameTeardownBlocks returns the blocks every path to which crosses a
// cancellation branch. The entry block is never a teardown block.
func frameTeardownBlocks(m *mir.Module, f *mir.Function) []bool {
	preds := framePredecessors(f)
	cancelEdge := make(map[[2]mir.BlockId]bool)
	for bi, b := range f.Blocks {
		if b == nil || b.Term.Kind != mir.TermBranch || !frameCancelCond(m, f, b.Term.Cond) {
			continue
		}
		cancelEdge[[2]mir.BlockId{mir.BlockId(bi), b.Term.Then}] = true
	}
	teardown := make([]bool, len(f.Blocks))
	for i := range teardown {
		teardown[i] = true
	}
	if len(teardown) > 0 {
		teardown[0] = false
	}
	changed := true
	for changed {
		changed = false
		for bi, b := range f.Blocks {
			if bi == 0 || b == nil {
				continue
			}
			val := len(preds[bi]) > 0
			for _, pred := range preds[bi] {
				if !teardown[pred] && !cancelEdge[[2]mir.BlockId{pred, mir.BlockId(bi)}] {
					val = false
					break
				}
			}
			if teardown[bi] != val {
				teardown[bi] = val
				changed = true
			}
		}
	}
	return teardown
}
