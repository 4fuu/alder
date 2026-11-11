# `std.io` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for the hosted I/O capability layer. It
is normative together with the executable example
[`examples/std.io-v1.al`](examples/std.io-v1.al), which lands in the module's
implementation commit: the docs example runner resolves sysroot modules, so the
example file cannot precede the module it imports. The module lives at
`<sysroot>/std/io.al`.

Snapshot v1 covers the blocking half of the frozen contract: the `Io` and
`BlockingIo` capability traits, the `Blocking` capability, the `Reader`,
`Writer`, and `Seek` traits, buffered readers and writers, standard input,
output, and error, the exact/copy helpers, and `IoError`. The `AsyncIo` trait is
declared here with no implementation; `Evented`, `SimIo`, and the suspending
lowering arrive with Milestone 9 as an additive v2 of this snapshot.

## Signatures

### Capability traits and the blocking capability

```alder
module std.io

import std.env { PlatformInfo }
import std.path { OsString, Path }

/// One open host file. Affine: exactly one owner closes it exactly once,
/// through `io.close` or best-effort cleanup. The capability constructs
/// handles inside its own implementation; callers can neither forge,
/// copy, nor reuse one, so a closed handle can never alias a descriptor
/// number that another file later reuses.
pub type HostFile {
    // private: handle
}

impl Cleanup for HostFile {
    // Best-effort close. Close errors are swallowed by contract: the
    // observing release is `io.close`.
}

/// One open host directory listing. Affine, like `HostFile`: only the
/// capability constructs one, and only its owner closes it.
pub type HostDirectory {
    // private: handle
}

impl Cleanup for HostDirectory {
    // Best-effort close. Close errors are swallowed by contract: the
    // observing release is `io.close_directory`.
}

/// One directory entry as the host reported it.
pub type DirEntry {
    name: OsString
    kind: EntryKind
}

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
    read: Bool
    write: Bool
    append: Bool
    truncate: Bool
    create: Bool
    create_new: Bool
}

/// Host timestamp in seconds plus sub-second nanos. `seconds` counts from
/// the platform epoch for wall-clock reads and is unspecified for monotonic
/// reads; only differences of two monotonic reads are meaningful.
pub type Timestamp {
    seconds: U64
    nanos: U32
}

/// Host file metadata as the capability reported it.
pub type FileStat {
    kind: EntryKind
    size: U64
    /// POSIX mode bits of the owner on POSIX targets; best-effort mapping
    /// elsewhere. Use `std.fs.Permissions` for the portable query.
    mode: U32
    modified: Timestamp
}

/// The I/O capability trait. Every value that may wait on the host or observe
/// host nondeterminism flows through an `Io` implementation. Requirement
/// arguments and results use only `std.io` types, `std.path.Path`, and
/// primitives, so no module cycle can form.
pub trait Io {
    /// Opens or creates the file at `path` with the requested flags.
    fn open(self, path: Path, mode: FileMode) -> Result(HostFile, IoError)
    /// Reads up to `buffer.len()` bytes; `Ok(0)` means end of file.
    fn read(self, file: HostFile, buffer: MutSlice(U8)) -> Result(U64, IoError)
    /// Writes up to `data.len()` bytes from the start of `data`.
    fn write(self, file: HostFile, data: [U8]) -> Result(U64, IoError)
    /// Moves to `from` and returns the new absolute position.
    fn seek(self, file: HostFile, from: SeekFrom) -> Result(U64, IoError)
    /// Closes the file, consuming the handle. Called by `File.finish` and
    /// by cleanup.
    fn close(self, take file: HostFile) -> Result(Unit, IoError)
    /// Flushes host buffers to durable storage.
    fn sync(self, file: HostFile) -> Result(Unit, IoError)
    /// Metadata of the open file.
    fn stat(self, file: HostFile) -> Result(FileStat, IoError)
    /// Metadata of the file at `path`, following symlinks.
    fn stat_path(self, path: Path) -> Result(FileStat, IoError)
    /// Replaces the file's permission mode.
    fn set_permissions(self, file: HostFile, mode: U32) -> Result(Unit, IoError)
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
    fn read_directory(self, directory: HostDirectory)
        -> Result(Option(DirEntry), IoError)
    /// Closes the listing, consuming the handle.
    fn close_directory(self, take directory: HostDirectory)
        -> Result(Unit, IoError)
    /// Reads from standard input; `Ok(0)` at end of input.
    fn read_stdin(self, buffer: MutSlice(U8)) -> Result(U64, IoError)
    /// Writes to standard output.
    fn write_stdout(self, data: [U8]) -> Result(U64, IoError)
    /// Writes to standard error.
    fn write_stderr(self, data: [U8]) -> Result(U64, IoError)
    /// Sleeps without observing an earlier wakeup.
    fn sleep(self, seconds: U64, nanos: U32)
    /// Reads the monotonic clock.
    fn monotonic(self) -> Timestamp
    /// Reads the wall clock.
    fn wallclock(self) -> Timestamp
    /// Fills `buffer` with unpredictable bytes. Randomness is essential, so a
    /// host failure terminates through the invariant path instead of a result.
    fn random_bytes(self, buffer: MutSlice(U8))
}

/// Marks a capability whose operations never suspend: waiting blocks the
/// calling OS thread. No type implements both `BlockingIo` and `AsyncIo`.
pub trait BlockingIo {
}

/// Marks a capability whose operations suspend through an executor. Declared
/// in v1 so bounds can name it; the `Evented` implementation arrives with
/// Milestone 9.
pub trait AsyncIo {
}

/// The blocking capability. `main(io: Blocking, ...)` receives one; every
/// `I: type(Io)` wrapper instantiated with it lowers to direct code.
pub type Blocking {
}

impl Io for Blocking {
    // Direct libc calls: open/read/write/lseek/close/fsync/fstat/chmod,
    // rename/unlink/rmdir/mkdir, realpath/opendir/readdir/closedir,
    // read(0)/write(1)/write(2), clock_nanosleep, clock_gettime,
    // getrandom. `EINTR` is retried inside each operation and never
    // surfaces as `Interrupted` or a partial result beyond documented
    // short reads.
}

impl BlockingIo for Blocking {
}
```

### Stream traits

```alder
/// A byte source. `Ok(0)` means end of stream for stream readers. The
/// `copy_to` requirement carries the frozen `files.copy` example shape;
/// its default body copies through a bounded internal buffer and does not
/// flush buffered writers.
pub trait Reader {
    fn read(mut self, buffer: MutSlice(U8)) -> Result(U64, IoError)
    fn copy_to(W: type(Writer), mut self, output: W) -> Result(U64, IoError) {
        // default body: read/write loop with a fixed internal buffer
    }
}

/// A byte sink. `write` may accept fewer bytes than requested; callers that
/// need complete writes use `io.write_all`. `flush` makes buffered writes
/// observable; an unbuffered writer returns `Ok(())`.
pub trait Writer {
    fn write(mut self, data: [U8]) -> Result(U64, IoError)
    fn flush(mut self) -> Result(Unit, IoError)
}

/// A repositionable byte stream. Returns the new absolute position.
pub trait Seek {
    fn seek(mut self, from: SeekFrom) -> Result(U64, IoError)
}

pub enum SeekFrom {
    Start(offset: U64)
    Current(offset: I64)
    End(offset: I64)
}
```

### Buffered readers and writers

```alder
/// Buffers reads from any `Reader`. Copyable value with mutably borrowed
/// methods; the compiler updates a uniquely owned reader in place. The
/// source carries the capability, so a `BufReader` over a `Blocking`-backed
/// source never suspends and a future `Evented`-backed one suspends at the
/// same calls.
pub type BufReader(Source: type(Reader)) {
    // private: source, buffer, position, length
}

impl(Source: type(Reader)) BufReader(Source) {
    pub fn new(source: Source) -> BufReader(Source)
    pub fn with_capacity(capacity: U64, source: Source) -> BufReader(Source)
    pub fn read_line(mut self) -> Result(Option(String), IoError)
    pub fn read_until(mut self, delimiter: U8) -> Result(Option(Vec(U8)), IoError)
    pub fn into_source(take self) -> Source
}

impl(Source: type(Reader)) Reader for BufReader(Source) {
    // Reads from the buffer first, then one `Source` read per refill.
}

/// Buffers writes to any `Writer` that cleans up as an owner.
pub type BufWriter(Sink: type(Writer, Cleanup)) {
    // private: sink, buffer, length
}

impl(Sink: type(Writer, Cleanup)) BufWriter(Sink) {
    pub fn new(sink: Sink) -> BufWriter(Sink)
    pub fn with_capacity(capacity: U64, sink: Sink) -> BufWriter(Sink)
    pub fn into_sink(take self) -> Result(Sink, IoError)
}

impl(Sink: type(Writer, Cleanup)) Writer for BufWriter(Sink) {
    // Writes fill the buffer; a full buffer flushes first. `flush` drains.
}

impl(Sink: type(Writer, Cleanup)) Cleanup for BufWriter(Sink) {
    // Best-effort flush, then cleans the sink. Flush errors are swallowed:
    // callers that must observe them use `into_sink`.
}
```

### Standard streams and text helpers

```alder
/// Standard input. Copyable non-owning view of descriptor 0: the process
/// owns the standard descriptors, so these values never close them.
pub type Stdin(IoType: type(Io)) {
    // private: io
}

impl(IoType: type(Io)) Reader for Stdin(IoType) {
}

/// Standard output, a copyable non-owning view of descriptor 1.
pub type Stdout(IoType: type(Io)) {
    // private: io
}

impl(IoType: type(Io)) Writer for Stdout(IoType) {
    // `flush` returns `Ok(())`: writes go straight to the descriptor.
}

/// Standard error, a copyable non-owning view of descriptor 2.
pub type Stderr(IoType: type(Io)) {
    // private: io
}

impl(IoType: type(Io)) Writer for Stderr(IoType) {
}

pub fn stdin(I: type(Io), io: I) -> Stdin(I)
pub fn stdout(I: type(Io), io: I) -> Stdout(I)
pub fn stderr(I: type(Io), io: I) -> Stderr(I)

/// Writes `text` to standard output. Write errors are ignored: standard
/// output is best-effort for text programs; observe errors through
/// `stdout(io)` and `io.write_all` instead.
pub fn print(I: type(Io), io: I, text: String)
pub fn println(I: type(Io), io: I, text: String)
pub fn eprint(I: type(Io), io: I, text: String)
pub fn eprintln(I: type(Io), io: I, text: String)
```

### Exact helpers and in-memory streams

```alder
/// Reads until `buffer` is full or fails with `InvalidInput` at end of
/// stream. The reader's position after a failed call is unspecified.
pub fn read_exact(R: type(Reader), reader: R, buffer: MutSlice(U8))
    -> Result(Unit, IoError)

/// Writes all of `data` or fails; returns `data.len()` on success.
pub fn write_all(W: type(Writer), writer: W, data: [U8]) -> Result(U64, IoError)

/// Reads to end of stream. Growth uses ordinary checked vector growth and
/// terminates on exhaustion; there is no size limit in v1.
pub fn read_to_end(R: type(Reader), reader: R) -> Result(Vec(U8), IoError)

/// Reader over an owned `Bytes` value. Pure and host-free, so buffered
/// behavior tests never touch the OS.
pub type ByteCursor {
    // private: data, position
}

impl ByteCursor {
    pub fn new(data: Bytes) -> ByteCursor
}

impl Reader for ByteCursor {
}

/// Grows an owned byte vector from writes. Pure and host-free.
pub type ByteSink {
    // private: data
}

impl ByteSink {
    pub fn new() -> ByteSink
    pub fn len(self) -> U64
    pub fn into_bytes(take self) -> Bytes
}

impl Writer for ByteSink {
    // `flush` returns `Ok(())`.
}
```

### `IoError`

```alder
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
    /// and its formatted message. The detail record is shared across the
    /// hosted modules and lives in `std.env`.
    Other(info: PlatformInfo)
}

impl IoError {
    /// Reads the host error number at this point in the calling thread and
    /// maps it like every capability operation does.
    pub fn last() -> IoError
    /// Maps one host error number to an `IoError` category.
    pub fn from_errno(code: I32) -> IoError
}

impl Error for IoError {
    // Root error: the default `cause` is `None`.
}
```

Every hosted error enum implements the prelude `Error` trait (D025; the
shared contract is recorded in [the `Error` section](#the-error-trait)) and
`Display` once the sysroot formatting snapshot lands.

## The `Error` trait

`Error` is a builtin prelude trait like `Cleanup`, settled as decision D025:
`cause` returns a report, and wrapped errors keep typed variant payloads.

```alder
/// A recoverable failure value that reports its wrapped cause. The default
/// `cause` is `None`: root errors implement the trait with an empty impl.
trait Error {
    fn cause(self) -> Option(ErrorReport) {
        return None
    }
}
```

`ErrorReport` is a prelude value holding the displayed text of one error and
of every cause below it, built by
`ErrorReport.of(E: type(Error, Display), error: E)`, which recurses through
`cause`. A module error keeps each wrapped lower-level error as a typed
variant payload that callers reach by `match`; its `cause` implementation
returns `Some(ErrorReport.of(...))` for whichever payload the current variant
wraps, so an error that can wrap several different lower-level error types
still reports its whole chain without trait objects. `program error:` output
prints the report one cause per line, per
[Language Semantics](../language-semantics.md#recoverable-errors).

Hosted errors in this snapshot family are all root errors: `IoError` writes
`impl Error for IoError { }` and inherits the default, as do `PathError`,
`EnvError`, and `ProcessError`. The compiler recognition commit for `Error`
and `ErrorReport` is available: `core.error` is prelude-loaded, so these empty
implementations resolve without an explicit import.

## Contracts

- Every operation that waits on the host or observes host nondeterminism takes
  the capability as an ordinary parameter or holds the capability value it was
  constructed with. There is no global I/O context.
- Every generic wrapper in this snapshot and in `std.fs`, `std.process`,
  `std.time`, and `std.random` is written once against `I: type(Io)`; a
  `BlockingIo` instantiation lowers to direct code and a future `AsyncIo`
  instantiation suspends at the same calls.
- `Blocking` never suspends. Its operations perform the host call directly;
  `EINTR` is retried inside the operation, so callers never see interrupted
  partial results.
- `Reader.read` may return fewer bytes than requested; `Ok(0)` is end of
  stream. `Writer.write` may accept fewer bytes than requested. Short results
  are values, not errors.
- `read_exact` and `write_all` are the complete-transfer forms. `copy_to`
  comes from the `Reader` trait, copies only to end of stream, does not flush
  buffered writers, and reports the copied length.
- Host handles are never forgeable values. `HostFile` and `HostDirectory` are
  affine owners with private fields that only a capability implementation can
  construct; they cannot be copied, so a closed handle can never alias a
  descriptor number another file reuses. `io.close` and `io.close_directory`
  consume the handle, and cleanup closes best-effort with `io.close` and
  `io.close_directory` named as the observing releases. Every owner of a host
  handle (`File(I)`, `Entries(I)`, and the process pipe ends in
  `std.process`) holds exactly one and closes it once.
- `BufReader` and `BufWriter` are ordinary copyable values; mutation happens
  through exclusively borrowed method calls and the compiler updates a
  uniquely owned buffer in place. `BufWriter.cleanup` flushes best-effort and
  cannot report an error; `into_sink` is the observing release.
- `BufWriter` requires `Sink: type(Writer, Cleanup)`, so it cannot wrap
  `ByteSink`, which is a plain value, not an owner. It wraps owners such as
  `File(I)` and the `std.process` pipe ends; `ByteSink` is written through
  `io.write_all` directly.
- Standard streams are process-owned descriptors. `Stdin`, `Stdout`, and
  `Stderr` values are copyable views that never close their descriptor, and no
  number of `stdout(io)` calls creates a second owner.
- `print`/`println`/`eprint`/`eprintln` ignore write errors by contract.
- `FileStat.mode` is POSIX-flavored detail; the portable query lives in
  `std.fs.Permissions`. `Timestamp` differences on the monotonic clock are the
  only defined monotonic values.
- Error categories are portable across tier-1 targets; `Other` carries the
  host detail. No operation returns a bare host error number.
- Failed writes are never reported as success because fallback cleanup could
  not report an error: cleanup that swallows an error is documented at the
  swallowing method (`BufWriter.cleanup`, `File.cleanup`), and the observing
  release is named at every such type.
- The host never enumerates anything into a public result in directory order
  from this module; `std.fs` documents host order and provides the sorted
  form.

## Example

The example below is the complete content that lands as
`examples/std.io-v1.al` with the implementation commit. It exercises buffering,
exact helpers, in-memory streams, and standard error without depending on the
filesystem, and returns a deterministic checksum.

```alder
module hello.std_io_example

import std.io

// The executable std.io v1 snapshot example. Every stage contributes a
// deterministic share of the returned checksum, so a changed result flags
// changed behavior. The example stays in memory: no file, no host state.

pub fn std_io_example() -> U64 {
    var total: U64 = 0

    // Buffered reads over an in-memory cursor.
    let cursor = io.ByteCursor.new("alpha\nbeta\ngamma")
    var reader = io.BufReader.new(cursor)
    var index: U64 = 0
    var done = false
    while !done {
        match reader.read_until(10) {
            Some(line) => {
                index = index + 1
                var at: U64 = 0
                while at < line.len() {
                    total = total + line[at].to_u64()
                    at = at + 1
                }
                total = total + line.len()
            }
            None => { done = true }
        }
    }
    total = total + index * 100

    // Complete writes through the exact helper into an in-memory sink.
    var sink = io.ByteSink.new()
    let written = io.write_all(sink, "hello")
    total = total + written
    let copied = io.write_all(sink, "world")
    total = total + copied
    let bytes = sink.into_bytes()
    let replay = io.ByteCursor.new(bytes)
    var verify: Array(U8, 10) = [104, 101, 108, 108, 111, 119, 111, 114, 108, 100]
    var at: U64 = 0
    var same = true
    while at < 10 {
        let one = [0]
        let chunk = io.read_exact(replay, one.slice_mut(0, 1))
        match chunk {
            Ok(_) => {}
            Err(_) => { same = false }
        }
        if one[0] != verify[at] { same = false }
        at = at + 1
    }
    if same { total = total + 10000 }

    return total
}
```

## Dependencies and sequencing

- Integer conversions in the example use the settled builtin surface: total `to_u64()` for all-fitting pairs (`U8`/`U32` into `U64`), with `to_u64_checked()` available where a value may not fit; the methods land with the sysroot thread's numeric surface after the String/Bytes byte work.
- Needs the C-binding thread's binding blocks, raw `c.*` types, `unsafe c`
  calls, and checked raw-integer conversions, plus an errno read for
  `IoError.last` (requested separately).
- Needs the D024 constraint syntax (`BufReader(Source: type(Reader))` and the
  other constrained parameters) and the generic implementation parameter
  list (D024 extension, `impl(Source: type(Reader)) Reader for
  BufReader(Source)`), both decided and landing with the constraint-syntax
  thread before this module's implementation commit.
- A probe on main confirmed trait default bodies calling their own trait's
  requirements, including generic methods such as `Reader.copy_to`; the
  default lands as designed and no free `io.copy` bridge is needed.
- Needs the sysroot thread's `String` byte access for `print`/`read_line` and
  `OsString` from `std.path` (this snapshot family).
- The example avoids string building, interpolation, and `while let` so it
  compiles on the current S0 boundary.
