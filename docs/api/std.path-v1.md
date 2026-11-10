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

/// One owned exact host string: the bytes are precisely what the host gave
/// or will receive, with no encoding assumption. Interior NUL bytes are
/// rejected at construction because no host interface can carry them.
/// Equality is exact bytes. This is the one host-string type the hosted
/// modules share; `std.env`, `std.io`, and `std.process` convert to and
/// from it explicitly and nothing reinterprets its bytes as text.
pub type OsString {
    // private: data
}

impl OsString {
    /// Checks text as a host string.
    pub fn parse(text: String) -> Result(OsString, PathError)
    /// Builds from owned bytes, rejecting interior NUL bytes.
    pub fn from_bytes(data: Bytes) -> Result(OsString, PathError)
    /// The exact bytes.
    pub fn to_bytes(self) -> Bytes
    /// The text when the bytes are valid UTF-8, `None` otherwise.
    /// (Checked-total convention: non-text host strings are a
    /// representable state, not an error.)
    pub fn to_string(self) -> Option(String)
    /// The byte length.
    pub fn len(self) -> U64
}

/// One owned, checked path value. The bytes are exactly the host path:
/// interior NUL bytes are rejected at construction because no target can
/// address them. Paths compare by exact bytes.
pub type Path {
    // private: data
}

/// Failure of host-string or path construction from text: the only
/// rejected byte is interior NUL.
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
    pub fn parse(text: String) -> Result(Path, PathError)
    /// Builds a path from host bytes. Infallible: `OsString` already
    /// rejects interior NUL bytes.
    pub fn from_os(name: OsString) -> Path
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

Equality for `Path` and for `OsString` is structural: values are equal
exactly when their bytes are equal. No ordering relation is public in v1; the
sorted directory iterator in `std.fs` sorts by exact bytes internally.

`Display` for `Path` and for `OsString` (rendering non-UTF-8 components with
escapes, and host strings lossily with replacement characters) lands with the
sysroot formatting snapshot and is additive.

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

// Byte equality between a host string and a literal.
// uses == once Eq equality lands
fn os_is(left: OsString, right: String) -> Bool {
    if left.len() != right.len() { return false }
    var at: U64 = 0
    while at < left.len() {
        if left.byte(at) != right.byte(at) { return false }
        at = at + 1
    }
    return true
}

// Option equality against a literal.
// uses == once Eq equality lands
fn os_option_is(left: Option(OsString), right: String) -> Bool {
    match left {
        Some(value) => { return os_is(value, right) }
        None => { return false }
    }
}

// The example inputs are fixed valid paths, so failed parses contribute
// nothing; `try` is reserved for functions returning `Result`.
pub fn std_path_example() -> U64 {
    var total: U64 = 0

    // Component iteration over an absolute path with an extension.
    match path.Path.parse("/usr/local/app.conf") {
        Ok(entry) => {
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
            // uses == once Eq equality lands
            if os_option_is(entry.file_name(), "app.conf") { total = total + 100 }
            // uses == once Eq equality lands
            if os_option_is(entry.file_stem(), "app") { total = total + 200 }
            // uses == once Eq equality lands
            if os_option_is(entry.extension(), "conf") { total = total + 400 }
            match entry.parent() {
                Some(up) => { total = total + up.to_os().len() }
                None => { total = total - 1000 }
            }
            if entry.is_absolute() { total = total + 1000 }
        }
        Err(_) => { total = total - 10000000 }
    }

    // Lexical join and normalize, including a climb past a relative root.
    match path.Path.parse("a/b/./c") {
        Ok(base) => {
            match path.Path.parse("d/../../e") {
                Ok(suffix) => {
                    let norm = base.join(suffix).normalize()
                    // uses == once Eq equality lands
                    if os_is(norm.to_os(), "a/b/e") { total = total + 10000 }
                }
                Err(_) => { total = total - 10000000 }
            }
        }
        Err(_) => { total = total - 10000000 }
    }
    match path.Path.parse("a/../../..") {
        Ok(base) => {
            let up = base.normalize()
            // uses == once Eq equality lands
            if os_is(up.to_os(), "../../..") { total = total + 100000 }
        }
        Err(_) => { total = total - 10000000 }
    }

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
- `OsString` is defined by this module (v1 amendment: it moved here from
  `std.env` so the module graph stays acyclic); its byte access rides the
  sysroot thread's landed `String`/`Bytes` byte-sequence methods, including
  UTF-8 validation for `to_string`.
- No C bindings: the module is pure computation and can land as soon as the
  sysroot string byte operations are on main.
- The example avoids string building, interpolation, and `while let`; its
  `os_is`/`os_option_is` helpers compare host strings against fixed `String`
  literals byte by byte so the checksum reads as ordinary comparisons, and
  return to `==` once Eq equality lands.
