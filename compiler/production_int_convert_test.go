package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 integer conversion surface through the production driver: the widening
// to_T methods are total on every widening pair, the lossy to_T form is
// rejected at compile time in favor of to_T_checked (Option of the target,
// None off-range) and to_T_wrapping (two's-complement truncation), and
// identity conversions are rejected. Every width edge is exercised on
// generated C: 127/128, 255, 32767/32768, 65535, 2147483647/2147483648,
// 4294967295, 2^63 for U64->I64, and the -1 round trips.
const intConvertProgram = `fn widen_u8(x: U8) -> I64 {
    return x.to_i64()
}

fn t_widen() -> I32 {
    let small: U8 = 255
    if widen_u8(small) != 255 { return 1 }
    let b: U16 = 65535
    if b.to_i32() != 65535 { return 2 }
    let c: U32 = 4294967295
    if c.to_i64() != 4294967295 { return 3 }
    let d: I8 = -128
    if d.to_i64() != -128 { return 4 }
    let e: I16 = -32768
    if e.to_i32() != -32768 { return 5 }
    let f: I32 = -2147483648
    if f.to_i64() != -2147483648 { return 6 }
    let g: U8 = 0
    if g.to_u64() != 0 { return 7 }
    let h: U16 = 40000
    if h.to_u32() != 40000 { return 8 }
    return 0
}

fn t_checked() -> I32 {
    let hi: U8 = 127
    match hi.to_i8_checked() {
        Some(v) => { if v != 127 { return 1 } }
        None => { return 2 }
    }
    let over: U8 = 128
    match over.to_i8_checked() {
        Some(_) => { return 3 }
        None => {}
    }
    let in_range: U16 = 200
    match in_range.to_u8_checked() {
        Some(v) => { if v != 200 { return 4 } }
        None => { return 5 }
    }
    let neg: I8 = -1
    match neg.to_u8_checked() {
        Some(_) => { return 6 }
        None => {}
    }
    let mid: U16 = 32768
    match mid.to_i16_checked() {
        Some(_) => { return 7 }
        None => {}
    }
    let fits: U16 = 20000
    match fits.to_i16_checked() {
        Some(v) => { if v != 20000 { return 8 } }
        None => { return 9 }
    }
    let big: U32 = 2147483648
    match big.to_i32_checked() {
        Some(_) => { return 10 }
        None => {}
    }
    let boundary: U32 = 2147483647
    match boundary.to_i32_checked() {
        Some(v) => { if v != 2147483647 { return 11 } }
        None => { return 12 }
    }
    let huge: U64 = 9223372036854775808
    match huge.to_i64_checked() {
        Some(_) => { return 13 }
        None => {}
    }
    let fits64: U64 = 4294967295
    match fits64.to_i64_checked() {
        Some(v) => { if v != 4294967295 { return 19 } }
        None => { return 20 }
    }
    let below: I64 = -1
    match below.to_u64_checked() {
        Some(_) => { return 14 }
        None => {}
    }
    let shrink: I64 = 2147483648
    match shrink.to_i32_checked() {
        Some(_) => { return 15 }
        None => {}
    }
    let byte_ok: U32 = 255
    match byte_ok.to_u8_checked() {
        Some(v) => { if v != 255 { return 16 } }
        None => { return 17 }
    }
    let byte_over: U32 = 256
    match byte_over.to_u8_checked() {
        Some(_) => { return 18 }
        None => {}
    }
    return 0
}

fn t_wrapping() -> I32 {
    let over: U8 = 128
    if over.to_i8_wrapping() != -128 { return 1 }
    let all: U8 = 255
    if all.to_i8_wrapping() != -1 { return 2 }
    let neg: I8 = -1
    if neg.to_u8_wrapping() != 255 { return 3 }
    let huge: U64 = 18446744073709551615
    if huge.to_i64_wrapping() != -1 { return 4 }
    let edge: U64 = 9223372036854775808
    let back: I64 = edge.to_i64_wrapping()
    if back >= 0 { return 5 }
    if back.to_u64_wrapping() != edge { return 6 }
    let below: I64 = -1
    if below.to_u64_wrapping() != 18446744073709551615 { return 7 }
    let shrink: I64 = 2147483648
    if shrink.to_i32_wrapping() != -2147483648 { return 8 }
    let byte_over: U32 = 256
    if byte_over.to_u8_wrapping() != 0 { return 9 }
    let byte_neg: I64 = 300
    if byte_neg.to_u8_wrapping() != 44 { return 10 }
    let half: U32 = 4294967295
    if half.to_i32_wrapping() != -1 { return 11 }
    return 0
}

fn main() -> I32 {
    let a = t_widen()
    if a != 0 { return a }
    let b = t_checked()
    if b != 0 { return b + 20 }
    let c = t_wrapping()
    if c != 0 { return c + 40 }
    return 0
}
`

var intConvertRejections = []struct {
	name, source, want string
}{
	{
		"lossy-narrowing-bare",
		"fn f(a: U8) -> I8 {\n    return a.to_i8()\n}\nfn main() -> I32 { return 0 }\n",
		`integer conversion method "to_i8" is not total because some receiver values do not fit the target; use the checked form "to_i8_checked"`,
	},
	{
		"identity",
		"fn f(a: I64) -> I64 {\n    return a.to_i64()\n}\nfn main() -> I32 { return 0 }\n",
		`integer conversion method "to_i64" converts a type to itself and has no effect`,
	},
	{
		"needless-checked",
		"fn f(a: U8) -> I64 {\n    return a.to_i64_checked()\n}\nfn main() -> I32 { return 0 }\n",
		`integer conversion method "to_i64_checked" is not needed because every receiver value fits the target`,
	},
	{
		"needless-wrapping",
		"fn f(a: U8) -> I64 {\n    return a.to_i64_wrapping()\n}\nfn main() -> I32 { return 0 }\n",
		`integer conversion method "to_i64_wrapping" is not needed because every receiver value fits the target`,
	},
	{
		"string-receiver-convert",
		"fn f(s: String) -> I64 {\n    return s.to_i64()\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
}

func TestIntConvertProductionQualification(t *testing.T) {
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

	files := map[string]string{"int-convert.al": intConvertProgram}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "int-convert.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "int-convert.al")
	if repeat != mirText {
		t.Fatalf("MIR changed across processes")
	}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "int-convert.al")
	if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("C result: %+v stderr=%s", cResult, cResult.stderr)
	}
	assertPublicMIR(t, "int-convert.al", mirText.stdout)
	if strings.Contains(cResult.stdout, "__s0_") {
		t.Fatalf("generated C exposes bootstrap names")
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	for _, rejection := range intConvertRejections {
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
