# Alder Memory and Resources

Design status: **Frozen for Alder 1.0**

Availability: **MIR/runtime mechanisms exist; the source model and inference are not implemented**

Alder separates ordinary data, resource ownership, scoped access, and
long-lived identity. It does not force one ownership mechanism onto every
value, use tracing GC, or introduce hidden universal ARC.

## Ordinary values

Primitives, records, enums, strings, bytes, arrays, vectors, maps, sets, and
other structures made only from ordinary values have value semantics.
Assignment, parameter passing, closure capture, and return create an
observationally independent value.

The implementation may avoid physical copies through destination construction,
copy elision, uniqueness, immutable sharing, or copy-on-write. It may not make
later mutation of one value visible through another value. Potentially large
cross-domain copies must be visible to compiler diagnostics or profiling.

There is no routine source-invalidating `move` operation. This semantic choice
does not require eager deep copies.

### In-place update of uniquely owned values

A mutating collection or builder operation updates its target in place when
the compiler proves the target's storage uniquely owned at that point: no other
live binding, closure capture, task argument, or view refers to it. Otherwise
the operation first copies. Uniqueness is a static fact derived from bindings,
view liveness, and storage placement; there is no reference count and no
runtime uniqueness test. Assignment followed by mutation of only one side, a
value passed to a function and then dead in the caller, and a loop that
rebuilds a local collection are the cases the analysis must prove.

The rule never changes observable values. It is a cost contract: tooling
reports every copy site that remains, with its reason (for example "`items` is
still used at line 40"), and the performance suite pins in-place behavior for
representative programs, because a silently lost in-place update can turn a
linear loop quadratic. See
[D023](design-decisions.md#d023--uniquely-owned-values-update-in-place).

## Affine owners

Types that represent exactly-once external state are affine. The initial set
includes:

- files, sockets, subprocesses, locks, transactions, and OS handles;
- `Table(T)` and identity-owning containers;
- owned foreign pointers and retained callback registrations;
- task groups and comparable structured-concurrency owners;
- records or enums containing an affine owner.

An affine value has one owning binding. It cannot be copied, implicitly
dropped, or overwritten. An ordinary parameter borrows it for the duration of
the call; `mut` grants exclusive call access; `take` on a parameter transfers
ownership. A call to a `take` parameter consumes the caller's binding based on
the callee's visible signature. Returning an owner transfers it to the caller.

This is deliberately not a general move-oriented object model. Ownership is
visible only at resource and identity boundaries.

## Scoped capabilities

Slices, mutable slices, table views, lock guards, and C borrows are capabilities
whose validity is tied to an owner or storage domain.

- `[T]` is an immutable contiguous view.
- `MutSlice(T)` is an exclusive mutable contiguous view.
- `Table(T).get` produces a scoped immutable table view.
- `Table(T).get_mut` produces a scoped exclusive table view.
- lock acquisition produces an affine guard whose cleanup releases the lock.

A view is formed only from a place: a binding, a field or element path of a
binding, or a parameter. It is never formed from a call result or another
temporary, which therefore cannot dangle. A caller that needs a view of a
temporary binds it first.

A capability cannot be used after reset, owner mutation that invalidates it,
table removal, unlock, task-group exit, or foreign release. Mutable capability
scopes are exclusive. The compiler rejects escaping or overlapping accesses
when it cannot prove validity.

No public lifetime parameter syntax is required. For immutable views derived
from copyable values, inferred result storage may keep the immutable backing
alive in the caller. A view derived from an affine owner cannot outlive the
verified owner access scope. When inference cannot prove an early end, it keeps
storage alive longer rather than accepting a dangling view.

## Inferred storage domains

The compiler groups ordinary allocations into hierarchical storage domains.
Functions, loops, task groups, requests, and selected containers create
candidate boundaries. Placement chooses the smallest domain proven to outlive
all uses.

```diagram
┌───────────────────────────────┐
│ caller/request domain         │
│  returned values              │
│  ┌─────────────────────────┐  │
│  │ function domain         │  │
│  │ parser tree and buffers │  │
│  │  ┌───────────────────┐  │  │
│  │  │ loop segment      │  │  │
│  │  │ iteration scratch │  │  │
│  │  └───────────────────┘  │  │
│  └─────────────────────────┘  │
└───────────────────────────────┘
```

If the compiler cannot prove that an allocation belongs in an inner domain,
it retains it in the nearest safe outer domain. The fallback may consume more
memory but cannot produce use after free. The compiler must diagnose or profile
material retention and cross-domain copies; it does not silently switch the
program to per-object reference counting.

Placement and view checking track individual fields and element paths, and
judge a view by its actual later uses rather than its lexical scope, so a
borrow of one field does not retain or lock its siblings. Precision here
directly reduces retention and needs no source syntax.

The placement analysis is a finite monotone constraint problem over stable
candidate-domain and allocation IDs. A placement starts at its innermost
candidate and moves only toward ancestors until it outlives direct uses, view
uses, and dependent allocations. An unproved lifetime contributes an explicit
root-retention constraint and a stable retention record; it is not interpreted
as permission to keep an inner placement. Candidate domains use
parent-before-child order, and dependency propagation uses stable input order,
so equivalent inputs produce identical plans independent of map iteration or
process scheduling. A view proven invalidated before use is rejected rather
than made apparently valid by retaining its backing allocation. M7.3 slices 1
and 2 implement this analysis boundary and connect deterministic checked-source
facts to inferred-domain MIR lowering. Ordinary calls nest function domains
under caller-result domains; result copies and direct immutable-view
materialization target the nearest caller-visible domain before inner storage
is destroyed.

Domains may use resettable segments, dedicated large-object segments, caller
result segments, and container-owned segments. The exact segmentation strategy
is an implementation choice so long as observable value, cleanup, and OOM
semantics remain unchanged.

## Collections and text

The 1.0 owned/view distinction is:

| Type | Category | Contract |
|---|---|---|
| `String` | ordinary value | immutable valid UTF-8; no integer character indexing |
| `StringBuilder` | ordinary value | mutable UTF-8 construction with validation |
| `Bytes` | ordinary value | immutable arbitrary bytes |
| `BytesBuilder` | ordinary value | mutable byte construction |
| `Array(T, N)` | ordinary value | fixed length known at compile time |
| `[T]` | scoped capability | immutable contiguous view |
| `MutSlice(T)` | scoped capability | exclusive mutable contiguous view |
| `Vec(T)` | ordinary value | growable contiguous value collection |
| `Map(K, V)` | ordinary value | insertion-ordered hash map |
| `Set(T)` | ordinary value | insertion-ordered hash set |
| `Table(T)` | affine owner | stable generational identity and independent removal |

`Array`, `Vec`, `Map`, `Set`, `Option`, `Result`, records, and enums propagate
their component category. For example, `Vec(File)` is affine and drains each
owned file exactly once; it is not copyable merely because `Vec(I64)` is. The
table itself is always affine even when `T` is copyable.

`Map` and `Set` iteration follows insertion order. Replacing an existing map
value does not move its key; removing and inserting it again places it at the
end. Hash seeding may vary for attack resistance but cannot change this order.

Copying a mutable collection has value semantics. Implementations may use
copy-on-write, but the first mutation must preserve independence. Collection
growth is geometric with checked size arithmetic; no capacity calculation may
wrap or narrow into C `size_t` unchecked.

Milestone 7.1 implements `Vec(T)` only when `T` is recursively copyable and
uses eager deep copy; the in-place rule above replaces eager copies once
uniqueness facts exist. This temporary restriction keeps ordinary vector APIs
free of transfer and cleanup behavior before Milestone 7.5 implements affine
element composition. M7.3 slice 2 replaces M7.1's single hidden borrowed root
placement with a hidden caller-result domain plus a nested function domain.
The `StoragePlan` chooses result or function placement at material allocation,
growth, and copy sites. Function domains are destroyed on every return,
failure, and panic path; return and failed-`try` values with relocatable storage
are recursively copied to caller-result storage before that destruction.
Identity-bearing resources are not relocatable and retain their real
provenance instead of passing through `copy_to_domain`. M7.3 slice 3
generalizes direct immutable-view results to ordinary aggregates: a record,
enum, `Option`, `Result`, or array result whose scoped parts are all
immutable slices is admitted when every scoped leaf is materializable, and
its view parts are recursively materialized into caller-result storage.
Mutable views and view-holding aggregates stay non-escaping at bindings,
arguments, match scrutinees, and cleanup initializers, so their exclusivity,
overlap, and invalidation checks are unchanged. Domains remain
absent from source APIs and vector representations, and the hosted entry still
owns the outer root. This changes storage lifetime and visible copy cost, not
independent value semantics.

## Generational identity with `Table(T)`

Long-lived identity belongs to a table rather than an interior address:

```alder
type Player {
    name: String
    target: Player.Id?
}

using players = Table.new(Player)
let alice = players.insert(Player(name: "Alice", target: None))
```

`T.Id` is a copyable typed value containing enough table identity, slot, and
generation information to reject stale or cross-table use. Removing a value,
resetting its table storage, or destroying the table makes prior IDs fail to
resolve. Slot reuse never makes an old ID designate a new object.

`get(id)` returns an optional immutable view; `get_mut(id)` returns an optional
exclusive view. A structural table mutation cannot overlap a live view. Graphs
and cycles use IDs, so graph topology does not control memory reclamation.

ID exhaustion is checked and terminates for infallible insertion. A fallible
`try_insert` returns `Result` for programs that must handle exhaustion or
capacity policy explicitly.

## Deterministic cleanup

`using name = expression` accepts an affine type implementing the language's
special `Cleanup` trait. Registrations run at most once in reverse lexical
order.

Cleanup is guaranteed on:

- normal block fallthrough;
- `return`;
- `try` error propagation;
- `break` and `continue` across the resource scope;
- structured task cancellation and task-group exit.

An invariant panic aborts the process and does not promise caller-frame
unwinding. OS process termination, power loss, and a cleanup operation that
itself aborts likewise provide no remaining-cleanup guarantee.

The automatic cleanup hook is infallible and returns `Unit`. A resource whose
orderly close can report an operational error exposes an explicit consuming
method such as `finish(take self) -> Result(Unit, E)`. Calling it disarms the
registered owner before entering the method; the method must release the
resource on both `Ok` and `Err`. A retryable operation instead uses `mut self`
and leaves fallback cleanup registered. Automatic cleanup remains suitable for
abandonment and cannot hide a recoverable result.

A cleanup hook whose owner holds a suspending I/O capability, such as a task
group or an evented socket, may suspend while joining child tasks or completing
an asynchronous release, so its scope exit is potentially suspending. Once
scope cancellation starts, cleanup runs in a cancellation-shielded teardown
state: it still observes the original cancellation token but is not itself
repeatedly canceled before it can join/release. Task groups require an
`AsyncIo` capability.

Resources may be grouped in ordinary affine records. Such a record either
implements `Cleanup` or must transfer/clean each owner before its scope ends.

## Allocation and OOM

Safe allocation never returns invalid or partially initialized memory.

Convenience operations such as ordinary `Vec.push` and string concatenation
are infallible at the type level and terminate the process on OOM or
unrepresentable target size. Services that need recovery use `try_reserve`,
`try_push`, builders with explicit limits, or domain budgets returning
`Result`. Failed fallible growth leaves the prior value valid and unchanged.

Domain retention is a safety guarantee, not a promise of bounded memory. A
program can still exhaust finite memory. Tooling must expose high-water domain
usage, retained segments, collection copies, and long-lived table capacity.

## Concurrency relation

Task creation copies ordinary inputs into independent task state and transfers
explicit affine inputs. Scoped capabilities and mutable locals are not
implicitly shared. Channels, locks, and atomics provide the only standard
shared-mutation paths. A task group owns their shared storage so handles cannot
outlive the group without a separate explicit owner.

The full scheduling, cancellation, and task-safety contract is in
[Async and Structured Concurrency](async.md).

## Bootstrap distinction

The current `Domain`, `DomainMark`, `__s0_*` allocation/buffer operations,
fixed-capacity map, callback-bearing `using ... with ...`, and MIR table
operations are implementation evidence only. They are not the 1.0 source API,
and since M7.3 they are not even ordinary source: the compiler accepts them
only under the private bootstrap profile that exists to compile its own
sources, while ordinary programs construct values through inferred storage.
See [Alder S0](s0-language.md).
