package cgen

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

const hostStub = `#include "alder_host.h"
#include <stdint.h>
int32_t alder_program_entry(void *context) {
    uint64_t i;
    const uint8_t stdout_expected[] = {'O', 10, 0, 255};
    const uint8_t stderr_expected[] = {'E', 10, 0, 254};
    (void)context;
    if (alderhost_source_count() != 2) return 10;
    if (alderhost_source_path_len(0) != 4 || alderhost_source_path_byte(0, 0) != 'a') return 11;
    if (alderhost_source_path_len(1) != 4 || alderhost_source_path_byte(1, 0) != 'b') return 12;
    if (alderhost_source_text_len(0) != 4100 || alderhost_source_text_len(1) != 0) return 13;
    if (alderhost_source_text_byte(0, 0) != 'A' ||
        alderhost_source_text_byte(0, 4095) != 0 ||
        alderhost_source_text_byte(0, 4096) != 255 ||
        alderhost_source_text_byte(0, 4099) != 'Z') return 14;
    for (i = 0; i < 4; i++) {
        if (!alderhost_stdout_byte(stdout_expected[i]) ||
            !alderhost_stderr_byte(stderr_expected[i])) return 15;
    }
    return 0;
}
`

func buildHost(t *testing.T, cc, stub string) string {
	t.Helper()
	dir := t.TempDir()
	stubPath := filepath.Join(dir, "stub.c")
	if err := os.WriteFile(stubPath, []byte(stub), 0o644); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(dir, "host.exe")
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join("..", "bootstrap"), filepath.Join("..", "bootstrap", "alder_host.c"), stubPath, "-o", exe}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("compile hosted ABI: %v\n%s", err, out)
	}
	return exe
}

func TestHostedSourceAndOutputABI(t *testing.T) {
	for _, cc := range findCompilers(t) {
		exe := buildHost(t, cc, hostStub)
		dir := t.TempDir()
		input := bytes.Repeat([]byte{'x'}, 4100)
		input[0] = 'A'
		input[4095] = 0
		input[4096] = 255
		input[4099] = 'Z'
		if err := os.WriteFile(filepath.Join(dir, "a.al"), input, 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "b.al"), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command(exe, "b.al", "a.al")
		cmd.Dir = dir
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		err := cmd.Run()
		if err != nil || !bytes.Equal(stdout.Bytes(), []byte{'O', '\n', 0, 255}) ||
			!bytes.Equal(stderr.Bytes(), []byte{'E', '\n', 0, 254}) {
			t.Fatalf("host run: err=%v stdout=%v stderr=%v", err, stdout.Bytes(), stderr.Bytes())
		}
	}
}

func TestHostedInputFailures(t *testing.T) {
	for _, cc := range findCompilers(t) {
		exe := buildHost(t, cc, "#include \"alder_host.h\"\nint32_t alder_program_entry(void *p) { (void)p; return 0; }\n")
		dir := t.TempDir()
		if err := os.WriteFile(filepath.Join(dir, "same"), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		for _, tc := range []struct {
			args    []string
			message string
		}{
			{[]string{"same", "same"}, "alder host: duplicate source: same\n"},
			{[]string{"missing"}, "alder host: cannot open source: missing\n"},
		} {
			cmd := exec.Command(exe, tc.args...)
			cmd.Dir = dir
			out, err := cmd.CombinedOutput()
			var exit *exec.ExitError
			if !errors.As(err, &exit) || exit.ExitCode() != 1 || string(out) != tc.message {
				t.Fatalf("args %v: err=%v output=%q", tc.args, err, out)
			}
		}
	}
}

func TestHostedAccessorContractFailure(t *testing.T) {
	for _, cc := range findCompilers(t) {
		stub := "#include \"alder_host.h\"\nint32_t alder_program_entry(void *p) { (void)p; (void)alderhost_source_path_len(0); return 0; }\n"
		exe := buildHost(t, cc, stub)
		out, err := exec.Command(exe).CombinedOutput()
		if err == nil || string(out) != "alder host: source accessor contract violation\n" {
			t.Fatalf("contract violation: err=%v output=%q", err, out)
		}
	}
}
