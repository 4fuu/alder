package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A function with a borrowed parameter has the function type `fn(mut T) -> R`.
// The mode is part of the type: it never converts to or from `fn(T) -> R`.
const fnMutTypeProgram = `fn bump(mut view: MutSlice(U8)) -> U8 {
    view[0] = view[0] + 1
    return view[0]
}

fn main() -> I32 {
    var data = Vec.from_array(U8, [1])
    let f: fn(mut MutSlice(U8)) -> U8 = bump
    let view = data.slice_mut(0, 1)
    if f(view) != 2 { return 1 }
    return 0
}
`

func TestFunctionMutTypeQualification(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)

	cResult := runProductionCompiler(t, exe, map[string]string{"mut-fn.al": fnMutTypeProgram}, "compile", "--emit=c", "mut-fn.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("fn(mut T) program: %+v", cResult)
	}
	runSanitizedGeneratedProgram(t, cc, root, cResult.stdout)

	rejections := []struct {
		name, source, want string
	}{
		{
			"mut-to-plain",
			`type Holder {
    data: Vec(U8)
}

impl Cleanup for Holder {
    fn cleanup(take self) -> Unit { return () }
}

fn touch(mut holder: Holder) -> U64 { return holder.data.len() }
fn apply(f: fn(Holder) -> U64) -> U64 { return 0 }
fn main() -> I32 {
    let holder = Holder(data: Vec.from_array(U8, [1]))
    let n: U64 = apply(touch)
    return 0
}
`,
			"[SEM0001]",
		},
		{
			"plain-to-mut",
			`type Holder {
    data: Vec(U8)
}

impl Cleanup for Holder {
    fn cleanup(take self) -> Unit { return () }
}

fn inspect(holder: Holder) -> U64 { return holder.data.len() }
fn apply(f: fn(mut Holder) -> U64, mut holder: Holder) -> U64 { return f(holder) }
fn main() -> I32 {
    let holder = Holder(data: Vec.from_array(U8, [1]))
    let n: U64 = apply(inspect, holder)
    return 0
}
`,
			"[SEM0001]",
		},
		{
			"closure-mut-parameter",
			`fn main() -> I32 {
    let f = fn(mut view: MutSlice(U8)) -> U8 { return 0 }
    return 0
}
`,
			"closure parameters cannot be mut or take",
		},
		{
			"function-type-take",
			`fn apply(f: fn(take MutSlice(U8)) -> U8) -> U8 { return 0 }
fn main() -> I32 { return 0 }
`,
			"take is not allowed in a function type",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run(rejection.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": rejection.source}, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("%s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("%s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
