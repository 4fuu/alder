# Alder Async and Structured Concurrency

Design status: **Frozen for Alder 1.0**

Availability: **Not implemented; the current runtime is single-threaded**

Async is a required Alder 1.0 feature, not a post-1.0 option. The design uses
familiar `async fn` and `await` with task groups that bound every child task's
lifetime. It does not add hidden shared mutable state or detached tasks.

## Async functions

```alder
async fn load_user(id: User.Id) -> Result(User, LoadError) {
    let response = try await http.get("/users/{id}")
    let user = try response.json(User)
    return Ok(user)
}
```

An async call starts only in an `await` or task-group `spawn` context. Alder
does not expose a freely droppable implicit future from a bare async call.
`await` is valid only in an `async fn` and returns the declared result type
exactly.

Copyable arguments are snapshotted into async state. An affine input must use a
`take` parameter because an async body can outlive the initiating call frame.
Borrowed affine parameters and mutable scoped capabilities cannot cross an
`await` unless the compiler proves they remain local and unaliased; the 1.0
portable rule rejects such suspension by default.

Async lowering produces verified state-machine MIR before C generation. It
does not depend on C stackful coroutines, undefined long jumps, or platform C
evaluation order.

## Task groups

Concurrency is created through an affine `TaskGroup` owner:

```alder
async fn load_pair(a: Url, b: Url) -> Result(Pair, HttpError) {
    using tasks = TaskGroup.new()
    let left = tasks.spawn(http.get(a))
    let right = tasks.spawn(http.get(b))

    let left_response = try await left
    let right_response = try await right

    return Ok(Pair(
        left: left_response,
        right: right_response,
    ))
}
```

`spawn` consumes one pending async call and returns an affine, group-scoped
`Task(T)`. Awaiting a handle consumes it and yields `T`. A task handle cannot
escape its group and must be awaited on every normal path. For child work that
has no result, `start` accepts only a pending operation returning `Unit` and
returns `Unit`; the group tracks and joins that child without a user handle.

On normal group exit, every `Task(T)` has been consumed and all `start` children
are joined. On `return`, failed `try`, or parent cancellation, outstanding
handles and started children receive cancellation and the group waits for their
cleanup before the parent leaves. A group therefore never leaves live children
behind. `TaskGroup` implements `AsyncCleanup`, so this join may suspend during
`using` teardown without blocking an executor worker.

There is no implicit detached task API in Alder 1.0. A server keeps a lexical
group alive for its service lifetime and creates bounded child groups per
request or connection. Long-lived background work is represented by an
explicit service owner joined during shutdown, not fire-and-forget syntax.

## Failure and cancellation

Ordinary task failure is the task's declared return value, normally
`Result(T, E)`. `await Task(Result(T, E))` yields that same `Result(T, E)`; it
does not add a nested scheduler error.

Cancellation is a structured control effect, not a catchable exception. It is
observed at `await`, async I/O, channel operations, sleeps, and explicit
cancellation checkpoints. Cancellation runs the task's normal `using` cleanup
and then completes it without a user result. Its parent is already leaving, so
no fabricated `T` is required.

Runtime task cancellation begins only when the parent is already taking an
exiting control path, or inside a standard combinator that owns, cancels, and
joins its private children. Alder 1.0 has no `Task.cancel` and no operation that
leaves normal user code holding an awaitable handle with no possible `T`.
Awaiting a task canceled by an already-exiting group cannot produce a value
because the awaiting parent is on that same exit path. User-facing timeout and
race operations do not expose the canceled child handle: they cancel and join
the losing child internally, then return an explicit timeout/race result.

Application-requested cooperative cancellation uses a scoped
`CancellationToken`. APIs accepting it report cancellation through their
documented ordinary result, usually a `Cancelled` error variant; the token does
not erase a task's declared result type or permit a child to outlive its group.

Timeout and race APIs wrap this behavior in explicit values:

```alder
let timed = await task.timeout(Duration.seconds(5), http.get(url))
let response = match timed {
    Ok(result) => try result
    Err(Timeout) => retry()
}
use(response)
```

`timeout(duration, pending T)` produces `Result(T, Timeout)`, so an operation
whose declared result is itself `Result(U, E)` remains explicitly nested. It
does not merge unrelated error types or hide the operation's ordinary result.

An invariant panic, runtime contract violation, or infallible OOM terminates
the process. It is not converted into a task error and does not promise task or
caller cleanup.

## Isolation and data races

Spawned tasks receive independent copies of ordinary values. Passing an affine
owner to a task requires the callee's visible `take` parameter and transfers
the owner before scheduling. Mutable locals, mutable slices, table views, lock
guards, and raw C borrows are never implicitly shared.

The compiler derives task-transfer safety structurally. Safe code cannot assert
an incorrect marker implementation. Values containing raw pointers, local C
thread affinity, or scoped capabilities require an explicit safe wrapper or
remain local.

Shared communication uses standard scoped owners:

- bounded and unbounded `Channel(T)` with group-scoped sender/receiver
  capabilities;
- `Shared(T)` with affine lock guards;
- fixed-width atomics with explicit memory-order operations;
- immutable copied values.

The task group owns channel and shared-state storage. Capabilities cannot
outlive it, so the implementation does not need universal ARC merely to manage
structured concurrency. A closed channel and cancellation are explicit
results/control effects, never dangling access.

Safe task code is data-race-free. Race freedom does not impose deterministic
completion order. Programs that communicate through channels observe the
channel's documented FIFO rules; independent external effects may occur in any
scheduler order.

## Executors

The hosted 1.0 runtime supplies:

- a multithreaded executor for structurally transferable tasks;
- a local executor lane for thread-affine tasks and platform event sources;
- timers, cancellation, wakeups, async files where supported, sockets, DNS,
  subprocess waiting, and channels;
- a bounded blocking-work pool for operations that cannot be made async.

The runtime may choose worker counts from host capabilities, with a standard
configuration API for applications and tests. Scheduling policy is not part of
program semantics. Tests can select a deterministic single-worker executor;
production code must not depend on that order.

No executor uses a tracing GC. Task frames and group-owned shared state live in
compiler/runtime-managed domains and are reclaimed when the owning task/group
finishes. Async cleanup runs in a cancellation-shielded teardown state so a
group can join children and release resources; it may still terminate the
process on an invariant failure and cannot make a permanently stuck foreign
operation cancellable.

## Blocking work and C

Potentially blocking work must not occupy an async executor worker
indefinitely. The standard API takes a named function and explicit independent
arguments:

```alder
let data = await tasks.blocking(read_with_legacy_c, path)
```

The blocking operation runs on the bounded blocking pool. Arguments are copied
or explicitly transferred under the same task rules. Cancellation stops
waiting for a queued operation when possible, but cannot unsafely interrupt an
arbitrary C function already executing. The group retains the operation's
state until C returns, and wrapper cleanup follows the binding contract.

Retained C callbacks use explicit callback owners and may wake tasks only
through the runtime's thread-safe callback bridge. C thread-safety and
cancellation claims are trusted binding/wrapper obligations. See
[C Interoperability](c-interop.md).

## Async standard-library baseline

Alder 1.0 includes async variants for timers, TCP/UDP, DNS, subprocess wait and
pipes, file operations on supported hosts, channels, HTTP, and TLS. An API whose
host implementation is blocking uses the bounded blocking pool without
changing its safe result contract. Synchronous variants remain available for
small tools and bootstrap code.

## Required evidence

The 1.0 async gate requires tests for:

- state-machine lowering and repeated deterministic compilation;
- nested groups, normal join, early return, failed `try`, and cancellation;
- reverse cleanup order before a canceled child completes;
- channel close, backpressure, FIFO behavior, and cancellation races;
- lock exclusion and compiler rejection of unsafe shared captures;
- local/thread-affine and multithread transfer rejection/acceptance;
- blocking C completion after parent cancellation without use after free;
- high task counts with bounded stack and compiler/runtime storage;
- sanitizer and race-detector coverage on supported hosts.
