# `std.process` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; value layer implemented**

This is the versioned public snapshot for child processes. It is normative
together with the executable example
[`examples/std.process-v1.al`](examples/std.process-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/process.al`.

Snapshot v1 covers the value-semantic `Command`, the affine `Child`, pipes,
exit status, output capture, waiting, termination, and explicit environment
inheritance. The value layer is implemented now; spawning, child handles,
pipe ends, and output capture wait for the `std.io` slice 2 capability and
host handles. Spawning waits on the host, so it takes the capability, and the
surfaces are written once against `I: type(io.Io)`. No function in this
module invokes a shell; the argument vector is passed to the target program
exactly as built, with no quoting or expansion anywhere in the layer.

## Signatures

### Command

```alder
module std.process

import std.env { PlatformInfo }
import std.io
import std.path { OsString, Path }

/// Value-semantic child-process description. Copying a `Command` copies the
/// whole configuration; builder methods mutate a uniquely owned value in
/// place and change nothing else. Builders return the updated value; rebind
/// the result. Validation happens at spawn time, so builders never fail.
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
    pub fn argument(self, value: OsString) -> Command
    /// Replaces the argument list.
    pub fn set_arguments(self, values: Vec(OsString)) -> Command
    /// Runs the child with `path` as its working directory.
    pub fn working_directory(self, path: Path) -> Command
    /// Adds one override applied over the inherited environment.
    pub fn env(self, key: OsString, value: OsString) -> Command
    /// Removes one key from the child's environment.
    pub fn env_remove(self, key: OsString) -> Command
    /// Starts the child from an empty environment; later `env` overrides
    /// apply on top of the empty set.
    pub fn clear_environment(self) -> Command
    /// Selects the wiring of one standard stream. Default is `Inherit`.
    pub fn stdin(self, mode: PipeMode) -> Command
    pub fn stdout(self, mode: PipeMode) -> Command
    pub fn stderr(self, mode: PipeMode) -> Command
    /// Spawns the child. The `Command` stays owned and reusable.
    pub fn spawn(I: type(io.Io), io: I, self) -> Result(Child(I), ProcessError)
    /// Spawns with default wiring, waits, and returns the exit status.
    pub fn status(I: type(io.Io), io: I, self) -> Result(ExitStatus, ProcessError)
    /// Spawns with standard output and error piped, captures both to end
    /// of stream, waits, and returns status plus captured bytes.
    pub fn output(I: type(io.Io), io: I, self) -> Result(Output, ProcessError)
}

pub enum PipeMode {
    /// The child shares the parent's descriptor (or is closed when the
    /// parent has none for that stream).
    Inherit
    /// A new pipe connects parent and child.
    Piped
}

impl PipeMode {
    /// The inherited mode.
    pub fn inherit() -> PipeMode
    /// The piped mode.
    pub fn piped() -> PipeMode
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

impl ProcessError {
    /// The program-does-not-exist category.
    pub fn not_found() -> ProcessError
    /// The permission-denied category.
    pub fn permission_denied() -> ProcessError
    /// The invalid-command-configuration category.
    pub fn invalid_configuration() -> ProcessError
    /// The target-unsupported category.
    pub fn unsupported() -> ProcessError
    /// A platform-detail category.
    pub fn platform(info: PlatformInfo) -> ProcessError
}

impl Error for ProcessError {
    // Root error: the default `cause` is `None`.
}
```

Equality for `ExitStatus` is structural. `Display` for `ExitStatus`
(`exited with code N` / `killed by signal N`) lands with the sysroot
formatting snapshot and is additive.

## Value-layer amendment

The value layer uses functional builder updates (`self -> Command`) and
public constructor functions for payload-less enum variants. In-place
assignment of a `Vec` or `OsString` field from a `mut self` method is not
safely expressible with the current storage plan: the field would retain
storage owned by the builder call's temporary domain. Functional updates
keep the value semantics and ownership contract unchanged; callers rebind the
result (`command = command.argument(value)`). `PipeMode.inherit`/`piped`,
`ExitStatus.from_exit`/`from_signal`, and the `ProcessError` category
constructors make the same immutable values available without relying on
qualified enum-variant expressions. The host spawn layer will use these
constructors when it lands.

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
  children.
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

import std.env
import std.io
import std.path
import std.process

// The executable std.process v1 snapshot example. One fixed program with
// fixed arguments and piped capture; the checksum is deterministic.

// Byte equality between a byte vector and a literal.
fn bytes_are(left: Bytes, right: String) -> Bool {
    return left == right.to_bytes()
}

// The example inputs are fixed, so any early failure produces a
// distinctive negative checksum.
pub fn std_process_example(io: io.Blocking) -> I64 {
    var total: I64 = 0

    // Value-semantic builder, then capture through Command.output.
    let program = match path.OsString.parse("/bin/echo") {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    let message = match path.OsString.parse("alder") {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    var command = process.Command.new(program)
    command = command.argument(message)
    let result = match process.Command.output(io, command) {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    if result.status.success() { total = total + 1 }
    if bytes_are(result.stdout, "alder\n") { total = total + 10 }

    // Explicit environment override path, same fixed program.
    var scripted = process.Command.new(program)
    scripted = scripted.argument(message)
    let key = match path.OsString.parse("ALDER_STD_PROCESS_EXAMPLE") {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    let flag = match path.OsString.parse("1") {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    scripted = scripted.env(key, flag)
    let second = match process.Command.output(io, scripted) {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    if second.status.success() { total = total + 100 }
    if second.stderr.len() == 0 { total = total + 1 }

    // An unsatisfiable program reports NotFound instead of panicking.
    let missing = match path.OsString.parse("/alder/does/not/exist") {
        Ok(value) => { value }
        Err(_) => { return -1000000 }
    }
    var gone = process.Command.new(missing)
    match process.Command.status(io, gone) {
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
- Needs the generic implementation parameter list (D024 extension, decided)
  for the trait and `Cleanup` impls over `Child(I)` and the pipe ends; the
  syntax lands with the constraint-syntax thread before the `std.io` commit.
- Needs the C-binding thread's binding blocks and checked raw-integer
  conversions for the POSIX process calls (`posix_spawn` or `fork`/`exec`
  inside the runtime host layer, `waitpid`, `kill`, `pipe`) and their errno
  mapping; spawn plumbing may need small runtime additions, which this
  module owns.
- Cancellation-aware termination (a canceled parent task terminating its
  child) arrives with Milestone 9; v1 documents cleanup kill-and-reap so the
  M9 change is internal.
- The example depends on `/bin/echo` existing on the host, the documented
  POSIX assumption of this snapshot family; the behavior tests use the same
  fixed program.
- The `Bytes` equality, `is_empty`, and byte-level operations in the example
  stand in for the sysroot thread's byte-operation snapshot; final code uses
  that snapshot's exact spellings.
