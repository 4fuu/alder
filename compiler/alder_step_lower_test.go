package compiler

import (
	"bytes"
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
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
}

impl BlockingIo for Blocking {
}
`,
		"step.al": `module step.main

import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
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

func runAlderRecursiveStepLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"private.marker": "Map(\n",
		"std/io.al": `module std.io

pub trait Io {
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
}

impl BlockingIo for Blocking {
}
`,
		"recursive.al": `module step.recursive

import std.io { AsyncIo, Io }

type TestIo {
}

impl Io for TestIo {
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
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
}

impl BlockingIo for Blocking {
}
`,
		"many.al": `module step.many

import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
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
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
}

impl BlockingIo for Blocking {
}
`,
		"branch.al": `import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
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
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
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
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
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
