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
    if left[0] != 227 { return 11 }
    if left[1] != 107 { return 12 }
    if left[2] != 71 { return 13 }
    if left[3] != 76 { return 14 }
    if left[4] != 54 { return 15 }
    if left[5] != 169 { return 16 }
    if left[6] != 243 { return 17 }
    if left[7] != 66 { return 18 }

    var tailer = random.Rng.seeded(1234)
    var bag: Array(U8, 21) = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let view = bag.slice_mut(0, 21)
    tailer.fill(view)
    if view[0] != 219 { return 19 }
    if view[1] != 28 { return 20 }
    if view[2] != 24 { return 21 }
    if view[3] != 47 { return 22 }
    if view[4] != 27 { return 23 }
    if view[5] != 246 { return 24 }
    if view[6] != 12 { return 25 }
    if view[7] != 187 { return 26 }
    if view[8] != 36 { return 27 }
    if view[9] != 101 { return 28 }
    if view[10] != 240 { return 29 }
    if view[11] != 77 { return 30 }
    if view[12] != 54 { return 31 }
    if view[13] != 161 { return 32 }
    if view[14] != 199 { return 33 }
    if view[15] != 151 { return 34 }
    if view[16] != 218 { return 35 }
    if view[17] != 37 { return 36 }
    if view[18] != 192 { return 37 }
    if view[19] != 155 { return 38 }
    if view[20] != 228 { return 39 }

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
			"os-form-not-landed",
			`module hello.main

import std.random

pub fn main() -> I32 {
    random.fill(0)
    return 0
}
`,
			`unknown name "random.fill"`,
		},
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
