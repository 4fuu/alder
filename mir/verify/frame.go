package verify

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/4fuu/alder/mir"
)

// Step frames are ordinary MIR 6 aggregates with reserved names. These
// constants and the inventory below are the single recognition point shared by
// the phases that add frame rules; docs/mir.md "Frame access and verification"
// pins every acceptance and rejection implemented here.
const (
	frameReservedPrefix = "__alder_step."
	frameStatusName     = "__alder_step.status"
	frameRunPrefix      = "__alder_step.run."
	frameTypePrefix     = "__alder_step.frame."
	frameStatePrefix    = "__alder_step.state."
)

type frameFieldKind uint8

const (
	frameFieldState frameFieldKind = iota
	frameFieldParam
	frameFieldOwner
	frameFieldCallee
	frameFieldCalleeOwner
	frameFieldDomain
	frameFieldLocal
	frameFieldTemp
	frameFieldCleanup
	frameFieldScope
	frameFieldOut
)

// frameFieldInfo is one parsed frame field. Index is the zero-based group
// ordinal from the field name (p<i>, x<i>, ...); it is -1 for state and out.
type frameFieldInfo struct {
	name   string
	kind   frameFieldKind
	index  int
	typeID mir.TypeId
}

// frameInfo is one recognized @__alder_step.frame.<instance> declaration.
type frameInfo struct {
	typeID    mir.TypeId
	instance  string
	fields    []frameFieldInfo
	byName    map[string]int
	stateType mir.TypeId
	step      *frameStepInfo
	// callPoint[i] reports whether x<i>/y<i> exist.
	callPoint []bool
}

func (f *frameInfo) field(name string) (frameFieldInfo, bool) {
	if i, ok := f.byName[name]; ok {
		return f.fields[i], true
	}
	return frameFieldInfo{}, false
}

// frameStepInfo is one recognized @__alder_step.run.<instance> function.
type frameStepInfo struct {
	funcIndex  int
	fn         *mir.Function
	instance   string
	frame      *frameInfo
	stateType  mir.TypeId
	statusType mir.TypeId
	// frameParam and ownerParam are the ValueIds of the second and third
	// parameters. MIR construction puts function parameters first, so each
	// value equals its parameter ordinal.
	frameParam mir.ValueId
	ownerParam mir.ValueId
	variants   []mir.Variant
	variantIdx map[string]int
	// dispatch maps a state variant name to its case target.
	dispatch map[string]mir.BlockId
}

// frameInventory is the module-level step/frame declaration model. The zero
// status and nil maps mean the module declares no reserved step names.
type frameInventory struct {
	status    mir.TypeId
	hasStatus bool
	steps     []*frameStepInfo
	byFunc    map[int]*frameStepInfo
	frames    map[mir.TypeId]*frameInfo
	states    map[mir.TypeId]string
}

// frameOf reports whether t is exactly a recognized frame aggregate.
func (inv *frameInventory) frameOf(t mir.TypeId) (*frameInfo, bool) {
	if inv == nil || inv.frames == nil {
		return nil, false
	}
	f, ok := inv.frames[t]
	return f, ok
}

// isFrameView reports whether t is exactly safe_mut(frame) for a recognized
// frame type.
func (inv *frameInventory) isFrameView(m *mir.Module, t mir.TypeId) bool {
	if !m.ValidType(t) || m.Types[t].Kind != mir.TypeSafeMut {
		return false
	}
	_, ok := inv.frameOf(m.Types[t].Elem)
	return ok
}

// containsFrameType reports whether t names a recognized frame aggregate
// anywhere in its type tree, including behind safe_mut.
func (inv *frameInventory) containsFrameType(m *mir.Module, t mir.TypeId) bool {
	seen := make(map[mir.TypeId]bool)
	var walk func(mir.TypeId) bool
	walk = func(id mir.TypeId) bool {
		if !m.ValidType(id) || seen[id] {
			return false
		}
		seen[id] = true
		if _, ok := inv.frameOf(id); ok {
			return true
		}
		for _, child := range typeChildren(&m.Types[id]) {
			if walk(child) {
				return true
			}
		}
		return false
	}
	return walk(t)
}

// containsFrameValueType reports whether t contains a frame aggregate outside
// a safe_mut view: the frame record itself, or a value type that embeds one.
func (inv *frameInventory) containsFrameValueType(m *mir.Module, t mir.TypeId) bool {
	seen := make(map[mir.TypeId]bool)
	var walk func(mir.TypeId) bool
	walk = func(id mir.TypeId) bool {
		if !m.ValidType(id) || seen[id] {
			return false
		}
		seen[id] = true
		if _, ok := inv.frameOf(id); ok {
			return true
		}
		if m.Types[id].Kind == mir.TypeSafeMut || m.Types[id].Kind == mir.TypeSafeRef {
			return false
		}
		for _, child := range typeChildren(&m.Types[id]) {
			if walk(child) {
				return true
			}
		}
		return false
	}
	return walk(t)
}

// buildFrameInventory recognizes the reserved step declarations and validates
// their pinned shapes. Phase 2 owns the returned diagnostics; later phases run
// only after Phase 2 succeeds, so they may assume a well-formed inventory.
func buildFrameInventory(m *mir.Module) (*frameInventory, []Error) {
	inv := &frameInventory{
		byFunc: make(map[int]*frameStepInfo),
		frames: make(map[mir.TypeId]*frameInfo),
		states: make(map[mir.TypeId]string),
	}
	var errs []Error
	// Classify reserved type declarations and reject names outside the three
	// pinned families.
	for i := range m.Types {
		t := &m.Types[i]
		if !strings.HasPrefix(t.Name, frameReservedPrefix) {
			continue
		}
		switch {
		case t.Name == frameStatusName:
			if t.Kind != mir.TypeEnum {
				errs = append(errs, Error{Loc: typeLoc(m, mir.TypeId(i)), Msg: "reserved status declaration must be an enum"})
				continue
			}
			inv.status = mir.TypeId(i)
			inv.hasStatus = true
		case strings.HasPrefix(t.Name, frameTypePrefix):
			if t.Kind != mir.TypeAggregate {
				errs = append(errs, Error{Loc: typeLoc(m, mir.TypeId(i)), Msg: "reserved frame declaration must be an aggregate type"})
				continue
			}
			info := &frameInfo{
				typeID:   mir.TypeId(i),
				instance: strings.TrimPrefix(t.Name, frameTypePrefix),
				byName:   make(map[string]int),
			}
			if info.instance == "" {
				errs = append(errs, Error{Loc: typeLoc(m, mir.TypeId(i)), Msg: "frame type name has no instance suffix"})
				continue
			}
			inv.frames[mir.TypeId(i)] = info
		case strings.HasPrefix(t.Name, frameStatePrefix):
			instance := strings.TrimPrefix(t.Name, frameStatePrefix)
			if t.Kind != mir.TypeEnum {
				errs = append(errs, Error{Loc: typeLoc(m, mir.TypeId(i)), Msg: "reserved state declaration must be an enum"})
				continue
			}
			if instance == "" {
				errs = append(errs, Error{Loc: typeLoc(m, mir.TypeId(i)), Msg: "state enum name has no instance suffix"})
				continue
			}
			inv.states[mir.TypeId(i)] = instance
		default:
			errs = append(errs, Error{Loc: typeLoc(m, mir.TypeId(i)), Msg: "reserved __alder_step. name is not a status, frame, or state declaration"})
		}
	}
	// Reject reserved names on non-type declarations: the prefix is
	// compiler-owned and only the pinned forms are legal.
	for i := range m.Constants {
		if strings.HasPrefix(m.Constants[i].Name, frameReservedPrefix) {
			errs = append(errs, Error{Loc: "const @" + m.Constants[i].Name, Msg: "reserved __alder_step. name is not a pinned step declaration"})
		}
	}
	for i := range m.Imports {
		if strings.HasPrefix(m.Imports[i].Name, frameReservedPrefix) {
			errs = append(errs, Error{Loc: "import @" + m.Imports[i].Name, Msg: "reserved __alder_step. name is not a pinned step declaration"})
		}
	}
	for bi := range m.Bindings {
		if strings.HasPrefix(m.Bindings[bi].Name, frameReservedPrefix) {
			errs = append(errs, Error{Loc: "binding @" + m.Bindings[bi].Name, Msg: "reserved __alder_step. name is not a pinned step declaration"})
		}
		for fi := range m.Bindings[bi].Funcs {
			if strings.HasPrefix(m.Bindings[bi].Funcs[fi].Name, frameReservedPrefix) {
				errs = append(errs, Error{Loc: "binding @" + m.Bindings[bi].Name + " function @" + m.Bindings[bi].Funcs[fi].Name, Msg: "reserved __alder_step. name is not a pinned step declaration"})
			}
		}
	}
	// Validate frame field order and kinds in declaration order.
	for i := range m.Types {
		info, ok := inv.frames[mir.TypeId(i)]
		if !ok {
			continue
		}
		fields, fieldErrs := parseFrameFields(m, inv, info)
		info.fields = fields
		info.byName = make(map[string]int, len(fields))
		for i, field := range fields {
			info.byName[field.name] = i
			if field.kind == frameFieldState {
				info.stateType = field.typeID
			}
			if field.kind == frameFieldCallee {
				for len(info.callPoint) <= field.index {
					info.callPoint = append(info.callPoint, false)
				}
				info.callPoint[field.index] = true
			}
		}
		errs = append(errs, fieldErrs...)
		if _, ok := inv.states[info.stateType]; !ok {
			errs = append(errs, Error{Loc: typeLoc(m, info.typeID), Msg: "frame state field must be a reserved state enum"})
		}
	}
	// Recognize step functions by the reserved run name and validate the
	// pinned three-parameter signature.
	for i := range m.Functions {
		f := m.Functions[i]
		if f == nil || !strings.HasPrefix(f.Name, frameReservedPrefix) {
			continue
		}
		if !strings.HasPrefix(f.Name, frameRunPrefix) {
			errs = append(errs, Error{Loc: locFunc(f), Msg: "reserved __alder_step. name is not a pinned step declaration"})
			continue
		}
		instance := strings.TrimPrefix(f.Name, frameRunPrefix)
		if instance == "" {
			errs = append(errs, Error{Loc: locFunc(f), Msg: "step function name has no instance suffix"})
			continue
		}
		step := &frameStepInfo{
			funcIndex:  i,
			fn:         f,
			instance:   instance,
			variantIdx: make(map[string]int),
			dispatch:   make(map[string]mir.BlockId),
		}
		if reason := frameStepSignatureError(m, inv, step); reason != "" {
			errs = append(errs, Error{Loc: locFunc(f), Msg: reason})
			continue
		}
		inv.steps = append(inv.steps, step)
		inv.byFunc[i] = step
		step.frame.step = step
	}
	// A frame type must belong to exactly one step function, and a step's
	// frame instance must match its own name.
	for i := range m.Types {
		info, ok := inv.frames[mir.TypeId(i)]
		if !ok {
			continue
		}
		owners := 0
		for _, step := range inv.steps {
			if step.frame == info {
				owners++
			}
		}
		if owners != 1 {
			errs = append(errs, Error{Loc: typeLoc(m, info.typeID), Msg: "frame type must be the frame of exactly one step function"})
		}
	}
	// Every state enum must be the state of exactly one frame, named by the
	// same instance.
	for i := range m.Types {
		id := mir.TypeId(i)
		instance, ok := inv.states[id]
		if !ok {
			continue
		}
		var owner *frameInfo
		for j := range m.Types {
			info, ok := inv.frames[mir.TypeId(j)]
			if !ok || info.stateType != id {
				continue
			}
			if owner != nil {
				errs = append(errs, Error{Loc: typeLoc(m, id), Msg: "state enum must belong to exactly one step frame"})
				owner = nil
				break
			}
			owner = info
			if info.instance != instance {
				errs = append(errs, Error{Loc: typeLoc(m, id), Msg: "state enum instance does not match its frame type"})
			}
		}
		if owner == nil {
			errs = append(errs, Error{Loc: typeLoc(m, id), Msg: "state enum must belong to exactly one step frame"})
		}
	}
	// The status enum exists exactly when the module has step functions.
	if len(inv.steps) > 0 && !inv.hasStatus {
		errs = append(errs, Error{Msg: "step functions require the module-level @__alder_step.status enum"})
	}
	if inv.hasStatus && len(inv.steps) == 0 {
		errs = append(errs, Error{Loc: typeLoc(m, inv.status), Msg: "reserved status enum requires at least one step function"})
	}
	if inv.hasStatus {
		errs = append(errs, checkStatusShape(m, inv.status)...)
	}
	// State enum numbering is part of the recognition shape, in declaration
	// order.
	for i := range m.Types {
		if _, ok := inv.states[mir.TypeId(i)]; ok {
			errs = append(errs, checkStateShape(m, mir.TypeId(i))...)
		}
	}
	// Fill each step's state variant table and dispatch case targets after the
	// declaration checks so malformed modules stop at Phase 2.
	for _, step := range inv.steps {
		step.variants, _ = m.VariantsOf(step.stateType)
		step.variantIdx = make(map[string]int, len(step.variants))
		for i, v := range step.variants {
			step.variantIdx[v.Name] = i
		}
		collectFrameDispatch(step)
	}
	return inv, errs
}

func checkStatusShape(m *mir.Module, id mir.TypeId) []Error {
	variants, ok := m.VariantsOf(id)
	if !ok {
		return []Error{{Loc: typeLoc(m, id), Msg: "reserved status declaration must be an enum"}}
	}
	want := []string{"done", "call", "park", "cancelled"}
	if len(variants) != len(want) {
		return []Error{{Loc: typeLoc(m, id), Msg: "status enum must contain exactly done, call, park, and cancelled in that order"}}
	}
	for i, name := range want {
		if variants[i].Name != name || variants[i].Payload != mir.TypeUnit {
			return []Error{{Loc: typeLoc(m, id), Msg: "status enum must contain exactly done, call, park, and cancelled in that order"}}
		}
	}
	return nil
}

func checkStateShape(m *mir.Module, id mir.TypeId) []Error {
	variants, ok := m.VariantsOf(id)
	if !ok || len(variants) == 0 || variants[0].Name != "entry" || variants[0].Payload != mir.TypeUnit {
		return []Error{{Loc: typeLoc(m, id), Msg: "state enum must start with the entry variant"}}
	}
	nextResume := 0
	nextCleanup := 0
	cleanupSeen := false
	for _, v := range variants[1:] {
		if v.Payload != mir.TypeUnit {
			return []Error{{Loc: typeLoc(m, id), Msg: "state variants carry no payload"}}
		}
		if strings.HasPrefix(v.Name, "resume") && !cleanupSeen {
			want := "resume" + strconv.Itoa(nextResume)
			if v.Name != want {
				return []Error{{Loc: typeLoc(m, id), Msg: "state enum must number resume variants contiguously from resume0"}}
			}
			nextResume++
			continue
		}
		if strings.HasPrefix(v.Name, "cleanup") {
			if !cleanupSeen {
				cleanupSeen = true
			}
			want := "cleanup" + strconv.Itoa(nextCleanup)
			if v.Name != want {
				return []Error{{Loc: typeLoc(m, id), Msg: "state enum must number cleanup variants contiguously from cleanup0 after its resume variants"}}
			}
			nextCleanup++
			continue
		}
		return []Error{{Loc: typeLoc(m, id), Msg: "state variants must be entry, resume<i>, or cleanup<i>"}}
	}
	return nil
}

// parseFrameFields validates the pinned frame field order and returns the
// parsed field list. Field-name numbering is zero-based and contiguous within
// each group.
func parseFrameFields(m *mir.Module, inv *frameInventory, info *frameInfo) ([]frameFieldInfo, []Error) {
	loc := typeLoc(m, info.typeID)
	t := &m.Types[info.typeID]
	if len(t.Fields) < 2 {
		return nil, []Error{{Loc: loc, Msg: "frame record requires a state field first and an out field last"}}
	}
	var fields []frameFieldInfo
	add := func(field frameFieldInfo) {
		fields = append(fields, field)
	}
	if t.Fields[0].Name != "state" {
		return nil, []Error{{Loc: loc, Msg: "frame record requires a state field first and an out field last"}}
	}
	add(frameFieldInfo{name: "state", kind: frameFieldState, index: -1, typeID: t.Fields[0].Type})
	i := 1
	errs := []Error{}
	fieldTypeErr := func(name string, ty mir.TypeId) {
		if containsKind(m, ty, mir.TypeTableView) || containsKind(m, ty, mir.TypeTableMutView) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame field %q may not contain a table view", name)})
		}

	}
	// p<i> followed by o<i> when the parameter is a borrowed safe_mut.
	for i < len(t.Fields) {
		fld := t.Fields[i]
		idx, ok := frameIndexed(fld.Name, "p")
		if !ok || idx != countFrameKind(fields, frameFieldParam) {
			break
		}
		fieldTypeErr(fld.Name, fld.Type)
		add(frameFieldInfo{name: fld.Name, kind: frameFieldParam, index: idx, typeID: fld.Type})
		i++
		if i < len(t.Fields) {
			if oidx, ok := frameIndexed(t.Fields[i].Name, "o"); ok {
				if oidx != idx {
					errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame owner field %q must follow parameter %q", t.Fields[i].Name, fld.Name)})
					return fields, errs
				}
				if !m.ValidType(t.Fields[i].Type) || m.Types[t.Fields[i].Type].Kind != mir.TypeDomainHandle {
					errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame owner field %q must be domain_handle", t.Fields[i].Name)})
				}
				add(frameFieldInfo{name: t.Fields[i].Name, kind: frameFieldOwner, index: idx, typeID: t.Fields[i].Type})
				i++
			} else if m.ValidType(fld.Type) && m.Types[fld.Type].Kind == mir.TypeSafeMut {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("borrowed frame parameter %q requires the owner field o%d", fld.Name, idx)})
			}
		} else if m.ValidType(fld.Type) && m.Types[fld.Type].Kind == mir.TypeSafeMut {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("borrowed frame parameter %q requires the owner field o%d", fld.Name, idx)})
		}
	}
	// x<i>/y<i> pairs in suspension-point order.
	for i < len(t.Fields) {
		fld := t.Fields[i]
		idx, ok := frameIndexed(fld.Name, "x")
		if !ok || idx != countFrameKind(fields, frameFieldCallee) {
			break
		}
		if !m.ValidType(fld.Type) || m.Types[fld.Type].Kind != mir.TypeSafeMut {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame callee field %q must be safe_mut(frame)", fld.Name)})
		} else if _, ok := inv.frameOf(m.Types[fld.Type].Elem); !ok {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame callee field %q must view a frame type", fld.Name)})
		}
		fieldTypeErr(fld.Name, fld.Type)
		add(frameFieldInfo{name: fld.Name, kind: frameFieldCallee, index: idx, typeID: fld.Type})
		i++
		if i >= len(t.Fields) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame callee field %q requires the adjacent owner field y%d", fld.Name, idx)})
			break
		}
		yf := t.Fields[i]
		yidx, ok := frameIndexed(yf.Name, "y")
		if !ok || yidx != idx {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame callee field %q requires the adjacent owner field y%d", fld.Name, idx)})
			break
		}
		if !m.ValidType(yf.Type) || m.Types[yf.Type].Kind != mir.TypeDomainHandle {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame callee owner field %q must be domain_handle", yf.Name)})
		}
		add(frameFieldInfo{name: yf.Name, kind: frameFieldCalleeOwner, index: idx, typeID: yf.Type})
		i++
	}
	// d<i>, l<i>, v<i>, c<i> in that group order.
	for _, group := range []struct {
		prefix string
		kind   frameFieldKind
		check  func(string, mir.TypeId)
	}{
		{"d", frameFieldDomain, func(name string, ty mir.TypeId) {
			if !m.ValidType(ty) || m.Types[ty].Kind != mir.TypeDomainHandle {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame domain field %q must be domain_handle", name)})
			}
		}},
		{"l", frameFieldLocal, nil},
		{"v", frameFieldTemp, nil},
		{"c", frameFieldCleanup, func(name string, ty mir.TypeId) {
			if !m.ValidType(ty) || m.Types[ty].Kind != mir.TypeCleanupID {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame cleanup field %q must be cleanup_id", name)})
			}
		}},
		{"s", frameFieldScope, func(name string, ty mir.TypeId) {
			if !m.ValidType(ty) || m.Types[ty].Kind != mir.TypeCleanupScope {
				errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame scope field %q must be cleanup_scope", name)})
			}
		}},
	} {
		for i < len(t.Fields) {
			fld := t.Fields[i]
			idx, ok := frameIndexed(fld.Name, group.prefix)
			if !ok || idx != countFrameKind(fields, group.kind) {
				break
			}
			fieldTypeErr(fld.Name, fld.Type)
			if group.check != nil {
				group.check(fld.Name, fld.Type)
			}
			add(frameFieldInfo{name: fld.Name, kind: group.kind, index: idx, typeID: fld.Type})
			i++
		}
	}
	// Only x<i> may name another frame type. A frame record is never
	// embedded by value in a frame field.
	for _, field := range fields {
		if field.kind == frameFieldState || field.kind == frameFieldCallee {
			continue
		}
		if inv.containsFrameType(m, field.typeID) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame field %q may not name a frame type", field.name)})
		}
		if field.kind != frameFieldScope && containsKind(m, field.typeID, mir.TypeCleanupScope) {
			errs = append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame field %q may not contain a cleanup scope", field.name)})
		}
	}
	if i != len(t.Fields)-1 || t.Fields[i].Name != "out" {
		name := ""
		if i < len(t.Fields) {
			name = t.Fields[i].Name
		}
		return fields, append(errs, Error{Loc: loc, Msg: fmt.Sprintf("frame field %q is out of order; expected the final out field", name)})
	}
	fieldTypeErr("out", t.Fields[i].Type)
	add(frameFieldInfo{name: "out", kind: frameFieldOut, index: -1, typeID: t.Fields[i].Type})
	return fields, errs
}

func frameIndexed(name, prefix string) (int, bool) {
	if !strings.HasPrefix(name, prefix) || len(name) == len(prefix) {
		return 0, false
	}
	digits := name[len(prefix):]
	for i := 0; i < len(digits); i++ {
		if digits[i] < '0' || digits[i] > '9' {
			return 0, false
		}
	}
	index, err := strconv.Atoi(digits)
	if err != nil || index < 0 {
		return 0, false
	}
	return index, true
}

func countFrameKind(fields []frameFieldInfo, kind frameFieldKind) int {
	n := 0
	for _, field := range fields {
		if field.kind == kind {
			n++
		}
	}
	return n
}

func frameStepSignatureError(m *mir.Module, inv *frameInventory, step *frameStepInfo) string {
	f := step.fn
	if len(f.Params) != 3 {
		return "step function must have the pinned three-parameter signature"
	}
	if !m.ValidType(f.Params[0].Type) || m.Types[f.Params[0].Type].Kind != mir.TypeDomainHandle {
		return "step function must have the pinned three-parameter signature"
	}
	frameView := f.Params[1].Type
	if !m.ValidType(frameView) || m.Types[frameView].Kind != mir.TypeSafeMut {
		return "step function must have the pinned three-parameter signature"
	}
	frameType := m.Types[frameView].Elem
	info, ok := inv.frameOf(frameType)
	if !ok {
		return "step function's second parameter must view a reserved frame type"
	}
	if info.instance != step.instance {
		return "step function instance does not match its frame type name"
	}
	if !m.ValidType(f.Params[2].Type) || m.Types[f.Params[2].Type].Kind != mir.TypeDomainHandle {
		return "step function must have the pinned three-parameter signature"
	}
	if !inv.hasStatus || f.Result != inv.status {
		return "step function must return the status enum"
	}
	step.frame = info
	step.stateType = info.stateType
	step.statusType = inv.status
	step.frameParam = mir.ValueId(1)
	step.ownerParam = mir.ValueId(2)
	return ""
}

// collectFrameDispatch records the state variant each dispatch case targets.
// The shape itself is checked in Phase 6 so the reserved declaration pass stays
// limited to declarations.
func collectFrameDispatch(step *frameStepInfo) {
	if len(step.fn.Blocks) == 0 || step.fn.Blocks[0] == nil {
		return
	}
	term := &step.fn.Blocks[0].Term
	if term.Kind != mir.TermSwitch {
		return
	}
	for _, c := range term.Cases {
		if c.Variant != "" {
			if _, seen := step.dispatch[c.Variant]; !seen {
				step.dispatch[c.Variant] = c.Target
			}
		}
	}
}

// frameStepOf returns the step info for f, or nil. It is a linear lookup so
// the inventory needs no function pointer key.
func (inv *frameInventory) frameStepOf(f *mir.Function) *frameStepInfo {
	if inv == nil {
		return nil
	}
	for _, step := range inv.steps {
		if step.fn == f {
			return step
		}
	}
	return nil
}

// frameTypingErrors applies the frame access rules that need only operand and
// place shape: the borrowed step frame is a deref base only, a frame field
// place is never aliased out, a frame view never escapes its activation, and a
// frame record is never a value. State save/restore rules live in Phase 6.
func frameTypingErrors(m *mir.Module, inv *frameInventory) []Error {
	var errs []Error
	if inv == nil || len(inv.steps) == 0 {
		return nil
	}
	stepOf := inv.frameStepOf
	for _, f := range m.Functions {
		if f == nil || len(f.Blocks) == 0 {
			continue
		}
		step := stepOf(f)
		views := make(map[mir.ValueId]bool)
		for vi, v := range f.Values {
			if inv.isFrameView(m, v.Type) {
				views[mir.ValueId(vi)] = true
			}
		}
		var frameParam mir.ValueId = mir.NoValue
		if step != nil {
			frameParam = step.frameParam
		}
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				loc := locInstr(f, b, ii, in)
				if in.Op == mir.OpCall {
					if _, isStep := inv.byFunc[int(in.Callee)]; isStep {
						errs = append(errs, Error{Loc: loc, Msg: "a step function is entered only through the executor trampoline"})
					}
				}
				if in.Op == mir.OpFnValue {
					if _, isStep := inv.byFunc[int(in.Callee)]; isStep {
						errs = append(errs, Error{Loc: loc, Msg: "a step function has no callable function value"})
					}
				}
				// A frame value is a storage record, never an ordinary SSA
				// value. The borrowed frame view is handled separately.
				if in.Result != mir.NoValue {
					if t, ok := f.ValueType(in.Result); ok && inv.containsFrameValueType(m, t) {
						errs = append(errs, Error{Loc: loc, Msg: "a frame record may not be used as a value"})
					}
				}
				if in.Op == mir.OpAggregateConstruct && in.AggType != mir.NoType {
					if _, ok := inv.frameOf(in.AggType); ok {
						errs = append(errs, Error{Loc: loc, Msg: "a frame record may not be constructed as a value"})
					}
				}
				placeOpc := in.Op == mir.OpLoad || in.Op == mir.OpStore || in.Op == mir.OpBorrow ||
					in.Op == mir.OpBorrowMut || in.Op == mir.OpCFieldSet || in.Op == mir.OpCAddr ||
					(in.Op == mir.OpCleanupPush && in.HasPlace)
				if placeOpc {
					// The borrowed step frame is only the base of a deref
					// field place.
					frameParamBad := false
					walkFramePlace(&in.Place, false, func(deref mir.ValueId, directField bool) {
						if deref == frameParam && !directField {
							frameParamBad = true
						}
					})
					if frameParamBad {
						errs = append(errs, Error{Loc: loc, Msg: "%frame may only be the base of a deref field place"})
					}
					// Borrowing a frame field place aliases the activation's
					// stable storage out into ordinary SSA.
					if in.Op == mir.OpBorrow || in.Op == mir.OpBorrowMut || in.Op == mir.OpCAddr {
						if _, deref, ok := frameFieldPlace(&in.Place); ok && views[deref] {
							errs = append(errs, Error{Loc: loc, Msg: "a frame field place may not be aliased out of its activation"})
						}
					}
					// A frame view may only be a deref base or the fresh
					// allocation stored into the allocating step's x<i>.
					if in.Op == mir.OpStore && views[in.StoreVal] && in.StoreVal != frameParam {
						field, deref, ok := frameFieldPlace(&in.Place)
						if !ok || step == nil || deref != frameParam || !strings.HasPrefix(field, "x") || !frameAllocResult(f, in.StoreVal) {
							errs = append(errs, Error{Loc: loc, Msg: "a frame view may not escape its activation"})
						}
					}
				}
				// Every value operand use of the borrowed step frame and of a
				// frame view is an escape. Place derefs are not value
				// operands, so the canonical accesses never appear here.
				operands := instrValueOperands(in)
				if in.Op == mir.OpCBindingCall {
					operands = append(operands, in.Args...)
				}
				for _, v := range operands {
					if v == frameParam {
						errs = append(errs, Error{Loc: loc, Msg: "%frame may only be the base of a deref field place"})
						continue
					}
					// task.spawn hands one fresh child frame view to the task
					// runtime; the borrow contract lives in the lowering, so
					// the view escape rule must not reject the spawn site.
					if views[v] && in.Op != mir.OpStore && !(in.Op == mir.OpTaskSpawn && v == in.B) {
						errs = append(errs, Error{Loc: loc, Msg: "a frame view may not escape its activation"})
					}
				}
				for _, v := range in.FailArgs {
					if v == frameParam || views[v] {
						errs = append(errs, Error{Loc: loc, Msg: "a frame view may not escape its activation"})
						break
					}
				}
			}
			// Terminators carry ordinary values only.
			term, tloc := &b.Term, locTerm(f, b)
			check := func(v mir.ValueId) bool { return (step != nil && v == frameParam) || views[v] }
			bad := check(term.Cond) || check(term.Result)
			for _, v := range term.Args {
				bad = bad || check(v)
			}
			for _, v := range term.ThenArgs {
				bad = bad || check(v)
			}
			for _, v := range term.ElseArgs {
				bad = bad || check(v)
			}
			for _, c := range term.Cases {
				for _, v := range c.Args {
					bad = bad || check(v)
				}
			}
			if term.Kind == mir.TermSwitch && check(term.Value) {
				bad = true
			}
			if bad {
				errs = append(errs, Error{Loc: tloc, Msg: "a frame view may not escape its activation"})
			}
		}
	}
	return errs
}

// walkFramePlace reports every deref base in a place and whether the deref is
// the base of a field place.
func walkFramePlace(p *mir.Place, directField bool, visit func(deref mir.ValueId, directField bool)) {
	seen := make(map[*mir.Place]bool)
	for p != nil && !seen[p] {
		seen[p] = true
		switch p.Kind {
		case mir.PlaceField:
			p = p.Base
			directField = true
		case mir.PlaceDeref:
			visit(p.Deref, directField)
			return
		default:
			return
		}
	}
}

// frameFieldPlace returns the direct field name and deref base of
// field(deref %v, name).
func frameFieldPlace(p *mir.Place) (string, mir.ValueId, bool) {
	if p == nil || p.Kind != mir.PlaceField || p.Base == nil || p.Base.Kind != mir.PlaceDeref {
		return "", mir.NoValue, false
	}
	return p.Field, p.Base.Deref, true
}

// frameAllocResult reports whether v is the result of a frame allocation.
func frameAllocResult(f *mir.Function, v mir.ValueId) bool {
	if int(v) >= len(f.Values) {
		return false
	}
	def := f.Values[v].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return false
	}
	in := &f.Blocks[def.Block].Instrs[def.Instr]
	return in.Op == mir.OpAlloc || in.Op == mir.OpAllocChecked
}

// frameFieldStore reports whether p is a direct field of a frame view, the one
// dereference-store position the frame rules exempt from the ordinary
// lifetime-bearing store restriction.
func frameFieldStore(m *mir.Module, inv *frameInventory, f *mir.Function, p *mir.Place) bool {
	_, deref, ok := frameFieldPlace(p)
	if !ok || inv == nil {
		return false
	}
	t, ok := f.ValueType(deref)
	return ok && inv.isFrameView(m, t)
}

// frameConstantOne reports whether v is a const.get of the u64 constant 1.
func frameConstantOne(m *mir.Module, f *mir.Function, v mir.ValueId) bool {
	if int(v) >= len(f.Values) {
		return false
	}
	def := f.Values[v].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return false
	}
	in := &f.Blocks[def.Block].Instrs[def.Instr]
	if in.Op != mir.OpConstGet {
		return false
	}
	for _, c := range m.Constants {
		if c.Name == in.Const {
			return c.Type == mir.TypeU64 && c.Value.Kind == mir.ConstInt && c.Value.Int == 1
		}
	}
	return false
}

// frameCleanupPlace recognizes a cleanup.push owner place that names a frame
// field. Phase 1 uses naming only because the frame inventory is validated by
// Phase 2.
func frameCleanupPlace(m *mir.Module, f *mir.Function, p *mir.Place) bool {
	_, deref, ok := frameFieldPlace(p)
	if !ok {
		return false
	}
	t, ok := f.ValueType(deref)
	if !ok || !m.ValidType(t) || m.Types[t].Kind != mir.TypeSafeMut {
		return false
	}
	elem := m.Types[t].Elem
	return m.ValidType(elem) && m.Types[elem].Kind == mir.TypeAggregate && strings.HasPrefix(m.Types[elem].Name, frameTypePrefix)
}

// frameFieldStores returns the values stored through the exact frame field
// place field(deref %deref, field), in instruction order.
func frameFieldStores(f *mir.Function, deref mir.ValueId, field string) []mir.ValueId {
	var stores []mir.ValueId
	for _, b := range f.Blocks {
		if b == nil {
			continue
		}
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpStore {
				continue
			}
			name, base, ok := frameFieldPlace(&in.Place)
			if ok && name == field && base == deref {
				stores = append(stores, in.StoreVal)
			}
		}
	}
	return stores
}

// frameComputedSaveLists derives the ordered save list of every non-entry
// state without phase-6 diagnostics; phase-7 anchor checks consume it.
func frameComputedSaveLists(m *mir.Module, inv *frameInventory, step *frameStepInfo) map[string][]string {
	result := make(map[string][]string)
	f := step.fn
	for _, b := range f.Blocks {
		if b == nil {
			continue
		}
		stateStore := -1
		variant := ""
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpStore {
				continue
			}
			field, deref, ok := frameFieldPlace(&in.Place)
			if ok && deref == step.frameParam && field == "state" {
				if v, ok := frameEnumVariant(f, in.StoreVal, step.stateType); ok {
					variant = v
					stateStore = ii
				}
			}
		}
		if stateStore < 0 || variant == "" || variant == "entry" {
			continue
		}
		var fields []string
		for ii := stateStore + 1; ii < len(b.Instrs); ii++ {
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
			switch step.frame.fields[fi].kind {
			case frameFieldCallee, frameFieldCalleeOwner, frameFieldDomain, frameFieldLocal, frameFieldTemp, frameFieldCleanup, frameFieldScope:
				fields = append(fields, field)
			}
		}
		result[variant] = fields
	}
	return result
}

// frameResidentScopes marks adopting begins anchored to a frame s<i> field.
// Those scopes span states, so a suspension return is not a scope exit.
func frameResidentScopes(m *mir.Module, inv *frameInventory, f *mir.Function, step *frameStepInfo) map[mir.ValueId]bool {
	resident := make(map[mir.ValueId]bool)
	if step == nil {
		return resident
	}
	anchors, _ := frameScopeAnchors(m, inv, step)
	for begin := range anchors {
		resident[begin] = true
	}
	return resident
}

// frameSuspensionReturn reports whether a block returns a call or park status.
func frameSuspensionReturn(m *mir.Module, step *frameStepInfo, b *mir.Block) bool {
	if step == nil || b == nil || b.Term.Kind != mir.TermReturn || b.Term.Result == mir.NoValue {
		return false
	}
	status, ok := frameEnumVariant(step.fn, b.Term.Result, step.statusType)
	if !ok {
		return false
	}
	return status == "call" || status == "park"
}

// frameCleanupErrors checks the frame-specific registration rules: a
// registration saved across a state names a frame field as its owner place,
// and a saved registration id is disarmed at most once on any path.
func frameCleanupErrors(m *mir.Module, inv *frameInventory) []Error {
	var errs []Error
	for _, step := range inv.steps {
		f := step.fn
		errs = append(errs, frameScopeAnchorErrors(m, inv, step, frameComputedSaveLists(m, inv, step))...)
		// A push result stored into c<i> spans a state.
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				if in.Op != mir.OpStore {
					continue
				}
				field, _, ok := frameFieldPlace(&in.Place)
				if !ok || !strings.HasPrefix(field, "c") {
					continue
				}
				fi, ok := step.frame.byName[field]
				if !ok || step.frame.fields[fi].kind != frameFieldCleanup {
					continue
				}
				push := frameDefiningInstr(f, in.StoreVal)
				if push == nil || push.Op != mir.OpCleanupPush {
					errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a saved frame cleanup id must come from cleanup.push"})
					continue
				}
				if _, _, ok := frameFieldPlace(&push.Place); !ok || !push.HasPlace {
					errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a cleanup registration spanning a state must name a frame field as its place"})
				}
			}
		}
		// A cleanup id loaded from a frame field may be disarmed at most once
		// on any path.
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				if in.Op != mir.OpLoad {
					continue
				}
				field, _, ok := frameFieldPlace(&in.Place)
				if !ok || !strings.HasPrefix(field, "c") {
					continue
				}
				sites := frameDisarmSites(f, in.Result)
				if len(sites) < 2 {
					continue
				}
				for i := 0; i < len(sites); i++ {
					for j := i + 1; j < len(sites); j++ {
						if frameReaches(f, sites[i], sites[j]) || frameReaches(f, sites[j], sites[i]) {
							errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a frame cleanup registration may be disarmed at most once on one path"})
							i = len(sites)
							break
						}
					}
				}
			}
		}
	}
	return errs
}

func frameDefiningInstr(f *mir.Function, v mir.ValueId) *mir.Instr {
	if int(v) >= len(f.Values) {
		return nil
	}
	def := f.Values[v].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return nil
	}
	return &f.Blocks[def.Block].Instrs[def.Instr]
}

// frameDisarmSites returns the block of every cleanup.disarm that uses v.
func frameDisarmSites(f *mir.Function, v mir.ValueId) []mir.BlockId {
	var sites []mir.BlockId
	for bi, b := range f.Blocks {
		if b == nil {
			continue
		}
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op == mir.OpCleanupDisarm && in.CleanupID == v {
				sites = append(sites, mir.BlockId(bi))
			}
		}
	}
	return sites
}

// frameReaches reports whether from can reach to in the CFG.
func frameReaches(f *mir.Function, from, to mir.BlockId) bool {
	if from == to {
		return true
	}
	seen := make([]bool, len(f.Blocks))
	seen[from] = true
	queue := []mir.BlockId{from}
	for len(queue) > 0 {
		b := queue[0]
		queue = queue[1:]
		for _, s := range successors(f, f.Blocks[b]) {
			if int(s) >= len(seen) || seen[s] {
				continue
			}
			if s == to {
				return true
			}
			seen[s] = true
			queue = append(queue, s)
		}
	}
	return false
}

// frameAllocationErrors checks the pinned frame allocation site: inside a
// step, in a child domain of the activation domain, and stored exactly once
// into the allocating step's own x<i> field.
func frameAllocationErrors(m *mir.Module, inv *frameInventory) []Error {
	if inv == nil {
		return nil
	}
	var errs []Error
	for _, step := range inv.steps {
		f := step.fn
		for _, b := range f.Blocks {
			if b == nil {
				continue
			}
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				if in.Op != mir.OpAlloc && in.Op != mir.OpAllocChecked {
					continue
				}
				if _, ok := inv.frameOf(in.TypeOp); !ok {
					continue
				}
				loc := locInstr(f, b, ii, in)
				child := frameDefiningInstr(f, in.Domain)
				if child == nil || child.Op != mir.OpDomainCreate || child.Domain != step.ownerParam {
					errs = append(errs, Error{Loc: loc, Msg: "a callee activation domain must be created from %frame_owner"})
				}
				stores := 0
				validTarget := false
				spawned := false
				for _, other := range f.Blocks {
					if other == nil {
						continue
					}
					for oi := range other.Instrs {
						x := &other.Instrs[oi]
						if x.Op == mir.OpTaskSpawn && x.B == in.Result {
							spawned = true
							continue
						}
						if x.Op != mir.OpStore || x.StoreVal != in.Result {
							continue
						}
						stores++
						field, deref, ok := frameFieldPlace(&x.Place)
						if ok && deref == step.frameParam && strings.HasPrefix(field, "x") {
							validTarget = true
						}
					}
				}
				if !spawned && (stores != 1 || !validTarget) {
					errs = append(errs, Error{Loc: loc, Msg: "a frame allocation must be stored exactly once into the allocating step's x<i> field"})
				}
			}
		}
	}
	return errs
}

// frameScopeAnchor is the frame slot a frame-resident adopting begin stores
// its handle into. All emissions storing the same s<i> are one dynamic scope.
type frameScopeAnchor struct {
	field string
	pos   int
	blk   mir.BlockId
	in    int
}

// frameScopeAnchors maps each adopting begin result to its anchoring s<i>
// store. All emissions storing the same s<i> are one dynamic scope.
func frameScopeAnchors(m *mir.Module, inv *frameInventory, step *frameStepInfo) (map[mir.ValueId]frameScopeAnchor, []Error) {
	anchors := make(map[mir.ValueId]frameScopeAnchor)
	var errs []Error
	f := step.fn
	for _, b := range f.Blocks {
		if b == nil {
			continue
		}
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpCleanupScopeBegin || in.Result == mir.NoValue {
				continue
			}
			def := f.Values[in.Result].Def
			var found []frameScopeAnchor
			for sbi, sb := range f.Blocks {
				if sb == nil || mir.BlockId(sbi) != def.Block {
					continue
				}
				for sii := range sb.Instrs {
					if sii <= ii {
						continue
					}
					st := &sb.Instrs[sii]
					if st.Op != mir.OpStore || st.StoreVal != in.Result {
						continue
					}
					field, deref, ok := frameFieldPlace(&st.Place)
					if !ok || deref != step.frameParam {
						continue
					}
					fi, ok := step.frame.byName[field]
					if !ok || step.frame.fields[fi].kind != frameFieldScope {
						continue
					}
					found = append(found, frameScopeAnchor{field: field, pos: fi, blk: mir.BlockId(sbi), in: sii})
					break
				}
				if len(found) != 0 {
					break
				}
			}
			if len(found) == 0 {
				// A scope that never stores into s<i> stays an ordinary
				// local scope; phase 7 rejects it if it spans a suspension.
				continue
			}
			anchor := found[0]
			anchors[in.Result] = anchor
			// The anchoring store must precede every direct use.
			dom := dominators(f)
			for _, use := range collectUses(f) {
				if use.value != in.Result || use.instr < 0 {
					continue
				}
				ui := &f.Blocks[use.block].Instrs[use.instr]
				if ui.Op != mir.OpCleanupPush && ui.Op != mir.OpCleanupScopeRun && ui.Op != mir.OpCleanupScopeEnd {
					continue
				}
				if ui.Scope != in.Result {
					continue
				}
				if !dominatesWithEdges(f, dom, anchor.blk, anchor.in, use.block, use.instr) {
					errs = append(errs, Error{Loc: useSiteLoc(f, use), Msg: fmt.Sprintf("scope %s is used before its s<i> anchor store", valueName(f, in.Result))})
				}
			}
		}
	}
	return anchors, errs
}

// frameScopeOperandField resolves a cleanup scope operand to the frame s<i>
// field that anchors it, either directly through its begin or through a load
// from the saved scope field.
func frameScopeOperandField(f *mir.Function, anchors map[mir.ValueId]frameScopeAnchor, v mir.ValueId) (string, bool) {
	if a, ok := anchors[v]; ok {
		return a.field, true
	}
	if int(v) >= len(f.Values) {
		return "", false
	}
	def := f.Values[v].Def
	if def.Kind != mir.ValueDefInstr || int(def.Block) >= len(f.Blocks) || def.Instr < 0 || def.Instr >= len(f.Blocks[def.Block].Instrs) {
		return "", false
	}
	in := &f.Blocks[def.Block].Instrs[def.Instr]
	if in.Op != mir.OpLoad {
		return "", false
	}
	field, _, ok := frameFieldPlace(&in.Place)
	return field, ok
}

// frameScopeAnchorErrors checks the anchor and saved-scope rules for a step.
func frameScopeAnchorErrors(m *mir.Module, inv *frameInventory, step *frameStepInfo, save map[string][]string) []Error {
	anchors, errs := frameScopeAnchors(m, inv, step)
	f := step.fn
	if len(errs) != 0 {
		return errs
	}
	for _, b := range f.Blocks {
		if b == nil {
			continue
		}
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op != mir.OpCleanupPush && in.Op != mir.OpCleanupScopeRun && in.Op != mir.OpCleanupScopeEnd {
				continue
			}
			field, ok := frameScopeOperandField(f, anchors, in.Scope)
			if ok {
				if fi, found := step.frame.byName[field]; found && step.frame.fields[fi].kind == frameFieldScope {
					continue
				}
			}
			if def := frameDefiningInstr(f, in.Scope); def != nil && def.Op == mir.OpCleanupScopeBegin {
				// A local scope with no s<i> anchor is legal until it spans
				// a suspension, which phase 7 rejects.
				continue
			}
			errs = append(errs, Error{Loc: locInstr(f, b, ii, in), Msg: "a frame cleanup scope handle must be anchored to a frame s<i> field"})
		}
	}
	// Each state that saves a scope begins with an emission of one of its
	// saved scope fields; this is how a resume continues the recorded scope
	// rather than substituting a new one.
	for _, variant := range step.variants {
		name := variant.Name
		if name == "entry" {
			continue
		}
		target, ok := step.dispatch[name]
		if !ok {
			continue
		}
		saved := make(map[string]bool)
		for _, field := range save[name] {
			fi, ok := step.frame.byName[field]
			if ok && step.frame.fields[fi].kind == frameFieldScope {
				saved[field] = true
			}
		}
		if len(saved) == 0 {
			continue
		}
		first := frameFirstBegin(m, f, target)
		if first == mir.NoValue {
			errs = append(errs, Error{Loc: locBlock(f, f.Blocks[target]), Msg: "a state that saves a cleanup scope must re-enter it with an adopting begin"})
			continue
		}
		anchor, ok := anchors[first]
		if !ok || !saved[anchor.field] {
			errs = append(errs, Error{Loc: locBlock(f, f.Blocks[target]), Msg: "a resumed cleanup scope must be anchored to one of the state's saved s<i> fields"})
		}
	}
	return errs
}

// frameFirstBegin returns the first cleanup.scope.begin on the canonical
// resume path from target, following the non-cancellation edge of a resume
// check and stopping at other dispatch targets.
func frameFirstBegin(m *mir.Module, f *mir.Function, target mir.BlockId) mir.ValueId {
	visited := make(map[mir.BlockId]bool)
	preds := framePredecessors(f)
	cur := target
	for int(cur) < len(f.Blocks) && f.Blocks[cur] != nil && !visited[cur] {
		visited[cur] = true
		b := f.Blocks[cur]
		for ii := range b.Instrs {
			in := &b.Instrs[ii]
			if in.Op == mir.OpCleanupScopeBegin && in.Result != mir.NoValue {
				return in.Result
			}
		}
		switch b.Term.Kind {
		case mir.TermJump:
			next := b.Term.Target
			if int(next) >= len(f.Blocks) || len(preds[next]) != 1 {
				return mir.NoValue
			}
			cur = next
		case mir.TermBranch:
			if !frameCancelCond(m, f, b.Term.Cond) {
				return mir.NoValue
			}
			next := b.Term.Else
			if int(next) >= len(f.Blocks) || len(preds[next]) != 1 || next == 0 {
				return mir.NoValue
			}
			cur = next
		default:
			return mir.NoValue
		}
	}
	return mir.NoValue
}
