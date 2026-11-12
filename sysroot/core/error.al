module core.error

import c "alder_entry.h" as entry {
    raw fn write = "c_program_error"(text: c.ConstPtr(c.Char)) -> Unit
}

// D025: the builtin Error contract and its report value. This module is
// prelude-loaded by the compiler when a project names Error or ErrorReport;
// users do not import it. Error is an ordinary trait with a defaulted cause
// method, so `impl Error for T {}` is enough for a root error and a wrapper
// error overrides cause with the typed payload it wraps.

/// The displayed text of one error and every cause below it, nearest cause
/// first. The fields are public so an error display or report consumer can
/// read the flat chain without a trait object.
pub type ErrorReport {
    pub message: String
    pub causes: Vec(String)
}

/// A recoverable failure value that reports its wrapped cause. The default
/// cause is None: root errors implement the trait with an empty impl.
pub trait Error {
    fn cause(self) -> Option(ErrorReport) {
        return None
    }
}

impl ErrorReport {
    /// Builds the flat report for one error by recursing through cause.
    /// `E` must both implement Error and have a Display rendering.
    fn of(E: type(Error, Display), error: E) -> ErrorReport {
        let message = error.display()
        var causes: Vec(String) = Vec.new(String)
        match error.cause() {
            Some(report) => {
                causes.push(report.message)
                var at: U64 = 0
                while at < report.causes.len() {
                    causes.push(report.causes[at])
                    at = at + 1
                }
            }
            None => {}
        }
        return ErrorReport(message: message, causes: causes)
    }
}

fn write_program_text(text: String) -> Unit {
    match c.CString(text) {
        Some(held) => {
            using value = held
            unsafe c { entry.write(value.ptr()) }
        }
        None => {
            using fallback = c.CString("program error: message contains an interior NUL byte")
            unsafe c { entry.write(fallback.ptr()) }
        }
    }
}

/// Writes `program error: <display(error)>` to standard error. Used by the
/// generated entry adapter when the error type has no Error implementation.
pub fn program_error_display(E: type(Display), error: E) -> Unit {
    write_program_text("program error: ".concat(error.display()))
}

/// Writes `program error: <display(error)>` and then each cause report on its
/// own line. Used when the error type implements Error.
pub fn program_error_chain(E: type(Error, Display), error: E) -> Unit {
    let report = ErrorReport.of(error)
    var text = "program error: ".concat(report.message)
    var at: U64 = 0
    while at < report.causes.len() {
        text = text.concat("\n").concat(report.causes[at])
        at = at + 1
    }
    write_program_text(text)
}
