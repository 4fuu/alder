module std.io

import std.env

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
    /// Maps one host error number to a category. The values below agree on
    /// the tier-1 POSIX targets; slice 2 replaces the literal table with the
    /// target's C errno constants and the host's formatted message.
    fn from_errno(code: I32) -> IoError {
        if code == 2 { return NotFound }
        if code == 13 { return PermissionDenied }
        if code == 17 { return AlreadyExists }
        if code == 22 { return InvalidInput }
        return Other(env.PlatformInfo(code: code, message: code.display()))
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

/// An in-memory byte sink with a fixed capacity. `new` reserves 4096 bytes;
/// `with_capacity` chooses another size. The capacity is temporary: until
/// borrowed-field provenance lands, `write` copies into preallocated storage
/// and reports a short count (including zero) when the sink is full. The
/// Writer contract allows short writes, so `write_all` reports the incomplete
/// transfer instead of growing storage in the callee's domain.
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
        let room = self.data.len() - self.length
        var count = data.len()
        if count > room { count = room }
        var at: U64 = 0
        while at < count {
            self.data[self.length + at] = data[at]
            at = at + 1
        }
        self.length = self.length + count
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
        // A mutable view must be formed from a binding, so the source reads
        // into a local copy. Copy the bytes back element by element; replacing
        // the field header would install the callee's storage in the caller.
        var scratch = self.buffer
        let count = try self.source.read(scratch.slice_mut(0, size))
        var at: U64 = 0
        while at < count {
            self.buffer[at] = scratch[at]
            at = at + 1
        }
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
    fn new(sink: Sink) -> BufWriter(Sink) {
        return BufWriter(Sink)(sink: sink, buffer: zero_bytes(4096), length: 0)
    }

    fn with_capacity(capacity: U64, sink: Sink) -> BufWriter(Sink) {
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
        // The buffer is preallocated at `room` bytes. Copy into its existing
        // storage; replacing the field header would install the callee's
        // storage in the caller.
        var at: U64 = 0
        while at < size {
            self.buffer[base + at] = data[at]
            at = at + 1
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
