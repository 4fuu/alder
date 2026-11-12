module std.env

import std.path { OsString }

import c "std/c/env_shim.h" as cenv {
    raw fn get = "env_get"(name: c.ConstPtr(c.Char), out: c.Ptr(c.UChar), capacity: c.Size) -> c.Int
}

// The Milestone 8 host-environment foundation: the shared host error-detail
// record, the environment error enum, and compile-time target information.
// Public snapshot v1 (docs/api/std.env-v1.md) fixes the full surface; the
// host-observing methods (`arguments`, `var`, `set_var`, `remove_var`,
// `current_exe`, `current_dir`, `set_current_dir`, `target`) land with the
// C-binding surface they need and are additive here. Environment access
// takes no I/O capability: it never waits on the host. Tests never read
// ambient environment values; a test that needs a value sets it first.

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
