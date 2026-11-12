# Alder Memory and Resources

Design status: **Frozen for Alder 1.0**

Availability: **Inferred storage is implemented (M7.3). M7.5 implements the `Table(T)`/`T.Id` source surface with generational staleness, scoped `get`/`get_mut` views, overlap rejection, affine aggregate composition, and callback-free `using` cleanup: the builtin Table release or the owner's `Cleanup` implementation, whose types are affine. `Vec(T)` over a `Cleanup` owner is affine: elements enter by transfer through `push` or `from_array`, element reads and views are rejected, and a registration drains every element at scope exit. There is no separate `AsyncCleanup` trait: a `Cleanup` hook may suspend when its owner holds a suspending capability once the concurrency runtime arrives in Milestone 9; the callback `with` clause is bootstrap-private. Tables as `Vec` elements are deferred by the phase-6 MIR lifetime rule
(`lifetime_deref_store` rejects storing a table handle through a deref
place), so heap-stored table elements await a storage decision.**

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

Milestone 7.5 implements the rule for the collection copy sites: a value
whose source binding is provably dead and unaliased at the copy transfers
its storage instead of copying, parameters never move inside their callee
(the caller's dead argument is elided at the call instead), and bindings
captured by closures or observed through views always copy.

A read inside a loop body also moves when the body re-establishes the
binding before the read runs again: the next access to that binding in the
body is a definition and the body is straight-line code, so the definition
always executes before the loop repeats the read. That is the loop-rebuild
shape `items = rebuild(items)`. A body that only reads the binding, reads it
again after the rebuild, or contains a conditional, a `match` or `try`
expression, or a nested loop still copies, because any of those can skip the
definition and leave the next iteration reading storage the callee owns.
Reads after the loop do not affect the verdict: the rebuild re-establishes
the binding, so they read the new value. The compiler's `--report-copies`
flag prints one line per remaining copy site with its reason after a
successful check or compile.

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
visible only at resource and identity boundaries. In the M7.5 composition
model, an affine argument transfers into the aggregate being constructed
(record field, enum payload, `Option`/`Result` wrapper, or array element), a
`match` over an affine scrutinee consumes the scrutinee as a whole and binds
its payload by transfer, and parts leave an aggregate only by transferring
the aggregate itself: there is no field-extraction or per-part move syntax.
An aggregate owner satisfies the exit rule by being transferred or registered
with `using`, exactly like any other owner.

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

Milestone 7.5 implements the ordered `Map(K, V)` and `Set(T)` as
insertion-ordered association lists over vector storage with structural key
comparison. Lookup, insert, and remove scan linearly, which is a known cost
accepted for M7.5; hashing indices arrive with the standard-library hash
containers. The M7.5 key domain is the structural-comparison domain that the
inline compare lowers: unsigned integers, `Bool`, `String`, `Bytes`, and
non-generic records and enums over that domain whose enum variant payloads
are primitives, `String`, or `Bytes`. Signed integers participate in
structural `Eq`/`Hash` but remain outside Map/Set keys in M8 as a deliberate
key-domain restriction. Values must be recursively copyable
ordinary values; slices, mutable views, and the ordered collections
themselves are excluded until affine composition lands. `remove`, `keys`,
`values`, and `items` move stored values through a lowering loop, so they
additionally require the moved type (both halves of the entry for `remove`)
to be free of storage-backed parts — vec, string, bytes, and the like —
until runtime-backed move operations exist.

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

### Borrowed-place owner domains (M8)

A `mut self` receiver and a `mut` parameter are borrowed places: the caller
owns the value, and the callee writes through a reference to it. MIR carries a
hidden owner `domain_handle` parameter after each `safe_mut` parameter. Direct
and delegated calls pass that domain with the borrowed argument, so growth and
relocatable storage replacement allocate in the domain that owns the caller's
place. The MIR representation and verifier pairing are installed; lowering will
record the owner of each local under this contract. A `take` parameter owns a
frame-local value and grows in the callee frame, and a returned value is still
copied to caller-result storage; a by-value parameter's storage stays in the
caller's active domain until the callee copies it, and growth uses the domain
of the value actually stored. A `using` owner, table view, or caller-result
value carries its own owning domain. If control-flow paths assign different
owners to one local, lowering copies the value with `copy_to_domain` into the
nearest dominating domain (the frame domain, or caller-result storage when it
may be returned), records that domain, and reports the copy site; it never
rejects the join. There is no
source lifetime annotation, `Vec` still carries no domain, and no ARC/GC is
introduced. C export signatures and callback trampolines never carry a
`safe_mut` or owner parameter because the C ABI has no `mut`.

The interim restriction below remains until the lowering and verifier
implementation of this owner-domain contract lands.

### Borrowed-field storage replacement (interim M8 restriction)

The lowering does not yet use the owner parameter for growth and replacement.
A callee that grows a `Vec`, assigns a `String`/`Bytes`/collection header, or
rebuilds a `Map`/`Set` through a field of such a receiver would therefore
allocate in the callee's function domain while the caller keeps a header into
it; the callee returns, its domain is destroyed, and the caller reads freed
storage.

Until the lowering uses the owner domain for every growth and replacement,
diagnostic 333 rejects
mutating collection operations and relocatable-storage assignments through a
field rooted in a `mut self` receiver or a `mut` parameter. The rule accepts the
shapes whose storage is static or empty today: string literals, `Vec.new`,
`Map.new`, `Set.new`, `None`, and record/array/variant constructions whose
relocatable children are themselves one of those. A local, a parameter, a field
read, a call result, or a mutable receiver is rejected because each retains the
current call's storage. The supported workaround is the functional-builder
convention: build a new value from a local copy and return it, then rebind the
caller, for example `value = value.with_item(x)`.

The real fix threads an owning domain token with every `mut` argument and
receiver through delegation, uses that domain at growth and replacement sites,
and adds verifier invariants that prove the stored header outlives the call.
The design is tracked in [Roadmap](../ROADMAP.md) deferred work; the diagnostic
is removed when the provenance contract and its tests land.

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
`try_insert` returns `Result(T.Id, T)`: `Ok` carries the fresh ID, and `Err`
carries the element value itself back to the caller, so a failed insertion
never drops or copies away the value it was given. `Err` means the table
refused the insert (identity exhaustion, the runtime capacity policy, or
slot-storage exhaustion); the table is unchanged. Exhaustion inside the
element copy itself follows the `copy_to_domain` termination contract instead,
because the copy is an infallible value operation.

Element placement: inserting a storage-bearing element deep-copies it into
the table's domain before its slot bytes are stored, so a stored owning
element stays valid as long as the table itself, even when its source was
allocated in the inserting function's hidden caller-result domain; a source
that is dead after the insert transfers its storage instead. A table value
itself is never copied (`copy_to_domain` rejects it, phase 10), so reads of
a table are borrows and the same table can be read again after an insert
without a value copy.

## Deterministic cleanup

`using name = expression` accepts an affine type implementing the language's
special `Cleanup` trait. Registrations run at most once in reverse lexical
order.

A conditional implementation — one whose `impl` declares type parameters, such
as `impl(T: type) Cleanup for Boxed(T)` — registers the concrete instance of
its `cleanup` hook for the registered owner's type, and that instance must
satisfy the implementation's own constraints. The hook itself is a nongeneric
method that takes the owner by value and returns `Unit`.

Cleanup is guaranteed on:

- normal block fallthrough;
- `return`;
- `try` error propagation;
- `break` and `continue` across the resource scope;
- structured task cancellation and task-group exit.

An invariant panic terminates the process immediately with status 101 and
does not unwind or run cleanup; the `core.panic` operations use this path and
do not run registered cleanup. OS process termination, power loss, and a
cleanup operation that itself terminates likewise provide no remaining-cleanup
guarantee.

The automatic cleanup hook is infallible and returns `Unit`. A resource whose
orderly close can report an operational error exposes an explicit consuming
method such as `finish(take self) -> Result(Unit, E)`. Calling it disarms the
registered owner before entering the method; the method must release the
resource on both `Ok` and `Err`. A retryable operation instead uses `mut self`
and leaves fallback cleanup registered. Automatic cleanup remains suitable for
abandonment and cannot hide a recoverable result.

A `take self` method may move its own direct record fields out one at a time,
by returning a field, binding it with `let`, or passing it as a `take`
argument. A moved field is a transfer of that sub-owner, so a later read of the
same field is the ordinary use-after-transfer error, and the whole owner may
not be used or transferred once any of its fields has moved. The method exits
only when every affine field has been moved out or registered with `using`;
leaving one live is rejected like any other untransferred affine owner. The
wrapper's own cleanup hook does not run for the taken binding — the registration
was disarmed before the call, so the consuming method is the release. A method
that fails after moving a field must itself release that field (and any other
live field) before returning `Err`. A borrowed receiver (`self` or `mut self`)
may not move a field.

A cleanup hook whose owner holds a suspending I/O capability, such as a task
group or an evented socket, may suspend while joining child tasks or completing
an asynchronous release, so its scope exit is potentially suspending. Once
scope cancellation starts, cleanup runs in a cancellation-shielded teardown
state: it still observes the original cancellation token but is not itself
repeatedly canceled before it can join/release. Task groups require an
`AsyncIo` capability.

Resources may be grouped in ordinary affine records. Such a record either
implements `Cleanup` or must transfer/clean each owner before its scope ends.

Resources may also be grouped in a `Vec(T)` of `Cleanup` owners. Elements
enter only by transfer (`push`, `from_array`) and leave only through the drain:
element reads, slices, and views would duplicate an owner and are rejected.
A vector grows through a plain local binding; the binding registered with
`using` is immutable, because the registration captured the vector at
registration time. Grow first, then register the whole vector.

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
