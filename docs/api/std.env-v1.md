# `std.env` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for host strings, process arguments,
environment, working directory, executable location, and target information.
It is normative together with the executable example
[`examples/std.env-v1.al`](examples/std.env-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/env.al`.

Snapshot v1 fixes the host-environment surface (process arguments,
environment, working directory, executable location, and target information)
and `PlatformInfo`, the shared host-error-detail record used by `IoError`,
`EnvError`, and `ProcessError`. The shared host-string type `OsString` is
defined by `std.path` (v1 amendment: it moved there so the module graph stays
acyclic) and imported here. Environment access deliberately takes no I/O
capability: it never waits on the host, and the frozen capability list
(`files`, `streams`, `processes`, `sleeps`, `clocks`, randomness) does not
include it. Operations observe and update process-global host state; the
contract below pins what that means for tests and programs.

## Signatures

```alder
module std.env

import std.path { OsString, Path }

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

/// The shared host error-detail record: the host error number and its
/// formatted message, as reported at the failure point. Every hosted
/// module's `Platform`-style variant carries this record.
pub type PlatformInfo {
    pub code: I32
    pub message: String
}

impl env {
    /// The process arguments, `arguments()[0]` being the program name per
    /// the entry contract. A copy; safe to retain.
    pub fn arguments() -> Vec(OsString)
    /// The value of environment variable `name`, `None` when unset.
    pub fn var(name: OsString) -> Option(OsString)
    /// Sets environment variable `name` to `value` in this process.
    pub fn set_var(name: OsString, value: OsString) -> Result(Unit, EnvError)
    /// Removes environment variable `name` from this process.
    pub fn remove_var(name: OsString) -> Result(Unit, EnvError)
    /// The path of the running executable.
    pub fn current_exe() -> Result(Path, EnvError)
    /// The process's current working directory.
    pub fn current_dir() -> Result(Path, EnvError)
    /// Changes the process's current working directory. Process-global:
    /// relative path resolution everywhere observes the change.
    pub fn set_current_dir(path: Path) -> Result(Unit, EnvError)
}

/// Compile-time target information of the running build.
pub type Target {
    pub os: TargetOs
    pub arch: TargetArch
}

pub enum TargetOs {
    Linux
    MacOS
    Windows
}

pub enum TargetArch {
    X64
    AArch64
}

impl env {
    /// The target the compiler built for. Values are fixed per build;
    /// nothing here inspects the running host beyond that.
    pub fn target() -> Target
}

impl Error for EnvError {
    // Root error: the default `cause` is `None`.
}
```

Equality for `OsString` is structural over exact bytes (owned by `std.path`,
like the type itself). `Display` for `OsString` (lossy UTF-8 rendering with
replacement characters) lands with the sysroot formatting snapshot and is
additive.

## Contracts

- `OsString` is the one host-string type of the hosted modules; it is defined
  by `std.path` and imported here. `std.env` and `std.io` convert to and from
  it explicitly and nothing reinterprets bytes as text.
- Construction is checked and total; the only universally rejected byte is
  interior NUL. No operation trims, splits, or otherwise rewrites bytes.
- `arguments`, `var`, and `target` are pure host observations: they never
  take a capability, never wait, and are allowed inside any function
  including `main` before capability use.
- `set_var`, `remove_var`, and `set_current_dir` update process-global state.
  Programs that run concurrent tasks must not call them while other tasks
  observe the same state; tests call them only at startup or in a
  single-task context.
- Environment lookups of unset names return `None`, not an error.
- `arguments()[0]` is the program name as the host delivered it and may be
  empty on exotic launch methods; nothing here asserts its shape.
- Error enums implement the prelude `Error` trait (D025); `EnvError` is a root error, so the default `cause` is `None`.
- Tests never read ambient environment values: a test that needs a value
  sets it first through `set_var` with a fixed key.

## Example

The example below is the complete content that lands as
`examples/std.env-v1.al` with the implementation commit. It only reads values
it set itself, so it is deterministic under any host environment, and returns
a checksum.

```alder
module hello.std_env_example

import std.env
import std.path

// The executable std.env v1 snapshot example. Only self-set values are
// observed; every stage contributes a deterministic share of the checksum.

// The example inputs are fixed valid values, so failed constructions
// contribute nothing; `try` is reserved for functions returning `Result`.
pub fn std_env_example() -> U64 {
    var total: U64 = 0

    // Arguments: entry contract shape, program name present.
    let args = env.arguments()
    if args.len() >= 1 { total = total + 1 }

    // Self-set variable round-trip, removal, rejected construction, and the
    // byte round-trip, over fixed key and value strings.
    match path.OsString.parse("ALDER_STD_ENV_EXAMPLE") {
        Ok(key) => {
            match path.OsString.parse("ready") {
                Ok(value) => {
                    match env.set_var(key, value) {
                        Ok(_) => {
                            match env.var(key) {
                                Some(found) => {
                                    if found == value { total = total + 10 }
                                }
                                None => { total = total - 1000 }
                            }
                        }
                        Err(_) => { total = total - 1000 }
                    }

                    // Removal.
                    match env.remove_var(key) {
                        Ok(_) => {
                            match env.var(key) {
                                Some(_) => { total = total - 10000 }
                                None => { total = total + 100 }
                            }
                        }
                        Err(_) => { total = total - 10000 }
                    }

                    // Byte round-trip: `Bytes` into a fresh host string.
                    let raw = "ready"
                    match path.OsString.from_bytes(raw.to_bytes()) {
                        Ok(rebuilt) => {
                            if rebuilt == value && rebuilt.len() == 5 {
                                total = total + 1
                            }
                        }
                        Err(_) => { total = total - 1 }
                    }
                }
                Err(_) => { total = total - 100000 }
            }
        }
        Err(_) => { total = total - 100000 }
    }

    // Rejected construction.
    match path.OsString.parse("bad\0value") {
        Ok(_) => { total = total - 100000 }
        Err(_) => { total = total + 1 }
    }

    // Working directory and executable resolve on every supported target.
    match env.current_dir() {
        Ok(dir) => { if dir.to_os().len() > 0 { total = total + 1 } }
        Err(_) => { total = total - 100 }
    }
    match env.current_exe() {
        Ok(exe) => {
            match exe.file_name() {
                Some(name) => { total = total + name.len() * 100 }
                None => { total = total - 100 }
            }
        }
        Err(_) => { total = total - 100 }
    }

    // Target information is fixed for the build.
    let target = env.target()
    total = total + arch_bonus(target.arch)

    return total
}

fn arch_bonus(arch: env.TargetArch) -> U64 {
    match arch {
        X64 => { return 1 }
        AArch64 => { return 2 }
    }
}
```

## Dependencies and sequencing

- Integer conversions in the example use the settled builtin surface: total `to_u64()` for all-fitting pairs, with `to_u64_checked()` available where a value may not fit; the methods land with the sysroot thread's numeric surface after the String/Bytes byte work.
- `OsString` construction comes from `std.path` (v1 amendment), riding the
  sysroot thread's landed `String`/`Bytes` byte-sequence methods, including
  UTF-8 validation for `to_string`.
- Needs host access to argv, environ, `/proc/self/exe`-style paths, and
  `getcwd`/`chdir` through the C-binding thread's binding blocks plus small
  runtime additions; no capability plumbing.
- `file_name` and `to_os`/`len` on `Path` come from `std.path` (this snapshot
  family).
- The example avoids string building, interpolation, and `while let`.
