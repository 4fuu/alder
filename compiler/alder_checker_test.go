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
)

const checkerWrapper = `
fn checker_storage_error() -> I32 { return 3 }
fn checker_good(state: State, parse: ParseStore, store: CheckStore) -> I32 {
 if !emit_check_manifest(state, parse, store) { return 4 }
 return 0
}
fn checker_bad(state: State, parse: ParseStore, store: CheckStore) -> I32 {
 if !emit_check_manifest(state, parse, store) { return 4 }
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
fn checker_done(state: State, parse: ParseStore, result: CheckResult) -> I32 { return match result {
 CheckGood(store) => checker_good(state, parse, store)
 CheckBad(store) => checker_bad(state, parse, store)
} }
fn checker_check(d: Domain, output: ParseOutput, store: CheckStore) -> I32 { return match check_parsed(d, output.state, output.store, store) {
 Err(error) => checker_storage_error()
 Ok(result) => checker_done(output.state, output.store, result)
} }
fn checker_parsed(d: Domain, result: ParseResult, store: CheckStore) -> I32 { return match result {
 ParseGood(output) => checker_check(d, output, store)
 ParseBad(output) => checker_parse_bad(output.state, output.store)
 ParseLexBad(output) => checker_lex_bad(output.state)
} }
fn ci_diag(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec), calls: __s0_Buffer(CallAnnotationRec), children: __s0_Buffer(CheckedExprChildRec), returns: __s0_Buffer(CheckedReturnRec)) -> I32 { return match __s0_buffer_new(CheckedBlockRec, d) { Err(e) => 3 Ok(blocks) => match __s0_buffer_new(CheckedStatementLinkRec, d) { Err(e) => 3 Ok(links) => match __s0_buffer_new(CheckedStatementRec, d) { Err(e) => 3 Ok(statements) => match __s0_buffer_new(CheckedPlaceRec, d) { Err(e) => 3 Ok(places) => match __s0_buffer_new(CheckedMatchRec, d) { Err(e) => 3 Ok(matches) => match __s0_buffer_new(CheckedMatchArmRec, d) { Err(e) => 3 Ok(arms) => match __s0_buffer_new(CheckedTryRec, d) { Err(e) => 3 Ok(tries) => match __s0_buffer_new(CheckedCleanupRec, d) { Err(e) => 3 Ok(cleanups) => match __s0_buffer_new(CheckDiagRec, d) { Err(e) => 3 Ok(b) => match __s0_buffer_new(CheckerUseIndexRec, d) { Err(e) => 3 Ok(use_indexes) => match __s0_buffer_new(U64, d) { Err(e) => 3 Ok(use_order) => match empty_trait_store(d) { Err(e) => 3 Ok(traits) => match parse_sources(d, state, parse) { Err(e) => 3 Ok(r) => checker_parsed(d, r, CheckStore(symbols: symbols, type_params: params, types: types, type_args: args, type_annotations: annotations, uses: uses, indexes: CheckerIndexes(uses: use_indexes, use_order: use_order, complete: false), locals: locals, environments: envs, expressions: exprs, call_annotations: calls, expression_children: children, returns: returns, control: CheckedControlStore(blocks: blocks, statement_links: links, statements: statements, places: places, matches: matches, match_arms: arms, tries: tries, cleanups: cleanups), diagnostics: b, traits: traits)) } } } } } } } } } } } } } }
fn ci_returns(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec), calls: __s0_Buffer(CallAnnotationRec), children: __s0_Buffer(CheckedExprChildRec)) -> I32 { return match __s0_buffer_new(CheckedReturnRec, d) { Err(e) => 3 Ok(b) => ci_diag(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,exprs,calls,children,b) } }
fn ci_children(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec), calls: __s0_Buffer(CallAnnotationRec)) -> I32 { return match __s0_buffer_new(CheckedExprChildRec, d) { Err(e) => 3 Ok(b) => ci_returns(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,exprs,calls,b) } }
fn ci_calls(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec), exprs: __s0_Buffer(CheckedExprRec)) -> I32 { return match __s0_buffer_new(CallAnnotationRec, d) { Err(e) => 3 Ok(b) => ci_children(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,exprs,b) } }
fn ci_exprs(d: Domain, state: State, parse: ParseStore, symbols: __s0_Buffer(SymbolRec), params: __s0_Buffer(TypeParamRec), types: __s0_Buffer(CheckedTypeRec), args: __s0_Buffer(U64), annotations: __s0_Buffer(CheckedTypeAnnotationRec), uses: __s0_Buffer(DeclTypeUseRec), locals: __s0_Buffer(LocalRec), envs: __s0_Buffer(EnvironmentRec)) -> I32 { return match __s0_buffer_new(CheckedExprRec, d) { Err(e) => 3 Ok(b) => ci_calls(d,state,parse,symbols,params,types,args,annotations,uses,locals,envs,b) } }
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

type checkerSpan struct{ id, source, start, end, nameStart, nameEnd int }

type checkerSymbol struct {
	id, kind, node, source, start, end, arity                        int
	declaration, firstInstanceArg, instanceArgCount, discoveryParent int
}

type checkerInstance struct {
	id, symbol, declaration, firstArg, argCount, discoveryParent int
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

type checkerCallAnnotation struct {
	id, owner, kind, target, checkedType, variantUse, builtin int
}

type checkerExpressionChild struct{ id, expression int }

type checkerReturn struct {
	id, owner, syntax, expression, resultUse int
}

type checkerPlace struct {
	id, owner, syntax, kind, root, field, index, checkedType int
}

type checkerStatement struct {
	id, owner, syntax, kind, environment, expression, place, binding, body, alternative int
}

type checkerStatementLink struct{ id, statement, next int }

type checkerBlock struct {
	id, owner, syntax, environment, statements, guaranteedReturn int
}

type checkerMatch struct{ id, owner, syntax, scrutinee, scrutineeType, checkedType, firstArm, armCount int }
type checkerMatchArm struct{ id, owner, syntax, checkedMatch, variantUse, variantKind, binding, environment, body int }
type checkerTry struct{ id, owner, syntax, expression, resultType, okType, errorType int }
type checkerCleanup struct {
	id, owner, syntax, environment, binding, initializer, callback int
	normalExit, returnExit, tryExit                                int
}

type checkerManifest struct {
	sources         []checkerSource
	sourceByPath    map[string]int
	spans           []checkerSpan
	symbols         []checkerSymbol
	params          []checkerTypeParam
	types           []checkerType
	args            []checkerTypeArg
	annotations     []checkerTypeAnnotation
	uses            []checkerTypeUse
	instances       []checkerInstance
	locals          []checkerLocal
	environments    []checkerEnvironment
	callAnnotations []checkerCallAnnotation
	expressions     []checkerExpression
	children        []checkerExpressionChild
	returns         []checkerReturn
	places          []checkerPlace
	statements      []checkerStatement
	statementLinks  []checkerStatementLink
	blocks          []checkerBlock
	matches         []checkerMatch
	matchArms       []checkerMatchArm
	tries           []checkerTry
	cleanups        []checkerCleanup
	diagnostics     []checkerDiagnostic
}
type checkerDiagnostic struct {
	kind, source, start, end                int
	hasRelated                              bool
	relatedSource, relatedStart, relatedEnd int
	note                                    int
}

func runCheckerConformance(t *testing.T, exe string) {
	t.Run("m71-collections", func(t *testing.T) { runAlderM71CheckerBehavior(t, exe) })
	t.Run("m73-storage-views", func(t *testing.T) { runAlderM73CheckerBehavior(t, exe) })
	t.Run("m75-traits", func(t *testing.T) { runAlderM75CheckerBehavior(t, exe) })
	t.Run("m75-ordered", func(t *testing.T) { runAlderM75OrderedCheckerBehavior(t, exe) })
	for _, fixture := range []string{"basic", "generics", "match", "try", "cleanup", "ffi", "buffer"} {
		t.Run("shared-accept-"+fixture, func(t *testing.T) {
			text, err := os.ReadFile(filepath.Join("..", "frontend", "testdata", "accept", fixture+".al"))
			if err != nil {
				t.Fatal(err)
			}
			name := fixture + ".al"
			files := map[string]string{name: string(text)}
			first := runAlderChecker(t, exe, files, []string{name}, false)
			second := runAlderChecker(t, exe, files, []string{name}, false)
			if first != second {
				t.Fatalf("shared accept %s was not process deterministic", fixture)
			}
			manifest := parseCheckerManifest(t, first, files)
			if len(manifest.spans) == 0 || len(manifest.diagnostics) != 0 {
				t.Fatalf("shared accept %s was not complete: spans=%d diagnostics=%+v", fixture, len(manifest.spans), manifest.diagnostics)
			}
		})
	}
	for _, fixture := range []string{"unknown-name", "unknown-type", "type-mismatch", "immutable-assign", "map-key-signed", "map-value-string", "nested-slice", "type-cycle", "match-nonexhaustive", "match-unknown-variant", "try-not-result", "try-error-mismatch", "using-in-loop", "using-callback-type", "literal-out-of-range", "fall-off-end", "reserved-name", "duplicate-decl", "alloc-as-slice-param", "bind-mark", "bind-unit", "ffi-unsupported-type", "float-arithmetic", "index-not-u64", "shadowing", "unreachable-statement", "function-value"} {
		t.Run("shared-reject-"+fixture, func(t *testing.T) {
			text, err := os.ReadFile(filepath.Join("..", "frontend", "testdata", "reject", fixture+".al"))
			if err != nil {
				t.Fatal(err)
			}
			want, err := os.ReadFile(filepath.Join("..", "frontend", "testdata", "reject", fixture+".err"))
			if err != nil {
				t.Fatal(err)
			}
			var line, column int
			if _, err := fmt.Sscanf(string(want), "line %d, column %d:", &line, &column); err != nil {
				t.Fatalf("parse shared diagnostic position: %v", err)
			}
			start := 0
			for current := 1; current < line; current++ {
				next := strings.IndexByte(string(text)[start:], '\n')
				if next < 0 {
					t.Fatalf("shared diagnostic line %d is outside source", line)
				}
				start += next + 1
			}
			start += column - 1
			name := fixture + ".al"
			files := map[string]string{name: string(text)}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{name}, true), files)
			if len(manifest.diagnostics) != 1 || manifest.diagnostics[0].start != start {
				t.Fatalf("shared reject %s first failure changed: got=%+v want-start=%d", fixture, manifest.diagnostics, start)
			}
		})
	}
	good := map[string]string{
		"a space.al": "import c foreign: fn(U64, Ptr(U8),) -> I32\n" +
			"type Box(T: type) { value: T }\n" +
			"type Nest {\n x: Map(U64, Option(U8))\n a: [U8]\n b: Result(U64, __s0_Error)\n c: Ptr(Domain)\n d: __s0_Buffer(U64)\n mark: DomainMark\n text: String\n bytes: Bytes\n}\n" +
			"enum E {\n Empty\n Full(value: Box(U64))\n}\n" +
			"fn f(T: type, x: T, y: Box(T),) -> Option(U64) {}\n" +
			"type Other(T: type) { value: T }\n" +
			"fn controlled() -> U64 {\n while true {}\n return 0\n}\n",
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
	matchTryText := "fn matched(value: Option(U64)) -> U64 { return match value {\n None => 0\n Some(item) => item\n} }\n" +
		"fn noop() -> Unit { return }\n" +
		"fn matched_statement(value: Option(U64)) -> Unit { match value {\n None => noop()\n Some(item) => noop()\n}\n return }\n" +
		"fn tried(value: Result(U64, __s0_Error)) -> Result(U64, __s0_Error) { return Ok(try value) }\n"
	matchTryFiles := map[string]string{"match-try.al": matchTryText}
	matchTry := parseCheckerManifest(t, runAlderChecker(t, exe, matchTryFiles, []string{"match-try.al"}, false), matchTryFiles)
	if len(matchTry.matches) != 2 || len(matchTry.matchArms) != 4 || len(matchTry.tries) != 1 {
		t.Fatalf("checked match records changed: matches=%+v arms=%+v tries=%+v diagnostics=%+v", matchTry.matches, matchTry.matchArms, matchTry.tries, matchTry.diagnostics)
	}
	runMatchTryCheckerConformance(t, exe)
	runCheckerShadowingConformance(t, exe)
	runOwnerReplayAndErrorConstructors(t, exe)
	cleanupText := "fn close(value: U64) -> Unit { return }\n" +
		"fn make() -> Result(U64, __s0_Error) { return Ok(2) }\n" +
		"fn f(flag: Bool, seed: U64) -> Result(U64, __s0_Error) {\n using outer = seed with close\n { using inner = seed with close\n  let made = try make()\n  while flag {} }\n return Ok(outer)\n}\n"
	cleanupFiles := map[string]string{"cleanup.al": cleanupText}
	cleanupOne := runAlderChecker(t, exe, cleanupFiles, []string{"cleanup.al"}, false)
	cleanupTwo := runAlderChecker(t, exe, cleanupFiles, []string{"cleanup.al"}, false)
	if cleanupOne != cleanupTwo {
		t.Fatal("cleanup manifest was not deterministic")
	}
	cleanupManifest := parseCheckerManifest(t, cleanupOne, cleanupFiles)
	if len(cleanupManifest.cleanups) != 2 || len(cleanupManifest.tries) != 1 {
		t.Fatalf("cleanup/try facts changed: cleanups=%+v tries=%+v", cleanupManifest.cleanups, cleanupManifest.tries)
	}
	if cleanupManifest.cleanups[0].environment == cleanupManifest.cleanups[1].environment || cleanupManifest.cleanups[0].callback != cleanupManifest.cleanups[1].callback {
		t.Fatalf("nested cleanup ownership changed: %+v", cleanupManifest.cleanups)
	}
	builtinText := "fn builtins(d: Domain, b: __s0_Buffer(U64), m: DomainMark) -> Result(__s0_Buffer(U64), __s0_Error) {\n" +
		" let raw: [U64] = __s0_alloc(U64, d, 2)\n let child = __s0_domain_create(d)\n __s0_domain_reset(child, __s0_domain_mark(child))\n __s0_domain_destroy(child)\n" +
		" let map = __s0_map_create(Map(U64, U64), d)\n Set(map, 1, 2)\n let found: Option(U64) = Get(U64, U64, map, 1)\n let removed: Bool = Remove(map, 1)\n" +
		" let empty = try __s0_buffer_new(U64, d)\n let size = __s0_buffer_len(U64, b)\n let grown = try __s0_buffer_append(U64, d, empty, size)\n let item = __s0_buffer_get(U64, grown, 0)\n __s0_buffer_set(U64, grown, 0, item)\n let view: [U64] = __s0_buffer_slice(U64, grown)\n return Ok(grown)\n}\n"
	builtinFiles := map[string]string{"builtins.al": builtinText}
	builtinOne := runAlderChecker(t, exe, builtinFiles, []string{"builtins.al"}, false)
	builtinTwo := runAlderChecker(t, exe, builtinFiles, []string{"builtins.al"}, false)
	if builtinOne != builtinTwo {
		t.Fatal("builtin manifest was not deterministic")
	}
	builtinManifest := parseCheckerManifest(t, builtinOne, builtinFiles)
	seenBuiltins := make(map[int]bool)
	for _, annotation := range builtinManifest.callAnnotations {
		seenBuiltins[annotation.builtin] = true
	}
	for _, identity := range []int{3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17} {
		if !seenBuiltins[identity] {
			t.Fatalf("builtin identity %d was not annotated", identity)
		}
	}
	if len(builtinManifest.tries) != 2 {
		t.Fatalf("new/append try facts changed: %+v", builtinManifest.tries)
	}
	builtinRejects := []string{
		"fn f(d: Domain) -> [U64] { return __s0_alloc(U64, d) }\n",
		"fn f() -> Domain { return __s0_domain_create() }\n",
		"fn f() -> DomainMark { return __s0_domain_mark() }\n",
		"fn f(d: Domain) -> Unit { return __s0_domain_reset(d) }\n",
		"fn f() -> Unit { return __s0_domain_destroy() }\n",
		"fn f(d: Domain) -> Result(__s0_Buffer(U64), __s0_Error) { return __s0_buffer_new(U64, false) }\n",
		"fn f(b: __s0_Buffer(U64)) -> U64 { return __s0_buffer_len(U8, b) }\n",
		"fn f(d: Domain, b: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) { return __s0_buffer_append(U64, d, b, false) }\n",
		"fn f(b: __s0_Buffer(U64)) -> U64 { return __s0_buffer_get(U64, b, false) }\n",
		"fn f(b: __s0_Buffer(U64)) -> Unit { return __s0_buffer_set(U64, b, 0, false) }\n",
		"fn f(b: __s0_Buffer(U64)) -> [U8] { return __s0_buffer_slice(U64, b) }\n",
		"fn f(d: Domain) -> [U64] { return __s0_alloc(Missing, d, 1) }\n",
		"fn f(d: Domain) -> Map(U64, U64) { return __s0_map_create(U64, d) }\n",
		"fn f(m: Map(U64, U64)) -> Option(U64) { return Get(U64, m, 1) }\n",
		"fn f(m: Map(U64, U64)) -> Unit { return Set(m, false, 1) }\n",
		"fn f(m: Map(U64, U64)) -> Bool { return Remove(U8, U64, m, 1) }\n",
	}
	for index, text := range builtinRejects {
		t.Run(fmt.Sprintf("builtin-reject-%02d", index), func(t *testing.T) {
			name := fmt.Sprintf("builtin-reject-%02d.al", index)
			files := map[string]string{name: text}
			rejected := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{name}, true), files)
			if len(rejected.diagnostics) != 1 || len(rejected.callAnnotations) != 0 {
				t.Fatalf("builtin rejection %d retained malformed identity: diagnostics=%+v annotations=%+v", index, rejected.diagnostics, rejected.callAnnotations)
			}
		})
	}
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
		"a.al": "type Concrete {\n outer: Outer(U64)\n bool_key: Map(Bool, U64)\n u8_key: Map(U8, U64)\n u16_key: Map(U16, U64)\n u32_key: Map(U32, U64)\n u64_key: Map(U64, U64)\n nested_key: Map(PairKey(U8, PairKey(Bool, U64)), U64)\n nested_box: CallerBox(CallerBox(U64))\n node: Node(U64)\n same: Same(U64)\n mutual: Left(U64)\n pointer_cut: PointerBox(Concrete)\n phantom: Phantom(String)\n}\n",
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
	canonicalGood := map[string]string{"canonical.al": "type Shared { first: Option(U64)\n second: Option(U64)\n text: String\n slice: [U8]\n bytes: Bytes }\n"}
	canonicalManifest := parseCheckerManifest(t, runAlderChecker(t, exe, canonicalGood, []string{"canonical.al"}, false), canonicalGood)
	shared := checkerSymbolByName(t, canonicalManifest, canonicalGood, "Shared")
	canonicalFirst, canonicalSecond := checkerUse(t, canonicalManifest, shared.id, 1, 0), checkerUse(t, canonicalManifest, shared.id, 1, 1)
	text, sliceUse, bytesUse := checkerUse(t, canonicalManifest, shared.id, 1, 2), checkerUse(t, canonicalManifest, shared.id, 1, 3), checkerUse(t, canonicalManifest, shared.id, 1, 4)
	if canonicalFirst.checkedType != canonicalSecond.checkedType || canonicalFirst.syntax == canonicalSecond.syntax || text.checkedType == sliceUse.checkedType || text.checkedType == bytesUse.checkedType || sliceUse.checkedType == bytesUse.checkedType {
		t.Fatalf("canonical identities changed: first=%+v second=%+v text=%+v slice=%+v bytes=%+v", canonicalFirst, canonicalSecond, text, sliceUse, bytesUse)
	}
	functionNameGood := map[string]string{"functions.al": "fn helper() -> U64 { return 0 }\nfn use(T: type, helper: T, T: T) -> T {}\nfn main(value: U64) -> Bool { return true }\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, functionNameGood, []string{"functions.al"}, false), functionNameGood)
	categoryGood := map[string]string{"categories.al": "type Owner { domain: Domain }\nfn inspect(value: Owner) -> Unit {}\nfn update(mut value: Owner) -> Unit {}\nfn install(take value: Owner) -> Owner { return value }\nfn edit(mut view: [U8]) -> Unit {}\nfn pass(take value: Owner) -> Owner { return install(value) }\nfn change(mut value: Owner) -> Unit { update(value) }\nfn branch(take value: Owner, flag: Bool) -> Owner { if flag { return install(value) } else { return install(value) } }\nfn forward(T: type, take value: T) -> T { return value }\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, categoryGood, []string{"categories.al"}, false), categoryGood)
	methodGood := map[string]string{"methods.al": "type Counter { value: U64 }\ntype Owner { domain: Domain }\nimpl Counter {\nfn new(value: U64) -> Counter { return Counter(value: value) }\nfn read(self) -> U64 { return self.value }\nfn write(mut self, value: U64) -> Unit { self.value = value }\nfn echo(T: type, self, value: T) -> T { return value }\n}\nimpl Owner {\nfn consume(take self) -> Owner { return self }\n}\nfn use(value: Counter) -> U64 { var local: Counter = value\n local.write(7)\n return local.echo(local.read()) }\nfn make() -> Counter { return Counter.new(3) }\nfn consume(take value: Owner) -> Owner { return value.consume() }\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, methodGood, []string{"methods.al"}, false), methodGood)
	arrayGood := map[string]string{"arrays.al": "fn identity(T: type, value: T) -> T { return value }\nfn read() -> U64 { let values: Array(U64, 3) = [1, 2, 3]\n return values[1] }\nfn write() -> U64 { var values: Array(U64, 3) = identity([1, 2, 3])\n values[1] = 7\n return values[1] }\nfn empty() -> Array(U64, 0) { return [] }\n"}
	arrayManifest := parseCheckerManifest(t, runAlderChecker(t, exe, arrayGood, []string{"arrays.al"}, false), arrayGood)
	arrayKinds := make(map[int]bool)
	for _, checked := range arrayManifest.types {
		arrayKinds[checked.kind] = true
	}
	if !arrayKinds[15] {
		t.Fatal("array fixture did not retain the fixed-array checked type")
	}
	arrayRejects := []struct {
		name, text string
		kind       int
	}{
		{name: "array-mixed.al", text: "fn f() -> Array(U64, 2) { return [1, true] }\n", kind: 98},
		{name: "array-length.al", text: "fn f() -> Array(U64, 2) { return [1] }\n", kind: 98},
		{name: "array-empty-inferred.al", text: "fn f() -> Unit { let values = []\n return }\n", kind: 97},
		{name: "array-negative-length.al", text: "fn f() -> Array(U64, -1) {}\n", kind: 96},
		{name: "array-overflow-length.al", text: "fn f() -> Array(U64, 18446744073709551616) {}\n", kind: 96},
		{name: "array-noninteger-length.al", text: "fn f() -> Array(U64, U64) {}\n", kind: 96},
		{name: "array-immutable-index.al", text: "fn f() -> Unit { let values: Array(U64, 1) = [1]\n values[0] = 2 }\n", kind: 28},
	}
	for _, tc := range arrayRejects {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name: tc.text}
			first := runAlderChecker(t, exe, files, []string{tc.name}, true)
			second := runAlderChecker(t, exe, files, []string{tc.name}, true)
			if first != second {
				t.Fatal("array diagnostic changed across processes")
			}
			manifest := parseCheckerManifest(t, first, files)
			if len(manifest.diagnostics) != 1 || manifest.diagnostics[0].kind != tc.kind {
				t.Fatalf("array diagnostic=%+v, want kind %d", manifest.diagnostics, tc.kind)
			}
		})
	}
	bodyGood := map[string]string{
		"a.al": "type Pair(T: type) { value: T }\n" +
			"fn identity(value: U64) -> U64 { return value }\n" +
			"fn choose(first: I64, second: U64) -> U64 { return second }\n" +
			"fn string_identity(value: String) -> String { return value }\n" +
			"fn bytes_identity(value: Bytes) -> Bytes { return value }\n" +
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
			"fn raw() -> Bytes { return \"bytes\" }\n" +
			"fn empty_string() -> String { return \"\" }\n" +
			"fn local_param(value: U64) -> U64 { let x: U64 = value\n return x }\n" +
			"fn local_assign() -> U64 { var y: U64 = 5\n y = 7\n return y }\n" +
			"fn local_literal() -> I64 { let z: I64 = -3\n return z }\n" +
			"fn local_string(value: String) -> String { let s: String = value\n return s }\n",
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
	for _, name := range []string{"identity", "choose", "string_identity", "bytes_identity", "declared"} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		checkedReturn := checkerReturnForOwner(t, bodyManifest, owner.id)
		if checkedReturn.expression == 0 || bodyManifest.expressions[checkedReturn.expression-1].owner != owner.id {
			t.Fatalf("function %s has invalid checked return %+v", name, checkedReturn)
		}
	}
	controlGood := map[string]string{"control.al": "type Box(T: type) { value: T }\n" +
		"fn branches(flag: Bool, mut values: [U64], mut boxes: [Box(U64)]) -> U64 {\n var direct: U64 = 0\n direct = 1\n var box: Box(U64) = Box(value: direct)\n box.value = 2\n values[0] = 3\n boxes[0].value = 4\n { let nested: U64 = direct }\n { let sibling: U64 = direct }\n if flag { let yes: U64 = direct\n return yes } else { let no: U64 = direct\n return no }\n}\n" +
		"fn loops(flag: Bool, values: [U64]) -> Unit {\n while flag { let inside: U64 = 1 }\n for item in values { let copy: U64 = item }\n}\n" +
		"fn fallthrough() -> Unit {}\n"}
	controlGood["control.al"] += "fn deep_blocks() -> Unit {"
	for i := 0; i < 16; i++ {
		controlGood["control.al"] += " {"
	}
	controlGood["control.al"] += " let deepest: U64 = 1"
	for i := 0; i < 16; i++ {
		controlGood["control.al"] += " }"
	}
	controlGood["control.al"] += " }\nfn long_block() -> Unit {\n"
	for i := 0; i < 64; i++ {
		controlGood["control.al"] += fmt.Sprintf(" let item%02d: U64 = %d\n", i, i)
	}
	controlGood["control.al"] += "}\n"
	controlManifest := parseCheckerManifest(t, runAlderChecker(t, exe, controlGood, []string{"control.al"}, false), controlGood)
	if len(controlManifest.blocks) < 24 || len(controlManifest.statements) < 99 || len(controlManifest.places) != 4 {
		t.Fatalf("control records are incomplete: blocks=%d statements=%d places=%d", len(controlManifest.blocks), len(controlManifest.statements), len(controlManifest.places))
	}
	choose := checkerSymbolByName(t, bodyManifest, bodyGood, "choose")
	chooseExpression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, choose.id).expression-1]
	if parameter := bodyManifest.locals[chooseExpression.parameterUse-1]; chooseExpression.kind != 1 || chooseExpression.boolValue != 0 || parameter.kind != 1 || checkerSourceText(bodyManifest, bodyGood, parameter.source, parameter.nameStart, parameter.nameEnd) != "second" {
		t.Fatalf("multi-parameter return resolved the wrong binding: %+v", parameter)
	}
	stringIdentity := checkerSymbolByName(t, bodyManifest, bodyGood, "string_identity")
	stringExpression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, stringIdentity.id).expression-1]
	if bodyManifest.types[stringExpression.checkedType-1].kind != 2 || bodyManifest.types[checkerUse(t, bodyManifest, stringIdentity.id, 6, 0).checkedType-1].kind != 2 {
		t.Fatal("String identity did not retain String")
	}
	bytesIdentity := checkerSymbolByName(t, bodyManifest, bodyGood, "bytes_identity")
	bytesExpression := bodyManifest.expressions[checkerReturnForOwner(t, bodyManifest, bytesIdentity.id).expression-1]
	if bodyManifest.types[bytesExpression.checkedType-1].kind != 14 || bodyManifest.types[checkerUse(t, bodyManifest, bytesIdentity.id, 6, 0).checkedType-1].kind != 14 {
		t.Fatal("Bytes identity did not retain Bytes")
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
	if bodyManifest.types[localStringExpr.checkedType-1].kind != 2 || bodyManifest.types[checkerUse(t, bodyManifest, localString.id, 6, 0).checkedType-1].kind != 2 {
		t.Fatal("String local did not retain String")
	}
	// Decoded literals preserve the distinct expected String or Bytes type.
	for name, wantKind := range map[string]int{"greeting": 2, "raw": 14, "empty_string": 2} {
		owner := checkerSymbolByName(t, bodyManifest, bodyGood, name)
		checkedReturn := checkerReturnForOwner(t, bodyManifest, owner.id)
		expression := bodyManifest.expressions[checkedReturn.expression-1]
		result := checkerUse(t, bodyManifest, owner.id, 6, 0)
		resultKind := bodyManifest.types[expression.checkedType-1].kind
		if expression.kind != 4 || expression.parameterUse != 0 || expression.boolValue != 0 || expression.checkedType != result.checkedType || resultKind != wantKind {
			t.Fatalf("string return %s has invalid expression/result records: expression=%+v result=%+v", name, expression, result)
		}
	}
	invalidUTF8 := string([]byte{0xff})
	invalidUTF8Files := map[string]string{"invalid-utf8.al": "fn bad() -> String { return \"" + invalidUTF8 + "\" }\n"}
	invalidUTF8Manifest := parseCheckerManifest(t, runAlderChecker(t, exe, invalidUTF8Files, []string{"invalid-utf8.al"}, true), invalidUTF8Files)
	if len(invalidUTF8Manifest.diagnostics) != 1 || invalidUTF8Manifest.diagnostics[0].kind != 99 {
		t.Fatalf("invalid UTF-8 String diagnostics=%+v, want kind 99", invalidUTF8Manifest.diagnostics)
	}
	bytesUTF8Files := map[string]string{"bytes-utf8.al": "fn raw() -> Bytes { return \"" + invalidUTF8 + "\" }\n"}
	parseCheckerManifest(t, runAlderChecker(t, exe, bytesUTF8Files, []string{"bytes-utf8.al"}, false), bytesUTF8Files)
	callGood := map[string]string{
		"a.al": "import c foreign: fn(U64) -> U64\n" +
			"type Point { x: U64\n y: Bool }\n" +
			"enum Shape { Circle(value: U64)\n Dot }\n" +
			"fn forward(value: U64) -> U64 { return add(value, 1) }\n" +
			"fn add(left: U64, right: U64) -> U64 { return left + right }\n" +
			"fn recurse(value: U64) -> U64 { return recurse(value) }\n" +
			"fn even(value: U64) -> U64 { return odd(value) }\n" +
			"fn odd(value: U64) -> U64 { return even(value) }\n" +
			"fn point() -> Point { return Point(y: true, x: 3) }\n" +
			"fn point_reordered() -> Point { return Point(x: 3, y: true) }\n" +
			"fn circle() -> Shape { return Circle(5) }\n" +
			"fn dot() -> Shape { return Dot }\n" +
			"fn imported(value: U64) -> U64 { return unsafe c { foreign(value) } }\n" +
			"fn noop() -> Unit { return }\n" +
			"fn contexts(value: U64) -> U64 { let x: U64 = add(value, 1)\n var y: U64 = x\n y = add(y, 2)\n noop()\n return add(y, 3) }\n",
		"z.al": "fn cross_file(value: U64) -> U64 { return forward(value) }\n",
	}
	for i := 0; i < 20; i++ {
		callGood["z.al"] += fmt.Sprintf("fn grow%02d(value: U64) -> U64 { return add(value, %d) }\n", i, i)
	}
	callOne := runAlderChecker(t, exe, callGood, []string{"z.al", "a.al"}, false)
	callTwo := runAlderChecker(t, exe, callGood, []string{"a.al", "z.al"}, false)
	if callOne != callTwo {
		t.Fatal("concrete call manifest changed with argv order")
	}
	callManifest := parseCheckerManifest(t, callOne, callGood)
	seenCallKinds := make(map[int]bool)
	for _, annotation := range callManifest.callAnnotations {
		seenCallKinds[annotation.kind] = true
	}
	for kind := 1; kind <= 4; kind++ {
		if !seenCallKinds[kind] {
			t.Fatalf("concrete call annotation kind %d is absent", kind)
		}
	}
	pointOwner := checkerSymbolByName(t, callManifest, callGood, "point")
	pointExpr := callManifest.expressions[checkerReturnForOwner(t, callManifest, pointOwner.id).expression-1]
	if pointExpr.kind != 9 || pointExpr.childCount != 2 {
		t.Fatalf("record construction has invalid root: %+v", pointExpr)
	}
	pointFirst := callManifest.expressions[callManifest.children[pointExpr.firstChild-1].expression-1]
	pointSecond := callManifest.expressions[callManifest.children[pointExpr.firstChild].expression-1]
	if pointFirst.kind != 3 || pointSecond.kind != 2 {
		t.Fatalf("record fields were not stored in declaration order: first=%+v second=%+v", pointFirst, pointSecond)
	}
	for _, name := range []string{"recurse", "even", "odd", "cross_file"} {
		owner := checkerSymbolByName(t, callManifest, callGood, name)
		root := callManifest.expressions[checkerReturnForOwner(t, callManifest, owner.id).expression-1]
		if root.kind != 8 || root.annotation == 0 {
			t.Fatalf("recursive/forward call %s has invalid root %+v", name, root)
		}
	}

	genericCalls := map[string]string{
		"a.al": "type Pair(A: type, B: type) { first: A\n second: B }\n" +
			"enum Maybe(T: type) { Some(value: T)\n None }\n" +
			"fn identity(T: type, value: T) -> T { return value }\n" +
			"fn same(T: type, left: T, right: T) -> T { return left }\n" +
			"fn wrap(T: type, value: T) -> Maybe(T) { return Some(value) }\n" +
			"fn pass(T: type, value: Maybe(T)) -> Maybe(T) { return value }\n" +
			"fn recur(T: type, value: T) -> T { return recur(value) }\n" +
			"fn left(T: type, value: T) -> T { return right(value) }\n" +
			"fn right(T: type, value: T) -> T { return left(value) }\n" +
			"fn inferred() -> I64 { return identity(7) }\n" +
			"fn explicit() -> U64 { return identity(U64, 7) }\n" +
			"fn string_instance() -> String { return identity(\"\") }\n" +
			"fn bytes_instance() -> Bytes { return identity(\"\") }\n" +
			"fn inferred_record() -> Pair(I64, Bool) { return Pair(first: 1, second: true) }\n" +
			"fn explicit_record() -> Pair(U64, Bool) { return Pair(U64, Bool)(second: true, first: 1) }\n" +
			"fn expected_variant() -> Maybe(I64) { return Some(1) }\n" +
			"fn unary_variant() -> Maybe(I64) { return pass(Some(1)) }\n" +
			"fn shared(value: I64) -> I64 { let first = identity(value)\n return identity(first) }\n" +
			"fn same_recursion(value: I64) -> I64 { return recur(value) }\n",
		"z.al": "fn mutual_recursion(value: I64) -> I64 { return left(value) }\n",
	}
	genericFirst := runAlderChecker(t, exe, genericCalls, []string{"z.al", "a.al"}, false)
	genericSecond := runAlderChecker(t, exe, genericCalls, []string{"a.al", "z.al"}, false)
	if genericFirst != genericSecond {
		t.Fatal("generic specialization manifest changed with argv order")
	}
	genericManifest := parseCheckerManifest(t, genericFirst, genericCalls)
	if len(genericManifest.instances) < 12 {
		t.Fatalf("generic fixture exposed only %d concrete instances", len(genericManifest.instances))
	}
	identityDecl := checkerSymbolByName(t, genericManifest, genericCalls, "identity")
	identityInstances := 0
	identityKinds := make(map[int]bool)
	for _, instance := range genericManifest.instances {
		if instance.declaration == identityDecl.id {
			identityInstances++
			if instance.argCount != 1 {
				t.Fatalf("identity instance is not concretely specialized: %+v", instance)
			}
			identityKinds[genericManifest.types[genericManifest.args[instance.firstArg-1].checkedType-1].kind] = true
		}
	}
	if identityInstances != 4 || !identityKinds[1] || !identityKinds[2] || !identityKinds[14] {
		t.Fatalf("identity concrete specializations=%d/%v, want primitive, String, and Bytes instances", identityInstances, identityKinds)
	}
	for _, expression := range genericManifest.expressions {
		if !checkedManifestTypeConcrete(genericManifest, expression.checkedType) {
			t.Fatalf("generic body expression retained a nonconcrete type: %+v", expression)
		}
	}
	genericRejects := []struct {
		name, text string
		kind       int
	}{
		{name: "generic-partial.al", kind: 56, text: "fn pair(A: type, B: type, a: A, b: B) -> A { return a }\nfn f() -> I64 { return pair(I64, 1, 2) }\n"},
		{name: "generic-excess.al", kind: 56, text: "fn identity(T: type, value: T) -> T { return value }\nfn f() -> I64 { return identity(I64, U64, 1) }\n"},
		{name: "generic-unresolved.al", kind: 57, text: "fn empty(T: type) -> T {}\nfn f() -> Unit { empty()\n return }\n"},
		{name: "generic-conflict.al", kind: 58, text: "fn same(T: type, a: T, b: T) -> T { return a }\nfn f() -> I64 { return same(1, true) }\n"},
		{name: "generic-expanding.al", kind: 59, text: "enum Box(T: type) { Put(value: T) }\nfn grow(T: type, value: T) -> T { return grow(Box(T), Put(value)) }\nfn f() -> I64 { return grow(1) }\n"},
	}
	for _, tc := range genericRejects {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name: tc.text}
			first := runAlderChecker(t, exe, files, []string{tc.name}, true)
			second := runAlderChecker(t, exe, files, []string{tc.name}, true)
			if first != second {
				t.Fatal("generic diagnostic changed across processes")
			}
			manifest := parseCheckerManifest(t, first, files)
			if len(manifest.diagnostics) != 1 || manifest.diagnostics[0].kind != tc.kind {
				t.Fatalf("generic diagnostic=%+v, want kind %d", manifest.diagnostics, tc.kind)
			}
		})
	}

	callRejects := []struct {
		name, text, marker string
		kind, occurrence   int
	}{
		{name: "call-unknown.al", text: "fn f() -> U64 { return missing() }\n", marker: "missing", kind: 40},
		{name: "call-bare-function.al", text: "fn helper() -> U64 { return 1 }\nfn f() -> U64 { return helper }\n", marker: "helper", kind: 39, occurrence: 1},
		{name: "call-arity.al", text: "fn helper(value: U64) -> U64 { return value }\nfn f() -> U64 { return helper() }\n", marker: "(", kind: 41, occurrence: 2},
		{name: "call-argument.al", text: "fn helper(value: U64) -> U64 { return value }\nfn f() -> U64 { return helper(true) }\n", marker: "true", kind: 42},
		{name: "record-positional.al", text: "type P { x: U64 }\nfn f() -> P { return P(1) }\n", marker: "1", kind: 43},
		{name: "record-unknown.al", text: "type P { x: U64 }\nfn f() -> P { return P(y: 1) }\n", marker: "y", kind: 44, occurrence: 1},
		{name: "record-duplicate.al", text: "type P { x: U64 }\nfn f() -> P { return P(x: 1, x: 2) }\n", marker: "x", kind: 45, occurrence: 2},
		{name: "record-missing.al", text: "type P { x: U64\n y: U64 }\nfn f() -> P { return P(x: 1) }\n", marker: "(", kind: 46, occurrence: 1},
		{name: "variant-bare-payload.al", text: "enum E { Some(value: U64) }\nfn f() -> E { return Some }\n", marker: "Some", kind: 47, occurrence: 1},
		{name: "variant-called-empty.al", text: "enum E { None }\nfn f() -> E { return None() }\n", marker: "(", kind: 48, occurrence: 1},
		{name: "variant-arity.al", text: "enum E { Some(value: U64) }\nfn f() -> E { return Some() }\n", marker: "(", kind: 49, occurrence: 2},
		{name: "variant-payload.al", text: "enum E { Some(value: U64) }\nfn f() -> E { return Some(true) }\n", marker: "true", kind: 50},
		{name: "variant-no-context.al", text: "enum E { Some(value: U64) }\nfn f() -> U64 { return Some(1) }\n", marker: "Some", kind: 40, occurrence: 1},
		{name: "import-outside.al", text: "import c foreign: fn(U64) -> U64\nfn f() -> U64 { return foreign(1) }\n", marker: "foreign", kind: 51, occurrence: 1},
		{name: "unsafe-nonimport.al", text: "fn helper(value: U64) -> U64 { return value }\nfn f() -> U64 { return unsafe c { helper(1) } }\n", marker: "unsafe", kind: 52},
		{name: "unsafe-chained.al", text: "import c foreign: fn(U64) -> U64\nfn f() -> U64 { return unsafe c { foreign(U64)(1) } }\n", marker: "unsafe", kind: 52},
		{name: "unsafe-nested.al", text: "import c foreign: fn(U64) -> U64\nfn helper() -> U64 { return 1 }\nfn f() -> U64 { return unsafe c { foreign(helper()) } }\n", marker: "(", kind: 53, occurrence: 4},
		{name: "unsafe-arity.al", text: "import c foreign: fn(U64) -> U64\nfn f() -> U64 { return unsafe c { foreign() } }\n", marker: "(", kind: 54, occurrence: 2},
		{name: "unsafe-argument.al", text: "import c foreign: fn(U64) -> U64\nfn f() -> U64 { return unsafe c { foreign(true) } }\n", marker: "true", kind: 55},
	}
	for _, tc := range callRejects {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name: tc.text}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name}, true), files)
			at := -1
			from := 0
			for occurrence := 0; occurrence <= tc.occurrence; occurrence++ {
				next := strings.Index(tc.text[from:], tc.marker)
				if next < 0 {
					t.Fatalf("marker %q occurrence %d absent", tc.marker, tc.occurrence)
				}
				at = from + next
				from = at + len(tc.marker)
			}
			assertCheckerDiagnostic(t, manifest, tc.kind, tc.name, at, at+len(tc.marker), "", -1, -1)
			failedOwner := checkerSymbolByName(t, manifest, files, "f")
			for _, expression := range manifest.expressions {
				if expression.owner == failedOwner.id {
					t.Fatalf("concrete call failure retained expression %+v", expression)
				}
			}
			for _, annotation := range manifest.callAnnotations {
				if annotation.owner == failedOwner.id {
					t.Fatalf("concrete call failure retained annotation %+v", annotation)
				}
			}
		})
	}
	bodyUnsupported := map[string]string{"unsupported.al": "type Thing { value: U64 }\nfn partial() -> Thing { return Thing }\n"}
	unsupportedText := bodyUnsupported["unsupported.al"]
	unsupportedManifest := parseCheckerManifest(t, runAlderChecker(t, exe, bodyUnsupported, []string{"unsupported.al"}, true), bodyUnsupported)
	unsupportedAt := strings.LastIndex(unsupportedText, "Thing")
	assertCheckerDiagnostic(t, unsupportedManifest, 87, "unsupported.al", unsupportedAt, unsupportedAt+len("Thing"), "", -1, -1)
	partialOwner := checkerSymbolByName(t, unsupportedManifest, bodyUnsupported, "partial")
	assertNoCheckerBodyForOwner(t, unsupportedManifest, partialOwner.id)
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
		occurrence                        int
		last                              bool
	}{
		{name: "duplicate-kind.al", text: "type A {}\ntype A {}\n", kind: 1, marker: "type", relatedMarker: "type", last: true},
		{name: "duplicate-cross.al", text: "type A {}\nfn A() -> U64 {}\n", kind: 1, marker: "fn", relatedMarker: "type", last: true},
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
		{name: "nested-slice-element.al", text: "type A { x: [[U8]] }\n", kind: 10, marker: "["},
		{name: "substituted-slice.al", text: "type Box(T: type) { x: [T] }\ntype A { x: Box([U8]) }\n", kind: 10, marker: "Box", last: true},
		{name: "multi-substituted-slice.al", text: "type Leaf(T: type) { x: [T] }\ntype Middle(T: type) { x: Leaf(T) }\ntype A { x: Middle([U8]) }\n", kind: 10, marker: "Middle", last: true},
		{name: "caller-ancestry-slice.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box([[U8]])) }\n", kind: 10, marker: "["},
		{name: "inherited-ancestry-forward-slice.al", text: "type Inner(T: type) { value: T }\ntype Outer { value: Inner([Later]) }\ntype Later { text: [U8] }\ntype Root { value: Outer }\n", kind: 10, marker: "Outer", last: true},
		{name: "shared-specialization-slice.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: [Pair([U8])] }\n", kind: 10, marker: "["},
		{name: "recursive-slice.al", text: "type A { x: [A] }\n", kind: 10, marker: "["},
		{name: "buffer-slice.al", text: "type A { x: __s0_Buffer([U8]) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "substituted-buffer.al", text: "type Box(T: type) { x: __s0_Buffer(T) }\ntype A { x: Box([U8]) }\n", kind: 11, marker: "Box", last: true},
		{name: "caller-ancestry-buffer.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(__s0_Buffer([U8]))) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "shared-specialization-buffer.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: __s0_Buffer(Pair([U8])) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "recursive-buffer.al", text: "type A { x: __s0_Buffer(A) }\n", kind: 11, marker: "__s0_Buffer"},
		{name: "map-key-before-value.al", text: "type Pair(K: type, V: type) { x: Map(K, V) }\ntype A { x: Pair(I64, String) }\n", kind: 12, marker: "Pair", last: true},
		{name: "map-key-float.al", text: "type A { x: Map(F64, U64) }\n", kind: 12, marker: "Map"},
		{name: "map-key-generic.al", text: "type Key(T: type) { x: T }\ntype A { x: Map(Key(I64), String) }\n", kind: 12, marker: "Map"},
		{name: "caller-ancestry-map-key.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(Map(I64, U64))) }\n", kind: 12, marker: "Map"},
		{name: "shared-specialization-map-key.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: Map(Pair(I64), U64) }\n", kind: 12, marker: "Map"},
		{name: "substituted-map-value.al", text: "type Pair(K: type, V: type) { x: Map(K, V) }\ntype A { x: Pair(U64, [U8]) }\n", kind: 13, marker: "Pair", last: true},
		{name: "declared-map-value.al", text: "type Value(T: type) { x: T }\ntype A { x: Map(U64, Value([U8])) }\n", kind: 13, marker: "Map"},
		{name: "caller-ancestry-map-value.al", text: "type Box(T: type) { value: T }\ntype Root { value: Box(Box(Map(U64, [U8]))) }\n", kind: 13, marker: "Map"},
		{name: "shared-specialization-map-value.al", text: "type Leaf(T: type) { value: T }\ntype Pair(T: type) { left: Leaf(T)\n right: Leaf(T) }\ntype Root { value: Map(U64, Pair([U8])) }\n", kind: 13, marker: "Map"},
		{name: "struct-member-order.al", text: "type Fields(T: type) { first: __s0_Buffer(T)\n second: Map(T, U64) }\ntype A { x: Fields([U8]) }\n", kind: 11, marker: "Fields", last: true},
		{name: "enum-member-order.al", text: "enum E(T: type) { First(value: __s0_Buffer(T))\n Second(value: Map(T, U64)) }\ntype A { x: E([U8]) }\n", kind: 11, marker: "E", last: true},
		{name: "changed-recursive-specialization.al", text: "type A(T: type) { next: Ptr(A(Option(T))) }\ntype Root { x: A(U64) }\n", kind: 14, marker: "A", last: true},
		{name: "memoized-changed-recursive-specialization.al", text: "type C { next: Ptr(A(Option(U64))) }\ntype A(T: type) { next: Ptr(C) }\ntype D(T: type) { first: C\n second: A(T) }\ntype Root { value: D(U64) }\n", kind: 14, marker: "D", last: true},
		{name: "recursive-sibling.al", text: "type A(T: type) { next: Ptr(A(T))\n bad: Map(T, U64) }\ntype Root { x: A(I64) }\n", kind: 12, marker: "A", last: true},
		{name: "restriction-before-cycle.al", text: "type Bad { x: Map(I64, String) }\ntype Cycle { x: Cycle }\n", kind: 12, marker: "Map"},
		{name: "forward-substituted-buffer.al", text: "type Use { x: Later([U8]) }\ntype Later(T: type) { x: __s0_Buffer(T) }\n", kind: 11, marker: "Later"},
		{name: "cycle-before-forward-revalidation.al", text: "type Use { x: Later([U8]) }\ntype Later(T: type) { x: __s0_Buffer(T) }\ntype Cycle { x: Cycle }\n", kind: 9, marker: "type", last: true},
		{name: "import-restriction-before-function.al", text: "fn earlier(x: __s0_Buffer([U8])) -> U64 {}\nimport c bad: fn(Map(I64, U64)) -> U64\n", kind: 15, marker: "import"},
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
		{name: "mut-copyable-parameter.al", text: "fn f(mut value: U64) -> Unit {}\n", kind: 89, marker: "U64"},
		{name: "take-copyable-parameter.al", text: "fn f(take value: U64) -> Unit {}\n", kind: 90, marker: "U64"},
		{name: "take-scoped-parameter.al", text: "fn f(take value: [U8]) -> Unit {}\n", kind: 90, marker: "["},
		{name: "take-borrowed-owner.al", text: "type Owner { domain: Domain }\nfn sink(take value: Owner) -> Owner { return value }\nfn f(value: Owner) -> Unit { sink(value) }\n", kind: 92, marker: "value", last: true},
		{name: "mut-borrowed-owner.al", text: "type Owner { domain: Domain }\nfn sink(mut value: Owner) -> Unit {}\nfn f(value: Owner) -> Unit { sink(value) }\n", kind: 92, marker: "value", last: true},
		{name: "use-after-take.al", text: "type Owner { domain: Domain }\nfn sink(take value: Owner) -> Owner { return value }\nfn f(take value: Owner) -> Unit { let gone: Owner = sink(value)\n sink(value) }\n", kind: 91, marker: "value", last: true},
		{name: "implicit-affine-drop.al", text: "type Owner { domain: Domain }\nfn f(take value: Owner) -> Unit {}\n", kind: 93, marker: "value"},
		{name: "generic-take-copyable.al", text: "fn forward(T: type, take value: T) -> T { return value }\nfn f(value: U64) -> U64 { return forward(U64, value) }\n", kind: 90, marker: "value", last: true},
		{name: "conditional-affine-transfer.al", text: "type Owner { domain: Domain }\nfn sink(take value: Owner) -> Owner { return value }\nfn f(take value: Owner, flag: Bool) -> Unit { if flag { let gone: Owner = sink(value) } }\n", kind: 94, marker: "if", last: true},
		{name: "loop-affine-transfer.al", text: "type Owner { domain: Domain }\nfn sink(take value: Owner) -> Owner { return value }\nfn f(take value: Owner, flag: Bool) -> Unit { while flag { let gone: Owner = sink(value) } }\n", kind: 94, marker: "while"},
		{name: "copy-borrowed-owner.al", text: "type Owner { domain: Domain }\nfn f(value: Owner) -> Unit { let copied: Owner = value }\n", kind: 92, marker: "value", last: true},
		{name: "drop-affine-local.al", text: "type Owner { domain: Domain }\nfn sink(take value: Owner) -> Owner { return value }\nfn f(take value: Owner) -> Unit { let local: Owner = sink(value) }\n", kind: 93, marker: "let"},
		{name: "mutable-affine-local.al", text: "type Owner { domain: Domain }\nfn sink(take value: Owner) -> Owner { return value }\nfn f(take value: Owner) -> Unit { var local: Owner = sink(value) }\n", kind: 95, marker: "var"},
		{name: "overwrite-affine-owner.al", text: "type Owner { domain: Domain }\nfn f(take value: Owner) -> Owner { value = value\n return value }\n", kind: 95, marker: "="},
		{name: "unknown-impl-owner.al", text: "impl Missing {\nfn make() -> U64 { return 0 }\n}\n", kind: 4, marker: "Missing"},
		{name: "duplicate-inherent-method.al", text: "type Item { value: U64 }\nimpl Item {\nfn read(self) -> U64 { return self.value }\nfn read(self) -> U64 { return self.value }\n}\n", kind: 1, marker: "fn", last: true, relatedMarker: "fn"},
		{name: "take-copyable-receiver.al", text: "type Item { value: U64 }\nimpl Item {\nfn consume(take self) -> Item { return self }\n}\n", kind: 90, marker: "Item", occurrence: 2},
		{name: "immutable-mut-receiver.al", text: "type Item { value: U64 }\nimpl Item {\nfn update(mut self, value: U64) -> Unit { self.value = value }\n}\nfn f(value: Item) -> Unit { value.update(1) }\n", kind: 92, marker: "value", last: true},
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
		{name: "body-local-reserved.al", text: "fn f() -> U64 { let len: U64 = 1\n return 5 }\n", kind: 22, marker: "let"},
		{name: "body-local-mismatch.al", text: "fn f() -> U64 { let x: I64 = true\n return 5 }\n", kind: 23, marker: "let"},
		{name: "body-local-unit.al", text: "fn f(u: Unit) -> Unit { let x: Unit = u\n return }\n", kind: 25, marker: "Unit", last: true},
		{name: "body-local-mark.al", text: "fn f(m: DomainMark) -> U64 { let x: DomainMark = m\n return 5 }\n", kind: 26, marker: "DomainMark", last: true},
		{name: "body-local-duplicate.al", text: "fn f() -> U64 { let seen: U64 = 1\n let seen: U64 = 2\n return 5 }\n", kind: 27, marker: "let", last: true},
		{name: "body-assign-mismatch.al", text: "fn f() -> U64 { var y: U64 = 1\n y = true\n return y }\n", kind: 24, marker: "=", last: true},
		{name: "body-assign-immutable.al", text: "fn f() -> U64 { let imm: U64 = 1\n imm = 2\n return 5 }\n", kind: 28, marker: "imm", last: true},
		{name: "body-assign-param.al", text: "fn f(param: U64) -> U64 { param = 2\n return 5 }\n", kind: 28, marker: "param", last: true},
		{name: "body-assign-immutable-field.al", text: "type Box { value: U64 }\nfn f(box: Box) -> Unit { box.value = 2 }\n", kind: 28, marker: "box", last: true},
		{name: "body-assign-unknown.al", text: "fn f() -> U64 { ghost = 2\n return 5 }\n", kind: 18, marker: "ghost"},
		{name: "body-assign-function.al", text: "fn helper() -> U64 { return 0 }\nfn f() -> U64 { helper = 2\n return 5 }\n", kind: 18, marker: "helper", last: true},
		{name: "body-scope-leak.al", text: "fn f() -> U64 { { let hidden: U64 = 1 }\n return hidden }\n", kind: 18, marker: "hidden", last: true},
		{name: "body-sibling-leak.al", text: "fn f() -> U64 { { let hidden: U64 = 1 }\n { return hidden } }\n", kind: 18, marker: "hidden", last: true},
		{name: "body-nested-shadow.al", text: "fn f(value: U64) -> U64 { { let value: U64 = 1 }\n return value }\n", kind: 27, marker: "let"},
		{name: "body-field-root.al", text: "fn f() -> Unit { var value: U64 = 1\n value.missing = 2 }\n", kind: 60, marker: "missing"},
		{name: "body-field-unknown.al", text: "type Box { value: U64 }\nfn f() -> Unit { var box: Box = Box(value: 1)\n box.missing = 2 }\n", kind: 61, marker: "missing"},
		{name: "body-index-root.al", text: "fn f() -> Unit { var value: U64 = 1\n value[0] = 2 }\n", kind: 62, marker: "["},
		{name: "body-index-type.al", text: "fn f(values: [U64], index: I64) -> Unit { values[index] = 2 }\n", kind: 63, marker: "[", last: true},
		{name: "body-condition-type.al", text: "fn f(value: U64) -> Unit { if value {} }\n", kind: 65, marker: "if"},
		{name: "body-while-type.al", text: "fn f(value: U64) -> Unit { while value {} }\n", kind: 65, marker: "while"},
		{name: "body-for-type.al", text: "fn f(value: U64) -> Unit { for item in value {} }\n", kind: 66, marker: "for"},
		{name: "body-for-reserved.al", text: "fn f(values: [U64]) -> Unit { for len in values {} }\n", kind: 22, marker: "for"},
		{name: "body-for-duplicate.al", text: "fn f(values: [U64], item: U64) -> Unit { for item in values {} }\n", kind: 27, marker: "for"},
		{name: "body-for-leak.al", text: "fn f(values: [U64]) -> U64 { for item in values {}\n return item }\n", kind: 18, marker: "item", last: true},
		{name: "body-falloff.al", text: "fn f(flag: Bool) -> U64 { if flag { return 1 } }\n", kind: 67, marker: "{"},
		{name: "body-unreachable.al", text: "fn f() -> U64 { return 1\n missing = 2 }\n", kind: 68, marker: "="},
		{name: "body-loop-using.al", text: "fn cleanup(value: U64) -> Unit { return }\nfn f(flag: Bool) -> Unit { while flag { if flag { using value = 1 with cleanup } } }\n", kind: 69, marker: "using"},
		{name: "using-initializer-before-callback.al", text: "fn f() -> Unit { using value = missing with nope }\n", kind: 18, marker: "missing"},
		{name: "using-unknown-callback.al", text: "fn f(seed: U64) -> Unit { using value = seed with nope }\n", kind: 83, marker: "nope"},
		{name: "using-zero-arity.al", text: "fn close() -> Unit { return }\nfn f(seed: U64) -> Unit { using value = seed with close }\n", kind: 84, marker: "close", last: true},
		{name: "using-two-arity.al", text: "fn close(a: U64, b: U64) -> Unit { return }\nfn f(seed: U64) -> Unit { using value = seed with close }\n", kind: 84, marker: "close", last: true},
		{name: "using-generic.al", text: "fn close(T: type, value: T) -> Unit { return }\nfn f(seed: U64) -> Unit { using value = seed with close }\n", kind: 84, marker: "close", last: true},
		{name: "using-callback-mismatch.al", text: "fn close(value: Bool) -> Unit { return }\nfn f(seed: U64) -> Unit { using value = seed with close }\n", kind: 85, marker: "using"},
		{name: "using-non-unit.al", text: "fn close(value: U64) -> U64 { return value }\nfn f(seed: U64) -> Unit { using value = seed with close }\n", kind: 86, marker: "close", last: true},
		{name: "using-duplicate.al", text: "fn close(value: U64) -> Unit { return }\nfn f(value: U64) -> Unit { using value = value with close }\n", kind: 27, marker: "using"},
		{name: "using-function-duplicate.al", text: "fn close(value: U64) -> Unit { return }\nfn f(close: U64) -> Unit { using close = close with close }\n", kind: 27, marker: "using"},
		{name: "using-scope-leak.al", text: "fn close(value: U64) -> Unit { return }\nfn f(seed: U64) -> U64 { { using value = seed with close }\n return value }\n", kind: 18, marker: "value", last: true},
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
			if tc.occurrence > 1 {
				from := 0
				for occurrence := 0; occurrence < tc.occurrence; occurrence++ {
					start = from + strings.Index(tc.text[from:], tc.marker)
					from = start + len(tc.marker)
				}
			}
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
		"Bool", "I8", "I16", "I32", "I64", "U8", "U16", "U32", "U64", "F32", "F64", "Unit", "String", "Bytes", "Option", "Result", "Map", "Ptr", "Domain", "DomainMark", "__s0_String", "__s0_Buffer", "__s0_Error",
		"len", "range", "__s0_alloc", "__s0_domain_create", "__s0_domain_mark", "__s0_domain_reset", "__s0_domain_destroy", "__s0_map_create", "__s0_buffer_new", "__s0_buffer_len", "__s0_buffer_append", "__s0_buffer_get", "__s0_buffer_set", "__s0_buffer_slice", "Get", "Set", "Remove",
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
	assertCheckerDiagnostic(t, cross, 1, "z.al", 0, len("fn"), "a.al", 0, len("type"))
	// Duplicate checking precedes reserved-name checking in collect_symbols, but
	// no two-declaration fixture can reach it: the first reserved declaration is
	// rejected immediately. The ordering is therefore pinned by code review.
}

// Shadowing is lexical: a name bound inside a completed block, loop, or using
// statement is out of scope again in a sibling block, matching the Stage 0 Go
// frontend's cloned block environments (checkBlock rejects only names already
// in the active environment). Issue #110 replaced the owner-wide
// local_declared scan with active-environment lookup at the let/var, using,
// and for-loop binders.
func runCheckerShadowingConformance(t *testing.T, exe string) {
	t.Helper()
	accepts := []struct {
		name, text string
	}{
		{name: "sibling-let-reuse.al", text: "fn f() -> U64 {\n { let x: U64 = 1 }\n { let x: U64 = 2\n  return x }\n}\n"},
		{name: "sequential-let-reuse.al", text: "fn f() -> U64 {\n { let x: U64 = 1 }\n let x: U64 = 2\n return x }\n"},
		{name: "sibling-var-reuse.al", text: "fn f() -> U64 {\n { var x: U64 = 1 }\n { var x: U64 = 2\n  x = 3\n  return x }\n}\n"},
		{name: "sibling-for-reuse.al", text: "fn f(values: [U64]) -> U64 {\n for item in values {}\n for item in values {}\n return 0 }\n"},
		{name: "sibling-using-reuse.al", text: "fn close(value: U64) -> Unit { return }\nfn f(seed: U64) -> U64 {\n { using item = seed with close }\n { using item = seed with close\n  return item }\n}\n"},
	}
	for _, tc := range accepts {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name: tc.text}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name}, false), files)
			if len(manifest.spans) == 0 || len(manifest.diagnostics) != 0 {
				t.Fatalf("sibling reuse was not accepted with a complete manifest: spans=%d diagnostics=%+v", len(manifest.spans), manifest.diagnostics)
			}
		})
	}
	rejects := []struct {
		name, text, marker string
		last               bool
	}{
		{name: "reuse-nested-shadow.al", text: "fn f() -> U64 { let x: U64 = 1\n { let x: U64 = 2\n  return x } }\n", marker: "let", last: true},
		{name: "reuse-for-param.al", text: "fn f(values: [U64], item: U64) -> Unit { for item in values {} }\n", marker: "for"},
		{name: "reuse-body-local-duplicate.al", text: "fn f() -> U64 { let seen: U64 = 1\n let seen: U64 = 2\n return 5 }\n", marker: "let", last: true},
		{name: "reuse-body-nested-shadow.al", text: "fn f(value: U64) -> U64 { { let value: U64 = 1 }\n return value }\n", marker: "let"},
		{name: "reuse-using-duplicate.al", text: "fn close(value: U64) -> Unit { return }\nfn f(value: U64) -> Unit { using value = value with close }\n", marker: "using"},
	}
	for _, tc := range rejects {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name: tc.text}
			cm := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name}, true), files)
			if len(cm.diagnostics) != 1 {
				t.Fatalf("diagnostics=%d", len(cm.diagnostics))
			}
			start := strings.LastIndex(tc.text, tc.marker)
			if !tc.last {
				start = strings.Index(tc.text, tc.marker)
			}
			assertCheckerDiagnostic(t, cm, 27, tc.name, start, start+len(tc.marker), "", -1, -1)
		})
	}
}

// Issue #107 pins owner-scoped type annotations: a generic declaration's
// explicit syntax is replayed under every concrete instance, so the same
// syntax ID carries a different checked type per owner. Issue #79 pins the
// payload-free S0 error constructors OutOfMemory and Limit, accepted only
// under an expected __s0_Error type.
func runOwnerReplayAndErrorConstructors(t *testing.T, exe string) {
	t.Helper()
	t.Run("owner-replay", func(t *testing.T) {
		text := "type Mark { value: U64 }\n" +
			"type Pair(T: type) { value: T }\n" +
			"fn first(T: type, b: __s0_Buffer(T)) -> T { return __s0_buffer_get(T, b, 0) }\n" +
			"fn use_mark(b: __s0_Buffer(Mark)) -> Mark { return first(b) }\n" +
			"fn use_pair(b: __s0_Buffer(Pair(U64))) -> Pair(U64) { return first(b) }\n"
		files := map[string]string{"replay.al": text}
		one := runAlderChecker(t, exe, files, []string{"replay.al"}, false)
		two := runAlderChecker(t, exe, files, []string{"replay.al"}, false)
		if one != two {
			t.Fatal("owner replay manifest changed across processes")
		}
		manifest := parseCheckerManifest(t, one, files)
		if len(manifest.diagnostics) != 0 {
			t.Fatalf("owner replay was rejected: %+v", manifest.diagnostics)
		}
		firstDecl := checkerSymbolByName(t, manifest, files, "first")
		var owners []int
		for _, instance := range manifest.instances {
			if instance.declaration == firstDecl.id {
				owners = append(owners, instance.symbol)
			}
		}
		if len(owners) != 2 {
			t.Fatalf("first instances=%d, want Mark and Pair owners: %+v", len(owners), manifest.instances)
		}
		instanceOf := map[int]checkerInstance{}
		for _, instance := range manifest.instances {
			instanceOf[instance.symbol] = instance
		}
		args := make([]int, len(owners))
		for i, owner := range owners {
			instance := instanceOf[owner]
			if instance.declaration != firstDecl.id || instance.argCount != 1 {
				t.Fatalf("first instance %+v is not a single-argument specialization", instance)
			}
			args[i] = manifest.args[instance.firstArg-1].checkedType
		}
		if args[0] == args[1] {
			t.Fatalf("first instances share one type argument %v, want Mark and Pair", args)
		}
		for _, id := range args {
			if !checkedManifestTypeConcrete(manifest, id) {
				t.Fatalf("first instance type argument is not concrete: %d", id)
			}
		}
		// Concrete instance arguments and instance-owned role-7 uses pin
		// specialization without replaying the declaration's shared T syntax.
		markParam := checkerUse(t, manifest, owners[0], 7, 0)
		pairParam := checkerUse(t, manifest, owners[1], 7, 0)
		if markParam.syntax != pairParam.syntax || markParam.checkedType == pairParam.checkedType {
			t.Fatalf("Buffer(T) params did not specialize per owner: %+v %+v", markParam, pairParam)
		}
		for _, id := range []int{markParam.checkedType, pairParam.checkedType} {
			if !checkedManifestTypeConcrete(manifest, id) {
				t.Fatalf("instance Buffer param is not concrete: %d", id)
			}
		}
	})
	t.Run("s0-error-constructors", func(t *testing.T) {
		for _, tc := range []struct {
			name, ident string
			builtin     int
		}{
			{name: "err-limit.al", ident: "Limit", builtin: 6},
			{name: "err-oom.al", ident: "OutOfMemory", builtin: 5},
		} {
			text := "fn f() -> Result(U64, __s0_Error) { return Err(" + tc.ident + ") }\n"
			files := map[string]string{tc.name: text}
			one := runAlderChecker(t, exe, files, []string{tc.name}, false)
			two := runAlderChecker(t, exe, files, []string{tc.name}, false)
			if one != two {
				t.Fatalf("%s manifest changed across fresh roots", tc.name)
			}
			manifest := parseCheckerManifest(t, one, files)
			if len(manifest.diagnostics) != 0 {
				t.Fatalf("%s was rejected: %+v", tc.name, manifest.diagnostics)
			}
			var annotations []checkerCallAnnotation
			for _, annotation := range manifest.callAnnotations {
				if annotation.kind == 6 {
					annotations = append(annotations, annotation)
				}
			}
			if len(annotations) != 1 {
				t.Fatalf("%s kind-6 annotations=%d, want 1", tc.name, len(annotations))
			}
			annotation := annotations[0]
			if annotation.builtin != tc.builtin || annotation.target != 0 || annotation.variantUse != 0 || manifest.types[annotation.checkedType-1].kind != 5 {
				t.Fatalf("%s kind-6 annotation=%+v, want builtin %d target 0 on a kind-5 checked type", tc.name, annotation, tc.builtin)
			}
			matches := 0
			for _, expression := range manifest.expressions {
				if expression.kind == 10 && expression.annotation == annotation.id && expression.childCount == 0 && expression.checkedType == annotation.checkedType {
					matches++
				}
			}
			if matches != 1 {
				t.Fatalf("%s kind-10 payload-free expressions=%d, want 1", tc.name, matches)
			}
		}
	})
	t.Run("s0-error-rejects", func(t *testing.T) {
		for _, tc := range []struct {
			name, text string
		}{
			{name: "err-unknown.al", text: "fn f() -> Result(U64, __s0_Error) { return Err(Unknown) }\n"},
			{name: "err-wrong-type.al", text: "fn f() -> U64 { return Limit }\n"},
		} {
			files := map[string]string{tc.name: tc.text}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name}, true), files)
			if len(manifest.diagnostics) != 1 || manifest.diagnostics[0].kind != 18 {
				t.Fatalf("%s diagnostics=%+v, want one kind-18 unknown-name failure", tc.name, manifest.diagnostics)
			}
		}
	})
}

func runMatchTryCheckerConformance(t *testing.T, exe string) {
	t.Helper()
	t.Run("match-try-acceptance", func(t *testing.T) {
		text := "enum Choice(T: type) { Empty\n First(value: T)\n Second(value: T) }\n" +
			"fn unit() -> Unit { return }\n" +
			"fn generic(value: Choice(U64)) -> U64 { return match value { Empty => 0\n First(item) => item\n Second(item) => item } }\n" +
			"fn result(value: Result(U64, U8)) -> U64 { return match value { Ok(item) => item\n Err(error) => 0 } }\n" +
			"fn nested(value: Option(Result(U64, U8))) -> U64 { return match value { None => 0\n Some(result) => match result { Ok(item) => item\n Err(error) => 0 } } }\n" +
			"fn error(value: __s0_Error) -> U64 { return match value { OutOfMemory => 0\n Limit => 1 } }\n" +
			"fn wild(value: Option(U64)) -> U64 { return match value { _ => 1\n _ => 2 } }\n" +
			"fn statement(value: Option(U64)) -> Unit { match value { None => unit()\n Some(item) => unit() }\n return }\n" +
			"fn attempted(value: Result(U64, __s0_Error)) -> Result(U64, __s0_Error) { return Ok(try value) }\n"
		files := map[string]string{"z-match.al": text, "a-empty.al": ""}
		one := runAlderChecker(t, exe, files, []string{"z-match.al", "a-empty.al"}, false)
		two := runAlderChecker(t, exe, files, []string{"a-empty.al", "z-match.al"}, false)
		three := runAlderChecker(t, exe, files, []string{"z-match.al", "a-empty.al"}, false)
		if one != two || one != three {
			t.Fatal("match/try manifest changed with argv order or across processes")
		}
		m := parseCheckerManifest(t, one, files)
		if len(m.matches) != 7 || len(m.matchArms) != 15 || len(m.tries) != 1 {
			t.Fatalf("match/try records: M=%d W=%d X=%d, want 7/15/1", len(m.matches), len(m.matchArms), len(m.tries))
		}
		nestedOwner := checkerSymbolByName(t, m, files, "nested").id
		nestedMatches := 0
		for _, checkedMatch := range m.matches {
			if checkedMatch.owner != nestedOwner {
				continue
			}
			nestedMatches++
			owners := 0
			for _, expression := range m.expressions {
				if expression.kind == 12 && expression.parameterUse == checkedMatch.id {
					owners++
					if expression.childCount != 1 || checkedMatch.syntax != expression.syntax || checkedMatch.scrutinee != m.children[expression.firstChild-1].expression {
						t.Fatalf("nested match is not reciprocal: match=%+v expression=%+v", checkedMatch, expression)
					}
				}
			}
			if owners != 1 {
				t.Fatalf("nested match %+v has %d owning expressions", checkedMatch, owners)
			}
		}
		if nestedMatches != 2 {
			t.Fatalf("nested Option/Result match records=%d, want 2", nestedMatches)
		}
		wildcards := 0
		for _, arm := range m.matchArms {
			if arm.variantKind == 7 {
				wildcards++
			}
		}
		if wildcards != 2 {
			t.Fatalf("wildcard arms=%d, want duplicate wildcards accepted", wildcards)
		}
		malformed := []struct {
			name, record string
			field        int
			value        string
		}{
			{"M owner", "M", 2, "999"}, {"M syntax reciprocity", "M", 3, "999"}, {"M scrutinee reciprocity", "M", 4, "999"}, {"M type reference", "M", 5, "999"},
			{"W owner", "W", 2, "999"}, {"W match reference", "W", 4, "999"}, {"W variant kind", "W", 6, "8"}, {"W body ownership", "W", 9, "999"},
			{"X owner", "X", 2, "999"}, {"X expression reference", "X", 4, "999"}, {"X result type", "X", 5, "999"},
		}
		for _, fixture := range malformed {
			t.Run("malformed-"+fixture.name, func(t *testing.T) {
				changed := mutateCheckerRecord(t, one, fixture.record, fixture.field, fixture.value)
				if _, err := decodeCheckerManifest(changed, files); err == nil {
					t.Fatalf("malformed %s record accepted", fixture.record)
				}
			})
		}
	})

	t.Run("match-try-rejections", func(t *testing.T) {
		cases := []struct {
			name, text, marker string
			kind               int
		}{
			{"70-non-enum", "fn f(x: Bool) -> U64 { return match x { _ => 0 } }\n", "match", 70},
			{"71-unknown", "fn f(x: Option(U64)) -> U64 { return match x { Missing => 0\n _ => 1 } }\n", "match", 71},
			{"72-duplicate", "fn f(x: Option(U64)) -> U64 { return match x { None => 0\n None => 1\n Some(v) => v } }\n", "match", 72},
			{"73-missing-binding", "fn f(x: Option(U64)) -> U64 { return match x { None => 0\n Some => 1 } }\n", "match", 73},
			{"74-unexpected-binding", "fn f(x: Option(U64)) -> U64 { return match x { None(v) => 0\n Some(v) => v } }\n", "match", 74},
			{"75-reserved-binding", "fn f(x: Option(U64)) -> U64 { return match x { None => 0\n Some(len) => len } }\n", "match", 75},
			{"76-duplicate-binding", "fn f(x: Option(U64), value: U64) -> U64 { return match x { None => 0\n Some(value) => value } }\n", "match", 76},
			{"77-arm-mismatch", "fn f(x: Option(U64)) -> U64 { return match x { None => 0\n Some(v) => true } }\n", "true", 77},
			{"78-empty", "fn f(x: Option(U64)) -> U64 { return match x {} }\n", "match", 78},
			{"79-nonexhaustive", "fn f(x: Option(U64)) -> U64 { return match x { None => 0 } }\n", "match", 79},
			{"80-try-outside-result", "fn f(x: Result(U64, __s0_Error)) -> U64 { return try x }\n", "try", 80},
			{"81-try-non-result", "fn f(x: Bool) -> Result(U64, __s0_Error) { return Ok(try x) }\n", "try", 81},
			{"82-try-error-mismatch", "fn f(x: Result(U64, U8)) -> Result(U64, __s0_Error) { return Ok(try x) }\n", "try", 82},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				files := map[string]string{tc.name + ".al": tc.text}
				out := runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true)
				m := parseCheckerManifest(t, out, files)
				at := strings.LastIndex(tc.text, tc.marker)
				if tc.kind != 77 {
					at = strings.Index(tc.text, tc.marker)
				}
				assertCheckerDiagnostic(t, m, tc.kind, tc.name+".al", at, at+len(tc.marker), "", -1, -1)
				owner := checkerSymbolByName(t, m, files, "f").id
				assertNoCheckerBodyForOwner(t, m, owner)
			})
		}
	})
}

func mutateCheckerRecord(t *testing.T, manifest, record string, field int, value string) string {
	t.Helper()
	lines := strings.Split(manifest, "\n")
	for i, line := range lines {
		fields := strings.Fields(line)
		if len(fields) > field && fields[0] == record {
			fields[field] = value
			lines[i] = strings.Join(fields, " ")
			return strings.Join(lines, "\n")
		}
	}
	t.Fatalf("valid fixture has no mutable %s record field %d", record, field)
	return ""
}

func assertNoCheckerBodyForOwner(t *testing.T, m checkerManifest, owner int) {
	t.Helper()
	for _, recordOwner := range [][]int{
		checkerOwnersExpressions(m.expressions), checkerOwnersLocals(m.locals), checkerOwnersEnvironments(m.environments), checkerOwnersMatches(m.matches), checkerOwnersMatchArms(m.matchArms), checkerOwnersTries(m.tries), checkerOwnersReturns(m.returns), checkerOwnersPlaces(m.places), checkerOwnersStatements(m.statements), checkerOwnersBlocks(m.blocks),
	} {
		for _, got := range recordOwner {
			if got == owner {
				t.Fatalf("failed owner %d retained body records (M/W/X or ordinary body graph)", owner)
			}
		}
	}
}

func checkerOwnersExpressions(v []checkerExpression) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersLocals(v []checkerLocal) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersEnvironments(v []checkerEnvironment) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersMatches(v []checkerMatch) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersMatchArms(v []checkerMatchArm) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersTries(v []checkerTry) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersReturns(v []checkerReturn) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersPlaces(v []checkerPlace) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersStatements(v []checkerStatement) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}
func checkerOwnersBlocks(v []checkerBlock) []int {
	r := make([]int, len(v))
	for i := range v {
		r[i] = v[i].owner
	}
	return r
}

// privateProfileSources reports whether a checker-conformance source set
// still uses the S0 bootstrap bridges and needs the private bootstrap
// profile. The ordinary-mode gate itself is pinned by the production-driver
// and frontend reject fixtures, not by these conformance runs.
func privateProfileSources(files map[string]string) bool {
	for _, text := range files {
		if strings.Contains(text, "__s0_") || strings.Contains(text, "Domain") || strings.Contains(text, "Map(") ||
			strings.Contains(text, "Get(") || strings.Contains(text, "Set(") || strings.Contains(text, "Remove(") {
			return true
		}
	}
	return false
}

func runAlderChecker(t *testing.T, exe string, files map[string]string, order []string, fail bool) string {
	t.Helper()
	d := t.TempDir()
	const sentinel = "!alder-core-checker"
	if err := os.WriteFile(filepath.Join(d, sentinel), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for n, s := range files {
		if e := os.WriteFile(filepath.Join(d, n), []byte(s), 0644); e != nil {
			t.Fatal(e)
		}
	}
	args := append([]string{sentinel}, order...)
	if privateProfileSources(files) {
		args = append([]string{"--bootstrap-private"}, args...)
	}
	cmd := conformanceCommand(exe, args...)
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
		t.Fatalf("run: %v %s\n%s", e, stderr.String(), out.String())
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
	if len(lines) < 2 || lines[0] != "ALDER-CHECKER-MANIFEST 14" || lines[len(lines)-1] != "END" {
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
		recordPhase := map[string]int{"S": 0, "Z": 1, "Y": 2, "P": 3, "C": 4, "A": 5, "T": 6, "U": 7, "I": 8, "L": 9, "N": 10, "Q": 11, "E": 12, "H": 13, "R": 14, "M": 15, "W": 16, "X": 17, "G": 18, "V": 19, "J": 20, "K": 21, "B": 22, "D": 23}[fields[0]]
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
		case "Z":
			if err != nil || len(numbers) != 6 {
				return m, fmt.Errorf("line %d has invalid Z record", lineNumber+2)
			}
			m.spans = append(m.spans, checkerSpan{id: numbers[0], source: numbers[1], start: numbers[2], end: numbers[3], nameStart: numbers[4], nameEnd: numbers[5]})
		case "Y":
			if err != nil || len(numbers) != 11 {
				return m, fmt.Errorf("line %d has invalid Y record", lineNumber+2)
			}
			m.symbols = append(m.symbols, checkerSymbol{id: numbers[0], kind: numbers[1], node: numbers[2], source: numbers[3], start: numbers[4], end: numbers[5], arity: numbers[6], declaration: numbers[7], firstInstanceArg: numbers[8], instanceArgCount: numbers[9], discoveryParent: numbers[10]})
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
		case "I":
			if err != nil || len(numbers) != 6 {
				return m, fmt.Errorf("line %d has invalid I record", lineNumber+2)
			}
			m.instances = append(m.instances, checkerInstance{id: numbers[0], symbol: numbers[1], declaration: numbers[2], firstArg: numbers[3], argCount: numbers[4], discoveryParent: numbers[5]})
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
		case "Q":
			if err != nil || len(numbers) != 7 {
				return m, fmt.Errorf("line %d has invalid Q record", lineNumber+2)
			}
			m.callAnnotations = append(m.callAnnotations, checkerCallAnnotation{id: numbers[0], owner: numbers[1], kind: numbers[2], target: numbers[3], checkedType: numbers[4], variantUse: numbers[5], builtin: numbers[6]})
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
		case "M":
			if err != nil || len(numbers) != 8 {
				return m, fmt.Errorf("line %d has invalid M record", lineNumber+2)
			}
			m.matches = append(m.matches, checkerMatch{id: numbers[0], owner: numbers[1], syntax: numbers[2], scrutinee: numbers[3], scrutineeType: numbers[4], checkedType: numbers[5], firstArm: numbers[6], armCount: numbers[7]})
		case "W":
			if err != nil || len(numbers) != 9 {
				return m, fmt.Errorf("line %d has invalid W record", lineNumber+2)
			}
			m.matchArms = append(m.matchArms, checkerMatchArm{id: numbers[0], owner: numbers[1], syntax: numbers[2], checkedMatch: numbers[3], variantUse: numbers[4], variantKind: numbers[5], binding: numbers[6], environment: numbers[7], body: numbers[8]})
		case "X":
			if err != nil || len(numbers) != 7 {
				return m, fmt.Errorf("line %d has invalid X record", lineNumber+2)
			}
			m.tries = append(m.tries, checkerTry{id: numbers[0], owner: numbers[1], syntax: numbers[2], expression: numbers[3], resultType: numbers[4], okType: numbers[5], errorType: numbers[6]})
		case "G":
			if err != nil || len(numbers) != 10 {
				return m, fmt.Errorf("line %d has invalid G record", lineNumber+2)
			}
			m.cleanups = append(m.cleanups, checkerCleanup{id: numbers[0], owner: numbers[1], syntax: numbers[2], environment: numbers[3], binding: numbers[4], initializer: numbers[5], callback: numbers[6], normalExit: numbers[7], returnExit: numbers[8], tryExit: numbers[9]})
		case "V":
			if err != nil || len(numbers) != 8 {
				return m, fmt.Errorf("line %d has invalid V record", lineNumber+2)
			}
			m.places = append(m.places, checkerPlace{id: numbers[0], owner: numbers[1], syntax: numbers[2], kind: numbers[3], root: numbers[4], field: numbers[5], index: numbers[6], checkedType: numbers[7]})
		case "J":
			if err != nil || len(numbers) != 10 {
				return m, fmt.Errorf("line %d has invalid J record", lineNumber+2)
			}
			m.statements = append(m.statements, checkerStatement{id: numbers[0], owner: numbers[1], syntax: numbers[2], kind: numbers[3], environment: numbers[4], expression: numbers[5], place: numbers[6], binding: numbers[7], body: numbers[8], alternative: numbers[9]})
		case "K":
			if err != nil || len(numbers) != 3 {
				return m, fmt.Errorf("line %d has invalid K record", lineNumber+2)
			}
			m.statementLinks = append(m.statementLinks, checkerStatementLink{id: numbers[0], statement: numbers[1], next: numbers[2]})
		case "B":
			if err != nil || len(numbers) != 6 {
				return m, fmt.Errorf("line %d has invalid B record", lineNumber+2)
			}
			m.blocks = append(m.blocks, checkerBlock{id: numbers[0], owner: numbers[1], syntax: numbers[2], environment: numbers[3], statements: numbers[4], guaranteedReturn: numbers[5]})
		case "D":
			if err != nil || len(numbers) != 6 && len(numbers) != 9 || numbers[4] > 1 || numbers[4] == 0 && len(numbers) != 6 || numbers[4] == 1 && len(numbers) != 9 {
				return m, fmt.Errorf("line %d has invalid D record", lineNumber+2)
			}
			diagnostic := checkerDiagnostic{kind: numbers[0], source: numbers[1], start: numbers[2], end: numbers[3], hasRelated: numbers[4] == 1}
			if diagnostic.hasRelated {
				diagnostic.relatedSource, diagnostic.relatedStart, diagnostic.relatedEnd = numbers[5], numbers[6], numbers[7]
				diagnostic.note = numbers[8]
			} else {
				diagnostic.note = numbers[5]
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
	for i, span := range m.spans {
		validName := span.nameStart == 0 && span.nameEnd == 0 || validSourceRange(span.source, span.nameStart, span.nameEnd, true)
		if span.id != i+1 || !validSourceRange(span.source, span.start, span.end, true) || !validName || span.nameStart != 0 && (span.nameStart < span.start || span.nameEnd > span.end) {
			return fmt.Errorf("invalid checked source span %+v", span)
		}
	}
	bodyPhase := len(m.expressions) != 0 || len(m.returns) != 0 || len(m.locals) != 0 || len(m.blocks) != 0 || len(m.matches) != 0 || len(m.tries) != 0
	for _, diagnostic := range m.diagnostics {
		if diagnostic.kind >= 18 && diagnostic.kind <= 69 || diagnostic.kind >= 97 && diagnostic.kind <= 104 {
			bodyPhase = true
		}
	}
	nodes := make(map[int]bool)
	// Traits carry one implicit trailing `Self` parameter whose node is the
	// trait declaration itself rather than a dedicated parameter node.
	traitSelfNodes := make(map[int]bool)
	for i, symbol := range m.symbols {
		instance := symbol.declaration != 0
		validInstance := symbol.kind == 12 && symbol.arity == 0 && symbol.declaration == symbol.id && symbol.instanceArgCount == 0 || symbol.kind == 13 && symbol.arity == 0 && symbol.declaration >= 1 && symbol.declaration < symbol.id && m.symbols[symbol.declaration-1].kind == 12 && m.symbols[symbol.declaration-1].arity == symbol.instanceArgCount
		if symbol.id != i+1 || (symbol.kind != 1 && symbol.kind != 2 && symbol.kind != 3 && symbol.kind != 12 && symbol.kind != 13 && symbol.kind != 50) || symbol.node < 1 || symbol.kind != 13 && nodes[symbol.node] || symbol.arity < 0 || !validSourceRange(symbol.source, symbol.start, symbol.end, true) || instance != validInstance || !instance && (symbol.firstInstanceArg != 0 || symbol.instanceArgCount != 0 || symbol.discoveryParent != 0) {
			return fmt.Errorf("invalid symbol %+v", symbol)
		}
		if symbol.kind != 13 {
			nodes[symbol.node] = true
		}
		if symbol.kind == 50 {
			traitSelfNodes[symbol.id] = true
		}
	}
	for i, param := range m.params {
		ownerSelf := traitSelfNodes[param.owner] && param.node == m.symbols[param.owner-1].node
		if param.id != i+1 || param.owner < 1 || param.owner > len(m.symbols) || param.node < 1 || nodes[param.node] && !ownerSelf || !validSourceRange(param.source, param.start, param.end, true) {
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
	for i, instance := range m.instances {
		if instance.id != i+1 || instance.symbol < 1 || instance.symbol > len(m.symbols) {
			return fmt.Errorf("invalid function instance %+v", instance)
		}
		symbol := m.symbols[instance.symbol-1]
		if symbol.declaration == 0 || instance.declaration != symbol.declaration || instance.firstArg != symbol.firstInstanceArg || instance.argCount != symbol.instanceArgCount || instance.discoveryParent != symbol.discoveryParent || (instance.argCount == 0) != (instance.firstArg == 0) || instance.argCount > 0 && (instance.firstArg < 1 || instance.firstArg-1+instance.argCount > len(m.args)) || instance.discoveryParent != 0 && (instance.discoveryParent >= instance.symbol || m.symbols[instance.discoveryParent-1].declaration == 0) {
			return fmt.Errorf("invalid function instance %+v", instance)
		}
		for at := 0; at < instance.argCount; at++ {
			argOwners[instance.firstArg-1+at]++
		}
	}
	instanceCount := 0
	for _, symbol := range m.symbols {
		if symbol.declaration != 0 {
			instanceCount++
		}
	}
	if len(m.instances) != instanceCount {
		return fmt.Errorf("manifest has %d instance records for %d concrete symbols", len(m.instances), instanceCount)
	}
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
		if checked.id != i+1 || checked.kind < 1 || checked.kind > 18 && checked.kind != 23 && checked.kind != 24 || checked.syntax != 0 || canonicalTypes[key.String()] || (checked.count == 0) != (checked.first == 0) || checked.first < 0 || checked.count < 0 || checked.count > 0 && (checked.first < 1 || checked.first-1 > len(m.args) || checked.count > len(m.args)-(checked.first-1)) {
			return fmt.Errorf("invalid checked type %+v", checked)
		}
		canonicalTypes[key.String()] = true
		if checked.kind == 1 && (checked.target < 1 || checked.target > 12) {
			return fmt.Errorf("checked type %+v has an invalid primitive target", checked)
		}
		if checked.target != 0 && checked.kind != 1 && checked.kind != 6 && checked.kind != 7 && checked.kind != 15 {
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
		case 8, 9, 12, 13, 15, 17, 18, 24:
			wantCount = 1
		case 10, 11, 23:
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
		if annotation.id != i+1 || annotation.owner < 1 || annotation.owner > len(m.symbols) || annotation.syntax < 1 || annotation.checkedType < 1 || annotation.checkedType > len(m.types) || annotations[key] != 0 {
			return fmt.Errorf("invalid type annotation %+v", annotation)
		}
		annotations[key] = annotation.checkedType
		if m.symbols[annotation.owner-1].kind != 13 {
			typeSyntax[annotation.syntax] = true
		}
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
			if symbol.kind == 50 && (paramCounts[i] == symbol.arity || paramCounts[i] == symbol.arity+1) {
				// Traits add one implicit trailing `Self` parameter.
				continue
			}
			if symbol.kind != 13 && paramCounts[i] != symbol.arity || symbol.kind == 13 && paramCounts[i] != 0 {
				return fmt.Errorf("symbol %+v has %d type parameter records", symbol, paramCounts[i])
			}
		}
	}
	ordinals := make(map[[2]int]int)
	for i, use := range m.uses {
		key := [2]int{use.owner, use.role}
		valueless := use.role == 2 && use.syntax == 0 && use.checkedType == 0
		named := use.role == 1 || use.role == 2 || use.role == 5 || use.role == 7
		ownerKind := 0
		if use.owner >= 1 && use.owner <= len(m.symbols) {
			ownerKind = m.symbols[use.owner-1].kind
		}
		roleMatchesOwner := use.role == 1 && ownerKind == 2 || use.role == 2 && ownerKind == 3 || (use.role == 3 || use.role == 4) && ownerKind == 1 || (use.role == 5 || use.role == 6) && ownerKind == 12 || (use.role == 7 || use.role == 8) && ownerKind == 13
		instanceUse := use.role == 7 || use.role == 8
		if use.id != i+1 || use.owner < 1 || use.owner > len(m.symbols) || use.role < 1 || use.role > 8 || !roleMatchesOwner || use.ordinal != ordinals[key] || use.node < 1 || nodes[use.node] && !instanceUse || !validSourceRange(use.source, use.nameStart, use.nameEnd, named) || named != (use.nameStart != 0 || use.nameEnd != 0) || !valueless && (use.syntax < 1 || use.checkedType < 1 || use.checkedType > len(m.types) || !instanceUse && annotations[[2]int{use.owner, use.syntax}] != use.checkedType) || valueless && (use.nameStart == 0 || use.nameEnd == 0) {
			return fmt.Errorf("invalid declaration type use %+v", use)
		}
		if !instanceUse {
			nodes[use.node] = true
		}
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
			if symbol.kind == 13 {
				role = 8
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
	bodySyntax := make(map[[2]int]bool)
	bindingEnvironments := make([]int, len(m.locals))
	lastEnvironment := make(map[int]int)
	lastEnvironmentOwner := 0
	for i, environment := range m.environments {
		validBinding := environment.binding == 0 || environment.binding <= len(m.locals) && m.locals[environment.binding-1].owner == environment.owner
		if environment.id != i+1 || environment.owner < 1 || environment.owner > len(m.symbols) || environment.owner < lastEnvironmentOwner || !validBinding || environment.parent < 0 || environment.parent >= environment.id || environment.parent != 0 && m.environments[environment.parent-1].owner != environment.owner {
			return fmt.Errorf("invalid environment %+v", environment)
		}
		if environment.binding != 0 {
			bindingEnvironments[environment.binding-1]++
		}
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
		validOwner := ownerKind == 12 && ownerArity == 0 || ownerKind == 13
		if local.id != i+1 || !validOwner || local.kind < 1 || local.kind > 2 || local.syntax < 1 || nodes[local.syntax] && !sharedParameterSyntax || bodySyntax[[2]int{local.owner, local.syntax}] || local.checkedType < 1 || local.checkedType > len(m.types) || local.kind == 1 && ownerArity < 0 || local.mutable < 0 || local.mutable > 2 || local.kind == 2 && local.mutable > 1 || !validSourceRange(local.source, local.nameStart, local.nameEnd, true) || bindingEnvironments[i] != 1 {
			return fmt.Errorf("invalid local binding %+v", local)
		}
		if local.kind == 2 {
			bodySyntax[[2]int{local.owner, local.syntax}] = true
		}
	}
	placeOwners := make([]int, len(m.places))
	controlExpressionOwners := make([]int, len(m.expressions))
	for i, place := range m.places {
		if place.id != i+1 || !checkerConcreteOwner(m, place.owner) || place.syntax < 1 || place.kind < 1 || place.kind > 4 || place.root < 1 || place.root > len(m.locals) || m.locals[place.root-1].owner != place.owner || place.checkedType < 1 || place.checkedType > len(m.types) {
			return fmt.Errorf("invalid checked place identity %+v", place)
		}
		rootType := m.locals[place.root-1].checkedType
		valueType := rootType
		if place.kind >= 3 {
			if rootType < 1 || rootType > len(m.types) || (m.types[rootType-1].kind != 8 && m.types[rootType-1].kind != 15 && m.types[rootType-1].kind != 17 && m.types[rootType-1].kind != 18) || m.types[rootType-1].count != 1 {
				return fmt.Errorf("checked place has nonslice indexed root %+v", place)
			}
			valueType = checkerDirectArgs(m, m.types[rootType-1])[0].checkedType
			if place.index < 1 || place.index > len(m.expressions) {
				return fmt.Errorf("checked place has invalid index %+v", place)
			}
			index := m.expressions[place.index-1]
			if index.owner != place.owner || index.siteKind != 7 || index.checkedType < 1 || index.checkedType > len(m.types) || m.types[index.checkedType-1].kind != 1 || m.types[index.checkedType-1].target != 9 {
				return fmt.Errorf("checked place index is not owned U64 %+v", place)
			}
			controlExpressionOwners[place.index-1]++
		} else if place.index != 0 {
			return fmt.Errorf("nonindexed checked place has index %+v", place)
		}
		if place.kind == 2 || place.kind == 4 {
			valueType = checkerConcreteFieldType(m, valueType, place.field)
			if valueType == 0 {
				return fmt.Errorf("checked place field does not belong to concrete aggregate %+v", place)
			}
		} else if place.field != 0 {
			return fmt.Errorf("fieldless checked place has field %+v", place)
		}
		if place.checkedType != valueType {
			return fmt.Errorf("checked place type disagrees with concrete target %+v", place)
		}
	}
	statementOwners := make([]int, len(m.statements))
	cleanupOwners := make([]int, len(m.cleanups))
	childBlockOwners := make([]int, len(m.blocks))
	returnStatementOwners := make([]int, len(m.returns))
	statementSyntax := make(map[[2]int]bool)
	for i, statement := range m.statements {
		validEnvironment := statement.environment == 0 || statement.environment <= len(m.environments) && m.environments[statement.environment-1].owner == statement.owner
		if statement.id != i+1 || !checkerConcreteOwner(m, statement.owner) || statement.syntax < 1 || statement.kind < 1 || statement.kind > 10 || !validEnvironment || statementSyntax[[2]int{statement.owner, statement.syntax}] {
			return fmt.Errorf("invalid checked statement identity %+v", statement)
		}
		statementSyntax[[2]int{statement.owner, statement.syntax}] = true
		expressionSite, requireExpression := 0, false
		requirePlace, requireBinding, requireBody := false, false, false
		allowAlternative := false
		switch statement.kind {
		case 1, 2:
			expressionSite, requireExpression, requireBinding = 1, true, true
		case 3:
			expressionSite, requireExpression, requirePlace = 2, true, true
		case 4:
			expressionSite = 3
		case 5:
			expressionSite, requireExpression = 4, true
		case 6:
			requireBody = true
		case 7:
			expressionSite, requireExpression, requireBody, allowAlternative = 5, true, true, true
		case 8:
			expressionSite, requireExpression, requireBody = 5, true, true
		case 9:
			expressionSite, requireExpression, requireBinding, requireBody = 6, true, true, true
		case 10:
			expressionSite, requireExpression, requireBinding = 8, true, true
		}
		validExpression := !requireExpression && statement.expression == 0
		if statement.expression >= 1 && statement.expression <= len(m.expressions) {
			expression := m.expressions[statement.expression-1]
			validExpression = expression.owner == statement.owner && expression.siteKind == expressionSite && expression.siteSyntax == statement.syntax
			controlExpressionOwners[statement.expression-1]++
		}
		validPlace := !requirePlace && statement.place == 0
		if statement.place >= 1 && statement.place <= len(m.places) {
			place := m.places[statement.place-1]
			validPlace = requirePlace && place.owner == statement.owner && place.syntax < statement.syntax
			placeOwners[statement.place-1]++
			if place.index != 0 && (m.expressions[place.index-1].siteSyntax != statement.syntax || statement.expression != 0 && place.index >= statement.expression) {
				return fmt.Errorf("checked place components do not precede assignment value %+v", statement)
			}
		}
		validBinding := !requireBinding && statement.binding == 0
		if statement.binding >= 1 && statement.binding <= len(m.locals) {
			binding := m.locals[statement.binding-1]
			validBinding = requireBinding && binding.owner == statement.owner && binding.syntax == statement.syntax && binding.kind == 2 && (statement.kind != 1 || binding.mutable == 0) && (statement.kind != 2 || binding.mutable == 1) && (statement.kind != 9 || binding.mutable == 0)
		}
		validBody := !requireBody && statement.body == 0
		if statement.kind == 10 && statement.body >= 1 && statement.body <= len(m.cleanups) {
			cleanup := m.cleanups[statement.body-1]
			validBody = cleanup.owner == statement.owner && cleanup.syntax == statement.syntax && cleanup.binding == statement.binding && cleanup.initializer == statement.expression
			cleanupOwners[statement.body-1]++
		}
		if statement.kind != 10 && statement.body >= 1 && statement.body <= len(m.blocks) {
			body := m.blocks[statement.body-1]
			validBody = requireBody && body.owner == statement.owner && body.id < len(m.blocks)+1
			childBlockOwners[statement.body-1]++
			if statement.kind == 6 && body.syntax != statement.syntax {
				validBody = false
			}
		}
		validAlternative := statement.alternative == 0
		if statement.alternative >= 1 && statement.alternative <= len(m.blocks) {
			alternative := m.blocks[statement.alternative-1]
			validAlternative = allowAlternative && alternative.owner == statement.owner
			childBlockOwners[statement.alternative-1]++
		}
		validReturn := statement.kind != 4
		if statement.kind == 4 {
			for i, checkedReturn := range m.returns {
				if checkedReturn.owner == statement.owner && checkedReturn.syntax == statement.syntax && checkedReturn.expression == statement.expression {
					validReturn = true
					returnStatementOwners[i]++
				}
			}
		}
		if !validExpression || !validPlace || !validBinding || !validBody || !validAlternative || !validReturn {
			return fmt.Errorf("invalid checked statement payload %+v", statement)
		}
	}
	for i, cleanup := range m.cleanups {
		validEnvironment := cleanup.environment == 0 || cleanup.environment <= len(m.environments) && m.environments[cleanup.environment-1].owner == cleanup.owner
		validBinding := cleanup.binding >= 1 && cleanup.binding <= len(m.locals) && m.locals[cleanup.binding-1].owner == cleanup.owner && m.locals[cleanup.binding-1].syntax == cleanup.syntax
		validInitializer := false
		if validBinding && cleanup.initializer >= 1 && cleanup.initializer <= len(m.expressions) {
			validInitializer = m.expressions[cleanup.initializer-1].owner == cleanup.owner && m.expressions[cleanup.initializer-1].checkedType == m.locals[cleanup.binding-1].checkedType
		}
		validCallback := cleanup.callback >= 1 && cleanup.callback <= len(m.symbols) && m.symbols[cleanup.callback-1].kind == 12 && m.symbols[cleanup.callback-1].arity == 0
		if cleanup.id != i+1 || !checkerConcreteOwner(m, cleanup.owner) || !validEnvironment || !validBinding || !validInitializer || !validCallback || cleanup.normalExit != 1 || cleanup.returnExit != 1 || cleanup.tryExit != 1 || cleanupOwners[i] != 1 {
			return fmt.Errorf("invalid checked cleanup %+v", cleanup)
		}
	}
	linkOwners := make([]int, len(m.statementLinks))
	rootBlocks := make(map[int]int)
	for i, block := range m.blocks {
		validEnvironment := block.environment == 0 || block.environment <= len(m.environments) && m.environments[block.environment-1].owner == block.owner
		if block.id != i+1 || !checkerConcreteOwner(m, block.owner) || block.syntax < 1 || !validEnvironment || block.statements < 0 || block.statements > len(m.statementLinks) || block.guaranteedReturn < 0 || block.guaranteedReturn > 1 {
			return fmt.Errorf("invalid checked block %+v", block)
		}
		link := block.statements
		for link != 0 {
			if linkOwners[link-1] != 0 {
				return fmt.Errorf("checked statement link %d has overlapping block owners", link)
			}
			item := m.statementLinks[link-1]
			if item.id != link || item.statement < 1 || item.statement > len(m.statements) || m.statements[item.statement-1].owner != block.owner || item.next < 0 || item.next >= item.id {
				return fmt.Errorf("invalid checked statement link %+v", item)
			}
			linkOwners[link-1]++
			statementOwners[item.statement-1]++
			statement := m.statements[item.statement-1]
			if statement.body != 0 && statement.body >= block.id || statement.alternative != 0 && statement.alternative >= block.id {
				return fmt.Errorf("checked statement child block is not acyclic %+v", statement)
			}
			if item.next != 0 && m.statements[m.statementLinks[item.next-1].statement-1].syntax >= m.statements[item.statement-1].syntax {
				return fmt.Errorf("checked statement link is not in source order %+v", item)
			}
			link = item.next
		}
		if childBlockOwners[i] == 0 {
			rootBlocks[block.owner]++
		} else if childBlockOwners[i] != 1 {
			return fmt.Errorf("checked block %d has %d parents", i+1, childBlockOwners[i])
		}
	}
	for i, owners := range linkOwners {
		if owners != 1 {
			return fmt.Errorf("checked statement link %d has %d block owners", i+1, owners)
		}
	}
	for i, owners := range statementOwners {
		if owners != 1 {
			return fmt.Errorf("checked statement %d has %d link owners", i+1, owners)
		}
	}
	for i, owners := range placeOwners {
		if owners != 1 {
			return fmt.Errorf("checked place %d has %d statement owners", i+1, owners)
		}
	}
	for i, owners := range returnStatementOwners {
		if owners != 1 {
			return fmt.Errorf("checked return %d has %d statement owners", i+1, owners)
		}
	}
	for i, expression := range m.expressions {
		if expression.siteKind != 0 && expression.siteKind <= 7 && controlExpressionOwners[i] != 1 {
			return fmt.Errorf("checked expression %d has %d control owners", i+1, controlExpressionOwners[i])
		}
	}
	for owner, roots := range rootBlocks {
		if roots != 1 {
			return fmt.Errorf("concrete owner %d has %d root blocks", owner, roots)
		}
	}
	if len(m.diagnostics) == 0 {
		for _, symbol := range m.symbols {
			if checkerConcreteOwner(m, symbol.id) && rootBlocks[symbol.id] != 1 {
				return fmt.Errorf("complete concrete owner %d has %d root blocks", symbol.id, rootBlocks[symbol.id])
			}
		}
	}
	blockGuarantee := make([]int, len(m.blocks))
	for i, block := range m.blocks {
		guaranteed := 0
		if block.statements != 0 {
			statement := m.statements[m.statementLinks[block.statements-1].statement-1]
			switch statement.kind {
			case 4:
				guaranteed = 1
			case 6:
				guaranteed = blockGuarantee[statement.body-1]
			case 7:
				if statement.alternative != 0 && blockGuarantee[statement.body-1] == 1 && blockGuarantee[statement.alternative-1] == 1 {
					guaranteed = 1
				}
			}
		}
		blockGuarantee[i] = guaranteed
		if block.guaranteedReturn != guaranteed {
			return fmt.Errorf("checked block has invalid return guarantee %+v", block)
		}
	}
	callAnnotationOwners := make([]int, len(m.callAnnotations))
	for i, annotation := range m.callAnnotations {
		ownerKind, ownerArity, targetKind, targetArity := 0, -1, 0, -1
		if annotation.owner >= 1 && annotation.owner <= len(m.symbols) {
			ownerKind, ownerArity = m.symbols[annotation.owner-1].kind, m.symbols[annotation.owner-1].arity
		}
		if annotation.target >= 1 && annotation.target <= len(m.symbols) {
			targetKind, targetArity = m.symbols[annotation.target-1].kind, m.symbols[annotation.target-1].arity
		}
		validTarget := annotation.kind == 1 && (targetKind == 12 && targetArity == 0 || targetKind == 13) || annotation.kind == 2 && targetKind == 1 || annotation.kind == 3 && targetKind == 2 || annotation.kind == 4 && targetKind == 3 || annotation.kind == 5 && annotation.target == 0 && (annotation.builtin >= 1 && annotation.builtin <= 25 || annotation.builtin >= 30 && annotation.builtin <= 42) || annotation.kind == 6 && annotation.target == 0 && (annotation.builtin == 5 || annotation.builtin == 6)
		validType := annotation.checkedType >= 1 && annotation.checkedType <= len(m.types)
		validVariant := annotation.kind != 4 && annotation.variantUse == 0
		if annotation.kind == 4 && annotation.variantUse >= 1 && annotation.variantUse <= len(m.uses) {
			variant := m.uses[annotation.variantUse-1]
			validVariant = variant.owner == annotation.target && variant.role == 2
		}
		if validType && (annotation.kind == 3 || annotation.kind == 4) {
			checked := m.types[annotation.checkedType-1]
			validType = checked.kind == 7 && checked.target == annotation.target
		}
		if validType && annotation.kind == 6 {
			validType = m.types[annotation.checkedType-1].kind == 5
		}
		if validType && (annotation.kind == 1 || annotation.kind == 2) {
			resultRole, resultType := 6, 0
			if annotation.kind == 2 {
				resultRole = 4
			}
			if annotation.kind == 1 && targetKind == 13 {
				resultRole = 8
			}
			for _, use := range m.uses {
				if use.owner == annotation.target && use.role == resultRole && use.ordinal == 0 {
					resultType = use.checkedType
				}
			}
			validType = resultType == annotation.checkedType
		}
		validOwner := ownerKind == 12 && ownerArity == 0 || ownerKind == 13
		validBuiltin := annotation.kind == 5 && annotation.builtin != 0 || annotation.kind == 6 && (annotation.builtin == 5 || annotation.builtin == 6) || annotation.kind != 5 && annotation.kind != 6 && annotation.builtin == 0
		if annotation.id != i+1 || !validOwner || annotation.kind < 1 || annotation.kind > 6 || !validTarget || !validType || !validVariant || !validBuiltin {
			return fmt.Errorf("invalid call annotation %+v", annotation)
		}
	}
	expressionOwners := make([]int, len(m.expressions))
	matchOwners := make([]int, len(m.matches))
	tryOwners := make([]int, len(m.tries))
	expressionSites := make(map[[3]int]int)
	for i, expression := range m.expressions {
		if expression.left != 0 || expression.right != 0 || (expression.childCount == 0) != (expression.firstChild == 0) || expression.firstChild < 0 || expression.childCount < 0 || expression.childCount > 0 && (expression.firstChild < 1 || expression.firstChild-1+expression.childCount > len(m.children)) {
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
		if (expression.kind == 1 || expression.kind == 22) && expression.parameterUse >= 1 && expression.parameterUse <= len(m.locals) && expression.boolValue == 0 {
			parameter := m.locals[expression.parameterUse-1]
			validPayload = parameter.owner == expression.owner && (expression.kind == 22 || parameter.kind == 1) && parameter.checkedType == expression.checkedType
		}
		if expression.kind == 2 {
			validPayload = expression.parameterUse == 0 && (expression.boolValue == 0 || expression.boolValue == 1) && expression.checkedType >= 1 && expression.checkedType <= len(m.types) && m.types[expression.checkedType-1].kind == 1
		}
		if expression.kind == 3 {
			validPayload = expression.parameterUse == 0 && expression.boolValue == 0 && expression.checkedType >= 1 && expression.checkedType <= len(m.types) && m.types[expression.checkedType-1].kind == 1
		}
		if expression.kind == 20 {
			validPayload = expression.parameterUse == 0 && expression.boolValue == 0 && expression.checkedType >= 1 && expression.checkedType <= len(m.types) && m.types[expression.checkedType-1].kind == 1 && (m.types[expression.checkedType-1].target == 10 || m.types[expression.checkedType-1].target == 11) && expression.left == 0 && expression.right == 0 && expression.operator == 0 && expression.annotation == 0 && expression.childCount == 0
		}
		if expression.kind == 21 && expression.parameterUse >= 1 && expression.parameterUse <= len(m.uses) && expression.left >= 1 && expression.left < expression.id && expression.right == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation == 0 && expression.childCount == 1 {
			field := m.uses[expression.parameterUse-1]
			base := m.expressions[expression.left-1]
			validPayload = field.role == 1 && base.owner == expression.owner && base.checkedType >= 1 && base.checkedType <= len(m.types) && m.types[base.checkedType-1].kind == 7 && m.types[base.checkedType-1].target == field.owner
		}
		if expression.kind == 4 {
			payloadKind := 0
			if expression.checkedType >= 1 && expression.checkedType <= len(m.types) {
				payloadKind = m.types[expression.checkedType-1].kind
			}
			validPayload = expression.parameterUse == 0 && expression.boolValue == 0 && (payloadKind == 2 || payloadKind == 8 || payloadKind == 14)
		}
		if (expression.kind == 5 || expression.kind == 22) && expression.parameterUse >= 1 && expression.parameterUse <= len(m.locals) && expression.boolValue == 0 {
			local := m.locals[expression.parameterUse-1]
			validPayload = local.owner == expression.owner && local.checkedType == expression.checkedType
		}
		if expression.kind >= 1 && expression.kind <= 5 || expression.kind == 22 {
			validPayload = validPayload && expression.left == 0 && expression.right == 0 && expression.operator == 0
		}
		if expression.kind == 6 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.left >= 1 && expression.left < expression.id && expression.right == 0 && (expression.operator == 1 || expression.operator == 2) {
			child := m.expressions[expression.left-1]
			validPayload = child.owner == expression.owner && child.checkedType == expression.checkedType
		}
		if expression.kind == 7 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.left >= 1 && expression.left < expression.id && expression.right >= 1 && expression.right < expression.id && expression.left != expression.right && expression.operator >= 3 && expression.operator <= 17 {
			left, right := m.expressions[expression.left-1], m.expressions[expression.right-1]
			validPayload = left.owner == expression.owner && right.owner == expression.owner
		}
		if expression.kind >= 8 && expression.kind <= 11 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation >= 1 && expression.annotation <= len(m.callAnnotations) {
			annotation := m.callAnnotations[expression.annotation-1]
			callTargetKind, callTargetArity := 0, -1
			if annotation.target >= 1 && annotation.target <= len(m.symbols) {
				callTargetKind, callTargetArity = m.symbols[annotation.target-1].kind, m.symbols[annotation.target-1].arity
			}
			wantAnnotationKind := map[int]int{8: 1, 9: 3, 10: 4, 11: 2}[expression.kind]
			validPayload = annotation.owner == expression.owner && annotation.checkedType == expression.checkedType && annotation.kind == wantAnnotationKind
			role, wantChildren := 0, 0
			switch annotation.kind {
			case 1:
				role = 5
				if callTargetKind == 13 {
					role = 7
				}
			case 2:
				role = 3
			case 3:
				role = 1
			case 4:
				if annotation.variantUse >= 1 && annotation.variantUse <= len(m.uses) && m.uses[annotation.variantUse-1].checkedType != 0 {
					wantChildren = 1
				}
			}
			if role != 0 {
				for _, use := range m.uses {
					if use.owner == annotation.target && use.role == role {
						wantChildren++
					}
				}
			}
			validPayload = validPayload && expression.childCount == wantChildren
			for childOrdinal := 0; validPayload && childOrdinal < wantChildren; childOrdinal++ {
				wantType := 0
				if annotation.kind == 4 {
					wantType = m.uses[annotation.variantUse-1].checkedType
				} else {
					for _, use := range m.uses {
						if use.owner == annotation.target && use.role == role && use.ordinal == childOrdinal {
							wantType = use.checkedType
						}
					}
				}
				childID := m.children[expression.firstChild-1+childOrdinal].expression
				validPayload = childID >= 1 && childID < expression.id && (callTargetArity > 0 && (annotation.kind == 3 || annotation.kind == 4) || m.expressions[childID-1].checkedType == wantType)
			}
			if validPayload {
				callAnnotationOwners[expression.annotation-1]++
			}
		}
		if expression.kind == 10 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation >= 1 && expression.annotation <= len(m.callAnnotations) && m.callAnnotations[expression.annotation-1].kind == 6 && expression.childCount == 0 {
			annotation := m.callAnnotations[expression.annotation-1]
			validPayload = annotation.owner == expression.owner && annotation.kind == 6 && annotation.checkedType == expression.checkedType
			if validPayload {
				callAnnotationOwners[expression.annotation-1]++
			}
		}
		if expression.kind == 18 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation >= 1 && expression.annotation <= len(m.callAnnotations) {
			annotation := m.callAnnotations[expression.annotation-1]
			validPayload = annotation.owner == expression.owner && annotation.kind == 5 && annotation.checkedType == expression.checkedType
			for childOrdinal := 0; validPayload && childOrdinal < expression.childCount; childOrdinal++ {
				childID := m.children[expression.firstChild-1+childOrdinal].expression
				validPayload = childID >= 1 && childID < expression.id && m.expressions[childID-1].owner == expression.owner
			}
			if validPayload {
				callAnnotationOwners[expression.annotation-1]++
			}
		}
		if expression.kind == 19 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation == 0 && expression.childCount == 2 {
			baseID := m.children[expression.firstChild-1].expression
			indexID := m.children[expression.firstChild].expression
			if baseID >= 1 && baseID < expression.id && indexID >= 1 && indexID < expression.id {
				base, index := m.expressions[baseID-1], m.expressions[indexID-1]
				validPayload = base.owner == expression.owner && index.owner == expression.owner && base.checkedType >= 1 && base.checkedType <= len(m.types) && index.checkedType >= 1 && index.checkedType <= len(m.types)
				if validPayload {
					sequence, indexType := m.types[base.checkedType-1], m.types[index.checkedType-1]
					args := checkerDirectArgs(m, sequence)
					validPayload = (sequence.kind == 8 || sequence.kind == 15 || sequence.kind == 17 || sequence.kind == 18) && len(args) == 1 && args[0].checkedType == expression.checkedType && indexType.kind == 1 && indexType.target == 9
				}
			}
		}
		if expression.kind == 23 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation == 0 && expression.checkedType >= 1 && expression.checkedType <= len(m.types) {
			array := m.types[expression.checkedType-1]
			args := checkerDirectArgs(m, array)
			validPayload = array.kind == 15 && len(args) == 1 && array.target == expression.childCount
			for childOrdinal := 0; validPayload && childOrdinal < expression.childCount; childOrdinal++ {
				childID := m.children[expression.firstChild-1+childOrdinal].expression
				validPayload = childID >= 1 && childID < expression.id && m.expressions[childID-1].owner == expression.owner && m.expressions[childID-1].checkedType == args[0].checkedType
			}
		}
		if expression.kind == 13 && expression.parameterUse >= 1 && expression.parameterUse <= len(m.tries) && expression.boolValue == 0 && expression.operator == 0 && expression.annotation == 0 && expression.left >= 1 && expression.left < expression.id && expression.right == 0 {
			checkedTry := m.tries[expression.parameterUse-1]
			validPayload = checkedTry.owner == expression.owner && checkedTry.syntax == expression.syntax && checkedTry.expression == expression.left && checkedTry.okType == expression.checkedType
			if validPayload {
				tryOwners[expression.parameterUse-1]++
			}
		}
		if expression.kind == 12 && expression.parameterUse >= 1 && expression.parameterUse <= len(m.matches) && expression.boolValue == 0 && expression.operator == 0 && expression.annotation == 0 && expression.left >= 1 && expression.left < expression.id && expression.right == 0 {
			checkedMatch := m.matches[expression.parameterUse-1]
			validPayload = checkedMatch.owner == expression.owner && checkedMatch.syntax == expression.syntax && checkedMatch.scrutinee == expression.left && checkedMatch.checkedType == expression.checkedType
			if validPayload {
				matchOwners[expression.parameterUse-1]++
			}
		}
		if expression.kind >= 14 && expression.kind <= 17 && expression.parameterUse == 0 && expression.boolValue == 0 && expression.operator == 0 && expression.annotation == 0 && expression.checkedType >= 1 && expression.checkedType <= len(m.types) && expression.right == 0 {
			concrete := m.types[expression.checkedType-1]
			args := checkerDirectArgs(m, concrete)
			validPayload = expression.kind == 14 && concrete.kind == 9 && len(args) == 1 && expression.left == 0
			if expression.kind >= 15 && expression.left >= 1 && expression.left < expression.id {
				payload := m.expressions[expression.left-1]
				want := 0
				if expression.kind == 15 && concrete.kind == 9 && len(args) == 1 {
					want = args[0].checkedType
				}
				if expression.kind == 16 && concrete.kind == 10 && len(args) == 2 {
					want = args[0].checkedType
				}
				if expression.kind == 17 && concrete.kind == 10 && len(args) == 2 {
					want = args[1].checkedType
				}
				validPayload = want != 0 && payload.owner == expression.owner && payload.checkedType == want
			}
		}
		if expression.kind < 8 && expression.annotation != 0 {
			validPayload = false
		}
		validSite := expression.siteKind == 0 && expression.siteSyntax == 0 || expression.siteKind >= 1 && expression.siteKind <= 8 && expression.siteSyntax >= 1
		if expression.siteKind != 0 {
			expressionOwners[i]++
			key := [3]int{expression.owner, expression.siteKind, expression.siteSyntax}
			if expressionSites[key] != 0 {
				return fmt.Errorf("checked expressions %d and %d share site %v", expressionSites[key], expression.id, key)
			}
			expressionSites[key] = expression.id
		}
		validOwner := ownerKind == 12 && ownerArity == 0 || ownerKind == 13
		if expression.id != i+1 || !validOwner || expression.syntax < 1 || nodes[expression.syntax] || typeSyntax[expression.syntax] || bodySyntax[[2]int{expression.owner, expression.syntax}] || expression.checkedType < 1 || expression.checkedType > len(m.types) || !validPayload || !validSite {
			return fmt.Errorf("invalid checked expression %+v", expression)
		}
		bodySyntax[[2]int{expression.owner, expression.syntax}] = true
	}
	for i, owners := range callAnnotationOwners {
		if owners != 1 {
			return fmt.Errorf("call annotation %d has %d expression owners", i+1, owners)
		}
	}
	for i, checkedTry := range m.tries {
		validTypes := checkedTry.resultType >= 1 && checkedTry.resultType <= len(m.types) && checkedTry.okType >= 1 && checkedTry.okType <= len(m.types) && checkedTry.errorType >= 1 && checkedTry.errorType <= len(m.types)
		if validTypes {
			result := m.types[checkedTry.resultType-1]
			args := checkerDirectArgs(m, result)
			validTypes = result.kind == 10 && len(args) == 2 && args[0].checkedType == checkedTry.okType && args[1].checkedType == checkedTry.errorType
		}
		if checkedTry.id != i+1 || !checkerConcreteOwner(m, checkedTry.owner) || checkedTry.expression < 1 || checkedTry.expression > len(m.expressions) || m.expressions[checkedTry.expression-1].owner != checkedTry.owner || !validTypes || tryOwners[i] != 1 {
			return fmt.Errorf("invalid checked try %+v", checkedTry)
		}
	}
	armOwners := make([]int, len(m.matchArms))
	for i, checkedMatch := range m.matches {
		valid := checkedMatch.id == i+1 && checkerConcreteOwner(m, checkedMatch.owner) && checkedMatch.scrutinee >= 1 && checkedMatch.scrutinee <= len(m.expressions) && checkedMatch.scrutineeType >= 1 && checkedMatch.scrutineeType <= len(m.types) && checkedMatch.checkedType >= 1 && checkedMatch.checkedType <= len(m.types) && checkedMatch.armCount > 0 && checkedMatch.firstArm >= 1 && checkedMatch.firstArm-1+checkedMatch.armCount <= len(m.matchArms) && matchOwners[i] == 1
		if valid {
			scrutinee := m.expressions[checkedMatch.scrutinee-1]
			valid = scrutinee.owner == checkedMatch.owner && scrutinee.checkedType == checkedMatch.scrutineeType
		}
		for at := 0; valid && at < checkedMatch.armCount; at++ {
			arm := m.matchArms[checkedMatch.firstArm-1+at]
			valid = arm.id == checkedMatch.firstArm+at && arm.owner == checkedMatch.owner && arm.checkedMatch == checkedMatch.id && arm.variantKind >= 0 && arm.variantKind <= 7 && arm.body >= 1 && arm.body <= len(m.expressions) && m.expressions[arm.body-1].owner == checkedMatch.owner && m.expressions[arm.body-1].checkedType == checkedMatch.checkedType
			if valid {
				armOwners[arm.id-1]++
				expressionOwners[arm.body-1]++
			}
		}
		if !valid {
			return fmt.Errorf("invalid checked match %+v", checkedMatch)
		}
	}
	for i, owners := range armOwners {
		if owners != 1 {
			return fmt.Errorf("checked match arm %d has %d owners", i+1, owners)
		}
	}
	childOwners := make([]int, len(m.children))
	for _, expression := range m.expressions {
		for at := 0; at < expression.childCount; at++ {
			child := m.children[expression.firstChild-1+at]
			if child.id != expression.firstChild+at || child.expression < 1 || child.expression >= expression.id || childOwners[child.id-1] != 0 || m.expressions[child.expression-1].owner != expression.owner {
				return fmt.Errorf("invalid checked expression child %+v", child)
			}
			childOwners[child.id-1]++
			expressionOwners[child.expression-1]++
		}
	}
	for i, owners := range childOwners {
		if owners != 1 {
			return fmt.Errorf("checked expression child %d has %d owners", i+1, owners)
		}
	}
	for _, local := range m.locals {
		forBinding := false
		matchBinding := false
		for _, statement := range m.statements {
			if statement.kind == 9 && statement.binding == local.id {
				forBinding = true
			}
			if statement.kind == 10 && statement.binding == local.id {
				forBinding = true
			}
		}
		for _, arm := range m.matchArms {
			if arm.binding == local.id {
				matchBinding = true
			}
		}
		if local.kind == 2 && !forBinding && !matchBinding && expressionSites[[3]int{local.owner, 1, local.syntax}] == 0 {
			return fmt.Errorf("local binding %d has no initializer expression", local.id)
		}
	}
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
		validOwner := ownerKind == 12 && ownerArity == 0 || ownerKind == 13
		validRole := result.role == 6 && ownerKind == 12 || result.role == 8 && ownerKind == 13
		if checkedReturn.id != i+1 || !validOwner || checkedReturn.syntax < 1 || nodes[checkedReturn.syntax] || typeSyntax[checkedReturn.syntax] || bodySyntax[[2]int{checkedReturn.owner, checkedReturn.syntax}] || !validExpression || result.id == 0 || result.owner != checkedReturn.owner || !validRole {
			return fmt.Errorf("invalid checked return %+v", checkedReturn)
		}
		bodySyntax[[2]int{checkedReturn.owner, checkedReturn.syntax}] = true
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
		wantNote := 0
		if diagnostic.kind == 1 {
			wantNote = 1
		}
		if diagnostic.kind == 3 {
			wantNote = 2
		}
		if diagnostic.kind < 1 || diagnostic.kind > 144 || !validSourceRange(diagnostic.source, diagnostic.start, diagnostic.end, true) || diagnostic.hasRelated != (diagnostic.kind == 1 || diagnostic.kind == 3 || diagnostic.kind == 107 || diagnostic.kind == 111) || diagnostic.note != wantNote {
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

func checkerConcreteOwner(m checkerManifest, owner int) bool {
	if owner < 1 || owner > len(m.symbols) {
		return false
	}
	symbol := m.symbols[owner-1]
	return symbol.kind == 12 && symbol.arity == 0 || symbol.kind == 13
}

func checkerSubstitutedType(m checkerManifest, id int, bindings map[int]int) int {
	if id < 1 || id > len(m.types) {
		return 0
	}
	checked := m.types[id-1]
	if checked.kind == 6 {
		return bindings[checked.target]
	}
	args := checkerDirectArgs(m, checked)
	want := make([]int, len(args))
	for i, arg := range args {
		want[i] = checkerSubstitutedType(m, arg.checkedType, bindings)
		if want[i] == 0 {
			return 0
		}
	}
	for _, candidate := range m.types {
		if candidate.kind != checked.kind || candidate.target != checked.target || candidate.count != len(want) {
			continue
		}
		candidateArgs := checkerDirectArgs(m, candidate)
		matches := true
		for i := range want {
			matches = matches && candidateArgs[i].checkedType == want[i]
		}
		if matches {
			return candidate.id
		}
	}
	return 0
}

func checkerConcreteFieldType(m checkerManifest, aggregate, field int) int {
	if aggregate < 1 || aggregate > len(m.types) || field < 1 || field > len(m.uses) {
		return 0
	}
	checked, use := m.types[aggregate-1], m.uses[field-1]
	if checked.kind != 7 || use.owner != checked.target || use.role != 1 {
		return 0
	}
	bindings := make(map[int]int)
	args := checkerDirectArgs(m, checked)
	ordinal := 0
	for _, param := range m.params {
		if param.owner == checked.target {
			if ordinal >= len(args) {
				return 0
			}
			bindings[param.id] = args[ordinal].checkedType
			ordinal++
		}
	}
	if ordinal != len(args) {
		return 0
	}
	return checkerSubstitutedType(m, use.checkedType, bindings)
}

func checkedManifestTypeConcrete(m checkerManifest, id int) bool {
	if id < 1 || id > len(m.types) {
		return false
	}
	checked := m.types[id-1]
	if checked.kind == 6 {
		return false
	}
	for _, arg := range checkerDirectArgs(m, checked) {
		if !checkedManifestTypeConcrete(m, arg.checkedType) {
			return false
		}
	}
	return true
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
		{name: "controlled", path: "a space.al", kind: 12},
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
	for ordinal, name := range []string{"x", "a", "b", "c", "d", "mark", "text", "bytes"} {
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
		t.Fatalf("Nest String field kind=%d, want distinct String kind 2", kind)
	}
	if kind := m.types[checkerUse(t, m, nest.id, 1, 7).checkedType-1].kind; kind != 14 {
		t.Fatalf("Nest Bytes field kind=%d, want distinct Bytes kind 14", kind)
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
	controlled := checkerSymbolByName(t, m, inputs, "controlled")
	if len(m.uses) != 86 || len(m.expressions) != 2 || len(m.returns) != 1 || len(m.locals) != 0 || m.types[checkerUse(t, m, controlled.id, 6, 0).checkedType-1].kind != 1 {
		t.Fatalf("controlled body or declaration-use count changed: uses=%d expressions=%d returns=%d", len(m.uses), len(m.expressions), len(m.returns))
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
	for kind := 1; kind <= 14; kind++ {
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
	valid := "ALDER-CHECKER-MANIFEST 14\nS 0 612e616c 1\nEND\n"
	if _, err := decodeCheckerManifest(valid, inputs); err != nil {
		t.Fatalf("valid minimal manifest: %v", err)
	}
	malformed := map[string]string{
		"version 13 envelope":         strings.Replace(valid, "MANIFEST 14", "MANIFEST 13", 1),
		"record after diagnostics":    "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nD 4 0 0 1 0\nC 1 1 0 1 0 0\nEND\n",
		"invalid primitive target":    "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nC 1 1 0 0 0 0\nD 4 0 0 1 0\nEND\n",
		"duplicate canonical type":    "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nC 1 1 0 1 0 0\nC 2 1 0 1 0 0\nD 4 0 0 1 0\nEND\n",
		"invalid type argument range": "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nC 1 8 0 0 1 1\nD 4 0 0 1 0\nEND\n",
		"annotation unknown owner":    "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nC 1 1 0 1 0 0\nT 1 1 1 1\nD 4 0 0 1 0\nEND\n",
		"orphan environment":          "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nN 1 1 0 1\nD 4 0 0 1 0\nEND\n",
		"truncated expression child":  "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nH 1\nEND\n",
		"truncated match":             "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nM 1 1\nEND\n",
		"truncated match arm":         "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nW 1 1\nEND\n",
		"truncated try":               "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nX 1 1\nEND\n",
		"truncated source span":       "ALDER-CHECKER-MANIFEST 14\nS 0 612e616c 1\nZ 1 0\nEND\n",
		"truncated cleanup":           "ALDER-CHECKER-MANIFEST 14\nS 0 612e616c 1\nG 1 1\nEND\n",
	}
	bodyPrefix := "ALDER-CHECKER-MANIFEST 14\nS 0 612e616c 1\nY 1 12 1 0 0 1 0 1 0 0 0\nC 1 1 0 9 0 0\nC 2 1 0 1 0 0\nT 1 1 2 1\nT 2 1 3 1\nU 1 1 5 0 4 0 0 1 2 1\nU 2 1 6 0 5 0 0 0 3 1\nI 1 1 1 0 0 0\nL 1 1 1 4 0 0 1 0 1\nN 1 1 0 1\n"
	validUnaryBody := bodyPrefix + "E 1 1 6 1 1 1 0 0 0 0 0 0 0 0 0\nE 2 1 8 6 1 0 0 0 0 0 1 1 1 3 7\nH 1 1\nR 1 1 7 2 2\nJ 1 1 7 4 1 2 0 0 0 0\nK 1 1 0\nB 1 1 8 1 1 1\nEND\n"
	if _, err := decodeCheckerManifest(validUnaryBody, inputs); err != nil {
		t.Fatalf("valid unary body manifest: %v", err)
	}
	malformed["invalid child range"] = strings.Replace(validUnaryBody, " 1 1 1 3 7\nH", " 2 1 1 3 7\nH", 1)
	malformed["forward child ID"] = strings.Replace(validUnaryBody, "H 1 1", "H 1 2", 1)
	malformed["invalid environment parent"] = strings.Replace(validUnaryBody, "N 1 1 0 1", "N 1 1 1 1", 1)
	malformed["invalid environment binding"] = strings.Replace(validUnaryBody, "N 1 1 0 1", "N 1 1 0 2", 1)
	malformed["binding type disagreement"] = strings.Replace(validUnaryBody, "E 1 1 6 1 1 1", "E 1 1 6 1 2 1", 1)
	malformed["missing concrete instance record"] = strings.Replace(validUnaryBody, "I 1 1 1 0 0 0\n", "", 1)
	malformed["instance declaration mismatch"] = strings.Replace(validUnaryBody, "I 1 1 1 0 0 0", "I 1 1 2 0 0 0", 1)
	malformed["instance argument range"] = strings.Replace(validUnaryBody, "I 1 1 1 0 0 0", "I 1 1 1 1 1 0", 1)
	malformed["instance discovery cycle"] = strings.Replace(validUnaryBody, "I 1 1 1 0 0 0", "I 1 1 1 0 0 1", 1)
	validCallBody := "ALDER-CHECKER-MANIFEST 14\nS 0 612e616c 1\nY 1 12 1 0 0 1 0 1 0 0 0\nC 1 1 0 9 0 0\nT 1 1 2 1\nU 1 1 6 0 3 0 0 0 2 1\nI 1 1 1 0 0 0\nQ 1 1 1 1 1 0 0\nE 1 1 4 8 1 0 0 0 0 1 0 0 0 3 5\nR 1 1 5 1 1\nJ 1 1 5 4 0 1 0 0 0 0\nK 1 1 0\nB 1 1 6 0 1 1\nEND\n"
	if _, err := decodeCheckerManifest(validCallBody, inputs); err != nil {
		t.Fatalf("valid call body manifest: %v", err)
	}
	malformed["call annotation noncanonical ID"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0", "Q 2 1 1 1 1 0", 1)
	malformed["call annotation unknown owner"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0", "Q 1 2 1 1 1 0", 1)
	malformed["call annotation invalid kind"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0", "Q 1 1 5 1 1 0", 1)
	malformed["call annotation invalid target"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0", "Q 1 1 1 2 1 0", 1)
	malformed["call annotation invalid type"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0", "Q 1 1 1 1 2 0", 1)
	malformed["call annotation unexpected variant"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0", "Q 1 1 1 1 1 1", 1)
	malformed["call annotation invalid builtin identity"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0 0", "Q 1 1 5 0 1 0 18", 1)
	malformed["expression missing call annotation"] = strings.Replace(validCallBody, "E 1 1 4 8 1 0 0 0 0 1", "E 1 1 4 8 1 0 0 0 0 0", 1)
	malformed["call annotation after expression"] = strings.Replace(validCallBody, "Q 1 1 1 1 1 0 0\nE 1 1 4 8 1 0 0 0 0 1 0 0 0 3 5", "E 1 1 4 8 1 0 0 0 0 1 0 0 0 3 5\nQ 1 1 1 1 1 0 0", 1)
	controlPrefix := "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nY 1 12 1 0 0 1 0 1 0 0 0\nC 1 1 0 12 0 0\nT 1 1 2 1\nU 1 1 6 0 3 0 0 0 2 1\nI 1 1 1 0 0 0\n"
	controlPrefix = strings.Replace(controlPrefix, "MANIFEST 11", "MANIFEST 14", 1)
	validControlBody := controlPrefix + "B 1 1 4 0 0 0\nEND\n"
	if _, err := decodeCheckerManifest(validControlBody, inputs); err != nil {
		t.Fatalf("valid control body manifest: %v", err)
	}
	malformed["place unknown root"] = controlPrefix + "V 1 1 4 1 1 0 0 1\nB 1 1 5 0 0 0\nEND\n"
	malformed["statement unknown place"] = controlPrefix + "J 1 1 4 3 0 0 1 0 0 0\nK 1 1 0\nB 1 1 5 0 1 0\nEND\n"
	malformed["statement link unknown statement"] = controlPrefix + "K 1 1 0\nB 1 1 4 0 1 0\nEND\n"
	malformed["block unknown environment"] = strings.Replace(validControlBody, "B 1 1 4 0 0 0", "B 1 1 4 1 0 0", 1)
	assignmentPrefix := "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nY 1 12 1 0 0 1 0 1 0 0 0\nC 1 1 0 9 0 0\nC 2 1 0 12 0 0\nT 1 1 2 1\nT 2 1 3 2\nU 1 1 5 0 4 0 0 1 2 1\nU 2 1 6 0 5 0 0 0 3 2\nI 1 1 1 0 0 0\nL 1 1 1 4 0 0 1 0 1\nN 1 1 0 1\nE 1 1 6 1 1 1 0 0 0 0 0 0 0 2 7\nV 1 1 5 1 1 0 0 1\nJ 1 1 7 3 1 1 1 0 0 0\nK 1 1 0\nB 1 1 8 1 1 0\nEND\n"
	assignmentPrefix = strings.Replace(assignmentPrefix, "MANIFEST 11", "MANIFEST 14", 1)
	if _, err := decodeCheckerManifest(assignmentPrefix, inputs); err != nil {
		t.Fatalf("valid assignment control manifest: %v", err)
	}
	genericFieldBody := "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nY 1 2 1 0 0 1 1 0 0 0 0\nY 2 12 4 0 0 1 0 2 0 0 0\nP 1 1 2 0 0 1\nC 1 1 0 9 0 0\nC 2 6 0 1 0 0\nC 3 7 0 1 1 1\nC 4 1 0 12 0 0\nA 1 1\nT 1 1 5 2\nT 2 2 6 3\nT 3 2 7 4\nU 1 1 1 0 3 0 0 1 5 2\nU 2 2 5 0 5 0 0 1 6 3\nU 3 2 6 0 6 0 0 0 7 4\nI 1 2 2 0 0 0\nL 1 2 1 5 0 0 1 0 3\nN 1 2 0 1\nE 1 2 8 3 1 0 0 0 0 0 0 0 0 2 9\nV 1 2 7 2 1 1 0 1\nJ 1 2 9 3 1 1 1 0 0 0\nK 1 1 0\nB 1 2 10 1 1 0\nEND\n"
	genericFieldBody = strings.Replace(genericFieldBody, "MANIFEST 11", "MANIFEST 14", 1)
	if _, err := decodeCheckerManifest(genericFieldBody, inputs); err != nil {
		t.Fatalf("valid generic field control manifest: %v", err)
	}
	indexedBody := "ALDER-CHECKER-MANIFEST 11\nS 0 612e616c 1\nY 1 12 1 0 0 1 0 1 0 0 0\nC 1 1 0 9 0 0\nC 2 1 0 12 0 0\nC 3 8 0 0 1 1\nA 1 1\nT 1 1 2 3\nT 2 1 3 2\nU 1 1 5 0 4 0 0 1 2 3\nU 2 1 6 0 5 0 0 0 3 2\nI 1 1 1 0 0 0\nL 1 1 1 4 0 0 1 0 3\nN 1 1 0 1\nE 1 1 6 3 1 0 0 0 0 0 0 0 0 7 8\nE 2 1 7 3 1 0 0 0 0 0 0 0 0 2 8\nV 1 1 5 3 1 0 1 1\nJ 1 1 8 3 1 2 1 0 0 0\nK 1 1 0\nB 1 1 9 1 1 0\nEND\n"
	indexedBody = strings.Replace(indexedBody, "MANIFEST 11", "MANIFEST 14", 1)
	if _, err := decodeCheckerManifest(indexedBody, inputs); err != nil {
		t.Fatalf("valid indexed control manifest: %v", err)
	}
	nestedBlockBody := controlPrefix + "J 1 1 5 6 0 0 0 0 1 0\nK 1 1 0\nB 1 1 5 0 0 0\nB 2 1 6 0 1 0\nEND\n"
	if _, err := decodeCheckerManifest(nestedBlockBody, inputs); err != nil {
		t.Fatalf("valid nested block control manifest: %v", err)
	}
	childBlockCycle := strings.Replace(nestedBlockBody, "J 1 1 5 6 0 0 0 0 1 0", "J 1 1 5 6 0 0 0 0 2 0", 1)
	childBlockCycle = strings.Replace(childBlockCycle, "B 2 1 6 0 1 0", "B 2 1 5 0 1 0", 1)
	focusedMalformed := map[string]struct {
		text, errorPart string
	}{
		"orphan statement":               {strings.Replace(assignmentPrefix, "K 1 1 0\nB 1 1 8 1 1 0", "B 1 1 8 1 0 0", 1), "checked statement 1 has 0 link owners"},
		"duplicate statement ownership":  {strings.Replace(assignmentPrefix, "K 1 1 0\nB 1 1 8 1 1 0", "K 1 1 0\nK 2 1 0\nB 1 1 8 1 1 0\nB 2 1 9 1 2 0", 1), "checked statement 1 has 2 link owners"},
		"unordered statement chain":      {strings.Replace(assignmentPrefix, "K 1 1 0\nB 1 1 8 1 1 0", "K 1 1 0\nK 2 1 1\nB 1 1 8 1 2 0", 1), "not in source order"},
		"nonconcrete block owner":        {strings.Replace(assignmentPrefix, "B 1 1 8 1 1 0", "B 1 2 8 1 1 0", 1), "invalid checked block"},
		"forbidden statement payload":    {strings.Replace(assignmentPrefix, "J 1 1 7 3 1 1 1 0 0 0", "J 1 1 7 3 1 1 1 1 0 0", 1), "invalid checked statement payload"},
		"place kind payload":             {strings.Replace(assignmentPrefix, "V 1 1 5 1 1 0 0 1", "V 1 1 5 1 1 1 0 1", 1), "fieldless checked place has field"},
		"place checked type":             {strings.Replace(assignmentPrefix, "V 1 1 5 1 1 0 0 1", "V 1 1 5 1 1 0 0 2", 1), "place type disagrees"},
		"place source component order":   {strings.Replace(assignmentPrefix, "V 1 1 5 1 1 0 0 1", "V 1 1 7 1 1 0 0 1", 1), "statement payload"},
		"expression statement site":      {strings.Replace(assignmentPrefix, "0 2 7\nV", "0 2 8\nV", 1), "statement payload"},
		"orphan place":                   {strings.Replace(assignmentPrefix, "V 1 1 5 1 1 0 0 1", "V 1 1 5 1 1 0 0 1\nV 2 1 4 1 1 0 0 1", 1), "checked place 2 has 0 statement owners"},
		"invalid block return guarantee": {strings.Replace(assignmentPrefix, "B 1 1 8 1 1 0", "B 1 1 8 1 1 1", 1), "invalid return guarantee"},
		"field use wrong aggregate":      {strings.Replace(genericFieldBody, "V 1 2 7 2 1 1 0 1", "V 1 2 7 2 1 2 0 1", 1), "field does not belong"},
		"generic field substitution":     {strings.Replace(genericFieldBody, "V 1 2 7 2 1 1 0 1", "V 1 2 7 2 1 1 0 4", 1), "place type disagrees"},
		"index is not U64":               {strings.Replace(indexedBody, "E 1 1 6 3 1", "E 1 1 6 3 2", 1), "index is not owned U64"},
		"index expression owner":         {strings.Replace(indexedBody, "E 1 1 6 3 1", "E 1 2 6 3 1", 1), "index is not owned U64"},
		"place component order":          {strings.Replace(indexedBody, "E 1 1 6 3 1 0 0 0 0 0 0 0 0 7 8\nE 2 1 7 3 1 0 0 0 0 0 0 0 0 2 8\nV 1 1 5 3 1 0 1 1\nJ 1 1 8 3 1 2", "E 1 1 6 3 1 0 0 0 0 0 0 0 0 2 8\nE 2 1 7 3 1 0 0 0 0 0 0 0 0 7 8\nV 1 1 5 3 1 0 2 1\nJ 1 1 8 3 1 1", 1), "components do not precede"},
		"child block cycle":              {childBlockCycle, "child block is not acyclic"},
		"child block parent ownership":   {strings.Replace(nestedBlockBody, "B 1 1 5 0 0 0", "B 1 2 5 0 0 0", 1), "statement payload"},
	}
	for name, fixture := range focusedMalformed {
		t.Run(name, func(t *testing.T) {
			_, err := decodeCheckerManifest(fixture.text, inputs)
			if err == nil || !strings.Contains(err.Error(), fixture.errorPart) {
				t.Fatalf("malformed control manifest error=%v, want %q\n%s", err, fixture.errorPart, fixture.text)
			}
		})
	}
	for name, text := range malformed {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeCheckerManifest(text, inputs); err == nil {
				t.Fatalf("malformed manifest accepted:\n%s", text)
			}
		})
	}
}
