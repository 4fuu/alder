package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 C-string ownership surface through the production driver. A literal
// c.CString is infallible and its scope registration releases the buffer
// exactly once; the try form over a runtime String yields option(c_string)
// and reports an interior NUL as none. The program also moves registered
// owners out of their `using` scope through both a plain return and an
// Option constructor: every transfer disarms the registration, so the moved
// buffer is owned by the caller and never released by the exiting scope.
// That disarm is the regression this fixture guards; without it the program
// releases the same buffer twice and the process aborts.
const cStringProgram = `import c "cstring.h" as cs {
    raw fn length = "cs_length"(text: c.ConstPtr(c.Char)) -> c.Size
    raw fn first = "cs_first"(text: c.ConstPtr(c.Char)) -> c.Size
}

fn literal() -> I32 {
    using mode = c.CString("rb")
    let n = unsafe c { cs.length(mode.ptr()) }
    let b = unsafe c { cs.first(mode.ptr()) }
    if n.to_u64() != 2 { return 1 }
    if b.to_u64() != 114 { return 2 }
    return 0
}

fn open_owned(text: String) -> Option(c.CString) {
    using path = try c.CString(text)
    return Some(path)
}

fn take_owned() -> c.CString {
    using path = c.CString("owned")
    return path
}

fn qualify() -> I32 {
    let text = "hel".concat("lo")
    match open_owned(text) {
        Some(held0) => {
            using held = held0
            let n = unsafe c { cs.length(held.ptr()) }
            if n.to_u64() != 5 { return 1 }
        }
        None => { return 2 }
    }
    using direct = take_owned()
    let d = unsafe c { cs.length(direct.ptr()) }
    if d.to_u64() != 5 { return 3 }
    return 0
}

fn none_path() -> I32 {
    let interior = "a".concat("\0b")
    match open_owned(interior) {
        Some(x) => {
            using y = x
            return 1
        }
        None => { return 0 }
    }
    return 2
}

fn bytes_path() -> I32 {
    let raw: Bytes = "\xff/\xfe"
    match c.CString(raw) {
        Some(owner0) => {
            using owner = owner0
            let n = unsafe c { cs.length(owner.ptr()) }
            let first = unsafe c { cs.first(owner.ptr()) }
            if n.to_u64() != 3 { return 1 }
            if first.to_u64() != 255 { return 2 }
        }
        None => { return 3 }
    }
    let interior: Bytes = "a\0b"
    match c.CString(interior) {
        Some(x) => {
            using y = x
            return 4
        }
        None => { return 0 }
    }
    return 5
}

fn main() -> I32 {
    let a = literal()
    if a != 0 { return a + 10 }
    let b = qualify()
    if b != 0 { return b + 20 }
    let tail = none_path()
    if tail != 0 { return tail + 30 }
    let raw = bytes_path()
    if raw != 0 { return raw + 40 }
    return 0
}
`

const cStringFixtureHeader = `#ifndef CSTRING_H
#define CSTRING_H
#include <stddef.h>
size_t cs_length(const char *text);
size_t cs_first(const char *text);
#endif
`

const cStringFixtureSource = `#include "cstring.h"
size_t cs_length(const char *text) {
    size_t n = 0;
    while (text != NULL && text[n] != 0) { n = n + 1; }
    return n;
}
size_t cs_first(const char *text) {
    return text != NULL ? (size_t)(unsigned char)text[0] : 0;
}
`

// The driver observes the runtime allocation counter around the whole
// program: every CString built here is released exactly once, so the live
// count must return to its starting value. A double release underflows the
// counter and fails even when the process does not abort.
const cStringDriver = `#include "alder.h"
#include "alder_host.h"
#include <stddef.h>
int main(void) {
    int context = 0;
    size_t before = alder_runtime_live_allocations();
    int status = (int)alder_program_entry(&context);
    size_t after = alder_runtime_live_allocations();
    if (status != 0) { return status; }
    if (before != after) { return 2; }
    return 0;
}
`

var cStringRejections = []struct {
	name, source, want string
}{
	{
		"literal-interior-nul",
		`fn main() -> I32 {
    using name = c.CString("a\0b")
    return 0
}
`,
		"a c.CString literal may not contain an interior NUL byte",
	},
	{
		"argument-count",
		`fn main() -> I32 {
    using name = c.CString("a", "b")
    return 0
}
`,
		"c.CString takes exactly one string argument",
	},
	{
		"argument-type",
		`fn main() -> I32 {
    using name = c.CString(5)
    return 0
}
`,
		"c.CString argument must be a String or Bytes value",
	},
}

// TestM8CStringProductionQualification drives the CString ownership surface
// end to end: literal construction, the try form, the runtime interior-NUL
// none path, and transfer of a registered owner out of its using scope. The
// emitted C must carry the cleanup disarm for both transfer sites, the
// printed MIR must expose the c.string vocabulary, and the strict-warning
// program must run to success with the live allocation count unchanged.
func TestM8CStringProductionQualification(t *testing.T) {
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
		"c-string.al": cStringProgram,
		"cstring.h":   cStringFixtureHeader,
		"cstring.c":   cStringFixtureSource,
	}
	check := runProductionCompilerAtRoot(t, exe, dir, files, "check", "c-string.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("c-string check result: %+v stderr=%s", check, check.stderr)
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-string.al")
	if emitted.status != 0 || emitted.stderr != "" || !strings.HasPrefix(emitted.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-string.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	// Both transfer sites (plain return and Option construction) must disarm
	// the registration they leave; a dropped disarm is the exact regression
	// that made the caller receive a released buffer.
	if got := strings.Count(emitted.stdout, "alder_cleanup_disarm("); got != 2 {
		t.Fatalf("generated C carries %d cleanup disarms, want 2", got)
	}
	if got := strings.Count(emitted.stdout, "alder_cstring_release("); got != 1 {
		t.Fatalf("generated C carries %d cstring release bodies, want 1", got)
	}

	mirText := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-string.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	assertPublicMIR(t, "c-string.al", mirText.stdout)
	for _, want := range []string{"c.string.make_lit", "c.string.make", "c.string.ptr", "c.string.release", "cleanup.disarm"} {
		if !strings.Contains(mirText.stdout, want) {
			t.Fatalf("printed MIR omits %q", want)
		}
	}
	repeatMIR := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-string.al")
	if repeatMIR.status != 0 || repeatMIR.stdout != mirText.stdout {
		t.Fatalf("emit=mir changed across processes")
	}

	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cStringDriver, 0,
		"-I", dir, filepath.Join(dir, "cstring.c"))

	for _, rejection := range cStringRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			rejectFiles := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, rejectFiles, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
