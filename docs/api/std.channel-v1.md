# `std.channel` Public Signature Snapshot v1

Status: **Milestone 9 frozen snapshot; not implemented**

This is the versioned public snapshot for group-scoped FIFO channels. It is
normative together with the executable example
`examples/std.channel-v1.al`, which lands in the module's implementation
commit: the docs example runner resolves installed sysroot modules, so the
file cannot precede the module. The module lives at
`<sysroot>/std/channel.al` and is imported explicitly; it is not part of the
prelude.

The module implements the channel half of
[Async and Structured Concurrency](../async.md): a bounded or unbounded queue,
group-scoped send and receive capabilities, base backpressure, explicit close
results, and cancellation behavior. The
[cross-cutting async rules](std.task-v1.md#cross-cutting-async-rules) and
[spelling choices](std.task-v1.md#v1-spelling-choices) apply; this file does
not restate them.

## Signatures

```alder
module std.channel

import std.io { AsyncIo, Io }
import std.task { TaskGroup }

/// The channel's operational result.
pub enum ChannelError {
    /// A bounded channel was requested with capacity zero.
    InvalidCapacity
    /// The requested direction is closed.
    Closed
}

/// Affine, local owner of one group-scoped FIFO queue.
pub type Channel(T: type) {
    // private: group, queue
}

/// Copyable, portable, group-scoped send capability.
pub type Sender(T: type) {
    // private: queue
}

/// Copyable, portable, group-scoped receive capability.
pub type Receiver(T: type) {
    // private: queue
}

impl(T: type) Channel(T) {
    /// A queue holding at most `capacity` values; `capacity` must be at least 1.
    fn bounded(I: type(Io, AsyncIo), group: TaskGroup(I), capacity: U64) -> Result(Channel(T), ChannelError)
    /// A queue with no limit beyond available memory.
    fn unbounded(I: type(Io, AsyncIo), group: TaskGroup(I)) -> Channel(T)
    fn sender(self) -> Sender(T)
    fn receiver(self) -> Receiver(T)
    /// Closes both directions; queued values stay receivable.
    fn close(take self) -> Unit
}

impl(T: type) Cleanup for Channel(T)

impl(T: type) Sender(T) {
    /// Transfers `value` into the queue, waiting for room when full.
    fn send(self, take value: T) -> Result(Unit, ChannelError)
}

impl(T: type) Receiver(T) {
    /// Takes the front value, waiting for one when empty.
    fn receive(self) -> Result(T, ChannelError)
}
```

## Contracts

- `bounded` rejects capacity zero with `InvalidCapacity`; `unbounded` has no
  capacity limit beyond available memory and is infallible apart from
  allocation failure, which terminates by the ordinary OOM rule.
- FIFO: values leave in the order their sends were accepted. Copies of one
  capability are interchangeable, and the accepted order is the queue's
  linearization; a program that needs a per-producer order uses one sender
  per producer.
- Backpressure: a send on a full bounded queue is a potentially suspending
  call and resumes when a receive frees a slot or the channel closes; a
  receive on an empty queue resumes when a value arrives or the channel
  closes. Neither operation spins and neither has a timeout of its own;
  timeouts come from `std.task.timeout` around the pending call.
- Close is explicit and owner-only. `Channel.close` and the channel's
  cleanup are the only close paths; capability copies never close the queue.
  After close, sends fail with `Closed`, receives drain the values already
  queued, and the next receive fails with `Closed`. Queued values are never
  discarded by close.
- Cancellation: a blocked send or receive is a potentially suspending call;
  structured group cancellation unwinds it without a result and releases the
  capability copy. A closed channel is an ordinary `Err`, never a
  cancellation.
- `Channel` is affine and local: only the owning task closes it and it does
  not enter a child. `Sender(T)` and `Receiver(T)` are copyable, portable,
  and group-scoped. The capability owns no `T`, so its category does not
  depend on `T`; `send` transfers with `take` and `receive` returns the owned
  value. A queued affine value that is never received is released by the
  group teardown exactly once.
- `try_send`, `try_receive`, `len`, and `capacity` are not in v1. There is no
  polling form: a consumer either waits on `receive` or is canceled by its
  group's exit.

## Example

The example below is the complete content that lands as
`examples/std.channel-v1.al` with the implementation commit. It runs one
bounded queue at capacity two with one producer and one consumer, so the
producer blocks on backpressure twice and the consumer observes FIFO order.
The annotated constructor result supplies `T = U64` and the concrete
capability type, because an associated constructor on a generic type has no
receiver value to infer from.

```alder
module hello.std_channel_example

import std.channel { Channel, ChannelError, Receiver, Sender }
import std.io { AsyncIo, Io }
import std.task { TaskGroup }

// The executable std.channel v1 snapshot example: one bounded queue, one
// producer, one consumer, backpressure at capacity two, and explicit close.

fn open_channel(I: type(Io, AsyncIo), tasks: TaskGroup(I)) -> Result(Channel(U64), ChannelError) {
    return Channel.bounded(tasks, 2)
}

fn produce(I: type(Io), io: I, out: Sender(U64), count: U64) -> Result(Unit, ChannelError) {
    var value: U64 = 0
    while value < count {
        try out.send(value + 1)
        value = value + 1
    }
    return Ok(())
}

fn consume(I: type(Io), io: I, source: Receiver(U64), count: U64) -> Result(U64, ChannelError) {
    var total: U64 = 0
    var taken: U64 = 0
    while taken < count {
        let value = try source.receive()
        total = total + value
        taken = taken + 1
    }
    return Ok(total)
}

pub fn std_channel_example(I: type(Io, AsyncIo), io: I) -> Result(U64, ChannelError) {
    using tasks = TaskGroup.new(io)
    using channel = try open_channel(tasks)
    let producer = tasks.spawn(produce(io, channel.sender(), 4))
    let worker = tasks.spawn(consume(io, channel.receiver(), 4))
    try await producer
    let total = try await worker
    channel.close()
    return Ok(total)
}
```

## Dependencies and sequencing

- Milestone 9 gate 9.5 implements this surface together with `std.sync`,
  `std.atomic`, and timers.
- `Channel` storage is group-owned, so the module depends on the group-scoped
  capability category recorded in
  [the cross-cutting rules](std.task-v1.md#cross-cutting-async-rules).
- The example harness needs a deterministic single-worker `AsyncIo`, the same
  requirement as the [`std.task` example](std.task-v1.md#example).
