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
    if trimmed.as_millis() == 1000 { total = total + 10 }
    let floor = time.Duration.millis(1).saturating_sub(time.Duration.seconds(2))
    if floor.is_zero() { total = total + 100 }

    // A sleep of a fixed span completes after at least that span.
    let started = time.Instant.now(io)
    time.sleep(io, time.Duration.millis(5))
    let finished = time.Instant.now(io)
    let waited = finished.duration_since(started)
    if waited.as_millis() >= 5 { total = total + 1 }

    // A timer waits until its monotonic deadline and then reports expired.
    let timer = time.Timer.after(io, time.Duration.millis(2))
    timer.wait(io)
    if timer.expired(io) { total = total + 1000 }

    // Wall-clock access exists and round-trips through its fixed
    // constructor accessors.
    if time.SystemTime.from_unix(0, 0).unix_seconds() == 0 { total = total + 1 }

    return total
}
