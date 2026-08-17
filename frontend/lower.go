package frontend

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/4fuu/alder/mir"
)

// lowerer emits a verified-ready MIR module from checked functions.
type lowerer struct {
	m          *mir.Module
	checked    []*checkedFn
	ann        map[*checkedFn]map[Expr]*annInfo
	importSigs map[string]*checkSig

	fnID        map[*checkedFn]mir.FunctionId
	fnByName    map[string]*checkedFn
	tyCache     map[string]mir.TypeId
	hashEq      map[string]*hashEqIDs
	consts      map[string]string
	constSeq    int
	mapCache    map[string]*mapHelpers
	bufferCache map[string]*bufferHelpers
}

// hashEqIDs are the per-key hash and equality helpers.
type hashEqIDs struct {
	hashID mir.FunctionId
	eqID   mir.FunctionId
}

// checkedModule is the result of type-checking: instantiations, annotations,
// and import signatures.
type checkedModule struct {
	fns     []*checkedFn
	ann     map[*checkedFn]map[Expr]*annInfo
	imports map[string]*checkSig
}

// lowerModule produces the MIR module. All type-checking and
// monomorphization happened before this point.
func lowerModule(decls []Decl, cm *checkedModule) (*mir.Module, error) {
	m := mir.NewModule()
	l := &lowerer{
		m:           m,
		checked:     cm.fns,
		ann:         cm.ann,
		importSigs:  cm.imports,
		fnID:        make(map[*checkedFn]mir.FunctionId),
		fnByName:    make(map[string]*checkedFn),
		tyCache:     make(map[string]mir.TypeId),
		hashEq:      make(map[string]*hashEqIDs),
		consts:      make(map[string]string),
		mapCache:    make(map[string]*mapHelpers),
		bufferCache: make(map[string]*bufferHelpers),
	}
	// Imports in source order.
	for _, d := range decls {
		imp, ok := d.(*ImportDecl)
		if !ok {
			continue
		}
		sig := cm.imports[imp.Name]
		params := make([]mir.TypeId, 0, len(sig.Params))
		for _, p := range sig.Params {
			params = append(params, l.ty(p))
		}
		m.AddImport(imp.Name, mir.FuncSig{Params: params, Result: l.ty(sig.Result)})
	}
	// Pass 1: function skeletons in instantiation order.
	for _, cf := range cm.fns {
		params := make([]mir.Param, 0, len(cf.params))
		pi := 0
		for _, p := range cf.decl.Params {
			if p.Kind == paramType {
				continue
			}
			params = append(params, mir.Param{Name: p.Name, Type: l.ty(cf.params[pi])})
			pi++
		}
		m.AddFunction(cf.name, params, l.ty(cf.result))
		l.fnID[cf] = mir.FunctionId(len(m.Functions) - 1)
		if len(cf.typeArgs) == 0 {
			l.fnByName[cf.decl.Name] = cf
		}
	}
	// Pass 2: bodies. The count is fixed before lowering; generated map
	// helpers are appended and lowered eagerly at creation.
	n := len(m.Functions)
	for i := 0; i < n; i++ {
		if err := l.lowerFn(cm.fns[i]); err != nil {
			return nil, err
		}
	}
	return m, nil
}

// ty interns a checked type into the module type table.
func (l *lowerer) ty(t *Type) mir.TypeId {
	switch t.kind {
	case tPrim:
		return primMir(t.prim)
	case tSlice:
		return l.m.Slice(l.ty(t.elem))
	case tAlloc:
		return l.m.SafeMut(l.ty(t.elem))
	case tOption:
		return l.m.Option(l.ty(t.elem))
	case tResult:
		return l.m.Result(l.ty(t.ok), l.ty(t.err))
	case tMap:
		return l.mapType(t)
	case tBuffer:
		return l.bufferType(t)
	case tS0Error:
		return l.s0ErrorType()
	case tStruct, tEnum:
		return l.structType(t)
	case tDomain:
		return l.m.DomainHandle()
	case tDomainMark:
		return l.m.DomainMark()
	case tCleanupScope:
		return l.m.CleanupScope()
	case tCleanupID:
		return l.m.CleanupID()
	case tPtr:
		return l.m.RawPtr(l.ty(t.elem))
	}
	return mir.TypeUnit
}

func primMir(p primType) mir.TypeId {
	switch p {
	case pBool:
		return mir.TypeBool
	case pI8:
		return mir.TypeI8
	case pI16:
		return mir.TypeI16
	case pI32:
		return mir.TypeI32
	case pI64:
		return mir.TypeI64
	case pU8:
		return mir.TypeU8
	case pU16:
		return mir.TypeU16
	case pU32:
		return mir.TypeU32
	case pU64:
		return mir.TypeU64
	case pF32:
		return mir.TypeF32
	case pF64:
		return mir.TypeF64
	}
	return mir.TypeUnit
}

// structType interns a monomorphized struct or enum by mangled name.
func (l *lowerer) structType(t *Type) mir.TypeId {
	key := t.mangledName()
	if id, ok := l.tyCache[key]; ok {
		return id
	}
	bindings := structBindings(t)
	if t.kind == tEnum {
		variants := make([]mir.Variant, 0, len(t.decl.variants))
		for _, v := range t.decl.variants {
			payload := mir.TypeUnit
			if v.payload != nil {
				payload = l.ty(substType(v.payload, bindings))
			}
			variants = append(variants, mir.Variant{Name: v.name, Payload: payload})
		}
		id := l.m.AddEnum(key, variants)
		l.tyCache[key] = id
		return id
	}
	fields := make([]mir.Field, 0, len(t.decl.fields))
	for i, f := range t.decl.fields {
		fields = append(fields, mir.Field{Name: t.decl.decl.Fields[i].Name, Type: l.ty(substType(f, bindings))})
	}
	id := l.m.AddAggregate(key, fields)
	l.tyCache[key] = id
	return id
}

// mapType interns the Map(K, V) aggregate and its entry type.
func (l *lowerer) mapType(t *Type) mir.TypeId {
	key := t.mangledName()
	if id, ok := l.tyCache[key]; ok {
		return id
	}
	entryKey := "MapEntry." + strings.TrimPrefix(key, "Map.c2.")
	entry := l.m.AddAggregate(entryKey, []mir.Field{
		{Name: "state", Type: mir.TypeU8},
		{Name: "hash", Type: mir.TypeU64},
		{Name: "key", Type: l.ty(t.key)},
		{Name: "value", Type: l.ty(t.val)},
	})
	id := l.m.AddAggregate(key, []mir.Field{
		{Name: "slots", Type: l.m.SafeMut(entry)},
	})
	l.tyCache[key] = id
	return id
}

type bufferHelpers struct{ newID, lenID, appendID, getID, setID, sliceID mir.FunctionId }

func (l *lowerer) s0ErrorType() mir.TypeId {
	const key = "__s0_Error"
	if id, ok := l.tyCache[key]; ok {
		return id
	}
	id := l.m.AddEnum(key, []mir.Variant{{Name: "OutOfMemory", Payload: mir.TypeUnit}, {Name: "Limit", Payload: mir.TypeUnit}})
	l.tyCache[key] = id
	return id
}

func (l *lowerer) bufferType(t *Type) mir.TypeId {
	key := t.mangledName()
	if id, ok := l.tyCache[key]; ok {
		return id
	}
	id := l.m.AddAggregate(key, []mir.Field{{Name: "data", Type: l.m.SafeMut(l.ty(t.elem))}, {Name: "len", Type: mir.TypeU64}})
	l.tyCache[key] = id
	return id
}

func (l *lowerer) bufferHelpersFor(t *Type) *bufferHelpers {
	key := t.elem.mangledName()
	if h := l.bufferCache[key]; h != nil {
		return h
	}
	bt, et := l.bufferType(t), l.ty(t.elem)
	errt := l.s0ErrorType()
	rt := l.m.Result(bt, errt)
	add := func(n string, p []mir.Param, r mir.TypeId) mir.FunctionId {
		l.m.AddFunction("buffer."+n+"."+key, p, r)
		return mir.FunctionId(len(l.m.Functions) - 1)
	}
	h := &bufferHelpers{}
	h.newID = add("new", []mir.Param{{Name: "d", Type: l.m.DomainHandle()}}, rt)
	h.lenID = add("len", []mir.Param{{Name: "b", Type: bt}}, mir.TypeU64)
	h.appendID = add("append", []mir.Param{{Name: "d", Type: l.m.DomainHandle()}, {Name: "b", Type: bt}, {Name: "v", Type: et}}, rt)
	h.getID = add("get", []mir.Param{{Name: "b", Type: bt}, {Name: "i", Type: mir.TypeU64}}, et)
	h.setID = add("set", []mir.Param{{Name: "b", Type: bt}, {Name: "i", Type: mir.TypeU64}, {Name: "v", Type: et}}, mir.TypeUnit)
	h.sliceID = add("slice", []mir.Param{{Name: "b", Type: bt}}, l.m.Slice(et))
	l.bufferCache[key] = h
	l.lowerBufferNew(h, t, bt, et, errt, rt)
	l.lowerBufferLen(h, t, bt)
	l.lowerBufferAppend(h, t, bt, et, errt, rt)
	l.lowerBufferSet(h, t, bt, et)
	l.lowerBufferGetSlice(h, t, bt, et)
	return h
}

func (l *lowerer) bufferConst(b *fb, v int64) mir.ValueId {
	return b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: v})
}
func (l *lowerer) bufferErr(b *fb, errt, rt mir.TypeId, variant string) mir.ValueId {
	e := b.res(errt)
	b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: e, TypeOp: errt, Variant: variant})
	r := b.res(rt)
	b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: r, TypeOp: rt, Variant: "err", Payload: e})
	return r
}
func (l *lowerer) bufferOK(b *fb, rt mir.TypeId, v mir.ValueId) mir.ValueId {
	r := b.res(rt)
	b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: r, TypeOp: rt, Variant: "ok", Payload: v})
	return r
}
func (l *lowerer) bufferAgg(b *fb, bt mir.TypeId, data, len mir.ValueId) mir.ValueId {
	v := b.res(bt)
	b.emit(mir.Instr{Op: mir.OpAggregateConstruct, Result: v, AggType: bt, AggFields: []mir.AggField{{Name: "data", Value: data}, {Name: "len", Value: len}}})
	return v
}

func (l *lowerer) lowerBufferNew(h *bufferHelpers, t *Type, bt, et, errt, rt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.newID])
	b.result = &Type{kind: tResult, ok: t, err: &Type{kind: tS0Error}}
	b.start("bb0")
	cap := l.bufferConst(b, 8)
	ok, _ := b.addBlock("bb_ok", nil)
	oom, _ := b.addBlock("bb_oom", nil)
	data := b.res(l.m.SafeMut(et))
	b.emit(mir.Instr{Op: mir.OpAllocChecked, Result: data, Domain: 0, Count: cap, TypeOp: et, FailTarget: blkID(b.f, oom)})
	b.jump(blkID(b.f, ok), nil)
	b.setCur(oom)
	b.ret(l.bufferErr(b, errt, rt, "OutOfMemory"))
	b.setCur(ok)
	zero := l.bufferConst(b, 0)
	b.ret(l.bufferOK(b, rt, l.bufferAgg(b, bt, data, zero)))
}
func (l *lowerer) lowerBufferLen(h *bufferHelpers, t *Type, bt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.lenID])
	b.result = prim(pU64)
	b.start("bb0")
	loc := b.f.AddLocal(b.localName("b"), bt)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: loc}, 0)
	b.ret(b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: loc}, Field: "len"}, mir.TypeU64))
}

func (l *lowerer) lowerBufferAppend(h *bufferHelpers, t *Type, bt, et, errt, rt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.appendID])
	b.result = &Type{kind: tResult, ok: t, err: &Type{kind: tS0Error}}
	b.start("bb0")
	loc := b.f.AddLocal(b.localName("b"), bt)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: loc}, 1)
	fld := func(n string, ty mir.TypeId) mir.ValueId {
		return b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: loc}, Field: n}, ty)
	}
	st := l.m.SafeMut(et)
	data, lenv := fld("data", st), fld("len", mir.TypeU64)
	cap := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpSliceLen, Result: cap, Slice: data})
	spare, _ := b.addBlock("bb_spare", nil)
	grow, _ := b.addBlock("bb_grow", nil)
	eq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: eq, A: lenv, B: cap})
	b.branch(eq, blkID(b.f, grow), blkID(b.f, spare))
	panic := b.panicBlock()
	one := l.bufferConst(b, 1)
	b.setCur(spare)
	ref := b.res(st)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: data, Index: lenv, FailTarget: panic})
	b.storePlace(mir.Place{Kind: mir.PlaceDeref, Deref: ref}, 2)
	nl := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: nl, A: lenv, B: one, FailTarget: panic})
	b.ret(l.bufferOK(b, rt, l.bufferAgg(b, bt, data, nl)))
	b.setCur(grow)
	limit, _ := b.addBlock("bb_limit", nil)
	alloc, _ := b.addBlock("bb_alloc", nil)
	two := l.bufferConst(b, 2)
	nc := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: nc, A: cap, B: two, FailTarget: blkID(b.f, limit)})
	b.jump(blkID(b.f, alloc), nil)
	b.setCur(limit)
	b.ret(l.bufferErr(b, errt, rt, "Limit"))
	b.setCur(alloc)
	oom, _ := b.addBlock("bb_oom", nil)
	copyHead, cp := b.addBlock("bb_copy", []mir.Param{{Name: "i", Type: mir.TypeU64}})
	copyBody, _ := b.addBlock("bb_copy_one", nil)
	finish, _ := b.addBlock("bb_finish", nil)
	nd := b.res(st)
	b.emit(mir.Instr{Op: mir.OpAllocChecked, Result: nd, Domain: 0, Count: nc, TypeOp: et, FailTarget: blkID(b.f, oom)})
	zero := l.bufferConst(b, 0)
	b.jump(blkID(b.f, copyHead), []mir.ValueId{zero})
	b.setCur(oom)
	b.ret(l.bufferErr(b, errt, rt, "OutOfMemory"))
	b.setCur(copyHead)
	done := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntGe, Result: done, A: cp[0], B: lenv})
	b.branch(done, blkID(b.f, finish), blkID(b.f, copyBody))
	b.setCur(copyBody)
	or := b.res(st)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: or, Slice: data, Index: cp[0], FailTarget: panic})
	val := b.loadPlace(mir.Place{Kind: mir.PlaceDeref, Deref: or}, et)
	nr := b.res(st)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: nr, Slice: nd, Index: cp[0], FailTarget: panic})
	b.storePlace(mir.Place{Kind: mir.PlaceDeref, Deref: nr}, val)
	ni := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: ni, A: cp[0], B: one, FailTarget: panic})
	b.jump(blkID(b.f, copyHead), []mir.ValueId{ni})
	b.setCur(finish)
	ar := b.res(st)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ar, Slice: nd, Index: lenv, FailTarget: panic})
	b.storePlace(mir.Place{Kind: mir.PlaceDeref, Deref: ar}, 2)
	nn := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: nn, A: lenv, B: one, FailTarget: panic})
	b.ret(l.bufferOK(b, rt, l.bufferAgg(b, bt, nd, nn)))
}

func (l *lowerer) lowerBufferSet(h *bufferHelpers, t *Type, bt, et mir.TypeId) {
	b := l.newFB(l.m.Functions[h.setID])
	b.result = prim(pUnit)
	b.start("bb0")
	loc := b.f.AddLocal(b.localName("b"), bt)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: loc}, 0)
	base := mir.Place{Kind: mir.PlaceLocal, Local: loc}
	data := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &base, Field: "data"}, l.m.SafeMut(et))
	ln := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &base, Field: "len"}, mir.TypeU64)
	inside := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntLt, Result: inside, A: 1, B: ln})
	valid, _ := b.addBlock("bb_valid", nil)
	b.branch(inside, blkID(b.f, valid), b.panicBlock())
	b.setCur(valid)
	ref := b.res(l.m.SafeMut(et))
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: data, Index: 1, FailTarget: b.panicBlock()})
	b.storePlace(mir.Place{Kind: mir.PlaceDeref, Deref: ref}, 2)
	b.ret(mir.NoValue)
}

func (l *lowerer) lowerBufferGetSlice(h *bufferHelpers, t *Type, bt, et mir.TypeId) {
	for _, spec := range []struct {
		id    mir.FunctionId
		slice bool
	}{{h.getID, false}, {h.sliceID, true}} {
		b := l.newFB(l.m.Functions[spec.id])
		if spec.slice {
			b.result = &Type{kind: tSlice, elem: t.elem}
		} else {
			b.result = t.elem
		}
		b.start("bb0")
		loc := b.f.AddLocal(b.localName("b"), bt)
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: loc}, 0)
		base := mir.Place{Kind: mir.PlaceLocal, Local: loc}
		data := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &base, Field: "data"}, l.m.SafeMut(et))
		if spec.slice {
			ln := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &base, Field: "len"}, mir.TypeU64)
			z := l.bufferConst(b, 0)
			out := b.res(l.m.Slice(et))
			b.emit(mir.Instr{Op: mir.OpSliceRangeChecked, Result: out, Slice: data, Lo: z, Hi: ln, FailTarget: b.panicBlock()})
			b.ret(out)
		} else {
			ln := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &base, Field: "len"}, mir.TypeU64)
			inside := b.res(mir.TypeBool)
			b.emit(mir.Instr{Op: mir.OpIntLt, Result: inside, A: 1, B: ln})
			valid, _ := b.addBlock("bb_valid", nil)
			b.branch(inside, blkID(b.f, valid), b.panicBlock())
			b.setCur(valid)
			ref := b.res(l.m.SafeMut(et))
			b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: data, Index: 1, FailTarget: b.panicBlock()})
			b.ret(b.loadPlace(mir.Place{Kind: mir.PlaceDeref, Deref: ref}, et))
		}
	}
}

// mapHelpers are the generated functions implementing Map(K, V).
type mapHelpers struct {
	makeID   mir.FunctionId
	hashID   mir.FunctionId
	eqID     mir.FunctionId
	getID    mir.FunctionId
	setID    mir.FunctionId
	removeID mir.FunctionId
}

// mapCap is the fixed capacity of every map.
const mapCap = 16

// mapHelpersFor creates the map helper functions and types on first use.
func (l *lowerer) mapHelpersFor(t *Type) *mapHelpers {
	key := mapKey(t)
	if h, ok := l.mapCache[key]; ok {
		return h
	}
	h := &mapHelpers{}
	mapTy := l.mapType(t)
	slotsTy := l.m.Types[mapTy].Fields[0].Type // safe_mut(MapEntry)
	kt := l.ty(t.key)
	vt := l.ty(t.val)
	optV := l.m.Option(vt)

	// The hash and equality helpers are per key type; share them across
	// map instantiations.
	he := l.hashEq[t.key.mangledName()]
	fresh := false
	if he == nil {
		he = &hashEqIDs{}
		fresh = true
		he.hashID = l.addMapFn("map.hash."+t.key.mangledName(), []mir.Param{{Name: "k", Type: kt}}, mir.TypeU64)
		he.eqID = l.addMapFn("map.eq."+t.key.mangledName(), []mir.Param{{Name: "a", Type: kt}, {Name: "b", Type: kt}}, mir.TypeBool)
		l.hashEq[t.key.mangledName()] = he
	}
	h.hashID = he.hashID
	h.eqID = he.eqID

	sfx := mapFnSuffix(t)
	h.makeID = l.addMapFn("map.make."+sfx, []mir.Param{{Name: "d", Type: l.m.DomainHandle()}}, mapTy)
	h.getID = l.addMapFn("map.get."+sfx, []mir.Param{{Name: "m", Type: mapTy}, {Name: "k", Type: kt}}, optV)
	h.setID = l.addMapFn("map.set."+sfx, []mir.Param{{Name: "m", Type: mapTy}, {Name: "k", Type: kt}, {Name: "v", Type: vt}}, mir.TypeBool)
	h.removeID = l.addMapFn("map.remove."+sfx, []mir.Param{{Name: "m", Type: mapTy}, {Name: "k", Type: kt}}, mir.TypeBool)
	l.mapCache[key] = h

	if fresh {
		l.lowerMapHash(h, t, kt)
		l.lowerMapEq(h, t, kt)
	}
	l.lowerMapMake(h, t, mapTy, slotsTy)
	l.lowerMapGet(h, t, mapTy, slotsTy, optV, kt, vt)
	l.lowerMapSet(h, mapTy, slotsTy, kt, vt)
	l.lowerMapRemove(h, mapTy, slotsTy, kt)
	return h
}

func mapKey(t *Type) string { return t.key.mangledName() + "," + t.val.mangledName() }

// mapFnSuffix is the dot-joined key/value mangle used in helper names.
func mapFnSuffix(t *Type) string {
	return t.key.mangledName() + "." + t.val.mangledName()
}

// addMapFn appends a generated map helper and returns its id.
func (l *lowerer) addMapFn(name string, params []mir.Param, result mir.TypeId) mir.FunctionId {
	l.m.AddFunction(name, params, result)
	return mir.FunctionId(len(l.m.Functions) - 1)
}

// mapConst returns a shared u64 constant for the map helpers.
func (l *lowerer) mapConst(b *fb, name string, v int64) mir.ValueId {
	key := "u64|" + name
	cname, ok := l.consts[key]
	if !ok {
		cname = "lit.map." + name
		l.consts[key] = cname
		l.m.AddConst(cname, mir.TypeU64, mir.ConstValue{Kind: mir.ConstInt, Int: v})
	}
	id := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpConstGet, Result: id, Const: cname})
	return id
}

// lowerMapMake allocates and explicitly marks every slot empty. Domain
// allocation is uninitialized, so no other entry field may be read first.
func (l *lowerer) lowerMapMake(h *mapHelpers, t *Type, mapTy, slotsTy mir.TypeId) {
	b := l.newFB(l.m.Functions[h.makeID])
	b.result = t
	b.start("bb0")
	cap := l.mapConst(b, "cap", mapCap)
	entryTy := l.m.Types[slotsTy].Elem
	slots := b.res(slotsTy)
	b.emit(mir.Instr{Op: mir.OpAlloc, Result: slots, Domain: 0, Count: cap, TypeOp: entryTy})
	id := b.res(mapTy)
	b.emit(mir.Instr{Op: mir.OpAggregateConstruct, Result: id, AggType: mapTy, AggFields: []mir.AggField{{Name: "slots", Value: slots}}})
	// The checked initialization index is bounded by the loop condition. Give
	// its impossible-but-explicit failure edge the standard panic policy.
	fail := b.f.AddBlock(b.blockName("bb_fail"), nil)
	fail.SetTerm(mir.Terminator{Kind: mir.TermPanic, Result: mir.NoValue})
	b.panicBlk = blkID(b.f, fail)
	zero := l.mapConst(b, "zero", 0)
	one := l.mapConst(b, "one", 1)
	loop, params := b.addBlock("bb_init", []mir.Param{{Name: "i", Type: mir.TypeU64}})
	body, _ := b.addBlock("bb_init_slot", nil)
	done, _ := b.addBlock("bb_done", nil)
	b.jump(blkID(b.f, loop), []mir.ValueId{zero})
	b.setCur(loop)
	finished := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntGe, Result: finished, A: params[0], B: cap})
	b.branch(finished, blkID(b.f, done), blkID(b.f, body))
	b.setCur(body)
	ref := b.res(slotsTy)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: slots, Index: params[0], FailTarget: b.panicBlock()})
	empty := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "state"}, empty)
	next := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: next, A: params[0], B: one, FailTarget: b.panicBlock()})
	b.jump(blkID(b.f, loop), []mir.ValueId{next})
	b.setCur(done)
	b.ret(id)
}

// lowerMapHash: fn map.hash.K(k) -> U64.
func (l *lowerer) lowerMapHash(h *mapHelpers, t *Type, kt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.hashID])
	b.result = prim(pU64)
	b.start("bb0")
	local := b.f.AddLocal(b.localName("k"), kt)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, 0)
	v := b.loadPlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, kt)
	hv := b.hashValue(v, t.key)
	b.ret(hv)
}

// lowerMapEq: fn map.eq.K(a, b) -> Bool.
func (l *lowerer) lowerMapEq(h *mapHelpers, t *Type, kt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.eqID])
	b.result = prim(pBool)
	b.start("bb0")
	la := b.f.AddLocal(b.localName("a"), kt)
	lb := b.f.AddLocal(b.localName("b"), kt)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: la}, 0)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: lb}, 1)
	av := b.loadPlace(mir.Place{Kind: mir.PlaceLocal, Local: la}, kt)
	bv := b.loadPlace(mir.Place{Kind: mir.PlaceLocal, Local: lb}, kt)
	trueBlk, _ := b.addBlock("bb_true", nil)
	falseBlk, _ := b.addBlock("bb_false", nil)
	b.emitEq(av, bv, t.key, blkID(b.f, trueBlk), blkID(b.f, falseBlk))
	b.setCur(trueBlk)
	tv := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: true})
	b.ret(tv)
	b.setCur(falseBlk)
	fv := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: false})
	b.ret(fv)
}

// lowerMapGet implements linear-probing lookup.
func (l *lowerer) lowerMapGet(h *mapHelpers, t *Type, mapTy, slotsTy, optV, kt, vt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.getID])
	b.result = &Type{kind: tOption, elem: t.val}
	b.start("bb0")
	ml := b.f.AddLocal(b.localName("m"), mapTy)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: ml}, 0)
	hash := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpCall, Result: hash, Callee: h.hashID, Args: []mir.ValueId{1}})
	cap := l.mapConst(b, "cap", mapCap)
	zero := l.mapConst(b, "zero", 0)
	one := l.mapConst(b, "one", 1)
	q := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: q, A: hash, B: cap, FailTarget: b.panicBlock()})
	p := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: p, A: q, B: cap, FailTarget: b.panicBlock()})
	idx := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: idx, A: hash, B: p, FailTarget: b.panicBlock()})

	loop, loopParams := b.addBlock("bb_loop", []mir.Param{{Name: "idx", Type: mir.TypeU64}, {Name: "probes", Type: mir.TypeU64}})
	probe, _ := b.addBlock("bb_probe", nil)
	none, _ := b.addBlock("bb_none", nil)
	b.setCur(loop)
	ge := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntGe, Result: ge, A: loopParams[1], B: cap})
	b.branch(ge, blkID(b.f, none), blkID(b.f, probe))

	b.setCur(probe)
	slots := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: ml}, Field: "slots"}, slotsTy)
	ref := b.res(slotsTy)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: slots, Index: loopParams[0], FailTarget: b.panicBlock()})
	state := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "state"}, mir.TypeU8)
	occupied := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	occ := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: occ, A: state, B: occupied})
	occBlk, _ := b.addBlock("bb_occ", nil)
	nonOcc, _ := b.addBlock("bb_non_occ", nil)
	b.branch(occ, blkID(b.f, occBlk), blkID(b.f, nonOcc))

	b.setCur(nonOcc)
	emptyState := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
	isEmpty := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: isEmpty, A: state, B: emptyState})
	empty, _ := b.addBlock("bb_empty", nil)
	next, _ := b.addBlock("bb_next", nil)
	b.branch(isEmpty, blkID(b.f, empty), blkID(b.f, next))

	b.setCur(empty)
	noneVal := b.res(optV)
	b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: noneVal, TypeOp: optV, Variant: "none"})
	b.ret(noneVal)

	b.setCur(occBlk)
	eh := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "hash"}, mir.TypeU64)
	heq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: heq, A: eh, B: hash})
	check, _ := b.addBlock("bb_check", nil)
	b.branch(heq, blkID(b.f, check), blkID(b.f, next))

	b.setCur(check)
	ek := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "key"}, kt)
	keq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpCall, Result: keq, Callee: h.eqID, Args: []mir.ValueId{1, ek}})
	found, _ := b.addBlock("bb_found", nil)
	b.branch(keq, blkID(b.f, found), blkID(b.f, next))

	b.setCur(found)
	val := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "value"}, vt)
	someVal := b.res(optV)
	b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: someVal, TypeOp: optV, Variant: "some", Payload: val})
	b.ret(someVal)

	b.setCur(next)
	ni := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: ni, A: loopParams[0], B: one, FailTarget: b.panicBlock()})
	nq := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: nq, A: ni, B: cap, FailTarget: b.panicBlock()})
	np := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: np, A: nq, B: cap, FailTarget: b.panicBlock()})
	ni2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: ni2, A: ni, B: np, FailTarget: b.panicBlock()})
	np2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: np2, A: loopParams[1], B: one, FailTarget: b.panicBlock()})
	b.jump(blkID(b.f, loop), []mir.ValueId{ni2, np2})

	b.setCur(none)
	noneVal2 := b.res(optV)
	b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: noneVal2, TypeOp: optV, Variant: "none"})
	b.ret(noneVal2)

	// Entry edge: jump into the loop head.
	b.setCur(b.f.Blocks[0])
	b.jump(blkID(b.f, loop), []mir.ValueId{idx, zero})
}

// lowerMapSet implements insertion with linear probing.
func (l *lowerer) lowerMapSet(h *mapHelpers, mapTy, slotsTy, kt, vt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.setID])
	b.result = prim(pBool)
	b.start("bb0")
	ml := b.f.AddLocal(b.localName("m"), mapTy)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: ml}, 0)
	hash := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpCall, Result: hash, Callee: h.hashID, Args: []mir.ValueId{1}})
	cap := l.mapConst(b, "cap", mapCap)
	zero := l.mapConst(b, "zero", 0)
	one := l.mapConst(b, "one", 1)
	q := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: q, A: hash, B: cap, FailTarget: b.panicBlock()})
	p := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: p, A: q, B: cap, FailTarget: b.panicBlock()})
	idx := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: idx, A: hash, B: p, FailTarget: b.panicBlock()})

	loop, loopParams := b.addBlock("bb_loop", []mir.Param{{Name: "idx", Type: mir.TypeU64}, {Name: "probes", Type: mir.TypeU64}, {Name: "first_deleted", Type: mir.TypeU64}})
	probe, _ := b.addBlock("bb_probe", nil)
	full, _ := b.addBlock("bb_full", nil)
	b.setCur(loop)
	ge := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntGe, Result: ge, A: loopParams[1], B: cap})
	b.branch(ge, blkID(b.f, full), blkID(b.f, probe))

	b.setCur(probe)
	slots := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: ml}, Field: "slots"}, slotsTy)
	ref := b.res(slotsTy)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: slots, Index: loopParams[0], FailTarget: b.panicBlock()})
	state := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "state"}, mir.TypeU8)
	occupied := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	occ := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: occ, A: state, B: occupied})
	occBlk, _ := b.addBlock("bb_occ", nil)
	nonOcc, _ := b.addBlock("bb_non_occ", nil)
	b.branch(occ, blkID(b.f, occBlk), blkID(b.f, nonOcc))

	b.setCur(nonOcc)
	emptyState := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
	isEmpty := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: isEmpty, A: state, B: emptyState})
	empty, _ := b.addBlock("bb_empty", nil)
	deleted, _ := b.addBlock("bb_deleted", nil)
	b.branch(isEmpty, blkID(b.f, empty), blkID(b.f, deleted))

	// Use an earlier tombstone, if any, after proving the key is absent.
	b.setCur(empty)
	hasDeleted := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: hasDeleted, A: loopParams[2], B: cap})
	useCurrent, _ := b.addBlock("bb_use_current", nil)
	useDeleted, _ := b.addBlock("bb_use_deleted", nil)
	insert, insertParams := b.addBlock("bb_insert", []mir.Param{{Name: "idx", Type: mir.TypeU64}})
	b.branch(hasDeleted, blkID(b.f, useCurrent), blkID(b.f, useDeleted))
	b.setCur(useCurrent)
	b.jump(blkID(b.f, insert), []mir.ValueId{loopParams[0]})
	b.setCur(useDeleted)
	b.jump(blkID(b.f, insert), []mir.ValueId{loopParams[2]})
	b.setCur(insert)
	insertSlots := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: ml}, Field: "slots"}, slotsTy)
	insertRef := b.res(slotsTy)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: insertRef, Slice: insertSlots, Index: insertParams[0], FailTarget: b.panicBlock()})
	insertOccupied := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: insertRef}, Field: "state"}, insertOccupied)
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: insertRef}, Field: "hash"}, hash)
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: insertRef}, Field: "key"}, 1)
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: insertRef}, Field: "value"}, 2)
	done, _ := b.addBlock("bb_done", nil)
	b.jump(blkID(b.f, done), nil)

	b.setCur(occBlk)
	eh := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "hash"}, mir.TypeU64)
	heq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: heq, A: eh, B: hash})
	check, _ := b.addBlock("bb_check", nil)
	next, _ := b.addBlock("bb_next", nil)
	b.branch(heq, blkID(b.f, check), blkID(b.f, next))

	b.setCur(check)
	ek := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "key"}, kt)
	keq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpCall, Result: keq, Callee: h.eqID, Args: []mir.ValueId{1, ek}})
	write, _ := b.addBlock("bb_write", nil)
	b.branch(keq, blkID(b.f, write), blkID(b.f, next))

	b.setCur(write)
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "value"}, 2)
	b.jump(blkID(b.f, done), nil)

	b.setCur(next)
	ni := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: ni, A: loopParams[0], B: one, FailTarget: b.panicBlock()})
	nq := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: nq, A: ni, B: cap, FailTarget: b.panicBlock()})
	np := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: np, A: nq, B: cap, FailTarget: b.panicBlock()})
	ni2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: ni2, A: ni, B: np, FailTarget: b.panicBlock()})
	np2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: np2, A: loopParams[1], B: one, FailTarget: b.panicBlock()})
	b.jump(blkID(b.f, loop), []mir.ValueId{ni2, np2, loopParams[2]})

	b.setCur(deleted)
	firstUnset := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: firstUnset, A: loopParams[2], B: cap})
	record, _ := b.addBlock("bb_record_deleted", nil)
	b.branch(firstUnset, blkID(b.f, record), blkID(b.f, next))
	b.setCur(record)
	// Advance while recording this first deleted slot.
	dni := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: dni, A: loopParams[0], B: one, FailTarget: b.panicBlock()})
	dnq := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: dnq, A: dni, B: cap, FailTarget: b.panicBlock()})
	dnp := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: dnp, A: dnq, B: cap, FailTarget: b.panicBlock()})
	dni2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: dni2, A: dni, B: dnp, FailTarget: b.panicBlock()})
	dprobes := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: dprobes, A: loopParams[1], B: one, FailTarget: b.panicBlock()})
	b.jump(blkID(b.f, loop), []mir.ValueId{dni2, dprobes, loopParams[0]})

	b.setCur(done)
	inserted := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: true})
	b.ret(inserted)

	b.setCur(full)
	noDeleted := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: noDeleted, A: loopParams[2], B: cap})
	failed, _ := b.addBlock("bb_failed", nil)
	b.branch(noDeleted, blkID(b.f, failed), blkID(b.f, useDeleted))
	b.setCur(failed)
	notInserted := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: false})
	b.ret(notInserted)

	b.setCur(b.f.Blocks[0])
	b.jump(blkID(b.f, loop), []mir.ValueId{idx, zero, cap})
}

// lowerMapRemove implements deletion with linear probing.
func (l *lowerer) lowerMapRemove(h *mapHelpers, mapTy, slotsTy, kt mir.TypeId) {
	b := l.newFB(l.m.Functions[h.removeID])
	b.result = prim(pBool)
	b.start("bb0")
	ml := b.f.AddLocal(b.localName("m"), mapTy)
	b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: ml}, 0)
	hash := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpCall, Result: hash, Callee: h.hashID, Args: []mir.ValueId{1}})
	cap := l.mapConst(b, "cap", mapCap)
	zero := l.mapConst(b, "zero", 0)
	one := l.mapConst(b, "one", 1)
	q := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: q, A: hash, B: cap, FailTarget: b.panicBlock()})
	p := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: p, A: q, B: cap, FailTarget: b.panicBlock()})
	idx := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: idx, A: hash, B: p, FailTarget: b.panicBlock()})

	loop, loopParams := b.addBlock("bb_loop", []mir.Param{{Name: "idx", Type: mir.TypeU64}, {Name: "probes", Type: mir.TypeU64}})
	probe, _ := b.addBlock("bb_probe", nil)
	none, _ := b.addBlock("bb_none", nil)
	b.setCur(loop)
	ge := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntGe, Result: ge, A: loopParams[1], B: cap})
	b.branch(ge, blkID(b.f, none), blkID(b.f, probe))

	b.setCur(probe)
	slots := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: ml}, Field: "slots"}, slotsTy)
	ref := b.res(slotsTy)
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: slots, Index: loopParams[0], FailTarget: b.panicBlock()})
	state := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "state"}, mir.TypeU8)
	occupied := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	occ := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: occ, A: state, B: occupied})
	occBlk, _ := b.addBlock("bb_occ", nil)
	nonOcc, _ := b.addBlock("bb_non_occ", nil)
	b.branch(occ, blkID(b.f, occBlk), blkID(b.f, nonOcc))

	b.setCur(nonOcc)
	emptyState := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
	isEmpty := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: isEmpty, A: state, B: emptyState})
	empty, _ := b.addBlock("bb_empty", nil)
	next, _ := b.addBlock("bb_next", nil)
	b.branch(isEmpty, blkID(b.f, empty), blkID(b.f, next))

	b.setCur(empty)
	falseVal := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: false})
	b.ret(falseVal)

	b.setCur(occBlk)
	eh := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "hash"}, mir.TypeU64)
	heq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpIntEq, Result: heq, A: eh, B: hash})
	check, _ := b.addBlock("bb_check", nil)
	b.branch(heq, blkID(b.f, check), blkID(b.f, next))

	b.setCur(check)
	ek := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "key"}, kt)
	keq := b.res(mir.TypeBool)
	b.emit(mir.Instr{Op: mir.OpCall, Result: keq, Callee: h.eqID, Args: []mir.ValueId{1, ek}})
	found, _ := b.addBlock("bb_found", nil)
	b.branch(keq, blkID(b.f, found), blkID(b.f, next))

	b.setCur(found)
	deletedState := b.constGet(prim(pU8), mir.ConstValue{Kind: mir.ConstInt, Int: 2})
	b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: "state"}, deletedState)
	trueVal := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: true})
	b.ret(trueVal)

	b.setCur(next)
	ni := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: ni, A: loopParams[0], B: one, FailTarget: b.panicBlock()})
	nq := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: nq, A: ni, B: cap, FailTarget: b.panicBlock()})
	np := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: np, A: nq, B: cap, FailTarget: b.panicBlock()})
	ni2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: ni2, A: ni, B: np, FailTarget: b.panicBlock()})
	np2 := b.res(mir.TypeU64)
	b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: np2, A: loopParams[1], B: one, FailTarget: b.panicBlock()})
	b.jump(blkID(b.f, loop), []mir.ValueId{ni2, np2})

	b.setCur(none)
	falseVal3 := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: false})
	b.ret(falseVal3)

	b.setCur(b.f.Blocks[0])
	b.jump(blkID(b.f, loop), []mir.ValueId{idx, zero})
}

// fb builds one MIR function body.
type fb struct {
	l          *lowerer
	f          *mir.Function
	ann        map[Expr]*annInfo
	result     *Type
	cur        *mir.Block
	terminated bool
	nval       int
	nlocal     int
	locals     map[string]mir.LocalId
	values     map[string]mir.ValueId
	usedVals   map[string]bool
	usedLocals map[string]bool
	usedBlocks map[string]bool
	scopes     []mir.ValueId
	panicBlk   mir.BlockId
	panicBlks  map[string]mir.BlockId
}

func (l *lowerer) newFB(f *mir.Function) *fb {
	b := &fb{
		l:          l,
		f:          f,
		locals:     make(map[string]mir.LocalId),
		values:     make(map[string]mir.ValueId),
		usedVals:   make(map[string]bool),
		usedLocals: make(map[string]bool),
		usedBlocks: make(map[string]bool),
		panicBlk:   mir.NoBlock,
		panicBlks:  make(map[string]mir.BlockId),
	}
	for _, v := range f.Values {
		b.usedVals[v.Name] = true
	}
	for _, lc := range f.Locals {
		b.usedLocals[lc.Name] = true
	}
	return b
}

// addBlock appends a block without changing the current position, and
// returns it with its parameter values.
func (b *fb) addBlock(name string, params []mir.Param) (*mir.Block, []mir.ValueId) {
	// Deduplicate parameter names before AddBlock registers their values.
	for i := range params {
		params[i].Name = b.valueName(params[i].Name)
	}
	blk := b.f.AddBlock(b.blockName(name), params)
	vals := make([]mir.ValueId, 0, len(params))
	for i := 0; i < len(params); i++ {
		vals = append(vals, mir.ValueId(len(b.f.Values)-len(params)+i))
	}
	return blk, vals
}

// blockName picks a unique block name per function.
func (b *fb) blockName(base string) string {
	if !b.usedBlocks[base] {
		b.usedBlocks[base] = true
		return base
	}
	for i := 0; ; i++ {
		name := base + strconv.Itoa(i)
		if !b.usedBlocks[name] {
			b.usedBlocks[name] = true
			return name
		}
	}
}

// start appends a fresh block and makes it current.
func (b *fb) start(name string) *mir.Block {
	blk, _ := b.addBlock(name, nil)
	b.setCur(blk)
	return blk
}

// setCur switches the current emission position.
func (b *fb) setCur(blk *mir.Block) {
	b.cur = blk
	b.terminated = false
}

// blkID returns the block id of a block in a function.
func blkID(f *mir.Function, blk *mir.Block) mir.BlockId {
	for i, g := range f.Blocks {
		if g == blk {
			return mir.BlockId(i)
		}
	}
	return 0
}

// valueName picks an unused value name.
func (b *fb) valueName(base string) string {
	if !b.usedVals[base] {
		b.usedVals[base] = true
		return base
	}
	for {
		name := base + strconv.Itoa(b.nval)
		b.nval++
		if !b.usedVals[name] {
			b.usedVals[name] = true
			return name
		}
	}
}

// localName picks an unused local name.
func (b *fb) localName(base string) string {
	if !b.usedLocals[base] {
		b.usedLocals[base] = true
		return base
	}
	for {
		name := base + strconv.Itoa(b.nlocal)
		b.nlocal++
		if !b.usedLocals[name] {
			b.usedLocals[name] = true
			return name
		}
	}
}

// res reserves a result value for the next instruction of the current block.
func (b *fb) res(typ mir.TypeId) mir.ValueId {
	id := b.f.AddValue(b.valueName("v"), typ, mir.ValueDef{Kind: mir.ValueDefInstr, Block: blkID(b.f, b.cur), Instr: len(b.cur.Instrs)})
	return id
}

// emit normalizes the zero Result and FailTarget sentinels (zero is a valid
// id), and clears a payload for payload-less enum variants.
func (b *fb) emit(in mir.Instr) {
	if !in.Op.ProducesResult() {
		in.Result = mir.NoValue
	}
	if !in.Op.HasFailEdge() {
		in.FailTarget = mir.NoBlock
	}
	if in.Op == mir.OpEnumConstruct {
		if idx, ok := b.l.m.VariantIndex(in.TypeOp, in.Variant); ok {
			if payload, _ := b.l.m.VariantPayload(in.TypeOp, idx); payload == mir.TypeUnit {
				in.Payload = mir.NoValue
			}
		}
	}
	b.cur.AddInstr(in)
}

// panicBlock returns the cleanup-aware checked-failure block for the current
// scope stack, creating it on first use. The map helper may install one shared
// panic block for its statically bounded initialization loop.
func (b *fb) panicBlock() mir.BlockId {
	if b.panicBlk != mir.NoBlock {
		return b.panicBlk
	}
	key := fmt.Sprint(b.scopes)
	if id, ok := b.panicBlks[key]; ok {
		return id
	}
	blk := b.f.AddBlock(b.blockName("bb_fail"), nil)
	saved := b.cur
	b.setCur(blk)
	b.panic()
	id := blkID(b.f, blk)
	b.panicBlks[key] = id
	b.setCur(saved)
	return id
}

// exits emits Run + End for every open using scope, in reverse order.
func (b *fb) exits() {
	for i := len(b.scopes) - 1; i >= 0; i-- {
		b.emit(mir.Instr{Op: mir.OpCleanupScopeRun, Scope: b.scopes[i]})
		b.emit(mir.Instr{Op: mir.OpCleanupScopeEnd, Scope: b.scopes[i]})
	}
}

func (b *fb) ret(v mir.ValueId) {
	b.exits()
	b.cur.SetTerm(mir.Terminator{Kind: mir.TermReturn, Result: v})
	b.terminated = true
}

func (b *fb) fail(v mir.ValueId) {
	b.exits()
	b.cur.SetTerm(mir.Terminator{Kind: mir.TermFail, Result: v})
	b.terminated = true
}

func (b *fb) panic() {
	b.exits()
	b.cur.SetTerm(mir.Terminator{Kind: mir.TermPanic, Result: mir.NoValue})
	b.terminated = true
}

func (b *fb) jump(target mir.BlockId, args []mir.ValueId) {
	b.cur.SetTerm(mir.Terminator{Kind: mir.TermJump, Target: target, Args: args})
	b.terminated = true
}

func (b *fb) branch(cond mir.ValueId, then, els mir.BlockId) {
	b.cur.SetTerm(mir.Terminator{Kind: mir.TermBranch, Cond: cond, Then: then, Else: els})
	b.terminated = true
}

func (b *fb) loadPlace(p mir.Place, typ mir.TypeId) mir.ValueId {
	id := b.res(typ)
	b.emit(mir.Instr{Op: mir.OpLoad, Result: id, Place: p})
	return id
}

func (b *fb) storePlace(p mir.Place, v mir.ValueId) {
	b.emit(mir.Instr{Op: mir.OpStore, Place: p, StoreVal: v})
}

// constGet materializes a module constant.
func (b *fb) constGet(typ *Type, v mir.ConstValue) mir.ValueId {
	key := constKey(typ, v)
	name, ok := b.l.consts[key]
	if !ok {
		name = "lit." + constKindName(v.Kind) + ".c" + strconv.Itoa(b.l.constSeq)
		b.l.constSeq++
		b.l.consts[key] = name
		b.l.m.AddConst(name, b.l.ty(typ), v)
	}
	id := b.res(b.l.ty(typ))
	b.emit(mir.Instr{Op: mir.OpConstGet, Result: id, Const: name})
	return id
}

func constKindName(k mir.ConstKind) string {
	switch k {
	case mir.ConstUnit:
		return "unit"
	case mir.ConstBool:
		return "bool"
	case mir.ConstInt:
		return "int"
	case mir.ConstFloat:
		return "float"
	case mir.ConstString:
		return "str"
	}
	return "const"
}

func constKey(typ *Type, v mir.ConstValue) string {
	switch v.Kind {
	case mir.ConstInt:
		return fmt.Sprintf("int|%s|%d", typ.display(), v.Int)
	case mir.ConstBool:
		return fmt.Sprintf("bool|%v", v.Bool)
	case mir.ConstFloat:
		return fmt.Sprintf("float|%s|%s", typ.display(), strconv.FormatFloat(v.Float, 'g', -1, 64))
	case mir.ConstString:
		return fmt.Sprintf("str|%q", v.String)
	}
	return "unit"
}

// lowerFn lowers a checked function body.
func (l *lowerer) lowerFn(cf *checkedFn) error {
	f := l.m.Functions[l.fnID[cf]]
	b := l.newFB(f)
	b.ann = l.ann[cf]
	b.result = cf.result
	pi := 0
	for _, p := range cf.decl.Params {
		if p.Kind == paramType {
			continue
		}
		b.values[p.Name] = mir.ValueId(pi)
		pi++
	}
	b.start("bb0")
	if err := b.stmts(cf.decl.Body.Stmts); err != nil {
		return err
	}
	if !b.terminated {
		b.ret(mir.NoValue)
	}
	return nil
}

// stmts lowers a statement list. The checker guarantees no statements after
// a guaranteed return, so the block terminates exactly when the source did.
func (b *fb) stmts(list []Stmt) error {
	for _, s := range list {
		if b.terminated {
			break
		}
		if err := b.stmt(s); err != nil {
			return err
		}
	}
	return nil
}

// scopedStmts lowers a lexical block. Bindings are visible only in the
// block, and cleanup scopes opened by a normally-falling-through block are
// closed before control leaves it.
func (b *fb) scopedStmts(list []Stmt) (err error) {
	savedLocals, savedValues := b.locals, b.values
	savedScopes := append([]mir.ValueId(nil), b.scopes...)
	b.locals = cloneLocalIDs(savedLocals)
	b.values = cloneValueIDs(savedValues)
	defer func() {
		b.locals = savedLocals
		b.values = savedValues
		b.scopes = savedScopes
	}()
	if err = b.stmts(list); err != nil {
		return err
	}
	if !b.terminated {
		for i := len(b.scopes) - 1; i >= len(savedScopes); i-- {
			b.emit(mir.Instr{Op: mir.OpCleanupScopeRun, Scope: b.scopes[i]})
			b.emit(mir.Instr{Op: mir.OpCleanupScopeEnd, Scope: b.scopes[i]})
		}
	}
	return nil
}

func cloneLocalIDs(src map[string]mir.LocalId) map[string]mir.LocalId {
	dst := make(map[string]mir.LocalId, len(src))
	for name, id := range src {
		dst[name] = id
	}
	return dst
}

func cloneValueIDs(src map[string]mir.ValueId) map[string]mir.ValueId {
	dst := make(map[string]mir.ValueId, len(src))
	for name, id := range src {
		dst[name] = id
	}
	return dst
}

func (b *fb) stmt(s Stmt) error {
	switch st := s.(type) {
	case *Let:
		typ := b.ann[st.Value].typ
		local := b.f.AddLocal(b.localName(st.Name), b.l.ty(typ))
		b.locals[st.Name] = local
		v, err := b.expr(st.Value)
		if err != nil {
			return err
		}
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, v)
		return nil

	case *Assign:
		return b.stmtAssign(st)

	case *IfStmt:
		cond, err := b.expr(st.Cond)
		if err != nil {
			return err
		}
		then, _ := b.addBlock("bb_then", nil)
		els, _ := b.addBlock("bb_else", nil)
		join, _ := b.addBlock("bb_join", nil)
		b.branch(cond, blkID(b.f, then), blkID(b.f, els))
		b.setCur(then)
		if err := b.scopedStmts(st.Then.Stmts); err != nil {
			return err
		}
		thenTerminated := b.terminated
		if !thenTerminated {
			b.jump(blkID(b.f, join), nil)
		}
		b.setCur(els)
		if st.Else != nil {
			if err := b.scopedStmts(st.Else.Stmts); err != nil {
				return err
			}
		}
		elseTerminated := b.terminated
		if !elseTerminated {
			b.jump(blkID(b.f, join), nil)
		}
		if thenTerminated && elseTerminated {
			join.SetTerm(mir.Terminator{Kind: mir.TermUnreachable})
			b.cur = join
			b.terminated = true
			return nil
		}
		b.setCur(join)
		return nil

	case *WhileStmt:
		head, _ := b.addBlock("bb_head", nil)
		body, _ := b.addBlock("bb_body", nil)
		join, _ := b.addBlock("bb_join", nil)
		b.jump(blkID(b.f, head), nil)
		b.setCur(head)
		cond, err := b.expr(st.Cond)
		if err != nil {
			return err
		}
		b.branch(cond, blkID(b.f, body), blkID(b.f, join))
		b.setCur(body)
		if err := b.scopedStmts(st.Body.Stmts); err != nil {
			return err
		}
		if !b.terminated {
			b.jump(blkID(b.f, head), nil)
		}
		b.setCur(join)
		return nil

	case *ForStmt:
		seq, err := b.expr(st.Seq)
		if err != nil {
			return err
		}
		seqTy := b.ann[st.Seq].typ
		lenVal := b.res(mir.TypeU64)
		b.emit(mir.Instr{Op: mir.OpSliceLen, Result: lenVal, Slice: seq})
		zero := b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
		one := b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: 1})
		head, headParams := b.addBlock("bb_head", []mir.Param{{Name: "i", Type: mir.TypeU64}})
		body, _ := b.addBlock("bb_body", nil)
		join, _ := b.addBlock("bb_join", nil)
		b.jump(blkID(b.f, head), []mir.ValueId{zero})
		b.setCur(head)
		lt := b.res(mir.TypeBool)
		b.emit(mir.Instr{Op: mir.OpIntLt, Result: lt, A: headParams[0], B: lenVal})
		b.branch(lt, blkID(b.f, body), blkID(b.f, join))
		b.setCur(body)
		ref := b.res(b.l.m.SafeMut(b.l.ty(seqTy.elem)))
		b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: seq, Index: headParams[0], FailTarget: b.panicBlock()})
		elem := b.loadPlace(mir.Place{Kind: mir.PlaceDeref, Deref: ref}, b.l.ty(seqTy.elem))
		savedValues := b.values
		b.values = cloneValueIDs(savedValues)
		b.values[st.Name] = elem
		if err := b.scopedStmts(st.Body.Stmts); err != nil {
			b.values = savedValues
			return err
		}
		b.values = savedValues
		if !b.terminated {
			ni := b.res(mir.TypeU64)
			b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: ni, A: headParams[0], B: one, FailTarget: b.panicBlock()})
			b.jump(blkID(b.f, head), []mir.ValueId{ni})
		}
		b.setCur(join)
		return nil

	case *UsingStmt:
		v, err := b.expr(st.Value)
		if err != nil {
			return err
		}
		scope := b.res(b.l.m.CleanupScope())
		b.emit(mir.Instr{Op: mir.OpCleanupScopeBegin, Result: scope})
		id := b.res(b.l.m.CleanupID())
		b.emit(mir.Instr{Op: mir.OpCleanupPush, Result: id, Scope: scope, CleanupFn: b.l.fnID[b.l.fnByName[st.Cleanup]], CleanupArgs: []mir.ValueId{v}})
		b.scopes = append(b.scopes, scope)
		b.values[st.Name] = v
		return nil

	case *ReturnStmt:
		if st.Value == nil {
			b.ret(mir.NoValue)
			return nil
		}
		v, err := b.expr(st.Value)
		if err != nil {
			return err
		}
		b.ret(v)
		return nil

	case *ExprStmt:
		_, err := b.expr(st.X)
		return err

	case *Block:
		return b.scopedStmts(st.Stmts)
	}
	return nil
}

// stmtAssign lowers an assignment.
func (b *fb) stmtAssign(st *Assign) error {
	var ref mir.ValueId
	if st.Target.Index != nil {
		local := b.locals[st.Target.Name]
		base := b.loadPlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, b.f.Locals[local].Type)
		idx, err := b.expr(st.Target.Index)
		if err != nil {
			return err
		}
		ref = b.res(b.l.m.SafeMut(b.l.m.Types[b.f.Locals[local].Type].Elem))
		b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: base, Index: idx, FailTarget: b.panicBlock()})
	}
	value, err := b.expr(st.Value)
	if err != nil {
		return err
	}
	switch {
	case st.Target.Field != "" && st.Target.Index != nil:
		b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: st.Target.Field}, value)
	case st.Target.Field != "":
		b.storePlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: b.locals[st.Target.Name]}, Field: st.Target.Field}, value)
	case st.Target.Index != nil:
		b.storePlace(mir.Place{Kind: mir.PlaceDeref, Deref: ref}, value)
	default:
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: b.locals[st.Target.Name]}, value)
	}
	return nil
}

// expr lowers an rvalue expression and returns its value.
func (b *fb) expr(e Expr) (mir.ValueId, error) {
	switch x := e.(type) {
	case *UnsafeC:
		return b.expr(x.Call)
	case *IntLit:
		typ := b.ann[e].typ
		return b.constGet(typ, mir.ConstValue{Kind: mir.ConstInt, Int: x.Value}), nil

	case *FloatLit:
		typ := b.ann[e].typ
		return b.constGet(typ, mir.ConstValue{Kind: mir.ConstFloat, Float: x.Value}), nil

	case *StrLit:
		typ := b.ann[e].typ
		return b.constGet(typ, mir.ConstValue{Kind: mir.ConstString, String: x.Value}), nil

	case *BoolLit:
		return b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: x.Value}), nil

	case *Ident:
		if local, ok := b.locals[x.Name]; ok {
			return b.loadPlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, b.f.Locals[local].Type), nil
		}
		if v, ok := b.values[x.Name]; ok {
			return v, nil
		}
		if ai, ok := b.ann[e]; ok && ai.call != nil && ai.call.kind == callVariant {
			enumTy := b.l.ty(ai.call.enumType)
			id := b.res(enumTy)
			b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: id, TypeOp: enumTy, Variant: mirVariantName(ai.call.variant.name, ai.call.enumType)})
			return id, nil
		}
		return 0, diag(x.P, "internal: unbound name %q at lowering", x.Name)

	case *Unary:
		if x.Op == "!" {
			v, err := b.expr(x.X)
			if err != nil {
				return 0, err
			}
			join, params := b.addBlock("bb_join", []mir.Param{{Name: "r", Type: mir.TypeBool}})
			tt, _ := b.addBlock("bb_true", nil)
			ff, _ := b.addBlock("bb_false", nil)
			b.branch(v, blkID(b.f, ff), blkID(b.f, tt))
			b.setCur(tt)
			tv := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: true})
			b.jump(blkID(b.f, join), []mir.ValueId{tv})
			b.setCur(ff)
			fv := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: false})
			b.jump(blkID(b.f, join), []mir.ValueId{fv})
			b.setCur(join)
			return params[0], nil
		}
		if il, ok := x.X.(*IntLit); ok && il.Value == -9223372036854775808 {
			typ := b.ann[e].typ
			return b.constGet(typ, mir.ConstValue{Kind: mir.ConstInt, Int: il.Value}), nil
		}
		v, err := b.expr(x.X)
		if err != nil {
			return 0, err
		}
		typ := b.ann[e].typ
		zero := b.constGet(typ, mir.ConstValue{Kind: mir.ConstInt, Int: 0})
		id := b.res(b.l.ty(typ))
		b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: id, A: zero, B: v, FailTarget: b.panicBlock()})
		return id, nil

	case *Binary:
		return b.binary(x)

	case *Field:
		if p, ok := b.place(x); ok {
			return b.loadPlace(p, b.l.ty(b.ann[e].typ)), nil
		}
		if idx, ok := x.Base.(*Index); ok {
			ref, err := b.indexRef(idx)
			if err != nil {
				return 0, err
			}
			return b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceDeref, Deref: ref}, Field: x.Name}, b.l.ty(b.ann[e].typ)), nil
		}
		base, err := b.expr(x.Base)
		if err != nil {
			return 0, err
		}
		baseTy := b.ann[x.Base].typ
		local := b.f.AddLocal(b.localName("tmp"), b.l.ty(baseTy))
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, base)
		return b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: local}, Field: x.Name}, b.l.ty(b.ann[e].typ)), nil

	case *Index:
		ref, err := b.indexRef(x)
		if err != nil {
			return 0, err
		}
		return b.loadPlace(mir.Place{Kind: mir.PlaceDeref, Deref: ref}, b.l.ty(b.ann[e].typ)), nil

	case *Call:
		return b.call(x)

	case *Match:
		return b.match(x)

	case *Try:
		r, err := b.expr(x.X)
		if err != nil {
			return 0, err
		}
		resTy := b.ann[x.X].typ
		switchBlk := b.cur
		switchID := blkID(b.f, switchBlk)
		errBlk, _ := b.addBlock("bb_err", nil)
		okBlk, _ := b.addBlock("bb_ok", nil)
		errBinding := b.f.AddValue(b.valueName("v"), b.l.ty(resTy.err), mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: switchID, Case: 0})
		okBinding := b.f.AddValue(b.valueName("v"), b.l.ty(resTy.ok), mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: switchID, Case: 1})
		cases := []mir.SwitchCase{
			{Variant: "err", Binding: errBinding, Target: blkID(b.f, errBlk)},
			{Variant: "ok", Binding: okBinding, Target: blkID(b.f, okBlk)},
		}
		switchBlk.SetTerm(mir.Terminator{Kind: mir.TermSwitch, Value: r, Cases: cases})
		b.setCur(errBlk)
		fnRes := b.l.ty(b.result)
		errVal := b.res(fnRes)
		b.emit(mir.Instr{Op: mir.OpEnumConstruct, Result: errVal, TypeOp: fnRes, Variant: "err", Payload: errBinding})
		b.fail(errVal)
		b.setCur(okBlk)
		return okBinding, nil
	}
	return 0, diag(e.exprPos(), "internal: invalid expression at lowering")
}

// place returns the storage place of an Ident/Field expression rooted at a
// local; ok=false when the expression denotes a value.
func (b *fb) place(e Expr) (mir.Place, bool) {
	switch x := e.(type) {
	case *Ident:
		local, ok := b.locals[x.Name]
		if !ok {
			return mir.Place{}, false
		}
		return mir.Place{Kind: mir.PlaceLocal, Local: local}, true
	case *Field:
		base, ok := b.place(x.Base)
		if !ok {
			return mir.Place{}, false
		}
		return mir.Place{Kind: mir.PlaceField, Base: &base, Field: x.Name}, true
	}
	return mir.Place{}, false
}

// indexRef lowers base[index] to a checked safe_mut element reference.
func (b *fb) indexRef(x *Index) (mir.ValueId, error) {
	base, err := b.expr(x.Base)
	if err != nil {
		return 0, err
	}
	idx, err := b.expr(x.Index)
	if err != nil {
		return 0, err
	}
	baseTy := b.ann[x.Base].typ
	ref := b.res(b.l.m.SafeMut(b.l.ty(baseTy.elem)))
	b.emit(mir.Instr{Op: mir.OpSliceIndexChecked, Result: ref, Slice: base, Index: idx, FailTarget: b.panicBlock()})
	return ref, nil
}

func (b *fb) binary(x *Binary) (mir.ValueId, error) {
	if x.Op == "&&" || x.Op == "||" {
		a, err := b.expr(x.X)
		if err != nil {
			return 0, err
		}
		bbR, _ := b.addBlock("bb_r", nil)
		bbF, _ := b.addBlock("bb_f", nil)
		join, params := b.addBlock("bb_join", []mir.Param{{Name: "r", Type: mir.TypeBool}})
		b.branch(a, blkID(b.f, bbR), blkID(b.f, bbF))
		b.setCur(bbR)
		if x.Op == "&&" {
			bv, err := b.expr(x.Y)
			if err != nil {
				return 0, err
			}
			b.jump(blkID(b.f, join), []mir.ValueId{bv})
			b.setCur(bbF)
			fv := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: false})
			b.jump(blkID(b.f, join), []mir.ValueId{fv})
		} else {
			tv := b.constGet(prim(pBool), mir.ConstValue{Kind: mir.ConstBool, Bool: true})
			b.jump(blkID(b.f, join), []mir.ValueId{tv})
			b.setCur(bbF)
			bv, err := b.expr(x.Y)
			if err != nil {
				return 0, err
			}
			b.jump(blkID(b.f, join), []mir.ValueId{bv})
		}
		b.setCur(join)
		return params[0], nil
	}
	a, err := b.expr(x.X)
	if err != nil {
		return 0, err
	}
	typ := b.ann[x].typ
	bv, err := b.expr(x.Y)
	if err != nil {
		return 0, err
	}
	if isCmpOp(x.Op) {
		id := b.res(mir.TypeBool)
		b.emit(mir.Instr{Op: cmpMirOp(x.Op, typ), Result: id, A: a, B: bv})
		return id, nil
	}
	if x.Op == "%" {
		q := b.res(b.l.ty(typ))
		b.emit(mir.Instr{Op: mir.OpIntDivChecked, Result: q, A: a, B: bv, FailTarget: b.panicBlock()})
		p := b.res(b.l.ty(typ))
		b.emit(mir.Instr{Op: mir.OpIntMulChecked, Result: p, A: q, B: bv, FailTarget: b.panicBlock()})
		r := b.res(b.l.ty(typ))
		b.emit(mir.Instr{Op: mir.OpIntSubChecked, Result: r, A: a, B: p, FailTarget: b.panicBlock()})
		return r, nil
	}
	id := b.res(b.l.ty(typ))
	b.emit(mir.Instr{Op: arithMirOp(x.Op), Result: id, A: a, B: bv, FailTarget: b.panicBlock()})
	return id, nil
}

func isCmpOp(op string) bool {
	switch op {
	case "==", "!=", "<", "<=", ">", ">=":
		return true
	}
	return false
}

func cmpMirOp(op string, typ *Type) mir.OpKind {
	prefix := mir.OpIntEq
	if typ.isFloat() {
		prefix = mir.OpFloatEq
	}
	switch op {
	case "==":
		return prefix
	case "!=":
		return prefix + 1
	case "<":
		return prefix + 2
	case "<=":
		return prefix + 3
	case ">":
		return prefix + 4
	}
	return prefix + 5
}

func arithMirOp(op string) mir.OpKind {
	switch op {
	case "+":
		return mir.OpIntAddChecked
	case "-":
		return mir.OpIntSubChecked
	case "*":
		return mir.OpIntMulChecked
	case "/":
		return mir.OpIntDivChecked
	case "<<":
		return mir.OpIntShlChecked
	}
	return mir.OpIntShrChecked
}

// mirVariantName maps a source variant name to the MIR variant name.
func mirVariantName(name string, enumType *Type) string {
	if enumType.kind == tOption || enumType.kind == tResult {
		return strings.ToLower(name)
	}
	return name
}

// call lowers a resolved call.
func (b *fb) call(x *Call) (mir.ValueId, error) {
	ai := b.ann[x].call
	switch ai.kind {
	case callUser:
		// The leading explicit type arguments are compile-time; only the
		// runtime arguments are lowered.
		runtime := x.Args[ai.explicitArgs:]
		args := make([]mir.ValueId, 0, len(runtime))
		for _, a := range runtime {
			v, err := b.expr(a)
			if err != nil {
				return 0, err
			}
			args = append(args, v)
		}
		resTy := b.l.ty(ai.fn.result)
		if resTy == mir.TypeUnit {
			b.emit(mir.Instr{Op: mir.OpCall, Result: mir.NoValue, Callee: b.l.fnID[ai.fn], Args: args})
			return mir.NoValue, nil
		}
		id := b.res(resTy)
		b.emit(mir.Instr{Op: mir.OpCall, Result: id, Callee: b.l.fnID[ai.fn], Args: args})
		return id, nil

	case callImport:
		impID, _ := b.l.m.Import(ai.importName)
		args := make([]mir.ValueId, 0, len(x.Args))
		for _, a := range x.Args {
			v, err := b.expr(a)
			if err != nil {
				return 0, err
			}
			args = append(args, v)
		}
		resTy := b.l.m.Imports[impID].Sig.Result
		if resTy == mir.TypeUnit {
			b.emit(mir.Instr{Op: mir.OpFFICallUnsafe, Result: mir.NoValue, FFIImport: impID, Args: args})
			return mir.NoValue, nil
		}
		id := b.res(resTy)
		b.emit(mir.Instr{Op: mir.OpFFICallUnsafe, Result: id, FFIImport: impID, Args: args})
		return id, nil

	case callStruct:
		fields := make([]mir.AggField, 0, len(ai.orderedArgs))
		for i, a := range ai.orderedArgs {
			v, err := b.expr(a)
			if err != nil {
				return 0, err
			}
			fields = append(fields, mir.AggField{Name: ai.ctorType.decl.decl.Fields[i].Name, Value: v})
		}
		id := b.res(b.l.ty(ai.ctorType))
		b.emit(mir.Instr{Op: mir.OpAggregateConstruct, Result: id, AggType: b.l.ty(ai.ctorType), AggFields: fields})
		return id, nil

	case callMap:
		d, err := b.expr(ai.orderedArgs[0])
		if err != nil {
			return 0, err
		}
		h := b.l.mapHelpersFor(ai.ctorType)
		id := b.res(b.l.ty(ai.ctorType))
		b.emit(mir.Instr{Op: mir.OpCall, Result: id, Callee: h.makeID, Args: []mir.ValueId{d}})
		return id, nil

	case callVariant:
		enumTy := b.l.ty(ai.enumType)
		in := mir.Instr{Op: mir.OpEnumConstruct, TypeOp: enumTy, Variant: mirVariantName(ai.variant.name, ai.enumType)}
		if ai.variant.payload != nil {
			pv, err := b.expr(x.Args[0])
			if err != nil {
				return 0, err
			}
			in.Payload = pv
		}
		id := b.res(enumTy)
		in.Result = id
		b.emit(in)
		return id, nil

	case callBuiltin:
		return b.builtinCall(x, ai.builtin)
	}
	return 0, diag(x.P, "internal: unresolved call at lowering")
}

// builtinCall lowers a builtin call. Alloc and Push skip their compile-time
// operands (the element type and the cleanup function name), which are not
// value expressions.
func (b *fb) builtinCall(x *Call, name string) (mir.ValueId, error) {
	var exprArgs []Expr
	if name == "__s0_alloc" {
		exprArgs = []Expr{x.Args[1], x.Args[2]}
	} else if strings.HasPrefix(name, "__s0_buffer_") {
		exprArgs = x.Args[1:]
	} else if name == "Push" {
		exprArgs = append([]Expr{x.Args[0]}, x.Args[2:]...)
	} else {
		exprArgs = x.Args
	}
	args := make([]mir.ValueId, 0, len(exprArgs))
	for _, a := range exprArgs {
		v, err := b.expr(a)
		if err != nil {
			return 0, err
		}
		args = append(args, v)
	}
	switch name {
	case "len":
		id := b.res(mir.TypeU64)
		b.emit(mir.Instr{Op: mir.OpSliceLen, Result: id, Slice: args[0]})
		return id, nil
	case "range":
		id := b.res(b.l.ty(b.ann[x].typ))
		b.emit(mir.Instr{Op: mir.OpSliceRangeChecked, Result: id, Slice: args[0], Lo: args[1], Hi: args[2], FailTarget: b.panicBlock()})
		return id, nil
	case "__s0_alloc":
		elemTy := b.ann[x].typ.elem
		id := b.res(b.l.m.SafeMut(b.l.ty(elemTy)))
		b.emit(mir.Instr{Op: mir.OpAlloc, Result: id, Domain: args[0], Count: args[1], TypeOp: b.l.ty(elemTy)})
		return id, nil
	case "__s0_buffer_new", "__s0_buffer_len", "__s0_buffer_append", "__s0_buffer_get", "__s0_buffer_set", "__s0_buffer_slice":
		var bt *Type
		switch name {
		case "__s0_buffer_new":
			bt = b.ann[x].typ.ok
		case "__s0_buffer_append":
			bt = b.ann[x.Args[2]].typ
		default:
			bt = b.ann[x.Args[1]].typ
		}
		if bt == nil || bt.kind != tBuffer {
			return mir.NoValue, fmt.Errorf("internal: %s has no concrete buffer type", name)
		}
		h := b.l.bufferHelpersFor(bt)
		callee := map[string]mir.FunctionId{"__s0_buffer_new": h.newID, "__s0_buffer_len": h.lenID, "__s0_buffer_append": h.appendID, "__s0_buffer_get": h.getID, "__s0_buffer_set": h.setID, "__s0_buffer_slice": h.sliceID}[name]
		if b.l.m.Functions[callee].Result == mir.TypeUnit {
			b.emit(mir.Instr{Op: mir.OpCall, Result: mir.NoValue, Callee: callee, Args: args})
			return mir.NoValue, nil
		}
		id := b.res(b.l.m.Functions[callee].Result)
		b.emit(mir.Instr{Op: mir.OpCall, Result: id, Callee: callee, Args: args})
		return id, nil
	case "__s0_domain_create":
		id := b.res(b.l.m.DomainHandle())
		b.emit(mir.Instr{Op: mir.OpDomainCreate, Result: id, Domain: args[0]})
		return id, nil
	case "__s0_domain_mark":
		id := b.res(b.l.m.DomainMark())
		b.emit(mir.Instr{Op: mir.OpDomainMark, Result: id, Domain: args[0]})
		return id, nil
	case "__s0_domain_reset":
		b.emit(mir.Instr{Op: mir.OpDomainReset, Domain: args[0], Mark: args[1]})
		return mir.NoValue, nil
	case "__s0_domain_destroy":
		b.emit(mir.Instr{Op: mir.OpDomainDestroy, Domain: args[0]})
		return mir.NoValue, nil
	case "Scope":
		id := b.res(b.l.m.CleanupScope())
		b.emit(mir.Instr{Op: mir.OpCleanupScopeBegin, Result: id})
		return id, nil
	case "Push":
		head := callHead(x.Args[1])
		cf := b.l.fnByName[head.name]
		id := b.res(b.l.m.CleanupID())
		b.emit(mir.Instr{Op: mir.OpCleanupPush, Result: id, Scope: args[0], CleanupFn: b.l.fnID[cf], CleanupArgs: args[2:]})
		return id, nil
	case "Disarm":
		b.emit(mir.Instr{Op: mir.OpCleanupDisarm, CleanupID: args[0]})
		return mir.NoValue, nil
	case "Run":
		b.emit(mir.Instr{Op: mir.OpCleanupScopeRun, Scope: args[0]})
		return mir.NoValue, nil
	case "End":
		b.emit(mir.Instr{Op: mir.OpCleanupScopeEnd, Scope: args[0]})
		return mir.NoValue, nil
	case "Get", "Set", "Remove":
		mapTy := b.ann[x.Args[0]].typ
		h := b.l.mapHelpersFor(mapTy)
		var callee mir.FunctionId
		switch name {
		case "Get":
			callee = h.getID
		case "Set":
			callee = h.setID
		case "Remove":
			callee = h.removeID
		}
		resTy := b.l.m.Functions[callee].Result
		if name == "Set" {
			inserted := b.res(mir.TypeBool)
			b.emit(mir.Instr{Op: mir.OpCall, Result: inserted, Callee: callee, Args: args})
			ok, _ := b.addBlock("bb_map_set_ok", nil)
			b.branch(inserted, blkID(b.f, ok), b.panicBlock())
			b.setCur(ok)
			return mir.NoValue, nil
		}
		if resTy == mir.TypeUnit {
			b.emit(mir.Instr{Op: mir.OpCall, Result: mir.NoValue, Callee: callee, Args: args})
			return mir.NoValue, nil
		}
		id := b.res(resTy)
		b.emit(mir.Instr{Op: mir.OpCall, Result: id, Callee: callee, Args: args})
		return id, nil
	}
	return 0, diag(x.P, "internal: unknown builtin %q at lowering", name)
}

// match lowers a match expression to a switch and a join block.
func (b *fb) match(x *Match) (mir.ValueId, error) {
	v, err := b.expr(x.Value)
	if err != nil {
		return 0, err
	}
	enumTy := b.ann[x.Value].typ
	resTy := b.ann[x].typ
	switchBlk := b.cur
	switchID := blkID(b.f, switchBlk)
	join, joinParams := b.addBlock("bb_join", []mir.Param{{Name: "r", Type: b.l.ty(resTy)}})
	cases := make([]mir.SwitchCase, 0, len(x.Arms))
	armBlocks := make([]*mir.Block, 0, len(x.Arms))
	for i, arm := range x.Arms {
		blk, _ := b.addBlock("bb_arm"+strconv.Itoa(i), nil)
		armBlocks = append(armBlocks, blk)
		c := mir.SwitchCase{Target: blkID(b.f, blk), Binding: mir.NoValue}
		if arm.Variant != "" {
			c.Variant = mirVariantName(arm.Variant, enumTy)
			if pv := enumTy.variantByName(arm.Variant); pv != nil && pv.payload != nil {
				bid := b.f.AddValue(b.valueName(arm.Bind), b.l.ty(substType(pv.payload, structBindings(enumTy))), mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: switchID, Case: len(cases)})
				c.Binding = bid
			}
		}
		cases = append(cases, c)
	}
	switchBlk.SetTerm(mir.Terminator{Kind: mir.TermSwitch, Value: v, Cases: cases})
	for i, arm := range x.Arms {
		b.setCur(armBlocks[i])
		saved := b.scopes
		savedValues := b.values
		b.values = cloneValueIDs(savedValues)
		if arm.Variant != "" {
			if pv := enumTy.variantByName(arm.Variant); pv != nil && pv.payload != nil {
				b.values[arm.Bind] = cases[i].Binding
			}
		}
		av, err := b.expr(arm.Body)
		if err != nil {
			b.values = savedValues
			return 0, err
		}
		b.jump(blkID(b.f, join), []mir.ValueId{av})
		b.scopes = saved
		b.values = savedValues
	}
	b.setCur(join)
	return joinParams[0], nil
}

// hashValue lowers a structural hash of a map key to a u64 value.
func (b *fb) hashValue(v mir.ValueId, t *Type) mir.ValueId {
	switch t.kind {
	case tPrim:
		switch t.prim {
		case pU64:
			return v
		case pU8, pU16, pU32:
			id := b.res(mir.TypeU64)
			b.emit(mir.Instr{Op: mir.OpIntZext, Result: id, A: v, TypeOp: mir.TypeU64})
			return id
		case pBool:
			return b.boolHash(v)
		}
		return v
	case tStruct:
		local := b.f.AddLocal(b.localName("k"), b.l.ty(t))
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: local}, v)
		var acc mir.ValueId = mir.NoValue
		for i, f := range t.decl.fields {
			ft := substType(f, structBindings(t))
			fv := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: local}, Field: t.decl.decl.Fields[i].Name}, b.l.ty(ft))
			h := b.hashValue(fv, ft)
			if acc == mir.NoValue {
				acc = h
				continue
			}
			id := b.res(mir.TypeU64)
			b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: id, A: acc, B: h, FailTarget: b.panicBlock()})
			acc = id
		}
		if acc == mir.NoValue {
			// An empty struct key hashes to zero.
			return b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
		}
		return acc
	case tEnum:
		return b.enumHash(v, t)
	}
	return v
}

func (b *fb) boolHash(v mir.ValueId) mir.ValueId {
	one := b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: 1})
	zero := b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: 0})
	join, params := b.addBlock("bb_join", []mir.Param{{Name: "h", Type: mir.TypeU64}})
	bb1, _ := b.addBlock("bb_one", nil)
	bb0, _ := b.addBlock("bb_zero", nil)
	b.branch(v, blkID(b.f, bb1), blkID(b.f, bb0))
	b.setCur(bb1)
	b.jump(blkID(b.f, join), []mir.ValueId{one})
	b.setCur(bb0)
	b.jump(blkID(b.f, join), []mir.ValueId{zero})
	b.setCur(join)
	return params[0]
}

func (b *fb) enumHash(v mir.ValueId, t *Type) mir.ValueId {
	switchBlk := b.cur
	switchID := blkID(b.f, switchBlk)
	join, params := b.addBlock("bb_join", []mir.Param{{Name: "h", Type: mir.TypeU64}})
	cases := make([]mir.SwitchCase, 0, len(t.decl.variants))
	blocks := make([]*mir.Block, 0, len(t.decl.variants))
	for i, vt := range t.decl.variants {
		blk, _ := b.addBlock("bb_v"+strconv.Itoa(i), nil)
		blocks = append(blocks, blk)
		c := mir.SwitchCase{Variant: vt.name, Target: blkID(b.f, blk), Binding: mir.NoValue}
		if vt.payload != nil {
			bid := b.f.AddValue(b.valueName("p"), b.l.ty(substType(vt.payload, structBindings(t))), mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: switchID, Case: i})
			c.Binding = bid
		}
		cases = append(cases, c)
	}
	switchBlk.SetTerm(mir.Terminator{Kind: mir.TermSwitch, Value: v, Cases: cases})
	for i, vt := range t.decl.variants {
		b.setCur(blocks[i])
		idx := b.constGet(prim(pU64), mir.ConstValue{Kind: mir.ConstInt, Int: int64(i)})
		h := idx
		if vt.payload != nil {
			pt := substType(vt.payload, structBindings(t))
			pv := b.hashValue(cases[i].Binding, pt)
			id := b.res(mir.TypeU64)
			b.emit(mir.Instr{Op: mir.OpIntAddChecked, Result: id, A: h, B: pv, FailTarget: b.panicBlock()})
			h = id
		}
		b.jump(blkID(b.f, join), []mir.ValueId{h})
	}
	b.setCur(join)
	return params[0]
}

// emitEq lowers a structural equality comparison by branching to trueBlk on
// equality and falseBlk otherwise. It returns no value, so the generated
// code never references a later block's parameter from an earlier block,
// which the current MIR text format cannot express.
func (b *fb) emitEq(a, bv mir.ValueId, t *Type, trueBlk, falseBlk mir.BlockId) {
	switch t.kind {
	case tPrim:
		if t.prim == pBool {
			b.emitBoolCmp(a, bv, trueBlk, falseBlk)
			return
		}
		id := b.res(mir.TypeBool)
		b.emit(mir.Instr{Op: mir.OpIntEq, Result: id, A: a, B: bv})
		b.branch(id, trueBlk, falseBlk)
	case tStruct:
		la := b.f.AddLocal(b.localName("a"), b.l.ty(t))
		lb := b.f.AddLocal(b.localName("b"), b.l.ty(t))
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: la}, a)
		b.storePlace(mir.Place{Kind: mir.PlaceLocal, Local: lb}, bv)
		for i, f := range t.decl.fields {
			ft := substType(f, structBindings(t))
			fa := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: la}, Field: t.decl.decl.Fields[i].Name}, b.l.ty(ft))
			fb := b.loadPlace(mir.Place{Kind: mir.PlaceField, Base: &mir.Place{Kind: mir.PlaceLocal, Local: lb}, Field: t.decl.decl.Fields[i].Name}, b.l.ty(ft))
			next, _ := b.addBlock("bb_c"+strconv.Itoa(i+1), nil)
			b.emitEq(fa, fb, ft, blkID(b.f, next), falseBlk)
			b.setCur(next)
		}
		b.jump(trueBlk, nil)
	case tEnum:
		b.emitEnumEq(a, bv, t, trueBlk, falseBlk)
	}
}

// emitBoolCmp compares two bool values by branching.
func (b *fb) emitBoolCmp(a, bv mir.ValueId, trueBlk, falseBlk mir.BlockId) {
	at, _ := b.addBlock("bb_at", nil)
	af, _ := b.addBlock("bb_af", nil)
	b.branch(a, blkID(b.f, at), blkID(b.f, af))
	tt, _ := b.addBlock("bb_tt", nil)
	tf, _ := b.addBlock("bb_tf", nil)
	b.setCur(at)
	b.branch(bv, blkID(b.f, tt), blkID(b.f, tf))
	ft, _ := b.addBlock("bb_ft", nil)
	ff, _ := b.addBlock("bb_ff", nil)
	b.setCur(af)
	b.branch(bv, blkID(b.f, ft), blkID(b.f, ff))
	b.setCur(tt)
	b.jump(trueBlk, nil)
	b.setCur(tf)
	b.jump(falseBlk, nil)
	b.setCur(ft)
	b.jump(falseBlk, nil)
	b.setCur(ff)
	b.jump(trueBlk, nil)
}

// emitEnumEq compares two enum values by branching.
func (b *fb) emitEnumEq(a, bv mir.ValueId, t *Type, trueBlk, falseBlk mir.BlockId) {
	switchBlk := b.cur
	switchID := blkID(b.f, switchBlk)
	cases := make([]mir.SwitchCase, 0, len(t.decl.variants))
	blocks := make([]*mir.Block, 0, len(t.decl.variants))
	for i, vt := range t.decl.variants {
		blk, _ := b.addBlock("bb_v"+strconv.Itoa(i), nil)
		blocks = append(blocks, blk)
		c := mir.SwitchCase{Variant: vt.name, Target: blkID(b.f, blk), Binding: mir.NoValue}
		if vt.payload != nil {
			bid := b.f.AddValue(b.valueName("p"), b.l.ty(substType(vt.payload, structBindings(t))), mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: switchID, Case: i})
			c.Binding = bid
		}
		cases = append(cases, c)
	}
	switchBlk.SetTerm(mir.Terminator{Kind: mir.TermSwitch, Value: a, Cases: cases})
	for i, vt := range t.decl.variants {
		b.setCur(blocks[i])
		innerSwitchID := blkID(b.f, blocks[i])
		cmpBlk, _ := b.addBlock("bb_cmp", nil)
		bc := mir.SwitchCase{Variant: vt.name, Target: blkID(b.f, cmpBlk), Binding: mir.NoValue}
		if vt.payload != nil {
			bid := b.f.AddValue(b.valueName("q"), b.l.ty(substType(vt.payload, structBindings(t))), mir.ValueDef{Kind: mir.ValueDefSwitchCase, Block: innerSwitchID, Case: 0})
			bc.Binding = bid
		}
		bs := []mir.SwitchCase{bc, {Target: falseBlk, Binding: mir.NoValue}}
		blocks[i].SetTerm(mir.Terminator{Kind: mir.TermSwitch, Value: bv, Cases: bs})
		b.setCur(cmpBlk)
		if vt.payload != nil {
			pt := substType(vt.payload, structBindings(t))
			b.emitEq(cases[i].Binding, bs[0].Binding, pt, trueBlk, falseBlk)
		} else {
			b.jump(trueBlk, nil)
		}
	}
}
