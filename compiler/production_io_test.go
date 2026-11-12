package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 std.io v1 slice 1 through the production driver: the Reader/Writer/Seek
// traits, SeekFrom, IoError (Display, Error, from_errno), read_exact,
// write_all, read_to_end, and the host-free ByteCursor and ByteSink streams
// compile as an ordinary sysroot module and behave on generated C. Every
// reader/writer call takes a mutable place, so the same program also proves
// the caller's cursor advances exactly once.

func ioCoreMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.io

fn main() -> I32 {
    // read_exact fills a one-byte view and advances the cursor.
    var cursor = io.ByteCursor.new("abc")
    var one: Array(U8, 1) = [0]
    match io.read_exact(cursor, one.slice_mut(0, 1)) {
        Ok(_) => {}
        Err(_) => { return 1 }
    }
    if one[0] != 97 { return 2 }
    match io.read_exact(cursor, one.slice_mut(0, 1)) {
        Ok(_) => {}
        Err(_) => { return 3 }
    }
    if one[0] != 98 { return 4 }

    // read_to_end drains the rest of the same cursor.
    match io.read_to_end(cursor) {
        Ok(rest) => { if rest.len() != 1 { return 5 } }
        Err(_) => { return 6 }
    }

    // write_all copies an Array view into a ByteSink.
    var sink = io.ByteSink.new()
    let hello: Array(U8, 5) = [104, 101, 108, 108, 111]
    match io.write_all(sink, hello.slice(0, 5)) {
        Ok(n) => { if n != 5 { return 7 } }
        Err(_) => { return 8 }
    }
    if sink.len() != 5 { return 9 }
    let made = sink.into_bytes()
    if made.len() != 5 { return 10 }
    if made.byte(4) != 111 { return 11 }

    // The Reader.copy_to default body copies through its bounded buffer.
    var source = io.ByteCursor.new(made)
    var target = io.ByteSink.new()
    match source.copy_to(target) {
        Ok(n) => { if n != 5 { return 12 } }
        Err(_) => { return 13 } }
    let copied = target.into_bytes()
    if copied.len() != 5 { return 14 }
    if copied.byte(0) != 104 { return 15 }

    // read_exact reports end of stream as InvalidInput.
    var empty = io.ByteCursor.new(made)
    match io.read_to_end(empty) {
        Ok(all) => { if all.len() != 5 { return 16 } }
        Err(_) => { return 17 }
    }
    var drained = io.ByteCursor.new(made)
    match io.read_to_end(drained) {
        Ok(all) => { if all.len() != 5 { return 18 } }
        Err(_) => { return 19 }
    }
    match io.read_exact(drained, one.slice_mut(0, 1)) {
        Ok(_) => { return 20 }
        Err(error) => {
            if error.display() != "invalid input" { return 21 }
        }
    }

    // IoError categories and the prelude Error report.
    let missing = io.IoError.from_errno(2)
    if missing.display() != "not found" { return 22 }
    let report = ErrorReport.of(missing)
    if report.message != "not found" { return 23 }
    if report.causes.len() != 0 { return 24 }
    let odd = io.IoError.from_errno(9999)
    match odd {
        Other(info) => { if info.code != 9999 { return 25 } }
        NotFound => { return 26 }
        PermissionDenied => { return 27 }
        AlreadyExists => { return 28 }
        InvalidInput => { return 29 }
        DirectoryNotEmpty => { return 30 }
        Unsupported => { return 31 }
    }
    return 0
}
`,
	}
}

func TestIoCoreProductionQualification(t *testing.T) {
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

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, ioCoreMain(), "test-plan")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.io plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, " module std.io\n") || !strings.Contains(plan.stdout, "edge std.io -> std.env\n") {
		t.Fatalf("plan does not list std.io and its dependency: %q", plan.stdout)
	}

	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, ioCoreMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.io core behavior run failed: %+v", run)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}

// A read helper takes its reader by mutable place: a let-bound cursor would
// advance a discarded copy, so the call is rejected at the argument.
func TestIoCoreRejectsLetBoundReader(t *testing.T) {
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

import std.io

fn main() -> I32 {
    let cursor = io.ByteCursor.new("abc")
    var one: Array(U8, 1) = [0]
    match io.read_exact(cursor, one.slice_mut(0, 1)) {
        Ok(_) => { return 0 }
        Err(_) => { return 1 }
    }
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status == 0 || !strings.Contains(result.stderr, "mut cursor argument must be a mutable place") {
		t.Fatalf("let-bound reader accepted: %+v", result)
	}
}

// Buffered streams: BufReader serves reads from its window and refills from
// the source; BufWriter buffers small writes, flushes on overflow or demand,
// and cleanup flushes the bytes written after registration. The sink below
// validates every byte in order, so a lost or reordered buffered byte fails
// the run instead of only changing a count.
func ioBufferedMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.io
import core.panic { assert }

type Checker {
    total: U64
    failure: U64
    expected: U64
}

impl Writer for Checker {
    fn write(mut self, data: [U8]) -> Result(U64, io.IoError) {
        var at: U64 = 0
        while at < data.len() {
            let base: U64 = 65
            let want = base + self.total + at
            if data[at] != want.to_u8_wrapping() {
                self.failure = self.failure + 1
            }
            at = at + 1
        }
        self.total = self.total + data.len()
        return Ok(data.len())
    }

    fn flush(mut self) -> Result(Unit, io.IoError) {
        if self.failure != 0 {
            return Err(InvalidInput)
        }
        return Ok(())
    }
}

impl Cleanup for Checker {
    fn cleanup(take self) -> Unit {
        assert(self.total == self.expected, "buffered cleanup flush")
        return
    }
}

fn buffered_reads() -> I32 {
    var reader = io.BufReader.with_capacity(2, io.ByteCursor.new("ab\ncd\nef"))
    var first: Option(Vec(U8)) = None
    match reader.read_until(10) {
        Ok(value) => { first = value }
        Err(_) => { return 1 }
    }
    match first {
        Some(line) => { if line.len() != 3 { return 2 } }
        None => { return 3 }
    }
    var second: Option(String) = None
    match reader.read_line() {
        Ok(value) => { second = value }
        Err(_) => { return 4 }
    }
    match second {
        Some(text) => { if text.len() != 3 { return 5 } }
        None => { return 6 }
    }
    var wide: Array(U8, 4) = [0, 0, 0, 0]
    match reader.read(wide.slice_mut(0, 4)) {
        Ok(n) => { if n != 2 { return 7 } }
        Err(_) => { return 8 }
    }
    if wide[0] != 101 { return 9 }
    if wide[1] != 102 { return 10 }
    return 0
}

fn buffered_writes() -> I32 {
    using held = io.BufWriter.with_capacity(4, Checker(total: 0, failure: 0, expected: 7))
    let head: Array(U8, 2) = [65, 66]
    match held.write(head.slice(0, 2)) {
        Ok(n) => { if n != 2 { return 1 } }
        Err(_) => { return 2 }
    }
    let tail: Array(U8, 5) = [67, 68, 69, 70, 71]
    match held.write(tail.slice(0, 5)) {
        Ok(n) => { if n != 5 { return 3 } }
        Err(_) => { return 4 }
    }
    // No explicit flush: the scope-exit cleanup loads the current writer and
    // flushes the five pending bytes before releasing the sink.
    return 0
}

type Tick {
    position: U64
}

impl Reader for Tick {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, io.IoError) {
        if self.position >= 3 { return Ok(0) }
        if buffer.len() == 0 { return Ok(0) }
        buffer[0] = 120
        self.position = self.position + 1
        return Ok(1)
    }
}

impl Cleanup for Tick {
    fn cleanup(take self) -> Unit {
        assert(self.position == 1, "buffered source cleanup")
        return
    }
}

fn buffered_into_source() -> I32 {
    let reader = io.BufReader.with_capacity(2, Tick(position: 0))
    var one: Array(U8, 1) = [0]
    var failed: I32 = 0
    match reader.read(one.slice_mut(0, 1)) {
        Ok(n) => { if n != 1 { failed = 1 } }
        Err(_) => { failed = 2 }
    }
    if failed == 0 && one[0] != 120 { failed = 3 }
    let source = reader.into_source()
    using kept = source
    return failed
}

fn buffered_into_sink() -> I32 {
    let writer = io.BufWriter.with_capacity(4, Checker(total: 0, failure: 0, expected: 3))
    let data: Array(U8, 3) = [65, 66, 67]
    var failed: I32 = 0
    match writer.write(data.slice(0, 3)) {
        Ok(n) => { if n != 3 { failed = 1 } }
        Err(_) => { failed = 2 }
    }
    var outcome: I32 = 2
    match writer.into_sink() {
        Ok(sink) => {
            using kept = sink
            outcome = failed
        }
        Err(_) => { outcome = 2 }
    }
    return outcome
}

fn main() -> I32 {
    let reads = buffered_reads()
    if reads != 0 { return reads }
    let writes = buffered_writes()
    if writes != 0 { return writes }
    let consumed = buffered_into_sink()
    if consumed != 0 { return consumed }
    let returned = buffered_into_source()
    if returned != 0 { return returned }
    return 0
}
`,
	}
}

func TestIoBufferedProductionQualification(t *testing.T) {
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

	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, ioBufferedMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.io buffered behavior run failed: %+v", run)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}

// ByteSink grows its field storage with the caller's owner domain. A short
// initial capacity no longer truncates: write returns the full count and
// write_all appends everything.
func TestIoByteSinkGrowthProduction(t *testing.T) {
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

import std.io

fn main() -> I32 {
    var sink = io.ByteSink.with_capacity(2)
    let data: Array(U8, 3) = [1, 2, 3]
    match sink.write(data.slice(0, 3)) {
        Ok(n) => { if n != 3 { return 1 } }
        Err(_) => { return 2 }
    }
    if sink.len() != 3 { return 3 }
    match io.write_all(sink, data.slice(0, 3)) {
        Ok(n) => { if n != 3 { return 4 } }
        Err(_) => { return 5 }
    }
    if sink.len() != 6 { return 6 }
    let bytes = sink.into_bytes()
    if bytes.len() != 6 { return 7 }
    if bytes.byte(0) != 1 { return 8 }
    if bytes.byte(2) != 3 { return 9 }
    if bytes.byte(3) != 1 { return 10 }
    if bytes.byte(5) != 3 { return 11 }
    return 0
}
`,
	}
	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, files, "run")
	if run != (productionResult{}) {
		t.Fatalf("growing ByteSink behavior run failed: %+v", run)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
