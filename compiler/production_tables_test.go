package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M7.5 table identity qualification: the ordinary public surface of Table(T),
// T.Id, and table views is compiled and run end to end through the Alder
// production driver on generated C. The programs avoid every private bootstrap
// name, so they compile without the private profile. They intentionally stay
// out of the Go-frontend oracle corpora: the Go checker has no table surface.

const m75TableProgram = `type Player {
    name: String
    age: U64
}
fn age_of(players: Table(Player), id: Player.Id) -> U64 {
    return match players.get(id) {
        Some(player) => player.age
        None => 0
    }
}
fn rename(mut players: Table(Player), id: Player.Id) -> Unit {
    match players.get_mut(id) {
        Some(player) => { player.age = 50 }
        None => {}
    }
    return
}
fn main() -> I32 {
    using players = Table.new(Player)
    let first = players.insert(Player(name: "a", age: 1))
    let second = players.insert(Player(name: "b", age: 2))
    if age_of(players, first) != 1 { return 1 }
    if age_of(players, second) != 2 { return 2 }
    rename(players, second)
    if age_of(players, second) != 50 { return 3 }
    if players.remove(first) { } else { return 4 }
    if age_of(players, first) != 0 { return 5 }
    let third = players.insert(Player(name: "c", age: 3))
    if age_of(players, first) != 0 { return 6 }
    if age_of(players, third) != 3 { return 7 }
    return 0
}
`

const m75TableTransferProgram = `fn move_out() -> Table(U64) {
    using fresh = Table.new(U64)
    return fresh
}
fn main() -> I32 {
    using owned = move_out()
    using players = Table.new(U64)
    let id = players.insert(4)
    if owned.remove(id) { return 1 }
    if players.remove(id) { } else { return 2 }
    if players.remove(id) { return 3 }
    return 0
}
`

const m75TableGenericProgram = `fn with_row(T: type, take players: Table(T), value: T) -> Table(T) {
    let id = players.insert(value)
    return players
}
type Row {
    n: U64
}
fn main() -> I32 {
    using rows = Table.new(Row)
    using cycled = with_row(Row, rows, Row(n: 1))
    return 0
}
`

const m75TableComposeProgram = `type Holder {
    table: Table(U64)
    n: U64
}
fn relay(take h: Holder) -> Holder { return h }
fn pass(take t: Table(U64)) -> Table(U64) { return t }
fn main() -> I32 {
    using t = Table.new(U64)
    let holder = Holder(table: t, n: 1)
    if relay(holder).n != 1 { return 1 }
    let u = Table.new(U64)
    let o: Option(Table(U64)) = Some(u)
    match o {
        Some(inside) => { pass(inside) }
        None => {}
    }
    return 0
}
`

const m75CleanupTraitProgram = `import c counter: fn(U64) -> Unit
type Res {
    n: U64
}
impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}
fn make(n: U64) -> Res { return Res(n: n) }
fn relay(take r: Res) -> Res { return r }
fn main() -> I32 {
    using r = make(7)
    relay(r)
    using late = make(9)
    if late.n != 9 { return 1 }
    return 0
}
`

// m75TableRejections pins the public-language rejection surface: overlapping
// table access, lookup misuse, view region violations, and the callback-free
// using form on a non-Table owner.
var m75TableRejections = []struct {
	name, source, want string
}{
	{
		"overlapping-insert",
		"fn f(mut t: Table(U64), id: U64.Id) -> Unit {\n    match t.get(id) {\n        Some(v) => { let fresh = t.insert(2) }\n        None => {}\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"overlapping table access",
	},
	{
		"lookup-discarded",
		"fn f(t: Table(U64), id: U64.Id) -> Unit { t.get(id) }\nfn main() -> I32 { return 0 }\n",
		"table lookup must be the scrutinee of a match",
	},
	{
		"lookup-bound",
		"fn f(t: Table(U64), id: U64.Id) -> Unit { let option = t.get(id) }\nfn main() -> I32 { return 0 }\n",
		"semantic error (checker diagnostic 104)",
	},
	{
		"view-control-flow",
		"fn f(t: Table(U64), id: U64.Id, flag: Bool) -> Unit {\n    match t.get(id) {\n        Some(v) => { if flag { let x = 1 } }\n        None => {}\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"straight-line copy statements",
	},
	{
		"using-non-cleanup-owner",
		"fn f() -> Unit { using value = 5 }\nfn main() -> I32 { return 0 }\n",
		"using requires an affine owner implementing Cleanup",
	},
	{
		"using-callback-gated",
		"fn close(v: I64) -> Unit { return }\nfn f() -> Unit { using h = 5 with close }\nfn main() -> I32 { return 0 }\n",
		"with-cleanup clause is private",
	},
	{
		"async-cleanup-removed",
		"type Res { n: U64 }\nimpl AsyncCleanup for Res {\n    fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit { using r = Res(n: 1) }\nfn main() -> I32 { return 0 }\n",
		"unknown trait",
	},
	{
		"untransferred-owner",
		"fn f() -> Unit { let t = Table.new(U64) }\nfn main() -> I32 { return 0 }\n",
		"affine owner reaches function exit",
	},
}

func TestM75TableProductionQualification(t *testing.T) {
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
	object, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)
	noGo := noGoEnv(t, cc)

	for _, program := range []struct {
		name, text string
	}{
		{"m75-tables.al", m75TableProgram},
		{"m75-table-transfer.al", m75TableTransferProgram},
		{"m75-table-generic.al", m75TableGenericProgram},
		{"m75-table-compose.al", m75TableComposeProgram},
		{"m75-cleanup-trait.al", m75CleanupTraitProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 5\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if repeat != mirText {
				t.Fatalf("%s MIR changed across processes", program.name)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			cRepeat := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cRepeat != cResult {
				t.Fatalf("%s C changed across processes", program.name)
			}
			assertPublicMIR(t, program.name, mirText.stdout)
			if strings.Contains(cResult.stdout, "__s0_") {
				t.Fatalf("%s generated C exposes bootstrap names", program.name)
			}
			if program.name == "m75-cleanup-trait.al" {
				// The cleanup hook is observed through the imported counter.
				const counterDriver = `#include "alder_host.h"
#include <stdint.h>
static uint64_t g_count = 0;
void counter(uint64_t v) { g_count += v; }
int main(void) {
	int context = 0;
	int result = (int)alder_program_entry(&context);
	if (g_count != 16) { return 98; }
	return result;
}
`
				compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, cResult.stdout, counterDriver, 0)
			} else {
				compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
			}
			_ = object
			_ = noGo
		})
	}

	for _, rejection := range m75TableRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "reject.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: status=%d stderr=%q", rejection.name, result.status, result.stderr)
			}
		})
	}
}
