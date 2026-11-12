# `std.process` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; implemented**

This is the versioned public snapshot for child processes. It is normative
together with the executable example
[`examples/std.process-v1.al`](examples/std.process-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/process.al`.

Snapshot v1 covers the value-semantic `Command`, the affine `Child`, pipes,
exit status, output capture, waiting, termination, and explicit environment
inheritance. Spawning waits on the host, so it takes the capability, and the
surfaces are written once against `I: type(io.Io)`. No function in this
module invokes a shell; the argument vector is passed to the target program
exactly as built, with no quoting or expansion anywhere in the layer.

`spawn`, `status`, and `output` are static associated functions today: the
command value is the last argument (`Command.output(io, command)`), so the
call form is exactly the one shown below. The receiver spelling
(`command.output(io)`) waits on generic associated receiver-call inference;
when that lands the parameter becomes `self` without changing the documented
call expressions.

## Signatures

### Command

```alder
module std.process

import std.env { PlatformInfo }
import std.io
import std.path { OsString, Path }

/// Value-semantic child-process description. Copying a `Command` copies the
/// whole configuration; builder methods mutate a uniquely owned value in
/// place and change nothing else. Validation happens at spawn time, so
/// builders never fail.
pub type Command {
    // private: program, arguments, working_directory,
    //          environment_overrides, environment_cleared, pipes
}

impl Command {
    /// A command running `program` with no arguments, inherited
    /// environment, inherited working directory, and all three standard
    /// streams inherited.
    pub fn new(program: OsString) -> Command
    /// Appends one argument, passed through verbatim.
    pub fn argument(mut self, value: OsString) -> Unit
    /// Replaces the argument list.
    pub fn set_arguments(mut self, values: Vec(OsString)) -> Unit
    /// Runs the child with `path` as its working directory.
    pub fn working_directory(mut self, path: Path) -> Unit
    /// Adds one override applied over the inherited environment.
    pub fn env(mut self, key: OsString, value: OsString) -> Unit
    /// Removes one key from the child's environment.
    pub fn env_remove(mut self, key: OsString) -> Unit
    /// Starts the child from an empty environment; later `env` overrides
    /// apply on top of the empty set.
    pub fn clear_environment(mut self) -> Unit
    /// Selects the wiring of one standard stream. Default is `Inherit`.
    pub fn stdin(mut self, mode: PipeMode) -> Unit
    pub fn stdout(mut self, mode: PipeMode) -> Unit
    pub fn stderr(mut self, mode: PipeMode) -> Unit
    /// Spawns the child. The `Command` stays owned and reusable.
    pub fn spawn(I: type(io.Io), io: I, command: Command) -> Result(Child(I), ProcessError)
    /// Spawns with default wiring, waits, and returns the exit status.
    pub fn status(I: type(io.Io), io: I, command: Command) -> Result(ExitStatus, ProcessError)
    /// Spawns with standard output and error piped, captures both to end
    /// of stream, waits, and returns status plus captured bytes.
    pub fn output(I: type(io.Io), io: I, command: Command) -> Result(Output, ProcessError)
}

pub enum PipeMode {
    /// The child shares the parent's descriptor (or is closed when the
    /// parent has none for that stream).
    Inherit
    /// A new pipe connects parent and child.
    Piped
}

```

### Child and pipe ends

```alder
/// One running child process. Affine: exactly one owner reaps it, through
/// `wait` or cleanup.
pub type Child(IoType: type(io.Io)) {
    // private: io, handle
}

impl(IoType: type(io.Io)) Child(IoType) {
    /// The host process id, valid until the child is reaped.
    pub fn id(self) -> U32
    /// Moves the write end of the child's standard input out, `None` when
    /// it was not piped. Each end moves at most once.
    pub fn take_stdin(mut self) -> Option(ChildStdin(IoType))
    /// Moves the read end of the child's standard output out, `None` when
    /// it was not piped.
    pub fn take_stdout(mut self) -> Option(ChildStdout(IoType))
    /// Moves the read end of the child's standard error out, `None` when
    /// it was not piped.
    pub fn take_stderr(mut self) -> Option(ChildStderr(IoType))
    /// Terminates the child with an immediate unconditional kill. Returns
    /// without waiting; `wait` or cleanup reaps.
    pub fn kill(mut self) -> Result(Unit, ProcessError)
    /// Closes any pipe ends still held here, waits for exit, reaps, and
    /// reports the status. Releases the owner on both arms: after `Err`
    /// the child is reaped or kill-and-reaped.
    pub fn wait(take self) -> Result(ExitStatus, ProcessError)
}

impl(IoType: type(io.Io)) Cleanup for Child(IoType) {
    // Kills the child unconditionally, reaps it, and closes remaining
    // pipe ends. Errors in any step are swallowed: the observing release
    // is `wait` (and `kill` for its error report).
}

/// The write end of the child's standard input. Affine; cleanup closes it,
/// which is how a reading child sees end of input.
pub type ChildStdin(IoType: type(io.Io)) {
    // private: io, handle (one affine io.HostFile pipe end)
}

impl(IoType: type(io.Io)) io.Writer for ChildStdin(IoType) {
}

impl(IoType: type(io.Io)) Cleanup for ChildStdin(IoType) {
    // Closes the descriptor; close errors are swallowed. The observing
    // release is a close through the capability in caller code.
}

/// The read end of the child's standard output. Affine; cleanup closes it.
pub type ChildStdout(IoType: type(io.Io)) {
    // private: io, handle
}

impl(IoType: type(io.Io)) io.Reader for ChildStdout(IoType) {
}

impl(IoType: type(io.Io)) Cleanup for ChildStdout(IoType) {
}

/// The read end of the child's standard error. Affine; cleanup closes it.
pub type ChildStderr(IoType: type(io.Io)) {
    // private: io, handle
}

impl(IoType: type(io.Io)) io.Reader for ChildStderr(IoType) {
}

impl(IoType: type(io.Io)) Cleanup for ChildStderr(IoType) {
}
```

### Exit status, output, and errors

```alder
/// How a child exited.
pub type ExitStatus {
    // private: kind
}

impl ExitStatus {
    /// Builds a normal-exit status. The host layer uses this constructor
    /// when it maps a waited child.
    pub fn from_exit(code: I32) -> ExitStatus
    /// Builds a signal-terminated status. The signal number is the host
    /// value surfaced verbatim.
    pub fn from_signal(signal: I32) -> ExitStatus
    /// True when the child exited normally with code zero.
    pub fn success(self) -> Bool
    /// The exit code for a normal exit, `None` when a signal ended it.
    pub fn code(self) -> Option(I32)
    /// The signal number when a signal ended the child, `None` otherwise.
    pub fn signal(self) -> Option(I32)
}

/// The result of `Command.output`.
pub type Output {
    pub status: ExitStatus
    pub stdout: Bytes
    pub stderr: Bytes
}

pub enum ProcessError {
    /// The program does not exist.
    NotFound
    /// The program exists but cannot be executed.
    PermissionDenied
    /// The `Command` configuration cannot run: for example `output` on a
    /// command whose standard streams are not both piped.
    InvalidConfiguration
    /// The operation has no implementation on this target.
    Unsupported
    /// A host call failed with no portable category.
    Platform(info: PlatformInfo)
}

impl Error for ProcessError {
    // Root error: the default `cause` is `None`.
}
```

Equality for `ExitStatus` is structural. `Display` for `ExitStatus`
(`exited with code N` / `killed by signal N`) lands with the sysroot
formatting snapshot and is additive.

## Value-layer note

Builder methods mutate the uniquely owned `Command` in place and return
`Unit`; callers call them directly on a mutable binding
(`command.argument(value)`). This is the frozen snapshot shape. Borrowed-place
owner-domain provenance keeps `Vec` and `OsString` field growth in the
caller's domain, so the builders remain safe through delegation. Qualified
enum-variant expressions such as `PipeMode.Piped` and
`ProcessError.Platform(info)` are available directly. The host spawn layer
will use these forms when it lands.

## Contracts

- No function in this module invokes a shell, quotes, expands, or splits
  anything. `Command.argument` bytes reach the child's argument vector
  verbatim. A shell is a program like any other and may be spawned explicitly
  under its own name.
- By default the child inherits the parent's environment and all three
  standard streams are inherited, decided as D12. Deviations are always
  explicit: `clear_environment`, `env`, and `env_remove` for the
  environment, and `PipeMode.Piped` per stream. Overrides apply in
  insertion order with later keys replacing earlier ones.
- `spawn` never mutates the `Command`: one description can spawn many
  children. The command is passed by value, so the documented
  `Command.spawn(io, command)` call form works before generic associated
  receiver-call inference lands.
- Process creation is a host operation on `std.io.Io` (`spawn`, `wait`,
  `kill`, `poll`); `std.process` never forges a host handle. `std.io` builds
  the pipe-end `HostFile`s, and `Child.take_stdin`/`take_stdout`/`take_stderr`
  move them out with `Option.take`.
- `Child` is affine. Forgetting to wait cannot leak a zombie: cleanup kills
  and reaps, and documents that it swallows errors. `wait` is the observing
  release and releases on both arms.
- `wait` closes parent-held pipe ends before waiting, so piped children
  observe end of input and `output` cannot deadlock on full pipes: `output`
  drains both captures to end of stream before waiting.
- Standard streams default to `Inherit`; `Piped` is opt-in per stream. A
  piped end that is never taken stays owned by the `Child` and is closed by
  `wait` or cleanup.
- `output` requires standard output and error both piped and reports
  `InvalidConfiguration` otherwise; `status` requires them inherited and
  reports `InvalidConfiguration` otherwise.
- Captured bytes are exact host bytes; decoding is caller policy through the
  checked `OsString`/`String` conversions.
- Exit-status decomposition is portable across tier-1 targets; signal numbers
  are host values surfaced verbatim under `signal`.
- Tests spawn only fixed known programs with fixed arguments and never depend
  on ambient environment or host state beyond that program.

## Example

The example below is the complete content that lands as
`examples/std.process-v1.al` with the implementation commit. It captures the
output of one fixed program with fixed arguments and returns a deterministic
checksum.

```alder
module hello.std_process_example

import std.io { Blocking }
import std.path { OsString }
import std.process { Command, Output, ProcessError }

// The executable std.process v1 snapshot example. One fixed program with
// fixed arguments and piped capture; the checksum is deterministic.

fn os_value(value: String) -> Option(OsString) {
    match OsString.parse(value) {
        Ok(text) => { return Some(text) }
        Err(_) => { return None }
    }
    return None
}

fn bytes_are(left: Bytes, right: String) -> Bool {
    return left == right.to_bytes()
}

// The example inputs are fixed, so any early failure produces a
// distinctive negative checksum.
pub fn std_process_example(io: Blocking) -> I64 {
    var total: I64 = 0

    let program = match os_value("/bin/echo") {
        Some(value) => value
        None => return -1000000
    }
    let message = match os_value("alder") {
        Some(value) => value
        None => return -1000000
    }
    var command = Command.new(program)
    command.argument(message)
    command.stdout(Piped)
    command.stderr(Piped)
    let result = match Command.output(io, command) {
        Ok(value) => value
        Err(_) => return -1000000
    }
    if result.status.success() { total = total + 1 }
    if bytes_are(result.stdout, "alder\n") { total = total + 10 }

    let scripted = match os_value("/bin/echo") {
        Some(value) => value
        None => return -1000000
    }
    let key = match os_value("ALDER_STD_PROCESS_EXAMPLE") {
        Some(value) => value
        None => return -1000000
    }
    let flag = match os_value("1") {
        Some(value) => value
        None => return -1000000
    }
    var second_command = Command.new(scripted)
    second_command.argument(message)
    second_command.env(key, flag)
    second_command.stdout(Piped)
    second_command.stderr(Piped)
    let second = match Command.output(io, second_command) {
        Ok(value) => value
        Err(_) => return -1000000
    }
    if second.status.success() { total = total + 100 }
    if second.stderr.len() == 0 { total = total + 1 }

    let missing = match os_value("/alder/does/not/exist") {
        Some(value) => value
        None => return -1000000
    }
    let gone = Command.new(missing)
    match Command.status(io, gone) {
        Ok(_) => { total = total - 100000 }
        Err(_) => { total = total + 1000 }
    }

    return total
}

```

## Dependencies and sequencing

- Builds on `std.io` (`Reader`/`Writer` for the pipe ends, the capability for
  descriptor operations), `std.path` (`OsString`), and `std.env`
  (`PlatformInfo`).
- Depends on the generic `Cleanup` implementations over `Child(I)` and the
  pipe ends, and on `Option.take` for moving a pipe end out of a child.
- Process host calls live in the `std.io` capability (`spawn`, `wait`,
  `kill`, `poll` backed by `sysroot/std/c/process_shim.h`): fork/exec,
  descriptor arrays, pipes, waitpid status decoding, signalling, and the
  two-descriptor poll. No shell is involved.
- Cancellation-aware termination (a canceled parent task terminating its
  child) arrives with Milestone 9; v1 documents cleanup kill-and-reap so the
  M9 change is internal.
- The example depends on `/bin/echo` existing on the host, the documented
  POSIX assumption of this snapshot family; the behavior tests use the same
  fixed program.
- The `Bytes` equality, `is_empty`, and byte-level operations in the example
  stand in for the sysroot thread's byte-operation snapshot; final code uses
  that snapshot's exact spellings.
