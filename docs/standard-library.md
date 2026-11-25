# Alder 1.0 Standard Library

Design status: **Frozen minimum module and behavior set**

Availability: **Not implemented as a 1.0 sysroot**

Alder 1.0 ships batteries sufficient for command-line tools, services, file
processing, C wrappers, networking, and concurrent services. The library is
version-matched to the toolchain and available offline after installation.

This document freezes the minimum scope and major contracts, not every final
function spelling. Public API snapshots and executable examples become
normative as each module is implemented.

Implemented module snapshots are versioned separately so their exact spelling
can be reviewed without pretending the rest of the 1.0 sysroot is available:

- [`core.collection` public snapshot v1](api/core.collection-v1.md), covering
  the Milestone 7.1 `Vec(T)` surface extended with the Milestone 8
  insertion-ordered `Map(K, V)` and `Set(T)` builtin surfaces;
- [`core.slice` public snapshot v1](api/core.slice-v1.md), covering the
  Milestone 7.1 immutable and mutable view surface;
- [`core.memory` public snapshot v1](api/core.memory-v1.md), covering the
  Milestone 8.1 `size_of(T)`/`align_of(T)` layout queries, including fixed
  arrays and the one-element C representation of a zero-length array;
- [`core.hash` public snapshot v1](api/core.hash-v1.md), covering the
  Milestone 8.1 SipHash-1-3 structural hash and `RandomState` key surface;
- [`core.iter` public snapshot v1](api/core.iter-v1.md), covering the
  Milestone 8.1 static iterator traits, builtin `.into_iterator()` receivers,
  lazy adapters, terminals, and materialized snapshot semantics;
- [`core.option` public snapshot v1](api/core.option-v1.md), covering the
  Milestone 8 `Option(T)` helper surface in the installed sysroot;
- [`core.result` public snapshot v1](api/core.result-v1.md), covering the
  Milestone 8 `Result(T, E)` helper surface in the installed sysroot;
- [`core.num` public snapshot v1](api/core.num-v1.md), covering the
  Milestone 8 integer limits and explicit-overflow absolute value in the
  installed sysroot;
- [`core.panic` public snapshot v1](api/core.panic-v1.md), covering the
  Milestone 8 process-terminating panic and assertion surface in the installed
  sysroot;
- [`core.error` public snapshot v1](api/core.error-v1.md), covering the
  Milestone 8 prelude `Error` trait, default `cause`, and `ErrorReport`
  flattening surface;
- [`core.format` public snapshot v1](api/core.format-v1.md), covering the
  Milestone 8 pure-Alder format specs, scalar-width padding, and integer
  rendering surface;
- [`std.io` public snapshot v1](api/std.io-v1.md), covering the Milestone 8
  hosted capability layer (`Io`, `BlockingIo`, `Blocking`, `Reader`,
  `Writer`, `Seek`, buffers, standard streams, exact helpers, `IoError`, and
  the prelude `Error` trait contract);
- [`std.format` public snapshot v1](api/std.format-v1.md), covering the
  Milestone 8 `Formatter` builder, integer/text composition, and the frozen
  shortest-round-trip float spelling;
- [`std.path` public snapshot v1](api/std.path-v1.md), covering the Milestone
  8 shared `OsString`, owned `Path` surface, and lexical operations;
- [`std.fs` public snapshot v1](api/std.fs-v1.md), covering the Milestone 8
  affine `File`, metadata, directory iteration, and temporary-file surface;
- [`std.env` public snapshot v1](api/std.env-v1.md), covering the Milestone 8
  argument, environment, and target-information surface;
- [`std.process` public snapshot v1](api/std.process-v1.md), covering the
  Milestone 8 `Command`, `Child`, pipe, and exit-status surface;
- [`std.time` public snapshot v1](api/std.time-v1.md), covering the
  Milestone 8 `Instant`, `SystemTime`, `Duration`, `sleep`, and UTC civil
  conversion surface;
- [`std.random` public snapshot v1](api/std.random-v1.md), covering the
  Milestone 8 OS randomness and seeded deterministic generator surface;
- [`std.math` public snapshot v1](api/std.math-v1.md), covering the Milestone
  8 scalar float surface;
- [`std.text` public snapshot v1](api/std.text-v1.md), covering the Milestone
  8 UTF-8 validation, scalar decoding, exact search/split/replace, checked
  conversion, and text builder surface;
- [`std.bytes` public snapshot v1](api/std.bytes-v1.md), covering the
  Milestone 8 byte construction, search, sorted search, endian integer
  coding, and hex and Base64 codec surface;
- [`std.parse` public snapshot v1](api/std.parse-v1.md), covering the
  Milestone 8.1 byte cursor, half-open spans, positioned errors, and scalar
  token parsers;
- [`std.signal` public snapshot v1](api/std.signal-v1.md), covering the
  Milestone 8.1 one-shot blocking termination/interrupt wait and the
  target-specific `Signal.Target` extension;
- [`std.collection` public snapshot v1](api/std.collection-v1.md), covering
  the Milestone 8 stable sorting entry point and the Milestone 8.1 `Deque(T)`
  and `BinaryHeap(T)` value types in the installed sysroot.

Milestone 9's async snapshots are versioned in this document because their
owning modules are not installed yet: [`std.task`](#stdtask-public-snapshot-v1),
[`std.channel`](#stdchannel-public-snapshot-v1),
[`std.sync`](#stdsync-public-snapshot-v1),
[`std.atomic`](#stdatomic-public-snapshot-v1),
[`std.test.SimIo`](#stdtestsimio-public-snapshot-v1), and the
[`std.io` Milestone 9 addition](#stdio-milestone-9-addition), all in
[Async public API snapshots](#async-public-api-snapshots-milestone-9). Each
family moves unchanged into its module's snapshot file when its
implementation lands.

M8 exit-audit status (complete):
`core.option`, `core.result`, `core.num`, `core.panic`, `core.error`,
`core.format`, `std.io`, `std.format`, `std.path`, `std.env`, `std.time`,
`std.random`, `std.math`, `std.text`, `std.bytes`, and `std.collection` are
implemented with production-driver evidence. `std.io` v1 is complete for
blocking and host streams; its `AsyncIo`/`Evented` half is Milestone 9 and is
frozen in [the Milestone 9 snapshots](#stdio-milestone-9-addition).
`std.fs` and `std.process` v1 are implemented on the blocking capability,
including host files, directory iteration, temporary owners, child spawning,
pipes, capture, and process termination. `std.test`'s runner-independent
library slice is implemented; its runner, fuzz, and `SimIo` pieces remain
tooling-milestone work. `core.range` is deferred by
scope decision; case mapping and normalization are deferred to a `std.text`
v2 amendment; async task, channel, sync, and atomic modules are Milestone 9;
networking, HTTP, TLS, data-format, CLI, log, OS, test-runner, and doc-tool
modules are post-M8. `std.c` is the verified C-interop surface rather than a
`.al` module; its exit audit is complete.

M8.1 exit-audit status (complete):
`core.memory`, `core.hash`, `core.iter`, `std.parse`, `std.signal`, and the
`Deque`/`BinaryHeap` additions have frozen snapshots, installed sysroot
implementations, and production-driver evidence under
[Milestone 8.1](../ROADMAP.md#milestone-81-standard-library-completion).
The independent audit and implementation-head CI are green at `d7f36cf`.
`core.iter` accepts arrays, immutable slices, read-only `MutSlice`, `Bytes`,
`Vec`, insertion-ordered `Map` as `Pair(K, V)`, and insertion-ordered `Set`;
`String` scalar iteration and exclusive `MutSlice`/`IterMut` remain
deferred, and Map/Set iteration keeps the documented diagnostic-129
storage-backed-part boundary.

The M8 exit audit maps every ROADMAP M8 exit criterion and named area to a
production-driver test. Live affine owners on a terminating
`core.panic.panic` path need no transfer, so `std.test.expect_err` accepts an
affine `Ok` payload; every non-diverging path still requires exactly-once
transfer or registered cleanup (`5ee3b45`).

## Distribution layers

The installed sysroot has two stability layers:

1. `core` is implicitly available, platform-neutral, and depends only on the
   minimal Alder runtime. It contains language-level algebraic types, traits,
   values/collections, slices, fixed arrays, checked numeric helpers, and
   minimal formatting contracts.
2. `std` is explicitly imported, hosted, and contains allocation, OS, I/O
   capabilities, task groups, network, test, and C support.

HTTP, TLS, URL, and JSON are part of the 1.0 `std` distribution rather than a
network-fetched starter bundle. Their implementations may use audited,
toolchain-vendored native components whose provenance is shipped with Alder.
User projects do not need xmake to use them.

## Prelude and `core`

Every module receives a small documented prelude:

```text
Bool, exact-width numeric types, Unit
Option, Some, None
Result, Ok, Err
String, Bytes, Array, Vec, Map, Set
Eq, Hash, Order, Iterator, IntoIterator
Display, Error, Cleanup
Range
```

The prelude does not import filesystem, networking, process, synchronization,
or C names.

Required `core` areas:

- `core.option` and `core.result`: transforms, predicates, extraction, and
  iteration without hidden exceptions;
- `core.num`: limits, checked/saturating/wrapping named operations, explicit
  conversions, parse and format foundations;
- `core.range`: half-open and inclusive ranges with checked endpoints;
- `core.array` and `core.slice`: iteration, split, search, comparison, copy,
  checked `get`, `[U8].to_bytes` (a copying view-to-`Bytes` conversion), and
  exclusive mutable operations;
- `core.collection`: fundamental `Vec`, insertion-ordered `Map`/`Set`, and
  their checked/fallible capacity operations;
- `core.iter`: static iterator traits and common lazy adapters
  ([snapshot](api/core.iter-v1.md));
- `core.hash`: stable hashing contract plus process-randomized builders for
  attack-facing maps;
- `core.format`: `Display`, formatting arguments, and the text rules used by
  string interpolation;
- `core.memory`: safe size/alignment queries needed by generic code, without
  raw allocation;
- `core.panic`: `panic`, `assert`, `assert_eq`, `assert_ne`, and
  process-terminating invariant APIs;
- `core.error`: the prelude `Error` trait, default `cause` report, and
  `ErrorReport` flattening value.

Index syntax is checked and terminates on an invalid index. `get` returns
`Option`. Checked, wrapping, and saturating numeric behavior is always explicit
in API names.

Implemented core.panic progress: `sysroot/core/panic.al` provides `panic`,
`assert`, `assert_eq`, and `assert_ne`. A failure flushes C output, writes the
documented `panic:` or `panic: assertion failed:` diagnostic to standard error,
and terminates the process with status 101 without running Alder cleanup.
`assert_eq` and `assert_ne` require `T: type(Eq, Display)` and display both operands;
source-expression capture remains deferred to the test runner. The runtime
boundary is the toolchain-owned `runtime/c/alder_panic.h` shim.

Implemented core.error progress: `sysroot/core/error.al` is the prelude source
for D025. It defines the `Error` trait with a defaulted `cause` method returning
`None`, and the `ErrorReport` value with public `message` and `causes` fields
(the source spelling makes both fields readable by ordinary record access).
`ErrorReport.of(E: type(Error, Display), error: E)` builds the flattened chain,
nearest cause first, by recursively calling `cause`. The compiler loads this
prelude source for a project that names `Error` or `ErrorReport`, even when the
project does not import it explicitly. The generated hosted entry adapter uses
`program_error_display`/`program_error_chain` for an unhandled `Err`, writes
`program error:` to standard error, and returns status 1 without exit cleanup.

Implemented core.memory progress: `sysroot/core/memory.al` provides
`size_of(T)` and `align_of(T)` as compile-time layout queries
([snapshot](api/core.memory-v1.md)). The checker recognizes the module's
exports, resolves the one type argument per instance, and lowering emits MIR
113 `type.size` or 115 `type.align`; the C backend answers with the target C
compiler's `sizeof`/`_Alignof` over the lowered representation. `Unit` is fixed
at size 0 and alignment 1. Calls with a non-type argument, wrong arity, or an
unresolved type are diagnostic 346. No allocation, pointer, or Alder layout
engine is added.

Implemented core.hash progress: `sysroot/core/hash.al` provides the stable
structural `hash`/`hash_with` contract, the SipHash-1-3 `Hasher`, and the
128-bit `RandomState` key carrier ([snapshot](api/core.hash-v1.md)). The
structural domain is the same synthesized `Eq`/`Hash` domain used for `==`,
covering `Bool`, signed and unsigned integers, `String`, `Bytes`,
`Option`/`Result`, and eligible records and enums; floats, pointers, views,
and collections are rejected with diagnostic 347. `hash` uses the fixed zero
key; `hash_with` uses a `RandomState`. `std.random.random_state` fills the
key from host entropy through `std.io.Io`, keeping `core.hash` below `std`.
The C backend lowers MIR 116 `hash.value` to the runtime SipHash-1-3 helper
over the canonical stream, and the Alder `Hasher` implements the same
primitive for callers that build their own stream. Map and Set remain
insertion-ordered association lists in M8.1, so `Map.with_hasher` stays
deferred until hash containers exist.

Implemented std.parse progress: `sysroot/std/parse.al` provides the byte
cursor, half-open `Span`, on-demand `Position`, generic `Step(T)`, and the
integer, boolean, and ASCII-word token parsers in
[`api/std.parse-v1.md`](api/std.parse-v1.md). Integer conversion still goes
through `core.num.parse_u64`/`parse_i64`; the module adds token boundaries,
spans, and positioned `ParseError` values without a new checker rule, MIR
operation, runtime helper, or C binding. `take` is a reserved parameter
keyword, so the cursor's buffer-consuming method is `take_bytes`. The
snapshot's explicitly deferred surface is data-format grammars and schemas,
typed/streaming parsers, quoted or escaped strings, key/value record grammars,
Unicode whitespace or identifiers, floating-point/date/time/IP parsing, and a
`Parser` trait or combinator objects.

Implemented std.signal progress: `sysroot/std/signal.al` provides the one-shot
blocking `wait(io, signal, timeout_ms)` surface in
[`api/std.signal-v1.md`](api/std.signal-v1.md). `Signal` covers interrupt,
terminate, hangup, quit, user signals, and the POSIX-only `Target(number)`
extension; Windows maps only interrupt/terminate to console control events.
The call installs a temporary host disposition, waits through
`std.io.Io.wait_signal`, restores the original disposition, and returns
`Some(signal)` or `None` on timeout. **Between waits the original disposition
is active, so a signal arriving outside a wait gets the default action.**
`sysroot/std/c/signal_shim.h` is the header-only POSIX self-pipe and Windows
console-event implementation. Persistent subscriptions, Evented/task delivery,
cancellation-safe teardown, realtime signals, and Windows close/logoff/shutdown
events are M9 work. No checker, MIR, runtime, or cgen case is added.

## Text and bytes

Required modules:

- `std.text`: immutable UTF-8 `String`, `StringBuilder`, scalar iteration,
  UTF-8 validation, split/search/replace, case mapping, normalization, and
  conversion to/from bytes;
- `std.bytes`: immutable `Bytes`, `BytesBuilder`, binary search/split, endian
  reads/writes, hex and Base64;
- `std.format`: integer/float/text formatting, width/alignment/precision, and
  buffered output;
- `std.parse`: numeric and common structured parsing helpers with byte ranges.

`String` indexing is never integer indexing. Byte equality/hashing does not
implicitly normalize Unicode. Unicode tables are toolchain-versioned and their
version is reported by the library.

## Iteration

`core.iter` v1 installs the static iterator traits and the common lazy
adapters; its public contract is the
[`core.iter` v1 snapshot](api/core.iter-v1.md). `Iterator(Item)` and
`IntoIterator(IteratorType, Item)` are builtin static traits: there are no
trait objects, associated types, or runtime dispatch metadata. The builtin
`.into_iterator()` surface accepts `Array(T, N)`, `[T]`, read-only
`MutSlice(T)`, `Bytes`, `Vec(T)`, `Map(K, V)`, and `Set(T)`. Arrays, slices,
and `Vec(T)` yield `T`; `MutSlice(T)` yields copied `T`; `Bytes` yields `U8`
in byte order; `Map(K, V)` yields `Pair(K, V)` in insertion order; and
`Set(T)` yields `T` in insertion order. The installed `SliceIter(T)` and
`VecIter(T)` values hold immutable `[T]` views, not owned vector copies;
`BytesIter` holds a copied `Bytes`. Construction materializes the input into
caller-result storage, copying O(n) elements and storage; later source
mutation does not affect the iterator. A read-only `MutSlice` is first copied
into a fresh `Vec`; `Map` takes `keys()`/`values()` snapshots; `Set` takes an
`items()` snapshot. `Map`/`Set` iteration therefore inherits the temporary
diagnostic-129 restriction on storage-backed keys, values, and elements that
the collection snapshots already have. Each lazy adapter constructor returns
a view-bearing aggregate and may materialize its inner iterator again, so
construction of a chain can copy O(k·n) elements even though iteration itself
is lazy. The adapters are `map`, `filter`, `filter_map`,
`enumerate` over `Indexed(T)`, `take_count`, `skip`, `chain`, and `zip` over
`Pair(A, B)`, with `zip` stopping at the shorter input. The terminals are
`to_vec`, `fold`, `for_each`, `count`, `any`, `all`, `find`, and `position`.
Terminals consume a mutable cursor.

`for value in sequence` remains the builtin array/slice/`Vec` fast path. This
snapshot does not desugar `for` through `IntoIterator`; that frontend work,
`String` scalar iteration, exclusive `MutSlice`/`IterMut` iteration,
double-ended iteration, and a `collect`/`FromIterator` protocol beyond `to_vec`
are later additions. The installed module is
[`core.iter`](api/core.iter-v1.md); the production-driver evidence and deferred
list are recorded in
[Milestone 8.1](../ROADMAP.md#milestone-81-standard-library-completion).

## Collections and identity

Required modules:

- `std.collection`: re-exports of `Vec(T)`, insertion-ordered `Map(K, V)`, and
  insertion-ordered `Set(T)`, plus `Deque(T)`, sorting, binary heaps, and
  collection builders;
- `std.table`: affine `Table(T)`, typed generational `T.Id`, immutable/mutable
  scoped views, insertion/removal, and fallible capacity APIs.

`Map` and `Set` require equality and hashing and iterate in insertion order.
Replacing an existing map value preserves its position; removal followed by
reinsertion places the key/value at the end. Hash randomization cannot change
this order.
Sorting APIs are stable unless explicitly named `sort_unstable`. Collection
fallible growth leaves the previous value unchanged. A collection containing
an affine element is itself affine, transfers elements explicitly, and cleans
all remaining elements exactly once.

## Paths, files, and I/O

Required modules:

- `std.path`: the shared exact host `OsString`, owned `Path`, component
  iteration, lexical join/normalize, extension/name operations, and explicit
  platform conversion;
- `std.io`: the `Io`, `BlockingIo`, and `AsyncIo` capability traits; the
  `Blocking` and `Evented` capabilities; `Reader`, `Writer`, and `Seek` traits;
  buffered readers/writers; standard input/output/error; exact/copy/line
  helpers; `IoError`;
- `std.fs`: affine `File`, directory iteration, metadata, permissions,
  canonicalization, copy/rename/remove, and temporary files/directories.

Implemented std.io progress (slice 1): `sysroot/std/io.al` provides the
`Reader`, `Writer`, and `Seek` traits with the `copy_to` default body,
`SeekFrom`, `IoError` with `from_errno`, `Display`, and `Error`, the
`read_exact`, `write_all`, and `read_to_end` helpers, the host-free
`ByteCursor` and `ByteSink` streams, and the buffered `BufReader`/`BufWriter`
over generic readers and writers. `BufReader` serves reads from its window and
refills from the source; `BufWriter` buffers small writes, flushes on
overflow or demand, and its cleanup flushes the value the registered
binding holds at scope exit, including writes performed after `using`.
`ByteSink` grows its owned byte vector from writes: `new` starts with 4096
bytes of room, `with_capacity` selects another initial size, and `write`
accepts every byte. Evidence:
`compiler/production_io_test.go` runs the installed module through the
production driver and checks cursor advancement, end-of-stream, the `copy_to`
default body, the error category report, line reads across a small buffer,
read refills, buffered write ordering through a validating sink, the full
`ByteSink` growth boundary, and the mutable-place rejection; the core,
buffered, and ByteSink programs also run under ASan/UBSan.

`into_source` and `into_sink` return the wrapped owner through the
consumed-field-move rule: a `take self` method may move one direct field out,
and the returned owner is owned by the caller. `into_sink` flushes pending
bytes first and releases the sink itself on a flush error. The capability
types, host files, and standard streams arrive with the C-binding buffer
surface as slice 2.

Implemented std.env progress: `sysroot/std/env.al` installs the full v1
surface. `arguments` copies the process vector installed by the hosted driver;
`get`, `set_var`, and `remove_var` observe and update the process environment;
`current_dir`, `set_current_dir`, and `current_exe` go through the audited
`std/c/env_shim.h` boundary; `target` reports compile-time OS/architecture
information. `EnvError` implements `Display` and `Error`, and invalid names
(empty or containing `=`) are rejected before the host call. The host-shim
argument and environment state is single-threaded by contract. Evidence:
`compiler/production_env_test.go` runs with `-- alpha beta` and checks the
argument vector, self-set variable round-trip and removal, rejected name,
working directory, executable, and target; `runtime/testdata/hostargs.c`
checks the runtime argument bridge under ASan/UBSan; `docs/api/examples/std.env-v1.al`
runs with checksum 117. Runtime ABI:
[`alder_host_set_args`](c-backend.md) in `runtime/c/alder.h`.

Implemented `std.process` v1: `sysroot/std/process.al` installs `PipeMode`,
the value-semantic `Command` and its in-place builders, `ExitStatus` with
exit/signal decomposition, `Output`, and `ProcessError` with `Display` and
`Error`. `Command.spawn`/`status`/`output` start children through the `Io`
capability; `Child(I)` owns the `HostChild` bridge, moves pipe ends out with
`Option.take`, and reaps through `wait` or kill-and-reap cleanup. `output`
drains stdout and stderr with the two-descriptor poll before waiting, so full
pipes cannot deadlock. The host calls live in `sysroot/std/c/process_shim.h`
and the `std.io` trait; no function invokes a shell or quotes an argument.
Stream modes and process categories are constructed with qualified variant
expressions such as `PipeMode.Piped` and `ProcessError.Platform(info)`.

Implemented `std.fs` v1: `sysroot/std/fs.al` installs `Options`, the portable
`Permissions` record, the affine `File(I)`, directory `Entries`/`Entry`,
`Metadata`, the whole-file and path operations, and the `TempFile`/`TempDir`
temporary owners. Traversal uses `lstat` whenever the host entry kind is
unknown or a symlink, so `remove_dir_all` unlinks links instead of following
them; the documented TOCTOU limit remains `no openat/unlinkat in v1`.

The hosted `std` module graph is acyclic and fixed by the snapshots:
`std.path` imports only `core`; `std.env` imports `std.path`; `std.io` imports
`std.path` and `std.env`; `std.fs` and `std.process` additionally build on
`std.io`, `std.time` and `std.random` on `std.io`, and `std.test` on `std.fs`,
`std.io`, and `std.random`.

Every operation that waits on the host takes an I/O capability and is written
once against `I: Io`, so the same API serves blocking tools and evented
servers; there is no parallel synchronous and asynchronous surface. See
[Async and Structured Concurrency](async.md#the-io-capability).

Path values preserve platform-relevant bytes/units and do not assume every OS
path is UTF-8. Display may escape non-text components. Directory iteration is
documented as host order; deterministic tools explicitly call the provided
sorted iterator.

`File` cleanup closes the descriptor. `finish`/`sync` return errors when a
caller must observe finalization. Failed writes are never reported as success
merely because fallback cleanup cannot return an error.

## Environment and processes

Required modules:

- `std.env`: arguments, environment lookup/update, checked `String`
  conversion for host-facing details, current executable and directory, and
  platform/target information;
- `std.process`: value-semantic `Command`, affine `Child`, pipes, exit status,
  output capture, wait, cancellation-aware termination, and explicit
  environment inheritance;
- `std.signal`: one-shot blocking termination/interrupt wait in M8.1, with
  persistent subscriptions, evented/task delivery, and target-specific
  extensions in M9 (Windows console events and POSIX realtime signals).

No API invokes a shell unless its name explicitly says `shell`. The default
process API passes an argument vector directly and never performs hidden
quoting or expansion.

## Time, random, and math

Required modules:

- `std.time`: monotonic `Instant`, wall-clock `SystemTime`, checked `Duration`,
  timezone-independent UTC conversion, timers, and sleep;
- `std.random`: OS cryptographic randomness, deterministic seeded generators
  for simulation/tests, and unbiased ranges;
- `std.math`: portable scalar math with documented IEEE behavior and explicit
  exceptional results.

Implemented std.fs progress: `sysroot/std/fs.al` installs `File` plus the
whole-file operations and `Metadata` on the `std.io` capability. `File` is
affine with `finish`/`keep`/cleanup releases, `Metadata.modified` preserves
signed pre-1970 wall-clock seconds, and owner mode bits map to `Permissions`.
Evidence: `compiler/production_fs_test.go` exercises the file methods and the
free helpers, including a host mtime set before the epoch. Directory iteration is installed:
`Entries`/`read_dir` skip `.` and `..`, `read_dir_sorted` orders by exact name
bytes, and `remove_dir_all` unlinks symlinks without following them (using
`io.lstat` for unknown host entry kinds). Temporary files and directories are
installed: `temp_root` reads `TMPDIR` through `env.get`, unique names use
random hex suffixes with `AlreadyExists` retries, and `TempFile`/`TempDir`
provide best-effort cleanup plus explicit `keep` releases.

Implemented std.time progress: `sysroot/std/time.al` installs the v1 surface.
`Duration` is normalized seconds plus nanos with checked arithmetic and a
zero-saturating subtraction, `SystemTime.from_unix`/`unix_seconds`/`to_utc`
use database-free proleptic-Gregorian integer conversion (including
pre-1970 instants), and `Instant`/`SystemTime.now` plus `time.sleep` take the
`std.io` capability. `Timer.at`/`Timer.after` provide one-shot monotonic
deadlines with `deadline`/`remaining`/`expired`/`wait`, and `sleep_until`
waits for an `Instant`; a timer needs no additional host descriptor, only the
existing clock and sleep capability methods. Evidence:
`compiler/production_time_test.go` checks independently computed UTC vectors,
duration arithmetic, the monotonic lower bound of a sleep, timer expiry and
waiting, and a zero-duration sleep through `Blocking`; the snapshot example
runs with a fixed checksum.

Implemented std.random: both halves are installed at `sysroot/std/random.al`.
The OS forms `fill`, `u64`, `u32`, `range_u64`, and `range_u32` take the
`std.io` capability and read host entropy; `u64`/`u32` assemble little-endian
byte draws and the range forms use the same rejection sampling as the seeded
generator. `Rng` is SplitMix64 over one `U64` state with value semantics,
`seeded`, `next_u64`, `next_u32`, unbiased `range_u64`/`range_u32`, and `fill`
over a `MutSlice(U8)`, so tests and simulations stay deterministic byte for
byte. Evidence: `compiler/production_random_test.go` checks independently
computed SplitMix64 vectors and runs the OS forms under `Blocking` and
ASan/UBSan with shape-only assertions; the snapshot example runs with a fixed
checksum.

Calendar and timezone databases are versioned distribution data. Ambient C
rounding-mode changes are outside safe wrappers and cannot silently redefine
Alder numeric semantics.

## Tasks and synchronization

Required modules:

- `std.task`: `TaskGroup.new(io)`, result-bearing `spawn`, unit-returning
  `start`, scoped `Task(T)`, parent-exit cancellation, cooperative cancellation
  tokens, `check_cancel`, internally joined timeout/race, yield, executor
  configuration, and bounded blocking work; the worker-count configuration type
  itself lives on the capability in `std.io` ([snapshot](#stdtask-public-snapshot-v1));
- `std.channel`: bounded/unbounded channels with FIFO and backpressure;
- `std.sync`: group-scoped `Shared(T)`, mutex/RW-lock guards, one-time
  initialization, and barriers;
- `std.atomic`: fixed-width integer, boolean, and pointer-free atomics with
  explicit memory ordering.

These modules implement [Async and Structured Concurrency](async.md). They do
not provide an implicit detached task, arbitrary single-handle `Task.cancel`,
or an unsafe user-asserted transfer trait. Their versioned public surfaces are
frozen in [Async public API snapshots](#async-public-api-snapshots-milestone-9);
implementation may not add a name absent from those sections.

## Async public API snapshots (Milestone 9)

Design status: **Frozen v1 snapshots; not implemented**

These sections freeze the Milestone 9 module families before implementation,
following
[the snapshot process](open-questions.md#standard-library-final-api-snapshots):
`std.task`, `std.channel`, `std.sync`, `std.atomic`, `std.test.SimIo`, and the
Milestone 9 `std.io` capability additions. They are normative for their
modules: implementation may not add a public name, parameter, result, or error
variant that is absent here. Pre-1.0 spelling may change only by updating the
snapshot, its example, and every caller together. Each family is one coherent
review section with exact signatures, ownership and transfer categories, error
enums, and an executable-style example.

The examples use the implemented S0 declaration and statement surface
(`type` parameters, `Name(...)` application, `using`, `take`, `mut self`,
`match`, `try`, and the builtin numeric and byte methods) plus the two
Milestone 9 forms already frozen in [Async](async.md): the prefix `await`
operator and a `Pending(T)` argument. Each section's example is the complete
content that lands as `docs/api/examples/<module>-v1.al` with that module's
implementation commit, following the
[`std.collection` v1 precedent](api/std.collection-v1.md): the docs example
runner resolves installed sysroot modules, so the file cannot precede the
module. A family that is implemented moves this section unchanged into its
module's owned snapshot file: a new `docs/api/<module>-v1.md`, or the existing
`std.io` and `std.test` files for those two amendments.

Cross-cutting v1 rules:

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
  [the `std.io` addition](#stdio-milestone-9-addition).
- Safe task code is data-race-free. Race freedom does not impose a
  deterministic completion order: only the documented channel FIFO and
  explicit synchronization results are ordered.
- There is no detached task, no `Task.cancel`, no stored `Pending(T)` value,
  and no user-asserted transfer category.

Module graph (acyclic): `std.task` imports `std.io` and `std.time`;
`std.channel`, `std.sync`, and `std.atomic` import `std.io` and `std.task`;
`std.test` gains `SimIo` without new imports.

### `std.task` public snapshot v1

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
    // private: group, child
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
    pub fn new(io: I) -> TaskGroup(I)
    /// Starts the direct call's body as a child and returns its handle.
    pub fn spawn(T: type, mut self, pending: Pending(T)) -> Task(T)
    /// Starts a `Unit` child that the group joins without a user handle.
    pub fn start(mut self, pending: Pending(Unit)) -> Unit
}

impl(I: type(Io, AsyncIo)) Cleanup for TaskGroup(I)
impl(T: type) Cleanup for Task(T)
impl Cleanup for Cancellation

impl Cancellation {
    pub fn new() -> Cancellation
    pub fn token(self) -> CancellationToken
    pub fn cancel(self) -> Unit
    pub fn is_cancelled(self) -> Bool
}

impl CancellationToken {
    pub fn is_cancelled(self) -> Bool
    pub fn check(self) -> Result(Unit, CancellationError)
}

pub fn timeout(T: type, I: type(Io, AsyncIo), io: I, duration: Duration, pending: Pending(T)) -> Result(T, Timeout)
pub fn race(T: type, I: type(Io, AsyncIo), io: I, first: Pending(T), second: Pending(T)) -> T
pub fn blocking(T: type, I: type(Io), io: I, pending: Pending(T)) -> T
pub fn yield(I: type(Io, AsyncIo), io: I) -> Unit
```

Contracts:

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
  joins, and returns `Err(Timeout.Timeout)` (the error type and its single
  variant share the name `Timeout`, so the unqualified pattern `Err(Timeout)`
  also resolves). An operation whose own result is `Result(U, E)` therefore
  surfaces as `Result(Result(U, E), Timeout)`; no error types are merged.
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

Example: the entry point is generic over the capability and the project
harness instantiates it with `std.test.SimIo.seeded(0)`, so the checksum is
deterministic.

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
        Ok(count) => { return Ok(count) }
        Err(Timeout.Timeout) => { return Err(IoError.Unsupported) }
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
        Err(CancellationError.Cancelled) => {}
    }
    return total
}
```

### `std.channel` public snapshot v1

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
    pub fn bounded(I: type(Io, AsyncIo), group: TaskGroup(I), capacity: U64) -> Result(Channel(T), ChannelError)
    /// A queue with no limit beyond available memory.
    pub fn unbounded(I: type(Io, AsyncIo), group: TaskGroup(I)) -> Channel(T)
    pub fn sender(self) -> Sender(T)
    pub fn receiver(self) -> Receiver(T)
    /// Closes both directions; queued values stay receivable.
    pub fn close(take self) -> Unit
}

impl(T: type) Cleanup for Channel(T)

impl(T: type) Sender(T) {
    /// Transfers `value` into the queue, waiting for room when full.
    pub fn send(self, take value: T) -> Result(Unit, ChannelError)
}

impl(T: type) Receiver(T) {
    /// Takes the front value, waiting for one when empty.
    pub fn receive(self) -> Result(T, ChannelError)
}
```

Contracts:

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

Example:

```alder
module hello.std_channel_example

import std.channel { Channel, ChannelError, Receiver, Sender }
import std.io { AsyncIo, Io }
import std.task { TaskGroup }

// The executable std.channel v1 snapshot example: one bounded queue, one
// producer, one consumer, backpressure at capacity two, and explicit close.

// The annotated result supplies `T = U64` and the concrete capability type,
// because an associated constructor on a generic type has no receiver value
// to infer from.
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
    using channel = try open_channel(io, tasks)
    let producer = tasks.spawn(produce(io, channel.sender(), 4))
    let worker = tasks.spawn(consume(io, channel.receiver(), 4))
    try await producer
    let total = try await worker
    channel.close()
    return Ok(total)
}
```

### `std.sync` public snapshot v1

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
    pub fn new(I: type(Io, AsyncIo), group: TaskGroup(I), take value: T) -> Shared(T)
    /// Exclusive access; excludes every other guard on the same slot.
    pub fn lock(self) -> LockGuard(T)
    /// Shared access; overlaps other read guards and excludes `lock`.
    pub fn read(self) -> ReadGuard(T)
}

impl(T: type) LockGuard(T) {
    /// A one-element mutable view of the guarded slot, scoped to this guard.
    pub fn borrow(mut self) -> MutSlice(T)
}

impl(T: type) ReadGuard(T) {
    /// A one-element immutable view of the guarded slot, scoped to this guard.
    pub fn borrow(self) -> [T]
}

impl(T: type) Cleanup for LockGuard(T)
impl(T: type) Cleanup for ReadGuard(T)

impl(T: type) Once(T) {
    pub fn new(I: type(Io, AsyncIo), group: TaskGroup(I)) -> Once(T)
    pub fn is_initialized(self) -> Bool
    /// Stores `value` when uninitialized; otherwise releases it and reports
    /// `AlreadyInitialized`.
    pub fn initialize(self, take value: T) -> Result(Unit, InitError)
    /// Copies the initialized value; available only for copyable `T`.
    pub fn get(self) -> Option(T)
}

impl Barrier {
    /// A reusable barrier that releases every waiter each time `parties`
    /// waits have arrived; `parties` must be at least 1.
    pub fn new(I: type(Io, AsyncIo), group: TaskGroup(I), parties: U64) -> Result(Barrier, SyncError)
    /// Waits for the current generation's last party.
    pub fn wait(self) -> Unit
}
```

Contracts:

- `Shared(T)` is the reader-writer lock; a plain mutex is the same type with
  only `lock` calls. `lock` is exclusive, `read` is shared, several read
  guards may overlap, and both are potentially suspending when contended.
  Completion order is never made deterministic by lock use.
- A guard is affine and local: it cannot enter a task, be returned, or be
  stored in an escaping aggregate. A guard that is live at a potentially
  suspending call is rejected and the diagnostic names both the guard and
  the call; under `BlockingIo` no call suspends, so the restriction does not
  apply. Guards release only through cleanup, so the ordinary form registers
  one with `using`. `borrow` yields a one-element view of the guarded slot
  and that view is scoped to the guard binding: it cannot outlive the guard.
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

Example:

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

### `std.atomic` public snapshot v1

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
    pub fn new(I: type(Io, AsyncIo), group: TaskGroup(I), value: U64) -> AtomicU64
    pub fn load(self, order: Ordering) -> U64
    pub fn store(self, value: U64, order: Ordering) -> Unit
    pub fn swap(self, value: U64, order: Ordering) -> U64
    pub fn compare_exchange(self, expected: U64, replacement: U64, success: Ordering, failure: Ordering) -> Result(U64, U64)
    pub fn fetch_add_wrapping(self, value: U64, order: Ordering) -> U64
    pub fn fetch_sub_wrapping(self, value: U64, order: Ordering) -> U64
}
```

Contracts:

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

Example:

```alder
module hello.std_atomic_example

import std.atomic { AtomicU64, Ordering }
import std.io { AsyncIo, Io }
import std.task { TaskGroup }

// The executable std.atomic v1 snapshot example: two children add through
// one group-scoped atomic, and the parent observes the final value after
// joining both. Each fetch returns the previous value, and every previous
// value 0..9 is returned exactly once across the two children, so their sum
// is deterministic regardless of interleaving.

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

### `std.test.SimIo` public snapshot v1

This section amends [`std.test` v1](api/std.test-v1.md) with the deterministic
async capability. Its example lands as
`docs/api/examples/std.test.simio-v1.al`.

```alder
module std.test

import std.io { AsyncIo, Io }

// The existing Milestone 8 declarations are unchanged.

/// Deterministic async capability for tests: one worker, a virtual clock,
/// and a seeded generator. Copyable like every `Io` capability.
pub type SimIo {
    // private: scheduler, clock, generator
}

impl SimIo {
    /// The virtual clock at zero and the fixed seed 0.
    pub fn new() -> SimIo
    /// The virtual clock at zero and the given generator seed.
    pub fn seeded(seed: U64) -> SimIo
}

impl Io for SimIo
impl AsyncIo for SimIo
```

Contracts:

- `SimIo` runs every task of a test on one worker. Runnable tasks run one at
  a time in deterministic readiness order, and `new()` is exactly
  `seeded(0)`, so a fixed program produces the same results, the same
  scheduling, and the same random bytes on every run, target, and process.
- Both clocks are virtual. The monotonic and wall clocks start at zero and at
  a fixed documented epoch (the Unix epoch), and they advance only when every
  live task is blocked on time: the clock jumps to the earliest pending
  deadline. A deadline at the current instant is a time block, so a
  zero-duration sleep advances nothing.
- `random_bytes` draws from one SplitMix64 stream seeded by `seeded`, so it is
  deterministic byte for byte. It never observes host entropy.
- Every `Io` operation outside the clock, sleep, randomness, scheduler, and
  standard-stream surface returns `Err(IoError.Unsupported)`: host files,
  directories, signals, `poll`, and child processes are not simulated in v1.
  Standard output and error write through to the host streams; capture is
  runner-level work. `read_stdin` returns `Unsupported`, so a test reads
  deterministic input from values it constructs. A test that needs a host
  resource uses `Blocking` or a real `Evented`.
- Deadlock: when no task is runnable, no timer is pending, and live tasks
  remain blocked, `SimIo` terminates the test through `core.panic.panic` with
  the fixed first line `panic: SimIo deadlock` followed by one
  `  blocked task <index>` line per blocked task, in spawn order with
  one-based indices. The listing is the failure diagnostic; a program must
  not depend on it as data.
- `SimIo` always uses one worker and ignores `std.io.ExecutorConfig`.
  Production code must not depend on its readiness order; only its own
  determinism is guaranteed.

Example:

```alder
module hello.std_simio_example

import std.io { AsyncIo, Io }
import std.task { TaskGroup, Timeout, timeout }
import std.test { SimIo }
import std.time { Duration, Instant, sleep }

// The executable std.test.SimIo v1 snapshot example: two sleeps advance the
// virtual clock in deadline order and a timeout observes the same clock.

fn nap(I: type(Io), io: I, millis: U64) -> U64 {
    sleep(io, Duration.millis(millis))
    return millis
}

pub fn std_simio_example() -> U64 {
    let sim = SimIo.seeded(0)
    let started = Instant.now(sim)
    using tasks = TaskGroup.new(sim)
    let short = tasks.spawn(nap(sim, 30))
    let long = tasks.spawn(nap(sim, 120))
    let first = await short
    let second = await long
    let elapsed = Instant.now(sim).duration_since(started)
    var total: U64 = first + second
    if elapsed == Duration.millis(120) { total = total + 1 }
    let timed = timeout(sim, Duration.millis(10), nap(sim, 1000))
    match timed {
        Ok(value) => { total = total + value }
        Err(Timeout.Timeout) => { total = total + 2 }
    }
    return total
}
```

### `std.io` Milestone 9 addition

This section is the additive Milestone 9 surface of
[`std.io` v1](api/std.io-v1.md). That file remains the owning snapshot; the
addition is folded into it unchanged when the module implements it.

```alder
module std.io

/// Worker counts requested from the hosted executor. `Automatic` lets the
/// runtime choose from host parallelism; `Fixed(count)` requires at least
/// one worker.
pub enum WorkerCount {
    Automatic
    Fixed(count: U64)
}

/// Configuration of the process-wide hosted executor.
pub type ExecutorConfig {
    pub portable: WorkerCount
    pub blocking: WorkerCount
}

impl ExecutorConfig {
    /// Both counts `Automatic`.
    pub fn automatic() -> ExecutorConfig
}

/// The hosted evented executor capability. Copyable, like every `Io`
/// capability.
pub type Evented {
    // private: executor
}

impl Evented {
    /// The process-wide executor with automatic worker counts.
    pub fn new() -> Evented
    /// The process-wide executor with an explicit configuration.
    pub fn configured(config: ExecutorConfig) -> Evented
}

impl Io for Evented
impl AsyncIo for Evented

/// Required `Io` v1 surface addition for Milestone 9.
impl Io for Blocking {
    // ... the existing Milestone 8 operations unchanged ...
    fn check_cancel(self) -> Unit {
        return
    }
}
```

The `Io` trait gains one requirement, which every implementor must provide:

```alder
pub trait Io {
    // ... the existing Milestone 8 operations unchanged ...

    /// Structured-cancellation checkpoint for long CPU-bound work. Returns
    /// normally when no cancellation is pending for the calling task. When
    /// the calling task's group has begun cancellation, the call ends the
    /// task's ordinary exit path instead of returning. Always returns
    /// normally for a caller that is not a group child, so `Blocking`
    /// implements it as an immediate return.
    fn check_cancel(self) -> Unit
}
```

Contracts:

- **`BlockingIo` and `AsyncIo` must require `Io`, and no type implements
  both.** Both are empty marker traits in `sysroot/std/io.al` today, and the
  S0 trait system has no supertrait form: a trait declaration records
  parameter constraints and method requirements only
  (`compiler/src/checker.al`, `check_trait_declaration`), and
  [Traits and Closures](traits-and-closures.md) states that trait
  inheritance is not supported. This snapshot therefore records the
  requirement without inventing syntax: `impl BlockingIo for T` and
  `impl AsyncIo for T` must be accompanied by `impl Io for T` in the same
  compilation unit, and Milestone 9 adds that checker invariant together
  with the exclusion of a type that implements both markers. Milestone 9
  signatures spell both bounds (`I: type(Io, AsyncIo)`) until a supertrait
  spelling exists.
- `check_cancel` is a required `Io` v1 surface addition, not a new trait.
  `Blocking` implements it as an immediate return; `Evented` and `SimIo`
  observe the calling task's structured cancellation. Like every capability
  operation it is a potentially suspending call by signature.
- `Evented` is the hosted executor. The process-wide executor is created by
  the first `Evented.new` or `Evented.configured` call; a later call with the
  same configuration returns another token to that executor, and a different
  configuration is program misuse that terminates through
  `core.panic.panic` with a fixed diagnostic. Tokens are copyable and
  interchangeable. The executor supplies the multithreaded pool for portable
  tasks, one local lane for thread-affine tasks and platform event sources,
  timers, cancellation and wakeups, async files where the host supports them,
  sockets, DNS, subprocess waiting, and the bounded blocking pool. The local
  lane is not configurable in v1. The executor stops at process exit after
  every program task has finished; v1 has no explicit shutdown API.
- `ExecutorConfig` configures worker counts only. `Fixed(0)` is invalid and
  terminates through `core.panic.panic`; `Automatic` chooses from host
  parallelism. Worker counts change throughput, never observable results
  beyond the documented `std.task.race` and channel FIFO rules.

### v1 spelling choices

Where [Async](async.md) leaves a narrow spelling open, these snapshots choose
the following and every module uses it consistently. Changing one is a v1
amendment, not an implementation detail.

- `await` is a prefix operator and has no method form; `try await task`
  composes right-to-left. `Task(T)` exposes no `await` method.
- `timeout`'s error type is `std.task.Timeout` and its single variant is also
  `Timeout`, so `Err(Timeout)` and `Err(Timeout.Timeout)` both resolve. The
  timeout call is a free function taking the capability, as in `async.md`.
- `race` has arity two and is a free function taking the capability. Its
  result is the winner's `T`; errors are never merged.
- `yield` and `blocking` are free functions taking the capability; `spawn`,
  `start`, and the group constructors are group operations.
- `std.task` owns the cooperative token pair: affine `Cancellation` source,
  copyable source-scoped `CancellationToken`, error `CancellationError` with
  the single variant `Cancelled`.
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

## Networking, HTTP, and TLS

Required modules:

- `std.net`: IP/socket addresses, DNS, affine TCP listeners/streams, UDP,
  socket options, and capability-based operations;
- `std.url`: parsing, normalization, percent encoding, and relative resolution;
- `std.net.http`: streaming HTTP/1.1 and HTTP/2 client/server APIs, limits,
  redirects, proxies, cancellation, and explicit body ownership;
- `std.net.tls`: client/server TLS, certificate validation, system and explicit
  trust stores, SNI/ALPN, secure defaults, and version reporting.

TLS verification is enabled by default; disabling it requires an explicit
unsafe/testing-named configuration. The exact cryptographic backend is pinned
and disclosed by the toolchain. Alder 1.0 does not invent general-purpose
cryptographic primitives beyond secure random and the operations required by
the audited TLS API.

## Data formats and utilities

Required modules:

- `std.json`: bounded parser, streaming reader/writer, generic value tree,
  deterministic serializer options, and explicit typed conversion;
- `std.encoding`: hex, Base64, UTF encodings, endian utilities;
- `std.cli`: argument tokenization and a small declarative option parser;
- `std.log`: structured levels/fields, synchronous baseline, and replaceable
  sinks;
- `std.os`: narrow portable OS facts and explicitly target-specific submodules.

JSON defaults reject duplicate object keys when converting to a map, enforce
configurable depth/size limits, preserve number text in the generic form, and
never silently narrow into an Alder number.

Compression, regular expressions, database clients, GUI frameworks, and
application protocols beyond HTTP are suitable official or third-party Git
packages, not required `std` modules for 1.0. A native desktop UI toolkit is
planned as an official package after 1.0 ([D021](design-decisions.md#d021--native-ui-is-an-official-package-after-10)).

## C support

`std.c` provides raw C scalar types, pointer tokens, checked conversions,
temporary NUL-terminated strings, owned foreign-buffer helpers, callback
owners, and target ABI facts. Raw pointer dereference, arithmetic, conversion,
and calls remain restricted to `unsafe c`.

Platform wrappers in `std` contain audited `unsafe c`; their public APIs expose
safe values, affine resources, and `Result`. No public API exposes S0
`Domain`, `DomainMark`, `__s0_*`, fixed-capacity map, or callback cleanup bridge.

## Testing and documentation

Required modules and tools:

- `std.test`: assertions, expected-error helpers, temporary resources,
  deterministic random seeds, `SimIo`, parameterized cases, fuzz inputs, and
  subprocess tests;
- top-level `test` declarations with `Unit` or `Result(Unit, E)` outcomes
  discovered by `alder test`;
- `alder doc` API documentation from public declarations and doc comments;
- examples in doc comments compiled and run as tests.

A failed `assert_eq`, `assert_ne`, or comparison assertion prints the source
expression and both operand values; a failed `assert` prints its expression
and the values of the bindings it reads. A failure message never only says
"assertion failed".

A parameterized test runs once per listed case, and each case is reported and
can be rerun by its own name. A fuzz test asks for generated input through
`std.test`; ordinary runs use a fixed seeded corpus plus every saved failing
input, so they stay deterministic, and only `alder test --fuzz` runs an
open-ended campaign. A new failing input is saved under the package's test
data directory and reported with the command that replays it.

`SimIo` is a deterministic `AsyncIo` for tests: one worker, a virtual clock
that advances only when every task is blocked on time, and a test failure that
lists each blocked task when the program deadlocks. Its v1 surface is frozen in
[the Milestone 9 snapshots](#stdtestsimio-public-snapshot-v1).

Implemented std.test progress: `sysroot/std/test.al` installs the
runner-independent slice. `fail`, `assert`, `assert_eq`, and `assert_ne` are
thin `Unit` wrappers over `core.panic`; `expect_ok`/`expect_err` return the
named payload and terminate with a fixed diagnostic on the wrong arm (with the
error displayed for `expect_ok`); `TempFile.new`/`TempDir.new` turn `std.fs` setup
failures into termination and return the affine owners; and `Case`/`cases`
draw deterministic seeds from `std.random.Rng.seeded`. Evidence:
`compiler/production_std_test_test.go` checks the passing helpers, independently
computed SplitMix64 seeds, every documented failure format at status 101, and
the non-`Display` rejection; the snapshot example runs with a fixed checksum.
The remaining runner surface in this section is the M8 tooling target, not
part of the installed module yet. `SimIo`'s v1 surface is frozen in
[the Milestone 9 snapshots](#stdtestsimio-public-snapshot-v1) and remains
unimplemented.

## Error taxonomy

Modules use domain-specific enums such as `IoError`, `PathError`, `ParseError`,
`NetError`, `TlsError`, and `ProcessError`. They implement `Error` and retain
portable categories plus optional platform details. Libraries do not collapse
all failures into strings or ambient integer error codes.

Errors are ordinary values and may carry safe source ranges, paths, and causal
context. There is no hidden exception chain.

Each module declares the precise error enum its operations can return; it does
not re-export a dependency's error or fall back to a catch-all. A wrapped
lower-level error is a typed variant payload reached by `match`; `Error.cause`
returns its `ErrorReport` (D025), and `program error:` output prints the chain
one cause per line. `core.result`
provides `map_error` for adaptation; no implicit conversion exists.

## Portability and unsupported capabilities

A module may expose an operation unavailable on one supported target. That
operation returns a typed `Unsupported` error or is isolated in an explicitly
target-specific submodule; it does not compile and fail later through a missing
C symbol. Core module semantics are identical across tier-1 targets.

The 1.0 release matrix and acceptance requirements are defined in
[Alder 1.0](alder-1.0.md).
