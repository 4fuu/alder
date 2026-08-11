package compiler

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

func TestDeclarationSpikeEndToEnd(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	spikeFiles := []string{"host.al", "main.al", "model.al", "output.al", "parser.al"}
	var spike []frontend.Source
	for i, file := range spikeFiles {
		name := filepath.Join(root, "bootstrap", "spike", file)
		text, readErr := os.ReadFile(name)
		if readErr != nil {
			t.Fatal(readErr)
		}
		spike = append(spike, frontend.Source{ID: frontend.SourceID(i + 1), Path: "bootstrap/spike/" + file, Text: string(text)})
	}
	reversed := append([]frontend.Source(nil), spike...)
	for left, right := 0, len(reversed)-1; left < right; left, right = left+1, right-1 {
		reversed[left], reversed[right] = reversed[right], reversed[left]
	}
	artifacts := make(map[EmitKind]string)
	for _, emit := range []EmitKind{EmitMIR, EmitC} {
		first, firstErr := Compile(Request{Sources: spike, Emit: emit})
		second, secondErr := Compile(Request{Sources: reversed, Emit: emit})
		if firstErr != nil || secondErr != nil || len(first.Diagnostics) != 0 || len(second.Diagnostics) != 0 || first.Artifact == nil || second.Artifact == nil {
			t.Fatalf("compile %s: first=%+v/%v second=%+v/%v", emit, first, firstErr, second, secondErr)
		}
		if first.Artifact.Text != second.Artifact.Text {
			t.Fatalf("spike %s changed with implementation source order", emit)
		}
		artifacts[emit] = first.Artifact.Text
	}
	parsed, err := mir.Parse(artifacts[EmitMIR])
	if err != nil {
		t.Fatalf("parse emitted spike MIR: %v", err)
	}
	if errs := verify.Module(parsed); len(errs) != 0 {
		t.Fatalf("emitted spike MIR failed verification: %s", verify.Errors(errs).String())
	}
	generated := artifacts[EmitC]
	for _, leaked := range []string{root, filepath.ToSlash(root), strings.ReplaceAll(root, `\`, `\\`)} {
		if leaked != "" && strings.Contains(generated, leaked) {
			t.Fatalf("generated C contains checkout path %q", leaked)
		}
	}
	if !strings.Contains(generated, "buffer_append") || strings.Contains(generated, "map_") {
		t.Fatalf("generated C has unexpected helper/path inventory")
	}
	dir := t.TempDir()
	gen := filepath.Join(dir, "spike.c")
	exe := filepath.Join(dir, "spike.exe")
	if err := os.WriteFile(gen, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), gen, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile: %v\n%s", err, output)
	}

	var a, b strings.Builder
	for i := 0; i < 64; i++ {
		fmt.Fprintf(&a, "def n%d\n", i)
	}
	for i := 63; i >= 0; i-- {
		fmt.Fprintf(&b, "use n%d\n", i)
	}
	valid := map[string]string{"a.al": b.String(), "b.al": a.String()}
	want := spikeManifest(valid)
	first := runSpike(t, exe, dir, valid, []string{"b.al", "a.al"}, false)
	second := runSpike(t, exe, dir, valid, []string{"a.al", "b.al"}, false)
	if first != want || second != want || first != second {
		t.Fatalf("valid manifest mismatch\nwant:\n%s\ngot:\n%s", want, first)
	}
	if again := runSpike(t, exe, dir, valid, []string{"b.al", "a.al"}, false); again != first {
		t.Fatal("repeat process output changed")
	}

	bad := map[string]string{"empty.al": "", "errors.al": "def ok\r\ndef ok\n@ bad\nuse missing\ndef later\nuse later"}
	out := runSpike(t, exe, dir, bad, []string{"errors.al", "empty.al"}, true)
	wantBad := "ALDER-DECL-MANIFEST 1\n" +
		"S 0 empty.al 0\n" +
		"S 1 errors.al 52\n" +
		"D 1 ok errors.al 4 6\n" +
		"D 2 ok errors.al 12 14\n" +
		"D 3 later errors.al 37 42\n" +
		"U 1 missing errors.al 25 32 0\n" +
		"U 2 later errors.al 47 52 3\n" +
		"E E001 errors.al 15 20\n" +
		"E E002 errors.al 12 14 related errors.al 4 6\n" +
		"E E003 errors.al 25 32\n" +
		"END\n"
	if out != wantBad {
		t.Fatalf("diagnostic manifest mismatch\nwant:\n%s\ngot:\n%s", wantBad, out)
	}
	if permuted := runSpike(t, exe, dir, bad, []string{"empty.al", "errors.al"}, true); permuted != out {
		t.Fatalf("diagnostic manifest changed with source argument order\nfirst:\n%s\nsecond:\n%s", out, permuted)
	}
	binary := map[string]string{"binary.al": "\x00\ndef kept\nuse kept\n"}
	wantBinary := "ALDER-DECL-MANIFEST 1\n" +
		"S 0 binary.al 20\n" +
		"D 1 kept binary.al 6 10\n" +
		"U 1 kept binary.al 15 19 1\n" +
		"E E001 binary.al 0 1\nEND\n"
	if got := runSpike(t, exe, dir, binary, []string{"binary.al"}, true); got != wantBinary {
		t.Fatalf("binary recovery manifest mismatch\nwant:\n%s\ngot:\n%s", wantBinary, got)
	}
	duplicates := map[string]string{"a.al": "def same\n", "b.al": "def same\n", "c.al": "use same"}
	wantDuplicates := "ALDER-DECL-MANIFEST 1\n" +
		"S 0 a.al 9\nS 1 b.al 9\nS 2 c.al 8\n" +
		"D 1 same a.al 4 8\nD 2 same b.al 4 8\n" +
		"U 1 same c.al 4 8 1\n" +
		"E E002 b.al 4 8 related a.al 4 8\nEND\n"
	for _, order := range [][]string{{"c.al", "b.al", "a.al"}, {"b.al", "a.al", "c.al"}} {
		if got := runSpike(t, exe, dir, duplicates, order, true); got != wantDuplicates {
			t.Fatalf("cross-file duplicate manifest mismatch for %v\nwant:\n%s\ngot:\n%s", order, wantDuplicates, got)
		}
	}
	nested := map[string]string{"nested.al": "begin\ndef nested\nbegin\nuse nested\nend\nend\n"}
	if got, want := runSpike(t, exe, dir, nested, []string{"nested.al"}, false), spikeManifest(nested); got != want {
		t.Fatalf("nested manifest mismatch\nwant:\n%s\ngot:\n%s", want, got)
	}
	nestingErrors := map[string]string{"nesting-errors.al": "end\ndef recovered\nuse recovered\nbegin"}
	wantNestingErrors := "ALDER-DECL-MANIFEST 1\n" +
		"S 0 nesting-errors.al 37\n" +
		"D 1 recovered nesting-errors.al 8 17\n" +
		"U 1 recovered nesting-errors.al 22 31 1\n" +
		"E E004 nesting-errors.al 0 3\n" +
		"E E004 nesting-errors.al 37 37\nEND\n"
	if got := runSpike(t, exe, dir, nestingErrors, []string{"nesting-errors.al"}, true); got != wantNestingErrors {
		t.Fatalf("nesting recovery manifest mismatch\nwant:\n%s\ngot:\n%s", wantNestingErrors, got)
	}
	var unknownText strings.Builder
	for i := 0; i < 20; i++ {
		fmt.Fprintf(&unknownText, "use missing%d\n", i)
	}
	unknown := map[string]string{"unknown.al": unknownText.String()}
	if got, want := runSpike(t, exe, dir, unknown, []string{"unknown.al"}, true), spikeUnknownManifest(unknown); got != want {
		t.Fatalf("diagnostic growth manifest mismatch\nwant:\n%s\ngot:\n%s", want, got)
	}
	var emptySources []string
	manySources := make(map[string]string)
	for i := 19; i >= 0; i-- {
		name := fmt.Sprintf("%02d-empty.al", i)
		emptySources = append(emptySources, name)
		manySources[name] = ""
	}
	if got, want := runSpike(t, exe, dir, manySources, emptySources, false), spikeManifest(manySources); got != want {
		t.Fatalf("source growth manifest mismatch\nwant:\n%s\ngot:\n%s", want, got)
	}
	if empty := runSpike(t, exe, dir, map[string]string{}, nil, false); empty != "ALDER-DECL-MANIFEST 1\nEND\n" {
		t.Fatalf("no-source output: %q", empty)
	}
}

func runSpike(t *testing.T, exe, dir string, files map[string]string, order []string, wantFailure bool) string {
	t.Helper()
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command(exe, order...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if wantFailure {
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			t.Fatalf("diagnostic run: err=%v stderr=%q", err, stderr.String())
		}
	} else if err != nil {
		t.Fatalf("run: %v stderr=%q", err, stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
	return string(out)
}

func spikeManifest(files map[string]string) string {
	var names []string
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	var out strings.Builder
	out.WriteString("ALDER-DECL-MANIFEST 1\n")
	for i, name := range names {
		fmt.Fprintf(&out, "S %d %s %d\n", i, name, len(files[name]))
	}
	id := map[string]int{}
	next := 1
	for _, path := range names {
		for _, line := range linesWithOffsets(files[path]) {
			if strings.HasPrefix(line.text, "def ") {
				name := strings.TrimSpace(line.text[4:])
				id[name] = next
				fmt.Fprintf(&out, "D %d %s %s %d %d\n", next, name, path, line.offset+4, line.offset+4+len(name))
				next++
			}
		}
	}
	use := 1
	for _, path := range names {
		for _, line := range linesWithOffsets(files[path]) {
			if strings.HasPrefix(line.text, "use ") {
				name := strings.TrimSpace(line.text[4:])
				fmt.Fprintf(&out, "U %d %s %s %d %d %d\n", use, name, path, line.offset+4, line.offset+4+len(name), id[name])
				use++
			}
		}
	}
	out.WriteString("END\n")
	return out.String()
}

func spikeUnknownManifest(files map[string]string) string {
	out := strings.TrimSuffix(spikeManifest(files), "END\n")
	var diagnostics strings.Builder
	var paths []string
	for path := range files {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	for _, path := range paths {
		text := files[path]
		for _, line := range linesWithOffsets(text) {
			if strings.HasPrefix(line.text, "use ") {
				name := strings.TrimSpace(line.text[4:])
				fmt.Fprintf(&diagnostics, "E E003 %s %d %d\n", path, line.offset+4, line.offset+4+len(name))
			}
		}
	}
	return out + diagnostics.String() + "END\n"
}

type spikeLine struct {
	offset int
	text   string
}

func linesWithOffsets(text string) []spikeLine {
	var result []spikeLine
	at := 0
	for _, line := range strings.SplitAfter(text, "\n") {
		value := strings.TrimSuffix(line, "\n")
		result = append(result, spikeLine{at, value})
		at += len(line)
	}
	return result
}
