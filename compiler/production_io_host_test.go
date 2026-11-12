package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// The blocking HostFile surface round-trips a real descriptor through the
// std.io shim: create, write, seek, read, stat, close, remove. A local
// `try` on the Unit-returning close also exercises the unit-result lowering.
const ioHostFileProgram = `module hello.main

import std.io { Blocking, FileMode, IoError }
import std.path { Path }

fn run(path: Path) -> Result(I32, IoError) {
    let cap = Blocking()
    let mode = FileMode(read: true, write: true, append: false, truncate: true, create: true, create_new: false)
    let file = try cap.open(path, mode)
    var text: Vec(U8) = Vec.new(U8)
    text.push(104)
    text.push(105)
    let written = try cap.write(file, text.slice(0, 2))
    let position = try cap.seek(file, Start(0))
    var room: Vec(U8) = Vec.new(U8)
    room.push(0)
    room.push(0)
    let count = try cap.read(file, room.slice_mut(0, 2))
    let info = try cap.stat(file)
    var code: I32 = 0
    if written != 2 { code = 1 }
    if position != 0 { code = 2 }
    if count != 2 { code = 3 }
    if room[0] != 104 || room[1] != 105 { code = 4 }
    if info.size != 2 { code = 5 }
    try cap.close(file)
    try cap.remove(path)
    return Ok(code)
}

fn main() -> I32 {
    return match Path.parse("/tmp/alder-io-host-probe.txt") {
        Ok(value) => match run(value) {
            Ok(code) => code
            Err(_) => 100
        }
        Err(_) => 40
    }
}
`

func TestIoHostFileProductionBehavior(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	files := map[string]string{
		"alder.toml":  "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": ioHostFileProgram,
	}
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("io host run result: %+v stderr=%s", result, result.stderr)
	}
}
