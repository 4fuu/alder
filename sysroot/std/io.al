module std.io

import std.env
import std.path { OsString, Path }
import core.panic { panic }

import c "std/c/io_shim.h" as posix {
    record type FileStatRaw = "io_file_stat" {
        kind: c.Int
        size: c.ULongLong
        mode: c.UInt
        seconds: c.LongLong
        nanos: c.Int
    }

    raw fn open = "io_open"(path: c.ConstPtr(c.Char), read: c.Int, write: c.Int, append: c.Int, truncate: c.Int, create: c.Int, create_new: c.Int) -> c.Int
    raw fn read = "io_read"(fd: c.Int, buffer: c.Ptr(c.UChar), length: c.Size) -> c.LongLong
    raw fn write = "io_write"(fd: c.Int, buffer: c.ConstPtr(c.UChar), length: c.Size) -> c.LongLong
    raw fn seek = "io_seek"(fd: c.Int, offset: c.LongLong, whence: c.Int, result: c.Ptr(c.LongLong)) -> c.Int
    raw fn fstat = "io_fstat"(fd: c.Int, out: c.Ptr(FileStatRaw)) -> c.Int
    raw fn stat_path = "io_stat_path"(path: c.ConstPtr(c.Char), out: c.Ptr(FileStatRaw)) -> c.Int
    raw fn lstat = "io_lstat"(path: c.ConstPtr(c.Char), out: c.Ptr(FileStatRaw)) -> c.Int
    raw fn close = "io_close"(fd: c.Int) -> c.Int
    raw fn sync = "io_fsync"(fd: c.Int) -> c.Int
    raw fn fchmod = "io_fchmod"(fd: c.Int, mode: c.UInt) -> c.Int
    raw fn chmod = "io_chmod"(path: c.ConstPtr(c.Char), mode: c.UInt) -> c.Int
    raw fn rename = "io_rename"(from: c.ConstPtr(c.Char), to: c.ConstPtr(c.Char)) -> c.Int
    raw fn remove = "io_remove"(path: c.ConstPtr(c.Char)) -> c.Int
    raw fn remove_directory = "io_rmdir"(path: c.ConstPtr(c.Char)) -> c.Int
    raw fn make_directory = "io_mkdir"(path: c.ConstPtr(c.Char), mode: c.UInt) -> c.Int
    raw fn canonicalize = "io_realpath"(path: c.ConstPtr(c.Char), out: c.Ptr(c.UChar), capacity: c.Size) -> c.LongLong
    raw fn open_directory = "io_open_dir"(path: c.ConstPtr(c.Char)) -> c.ULongLong
    raw fn read_directory = "io_read_dir"(directory: c.ULongLong, name: c.Ptr(c.UChar), capacity: c.Size, length: c.Ptr(c.Size), kind: c.Ptr(c.Int)) -> c.Int
    raw fn close_dir = "io_close_dir"(directory: c.ULongLong) -> c.Int
    raw fn clock_gettime = "io_clock_gettime"(which: c.Int, seconds: c.Ptr(c.LongLong), nanos: c.Ptr(c.Int)) -> c.Int
    raw fn sleep = "io_sleep"(seconds: c.ULongLong, nanos: c.UInt) -> c.Int
    raw fn random = "io_random"(buffer: c.Ptr(c.UChar), length: c.Size) -> c.Int
    raw fn errno_message = "io_errno_message"(code: c.Int, out: c.Ptr(c.UChar), capacity: c.Size) -> c.Size
}

import c "alder_errno.h" as cerrno {
    raw fn last = "c_errno"() -> c.Int
}

import c "std/c/process_shim.h" as proc {
    record type ChildStart = "io_child_start" {
        pid: c.Int
        stdin_fd: c.Int
        stdout_fd: c.Int
        stderr_fd: c.Int
    }

    record type ChildStatusRaw = "io_child_status" {
        kind: c.Int
        value: c.Int
    }

    record type PollPairRaw = "io_poll_pair" {
        first_ready: c.Int
        second_ready: c.Int
    }

    raw fn spawn = "io_spawn"(program: c.ConstPtr(c.Char), argv_blob: c.ConstPtr(c.UChar), argv_length: c.Size, set_blob: c.ConstPtr(c.UChar), set_length: c.Size, remove_blob: c.ConstPtr(c.UChar), remove_length: c.Size, clear_environment: c.Int, has_working_directory: c.Int, working_directory: c.ConstPtr(c.Char), stdin_mode: c.Int, stdout_mode: c.Int, stderr_mode: c.Int, out: c.Ptr(ChildStart)) -> c.Int
    raw fn wait_child = "io_wait_child"(pid: c.Int, out: c.Ptr(ChildStatusRaw)) -> c.Int
    raw fn kill_child = "io_kill_child"(pid: c.Int) -> c.Int
    raw fn poll_pair = "io_poll_pair_wait"(first_fd: c.Int, second_fd: c.Int, timeout_ms: c.Int, out: c.Ptr(PollPairRaw)) -> c.Int
}

// The Milestone 8 std.io v1 stream foundation, slice 1: the `Reader`,
// `Writer`, and `Seek` traits, the portable error category, the exact
// transfer helpers, and two host-free in-memory streams. Everything here is
// pure Alder over values; the capability types, host files, and standard
// streams arrive with the C-binding buffer surface they need in slice 2.
//
// Readers and writers are copyable values whose methods take `mut self`; a
// call exclusively borrows the caller's place, so a stateful stream advances
// exactly once and no descriptor or buffer is copied behind the callee's
// back. A callee that writes through a `MutSlice(U8)` says `mut` on that
// parameter as well.

/// Where a seek starts from. A `Start` offset is absolute; `Current` and
/// `End` offsets are signed.
pub enum SeekFrom {
    Start(offset: U64)
    Current(offset: I64)
    End(offset: I64)
}

/// Portable I/O failure categories plus optional platform detail.
pub enum IoError {
    /// The file or directory does not exist.
    NotFound
    /// Access was denied by permissions or policy.
    PermissionDenied
    /// A create request found an existing target.
    AlreadyExists
    /// An argument was invalid for the operation, including invalid path
    /// encoding and reads past end of stream for `read_exact`.
    InvalidInput
    /// A directory removal found the directory not empty.
    DirectoryNotEmpty
    /// The operation has no implementation on this target.
    Unsupported
    /// A failure with no portable category carries the host error number
    /// and its formatted message.
    Other(info: env.PlatformInfo)
}

impl IoError {
    /// Reads the host error number at this point in the calling thread.
    fn last() -> IoError {
        return IoError.from_errno(unsafe c { cerrno.last() }.to_i32())
    }

    /// Maps one host error number to a category. The values below agree on
    /// the tier-1 POSIX targets; `Other` carries the host's formatted text.
    fn from_errno(code: I32) -> IoError {
        if code == 2 { return NotFound }
        if code == 13 { return PermissionDenied }
        if code == 17 { return AlreadyExists }
        if code == 22 { return InvalidInput }
        if code == 39 { return DirectoryNotEmpty }
        if code == 38 { return Unsupported }
        var message = code.display()
        var room = zero_bytes(256)
        let capacity: U64 = 256
        let length = unsafe c { posix.errno_message(code.to_c_int(), room.slice_mut(0, 256), capacity.to_c_size()) }
        if length.to_u64() != 0 {
            match room.slice(0, length.to_u64()).to_bytes().to_string_checked() {
                Some(text) => { message = text }
                None => {}
            }
        }
        return Other(env.PlatformInfo(code: code, message: message))
    }
}

impl Display for IoError {
    fn display(self) -> String {
        return match self {
            NotFound => "not found"
            PermissionDenied => "permission denied"
            AlreadyExists => "already exists"
            InvalidInput => "invalid input"
            DirectoryNotEmpty => "directory not empty"
            Unsupported => "unsupported"
            Other(info) => info.message
        }
    }
}

impl Error for IoError {
}

// ---- Blocking host capability ------------------------------------------------
//
// The capability constructs host handles inside its own implementation. A
// HostFile/HostDirectory field is module-private, so another module can hold
// and pass a handle but cannot construct one with an arbitrary descriptor;
// affine ownership makes the value non-copyable. Field reads remain visible
// in S0 (ROADMAP records that gap); the opaque-construction boundary is what
// makes a descriptor unforgeable.

/// One open host file. Affine: exactly one owner closes it exactly once,
/// through `io.close` or best-effort cleanup.
pub type HostFile {
    handle: I32
}

impl HostFile {
    /// Takes the descriptor out and disarms cleanup. Only the capability and
    /// the observing close use this.
    fn take_handle(mut self) -> I32 {
        let fd = self.handle
        self.handle = -1
        return fd
    }
}

impl Cleanup for HostFile {
    fn cleanup(take self) -> Unit {
        if self.handle >= 0 {
            let closed = unsafe c { posix.close(self.handle.to_c_int()) }
            if closed.to_i32() != 0 {
                // Best-effort fallback: close errors are not observable here.
            }
        }
        return
    }
}

/// One open host directory listing. Affine, like `HostFile`. The handle is an
/// opaque host round trip; Alder never dereferences it.
pub type HostDirectory {
    handle: U64
}

impl HostDirectory {
    fn take_handle(mut self) -> U64 {
        let token = self.handle
        self.handle = 0
        return token
    }
}

impl Cleanup for HostDirectory {
    fn cleanup(take self) -> Unit {
        if self.handle != 0 {
            let ignored = unsafe c { posix.close_dir(self.handle.to_c_ulonglong()) }
            if ignored.to_i32() != 0 {
                // Best-effort fallback.
            }
        }
        return
    }
}

/// One directory entry as the host reported it.
pub type DirEntry {
    pub name: OsString
    pub kind: EntryKind
}

/// The portable entry kind. Host values outside the known set are `Other`;
/// a host that cannot report the kind uses `Unknown`.
pub enum EntryKind {
    File
    Directory
    Symlink
    Other
    Unknown
}

/// Raw open flags of one host open request. `std.fs` builds this from its
/// public options record; wrappers outside `std.fs` do not need it.
pub type FileMode {
    pub read: Bool
    pub write: Bool
    pub append: Bool
    pub truncate: Bool
    pub create: Bool
    pub create_new: Bool
}

/// How a waited child ended. `kind` 0 is a normal exit with `value` as the
/// code; 1 is a signal termination with `value` as the signal number.
pub type ChildStatus {
    pub kind: U8
    pub value: I32
}

/// Readiness of the two descriptors a capture drain watches.
pub type PollPair {
    pub first_ready: Bool
    pub second_ready: Bool
}

/// One running child and its parent-held pipe ends. The pipe end is absent
/// when that stream was inherited. `std.process` owns the lifetime; cleanup
/// closes every remaining pipe end but never waits or kills by itself.
pub type HostChild {
    pub pid: I32
    pub stdin: Option(HostFile)
    pub stdout: Option(HostFile)
    pub stderr: Option(HostFile)
}

impl Cleanup for HostChild {
    fn cleanup(take self) -> Unit {
        match self.stdin {
            Some(handle) => { handle.cleanup() }
            None => {}
        }
        match self.stdout {
            Some(handle) => { handle.cleanup() }
            None => {}
        }
        match self.stderr {
            Some(handle) => { handle.cleanup() }
            None => {}
        }
        return
    }
}

/// Host timestamp in seconds plus sub-second nanos.
pub type Timestamp {
    pub seconds: I64
    pub nanos: U32
}

/// Host file metadata as the capability reported it.
pub type FileStat {
    pub kind: EntryKind
    pub size: U64
    pub mode: U32
    pub modified: Timestamp
}

/// The I/O capability trait. Every value that may wait on the host or observe
/// host nondeterminism flows through an `Io` implementation.
pub trait Io {
    /// Opens or creates the file at `path` with the requested flags.
    fn open(self, path: Path, mode: FileMode) -> Result(HostFile, IoError)
    /// Reads up to `buffer.len()` bytes; `Ok(0)` means end of file.
    fn read(self, mut file: HostFile, mut buffer: MutSlice(U8)) -> Result(U64, IoError)
    /// Writes up to `data.len()` bytes from the start of `data`.
    fn write(self, mut file: HostFile, data: [U8]) -> Result(U64, IoError)
    /// Moves to `from` and returns the new absolute position.
    fn seek(self, mut file: HostFile, from: SeekFrom) -> Result(U64, IoError)
    /// Closes the file, consuming the handle.
    fn close(self, take file: HostFile) -> Result(Unit, IoError)
    /// Flushes host buffers to durable storage.
    fn sync(self, mut file: HostFile) -> Result(Unit, IoError)
    /// Metadata of the open file.
    fn stat(self, mut file: HostFile) -> Result(FileStat, IoError)
    /// Metadata of the file at `path`, following symlinks.
    fn stat_path(self, path: Path) -> Result(FileStat, IoError)
    /// Metadata of `path` without following a final symlink.
    fn lstat(self, path: Path) -> Result(FileStat, IoError)
    /// Replaces the file's permission mode.
    fn set_permissions(self, mut file: HostFile, mode: U32) -> Result(Unit, IoError)
    /// Renames `from` to `to` in place.
    fn rename(self, from: Path, to: Path) -> Result(Unit, IoError)
    /// Removes the file (or symlink) at `path`.
    fn remove(self, path: Path) -> Result(Unit, IoError)
    /// Removes the empty directory at `path`.
    fn remove_directory(self, path: Path) -> Result(Unit, IoError)
    /// Creates one directory.
    fn make_directory(self, path: Path) -> Result(Unit, IoError)
    /// Resolves symlinks and returns the absolute canonical path.
    fn canonicalize(self, path: Path) -> Result(Path, IoError)
    /// Opens a directory listing.
    fn open_directory(self, path: Path) -> Result(HostDirectory, IoError)
    /// Next entry of the listing in host order; `None` at the end.
    fn read_directory(self, mut directory: HostDirectory) -> Result(Option(DirEntry), IoError)
    /// Closes the listing, consuming the handle.
    fn close_directory(self, take directory: HostDirectory) -> Result(Unit, IoError)
    /// Reads from standard input; `Ok(0)` at end of input.
    fn read_stdin(self, mut buffer: MutSlice(U8)) -> Result(U64, IoError)
    /// Writes to standard output.
    fn write_stdout(self, data: [U8]) -> Result(U64, IoError)
    /// Writes to standard error.
    fn write_stderr(self, data: [U8]) -> Result(U64, IoError)
    /// Starts a child. `stdin_mode`, `stdout_mode`, and `stderr_mode` are 0
    /// for inheritance and 1 for a pipe; a piped stream returns its parent
    /// end in the child record. Arguments and environment entries are exact
    /// host bytes; no shell, quoting, or expansion is involved.
    fn spawn(self, program: OsString, arguments: Vec(OsString), set_environment: Vec(OsString), remove_environment: Vec(OsString), clear_environment: Bool, working_directory: Option(Path), stdin_mode: U8, stdout_mode: U8, stderr_mode: U8) -> Result(HostChild, IoError)
    /// Waits for `pid` and reports how it ended.
    fn wait(self, pid: I32) -> Result(ChildStatus, IoError)
    /// Sends an unconditional kill to `pid`.
    fn kill(self, pid: I32) -> Result(Unit, IoError)
    /// Waits until either pipe end has input, hangup, or an error. A
    /// negative timeout waits without a deadline; readiness includes the
    /// hangup and error states, so a caller always reaches a read that
    /// observes end of stream.
    fn poll(self, mut first: HostFile, mut second: HostFile, timeout_ms: I32) -> Result(PollPair, IoError)
    /// Sleeps without observing an earlier wakeup.
    fn sleep(self, seconds: U64, nanos: U32) -> Unit
    /// Reads the monotonic clock.
    fn monotonic(self) -> Timestamp
    /// Reads the wall clock.
    fn wallclock(self) -> Timestamp
    /// Fills `buffer` with unpredictable bytes; a host failure terminates.
    fn random_bytes(self, buffer: MutSlice(U8)) -> Unit
}

/// Marks a capability whose operations never suspend.
pub trait BlockingIo {
}

/// Marks a capability whose operations suspend through an executor. Declared
/// in v1 so bounds can name it; `Evented` arrives with Milestone 9.
pub trait AsyncIo {
}

/// The blocking capability. Direct host calls; `EINTR` is retried inside each
/// operation and never surfaces.
pub type Blocking {
}

/// Converts a path to the NUL-terminated host form. A path never contains an
/// interior NUL, so `None` is unreachable and maps to InvalidInput.
fn host_path(path: Path) -> Result(Vec(U8), IoError) {
    // Build the NUL-terminated host form without an affine c_string: the
    // buffer is a plain Vec(U8) passed through the call-scoped byte borrow.
    // The interior-NUL check is the same one c.CString performs, so a path
    // can never be silently truncated at a host boundary.
    let data = path.to_os().to_bytes()
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        let byte = data.byte(at)
        if byte == 0 { return Err(InvalidInput) }
        out.push(byte)
        at = at + 1
    }
    out.push(0)
    return Ok(out)
}

fn flag_int(value: Bool) -> I32 {
    if value { return 1 }
    return 0
}

fn entry_kind(code: I32) -> EntryKind {
    if code == 1 { return File }
    if code == 2 { return Directory }
    if code == 3 { return Symlink }
    if code == 4 { return Other }
    return Unknown
}


fn seek_offset(from: SeekFrom) -> I64 {
    return match from {
        Start(offset) => offset.to_i64_wrapping()
        Current(offset) => offset
        End(offset) => offset
    }
}

fn seek_whence(from: SeekFrom) -> I32 {
    return match from {
        Start(_) => 0
        Current(_) => 1
        End(_) => 2
    }
}

fn file_stat_from(raw: FileStatRaw) -> FileStat {
    let kind = unsafe c { raw.kind }
    let size = unsafe c { raw.size }
    let mode = unsafe c { raw.mode }
    let seconds = unsafe c { raw.seconds }
    let nanos = unsafe c { raw.nanos }
    return FileStat(kind: entry_kind(kind.to_i32()), size: size.to_u64(), mode: mode.to_u32(), modified: Timestamp(seconds: seconds.to_i64(), nanos: nanos.to_i32().to_u32_wrapping()))
}

fn os_bytes(value: OsString) -> Vec(U8) {
    let data = value.to_bytes()
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        out.push(data.byte(at))
        at = at + 1
    }
    out.push(0)
    return out
}

fn blob_append(blob: Vec(U8), value: OsString) -> Vec(U8) {
    var copy = blob
    let data = value.to_bytes()
    var at: U64 = 0
    while at < data.len() {
        copy.push(data.byte(at))
        at = at + 1
    }
    copy.push(0)
    return copy
}

fn blob_of(values: Vec(OsString)) -> Vec(U8) {
    var blob: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < values.len() {
        blob = blob_append(blob, values[at])
        at = at + 1
    }
    return blob
}

fn pipe_end(fd: I32) -> Option(HostFile) {
    if fd >= 0 { return Some(HostFile(handle: fd)) }
    return None
}

impl Io for Blocking {
    fn open(self, path: Path, mode: FileMode) -> Result(HostFile, IoError) {
        let path_bytes = try host_path(path)
        let fd = unsafe c { posix.open(path_bytes.slice(0, path_bytes.len()), flag_int(mode.read).to_c_int(), flag_int(mode.write).to_c_int(), flag_int(mode.append).to_c_int(), flag_int(mode.truncate).to_c_int(), flag_int(mode.create).to_c_int(), flag_int(mode.create_new).to_c_int()) }
        if fd.to_i32() < 0 { return Err(IoError.last()) }
        return Ok(HostFile(handle: fd.to_i32()))
    }

    fn read(self, mut file: HostFile, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        let count = unsafe c { posix.read(file.handle.to_c_int(), buffer, buffer.len().to_c_size()) }
        if count.to_i64() < 0 { return Err(IoError.last()) }
        return Ok(count.to_i64().to_u64_wrapping())
    }

    fn write(self, mut file: HostFile, data: [U8]) -> Result(U64, IoError) {
        let count = unsafe c { posix.write(file.handle.to_c_int(), data, data.len().to_c_size()) }
        if count.to_i64() < 0 { return Err(IoError.last()) }
        return Ok(count.to_i64().to_u64_wrapping())
    }

    fn seek(self, mut file: HostFile, from: SeekFrom) -> Result(U64, IoError) {
        var position = c.Zero(c.LongLong)
        let rc = unsafe c { posix.seek(file.handle.to_c_int(), seek_offset(from).to_c_longlong(), seek_whence(from).to_c_int(), c.addr(position)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(position.to_i64().to_u64_wrapping())
    }

    fn close(self, take file: HostFile) -> Result(Unit, IoError) {
        let fd = file.take_handle()
        file.cleanup()
        let rc = unsafe c { posix.close(fd.to_c_int()) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn sync(self, mut file: HostFile) -> Result(Unit, IoError) {
        let rc = unsafe c { posix.sync(file.handle.to_c_int()) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn stat(self, mut file: HostFile) -> Result(FileStat, IoError) {
        var raw = c.Zero(FileStatRaw)
        let rc = unsafe c { posix.fstat(file.handle.to_c_int(), c.addr(raw)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(file_stat_from(raw))
    }

    fn stat_path(self, path: Path) -> Result(FileStat, IoError) {
        let path_bytes = try host_path(path)
        var raw = c.Zero(FileStatRaw)
        let rc = unsafe c { posix.stat_path(path_bytes.slice(0, path_bytes.len()), c.addr(raw)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(file_stat_from(raw))
    }

    fn lstat(self, path: Path) -> Result(FileStat, IoError) {
        let path_bytes = try host_path(path)
        var raw = c.Zero(FileStatRaw)
        let rc = unsafe c { posix.lstat(path_bytes.slice(0, path_bytes.len()), c.addr(raw)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(file_stat_from(raw))
    }

    fn set_permissions(self, mut file: HostFile, mode: U32) -> Result(Unit, IoError) {
        let rc = unsafe c { posix.fchmod(file.handle.to_c_int(), mode.to_c_uint()) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn rename(self, from: Path, to: Path) -> Result(Unit, IoError) {
        let from_bytes = try host_path(from)
        let to_bytes = try host_path(to)
        let rc = unsafe c { posix.rename(from_bytes.slice(0, from_bytes.len()), to_bytes.slice(0, to_bytes.len())) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn remove(self, path: Path) -> Result(Unit, IoError) {
        let path_bytes = try host_path(path)
        let rc = unsafe c { posix.remove(path_bytes.slice(0, path_bytes.len())) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn remove_directory(self, path: Path) -> Result(Unit, IoError) {
        let path_bytes = try host_path(path)
        let rc = unsafe c { posix.remove_directory(path_bytes.slice(0, path_bytes.len())) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn make_directory(self, path: Path) -> Result(Unit, IoError) {
        let path_bytes = try host_path(path)
        let mode: U32 = 511
        let rc = unsafe c { posix.make_directory(path_bytes.slice(0, path_bytes.len()), mode.to_c_uint()) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn canonicalize(self, path: Path) -> Result(Path, IoError) {
        let path_bytes = try host_path(path)
        var room = zero_bytes(4096)
        let capacity: U64 = 4096
        let length = unsafe c { posix.canonicalize(path_bytes.slice(0, path_bytes.len()), room.slice_mut(0, 4096), capacity.to_c_size()) }
        if length.to_i64() < 0 { return Err(IoError.last()) }
        let bytes = room.slice(0, length.to_i64().to_u64_wrapping()).to_bytes()
        var result: Result(Path, IoError) = Err(InvalidInput)
        match OsString.from_bytes(bytes) {
            Ok(name) => { result = Ok(Path.from_os(name)) }
            Err(_) => { result = Err(InvalidInput) }
        }
        return result
    }

    fn open_directory(self, path: Path) -> Result(HostDirectory, IoError) {
        let path_bytes = try host_path(path)
        let token = unsafe c { posix.open_directory(path_bytes.slice(0, path_bytes.len())) }
        if token.to_u64() == 0 { return Err(IoError.last()) }
        return Ok(HostDirectory(handle: token.to_u64()))
    }

    fn read_directory(self, mut directory: HostDirectory) -> Result(Option(DirEntry), IoError) {
        var room = zero_bytes(256)
        let capacity: U64 = 256
        var length = c.Zero(c.Size)
        var kind = c.Zero(c.Int)
        let rc = unsafe c { posix.read_directory(directory.handle.to_c_ulonglong(), room.slice_mut(0, 256), capacity.to_c_size(), c.addr(length), c.addr(kind)) }
        if rc.to_i32() < 0 { return Err(IoError.last()) }
        if rc.to_i32() == 0 { return Ok(None) }
        let bytes = room.slice(0, length.to_u64()).to_bytes()
        var entry: Option(DirEntry) = None
        match OsString.from_bytes(bytes) {
            Ok(name) => { entry = Some(DirEntry(name: name, kind: entry_kind(kind.to_i32()))) }
            Err(_) => {}
        }
        return Ok(entry)
    }

    fn close_directory(self, take directory: HostDirectory) -> Result(Unit, IoError) {
        let token = directory.take_handle()
        directory.cleanup()
        let rc = unsafe c { posix.close_dir(token.to_c_ulonglong()) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn read_stdin(self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        let stdin_fd: I32 = 0
        let count = unsafe c { posix.read(stdin_fd.to_c_int(), buffer, buffer.len().to_c_size()) }
        if count.to_i64() < 0 { return Err(IoError.last()) }
        return Ok(count.to_i64().to_u64_wrapping())
    }

    fn write_stdout(self, data: [U8]) -> Result(U64, IoError) {
        let stdout_fd: I32 = 1
        let count = unsafe c { posix.write(stdout_fd.to_c_int(), data, data.len().to_c_size()) }
        if count.to_i64() < 0 { return Err(IoError.last()) }
        return Ok(count.to_i64().to_u64_wrapping())
    }

    fn write_stderr(self, data: [U8]) -> Result(U64, IoError) {
        let stderr_fd: I32 = 2
        let count = unsafe c { posix.write(stderr_fd.to_c_int(), data, data.len().to_c_size()) }
        if count.to_i64() < 0 { return Err(IoError.last()) }
        return Ok(count.to_i64().to_u64_wrapping())
    }

    fn spawn(self, program: OsString, arguments: Vec(OsString), set_environment: Vec(OsString), remove_environment: Vec(OsString), clear_environment: Bool, working_directory: Option(Path), stdin_mode: U8, stdout_mode: U8, stderr_mode: U8) -> Result(HostChild, IoError) {
        let program_bytes = os_bytes(program)
        var argv_values: Vec(OsString) = Vec.new(OsString)
        argv_values.push(program)
        var argument_at: U64 = 0
        while argument_at < arguments.len() {
            argv_values.push(arguments[argument_at])
            argument_at = argument_at + 1
        }
        let args_blob = blob_of(argv_values)
        let set_blob = blob_of(set_environment)
        let remove_blob = blob_of(remove_environment)
        var cwd: Vec(U8) = Vec.new(U8)
        var has_cwd: I32 = 0
        match working_directory {
            Some(path) => {
                cwd = try host_path(path)
                has_cwd = 1
            }
            None => {}
        }
        var raw = c.Zero(ChildStart)
        let rc = unsafe c { proc.spawn(program_bytes.slice(0, program_bytes.len()), args_blob.slice(0, args_blob.len()), args_blob.len().to_c_size(), set_blob.slice(0, set_blob.len()), set_blob.len().to_c_size(), remove_blob.slice(0, remove_blob.len()), remove_blob.len().to_c_size(), flag_int(clear_environment).to_c_int(), has_cwd.to_c_int(), cwd.slice(0, cwd.len()), stdin_mode.to_c_int(), stdout_mode.to_c_int(), stderr_mode.to_c_int(), c.addr(raw)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        let pid = unsafe c { raw.pid }
        let input_fd = unsafe c { raw.stdin_fd }
        let output_fd = unsafe c { raw.stdout_fd }
        let error_fd = unsafe c { raw.stderr_fd }
        return Ok(HostChild(pid: pid.to_i32(), stdin: pipe_end(input_fd.to_i32()), stdout: pipe_end(output_fd.to_i32()), stderr: pipe_end(error_fd.to_i32())))
    }

    fn wait(self, pid: I32) -> Result(ChildStatus, IoError) {
        var raw = c.Zero(ChildStatusRaw)
        let rc = unsafe c { proc.wait_child(pid.to_c_int(), c.addr(raw)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        let kind = unsafe c { raw.kind }
        let value = unsafe c { raw.value }
        return Ok(ChildStatus(kind: kind.to_i32().to_u8_wrapping(), value: value.to_i32()))
    }

    fn kill(self, pid: I32) -> Result(Unit, IoError) {
        let rc = unsafe c { proc.kill_child(pid.to_c_int()) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        return Ok(())
    }

    fn poll(self, mut first: HostFile, mut second: HostFile, timeout_ms: I32) -> Result(PollPair, IoError) {
        var raw = c.Zero(PollPairRaw)
        let rc = unsafe c { proc.poll_pair(first.handle.to_c_int(), second.handle.to_c_int(), timeout_ms.to_c_int(), c.addr(raw)) }
        if rc.to_i32() != 0 { return Err(IoError.last()) }
        let first_ready = unsafe c { raw.first_ready }
        let second_ready = unsafe c { raw.second_ready }
        return Ok(PollPair(first_ready: first_ready.to_i32() != 0, second_ready: second_ready.to_i32() != 0))
    }

    fn sleep(self, seconds: U64, nanos: U32) -> Unit {
        let ignored = unsafe c { posix.sleep(seconds.to_c_ulonglong(), nanos.to_c_uint()) }
        if ignored.to_i32() != 0 {
            panic("io.sleep failed")
        }
        return
    }

    fn monotonic(self) -> Timestamp {
        var seconds = c.Zero(c.LongLong)
        var nanos = c.Zero(c.Int)
        let monotonic_clock: I32 = 1
        let rc = unsafe c { posix.clock_gettime(monotonic_clock.to_c_int(), c.addr(seconds), c.addr(nanos)) }
        if rc.to_i32() != 0 {
            panic("io.monotonic failed")
        }
        return Timestamp(seconds: seconds.to_i64(), nanos: nanos.to_i32().to_u32_wrapping())
    }

    fn wallclock(self) -> Timestamp {
        var seconds = c.Zero(c.LongLong)
        var nanos = c.Zero(c.Int)
        let realtime_clock: I32 = 0
        let rc = unsafe c { posix.clock_gettime(realtime_clock.to_c_int(), c.addr(seconds), c.addr(nanos)) }
        if rc.to_i32() != 0 {
            panic("io.wallclock failed")
        }
        return Timestamp(seconds: seconds.to_i64(), nanos: nanos.to_i32().to_u32_wrapping())
    }

    fn random_bytes(self, buffer: MutSlice(U8)) -> Unit {
        let rc = unsafe c { posix.random(buffer, buffer.len().to_c_size()) }
        if rc.to_i32() != 0 {
            panic("io.random_bytes failed")
        }
        return
    }
}

impl BlockingIo for Blocking {
}

/// A byte source. `Ok(0)` means end of stream for stream readers. The
/// `copy_to` requirement's default body copies through a bounded internal
/// buffer and does not flush buffered writers.
pub trait Reader {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError)
    fn copy_to(W: type(Writer), mut self, mut output: W) -> Result(U64, IoError) {
        var storage: Vec(U8) = Vec.new(U8)
        var filled: U64 = 0
        while filled < 4096 {
            storage.push(0)
            filled = filled + 1
        }
        var total: U64 = 0
        var reading = true
        while reading {
            let count = try self.read(storage.slice_mut(0, 4096))
            if count == 0 {
                reading = false
            } else {
                let written = try write_all(output, storage.slice(0, count))
                total = total + written
            }
        }
        return Ok(total)
    }
}

/// A byte sink. `write` may accept fewer bytes than requested; callers that
/// need complete writes use `write_all`. `flush` makes buffered writes
/// observable; an unbuffered writer returns `Ok(())`.
pub trait Writer {
    fn write(mut self, data: [U8]) -> Result(U64, IoError)
    fn flush(mut self) -> Result(Unit, IoError)
}

/// A repositionable byte stream. Returns the new absolute position.
pub trait Seek {
    fn seek(mut self, from: SeekFrom) -> Result(U64, IoError)
}

/// Reads until `buffer` is full or fails with `InvalidInput` at end of
/// stream. The reader's position after a failed call is unspecified.
pub fn read_exact(R: type(Reader), mut reader: R, mut buffer: MutSlice(U8)) -> Result(Unit, IoError) {
    var filled: U64 = 0
    let size = buffer.len()
    while filled < size {
        let count = try reader.read(buffer.subview(filled, size))
        if count == 0 {
            return Err(InvalidInput)
        }
        filled = filled + count
    }
    return Ok(())
}

/// Writes all of `data` or fails; returns `data.len()` on success.
pub fn write_all(W: type(Writer), mut writer: W, data: [U8]) -> Result(U64, IoError) {
    var written: U64 = 0
    let size = data.len()
    while written < size {
        let count = try writer.write(data.slice(written, size))
        if count == 0 {
            return Err(InvalidInput)
        }
        written = written + count
    }
    return Ok(written)
}

/// Reads to end of stream. Growth uses ordinary checked vector growth and
/// terminates on exhaustion; there is no size limit in v1.
pub fn read_to_end(R: type(Reader), mut reader: R) -> Result(Vec(U8), IoError) {
    var collected: Vec(U8) = Vec.new(U8)
    var storage: Vec(U8) = Vec.new(U8)
    var filled: U64 = 0
    while filled < 4096 {
        storage.push(0)
        filled = filled + 1
    }
    var reading = true
    while reading {
        let count = try reader.read(storage.slice_mut(0, 4096))
        if count == 0 {
            reading = false
        } else {
            var copied: U64 = 0
            while copied < count {
                collected.push(storage[copied])
                copied = copied + 1
            }
        }
    }
    return Ok(collected)
}

/// Reader over an owned `Bytes` value. Pure and host-free, so buffered
/// behavior tests never touch the OS.
pub type ByteCursor {
    data: Bytes
    position: U64
}

impl ByteCursor {
    fn new(data: Bytes) -> ByteCursor {
        return ByteCursor(data: data, position: 0)
    }
}

impl Reader for ByteCursor {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        let remaining = self.data.len() - self.position
        var count = buffer.len()
        if count > remaining {
            count = remaining
        }
        var at: U64 = 0
        while at < count {
            buffer[at] = self.data.byte(self.position + at)
            at = at + 1
        }
        self.position = self.position + count
        return Ok(count)
    }
}

/// Grows an owned byte vector from writes. `new` starts with 4096 bytes of
/// room; `with_capacity` selects another initial size. `write` grows the
/// sink to accept every byte and returns the full count.
pub type ByteSink {
    data: Vec(U8)
    length: U64
}

impl ByteSink {
    fn new() -> ByteSink {
        return ByteSink.with_capacity(4096)
    }

    fn with_capacity(capacity: U64) -> ByteSink {
        return ByteSink(data: zero_bytes(capacity), length: 0)
    }

    fn len(self) -> U64 {
        return self.length
    }

    fn into_bytes(self) -> Bytes {
        return self.data.slice(0, self.length).to_bytes()
    }
}

impl Writer for ByteSink {
    fn write(mut self, data: [U8]) -> Result(U64, IoError) {
        let count = data.len()
        let needed = self.length + count
        while self.data.len() < needed {
            self.data.push(0)
        }
        var at: U64 = 0
        while at < count {
            self.data[self.length + at] = data[at]
            at = at + 1
        }
        self.length = needed
        return Ok(count)
    }

    fn flush(mut self) -> Result(Unit, IoError) {
        return Ok(())
    }
}

// Buffered streams. The reader keeps a byte window that a refill replaces
// from the source; the writer accumulates bytes and hands them to its sink
// on flush. Both take their source/sink by value: a capability value is
// copyable, and an affine owner moves into the wrapper exactly once.

/// Buffers reads from any `Reader`. Copyable when its source is; the
/// compiler updates a uniquely owned reader in place through `mut self`.
pub type BufReader(Source: type(Reader)) {
    source: Source
    buffer: Vec(U8)
    position: U64
    length: U64
}

impl(Source: type(Reader)) BufReader(Source) {
    fn new(source: Source) -> BufReader(Source) {
        return BufReader(Source)(source: source, buffer: zero_bytes(4096), position: 0, length: 0)
    }

    fn with_capacity(capacity: U64, source: Source) -> BufReader(Source) {
        var room = capacity
        if room == 0 { room = 1 }
        return BufReader(Source)(source: source, buffer: zero_bytes(room), position: 0, length: 0)
    }

    /// Reads through `delimiter` into the result, without it at end of
    /// stream. `None` means end of stream before any byte was read.
    fn read_until(mut self, delimiter: U8) -> Result(Option(Vec(U8)), IoError) {
        var out: Vec(U8) = Vec.new(U8)
        var scanning = true
        while scanning {
            if self.position >= self.length {
                let filled = try self.refill()
                if filled == 0 {
                    scanning = false
                    if out.len() == 0 { return Ok(None) }
                    return Ok(Some(out))
                }
            }
            if scanning {
                let one = self.buffer[self.position]
                self.position = self.position + 1
                out.push(one)
                if one == delimiter { scanning = false }
            }
        }
        return Ok(Some(out))
    }

    /// One line through the newline, which is kept. Invalid UTF-8 is
    /// `InvalidInput`.
    fn read_line(mut self) -> Result(Option(String), IoError) {
        let line = try self.read_until(10)
        var result: Result(Option(String), IoError) = Ok(None)
        match line {
            Some(bytes) => {
                let data = bytes.slice(0, bytes.len()).to_bytes()
                match data.to_string_checked() {
                    Some(text) => { result = Ok(Some(text)) }
                    None => { result = Err(InvalidInput) }
                }
            }
            None => { result = Ok(None) }
        }
        return result
    }

    fn refill(mut self) -> Result(U64, IoError) {
        let size = self.buffer.len()
        let count = try self.source.read(self.buffer.slice_mut(0, size))
        self.position = 0
        self.length = count
        return Ok(count)
    }
}

impl(Source: type(Reader, Cleanup)) BufReader(Source) {
    /// Returns the wrapped reader. Pending buffered bytes stay unread; the
    /// buffer is an ordinary `Vec(U8)` that owns no element cleanup.
    fn into_source(take self) -> Source {
        return self.source
    }
}

impl(Source: type(Reader)) Reader for BufReader(Source) {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        let size = buffer.len()
        var produced: U64 = 0
        while produced < size {
            if self.position >= self.length {
                let filled = try self.refill()
                if filled == 0 { return Ok(produced) }
            }
            let available = self.length - self.position
            var chunk = size - produced
            if chunk > available { chunk = available }
            var at: U64 = 0
            while at < chunk {
                buffer[produced + at] = self.buffer[self.position + at]
                at = at + 1
            }
            self.position = self.position + chunk
            produced = produced + chunk
        }
        return Ok(produced)
    }
}

/// Buffers writes to any `Writer` that cleans up as an owner.
pub type BufWriter(Sink: type(Writer, Cleanup)) {
    sink: Sink
    buffer: Vec(U8)
    length: U64
}

impl(Sink: type(Writer, Cleanup)) BufWriter(Sink) {
    fn new(take sink: Sink) -> BufWriter(Sink) {
        return BufWriter(Sink)(sink: sink, buffer: zero_bytes(4096), length: 0)
    }

    fn with_capacity(capacity: U64, take sink: Sink) -> BufWriter(Sink) {
        var room = capacity
        if room == 0 { room = 1 }
        return BufWriter(Sink)(sink: sink, buffer: zero_bytes(room), length: 0)
    }

    /// Flushes pending bytes and returns the sink. A flush error releases
    /// the sink here, so the caller no longer holds it.
    fn into_sink(take self) -> Result(Sink, IoError) {
        let pending = self.length
        var offset: U64 = 0
        while offset < pending {
            match self.sink.write(self.buffer.slice(offset, pending)) {
                Ok(written) => {
                    if written == 0 {
                        self.sink.cleanup()
                        return Err(InvalidInput)
                    }
                    offset = offset + written
                }
                Err(error) => {
                    self.sink.cleanup()
                    return Err(error)
                }
            }
        }
        return Ok(self.sink)
    }

}

impl(Sink: type(Writer, Cleanup)) Writer for BufWriter(Sink) {
    fn write(mut self, data: [U8]) -> Result(U64, IoError) {
        let size = data.len()
        if size == 0 { return Ok(0) }
        let room = self.buffer.len()
        if self.length + size > room {
            match self.flush() {
                Ok(_) => {}
                Err(error) => { return Err(error) }
            }
        }
        if size >= room {
            return self.sink.write(data)
        }
        let base = self.length
        let total = base + size
        // The view borrows the field storage directly. Scope it so the
        // exclusive borrow ends before the length update below.
        if true {
            var view: MutSlice(U8) = self.buffer.slice_mut(0, total)
            var at: U64 = 0
            while at < size {
                view[base + at] = data[at]
                at = at + 1
            }
        }
        self.length = total
        return Ok(size)
    }

    fn flush(mut self) -> Result(Unit, IoError) {
        var offset: U64 = 0
        while offset < self.length {
            let written = try self.sink.write(self.buffer.slice(offset, self.length))
            if written == 0 { return Err(InvalidInput) }
            offset = offset + written
        }
        self.length = 0
        return Ok(())
    }
}

impl(Sink: type(Writer, Cleanup)) Cleanup for BufWriter(Sink) {
    fn cleanup(take self) -> Unit {
        // Best-effort flush: a `take self` binding cannot become a mutable
        // local, so the pending bytes go to the sink directly and every
        // write error is swallowed. `into_sink` is the observing release.
        // The window is copied before the sink moves out, and it is a local
        // so the field-view-as-argument limitation cannot drop the bytes.
        let pending = self.length
        var window = self.buffer
        let sink = self.sink
        var offset: U64 = 0
        while offset < pending {
            match sink.write(window.slice(offset, pending)) {
                Ok(written) => {
                    if written == 0 { offset = pending } else { offset = offset + written }
                }
                Err(_) => { offset = pending }
            }
        }
        sink.cleanup()
    }
}

fn zero_bytes(capacity: U64) -> Vec(U8) {
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < capacity {
        out.push(0)
        at = at + 1
    }
    return out
}

// Standard streams and text helpers. The standard descriptors are owned by
// the process, so these values are copyable non-owning views that never close
// their descriptor or create a second owner.
pub type Stdin(IoType: type(Io)) {
    io: IoType
}

pub type Stdout(IoType: type(Io)) {
    io: IoType
}

pub type Stderr(IoType: type(Io)) {
    io: IoType
}

impl(IoType: type(Io)) Reader for Stdin(IoType) {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.io.read_stdin(buffer)
    }
}

impl(IoType: type(Io)) Writer for Stdout(IoType) {
    fn write(mut self, data: [U8]) -> Result(U64, IoError) {
        return self.io.write_stdout(data)
    }

    fn flush(mut self) -> Result(Unit, IoError) {
        return Ok(())
    }
}

impl(IoType: type(Io)) Writer for Stderr(IoType) {
    fn write(mut self, data: [U8]) -> Result(U64, IoError) {
        return self.io.write_stderr(data)
    }

    fn flush(mut self) -> Result(Unit, IoError) {
        return Ok(())
    }
}

pub fn stdin(I: type(Io), io: I) -> Stdin(I) {
    return Stdin(io: io)
}

pub fn stdout(I: type(Io), io: I) -> Stdout(I) {
    return Stdout(io: io)
}

pub fn stderr(I: type(Io), io: I) -> Stderr(I) {
    return Stderr(io: io)
}

fn text_bytes(text: String) -> Vec(U8) {
    let data = text.to_bytes()
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        out.push(data.byte(at))
        at = at + 1
    }
    return out
}

// Text helpers write until the descriptor accepts every byte or a write
// fails. The contract is best-effort: standard streams report errors only
// through the observing `Io` methods, never through these functions.
fn write_stdout_all(I: type(Io), io: I, data: [U8]) -> Unit {
    var at: U64 = 0
    while at < data.len() {
        match io.write_stdout(data.slice(at, data.len())) {
            Ok(count) => {
                if count == 0 { return }
                at = at + count
            }
            Err(_) => { return }
        }
    }
    return
}

fn write_stderr_all(I: type(Io), io: I, data: [U8]) -> Unit {
    var at: U64 = 0
    while at < data.len() {
        match io.write_stderr(data.slice(at, data.len())) {
            Ok(count) => {
                if count == 0 { return }
                at = at + count
            }
            Err(_) => { return }
        }
    }
    return
}

pub fn print(I: type(Io), io: I, text: String) -> Unit {
    let bytes = text_bytes(text)
    write_stdout_all(io, bytes.slice(0, bytes.len()))
    return
}

pub fn println(I: type(Io), io: I, text: String) -> Unit {
    let bytes = text_bytes(text)
    write_stdout_all(io, bytes.slice(0, bytes.len()))
    let newline: Array(U8, 1) = [10]
    write_stdout_all(io, newline.slice(0, 1))
    return
}

pub fn eprint(I: type(Io), io: I, text: String) -> Unit {
    let bytes = text_bytes(text)
    write_stderr_all(io, bytes.slice(0, bytes.len()))
    return
}

pub fn eprintln(I: type(Io), io: I, text: String) -> Unit {
    let bytes = text_bytes(text)
    write_stderr_all(io, bytes.slice(0, bytes.len()))
    let newline: Array(U8, 1) = [10]
    write_stderr_all(io, newline.slice(0, 1))
    return
}
