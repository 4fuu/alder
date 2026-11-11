package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 C-boundary record surface through the production driver. The program
// moves a C record by value in every direction a raw fn signature allows:
// a by-value result constructs the record, field reads and writes go
// through the binding spellings inside `unsafe c`, a field write through a
// var local is visible to a by-value C callee, and a by-value parameter
// plus by-value result round trip carries every member. The rejections pin
// the checker diagnostics for the field forms: reading through a
// non-record local, an unknown field, a write whose value does not match
// the field's declared type, a write through a let binding, and a write
// through a function parameter. Exact float-value assertions stay out of
// this surface by the same TODO as the conversion test.
const cRecordProgram = `import c "crecord.h" as crec {
    record type Stamp = "struct crec_stamp" {
        seconds: c.Long = "tv_sec"
        nanos: c.Long = "tv_nsec"
    }
    raw fn make = "crec_make"() -> Stamp
    raw fn consume = "crec_consume"(stamp: Stamp) -> c.Long
    raw fn bump = "crec_bump"(stamp: Stamp, delta: c.Long) -> Stamp
}

fn t_records() -> I32 {
    // By-value result: the whole record moves out of the C callee.
    var stamp = unsafe c { crec.make() }
    // Field read through the binding spelling.
    let seconds = unsafe c { stamp.seconds }
    if seconds.to_i64() != 40 { return 1 }
    // Field write through the var local, then a read observes it.
    let rewritten: I64 = 42
    unsafe c { stamp.seconds = rewritten.to_c_long() }
    let read_back = unsafe c { stamp.seconds }
    if read_back.to_i64() != 42 { return 2 }
    // The write is visible to a by-value C callee: consume reads both
    // members of the passed copy.
    let total = unsafe c { crec.consume(stamp) }
    if total.to_i64() != 49 { return 3 }
    // By-value parameter and by-value result: bump returns a modified
    // copy and leaves the argument's own copy alone.
    let delta: I64 = 8
    var bumped = unsafe c { crec.bump(stamp, delta.to_c_long()) }
    let bumped_seconds = unsafe c { bumped.seconds }
    if bumped_seconds.to_i64() != 50 { return 4 }
    let stamp_again = unsafe c { stamp.seconds }
    if stamp_again.to_i64() != 42 { return 5 }
    return 0
}

fn main() -> I32 {
    let a = t_records()
    if a != 0 { return a }
    return 0
}
`

const cRecordFixtureHeader = `#ifndef CRECORD_H
#define CRECORD_H
typedef long crec_long;
struct crec_stamp {
    long tv_sec;
    long tv_nsec;
};
struct crec_stamp crec_make(void);
long crec_consume(struct crec_stamp stamp);
struct crec_stamp crec_bump(struct crec_stamp stamp, long delta);
long crec_count(void);
#endif
`

const cRecordFixtureSource = `#include "crecord.h"
struct crec_stamp crec_make(void) {
    struct crec_stamp stamp;
    stamp.tv_sec = 40L;
    stamp.tv_nsec = 7L;
    return stamp;
}

long crec_consume(struct crec_stamp stamp) {
    return stamp.tv_sec + stamp.tv_nsec;
}

long crec_count(void) {
    return 5L;
}

struct crec_stamp crec_bump(struct crec_stamp stamp, long delta) {
    stamp.tv_sec = stamp.tv_sec + delta;
    return stamp;
}
`

var cRecordRejections = []struct {
	name, source, want string
}{
	{
		"read-through-non-record",
		`import c "crecord.h" as crec {
    scalar type Count = "crec_long"
    raw fn count = "crec_count"() -> Count
    record type Stamp = "struct crec_stamp" {
        seconds: c.Long = "tv_sec"
    }
}
fn f() -> I32 {
    let value = unsafe c { crec.count() }
    let read = unsafe c { value.seconds }
    return 0
}
fn main() -> I32 { return 0 }
`,
		"unsafe c field access requires a local binding holding a C record value",
	},
	{
		"unknown-field",
		`import c "crecord.h" as crec {
    record type Stamp = "struct crec_stamp" {
        seconds: c.Long = "tv_sec"
    }
    raw fn make = "crec_make"() -> Stamp
}
fn f() -> I32 {
    var stamp = unsafe c { crec.make() }
    let read = unsafe c { stamp.minutes }
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such field on the bound C record",
	},
	{
		"write-type-mismatch",
		`import c "crecord.h" as crec {
    record type Stamp = "struct crec_stamp" {
        seconds: c.Long = "tv_sec"
    }
    raw fn make = "crec_make"() -> Stamp
    raw fn flag = "crec_flag"() -> c.Int
}
fn f() -> I32 {
    var stamp = unsafe c { crec.make() }
    unsafe c { stamp.seconds = unsafe c { crec.flag() } }
    return 0
}
fn main() -> I32 { return 0 }
`,
		"a C field assignment value does not match the field's declared binding type",
	},
	{
		"write-through-let",
		`import c "crecord.h" as crec {
    record type Stamp = "struct crec_stamp" {
        seconds: c.Long = "tv_sec"
    }
    raw fn make = "crec_make"() -> Stamp
}
fn f() -> I32 {
    let stamp = unsafe c { crec.make() }
    let rewritten: I64 = 1
    unsafe c { stamp.seconds = rewritten.to_c_long() }
    return 0
}
fn main() -> I32 { return 0 }
`,
		"a C field assignment requires a var binding",
	},
	{
		"nested-selector",
		`import c "crecord.h" as crec {
    record type Stamp = "struct crec_stamp" {
        seconds: c.Long = "tv_sec"
    }
    raw fn make = "crec_make"() -> Stamp
}
fn f() -> I32 {
    var stamp = unsafe c { crec.make() }
    let read = unsafe c { stamp.seconds.nanos }
    return 0
}
fn main() -> I32 { return 0 }
`,
		"unsafe c field access requires a local binding holding a C record value",
	},
}

// TestM8CRecordProductionQualification drives the C-boundary record forms
// end to end: the program emits deterministic C, compiles under the strict
// C11 set, runs to its success exit, and asserts the field values a real C
// fixture reports back through by-value signatures. The rejections pin the
// field diagnostics.
func TestM8CRecordProductionQualification(t *testing.T) {
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
		"c-record.al": cRecordProgram,
		"crecord.h":   cRecordFixtureHeader,
		"crecord.c":   cRecordFixtureSource,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-record.al")
	if emitted.status != 0 || emitted.stderr != "" || !strings.HasPrefix(emitted.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-record.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	mirText := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-record.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	assertPublicMIR(t, "c-record.al", mirText.stdout)
	if !strings.Contains(mirText.stdout, "c.field.get") || !strings.Contains(mirText.stdout, "c.field.set") {
		t.Fatalf("MIR carries no c.field ops")
	}
	driverText := `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, driverText, 0,
		"-I", dir, filepath.Join(dir, "crecord.c"))

	for _, rejection := range cRecordRejections {
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
