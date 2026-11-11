package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 float literal surface through the production driver: an F32-typed float
// literal must denote a value binary32 represents exactly, so the written
// decimal digits name the stored value and the MIR verifier's exact-f32
// constant rule can never fail behind the checker's back. The checker
// rejects a magnitude beyond F32's range with diagnostic 255 and any other
// literal rounding would change with 256, at the literal site and through
// an expected F32 argument type; F64 literals stay unrestricted.

const floatLiteralProgram = `fn takes_f32(x: F32) -> F32 { return x }

fn main() -> I32 {
    let one: F32 = 1.0
    if one != 1.0 { return 1 }
    let negative: F32 = -2.5
    if negative != -2.5 { return 2 }
    let exponent: F32 = 9.9999997473787516e-05
    if exponent != 9.9999997473787516e-05 { return 3 }
    let pi_wide: F32 = 3.1415927410125732
    if pi_wide < 3.0 || pi_wide > 4.0 { return 4 }
    if takes_f32(2.0) != 2.0 { return 5 }
    let double_any: F64 = 3.141592653589793
    if double_any < 3.14159265358979 || double_any > 3.14159265358980 { return 6 }
    let tiny: F64 = 1.0e-300
    if tiny <= 0.0 { return 7 }
    return 0
}
`

var floatLiteralRejections = []struct {
	name, source, want string
}{
	{
		"out-of-range-annotation",
		"fn main() -> I32 {\n    let a: F32 = 1.0e39\n    return 0\n}\n",
		"float literal is out of range for F32",
	},
	{
		"out-of-range-argument",
		"fn f(x: F32) -> F32 { return x }\nfn main() -> I32 {\n    let a = f(1.0e39)\n    return 0\n}\n",
		"float literal is out of range for F32",
	},
	{
		"inexact-annotation",
		"fn main() -> I32 {\n    let a: F32 = 3.14159265\n    return 0\n}\n",
		"float literal is not exactly representable as F32",
	},
	{
		"inexact-argument",
		"fn f(x: F32) -> F32 { return x }\nfn main() -> I32 {\n    let a = f(3.14159265)\n    return 0\n}\n",
		"float literal is not exactly representable as F32",
	},
	{
		"inexact-comparison-operand",
		"fn f(x: F32) -> Bool { return x < 0.0001 }\nfn main() -> I32 { return 0 }\n",
		"float literal is not exactly representable as F32",
	},
	{
		"underflow-to-zero",
		"fn main() -> I32 {\n    let a: F32 = 1.0e-60\n    return 0\n}\n",
		"float literal is not exactly representable as F32",
	},
}

func TestFloatLiteralProductionQualification(t *testing.T) {
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

	files := map[string]string{"float-literal.al": floatLiteralProgram}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "float-literal.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("emit=c result: %+v stderr=%s", cResult, cResult.stderr)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	for _, rejection := range floatLiteralRejections {
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
