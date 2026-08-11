# Roadmap

This roadmap separates committed near-term work from longer-term direction. Dates are intentionally omitted until implementation velocity and semantic risk are better understood.

## Project Principles

1. Validate semantics before optimizing them.
2. Keep one production path during bootstrap: Alder MIR to C11.
3. Make unsafe behavior explicit and locally auditable.
4. Prefer deterministic, inspectable compiler output.
5. Do not expand the user-facing memory model to fix isolated performance cases.
6. Start self-hosting as soon as a small Alder subset can express the compiler; do not first build a complete compiler in Go.

## Active Scope

### Milestone 0: Design Baseline

Status: **in progress**

Deliverables:

- document language goals, non-goals, and unresolved semantics;
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
  single-file source subset defined in `docs/language-design.md` (Alder S0):
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
current source model, lossless lexer, and syntactically complete current S0
parser are only preparatory M5.4 slices. They pin Go-compatible token kinds,
keywords, trivia, byte ranges, literal escapes, lexical failures, host-snapshot
order, imports, generic struct/enum declarations, recursive type expressions,
function declarations, core bindings/returns/assignments, blocks, ordinary
expressions, control flow, match and unsafe expressions, deterministic
first-failure order, verified MIR/C, and strict C execution. Literal conversion,
checking, lowering, and the complete frontend remain incomplete. The token and
parser manifests are private conformance protocols; these slices do not open a
second frontend, replace the M5.3 declaration spike yet, constitute a complete
frontend, or satisfy any self-hosting claim. Grouping nodes follow the Go
semantic AST and are erased; the lossless token stream retains their delimiters.

Port lexing, parsing, checking, inference, monomorphization, MIR construction,
all ten verifier phases, diagnostics, and C11 generation to Alder. The Go
compiler (`alder0`) produces C for the Alder compiler; a system C compiler
builds `alder1`. `alder1` must compile the shared corpus without Go in `PATH`
and without skipping or repairing MIR verification.

This gate may claim only **self-hosting-capable**, not repeatable self-hosting.

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

## Milestone 6: Local Modules and Build Graph

Status: **planned after self-hosting**

Define module names, imports, visibility, cycle policy, manifest version,
target/profile/triple, deterministic source enumeration and output layout, and
compiler-coupled sysroot behavior. Establish shared workspace snapshots and a
deterministic build-plan boundary used by CLI, tests, packages, and later LSP.
Local multi-module build/check/test must work without network access before
remote packages are introduced.

## Milestone 7: Minimal Standard Library

Status: **planned after local modules**

Ship a toolchain-versioned sysroot containing ordinary Alder packages for
bytes, UTF-8 text, settled collections, paths, files, process execution, and a
minimal test API. OS calls stay in audited `unsafe c` platform wrappers. Public
APIs must not expose `__s0_*`, `Domain`, `DomainMark`, the fixed-capacity S0 Map,
or callback-bearing bootstrap cleanup forms.

## Milestone 8: Canonical Formatter

Status: **planned after lossless syntax stabilizes**

Implement `alder fmt` over lossless syntax rather than the semantic AST. Exit
requires idempotence, comment/trivia preservation, semantic equivalence for
newline-sensitive syntax, pinned malformed-input behavior, and a non-writing
`--check` mode.

## Milestone 9: Git Package Management

Status: **planned after local modules and sysroot**

Start with exact-revision Git dependency graphs, an authoritative `alder.lock`,
independent canonical-tree hashes, an immutable content-addressed cache, and
`--locked`, `--offline`, and `--frozen` operation. Network is limited to
explicit add/update/fetch commands. Registries, publishing, semver solving,
submodules, Git LFS, and arbitrary lifecycle scripts remain deferred until
their identity and trust rules are separately approved.

## Milestone 10: Managed Native Provider

Status: **planned after locked Alder packages**

Provide managed, version-pinned xmake/xrepo as the default replaceable C/C++
provider. Alder remains authoritative for package identity and locking. Pin the
xmake binary, recipe repository and file, sources, configs, target, and
toolchain identity; separate network-enabled fetch from offline build; disable
implicit system packages in reproducible mode; and treat recipes as executable
native code. The compiler bootstrap and standard library must not require
xmake.

## Milestone 11: Language Server

Status: **planned after workspace, diagnostics, and formatter**

Implement `alder lsp` as an adapter over the same immutable workspace snapshots,
resolver, syntax, compiler service, structured diagnostics, and formatter used
by the CLI. Begin with file-granularity analysis. LSP must not fetch packages or
native dependencies implicitly. Exit requires CLI/LSP diagnostic parity,
UTF-8/UTF-16 conversion tests, overlay isolation, cancellation and stale-result
suppression, formatting parity, and deterministic repeated sessions.

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
- production readiness or performance claims.

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
