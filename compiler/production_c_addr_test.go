package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 C-boundary zero-initialized values and local addresses through the
// production driver. c.Zero builds a zeroed bound record or raw C scalar in
// ordinary code; c.addr passes a local place of the declared pointee type to
// one raw call and never becomes an Alder value. The fixture writes one
// record member through the out-parameter and leaves the other untouched, so
// the zero-initialized member value proves c.Zero zeroed the record.
const cAddrProgram = `import c "caddr.h" as posix {
    record type Pair = "struct caddr_pair" {
        first: c.Long = "first"
        second: c.Long = "second"
    }
    raw fn fill = "caddr_fill"(out: c.Ptr(Pair), value: c.Long) -> c.Int
    raw fn total = "caddr_total"(pair: c.ConstPtr(Pair)) -> c.Long
    raw fn bump = "caddr_bump"(io: c.Ptr(c.Long)) -> c.Int
    raw fn read_long = "caddr_read"(value: c.ConstPtr(c.Long)) -> c.Long
    raw fn round_trip = "caddr_round_trip"(value: c.Long) -> c.Long
}

fn main() -> I32 {
    // A zeroed record local is a mutable out-parameter for one call.
    let seven: I64 = 7
    var pair = c.Zero(Pair)
    let rc = unsafe c { posix.fill(c.addr(pair), seven.to_c_long()) }
    if rc.to_i64() != 0 { return 1 }
    let first = unsafe c { pair.first }
    if first.to_i64() != 7 { return 2 }
    // The fixture never writes the second member, so zero proves c.Zero.
    let second = unsafe c { pair.second }
    if second.to_i64() != 0 { return 3 }
    // A const pointer parameter takes the same local without a mutable view.
    let pair_total = unsafe c { posix.total(c.addr(pair)) }
    if pair_total.to_i64() != 7 { return 4 }
    // A zeroed raw scalar is an ordinary by-value argument.
    let zeroed = unsafe c { posix.round_trip(c.Zero(c.Long)) }
    if zeroed.to_i64() != 0 { return 5 }
    // A var scalar local round-trips through c.Ptr and c.ConstPtr.
    var value = c.Zero(c.Long)
    let bumped_rc = unsafe c { posix.bump(c.addr(value)) }
    if bumped_rc.to_i64() != 0 { return 8 }
    let bumped = unsafe c { posix.read_long(c.addr(value)) }
    if bumped.to_i64() != 1 { return 6 }
    // A let copy of a record can still be addressed const.
    let frozen = pair
    let frozen_total = unsafe c { posix.total(c.addr(frozen)) }
    if frozen_total.to_i64() != 7 { return 7 }
    // The binding block alias qualifies the same record type.
    var aliased = c.Zero(posix.Pair)
    let aliased_total = unsafe c { posix.total(c.addr(aliased)) }
    if aliased_total.to_i64() != 0 { return 9 }
    return 0
}
`

const cAddrFixtureHeader = `#ifndef CADDR_H
#define CADDR_H
struct caddr_pair {
    long first;
    long second;
};
int caddr_fill(struct caddr_pair *out, long value);
long caddr_total(const struct caddr_pair *pair);
int caddr_bump(long *io);
long caddr_read(const long *value);
long caddr_round_trip(long value);
#endif
`

const cAddrFixtureSource = `#include "caddr.h"

int caddr_fill(struct caddr_pair *out, long value) {
    out->first = value;
    return 0;
}

long caddr_total(const struct caddr_pair *pair) {
    return pair->first + pair->second;
}

int caddr_bump(long *io) {
    *io = *io + 1;
    return 0;
}

long caddr_read(const long *value) {
    return *value;
}

long caddr_round_trip(long value) {
    return value;
}
`

const cAddrRejectPrelude = `import c "caddr.h" as posix {
    record type Pair = "struct caddr_pair" {
        first: c.Long = "first"
        second: c.Long = "second"
    }
    opaque type Handle = "struct caddr_opaque"
    raw fn fill = "caddr_fill"(out: c.Ptr(Pair), value: c.Long) -> c.Int
    raw fn total = "caddr_total"(pair: c.ConstPtr(Pair)) -> c.Long
}

`

var cAddrRejections = []struct {
	name, source, want string
}{
	{
		"zero-pointer-type",
		cAddrRejectPrelude + `fn main() -> I32 {
    let bad = c.Zero(c.Ptr(Pair))
    return 0
}
`,
		"c.Zero argument must name a by-value C scalar or record type",
	},
	{
		"zero-unknown-name",
		cAddrRejectPrelude + `fn main() -> I32 {
    let bad = c.Zero(Nope)
    return 0
}
`,
		"c.Zero argument must name a by-value C scalar or record type",
	},
	{
		"zero-opaque-member",
		cAddrRejectPrelude + `fn main() -> I32 {
    let bad = c.Zero(Handle)
    return 0
}
`,
		"c.Zero argument must name a by-value C scalar or record type",
	},
	{
		"zero-arity",
		cAddrRejectPrelude + `fn main() -> I32 {
    let bad = c.Zero(Pair, Pair)
    return 0
}
`,
		"c.Zero argument must name a by-value C scalar or record type",
	},
	{
		"addr-outside-raw-call",
		cAddrRejectPrelude + `fn main() -> I32 {
    var pair = c.Zero(Pair)
    let bad = c.addr(pair)
    return 0
}
`,
		"c.addr requires a local place",
	},
	{
		"addr-let-is-not-mutable",
		cAddrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    let pair = c.Zero(Pair)
    unsafe c { posix.fill(c.addr(pair), one.to_c_long()) }
    return 0
}
`,
		"c.addr requires a local place",
	},
	{
		"addr-pointee-mismatch",
		cAddrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    var value = c.Zero(c.Long)
    unsafe c { posix.fill(c.addr(value), one.to_c_long()) }
    return 0
}
`,
		"c.addr requires a local place",
	},
	{
		"addr-not-a-place",
		cAddrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    unsafe c { posix.fill(c.addr(c.Zero(Pair)), one.to_c_long()) }
    return 0
}
`,
		"c.addr requires a local place",
	},
	{
		"addr-const-pointee-mismatch",
		cAddrRejectPrelude + `fn main() -> I32 {
    var value = c.Zero(c.Long)
    let bad = unsafe c { posix.total(c.addr(value)) }
    return 0
}
`,
		"c.addr requires a local place",
	},
	{
		"addr-arity",
		cAddrRejectPrelude + `fn main() -> I32 {
    let one: I64 = 1
    var pair = c.Zero(Pair)
    unsafe c { posix.fill(c.addr(pair, pair), one.to_c_long()) }
    return 0
}
`,
		"c.addr requires a local place",
	},
}

func TestM8CAddrProductionQualification(t *testing.T) {
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
		"c-addr.al": cAddrProgram,
		"caddr.h":   cAddrFixtureHeader,
		"caddr.c":   cAddrFixtureSource,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-addr.al")
	if emitted.status != 0 || emitted.stderr != "" || !strings.HasPrefix(emitted.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-addr.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	mirText := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-addr.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	assertPublicMIR(t, "c-addr.al", mirText.stdout)
	if !strings.Contains(mirText.stdout, "c.zero @Pair") || !strings.Contains(mirText.stdout, "c.addr local") {
		t.Fatalf("MIR carries no c.zero/c.addr ops:\n%s", mirText.stdout)
	}
	driverText := `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, driverText, 0,
		"-I", dir, filepath.Join(dir, "caddr.c"))

	for _, rejection := range cAddrRejections {
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
