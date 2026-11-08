package compiler

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M7.5 cleanup inside loops: a `using` registration in a loop body runs at the
// end of that iteration's scope, and every exit from the iteration runs the
// registrations it crosses in reverse order exactly once: fallthrough, `break`,
// `continue`, `return`, and a failed `try`. A nested loop and a match arm keep
// the same order, and a registered vector drains its elements per iteration.
//
// Every program observes cleanup through an imported counter, so a missing or
// duplicated run changes the total instead of only the exit path.

// m75UsingLoopPrelude declares the counted owner and the marking helper the
// loop programs share.
const m75UsingLoopPrelude = `import c counter: fn(U64) -> Unit
type Res {
    n: U64
}
impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}
fn mark(n: U64) -> Unit {
    unsafe c { counter(n) }
    return
}
`

// m75UsingLoopDriver counts the counter calls and compares the total with the
// value the program's shape requires.
func m75UsingLoopDriver(want int) string {
	return fmt.Sprintf(`#include <stdint.h>
static uint64_t g_count = 0;
void counter(uint64_t v) { g_count += v; }
uint64_t alder_program_entry(uint64_t *c);
int main(void) {
	int context = 0;
	int result = (int)alder_program_entry((uint64_t *)&context);
	if (result != 0) { return result; }
	if (g_count != %d) { return 98; }
	return 0;
}
`, want)
}

var m75UsingLoopPrograms = []struct {
	name string
	want int
	body string
}{
	{
		// Three iterations register 0, 1, and 2 and mark 100 each.
		"fallthrough",
		303,
		`fn main() -> I32 {
    var i: U64 = 0
    while i < 3 {
        using r = Res(n: i)
        mark(100)
        i = i + 1
    }
    return 0
}
`,
	},
	{
		// The break in iteration 2 still runs that iteration's registration.
		"break",
		303,
		`fn main() -> I32 {
    var i: U64 = 0
    while i < 5 {
        using r = Res(n: i)
        mark(100)
        if i == 2 { break }
        i = i + 1
    }
    return 0
}
`,
	},
	{
		// The continue in iteration 1 runs its registration and skips the mark.
		"continue",
		203,
		`fn main() -> I32 {
    var i: U64 = 0
    while i < 3 {
        using r = Res(n: i)
        i = i + 1
        if i == 2 { continue }
        mark(100)
    }
    return 0
}
`,
	},
	{
		// The return in iteration 1 runs that registration before leaving.
		"return",
		201,
		`fn run() -> U64 {
    var i: U64 = 0
    while i < 5 {
        using r = Res(n: i)
        mark(100)
        if i == 1 { return 7 }
        i = i + 1
    }
    return 0
}
fn main() -> I32 {
    if run() != 7 { return 1 }
    return 0
}
`,
	},
	{
		// The failing try in iteration 1 runs that registration on the way out.
		"try",
		201,
		`fn step(i: U64) -> Result(U64, U64) {
    if i == 1 { return Err(i) }
    return Ok(i)
}
fn run() -> Result(U64, U64) {
    var i: U64 = 0
    while i < 3 {
        using r = Res(n: i)
        mark(100)
        let v = try step(i)
        i = i + 1
    }
    return Ok(0)
}
fn main() -> I32 {
    match run() {
        Ok(v) => { return 1 }
        Err(e) => { if e != 1 { return 2 } }
    }
    return 0
}
`,
	},
	{
		// Both loops register: the inner one per inner iteration, the outer one
		// per outer iteration.
		"nested",
		31,
		`fn main() -> I32 {
    let ten: U64 = 10
    let two: U64 = 2
    var i: U64 = 0
    while i < 2 {
        using outer = Res(n: ten + i)
        var j: U64 = 0
        while j < 2 {
            using inner = Res(n: i * two + j)
            mark(1)
            j = j + 1
        }
        i = i + 1
    }
    return 0
}
`,
	},
	{
		// A registered vector drains its elements at the end of each iteration.
		"vec-drain",
		39,
		`fn main() -> I32 {
    let ten: U64 = 10
    var i: U64 = 0
    while i < 3 {
        let items = Vec.new(Res)
        items.push(Res(n: i))
        items.push(Res(n: ten + i))
        using drained = items
        mark(1)
        i = i + 1
    }
    return 0
}
`,
	},
	{
		// A `for` body registers per element, and `continue` still runs the
		// registration before the step block advances the index.
		"for-loop",
		203,
		`fn main() -> I32 {
    var items = Vec.new(U64)
    items.push(0)
    items.push(1)
    items.push(2)
    for x in items {
        using r = Res(n: x)
        if x == 1 { continue }
        mark(100)
    }
    return 0
}
`,
	},
	{
		// A registration inside a match arm runs at the arm's exit, and a break
		// from an arm still runs it.
		"match-arms",
		42,
		`enum Kind {
    A
    B
}
fn pick(n: U64) -> Kind {
    if n == 0 { return A }
    return B
}
fn main() -> I32 {
    var i: U64 = 0
    while i < 2 {
        match pick(i) {
            A => {
                using inner = Res(n: 5)
                mark(10)
            }
            B => {
                using inner = Res(n: 7)
                mark(20)
                break
            }
        }
        i = i + 1
    }
    return 0
}
`,
	},
}

func TestM75UsingLoopQualification(t *testing.T) {
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

	for _, program := range m75UsingLoopPrograms {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			name := "using-loop-" + program.name + ".al"
			files := map[string]string{name: m75UsingLoopPrelude + program.body}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 5\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", name, mirText, mirText.stderr)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", name, cResult, cResult.stderr)
			}
			compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, cResult.stdout, m75UsingLoopDriver(program.want), 0)
		})
	}
}
