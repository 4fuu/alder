package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// () is the sole Unit value. It is accepted as a return operand, a Unit
// argument, and a unit-payload variant argument. A standalone () statement is
// rejected because only a Unit-result call may stand alone.
const unitLiteralProgram = `fn accept(flag: Bool, value: Unit) -> I32 {
    if flag { return 0 }
    return 1
}
fn nothing() -> Unit {
    return ()
}
fn is_ok(value: Result(Unit, I32)) -> Bool {
    return match value {
        Ok(_) => true
        Err(_) => false
    }
}
fn is_some(value: Option(Unit)) -> Bool {
    return match value {
        Some(_) => true
        None => false
    }
}
fn main() -> I32 {
    let ok: Result(Unit, I32) = Ok(())
    if !is_ok(ok) { return 1 }
    let some: Option(Unit) = Some(())
    if !is_some(some) { return 2 }
    if accept(true, ()) != 0 { return 3 }
    nothing()
    return 0
}
`

var unitLiteralRejections = []struct {
	name, source, want string
}{
	{
		"standalone-statement",
		"fn main() -> I32 {\n    ()\n    return 0\n}\n",
		"unit value statement has no effect",
	},
	{
		"non-unit-argument",
		"fn accept(value: U64) -> I32 {\n    return 0\n}\nfn main() -> I32 {\n    return accept(())\n}\n",
		"checker diagnostic 42",
	},
	{
		"unit-payload-mismatch",
		"fn main() -> I32 {\n    let value: Result(Unit, I32) = Ok(1)\n    return 0\n}\n",
		"binding: type mismatch",
	},
}

func TestUnitLiteralProductionQualification(t *testing.T) {
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
	runtimeObject := buildRuntimeObject(t, cc, root)

	files := map[string]string{"unit.al": unitLiteralProgram}
	mirResult := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "unit.al")
	if mirResult.status != 0 || mirResult.stderr != "" {
		t.Fatalf("emit=mir result: %+v", mirResult)
	}
	if !strings.Contains(mirResult.stdout, ": unit = ()") {
		t.Fatalf("MIR is missing a unit constant:\n%s", mirResult.stdout)
	}
	if strings.Contains(mirResult.stdout, ", ok, %") && strings.Contains(mirResult.stdout, "result(unit") {
		for _, line := range strings.Split(mirResult.stdout, "\n") {
			if strings.Contains(line, "enum.construct") && strings.Contains(line, "result(unit") && strings.Contains(line, ", ok, %") {
				t.Fatalf("unit payload carried an operand: %s", line)
			}
		}
	}

	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "unit.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("emit=c result: %+v", cResult)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	for _, rejection := range unitLiteralRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": rejection.source}, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
