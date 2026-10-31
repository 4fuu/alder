# Alder 1.0 Standard Library

Design status: **Frozen minimum module and behavior set**

Availability: **Not implemented as a 1.0 sysroot**

Alder 1.0 ships batteries sufficient for command-line tools, services, file
processing, C wrappers, networking, and async applications. The library is
version-matched to the toolchain and available offline after installation.

This document freezes the minimum scope and major contracts, not every final
function spelling. Public API snapshots and executable examples become
normative as each module is implemented.

Implemented module snapshots are versioned separately so their exact spelling
can be reviewed without pretending the rest of the 1.0 sysroot is available:

- [`core.collection` public snapshot v1](api/core.collection-v1.md), covering
  the Milestone 7.1 `Vec(T)` surface;
- [`core.slice` public snapshot v1](api/core.slice-v1.md), covering the
  Milestone 7.1 immutable and mutable view surface.

## Distribution layers

The installed sysroot has two stability layers:

1. `core` is implicitly available, platform-neutral, and depends only on the
   minimal Alder runtime. It contains language-level algebraic types, traits,
   values/collections, slices, fixed arrays, checked numeric helpers, and
   minimal formatting contracts.
2. `std` is explicitly imported, hosted, and contains allocation, OS, async,
   network, test, and C support.

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
Display, Error, Cleanup, AsyncCleanup
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
  checked `get`, and exclusive mutable operations;
- `core.collection`: fundamental `Vec`, insertion-ordered `Map`/`Set`, and
  their checked/fallible capacity operations;
- `core.iter`: static iterator traits and common lazy adapters;
- `core.hash`: stable hashing contract plus process-randomized builders for
  attack-facing maps;
- `core.format`: `Display`, formatting arguments, and interpolation support;
- `core.memory`: safe size/alignment queries needed by generic code, without
  raw allocation;
- `core.panic`: `assert`, `assert_eq`, and process-terminating invariant APIs.

Index syntax is checked and terminates on an invalid index. `get` returns
`Option`. Checked, wrapping, and saturating numeric behavior is always explicit
in API names.

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

- `std.path`: owned `Path`, component iteration, lexical join/normalize,
  extension/name operations, and explicit platform conversion;
- `std.io`: `Reader`, `Writer`, and `Seek` traits; buffered readers/writers;
  standard input/output/error; exact/copy/line helpers; `IoError`;
- `std.fs`: affine `File`, directory iteration, metadata, permissions,
  canonicalization, copy/rename/remove, temporary files/directories, and
  synchronous plus async operations.

Path values preserve platform-relevant bytes/units and do not assume every OS
path is UTF-8. Display may escape non-text components. Directory iteration is
documented as host order; deterministic tools explicitly call the provided
sorted iterator.

`File` cleanup closes the descriptor. `finish`/`sync` return errors when a
caller must observe finalization. Failed writes are never reported as success
merely because fallback cleanup cannot return an error.

## Environment and processes

Required modules:

- `std.env`: exact host `OsString`, arguments, environment lookup/update,
  checked `String` conversion, current executable and directory, and
  platform/target information;
- `std.process`: value-semantic `Command`, affine `Child`, pipes, exit status,
  synchronous output, async wait, cancellation-aware termination, and explicit
  environment inheritance;
- `std.signal`: portable termination/interrupt subscriptions plus
  target-specific extensions behind capability checks.

No API invokes a shell unless its name explicitly says `shell`. The default
process API passes an argument vector directly and never performs hidden
quoting or expansion.

## Time, random, and math

Required modules:

- `std.time`: monotonic `Instant`, wall-clock `SystemTime`, checked `Duration`,
  timezone-independent UTC conversion, timers, sleep, and async sleep;
- `std.random`: OS cryptographic randomness, deterministic seeded generators
  for simulation/tests, and unbiased ranges;
- `std.math`: portable scalar math with documented IEEE behavior and explicit
  exceptional results.

Calendar and timezone databases are versioned distribution data. Ambient C
rounding-mode changes are outside safe wrappers and cannot silently redefine
Alder numeric semantics.

## Async and synchronization

Required modules:

- `std.task`: `TaskGroup.new`, result-bearing `spawn`, unit-returning `start`,
  scoped `Task(T)`, parent-exit cancellation, cooperative cancellation tokens,
  internally joined timeout/race, yield, executor configuration, and bounded
  blocking work;
- `std.channel`: bounded/unbounded channels with FIFO and backpressure;
- `std.sync`: group-scoped `Shared(T)`, mutex/RW-lock guards, one-time
  initialization, and barriers;
- `std.atomic`: fixed-width integer, boolean, and pointer-free atomics with
  explicit memory ordering.

These modules implement [Async and Structured Concurrency](async.md). They do
not provide an implicit detached task, arbitrary single-handle `Task.cancel`,
or an unsafe user-asserted transfer trait.

## Networking, HTTP, and TLS

Required modules:

- `std.net`: IP/socket addresses, DNS, affine TCP listeners/streams, UDP,
  socket options, and sync/async operations;
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
  deterministic random seeds, async tests, and subprocess tests;
- top-level `test`/`async test` declarations with `Unit` or
  `Result(Unit, E)` outcomes discovered by `alder test`;
- `alder doc` API documentation from public declarations and doc comments;
- examples compiled as tests when marked as Alder code.

The test runner isolates tests by process by default, captures output, reports
stable machine-readable results, and never depends on directory enumeration
order. Network tests require an explicit opt-in capability.

## Error taxonomy

Modules use domain-specific enums such as `IoError`, `PathError`, `ParseError`,
`NetError`, `TlsError`, and `ProcessError`. They implement `Error` and retain
portable categories plus optional platform details. Libraries do not collapse
all failures into strings or ambient integer error codes.

Errors are ordinary values and may carry safe source ranges, paths, and causal
context. There is no hidden exception chain.

## Portability and unsupported capabilities

A module may expose an operation unavailable on one supported target. That
operation returns a typed `Unsupported` error or is isolated in an explicitly
target-specific submodule; it does not compile and fail later through a missing
C symbol. Core module semantics are identical across tier-1 targets.

The 1.0 release matrix and acceptance requirements are defined in
[Alder 1.0](alder-1.0.md).
