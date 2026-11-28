package compiler

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// The dual-instance fixture keeps run.Blocking direct and lowers run.TestIo
// and leaf.TestIo as a step chain. It is the smallest lockstep acceptance for
// the Alder-written splitter against both the Alder mirror and the Go verifier.
func runAlderStepSplitLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`,
		"step.al": `module step.main

import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn run(I: type(Io), io: I, n: U64) -> U64 {
    return leaf(io, n)
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = run(block, 41)
    let b = run(test, 41)
    if a != b { return 1 }
    return 0
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"std/io.al", "step.al"})
	second := runLowerCompiler(t, exe, files, []string{"step.al", "std/io.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("step-lowered MIR changed with source order")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse step MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify step MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	steps := 0
	for _, function := range module.Functions {
		if strings.HasPrefix(function.Name, "__alder_step.run.") {
			steps++
		}
	}
	if steps < 2 {
		t.Fatalf("step-lowered MIR has %d step functions, want the handoff chain\n%s", steps, first)
	}
	frames := 0
	for i := range module.Types {
		if strings.HasPrefix(module.Types[i].Name, "__alder_step.frame.") {
			frames++
		}
	}
	if frames < 2 {
		t.Fatalf("step-lowered MIR has %d frame types, want the handoff chain\n%s", frames, first)
	}
	checkLowerGolden(t, "step-dual.mir", first)
}

func runAlderStepFailureEdgeConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io
pub trait Io {}
pub trait BlockingIo {}
pub trait AsyncIo {}
`,
		"edge.al": `import std.io { AsyncIo, Io }

type Evented {}
impl Io for Evented {}
impl AsyncIo for Evented {}

fn before(n: U64) -> U64 { return n + 1 }
fn earlier(n: U64) -> U64 { return before(n) + 2 }

fn leaf(I: type(Io), io: I, n: U64) -> U64 { return earlier(n) }

fn late(I: type(Io), io: I, n: U64) -> U64 {
    if n == 5 { return "a".concat("bc").len() }
    return leaf(io, n)
}

pub fn main() -> I32 {
    let io = Evented()
    return late(io, 2).to_i32_wrapping()
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "edge.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse late step MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify late step MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	for _, function := range module.Functions {
		if !strings.HasPrefix(function.Name, "__alder_step.run.late") {
			continue
		}
		for _, block := range function.Blocks {
			for _, instr := range block.Instrs {
				if instr.Op == mir.OpStrConcat {
					if instr.FailTarget == mir.NoBlock || function.Blocks[instr.FailTarget].Term.Kind != mir.TermPanic {
						t.Fatalf("cloned str.concat does not target the cloned panic block\n%s", out)
					}
					return
				}
			}
		}
	}
	t.Fatalf("missing str.concat in the late step\n%s", out)
}

func TestAlderStepSharedPanic(t *testing.T) {
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
	files := map[string]string{
		"shared-panic.al": `import c "fixture_timer.h" as rt {
    raw fn park = "alder_task_park"() -> Unit
}

fn wait(n: U64) -> U64 {
    unsafe c { rt.park() }
    return n
}

pub fn main() -> I32 {
    let label = "".concat("a")
    let index = wait(label.len())
    var bytes: Array(U8, 3) = [1, 5, 7]
    let length = bytes.slice_mut(0, index).len()
    let n = wait(length)
    return (n + bytes[index].to_u64()).to_i32_wrapping()
}
`,
	}
	result := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "shared-panic.al")
	if result.status != 0 {
		t.Fatalf("emit shared panic MIR: status %d\n%s", result.status, result.stderr)
	}
	out := result.stdout
	module, err := mir.Parse(out)
	if err != nil {
		t.Fatalf("parse shared panic MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify shared panic MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	for _, function := range module.Functions {
		if function.Name != "__alder_step.run.main" {
			continue
		}
		for _, panicBlock := range function.Blocks {
			if panicBlock.Term.Kind != mir.TermPanic || len(panicBlock.Params) != 1 {
				continue
			}
			seen := map[mir.OpKind]mir.ValueId{}
			for _, block := range function.Blocks {
				for _, instr := range block.Instrs {
					if instr.FailTarget != mir.NoBlock && function.Blocks[instr.FailTarget] == panicBlock && len(instr.FailArgs) == 1 {
						seen[instr.Op] = instr.FailArgs[0]
					}
				}
			}
			slice, hasSlice := seen[mir.OpSliceRangeChecked]
			index, hasIndex := seen[mir.OpArrayIndexChecked]
			add, hasAdd := seen[mir.OpIntAddChecked]
			if hasSlice && hasIndex && hasAdd && slice != index && add == index {
				return
			}
		}
	}
	t.Fatalf("no shared panic with distinct edge domain arguments\n%s", out)
}

func runAlderStepSpawnLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io
pub trait Io {}
pub trait BlockingIo {}
pub trait AsyncIo {}
`,
		"std/task.al": `module std.task
import std.io { AsyncIo, Io }
pub type Pending(T: type) {}
pub type Task(T: type) { child: U64
    out_offset: U64 }
pub type TaskGroup(I: type(Io, AsyncIo)) {
    capability: I
    group: U64
}
impl(I: type(Io, AsyncIo)) TaskGroup(I) {
    fn new(io: I) -> TaskGroup(I) { return TaskGroup(capability: io, group: 37) }
    fn spawn(T: type, mut self, pending: Pending(T)) -> Task(T) { return Task(child: 0, out_offset: 0) }
    fn start(mut self, pending: Pending(Unit)) -> Unit { return }
}
impl(I: type(Io, AsyncIo)) Cleanup for TaskGroup(I) {
    fn cleanup(take self) -> Unit { return }
}
`,
		"spawn.al": `import std.io { AsyncIo, Io }
import std.task { TaskGroup }
type Evented {}
impl Io for Evented {}
impl AsyncIo for Evented {}
fn counted(first: U64, second: U64) -> U64 { return first - second }
fn note(n: U64) -> Unit { return }
fn parent(io: Evented) -> Unit {
    using tasks = TaskGroup.new(io)
    let child = tasks.spawn(counted(83, 19))
    tasks.start(note(57))
    return
}
pub fn main() -> I32 {
    let io = Evented()
    parent(io)
    return 0
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "std/task.al", "spawn.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse spawn MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify spawn MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	if module.FormatVersion != mir.TaskFormatVersion {
		t.Fatalf("spawn MIR version = %d, want %d", module.FormatVersion, mir.TaskFormatVersion)
	}
	constants := make(map[string]int64)
	for _, constant := range module.Constants {
		if constant.Value.Kind == mir.ConstInt {
			constants[constant.Name] = constant.Value.Int
		}
	}
	var targets []string
	for _, function := range module.Functions {
		for _, block := range function.Blocks {
			for i, instr := range block.Instrs {
				if instr.Op == mir.OpTaskSpawn {
					if !strings.HasPrefix(function.Name, "__alder_step.run.parent") {
						t.Fatalf("task.spawn emitted outside parent step: %s", function.Name)
					}
					target := module.Functions[instr.Callee].Name
					targets = append(targets, target)
					want := []int64{57}
					if strings.HasPrefix(target, "__alder_step.run.counted") {
						want = []int64{83, 19}
					}
					initialized := make(map[string]mir.Instr)
					for _, prior := range block.Instrs[:i] {
						if prior.Op == mir.OpStore && prior.Place.Kind == mir.PlaceField && prior.Place.Base.Kind == mir.PlaceDeref && prior.Place.Base.Deref == instr.B {
							def := function.Values[prior.StoreVal].Def
							initialized[prior.Place.Field] = function.Blocks[def.Block].Instrs[def.Instr]
						}
					}
					if entry := initialized["state"]; entry.Op != mir.OpEnumConstruct || entry.Variant != "entry" {
						t.Fatalf("child %s was not initialized to entry before spawn", target)
					}
					for j, value := range want {
						field := "p" + strconv.Itoa(j)
						got := initialized[field]
						if got.Op != mir.OpConstGet || constants[got.Const] != value {
							t.Fatalf("child %s field %s did not receive %d before spawn", target, field, value)
						}
					}
				}
			}
		}
	}
	if len(targets) != 2 || !strings.HasPrefix(targets[0], "__alder_step.run.counted") || !strings.HasPrefix(targets[1], "__alder_step.run.note") {
		t.Fatalf("expected inline spawn and start, got %v\n%s", targets, out)
	}
}

func runAlderRecursiveStepLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`,
		"recursive.al": `module step.recursive

import std.io { AsyncIo, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn down(I: type(Io), io: I, n: U64) -> U64 {
    if n == 0 { return 0 }
    return down(io, n - 1)
}

pub fn main() -> I32 {
    let test = TestIo()
    if down(test, 3) != 0 { return 1 }
    return 0
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "recursive.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse recursive step MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify recursive step MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	found := false
	for i := range module.Types {
		typ := &module.Types[i]
		if !strings.HasPrefix(typ.Name, "__alder_step.frame.") {
			continue
		}
		for _, field := range typ.Fields {
			if module.ValidType(field.Type) && module.Types[field.Type].Kind == mir.TypeSafeMut && module.Types[field.Type].Elem == mir.TypeId(i) {
				found = true
			}
		}
	}
	if !found {
		t.Fatalf("recursive step MIR has no self-referential frame\n%s", out)
	}
	checkLowerGolden(t, "step-recursive.mir", out)
}

func runAlderStepManyLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`,
		"many.al": `module step.many

import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn chain(I: type(Io), io: I, n: U64) -> U64 {
    let a = leaf(io, n)
    let b = leaf(io, a)
    return leaf(io, b)
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = chain(block, 40)
    let b = chain(test, 40)
    if a != 43 { return 1 }
    if b != a { return 2 }
    return 0
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "many.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse many-point step MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify many-point step MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	steps := 0
	for _, function := range module.Functions {
		if strings.HasPrefix(function.Name, "__alder_step.run.chain") {
			steps++
		}
	}
	if steps != 1 {
		t.Fatalf("many-point MIR has %d chain step functions, want 1\n%s", steps, out)
	}
	checkLowerGolden(t, "step-many.mir", out)
}

func runAlderStepBranchLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`,
		"branch.al": `import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn choose(I: type(Io), io: I, n: U64) -> U64 {
    let a = leaf(io, n)
    var x: U64 = 0
    if a == 41 {
        x = leaf(io, a)
    } else {
        x = leaf(io, a + 1)
    }
    return leaf(io, x)
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = choose(block, 40)
    let b = choose(test, 40)
    if a != b { return 1 }
    if a != 43 { return 2 }
    let c = choose(block, 39)
    let d = choose(test, 39)
    if c != d { return 3 }
    if c != 43 { return 4 }
    return 0
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "branch.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse branch step MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify branch step MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	checkLowerGolden(t, "step-branch.mir", out)
}

func runAlderStepCleanupLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`,
		"cleanup.al": `module step.cleanup

import std.io { AsyncIo, Blocking, Io }

type Res {
    id: U64
}

impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        return
    }
}

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn work(I: type(Io), io: I, n: U64) -> U64 {
    let r = Res(id: n)
    using held = r
    let a = leaf(io, n)
    let b = leaf(io, a)
    return b
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = work(block, 40)
    let b = work(test, 40)
    if a != b { return 1 }
    if a != 42 { return 2 }
    return 0
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "cleanup.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse cleanup step MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify cleanup step MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	checkLowerGolden(t, "step-cleanup.mir", out)
}

func runAlderStepCleanupCursorLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`,
		"cleanup-cursor.al": `module step.cleanup.cursor

import std.io { AsyncIo, Blocking, Io }

type Res {
    id: U64
}

impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        let io = TestIo()
        let x = leaf(io, 1)
        return
    }
}

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn work(I: type(Io), io: I, n: U64) -> U64 {
    let r = Res(id: n)
    using held = r
    let a = leaf(io, n)
    return a
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = work(block, 40)
    let b = work(test, 40)
    if a != b { return 1 }
    if a != 41 { return 2 }
    return 0
}
`,
	}
	out := runLowerCompiler(t, exe, files, []string{"std/io.al", "cleanup-cursor.al"})
	module, err := mir.Parse(string(out))
	if err != nil {
		t.Fatalf("parse cleanup cursor step MIR: %v\n%s", err, out)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify cleanup cursor step MIR: %s\n%s", verify.Errors(diagnostics), out)
	}
	has_cleanup := false
	for _, function := range module.Functions {
		if strings.HasPrefix(function.Name, "__alder_step.run.cleanup") {
			has_cleanup = true
		}
	}
	if !has_cleanup {
		t.Fatalf("cleanup cursor MIR has no cleanup step function\n%s", out)
	}
	checkLowerGolden(t, "step-cleanup-cursor.mir", out)
}
