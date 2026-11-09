package compiler

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

var bootstrapAcceptFixtures = []string{
	"basic",
	"generics",
	"match",
	"try",
	"cleanup",
	"ffi",
	"buffer",
}

var bootstrapE2EFixtures = []string{
	"arith",
	"structs",
	"enums",
	"option",
	"strings",
	"generic",
	"domains",
	"maps",
	"buffer",
	"collections",
	"storage",
	"cleanup",
	"ffi",
}

var bootstrapRejectFixtures = []string{
	"syntax-unterminated-comment",
	"syntax-bad-escape",
	"syntax-missing-semicolon",
	"unknown-name",
	"unknown-type",
	"type-mismatch",
	"immutable-assign",
	"map-key-signed",
	"map-value-string",
	"nested-slice",
	"type-cycle",
	"match-nonexhaustive",
	"match-unknown-variant",
	"try-not-result",
	"try-error-mismatch",
	// using-in-loop moved to the Go Stage 0 rejection list only: the Alder
	// compiler registers a using in a loop body for that iteration's scope.
	"using-callback-type",
	"literal-out-of-range",
	"fall-off-end",
	"reserved-name",
	"duplicate-decl",
	"alloc-as-slice-param",
	"bind-mark",
	"bind-unit",
	"ffi-unsupported-type",
	"float-arithmetic",
	"index-not-u64",
	"shadowing",
	"unreachable-statement",
	// function-value moved to the Alder-only M7.5 function-value fixtures:
	// the Alder checker accepts a non-generic function name as a value.
	"type-parameter-after-runtime",
	// The bootstrap-* fixtures pin the ordinary-mode bootstrap-surface gate
	// in both compilers. bootstrap-type-map moved to the Alder-only M7.5
	// ordered-collection fixtures: the public Map is the ordered kind-23
	// collection now, so only the Go oracle still rejects it there.
	"bootstrap-type-domain",
	"bootstrap-type-domainmark",
	"bootstrap-type-s0error",
	"bootstrap-type-s0string",
	"bootstrap-type-s0buffer",
	"bootstrap-op-alloc",
	"bootstrap-op-buffer-new",
	"bootstrap-op-map-create",
	"bootstrap-op-get",
	"bootstrap-entry-domain-main",
}

// privateProfileReject keeps testing its original diagnostic under the
// private bootstrap profile.
var privateProfileReject = map[string]bool{
	"alloc-as-slice-param.al": true,
	"bind-mark.al":            true,
	"bind-unit.al":            true,
	"map-key-signed.al":       true,
	"map-value-string.al":     true,
	// The callback `using` clause is bootstrap-private since M7.5, so its
	// rejects (and the Go oracle that still accepts the form) run privately.
	"using-callback-type.al": true,
}

// privateProfileFiles reports whether a self-hosting acceptance corpus still
// uses the S0 bridges and needs the private bootstrap profile. The
// `with cleanup_function` clause is one of those bridges since M7.5 gated it
// behind the profile.
func privateProfileFiles(files map[string]string) bool {
	for _, text := range files {
		if strings.Contains(text, "__s0_") || strings.Contains(text, "Domain") || strings.Contains(text, "Map(") {
			return true
		}
		for _, line := range strings.Split(text, "\n") {
			if strings.Contains(line, "using ") && strings.Contains(line, " with ") {
				return true
			}
		}
	}
	return false
}

func TestAlder1SelfHostingCapableCorpus(t *testing.T) {
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
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	object := buildRuntimeObject(t, cc, root)
	noGo := noGoEnv(t, cc)
	t.Run("i64-min", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"i64min.al": "fn main() -> I32 {\n    if -9223372036854775808 == -9223372036854775807 - 1 { return 0 }\n    return 1\n}\n"}
		assertAlder1VerifiedArtifact(t, exe, cc, root, object, noGo, files, "i64min.al", "", 0)
	})
	t.Run("s0-error-limit", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"limit.al": "fn f() -> Result(U64, __s0_Error) { return Err(Limit) }\nfn main() -> I32 { return 0 }\n"}
		assertAlder1VerifiedArtifact(t, exe, cc, root, object, noGo, files, "limit.al", "", 0)
	})
	t.Run("buffer-new-without-slice", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"noslice.al": "fn make(d: Domain) -> Result(__s0_Buffer(U64), __s0_Error) {\n    let b = try __s0_buffer_new(U64, d)\n    return Ok(b)\n}\nfn main() -> I32 { return 0 }\n"}
		assertAlder1VerifiedArtifact(t, exe, cc, root, object, noGo, files, "noslice.al", "", 0)
	})
	t.Run("buffer-match-result", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"matchbuf.al": "fn consume(b: __s0_Buffer(U64)) -> I32 { return 0 }\nfn main(d: Domain) -> I32 {\n    return match __s0_buffer_new(U64, d) {\n        Err(error) => 1\n        Ok(b) => consume(b)\n    }\n}\n"}
		assertAlder1VerifiedArtifact(t, exe, cc, root, object, noGo, files, "matchbuf.al", "", 0)
	})

	for _, name := range bootstrapAcceptFixtures {
		name := name
		t.Run("accept/"+name, func(t *testing.T) {
			t.Parallel()
			text := readBootstrapFixture(t, root, filepath.Join("frontend", "testdata", "accept", name+".al"))
			files := map[string]string{name + ".al": text}
			assertAlder1VerifiedArtifact(t, exe, cc, root, object, noGo, files, name+".al", extraSymbolsFor(name), 0)
		})
	}
	for _, name := range bootstrapE2EFixtures {
		name := name
		t.Run("e2e/"+name, func(t *testing.T) {
			t.Parallel()
			text := readBootstrapFixture(t, root, filepath.Join("frontend", "testdata", "e2e", name+".al"))
			files := map[string]string{name + ".al": text}
			assertAlder1VerifiedArtifact(t, exe, cc, root, object, noGo, files, name+".al", extraSymbolsFor(name), 0)
		})
	}
	for _, name := range bootstrapRejectFixtures {
		name := name
		t.Run("reject/"+name, func(t *testing.T) {
			t.Parallel()
			text := readBootstrapFixture(t, root, filepath.Join("frontend", "testdata", "reject", name+".al"))
			files := map[string]string{name + ".al": text}
			assertAlder1RejectsLikeGo(t, exe, noGo, files, name+".al")
		})
	}

	t.Run("no-repair", func(t *testing.T) {
		got := runProductionCompiler(t, exe, map[string]string{"library.al": "fn helper() -> I32 { return 0 }\n"}, "compile", "--emit=c", "library.al")
		if got.status != 4 || got.stdout != "" || !strings.Contains(got.stderr, "internal compiler failure") {
			t.Fatalf("unhosted library emitted bytes or wrong class: %+v", got)
		}
	})
}

func buildAlder1(t *testing.T, cc, root string) string {
	t.Helper()
	var sources []frontend.Source
	for i, name := range compilerSourceManifest {
		text, err := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if err != nil {
			t.Fatal(err)
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	compiled, err := Compile(Request{Sources: sources, Emit: EmitC, BootstrapPrivate: true})
	if err != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		t.Fatalf("compile production root: result=%+v error=%v", compiled, err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "compiler.c")
	exe := filepath.Join(dir, "alder1")
	if err := os.WriteFile(cfile, []byte(compiled.Artifact.Text), 0o644); err != nil {
		t.Fatal(err)
	}
	linkGeneratedProgram(t, cc, root, compileGeneratedObject(t, cc, root, cfile, alder1OptimizeFlags()...), filepath.Join(root, "bootstrap", "alder_host.c"), exe, alder1LinkFlags()...)
	return exe
}

func assertAlder1VerifiedArtifact(t *testing.T, exe, cc, root, object string, noGo []string, files map[string]string, source string, extra string, want int) {
	t.Helper()
	private := privateProfileFiles(files)
	alderArgs := func(kind string) []string {
		args := []string{"compile", kind}
		if private {
			args = append(args, "--bootstrap-private")
		}
		return append(args, source)
	}
	first := runAlder1(t, exe, noGo, files, alderArgs("--emit=mir")...)
	second := runAlder1(t, exe, noGo, files, alderArgs("--emit=mir")...)
	if first.status != 0 || first.stderr != "" || !strings.HasPrefix(first.stdout, "mir 5\n") || first != second {
		t.Fatalf("MIR failed or was nondeterministic: first=%+v second=%+v", first, second)
	}
	module, err := mir.Parse(first.stdout)
	if err != nil {
		t.Fatalf("parse alder1 MIR: %v\n%s", err, first.stdout)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("independently verify alder1 MIR: %s\n%s", verify.Errors(diagnostics).String(), first.stdout)
	}
	cFirst := runAlder1(t, exe, noGo, files, alderArgs("--emit=c")...)
	cSecond := runAlder1(t, exe, noGo, files, alderArgs("--emit=c")...)
	if cFirst.status != 0 || cFirst.stderr != "" || !strings.HasPrefix(cFirst.stdout, "/* Generated by the Alder C11 backend.") || cFirst.stdout != cSecond.stdout {
		t.Fatalf("C failed or was nondeterministic: first=%+v second=%+v", cFirst, cSecond)
	}
	if extra == "" {
		compileAndRunProductionArtifact(t, cc, root, object, cFirst.stdout, want)
		return
	}
	compileAndRunWithExtras(t, cc, root, object, cFirst.stdout, extra, want)
}

func assertAlder1RejectsLikeGo(t *testing.T, exe string, noGo []string, files map[string]string, source string) {
	t.Helper()
	text := files[source]
	compileOracle := frontend.CompileSource
	if privateProfileReject[source] {
		compileOracle = frontend.CompileSourcePrivate
	}
	oracle, diagnostics, err := compileOracle(frontend.Source{ID: 1, Path: source, Text: text})
	if err != nil || oracle != nil || len(diagnostics) == 0 {
		t.Fatalf("Go diagnostic oracle: module=%v diagnostics=%+v error=%v", oracle, diagnostics, err)
	}
	want := diagnostics[0]
	// The bootstrap diagnostic payload retains a nominal type's symbol ID but
	// does not carry its spelling into the production driver yet.
	if source == "map-value-string.al" {
		want.Message = strings.ReplaceAll(want.Message, "Wrapped", "<unknown>")
	}
	src := frontend.Source{ID: 1, Path: source, Text: text}
	startLine, startColumn := src.LineColumn(want.Primary.Start)
	wantHuman := fmt.Sprintf("%s:%d:%d: %s[%s]: %s\n", source, startLine, startColumn, want.Severity, want.Code, want.Message)

	var firstHuman, firstJSON string
	rejectArgs := func(format string) []string {
		args := []string{"compile"}
		if format != "" {
			args = append(args, format)
		}
		if privateProfileReject[source] {
			args = append(args, "--bootstrap-private")
		}
		return append(args, "--emit=mir", "-o", "out.mir", source)
	}
	for range 2 {
		root := t.TempDir()
		human := runAlder1AtRoot(t, exe, root, noGo, files, rejectArgs("")...)
		if human.status != 1 || human.stdout != "" || !strings.HasPrefix(human.stderr, wantHuman) {
			t.Fatalf("human diagnostic mismatch: got=%+v want prefix=%q", human, wantHuman)
		}
		if len(want.Related) != 0 && !strings.Contains(human.stderr, "related:") {
			t.Fatalf("human diagnostic missing related range: %q", human.stderr)
		}
		assertProductionArtifactAbsent(t, root)
		machine := runAlder1AtRoot(t, exe, root, noGo, files, rejectArgs("--format=json")...)
		envelope := decodeProductionEnvelope(t, machine.stdout)
		if machine.status != 1 || machine.stderr != "" || envelope.Artifact != nil || len(envelope.Diagnostics) != 1 {
			t.Fatalf("JSON reject protocol: result=%+v envelope=%+v", machine, envelope)
		}
		got := envelope.Diagnostics[0]
		if got.Code != string(want.Code) || got.Message != want.Message || got.Range.Path != source ||
			got.Range.StartByte != want.Primary.Start || got.Range.EndByte != want.Primary.End {
			t.Fatalf("JSON diagnostic mismatch: got=%+v want=%+v", got, want)
		}
		assertProductionArtifactAbsent(t, root)
		if firstHuman == "" {
			firstHuman, firstJSON = human.stderr, machine.stdout
		} else if human.stderr != firstHuman || machine.stdout != firstJSON {
			t.Fatal("reject diagnostics changed across fresh processes")
		}
	}
}

func extraSymbolsFor(name string) string {
	switch name {
	case "ffi":
		return `static int64_t g_value = 0;
uint64_t magic(uint64_t v) { return v + 2; }
void store(int64_t v) { g_value = v; }
int64_t load(void) { return g_value; }
`
	case "cleanup":
		return `static int64_t g_count = 0;
void counter(int64_t v) { g_count += v; }
int64_t read_counter(void) { return g_count; }
`
	default:
		return ""
	}
}

func compileAndRunWithExtras(t *testing.T, cc, root, object, generated, extra string, want int) {
	t.Helper()
	dir := t.TempDir()
	cfile := filepath.Join(dir, "program.c")
	driver := filepath.Join(dir, "driver.c")
	exe := filepath.Join(dir, "program")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	text := `#include "alder_host.h"
#include <stdint.h>
` + extra + `
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	if err := os.WriteFile(driver, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cfile, driver, object, "-o", exe}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict generated C compile: %v\n%s", err, output)
	}
	err := exec.Command(exe).Run()
	if want == 0 {
		if err != nil {
			t.Fatalf("generated program status: err=%v want=0", err)
		}
		return
	}
	var exit *exec.ExitError
	if !errors.As(err, &exit) || exit.ExitCode() != want {
		t.Fatalf("generated program status: err=%v want=%d", err, want)
	}
}

func runAlder1(t *testing.T, exe string, env []string, files map[string]string, args ...string) productionResult {
	t.Helper()
	return runAlder1AtRoot(t, exe, t.TempDir(), env, files, args...)
}

func runAlder1AtRoot(t *testing.T, exe, dir string, env []string, files map[string]string, args ...string) productionResult {
	t.Helper()
	for name, text := range files {
		path := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	tmp := filepath.Join(dir, "tmp")
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		t.Fatal(err)
	}
	cmd.Env = append(append([]string{}, env...), "TMPDIR="+tmp)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("run alder1: %v", err)
		}
		status = exit.ExitCode()
	}
	return productionResult{status: status, stdout: stdout.String(), stderr: stderr.String()}
}

func noGoEnv(t *testing.T, cc string) []string {
	t.Helper()
	pathList := []string{filepath.Dir(cc)}
	if runtime.GOOS == "windows" {
		if systemRoot := os.Getenv("SystemRoot"); systemRoot != "" {
			pathList = append(pathList, filepath.Join(systemRoot, "System32"))
		}
	} else {
		pathList = append(pathList, "/usr/bin", "/bin")
	}
	env := os.Environ()
	out := make([]string, 0, len(env))
	for _, item := range env {
		if strings.HasPrefix(strings.ToUpper(item), "PATH=") {
			continue
		}
		out = append(out, item)
	}
	out = append(out, "PATH="+strings.Join(pathList, string(os.PathListSeparator)))
	probe := "command"
	args := []string{"-v", "go"}
	if runtime.GOOS == "windows" {
		probe = "where"
		args = []string{"go"}
	}
	cmd := exec.Command(probe, args...)
	cmd.Env = out
	if output, err := cmd.CombinedOutput(); err == nil {
		t.Fatalf("constructed PATH still contains a go executable:\n%s", output)
	}
	return out
}

func TestAlder1CompilesCompilerSource(t *testing.T) {
	if os.Getenv("ALDER_BOOTSTRAP_SELFCOMPILE") == "" {
		t.Skip("set ALDER_BOOTSTRAP_SELFCOMPILE=1 to run alder1 on compiler/src")
	}
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
	exe := buildAlder1(t, cc, root)
	noGo := noGoEnv(t, cc)
	files := make(map[string]string, len(compilerSourceManifest))
	compileArgs := []string{"compile", "--emit=c", "--bootstrap-private"}
	for _, name := range compilerSourceManifest {
		files[name] = readBootstrapFixture(t, root, filepath.Join("compiler", "src", name))
		compileArgs = append(compileArgs, name)
	}
	c2 := runAlder1(t, exe, noGo, files, compileArgs...)
	if c2.status != 0 || c2.stderr != "" || !strings.HasPrefix(c2.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("alder1 compile of compiler/src failed: %+v", c2)
	}
	dir := t.TempDir()
	c2file := filepath.Join(dir, "c2.c")
	if err := os.WriteFile(c2file, []byte(c2.stdout), 0o644); err != nil {
		t.Fatal(err)
	}
	alder2 := filepath.Join(dir, "alder2")
	linkGeneratedProgram(t, cc, root, compileGeneratedObject(t, cc, root, c2file, alder1OptimizeFlags()...), filepath.Join(root, "bootstrap", "alder_host.c"), alder2, alder1LinkFlags()...)
	c3 := runAlder1(t, alder2, noGo, files, compileArgs...)
	if c3.status != 0 || c3.stderr != "" || c3.stdout != c2.stdout {
		t.Fatalf("fixed point failed: c3=%+v c2_len=%d", c3, len(c2.stdout))
	}
}

func TestCommittedSourceBootstrap(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	order, err := os.ReadFile(filepath.Join(root, "bootstrap", "compiler-sources.order"))
	if err != nil {
		t.Fatal(err)
	}
	wantOrder := "ALDER-COMPILER-ORDER 1\n"
	for _, name := range compilerSourceManifest {
		wantOrder += "compiler/src/" + name + "\n"
	}
	if string(order) != wantOrder {
		t.Fatal("committed compiler source order differs from compilerSourceManifest")
	}
	inventory, err := os.ReadFile(filepath.Join(root, "bootstrap", "compiler-sources.manifest"))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(inventory), "\n")
	if len(lines) != len(compilerSourceManifest)+3 || lines[0] != "ALDER-COMPILER-SOURCES 1" || lines[len(lines)-1] != "" {
		t.Fatal("committed compiler source inventory has an unexpected entry count or framing")
	}
	inventoried := make(map[string]bool, len(compilerSourceManifest))
	for _, line := range lines[1 : len(lines)-2] {
		fields := strings.Split(line, " ")
		if len(fields) != 3 || inventoried[fields[2]] {
			t.Fatal("committed compiler source inventory has a malformed or duplicate entry")
		}
		inventoried[fields[2]] = true
	}
	for _, name := range compilerSourceManifest {
		if !inventoried["compiler/src/"+name] {
			t.Fatalf("committed compiler source inventory is missing %s", name)
		}
	}
	bootstrap, err := os.ReadFile(filepath.Join(root, "bootstrap", "alder.c"))
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(bootstrap)
	if got, want := fmt.Sprintf("%x", digest), "d47b039ce5c007fbd779f5e9b0f1b47101694fd64bf7ee2f661fc269dc90fda4"; got != want {
		t.Fatalf("bootstrap/alder.c digest = %s, want %s", got, want)
	}
}

func readBootstrapFixture(t *testing.T, root, rel string) string {
	t.Helper()
	text, err := os.ReadFile(filepath.Join(root, rel))
	if err != nil {
		t.Fatal(err)
	}
	return string(text)
}
