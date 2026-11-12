module std.fs

// The Milestone 8 filesystem surface, value layer first. The public snapshot
// (docs/api/std.fs-v1.md) fixes the full surface; this module currently
// installs the pure value types (`Options` and `Permissions`) that need no
// host capability. File handles, directory iteration, metadata, whole-file
// operations, and temporary owners wait for the std.io slice 2 capability
// types and host handles.

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
