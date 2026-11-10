package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 integer overflow surface through the production driver: the
// checked/saturating/wrapping methods on integer receivers compile and run
// end to end on generated C. Checked methods report overflow as Option(T)
// (none) instead of the panicking fail edge, saturating methods clamp at the
// type bounds, and wrapping methods wrap modulo 2^width.

const intMethodsProgram = `fn t_checked_i64() -> I32 {
    let big: I64 = 4611686018427387904
    var code: I32 = 9
    match big.add_checked(big) {
        Some(_) => { code = 1 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    let a: I64 = 21
    match a.add_checked(a) {
        Some(v) => { if v != 42 { code = 2 } }
        None => { code = 3 }
    }
    if code != 0 { return code }
    match big.mul_checked(big) {
        Some(_) => { code = 4 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    let lo: I64 = -4611686018427387904
    match lo.sub_checked(lo) {
        Some(v) => { if v != 0 { code = 5 } }
        None => { code = 6 }
    }
    return code
}

fn t_checked_narrow() -> I32 {
    let b: I8 = 100
    var code: I32 = 9
    match b.add_checked(b) {
        Some(_) => { code = 1 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    match b.add_checked(20) {
        Some(v) => { if v != 120 { code = 2 } }
        None => { code = 3 }
    }
    if code != 0 { return code }
    let u: U8 = 200
    match u.add_checked(u) {
        Some(_) => { code = 4 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    let w: U16 = 400
    match w.mul_checked(w) {
        Some(_) => { code = 5 }
        None => { code = 0 }
    }
    return code
}

fn t_checked_u64() -> I32 {
    let m: U64 = 18446744073709551615
    var code: I32 = 9
    match m.add_checked(1) {
        Some(_) => { code = 1 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    match m.mul_checked(2) {
        Some(_) => { code = 2 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    match m.sub_checked(m) {
        Some(v) => { if v != 0 { code = 3 } }
        None => { code = 4 }
    }
    return code
}

fn t_saturating() -> I32 {
    let lo: I64 = -4611686018427387904
    let min: I64 = lo.add_wrapping(lo)
    let max: I64 = min.sub_wrapping(1)
    if max.add_saturating(1) != max { return 1 }
    if min.sub_saturating(1) != min { return 2 }
    if min.mul_saturating(-1) != max { return 3 }
    if lo.add_saturating(lo) != min { return 4 }
    let b: I8 = 127
    if b.add_saturating(1) != 127 { return 5 }
    if b.add_saturating(0) != 127 { return 6 }
    let n: I8 = -128
    if n.add_saturating(-1) != -128 { return 7 }
    let u: U8 = 200
    if u.add_saturating(100) != 255 { return 8 }
    if u.sub_saturating(250) != 0 { return 9 }
    let m: U64 = 18446744073709551615
    if m.mul_saturating(2) != m { return 10 }
    if m.sub_saturating(m) != 0 { return 11 }
    return 0
}

fn t_wrapping() -> I32 {
    let lo: I64 = -4611686018427387904
    let min: I64 = lo.add_wrapping(lo)
    let max: I64 = min.sub_wrapping(1)
    if max.add_wrapping(1) != min { return 1 }
    if min.sub_wrapping(1) != max { return 2 }
    if min.mul_wrapping(-1) != min { return 3 }
    let b: I8 = 127
    if b.add_wrapping(1) != -128 { return 4 }
    let u: U8 = 255
    if u.add_wrapping(1) != 0 { return 5 }
    if u.mul_wrapping(2) != 254 { return 6 }
    let m: U64 = 18446744073709551615
    if m.add_wrapping(1) != 0 { return 7 }
    if m.mul_wrapping(m) != 1 { return 8 }
    return 0
}

fn main() -> I32 {
    let a = t_checked_i64()
    if a != 0 { return a }
    let b = t_checked_narrow()
    if b != 0 { return b }
    let c = t_checked_u64()
    if c != 0 { return c }
    let d = t_saturating()
    if d != 0 { return d }
    let e = t_wrapping()
    if e != 0 { return e }
    return 0
}
`

var intMethodsRejections = []struct {
	name, source, want string
}{
	{
		"bool-receiver",
		"fn f(b: Bool) -> I32 {\n    match b.add_checked(b) {\n        Some(_) => { return 1 }\n        None => { return 0 }\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 61",
	},
	{
		"float-receiver",
		"fn f(a: F64) -> I32 {\n    return a.add_checked(a)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 61",
	},
	{
		"mixed-operand-types",
		"fn f(a: I64, b: U64) -> I32 {\n    match a.add_checked(b) {\n        Some(_) => { return 1 }\n        None => { return 0 }\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 42",
	},
	{
		"missing-argument",
		"fn f(a: I64) -> I32 {\n    match a.add_checked() {\n        Some(_) => { return 1 }\n        None => { return 0 }\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
	{
		"extra-argument",
		"fn f(a: I64) -> I32 {\n    match a.add_checked(a, a) {\n        Some(_) => { return 1 }\n        None => { return 0 }\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
	{
		"option-into-integer",
		"fn f(a: I64) -> I64 {\n    let x: I64 = a.add_checked(a)\n    return x\n}\nfn main() -> I32 { return 0 }\n",
		"binding: type mismatch: expected I64, got <unknown>",
	},
}

func TestIntMethodsProductionQualification(t *testing.T) {
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

	files := map[string]string{"int-methods.al": intMethodsProgram}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "int-methods.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("int methods MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "int-methods.al")
	if repeat != mirText {
		t.Fatal("int methods MIR changed across processes")
	}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "int-methods.al")
	if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("int methods C result: %+v stderr=%s", cResult, cResult.stderr)
	}
	assertPublicMIR(t, "int-methods.al", mirText.stdout)
	if strings.Contains(cResult.stdout, "__s0_") {
		t.Fatal("int methods generated C exposes bootstrap names")
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	for _, rejection := range intMethodsRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
