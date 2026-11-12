# `std.test` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; library slice implemented**

This is the versioned public snapshot for the runner-independent testing
helpers. It is normative together with the executable example
[`examples/std.test-v1.al`](examples/std.test-v1.al). The module lives at
`<sysroot>/std/test.al`.

Snapshot v1 covers the part of `std.test` that needs no test runner:
assertions, expected-result extraction, temporary-resource constructors, and
deterministic seeded cases. Top-level `test` declarations, discovery and
reporting, expected-panic tests, fuzz corpora, subprocess isolation, `SimIo`,
and source-expression capture are intentionally outside this snapshot. They
require `alder test` or the async runtime and belong to the tooling milestones
and Milestone 9. The required list in
[the standard library](../standard-library.md#testing-and-documentation)
remains the Alder 1.0 target; this snapshot fixes only the library slice that
M8 can install.

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
- `expect_err`'s `T` must be copyable. Its `Ok` arm discards the payload on a
  terminating path, where Alder cleanup does not run, so an affine `T` is
  rejected at the call; use `match` directly when the success payload owns a
  resource. `expect_ok` returns an affine `T` by transfer and has no such
  restriction.
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
