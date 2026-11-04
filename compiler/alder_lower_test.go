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
	runPreferredResultNameCollisionConformance(t, exe)
	runMethodLowerConformance(t, exe)
	t.Run("arrays", func(t *testing.T) { runArrayLowerConformance(t, exe) })
	t.Run("m71-collections", func(t *testing.T) { runM71LowerConformance(t, exe) })
	t.Run("m73-storage-views", func(t *testing.T) { runAlderM73LowerBehavior(t, exe) })
	t.Run("m75-trait-dispatch", func(t *testing.T) { runAlderM75LowerBehavior(t, exe) })
	t.Run("m75-ordered-collections", func(t *testing.T) { runAlderM75OrderedLowerBehavior(t, exe) })
	t.Run("m75-fn-values", func(t *testing.T) { runAlderFnValueLowerBehavior(t, exe) })
	t.Run("m75-closures", func(t *testing.T) { runAlderClosureLowerBehavior(t, exe) })
	t.Run("m75-default-methods", func(t *testing.T) { runAlderDefaultMethodLowerBehavior(t, exe) })
	t.Run("m75-mut-cursors", func(t *testing.T) { runAlderM75MutCursorLowerBehavior(t, exe) })
	t.Run("m75-generic-methods", func(t *testing.T) { runAlderM75GenericMethodLowerBehavior(t, exe) })
	t.Run("m75-vec-loop-scalars", func(t *testing.T) { runAlderVecLoopLowerBehavior(t, exe) })
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
    __s0_buffer_set(U64, two, 0, 11)
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
	checkIndexedPlaceLoadTypes(t, exe)
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
	runNotNameConformance(t, exe)
	runLongChainLowerConformance(t, exe)
	runContinuationLowerConformance(t, exe)
	runErrorConstructorLowerConformance(t, exe)
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
fn not_single(value: Bool) -> Bool { return !value }
fn not_and(left: Bool, right: Bool) -> Bool { return !(left && right) }
fn not_or(left: Bool, right: Bool) -> Bool { return !(left || right) }
fn not_deep(left: Bool, middle: Bool, right: Bool) -> Bool { return !(left && (middle || right)) }
fn not_repeated(left: Bool, middle: Bool, right: Bool) -> Bool { return !(left && middle && right) }
fn not_match(value: Bool) -> Bool {
    let selected: Option(Bool) = Some(value)
    return !(match selected {
        None => false
        Some(item) => item
    })
}
fn short_order_and() -> Bool {
    return unsafe c { observe(1, true) } && unsafe c { observe(2, false) } && unsafe c { observe(3, true) }
}
fn short_order_or() -> Bool {
    return unsafe c { observe(1, false) } || unsafe c { observe(2, true) } || unsafe c { observe(3, false) }
}
fn short_order_mixed() -> Bool {
    return unsafe c { observe(1, true) } && unsafe c { observe(2, false) } || unsafe c { observe(3, true) }
}
fn not_order() -> Bool {
    return !(unsafe c { observe(1, true) } && unsafe c { observe(2, false) } && unsafe c { observe(3, true) })
}
`}
	first := runLowerCompiler(t, exe, files, []string{"short.al"})
	second := runLowerCompiler(t, exe, files, []string{"short.al"})
	if len(first) == 0 || len(second) == 0 {
		t.Fatal("logical lowering produced empty MIR")
	}
	if !bytes.Equal(first, second) {
		t.Fatal("short-circuit MIR changed across fresh processes")
	}
	var module *mir.Module
	for run, output := range [][]byte{first, second} {
		parsed, err := mir.Parse(string(output))
		if err != nil {
			t.Fatalf("parse logical MIR run %d: %v\n%s", run, err, output)
		}
		if diagnostics := verify.Module(parsed); len(diagnostics) != 0 {
			t.Fatalf("verify logical MIR run %d: %s\n%s", run, verify.Errors(diagnostics), output)
		}
		if run == 0 {
			module = parsed
		}
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
	notSingle := functionID("not_single")
	notAnd := functionID("not_and")
	notOr := functionID("not_or")
	notDeep := functionID("not_deep")
	notRepeated := functionID("not_repeated")
	notMatch := functionID("not_match")
	orderAnd := functionID("short_order_and")
	orderOr := functionID("short_order_or")
	orderMixed := functionID("short_order_mixed")
	notOrder := functionID("not_order")
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
  if (alder_fn_not_single_%d(true) || !alder_fn_not_single_%d(false)) return 12;
  if (alder_fn_not_and_%d(true, true) || !alder_fn_not_and_%d(true, false)) return 13;
  if (!alder_fn_not_or_%d(false, false) || alder_fn_not_or_%d(false, true)) return 14;
  if (alder_fn_not_deep_%d(true, false, true) || !alder_fn_not_deep_%d(true, false, false)) return 15;
  if (alder_fn_not_repeated_%d(true, true, true) || !alder_fn_not_repeated_%d(true, false, true)) return 16;
  if (alder_fn_not_match_%d(true) || !alder_fn_not_match_%d(false)) return 18;
  alder_test_observed = 0;
  if (alder_fn_short_order_and_%d() || alder_test_observed != 12) return 7;
  alder_test_observed = 0;
  if (!alder_fn_short_order_or_%d() || alder_test_observed != 12) return 8;
  alder_test_observed = 0;
  if (!alder_fn_short_order_mixed_%d() || alder_test_observed != 123) return 9;
  alder_test_observed = 0;
  if (!alder_fn_not_order_%d() || alder_test_observed != 12) return 17;
  return 0;
}
`, collision, collision, collisionAgain, collisionAgain, single, single, rightNested, rightNested, repeatedAnd, repeatedAnd, explicitAnd, explicitAnd,
		repeatedOr, repeatedOr, mixed, mixed, notSingle, notSingle, notAnd, notAnd, notOr, notOr, notDeep, notDeep, notRepeated, notRepeated,
		notMatch, notMatch, orderAnd, orderOr, orderMixed, notOrder)
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

func runMethodLowerConformance(t *testing.T, exe string) {
	t.Helper()
	source := `type Counter { value: U64 }
type Other { value: U64 }
impl Counter {
fn new(value: U64) -> Counter { return Counter(value: value) }
fn read(self) -> U64 { return self.value }
fn write(mut self, value: U64) -> Unit { self.value = value
 return }
fn echo(T: type, self, value: T) -> T { return value }
}
impl Other {
fn read(self) -> U64 { return self.value }
}
fn main(value: Counter) -> U64 {
    var local: Counter = value
    local.write(7)
    return local.echo(local.read())
}
fn make() -> Counter { return Counter.new(3) }
fn read_parameter(value: Counter) -> U64 { return value.read() }
fn read_temporary() -> U64 { return Counter.new(4).read() }
`
	text := runLowerCompiler(t, exe, map[string]string{"methods.al": source}, []string{"methods.al"})
	module, err := mir.Parse(string(text))
	if err != nil {
		t.Fatalf("parse method MIR: %v\n%s", err, text)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify method MIR: %s\n%s", verify.Errors(diagnostics), text)
	}
	borrowed := false
	storedThroughReceiver := false
	for _, function := range module.Functions {
		for _, block := range function.Blocks {
			for _, instruction := range block.Instrs {
				if instruction.Op == mir.OpBorrowMut {
					borrowed = true
				}
				if instruction.Op == mir.OpStore && instruction.Place.Kind == mir.PlaceField && instruction.Place.Base != nil && instruction.Place.Base.Kind == mir.PlaceDeref {
					storedThroughReceiver = true
				}
			}
		}
	}
	if !borrowed || !storedThroughReceiver {
		t.Fatalf("method MIR does not preserve mutable receiver borrowing: borrow=%v store-through-receiver=%v\n%s", borrowed, storedThroughReceiver, text)
	}
}

func runArrayLowerConformance(t *testing.T, exe string) {
	t.Helper()
	source := `fn copy(value: Array(U64, 3)) -> Array(U64, 3) { return value }
fn independent() -> U64 {
    var original: Array(U64, 3) = [1, 2, 3]
    var copied: Array(U64, 3) = copy(original)
    copied[1] = 9
    return original[1] * 10 + copied[1]
}
fn empty() -> Array(U64, 0) { return [] }
fn out_of_bounds() -> U64 {
    let values: Array(U64, 3) = [1, 2, 3]
    return values[3]
}
`
	files := map[string]string{"arrays.al": source}
	parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{"arrays.al"}, false), files)
	first := runLowerCompiler(t, exe, files, []string{"arrays.al"})
	second := runLowerCompiler(t, exe, files, []string{"arrays.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("array lowering changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse array MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify array MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	indexed := 0
	for _, function := range module.Functions {
		for _, block := range function.Blocks {
			for _, instruction := range block.Instrs {
				if instruction.Op == mir.OpArrayIndexChecked {
					indexed++
				}
			}
		}
	}
	if indexed != 4 {
		t.Fatalf("array MIR has %d checked indexes, want 4\n%s", indexed, first)
	}
	runArrayCgenBehavior(t, module, exe, files)
}

func runArrayCgenBehavior(t *testing.T, module *mir.Module, coreExe string, files map[string]string) {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	generated := runResourceCgenCompiler(t, coreExe, files, []string{"arrays.al"})
	independent, ok := module.Function("independent")
	if !ok {
		t.Fatal("array MIR has no independent function")
	}
	outOfBounds, ok := module.Function("out_of_bounds")
	if !ok {
		t.Fatal("array MIR has no out_of_bounds function")
	}
	dir := t.TempDir()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	compile := func(name, driver string) string {
		file := filepath.Join(dir, name+".c")
		if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
			t.Fatal(err)
		}
		program := filepath.Join(dir, name+".exe")
		args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
		if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
			t.Fatalf("compile array C: %v\n%s", err, output)
		}
		return program
	}
	success := compile("array-success", fmt.Sprintf("\nint main(void) { return alder_fn_independent_%d() == 29 ? 0 : 1; }\n", independent))
	if output, err := conformanceCommand(success).CombinedOutput(); err != nil {
		t.Fatalf("run array value-independence C: %v\n%s", err, output)
	}
	bounds := compile("array-bounds", fmt.Sprintf("\nint main(void) { (void)alder_fn_out_of_bounds_%d(); return 0; }\n", outOfBounds))
	if output, err := conformanceCommand(bounds).CombinedOutput(); err == nil {
		t.Fatalf("out-of-bounds array access succeeded\n%s", output)
	}
}

func runM71LowerConformance(t *testing.T, exe string) {
	t.Helper()
	source := `fn first(T: type, values: [T]) -> T { return values[0] }
fn clone_vec(T: type, values: Vec(T)) -> Vec(T) { return values }
fn returned_array_view() -> [U64] {
    let values: Array(U64, 3) = [3, 5, 7]
    return values.slice(0, 3)
}
fn returned_vec_view() -> [U64] {
    var values: Vec(U64) = Vec.from_array(U64, [11, 13])
    values.push(17)
    return values.slice(0, 3)
}
fn nested_returned_view() -> [U64] { return returned_vec_view() }
fn returned_parameter_view(values: [U64]) -> [U64] { return values }
fn returned_nested_vec_view() -> [Vec(U64)] {
    var first: Vec(U64) = Vec.from_array(U64, [47, 53])
    var second: Vec(U64) = Vec.from_array(U64, [59])
    let values: Array(Vec(U64), 2) = [first, second]
    return values.slice(0, 2)
}
fn returned_nested_vec_array() -> Array(Vec(U64), 2) {
    var first: Vec(U64) = Vec.from_array(U64, [71, 73])
    var second: Vec(U64) = Vec.from_array(U64, [79])
    return [first, second]
}
fn scalar_from_local_collection() -> U64 {
    var values: Vec(U64) = Vec.from_array(U64, [31])
    values.push(37)
    return values[1]
}
fn fail_vec() -> Result(U64, Vec(U64)) {
    var error: Vec(U64) = Vec.from_array(U64, [7, 11])
    return Err(error)
}
fn propagate_vec_error() -> Result(U64, Vec(U64)) {
    let value = try fail_vec()
    return Ok(value)
}
fn main() -> I32 {
    let seed: Array(U64, 2) = [1, 2]
    var values: Vec(U64) = Vec.from_array(U64, seed)
    values.push(3)
    values.push(5)
    values.push(8)
    if values.len() != 5 { return 1 }

    var copied: Vec(U64) = clone_vec(values)
    copied[0] = 13
    if values[0] != 1 || copied[0] != 13 { return 2 }

    var view_sum: U64 = 0
    {
        let middle: [U64] = values.slice(1, 4)
        view_sum = middle[0] + middle[2]
    }
    {
        var head: MutSlice(U64) = values.slice_mut(0, 2)
        head[0] = 21
        {
            var one: MutSlice(U64) = head.subview(1, 2)
            one[0] = 34
        }
    }
    if view_sum != 7 || first(values) != 21 || values[1] != 34 { return 3 }

    let present = values.get(2)
    let found = match present {
        Some(value) => value
        None => 0
    }
    let absent = values.get(99)
    let fallback = match absent {
        Some(value) => value
        None => 55
    }
    if found != 3 || fallback != 55 { return 4 }

    var array: Array(U64, 4) = [2, 3, 5, 7]
    var before: U64 = 0
    {
        let middle: [U64] = array.slice(1, 3)
        before = first(middle)
    }
    {
        var tail: MutSlice(U64) = array.slice_mut(2, 4)
        tail[0] = 11
        {
            var last: MutSlice(U64) = tail.subview(1, 2)
            last[0] = 13
        }
    }
    if before != 3 || array[2] != 11 || array[3] != 13 || first(array) != 2 { return 5 }

    var empty: Vec(U64) = Vec.new(U64)
    empty.push(55)
    if empty.len() != 1 || empty[0] != 55 { return 6 }

    var nested_seed: Vec(U64) = Vec.from_array(U64, [89])
    var nested: Vec(Vec(U64)) = Vec.from_array(Vec(U64), [nested_seed])
    var nested_copy: Vec(Vec(U64)) = clone_vec(nested)
    var replacement: Vec(U64) = Vec.from_array(U64, [144])
    nested_copy[0] = replacement
    var nested_original: Vec(U64) = nested[0]
    var nested_changed: Vec(U64) = nested_copy[0]
    if nested_original[0] != 89 || nested_changed[0] != 144 { return 7 }
    let array_view = returned_array_view()
    let vec_view = nested_returned_view()
    if array_view[0] != 3 || array_view[2] != 7 { return 8 }
    if vec_view[0] != 11 || vec_view[2] != 17 { return 9 }
    let parameter_view = returned_parameter_view(vec_view)
    if parameter_view[1] != 13 { return 10 }
    let nested_view = returned_nested_vec_view()
    var view_original: Vec(U64) = nested_view[0]
    var view_changed: Vec(U64) = nested_view[0]
    view_changed[0] = 61
    view_changed.push(67)
    if view_original[0] != 47 || view_original.len() != 2 { return 11 }
    if view_changed[0] != 61 || view_changed.len() != 3 { return 12 }
    let nested_array = returned_nested_vec_array()
    var array_original: Vec(U64) = nested_array[0]
    var array_changed: Vec(U64) = nested_array[0]
    array_changed[0] = 79
    array_changed.push(83)
    if array_original[0] != 71 || array_original.len() != 2 { return 13 }
    if array_changed[0] != 79 || array_changed.len() != 3 { return 14 }
    if scalar_from_local_collection() != 37 { return 15 }
    let propagated = propagate_vec_error()
    if !match propagated {
        Ok(value) => false
        Err(error) => error[0] == 7 && error[1] == 11
    } { return 16 }
    return 0
}
fn out_of_bounds() -> U64 {
    var values: Vec(U64) = Vec.new(U64)
    values.push(1)
    return values[1]
}
`
	files := map[string]string{"collections.al": source}
	first := runLowerCompiler(t, exe, files, []string{"collections.al"})
	second := runLowerCompiler(t, exe, files, []string{"collections.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("M7.1 collection lowering changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse M7.1 MIR: %v\n%s", err, first)
	}
	if module.FormatVersion != mir.CurrentFormatVersion {
		t.Fatalf("M7.1 MIR version = %d, want %d", module.FormatVersion, mir.CurrentFormatVersion)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify M7.1 MIR: %s\n%s", verify.Errors(diagnostics), first)
	}

	counts := map[mir.OpKind]int{}
	for _, function := range module.Functions {
		if len(function.Params) == 0 || module.Types[function.Params[0].Type].Kind != mir.TypeDomainHandle {
			t.Fatalf("M7.1 function %s has no hidden domain parameter", function.Name)
		}
		for _, block := range function.Blocks {
			for _, instruction := range block.Instrs {
				counts[instruction.Op]++
			}
		}
	}
	for _, op := range []mir.OpKind{
		mir.OpDomainCreate,
		mir.OpDomainDestroy,
		mir.OpVecNew,
		mir.OpVecConstructChecked,
		mir.OpVecGrowChecked,
		mir.OpVecLen,
		mir.OpVecCapacity,
		mir.OpVecStorage,
		mir.OpVecAsSlice,
		mir.OpVecAsMutSlice,
		mir.OpArrayAsSlice,
		mir.OpSliceRangeChecked,
		mir.OpCopyToDomain,
		mir.OpIntMulChecked,
	} {
		if counts[op] == 0 {
			t.Fatalf("M7.1 MIR has no %s instruction\n%s", op, first)
		}
	}
	runM71CgenBehavior(t, module, exe, files)
}

func runM71CgenBehavior(t *testing.T, module *mir.Module, coreExe string, files map[string]string) {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	generated := runResourceCgenCompiler(t, coreExe, files, []string{"collections.al"})
	if second := runResourceCgenCompiler(t, coreExe, files, []string{"collections.al"}); !bytes.Equal(generated, second) {
		t.Fatal("Alder-written M7.1 C changed across processes")
	}
	outOfBounds, ok := module.Function("out_of_bounds")
	if !ok {
		t.Fatal("M7.1 MIR has no out_of_bounds function")
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("M7.1 MIR has no main function")
	}
	dir := t.TempDir()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	compile := func(name, driver string) string {
		t.Helper()
		file := filepath.Join(dir, name+".c")
		program := filepath.Join(dir, name+".exe")
		text := append(append([]byte(nil), generated...), []byte(driver)...)
		if err := os.WriteFile(file, text, 0o644); err != nil {
			t.Fatal(err)
		}
		args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
		if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
			t.Fatalf("strict C11 compile of %s: %v\n%s", name, err, output)
		}
		return program
	}
	successDriver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; int32_t status = alder_fn_main_%d(&root); alder_domain_destroy(&root); return status; }\n", mainID)
	success := compile("m71-success", successDriver)
	if output, err := conformanceCommand(success).CombinedOutput(); err != nil {
		t.Fatalf("run M7.1 collection behavior: %v\n%s", err, output)
	}
	boundsDriver := fmt.Sprintf("\nint main(void) { AlderDomain root = {0}; if (!alder_domain_init(&root, NULL)) return 2; (void)alder_fn_out_of_bounds_%d(&root); alder_domain_destroy(&root); return 0; }\n", outOfBounds)
	bounds := compile("m71-bounds", boundsDriver)
	if output, err := conformanceCommand(bounds).CombinedOutput(); err == nil {
		t.Fatalf("out-of-bounds Vec access succeeded\n%s", output)
	}
}

func checkIndexedPlaceLoadTypes(t *testing.T, exe string) {
	t.Helper()
	src, err := os.ReadFile(filepath.Join("..", "frontend", "testdata", "e2e", "domains.al"))
	if err != nil {
		t.Fatal(err)
	}
	text := runLowerCompiler(t, exe, map[string]string{"domains.al": string(src)}, []string{"domains.al"})
	module, err := mir.Parse(string(text))
	if err != nil {
		t.Fatalf("parse domains MIR: %v\n%s", err, text)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify domains MIR: %s\n%s", verify.Errors(diagnostics), text)
	}
	checked := 0
	for _, function := range module.Functions {
		for _, block := range function.Blocks {
			for _, instruction := range block.Instrs {
				if instruction.Op != mir.OpSliceIndexChecked {
					continue
				}
				storedThroughPlace := false
				for _, candidateBlock := range function.Blocks {
					for _, candidate := range candidateBlock.Instrs {
						if candidate.Op == mir.OpStore && candidate.Place.Kind == mir.PlaceDeref && candidate.Place.Deref == instruction.Result {
							storedThroughPlace = true
						}
					}
				}
				if !storedThroughPlace {
					continue
				}
				value := function.Values[instruction.Slice]
				if value.Def.Kind != mir.ValueDefInstr {
					continue
				}
				load := function.Blocks[value.Def.Block].Instrs[value.Def.Instr]
				if load.Op != mir.OpLoad || load.Place.Kind != mir.PlaceLocal {
					continue
				}
				inferred, ok := module.PlaceType(function, &load.Place)
				if !ok {
					t.Fatalf("indexed root load has invalid place in %s", function.Name)
				}
				if stored := function.Values[load.Result].Type; stored != inferred {
					t.Fatalf("indexed root load type in %s: stored %d, inferred %d", function.Name, stored, inferred)
				}
				checked++
			}
		}
	}
	if checked == 0 {
		t.Fatal("domains MIR has no indexed checked-place root load")
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

func runPreferredResultNameCollisionConformance(t *testing.T, exe string) {
	t.Helper()
	fixtures := []struct {
		name, source, preferred, driver string
		op                              mir.OpKind
	}{
		{
			name:      "for-reference",
			preferred: "for_ref",
			op:        mir.OpSliceIndexChecked,
			source: `fn collision(for_ref: U64, values: [U64]) -> U64 {
    var total: U64 = 0
    for value in values {
        total = total + value
    }
    return total
}
`,
			driver: `
int main(void) {
  uint64_t values[3] = {1, 2, 3};
  AlderSlice slice = {(void *)values, 3};
  return alder_fn_collision_%d(0, slice) == 6 ? 0 : 1;
}
`,
		},
		{
			name:      "cleanup-scope",
			preferred: "cleanup_scope3",
			op:        mir.OpCleanupScopeBegin,
			source: `import c counter: fn(I64) -> Unit
fn close(value: I64) -> Unit { unsafe c { counter(value) } }
fn collision(cleanup_scope3: U64) -> I64 {
    using handle = 5 with close
    return 7
}
`,
			driver: `
static int64_t observed;
void counter(int64_t value) { observed = value; }
int main(void) {
  if (alder_fn_collision_%d(0) != 7) return 1;
  return observed == 5 ? 0 : 2;
}
`,
		},
		{
			name:      "cleanup-id",
			preferred: "cleanup_id3",
			op:        mir.OpCleanupPush,
			source: `import c counter: fn(I64) -> Unit
fn close(value: I64) -> Unit { unsafe c { counter(value) } }
fn collision(cleanup_id3: U64) -> I64 {
    using handle = 5 with close
    return 7
}
`,
			driver: `
static int64_t observed;
void counter(int64_t value) { observed = value; }
int main(void) {
  if (alder_fn_collision_%d(0) != 7) return 1;
  return observed == 5 ? 0 : 2;
}
`,
		},
	}
	for _, fixture := range fixtures {
		t.Run("preferred-result-name-"+fixture.name, func(t *testing.T) {
			files := map[string]string{"collision.al": fixture.source}
			first := runLowerCompiler(t, exe, files, []string{"collision.al"})
			second := runLowerCompiler(t, exe, files, []string{"collision.al"})
			if len(first) == 0 || !bytes.Equal(first, second) {
				t.Fatal("preferred-name collision lowering was empty or changed across fresh processes")
			}
			module, err := mir.Parse(string(first))
			if err != nil {
				t.Fatalf("independently parse preferred-name collision MIR: %v\n%s", err, first)
			}
			if diagnostics := verify.Module(module); len(diagnostics) != 0 {
				t.Fatalf("complete V1-V10 verification of preferred-name collision MIR: %s\n%s", verify.Errors(diagnostics), first)
			}
			functionID, ok := module.Function("collision")
			if !ok {
				t.Fatalf("preferred-name collision MIR has no collision function\n%s", first)
			}
			function := module.Functions[functionID]
			foundParameter := false
			for _, parameter := range function.Params {
				if parameter.Name == fixture.preferred {
					foundParameter = true
				}
			}
			if !foundParameter {
				t.Fatalf("collision function has no parameter %%%s", fixture.preferred)
			}
			resultName := instructionResultName(t, function, fixture.op)
			if resultName == fixture.preferred {
				t.Fatalf("%s result retained occupied preferred name %%%s", fixture.op, fixture.preferred)
			}
			if !strings.HasPrefix(resultName, "v") {
				t.Fatalf("%s result = %%%s, want deterministic fallback after %%%s collision", fixture.op, resultName, fixture.preferred)
			}
			runPreferredResultNameCgenBehavior(t, exe, files, functionID, fixture.driver)
		})
	}

	t.Run("preferred-result-name-cross-function-reuse", func(t *testing.T) {
		const source = `fn first(values: [U64]) -> U64 {
    for value in values { return value }
    return 0
}
fn second(values: [U64]) -> U64 {
    for value in values { return value }
    return 0
}
`
		files := map[string]string{"reuse.al": source}
		first := runLowerCompiler(t, exe, files, []string{"reuse.al"})
		second := runLowerCompiler(t, exe, files, []string{"reuse.al"})
		if len(first) == 0 || !bytes.Equal(first, second) {
			t.Fatal("cross-function preferred-name lowering was empty or changed across fresh processes")
		}
		module, err := mir.Parse(string(first))
		if err != nil {
			t.Fatalf("independently parse cross-function preferred-name MIR: %v\n%s", err, first)
		}
		if diagnostics := verify.Module(module); len(diagnostics) != 0 {
			t.Fatalf("complete V1-V10 verification of cross-function preferred-name MIR: %s\n%s", verify.Errors(diagnostics), first)
		}
		for _, name := range []string{"first", "second"} {
			functionID, ok := module.Function(name)
			if !ok {
				t.Fatalf("cross-function preferred-name MIR has no %s function", name)
			}
			if got := instructionResultName(t, module.Functions[functionID], mir.OpSliceIndexChecked); got != "for_ref" {
				t.Fatalf("%s slice index result = %%%s, want %%for_ref", name, got)
			}
		}
	})
}

func instructionResultName(t *testing.T, function *mir.Function, op mir.OpKind) string {
	t.Helper()
	name := ""
	for _, block := range function.Blocks {
		for _, instruction := range block.Instrs {
			if instruction.Op != op {
				continue
			}
			if name != "" {
				t.Fatalf("function %s has more than one %s result", function.Name, op)
			}
			if instruction.Result == mir.NoValue || int(instruction.Result) >= len(function.Values) {
				t.Fatalf("function %s has invalid %s result", function.Name, op)
			}
			name = function.Values[instruction.Result].Name
		}
	}
	if name == "" {
		t.Fatalf("function %s has no %s result", function.Name, op)
	}
	return name
}

func runPreferredResultNameCgenBehavior(t *testing.T, coreExe string, files map[string]string, functionID mir.FunctionId, driverFormat string) {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	generated := runResourceCgenCompiler(t, coreExe, files, []string{"collision.al"})
	dir := t.TempDir()
	cfile := filepath.Join(dir, "preferred-result-name.c")
	if err := os.WriteFile(cfile, append(generated, []byte(fmt.Sprintf(driverFormat, functionID))...), 0o644); err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(dir, "preferred-result-name.exe")
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), cfile, filepath.Join(root, "runtime", "c", "alder.c"), "-o", output}
	if compileOutput, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of preferred-name collision: %v\n%s", err, compileOutput)
	}
	if runOutput, err := exec.Command(output).CombinedOutput(); err != nil {
		t.Fatalf("run preferred-name collision C: %v\n%s", err, runOutput)
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
	if privateProfileLowerSources(files) {
		args = append([]string{"--bootstrap-private"}, args...)
	}
	cmd := conformanceCommand(exe, args...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), "TMPDIR="+t.TempDir())
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
				// The callback `with` clause is bootstrap-private since M7.5;
				// this malformed-cleanup path is exercised through the public
				// Cleanup-selection form instead.
				source = "type Res { n: U64 }\nimpl Cleanup for Res { fn cleanup(take self) -> Unit { return } }\nfn bad() -> Unit { using value = Res(n: 1) }\n"
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

// privateProfileLowerSources reports whether a lower-conformance source set
// still uses the S0 bridges and needs the private bootstrap profile.
func privateProfileLowerSources(files map[string]string) bool {
	for _, text := range files {
		if strings.Contains(text, "__s0_") || strings.Contains(text, "Domain") || strings.Contains(text, "Map(") {
			return true
		}
		// The `with cleanup_function` clause is bootstrap-private since M7.5.
		for _, line := range strings.Split(text, "\n") {
			if strings.Contains(line, "using ") && strings.Contains(line, " with ") {
				return true
			}
		}
	}
	return false
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
	if privateProfileLowerSources(files) {
		args = append([]string{"--bootstrap-private"}, args...)
	}
	cmd := conformanceCommand(exe, args...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), "TMPDIR="+t.TempDir())
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

func runNotNameConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"double_not.al": `fn double_not_a(value: Bool) -> Bool { return !!value }
fn double_not_b(value: Bool) -> Bool { return !!value }
`,
		"not_source.al": `fn not_source(not: Bool, flag: Bool) -> Bool { return !not || !flag }
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"double_not.al", "not_source.al"})
	second := runLowerCompiler(t, exe, files, []string{"double_not.al", "not_source.al"})
	if len(first) == 0 || len(second) == 0 {
		t.Fatal("unary-not lowering produced empty MIR")
	}
	if !bytes.Equal(first, second) {
		t.Fatal("unary-not MIR changed across fresh processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse unary-not MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify unary-not MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	for _, name := range []string{"double_not_a", "double_not_b", "not_source"} {
		if _, ok := module.Function(name); !ok {
			t.Fatalf("lowered MIR has no function %q", name)
		}
	}
	notSource, ok := module.Function("not_source")
	if !ok {
		t.Fatalf("lowered MIR has no function %q", "not_source")
	}
	if got := module.Functions[notSource].Params[0].Name; got != "not" {
		t.Fatalf("source parameter renamed: got %q", got)
	}
	joins := 0
	for _, function := range module.Functions {
		for _, block := range function.Blocks {
			for _, param := range block.Params {
				if param.Name == "not" {
					t.Fatalf("unary-not join retained colliding param name %q", param.Name)
				}
				if strings.HasPrefix(param.Name, "__s0_not_join") {
					joins++
				}
			}
		}
	}
	// Six unary nots (two per function) produce six isolated join params.
	if joins != 6 {
		t.Fatalf("unary-not join names = %d, want 6", joins)
	}
	truths, falsities := 0, 0
	constNames := map[string]bool{}
	for _, constant := range module.Constants {
		switch {
		case strings.HasPrefix(constant.Name, "__s0_not_true_"):
			truths++
		case strings.HasPrefix(constant.Name, "__s0_not_false_"):
			falsities++
		}
		if strings.HasPrefix(constant.Name, "__s0_not_") {
			if constNames[constant.Name] {
				t.Fatalf("duplicate unary-not constant name %q", constant.Name)
			}
			constNames[constant.Name] = true
		}
	}
	if truths != 6 || falsities != 6 {
		t.Fatalf("unary-not constants: truths=%d falsities=%d, want 6 and 6", truths, falsities)
	}
	// The not-source function must also parse and verify independently of the
	// double-not functions.
	sourceOnly := runLowerCompiler(t, exe, map[string]string{"not_source.al": files["not_source.al"]}, []string{"not_source.al"})
	sourceModule, err := mir.Parse(string(sourceOnly))
	if err != nil {
		t.Fatalf("parse not-source MIR: %v\n%s", err, sourceOnly)
	}
	if diagnostics := verify.Module(sourceModule); len(diagnostics) != 0 {
		t.Fatalf("verify not-source MIR: %s\n%s", verify.Errors(diagnostics), sourceOnly)
	}
	sourceID, ok := sourceModule.Function("not_source")
	if !ok {
		t.Fatalf("lowered MIR has no function %q", "not_source")
	}
	if got := sourceModule.Functions[sourceID].Params[0].Name; got != "not" {
		t.Fatalf("source parameter renamed: got %q", got)
	}
	for _, function := range sourceModule.Functions {
		for _, block := range function.Blocks {
			for _, param := range block.Params {
				if param.Name == "not" {
					t.Fatalf("unary-not join retained colliding param name %q", param.Name)
				}
			}
		}
	}
}

func runLongChainLowerConformance(t *testing.T, exe string) {
	t.Helper()
	// A straight-line root-block chain of 24 lets, 24 assignments, and a
	// return exercises the iterative statement-chain walk: the former
	// link.next recursion paid a call frame per link and exhausted on
	// chains this long.
	var body strings.Builder
	body.WriteString("fn long_chain(seed: U64) -> U64 {\n")
	body.WriteString("    var total = seed\n")
	for i := 0; i < 24; i++ {
		fmt.Fprintf(&body, "    let step_%d = total + %d\n", i, i+1)
		fmt.Fprintf(&body, "    total = step_%d * 2\n", i)
	}
	body.WriteString("    return total\n")
	body.WriteString("}\n")
	files := map[string]string{"longchain.al": body.String()}
	first := runLowerCompiler(t, exe, files, []string{"longchain.al"})
	second := runLowerCompiler(t, exe, files, []string{"longchain.al"})
	if len(first) == 0 || len(second) == 0 {
		t.Fatal("long statement chain lowering produced empty MIR")
	}
	if !bytes.Equal(first, second) {
		t.Fatal("long statement chain MIR changed across fresh processes")
	}
	for run, output := range [][]byte{first, second} {
		parsed, err := mir.Parse(string(output))
		if err != nil {
			t.Fatalf("parse long chain MIR run %d: %v\n%s", run, err, output)
		}
		if diagnostics := verify.Module(parsed); len(diagnostics) != 0 {
			t.Fatalf("verify long chain MIR run %d: %s\n%s", run, verify.Errors(diagnostics), output)
		}
		if _, ok := parsed.Function("long_chain"); !ok {
			t.Fatalf("long chain MIR run %d has no long_chain function\n%s", run, output)
		}
	}
}

func runContinuationLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"continuations.al": `fn checked(n: I64, d: I64) -> Result(I64, I64) {
    if d == 0 {
        return Err(1)
    }
    return Ok(n / d)
}

enum Which {
    First
    Second
}

type Indexed {
    value: U64
    mark: U64
}

fn sequential_try(d: Domain) -> Result(U64, __s0_Error) {
    let first = try __s0_buffer_new(U64, d)
    let second = try __s0_buffer_append(U64, d, first, 7)
    let third = try __s0_buffer_append(U64, d, second, 9)
    return Ok(__s0_buffer_len(U64, third))
}

fn double(d: Domain) -> Result(Result(U64, __s0_Error), __s0_Error) {
    return Ok(Ok(5))
}

fn nested_try(d: Domain) -> Result(U64, __s0_Error) {
    let value = try try double(d)
    return Ok(value)
}

fn try_of_match(d: Domain) -> Result(U64, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let attempted: Result(U64, __s0_Error) = match __s0_buffer_append(U64, d, empty, 7) {
        Ok(value) => Ok(__s0_buffer_len(U64, value))
        Err(error) => Err(error)
    }
    let grown = try attempted
    return Ok(grown)
}

fn arm_assign_try(d: Domain, b: __s0_Buffer(U64), bad: Bool) -> Result(U64, __s0_Error) {
    var value = b
    if bad {
        value = try __s0_buffer_append(U64, d, b, 9)
    } else {
        value = try __s0_buffer_append(U64, d, b, 8)
    }
    return Ok(__s0_buffer_len(U64, value))
}

fn arm_assign_checked(bad: Bool) -> Result(I64, I64) {
    var value: I64 = 0
    if bad {
        value = try checked(10, 0)
    } else {
        value = try checked(10, 2)
    }
    return Ok(value)
}

fn arm_assign_match(d: Domain, flag: Bool) -> Result(U64, __s0_Error) {
    var result: U64 = 0
    if flag {
        result = match __s0_buffer_new(U64, d) {
            Ok(value) => 1
            Err(error) => 2
        }
    }
    return Ok(result)
}

fn index_by_match(source: [U64], which: Which) -> U64 {
    var local = source
    local[match which {
        First => 0
        Second => 1
    }] = 9
    return local[0] + local[1]
}

fn field_by_match(source: [Indexed], which: Which) -> U64 {
    var local = source
    local[match which {
        First => 0
        Second => 1
    }].value = 9
    return local[0].value + local[1].value
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"continuations.al"})
	second := runLowerCompiler(t, exe, files, []string{"continuations.al"})
	if len(first) == 0 || !bytes.Equal(first, second) {
		t.Fatal("continuation lowering was empty or changed across fresh processes")
	}
	var module *mir.Module
	for run, output := range [][]byte{first, second} {
		parsed, err := mir.Parse(string(output))
		if err != nil {
			t.Fatalf("parse continuation MIR run %d: %v\n%s", run, err, output)
		}
		if diagnostics := verify.Module(parsed); len(diagnostics) != 0 {
			t.Fatalf("verify continuation MIR run %d: %s\n%s", run, verify.Errors(diagnostics), output)
		}
		if run == 0 {
			module = parsed
		}
	}
	for _, name := range []string{"sequential_try", "double", "nested_try", "try_of_match", "arm_assign_try", "arm_assign_checked", "arm_assign_match", "index_by_match", "field_by_match"} {
		if _, ok := module.Function(name); !ok {
			t.Fatalf("continuation MIR has no function %q\n%s", name, first)
		}
	}
	// #90: a try switch must land on the operand's continuation, never on a
	// freshly added bb_try_err block (which carries only the fail terminator).
	for _, function := range module.Functions {
		for _, block := range function.Blocks {
			if block.Term.Kind == mir.TermSwitch && strings.HasPrefix(block.Name, "bb_try_err") {
				t.Fatalf("try switch placed on err block %s in %s", block.Name, function.Name)
			}
		}
	}
	// #90 nested try: the outer try continues on the inner try's ok block.
	checkSwitchOnPrefixedBlock(t, module, "nested_try", "bb_try_ok")
	// #90 try-of-match: the try continues on the match join.
	checkSwitchOnPrefixedBlock(t, module, "try_of_match", "bb_match_join")
	// #111: the assignment store lands on the continuation block, which then
	// jumps to the enclosing join instead of leaving two terminators on the
	// arm block.
	for _, name := range []string{"arm_assign_try", "arm_assign_checked"} {
		checkTryAssignStoreContinuation(t, module, name)
	}
	checkMatchAssignStoreContinuation(t, module, "arm_assign_match")
	// #116: slice_index_checked results are owned by the block that contains
	// the instruction, even when the index eval terminated the requested block.
	checkSliceIndexOwnership(t, module)

	accept, err := os.ReadFile(filepath.Join("..", "frontend", "testdata", "accept", "buffer.al"))
	if err != nil {
		t.Fatal(err)
	}
	buffer := runLowerCompiler(t, exe, map[string]string{"buffer.al": string(accept)}, []string{"buffer.al"})
	if len(buffer) == 0 {
		t.Fatal("accept/buffer.al lowering was empty")
	}
	parsed, err := mir.Parse(string(buffer))
	if err != nil {
		t.Fatalf("parse buffer MIR: %v\n%s", err, buffer)
	}
	if diagnostics := verify.Module(parsed); len(diagnostics) != 0 {
		t.Fatalf("verify buffer MIR: %s\n%s", verify.Errors(diagnostics), buffer)
	}
	if _, ok := parsed.Function("build"); !ok {
		t.Fatalf("buffer MIR has no build function\n%s", buffer)
	}
}

func checkSwitchOnPrefixedBlock(t *testing.T, module *mir.Module, functionName, prefix string) {
	t.Helper()
	id, ok := module.Function(functionName)
	if !ok {
		t.Fatalf("continuation MIR has no function %q", functionName)
	}
	for _, block := range module.Functions[id].Blocks {
		if block.Term.Kind == mir.TermSwitch && strings.HasPrefix(block.Name, prefix) {
			return
		}
	}
	t.Fatalf("%s has no switch on a %s* block", functionName, prefix)
}

func checkTryAssignStoreContinuation(t *testing.T, module *mir.Module, functionName string) {
	t.Helper()
	id, ok := module.Function(functionName)
	if !ok {
		t.Fatalf("continuation MIR has no function %q", functionName)
	}
	f := module.Functions[id]
	found := false
	for _, block := range f.Blocks {
		if block.Term.Kind != mir.TermSwitch {
			continue
		}
		for _, c := range block.Term.Cases {
			if c.Variant != "ok" {
				continue
			}
			found = true
			target := f.Blocks[c.Target]
			hasStore := false
			for _, in := range target.Instrs {
				if in.Op == mir.OpStore {
					hasStore = true
				}
			}
			if !hasStore {
				t.Fatalf("%s try ok continuation %s contains no store", functionName, target.Name)
			}
			if target.Term.Kind != mir.TermJump {
				t.Fatalf("%s try ok continuation %s ends with %s, want jump", functionName, target.Name, target.Term.Kind)
			}
		}
	}
	if !found {
		t.Fatalf("%s has no try switch", functionName)
	}
}

func checkMatchAssignStoreContinuation(t *testing.T, module *mir.Module, functionName string) {
	t.Helper()
	id, ok := module.Function(functionName)
	if !ok {
		t.Fatalf("continuation MIR has no function %q", functionName)
	}
	for _, block := range module.Functions[id].Blocks {
		if !strings.HasPrefix(block.Name, "bb_match_join") {
			continue
		}
		hasStore := false
		for _, in := range block.Instrs {
			if in.Op == mir.OpStore {
				hasStore = true
			}
		}
		if !hasStore {
			t.Fatalf("%s match join %s contains no store", functionName, block.Name)
		}
		if block.Term.Kind != mir.TermJump {
			t.Fatalf("%s match join %s ends with %s, want jump", functionName, block.Name, block.Term.Kind)
		}
		return
	}
	t.Fatalf("%s has no match join block", functionName)
}

func checkSliceIndexOwnership(t *testing.T, module *mir.Module) {
	t.Helper()
	for _, function := range module.Functions {
		for bi, block := range function.Blocks {
			for _, in := range block.Instrs {
				if in.Op != mir.OpSliceIndexChecked || in.Result == mir.NoValue {
					continue
				}
				def := function.Values[in.Result].Def
				if def.Kind != mir.ValueDefInstr || int(def.Block) != bi {
					t.Fatalf("slice_index_checked ownership mismatch in %s: instruction block %d, value def %+v", function.Name, bi, def)
				}
			}
		}
	}
}

// Issue #79: Err(Limit)/Err(OutOfMemory) are payload-free S0 error
// constructors. The checker records them as kind-6 call annotations and the
// lowering emits a payload-free enum.construct of the named __s0_Error variant.
func runErrorConstructorLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"err_construct.al": "fn fail() -> Result(U64, __s0_Error) { return Err(Limit) }\nfn fail_oom() -> Result(U64, __s0_Error) { return Err(OutOfMemory) }\n",
	}
	first := runLowerCompiler(t, exe, files, []string{"err_construct.al"})
	second := runLowerCompiler(t, exe, files, []string{"err_construct.al"})
	if len(first) == 0 || !bytes.Equal(first, second) {
		t.Fatal("S0 error constructor lowering changed across fresh processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v", err)
	}
	for _, tc := range []struct {
		function, variant string
	}{
		{function: "fail", variant: "Limit"},
		{function: "fail_oom", variant: "OutOfMemory"},
	} {
		id, ok := module.Function(tc.function)
		if !ok {
			t.Fatalf("lowered MIR has no function %q", tc.function)
		}
		found := false
		for _, block := range module.Functions[id].Blocks {
			for _, instruction := range block.Instrs {
				if instruction.Op == mir.OpEnumConstruct && instruction.Variant == tc.variant && instruction.Payload == mir.NoValue {
					found = true
				}
			}
		}
		if !found {
			t.Fatalf("%s did not lower a payload-free enum.construct of %q", tc.function, tc.variant)
		}
	}
}
