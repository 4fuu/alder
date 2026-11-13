package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The SipHash-1-3 vectors are the standard key bytes 00..0f and messages
// 00..i-1, published by the independent go-sip13 implementation. The
// structural checks then require `hash` to agree with the public Hasher over
// the same canonical byte stream.
const coreHashProgram = `module hello.main

import core.hash { hash, hash_with, Hasher, RandomState }
import std.io { Blocking }
import std.random

pub type Pair {
    a: U8
    b: U64
}

pub enum Choice {
    None
    Some(value: U64)
}

fn manual_pair(value: Pair) -> U64 {
    var h = RandomState.from_words(0, 0).hasher()
    h.write_u8(value.a)
    h.write_u64(value.b)
    return h.finish()
}

fn manual_choice() -> U64 {
    var h = RandomState.from_words(0, 0).hasher()
    h.write_u64(1)
    h.write_u64(7)
    return h.finish()
}

fn manual_option() -> U64 {
    var h = RandomState.from_words(0, 0).hasher()
    h.write_u8(1)
    h.write_u64(7)
    return h.finish()
}

fn manual_result() -> U64 {
    var h = RandomState.from_words(0, 0).hasher()
    h.write_u8(0)
    h.write_u64(7)
    return h.finish()
}

fn manual_keyed() -> U64 {
    var h = RandomState.from_words(11, 13).hasher()
    h.write_u64(7)
    return h.finish()
}

fn reference_vectors() -> Bool {
    let state = RandomState.from_words(506097522914230528, 1084818905618843912)
    var empty = state.hasher()
    if empty.finish() != 12370263754033579228 { return false }
    var one = state.hasher()
    one.write_u8(0)
    if one.finish() != 14552427766023178899 { return false }
    var eight = state.hasher()
    var at: U64 = 0
    while at < 8 {
        eight.write_u8(at.to_u8_wrapping())
        at = at + 1
    }
    if eight.finish() != 3931806377309739662 { return false }
    var sixteen = state.hasher()
    at = 0
    while at < 16 {
        sixteen.write_u8(at.to_u8_wrapping())
        at = at + 1
    }
    if sixteen.finish() != 14722228812742953830 { return false }
    return true
}

pub fn main() -> I32 {
    if !reference_vectors() { return 1 }

    var integer = RandomState.from_words(0, 0).hasher()
    integer.write_u64(7)
    if hash(U64, 7) != integer.finish() { return 2 }

    var text = RandomState.from_words(0, 0).hasher()
    text.write_u64(3)
    text.write_bytes("abc".to_bytes())
    if hash(String, "abc") != text.finish() { return 3 }
    if hash(Bytes, "abc".to_bytes()) != text.finish() { return 4 }

    let pair = Pair(a: 7, b: 9)
    if hash(Pair, pair) != manual_pair(pair) { return 5 }
    if hash(Choice.Some(7)) != manual_choice() { return 6 }

    let option: Option(U64) = Some(7)
    if hash(Option(U64), option) != manual_option() { return 7 }
    let result: Result(U64, U64) = Ok(7)
    if hash(Result(U64, U64), result) != manual_result() { return 8 }

    let state = RandomState.from_words(11, 13)
    if hash_with(U64, state, 7) != manual_keyed() { return 9 }

    let io = Blocking()
    let first = random.random_state(io)
    let second = random.random_state(io)
    if hash_with(U64, first, 7) == hash_with(U64, second, 7) { return 10 }
    return 0
}
`

func TestCoreHashProductionQualification(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("cc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml":  snapshotProjectManifest,
		"src/main.al": coreHashProgram,
	}, "run")
	if result.status != 0 {
		t.Fatalf("core.hash program failed: %+v", result)
	}
}

func TestCoreHashRejections(t *testing.T) {
	t.Parallel()
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("cc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	for _, source := range []string{
		`module hello.main

import core.hash { hash }

pub fn main() -> I32 {
    return hash(1.5).to_i32_wrapping()
}
`,
		`module hello.main

import core.hash { hash_with, RandomState }

pub fn main() -> I32 {
    let state = RandomState.from_words(1, 2)
    return hash_with(state, 1.5).to_i32_wrapping()
}
`,
	} {
		result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
			"alder.toml":  snapshotProjectManifest,
			"src/main.al": source,
		}, "check")
		if result.status != 1 || !strings.Contains(result.stderr, "core.hash requires a structurally hashable type") {
			t.Fatalf("core.hash rejection: %+v", result)
		}
	}
}
