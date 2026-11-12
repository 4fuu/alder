package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// A function value whose target borrows a parameter carries the same
// safe_mut/owner-domain pair as a direct call. The indirect call borrows the
// caller's view, forwards the owner domain through a `mut` parameter, and the
// write is visible in the original array.
const ownerDomainIndirectProgram = `fn bump(mut view: MutSlice(U8)) -> U8 {
    view[0] = view[0] + 1
    return view[0]
}

fn apply(f: fn(mut MutSlice(U8)) -> U8, mut view: MutSlice(U8)) -> U8 {
    return f(view)
}

fn main() -> I32 {
    var data = Vec.new(U8)
    data.push(1)
    if apply(bump, data.slice_mut(0, 1)) != 2 { return 1 }
    if data[0] != 2 { return 2 }
    return 0
}
`

func TestOwnerDomainIndirectProductionQualification(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	cResult := runProductionCompiler(t, exe, map[string]string{"indirect.al": ownerDomainIndirectProgram}, "compile", "--emit=c", "indirect.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("owner-domain indirect C: %+v", cResult)
	}
	runSanitizedGeneratedProgram(t, cc, root, cResult.stdout)
}
