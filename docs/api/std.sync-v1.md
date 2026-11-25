# `std.sync` Public Signature Snapshot v1

Status: **Milestone 9 frozen snapshot; not implemented**

This is the versioned public snapshot for group-scoped shared state. It is
normative together with the executable example
`examples/std.sync-v1.al`, which lands in the module's implementation
commit: the docs example runner resolves installed sysroot modules, so the
file cannot precede the module. The module lives at
`<sysroot>/std/sync.al` and is imported explicitly; it is not part of the
prelude.

The module implements the shared-state half of
[Async and Structured Concurrency](../async.md): a reader-writer shared slot,
affine lock guards, one-time initialization, and a reusable barrier. The
[cross-cutting async rules](std.task-v1.md#cross-cutting-async-rules) and
[spelling choices](std.task-v1.md#v1-spelling-choices) apply; this file does
not restate them.

## Signatures

```alder
module std.sync

import std.io { AsyncIo, Io }
import std.task { TaskGroup }

/// A synchronization configuration error.
pub enum SyncError {
    /// A barrier was requested with zero parties.
    InvalidParties
}

/// A one-time-initialization error.
pub enum InitError {
    /// Another task initialized the value first.
    AlreadyInitialized
}

/// Copyable, portable, group-scoped reader-writer shared slot.
pub type Shared(T: type) {
    // private: slot
}

/// Affine, local exclusive guard over one `Shared(T)` slot.
pub type LockGuard(T: type) {
    // private: slot, held
}

/// Affine, local shared guard over one `Shared(T)` slot.
pub type ReadGuard(T: type) {
    // private: slot, held
}

/// Copyable, portable, group-scoped one-time slot.
pub type Once(T: type) {
    // private: slot
}

/// Copyable, portable, group-scoped reusable barrier.
pub type Barrier {
    // private: state
}

impl(T: type) Shared(T) {
    /// Stores `value` in group-owned storage.
    fn new(I: type(Io, AsyncIo), group: TaskGroup(I), take value: T) -> Shared(T)
    /// Exclusive access; excludes every other guard on the same slot.
    fn lock(self) -> LockGuard(T)
    /// Shared access; overlaps other read guards and excludes `lock`.
    fn read(self) -> ReadGuard(T)
}

impl(T: type) LockGuard(T) {
    /// A one-element mutable view of the guarded slot, scoped to this guard.
    fn borrow(mut self) -> MutSlice(T)
}

impl(T: type) ReadGuard(T) {
    /// A one-element immutable view of the guarded slot, scoped to this guard.
    fn borrow(self) -> [T]
}

impl(T: type) Cleanup for LockGuard(T)
impl(T: type) Cleanup for ReadGuard(T)

impl(T: type) Once(T) {
    fn new(I: type(Io, AsyncIo), group: TaskGroup(I)) -> Once(T)
    fn is_initialized(self) -> Bool
    /// Stores `value` when uninitialized; otherwise releases it and reports
    /// `AlreadyInitialized`.
    fn initialize(self, take value: T) -> Result(Unit, InitError)
    /// Copies the initialized value; available only for copyable `T`.
    fn get(self) -> Option(T)
}

impl Barrier {
    /// A reusable barrier that releases every waiter each time `parties`
    /// waits have arrived; `parties` must be at least 1.
    fn new(I: type(Io, AsyncIo), group: TaskGroup(I), parties: U64) -> Result(Barrier, SyncError)
    /// Waits for the current generation's last party.
    fn wait(self) -> Unit
}
```

## Contracts

- `Shared(T)` is the reader-writer lock; a plain mutex is the same type with
  only `lock` calls. `lock` is exclusive, `read` is shared, several read
  guards may overlap, and both are potentially suspending when contended.
  Completion order is never made deterministic by lock use.
- A guard is affine and local: it cannot enter a task, be returned, or be
  stored in an escaping aggregate. A guard that is live at a potentially
  suspending call is rejected and the diagnostic names both the guard and
  the call; under `BlockingIo` no call suspends, so the restriction does not
  apply. Guards release only through cleanup, so the ordinary form registers
  one with `using`.
- `Shared` is copyable, portable, and group-scoped; copies share one slot and
  the group releases it after every child has finished, releasing an affine
  `T` exactly once.
- `Once(T)` initializes at most once. The winning call stores the value; a
  losing call reports `AlreadyInitialized` and releases the discarded value
  exactly once. `get` copies the value, so it is available only when `T` is
  copyable; an affine value that must be initialized once is held as
  `Shared(Option(T))` and taken under `lock`.
- `Barrier` is reusable and generation-based: every wait blocks until
  `parties` waits have arrived for the current generation, then all are
  released. `parties` zero is `InvalidParties`. Fairness and arrival order
  are not specified. A canceled waiter unwinds with its group and abandons
  its generation.

## Guard-borrow view rule

`LockGuard.borrow` and `ReadGuard.borrow` form a view from a call result,
which the M7.1 view rules do not allow in general: [`core.slice` v1](core.slice-v1.md)
permits a mutable-view local to be formed only by `slice_mut` or `subview`
from a place, and it does not make a call result a view source. This snapshot
records a Milestone 9 checker and view-rule extension instead of a general
widening:

- only these two guard methods form a view from a call result;
- each call forms exactly one one-element view whose lifetime is scoped to the
  guard binding it was called on, and that view cannot be copied, aliased,
  stored, returned, or moved into another aggregate;
- the guard stays live and immovable until the view dies, and the view dies no
  later than the guard's scope;
- forming any other view from a call result keeps the existing rejection;
- the collection `slice_mut`/`subview` rules, the place requirement, and the
  exclusivity rules are unchanged.

## Example

The example below is the complete content that lands as
`examples/std.sync-v1.al` with the implementation commit. Two children add to
one shared counter under the exclusive guard, one copyable value is initialized
exactly once, and two more children meet at a two-party barrier. Each child
contributes its own post-increment value, and the two values sum to 30 in
either order, so the checksum does not depend on scheduling.

```alder
module hello.std_sync_example

import std.io { AsyncIo, Io }
import std.sync { Barrier, Once, Shared, SyncError }
import std.task { TaskGroup }

// The executable std.sync v1 snapshot example: two workers add to one shared
// counter under the exclusive guard, one value is initialized once, and two
// more children meet at a barrier.

fn add_ten(I: type(Io), io: I, counter: Shared(U64)) -> Result(U64, SyncError) {
    using guard = counter.lock()
    let cell = guard.borrow()
    cell[0] = cell[0] + 10
    return Ok(cell[0])
}

fn meet(I: type(Io), io: I, gate: Barrier) -> Unit {
    gate.wait()
    return
}

pub fn std_sync_example(I: type(Io, AsyncIo), io: I) -> Result(U64, SyncError) {
    using tasks = TaskGroup.new(io)
    let counter: Shared(U64) = Shared.new(tasks, 0)
    let slot: Once(U64) = Once.new(tasks)
    let gate = try Barrier.new(tasks, 2)
    let first = tasks.spawn(add_ten(io, counter))
    let second = tasks.spawn(add_ten(io, counter))
    tasks.start(meet(io, gate))
    tasks.start(meet(io, gate))
    let a = try await first
    let b = try await second
    match slot.initialize(7) {
        Ok(_) => {}
        Err(_) => {}
    }
    var seeded: U64 = 0
    match slot.get() {
        Some(value) => { seeded = value }
        None => {}
    }
    return Ok(a + b + seeded)
}
```

## Dependencies and sequencing

- Milestone 9 gate 9.5 implements this surface together with `std.channel`,
  `std.atomic`, and timers.
- The guard-borrow view rule is new checker work in the same gate; the
  potentially-suspending-call guard rejection depends on gate 9.1.
- The example harness needs a deterministic single-worker `AsyncIo`, the same
  requirement as the [`std.task` example](std.task-v1.md#example).
