package compiler

import (
	"bytes"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
)

const checkerWrapper = `
fn checker_storage_error() -> I32 { return 3 }
fn checker_good(state: State, store: CheckStore) -> I32 {
 if !emit_check_manifest(state, store) { return 4 }
 return 0
}
fn checker_bad(state: State, store: CheckStore) -> I32 {
 if !emit_check_manifest(state, store) { return 4 }
 return 1
}
fn checker_parse_bad(state: State, store: ParseStore) -> I32 {
 if !emit_parse_manifest(state, store) { return 4 }
 return 1
}
fn checker_lex_bad(state: State) -> I32 {
 if !emit(state) { return 4 }
 return 1
}
fn checker_done(state: State, result: CheckResult) -> I32 { return match result {
 CheckGood(store) => checker_good(state, store)
 CheckBad(store) => checker_bad(state, store)
} }
fn checker_check(d: Domain, output: ParseOutput, store: CheckStore) -> I32 { return match check_parsed(d, output.state, output.store, store) {
 Err(error) => checker_storage_error()
 Ok(result) => checker_done(output.state, result)
} }
fn checker_parsed(d: Domain, result: ParseResult, store: CheckStore) -> I32 { return match result {
 ParseGood(output) => checker_check(d, output, store)
 ParseBad(output) => checker_parse_bad(output.state, output.store)
 ParseLexBad(output) => checker_lex_bad(output.state)
} }
fn ci_diag(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec), children: __s0_Buffer(CheckedExprChildRec), returns: __s0_Buffer(CheckedReturnRec)) -> I32 { return match __s0_buffer_new(CheckDiagRec, d) { Err(e) => 3 Ok(b) => match parse_sources(d, state, parse) { Err(e) => 3 Ok(r) => checker_parsed(d, r, CheckStore(symbols: symbols, type_params: params, types: types, type_args: args, type_annotations: annotations, uses: uses, locals: locals, environments: envs, expressions: exprs, expression_children: children, returns: returns, diagnostics: b)) } } }
fn ci_returns(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec), children: __s0_Buffer(CheckedExprChildRec)) -> I32 { return match __s0_buffer_new(CheckedReturnRec, d) { Err(e) => 3 Ok(b) => ci_diag(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,exprs,children,b) } }
fn ci_children(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec)) -> I32 { return match __s0_buffer_new(CheckedExprChildRec, d) { Err(e) => 3 Ok(b) => ci_returns(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,exprs,b) } }
fn ci_exprs(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec)) -> I32 { return match __s0_buffer_new(CheckedExprRec, d) { Err(e) => 3 Ok(b) => ci_children(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,b) } }
fn ci_envs(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec)) -> I32 { return match __s0_buffer_new(EnvironmentRec, d) { Err(e) => 3 Ok(b) => ci_exprs(d,state,parse,symbols,params,types,args,annotations,uses,locals,b) } }
fn ci_locals(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec)) -> I32 { return match __s0_buffer_new(LocalRec, d) { Err(e) => 3 Ok(b) => ci_envs(d,state,parse,symbols,params,types,args,annotations,uses,b) } }
fn ci_uses(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec)) -> I32 { return match __s0_buffer_new(DeclTypeUseRec, d) { Err(e) => 3 Ok(b) => ci_locals(d,state,parse,symbols,params,types,args,annotations,b) } }
fn ci_annotations(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64)) -> I32 { return match __s0_buffer_new(CheckedTypeAnnotationRec, d) { Err(e) => 3 Ok(b) => ci_uses(d,state,parse,symbols,params,types,args,b) } }
fn ci_args(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec)) -> I32 { return match __s0_buffer_new(U64, d) { Err(e) => 3 Ok(b) => ci_annotations(d,state,parse,symbols,params,types,b) } }
fn ci_types(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec)) -> I32 { return match __s0_buffer_new(CheckedTypeRec, d) { Err(e) => 3 Ok(b) => ci_args(d,state,parse,symbols,params,b) } }
fn ci_params(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec)) -> I32 { return match __s0_buffer_new(TypeParamRec, d) { Err(e) => 3 Ok(b) => ci_types(d,state,parse,symbols,b) } }
fn ci_symbols(d: Domain, state: State, parse: ParseStore) -> I32 { return match __s0_buffer_new(SymbolRec, d) { Err(e) => 3 Ok(b) => ci_params(d,state,parse,b) } }
fn pi_diag(d: Domain,state: State,n: __s0_Buffer(SyntaxRec),l: __s0_Buffer(SyntaxLinkRec),r: __s0_Buffer(U64)) -> I32 { return match __s0_buffer_new(ParseDiagRec,d) { Err(e)=>3 Ok(b)=>ci_symbols(d,state,ParseStore(nodes:n,links:l,roots:r,diagnostics:b)) } }
fn pi_roots(d: Domain,state: State,n: __s0_Buffer(SyntaxRec),l: __s0_Buffer(SyntaxLinkRec)) -> I32 { return match __s0_buffer_new(U64,d) { Err(e)=>3 Ok(b)=>pi_diag(d,state,n,l,b) } }
fn pi_links(d: Domain,state: State,n: __s0_Buffer(SyntaxRec)) -> I32 { return match __s0_buffer_new(SyntaxLinkRec,d) { Err(e)=>3 Ok(b)=>pi_roots(d,state,n,b) } }
fn pi_nodes(d: Domain,state: State) -> I32 { return match __s0_buffer_new(SyntaxRec,d) { Err(e)=>3 Ok(b)=>pi_links(d,state,b) } }
fn loaded(d: Domain,state: State) -> I32 { return match load_sources(d,state) { Err(e)=>3 Ok(s)=>pi_nodes(d,s) } }
fn li_diag(d: Domain,p: __s0_Buffer(U8),t: __s0_Buffer(U8),v: __s0_Buffer(U8),s: __s0_Buffer(SourceRec),k: __s0_Buffer(TokenRec)) -> I32 { return match __s0_buffer_new(LexDiagRec,d) { Err(e)=>3 Ok(b)=>loaded(d,State(paths:p,texts:t,values:v,sources:s,tokens:k,diagnostics:b)) } }
fn li_tokens(d: Domain,p: __s0_Buffer(U8),t: __s0_Buffer(U8),v: __s0_Buffer(U8),s: __s0_Buffer(SourceRec)) -> I32 { return match __s0_buffer_new(TokenRec,d) { Err(e)=>3 Ok(b)=>li_diag(d,p,t,v,s,b) } }
fn li_sources(d: Domain,p: __s0_Buffer(U8),t: __s0_Buffer(U8),v: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(SourceRec,d) { Err(e)=>3 Ok(b)=>li_tokens(d,p,t,v,b) } }
fn li_values(d: Domain,p: __s0_Buffer(U8),t: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(U8,d) { Err(e)=>3 Ok(b)=>li_sources(d,p,t,b) } }
fn li_texts(d: Domain,p: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(U8,d) { Err(e)=>3 Ok(b)=>li_values(d,p,b) } }
fn main(d: Domain) -> I32 { return match __s0_buffer_new(U8,d) { Err(e)=>3 Ok(b)=>li_texts(d,b) } }
`

type checkerSource struct {
	id, length int
	path       string
}

type checkerSymbol struct {
	id, kind, node, source, start, end, arity int
}

type checkerTypeParam struct {
	id, owner, node, source, start, end int
}

type checkerType struct {
	id, kind, syntax, target, first, count int
}

type checkerTypeArg struct {
	id, checkedType int
}

type checkerTypeAnnotation struct{ id, owner, syntax, checkedType int }

type checkerTypeUse struct {
	id, owner, role, ordinal, node, source, nameStart, nameEnd, syntax, checkedType int
}

type checkerLocal struct {
	id, owner, kind, syntax, source, nameStart, nameEnd, mutable, checkedType int
}

type checkerEnvironment struct{ id, owner, parent, binding int }

type checkerExpression struct {
	id, owner, syntax, kind, checkedType, parameterUse, boolValue                   int
	left, right, annotation, firstChild, childCount, operator, siteKind, siteSyntax int
}

type checkerExpressionChild struct{ id, expression int }

type checkerReturn struct {
	id, owner, syntax, expression, resultUse int
}

type checkerManifest struct {
	sources      []checkerSource
	sourceByPath map[string]int
	symbols      []checkerSymbol
	params       []checkerTypeParam
	types        []checkerType
	args         []checkerTypeArg
	annotations  []checkerTypeAnnotation
	uses         []checkerTypeUse
	locals       []checkerLocal
	environments []checkerEnvironment
	expressions  []checkerExpression
	children     []checkerExpressionChild
	returns      []checkerReturn
	diagnostics  []checkerDiagnostic
}
type checkerDiagnostic struct {
	kind, source, start, end                int
	hasRelated                              bool
	relatedSource, relatedStart, relatedEnd int
}

func TestAlderCheckerConformanceEndToEnd(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var sources []frontend.Source
	for _, name := range compilerSourceManifest {
		if name != "main.al" && name != "mir_print.al" {
			b, e := os.ReadFile(filepath.Join(root, "compiler", "src", name))
			if e != nil {
				t.Fatal(e)
			}
			sources = append(sources, frontend.Source{ID: frontend.SourceID(len(sources) + 1), Path: "compiler/src/" + name, Text: string(b)})
		}
	}
	checkerText := strings.ReplaceAll(checkerWrapper, " { Err", " {\n Err")
	checkerText = strings.ReplaceAll(checkerText, " 3 Ok", " 3\n Ok")
	checkerText = strings.ReplaceAll(checkerText, " Err(", "\n Err(")
	checkerText = strings.ReplaceAll(checkerText, " Ok(", "\n Ok(")
	sources = append(sources, frontend.Source{ID: 99, Path: "compiler/test/checker_main.al", Text: checkerText})
	// This slice compiles its fixed checker closure. The production driver and
	// independent MIR printer are covered by their owning harnesses. Round-trip and verify its
	// textual MIR before generating the C used for strict direct execution.
	compiled, err := Compile(Request{Sources: sources, Emit: EmitMIR})
	if err != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		t.Fatalf("compile checker MIR: result=%+v error=%v", compiled, err)
	}
	module, err := mir.Parse(compiled.Artifact.Text)
	if err != nil {
		t.Fatalf("parse checker MIR: %v", err)
	}
	for _, name := range []string{"collect_cycle_edges", "reject_value_cycles", "interpreted_type_equal", "interpreted_may_reach_ancestry", "direct_type_concrete", "interpreted_contains_reference", "interpreted_map_key_ok", "validate_concrete_type", "revalidate_aggregate_roots"} {
		id, ok := module.Function(name)
		if !ok {
			t.Fatalf("checker MIR has no %s function", name)
		}
		for _, block := range module.Functions[id].Blocks {
			for _, instruction := range block.Instrs {
				if instruction.Op == mir.OpCall && instruction.Callee == id {
					t.Fatalf("%s recursively calls itself", name)
				}
			}
		}
	}
	// GenerateProgram reruns the complete verifier before lowering.
	generated, err := cgen.GenerateProgram(module)
	if err != nil {
		t.Fatalf("generate checker C: %v", err)
	}
	dir := t.TempDir()
	cf := filepath.Join(dir, "checker.c")
	exe := filepath.Join(dir, "checker.exe")
	if err = os.WriteFile(cf, []byte(generated), 0644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cf, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if out, e := exec.Command(cc, args...).CombinedOutput(); e != nil {
		t.Fatalf("strict C11: %v\n%s", e, out)
	}

	good := map[string]string{
		"a space.al": "import c foreign: fn(U64, Ptr(U8),) -> I32\n" +
			"type Box(T: type) { value: T }\n" +
			"type Nest {\n x: Map(U64, Option(U8))\n a: [U8]\n b: Result(U64, __s0_Error)\n c: Ptr(Domain)\n d: __s0_Buffer(U64)\n mark: DomainMark\n text: String\n}\n" +
			"enum E {\n Empty\n Full(value: Box(U64))\n}\n" +
			"fn f(T: type, x: T, y: Box(T),) -> Option(U64) {}\n" +
			"type Other(T: type) { value: T }\n" +
			"fn deferred() -> U64 {\n let local = f()\n return wrong\n}\n",
		"b.al": "type Forward { x: Later }\n" +
			"type Later { x: U64 }\n" +
			"type Recursive { pointer: Ptr(Recursive) }\n",
	}
	for i := 0; i < 64; i++ {
		good["b.al"] += fmt.Sprintf("type X%02d(T: type) { x: Option(T) }\n", i)
	}
	one := runAlderChecker(t, exe, good, []string{"b.al", "a space.al"}, false)
	two := runAlderChecker(t, exe, good, []string{"a space.al", "b.al"}, false)
	if one != two {
		t.Fatal("success manifest changed with argv order")
	}
	manifest := parseCheckerManifest(t, one, good)
	assertCheckerSuccessManifest(t, manifest, good)
	var deep strings.Builder
	for i := 0; i < 40; i++ {
		field := "U64"
		if i+1 < 40 {
			field = fmt.Sprintf("Chain%02d", i+1)
		}
		fmt.Fprintf(&deep, "type Chain%02d { next: %s }\n", i, field)
	}
	deep.WriteString("type Diamond { left: Left\n right: Right }\ntype Left { value: Leaf }\ntype Right { value: Leaf }\ntype Leaf { value: U64 }\n")
	deep.WriteString("type Phantom(T: type) { value: U64 }\ntype ThroughArg { value: Phantom(ThroughArg) }\n")
	deep.WriteString("type Cut { option: Option(Ptr(Cut))\n result: Result(U64, U64)\n map: Map(U64, U64) }\n")
	deepFiles := map[string]string{"deep.al": deep.String()}
	parseCheckerManifest(t, runAlderChecker(t, exe, deepFiles, []string{"deep.al"}, false), deepFiles)

	genericGood := map[string]string{
		"a.al": "type Concrete {\n outer: Outer(U64)\n bool_key: Map(Bool, U64)\n u8_key: Map(U8, U64)\n u16_key: Map(U16, U64)\n u32_key: Map(U32, U64)\n u64_key: Map(U64, U64)\n nested_key: Map(PairKey(U8, PairKey(Bool, U64)), U64)\n nested_box: CallerBox(CallerBox(U64))\n node: Node(U64)\n same: Same(U64)\n mutual: Left(U64)\n pointer_cut: PointerBox(Concrete)\n phantom: Phantom(String)\n sugar_one: StringSliceOne(String)\n sugar_two: StringSliceTwo([U8])\n sugar_relay: StringRelayRoot(String)\n}\n",
		"z.al": "type Key(T: type) { value: T }\n" +
			"type PairKey(A: type, B: type) { first: A\n second: B }\n" +
			"type CallerBox(T: type) { value: T }\n" +
			"type Transparent(T: type) { value: Key(T) }\n" +
			"enum Choice(T: type) { None\n Some(value: T) }\n" +
			"type Inner(T: type) { values: __s0_Buffer(T) }\n" +
			"type Outer(T: type) { key: Map(Key(T), Choice(T))\n inner: Inner(T) }\n" +
			"type Node(T: type) { next: Ptr(Node(T))\n value: T }\n" +
			"type Same(T: type) { next: Ptr(Same(U64)) }\n" +
			"type Left(T: type) { right: Ptr(Right(T)) }\n" +
			"type Right(T: type) { left: Ptr(Left(T)) }\n" +
			"type PointerBox(T: type) { value: Ptr(T) }\n" +
			"type Phantom(T: type) { value: U64 }\n" +
			"type StringSliceOne(T: type) { next: Ptr(StringSliceOne([U8])) }\n" +
			"type StringSliceTwo(T: type) { next: Ptr(StringSliceTwo(String)) }\n" +
			"type StringRelayRoot(T: type) { next: Ptr(StringRelayOne([U8])) }\n" +
			"type StringRelayOne(T: type) { next: Ptr(StringRelayTwo(T)) }\n" +
			"type StringRelayTwo(T: type) { next: Ptr(StringRelayRoot(T)) }\n",
	}
	genericOne := runAlderChecker(t, exe, genericGood, []string{"z.al", "a.al"}, false)
	genericTwo := runAlderChecker(t, exe, genericGood, []string{"a.al", "z.al"}, false)
	if genericOne != genericTwo {
		t.Fatal("generic revalidation changed with argv order")
	}
	parseCheckerManifest(t, genericOne, genericGood)

	var substitutionGrowth strings.Builder
	for i := 0; i < 64; i++ {
		field := "T"
		if i != 0 {
			field = fmt.Sprintf("G%02d(T)", i-1)
		}
		fmt.Fprintf(&substitutionGrowth, "type G%02d(T: type) { value: %s }\n", i, field)
	}
	substitutionGrowth.WriteString("type Root { value: G63(U64) }\n")
	growthFiles := map[string]string{"growth.al": substitutionGrowth.String()}
	parseCheckerManifest(t, runAlderChecker(t, exe, growthFiles, []string{"growth.al"}, false), growthFiles)
	var layeredDAG strings.Builder
	layeredDAG.WriteString("type PhantomLeaf(T: type) { value: U64 }\ntype DivergentLeaf { first: PhantomLeaf(U64)\n second: PhantomLeaf(U8) }\n")
	for i := 0; i <= 24; i++ {
		field := "DivergentLeaf"
		if i != 0 {
			field = fmt.Sprintf("D%02d", i-1)
		}
		fmt.Fprintf(&layeredDAG, "type D%02d { left: %s\n right: %s }\n", i, field, field)
	}
	dagFiles := map[string]string{"dag.al": layeredDAG.String()}
	parseCheckerManifest(t, runAlderChecker(t, exe, dagFiles, []string{"dag.al"}, false), dagFiles)
	var compactEquality strings.Builder
	compactEquality.WriteString("type EqualityPhantom(T: type) { value: U64 }\ntype EqualityLeaf(T: type) { left: EqualityPhantom(T)\n right: EqualityPhantom(T) }\n")
	for i := 0; i <= 24; i++ {
		field := "EqualityLeaf(T)"
		if i != 0 {
			field = fmt.Sprintf("S%02d(Result(T, T))", i-1)
		}
		fmt.Fprintf(&compactEquality, "type S%02d(T: type) { value: %s }\n", i, field)
	}
	compactEquality.WriteString("type EqualityRoot { value: S24(U64) }\n")
	equalityFiles := map[string]string{"equality.al": compactEquality.String()}
	parseCheckerManifest(t, runAlderChecker(t, exe, equalityFiles, []string{"equality.al"}, false), equalityFiles)
	var compactInterpretation strings.Builder
	compactInterpretation.WriteString("type G00(T: type) { value: T\n items: [T] }\n")
	for i := 1; i <= 24; i++ {
		fmt.Fprintf(&compactInterpretation, "type G%02d(T: type) { value: G%02d(Result(T, T)) }\n", i, i-1)
	}
	compactInterpretation.WriteString("type InterpretationRoot { value: G24(U64) }\n")
	interpretationFiles := map[string]string{"interpretation.al": compactInterpretation.String()}
	parseCheckerManifest(t, runAlderChecker(t, exe, interpretationFiles, []string{"interpretation.al"}, false), interpretationFiles)
	ffiGood := map[string]string{"ffi.al": "import c primitive_ffi: fn(Bool, I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Unit, Ptr(F64)) -> Unit\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, ffiGood, []string{"ffi.al"}, false), ffiGood)
	canonicalGood := map[string]string{"canonical.al": "type Shared { first: Option(U64)\n second: Option(U64)\n text: String\n bytes: [U8] }\n"}
	canonicalManifest := parseCheckerManifest(t, runAlderChecker(t, exe, canonicalGood, []string{"canonical.al"}, false), canonicalGood)
	shared := checkerSymbolByName(t, canonicalManifest, canonicalGood, "Shared")
	canonicalFirst, canonicalSecond := checkerUse(t, canonicalManifest, shared.id, 1, 0), checkerUse(t, canonicalManifest, shared.id, 1, 1)
	text, bytesUse := checkerUse(t, canonicalManifest, shared.id, 1, 2), checkerUse(t, canonicalManifest, shared.id, 1, 3)
	if canonicalFirst.checkedType != canonicalSecond.checkedType || canonicalFirst.syntax == canonicalSecond.syntax || text.checkedType != bytesUse.checkedType || text.syntax == bytesUse.syntax {
		t.Fatalf("canonical types did not deduplicate while retaining uses: first=%+v second=%+v text=%+v bytes=%+v", canonicalFirst, canonicalSecond, text, bytesUse)
	}
	functionNameGood := map[string]string{"functions.al": "fn helper() -> U64 {}\nfn use(T: type, helper: T, T: T) -> T {}\nfn main(value: U64) -> Bool {}\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, functionNameGood, []string{"functions.al"}, false), functionNameGood)
	bodyGood := map[string]string{
		"a.al": "type Pair(T: type) { value: T }\n" +
			"fn identity(value: U64) -> U64 { return value }\n" +
			"fn choose(first: I64, second: U64) -> U64 { return second }\n" +
			"fn string_to_slice(value: String) -> [U8] { return value }\n" +
			"fn slice_to_string(value: [U8]) -> String { return value }\n" +
			"fn declared(value: Pair(U64)) -> Pair(U64) { return value }\n" +
			"fn done() -> Unit { return }\n" +
			"fn yes() -> Bool { return true }\n" +
			"fn no() -> Bool { return false }\n" +
			"fn literal() -> U64 { return 1 }\n" +
			"fn u8_max() -> U8 { return 255 }\n" +
			"fn u64_max() -> U64 { return 18446744073709551615 }\n" +
			"fn i64_min() -> I64 { return -9223372036854775808 }\n" +
			"fn leading_zeros() -> U64 { return 007 }\n" +
			"fn neg_zero() -> U8 { return -0 }\n" +
			"fn greeting() -> String { return \"hello\" }\n" +
			"fn raw() -> [U8] { return \"bytes\" }\n" +
			"fn empty_string() -> String { return \"\" }\n" +
			"fn local_param(value: U64) -> U64 { let x: U64 = value\n return x }\n" +
			"fn local_assign() -> U64 { var y: U64 = 5\n y = 7\n return y }\n" +
			"fn local_literal() -> I64 { let z: I64 = -3\n return z }\n" +
			"fn local_string(value: String) -> [U8] { let s: String = value\n return s }\n",
		"z.al": "",
	}
	for i := 0; i < 20; i++ {
		bodyGood["z.al"] += fmt.Sprintf("fn copy%02d(value: U64) -> U64 { return value }\n", i)
	}
	bodyOne := runAlderChecker(t, exe, bodyGood, []string{"z.al", "a.al"}, false)
	bodyTwo := runAlderChecker(t, exe, bodyGood, []string{"a.al", "z.al"}, false)
	if bodyOne != bodyTwo {
		t.Fatal("checked body manifest changed with argv order")
	}
	bodyManifest := parseCheckerManifest(t, bodyOne, bodyGood)
	if len(bodyManifest.expressions) != 45 || len(bodyManifest.returns) != 41 {
		t.Fatalf("body records: expressions=%d returns=%d, want 45/41", len(bodyManifest.expressions), len(bodyManifest.returns))
	}
	for i, expression := range bodyManifest.expressions {
		if expression.id != i+1 || i > 0 && expression.owner < bodyManifest.expressions[i-1].owner {
			t.Fatalf("body expressions are not in canonical function order: %+v", bodyManifest.expressions)
		}
	}
	for i, checkedReturn := range bodyManifest.returns {
		if checkedReturn.id != i+1 || i > 0 && checkedReturn.owner <= bodyManifest.returns[i-1].owner {
			t.Fatalf("checked returns are not in canonical function order: %+v", bodyManifest.returns)
		}
	}
	for _, name := range []string{"identity", "choose", "string_to_slice", "slice_to_string", "declared"} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		checkedReturn := checkerReturnForOwner(t, bodyManifest, owner.id)
		if checkedReturn.expression == 0 || bodyManifest.expressions[checkedReturn.expression-1].owner != owner.id {
			t.Fatalf("function %s has invalid checked return %+v", name, checkedReturn)
		}
	}
	choose := checkerSymbolByName(t, bodyManifest, bodyGood, "choose")
	chooseExpression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, choose.id).expression-1]
	if parameter := bodyManifest.locals[chooseExpression.parameterUse-1]; chooseExpression.kind != 1 || chooseExpression.boolValue != 0 || parameter.kind != 1 || checkerSourceText(bodyManifest, bodyGood, parameter.source, parameter.nameStart, parameter.nameEnd) != "second" {
		t.Fatalf("multi-parameter return resolved the wrong binding: %+v", parameter)
	}
	stringToSlice := checkerSymbolByName(t, bodyManifest, bodyGood, "string_to_slice")
	stringExpression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, stringToSlice.id).expression-1]
	if bodyManifest.types[stringExpression.checkedType-1].kind != 8 || stringExpression.checkedType != checkerUse(t, bodyManifest, stringToSlice.id, 6, 0).checkedType {
		t.Fatal("String parameter was not accepted as a [U8] return")
	}
	sliceToString := checkerSymbolByName(t, bodyManifest, bodyGood, "slice_to_string")
	sliceExpression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, sliceToString.id).expression-1]
	if bodyManifest.types[sliceExpression.checkedType-1].kind != 8 || sliceExpression.checkedType != checkerUse(t, bodyManifest, sliceToString.id, 6, 0).checkedType {
		t.Fatal("[U8] parameter was not accepted as a String return")
	}
	done := checkerSymbolByName(t, bodyManifest, bodyGood, "done")
	if checkedReturn := checkerReturnForOwner(t, bodyManifest, done.id); checkedReturn.expression != 0 {
		t.Fatalf("bare Unit return has expression %d", checkedReturn.expression)
	}
	for name, value := range map[string]int{"yes": 1, "no": 0} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		checkedReturn := checkerReturnForOwner(t, bodyManifest, owner.id)
		expression := bodyManifest.expressions[checkedReturn.expression-1]
		result := checkerUse(t, bodyManifest, owner.id, 6, 0)
		if expression.kind != 2 || expression.parameterUse != 0 || expression.boolValue != value || expression.checkedType != result.checkedType || bodyManifest.types[expression.checkedType-1].kind != 1 {
			t.Fatalf("Bool return %s has invalid expression/result records: expression=%+v result=%+v", name, expression, result)
		}
	}
	// u64_max and i64_min pin full-width bounds that Stage 0 signed host
	// storage cannot represent; the checker range proof uses digit text.
	for _, name := range []string{"literal", "u8_max", "u64_max", "i64_min", "leading_zeros", "neg_zero"} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		checkedReturn := checkerReturnForOwner(t, bodyManifest, owner.id)
		expression := bodyManifest.expressions[checkedReturn.expression-1]
		result := checkerUse(t, bodyManifest, owner.id, 6, 0)
		if expression.kind != 3 || expression.parameterUse != 0 || expression.boolValue != 0 || expression.checkedType != result.checkedType || bodyManifest.types[expression.checkedType-1].kind != 1 {
			t.Fatalf("integer return %s has invalid expression/result records: expression=%+v result=%+v", name, expression, result)
		}
	}
	// Local returns resolve their LocalRec in canonical statement order.
	for _, name := range []string{"local_param", "local_assign", "local_literal", "local_string"} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		expression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, owner.id).expression-1]
		local := bodyManifest.locals[expression.parameterUse-1]
		if expression.kind != 5 || expression.boolValue != 0 || local.owner != owner.id || local.checkedType != expression.checkedType {
			t.Fatalf("local return %s has invalid records: expression=%+v local=%+v", name, expression, local)
		}
	}
	localAssign := checkerSymbolByName(t, bodyManifest, bodyGood, "local_assign")
	localAssignExpr := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, localAssign.id).expression-1]
	if local := bodyManifest.locals[localAssignExpr.parameterUse-1]; local.mutable != 1 || checkerSourceText(bodyManifest, bodyGood, local.source, local.nameStart, local.nameEnd) != "y" {
		t.Fatalf("mutable local lost its flag or name: %+v", local)
	}
	localString := checkerSymbolByName(t, bodyManifest, bodyGood, "local_string")
	localStringExpr := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, localString.id).expression-1]
	if bodyManifest.types[localStringExpr.checkedType-1].kind != 8 || localStringExpr.checkedType != checkerUse(t, bodyManifest, localString.id, 6, 0).checkedType {
		t.Fatal("String local was not accepted as a [U8] return")
	}
	// String and [U8] are one semantic type for a decoded string literal.
	for _, name := range []string{"greeting", "raw", "empty_string"} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		checkedReturn := checkerReturnForOwner(t, bodyManifest, owner.id)
		expression := bodyManifest.expressions[checkedReturn.expression-1]
		result := checkerUse(t, bodyManifest, owner.id, 6, 0)
		resultKind := bodyManifest.types[expression.checkedType-1].kind
		if expression.kind != 4 || expression.parameterUse != 0 || expression.boolValue != 0 || expression.checkedType != result.checkedType || (resultKind != 2 && resultKind != 8) {
			t.Fatalf("string return %s has invalid expression/result records: expression=%+v result=%+v", name, expression, result)
		}
	}
	bodyDeferred := map[string]string{"deferred.al": "type Thing { value: U64 }\n" +
		"enum Choice { Red }\n" +
		"fn helper() -> U64 {}\n" +
		"fn partial() -> U64 { let scalar = 1\n let complete: Option(U64) = helper()\n return scalar }\n" +
		"fn generic(T: type, value: T) -> T { return missing }\n" +
		"fn generic_bool(T: type) -> Bool { return true }\n" +
		"fn empty() -> U64 {}\n" +
		"fn float_literal() -> F64 { return 1.5 }\n" +
		"fn call() -> U64 { return helper() }\n" +
		"fn nested(value: U64) -> U64 { { return value } }\n" +
		"fn two(value: U64) -> U64 { return value\n return value }\n" +
		"fn function_name() -> U64 { return helper }\n" +
		"fn type_name() -> Thing { return Thing }\n" +
		"fn variant() -> Choice { return Red }\n" +
		"fn builtin() -> U64 { return len }\n"}
	deferredManifest := parseCheckerManifest(t, runAlderChecker(t, exe, bodyDeferred, []string{"deferred.al"}, false), bodyDeferred)
	hasDeferredOption := false
	for _, checked := range deferredManifest.types {
		hasDeferredOption = hasDeferredOption || checked.kind == 9
	}
	if len(deferredManifest.expressions) != 0 || len(deferredManifest.children) != 0 || len(deferredManifest.returns) != 0 || len(deferredManifest.locals) != 0 || len(deferredManifest.environments) != 0 || len(deferredManifest.args) != 0 || hasDeferredOption {
		t.Fatalf("unsupported bodies emitted records: types=%d args=%d locals=%d envs=%d expressions=%d children=%d returns=%d", len(deferredManifest.types), len(deferredManifest.args), len(deferredManifest.locals), len(deferredManifest.environments), len(deferredManifest.expressions), len(deferredManifest.children), len(deferredManifest.returns))
	}
	bodyFailure := map[string]string{"body.al": "fn good(value: U64) -> U64 { return value }\nfn bad(value: U64) -> I64 { return value }\n"}
	bodyFailureManifest := parseCheckerManifest(t, runAlderChecker(t, exe, bodyFailure, []string{"body.al"}, true), bodyFailure)
	if len(bodyFailureManifest.expressions) != 1 || len(bodyFailureManifest.returns) != 1 || checkerSourceText(bodyFailureManifest, bodyFailure, bodyFailureManifest.symbols[bodyFailureManifest.expressions[0].owner-1].source, bodyFailureManifest.symbols[bodyFailureManifest.expressions[0].owner-1].start, bodyFailureManifest.symbols[bodyFailureManifest.expressions[0].owner-1].end) != "good" {
		t.Fatalf("body failure retained an incomplete record prefix: expressions=%+v returns=%+v", bodyFailureManifest.expressions, bodyFailureManifest.returns)
	}
	badReturn := strings.LastIndex(bodyFailure["body.al"], "return")
	assertCheckerDiagnostic(t, bodyFailureManifest, 19, "body.al", badReturn, badReturn+len("return"), "", -1, -1)
	bodyBoolFailure := map[string]string{"bool-body.al": "fn good() -> Bool { return false }\nfn bad() -> U64 { return true }\n"}
	bodyBoolFailureManifest := parseCheckerManifest(t, runAlderChecker(t, exe, bodyBoolFailure, []string{"bool-body.al"}, true), bodyBoolFailure)
	if len(bodyBoolFailureManifest.expressions) != 1 || len(bodyBoolFailureManifest.returns) != 1 || bodyBoolFailureManifest.expressions[0].kind != 2 || bodyBoolFailureManifest.expressions[0].boolValue != 0 || checkerSourceText(bodyBoolFailureManifest, bodyBoolFailure, bodyBoolFailureManifest.symbols[bodyBoolFailureManifest.expressions[0].owner-1].source, bodyBoolFailureManifest.symbols[bodyBoolFailureManifest.expressions[0].owner-1].start, bodyBoolFailureManifest.symbols[bodyBoolFailureManifest.expressions[0].owner-1].end) != "good" {
		t.Fatalf("Bool body failure retained an incomplete record prefix: expressions=%+v returns=%+v", bodyBoolFailureManifest.expressions, bodyBoolFailureManifest.returns)
	}
	badBoolReturn := strings.LastIndex(bodyBoolFailure["bool-body.al"], "return")
	assertCheckerDiagnostic(t, bodyBoolFailureManifest, 19, "bool-body.al", badBoolReturn, badBoolReturn+len("return"), "", -1, -1)
	bodyOrderFiles := map[string]string{
		"z.al": "fn zed(value: U64) -> I64 { return value }\n",
		"a.al": "fn alpha() -> U64 { return missing }\n",
	}
	bodyOrderOne := runAlderChecker(t, exe, bodyOrderFiles, []string{"z.al", "a.al"}, true)
	bodyOrderTwo := runAlderChecker(t, exe, bodyOrderFiles, []string{"a.al", "z.al"}, true)
	if bodyOrderOne != bodyOrderTwo {
		t.Fatal("body first failure changed with argv order")
	}
	bodyOrderManifest := parseCheckerManifest(t, bodyOrderOne, bodyOrderFiles)
	unknown := strings.Index(bodyOrderFiles["a.al"], "missing")
	assertCheckerDiagnostic(t, bodyOrderManifest, 18, "a.al", unknown, unknown+len("missing"), "", -1, -1)

	operatorGood := map[string]string{
		"operators.al": "fn negate(value: I64) -> I64 { return -value }\n" +
			"fn logical_not(value: Bool) -> Bool { return !value }\n" +
			"fn arithmetic(a: I64, b: I64) -> I64 { return (a + b) - (a * b) / (b % a) }\n" +
			"fn shifts(value: U64, count: U64) -> U64 { return (value << count) >> count }\n" +
			"fn comparisons(a: I64, b: I64) -> Bool { return (a == b || a != b) && (a < b || a <= b) && (a > b || a >= b) }\n" +
			"fn float_comparison(a: F64, b: F64) -> Bool { return a <= b }\n" +
			"fn full_width(value: U64) -> U64 { return value + 18446744073709551615 }\n" +
			"fn signed_min(value: I64) -> I64 { return value + -9223372036854775808 }\n" +
			"fn inferred(value: I64) -> Bool { let integer = 1\n let truth = true\n let text = \"scalar\"\n let copied = value\n let nested = -copied + integer\n return truth }\n" +
			"fn inferred_mutable() -> I64 { var value = 1\n value = value + 2\n return value }\n" +
			"fn contexts(a: I64, b: I64) -> I64 { let x: I64 = -a + b\n var y: I64 = x << b\n y = y - a\n return y }\n",
		"z.al": "fn ordered(a: U64, b: U64) -> U64 { return a + b }\n",
	}
	operatorOne := runAlderChecker(t, exe, operatorGood, []string{"z.al", "operators.al"}, false)
	operatorTwo := runAlderChecker(t, exe, operatorGood, []string{"operators.al", "z.al"}, false)
	if operatorOne != operatorTwo {
		t.Fatal("recursive operator manifest changed across processes")
	}
	operatorManifest := parseCheckerManifest(t, operatorOne, operatorGood)
	seenOperators := make(map[int]bool)
	seenSites := make(map[int]bool)
	for _, expression := range operatorManifest.expressions {
		seenOperators[expression.operator] = true
		seenSites[expression.siteKind] = true
	}
	for operator := 1; operator <= 17; operator++ {
		if !seenOperators[operator] {
			t.Fatalf("operator %d has no checked expression", operator)
		}
	}
	for site := 1; site <= 3; site++ {
		if !seenSites[site] {
			t.Fatalf("expression site kind %d is not represented", site)
		}
	}
	contexts := checkerSymbolByName(t, operatorManifest, operatorGood, "contexts")
	if root := operatorManifest.expressions[checkerReturnForOwner(t, operatorManifest, contexts.id).expression-1]; root.kind != 5 || root.siteKind != 3 {
		t.Fatalf("operator context return has invalid root: %+v", root)
	}

	operatorRejects := []struct {
		name, text, marker string
		kind               int
	}{
		{name: "operator-not.al", text: "fn f(value: I64) -> Bool { return !value }\n", marker: "!", kind: 29},
		{name: "operator-negate-unsigned.al", text: "fn f(value: U64) -> U64 { return -value }\n", marker: "-", kind: 30},
		{name: "operator-negate-bool.al", text: "fn f(value: Bool) -> Bool { return -value }\n", marker: "-", kind: 31},
		{name: "operator-bool.al", text: "fn f(a: I64, b: I64) -> Bool { return a && b }\n", marker: "&&", kind: 32},
		{name: "operator-shift-left.al", text: "fn f(a: Bool, b: Bool) -> Bool { return a << b }\n", marker: "<<", kind: 33},
		{name: "operator-shift-count.al", text: "fn f(a: I64, b: U64) -> I64 { return a << b }\n", marker: "<<", kind: 34},
		{name: "operator-comparison-mismatch.al", text: "fn f(a: I64, b: U64) -> Bool { return a == b }\n", marker: "==", kind: 35},
		{name: "operator-comparison-type.al", text: "fn f(a: Bool, b: Bool) -> Bool { return a == b }\n", marker: "==", kind: 36},
		{name: "operator-arithmetic-type.al", text: "fn f(a: Bool, b: Bool) -> Bool { return a + b }\n", marker: "+", kind: 37},
		{name: "operator-float-arithmetic.al", text: "fn f(a: F64, b: F64) -> F64 { return a + b }\n", marker: "+", kind: 37},
		{name: "operator-arithmetic-mismatch.al", text: "fn f(a: I64, b: U64) -> I64 { return a + b }\n", marker: "+", kind: 38},
	}
	for _, tc := range operatorRejects {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name: tc.text}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name}, true), files)
			at := strings.LastIndex(tc.text, tc.marker)
			assertCheckerDiagnostic(t, manifest, tc.kind, tc.name, at, at+len(tc.marker), "", -1, -1)
			if len(manifest.expressions) != 0 || len(manifest.returns) != 0 {
				t.Fatalf("operator failure retained a partial graph: expressions=%+v returns=%+v", manifest.expressions, manifest.returns)
			}
		})
	}

	rejects := []struct {
		name, text, marker, relatedMarker string
		kind                              int
		last                              bool
	}{
		{name: "duplicate-kind.al", text: "type A {}\ntype A {}\n", kind: 1, marker: "A", relatedMarker: "A", last: true},
		{name: "duplicate-cross.al", text: "type A {}\nfn A() -> U64 {}\n", kind: 1, marker: "A", relatedMarker: "A", last: true},
		{name: "param.al", text: "type Box(T: type, T: type) {}\n", kind: 3, marker: "T", relatedMarker: "T", last: true},
		{name: "unknown.al", text: "type A { x: Missing }\n", kind: 4, marker: "Missing"},
		{name: "import-type.al", text: "import c Foreign: fn(U64) -> U64\ntype A { x: Foreign }\n", kind: 4, marker: "Foreign", last: true},
		{name: "function-type.al", text: "fn F() -> U64 {}\ntype A { x: F }\n", kind: 4, marker: "F", last: true},
		{name: "leak.al", text: "type A(T: type) {}\ntype B { x: T }\n", kind: 4, marker: "T", last: true},
		{name: "option-arity.al", text: "type A { x: Option() }\n", kind: 5, marker: "Option"},
		{name: "result-arity.al", text: "type A { x: Result(U64) }\n", kind: 5, marker: "Result"},
		{name: "map-arity.al", text: "type A { x: Map(U64) }\n", kind: 5, marker: "Map"},
		{name: "ptr-arity.al", text: "type A { x: Ptr() }\n", kind: 5, marker: "Ptr"},
		{name: "buffer-arity.al", text: "type A { x: __s0_Buffer() }\n", kind: 5, marker: "__s0_Buffer"},
		{name: "generic-arity.al", text: "type Box(T: type) {}\ntype A { x: Box() }\n", kind: 5, marker: "Box", last: true},
		{name: "applied-t.al", text: "type A(T: type) { x: T(U64) }\n", kind: 4, marker: "T", last: true},
		{name: "duplicate-field.al", text: "type A { x: U64\n x: U8 }\n", kind: 6, marker: "type"},
		{name: "duplicate-variant.al", text: "enum A { X\n X(value: U64) }\n", kind: 7, marker: "enum"},
		{name: "empty-enum.al", text: "enum A {}\n", kind: 8, marker: "enum"},
		{name: "interleaved-type-order.al", text: "enum First { X\n X }\ntype Later { x: U64\n x: U8 }\n", kind: 7, marker: "enum"},
		{name: "shape-before-cycle.al", text: "type Cyclic { x: Cyclic }\nenum Empty {}\n", kind: 8, marker: "enum"},
		{name: "cycle-before-import.al", text: "import c bad: fn(Missing) -> U64\ntype Cyclic { x: Cyclic }\n", kind: 9, marker: "type"},
		{name: "import-before-function.al", text: "fn earlier() -> Missing {}\nimport c bad: fn(Nope) -> U64\n", kind: 15, marker: "import"},
		{name: "self-cycle.al", text: "type A { x: A }\n", kind: 9, marker: "type"},
		{name: "enum-payload-cycle.al", text: "enum A { Wrap(value: A) }\n", kind: 9, marker: "enum"},
		{name: "option-cycle.al", text: "type A { x: Option(A) }\n", kind: 9, marker: "type"},
		{name: "result-ok-cycle.al", text: "type A { x: Result(A, U64) }\n", kind: 9, marker: "type"},
		{name: "result-err-cycle.al", text: "type A { x: Result(U64, A) }\n", kind: 9, marker: "type"},
		{name: "map-key-cycle.al", text: "type A { x: Map(A, U64) }\n", kind: 9, marker: "type"},
		{name: "map-value-cycle.al", text: "type A { x: Map(U64, A) }\n", kind: 9, marker: "type"},
		{name: "two-cycle.al", text: "type A { x: B }\ntype B { x: A }\n", kind: 9, marker: "type"},
		{name: "generic-target-cycle.al", text: "type Box(T: type) { x: A }\ntype A { x: Box(U64) }\n", kind: 9, marker: "type"},
		{name: "substituted-value-cycle.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Root) }\n", kind: 9, marker: "type", last: true},
		{name: "nested-substituted-value-cycle.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(Root)) }\n", kind: 9, marker: "type", last: true},
		{name: "cycle-owner-memo.al", text: "type Leaf(T: type) { value: T }\ntype A { value: Leaf(B) }\ntype B { value: Leaf(B) }\n", kind: 9, marker: "type", last: true},
		{name: "generic-substituted-value-cycle.al", text: "type Loop(T: type) { value: Box(Loop(T)) }\ntype Box(T: type) { value: T }\n", kind: 9, marker: "type"},
		{name: "substituted-cycle-before-forward-restriction.al", text: "type Root { value: Box(Root) }\ntype Box(T: type) { bad: Map(T, U64)\n value: T }\n", kind: 9, marker: "type"},
		{name: "substituted-cycle-sibling.al", text: "type Pair(T: type) { left: Box(T)\n right: Box(Root) }\ntype Box(T: type) { value: T }\ntype Root { value: Pair(U64) }\n", kind: 9, marker: "type"},
		{name: "nested-string-slice.al", text: "type A { x: [String] }\n", kind: 10, marker: "["},
		{name: "substituted-slice.al", text: "type Box(T: type) { x: [T] }\ntype A { x: Box(String) }\n", kind: 10, marker: "Box", last: true},
		{name: "multi-substituted-slice.al", text: "type Leaf(T: type) { x: [T] }\ntype Middle(T: type) { x: Leaf(T) }\ntype A { x: Middle(String) }\n", kind: 10, marker: "Middle", last: true},
		{name: "caller-ancestry-slice.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box([String])) }\n", kind: 10, marker: "["},
		{name: "inherited-ancestry-forward-slice.al", text: "type Inner(T: type) { value: T }\ntype Outer { value: Inner([Later]) }\ntype Later { text: String }\ntype Root { value: Outer }\n", kind: 10, marker: "Outer", last: true},
		{name: "shared-specialization-slice.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: [Pair(String)] }\n", kind: 10, marker: "["},
		{name: "recursive-slice.al", text: "type A { x: [A] }\n", kind: 10, marker: "["},
		{name: "buffer-string.al", text: "type A { x: __s0_Buffer(String) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "substituted-buffer.al", text: "type Box(T: type) { x: __s0_Buffer(T) }\ntype A { x: Box(String) }\n", kind: 11, marker: "Box", last: true},
		{name: "caller-ancestry-buffer.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(__s0_Buffer(String))) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "shared-specialization-buffer.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: __s0_Buffer(Pair(String)) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "recursive-buffer.al", text: "type A { x: __s0_Buffer(A) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "map-key-before-value.al", text: "type Pair(K: type, V: type) { x: Map(K, V) }\ntype A { x: Pair(I64, String) }\n", kind: 12, marker: "Pair", last: true},
		{name: "map-key-float.al", text: "type A { x: Map(F64, U64) }\n", kind: 12, marker: "Map"},
		{name: "map-key-generic.al", text: "type Key(T: type) { x: T }\ntype A { x: Map(Key(I64), String) }\n", kind: 12, marker: "Map"},
		{name: "caller-ancestry-map-key.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(Map(I64, U64))) }\n", kind: 12, marker: "Map"},
		{name: "shared-specialization-map-key.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: Map(Pair(I64), U64) }\n", kind: 12, marker: "Map"},
		{name: "substituted-map-value.al", text: "type Pair(K: type, V: type) { x: Map(K, V) }\ntype A { x: Pair(U64, String) }\n", kind: 13, marker: "Pair", last: true},
		{name: "declared-map-value.al", text: "type Value(T: type) { x: T }\ntype A { x: Map(U64, Value(String)) }\n", kind: 13, marker: "Map"},
		{name: "caller-ancestry-map-value.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(Map(U64, String))) }\n", kind: 13, marker: "Map"},
		{name: "shared-specialization-map-value.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: Map(U64, Pair(String)) }\n", kind: 13, marker: "Map"},
		{name: "struct-member-order.al", text: "type Fields(T: type) { first: __s0_Buffer(T)\n second: Map(T, U64) }\ntype A { x: Fields(String) }\n", kind: 11, marker: "Fields", last: true},
		{name: "enum-member-order.al", text: "enum E(T: type) { First(value: __s0_Buffer(T))\n Second(value: Map(T, U64)) }\ntype A { x: E(String) }\n", kind: 11, marker: "E", last: true},
		{name: "changed-recursive-specialization.al", text: "type A(T: type) { next: Ptr(A(Option(T))) }\ntype Root { x: A(U64) }\n", kind: 14, marker: "A", last: true},
		{name: "memoized-changed-recursive-specialization.al", text: "type C { next: Ptr(A(Option(U64))) }\ntype A(T: type) { next: Ptr(C) }\ntype D(T: type) { first: C\n second: A(T) }\ntype Root { value: D(U64) }\n", kind: 14, marker: "D", last: true},
		{name: "recursive-sibling.al", text: "type A(T: type) { next: Ptr(A(T))\n bad: Map(T, U64) }\ntype Root { x: A(I64) }\n", kind: 12, marker: "A", last: true},
		{name: "restriction-before-cycle.al", text: "type Bad { x: Map(I64, String) }\ntype Cycle { x: Cycle }\n", kind: 12, marker: "Map"},
		{name: "forward-substituted-buffer.al", text: "type Use { x: Later(String) }\ntype Later(T: type) { x: __s0_Buffer(T) }\n", kind: 11, marker: "Later"},
		{name: "cycle-before-forward-revalidation.al", text: "type Use { x: Later(String) }\ntype Later(T: type) { x: __s0_Buffer(T) }\ntype Cycle { x: Cycle }\n", kind: 9, marker: "type", last: true},
		{name: "import-restriction-before-function.al", text: "fn earlier(x: __s0_Buffer(String)) -> U64 {}\nimport c bad: fn(Map(I64, U64)) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-string-parameter.al", text: "import c bad: fn(String) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-string-result.al", text: "import c bad: fn(U64) -> String\n", kind: 15, marker: "import"},
		{name: "ffi-pointer-string.al", text: "import c bad: fn(Ptr(String)) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-nested-pointer.al", text: "import c bad: fn(Ptr(Ptr(U8))) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-bare-pointer.al", text: "import c bad: fn(Ptr) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-pointer-arity.al", text: "import c bad: fn(Ptr(U8, U16)) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-slice.al", text: "import c bad: fn([U8]) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-domain.al", text: "import c bad: fn(Domain) -> U64\n", kind: 15, marker: "import"},
		{name: "ffi-declared.al", text: "type A { x: U64 }\nimport c bad: fn(A) -> U64\n", kind: 15, marker: "import"},
		{name: "duplicate-function-parameter.al", text: "fn f(x: U64, x: U8) -> Unit {}\n", kind: 16, marker: "U8"},
		{name: "reserved-function-parameter-builtin.al", text: "fn f(len: U64) -> Unit {}\n", kind: 17, marker: "U64"},
		{name: "reserved-function-parameter-prefix.al", text: "fn f(__s0_private: U64) -> Unit {}\n", kind: 17, marker: "U64"},
		{name: "reserved-function-parameter-type.al", text: "type User {}\nfn f(User: U64) -> Unit {}\n", kind: 17, marker: "U64"},
		{name: "reserved-parameter-before-result.al", text: "fn f(len: U64) -> Missing {}\n", kind: 17, marker: "U64"},
		{name: "function-parameter-type-before-name.al", text: "fn f(x: U64, x: Missing) -> Unit {}\n", kind: 4, marker: "Missing"},
		{name: "body-unknown.al", text: "fn f() -> U64 { return missing }\n", kind: 18, marker: "missing"},
		{name: "body-return-mismatch.al", text: "fn f(value: U64) -> I64 { return value }\n", kind: 19, marker: "return"},
		{name: "body-bool-return-mismatch.al", text: "fn f() -> U64 { return true }\n", kind: 19, marker: "return"},
		{name: "body-bool-string-mismatch.al", text: "fn f() -> String { return false }\n", kind: 19, marker: "return"},
		{name: "body-bare-valued.al", text: "fn f() -> U64 { return }\n", kind: 20, marker: "return"},
		{name: "body-int-out-of-range-u8.al", text: "fn f() -> U8 { return 256 }\n", kind: 21, marker: "256"},
		{name: "body-int-out-of-range-i8.al", text: "fn f() -> I8 { return 128 }\n", kind: 21, marker: "128"},
		{name: "body-int-out-of-range-u64.al", text: "fn f() -> U64 { return 18446744073709551616 }\n", kind: 21, marker: "18446744073709551616"},
		{name: "body-int-out-of-range-huge.al", text: "fn f() -> U64 { return 99999999999999999999999999999 }\n", kind: 21, marker: "99999999999999999999999999999"},
		{name: "body-int-negative-unsigned.al", text: "fn f() -> U8 { return -1 }\n", kind: 21, marker: "-1"},
		{name: "body-int-negative-i8-over.al", text: "fn f() -> I8 { return -129 }\n", kind: 21, marker: "-129"},
		{name: "body-int-negative-i64-over.al", text: "fn f() -> I64 { return -9223372036854775809 }\n", kind: 21, marker: "-9223372036854775809"},
		{name: "body-int-float-mismatch.al", text: "fn f() -> F64 { return 1 }\n", kind: 19, marker: "return"},
		{name: "body-int-string-mismatch.al", text: "fn f() -> String { return 1 }\n", kind: 19, marker: "return"},
		{name: "body-int-unit-mismatch.al", text: "fn f() -> Unit { return 1 }\n", kind: 19, marker: "return"},
		{name: "body-int-declared-mismatch.al", text: "type P { x: U64 }\nfn f() -> P { return 1 }\n", kind: 19, marker: "return"},
		{name: "body-string-int-mismatch.al", text: "fn f() -> U64 { return \"text\" }\n", kind: 19, marker: "return"},
		{name: "body-string-bool-mismatch.al", text: "fn f() -> Bool { return \"x\" }\n", kind: 19, marker: "return"},
		{name: "body-local-unknown-type.al", text: "fn f() -> U64 { let x: Missing = 1\n return x }\n", kind: 4, marker: "Missing"},
		{name: "body-local-reserved.al", text: "fn f() -> U64 { let len: U64 = 1\n return 5 }\n", kind: 22, marker: "len"},
		{name: "body-local-mismatch.al", text: "fn f() -> U64 { let x: I64 = true\n return 5 }\n", kind: 23, marker: "let"},
		{name: "body-local-unit.al", text: "fn f(u: Unit) -> Unit { let x: Unit = u\n return }\n", kind: 25, marker: "Unit", last: true},
		{name: "body-local-mark.al", text: "fn f(m: DomainMark) -> U64 { let x: DomainMark = m\n return 5 }\n", kind: 26, marker: "DomainMark", last: true},
		{name: "body-local-duplicate.al", text: "fn f() -> U64 { let seen: U64 = 1\n let seen: U64 = 2\n return 5 }\n", kind: 27, marker: "seen", last: true},
		{name: "body-assign-mismatch.al", text: "fn f() -> U64 { var y: U64 = 1\n y = true\n return y }\n", kind: 24, marker: "=", last: true},
		{name: "body-assign-immutable.al", text: "fn f() -> U64 { let imm: U64 = 1\n imm = 2\n return 5 }\n", kind: 28, marker: "imm", last: true},
		{name: "body-assign-param.al", text: "fn f(param: U64) -> U64 { param = 2\n return 5 }\n", kind: 28, marker: "param", last: true},
		{name: "body-assign-unknown.al", text: "fn f() -> U64 { ghost = 2\n return 5 }\n", kind: 18, marker: "ghost"},
		{name: "body-assign-function.al", text: "fn helper() -> U64 {}\nfn f() -> U64 { helper = 2\n return 5 }\n", kind: 18, marker: "helper", last: true},
		{name: "signature-before-body.al", text: "fn earlier(value: U64) -> I64 { return value }\nfn later() -> Missing {}\n", kind: 4, marker: "Missing"},
	}
	cycleFiles := map[string]string{"z.al": "type B { x: A }\n", "a.al": "type A { x: B }\n"}
	cycleOne := runAlderChecker(t, exe, cycleFiles, []string{"z.al", "a.al"}, true)
	cycleTwo := runAlderChecker(t, exe, cycleFiles, []string{"a.al", "z.al"}, true)
	if cycleOne != cycleTwo {
		t.Fatal("cross-file cycle changed with argv order")
	}
	cycleManifest := parseCheckerManifest(t, cycleOne, cycleFiles)
	assertCheckerDiagnostic(t, cycleManifest, 9, "a.al", 0, len("type"), "", -1, -1)
	for _, tc := range rejects {
		t.Run(tc.name, func(t *testing.T) {
			out := runAlderChecker(t, exe, map[string]string{tc.name: tc.text}, []string{tc.name}, true)
			cm := parseCheckerManifest(t, out, map[string]string{tc.name: tc.text})
			if len(cm.diagnostics) != 1 {
				t.Fatalf("diagnostics=%d", len(cm.diagnostics))
			}
			start := strings.Index(tc.text, tc.marker)
			if tc.last {
				start = strings.LastIndex(tc.text, tc.marker)
			}
			related := -1
			relatedPath := ""
			if tc.relatedMarker != "" {
				related = strings.Index(tc.text, tc.relatedMarker)
				relatedPath = tc.name
			}
			assertCheckerDiagnostic(t, cm, tc.kind, tc.name, start, start+len(tc.marker), relatedPath, related, related+len(tc.relatedMarker))
		})
	}
	reserved := []string{
		"Bool", "I8", "I16", "I32", "I64", "U8", "U16", "U32", "U64", "F32", "F64", "Unit", "String", "Option", "Result", "Map", "Ptr", "Domain", "DomainMark", "__s0_Buffer", "__s0_Error",
		"len", "range", "__s0_alloc", "__s0_domain_create", "__s0_domain_mark", "__s0_domain_reset", "__s0_domain_destroy", "__s0_map_create", "__s0_buffer_new", "__s0_buffer_len", "__s0_buffer_append", "__s0_buffer_get", "__s0_buffer_slice", "Get", "Set", "Remove",
		"None", "Some", "Ok", "Err",
	}
	for _, name := range reserved {
		text := "type " + name + " {}\n"
		cm := parseCheckerManifest(t, runAlderChecker(t, exe, map[string]string{"r.al": text}, []string{"r.al"}, true), map[string]string{"r.al": text})
		assertCheckerDiagnostic(t, cm, 2, "r.al", len("type "), len("type ")+len(name), "", -1, -1)
	}
	for name, text := range map[string]string{"lex.al": ";", "parse.al": "type {"} {
		out := runAlderChecker(t, exe, map[string]string{name: text}, []string{name}, true)
		prefix, diagnostic := "ALDER-TOKEN-MANIFEST 1\n", "D LEX0001 "
		if name == "parse.al" {
			prefix, diagnostic = "ALDER-PARSER-MANIFEST 1\n", "D SYN0001 "
		}
		if !strings.HasPrefix(out, prefix) || !strings.Contains(out, diagnostic) || !strings.HasSuffix(out, "END\n") || strings.Contains(out, "ALDER-CHECKER-MANIFEST") {
			t.Fatalf("invalid early-phase manifest for %s:\n%s", name, out)
		}
	}
	bad := map[string]string{"z.al": "type Z { x: Missing }\n", "a.al": "type A { x: Nope }\n"}
	x := runAlderChecker(t, exe, bad, []string{"z.al", "a.al"}, true)
	y := runAlderChecker(t, exe, bad, []string{"a.al", "z.al"}, true)
	if x != y {
		t.Fatal("canonical checker failure changed with argv order")
	}
	canonical := parseCheckerManifest(t, x, bad)
	start := strings.Index(bad["a.al"], "Nope")
	assertCheckerDiagnostic(t, canonical, 4, "a.al", start, start+len("Nope"), "", -1, -1)

	crossFiles := map[string]string{"z.al": "fn Shared() -> U64 {}\n", "a.al": "type Shared {}\n"}
	first := runAlderChecker(t, exe, crossFiles, []string{"z.al", "a.al"}, true)
	second := runAlderChecker(t, exe, crossFiles, []string{"a.al", "z.al"}, true)
	if first != second {
		t.Fatal("cross-file duplicate changed with argv order")
	}
	cross := parseCheckerManifest(t, first, crossFiles)
	assertCheckerDiagnostic(t, cross, 1, "z.al", len("fn "), len("fn ")+len("Shared"), "a.al", len("type "), len("type ")+len("Shared"))
	// Duplicate checking precedes reserved-name checking in collect_symbols, but
	// no two-declaration fixture can reach it: the first reserved declaration is
	// rejected immediately. The ordering is therefore pinned by code review.
}

func runAlderChecker(t *testing.T, exe string, files map[string]string, order []string, fail bool) string {
	t.Helper()
	d := t.TempDir()
	for n, s := range files {
		if e := os.WriteFile(filepath.Join(d, n), []byte(s), 0644); e != nil {
			t.Fatal(e)
		}
	}
	cmd := exec.Command(exe, order...)
	cmd.Dir = d
	var out, stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	e := cmd.Run()
	if fail {
		var x *exec.ExitError
		if !errors.As(e, &x) || x.ExitCode() != 1 {
			t.Fatalf("run: %v %s", e, stderr.String())
		}
	} else if e != nil {
		t.Fatalf("run: %v %s", e, stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatal(stderr.String())
	}
	return out.String()
}

func parseCheckerManifest(t *testing.T, text string, inputs map[string]string) checkerManifest {
	t.Helper()
	m, err := decodeCheckerManifest(text, inputs)
	if err != nil {
		t.Fatalf("decode checker manifest: %v\n%s", err, text)
	}
	return m
}

func decodeCheckerManifest(text string, inputs map[string]string) (checkerManifest, error) {
	m := checkerManifest{sourceByPath: make(map[string]int)}
	if !strings.HasSuffix(text, "\n") {
		return m, errors.New("manifest has no final line break")
	}
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	if len(lines) < 2 || lines[0] != "ALDER-CHECKER-MANIFEST 7" || lines[len(lines)-1] != "END" {
		return m, errors.New("invalid checker manifest envelope")
	}
	phase := 0
	for lineNumber, line := range lines[1 : len(lines)-1] {
		if line == "" {
			return m, fmt.Errorf("line %d is blank", lineNumber+2)
		}
		fields := strings.Fields(line)
		if len(fields) == 0 || strings.Join(fields, " ") != line {
			return m, fmt.Errorf("line %d has noncanonical fields", lineNumber+2)
		}
		recordPhase := map[string]int{"S": 0, "Y": 1, "P": 2, "C": 3, "A": 4, "T": 5, "U": 6, "L": 7, "N": 8, "E": 9, "H": 10, "R": 11, "D": 12}[fields[0]]
		if recordPhase == 0 && fields[0] != "S" {
			return m, fmt.Errorf("line %d has unknown record %q", lineNumber+2, fields[0])
		}
		if recordPhase < phase {
			return m, fmt.Errorf("line %d has out-of-order record %q", lineNumber+2, fields[0])
		}
		phase = recordPhase
		numbers, err := checkerManifestInts(fields[1:])
		switch fields[0] {
		case "S":
			if len(fields) != 4 {
				return m, fmt.Errorf("line %d: S expects 3 fields", lineNumber+2)
			}
			id, err := checkerManifestInt(fields[1])
			if err != nil {
				return m, fmt.Errorf("line %d: %w", lineNumber+2, err)
			}
			pathBytes, err := hex.DecodeString(fields[2])
			if err != nil || len(pathBytes) == 0 || hex.EncodeToString(pathBytes) != fields[2] {
				return m, fmt.Errorf("line %d has invalid hex path", lineNumber+2)
			}
			length, err := checkerManifestInt(fields[3])
			if err != nil {
				return m, fmt.Errorf("line %d: %w", lineNumber+2, err)
			}
			path := string(pathBytes)
			input, exists := inputs[path]
			if id != len(m.sources) || !exists || len(input) != length {
				return m, fmt.Errorf("line %d has invalid source %d %q", lineNumber+2, id, path)
			}
			if _, duplicate := m.sourceByPath[path]; duplicate {
				return m, fmt.Errorf("line %d duplicates source %q", lineNumber+2, path)
			}
			m.sourceByPath[path] = id
			m.sources = append(m.sources, checkerSource{id: id, path: path, length: length})
		case "Y":
			if err != nil || len(numbers) != 7 {
				return m, fmt.Errorf("line %d has invalid Y record", lineNumber+2)
			}
			m.symbols = append(m.symbols, checkerSymbol{id: numbers[0], kind: numbers[1], node: numbers[2], source: numbers[3], start: numbers[4], end: numbers[5], arity: numbers[6]})
		case "P":
			if err != nil || len(numbers) != 6 {
				return m, fmt.Errorf("line %d has invalid P record", lineNumber+2)
			}
			m.params = append(m.params, checkerTypeParam{id: numbers[0], owner: numbers[1], node: numbers[2], source: numbers[3], start: numbers[4], end: numbers[5]})
		case "C":
			if err != nil || len(numbers) != 6 {
				return m, fmt.Errorf("line %d has invalid C record", lineNumber+2)
			}
			m.types = append(m.types, checkerType{id: numbers[0], kind: numbers[1], syntax: numbers[2], target: numbers[3], first: numbers[4], count: numbers[5]})
		case "A":
			if err != nil || len(numbers) != 2 {
				return m, fmt.Errorf("line %d has invalid A record", lineNumber+2)
			}
			m.args = append(m.args, checkerTypeArg{id: numbers[0], checkedType: numbers[1]})
		case "T":
			if err != nil || len(numbers) != 4 {
				return m, fmt.Errorf("line %d has invalid T record", lineNumber+2)
			}
			m.annotations = append(m.annotations, checkerTypeAnnotation{id: numbers[0], owner: numbers[1], syntax: numbers[2], checkedType: numbers[3]})
		case "U":
			if err != nil || len(numbers) != 10 {
				return m, fmt.Errorf("line %d has invalid U record", lineNumber+2)
			}
			m.uses = append(m.uses, checkerTypeUse{id: numbers[0], owner: numbers[1], role: numbers[2], ordinal: numbers[3], node: numbers[4], source: numbers[5], nameStart: numbers[6], nameEnd: numbers[7], syntax: numbers[8], checkedType: numbers[9]})
		case "L":
			if err != nil || len(numbers) != 9 {
				return m, fmt.Errorf("line %d has invalid L record", lineNumber+2)
			}
			m.locals = append(m.locals, checkerLocal{id: numbers[0], owner: numbers[1], kind: numbers[2], syntax: numbers[3], source: numbers[4], nameStart: numbers[5], nameEnd: numbers[6], mutable: numbers[7], checkedType: numbers[8]})
		case "N":
			if err != nil || len(numbers) != 4 {
				return m, fmt.Errorf("line %d has invalid N record", lineNumber+2)
			}
			m.environments = append(m.environments, checkerEnvironment{id: numbers[0], owner: numbers[1], parent: numbers[2], binding: numbers[3]})
		case "E":
			if err != nil || len(numbers) != 15 {
				return m, fmt.Errorf("line %d has invalid E record", lineNumber+2)
			}
			m.expressions = append(m.expressions, checkerExpression{id: numbers[0], owner: numbers[1], syntax: numbers[2], kind: numbers[3], checkedType: numbers[4], parameterUse: numbers[5], boolValue: numbers[6], left: numbers[7], right: numbers[8], annotation: numbers[9], firstChild: numbers[10], childCount: numbers[11], operator: numbers[12], siteKind: numbers[13], siteSyntax: numbers[14]})
		case "H":
			if err != nil || len(numbers) != 2 {
				return m, fmt.Errorf("line %d has invalid H record", lineNumber+2)
			}
			m.children = append(m.children, checkerExpressionChild{id: numbers[0], expression: numbers[1]})
		case "R":
			if err != nil || len(numbers) != 5 {
				return m, fmt.Errorf("line %d has invalid R record", lineNumber+2)
			}
			m.returns = append(m.returns, checkerReturn{id: numbers[0], owner: numbers[1], syntax: numbers[2], expression: numbers[3], resultUse: numbers[4]})
		case "D":
			if err != nil || len(numbers) != 5 && len(numbers) != 8 || numbers[4] > 1 || numbers[4] == 0 && len(numbers) != 5 || numbers[4] == 1 && len(numbers) != 8 {
				return m, fmt.Errorf("line %d has invalid D record", lineNumber+2)
			}
			diagnostic := checkerDiagnostic{kind: numbers[0], source: numbers[1], start: numbers[2], end: numbers[3], hasRelated: numbers[4] == 1}
			if diagnostic.hasRelated {
				diagnostic.relatedSource, diagnostic.relatedStart, diagnostic.relatedEnd = numbers[5], numbers[6], numbers[7]
			}
			m.diagnostics = append(m.diagnostics, diagnostic)
		}
	}
	if len(m.sources) != len(inputs) {
		return m, fmt.Errorf("manifest has %d sources, want %d", len(m.sources), len(inputs))
	}
	paths := make([]string, 0, len(inputs))
	for path := range inputs {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	for i, path := range paths {
		if m.sources[i].path != path {
			return m, fmt.Errorf("source %d is %q, want canonical path %q", i, m.sources[i].path, path)
		}
	}
	if err := validateCheckerManifest(m); err != nil {
		return m, err
	}
	return m, nil
}

func checkerManifestInt(field string) (int, error) {
	value, err := strconv.Atoi(field)
	if err != nil || value < 0 || strconv.Itoa(value) != field {
		return 0, fmt.Errorf("invalid nonnegative integer %q", field)
	}
	return value, nil
}

func checkerManifestInts(fields []string) ([]int, error) {
	result := make([]int, len(fields))
	for i, field := range fields {
		value, err := checkerManifestInt(field)
		if err != nil {
			return nil, err
		}
		result[i] = value
	}
	return result, nil
}

func validateCheckerManifest(m checkerManifest) error {
	validSourceRange := func(source, start, end int, nonempty bool) bool {
		return source >= 0 && source < len(m.sources) && start >= 0 && start <= end && end <= m.sources[source].length && (!nonempty || start < end)
	}
	bodyPhase := len(m.expressions) != 0 || len(m.returns) != 0 || len(m.locals) != 0
	for _, diagnostic := range m.diagnostics {
		if diagnostic.kind >= 18 && diagnostic.kind <= 28 {
			bodyPhase = true
		}
	}
	nodes := make(map[int]bool)
	for i, symbol := range m.symbols {
		if symbol.id != i+1 || (symbol.kind != 1 && symbol.kind != 2 && symbol.kind != 3 && symbol.kind != 12) || symbol.node < 1 || nodes[symbol.node] || symbol.arity < 0 || !validSourceRange(symbol.source, symbol.start, symbol.end, true) {
			return fmt.Errorf("invalid symbol %+v", symbol)
		}
		nodes[symbol.node] = true
	}
	for i, param := range m.params {
		if param.id != i+1 || param.owner < 1 || param.owner > len(m.symbols) || param.node < 1 || nodes[param.node] || !validSourceRange(param.source, param.start, param.end, true) {
			return fmt.Errorf("invalid type parameter %+v", param)
		}
		nodes[param.node] = true
	}
	for i, arg := range m.args {
		if arg.id != i+1 || arg.checkedType < 1 || arg.checkedType > len(m.types) {
			return fmt.Errorf("invalid type argument %+v", arg)
		}
	}
	argOwners := make([]int, len(m.args))
	typeOwners := make([]int, len(m.types))
	typeSemanticOwners := make([]int, len(m.types))
	typeSyntax := make(map[int]bool)
	canonicalTypes := make(map[string]bool)
	for i, checked := range m.types {
		var key strings.Builder
		fmt.Fprintf(&key, "%d/%d", checked.kind, checked.target)
		if checked.first >= 1 && checked.first-1+checked.count <= len(m.args) {
			for _, arg := range checkerDirectArgs(m, checked) {
				fmt.Fprintf(&key, "/%d", arg.checkedType)
			}
		}
		if checked.id != i+1 || checked.kind < 1 || checked.kind > 13 || checked.syntax != 0 || canonicalTypes[key.String()] || (checked.count == 0) != (checked.first == 0) || checked.first < 0 || checked.count < 0 || checked.count > 0 && (checked.first < 1 || checked.first-1 > len(m.args) || checked.count > len(m.args)-(checked.first-1)) {
			return fmt.Errorf("invalid checked type %+v", checked)
		}
		canonicalTypes[key.String()] = true
		if checked.kind == 1 && (checked.target < 1 || checked.target > 12) {
			return fmt.Errorf("checked type %+v has an invalid primitive target", checked)
		}
		if checked.target != 0 && checked.kind != 1 && checked.kind != 6 && checked.kind != 7 {
			return fmt.Errorf("checked type %+v has an unexpected target", checked)
		}
		if checked.kind == 6 && (checked.target < 1 || checked.target > len(m.params)) {
			return fmt.Errorf("checked type %+v has an invalid parameter target", checked)
		}
		if checked.kind == 7 && (checked.target < 1 || checked.target > len(m.symbols) || m.symbols[checked.target-1].kind != 2 && m.symbols[checked.target-1].kind != 3) {
			return fmt.Errorf("checked type %+v has an invalid declaration target", checked)
		}
		wantCount := 0
		switch checked.kind {
		case 7:
			wantCount = m.symbols[checked.target-1].arity
		case 8, 9, 12, 13:
			wantCount = 1
		case 10, 11:
			wantCount = 2
		}
		if checked.count != wantCount {
			return fmt.Errorf("checked type %+v has %d arguments, want %d", checked, checked.count, wantCount)
		}
		for _, arg := range checkerDirectArgs(m, checked) {
			if arg.checkedType >= checked.id {
				return fmt.Errorf("checked type %+v does not follow its argument %+v", checked, arg)
			}
			argOwners[arg.id-1]++
			typeOwners[arg.checkedType-1]++
			if argOwners[arg.id-1] != 1 {
				return fmt.Errorf("type argument %+v has overlapping owners", arg)
			}
		}
	}
	annotations := make(map[[2]int]int)
	for i, annotation := range m.annotations {
		key := [2]int{annotation.owner, annotation.syntax}
		if annotation.id != i+1 || annotation.owner < 1 || annotation.owner > len(m.symbols) || annotation.syntax < 1 || annotation.checkedType < 1 || annotation.checkedType > len(m.types) || annotations[key] != 0 || typeSyntax[annotation.syntax] {
			return fmt.Errorf("invalid type annotation %+v", annotation)
		}
		annotations[key] = annotation.checkedType
		typeSyntax[annotation.syntax] = true
	}
	for i, owners := range argOwners {
		if owners != 1 {
			return fmt.Errorf("type argument %d has %d owners", i+1, owners)
		}
	}
	if len(m.diagnostics) == 0 || bodyPhase {
		paramCounts := make([]int, len(m.symbols))
		for _, param := range m.params {
			paramCounts[param.owner-1]++
		}
		for i, symbol := range m.symbols {
			if paramCounts[i] != symbol.arity {
				return fmt.Errorf("symbol %+v has %d type parameter records", symbol, paramCounts[i])
			}
		}
	}
	ordinals := make(map[[2]int]int)
	for i, use := range m.uses {
		key := [2]int{use.owner, use.role}
		valueless := use.role == 2 && use.syntax == 0 && use.checkedType == 0
		named := use.role == 1 || use.role == 2 || use.role == 5
		ownerKind := 0
		if use.owner >= 1 && use.owner <= len(m.symbols) {
			ownerKind = m.symbols[use.owner-1].kind
		}
		roleMatchesOwner := use.role == 1 && ownerKind == 2 || use.role == 2 && ownerKind == 3 || (use.role == 3 || use.role == 4) && ownerKind == 1 || (use.role == 5 || use.role == 6) && ownerKind == 12
		if use.id != i+1 || use.owner < 1 || use.owner > len(m.symbols) || use.role < 1 || use.role > 6 || !roleMatchesOwner || use.ordinal != ordinals[key] || use.node < 1 || nodes[use.node] || !validSourceRange(use.source, use.nameStart, use.nameEnd, named) || named != (use.nameStart != 0 || use.nameEnd != 0) || !valueless && (use.syntax < 1 || use.checkedType < 1 || use.checkedType > len(m.types) || annotations[[2]int{use.owner, use.syntax}] != use.checkedType) || valueless && (use.nameStart == 0 || use.nameEnd == 0) {
			return fmt.Errorf("invalid declaration type use %+v", use)
		}
		nodes[use.node] = true
		if !valueless {
			checkedIndex := use.checkedType - 1
			typeOwners[checkedIndex]++
			typeSemanticOwners[checkedIndex] = use.owner
		}
		ordinals[key]++
	}
	for _, local := range m.locals {
		checkedIndex := local.checkedType - 1
		if checkedIndex < 0 || checkedIndex >= len(m.types) {
			continue
		}
		typeOwners[checkedIndex]++
		typeSemanticOwners[checkedIndex] = local.owner
	}
	for i, owners := range typeOwners {
		// Failed manifests may retain orphan types from a resolution that
		// completed before the failing check, matching declaration-phase
		// failures. Success manifests keep exact single ownership.
		if owners < 0 {
			return fmt.Errorf("checked type %d has %d owners", i+1, owners)
		}
	}
	if bodyPhase {
		for _, symbol := range m.symbols {
			role := 0
			if symbol.kind == 1 {
				role = 4
			}
			if symbol.kind == 12 {
				role = 6
			}
			if role != 0 && ordinals[[2]int{symbol.id, role}] != 1 {
				return fmt.Errorf("body phase symbol %+v has %d result records", symbol, ordinals[[2]int{symbol.id, role}])
			}
		}
	}
	// The private checker manifest omits the parser graph. These checks therefore
	// prove relational ownership among semantic records. The producer derives
	// syntax IDs from the traversed parser nodes, while direct E2E fixtures prove
	// semantic type equality, exact Bool/other primitive spellings, and that a
	// zero-expression return has a Unit result.
	bodySyntax := make(map[int]bool)
	bindingEnvironments := make([]int, len(m.locals))
	lastEnvironment := make(map[int]int)
	lastEnvironmentOwner := 0
	for i, environment := range m.environments {
		if environment.id != i+1 || environment.owner < 1 || environment.owner > len(m.symbols) || environment.owner < lastEnvironmentOwner || environment.binding != i+1 || environment.binding > len(m.locals) || environment.parent != lastEnvironment[environment.owner] || m.locals[environment.binding-1].owner != environment.owner {
			return fmt.Errorf("invalid environment %+v", environment)
		}
		bindingEnvironments[environment.binding-1]++
		lastEnvironment[environment.owner] = environment.id
		lastEnvironmentOwner = environment.owner
	}
	for i, local := range m.locals {
		ownerKind, ownerArity := 0, -1
		if local.owner >= 1 && local.owner <= len(m.symbols) {
			ownerKind = m.symbols[local.owner-1].kind
			ownerArity = m.symbols[local.owner-1].arity
		}
		sharedParameterSyntax := local.kind == 1 && local.syntax >= 1 && nodes[local.syntax]
		if local.id != i+1 || ownerKind != 12 || local.kind < 1 || local.kind > 2 || local.syntax < 1 || nodes[local.syntax] && !sharedParameterSyntax || bodySyntax[local.syntax] || local.checkedType < 1 || local.checkedType > len(m.types) || local.kind == 1 && (local.mutable != 0 || ownerArity < 0) || local.kind == 2 && ownerArity != 0 || (local.mutable != 0 && local.mutable != 1) || !validSourceRange(local.source, local.nameStart, local.nameEnd, true) || bindingEnvironments[i] != 1 {
			return fmt.Errorf("invalid local binding %+v", local)
		}
		if local.kind == 2 {
			bodySyntax[local.syntax] = true
		}
	}
	expressionOwners := make([]int, len(m.expressions))
	expressionSites := make(map[[2]int]int)
	for i, expression := range m.expressions {
		if expression.left != 0 || expression.right != 0 || expression.annotation != 0 || (expression.childCount == 0) != (expression.firstChild == 0) || expression.firstChild < 0 || expression.childCount < 0 || expression.childCount > 0 && (expression.firstChild < 1 || expression.firstChild-1+expression.childCount > len(m.children)) {
			return fmt.Errorf("invalid checked expression child range %+v", expression)
		}
		if expression.childCount > 0 {
			expression.left = m.children[expression.firstChild-1].expression
		}
		if expression.childCount > 1 {
			expression.right = m.children[expression.firstChild].expression
		}
		ownerKind, ownerArity := 0, -1
		if expression.owner >= 1 && expression.owner <= len(m.symbols) {
			ownerKind = m.symbols[expression.owner-1].kind
			ownerArity = m.symbols[expression.owner-1].arity
		}
		validPayload := false
		if expression.kind == 1 && expression.parameterUse >= 1 && expression.parameterUse <= len(m.locals) && expression.boolValue == 0 {
			parameter := m.locals[expression.parameterUse-1]
			validPayload = parameter.owner == expression.owner && parameter.kind == 1 && parameter.checkedType == expression.checkedType
		}
		if expression.kind == 2 {
			validPayload = expression.parameterUse == 0 && (expression.boolValue == 0 || expression.boolValue == 1) && expression.checkedType >= 1 && expression.checkedType <= len(m.types) && m.types[expression.checkedType-1].kind == 1
		}
		if expression.kind == 3 {
			validPayload = expression.parameterUse == 0 && expression.boolValue == 0 && expression.checkedType >= 1 && expression.checkedType <= len(m.types) && m.types[expression.checkedType-1].kind == 1
		}
		if expression.kind == 4 {
			payloadKind := 0
			if expression.checkedType >= 1 && expression.checkedType <= len(m.types) {
				payloadKind = m.types[expression.checkedType-1].kind
			}
			validPayload = expression.parameterUse == 0 && expression.boolValue == 0 && (payloadKind == 2 || payloadKind == 8)
		}
		if expression.kind == 5 && expression.parameterUse >= 1 && expression.parameterUse <= len(m.locals) && expression.boolValue == 0 {
			local := m.locals[expression.parameterUse-1]
			validPayload = local.owner == expression.owner && local.checkedType == expression.checkedType
		}
		if expression.kind >= 1 && expression.kind <= 5 {
			validPayload = validPayload && expression.left == 0 && expression.right == 0 && expression.operator == 0
		}
		if expression.kind == 6 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.left >= 1 && expression.left < expression.id && expression.right == 0 && (expression.operator == 1 || expression.operator == 2) {
			child := m.expressions[expression.left-1]
			validPayload = child.owner == expression.owner && child.checkedType == expression.checkedType
			expressionOwners[expression.left-1]++
		}
		if expression.kind == 7 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.left >= 1 && expression.left < expression.id && expression.right >= 1 && expression.right < expression.id && expression.left != expression.right && expression.operator >= 3 && expression.operator <= 17 {
			left, right := m.expressions[expression.left-1], m.expressions[expression.right-1]
			validPayload = left.owner == expression.owner && right.owner == expression.owner
			expressionOwners[expression.left-1]++
			expressionOwners[expression.right-1]++
		}
		validSite := expression.siteKind == 0 && expression.siteSyntax == 0 || expression.siteKind >= 1 && expression.siteKind <= 3 && expression.siteSyntax >= 1
		if expression.siteKind != 0 {
			expressionOwners[i]++
			key := [2]int{expression.siteKind, expression.siteSyntax}
			if expressionSites[key] != 0 {
				return fmt.Errorf("checked expressions %d and %d share site %v", expressionSites[key], expression.id, key)
			}
			expressionSites[key] = expression.id
		}
		if expression.id != i+1 || ownerKind != 12 || ownerArity != 0 || expression.syntax < 1 || nodes[expression.syntax] || typeSyntax[expression.syntax] || bodySyntax[expression.syntax] || expression.checkedType < 1 || expression.checkedType > len(m.types) || !validPayload || !validSite {
			return fmt.Errorf("invalid checked expression %+v", expression)
		}
		bodySyntax[expression.syntax] = true
	}
	childOwners := make([]int, len(m.children))
	for _, expression := range m.expressions {
		for at := 0; at < expression.childCount; at++ {
			child := m.children[expression.firstChild-1+at]
			if child.id != expression.firstChild+at || child.expression < 1 || child.expression >= expression.id || childOwners[child.id-1] != 0 {
				return fmt.Errorf("invalid checked expression child %+v", child)
			}
			childOwners[child.id-1]++
		}
	}
	for i, owners := range childOwners {
		if owners != 1 {
			return fmt.Errorf("checked expression child %d has %d owners", i+1, owners)
		}
	}
	for _, local := range m.locals {
		if local.kind == 2 && expressionSites[[2]int{1, local.syntax}] == 0 {
			return fmt.Errorf("local binding %d has no initializer expression", local.id)
		}
	}
	returnOwners := make(map[int]bool)
	for i, checkedReturn := range m.returns {
		ownerKind, ownerArity := 0, -1
		if checkedReturn.owner >= 1 && checkedReturn.owner <= len(m.symbols) {
			ownerKind = m.symbols[checkedReturn.owner-1].kind
			ownerArity = m.symbols[checkedReturn.owner-1].arity
		}
		var result checkerTypeUse
		if checkedReturn.resultUse >= 1 && checkedReturn.resultUse <= len(m.uses) {
			result = m.uses[checkedReturn.resultUse-1]
		}
		validExpression := checkedReturn.expression == 0
		if checkedReturn.expression >= 1 && checkedReturn.expression <= len(m.expressions) {
			expression := m.expressions[checkedReturn.expression-1]
			validExpression = expression.owner == checkedReturn.owner && expression.siteKind == 3 && expression.siteSyntax == checkedReturn.syntax && (expression.kind == 1 || expression.kind == 5 || expression.kind == 6 || expression.kind == 7 || expression.checkedType == result.checkedType)
		}
		if checkedReturn.id != i+1 || ownerKind != 12 || ownerArity != 0 || returnOwners[checkedReturn.owner] || checkedReturn.syntax < 1 || nodes[checkedReturn.syntax] || typeSyntax[checkedReturn.syntax] || bodySyntax[checkedReturn.syntax] || !validExpression || result.id == 0 || result.owner != checkedReturn.owner || result.role != 6 {
			return fmt.Errorf("invalid checked return %+v", checkedReturn)
		}
		returnOwners[checkedReturn.owner] = true
		bodySyntax[checkedReturn.syntax] = true
	}
	for i, owners := range expressionOwners {
		if owners != 1 {
			return fmt.Errorf("checked expression %d has %d return owners", i+1, owners)
		}
	}
	if len(m.diagnostics) > 1 {
		return fmt.Errorf("manifest has %d diagnostics, want at most one", len(m.diagnostics))
	}
	for _, diagnostic := range m.diagnostics {
		if diagnostic.kind < 1 || diagnostic.kind > 38 || !validSourceRange(diagnostic.source, diagnostic.start, diagnostic.end, true) || diagnostic.hasRelated != (diagnostic.kind == 1 || diagnostic.kind == 3) {
			return fmt.Errorf("invalid checker diagnostic %+v", diagnostic)
		}
		if diagnostic.hasRelated && !validSourceRange(diagnostic.relatedSource, diagnostic.relatedStart, diagnostic.relatedEnd, true) {
			return fmt.Errorf("invalid related checker diagnostic %+v", diagnostic)
		}
	}
	return nil
}

func checkerDirectArgs(m checkerManifest, checked checkerType) []checkerTypeArg {
	if checked.count == 0 {
		return nil
	}
	return m.args[checked.first-1 : checked.first-1+checked.count]
}

func checkerSourceText(m checkerManifest, inputs map[string]string, source, start, end int) string {
	return inputs[m.sources[source].path][start:end]
}

func checkerSymbolByName(t *testing.T, m checkerManifest, inputs map[string]string, name string) checkerSymbol {
	t.Helper()
	for _, symbol := range m.symbols {
		if checkerSourceText(m, inputs, symbol.source, symbol.start, symbol.end) == name {
			return symbol
		}
	}
	t.Fatalf("no checker symbol named %q", name)
	return checkerSymbol{}
}

func checkerTypeParamForOwner(t *testing.T, m checkerManifest, owner int) checkerTypeParam {
	t.Helper()
	for _, param := range m.params {
		if param.owner == owner {
			return param
		}
	}
	t.Fatalf("symbol %d has no type parameter", owner)
	return checkerTypeParam{}
}

func checkerUse(t *testing.T, m checkerManifest, owner, role, ordinal int) checkerTypeUse {
	t.Helper()
	for _, use := range m.uses {
		if use.owner == owner && use.role == role && use.ordinal == ordinal {
			return use
		}
	}
	t.Fatalf("no checker use owner=%d role=%d ordinal=%d", owner, role, ordinal)
	return checkerTypeUse{}
}

func checkerReturnForOwner(t *testing.T, m checkerManifest, owner int) checkerReturn {
	t.Helper()
	for _, checkedReturn := range m.returns {
		if checkedReturn.owner == owner {
			return checkedReturn
		}
	}
	t.Fatalf("no checked return for owner=%d", owner)
	return checkerReturn{}
}

func assertCheckerSuccessManifest(t *testing.T, m checkerManifest, inputs map[string]string) {
	t.Helper()
	type symbolWant struct {
		name, path  string
		kind, arity int
	}
	wants := []symbolWant{
		{name: "foreign", path: "a space.al", kind: 1},
		{name: "Box", path: "a space.al", kind: 2, arity: 1},
		{name: "Nest", path: "a space.al", kind: 2},
		{name: "E", path: "a space.al", kind: 3},
		{name: "f", path: "a space.al", kind: 12, arity: 1},
		{name: "Other", path: "a space.al", kind: 2, arity: 1},
		{name: "deferred", path: "a space.al", kind: 12},
		{name: "Forward", path: "b.al", kind: 2},
		{name: "Later", path: "b.al", kind: 2},
		{name: "Recursive", path: "b.al", kind: 2},
	}
	for i := 0; i < 64; i++ {
		wants = append(wants, symbolWant{name: fmt.Sprintf("X%02d", i), path: "b.al", kind: 2, arity: 1})
	}
	if len(m.symbols) != len(wants) {
		t.Fatalf("symbols=%d, want %d", len(m.symbols), len(wants))
	}
	for i, want := range wants {
		symbol := m.symbols[i]
		if symbol.id != i+1 || symbol.kind != want.kind || symbol.arity != want.arity || m.sources[symbol.source].path != want.path || checkerSourceText(m, inputs, symbol.source, symbol.start, symbol.end) != want.name {
			t.Fatalf("symbol %d = %+v/%q, want %+v", i+1, symbol, checkerSourceText(m, inputs, symbol.source, symbol.start, symbol.end), want)
		}
	}
	if len(m.params) != 67 || len(m.args) <= 16 || len(m.types) <= 16 || len(m.uses) <= 16 {
		t.Fatalf("growth coverage: params=%d args=%d types=%d uses=%d", len(m.params), len(m.args), len(m.types), len(m.uses))
	}
	parameterOwners := []int{2, 6}
	for owner := 11; owner <= 74; owner++ {
		parameterOwners = append(parameterOwners, owner)
	}
	parameterOwners = append(parameterOwners, 5)
	for _, owner := range parameterOwners {
		param := checkerTypeParamForOwner(t, m, owner)
		if checkerSourceText(m, inputs, param.source, param.start, param.end) != "T" {
			t.Fatalf("type parameter for owner %d = %+v", owner, param)
		}
	}

	foreign := checkerSymbolByName(t, m, inputs, "foreign")
	foreign0, foreign1, foreignResult := checkerUse(t, m, foreign.id, 3, 0), checkerUse(t, m, foreign.id, 3, 1), checkerUse(t, m, foreign.id, 4, 0)
	foreignPointer := m.types[foreign1.checkedType-1]
	if foreign0.nameStart != 0 || foreign0.nameEnd != 0 || foreign1.nameStart != 0 || foreign1.nameEnd != 0 || foreignResult.nameStart != 0 || foreignResult.nameEnd != 0 || m.types[foreign0.checkedType-1].kind != 1 || foreignPointer.kind != 12 || m.types[checkerDirectArgs(m, foreignPointer)[0].checkedType-1].kind != 1 || m.types[foreignResult.checkedType-1].kind != 1 {
		t.Fatal("import type-use order or kinds changed")
	}
	box := checkerSymbolByName(t, m, inputs, "Box")
	boxParam := checkerTypeParamForOwner(t, m, box.id)
	boxField := m.types[checkerUse(t, m, box.id, 1, 0).checkedType-1]
	if boxField.kind != 6 || boxField.target != boxParam.id {
		t.Fatal("Box.T did not resolve to its owner-local parameter")
	}
	nest := checkerSymbolByName(t, m, inputs, "Nest")
	for ordinal, name := range []string{"x", "a", "b", "c", "d", "mark", "text"} {
		item := checkerUse(t, m, nest.id, 1, ordinal)
		if checkerSourceText(m, inputs, item.source, item.nameStart, item.nameEnd) != name {
			t.Fatalf("Nest field %d metadata changed: %+v", ordinal, item)
		}
	}
	mapType := m.types[checkerUse(t, m, nest.id, 1, 0).checkedType-1]
	mapArgs := checkerDirectArgs(m, mapType)
	if mapType.kind != 11 || len(mapArgs) != 2 || m.types[mapArgs[0].checkedType-1].kind != 1 || m.types[mapArgs[1].checkedType-1].kind != 9 {
		t.Fatal("Map direct arguments are not U64 and Option(U8)")
	}
	optionType := m.types[mapArgs[1].checkedType-1]
	optionArgs := checkerDirectArgs(m, optionType)
	if len(optionArgs) != 1 || m.types[optionArgs[0].checkedType-1].kind != 1 {
		t.Fatal("nested Option direct argument is not U8")
	}
	for ordinal, kind := range []int{8, 10, 12, 13} {
		if m.types[checkerUse(t, m, nest.id, 1, ordinal+1).checkedType-1].kind != kind {
			t.Fatalf("Nest field %d kind changed", ordinal+1)
		}
	}
	if kind := m.types[checkerUse(t, m, nest.id, 1, 5).checkedType-1].kind; kind != 4 {
		t.Fatalf("Nest DomainMark field kind=%d, want 4", kind)
	}
	if kind := m.types[checkerUse(t, m, nest.id, 1, 6).checkedType-1].kind; kind != 8 {
		t.Fatalf("Nest String field kind=%d, want canonical slice kind 8", kind)
	}
	enum := checkerSymbolByName(t, m, inputs, "E")
	enumUses := 0
	for _, use := range m.uses {
		if use.owner == enum.id && use.role == 2 {
			enumUses++
		}
	}
	empty := checkerUse(t, m, enum.id, 2, 0)
	full := checkerUse(t, m, enum.id, 2, 1)
	payload := m.types[full.checkedType-1]
	if enumUses != 2 || empty.syntax != 0 || empty.checkedType != 0 || checkerSourceText(m, inputs, empty.source, empty.nameStart, empty.nameEnd) != "Empty" || checkerSourceText(m, inputs, full.source, full.nameStart, full.nameEnd) != "Full" || payload.kind != 7 || payload.target != box.id {
		t.Fatal("enum declaration items or payload target changed")
	}
	function := checkerSymbolByName(t, m, inputs, "f")
	functionParam := checkerTypeParamForOwner(t, m, function.id)
	xType := m.types[checkerUse(t, m, function.id, 5, 0).checkedType-1]
	yType := m.types[checkerUse(t, m, function.id, 5, 1).checkedType-1]
	resultType := m.types[checkerUse(t, m, function.id, 6, 0).checkedType-1]
	if xType.kind != 6 || xType.target != functionParam.id || yType.kind != 7 || yType.target != box.id || m.types[checkerDirectArgs(m, yType)[0].checkedType-1].target != functionParam.id || resultType.kind != 9 {
		t.Fatal("function owner-local parameter or signature resolution changed")
	}
	if xItem, yItem, resultItem := checkerUse(t, m, function.id, 5, 0), checkerUse(t, m, function.id, 5, 1), checkerUse(t, m, function.id, 6, 0); checkerSourceText(m, inputs, xItem.source, xItem.nameStart, xItem.nameEnd) != "x" || checkerSourceText(m, inputs, yItem.source, yItem.nameStart, yItem.nameEnd) != "y" || resultItem.nameStart != 0 || resultItem.nameEnd != 0 {
		t.Fatal("function declaration-item names changed or compile-time T became an item")
	}
	other := checkerSymbolByName(t, m, inputs, "Other")
	if checkerTypeParamForOwner(t, m, other.id).id == boxParam.id {
		t.Fatal("same-spelled type parameters share an ID across owners")
	}
	forward := checkerSymbolByName(t, m, inputs, "Forward")
	later := checkerSymbolByName(t, m, inputs, "Later")
	recursive := checkerSymbolByName(t, m, inputs, "Recursive")
	for _, pair := range []struct {
		owner checkerSymbol
		names []string
	}{{forward, []string{"x"}}, {later, []string{"x"}}, {recursive, []string{"pointer"}}} {
		for ordinal, name := range pair.names {
			item := checkerUse(t, m, pair.owner.id, 1, ordinal)
			if checkerSourceText(m, inputs, item.source, item.nameStart, item.nameEnd) != name {
				t.Fatalf("field item metadata changed for owner %d ordinal %d", pair.owner.id, ordinal)
			}
		}
	}
	if target := m.types[checkerUse(t, m, forward.id, 1, 0).checkedType-1].target; target != later.id {
		t.Fatalf("forward type target=%d, want %d", target, later.id)
	}
	if kind := m.types[checkerUse(t, m, recursive.id, 1, 0).checkedType-1].kind; kind != 12 {
		t.Fatalf("pointer-cut recursive field kind=%d, want 12", kind)
	}
	deferred := checkerSymbolByName(t, m, inputs, "deferred")
	if len(m.uses) != 85 || len(m.expressions) != 0 || len(m.returns) != 0 || len(m.locals) != 0 || m.types[checkerUse(t, m, deferred.id, 6, 0).checkedType-1].kind != 1 {
		t.Fatalf("unsupported body was checked or declaration-use count changed: uses=%d expressions=%d returns=%d", len(m.uses), len(m.expressions), len(m.returns))
	}
	for owner := 11; owner <= 74; owner++ {
		param := checkerTypeParamForOwner(t, m, owner)
		checked := m.types[checkerUse(t, m, owner, 1, 0).checkedType-1]
		args := checkerDirectArgs(m, checked)
		if checked.kind != 9 || len(args) != 1 || m.types[args[0].checkedType-1].kind != 6 || m.types[args[0].checkedType-1].target != param.id {
			t.Fatalf("stress declaration owner %d did not retain Option(T)", owner)
		}
	}
	kinds := make(map[int]bool)
	for _, checked := range m.types {
		kinds[checked.kind] = true
	}
	for kind := 1; kind <= 13; kind++ {
		if kind == 2 {
			continue // String is canonical slice(U8), not a distinct type kind.
		}
		if !kinds[kind] {
			t.Fatalf("success fixture did not exercise checked type kind %d", kind)
		}
	}
}

func assertCheckerDiagnostic(t *testing.T, m checkerManifest, kind int, path string, start, end int, relatedPath string, relatedStart, relatedEnd int) {
	t.Helper()
	if len(m.diagnostics) != 1 {
		t.Fatalf("diagnostics=%d, want 1", len(m.diagnostics))
	}
	diagnostic := m.diagnostics[0]
	actualPath := m.sources[diagnostic.source].path
	if diagnostic.kind != kind || actualPath != path || diagnostic.start != start || diagnostic.end != end {
		t.Fatalf("diagnostic=%+v path=%q, want kind=%d %s:%d..%d", diagnostic, actualPath, kind, path, start, end)
	}
	if relatedPath == "" {
		if diagnostic.hasRelated {
			t.Fatalf("unexpected related diagnostic %+v", diagnostic)
		}
		return
	}
	actualRelatedPath := m.sources[diagnostic.relatedSource].path
	if !diagnostic.hasRelated || actualRelatedPath != relatedPath || diagnostic.relatedStart != relatedStart || diagnostic.relatedEnd != relatedEnd {
		t.Fatalf("related diagnostic=%+v path=%q, want %s:%d..%d", diagnostic, actualRelatedPath, relatedPath, relatedStart, relatedEnd)
	}
}

func TestCheckerManifestDecoderRejectsMalformed(t *testing.T) {
	inputs := map[string]string{"a.al": "x"}
	valid := "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nEND\n"
	if _, err := decodeCheckerManifest(valid, inputs); err != nil {
		t.Fatalf("valid minimal manifest: %v", err)
	}
	malformed := map[string]string{
		"version 6 envelope":          strings.Replace(valid, "MANIFEST 7", "MANIFEST 6", 1),
		"record after diagnostics":    "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nD 4 0 0 1 0\nC 1 1 0 1 0 0\nEND\n",
		"invalid primitive target":    "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nC 1 1 0 0 0 0\nD 4 0 0 1 0\nEND\n",
		"duplicate canonical type":    "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nC 1 1 0 1 0 0\nC 2 1 0 1 0 0\nD 4 0 0 1 0\nEND\n",
		"invalid type argument range": "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nC 1 8 0 0 1 1\nD 4 0 0 1 0\nEND\n",
		"annotation unknown owner":    "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nC 1 1 0 1 0 0\nT 1 1 1 1\nD 4 0 0 1 0\nEND\n",
		"orphan environment":          "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nN 1 1 0 1\nD 4 0 0 1 0\nEND\n",
		"truncated expression child":  "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nH 1\nEND\n",
	}
	bodyPrefix := "ALDER-CHECKER-MANIFEST 7\nS 0 612e616c 1\nY 1 12 1 0 0 1 0\nC 1 1 0 9 0 0\nC 2 1 0 1 0 0\nT 1 1 2 1\nT 2 1 3 1\nU 1 1 5 0 4 0 0 1 2 1\nU 2 1 6 0 5 0 0 0 3 1\nL 1 1 1 4 0 0 1 0 1\nN 1 1 0 1\n"
	validUnaryBody := bodyPrefix + "E 1 1 6 1 1 1 0 0 0 0 0 0 0 0 0\nE 2 1 8 6 1 0 0 0 0 0 1 1 1 3 7\nH 1 1\nR 1 1 7 2 2\nEND\n"
	if _, err := decodeCheckerManifest(validUnaryBody, inputs); err != nil {
		t.Fatalf("valid unary body manifest: %v", err)
	}
	malformed["invalid child range"] = strings.Replace(validUnaryBody, " 1 1 1 3 7\nH", " 2 1 1 3 7\nH", 1)
	malformed["forward child ID"] = strings.Replace(validUnaryBody, "H 1 1", "H 1 2", 1)
	malformed["invalid environment parent"] = strings.Replace(validUnaryBody, "N 1 1 0 1", "N 1 1 1 1", 1)
	malformed["invalid environment binding"] = strings.Replace(validUnaryBody, "N 1 1 0 1", "N 1 1 0 2", 1)
	malformed["binding type disagreement"] = strings.Replace(validUnaryBody, "E 1 1 6 1 1 1", "E 1 1 6 1 2 1", 1)
	for name, text := range malformed {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeCheckerManifest(text, inputs); err == nil {
				t.Fatalf("malformed manifest accepted:\n%s", text)
			}
		})
	}
}
