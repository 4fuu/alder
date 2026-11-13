//go:build !windows

package compiler

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
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

func buildSignalProgram(t *testing.T, root, exe, source string) string {
	t.Helper()
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(root, "sysroot")), map[string]string{
		"alder.toml":  snapshotProjectManifest,
		"src/main.al": source,
	}, "build")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("std.signal build: %+v", result)
	}
	binary := filepath.Join(dir, "build", productionHostTriple(), "debug", "hello", "hello")
	if _, err := os.Stat(binary); err != nil {
		t.Fatalf("std.signal executable: %v", err)
	}
	return binary
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

	t.Run("real-term", func(t *testing.T) {
		binary := buildSignalProgram(t, root, exe, stdSignalWaitProgram)
		cmd, reader := startSignalChild(t, binary)
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
		binary := buildSignalProgram(t, root, exe, signalTargetProgram(int(syscall.SIGUSR1)))
		cmd, reader := startSignalChild(t, binary)
		readSignalReady(t, reader)
		if err := cmd.Process.Signal(syscall.SIGUSR1); err != nil {
			t.Fatal(err)
		}
		if err := waitSignalChild(t, cmd); err != nil {
			t.Fatalf("std.signal target child failed: %v", err)
		}
	})

	t.Run("disposition-restored", func(t *testing.T) {
		binary := buildSignalProgram(t, root, exe, stdSignalRestoreProgram)
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
