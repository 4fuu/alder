package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A record returned from a constructor may carry immutable slice views when
// every view is rooted in a borrowed parameter. The caller may bind the
// returned record and read the materialized view; the source array or vector
// stays alive in the caller's frame. Mutable views and views rooted in the
// callee's locals stay rejected.
func TestProductionAggregateViewBinding(t *testing.T) {
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

	source := `type Holder {
    items: [U64]
    index: U64
}
type ViewHolder(T: type) {
    view: [T]
    at: U64
}
fn make_holder(items: [U64], index: U64) -> Holder {
    return Holder(items: items, index: index)
}
fn make_view(T: type, values: Vec(T)) -> ViewHolder(T) {
    let count = values.len()
    return ViewHolder(view: values.slice(0, count), at: 0)
}
fn maybe_holder(items: [U64]) -> Option(Holder) {
    return Some(Holder(items: items, index: 1))
}
fn result_holder(items: [U64]) -> Result(Holder, U64) {
    return Ok(Holder(items: items, index: 2))
}
fn main() -> I32 {
    let data: Array(U64, 3) = [3, 4, 5]
    let view = data.slice(0, 3)
    let holder = make_holder(view, 7)
    if holder.index != 7 { return 1 }
    if holder.items[1] != 4 { return 2 }

    var values = Vec.new(U64)
    values.push(8)
    values.push(9)
    let view_holder = make_view(U64, values)
    if view_holder.at != 0 { return 3 }
    if view_holder.view.len() != 2 { return 4 }
    if view_holder.view[1] != 9 { return 5 }

    let maybe = maybe_holder(data.slice(0, 2))
    match maybe {
        Some(inner) => {
            if inner.index != 1 { return 6 }
            if inner.items[1] != 4 { return 7 }
        }
        None => { return 8 }
    }
    let result = result_holder(data.slice(1, 3))
    match result {
        Ok(inner) => {
            if inner.index != 2 { return 9 }
            if inner.items[0] != 4 { return 10 }
        }
        Err(_) => { return 11 }
    }
    return 0
}
`
	files := map[string]string{"view-binding.al": source}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "view-binding.al")
	if mirText.status != 0 || mirText.stderr != "" {
		t.Fatalf("view-binding MIR: %+v stderr=%s", mirText, mirText.stderr)
	}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "view-binding.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("view-binding C: %+v stderr=%s", cResult, cResult.stderr)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
	runSanitizedGeneratedProgram(t, cc, root, cResult.stdout)

	rejections := []struct {
		name, source string
	}{
		{
			"local-view-binding",
			`type Holder {
    items: [U64]
    index: U64
}
fn main() -> I32 {
    let local: Array(U64, 2) = [1, 2]
    let holder = Holder(items: local.slice(0, 1), index: 0)
    return 0
}
`,
		},
		{
			"local-view-option-binding",
			`type Holder {
    items: [U64]
    index: U64
}
fn main() -> I32 {
    let local: Array(U64, 2) = [1, 2]
    let maybe: Option(Holder) = Some(Holder(items: local.slice(0, 1), index: 0))
    return 0
}
`,
		},
		{
			"mutable-view-return",
			`type Holder {
    items: MutSlice(U64)
}
fn make() -> Holder {
    var values: Array(U64, 2) = [1, 2]
    return Holder(items: values.slice_mut(0, 1))
}
fn main() -> I32 { return 0 }
`,
		},
	}
	for _, rejection := range rejections {
		t.Run(rejection.name, func(t *testing.T) {
			result := runProductionCompiler(t, exe, map[string]string{rejection.name + ".al": rejection.source}, "check", rejection.name+".al")
			if result.status == 0 || !strings.Contains(result.stderr, "checker diagnostic 104") {
				t.Fatalf("%s was not rejected with diagnostic 104: %+v stderr=%s", rejection.name, result, result.stderr)
			}
		})
	}
}
