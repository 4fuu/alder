package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// M9 gate 9.4c: deterministic structured-concurrency evidence under SimIo.
// Every program is a parameterless main that constructs SimIo and calls a
// suspending helper, so the hosted entry is the async root-as-task path.

func simioE2EProject(body string) map[string]string {
	return map[string]string{
		"alder.toml":  taskManifest,
		"src/main.al": "module hello.main\n\nimport std.io { AsyncIo, Blocking, Io }\nimport std.task { CancellationError, TaskGroup, Timeout, timeout, race, blocking, yield }\nimport std.test { SimIo }\nimport std.time { Duration, Instant, sleep }\n\n" + body,
	}
}

func runSimioE2E(t *testing.T, body string) productionResult {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	return runProductionCompilerEnv(t, exe, t.TempDir(), env, simioE2EProject(body), "run")
}

func expectSimioE2E(t *testing.T, name, body, stdout string) {
	t.Helper()
	res := runSimioE2E(t, body)
	if res.status != 0 || res.stdout != stdout || res.stderr != "" {
		t.Fatalf("%s: %+v", name, res)
	}
}

func TestSimIoEndToEnd(t *testing.T) {
	t.Run("spawn-argument", func(t *testing.T) {
		expectSimioE2E(t, "spawn argument", `fn child(io: SimIo, tag: U8) -> Unit {
    let text: Array(U8, 1) = [tag]
    let _ = io.write_stdout(text.slice(0, 1))
    return
}

fn check(sim: SimIo) -> I32 {
    using tasks = TaskGroup.new(sim)
    tasks.start(child(sim, 65))
    return 0
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "A")
	})

	t.Run("await-return", func(t *testing.T) {
		expectSimioE2E(t, "await return", `fn child() -> U64 { return 42 }

fn check(sim: SimIo) -> I32 {
    using tasks = TaskGroup.new(sim)
    let t = tasks.spawn(child())
    let v = await t
    if v == 42 { return 0 }
    return 70
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "")
	})

	t.Run("nested-groups", func(t *testing.T) {
		expectSimioE2E(t, "nested groups", `fn one() -> U64 { return 11 }
fn two() -> U64 { return 31 }

fn inner(sim: SimIo) -> U64 {
    using tasks = TaskGroup.new(sim)
    let a = tasks.spawn(one())
    let b = tasks.spawn(two())
    return (await a) + (await b)
}

fn outer(sim: SimIo) -> U64 {
    using tasks = TaskGroup.new(sim)
    let t = tasks.spawn(inner(sim))
    return await t
}

fn check(sim: SimIo) -> I32 {
    if outer(sim) == 42 { return 0 }
    return 70
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "")
	})

	t.Run("failed-try", func(t *testing.T) {
		expectSimioE2E(t, "failed try", `fn child() -> Result(U64, CancellationError) {
    return Err(Cancelled)
}

fn check(sim: SimIo) -> Result(I32, CancellationError) {
    using tasks = TaskGroup.new(sim)
    let t = tasks.spawn(child())
    let value = try await t
    return Ok(70)
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return match check(sim) {
        Ok(value) => value
        Err(Cancelled) => 0
    }
}
`, "")
	})

	t.Run("early-return-cancel", func(t *testing.T) {
		expectSimioE2E(t, "early return cancel", `type Marker {
    io: SimIo
    tag: U8
}

impl Cleanup for Marker {
    fn cleanup(take self) -> Unit {
        let text: Array(U8, 1) = [self.tag]
        let _ = self.io.write_stdout(text.slice(0, 1))
        return
    }
}

fn child(io: SimIo, tag: U8) -> Unit {
    using marker = Marker(io: io, tag: tag)
    sleep(io, Duration.seconds(10))
    return
}

fn check(sim: SimIo) -> I32 {
    using tasks = TaskGroup.new(sim)
    using first = tasks.spawn(child(sim, 49))
    using second = tasks.spawn(child(sim, 50))
    using third = tasks.spawn(child(sim, 51))
    yield(sim)
    return 0
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "321")
	})

	t.Run("timeout-expiry", func(t *testing.T) {
		expectSimioE2E(t, "timeout expiry", `fn nap(sim: SimIo, millis: U64) -> U64 {
    sleep(sim, Duration.millis(millis))
    return millis
}

fn timed(sim: SimIo) -> U64 {
    let outcome = match timeout(sim, Duration.millis(10), nap(sim, 1000)) {
        Ok(value) => value
        Err(_) => 0
    }
    return outcome
}

fn check(sim: SimIo) -> I32 {
    let started = Instant.now(sim)
    let outcome = timed(sim)
    let elapsed = Instant.now(sim).duration_since(started)
    if outcome == 0 && elapsed.as_millis() == 10 { return 0 }
    return 71
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "")
	})

	t.Run("race-winner", func(t *testing.T) {
		expectSimioE2E(t, "race winner", `fn nap(sim: SimIo, millis: U64) -> U64 {
    sleep(sim, Duration.millis(millis))
    return millis
}

fn check(sim: SimIo) -> I32 {
    let won = race(sim, nap(sim, 30), nap(sim, 120))
    if won == 30 { return 0 }
    return 70
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "")
	})

	t.Run("blocking-direct", func(t *testing.T) {
		expectSimioE2E(t, "blocking direct", `fn child() -> U64 { return 42 }

fn check(io: Blocking) -> I32 {
    let value = blocking(io, child())
    if value == 42 { return 0 }
    return 70
}

pub fn main() -> I32 {
    return check(Blocking())
}
`, "")
	})

	t.Run("blocking-async", func(t *testing.T) {
		expectSimioE2E(t, "blocking async", `fn child() -> U64 { return 42 }

fn check(sim: SimIo) -> I32 {
    let value = blocking(sim, child())
    if value == 42 { return 0 }
    return 70
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "")
	})

	t.Run("virtual-time-ordering", func(t *testing.T) {
		expectSimioE2E(t, "virtual time ordering", `fn check(sim: SimIo) -> I32 {
    let started = Instant.now(sim)
    sleep(sim, Duration.millis(30))
    sleep(sim, Duration.millis(120))
    let elapsed = Instant.now(sim).duration_since(started)
    if elapsed.as_millis() == 150 { return 0 }
    return 71
}

pub fn main() -> I32 {
    let sim = SimIo.seeded(0)
    return check(sim)
}
`, "")
	})
}
