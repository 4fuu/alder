package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// A storage-model mut receiver carries a hidden owner domain immediately after
// its safe_mut parameter, and the caller passes that owner with the borrowed
// argument. The pair is verifier-visible and the generated C still runs.
const ownerDomainProgram = `type Buf {
    data: Vec(U8)
    n: U64
}

impl Buf {
    fn new() -> Buf { return Buf(data: Vec.new(U8), n: 0) }
    fn bump(mut self) -> Unit {
        self.n = self.n + 1
        return
    }
    fn count(self) -> U64 { return self.n }
}

fn main() -> I32 {
    var b = Buf.new()
    b.bump()
    if b.count() != 1 { return 1 }
    return 0
}
`

func TestOwnerDomainMIRQualification(t *testing.T) {
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
	files := map[string]string{"owner.al": ownerDomainProgram}

	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "owner.al")
	if mirText.status != 0 || mirText.stderr != "" {
		t.Fatalf("owner-domain MIR: %+v", mirText)
	}
	module, err := mir.Parse(mirText.stdout)
	if err != nil {
		t.Fatalf("parse owner-domain MIR: %v\n%s", err, mirText.stdout)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify owner-domain MIR: %s", verify.Errors(diagnostics).String())
	}
	found := false
	for _, function := range module.Functions {
		if !strings.HasPrefix(function.Name, "bump") {
			continue
		}
		for at, param := range function.Params {
			if !module.ValidType(param.Type) || module.Types[param.Type].Kind != mir.TypeSafeMut {
				continue
			}
			if at+1 >= len(function.Params) || !module.ValidType(function.Params[at+1].Type) || module.Types[function.Params[at+1].Type].Kind != mir.TypeDomainHandle {
				t.Fatalf("bump safe_mut parameter has no owner domain: %+v", function.Params)
			}
			found = true
		}
	}
	if !found {
		t.Fatalf("owner-domain MIR has no mut receiver pair:\n%s", mirText.stdout)
	}

	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "owner.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("owner-domain C: %+v", cResult)
	}
	compileAndRunProductionArtifact(t, cc, root, buildRuntimeObject(t, cc, root), cResult.stdout, 0)
}
