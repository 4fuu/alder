package hosttest

import (
	"bytes"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

const stubEntry = `#include "alder_host.h"
#include <stdint.h>
#include <stdio.h>

static bool stub_write(const char *text) {
    size_t at = 0;
    while (text[at] != '\0') {
        if (!alderhost_stdout_byte((uint8_t)(unsigned char)text[at])) { return false; }
        at++;
    }
    return true;
}

static bool stub_wait(void) {
    for (;;) {
        FILE *file = fopen("start.signal", "rb");
        if (file != NULL) { return fclose(file) == 0; }
    }
}

int32_t alder_program_entry(void *host_context) {
    uint8_t mode;
    uint64_t at;
    (void)host_context;
    mode = alderhost_source_text_byte(0, 0);
    if (mode == (uint8_t)'S') { return ALDER_PROGRAM_FAILURE_STATUS; }
    if (mode == (uint8_t)'X') { return (int32_t)9; }
    if (mode == (uint8_t)'D') {
        if (alderhost_format_json()) {
            if (!stub_write("{\"version\":1,\"command\":\"compile\",\"success\":false,\"diagnostics\":[],\"failure\":{\"kind\":\"internal\",\"message\":\"driver failure\"}}\n")) { return (int32_t)3; }
        } else {
            if (!alderhost_output_mode(UINT64_C(1)) || !stub_write("alder: driver failure\n")) { return (int32_t)3; }
        }
        return (int32_t)4;
    }
    if (!stub_wait() || !alderhost_output_mode(UINT64_C(2))) { return (int32_t)3; }
    for (at = 0; at < UINT64_C(262144); at++) {
        if (!alderhost_stdout_byte(mode)) { return (int32_t)3; }
    }
    return (int32_t)0;
}
`

type result struct {
	status int
	stdout string
	stderr string
}

func compileHost(t *testing.T) string {
	t.Helper()
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	dir := t.TempDir()
	stub := filepath.Join(dir, "stub.c")
	exe := filepath.Join(dir, "alder1")
	if runtime.GOOS == "windows" {
		exe += ".exe"
	}
	if err := os.WriteFile(stub, []byte(stubEntry), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{
		"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion",
		"-I", "..", stub, filepath.Join("..", "alder_host.c"), "-o", exe,
	}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict host compile: %v\n%s", err, output)
	}
	return exe
}

func run(t *testing.T, exe, dir string, args ...string) result {
	t.Helper()
	command := exec.Command(exe, args...)
	command.Dir = dir
	var stdout, stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	err := command.Run()
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("run host: %v", err)
		}
		status = exit.ExitCode()
	}
	return result{status: status, stdout: stdout.String(), stderr: stderr.String()}
}

func source(t *testing.T, dir, name, text string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestUsageResponseFailuresAreIO(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("/dev/full probes require Linux")
	}
	exe := compileHost(t)
	for _, test := range []struct {
		name string
		json bool
	}{
		{"human", false},
		{"json", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			full, err := os.OpenFile("/dev/full", os.O_WRONLY, 0)
			if err != nil {
				t.Skip("/dev/full unavailable")
			}
			defer full.Close()
			args := []string{"bogus"}
			command := exec.Command(exe, args...)
			command.Stdout = io.Discard
			command.Stderr = io.Discard
			if test.json {
				command.Args = append(command.Args, "--format=json")
				command.Stdout = full
			} else {
				command.Stderr = full
			}
			err = command.Run()
			var exit *exec.ExitError
			if !errors.As(err, &exit) || exit.ExitCode() != 3 {
				t.Fatalf("status=%v, want 3", err)
			}
		})
	}
}

func TestEntryFailureResponsesAndNoDuplication(t *testing.T) {
	exe := compileHost(t)
	dir := t.TempDir()
	for _, mode := range []string{"S", "X", "D"} {
		source(t, dir, "main.al", mode)
		for _, json := range []bool{false, true} {
			args := []string{"compile", "--emit=mir", "main.al"}
			if json {
				args = []string{"compile", "--format=json", "--emit=mir", "main.al"}
			}
			got := run(t, exe, dir, args...)
			if got.status != 4 {
				t.Fatalf("mode=%s json=%v status=%d", mode, json, got.status)
			}
			message := "internal compiler failure"
			if mode == "D" {
				message = "driver failure"
			}
			if json {
				want := "{\"version\":1,\"command\":\"compile\",\"success\":false,\"diagnostics\":[],\"failure\":{\"kind\":\"internal\",\"message\":\"" + message + "\"}}\n"
				if got.stdout != want || got.stderr != "" {
					t.Fatalf("mode=%s JSON response=(%q,%q), want (%q, empty)", mode, got.stdout, got.stderr, want)
				}
			} else {
				want := "alder: " + message + "\n"
				if got.stdout != "" || got.stderr != want {
					t.Fatalf("mode=%s human response=(%q,%q), want (empty,%q)", mode, got.stdout, got.stderr, want)
				}
			}
		}
	}
}

func TestAtomicOutputReplacementAndIsolation(t *testing.T) {
	exe := compileHost(t)
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "start.signal"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	source(t, dir, "a.al", "A")
	got := run(t, exe, dir, "compile", "--emit=mir", "-o", "out.mir", "a.al")
	data, err := os.ReadFile(filepath.Join(dir, "out.mir"))
	if got != (result{}) || err != nil || len(data) != 262144 || strings.Trim(string(data), "A") != "" {
		t.Fatalf("successful replacement: result=%+v bytes=%d err=%v", got, len(data), err)
	}

	blocked := filepath.Join(dir, "blocked")
	if err := os.Mkdir(blocked, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(blocked, "marker"), []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	got = run(t, exe, dir, "compile", "--emit=mir", "-o", "blocked", "a.al")
	marker, markerErr := os.ReadFile(filepath.Join(blocked, "marker"))
	if got.status != 3 || got.stdout != "" || got.stderr != "alder: cannot write output file\n" || markerErr != nil || string(marker) != "keep" {
		t.Fatalf("failed replacement: result=%+v marker=%q err=%v", got, marker, markerErr)
	}
	assertNoTemps(t, dir)

	if err := os.WriteFile(filepath.Join(dir, "old.mir"), []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 1000; i++ {
		name := filepath.Join(dir, "old.mir.alder-tmp-"+strconv.Itoa(i))
		if err := os.WriteFile(name, []byte("reserved"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got = run(t, exe, dir, "compile", "--emit=mir", "-o", "old.mir", "a.al")
	old, oldErr := os.ReadFile(filepath.Join(dir, "old.mir"))
	if got.status != 3 || oldErr != nil || string(old) != "keep" {
		t.Fatalf("failed reservation changed existing output: result=%+v old=%q err=%v", got, old, oldErr)
	}
	for i := 0; i < 1000; i++ {
		name := filepath.Join(dir, "old.mir.alder-tmp-"+strconv.Itoa(i))
		if err := os.Remove(name); err != nil {
			t.Fatal(err)
		}
	}

	if err := os.Remove(filepath.Join(dir, "start.signal")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "shared.mir.alder-tmp-0"), []byte("reserved"), 0o644); err != nil {
		t.Fatal(err)
	}
	const processes = 16
	commands := make([]*exec.Cmd, 0, processes)
	for i := 0; i < processes; i++ {
		name := "a.al"
		if i%2 != 0 {
			name = "b.al"
			source(t, dir, name, "B")
		}
		command := exec.Command(exe, "compile", "--emit=mir", "-o", "shared.mir", name)
		command.Dir = dir
		command.Stdout = io.Discard
		command.Stderr = io.Discard
		if err := command.Start(); err != nil {
			t.Fatal(err)
		}
		commands = append(commands, command)
	}
	time.Sleep(100 * time.Millisecond)
	if err := os.WriteFile(filepath.Join(dir, "start.signal"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for _, command := range commands {
		if err := command.Wait(); err != nil {
			t.Fatalf("competing writer: %v", err)
		}
	}
	data, err = os.ReadFile(filepath.Join(dir, "shared.mir"))
	if err != nil || len(data) != 262144 || (strings.Trim(string(data), "A") != "" && strings.Trim(string(data), "B") != "") {
		t.Fatalf("isolated output: bytes=%d err=%v", len(data), err)
	}
	reserved, err := os.ReadFile(filepath.Join(dir, "shared.mir.alder-tmp-0"))
	if err != nil || string(reserved) != "reserved" {
		t.Fatalf("reserved candidate changed: %q err=%v", reserved, err)
	}
	assertNoTempsExcept(t, dir, "shared.mir.alder-tmp-0")
}

func assertNoTemps(t *testing.T, dir string) {
	t.Helper()
	assertNoTempsExcept(t, dir, "")
}

func assertNoTempsExcept(t *testing.T, dir, allowed string) {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(dir, "*.alder-tmp-*"))
	if err != nil {
		t.Fatal(err)
	}
	for _, match := range matches {
		if filepath.Base(match) != allowed {
			t.Fatalf("leaked temporary output %s", match)
		}
	}
}
