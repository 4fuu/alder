# `core.panic` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; core panic surface implemented**

This is the versioned public snapshot for process-terminating invariant
assertions. It is normative together with the executable example
[`examples/core.panic-v1.al`](examples/core.panic-v1.al), which lands with the
module implementation. The module lives at `<sysroot>/core/panic.al` and is
imported explicitly; it is not part of the prelude.

The functions in this module terminate the process. They do not return a
`Result`, are not catchable, and do not promise caller-frame unwinding. A
failed assertion writes a fixed diagnostic to standard error and aborts the
process. Alder cleanup scopes do not run on that path.

## Signatures

```alder
module core.panic

/// Terminates the process with `panic: <message>` on standard error.
///
/// This function never returns. The process aborts, Alder cleanup scopes do
/// not run, and caller frames are not unwound.
pub fn panic(message: String) -> Unit

/// Terminates the process when `condition` is false.
///
/// The diagnostic is `panic: assertion failed: <message>`. A true condition
/// returns normally.
pub fn assert(condition: Bool, message: String) -> Unit

/// Terminates the process when `a` and `b` are not equal.
///
/// The diagnostic names the fixed `a == b` relation and displays both operands.
/// Source-expression capture is deferred to the test runner.
pub fn assert_eq(T: type(Eq, Display), a: T, b: T) -> Unit

/// Terminates the process when `a` and `b` are equal.
///
/// The diagnostic names the fixed `a != b` relation and displays both operands.
/// Source-expression capture is deferred to the test runner.
pub fn assert_ne(T: type(Eq, Display), a: T, b: T) -> Unit
```

## Failure format

`panic(message)` writes exactly:

```text
panic: <message>
```

`assert(false, message)` writes exactly:

```text
panic: assertion failed: <message>
```

A failed `assert_eq` writes:

```text
panic: assertion failed: a == b
  a: <display(a)>
  b: <display(b)>
```

A failed `assert_ne` writes the same shape with `a != b`. The labels are the
fixed parameter names, not caller source expressions; source-expression
capture is deferred to the test runner. A passing assertion writes nothing and
returns `Unit`.

The process terminates by `abort()` after `fflush(NULL)` and a flush of
standard error. On POSIX hosts the termination signal is `SIGABRT` (a shell
status of 128 plus 6); it is not an `exit()` status and `atexit` handlers do
not run. A failure to write the diagnostic does not change the termination
path.

## Contracts

- The functions are process-terminating invariants, not recoverable errors.
  Use `Result` and `try` for recoverable failures.
- No Alder cleanup scope, resource hook, `atexit` handler, or caller frame runs
  on the terminating path. Cleanup before a possible assertion failure must be
  explicit in the caller when it is required.
- `assert_eq` and `assert_ne` require `T: type(Eq, Display)`. The builtin `Eq`
  domain currently covers unsigned integers, `Bool`, `String`, `Bytes`, and
  eligible records/enums; the builtin `Display` domain covers `Bool`, signed
  and unsigned integers, and `String`, with user implementations for eligible
  declared types.
- Operands are evaluated once at the call boundary. A passing assertion has no
  output and no observable side effect beyond operand evaluation.
- A `String` containing an interior NUL cannot be represented by the current
  C-string boundary. Such a panic writes the fixed message
  `panic: message contains an interior NUL byte` and still aborts. The
  signature and abort contract stay stable when the pointer-plus-length buffer
  surface replaces this fallback.
- The runtime shim is `runtime/c/alder_panic.h` (`c_panic`). It is separate
  from the compiler's `alder_runtime_panic` hook: both terminate by abort, but
  this hook writes the user panic prefix and no backtrace, while
  `alder_runtime_panic` writes the runtime's fixed diagnostic. See
  [C backend](../c-backend.md).

## Example

```alder
module hello.core_panic_example

import core.panic { assert, assert_eq, assert_ne }

pub fn core_panic_example() -> U64 {
    var total: U64 = 0
    assert(true, "never printed")
    assert_eq(U64, 7, 7)
    assert_ne(U64, 7, 8)
    total = total + 1
    assert_eq(String, "alder", "alder")
    total = total + 10
    return total
}
```

The example returns 11. A failing case is observed by a subprocess test: the
child writes the documented stderr line and terminates with `SIGABRT`.
