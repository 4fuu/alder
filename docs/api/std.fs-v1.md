# `std.fs` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for filesystem access. It is normative
together with the executable example
[`examples/std.fs-v1.al`](examples/std.fs-v1.al), which lands in the module's
implementation commit: the docs example runner resolves sysroot modules, so
the example file cannot precede the module it imports. The module lives at
`<sysroot>/std/fs.al`.

Snapshot v1 covers the affine `File` with `Cleanup`, metadata, directory
iteration in host order plus the byte-sorted deterministic form, copy,
rename, remove, canonicalize, permissions query and replace, and temporary
files and directories that clean up after themselves. File and directory
operations return `IoError` (the shared OS-layer error of `std.io`, as fixed
by the `files.copy` design example); path-shape failures are unreachable here
because `Path` construction is checked.

## Signatures

### Affine files

```alder
module std.fs

import std.io
import std.path { OsString, Path }
import std.time { SystemTime }

/// Options for `File.open_options`. Construct with `Options.read` or
/// `Options.write` and adjust fields on a `var` binding.
pub type Options {
    read: Bool
    write: Bool
    append: Bool
    truncate: Bool
    create: Bool
    create_new: Bool
}

impl Options {
    /// Read-only.
    pub fn read() -> Options
    /// Write, create, and truncate.
    pub fn write() -> Options
}

/// One open file. Affine: exactly one owner closes it exactly once, through
/// `finish`, `keep`, or cleanup.
pub type File(IoType: type(io.Io)) {
    // private: io, handle (one affine io.HostFile), path
}

impl(IoType: type(io.Io)) File(IoType) {
    /// Opens the file for reading.
    pub fn open(I: type(io.Io), io: I, path: Path) -> Result(File(I), io.IoError)
    /// Creates or truncates the file for writing.
    pub fn create(I: type(io.Io), io: I, path: Path) -> Result(File(I), io.IoError)
    /// Opens for appending, creating the file when absent.
    pub fn append(I: type(io.Io), io: I, path: Path) -> Result(File(I), io.IoError)
    /// Opens with explicit flags.
    pub fn open_options(I: type(io.Io), io: I, path: Path, options: Options)
        -> Result(File(I), io.IoError)
    /// Metadata of this file.
    pub fn metadata(mut self) -> Result(Metadata, io.IoError)
    /// Replaces the file's permission mode.
    pub fn set_permissions(mut self, permissions: Permissions)
        -> Result(Unit, io.IoError)
    /// Flushes host buffers to durable storage.
    pub fn sync_all(mut self) -> Result(Unit, io.IoError)
    /// Closes the file and reports host close errors. Releases the owner on
    /// both arms: after `Err` the file is closed.
    pub fn finish(take self) -> Result(Unit, io.IoError)
    /// Disarms cleanup and returns the open file.
    pub fn keep(take self) -> File(I)
}

impl(IoType: type(io.Io)) io.Reader for File(IoType) {
    // Reads through the capability from the current position.
}

impl(IoType: type(io.Io)) io.Writer for File(IoType) {
    // Writes through the capability. `flush` returns `Ok(())`; durability
    // is `sync_all`.
}

impl(IoType: type(io.Io)) io.Seek for File(IoType) {
}

impl(IoType: type(io.Io)) Cleanup for File(IoType) {
    // Closes the descriptor. Close errors are swallowed by contract: the
    // observing release is `finish`.
}
```

### Whole-file operations

```alder
impl fs {
    /// Reads the whole file.
    pub fn read(I: type(io.Io), io: I, path: Path) -> Result(Vec(U8), io.IoError)
    /// Reads the whole file as text; `InvalidInput` when the bytes are not
    /// UTF-8.
    pub fn read_text(I: type(io.Io), io: I, path: Path) -> Result(String, io.IoError)
    /// Creates or truncates `path` and writes all of `data`.
    pub fn write(I: type(io.Io), io: I, path: Path, data: [U8])
        -> Result(Unit, io.IoError)
    /// Creates or truncates `path` and writes the text.
    pub fn write_text(I: type(io.Io), io: I, path: Path, text: String)
        -> Result(Unit, io.IoError)
    /// Metadata of `path`, following symlinks.
    pub fn metadata(I: type(io.Io), io: I, path: Path) -> Result(Metadata, io.IoError)
    /// Resolves symlinks and returns the absolute canonical path.
    pub fn canonicalize(I: type(io.Io), io: I, path: Path) -> Result(Path, io.IoError)
    /// Renames `from` to `to` in place.
    pub fn rename(I: type(io.Io), io: I, from: Path, to: Path)
        -> Result(Unit, io.IoError)
    /// Removes the file or symlink at `path`.
    pub fn remove_file(I: type(io.Io), io: I, path: Path) -> Result(Unit, io.IoError)
    /// Removes the empty directory at `path`; `DirectoryNotEmpty` otherwise.
    pub fn remove_dir(I: type(io.Io), io: I, path: Path) -> Result(Unit, io.IoError)
    /// Removes `path` and everything under it. Symbolic links inside are
    /// unlinked, never followed.
    pub fn remove_dir_all(I: type(io.Io), io: I, path: Path)
        -> Result(Unit, io.IoError)
    /// Creates one directory.
    pub fn make_dir(I: type(io.Io), io: I, path: Path) -> Result(Unit, io.IoError)
}
```

### Directory iteration

```alder
/// One entry of a listing: the exact name bytes and the host-reported kind.
pub type Entry {
    name: OsString
    kind: io.EntryKind
}

/// A listing in host order. Affine: cleanup closes the listing.
pub type Entries(IoType: type(io.Io)) {
    // private: io, directory (one affine io.HostDirectory)
}

impl(IoType: type(io.Io)) Entries(IoType) {
    /// The directory being listed.
    pub fn path(self) -> Path
    /// The next entry in host order, `None` at the end. Host order is
    /// documented as nondeterministic; deterministic tools use
    /// `read_dir_sorted`.
    pub fn next(mut self) -> Result(Option(Entry), io.IoError)
    /// Closes the listing and reports host close errors. Releases on both
    /// arms.
    pub fn close(take self) -> Result(Unit, io.IoError)
}

impl(IoType: type(io.Io)) Cleanup for Entries(IoType) {
    // Closes the listing; close errors are swallowed. The observing
    // release is `close`.
}

impl fs {
    /// Lists `path` in host order.
    pub fn read_dir(I: type(io.Io), io: I, path: Path)
        -> Result(Entries(I), io.IoError)
    /// Lists `path` fully and returns the entries sorted by exact name
    /// bytes. Deterministic by construction; never depends on host order.
    pub fn read_dir_sorted(I: type(io.Io), io: I, path: Path)
        -> Result(Vec(Entry), io.IoError)
}
```

### Metadata and permissions

```alder
pub type Metadata {
    kind: io.EntryKind
    length: U64
    permissions: Permissions
    modified: SystemTime
}

/// Portable permission query. On POSIX targets these are the owner bits;
/// other targets map best-effort and document the mapping.
pub type Permissions {
    readable: Bool
    writable: Bool
    executable: Bool
}
```

### Temporary files and directories

```alder
/// The system temporary root (`TMPDIR` when set, the platform default
/// otherwise).
pub fn temp_root(I: type(io.Io), io: I) -> Result(Path, io.IoError)

/// One exclusive temporary file. Affine: cleanup closes the file and
/// removes it.
pub type TempFile(IoType: type(io.Io)) {
    // private: file, path
}

impl(IoType: type(io.Io)) TempFile(IoType) {
    /// Creates a file with a fresh unique name under the temporary root.
    /// The name never exists beforehand; creation is retry-until-unique.
    pub fn new(I: type(io.Io), io: I, prefix: String)
        -> Result(TempFile(I), io.IoError)
    /// The file's path.
    pub fn path(self) -> Path
    /// Disarms removal and returns the open file. The file keeps its path;
    /// the caller now owns its lifetime.
    pub fn keep(take self) -> File(I)
}

impl(IoType: type(io.Io)) Cleanup for TempFile(IoType) {
    // Closes the file and removes it. Errors on either step are swallowed:
    // the observing releases are `keep` plus `File.finish`, and
    // `fs.remove_file`.
}

/// One exclusive temporary directory. Affine: cleanup removes the whole
/// tree, unlinking symbolic links without following them.
pub type TempDir(IoType: type(io.Io)) {
    // private: path
}

impl(IoType: type(io.Io)) TempDir(IoType) {
    /// Creates a directory with a fresh unique name under the temporary
    /// root.
    pub fn new(I: type(io.Io), io: I, prefix: String)
        -> Result(TempDir(I), io.IoError)
    /// The directory's path.
    pub fn path(self) -> Path
    /// Disarms removal and returns the path.
    pub fn keep(take self) -> Path
}

impl(IoType: type(io.Io)) Cleanup for TempDir(IoType) {
    // Removes the tree best-effort; errors are swallowed. The observing
    // release is `keep` plus `fs.remove_dir_all`.
}
```

## Contracts

- Every operation takes the capability; all generic surfaces are written once
  against `I: type(io.Io)`, so `Blocking` instantiations lower to direct code
  and a future `AsyncIo` instantiation suspends at the same calls.
- `File` is affine with `Cleanup`; `finish` is the error-observing close and
  releases on both arms, so a failed close never leaves a second owner.
  Every `File` owns exactly one affine `io.HostFile` handle, and every
  `Entries` owns exactly one `io.HostDirectory`; the handles are closed
  once through `io.close`/`io.close_directory` or best-effort cleanup,
  and nothing forgeable or copyable ever reaches a caller.
- Names of directory entries are exact host bytes in `OsString` values;
  nothing in this module assumes they are text. `Entry` never contains a
  path: `directory.join(Path.from_os(entry.name))` builds one when needed.
- `read_dir` returns host order and says so; `read_dir_sorted` is the
  deterministic form every tool test or snapshot diff must use. No test may
  depend on host order.
- `copy_to` comes from the `Reader` trait contract in `std.io` (the
  `files.copy` design example shape: open, `copy_to`, `finish`); a failed
  copy leaves the destination contents unspecified and reports the `IoError`.
- Whole-file helpers open, transfer, and close internally; a failure on any
  step reports `IoError` and leaves the target's contents unspecified on
  write failures.
- Temporary names come from the capability's randomness; creation retries on
  collision and never overwrites an existing path (`create_new` semantics).
- Cleanup that swallows errors is documented at each swallowing cleanup, and
  each such type names its observing release.
- Metadata `modified` uses wall-clock `SystemTime`; the timestamp may go
  backwards, and nothing here treats it as ordered.
- Tests run in temporary directories created through this module, never in a
  shared host location, and never depend on enumeration order.

## Example

The example below is the complete content that lands as
`examples/std.fs-v1.al` with the implementation commit. It works inside a
`TempDir` so the run is isolated from the host and returns a deterministic
checksum.

```alder
module hello.std_fs_example

import std.fs
import std.io
import std.path

// The executable std.fs v1 snapshot example. Everything happens inside one
// temporary directory that cleanup removes; the checksum is deterministic.

// Byte equality between text and a literal.
// uses == once Eq equality lands
fn text_is(left: String, right: String) -> Bool {
    if left.len() != right.len() { return false }
    var at: U64 = 0
    while at < left.len() {
        if left.byte(at) != right.byte(at) { return false }
        at = at + 1
    }
    return true
}

// Option equality between two host strings.
// uses == once Eq equality lands
fn name_opt_eq(left: Option(OsString), right: Option(OsString)) -> Bool {
    match left {
        Some(one) => {
            match right {
                Some(two) => {
                    if one.len() != two.len() { return false }
                    var at: U64 = 0
                    while at < one.len() {
                        if one.byte(at) != two.byte(at) { return false }
                        at = at + 1
                    }
                    return true
                }
                None => { return false }
            }
        }
        None => {
            match right {
                Some(_) => { return false }
                None => { return true }
            }
        }
    }
}

// The example inputs are fixed, so any early failure aborts with zero.
pub fn std_fs_example(io: io.Blocking) -> U64 {
    var total: U64 = 0
    let room = match fs.TempDir.new(io, "alder-fs-example") {
        Ok(value) => { value }
        Err(_) => { return 0 }
    }
    let base = room.path()

    // Write, read back, and confirm exact bytes.
    let note = match path.Path.parse("note.txt") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    match fs.write_text(io, note, "alder") {
        Ok(_) => {}
        Err(_) => { return 0 }
    }
    let text = match fs.read_text(io, note) {
        Ok(value) => { value }
        Err(_) => { return 0 }
    }
    // uses == once Eq equality lands
    if text_is(text, "alder") { total = total + 1 }

    // The frozen files.copy shape: open, copy_to, finish.
    let source = match path.Path.parse("source.bin") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    let raw: Array(U8, 5) = [1, 2, 3, 4, 5]
    match fs.write(io, source, raw.slice(0, 5)) {
        Ok(_) => {}
        Err(_) => { return 0 }
    }
    let target = match path.Path.parse("target.bin") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    match fs.File.open(io, source) {
        Ok(opened) => {
            using input = opened
            match fs.File.create(io, target) {
                Ok(created) => {
                    var output = created
                    let copied = match input.copy_to(output) {
                        Ok(value) => { value }
                        Err(_) => { return 0 }
                    }
                    match output.finish() {
                        Ok(_) => { total = total + copied }
                        Err(_) => { return 0 }
                    }
                }
                Err(_) => { return 0 }
            }
        }
        Err(_) => { return 0 }
    }

    // Deterministic sorted iteration over a fixed set of names.
    let c_name = match path.Path.parse("c.txt") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    let a_name = match path.Path.parse("a.txt") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    let b_name = match path.Path.parse("b.txt") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    match fs.write_text(io, c_name, "3") {
        Ok(_) => {}
        Err(_) => { return 0 }
    }
    match fs.write_text(io, a_name, "1") {
        Ok(_) => {}
        Err(_) => { return 0 }
    }
    match fs.write_text(io, b_name, "2") {
        Ok(_) => {}
        Err(_) => { return 0 }
    }
    let sorted = match fs.read_dir_sorted(io, base) {
        Ok(value) => { value }
        Err(_) => { return 0 }
    }
    total = total + sorted.len() * 100
    var sum: U64 = 0
    var at: U64 = 0
    while at < sorted.len() {
        let name = sorted[at].name
        let first = name.len()
        sum = sum + first
        at = at + 1
    }
    total = total + sum * 10

    // Canonicalize inside the temporary directory: the resolved suffix and
    // existence are checked, the host-specific prefix is not.
    let canonical = match fs.canonicalize(io, note) {
        Ok(value) => { value }
        Err(_) => { return 0 }
    }
    // uses == once Eq equality lands
    if name_opt_eq(canonical.file_name(), note.file_name()) { total = total + 1 }

    // Rename and remove.
    let moved = match path.Path.parse("moved.bin") {
        Ok(value) => { base.join(value) }
        Err(_) => { return 0 }
    }
    match fs.rename(io, target, moved) {
        Ok(_) => {}
        Err(_) => { return 0 }
    }
    match fs.remove_file(io, moved) {
        Ok(_) => {}
        Err(_) => { return 0 }
    }

    // Metadata query on a fresh write.
    let meta = match fs.metadata(io, note) {
        Ok(value) => { value }
        Err(_) => { return 0 }
    }
    match meta.kind {
        File => { total = total + 1 }
        Directory => { total = total - 100 }
        Symlink => { total = total - 100 }
        Other => { total = total - 100 }
        Unknown => { total = total - 100 }
    }
    if meta.permissions.readable { total = total + 1 }

    // Cleanup removes the whole tree here.
    return total
}
```

## Dependencies and sequencing

- Integer conversions in the example use the settled builtin surface: total `to_u64()` for all-fitting pairs, with `to_u64_checked()` available where a value may not fit; the methods land with the sysroot thread's numeric surface after the String/Bytes byte work.
- Builds on `std.io` (capability traits, `IoError`, `Reader`), `std.path`
  (`Path`, `OsString`), and `std.env`.
- Needs the sysroot thread's `String` byte operations for `read_text`/
  `write_text` and their UTF-8 check.
- Needs the generic implementation parameter list (D024 extension, decided)
  for the `Cleanup` impls over `Entries(I)`, `TempFile(I)`, and `TempDir(I)`
  and the trait impls over `File(I)`; the syntax lands with the
  constraint-syntax thread before the `std.io` commit.
- Needs the C-binding thread's checked raw-integer conversions for handle and
  mode-bit plumbing inside the capability implementation.
