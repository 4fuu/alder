# `core.result` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for the builtin `Result(T, E)` helpers
in the installed sysroot. It is normative together with the executable example
in [`examples/core.result-v1.al`](examples/core.result-v1.al). The module lives
at `<sysroot>/core/result.al`; how the driver finds the sysroot and records it
in the build plan is defined in
[Modules and Builds](../modules-and-builds.md#installed-sysroot).

## Signatures

```alder
module core.result

pub fn is_ok(T: type, E: type, value: Result(T, E)) -> Bool
pub fn is_err(T: type, E: type, value: Result(T, E)) -> Bool

pub fn map(T: type, U: type, E: type, value: Result(T, E), f: fn(T) -> U) -> Result(U, E)
pub fn map_err(T: type, E: type, F: type, value: Result(T, E), f: fn(E) -> F) -> Result(T, F)
pub fn and_then(T: type, U: type, E: type, value: Result(T, E), f: fn(T) -> Result(U, E)) -> Result(U, E)

pub fn ok(T: type, E: type, value: Result(T, E)) -> Option(T)
pub fn err(T: type, E: type, value: Result(T, E)) -> Option(E)

pub fn unwrap_or(T: type, E: type, value: Result(T, E), fallback: T) -> T
```

`Result`, `Ok`, `Err`, and `Option` are prelude builtins; `core.result` only
adds these helpers, imported explicitly like any module and called qualified
(`result.map`) or imported by name.

## Contracts

- No helper terminates or fabricates a value. Which side a helper touches is
  explicit in its name and return type; extraction is total, through a
  mandatory fallback.
- The compile-time `type` parameters are ordinary leading parameters. Call
  sites omit them when the checker infers them from the arguments and may
  always spell them, in declaration order, as leading arguments.
- All type parameters must be recursively copyable values, matching the M7
  value model; an affine owner cannot sit inside a `Result` in this snapshot.
- `map` and `and_then` pass an error through unchanged and never call `f`;
  `map_err` passes a success through unchanged and never calls `f`.
- `ok` and `err` project exactly one side into `Option` and never lose the
  other side's identity: `is_err(v)` and `err(v)` agree on which side holds.
- Helpers are deterministic pure functions of their arguments: same argument
  values, same result, no hidden state, no OS access.

Iteration over `Result(T, E)` is not part of this snapshot; it arrives with
the `core.iter` iterator contract in a later snapshot.
