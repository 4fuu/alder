package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// std.random lands its seeded-generator half through the installed sysroot.
// The vectors are independently computed SplitMix64 outputs for the stated
// seeds: draws, unbiased range sums, 32-bit high words, byte fills across the
// eight-byte boundary, and value-semantics copies.
func TestProductionStdRandomRngRuns(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.random

pub fn main() -> I32 {
    var rng = random.Rng.seeded(42)
    let first = rng.next_u64()
    let second = rng.next_u64()
    if first != 13679457532755275413 { return 1 }
    if second != 2949826092126892291 { return 2 }

    var twin = random.Rng.seeded(42)
    if twin.next_u64() != first { return 3 }
    var other = random.Rng.seeded(43)
    if other.next_u64() == first { return 4 }

    var dice = random.Rng.seeded(7)
    var rolls: U64 = 0
    var at: U64 = 0
    while at < 20 {
        let roll = dice.range_u64(1, 7)
        if roll < 1 || roll > 6 { return 5 }
        rolls = rolls + roll
        at = at + 1
    }
    if rolls != 71 { return 6 }

    var small = random.Rng.seeded(42)
    let low_a = small.next_u32()
    let low_b = small.next_u32()
    if low_a != (first >> 32).to_u32_wrapping() { return 7 }
    if low_b != (second >> 32).to_u32_wrapping() { return 8 }

    var bounded = random.Rng.seeded(5)
    var hits: U64 = 0
    var index: U64 = 0
    while index < 3 {
        let drawn = bounded.range_u32(0, 5)
        if drawn > 4 { return 9 }
        hits = hits + drawn.to_u64()
        index = index + 1
    }
    if hits != 8 { return 10 }

    var filler = random.Rng.seeded(99)
    var source: Array(U8, 8) = [0, 0, 0, 0, 0, 0, 0, 0]
    let left = source.slice_mut(0, 8)
    filler.fill(left)
    var expected8: Array(U8, 8) = [227, 107, 71, 76, 54, 169, 243, 66]
    var first_index: U64 = 0
    while first_index < 8 {
        if left[first_index] != expected8[first_index] { return 11 }
        first_index = first_index + 1
    }

    var tailer = random.Rng.seeded(1234)
    var bag: Array(U8, 21) = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let view = bag.slice_mut(0, 21)
    tailer.fill(view)
    var expected21: Array(U8, 21) = [219, 28, 24, 47, 27, 246, 12, 187, 36, 101, 240, 77, 54, 161, 199, 151, 218, 37, 192, 155, 228]
    var second_index: U64 = 0
    while second_index < 21 {
        if view[second_index] != expected21[second_index] { return 12 }
        second_index = second_index + 1
    }

    var keeper = random.Rng.seeded(42)
    if keeper.next_u64() != first { return 40 }
    var copy = keeper
    if copy.next_u64() != second { return 41 }
    if keeper.next_u64() != second { return 42 }
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("std.random Rng behavior failed: %+v", result)
	}

	rejections := []struct {
		name, source, want string
	}{
		{
			"seeded-arity",
			`module hello.main

import std.random

pub fn main() -> I32 {
    let rng = random.Rng.seeded()
    return 0
}
`,
			"checker diagnostic 41",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			rejectFiles := map[string]string{
				"alder.toml":  files["alder.toml"],
				"src/main.al": rejection.source,
			}
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, rejectFiles, "run")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}

// The OS forms go through the installed sysroot and the Blocking capability.
// Values are unpredictable, so the checks are shape-only: fill must write
// bytes, every range draw stays in bounds, and a run of draws is not a
// constant. The same generated program runs again under ASan/UBSan.
func TestProductionStdRandomOsRuns(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))
	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.io { Blocking }
import std.random

pub fn main() -> I32 {
    let io = Blocking()
    var bytes: Array(U8, 32) = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    random.fill(io, bytes.slice_mut(0, 32))
    var any = false
    var at: U64 = 0
    while at < 32 {
        if bytes[at] != 0 { any = true }
        at = at + 1
    }
    if !any { return 1 }

    let first = random.range_u64(io, 11, 17)
    if first < 11 || first >= 17 { return 2 }
    var same: U64 = 0
    var drawn: U64 = 0
    while drawn < 64 {
        let one = random.u64(io)
        let small = random.u32(io)
        let in64 = random.range_u64(io, 11, 17)
        if in64 < 11 || in64 >= 17 { return 3 }
        if in64 == first { same = same + 1 }
        let in32 = random.range_u32(io, 3, 5)
        if in32 < 3 || in32 >= 5 { return 4 }
        drawn = drawn + 1
    }
    if same == 64 { return 5 }
    return 0
}
`,
	}
	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, files, "run")
	if run != (productionResult{}) {
		t.Fatalf("std.random OS behavior failed: %+v", run)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
