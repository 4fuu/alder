package compiler

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M7.3 slice 3 production qualification: the storage half of the milestone is
// exercised through the Alder production driver on the ordinary public
// surface. The programs avoid every private bootstrap name, so they compile
// without the private profile. New view-aggregate programs intentionally stay
// out of the Go-frontend oracle corpora: the Go checker still rejects nested
// view-aggregate construction, so these programs are qualified through the
// Alder-written pipeline only.

const m73ViewsProgram = `type Window {
    prefix: [U64]
    data: [U64]
}
fn window(values: Array(U64, 4)) -> Window {
    return Window(prefix: values.slice(0, 2), data: values.slice(2, 4))
}
fn forwarded(values: Array(U64, 4)) -> Window {
    return window(values)
}
fn twice_forwarded(values: Array(U64, 4)) -> Window {
    return forwarded(values)
}
fn opt_window(values: Array(U64, 4)) -> Option(Window) {
    return Some(Window(prefix: values.slice(1, 3), data: values.slice(2, 4)))
}
fn opt_pass(values: Array(U64, 4)) -> Option(Window) {
    return opt_window(values)
}
fn fail_window(values: Array(U64, 4)) -> Result(U64, Window) {
    return Err(Window(prefix: values.slice(0, 1), data: values.slice(3, 4)))
}
fn propagate_window(values: Array(U64, 4)) -> Result(U64, Window) {
    let value = try fail_window(values)
    return Ok(value)
}
fn vec_window(seed: Array(U64, 3)) -> Window {
    var values: Vec(U64) = Vec.from_array(U64, seed)
    values.push(99)
    return Window(prefix: values.slice(0, 2), data: values.slice(values.len() - 1, values.len()))
}
fn main() -> I32 {
    var values: Array(U64, 4) = [3, 5, 7, 11]
    if window(values).prefix[0] != 3 || window(values).prefix[1] != 5 { return 1 }
    if window(values).data[0] != 7 || window(values).data[1] != 11 { return 2 }
    let prefix = twice_forwarded(values).prefix
    values[0] = 99
    if prefix[0] != 3 || prefix[1] != 5 { return 3 }
    if window(values).prefix[0] != 99 { return 4 }
    let grown_head = vec_window([13, 17, 19]).prefix
    if vec_window([13, 17, 19]).data[0] != 99 { return 5 }
    var regrown: Vec(U64) = Vec.from_array(U64, [13, 17, 19])
    regrown.push(23)
    regrown.push(29)
    if grown_head[0] != 13 || grown_head[1] != 17 { return 6 }
    if vec_window([13, 17, 19]).data[0] != 99 { return 7 }
    opt_pass(values)
    propagate_window(values)
    return 0
}
`

const m73GenericProgram = `type Span(T: type) {
    head: [T]
}
fn span_of(T: type, values: Array(T, 2)) -> Span(T) {
    return Span(head: values.slice(1, 2))
}
fn pick(T: type, values: Array(T, 2)) -> T {
    return span_of(T, values).head[0]
}
fn main() -> I32 {
    var wide: Array(U64, 2) = [4, 9]
    var narrow: Array(U8, 2) = [4, 9]
    if pick(U64, wide) != 9 { return 1 }
    if pick(U8, narrow) != 9 { return 2 }
    return 0
}
`

// m73LayeredProgram builds a chain of depth functions. Every frame returns
// the next frame's view-aggregate result directly, which lowering retains at
// the root domain through the storage plan's fallback path, and the deepest
// frame constructs the views over its parameter.
func m73LayeredProgram(depth int) string {
	var builder strings.Builder
	builder.WriteString("type Window {\n    prefix: [U64]\n    data: [U64]\n}\n")
	for level := 0; level < depth; level++ {
		next := "level_" + fmt.Sprintf("%03d", level+1)
		if level == depth-1 {
			next = ""
		}
		builder.WriteString(fmt.Sprintf("fn level_%03d(values: Array(U64, 4)) -> Window {\n", level))
		if next != "" {
			builder.WriteString(fmt.Sprintf("    return %s(values)\n", next))
		} else {
			builder.WriteString("    return Window(prefix: values.slice(0, 2), data: values.slice(2, 4))\n")
		}
		builder.WriteString("}\n")
	}
	builder.WriteString(`fn main() -> I32 {
    var values: Array(U64, 4) = [3, 5, 7, 11]
    let prefix = level_000(values).prefix
    values[0] = 99
    if prefix[0] != 3 || prefix[1] != 5 { return 1 }
    if level_000(values).prefix[0] != 99 { return 2 }
    return 0
}
`)
	return builder.String()
}

// A view created per iteration is created and read inside the same iteration,
// so nothing crosses the loop backedge: the loop rule accepts it because every
// read is dominated by a store in the same cycle, and a view whose owner is
// reassigned in the loop stays valid because it is re-created first. The table
// shapes read a row through a view arm and write one through get_mut each
// iteration.
const m73LoopViewProgram = `type Player {
    age: U64
}
fn one(seed: U64) -> Vec(U64) {
    var v = Vec.new(U64)
    v.push(seed)
    v.push(seed + 1)
    return v
}
fn while_views(seed: U64) -> U64 {
    var total: U64 = 0
    var i: U64 = 0
    while i < 3 {
        let v = one(seed + i)
        let s = v.slice(0, 2)
        total = total + s.len() + s[0]
        i = i + 1
    }
    return total
}
fn for_views(seed: U64) -> U64 {
    let items = one(seed)
    let other = one(seed + 10)
    var total: U64 = 0
    for x in items {
        let s = other.slice(0, 2)
        total = total + x + s.len()
    }
    return total
}
fn reassigned_owner(seed: U64) -> U64 {
    var v = one(seed)
    var total: U64 = 0
    var i: U64 = 0
    while i < 3 {
        let s = v.slice(0, 2)
        total = total + s.len() + s[1]
        v = one(seed + i)
        i = i + 1
    }
    return total
}
fn table_loop(seed: U64) -> U64 {
    using players = Table.new(Player)
    let first = players.insert(Player(age: seed))
    var total: U64 = 0
    var i: U64 = 0
    while i < 3 {
        total = total + match players.get(first) {
            Some(p) => p.age
            None => 0
        }
        match players.get_mut(first) {
            Some(p) => { p.age = i }
            None => {}
        }
        i = i + 1
    }
    return total + match players.get(first) {
        Some(p) => p.age
        None => 0
    }
}
fn main() -> I32 {
    if while_views(10) != 39 { return 1 }
    if for_views(10) != 25 { return 2 }
    if reassigned_owner(10) != 40 { return 3 }
    if table_loop(5) != 8 { return 4 }
    return 0
}
`

func runM73ProductionProgram(t *testing.T, exe, object, root, name, text string) {
	t.Helper()
	files := map[string]string{name: text}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", name)
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("%s MIR result: %+v", name, mirText)
	}
	repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", name)
	if repeat != mirText {
		t.Fatalf("%s MIR changed across processes: first=%+v second=%+v", name, mirText, repeat)
	}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", name)
	if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("%s C result: %+v", name, cResult)
	}
	cRepeat := runProductionCompiler(t, exe, files, "compile", "--emit=c", name)
	if cRepeat != cResult {
		t.Fatalf("%s C changed across processes", name)
	}
	compileAndRunProductionArtifact(t, "gcc", root, object, cResult.stdout, 0)
}

func TestM73StorageProductionQualification(t *testing.T) {
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

	t.Run("view-aggregate-results", func(t *testing.T) {
		t.Parallel()
		runM73ProductionProgram(t, exe, runtimeObject, root, "views.al", m73ViewsProgram)
	})
	t.Run("generic-monomorphization", func(t *testing.T) {
		t.Parallel()
		runM73ProductionProgram(t, exe, runtimeObject, root, "generic.al", m73GenericProgram)
	})
	t.Run("loop-views", func(t *testing.T) {
		t.Parallel()
		runM73ProductionProgram(t, exe, runtimeObject, root, "loopviews.al", m73LoopViewProgram)
	})
	t.Run("layered-retention", func(t *testing.T) {
		t.Parallel()
		runM73ProductionProgram(t, exe, runtimeObject, root, "layered.al", m73LayeredProgram(120))
	})
	t.Run("layered-permutations", func(t *testing.T) {
		t.Parallel()
		// The layered chain is split across sources so canonical path order,
		// not discovery order, drives compilation; identical MIR and C across
		// permutations pins deterministic diagnostics and output.
		depth := 60
		var heads, tails strings.Builder
		heads.WriteString("type Window {\n    prefix: [U64]\n    data: [U64]\n}\n")
		for level := 0; level < depth; level++ {
			next := "level_" + fmt.Sprintf("%03d", level+1)
			own := "level_" + fmt.Sprintf("%03d", level)
			var body string
			if level == depth-1 {
				body = "    return Window(prefix: values.slice(0, 2), data: values.slice(2, 4))\n"
			} else {
				body = fmt.Sprintf("    return %s(values)\n", next)
			}
			if level < depth/2 {
				heads.WriteString(fmt.Sprintf("fn %s(values: Array(U64, 4)) -> Window {\n%s}\n", own, body))
			} else {
				tails.WriteString(fmt.Sprintf("fn %s(values: Array(U64, 4)) -> Window {\n%s}\n", own, body))
			}
		}
		tails.WriteString(`fn main() -> I32 {
    var values: Array(U64, 4) = [3, 5, 7, 11]
    if level_000(values).prefix[1] != 5 { return 1 }
    return 0
}
`)
		files := map[string]string{"a_heads.al": heads.String(), "z_tail.al": tails.String()}
		first := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "z_tail.al", "a_heads.al")
		second := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "a_heads.al", "z_tail.al")
		if first.status != 0 || first.stderr != "" || !strings.HasPrefix(first.stdout, "mir 6\n") {
			t.Fatalf("layered permutation MIR: %+v", first)
		}
		if first != second {
			t.Fatal("layered MIR changed with source permutation")
		}
		cFirst := runProductionCompiler(t, exe, files, "compile", "--emit=c", "z_tail.al", "a_heads.al")
		cSecond := runProductionCompiler(t, exe, files, "compile", "--emit=c", "a_heads.al", "z_tail.al")
		if cFirst.status != 0 || cFirst.stderr != "" || cFirst != cSecond {
			t.Fatalf("layered permutation C: first=%+v equal=%v", cFirst, cFirst == cSecond)
		}
		compileAndRunProductionArtifact(t, cc, root, runtimeObject, cFirst.stdout, 0)
	})

	// Rejections through the production driver. These programs stay out of
	// the shared Go-comparison corpora: the Go checker rejects them at
	// construction with a different message, while the Alder checker rejects
	// them at the escape gate.
	rejections := []struct {
		name, want string
		source     string
	}{
		{"mutable-view-aggregate-return.al", "checker diagnostic 104", "type Bad {\n    m: MutSlice(U64)\n}\nfn f() -> Bad {\n    var values: Array(U64, 2) = [1, 2]\n    return Bad(m: values.slice_mut(0, 1))\n}\nfn main() -> I32 { return 0 }\n"},
		{"view-aggregate-binding.al", "checker diagnostic 104", "type Window {\n    prefix: [U64]\n}\nfn f(values: [U64]) -> I32 {\n    let holder = Window(prefix: values)\n    return 0\n}\nfn main() -> I32 { return 0 }\n"},
		{"view-aggregate-scrutinee.al", "checker diagnostic 104", "type Window {\n    prefix: [U64]\n}\nenum Pick {\n    Chosen(window: Window)\n    Empty\n}\nfn pick(values: [U64]) -> Pick {\n    return Chosen(Window(prefix: values))\n}\nfn f(values: [U64]) -> U64 {\n    return match pick(values) {\n        Chosen(window) => window.prefix[0]\n        Empty => 0\n    }\n}\nfn main() -> I32 { return 0 }\n"},
		{"immutable-view-owner-mutation.al", "exclusive or owning access", "fn main() -> I32 {\n    var values: Array(U64, 2) = [1, 2]\n    let view: [U64] = values.slice(0, 2)\n    values[0] = 3\n    return 0\n}\n"},
		// Diagnostic 101 must keep its own meaning in ordinary programs; it
		// once shared a message with the private bootstrap-operation gate.
		{"immutable-vec-receiver-push.al", "checker diagnostic 101", "fn add(values: Vec(U64)) -> I32 {\n    values.push(1)\n    return 0\n}\nfn main() -> I32 { return 0 }\n"},
		{"view-assigned-in-loop.al", "a view cannot be assigned inside a loop body", "fn one(seed: U64) -> Vec(U64) {\n    var v = Vec.new(U64)\n    v.push(seed)\n    return v\n}\nfn f(seed: U64) -> U64 {\n    let v = one(seed)\n    var s = v.slice(0, 1)\n    var total: U64 = 0\n    var i: U64 = 0\n    while i < 3 {\n        s = v.slice(0, 1)\n        total = total + s.len()\n        i = i + 1\n    }\n    return total\n}\nfn main() -> I32 { return 0 }\n"},
		{"overlapping-mutable-views.al", "exclusive or owning access", "fn main() -> I32 {\n    var values: Array(U64, 3) = [1, 2, 3]\n    var left: MutSlice(U64) = values.slice_mut(0, 2)\n    var right: MutSlice(U64) = values.slice_mut(1, 3)\n    return 0\n}\n"},
	}
	for _, tc := range rejections {
		tc := tc
		t.Run("reject/"+tc.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{tc.name: tc.source}
			result := runProductionCompiler(t, exe, files, "compile", "--emit=mir", tc.name)
			if result.status == 0 || result.stdout != "" || !strings.Contains(result.stderr, tc.want) {
				t.Fatalf("%s rejection: %+v want stderr containing %q", tc.name, result, tc.want)
			}
		})
	}
}
