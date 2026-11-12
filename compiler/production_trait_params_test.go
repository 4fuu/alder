package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Trait requirements may declare several runtime parameters. The requirement
// syntax links are stored last-to-first, so a positional comparison must walk
// the implementation's role-5 uses from the other end; a static requirement
// has no receiver slot. These cases pin both rules across scalar, record,
// generic-parameter, static, and `mut` parameter modes.
var traitParamAcceptance = []struct {
	name   string
	source string
}{
	{
		"two-scalars-self",
		`trait Pair {
    fn ping(self, first: U64, second: U32) -> Unit
}
type Box {
}
impl Pair for Box {
    fn ping(self, first: U64, second: U32) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
	{
		"three-mixed-records-self",
		`type Left {
    value: U64
}
type Right {
    value: U32
}
trait Trio {
    fn mix(self, left: Left, count: U8, right: Right) -> Unit
}
type Box {
}
impl Trio for Box {
    fn mix(self, left: Left, count: U8, right: Right) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
	{
		"static-two-scalars",
		`trait StaticPair {
    fn ping(first: U64, second: U32) -> Unit
}
type Box {
}
impl StaticPair for Box {
    fn ping(first: U64, second: U32) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
	{
		"mut-cursor-self",
		`trait Fill {
    fn fill(self, mut target: MutSlice(U8), value: U8) -> Unit
}
type Box {
}
impl Fill for Box {
    fn fill(self, mut target: MutSlice(U8), value: U8) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
	{
		"mut-cursor-static",
		`trait Fill {
    fn fill(mut target: MutSlice(U8), value: U8) -> Unit
}
type Box {
}
impl Fill for Box {
    fn fill(mut target: MutSlice(U8), value: U8) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
	{
		"generic-second-parameter",
		`trait Store(Value: type) {
    fn put(self, key: U64, value: Value) -> Unit
}
type Box {
}
impl Store(U32) for Box {
    fn put(self, key: U64, value: U32) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
	{
		"generic-three-parameters",
		`type Name {
    bytes: U64
}
trait Store(Value: type) {
    fn put(self, key: U64, name: Name, value: Value) -> Unit
}
type Box {
}
impl Store(U32) for Box {
    fn put(self, key: U64, name: Name, value: U32) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`,
	},
}

func TestTraitRequirementMultiParameterSignatures(t *testing.T) {
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

	for _, acceptance := range traitParamAcceptance {
		acceptance := acceptance
		t.Run(acceptance.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"params.al": acceptance.source}
			result := runProductionCompiler(t, exe, files, "check", "params.al")
			if result.status != 0 || result.stderr != "" {
				t.Fatalf("%s: %+v", acceptance.name, result)
			}
		})
	}

	t.Run("reject-mismatched-second-parameter", func(t *testing.T) {
		t.Parallel()
		files := map[string]string{"reject.al": `trait Pair {
    fn ping(self, first: U64, second: U32) -> Unit
}
type Box {
}
impl Pair for Box {
    fn ping(self, first: U64, second: U8) -> Unit {
        return
    }
}
fn main() -> I32 { return 0 }
`}
		result := runProductionCompiler(t, exe, files, "check", "reject.al")
		if result.status == 0 || !strings.Contains(result.stderr, "trait implementation method does not match the trait requirement signature") {
			t.Fatalf("mismatched second parameter accepted: %+v", result)
		}
	})
}
