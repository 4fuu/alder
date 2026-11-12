package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func macroLine(text string) string {
	for _, line := range strings.Split(text, "\n") {
		if strings.Contains(line, "_POSIX_C_SOURCE") {
			return line
		}
	}
	return "(no _POSIX_C_SOURCE definition)"
}

// Newer glibc releases predefine _POSIX_C_SOURCE in features.h, and -Werror
// turns a different value in the shim into a build failure. The shim must keep
// a surface the build already selected instead of redefining it. The macro
// probe checks the preset value survives preprocessing; a syntax check then
// proves the header still declares everything it uses.
const ioShimPresetSource = `#include <stdio.h>
#include "std/c/io_shim.h"
int main(void) { return 0; }
`

func TestIoShimAcceptsPresetFeatureMacros(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(t.TempDir(), "shim.c")
	if err := os.WriteFile(source, []byte(ioShimPresetSource), 0o644); err != nil {
		t.Fatal(err)
	}
	preset := []string{"-std=c11", "-D_POSIX_C_SOURCE=202405L", "-D_XOPEN_SOURCE=700",
		"-I", filepath.Join(root, "sysroot")}
	macros, err := exec.Command(cc, append(preset, "-E", "-dM", source)...).CombinedOutput()
	if err != nil {
		t.Fatalf("preprocess io shim: %v\n%s", err, macros)
	}
	if !strings.Contains(string(macros), "#define _POSIX_C_SOURCE 202405L") {
		t.Fatalf("io shim replaced the preset _POSIX_C_SOURCE:\n%s", macroLine(string(macros)))
	}
	args := append(preset, "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow",
		"-Wconversion", "-ffp-contract=off", "-fsyntax-only", source)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("io shim with preset feature macros: %v\n%s", err, output)
	}
}
