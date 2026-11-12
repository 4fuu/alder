module std.process

import std.env { PlatformInfo }
import std.io { ChildStatus, HostChild, HostFile, Io, IoError, PollPair, Reader, Writer }
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

    /// Spawns the child. The `Command` stays owned and reusable.
    fn spawn(I: type(Io), io: I, command: Command) -> Result(Child(I), ProcessError) {
        return spawn_command(io, command)
    }

    /// Spawns with default wiring, waits, and returns the exit status.
    fn status(I: type(Io), io: I, command: Command) -> Result(ExitStatus, ProcessError) {
        if command.stdout_mode != Inherit || command.stderr_mode != Inherit {
            return Err(InvalidConfiguration)
        }
        let spawned = match spawn_command(io, command) {
            Ok(value) => value
            Err(error) => return Err(error)
        }
        using child = spawned
        match child.take_stdin() {
            Some(input) => { input.cleanup() }
            None => {}
        }
        return child.wait()
    }

    /// Spawns with standard output and error piped, captures both to end of
    /// stream, waits, and returns status plus captured bytes.
    fn output(I: type(Io), io: I, command: Command) -> Result(Output, ProcessError) {
        if command.stdout_mode != Piped || command.stderr_mode != Piped {
            return Err(InvalidConfiguration)
        }
        let spawned = match spawn_command(io, command) {
            Ok(value) => value
            Err(error) => return Err(error)
        }
        using child = spawned
        match child.take_stdin() {
            Some(input) => { input.cleanup() }
            None => {}
        }
        var captured: Result(Captured, ProcessError) = Err(InvalidConfiguration)
        match child.take_stdout() {
            Some(output_value) => {
                match child.take_stderr() {
                    Some(error_value) => {
                        captured = capture(io, output_value, error_value)
                    }
                    None => { output_value.cleanup() }
                }
            }
            None => {
                match child.take_stderr() {
                    Some(error_value) => { error_value.cleanup() }
                    None => {}
                }
            }
        }
        let bytes = match captured {
            Ok(value) => value
            Err(error) => return Err(error)
        }
        let status = try child.wait()
        return Ok(Output(status: status, stdout: bytes.stdout_bytes.slice(0, bytes.stdout_bytes.len()).to_bytes(), stderr: bytes.stderr_bytes.slice(0, bytes.stderr_bytes.len()).to_bytes()))
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

/// One running child process. Affine: exactly one owner reaps it, through
/// `wait` or cleanup.
pub type Child(IoType: type(Io)) {
    io: IoType
    handle: HostChild
}

impl(IoType: type(Io)) Child(IoType) {
    /// The host process id, valid until the child is reaped.
    fn id(self) -> U32 {
        return self.handle.pid.to_u32_wrapping()
    }

    /// Moves the write end of the child's standard input out, `None` when it
    /// was not piped. Each end moves at most once.
    fn take_stdin(mut self) -> Option(ChildStdin(IoType)) {
        match self.handle.stdin.take() {
            Some(handle) => { return Some(ChildStdin(io: self.io, handle: handle)) }
            None => { return None }
        }
        return None
    }

    /// Moves the read end of the child's standard output out, `None` when it
    /// was not piped.
    fn take_stdout(mut self) -> Option(ChildStdout(IoType)) {
        match self.handle.stdout.take() {
            Some(handle) => { return Some(ChildStdout(io: self.io, handle: handle)) }
            None => { return None }
        }
        return None
    }

    /// Moves the read end of the child's standard error out, `None` when it
    /// was not piped.
    fn take_stderr(mut self) -> Option(ChildStderr(IoType)) {
        match self.handle.stderr.take() {
            Some(handle) => { return Some(ChildStderr(io: self.io, handle: handle)) }
            None => { return None }
        }
        return None
    }

    /// Terminates the child with an immediate unconditional kill. Returns
    /// without waiting; `wait` or cleanup reaps.
    fn kill(mut self) -> Result(Unit, ProcessError) {
        match self.io.kill(self.handle.pid) {
            Ok(_) => { return Ok(()) }
            Err(error) => { return Err(process_error(error)) }
        }
        return Err(Unsupported)
    }

    /// Closes any pipe ends still held here, waits for exit, reaps, and
    /// reports the status. Releases the owner on both arms: after `Err` the
    /// child is reaped or kill-and-reaped.
    fn wait(take self) -> Result(ExitStatus, ProcessError) {
        let io = self.io
        let pid = self.handle.pid
        self.handle.cleanup()
        match io.wait(pid) {
            Ok(status) => { return Ok(exit_status(status)) }
            Err(error) => {
                let killed = io.kill(pid)
                let reaped = io.wait(pid)
                return Err(process_error(error))
            }
        }
        return Err(Unsupported)
    }
}

impl(IoType: type(Io)) Cleanup for Child(IoType) {
    fn cleanup(take self) -> Unit {
        let io = self.io
        let pid = self.handle.pid
        let killed = io.kill(pid)
        self.handle.cleanup()
        let waited = io.wait(pid)
        return
    }
}

/// The write end of the child's standard input. Affine; cleanup closes it,
/// which is how a reading child sees end of input.
pub type ChildStdin(IoType: type(Io)) {
    io: IoType
    handle: HostFile
}

impl(IoType: type(Io)) Writer for ChildStdin(IoType) {
    fn write(mut self, data: [U8]) -> Result(U64, IoError) {
        return self.io.write(self.handle, data)
    }

    fn flush(mut self) -> Result(Unit, IoError) {
        return Ok(())
    }
}

impl(IoType: type(Io)) Cleanup for ChildStdin(IoType) {
    fn cleanup(take self) -> Unit {
        let closed = self.io.close(self.handle)
        return
    }
}

/// The read end of the child's standard output. Affine; cleanup closes it.
pub type ChildStdout(IoType: type(Io)) {
    io: IoType
    handle: HostFile
}

impl(IoType: type(Io)) Reader for ChildStdout(IoType) {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.io.read(self.handle, buffer)
    }
}

impl(IoType: type(Io)) Cleanup for ChildStdout(IoType) {
    fn cleanup(take self) -> Unit {
        let closed = self.io.close(self.handle)
        return
    }
}

/// The read end of the child's standard error. Affine; cleanup closes it.
pub type ChildStderr(IoType: type(Io)) {
    io: IoType
    handle: HostFile
}

impl(IoType: type(Io)) Reader for ChildStderr(IoType) {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.io.read(self.handle, buffer)
    }
}

impl(IoType: type(Io)) Cleanup for ChildStderr(IoType) {
    fn cleanup(take self) -> Unit {
        let closed = self.io.close(self.handle)
        return
    }
}

/// The bytes captured by `Command.output`.
type Captured {
    stdout_bytes: Vec(U8)
    stderr_bytes: Vec(U8)
}

fn pipe_mode(mode: PipeMode) -> U8 {
    match mode {
        Inherit => { return 0 }
        Piped => { return 1 }
    }
    return 0
}

fn environment_entry(key: OsString, value: OsString) -> Option(OsString) {
    let data = key.to_bytes().concat("=".to_bytes()).concat(value.to_bytes())
    match OsString.from_bytes(data) {
        Ok(entry) => { return Some(entry) }
        Err(_) => { return None }
    }
    return None
}

fn process_error(error: IoError) -> ProcessError {
    match error {
        NotFound => { return NotFound }
        PermissionDenied => { return PermissionDenied }
        InvalidInput => { return InvalidConfiguration }
        Unsupported => { return Unsupported }
        Other(info) => { return Platform(info) }
        AlreadyExists => { return Platform(PlatformInfo(code: 17, message: "already exists")) }
        DirectoryNotEmpty => { return Platform(PlatformInfo(code: 39, message: "directory not empty")) }
    }
    return Unsupported
}

fn exit_status(status: ChildStatus) -> ExitStatus {
    if status.kind == 1 { return ExitStatus.from_signal(status.value) }
    return ExitStatus.from_exit(status.value)
}

fn spawn_command(I: type(Io), io: I, command: Command) -> Result(Child(I), ProcessError) {
    var set_environment: Vec(OsString) = Vec.new(OsString)
    var remove_environment: Vec(OsString) = Vec.new(OsString)
    var at: U64 = 0
    while at < command.environment_keys.len() {
        let key = command.environment_keys[at]
        match command.environment_values[at] {
            Some(value) => {
                match environment_entry(key, value) {
                    Some(entry) => { set_environment.push(entry) }
                    None => { return Err(InvalidConfiguration) }
                }
            }
            None => { remove_environment.push(key) }
        }
        at = at + 1
    }
    match io.spawn(command.program, command.arguments, set_environment, remove_environment, command.environment_cleared, command.working_directory, pipe_mode(command.stdin_mode), pipe_mode(command.stdout_mode), pipe_mode(command.stderr_mode)) {
        Ok(handle) => { return Ok(Child(io: io, handle: handle)) }
        Err(error) => { return Err(process_error(error)) }
    }
    return Err(Unsupported)
}

fn append_bytes(target: Vec(U8), chunk: Vec(U8), count: U64) -> Vec(U8) {
    var out = target
    var at: U64 = 0
    while at < count {
        out.push(chunk[at])
        at = at + 1
    }
    return out
}

fn capture(I: type(Io), io: I, take output: ChildStdout(I), take error: ChildStderr(I)) -> Result(Captured, ProcessError) {
    var output_bytes: Vec(U8) = Vec.new(U8)
    var error_bytes: Vec(U8) = Vec.new(U8)
    var chunk: Vec(U8) = Vec.new(U8)
    var filled: U64 = 0
    while filled < 4096 {
        chunk.push(0)
        filled = filled + 1
    }
    var output_open = true
    var error_open = true
    while output_open || error_open {
        // With one stream at end of file, read the other directly: polling a
        // descriptor that stays at hangup would spin.
        if !output_open {
            match io.read(error.handle, chunk.slice_mut(0, 4096)) {
                Ok(count) => {
                    if count == 0 {
                        error_open = false
                    } else {
                        error_bytes = append_bytes(error_bytes, chunk, count)
                    }
                }
                Err(problem) => {
                    output.cleanup()
                    error.cleanup()
                    return Err(process_error(problem))
                }
            }
        } else if !error_open {
            match io.read(output.handle, chunk.slice_mut(0, 4096)) {
                Ok(count) => {
                    if count == 0 {
                        output_open = false
                    } else {
                        output_bytes = append_bytes(output_bytes, chunk, count)
                    }
                }
                Err(problem) => {
                    output.cleanup()
                    error.cleanup()
                    return Err(process_error(problem))
                }
            }
        } else {
            var ready = PollPair(first_ready: false, second_ready: false)
            match io.poll(output.handle, error.handle, -1) {
                Ok(value) => { ready = value }
                Err(problem) => {
                    output.cleanup()
                    error.cleanup()
                    return Err(process_error(problem))
                }
            }
            if ready.first_ready {
                match io.read(output.handle, chunk.slice_mut(0, 4096)) {
                    Ok(count) => {
                        if count == 0 {
                            output_open = false
                        } else {
                            output_bytes = append_bytes(output_bytes, chunk, count)
                        }
                    }
                    Err(problem) => {
                        output.cleanup()
                        error.cleanup()
                        return Err(process_error(problem))
                    }
                }
            }
            if ready.second_ready {
                match io.read(error.handle, chunk.slice_mut(0, 4096)) {
                    Ok(count) => {
                        if count == 0 {
                            error_open = false
                        } else {
                            error_bytes = append_bytes(error_bytes, chunk, count)
                        }
                    }
                    Err(problem) => {
                        output.cleanup()
                        error.cleanup()
                        return Err(process_error(problem))
                    }
                }
            }
        }
    }
    output.cleanup()
    error.cleanup()
    return Ok(Captured(stdout_bytes: output_bytes, stderr_bytes: error_bytes))
}
