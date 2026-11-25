module std.task

// Milestone 9 gate 9.4 slice B: the std.task type skeleton. The group and task
// owners, their cleanup hooks, the free combinators, and the token operations
// are fixed-panic placeholders until gate 9.4c installs the group record, the
// executor handoff, and source-scoped shared state. `Cancellation`'s source
// side is complete and runs under any capability; see docs/api/std.task-v1.md.

import core.panic { panic }
import std.io { AsyncIo, Io }
import std.time { Duration }

/// Affine owner of one executor-backed task group.
///
/// The capability and child registry are private, and the group's `Cleanup`
/// hook joins every child before the owning scope exits.
pub type TaskGroup(I: type(Io, AsyncIo)) {
    capability: I
}

/// Affine, group-scoped handle to one spawned child.
///
/// The handle is local to the group and is consumed by `await`; it cannot be
/// returned, stored in an escaping aggregate, or awaited outside its group
/// scope.
pub type Task(T: type) {
    child: U64
}

/// Declaration-only parameter type of the five standard task operations.
///
/// A `Pending(T)` argument is always written as a direct call to a named
/// function or method; the type is never constructed, bound, stored, returned,
/// or passed as a value.
pub type Pending(T: type) {
}

/// The timeout combinator's error: the child did not finish in time.
pub enum Timeout {
    Timeout
}

/// Cooperative application cancellation, as an ordinary result.
pub enum CancellationError {
    Cancelled
}

/// Affine owner of one cooperative cancellation state.
///
/// `new` takes no capability, so the pair works under `BlockingIo` where the
/// executor has no task cancellation.
pub type Cancellation {
    cancelled: Array(U8, 1)
}

/// Copyable, portable read capability minted from one `Cancellation`.
///
/// Every copy observes the source's state; a token may not escape the scope
/// that owns its source. The skeleton leaves the shared state to gate 9.4c,
/// because a copyable value cannot observe an affine source until the
/// source-scoped capability category exists.
pub type CancellationToken {
}

impl(I: type(Io, AsyncIo)) TaskGroup(I) {
    /// Creates a group on the executor carried by `io`.
    fn new(io: I) -> TaskGroup(I) {
        panic("std.task.TaskGroup.new is unimplemented until gate 9.4c")
    }

    /// Starts the direct call's body as a child and returns its handle.
    fn spawn(T: type, mut self, pending: Pending(T)) -> Task(T) {
        panic("std.task.TaskGroup.spawn is unimplemented until gate 9.4c")
    }

    /// Starts a `Unit` child that the group joins without a user handle.
    fn start(mut self, pending: Pending(Unit)) -> Unit {
        panic("std.task.TaskGroup.start is unimplemented until gate 9.4c")
    }
}

impl(I: type(Io, AsyncIo)) Cleanup for TaskGroup(I) {
    /// Joins every outstanding child, cancelling the ones the parent never
    /// awaited. Unimplemented until gate 9.4c.
    fn cleanup(take self) -> Unit {
        panic("std.task.TaskGroup cleanup is unimplemented until gate 9.4c")
    }
}

impl(T: type) Cleanup for Task(T) {
    /// Returns the child to its group without waiting. Unimplemented until
    /// gate 9.4c.
    fn cleanup(take self) -> Unit {
        panic("std.task.Task cleanup is unimplemented until gate 9.4c")
    }
}

impl Cancellation {
    /// Creates a cancellation state that no token reports as cancelled yet.
    fn new() -> Cancellation {
        return Cancellation(cancelled: [0])
    }

    /// Mints a token that observes this source's state. Unimplemented until
    /// gate 9.4c installs source-scoped shared state.
    fn token(self) -> CancellationToken {
        panic("std.task.Cancellation.token is unimplemented until gate 9.4c")
    }

    /// Marks the state; every token minted from this source observes it.
    fn cancel(mut self) -> Unit {
        self.cancelled = [1]
        return
    }

    /// Reports whether `cancel` has marked the state.
    fn is_cancelled(self) -> Bool {
        return self.cancelled[0] == 1
    }
}

impl Cleanup for Cancellation {
    /// The state is inline, so the owner needs no release step.
    fn cleanup(take self) -> Unit {
        return
    }
}

impl CancellationToken {
    /// Reports whether the source's `cancel` has marked the state.
    /// Unimplemented until gate 9.4c.
    fn is_cancelled(self) -> Bool {
        panic("std.task.CancellationToken.is_cancelled is unimplemented until gate 9.4c")
    }

    /// The ordinary-result form of `is_cancelled`. Unimplemented until gate
    /// 9.4c.
    fn check(self) -> Result(Unit, CancellationError) {
        panic("std.task.CancellationToken.check is unimplemented until gate 9.4c")
    }
}

/// Starts one private child group and cancels it when `duration` expires.
/// Unimplemented until gate 9.4c.
pub fn timeout(T: type, I: type(Io, AsyncIo), io: I, duration: Duration, pending: Pending(T)) -> Result(T, Timeout) {
    panic("std.task.timeout is unimplemented until gate 9.4c")
}

/// Starts both pending calls and returns the first completed result.
/// Unimplemented until gate 9.4c.
pub fn race(T: type, I: type(Io, AsyncIo), io: I, first: Pending(T), second: Pending(T)) -> T {
    panic("std.task.race is unimplemented until gate 9.4c")
}

/// Runs the call on the bounded blocking pool under `AsyncIo` and directly
/// under `BlockingIo`. Unimplemented until gate 9.4c.
pub fn blocking(T: type, I: type(Io), io: I, pending: Pending(T)) -> T {
    panic("std.task.blocking is unimplemented until gate 9.4c")
}

/// Gives the calling task's worker to other runnable tasks.
/// Unimplemented until gate 9.4c.
pub fn yield(I: type(Io, AsyncIo), io: I) -> Unit {
    panic("std.task.yield is unimplemented until gate 9.4c")
}

/// The compiler-internal placeholder that `await task` lowers to.
///
/// The `await` form checks the handle and the group scope, then records the
/// call; the body is a fixed panic until gate 9.4c replaces it with the task
/// handoff. It is module-private, so `await` is the only way to consume a
/// `Task(T)`.
fn await_result(T: type, take task: Task(T)) -> T {
    panic("std.task await is unimplemented until gate 9.4c")
}
