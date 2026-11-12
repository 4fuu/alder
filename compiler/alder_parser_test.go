package compiler

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

const parserWrapper = `
fn parser_storage_error() -> I32 {
    let text: __s0_String = "alder compiler: storage failure\n"
    var at: U64 = 0
    while at < len(text) {
        if !unsafe c { alderhost_stderr_byte(text[at]) } { return 3 }
        at = at + 1
    }
    return 3
}
fn parser_lex_bad(state: State) -> I32 {
    if !emit(state) { return 4 }
    return 1
}
fn parser_finish_good(state: State, store: ParseStore) -> I32 {
    if !emit_parse_manifest(state, store) { return 4 }
    return 0
}
fn parser_finish_bad(state: State, store: ParseStore) -> I32 {
    if !emit_parse_manifest(state, store) { return 4 }
    return 1
}
fn parser_finish(result: ParseResult) -> I32 {
    return match result {
        ParseGood(output) => parser_finish_good(output.state, output.store)
        ParseBad(output) => parser_finish_bad(output.state, output.store)
        ParseLexBad(output) => parser_lex_bad(output.state)
    }
}
fn parser_parse(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec), roots: __s0_Buffer(U64), diagnostics: __s0_Buffer(ParseDiagRec), bindings: __s0_Buffer(ParseBindingRec)) -> I32 {
    return match parse_sources(d, state, ParseStore(nodes: nodes, links: links, roots: roots, diagnostics: diagnostics, bindings: bindings, binding_count: 0)) {
        Err(error) => parser_storage_error()

        Ok(result) => parser_finish(result)
    }
}
fn parser_init_diags(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec), roots: __s0_Buffer(U64)) -> I32 { return match __s0_buffer_new(ParseDiagRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => match __s0_buffer_new(ParseBindingRec, d) {
            Err(error) => parser_storage_error()
            Ok(bindings) => parser_parse(d, state, nodes, links, roots, b, bindings) } } }
fn parser_init_roots(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec)) -> I32 { return match __s0_buffer_new(U64, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_diags(d, state, nodes, links, b) } }
fn parser_init_links(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec)) -> I32 { return match __s0_buffer_new(SyntaxLinkRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_roots(d, state, nodes, b) } }
fn parser_init_nodes(d: Domain, state: State) -> I32 { return match __s0_buffer_new(SyntaxRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_links(d, state, b) } }
fn parser_run(d: Domain, state: State) -> I32 { return match load_sources(d, state) {
        Err(error) => parser_storage_error()
        Ok(loaded) => parser_init_nodes(d, loaded) } }
fn parser_init_lex_diags(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec), tokens: __s0_Buffer(TokenRec)) -> I32 { return match __s0_buffer_new(LexDiagRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_run(d, State(paths: paths, texts: texts, values: values, sources: sources, tokens: tokens, diagnostics: b)) } }
fn parser_init_tokens(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec)) -> I32 { return match __s0_buffer_new(TokenRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_lex_diags(d, paths, texts, values, sources, b) } }
fn parser_init_sources(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(SourceRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_tokens(d, paths, texts, values, b) } }
fn parser_init_values(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(U8, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_sources(d, paths, texts, b) } }
fn parser_init_texts(d: Domain, paths: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(U8, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_values(d, paths, b) } }
fn main(d: Domain) -> I32 { return match __s0_buffer_new(U8, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_init_texts(d, b) } }
`

const wantParserManifest = `ALDER-PARSER-MANIFEST 1
S 0 a.al 108
S 1 b.al 137
S 2 z-empty.al 0
T 96
R 0 3
R 1 6
R 2 9
R 3 12
R 4 15
R 5 18
R 6 23
R 7 28
R 8 36
N 1 4 6 0 12 15 a.al 12 15 12 15 0
N 2 8 4 0 9 10 a.al 9 15 9 10 1
N 3 2 1 0 0 4 a.al 0 17 5 6 2
N 4 4 13 0 30 33 a.al 30 33 30 33 0
N 5 8 11 0 27 28 a.al 27 33 27 28 3
N 6 2 8 0 18 22 a.al 18 35 23 24 4
N 7 4 20 0 48 51 a.al 48 51 48 51 0
N 8 8 18 0 45 46 a.al 45 51 45 46 5
N 9 2 15 0 36 40 a.al 36 53 41 42 6
N 10 4 27 0 66 69 a.al 66 69 66 69 0
N 11 8 25 0 63 64 a.al 63 69 63 64 7
N 12 2 22 0 54 58 a.al 54 71 59 60 8
N 13 4 34 0 84 87 a.al 84 87 84 87 0
N 14 8 32 0 81 82 a.al 81 87 81 82 9
N 15 2 29 0 72 76 a.al 72 89 77 78 10
N 16 4 41 0 102 105 a.al 102 105 102 105 0
N 17 8 39 0 99 100 a.al 99 105 99 100 11
N 18 2 36 0 90 94 a.al 90 107 95 96 12
N 19 4 51 1 19 21 b.al 19 21 19 21 0
N 20 5 50 1 18 19 b.al 18 22 0 0 13
N 21 4 56 1 28 31 b.al 28 31 28 31 0
N 22 10 48 1 15 17 b.al 15 31 0 0 15
N 23 1 44 1 0 6 b.al 0 31 9 13 16
N 24 7 60 1 48 49 b.al 48 55 48 49 0
N 25 4 69 1 70 71 b.al 70 71 70 71 0
N 26 5 68 1 69 70 b.al 69 72 0 0 18
N 27 8 66 1 62 67 b.al 62 72 62 67 19
N 28 2 57 1 39 43 b.al 39 75 44 47 20
N 29 7 75 1 89 90 b.al 89 96 89 90 0
N 30 11 83 1 108 113 b.al 108 113 108 113 0
N 31 4 88 1 120 121 b.al 120 121 120 121 0
N 32 5 87 1 119 120 b.al 119 122 0 0 23
N 33 6 85 1 115 118 b.al 115 124 115 118 24
N 34 9 81 1 103 107 b.al 103 125 103 107 25
N 35 9 93 1 128 132 b.al 128 132 128 132 0
N 36 3 72 1 77 81 b.al 77 135 82 88 27
L 1 1 0
L 2 2 0
L 3 4 0
L 4 5 0
L 5 7 0
L 6 8 0
L 7 10 0
L 8 11 0
L 9 13 0
L 10 14 0
L 11 16 0
L 12 17 0
L 13 19 0
L 14 20 0
L 15 21 14
L 16 22 0
L 17 24 0
L 18 25 0
L 19 26 0
L 20 27 17
L 21 29 0
L 22 30 0
L 23 31 0
L 24 32 0
L 25 33 22
L 26 34 21
L 27 35 26
END
`

func TestAlderParserConformanceEndToEnd(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}

	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var sources []frontend.Source
	for _, name := range parserSourceManifest {
		text, err := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if err != nil {
			t.Fatal(err)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(len(sources) + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	sources = append(sources, frontend.Source{ID: 99, Path: "compiler/test/parser_main.al", Text: parserWrapper})
	rev := append([]frontend.Source(nil), sources...)
	for i, j := 0, len(rev)-1; i < j; i, j = i+1, j-1 {
		rev[i], rev[j] = rev[j], rev[i]
	}
	forward, forwardErr := Compile(Request{Sources: sources, Emit: EmitMIR, BootstrapPrivate: true})
	reversed, reversedErr := Compile(Request{Sources: rev, Emit: EmitMIR, BootstrapPrivate: true})
	if forwardErr != nil || reversedErr != nil || forward.Artifact == nil || reversed.Artifact == nil || len(forward.Diagnostics) != 0 || len(reversed.Diagnostics) != 0 {
		t.Fatalf("compile parser MIR: forward=%+v/%v reversed=%+v/%v", forward, forwardErr, reversed, reversedErr)
	}
	if forward.Artifact.Text != reversed.Artifact.Text {
		t.Fatal("parser MIR changed with compiler source request order")
	}
	module, err := mir.Parse(forward.Artifact.Text)
	if err != nil {
		t.Fatalf("parse emitted parser MIR: %v", err)
	}
	if errs := verify.Module(module); len(errs) != 0 {
		t.Fatalf("emitted parser MIR failed verification: %s", verify.Errors(errs).String())
	}
	id, ok := module.Function("parse_sources")
	if !ok {
		t.Fatal("emitted parser MIR has no parse_sources function")
	}
	for _, block := range module.Functions[id].Blocks {
		for _, instruction := range block.Instrs {
			if instruction.Op == mir.OpCall && instruction.Callee == id {
				t.Fatal("parse_sources recursively calls itself")
			}
		}
	}
	// Generate from the verified textual round trip: MIR equality already proves
	// source-order independence without compiling this compiler-sized unit twice
	// more through the identical frontend for EmitC.
	generated, err := cgen.GenerateProgram(module)
	if err != nil {
		t.Fatalf("generate parser C from round-tripped MIR: %v", err)
	}
	for _, leaked := range []string{root, filepath.ToSlash(root), strings.ReplaceAll(root, `\`, `\\`)} {
		if leaked != "" && strings.Contains(generated, leaked) {
			t.Fatalf("generated C contains checkout path %q", leaked)
		}
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "parser.c")
	exe := filepath.Join(dir, "parser.exe")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-ffp-contract=off", "-DALDER_HOST_CONFORMANCE", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cfile, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile: %v\n%s", err, output)
	}
	files := map[string]string{
		"z-empty.al": "",
		"b.al":       "import c puts: fn([U8],) -> I32\r\n// c\r\ntype Box(T: type,) {\r\n value: [T]\r\n}\r\nenum Choice(T: type,) {\r\n Some(value: Box([T],))\r\n None\r\n}\r\n",
		"a.al":       "type A { x: U64 }\ntype B { x: U64 }\ntype C { x: U64 }\ntype D { x: U64 }\ntype E { x: U64 }\ntype F { x: U64 }\n",
	}
	first := runAlderParser(t, exe, files, []string{"z-empty.al", "b.al", "a.al"}, false)
	second := runAlderParser(t, exe, files, []string{"a.al", "z-empty.al", "b.al"}, false)
	if first != wantParserManifest || second != wantParserManifest {
		t.Fatalf("success manifest mismatch\nwant:\n%s\ngot:\n%s", wantParserManifest, first)
	}
	validateParserManifest(t, first, files)
	functionSource := "fn empty() -> U64 {\r\n return\r\n}\r\n" +
		"fn core(T: type, mut x: U64, take owner: Domain,) -> U64 {\r\n" +
		" // bindings and delimiter continuation\r\n let a: U64 = (1 +\r\n 2) * 3 / 4 % 5 - 6 << 1 >> 1 < 9 <= 9 > 0 >= 0 == true != false && !false || true\r\n" +
		" var b = 1.5\r\n let s = \"text\"\r\n let c = empty()\r\n let d = core(\r\n T: x, x,\r\n )\r\n x = try d\r\n x.field = a\r\n x[b] = c\r\n x[b].field = s\r\n {\r\n  return x\r\n }\r\n return\r\n}\r\n"
	functionSource += "fn assoc(a: U64, b: U64, c: U64, d: U64) -> U64 {\r\n" +
		" let sub = a - b - c\r\n let mixed = a + b * c\r\n let logic = a || b && c\r\n let product = a / b * c % d\r\n return product\r\n}\r\n" +
		"fn postfix(factory: U64, x: U64, y: U64) -> U64 {\r\n return factory()(x).field[y]\r\n}\r\n" +
		"fn named(f: U64, a: U64, b: U64) -> U64 {\r\n (f())\r\n return f(a, label: b,)\r\n}\r\n"
	functionFiles := map[string]string{"functions.al": functionSource}
	functionManifest := runAlderParser(t, exe, functionFiles, []string{"functions.al"}, false)
	functionTree := validateParserManifest(t, functionManifest, functionFiles)
	assertFunctionParserTree(t, functionTree)
	flowSource := "fn flow(xs: U64, value: U64) -> U64 {\n" +
		" if true {\n  return value\n } else {\n  return 0\n }\n" +
		" while false {\n  return\n }\n" +
		" for item in xs {\n  return item\n }\n" +
		" using resource = make() with CleanupFn\n" +
		" let selected = match value {\n  Some(payload) => payload\n  None => 0\n  _ => (1)\n }\n" +
		" let called = unsafe c { foreign(value) }\n return selected\n}\n"
	flowSource += "fn nested(value: U64) -> U64 {\n" +
		" return match (value + 1) {\n" +
		"  Some(payload) => match payload {\n" +
		"   _ => payload +\n    1\n" +
		"  }\n  _ => 0\n }\n}\n"
	flowSource += "fn grouped_arms(x: U64, f: U64, i: U64) -> U64 {\n" +
		" return match x {\n" +
		"  A => (x)\n  B => ((x))\n  C => (f)()\n  D => (x).field\n  E => (x)[i]\n  F => (f())\n }\n}\n"
	flowFiles := map[string]string{"flow.al": flowSource}
	flowManifest := runAlderParser(t, exe, flowFiles, []string{"flow.al"}, false)
	flowTree := validateParserManifest(t, flowManifest, flowFiles)
	assertControlParserTree(t, flowTree)
	if repeat := runAlderParser(t, exe, flowFiles, []string{"flow.al"}, false); repeat != flowManifest {
		t.Fatal("control/match/unsafe manifest changed across processes")
	}
	if repeat := runAlderParser(t, exe, functionFiles, []string{"functions.al"}, false); repeat != functionManifest {
		t.Fatal("function/expression manifest changed across processes")
	}
	seenKinds := make(map[int]bool)
	for _, node := range functionTree.nodes {
		seenKinds[node.kind] = true
	}
	for _, node := range flowTree.nodes {
		seenKinds[node.kind] = true
	}
	for kind := 12; kind <= 39; kind++ {
		if !seenKinds[kind] {
			t.Fatalf("function/expression manifest does not exercise syntax kind %d\n%s", kind, functionManifest)
		}
	}
	moduleSource := "module acme.main\n" +
		"import acme.compiler.token\n" +
		"import acme.compiler.syntax as tree\n" +
		"pub import acme.api { Request, Response }\n" +
		"pub type Exported { value: U64 }\n" +
		"pub fn entry() -> I32 { return 0 }\n"
	moduleFiles := map[string]string{"module.al": moduleSource}
	moduleManifest := runAlderParser(t, exe, moduleFiles, []string{"module.al"}, false)
	moduleTree := validateParserManifest(t, moduleManifest, moduleFiles)
	moduleKinds := make(map[int]bool)
	for _, node := range moduleTree.nodes {
		moduleKinds[node.kind] = true
	}
	for kind := 40; kind <= 46; kind++ {
		if !moduleKinds[kind] {
			t.Fatalf("module manifest does not exercise syntax kind %d\n%s", kind, moduleManifest)
		}
	}
	if repeat := runAlderParser(t, exe, moduleFiles, []string{"module.al"}, false); repeat != moduleManifest {
		t.Fatal("module parser manifest changed across processes")
	}
	if again := runAlderParser(t, exe, files, []string{"b.al", "a.al", "z-empty.al"}, false); again != first {
		t.Fatal("repeat parser process output changed")
	}
	// A generic implementation is not limited to traits: the same parameter
	// list may declare an inherent implementation of an applied type.
	genericImplFiles := map[string]string{"impl-generic-inherent.al": "type File(I: type) {\n    id: I\n}\n\nimpl(I: type) File(I) {\n    fn id(self) -> I {\n        return self.id\n    }\n}\n"}
	genericImplManifest := runAlderParser(t, exe, genericImplFiles, []string{"impl-generic-inherent.al"}, false)
	if strings.Contains(genericImplManifest, "\nD ") {
		t.Fatalf("generic inherent implementation rejected:\n%s", genericImplManifest)
	}
	rejects := []struct {
		name, text       string
		kind, start, end int
	}{
		{"if.al", "fn bad() -> U64 { if\n true {}\n}", 13, 22, 26},
		{"ident.al", "type {", 3, 5, 6},
		{"punct.al", "type A x", 4, 7, 8},
		{"type.al", "type A { x: }", 5, 12, 13},
		{"label.al", "enum E { V(: U64)\n}", 6, 11, 12},
		{"top.al", "type A {} type B {}", 7, 10, 14},
		{"field.al", "type A { x: U64 y: U64\n}", 8, 16, 17},
		{"variant.al", "enum E { A B\n}", 9, 11, 12},
		{"eof.al", "type A {", 4, 8, 8},
		{"where-fn.al", "fn bad(T: type) -> U64\nwhere T: Eq {\n    return 0\n}\n", 24, 23, 28},
		{"where-record.al", "type Slot(K: type, V: type)\nwhere K: Eq {\n    key: K\n}\n", 24, 28, 33},
		{"where-trait.al", "trait Bad(T: type)\nwhere T: Eq {\n    fn next(self) -> U64\n}\n", 24, 19, 24},
		{"where-impl.al", "type Box { v: U64 }\ntrait Mark { }\nimpl Mark for Box\nwhere Box: Mark {\n}\n", 24, 53, 58},
		{"constraint-plus.al", "fn bad(T: type(Eq + Hash), t: T) -> U64 {\n    return 0\n}\n", 4, 18, 19},
		{"impl-constraint-plus.al", "trait Io {\n}\n\ntrait Reader {\n    fn read(self) -> U64\n}\n\ntype Token {\n}\n\ntype File(I: type(Io)) {\n    id: I\n}\n\nimpl(I: type(Io + Reader)) Reader for File(I) {\n    fn read(self) -> U64 { return 0 }\n}\n", 4, 127, 128},
	}
	for _, tc := range rejects {
		t.Run(tc.name, func(t *testing.T) {
			got := runAlderParser(t, exe, map[string]string{tc.name: tc.text}, []string{tc.name}, true)
			want := fmt.Sprintf("D SYN0001 %d %s %d %d", tc.kind, tc.name, tc.start, tc.end)
			if diagnostic := parserDiagnosticLine(t, got); diagnostic != want {
				t.Fatalf("diagnostic mismatch: want %q, got %q\n%s", want, diagnostic, got)
			}
		})
	}
	syntaxRejects := []struct {
		name, text       string
		kind             int
		marker           string
		shift, spanWidth int
	}{
		{"parameter-order.al", "fn bad(x: U64, T: type) -> U64 {}", 10, "T: type", 0, 1},
		{"statement-line.al", "fn bad() -> U64 {\n let x = 1 return x\n}\n", 11, "return x", 0, 6},
		{"operator-before-line.al", "fn bad() -> U64 {\n return a\n + b\n}\n", 13, "+ b", 0, 1},
		{"operator-after-line.al", "fn bad() -> U64 {\n return a +\n b\n}\n", 13, "\n b", 2, 1},
		{"postfix-line.al", "fn bad() -> U64 {\n return f\n ()\n}\n", 13, "\n ()", 2, 1},
		{"field-line.al", "fn bad() -> U64 {\n return x\n .field\n}\n", 13, ".field", 0, 1},
		{"index-line.al", "fn bad() -> U64 {\n return x\n [index]\n}\n", 13, "[index]", 0, 1},
		{"unary-line.al", "fn bad() -> U64 {\n return !\n x\n}\n", 13, "\n x", 2, 1},
		{"try-line.al", "fn bad() -> U64 {\n return try\n x\n}\n", 13, "\n x", 2, 1},
		{"while-condition-line.al", "fn bad() -> U64 {\n while\n true {}\n}\n", 13, "true", 0, 4},
		{"for-expression-line.al", "fn bad(xs: U64) -> U64 {\n for x in\n xs {}\n}\n", 13, "xs {}", 0, 2},
		{"using-initializer-line.al", "fn bad() -> U64 {\n using x =\n make() with Cleanup\n}\n", 13, "make()", 0, 4},
		{"using-cleanup-line.al", "fn bad() -> U64 {\n using x = make() with\n Cleanup\n}\n", 13, "Cleanup", 0, 7},
		{"match-scrutinee-line.al", "fn bad(x: U64) -> U64 {\n return match\n x {\n  _ => x\n }\n}\n", 13, "x {", 0, 1},
		{"match-binary-scrutinee.al", "fn bad(x: U64, y: U64) -> U64 {\n return match x + y {\n  _ => x\n }\n}\n", 4, "+ y", 0, 1},
		{"match-quoted-wildcard.al", "fn bad(x: U64) -> U64 {\n return match x {\n  \"_\" => x\n }\n}\n", 15, "\"_\"", 0, 3},
		{"match-comma.al", "fn bad(x: U64) -> U64 {\n return match x {\n  _ => x,\n }\n}\n", 16, ",", 0, 1},
		{"match-same-line-arms.al", "fn bad(x: U64) -> U64 {\n return match x { A => 1 B => 2 }\n}\n", 16, "B =>", 0, 1},
		{"match-eof.al", "fn bad(x: U64) -> U64 {\n return match x {", 15, "", 0, 0},
		{"match-variant-eof.al", "fn bad(x: U64) -> U64 {\n return match x { Some", 4, "", 0, 0},
		{"match-binding-eof.al", "fn bad(x: U64) -> U64 {\n return match x { Some(", 3, "", 0, 0},
		{"match-body-eof.al", "fn bad(x: U64) -> U64 {\n return match x { Some =>", 12, "", 0, 0},
		{"unsafe-language.al", "fn bad() -> U64 {\n return unsafe rust { f() }\n}\n", 17, "rust", 0, 4},
		{"unsafe-not-call.al", "fn bad(x: U64) -> U64 {\n return unsafe c { x }\n}\n", 30, "unsafe", 0, 6},
		{"unsafe-binary-root.al", "fn bad() -> U64 {\n return unsafe c { f() + g() }\n}\n", 30, "unsafe", 0, 6},
		{"unsafe-extra-expression.al", "fn bad(x: U64) -> U64 {\n return unsafe c { f() x }\n}\n", 18, "x }", 0, 1},
		{"unsafe-not-call-eof.al", "fn bad(x: U64) -> U64 {\n return unsafe c { x", 30, "unsafe", 0, 6},
		{"unsafe-call-eof.al", "fn bad(x: U64) -> U64 {\n return unsafe c { f()", 18, "", 0, 0},
		{"for-missing-in.al", "fn bad(xs: U64) -> U64 {\n for x xs {}\n}\n", 4, "xs {}", 0, 2},
		// `using x = expr` without a `with` clause is the M7.5 public form, so
		// the trailing token now fails later as a statement, not at `with`.
		{"using-missing-with.al", "fn bad() -> U64 {\n using x = make() Cleanup\n}\n", 11, "Cleanup", 0, 7},
		{"if-missing-block.al", "fn bad() -> U64 {\n if true", 4, "", 0, 0},
		{"call-empty-eof.al", "fn bad() -> U64 {\n return f(", 12, "", 0, 0},
		{"call-value-eof.al", "fn bad() -> U64 {\n return f(x", 4, "", 0, 0},
		{"call-named-eof.al", "fn bad() -> U64 {\n return f(label:", 12, "", 0, 0},
		{"call-keyword-label.al", "fn bad() -> U64 {\n return f(return: x)\n}\n", 12, "return: x", 0, 6},
		{"field-eof.al", "fn bad() -> U64 {\n return x.", 3, "", 0, 0},
		{"index-empty-eof.al", "fn bad() -> U64 {\n return x[", 12, "", 0, 0},
		{"index-value-eof.al", "fn bad() -> U64 {\n return x[0", 4, "", 0, 0},
		{"group-eof.al", "fn bad() -> U64 {\n return (x", 4, "", 0, 0},
		{"named-value.al", "fn bad() -> U64 {\n return f(label:)\n}\n", 12, ":)", 1, 1},
		{"result-type.al", "fn bad() -> {}", 5, "{}", 0, 1},
		{"body-eof.al", "fn bad() -> U64", 4, "", 0, 0},
		{"block-eof.al", "fn bad() -> U64 {\n return 0\n", 4, "", 0, 0},
		{"return-eof.al", "fn bad() -> U64 { return", 12, "", 0, 0},
		{"return-line-eof.al", "fn bad() -> U64 {\n return\n", 4, "", 0, 0},
		{"assign-call.al", "fn bad() -> U64 {\n f() = value\n}\n", 14, "f() =", 0, 1},
		// Field and index chains are assignment targets: `x.field.other`,
		// `x.field[index]`, and `x[index][other]` all parse as places, so they
		// reach the checker instead of failing here.
		{"assign-group.al", "fn bad() -> U64 {\n (x + y) = value\n}\n", 14, "(x + y)", 0, 1},
		{"nesting-group-depth.al", "fn bad() -> U64 { return " + strings.Repeat("(", 65) + "X" + strings.Repeat(")", 65) + " }", 19, "X", 0, 1},
		{"nesting-chain-depth.al", "fn bad() -> U64 { return 1" + strings.Repeat(" + 1", 64) + " + X }", 19, "+ X", 0, 1},
	}
	for _, tc := range syntaxRejects {
		t.Run(tc.name, func(t *testing.T) {
			start := len(tc.text)
			if tc.marker != "" {
				start = strings.Index(tc.text, tc.marker)
				if start < 0 {
					t.Fatalf("marker %q not found", tc.marker)
				}
				start += tc.shift
			}
			got := runAlderParser(t, exe, map[string]string{tc.name: tc.text}, []string{tc.name}, true)
			want := fmt.Sprintf("D SYN0001 %d %s %d %d", tc.kind, tc.name, start, start+tc.spanWidth)
			if diagnostic := parserDiagnosticLine(t, got); diagnostic != want {
				t.Fatalf("diagnostic mismatch: want %q, got %q\n%s", want, diagnostic, got)
			}
		})
	}
	canonicalBad := map[string]string{
		"z-bad.al": "fn bad() -> U64 { if true {}\n}",
		"a-bad.al": "type {",
	}
	for _, order := range [][]string{{"z-bad.al", "a-bad.al"}, {"a-bad.al", "z-bad.al"}} {
		got := runAlderParser(t, exe, canonicalBad, order, true)
		if diagnostic := parserDiagnosticLine(t, got); diagnostic != "D SYN0001 3 a-bad.al 5 6" {
			t.Fatalf("canonical first parser diagnostic mismatch for %v: %q\n%s", order, diagnostic, got)
		}
	}
	mixedFailures := []struct {
		name  string
		files map[string]string
		want  string
	}{
		{
			name:  "earlier parser failure",
			files: map[string]string{"a-bad.al": "type {", "z-bad.al": ";"},
			want:  "D SYN0001 3 a-bad.al 5 6",
		},
		{
			name:  "earlier lexer failure",
			files: map[string]string{"a-bad.al": ";", "z-bad.al": "type {"},
			want:  "D LEX0001 1 a-bad.al 0 1",
		},
	}
	for _, tc := range mixedFailures {
		t.Run(tc.name, func(t *testing.T) {
			for _, order := range [][]string{{"z-bad.al", "a-bad.al"}, {"a-bad.al", "z-bad.al"}} {
				got := runAlderParser(t, exe, tc.files, order, true)
				if diagnostic := parserDiagnosticLine(t, got); diagnostic != tc.want {
					t.Fatalf("mixed-phase first diagnostic mismatch for %v: want %q, got %q\n%s", order, tc.want, diagnostic, got)
				}
			}
		})
	}
	lex := runAlderParser(t, exe, map[string]string{"semi.al": ";"}, []string{"semi.al"}, true)
	wantLex := "ALDER-TOKEN-MANIFEST 1\nS 0 semi.al 1\nD LEX0001 1 semi.al 0 1\nEND\n"
	if lex != wantLex {
		t.Fatalf("lexical rejection manifest mismatch\nwant:\n%s\ngot:\n%s", wantLex, lex)
	}
}

func runAlderParser(t *testing.T, exe string, files map[string]string, order []string, wantFailure bool) string {
	t.Helper()
	dir := t.TempDir()
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := conformanceCommand(exe, order...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if wantFailure {
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			t.Fatalf("diagnostic run: err=%v stderr=%q", err, stderr.String())
		}
	} else if err != nil {
		t.Fatalf("parser run: %v stderr=%q", err, stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
	return stdout.String()
}

func parserDiagnosticLine(t *testing.T, manifest string) string {
	t.Helper()
	var diagnostic string
	for _, line := range strings.Split(strings.TrimSuffix(manifest, "\n"), "\n") {
		if strings.HasPrefix(line, "D ") {
			if diagnostic != "" {
				t.Fatalf("manifest contains multiple diagnostics:\n%s", manifest)
			}
			diagnostic = line
		}
	}
	if diagnostic == "" || !strings.HasSuffix(manifest, diagnostic+"\nEND\n") {
		t.Fatalf("manifest does not end with one diagnostic and END:\n%s", manifest)
	}
	return diagnostic
}

type parserManifestNode struct {
	kind                           int
	path                           string
	start, end, nameStart, nameEnd int
	token, tokenSource             int
	tokenStart, tokenEnd           int
	children                       int
}

type parserManifestLink struct {
	node int
	next int
}

type parserManifest struct {
	sourceTexts map[string]string
	roots       []int
	nodes       []parserManifestNode
	links       []parserManifestLink
}

func validateParserManifest(t *testing.T, manifest string, sourceTexts map[string]string) parserManifest {
	t.Helper()
	sourceLengths := make(map[string]int)
	var sourcePaths []string
	var roots []int
	var nodes []parserManifestNode
	var links []parserManifestLink
	tokenCount := -1
	for _, line := range strings.Split(strings.TrimSuffix(manifest, "\n"), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		switch fields[0] {
		case "T":
			if len(fields) != 2 || tokenCount != -1 {
				t.Fatalf("invalid token count record %q", line)
			}
			tokenCount = manifestInt(t, fields[1])
		case "S":
			if len(fields) != 4 || manifestInt(t, fields[1]) != len(sourcePaths) {
				t.Fatalf("invalid source record %q", line)
			}
			if _, exists := sourceLengths[fields[2]]; exists {
				t.Fatalf("duplicate source path in record %q", line)
			}
			text, exists := sourceTexts[fields[2]]
			if !exists || len(text) != manifestInt(t, fields[3]) {
				t.Fatalf("source record does not match input %q", line)
			}
			sourcePaths = append(sourcePaths, fields[2])
			sourceLengths[fields[2]] = len(text)
		case "R":
			if len(fields) != 3 || manifestInt(t, fields[1]) != len(roots) {
				t.Fatalf("invalid root record %q", line)
			}
			roots = append(roots, manifestInt(t, fields[2]))
		case "N":
			if len(fields) != 13 || manifestInt(t, fields[1]) != len(nodes)+1 {
				t.Fatalf("invalid node record %q", line)
			}
			nodes = append(nodes, parserManifestNode{
				kind:        manifestInt(t, fields[2]),
				token:       manifestInt(t, fields[3]),
				tokenSource: manifestInt(t, fields[4]),
				tokenStart:  manifestInt(t, fields[5]),
				tokenEnd:    manifestInt(t, fields[6]),
				path:        fields[7],
				start:       manifestInt(t, fields[8]),
				end:         manifestInt(t, fields[9]),
				nameStart:   manifestInt(t, fields[10]),
				nameEnd:     manifestInt(t, fields[11]),
				children:    manifestInt(t, fields[12]),
			})
		case "L":
			if len(fields) != 4 || manifestInt(t, fields[1]) != len(links)+1 {
				t.Fatalf("invalid link record %q", line)
			}
			links = append(links, parserManifestLink{node: manifestInt(t, fields[2]), next: manifestInt(t, fields[3])})
		}
	}
	for id, node := range nodes {
		if tokenCount < 0 || node.token < 1 || node.token > tokenCount {
			t.Fatalf("node %d has invalid token ID %d (count %d)", id+1, node.token, tokenCount)
		}
		length, ok := sourceLengths[node.path]
		if !ok || node.start < 0 || node.start > node.end || node.end > length {
			t.Fatalf("node %d has invalid source span %+v", id+1, node)
		}
		if node.tokenSource < 0 || node.tokenSource >= len(sourcePaths) || sourcePaths[node.tokenSource] != node.path || node.tokenStart < node.start || node.tokenStart >= node.tokenEnd || node.tokenEnd > node.end {
			t.Fatalf("node %d has invalid token source/span %+v", id+1, node)
		}
		if (node.nameStart != 0 || node.nameEnd != 0) && (node.nameStart < node.start || node.nameStart > node.nameEnd || node.nameEnd > node.end) {
			t.Fatalf("node %d has invalid name span %+v", id+1, node)
		}
		if node.tokenStart < node.start || node.tokenStart > node.tokenEnd || node.tokenEnd > node.end {
			t.Fatalf("node %d has semantic token outside its span: %+v", id+1, node)
		}
		tokenText := sourceTexts[node.path][node.tokenStart:node.tokenEnd]
		if !validParserNodeToken(node, tokenText) {
			t.Fatalf("node %d has invalid semantic token %q: %+v", id+1, tokenText, node)
		}
		if node.children < 0 || node.children > len(links) {
			t.Fatalf("node %d has invalid child head %d", id+1, node.children)
		}
	}
	ownedLinks := make(map[int]int)
	reachableNodes := make(map[int]bool)
	var visitNode func(int)
	visitNode = func(nodeID int) {
		if nodeID < 1 || nodeID > len(nodes) {
			t.Fatalf("invalid node ID %d", nodeID)
		}
		if reachableNodes[nodeID] {
			return
		}
		reachableNodes[nodeID] = true
		for linkID := nodes[nodeID-1].children; linkID != 0; {
			if linkID < 1 || linkID > len(links) {
				t.Fatalf("node %d references invalid link %d", nodeID, linkID)
			}
			if owner, exists := ownedLinks[linkID]; exists {
				t.Fatalf("link %d is shared by nodes %d and %d", linkID, owner, nodeID)
			}
			ownedLinks[linkID] = nodeID
			link := links[linkID-1]
			if link.next >= linkID {
				t.Fatalf("link %d does not point backward: %+v", linkID, link)
			}
			visitNode(link.node)
			linkID = link.next
		}
	}
	incoming := make(map[int]int)
	for _, link := range links {
		incoming[link.node]++
	}
	rootSet := make(map[int]bool)
	lastPath := ""
	lastStart := -1
	for _, root := range roots {
		if root < 1 || root > len(nodes) {
			t.Fatalf("invalid root node ID %d", root)
		}
		if rootSet[root] || incoming[root] != 0 {
			t.Fatalf("root node %d is duplicated or has a parent", root)
		}
		rootSet[root] = true
		node := nodes[root-1]
		if node.path < lastPath || node.path == lastPath && node.start <= lastStart {
			t.Fatalf("roots are not in canonical source order: %d after %s:%d", root, lastPath, lastStart)
		}
		lastPath, lastStart = node.path, node.start
		visitNode(root)
	}
	for nodeID := range nodes {
		id := nodeID + 1
		if !rootSet[id] && incoming[id] != 1 {
			t.Fatalf("non-root node %d has %d parents", id, incoming[id])
		}
	}
	if len(reachableNodes) != len(nodes) || len(ownedLinks) != len(links) {
		var missingNodes, missingLinks []int
		for id := 1; id <= len(nodes); id++ {
			if !reachableNodes[id] {
				missingNodes = append(missingNodes, id)
			}
		}
		for id := 1; id <= len(links); id++ {
			if ownedLinks[id] == 0 {
				missingLinks = append(missingLinks, id)
			}
		}
		t.Fatalf("unreachable parser arena records: nodes %d/%d %v links %d/%d %v", len(reachableNodes), len(nodes), missingNodes, len(ownedLinks), len(links), missingLinks)
	}
	return parserManifest{sourceTexts: sourceTexts, roots: roots, nodes: nodes, links: links}
}

func validParserNodeToken(node parserManifestNode, tokenText string) bool {
	nameToken := node.tokenStart == node.nameStart && node.tokenEnd == node.nameEnd
	switch node.kind {
	case 1:
		return node.tokenStart == node.start && tokenText == "import"
	case 2:
		return node.tokenStart == node.start && tokenText == "type"
	case 3:
		return node.tokenStart == node.start && tokenText == "enum"
	case 4, 6, 7, 8, 9, 11, 13, 24, 28, 47, 48:
		return nameToken
	case 5, 30:
		return tokenText == "["
	case 10, 12:
		return node.tokenStart == node.start && tokenText == "fn"
	case 14:
		return node.tokenStart == node.start && tokenText == "{"
	case 15:
		return node.tokenStart == node.start && tokenText == "let"
	case 16:
		return node.tokenStart == node.start && tokenText == "var"
	case 17:
		return nameToken && tokenText == "="
	case 18:
		return node.tokenStart == node.start && tokenText == "return"
	case 19, 20, 21, 22:
		return node.tokenStart == node.start
	case 23:
		return node.tokenStart == node.start && (tokenText == "true" || tokenText == "false")
	case 25:
		return nameToken && (tokenText == "-" || tokenText == "!")
	case 26:
		return nameToken && binaryOperator(tokenText)
	case 27:
		return tokenText == "("
	case 29:
		return tokenText == "."
	case 31:
		return node.tokenStart == node.start && nameToken && tokenText == "try"
	case 32:
		return node.tokenStart == node.start && tokenText == "if" && node.nameStart == 0 && node.nameEnd == 0
	case 33:
		return node.tokenStart == node.start && tokenText == "while" && node.nameStart == 0 && node.nameEnd == 0
	case 34:
		return node.tokenStart == node.start && tokenText == "for" && node.nameStart > node.tokenEnd
	case 35:
		return node.tokenStart == node.start && tokenText == "using" && node.nameStart > node.tokenEnd
	case 36:
		return node.tokenStart == node.start && tokenText == "unsafe" && node.nameStart == 0 && node.nameEnd == 0
	case 37:
		return node.tokenStart == node.start && tokenText == "match" && node.nameStart == 0 && node.nameEnd == 0
	case 38:
		return node.tokenStart == node.start && ((tokenText == "_" && node.nameStart == 0 && node.nameEnd == 0) || nameToken)
	case 39:
		return nameToken
	case 40:
		return node.tokenStart == node.start && tokenText == "module" && node.nameStart > node.tokenEnd
	case 41, 42:
		return node.tokenStart == node.start && tokenText == "import" && node.nameStart > node.tokenEnd
	case 43, 44:
		return nameToken
	case 45:
		return node.tokenStart == node.start && tokenText == "pub" && node.nameStart > node.tokenEnd
	case 46:
		return node.tokenStart == node.nameStart && node.tokenEnd <= node.nameEnd
	default:
		return false
	}
}

func binaryOperator(text string) bool {
	switch text {
	case "||", "&&", "==", "!=", "<", "<=", ">", ">=", "<<", ">>", "+", "-", "*", "/", "%":
		return true
	default:
		return false
	}
}

func (m parserManifest) childrenInSourceOrder(t *testing.T, nodeID int) []int {
	t.Helper()
	if nodeID < 1 || nodeID > len(m.nodes) {
		t.Fatalf("invalid node ID %d", nodeID)
	}
	var children []int
	for linkID := m.nodes[nodeID-1].children; linkID != 0; linkID = m.links[linkID-1].next {
		children = append(children, m.links[linkID-1].node)
	}
	for left, right := 0, len(children)-1; left < right; left, right = left+1, right-1 {
		children[left], children[right] = children[right], children[left]
	}
	return children
}

func (m parserManifest) tokenText(t *testing.T, nodeID int) string {
	t.Helper()
	node := m.nodes[nodeID-1]
	return m.sourceTexts[node.path][node.tokenStart:node.tokenEnd]
}

func (m parserManifest) name(t *testing.T, nodeID int) string {
	t.Helper()
	node := m.nodes[nodeID-1]
	if node.nameStart == 0 && node.nameEnd == 0 {
		return ""
	}
	return m.sourceTexts[node.path][node.nameStart:node.nameEnd]
}

func (m parserManifest) spanText(t *testing.T, nodeID int) string {
	t.Helper()
	node := m.nodes[nodeID-1]
	return m.sourceTexts[node.path][node.start:node.end]
}

func (m parserManifest) rootNamed(t *testing.T, name string) int {
	t.Helper()
	for _, root := range m.roots {
		if m.name(t, root) == name {
			return root
		}
	}
	t.Fatalf("no root named %q", name)
	return 0
}

func assertNodeKinds(t *testing.T, tree parserManifest, ids []int, want ...int) {
	t.Helper()
	if len(ids) != len(want) {
		t.Fatalf("child count mismatch: got %v, want kinds %v", ids, want)
	}
	for i, id := range ids {
		if tree.nodes[id-1].kind != want[i] {
			t.Fatalf("node %d kind = %d, want %d in %v", id, tree.nodes[id-1].kind, want[i], ids)
		}
	}
}

func bindingValue(t *testing.T, tree parserManifest, blockID int, name string) int {
	t.Helper()
	for _, statement := range tree.childrenInSourceOrder(t, blockID) {
		node := tree.nodes[statement-1]
		if (node.kind == 15 || node.kind == 16) && tree.name(t, statement) == name {
			children := tree.childrenInSourceOrder(t, statement)
			return children[len(children)-1]
		}
	}
	t.Fatalf("no binding named %q", name)
	return 0
}

func assertFunctionParserTree(t *testing.T, tree parserManifest) {
	t.Helper()
	if len(tree.roots) != 5 {
		t.Fatalf("function manifest roots = %d, want 5", len(tree.roots))
	}
	for i, name := range []string{"empty", "core", "assoc", "postfix", "named"} {
		if tree.name(t, tree.roots[i]) != name {
			t.Fatalf("root %d name = %q, want %q", i, tree.name(t, tree.roots[i]), name)
		}
	}

	emptyChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "empty"))
	assertNodeKinds(t, tree, emptyChildren, 4, 14)
	emptyStatements := tree.childrenInSourceOrder(t, emptyChildren[1])
	assertNodeKinds(t, tree, emptyStatements, 18)
	if len(tree.childrenInSourceOrder(t, emptyStatements[0])) != 0 {
		t.Fatal("line-terminated return unexpectedly has a value")
	}

	coreChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "core"))
	assertNodeKinds(t, tree, coreChildren, 7, 47, 48, 4, 14)
	if tree.name(t, coreChildren[0]) != "T" || tree.name(t, coreChildren[1]) != "x" {
		t.Fatalf("function parameter order changed: %q, %q", tree.name(t, coreChildren[0]), tree.name(t, coreChildren[1]))
	}
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, coreChildren[1]), 4)
	if tree.name(t, coreChildren[2]) != "owner" {
		t.Fatalf("take parameter name = %q, want owner", tree.name(t, coreChildren[2]))
	}
	coreStatements := tree.childrenInSourceOrder(t, coreChildren[4])
	assertNodeKinds(t, tree, coreStatements, 15, 16, 15, 15, 15, 17, 17, 17, 17, 14, 18)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, coreStatements[0]), 4, 26)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, coreStatements[1]), 21)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, coreStatements[2]), 22)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, coreStatements[3]), 27)
	callWithNamed := bindingValue(t, tree, coreChildren[4], "d")
	callChildren := tree.childrenInSourceOrder(t, callWithNamed)
	assertNodeKinds(t, tree, callChildren, 24, 28, 24)
	if tree.name(t, callChildren[1]) != "T" {
		t.Fatalf("named argument label = %q, want T", tree.name(t, callChildren[1]))
	}
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, callChildren[1]), 24)
	for i, statement := range coreStatements[5:9] {
		assignmentChildren := tree.childrenInSourceOrder(t, statement)
		assertNodeKinds(t, tree, assignmentChildren, []int{24, 29, 30, 29}[i], tree.nodes[assignmentChildren[1]-1].kind)
		if tree.tokenText(t, statement) != "=" {
			t.Fatalf("assignment token = %q", tree.tokenText(t, statement))
		}
	}
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, coreStatements[9]), 18)
	if len(tree.childrenInSourceOrder(t, coreStatements[10])) != 0 {
		t.Fatal("block-closing return unexpectedly has a value")
	}

	assocChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "assoc"))
	assocBlock := assocChildren[len(assocChildren)-1]
	sub := bindingValue(t, tree, assocBlock, "sub")
	if tree.tokenText(t, sub) != "-" {
		t.Fatalf("subtraction root token = %q", tree.tokenText(t, sub))
	}
	subChildren := tree.childrenInSourceOrder(t, sub)
	assertNodeKinds(t, tree, subChildren, 26, 24)
	if tree.tokenText(t, subChildren[0]) != "-" {
		t.Fatal("subtraction is not left-associative")
	}
	mixed := bindingValue(t, tree, assocBlock, "mixed")
	if tree.tokenText(t, mixed) != "+" {
		t.Fatalf("mixed precedence root = %q, want +", tree.tokenText(t, mixed))
	}
	mixedChildren := tree.childrenInSourceOrder(t, mixed)
	assertNodeKinds(t, tree, mixedChildren, 24, 26)
	if tree.tokenText(t, mixedChildren[1]) != "*" {
		t.Fatal("multiplication did not bind tighter than addition")
	}
	logic := bindingValue(t, tree, assocBlock, "logic")
	logicChildren := tree.childrenInSourceOrder(t, logic)
	if tree.tokenText(t, logic) != "||" || tree.tokenText(t, logicChildren[1]) != "&&" {
		t.Fatal("logical precedence changed")
	}
	product := bindingValue(t, tree, assocBlock, "product")
	productChildren := tree.childrenInSourceOrder(t, product)
	if tree.tokenText(t, product) != "%" || tree.tokenText(t, productChildren[0]) != "*" {
		t.Fatal("multiplicative operators are not left-associative")
	}
	productLeft := tree.childrenInSourceOrder(t, productChildren[0])
	if tree.tokenText(t, productLeft[0]) != "/" {
		t.Fatal("division did not remain on the left of multiplication")
	}

	postfixChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "postfix"))
	postfixBlock := postfixChildren[len(postfixChildren)-1]
	postfixReturn := tree.childrenInSourceOrder(t, postfixBlock)[0]
	index := tree.childrenInSourceOrder(t, postfixReturn)[0]
	assertNodeKinds(t, tree, []int{index}, 30)
	indexChildren := tree.childrenInSourceOrder(t, index)
	assertNodeKinds(t, tree, indexChildren, 29, 24)
	fieldChildren := tree.childrenInSourceOrder(t, indexChildren[0])
	assertNodeKinds(t, tree, fieldChildren, 27)
	outerCallChildren := tree.childrenInSourceOrder(t, fieldChildren[0])
	assertNodeKinds(t, tree, outerCallChildren, 27, 24)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, outerCallChildren[0]), 24)
	if tree.tokenText(t, index) != "[" || tree.tokenText(t, indexChildren[0]) != "." || tree.name(t, indexChildren[0]) != "field" {
		t.Fatal("postfix token/name identity changed")
	}

	namedChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "named"))
	namedStatements := tree.childrenInSourceOrder(t, namedChildren[len(namedChildren)-1])
	assertNodeKinds(t, tree, namedStatements, 19, 18)
	groupedStatement := tree.nodes[namedStatements[0]-1]
	if tree.tokenText(t, namedStatements[0]) != "(" || groupedStatement.tokenStart != groupedStatement.start || groupedStatement.end <= tree.nodes[tree.childrenInSourceOrder(t, namedStatements[0])[0]-1].end {
		t.Fatal("grouped expression statement does not retain its consumed delimiters")
	}
	namedCall := tree.childrenInSourceOrder(t, namedStatements[1])[0]
	namedCallChildren := tree.childrenInSourceOrder(t, namedCall)
	assertNodeKinds(t, tree, namedCallChildren, 24, 24, 28)
	if tree.name(t, namedCallChildren[2]) != "label" {
		t.Fatalf("named call label = %q", tree.name(t, namedCallChildren[2]))
	}
}

func assertControlParserTree(t *testing.T, tree parserManifest) {
	t.Helper()
	root := tree.rootNamed(t, "flow")
	rootChildren := tree.childrenInSourceOrder(t, root)
	block := rootChildren[len(rootChildren)-1]
	statements := tree.childrenInSourceOrder(t, block)
	assertNodeKinds(t, tree, statements, 32, 33, 34, 35, 15, 15, 18)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, statements[0]), 23, 14, 14)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, statements[1]), 23, 14)
	if tree.name(t, statements[2]) != "item" {
		t.Fatalf("for binding = %q, want item", tree.name(t, statements[2]))
	}
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, statements[2]), 24, 14)
	if tree.name(t, statements[3]) != "resource" {
		t.Fatalf("using binding = %q, want resource", tree.name(t, statements[3]))
	}
	usingChildren := tree.childrenInSourceOrder(t, statements[3])
	assertNodeKinds(t, tree, usingChildren, 27, 24)
	if tree.name(t, usingChildren[1]) != "CleanupFn" {
		t.Fatalf("using cleanup = %q, want CleanupFn", tree.name(t, usingChildren[1]))
	}
	matchNode := tree.childrenInSourceOrder(t, statements[4])[0]
	matchChildren := tree.childrenInSourceOrder(t, matchNode)
	assertNodeKinds(t, tree, matchChildren, 24, 38, 38, 38)
	if tree.name(t, matchChildren[1]) != "Some" || tree.name(t, matchChildren[2]) != "None" || tree.name(t, matchChildren[3]) != "" {
		t.Fatal("match arm variant/wildcard shape changed")
	}
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, matchChildren[1]), 39, 24)
	groupedArm := tree.nodes[matchChildren[3]-1]
	groupedBody := tree.nodes[tree.childrenInSourceOrder(t, matchChildren[3])[0]-1]
	if groupedArm.end <= groupedBody.end {
		t.Fatal("grouped match-arm span does not retain its consumed closing delimiter")
	}
	unsafeNode := tree.childrenInSourceOrder(t, statements[5])[0]
	assertNodeKinds(t, tree, []int{unsafeNode}, 36)
	assertNodeKinds(t, tree, tree.childrenInSourceOrder(t, unsafeNode), 27)

	nestedChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "nested"))
	nestedBlock := nestedChildren[len(nestedChildren)-1]
	nestedReturn := tree.childrenInSourceOrder(t, nestedBlock)[0]
	outerMatch := tree.childrenInSourceOrder(t, nestedReturn)[0]
	outerChildren := tree.childrenInSourceOrder(t, outerMatch)
	assertNodeKinds(t, tree, outerChildren, 26, 38, 38)
	firstArmChildren := tree.childrenInSourceOrder(t, outerChildren[1])
	assertNodeKinds(t, tree, firstArmChildren, 39, 37)
	innerChildren := tree.childrenInSourceOrder(t, firstArmChildren[1])
	assertNodeKinds(t, tree, innerChildren, 24, 38)
	innerBody := tree.childrenInSourceOrder(t, innerChildren[1])[0]
	assertNodeKinds(t, tree, []int{innerBody}, 26)
	if tree.tokenText(t, outerChildren[0]) != "+" || tree.tokenText(t, innerBody) != "+" {
		t.Fatal("grouped scrutinee or multiline nested match body lost binary shape")
	}

	groupedChildren := tree.childrenInSourceOrder(t, tree.rootNamed(t, "grouped_arms"))
	groupedReturn := tree.childrenInSourceOrder(t, groupedChildren[len(groupedChildren)-1])[0]
	groupedMatch := tree.childrenInSourceOrder(t, groupedReturn)[0]
	groupedMatchChildren := tree.childrenInSourceOrder(t, groupedMatch)
	wantArms := []string{"A => (x)", "B => ((x))", "C => (f)()", "D => (x).field", "E => (x)[i]", "F => (f())"}
	if len(groupedMatchChildren) != len(wantArms)+1 {
		t.Fatalf("grouped match children = %d, want %d", len(groupedMatchChildren), len(wantArms)+1)
	}
	for i, want := range wantArms {
		arm := groupedMatchChildren[i+1]
		if tree.nodes[arm-1].kind != 38 || tree.spanText(t, arm) != want {
			t.Fatalf("grouped arm %d span = %q, want %q", i, tree.spanText(t, arm), want)
		}
	}
}

func manifestInt(t *testing.T, text string) int {
	t.Helper()
	value, err := strconv.Atoi(text)
	if err != nil {
		t.Fatalf("invalid manifest integer %q: %v", text, err)
	}
	return value
}
