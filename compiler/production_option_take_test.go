package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const optionTakeScalarProgram = `fn main() -> I32 {
    var slot: Option(U64) = Some(7)
    let first = slot.take()
    match first {
        Some(value) => { if value != 7 { return 1 } }
        None => { return 2 }
    }
    match slot.take() {
        Some(_) => { return 3 }
        None => {}
    }
    var empty: Option(U64) = None
    match empty.take() {
        Some(_) => { return 4 }
        None => {}
    }
    return 0
}
`

// The affine payload is moved out of a mut-self field. The wrapper cleanup
// must observe None and release nothing; the returned owner is released once,
// so the imported counter totals 7, not 14.
const optionTakeAffineProgram = `import c counter: fn(U64) -> Unit

type Res {
    n: U64
}

impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}

type Holder {
    slot: Option(Res)
}

impl Holder {
    fn take_it(mut self) -> Option(Res) {
        return self.slot.take()
    }
}

fn drop_slot(value: Option(Res)) -> Unit {
    match value {
        Some(item) => { item.cleanup() }
        None => {}
    }
    return
}

impl Cleanup for Holder {
    fn cleanup(take self) -> Unit {
        drop_slot(self.slot)
        return
    }
}

fn take_param(mut holder: Holder) -> Option(Res) {
    return holder.slot.take()
}

fn bump(mut item: Res) -> Unit {
    item.n = item.n + 1
    return
}

fn make(n: U64) -> Res { return Res(n: n) }

fn main() -> I32 {
    using holder = Holder(slot: Some(make(7)))
    let taken = holder.take_it()
    match taken {
        Some(item) => {
            bump(item)
            if item.n != 8 { return 1 }
            item.cleanup()
        }
        None => { return 2 }
    }
    using holder2 = Holder(slot: Some(make(2)))
    let taken2 = take_param(holder2)
    match taken2 {
        Some(item) => {
            if item.n != 2 { return 3 }
            item.cleanup()
        }
        None => { return 4 }
    }
    return 0
}
`

const optionTakeDriver = `#include "alder_host.h"
#include <stdint.h>
static uint64_t g_count = 0;
void counter(uint64_t v) { g_count += v; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (g_count != 10) { return 98; }
    return result;
}
`

func TestOptionTakeProduction(t *testing.T) {
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

	scalarFiles := map[string]string{"option-take.al": optionTakeScalarProgram}
	if result := runPrivateProductionCompiler(t, exe, scalarFiles, "check", "option-take.al"); result.status != 0 || result.stderr != "" {
		t.Fatalf("option take check: %+v stderr=%s", result, result.stderr)
	}
	scalarC := runPrivateProductionCompiler(t, exe, scalarFiles, "compile", "--emit=c", "option-take.al")
	if scalarC.status != 0 || scalarC.stderr != "" {
		t.Fatalf("option take C: %+v stderr=%s", scalarC, scalarC.stderr)
	}
	compileAndRunProductionArtifact(t, cc, root, runtimeObject, scalarC.stdout, 0)

	affineFiles := map[string]string{"option-take-affine.al": optionTakeAffineProgram}
	affineC := runPrivateProductionCompiler(t, exe, affineFiles, "compile", "--emit=c", "option-take-affine.al")
	if affineC.status != 0 || affineC.stderr != "" {
		t.Fatalf("option take affine C: %+v stderr=%s", affineC, affineC.stderr)
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, affineC.stdout, optionTakeDriver, 0)

	mirText := runPrivateProductionCompiler(t, exe, affineFiles, "compile", "--emit=mir", "option-take-affine.al")
	if mirText.status != 0 || mirText.stderr != "" {
		t.Fatalf("option take MIR: %+v stderr=%s", mirText, mirText.stderr)
	}
	if got := strings.Count(mirText.stdout, "cleanup.disarm"); got != 0 {
		t.Fatalf("option take MIR carries %d cleanup disarms, want 0", got)
	}
	if !strings.Contains(mirText.stdout, "enum.construct") || !strings.Contains(mirText.stdout, "none") {
		t.Fatalf("option take MIR does not construct none:\n%s", mirText.stdout)
	}
	if !strings.Contains(mirText.stdout, "borrow_mut local %__alder_mut_binding_") {
		t.Fatalf("option take MIR does not materialize the match binding for the mut argument:\n%s", mirText.stdout)
	}
}

func TestOptionTakeRejections(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	cases := []struct {
		text string
		want string
	}{
		{"fn main() -> I32 {\n    let slot: Option(U64) = Some(1)\n    let taken = slot.take()\n    return 0\n}\n", "cannot assign to immutable binding"},
		{"fn pick() -> Option(U64) { return Some(1) }\nfn main() -> I32 {\n    let taken = pick().take()\n    return 0\n}\n", "Option.take requires a mutable place receiver"},
		{"type Res {\n    n: U64\n}\nimpl Cleanup for Res {\n    fn cleanup(take self) -> Unit { return }\n}\nfn bump(mut item: Res) -> Unit { item.n = item.n + 1\n    return }\nfn forward(item: Res) -> Unit {\n    bump(item)\n    return\n}\nfn main() -> I32 { return 0 }\n", "argument does not provide the parameter's required exclusive or owning access"},
	}
	for _, tc := range cases {
		result := runPrivateProductionCompiler(t, exe, map[string]string{"reject.al": tc.text}, "check", "reject.al")
		if result.status != 1 || !strings.Contains(result.stderr, tc.want) {
			t.Fatalf("option take rejection %q: %+v stderr=%s", tc.want, result, result.stderr)
		}
	}
}
