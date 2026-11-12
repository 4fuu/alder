package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// The M8 explicit-shim surface is a header of static inline C functions
// shipped beside the declaring package or sysroot. The binding block uses the
// ordinary header-binding syntax; the generated program includes the header
// through the same explicit -I root as any other binding. The dirent half
// exercises a flexible array member through a pointer and a bounded name
// length; the pipe half passes two out-parameters with c.addr.
const shimProgram = `import c "std/c/fs_shim.h" as fsshim {
    opaque type Dir = "DIR"
    opaque type Entry = "struct dirent"

    raw fn opendir = "opendir"(name: c.ConstPtr(c.Char)) -> c.Ptr(Dir)
    raw fn readdir = "readdir"(dir: c.Ptr(Dir)) -> c.Ptr(Entry)
    raw fn closedir = "closedir"(dir: c.Ptr(Dir)) -> c.Int
    raw fn dirent_name = "fs_dirent_name"(entry: c.ConstPtr(Entry)) -> c.ConstPtr(c.Char)
    raw fn dirent_name_length = "fs_dirent_name_length"(entry: c.ConstPtr(Entry)) -> c.Size
    raw fn pipe = "fs_pipe"(read_end: c.Ptr(c.Int), write_end: c.Ptr(c.Int)) -> c.Int
    raw fn close = "fs_close"(fd: c.Int) -> c.Int
}

fn main() -> I32 {
    using path = c.CString(".")
    let dir = unsafe c { fsshim.opendir(path.ptr()) }
    if c.is_null(dir) { return 1 }
    let entry = unsafe c { fsshim.readdir(dir) }
    if c.is_null(entry) {
        let closed = unsafe c { fsshim.closedir(dir) }
        if closed.to_i32() != 0 { return 2 }
        return 3
    }
    let name = unsafe c { fsshim.dirent_name(entry) }
    let length = unsafe c { fsshim.dirent_name_length(entry) }
    if c.is_null(name) { return 4 }
    if length.to_u64() == 0 || length.to_u64() > 255 { return 5 }
    let closed = unsafe c { fsshim.closedir(dir) }
    if closed.to_i32() != 0 { return 6 }

    var read_end = c.Zero(c.Int)
    var write_end = c.Zero(c.Int)
    let made = unsafe c { fsshim.pipe(c.addr(read_end), c.addr(write_end)) }
    if made.to_i32() != 0 { return 7 }
    let closed_read = unsafe c { fsshim.close(read_end) }
    let closed_write = unsafe c { fsshim.close(write_end) }
    if closed_read.to_i32() != 0 { return 8 }
    if closed_write.to_i32() != 0 { return 9 }
    return 0
}
`

// fs_shim.h is the whole C surface. It is deliberately header-only: static
// inline definitions add no link symbol, so a shim shipped by a package or
// sysroot cannot collide with a C library. The names are fs_*, never the
// runtime-reserved alder_ prefix.
const shimHeader = `#ifndef FS_SHIM_H
#define FS_SHIM_H
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <stddef.h>
#include <unistd.h>

static inline const char *fs_dirent_name(const struct dirent *entry) {
    return entry == NULL ? (const char *)0 : entry->d_name;
}

static inline size_t fs_dirent_name_length(const struct dirent *entry) {
    size_t length = 0;
    if (entry == NULL) { return 0; }
    while (entry->d_name[length] != '\0') { length = length + 1; }
    return length;
}

static inline int fs_pipe(int *read_end, int *write_end) {
    int ends[2];
    if (pipe(ends) != 0) { return -1; }
    *read_end = ends[0];
    *write_end = ends[1];
    return 0;
}

static inline int fs_close(int fd) { return close(fd); }
#endif
`

func TestM8HeaderShimProduction(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the dirent shim fixture uses POSIX dirent.h")
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
		"shim.al":                 shimProgram,
		"sysroot/std/c/fs_shim.h": shimHeader,
	}
	generated := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "shim.al")
	if generated.status != 0 || generated.stderr != "" {
		t.Fatalf("shim emit=c result: %+v stderr=%s", generated, generated.stderr)
	}
	for _, fragment := range []string{
		`#include <std/c/fs_shim.h>`,
		`_Static_assert(_Generic(&fs_dirent_name, const char * (*)(const struct dirent *): 1, default: 0)`,
		`_Static_assert(_Generic(&fs_pipe, int (*)(int *, int *): 1, default: 0)`,
	} {
		if !strings.Contains(generated.stdout, fragment) {
			t.Fatalf("generated shim program misses %q", fragment)
		}
	}

	runtimeObject := buildRuntimeObject(t, cc, root)
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, generated.stdout,
		`#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`, 0, "-I", filepath.Join(dir, "sysroot"))
}

func buildSanitizedRuntimeObject(t *testing.T, cc, root string) string {
	t.Helper()
	object := filepath.Join(t.TempDir(), "alder-san.o")
	args := append(append([]string{}, strictC11Flags()...), "-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer")
	args = append(args, "-I", filepath.Join(root, "runtime", "c"),
		"-c", filepath.Join(root, "runtime", "c", "alder.c"), "-o", object)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("sanitized runtime compile: %v\n%s", err, output)
	}
	return object
}

func TestM8HeaderShimSanitizers(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the dirent shim fixture uses POSIX dirent.h")
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
	if err := os.MkdirAll(filepath.Join(dir, "sysroot", "std", "c"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sysroot", "std", "c", "fs_shim.h"), []byte(shimHeader), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "shim.al"), []byte(shimProgram), 0o644); err != nil {
		t.Fatal(err)
	}
	generated := runProductionCompilerAtRoot(t, exe, dir, nil, "compile", "--emit=c", "shim.al")
	if generated.status != 0 || generated.stderr != "" {
		t.Fatalf("shim emit=c sanitizer result: %+v stderr=%s", generated, generated.stderr)
	}
	runtimeObject := buildSanitizedRuntimeObject(t, cc, root)
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, generated.stdout,
		`#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`, 0, "-fsanitize=address,undefined", "-g", "-fno-omit-frame-pointer",
		"-I", filepath.Join(dir, "sysroot"))
}
