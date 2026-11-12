package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// A bare module import binds a namespace, but a lexical binding with the same
// spelling must win inside its scope. Before the parser tracked visible
// bindings, `util.count()` with a parameter or local `util` went through the
// namespace path and tripped the associated-call argument count.
func TestDottedMethodCallOnBareImportShadow(t *testing.T) {
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
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/util.al": `module hello.util

pub type Thing {
    pub value: U64
}

impl Thing {
    fn count(self) -> U64 {
        return self.value
    }
}
`,
		"src/main.al": `module hello.main

import hello.util

fn from_parameter(util: util.Thing) -> U64 {
    return util.count()
}

fn from_let() -> U64 {
    let value = util.Thing(value: 7)
    let util = value
    return util.count()
}

fn from_var() -> U64 {
    let value = util.Thing(value: 8)
    var util = value
    return util.count()
}

fn main() -> I32 {
    if from_parameter(util.Thing(value: 5)) != 5 { return 1 }
    if from_let() != 7 { return 2 }
    if from_var() != 8 { return 3 }
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("bare-import shadow program failed: %+v", result)
	}
}

// A selected import (`import m { Name }`) binds no module namespace. A local
// binding whose name happens to match the module's final component is
// therefore a value, and `path.to_os()` / `util.count()` must be treated as
// method calls, not associated calls through the module. The receiver matrix
// covers parameters, `mut`/`take` parameters, let, var, and field bindings on
// a sysroot-imported type and a project-module type, with zero-argument and
// argument-taking methods.
func TestDottedMethodCallOnSelectedImportBinding(t *testing.T) {
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
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))

	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/util.al": `module hello.util

pub type Thing {
    pub value: U64
}

impl Thing {
    fn count(self) -> U64 {
        return self.value
    }
    fn add(self, delta: U64) -> U64 {
        return self.value + delta
    }
}

pub type Counter {
    pub value: U64
}

impl Counter {
    fn bump(mut self) -> Unit {
        self.value = self.value + 1
    }
}

pub type Owner {
    pub value: U64
}

impl Owner {
    fn grow(mut self) -> Unit {
        self.value = self.value + 1
    }
    fn release(take self) -> U64 {
        let value = self.value
        self.cleanup()
        return value
    }
}

impl Cleanup for Owner {
    fn cleanup(take self) -> Unit {
        return
    }
}
`,
		"src/main.al": `module hello.main

import hello.util { Counter, Owner, Thing }
import std.path { Path }

type Holder {
    thing: Thing
}

fn from_parameter(util: Thing) -> U64 {
    return util.count()
}

fn from_parameter_argument(util: Thing) -> U64 {
    return util.add(2)
}

fn from_let(path: Path) -> U64 {
    let copy = path
    let host = copy.to_os()
    return host.len()
}

fn from_var(path: Path) -> U64 {
    var copy = path
    let host = copy.to_os()
    return host.len()
}

fn from_field(holder: Holder) -> U64 {
    return holder.thing.count()
}

fn from_mut_parameter(mut owner: Owner) -> Unit {
    owner.grow()
    return
}

fn from_take_parameter(take owner: Owner) -> U64 {
    return owner.release()
}

fn from_var_counter() -> U64 {
    var counter = Counter(value: 0)
    counter.bump()
    return counter.value
}

fn main() -> I32 {
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "check")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("dotted method calls on selected-import bindings failed: %+v", result)
	}
}
