module core.panic

// The Milestone 8 process-terminating invariant surface. These functions are
// the only source-level operations that intentionally terminate the process:
// checked arithmetic, indexing, allocation, and runtime contract failures use
// the runtime's separate invariant path. The distinction is deliberate:
// `core.panic` writes a user message and aborts without a backtrace, while the
// runtime path's fixed diagnostics remain internal to the language runtime.
//
// Termination is not catchable and does not run Alder cleanup scopes or unwind
// caller frames. C stdio is flushed before the abort so earlier output is not
// lost. The message surface currently copies through `c.CString`; when the
// pointer-plus-length binding surface lands, it can use an allocation-free
// byte buffer without changing these signatures.

import c "alder_panic.h" as cpanic {
    raw fn raise = "c_panic"(message: c.ConstPtr(c.Char)) -> Unit
}

/// Terminates the process with `panic: <message>` on standard error.
///
/// This function never returns. The process aborts, Alder cleanup scopes do
/// not run, and caller frames are not unwound.
pub fn panic(message: String) -> Unit {
    raise_message(message)
}

/// Terminates the process when `condition` is false.
///
/// The diagnostic is `panic: assertion failed: <message>`. A true condition
/// returns normally. This function does not run Alder cleanup scopes on the
/// terminating path.
pub fn assert(condition: Bool, message: String) -> Unit {
    if !condition {
        raise_message("assertion failed: ".concat(message))
    }
}

/// Terminates the process when `a` and `b` are not equal.
///
/// The diagnostic names the fixed `a == b` relation and displays both operands.
/// Source-expression capture is deferred to the test runner; this function
/// prints parameter labels, not caller source text. Alder cleanup scopes do not
/// run on the terminating path.
pub fn assert_eq(T: type(Eq, Display), a: T, b: T) -> Unit {
    if a != b {
        raise_message(
            "assertion failed: a == b\n  a: "
                .concat(a.display())
                .concat("\n  b: ")
                .concat(b.display())
        )
    }
}

/// Terminates the process when `a` and `b` are equal.
///
/// The diagnostic names the fixed `a != b` relation and displays both operands.
/// Source-expression capture is deferred to the test runner; this function
/// prints parameter labels, not caller source text. Alder cleanup scopes do not
/// run on the terminating path.
pub fn assert_ne(T: type(Eq, Display), a: T, b: T) -> Unit {
    if a == b {
        raise_message(
            "assertion failed: a != b\n  a: "
                .concat(a.display())
                .concat("\n  b: ")
                .concat(b.display())
        )
    }
}

// The raw termination boundary. A CString owns a NUL-terminated copy of the
// message; an interior NUL is not representable there, so the fallback keeps
// termination total without truncating silently.
fn raise_message(message: String) -> Unit {
    match c.CString(message) {
        Some(held) => {
            using text = held
            unsafe c { cpanic.raise(text.ptr()) }
        }
        None => {
            using fallback = c.CString("message contains an interior NUL byte")
            unsafe c { cpanic.raise(fallback.ptr()) }
        }
    }
}
