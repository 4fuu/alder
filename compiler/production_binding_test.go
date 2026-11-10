package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// D0xx M8 binding blocks through the production driver: module-level
// `import c "header.h" as name { ... }` blocks parse, check, lower, and
// verify end to end, while every binding mismatch the contract names is a
// hard rejection. C4 adds the MIR binding lowering and the generated
// _Static_assert probe unit; the checks here pin the checker surface that
// decides the rejections before any C is produced.

const m8BindingProgram = `import c "time.h" as ctime {
    scalar type Time = "time_t"

    opaque type File = "FILE"

    record type Timespec = "struct timespec" {
        seconds: Time = "tv_sec"
        nanos: c.Long = "tv_nsec"
    }

    const ClockRealtime = "CLOCK_REALTIME": c.Int

    raw fn get = "timespec_get"(
        value: c.Ptr(Timespec),
        base: c.Int,
    ) -> c.Int

    raw fn open = "fopen"(
        path: c.ConstPtr(c.Char),
        mode: c.ConstPtr(c.Char),
    ) -> c.Ptr(File)
}

fn main() -> I32 {
    return 0
}
`

var m8BindingRejections = []struct {
	name, source, want string
}{
	{
		"public-block",
		"pub import c \"time.h\" as ctime {\n    opaque type File = \"FILE\"\n}\nfn main() -> I32 { return 0 }\n",
		"public C binding blocks are not supported",
	},
	{
		"missing-spelling",
		"import c \"time.h\" as ctime {\n    opaque type File =\n}\nfn main() -> I32 { return 0 }\n",
		"expected a C spelling string",
	},
	{
		"malformed-member",
		"import c \"time.h\" as ctime {\n    fn f() -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"expected a C binding member declaration",
	},
	{
		"member-separator",
		"import c \"time.h\" as ctime {\n    opaque type A = \"A\"    opaque type B = \"B\"\n}\nfn main() -> I32 { return 0 }\n",
		"expected a C binding member declaration",
	},
	{
		"field-separator",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int    b: c.Int\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"C binding record fields must be separated by a physical line break",
	},
	{
		"duplicate-header",
		"import c \"time.h\" as ctime {\n    opaque type A = \"A\"\n}\n\nimport c \"time.h\" as wall {\n    opaque type B = \"B\"\n}\nfn main() -> I32 { return 0 }\n",
		"a module binds the same C header twice",
	},
	{
		"duplicate-member-name",
		"import c \"time.h\" as ctime {\n    opaque type A = \"A\"\n    raw fn A = \"a_fn\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block declares the same member name twice",
	},
	{
		"duplicate-field-name",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int\n        a: c.Int = \"y\"\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block declares the same member name twice",
	},
	{
		"duplicate-member-spelling",
		"import c \"time.h\" as ctime {\n    opaque type A = \"same\"\n    raw fn f = \"same\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block maps two members to the same C spelling",
	},
	{
		"duplicate-field-spelling",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int = \"x\"\n        b: c.Int = \"x\"\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block maps two members to the same C spelling",
	},
	{
		"underscore-spelling",
		"import c \"time.h\" as ctime {\n    raw fn f = \"_f\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"C spelling must be a non-reserved C identifier",
	},
	{
		"keyword-spelling",
		"import c \"time.h\" as ctime {\n    raw fn f = \"int\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"C spelling must be a non-reserved C identifier",
	},
	{
		"runtime-prefix-spelling",
		"import c \"time.h\" as ctime {\n    raw fn f = \"alder_f\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"C spelling must be a non-reserved C identifier",
	},
	{
		"scalar-tag-form",
		"import c \"time.h\" as ctime {\n    scalar type T = \"struct timespec\"\n}\nfn main() -> I32 { return 0 }\n",
		"scalar binding spelling may not use a struct, union, or enum tag form",
	},
	{
		"unknown-c-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: c.Longlong) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"unknown C type in the c namespace",
	},
	{
		"unknown-member-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: Missing) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"unknown binding type name in a C binding block",
	},
	{
		"bare-pointer-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: c.Ptr) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"c.Ptr and c.ConstPtr take exactly one type argument",
	},
	{
		"foreign-namespace-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: elsewhere.Thing) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"invalid type in a C binding block",
	},
	{
		"ordinary-applied-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: Vec(I32)) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"invalid type in a C binding block",
	},
	{
		"opaque-by-value",
		"import c \"time.h\" as ctime {\n    opaque type File = \"FILE\"\n    raw fn f = \"f\"(v: File) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"non-scalar C binding types are only valid behind c.Ptr or c.ConstPtr",
	},
	{
		"record-by-value",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int\n    }\n    raw fn f = \"f\"(v: T) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"non-scalar C binding types are only valid behind c.Ptr or c.ConstPtr",
	},
	{
		"non-integral-const",
		"import c \"time.h\" as ctime {\n    const Epsilon = \"EPSILON\": c.Double\n}\nfn main() -> I32 { return 0 }\n",
		"a C binding constant must have an integral c.* type",
	},
	{
		"unsafe-not-raw-fn",
		"import c \"time.h\" as ctime {\n    const Mark = \"MARK\": c.Int\n}\nfn helper() -> I32 { return 0 }\nfn main() -> I32 {\n    let v = unsafe c { helper() }\n    return 0\n}\n",
		"unsafe c does not name a raw fn of a C binding block",
	},
	{
		"argument-mismatch",
		"import c \"time.h\" as ctime {\n    opaque type File = \"FILE\"\n    raw fn open = \"fopen\"(path: c.ConstPtr(c.Char)) -> c.Ptr(File)\n}\nfn main() -> I32 {\n    let v = unsafe c { ctime.open(1) }\n    return 0\n}\n",
		"a C binding call argument does not match its declared C parameter",
	},
	{
		"argument-count",
		"import c \"time.h\" as ctime {\n    opaque type File = \"FILE\"\n    raw fn open = \"fopen\"(path: c.ConstPtr(c.Char)) -> c.Ptr(File)\n}\nfn main() -> I32 {\n    let v = unsafe c { ctime.open() }\n    return 0\n}\n",
		"a C binding call takes 1 argument(s), got 0",
	},
	{
		"is-null-argument",
		"import c \"time.h\" as ctime {\n    raw fn no = \"f\"() -> c.Int\n}\nfn main() -> I32 {\n    let value = unsafe c { ctime.no() }\n    if c.is_null(value) { return 1 }\n    return 0\n}\n",
		"c.is_null takes one raw C pointer",
	},
	{
		"dropped-result",
		"import c \"time.h\" as ctime {\n    raw fn no = \"f\"() -> c.Int\n}\nfn main() -> I32 {\n    unsafe c { ctime.no() }\n    return 0\n}\n",
		"a C binding call's non-unit result must be used",
	},
}

func TestM8BindingProductionQualification(t *testing.T) {
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

	files := map[string]string{"m8-bindings.al": m8BindingProgram}
	check := runProductionCompiler(t, exe, files, "check", "m8-bindings.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("binding check result: %+v stderr=%s", check, check.stderr)
	}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "m8-bindings.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("binding MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "m8-bindings.al")
	if repeat != mirText {
		t.Fatal("binding MIR changed across processes")
	}

	for _, rejection := range m8BindingRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "reject.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: status=%d stderr=%q", rejection.name, result.status, result.stderr)
			}
		})
	}
}

// The fixture header and definition the unsafe-call programs bind. The
// functions observe raw results only through pointer nullness: C4's
// surface has no c.*-to-Alder conversion yet, so pointer identity is the
// sanctioned observable until the checked-conversion commit.
const m8FixtureHeader = `#ifndef FIXT_H
#define FIXT_H
struct fixt_ts { long long sec; long ns; };
typedef struct fixt_file fixt_file;
#define FIXT_THREE 3
int fixt_five(void);
int fixt_yes(void);
int fixt_no(void);
void fixt_reset(void);
fixt_file *fixt_handle(int nullp);
fixt_file *fixt_round(fixt_file *f);
#endif
`

const m8FixtureSource = `#include "fixt.h"
static struct fixt_file { int handle; } the_file = { 42 };
int fixt_five(void) { return 5; }
int fixt_yes(void) { return 1; }
int fixt_no(void) { return 0; }
void fixt_reset(void) { the_file.handle = 42; }
fixt_file *fixt_handle(int nullp) { return nullp ? (fixt_file *)0 : &the_file; }
fixt_file *fixt_round(fixt_file *f) { return f; }
`

const m8UnsafeProgram = `import c "fixt.h" as cfx {
    opaque type File = "fixt_file"

    record type Ts = "struct fixt_ts" {
        seconds: c.LongLong = "sec"
        nanos: c.Long = "ns"
    }

    const Three = "FIXT_THREE": c.Int

    raw fn five = "fixt_five"() -> c.Int
    raw fn yes = "fixt_yes"() -> c.Int
    raw fn no = "fixt_no"() -> c.Int
    raw fn reset = "fixt_reset"() -> Unit
    raw fn handle = "fixt_handle"(nullp: c.Int) -> c.Ptr(File)
    raw fn round = "fixt_round"(f: c.Ptr(File)) -> c.Ptr(File)
}

fn main() -> I32 {
    let no = unsafe c { cfx.no() }
    let pointer = unsafe c { cfx.handle(no) }
    if c.is_null(pointer) { return 1 }
    let yes = unsafe c { cfx.yes() }
    let null_pointer = unsafe c { cfx.handle(yes) }
    if !c.is_null(null_pointer) { return 2 }
    let identity = unsafe c { cfx.round(pointer) }
    if c.is_null(identity) { return 3 }
    unsafe c { cfx.reset() }
    return 0
}
`

const m8ErrnoProgram = `import c "alder_errno.h" as cerrno {
    raw fn last = "c_errno"() -> c.Int
    raw fn message = "c_strerror"(code: c.Int) -> c.ConstPtr(c.Char)
}

fn main() -> I32 {
    let code = unsafe c { cerrno.last() }
    let text = unsafe c { cerrno.message(code) }
    if c.is_null(text) { return 1 }
    return 0
}
`

// TestM8BindingUnsafeCallsProduction drives raw fn members and unsafe c
// calls through the production driver: the generated translation unit
// includes the fixture header, pins every binding member with
// _Static_assert probes, compiles under the strict C11 set, links against
// the fixture, and runs to the is_null-observed success exit. Generation is
// deterministic across processes, a wrong fixture header fails the probe
// unit with a message naming the Alder binding member, and the sanitizer
// build runs the same program clean.
func TestM8BindingUnsafeCallsProduction(t *testing.T) {
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

	dir := t.TempDir()
	files := map[string]string{
		"m8-unsafe.al": m8UnsafeProgram,
		"fixt.h":       m8FixtureHeader,
		"fixt.c":       m8FixtureSource,
	}
	generated := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "-o", "program.c", "m8-unsafe.al")
	if generated.status != 0 || generated.stderr != "" {
		t.Fatalf("unsafe-call emit=c result: %+v stderr=%s", generated, generated.stderr)
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "-o", "program-2.c", "m8-unsafe.al")
	if repeat.status != 0 || repeat.stdout != generated.stdout || repeat.stderr != generated.stderr {
		t.Fatalf("unsafe-call emit=c changed across processes: %+v vs %+v", repeat, generated)
	}
	program, err := os.ReadFile(filepath.Join(dir, "program.c"))
	if err != nil {
		t.Fatal(err)
	}
	program2, err := os.ReadFile(filepath.Join(dir, "program-2.c"))
	if err != nil {
		t.Fatal(err)
	}
	if string(program) != string(program2) || len(program) == 0 {
		t.Fatal("unsafe-call generated C is empty or process-nondeterministic")
	}
	for _, fragment := range []string{
		`#include <fixt.h>`,
		`_Static_assert(_Generic(&fixt_handle, fixt_file * (*)(int): 1, default: 0)`,
		`_Static_assert(_Generic(((alder_bind_0_t1 *)0)->sec, long long: 1, default: 0)`,
		`_Static_assert((FIXT_THREE) == (int)(FIXT_THREE)`,
		`binding cfx.handle (fixt_handle)`,
	} {
		if !strings.Contains(string(program), fragment) {
			t.Fatalf("generated program misses probe fragment %q", fragment)
		}
	}

	runtimeObject := buildRuntimeObject(t, cc, root)
	driverText := `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, string(program), driverText, 0,
		"-I", dir, filepath.Join(dir, "fixt.c"))

	// A fixture header that disagrees with any declared binding member must
	// fail the probe unit, and the failure must name the Alder member path.
	wrongDir := t.TempDir()
	wrongHeader := strings.Replace(m8FixtureHeader, "long ns;", "int ns;", 1)
	if wrongHeader == m8FixtureHeader {
		t.Fatal("wrong-fixture mutation changed nothing")
	}
	if err := os.WriteFile(filepath.Join(wrongDir, "fixt.h"), []byte(wrongHeader), 0o644); err != nil {
		t.Fatal(err)
	}
	probeExe := filepath.Join(dir, "probe-wrong")
	args := strictC11Flags()
	args = append(args, "-I", wrongDir, "-I", filepath.Join(root, "runtime", "c"),
		"-I", filepath.Join(root, "bootstrap"), filepath.Join(dir, "program.c"),
		filepath.Join(dir, "driver.c"), runtimeObject, "-o", probeExe)
	if err := os.WriteFile(filepath.Join(dir, "driver.c"), []byte(driverText), 0o644); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(cc, args...).CombinedOutput()
	if err == nil {
		t.Fatalf("wrong fixture header compiled: %s", output)
	}
	for _, fragment := range []string{"binding cfx.Ts", "nanos", "field type does not match"} {
		if !strings.Contains(string(output), fragment) {
			t.Fatalf("wrong-header failure misses %q:\n%s", fragment, output)
		}
	}
}

// TestM8BindingUnsafeCallsSanitizers reruns the unsafe-call program under
// ASan/UBSan: the raw pointer chain crosses real C calls, so a lowering
// mistake that strict C11 cannot see still trips the sanitizers.
func TestM8BindingUnsafeCallsSanitizers(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	if !closureSanitizersSupported(t, cc) {
		t.Skip("ASan/UBSan not supported by this host toolchain")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	dir := t.TempDir()
	files := map[string]string{
		"m8-unsafe.al": m8UnsafeProgram,
		"fixt.h":       m8FixtureHeader,
		"fixt.c":       m8FixtureSource,
	}
	generated := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "-o", "program.c", "m8-unsafe.al")
	if generated.status != 0 || generated.stderr != "" {
		t.Fatalf("unsafe-call emit=c result: %+v stderr=%s", generated, generated.stderr)
	}
	sanitizer := []string{"-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer"}
	runtimeObject := filepath.Join(t.TempDir(), "alder-san.o")
	runtimeArgs := append(append([]string{}, strictC11Flags()...), sanitizer...)
	runtimeArgs = append(runtimeArgs, "-I", filepath.Join(root, "runtime", "c"),
		"-c", filepath.Join(root, "runtime", "c", "alder.c"), "-o", runtimeObject)
	if out, err := exec.Command(cc, runtimeArgs...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized runtime compile: %v\n%s", err, out)
	}
	fixtureObject := filepath.Join(t.TempDir(), "fixt-san.o")
	fixtureArgs := append(append([]string{}, strictC11Flags()...), sanitizer...)
	fixtureArgs = append(fixtureArgs, "-I", dir, "-c", filepath.Join(dir, "fixt.c"), "-o", fixtureObject)
	if out, err := exec.Command(cc, fixtureArgs...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized fixture compile: %v\n%s", err, out)
	}
	exePath := filepath.Join(dir, "program-san")
	args := append(append([]string{}, strictC11Flags()...), sanitizer...)
	args = append(args, "-I", dir, "-I", filepath.Join(root, "runtime", "c"),
		"-I", filepath.Join(root, "bootstrap"), filepath.Join(dir, "program.c"),
		filepath.Join(dir, "driver.c"), fixtureObject, runtimeObject, "-o", exePath)
	if err := os.WriteFile(filepath.Join(dir, "driver.c"), []byte(`#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized program compile: %v\n%s", err, out)
	}
	if err := exec.Command(exePath).Run(); err != nil {
		t.Fatalf("sanitized program status: err=%v want=0", err)
	}
}

// TestM8BindingErrnoShimProduction covers the toolchain-owned errno and
// strerror shims: the wrapper-facing raw operations a binding block cannot
// spell against real headers. The generated probe unit pins the shim
// signatures through the runtime header, and the program calls both shims
// end to end. The errno VALUE assertions belong to the checked-conversion
// commit, which adds the c.Int-to-I32 surface this test intentionally does
// not use.
func TestM8BindingErrnoShimProduction(t *testing.T) {
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

	files := map[string]string{"m8-errno.al": m8ErrnoProgram}
	generated := runProductionCompiler(t, exe, files, "compile", "--emit=c", "m8-errno.al")
	if generated.status != 0 || generated.stderr != "" {
		t.Fatalf("errno shim emit=c result: %+v stderr=%s", generated, generated.stderr)
	}
	for _, fragment := range []string{
		`#include <alder_errno.h>`,
		`_Static_assert(_Generic(&c_errno, int (*)(void): 1, default: 0)`,
		`_Static_assert(_Generic(&c_strerror, const char * (*)(int): 1, default: 0)`,
	} {
		if !strings.Contains(generated.stdout, fragment) {
			t.Fatalf("errno shim program misses probe fragment %q", fragment)
		}
	}
	runtimeObject := buildRuntimeObject(t, cc, root)
	driverText := `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, generated.stdout, driverText, 0)
}
