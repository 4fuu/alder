package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The loop-carried collection gap: for-loops over owned Vec(T) values and
// whole-vector reassignment inside while bodies previously produced MIR that
// phase 5 and phase 6 refused (the loop parameter carried a view type and
// the loop-store rule rejected every storage-backed header). These programs
// pin the fixed shapes end to end through strict C11: a for over a local
// vector, a for over a vector field, a for over a vector-returning call, a
// while that reassigns the vector from a call, a while that pushes into an
// outer vector, and Map/Set/Vec values built inside loops.
//
// The second group pins the compositions around a reassigned sequence, which
// phase 6 used to refuse because it asked whether a carried value's storage
// was allocated on ANY cycle in the function rather than inside the loop
// being checked: a while that rebuilds the vector followed by a for over it,
// a for followed by a while that grows it and a second for, a nested for over
// the same rebuilt vector, a for inside the while, and Map/Set grown in the
// same while as the rebuild. Two for statements in one function also pin the
// per-loop block-parameter and constant names that used to collide.

const loopVecForLocal = `fn main() -> I32 {
    var v = Vec.new(U64)
    v.push(7)
    v.push(9)
    var total: U64 = 0
    for x in v {
        total = total + x
    }
    if total != 16 { return 1 }
    return 0
}
`

const loopVecForField = `type Box {
    items: Vec(U64)
}
fn main() -> I32 {
    let b = Box(items: Vec.new(U64))
    var total: U64 = 0
    for x in b.items {
        total = total + x
    }
    if total != 0 { return 1 }
    return 0
}
`

const loopVecForCall = `fn make(v: U64) -> Vec(U64) {
    var r = Vec.new(U64)
    r.push(v)
    return r
}
fn main() -> I32 {
    var total: U64 = 0
    for x in make(5) {
        total = total + x
    }
    if total != 5 { return 1 }
    return 0
}
`

const loopVecReassign = `fn add_one(v: Vec(U64)) -> Vec(U64) {
    var b = v
    b.push(1)
    return b
}
fn main() -> I32 {
    var a = Vec.new(U64)
    var i: U64 = 0
    while i < 3 {
        i = i + 1
        a = add_one(a)
    }
    if a.len() != 3 { return 1 }
    return 0
}
`

const loopVecPushOuter = `fn main() -> I32 {
    var a = Vec.new(U64)
    var i: U64 = 0
    while i < 4 {
        i = i + 1
        a.push(i)
    }
    if a.len() != 4 { return 1 }
    return 0
}
`

const loopMapValues = `fn main() -> I32 {
    var m = Map.new(U64, Vec(U64))
    var i: U64 = 0
    while i < 2 {
        i = i + 1
        var row = Vec.new(U64)
        row.push(i)
        let _ = m.insert(i, row)
    }
    if m.len() != 2 { return 1 }
    match m.get(1) {
        Some(v) => { if v.len() != 1 { return 2 } }
        None => { return 3 }
    }
    return 0
}
`

const loopSetInsert = `fn main() -> I32 {
    var s = Set.new(U64)
    var i: U64 = 0
    while i < 3 {
        i = i + 1
        let _ = s.insert(i)
    }
    if s.len() != 3 { return 1 }
    return 0
}
`

const loopForAfterRebuild = `fn rebuild(src: Vec(U64)) -> Vec(U64) {
    var out = Vec.new(U64)
    var i: U64 = 0
    while i < src.len() {
        match src.get(i) {
            Some(x) => { out.push(x) }
            None => { }
        }
        i = i + 1
    }
    out.push(src.len())
    return out
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var i: U64 = 0
    while i < 3 {
        a = rebuild(a)
        i = i + 1
    }
    var total: U64 = 0
    for x in a {
        total = total + x
    }
    if a.len() != 4 { return 1 }
    if total != 11 { return 2 }
    return 0
}
`

const loopForThenWhile = `fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(1)
    a.push(2)
    var total: U64 = 0
    for x in a {
        total = total + x
    }
    var i: U64 = 0
    while i < 3 {
        a.push(7)
        i = i + 1
    }
    for y in a {
        total = total + y
    }
    if total != 27 { return 1 }
    return 0
}
`

const loopNestedForRebuild = `fn rebuild(src: Vec(U64)) -> Vec(U64) {
    var out = Vec.new(U64)
    var i: U64 = 0
    while i < src.len() {
        match src.get(i) {
            Some(x) => { out.push(x) }
            None => { }
        }
        i = i + 1
    }
    out.push(src.len())
    return out
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var i: U64 = 0
    while i < 2 {
        a = rebuild(a)
        i = i + 1
    }
    var total: U64 = 0
    for x in a {
        for y in a {
            total = total + x * y
        }
    }
    if a.len() != 3 { return 1 }
    if total != 64 { return 2 }
    return 0
}
`

const loopWhileForRebuild = `fn rebuild(src: Vec(U64)) -> Vec(U64) {
    var out = Vec.new(U64)
    var i: U64 = 0
    while i < src.len() {
        match src.get(i) {
            Some(x) => { out.push(x) }
            None => { }
        }
        i = i + 1
    }
    out.push(src.len())
    return out
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var i: U64 = 0
    while i < 2 {
        a = rebuild(a)
        i = i + 1
    }
    var total: U64 = 0
    var j: U64 = 0
    while j < 2 {
        for x in a {
            total = total + x
        }
        j = j + 1
    }
    if total != 16 { return 1 }
    return 0
}
`

const loopMapRebuild = `fn rebuild(src: Vec(U64)) -> Vec(U64) {
    var out = Vec.new(U64)
    var i: U64 = 0
    while i < src.len() {
        match src.get(i) {
            Some(x) => { out.push(x) }
            None => { }
        }
        i = i + 1
    }
    out.push(src.len())
    return out
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var m = Map.new(U64, U64)
    var i: U64 = 0
    while i < 3 {
        a = rebuild(a)
        let _ = m.insert(i, a.len())
        i = i + 1
    }
    var total: U64 = 0
    for x in a {
        total = total + x
    }
    if a.len() != 4 { return 1 }
    if total != 11 { return 2 }
    if m.len() != 3 { return 3 }
    match m.get(2) {
        Some(v) => { if v != 4 { return 4 } }
        None => { return 5 }
    }
    return 0
}
`

const loopSetRebuild = `fn rebuild(src: Vec(U64)) -> Vec(U64) {
    var out = Vec.new(U64)
    var i: U64 = 0
    while i < src.len() {
        match src.get(i) {
            Some(x) => { out.push(x) }
            None => { }
        }
        i = i + 1
    }
    out.push(src.len())
    return out
}
fn main() -> I32 {
    var a = Vec.new(U64)
    a.push(5)
    var s = Set.new(U64)
    var i: U64 = 0
    while i < 3 {
        a = rebuild(a)
        let _ = s.insert(a.len())
        i = i + 1
    }
    var total: U64 = 0
    for x in a {
        total = total + x
    }
    if a.len() != 4 { return 1 }
    if total != 11 { return 2 }
    if s.len() != 3 { return 3 }
    return 0
}
`

func TestM75LoopVecProductionQualification(t *testing.T) {
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
		{"loop-vec-for-local.al", loopVecForLocal},
		{"loop-vec-for-field.al", loopVecForField},
		{"loop-vec-for-call.al", loopVecForCall},
		{"loop-vec-reassign.al", loopVecReassign},
		{"loop-vec-push-outer.al", loopVecPushOuter},
		{"loop-map-values.al", loopMapValues},
		{"loop-set-insert.al", loopSetInsert},
		{"loop-for-after-rebuild.al", loopForAfterRebuild},
		{"loop-for-then-while.al", loopForThenWhile},
		{"loop-nested-for-rebuild.al", loopNestedForRebuild},
		{"loop-while-for-rebuild.al", loopWhileForRebuild},
		{"loop-map-rebuild.al", loopMapRebuild},
		{"loop-set-rebuild.al", loopSetRebuild},
	}
	for _, program := range programs {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
		})
	}
}
