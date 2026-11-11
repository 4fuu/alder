package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 call-scoped buffer borrows through the production driver. Inside
// `unsafe c`, a MutSlice(U8), [U8], or Bytes argument stands for a declared
// c.Ptr/c.ConstPtr parameter with a byte-addressable pointee; the borrow
// lasts exactly one call, never moves the buffer, and an empty buffer still
// passes a non-null address. The fixture rejects a null pointer even at
// count zero, so the zero-length cases prove the runtime dummy fallback.
const cBufferProgram = `import c "cbuffer.h" as buf {
    opaque type Buffer = "CBuffer"
    raw fn fill = "cbuf_fill"(buffer: c.Ptr(Buffer), count: c.Size) -> c.Size
    raw fn sum = "cbuf_sum"(buffer: c.ConstPtr(Buffer), count: c.Size) -> c.Size
    raw fn copy = "cbuf_copy"(dest: c.Ptr(Buffer), src: c.ConstPtr(Buffer), count: c.Size) -> c.Size
}

fn main() -> I32 {
    var bytes = Vec.new(U8)
    bytes.push(1)
    bytes.push(2)
    bytes.push(3)
    bytes.push(4)
    {
        let view = bytes.slice_mut(0, bytes.len())
        let filled = unsafe c { buf.fill(view, view.len().to_c_size()) }
        if filled.to_u64() != 4 { return 1 }
    }
    let slice = bytes.slice(0, bytes.len())
    let total = unsafe c { buf.sum(slice, slice.len().to_c_size()) }
    if total.to_u64() != 28 { return 2 }
    let text = "abc".to_bytes()
    let copied = unsafe c { buf.sum(text, text.len().to_c_size()) }
    if copied.to_u64() != 294 { return 3 }
    var empty = Vec.new(U8)
    {
        let empty_view = empty.slice_mut(0, 0)
        let zero = unsafe c { buf.fill(empty_view, empty_view.len().to_c_size()) }
        if zero.to_u64() != 0 { return 4 }
    }
    let empty_bytes = "".to_bytes()
    let none_sum = unsafe c { buf.sum(empty_bytes, empty_bytes.len().to_c_size()) }
    if none_sum.to_u64() != 0 { return 5 }
    return 0
}
`

const cBufferFixtureHeader = `#ifndef CBUFFER_H
#define CBUFFER_H
#include <stddef.h>
typedef struct CBuffer CBuffer;
size_t cbuf_fill(CBuffer *buffer, size_t count);
size_t cbuf_sum(const CBuffer *buffer, size_t count);
size_t cbuf_copy(CBuffer *dest, const CBuffer *src, size_t count);
size_t cbuf_wide(const int *values);
#endif
`

const cBufferFixtureSource = `#include "cbuffer.h"
size_t cbuf_fill(CBuffer *buffer, size_t count) {
    if (buffer == NULL) { return (size_t)-1; }
    unsigned char *bytes = (unsigned char *)buffer;
    for (size_t i = 0; i < count; i++) { bytes[i] = 7; }
    return count;
}
size_t cbuf_sum(const CBuffer *buffer, size_t count) {
    if (buffer == NULL) { return (size_t)-1; }
    const unsigned char *bytes = (const unsigned char *)buffer;
    size_t total = 0;
    for (size_t i = 0; i < count; i++) { total += bytes[i]; }
    return total;
}
size_t cbuf_copy(CBuffer *dest, const CBuffer *src, size_t count) {
    if (dest == NULL || src == NULL) { return (size_t)-1; }
    unsigned char *to = (unsigned char *)dest;
    const unsigned char *from = (const unsigned char *)src;
    for (size_t i = 0; i < count; i++) { to[i] = from[i]; }
    return count;
}
size_t cbuf_wide(const int *values) {
    if (values == NULL) { return (size_t)-1; }
    return (size_t)values[0];
}
`

const cBufferRejectBase = `import c "cbuffer.h" as buf {
    opaque type Buffer = "CBuffer"
    raw fn fill = "cbuf_fill"(buffer: c.Ptr(Buffer), count: c.Size) -> c.Size
    raw fn sum = "cbuf_sum"(buffer: c.ConstPtr(Buffer), count: c.Size) -> c.Size
    raw fn copy = "cbuf_copy"(dest: c.Ptr(Buffer), src: c.ConstPtr(Buffer), count: c.Size) -> c.Size
    raw fn wide = "cbuf_wide"(values: c.Ptr(c.Int)) -> c.Size
}
`

var cBufferRejections = []struct {
	name, body, want string
}{
	{
		"bytes-to-mutable",
		`fn f(data: Bytes) -> I32 {
    let n = unsafe c { buf.fill(data, data.len().to_c_size()) }
    return 0
}
`,
		"a mutable C pointer parameter requires a MutSlice(U8) argument",
	},
	{
		"slice-to-mutable",
		`fn f(data: [U8]) -> I32 {
    let n = unsafe c { buf.fill(data, data.len().to_c_size()) }
    return 0
}
`,
		"a mutable C pointer parameter requires a MutSlice(U8) argument",
	},
	{
		"wide-pointee",
		`fn f(data: Bytes) -> I32 {
    let n = unsafe c { buf.wide(data) }
    return 0
}
`,
		"a buffer argument requires a byte-addressable C pointee",
	},
	{
		"overlapping-borrow",
		`fn f(buffer: MutSlice(U8)) -> I32 {
    let n = unsafe c { buf.copy(buffer, buffer, buffer.len().to_c_size()) }
    return 0
}
`,
		"the same buffer is borrowed more than once in one unsafe C call",
	},
}

// TestM8CBufferBorrowProductionQualification drives the three buffer forms
// end to end: a MutSlice fills caller storage in place, an immutable [U8]
// and an owned Bytes value are read, and zero-length borrows of empty
// buffers reach C as a valid address. The emitted MIR carries c.buffer.ptr
// and the generated C carries the dummy fallback; the strict-warning program
// runs to success. The rejections pin the mutable, pointee, and overlap
// rules.
func TestM8CBufferBorrowProductionQualification(t *testing.T) {
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
		"c-buffer.al": cBufferProgram,
		"cbuffer.h":   cBufferFixtureHeader,
		"cbuffer.c":   cBufferFixtureSource,
	}
	check := runProductionCompilerAtRoot(t, exe, dir, files, "check", "c-buffer.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("c-buffer check result: %+v stderr=%s", check, check.stderr)
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-buffer.al")
	if emitted.status != 0 || emitted.stderr != "" || !strings.HasPrefix(emitted.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	if !strings.Contains(emitted.stdout, "alder_c_buffer_dummy") {
		t.Fatalf("generated C omits the empty-buffer dummy fallback")
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "c-buffer.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	mirText := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-buffer.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	assertPublicMIR(t, "c-buffer.al", mirText.stdout)
	if got := strings.Count(mirText.stdout, "c.buffer.ptr"); got != 5 {
		t.Fatalf("printed MIR carries %d c.buffer.ptr operations, want 5", got)
	}
	repeatMIR := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=mir", "c-buffer.al")
	if repeatMIR.status != 0 || repeatMIR.stdout != mirText.stdout {
		t.Fatalf("emit=mir changed across processes")
	}

	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cStringDriver, 0,
		"-I", dir, filepath.Join(dir, "cbuffer.c"))

	for _, rejection := range cBufferRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			source := cBufferRejectBase + rejection.body + "fn main() -> I32 { return 0 }\n"
			result := runProductionCompiler(t, exe, map[string]string{"reject.al": source}, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
