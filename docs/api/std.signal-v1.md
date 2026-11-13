# `std.signal` Public Signature Snapshot v1

Status: **Milestone 8.1 frozen snapshot; one-shot blocking wait implemented**

This is the versioned public snapshot for the signal foundation. It is
normative together with the executable example
[`examples/std.signal-v1.al`](examples/std.signal-v1.al), which lands in the
module's implementation commit. The module lives at `<sysroot>/std/signal.al`
and is imported explicitly; it is not part of the prelude.

The M8.1 surface is deliberately one-shot. `wait` installs a host disposition,
waits at most the requested timeout, restores the previous disposition, and
returns. **Between waits the original disposition is active, so a signal that
arrives outside a wait gets the default action** (or whatever handler the
process installed before). It is not a subscription and does not deliver to a
task. Persistent subscriptions, evented delivery, and task wakeups are M9
work.

## Signatures

```alder
module std.signal

import std.io { Io, IoError }

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

impl Display for SignalError {
    fn display(self) -> String
}

impl Error for SignalError {
}

/// Waits up to `timeout_ms` for `signal`. A negative timeout waits forever;
/// zero polls once. `Some(signal)` means it arrived, `None` means timeout.
/// The original disposition is restored before this returns, so a signal that
/// arrives between waits follows that original disposition.
pub fn wait(I: type(Io), io: I, signal: Signal, timeout_ms: I32)
    -> Result(Option(Signal), SignalError)
```

The generic call may omit the type argument when `io` is a named local:
`let io = Blocking()` followed by `signal.wait(io, signal.Signal.Terminate,
5000)`. Passing a constructor directly (`wait(Blocking(), ...)`) does not
provide enough inference information in the current checker.

## Signal mapping

`Signal` maps to the host's portable names. Linux and macOS use their POSIX
signal numbers; Windows uses console control events.

| Signal | Linux | macOS | Windows |
| --- | --- | --- | --- |
| `Interrupt` | `SIGINT` | `SIGINT` | `CTRL_C_EVENT` |
| `Terminate` | `SIGTERM` | `SIGTERM` | `CTRL_BREAK_EVENT` |
| `Hangup` | `SIGHUP` | `SIGHUP` | `Unsupported` |
| `Quit` | `SIGQUIT` | `SIGQUIT` | `Unsupported` |
| `User1` | 10 | 30 | `Unsupported` |
| `User2` | 12 | 31 | `Unsupported` |
| `Target(number)` | raw number | raw number | `Unsupported` |

`Signal.Target` is the target-specific extension. The capability validates
the number; an invalid POSIX number maps to `SignalError.InvalidSignal`.
Windows console events beyond Ctrl-C and Ctrl-Break wait for M9.

## Semantics

- `wait` is one-shot. Repeated waits are separate calls, each with its own
  install/restore cycle. A signal arriving after a wait returns follows the
  restored disposition; it is not queued for the next wait.
- Standard signals coalesce while the temporary handler is installed. One
  wait observes at most one delivery.
- `timeout_ms < 0` waits without a deadline; `0` polls once. A timeout is
  `Ok(None)`, not an error.
- `Io.wait_signal` is the capability operation. `std.signal` maps the
  portable enum to a host number, calls the capability, and maps an
  unsupported or invalid host result to `SignalError`. The bootstrap compiler
  does not import `std.signal`, so the compiler fixed point is unaffected.
- Concurrent waits on the same signal are outside v1; the host shim uses one
  process-global temporary disposition. M9 owns subscription state and
  concurrency.
- No Alder process receives a signal through this API on Windows unless the
  process has a console; the capability reports `Unsupported` otherwise.

## Out of scope

The following are M9 or later, not gaps in the v1 contract:

- persistent `Subscription(I)` owners, multiple signals or signal sets per
  subscription, and repeated `poll`/`wait` without reinstalling;
- `AsyncIo`/`Evented` delivery, task wakeups, and cancellation-safe teardown;
- Windows close, logoff, and shutdown console events;
- POSIX realtime signals and `sigqueue`, plus `SIGCHLD` integration with
  process/task waiting;
- cancellation-aware process termination built on the same subscription
  machinery.

## Verification

`compiler/production_std_signal_test.go` builds an Alder executable, starts it
as a child, sends a real `SIGTERM`, and checks that the program exits zero
only on `Some(Terminate)`. It also checks the zero-timeout `None` path, a
second wait receiving the signal, raw `Signal.Target(SIGUSR1)` on POSIX, and
disposition restoration: after a wait returns, a late `SIGTERM` terminates the
child by the default action. The shim is compiled under the strict C11 warning
set and the cross-target compile-only lanes. No checker, MIR, lowering,
verifier, or cgen case is added.
