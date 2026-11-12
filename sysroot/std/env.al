module std.env

import std.path { OsString, Path }

import c "std/c/env_shim.h" as cenv {
    raw fn get = "env_get"(name: c.ConstPtr(c.Char), out: c.Ptr(c.UChar), capacity: c.Size) -> c.Int
    raw fn arg_count = "env_arg_count"() -> c.Int
    raw fn arg_length = "env_arg_length"(index: c.Int) -> c.LongLong
    raw fn arg_byte = "env_arg_byte"(index: c.Int, offset: c.ULongLong) -> c.Int
    raw fn current_exe = "env_current_exe"(out: c.Ptr(c.UChar), capacity: c.Size) -> c.LongLong
    raw fn current_dir = "env_current_dir"(out: c.Ptr(c.UChar), capacity: c.Size) -> c.LongLong
    raw fn set_var = "env_set_var"(name: c.ConstPtr(c.Char), value: c.ConstPtr(c.Char)) -> c.Int
    raw fn remove_var = "env_remove_var"(name: c.ConstPtr(c.Char)) -> c.Int
    raw fn set_current_dir = "env_set_current_dir"(path: c.ConstPtr(c.Char)) -> c.Int
    raw fn last_errno = "env_last_errno"() -> c.Int
    raw fn target_os = "env_target_os"() -> c.Int
    raw fn target_arch = "env_target_arch"() -> c.Int
}

// The Milestone 8 host-environment foundation: the shared host error-detail
// record, the environment error enum, and compile-time target information.
// Public snapshot v1 (docs/api/std.env-v1.md) fixes the full surface:
// `arguments`, `get`, `set_var`, `remove_var`, `current_exe`, `current_dir`,
// `set_current_dir`, and `target`. Environment access takes no I/O
// capability: it never waits on the host. Tests never read ambient
// environment values; a test that needs a value sets it first.

/// The shared host error-detail record: the host error number and its
/// formatted message, as reported at the failure point. Every hosted
/// module's `Platform`-style variant carries this record.
pub type PlatformInfo {
    pub code: I32
    pub message: String
}

/// Failure of checked construction or environment update.
pub enum EnvError {
    /// The input contained an interior NUL byte.
    InvalidEncoding
    /// A name or value cannot be used in the host environment (for
    /// example an empty name or one containing `=` on POSIX targets).
    InvalidName
    /// The operation has no implementation on this target.
    Unsupported
    /// A host call failed with no portable category.
    Platform(info: PlatformInfo)
}

/// Compile-time target information of the running build.
pub type Target {
    pub os: TargetOs
    pub arch: TargetArch
}

/// The operating system family the compiler built for.
pub enum TargetOs {
    Linux
    MacOS
    Windows
}

/// The machine architecture the compiler built for.
pub enum TargetArch {
    X64
    AArch64
}

fn host_name(name: OsString) -> Vec(U8) {
    let data = name.to_bytes()
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        out.push(data.byte(at))
        at = at + 1
    }
    out.push(0)
    return out
}

/// The value of environment variable `name`, `None` when unset. The value is
/// copied into owned bytes; no host pointer is retained. The function is
/// spelled `get` because `var` is a language keyword and cannot follow a
/// module qualifier in a call.
pub fn get(name: OsString) -> Option(OsString) {
    let key = host_name(name)
    var capacity: U64 = 256
    var attempt: U64 = 0
    while attempt < 8 {
        var room: Vec(U8) = Vec.new(U8)
        var filled: U64 = 0
        while filled < capacity {
            room.push(0)
            filled = filled + 1
        }
        let length = unsafe c { cenv.get(key.slice(0, key.len()), room.slice_mut(0, capacity), capacity.to_c_size()) }
        if length.to_i32() == -1 { return None }
        if length.to_i32() >= 0 {
            let size = length.to_i32().to_u64_wrapping()
            let value = room.slice(0, size).to_bytes()
            return match OsString.from_bytes(value) {
                Ok(text) => Some(text)
                Err(_) => None
            }
        }
        capacity = capacity * 2
        attempt = attempt + 1
    }
    return None
}

fn zeroed(size: U64) -> Vec(U8) {
    var room: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < size {
        room.push(0)
        at = at + 1
    }
    return room
}

fn host_error(message: String) -> EnvError {
    let code = unsafe c { cenv.last_errno() }.to_i32()
    return EnvError.Platform(PlatformInfo(code: code, message: message))
}

fn checked_name(name: OsString) -> Result(Vec(U8), EnvError) {
    let data = name.to_bytes()
    if data.len() == 0 { return Err(EnvError.InvalidName) }
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        let byte = data.byte(at)
        if byte == 61 { return Err(EnvError.InvalidName) }
        out.push(byte)
        at = at + 1
    }
    out.push(0)
    return Ok(out)
}

fn host_path(path: Path) -> Vec(U8) {
    let data = path.to_os().to_bytes()
    var out: Vec(U8) = Vec.new(U8)
    var at: U64 = 0
    while at < data.len() {
        out.push(data.byte(at))
        at = at + 1
    }
    out.push(0)
    return out
}

fn os_from_room(room: Vec(U8), length: I64) -> Result(OsString, EnvError) {
    if length < 0 { return Err(EnvError.Platform(PlatformInfo(code: -1, message: "host result is invalid"))) }
    let size = length.to_u64_wrapping()
    if size > room.len() { return Err(EnvError.Platform(PlatformInfo(code: -1, message: "host result exceeds the buffer"))) }
    return match OsString.from_bytes(room.slice(0, size).to_bytes()) {
        Ok(name) => Ok(name)
        Err(_) => Err(EnvError.InvalidEncoding)
    }
}

/// The process arguments, `arguments()[0]` being the program name per the
/// entry contract. A copy; safe to retain.
pub fn arguments() -> Vec(OsString) {
    var result: Vec(OsString) = Vec.new(OsString)
    let count = unsafe c { cenv.arg_count() }.to_i32()
    if count <= 0 { return result }
    var index: I32 = 0
    while index < count {
        let length = unsafe c { cenv.arg_length(index.to_c_int()) }.to_i64()
        if length >= 0 {
            var data: Vec(U8) = Vec.new(U8)
            let size = length.to_u64_wrapping()
            var offset: U64 = 0
            while offset < size {
                let raw = unsafe c { cenv.arg_byte(index.to_c_int(), offset.to_c_ulonglong()) }.to_i32()
                if raw < 0 {
                    offset = size
                } else {
                    data.push(raw.to_u8_wrapping())
                    offset = offset + 1
                }
            }
            if offset == size {
                match OsString.from_bytes(data.slice(0, size).to_bytes()) {
                    Ok(value) => { result.push(value) }
                    Err(_) => {}
                }
            }
        }
        index = index + 1
    }
    return result
}

/// Sets environment variable `name` to `value` in this process.
pub fn set_var(name: OsString, value: OsString) -> Result(Unit, EnvError) {
    let key = try checked_name(name)
    let text = host_name(value)
    let rc = unsafe c { cenv.set_var(key.slice(0, key.len()), text.slice(0, text.len())) }
    if rc.to_i32() != 0 { return Err(host_error("set environment variable failed")) }
    return Ok(())
}

/// Removes environment variable `name` from this process.
pub fn remove_var(name: OsString) -> Result(Unit, EnvError) {
    let key = try checked_name(name)
    let rc = unsafe c { cenv.remove_var(key.slice(0, key.len())) }
    if rc.to_i32() != 0 { return Err(host_error("remove environment variable failed")) }
    return Ok(())
}

/// The path of the running executable.
pub fn current_exe() -> Result(Path, EnvError) {
    let capacity: U64 = 4096
    var room = zeroed(capacity)
    let length = unsafe c { cenv.current_exe(room.slice_mut(0, capacity), capacity.to_c_size()) }
    if length.to_i64() < 0 { return Err(host_error("current executable path failed")) }
    let name = try os_from_room(room, length.to_i64())
    return Ok(Path.from_os(name))
}

/// The process's current working directory.
pub fn current_dir() -> Result(Path, EnvError) {
    let capacity: U64 = 4096
    var room = zeroed(capacity)
    let length = unsafe c { cenv.current_dir(room.slice_mut(0, capacity), capacity.to_c_size()) }
    if length.to_i64() < 0 { return Err(host_error("current directory failed")) }
    let name = try os_from_room(room, length.to_i64())
    return Ok(Path.from_os(name))
}

/// Changes the process's current working directory. Process-global:
/// relative path resolution everywhere observes the change.
pub fn set_current_dir(path: Path) -> Result(Unit, EnvError) {
    let bytes = host_path(path)
    let rc = unsafe c { cenv.set_current_dir(bytes.slice(0, bytes.len())) }
    if rc.to_i32() != 0 { return Err(host_error("set current directory failed")) }
    return Ok(())
}

/// The target the compiler built for. Values are fixed per build; nothing
/// here inspects the running host beyond that.
pub fn target() -> Target {
    let os_code = unsafe c { cenv.target_os() }.to_i32()
    var os: TargetOs = Linux
    if os_code == 1 { os = MacOS }
    if os_code == 2 { os = Windows }
    let arch_code = unsafe c { cenv.target_arch() }.to_i32()
    var arch: TargetArch = X64
    if arch_code == 1 { arch = AArch64 }
    return Target(os: os, arch: arch)
}

impl Display for EnvError {
    fn display(self) -> String {
        return match self {
            InvalidEncoding => "invalid encoding"
            InvalidName => "invalid environment name"
            Unsupported => "unsupported"
            Platform(info) => info.message
        }
    }
}

impl Error for EnvError {
}
