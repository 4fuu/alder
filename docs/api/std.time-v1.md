# `std.time` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for time values. It is normative
together with the executable example
[`examples/std.time-v1.al`](examples/std.time-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/time.al`.

Snapshot v1 covers monotonic `Instant`, wall-clock `SystemTime`, checked
`Duration`, capability-mediated `sleep`, and timezone-independent UTC civil
conversion. Calendar and timezone databases are versioned distribution data
and stay outside v1; `to_utc` is pure integer civil math and needs no
database. Reading a clock or sleeping waits on the host, so both take the
capability, and the wrappers are written once against `I: type(io.Io)`.

## Signatures

```alder
module std.time

import std.io

/// A point of the monotonic clock. Values from one process are comparable;
/// only differences are meaningful, never the raw count.
pub type Instant {
    // private: value
}

impl Instant {
    /// Reads the monotonic clock through the capability.
    pub fn now(I: type(io.Io), io: I) -> Instant
    /// The duration from `earlier` to this instant. Monotonic clock reads
    /// never go backwards, so an inverted pair terminates through the
    /// invariant path; `checked_duration_since` is the total form.
    pub fn duration_since(self, earlier: Instant) -> Duration
    /// `Some` of the duration when this instant is not before `earlier`,
    /// `None` otherwise.
    pub fn checked_duration_since(self, earlier: Instant) -> Option(Duration)
}

/// A point of the wall clock, counting from the platform epoch. Wall-clock
/// reads may go backwards across calls; nothing here assumes ordering.
pub type SystemTime {
    // private: value
}

impl SystemTime {
    /// Reads the wall clock through the capability.
    pub fn now(I: type(io.Io), io: I) -> SystemTime
    /// Builds a wall-clock point from seconds since the epoch plus
    /// sub-second nanos. Nanos at or above one billion terminate through
    /// the invariant path.
    pub fn from_unix(seconds: I64, nanos: U32) -> SystemTime
    /// Whole seconds since the epoch; negative before the epoch.
    pub fn unix_seconds(self) -> I64
    /// The timezone-independent UTC civil breakdown.
    pub fn to_utc(self) -> UtcDateTime
}

/// One UTC civil date and time. Fields are plain data with documented
/// ranges: month and day start at 1, hour/minute/second start at 0.
pub type UtcDateTime {
    year: I64
    month: U8
    day: U8
    hour: U8
    minute: U8
    second: U8
    nanos: U32
}

/// A non-negative span of time. Stored as normalized seconds plus nanos
/// (`nanos` below one billion); arithmetic is checked and terminates on
/// overflow through the ordinary checked-integer path.
pub type Duration {
    // private: seconds, nanos
}

impl Duration {
    pub fn seconds(value: U64) -> Duration
    pub fn millis(value: U64) -> Duration
    pub fn micros(value: U64) -> Duration
    pub fn nanos(value: U64) -> Duration
    /// Builds from parts; nanos at or above one billion terminate through
    /// the invariant path. The named constructors above are the total form.
    pub fn of_parts(seconds: U64, nanos: U32) -> Duration
    /// The zero duration.
    pub fn zero() -> Duration
    /// Checked sum; overflow terminates.
    pub fn plus(self, other: Duration) -> Duration
    /// Difference saturating at zero.
    pub fn saturating_sub(self, other: Duration) -> Duration
    pub fn is_zero(self) -> Bool
    /// Whole seconds, truncating downward.
    pub fn as_seconds(self) -> U64
    /// Whole milliseconds, truncating downward.
    pub fn as_millis(self) -> U64
    /// Whole microseconds, truncating downward.
    pub fn as_micros(self) -> U64
    /// Total nanoseconds; overflow of `U64` terminates.
    pub fn as_nanos(self) -> U64
}

impl time {
    /// Sleeps for the duration without waking early. A zero duration
    /// yields one scheduler yield on the host, not a busy spin.
    pub fn sleep(I: type(io.Io), io: I, duration: Duration)
}
```

Equality for `Instant`, `SystemTime`, and `Duration` is structural over their
private parts. `Display` for all three lands with the sysroot formatting
snapshot and is additive. No time operation returns an error in v1: supported
targets implement the underlying clocks and sleeps without failing calls, and
invariant violations terminate as documented.

## Contracts

- `now` and `sleep` take the capability; the wrappers are written once against
  `I: type(io.Io)`, so a `Blocking` instantiation lowers to direct host calls
  and a future `AsyncIo` instantiation suspends at the same calls.
- `Instant` differences are reliable; `Instant` raw values are not. Nothing
  may persist an `Instant` beyond the process.
- `SystemTime` is wall-clock and may step backwards; durations between
  `SystemTime` points must use explicit checked forms in caller code, which
  v1 does not provide (wall-clock differences are caller policy).
- `Duration` is always non-negative; negative spans are unrepresentable.
  Overflow terminates like the language's checked integer arithmetic.
- `to_utc` is deterministic pure integer civil conversion (proleptic
  Gregorian), needs no database, and never reads the host.
- `sleep` never wakes early; shortening a sleep is caller policy (v1 provides
  no early-wake form; cancellation-aware waiting arrives with Milestone 9).
- Tests read the monotonic clock only for lower bounds (a sleep of at least
  the requested span), so timing jitter cannot change a checksum.

## Example

The example below is the complete content that lands as
`examples/std.time-v1.al` with the implementation commit. Every checksum
contribution comes from fixed inputs or lower bounds, so the result is
deterministic.

```alder
module hello.std_time_example

import std.io
import std.time

// The executable std.time v1 snapshot example. Fixed civil conversion and
// duration math dominate the checksum; host reads appear only as lower
// bounds.

pub fn std_time_example(io: io.Blocking) -> I64 {
    var total: I64 = 0

    // Pure UTC civil conversion of a fixed instant:
    // 2000-03-01T00:00:00.5 UTC is 951868800 seconds plus 500000000 nanos.
    let fixed = time.SystemTime.from_unix(951868800, 500000000)
    let civil = fixed.to_utc()
    total = total + civil.year
    total = total + civil.month.to_i64() * 10
    total = total + civil.day.to_i64() * 100
    total = total + civil.hour.to_i64() * 1000
    total = total + civil.minute.to_i64() * 10000
    total = total + civil.second.to_i64() * 100000
    total = total + civil.nanos.to_i64() / 1000000

    // Fixed duration arithmetic.
    let step = time.Duration.millis(1500)
    let twice = step.plus(step)
    if twice.as_millis() == 3000 { total = total + 1 }
    let trimmed = twice.saturating_sub(time.Duration.seconds(2))
    if trimmed.as_millis() == 500 { total = total + 10 }
    let floor = time.Duration.millis(1).saturating_sub(time.Duration.seconds(2))
    if floor.is_zero() { total = total + 100 }

    // A sleep of a fixed span completes after at least that span.
    let started = time.Instant.now(io)
    time.sleep(io, time.Duration.millis(5))
    let finished = time.Instant.now(io)
    let waited = finished.duration_since(started)
    if waited.as_millis() >= 5 { total = total + 1 }

    // Wall-clock access exists and round-trips through its fixed
    // constructor accessors.
    if time.SystemTime.from_unix(0, 0).unix_seconds() == 0 { total = total + 1 }

    return total
}
```

## Dependencies and sequencing

- Integer conversions in the example use the settled builtin surface: total `to_i64()` for all-fitting pairs (`U8`/`U32` into `I64`), with `to_i64_checked()` available where a value may not fit; the methods land with the sysroot thread's numeric surface after the String/Bytes byte work.
- Builds on the `std.io` capability (`monotonic`, `wallclock`, `sleep`) and
  the C-binding thread's checked raw-integer conversions inside the
  capability implementation.
- `Timestamp` parts come from `std.io`; this module owns every public time
  type, so `std.io` never imports `std.time` (no cycle).
- The civil conversion needs no C support and no sysroot text operations; the
  module can land as soon as `std.io`'s capability ops exist.
