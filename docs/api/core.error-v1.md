# `core.error` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for the D025 recoverable-error report
contract. It is normative together with the executable behavior in the
production compiler tests. The module lives at `<sysroot>/core/error.al` and is
prelude-loaded for projects that name `Error` or `ErrorReport`; programs do not
need an explicit import.

## Signatures

```alder
module core.error

pub type ErrorReport {
    pub message: String
    pub causes: Vec(String)
}

pub trait Error {
    fn cause(self) -> Option(ErrorReport) {
        return None
    }
}

impl ErrorReport {
    fn of(E: type(Error, Display), error: E) -> ErrorReport
}

pub fn program_error_display(E: type(Display), error: E) -> Unit
pub fn program_error_chain(E: type(Error, Display), error: E) -> Unit
```

`message` is the `Display` rendering of the error itself. `causes` holds the
flattened chain below it, nearest cause first; the current error is not repeated
in `causes`.

## Contracts

- `impl Error for T {}` is valid for a root error and inherits the default
  `cause`, which returns `None`.
- A wrapper error implements `cause` by matching its typed payload and returning
  `Some(ErrorReport.of(payload))`. Typed payload access stays with `match`; the
  report is the only chain value and there are no trait objects.
- `ErrorReport.of` requires both `Error` and `Display`. It displays `error`
  before walking `cause`, then appends each cause report's message followed by
  its causes, preserving nearest-first order.
- Reports are ordinary copyable values. `causes` is an independent `Vec(String)`
  copy selected by the normal value semantics.
- The prelude surface is explicit in source: `Error` remains a reserved name
  for user declarations outside `core.error`, while the prelude source is the
  one permitted declaration site.
- The generated hosted entry adapter uses these helpers for an unhandled
  `Err`: `program_error_display` prints `program error: <display(error)>` for
  a `Display`-only error, while `program_error_chain` prints the report
  message followed by each cause on its own line. Both write to standard
  error and return normally; the adapter then returns status 1. The entry
  adapter is generated only for the documented source result forms and does
  not perform exit cleanup
  ([Modules and Builds](../modules-and-builds.md#entry-points-and-tests)).
