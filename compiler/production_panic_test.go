package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The process-terminating assertions are observed through the production
// driver's project runner. The child exits with the documented invariant status
// 101, and this test pins that status together with the exact stderr contract.
const corePanicManifest = "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

func TestProductionCorePanicTerminates(t *testing.T) {
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

	cases := []struct {
		name, source string
		wantStatus   int
		wantStdout   string
		wantStderr   string
	}{
		{
			name: "panic",
			source: `module hello.main

import core.panic { panic }

pub fn main() -> I32 {
    panic("boom")
}
`,
			wantStatus: 101,
			wantStderr: "panic: boom\n",
		},
		{
			name: "assert",
			source: `module hello.main

import core.panic { assert }

pub fn main() -> I32 {
    assert(false, "condition")
    return 0
}
`,
			wantStatus: 101,
			wantStderr: "panic: assertion failed: condition\n",
		},
		{
			name: "assert-eq",
			source: `module hello.main

import core.panic { assert_eq }

pub fn main() -> I32 {
    assert_eq(U64, 1, 2)
    return 0
}
`,
			wantStatus: 101,
			wantStderr: "panic: assertion failed: a == b\n  a: 1\n  b: 2\n",
		},
		{
			name: "assert-eq-signed",
			source: `module hello.main

import core.panic { assert_eq }

pub fn main() -> I32 {
    assert_eq(I32, -1, 1)
    return 0
}
`,
			wantStatus: 101,
			wantStderr: "panic: assertion failed: a == b\n  a: -1\n  b: 1\n",
		},
		{
			name: "assert-ne",
			source: `module hello.main

import core.panic { assert_ne }

pub fn main() -> I32 {
    assert_ne(U64, 1, 1)
    return 0
}
`,
			wantStatus: 101,
			wantStderr: "panic: assertion failed: a != b\n  a: 1\n  b: 1\n",
		},
		{
			name: "passing-assertions",
			source: `module hello.main

import core.panic { assert, assert_eq, assert_ne }

pub fn main() -> I32 {
    assert(true, "never printed")
    assert_eq(U64, 42, 42)
    assert_ne(U64, 42, 7)
    assert_eq(I32, -42, -42)
    assert_ne(I64, -42, 7)
    return 0
}
`,
			wantStatus: 0,
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  corePanicManifest,
				"src/main.al": tc.source,
			}, "run")
			if result.status != tc.wantStatus {
				t.Fatalf("status = %d, want %d; stdout=%q stderr=%q", result.status, tc.wantStatus, result.stdout, result.stderr)
			}
			if result.stdout != tc.wantStdout {
				t.Fatalf("stdout = %q, want %q", result.stdout, tc.wantStdout)
			}
			if result.stderr != tc.wantStderr {
				t.Fatalf("stderr = %q, want %q", result.stderr, tc.wantStderr)
			}
		})
	}
}

func TestProductionCorePanicFlushesStdout(t *testing.T) {
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

	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml": corePanicManifest,
		"src/main.al": `module hello.main

import core.panic { panic }
import c "stdio.h" as stdio {
    raw fn putchar = "putchar"(value: c.Int) -> c.Int
}

pub fn main() -> I32 {
    let letter: I32 = 65
    let written = unsafe c { stdio.putchar(letter.to_c_int()) }
    if written.to_i32() != 65 { return 1 }
    panic("boom")
}
`,
	}, "run")
	if result.status != 101 {
		t.Fatalf("status = %d, want %d; stdout=%q stderr=%q", result.status, 101, result.stdout, result.stderr)
	}
	if result.stdout != "A" {
		t.Fatalf("stdout = %q, want %q", result.stdout, "A")
	}
	if result.stderr != "panic: boom\n" {
		t.Fatalf("stderr = %q, want %q", result.stderr, "panic: boom\n")
	}
}

func TestProductionCorePanicSkipsCleanup(t *testing.T) {
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

	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml": corePanicManifest,
		"src/main.al": `module hello.main

import core.panic { panic }
import c "stdio.h" as stdio {
    raw fn putchar = "putchar"(value: c.Int) -> c.Int
}

type Resource {
    value: U64
}

impl Cleanup for Resource {
    fn cleanup(take self) -> Unit {
        let marker: I32 = 67
        let written = unsafe c { stdio.putchar(marker.to_c_int()) }
        if written.to_i32() != 67 { return }
        return
    }
}

pub fn main() -> I32 {
    using held = Resource(value: 1)
    panic("boom")
}
`,
	}, "run")
	if result.status != 101 {
		t.Fatalf("status = %d, want %d; stdout=%q stderr=%q", result.status, 101, result.stdout, result.stderr)
	}
	if result.stdout != "" {
		t.Fatalf("cleanup ran before termination: stdout = %q", result.stdout)
	}
	if result.stderr != "panic: boom\n" {
		t.Fatalf("stderr = %q, want %q", result.stderr, "panic: boom\n")
	}
}

func TestProductionCorePanicInteriorNULFallback(t *testing.T) {
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

	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml": corePanicManifest,
		"src/main.al": `module hello.main

import core.panic { panic }

pub fn main() -> I32 {
    let text = "a".concat("\0b")
    panic(text)
}
`,
	}, "run")
	if result.status != 101 {
		t.Fatalf("status = %d, want %d; stdout=%q stderr=%q", result.status, 101, result.stdout, result.stderr)
	}
	if result.stderr != "panic: message contains an interior NUL byte\n" {
		t.Fatalf("stderr = %q, want interior-NUL fallback", result.stderr)
	}
}

func TestProductionCorePanicRejectsUnsatisfiedEq(t *testing.T) {
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

	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml": corePanicManifest,
		"src/main.al": `module hello.main

import core.panic { assert_eq }

pub fn main() -> I32 {
    assert_eq(F32, 1.0, 2.0)
    return 0
}
`,
	}, "run")
	if result.status == 0 {
		t.Fatalf("floating Eq constraint was accepted: %+v", result)
	}
	if result.stderr == "" {
		t.Fatalf("floating Eq constraint produced no diagnostic")
	}
}

// A statement-position core.panic.panic call is a diverging path end. The
// value-returning stop function needs no trailing return, a match arm ending
// in panic diverges like a return arm, and the generated C keeps compiling
// under the strict warning set.
func TestProductionCorePanicDiverges(t *testing.T) {
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

	cases := []struct {
		name       string
		expression string
		wantStderr string
	}{
		{"value-returning-function", "return stop()", "panic: done\n"},
		{"match-arm", "return pick(None)", "panic: none\n"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml": corePanicManifest,
				"src/main.al": `module hello.main

import core.panic { panic }

fn stop() -> I32 {
    panic("done")
}

fn pick(value: Option(U64)) -> I32 {
    match value {
        Some(item) => { return item.to_i32_wrapping() }
        None => { panic("none") }
    }
}

pub fn main() -> I32 {
    if pick(Some(7)) != 7 { return 1 }
    ` + tc.expression + `
}
`,
			}, "run")
			if result.status != 101 {
				t.Fatalf("status = %d, want 101; stdout=%q stderr=%q", result.status, result.stdout, result.stderr)
			}
			if result.stderr != tc.wantStderr {
				t.Fatalf("stderr = %q, want %q", result.stderr, tc.wantStderr)
			}
		})
	}
}

func TestProductionCorePanicRejectsCodeAfter(t *testing.T) {
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

	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml": corePanicManifest,
		"src/main.al": `module hello.main

import core.panic { panic }

pub fn main() -> I32 {
    panic("boom")
    return 0
}
`,
	}, "check")
	if result.status != 1 || !strings.Contains(result.stderr, "unreachable statement") {
		t.Fatalf("code after panic: %+v stderr=%s", result, result.stderr)
	}
}
