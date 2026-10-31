package compiler

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

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
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion",
		"-I", filepath.Dir(genPath), "-I", filepath.Join(root, "runtime", "c"), genPath, driverPath, object, "-o", program}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile array-order generated C: %v\n%s", err, out)
	}
	if out, err := exec.Command(program).CombinedOutput(); err != nil {
		t.Fatalf("run array-order generated C: %v\n%s", err, out)
	}
}
