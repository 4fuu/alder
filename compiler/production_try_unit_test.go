package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A `try` on Result(Unit, E) has no ok payload to bind. MIR forbids a switch
// case binding of unit type, so the ok case must carry no payload and the try
// expression must still lower. The regression compiled but the verifier
// refused the module before the ok payload was omitted.
const tryUnitProgram = `fn nothing() -> Result(Unit, U64) {
    return Ok(())
}
fn run() -> Result(Unit, U64) {
    try nothing()
    return Ok(())
}
fn main() -> I32 {
    return match run() {
        Ok(_) => 0
        Err(_) => 1
    }
}
`

func TestTryUnitResultLowers(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)

	files := map[string]string{"try-unit.al": tryUnitProgram}
	check := runPrivateProductionCompiler(t, exe, files, "check", "try-unit.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("try-unit check result: %+v stderr=%s", check, check.stderr)
	}
	mirText := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=mir", "try-unit.al")
	if mirText.status != 0 || mirText.stderr != "" {
		t.Fatalf("try-unit MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	if !strings.Contains(mirText.stdout, "ok -> ") {
		t.Fatalf("try-unit MIR binds a unit ok payload:\n%s", mirText.stdout)
	}
	if strings.Contains(mirText.stdout, "ok(%") {
		t.Fatalf("try-unit MIR carries an ok payload binding:\n%s", mirText.stdout)
	}
	cResult := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=c", "try-unit.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("try-unit C result: %+v stderr=%s", cResult, cResult.stderr)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
}
