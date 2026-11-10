module std.env

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
    code: I32
    message: String
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
    os: TargetOs
    arch: TargetArch
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
