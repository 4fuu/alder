package compiler

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/cgen"
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
		"scalar.al": `fn scalar(pair: Pair, values: [U64], flag: Bool) -> U64 {
    let called = identity(U64, pair.value + values[0])
    if !flag {
        return called % 3
    }
    return unsafe c { foreign(called) }
}
fn floating() -> F64 { return 1.5 }
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
fn before_using(bad: Bool) -> I32 {
    if bad { return 1 }
    using handle = 2 with close
    return 0
}
fn nested_cleanup() -> I32 {
    {
        using inner = 3 with close
    }
    using outer = 4 with close
    return 0
}
fn cleanup_try(bad: Bool) -> Result(I64, I64) {
    using handle = 6 with close
    let divisor: I64 = 2
    if bad { return Ok(try checked(10, 0)) }
    return Ok(try checked(10, divisor))
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"types.al", "scalar.al", "control.al", "match_try.al", "cleanup.al"})
	second := runLowerCompiler(t, exe, files, []string{"cleanup.al", "match_try.al", "control.al", "scalar.al", "types.al"})
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
	for _, name := range []string{"make_pair", "make_some", "scalar", "floating", "calculate", "short", "sum", "checked", "propagate", "choose", "close", "attempt", "before_using", "nested_cleanup", "cleanup_try"} {
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
	checkLowerGolden(t, "lower-all.golden", first)
	runLowerCgenBehavior(t, module)
	runMalformedLowerCompiler(t, exe)
}

func runLowerCgenBehavior(t *testing.T, module *mir.Module) {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	generated, err := cgen.Generate(module)
	if err != nil {
		t.Fatal(err)
	}
	functionID := func(name string) mir.FunctionId {
		id, ok := module.Function(name)
		if !ok {
			t.Fatalf("missing function %s", name)
		}
		return id
	}
	calculate := functionID("calculate")
	short := functionID("short")
	sum := functionID("sum")
	choose := functionID("choose")
	propagate := functionID("propagate")
	attempt := functionID("attempt")
	beforeUsing := functionID("before_using")
	nestedCleanup := functionID("nested_cleanup")
	cleanupTry := functionID("cleanup_try")
	maybeType := module.Functions[choose].Params[0].Type
	resultType := module.Functions[propagate].Result
	none, _ := module.VariantIndex(maybeType, "None")
	some, _ := module.VariantIndex(maybeType, "Some")
	ok, _ := module.VariantIndex(resultType, "ok")
	errVariant, _ := module.VariantIndex(resultType, "err")
	driver := fmt.Sprintf(`
static int64_t alder_test_cleanup;
uint64_t foreign(uint64_t value) { return value; }
void counter(int64_t value) { alder_test_cleanup += value; }
int main(void) {
  uint64_t values[3] = {1, 2, 3};
  AlderSlice slice = {(void *)values, 3};
  AlderTy%d none = {0};
  AlderTy%d some = {0};
  AlderTy%d success;
  AlderTy%d failure;
  none.alder_tag = %d;
  some.alder_tag = %d;
  some.alder_u.alder_p%d = 9;
  if (alder_fn_calculate_%d(0) != 3) return 1;
  if (!alder_fn_short_%d(true, true) || alder_fn_short_%d(true, false)) return 2;
  if (alder_fn_sum_%d(slice) != 6) return 3;
  if (alder_fn_choose_%d(none) != 0 || alder_fn_choose_%d(some) != 9) return 4;
  success = alder_fn_propagate_%d(2);
  failure = alder_fn_propagate_%d(0);
  if (success.alder_tag != %d || failure.alder_tag != %d) return 5;
  if (alder_fn_attempt_%d(false) != 0 || alder_test_cleanup != 5) return 6;
  if (alder_fn_attempt_%d(true) != 7 || alder_test_cleanup != 10) return 7;
  if (alder_fn_before_using_%d(true) != 1 || alder_test_cleanup != 10) return 8;
  if (alder_fn_before_using_%d(false) != 0 || alder_test_cleanup != 12) return 9;
  if (alder_fn_nested_cleanup_%d() != 0 || alder_test_cleanup != 19) return 10;
  (void)alder_fn_cleanup_try_%d(false);
  if (alder_test_cleanup != 25) return 11;
  (void)alder_fn_cleanup_try_%d(true);
  if (alder_test_cleanup != 31) return 12;
  return 0;
}
`, maybeType, maybeType, resultType, resultType, none, some, some, calculate, short, short, sum, choose, choose, propagate, propagate, ok, errVariant, attempt, attempt, beforeUsing, beforeUsing, nestedCleanup, cleanupTry, cleanupTry)
	dir := t.TempDir()
	file := filepath.Join(dir, "lower-behavior.c")
	if err := os.WriteFile(file, []byte(generated+driver), 0o644); err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(dir, "lower-behavior.exe")
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile lowered C: %v\n%s", err, output)
	}
	if output, err := exec.Command(exe).CombinedOutput(); err != nil {
		t.Fatalf("run lowered C: %v\n%s", err, output)
	}
	for _, block := range module.Functions[sum].Blocks {
		if len(block.Params) >= 2 {
			return
		}
	}
	t.Fatal("slice-for lowering has no two-parameter edge for parallel-copy evidence")
}

func checkLowerGolden(t *testing.T, name string, got []byte) {
	t.Helper()
	path := filepath.Join("testdata", name)
	if os.Getenv("UPDATE_GOLDEN") == "1" {
		if err := os.WriteFile(path, got, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("lowered MIR differs from %s", path)
	}
}

func runMalformedLowerCompiler(t *testing.T, exe string) {
	t.Helper()
	for _, mode := range []string{"!alder-core-lower-bad", "!alder-core-lower-bad-k", "!alder-core-lower-bad-m", "!alder-core-lower-bad-w", "!alder-core-lower-bad-x", "!alder-core-lower-bad-g"} {
		t.Run(strings.TrimPrefix(mode, "!alder-core-lower-bad"), func(t *testing.T) {
			dir := t.TempDir()
			for name, text := range map[string]string{mode: "", "bad.al": "fn bad() -> Unit {}\n"} {
				if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			cmd := exec.Command(exe, mode, "bad.al")
			cmd.Dir = dir
			if output, err := cmd.CombinedOutput(); err != nil || len(output) != 0 {
				t.Fatalf("malformed checked model was not rejected with zero output: %v\n%s", err, output)
			}
		})
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
