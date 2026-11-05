# Alder Async and Structured Concurrency

Design status: **Frozen for Alder 1.0** (coloring amended by
[D012](design-decisions.md#d012--structured-concurrency-with-per-instance-suspension))

Availability: **Not implemented; the current runtime is single-threaded**

Structured concurrency is a required Alder 1.0 feature. Alder has no `async fn`
color. A function that may wait on the host receives an explicit I/O
capability through a compile-time type parameter. Each monomorphized instance
is lowered as ordinary direct code when its capability never suspends and as a
verified state machine when it does. One source function therefore serves
blocking tools, the bootstrap, and evented servers.

Task groups bound every child task's lifetime. There is no hidden shared
mutable state and no detached task.

## The I/O capability

Every operation that waits on the host or observes host nondeterminism goes
through an I/O capability value: files, standard streams, sockets, DNS,
processes, sleeps, clocks, OS randomness, channels, and task joins. Pure
computation, formatting, collections, and seeded random generators do not.

Three static traits describe capabilities:

- `Io` declares the operation surface. Code bounded only by `Io` must assume
  that every operation may suspend.
- `BlockingIo` marks an implementation that never suspends; waiting blocks the
  calling OS thread.
- `AsyncIo` marks an implementation that suspends through an executor.

`BlockingIo` and `AsyncIo` both require `Io`, and no type implements both. The
standard library provides `std.io.Blocking` (no executor) and
`std.io.Evented` (the hosted executor). `std.test.SimIo` is a deterministic
`AsyncIo` used by tests. Capability values are copyable tokens; the runtime
that issued them outlives every program task.

```alder
fn word_count(I: type, io: I, path: Path) -> Result(U64, IoError)
where I: Io {
    let text = try std.fs.read_text(io, path)
    return Ok(count_words(text))
}
```

`word_count(blocking, path)` lowers to direct C calls.
`word_count(evented, path)` suspends at the file operation. The two instances
produce the same results; only the waiting mechanism differs. Leading type
arguments are inferred from `io` as usual.

## Potentially suspending calls

A type is a *suspending capability type* when it is a type parameter bounded
by `Io` but not `BlockingIo`, a concrete type implementing `AsyncIo`, or a
record, enum, or applied generic containing such a type. A call is
*potentially suspending* when the callee's signature, including its receiver,
has a parameter of a suspending capability type, or when it is `await`. Scope
exit is potentially suspending when it runs a cleanup hook whose receiver has
a suspending capability type.

This rule reads only signatures and the current function's bounds, so checking
stays local and finishes before monomorphization. No instance is rejected later
because of how it was instantiated.

Across a potentially suspending call:

- arguments, including views and borrowed owners, stay valid. The suspended
  caller's frame lives in task storage and is never relocated, so no pinning
  concept exists;
- a lock guard from `std.sync`, a raw C borrow, and a thread-affine value
  cannot stay live, because another task may run on the same worker or the
  task may move to another worker. The diagnostic names the guard and the
  call that may suspend.

Under `BlockingIo` no call suspends, so these restrictions do not apply.
Tooling (`alder ide hover`, the LSP) marks potentially suspending calls.

## Lowering

Monomorphization happens before backend MIR. An instance whose concrete
capability types are all `BlockingIo` lowers to ordinary direct MIR. Any other
instance lowers to state-machine MIR: each potentially suspending call becomes
a suspension point, and frames are allocated in task storage. Recursion is
allowed under one concrete capability; each recursive call allocates its frame
in task storage. Recursion that changes the capability type is
specialization-expanding and already rejected.

Lowering does not depend on stackful coroutines, `setjmp`/`longjmp`, or
platform C evaluation order. The exact MIR representation is an
[open question](open-questions.md#exact-mir-representation-for-async-suspension).

## Function values, closures, and C callbacks

Function values `fn(A) -> R` never suspend. A closure body or a function used
as a function value cannot contain a potentially suspending call. This keeps
one calling convention for function values and keeps them usable as C
callbacks.

An API that needs a suspending callback accepts a named function through a
compile-time parameter plus explicit arguments, or a `Pending(T)` call (below).
C callbacks use explicit callback owners and wake tasks only through the
runtime's thread-safe callback bridge. A suspending instance is never a C
callback.

## Task groups

Concurrency is created through an affine `TaskGroup(I)` owner, which requires
`I: AsyncIo`:

```alder
fn load_pair(I: type, io: I, a: Url, b: Url) -> Result(Pair, HttpError)
where I: AsyncIo {
    using tasks = TaskGroup.new(io)
    let left = tasks.spawn(http.get(io, a))
    let right = tasks.spawn(http.get(io, b))

    let left_response = try await left
    let right_response = try await right

    return Ok(Pair(
        left: left_response,
        right: right_response,
    ))
}
```

`spawn`, `start`, `timeout`, `race`, and `blocking` take a `Pending(T)`
parameter. Its argument must be a direct call to a named function or method.
The parent evaluates the call's arguments in source order and transfers them
under the task-transfer rules; the call body then runs as the child. Copyable
arguments are copied, affine arguments move only through the callee's `take`
parameters, and borrowed owners, views, and mutable capabilities are rejected
because the child runs concurrently with the parent. Only standard task
operations accept `Pending(T)` in Alder 1.0, and a `Pending(T)` value cannot be
stored.

`spawn` returns an affine, group-scoped `Task(T)`. `await task` consumes the
handle and yields `T`; it is the only `await` form. A task handle cannot escape
its group and must be awaited on every normal path. `start` accepts only a
pending call returning `Unit`; the group tracks and joins that child without a
user handle.

On normal group exit, every `Task(T)` has been consumed and all `start`
children are joined. On `return`, failed `try`, or parent cancellation,
outstanding handles and started children receive cancellation and the group
waits for their cleanup before the parent leaves. A group therefore never
leaves live children behind. The group's `Cleanup` hook joins children, so its
scope exit is potentially suspending and does not block an executor worker.

There is no detached task API in Alder 1.0. A server keeps a lexical group
alive for its service lifetime and creates bounded child groups per request or
connection. Long-lived background work is represented by an explicit service
owner joined during shutdown, not fire-and-forget syntax.

## Failure and cancellation

Ordinary task failure is the task's declared return value, normally
`Result(T, E)`. `await Task(Result(T, E))` yields that same `Result(T, E)`; it
does not add a nested scheduler error.

Cancellation is a structured control effect, not a catchable exception. It is
observed only at potentially suspending calls: capability operations,
`await`, channel operations, sleeps, and the explicit `io.check_cancel()`
checkpoint for long CPU-bound loops. Cancellation leaves the task's frames
along the ordinary exit path, runs their `using` cleanup in reverse order, and
completes the task without a user result. Its parent is already leaving, so no
fabricated `T` is required.

Runtime task cancellation begins only when the parent is already taking an
exiting control path, or inside a standard combinator that owns, cancels, and
joins its private children. Alder 1.0 has no `Task.cancel` and no operation that
leaves normal user code holding an awaitable handle with no possible `T`.
Awaiting a task canceled by an already-exiting group cannot produce a value
because the awaiting parent is on that same exit path. Timeout and race
operations do not expose the canceled child: they cancel and join the losing
child internally, then return an explicit result.

Application-requested cooperative cancellation uses a scoped
`CancellationToken`. APIs accepting it report cancellation through their
documented ordinary result, usually a `Cancelled` error variant; the token does
not erase a task's declared result type or permit a child to outlive its group.
Tokens also work under `BlockingIo`, which has no structured task
cancellation.

```alder
let timed = std.task.timeout(io, Duration.seconds(5), http.get(io, url))
let response = match timed {
    Ok(result) => try result
    Err(Timeout) => retry()
}
use(response)
```

`timeout(io, duration, pending T)` produces `Result(T, Timeout)`, so an
operation whose declared result is itself `Result(U, E)` remains explicitly
nested. It does not merge unrelated error types or hide the operation's
ordinary result.

An invariant panic, runtime contract violation, or infallible OOM terminates
the process. It is not converted into a task error and does not promise task or
caller cleanup.

## Isolation and data races

Each value has a transfer category that the compiler derives structurally:

- **portable** values may move to another task and another worker: copyable
  values without thread-affine parts, and affine owners passed through `take`;
- **local** values must stay on their task: views, mutable capabilities, lock
  guards, raw C borrows, and values marked thread-affine by a C binding
  wrapper.

A `Pending(T)` call may carry only portable arguments, and its result must be
portable. A task containing a thread-affine value runs on the local executor
lane. Safe code cannot assert a category; values containing raw pointers,
local C thread affinity, or scoped capabilities require an explicit safe
wrapper or remain local.

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

`std.io.Evented` supplies:

- a multithreaded executor for portable tasks;
- a local executor lane for thread-affine tasks and platform event sources;
- timers, cancellation, wakeups, async files where supported, sockets, DNS,
  subprocess waiting, and channels;
- a bounded blocking-work pool for operations that cannot be made async.

The runtime may choose worker counts from host capabilities, with a standard
configuration API for applications and tests. Scheduling policy is not part of
program semantics.

`std.test.SimIo` runs every task of a test on one worker with a virtual clock.
The clock advances only when every task is blocked on time; a state where every
task is blocked and no timer is pending fails the test and lists the blocked
tasks. Production code must not depend on its order.

No executor uses a tracing GC. Task frames and group-owned shared state live in
compiler/runtime-managed domains and are reclaimed when the owning task/group
finishes. Cleanup during cancellation runs in a cancellation-shielded teardown
state so a group can join children and release resources; it may still
terminate the process on an invariant failure and cannot make a permanently
stuck foreign operation cancellable.

## Blocking work and C

Potentially blocking C must not occupy an executor worker indefinitely. The
standard API takes a pending call:

```alder
let data = std.task.blocking(io, read_with_legacy_c(path))
```

Under `AsyncIo` the call runs on the bounded blocking pool; under `BlockingIo`
it runs directly. Arguments follow the task-transfer rules. Cancellation stops
waiting for a queued operation when possible, but cannot unsafely interrupt an
arbitrary C function already executing. The group retains the operation's
state until C returns, and wrapper cleanup follows the binding contract. See
[C Interoperability](c-interop.md).

## One standard library for every capability

Standard I/O, networking, HTTP, TLS, process, and time APIs are written once
against `I: Io`. Bootstrap code and small tools instantiate `std.io.Blocking`
and need no executor; hosted servers instantiate `std.io.Evented`. There is no
separate synchronous and asynchronous API surface. Task groups, channels, and
`Shared(T)` require `AsyncIo`.

## Required evidence

The 1.0 async gate requires tests for:

- direct lowering of `BlockingIo` instances and state-machine lowering of
  `AsyncIo` instances of the same source, with identical results;
- rejection of lock guards, raw C borrows, and thread-affine values live across
  a potentially suspending call, and of suspending calls in closures;
- repeated deterministic compilation;
- nested groups, normal join, early return, failed `try`, and cancellation;
- reverse cleanup order before a canceled child completes;
- channel close, backpressure, FIFO behavior, and cancellation races;
- lock exclusion and rejection of non-portable `Pending(T)` arguments;
- local-lane and multithread transfer acceptance and rejection;
- blocking C completion after parent cancellation without use after free;
- high task counts and deep recursion with bounded stack and measured task
  storage;
- `SimIo` virtual time, quiescence, and deadlock reporting;
- measured code size of dual-instance standard-library code;
- sanitizer and race-detector coverage on supported hosts.
