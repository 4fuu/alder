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
import std.io { Io }
import std.random

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
/// when the result is `Ok`.
pub fn expect_err(T: type, E: type, take result: Result(T, E)) -> E {
    match result {
        // The Ok payload is discarded. A copyable T is the supported case; an
        // affine T is rejected at the call because no cleanup runs on the
        // terminating path, so the caller must use match when Ok owns a
        // resource.
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
