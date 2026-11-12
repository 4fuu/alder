package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// An affine owner may be transferred through a match-arm expression. The arm
// binding owns the payload, the Ok constructor transfers it, and the matched
// result is returned to the caller, which releases it once.
const matchOwnerProgram = `fn make(text: String) -> Result(c.CString, U64) {
    return match c.CString(text) {
        Some(value) => Ok(value)
        None => Err(1)
    }
}

fn main() -> I32 {
    match make("abc".concat("de")) {
        Ok(owner) => {
            using held = owner
        }
        Err(_) => { return 1 }
    }
    return 0
}
`

const matchOwnerDropProgram = `fn make(text: String) -> Result(c.CString, U64) {
    return match c.CString(text) {
        Some(value) => Ok(c.CString("x"))
        None => Err(1)
    }
}

fn main() -> I32 { return 0 }
`

func TestMatchArmOwnerMustTransfer(t *testing.T) {
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
	check := runProductionCompiler(t, exe, map[string]string{"match-owner-drop.al": matchOwnerDropProgram}, "check", "match-owner-drop.al")
	if check.status == 0 || !strings.Contains(check.stderr, "affine owner") {
		t.Fatalf("match owner drop: %+v stderr=%s", check, check.stderr)
	}
}

func TestMatchArmTransfersAffineOwner(t *testing.T) {
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
	result := runProductionCompiler(t, exe, map[string]string{"match-owner.al": matchOwnerProgram}, "compile", "--emit=c", "match-owner.al")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("match owner program: %+v stderr=%s", result, result.stderr)
	}
	runSanitizedGeneratedProgram(t, cc, root, result.stdout)
}
