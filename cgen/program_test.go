package cgen

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

func programModule(t *testing.T, params, body string) *mir.Module {
	return programModuleStatus(t, 0, params, body)
}

func programModuleStatus(t *testing.T, status int, params, body string) *mir.Module {
	t.Helper()
	m, err := mir.Parse(fmt.Sprintf("mir 1\n\nconst @status: i32 = %d\nconst @one: u64 = 1\n\nfn @main(%s) -> i32 {\nbb0:\n%s  %%r = const.get @status\n  return %%r\n}\n", status, params, body))
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestGenerateProgramContract(t *testing.T) {
	m := programModule(t, "", "")
	generic, err := Generate(m)
	if err != nil {
		t.Fatal(err)
	}
	got, err := GenerateProgram(m)
	if err != nil {
		t.Fatal(err)
	}
	again, err := GenerateProgram(m)
	if err != nil || got != again {
		t.Fatalf("program output is not deterministic: %v", err)
	}
	if strings.Contains(generic, "alder_program_entry") {
		t.Fatal("generic Generate emitted a program entry")
	}
	if strings.Count(got, "int32_t alder_program_entry(void *host_context)") != 1 {
		t.Fatal("program output does not contain exactly one exported entry definition")
	}
	if !strings.Contains(got, "static ALDER_MAYBE_UNUSED int32_t alder_fn_main_0") {
		t.Fatal("internal main is not static and ID-named")
	}
}

func TestGenerateProgramEntryErrors(t *testing.T) {
	cases := []*mir.Module{mir.NewModule()}
	wrongResult, err := mir.Parse("mir 1\nfn @main() {\nbb0:\n  return\n}\n")
	if err != nil {
		t.Fatal(err)
	}
	cases = append(cases, wrongResult)
	wrongParam, err := mir.Parse("mir 1\nconst @zero: i32 = 0\nfn @main(%x: i32) -> i32 {\nbb0:\n  %r = const.get @zero\n  return %r\n}\n")
	if err != nil {
		t.Fatal(err)
	}
	cases = append(cases, wrongParam)
	for _, m := range cases {
		typeCount := len(m.Types)
		_, err := GenerateProgram(m)
		var entryErr *ProgramEntryError
		if !errors.As(err, &entryErr) || !IsProgramEntryError(err) {
			t.Fatalf("entry mismatch did not return typed error: %v", err)
		}
		if len(m.Types) != typeCount {
			t.Fatal("entry validation mutated the input module")
		}
	}
}

func TestGenerateProgramVerifiesBeforeEntryValidation(t *testing.T) {
	m := mir.NewModule()
	m.AddFunction("main", nil, mir.TypeUnit)
	_, err := GenerateProgram(m)
	if err == nil || IsProgramEntryError(err) || !strings.Contains(err.Error(), "module failed verification") {
		t.Fatalf("invalid MIR was not rejected by the verifier first: %v", err)
	}
}

func TestRecursiveProgramCompilesAsStrictC11(t *testing.T) {
	text := `mir 1
const @status: i32 = 0
fn @main() -> i32 {
bb0:
  %r = const.get @status
  return %r
}
fn @left() {
bb0:
  call @right()
  return
}
fn @right() {
bb0:
  call @left()
  return
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	generated, err := GenerateProgram(m)
	if err != nil {
		t.Fatal(err)
	}
	for _, cc := range findCompilers(t) {
		path := filepath.Join(t.TempDir(), "recursive.c")
		if err := os.WriteFile(path, []byte(generated), 0o644); err != nil {
			t.Fatal(err)
		}
		args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join("..", "runtime", "c"), "-I", filepath.Join("..", "bootstrap"), "-fsyntax-only", path}
		if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
			t.Fatalf("strict compile: %v\n%s", err, output)
		}
	}
}

func TestProgramSeparateTranslationUnits(t *testing.T) {
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			for _, tc := range []struct {
				name, params, body, probe string
				status                    int
				wantSuccess               bool
			}{
				{"no_domain", "", "", "host", 0, true},
				{"nonzero_status", "", "", "host", 7, false},
				{"root_domain", "%d: domain_handle", "  %n = const.get @one\n  %buf = alloc %d, u8, %n\n", "probe", 0, true},
			} {
				t.Run(tc.name, func(t *testing.T) {
					out, err := GenerateProgram(programModuleStatus(t, tc.status, tc.params, tc.body))
					if err != nil {
						t.Fatal(err)
					}
					dir := t.TempDir()
					gen := filepath.Join(dir, "gen.c")
					if err := os.WriteFile(gen, []byte(out), 0o644); err != nil {
						t.Fatal(err)
					}
					driver := filepath.Join("..", "bootstrap", "alder_host.c")
					if tc.probe == "probe" {
						driver = filepath.Join(dir, "probe.c")
						source := "#include \"alder_host.h\"\n#include \"alder.h\"\nint main(void) { int x = 0; if (alder_program_entry(NULL) != ALDER_PROGRAM_FAILURE_STATUS) return 2; if (alder_program_entry(&x) != 0) return 3; return alder_runtime_live_allocations() == 0 ? 0 : 4; }\n"
						if err := os.WriteFile(driver, []byte(source), 0o644); err != nil {
							t.Fatal(err)
						}
					}
					exe := filepath.Join(dir, "program.exe")
					args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join("..", "runtime", "c"), "-I", filepath.Join("..", "bootstrap"), gen, driver, filepath.Join("..", "runtime", "c", "alder.c"), "-o", exe}
					if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
						t.Fatalf("compile: %v\n%s", err, output)
					}
					output, err := exec.Command(exe).CombinedOutput()
					if tc.wantSuccess && err != nil {
						t.Fatalf("run: %v\n%s", err, output)
					}
					if !tc.wantSuccess {
						var exitError *exec.ExitError
						if !errors.As(err, &exitError) || exitError.ExitCode() != 1 {
							t.Fatalf("nonzero Alder status was not mapped to EXIT_FAILURE: err=%v output=%s", err, output)
						}
					}
				})
			}
		})
	}
}
