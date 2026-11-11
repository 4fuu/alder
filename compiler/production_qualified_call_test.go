package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A namespace-qualified associated call through a bare import carries its
// argument links unchanged. The zero-argument form was fixed first; this
// fixture pins the argument form with a deterministic SplitMix64 draw and
// keeps the fully qualified module path rejected as an unknown receiver.
func TestQualifiedAssociatedCallWithArgument(t *testing.T) {
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

	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import hello.random

pub fn main() -> I32 {
    var rng = random.Rng.seeded(42)
    if rng.next_u64() != 13679457532755275413 { return 1 }
    if rng.next_u64() != 2949826092126892291 { return 2 }
    let zero = random.Rng.seeded(0)
    if zero.next_u64() == 0 { return 3 }
    return 0
}
`,
		"src/random.al": `module hello.random

pub type Rng {
    state: U64
}

impl Rng {
    fn seeded(seed: U64) -> Rng {
        return Rng(state: seed)
    }
    fn next_u64(mut self) -> U64 {
        let advanced = self.state.add_wrapping(11400714819323198485)
        self.state = advanced
        let z = advanced ^ (advanced >> 30)
        let mixed = z.mul_wrapping(13787848793156543929)
        let folded = mixed ^ (mixed >> 27)
        let scaled = folded.mul_wrapping(10723151780598845931)
        return scaled ^ (scaled >> 31)
    }
}
`,
	}
	result := runProductionCompiler(t, exe, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("qualified associated call with argument failed: %+v", result)
	}

	reject := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import hello.random

pub fn main() -> I32 {
    var rng = std.random.Rng.seeded(42)
    return 0
}
`,
		"src/random.al": files["src/random.al"],
	}
	rejected := runProductionCompiler(t, exe, reject, "check")
	if rejected.status == 0 || !strings.Contains(rejected.stderr, `unknown name "std"`) {
		t.Fatalf("fully qualified module path: %+v", rejected)
	}
}
