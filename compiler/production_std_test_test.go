package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const stdTestManifest = "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

// The runner-independent std.test slice runs through the installed sysroot.
// Seeded-case values are independently computed SplitMix64 outputs for seed 7;
// the temporary owners contribute only presence checks, so no host path enters
// the assertions.
func TestProductionStdTestHelpersRun(t *testing.T) {
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
		"alder.toml": stdTestManifest,
		"src/main.al": `module hello.main

import std.io { Blocking }
import std.test

pub type Holder {
    value: U64
}

impl Cleanup for Holder {
    fn cleanup(take self) -> Unit {
        return
    }
}

pub fn main() -> I32 {
    test.assert(true, "never printed")
    test.assert_eq(U64, 7, 7)
    test.assert_ne(String, "alder", "aster")

    let good: Result(U64, String) = Ok(41)
    if test.expect_ok(U64, String, good) != 41 { return 1 }
    let bad: Result(U64, String) = Err("boom")
    if test.expect_err(U64, String, bad) != "boom" { return 2 }

    // Affine payloads survive the named arm and are cleaned on the discarded
    // arm: expect_ok moves the success owner out, expect_err drops an Ok owner
    // through its cleanup.
    let owned: Result(Holder, String) = Ok(Holder(value: 2))
    using moved = test.expect_ok(Holder, String, owned)
    if moved.value != 2 { return 9 }
    let unowned: Result(Holder, String) = Err("kept")
    if test.expect_err(Holder, String, unowned) != "kept" { return 10 }

    let case_list = test.cases(4, 7)
    if case_list.len() != 4 { return 3 }
    var expected: Array(U64, 4) = [7191089600892374487, 309689372594955804, 16616101746815609346, 10753165928301472203]
    var at: U64 = 0
    while at < 4 {
        match case_list.get(at) {
            Some(item) => {
                if item.index != at { return 4 }
                if item.seed != expected[at] { return 5 }
            }
            None => { return 6 }
        }
        at = at + 1
    }

    let cap = Blocking()
    using temporary_file = test.temp_file(cap, "alder-test")
    if temporary_file.path().to_os().to_bytes().len() == 0 { return 7 }
    using temporary_dir = test.temp_dir(cap, "alder-test")
    if temporary_dir.path().to_os().to_bytes().len() == 0 { return 8 }
    return 0
}
`,
	}, "run")
	if result != (productionResult{}) {
		t.Fatalf("std.test helpers failed: %+v", result)
	}
}

// Every failing helper terminates with status 101 and the documented stderr
// shape. The assertion wrappers stay ordinary Unit functions; only the
// value-returning helpers call core.panic directly.
func TestProductionStdTestFailureFormats(t *testing.T) {
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
		name, source, wantStderr string
	}{
		{
			name: "fail",
			source: `module hello.main

import std.test

pub fn main() -> I32 {
    test.fail("boom")
    return 0
}
`,
			wantStderr: "panic: boom\n",
		},
		{
			name: "assert",
			source: `module hello.main

import std.test

pub fn main() -> I32 {
    test.assert(false, "condition")
    return 0
}
`,
			wantStderr: "panic: assertion failed: condition\n",
		},
		{
			name: "assert-eq",
			source: `module hello.main

import std.test

pub fn main() -> I32 {
    test.assert_eq(U64, 1, 2)
    return 0
}
`,
			wantStderr: "panic: assertion failed: a == b\n  a: 1\n  b: 2\n",
		},
		{
			name: "assert-ne",
			source: `module hello.main

import std.test

pub fn main() -> I32 {
    test.assert_ne(U64, 1, 1)
    return 0
}
`,
			wantStderr: "panic: assertion failed: a != b\n  a: 1\n  b: 1\n",
		},
		{
			name: "expect-ok",
			source: `module hello.main

import std.test

pub fn main() -> I32 {
    let bad: Result(U64, String) = Err("boom")
    let value = test.expect_ok(U64, String, bad)
    if value == 41 { return 0 }
    return 1
}
`,
			wantStderr: "panic: expected Ok\n  error: boom\n",
		},
		{
			name: "expect-err",
			source: `module hello.main

import std.test

pub fn main() -> I32 {
    let good: Result(U64, String) = Ok(7)
    let value = test.expect_err(U64, String, good)
    if value == "boom" { return 0 }
    return 1
}
`,
			wantStderr: "panic: expected Err, found Ok\n",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  stdTestManifest,
				"src/main.al": tc.source,
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

// expect_ok displays the error on the wrong arm, so the error type must
// implement Display. A plain enum without that impl is rejected at the call.
func TestProductionStdTestRejectsNonDisplayError(t *testing.T) {
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
		"alder.toml": stdTestManifest,
		"src/main.al": `module hello.main

import std.test

pub enum Boom {
    No
}

pub fn main() -> I32 {
    let bad: Result(U64, Boom) = Err(Boom.No)
    let value = test.expect_ok(U64, Boom, bad)
    if value == 41 { return 0 }
    return 1
}
`,
	}, "run")
	if result.status == 0 {
		t.Fatalf("non-Display error accepted: %+v", result)
	}
	if !strings.Contains(result.stderr, "does not implement a trait required here") {
		t.Fatalf("diagnostic = %q", result.stderr)
	}
}
