module std.fs

import std.io { EntryKind, FileMode, FileStat, HostFile, Io, IoError, Reader, Seek, SeekFrom, Writer, read_to_end, write_all }
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

/// Opens with explicit flags.
pub fn open_options(I: type(Io), io: I, path: Path, options: Options) -> Result(File(I), IoError) {
    let mode = FileMode(read: options.read, write: options.write, append: options.append, truncate: options.truncate, create: options.create, create_new: options.create_new)
    let handle = try io.open(path, mode)
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
