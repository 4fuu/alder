package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 C-boundary conversion surface through the production driver. The
// errno program observes a real errno VALUE left by a failed C library
// call and reads it through the conversion methods in every direction:
// the bare total form crosses unchanged, the checked narrowing carries an
// in-range value as some, and the Alder-to-C round trip comes home as
// some. The fixture program covers the scalar sources a binding can
// produce (c.Long, c.ULongLong, c.Double, c.Float, c.Char), the float
// specials (to_c_float, to_c_double, to_c_float_checked), the wrapping
// forms at the 32-bit edges, and a by-value pass-back of a converted
// scalar. The rejections pin diagnostic 205 for the lossy bare forms and
// for pairs the model refuses (integer receivers into float c targets,
// checked forms on the total float pair, c_char without a runtime
// check). c.Char's checked form is host-dependent by design: this test
// documents the signed-char host, where (char)-1 is outside U8's range.
const cConvertErrnoProgram = `import c "alder_errno.h" as cerrno {
    raw fn last = "c_errno"() -> c.Int
    raw fn message = "c_strerror"(code: c.Int) -> c.ConstPtr(c.Char)
}
import c "stdio.h" as stdio {
    raw fn remove = "remove"(path: c.ConstPtr(c.Char)) -> c.Int
}

fn main() -> I32 {
    let seed = unsafe c { cerrno.last() }
    let path = unsafe c { cerrno.message(seed) }
    let status = unsafe c { stdio.remove(path) }
    if status.to_i32() == 0 { return 1 }
    let code = unsafe c { cerrno.last() }
    // A failed remove leaves ENOENT, whose hosted value is 2: the bare
    // total conversion crosses the boundary unchanged.
    if code.to_i32() != 2 { return 2 }
    // The checked narrowing into I16 carries an in-range value as some.
    match code.to_i16_checked() {
        Some(v) => { if v != 2 { return 3 } }
        None => { return 4 }
    }
    // The total widening into I64 accepts the bare form.
    if code.to_i64() != 2 { return 5 }
    // Alder -> C -> Alder round trip: the bare form crosses out and the
    // checked form comes home as some.
    let out_value = code.to_i32()
    let out = out_value.to_c_int()
    match out.to_i32_checked() {
        Some(v) => { if v != 2 { return 6 } }
        None => { return 7 }
    }
    return 0
}
`

const cConvertFixtureHeader = `#ifndef CCONVERT_H
#define CCONVERT_H
long cfx_long(void);
unsigned long long cfx_ulonglong(void);
double cfx_double(void);
float cfx_float(void);
char cfx_char(void);
int cfx_take_long(long value);
#endif
`

const cConvertFixtureSource = `#include "cconvert.h"
long cfx_long(void) { return 4321L; }
unsigned long long cfx_ulonglong(void) { return 18446744073709551615ULL; }
double cfx_double(void) { return 3.5; }
float cfx_float(void) { return 1.25f; }
char cfx_char(void) { return (char)-1; }
int cfx_take_long(long value) { return (int)(value / 2); }
`

const cConvertScalarProgram = `import c "cconvert.h" as cfx {
    raw fn long_value = "cfx_long"() -> c.Long
    raw fn ull_value = "cfx_ulonglong"() -> c.ULongLong
    raw fn double_value = "cfx_double"() -> c.Double
    raw fn float_value = "cfx_float"() -> c.Float
    raw fn char_value = "cfx_char"() -> c.Char
    raw fn take_long = "cfx_take_long"(value: c.Long) -> c.Int
}

fn t_scalars() -> I32 {
    let long_value = unsafe c { cfx.long_value() }
    // c.Long into I32 is lossy in general: only the checked form reads it.
    match long_value.to_i32_checked() {
        Some(v) => { if v != 4321 { return 1 } }
        None => { return 2 }
    }
    // The total widening into I64 is bare.
    if long_value.to_i64() != 4321 { return 3 }
    // Passing the scalar back into C by value observes the same value.
    let passed = unsafe c { cfx.take_long(long_value) }
    match passed.to_i32_checked() {
        Some(v) => { if v != 2160 { return 4 } }
        None => { return 5 }
    }
    // c.ULongLong into I64 is the checked sign-change narrowing:
    // UINT64_MAX is outside and yields none.
    let ull = unsafe c { cfx.ull_value() }
    match ull.to_i64_checked() {
        Some(_) => { return 6 }
        None => {}
    }
    // c.Double and c.Float read through their equal-precision total forms.
    // The round trips are exact (D026 float comparisons): dback equals the
    // C double 3.5 and fback equals the C float 1.25, and both values sit
    // inside float's range, so the checked narrowing yields some.
    let d = unsafe c { cfx.double_value() }
    let dback = d.to_f64()
    if dback != 3.5 { return 7 }
    match dback.to_c_float_checked() {
        Some(_) => {}
        None => { return 10 }
    }
    let f = unsafe c { cfx.float_value() }
    let fback = f.to_f32()
    if fback != 1.25 { return 8 }
    // F32 has no checked narrowing of its own; widen through the total
    // c.Float form into F64 and assert the range there.
    let fwide = fback.to_c_float()
    let fwidened = fwide.to_f64()
    match fwidened.to_c_float_checked() {
        Some(_) => {}
        None => { return 11 }
    }
    // c.Char's signedness is target-dependent: the checked form runs at
    // runtime, and (char)-1 on this host is outside U8's range.
    let ch = unsafe c { cfx.char_value() }
    match ch.to_u8_checked() {
        Some(_) => { return 9 }
        None => {}
    }
    return 0
}

fn t_floats() -> I32 {
    // F64 -> c.Double and c.Double -> F64 are the total bare forms; the
    // round trip is exact (D026 float comparisons): back equals 1.5 after
    // the round trip, widened equals 1.5 after the checked narrowing, and
    // fback equals 0.5 after the F32 round trip.
    let d: F64 = 1.5
    let cd = d.to_c_double()
    let back = cd.to_f64()
    if back != 1.5 { return 1 }
    match back.to_c_float_checked() {
        Some(_) => {}
        None => { return 1 }
    }
    // F64 -> c.Float checked narrows in-range values as some and yields
    // none beyond float's range.
    let narrow = d.to_c_float_checked()
    match narrow {
        Some(v) => {
            let widened = v.to_f64()
            if widened != 1.5 { return 6 }
            match widened.to_c_float_checked() {
                Some(_) => {}
                None => { return 2 }
            }
        }
        None => { return 3 }
    }
    let big: F64 = 1e300
    match big.to_c_float_checked() {
        Some(_) => { return 4 }
        None => {}
    }
    // F32 -> c.Float and c.Float -> F32 are the total bare forms, and the
    // round trip is exact: fback compares equal to 0.5. F32 has no
    // checked narrowing; widen through c.Float into F64 and assert the
    // range there.
    let f: F32 = 0.5
    let cf = f.to_c_float()
    let fback = cf.to_f32()
    if fback != 0.5 { return 7 }
    let fwide = fback.to_c_float()
    let fwidened = fwide.to_f64()
    match fwidened.to_c_float_checked() {
        Some(_) => {}
        None => { return 5 }
    }
    return 0
}

fn t_wrapping() -> I32 {
    // I64 into c.UInt wrapping keeps the low 32 bits.
    let big: I64 = 4294967296
    let wrapped = big.to_c_uint_wrapping()
    let read_back = wrapped.to_u32()
    if read_back != 0 { return 1 }
    // I32 into c.UInt wrapping reinterprets the bit pattern.
    let neg: I32 = -1
    let bits = neg.to_c_uint_wrapping()
    let pattern = bits.to_u32()
    if pattern != 4294967295 { return 2 }
    // c.UInt into I32 wrapping brings the pattern back.
    let signed_back = bits.to_i32_wrapping()
    if signed_back != -1 { return 3 }
    return 0
}

fn main() -> I32 {
    let a = t_scalars()
    if a != 0 { return a }
    let b = t_floats()
    if b != 0 { return b + 10 }
    let c = t_wrapping()
    if c != 0 { return c + 20 }
    return 0
}
`

var cConvertRejections = []struct {
	name, source, want string
}{
	{
		"lossy-bare-c-to-alder",
		`import c "alder_errno.h" as cerrno {
    raw fn last = "c_errno"() -> c.Int
}
fn f() -> I32 {
    let code = unsafe c { cerrno.last() }
    return code.to_i16()
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"lossy-bare-c-char-target",
		`fn f(a: I32) -> I32 {
    let ch = a.to_c_char()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"integer-receiver-float-target",
		`fn f(a: I32) -> I32 {
    let f = a.to_c_float()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"bare-float-narrowing",
		`fn f(d: F64) -> I32 {
    let f = d.to_c_float()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"bare-c-double-to-f32",
		`fn f(d: F64) -> I32 {
    let cd = d.to_c_double()
    let f = cd.to_f32()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"checked-total-float-pair",
		`fn f(f: F32) -> I32 {
    let cf = f.to_c_float()
    let bad = cf.to_f32_checked()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"c-receiver-c-target",
		`import c "alder_errno.h" as cerrno {
    raw fn last = "c_errno"() -> c.Int
}
fn f() -> I32 {
    let code = unsafe c { cerrno.last() }
    let same = code.to_c_long()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
	{
		"unknown-method-name",
		`import c "alder_errno.h" as cerrno {
    raw fn last = "c_errno"() -> c.Int
}
fn f() -> I32 {
    let code = unsafe c { cerrno.last() }
    let f64v = code.to_f64()
    return 0
}
fn main() -> I32 { return 0 }
`,
		"no such C conversion method on this receiver",
	},
}

// TestM8CConvertProductionQualification drives the C-boundary conversion
// methods end to end: both programs emit deterministic C, compile under
// the strict C11 set, run to their success exits, and the errno program
// asserts the hosted ENOENT value through the conversion methods. The
// generated MIR carries no bootstrap names. The rejections pin diagnostic
// 205 for every pair the checker refuses.
func TestM8CConvertProductionQualification(t *testing.T) {
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

	// The errno program needs no fixture files: the toolchain-owned
	// alder_errno.h shim and the host stdio.h carry it.
	errnoFiles := map[string]string{"c-errno.al": cConvertErrnoProgram}
	errnoC := runProductionCompiler(t, exe, errnoFiles, "compile", "--emit=c", "c-errno.al")
	if errnoC.status != 0 || errnoC.stderr != "" || !strings.HasPrefix(errnoC.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("errno emit=c result: %+v stderr=%s", errnoC, errnoC.stderr)
	}
	errnoRepeat := runProductionCompiler(t, exe, errnoFiles, "compile", "--emit=c", "c-errno.al")
	if errnoRepeat != errnoC {
		t.Fatalf("errno emit=c changed across processes")
	}
	mirText := runProductionCompiler(t, exe, errnoFiles, "compile", "--emit=mir", "c-errno.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("errno MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	assertPublicMIR(t, "c-errno.al", mirText.stdout)
	if !strings.Contains(mirText.stdout, "c.num") {
		t.Fatalf("errno MIR carries no c.num conversion ops")
	}
	driverText := `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, errnoC.stdout, driverText, 0)

	// The scalar fixture program links its C fixture.
	dir := t.TempDir()
	scalarFiles := map[string]string{
		"c-scalar.al": cConvertScalarProgram,
		"cconvert.h":  cConvertFixtureHeader,
		"cconvert.c":  cConvertFixtureSource,
	}
	scalarC := runProductionCompilerAtRoot(t, exe, dir, scalarFiles, "compile", "--emit=c", "c-scalar.al")
	if scalarC.status != 0 || scalarC.stderr != "" {
		t.Fatalf("scalar emit=c result: %+v stderr=%s", scalarC, scalarC.stderr)
	}
	scalarRepeat := runProductionCompilerAtRoot(t, exe, dir, scalarFiles, "compile", "--emit=c", "c-scalar.al")
	if scalarRepeat.status != 0 || scalarRepeat.stdout != scalarC.stdout {
		t.Fatalf("scalar emit=c changed across processes")
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, scalarC.stdout, driverText, 0,
		"-I", dir, filepath.Join(dir, "cconvert.c"))

	for _, rejection := range cConvertRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
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
