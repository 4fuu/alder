module std.test

// The runner-independent part of the Milestone 8 testing surface. Top-level
// `test` declarations, discovery and reporting, fuzzing, subprocess
// isolation, and SimIo stay with the tooling milestones; this module provides
// the value-level helpers a test body can use directly.
//
// Failures terminate through `core.panic.panic` with status 101. The helpers
// that return a value call that function directly as their last statement, so
// the checker sees a diverging path end. `fail`, `assert`, `assert_eq`, and
// `assert_ne` are ordinary `Unit` functions: a call to one of them is not a
// diverging path end for the caller.

import core.panic
import std.fs
import std.io { AsyncIo, ChildStatus, DirEntry, FileMode, FileStat, HostChild, HostDirectory, HostFile, Io, IoError, PollPair, SeekFrom, Timestamp }
import std.path { OsString, Path }
import std.random
import std.time { Duration }

import c "std/c/sim_shim.h" as simrt {
    raw fn install_hooks = "task_install_sim_hooks"() -> Unit
    raw fn park = "alder_task_park"() -> Unit
    raw fn clock_now = "task_clock_now"() -> c.ULongLong
    raw fn timer_in = "task_timer_in"(delay: c.ULongLong) -> c.Int
    raw fn yield_current = "task_yield_current"() -> Unit
    raw fn rng_new = "sim_rng_new"(seed: c.ULongLong) -> c.ULongLong
    raw fn rng_fill = "sim_rng_fill"(handle: c.ULongLong, buffer: c.Ptr(c.UChar), length: c.ULongLong) -> Unit
    raw fn write_stdout = "task_write_stdout"(data: c.ConstPtr(c.UChar), length: c.ULongLong) -> c.Int
    raw fn write_stderr = "task_write_stderr"(data: c.ConstPtr(c.UChar), length: c.ULongLong) -> c.Int
}

/// Terminates the process with the test failure message.
///
/// This is the thin source-level spelling over `core.panic.panic`; the
/// process exits with status 101 and does not run cleanup scopes.
pub fn fail(message: String) -> Unit {
    panic.panic(message)
}

/// Terminates unless `condition` is true. The message is the fixed parameter
/// text; source-expression capture belongs to the test runner.
pub fn assert(condition: Bool, message: String) -> Unit {
    panic.assert(condition, message)
    return
}

/// Terminates unless `a` equals `b`. The diagnostic names the fixed `a == b`
/// relation and displays both operands.
pub fn assert_eq(T: type(Eq, Display), a: T, b: T) -> Unit {
    panic.assert_eq(T, a, b)
    return
}

/// Terminates unless `a` differs from `b`. The diagnostic names the fixed
/// `a != b` relation and displays both operands.
pub fn assert_ne(T: type(Eq, Display), a: T, b: T) -> Unit {
    panic.assert_ne(T, a, b)
    return
}

/// Returns the success value of `result`, or terminates with `expected Ok`
/// and the displayed error.
pub fn expect_ok(T: type, E: type(Display), take result: Result(T, E)) -> T {
    match result {
        Ok(value) => { return value }
        Err(error) => { panic.panic("expected Ok\n  error: ".concat(error.display())) }
    }
}

/// Returns the error value of `result`, or terminates with `expected Err`
/// when the result is `Ok`. An `Ok` payload is discarded by the terminating
/// path, where Alder cleanup does not run.
pub fn expect_err(T: type, E: type, take result: Result(T, E)) -> E {
    match result {
        Ok(_) => { panic.panic("expected Err, found Ok") }
        Err(error) => { return error }
    }
}

/// Creates a temporary file, terminating on setup failure, and returns the
/// affine owner. The caller must consume it, explicitly keep it, or let its
/// cleanup remove it.
pub fn temp_file(I: type(Io), io: I, prefix: String) -> fs.TempFile(I) {
    match fs.TempFile.new(io, prefix) {
        Ok(value) => { return value }
        Err(error) => { panic.panic("std.test.temp_file: ".concat(error.display())) }
    }
}

/// Creates a temporary directory, terminating on setup failure, and returns
/// the affine owner. The caller must consume it, explicitly keep it, or let
/// its cleanup remove the tree.
pub fn temp_dir(I: type(Io), io: I, prefix: String) -> fs.TempDir(I) {
    match fs.TempDir.new(io, prefix) {
        Ok(value) => { return value }
        Err(error) => { panic.panic("std.test.temp_dir: ".concat(error.display())) }
    }
}

/// One seeded test case: its zero-based position and an independently drawn
/// 64-bit seed. Cases are plain copyable values.
pub type Case {
    pub index: U64
    pub seed: U64
}

/// Builds `count` deterministic cases from one SplitMix64 stream. The same
/// `(count, seed)` pair produces the same cases on every target and in every
/// process, so a failed case can be replayed by its index and seed.
pub fn cases(count: U64, seed: U64) -> Vec(Case) {
    var generated: Vec(Case) = Vec.new(Case)
    var rng = random.Rng.seeded(seed)
    var index: U64 = 0
    while index < count {
        generated.push(Case(index: index, seed: rng.next_u64()))
        index = index + 1
    }
    return generated
}

/// Deterministic asynchronous capability for tests: one worker, a virtual
/// clock, and a seeded generator. Copyable like every `Io` capability.
pub type SimIo {
    origin: U64
    rng: U64
}

impl SimIo {
    /// The virtual clock at zero and the fixed seed 0.
    fn new() -> SimIo {
        return SimIo.seeded(0)
    }

    /// The virtual clock at zero and the given generator seed.
    fn seeded(seed: U64) -> SimIo {
        let raw_handle = unsafe c { simrt.rng_new(seed.to_c_ulonglong()) }
        let handle = raw_handle.to_u64()
        if handle == 0 {
            panic.panic("std.test.SimIo: random generator allocation failed")
        }
        unsafe c { simrt.install_hooks() }
        let origin_raw = unsafe c { simrt.clock_now() }
        return SimIo(origin: origin_raw.to_u64(), rng: handle)
    }
}

fn sim_stdout(data: [U8]) -> Result(U64, IoError) {
    let rc = unsafe c { simrt.write_stdout(data, data.len().to_c_ulonglong()) }
    if rc.to_i32() != 0 { return Err(IoError.last()) }
    return Ok(data.len())
}

fn sim_stderr(data: [U8]) -> Result(U64, IoError) {
    let rc = unsafe c { simrt.write_stderr(data, data.len().to_c_ulonglong()) }
    if rc.to_i32() != 0 { return Err(IoError.last()) }
    return Ok(data.len())
}

impl Io for SimIo {
    fn open(self, path: Path, mode: FileMode) -> Result(HostFile, IoError) {
        return Err(Unsupported)
    }

    fn read(self, mut file: HostFile, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return Err(Unsupported)
    }

    fn write(self, mut file: HostFile, data: [U8]) -> Result(U64, IoError) {
        return Err(Unsupported)
    }

    fn seek(self, mut file: HostFile, from: SeekFrom) -> Result(U64, IoError) {
        return Err(Unsupported)
    }

    fn close(self, take file: HostFile) -> Result(Unit, IoError) {
        file.cleanup()
        return Err(Unsupported)
    }

    fn sync(self, mut file: HostFile) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn stat(self, mut file: HostFile) -> Result(FileStat, IoError) {
        return Err(Unsupported)
    }

    fn stat_path(self, path: Path) -> Result(FileStat, IoError) {
        return Err(Unsupported)
    }

    fn lstat(self, path: Path) -> Result(FileStat, IoError) {
        return Err(Unsupported)
    }

    fn set_permissions(self, mut file: HostFile, mode: U32) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn rename(self, from: Path, to: Path) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn remove(self, path: Path) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn remove_directory(self, path: Path) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn make_directory(self, path: Path) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn canonicalize(self, path: Path) -> Result(Path, IoError) {
        return Err(Unsupported)
    }

    fn open_directory(self, path: Path) -> Result(HostDirectory, IoError) {
        return Err(Unsupported)
    }

    fn read_directory(self, mut directory: HostDirectory) -> Result(Option(DirEntry), IoError) {
        return Err(Unsupported)
    }

    fn close_directory(self, take directory: HostDirectory) -> Result(Unit, IoError) {
        directory.cleanup()
        return Err(Unsupported)
    }

    fn read_stdin(self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return Err(Unsupported)
    }

    fn write_stdout(self, data: [U8]) -> Result(U64, IoError) {
        return sim_stdout(data)
    }

    fn write_stderr(self, data: [U8]) -> Result(U64, IoError) {
        return sim_stderr(data)
    }

    fn spawn(self, program: OsString, arguments: Vec(OsString), set_environment: Vec(OsString), remove_environment: Vec(OsString), clear_environment: Bool, working_directory: Option(Path), stdin_mode: U8, stdout_mode: U8, stderr_mode: U8) -> Result(HostChild, IoError) {
        return Err(Unsupported)
    }

    fn wait(self, pid: I32) -> Result(ChildStatus, IoError) {
        return Err(Unsupported)
    }

    fn kill(self, pid: I32) -> Result(Unit, IoError) {
        return Err(Unsupported)
    }

    fn poll(self, mut first: HostFile, mut second: HostFile, timeout_ms: I32) -> Result(PollPair, IoError) {
        return Err(Unsupported)
    }

    fn wait_signal(self, signal: I32, timeout_ms: I32) -> Result(Bool, IoError) {
        return Err(Unsupported)
    }

    fn sleep(self, seconds: U64, nanos: U32) -> Unit {
        let delay = Duration.of_parts(seconds, nanos).as_nanos()
        let registered = unsafe c { simrt.timer_in(delay.to_c_ulonglong()) }
        if registered.to_i32() == 0 {
            panic.panic("std.test.SimIo: sleep deadline is unavailable")
        }
        unsafe c { simrt.park() }
        return
    }

    fn monotonic(self) -> Timestamp {
        let raw_now = unsafe c { simrt.clock_now() }
        let elapsed = raw_now.to_u64() - self.origin
        return Timestamp(seconds: (elapsed / 1000000000).to_i64_wrapping(), nanos: (elapsed % 1000000000).to_u32_wrapping())
    }

    fn wallclock(self) -> Timestamp {
        let raw_now = unsafe c { simrt.clock_now() }
        let elapsed = raw_now.to_u64() - self.origin
        return Timestamp(seconds: (elapsed / 1000000000).to_i64_wrapping(), nanos: (elapsed % 1000000000).to_u32_wrapping())
    }

    fn random_bytes(self, buffer: MutSlice(U8)) -> Unit {
        unsafe c { simrt.rng_fill(self.rng.to_c_ulonglong(), buffer, buffer.len().to_c_ulonglong()) }
        return
    }

    fn check_cancel(self) -> Unit {
        unsafe c { simrt.yield_current() }
        unsafe c { simrt.park() }
        return
    }
}

impl AsyncIo for SimIo {
}
