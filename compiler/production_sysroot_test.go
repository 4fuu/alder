package compiler

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// C1 installed sysroot: discovery, rooted-import resolution, plan identity,
// and deterministic rejections. Every case forces ALDER_SYSROOT explicitly so
// no assertion depends on the ambient environment, and one case proves the
// plan does not depend on how the sysroot was found.

// sysrootEnv strips ALDER_SYSROOT from the test process environment and
// re-adds it only when value is nonempty.
func sysrootEnv(value string) []string {
	env := make([]string, 0, len(os.Environ())+1)
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "ALDER_SYSROOT=") {
			continue
		}
		env = append(env, entry)
	}
	if value != "" {
		env = append(env, "ALDER_SYSROOT="+value)
	}
	return env
}

func runProductionCompilerEnv(t *testing.T, exe, dir string, env []string, files map[string]string, args ...string) productionResult {
	t.Helper()
	for name, text := range files {
		path := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	tmp := filepath.Join(dir, "tmp")
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		t.Fatal(err)
	}
	cmd.Env = append(env, "TMPDIR="+tmp)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("run production compiler: %v", err)
		}
		status = exit.ExitCode()
	}
	return productionResult{status: status, stdout: stdout.String(), stderr: stderr.String()}
}

// copySysrootTree copies the committed sysroot library sources into dst so a
// test can exercise the installed `<exe dir>/../lib/alder` discovery order.
func copySysrootTree(t *testing.T, repoRoot, dst string) {
	t.Helper()
	for _, root := range []string{"core", "std"} {
		entries, err := os.ReadDir(filepath.Join(repoRoot, "sysroot", root))
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Join(dst, root), 0o755); err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			text, err := os.ReadFile(filepath.Join(repoRoot, "sysroot", root, entry.Name()))
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dst, root, entry.Name()), text, 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func sysrootOptionMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import core.option

pub fn main() -> I32 {
    let value: Option(U64) = Some(3)
    if option.is_none(value) { return 1 }
    let empty: Option(U64) = None
    if !option.is_none(empty) { return 2 }
    if !option.is_some(value) { return 3 }
    return 0
}
`,
	}
}

func sysrootTextBytesMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.bytes { BytesBuilder, of_byte, find, find_from, split, binary_search, read_u16_le, read_u16_be, read_u32_le, read_u32_be, read_u64_le, read_u64_be, u16_le_bytes, u16_be_bytes, u32_le_bytes, u32_be_bytes, u64_le_bytes, u64_be_bytes, hex_encode, hex_decode, base64_encode, base64_decode }
import std.text

import hello.builders { builders_check }

fn fail(code: I32) -> I32 {
    return code
}

pub fn main() -> I32 {
    // bytes.of_byte: first, middle, last byte values.
    if of_byte(0).len() != 1 { return fail(1) }
    if of_byte(65).byte(0) != 65 { return fail(2) }
    if of_byte(255).byte(0) != 255 { return fail(3) }

    // BytesBuilder: functional pushes accumulate and finish.
    var b = BytesBuilder.new()
    if b.len() != 0 { return fail(4) }
    b = b.push_byte(65)
    b = b.push_bytes("bc".to_bytes())
    let done = b.finish()
    if done.len() != 3 { return fail(5) }
    if !(done == "Abc".to_bytes()) { return fail(6) }

    // find / find_from on exact bytes.
    let hay = "abcabc".to_bytes()
    var at: U64 = 0
    var seen: Bool = false
    match find(hay, "bc".to_bytes()) {
        Some(found) => {
            at = found
            seen = true
        }
        None => {}
    }
    if !seen { return fail(7) }
    if at != 1 { return fail(8) }
    match find_from(hay, "bc".to_bytes(), 2) {
        Some(found) => {
            if found != 4 { return fail(9) }
        }
        None => { return fail(10) }
    }
    var absent: Bool = false
    match find(hay, "zz".to_bytes()) {
        Some(_) => {}
        None => { absent = true }
    }
    if !absent { return fail(11) }

    // split with empty pieces, no trailing separator piece.
    let parts = split("a,b,,c".to_bytes(), ",".to_bytes())
    if parts.len() != 4 { return fail(12) }
    if !(parts[0] == "a".to_bytes()) { return fail(13) }
    if parts[2].len() != 0 { return fail(14) }
    if !(parts[3] == "c".to_bytes()) { return fail(15) }
    if split("abc", "").len() != 1 { return fail(16) }

    // binary_search: hit, miss beyond, miss before range, leftmost.
    let sorted = "abcce".to_bytes()
    match binary_search(sorted, 99) {
        Ok(found) => {
            if found != 2 { return fail(17) }
        }
        Err(_) => { return fail(18) }
    }
    match binary_search(sorted, 102) {
        Ok(_) => { return fail(19) }
        Err(slot) => {
            if slot != 5 { return fail(20) }
        }
    }
    match binary_search(sorted, 0) {
        Ok(_) => { return fail(21) }
        Err(slot) => {
            if slot != 0 { return fail(22) }
        }
    }

    // Endian writes and reads round-trip; the RFC 5297 example constant
    // fixes the exact byte forms.
    let le = u32_le_bytes(16909060)
    if le.len() != 4 { return fail(23) }
    if le.byte(0) != 4 { return fail(24) }
    if le.byte(3) != 1 { return fail(25) }
    match read_u32_le(le, 0) {
        Ok(value) => {
            if value != 16909060 { return fail(26) }
        }
        Err(_) => { return fail(27) }
    }
    let be = u32_be_bytes(16909060)
    if be.byte(0) != 1 { return fail(28) }
    if be.byte(3) != 4 { return fail(29) }
    match read_u32_be(be, 0) {
        Ok(value) => {
            if value != 16909060 { return fail(30) }
        }
        Err(_) => { return fail(31) }
    }
    let wide = u64_le_bytes(18446744073709551615)
    if wide.len() != 8 { return fail(32) }
    match read_u64_le(wide, 0) {
        Ok(value) => {
            if value != 18446744073709551615 { return fail(33) }
        }
        Err(_) => { return fail(34) }
    }
    let half = u16_be_bytes(4660)
    if half.byte(0) != 18 { return fail(35) }
    if half.byte(1) != 52 { return fail(36) }
    match read_u16_be(half, 0) {
        Ok(value) => {
            if value != 4660 { return fail(37) }
        }
        Err(_) => { return fail(38) }
    }
    var short: Bool = false
    match read_u64_be(wide, 1) {
        Ok(_) => {}
        Err(_) => { short = true }
    }
    if !short { return fail(39) }

    // hex: encode is lowercase, decode accepts both cases, rejects junk.
    let raw: Bytes = "\xde\xad\xbe\xef"
    if hex_encode(raw) != "deadbeef" { return fail(40) }
    match hex_decode("DeAdBeEf") {
        Ok(again) => {
            if !(again == raw) { return fail(41) }
        }
        Err(_) => { return fail(42) }
    }
    var badhex: Bool = false
    match hex_decode("deadbeef0") {
        Ok(_) => {}
        Err(_) => { badhex = true }
    }
    if !badhex { return fail(43) }
    var badchar: Bool = false
    match hex_decode("deadbeeg") {
        Ok(_) => {}
        Err(_) => { badchar = true }
    }
    if !badchar { return fail(44) }

    // base64: the RFC 4648 vectors, padding, and strict rejection.
    if base64_encode("".to_bytes()) != "" { return fail(45) }
    if base64_encode("f".to_bytes()) != "Zg==" { return fail(46) }
    if base64_encode("fo".to_bytes()) != "Zm8=" { return fail(47) }
    if base64_encode("foo".to_bytes()) != "Zm9v" { return fail(48) }
    if base64_encode("foob".to_bytes()) != "Zm9vYg==" { return fail(49) }
    if base64_encode("fooba".to_bytes()) != "Zm9vYmE=" { return fail(50) }
    if base64_encode("foobar".to_bytes()) != "Zm9vYmFy" { return fail(51) }
    match base64_decode("Zm9vYmFy") {
        Ok(back) => {
            if !(back == "foobar".to_bytes()) { return fail(52) }
        }
        Err(_) => { return fail(53) }
    }
    match base64_decode("Zg==") {
        Ok(back) => {
            if !(back == "f".to_bytes()) { return fail(54) }
        }
        Err(_) => { return fail(55) }
    }
    var badpad: Bool = false
    match base64_decode("Zg=") {
        Ok(_) => {}
        Err(_) => { badpad = true }
    }
    if !badpad { return fail(56) }
    var badbits: Bool = false
    match base64_decode("Zh==") {
        Ok(_) => {}
        Err(_) => { badbits = true }
    }
    if !badbits { return fail(57) }
    var badalpha: Bool = false
    match base64_decode("Zm9*") {
        Ok(_) => {}
        Err(_) => { badalpha = true }
    }
    if !badalpha { return fail(58) }
    var pad1_bits: Bool = false
    match base64_decode("Zhi=") {
        Ok(_) => {}
        Err(_) => { pad1_bits = true }
    }
    if !pad1_bits { return fail(100) }
    match base64_decode("Zh8=") {
        Ok(back) => {
            if !(back == "f\x1f".to_bytes()) { return fail(101) }
        }
        Err(_) => { return fail(101) }
    }

    let lone: Bytes = "\xff"
    let overlong: Bytes = "\xc0\x80"
    let surrogate_seq: Bytes = "\xed\xa0\x80"
    let cut: Bytes = "\xc3"
    let narrow_e0_bytes: Bytes = "\xe0\x80\x80"
    let wide_f4_bytes: Bytes = "\xf4\x90\x80\x80"
    // text.validate: ASCII, two-byte, and the rejection edges.
    match text.validate("hello".to_bytes()) {
        Ok(count) => {
            if count != 5 { return fail(59) }
        }
        Err(_) => { return fail(60) }
    }
    match text.validate("\xc3\xa9".to_bytes()) {
        Ok(count) => {
            if count != 1 { return fail(61) }
        }
        Err(_) => { return fail(62) }
    }
    var badutf: Bool = false
    match text.validate(lone) {
        Ok(_) => {}
        Err(failure) => {
            match failure {
                InvalidUtf8(offset) => {
                    if offset == 0 { badutf = true }
                }
                InvalidScalar(_) => {}
            }
        }
    }
    if !badutf { return fail(63) }
    var overlong_reject: Bool = false
    match text.validate(overlong) {
        Ok(_) => {}
        Err(_) => { overlong_reject = true }
    }
    if !overlong_reject { return fail(64) }
    var surrogate: Bool = false
    match text.validate(surrogate_seq) {
        Ok(_) => {}
        Err(_) => { surrogate = true }
    }
    if !surrogate { return fail(65) }
    var truncated: Bool = false
    match text.validate(cut) {
        Ok(_) => {}
        Err(_) => { truncated = true }
    }
    if !truncated { return fail(66) }
    var narrow_e0: Bool = false
    match text.validate(narrow_e0_bytes) {
        Ok(_) => {}
        Err(_) => { narrow_e0 = true }
    }
    if !narrow_e0 { return fail(67) }
    var wide_f4: Bool = false
    match text.validate(wide_f4_bytes) {
        Ok(_) => {}
        Err(_) => { wide_f4 = true }
    }
    if !wide_f4 { return fail(68) }
    var four: Bool = false
    match text.validate("\xf0\x9f\x98\x80".to_bytes()) {
        Ok(count) => {
            if count == 1 { four = true }
        }
        Err(_) => {}
    }
    if !four { return fail(69) }

    // scalar_at, scalar_count, scalars over a two-byte scalar.
    if text.scalar_count("h\xc3\xa9llo") != 5 { return fail(70) }
    match text.scalar_at("h\xc3\xa9llo", 1) {
        Some(one) => {
            if one.value != 233 { return fail(71) }
            if one.size != 2 { return fail(72) }
        }
        None => { return fail(73) }
    }
    var mid: Bool = false
    match text.scalar_at("h\xc3\xa9llo", 2) {
        Some(_) => {}
        None => { mid = true }
    }
    if !mid { return fail(74) }
    var out_of_range: Bool = false
    match text.scalar_at("h\xc3\xa9llo", 99) {
        Some(_) => {}
        None => { out_of_range = true }
    }
    if !out_of_range { return fail(75) }
    let list = text.scalars("h\xc3\xa9llo")
    if list.len() != 5 { return fail(76) }
    if list[1] != 233 { return fail(77) }

    // text find / split / replace.
    match text.find("hello world hello", "world") {
        Some(found) => {
            if found != 6 { return fail(78) }
        }
        None => { return fail(79) }
    }
    var missing: Bool = false
    match text.find("hello", "world") {
        Some(_) => {}
        None => { missing = true }
    }
    if !missing { return fail(80) }
    let pieces = text.split("a:b::c", ":")
    if pieces.len() != 4 { return fail(81) }
    if pieces[0] != "a" { return fail(82) }
    if pieces[2] != "" { return fail(83) }
    if pieces[3] != "c" { return fail(84) }
    if text.replace("aaa", "a", "b") != "bbb" { return fail(85) }
    if text.replace("abcabc", "abc", "x") != "xx" { return fail(86) }
    if text.replace("abc", "", "z") != "abc" { return fail(87) }
    if text.replace("aaa", "aa", "b") != "ba" { return fail(88) }

    // from_utf8 round-trip and rejection.
    match text.from_utf8("h\xc3\xa9llo".to_bytes()) {
        Ok(value) => {
            if value != "h\xc3\xa9llo" { return fail(89) }
        }
        Err(_) => { return fail(90) }
    }
    var reject_utf: Bool = false
    match text.from_utf8(lone) {
        Ok(_) => {}
        Err(_) => { reject_utf = true }
    }
    if !reject_utf { return fail(91) }

    if builders_check() != 0 { return builders_check() + 100 }
    return 0
}
`,
		"src/builders.al": `module hello.builders

import std.text { StringBuilder }

pub fn builders_check() -> I32 {
    var sb = StringBuilder.new()
    sb = sb.push_text("a")
    let pushed = match sb.push_scalar(233) {
        Ok(next) => next
        Err(_) => sb
    }
    let finished = pushed.finish()
    if finished != "a\xc3\xa9" { return 1 }
    if finished.len() != 3 { return 2 }
    var scalar_reject: Bool = false
    match sb.push_scalar(55296) {
        Ok(_) => {}
        Err(failure) => {
            match failure {
                InvalidScalar(value) => {
                    if value == 55296 { scalar_reject = true }
                }
                InvalidUtf8(_) => {}
            }
        }
    }
    if !scalar_reject { return 3 }
    var above: Bool = false
    match sb.push_scalar(1114112) {
        Ok(_) => {}
        Err(_) => { above = true }
    }
    if !above { return 4 }
    let junk: Bytes = "\xff"
    var utf_reject: Bool = false
    match pushed.push_utf8(junk) {
        Ok(_) => {}
        Err(_) => { utf_reject = true }
    }
    if !utf_reject { return 5 }
    var utf_ok: Bool = false
    let emoji: Bytes = "\xf0\x9f\x98\x80"
    let grown = match pushed.push_utf8(emoji) {
        Ok(next) => next
        Err(_) => pushed
    }
    if grown.finish().len() == 7 { utf_ok = true }
    if !utf_ok { return 6 }
    return 0
}
`,
	}
}

func sysrootCollectionMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.collection { sort }

pub fn main() -> I32 {
    let first = check_number_sort()
    if first != 0 { return first }
    let second = check_word_sort()
    if second != 0 { return second }
    let third = check_flag_sort()
    if third != 0 { return third }
    let fourth = check_small_sorts()
    if fourth != 0 { return fourth }
    return 0
}

fn check_number_sort() -> I32 {
    let numbers: Array(U64, 7) = [5, 1, 4, 1, 3, 1, 9]
    let sorted = sort(U64, numbers.slice(0, 7))
    if sorted.len() != 7 { return 1 }
    let expect: Array(U64, 7) = [1, 1, 1, 3, 4, 5, 9]
    var values_bad: Bool = false
    var at: U64 = 0
    while at < 7 {
        match sorted.get(at) {
            Some(value) => {
                match expect.get(at) {
                    Some(wanted) => {
                        if value != wanted { values_bad = true }
                    }
                    None => { return 2 }
                }
            }
            None => { return 3 }
        }
        at = at + 1
    }
    if values_bad { return 10 }
    // The input slice stays untouched.
    match numbers.get(0) {
        Some(head) => { if head != 5 { return 4 } }
        None => { return 5 }
    }
    return 0
}

fn check_word_sort() -> I32 {
    let words: Array(String, 5) = ["pear", "apple", "banana", "app", "apple"]
    let sorted = sort(String, words.slice(0, 5))
    if sorted.len() != 5 { return 1 }
    let expect: Array(String, 5) = ["app", "apple", "apple", "banana", "pear"]
    var values_bad: Bool = false
    var at: U64 = 0
    while at < 5 {
        match sorted.get(at) {
            Some(value) => {
                match expect.get(at) {
                    Some(wanted) => {
                        if value != wanted { values_bad = true }
                    }
                    None => { return 2 }
                }
            }
            None => { return 3 }
        }
        at = at + 1
    }
    if values_bad { return 10 }
    return 0
}

fn check_flag_sort() -> I32 {
    let flags: Array(Bool, 3) = [true, false, true]
    let sorted = sort(Bool, flags.slice(0, 3))
    if sorted.len() != 3 { return 1 }
    match sorted.get(0) {
        Some(value) => { if value { return 2 } }
        None => { return 3 }
    }
    match sorted.get(1) {
        Some(value) => { if !value { return 4 } }
        None => { return 5 }
    }
    match sorted.get(2) {
        Some(value) => { if !value { return 6 } }
        None => { return 7 }
    }
    return 0
}

fn check_small_sorts() -> I32 {
    let none: Array(U64, 0) = []
    let sorted_none = sort(U64, none.slice(0, 0))
    if sorted_none.len() != 0 { return 1 }
    let one: Array(U64, 1) = [42]
    let sorted_one = sort(U64, one.slice(0, 1))
    if sorted_one.len() != 1 { return 2 }
    match sorted_one.get(0) {
        Some(value) => { if value != 42 { return 3 } }
        None => { return 4 }
    }
    return 0
}
`,
	}
}

func TestProductionSysrootCollectionRuns(t *testing.T) {
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootCollectionMain(), "test-plan")
	collectionSeed := sysrootModuleSeed(t, repoRoot, "collection.al")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.collection plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/collection.al bytes "+collectionSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.collection\n") {
		t.Fatalf("plan does not list the std.collection source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> std.collection\n") {
		t.Fatalf("plan does not record the std.collection edge: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootCollectionMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("std.collection plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootCollectionMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.collection behavior run failed: %+v", run)
	}
}

func sysrootPathEnvMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.env { EnvError, PlatformInfo, Target, TargetArch, TargetOs }
import std.path { OsString, Path }

pub fn main() -> I32 {
    let first = check_os_parse()
    if first != 0 { return first }
    let second = check_os_reject()
    if second != 0 { return second }
    let third = check_os_from_bytes()
    if third != 0 { return third }
    let fourth = check_os_non_text()
    if fourth != 0 { return fourth }
    let fifth = check_path_queries()
    if fifth != 0 { return fifth }
    let sixth = check_path_join()
    if sixth != 0 { return sixth }
    let seventh = check_path_normalize()
    if seventh != 0 { return seventh }
    let eighth = check_path_names()
    if eighth != 0 { return eighth }
    let ninth = check_path_parent()
    if ninth != 0 { return ninth }
    let tenth = check_env_types()
    if tenth != 0 { return tenth }
    return 0
}

fn text_same(left: String, right: String) -> Bool {
    if left.len() != right.len() { return false }
    var at: U64 = 0
    while at < left.len() {
        if left.byte(at) != right.byte(at) { return false }
        at = at + 1
    }
    return true
}

fn host_text_is(left: Option(OsString), right: String) -> Bool {
    var same: Bool = false
    match left {
        Some(host) => {
            match host.to_string() {
                Some(text) => { same = text_same(text, right) }
                None => {}
            }
        }
        None => {}
    }
    return same
}

fn path_text_is(left: Option(Path), right: String) -> Bool {
    var same: Bool = false
    match left {
        Some(value) => {
            let host = value.to_os()
            match host.to_string() {
                Some(text) => { same = text_same(text, right) }
                None => {}
            }
        }
        None => {}
    }
    return same
}

fn check_os_parse() -> I32 {
    var code: I32 = 0
    match OsString.parse("hello") {
        Ok(value) => {
            if !host_text_is(Some(value), "hello") { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    return code
}

fn check_os_reject() -> I32 {
    var code: I32 = 0
    match OsString.parse("bad\0name") {
        Ok(_) => { code = 1 }
        Err(_) => {}
    }
    match Path.parse("bad\0name") {
        Ok(_) => { code = 2 }
        Err(_) => {}
    }
    return code
}

fn check_os_from_bytes() -> I32 {
    var code: I32 = 0
    let raw = "ready"
    match OsString.from_bytes(raw.to_bytes()) {
        Ok(value) => {
            if !host_text_is(Some(value), "ready") { code = 1 }
            let again = raw.to_bytes()
            match OsString.from_bytes(again) {
                Ok(twin) => {
                    let one = value.to_string()
                    let two = twin.to_string()
                    var equal: Bool = false
                    match one {
                        Some(first) => {
                            match two {
                                Some(second) => { equal = text_same(first, second) }
                                None => {}
                            }
                        }
                        None => {}
                    }
                    if !equal { code = 2 }
                }
                Err(_) => { code = 3 }
            }
        }
        Err(_) => { code = 4 }
    }
    return code
}

fn check_os_non_text() -> I32 {
    var code: I32 = 0
    let raw: Bytes = "\xff\xfe"
    match OsString.from_bytes(raw) {
        Ok(value) => {
            match value.to_string() {
                Some(_) => { code = 1 }
                None => {}
            }
        }
        Err(_) => { code = 2 }
    }
    return code
}

fn check_path_queries() -> I32 {
    var code: I32 = 0
    match Path.parse("/usr/local/app.conf") {
        Ok(entry) => {
            let parts = entry.components()
            if parts.len() != 4 { code = 1 }
            if code == 0 {
                match parts[0] {
                    RootDir => {}
                    CurDir => { code = 2 }
                    ParentDir => { code = 2 }
                    Normal(_) => { code = 2 }
                }
            }
            if code == 0 {
                match parts[1] {
                    Normal(name) => {
                        if !host_text_is(Some(name), "usr") { code = 3 }
                    }
                    RootDir => { code = 3 }
                    CurDir => { code = 3 }
                    ParentDir => { code = 3 }
                }
            }
            if code == 0 {
                if !host_text_is(entry.file_name(), "app.conf") { code = 4 }
            }
            if code == 0 {
                if !host_text_is(entry.file_stem(), "app") { code = 5 }
            }
            if code == 0 {
                if !host_text_is(entry.extension(), "conf") { code = 6 }
            }
            if code == 0 {
                if !path_text_is(entry.parent(), "/usr/local") { code = 7 }
            }
            if code == 0 {
                if !entry.is_absolute() { code = 8 }
            }
        }
        Err(_) => { code = 9 }
    }
    return code
}

fn check_path_join() -> I32 {
    var code: I32 = 0
    match Path.parse("a/b/./c") {
        Ok(base) => {
            match Path.parse("d/../../e") {
                Ok(suffix) => {
                    let joined = base.join(suffix)
                    let norm = joined.normalize()
                    if !path_text_is(Some(norm), "a/b/e") { code = 1 }
                }
                Err(_) => { code = 2 }
            }
            if code == 0 {
                match Path.parse("/absolute") {
                    Ok(absolute) => {
                        let replaced = base.join(absolute)
                        if !path_text_is(Some(replaced), "/absolute") { code = 3 }
                    }
                    Err(_) => { code = 4 }
                }
            }
        }
        Err(_) => { code = 5 }
    }
    if code == 0 {
        match Path.parse("") {
            Ok(empty) => {
                match Path.parse("b") {
                    Ok(other) => {
                        let grown = empty.join(other)
                        if !path_text_is(Some(grown), "b") { code = 6 }
                        let kept = other.join(empty)
                        if !path_text_is(Some(kept), "b") { code = 7 }
                    }
                    Err(_) => { code = 8 }
                }
            }
            Err(_) => { code = 9 }
        }
    }
    return code
}

fn check_path_normalize() -> I32 {
    var code: I32 = 0
    match Path.parse("a/../../..") {
        Ok(base) => {
            let up = base.normalize()
            if !path_text_is(Some(up), "../..") { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    if code == 0 {
        match Path.parse("/a/../../b") {
            Ok(deep) => {
                let norm = deep.normalize()
                if !path_text_is(Some(norm), "/../b") { code = 3 }
            }
            Err(_) => { code = 4 }
        }
    }
    if code == 0 {
        match Path.parse(".") {
            Ok(dot) => {
                let plain = dot.normalize()
                if !path_text_is(Some(plain), "") { code = 5 }
            }
            Err(_) => { code = 6 }
        }
    }
    if code == 0 {
        match Path.parse("/..") {
            Ok(over) => {
                let kept = over.normalize()
                if !path_text_is(Some(kept), "/..") { code = 7 }
            }
            Err(_) => { code = 8 }
        }
    }
    if code == 0 {
        match Path.parse("a/./b/..") {
            Ok(mixed) => {
                let clean = mixed.normalize()
                if !path_text_is(Some(clean), "a") { code = 9 }
            }
            Err(_) => { code = 10 }
        }
    }
    if code == 0 {
        match Path.parse("") {
            Ok(empty) => {
                let flat = empty.normalize()
                if !path_text_is(Some(flat), "") { code = 11 }
                if empty.is_absolute() { code = 12 }
            }
            Err(_) => { code = 13 }
        }
    }
    if code == 0 {
        match Path.parse("/") {
            Ok(root) => {
                let same = root.normalize()
                if !path_text_is(Some(same), "/") { code = 14 }
                if !root.is_absolute() { code = 15 }
            }
            Err(_) => { code = 16 }
        }
    }
    return code
}

fn check_path_names() -> I32 {
    var code: I32 = 0
    match Path.parse("a/b/") {
        Ok(slash) => {
            if !host_text_is(slash.file_name(), "b") { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    if code == 0 {
        match Path.parse("a/.") {
            Ok(dot_end) => {
                var absent: Bool = true
                match dot_end.file_name() {
                    Some(_) => { absent = false }
                    None => {}
                }
                if !absent { code = 3 }
            }
            Err(_) => { code = 4 }
        }
    }
    if code == 0 {
        match Path.parse("a/..") {
            Ok(up_end) => {
                var absent: Bool = true
                match up_end.file_name() {
                    Some(_) => { absent = false }
                    None => {}
                }
                if !absent { code = 5 }
            }
            Err(_) => { code = 6 }
        }
    }
    if code == 0 {
        match Path.parse("foo.tar.gz") {
            Ok(archive) => {
                if !host_text_is(archive.file_stem(), "foo.tar") { code = 7 }
                if !host_text_is(archive.extension(), "gz") { code = 8 }
            }
            Err(_) => { code = 9 }
        }
    }
    if code == 0 {
        match Path.parse(".gitignore") {
            Ok(dotfile) => {
                if !host_text_is(dotfile.file_stem(), ".gitignore") { code = 10 }
                var none: Bool = true
                match dotfile.extension() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 11 }
            }
            Err(_) => { code = 12 }
        }
    }
    if code == 0 {
        match Path.parse(".foo.tar.gz") {
            Ok(hidden) => {
                if !host_text_is(hidden.file_stem(), ".foo.tar") { code = 13 }
                if !host_text_is(hidden.extension(), "gz") { code = 14 }
            }
            Err(_) => { code = 15 }
        }
    }
    if code == 0 {
        match Path.parse("a.") {
            Ok(trailing) => {
                var empty: Bool = false
                match trailing.extension() {
                    Some(ext) => {
                        match ext.to_string() {
                            Some(text) => {
                                if text.len() == 0 { empty = true }
                            }
                            None => {}
                        }
                    }
                    None => { code = 16 }
                }
                if !empty { code = 17 }
            }
            Err(_) => { code = 18 }
        }
    }
    if code == 0 {
        match Path.parse("foo") {
            Ok(plain) => {
                var none: Bool = true
                match plain.extension() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 19 }
            }
            Err(_) => { code = 20 }
        }
    }
    return code
}

fn check_path_parent() -> I32 {
    var code: I32 = 0
    match Path.parse("foo") {
        Ok(plain) => {
            let up = plain.parent()
            var found: Bool = false
            match up {
                Some(remainder) => {
                    let host = remainder.to_os()
                    match host.to_string() {
                        Some(text) => {
                            if text.len() == 0 { found = true }
                        }
                        None => {}
                    }
                }
                None => {}
            }
            if !found { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    if code == 0 {
        match Path.parse("/") {
            Ok(root) => {
                var none: Bool = true
                match root.parent() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 3 }
            }
            Err(_) => { code = 4 }
        }
    }
    if code == 0 {
        match Path.parse("") {
            Ok(empty) => {
                var none: Bool = true
                match empty.parent() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 5 }
            }
            Err(_) => { code = 6 }
        }
    }
    if code == 0 {
        match Path.parse("a/.") {
            Ok(dot_end) => {
                if !path_text_is(dot_end.parent(), "a") { code = 7 }
            }
            Err(_) => { code = 8 }
        }
    }
    if code == 0 {
        match Path.parse("a/..") {
            Ok(up_end) => {
                if !path_text_is(up_end.parent(), "a") { code = 9 }
            }
            Err(_) => { code = 10 }
        }
    }
    return code
}

fn check_env_types() -> I32 {
    var code: I32 = 0
    let info: PlatformInfo = PlatformInfo(code: 2, message: "no entry")
    if info.code != 2 { code = 1 }
    if info.message.len() != 8 { code = 2 }
    if code == 0 {
        let failure: EnvError = Platform(info)
        match failure {
            Platform(carried) => {
                if carried.code != 2 { code = 3 }
                if !text_same(carried.message, "no entry") { code = 4 }
            }
            InvalidEncoding => { code = 5 }
            InvalidName => { code = 5 }
            Unsupported => { code = 5 }
        }
    }
    if code == 0 {
        let target: Target = Target(os: Linux, arch: X64)
        match target.os {
            Linux => {}
            MacOS => { code = 6 }
            Windows => { code = 6 }
        }
        match target.arch {
            X64 => {}
            AArch64 => { code = 7 }
        }
    }
    return code
}
`,
	}
}

func sysrootEnvMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.env { EnvError, PlatformInfo, Target, TargetArch, TargetOs }

pub fn main() -> I32 {
    return check_env_types()
}

fn text_same(left: String, right: String) -> Bool {
    if left.len() != right.len() { return false }
    var at: U64 = 0
    while at < left.len() {
        if left.byte(at) != right.byte(at) { return false }
        at = at + 1
    }
    return true
}

fn check_env_types() -> I32 {
    var code: I32 = 0
    let info: PlatformInfo = PlatformInfo(code: 2, message: "no entry")
    if info.code != 2 { code = 1 }
    if info.message.len() != 8 { code = 2 }
    if code == 0 {
        let failure: EnvError = Platform(info)
        match failure {
            Platform(carried) => {
                if carried.code != 2 { code = 3 }
                if !text_same(carried.message, "no entry") { code = 4 }
            }
            InvalidEncoding => { code = 5 }
            InvalidName => { code = 5 }
            Unsupported => { code = 5 }
        }
    }
    if code == 0 {
        let target: Target = Target(os: Linux, arch: X64)
        match target.os {
            Linux => {}
            MacOS => { code = 6 }
            Windows => { code = 6 }
        }
        match target.arch {
            X64 => {}
            AArch64 => { code = 7 }
        }
    }
    return code
}
`,
	}
}

func sysrootSeedLength(t *testing.T, repoRoot string) string {
	t.Helper()
	info, err := os.Stat(filepath.Join(repoRoot, "sysroot", "core", "option.al"))
	if err != nil {
		t.Fatal(err)
	}
	return strconv.FormatUint(uint64(info.Size()), 10)
}

func TestProductionSysrootCoreResolves(t *testing.T) {
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "test-plan")
	seedBytes := sysrootSeedLength(t, repoRoot)
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("sysroot plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") || strings.Contains(plan.stdout, "compiler-coupled-v1") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source core/option.al bytes "+seedBytes+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module core.option\n") {
		t.Fatalf("plan does not list the sysroot source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> core.option\n") {
		t.Fatalf("plan does not record the sysroot edge: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("sysroot plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("sysroot project run failed: %+v", run)
	}
}

func TestProductionSysrootPathEnvRuns(t *testing.T) {
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootPathEnvMain(), "test-plan")
	pathSeed := sysrootModuleSeed(t, repoRoot, "path.al")
	envSeed := sysrootModuleSeed(t, repoRoot, "env.al")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.path/std.env plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/path.al bytes "+pathSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.path\n") {
		t.Fatalf("plan does not list the std.path source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/env.al bytes "+envSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.env\n") {
		t.Fatalf("plan does not list the std.env source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> std.path\n") ||
		!strings.Contains(plan.stdout, "edge hello.main -> std.env\n") {
		t.Fatalf("plan does not record the std edges: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootPathEnvMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("std.path/std.env plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootPathEnvMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.path/std.env behavior run failed: %+v", run)
	}
}

func TestProductionSysrootTextBytesRuns(t *testing.T) {
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootTextBytesMain(), "test-plan")
	bytesSeed := sysrootModuleSeed(t, repoRoot, "bytes.al")
	textSeed := sysrootModuleSeed(t, repoRoot, "text.al")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.text/std.bytes plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/bytes.al bytes "+bytesSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.bytes\n") {
		t.Fatalf("plan does not list the std.bytes source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/text.al bytes "+textSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.text\n") {
		t.Fatalf("plan does not list the std.text source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> std.bytes\n") ||
		!strings.Contains(plan.stdout, "edge hello.main -> std.text\n") ||
		!strings.Contains(plan.stdout, "edge hello.builders -> std.text\n") {
		t.Fatalf("plan does not record the std edges: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootTextBytesMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("std.text/std.bytes plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootTextBytesMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.text/std.bytes behavior run failed: %+v", run)
	}
}

func TestProductionSysrootEnvRuns(t *testing.T) {
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootEnvMain(), "test-plan")
	envSeed := sysrootModuleSeed(t, repoRoot, "env.al")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.env plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/env.al bytes "+envSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.env\n") {
		t.Fatalf("plan does not list the std.env source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> std.env\n") {
		t.Fatalf("plan does not record the std.env edge: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootEnvMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("std.env plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootEnvMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.env behavior run failed: %+v", run)
	}
}

func sysrootModuleSeed(t *testing.T, repoRoot, name string) string {
	t.Helper()
	info, err := os.Stat(filepath.Join(repoRoot, "sysroot", "std", name))
	if err != nil {
		t.Fatal(err)
	}
	return strconv.FormatUint(uint64(info.Size()), 10)
}

func TestProductionSysrootPlanStableAcrossDiscovery(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)

	envRoot := t.TempDir()
	viaEnv := runProductionCompilerEnv(t, exe, envRoot, sysrootEnv(filepath.Join(repoRoot, "sysroot")), sysrootOptionMain(), "test-plan")
	if viaEnv.status != 0 || viaEnv.stderr != "" {
		t.Fatalf("ALDER_SYSROOT discovery plan failed: %+v", viaEnv)
	}

	// The same sysroot content found through <exe dir>/../lib/alder with no
	// ALDER_SYSROOT must produce a byte-identical plan.
	layout := t.TempDir()
	if err := os.MkdirAll(filepath.Join(layout, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	copySysrootTree(t, repoRoot, filepath.Join(layout, "lib", "alder"))
	copied := filepath.Join(layout, "bin", "alder-driver")
	text, err := os.ReadFile(exe)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(copied, text, 0o755); err != nil {
		t.Fatal(err)
	}
	viaLayout := runProductionCompilerEnv(t, copied, t.TempDir(), sysrootEnv(""), sysrootOptionMain(), "test-plan")
	if viaLayout != viaEnv {
		t.Fatalf("plan depends on sysroot discovery order: env=%q layout=%q", viaEnv.stdout, viaLayout.stdout)
	}
}

func TestProductionSysrootUnavailable(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(""), sysrootOptionMain(), "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "no installed Alder sysroot is available") {
		t.Fatalf("missing sysroot rejection: %+v", result)
	}
}

func TestProductionSysrootMissingModule(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	files["src/main.al"] = strings.Replace(files["src/main.al"], "import core.option", "import core.missing", 1)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "a required sysroot module is unavailable") {
		t.Fatalf("missing sysroot module rejection: %+v", result)
	}
}

func TestProductionSysrootStdResolves(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	// A fixture sysroot proves the `std` root resolves through the same
	// machinery before the first hosted std module lands.
	fixture := t.TempDir()
	if err := os.MkdirAll(filepath.Join(fixture, "std"), 0o755); err != nil {
		t.Fatal(err)
	}
	echo := "module std.echo\n\n/// Echoes one fixed byte.\npub fn first_byte() -> U8 {\n    return 7\n}\n"
	if err := os.WriteFile(filepath.Join(fixture, "std", "echo.al"), []byte(echo), 0o644); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.echo

pub fn main() -> I32 {
    if echo.first_byte() != 7 { return 1 }
    return 0
}
`,
	}
	run := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(fixture), files, "run")
	if run != (productionResult{}) {
		t.Fatalf("std fixture project run failed: %+v", run)
	}
}

func TestProductionSysrootCannotShadow(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	// Both decoys must be ignored: a project-local sysroot tree and a
	// project source at the sysroot path.
	files["sysroot/core/option.al"] = "module core.option\npub fn is_none(T: type, value: Option(T)) -> Bool {\n    return true\n}\n"
	files["src/core/option.al"] = "module hello.core.option\npub fn decoy() -> I32 { return 0 }\n"
	dir := t.TempDir()
	plan := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "test-plan")
	seedBytes := sysrootSeedLength(t, repoRoot)
	if plan.status != 0 || !strings.Contains(plan.stdout, "source core/option.al bytes "+seedBytes+" poly64-v1:") {
		t.Fatalf("project tree shadowed the sysroot: %+v", plan)
	}
	run := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "run")
	if run != (productionResult{}) {
		t.Fatalf("shadowed project run failed: %+v", run)
	}
}

func TestProductionSysrootReservedPackageName(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	files["alder.toml"] = strings.Replace(files["alder.toml"], "name = \"hello\"", "name = \"core\"", 1)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "the package name core or std is reserved") {
		t.Fatalf("reserved package name rejection: %+v", result)
	}
}

// The qualified-call sequence programs pin that imported generic calls
// compose across let, var, and argument position under every import
// spelling. Before the qualified-name fix, a follow-up qualified call after
// a let-position generic call could be misdiagnosed through receiver
// dispatch, so these programs guard resolution state across a whole body.
func sysrootSequenceProjects() map[string]map[string]string {
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	qualified := `module hello.main

import core.option
import core.result

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let held: Option(I64) = Some(5)
    let bad: Result(I64, String) = Err("rejected")
    let good: Result(I64, String) = Ok(30)
    let projected = result.ok(I64, String, good)
    let error_side = result.err(I64, String, bad)
    var total: I64 = option.unwrap_or(I64, projected, 0)
    total = total + option.unwrap_or(I64, option.map(I64, I64, held, double), 0)
    if result.is_err(bad) { total = total + 1 }
    if option.is_none(error_side) { total = total + 2 }
    if option.is_some(option.and_then(I64, I64, held, half)) { total = total + 4 }
    if option.is_none(empty) { total = total + 8 }
    if total == 53 { return 0 }
    return 1
}

fn double(v: I64) -> I64 { return v * 2 }

fn half(v: I64) -> Option(I64) {
    return Some(v / 2)
}
`
	aliased := `module hello.main

import core.option as opt
import core.result as res

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let held: Option(I64) = Some(5)
    let bad: Result(I64, String) = Err("rejected")
    let good: Result(I64, String) = Ok(30)
    let projected = res.ok(I64, String, good)
    let error_side = res.err(I64, String, bad)
    var total: I64 = opt.unwrap_or(I64, projected, 0)
    total = total + opt.unwrap_or(I64, opt.map(I64, I64, held, double), 0)
    if res.is_err(bad) { total = total + 1 }
    if opt.is_none(error_side) { total = total + 2 }
    if opt.is_some(opt.and_then(I64, I64, held, half)) { total = total + 4 }
    if opt.is_none(empty) { total = total + 8 }
    if total == 53 { return 0 }
    return 1
}

fn double(v: I64) -> I64 { return v * 2 }

fn half(v: I64) -> Option(I64) {
    return Some(v / 2)
}
`
	braced := `module hello.main

import core.option { is_none, is_some, map, and_then, unwrap_or }
import core.result { is_err, ok, err }

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let held: Option(I64) = Some(5)
    let bad: Result(I64, String) = Err("rejected")
    let good: Result(I64, String) = Ok(30)
    let projected = ok(I64, String, good)
    let error_side = err(I64, String, bad)
    var total: I64 = unwrap_or(I64, projected, 0)
    total = total + unwrap_or(I64, map(I64, I64, held, double), 0)
    if is_err(bad) { total = total + 1 }
    if is_none(error_side) { total = total + 2 }
    if is_some(and_then(I64, I64, held, half)) { total = total + 4 }
    if is_none(empty) { total = total + 8 }
    if total == 53 { return 0 }
    return 1
}

fn double(v: I64) -> I64 { return v * 2 }

fn half(v: I64) -> Option(I64) {
    return Some(v / 2)
}
`
	files := func(mainText string) map[string]string {
		return map[string]string{"alder.toml": manifest, "src/main.al": mainText}
	}
	return map[string]map[string]string{
		"qualified": files(qualified),
		"aliased":   files(aliased),
		"braced":    files(braced),
	}
}

func TestProductionSysrootImportedCallsCompose(t *testing.T) {
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
	// Expected checksum: 30 (projected) + 10 (doubled) + 1 (bad is_err)
	// (error_side is Some so is_none adds 0) + 4 (and_then is_some)
	// + 8 (empty is_none).
	for name, files := range sysrootSequenceProjects() {
		run := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
		if run != (productionResult{}) {
			t.Fatalf("%s sequence run failed: %+v", name, run)
		}
	}
}

// The core.num snapshot runtime test pins the limits and the explicit
// overflow-mode absolute value against the installed sysroot, including the
// minimum-boundary None of the checked form and the wrapping identity at
// every width.
func TestProductionSysrootNumHelpers(t *testing.T) {
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
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	main := `module hello.main

import core.num

pub fn main() -> I32 {
    var total: I64 = 0
    if num.i32_max() == 2147483647 { total = total + 1 }
    if num.u32_max() == 4294967295 { total = total + 2 }
    match num.i64_abs_checked(num.i64_min()) {
        None => { total = total + 4 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    match num.i32_abs_checked(num.i32_min()) {
        None => { total = total + 8 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    if num.i64_abs_wrapping(num.i64_min()) == num.i64_min() { total = total + 16 }
    match num.i64_abs_checked(-42) {
        Some(v) => {
            if v == 42 { total = total + 32 }
        }
        None => { total = total + 0 }
    }
    if total == 63 { return 0 }
    return 1
}
`
	files := map[string]string{"alder.toml": manifest, "src/main.al": main}
	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if run != (productionResult{}) {
		t.Fatalf("core.num helpers run failed: %+v", run)
	}
}

func TestProductionSysrootQualifiedNameDiagnostics(t *testing.T) {
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
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

	// A typo'd member under a real sysroot namespace is reported against the
	// full dotted name at its qualified span, never as the bare qualifier.
	typo := `module hello.main

import core.option

pub fn main() -> I32 {
    let empty: Option(I64) = None
    return option.typo(empty)
}
`
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": typo}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, `unknown name "option.typo"`) {
		t.Fatalf("typo member rejection: %+v", result)
	}

	// A qualifier the program never imports under is the same dotted-name
	// miss, not a receiver dispatch on the unknown word.
	wrongQualifier := `module hello.main

import core.option as opt

pub fn main() -> I32 {
    let empty: Option(I64) = None
    return opt.unwrap_or(I64, option.map(I64, I64, empty, double), 0)
}

fn double(v: I64) -> I64 { return v * 2 }
`
	result = runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": wrongQualifier}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, `unknown name "option.map"`) {
		t.Fatalf("wrong qualifier rejection: %+v", result)
	}

	// The same rule holds for the result namespace.
	resultTypo := `module hello.main

import core.result

pub fn main() -> I32 {
    let good: Result(I64, String) = Ok(30)
    return result.typo(I64, String, good)
}
`
	result = runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": resultTypo}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, `unknown name "result.typo"`) {
		t.Fatalf("result typo rejection: %+v", result)
	}

	// A dotted callee that resolves but fails to type check keeps the type
	// diagnostic; the old defect turned this shape into an unknown-name
	// report against the qualifier.
	mismatch := `module hello.main

import core.option

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let verdict = option.ok_or(I64, I64, empty, 9)
    if option.is_some(verdict) { return 1 }
    return 0
}
`
	result = runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": mismatch}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, "semantic error") || strings.Contains(result.stderr, `unknown name "option`) {
		t.Fatalf("type mismatch diagnostic: %+v", result)
	}
}
