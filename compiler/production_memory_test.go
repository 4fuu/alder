package compiler

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// core.memory answers the target C compiler's size and alignment for the
// lowered representation of one concrete type. Unit is the fixed exception:
// size 0 and alignment 1. Generic code forwards its own type parameter, so the
// query must resolve after monomorphization rather than at declaration time.
const coreMemoryProgram = `module hello.main

import core.memory { size_of, align_of }

pub type Pair {
    a: U8
    b: U64
}

pub enum Choice {
    None
    Some(value: U64)
}

pub type Triple {
    a: U64
    b: U64
    c: U64
}

pub fn query(T: type) -> U64 {
    return size_of(T) + align_of(T)
}

pub fn main() -> I32 {
    if size_of(Unit) != 0 { return 1 }
    if align_of(Unit) != 1 { return 2 }
    if size_of(U8) != 1 { return 3 }
    if size_of(U16) != 2 { return 4 }
    if size_of(U32) != 4 { return 5 }
    if size_of(U64) != 8 { return 6 }
    if size_of(I64) != 8 { return 7 }
    if align_of(U64) != 8 { return 8 }
    if size_of(Pair) != 16 { return 9 }
    if align_of(Pair) != 8 { return 10 }
    if size_of(Choice) != 16 { return 11 }
    if size_of(String) != 16 { return 12 }
    if size_of(Bytes) != 16 { return 13 }
    if size_of(Option(U64)) != 16 { return 14 }
    if size_of(Result(U64, U64)) != 16 { return 15 }
    if size_of(Triple) != 24 { return 18 }
    if query(Pair) != 24 { return 16 }
    if query(Unit) != 1 { return 17 }
    return 0
}
`

const coreMemoryRejectPrelude = `module hello.main

import core.memory { size_of, align_of }

`

var coreMemoryRejections = []struct {
	name, source, want string
}{
	{
		"value-argument",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(7).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"missing-argument",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of().to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"extra-argument",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return align_of(U8, U16).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
}

func TestCoreMemoryProductionQualification(t *testing.T) {
	t.Parallel()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, "cc", root)
	files := map[string]string{
		"alder.toml":  snapshotProjectManifest,
		"src/main.al": coreMemoryProgram,
	}
	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(root, "sysroot")), files, "run")
	if run.status != 0 {
		t.Fatalf("core.memory program failed: %+v", run)
	}
	generated, err := filepath.Glob(filepath.Join(dir, "build", "*", "debug", "hello", "hello.c"))
	if err != nil || len(generated) != 1 {
		t.Fatalf("core.memory generated C: %v %v", generated, err)
	}
	cText, err := os.ReadFile(generated[0])
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(cText), "sizeof(uint64_t)") || !strings.Contains(string(cText), "_Alignof(uint64_t)") {
		t.Fatalf("core.memory C output has no target sizeof/_Alignof:\n%s", cText)
	}
}

func TestCoreMemoryRejections(t *testing.T) {
	t.Parallel()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, "cc", root)
	for _, rejection := range coreMemoryRejections {
		rejection := rejection
		t.Run(rejection.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(root, "sysroot")), map[string]string{
				"alder.toml":  snapshotProjectManifest,
				"src/main.al": rejection.source,
			}, "check")
			if result.status != 1 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("core.memory rejection: %+v", result)
			}
		})
	}
}
