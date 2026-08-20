package cgen

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// runFixtures pairs each behavior fixture with its C driver. The driver
// includes the generated translation unit ("gen.c"), so static functions and
// type definitions are visible to it.
var runFixtures = []struct {
	mir    string
	driver string
}{
	{"checked", "checked_driver.c"},
	{"loop", "loop_driver.c"},
	{"enum", "enum_driver.c"},
	{"domain", "domain_driver.c"},
	{"cleanup", "cleanup_driver.c"},
	{"table", "table_driver.c"},
	{"cfg", "cfg_driver.c"},
	{"regressions", "regressions_driver.c"},
}

// runArgs builds the strict compile command for a behavior fixture: the
// generated file, the driver, and the runtime.
func runArgs(gen, driver string) []string {
	return []string{
		"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
		"-Wshadow", "-Wconversion",
		"-I", filepath.Dir(gen),
		"-I", filepath.Join("..", "runtime", "c"),
		gen, driver, filepath.Join("..", "runtime", "c", "alder.c"),
	}
}

// generateRun writes the generated C of a run fixture and returns its path.
func generateRun(t *testing.T, name string) string {
	t.Helper()
	path := filepath.Join("testdata", "run", name+".mir")
	if name == "cfg" {
		path = goldenMirPath(name) // cfg is a shared MIR golden
	}
	dir := t.TempDir()
	gen := filepath.Join(dir, "gen.c")
	if err := os.WriteFile(gen, []byte(generatePath(t, path)), 0o644); err != nil {
		t.Fatal(err)
	}
	return gen
}

// TestRunFixtures compiles each behavior fixture with its driver under the
// strict warning set and runs it, requiring exit code 0.
func TestRunFixtures(t *testing.T) {
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			for _, rf := range runFixtures {
				rf := rf
				t.Run(rf.mir, func(t *testing.T) {
					gen := generateRun(t, rf.mir)
					exe := filepath.Join(t.TempDir(), rf.mir+".exe")
					args := runArgs(gen, filepath.Join("testdata", "run", rf.driver))
					args = append(args, "-o", exe)
					if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
						t.Fatalf("compile %s failed: %v\n%s", rf.mir, err, out)
					}
					if out, err := exec.Command(exe).CombinedOutput(); err != nil {
						t.Fatalf("run %s failed: %v\n%s", rf.mir, err, out)
					}
				})
			}
		})
	}
}

func TestAllocCheckedBehavior(t *testing.T) {
	const text = `mir 3

const @success: i32 = 0
const @failure: i32 = 1
const @one: u64 = 1
const @answer: u64 = 42

fn @allocate(%d: domain_handle, %n: u64) -> i32 {
bb0:
  %p = alloc.checked %d, u64, %n else bb_fail
  %ok = const.get @success
  return %ok

bb_fail:
  %err = const.get @failure
  return %err
}

fn @swap_on_failure(%d: domain_handle, %first: u64, %second: u64) -> u64 {
bb0:
  jump bb_try(%first, %second)

bb_try(%x: u64, %y: u64):
  %p = alloc.checked %d, u64, %x else bb_try(%y, %x)
  return %y
}

fn @preserve_old_storage(%d: domain_handle, %n: u64) -> u64 {
bb0:
  %one_value = const.get @one
  %old = alloc %d, u64, %one_value
  %answer_value = const.get @answer
  store deref %old, %answer_value
  %fresh = alloc.checked %d, u64, %n else bb_fail
  return %answer_value

bb_fail:
  %got = load deref %old
  return %got
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	generated, err := Generate(m)
	if err != nil {
		t.Fatal(err)
	}
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			dir := t.TempDir()
			gen := filepath.Join(dir, "gen.c")
			if err := os.WriteFile(gen, []byte(generated), 0o644); err != nil {
				t.Fatal(err)
			}
			driver := filepath.Join(dir, "driver.c")
			const source = `#include "gen.c"
#include <stdint.h>
int main(void) {
    AlderDomain root = {0};
    if (!alder_domain_init(&root, NULL)) { return 2; }
    if (alder_fn_allocate_0(&root, (uint64_t)1) != (int32_t)0) { return 3; }
    if (alder_fn_allocate_0(NULL, (uint64_t)1) != (int32_t)1) { return 4; }
    if (alder_fn_allocate_0(&root, UINT64_MAX) != (int32_t)1) { return 5; }
    if (alder_fn_swap_on_failure_1(&root, UINT64_MAX, (uint64_t)1) != UINT64_MAX) { return 6; }
    if (alder_fn_preserve_old_storage_2(&root, UINT64_MAX) != (uint64_t)42) { return 7; }
    alder_domain_destroy(&root);
    return alder_runtime_live_allocations() == (size_t)0 ? 0 : 8;
}
`
			if err := os.WriteFile(driver, []byte(source), 0o644); err != nil {
				t.Fatal(err)
			}
			exe := filepath.Join(dir, "alloc_checked.exe")
			args := runArgs(gen, driver)
			args = append(args, "-o", exe)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("compile alloc.checked fixture: %v\n%s", err, out)
			}
			if out, err := exec.Command(exe).CombinedOutput(); err != nil {
				t.Fatalf("run alloc.checked fixture: %v\n%s", err, out)
			}
		})
	}
}

func TestFixedArrayBehavior(t *testing.T) {
	const text = `mir 3

fn @construct(%x: i64, %y: i64) -> array(i64, 2) {
bb0:
  %a = aggregate.construct array(i64, 2) { %x, %y }
  return %a
}

fn @replace(%a: array(i64, 2), %i: u64, %x: i64) -> array(i64, 2) {
  local %copy: array(i64, 2)
bb0:
  store local %copy, %a
  %r = borrow_mut local %copy
  %p = array.index.checked %r, %i else bb_fail
  store deref %p, %x
  %result = load local %copy
  return %result
bb_fail:
  %fallback = load local %copy
  return %fallback
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	generated, err := Generate(m)
	if err != nil {
		t.Fatal(err)
	}
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			dir := t.TempDir()
			gen := filepath.Join(dir, "gen.c")
			if err := os.WriteFile(gen, []byte(generated), 0o644); err != nil {
				t.Fatal(err)
			}
			driver := filepath.Join(dir, "driver.c")
			const source = `#include "gen.c"
int main(void) {
    AlderTy12 original = alder_fn_construct_0((int64_t)10, (int64_t)20);
    AlderTy12 changed = alder_fn_replace_1(original, (uint64_t)1, (int64_t)99);
    if (original.alder_e[0] != (int64_t)10 || original.alder_e[1] != (int64_t)20) { return 1; }
    if (changed.alder_e[0] != (int64_t)10 || changed.alder_e[1] != (int64_t)99) { return 2; }
    changed = alder_fn_replace_1(changed, (uint64_t)2, (int64_t)77);
    return changed.alder_e[1] == (int64_t)99 ? 0 : 3;
}
`
			if err := os.WriteFile(driver, []byte(source), 0o644); err != nil {
				t.Fatal(err)
			}
			exe := filepath.Join(dir, "array.exe")
			args := runArgs(gen, driver)
			args = append(args, "-o", exe)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("compile fixed array fixture: %v\n%s", err, out)
			}
			if out, err := exec.Command(exe).CombinedOutput(); err != nil {
				t.Fatalf("run fixed array fixture: %v\n%s", err, out)
			}
		})
	}
}

func TestLoopCarriedExternalAllocationsBehavior(t *testing.T) {
	const text = `mir 1

const @zero: u64 = 0
const @one: u64 = 1
const @eleven: u64 = 11

fn @loop_alloc(%d: domain_handle, %count: u64) -> u64 {
  local %current: safe_mut(u64)
  local %i: u64
entry:
  %one = const.get @one
  %initial = alloc %d, u64, %one
  %eleven = const.get @eleven
  store deref %initial, %eleven
  store local %current, %initial
  %zero = const.get @zero
  store local %i, %zero
  jump loop
loop:
  %at = load local %i
  %more = int.lt %at, %count
  branch %more, body, done
body:
  %next = alloc %d, u64, %one
  store deref %next, %at
  store local %current, %next
  %after = int.add.checked %at, %one else fail
  store local %i, %after
  jump loop
done:
  %latest = load local %current
  %first_value = load deref %initial
  %latest_value = load deref %latest
  %result = int.add.checked %first_value, %latest_value else fail
  return %result
fail:
  %failed = const.get @zero
  return %failed
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	generated, err := Generate(m)
	if err != nil {
		t.Fatal(err)
	}
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			dir := t.TempDir()
			gen := filepath.Join(dir, "gen.c")
			if err := os.WriteFile(gen, []byte(generated), 0o644); err != nil {
				t.Fatal(err)
			}
			driver := filepath.Join(dir, "driver.c")
			const source = `#include "gen.c"
#include <stdint.h>
int main(void) {
    AlderDomain root = {0};
    if (!alder_domain_init(&root, NULL)) { return 1; }
    if (alder_fn_loop_alloc_0(&root, (uint64_t)0) != (uint64_t)22) { return 2; }
    if (alder_fn_loop_alloc_0(&root, (uint64_t)2) != (uint64_t)12) { return 3; }
    alder_domain_destroy(&root);
    return alder_runtime_live_allocations() == (size_t)0 ? 0 : 4;
}
`
			if err := os.WriteFile(driver, []byte(source), 0o644); err != nil {
				t.Fatal(err)
			}
			exe := filepath.Join(dir, "loop_carried_allocations.exe")
			args := runArgs(gen, driver)
			args = append(args, "-o", exe)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("compile loop-carried allocation fixture: %v\n%s", err, out)
			}
			if out, err := exec.Command(exe).CombinedOutput(); err != nil {
				t.Fatalf("run loop-carried allocation fixture: %v\n%s", err, out)
			}
		})
	}
}

// TestFloatNarrowingPanics proves the f64-to-f32 guard executes before an
// out-of-range C cast. The ordinary checked fixture covers the in-range path.
func TestFloatNarrowingPanics(t *testing.T) {
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			gen := generateRun(t, "checked")
			driver := filepath.Join(t.TempDir(), "float_narrow_panic.c")
			const source = `#include "gen.c"
#include <float.h>
int main(void) {
    (void)alder_fn_narrow_11(DBL_MAX);
    return 0;
}
`
			if err := os.WriteFile(driver, []byte(source), 0o644); err != nil {
				t.Fatal(err)
			}
			exe := filepath.Join(t.TempDir(), "float_narrow_panic.exe")
			args := runArgs(gen, driver)
			args = append(args, "-o", exe)
			if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
				t.Fatalf("compile float narrowing panic fixture: %v\n%s", err, out)
			}
			out, err := exec.Command(exe).CombinedOutput()
			if err == nil {
				t.Fatal("out-of-range float narrowing exited successfully")
			}
			if !strings.Contains(string(out), "float.convert: out of range") {
				t.Fatalf("float narrowing panic message missing: %s", out)
			}
		})
	}
}

// TestRunFixturesSanitizers reruns the behavior fixtures under ASan/UBSan
// when the host toolchain supports them, and skips otherwise.
func TestRunFixturesSanitizers(t *testing.T) {
	for _, cc := range findCompilers(t) {
		cc := cc
		t.Run(filepath.Base(cc), func(t *testing.T) {
			if !sanitizersSupported(t, cc) {
				t.Skip("ASan/UBSan not supported by this toolchain")
			}
			for _, rf := range runFixtures {
				rf := rf
				t.Run(rf.mir, func(t *testing.T) {
					gen := generateRun(t, rf.mir)
					exe := filepath.Join(t.TempDir(), rf.mir+".exe")
					args := runArgs(gen, filepath.Join("testdata", "run", rf.driver))
					args = append(args,
						"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer",
						"-o", exe)
					if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
						t.Fatalf("sanitizer compile %s failed: %v\n%s", rf.mir, err, out)
					}
					if out, err := exec.Command(exe).CombinedOutput(); err != nil {
						t.Fatalf("sanitizer run %s failed: %v\n%s", rf.mir, err, out)
					}
				})
			}
		})
	}
}

// sanitizersSupported probes whether the host toolchain can build and run
// ASan/UBSan binaries.
func sanitizersSupported(t *testing.T, cc string) bool {
	t.Helper()
	dir := t.TempDir()
	probe := filepath.Join(dir, "probe.c")
	if err := os.WriteFile(probe, []byte("int main(void) { return 0; }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(dir, "probe.exe")
	args := []string{"-fsanitize=address,undefined", probe, "-o", exe}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Logf("sanitizer build unsupported on this host: %v\n%s", err, out)
		return false
	}
	if out, err := exec.Command(exe).CombinedOutput(); err != nil {
		t.Logf("sanitizer run unsupported on this host: %v\n%s", err, out)
		return false
	}
	return true
}
