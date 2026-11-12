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

/// Value-semantic child-process description. Copying a `Command` copies the
/// whole configuration; builder methods mutate a uniquely owned value in
/// place and change nothing else. Validation happens at spawn time, so
/// builders never fail.
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

    /// Appends one argument, passed through verbatim.
    fn argument(mut self, value: OsString) -> Unit {
        self.arguments.push(value)
        return
    }

    /// Replaces the argument list.
    fn set_arguments(mut self, values: Vec(OsString)) -> Unit {
        self.arguments = values
        return
    }

    /// Runs the child with `path` as its working directory.
    fn working_directory(mut self, path: Path) -> Unit {
        self.working_directory = Some(path)
        return
    }

    /// Adds one override applied over the inherited environment.
    fn env(mut self, key: OsString, value: OsString) -> Unit {
        self.environment_keys.push(key)
        self.environment_values.push(Some(value))
        return
    }

    /// Removes one key from the child's environment.
    fn env_remove(mut self, key: OsString) -> Unit {
        self.environment_keys.push(key)
        self.environment_values.push(None)
        return
    }

    /// Starts the child from an empty environment; later `env` overrides
    /// apply on top of the empty set.
    fn clear_environment(mut self) -> Unit {
        self.environment_cleared = true
        return
    }

    /// Selects the wiring of standard input. Default is `Inherit`.
    fn stdin(mut self, mode: PipeMode) -> Unit {
        self.stdin_mode = mode
        return
    }

    /// Selects the wiring of standard output. Default is `Inherit`.
    fn stdout(mut self, mode: PipeMode) -> Unit {
        self.stdout_mode = mode
        return
    }

    /// Selects the wiring of standard error. Default is `Inherit`.
    fn stderr(mut self, mode: PipeMode) -> Unit {
        self.stderr_mode = mode
        return
    }
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
    pub status: ExitStatus
    pub stdout: Bytes
    pub stderr: Bytes
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
