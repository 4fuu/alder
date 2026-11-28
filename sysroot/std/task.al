module std.task

// Milestone 9 gate 9.4 slice C: structured concurrency. TaskGroup owns the
// runtime group record; spawn and start are compiler-lowered operations that
// allocate the child step frame and emit MIR 7 task.spawn; await is a park
// point whose resume copies the child result and releases the child.
// `Cancellation`'s source side is complete and runs under any capability.
// `CancellationToken` shared state remains the source-scoped capability
// category work of gate 9.4d.

import core.panic { panic }
import std.io { AsyncIo, Io }
import std.time { Duration }

import c "std/c/task_shim.h" as taskrt {
    raw fn group_new = "task_group_new"() -> c.ULongLong
    raw fn group_cancel = "task_group_cancel"(group: c.ULongLong) -> Unit
    raw fn group_next = "task_group_next"(group: c.ULongLong) -> c.ULongLong
    raw fn group_release = "task_group_release"(group: c.ULongLong) -> Unit
    raw fn cancel = "task_cancel"(child: c.ULongLong) -> Unit
    raw fn await_parkable = "task_await_parkable"(child: c.ULongLong) -> c.Int
    raw fn release_spawned = "task_release_spawned"(child: c.ULongLong) -> Unit
    raw fn yield_current = "task_yield_current"() -> Unit
}

import c "alder.h" as runtime {
    raw fn park = "alder_task_park"() -> Unit
}

/// Affine owner of one executor-backed task group.
///
/// The capability and child registry are private, and the group's `Cleanup`
/// hook joins every child before the owning scope exits.
pub type TaskGroup(I: type(Io, AsyncIo)) {
    capability: I
    group: U64
}

/// Affine, group-scoped handle to one spawned child.
///
/// The handle is local to the group and is consumed by `await`; it cannot be
/// returned, stored in an escaping aggregate, or awaited outside its group
/// scope.
pub type Task(T: type) {
    child: U64
    out_offset: U64
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
/// that owns its source. The skeleton leaves the shared state to gate 9.4d,
/// because a copyable value cannot observe an affine source until the
/// source-scoped capability category exists.
pub type CancellationToken {
}

impl(I: type(Io, AsyncIo)) TaskGroup(I) {
    /// Creates a group on the executor carried by `io`.
    fn new(io: I) -> TaskGroup(I) {
        let handle = unsafe c { taskrt.group_new() }
        let group: U64 = handle.to_u64()
        return TaskGroup(capability: io, group: group)
    }

    /// Starts the direct call's body as a child and returns its handle. The
    /// compiler lowers the call; the pending argument is never evaluated here.
    fn spawn(T: type, mut self, pending: Pending(T)) -> Task(T) {
        panic("std.task.TaskGroup.spawn is lowered by the compiler")
    }

    /// Starts a `Unit` child that the group joins without a user handle. The
    /// compiler lowers the call; the pending argument is never evaluated here.
    fn start(mut self, pending: Pending(Unit)) -> Unit {
        panic("std.task.TaskGroup.start is lowered by the compiler")
    }
}

/// Waits for one cancelled child. The park lives in its own step function so
/// the joining function's frame has only call-handoff fields.
fn join_wait(I: type(Io, AsyncIo), io: I, child: U64) -> Unit {
    let child_id = child.to_c_ulonglong()
    let ready = unsafe c { taskrt.await_parkable(child_id) }
    let _ = ready
    unsafe c { runtime.park() }
    return
}

/// Joins one child, releases it, and recurses for the next. Recursion keeps
/// every call in a straight-line step segment, so group teardown needs no
/// loop-carried activation value around a suspension point.
fn join_next(I: type(Io, AsyncIo), io: I, group: U64) -> Unit {
    let group_id = group.to_c_ulonglong()
    let next = unsafe c { taskrt.group_next(group_id) }
    let child = next.to_u64()
    if child == 0 {
        unsafe c { taskrt.group_release(group_id) }
        return
    }
    let child_id = child.to_c_ulonglong()
    unsafe c { taskrt.cancel(child_id) }
    join_wait(io, child)
    unsafe c { taskrt.release_spawned(child_id) }
    join_next(io, group)
    return
}

impl(I: type(Io, AsyncIo)) Cleanup for TaskGroup(I) {
    /// Cancels every outstanding child, joins it, and releases its task record
    /// and activation domain. Children are visited newest first, so teardown
    /// follows reverse spawn order.
    fn cleanup(take self) -> Unit {
        let group_id = self.group.to_c_ulonglong()
        unsafe c { taskrt.group_cancel(group_id) }
        join_next(self.capability, self.group)
        return
    }
}

impl(T: type) Cleanup for Task(T) {
    /// Returns the child to its group without waiting. The group owns the
    /// runtime record, so there is no release step here.
    fn cleanup(take self) -> Unit {
        return
    }
}

impl Cancellation {
    /// Creates a cancellation state that no token reports as cancelled yet.
    fn new() -> Cancellation {
        return Cancellation(cancelled: [0])
    }

    /// Mints a token that observes this source's state. Unimplemented until
    /// gate 9.4d installs source-scoped shared state.
    fn token(self) -> CancellationToken {
        panic("std.task.Cancellation.token is unimplemented until gate 9.4d")
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
    /// Unimplemented until gate 9.4d.
    fn is_cancelled(self) -> Bool {
        panic("std.task.CancellationToken.is_cancelled is unimplemented until gate 9.4d")
    }

    /// The ordinary-result form of `is_cancelled`. Unimplemented until gate
    /// 9.4d.
    fn check(self) -> Result(Unit, CancellationError) {
        panic("std.task.CancellationToken.check is unimplemented until gate 9.4d")
    }
}

/// Starts one private child group and cancels it when `duration` expires. The
/// compiler lowers the call.
pub fn timeout(T: type, I: type(Io, AsyncIo), io: I, duration: Duration, pending: Pending(T)) -> Result(T, Timeout) {
    panic("std.task.timeout is lowered by the compiler")
}

/// Starts both pending calls and returns the first completed result. The
/// compiler lowers the call.
pub fn race(T: type, I: type(Io, AsyncIo), io: I, first: Pending(T), second: Pending(T)) -> T {
    panic("std.task.race is lowered by the compiler")
}

/// Runs the call on the blocking pool under `AsyncIo` and directly under
/// `BlockingIo`. The compiler lowers the call.
pub fn blocking(T: type, I: type(Io), io: I, pending: Pending(T)) -> T {
    panic("std.task.blocking is lowered by the compiler")
}

/// Gives the calling task's worker to other runnable tasks.
pub fn yield(I: type(Io, AsyncIo), io: I) -> Unit {
    unsafe c { taskrt.yield_current() }
    unsafe c { runtime.park() }
    return
}

/// The compiler-recognized result access inside `await_result`.
///
/// The declaration types the expression as `T`; lowering replaces the call
/// with the child result view, the copy into this activation's domain, and the
/// child release.
fn take_result(T: type, offset: U64) -> T {
    panic("std.task.take_result is lowered by the compiler")
}

/// Waits for the spawned child and returns its result.
///
/// The registration precedes the park marker, so a child that completed
/// before the park sets the wakeup latch and the park is a no-op. A cancelled
/// child has no result value; the awaiting task is already on its cancellation
/// edge, so the remaining case is a contract violation.
fn await_result(T: type, take task: Task(T)) -> T {
    using t = task
    let child_id = t.child.to_c_ulonglong()
    let _ready = unsafe c { taskrt.await_parkable(child_id) }
    unsafe c { runtime.park() }
    return take_result(T, t.out_offset)
}
