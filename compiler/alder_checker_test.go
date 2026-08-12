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
	"github.com/4fuu/alder/mir/verify"
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
fn ci_diag(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), uses: __s0_Buffer(DeclTypeUseRec)) -> I32 { return match __s0_buffer_new(CheckDiagRec, d) { Err(e) => 3 Ok(b) => match parse_sources(d, state, parse) { Err(e) => 3 Ok(r) => checker_parsed(d, r, CheckStore(symbols: symbols, type_params: params, types: types, type_args: args, uses: uses, diagnostics: b)) } } }
fn ci_uses(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64)) -> I32 { return match __s0_buffer_new(DeclTypeUseRec, d) { Err(e) => 3 Ok(b) => ci_diag(d,state,parse,symbols,params,types,args,b) } }
fn ci_args(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec)) -> I32 { return match __s0_buffer_new(U64, d) { Err(e) => 3 Ok(b) => ci_uses(d,state,parse,symbols,params,types,b) } }
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

type checkerTypeUse struct {
	id, owner, role, ordinal, node, source, nameStart, nameEnd, syntax, checkedType int
}

type checkerManifest struct {
	sources      []checkerSource
	sourceByPath map[string]int
	symbols      []checkerSymbol
	params       []checkerTypeParam
	types        []checkerType
	args         []checkerTypeArg
	uses         []checkerTypeUse
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
		if name != "main.al" {
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
	// This latest slice compiles the complete fixed production core (except its
	// lexer-only main, replaced by this wrapper) once. Round-trip and verify its
	// textual MIR before generating the C used for strict direct execution.
	compiled, err := Compile(Request{Sources: sources, Emit: EmitMIR})
	if err != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		t.Fatalf("compile checker MIR: result=%+v error=%v", compiled, err)
	}
	module, err := mir.Parse(compiled.Artifact.Text)
	if err != nil {
		t.Fatalf("parse checker MIR: %v", err)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify checker MIR: %s", verify.Errors(diagnostics).String())
	}
	for _, name := range []string{"collect_cycle_edges", "reject_value_cycles", "interpreted_type_equal", "direct_type_concrete", "interpreted_contains_reference", "interpreted_map_key_ok", "validate_concrete_type", "revalidate_aggregate_roots"} {
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
			"fn deferred() -> U64 {\n let local: Missing = nope\n return wrong\n}\n",
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
		"a.al": "type Concrete {\n outer: Outer(U64)\n bool_key: Map(Bool, U64)\n u8_key: Map(U8, U64)\n u16_key: Map(U16, U64)\n u32_key: Map(U32, U64)\n u64_key: Map(U64, U64)\n node: Node(U64)\n same: Same(U64)\n mutual: Left(U64)\n pointer_cut: PointerBox(Concrete)\n phantom: Phantom(String)\n}\n",
		"z.al": "type Key(T: type) { value: T }\n" +
			"type Transparent(T: type) { value: Key(T) }\n" +
			"enum Choice(T: type) { None\n Some(value: T) }\n" +
			"type Inner(T: type) { values: __s0_Buffer(T) }\n" +
			"type Outer(T: type) { key: Map(Key(T), Choice(T))\n inner: Inner(T) }\n" +
			"type Node(T: type) { next: Ptr(Node(T))\n value: T }\n" +
			"type Same(T: type) { next: Ptr(Same(U64)) }\n" +
			"type Left(T: type) { right: Ptr(Right(T)) }\n" +
			"type Right(T: type) { left: Ptr(Left(T)) }\n" +
			"type PointerBox(T: type) { value: Ptr(T) }\n" +
			"type Phantom(T: type) { value: U64 }\n",
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
	ffiGood := map[string]string{"ffi.al": "import c primitive_ffi: fn(Bool, I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Unit, Ptr(F64)) -> Unit\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, ffiGood, []string{"ffi.al"}, false), ffiGood)

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
		{name: "generic-substituted-value-cycle.al", text: "type Loop(T: type) { value: Box(Loop(T)) }\ntype Box(T: type) { value: T }\n", kind: 9, marker: "type"},
		{name: "substituted-cycle-before-forward-restriction.al", text: "type Root { value: Box(Root) }\ntype Box(T: type) { bad: Map(T, U64)\n value: T }\n", kind: 9, marker: "type"},
		{name: "substituted-cycle-sibling.al", text: "type Pair(T: type) { left: Box(T)\n right: Box(Root) }\ntype Box(T: type) { value: T }\ntype Root { value: Pair(U64) }\n", kind: 9, marker: "type"},
		{name: "nested-string-slice.al", text: "type A { x: [String] }\n", kind: 10, marker: "["},
		{name: "substituted-slice.al", text: "type Box(T: type) { x: [T] }\ntype A { x: Box(String) }\n", kind: 10, marker: "Box", last: true},
		{name: "multi-substituted-slice.al", text: "type Leaf(T: type) { x: [T] }\ntype Middle(T: type) { x: Leaf(T) }\ntype A { x: Middle(String) }\n", kind: 10, marker: "Middle", last: true},
		{name: "recursive-slice.al", text: "type A { x: [A] }\n", kind: 10, marker: "["},
		{name: "buffer-string.al", text: "type A { x: __s0_Buffer(String) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "substituted-buffer.al", text: "type Box(T: type) { x: __s0_Buffer(T) }\ntype A { x: Box(String) }\n", kind: 11, marker: "Box", last: true},
		{name: "recursive-buffer.al", text: "type A { x: __s0_Buffer(A) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "map-key-before-value.al", text: "type Pair(K: type, V: type) { x: Map(K, V) }\ntype A { x: Pair(I64, String) }\n", kind: 12, marker: "Pair", last: true},
		{name: "map-key-float.al", text: "type A { x: Map(F64, U64) }\n", kind: 12, marker: "Map"},
		{name: "map-key-generic.al", text: "type Key(T: type) { x: T }\ntype A { x: Map(Key(I64), String) }\n", kind: 12, marker: "Map"},
		{name: "substituted-map-value.al", text: "type Pair(K: type, V: type) { x: Map(K, V) }\ntype A { x: Pair(U64, String) }\n", kind: 13, marker: "Pair", last: true},
		{name: "declared-map-value.al", text: "type Value(T: type) { x: T }\ntype A { x: Map(U64, Value(String)) }\n", kind: 13, marker: "Map"},
		{name: "struct-member-order.al", text: "type Fields(T: type) { first: __s0_Buffer(T)\n second: Map(T, U64) }\ntype A { x: Fields(String) }\n", kind: 11, marker: "Fields", last: true},
		{name: "enum-member-order.al", text: "enum E(T: type) { First(value: __s0_Buffer(T))\n Second(value: Map(T, U64)) }\ntype A { x: E(String) }\n", kind: 11, marker: "E", last: true},
		{name: "changed-recursive-specialization.al", text: "type A(T: type) { next: Ptr(A(Option(T))) }\ntype Root { x: A(U64) }\n", kind: 14, marker: "A", last: true},
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
	if len(lines) < 2 || lines[0] != "ALDER-CHECKER-MANIFEST 2" || lines[len(lines)-1] != "END" {
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
		recordPhase := map[string]int{"S": 0, "Y": 1, "P": 2, "C": 3, "A": 4, "U": 5, "D": 6}[fields[0]]
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
		case "U":
			if err != nil || len(numbers) != 10 {
				return m, fmt.Errorf("line %d has invalid U record", lineNumber+2)
			}
			m.uses = append(m.uses, checkerTypeUse{id: numbers[0], owner: numbers[1], role: numbers[2], ordinal: numbers[3], node: numbers[4], source: numbers[5], nameStart: numbers[6], nameEnd: numbers[7], syntax: numbers[8], checkedType: numbers[9]})
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
	for i, checked := range m.types {
		if checked.id != i+1 || checked.kind < 1 || checked.kind > 13 || checked.syntax < 1 || typeSyntax[checked.syntax] || (checked.count == 0) != (checked.first == 0) || checked.first < 0 || checked.count < 0 || checked.count > 0 && (checked.first < 1 || checked.first-1 > len(m.args) || checked.count > len(m.args)-(checked.first-1)) {
			return fmt.Errorf("invalid checked type %+v", checked)
		}
		typeSyntax[checked.syntax] = true
		if checked.target != 0 && checked.kind != 6 && checked.kind != 7 {
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
	for i, owners := range argOwners {
		if owners != 1 {
			return fmt.Errorf("type argument %d has %d owners", i+1, owners)
		}
	}
	if len(m.diagnostics) == 0 {
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
		if use.id != i+1 || use.owner < 1 || use.owner > len(m.symbols) || use.role < 1 || use.role > 6 || !roleMatchesOwner || use.ordinal != ordinals[key] || use.node < 1 || nodes[use.node] || !validSourceRange(use.source, use.nameStart, use.nameEnd, named) || named != (use.nameStart != 0 || use.nameEnd != 0) || !valueless && (use.syntax < 1 || use.checkedType < 1 || use.checkedType > len(m.types) || m.types[use.checkedType-1].syntax != use.syntax) || valueless && (use.nameStart == 0 || use.nameEnd == 0) {
			return fmt.Errorf("invalid declaration type use %+v", use)
		}
		nodes[use.node] = true
		if !valueless {
			checkedIndex := use.checkedType - 1
			typeOwners[checkedIndex]++
			if typeSemanticOwners[checkedIndex] != 0 && typeSemanticOwners[checkedIndex] != use.owner {
				return fmt.Errorf("checked type %d has declaration owners %d and %d", use.checkedType, typeSemanticOwners[checkedIndex], use.owner)
			}
			typeSemanticOwners[checkedIndex] = use.owner
		}
		ordinals[key]++
	}
	for i, owners := range typeOwners {
		if owners > 1 || len(m.diagnostics) == 0 && owners != 1 {
			return fmt.Errorf("checked type %d has %d owners", i+1, owners)
		}
	}
	for i := len(m.types) - 1; i >= 0; i-- {
		owner := typeSemanticOwners[i]
		if owner == 0 {
			continue
		}
		for _, arg := range checkerDirectArgs(m, m.types[i]) {
			childIndex := arg.checkedType - 1
			if typeSemanticOwners[childIndex] != 0 && typeSemanticOwners[childIndex] != owner {
				return fmt.Errorf("checked type %d has declaration owners %d and %d", arg.checkedType, typeSemanticOwners[childIndex], owner)
			}
			typeSemanticOwners[childIndex] = owner
		}
	}
	for i, checked := range m.types {
		if checked.kind == 6 && typeSemanticOwners[i] != 0 && m.params[checked.target-1].owner != typeSemanticOwners[i] {
			return fmt.Errorf("checked type %+v targets a parameter outside declaration owner %d", checked, typeSemanticOwners[i])
		}
	}
	if len(m.diagnostics) > 1 {
		return fmt.Errorf("manifest has %d diagnostics, want at most one", len(m.diagnostics))
	}
	for _, diagnostic := range m.diagnostics {
		if diagnostic.kind < 1 || diagnostic.kind > 15 || !validSourceRange(diagnostic.source, diagnostic.start, diagnostic.end, true) || diagnostic.hasRelated != (diagnostic.kind == 1 || diagnostic.kind == 3) {
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
	if kind := m.types[checkerUse(t, m, nest.id, 1, 6).checkedType-1].kind; kind != 2 {
		t.Fatalf("Nest String field kind=%d, want 2", kind)
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
	if len(m.uses) != 85 || m.types[checkerUse(t, m, deferred.id, 6, 0).checkedType-1].kind != 1 {
		t.Fatalf("deferred body was checked or declaration-use count changed: %d", len(m.uses))
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
	valid := "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nEND\n"
	if _, err := decodeCheckerManifest(valid, inputs); err != nil {
		t.Fatalf("valid minimal manifest: %v", err)
	}
	partial := "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nC 1 1 1 0 0 0\nD 4 0 0 1 0\nEND\n"
	if _, err := decodeCheckerManifest(partial, inputs); err != nil {
		t.Fatalf("valid partial failure manifest: %v", err)
	}
	malformed := map[string]string{
		"missing final line break":   strings.TrimSuffix(valid, "\n"),
		"blank record":               "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\n\nEND\n",
		"unknown record":             "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nQ 1\nEND\n",
		"invalid path hex":           "ALDER-CHECKER-MANIFEST 2\nS 0 zz 1\nEND\n",
		"noncanonical path hex":      "ALDER-CHECKER-MANIFEST 2\nS 0 612E616C 1\nEND\n",
		"unknown source":             "ALDER-CHECKER-MANIFEST 2\nS 0 67686f73742e616c 1\nEND\n",
		"duplicate source":           "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nS 1 612e616c 1\nEND\n",
		"negative integer":           "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nY 1 2 1 0 -1 0 0\nEND\n",
		"noncanonical integer":       "ALDER-CHECKER-MANIFEST 2\nS 00 612e616c 1\nEND\n",
		"nonsequential ID":           "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nY 2 2 1 0 0 1 0\nEND\n",
		"truncated diagnostic":       "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nD 1\nEND\n",
		"unknown diagnostic kind":    "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nD 16 0 0 1 0\nEND\n",
		"invalid related flag":       "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nD 1 0 0 1 2\nEND\n",
		"invalid argument range":     "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nC 1 1 1 0 0 1\nEND\n",
		"malformed declaration item": "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nY 1 2 1 0 0 1 0\nU 1 1 1 0 2 0 0 1 0 0\nEND\n",
		"ownerless failed argument":  "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nC 1 1 1 0 0 0\nA 1 1\nD 4 0 0 1 0\nEND\n",
		"multiply-owned failed type": "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nY 1 2 1 0 0 1 0\nC 1 1 1 0 0 0\nU 1 1 1 0 2 0 0 1 1 1\nU 2 1 1 1 3 0 0 1 1 1\nD 6 0 0 1 0\nEND\n",
		"foreign type parameter":     "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nY 1 2 1 0 0 1 1\nY 2 2 2 0 0 1 1\nP 1 1 3 0 0 1\nP 2 2 4 0 0 1\nC 1 6 5 2 0 0\nU 1 1 1 0 6 0 0 1 5 1\nEND\n",
		"multiple diagnostics":       "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nD 4 0 0 1 0\nD 5 0 0 1 0\nEND\n",
		"unreachable success type":   "ALDER-CHECKER-MANIFEST 2\nS 0 612e616c 1\nC 1 1 1 0 0 0\nEND\n",
	}
	for name, text := range malformed {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeCheckerManifest(text, inputs); err == nil {
				t.Fatalf("malformed manifest accepted:\n%s", text)
			}
		})
	}
	unorderedInputs := map[string]string{"a.al": "", "b.al": ""}
	unorderedSources := "ALDER-CHECKER-MANIFEST 2\nS 0 622e616c 0\nS 1 612e616c 0\nEND\n"
	if _, err := decodeCheckerManifest(unorderedSources, unorderedInputs); err == nil {
		t.Fatalf("noncanonical source order accepted:\n%s", unorderedSources)
	}
}
