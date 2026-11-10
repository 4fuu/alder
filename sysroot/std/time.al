module std.time

// The Milestone 8 time surface (docs/api/std.time-v1.md): monotonic
// `Instant`, wall-clock `SystemTime`, normalized `Duration`, and `sleep`,
// each through the `Io` capability (written once against
// `I: type(io.Io)`; the `Blocking` instantiation lowers to direct host
// calls, the future `AsyncIo` one suspends at the same calls).
//
// The host clock and sleep bind through the binding block below:
// `clock_gettime` for both clocks and `nanosleep` for `sleep`. The clock
// ids are bound object-like constants (the C4 binding model checks them
// against the real header through the probe unit), so no numeric id is
// hardcoded.
//
// `sleep` re-requests the `nanosleep` remainder until it reports a full
// sleep, so EINTR cannot shorten a sleep; a request that does not shrink
// terminates through the invariant path, so no failure loops. `to_utc` is
// the deterministic proleptic-Gregorian integer conversion, written in
// pure Alder over `unix_seconds`, never a host read.
//
// Wrapper bodies land with the checked raw-scalar conversions (C6) and
// verified record field access (C7 batch); until then this file carries
// the binding block only.

import c "time.h" as ctime {
    scalar type Time = "time_t"

    record type Timespec = "struct timespec" {
        seconds: Time = "tv_sec"
        nanos: c.Long = "tv_nsec"
    }

    /// `CLOCK_REALTIME`: the wall clock `SystemTime.now` reads.
    const clock_realtime = "CLOCK_REALTIME": c.Int

    /// `CLOCK_MONOTONIC`: the clock `Instant.now` reads.
    const clock_monotonic = "CLOCK_MONOTONIC": c.Int

    /// POSIX `clock_gettime`. Nonzero return is a host failure; the
    /// wrapper terminates through the invariant path.
    raw fn get_time = "clock_gettime"(
        clock: c.Int,
        value: c.Ptr(Timespec),
    ) -> c.Int

    /// POSIX `nanosleep`: sleeps the request span or until a signal,
    /// storing the unelapsed remainder. Zero return means the full span
    /// elapsed. The wrapper re-requests the remainder on nonzero.
    raw fn sleep_request = "nanosleep"(
        request: c.ConstPtr(Timespec),
        remaining: c.Ptr(Timespec),
    ) -> c.Int
}
