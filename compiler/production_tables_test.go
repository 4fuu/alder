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

const m75TableOwningProgram = `type Row {
    n: U64
    xs: Vec(U64)
}
fn main() -> I32 {
    using t = Table.new(Row)
    var a = Row(n: 1, xs: Vec.new(U64))
    a.xs.push(10)
    let first = t.insert(a)
    let second = t.insert(a)
    let n1 = match t.get(first) {
        Some(v) => v.n
        None => 0
    }
    let x1 = match t.get(first) {
        Some(v) => v.xs.len()
        None => 0
    }
    let n2 = match t.get(second) {
        Some(v) => v.n
        None => 0
    }
    if n1 != 1 { return 1 }
    if x1 != 1 { return 2 }
    if n2 != 1 { return 3 }
    a.n = 9
    a.xs.push(99)
    let n1b = match t.get(first) {
        Some(v) => v.n
        None => 0
    }
    let x1b = match t.get(first) {
        Some(v) => v.xs.len()
        None => 0
    }
    if n1b != 1 { return 4 }
    if x1b != 1 { return 5 }
    var filler = Vec.new(U64)
    var f: U64 = 0
    while f < 64 {
        filler.push(f * 3)
        f = f + 1
    }
    var i: U64 = 0
    var last = first
    while i < 3 {
        var r = Row(n: i + 2, xs: Vec.new(U64))
        r.xs.push(i * 10)
        last = t.insert(r)
        i = i + 1
    }
    let nlast = match t.get(last) {
        Some(v) => v.n
        None => 0
    }
    let xlast = match t.get(last) {
        Some(v) => v.xs.len()
        None => 0
    }
    if nlast != 4 { return 6 }
    if xlast != 1 { return 7 }
    let nfirst = match t.get(first) {
        Some(v) => v.n
        None => 0
    }
    if nfirst != 1 { return 8 }
    if filler.len() != 64 { return 9 }
    return 0
}
`

// m75TableOwningEscapeProgram pins that owning elements inserted in one
// function are still intact after the table crosses a take/return round trip
// and is read back in the caller: the element copies must live where the
// table lives, not in the inserting function's storage domain.
const m75TableOwningEscapeProgram = `type Row {
    n: U64
    xs: Vec(U64)
}
fn fill(take rows: Table(Row), n: U64) -> Table(Row) {
    var a = Row(n: n, xs: Vec.new(U64))
    a.xs.push(n * 2)
    let first = rows.insert(a)
    let second = rows.insert(a)
    return rows
}
fn main() -> I32 {
    let fresh = Table.new(Row)
    using rows = fill(fresh, 5)
    var a = Row(n: 50, xs: Vec.new(U64))
    a.xs.push(7)
    let id = rows.insert(a)
    let n1 = match rows.get(id) {
        Some(v) => v.n
        None => 0
    }
    let x1 = match rows.get(id) {
        Some(v) => v.xs.len()
        None => 0
    }
    if n1 != 50 { return 1 }
    if x1 != 1 { return 2 }
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
    using back = relay(r)
    if back.n != 7 { return 2 }
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
		{"m75-table-owning.al", m75TableOwningProgram},
		{"m75-table-owning-escape.al", m75TableOwningEscapeProgram},
		{"m75-cleanup-trait.al", m75CleanupTraitProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			repeat := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if repeat != mirText {
				t.Fatalf("%s MIR changed across processes", program.name)
			}
			cResult := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			cRepeat := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
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

// TestM75TableProductionSanitizers reruns the owning-element table programs
// under ASan/UBSan when the host toolchain supports them. An owning element
// whose internal storage died with the creating function is a use-after-free
// that strict C11 alone cannot see.
func TestM75TableProductionSanitizers(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	if !closureSanitizersSupported(t, cc) {
		t.Skip("ASan/UBSan not supported by this host toolchain")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	sanitizer := []string{"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer"}
	runtimeObject := filepath.Join(t.TempDir(), "alder-san.o")
	runtimeArgs := append(append([]string{}, strictC11Flags()...), sanitizer...)
	runtimeArgs = append(runtimeArgs, "-I", filepath.Join(root, "runtime", "c"),
		"-c", filepath.Join(root, "runtime", "c", "alder.c"), "-o", runtimeObject)
	if out, err := exec.Command(cc, runtimeArgs...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized runtime compile: %v\n%s", err, out)
	}

	const driverText = `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	for _, program := range []struct {
		name, source string
	}{
		{"m75-table-owning", m75TableOwningProgram},
		{"m75-table-owning-escape", m75TableOwningEscapeProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name + ".al": program.source}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name+".al")
			if cResult.status != 0 || cResult.stderr != "" {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			dir := t.TempDir()
			cfile := filepath.Join(dir, "program.c")
			driver := filepath.Join(dir, "driver.c")
			binary := filepath.Join(dir, "program")
			if err := os.WriteFile(cfile, []byte(cResult.stdout), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(driver, []byte(driverText), 0o644); err != nil {
				t.Fatal(err)
			}
			args := append(append([]string{}, strictC11Flags()...), sanitizer...)
			args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"),
				cfile, driver, runtimeObject, "-o", binary)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("%s sanitized generated C compile: %v\n%s", program.name, err, out)
			}
			cmd := exec.Command(binary)
			cmd.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=0")
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("%s sanitized run: %v\n%s", program.name, err, out)
			}
		})
	}
}

// m75TableTryInsertOkProgram pins the Ok edge: the insert succeeds, the
// returned id resolves through get, and the stored element is readable
// through the view (the view arm stores the field into an outer local because
// view arms admit only straight-line copy statements and expose field reads).
// It links the unlimited runtime with the plain driver.
const m75TableTryInsertOkProgram = `type Slot {
    n: U64
}
fn main() -> I32 {
    using players = Table.new(Slot)
    var seen: U64 = 0
    match players.try_insert(Slot(n: 41)) {
        Ok(id) => {
            match players.get(id) {
                Some(row) => { seen = row.n }
                None => { return 2 }
            }
        }
        Err(back) => { return 3 }
    }
    if seen != 41 { return 1 }
    return 0
}
`

// m75TableTryInsertErrOomProgram pins the Err edge for a heap-backed element:
// the driver makes the insert's slot-storage allocation fail deterministically
// (four allocations succeed first: the table slot array, the vector's two
// buffer allocations, and the element deep copy's buffer, which follows the
// infallible copy_to_domain termination contract), the insert reports Err instead
// of panicking, and the Err payload hands the vector back with its contents
// intact. The sum over
// the returned vector proves the payload carries the original bytes.
const m75TableTryInsertErrOomProgram = `fn main() -> I32 {
    using players = Table.new(Vec(U64))
    var overflow: Vec(U64) = Vec.new(U64)
    overflow.push(99)
    match players.try_insert(overflow) {
        Ok(id) => { return 2 }
        Err(back) => {
            var total: U64 = 0
            for item in back {
                total = total + item
            }
            if total != 99 { return 4 }
        }
    }
    return 0
}
`

// m75TableTryInsertErrCapProgram pins the capacity-policy Err edge: with the
// slot limit at the initial capacity, the ninth insert refuses to grow, the
// caller gets Err with the element value handed back, and the payload's field
// still matches the argument. A copyable record element is used because
// owning elements cannot be inserted repeatedly into one table until the
// pre-existing verifier gap is fixed.
const m75TableTryInsertErrCapProgram = `type Slot {
    n: U64
}
fn main() -> I32 {
    using players = Table.new(Slot)
    var round: U64 = 0
    while round < 8 {
        players.insert(Slot(n: round + 1))
        round = round + 1
    }
    match players.try_insert(Slot(n: 99)) {
        Ok(id) => { return 2 }
        Err(back) => {
            if back.n != 99 { return 4 }
        }
    }
    return 0
}
`

// m75TableTryInsertDefaultProgram pins the shipped default: without the test
// hook the table grows without bound, so every one of these try_inserts takes
// the Ok edge. It links the unlimited runtime with the plain driver.
const m75TableTryInsertDefaultProgram = `fn main() -> I32 {
    using players = Table.new(U64)
    var round: U64 = 0
    var inserted: U64 = 0
    while round < 64 {
        match players.try_insert(round) {
            Ok(id) => { inserted = inserted + 1 }
            Err(back) => { return 1 }
        }
        round = round + 1
    }
    if inserted != 64 { return 2 }
    return 0
}
`

// m75TableInsertAbortProgram pins the panic edge that try_insert deliberately
// does not take: plain insert past the slot limit still terminates the process,
// so the non-panicking form is an explicit caller choice, not a silent
// change of insert behavior.
const m75TableInsertAbortProgram = `fn main() -> I32 {
    using players = Table.new(U64)
    var round: U64 = 0
    while round < 9 {
        let id = players.insert(round)
        round = round + 1
    }
    return 0
}
`

// m75TableSlotLimitDriver is the custom C main for the slot-limit fixtures: it
// installs the cap and then hands control to the Alder entry point.
const m75TableSlotLimitDriver = `#include "alder_host.h"
#include "alder.h"
#include <stdint.h>
int main(void) {
	alder_runtime_test_set_table_slot_limit(8);
	int context = 0;
	return (int)alder_program_entry(&context);
}
`

// m75TableAllocFailDriver makes the fifth domain allocation fail, which in
// the Err-payload fixture is the insert's slot-storage allocation (the table
// slot array, the vector's two buffer allocations, and the element deep
// copy's buffer come first; the copy terminates on its own OOM per the
// copy_to_domain contract, so the fixture must exhaust past it). This is how
// the exhaustion-policy Err edge is reached without any earlier same-table
// insert.
const m75TableAllocFailDriver = `#include "alder_host.h"
#include "alder.h"
#include <stdint.h>
int main(void) {
	alder_runtime_test_fail_domain_alloc_after(4);
	int context = 0;
	return (int)alder_program_entry(&context);
}
`

func TestM75TableTryInsertProduction(t *testing.T) {
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
	testingObject := buildRuntimeObjectTesting(t, cc, root)

	for _, program := range []struct {
		name, text, driver string
		object             string
		want               int
	}{
		{"m75-table-try-insert-ok.al", m75TableTryInsertOkProgram, "", runtimeObject, 0},
		{"m75-table-try-insert-err-oom.al", m75TableTryInsertErrOomProgram, m75TableAllocFailDriver, testingObject, 0},
		{"m75-table-try-insert-err-cap.al", m75TableTryInsertErrCapProgram, m75TableSlotLimitDriver, testingObject, 0},
		{"m75-table-try-insert-default.al", m75TableTryInsertDefaultProgram, "", runtimeObject, 0},
		{"m75-table-insert-abort.al", m75TableInsertAbortProgram, m75TableSlotLimitDriver, testingObject, 101},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			assertPublicMIR(t, program.name, mirText.stdout)
			if strings.Contains(mirText.stdout, "__s0_") {
				t.Fatalf("%s generated MIR exposes bootstrap names", program.name)
			}
			if strings.HasPrefix(program.name, "m75-table-try-insert") &&
				!strings.Contains(mirText.stdout, "table.insert.try") {
				t.Fatalf("%s MIR does not lower try_insert to table.insert.try", program.name)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			if strings.Contains(cResult.stdout, "__s0_") {
				t.Fatalf("%s generated C exposes bootstrap names", program.name)
			}
			if program.driver == "" {
				compileAndRunProductionArtifact(t, cc, root, program.object, cResult.stdout, program.want)
			} else {
				compileAndRunProductionArtifactWithDriver(t, cc, root, program.object, cResult.stdout, program.driver, program.want, "-DALDER_RUNTIME_TESTING")
			}
		})
	}
}
