module std.process

import std.env { PlatformInfo }
import std.io
import std.path { OsString, Path }

// The Milestone 8 process surface, value layer first. The public snapshot
// (docs/api/std.process-v1.md) fixes the full surface; this module currently
// installs the pure value types and builder methods. Spawning, child
// handles, pipe ends, and output capture wait for the std.io slice 2
// capability and host handles.

/// The wiring selected for one standard stream. The default is `Inherit`.
pub enum PipeMode {
    /// The child shares the parent's descriptor (or is closed when the
    /// parent has none for that stream).
    Inherit
    /// A new pipe connects parent and child.
    Piped
}

impl PipeMode {
    /// The inherited mode; the same value as the default stream wiring.
    fn inherit() -> PipeMode {
        return Inherit
    }

    /// The piped mode.
    fn piped() -> PipeMode {
        return Piped
    }
}

/// Value-semantic child-process description. Copying a `Command` copies the
/// whole configuration; builder methods return an updated value and change
/// nothing else. Validation happens at spawn time, so builders never fail.
pub type Command {
    program: OsString
    arguments: Vec(OsString)
    working_directory: Option(Path)
    environment_keys: Vec(OsString)
    environment_values: Vec(Option(OsString))
    environment_cleared: Bool
    stdin_mode: PipeMode
    stdout_mode: PipeMode
    stderr_mode: PipeMode
}

impl Command {
    /// A command running `program` with no arguments, inherited
    /// environment, inherited working directory, and all three standard
    /// streams inherited.
    fn new(program: OsString) -> Command {
        return Command(
            program: program,
            arguments: Vec.new(OsString),
            working_directory: None,
            environment_keys: Vec.new(OsString),
            environment_values: Vec.new(Option(OsString)),
            environment_cleared: false,
            stdin_mode: Inherit,
            stdout_mode: Inherit,
            stderr_mode: Inherit,
        )
    }

    /// Appends one argument, passed through verbatim. Functional update:
    /// the result is a new value, matching the storage-backed builder
    /// convention used by `std.text.StringBuilder`.
    fn argument(self, value: OsString) -> Command {
        var arguments = self.arguments
        arguments.push(value)
        return rebuild(self, arguments, self.working_directory, self.environment_keys, self.environment_values, self.environment_cleared, self.stdin_mode, self.stdout_mode, self.stderr_mode)
    }

    /// Replaces the argument list.
    fn set_arguments(self, values: Vec(OsString)) -> Command {
        return rebuild(self, values, self.working_directory, self.environment_keys, self.environment_values, self.environment_cleared, self.stdin_mode, self.stdout_mode, self.stderr_mode)
    }

    /// Runs the child with `path` as its working directory.
    fn working_directory(self, path: Path) -> Command {
        return rebuild(self, self.arguments, Some(path), self.environment_keys, self.environment_values, self.environment_cleared, self.stdin_mode, self.stdout_mode, self.stderr_mode)
    }

    /// Adds one override applied over the inherited environment.
    fn env(self, key: OsString, value: OsString) -> Command {
        var keys = self.environment_keys
        var values = self.environment_values
        keys.push(key)
        values.push(Some(value))
        return rebuild(self, self.arguments, self.working_directory, keys, values, self.environment_cleared, self.stdin_mode, self.stdout_mode, self.stderr_mode)
    }

    /// Removes one key from the child's environment.
    fn env_remove(self, key: OsString) -> Command {
        var keys = self.environment_keys
        var values = self.environment_values
        keys.push(key)
        values.push(None)
        return rebuild(self, self.arguments, self.working_directory, keys, values, self.environment_cleared, self.stdin_mode, self.stdout_mode, self.stderr_mode)
    }

    /// Starts the child from an empty environment; later `env` overrides
    /// apply on top of the empty set.
    fn clear_environment(self) -> Command {
        return rebuild(self, self.arguments, self.working_directory, self.environment_keys, self.environment_values, true, self.stdin_mode, self.stdout_mode, self.stderr_mode)
    }

    /// Selects the wiring of standard input. Default is `Inherit`.
    fn stdin(self, mode: PipeMode) -> Command {
        return rebuild(self, self.arguments, self.working_directory, self.environment_keys, self.environment_values, self.environment_cleared, mode, self.stdout_mode, self.stderr_mode)
    }

    /// Selects the wiring of standard output. Default is `Inherit`.
    fn stdout(self, mode: PipeMode) -> Command {
        return rebuild(self, self.arguments, self.working_directory, self.environment_keys, self.environment_values, self.environment_cleared, self.stdin_mode, mode, self.stderr_mode)
    }

    /// Selects the wiring of standard error. Default is `Inherit`.
    fn stderr(self, mode: PipeMode) -> Command {
        return rebuild(self, self.arguments, self.working_directory, self.environment_keys, self.environment_values, self.environment_cleared, self.stdin_mode, self.stdout_mode, mode)
    }
}

fn rebuild(command: Command, arguments: Vec(OsString), working_directory: Option(Path), environment_keys: Vec(OsString), environment_values: Vec(Option(OsString)), environment_cleared: Bool, stdin_mode: PipeMode, stdout_mode: PipeMode, stderr_mode: PipeMode) -> Command {
    return Command(program: command.program, arguments: arguments, working_directory: working_directory, environment_keys: environment_keys, environment_values: environment_values, environment_cleared: environment_cleared, stdin_mode: stdin_mode, stdout_mode: stdout_mode, stderr_mode: stderr_mode)
}

/// How a child exited.
pub type ExitStatus {
    kind: U8
    value: I32
}

impl ExitStatus {
    /// Builds a normal-exit status. The host layer uses this constructor
    /// when it maps a waited child.
    fn from_exit(code: I32) -> ExitStatus {
        return ExitStatus(kind: 0, value: code)
    }

    /// Builds a signal-terminated status. The signal number is the host
    /// value surfaced verbatim.
    fn from_signal(signal: I32) -> ExitStatus {
        return ExitStatus(kind: 1, value: signal)
    }

    /// True when the child exited normally with code zero.
    fn success(self) -> Bool {
        return self.kind == 0 && self.value == 0
    }

    /// The exit code for a normal exit, `None` when a signal ended it.
    fn code(self) -> Option(I32) {
        var out: Option(I32) = None
        if self.kind == 0 { out = Some(self.value) }
        return out
    }

    /// The signal number when a signal ended the child, `None` otherwise.
    fn signal(self) -> Option(I32) {
        var out: Option(I32) = None
        if self.kind == 1 { out = Some(self.value) }
        return out
    }
}

/// The result of `Command.output`.
pub type Output {
    status: ExitStatus
    stdout: Bytes
    stderr: Bytes
}

/// Process-layer failures. The value layer installs the categories now;
/// spawn and wait map host errors into them with slice 2.
pub enum ProcessError {
    /// The program does not exist.
    NotFound
    /// The program exists but cannot be executed.
    PermissionDenied
    /// The `Command` configuration cannot run.
    InvalidConfiguration
    /// The operation has no implementation on this target.
    Unsupported
    /// A host call failed with no portable category.
    Platform(info: PlatformInfo)
}

impl ProcessError {
    /// The program-does-not-exist category.
    fn not_found() -> ProcessError {
        return NotFound
    }

    /// The permission-denied category.
    fn permission_denied() -> ProcessError {
        return PermissionDenied
    }

    /// The invalid-command-configuration category.
    fn invalid_configuration() -> ProcessError {
        return InvalidConfiguration
    }

    /// The target-unsupported category.
    fn unsupported() -> ProcessError {
        return Unsupported
    }

    /// A platform-detail category.
    fn platform(info: PlatformInfo) -> ProcessError {
        return Platform(info)
    }
}

impl Display for ProcessError {
    /// The portable text for a process failure.
    fn display(self) -> String {
        return match self {
            NotFound => "not found"
            PermissionDenied => "permission denied"
            InvalidConfiguration => "invalid configuration"
            Unsupported => "unsupported"
            Platform(info) => info.message
        }
    }
}

impl Error for ProcessError {
}
