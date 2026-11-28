# `std.task` Public Signature Snapshot v1

Status: **Milestone 9 frozen snapshot; not implemented**

This is the versioned public snapshot for structured concurrency: task groups,
`Pending(T)` operations, group-scoped task handles, and cooperative
cancellation. It is normative together with the executable example
`examples/std.task-v1.al`, which lands in the module's implementation commit:
the docs example runner resolves installed sysroot modules, so the file
cannot precede the module. The module lives at
`<sysroot>/std/task.al` and is imported explicitly; it is not part of the
prelude.

The module implements [Async and Structured Concurrency](../async.md). It adds
no detached task, no `Task.cancel`, no stored `Pending(T)` value, and no
user-asserted transfer category. The other Milestone 9 snapshots link to the
cross-cutting rules and the spelling choices below instead of restating them,
so this file is their one canonical location.

## Cross-cutting async rules

- **Portable** values may move to another task and worker: copyable values
  without thread-affine parts, and affine owners transferred through `take`.
  **Local** values stay on their task: views, mutable capabilities, lock
  guards, raw C borrows, and C-binding values marked thread-affine.
- A `Pending(T)` call may carry only portable arguments and must have a
  portable result. A task containing a thread-affine value runs on the local
  executor lane.
- Shared capabilities minted from a task group (senders, receivers, shared
  slots, one-time slots, barriers, and atomics) are **group-scoped**: they are
  copyable, may be copied and transferred into any child of that group, and
  cannot escape the group's scope. The group releases their storage after
  every child has finished. A `CancellationToken` follows the same rule with
  its `Cancellation` source as the scope. The affine owners (`TaskGroup`,
  `Task(T)`, `Channel(T)`, and `Cancellation`) are local instead. S0 has no
  group-scoped or source-scoped category today; Milestone 9 adds it to the
  checker and MIR as a recorded requirement, not as source syntax.
- `I: type(Io, AsyncIo)` is the bound spelling used throughout, because
  Alder has no supertraits; see
  [the `std.io` Milestone 9 section](std.io-v1.md#milestone-9-addition-evented-and-check_cancel).
- Safe task code is data-race-free. Race freedom does not impose a
  deterministic completion order: only the documented channel FIFO and
  explicit synchronization results are ordered.
- The Milestone 9 module graph is acyclic: `std.task` imports `std.io` and
  `std.time`; `std.channel`, `std.sync`, and `std.atomic` import `std.io` and
  `std.task`; `std.test` gains `SimIo` without new imports.

## Signatures

```alder
module std.task

import std.io { AsyncIo, Io, IoError }
import std.time { Duration }

/// Affine owner of one executor-backed task group.
pub type TaskGroup(I: type(Io, AsyncIo)) {
    // private: capability, child registry
}

/// Affine, group-scoped handle to one spawned child.
pub type Task(T: type) {
    // private: group, child, out_offset (the spawned frame's out field
    // offset, recorded by spawn lowering; gate 9.4c await handoff)
}

/// Declaration-only parameter type of the five standard task operations.
pub type Pending(T: type) {
    // private: never constructed
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
pub type Cancellation {
    // private: state
}

/// Copyable, portable read capability minted from one `Cancellation`.
pub type CancellationToken {
    // private: state
}

impl(I: type(Io, AsyncIo)) TaskGroup(I) {
    /// Creates a group on the executor carried by `io`.
    fn new(io: I) -> TaskGroup(I)
    /// Starts the direct call's body as a child and returns its handle.
    fn spawn(T: type, mut self, pending: Pending(T)) -> Task(T)
    /// Starts a `Unit` child that the group joins without a user handle.
    fn start(mut self, pending: Pending(Unit)) -> Unit
}

impl(I: type(Io, AsyncIo)) Cleanup for TaskGroup(I)
impl(T: type) Cleanup for Task(T)
impl Cleanup for Cancellation

impl Cancellation {
    fn new() -> Cancellation
    fn token(self) -> CancellationToken
    fn cancel(mut self) -> Unit
    fn is_cancelled(self) -> Bool
}

impl CancellationToken {
    fn is_cancelled(self) -> Bool
    fn check(self) -> Result(Unit, CancellationError)
}

pub fn timeout(T: type, I: type(Io, AsyncIo), io: I, duration: Duration, pending: Pending(T)) -> Result(T, Timeout)
pub fn race(T: type, I: type(Io, AsyncIo), io: I, first: Pending(T), second: Pending(T)) -> T
pub fn blocking(T: type, I: type(Io), io: I, pending: Pending(T)) -> T
pub fn yield(I: type(Io, AsyncIo), io: I) -> Unit
```

## Contracts

- `TaskGroup.new(io)` creates the group on the executor carried by `io`. The
  group is affine and its `Cleanup` hook joins children, so its scope exit is
  potentially suspending and does not hold an executor worker while it waits.
  Worker counts are configured on the capability through
  `std.io.ExecutorConfig`, never by a group; the configuration type lives in
  `std.io` because `std.task` depends on the capability, not the reverse.
- `spawn` returns an affine `Task(T)`; `start` accepts only a `Pending(Unit)`
  call and the group joins that child without a handle, so a `start` child
  cannot report an error of its own. Both take their `Pending(T)` argument as
  a direct call to a named function or method, never as a value: the parent
  evaluates the call's arguments in source order, applies the task-transfer
  rules (copyable arguments copied, affine arguments moved only through the
  callee's `take` parameters, views, borrowed owners, and mutable
  capabilities rejected), and starts the body as a child. `Pending(T)`
  appears only in those parameter lists; it cannot be bound, stored,
  returned, or passed anywhere else, and a user declaration that mentions it
  outside a standard task operation is rejected.
- `await` is the only await form: a prefix operator, never a method.
  `await task` consumes a `Task(T)` and yields `T`. `await Task(Result(T, E))`
  yields that same `Result(T, E)` without an added scheduler error, and
  `try await task` composes right-to-left. A `Task(T)` is affine, local, and
  group-scoped: it cannot be returned, stored in an escaping aggregate, or
  awaited outside its group scope, and every normal path consumes it with
  `await`. Its `Cleanup` hook only returns the child to the group and never
  waits; on `return`, a failed `try`, or parent cancellation the group
  cancels outstanding children, joins them, and releases an unclaimed result
  exactly once. On a normal group exit every handle has been consumed and
  every `start` child has been joined.
- `timeout(io, duration, pending T)` starts one private child group, returns
  `Ok(T)` when the child completes within `duration`, and otherwise cancels,
  joins, and returns `Err(Timeout)`. The error type and its single variant
  share the name `Timeout`; match patterns spell the bare variant, and the
  qualified form `Timeout.Timeout` is valid in expression position. An
  operation whose own result is `Result(U, E)` therefore surfaces as
  `Result(Result(U, E), Timeout)`; no error types are merged.
- `race(io, first, second)` starts both pending calls in one private child
  group, returns the first completed `T`, and cancels and joins the other.
  Scheduling decides the winner and no losing value is exposed; a
  completed-but-unclaimed sibling result is released by the group teardown
  exactly once. Two pending arguments is the v1 arity because `Pending(T)`
  values cannot be stored in a collection.
- `blocking(io, pending T)` runs the call on the bounded blocking pool under
  `AsyncIo` and directly under `BlockingIo`. Cancellation stops waiting for a
  queued operation when possible but cannot interrupt an arbitrary C function
  already running; the group retains the operation's state until C returns,
  and wrapper cleanup follows the binding contract.
- `yield(io)` gives the calling task's worker to other runnable tasks of the
  same executor. It is a scheduling hint, not a synchronization point, and
  promises no completion order. `BlockingIo` has no yield.
- Structured cancellation is a control effect, not an exception and not an
  ordinary `Err`. It is observed at potentially suspending calls (`await`,
  capability and channel operations, sleeps) and at `io.check_cancel()`; it
  unwinds the task's frames along the ordinary exit path, runs `using`
  cleanup in reverse order, and completes the task without a user result.
  Parent cancellation begins only on an already-exiting control path, or
  inside a combinator that owns its private children. There is no
  `Task.cancel` and no operation that leaves user code holding an awaitable
  handle with no possible `T`.
- `Cancellation` and `CancellationToken` are the application-level
  cooperative channel used where no group is exiting. `Cancellation.new()`
  takes no capability, so a token works under `BlockingIo` too; `token()`
  mints copyable tokens, `cancel()` marks the state, and `check()` returns
  `Err(CancellationError.Cancelled)` once it is marked. A token is scoped to
  its source: copies may be used and passed into children of a group whose
  scope the source encloses, so reverse cleanup joins the children before the
  source is released, and no copy may escape the source's scope. The source
  is local, so the task that owns it is the one that requests cancellation;
  every token holder observes the result. A token never erases a task's
  declared result type and never lets a child outlive its group.
- `Cancellation` is local; its tokens are portable but source-scoped.
  `TaskGroup`, `Task(T)`, and `Cancellation` are affine; `Pending(T)` is
  never a value.

## Example

The example below is the complete content that lands as
`examples/std.task-v1.al` with the implementation commit. Its entry point is
generic over the capability, and the project harness instantiates it with a
deterministic single-worker `AsyncIo` (`std.test.SimIo.seeded(0)` once the
Milestone 9 test capability lands), so the checksum is deterministic. The
`race` branch adds the same amount for either winner, so the checksum does not
depend on scheduling.

```alder
module hello.std_task_example

import std.io { AsyncIo, Io, IoError }
import std.task { Cancellation, CancellationError, TaskGroup, Timeout, race, timeout }
import std.time { Duration }

// The executable std.task v1 snapshot example. Every pending argument is a
// direct call to a named function.

fn count_byte(I: type(Io), io: I, text: String, needle: U8) -> Result(U64, IoError) {
    var hits: U64 = 0
    let data = text.to_bytes()
    var at: U64 = 0
    while at < data.len() {
        if data.byte(at) == needle { hits = hits + 1 }
        at = at + 1
    }
    return Ok(hits)
}

fn note(I: type(Io), io: I) -> Unit {
    return
}

fn count_pair(I: type(Io, AsyncIo), io: I) -> Result(U64, IoError) {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(count_byte(io, "abracadabra", 97))
    let right = tasks.spawn(count_byte(io, "banana", 110))
    tasks.start(note(io))
    let a = try await left
    let b = try await right
    return Ok(a * 100 + b)
}

fn under_deadline(I: type(Io, AsyncIo), io: I) -> Result(U64, IoError) {
    let timed = timeout(io, Duration.seconds(5), count_byte(io, "aaaa", 97))
    match timed {
        Ok(count) => { return count }
        Err(Timeout) => { return Err(IoError.Unsupported) }
    }
}

pub fn std_task_example(I: type(Io, AsyncIo), io: I) -> U64 {
    var total: U64 = 0
    match count_pair(io) {
        Ok(value) => { total = total + value }
        Err(_) => {}
    }
    match under_deadline(io) {
        Ok(value) => { total = total + value }
        Err(_) => {}
    }
    let winner = race(io, count_byte(io, "aa", 97), count_byte(io, "bbb", 98))
    match winner {
        Ok(count) => {
            if count == 2 || count == 3 { total = total + 4 }
        }
        Err(_) => {}
    }
    using cancel = Cancellation.new()
    let token = cancel.token()
    if !token.is_cancelled() { total = total + 8 }
    match token.check() {
        Ok(_) => { total = total + 16 }
        Err(Cancelled) => {}
    }
    return total
}
```

## v1 spelling choices

Where [Async](../async.md) leaves a narrow spelling open, the Milestone 9
snapshots choose the following and every module uses it consistently. Changing
one is a v1 amendment, not an implementation detail. This list is canonical
for all six Milestone 9 surfaces.

- `await` is a prefix operator and has no method form; `try await task`
  composes right-to-left. `Task(T)` exposes no `await` method.
- `timeout`'s error type is `std.task.Timeout` and its single variant is also
  `Timeout`. Match patterns spell the bare variant (`Err(Timeout)`); the
  qualified form `Timeout.Timeout` is valid in expression position only,
  because S0 match patterns take a bare variant name plus an optional payload
  binding. The timeout call is a free function taking the capability, as in
  `async.md`.
- `race` has arity two and is a free function taking the capability. Its
  result is the winner's `T`; errors are never merged.
- `yield` and `blocking` are free functions taking the capability; `spawn`,
  `start`, and the group constructors are group operations.
- `std.task` owns the cooperative token pair: affine `Cancellation` source,
  copyable source-scoped `CancellationToken`, error `CancellationError` with
  the single variant `Cancelled`. `cancel` takes `mut self`; `token` and
  `is_cancelled` take `self`.
- Channel and shared-state capabilities are copyable and group-scoped;
  `Channel` is the only affine channel type and the only close path.
  `Sender`/`Receiver` copies never close the queue.
- A copyable group-scoped capability takes `self` for operations that change
  shared state, because the handle is unchanged; `mut self` stays reserved
  for affine owners whose own caller-visible state changes.
- `Shared(T)` is both the mutex and the reader-writer lock: `lock` is
  exclusive and `read` is shared. Guards expose the slot through `borrow`,
  which returns a one-element `MutSlice(T)` or `[T]` view.
- `Once(T)` reads by copy only, so an affine value initialized once is held
  as `Shared(Option(T))`.
- `std.atomic.compare_exchange` returns `Result(previous, actual)` rather
  than a Boolean. Integer fetch operations are named
  `fetch_add_wrapping`/`fetch_sub_wrapping`.
- `ExecutorConfig` and `WorkerCount` live in `std.io` beside `Evented`,
  because the task group depends on the capability and the module graph is
  acyclic. The evented executor is one process-wide instance created on first
  use.
- `SimIo` has `new()` (seed 0) and `seeded(seed)`, always one worker, and its
  deadlock diagnostic starts with the fixed line `panic: SimIo deadlock`.
- `Io.check_cancel` returns `Unit` and acts as a cancellation control effect
  rather than returning an `Err`, so a cancellation cannot be caught and
  ignored by user code.

## Dependencies and sequencing

- Milestone 9 gates 9.1 through 9.4 implement this surface: signature-local
  suspension checking, the task runtime, per-instance lowering, and
  `TaskGroup`/`Task(T)`/`Pending(T)`/`await`/`CancellationToken`.
- The example needs one deterministic single-worker `AsyncIo`. Gate 9.2
  supplies a single-worker executor; `std.test.SimIo` (gate 9.7) is the
  intended long-term harness.
- `blocking` depends on the bounded blocking pool from gate 9.6; until then a
  `BlockingIo` instance runs the call directly and an `AsyncIo` instance
  still runs it, with the pool as the target implementation.
- The `std.io` addition this snapshot relies on is recorded in
  [`std.io` v1](std.io-v1.md#milestone-9-addition-evented-and-check_cancel).
