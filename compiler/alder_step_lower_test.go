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
