package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// A take parameter transfers affine owners and copies copyable values. The
// caller keeps a copyable binding usable, including through a generic
// parameter and a take-self receiver.
const takeCopyableProgram = `type Copy {
    n: U64
}

impl Copy {
    fn read_it(take self) -> U64 {
        return self.n
    }
}

fn forward(T: type, take value: T) -> T {
    return value
}

fn take_number(take value: U64) -> U64 {
    return value
}

fn main() -> I32 {
    let item = Copy(n: 7)
    let first = forward(Copy, item)
    let second = item.read_it()
    let third = item.read_it()
    if first.n != 7 || second != 7 || third != 7 { return 1 }
    let number: U64 = 5
    let copy = take_number(number)
    if copy != 5 || number != 5 { return 2 }
    return 0
}
`

func TestTakeCopyableSemantics(t *testing.T) {
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
	result := runProductionCompiler(t, exe, map[string]string{"take-copyable.al": takeCopyableProgram}, "compile", "--emit=c", "take-copyable.al")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("take copyable program: %+v stderr=%s", result, result.stderr)
	}
	runSanitizedGeneratedProgram(t, cc, root, result.stdout)
}
