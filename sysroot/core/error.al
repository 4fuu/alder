module core.error

// D025: the builtin Error contract and its report value. This module is
// prelude-loaded by the compiler when a project names Error or ErrorReport;
// users do not import it. Error is an ordinary trait with a defaulted cause
// method, so `impl Error for T {}` is enough for a root error and a wrapper
// error overrides cause with the typed payload it wraps.

/// The displayed text of one error and every cause below it, nearest cause
/// first. The fields are public so an error display or report consumer can
/// read the flat chain without a trait object.
pub type ErrorReport {
    message: String
    causes: Vec(String)
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
