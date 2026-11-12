package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Qualified variant construction until now needed a factory function. The
// type prefix is an expression-shaped field chain, so both a selected-import
// type (`Mode.Piped`), a namespace prefix (`process.PipeMode.Piped`), and a
// payload variant call (`Failure.Detail(value)`) must resolve without a bare
// variant name or a helper. Ordinary field access stays unchanged.
func TestM8QualifiedVariantExpressions(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	model := `module hello.model

pub enum Mode {
    Inherit
    Piped
}

pub enum Failure {
    Missing
    Detail(info: U64)
}
`
	files := map[string]string{
		"alder.toml":   manifest,
		"src/model.al": model,
		"src/main.al": `module hello.main

import hello.model { Mode, Failure }
import std.process

pub fn main() -> I32 {
    let a = Mode.Piped
    let b = Failure.Detail(7)
    let c = process.PipeMode.Inherit
    let d = Failure.Missing
    match a {
        Piped => {}
        Inherit => { return 1 }
    }
    match b {
        Detail(value) => { if value != 7 { return 2 } }
        Missing => { return 3 }
    }
    match c {
        Inherit => {}
        Piped => { return 4 }
    }
    match d {
        Missing => {}
        Detail(_) => { return 5 }
    }
    return 0
}
`,
	}
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("qualified variant run: %+v", result)
	}

	rejected := map[string]string{
		"alder.toml":   manifest,
		"src/model.al": model,
		"src/main.al": `module hello.main

import hello.model { Failure }

pub fn main() -> I32 {
    let missing = Failure.Detail()
    return 0
}
`,
	}
	bad := runProductionCompilerEnv(t, exe, t.TempDir(), env, rejected, "check")
	if bad.status == 0 || !strings.Contains(bad.stderr, "checker diagnostic 49") {
		t.Fatalf("qualified payload arity rejection: %+v", bad)
	}
}
