# `core.option` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for the builtin `Option(T)` helpers in
the installed sysroot. It is normative together with the executable example in
[`examples/core.option-v1.al`](examples/core.option-v1.al). The module lives at
`<sysroot>/core/option.al`; how the driver finds the sysroot and records it in
the build plan is defined in
[Modules and Builds](../modules-and-builds.md#installed-sysroot).

## Signatures

```alder
module core.option

pub fn is_some(T: type, value: Option(T)) -> Bool
pub fn is_none(T: type, value: Option(T)) -> Bool

pub fn map(T: type, U: type, value: Option(T), f: fn(T) -> U) -> Option(U)
pub fn and_then(T: type, U: type, value: Option(T), f: fn(T) -> Option(U)) -> Option(U)
pub fn or(T: type, value: Option(T), fallback: Option(T)) -> Option(T)

pub fn unwrap_or(T: type, value: Option(T), fallback: T) -> T
pub fn unwrap_or_else(T: type, value: Option(T), fallback: fn() -> T) -> T

pub fn ok_or(T: type, E: type, value: Option(T), error: E) -> Result(T, E)
```

`Option(T)`, `Some`, `None`, and `Result` are prelude builtins; `core.option`
only adds these helpers, imported explicitly like any module and called
qualified (`option.map`) or imported by name.

## Contracts

- No helper terminates or fabricates a value. Every emptiness decision is
  explicit in the helper's name and return type; extraction is total, through
  a mandatory fallback.
- The compile-time `type` parameters are ordinary leading parameters. Call
  sites omit them when the checker infers them from the arguments and may
  always spell them, in declaration order, as leading arguments.
- All type parameters must be recursively copyable values, matching the M7
  value model; an affine owner cannot sit inside an `Option` in this snapshot.
- `map` and `and_then` pass emptiness through unchanged and never call `f`.
- `or` and `unwrap_or` evaluate their fallback argument eagerly in the
  caller's source position, whether or not the option holds a value;
  `unwrap_or_else` calls `fallback` only for an empty option.
- `ok_or` evaluates `error` eagerly in the caller's source position, whether
  or not the option holds a value.
- Helpers are deterministic pure functions of their arguments: same argument
  values, same result, no hidden state, no OS access.

Iteration over `Option(T)` is not part of this snapshot; it arrives with the
`core.iter` iterator contract in a later snapshot.
