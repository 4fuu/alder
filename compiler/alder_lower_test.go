package compiler

import (
	"bytes"
	"fmt"
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
	runSyntheticValueNameCollisionConformance(t, exe)
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
	runLowerCgenBehavior(t, module, exe, files, []string{"types.al", "scalar.al", "control.al", "match_try.al", "cleanup.al", "bridge.al"})
	runMalformedLowerCompiler(t, exe)
	runMatchNameConformance(t, exe)
	runShortCircuitLowerConformance(t, exe)
}

func checkMatchValueNames(t *testing.T, module *mir.Module, functionName string, wantJoins, wantPayloads int) {
	t.Helper()
	id, ok := module.Function(functionName)
	if !ok {
		t.Fatalf("lowered MIR has no function %q", functionName)
	}
	joins, payloads := 0, 0
	for _, value := range module.Functions[id].Values {
		switch {
		case strings.HasPrefix(value.Name, "__s0_match_join"):
			joins++
		case strings.HasPrefix(value.Name, "__s0_match_payload"):
			payloads++
		case value.Name == "match" || strings.HasPrefix(value.Name, "match_payload") && value.Def.Kind != mir.ValueDefFuncParam:
			t.Fatalf("%s retained colliding match value name %%%s", functionName, value.Name)
		}
	}
	if joins != wantJoins || payloads != wantPayloads {
		t.Fatalf("%s synthetic match values: joins=%d payloads=%d, want %d and %d", functionName, joins, payloads, wantJoins, wantPayloads)
	}
}

func checkExactMatchValueNames(t *testing.T, module *mir.Module, functionName string, want []string) {
	t.Helper()
	id, ok := module.Function(functionName)
	if !ok {
		t.Fatalf("lowered MIR has no function %q", functionName)
	}
	var got []string
	for _, value := range module.Functions[id].Values {
		if strings.HasPrefix(value.Name, "__s0_match_join") || strings.HasPrefix(value.Name, "__s0_match_payload") {
			got = append(got, value.Name)
		}
	}
	if len(got) != len(want) {
		t.Fatalf("%s synthetic match names = %v, want %v", functionName, got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%s synthetic match names = %v, want %v", functionName, got, want)
		}
	}
}

func runMatchNameConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"types.al": `enum Maybe {
    None
    Some(value: U64)
}
fn wrap(value: U64) -> Maybe { return Some(value) }
`,
		"match_names.al": `fn repeated_matches(match_value: Maybe, match_payload0: Maybe, match_payload4: U64) -> U64 {
    let first = match match_value {
        None => match_payload4
        Some(match_payload1) => match_payload1
    }
    return match match_payload0 {
        None => first
        Some(match_payload2) => match_payload2
    }
}
fn repeated_matches_again(match_value: Maybe, match_payload0: Maybe) -> U64 {
    let first: U64 = match match_payload0 {
        None => 0
        Some(match_payload1) => match_payload1
    }
    return match match_value {
        None => first
        Some(match_payload2) => match_payload2
    }
}
fn nested_match(match_value: Maybe, match_payload0: Maybe, match_payload4: U64) -> U64 {
    return match wrap(match match_value {
        None => match_payload4
        Some(match_payload1) => match_payload1
    }) {
        None => 0
        Some(match_payload2) => match_payload2
    }
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"types.al", "match_names.al"})
	second := runLowerCompiler(t, exe, files, []string{"match_names.al", "types.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("match lowering changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse match-name MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify match-name MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	checkMatchValueNames(t, module, "repeated_matches", 2, 2)
	checkMatchValueNames(t, module, "repeated_matches_again", 2, 2)
	checkMatchValueNames(t, module, "nested_match", 2, 2)
	checkExactMatchValueNames(t, module, "nested_match", []string{"__s0_match_payload10", "__s0_match_join3", "__s0_match_payload12", "__s0_match_join6"})
	runMatchNameCgenBehavior(t, module, exe, files)
}

func runMatchNameCgenBehavior(t *testing.T, module *mir.Module, coreExe string, files map[string]string) {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	generated := runResourceCgenCompiler(t, coreExe, files, []string{"types.al", "match_names.al"})
	repeated, _ := module.Function("repeated_matches")
	again, _ := module.Function("repeated_matches_again")
	nested, _ := module.Function("nested_match")
	maybeType := module.Functions[repeated].Params[0].Type
	none, _ := module.VariantIndex(maybeType, "None")
	some, _ := module.VariantIndex(maybeType, "Some")
	driver := fmt.Sprintf(`
int main(void) {
  AlderTy%d none = {0};
  AlderTy%d some = {0};
  none.alder_tag = %d;
  some.alder_tag = %d;
  some.alder_u.alder_p%d = 9;
  if (alder_fn_repeated_matches_%d(none, none, 7) != 7) return 1;
  if (alder_fn_repeated_matches_%d(some, some, 7) != 9) return 2;
  if (alder_fn_repeated_matches_%d(none, some, 7) != 9) return 3;
  if (alder_fn_repeated_matches_again_%d(none, some) != 9) return 4;
  if (alder_fn_nested_match_%d(none, some, 7) != 7) return 5;
  if (alder_fn_nested_match_%d(some, none, 7) != 9) return 6;
  return 0;
}
`, maybeType, maybeType, none, some, some, repeated, repeated, repeated, again, nested, nested)
	dir := t.TempDir()
	file := filepath.Join(dir, "match-name-behavior.c")
	if err := os.WriteFile(file, append(generated, []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(dir, "match-name-behavior.exe")
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", output}
	if compiled, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile match-name C: %v\n%s", err, compiled)
	}
	if ran, err := conformanceCommand(output).CombinedOutput(); err != nil {
		t.Fatalf("run match-name C: %v\n%s", err, ran)
	}
}

func runShortCircuitLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"short.al": `import c observe: fn(U64, Bool) -> Bool
fn short_collision(short_5: Bool, right: Bool) -> Bool { return short_5 && right }
fn short_collision_again(short_5: Bool, right: Bool) -> Bool { return short_5 || right }
fn short_single(left: Bool, right: Bool) -> Bool { return left && right }
fn short_right_nested(left: Bool, middle: Bool, right: Bool) -> Bool { return left && (middle && right) }
fn short_repeated_and(left: Bool, middle: Bool, right: Bool) -> Bool { return left && middle && right }
fn short_explicit_and(left: Bool, middle: Bool, right: Bool) -> Bool { return (left && middle) && right }
fn short_repeated_or(left: Bool, middle: Bool, right: Bool) -> Bool { return left || middle || right }
fn short_mixed(left: Bool, middle: Bool, right: Bool) -> Bool { return left && middle || right }
fn short_order_and() -> Bool {
    return unsafe c { observe(1, true) } && unsafe c { observe(2, false) } && unsafe c { observe(3, true) }
}
fn short_order_or() -> Bool {
    return unsafe c { observe(1, false) } || unsafe c { observe(2, true) } || unsafe c { observe(3, false) }
}
fn short_order_mixed() -> Bool {
    return unsafe c { observe(1, true) } && unsafe c { observe(2, false) } || unsafe c { observe(3, true) }
}
`}
	first := runLowerCompiler(t, exe, files, []string{"short.al"})
	if second := runLowerCompiler(t, exe, files, []string{"short.al"}); !bytes.Equal(first, second) {
		t.Fatal("short-circuit MIR changed across fresh processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse short-circuit MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify short-circuit MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	functionID := func(name string) mir.FunctionId {
		id, ok := module.Function(name)
		if !ok {
			t.Fatalf("short-circuit MIR has no function %q", name)
		}
		return id
	}
	collision := functionID("short_collision")
	collisionAgain := functionID("short_collision_again")
	single := functionID("short_single")
	rightNested := functionID("short_right_nested")
	repeatedAnd := functionID("short_repeated_and")
	explicitAnd := functionID("short_explicit_and")
	repeatedOr := functionID("short_repeated_or")
	mixed := functionID("short_mixed")
	orderAnd := functionID("short_order_and")
	orderOr := functionID("short_order_or")
	orderMixed := functionID("short_order_mixed")
	if got := module.Functions[collision].Params[0].Name; got != "short_5" {
		t.Fatalf("source parameter renamed: got %q", got)
	}
	blockParamNames := func(id mir.FunctionId) []string {
		var names []string
		for _, block := range module.Functions[id].Blocks {
			for _, param := range block.Params {
				names = append(names, param.Name)
			}
		}
		return names
	}
	for _, id := range []mir.FunctionId{collision, collisionAgain, single} {
		if got := blockParamNames(id); len(got) != 1 || got[0] != "__s0_short_5" {
			t.Fatalf("single short-circuit join names = %v, want [__s0_short_5]", got)
		}
	}
	if got := blockParamNames(repeatedAnd); len(got) != 2 || got[0] != "__s0_short_5" || got[1] != "__s0_short_8" {
		t.Fatalf("repeated short-circuit join names = %v, want [__s0_short_5 __s0_short_8]", got)
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"short.al"})
	if second := runResourceCgenCompiler(t, exe, files, []string{"short.al"}); !bytes.Equal(generated, second) {
		t.Fatal("short-circuit C changed across fresh processes")
	}
	driver := fmt.Sprintf(`
static uint64_t alder_test_observed;
bool observe(uint64_t ordinal, bool value) { alder_test_observed = alder_test_observed * 10 + ordinal; return value; }
int main(void) {
  if (!alder_fn_short_collision_%d(true, true) || alder_fn_short_collision_%d(false, true)) return 10;
  if (!alder_fn_short_collision_again_%d(false, true) || alder_fn_short_collision_again_%d(false, false)) return 11;
  if (!alder_fn_short_single_%d(true, true) || alder_fn_short_single_%d(true, false)) return 1;
  if (!alder_fn_short_right_nested_%d(true, true, true) || alder_fn_short_right_nested_%d(true, false, true)) return 2;
  if (!alder_fn_short_repeated_and_%d(true, true, true) || alder_fn_short_repeated_and_%d(true, false, true)) return 3;
  if (!alder_fn_short_explicit_and_%d(true, true, true) || alder_fn_short_explicit_and_%d(true, false, true)) return 4;
  if (!alder_fn_short_repeated_or_%d(false, false, true) || alder_fn_short_repeated_or_%d(false, false, false)) return 5;
  if (!alder_fn_short_mixed_%d(true, false, true) || alder_fn_short_mixed_%d(true, false, false)) return 6;
  alder_test_observed = 0;
  if (alder_fn_short_order_and_%d() || alder_test_observed != 12) return 7;
  alder_test_observed = 0;
  if (!alder_fn_short_order_or_%d() || alder_test_observed != 12) return 8;
  alder_test_observed = 0;
  if (!alder_fn_short_order_mixed_%d() || alder_test_observed != 123) return 9;
  return 0;
}
`, collision, collision, collisionAgain, collisionAgain, single, single, rightNested, rightNested, repeatedAnd, repeatedAnd, explicitAnd, explicitAnd,
		repeatedOr, repeatedOr, mixed, mixed, orderAnd, orderOr, orderMixed)
	dir := t.TempDir()
	file := filepath.Join(dir, "short-circuit.c")
	if err := os.WriteFile(file, append(generated, []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	program := filepath.Join(dir, "short-circuit.exe")
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile short-circuit C: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run short-circuit C: %v\n%s", err, output)
	}
}

func runSyntheticValueNameCollisionConformance(t *testing.T, exe string) {
	t.Helper()
	fixtures := []struct {
		name   string
		source string
	}{
		{name: "parameter", source: "fn collision(v2: U64) -> U64 { return 1 }\n"},
		{name: "block-parameter-progress", source: "fn collision(v5: U64, flag: Bool) -> Bool { return !flag }\n"},
		{name: "function-local", source: "fn first(v2: U64) -> U64 { return 1 }\nfn second(v2: U64) -> U64 { return 1 }\n"},
	}
	for _, fixture := range fixtures {
		t.Run("synthetic-value-name-"+fixture.name, func(t *testing.T) {
			files := map[string]string{"collision.al": fixture.source}
			first := runLowerCompiler(t, exe, files, []string{"collision.al"})
			second := runLowerCompiler(t, exe, files, []string{"collision.al"})
			if len(first) == 0 || !bytes.Equal(first, second) {
				t.Fatal("collision lowering was empty or changed across fresh processes")
			}
			module, err := mir.Parse(string(first))
			if err != nil {
				t.Fatalf("parse collision MIR: %v\n%s", err, first)
			}
			if diagnostics := verify.Module(module); len(diagnostics) != 0 {
				t.Fatalf("verify collision MIR: %s\n%s", verify.Errors(diagnostics), first)
			}
		})
	}
}

func runLowerCgenBehavior(t *testing.T, module *mir.Module, coreExe string, files map[string]string, order []string) {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	generated := runResourceCgenCompiler(t, coreExe, files, order)
	if second := runResourceCgenCompiler(t, coreExe, files, order); !bytes.Equal(generated, second) {
		t.Fatal("Alder-written resource C changed across processes")
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
	resultCType := generatedFunctionResultType(t, generated, "propagate", propagate)
	bufferResultCType := generatedFunctionResultType(t, generated, "buffer_oom_retry", bufferOOMRetry)
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
  %s success;
  %s failure;
  %s retried;
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
`, maybeType, maybeType, resultCType, resultCType, bufferResultCType,
		none, some, some, calculate, short, short, sum, choose, choose, propagate, propagate, ok, errVariant,
		attempt, attempt, beforeUsing, beforeUsing, nestedCleanup, cleanupTry, cleanupTry,
		domainBridge, mapBridge, mapProbeBridge, mapStructuralBridge, bufferOOMRetry, ok, ok)
	dir := t.TempDir()
	file := filepath.Join(dir, "lower-behavior.c")
	if err := os.WriteFile(file, append(generated, []byte(driver)...), 0o644); err != nil {
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
	if output, err := conformanceCommand(exe).CombinedOutput(); err != nil {
		t.Fatalf("run lowered C: %v\n%s", err, output)
	}
	for _, block := range module.Functions[sum].Blocks {
		if len(block.Params) >= 2 {
			return
		}
	}
	t.Fatal("slice-for lowering has no two-parameter edge for parallel-copy evidence")
}

func generatedFunctionResultType(t *testing.T, generated []byte, name string, id mir.FunctionId) string {
	t.Helper()
	needle := fmt.Sprintf(" alder_fn_%s_%d(", name, id)
	for _, line := range strings.Split(string(generated), "\n") {
		before, _, found := strings.Cut(line, needle)
		if found {
			fields := strings.Fields(before)
			if len(fields) != 0 {
				return fields[len(fields)-1]
			}
		}
	}
	t.Fatalf("generated C has no declaration for %s", name)
	return ""
}

func runResourceCgenCompiler(t *testing.T, exe string, files map[string]string, order []string) []byte {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "!alder-core-cgen-resources"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	args := append([]string{"!alder-core-cgen-resources"}, order...)
	cmd := conformanceCommand(exe, args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("run Alder resource C generator: %v\nstdout:\n%s\nstderr:\n%s", err, stdout.Bytes(), stderr.Bytes())
	}
	if stderr.Len() != 0 || stdout.Len() == 0 {
		t.Fatalf("Alder resource C generator produced invalid streams: stdout=%d stderr=%s", stdout.Len(), stderr.Bytes())
	}
	return stdout.Bytes()
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
			cmd := conformanceCommand(exe, mode, "bad.al")
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
	cmd := conformanceCommand(exe, args...)
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
