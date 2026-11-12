package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// std.process value layer: the command description, stream modes, exit status,
// output value, and process error category are pure values. Spawning and
// child handles stay out until the std.io slice 2 capability and host handles
// exist.
func sysrootProcessValueMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.env { PlatformInfo }
import std.path { OsString, Path }
import std.process { Command, ExitStatus, Output, PipeMode, ProcessError }

fn run_checks(program: OsString, work_dir: Path) -> I32 {
    var command = Command.new(program)
    command.argument(program)
    var args: Vec(OsString) = Vec.new(OsString)
    args.push(program)
    args.push(program)
    command.set_arguments(args)
    command.working_directory(work_dir)
    command.env(program, program)
    command.env_remove(program)
    command.clear_environment()
    command.stdin(PipeMode.Piped)
    command.stdout(PipeMode.Inherit)
    command.stderr(PipeMode.Piped)

    let exited = ExitStatus.from_exit(3)
    match exited.code() {
        Some(code) => {
            if code != 3 { return 7 }
        }
        None => { return 8 }
    }
    if exited.success() { return 9 }
    match exited.signal() {
        Some(_) => { return 10 }
        None => {}
    }
    let success = ExitStatus.from_exit(0)
    if !success.success() { return 11 }
    let killed = ExitStatus.from_signal(9)
    match killed.signal() {
        Some(signal) => {
            if signal != 9 { return 12 }
        }
        None => { return 13 }
    }
    match killed.code() {
        Some(_) => { return 14 }
        None => {}
    }
    if killed.success() { return 15 }

    let output = Output(status: exited, stdout: "out".to_bytes(), stderr: "err".to_bytes())
    if output.status.success() { return 16 }
    if output.stdout.len() != 3 { return 17 }
    if output.stderr.len() != 3 { return 18 }

    let not_found = ProcessError.NotFound
    if not_found.display() != "not found" { return 20 }
    let denied = ProcessError.PermissionDenied
    if denied.display() != "permission denied" { return 21 }
    let invalid = ProcessError.InvalidConfiguration
    if invalid.display() != "invalid configuration" { return 22 }
    let unsupported = ProcessError.Unsupported
    if unsupported.display() != "unsupported" { return 23 }
    let platform = ProcessError.Platform(PlatformInfo(code: 7, message: "host detail"))
    if platform.display() != "host detail" { return 24 }
    match platform.cause() {
        Some(_) => { return 25 }
        None => {}
    }
    return 0
}

pub fn main() -> I32 {
    match OsString.parse("program") {
        Ok(program) => {
            match Path.parse("work") {
                Ok(work_dir) => { return run_checks(program, work_dir) }
                Err(_) => { return 2 }
            }
        }
        Err(_) => { return 1 }
    }
    return 3
}
`,
	}
}

func TestSysrootProcessValueLayer(t *testing.T) {
	testSysrootValueModule(t, sysrootProcessValueMain())
}

func testSysrootValueModule(t *testing.T, files map[string]string) {
	t.Helper()
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
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	run := runProductionCompilerEnv(t, exe, dir, env, files, "run")
	if run.status != 0 || run.stderr != "" || run.stdout != "" {
		t.Fatalf("sysroot value-layer run: status=%d stdout=%q stderr=%q", run.status, run.stdout, run.stderr)
	}
	runSanitizedProject(t, cc, root, dir, "hello")
}
