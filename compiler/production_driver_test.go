package compiler

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
)

func TestAlderProductionDriverEndToEnd(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	var sources []frontend.Source
	for i, name := range compilerSourceManifest {
		text, readErr := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if readErr != nil {
			t.Fatal(readErr)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	compiled, err := Compile(Request{Sources: sources, Emit: EmitMIR})
	if err != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		t.Fatalf("compile production root: result=%+v error=%v", compiled, err)
	}
	module, err := mir.Parse(compiled.Artifact.Text)
	if err != nil {
		t.Fatalf("parse production MIR: %v", err)
	}
	// Compile already verifies the production module before emitting this MIR.
	// Parse the emitted form for C generation without repeating the expensive
	// whole-module verifier over the compiler-sized graph.
	generated, err := cgen.GenerateProgram(module)
	if err != nil {
		t.Fatalf("generate production C: %v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "compiler.c")
	exe := filepath.Join(dir, "alder-compiler.exe")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	compileGeneratedProgram(t, cc, root, cfile, filepath.Join(root, "bootstrap", "alder_host.c"), exe)

	validFiles := map[string]string{
		"z.al": "fn identity(value: U64) -> U64 { return value }\n",
		"a.al": "type Box { value: U64 }\n",
	}
	first, firstStatus := runProductionCompiler(t, exe, validFiles, []string{"z.al", "a.al"})
	second, secondStatus := runProductionCompiler(t, exe, validFiles, []string{"a.al", "z.al"})
	if firstStatus != 0 || secondStatus != 0 || first != second {
		t.Fatalf("valid production run is not deterministic: status=%d/%d", firstStatus, secondStatus)
	}
	if !strings.HasPrefix(first, "ALDER-CHECKER-MANIFEST 6\n") || !strings.Contains(first, "\nY ") || strings.Contains(first, "\nD ") || !strings.HasSuffix(first, "END\n") {
		t.Fatalf("valid input did not reach checker output:\n%s", first)
	}

	rejections := []struct {
		name, text, prefix, diagnostic string
	}{
		{"lex.al", ";", "ALDER-TOKEN-MANIFEST 1\n", "\nD LEX0001 "},
		{"parse.al", "type Broken { value U64 }\n", "ALDER-PARSER-MANIFEST 1\n", "\nD SYN0001 "},
		{"check.al", "type Broken { value: Missing }\n", "ALDER-CHECKER-MANIFEST 6\n", "\nD 4 "},
	}
	for _, fixture := range rejections {
		t.Run(fixture.name, func(t *testing.T) {
			files := map[string]string{fixture.name: fixture.text}
			one, oneStatus := runProductionCompiler(t, exe, files, []string{fixture.name})
			two, twoStatus := runProductionCompiler(t, exe, files, []string{fixture.name})
			if oneStatus != 1 || twoStatus != 1 || one != two {
				t.Fatalf("phase failure is not deterministic: status=%d/%d", oneStatus, twoStatus)
			}
			if !strings.HasPrefix(one, fixture.prefix) || !strings.Contains(one, fixture.diagnostic) || !strings.HasSuffix(one, "END\n") {
				t.Fatalf("failure reached the wrong phase:\n%s", one)
			}
		})
	}

	testProductionFailureStatus(t, cc, root, cfile, dir, "STORAGE_FAIL", 3)
	testProductionFailureStatus(t, cc, root, cfile, dir, "OUTPUT_FAIL", 4)
}

func compileGeneratedProgram(t *testing.T, cc, root, generated, host, output string, extra ...string) {
	t.Helper()
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion"}
	args = append(args, extra...)
	args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), generated, host, filepath.Join(root, "runtime", "c", "alder.c"), "-o", output)
	if outputText, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile: %v\n%s", err, outputText)
	}
}

func runProductionCompiler(t *testing.T, exe string, files map[string]string, order []string) (string, int) {
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
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("run production compiler: %v", err)
		}
		status = exit.ExitCode()
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
	return stdout.String(), status
}

func testProductionFailureStatus(t *testing.T, cc, root, generated, dir, mode string, want int) {
	t.Helper()
	host := filepath.Join(dir, strings.ToLower(mode)+"_host.c")
	exe := filepath.Join(dir, strings.ToLower(mode)+".exe")
	source := fmt.Sprintf(`#include "alder_host.h"
#include "alder.h"
#include <stdbool.h>
#include <stdint.h>

static const uint8_t source_text[] = "type Good { value: U64 }\n";
uint64_t alderhost_source_count(void) { return 1; }
uint64_t alderhost_source_path_len(uint64_t source) { (void)source; return 7; }
uint8_t alderhost_source_path_byte(uint64_t source, uint64_t offset) { (void)source; return (uint8_t)"good.al"[offset]; }
uint64_t alderhost_source_text_len(uint64_t source) { (void)source; return (uint64_t)(sizeof(source_text) - 1); }
uint8_t alderhost_source_text_byte(uint64_t source, uint64_t offset) { (void)source; return source_text[offset]; }
bool alderhost_stdout_byte(uint8_t byte) { (void)byte; return %s; }
bool alderhost_stderr_byte(uint8_t byte) { (void)byte; return true; }
int main(void) {
    int context = 0;
    %s
    return alder_program_entry(&context) == (int32_t)%d ? 0 : 1;
}
`, map[bool]string{true: "false", false: "true"}[mode == "OUTPUT_FAIL"], map[bool]string{true: "alder_runtime_test_fail_domain_alloc_after(0);", false: ""}[mode == "STORAGE_FAIL"], want)
	if err := os.WriteFile(host, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	compileGeneratedProgram(t, cc, root, generated, host, exe, "-DALDER_RUNTIME_TESTING")
	if output, err := exec.Command(exe).CombinedOutput(); err != nil {
		t.Fatalf("production %s status: %v\n%s", mode, err, output)
	}
}
