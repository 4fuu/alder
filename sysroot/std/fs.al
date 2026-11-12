module std.fs

import std.io { EntryKind, FileMode, FileStat, HostDirectory, HostFile, Io, IoError, Reader, Seek, SeekFrom, Writer, read_to_end, write_all }
import std.env
import std.path { OsString, Path }
import std.text
import std.time { SystemTime }

/// Options for opening a file. Construct with `Options.read` or
/// `Options.write` and adjust fields on a `var` binding.
pub type Options {
    pub read: Bool
    pub write: Bool
    pub append: Bool
    pub truncate: Bool
    pub create: Bool
    pub create_new: Bool
}

impl Options {
    /// Read-only.
    fn read() -> Options {
        return Options(read: true, write: false, append: false, truncate: false, create: false, create_new: false)
    }

    /// Write, create, and truncate.
    fn write() -> Options {
        return Options(read: false, write: true, append: false, truncate: true, create: true, create_new: false)
    }
}

/// Portable permission query. On POSIX targets these are the owner bits;
/// other targets map best-effort and document the mapping.
pub type Permissions {
    pub readable: Bool
    pub writable: Bool
    pub executable: Bool
}

/// One open file. Affine: exactly one owner closes it exactly once through
/// `finish`, `keep`, or cleanup.
pub type File(IoType: type(Io)) {
    io: IoType
    handle: HostFile
    path: Path
}

/// Opens the file for reading. The generic implementation parameter of
/// `File` cannot be inferred at an associated call, so opening is a module
/// function (`fs.open`) rather than `File.open`.
pub fn open(I: type(Io), io: I, path: Path) -> Result(File(I), IoError) {
    return open_options(io, path, Options(read: true, write: false, append: false, truncate: false, create: false, create_new: false))
}

/// Creates or truncates the file for writing.
pub fn create(I: type(Io), io: I, path: Path) -> Result(File(I), IoError) {
    return open_options(io, path, Options(read: true, write: true, append: false, truncate: true, create: true, create_new: false))
}

/// Opens for appending, creating the file when absent.
pub fn append(I: type(Io), io: I, path: Path) -> Result(File(I), IoError) {
    return open_options(io, path, Options(read: false, write: true, append: true, truncate: false, create: true, create_new: false))
}

/// Opens a host handle with explicit flags. File and TempFile share it so a
/// taken temporary owner never nests one consumed field inside another.
fn open_handle(I: type(Io), io: I, path: Path, options: Options) -> Result(HostFile, IoError) {
    let mode = FileMode(read: options.read, write: options.write, append: options.append, truncate: options.truncate, create: options.create, create_new: options.create_new)
    return io.open(path, mode)
}

/// Opens with explicit flags.
pub fn open_options(I: type(Io), io: I, path: Path, options: Options) -> Result(File(I), IoError) {
    let handle = try open_handle(io, path, options)
    return Ok(File(io: io, handle: handle, path: path))
}

impl(IoType: type(Io)) File(IoType) {
    fn metadata(mut self) -> Result(Metadata, IoError) {
        let stat = try self.io.stat(self.handle)
        return Ok(metadata_of(stat))
    }

    fn set_permissions(mut self, permissions: Permissions) -> Result(Unit, IoError) {
        var mode: U32 = 0
        if permissions.readable { mode = mode + 256 }
        if permissions.writable { mode = mode + 128 }
        if permissions.executable { mode = mode + 64 }
        return self.io.set_permissions(self.handle, mode)
    }

    fn sync_all(mut self) -> Result(Unit, IoError) {
        return self.io.sync(self.handle)
    }

    fn finish(take self) -> Result(Unit, IoError) {
        let handle = self.handle
        return self.io.close(handle)
    }

    fn keep(take self) -> File(IoType) {
        return self
    }
}

impl(IoType: type(Io)) Reader for File(IoType) {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.io.read(self.handle, buffer)
    }
}

impl(IoType: type(Io)) Writer for File(IoType) {
    fn write(mut self, data: [U8]) -> Result(U64, IoError) {
        return self.io.write(self.handle, data)
    }

    fn flush(mut self) -> Result(Unit, IoError) {
        return Ok(())
    }
}

impl(IoType: type(Io)) Seek for File(IoType) {
    fn seek(mut self, from: SeekFrom) -> Result(U64, IoError) {
        return self.io.seek(self.handle, from)
    }
}

impl(IoType: type(Io)) Cleanup for File(IoType) {
    fn cleanup(take self) -> Unit {
        let closed = self.io.close(self.handle)
        return
    }
}

/// One file's metadata. `modified` is signed wall-clock time, so pre-1970
/// modification times round-trip exactly.
pub type Metadata {
    pub kind: EntryKind
    pub length: U64
    pub permissions: Permissions
    pub modified: SystemTime
}

fn metadata_of(stat: FileStat) -> Metadata {
    return Metadata(kind: stat.kind, length: stat.size, permissions: permissions_of(stat.mode), modified: SystemTime.from_unix(stat.modified.seconds, stat.modified.nanos))
}

fn permissions_of(mode: U32) -> Permissions {
    let owner = mode % 512
    return Permissions(readable: (owner / 256) % 2 == 1, writable: (owner / 128) % 2 == 1, executable: (owner / 64) % 2 == 1)
}

fn copy_text_bytes(value: String) -> Vec(U8) {
    let data = value.to_bytes()
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        out.push(data.byte(at))
        at = at + 1
    }
    return out
}

/// Reads the whole file.
pub fn read(I: type(Io), io: I, path: Path) -> Result(Vec(U8), IoError) {
    let file = try open(io, path)
    let data = read_to_end(file)
    let finished = file.finish()
    match data {
        Ok(bytes) => {
            match finished {
                Ok(_) => { return Ok(bytes) }
                Err(error) => { return Err(error) }
            }
        }
        Err(error) => { return Err(error) }
    }
    return Err(IoError.InvalidInput)
}

/// Reads the whole file as text; `InvalidInput` when the bytes are not UTF-8.
pub fn read_text(I: type(Io), io: I, path: Path) -> Result(String, IoError) {
    let data = try read(io, path)
    return match text.from_utf8(data.slice(0, data.len()).to_bytes()) {
        Ok(value) => Ok(value)
        Err(_) => Err(IoError.InvalidInput)
    }
}

/// Creates or truncates `path` and writes all of `data`.
pub fn write(I: type(Io), io: I, path: Path, data: [U8]) -> Result(Unit, IoError) {
    let file = try create(io, path)
    let written = write_all(file, data)
    let finished = file.finish()
    match written {
        Ok(count) => {
            match finished {
                Ok(_) => { return Ok(()) }
                Err(error) => { return Err(error) }
            }
        }
        Err(error) => { return Err(error) }
    }
    return Err(IoError.InvalidInput)
}

/// Creates or truncates `path` and writes the text.
pub fn write_text(I: type(Io), io: I, path: Path, value: String) -> Result(Unit, IoError) {
    let bytes = copy_text_bytes(value)
    return write(io, path, bytes.slice(0, bytes.len()))
}

/// Metadata of `path`, following symlinks.
pub fn metadata(I: type(Io), io: I, path: Path) -> Result(Metadata, IoError) {
    let stat = try io.stat_path(path)
    return Ok(metadata_of(stat))
}

/// Resolves symlinks and returns the absolute canonical path.
pub fn canonicalize(I: type(Io), io: I, path: Path) -> Result(Path, IoError) {
    return io.canonicalize(path)
}

/// Renames `from` to `to` in place.
pub fn rename(I: type(Io), io: I, from: Path, to: Path) -> Result(Unit, IoError) {
    return io.rename(from, to)
}

/// Removes the file or symlink at `path`.
pub fn remove_file(I: type(Io), io: I, path: Path) -> Result(Unit, IoError) {
    return io.remove(path)
}

/// Removes the empty directory at `path`.
pub fn remove_dir(I: type(Io), io: I, path: Path) -> Result(Unit, IoError) {
    return io.remove_directory(path)
}

/// Creates one directory.
pub fn make_dir(I: type(Io), io: I, path: Path) -> Result(Unit, IoError) {
    return io.make_directory(path)
}

/// One entry of a listing: the exact name bytes and the host-reported kind.
pub type Entry {
    pub name: OsString
    pub kind: EntryKind
}

/// A listing in host order. Affine: cleanup closes the listing.
pub type Entries(IoType: type(Io)) {
    io: IoType
    directory: HostDirectory
    location: Path
}

impl(IoType: type(Io)) Entries(IoType) {
    fn path(self) -> Path {
        return self.location
    }

    fn next(mut self) -> Result(Option(Entry), IoError) {
        var reading = true
        while reading {
            let item = try self.io.read_directory(self.directory)
            match item {
                Some(value) => {
                    if !is_dot_name(value.name) {
                        return Ok(Some(Entry(name: value.name, kind: value.kind)))
                    }
                }
                None => { return Ok(None) }
            }
        }
        return Ok(None)
    }

    fn close(take self) -> Result(Unit, IoError) {
        let directory = self.directory
        return self.io.close_directory(directory)
    }
}

impl(IoType: type(Io)) Cleanup for Entries(IoType) {
    fn cleanup(take self) -> Unit {
        let closed = self.io.close_directory(self.directory)
        return
    }
}

fn is_dot_name(name: OsString) -> Bool {
    let data = name.to_bytes()
    if data.len() == 1 { return data.byte(0) == 46 }
    if data.len() == 2 { return data.byte(0) == 46 && data.byte(1) == 46 }
    return false
}

fn entry_less(left: Entry, right: Entry) -> Bool {
    let a = left.name.to_bytes()
    let b = right.name.to_bytes()
    var at: U64 = 0
    while at < a.len() && at < b.len() {
        if a.byte(at) < b.byte(at) { return true }
        if a.byte(at) > b.byte(at) { return false }
        at = at + 1
    }
    return a.len() < b.len()
}

/// Lists `path` in host order.
pub fn read_dir(I: type(Io), io: I, path: Path) -> Result(Entries(I), IoError) {
    let directory = try io.open_directory(path)
    return Ok(Entries(io: io, directory: directory, location: path))
}

/// Lists `path` fully and returns entries sorted by exact name bytes.
pub fn read_dir_sorted(I: type(Io), io: I, path: Path) -> Result(Vec(Entry), IoError) {
    var entries: Vec(Entry) = Vec.new(Entry)
    using listing = try read_dir(io, path)
    var reading = true
    while reading {
        let item = try listing.next()
        match item {
            Some(value) => { entries.push(value) }
            None => { reading = false }
        }
    }
    try listing.close()
    var at: U64 = 1
    while at < entries.len() {
        let current = entries[at]
        var slot = at
        while slot > 0 && entry_less(current, entries[slot - 1]) {
            entries[slot] = entries[slot - 1]
            slot = slot - 1
        }
        entries[slot] = current
        at = at + 1
    }
    return Ok(entries)
}

/// Removes `path` and everything under it. Symbolic links are unlinked and
/// never followed. The walk has a TOCTOU window: no openat/unlinkat in v1, so
/// a component replaced between lstat and unlink could redirect the call.
pub fn remove_dir_all(I: type(Io), io: I, path: Path) -> Result(Unit, IoError) {
    let root = try io.lstat(path)
    if root.kind == EntryKind.Symlink { return remove_file(io, path) }
    if root.kind != EntryKind.Directory { return remove_file(io, path) }
    using listing = try read_dir(io, path)
    var reading = true
    while reading {
        let item = try listing.next()
        match item {
            Some(value) => {
                let child = path.join(Path.from_os(value.name))
                var recurse = value.kind == EntryKind.Directory
                if value.kind == EntryKind.Unknown {
                    let info = try io.lstat(child)
                    recurse = info.kind == EntryKind.Directory
                }
                if recurse {
                    try remove_dir_all(io, child)
                } else {
                    try remove_file(io, child)
                }
            }
            None => { reading = false }
        }
    }
    try listing.close()
    return remove_dir(io, path)
}

/// The system temporary root (`TMPDIR` when set, `/tmp` otherwise).
pub fn temp_root(I: type(Io), io: I) -> Result(Path, IoError) {
    let name = env_name("TMPDIR")
    match name {
        Some(value) => {
            match env.get(value) {
                Some(found) => { return Ok(Path.from_os(found)) }
                None => {}
            }
        }
        None => {}
    }
    return match Path.parse("/tmp") {
        Ok(value) => Ok(value)
        Err(_) => Err(IoError.InvalidInput)
    }
}

fn env_name(value: String) -> Option(OsString) {
    match OsString.parse(value) {
        Ok(parsed) => { return Some(parsed) }
        Err(_) => { return None }
    }
    return None
}

fn temp_path(I: type(Io), io: I, root: Path, prefix: String) -> Result(Path, IoError) {
    var raw: Array(U8, 16) = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    io.random_bytes(raw.slice_mut(0, 16))
    let digits: Array(U8, 16) = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102]
    var name: Vec(U8) = copy_text_bytes(prefix)
    name.push(45)
    var at: U64 = 0
    while at < 16 {
        let one = raw[at]
        name.push(digits[(one / 16).to_u64()])
        name.push(digits[(one % 16).to_u64()])
        at = at + 1
    }
    return match OsString.from_bytes(name.slice(0, name.len()).to_bytes()) {
        Ok(value) => Ok(root.join(Path.from_os(value)))
        Err(_) => Err(IoError.InvalidInput)
    }
}

/// One exclusive temporary file. Affine: cleanup closes the file and removes
/// it. Creation retries a fresh random name until the host accepts it.
pub type TempFile(IoType: type(Io)) {
    io: IoType
    handle: HostFile
    location: Path
}

pub fn temp_file(I: type(Io), io: I, prefix: String) -> Result(TempFile(I), IoError) {
    let root = try temp_root(io)
    var attempt: U64 = 0
    while attempt < 16 {
        let path = try temp_path(io, root, prefix)
        let made = open_handle(io, path, Options(read: true, write: true, append: false, truncate: false, create: false, create_new: true))
        match made {
            Ok(handle) => { return Ok(TempFile(io: io, handle: handle, location: path)) }
            Err(error) => {
                match error {
                    AlreadyExists => {}
                    _ => { return Err(error) }
                }
            }
        }
        attempt = attempt + 1
    }
    return Err(IoError.AlreadyExists)
}

impl(IoType: type(Io)) TempFile(IoType) {
    fn path(self) -> Path {
        return self.location
    }

    fn keep(take self) -> File(IoType) {
        let handle = self.handle
        let io = self.io
        let location = self.location
        return File(io: io, handle: handle, path: location)
    }
}

impl(IoType: type(Io)) Cleanup for TempFile(IoType) {
    fn cleanup(take self) -> Unit {
        let handle = self.handle
        let closed = self.io.close(handle)
        let removed = remove_file(self.io, self.location)
        return
    }
}


/// One exclusive temporary directory. Affine: cleanup removes the tree,
/// unlinking symbolic links without following them.
pub type TempDir(IoType: type(Io)) {
    io: IoType
    location: Path
}

pub fn temp_dir(I: type(Io), io: I, prefix: String) -> Result(TempDir(I), IoError) {
    let root = try temp_root(io)
    var attempt: U64 = 0
    while attempt < 16 {
        let path = try temp_path(io, root, prefix)
        let made = make_dir(io, path)
        match made {
            Ok(_) => { return Ok(TempDir(io: io, location: path)) }
            Err(error) => {
                match error {
                    AlreadyExists => {}
                    _ => { return Err(error) }
                }
            }
        }
        attempt = attempt + 1
    }
    return Err(IoError.AlreadyExists)
}

impl(IoType: type(Io)) TempDir(IoType) {
    fn path(self) -> Path {
        return self.location
    }

    fn keep(take self) -> Path {
        return self.location
    }
}

impl(IoType: type(Io)) Cleanup for TempDir(IoType) {
    fn cleanup(take self) -> Unit {
        let removed = remove_dir_all(self.io, self.location)
        return
    }
}
