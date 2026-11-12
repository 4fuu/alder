package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 std.process v1 through the production driver. The program captures stdout
// and stderr through the poll drain, uses a bidirectional stdin/stdout pipe,
// kills and reaps a child, maps a missing program to NotFound, and passes an
// environment override and working directory to fixed host programs.
const processV1Program = `module hello.main

import std.io { Blocking, IoError, Writer, Reader }
import std.path { OsString, Path }
import std.process { Command, Child, ChildStdin, ChildStdout, ExitStatus, Output, PipeMode, ProcessError }

fn os_value(value: String) -> Result(OsString, ProcessError) {
    match OsString.parse(value) {
        Ok(text) => { return Ok(text) }
        Err(_) => { return Err(InvalidConfiguration) }
    }
    return Err(InvalidConfiguration)
}

fn path_value(value: String) -> Result(Path, ProcessError) {
    match Path.parse(value) {
        Ok(text) => { return Ok(text) }
        Err(_) => { return Err(InvalidConfiguration) }
    }
    return Err(InvalidConfiguration)
}

fn is_text(value: Bytes, want: String) -> Bool {
    match value.to_string_checked() {
        Some(text) => { return text == want }
        None => { return false }
    }
    return false
}

fn probe_main(io: Blocking) -> Result(I32, ProcessError) {
    let echo = try os_value("/bin/echo")
    let message = try os_value("alder")
    var command = Command.new(echo)
    command.argument(message)
    command.stdout(Piped)
    command.stderr(Piped)
    let captured = try Command.output(io, command)
    if !captured.status.success() { return Ok(90) }
    if !is_text(captured.stdout, "alder\n") { return Ok(91) }
    if captured.stderr.len() != 0 { return Ok(92) }

    let shell = try os_value("/bin/sh")
    let flag = try os_value("-c")
    let script = try os_value("printf err >&2")
    var noisy = Command.new(shell)
    noisy.argument(flag)
    noisy.argument(script)
    noisy.stdout(Piped)
    noisy.stderr(Piped)
    let noise = try Command.output(io, noisy)
    if !noise.status.success() { return Ok(93) }
    if noise.stdout.len() != 0 { return Ok(94) }
    if !is_text(noise.stderr, "err") { return Ok(95) }

    let truth = try os_value("/bin/true")
    let true_command = Command.new(truth)
    let true_status = try Command.status(io, true_command)
    if !true_status.success() { return Ok(96) }

    let status_cat = try os_value("/bin/cat")
    var status_cat_command = Command.new(status_cat)
    status_cat_command.stdin(Piped)
    let status_cat_status = try Command.status(io, status_cat_command)
    if !status_cat_status.success() { return Ok(118) }

    var bad_status = Command.new(truth)
    bad_status.stdout(Piped)
    match Command.status(io, bad_status) {
        Ok(_) => { return Ok(97) }
        Err(error) => {
            match error {
                InvalidConfiguration => {}
                _ => { return Ok(98) }
            }
        }
    }
    var bad_output = Command.new(echo)
    bad_output.stderr(Piped)
    match Command.output(io, bad_output) {
        Ok(_) => { return Ok(99) }
        Err(error) => {
            match error {
                InvalidConfiguration => {}
                _ => { return Ok(100) }
            }
        }
    }

    let cat = try os_value("/bin/cat")
    var cat_command = Command.new(cat)
    cat_command.stdin(Piped)
    cat_command.stdout(Piped)
    let child = try Command.spawn(io, cat_command)
    using child_owner = child
    let input = match child_owner.take_stdin() {
        Some(value) => value
        None => return Ok(101)
    }
    using input_owner = input
    var payload: Array(U8, 4) = [112, 105, 112, 101]
    let written = match input_owner.write(payload.slice(0, 4)) {
        Ok(value) => value
        Err(_) => return Ok(102)
    }
    if written != 4 { return Ok(103) }
    input_owner.cleanup()
    let output = match child_owner.take_stdout() {
        Some(value) => value
        None => return Ok(104)
    }
    using output_owner = output
    var room: Vec(U8) = Vec.new(U8)
    room.push(0)
    room.push(0)
    room.push(0)
    room.push(0)
    let count = match output_owner.read(room.slice_mut(0, 4)) {
        Ok(value) => value
        Err(_) => return Ok(105)
    }
    if count != 4 { return Ok(106) }
    if room[0] != 112 || room[3] != 101 { return Ok(107) }
    let cat_status = try child_owner.wait()
    if !cat_status.success() { return Ok(108) }

    let sleep = try os_value("/bin/sleep")
    let delay = try os_value("5")
    var sleeping = Command.new(sleep)
    sleeping.argument(delay)
    let sleeper = try Command.spawn(io, sleeping)
    using sleeper_owner = sleeper
    try sleeper_owner.kill()
    let killed = try sleeper_owner.wait()
    if killed.kind != 1 || killed.value != 9 { return Ok(109) }

    let missing = try os_value("/alder/does/not/exist")
    let missing_command = Command.new(missing)
    match Command.spawn(io, missing_command) {
        Ok(unexpected_child) => {
            using unexpected_owner = unexpected_child
            return Ok(110)
        }
        Err(error) => {
            match error {
                NotFound => {}
                _ => { return Ok(111) }
            }
        }
    }

    let show = try os_value("printf %s \"$ALDER_TEST\"")
    let key = try os_value("ALDER_TEST")
    let flag_value = try os_value("ok")
    var env_command = Command.new(shell)
    env_command.argument(flag)
    env_command.argument(show)
    env_command.env(key, flag_value)
    env_command.stdout(Piped)
    env_command.stderr(Piped)
    let env_output = try Command.output(io, env_command)
    if !env_output.status.success() { return Ok(112) }
    if !is_text(env_output.stdout, "ok") { return Ok(113) }

    var duplicate = Command.new(shell)
    duplicate.argument(flag)
    duplicate.argument(show)
    duplicate.env(key, try os_value("first"))
    duplicate.env(key, flag_value)
    duplicate.stdout(Piped)
    duplicate.stderr(Piped)
    let duplicate_output = try Command.output(io, duplicate)
    if !duplicate_output.status.success() { return Ok(116) }
    if !is_text(duplicate_output.stdout, "ok") { return Ok(117) }

    let root = try path_value("/")
    var pwd_command = Command.new(try os_value("/bin/pwd"))
    pwd_command.working_directory(root)
    pwd_command.stdout(Piped)
    pwd_command.stderr(Piped)
    let pwd_output = try Command.output(io, pwd_command)
    if !pwd_output.status.success() { return Ok(114) }
    if !is_text(pwd_output.stdout, "/\n") { return Ok(115) }

    return Ok(0)
}

fn main() -> I32 {
    let io = Blocking()
    match probe_main(io) {
        Ok(code) => { return code }
        Err(_) => { return 89 }
    }
    return 88
}
`

func processV1Project() map[string]string {
	return map[string]string{
		"alder.toml":  "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": processV1Program,
	}
}

func TestProcessV1ProductionRuns(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, processV1Project(), "test-plan")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.process plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, " module std.process\n") || !strings.Contains(plan.stdout, "edge std.process -> std.io\n") {
		t.Fatalf("plan does not list std.process and its dependency: %q", plan.stdout)
	}

	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, processV1Project(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.process v1 behavior run failed: %+v", run)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
