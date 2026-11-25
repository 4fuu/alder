# `std.test` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; library slice implemented; Milestone 9 additive section recorded**

This is the versioned public snapshot for the runner-independent testing
helpers. It is normative together with the executable example
[`examples/std.test-v1.al`](examples/std.test-v1.al). The module lives at
`<sysroot>/std/test.al`.

Snapshot v1 covers the part of `std.test` that needs no test runner:
assertions, expected-result extraction, temporary-resource constructors, and
deterministic seeded cases. Top-level `test` declarations, discovery and
reporting, expected-panic tests, fuzz corpora, subprocess isolation, `SimIo`,
and source-expression capture are intentionally outside this M8 slice. They
require `alder test` or the async runtime and belong to the tooling milestones
and Milestone 9. The required list in
[the standard library](../standard-library.md#testing-and-documentation)
remains the Alder 1.0 target; this snapshot fixes only the library slice that
M8 can install. The additive
[Milestone 9 `SimIo` section](#milestone-9-addition-simio) at the end of this
file records that surface; nothing else in this snapshot changes.

Every failing helper terminates through `core.panic.panic`: the process exits
with status 101, writes the documented `panic: ` diagnostic to standard error,
and does not run Alder cleanup scopes. The value-returning helpers call that
resolved function directly as their last statement, so the checker treats the
call as a diverging path end. `fail`, `assert`, `assert_eq`, and `assert_ne`
are ordinary `Unit` functions: calling one is not a diverging path end for the
caller.

## Signatures

```alder
module std.test

import std.fs
import std.io { Io }
import std.random

/// Terminates the process with `panic: <message>`.
pub fn fail(message: String)

/// Terminates with `panic: assertion failed: <message>` unless `condition`
/// is true.
pub fn assert(condition: Bool, message: String)

/// Terminates unless `a == b`, displaying both operands.
pub fn assert_eq(T: type(Eq, Display), a: T, b: T)

/// Terminates unless `a != b`, displaying both operands.
pub fn assert_ne(T: type(Eq, Display), a: T, b: T)

/// Returns the `Ok` payload; an `Err` terminates with `expected Ok` and the
/// displayed error.
pub fn expect_ok(T: type, E: type(Display), take result: Result(T, E)) -> T

/// Returns the `Err` payload; an `Ok` terminates with
/// `expected Err, found Ok`.
pub fn expect_err(T: type, E: type, take result: Result(T, E)) -> E

/// Creates an affine temporary file, terminating on setup failure.
pub fn temp_file(I: type(Io), io: I, prefix: String) -> fs.TempFile(I)

/// Creates an affine temporary directory, terminating on setup failure.
pub fn temp_dir(I: type(Io), io: I, prefix: String) -> fs.TempDir(I)

/// One seeded test case: its zero-based position and a drawn 64-bit seed.
pub type Case {
    pub index: U64
    pub seed: U64
}

/// Builds `count` deterministic cases from one SplitMix64 stream.
pub fn cases(count: U64, seed: U64) -> Vec(Case)
```

## Failure formats

`fail(message)` writes exactly:

```text
panic: <message>
```

`assert(false, message)` writes exactly:

```text
panic: assertion failed: <message>
```

`assert_eq` and `assert_ne` use the same fixed formats as
[`core.panic`](core.panic-v1.md): the relation is named as `a == b` or
`a != b`, and both operands are displayed on labeled lines. `expect_ok` on an
error writes:

```text
panic: expected Ok
  error: <display(error)>
```

`expect_err` on a success writes:

```text
panic: expected Err, found Ok
```

A temporary-resource setup failure writes `panic: std.test.temp_file: ` or
`panic: std.test.temp_dir: ` followed by the displayed `std.io` error.

The labels are fixed parameter names. Capturing the caller's source expression
requires the test runner's source map and is deferred.

## Contracts

- A passing helper writes nothing and returns normally. `expect_ok` and
  `expect_err` return the payload they name exactly once, moving an affine
  payload to the caller.
- `expect_err` does not format the discarded `Ok` payload, so `T` needs no
  `Display` bound. `expect_ok` displays the error, so `E: type(Display)`.
  Both take the result by `take`: an affine error transfers to the helper,
  and a copyable result leaves the caller's binding usable.
- `expect_err`'s `Ok` arm discards the payload on a terminating path, where
  Alder cleanup does not run. A live affine payload needs no transfer on that
  path, matching the panic divergence contract; `expect_ok` returns an affine
  `T` by transfer.
- `temp_file` and `temp_dir` return affine owners built by `std.fs`; cleanup
  closes and removes them unless the caller explicitly keeps them. A setup
  failure is an invariant violation: ordinary recoverable code uses
  `std.fs.temp_file`/`temp_dir` and handles the `Result` itself.
- `cases(count, seed)` uses `std.random.Rng.seeded(seed)` and draws one
  64-bit value per case in order. For a fixed `(count, seed)` the sequence is
  identical on every target and in every process; `index` is the zero-based
  position. The helper allocates one `Vec(Case)`.
- No helper performs I/O except the temporary-resource constructors, which use
  the supplied `std.io` capability. The assertion and expected-result helpers
  are pure apart from termination.
- The module is imported explicitly; it is not part of the prelude. It adds no
  runtime support and uses the existing `core.panic` and `std.fs` owners.

## Example

The example below is the complete content of
`examples/std.test-v1.al`. It exercises every passing path; failure paths run
in subprocess tests that observe status 101 and the documented stderr.

## Milestone 9 addition: `SimIo`

Status: **Milestone 9 additive section; not implemented**

This section is the additive Milestone 9 surface of this snapshot. It records
`std.test.SimIo`, the deterministic `AsyncIo` used by tests, and changes no
Milestone 8 declaration. It is normative together with the executable example
`examples/std.test.simio-v1.al`, which lands in the module's implementation
commit: the docs example runner resolves installed sysroot modules, so the file
cannot precede the implementation. The
[cross-cutting async rules](std.task-v1.md#cross-cutting-async-rules) and
[spelling choices](std.task-v1.md#v1-spelling-choices) apply.

### Signatures

```alder
module std.test

import std.io { AsyncIo, Io }

/// Deterministic async capability for tests: one worker, a virtual clock,
/// and a seeded generator. Copyable like every `Io` capability.
pub type SimIo {
    // private: scheduler, clock, generator
}

impl SimIo {
    /// The virtual clock at zero and the fixed seed 0.
    fn new() -> SimIo
    /// The virtual clock at zero and the given generator seed.
    fn seeded(seed: U64) -> SimIo
}

impl Io for SimIo
impl AsyncIo for SimIo
```

### Contracts

- `SimIo` runs every task of a test on one worker. Runnable tasks run one at
  a time in deterministic readiness order, and `new()` is exactly
  `seeded(0)`, so a fixed program produces the same results, the same
  scheduling, and the same random bytes on every run, target, and process.
- Both clocks are virtual. The monotonic and wall clocks start at zero and at
  a fixed documented epoch (the Unix epoch), and they advance only when every
  live task is blocked on time: the clock jumps to the earliest pending
  deadline. A deadline at the current instant is a time block, so a
  zero-duration sleep advances nothing.
- `random_bytes` draws from one SplitMix64 stream seeded by `seeded`, so it is
  deterministic byte for byte. It never observes host entropy.
- Every `Io` operation outside the clock, sleep, randomness, scheduler, and
  standard-stream surface returns `Err(IoError.Unsupported)`: host files,
  directories, signals, `poll`, and child processes are not simulated in v1.
  Standard output and error write through to the host streams; capture is
  runner-level work. `read_stdin` returns `Unsupported`, so a test reads
  deterministic input from values it constructs. A test that needs a host
  resource uses `Blocking` or a real `Evented`.
- Deadlock: when no task is runnable, no timer is pending, and live tasks
  remain blocked, `SimIo` terminates the test through `core.panic.panic` with
  the fixed first line `panic: SimIo deadlock` followed by one
  `  blocked task <index>` line per blocked task, in spawn order with
  one-based indices. The listing is the failure diagnostic; a program must
  not depend on it as data.
- `SimIo` always uses one worker and ignores `std.io.ExecutorConfig`.
  Production code must not depend on its readiness order; only its own
  determinism is guaranteed.

### Example

The example below is the complete content that lands as
`examples/std.test.simio-v1.al` with the implementation commit. Two sleeps
advance the virtual clock in deadline order, and a timeout observes the same
clock.

```alder
module hello.std_simio_example

import std.io { AsyncIo, Io }
import std.task { TaskGroup, Timeout, timeout }
import std.test { SimIo }
import std.time { Duration, Instant, sleep }

// The executable std.test.SimIo v1 snapshot example: two sleeps advance the
// virtual clock in deadline order and a timeout observes the same clock.

fn nap(I: type(Io), io: I, millis: U64) -> U64 {
    sleep(io, Duration.millis(millis))
    return millis
}

pub fn std_simio_example() -> U64 {
    let sim = SimIo.seeded(0)
    let started = Instant.now(sim)
    using tasks = TaskGroup.new(sim)
    let short = tasks.spawn(nap(sim, 30))
    let long = tasks.spawn(nap(sim, 120))
    let first = await short
    let second = await long
    let elapsed = Instant.now(sim).duration_since(started)
    var total: U64 = first + second
    if elapsed.as_millis() == 120 { total = total + 1 }
    let timed = timeout(sim, Duration.millis(10), nap(sim, 1000))
    match timed {
        Ok(value) => { total = total + value }
        Err(Timeout) => { total = total + 2 }
    }
    return total
}
```

### Dependencies and sequencing

- Milestone 9 gate 9.7 implements `SimIo` virtual time, quiescence, and
  deadlock reporting.
- `SimIo` is an `AsyncIo`, so it requires the `Io` implementation and the
  `AsyncIo`/`BlockingIo` checker invariant recorded in
  [`std.io` v1](std.io-v1.md#milestone-9-addition-evented-and-check_cancel).
- The deadlock diagnostic uses the existing `core.panic` path; the test
  runner's capture and reporting are Milestone 11 work.
