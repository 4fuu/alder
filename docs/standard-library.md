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
- [`std.io` public snapshot v1](api/std.io-v1.md), covering the Milestone 8
  hosted capability layer (`Io`, `BlockingIo`, `Blocking`, `Reader`,
  `Writer`, `Seek`, buffers, standard streams, exact helpers, `IoError`, and
  the prelude `Error` trait contract);
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
- [`std.collection` public snapshot v1](api/std.collection-v1.md), covering
  the Milestone 8 stable sorting entry point over the Order domain in the
  installed sysroot.

M8 exit-audit status (main after the random and field-view commits):
`core.option`, `core.result`, `core.num`, `core.panic`, `core.error`,
`std.io`, `std.path`, `std.time`, `std.random`, `std.math`, `std.text`,
`std.bytes`, and `std.collection` are implemented with production-driver
evidence. `std.io` v1 is complete for blocking and host streams; its
`AsyncIo`/`Evented` half is Milestone 9. `std.fs` and `std.process` are in
progress under the std.io thread: their file, directory, temporary-owner,
value, and qualified-variant layers are on main, while process spawning,
pipes, and capture are missing. `std.env` is partial: `get` and the target
records are implemented, while `arguments`, environment updates,
`current_exe`, current-directory operations, and `target()` are missing.
`core.range` is deferred by scope decision; case mapping and normalization are
deferred to a `std.text` v2 amendment; async task, channel, sync, and atomic
modules are Milestone 9; networking, HTTP, TLS, data-format, CLI, log, OS,
test-runner, and doc-tool modules are post-M8. Still missing from the M8
foundation: `core.iter`, `core.hash`, `core.format`, `core.memory`,
`std.format`, `std.parse`, `std.signal`, numeric parse/format foundations,
and the `Deque`/heap parts of `std.collection`/`core.collection`. `std.c` is
the verified C-interop surface rather than a `.al` module; its exit audit is
complete.

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
- `core.iter`: static iterator traits and common lazy adapters;
- `core.hash`: stable hashing contract plus process-randomized builders for
  attack-facing maps;
- `core.format`: `Display`, formatting arguments, and interpolation support;
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

Implemented std.process progress (value layer): `sysroot/std/process.al`
installs `PipeMode`, the value-semantic `Command` and its in-place
builders, `ExitStatus` with exit/signal decomposition, `Output`, and
`ProcessError` with `Display` and `Error`. Stream modes and process
categories are constructed with qualified variant expressions such as
`PipeMode.Piped` and `ProcessError.Platform(info)`. Spawning, `Child`, pipe
ends, and captured output wait for the `std.io` slice 2 capability and host
handles.

Implemented std.fs progress (value layer): `sysroot/std/fs.al` installs
`Options.read`/`Options.write` and the portable `Permissions` record. The
affine file, directory, metadata, whole-file, canonicalization, and temporary
owner surfaces wait for the same slice 2 handles.

The hosted `std` module graph is acyclic and fixed by the snapshots:
`std.path` imports only `core`; `std.env` imports `std.path`; `std.io` imports
`std.path` and `std.env`; `std.fs` and `std.process` additionally build on
`std.io`, and `std.time` and `std.random` on `std.io`.

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
- `std.signal`: portable termination/interrupt subscriptions plus
  target-specific extensions behind capability checks.

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
`std.io` capability. Evidence: `compiler/production_time_test.go` checks
independently computed UTC vectors, duration arithmetic, the monotonic lower
bound of a sleep, and a zero-duration sleep through `Blocking`; the snapshot
example runs with a fixed checksum.

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
  configuration, and bounded blocking work;
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
lists each blocked task when the program deadlocks.

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
