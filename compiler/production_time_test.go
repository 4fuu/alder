package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// UTC vectors are derived independently from the proleptic Gregorian
// calendar with Python's datetime: the epoch boundary, a pre-epoch second,
// the snapshot instant, a pre-1970 landing, leap days in a leap century and
// in 2024, a non-leap 2100, and year boundaries. Duration arithmetic uses
// fixed parts so no host timing enters the checksum.
const timeVectorsProgram = `module hello.main

import std.io { Blocking, Io, Timestamp }
import std.time

fn utc_of(seconds: I64) -> time.UtcDateTime {
    return time.SystemTime.from_unix(seconds, 0).to_utc()
}

fn zero_sleep(I: type(Io), cap: I) -> Unit {
    time.sleep(cap, time.Duration.zero())
    return
}

fn main() -> I32 {
    let epoch = utc_of(0)
    if epoch.year != 1970 || epoch.month != 1 || epoch.day != 1 { return 1 }
    if epoch.hour != 0 || epoch.minute != 0 || epoch.second != 0 { return 2 }

    let before = utc_of(-1)
    if before.year != 1969 || before.month != 12 || before.day != 31 { return 3 }
    if before.hour != 23 || before.minute != 59 || before.second != 59 { return 4 }

    let fixed = time.SystemTime.from_unix(951868800, 500000000).to_utc()
    if fixed.year != 2000 || fixed.month != 3 || fixed.day != 1 { return 5 }
    if fixed.nanos != 500000000 { return 6 }

    let landing = utc_of(-14182940)
    if landing.year != 1969 || landing.month != 7 || landing.day != 20 { return 7 }
    if landing.hour != 20 || landing.minute != 17 || landing.second != 40 { return 8 }

    let leap = utc_of(1709210096)
    if leap.year != 2024 || leap.month != 2 || leap.day != 29 { return 9 }
    if leap.hour != 12 || leap.minute != 34 || leap.second != 56 { return 10 }

    let century = utc_of(4107542400)
    if century.year != 2100 || century.month != 3 || century.day != 1 { return 11 }

    let leap_century = utc_of(951782400)
    if leap_century.year != 2000 || leap_century.month != 2 || leap_century.day != 29 { return 12 }

    let year_end = utc_of(1704067199)
    if year_end.year != 2023 || year_end.month != 12 || year_end.day != 31 { return 13 }
    if year_end.hour != 23 || year_end.minute != 59 || year_end.second != 59 { return 14 }

    let year_start = utc_of(1704067200)
    if year_start.year != 2024 || year_start.month != 1 || year_start.day != 1 { return 15 }

    let old = utc_of(-2208988800)
    if old.year != 1900 || old.month != 1 || old.day != 1 { return 16 }

    let step = time.Duration.millis(1500)
    let twice = step.plus(step)
    if twice.as_millis() != 3000 { return 20 }
    if twice.as_seconds() != 3 { return 21 }
    if time.Duration.micros(1500).as_micros() != 1500 { return 22 }
    if time.Duration.nanos(1500).as_nanos() != 1500 { return 23 }
    if time.Duration.of_parts(2, 500000000).as_millis() != 2500 { return 24 }
    let carried = time.Duration.of_parts(0, 600000000).plus(time.Duration.of_parts(0, 600000000))
    if carried.as_seconds() != 1 || carried.as_millis() != 1200 { return 25 }
    let trimmed = twice.saturating_sub(time.Duration.seconds(2))
    if trimmed.as_millis() != 1000 { return 26 }
    if !time.Duration.millis(1).saturating_sub(time.Duration.seconds(2)).is_zero() { return 27 }
    if time.Duration.seconds(3).saturating_sub(time.Duration.seconds(3)).is_zero() != true { return 28 }

    let cap = Blocking()
    let started = time.Instant.now(cap)
    time.sleep(cap, time.Duration.millis(2))
    let finished = time.Instant.now(cap)
    let waited = finished.duration_since(started)
    if waited.as_millis() < 2 { return 30 }
    if finished.checked_duration_since(started) == None { return 31 }
    zero_sleep(cap)

    let wall = time.SystemTime.now(cap)
    if wall.unix_seconds() < 1700000000 { return 32 }
    if wall.to_utc().year < 2023 { return 33 }
    let signed = Timestamp(seconds: -1, nanos: 0)
    if signed.seconds != -1 { return 34 }
    return 0
}
`

func TestTimeProductionVectors(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	files := map[string]string{
		"alder.toml":  "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": timeVectorsProgram,
	}
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("std.time vectors: %+v stderr=%s", result, result.stderr)
	}
}
