package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The installed core.iter surface: the builtin IntoIterator path materializes
// SliceIter/VecIter, the adapters stay lazy, and the terminals consume a
// mutable cursor. Every acceptance program runs through the production driver;
// the adapter and terminal programs also rerun under ASan/UBSan.
func TestProductionCoreIterRuns(t *testing.T) {
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

	programs := []struct {
		name      string
		source    string
		sanitized bool
	}{
		{
			name: "builtin",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    values.push(3)

    let view = values.slice(0, 3)
    var slice_cursor = view.into_iterator()
    let first = slice_cursor.next()
    if first != Some(1) { return 1 }
    let second = slice_cursor.next()
    if second != Some(2) { return 2 }
    let rest = slice_cursor.to_vec()
    if rest.len() != 1 || rest[0] != 3 { return 3 }

    let whole = values.into_iterator().to_vec()
    if whole.len() != 3 { return 4 }
    if whole[0] != 1 || whole[1] != 2 || whole[2] != 3 { return 5 }
    return 0
}
`,
			sanitized: true,
		},
		{
			name: "adapters",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var source = Vec.new(U64)
    source.push(1)
    source.push(2)
    source.push(3)
    source.push(4)

    let offset: U64 = 10
    var mapped = iter.map(source.into_iterator(), fn(x: U64) => x + offset)
    let mapped_values = iter.to_vec(mapped)
    if mapped_values.len() != 4 { return 1 }
    if mapped_values[0] != 11 || mapped_values[3] != 14 { return 2 }

    var filtered = iter.filter(source.into_iterator(), fn(x: U64) => x % 2 == 0)
    let filtered_values = iter.to_vec(filtered)
    if filtered_values.len() != 2 { return 3 }
    if filtered_values[0] != 2 || filtered_values[1] != 4 { return 4 }

    var filtered_map = iter.filter_map(source.into_iterator(), fn(x: U64) -> Option(U64) {
        if x > 2 { return Some(x * 2) }
        return None
    })
    let filtered_map_values = iter.to_vec(filtered_map)
    if filtered_map_values.len() != 2 { return 5 }
    if filtered_map_values[0] != 6 || filtered_map_values[1] != 8 { return 6 }

    var enumerated = iter.enumerate(source.into_iterator())
    match enumerated.next() {
        Some(item) => {
            if item.index != 0 || item.value != 1 { return 7 }
        }
        None => { return 8 }
    }
    match enumerated.next() {
        Some(item) => {
            if item.index != 1 || item.value != 2 { return 9 }
        }
        None => { return 10 }
    }

    var taken = iter.take_count(source.into_iterator(), 2)
    let taken_values = iter.to_vec(taken)
    if taken_values.len() != 2 { return 11 }
    if taken_values[0] != 1 || taken_values[1] != 2 { return 12 }

    var skipped = iter.skip(source.into_iterator(), 2)
    let skipped_values = iter.to_vec(skipped)
    if skipped_values.len() != 2 { return 13 }
    if skipped_values[0] != 3 || skipped_values[1] != 4 { return 14 }

    var tail = Vec.new(U64)
    tail.push(5)
    tail.push(6)
    var chained = iter.chain(source.into_iterator(), tail.into_iterator())
    let chained_values = iter.to_vec(chained)
    if chained_values.len() != 6 { return 15 }
    if chained_values[0] != 1 || chained_values[4] != 5 || chained_values[5] != 6 { return 16 }

    var right = Vec.new(U64)
    right.push(7)
    right.push(8)
    var zipped = iter.zip(source.into_iterator(), right.into_iterator())
    match zipped.next() {
        Some(item) => {
            if item.first != 1 || item.second != 7 { return 17 }
        }
        None => { return 18 }
    }
    match zipped.next() {
        Some(item) => {
            if item.first != 2 || item.second != 8 { return 19 }
        }
        None => { return 20 }
    }
    match zipped.next() {
        Some(_) => { return 21 }
        None => {}
    }

    // zip stops at the shorter input in either direction.
    var short = Vec.new(U64)
    short.push(9)
    var left_long = iter.zip(source.into_iterator(), short.into_iterator())
    match left_long.next() {
        Some(item) => {
            if item.first != 1 || item.second != 9 { return 22 }
        }
        None => { return 23 }
    }
    match left_long.next() {
        Some(_) => { return 24 }
        None => {}
    }
    var right_long = iter.zip(short.into_iterator(), source.into_iterator())
    match right_long.next() {
        Some(item) => {
            if item.first != 9 || item.second != 1 { return 25 }
        }
        None => { return 26 }
    }
    match right_long.next() {
        Some(_) => { return 27 }
        None => {}
    }
    return 0
}
`,
			sanitized: true,
		},
		{
			name: "terminals",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var source = Vec.new(U64)
    source.push(1)
    source.push(2)
    source.push(3)
    source.push(4)

    var folded_cursor = source.into_iterator()
    let zero: U64 = 0
    let folded = iter.fold(folded_cursor, zero, fn(acc: U64, x: U64) => acc + x)
    if folded != 10 { return 1 }

    var each_cursor = source.into_iterator()
    iter.for_each(each_cursor, fn(x: U64) -> Unit { return })

    var count_cursor = source.into_iterator()
    if iter.count(count_cursor) != 4 { return 2 }

    var any_cursor = source.into_iterator()
    if !iter.any(any_cursor, fn(x: U64) => x == 3) { return 3 }
    var any_missing_cursor = source.into_iterator()
    if iter.any(any_missing_cursor, fn(x: U64) => x == 9) { return 4 }

    var all_cursor = source.into_iterator()
    if !iter.all(all_cursor, fn(x: U64) => x < 5) { return 5 }
    var all_failing_cursor = source.into_iterator()
    if iter.all(all_failing_cursor, fn(x: U64) => x < 4) { return 6 }

    var find_cursor = source.into_iterator()
    match iter.find(find_cursor, fn(x: U64) => x > 2) {
        Some(value) => { if value != 3 { return 7 } }
        None => { return 8 }
    }

    var position_cursor = source.into_iterator()
    match iter.position(position_cursor, fn(x: U64) => x == 4) {
        Some(position) => { if position != 3 { return 9 } }
        None => { return 10 }
    }

    var collected_cursor = source.into_iterator()
    let collected = iter.to_vec(collected_cursor)
    if collected.len() != 4 { return 11 }
    if collected[0] != 1 || collected[3] != 4 { return 12 }
    return 0
}
`,
			sanitized: true,
		},
		{
			name: "receivers",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var numbers: Array(U64, 3) = [3, 1, 2]
    var array_cursor = numbers.into_iterator()
    let from_array = iter.to_vec(array_cursor)
    if from_array.len() != 3 { return 1 }
    if from_array[0] != 3 || from_array[1] != 1 || from_array[2] != 2 { return 2 }

    var mutable_numbers: Array(U64, 3) = [4, 5, 6]
    var view = mutable_numbers.slice_mut(0, 3)
    var mut_cursor = view.into_iterator()
    let from_mut = iter.to_vec(mut_cursor)
    if from_mut.len() != 3 { return 3 }
    if from_mut[0] != 4 || from_mut[1] != 5 || from_mut[2] != 6 { return 4 }

    let bytes: Bytes = "\x00\x7f\xff"
    var bytes_cursor = bytes.into_iterator()
    let from_bytes = iter.to_vec(bytes_cursor)
    if from_bytes.len() != 3 { return 5 }
    if from_bytes[0] != 0 || from_bytes[1] != 127 || from_bytes[2] != 255 { return 6 }

    var map = Map.new(U64, U64)
    if !map.insert(7, 70) { return 7 }
    if !map.insert(9, 90) { return 8 }
    if !map.insert(11, 110) { return 9 }
    if map.insert(9, 95) { return 10 }
    var map_cursor = map.into_iterator()
    let entries = iter.to_vec(map_cursor)
    if entries.len() != 3 { return 11 }
    if entries[0].first != 7 || entries[0].second != 70 { return 12 }
    if entries[1].first != 9 || entries[1].second != 95 { return 13 }
    if entries[2].first != 11 || entries[2].second != 110 { return 14 }

    var set = Set.new(U64)
    if !set.insert(3) { return 15 }
    if !set.insert(5) { return 16 }
    if !set.insert(7) { return 17 }
    var set_cursor = set.into_iterator()
    let items = iter.to_vec(set_cursor)
    if items.len() != 3 { return 18 }
    if items[0] != 3 || items[1] != 5 || items[2] != 7 { return 19 }
    return 0
}
`,
		},
		{
			name: "view-materialization",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    var it = values.into_iterator()
    var at: U64 = 0
    while at < 64 {
        values.push(99)
        at = at + 1
    }
    let rest = iter.to_vec(it)
    if rest.len() != 2 { return 1 }
    if rest[0] != 1 || rest[1] != 2 { return 2 }
    return 0
}
`,
			sanitized: true,
		},
		{
			name: "generic-cursor",
			source: `module hello.main

import core.iter

fn drain(I: type(Iterator(U64)), mut iter: I) -> U64 {
    var total: U64 = 0
    var running = true
    while running {
        match iter.next() {
            Some(value) => { total = total + value }
            None => { running = false }
        }
    }
    return total
}

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    values.push(3)
    var cursor = values.into_iterator()
    if drain(cursor) != 6 { return 1 }

    // The parameter named iter above must not shadow the imported module in
    // a later function in the same source.
    var mapped = iter.map(values.into_iterator(), fn(x: U64) => x + 1)
    let mapped_values = iter.to_vec(mapped)
    if mapped_values.len() != 3 { return 2 }
    if mapped_values[0] != 2 || mapped_values[2] != 4 { return 3 }
    var count_cursor = values.into_iterator()
    if iter.count(count_cursor) != 3 { return 4 }
    return 0
}
`,
		},
	}

	for _, program := range programs {
		program := program
		t.Run(program.name, func(t *testing.T) {
			dir := t.TempDir()
			files := map[string]string{
				"alder.toml":  snapshotProjectManifest,
				"src/main.al": program.source,
			}
			run := runProductionCompilerEnv(t, exe, dir, env, files, "run")
			if run.status != 0 || run.stderr != "" {
				t.Fatalf("%s: %+v stderr=%s", program.name, run, run.stderr)
			}
			if program.sanitized {
				generated, err := filepath.Glob(filepath.Join(dir, "build", "*", "debug", "hello", "hello.c"))
				if err != nil || len(generated) != 1 {
					t.Fatalf("%s generated C: %v %v", program.name, generated, err)
				}
				cText, err := os.ReadFile(generated[0])
				if err != nil {
					t.Fatal(err)
				}
				runSanitizedGeneratedProgram(t, cc, repoRoot, string(cText))
			}
		})
	}
}

// A Unit-returning indirect call is droppable: it binds no MIR result, just
// like a direct Unit call. The checker accepts the call and the verifier must
// not require a result value for it.
func TestProductionUnitIndirectCallRuns(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	source := `module hello.main

fn apply(T: type, f: fn(T) -> Unit, x: T) -> Unit {
    f(x)
    return
}
fn ignore(x: U64) -> Unit { return }
pub fn main() -> I32 {
    apply(U64, ignore, 1)
    return 0
}
`
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(""), map[string]string{
		"alder.toml":  snapshotProjectManifest,
		"src/main.al": source,
	}, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("Unit indirect call: %+v stderr=%s", result, result.stderr)
	}
}

func TestProductionCoreIterRejections(t *testing.T) {
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
	cases := []struct {
		name, source, want string
	}{
		{
			name: "missing-module",
			source: `module hello.main

pub fn main() -> I32 {
    var values = Vec.new(U64)
    let it = values.slice(0, 0).into_iterator()
    return 0
}
`,
			want: "into_iterator requires the core.iter module: add import core.iter",
		},
		{
			name: "wrong-arity",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    let it = values.slice(0, 0).into_iterator(1)
    return 0
}
`,
			want: "into_iterator takes no arguments",
		},
		{
			name: "unsupported-receiver",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    let text = "abc"
    let it = text.into_iterator()
    return 0
}
`,
			want: "into_iterator is available on arrays, immutable slices, read-only MutSlice, Bytes, Vec, Map, and Set",
		},
		{
			name: "scoped-view-capture",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    let view = values.slice(0, 2)
    var mapped = iter.map(values.into_iterator(), fn(x: U64) => x + view[0])
    let out = iter.to_vec(mapped)
    if out.len() != 2 { return 1 }
    return 0
}
`,
			want: "closure captures a scoped capability and escapes",
		},
		{
			name: "affine-elements",
			source: `module hello.main

import core.iter

type Resource {
    value: U64
}

impl Cleanup for Resource {
    fn cleanup(take self) -> Unit { return }
}

pub fn main() -> I32 {
    var values = Vec.new(Resource)
    values.push(Resource(value: 1))
    let it = values.into_iterator()
    return 0
}
`,
			want: "affine",
		},
		{
			name: "map-storage-key",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var map = Map.new(String, U64)
    map.insert("a", 1)
    let it = map.into_iterator()
    return 0
}
`,
			want: "checker diagnostic 129",
		},
		{
			name: "map-storage-value",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var map = Map.new(U64, String)
    map.insert(1, "a")
    let it = map.into_iterator()
    return 0
}
`,
			want: "checker diagnostic 129",
		},
		{
			name: "set-storage-element",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var set = Set.new(String)
    set.insert("a")
    let it = set.into_iterator()
    return 0
}
`,
			want: "checker diagnostic 129",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  snapshotProjectManifest,
				"src/main.al": tc.source,
			}, "check")
			if result.status == 0 {
				t.Fatalf("%s accepted: %+v", tc.name, result)
			}
			if !strings.Contains(result.stderr, tc.want) {
				t.Fatalf("%s diagnostic = %q, want %q", tc.name, result.stderr, tc.want)
			}
		})
	}
}
