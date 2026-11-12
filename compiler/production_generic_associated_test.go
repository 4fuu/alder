package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const genericAssociatedManifest = "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

const genericAssociatedBox = `module hello.box

pub trait Cap {}
pub type CapImpl {}
impl Cap for CapImpl {}

pub type Box(C: type(Cap)) {
    item: U64
}

impl(C: type(Cap)) Box(C) {
    fn make(I: type(Cap), io: I, value: U64) -> Box(I) {
        return Box(item: value)
    }

    fn open(I: type(Cap), io: I) -> Result(Box(I), U64) {
        return Ok(Box(item: 1))
    }

    fn stamped(I: type(Cap), self, io: I) -> Box(I) {
        return Box(item: self.item)
    }
}

pub type Command {
    pub item: U64
}

impl Command {
    fn spawn(I: type(Cap), self, io: I) -> Box(I) {
        return Box(item: self.item)
    }
}
`

func TestGenericAssociatedCallInference(t *testing.T) {
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

	accepted := map[string]string{
		"alder.toml": genericAssociatedManifest,
		"src/box.al": genericAssociatedBox,
		"src/main.al": `module hello.main

import hello.box { Box, CapImpl, Command }

pub fn main() -> I32 {
    let cap = CapImpl()
    let boxed: Box(CapImpl) = Box.make(cap, 7)
    if boxed.item != 7 { return 1 }
    let opened: Result(Box(CapImpl), U64) = Box.open(cap)
    match opened {
        Ok(value) => { if value.item != 1 { return 2 } }
        Err(_) => { return 3 }
    }
    let command = Command(item: 9)
    let spawned: Box(CapImpl) = command.spawn(cap)
    if spawned.item != 9 { return 4 }
    let stamped: Box(CapImpl) = boxed.stamped(cap)
    if stamped.item != 7 { return 5 }
    return 0
}
`,
	}
	check := runProductionCompiler(t, exe, accepted, "check")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("generic associated check: %+v stderr=%s", check, check.stderr)
	}
	runResult := runProductionCompiler(t, exe, accepted, "run")
	if runResult.status != 0 || runResult.stderr != "" {
		t.Fatalf("generic associated run: %+v stderr=%s", runResult, runResult.stderr)
	}

	rejected := map[string]string{
		"alder.toml": genericAssociatedManifest,
		"src/box.al": genericAssociatedBox,
		"src/main.al": `module hello.main

import hello.box { Box, CapImpl, Command }

pub fn main() -> I32 {
    let cap = CapImpl()
    let boxed = Box.make(cap, 7)
    return 0
}
`,
	}
	reject := runProductionCompiler(t, exe, rejected, "check")
	if reject.status == 0 || !strings.Contains(reject.stderr, "type argument inference failed") {
		t.Fatalf("generic associated rejection: %+v stderr=%s", reject, reject.stderr)
	}
}
