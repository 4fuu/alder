// Package cgen lowers verified Alder MIR to deterministic, portable C11.
//
// The backend accepts only verified modules: Generate runs the full verifier
// and refuses to lower invalid input rather than silently repairing it. All
// output derives from declaration and ID order; it never depends on Go map
// iteration, host addresses, or absolute paths.
//
// Lowering policy (details in docs/c-backend.md):
//   - every non-unit MIR value becomes one C variable; unit is erased, and
//     block-parameter edges use typed temporaries before assigning their
//     destinations, which gives deterministic parallel-copy phi lowering;
//   - side effects are sequenced as explicit statements; call arguments are
//     reads of already-computed variables, so their unspecified C evaluation
//     order is unobservable;
//   - checked operations fail by branching to their explicit MIR failure
//     edge; unchecked runtime failures (allocation failure, identity
//     exhaustion, unreachable execution, rejected float narrowing, or
//     out-of-range float-to-int conversion) terminate via alder_runtime_panic
//     with a documented message;
//   - narrow integer operations promote to 64 bits and range-check; narrow
//     shifts check against the source width and compute at that width.
package cgen

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// ProgramEntryError reports that a verified MIR module does not have the
// temporary Stage 0 entry shape required by GenerateProgram.
type ProgramEntryError struct {
	Reason string
}

func (e *ProgramEntryError) Error() string { return "cgen: invalid program entry: " + e.Reason }

// IsProgramEntryError reports whether err is a GenerateProgram entry error.
func IsProgramEntryError(err error) bool {
	var target *ProgramEntryError
	return errors.As(err, &target)
}

// Generate lowers a verified module to a single C11 translation unit.
func Generate(m *mir.Module) (string, error) {
	if err := verifyInput(m); err != nil {
		return "", err
	}
	return generate(m, mir.NoFunction, false)
}

// GenerateProgram lowers a verified module and adds the single stable entry
// point consumed by the separate bootstrap host shim.
func GenerateProgram(m *mir.Module) (string, error) {
	if err := verifyInput(m); err != nil {
		return "", err
	}
	return generateProgram(m)
}

// GenerateProgramTrusted lowers a module the caller already ran through
// verify.Module. Public GenerateProgram remains the verified-only gate.
func GenerateProgramTrusted(m *mir.Module) (string, error) {
	if m == nil {
		return "", fmt.Errorf("cgen: nil module")
	}
	return generateProgram(m)
}

func generateProgram(m *mir.Module) (string, error) {
	mainID := mir.NoFunction
	for i, f := range m.Functions {
		if f != nil && f.Name == "main" {
			if mainID != mir.NoFunction {
				return "", &ProgramEntryError{Reason: "multiple functions named main"}
			}
			mainID = mir.FunctionId(i)
		}
	}
	if mainID == mir.NoFunction {
		return "", &ProgramEntryError{Reason: "missing function named main"}
	}
	f := m.Functions[mainID]
	if f.Result != mir.TypeI32 {
		return "", &ProgramEntryError{Reason: "main must return i32"}
	}
	if len(f.Params) > 1 || (len(f.Params) == 1 && (!m.ValidType(f.Params[0].Type) || m.Types[f.Params[0].Type].Kind != mir.TypeDomainHandle)) {
		return "", &ProgramEntryError{Reason: "main must take no parameters or one domain_handle parameter"}
	}
	return generate(m, mainID, true)
}

func verifyInput(m *mir.Module) error {
	if m == nil {
		return fmt.Errorf("cgen: nil module")
	}
	if errs := verify.Module(m); len(errs) > 0 {
		return fmt.Errorf("cgen: module failed verification:\n%s", verify.Errors(errs).String())
	}
	return nil
}

func generate(m *mir.Module, mainID mir.FunctionId, program bool) (string, error) {
	g := &gen{m: m, program: program, mainID: mainID}
	if err := g.analyze(); err != nil {
		return "", err
	}
	var b strings.Builder
	g.emitModule(&b)
	return b.String(), nil
}

// gen carries the module and the per-function lowering state.
type gen struct {
	m       *mir.Module
	program bool
	mainID  mir.FunctionId

	// Module-wide analysis results.
	copyTypes []mir.TypeId   // types needing copy helpers, dependencies first
	pushSites map[[3]int]int // cleanup.push site -> ctx/adapter index
	nextCtx   int            // module-wide ctx/adapter counter
	strConsts map[string]int // string constant name -> static array index
	fnValues  [][3]int       // (function id, function type id, domain marker) fn.value wrappers, first occurrence order

	// Per-function lowering state.
	f           *mir.Function
	paramValues map[[2]int]mir.ValueId // (block, param) -> value id
	domainUsed  int                    // running domain slot counter
	scopeUsed   int                    // running scope slot counter
	edgeUsed    int                    // running edge-temporary counter
	domainTotal map[int]int            // domain.create sites per function
	scopeTotal  map[int]int            // cleanup.scope.begin sites per function
	valueRead   []bool
	localRead   []bool
}

// analyze precomputes everything that must be consistent between the
// declarations and the instruction lowering, and rejects constructs the M3
// backend cannot represent honestly.
func (g *gen) analyze() error {
	g.pushSites = make(map[[3]int]int)
	g.strConsts = make(map[string]int)
	g.domainTotal = make(map[int]int)
	g.scopeTotal = make(map[int]int)
	var copySet map[mir.TypeId]bool

	for fi, f := range g.m.Functions {
		if f == nil {
			continue
		}
		for bi, b := range f.Blocks {
			if b == nil {
				continue
			}
			for ii := range b.Instrs {
				in := &b.Instrs[ii]
				switch in.Op {
				case mir.OpCleanupPush:
					g.pushSites[[3]int{fi, bi, ii}] = g.nextCtx
					g.nextCtx++
				case mir.OpDomainCreate:
					g.domainTotal[fi]++
				case mir.OpCleanupScopeBegin:
					g.scopeTotal[fi]++
				case mir.OpCopyToDomain:
					t, ok := f.ValueType(in.CopyVal)
					if !ok {
						continue
					}
					if g.copyTrivial(t) {
						continue
					}
					if err := g.requireCopyable(t); err != nil {
						return err
					}
					if copySet == nil {
						copySet = make(map[mir.TypeId]bool)
					}
					g.collectCopyTypes(t, copySet)
				case mir.OpFnValue:
					// The environment retain hook deep-copies a
					// storage-bearing capture through its per-type copy
					// helper, so those helpers must exist even when no
					// copy_to_domain instruction names the type.
					if t := g.fnEnvAggregate(f, in.A); t != 0 {
						for _, fld := range g.m.Types[t].Fields {
							if !g.m.ValidType(fld.Type) || g.copyTrivial(fld.Type) {
								continue
							}
							switch g.m.Types[fld.Type].Kind {
							case mir.TypeDomainHandle, mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
								continue
							}
							if err := g.requireCopyable(fld.Type); err != nil {
								return err
							}
							if copySet == nil {
								copySet = make(map[mir.TypeId]bool)
							}
							g.collectCopyTypes(fld.Type, copySet)
						}
					}
				case mir.OpVecGrowChecked:
					t, ok := f.ValueType(in.Slice)
					if !ok || !g.m.ValidType(t) {
						continue
					}
					elem := g.m.Types[t].Elem
					if g.copyTrivial(elem) {
						continue
					}
					if err := g.requireCopyable(elem); err != nil {
						return err
					}
					if copySet == nil {
						copySet = make(map[mir.TypeId]bool)
					}
					g.collectCopyTypes(elem, copySet)
				case mir.OpTableInsert, mir.OpTableInsertTry:
					// A storage-bearing element is deep-copied into the
					// table's own domain at insert, so its copy helper must
					// exist even when no copy_to_domain instruction names
					// the type.
					t, ok := f.ValueType(in.TableVal)
					if !ok || !g.m.ValidType(t) || t == mir.TypeUnit {
						continue
					}
					if g.copyTrivial(t) {
						continue
					}
					if err := g.requireCopyable(t); err != nil {
						return err
					}
					if copySet == nil {
						copySet = make(map[mir.TypeId]bool)
					}
					g.collectCopyTypes(t, copySet)
				}
			}
		}
	}
	for i, c := range g.m.Constants {
		if c.Value.Kind == mir.ConstString {
			g.strConsts[c.Name] = i
		}
	}
	for _, t := range g.typeEmissionOrder() {
		if copySet[t] {
			g.copyTypes = append(g.copyTypes, t)
		}
	}
	return nil
}

// copyTrivial reports whether a value of the type can be copied by identity:
// it contains no slice, safe reference, string, or bytes anywhere, so there
// is no storage to move between domains. String and Bytes descriptors carry
// a domain-allocated byte buffer whenever a str/bytes op produced them, so
// their copies must reallocate the buffer.
func (g *gen) copyTrivial(t mir.TypeId) bool {
	if !g.m.ValidType(t) {
		return true
	}
	ty := &g.m.Types[t]
	switch ty.Kind {
	case mir.TypeFunction, mir.TypeSlice, mir.TypeVec, mir.TypeSafeRef, mir.TypeSafeMut,
		mir.TypeDomainHandle, mir.TypeDomainMark, mir.TypeCleanupScope, mir.TypeCleanupID,
		mir.TypeTable, mir.TypeTableView, mir.TypeTableMutView, mir.TypeRawPtr,
		mir.TypeString, mir.TypeBytes:
		return false
	case mir.TypeOption, mir.TypeArray:
		return g.copyTrivial(ty.Elem)
	case mir.TypeResult:
		return g.copyTrivial(ty.OK) && g.copyTrivial(ty.Err)
	case mir.TypeAggregate:
		for _, fld := range ty.Fields {
			if !g.copyTrivial(fld.Type) {
				return false
			}
		}
		return true
	case mir.TypeEnum:
		for _, v := range ty.Variants {
			if v.Payload != mir.TypeUnit && !g.copyTrivial(v.Payload) {
				return false
			}
		}
		return true
	}
	return true
}

// requireCopyable checks that copy_to_domain can recursively materialize the
// value. Identity-bearing resources are never relocatable; slices, vectors,
// arrays, and ordinary aggregates recursively copy non-trivial children.
func (g *gen) requireCopyable(t mir.TypeId) error {
	if !g.m.ValidType(t) {
		return nil
	}
	ty := &g.m.Types[t]
	child := func(ct mir.TypeId) error {
		if !g.copyTrivial(ct) {
			return g.requireCopyable(ct)
		}
		return nil
	}
	switch ty.Kind {
	case mir.TypeDomainHandle, mir.TypeDomainMark, mir.TypeCleanupScope, mir.TypeCleanupID,
		mir.TypeTable, mir.TypeTableView, mir.TypeTableMutView, mir.TypeRawPtr:
		return fmt.Errorf("cgen: copy_to_domain of %s: identity-bearing type is not relocatable", g.m.TypeString(t))
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
		return g.requireCopyable(ty.Elem)
	case mir.TypeVec, mir.TypeArray:
		return g.requireCopyable(ty.Elem)
	case mir.TypeAggregate:
		for _, fld := range ty.Fields {
			if err := child(fld.Type); err != nil {
				return err
			}
		}
	case mir.TypeEnum:
		for _, v := range ty.Variants {
			if v.Payload != mir.TypeUnit {
				if err := child(v.Payload); err != nil {
					return err
				}
			}
		}
	case mir.TypeOption:
		if err := child(ty.Elem); err != nil {
			return err
		}
	case mir.TypeResult:
		if err := child(ty.OK); err != nil {
			return err
		}
		if err := child(ty.Err); err != nil {
			return err
		}
	}
	return nil
}

// collectCopyTypes adds t and every non-trivial child type to the copy-helper
// set.
func (g *gen) collectCopyTypes(t mir.TypeId, set map[mir.TypeId]bool) {
	if !g.m.ValidType(t) || set[t] {
		return
	}
	set[t] = true
	ty := &g.m.Types[t]
	visit := func(ct mir.TypeId) {
		if g.copyTrivial(ct) {
			return
		}
		g.collectCopyTypes(ct, set)
	}
	switch ty.Kind {
	case mir.TypeSlice, mir.TypeVec, mir.TypeSafeRef, mir.TypeSafeMut:
		visit(ty.Elem)
	case mir.TypeAggregate:
		for _, fld := range ty.Fields {
			visit(fld.Type)
		}
	case mir.TypeEnum:
		for _, v := range ty.Variants {
			if v.Payload != mir.TypeUnit {
				visit(v.Payload)
			}
		}
	case mir.TypeOption, mir.TypeResult, mir.TypeArray:
		visit(ty.Elem)
		if ty.Kind == mir.TypeResult {
			visit(ty.OK)
			visit(ty.Err)
		}
	}
}

// emitModule writes the complete translation unit.
// emitFnValueWrappers emits one strictly-conforming forwarder per distinct
// fn.value (target, type) pair: the value's code pointer type takes the
// declared parameters plus an opaque environment pointer, which ordinary
// functions do not, so the wrapper adapts the signature.
func (g *gen) emitFnValueWrappers(b *strings.Builder) {
	for _, site := range g.fnValues {
		fnID := mir.FunctionId(site[0])
		ft := mir.TypeId(site[1])
		sig := g.m.Types[ft].Sig
		n := strconv.Itoa(int(ft))
		wname := "alder_fnwrap_" + strconv.Itoa(int(fnID)) + "_" + n
		ret := "void"
		if sig.Result != mir.TypeUnit {
			ret = g.cType(sig.Result)
		}
		var params []string
		for i, p := range sig.Params {
			if p == mir.TypeUnit {
				continue
			}
			params = append(params, g.cType(p)+" alder_p"+strconv.Itoa(i))
		}
		// The environment pointer is always the final parameter; with no
		// declared parameters it is the only one, so no "void" placeholder is
		// needed.
		paramList := strings.Join(params, ", ")
		if len(params) != 0 {
			paramList += ", "
		}
		paramList += "void *alder_env"
		b.WriteString("static " + ret + " " + wname + "(" + paramList + ");\n")
		b.WriteString("static " + ret + " " + wname + "(" + paramList + ") {\n")
		b.WriteString("  (void)alder_env;\n")
		var args []string
		// A storage-model target: the environment member carries the
		// AlderDomain * captured at the fn.value site, and it becomes the
		// target's leading domain argument.
		if site[2] != 0 {
			args = append(args, "(AlderDomain *)alder_env")
		}
		for i, p := range sig.Params {
			if p == mir.TypeUnit {
				continue
			}
			args = append(args, "alder_p"+strconv.Itoa(i))
		}
		// A closure thunk takes one trailing environment parameter beyond the
		// function type's declared parameters: the wrapper adapts the opaque
		// void * environment to the thunk's reference parameter. A
		// domain-marked target also has one parameter beyond the declared
		// set, but that parameter is the leading domain, already supplied
		// above.
		callee := g.m.Functions[fnID]
		if site[2] == 0 && callee != nil && len(callee.Params) == len(params)+1 {
			args = append(args, "("+g.cType(callee.Params[len(callee.Params)-1].Type)+"){ alder_env, (uint64_t)1 }")
		}
		call := g.fnName(fnID) + "(" + strings.Join(args, ", ") + ")"
		if sig.Result == mir.TypeUnit {
			b.WriteString("  " + call + ";\n}\n")
		} else {
			b.WriteString("  return " + call + ";\n}\n")
		}
	}
	if len(g.fnValues) != 0 {
		b.WriteString("\n")
	}
}

func (g *gen) emitModule(b *strings.Builder) {
	b.WriteString("/* Generated by the Alder C11 backend. Do not edit. */\n")
	b.WriteString("/* Source: verified Alder MIR, format " + strconv.Itoa(g.m.FormatVersion) + ". */\n")
	b.WriteString("#include \"alder.h\"\n")
	if g.program {
		b.WriteString("#include \"alder_host.h\"\n")
	}
	b.WriteString("#include <float.h>\n")
	b.WriteString("#include <string.h>\n")
	b.WriteString("#if defined(__GNUC__) && !defined(__clang__)\n")
	b.WriteString("#pragma GCC diagnostic ignored \"-Wunknown-pragmas\"\n")
	b.WriteString("#endif\n")
	b.WriteString("#pragma STDC FP_CONTRACT OFF\n\n")

	g.emitBindings(b)
	g.emitTypes(b)
	g.emitStringConsts(b)
	g.emitFunctionDecls(b)
	g.emitImportDecls(b)
	g.emitBindingDecls(b)
	g.emitCtxSites(b)
	g.emitCopyHelpers(b)
	g.emitEnvRetainHelpers(b)
	g.emitFnValueWrappers(b)
	for i, f := range g.m.Functions {
		if f == nil {
			continue
		}
		if i > 0 {
			b.WriteString("\n")
		}
		g.emitFunction(b, f)
	}
	if g.program {
		g.emitProgramEntry(b)
	}
}

func (g *gen) emitProgramEntry(b *strings.Builder) {
	f := g.m.Functions[g.mainID]
	b.WriteString("\nint32_t alder_program_entry(void *host_context) {\n")
	b.WriteString("  if (host_context == NULL) { return ALDER_PROGRAM_FAILURE_STATUS; }\n")
	if len(f.Params) == 0 {
		b.WriteString("  return " + g.fnName(g.mainID) + "();\n")
	} else {
		b.WriteString("  AlderDomain alder_root = {0};\n")
		b.WriteString("  int32_t alder_status;\n")
		b.WriteString("  if (!alder_domain_init(&alder_root, NULL)) { return ALDER_PROGRAM_FAILURE_STATUS; }\n")
		b.WriteString("  alder_status = " + g.fnName(g.mainID) + "(&alder_root);\n")
		b.WriteString("  alder_domain_destroy(&alder_root);\n")
		b.WriteString("  return alder_status;\n")
	}
	b.WriteString("}\n")
}

// emitImportDecls writes forward declarations for every imported C symbol,
// so generated calls are always prototyped.
func (g *gen) emitImportDecls(b *strings.Builder) {
	for i := range g.m.Imports {
		imp := &g.m.Imports[i]
		ret := "void"
		if imp.Sig.Result != mir.TypeUnit {
			ret = g.cType(imp.Sig.Result)
		}
		var params []string
		for _, p := range imp.Sig.Params {
			if p == mir.TypeUnit {
				continue
			}
			params = append(params, g.cType(p))
		}
		if len(params) == 0 {
			params = append(params, "void")
		}
		b.WriteString(ret + " (" + imp.Name + ")(" + strings.Join(params, ", ") + ");\n")
	}
	if len(g.m.Imports) > 0 {
		b.WriteString("\n")
	}
}

// emitBindings writes one include per binding block, each followed by the
// C11 compile-time binding checks. The checks live in the generated program
// translation unit, so no build can compile a binding whose header disagrees
// with the declared spelling, record field, function signature, or constant.
// Assertion messages name the Alder binding member.
func (g *gen) emitBindings(b *strings.Builder) {
	if len(g.m.Bindings) == 0 {
		return
	}
	b.WriteString("#include <stddef.h>\n")
	for i := range g.m.Bindings {
		bind := &g.m.Bindings[i]
		b.WriteString("#include <" + bind.Header + ">\n")
		g.emitBindingChecks(b, i, bind)
	}
	b.WriteString("\n")
}

func (g *gen) emitBindingChecks(b *strings.Builder, block int, bind *mir.BindingBlock) {
	for ti, id := range bind.Types {
		ty := &g.m.Types[id]
		probe := "alder_bind_" + strconv.Itoa(block) + "_t" + strconv.Itoa(ti)
		what := "binding " + bind.Name + "." + ty.Name + " (" + ty.CName + ")"
		b.WriteString("typedef " + ty.CName + " " + probe + ";\n")
		switch ty.CClass {
		case mir.CClassOpaque:
			b.WriteString("_Static_assert(sizeof(" + probe + " *) == sizeof(void *), \"" + what +
				": opaque binding spelling must resolve to a pointer-representable type\");\n")
		case mir.CClassScalar:
			b.WriteString("_Static_assert(sizeof(" + probe + ") >= 1, \"" + what +
				": scalar binding spelling must resolve to a complete type\");\n")
		case mir.CClassRecord:
			b.WriteString("_Static_assert(_Alignof(" + probe + ") >= 1, \"" + what +
				": record binding spelling must resolve to a complete type\");\n")
			for _, fld := range ty.Fields {
				fldWhat := what + "." + fld.Name + " (" + fld.CName + ")"
				declared := g.cType(fld.Type)
				b.WriteString("_Static_assert(offsetof(" + probe + ", " + fld.CName + ") % _Alignof(" + declared + ") == 0, \"" +
					fldWhat + ": field offset must respect the declared field alignment\");\n")
				b.WriteString("_Static_assert(offsetof(" + probe + ", " + fld.CName + ") + sizeof(" + declared + ") <= sizeof(" + probe + "), \"" +
					fldWhat + ": field does not fit inside the record\");\n")
				b.WriteString("_Static_assert(_Generic(((" + probe + " *)0)->" + fld.CName + ", " + declared + ": 1, default: 0), \"" +
					fldWhat + ": field type does not match the declared binding type " + declared + "\");\n")
			}
		}
	}
	for fi := range bind.Funcs {
		fn := &bind.Funcs[fi]
		what := "binding " + bind.Name + "." + fn.Name + " (" + fn.CName + ")"
		var params []string
		for _, p := range fn.Sig.Params {
			if p == mir.TypeUnit {
				continue
			}
			params = append(params, g.cType(p))
		}
		if len(params) == 0 {
			params = append(params, "void")
		}
		ret := "void"
		if fn.Sig.Result != mir.TypeUnit {
			ret = g.cType(fn.Sig.Result)
		}
		b.WriteString("_Static_assert(_Generic(&" + fn.CName + ", " + ret + " (*)(" + strings.Join(params, ", ") +
			"): 1, default: 0), \"" + what + ": function type does not match the declared binding signature\");\n")
	}
	for ci := range bind.Consts {
		c := &bind.Consts[ci]
		what := "binding " + bind.Name + "." + c.Name + " (" + c.CName + ")"
		declared := g.cType(c.Type)
		b.WriteString("_Static_assert(_Generic(" + c.CName + " + 0, int: 1, unsigned int: 1, long: 1, unsigned long: 1, " +
			"long long: 1, unsigned long long: 1, short: 1, unsigned short: 1, char: 1, signed char: 1, unsigned char: 1, " +
			"_Bool: 1, default: 0), \"" + what + ": constant must have an integral type\");\n")
		b.WriteString("_Static_assert((" + c.CName + ") == (" + declared + ")(" + c.CName + "), \"" + what +
			": value must be representable as " + declared + "\");\n")
	}
}

// emitBindingDecls writes forward declarations for every binding-block C
// function, so generated unsafe calls are always prototyped.
func (g *gen) emitBindingDecls(b *strings.Builder) {
	for i := range g.m.Bindings {
		bind := &g.m.Bindings[i]
		for j := range bind.Funcs {
			fn := &bind.Funcs[j]
			ret := "void"
			if fn.Sig.Result != mir.TypeUnit {
				ret = g.cType(fn.Sig.Result)
			}
			var params []string
			for _, p := range fn.Sig.Params {
				if p == mir.TypeUnit {
					continue
				}
				params = append(params, g.cType(p))
			}
			if len(params) == 0 {
				params = append(params, "void")
			}
			b.WriteString(ret + " " + fn.CName + "(" + strings.Join(params, ", ") + ");\n")
		}
	}
	if len(g.m.Bindings) > 0 {
		b.WriteString("\n")
	}
}

// emitTypes writes forward typedefs for record-like types, then emits all
// type bodies and function-pointer typedefs in dependency order. The verifier
// rejects cycles, so a stable postorder is sufficient even for API-built
// modules whose child TypeIds are greater than their parents.
func (g *gen) emitTypes(b *strings.Builder) {
	hasString, hasBytes := false, false
	for i := range g.m.Types {
		hasString = hasString || g.m.Types[i].Kind == mir.TypeString
		hasBytes = hasBytes || g.m.Types[i].Kind == mir.TypeBytes
	}
	if hasString {
		b.WriteString("typedef struct { const uint8_t *data; uint64_t len; } AlderString;\n")
		b.WriteString("static bool ALDER_MAYBE_UNUSED alder_string_eq(AlderString alder_a, AlderString alder_b) {\n")
		b.WriteString("  if (alder_a.len != alder_b.len) { return false; }\n")
		b.WriteString("  return alder_a.len == UINT64_C(0) || memcmp(alder_a.data, alder_b.data, (size_t)alder_a.len) == 0;\n")
		b.WriteString("}\n")
		b.WriteString("static bool ALDER_MAYBE_UNUSED alder_string_lt(AlderString alder_a, AlderString alder_b) {\n")
		b.WriteString("  uint64_t alder_n = alder_a.len < alder_b.len ? alder_a.len : alder_b.len;\n")
		b.WriteString("  for (uint64_t alder_i = 0; alder_i < alder_n; alder_i++) {\n")
		b.WriteString("    if (alder_a.data[alder_i] != alder_b.data[alder_i]) { return alder_a.data[alder_i] < alder_b.data[alder_i]; }\n")
		b.WriteString("  }\n")
		b.WriteString("  return alder_a.len < alder_b.len;\n")
		b.WriteString("}\n")
	}
	if hasBytes {
		b.WriteString("typedef struct { const uint8_t *data; uint64_t len; } AlderBytes;\n")
		b.WriteString("static bool ALDER_MAYBE_UNUSED alder_bytes_eq(AlderBytes alder_a, AlderBytes alder_b) {\n")
		b.WriteString("  if (alder_a.len != alder_b.len) { return false; }\n")
		b.WriteString("  return alder_a.len == UINT64_C(0) || memcmp(alder_a.data, alder_b.data, (size_t)alder_a.len) == 0;\n")
		b.WriteString("}\n")
		b.WriteString("static bool ALDER_MAYBE_UNUSED alder_bytes_lt(AlderBytes alder_a, AlderBytes alder_b) {\n")
		b.WriteString("  uint64_t alder_n = alder_a.len < alder_b.len ? alder_a.len : alder_b.len;\n")
		b.WriteString("  for (uint64_t alder_i = 0; alder_i < alder_n; alder_i++) {\n")
		b.WriteString("    if (alder_a.data[alder_i] != alder_b.data[alder_i]) { return alder_a.data[alder_i] < alder_b.data[alder_i]; }\n")
		b.WriteString("  }\n")
		b.WriteString("  return alder_a.len < alder_b.len;\n")
		b.WriteString("}\n")
	}
	if hasString || hasBytes {
		b.WriteByte('\n')
	}
	hasRecords := false
	for i := range g.m.Types {
		id := mir.TypeId(i)
		ty := &g.m.Types[i]
		switch ty.Kind {
		case mir.TypeAggregate, mir.TypeEnum, mir.TypeOption, mir.TypeResult, mir.TypeArray:
			b.WriteString("typedef struct AlderTy" + strconv.Itoa(int(id)) + " AlderTy" + strconv.Itoa(int(id)) + ";\n")
			hasRecords = true
		}
	}
	if hasRecords {
		b.WriteString("\n")
	}
	for _, id := range g.typeEmissionOrder() {
		ty := &g.m.Types[id]
		switch ty.Kind {
		case mir.TypeAggregate, mir.TypeEnum, mir.TypeOption, mir.TypeResult, mir.TypeArray:
			g.emitStruct(b, id, ty)
		case mir.TypeFunction:
			g.emitFunctionType(b, id, ty.Sig)
		}
	}
}

func (g *gen) typeEmissionOrder() []mir.TypeId {
	seen := make([]bool, len(g.m.Types))
	var order []mir.TypeId
	var visit func(mir.TypeId)
	visit = func(id mir.TypeId) {
		if !g.m.ValidType(id) || seen[id] {
			return
		}
		seen[id] = true
		for _, child := range typeDependencies(&g.m.Types[id]) {
			visit(child)
		}
		if id >= mir.NumPrimitiveTypes {
			order = append(order, id)
		}
	}
	for id := mir.NumPrimitiveTypes; int(id) < len(g.m.Types); id++ {
		visit(id)
	}
	return order
}

func typeDependencies(ty *mir.Type) []mir.TypeId {
	var out []mir.TypeId
	switch ty.Kind {
	case mir.TypeAggregate:
		for _, field := range ty.Fields {
			out = append(out, field.Type)
		}
	case mir.TypeEnum:
		for _, variant := range ty.Variants {
			out = append(out, variant.Payload)
		}
	case mir.TypeOption, mir.TypeSlice, mir.TypeVec, mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeArray,
		mir.TypeRawPtr, mir.TypeTable, mir.TypeID, mir.TypeTableView, mir.TypeTableMutView:
		out = append(out, ty.Elem)
	case mir.TypeResult:
		out = append(out, ty.OK, ty.Err)
	case mir.TypeFunction:
		out = append(out, ty.Sig.Params...)
		out = append(out, ty.Sig.Result)
		if ty.Sig.Env != mir.NoType {
			out = append(out, ty.Sig.Env)
		}
	}
	return out
}

func (g *gen) emitFunctionType(b *strings.Builder, id mir.TypeId, sig mir.FuncSig) {
	ret := "void"
	if sig.Result != mir.TypeUnit {
		ret = g.cType(sig.Result)
	}
	var params []string
	for _, param := range sig.Params {
		if param != mir.TypeUnit {
			params = append(params, g.cType(param))
		}
	}
	// A function value is {code, env}: the code pointer takes the declared
	// parameters plus the opaque environment pointer, so closures and plain
	// function references share one ABI. Env-less functions pass NULL.
	paramList := strings.Join(params, ", ")
	if len(params) != 0 {
		paramList += ", "
	}
	paramList += "void *alder_env"
	b.WriteString("typedef struct AlderFnTy" + strconv.Itoa(int(id)) + " AlderFnTy" + strconv.Itoa(int(id)) + ";\n")
	b.WriteString("typedef " + ret + " (*AlderFnTy" + strconv.Itoa(int(id)) + "_code)(" + paramList + ");\n")
	b.WriteString("struct AlderFnTy" + strconv.Itoa(int(id)) + " { AlderFnTy" + strconv.Itoa(int(id)) + "_code code; void *env; void *(*retain)(AlderDomain *, void *); };\n")
}

func (g *gen) emitStruct(b *strings.Builder, id mir.TypeId, ty *mir.Type) {
	name := "AlderTy" + strconv.Itoa(int(id))
	if ty.Name != "" {
		b.WriteString("/* @" + ty.Name + " */\n")
	} else {
		b.WriteString("/* " + g.m.TypeString(id) + " */\n")
	}
	b.WriteString("struct " + name + " {\n")
	switch ty.Kind {
	case mir.TypeAggregate:
		if len(ty.Fields) == 0 {
			b.WriteString("  uint8_t alder_empty;\n")
		}
		for i, fld := range ty.Fields {
			b.WriteString("  " + g.cType(fld.Type) + " alder_f" + strconv.Itoa(i) + ";\n")
		}
	case mir.TypeEnum, mir.TypeOption, mir.TypeResult:
		vs, _ := g.m.VariantsOf(id)
		hasPayload := false
		for _, v := range vs {
			if v.Payload != mir.TypeUnit {
				hasPayload = true
				break
			}
		}
		if hasPayload {
			b.WriteString("  union {\n")
			for i, v := range vs {
				if v.Payload != mir.TypeUnit {
					b.WriteString("    " + g.cType(v.Payload) + " alder_p" + strconv.Itoa(i) + ";\n")
				}
			}
			b.WriteString("  } alder_u;\n")
		}
		b.WriteString("  uint32_t alder_tag;\n")
	case mir.TypeArray:
		length := ty.Length
		if length == 0 {
			length = 1 // native C arrays cannot have zero length
		}
		b.WriteString("  " + g.cType(ty.Elem) + " alder_e[" + strconv.FormatUint(length, 10) + "];\n")
	}
	b.WriteString("};\n")
}

// emitStringConsts writes immutable numeric byte storage for byte-sequence constants.
func (g *gen) emitStringConsts(b *strings.Builder) {
	for i, c := range g.m.Constants {
		if c.Value.Kind != mir.ConstString {
			continue
		}
		qualifier := "const "
		if g.m.Types[c.Type].Kind == mir.TypeSlice {
			qualifier = ""
		}
		b.WriteString("static ALDER_MAYBE_UNUSED " + qualifier + "uint8_t alder_str_" + strconv.Itoa(i) + "[] = {")
		if len(c.Value.String) == 0 {
			b.WriteString(" UINT8_C(0)")
		} else {
			for j := 0; j < len(c.Value.String); j++ {
				if j > 0 {
					b.WriteByte(',')
				}
				b.WriteString(" UINT8_C(" + strconv.Itoa(int(c.Value.String[j])) + ")")
			}
		}
		b.WriteString(" };\n")
	}
	if len(g.strConsts) > 0 {
		b.WriteString("\n")
	}
}

// emitCopyHelpers writes the per-type copy functions used by copy_to_domain.
func (g *gen) emitCopyHelpers(b *strings.Builder) {
	for _, t := range g.copyTypes {
		g.emitCopyHelper(b, t)
	}
	if len(g.copyTypes) > 0 {
		b.WriteString("\n")
	}
}

// fnEnvAggregate returns the environment record type of a fn.value's
// environment operand when that operand is a reference to an aggregate, or 0
// when the function value has no owned closure environment.
func (g *gen) fnEnvAggregate(f *mir.Function, env mir.ValueId) mir.TypeId {
	if env == mir.NoValue {
		return 0
	}
	t, ok := f.ValueType(env)
	if !ok || !g.m.ValidType(t) {
		return 0
	}
	ty := &g.m.Types[t]
	switch ty.Kind {
	case mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeSlice:
	default:
		return 0
	}
	if !g.m.ValidType(ty.Elem) || g.m.Types[ty.Elem].Kind != mir.TypeAggregate {
		return 0
	}
	return ty.Elem
}

// emitEnvRetainHelpers writes the per-environment retain hook used by
// copy_to_domain of a function value. It allocates a complete, independent
// environment in the destination domain: a shallow record copy is enough
// because captures are storage-free, a domain field is rewritten to the
// destination domain, and every function-valued capture is retained
// recursively through its own hook.
func (g *gen) emitEnvRetainHelpers(b *strings.Builder) {
	seen := make(map[mir.TypeId]bool)
	domainEmitted := false
	wrote := false
	for _, f := range g.m.Functions {
		if f == nil {
			continue
		}
		for _, blk := range f.Blocks {
			if blk == nil {
				continue
			}
			for i := range blk.Instrs {
				in := &blk.Instrs[i]
				if in.Op != mir.OpFnValue {
					continue
				}
				if t := g.fnEnvAggregate(f, in.A); t != 0 {
					if !seen[t] {
						seen[t] = true
						g.emitEnvRetain(b, t)
						wrote = true
					}
					continue
				}
				// A named function value's environment is the domain its
				// frame will hang off, so retaining it into another domain
				// rewrites it to that domain.
				if in.A != mir.NoValue && in.TypeOp == mir.FnValueDomainMarker && !domainEmitted {
					b.WriteString("static ALDER_MAYBE_UNUSED void *alder_env_retain_domain(AlderDomain *alder_d, void *alder_env) {\n  (void)alder_env;\n  return alder_d;\n}\n")
					domainEmitted = true
					wrote = true
				}
			}
		}
	}
	if wrote {
		b.WriteString("\n")
	}
}

func (g *gen) emitEnvRetain(b *strings.Builder, t mir.TypeId) {
	name := "alder_env_retain_ty" + strconv.Itoa(int(t))
	b.WriteString("static ALDER_MAYBE_UNUSED void *" + name + "(AlderDomain *alder_d, void *alder_env) {\n")
	b.WriteString("  " + g.cType(t) + " *alder_src = (" + g.cType(t) + " *)alder_env;\n")
	b.WriteString("  " + g.cType(t) + " *alder_dst = (" + g.cType(t) +
		" *)alder_domain_alloc(alder_d, sizeof(" + g.cType(t) + "), (size_t)" + g.typeAlign(t) + ");\n")
	b.WriteString("  if (alder_dst == NULL) { alder_runtime_panic(\"closure environment: out of memory\"); }\n")
	b.WriteString("  *alder_dst = *alder_src;\n")
	for i, fld := range g.m.Types[t].Fields {
		if !g.m.ValidType(fld.Type) {
			continue
		}
		field := "alder_dst->alder_f" + strconv.Itoa(i)
		switch g.m.Types[fld.Type].Kind {
		case mir.TypeFunction:
			b.WriteString("  if (" + field + ".retain != NULL && " + field + ".env != NULL) { " +
				field + ".env = " + field + ".retain(alder_d, " + field + ".env); }\n")
		case mir.TypeDomainHandle:
			b.WriteString("  " + field + " = alder_d;\n")
		case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
			// A captured view is a header, not owned storage: the closure
			// aliases the scope that owns it, so the hook copies the header.
		default:
			// A storage-bearing capture is deep-copied into the destination
			// domain, and any function inside it is retained by the
			// recursive copy.
			if !g.copyTrivial(fld.Type) {
				b.WriteString("  " + field + " = " + g.copyCall(fld.Type) +
					"(alder_d, alder_src->alder_f" + strconv.Itoa(i) + ", 1);\n")
			}
		}
	}
	b.WriteString("  return alder_dst;\n}\n")
}

func (g *gen) emitCopyHelper(b *strings.Builder, t mir.TypeId) {
	name := "alder_copy_ty" + strconv.Itoa(int(t))
	b.WriteString("static ALDER_MAYBE_UNUSED " + g.cType(t) + " " + name +
		"(AlderDomain *alder_d, " + g.cType(t) + " alder_v, int alder_retain) {\n  (void)alder_retain;\n")
	ty := &g.m.Types[t]
	switch ty.Kind {
	case mir.TypeString, mir.TypeBytes:
		// The descriptor is {data, len}; the buffer moves into the
		// destination domain, keeping the slice-branch checks and style.
		b.WriteString("  uint64_t alder_t;\n")
		b.WriteString("  if (!alder_u64_mul_checked(alder_v.len, (uint64_t)sizeof(uint8_t), &alder_t)) { alder_runtime_panic(\"copy_to_domain: size overflow\"); }\n")
		b.WriteString("  if (alder_t > (uint64_t)SIZE_MAX) { alder_runtime_panic(\"copy_to_domain: size exceeds size_t\"); }\n")
		b.WriteString("  if (alder_v.len > (uint64_t)0) {\n")
		b.WriteString("    if (alder_v.data == NULL) { alder_runtime_panic(\"copy_to_domain: null source\"); }\n")
		b.WriteString("    void *alder_p = alder_domain_alloc(alder_d, (size_t)alder_t, (size_t)1);\n")
		b.WriteString("    if (alder_p == NULL) { alder_runtime_panic(\"copy_to_domain: out of memory\"); }\n")
		b.WriteString("    memcpy(alder_p, alder_v.data, (size_t)alder_t);\n")
		b.WriteString("    alder_v.data = alder_p;\n")
		b.WriteString("  }\n")
	case mir.TypeFunction:
		// A function value is {code, environment, retain}. A cross-domain
		// copy retains the environment through the hook so the copy owns a
		// complete environment in the destination domain; a same-domain copy
		// (a vector grow) passes zero and stays a plain bit copy.
		b.WriteString("  if (alder_retain != 0 && alder_v.retain != NULL && alder_v.env != NULL) { alder_v.env = alder_v.retain(alder_d, alder_v.env); }\n")
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut, mir.TypeVec:
		elem := ty.Elem
		b.WriteString("  uint64_t alder_t;\n")
		b.WriteString("  if (!alder_u64_mul_checked(alder_v.len, (uint64_t)" +
			g.typeSize(elem) + ", &alder_t)) { alder_runtime_panic(\"copy_to_domain: size overflow\"); }\n")
		b.WriteString("  if (alder_t > (uint64_t)SIZE_MAX) { alder_runtime_panic(\"copy_to_domain: size exceeds size_t\"); }\n")
		b.WriteString("  if (alder_v.len > (uint64_t)0) {\n")
		b.WriteString("    if (alder_v.data == NULL) { alder_runtime_panic(\"copy_to_domain: null source\"); }\n")
		b.WriteString("    void *alder_p = alder_domain_alloc(alder_d, (size_t)alder_t, (size_t)" +
			g.typeAlign(elem) + ");\n")
		b.WriteString("    if (alder_p == NULL) { alder_runtime_panic(\"copy_to_domain: out of memory\"); }\n")
		if g.copyTrivial(elem) {
			b.WriteString("    memcpy(alder_p, alder_v.data, (size_t)alder_t);\n")
		} else {
			b.WriteString("    for (uint64_t alder_i = (uint64_t)0; alder_i < alder_v.len; alder_i++) { ((" + g.cType(elem) + " *)alder_p)[alder_i] = " + g.copyCall(elem) + "(alder_d, ((" + g.cType(elem) + " *)alder_v.data)[alder_i], alder_retain); }\n")
		}
		b.WriteString("    alder_v.data = alder_p;\n")
		b.WriteString("  }\n")
		if ty.Kind == mir.TypeVec {
			b.WriteString("  alder_v.capacity = alder_v.len;\n")
		}
	case mir.TypeArray:
		if !g.copyTrivial(ty.Elem) {
			b.WriteString("  for (uint64_t alder_i = (uint64_t)0; alder_i < (uint64_t)" + strconv.FormatUint(ty.Length, 10) + "; alder_i++) {\n")
			b.WriteString("    alder_v.alder_e[alder_i] = " + g.copyCall(ty.Elem) + "(alder_d, alder_v.alder_e[alder_i], alder_retain);\n")
			b.WriteString("  }\n")
		}
	case mir.TypeAggregate:
		for i, fld := range ty.Fields {
			if g.copyTrivial(fld.Type) {
				continue
			}
			field := "alder_f" + strconv.Itoa(i)
			b.WriteString("  alder_v." + field + " = " +
				g.copyCall(fld.Type) + "(alder_d, alder_v." + field + ", alder_retain);\n")
		}
	case mir.TypeEnum:
		vs := ty.Variants
		for i, v := range vs {
			if v.Payload == mir.TypeUnit || g.copyTrivial(v.Payload) {
				continue
			}
			b.WriteString("  if (alder_v.alder_tag == (uint32_t)" + strconv.Itoa(i) + ") {\n")
			b.WriteString("    alder_v.alder_u.alder_p" + strconv.Itoa(i) + " = " +
				g.copyCall(v.Payload) + "(alder_d, alder_v.alder_u.alder_p" + strconv.Itoa(i) + ", alder_retain);\n")
			b.WriteString("  }\n")
		}
	case mir.TypeOption, mir.TypeResult:
		vs, _ := g.m.VariantsOf(t)
		for i, v := range vs {
			if v.Payload == mir.TypeUnit || g.copyTrivial(v.Payload) {
				continue
			}
			b.WriteString("  if (alder_v.alder_tag == (uint32_t)" + strconv.Itoa(i) + ") {\n")
			b.WriteString("    alder_v.alder_u.alder_p" + strconv.Itoa(i) + " = " +
				g.copyCall(v.Payload) + "(alder_d, alder_v.alder_u.alder_p" + strconv.Itoa(i) + ", alder_retain);\n")
			b.WriteString("  }\n")
		}
	}
	b.WriteString("  return alder_v;\n}\n")
}

// copyCall returns the helper name for a non-trivial copied type.
func (g *gen) copyCall(t mir.TypeId) string {
	return "alder_copy_ty" + strconv.Itoa(int(t))
}

// emitCtxSites writes the cleanup adapter types, context structs, and adapter
// functions for every cleanup.push site.
func (g *gen) emitCtxSites(b *strings.Builder) {
	sites := make([]struct {
		fi, bi, ii int
	}, 0, g.nextCtx)
	for fi, f := range g.m.Functions {
		if f == nil {
			continue
		}
		for bi, blk := range f.Blocks {
			if blk == nil {
				continue
			}
			for ii := range blk.Instrs {
				if blk.Instrs[ii].Op == mir.OpCleanupPush {
					sites = append(sites, struct{ fi, bi, ii int }{fi, bi, ii})
				}
			}
		}
	}
	for _, s := range sites {
		idx := g.pushSites[[3]int{s.fi, s.bi, s.ii}]
		f := g.m.Functions[s.fi]
		in := &f.Blocks[s.bi].Instrs[s.ii]
		callee := g.m.Functions[in.CleanupFn]
		b.WriteString("typedef struct AlderCtx_" + strconv.Itoa(idx) + " {\n")
		arg := 0
		for _, p := range callee.Params {
			if p.Type == mir.TypeUnit {
				continue
			}
			b.WriteString("  " + g.cType(p.Type) + " alder_f" + strconv.Itoa(arg) + ";\n")
			arg++
		}
		if arg == 0 {
			b.WriteString("  uint8_t alder_empty;\n")
		}
		b.WriteString("} AlderCtx_" + strconv.Itoa(idx) + ";\n")
		b.WriteString("static ALDER_MAYBE_UNUSED void alder_cleanup_" + strconv.Itoa(idx) + "(void *alder_ctx) {\n")
		if arg == 0 {
			b.WriteString("  (void)alder_ctx;\n")
		} else {
			b.WriteString("  AlderCtx_" + strconv.Itoa(idx) + " *alder_c = (AlderCtx_" + strconv.Itoa(idx) + " *)alder_ctx;\n")
		}
		b.WriteString("  " + g.fnName(in.CleanupFn) + "(")
		arg = 0
		first := true
		for _, p := range callee.Params {
			if p.Type == mir.TypeUnit {
				continue
			}
			if !first {
				b.WriteString(", ")
			}
			first = false
			b.WriteString("alder_c->alder_f" + strconv.Itoa(arg))
			arg++
		}
		b.WriteString(");\n}\n")
	}
	if len(sites) > 0 {
		b.WriteString("\n")
	}
}

// emitFunctionDecls writes forward declarations for every function.
func (g *gen) emitFunctionDecls(b *strings.Builder) {
	for i, f := range g.m.Functions {
		if f == nil {
			continue
		}
		b.WriteString("static ALDER_MAYBE_UNUSED " + g.fnResultType(f) + " " +
			g.fnName(mir.FunctionId(i)) + "(" + g.fnParams(f) + ");\n")
	}
	if len(g.m.Functions) > 0 {
		b.WriteString("\n")
	}
}

// fnName returns the generated C name of a function.
func (g *gen) fnName(id mir.FunctionId) string {
	f := g.m.Functions[id]
	return "alder_fn_" + sanitize(f.Name) + "_" + strconv.Itoa(int(id))
}

// fnResultType returns the C result type of a function (void for unit).
func (g *gen) fnResultType(f *mir.Function) string {
	if f.Result == mir.TypeUnit {
		return "void"
	}
	return g.cType(f.Result)
}

// fnParams returns the C parameter list of a function; unit parameters are
// dropped because unit has exactly one value and C has no void parameters.
func (g *gen) fnParams(f *mir.Function) string {
	var parts []string
	for i, p := range f.Params {
		if p.Type == mir.TypeUnit {
			continue
		}
		parts = append(parts, g.cType(p.Type)+" alder_v"+strconv.Itoa(i))
	}
	if len(parts) == 0 {
		return "void"
	}
	return strings.Join(parts, ", ")
}

// sanitize maps a MIR identifier to a safe C identifier fragment.
func sanitize(name string) string {
	var b strings.Builder
	for i := 0; i < len(name); i++ {
		c := name[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			b.WriteByte(c)
		} else {
			b.WriteByte('_')
		}
	}
	return b.String()
}
