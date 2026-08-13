package compiler

import (
	"bytes"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// compilerSourceManifest is deliberately fixed: Alder compiler inputs are
// never discovered by walking the checkout.
var compilerSourceManifest = []string{
	"checker.al",
	"host.al",
	"lexer.al",
	"main.al",
	"mir_build.al",
	"mir_model.al",
	"mir_print.al",
	"model.al",
	"output.al",
	"parser.al",
	"verify_analysis.al",
	"verify_model.al",
	"verify_phase1.al",
	"verify_phase2.al",
	"verify_phase3.al",
	"verify_phase4.al",
	"verify_phase5.al",
	"verify_phase6.al",
	"verify_phase7.al",
	"verify_phase8.al",
	"verify_phase9.al",
	"verify_phase10.al",
}

// Conformance harnesses compile exact fixed dependency closures.
// TestAlderProductionDriverEndToEnd compiles the complete production root.
// Keeping earlier lexer/parser harnesses narrow prevents later compiler layers
// from being recompiled by all preceding layer tests.
var lexerSourceManifest = []string{
	"host.al",
	"lexer.al",
	"model.al",
	"output.al",
}

const lexerWrapper = `
fn storage_error() -> I32 {
    return 3
}
fn finish(result: LexResult) -> I32 {
    return match result {
        Good(state) => finish_state(state, false)
        Bad(state) => finish_state(state, true)
    }
}
fn finish_state(state: State, failed: Bool) -> I32 {
    if !emit(state) { return 4 }
    if failed { return 1 }
    return 0
}
fn run(d: Domain, state: State) -> I32 {
    return match load_sources(d, state) {
        Err(error) => storage_error()
        Ok(loaded) => match lex_sources(d, loaded, 0) {
            Err(error) => storage_error()
            Ok(result) => finish(result)
        }
    }
}
fn init_diagnostics(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec), tokens: __s0_Buffer(TokenRec)) -> I32 { return match __s0_buffer_new(LexDiagRec, d) {
    Err(error) => storage_error()
    Ok(diagnostics) => run(d, State(paths: paths, texts: texts, values: values, sources: sources, tokens: tokens, diagnostics: diagnostics))
} }
fn init_tokens(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8), sources: __s0_Buffer(SourceRec)) -> I32 { return match __s0_buffer_new(TokenRec, d) {
    Err(error) => storage_error()
    Ok(tokens) => init_diagnostics(d, paths, texts, values, sources, tokens)
} }
fn init_sources(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8), values: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(SourceRec, d) {
    Err(error) => storage_error()
    Ok(sources) => init_tokens(d, paths, texts, values, sources)
} }
fn init_values(d: Domain, paths: __s0_Buffer(U8), texts: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(U8, d) {
    Err(error) => storage_error()
    Ok(values) => init_sources(d, paths, texts, values)
} }
fn init_texts(d: Domain, paths: __s0_Buffer(U8)) -> I32 { return match __s0_buffer_new(U8, d) {
    Err(error) => storage_error()
    Ok(texts) => init_values(d, paths, texts)
} }
fn main(d: Domain) -> I32 { return match __s0_buffer_new(U8, d) {
    Err(error) => storage_error()
    Ok(paths) => init_texts(d, paths)
} }
`

var parserSourceManifest = []string{
	"host.al",
	"lexer.al",
	"model.al",
	"output.al",
	"parser.al",
}

func TestAlderLexerConformanceEndToEnd(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var sources []frontend.Source
	for i, name := range lexerSourceManifest {
		text, err := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if err != nil {
			t.Fatal(err)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	sources = append(sources, frontend.Source{ID: 99, Path: "compiler/test/lexer_main.al", Text: lexerWrapper})
	reversed := append([]frontend.Source(nil), sources...)
	for left, right := 0, len(reversed)-1; left < right; left, right = left+1, right-1 {
		reversed[left], reversed[right] = reversed[right], reversed[left]
	}
	artifacts := make(map[EmitKind]string)
	for _, emit := range []EmitKind{EmitMIR, EmitC} {
		first, firstErr := Compile(Request{Sources: sources, Emit: emit})
		second, secondErr := Compile(Request{Sources: reversed, Emit: emit})
		if firstErr != nil || secondErr != nil || len(first.Diagnostics) != 0 || len(second.Diagnostics) != 0 || first.Artifact == nil || second.Artifact == nil {
			t.Fatalf("compile %s: first=%+v/%v second=%+v/%v", emit, first, firstErr, second, secondErr)
		}
		if first.Artifact.Text != second.Artifact.Text {
			t.Fatalf("Alder lexer %s changed with implementation source order", emit)
		}
		artifacts[emit] = first.Artifact.Text
	}
	parsed, err := mir.Parse(artifacts[EmitMIR])
	if err != nil {
		t.Fatalf("parse emitted lexer MIR: %v", err)
	}
	if errs := verify.Module(parsed); len(errs) != 0 {
		t.Fatalf("emitted lexer MIR failed verification: %s", verify.Errors(errs).String())
	}
	lexSourcesID, ok := parsed.Function("lex_sources")
	if !ok {
		t.Fatal("emitted lexer MIR has no lex_sources function")
	}
	for _, block := range parsed.Functions[lexSourcesID].Blocks {
		for _, instruction := range block.Instrs {
			if instruction.Op == mir.OpCall && instruction.Callee == lexSourcesID {
				t.Fatal("lex_sources recursively calls itself")
			}
		}
	}
	generated := artifacts[EmitC]
	for _, leaked := range []string{root, filepath.ToSlash(root), strings.ReplaceAll(root, `\`, `\\`)} {
		if leaked != "" && strings.Contains(generated, leaked) {
			t.Fatalf("generated C contains checkout path %q", leaked)
		}
	}
	if !strings.Contains(generated, "buffer_append") || strings.Contains(generated, "map_") {
		t.Fatal("generated C has unexpected bootstrap storage inventory")
	}
	dir := t.TempDir()
	gen := filepath.Join(dir, "lexer.c")
	exe := filepath.Join(dir, "alder-lexer.exe")
	if err := os.WriteFile(gen, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), gen, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile: %v\n%s", err, output)
	}

	keywords := []expectedLexerToken{
		{raw: "import", kind: 1, keyword: 1}, {raw: "type", kind: 1, keyword: 2},
		{raw: "enum", kind: 1, keyword: 3}, {raw: "fn", kind: 1, keyword: 4},
		{raw: "let", kind: 1, keyword: 5}, {raw: "var", kind: 1, keyword: 6},
		{raw: "if", kind: 1, keyword: 7}, {raw: "else", kind: 1, keyword: 8},
		{raw: "while", kind: 1, keyword: 9}, {raw: "for", kind: 1, keyword: 10},
		{raw: "in", kind: 1, keyword: 11}, {raw: "return", kind: 1, keyword: 12},
		{raw: "match", kind: 1, keyword: 13}, {raw: "using", kind: 1, keyword: 14},
		{raw: "with", kind: 1, keyword: 15}, {raw: "try", kind: 1, keyword: 16},
		{raw: "true", kind: 1, keyword: 17}, {raw: "false", kind: 1, keyword: 18},
		{raw: "unsafe", kind: 1, keyword: 19}, {raw: "ident_9", kind: 1},
	}
	keywordRaw := make([]string, len(keywords))
	for i := range keywords {
		keywordRaw[i] = keywords[i].raw
	}
	valueTokens := []expectedLexerToken{
		{raw: "0", kind: 2}, {raw: "-12", kind: 2}, {raw: "3.", kind: 3}, {raw: "4.5", kind: 3},
		{raw: "6e2", kind: 3}, {raw: "7E+3", kind: 3}, {raw: "-8e-2", kind: 3},
		{raw: `"a\n\t\r\\\"\0b"`, semantic: []byte{'a', '\n', '\t', '\r', '\\', '"', 0, 'b'}, kind: 4},
	}
	for _, punct := range []string{"(", ")", "{", "}", "[", "]", ",", ":", "=", ".", "<", ">", "!", "&", "|", "+", "-", "*", "/", "%", "->", "<<", ">>", "==", "!=", "<=", ">=", "&&", "||", "=>"} {
		valueTokens = append(valueTokens, expectedLexerToken{raw: punct, kind: 5})
	}
	valueRaw := make([]string, len(valueTokens))
	for i := range valueTokens {
		valueRaw[i] = valueTokens[i].raw
	}
	boundaryTokens := []expectedLexerToken{
		{raw: "-", kind: 5}, {raw: "->", kind: 5}, {raw: "-", kind: 5},
		{raw: "-1", kind: 2}, {raw: ".", kind: 5}, {raw: "5", kind: 2},
		{raw: "1.", kind: 3}, {raw: ".", kind: 5}, {raw: "2", kind: 2},
		{raw: "1.e2", kind: 3},
	}
	fixtures := []lexerFixture{
		{path: "a-empty.al", text: nil},
		{path: "b-keywords.al", text: []byte(strings.Join(keywordRaw, " ") + "\r\n// trailing trivia\n"), tokens: keywords},
		{path: "c-values.al", text: []byte("/* leading */ " + strings.Join(valueRaw, " ") + "\n"), tokens: valueTokens},
		{path: "d-boundaries.al", text: []byte("- -> --1 .5 1..2 1.e2 /**/ // eof"), tokens: boundaryTokens},
	}
	files := make(map[string][]byte, len(fixtures))
	var order []string
	for i := len(fixtures) - 1; i >= 0; i-- {
		files[fixtures[i].path] = fixtures[i].text
		order = append(order, fixtures[i].path)
	}
	want := expectedLexerManifest(t, fixtures)
	first := runAlderLexer(t, exe, dir, files, order, false)
	second := runAlderLexer(t, exe, dir, files, []string{"a-empty.al", "b-keywords.al", "c-values.al", "d-boundaries.al"}, false)
	if first != want || second != want || first != second {
		t.Fatalf("valid token manifest mismatch\nwant:\n%s\ngot:\n%s", want, first)
	}
	if again := runAlderLexer(t, exe, dir, files, order, false); again != first {
		t.Fatal("repeat lexer process output changed")
	}

	rejections := []struct {
		name string
		text []byte
		kind uint64
		end  int
	}{
		{"semicolon.al", []byte(";"), 1, 1},
		{"invalid-byte.al", []byte{0xff}, 2, 1},
		{"unicode.al", []byte("é"), 2, 2},
		{"unicode-three.al", []byte("€"), 2, 3},
		{"unicode-four.al", []byte("😀"), 2, 4},
		{"truncated-utf8.al", []byte{0xe2, 0x82}, 2, 1},
		{"overlong-utf8.al", []byte{0xc0, 0x80}, 2, 1},
		{"exponent.al", []byte("1e+"), 3, 1},
		{"escape.al", []byte(`"\q"`), 4, 1},
		{"string.al", []byte(`"abc`), 5, 1},
		{"comment.al", []byte("/* x"), 6, 1},
	}
	for _, tc := range rejections {
		t.Run(tc.name, func(t *testing.T) {
			got := runAlderLexer(t, exe, t.TempDir(), map[string][]byte{tc.name: tc.text}, []string{tc.name}, true)
			want := fmt.Sprintf("ALDER-TOKEN-MANIFEST 1\nS 0 %s %d\nD LEX0001 %d %s 0 %d\nEND\n", tc.name, len(tc.text), tc.kind, tc.name, tc.end)
			if got != want {
				t.Fatalf("rejection manifest mismatch\nwant:\n%s\ngot:\n%s", want, got)
			}
		})
	}
	shiftedText := []byte("ok /* trivia */ ;")
	shiftedWant := "ALDER-TOKEN-MANIFEST 1\nS 0 shifted.al 17\nT 0 1 0 0 2 0 0 6f6b\nD LEX0001 1 shifted.al 16 17\nEND\n"
	if got := runAlderLexer(t, exe, t.TempDir(), map[string][]byte{"shifted.al": shiftedText}, []string{"shifted.al"}, true); got != shiftedWant {
		t.Fatalf("shifted rejection manifest mismatch\nwant:\n%s\ngot:\n%s", shiftedWant, got)
	}
	partialText := []byte(`ok "` + strings.Repeat("a", 32) + `\q"`)
	partialWant := fmt.Sprintf("ALDER-TOKEN-MANIFEST 1\nS 0 partial-string.al %d\nT 0 1 0 0 2 0 0 6f6b\nD LEX0001 4 partial-string.al 3 4\nEND\n", len(partialText))
	if got := runAlderLexer(t, exe, t.TempDir(), map[string][]byte{"partial-string.al": partialText}, []string{"partial-string.al"}, true); got != partialWant {
		t.Fatalf("partial string rejection manifest mismatch\nwant:\n%s\ngot:\n%s", partialWant, got)
	}
	canonicalBad := map[string][]byte{"z-bad.al": {'@'}, "a-bad.al": {';'}}
	wantBad := "ALDER-TOKEN-MANIFEST 1\nS 0 a-bad.al 1\nS 1 z-bad.al 1\nD LEX0001 1 a-bad.al 0 1\nEND\n"
	for _, badOrder := range [][]string{{"z-bad.al", "a-bad.al"}, {"a-bad.al", "z-bad.al"}} {
		if got := runAlderLexer(t, exe, t.TempDir(), canonicalBad, badOrder, true); got != wantBad {
			t.Fatalf("canonical first diagnostic mismatch for %v\nwant:\n%s\ngot:\n%s", badOrder, wantBad, got)
		}
	}
}

type expectedLexerToken struct {
	raw      string
	semantic []byte
	kind     uint64
	keyword  uint64
}

type lexerFixture struct {
	path   string
	text   []byte
	tokens []expectedLexerToken
}

func expectedLexerManifest(t *testing.T, fixtures []lexerFixture) string {
	t.Helper()
	var out strings.Builder
	out.WriteString("ALDER-TOKEN-MANIFEST 1\n")
	for source, fixture := range fixtures {
		fmt.Fprintf(&out, "S %d %s %d\n", source, fixture.path, len(fixture.text))
	}
	for source, fixture := range fixtures {
		cursor := 0
		for _, token := range fixture.tokens {
			relative := bytes.Index(fixture.text[cursor:], []byte(token.raw))
			if relative < 0 {
				t.Fatalf("expected token %q not found in %s after byte %d", token.raw, fixture.path, cursor)
			}
			start := cursor + relative
			end := start + len(token.raw)
			semantic := token.semantic
			if semantic == nil {
				semantic = []byte(token.raw)
			}
			fmt.Fprintf(&out, "T %d %d %d %d %d %d %d %s\n", source, token.kind, token.keyword, start, end, cursor, start, hex.EncodeToString(semantic))
			cursor = end
		}
		fmt.Fprintf(&out, "T %d 0 0 %d %d %d %d \n", source, len(fixture.text), len(fixture.text), cursor, len(fixture.text))
	}
	out.WriteString("END\n")
	return out.String()
}

func runAlderLexer(t *testing.T, exe, dir string, files map[string][]byte, order []string, wantFailure bool) string {
	t.Helper()
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), text, 0o644); err != nil {
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
		t.Fatalf("lexer run: %v stderr=%q", err, stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
	return stdout.String()
}
