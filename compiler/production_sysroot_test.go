package compiler

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// C1 installed sysroot: discovery, rooted-import resolution, plan identity,
// and deterministic rejections. Every case forces ALDER_SYSROOT explicitly so
// no assertion depends on the ambient environment, and one case proves the
// plan does not depend on how the sysroot was found.

// sysrootEnv strips ALDER_SYSROOT from the test process environment and
// re-adds it only when value is nonempty.
func sysrootEnv(value string) []string {
	env := make([]string, 0, len(os.Environ())+1)
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "ALDER_SYSROOT=") {
			continue
		}
		env = append(env, entry)
	}
	if value != "" {
		env = append(env, "ALDER_SYSROOT="+value)
	}
	return env
}

func runProductionCompilerEnv(t *testing.T, exe, dir string, env []string, files map[string]string, args ...string) productionResult {
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
	cmd.Env = append(env, "TMPDIR="+tmp)
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

// copySysrootTree copies the committed sysroot library sources into dst so a
// test can exercise the installed `<exe dir>/../lib/alder` discovery order.
func copySysrootTree(t *testing.T, repoRoot, dst string) {
	t.Helper()
	for _, root := range []string{"core", "std"} {
		entries, err := os.ReadDir(filepath.Join(repoRoot, "sysroot", root))
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Join(dst, root), 0o755); err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			text, err := os.ReadFile(filepath.Join(repoRoot, "sysroot", root, entry.Name()))
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dst, root, entry.Name()), text, 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func sysrootOptionMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import core.option

pub fn main() -> I32 {
    let value: Option(U64) = Some(3)
    if option.is_none(value) { return 1 }
    let empty: Option(U64) = None
    if !option.is_none(empty) { return 2 }
    if !option.is_some(value) { return 3 }
    return 0
}
`,
	}
}

func sysrootSeedLength(t *testing.T, repoRoot string) string {
	t.Helper()
	info, err := os.Stat(filepath.Join(repoRoot, "sysroot", "core", "option.al"))
	if err != nil {
		t.Fatal(err)
	}
	return strconv.FormatUint(uint64(info.Size()), 10)
}

func TestProductionSysrootCoreResolves(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "test-plan")
	seedBytes := sysrootSeedLength(t, repoRoot)
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("sysroot plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") || strings.Contains(plan.stdout, "compiler-coupled-v1") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source core/option.al bytes "+seedBytes+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module core.option\n") {
		t.Fatalf("plan does not list the sysroot source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> core.option\n") {
		t.Fatalf("plan does not record the sysroot edge: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("sysroot plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("sysroot project run failed: %+v", run)
	}
}

func TestProductionSysrootPlanStableAcrossDiscovery(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)

	envRoot := t.TempDir()
	viaEnv := runProductionCompilerEnv(t, exe, envRoot, sysrootEnv(filepath.Join(repoRoot, "sysroot")), sysrootOptionMain(), "test-plan")
	if viaEnv.status != 0 || viaEnv.stderr != "" {
		t.Fatalf("ALDER_SYSROOT discovery plan failed: %+v", viaEnv)
	}

	// The same sysroot content found through <exe dir>/../lib/alder with no
	// ALDER_SYSROOT must produce a byte-identical plan.
	layout := t.TempDir()
	if err := os.MkdirAll(filepath.Join(layout, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	copySysrootTree(t, repoRoot, filepath.Join(layout, "lib", "alder"))
	copied := filepath.Join(layout, "bin", "alder-driver")
	text, err := os.ReadFile(exe)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(copied, text, 0o755); err != nil {
		t.Fatal(err)
	}
	viaLayout := runProductionCompilerEnv(t, copied, t.TempDir(), sysrootEnv(""), sysrootOptionMain(), "test-plan")
	if viaLayout != viaEnv {
		t.Fatalf("plan depends on sysroot discovery order: env=%q layout=%q", viaEnv.stdout, viaLayout.stdout)
	}
}

func TestProductionSysrootUnavailable(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(""), sysrootOptionMain(), "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "no installed Alder sysroot is available") {
		t.Fatalf("missing sysroot rejection: %+v", result)
	}
}

func TestProductionSysrootMissingModule(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	files["src/main.al"] = strings.Replace(files["src/main.al"], "import core.option", "import core.missing", 1)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "a required sysroot module is unavailable") {
		t.Fatalf("missing sysroot module rejection: %+v", result)
	}
}

func TestProductionSysrootStdResolves(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	// A fixture sysroot proves the `std` root resolves through the same
	// machinery before the first hosted std module lands.
	fixture := t.TempDir()
	if err := os.MkdirAll(filepath.Join(fixture, "std"), 0o755); err != nil {
		t.Fatal(err)
	}
	echo := "module std.echo\n\n/// Echoes one fixed byte.\npub fn first_byte() -> U8 {\n    return 7\n}\n"
	if err := os.WriteFile(filepath.Join(fixture, "std", "echo.al"), []byte(echo), 0o644); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.echo

pub fn main() -> I32 {
    if echo.first_byte() != 7 { return 1 }
    return 0
}
`,
	}
	run := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(fixture), files, "run")
	if run != (productionResult{}) {
		t.Fatalf("std fixture project run failed: %+v", run)
	}
}

func TestProductionSysrootCannotShadow(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	// Both decoys must be ignored: a project-local sysroot tree and a
	// project source at the sysroot path.
	files["sysroot/core/option.al"] = "module core.option\npub fn is_none(T: type, value: Option(T)) -> Bool {\n    return true\n}\n"
	files["src/core/option.al"] = "module hello.core.option\npub fn decoy() -> I32 { return 0 }\n"
	dir := t.TempDir()
	plan := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "test-plan")
	seedBytes := sysrootSeedLength(t, repoRoot)
	if plan.status != 0 || !strings.Contains(plan.stdout, "source core/option.al bytes "+seedBytes+" poly64-v1:") {
		t.Fatalf("project tree shadowed the sysroot: %+v", plan)
	}
	run := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "run")
	if run != (productionResult{}) {
		t.Fatalf("shadowed project run failed: %+v", run)
	}
}

func TestProductionSysrootReservedPackageName(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	files["alder.toml"] = strings.Replace(files["alder.toml"], "name = \"hello\"", "name = \"core\"", 1)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "the package name core or std is reserved") {
		t.Fatalf("reserved package name rejection: %+v", result)
	}
}
