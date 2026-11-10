package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 byte-sequence surface through the production driver: the len/byte/concat/
// slice/to_bytes/to_string_checked methods on String and Bytes receivers
// compile and run end to end on generated C. Lengths and indices count bytes,
// not characters; slice rejects an inverted or out-of-range range through its
// checked edge; to_string_checked reports invalid UTF-8 as None instead of
// taking a failure edge.

const strMethodsProgram = `fn t_len() -> I32 {
    if "hello".len() != 5 { return 1 }
    if "".len() != 0 { return 2 }
    let accented: String = "héllo"
    if accented.len() != 6 { return 3 }
    let bytes: Bytes = "héllo".to_bytes()
    if bytes.len() != 6 { return 4 }
    return 0
}

fn t_byte() -> I32 {
    let s: String = "hello"
    if s.byte(0) != 104 { return 1 }
    if s.byte(4) != 111 { return 2 }
    let accented: String = "héllo"
    if accented.byte(1) != 195 { return 3 }
    if accented.byte(2) != 169 { return 4 }
    let b: Bytes = "AB".to_bytes()
    if b.byte(1) != 66 { return 5 }
    return 0
}

fn t_concat() -> I32 {
    let s: String = "ab".concat("cd")
    if s.len() != 4 { return 1 }
    if s.byte(2) != 99 { return 2 }
    let a: Bytes = "ab".to_bytes()
    let b: Bytes = "cd".to_bytes()
    let joined: Bytes = a.concat(b)
    if joined.len() != 4 { return 3 }
    if joined.byte(3) != 100 { return 4 }
    let empty: String = "".concat("")
    if empty.len() != 0 { return 5 }
    return 0
}

fn t_slice() -> I32 {
    let s: String = "hello"
    let part: String = s.slice(1, 3)
    if part.len() != 2 { return 1 }
    if part.byte(0) != 101 { return 2 }
    if part.byte(1) != 108 { return 3 }
    let b: Bytes = "abcd".to_bytes()
    let piece: Bytes = b.slice(1, 3)
    if piece.len() != 2 { return 4 }
    if piece.byte(0) != 98 { return 5 }
    let empty_range: Bytes = b.slice(2, 2)
    if empty_range.len() != 0 { return 6 }
    let whole: Bytes = b.slice(0, 4)
    if whole.len() != 4 { return 7 }
    return 0
}

fn t_to_bytes() -> I32 {
    let accented: String = "héllo"
    let b: Bytes = accented.to_bytes()
    if b.len() != 6 { return 1 }
    if b.byte(1) != 195 { return 2 }
    let empty: Bytes = "".to_bytes()
    if empty.len() != 0 { return 3 }
    return 0
}

fn t_to_string_checked() -> I32 {
    let ok: Bytes = "h".to_bytes()
    var code: I32 = 0
    match ok.to_string_checked() {
        Some(text) => { if text.len() != 1 { code = 1 } }
        None => { code = 2 }
    }
    if code != 0 { return code }
    let bad: Bytes = "\xed\xa0\x80"
    match bad.to_string_checked() {
        Some(_) => { code = 3 }
        None => { code = 0 }
    }
    if code != 0 { return code }
    let blank: Bytes = "".to_bytes()
    match blank.to_string_checked() {
        Some(text) => { if text.len() != 0 { code = 4 } }
        None => { code = 5 }
    }
    let accented: Bytes = "héllo".to_bytes()
    match accented.to_string_checked() {
        Some(text) => { if text.len() != 6 { code = 6 } }
        None => { code = 7 }
    }
    return code
}

fn main() -> I32 {
    let a = t_len()
    if a != 0 { return a }
    let b = t_byte()
    if b != 0 { return b }
    let c = t_concat()
    if c != 0 { return c }
    let d = t_slice()
    if d != 0 { return d }
    let e = t_to_bytes()
    if e != 0 { return e }
    let f = t_to_string_checked()
    if f != 0 { return f }
    return 0
}
`

var strMethodsRejections = []struct {
	name, source, want string
}{
	{
		"bool-receiver-len",
		"fn f(b: Bool) -> I32 {\n    return b.len()\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 61",
	},
	{
		"integer-receiver-concat",
		"fn f(a: I64) -> I64 {\n    return a.concat(a)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 61",
	},
	{
		"bytes-to-bytes",
		"fn f(b: Bytes) -> Bytes {\n    return b.to_bytes()\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 61",
	},
	{
		"string-to-string-checked",
		"fn f(s: String) -> I32 {\n    match s.to_string_checked() {\n        Some(_) => { return 1 }\n        None => { return 0 }\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 61",
	},
	{
		"len-arity",
		"fn f(s: String) -> U64 {\n    return s.len(1)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
	{
		"concat-arity",
		"fn f(s: String) -> String {\n    return s.concat()\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
	{
		"byte-arity",
		"fn f(s: String) -> U8 {\n    return s.byte()\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
	{
		"concat-mixed-operand",
		"fn f(s: String) -> String {\n    return s.concat(5)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 42",
	},
	{
		"byte-non-index-arg",
		"fn f(s: String) -> U8 {\n    return s.byte(s)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 42",
	},
	{
		"slice-non-range-arg",
		"fn f(s: String) -> String {\n    return s.slice(\"a\", 1)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 42",
	},
	{
		"slice-arity",
		"fn f(s: String) -> String {\n    return s.slice(1)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
	{
		"to-bytes-arity",
		"fn f(s: String) -> Bytes {\n    return s.to_bytes(1)\n}\nfn main() -> I32 { return 0 }\n",
		"checker diagnostic 41",
	},
}

func TestStrMethodsProductionQualification(t *testing.T) {
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

	files := map[string]string{"str-methods.al": strMethodsProgram}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "str-methods.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("str methods MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "str-methods.al")
	if repeat != mirText {
		t.Fatal("str methods MIR changed across processes")
	}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "str-methods.al")
	if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("str methods C result: %+v stderr=%s", cResult, cResult.stderr)
	}
	assertPublicMIR(t, "str-methods.al", mirText.stdout)
	if strings.Contains(cResult.stdout, "__s0_") {
		t.Fatal("str methods generated C exposes bootstrap names")
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	for _, rejection := range strMethodsRejections {
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
