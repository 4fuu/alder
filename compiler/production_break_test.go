package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// `break` and `continue` are 1.0 core control flow. These programs pin the
// lowering end to end through strict C11: both jump to the innermost enclosing
// loop, a `continue` in a `for` still runs the index step, a match arm's
// statement block inherits the enclosing loop context, statements after an
// unconditional `break` are unreachable, and the loop-rebuild move refuses a
// read whose body a `continue` can leave before the rebuilding definition.
//
// Cleanups cannot be crossed: `using` inside a loop is rejected, so no cleanup
// scope is created inside a loop body and neither exit has anything to unwind.
// A table-view match arm restricts its statements to straight-line copy
// statements, so it rejects both jumps as well.

const breakWhileProgram = `fn main() -> I32 {
    var i: U64 = 0
    while i < 10 {
        if i == 3 { break }
        i = i + 1
    }
    if i != 3 { return 1 }
    return 0
}
`

const continueWhileProgram = `fn main() -> I32 {
    var i: U64 = 0
    var total: U64 = 0
    while i < 6 {
        i = i + 1
        if i == 2 { continue }
        total = total + i
    }
    if total != 19 { return 1 }
    return 0
}
`

const breakForProgram = `fn main() -> I32 {
    var v = Vec.new(U64)
    v.push(1)
    v.push(2)
    v.push(3)
    var total: U64 = 0
    for x in v {
        if x == 2 { break }
        total = total + x
    }
    if total != 1 { return 1 }
    return 0
}
`

const continueForProgram = `fn main() -> I32 {
    var v = Vec.new(U64)
    v.push(1)
    v.push(2)
    v.push(3)
    v.push(4)
    var total: U64 = 0
    for x in v {
        if x == 2 { continue }
        total = total + x
    }
    if total != 8 { return 2 }
    return 0
}
`

const breakContinueNestedProgram = `fn main() -> I32 {
    var total: U64 = 0
    var i: U64 = 0
    while i < 3 {
        var j: U64 = 0
        while j < 5 {
            j = j + 1
            if j == 2 { continue }
            if j == 4 { break }
            total = total + 1
        }
        i = i + 1
    }
    if total != 6 { return 1 }
    return 0
}
`

const breakContinueMatchProgram = `enum Step {
    Go
    Skip
    Stop
}
fn classify(i: U64) -> Step {
    if i == 2 { return Skip }
    if i == 3 { return Stop }
    return Go
}
fn main() -> I32 {
    var total: U64 = 0
    var i: U64 = 0
    while i < 5 {
        i = i + 1
        match classify(i) {
            Skip => { continue }
            Stop => { break }
            Go => { total = total + i }
        }
    }
    if i != 3 { return 1 }
    if total != 1 { return 2 }
    return 0
}
`

const breakUnreachableTailProgram = `fn main() -> I32 {
    var v = Vec.new(U64)
    v.push(1)
    v.push(2)
    var total: U64 = 0
    for x in v {
        break
        total = total + x
    }
    if total != 0 { return 1 }
    return 0
}
`

const continueForTailProgram = `fn main() -> I32 {
    var v = Vec.new(U64)
    v.push(1)
    v.push(2)
    var total: U64 = 0
    for x in v {
        total = total + x
        continue
    }
    if total != 3 { return 1 }
    return 0
}
`

// d023ContinueBetweenReadAndRebuild puts an unconditional `continue` between a
// read of `a` and the definition that would rebuild it, so the body is not
// straight-line code and the read must copy. The control program below has the
// same body without the `continue` and moves.
const d023ContinueBetweenReadAndRebuild = `fn add_one(v: Vec(U64)) -> Vec(U64) {
    var b = v
    b.push(1)
    return b
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var total: U64 = 0
    var i: U64 = 0
    while i < 3 {
        i = i + 1
        let b = add_one(a)
        total = total + b.len()
        continue
        a = Vec.new(U64)
    }
    if a.len() != 1 { return 1 }
    if total != 6 { return 2 }
    return 0
}
`

const d023ContinueControl = `fn add_one(v: Vec(U64)) -> Vec(U64) {
    var b = v
    b.push(1)
    return b
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var total: U64 = 0
    var i: U64 = 0
    while i < 3 {
        i = i + 1
        let b = add_one(a)
        total = total + b.len()
        a = Vec.new(U64)
    }
    if total != 4 { return 2 }
    return 0
}
`

func TestM75BreakContinueQualification(t *testing.T) {
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

	programs := []struct {
		name, text string
	}{
		{"break-while.al", breakWhileProgram},
		{"continue-while.al", continueWhileProgram},
		{"break-for.al", breakForProgram},
		{"continue-for.al", continueForProgram},
		{"break-continue-nested.al", breakContinueNestedProgram},
		{"break-continue-match.al", breakContinueMatchProgram},
		{"break-unreachable-tail.al", breakUnreachableTailProgram},
		{"continue-for-tail.al", continueForTailProgram},
		{"d023-continue-rebuild.al", d023ContinueBetweenReadAndRebuild},
		{"d023-continue-control.al", d023ContinueControl},
	}
	for _, program := range programs {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 5\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
		})
	}

	// The move rule refuses the read the `continue` can leave un-rebuilt, and
	// accepts the same body without it.
	continueReport := runProductionCompiler(t, exe, map[string]string{"d023-continue-rebuild.al": d023ContinueBetweenReadAndRebuild}, "check", "--report-copies", "d023-continue-rebuild.al")
	if continueReport.status != 0 {
		t.Fatalf("continue rebuild report run: %+v", continueReport)
	}
	if got := continueReport.stdout + continueReport.stderr; !strings.Contains(got, "copy of `a`: re-read by a loop") {
		t.Fatalf("continue rebuild report missing the loop reason: %q", got)
	}
	controlReport := runProductionCompiler(t, exe, map[string]string{"d023-continue-control.al": d023ContinueControl}, "check", "--report-copies", "d023-continue-control.al")
	if controlReport.status != 0 {
		t.Fatalf("continue control report run: %+v", controlReport)
	}
	if got := controlReport.stdout + controlReport.stderr; strings.Contains(got, "copy of `a`") {
		t.Fatalf("continue control should move its read: %q", got)
	}

	rejections := []struct {
		name, want string
		source     string
	}{
		{"break-outside-loop.al", "break is only allowed inside a loop", "fn main() -> I32 {\n    break\n    return 0\n}\n"},
		{"continue-outside-loop.al", "continue is only allowed inside a loop", "fn main() -> I32 {\n    continue\n    return 0\n}\n"},
		{"break-in-closure-body.al", "break is only allowed inside a loop", "fn main() -> I32 {\n    var i: U64 = 0\n    while i < 2 {\n        i = i + 1\n        let f = fn() -> Unit { break }\n    }\n    return 0\n}\n"},
		// A table-view arm is one straight-line fail-free region, so it cannot
		// carry either jump.
		{"break-in-table-view-arm.al", "table-view match arm may contain only straight-line copy statements", "fn main() -> I32 {\n    using t = Table.new(U64)\n    let id = t.insert(5)\n    var i: U64 = 0\n    while i < 2 {\n        i = i + 1\n        match t.get(id) {\n            Some(v) => { break }\n            None => { }\n        }\n    }\n    return 0\n}\n"},
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
