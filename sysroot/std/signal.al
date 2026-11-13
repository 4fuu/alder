module std.signal

import std.env { TargetOs, target }
import std.io { Io, IoError }

// The Milestone 8.1 signal foundation: one blocking, capability-based wait for
// a termination, interrupt, or target signal. The call installs a host
// disposition, waits at most the requested timeout, restores the previous
// disposition, and returns. It is not a subscription: between calls the
// original disposition is active, so a signal that arrives outside a wait
// gets the default action (or whatever handler the process installed before).
// Persistent subscriptions, evented delivery, and task wakeups are M9 work.

/// One termination or interrupt request. `Target` is the POSIX extension;
/// Windows reports it as unsupported.
pub enum Signal {
    Interrupt
    Terminate
    Hangup
    Quit
    User1
    User2
    /// A raw target signal number. POSIX only in v1.
    Target(number: I32)
}

/// Failure of a signal wait. `Host` carries a host I/O category that has no
/// more precise portable signal meaning.
pub enum SignalError {
    /// This target or capability cannot deliver the requested signal.
    Unsupported
    /// The host rejected the signal number.
    InvalidSignal
    /// A host wait failed for another reason.
    Host(error: IoError)
}

/// Waits up to `timeout_ms` for `signal`. A negative timeout waits forever;
/// zero polls once. `Some(signal)` means it arrived, `None` means timeout.
/// The original disposition is restored before this returns, so a signal that
/// arrives between waits follows that original disposition.
pub fn wait(I: type(Io), io: I, signal: Signal, timeout_ms: I32) -> Result(Option(Signal), SignalError) {
    let number = try host_number(signal)
    var delivered = false
    match io.wait_signal(number, timeout_ms) {
        Ok(value) => { delivered = value }
        Err(error) => { return Err(signal_error(error)) }
    }
    if delivered { return Ok(Some(signal)) }
    return Ok(None)
}

fn host_number(signal: Signal) -> Result(I32, SignalError) {
    let os = target().os
    match signal {
        Interrupt => {
            if os == TargetOs.Windows { return Ok(0) }
            return Ok(2)
        }
        Terminate => {
            if os == TargetOs.Windows { return Ok(1) }
            return Ok(15)
        }
        Hangup => {
            if os == TargetOs.Windows { return Err(SignalError.Unsupported) }
            return Ok(1)
        }
        Quit => {
            if os == TargetOs.Windows { return Err(SignalError.Unsupported) }
            return Ok(3)
        }
        User1 => {
            if os == TargetOs.Linux { return Ok(10) }
            if os == TargetOs.MacOS { return Ok(30) }
            return Err(SignalError.Unsupported)
        }
        User2 => {
            if os == TargetOs.Linux { return Ok(12) }
            if os == TargetOs.MacOS { return Ok(31) }
            return Err(SignalError.Unsupported)
        }
        Target(number) => {
            if os == TargetOs.Windows { return Err(SignalError.Unsupported) }
            return Ok(number)
        }
    }
    return Err(SignalError.Unsupported)
}

fn signal_error(error: IoError) -> SignalError {
    match error {
        Unsupported => { return SignalError.Unsupported }
        InvalidInput => { return SignalError.InvalidSignal }
        _ => {}
    }
    return SignalError.Host(error)
}

impl Display for SignalError {
    fn display(self) -> String {
        return match self {
            Unsupported => "unsupported signal"
            InvalidSignal => "invalid signal"
            Host(error) => error.display()
        }
    }
}

impl Error for SignalError {
}
