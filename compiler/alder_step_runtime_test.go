package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
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

func runAlderStepProgram(t *testing.T, exe, cc, root, source, driver string) string {
	t.Helper()
	files := map[string]string{
		"std/io.al":       alderStepRuntimeStdIO,
		"fixture_timer.h": alderStepRuntimeTimerHeader,
		"program.al":      source,
	}
	result := runProductionCompiler(t, exe, files, "compile", "--bootstrap-private", "--emit=c", "std/io.al", "program.al")
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
		name   string
		source string
		driver string
		want   string
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
			name: "cancelled-cleanup-reverse",
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
			name: "park-timer",
			source: `import std.io { AsyncIo, Io }

import c "fixture_timer.h" as rt {
    raw fn register = "fixture_timer_register"(deadline: c.ULongLong) -> c.ULongLong
    raw fn park = "alder_task_park"() -> Unit
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

fn wait(I: type(Io), io: I, n: U64) -> U64 {
    let deadline: U64 = n
    let registered = unsafe c { rt.register(deadline.to_c_ulonglong()) }
    if registered.to_u64() != 1 { return 0 }
    unsafe c { rt.park() }
    return n + 1
}

pub fn main() -> I32 {
    let io = TestIo()
    let value = wait(io, 40)
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
			generated := runAlderStepProgram(t, exe, cc, root, tc.source, tc.driver)
			if !strings.Contains(generated, tc.want) {
				t.Fatalf("generated C has no step thunk %q:\n%s", tc.want, generated)
			}
			if !strings.Contains(generated, "alder_program_entry(void *host_context)") || !strings.Contains(generated, "alder_executor_run(NULL)") {
				t.Fatalf("generated C has no root-as-task entry:\n%s", generated)
			}
		})
	}
}
