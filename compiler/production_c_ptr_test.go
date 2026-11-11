package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 C-boundary pointer member access and whole-value memory through the
// production driver. `unsafe c { ptr.field }` reads through c.Ptr and
// c.ConstPtr, the write form goes through c.Ptr only, and c.load/c.store move
// whole values behind one pointer. The fixture heap-allocates a record and
// a scalar so reads and writes observe real C storage; every function stays
// small because the checker's body recursion is stack-heavy.
const cPtrProgram = `import c "cptrmem.h" as cp {
    record type Pair = "struct cptr_pair" {
        first: c.Long = "first"
        second: c.Long = "second"
    }
    raw fn make = "cptr_make"(a: c.Long, b: c.Long) -> c.Ptr(Pair)
    raw fn const_view = "cptr_const_view"(p: c.Ptr(Pair)) -> c.ConstPtr(Pair)
    raw fn total = "cptr_total"(p: c.ConstPtr(Pair)) -> c.Long
    raw fn release = "cptr_free"(p: c.Ptr(Pair)) -> c.Int
    raw fn long_out = "cptr_long_out"(value: c.Long) -> c.Ptr(c.Long)
}

fn pointer_fields() -> I32 {
    let a: I64 = 3
    let b: I64 = 4
    let p = unsafe c { cp.make(a.to_c_long(), b.to_c_long()) }
    let first = unsafe c { p.first }
    if first.to_i64() != 3 { return 1 }
    let nine: I64 = 9
    unsafe c { p.second = nine.to_c_long() }
    let total = unsafe c { cp.total(p) }
    if total.to_i64() != 12 { return 2 }
    let rc = unsafe c { cp.release(p) }
    if rc.to_i64() != 0 { return 3 }
    return 0
}

fn whole_values() -> I32 {
    let a: I64 = 3
    let b: I64 = 4
    let p = unsafe c { cp.make(a.to_c_long(), b.to_c_long()) }
    let whole = unsafe c { c.load(p) }
    let whole_first = unsafe c { whole.first }
    if whole_first.to_i64() != 3 { return 1 }
    let q = unsafe c { cp.make(a.to_c_long(), b.to_c_long()) }
    unsafe c { c.store(q, whole) }
    let q_total = unsafe c { cp.total(q) }
    if q_total.to_i64() != 7 { return 2 }
    let r1 = unsafe c { cp.release(p) }
    if r1.to_i64() != 0 { return 3 }
    let r2 = unsafe c { cp.release(q) }
    if r2.to_i64() != 0 { return 4 }
    return 0
}

fn const_and_scalar() -> I32 {
    let a: I64 = 3
    let b: I64 = 4
    let p = unsafe c { cp.make(a.to_c_long(), b.to_c_long()) }
    let view = unsafe c { cp.const_view(p) }
    let first = unsafe c { view.first }
    if first.to_i64() != 3 { return 1 }
    let seven: I64 = 7
    let lp = unsafe c { cp.long_out(seven.to_c_long()) }
    let loaded = unsafe c { c.load(lp) }
    if loaded.to_i64() != 7 { return 2 }
    let eight: I64 = 8
    unsafe c { c.store(lp, eight.to_c_long()) }
    let again = unsafe c { c.load(lp) }
    if again.to_i64() != 8 { return 3 }
    let rc = unsafe c { cp.release(p) }
    if rc.to_i64() != 0 { return 4 }
    return 0
}

fn main() -> I32 {
    let a = pointer_fields()
    if a != 0 { return a }
    let b = whole_values()
    if b != 0 { return b }
    let c = const_and_scalar()
    if c != 0 { return c }
    return 0
}
`

const cPtrFixtureHeader = `#ifndef CPTRMEM_H
#define CPTRMEM_H
struct cptr_pair {
    long first;
    long second;
};
typedef struct cptr_pair *cptr_handle;
struct cptr_pair *cptr_make(long a, long b);
struct cptr_pair cptr_pair_value(long a, long b);
const struct cptr_pair *cptr_const_view(struct cptr_pair *p);
long cptr_total(const struct cptr_pair *p);
int cptr_free(struct cptr_pair *p);
long *cptr_long_out(long value);
cptr_handle cptr_handle_make(void);
#endif
`

const cPtrFixtureSource = `#include "cptrmem.h"
#include <stdlib.h>

struct cptr_pair *cptr_make(long a, long b) {
    struct cptr_pair *p = malloc(sizeof *p);
    if (p == 0) { return 0; }
    p->first = a;
    p->second = b;
    return p;
}

struct cptr_pair cptr_pair_value(long a, long b) {
    struct cptr_pair p;
    p.first = a;
    p.second = b;
    return p;
}

const struct cptr_pair *cptr_const_view(struct cptr_pair *p) {
    return p;
}

long cptr_total(const struct cptr_pair *p) {
    return p->first + p->second;
}

int cptr_free(struct cptr_pair *p) {
    free(p);
    return 0;
}

long *cptr_long_out(long value) {
    long *p = malloc(sizeof *p);
    if (p == 0) { return 0; }
    *p = value;
    return p;
}

cptr_handle cptr_handle_make(void) {
    return cptr_make(1L, 2L);
}
`

const cPtrRejectPrelude = `import c "cptrmem.h" as cp {
    record type Pair = "struct cptr_pair" {
        first: c.Long = "first"
        second: c.Long = "second"
    }
    opaque type Handle = "cptr_handle"
    raw fn make = "cptr_make"(a: c.Long, b: c.Long) -> c.Ptr(Pair)
    raw fn value = "cptr_pair_value"(a: c.Long, b: c.Long) -> Pair
    raw fn const_view = "cptr_const_view"(p: c.Ptr(Pair)) -> c.ConstPtr(Pair)
    raw fn handle = "cptr_handle_make"() -> c.Ptr(Handle)
    raw fn long_out = "cptr_long_out"(value: c.Long) -> c.Ptr(c.Long)
}

`

var cPtrRejections = []struct {
	name, source, want string
}{
	{
		"load-outside-unsafe-c",
		cPtrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let p = unsafe c { cp.make(one.to_c_long(), one.to_c_long()) }
    let bad = c.load(p)
    return 0
}
`,
		"c.load and c.store require a C pointer to a by-value C type",
	},
	{
		"load-non-pointer",
		cPtrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let pair = unsafe c { cp.value(one.to_c_long(), one.to_c_long()) }
    let bad = unsafe c { c.load(pair) }
    return 0
}
`,
		"c.load and c.store require a C pointer to a by-value C type",
	},
	{
		"load-opaque-pointee",
		cPtrRejectPrelude + `fn main() -> I32 {
    let h = unsafe c { cp.handle() }
    let bad = unsafe c { c.load(h) }
    return 0
}
`,
		"c.load and c.store require a C pointer to a by-value C type",
	},
	{
		"store-through-const",
		cPtrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let p = unsafe c { cp.make(one.to_c_long(), one.to_c_long()) }
    let whole = unsafe c { c.load(p) }
    let view = unsafe c { cp.const_view(p) }
    unsafe c { c.store(view, whole) }
    return 0
}
`,
		"a write through a c.ConstPtr is not allowed",
	},
	{
		"const-field-write",
		cPtrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let p = unsafe c { cp.make(one.to_c_long(), one.to_c_long()) }
    let view = unsafe c { cp.const_view(p) }
    unsafe c { view.first = one.to_c_long() }
    return 0
}
`,
		"a write through a c.ConstPtr is not allowed",
	},
	{
		"store-type-mismatch",
		cPtrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let p = unsafe c { cp.make(one.to_c_long(), one.to_c_long()) }
    unsafe c { c.store(p, one.to_c_long()) }
    return 0
}
`,
		"c.store value does not match the C pointer pointee",
	},
	{
		"load-arity",
		cPtrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let p = unsafe c { cp.make(one.to_c_long(), one.to_c_long()) }
    let bad = unsafe c { c.load(p, p) }
    return 0
}
`,
		"c.load and c.store require a C pointer to a by-value C type",
	},
}

func TestM8CPtrMemoryProductionQualification(t *testing.T) {
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
		"c-ptr.al":  cPtrProgram,
		"cptrmem.h": cPtrFixtureHeader,
		"cptrmem.c": cPtrFixtureSource,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-ptr.al")
	if emitted.status != 0 || emitted.stderr != "" || !strings.HasPrefix(emitted.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-ptr.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	mirText := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-ptr.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	assertPublicMIR(t, "c-ptr.al", mirText.stdout)
	if !strings.Contains(mirText.stdout, "load field(deref") || !strings.Contains(mirText.stdout, "store field(deref") || !strings.Contains(mirText.stdout, "load deref") {
		t.Fatalf("MIR carries no pointer place loads/stores:\n%s", mirText.stdout)
	}
	driverText := `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, driverText, 0,
		"-I", dir, filepath.Join(dir, "cptrmem.c"))

	for _, rejection := range cPtrRejections {
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
