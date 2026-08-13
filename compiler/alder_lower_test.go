package compiler

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

func runLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"types.al": `import c foreign: fn(U64) -> U64
type Pair {
    value: U64
}
enum Maybe {
    None
    Some(value: U64)
}
fn identity(T: type, value: T) -> T { return value }
fn make_pair(value: U64) -> Pair { return Pair(value: value) }
fn make_some(value: U64) -> Maybe { return Some(value) }
`,
		"control.al": `fn calculate(value: U64) -> U64 {
    var next = value
    while next < 3 {
        next = next + 1
    }
    if next == 3 {
        return next
    } else {
        let fallback = identity(U64, 0)
        return unsafe c { foreign(fallback) }
    }
}
fn short(left: Bool, right: Bool) -> Bool {
    return left && right
}
fn sum(values: [U64]) -> U64 {
    var total: U64 = 0
    for value in values {
        total = total + value
    }
    return total
}
`,
		"match_try.al": `fn checked(n: I64, d: I64) -> Result(I64, I64) {
    if d == 0 {
        return Err(1)
    }
    return Ok(n / d)
}
fn propagate(d: I64) -> Result(I64, I64) {
    let q = try checked(10, d)
    return Ok(q)
}
fn choose(value: Maybe) -> U64 {
    return match value {
        None => 0
        Some(item) => item
    }
}
`,
		"cleanup.al": `import c counter: fn(I64) -> Unit
fn close(value: I64) -> Unit {
    unsafe c { counter(value) }
}
fn attempt(bad: Bool) -> I32 {
    using handle = 5 with close
    if bad {
        return 7
    }
    return 0
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"types.al", "control.al", "match_try.al", "cleanup.al"})
	second := runLowerCompiler(t, exe, files, []string{"cleanup.al", "match_try.al", "control.al", "types.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("lowered MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify lowered MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	for _, name := range []string{"make_pair", "make_some", "calculate", "short", "sum", "checked", "propagate", "choose", "close", "attempt"} {
		if _, ok := module.Function(name); !ok {
			t.Fatalf("lowered MIR has no function %q\n%s", name, first)
		}
	}
	foundIdentity := false
	for _, function := range module.Functions {
		if strings.HasPrefix(function.Name, "identity") {
			foundIdentity = true
		}
	}
	if !foundIdentity {
		t.Fatalf("lowered MIR has no concrete identity instance\n%s", first)
	}
	runMalformedLowerCompiler(t, exe)
}

func runMalformedLowerCompiler(t *testing.T, exe string) {
	t.Helper()
	dir := t.TempDir()
	for name, text := range map[string]string{
		"!alder-core-lower-bad": "",
		"bad.al":                "fn bad() -> Unit {}\n",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command(exe, "!alder-core-lower-bad", "bad.al")
	cmd.Dir = dir
	if output, err := cmd.CombinedOutput(); err != nil || len(output) != 0 {
		t.Fatalf("malformed checked owner was not rejected: %v\n%s", err, output)
	}
}

func runLowerCompiler(t *testing.T, exe string, files map[string]string, order []string) []byte {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "!alder-core-lower"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	args := append([]string{"!alder-core-lower"}, order...)
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("run lower compiler: %v\nstdout:\n%s\nstderr:\n%s", err, stdout.Bytes(), stderr.Bytes())
	}
	if stderr.Len() != 0 {
		t.Fatalf("lower compiler wrote stderr: %s", stderr.Bytes())
	}
	return stdout.Bytes()
}
