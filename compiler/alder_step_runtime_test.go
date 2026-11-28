package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

const alderStepRuntimeStdIO = `module std.io

pub trait Io {
    fn check_cancel(self) -> Unit
}

pub trait BlockingIo {
}

pub trait AsyncIo {
}

pub type Blocking {
}

impl Io for Blocking {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl BlockingIo for Blocking {
}
`

const alderStepRuntimeTimerHeader = `#ifndef FIXTURE_TIMER_H
#define FIXTURE_TIMER_H
#include <stdbool.h>
#include <stdint.h>
typedef struct AlderWakeup AlderWakeup;
AlderWakeup *alder_task_wakeup(void);
bool alder_timer_at(AlderWakeup *wakeup, uint64_t deadline);
void alder_task_park(void);
void fixture_mark(unsigned long long value);
static inline unsigned long long fixture_timer_register(unsigned long long deadline) {
    return alder_timer_at(alder_task_wakeup(), deadline) ? 1ULL : 0ULL;
}
#endif
`

func runAlderStepProgram(t *testing.T, exe, cc, root, source, driver string, private, verifyMIR bool) string {
	t.Helper()
	files := map[string]string{
		"std/io.al":       alderStepRuntimeStdIO,
		"fixture_timer.h": alderStepRuntimeTimerHeader,
		"program.al":      source,
	}
	compile := []string{"compile"}
	if private {
		compile = append(compile, "--bootstrap-private")
	}
	if verifyMIR {
		result := runProductionCompiler(t, exe, files, append(compile, "--emit=mir", "std/io.al", "program.al")...)
		if result.status != 0 {
			t.Fatalf("emit step MIR: status %d\n%s", result.status, result.stderr)
		}
		module, err := mir.Parse(result.stdout)
		if err != nil {
			t.Fatalf("parse step MIR: %v\n%s", err, result.stdout)
		}
		if diagnostics := verify.Module(module); len(diagnostics) != 0 {
			t.Fatalf("verify step MIR: %s\n%s", verify.Errors(diagnostics), result.stdout)
		}
	}
	result := runProductionCompiler(t, exe, files, append(compile, "--emit=c", "std/io.al", "program.al")...)
	if result.status != 0 {
		t.Fatalf("compile step program: status %d\nstdout:\n%s\nstderr:\n%s", result.status, result.stdout, result.stderr)
	}
	dir := t.TempDir()
	cPath := filepath.Join(dir, "program.c")
	driverPath := filepath.Join(dir, "driver.c")
	binPath := filepath.Join(dir, "program")
	if err := os.WriteFile(filepath.Join(dir, "fixture_timer.h"), []byte(alderStepRuntimeTimerHeader), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cPath, []byte(result.stdout), 0o644); err != nil {
		t.Fatal(err)
	}
	if driver == "" {
		driver = "#include <stdint.h>\nextern int32_t alder_program_entry(void *);\nint main(void) { int context = 0; return (int)alder_program_entry(&context); }\n"
	}
	if err := os.WriteFile(driverPath, []byte(driver), 0o644); err != nil {
		t.Fatal(err)
	}
	args := strictC11Flags()
	args = append(args, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), "-I", dir, cPath, driverPath, filepath.Join(root, "runtime", "c", "alder.c"), "-pthread", "-o", binPath)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of step program: %v\n%s\n%s", err, output, result.stdout)
	}
	output, err := exec.Command(binPath).CombinedOutput()
	if err != nil {
		t.Fatalf("run step program: %v\n%s", err, output)
	}
	return result.stdout
}

func TestAlderStepRuntimePrograms(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)

	cases := []struct {
		name      string
		source    string
		driver    string
		want      string
		private   bool
		verifyMIR bool
	}{
		{
			name: "chain-three-points",
			source: `import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn chain(I: type(Io), io: I, n: U64) -> U64 {
    let a = leaf(io, n)
    let b = leaf(io, a)
    return leaf(io, b)
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = chain(block, 40)
    let b = chain(test, 40)
    if a != 43 { return 1 }
    if b != a { return 2 }
    return 0
}
`,
			want: "alder_step___alder_step_run_chain",
		},
		{
			name: "branch-join",
			source: `import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn choose(I: type(Io), io: I, n: U64) -> U64 {
    let a = leaf(io, n)
    var x: U64 = 0
    if a == 41 {
        x = leaf(io, a)
    } else {
        x = leaf(io, a + 1)
    }
    return leaf(io, x)
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = choose(block, 40)
    let b = choose(test, 40)
    if a != b { return 1 }
    if a != 43 { return 2 }
    let c = choose(block, 39)
    let d = choose(test, 39)
    if c != d { return 3 }
    if c != 43 { return 4 }
    return 0
}
`,
			want: "alder_step___alder_step_run_choose",
		},
		{
			name: "loop-two-points",
			source: `import std.io { AsyncIo, Blocking, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn loop(I: type(Io), io: I, n: U64) -> U64 {
    var i: U64 = 0
    var acc: U64 = n
    while i < 2 {
        acc = leaf(io, acc)
        acc = leaf(io, acc)
        i = i + 1
    }
    return acc
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = loop(block, 40)
    let b = loop(test, 40)
    if a != b { return 1 }
    if a != 44 { return 2 }
    return 0
}
`,
			want: "alder_step___alder_step_run_loop",
		},
		{
			name: "cleanup-two-points",
			source: `import std.io { AsyncIo, Blocking, Io }

type Res {
    id: U64
}

impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        return
    }
}

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn work(I: type(Io), io: I, n: U64) -> U64 {
    let r = Res(id: n)
    using held = r
    let a = leaf(io, n)
    let b = leaf(io, a)
    return b
}

pub fn main() -> I32 {
    let block = Blocking()
    let test = TestIo()
    let a = work(block, 40)
    let b = work(test, 40)
    if a != b { return 1 }
    if a != 42 { return 2 }
    return 0
}
`,
			want: "alder_cleanup_scope_begin_adopting",
		},
		{
			name:    "cancelled-cleanup-reverse",
			private: true,
			source: `import std.io { AsyncIo, Io }

import c cancel_self: fn() -> Unit
import c mark: fn(U64) -> Unit
import c shield_check: fn() -> Unit

type First {
}

impl Cleanup for First {
    fn cleanup(take self) -> Unit {
        unsafe c { shield_check() }
        unsafe c { mark(1) }
    }
}

type Second {
}

impl Cleanup for Second {
    fn cleanup(take self) -> Unit {
        unsafe c { shield_check() }
        unsafe c { mark(2) }
    }
}

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn work(I: type(Io), io: I, n: U64) -> U64 {
    let first = First()
    using held_first = first
    let second = Second()
    using held_second = second
    unsafe c { cancel_self() }
    let a = leaf(io, n)
    let b = leaf(io, a)
    return b
}

pub fn main() -> I32 {
    let test = TestIo()
    let value = work(test, 40)
    return 0
}
`,
			driver: `#include <stdint.h>
#include "alder.h"
extern int32_t alder_program_entry(void *);
static uint64_t marks = 0;
static uint64_t count = 0;
static int shield_fail = 0;
void cancel_self(void) { alder_task_cancel(alder_task_id()); }
void mark(uint64_t value) { marks = marks * 10 + value; count++; }
void shield_check(void) { if (alder_task_cancelled()) shield_fail = 1; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (result != 0) { return 20; }
    if (marks != 21) { return 21; }
    if (count != 2) { return 22; }
    if (shield_fail != 0) { return 23; }
    return 0;
}
`,
			want: "alder_step___alder_step_run_work",
		},
		{
			name:      "capability-free-park-timer",
			verifyMIR: true,
			source: `import c "fixture_timer.h" as rt {
    raw fn register = "fixture_timer_register"(deadline: c.ULongLong) -> c.ULongLong
    raw fn park = "alder_task_park"() -> Unit
}

fn wait(n: U64) -> U64 {
    let deadline: U64 = n
    let registered = unsafe c { rt.register(deadline.to_c_ulonglong()) }
    if registered.to_u64() != 1 { return 0 }
    unsafe c { rt.park() }
    return n + 1
}

pub fn main() -> I32 {
    let first: U64 = 39
    let registered = unsafe c { rt.register(first.to_c_ulonglong()) }
    if registered.to_u64() != 1 { return 2 }
    unsafe c { rt.park() }
    let value = wait(40)
    if value != 41 { return 1 }
    return 0
}
`,
			want: "alder_step___alder_step_run_wait",
		},
		{
			name: "suspending-cleanup-hook",
			source: `import std.io { AsyncIo, Io }

import c "fixture_timer.h" as rt {
    raw fn mark = "fixture_mark"(value: c.ULongLong) -> Unit
}

type Res {
    id: U64
}

impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        let io = TestIo()
        let x = leaf(io, 1)
        let seven: U64 = 7
        unsafe c { rt.mark(seven.to_c_ulonglong()) }
        return
    }
}

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn leaf(I: type(Io), io: I, n: U64) -> U64 {
    return n + 1
}

fn work(I: type(Io), io: I, n: U64) -> U64 {
    let r = Res(id: n)
    using held = r
    let a = leaf(io, n)
    return a
}

pub fn main() -> I32 {
    let test = TestIo()
    let value = work(test, 40)
    if value != 41 { return 1 }
    return 0
}
`,
			driver: `#include <stdint.h>
#include "alder.h"
extern int32_t alder_program_entry(void *);
static uint64_t marks = 0;
void fixture_mark(unsigned long long value) { marks += value; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (result != 0) { return 20; }
    if (marks != 7) { return 21; }
    return 0;
}
`,
			want: "alder_cleanup_scope_next_step",
		},
		{
			name: "recursive-frame",
			source: `import std.io { AsyncIo, Io }

type TestIo {
}

impl Io for TestIo {
    fn check_cancel(self) -> Unit {
        return
    }
}

impl AsyncIo for TestIo {
}

fn down(I: type(Io), io: I, n: U64) -> U64 {
    if n == 0 { return 0 }
    return down(io, n - 1)
}

pub fn main() -> I32 {
    let test = TestIo()
    if down(test, 1000) != 0 { return 1 }
    return 0
}
`,
			want: "alder_step___alder_step_run_down",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			generated := runAlderStepProgram(t, exe, cc, root, tc.source, tc.driver, tc.private, tc.verifyMIR)
			if !strings.Contains(generated, tc.want) {
				t.Fatalf("generated C has no step thunk %q:\n%s", tc.want, generated)
			}
			if !strings.Contains(generated, "alder_program_entry(void *host_context)") || !strings.Contains(generated, "alder_executor_run(NULL)") {
				t.Fatalf("generated C has no root-as-task entry:\n%s", generated)
			}
			if regexp.MustCompile(`\balder_fn_main_[0-9]+\(`).MatchString(generated) {
				t.Fatal("generated C contains a direct twin for suspending main")
			}
		})
	}
}

func TestAlderHostedStepEntry(t *testing.T) {
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

	t.Run("direct-main", func(t *testing.T) {
		files := map[string]string{"main.al": "fn main() -> I32 { return 37 }\n"}
		got := runProductionCompiler(t, exe, files, "compile", "--emit=c", "main.al")
		if got.status != 0 || !strings.Contains(got.stdout, "return alder_fn_main_") || strings.Contains(got.stdout, "alder_executor_run(NULL)") {
			t.Fatalf("non-suspending main did not keep a direct entry: %+v", got)
		}
	})

	t.Run("local-sim-clock", func(t *testing.T) {
		files := map[string]string{"alder.toml": taskManifest, "src/main.al": `module hello.main
import std.io { Io }
import std.test { SimIo }

fn elapsed(sim: SimIo) -> I32 {
    sim.sleep(0, 37)
    let now = sim.monotonic()
    if now.seconds != 0 || now.nanos != 37 { return 98 }
    return 37
}

pub fn main() -> I32 {
    let sim = SimIo.new()
    return elapsed(sim)
}
`}
		got := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
		if got.status != 37 || got.stdout != "" || got.stderr != "" {
			t.Fatalf("hosted SimIo step did not return its elapsed virtual time: %+v", got)
		}
	})

	t.Run("early-task-group-return", func(t *testing.T) {
		dir := t.TempDir()
		files := taskProject(taskTestCapability + `import c "fixture_task.h" as fixture {
    raw fn park = "alder_task_park"() -> Unit
    raw fn shield = "fixture_shield"() -> Unit
    raw fn observe = "fixture_observe"(byte: c.Int) -> Unit
    raw fn yield = "fixture_yield"() -> Unit
}

fn child(id: I32) -> Unit {
    unsafe c { fixture.shield() }
    unsafe c { fixture.park() }
    unsafe c { fixture.observe(id.to_c_int()) }
}

pub fn main() -> I32 {
    let io = TestCapability()
    using tasks = TaskGroup.new(io)
    tasks.start(child(49))
    tasks.start(child(50))
    unsafe c { fixture.yield() }
    unsafe c { fixture.park() }
    return 37
}
`)
		files["fixture_task.h"] = `#include <stdio.h>
#include "alder.h"
static inline void fixture_yield(void) { alder_task_yield(); }
static inline void fixture_shield(void) { alder_task_shield_push(); }
static inline void fixture_observe(int value) {
    alder_task_shield_pop();
    (void)putchar(alder_task_cancelled() ? value : 'X');
}
`
		got := runProductionCompilerEnv(t, exe, dir, append(env, "CPATH="+dir), files, "run")
		if got.status != 37 || got.stdout != "21" || got.stderr != "" {
			t.Fatalf("hosted main did not cancel parked children newest first before returning: %+v", got)
		}
	})

	for _, tc := range []struct{ module, capability string }{{"std.test", "SimIo"}, {"std.io", "Blocking"}} {
		t.Run("reject-"+tc.capability+"-parameter", func(t *testing.T) {
			files := map[string]string{"alder.toml": taskManifest, "src/main.al": "module hello.main\nimport " + tc.module + " { " + tc.capability + " }\n\npub fn main(io: " + tc.capability + ") -> I32 { return 0 }\n"}
			got := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "check")
			const want = "error[SEM0001]: hosted main cannot take an I/O capability yet; use a parameterless main and construct the capability locally"
			if got.status != 1 || got.stdout != "" || !strings.Contains(got.stderr, want) {
				t.Fatalf("hosted capability parameter did not get a source diagnostic: %+v", got)
			}
		})
	}
}
