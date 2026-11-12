package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 nonretained C callbacks: a bound function-pointer typedef, the
// c.callback(name) direct raw-call argument, and the generated trampoline
// that enters the Alder runtime. The C fixture invokes the callback
// synchronously and observes the context write before returning.
const cCallbackProgram = `import c "cbtest.h" as cbtest {
    callback type Handler = "cbtest_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int

    raw fn invoke = "cbtest_invoke"(handler: Handler, context: c.Ptr(c.UChar)) -> c.Int
}

fn handle_event(event: c.ConstPtr(c.UChar), length: c.Size, context: c.Ptr(c.UChar)) -> c.Int {
    if length.to_u64() != 1 { return c.Zero(c.Int) }
    let value = unsafe c { c.load(event) }
    unsafe c { c.store(context, value) }
    return c.Zero(c.Int)
}

fn main() -> I32 {
    var slot: c.UChar = c.Zero(c.UChar)
    let status = unsafe c { cbtest.invoke(c.callback(handle_event), c.addr(slot)) }
    if status.to_i64() != 0 { return 1 }
    return 0
}
`

const cCallbackFixtureHeader = `#ifndef CBTEST_H
#define CBTEST_H
#include <stddef.h>
typedef int (*cbtest_handler)(const unsigned char *event, size_t length, unsigned char *context);
int cbtest_invoke(cbtest_handler handler, unsigned char *context);
#endif
`

const cCallbackDriver = `#include "alder_host.h"
#include "cbtest.h"

static unsigned char observed;

int cbtest_invoke(cbtest_handler handler, unsigned char *context) {
    unsigned char event = 'A';
    int status = handler(&event, 1, context);
    observed = *context;
    return status;
}

int main(void) {
    int context = 0;
    if (alder_program_entry(&context) != 0) { return 1; }
    if (observed != (unsigned char)'A') { return 2; }
    return 0;
}
`

func TestM8CCallbackProductionQualification(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)

	dir := t.TempDir()
	files := map[string]string{
		"callback.al": cCallbackProgram,
		"cbtest.h":    cCallbackFixtureHeader,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "callback.al")
	if emitted.status != 0 || emitted.stderr != "" {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	for _, want := range []string{
		"typedef cbtest_handler alder_bind_0_t0;",
		"alder_callback_",
		"_Static_assert(_Generic(&alder_callback_",
		" = alder_callback_",
	} {
		if !strings.Contains(emitted.stdout, want) {
			t.Fatalf("generated C misses %q:\n%s", want, emitted.stdout)
		}
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "callback.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cCallbackDriver, 0,
		"-I", dir)

	rejections := []struct {
		name, source, want string
	}{
		{
			"target-mismatch",
			`import c "cbtest.h" as cbtest {
    callback type Handler = "cbtest_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int
    raw fn invoke = "cbtest_invoke"(handler: Handler, context: c.Ptr(c.UChar)) -> c.Int
}

fn wrong(event: c.ConstPtr(c.UChar)) -> c.Int { return c.Zero(c.Int) }

fn main() -> I32 {
    var slot: c.UChar = c.Zero(c.UChar)
    let status = unsafe c { cbtest.invoke(c.callback(wrong), c.addr(slot)) }
    return 0
}
`,
			"a C callback target does not match the bound callback type",
		},
		{
			"callback-outside-unsafe",
			`import c "cbtest.h" as cbtest {
    callback type Handler = "cbtest_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int
}
fn handle(event: c.ConstPtr(c.UChar), length: c.Size, context: c.Ptr(c.UChar)) -> c.Int { return c.Zero(c.Int) }
fn main() -> I32 {
    let value = c.callback(handle)
    return 0
}
`,
			"c.callback is allowed only as a direct raw-call argument",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": rejection.source}, "check", "reject.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: %+v stderr=%s", rejection.name, result, result.stderr)
			}
		})
	}
}

// M8 retained callback owner: registration copies the context into
// heap-owned storage, a take/generic move keeps the context address stable,
// and the using cleanup clears, waits, and frees exactly once.
const cCallbackOwnerProgram = `import c "ownertest.h" as ev {
    callback type Handler = "ownertest_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int

    raw fn set = "ownertest_set"(handler: Handler, context: c.Ptr(c.UChar)) -> c.Int
    raw fn clear = "ownertest_clear"(context: c.Ptr(c.UChar)) -> c.Int
    raw fn wait = "ownertest_wait"(context: c.Ptr(c.UChar)) -> Unit
    raw fn fire = "ownertest_fire"() -> c.Int
}

fn handle_event(event: c.ConstPtr(c.UChar), length: c.Size, context: c.Ptr(c.UChar)) -> c.Int {
    let zero = c.Zero(c.UChar)
    unsafe c { c.store(context, zero) }
    return c.Zero(c.Int)
}

fn consume(T: type, take owner: T) -> Unit {
    using held = owner
    let status = unsafe c { ev.fire() }
    return
}

fn main() -> I32 {
    var state: c.UChar = c.Zero(c.UChar)
    let registered = unsafe c { c.CallbackOwner.register(ev.set, ev.clear, ev.wait, handle_event, state) }
    using owner = match registered {
        Some(value) => value
        None => return 1
    }
    consume(owner)
    return 0
}
`

const cCallbackOwnerFixtureHeader = `#ifndef OWNERTEST_H
#define OWNERTEST_H
#include <stddef.h>
typedef int (*ownertest_handler)(const unsigned char *event, size_t length, unsigned char *context);
int ownertest_set(ownertest_handler handler, unsigned char *context);
int ownertest_clear(unsigned char *context);
void ownertest_wait(unsigned char *context);
int ownertest_fire(void);
#endif
`

const cCallbackOwnerDriver = `#include "alder_host.h"
#include "ownertest.h"

static ownertest_handler saved_handler;
static unsigned char *saved_context;
static int clear_count;
static int wait_count;

int ownertest_set(ownertest_handler handler, unsigned char *context) {
    saved_handler = handler;
    saved_context = context;
    return 0;
}
int ownertest_clear(unsigned char *context) { (void)context; clear_count += 1; return 0; }
void ownertest_wait(unsigned char *context) { (void)context; wait_count += 1; }
int ownertest_fire(void) {
    unsigned char event = 'A';
    if (saved_handler == NULL || saved_context == NULL) { return 1; }
    if (saved_handler(&event, 1, saved_context) != 0) { return 2; }
    return *saved_context == (unsigned char)0 ? 0 : 3;
}

int main(void) {
    int context = 0;
    if (alder_program_entry(&context) != 0) { return 10; }
    if (clear_count != 1) { return 11; }
    if (wait_count != 1) { return 12; }
    return 0;
}
`

func TestM8CCallbackOwnerProductionQualification(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	runtimeObject := buildRuntimeObject(t, cc, root)

	dir := t.TempDir()
	files := map[string]string{
		"owner.al":    cCallbackOwnerProgram,
		"ownertest.h": cCallbackOwnerFixtureHeader,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "owner.al")
	if emitted.status != 0 || emitted.stderr != "" {
		t.Fatalf("owner emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	for _, want := range []string{
		"alder_callback_owner_new(sizeof(unsigned char))",
		"alder_callback_owner_release_",
		"ownertest_clear(context) != 0",
		"ownertest_wait(context)",
	} {
		if !strings.Contains(emitted.stdout, want) {
			t.Fatalf("generated owner C misses %q:\n%s", want, emitted.stdout)
		}
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cCallbackOwnerDriver, 0,
		"-I", dir)

	rejections := []struct {
		name, source, want string
	}{
		{
			"clear-result",
			`import c "ownertest.h" as ev {
    callback type Handler = "ownertest_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int
    raw fn set = "ownertest_set"(handler: Handler, context: c.Ptr(c.UChar)) -> c.Int
    raw fn wait = "ownertest_wait"(context: c.Ptr(c.UChar)) -> Unit
}
fn handle(event: c.ConstPtr(c.UChar), length: c.Size, context: c.Ptr(c.UChar)) -> c.Int { return c.Zero(c.Int) }
fn main() -> I32 {
    var state: c.UChar = c.Zero(c.UChar)
    let registered = unsafe c { c.CallbackOwner.register(ev.set, ev.wait, ev.wait, handle, state) }
    return 0
}
`,
			"a callback type is a C function-pointer signature, not an ordinary value type",
		},
		{
			"target-mismatch",
			`import c "ownertest.h" as ev {
    callback type Handler = "ownertest_handler" (
        event: c.ConstPtr(c.UChar),
        length: c.Size,
        context: c.Ptr(c.UChar),
    ) -> c.Int
    raw fn set = "ownertest_set"(handler: Handler, context: c.Ptr(c.UChar)) -> c.Int
    raw fn clear = "ownertest_clear"(context: c.Ptr(c.UChar)) -> c.Int
    raw fn wait = "ownertest_wait"(context: c.Ptr(c.UChar)) -> Unit
}
fn wrong(event: c.ConstPtr(c.UChar)) -> c.Int { return c.Zero(c.Int) }
fn main() -> I32 {
    var state: c.UChar = c.Zero(c.UChar)
    let registered = unsafe c { c.CallbackOwner.register(ev.set, ev.clear, ev.wait, wrong, state) }
    return 0
}
`,
			"a C callback target does not match the bound callback type",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": rejection.source}, "check", "reject.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: %+v stderr=%s", rejection.name, result, result.stderr)
			}
		})
	}

	// The same driver under ASan/UBSan catches a moved-owner use-after-free or
	// a double clear/free that the observable counters would miss.
	sanitizedDir := t.TempDir()
	sanitizedC := filepath.Join(sanitizedDir, "owner.c")
	sanitizedDriver := filepath.Join(sanitizedDir, "driver.c")
	sanitizedExe := filepath.Join(sanitizedDir, "owner")
	if err := os.WriteFile(sanitizedC, []byte(emitted.stdout), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sanitizedDriver, []byte(cCallbackOwnerDriver), 0o644); err != nil {
		t.Fatal(err)
	}
	sanitize := []string{"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer"}
	args := append(append([]string{}, strictC11Flags()...), sanitize...)
	args = append(args, "-I", dir, "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"),
		sanitizedC, sanitizedDriver, filepath.Join(root, "runtime", "c", "alder.c"), "-lm", "-o", sanitizedExe)
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized owner compile: %v\n%s", err, out)
	}
	run := exec.Command(sanitizedExe)
	run.Env = append(os.Environ(), "ASAN_OPTIONS=detect_leaks=1")
	if out, err := run.CombinedOutput(); err != nil {
		t.Fatalf("sanitized owner run: %v\n%s", err, out)
	}
}
