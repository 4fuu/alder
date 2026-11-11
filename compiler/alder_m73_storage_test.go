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

// M7.3 slice 3 storage-side lowering contract: view-aggregate results lower
// to hidden caller-result domains, copy_to_domain at return roots, and
// generated C keeps the materialized views independent of the caller's
// source storage.
func runAlderM73LowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"views.al": `type Window {
    prefix: [U64]
    data: [U64]
}
fn window(values: Array(U64, 4)) -> Window {
    return Window(prefix: values.slice(0, 2), data: values.slice(2, 4))
}
fn nested(values: Array(U64, 4)) -> Window {
    return window(values)
}
fn main() -> I32 {
    return 0
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"views.al"})
	second := runLowerCompiler(t, exe, files, []string{"views.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("view-aggregate lowered MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse view-aggregate MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify view-aggregate MIR: %s\n%s", verify.Errors(diagnostics).String(), first)
	}
	printed := string(first)
	for _, want := range []string{
		"prefix: slice(u64)",
		"data: slice(u64)",
		"copy_to_domain",
		"%__domain: domain_handle",
	} {
		if !strings.Contains(printed, want) {
			t.Fatalf("view-aggregate lowered MIR is missing %q:\n%s", want, printed)
		}
	}
	windowID, ok := module.Function("window")
	if !ok {
		t.Fatalf("view-aggregate MIR has no window function:\n%s", printed)
	}
	if len(module.Functions[windowID].Params) != 2 || module.Functions[windowID].Params[0].Type != module.DomainHandle() {
		t.Fatalf("window does not carry the hidden placement domain as its first parameter")
	}

	// Generic records substitute their member type parameters at any depth:
	// Span(T) { head: [T] } must lower distinct concrete instances whose
	// fields are resolved element types, not unresolved parameters.
	genericFiles := map[string]string{
		"generic.al": `type Span(T: type) {
    head: [T]
}
fn span_of(T: type, values: Array(T, 2)) -> Span(T) {
    return Span(head: values.slice(1, 2))
}
fn main() -> I32 {
    var wide: Array(U64, 2) = [4, 9]
    var narrow: Array(U8, 2) = [4, 9]
    if span_of(U64, wide).head[0] != 9 { return 1 }
    if span_of(U8, narrow).head[0] != 9 { return 2 }
    return 0
}
`,
	}
	genericLowered := runLowerCompiler(t, exe, genericFiles, []string{"generic.al"})
	genericModule, err := mir.Parse(string(genericLowered))
	if err != nil {
		t.Fatalf("parse generic view-aggregate MIR: %v\n%s", err, genericLowered)
	}
	if diagnostics := verify.Module(genericModule); len(diagnostics) != 0 {
		t.Fatalf("verify generic view-aggregate MIR: %s\n%s", verify.Errors(diagnostics).String(), genericLowered)
	}
	genericPrinted := string(genericLowered)
	for _, want := range []string{"head: slice(u64)", "head: slice(u8)"} {
		if !strings.Contains(genericPrinted, want) {
			t.Fatalf("generic view-aggregate MIR is missing %q:\n%s", want, genericPrinted)
		}
	}

	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"views.al"})
	nestedID, ok := module.Function("nested")
	if !ok {
		t.Fatalf("view-aggregate MIR has no nested function:\n%s", printed)
	}
	object := buildRuntimeObject(t, cc, root)
	dir := t.TempDir()
	genPath := filepath.Join(dir, "gen.c")
	driverPath := filepath.Join(dir, "driver.c")
	program := filepath.Join(dir, "views.exe")
	if err := os.WriteFile(genPath, generated, 0o644); err != nil {
		t.Fatal(err)
	}
	driver := fmt.Sprintf(`#include "gen.c"
#include <stdint.h>
int main(void) {
    AlderDomain root = {0};
    if (!alder_domain_init(&root, NULL)) { return 2; }
    AlderTy15 values = {.alder_e = {3, 5, 7, 11}};
    AlderTy12 window = alder_fn_window_%d(&root, values);
    const uint64_t *prefix = (const uint64_t *)window.alder_f0.data;
    const uint64_t *data = (const uint64_t *)window.alder_f1.data;
    if (window.alder_f0.len != 2 || window.alder_f1.len != 2) { return 3; }
    if (prefix[0] != 3 || prefix[1] != 5) { return 4; }
    if (data[0] != 7 || data[1] != 11) { return 5; }
    /* The materialized views live in the caller-result domain, so mutating
     * the caller's source array cannot change them. */
    values.alder_e[0] = 99;
    if (prefix[0] != 3) { return 6; }
    AlderTy12 forwarded = alder_fn_nested_%d(&root, values);
    const uint64_t *forwarded_prefix = (const uint64_t *)forwarded.alder_f0.data;
    if (forwarded_prefix[0] != 99 || forwarded_prefix[1] != 5) { return 7; }
    alder_domain_destroy(&root);
    return alder_runtime_live_allocations() == (size_t)0 ? 0 : 8;
}
`, windowID, nestedID)
	if err := os.WriteFile(driverPath, []byte(driver), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-ffp-contract=off",
		"-I", filepath.Dir(genPath), "-I", filepath.Join(root, "runtime", "c"), genPath, driverPath, object, "-o", program}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile view-aggregate generated C: %v\n%s", err, out)
	}
	if out, err := exec.Command(program).CombinedOutput(); err != nil {
		t.Fatalf("run view-aggregate generated C: %v\n%s", err, out)
	}
}

// M7.3 slice 3 storage-side checker contract: ordinary aggregates whose
// scoped parts are all immutable views can be constructed and returned,
// because lowering materializes their view parts into caller-result storage.
// Every other escape of a view through an aggregate stays rejected with the
// stable scoped-view diagnostic.
func runAlderM73CheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"views.al": `type Window {
    prefix: [U64]
    data: [U64]
}
fn window(values: Array(U64, 4)) -> Window {
    return Window(prefix: values.slice(0, 2), data: values.slice(2, 4))
}
fn maybe_window(values: Array(U64, 4)) -> Option(Window) {
    return Some(Window(prefix: values.slice(1, 3), data: values.slice(2, 4)))
}
fn fail_window(values: Array(U64, 4)) -> Result(U64, Window) {
    return Err(Window(prefix: values.slice(0, 1), data: values.slice(3, 4)))
}
fn view_pair(values: Array(U64, 2)) -> Array([U64], 2) {
    return [values.slice(0, 1), values.slice(1, 2)]
}
fn read_window(values: Array(U64, 4)) -> U64 {
    if window(values).prefix[0] != values[0] { return 1 }
    let prefix = window(values).prefix
    return prefix[1]
}
fn main() -> I32 {
    let values: Array(U64, 4) = [3, 5, 7, 11]
    if window(values).prefix[0] != 3 || window(values).data[1] != 11 { return 1 }
    if window(values).prefix[1] != read_window(values) { return 2 }
    return 0
}
`,
	}
	manifest := parseCheckerManifest(t, runAlderChecker(t, exe, accept, []string{"views.al"}, false), accept)
	if len(manifest.diagnostics) != 0 {
		t.Fatalf("M7.3 view-aggregate acceptance diagnostics: %+v", manifest.diagnostics)
	}

	generic := map[string]string{
		"generic.al": `type Span(T: type) {
    head: [T]
}
fn span_of(T: type, values: Array(T, 2)) -> Span(T) {
    return Span(head: values.slice(1, 2))
}
fn main() -> I32 {
    let wide: Array(U64, 2) = [4, 9]
    let narrow: Array(U8, 2) = [4, 9]
    if span_of(U64, wide).head[0] != 9 { return 1 }
    if span_of(U8, narrow).head[0] != 9 { return 2 }
    return 0
}
`,
	}
	genericManifest := parseCheckerManifest(t, runAlderChecker(t, exe, generic, []string{"generic.al"}, false), generic)
	if len(genericManifest.diagnostics) != 0 {
		t.Fatalf("M7.3 generic view-aggregate diagnostics: %+v", genericManifest.diagnostics)
	}
	spanDeclaration := checkerSymbolByName(t, genericManifest, generic, "span_of")
	spanInstances := 0
	for _, instance := range genericManifest.instances {
		if instance.declaration == spanDeclaration.id {
			spanInstances = spanInstances + 1
		}
	}
	if spanInstances != 2 {
		t.Fatalf("span_of concrete instances = %d, want the U64 and U8 instances", spanInstances)
	}

	rejections := []struct {
		name, source string
		code         int
	}{
		{"mutable-view-aggregate-return", "type Bad {\n    m: MutSlice(U64)\n}\nfn f() -> Bad {\n    var values: Array(U64, 2) = [1, 2]\n    return Bad(m: values.slice_mut(0, 1))\n}\n", 104},
		{"mutable-view-variant-return", "fn f(values: Array(U64, 2)) -> Option(MutSlice(U64)) {\n    return Some(values.slice_mut(0, 1))\n}\n", 104},
		{"view-aggregate-binding", "type Window {\n    prefix: [U64]\n}\nfn f(values: [U64]) -> Unit {\n    let holder = Window(prefix: values)\n}\n", 104},
		{"view-aggregate-argument", "type Window {\n    prefix: [U64]\n}\nfn consume(window: Window) -> U64 {\n    return window.prefix[0]\n}\nfn f(values: [U64]) -> Unit {\n    consume(Window(prefix: values))\n}\n", 104},
		{"view-aggregate-using", "type Window {\n    prefix: [U64]\n}\nfn close(window: Window) -> Unit { return }\nfn f(values: [U64]) -> Unit {\n    using holder = Window(prefix: values) with close\n}\n", 104},
		{"view-aggregate-match-scrutinee", "type Window {\n    prefix: [U64]\n}\nenum Pick {\n    Chosen(window: Window)\n    Empty\n}\nfn pick(values: [U64]) -> Pick {\n    return Chosen(Window(prefix: values))\n}\nfn f(values: [U64]) -> U64 {\n    return match pick(values) {\n        Chosen(window) => window.prefix[0]\n        Empty => 0\n    }\n}\n", 104},
	}
	for _, tc := range rejections {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name + ".al": tc.source}
			m := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true), files)
			if len(m.diagnostics) != 1 || m.diagnostics[0].kind != tc.code {
				t.Fatalf("diagnostics = %+v, want exactly one code %d", m.diagnostics, tc.code)
			}
		})
	}

	// Regression for the checked array-literal child window: an element that
	// carries its own child records (a call) must not shift the following
	// element's child slot. Source order must survive checking, lowering,
	// verification, and generated-code execution.
	orderFiles := map[string]string{
		"order.al": "fn twice(value: U64) -> U64 { return value * 2 }\nfn main() -> I32 {\n    let pair: Array(U64, 2) = [twice(11), twice(22)]\n    if pair[0] != 22 { return 1 }\n    if pair[1] != 44 { return 2 }\n    return 0\n}\n",
	}
	lowered := runLowerCompiler(t, exe, orderFiles, []string{"order.al"})
	if repeat := runLowerCompiler(t, exe, orderFiles, []string{"order.al"}); !bytes.Equal(lowered, repeat) {
		t.Fatal("array-order lowered MIR changed across processes")
	}
	module, err := mir.Parse(string(lowered))
	if err != nil {
		t.Fatalf("parse array-order MIR: %v\n%s", err, lowered)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify array-order MIR: %s\n%s", verify.Errors(diagnostics).String(), lowered)
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	generated := runResourceCgenCompiler(t, exe, orderFiles, []string{"order.al"})
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("array-order module has no main function")
	}
	object := buildRuntimeObject(t, cc, root)
	dir := t.TempDir()
	genPath := filepath.Join(dir, "gen.c")
	driverPath := filepath.Join(dir, "driver.c")
	program := filepath.Join(dir, "order.exe")
	if err := os.WriteFile(genPath, generated, 0o644); err != nil {
		t.Fatal(err)
	}
	driver := fmt.Sprintf("#include \"gen.c\"\n#include <stdint.h>\nint main(void) { return (int)alder_fn_main_%d(); }\n", mainID)
	if err := os.WriteFile(driverPath, []byte(driver), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-ffp-contract=off",
		"-I", filepath.Dir(genPath), "-I", filepath.Join(root, "runtime", "c"), genPath, driverPath, object, "-o", program}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile array-order generated C: %v\n%s", err, out)
	}
	if out, err := exec.Command(program).CombinedOutput(); err != nil {
		t.Fatalf("run array-order generated C: %v\n%s", err, out)
	}
}
