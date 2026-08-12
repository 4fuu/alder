# Roadmap

This roadmap orders the shortest path to source self-hosting and then to the
complete [Alder 1.0 product contract](docs/alder-1.0.md). Dates are
intentionally omitted until implementation velocity and semantic risk are
better understood. A planned milestone is a required implementation gate, not
a claim that its documented 1.0 features work today.

## Project Principles

1. Validate semantics before optimizing them.
2. Keep one production path during bootstrap: Alder MIR to C11.
3. Make unsafe behavior explicit and locally auditable.
4. Prefer deterministic, inspectable compiler output.
5. Do not expand the user-facing memory model to fix isolated performance cases.
6. Start self-hosting as soon as a small Alder subset can express the compiler; do not first build a complete compiler in Go.

## Active Scope

### Milestone 0: Design Baseline

Status: **complete as the Alder 1.0 documentation baseline**

Deliverables:

- document language goals, non-goals, and unresolved semantics;
- freeze the required Alder 1.0 language, async, standard-library, C interop,
  module/package/build, xmake-provider, tooling, and release boundaries;
- document compile-time `type` values, type application, inference, and the monomorphization boundary;
- define the first versioned Alder MIR vocabulary;
- define the C11 lowering contract and undefined-behavior policy;
- establish repository, contribution, and orb lifecycle standards;
- choose representative validation programs.

Exit criteria:

- every initial MIR operation has a documented type and effect;
- storage-domain and cleanup invariants can be checked without consulting source syntax;
- the C backend document explains how safe MIR avoids C undefined behavior;
- open questions are explicit rather than hidden behind examples.

The baseline is intentionally amendable: an explicit design decision may
change it before 1.0, but must update its owning document, decision register,
examples, roadmap, and later executable tests together. Documentation status
does not imply implementation availability.

### Milestone 1: MIR Toolkit

Status: **complete**

Deliverables:

- a small Go module with no unnecessary third-party dependencies (`mir` and `mir/verify`);
- in-memory MIR types using stable integer IDs rather than pointer-linked compiler graphs;
- deterministic textual MIR parser and printer (format version 1, pinned by golden fixtures);
- MIR verifier with source-independent diagnostics covering all ten documented phases;
- golden tests and invalid-MIR tests with pinned diagnostics.

Exit-criteria evidence:

- parse-print-parse reaches a stable canonical form across all golden, verifier-acceptance, and verifier-rejection fixtures;
- malformed textual and public-API-built modules fail without panics and with deterministic diagnostics;
- the verifier covers all ten documented phases, including instruction-boundary failure edges, interprocedural domain and table effects, path-sensitive cleanup, and unsafe-boundary checks;
- a cross-process pipeline harness compares byte-for-byte output from isolated processes with different working and temporary directories;
- golden, acceptance, rejection, determinism, race, and vet checks pass without a future source frontend.

MIR 1 intentionally retains documented conservative restrictions where exact
provenance is not representable, including direct SSA identity for cleanup
handles, possible aliasing between external table or domain parameters, and no
lifetime-bearing stores through dereference places. A MIR interpreter for
differential backend testing remains an open question until the C backend
exists; it is not required for this milestone.

### Milestone 2: Minimal Runtime

Status: **complete**

Deliverables (implemented in `runtime/c/alder.h` and `runtime/c/alder.c`):

- portable C11 storage-domain primitives: init/alloc/mark/reset/destroy with parent-child tracking;
- epoch-scoped marks, resets to the empty frontier, segmented bump allocation (doubling regular segments up to 1 MiB, dedicated exact-size large segments), alignment and overflow/OOM handling;
- scoped cleanup: begin/push/disarm/run/end with reverse-order, at-most-once execution;
- checked arithmetic, explicit left/right shifts, division, and bounds helpers for the 64-bit MIR operations, plus defined float-to-integer conversions;
- a minimal generational table: non-wrapping serial identity, slot generations, domain-reset epochs, growth, and stale-id rejection;
- strict-warning compile-and-run tests for every area, with ASan/UBSan reruns when the host toolchain supports them.

Exit-criteria evidence:

- every runtime API carries an explicit failure and lifetime contract in `runtime/c/alder.h` and `docs/c-backend.md`;
- repeated domain create/reset/destroy cycles are leak-free: a live-allocation counter proves zero retained heap blocks on every tested host, and the same suites rerun under ASan/UBSan where the toolchain supports them (the current mingw-w64 host lacks libasan/libubsan, so those runs skip);
- empty-frontier reset, consumed-mark rejection, and stable integer mark identities are pinned by runtime and verifier tests;
- stale generational IDs never resolve to reused objects: slot reuse always assigns a fresh generation, ids carry a non-wrapping table serial, and reset/destroy/re-init changes the owning domain identity or epoch;
- cleanup runs exactly once across success and failure paths: reverse-order execution, disarmed skipping, and contract-violation handling are pinned by tests.

### Milestone 3: C11 Backend

Status: **complete**

Deliverables (implemented in the `cgen` package):

- deterministic MIR-to-C11 lowering with ID-based naming, erased unit values, and parallel block-parameter copies at every edge;
- explicit sequencing of all side effects as statements, with instruction-local temporaries;
- dependency-ordered aggregate, enum, option, result, and function-pointer types with collision-free ordinal fields and portable empty aggregates;
- checked operations with 64-bit runtime helpers, promotion plus range checks for narrow widths, portable arithmetic right shifts, and checked slice bounds, nullability, and `size_t` conversion;
- domains, scoped cleanup with generated adapters and per-site contexts, identity-preserving domain-backed tables, and generated per-type `copy_to_domain` helpers;
- C ABI declarations for backend-safe imported symbols and generated functions;
- compile-and-run behavior fixtures with drivers under the strict warning set;
- deterministic output pinned in-process and across isolated processes.

Exit-criteria evidence:

- every golden fixture compiles without warnings under the strict warning set (`-std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion`);
- generated programs pass runtime behavior tests (all integer widths with operation-specific 8/64-bit boundaries and intermediate-width overflow/shift cases, guarded float narrowing, loops and parallel edges, enum/option/result dispatch, domains with marks and resets, cleanup exactly-once on success and failure paths, table aliasing and growth, stale-id rejection, null-slice ranges, and string-byte preservation);
- signed overflow, shifts, indexing, aliasing, alignment, and evaluation order have defined lowering rules in `docs/c-backend.md`;
- generated C is inspectable and independent of host paths, verified by cross-process determinism tests;
- ASan/UBSan reruns probe the host toolchain and skip when unsupported (the current mingw-w64 host lacks libasan/libubsan);
- unverified modules, uninitialized local loads, unsafe external names, and non-copyable `copy_to_domain` targets are rejected with diagnostics.

A MIR interpreter for differential testing remains an open question; the compile-and-run fixtures provide the behavioral evidence, so the interpreter is not required for this milestone.

### Milestone 4: Bootstrap Language Subset

Status: **complete**

Deliverables (implemented in the `frontend` Go package):

- a deterministic lexer, parser, type checker, and MIR emitter for the
  single-file source subset now isolated in `docs/s0-language.md` (Alder S0):
  functions, primitives, structs, enums with `match`, slices and `String`,
  `Option`/`Result` with `try`, a fixed-capacity `Map` helper, bootstrap
  domain intrinsics, callback-bearing `using` cleanup, and direct concrete C
  symbol declarations called through `unsafe c`;
- compile-time `type` parameters with parenthesized application syntax,
  inference from runtime arguments and expected results, all-or-none explicit
  type arguments, rejection of specialization-expanding polymorphic
  recursion, and complete monomorphization before any backend MIR exists;
- deterministic diagnostics with line and column, pinned by rejection
  fixtures;
- a reorder pass emitting callees before callers so the printed MIR round
  trips through the single-pass MIR 1 text parser (call cycles are left in
  instantiation order and documented as unrepresentable in the text format).

This reorder pass records the M4 implementation at its acceptance point. M5.2
supersedes it with function-header predeclaration in the MIR 1 parser and uses
deterministic frontend instantiation order directly.

The `__s0_domain_create`, `__s0_alloc`, `__s0_domain_mark`,
`__s0_domain_reset`, `__s0_domain_destroy`, and `__s0_map_create` names, the
`Domain`/`DomainMark` types, and `using x = expr with CleanupFn` are temporary
MIR 1 bootstrap bridges. They do not implement or replace the intended
compiler-inferred storage, `Table(T)`/generational `T.Id`, and resource-owned
cleanup model. S0 has no fixed arrays, source modules, header importing,
storage inference, table surface, structured concurrency, traits, closures,
or methods, and is not a complete language frontend.

M5.3 also carries the private `__s0_Buffer(T)`/`__s0_Error` buffer bridge and
its `__s0_buffer_*` operations. It exists only to unblock Stage 0 plain-value
buffering; it is not final `Vec` or standard-library semantics. The frontend
owns this bridge, and source declarations plus the standard collection API
are the removal trigger. Test-only runtime fault injection pins initial and
growth-allocation `OutOfMemory`, old-buffer validity after failed growth, and
successful retry. An out-of-band C driver pins capacity-doubling `Limit`
without exposing a source capacity escape hatch. Broader identity-exhaustion
evidence remains part of the active M5.3 readiness gate.

Exit-criteria evidence:

- ten end-to-end source programs (arith, structs, enums, option, strings,
  generic, domains, maps, cleanup, ffi) compile through the full pipeline to
  verified MIR and then to strict-warning C11, compile with the canonical
  strict warning set, and pass runtime behavior checks (including a map with
  struct keys, 14-entry probe stress, and observable FFI-backed cleanup
  ordering);
- accept fixtures pin the printed MIR; rejection fixtures pin diagnostics
  covering syntax, typing, mutability, generics, map restrictions,
  cycles, match exhaustiveness, `try` error matching, `using` discipline,
  and the MIR 1 restrictions (direct marks, direct cleanup handles,
  materializable fail values, callee-before-caller ordering);
- printed MIR re-parses and re-verifies for every end-to-end fixture;
- in-process and cross-process determinism checks cover the printed MIR and
  the generated C;
- ASan/UBSan reruns are not available on the current mingw-w64 host
  (missing libasan/libubsan), so sanitizer coverage is reported as skipped.

This evidence covers the documented representative S0-to-MIR-to-C11 path; it
does not claim that S0 exercises every backend mechanism.

## Milestone 5: Self-Hosted Compiler

Milestone 5 is split into dependency-ordered gates. Passing a later gate must
not weaken MIR verification, explicit `unsafe c`, deterministic output, or the
portable C11 path.

### Milestone 5.0: Alder Identity Migration

Status: **complete**

The language, repository, Go module, runtime ABI, generated C namespace,
environment variables, documentation, and source fixtures use Alder naming.
Source fixtures use `.al`; there is no compatibility alias for the pre-release
Aster C ABI. Commit `a3ed108` passed all Go, race, end-to-end, round-trip,
determinism, and strict C11 checks before the GitHub repository was renamed.

### Milestone 5.1: Compiler Service and Structured Diagnostics

Status: **complete**

Deliverables:

- explicit immutable source identities and UTF-8 byte ranges;
- one structured diagnostic model with stable codes, severity, primary and
  related ranges, notes, and deterministic ordering;
- human and versioned JSON renderers over the same diagnostic records;
- a pure request/result compiler service that accepts an explicit source list;
- a thin `alder` executable initially limited to `check`, `compile`, MIR/C
  emission, and deterministic non-interactive machine output;
- lossless access to source text and lexical trivia needed by a later
  formatter, without making formatting part of this milestone.

Exit criteria:

- human and JSON diagnostics agree on codes and source ranges;
- machine mode emits one versioned result envelope and never mixes diagnostics
  with generated MIR/C bytes;
- logical paths and outputs are independent of absolute checkout, working, and
  temporary directories;
- malformed source produces structured diagnostics while I/O and internal
  failures remain distinct;
- the existing single-file corpus still produces verified MIR and deterministic
  C through the compiler service and CLI.

Exit-criteria evidence:

- commit `bea2850` adds the filesystem-independent `compiler` request/result
  service and the `alder check` / `alder compile` command adapter;
- all existing end-to-end `.al` sources produce byte-identical MIR and C across
  repeated service invocations, and CLI human/JSON diagnostics are identical
  across distinct absolute workspace roots;
- machine success, source-diagnostic, usage, and I/O paths emit one JSON v1
  envelope; writer failures, invalid ranges, and unknown source identities fail
  without appending a second output format;
- logical input and output names use one canonical slash-relative validator;
  output replacement is committed by a same-directory rename and retains the
  previous target on failure;
- the canonical format, vet, test, and race checks pass, and a separately built
  `alder` process emitted C that passed the strict GCC C11 warning set.

### Milestone 5.2: Deterministic Multi-File Compilation

Status: **complete**

- compile an explicit, deterministically ordered source set as one compilation
  unit before introducing packages or separate compilation;
- support cross-file declarations and deterministic duplicate diagnostics;
- make textual MIR round-trip forward and recursive calls through deliberate
  predeclaration or a versioned MIR change;
- define a stable generated-C entry signature and an audited C host shim;
- keep filesystem discovery in the driver, never in the compiler core.

Exit requires shuffled source order to produce identical diagnostics, MIR, and
C; recursive printed MIR must parse and verify; and separately linked generated
C must launch through the audited host shim without Go code or a Go runtime.
Safe argument, file, and output access is deferred to M5.3; an Alder-written
executable that consumes `.al` files and emits C is a M5.4 self-hosting gate.

Exit-criteria evidence:

- the compiler service and CLI accept copied, explicit source sets, canonicalize
  them by logical path, and produce byte-identical diagnostics, MIR, and C for
  every tested input permutation without scanning the filesystem in the core;
- cross-file declarations share one top-level namespace, and duplicate
  diagnostics carry deterministic primary and related source ranges;
- MIR 1 and MIR 2 predeclare function headers in textual order, round-trip self,
  forward, mutual-recursive, and cleanup-callback references, and retains
  declaration-before-use for named types, constants, and imports;
- program generation verifies MIR before entry validation, exports only
  `alder_program_entry`, and links the separate host shim under strict C11;
- no-domain, domain-root, null-context, nonzero-status, and recursive-program
  cases pass compile-and-run tests, and a separately built `alder` executable
  passed real multi-source permutation, emission, strict-link, and run checks;
- format, diff, vet, full test, race, focused round-trip/determinism, and strict
  GCC C11 checks pass.

### Milestone 5.3: Bootstrap Capability Readiness

Status: **complete**

The private declaration spike in `bootstrap/spike/*.al` is owned by M5.3. It
consumes only an explicit host snapshot and emits `ALDER-DECL-MANIFEST 1`; its
line grammar, balanced nesting probe, and manifest are capability-test
protocols, not Alder semantics.
Remove the spike when the M5.4 compiler core replaces it with the shared
production frontend and diagnostic representation.

Checked-operation failure is a valueless invariant panic after explicit
current-function cleanup; typed `fail` remains ordinary `Result` propagation,
and no fabricated result or caller-frame unwinding is permitted. This
incompatible terminator is carried by MIR 2 while legacy MIR 1 fixtures remain
supported; process-level tests pin division-by-zero cleanup order, narrow
overflow, and fixed-map capacity failure. MIR 3 adds `alloc.checked` so
bootstrap storage can report allocation preparation and runtime failures
without terminating or mutating prior state. Deterministic initial/growth OOM,
runtime segment-identity exhaustion, successful retry, and prior-buffer
validity are pinned at the buffer gate. Narrow-target `SIZE_MAX` behavior still
requires a supported target environment. The declaration spike justifies the
storage, growable byte/vector, symbol, diagnostic, safe argument/file/output,
and host-wrapper capabilities actually required by the compiler. The first
production lexer slice additionally demonstrated the need for non-recursive
Buffer growth in byte loops: Phase 6 now permits cyclic local descriptors whose
dynamic roots are owned only by parameter domains that the function cannot
invalidate, while retaining the local-domain, block-argument, dereference-store,
and parameter-invalidation-through-call, cleanup, and aliasing rejection gates.
Every temporary bridge has an owner and removal condition.

Exit requires compiler-scale tests with multiple files, more than sixteen
declarations, retained source/range data, nested syntax, recursion, malformed
input, growth boundaries, and failure cleanup, all producing deterministic
verified MIR and C.

Exit-criteria evidence:

- commits `d91f60a`, `ce3ce47`, and `b06983f` replace fabricated checked
  results with cleanup-aware panic, add recoverable checked allocation to MIR
  3, and provide the private growable Buffer bridge with deterministic initial
  and growth OOM, identity-exhaustion, prior-buffer-validity, limit, and retry
  tests;
- commit `f58bb24` adds the explicit, byte-safe host snapshot and declaration
  spike, whose compiler-scale corpus covers multiple binary source files, more
  than sixteen declarations, retained paths/text/ranges, nested delimiters,
  recursive declaration processing, malformed input, buffer growth, and
  deterministic verified MIR/C and strict C execution;
- commits `e0d4484` and `b58d5bf` pin the conservative external-domain loop
  lifetime rule and exercise it in the first production lexer slice with
  iterative source and byte scans, lossless trivia, malformed UTF-8 and syntax,
  growth past initial capacity, stable source-order diagnostics, and repeated
  process/source-permutation determinism;
- Linux/GCC acceptance at `b58d5bf` passed format, vet, full and race tests,
  strict C11, GCC analyzer, generated-C behavior, and complete runtime/cgen
  ASan/UBSan suites without a skipped compiler-dependent check. Narrow-target
  `SIZE_MAX` remains a target-specific portability check, not an unsupported
  bootstrap failure path on accepted hosts.

### Milestone 5.4: Self-Hosted Compiler Core

Status: **active**

`compiler/src/*.al` is the fixed, explicit production compiler source root. Its
current source model, lossless lexer, syntactically complete current S0 parser,
and declaration-resolution checker slice are preparatory M5.4 work. They pin
Go-compatible token kinds, keywords, trivia, byte ranges, literal escapes,
lexical failures, host-snapshot order, imports, generic struct/enum declarations,
recursive type expressions, function declarations, core bindings, returns,
assignments, blocks, ordinary expressions, control flow, match and unsafe
expressions, deterministic
first-failure order, verified MIR/C, and strict C execution. The checker slice
collects stable top-level symbols and owner-local type parameters, resolves
declaration-level type names and arities, records fields, variants, import and
function signature items with stable semantic IDs, rejects duplicate aggregate
members and empty enums, rejects deterministic value-type cycles, and now
performs concrete generic substitution/revalidation for current slice, buffer,
map, and recursive-specialization representation restrictions. Binding traversal
restores caller context, compares `String` with its `[U8]` semantic form, and
memoizes equivalent interpreted declaration specializations independently of
active ancestry so finite declaration DAGs do not expand by path. The checker
also restricts C import signatures to primitives and `Ptr(primitive)`, and
rejects duplicate or reserved function runtime parameter names before body
checking. Its body slice checks a
nongeneric body whose complete shape is zero or more annotated let/var
bindings and plain-identifier assignments followed by one top-level return: a
runtime parameter or local identifier must have the declared type, `true` and
`false` require `Bool`, a bare return requires `Unit`, an integer literal must
fit the declared integer type, and a string literal requires `String` or
its `[U8]` semantic form. Binding order mirrors the Go checker: reserved
names, annotation resolution, initializer mismatch, Unit/DomainMark
rejection, then duplicates; parameters are immutable assignment targets.
Integer bounds compare canonical decimal
digit text against per-type bounds, preserving every `U64` value and the `I64`
minimum rather than inheriting Stage 0's signed host-storage limit. Stable
tagged expression, local-binding, and return records retain parameter, local,
Bool-payload, and result-use relationships;
unsupported body shapes and expression forms outside this slice remain
deferred, and a deferred body discards its partial records. These checks
are preparatory: general body checking, other literals, locals, calls, control
flow, missing-return analysis, inference, monomorphization, MIR lowering, the
full checker, and the complete frontend remain incomplete. Its
current reverse-link and declaration-phase replay are recursive and are not yet
an arbitrary-size stack contract. The token, parser, and checker manifests are
private conformance protocols. The fixed production entry now loads its explicit
host snapshot and runs the shared lexer, parser, and current checker in order,
stopping at the first failed phase and emitting that phase's private manifest.
This integration is execution evidence only; these slices do not open a second
frontend, replace the M5.3 declaration spike yet, constitute a complete frontend,
or satisfy any self-hosting claim. Grouping nodes follow the Go semantic AST and
are erased; the lossless token stream retains their delimiters.

The independent MIR model now pins its MIR 3 numeric, 1-based ID, flattened
ownership, ordinal, reciprocal-link, named-type-part, and import-signature
encoding contract with an Alder-generated conformance manifest and malformed
raw-record fixtures. This is preparatory consumer work only; it does not provide
a MIR printer or verifier.

Port lexing, parsing, checking, inference, monomorphization, MIR construction,
all ten verifier phases, diagnostics, and C11 generation to Alder. The Go
compiler (`alder0`) produces C for the Alder compiler; a system C compiler
builds `alder1`. `alder1` must compile the shared corpus without Go in `PATH`
and without skipping or repairing MIR verification.

This gate may claim only **self-hosting-capable**, not repeatable self-hosting.

#### Bootstrap execution policy

M5.4 advances by the smallest checker/lowering slices that make the compiler
compile itself. A finding blocks this path when it demonstrates source
miscompilation, unsafe generated behavior, malformed compiler state consumed as
valid, nondeterministic bootstrap output, compiler-scale nontermination or
resource explosion, or failure of the fixed explicit compiler corpus. Narrow
diagnostic wording, redundant decoder hardening, and coverage that does not
challenge the active semantic slice may be recorded for its owning later gate
rather than stalling self-hosting. This policy never permits a known safety or
semantic correctness counterexample to be declared complete.

### Milestone 5.5: Fixed Point and Source Bootstrap

Status: **planned**

Run `alder1 -> C2 -> alder2 -> C3` and require `C2 == C3` byte-for-byte. Commit
an auditable `bootstrap/alder.c`, compiler-source manifest and digests, runtime,
host shim, and regeneration harness. A clean source archive plus a system C
compiler must regenerate the committed C offline without Go or a prior Alder
installation.

Only after this gate is the Go bootstrap compiler frozen except for correctness
and bootstrap maintenance. This is a reproducible **source** bootstrap claim;
bit-identical native binaries require a separately pinned native toolchain.

## Alder 1.0 Implementation Gates

M5.5 produces a trustworthy compiler bootstrap, not the full language. Every
following milestone is required before the project may claim Alder 1.0. Their
contracts are already frozen in `docs/`; implementation may amend a contract
only through the documented design-decision process.

## Milestone 6: Local Modules and Deterministic Build Graph

Status: **planned after self-hosting**

Implement the one-file/one-module mapping, required `module`, explicit imports,
private-by-default visibility, `pub`/re-export, cycle rejection, manifest v1,
targets/profiles/triples, deterministic source enumeration and output layout,
and compiler-coupled sysroot behavior from
[Modules and Builds](docs/modules-and-builds.md). Establish the immutable
workspace snapshot and versioned build-plan boundary shared by CLI, tests,
packages, documentation, and later LSP.

Exit requires local multi-module `check`, `build`, `run`, and test-plan
construction without network access; path/order permutations must produce
identical graphs, diagnostics, MIR, and C. The compiler core still receives only
explicit sources and never scans the filesystem.

## Milestone 7: Complete 1.0 Language and Memory Model

Status: **planned after local modules; may be sliced in dependency order**

Implement the remaining source semantics in [Syntax](docs/syntax.md),
[Language Semantics](docs/language-semantics.md),
[Memory and Resources](docs/memory-and-resources.md), and
[Traits and Closures](docs/traits-and-closures.md): owned UTF-8 `String` and
`Bytes`, fixed arrays, ordinary `Vec`/ordered `Map`/`Set`, mutable slices,
inherent methods, static coherent traits, safe closures, inferred storage,
affine owners, `Cleanup`/`AsyncCleanup`, and the source `Table(T)`/`T.Id`
surface.

Exit requires focused acceptance/rejection tests for value independence,
owner transfer, view escape/overlap, storage retention fallback, cross-domain
copies, cleanup on every normal control exit, table staleness, trait coherence,
closure capture, generic monomorphization, and compiler-scale layered DAGs. The
public language and generated MIR/C may no longer expose `__s0_*`, `Domain`,
`DomainMark`, fixed S0 Map/Buffer, `String = [U8]`, or callback-bearing bootstrap
cleanup forms.

## Milestone 8: Verified C Bindings and Hosted Standard-Library Foundation

Status: **planned after the 1.0 resource/type model**

Implement target-aware `import c` binding blocks, raw C types, header/toolchain
probes, by-value verified records, explicit shims, safe ownership/retention
wrappers, C exports, and callback owners from
[C Interoperability](docs/c-interop.md). Build the provider-free hosted sysroot
foundation: formatting, Unicode text/bytes, collections, paths, I/O/files,
environment, processes, time, random, math, testing primitives, and audited OS
wrappers from [Standard Library](docs/standard-library.md).

Exit requires binding mismatch rejection and strict per-target ABI tests for
layouts, null/bounds/alignment, integer conversion, borrowed/retained buffers,
exactly-once release, callbacks and foreign threads. Standard APIs expose only
safe values, affine owners, `Result`, and locally audited `unsafe c`; no S0 C
bridge appears publicly.

## Milestone 9: Async Runtime and Structured Concurrency

Status: **required before Alder 1.0**

Implement `async fn`, `await`, state-machine MIR/lowering, affine `TaskGroup`
and `Task(T)`, structured cancellation with async cleanup, multithread and local
executors, channels, synchronization, atomics, timers, async files/sockets, and
the bounded blocking-C bridge defined in
[Async and Structured Concurrency](docs/async.md).

Exit requires data-race rejection, nested join/cancel/cleanup tests, channel
backpressure/FIFO tests, task-transfer and thread-affinity checks, high task
counts with bounded stack/storage, blocking C completion after cancellation,
and sanitizer/race coverage on supported hosts. No child may outlive its group
and no detached task surface may be introduced.

## Milestone 10: Batteries-Included Standard Library Completion

Status: **required before Alder 1.0**

Complete the [Standard Library](docs/standard-library.md) with async/sync
networking, DNS, TCP/UDP, URL, HTTP/1.1 and HTTP/2, TLS with secure defaults,
JSON, encodings, CLI parsing, logging, signals, async processes, and all required
cross-platform error contracts. Ship versioned Unicode, timezone, certificate,
and native provenance data with the toolchain.

Exit requires offline use after installation and complete Linux/macOS/Windows
behavior suites for paths, Unicode, I/O, cancellation, networking, TLS
verification, bounded parsers, process behavior, and unsupported capabilities.
HTTP/TLS/JSON are toolchain libraries, not an implicit network download.

## Milestone 11: Formatter, Test/Doc Tools, and Language Server

Status: **required distribution tooling before Alder 1.0**

Implement `alder fmt` over lossless syntax, the isolated deterministic test
runner (including async tests), `alder doc`, and baseline `alder lsp` over the
same snapshot, resolver, compiler service, diagnostics, and build plan.

Exit requires formatter idempotence/trivia and malformed-input behavior,
machine-readable stable test results, compiled documentation examples,
CLI/LSP diagnostic and formatting parity, UTF-8/UTF-16 conversion, overlay
isolation, cancellation/stale-result suppression, and no implicit fetch.

## Milestone 12: Locked Git Package Management

Status: **required before Alder 1.0**

Implement workspace/path and exact-revision Git dependency graphs, the
authoritative `alder.lock`, canonical-tree hashes independent of Git object
identity, immutable content-addressed caches, and `--locked`, `--offline`, and
`--frozen` modes from [Modules and Builds](docs/modules-and-builds.md). Network
is limited to explicit add/update/fetch commands.

Exit requires deterministic transitive resolution, content/path ambiguity
rejection, cache corruption detection, frozen offline builds, and hostile or
malformed repository tests. Registries, publishing, general semver solving,
submodules, Git LFS, and arbitrary lifecycle scripts remain outside 1.0.

## Milestone 13: Managed Native Provider

Status: **required default integration before Alder 1.0**

Provide managed, version-pinned xmake/xrepo as the default replaceable C/C++
provider below Alder's authoritative package/build-plan boundary. Pin the
xmake binary, recipe repository/file, sources, patches, configs, target,
toolchain, outputs, licenses, and hashes; separate network fetch from offline
build; disable implicit system packages in frozen mode; and treat recipes as
trusted executable native code.

Exit requires repeatable locked native plans and artifacts with a pinned
toolchain, offline rebuild, provenance output, system-provider drift reporting,
and identical Alder semantics through an alternate/source provider. The
compiler bootstrap and standard library must not require xmake.

## Milestone 14: Alder 1.0 Qualification

Status: **final release gate**

Satisfy every item in [Alder 1.0](docs/alder-1.0.md): fixed-point source
bootstrap; complete language/stdlib/tooling; tier-1 Linux x86-64/AArch64, macOS
x86-64/Apple silicon, and Windows x86-64 qualification; deterministic semantic
artifacts; strict C11; analyzers/sanitizers/race tests where supported;
allocation and malformed-input failures; compiler/runtime scale budgets; API
snapshots; compatibility/edition policy; and clean offline source/binary
distribution acceptance.

No earlier milestone may call the language or toolchain Alder 1.0.

## Deferred Work

The following items are not part of the current implementation scope:

- LLVM, Cranelift, QBE, or direct machine-code backends;
- JIT and REPL execution engines;
- package registry, publishing, and a general semantic-version solver;
- debugger integration and broad IDE refactoring/indexing;
- macros and compile-time execution;
- advanced optimization pipelines;
- remote build and cache services;
- stable native ABI promises beyond intentional C interfaces;
- bit-reproducible native binaries without a pinned native toolchain;
- dynamic trait objects and specialization;
- detached fire-and-forget tasks.

## LLVM Reconsideration Gate

LLVM may be reconsidered only after:

- MIR semantics are versioned and tested;
- the C backend passes representative correctness suites;
- self-hosting needs or measured workloads demonstrate a concrete limitation;
- a proposal defines dependency, versioning, distribution, debug-info, and differential-testing costs.

Until then, changes must not add LLVM libraries, bindings, conditional build flags, or LLVM-specific assumptions to MIR.

## Representative Validation Programs

The memory model should eventually be exercised by:

1. a parser with many phase-local allocations;
2. a request-style workload with one bounded top-level domain;
3. an entity graph using `Table(T)` and generational IDs;
4. a structured concurrent file scanner;
5. a small C library wrapper that tests pointer, length, error, and cleanup contracts.
