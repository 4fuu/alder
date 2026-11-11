package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Lifetime classes over the existing Cleanup trait, with no new registration
// surface. The first program registers a Cleanup owner on both a normal and
// an early-return exit and observes exactly one release per call through the
// imported counter (10 for the two 5-unit owners). The second copies bytes
// out of a CString owner into Alder storage through a call-scoped buffer
// borrow, releases the owner, and then reads the copy back: the copy must
// outlive the owner, and the runtime allocation count must return to zero.
const lifetimeCleanupProgram = `import c counter: fn(U64) -> Unit
type Res {
    n: U64
}
impl Cleanup for Res {
    fn cleanup(take self) -> Unit {
        unsafe c { counter(self.n) }
        return
    }
}
fn make(n: U64) -> Res { return Res(n: n) }
fn early(flag: Bool) -> I32 {
    using r = make(5)
    if flag { return 1 }
    return 0
}
fn main() -> I32 {
    if early(false) != 0 { return 1 }
    if early(true) != 1 { return 2 }
    return 0
}
`

const lifetimeCopyProgram = `import c "lifetime.h" as cs {
    opaque type Buffer = "Buffer"
    raw fn copy_from = "lifetime_copy_from"(src: c.ConstPtr(c.Char), dst: c.Ptr(Buffer), count: c.Size) -> c.Size
    raw fn sum = "lifetime_sum"(src: c.ConstPtr(Buffer), count: c.Size) -> c.Size
}

fn main() -> I32 {
    let text = "abc".concat("de")
    var buffer = Vec.new(U8)
    var at: U64 = 0
    let n = text.len()
    while at < n {
        let zero: U8 = 0
        buffer.push(zero)
        at = at + 1
    }
    match c.CString(text) {
        Some(owner0) => {
            using owner = owner0
            let view = buffer.slice_mut(0, buffer.len())
            let copied = unsafe c { cs.copy_from(owner.ptr(), view, view.len().to_c_size()) }
            if copied.to_u64() != 5 { return 1 }
        }
        None => { return 3 }
    }
    let read_back = buffer.slice(0, buffer.len())
    let total = unsafe c { cs.sum(read_back, read_back.len().to_c_size()) }
    if total.to_u64() != 495 { return 2 }
    return 0
}
`

const lifetimeHeader = `#ifndef LIFETIME_H
#define LIFETIME_H
#include <stddef.h>
typedef struct Buffer Buffer;
size_t lifetime_copy_from(const char *src, Buffer *dst, size_t count);
size_t lifetime_sum(const Buffer *src, size_t count);
#endif
`

const lifetimeSource = `#include "lifetime.h"
size_t lifetime_copy_from(const char *src, Buffer *dst, size_t count) {
    if (src == NULL || dst == NULL) { return (size_t)-1; }
    unsigned char *to = (unsigned char *)dst;
    for (size_t i = 0; i < count; i++) { to[i] = (unsigned char)src[i]; }
    return count;
}
size_t lifetime_sum(const Buffer *src, size_t count) {
    if (src == NULL) { return (size_t)-1; }
    const unsigned char *bytes = (const unsigned char *)src;
    size_t total = 0;
    for (size_t i = 0; i < count; i++) { total += bytes[i]; }
    return total;
}
`

const lifetimeCounterDriver = `#include "alder_host.h"
#include <stdint.h>
static uint64_t g_count = 0;
void counter(uint64_t v) { g_count += v; }
int main(void) {
    int context = 0;
    int result = (int)alder_program_entry(&context);
    if (g_count != 10) { return 98; }
    return result;
}
`

// TestLifetimeAffineOwnerExactlyOnce pins the affine-owner class: a Cleanup
// owner registered by `using` releases exactly once on the normal exit and
// exactly once on an early return, and nothing double-releases.
func TestLifetimeAffineOwnerExactlyOnce(t *testing.T) {
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

	files := map[string]string{"lifetime-cleanup.al": lifetimeCleanupProgram}
	check := runPrivateProductionCompiler(t, exe, files, "check", "lifetime-cleanup.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("lifetime-cleanup check result: %+v stderr=%s", check, check.stderr)
	}
	mirText := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=mir", "lifetime-cleanup.al")
	if mirText.status != 0 || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	if !strings.Contains(mirText.stdout, "cleanup.push") || !strings.Contains(mirText.stdout, "cleanup.scope.run") {
		t.Fatalf("printed MIR omits the cleanup registration or run:\n%s", mirText.stdout)
	}
	cResult := runPrivateProductionCompiler(t, exe, files, "compile", "--emit=c", "lifetime-cleanup.al")
	if cResult.status != 0 || cResult.stderr != "" {
		t.Fatalf("C result: %+v stderr=%s", cResult, cResult.stderr)
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, cResult.stdout, lifetimeCounterDriver, 0)
}

// TestLifetimeScopedBorrowAndCopy pins the scoped-borrow and copy-before-
// return classes: a CString owner is borrowed for one call through ptr(), the
// callee copies the bytes into Alder storage through a MutSlice borrow, the
// owner releases at scope exit, and the copied bytes are read back and summed
// after the release. The live allocation count returns to zero, so the owner
// released exactly once.
func TestLifetimeScopedBorrowAndCopy(t *testing.T) {
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
		"lifetime-copy.al": lifetimeCopyProgram,
		"lifetime.h":       lifetimeHeader,
		"lifetime.c":       lifetimeSource,
	}
	check := runProductionCompilerAtRoot(t, exe, dir, files, "check", "lifetime-copy.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("lifetime-copy check result: %+v stderr=%s", check, check.stderr)
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "lifetime-copy.al")
	if emitted.status != 0 || emitted.stderr != "" {
		t.Fatalf("C result: %+v stderr=%s", emitted, emitted.stderr)
	}
	if got := strings.Count(emitted.stdout, "alder_cstring_release("); got != 1 {
		t.Fatalf("generated C carries %d cstring release bodies, want 1", got)
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cStringDriver, 0,
		"-I", dir, filepath.Join(dir, "lifetime.c"))
}
