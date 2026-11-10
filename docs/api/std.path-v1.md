# `std.path` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for path values and lexical path
operations. It is normative together with the executable example
[`examples/std.path-v1.al`](examples/std.path-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/path.al`.

Snapshot v1 defines POSIX-native semantics (the separator is `/`, `.`, and
`..` are ordinary components, a leading `/` is the root). Path values preserve
exact host bytes, never assume paths are UTF-8, and never touch the
filesystem. Windows separator and drive-component semantics arrive with the
M10 target work as an additive revision; the lexical contract below is written
so that extension does not change any v1 signature.

## Signatures

```alder
module std.path

import std.env { OsString }

/// One owned, checked path value. The bytes are exactly the host path:
/// interior NUL bytes are rejected at construction because no target can
/// address them. Paths compare by exact bytes.
pub type Path {
    // private: data
}

/// Failure of path construction from text.
pub enum PathError {
    /// The input contained an interior NUL byte.
    InvalidEncoding
}

/// One component of a path in native form.
pub enum Component {
    /// The leading root, `/` on POSIX targets.
    RootDir
    /// A `.` component.
    CurDir
    /// A `..` component.
    ParentDir
    /// A normal component's exact bytes.
    Normal(name: OsString)
}

impl Path {
    /// Checks text as a path: every UTF-8 sequence is accepted except one
    /// containing an interior NUL byte.
    pub fn parse(T: type, text: T) -> Result(Path, PathError)
    /// Builds a path from host bytes. Infallible: `OsString` already
    /// rejects interior NUL bytes.
    pub fn from_os(T: type, name: T) -> Path
    /// The exact bytes as an `OsString`.
    pub fn to_os(self) -> OsString
    /// The bytes as text when they are valid UTF-8, `None` otherwise.
    /// (Checked-total convention: non-text paths are a representable state,
    /// not an error.)
    pub fn to_string(self) -> Option(String)
}

impl Path {
    /// The path's components in native form.
    pub fn components(self) -> Vec(Component)
    /// Lexical join. An empty suffix returns the path unchanged; an
    /// absolute suffix replaces the path. Never consults the filesystem.
    pub fn join(self, suffix: Path) -> Path
    /// Collapses `.` components and resolves `..` lexically. A `..` that
    /// would climb past the root is kept, so normalization never needs the
    /// filesystem and never turns a relative path into an absolute one.
    pub fn normalize(self) -> Path
    /// The final normal component, `None` when the path ends in a root,
    /// `.`/`..` component, or is empty.
    pub fn file_name(self) -> Option(OsString)
    /// `file_name` without its final extension, `None` when there is no
    /// file name.
    pub fn file_stem(self) -> Option(OsString)
    /// The final extension's bytes without the dot, `None` when the file
    /// name has no extension or is a dotfile with none.
    pub fn extension(self) -> Option(OsString)
    /// The path without its final component, `None` at the root or for an
    /// empty path.
    pub fn parent(self) -> Option(Path)
    /// True when the first component is the root.
    pub fn is_absolute(self) -> Bool
}

impl Error for PathError {
    // Root error: the default `cause` is `None`.
}
```

Equality for `Path` is structural: two paths are equal exactly when their
bytes are equal. No ordering relation is public in v1; the sorted directory
iterator in `std.fs` sorts by exact bytes internally.

`Display` for `Path` (rendering non-UTF-8 components with escapes) lands with
the sysroot formatting snapshot and is additive.

## Contracts

- `Path` is pure data: no method opens, stats, or normalizes through the
  filesystem. Operations that consult the host live in `std.fs`.
- Construction is checked and total: interior NUL bytes are the only rejected
  byte on POSIX targets, reported as `PathError.InvalidEncoding`.
- All operations preserve exact component bytes; nothing percent-encodes,
  decodes, or otherwise rewrites component content.
- `join` is purely lexical: it never produces `..` and never resolves one.
  `normalize` removes `.` and lexically resolvable `..` and keeps a leading
  run of `..` on relative paths.
- `components`, `file_name`, `file_stem`, `extension`, and `parent` follow
  native separator rules; v1 fixes the POSIX rules and M10 extends the same
  signatures to per-target rules.
- Error enums implement the prelude `Error` trait (D025); `PathError` is a root error, so the default `cause` is `None`.
- Examples and tests never depend on filesystem state or locale.

## Example

The example below is the complete content that lands as
`examples/std.path-v1.al` with the implementation commit. It stays purely
lexical and returns a deterministic checksum.

```alder
module hello.std_path_example

import std.path

// The executable std.path v1 snapshot example. Pure lexical operations over
// fixed inputs; every stage contributes a deterministic share of the
// returned checksum.

pub fn std_path_example() -> U64 {
    var total: U64 = 0

    // Component iteration over an absolute path with an extension.
    let entry = try path.Path.parse("/usr/local/app.conf")
    var names: U64 = 0
    var dots: U64 = 0
    let parts = entry.components()
    var at: U64 = 0
    while at < parts.len() {
        match parts[at] {
            RootDir => { dots = dots + 1 }
            CurDir => { dots = dots + 2 }
            ParentDir => { dots = dots + 4 }
            Normal(name) => { names = names + name.len() }
        }
        at = at + 1
    }
    total = total + names * 10 + dots

    // Name, stem, extension, and parent queries.
    if entry.file_name() == some_os("app.conf") { total = total + 100 }
    if entry.file_stem() == some_os("app") { total = total + 200 }
    if entry.extension() == some_os("conf") { total = total + 400 }
    match entry.parent() {
        Some(up) => { total = total + up.to_os().len() }
        None => { total = total - 1000 }
    }
    if entry.is_absolute() { total = total + 1000 }

    // Lexical join and normalize, including a climb past a relative root.
    let base = try path.Path.parse("a/b/./c")
    let joined = base.join(try path.Path.parse("d/../../e"))
    let norm = joined.normalize()
    if norm.to_os() == os_bytes("a/b/e") { total = total + 10000 }
    let up = try path.Path.parse("a/../../..").normalize()
    if up.to_os() == os_bytes("../../..") { total = total + 100000 }

    // Rejected construction.
    match path.Path.parse("bad\0name") {
        Ok(_) => { total = total - 1000000 }
        Err(_) => { total = total + 1 }
    }

    return total
}
```

## Dependencies and sequencing

- Integer conversions in the example use the settled builtin surface: total `to_u64()` for all-fitting pairs, with `to_u64_checked()` available where a value may not fit; the methods land with the sysroot thread's numeric surface after the String/Bytes byte work.
- Needs `OsString` and its `len` from `std.env` (this snapshot family) and the
  sysroot thread's `String` byte-level construction for `parse` and
  `to_string` (decode and UTF-8 validation helpers).
- No C bindings: the module is pure computation and can land as soon as the
  sysroot string byte operations are on main.
- The example avoids string building, interpolation, and `while let`; helper
  functions `os_bytes`/`some_os` in the example file build fixed `OsString`
  values through the module's own checked constructors so the checksum reads
  as ordinary comparisons.
