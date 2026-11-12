package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// Standard streams are copyable non-owning views. The text helpers write
// through the Io capability and ignore errors by contract; the same program
// writes through a converted Stdout/Stderr value with write_all and flushes,
// then reads standard input at end of input.
const ioStreamsProgram = `module hello.main

import std.io { Blocking, eprint, eprintln, print, println, stderr, stdin, stdout, write_all, Reader, Writer }

fn main() -> I32 {
    let cap = Blocking()
    print(cap, "out:")
    println(cap, "hello")
    eprint(cap, "err:")
    eprintln(cap, "bad")
    var out = stdout(cap)
    let data: Array(U8, 2) = [65, 66]
    match write_all(out, data.slice(0, 2)) {
        Ok(n) => { if n != 2 { return 1 } }
        Err(_) => { return 2 }
    }
    match out.flush() {
        Ok(_) => {}
        Err(_) => { return 3 }
    }
    var err = stderr(cap)
    match write_all(err, data.slice(0, 1)) {
        Ok(n) => { if n != 1 { return 4 } }
        Err(_) => { return 5 }
    }
    var input = stdin(cap)
    var one: Array(U8, 1) = [0]
    match input.read(one.slice_mut(0, 1)) {
        Ok(n) => { if n != 0 { return 6 } }
        Err(_) => { return 7 }
    }
    return 0
}
`

func TestIoStandardStreamsProduction(t *testing.T) {
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
		"src/main.al": ioStreamsProgram,
	}
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 {
		t.Fatalf("std streams run: %+v stderr=%s", result, result.stderr)
	}
	if result.stdout != "out:hello\nAB" {
		t.Fatalf("stdout = %q, want %q", result.stdout, "out:hello\nAB")
	}
	if result.stderr != "err:bad\nA" {
		t.Fatalf("stderr = %q, want %q", result.stderr, "err:bad\nA")
	}
}
