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
