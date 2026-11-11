package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 std.io v1 slice 1 through the production driver: the Reader/Writer/Seek
// traits, SeekFrom, IoError (Display, Error, from_errno), read_exact,
// write_all, read_to_end, and the host-free ByteCursor and ByteSink streams
// compile as an ordinary sysroot module and behave on generated C. Every
// reader/writer call takes a mutable place, so the same program also proves
// the caller's cursor advances exactly once.

func ioCoreMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.io

fn main() -> I32 {
    // read_exact fills a one-byte view and advances the cursor.
    var cursor = io.ByteCursor.new("abc")
    var one: Array(U8, 1) = [0]
    match io.read_exact(cursor, one.slice_mut(0, 1)) {
        Ok(_) => {}
        Err(_) => { return 1 }
    }
    if one[0] != 97 { return 2 }
    match io.read_exact(cursor, one.slice_mut(0, 1)) {
        Ok(_) => {}
        Err(_) => { return 3 }
    }
    if one[0] != 98 { return 4 }

    // read_to_end drains the rest of the same cursor.
    match io.read_to_end(cursor) {
        Ok(rest) => { if rest.len() != 1 { return 5 } }
        Err(_) => { return 6 }
    }

    // write_all copies an Array view into a ByteSink.
    var sink = io.ByteSink.new()
    let hello: Array(U8, 5) = [104, 101, 108, 108, 111]
    match io.write_all(sink, hello.slice(0, 5)) {
        Ok(n) => { if n != 5 { return 7 } }
        Err(_) => { return 8 }
    }
    if sink.len() != 5 { return 9 }
    let made = sink.into_bytes()
    if made.len() != 5 { return 10 }
    if made.byte(4) != 111 { return 11 }

    // The Reader.copy_to default body copies through its bounded buffer.
    var source = io.ByteCursor.new(made)
    var target = io.ByteSink.new()
    match source.copy_to(target) {
        Ok(n) => { if n != 5 { return 12 } }
        Err(_) => { return 13 } }
    let copied = target.into_bytes()
    if copied.len() != 5 { return 14 }
    if copied.byte(0) != 104 { return 15 }

    // read_exact reports end of stream as InvalidInput.
    var empty = io.ByteCursor.new(made)
    match io.read_to_end(empty) {
        Ok(all) => { if all.len() != 5 { return 16 } }
        Err(_) => { return 17 }
    }
    var drained = io.ByteCursor.new(made)
    match io.read_to_end(drained) {
        Ok(all) => { if all.len() != 5 { return 18 } }
        Err(_) => { return 19 }
    }
    match io.read_exact(drained, one.slice_mut(0, 1)) {
        Ok(_) => { return 20 }
        Err(error) => {
            if error.display() != "invalid input" { return 21 }
        }
    }

    // IoError categories and the prelude Error report.
    let missing = io.IoError.from_errno(2)
    if missing.display() != "not found" { return 22 }
    let report = ErrorReport.of(missing)
    if report.message != "not found" { return 23 }
    if report.causes.len() != 0 { return 24 }
    let odd = io.IoError.from_errno(9999)
    match odd {
        Other(info) => { if info.code != 9999 { return 25 } }
        NotFound => { return 26 }
        PermissionDenied => { return 27 }
        AlreadyExists => { return 28 }
        InvalidInput => { return 29 }
        DirectoryNotEmpty => { return 30 }
        Unsupported => { return 31 }
    }
    return 0
}
`,
	}
}

func TestIoCoreProductionQualification(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, ioCoreMain(), "test-plan")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.io plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, " module std.io\n") || !strings.Contains(plan.stdout, "edge std.io -> std.env\n") {
		t.Fatalf("plan does not list std.io and its dependency: %q", plan.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, ioCoreMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.io core behavior run failed: %+v", run)
	}
}

// A read helper takes its reader by mutable place: a let-bound cursor would
// advance a discarded copy, so the call is rejected at the argument.
func TestIoCoreRejectsLetBoundReader(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
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

	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.io

fn main() -> I32 {
    let cursor = io.ByteCursor.new("abc")
    var one: Array(U8, 1) = [0]
    match io.read_exact(cursor, one.slice_mut(0, 1)) {
        Ok(_) => { return 0 }
        Err(_) => { return 1 }
    }
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status == 0 || !strings.Contains(result.stderr, "mut cursor argument must be a mutable place") {
		t.Fatalf("let-bound reader accepted: %+v", result)
	}
}
