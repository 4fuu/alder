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

pub type Bucket {
    values: Array(U64, 3)
}

pub fn query(T: type) -> U64 {
    return size_of(T) + align_of(T)
}

pub fn array_query(T: type) -> U64 {
    return size_of(Array(T, 3)) + align_of(Array(T, 3))
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
    // The target C compiler answers for the lowered array wrapper. A
    // zero-length Alder array occupies one element in C because native C
    // arrays cannot have length zero.
    if size_of(Array(U64, 3)) != 24 { return 19 }
    if align_of(Array(U64, 3)) != 8 { return 20 }
    if size_of(Array(U64, 0)) != 8 { return 21 }
    if align_of(Array(U64, 0)) != 8 { return 22 }
    if size_of(Array(Bool, 2)) != 2 { return 23 }
    if align_of(Array(Bool, 2)) != 1 { return 24 }
    if size_of(Array(Array(U64, 2), 2)) != 32 { return 25 }
    if align_of(Array(Array(U64, 2), 2)) != 8 { return 26 }
    if size_of(Option(Array(U64, 3))) != 32 { return 27 }
    if align_of(Option(Array(U64, 3))) != 8 { return 28 }
    if size_of(Result(Array(U64, 2), U8)) != 24 { return 29 }
    if align_of(Result(Array(U64, 2), U8)) != 8 { return 30 }
    if query(Array(U64, 3)) != 32 { return 31 }
    if size_of(Bucket) != 24 { return 32 }
    if align_of(Bucket) != 8 { return 33 }
    if array_query(U64) != 32 { return 34 }
    if array_query(Bool) != 4 { return 35 }
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
	{
		"array-element-not-type",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(7, 2)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-unresolved-element",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(Missing, 2)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-nested-unresolved-element",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Option(Array(Missing, 2))).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-missing-length",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(U64)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-extra-operand",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(U64, 2, 3)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-non-integer-length",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(U64, U8)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-negative-length",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(U64, -1)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-overflow-length",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(U64, 18446744073709551616)).to_i32()
}
`,
		"size_of and align_of require exactly one concrete type argument",
	},
	{
		"array-length-expression",
		coreMemoryRejectPrelude + `pub fn main() -> I32 {
    return size_of(Array(U64, 1 + 2)).to_i32()
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
