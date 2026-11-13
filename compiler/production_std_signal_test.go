//go:build !windows

package compiler

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"
)

const stdSignalWaitProgram = `module hello.main

import std.io { Blocking, print }
import std.signal

pub fn main() -> I32 {
    let io = Blocking()
    let first = match signal.wait(io, signal.Signal.Terminate, 0) {
        Ok(value) => value
        Err(_) => return 2
    }
    match first {
        None => {}
        _ => { return 3 }
    }
    print(io, "ready\n")
    let second = match signal.wait(io, signal.Signal.Terminate, 5000) {
        Ok(value) => value
        Err(_) => return 4
    }
    match second {
        Some(Terminate) => { return 0 }
        _ => { return 1 }
    }
    return 5
}
`

const stdSignalRestoreProgram = `module hello.main

import std.io { Blocking, print }
import std.signal

pub fn main() -> I32 {
    let io = Blocking()
    let first = match signal.wait(io, signal.Signal.Terminate, 0) {
        Ok(value) => value
        Err(_) => return 2
    }
    match first {
        None => {}
        _ => { return 3 }
    }
    print(io, "restored\n")
    io.sleep(10, 0)
    return 4
}
`

func buildSignalProgram(t *testing.T, root, exe, source string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(root, "sysroot")), map[string]string{
		"alder.toml":  snapshotProjectManifest,
		"src/main.al": source,
	}, "build")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("std.signal build: %+v", result)
	}
	output := filepath.Join(dir, "build", productionHostTriple(), "debug", "hello")
	binary := filepath.Join(output, "hello")
	if _, err := os.Stat(binary); err != nil {
		t.Fatalf("std.signal executable: %v", err)
	}
	generated := filepath.Join(output, "hello.c")
	if _, err := os.Stat(generated); err != nil {
		t.Fatalf("std.signal generated C: %v", err)
	}
	return binary, generated
}

// signalReadyEnv names the inherited descriptor that the test-only signal shim
// copy writes to once a blocking wait has installed its handler.
const signalReadyEnv = "ALDER_TEST_SIGNAL_READY_FD"

// signalShimWithReadyHook returns the production std.signal C shim with one
// test-only observation inserted after a blocking wait installs its handler.
// The production shim, public one-shot semantics, and the generated program's
// Alder source are unchanged: only this test's C build uses the copy.
func signalShimWithReadyHook(t *testing.T, source []byte) []byte {
	t.Helper()
	const includeAnchor = "#include <unistd.h>\n"
	const installAnchor = "installed = 1;"
	const readyHook = `#include <stdlib.h>

// Test-only observation: report that a blocking wait has installed its
// handler. An inherited pipe carries the byte to the test process.
static inline void io_signal_test_ready(void) {
    const char *value = getenv("ALDER_TEST_SIGNAL_READY_FD");
    unsigned char byte = 1;
    ssize_t ignored;
    int fd;
    if (value == NULL) { return; }
    fd = atoi(value);
    if (fd <= 0) { return; }
    ignored = write(fd, &byte, (size_t)1);
    (void)ignored;
}

`
	text := string(source)
	if strings.Count(text, includeAnchor) != 1 || strings.Count(text, installAnchor) != 1 {
		t.Fatal("std.signal test hook anchors changed")
	}
	text = strings.Replace(text, includeAnchor, includeAnchor+readyHook, 1)
	text = strings.Replace(text, installAnchor, installAnchor+" if (timeout_ms > 0) { io_signal_test_ready(); }", 1)
	return []byte(text)
}

// buildSignalProgramAtHandlerInstalled rebuilds the generated C with the
// test-only shim copy. Readiness is then an observation of the second wait's
// handler installation, not a guess based on buffered stdout.
func buildSignalProgramAtHandlerInstalled(t *testing.T, root, runtimeObject, generated string) string {
	t.Helper()
	dir := t.TempDir()
	cSource, err := os.ReadFile(generated)
	if err != nil {
		t.Fatal(err)
	}
	shimSource, err := os.ReadFile(filepath.Join(root, "sysroot", "std", "c", "signal_shim.h"))
	if err != nil {
		t.Fatal(err)
	}
	include := filepath.Join(dir, "include", "std", "c")
	if err := os.MkdirAll(include, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(include, "signal_shim.h"), signalShimWithReadyHook(t, shimSource), 0o644); err != nil {
		t.Fatal(err)
	}
	cfile := filepath.Join(dir, "hello.c")
	if err := os.WriteFile(cfile, cSource, 0o644); err != nil {
		t.Fatal(err)
	}
	driver := filepath.Join(dir, "driver.c")
	const driverText = `#include "alder_host.h"
#include <stdint.h>
int main(void) { int context = 0; return (int)alder_program_entry(&context); }
`
	if err := os.WriteFile(driver, []byte(driverText), 0o644); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(dir, "hello")
	args := strictC11Flags()
	args = append(args, "-I", filepath.Join(dir, "include"), "-I", filepath.Join(root, "sysroot"),
		"-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"),
		cfile, driver, runtimeObject, "-o", binary)
	if output, err := exec.Command("cc", args...).CombinedOutput(); err != nil {
		t.Fatalf("std.signal observed C compile: %v\n%s", err, output)
	}
	return binary
}

// startSignalChildAtHandler starts the observed program and waits for the
// shim's byte, which is written only after the blocking wait installs the
// signal handler. The stdout readiness line is still checked by the caller.
func startSignalChildAtHandler(t *testing.T, binary string) (*exec.Cmd, *bufio.Reader) {
	t.Helper()
	readyRead, readyWrite, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(binary)
	cmd.ExtraFiles = []*os.File{readyWrite}
	cmd.Env = append(os.Environ(), signalReadyEnv+"=3")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		readyRead.Close()
		readyWrite.Close()
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		readyRead.Close()
		readyWrite.Close()
		t.Fatal(err)
	}
	readyWrite.Close()
	ready := make([]byte, 1)
	if _, err := io.ReadFull(readyRead, ready); err != nil {
		readyRead.Close()
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		t.Fatalf("std.signal handler readiness: %v", err)
	}
	readyRead.Close()
	return cmd, bufio.NewReader(stdout)
}

func startSignalChild(t *testing.T, binary string) (*exec.Cmd, *bufio.Reader) {
	t.Helper()
	cmd := exec.Command(binary)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	return cmd, bufio.NewReader(stdout)
}

func readSignalReady(t *testing.T, reader *bufio.Reader) {
	t.Helper()
	line, err := reader.ReadString('\n')
	if err != nil || line != "ready\n" {
		t.Fatalf("std.signal readiness: line=%q err=%v", line, err)
	}
}

func waitSignalChild(t *testing.T, cmd *exec.Cmd) error {
	t.Helper()
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return err
	case <-time.After(10 * time.Second):
		_ = cmd.Process.Kill()
		<-done
		t.Fatal("std.signal child did not exit")
		return nil
	}
}

func signalTargetProgram(number int) string {
	return fmt.Sprintf(`module hello.main

import std.io { Blocking, print }
import std.signal

pub fn main() -> I32 {
    let io = Blocking()
    let first = match signal.wait(io, signal.Signal.Target(%d), 0) {
        Ok(value) => value
        Err(_) => return 2
    }
    match first {
        None => {}
        _ => { return 3 }
    }
    print(io, "ready\n")
    let second = match signal.wait(io, signal.Signal.Target(%d), 5000) {
        Ok(value) => value
        Err(_) => return 4
    }
    match second {
        Some(value) => {
            match value {
                Target(number) => { if number == %d { return 0 } }
                _ => {}
            }
            return 5
        }
        None => { return 1 }
    }
    return 6
}
`, number, number, number)
}

func TestStdSignalProductionQualification(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, "cc", root)
	runtimeObject := buildRuntimeObject(t, "cc", root)

	t.Run("real-term", func(t *testing.T) {
		_, generated := buildSignalProgram(t, root, exe, stdSignalWaitProgram)
		binary := buildSignalProgramAtHandlerInstalled(t, root, runtimeObject, generated)
		cmd, reader := startSignalChildAtHandler(t, binary)
		readSignalReady(t, reader)
		if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatal(err)
		}
		if err := waitSignalChild(t, cmd); err != nil {
			t.Fatalf("std.signal child failed: %v", err)
		}
	})

	t.Run("raw-target", func(t *testing.T) {
		if runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
			t.Skip("raw target signal test needs a POSIX host")
		}
		_, generated := buildSignalProgram(t, root, exe, signalTargetProgram(int(syscall.SIGUSR1)))
		binary := buildSignalProgramAtHandlerInstalled(t, root, runtimeObject, generated)
		cmd, reader := startSignalChildAtHandler(t, binary)
		readSignalReady(t, reader)
		if err := cmd.Process.Signal(syscall.SIGUSR1); err != nil {
			t.Fatal(err)
		}
		if err := waitSignalChild(t, cmd); err != nil {
			t.Fatalf("std.signal target child failed: %v", err)
		}
	})

	t.Run("disposition-restored", func(t *testing.T) {
		binary, _ := buildSignalProgram(t, root, exe, stdSignalRestoreProgram)
		cmd, reader := startSignalChild(t, binary)
		line, err := reader.ReadString('\n')
		if err != nil || line != "restored\n" {
			t.Fatalf("std.signal restore readiness: line=%q err=%v", line, err)
		}
		if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
			t.Fatal(err)
		}
		err = waitSignalChild(t, cmd)
		exit, ok := err.(*exec.ExitError)
		if err == nil || !ok {
			t.Fatalf("std.signal restore: expected signal termination, got %v", err)
		}
		status, ok := exit.Sys().(syscall.WaitStatus)
		if !ok || !status.Signaled() || status.Signal() != syscall.SIGTERM {
			t.Fatalf("std.signal restore: status=%v", exit)
		}
	})
}
