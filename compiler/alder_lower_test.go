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
type BridgeKey {
    active: Bool
    group: U8
    code: U64
}
enum BridgeTag {
    Empty
    Value(value: BridgeKey)
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
    using outer = 4 with close
    {
        using inner = 3 with close
    }
    return 0
}
fn cleanup_try(bad: Bool) -> Result(I64, I64) {
    using handle = 6 with close
    let divisor: I64 = 2
    if bad { return Ok(try checked(10, 0)) }
    return Ok(try checked(10, divisor))
}
`,
		"bridge.al": `import c test_clear_domain_alloc_failure: fn() -> Unit
fn allocated_length(d: Domain) -> U64 {
    let values = __s0_alloc(U64, d, 2)
    return len(values)
}
fn domain_bridge(d: Domain) -> U64 {
    let child = __s0_domain_create(d)
    let count = allocated_length(child)
    __s0_domain_reset(child, __s0_domain_mark(child))
    __s0_domain_destroy(child)
    return count
}
fn option_value(value: Option(U64), missing: U64) -> U64 {
    return match value { None => missing
        Some(item) => item }
}
fn map_bridge(d: Domain) -> I32 {
    var values = __s0_map_create(Map(U64, U64), d)
    Set(values, 1, 10)
    Set(values, 17, 20)
    if !Remove(values, 1) { return 1 }
    Set(values, 33, 30)
    let found: U64 = match Get(values, 33) {
        None => 0
        Some(value) => value
    }
    if found != 30 { return 2 }
    return 0
}
fn map_probe_bridge(d: Domain) -> I32 {
    var values = __s0_map_create(Map(U64, U64), d)
    var index: U64 = 0
    while index < 14 {
        let key = index * 16 + 1
        Set(values, key, index)
        index = index + 1
    }
    Set(values, 81, 99)
    let updated = option_value(Get(values, 81), 0)
    if updated != 99 { return 1 }
    if !Remove(values, 81) { return 2 }
    if Remove(values, 81) { return 3 }
    Set(values, 225, 77)
    let reused = option_value(Get(values, 225), 0)
    if reused != 77 { return 4 }
    let retained = option_value(Get(values, 209), 99)
    if retained != 13 { return 5 }
    return 0
}
fn map_structural_bridge(d: Domain) -> I32 {
    var records = __s0_map_create(Map(BridgeKey, U64), d)
    Set(records, BridgeKey(active: true, group: 2, code: 9), 41)
    let record = option_value(Get(records, BridgeKey(active: true, group: 2, code: 9)), 0)
    if record != 41 { return 1 }
    var variants = __s0_map_create(Map(BridgeTag, U64), d)
    Set(variants, Value(BridgeKey(active: false, group: 3, code: 7)), 52)
    let variant = option_value(Get(variants, Value(BridgeKey(active: false, group: 3, code: 7))), 0)
    if variant != 52 { return 2 }
    Set(variants, Empty, 63)
    let empty = option_value(Get(variants, Empty), 0)
    if empty != 63 { return 3 }
    return 0
}
fn buffer_bridge(d: Domain) -> Result(U64, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let one = try __s0_buffer_append(U64, d, empty, 7)
    let two = try __s0_buffer_append(U64, d, one, 9)
    let view = __s0_buffer_slice(U64, two)
    return Ok(__s0_buffer_get(U64, two, 0) + view[1] + __s0_buffer_len(U64, two))
}
fn clear_domain_failure() -> U64 {
    unsafe c { test_clear_domain_alloc_failure() }
    return 0
}
fn buffer_oom_retry(d: Domain) -> Result(U64, __s0_Error) {
    let b0 = try __s0_buffer_new(U64, d)
    let b1 = try __s0_buffer_append(U64, d, b0, 0)
    let b2 = try __s0_buffer_append(U64, d, b1, 1)
    let b3 = try __s0_buffer_append(U64, d, b2, 2)
    let b4 = try __s0_buffer_append(U64, d, b3, 3)
    let b5 = try __s0_buffer_append(U64, d, b4, 4)
    let b6 = try __s0_buffer_append(U64, d, b5, 5)
    let b7 = try __s0_buffer_append(U64, d, b6, 6)
    let buffer = try __s0_buffer_append(U64, d, b7, 7)
    let attempt: U64 = match __s0_buffer_append(U64, d, buffer, 8) {
        Ok(grown) => __s0_buffer_len(U64, grown)
        Err(error) => clear_domain_failure()
    }
    if attempt != 0 { return Ok(attempt) }
    let old_view = __s0_buffer_slice(U64, buffer)
    let before = __s0_buffer_len(U64, buffer) + __s0_buffer_get(U64, buffer, 0) + old_view[7]
    if before != 15 { return Ok(0) }
    let retried = try __s0_buffer_append(U64, d, buffer, 8)
    let retried_view = __s0_buffer_slice(U64, retried)
    return Ok(before + __s0_buffer_len(U64, retried) + __s0_buffer_get(U64, retried, 0) + retried_view[8])
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"types.al", "scalar.al", "control.al", "match_try.al", "cleanup.al", "bridge.al"})
	second := runLowerCompiler(t, exe, files, []string{"bridge.al", "cleanup.al", "match_try.al", "control.al", "scalar.al", "types.al"})
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
	for _, name := range []string{"make_pair", "make_some", "scalar", "floating", "calculate", "short", "sum", "checked", "propagate", "choose", "close", "attempt", "before_using", "nested_cleanup", "cleanup_try", "domain_bridge", "option_value", "map_bridge", "map_probe_bridge", "map_structural_bridge", "buffer_bridge", "clear_domain_failure", "buffer_oom_retry"} {
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
	domainBridge := functionID("domain_bridge")
	mapBridge := functionID("map_bridge")
	mapProbeBridge := functionID("map_probe_bridge")
	mapStructuralBridge := functionID("map_structural_bridge")
	bufferOOMRetry := functionID("buffer_oom_retry")
	maybeType := module.Functions[choose].Params[0].Type
	resultType := module.Functions[propagate].Result
	bufferResultType := module.Functions[bufferOOMRetry].Result
	none, _ := module.VariantIndex(maybeType, "None")
	some, _ := module.VariantIndex(maybeType, "Some")
	ok, _ := module.VariantIndex(resultType, "ok")
	errVariant, _ := module.VariantIndex(resultType, "err")
	driver := fmt.Sprintf(`
static int64_t alder_test_cleanup;
uint64_t foreign(uint64_t value) { return value; }
void counter(int64_t value) { alder_test_cleanup = alder_test_cleanup * 10 + value; }
void test_clear_domain_alloc_failure(void) { alder_runtime_test_clear_domain_alloc_failure(); }
int main(void) {
  uint64_t values[3] = {1, 2, 3};
  AlderSlice slice = {(void *)values, 3};
  AlderTy%d none = {0};
  AlderTy%d some = {0};
  AlderTy%d success;
  AlderTy%d failure;
  AlderTy%d retried;
  AlderDomain root = {0};
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
  alder_test_cleanup = 0;
  if (alder_fn_attempt_%d(true) != 7 || alder_test_cleanup != 5) return 7;
  alder_test_cleanup = 0;
  if (alder_fn_before_using_%d(true) != 1 || alder_test_cleanup != 0) return 8;
  if (alder_fn_before_using_%d(false) != 0 || alder_test_cleanup != 2) return 9;
  alder_test_cleanup = 0;
  if (alder_fn_nested_cleanup_%d() != 0 || alder_test_cleanup != 34) return 10;
  alder_test_cleanup = 0;
  (void)alder_fn_cleanup_try_%d(false);
  if (alder_test_cleanup != 6) return 11;
  alder_test_cleanup = 0;
  (void)alder_fn_cleanup_try_%d(true);
  if (alder_test_cleanup != 6) return 12;
  alder_test_cleanup = 0;
  if (!alder_domain_init(&root, NULL)) return 13;
  if (alder_fn_domain_bridge_%d(&root) != 2) return 14;
  if (alder_fn_map_bridge_%d(&root) != 0) return 15;
  if (alder_fn_map_probe_bridge_%d(&root) != 0) return 16;
  if (alder_fn_map_structural_bridge_%d(&root) != 0) return 17;
  alder_runtime_test_fail_domain_alloc_after(1);
  retried = alder_fn_buffer_oom_retry_%d(&root);
  if (retried.alder_tag != %d || retried.alder_u.alder_p%d != 32) return 18;
  alder_domain_destroy(&root);
  return 0;
}
`, maybeType, maybeType, resultType, resultType, bufferResultType,
		none, some, some, calculate, short, short, sum, choose, choose, propagate, propagate, ok, errVariant,
		attempt, attempt, beforeUsing, beforeUsing, nestedCleanup, cleanupTry, cleanupTry,
		domainBridge, mapBridge, mapProbeBridge, mapStructuralBridge, bufferOOMRetry, ok, ok)
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
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-DALDER_RUNTIME_TESTING", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", exe}
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
	for _, mode := range []string{"!alder-core-lower-bad", "!alder-core-lower-bad-k", "!alder-core-lower-bad-m", "!alder-core-lower-bad-w", "!alder-core-lower-bad-x", "!alder-core-lower-bad-g", "!alder-core-lower-bad-v", "!alder-core-lower-bad-h", "!alder-core-lower-bad-q", "!alder-core-lower-bad-l", "!alder-core-lower-bad-e", "!alder-core-lower-bad-ea", "!alder-core-lower-bad-y", "!alder-core-lower-bad-c", "!alder-core-lower-bad-u", "!alder-core-lower-bad-n", "!alder-core-lower-bad-ca", "!alder-core-lower-bad-eliteral", "!alder-core-lower-bad-j", "!alder-core-lower-bad-gactive", "!alder-core-lower-bad-wduplicate"} {
		t.Run(strings.TrimPrefix(mode, "!alder-core-lower-bad"), func(t *testing.T) {
			dir := t.TempDir()
			source := "fn bad() -> Unit {}\n"
			if mode == "!alder-core-lower-bad-gactive" {
				source = "fn close(value: I64) -> Unit {}\nfn bad() -> Unit { using value = 1 with close }\n"
			}
			if mode == "!alder-core-lower-bad-wduplicate" {
				source = "fn bad(value: Option(U64)) -> U64 {\n    return match value {\n        None => 0\n        Some(item) => item\n    }\n}\n"
			}
			for name, text := range map[string]string{mode: "", "bad.al": source} {
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
