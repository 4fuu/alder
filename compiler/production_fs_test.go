package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// File methods and the free whole-file helpers live in separate fixtures:
// importing `read` from std.fs and then calling `file.read(...)` currently
// resolves the dotted call against the imported free function, so the method
// fixture imports no colliding free function. Both fixtures share the same
// on-disk probe file, which the Go harness resets between runs.
const fsFileProgram = `module hello.main

import std.fs { File, Permissions, create, open }
import std.io { Blocking, IoError, Reader, Seek, SeekFrom, Writer }
import std.path { Path }

fn io_path(value: String) -> Result(Path, IoError) {
    match Path.parse(value) {
        Ok(parsed) => { return Ok(parsed) }
        Err(_) => { return Err(IoError.InvalidInput) }
    }
    return Err(IoError.InvalidInput)
}

fn probe_main(cap: Blocking) -> Result(I32, IoError) {
    let path = try io_path("/tmp/alder-fs-probe.txt")
    let file: File(Blocking) = try open(cap, path)
    let info = try file.metadata()
    var code: I32 = 0
    if info.length != 2 || info.modified.unix_seconds() != -1 { code = 3 }
    if !info.permissions.readable || info.permissions.executable { code = 4 }
    try file.seek(SeekFrom.Start(1))
    var one: Array(U8, 1) = [0]
    let count = try file.read(one.slice_mut(0, 1))
    if count != 1 || one[0] != 105 { code = 5 }
    try file.finish()
    if code != 0 { return Ok(code) }
    let made: File(Blocking) = try create(cap, path)
    let data: Array(U8, 2) = [111, 107]
    let written = try made.write(data.slice(0, 2))
    if written != 2 { code = 6 }
    try made.set_permissions(Permissions(readable: true, writable: false, executable: true))
    try made.finish()
    if code != 0 { return Ok(code) }
    let tuned: File(Blocking) = try open(cap, path)
    let tuned_info = try tuned.metadata()
    if !tuned_info.permissions.executable || tuned_info.permissions.writable { code = 7 }
    try tuned.finish()
    return Ok(code)
}

fn main() -> I32 {
    let cap = Blocking()
    match probe_main(cap) {
        Ok(code) => { return code }
        Err(_) => { return 90 }
    }
    return 91
}
`

const fsFreeProgram = `module hello.main

import std.fs { make_dir, metadata, read, read_text, remove_dir, remove_file, rename, write_text }
import std.io { Blocking, IoError }
import std.path { Path }

fn io_path(value: String) -> Result(Path, IoError) {
    match Path.parse(value) {
        Ok(parsed) => { return Ok(parsed) }
        Err(_) => { return Err(IoError.InvalidInput) }
    }
    return Err(IoError.InvalidInput)
}

fn probe_main(cap: Blocking) -> Result(I32, IoError) {
    let path = try io_path("/tmp/alder-fs-probe.txt")
    let info = try metadata(cap, path)
    if info.length != 2 { return Ok(1) }
    if info.modified.unix_seconds() != -1 { return Ok(2) }
    let data = try read(cap, path)
    if data.len() != 2 || data[0] != 104 || data[1] != 105 { return Ok(3) }
    try write_text(cap, path, "text")
    let content = try read_text(cap, path)
    if content != "text" { return Ok(4) }
    let moved = try io_path("/tmp/alder-fs-probe-moved.txt")
    try rename(cap, path, moved)
    let after = try read_text(cap, moved)
    if after != "text" { return Ok(5) }
    let dir = try io_path("/tmp/alder-fs-probe-dir")
    try make_dir(cap, dir)
    try remove_dir(cap, dir)
    try remove_file(cap, moved)
    return Ok(0)
}

fn main() -> I32 {
    let cap = Blocking()
    match probe_main(cap) {
        Ok(code) => { return code }
        Err(_) => { return 90 }
    }
    return 91
}
`

func resetFsProbeFile(t *testing.T) {
	t.Helper()
	path := "/tmp/alder-fs-probe.txt"
	_ = os.Chmod(path, 0o644)
	if err := os.WriteFile(path, []byte("hi"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0o644); err != nil {
		t.Fatal(err)
	}
	stamp := time.Unix(-1, 0)
	if err := os.Chtimes(path, stamp, stamp); err != nil {
		t.Fatal(err)
	}
}

func TestFsProductionFileAndValues(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

	resetFsProbeFile(t)
	fileRun := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": fsFileProgram,
	}, "run")
	if fileRun.status != 0 {
		t.Fatalf("fs file probe: %+v stderr=%s", fileRun, fileRun.stderr)
	}

	resetFsProbeFile(t)
	freeRun := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": fsFreeProgram,
	}, "run")
	if freeRun.status != 0 {
		t.Fatalf("fs free-function probe: %+v stderr=%s", freeRun, freeRun.stderr)
	}
	_ = os.Remove("/tmp/alder-fs-probe.txt")
	_ = os.Remove("/tmp/alder-fs-probe-moved.txt")
}
