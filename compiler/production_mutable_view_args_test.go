package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Inherent and trait methods share one call path for exclusive-view
// parameters. A MutSlice parameter is mutable through its binding whether or
// not the declaration repeats `mut`, a let-bound view may be passed as the
// capability, and a newly formed view may be the final argument. Taking
// slice_mut still requires the owner binding to be mutable.
const mutableViewArgsProgram = `trait Packer {
    fn pack(mut self, mut buffer: MutSlice(U8)) -> Unit
}

type Box {
    n: U64
}

impl Packer for Box {
    fn pack(mut self, mut buffer: MutSlice(U8)) -> Unit {
        buffer[2] = self.n.to_u8_wrapping()
        return
    }
}

impl Box {
    fn pack_let(mut self, buffer: MutSlice(U8)) -> Unit {
        buffer[0] = self.n.to_u8_wrapping()
        return
    }
    fn pack_mut(mut self, mut buffer: MutSlice(U8)) -> Unit {
        buffer[1] = self.n.to_u8_wrapping()
        return
    }
}

fn forward(mut buffer: MutSlice(U8)) -> Unit {
    var b = Box(n: 4)
    b.pack_mut(buffer)
    return
}

fn main() -> I32 {
    var b = Box(n: 7)

    var first: Array(U8, 3) = [0, 0, 0]
    let first_view = first.slice_mut(0, 3)
    b.pack_let(first_view)
    if first_view[0] != 7 { return 1 }

    var second: Array(U8, 3) = [0, 0, 0]
    b.pack_mut(second.slice_mut(0, 3))
    if second[1] != 7 { return 2 }

    var third: Array(U8, 3) = [0, 0, 0]
    let third_view = third.slice_mut(0, 3)
    b.pack(third_view)
    if third_view[2] != 7 { return 3 }

    var fourth: Array(U8, 3) = [0, 0, 0]
    forward(fourth.slice_mut(0, 3))
    if fourth[1] != 4 { return 4 }

    var fifth: Array(U8, 3) = [0, 0, 0]
    let fifth_view = fifth.slice_mut(0, 3)
    b.pack_let(fifth_view)
    if fifth_view[0] != 7 { return 5 }
    return 0
}
`

func TestMutableViewArgumentsProductionQualification(t *testing.T) {
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

	files := map[string]string{"view-args.al": mutableViewArgsProgram}
	cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", "view-args.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("emit=c result: %+v", cResult)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)

	rejections := []struct {
		name, source, want string
	}{
		{
			"slice-mut-immutable-owner",
			"fn main() -> I32 {\n    let data: Array(U8, 2) = [0, 0]\n    let view = data.slice_mut(0, 2)\n    return 0\n}\n",
			"checker diagnostic 101",
		},
		{
			"temporary-view-not-final",
			"fn fill(mut buffer: MutSlice(U8), tail: U64) -> Unit {\n    buffer[0] = 1\n    return\n}\nfn main() -> I32 {\n    var data: Array(U8, 2) = [0, 0]\n    fill(data.slice_mut(0, 2), 1)\n    return 0\n}\n",
			"checker diagnostic 104",
		},
		{
			"view-binding-reassignment",
			"fn main() -> I32 {\n    var data: Array(U8, 2) = [0, 0]\n    let view = data.slice_mut(0, 2)\n    view = data.slice_mut(0, 2)\n    return 0\n}\n",
			"immutable binding",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": rejection.source}, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
