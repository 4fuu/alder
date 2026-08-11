// Package cgen lowers verified Aster MIR to deterministic, portable C11.
//
// The backend accepts only verified modules: Generate runs the full verifier
// and refuses to lower invalid input rather than silently repairing it. All
// output derives from declaration and ID order; it never depends on Go map
// iteration, host addresses, or absolute paths.
//
// Lowering policy (details in docs/c-backend.md):
//   - every MIR value becomes one C variable, assigned exactly once by its
//     definition; block parameters are assigned at every edge before the
//     goto, which gives deterministic phi lowering;
//   - side effects are sequenced as explicit statements; call arguments are
//     reads of already-computed variables, so their unspecified C evaluation
//     order is unobservable;
//   - checked operations fail by branching to their explicit MIR failure
//     edge; unchecked runtime failures (allocation failure, identity
//     exhaustion, unreachable execution, out-of-range float-to-int
//     conversion) terminate via aster_runtime_panic with a documented
//     message;
//   - narrow integer operations promote to 64 bits and range-check; narrow
//     shifts check against the source width and compute at that width.
package cgen

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/4fuu/aster/mir"
	"github.com/4fuu/aster/mir/verify"
)

// Generate lowers a verified module to a single C11 translation unit.
func Generate(m *mir.Module) (string, error) {
	if m == nil {
		return "", fmt.Errorf("cgen: nil module")
	}
	if errs := verify.Module(m); len(errs) > 0 {
		return "", fmt.Errorf("cgen: module failed verification:\n%s", verify.Errors(errs).String())
	}
	g := &gen{m: m}
	if err := g.analyze(); err != nil {
		return "", err
	}
	var b strings.Builder
	g.emitModule(&b)
	return b.String(), nil
}

// gen carries the module and the per-function lowering state.
type gen struct {
	m *mir.Module

	// Module-wide analysis results.
	copyTypes []mir.TypeId   // types needing copy helpers, ascending
	pushSites map[[3]int]int // cleanup.push site -> ctx/adapter index
	nextCtx   int            // module-wide ctx/adapter counter
	strConsts map[string]int // string constant name -> static array index

	// Per-function lowering state.
	f           *mir.Function
	paramValues map[[2]int]mir.ValueId // (block, param) -> value id
	domainUsed  int                    // running domain slot counter
	scopeUsed   int                    // running scope slot counter
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
				}
			}
		}
	}
	for _, c := range g.m.Constants {
		if c.Value.Kind == mir.ConstString {
			g.strConsts[c.Name] = len(g.strConsts)
		}
	}
	for t := range copySet {
		g.copyTypes = append(g.copyTypes, t)
	}
	for i := 0; i < len(g.copyTypes); i++ {
		for j := i + 1; j < len(g.copyTypes); j++ {
			if g.copyTypes[j] < g.copyTypes[i] {
				g.copyTypes[i], g.copyTypes[j] = g.copyTypes[j], g.copyTypes[i]
			}
		}
	}
	return nil
}

// copyTrivial reports whether a value of the type can be copied by identity:
// it contains no slice or safe reference anywhere, so there is no storage to
// move between domains.
func (g *gen) copyTrivial(t mir.TypeId) bool {
	if !g.m.ValidType(t) {
		return true
	}
	ty := &g.m.Types[t]
	switch ty.Kind {
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
		return false
	case mir.TypeOption:
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

// requireCopyable rejects copy_to_domain targets whose slice elements are
// themselves non-trivial: the M3 backend copies slice element bytes, so a
// nested reference inside an element would be shared instead of copied.
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
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
		if !g.copyTrivial(ty.Elem) {
			return fmt.Errorf("cgen: copy_to_domain of %s: slice elements must be copy-trivial (no nested references)", g.m.TypeString(t))
		}
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
	case mir.TypeOption, mir.TypeResult:
		if err := child(ty.Elem); err != nil {
			return err
		}
		if ty.Kind == mir.TypeResult {
			if err := child(ty.OK); err != nil {
				return err
			}
			if err := child(ty.Err); err != nil {
				return err
			}
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
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
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
	case mir.TypeOption, mir.TypeResult:
		visit(ty.Elem)
		if ty.Kind == mir.TypeResult {
			visit(ty.OK)
			visit(ty.Err)
		}
	}
}

// emitModule writes the complete translation unit.
func (g *gen) emitModule(b *strings.Builder) {
	b.WriteString("/* Generated by the Aster C11 backend. Do not edit. */\n")
	b.WriteString("/* Source: verified Aster MIR, format " + strconv.Itoa(g.m.FormatVersion) + ". */\n")
	b.WriteString("#include \"aster.h\"\n")
	b.WriteString("#include <string.h>\n\n")

	g.emitTypes(b)
	g.emitStringConsts(b)
	g.emitFunctionDecls(b)
	g.emitImportDecls(b)
	g.emitCtxSites(b)
	g.emitCopyHelpers(b)
	for i, f := range g.m.Functions {
		if f == nil {
			continue
		}
		if i > 0 {
			b.WriteString("\n")
		}
		g.emitFunction(b, f)
	}
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
		b.WriteString(ret + " " + sanitize(imp.Name) + "(" + strings.Join(params, ", ") + ");\n")
	}
	if len(g.m.Imports) > 0 {
		b.WriteString("\n")
	}
}

// emitTypes writes one struct per aggregate, enum, option, and result type.
func (g *gen) emitTypes(b *strings.Builder) {
	for i := range g.m.Types {
		id := mir.TypeId(i)
		ty := &g.m.Types[i]
		switch ty.Kind {
		case mir.TypeAggregate, mir.TypeEnum, mir.TypeOption, mir.TypeResult:
			g.emitStruct(b, id, ty)
		}
	}
}

func (g *gen) emitStruct(b *strings.Builder, id mir.TypeId, ty *mir.Type) {
	name := "AsterTy" + strconv.Itoa(int(id))
	if ty.Name != "" {
		b.WriteString("/* @" + ty.Name + " */\n")
	} else {
		b.WriteString("/* " + g.m.TypeString(id) + " */\n")
	}
	b.WriteString("typedef struct " + name + " " + name + ";\n")
	b.WriteString("struct " + name + " {\n")
	switch ty.Kind {
	case mir.TypeAggregate:
		for _, fld := range ty.Fields {
			b.WriteString("  " + g.cType(fld.Type) + " aster_f_" + sanitize(fld.Name) + ";\n")
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
					b.WriteString("    " + g.cType(v.Payload) + " aster_p" + strconv.Itoa(i) + ";\n")
				}
			}
			b.WriteString("  } aster_u;\n")
		}
		b.WriteString("  uint32_t aster_tag;\n")
	}
	b.WriteString("};\n")
}

// emitStringConsts writes static storage for string constants.
func (g *gen) emitStringConsts(b *strings.Builder) {
	for i, c := range g.m.Constants {
		if c.Value.Kind != mir.ConstString {
			continue
		}
		b.WriteString("static uint8_t aster_str_" + strconv.Itoa(i) + "[] = \"")
		b.WriteString(cString(c.Value.String))
		b.WriteString("\";\n")
	}
	if len(g.strConsts) > 0 {
		b.WriteString("\n")
	}
}

// cString escapes a byte string as a C string literal with octal escapes, so
// embedded NUL bytes and hex-digit ambiguity are impossible.
func cString(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch c {
		case '"':
			b.WriteString("\\\"")
		case '\\':
			b.WriteString("\\\\")
		case '\n':
			b.WriteString("\\n")
		case '\t':
			b.WriteString("\\t")
		case '\r':
			b.WriteString("\\r")
		default:
			if c >= 0x20 && c < 0x7f {
				b.WriteByte(c)
			} else {
				b.WriteString("\\" + octal(c))
			}
		}
	}
	return b.String()
}

func octal(c byte) string {
	return strconv.FormatInt(int64(c), 8)
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

func (g *gen) emitCopyHelper(b *strings.Builder, t mir.TypeId) {
	name := "aster_copy_ty" + strconv.Itoa(int(t))
	b.WriteString("static ASTER_MAYBE_UNUSED " + g.cType(t) + " " + name +
		"(AsterDomain *aster_d, " + g.cType(t) + " aster_v) {\n")
	ty := &g.m.Types[t]
	switch ty.Kind {
	case mir.TypeSlice, mir.TypeSafeRef, mir.TypeSafeMut:
		elem := ty.Elem
		b.WriteString("  uint64_t aster_t;\n")
		b.WriteString("  if (!aster_u64_mul_checked(aster_v.len, (uint64_t)" +
			g.typeSize(elem) + ", &aster_t)) { aster_runtime_panic(\"copy_to_domain: size overflow\"); }\n")
		b.WriteString("  if (aster_v.len > (uint64_t)0) {\n")
		b.WriteString("    void *aster_p = aster_domain_alloc(aster_d, (size_t)aster_t, (size_t)" +
			g.typeAlign(elem) + ");\n")
		b.WriteString("    if (aster_p == NULL) { aster_runtime_panic(\"copy_to_domain: out of memory\"); }\n")
		b.WriteString("    memcpy(aster_p, aster_v.data, (size_t)aster_t);\n")
		b.WriteString("    aster_v.data = aster_p;\n")
		b.WriteString("  }\n")
	case mir.TypeAggregate:
		for _, fld := range ty.Fields {
			if g.copyTrivial(fld.Type) {
				continue
			}
			b.WriteString("  aster_v.aster_f_" + sanitize(fld.Name) + " = " +
				g.copyCall(fld.Type) + "(aster_d, aster_v.aster_f_" + sanitize(fld.Name) + ");\n")
		}
	case mir.TypeEnum:
		vs := ty.Variants
		for i, v := range vs {
			if v.Payload == mir.TypeUnit || g.copyTrivial(v.Payload) {
				continue
			}
			b.WriteString("  if (aster_v.aster_tag == (uint32_t)" + strconv.Itoa(i) + ") {\n")
			b.WriteString("    aster_v.aster_u.aster_p" + strconv.Itoa(i) + " = " +
				g.copyCall(v.Payload) + "(aster_d, aster_v.aster_u.aster_p" + strconv.Itoa(i) + ");\n")
			b.WriteString("  }\n")
		}
	case mir.TypeOption, mir.TypeResult:
		vs, _ := g.m.VariantsOf(t)
		for i, v := range vs {
			if v.Payload == mir.TypeUnit || g.copyTrivial(v.Payload) {
				continue
			}
			b.WriteString("  if (aster_v.aster_tag == (uint32_t)" + strconv.Itoa(i) + ") {\n")
			b.WriteString("    aster_v.aster_u.aster_p" + strconv.Itoa(i) + " = " +
				g.copyCall(v.Payload) + "(aster_d, aster_v.aster_u.aster_p" + strconv.Itoa(i) + ");\n")
			b.WriteString("  }\n")
		}
	}
	b.WriteString("  return aster_v;\n}\n")
}

// copyCall returns the helper name for a non-trivial copied type.
func (g *gen) copyCall(t mir.TypeId) string {
	return "aster_copy_ty" + strconv.Itoa(int(t))
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
		b.WriteString("typedef struct AsterCtx_" + strconv.Itoa(idx) + " {\n")
		arg := 0
		for _, p := range callee.Params {
			if p.Type == mir.TypeUnit {
				continue
			}
			b.WriteString("  " + g.cType(p.Type) + " aster_f" + strconv.Itoa(arg) + ";\n")
			arg++
		}
		b.WriteString("} AsterCtx_" + strconv.Itoa(idx) + ";\n")
		b.WriteString("static ASTER_MAYBE_UNUSED void aster_cleanup_" + strconv.Itoa(idx) + "(void *aster_ctx) {\n")
		b.WriteString("  AsterCtx_" + strconv.Itoa(idx) + " *aster_c = (AsterCtx_" + strconv.Itoa(idx) + " *)aster_ctx;\n")
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
			b.WriteString("aster_c->aster_f" + strconv.Itoa(arg))
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
		b.WriteString("static ASTER_MAYBE_UNUSED " + g.fnResultType(f) + " " +
			g.fnName(mir.FunctionId(i)) + "(" + g.fnParams(f) + ");\n")
	}
	if len(g.m.Functions) > 0 {
		b.WriteString("\n")
	}
}

// fnName returns the generated C name of a function.
func (g *gen) fnName(id mir.FunctionId) string {
	f := g.m.Functions[id]
	return "aster_fn_" + sanitize(f.Name) + "_" + strconv.Itoa(int(id))
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
		parts = append(parts, g.cType(p.Type)+" aster_v"+strconv.Itoa(i))
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
