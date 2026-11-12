module std.time

import std.io { Io, Timestamp }
import core.panic { panic }

// The Milestone 8 std.time v1 surface: a monotonic Instant, a wall-clock
// SystemTime, a checked non-negative Duration, capability-mediated sleep, and
// database-free UTC civil conversion. Clock reads and sleeps go through the
// std.io capability, so a Blocking instantiation is a direct host call and a
// future AsyncIo instantiation suspends at the same place.

/// One UTC civil date and time in the proleptic Gregorian calendar.
pub type UtcDateTime {
    pub year: I64
    pub month: U8
    pub day: U8
    pub hour: U8
    pub minute: U8
    pub second: U8
    pub nanos: U32
}

/// A non-negative span stored as normalized seconds plus nanos below one
/// billion. Arithmetic is checked and terminates on overflow.
pub type Duration {
    seconds: U64
    nanos: U32
}

impl Duration {
    fn seconds(value: U64) -> Duration {
        return Duration(seconds: value, nanos: 0)
    }

    fn millis(value: U64) -> Duration {
        return Duration(seconds: value / 1000, nanos: (value % 1000).to_u32_wrapping() * 1000000)
    }

    fn micros(value: U64) -> Duration {
        return Duration(seconds: value / 1000000, nanos: (value % 1000000).to_u32_wrapping() * 1000)
    }

    fn nanos(value: U64) -> Duration {
        return Duration(seconds: value / 1000000000, nanos: (value % 1000000000).to_u32_wrapping())
    }

    fn of_parts(seconds: U64, nanos: U32) -> Duration {
        if nanos >= 1000000000 { panic("duration nanos out of range") }
        return Duration(seconds: seconds, nanos: nanos)
    }

    fn zero() -> Duration {
        return Duration(seconds: 0, nanos: 0)
    }

    fn plus(self, other: Duration) -> Duration {
        let combined = self.nanos + other.nanos
        var carry: U32 = 0
        var nanos = combined
        if combined >= 1000000000 {
            carry = 1
            nanos = combined - 1000000000
        }
        return Duration(seconds: self.seconds + other.seconds + carry.to_u64(), nanos: nanos)
    }

    fn saturating_sub(self, other: Duration) -> Duration {
        if self.seconds < other.seconds { return Duration.zero() }
        if self.seconds == other.seconds && self.nanos < other.nanos { return Duration.zero() }
        if self.nanos >= other.nanos {
            return Duration(seconds: self.seconds - other.seconds, nanos: self.nanos - other.nanos)
        }
        return Duration(seconds: self.seconds - other.seconds - 1, nanos: self.nanos + 1000000000 - other.nanos)
    }

    fn is_zero(self) -> Bool {
        return self.seconds == 0 && self.nanos == 0
    }

    fn as_seconds(self) -> U64 {
        return self.seconds
    }

    fn as_millis(self) -> U64 {
        return self.seconds * 1000 + self.nanos.to_u64() / 1000000
    }

    fn as_micros(self) -> U64 {
        return self.seconds * 1000000 + self.nanos.to_u64() / 1000
    }

    fn as_nanos(self) -> U64 {
        return self.seconds * 1000000000 + self.nanos.to_u64()
    }
}

/// A point of the monotonic clock. Only differences are meaningful.
pub type Instant {
    value: Timestamp
}

impl Instant {
    fn now(I: type(Io), io: I) -> Instant {
        return Instant(value: io.monotonic())
    }

    fn checked_duration_since(self, earlier: Instant) -> Option(Duration) {
        if self.value.seconds < earlier.value.seconds { return None }
        if self.value.seconds == earlier.value.seconds && self.value.nanos < earlier.value.nanos { return None }
        let seconds = self.value.seconds - earlier.value.seconds
        if self.value.nanos >= earlier.value.nanos {
            return Some(Duration(seconds: seconds, nanos: self.value.nanos - earlier.value.nanos))
        }
        return Some(Duration(seconds: seconds - 1, nanos: self.value.nanos + 1000000000 - earlier.value.nanos))
    }

    fn duration_since(self, earlier: Instant) -> Duration {
        if self.value.seconds < earlier.value.seconds { panic("instant order violated") }
        if self.value.seconds == earlier.value.seconds && self.value.nanos < earlier.value.nanos { panic("instant order violated") }
        let seconds = self.value.seconds - earlier.value.seconds
        if self.value.nanos >= earlier.value.nanos {
            return Duration(seconds: seconds, nanos: self.value.nanos - earlier.value.nanos)
        }
        return Duration(seconds: seconds - 1, nanos: self.value.nanos + 1000000000 - earlier.value.nanos)
    }
}

/// A point of the wall clock, counting from the Unix epoch. Wall-clock reads
/// may step backwards; differences are caller policy.
pub type SystemTime {
    seconds: I64
    nanos: U32
}

impl SystemTime {
    fn now(I: type(Io), io: I) -> SystemTime {
        let stamp = io.wallclock()
        return SystemTime(seconds: stamp.seconds.to_i64_wrapping(), nanos: stamp.nanos)
    }

    fn from_unix(seconds: I64, nanos: U32) -> SystemTime {
        if nanos >= 1000000000 { panic("system time nanos out of range") }
        return SystemTime(seconds: seconds, nanos: nanos)
    }

    fn unix_seconds(self) -> I64 {
        return self.seconds
    }

    fn to_utc(self) -> UtcDateTime {
        let days = floor_div(self.seconds, 86400)
        let within = self.seconds - days * 86400
        let hour = (within / 3600).to_u8_wrapping()
        let minute = ((within % 3600) / 60).to_u8_wrapping()
        let second = (within % 60).to_u8_wrapping()
        let civil = civil_from_days(days)
        return UtcDateTime(year: civil.year, month: civil.month, day: civil.day, hour: hour, minute: minute, second: second, nanos: self.nanos)
    }
}

/// A civil date without the time of day, used by the day-to-date conversion.
type CivilDate {
    year: I64
    month: U8
    day: U8
}

fn floor_div(value: I64, divisor: I64) -> I64 {
    let quotient = value / divisor
    let remainder = value - quotient * divisor
    if remainder < 0 { return quotient - 1 }
    return quotient
}

// Howard Hinnant's civil_from_days for a day count relative to 1970-01-01,
// written with floor division so pre-epoch instants convert symmetrically.
fn civil_from_days(days: I64) -> CivilDate {
    let shifted = days + 719468
    let era = floor_div(shifted, 146097)
    let day_of_era = shifted - era * 146097
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365
    var year = year_of_era + era * 400
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
    let month_prime = (5 * day_of_year + 2) / 153
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1
    let month_offset = month_prime + 3
    var month = month_offset
    if month_prime >= 10 { month = month_prime - 9 }
    if month <= 2 { year = year + 1 }
    return CivilDate(year: year, month: month.to_u8_wrapping(), day: day.to_u8_wrapping())
}

/// Sleeps for `duration` without waking early. A zero duration yields on the
/// host instead of spinning.
pub fn sleep(I: type(Io), io: I, duration: Duration) -> Unit {
    io.sleep(duration.seconds, duration.nanos)
    return
}
