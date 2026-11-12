package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// A generic type application may name a namespace-qualified declared type,
// such as `fs.TempDir(I)`. The parser records the whole dotted head, so the
// checker resolves both the type and its arity; previously it recorded only
// the `fs` prefix and rejected the declaration.
func TestProductionQualifiedGenericTypeApplication(t *testing.T) {
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
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.fs
import std.io { Blocking, IoError }

fn make(io: Blocking) -> Result(fs.TempDir(Blocking), IoError) {
    return fs.temp_dir(io, "qualified-type")
}

pub fn main() -> I32 {
    let cap = Blocking()
    match make(cap) {
        Ok(value) => {
            using room = value
            if room.path().to_os().to_bytes().len() == 0 { return 1 }
        }
        Err(_) => { return 2 }
    }
    return 0
}
`,
	}, "run")
	if result != (productionResult{}) {
		t.Fatalf("qualified generic type application failed: %+v", result)
	}
}
