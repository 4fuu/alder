package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The total bitwise family through the production driver: & | ^ are
// same-type integer binaries and ~ is the integer complement. The generated C
// applies them to the unsigned type of the operand width, so signed operands
// keep the fixed-width two's-complement result with no undefined behavior.
const bitwiseProgram = `fn main() -> I32 {
    var a: U32 = 12
    var b: U32 = 10
    let c = a & b
    let d = a | b
    let e = a ^ b
    if c != 8 { return 1 }
    if d != 14 { return 2 }
    if e != 6 { return 3 }
    var zero: U32 = 0
    if ~zero != 4294967295 { return 4 }
    if ~a != 4294967283 { return 5 }
    var s: I8 = -2
    if ~s != 1 { return 6 }
    var m: I8 = -1
    if m & 15 != 15 { return 7 }
    if m | 0 != -1 { return 8 }
    if m ^ m != 0 { return 9 }
    var big: U64 = 1099511627776
    var one: U64 = 1
    if big & 255 != 0 { return 10 }
    if (one << 40) != big { return 11 }
    var p1: U32 = 1
    var p2: U32 = 2
    var p3: U32 = 3
    var p4: U32 = 4
    if (p1 | p2 ^ p3 & p4 << 1) != 3 { return 12 }
    return 0
}
`

var bitwiseRejections = []struct {
	name, source, want string
}{
	{
		"bool-operand",
		"fn main() -> I32 {\n    let a = true & false\n    return 0\n}\n",
		"operator & requires integer operands",
	},
	{
		"float-operand",
		"fn main() -> I32 {\n    let a = 1.0 | 2.0\n    return 0\n}\n",
		"operator | requires integer operands",
	},
	{
		"mixed-width",
		"fn main() -> I32 {\n    let a: U8 = 1\n    let b: U64 = 2\n    let c = a ^ b\n    return 0\n}\n",
		"operator ^ requires same-type integer operands: expected U8, got U64",
	},
	{
		"bool-complement",
		"fn main() -> I32 {\n    let a = ~true\n    return 0\n}\n",
		"operator ~ requires integer operands",
	},
	{
		"float-complement",
		"fn main() -> I32 {\n    let a = ~1.0\n    return 0\n}\n",
		"operator ~ requires integer operands",
	},
}

func TestBitwiseProductionQualification(t *testing.T) {
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

	files := map[string]string{"bitwise.al": bitwiseProgram}
	mirResult := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "bitwise.al")
	if mirResult.status != 0 || mirResult.stderr != "" {
		t.Fatalf("emit=mir result: %+v", mirResult)
	}
	for _, op := range []string{"int.and", "int.or", "int.xor", "int.not"} {
		if !strings.Contains(mirResult.stdout, op) {
			t.Fatalf("MIR is missing %s:\n%s", op, mirResult.stdout)
		}
	}
	for _, line := range strings.Split(mirResult.stdout, "\n") {
		if (strings.Contains(line, "int.and") || strings.Contains(line, "int.or") ||
			strings.Contains(line, "int.xor") || strings.Contains(line, "int.not")) &&
			strings.Contains(line, " else") {
			t.Fatalf("total bitwise operation printed a failure edge: %s", line)
		}
	}

	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "bitwise.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("emit=c result: %+v", cResult)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	for _, rejection := range bitwiseRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			rejectFiles := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, rejectFiles, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
