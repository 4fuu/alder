package compiler

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"

	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

type productionResult struct {
	status int
	stdout string
	stderr string
}

type productionEnvelope struct {
	Version     int `json:"version"`
	Command     string
	Success     bool
	Diagnostics []struct {
		Code     string
		Severity string
		Message  string
		Range    struct {
			Path               string
			StartByte, EndByte int
			Start, End         struct{ Line, Column int }
		}
		Related []struct {
			Message string
			Range   struct{ Path string }
		}
		Notes []string
	}
	Artifact *struct {
		Kind, Content, Path string
	}
	Failure *struct{ Kind, Message string }
}

type sharedProductionBuildResult struct {
	dir, object, exe string
	err              error
}

var (
	sharedProductionBuildOnce sync.Once
	sharedProductionBuild     sharedProductionBuildResult
)

// TestMain keeps the ordinary tests' shared compiler executable alive until
// every parallel package test has finished, without caching between go test
// processes.
func TestMain(m *testing.M) {
	code := m.Run()
	if sharedProductionBuild.dir != "" {
		_ = os.RemoveAll(sharedProductionBuild.dir)
	}
	os.Exit(code)
}

func getSharedProductionBuild(t *testing.T, cc, root string) (object, exe, dir string) {
	t.Helper()
	sharedProductionBuildOnce.Do(func() {
		sharedProductionBuild = buildSharedProductionCompiler(cc, root)
	})
	if sharedProductionBuild.err != nil {
		t.Fatalf("build shared production compiler: %v", sharedProductionBuild.err)
	}
	return sharedProductionBuild.object, sharedProductionBuild.exe, sharedProductionBuild.dir
}

func buildSharedProductionCompiler(cc, root string) sharedProductionBuildResult {
	result := sharedProductionBuildResult{}
	dir, err := os.MkdirTemp("", "alder-production-test-")
	if err != nil {
		result.err = err
		return result
	}
	result.dir = dir
	var sources []frontend.Source
	for i, name := range compilerSourceManifest {
		text, readErr := os.ReadFile(filepath.Join(root, "compiler", "src", name))
		if readErr != nil {
			result.err = readErr
			return result
		}
		sources = append(sources, frontend.Source{ID: frontend.SourceID(i + 1), Path: "compiler/src/" + name, Text: string(text)})
	}
	compiled, compileErr := Compile(Request{Sources: sources, Emit: EmitC})
	if compileErr != nil || compiled.Artifact == nil || len(compiled.Diagnostics) != 0 {
		result.err = fmt.Errorf("compile production root: result=%+v error=%v", compiled, compileErr)
		return result
	}
	cfile := filepath.Join(dir, "compiler.c")
	result.object = cfile + ".o"
	result.exe = filepath.Join(dir, "alder1")
	if err = os.WriteFile(cfile, []byte(compiled.Artifact.Text), 0o644); err != nil {
		result.err = err
		return result
	}
	strict := strictC11Flags()
	compileArgs := append(append([]string{}, strict...), "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), "-c", cfile, "-o", result.object)
	if output, commandErr := exec.Command(cc, compileArgs...).CombinedOutput(); commandErr != nil {
		result.err = fmt.Errorf("strict C11 compile: %w\n%s", commandErr, output)
		return result
	}
	linkArgs := append(append([]string{}, strict...), alder1LinkFlags()...)
	linkArgs = append(linkArgs,
		fmt.Sprintf("-DALDER_HOST_RUNTIME_C=\"%s\"", filepath.Join(root, "runtime", "c", "alder.c")),
		fmt.Sprintf("-DALDER_HOST_RUNTIME_INCLUDE_DIR=\"%s\"", filepath.Join(root, "runtime", "c")),
		fmt.Sprintf("-DALDER_HOST_INCLUDE_DIR=\"%s\"", filepath.Join(root, "bootstrap")),
	)
	linkArgs = append(linkArgs, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), result.object, filepath.Join(root, "bootstrap", "alder_host.c"), filepath.Join(root, "runtime", "c", "alder.c"), "-o", result.exe)
	if output, commandErr := exec.Command(cc, linkArgs...).CombinedOutput(); commandErr != nil {
		result.err = fmt.Errorf("strict C11 link: %w\n%s", commandErr, output)
	}
	return result
}

func TestAlderProductionDriverEndToEnd(t *testing.T) {
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

	object, exe, dir := getSharedProductionBuild(t, cc, root)
	testProductionInjectedFailure(t, cc, root, object, dir, true, 3)
	testProductionInjectedFailure(t, cc, root, object, dir, false, 3)

	valid := map[string]string{
		"a/helper.al": "fn helper() -> I32 { return 7 }\n",
		"z/main.al":   "fn main() -> I32 { return helper() }\n",
	}
	check := runProductionCompiler(t, exe, valid, "check", "z/main.al", "a/helper.al")
	if check != (productionResult{}) {
		t.Fatalf("check emitted output or failed: %+v", check)
	}
	jsonCheck := runProductionCompiler(t, exe, valid, "check", "--format=json", "a/helper.al", "z/main.al")
	checkEnvelope := decodeProductionEnvelope(t, jsonCheck.stdout)
	if jsonCheck.status != 0 || jsonCheck.stderr != "" || !checkEnvelope.Success || checkEnvelope.Artifact != nil {
		t.Fatalf("JSON check result: %+v envelope=%+v", jsonCheck, checkEnvelope)
	}
	project := map[string]string{
		"alder.toml":        "manifest = 1\nedition = \"1\"\n\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al":       "module hello.main\n\nimport hello.util { helper }\n\npub fn main() -> I32 { return helper() }\n",
		"src/util.al":       "module hello.util\n\npub fn helper() -> I32 { return 0 }\n",
		"src/unimported.al": "this file must not affect the selected target\n",
	}
	projectCheck := runProductionCompiler(t, exe, project, "check")
	if projectCheck != (productionResult{}) {
		t.Fatalf("project check failed: %+v", projectCheck)
	}
	projectJSON := runProductionCompiler(t, exe, project, "check", "--format=json")
	projectEnvelope := decodeProductionEnvelope(t, projectJSON.stdout)
	if projectJSON.status != 0 || projectJSON.stderr != "" || !projectEnvelope.Success || projectEnvelope.Artifact != nil {
		t.Fatalf("JSON project check result: %+v envelope=%+v", projectJSON, projectEnvelope)
	}
	plan := runProductionCompiler(t, exe, project, "test-plan")
	triple := productionHostTriple()
	wantPlan := "ALDER-BUILD-PLAN 1\nedition 1\ntarget hello\nkind bin\nprofile debug\ntriple " + triple + "\ntoolchain system-cc-c11\nflags strict-c11,O0\nsysroot compiler-coupled-v1\nsnapshot poly64-v1:43a83e5f2cf81c50\npackage hello\nroot src/main.al\noutput c build/" + triple + "/debug/hello/hello.c\noutput executable build/" + triple + "/debug/hello/hello\nsource src/main.al bytes 90 poly64-v1:2c61e11e166e386b module hello.main\nsource src/util.al bytes 55 poly64-v1:44cb2f09be53d6de module hello.util\nedge hello.main -> hello.util\n"
	if plan.status != 0 || plan.stderr != "" || plan.stdout != wantPlan {
		t.Fatalf("project test plan: %+v want stdout %q", plan, wantPlan)
	}
	planRepeat := runProductionCompiler(t, exe, project, "test-plan", "--triple="+triple)
	if planRepeat != plan {
		t.Fatalf("project plan changed across workspace/process: first=%+v repeat=%+v", plan, planRepeat)
	}
	jsonPlan := runProductionCompiler(t, exe, project, "test-plan", "--format=json")
	planEnvelope := decodeProductionEnvelope(t, jsonPlan.stdout)
	if jsonPlan.status != 0 || jsonPlan.stderr != "" || !planEnvelope.Success || planEnvelope.Artifact == nil || planEnvelope.Artifact.Kind != "build-plan" || planEnvelope.Artifact.Content != plan.stdout {
		t.Fatalf("JSON project plan result: %+v envelope=%+v", jsonPlan, planEnvelope)
	}
	releasePlan := runProductionCompiler(t, exe, project, "test-plan", "--release")
	if releasePlan.status != 0 || releasePlan.stderr != "" || !strings.Contains(releasePlan.stdout, "\nprofile release\n") || !strings.Contains(releasePlan.stdout, "\nflags strict-c11,O2\n") || !strings.Contains(releasePlan.stdout, "/release/hello/hello.c\n") {
		t.Fatalf("release project plan: %+v", releasePlan)
	}
	unsupportedTriple := runProductionCompiler(t, exe, project, "test-plan", "--triple=unsupported-none")
	if unsupportedTriple.status != 2 || unsupportedTriple.stdout != "" || !strings.Contains(unsupportedTriple.stderr, "not supported") {
		t.Fatalf("unsupported triple result: %+v", unsupportedTriple)
	}
	build := runProductionCompiler(t, exe, project, "build")
	if build != (productionResult{}) {
		t.Fatalf("project build failed: %+v", build)
	}
	projectRoot := t.TempDir()
	runResult := runProductionCompilerAtRoot(t, exe, projectRoot, project, "run")
	if runResult != (productionResult{}) {
		t.Fatalf("project run failed: %+v", runResult)
	}
	for _, path := range []string{"build/" + triple + "/debug/hello/hello.c", "build/" + triple + "/debug/hello/hello"} {
		if info, statErr := os.Stat(filepath.Join(projectRoot, filepath.FromSlash(path))); statErr != nil || info.IsDir() {
			t.Fatalf("missing project output %s: info=%v err=%v", path, info, statErr)
		}
	}
	secondBuildRoot := t.TempDir()
	secondBuild := runProductionCompilerAtRoot(t, exe, secondBuildRoot, project, "build")
	firstC, firstCErr := os.ReadFile(filepath.Join(projectRoot, "build", triple, "debug", "hello", "hello.c"))
	secondC, secondCErr := os.ReadFile(filepath.Join(secondBuildRoot, "build", triple, "debug", "hello", "hello.c"))
	if secondBuild != (productionResult{}) || firstCErr != nil || secondCErr != nil || !bytes.Equal(firstC, secondC) {
		t.Fatalf("project C changed across workspace roots: build=%+v firstErr=%v secondErr=%v", secondBuild, firstCErr, secondCErr)
	}
	libProject := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.api]\nkind = \"lib\"\nroot = \"src/lib.al\"\n",
		"src/lib.al": "module hello\npub fn answer() -> I32 { return 42 }\n",
	}
	libRoot := t.TempDir()
	libBuild := runProductionCompilerAtRoot(t, exe, libRoot, libProject, "build")
	if libBuild != (productionResult{}) {
		t.Fatalf("library project build failed: %+v", libBuild)
	}
	if _, statErr := os.Stat(filepath.Join(libRoot, "build", triple, "debug", "hello", "libapi.o")); statErr != nil {
		t.Fatalf("missing library object: %v", statErr)
	}
	moduleCases := []struct {
		name  string
		files map[string]string
		good  bool
	}{
		{"namespace-default", map[string]string{
			"src/main.al": "module hello.main\nimport hello.util\npub fn main() -> I32 { return util.helper() }\n",
			"src/util.al": "module hello.util\npub fn helper() -> I32 { return 0 }\n",
		}, true},
		{"namespace-alias-qualified-type", map[string]string{
			"src/main.al":  "module hello.main\nimport hello.types as t\nfn pass(x: t.Box) -> t.Box { return x }\npub fn main() -> I32 { return 0 }\n",
			"src/types.al": "module hello.types\npub type Box { value: U64 }\n",
		}, true},
		{"selected-reexport", map[string]string{
			"src/main.al":     "module hello.main\nimport hello.api { helper }\npub fn main() -> I32 { return helper() }\n",
			"src/api.al":      "module hello.api\npub import hello.internal { helper }\n",
			"src/internal.al": "module hello.internal\npub fn helper() -> I32 { return 0 }\n",
		}, true},
		{"same-name-isolated", map[string]string{
			"src/main.al": "module hello.main\nimport hello.a as a\nimport hello.b as b\npub fn main() -> I32 { return a.helper() - b.helper() }\n",
			"src/a.al":    "module hello.a\npub fn helper() -> I32 { return 0 }\n",
			"src/b.al":    "module hello.b\npub fn helper() -> I32 { return 0 }\n",
		}, true},
		{"import-after-declaration", map[string]string{
			"src/main.al": "module hello.main\nfn local() -> I32 { return 1 }\nimport hello.util { helper }\npub fn main() -> I32 { return helper() - 1 }\n",
			"src/util.al": "module hello.util\npub fn helper() -> I32 { return 1 }\n",
		}, true},
		{"private-selected", map[string]string{
			"src/main.al": "module hello.main\nimport hello.util { helper }\npub fn main() -> I32 { return helper() }\n",
			"src/util.al": "module hello.util\nfn helper() -> I32 { return 0 }\n",
		}, false},
		{"unknown-selected", map[string]string{
			"src/main.al": "module hello.main\nimport hello.util { missing }\npub fn main() -> I32 { return missing() }\n",
			"src/util.al": "module hello.util\npub fn helper() -> I32 { return 0 }\n",
		}, false},
		{"selected-local-collision", map[string]string{
			"src/main.al": "module hello.main\nimport hello.util { helper }\nfn helper() -> I32 { return 1 }\npub fn main() -> I32 { return helper() }\n",
			"src/util.al": "module hello.util\npub fn helper() -> I32 { return 0 }\n",
		}, false},
		{"selected-import-collision", map[string]string{
			"src/main.al": "module hello.main\nimport hello.a { helper }\nimport hello.b { helper }\npub fn main() -> I32 { return 0 }\n",
			"src/a.al":    "module hello.a\npub fn helper() -> I32 { return 0 }\n",
			"src/b.al":    "module hello.b\npub fn helper() -> I32 { return 1 }\n",
		}, false},
		{"namespace-local-collision", map[string]string{
			"src/main.al": "module hello.main\nimport hello.util\nfn util() -> I32 { return 0 }\npub fn main() -> I32 { return 0 }\n",
			"src/util.al": "module hello.util\npub fn helper() -> I32 { return 0 }\n",
		}, false},
		{"namespace-alias-collision", map[string]string{
			"src/main.al": "module hello.main\nimport hello.a as shared\nimport hello.b as shared\npub fn main() -> I32 { return 0 }\n",
			"src/a.al":    "module hello.a\npub fn helper() -> I32 { return 0 }\n",
			"src/b.al":    "module hello.b\npub fn helper() -> I32 { return 1 }\n",
		}, false},
		{"invalid-namespace-reexport", map[string]string{
			"src/main.al": "module hello.main\npub import hello.util\npub fn main() -> I32 { return 0 }\n",
			"src/util.al": "module hello.util\npub fn helper() -> I32 { return 0 }\n",
		}, false},
		{"unused-private-selected", map[string]string{
			"src/main.al": "module hello.main\nimport hello.util { helper }\npub fn main() -> I32 { return 0 }\n",
			"src/util.al": "module hello.util\nfn helper() -> I32 { return 0 }\n",
		}, false},
		{"public-signature-private-type", map[string]string{
			"src/main.al": "module hello.main\ntype Hidden { value: U64 }\npub fn expose(value: Hidden) -> Hidden { return value }\npub fn main() -> I32 { return 0 }\n",
		}, false},
	}
	for _, tc := range moduleCases {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{"alder.toml": project["alder.toml"]}
			for path, text := range tc.files {
				files[path] = text
			}
			got := runProductionCompiler(t, exe, files, "check")
			if tc.good && got != (productionResult{}) {
				t.Fatalf("module check failed: %+v", got)
			}
			if !tc.good && got.status == 0 {
				t.Fatalf("module rejection status: %+v", got)
			}
		})
	}
	cycleProject := map[string]string{
		"alder.toml":  project["alder.toml"],
		"src/main.al": "module hello.main\nimport hello.util\npub fn main() -> I32 { return 0 }\n",
		"src/util.al": "module hello.util\nimport hello.main\npub fn helper() -> I32 { return 0 }\n",
	}
	cycle := runProductionCompiler(t, exe, cycleProject, "check")
	if cycle.status != 2 || cycle.stdout != "" || !strings.Contains(cycle.stderr, "module import cycle") {
		t.Fatalf("project cycle result: %+v", cycle)
	}
	duplicatePackage := map[string]string{
		"alder.toml": project["alder.toml"] + "\n[package]\nname = \"again\"\n",
	}
	duplicateManifest := runProductionCompiler(t, exe, duplicatePackage, "check")
	if duplicateManifest.status != 2 || duplicateManifest.stdout != "" || !strings.Contains(duplicateManifest.stderr, "duplicate") {
		t.Fatalf("duplicate manifest table result: %+v", duplicateManifest)
	}
	manifestCases := []struct {
		name, manifest, message string
		good                    bool
	}{
		{"crlf-comments", "# project\r\nmanifest = 1\r\nedition = \"1\" # edition\r\n[package]\r\nname = \"hello\"\r\nversion = \"0.1.0\"\r\n[targets.hello]\r\nkind = \"bin\"\r\nroot = \"src/main.al\"\r\n", "", true},
		{"duplicate-key", "manifest = 1\nmanifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n", "duplicate", false},
		{"unknown-field", "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\nunknown = true\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n", "malformed", false},
		{"noncanonical-root", "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/../main.al\"\n", "malformed", false},
		{"roadmap-gated-dependency", project["alder.toml"] + "\n[dependencies]\n", "roadmap gate", false},
	}
	for _, tc := range manifestCases {
		got := runProductionCompiler(t, exe, map[string]string{"alder.toml": tc.manifest, "src/main.al": "module hello.main\npub fn main() -> I32 { return 0 }\n"}, "check")
		if tc.good && got != (productionResult{}) {
			t.Fatalf("manifest %s failed: %+v", tc.name, got)
		}
		if !tc.good && (got.status != 2 || got.stdout != "" || !strings.Contains(got.stderr, tc.message)) {
			t.Fatalf("manifest %s rejection: %+v", tc.name, got)
		}
	}
	projectSourceCases := []struct {
		name, main, message string
	}{
		{"module-path-mismatch", "module wrong.main\npub fn main() -> I32 { return 0 }\n", "canonical path"},
		{"missing-import", "module hello.main\nimport hello.missing\npub fn main() -> I32 { return 0 }\n", "unavailable"},
		{"duplicate-module-declaration", "module hello.main\nmodule hello.main\npub fn main() -> I32 { return 0 }\n", "canonical path"},
	}
	for _, tc := range projectSourceCases {
		got := runProductionCompiler(t, exe, map[string]string{"alder.toml": project["alder.toml"], "src/main.al": tc.main}, "check")
		if got.status != 2 || got.stdout != "" || !strings.Contains(got.stderr, tc.message) {
			t.Fatalf("project source %s rejection: %+v", tc.name, got)
		}
	}
	multipleTargets := map[string]string{
		"alder.toml":   "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.first]\nkind = \"bin\"\nroot = \"src/main.al\"\n[targets.second]\nkind = \"bin\"\nroot = \"src/other.al\"\n",
		"src/main.al":  "module hello.main\npub fn main() -> I32 { return 0 }\n",
		"src/other.al": "module hello.other\npub fn main() -> I32 { return 0 }\n",
	}
	missingTarget := runProductionCompiler(t, exe, multipleTargets, "check")
	selectedTarget := runProductionCompiler(t, exe, multipleTargets, "check", "--target=second")
	if missingTarget.status != 2 || !strings.Contains(missingTarget.stderr, "target must be specified") || selectedTarget != (productionResult{}) {
		t.Fatalf("multi-target selection: missing=%+v selected=%+v", missingTarget, selectedTarget)
	}

	orders := [][]string{{"z/main.al", "a/helper.al"}, {"a/helper.al", "z/main.al"}, {"z/main.al", "a/helper.al"}}
	var mirText string
	for _, order := range orders {
		args := append([]string{"compile", "--emit=mir"}, order...)
		got := runProductionCompiler(t, exe, valid, args...)
		if got.status != 0 || got.stderr != "" || !strings.HasPrefix(got.stdout, "mir 4\n") {
			t.Fatalf("MIR result for %v: %+v", order, got)
		}
		if mirText != "" && got.stdout != mirText {
			t.Fatal("MIR changed with source permutation or repeat process")
		}
		mirText = got.stdout
	}
	module, err := mir.Parse(mirText)
	if err != nil {
		t.Fatalf("parse production MIR: %v", err)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("independently verify production MIR: %s", verify.Errors(diagnostics).String())
	}
	otherRoot := runProductionCompiler(t, exe, valid, "compile", "--emit=mir", "a/helper.al", "z/main.al")
	if otherRoot.stdout != mirText {
		t.Fatal("MIR changed across workspace roots")
	}
	testProductionLocalNameUniqueness(t, cc, root, exe)
	optionText, err := os.ReadFile(filepath.Join(root, "frontend", "testdata", "e2e", "option.al"))
	if err != nil {
		t.Fatal(err)
	}
	optionFiles := map[string]string{"option.al": string(optionText)}
	optionOne := runProductionCompiler(t, exe, optionFiles, "compile", "--emit=mir", "option.al")
	optionTwo := runProductionCompiler(t, exe, optionFiles, "compile", "--emit=mir", "option.al")
	if optionOne.status != 0 || optionOne.stderr != "" || optionOne.stdout == "" || optionTwo != optionOne {
		t.Fatalf("Option MIR was not successful and deterministic: first=%+v second=%+v", optionOne, optionTwo)
	}
	optionModule, err := mir.Parse(optionOne.stdout)
	if err != nil {
		t.Fatalf("parse Option MIR: %v", err)
	}
	if diagnostics := verify.Module(optionModule); len(diagnostics) != 0 {
		t.Fatalf("independently verify Option MIR: %s", verify.Errors(diagnostics).String())
	}
	optionC := runProductionCompiler(t, exe, optionFiles, "compile", "--emit=c", "option.al")
	if optionC.status != 0 || optionC.stderr != "" || !strings.HasPrefix(optionC.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("Option C result: %+v", optionC)
	}
	compileAndRunProductionArtifact(t, cc, root, optionC.stdout, 0)

	jsonMIR := runProductionCompiler(t, exe, valid, "compile", "--format=json", "--emit=mir", "z/main.al", "a/helper.al")
	mirEnvelope := decodeProductionEnvelope(t, jsonMIR.stdout)
	if jsonMIR.status != 0 || jsonMIR.stderr != "" || mirEnvelope.Artifact == nil || mirEnvelope.Artifact.Kind != "mir" || mirEnvelope.Artifact.Content != mirText {
		t.Fatalf("JSON MIR artifact separation: %+v envelope=%+v", jsonMIR, mirEnvelope)
	}

	cOutput := runProductionCompiler(t, exe, valid, "compile", "--emit=c", "z/main.al", "a/helper.al")
	if cOutput.status != 0 || cOutput.stderr != "" || !strings.HasPrefix(cOutput.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("C result: %+v", cOutput)
	}
	compileAndRunProductionArtifact(t, cc, root, cOutput.stdout, 7)
	jsonC := runProductionCompiler(t, exe, valid, "compile", "--format=json", "--emit=c", "-o", "out.c", "a/helper.al", "z/main.al")
	cEnvelope := decodeProductionEnvelope(t, jsonC.stdout)
	if jsonC.status != 0 || jsonC.stderr != "" || cEnvelope.Artifact == nil || cEnvelope.Artifact.Kind != "c" || cEnvelope.Artifact.Path != "out.c" || cEnvelope.Artifact.Content != "" {
		t.Fatalf("JSON C file result: %+v envelope=%+v", jsonC, cEnvelope)
	}

	rejections := []struct {
		name, text, code string
	}{
		{"lex.al", ";\n", "LEX0001"},
		{"parse.al", "type Broken { value U64 }\n", "SYN0001"},
		{"check.al", "type Broken { value: Missing }\n", "SEM0001"},
	}
	for _, fixture := range rejections {
		t.Run(fixture.name, func(t *testing.T) {
			files := map[string]string{fixture.name: fixture.text}
			human := runProductionCompiler(t, exe, files, "compile", "--emit=mir", fixture.name)
			machine := runProductionCompiler(t, exe, files, "compile", "--format=json", "--emit=mir", fixture.name)
			envelope := decodeProductionEnvelope(t, machine.stdout)
			if human.status != 1 || human.stdout != "" || !strings.Contains(human.stderr, fixture.code) || machine.status != 1 || machine.stderr != "" || len(envelope.Diagnostics) != 1 || envelope.Diagnostics[0].Code != fixture.code || envelope.Artifact != nil {
				t.Fatalf("diagnostic mismatch: human=%+v machine=%+v envelope=%+v", human, machine, envelope)
			}
			if !strings.Contains(human.stderr, envelope.Diagnostics[0].Range.Path+":") || !strings.Contains(human.stderr, envelope.Diagnostics[0].Message) {
				t.Fatalf("human/JSON disagreement: human=%q envelope=%+v", human.stderr, envelope)
			}
		})
	}
	testProductionInvalidEscapeFacts(t, exe)
	duplicate := map[string]string{"a.al": "type clash { value: I64 }\n", "z.al": "fn clash() -> Unit { }\n"}
	related := runProductionCompiler(t, exe, duplicate, "check", "--format=json", "z.al", "a.al")
	relatedEnvelope := decodeProductionEnvelope(t, related.stdout)
	if related.status != 1 || len(relatedEnvelope.Diagnostics) != 1 || relatedEnvelope.Diagnostics[0].Range.Path != "z.al" || len(relatedEnvelope.Diagnostics[0].Related) != 1 || relatedEnvelope.Diagnostics[0].Related[0].Range.Path != "a.al" {
		t.Fatalf("primary/related ranges: %+v envelope=%+v", related, relatedEnvelope)
	}

	backend := runProductionCompiler(t, exe, map[string]string{"library.al": "fn helper() -> I32 { return 0 }\n"}, "compile", "--emit=c", "library.al")
	if backend.status != 4 || backend.stdout != "" || !strings.Contains(backend.stderr, "internal compiler failure") {
		t.Fatalf("backend refusal emitted bytes or wrong class: %+v", backend)
	}
	for _, args := range [][]string{{}, {"bogus"}, {"check", "x.AL"}, {"check", "../x.al"}, {"check", "same.al", "same.al"}, {"compile", "--emit=nope", "x.al"}} {
		got := runProductionCompiler(t, exe, nil, args...)
		if got.status != 2 || got.stdout != "" {
			t.Fatalf("malformed request %v: %+v", args, got)
		}
	}
	projectMissing := runProductionCompiler(t, exe, nil, "check")
	if projectMissing.status != 3 || projectMissing.stdout != "" || !strings.Contains(projectMissing.stderr, "alder.toml") {
		t.Fatalf("project manifest I/O class: %+v", projectMissing)
	}
	missing := runProductionCompiler(t, exe, nil, "check", "missing.al")
	if missing.status != 3 || missing.stdout != "" {
		t.Fatalf("input I/O class: %+v", missing)
	}
	missingJSON := runProductionCompiler(t, exe, nil, "check", "--format=json", "missing.al")
	missingEnvelope := decodeProductionEnvelope(t, missingJSON.stdout)
	if missingJSON.status != 3 || missingJSON.stderr != "" || missingEnvelope.Failure == nil || missingEnvelope.Failure.Kind != "io" {
		t.Fatalf("JSON input I/O class: %+v envelope=%+v", missingJSON, missingEnvelope)
	}
}

func productionHostTriple() string {
	switch runtime.GOOS + "/" + runtime.GOARCH {
	case "linux/amd64":
		return "x86_64-unknown-linux-gnu"
	case "linux/arm64":
		return "aarch64-unknown-linux-gnu"
	case "darwin/amd64":
		return "x86_64-apple-darwin"
	case "darwin/arm64":
		return "aarch64-apple-darwin"
	case "windows/amd64":
		return "x86_64-pc-windows-msvc"
	case "windows/arm64":
		return "aarch64-pc-windows-msvc"
	default:
		return "unknown-host"
	}
}

func testProductionInvalidEscapeFacts(t *testing.T, exe string) {
	t.Helper()
	fixtures := []struct {
		name, text string
	}{
		{"earlier-valid.al", `let s = "a\nb\q"` + "\n"},
		// Two adjacent escaped backslashes precede the invalid escape.
		{"repeated-escapes.al", `let s = "\\\\\q"` + "\n"},
	}
	for _, fixture := range fixtures {
		t.Run(fixture.name, func(t *testing.T) {
			source := frontend.Source{ID: 1, Path: fixture.name, Text: fixture.text}
			_, diagnostics, err := frontend.CompileSource(source)
			if err != nil || len(diagnostics) != 1 {
				t.Fatalf("Go diagnostic oracle: diagnostics=%+v error=%v", diagnostics, err)
			}
			want := diagnostics[0]
			if want.Message != `invalid escape \q` {
				t.Fatalf("Go diagnostic oracle message = %q", want.Message)
			}
			startLine, startColumn := source.LineColumn(want.Primary.Start)
			endLine, endColumn := source.LineColumn(want.Primary.End)
			wantHuman := fmt.Sprintf("%s:%d:%d: %s[%s]: %s\n", source.Path, startLine, startColumn, want.Severity, want.Code, want.Message)
			var firstHuman, firstJSON string
			for attempt := 0; attempt < 3; attempt++ {
				root := t.TempDir()
				files := map[string]string{fixture.name: fixture.text}
				human := runProductionCompilerAtRoot(t, exe, root, files, "compile", "--emit=mir", "-o", "out.mir", fixture.name)
				if human.status != 1 || human.stdout != "" || human.stderr != wantHuman {
					t.Fatalf("human diagnostic mismatch: got=%+v want stderr=%q", human, wantHuman)
				}
				assertProductionArtifactAbsent(t, root)

				machine := runProductionCompilerAtRoot(t, exe, root, files, "compile", "--format=json", "--emit=mir", "-o", "out.mir", fixture.name)
				envelope := decodeProductionEnvelope(t, machine.stdout)
				if machine.status != 1 || machine.stderr != "" || envelope.Version != 1 || envelope.Command != "compile" || envelope.Success || envelope.Artifact != nil || envelope.Failure != nil || len(envelope.Diagnostics) != 1 {
					t.Fatalf("JSON diagnostic protocol mismatch: result=%+v envelope=%+v", machine, envelope)
				}
				got := envelope.Diagnostics[0]
				if got.Code != string(want.Code) || got.Severity != string(want.Severity) || got.Message != want.Message ||
					got.Range.Path != source.Path || got.Range.StartByte != want.Primary.Start || got.Range.EndByte != want.Primary.End ||
					got.Range.Start.Line != startLine || got.Range.Start.Column != startColumn || got.Range.End.Line != endLine || got.Range.End.Column != endColumn ||
					len(got.Related) != len(want.Related) || len(got.Notes) != len(want.Notes) {
					t.Fatalf("decoded JSON diagnostic mismatch: got=%+v want=%+v", got, want)
				}
				assertProductionArtifactAbsent(t, root)
				if attempt == 0 {
					firstHuman, firstJSON = human.stderr, machine.stdout
				} else if human.stderr != firstHuman || machine.stdout != firstJSON {
					t.Fatal("invalid-escape diagnostics changed across fresh processes or workspace roots")
				}
			}
		})
	}
}

func assertProductionArtifactAbsent(t *testing.T, root string) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(root, "out.mir")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("rejected compilation left output artifact: %v", err)
	}
	temps, err := filepath.Glob(filepath.Join(root, "out.mir.alder-tmp-*"))
	if err != nil || len(temps) != 0 {
		t.Fatalf("rejected compilation left temporary artifacts: paths=%v error=%v", temps, err)
	}
}

func testProductionLocalNameUniqueness(t *testing.T, cc, root, exe string) {
	t.Helper()
	files := map[string]string{"locals.al": `enum Choice {
    Left(value: U64)
    Right(value: U64)
}
fn repeated(value: Choice) -> U64 {
    {
        let unique: U64 = match value {
            Left(v) => v
            Right(v) => v
        }
        return unique
    }
}
fn separate(value: Choice) -> U64 {
    return match value {
        Left(v) => v
        Right(other) => other
    }
}
fn main() -> I32 {
    if repeated(Left(7)) != 7 { return 1 }
    if repeated(Right(8)) != 8 { return 2 }
    if separate(Left(9)) != 9 { return 3 }
    return 7
}
`}
	first := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "locals.al")
	second := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "locals.al")
	if first.status != 0 || first.stderr != "" || !strings.HasPrefix(first.stdout, "mir 4\n") || first.stdout != second.stdout {
		t.Fatalf("source-local MIR result is empty, failed, or nondeterministic: first=%+v second=%+v", first, second)
	}
	module, err := mir.Parse(first.stdout)
	if err != nil {
		t.Fatalf("parse source-local MIR: %v\n%s", err, first.stdout)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify source-local MIR through V1-V10: %s\n%s", verify.Errors(diagnostics).String(), first.stdout)
	}
	repeatedID, ok := module.Function("repeated")
	if !ok {
		t.Fatal("source-local MIR has no repeated function")
	}
	repeated := module.Functions[repeatedID]
	wantNames := []string{"v", "__s0_local_1", "unique"}
	if len(repeated.Locals) != len(wantNames) {
		t.Fatalf("repeated locals = %+v, want names %v", repeated.Locals, wantNames)
	}
	for i, want := range wantNames {
		if repeated.Locals[i].Name != want {
			t.Fatalf("repeated local %d name = %q, want %q", i, repeated.Locals[i].Name, want)
		}
	}
	separateID, ok := module.Function("separate")
	if !ok {
		t.Fatal("source-local MIR has no separate function")
	}
	separate := module.Functions[separateID]
	if len(separate.Locals) != 2 || separate.Locals[0].Name != "v" || separate.Locals[1].Name != "other" {
		t.Fatalf("same source name in separate function was changed: %+v", separate.Locals)
	}
	uses := make([]int, len(repeated.Locals))
	for _, block := range repeated.Blocks {
		for _, instruction := range block.Instrs {
			if instruction.Op == mir.OpLoad || instruction.Op == mir.OpStore {
				place := instruction.Place
				for place.Kind == mir.PlaceField {
					place = *place.Base
				}
				if place.Kind == mir.PlaceLocal && int(place.Local) < len(uses) {
					uses[place.Local]++
				}
			}
		}
	}
	if uses[2] == 0 {
		t.Fatalf("ordinary local declarations and references are not linked: use counts %v", uses)
	}
	cOutput := runProductionCompiler(t, exe, files, "compile", "--emit=c", "locals.al")
	cRepeat := runProductionCompiler(t, exe, files, "compile", "--emit=c", "locals.al")
	if cOutput.status != 0 || cOutput.stderr != "" || cOutput.stdout != cRepeat.stdout {
		t.Fatalf("source-local C result failed or was nondeterministic: first=%+v second=%+v", cOutput, cRepeat)
	}
	compileAndRunProductionArtifact(t, cc, root, cOutput.stdout, 7)
}

func decodeProductionEnvelope(t *testing.T, text string) productionEnvelope {
	t.Helper()
	decoder := json.NewDecoder(strings.NewReader(text))
	var envelope productionEnvelope
	if err := decoder.Decode(&envelope); err != nil {
		t.Fatalf("decode JSON envelope %q: %v", text, err)
	}
	var extra any
	if err := decoder.Decode(&extra); err == nil {
		t.Fatalf("more than one JSON envelope: %q", text)
	}
	return envelope
}

func compileGeneratedObject(t *testing.T, cc, root, generated string, extra ...string) string {
	t.Helper()
	object := generated + ".o"
	args := strictC11Flags()
	args = append(args, extra...)
	args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), "-c", generated, "-o", object)
	if outputText, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile: %v\n%s", err, outputText)
	}
	return object
}

func strictC11Flags() []string {
	return []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion"}
}

func alder1LinkFlags() []string {
	switch runtime.GOOS {
	case "windows":
		return []string{"-Wl,--stack,33554432"}
	case "linux":
		return []string{"-DALDER_HOST_LARGE_STACK"}
	default:
		return nil
	}
}

// alder1OptimizeFlags is used only for the large self-hosted compiler
// binaries. Generated C trips -Wmaybe-uninitialized under -O2; the warning
// is a false positive on MIR temporaries and is suppressed here only.
func alder1OptimizeFlags() []string {
	return []string{"-O2", "-Wno-maybe-uninitialized"}
}

func linkGeneratedProgram(t *testing.T, cc, root, object, host, output string, extra ...string) {
	t.Helper()
	args := strictC11Flags()
	args = append(args, extra...)
	args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), object, host, filepath.Join(root, "runtime", "c", "alder.c"), "-o", output)
	if outputText, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile: %v\n%s", err, outputText)
	}
}

func compileGeneratedProgram(t *testing.T, cc, root, generated, host, output string, extra ...string) {
	t.Helper()
	linkGeneratedProgram(t, cc, root, compileGeneratedObject(t, cc, root, generated), host, output, extra...)
}

func compileAndRunProductionArtifact(t *testing.T, cc, root, generated string, want int) {
	t.Helper()
	dir := t.TempDir()
	cfile := filepath.Join(dir, "program.c")
	driver := filepath.Join(dir, "driver.c")
	exe := filepath.Join(dir, "program")
	if err := os.WriteFile(cfile, []byte(generated), 0o644); err != nil {
		t.Fatal(err)
	}
	const driverText = `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	if err := os.WriteFile(driver, []byte(driverText), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), cfile, driver, filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
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

func testProductionInjectedFailure(t *testing.T, cc, root, generated, dir string, storage bool, want int) {
	t.Helper()
	name := "output"
	setup := ""
	command := 2
	stdout := "false"
	if storage {
		name = "storage"
		setup = "alder_runtime_test_fail_domain_alloc_after(0);"
		command = 1
		stdout = "true"
	}
	host := filepath.Join(dir, name+"_host.c")
	exe := filepath.Join(dir, name+"_host")
	source := fmt.Sprintf(`#include "alder_host.h"
#include "alder.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
static const uint8_t text[] = "fn main() -> I32 { return 0 }\n";
uint64_t alderhost_source_count(void) { return 1; }
uint64_t alderhost_source_path_len(uint64_t source) { (void)source; return 7; }
uint8_t alderhost_source_path_byte(uint64_t source, uint64_t offset) { (void)source; return (uint8_t)"main.al"[offset]; }
uint64_t alderhost_source_text_len(uint64_t source) { (void)source; return (uint64_t)(sizeof(text) - 1); }
uint8_t alderhost_source_text_byte(uint64_t source, uint64_t offset) { (void)source; return text[offset]; }
uint64_t alderhost_command(void) { return %d; }
bool alderhost_project_mode(void) { return false; }
uint64_t alderhost_project_action(void) { return 0; }
uint64_t alderhost_manifest_len(void) { return 0; }
uint8_t alderhost_manifest_byte(uint64_t offset) { (void)offset; return 0; }
uint64_t alderhost_target_len(void) { return 0; }
uint8_t alderhost_target_byte(uint64_t offset) { (void)offset; return 0; }
uint64_t alderhost_profile_len(void) { return 0; }
uint8_t alderhost_profile_byte(uint64_t offset) { (void)offset; return 0; }
uint64_t alderhost_triple_len(void) { return 0; }
uint8_t alderhost_triple_byte(uint64_t offset) { (void)offset; return 0; }
bool alderhost_source_request_reset(void) { return false; }
bool alderhost_source_request_byte(uint8_t byte) { (void)byte; return false; }
uint64_t alderhost_source_request_finish(void) { return 0; }
bool alderhost_sources_sort(void) { return false; }
bool alderhost_project_output_reset(uint64_t kind) { (void)kind; return false; }
bool alderhost_project_output_byte(uint8_t byte) { (void)byte; return false; }
bool alderhost_project_output_finish(void) { return false; }
bool alderhost_project_target_kind(uint64_t kind) { (void)kind; return false; }
uint64_t alderhost_project_selected_kind(void) { return 0; }
bool alderhost_project_entry_source_set(uint64_t source) { (void)source; return false; }
uint64_t alderhost_project_entry_source(void) { return 0; }
bool alderhost_format_json(void) { return false; }
uint64_t alderhost_output_path_len(void) { return 0; }
uint8_t alderhost_output_path_byte(uint64_t offset) { (void)offset; return 0; }
bool alderhost_output_mode(uint64_t mode) { (void)mode; return true; }
bool alderhost_output_failed(void) { return %s; }
bool alderhost_response_reset(void) { return true; }
bool alderhost_stdout_byte(uint8_t byte) { (void)byte; return %s; }
bool alderhost_stdout_f64_bits(uint64_t bits) { (void)bits; return true; }
uint64_t alderhost_decimal_f64_bits(uint64_t negative, uint64_t significand, int64_t exponent) { double value = (double)significand; uint64_t bits = 0; while (exponent > 0) { value *= 10.0; exponent--; } while (exponent < 0) { value /= 10.0; exponent++; } if (negative != 0) { value = -value; } memcpy(&bits, &value, sizeof(bits)); return bits; }
bool alderhost_stderr_byte(uint8_t byte) { (void)byte; return true; }
int main(void) { int context = 0; %s return alder_program_entry(&context) == (int32_t)%d ? 0 : 1; }
`, command, map[bool]string{true: "false", false: "true"}[storage], stdout, setup, want)
	if err := os.WriteFile(host, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	linkGeneratedProgram(t, cc, root, generated, host, exe, "-DALDER_RUNTIME_TESTING")
	if output, err := exec.Command(exe).CombinedOutput(); err != nil {
		t.Fatalf("injected %s failure: %v\n%s", name, err, output)
	}
}

func runProductionCompiler(t *testing.T, exe string, files map[string]string, args ...string) productionResult {
	t.Helper()
	return runProductionCompilerAtRoot(t, exe, t.TempDir(), files, args...)
}

func runProductionCompilerAtRoot(t *testing.T, exe, dir string, files map[string]string, args ...string) productionResult {
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
	cmd.Env = append(os.Environ(), "TMPDIR="+tmp)
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
	return productionResult{status: status, stdout: stdout.String(), stderr: stderr.String()}
}
