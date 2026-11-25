# `std.atomic` Public Signature Snapshot v1

Status: **Milestone 9 frozen snapshot; not implemented**

This is the versioned public snapshot for group-scoped fixed-width atomics. It
is normative together with the executable example
`examples/std.atomic-v1.al`, which lands in the module's implementation
commit: the docs example runner resolves installed sysroot modules, so the
file cannot precede the module. The module lives at
`<sysroot>/std/atomic.al` and is imported explicitly; it is not part of the
prelude.

The module implements the atomic half of
[Async and Structured Concurrency](../async.md): fixed-width integer and
Boolean slots with an explicit memory order on every operation. The
[cross-cutting async rules](std.task-v1.md#cross-cutting-async-rules) and
[spelling choices](std.task-v1.md#v1-spelling-choices) apply; this file does
not restate them.

## Signatures

```alder
module std.atomic

import std.io { AsyncIo, Io }
import std.task { TaskGroup }

/// The memory order of one atomic operation.
pub enum Ordering {
    Relaxed
    Acquire
    Release
    AcqRel
    SeqCst
}

// AtomicBool, AtomicU8, AtomicU16, AtomicU32, AtomicU64, AtomicI8,
// AtomicI16, AtomicI32, and AtomicI64 are copyable, portable,
// group-scoped slots. Each carries the method set written here for
// AtomicU64 with `U64` replaced by its value type, plus
// `fetch_add_wrapping` and `fetch_sub_wrapping` for every integer type
// (never for AtomicBool).
pub type AtomicU64 {
    // private: slot
}

impl AtomicU64 {
    fn new(I: type(Io, AsyncIo), group: TaskGroup(I), value: U64) -> AtomicU64
    fn load(self, order: Ordering) -> U64
    fn store(self, value: U64, order: Ordering) -> Unit
    fn swap(self, value: U64, order: Ordering) -> U64
    fn compare_exchange(self, expected: U64, replacement: U64, success: Ordering, failure: Ordering) -> Result(U64, U64)
    fn fetch_add_wrapping(self, value: U64, order: Ordering) -> U64
    fn fetch_sub_wrapping(self, value: U64, order: Ordering) -> U64
}
```

## Contracts

- Every atomic type is created from a task group, is copyable and portable,
  and is group-scoped: copies refer to one group-owned slot, the slot is
  naturally aligned and has the target's width, and the group releases it
  after every child has finished. There is no standalone or global atomic
  and no pointer atomic in v1.
- Each operation's order is explicit and checked:
  `load` accepts `Relaxed`, `Acquire`, or `SeqCst`; `store` accepts
  `Relaxed`, `Release`, or `SeqCst`; `swap`, `fetch_add_wrapping`,
  `fetch_sub_wrapping`, and `compare_exchange`'s `success` accept any of the
  five; `compare_exchange`'s `failure` accepts `Relaxed`, `Acquire`, or
  `SeqCst` and may not be stronger than `success`. An invalid combination is
  a program invariant failure and terminates through `core.panic.panic`.
- `compare_exchange` compares against `expected` and returns `Ok(previous)`
  on success or `Err(actual)` on failure; it never retries on its own.
  `fetch_add_wrapping` and `fetch_sub_wrapping` return the previous value and
  wrap on the two's-complement pattern, consistent with the named wrapping
  arithmetic of `core.num`; a checked variant is not in v1.
- Atomic operations never suspend and never take a capability. They
  establish ordering only for the slot; they do not make any other shared
  value safe to access without `std.sync` or a channel.
- Fences, atomic floats, 128-bit atomics, and bitwise fetch operations are
  not in v1.

## Example

The example below is the complete content that lands as
`examples/std.atomic-v1.al` with the implementation commit. Two children add
through one group-scoped atomic. Each fetch returns the previous value, and
every previous value 0..9 is returned exactly once across the two children, so
their sum is deterministic regardless of interleaving.

```alder
module hello.std_atomic_example

import std.atomic { AtomicU64, Ordering }
import std.io { AsyncIo, Io }
import std.task { TaskGroup }

// The executable std.atomic v1 snapshot example: two children add through
// one group-scoped atomic, and the parent observes the final value after
// joining both.

fn add_loop(I: type(Io), io: I, cell: AtomicU64, rounds: U64) -> U64 {
    var at: U64 = 0
    var sum: U64 = 0
    while at < rounds {
        sum = sum + cell.fetch_add_wrapping(1, Ordering.Relaxed)
        at = at + 1
    }
    return sum
}

pub fn std_atomic_example(I: type(Io, AsyncIo), io: I) -> U64 {
    using tasks = TaskGroup.new(io)
    let cell = AtomicU64.new(tasks, 0)
    let first = tasks.spawn(add_loop(io, cell, 4))
    let second = tasks.spawn(add_loop(io, cell, 6))
    let a = await first
    let b = await second
    var total: U64 = a + b
    cell.store(100, Ordering.Release)
    match cell.compare_exchange(100, 101, Ordering.AcqRel, Ordering.Acquire) {
        Ok(previous) => { total = total + previous }
        Err(actual) => { total = total + actual }
    }
    return total + cell.load(Ordering.Acquire)
}
```

## Dependencies and sequencing

- Milestone 9 gate 9.5 implements this surface together with `std.channel`,
  `std.sync`, and timers.
- The atomics need the group-owned storage and target-alignment work recorded
  in [the cross-cutting rules](std.task-v1.md#cross-cutting-async-rules),
  plus the C11 atomic surface in the runtime.
- The example harness needs a deterministic single-worker `AsyncIo`, the same
  requirement as the [`std.task` example](std.task-v1.md#example). The
  checksum is interleaving-independent.
