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

	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

const parserWrapper = `
fn parser_storage_error() -> I32 {
    let text = "alder compiler: storage failure\n"
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
fn parser_parse(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec), roots: __s0_Buffer(U64), diagnostics: __s0_Buffer(ParseDiagRec)) -> I32 {
    return match parse_sources(d, state, ParseStore(nodes: nodes, links: links, roots: roots, diagnostics: diagnostics)) {
        Err(error) => parser_storage_error()

        Ok(result) => parser_finish(result)
    }
}
fn parser_init_diags(d: Domain, state: State, nodes: __s0_Buffer(SyntaxRec), links: __s0_Buffer(SyntaxLinkRec), roots: __s0_Buffer(U64)) -> I32 { return match __s0_buffer_new(ParseDiagRec, d) {
        Err(error) => parser_storage_error()
        Ok(b) => parser_parse(d, state, nodes, links, roots, b) } }
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
R 0 3
R 1 6
R 2 9
R 3 12
R 4 15
R 5 18
R 6 23
R 7 28
R 8 36
N 1 4 a.al 12 15 12 15 0
N 2 8 a.al 9 15 9 10 1
N 3 2 a.al 0 17 5 6 2
N 4 4 a.al 30 33 30 33 0
N 5 8 a.al 27 33 27 28 3
N 6 2 a.al 18 35 23 24 4
N 7 4 a.al 48 51 48 51 0
N 8 8 a.al 45 51 45 46 5
N 9 2 a.al 36 53 41 42 6
N 10 4 a.al 66 69 66 69 0
N 11 8 a.al 63 69 63 64 7
N 12 2 a.al 54 71 59 60 8
N 13 4 a.al 84 87 84 87 0
N 14 8 a.al 81 87 81 82 9
N 15 2 a.al 72 89 77 78 10
N 16 4 a.al 102 105 102 105 0
N 17 8 a.al 99 105 99 100 11
N 18 2 a.al 90 107 95 96 12
N 19 4 b.al 19 21 19 21 0
N 20 5 b.al 18 22 0 0 13
N 21 4 b.al 28 31 28 31 0
N 22 10 b.al 15 31 0 0 15
N 23 1 b.al 0 31 9 13 16
N 24 7 b.al 48 49 48 49 0
N 25 4 b.al 70 71 70 71 0
N 26 5 b.al 69 72 0 0 18
N 27 8 b.al 62 72 62 67 19
N 28 2 b.al 39 75 44 47 20
N 29 7 b.al 89 90 89 90 0
N 30 11 b.al 108 113 108 113 0
N 31 4 b.al 120 121 120 121 0
N 32 5 b.al 119 122 0 0 23
N 33 6 b.al 115 124 115 118 24
N 34 9 b.al 103 125 103 107 25
N 35 9 b.al 128 132 128 132 0
N 36 3 b.al 77 135 82 88 27
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
		if name == "main.al" {
			continue
		}
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
	arts := map[EmitKind]string{}
	for _, emit := range []EmitKind{EmitMIR, EmitC} {
		first, firstErr := Compile(Request{Sources: sources, Emit: emit})
		second, secondErr := Compile(Request{Sources: rev, Emit: emit})
		if firstErr != nil || secondErr != nil || first.Artifact == nil || second.Artifact == nil || len(first.Diagnostics) != 0 || len(second.Diagnostics) != 0 {
			t.Fatalf("compile parser %s: first=%+v/%v second=%+v/%v", emit, first, firstErr, second, secondErr)
		}
		if first.Artifact.Text != second.Artifact.Text {
			t.Fatalf("parser %s changed with compiler source request order", emit)
		}
		arts[emit] = first.Artifact.Text
	}
	module, err := mir.Parse(arts[EmitMIR])
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
	for _, leaked := range []string{root, filepath.ToSlash(root), strings.ReplaceAll(root, `\`, `\\`)} {
		if leaked != "" && strings.Contains(arts[EmitC], leaked) {
			t.Fatalf("generated C contains checkout path %q", leaked)
		}
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "parser.c")
	exe := filepath.Join(dir, "parser.exe")
	if err := os.WriteFile(cfile, []byte(arts[EmitC]), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cfile, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
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
	validateParserManifest(t, first)
	if again := runAlderParser(t, exe, files, []string{"b.al", "a.al", "z-empty.al"}, false); again != first {
		t.Fatal("repeat parser process output changed")
	}
	rejects := []struct {
		name, text       string
		kind, start, end int
	}{
		{"fn.al", "fn bad() -> U64 {}", 2, 0, 2},
		{"ident.al", "type {", 3, 5, 6},
		{"punct.al", "type A x", 4, 7, 8},
		{"type.al", "type A { x: }", 5, 12, 13},
		{"label.al", "enum E { V(: U64)\n}", 6, 11, 12},
		{"top.al", "type A {} type B {}", 7, 10, 14},
		{"field.al", "type A { x: U64 y: U64\n}", 8, 16, 17},
		{"variant.al", "enum E { A B\n}", 9, 11, 12},
		{"eof.al", "type A {", 4, 8, 8},
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
	canonicalBad := map[string]string{
		"z-bad.al": "fn bad() -> U64 {}",
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
	cmd := exec.Command(exe, order...)
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
	path                           string
	start, end, nameStart, nameEnd int
	children                       int
}

type parserManifestLink struct {
	node int
	next int
}

func validateParserManifest(t *testing.T, manifest string) {
	t.Helper()
	sourceLengths := make(map[string]int)
	var roots []int
	var nodes []parserManifestNode
	var links []parserManifestLink
	for _, line := range strings.Split(strings.TrimSuffix(manifest, "\n"), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		switch fields[0] {
		case "S":
			if len(fields) != 4 || manifestInt(t, fields[1]) != len(sourceLengths) {
				t.Fatalf("invalid source record %q", line)
			}
			sourceLengths[fields[2]] = manifestInt(t, fields[3])
		case "R":
			if len(fields) != 3 || manifestInt(t, fields[1]) != len(roots) {
				t.Fatalf("invalid root record %q", line)
			}
			roots = append(roots, manifestInt(t, fields[2]))
		case "N":
			if len(fields) != 9 || manifestInt(t, fields[1]) != len(nodes)+1 {
				t.Fatalf("invalid node record %q", line)
			}
			nodes = append(nodes, parserManifestNode{
				path:      fields[3],
				start:     manifestInt(t, fields[4]),
				end:       manifestInt(t, fields[5]),
				nameStart: manifestInt(t, fields[6]),
				nameEnd:   manifestInt(t, fields[7]),
				children:  manifestInt(t, fields[8]),
			})
		case "L":
			if len(fields) != 4 || manifestInt(t, fields[1]) != len(links)+1 {
				t.Fatalf("invalid link record %q", line)
			}
			links = append(links, parserManifestLink{node: manifestInt(t, fields[2]), next: manifestInt(t, fields[3])})
		}
	}
	for id, node := range nodes {
		length, ok := sourceLengths[node.path]
		if !ok || node.start < 0 || node.start > node.end || node.end > length {
			t.Fatalf("node %d has invalid source span %+v", id+1, node)
		}
		if (node.nameStart != 0 || node.nameEnd != 0) && (node.nameStart < node.start || node.nameStart > node.nameEnd || node.nameEnd > node.end) {
			t.Fatalf("node %d has invalid name span %+v", id+1, node)
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
	lastPath := ""
	lastStart := -1
	for _, root := range roots {
		if root < 1 || root > len(nodes) {
			t.Fatalf("invalid root node ID %d", root)
		}
		node := nodes[root-1]
		if node.path < lastPath || node.path == lastPath && node.start <= lastStart {
			t.Fatalf("roots are not in canonical source order: %d after %s:%d", root, lastPath, lastStart)
		}
		lastPath, lastStart = node.path, node.start
		visitNode(root)
	}
	if len(reachableNodes) != len(nodes) || len(ownedLinks) != len(links) {
		t.Fatalf("unreachable parser arena records: nodes %d/%d links %d/%d", len(reachableNodes), len(nodes), len(ownedLinks), len(links))
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
