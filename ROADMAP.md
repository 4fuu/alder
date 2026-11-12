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

The 2026-11 design review against 2024-2026 language developments amended the
baseline in documentation only: D012 replaces `async fn` coloring with I/O
capabilities and per-instance suspension, D018 adds `match` guards, D022 makes
the toolchain CLI-first with complete first-read diagnostics and required doc
comments, and D023 makes in-place update of uniquely owned values a cost
contract. Implemented milestones are unaffected.

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
cleanup model. At the M4 acceptance point S0 had no fixed arrays, source
modules, header importing,
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

Status: **complete**

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
restores caller context and, after M7, keeps public `String`, `Bytes`, and
`[U8]` identities distinct while retaining a private `__s0_String` bridge, and
memoizes equivalent interpreted declaration specializations independently of
active ancestry so finite declaration DAGs do not expand by path. The checker
also restricts C import signatures to primitives and `Ptr(primitive)`, and
rejects duplicate or reserved function runtime parameter names before body
checking. Its body slice checks concrete function instances compositionally
across lexical blocks, assignments, `if`/`else`, `while`, and slice `for`: a
runtime parameter or local identifier must have the declared type, `true` and
`false` require `Bool`, a bare return requires `Unit`, an integer literal must
fit the declared integer type, and a quoted literal adapts to distinct
`String`, `Bytes`, or private `__s0_String` context. Binding initializers, assignment right-hand sides,
and returns recursively check unary `-`/`!`, checked integer arithmetic and
shifts, integer/float comparison and equality, and short-circuit Bool operators
with the Go Stage 0 operand rules. Binding order mirrors the Go checker: reserved
names, annotation resolution, initializer mismatch, Unit/DomainMark
rejection, then duplicates; parameters are immutable direct assignment targets,
while immutable slice bindings retain reference-style indexed mutation. Block,
branch, loop, and `for` bindings do not escape. Assignment roots use stable local
IDs, fields use declaration ordinals after concrete generic substitution, and
indices require `U64` and the existing copy-trivial element restriction.
Integer bounds compare canonical decimal
digit text against per-type bounds, preserving every `U64` value and the `I64`
minimum rather than inheriting Stage 0's signed host-storage limit. Stable
postorder tagged-expression, local-binding, return, lexical-block, ordered-
statement, and assignment-place records retain parameter, local, Bool-payload,
child, operator, statement-site, scope, concrete type, and result-use relationships.
Unannotated bindings infer scalar types from supported literals, identifiers,
and unary/binary expressions. Checked types are canonical structure-deduplicated
DAG nodes with direct primitive targets and distinct public `String`, `Bytes`,
and `[U8]` identities; source
spellings live on annotations. Stable parameter/local binding IDs, persistent
environment chains, and flattened ordered expression-child ranges establish the
body model. Direct user calls now support all-or-none explicit type arguments,
structural inference from runtime arguments and expected results, generic record
construction, expected generic enum variants, and declared-enum unary-payload
inference. Concrete function instances are keyed by declaration ID plus ordered
canonical type IDs, registered before body checking, and processed in stable
first-discovery FIFO order. Calls share instances, same-instance and finite
concrete mutual recursion close normally, and active specialization-expanding
polymorphic recursion is rejected. Instance signatures, bodies, expression
types, aggregate applications, and user-call targets are concrete; stable
private-manifest instance IDs expose that backend-facing boundary. Concrete C
imports inside `unsafe c` retain their prior contract. Record children use
declaration-field order. Issue #7 adds callback `using` resolution,
exact concrete callback signatures, lexical bindings, nested cleanup scopes,
and lowering-facing normal/return/`try` exit facts without MIR CFG IDs. `using`
under a loop is rejected while loops nested beneath an active cleanup remain
valid. Non-`Unit` paths must return, loops conservatively fall
through, both `if` branches must return to guarantee return, and unreachable
statements are rejected before checking their contents. Issue #8 seals this S0
boundary: every concrete owner has one root block (including empty `Unit`
bodies), unsupported body syntax is one deterministic source failure rather
than silent record discard, and private manifest v14 carries canonical syntax
spans plus stable diagnostic codes, related ranges, and notes. Issues #9 and
#10 add the first Alder-owned lowering package over that sealed boundary. It
consumes only canonical concrete records plus Z spans and source bytes, rejects
malformed ownership and edges before output, and emits exact MIR for the
current scalar/call/aggregate/place slice and structured
`if`/loop/short-circuit/`match`/typed-`try` CFG. Active `using` cleanups are
selected from lexical environment chains and emitted in reverse order on scope
fallthrough, return, and failed `try`. Issue #11 adds the manifest-v14
bridge-to-MIR slice: domain create/mark/reset/destroy and allocation, active
lexical cleanup exactly once in reverse order, fixed 16-slot `Map` structural
hash/equality and probe helpers, private buffers with recoverable OOM retry,
and the required FFI bridge forms. Its MIR is independently parsed and
verifier-gated in the fixed shared-core harness. Issue #21 wires the production
entry from successful checking through canonical checked spans and unchanged
lowering into the complete V1–V10 verifier; only its complete result authorizes
textual MIR output. Issue #24 supplies the complete-verifier and preflight-gated
resource C backend slice. Later Alder 1.0 forms and language facilities remain
incomplete. Some reverse-link and declaration-phase traversals are recursive
and are not an arbitrary-size stack contract. The token, parser, and checker
manifests are private conformance protocols. The fixed production entry loads
its explicit host snapshot and runs the shared lexer, parser, and checker in
order.
Issue #25 replaces production private-manifest output with the shared
explicit-source `check`/`compile --emit=mir|c` contract, stable human/version-1
JSON diagnostics, faithful status classes, and atomic host output replacement.
Successful checking lowers directly to MIR 3 and emits the requested artifact
only after complete verification; malformed checked/lowered state, verifier
rejection, and C preflight rejection produce no artifact bytes. This S0
implementation does not open a second frontend or constitute the complete
Alder 1.0 frontend. Grouping nodes follow the Go semantic AST and are erased;
the lossless token stream retains their delimiters.

The independent MIR model pins its MIR 3 numeric, 1-based ID, flattened
ownership, ordinal, reciprocal-link, named-type-part, and import-signature
encoding contract with an Alder-generated conformance manifest and malformed
raw-record fixtures. An Alder textual printer now validates that independent
store before emitting canonical, source-independent MIR 3 bytes; malformed
stores are rejected without partial output. The sealed S0 lowering slice covers
the current resource/domain operations and is wired into the production
pipeline. Checker, textual-printer, and verifier V1–V10 conformance share one
fixed source closure and executable while retaining independent mode assertions;
the complete production root remains an independent end-to-end gate.

Port lexing, parsing, checking, inference, monomorphization, MIR construction,
all ten verifier phases, diagnostics, and C11 generation to Alder. The Go
compiler (`alder0`) produces C for the Alder compiler; a system C compiler
builds `alder1`. `alder1` must compile the shared corpus without Go in `PATH`
and without skipping or repairing MIR verification.

The independent Alder MIR consumer now provides all ten verifier phases for raw
MIR stores: integrity and reciprocal-ID checks, type/layout/declaration checks,
CFG target, switch, reachability, and edge-arity checks, plus point-level
dominance, checked-failure-edge availability, use-def, and definite local
initialization, followed by complete current-opcode operand, result, place,
projection, edge, call/import-call, aggregate, enum, checked-failure, and
terminator typing. Phase 6 adds domain identity and strict ancestry, allocation
provenance, path-sensitive reset/destroy state, interprocedural lifetime
effects, loop-carried resource rules, and safe-reference escape/use and
dereference-store rejection. Its stable numeric diagnostics are separate from
source diagnostics, and orchestration stops after the first failing phase.
Phase 7 adds path-sensitive cleanup scope and registration-stack identity,
checked-failure and multiexit handling, exactly-once execution, and repeatable
per-iteration lifecycles. Its path-specific active registration sets feed Phase
6 callback-argument validation, LIFO resource effects, and whole-module
function-effect summaries. Phase 8 validates table identity, lookup consumption,
view regions, aliasing, and mutation effects using those provenance and cleanup
facts. Phase 9 confines recursively raw-pointer-bearing values to explicit
unsafe FFI and function boundaries. Phase 10 validates conservative C11 element
types and external names. `mir_verify_complete` adds the hosted `main` contract
and returns the sole positive complete-verifier gate. The production source-to-
MIR path now consumes that complete result as its only output authorization;
the raw verified-MIR scalar/CFG generator is described below.

The independent Alder C-backend lane consumes those flat MIR 3 records
directly. Its retained declaration conformance API emits portable headers,
dependency-first type layouts, stable numeric names, constants, C import
prototypes, internal declarations, and the temporary hosted adapter. The
production-shaped `cgen_generate` entry additionally emits the complete M5.4
scalar/CFG body slice: ordered scalar and checked operations, places and
assignments, aggregates and enum-like values, direct and unsafe-import calls,
parallel-copy block edges, branches, loops, switches, and typed return/fail
control flow. Hand-built MIR fixtures pin a runtime backedge swap cycle,
checked failure, struct/enum/option/result and concrete-generic behavior, FFI,
strict C11, process determinism, no nested C evaluation-order shortcut, and
zero-output refusal. Both APIs call `mir_verify_complete` before allocating an
output buffer and consume the verifier-returned hosted mode and external entry
ID. Invalid or unsupported MIR is refused without repair. The current #24
domain/cleanup/table/buffer operation set is supported and the final driver
wires the verified production source slice to this C path.

This gate may claim only **self-hosting-capable**, not repeatable self-hosting.

Exit-criteria evidence on the fixed 28-file source root:

- `alder0` emits the compiler C and GCC links `alder1`; the ordinary production
  and S0 conformance suites run that executable with Go absent from `PATH`;
- the internal mutable buffer-slot operation supports deterministic dense
  compiler indexes without changing emitted semantic table identities;
- checker and verifier indexes remove the compiler-scale repeated-scan and
  Phase 6 dataflow nontermination blockers while preserving first-record
  lookup semantics, stable diagnostics, and table-order output;
- a native `alder1 check` of all 28 sources completes in 168.55 seconds on the
  measured Linux/GCC host, and `alder1` emits the next compiler C in 182.68
  seconds, with approximately 2.5 GiB peak memory. After the compile-speed work
  recorded below, the same 30-source corpus measures 85.02 s for `check` and
  89.32 s for `compile --emit=c` on the 2026-10 Amp orb host, with 3.48 GiB peak
  RSS for `check` — an 13.99x reduction in `check` time against
  the 1189.17 s measured on that host before the change;
- `ALDER_BOOTSTRAP_SELFCOMPILE=1 go test ./compiler -run
  '^TestAlder1CompilesCompilerSource$' -count=1` passes the complete source,
  verification, C generation, native build, and next-stage execution path.

#### Compile-speed work on the self-hosted compiler

Phase-level instrumentation of the native `alder1 check` over the fixed
30-source corpus attributes 67% of wall time to the checker, 30% to the MIR
verifier and 3% to lowering; lexing and parsing together are 0.02%. A gprof
profile of the same run attributes 26% of sampled time to the checked-arithmetic
and bounds-check runtime helpers and a further 15% to `__s0_buffer_get`
monomorphisations, roughly 63 billion calls into out-of-line functions in a
separate translation unit.

Six changes landed:

- the checker reads `SymbolRec.inherent_owner`, already computed once per symbol
  by `collect_symbols`, instead of re-walking the parse roots per candidate in
  `symbol_named` — fixed point regenerated;
- the checked leaf helpers move from `runtime/c/alder.c` into `runtime/c/alder.h`
  as `static inline`, so the generated compiler C — which already includes that
  header — inlines them. No check is removed and the trap behaviour is unchanged.
  This is a pure C-runtime change: it needs no regeneration, and it is the single
  largest win;
- the parser rejects expression nesting deeper than 64 levels with a normal
  syntax diagnostic, so deeply nested input can no longer exhaust the native
  stack — fixed point regenerated;
- `lower_expression` counted a field access's temporary local by scanning the
  whole MIR local table, which made lowering quadratic in the number of
  functions already lowered. It now calls the existing `lower_local_count`, which
  reads the last local's ordinal — the same value, since `mir_add_local` assigns
  ordinals densely per function — fixed point regenerated. Every MIR and
  generated-C golden is byte-identical, so this is output-neutral;
- `lower_mir_type_contains_vec` found a type's MIR type parts by scanning the
  whole part table for every type it visited, which made each call proportional
  to visited-types times all parts. Lowering now keeps an owner-keyed index over
  the part table in `LowerState`, extended lazily as parts are appended, so a
  visited type costs only its own part count. Fixed point regenerated; every MIR
  and generated-C golden is byte-identical, so this is output-neutral;
- the monomorphised `__s0_buffer_get` / `len` / `set` / `slice` accessors were
  emitted as out-of-line `static` functions, and a compiler-sized program calls
  them billions of times. The C backend now declares those four accessors
  `static inline`, which lets GCC inline them. No body, bounds check or trap
  changes: the generated C for every program is identical except for the added
  `inline` qualifier on those declarations and definitions. Because the change
  is in the backend rather than in the compiled source, the fixed point needed a
  second regeneration round to settle.

A seventh change landed after the integration branch: phase 6's `merge_value`
re-walked a source's whole per-key fact list on every merge, and each fact it
re-added was already present, because the target's fact list is append-only and
insertion-ordered while the source's is only ever appended to. Once a merge of a
given (function, target, source) has reached fact position `p`, every fact at or
before `p` is already in the target. `MirV6ConsumerIndex` now carries one `merged`
resume slot per consumer edge, `mir_v6_merge_edge` finds that edge by walking the
source key's edge chain for the matching target, and `mir_v6_merge_from`
fast-forwards past the already-merged prefix instead of re-adding it. The
sequence of effective adds is unchanged, so fact order and all output are
identical. Two consumer-index mismatches — `vec_grow_checked` records `x.a`
where `transfer_value` merges `x.b`, and `copy_to_domain` records an extra `x.b`
edge — are left as they are; they only cost resume coverage, never correctness.
The chain walk is capped at 1024 edges: the longest chain on the compiler's own
sources measures 500 and every merge site is present in its source's chain, so
the cap is never reached here.

Measured on the 2026-10 Amp orb host (30 sources, `-O2`): `check` 1189.17 s to
256.43 s with the first three changes, to 219.73 s with the fourth, to 213.54 s
with the fifth, to 142.70 s with the sixth, and to 85.02 s with the seventh,
`compile --emit=c` 267.64 s to 89.32 s, peak RSS unchanged at about 3.4 GiB
(+7.3 MB for the consumer-index resume slots).
Peak memory is dominated by the never-freed doubling domain segments and is not
addressed by this work.

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

Status: **complete**

Run `alder1 -> C2 -> alder2 -> C3` and require `C2 == C3` byte-for-byte. Commit
an auditable `bootstrap/alder.c`, compiler-source manifest and digests, runtime,
host shim, and regeneration harness. A clean source archive plus a system C
compiler must regenerate the committed C offline without Go or a prior Alder
installation.

Only after this gate is the Go bootstrap compiler frozen except for correctness
and bootstrap maintenance. This is a reproducible **source** bootstrap claim;
bit-identical native binaries require a separately pinned native toolchain.

Exit-criteria evidence:

- `alder1 -> C2 -> alder2 -> C3` completes for the current 30-source compiler
  root, and `C2` and `C3` are byte-identical with SHA-256
  `292dca13e065ca6e0a6e0d52c69c3277732e801e57ac1091332463ffcbdad1ea`
- `bootstrap/alder.c` is that fixed-point C, and its digest is pinned by an
  ordinary compiler test;
- `bootstrap/compiler-sources.manifest` records canonical lengths and SHA-256
  digests, while `bootstrap/compiler-sources.order` records the exact source
  order without directory discovery; ordinary tests validate both contracts;
- `bootstrap/regenerate.sh` verifies the inventory, builds the committed C
  compiler with the runtime and host shim, regenerates the C from the explicit
  source order, and requires byte-identical output;
- the regeneration harness runs from a clean source archive with a system C11
  compiler and common POSIX-host utilities, without Go in the build path,
  network access, or a prior Alder installation.

#### Go bootstrap retention and retirement policy

The Go implementation remains in the main tree through Milestone 11 as a
bootstrap-maintenance path, independent MIR/verifier/C-generation oracle, and
test harness. Milestones 6–11 implement new source-language and tooling
features only in the Alder-written compiler; they must not grow a parallel Go
frontend. Go changes during this period are limited to correctness fixes,
fixed-point/bootstrap maintenance, keeping independent oracles compatible with
versioned compiler boundaries, and migrating existing tests to non-Go
infrastructure.

Go retirement begins only after the Milestone 11 `alder test` gate passes and a
non-Go harness continuously covers the existing acceptance/rejection and golden
fixtures, source-to-C execution, malformed MIR verification, C backend/runtime
behavior, strict C11 and sanitizer checks, host/inventory failure paths,
cross-process and source-order determinism, and C2/C3 fixed-point comparison.
Before the first deletion, preserve the final Go bootstrap on an archival
branch or tag. Remove Go packages incrementally only after equivalent non-Go
coverage is active; remove `go.mod`, Go lifecycle setup, and the last Go source
only when a clean archive can build, regenerate, and run the complete test
matrix with no Go executable available.

## Alder 1.0 Implementation Gates

M5.5 produces a trustworthy compiler bootstrap, not the full language. Every
following milestone is required before the project may claim Alder 1.0. Their
contracts are already frozen in `docs/`; implementation may amend a contract
only through the documented design-decision process.

## Milestone 6: Local Modules and Deterministic Build Graph

Status: **complete**

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

Exit-criteria evidence:

- the Alder-written compiler owns manifest parsing, exact-import module-closure
  construction, visibility and import resolution, stable module-qualified
  lowering, and versioned build-plan construction; the C host performs only
  requested local I/O, atomic output replacement, native tool invocation, and
  direct process execution;
- project-mode acceptance and rejection tests cover canonical module paths,
  namespace and selected imports, aliases, selected re-exports,
  private-by-default visibility, public-signature leakage, duplicate and
  missing modules, cycles, collisions, and isolation from unimported files;
- production-driver tests exercise local `check`, `build`, `run`, JSON check and
  test-plan output, binary and library targets, debug/release selection, host
  triple validation, canonical output paths, argument/status forwarding, and
  failed-build preservation of prior artifacts;
- repeated fresh processes, workspace-root changes, and source-order
  permutations produce identical build plans, diagnostics, MIR, and generated
  C; snapshots enumerate only exact requested paths and are sorted before the
  compiler consumes them;
- `go test ./...`, `go vet ./...`, both strict C11 syntax checks, and the
  Go-free `bootstrap/regenerate.sh` fixed-point gate pass on the 30-source
  compiler root. The committed fixed-point C has SHA-256
  `292dca13e065ca6e0a6e0d52c69c3277732e801e57ac1091332463ffcbdad1ea`

## Milestone 7: Core Value Categories and Owned Foundations

Status: **complete**

Implement the first foundational source semantics from
[Syntax](docs/syntax.md), [Language Semantics](docs/language-semantics.md), and
[Memory and Resources](docs/memory-and-resources.md): recursive copyable,
affine, and scoped-capability type classification; owner borrowing and transfer
through ordinary, `mut`, and `take` parameters; inherent methods and receiver
modes; fixed arrays; and distinct owned UTF-8 `String` and arbitrary `Bytes`
values.

Advance this gate through five dependency-ordered slices:

1. type-category representation and recursive propagation;
2. affine owner flow, borrowing, transfer, and illegal drop/overwrite checks;
3. inherent methods, associated functions, receiver modes, and static
   monomorphized resolution;
4. `Array(T, N)`, array literals, indexing, and value independence;
5. owned `String` and `Bytes` representations with `String` no longer sharing
   the `[U8]` source identity.

Exit requires focused acceptance/rejection tests for category propagation,
owner transfer and illegal copy/drop/overwrite, receiver access and
consumption, fixed-array bounds and independence, UTF-8 validation, arbitrary
byte preservation, and generic monomorphization. Generated MIR/C must preserve
deterministic evaluation and value behavior. Ordinary source construction of
arrays, strings, and bytes must not require explicit bootstrap storage, while
the compiler implementation may retain private bootstrap facilities until the
Milestone 7.3 migration gate.

Exit-criteria evidence:

- commits `55c2e1f`, `18febe3`, and `061567d` establish recursive value
  categories, parameter ownership modes, and deterministic affine owner flow;
- commits `f350b74` and `a0e700e` add inherent/associated method resolution,
  receiver modes, fixed arrays, checked indexing, and independent C value
  behavior;
- the final M7 slice adds distinct `string`/`bytes` MIR and C ABI values,
  UTF-8-only `String`, arbitrary-byte `Bytes`, exact `\xNN` decoding, empty and
  embedded-NUL constants, distinct generic instances, and a private
  `__s0_String` bootstrap bridge owned by the M7.3 migration gate;
- focused Go and Alder-written checker/lowering/verifier/C tests pin rejection
  of public String/Bytes slicing and indexing, malformed escapes and invalid
  UTF-8, plus deterministic assignment, call, return, generic, and generated-C
  behavior.

## Milestone 7.1: Core Collections and Scoped Views

Status: **complete**

Build the owned/view sequence model on the Milestone 7 category and method
foundation: ordinary `Vec(T)`, immutable `[T]` views, and exclusive
`MutSlice(T)` views. Arrays and vectors borrow as slices without changing their
owned value semantics; strings and bytes expose only their documented view
operations, and integer indexing remains unavailable on `String`.

Advance this gate through three dependency-ordered slices:

1. ordinary `Vec(T)` construction, geometric growth, indexing, mutation, and
   independent copies;
2. immutable views, range formation, lexical validity, and non-retaining call
   borrowing;
3. mutable views, exclusive access, overlap rejection, and invalidation by
   incompatible owner mutation.

Exit requires focused acceptance/rejection tests for collection growth and
mutation independence; immutable and mutable view formation; view
escape/overlap/invalidation; checked bounds and growth arithmetic; and generic
monomorphization. Generated MIR/C must preserve left-to-right evaluation,
checked access, deterministic output, and independent value behavior. Cases
that require a view or allocation to survive an inner candidate domain remain
conservatively retained for the Milestone 7.3 inference gate rather than being
accepted through an unproved lifetime.

Exit-criteria evidence:

- MIR format v4 and the Go/Alder-written lowering, printer, parser, verifier,
  and C11 backend implement `Vec(T)` construction, checked 0-to-4 geometric
  growth, checked indexing and mutation, and recursive eager deep copies,
  including independent nested `Vec(Vec(T))` values;
- arrays and vectors form checked half-open immutable views, and exact `[T]`
  parameters accept deterministic non-retaining Array/Vec call borrows without
  changing owned value semantics;
- focused checker rejections enforce lexical view lifetimes, mutable-view
  exclusivity and direct formation, overlapping-view and owner-access
  conflicts, temporary call-borrow ordering, and escape prevention through
  returns, records, arrays, variants, and collections;
- Go and Alder-written checker/lowering conformance tests, generated-C goldens,
  strict C11 compile-and-run fixtures, and runtime regressions cover growth,
  bounds termination, mutation independence, generic monomorphization, nested
  deep copies, view formation, subviews, and deterministic output;
- `gofmt -l .`, `go vet ./...`, `go test ./...`, the strict runtime C11 syntax
  check, and the Go-free `bootstrap/regenerate.sh` byte-for-byte fixed-point
  gate pass with the committed 30-source compiler inventory and MIR v4
  bootstrap artifact.

## Milestone 7.3: Inferred Hierarchical Storage

Status: **complete**

Complete the foundational value and view model with compiler-inferred
hierarchical storage. Placement chooses the smallest domain proven to outlive
all uses, retains storage in the nearest safe outer domain when an earlier end
cannot be proved, and makes material retention and cross-domain copy costs
visible rather than introducing dangling views or hidden universal reference
counting.

Advance this gate through three dependency-ordered slices:

1. a deterministic compiler-scale constraint/fixed-point analysis for
   allocation placement, view validity, and safe outer-domain retention;
2. inferred-domain lowering, returned-view retention, and deterministic
   cross-domain copying for ordinary values and collections;
3. migration and qualification of the complete Milestone 7 value/view surface,
   including removal of explicit bootstrap storage from ordinary public value
   construction.

Slice 1 establishes the Alder-written, lowering-independent storage-analysis
boundary. Stable candidate-domain, allocation, dependency, fallback, and view
records feed a deterministic monotone worklist. The result records the nearest
safe placement, every conservative outer-domain retention site, and validated
views; malformed hierarchies/constraints and views proven invalidated are
rejected in stable input order. Parent-before-child domain IDs make hierarchy
validation and depth construction finite, while a stable dependency index and
FIFO queue avoid whole-graph rescans on layered compiler-scale inputs. Slice 2
owns construction of these constraints from ordinary source programs and all
consumption by inferred-domain lowering.

Slice 2 constructs deterministic expression/allocation, result-lifetime,
fallback, and immutable-view facts from the sealed checked graph, runs the
slice-1 `StoragePlan` solver before MIR exists, and consumes its placements at
Vec allocation, growth, value-copy, and result-copy sites. Ordinary functions
receive a caller-result domain and create a nested function domain; calls pass
the current function domain, while return copies target the nearest
caller-visible result domain before the function domain is destroyed. This
also permits direct immutable `[T]` results by materializing independent result
storage, including array-backed, Vec-backed, parameter-backed, and
callee-returned views and views whose elements contain recursively copyable
collections. Return and failed-`try` exits retain the complete relocatable
result before local cleanup and domain destruction. `copy_to_domain` severs
source-domain provenance only for values it can independently materialize;
domain, table, cleanup, raw-pointer, and other identity-bearing resource inputs
are rejected. Mutable views and aggregates containing views remain
non-escaping, and their overlap, mutation, and invalidation checks are
unchanged.

Slice 3 migrated and qualified the complete Milestone 7 value/view surface.
Its public-surface half made the bootstrap bridges compiler-private, accepted
only under a private bootstrap profile (`--bootstrap-private`) that exists to
compile `compiler/src`, `bootstrap/spike`, and the bridge test fixtures,
while ordinary programs construct values through inferred storage with a
parameterless hosted entry; the Alder production driver verifies its own
output at the current MIR format version, and the self-hosted e2e corpus
includes the `collections` and `storage` Vec programs. Its storage half
generalized direct immutable view results to nested ordinary aggregates:
construction and return admit a record, enum, `Option`, `Result`, or array
whose scoped leaves are all immutable slices, lowering materializes those
view parts into caller-result storage, and match scrutinees, aggregate view
parameters, aggregate view `using` initializers, and local view-aggregate
bindings stay rejected so overlap, mutation, and invalidation checks are
unchanged. Two pre-existing bugs surfaced and were fixed on the way: the
checked array-literal child window shifted later elements whenever an
element carried its own child records, and generic member types were not
substituted below the top level, refusing every generic record with a
parameterized view field.

Exit requires focused acceptance/rejection tests for storage retention
fallback, returned immutable views, cross-domain copies, nested candidate
domains, collection growth and mutation independence, mutable and immutable
view escape/overlap/invalidation, and generic monomorphization. Compiler-scale
layered inputs must terminate with deterministic diagnostics, MIR, and C.
Generated MIR/C must preserve deterministic evaluation and independent value
behavior, and the public language may no longer expose `String = [U8]` or
explicit bootstrap storage as the way to construct ordinary values.

Exit-criteria evidence:

- slice 1's solver conformance pins nested candidate domains, dependency
  promotion, root fallback retention records, invalidated-view rejection, and
  a 2048-allocation layered case; slice 2's Go and Alder-written conformance
  pins direct immutable `[T]` results, cross-domain `copy_to_domain` copies,
  nested `Vec` deep copies, failed-`try` retention, and growth/mutation
  independence through generated C;
- the M7.3 storage-side conformance pins backend slice-part aggregate support
  (verify plus generated recursive copy helpers), Alder checker acceptance
  and rejection of nested view-aggregate results and every untracked escape,
  lowered hidden placement domains with `copy_to_domain` return roots, the
  array-literal child-window regression, and generic view-field substitution
  through distinct concrete instances;
- the Alder production qualification compiles and runs ordinary-surface
  programs end to end: returned view aggregates over arrays and grown
  vectors with mutation independence after materialization, `Option` and
  `Result`-`Err` view-aggregate results, generic monomorphization, a
  120-level retention-fallback chain of forwarded view results, identical
  MIR and C across repeated processes and source permutations, and
  production-driver rejections for mutable-view aggregates, view-aggregate
  bindings and scrutinees, owner mutation under an active view, and
  overlapping mutable views;
- `gofmt -l .`, `go vet ./...`, `go test ./...`, the strict runtime C11
  syntax check, and the Go-free `bootstrap/regenerate.sh` byte-for-byte
  fixed-point gate pass with the updated source inventory and digest pins.

## Milestone 7.5: Static Abstraction, Resources, and Identity

Status: **complete**

Complete the remaining 1.0 language and memory model from
[Syntax](docs/syntax.md), [Language Semantics](docs/language-semantics.md),
[Memory and Resources](docs/memory-and-resources.md), and
[Traits and Closures](docs/traits-and-closures.md): static coherent traits and
constraints, safe closures and function values, ordered `Map`/`Set`, affine
resource composition, compiler-recognized `Cleanup`, `match` guards, the
in-place-when-unique update rule with per-site copy reporting, and the source
`Table(T)`/`T.Id` surface. Suspending cleanup hooks receive their complete
execution and cancellation behavior with the concurrency runtime in Milestone
9; this milestone establishes cleanup type, affinity, and scope rules without
introducing suspension early.

Exit requires focused acceptance/rejection tests for trait coherence and
static dispatch, closure capture and escape, deterministic ordered
collections, cleanup on every normal synchronous control exit, table
staleness and overlapping access, resource composition, generic
monomorphization, and compiler-scale layered DAGs. The public language and
generated MIR/C may no longer expose `__s0_*`, `Domain`, `DomainMark`, fixed S0
Map/Buffer, or callback-bearing bootstrap cleanup forms.

Exit-criteria evidence (complete):

- the static-abstraction half adds `trait`/`where`/`impl Trait(...) for`
  declaration checking with builtin standard-trait names
  (`Eq`, `Hash`, `Iterator`, `IntoIterator`, and `Cleanup`; the
  design amendment's `AsyncCleanup` is removed below),
  per-unit coherence over a once-built sorted impl index, `Self` resolution,
  and constraint-gated generic instantiation and concrete applications;
- the dispatch half resolves dot-calls to inherent methods first and then to
  the unique trait implementation for the receiver's concrete type, validates
  every impl against its trait's receiver modes, arity, and substituted
  signature, and lowers resolved methods as ordinary monomorphized functions
  (`take_first8`-style names), pinned through generated strict-C11 programs
  that dispatch a constrained generic at two receiver types;
- structural `Eq`/`Hash` implementations are synthesized for signed and
  unsigned integers, `Bool`, `String`, `Bytes`, and non-generic records/enums
  over that domain, satisfying `Eq + Hash` constraints while user `impl Eq`/
  `impl Hash` blocks are rejected; the synthesized methods remain
  non-callable until default-method dispatch lands;
- the ordered public `Map(K, V)`/`Set(T)` (checked kinds 23/24, builtin
  identities 30-42) are insertion-ordered association lists lowered inline
  over `vec` storage: `Map.new`/`Set.new`, `insert` with in-place
  replacement and geometric growth, `get` with `Some`/`None` results,
  `contains`, `len`, order-preserving `remove` via in-place compaction,
  and `keys`/`values`/`items` projections, all pinned end to end through
  generated strict C11, including the insertion-order contract after
  replace, remove, and reinsertion. Structural record and enum keys
  compare through place chains, and the rebuilt or projected vector is
  stored back into the receiver binding for value semantics. Keys are
  gated to the structural-comparison domain M7.5 lowers — unsigned
  integers, `Bool`, `String`, and `Bytes` compared through `str.eq`, plus
  records and enums over that domain (diagnostic 127) — values to
  recursively copyable ordinary values (128), and `remove`/`keys`/`values`/
  `items` to storage-free moved types while entries cross a lowering loop
  (129); malformed call shapes are rejected (144). Lookup, insert, and
  remove scan linearly, a known cost deferred to the standard-library hash
  containers;
- phase 6 exempts loads of provenance-free types from storage-domain
  derivation, implemented in lockstep in the Go verifier and the Alder
  mirror with the soundness argument in [MIR](mir.md): plain-bit values
  (primitives and options, results, arrays, aggregates, and enums over
  them) loaded from storage carry no domain provenance, so binding Vec
  elements to locals inside source loops verifies, while storage-carrying
  loads keep the full derivation and every cyclic-store rejection;
- function values round-trip end to end: `fn(A, B) -> R` (checked kind 25)
  types resolve with nested function types, a function name in value
  position lowers through `fn.value` with strictly-conforming C forwarder
  wrappers whose code pointer takes an opaque environment parameter, and
  calls through function-typed bindings lower through `call.value`, pinned
  through generated strict C11 that applies, selects, and invokes function
  values (the indirect-call child count equals the callee plus one child
  per parameter in the lowering model);
- closures lower end to end: `fn(name: Type, ...) => expr` and
  `fn(name: Type, ...) -> R { ... }` literals create function values whose
  read-only snapshots of enclosing `let`/`var` locals ride a
  compiler-generated thunk (captures are the thunk's hidden trailing
  immutable parameters, so writes to captures are rejected as parameter
  immutability. Captures are ordinary snapshot values: primitives, `String`,
  `Bytes`, arrays, `Vec(T)`, `Map(K, V)`, `Set(T)`, records and enums over
  them, and function values; a storage-backed capture is copied into the
  environment's domain at creation and deep-copied into the destination
  domain when the closure escapes, and function-valued captures are retained
  recursively. Affine owners and scoped capabilities are rejected with
  diagnostic 145, and malformed shapes with 147. The
  environment is one domain-allocated record per closure built through
  `aggregate.construct` plus `copy_to_domain`, so creation stays inside the
  verifier loop-store rule's domain-provenance discipline; thunks take no
  hidden domain parameter and the wrapper adapts the opaque environment
  pointer to the thunk's reference parameter. A literal inside a generic
  function body materializes one thunk per checked instance, so its
  parameters, captures, and result take that instance's concrete types;
  the linear body walk skips thunks and a post-body pass checks each one
  after every ordinary body has run, which is also when an instance's
  site check has recorded the thunk signature. A closure created inside a
  `while` loop is carried by its immutable environment snapshot, and a
  literal nested inside another literal captures transitively: the outer
  environment carries every value the inner body reads, and the outer
  record records the domain that owns it so the thunk allocates the inner
  environment beside it. An escaping closure is retained into its
  destination domain by the function value's retain hook, so chains of
  returns and closures carried in vectors or records stay valid. Closure
  sites, thunks, and erased `fn(params) -> result` value types are pinned
  through generated strict C11 programs with captures, and the layered DAG
  threads a nested literal through a generic body.
- default-method dispatch works end to end: a trait requirement with a
  default body is materialized as an ordinary impl method (a kind-12
  symbol whose node is the requirement) for every implementation that
  does not override it, inside symbol collection and before any
  declaration or body checking, with the impl's method symbols regrouped
  so each implementation's method range stays contiguous; dot-calls then
  dispatch through the existing static path (`trait method ... not
  callable yet`, diagnostic 120, is retired), and both overridden and
  defaulted dispatch are pinned through generated strict C11.
- trait and impl methods carry their own compile-time type parameters:
  a requirement's leading `type` parameters are recorded in the trait's
  scope (name-unique across the trait), an implementation must declare the
  same count and they match positionally through the impl substitution
  (`trait method ... cannot declare their own type parameters yet`,
  diagnostic 118, and `generic trait implementation methods are not
  supported yet`, 124, are retired; arity and position mismatches are
  signature mismatches, 123). Method calls take explicit type arguments
  after the receiver, and generic trait, impl, and inherent methods are
  pinned end to end through generated strict C11, including dispatch
  through a constrained generic function and a defaulted generic method on
  an arity-zero trait.
- defaulted methods synthesize for generic traits as well: a materialized
  method resolves the trait's parameters substituted with the concrete
  trait arguments of its own implementation, so one defaulted requirement
  runs at different result types per implementation (diagnostic 120 is
  retired with its flag and helper). Both materializations of a
  generic-trait default, direct dot-calls, and dispatch through a
  constrained generic function are pinned end to end through generated
  strict C11.
- iterator cursors borrow exclusively: a non-self `mut` parameter stays an
  exclusive call borrow (rule 89 unchanged for ordinary parameters) and is
  legal for copyable values only when its type is a type parameter
  constrained by a trait with at least one `mut self` requirement — the
  builtin `Iterator` or a user trait. The call-site argument must be a
  mutable place, so `next()` advances the caller's `var` cursor through the
  lowered `safe_mut` reference; `let`-bound copyable and temporary arguments
  are rejected (146). The [Traits and Closures](docs/traits-and-closures.md)
  drain shape is pinned end to end through generated strict C11, proving the
  second drain starts where the first ended.

Implementation progress, resource and identity half (the five commits atop
`77437ec`: source `Table(T)`/`T.Id` surface, affine aggregate composition,
Cleanup selection through `using`, affine `Vec(T)` drain composition, and
this evidence record):

- checked kinds 19-22 and builtins 26-29 plus 45 add `Table(T)`, `T.Id`, and the
  scoped `get`/`get_mut` view payloads: lookups are consumed only as match
  scrutinees whose `Some` arm binds a straight-line fail-free view, and
  table-view registrations reject overlapping mutation or exclusive access
  under a live view. Table storage allocates in the caller-result domain so
  an escaping owner outlives its function; the builtin registration is a
  compiler-synthesized no-op release; `try_insert` adds the non-panicking
  edge, returning `Result(T.Id, T)` where a failed insert hands its affine
  element back through the `Err` payload (`table.insert.try`, MIR op 68)
  while plain `insert` keeps the capacity-refusal abort — the C-side
  slot-limit hook forcing the capacity `Err` deterministically is a test
  hook, not language surface (see `docs/c-backend.md`);
- same-table owning-element inserts are buildable: reads of a vec-bearing
  type that carries an affine owner (for example `Table(Row)` with
  `xs: Vec(U64)` fields) are borrows like plain table reads, so reading the
  table binding again after an insert no longer emits the `copy_to_domain`
  that phase 10 refuses, and `insert`/`insert.try` deep-copy a
  storage-bearing element into the table's domain at insert so stored
  owning elements stay valid after the inserting function returns
  (straight-line and per-iteration loop inserts pinned through strict C11
  and ASan/UBSan, with snapshot independence and take/return escape);
- affine owners compose into records, enums, `Option`, `Result`, and fixed
  arrays: construction transfers parts, affine scrutinees are consumed as a
  whole, and parts leave only by transferring the whole aggregate or
  registering it with `using` (field extraction is deliberately out of
  scope). A whole-aggregate read at a public `using` transfers its source,
  so a received owner registers directly;
- the callback-free `using` selects the builtin table release, the owner's
  `Cleanup` trait method, or a compiler-synthesized per-element drain for a
  `Vec(T)` of `Cleanup` owners. Cleanup impl types are affine through the
  receiver index, and the callback `with` clause is bootstrap-private (137,
  gated in every corpus that still exercises the bridge); the builtin
  `AsyncCleanup` trait is removed with its diagnostics 138/139 per D012 — a
  `Cleanup` hook may suspend once its owner holds a suspending capability in
  Milestone 9;
- the D023 in-place-when-unique rule: a copy site whose source binding is
  provably dead and unaliased transfers the storage instead of copying
  (pinned observable: an aliased source still copies and reports, a dead
  source moves with no copy call in the generated C, parameter storage
  never moves inside the callee while a dead caller argument does, and an
  escaping target still copies through exit retention). Copy sites inside
  loop bodies and closure captures copy and report (reasons "re-read by a
  loop" and "captured by a closure"); `--report-copies` prints every
  remaining site with its reason after a successful check or compile;
- `match` guards (D018): an arm may carry an `if` guard between its pattern
  and its arrow. The guard runs after the pattern matches with the arm's
  bindings in scope, a false guard continues with the next arm, a guarded
  arm never counts toward exhaustiveness, a guard only borrows its bindings
  (no transfer may appear inside it, 148), and a table-view arm cannot
  carry a guard because its access region is one straight-line fail-free
  block (149). Same-variant arms form one contiguous run (72) so lowering
  chains each false guard through one straight edge into the next entry,
  ending at the run's unguarded arm or the wildcard arm; W records carry
  the guard expression (manifest v17);
- focused evidence: Alder checker conformance suites pin the accept surface
  and rejections 130-143 and 148-149, and the production qualification
  compiles and runs table, trait-cleanup, vec-drain, and guard programs end
  to end on generated C (imported counters observe every cleanup firing
  exactly once per element on normal and early-return exits, guard programs
  assert the fall-through chain at runtime, deterministic MIR/C across
  processes, no `__s0_` names in generated C for ordinary programs).
- exit audit: every exit clause maps to concrete evidence. Trait coherence
  and static dispatch, closure capture and escape, deterministic ordered
  collections, cleanup on every normal synchronous control exit, table
  staleness and overlapping access, resource composition, generic
  monomorphization, and compiler-scale layered DAGs each resolve to the
  bullets and conformance suites above. The public-surface clause holds by
  inspection: ordinary programs compiled without `--bootstrap-private`
  produce MIR and C free of `__s0_*`, `Domain`, `DomainMark`, and the
  fixed S0 Map/Buffer names, the checker rejects each of those names in
  public source, and `7221ce9` renamed the last MIR-internal `__s0_`
  names, so the generated MIR is `__s0_`-free as well. The closing
  commits are try_insert with the non-panicking `Err` edge (`fbf3b91`),
  the `__s0_`-free MIR rename (`7221ce9`), views per loop iteration
  (`6f734a3`), and the same-table owning-element insert fix (`ac4169b`),
  whose production program pins straight-line and in-loop double inserts
  of an owning record through strict C11 with snapshot independence; the
  production qualification and its sanitizer run pass on the exit tip.

Deferred from this half, with reasons:

- suspending cleanup behavior: deferred to Milestone 9 as planned.

Compile-time guardrails (cold `bootstrap/regenerate.sh`, one host, measured
back to back on the exit audit): the pre-M7.5 tip `2a96d07` takes 160.16 s /
3,769,260 KiB peak RSS, and the M7.5 exit tip `ac4169b` takes 234.45 s /
5,704,880 KiB, so the milestone cost +46% wall time and +51% peak RSS while
the compiler sources grew from 1,549,800 to 2,080,120 bytes (+34.2%). The
peak is still the stage-0 self-compile process itself, at 3.65 KiB RSS per
added source byte against the pre-milestone band of 2.5-3.4 — at the top of
the band, tracked, not regressed. No whole-store scan or copy amplification
is present: the regenerator stays in its four-minute class, far inside the
15-minute CI budget. Absolute figures vary by host: a different host
measured `2a96d07` at 159.25 s / 3.77 GB and `1cf2572` at 216.20 s / 5.62 GB;
only same-host back-to-back comparisons are meaningful. On the first host,
the M7.5-exit tip measured 212.0 s / 5,704,676 KiB before the verifier
optimizations landed. Memoized verifier type queries (`130e604`) cut the
stage-0 self-compile to 144.5 s / 3,335,888 KiB peak; the division-free fact
hash (`641015a`) cut it to 127.8 s. The stage-0 gcc build used to compile the
whole ~25 MB `bootstrap/alder.c` as one translation unit (73.5 s / 911 MiB);
`regenerate.sh` now splits the generated file into four fixed translation
units compiled in parallel inside its temporary build tree (the pinned
artifact stays single-file), taking the stage-0 build to about 23 s wall and
cold regenerate to 147.6-148.5 s / ~3.33 GB peak across two back-to-back
runs — below even the pre-M7.5 tip — with the self-compile byte-identical
and peak RSS unchanged, because the self-compile still dominates. The split
stage-0 build alone adds plain `-Wno-uninitialized`: gcc's jump threading
reports one parse_array_literal false-positive class on tag-guarded payload
reads that `-Wno-maybe-uninitialized` does not cover; single-TU compiles of
the pinned artifact (`go test ./compiler`, -O0) stay clean under the full
strict set. `./check --bootstrap` on the same host dropped from about 6.7 to
3.9 minutes. The phase-6 fixpoint skips provably no-op fact merges
(`7c50f15`), and the phase-4 per-leaf forward BFS from the function entry
became a backward walk over a per-function predecessor CSR (`3f79ec0`),
removing the last full-CFG walk per uninitialized-place leaf; back to back
on one loaded host with identical sources, the stage-0 self-compile went
from 147.0 s / 3,344,412 KiB to 124.0 s / 3,348,560 KiB (-15.6% wall, +4.1
MB peak for the predecessor arrays, to be reclaimed by reusing the
per-function verifier scratch across functions). A presized reusable
scratch buffer in the lowering (`lower_move_analyze` now clears one
plan-carried `excluded` buffer in place instead of regrowing a fresh one
on every call) cut the stage-0 self-compile to 126.4 s / 2,959,944 KiB
peak on its own commit, measured back to back on the unloaded host
(128.9 s / 3,333,572 KiB before; cold regenerate 153.6 s / 2,960,252 KiB,
wall within run-to-run noise), removing about 365 MiB of dead-but-retained
doubling garbage from the peak. On the combined tip with the verifier
changes above, the same unloaded host measures the stage-0 self-compile at
101.4 s / 2,976,232 KiB and cold regenerate at 123.2 s / 2,976,444 KiB.
The call-argument borrow scan in `lower_expression` walked the whole
locals table once per call argument (621 million table reads per
self-compile); it now resolves the callee's ordinal-th parameter through
the owner-keyed local index the lowering already builds, riding in the
state, cutting the stage-0 self-compile to 78.3 s / 2,979,912 KiB and
cold regenerate to 105.8 s / 2,979,688 KiB on the same host, with the
pre-change binary compiling the identical sources emitting byte-for-byte
identical C and the peak unchanged. Remaining self-compile time sits in
the verifier phase-6 merge family and phase-4 initialization; the largest
non-verifier items are the lowering's storage planning, cgen emission,
and the MIR builder. On this commit's tip, which also carries the
verifier's phase-4 table reuse, the same host measures the stage-0
self-compile at 80.8 s / 2,970,040 KiB and cold regenerate at
111.6 s / 2,970,016 KiB. The phase-4 CFG, dominator, and Euler-tour
scratch joined the plan-carried pattern (the builders now grow fifteen
reusable cfg buffers and seventeen dominator buffers once and rewrite them
in place per function); back to back on one host, cold regenerate went
from 133.7 s / 2,966,448 KiB at `58acb34` to 125.7 s / 2,732,244 KiB,
about -229 MiB of peak, with the fixed point byte-identical. The merge_edge
resume lookup became a bucket-table probe instead of a per-key chain walk
(first edge per pair wins, so the probe returns exactly the edge the walk
returned); the slot hash multiplies the key and target by fixed constants
modulo the prime 2^32-5 before reducing, because a linear fold mod a
power-of-two table clusters consecutive inserts into quadratic probe runs.
Back to back on one host, the stage-0 self-compile went from 82.8-83.4 s to
71.5-72.0 s (-13%), cold regenerate from 117.5 s to 108.7 s, peak RSS about
+29 MiB for the bucket table, with the fixed point byte-identical.
Separately,
the quadratic MIR print/validation layer had left `compile --emit=mir`
unable to finish on the compiler's own sources: every operand, value, and
type-part lookup rescanned full tables, and the 30-source corpus produced
no output past 15 minutes of running (the pre-change binary needed
114.6 s on a synthetic module a quarter the size, scaling quadratically
with values x instructions). `mir_print` now builds per-key group indexes
once per print — counting-sort CSR spans per function and block, with
out-of-range keys kept in exact side lists — and takes the Domain for its
scratch allocation. The print output is byte-identical to the pre-change
printer with matching exit codes on every accept, e2e, and reject fixture
and on synthetic modules up to a 2.0 MB MIR print, the corpus still parses
and re-verifies everything the printer emits, and a new 500x40-function
corpus subtest keeps the regression pinned (the fixed harness build
finishes it in about 47 s, while the quadratic version extrapolates to
about 95 minutes there, roughly 9x past the 10-minute go test timeout,
which is why the size is pinned at corpus scale rather than a few
seconds). On the same host back to back, `compile --emit=mir` on the 30
sources now completes at 72.8 s / 2,747,584 KiB, and cold regenerate went
from 110.5 s / 2,735,652 KiB at `43e6b50` to 105.0 s / 2,794,436 KiB with
the self-compile at 74.4 s / 2,794,572 KiB; the peak adds about 58,800 KiB
for the rewrite's 44,968 added source bytes, about 1.3 KiB per added byte,
below the band above, with the fixed point byte-identical. The phase-6
successor enumeration joined the same pattern (`mir_v6_successors_at` now
overwrites a caller-held buffer in place and returns the valid span, so
the dataflow solve and the reachability BFS reuse one buffer per pass
instead of allocating a fresh one per block or per BFS source); back to
back on one host, cold regenerate peak RSS went from 2,824,784-2,824,864
KiB at `7fd99e7` to 2,558,092-2,558,180 KiB (about -260 MiB, -9.4%), wall
unchanged at 106.2-109.0 s across four alternating runs, with the fixed
point byte-identical. The loop-check reachability closure stopped being a
pair list: a membership-only pre-pass counts each function's reachable
pairs, and the closure is stored as a bit matrix (rows of U64 words,
cleared per function, reached-bit test in place of the per-source linear
scan) whenever the matrix is strictly cheaper than 16 bytes per pair for
that function's own shape, falling back to the presized pair list on the
same comparison otherwise; all five buffers (matrix, pairs, span, seen,
successor queue) are carried across functions and rewritten in place. The
largest self-compile function measures 2,340 blocks (`lower_model_valid`;
next 1,497 and 1,153), so its matrix is about 0.66 MiB against a pair
list that reached a 128 MiB doubling capacity, and the sum of n^2/8 over
all 2,082 functions is under 2 MiB. Back to back on one host, cold
regenerate peak RSS went from 2,558,100-2,558,180 KiB at `f6cbd9b` to
2,195,012-2,195,052 KiB (about -355 MiB, -14%), the stage-0 self-compile
from 75.70 s / 2,560,004 KiB to 73.84 s / 2,195,132 KiB, wall otherwise
unchanged at 107.5-109.1 s, with the fixed point byte-identical. The
phase-6 fact record folded function and value into the dense key its add
site already computes and chained dedup slots through the record itself,
dropping the separate hash-next buffer (64 to 56 bytes per fact), and
phase-8's effect and mutates queries joined the bucket pattern, walking
per-key chains instead of the whole fact buffer; a measured detour worth
recording: grouping dedup slots per key walked about nine hops per probe
on the self-compile (2,800 hot keys carry 513-545 facts each, so per-key
slot chains track the skew, not the load factor), tripling `fact_add`
cost until the uniform full-tuple hash was restored. Back to back on one
host, cold regenerate went from 91.36 s / 2,195,072 KiB to 90.63 s /
2,135,796 KiB (wall within run-to-run noise, peak about -58 MiB), `go
test ./compiler` from 163 s to 128 s on the phase-8 walks, with
identical accept, reject, and end-to-end fixtures and the fixed point
byte-identical.

The checker's interpretation worklists joined the same pattern: the seven
interpreted-type probes plus `push_decl_members` now carry five stable,
pre-grown worklist/seen/memo backings on `CheckStore` (appended onto once
in `check_parsed`) instead of allocating fresh work, seen, target, and
pair buffers per probe, with per-probe `used` counts bounding every
membership scan and set-or-append pushes; back to back on one host at
the loop-check bit-matrix tip, cold regenerate peak RSS went from
2,194,724-2,194,964 KiB to 1,803,348-1,803,544 KiB (about -382 MiB,
-17.4%) and self-compile peak RSS from 2,339,988-2,340,020 KiB to
1,803,424-1,803,800 KiB (about -524 MiB, -22.4%), requested allocator
bytes from 2.50 GiB in 3,659,938 allocations to 1.99 GiB in 2,737,476
(-526 MiB, -25.2% of calls), with self-compile wall unchanged
(67.8/66.0 s before, 66.3/67.1 s after), cold regenerate wall within
this host's run-to-run drift (90.7/92.2 s before, 97.8/95.6 s after
across two order-swapped pairs; the split gcc stage measured in
isolation is faster after the change, 27.6 vs 23.3 s, and the stage-0
run is unchanged, 66.9 vs 66.7 s mean), the push_decl_members chain
gone from the allocation profile, and the fixed point byte-identical.

Exit record (as of the integration of both halves; every item below landed
before exit; the items were added to or reshaped by the 2026-11 design
amendment, which landed after both halves were written):

- (D023 landed; see the evidence below) the D023 loop-rebuild move landed with
  it: a read inside a loop body transfers its storage when the next access to
  that binding in the body is a definition and the body is straight-line
  code, so `items = rebuild(items)` no longer copies, while a body that only
  reads the binding, reads it again after the rebuild, or contains a
  conditional, `match`/`try` expression, or nested loop still copies. The
  lowering and verification gap that used to block the shape is fixed too:
  `for x in v` over an owned `Vec(T)` and whole-vector assignment inside a
  `while` body now verify, because the for lowering carries the owning value
  as the loop parameter and phase 6 rejects an owning loop-carried value only
  when its storage dies inside the loop under check - so `for x in a` over a
  vector an earlier `while` body rebuilt now compiles, along with the
  surrounding for/while and Map/Set compositions;
- a compiler-scale layered DAG input over traits, generics, and closures
  that terminates with deterministic diagnostics, MIR, and C — landed: one
  generic trait with a defaulted method implemented by eight record types,
  and thirty-two constrained generic layers instantiating each other two
  ways (layer i calls i+1 and i+2, 256 instances), with closures
  snapshotting locals and threading through a function-typed helper; MIR,
  C, and rejection diagnostics are byte-identical across processes and
  across source/CLI permutations, and the generated C runs under strict
  C11.
- closure surface complete for the 1.0 value model: a literal inside a
  generic function body materializes one thunk per instance, nested literals
  thread their captures transitively through the outer environment, a closure
  created inside a `while` loop carries its immutable environment snapshot
  across the backedge, and an escaping closure is retained into its
  destination domain by the `copy_to_domain` retain hook, so chains of
  returns and closures carried in vectors or records stay valid. Captures of
  ordinary storage-backed values and function values snapshot and retain
  correctly.
- scoped-capability captures land for closures that provably do not escape:
  a closure may capture an immutable slice or a mutable view when every read
  of the value in the owning scope is a call through it or an argument at a
  parameter the callee's per-instance retain summary proves non-retaining, the
  restriction carries through captured closures, and any other use rejects
  with diagnostic 152. The summary is computed once per compile as a monotone
  fixpoint over the instance call graph, so recursion stays non-retaining when
  the whole cycle only calls or forwards the value, while returns, stores,
  captures, cross-domain copies, imports, `unsafe c` calls, unresolved targets,
  function-value callees, and forwards to retaining parameters all count as
  retaining. The environment holds the view header instead of a copy, so
  the closure reads the original storage, and phase 6's local-store rule is
  narrowed for an environment record that carries a view field (see
  [MIR](docs/mir.md)). Two limits remain, deliberately rejected rather than
  miscompiled: creating such a closure inside a loop body rejects with
  diagnostic 153, because phase 6's loop-store rule still classifies the
  environment record as a capability. Views and loop bodies otherwise
  compose: a view created in an iteration is read inside that iteration, so
  phase 6 accepts a view store whose storage domain survives the loop and
  requires every read of a view local inside the cycle to be dominated by a
  store in the same cycle (or to name storage the loop cannot relocate), a
  view of a vector the loop reassigns works, a view created before a loop and
  read inside it still works when the loop cannot move its storage, and a
  table-view arm inside a `while` body works once cleanup registration runs
  on the loop's panic path (the using-inside-loops commit). A view cannot be
  assigned inside a loop body: diagnostic 154 rejects `s = v.slice(...)`
  there, because the target slot survives the backedge. Every closure body has a
  domain: a capturing closure's environment record carries the domain that
  owns it, and a capture-free closure takes the caller's domain as its leading
  hidden parameter, so a body that allocates or copies storage works whether
  or not it captures anything.
- `mut self` receivers on a field place landed: a place is now a chain, so
  `b.items.push(x)`, `b.items[i] = x`, a Map or Set `insert`/`remove`, and
  every Table operation work through a field of a local, a field of a `mut
  self` receiver, a nested path (`a.b.c.push`), and an element of a field
  (`a.rows[0].push`). The checker records the receiver place on the call and
  the lowering writes the grown header back through it, so a `mut self`
  method and a field of a local both store into the storage the caller owns.
  A view taken through a field now also excludes mutation of the binding that
  owns it, so `let view = b.items.slice(0, 1)` followed by `b.items.push(x)`
  is the same access conflict as it is for a whole binding.
- `break` and `continue` landed: both lower to jumps to the innermost
  enclosing loop's exit and step blocks, `continue` in a `for` reaches a
  dedicated step block so the index still advances, a match arm's statement
  block inherits the enclosing loop context, and the D023 loop-rebuild gate
  treats both as skipping constructs. A table-view arm rejects both jumps as
  control flow.
- `using` inside a loop body landed: a registration belongs to that
  iteration's scope, so it runs at the end of the iteration, and `break`,
  `continue`, `return`, and a failed `try` run the registrations they cross in
  reverse order exactly once. A checked failure while a registration is active
  now runs the crossed registrations before the shared panic handler instead of
  being refused, so a loop body may compute inside its scope. A loop body that
  declares the binding re-establishes it every iteration, so its own transfer
  is not a partial-path transfer; `break` and `continue` count as exits that
  require a live affine owner to be transferred or registered. A table-view `match`
  inside a `while` body composes with the loop once cleanup registration runs
  on the loop's panic path: the straight-line arm compiles end to end on the
  exit tip (re-verified by recompiling the shape), and `break`/`continue`
  inside such an arm are rejected by the checker's straight-line arm rule
  (a table-view arm may contain only straight-line copy statements), so the
  checker never accepts what the verifier refuses.

Cold `bootstrap/regenerate.sh` timing is recorded per commit and compared only
on the same host: absolute wall time and peak RSS depend on the host and
toolchain, so one host's figure is not a baseline for another. Each commit's
growth stayed proportional to the compiler's own source size; profiling the
self-compile memory density is tracked separately.

## Milestone 8: Verified C Bindings and Hosted Standard-Library Foundation

Status: **in progress (C-interop complete; hosted foundation partially landed; std.fs/std.process finishing, std.env partial)**

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

Deferred from this milestone by scope decision: the `Range` library type stays
out until source syntax uses it (no current syntax does). `Error` is a prelude
trait with a defaulted `cause` method, and `ErrorReport` is the prelude value
that flattens a typed cause chain (D025); the compiler loads `core.error` for
projects that name either surface. Builtins stay builtins in this milestone:
the prelude is the builtin names, and library helpers are imported explicitly.

Constraint syntax (D024): trait constraints move from `where` clauses onto
the type parameter, `T: type(Order)` and `K: type(Eq, Hash)`. The Alder
parser and checker, the trait fixtures, and docs/s0-language.md migrate in one
commit before the sysroot library uses `Order` or `Display`; `where` is then
rejected with a diagnostic that names the new form.

Landed C-interop progress: the checked scalar conversions between `c.*`
scalars and Alder numerics are installed end to end. The checker accepts the
documented method surface (`to_i8`..`to_u64` in bare/checked/wrapping forms
from integer C scalars, the total float reads `c.Float.to_f32`,
`c.Float.to_f64`, `c.Double.to_f64`, the mirror `to_c_*` integer targets
from Alder integers, and the float specials `F32.to_c_float`,
`F64.to_c_double`, `F64.to_c_float_checked`), rejecting any other conversion
name on such receivers with diagnostic 205 and rejecting lossy bare pairs;
MIR gains operations 88-90 (`c.num.try`/`c.num.wrap`/`c.num.cast`) whose
endpoints must cross the boundary with matching numeric classes, mirrored in
the Go verifier and the Alder mirror; and the C backend widens integer
crossings in 64-bit signedness before range-checking, handles the one checked
float narrowing by comparing against `float`'s limits in `double`, and emits
`f32` constant-table slots as true 32-bit patterns narrowed at emission.
Evidence: MIR-level accept/reject/inference tests in `mir/verify`, the cgen
run fixture `cgen/testdata/run/cnum.mir`, and the production qualification
`compiler/production_c_convert_test.go` (errno and C-fixture programs
compiled and run under the strict warning set, print/MIR and cross-process
determinism, and eight checker rejections); the surface is documented in
[docs/c-interop.md](docs/c-interop.md) "Scalar conversions", with the
emission contract in [docs/c-backend.md](docs/c-backend.md). Since the
IEEE-754 float decision (D026), the same qualification asserts exact values:
the conversion round trips compare `dback == 3.5`, `fback == 1.25`,
`back == 1.5`, `widened == 1.5`, and `fback == 0.5` directly instead of
observing the checked narrowing's `some`/`none`.

Landed language progress: float comparison and float arithmetic are in the
S0/MIR profile under the approved IEEE-754 semantics (decision
[D026](docs/design-decisions.md)). The checker accepts the six comparisons
and `+`/`-`/`*`/`/` on same-type `F32`/`F64` operands (float `%` and unary
float minus still reject), MIR gains the total operations 91-94 with no
failure edge, and `float.div` lowers through `alder_f64_div`/`alder_f32_div`,
which branch on a zero divisor to produce the IEEE signed infinity (NaN for
0/0) instead of the undefined bare C division. Every generated program emits
`#pragma STDC FP_CONTRACT OFF`, so `a * b + c` computes as written. Evidence:
the MIR verifier accept/reject tests in `mir/verify`, the strict-and-sanitizer
cgen run fixture `cgen/testdata/run/float.mir`, and the 66-return-code
conformance behavior `m8-float-binary` covering NaN unorderedness, signed
zeros, 1/±0 → ±Inf, overflow, exact sums, and no-contraction under
`-fsanitize=address,undefined,float-divide-by-zero` where the toolchain
supports it. C-interop float-value assertions can now compare exactly instead
of observing the checked narrowing's `some`/`none`.

Landed language progress continues with the total bitwise family. The
checker accepts `&`, `|`, and `^` on same-type integer operands and unary `~`,
using the precedence frozen in [docs/syntax.md](docs/syntax.md); the operands
keep their fixed-width two's-complement representation and the operations
never fail. MIR gains operations 103-106 (`int.and`/`int.or`/`int.xor`/
`int.not`), the C backend computes them on the unsigned width type and
transfers signed results by `memcpy`, and the Go Stage 0 frontend carries the
same rules. Evidence: the MIR verifier accept/reject tests in `mir/verify`, the
strict-and-sanitizer cgen run fixture `cgen/testdata/run/bitwise.mir`, the
`frontend` end-to-end `bitwise` program, and
`compiler/production_bitwise_test.go`, which compiles and runs the production
driver output and pins the non-integer and mixed-width rejections.

Landed language progress also aligns exclusive-view arguments between the
inherent and trait method paths. A `MutSlice(T)` parameter is mutable through
its view without repeating `mut`, `let` may bind a directly formed mutable
view for the block without allowing descriptor reassignment, a `let`-bound or
newly formed view satisfies an exclusive-view parameter, and a newly formed
view must be the final runtime argument. Taking `slice_mut`/`subview` still
requires a mutable owner. Evidence: `compiler/production_mutable_view_args_test.go`
runs inherent and trait methods, temporary views, forwarding, and the three
kept rejections (101, 104, and immutable reassignment).

Landed language progress adds the `()` Unit literal. `()` has type `Unit` and
is accepted as a return operand, a `Unit` argument, and the absent payload of
`Ok(())`/`Some(())`; lowering emits the unit constant and omits the variant
payload operand. It is not a standalone statement: diagnostic 331 rejects a
bare `()` where only a `Unit`-result call may stand alone, and Unit bindings
stay rejected. The Go Stage 0 frontend carries the same rules. Evidence: the
`frontend` end-to-end `unit` program and rejection tests, and
`compiler/production_unit_test.go`, which compiles and runs the production
driver output and pins the standalone, non-`Unit` argument, and unit-payload
mismatch rejections.

Landed language progress: signed integers `I8` through `I64` now participate
in structural `Eq`/`Hash`, so `assert_eq`/`assert_ne` over `Eq, Display` accept
them. Float `==`/`!=` remain operator-only IEEE comparisons; floats stay out
of `Eq`/`Hash` because NaN is not reflexive. Map/Set keys remain unsigned as a
deliberate M8 restriction. Evidence: the M7.5 checker/operator fixtures cover
signed Result payloads and a signed `Eq, Hash` constraint, while the existing
signed-key rejection remains.

Landed standard-library progress: `core.panic` is installed at
`sysroot/core/panic.al` with `panic`, `assert`, `assert_eq`, and `assert_ne`.
Failures flush C output, write the documented `panic:`/`panic: assertion
failed:` diagnostic to stderr, and terminate with status 101 without running
Alder cleanup; `assert_eq`/`assert_ne` require `T: type(Eq, Display)` and
display both operands, while source-expression capture waits for the test
runner. Evidence: `compiler/production_panic_test.go` checks status 101 and
exact stderr for every function, passing assertions, stdout flushing, the
interior-NUL fallback, and an unsatisfied Eq constraint; the `core.panic`
snapshot example runs under the docs API example gate. The runtime boundary is
`runtime/c/alder_panic.h`.

Landed standard-library progress: `core.error` is the prelude source for
D025's `Error` trait and `ErrorReport` value. Root errors implement `Error`
with an empty impl and inherit the default `None` cause; wrapper errors return
the report of their typed payload, and `ErrorReport.of` flattens the chain
nearest cause first. Projects that name `Error` or `ErrorReport` load the
prelude source from the installed sysroot, while unrelated projects keep their
existing plan and source closure. Evidence:
`compiler/production_error_test.go` runs a root error, a wrapper cause chain,
the default cause, and an explicit `core.error` import through the production
driver; it rejects a mismatched `cause` result and a report operand that lacks
`Error`. Docs: the frozen [`core.error` snapshot](docs/api/core.error-v1.md).

Landed standard-library progress: `std.io` v1 slice 1 ships the stream
foundation at `sysroot/std/io.al`: the `Reader`, `Writer`, and `Seek` traits
(including the `copy_to` default body), `SeekFrom`, `IoError` with
`from_errno`, `Display`, and the prelude `Error` implementation, the
`read_exact`, `write_all`, and `read_to_end` helpers, the host-free
`ByteCursor` and `ByteSink` streams, and the buffered `BufReader`/`BufWriter`.
Evidence: `compiler/production_io_test.go` runs the installed sysroot module
through the production driver and checks cursor advancement, short reads, end
of stream, the default `copy_to`, the error report, line reads and refills
across a two-byte buffer, buffered write ordering through a validating sink,
and the mutable-place rejection for a `let`-bound reader.

`into_source`/`into_sink` return the wrapped owner through the
consumed-field-move rule (`take self` moves one direct field); `into_sink`
flushes pending bytes and releases the sink on a flush error.

`std.fs` file layer lands on `std.io`: `File` wraps the capability, a host
handle, and its path; `finish` moves the handle out and closes it, `keep`
transfers the owner, and cleanup closes a still-owned handle. The whole-file
`read`/`read_text`/`write`/`write_text` helpers, `metadata`, `canonicalize`,
`rename`, `remove_file`, `remove_dir`, and `make_dir` are installed.
`Metadata` maps owner permission bits and carries signed wall-clock seconds,
so pre-1970 modification times round-trip. Evidence:
`compiler/production_fs_test.go` opens, seeks, reads, writes, changes
permissions, and reads metadata through `File`, and separately exercises the
free helpers against a file whose mtime the Go harness sets to -1 second.
Directory iteration is installed: `Entries`/`read_dir` skip `.` and `..`,
`read_dir_sorted` orders by exact name bytes, and `remove_dir_all` unlinks
symlinks rather than following them, using `io.lstat` for unknown host entry
kinds. The documented TOCTOU window remains because v1 has no
`openat`/`unlinkat`. Temporary owners are installed: `temp_root` reads
`TMPDIR` through the new `std.env.get`, and `temp_file`/`temp_dir` derive a
unique hex suffix from `io.random_bytes`, retrying on `AlreadyExists`.
`TempFile` stores the host handle directly (cleanup closes and unlinks) and
`TempDir` carries an affine token so exactly one owner removes the tree.

`std.time` v1 lands on the `std.io` capability: normalized checked
`Duration`, monotonic `Instant` with checked differences, wall-clock
`SystemTime` with epoch construction and proleptic-Gregorian `to_utc`
(including pre-1970 instants), and a zero-yield `time.sleep`. Evidence:
`compiler/production_time_test.go` checks independently computed leap-year,
epoch, and pre-epoch vectors plus fixed duration arithmetic and host lower
bounds; `docs/api/examples/std.time-v1.al` runs with checksum 2743.

`std.io` v1 slice 2 adds the blocking capability: `Blocking` implements `Io`
with host files (`HostFile`), directory listings (`HostDirectory`), file
metadata, POSIX rename/remove/mkdir/realpath, clocks, sleep, randomness, and
standard streams. `Stdin`, `Stdout`, and `Stderr` are copyable non-owning
views of descriptors 0-2, and `print`/`println`/`eprint`/`eprintln` write
best-effort text through the capability. The POSIX surface lives behind the
header-only shim `sysroot/std/c/io_shim.h`; host paths are NUL-terminated byte
buffers built with an interior-NUL check, and a `DIR*` crosses as an opaque
integer token. Evidence: `compiler/production_io_host_test.go` opens, writes,
seeks, reads, stats, closes, and removes a real file through `Blocking`;
`compiler/production_io_streams_test.go` pins standard-stream output and the
text helpers; `compiler/docs_api_test.go` runs the snapshot example. Docs:
[Standard Library](docs/standard-library.md) and the frozen
[`std.io` snapshot](docs/api/std.io-v1.md).
Landed language and runtime progress: hosted binaries accept `Unit`, `I32`,
`Result(Unit, E)`, and `Result(I32, E)` source entry results with `E: Display`.
The compiler generates an internal source adapter and keeps the generated MIR
entry `I32`. `Unit`/`Ok(())` maps to status 0, `I32`/`Ok(I32)` to the low eight
bits, and unhandled `Err` writes `program error:` plus the displayed error (and
the `ErrorReport` cause chain when available) before returning status 1. Entry
arguments remain unchanged. Evidence: `compiler/production_entry_test.go`
runs Unit, both Result success forms, a display-only Err, a wrapper Error cause
chain, and rejects unsupported results and non-Display errors; the compiler's
own bootstrap `main` still uses the untouched I32 path.

Landed standard-library progress: `std.process` installs its value layer at
`sysroot/std/process.al`: `PipeMode`, the value-semantic `Command` with
in-place builders, `ExitStatus` exit/signal decomposition, `Output`, and
`ProcessError` with `Display`/`Error`. Builder methods mutate a mutable
`Command` binding and return `Unit`; borrowed-place owner-domain provenance
keeps their `Vec`/`OsString` field growth in the caller's domain. Qualified
variant expressions such as `PipeMode.Piped` and
`ProcessError.Platform(info)` are implemented and carry the snapshot surface
without factory functions. Evidence:
`compiler/production_process_test.go` runs the value layer through the
installed sysroot, and `compiler/production_qualified_variant_test.go` pins
the cross-module construction forms. Spawning, `Child`, pipes, and capture
wait for `std.io` slice 2. Docs:
[`std.process` snapshot](docs/api/std.process-v1.md).

Landed standard-library progress: `std.fs` installs its value layer at
`sysroot/std/fs.al`: `Options.read`/`Options.write` and the portable public
`Permissions` record. File handles, directory iteration, metadata, and
temporary owners wait for `std.io` slice 2. Evidence:
`compiler/production_process_fs_test.go` exercises both value modules through
the installed sysroot. Docs: [`std.fs` snapshot](docs/api/std.fs-v1.md).

Landed C-interop progress: header-only explicit shims are available through
the ordinary binding-block syntax. A package or sysroot supplies a header of
`static inline` C functions for bitfields, flexible arrays, fixed arrays,
packed records, macros, inline functions, and fixed-argument wrappers over
variadics; the generated program includes it through its explicit include
root and the existing probes pin every bound function. `static inline` keeps
the shim out of the link symbol table, and C spellings stay outside the
reserved `alder_` prefix. Evidence:
`compiler/production_shim_test.go` compiles and runs a dirent name/length
shim and a pipe shim using `c.addr` under the strict warning set and
ASan/UBSan. Out-of-line `.c` shims and build-plan source objects remain
deferred to the build driver. Docs:
[docs/c-interop.md](docs/c-interop.md) "Explicit shims".

Landed standard-library progress: `std.random` ships both halves at
`sysroot/std/random.al`. The OS forms `fill`, `u64`, `u32`, `range_u64`, and
`range_u32` take the `std.io` capability through `Blocking`; `u64`/`u32`
assemble four or eight entropy bytes little-endian, and the range forms use
unbiased rejection sampling. `Rng` is SplitMix64 over one `U64` state with
value semantics, `seeded`, `next_u64`, `next_u32`, `range_u64`, `range_u32`,
and `fill(MutSlice(U8))`. Evidence: `compiler/production_random_test.go` runs
the installed sysroot module through the production driver, checks
independently computed SplitMix64 draws, range sums, the 32-bit high word,
eight-byte and 21-byte fills, and value-semantics copies, and exercises the OS
forms under `Blocking` and ASan/UBSan with shape-only assertions; the snapshot
example runs with a fixed checksum. Docs: [Standard Library](docs/standard-library.md)
and the frozen [`std.random` snapshot](docs/api/std.random-v1.md).

Landed C-interop progress continues with by-value verified records. The
checker accepts raw fn signatures with complete record parameters and
results, and inside `unsafe c` the field read `rec.field` (yielding the
field's declared binding type) and the field write `rec.field = value`
(requiring a `var` local and an exactly matching value type), rejecting a
non-record or scalar receiver with diagnostic 206, an unknown field with
207, a value type mismatch with 208, and a write through a non-`var`
binding with 209; lowering assigns record fields source-order MIR ordinals
that match the raw-fn parameter ordinals, and MIR gains operations 96-97
(`c.field.get`/`c.field.set`) validated by the verifier, mirrored in the Go
verifier, printer, and op model. The C backend lowers field reads and
writes to plain member access through the declared C spelling and moves
records by value through raw fn calls using the declared struct spelling;
binding emission pins field offset, fit, and type with `_Static_assert`/
`_Generic` probes per field. Evidence: the MIR-level `mir/verify` binding
tests, the cgen run fixture `cgen/testdata/run/crecord.mir`, and the
production qualification `compiler/production_c_record_test.go` (a
C-fixture program moving a record by value in every direction, compiled and
run under the strict warning set, print/MIR and cross-process determinism,
and five checker rejections); the surface is documented in
[docs/c-interop.md](docs/c-interop.md) "C records, unions, bitfields, and
variadics", [docs/mir.md](docs/mir.md) "Binding Blocks and C Types", and
[docs/c-backend.md](docs/c-backend.md).

Landed C-interop progress: `c.CString` ownership is installed end to end. A
string literal constructs the bare owner infallibly and the checker rejects an
interior NUL in the literal (diagnostic 210); any other `String` yields
`Option(c.CString)` with `none` for an interior NUL, and wrong argument count
or a non-`String` argument is rejected with 211 and 212. `owner.ptr()` borrows
the buffer as `c.ConstPtr(c.Char)` without consuming the owner, a callback-free
`using` registration releases the buffer exactly once through a synthesized
per-module shell, and `try` now propagates `Option` in a function returning
`Option` so `using name = try c.CString(text)` composes with the existing
cleanup rules. MIR gains operations 98-101 (`c.string.make_lit`,
`c.string.make`, `c.string.ptr`, `c.string.release`), and `str.display` moves
from 98 to 102; the Go parser, printer, type inference, and verifier mirror the
new operand rule and the constructors' failure edges so printed MIR
round-trips. The same slice fixed a general lowering defect the new ownership
exposed: `lower_binding_expression` built the disarm instruction for a
transfer, then rebuilt the place/type/load chain from the entry state and
silently discarded it, so no `using` owner was ever disarmed when it moved out
of its scope. Table and Vec releases hid it because their storage dies with a
domain; a moved CString was freed by the exiting scope and again by the
receiver (ASan heap-use-after-free and a libc double-free abort). The load path
now threads the transfer state, so every documented transfer path (plain
return, aggregate and `Option`/`Result` construction, `take` argument, match
scrutinee, re-registration) disarms exactly the moved entry. Evidence: the
production qualification `compiler/production_c_string_test.go` (literal, `try`,
runtime `none`, transfers through `Some` and a plain return, strict-warning
compile and run with the live allocation count unchanged, both disarms pinned
in generated C, MIR vocabulary and cross-process determinism, and three checker
rejections), the MIR accept/reject/printer round trip in
`mir/verify/c_string_ops_test.go`, and the updated `m75-cleanup-trait` fixture,
which registers the returned owner and observes the cleanup counter 16 (23
before the fix). Documentation is in
[docs/c-interop.md](docs/c-interop.md) "C strings",
[docs/mir.md](docs/mir.md) "C-String Ownership", and
[docs/c-backend.md](docs/c-backend.md). A cold `bootstrap/regenerate.sh`
measured 132.6 s wall and 1.94 GB peak RSS against 132.5 s and 1.92 GB for the
parent tree on the same host.

Landed C-interop progress: call-scoped buffer borrows. Inside `unsafe c`, a
`Bytes`, `[U8]`, or `MutSlice(U8)` argument may stand for a raw fn parameter
declared `c.ConstPtr(T)` or `c.Ptr(T)` when `T` is a byte-addressable pointee
(`c.Char`, `c.SChar`, `c.UChar`, or an opaque bound type). The borrow lasts
exactly one call, never moves the buffer, and never materializes a pointer as
an Alder value; immutable buffers satisfy only `c.ConstPtr`, and one buffer
may not be borrowed mutably twice in a call (checker 215, with 213 for a
non-byte pointee and 214 for an immutable buffer at a mutable pointer). An
empty buffer whose data pointer is null reaches C as the runtime's writable
one-byte dummy, because C library entry points reject NULL even at length
zero. MIR gains operation 107 (`c.buffer.ptr a, P`), mirrored in the Go
parser, printer, type inference, verifier, and cgen, and the C backend emits
the data-pointer read with the dummy fallback. The same slice fixed the
integer-receiver C conversion guard that rejected `to_c_size` and
`to_c_ptrdiff` (it excluded every scalar id at or above the two float ids),
which the buffer length conversions need. Evidence: the production
qualification `compiler/production_c_buffer_test.go` (MutSlice fill, `[U8]`
and `Bytes` reads, zero-length borrows of empty buffers, MIR and C
determinism, and four rejections), the cgen run fixture
`cgen/testdata/run/cbuffer.mir` (including a null-backed slice), and the MIR
accept/reject/round trip in `mir/verify/c_buffer_ops_test.go`. The
lifetime-class qualification in
`compiler/production_lifetime_classes_test.go` pins an affine `Cleanup` owner
on normal and early exits (exactly-once release through the imported
counter), a call-scoped borrow of a CString owner, and a copy into Alder
storage that is read back after the owner releases. Documentation is in
[docs/c-interop.md](docs/c-interop.md) "Strings and buffers",
[docs/mir.md](docs/mir.md) "Call-Scoped Buffer Borrows", and
[docs/c-backend.md](docs/c-backend.md). A cold `bootstrap/regenerate.sh`
measured 128.0 s wall and 2.01 GB peak RSS against 134.5 s and 2.00 GB for the
parent tree on the same host.

Landed C-interop progress: `c.CString` accepts exact `Bytes` as well as
`String`. A `String` literal keeps the infallible bare-owner form and its
compile-time interior-NUL rejection (210); a `String` or `Bytes` value yields
`Option(c.CString)` with `none` for an interior NUL, and an argument that is
neither is rejected with 212. The `Bytes` form copies exact bytes without a
UTF-8 requirement, which paths, environment strings, and argv need; a `Bytes`
literal may carry non-UTF-8 bytes. MIR `c.string.make` now accepts a `string`
or `bytes` operand in the Alder verifier and the Go mirror; the runtime helper
is unchanged because it is already byte-based. Evidence: the production
CString qualification gains a non-UTF-8 `Bytes` path (`0xff` round-trips
through a C length/first-byte fixture) and a `Bytes` interior-NUL `none`
path, and the MIR verifier/printer test accepts `make` on `bytes` and rejects
it on `c_string`. Documentation is in
[docs/c-interop.md](docs/c-interop.md) "C strings",
[docs/mir.md](docs/mir.md) "C-String Ownership", and
[docs/s0-language.md](docs/s0-language.md). A cold
`bootstrap/regenerate.sh` measured 135.8 s wall and 2.06 GB peak RSS against
133.6 s and 2.06 GB for the parent tree on the same host.

Landed C-interop progress: `c.Zero(T)` and `c.addr(place)` make C
out-parameters usable without exposing a raw pointer value. `c.Zero` accepts a
raw `c.*` scalar or a bound scalar or record type member (bare when exactly
one block declares it, or `alias.Name`) and yields a zero-initialized copyable
value in ordinary code; record fields stay confined to `unsafe c`, and an
opaque member, pointer type, unknown or ambiguous name, or wrong argument
count is kind 216. `c.addr` is admitted only as a direct raw-call argument
inside `unsafe c`; the place is a local variable or field path of one whose
type is the declared pointee, `c.Ptr` requires a `var` binding with no live
view, `c.ConstPtr` any local place without a mutable view, and the pointer
never becomes an Alder value (kind 217 otherwise). MIR 109 `c.zero` and 110
`c.addr` carry the forms beside 108 `slice.to_bytes`; cgen emits a C compound
literal for records and the address of the local, and no earlier MIR op
changed. Evidence: the production qualification writes a record member
through a `c.Ptr` out-parameter and observes the untouched member stays zero,
round-trips a `c.Zero(c.Long)` scalar through `c.Ptr` and `c.ConstPtr`,
addresses a `let` record const, and covers ten rejection shapes; the MIR
verifier test pins the textual format, the pointee and local-root rules, and
the printer round trip. A cold `bootstrap/regenerate.sh` measured 129.0 s
wall and 2.08 GB peak RSS against 128.3 s and 2.07 GB for the parent tree on
the same host.

Landed C-interop progress: pointer member access and whole-value C memory
make the verified record and scalar bindings usable behind the pointers raw
functions return. Inside `unsafe c`, `ptr.field` reads through a local holding
`c.Ptr(Rec)` or `c.ConstPtr(Rec)`, its write form is admitted only through
`c.Ptr` (kind 219 for a const pointer), and `c.load(ptr)` / `c.store(ptr,
value)` move a whole by-value C value, with kind 218 for a non-pointer,
opaque-pointee, or wrong-arity use and kind 220 for a stored value whose type
does not match. Pointer member access lowers through the existing deref and
field places with load and store, so no MIR op number is spent: a `c_ptr`
deref place is mutable, a `c_const_ptr` deref place is read-only, and a
`c_named` record field resolves by Alder name to its verified C spelling. No
null check is emitted; non-nullness, alignment, and the pointee's lifetime are
the unsafe caller's obligation, documented in
[docs/c-interop.md](docs/c-interop.md) "C records, unions, bitfields, and
variadics" and [docs/mir.md](docs/mir.md) "Pointer Places". Evidence: the
production qualification reads and writes a heap record's members through
`c.Ptr`, round-trips a whole record through `c.load`/`c.store`, reads through
`c.ConstPtr`, and moves a scalar pointer through both forms, with seven
rejection shapes; the MIR verifier test pins the accepted deref/field place
shapes, the const-store rejection, and the non-record pointer rejection, and
the printed form reparses. A cold `bootstrap/regenerate.sh` measured 132.7 s
wall and 2.09 GB peak RSS against 137.4 s and 2.08 GB for the parent tree on
the same host.

Landed C-interop progress: intentional C exports and `compile --emit=header`.
A top-level `export c fn` declaration defines a non-static C symbol named by
the Alder function. Its signature is restricted to C ABI types (`c.*` raw
scalars, `c.Ptr`/`c.ConstPtr` over a bound C type, and a verified bound scalar
or record by value), with `Unit` mapping to C `void`; any other signature type
is diagnostic 221. A generic or receiver-bearing declaration, a reserved or
otherwise invalid symbol, and an export named `main` are 222, and an export
whose symbol equals a raw fn's C spelling is 223; the reserved
`alder_`/`ALDER_`/`Alder` prefixes keep every export clear of generated
internal names. The generated C calls the ordinary static Alder function
through a wrapper that creates and destroys a per-call root domain, so a
foreign thread may call an export without entering `alder_program_entry`, and
failed domain initialization terminates through the runtime panic. The header
emits `<stddef.h>`, each binding header referenced by an export signature once
in declaration order, then the prototypes under an `extern "C"` guard whose
word digests the full sorted export-symbol list, so declaration order and
case-only name differences cannot collide. A source set with exports and no
`main` is a library build: C emission skips only the hosted-entry phase of
verification, emits no `alder_program_entry`, and leaves the export wrappers
callable from an ordinary C `main`; a source set with neither `main` nor an
export keeps the missing-entry failure. Evidence: the production qualification
`compiler/production_c_export_test.go` compiles and runs scalar, by-value
record, pointer/length, Unit, and no-argument exports from a C driver through
the generated header under the strict warning set, compiles and calls a
main-less export library, checks header-guard order and case independence,
checks include order, deduplication, unreferenced-header exclusion, and
cross-process determinism for both outputs, and pins eight rejection shapes
across 221-223 and parse 35 plus the no-entry failure. The MIR is unchanged,
so the existing verifier and printer tests cover the lowered functions.
Documentation is in [docs/c-interop.md](docs/c-interop.md) "Callbacks and C
calling Alder", [docs/c-backend.md](docs/c-backend.md) "Exported functions",
[docs/modules-and-builds.md](docs/modules-and-builds.md), [docs/mir.md](docs/mir.md),
and [docs/s0-language.md](docs/s0-language.md). A cold
`bootstrap/regenerate.sh` measured 145.6 s wall and 2.16 GB peak RSS against
132.6 s and 2.16 GB for the parent tree on the same host.

Landed C-interop progress: nonretained C callbacks. A binding block can
declare `callback type Name = "spelling" (params) -> result` for a C
function-pointer typedef restricted to C ABI types. Inside `unsafe c`,
`c.callback(target)` supplies the callback directly to one raw call; the
target must be a top-level, non-generic, noncapturing function with the bound
signature, and callback pointers never become ordinary Alder values
(diagnostics 224-227, parse 31). MIR 111 `c.callback.make` carries the target
function and callback type; cgen emits a static trampoline that creates a
per-invocation root domain when needed, enters the runtime, and pins the
trampoline against the binding typedef with `_Generic`. A retained
registration uses the unsafe-only `c.CallbackOwner.register(set, clear, wait,
target, context)`: the context is copied into separate heap storage, the
owner is an affine `Option` value, and its `using` cleanup clears, waits, then
frees with exactly-once transfer semantics; a nonzero clear terminates with
status 101 because freed context must never remain registered. Moving the
owner through a `take` parameter keeps the context address stable. Foreign-
thread callback entry is added by the ABI/thread slice below. Evidence:
`compiler/production_c_callback_test.go` compiles and runs synchronous
nonretained and retained callbacks under the strict warning set, moves the
retained owner through a generic `take` helper, runs the retained program
under ASan/UBSan, checks the trampoline and owner helper shapes and
cross-process determinism, and pins target-mismatch, clear-contract, and
unsafe-only rejections. Documentation is in
[docs/c-interop.md](docs/c-interop.md) "Callbacks and C calling Alder",
[docs/c-backend.md](docs/c-backend.md) "Callback trampolines",
[docs/mir.md](docs/mir.md) "C Callback Values", and
[docs/s0-language.md](docs/s0-language.md). A cold `bootstrap/regenerate.sh`
measured 139.8 s wall and 2.21 GB peak RSS against 131.0 s and 2.18 GB for the
parent tree on the same host.

Landed compile-memory progress: verification's V6 provenance tables are the
largest per-compile scratch allocation, and cgen used to inherit them because
they stayed in the root domain. V6 and phases 6-8 now run in a child domain;
on a clean result it is destroyed before phases 9-10 and cgen, while a refusal
or allocation failure re-runs those phases in the caller's domain so refusal
diagnostics and storage errors stay byte-identical. The verifier conformance
manifest pins a phase-6 refusal through `mir_verify_complete`, and an
ASan/UBSan stage-1 self-compile exercises the destroyed domain before cgen.
A cold `bootstrap/regenerate.sh` measured 112.3 s wall and 2.01 GB peak RSS
(2,013,632 KiB), down from 2.20 GB and under the 2 GiB project target, against
109.8 s for the parent tree on the same host; the remaining peak is
verification itself.

Landed C-interop progress: target ABI probes and foreign-thread entry.
`compile --emit=bind` emits a deterministic standalone C unit with each
binding header, `_Generic`/`_Static_assert` record, field, function, and scalar
spelling checks, then target data-model assertions (`CHAR_BIT == 8`, pointer
width, `size_t`/`ptrdiff_t` width and alignment). Binding-only sources need no
`main` or export, and the C compiler remains the target ABI authority; there is
no Alder layout engine. The host x86-64 fixture emits and compiles the probe,
mutates a bound field type to pin a diagnostic, and runs a main-less bind source
with `--emit=bind`; separate CI lanes cross-compile the same deterministic unit
with `aarch64-linux-gnu-gcc` and `x86_64-w64-mingw32-gcc`. The macOS lane is
deferred to a macOS runner. Target-specific binding modules use the manifest's
existing target-root selection, documented in
[docs/modules-and-builds.md](docs/modules-and-builds.md); no source clauses or
package work are added.

The runtime now supports foreign-thread entry for pure-Alder exports and
retained callbacks whose `wait` is a real barrier. The live-allocation counter
and domain, segment, and table serials use C11 `<stdatomic.h>`; a target that
defines `__STDC_NO_ATOMICS__` fails the build with `#error`. Each export and
callback trampoline creates an independent root domain instead of entering
`alder_program_entry`. Host-shim services that own their own threads remain
excluded until the hosted-entry bridge exists. Evidence:
`compiler/production_c_thread_test.go` runs eight pthreads making 500 export
calls each against an export that uses storage, and registers a retained
callback whose worker thread invokes the trampoline while cleanup clears,
waits, joins, and frees under the strict warning set.
`compiler/bootstrap_test.go` covers the bind fixture and cross-target test;
`.github/workflows/ci.yml` carries the two compile-only lanes. Documentation is
in [docs/c-interop.md](docs/c-interop.md) "Target ABI probes" and "Callbacks
and C calling Alder", [docs/c-backend.md](docs/c-backend.md) "Binding and
target-ABI probes" and "Exported functions", and
[docs/modules-and-builds.md](docs/modules-and-builds.md).

Landed C-interop progress: the narrow S0 C bridge (`import c name:
fn(...) -> T`) no longer appears on the public surface. Ordinary modules
reject the form at the checker with the stable bootstrap-private diagnostic
106 ("bootstrap operation ... is private to the compiler's bootstrap sources
(--bootstrap-private)") before the signature resolves, while
`compiler/src/*.al`, `bootstrap/spike/*.al`, and the conformance fixtures
that exercise the bridge's call mechanics keep it under the private
bootstrap profile. This closes the s0-language removal-gate row "direct
`import c name`": header binding blocks own the public C surface. Evidence:
the `direct-c-import` rejection case in
`compiler/production_binding_test.go`, the extended private-profile detector
in the checker conformance runner (all existing narrow-import fixtures still
pass under `--bootstrap-private`), and the bootstrap fixed point, which
compiles the compiler's own host imports under the profile.

## Milestone 9: Async Runtime and Structured Concurrency

Status: **required before Alder 1.0**

Implement the `Io`/`BlockingIo`/`AsyncIo` capability traits, signature-based
suspension checking, per-instance direct or state-machine MIR/lowering, affine
`TaskGroup` and `Task(T)`, `Pending(T)` task operations, structured
cancellation with suspending cleanup, multithread and local executors,
`SimIo`, channels, synchronization, atomics, timers, evented files/sockets,
and the bounded blocking-C bridge defined in
[Async and Structured Concurrency](docs/async.md).

Exit requires one source instantiated under both `Blocking` and `Evented` with
identical results, rejection of guards and affine values across potentially
suspending calls and of suspending closures, data-race rejection, nested
join/cancel/cleanup tests, `SimIo` virtual-time and deadlock tests, channel
backpressure/FIFO tests, task-transfer and thread-affinity checks, high task
counts with bounded stack/storage, blocking C completion after cancellation,
and sanitizer/race coverage on supported hosts. No child may outlive its group
and no detached task surface may be introduced.

## Milestone 10: Batteries-Included Standard Library Completion

Status: **required before Alder 1.0**

Complete the [Standard Library](docs/standard-library.md), written once
against `I: Io`, with networking, DNS, TCP/UDP, URL, HTTP/1.1 and HTTP/2, TLS with secure defaults,
JSON, encodings, CLI parsing, logging, signals, async processes, and all required
cross-platform error contracts and precise per-module error enums. Ship versioned Unicode, timezone, certificate,
and native provenance data with the toolchain.

Exit requires offline use after installation and complete Linux/macOS/Windows
behavior suites for paths, Unicode, I/O, cancellation, networking, TLS
verification, bounded parsers, process behavior, and unsupported capabilities.
HTTP/TLS/JSON are toolchain libraries, not an implicit network download.

## Milestone 11: Formatter, Test/Doc Tools, and Language Server

Status: **required distribution tooling before Alder 1.0**

Implement `alder fmt` over lossless syntax, the isolated deterministic test
runner (parameterized cases, seeded fuzz corpora, `--fuzz`, value-capturing
assertions), `alder doc` layered queries and search, `alder ide`,
`alder explain`, `alder spec`, `alder fix`, `alder help agent`, required doc
comments, and baseline `alder lsp` over the same serialized build plan,
compiler service, and diagnostics, following the CLI output contract in
[Modules and Builds](docs/modules-and-builds.md#cli-output-contract).
Splitting coarse diagnostic codes into one code per rule is not gated on this
milestone; it proceeds whenever a diagnostic is added or touched, per
`CONTRIBUTING.md`.

Exit requires formatter idempotence/trivia, upgrade stability, and
malformed-input behavior, CLI output-contract tests (one-line success,
complete first-read diagnostics, head-and-tail truncation with a full-output
file, text/JSON parity), an explanation entry for every diagnostic code,
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

## Post-1.0: Native UI Package

Status: **planned after Milestone 14; official Git package, not `std`**

Build a native desktop UI toolkit as an official package, with the native UI
of [MyGo](https://github.com/egoist/mygo) as the reference design
([D021](docs/design-decisions.md#d021--native-ui-is-an-official-package-after-10)).
It depends on the 1.0 closures, resources, C bindings with callbacks, and
cross-thread wakeup, and is sequenced so the deterministic core lands first:

1. a pure-Alder core: views rebuilt from state each frame, element identity
   and per-element state, flexbox and grid layout, a display list, a
   deterministic CPU rasterizer, and a windowless tester with golden images;
2. Linux windows through GTK with Pango text, presented from the CPU renderer;
3. input methods, ATK accessibility, and an OpenGL renderer checked against
   the CPU renderer;
4. macOS (Metal, Core Text) and Windows (Direct3D 11, DirectWrite).

## Deferred Work

The following items are not part of the current implementation scope:

- a macOS bind-probe CI lane and macOS foreign-thread run fixtures: deferred
  to a macOS runner; Linux x86-64, Linux AArch64, and Windows LLP64 compile
  lanes cover the current target-ABI probes;
- hosted runtime initialization for host-shim services that own their own
  threads: pure-Alder exports and retained callbacks with a real `wait` barrier
  are in scope, but services outside that contract wait for the hosted-entry
  bridge;
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
- detached fire-and-forget tasks;
- generators, `gen` blocks, and callback sugar such as Gleam's `use`;
- `Vec(Table(T))` and other heap-stored table handles: the phase-6 MIR
  verifier lifetime rule (`lifetime_deref_store`) rejects storing a table
  handle through a deref place, so table elements await a storage decision.
  No 1.0 sentence requires the composition, and diagnostic 143 keeps the
  surface honest in the meantime.
- record field *read* privacy: S0 enforces only construction privacy (a
  record with a non-`pub` field cannot be constructed outside its module,
  diagnostic 309); reads of any field still type-check across modules. The
  full module-visibility pass that makes non-`pub` fields unreadable is
  deferred; the opaque-construction boundary and every `using`/affine rule
  already hold.
- get_mut growth of relocatable fields: a `Table` view can assign scalar
  fields today, but table elements must be concrete copyable data, so a
  `Vec`/`String`/`Bytes`/`OsString` field cannot live in a table. Growing such
  a field through `get_mut` waits for tables whose elements carry relocatable
  storage.
- returning an affine `c.CString` through a `match` arm: the affine flow
  analysis requires the owner to be transferred on every reachable path or
  on none, and a branch that returns a `While`/`match` expression value does
  not count as a transfer. Minimal repro:
  `fn make(text: String) -> Result(c.CString, U64) { return match c.CString(text) { Some(value) => Ok(value) None => Err(1) } }`
  fails with "affine owner must be transferred on every reachable path or on
  none". `std.io` avoids it by building host paths in a `Vec(U8)` buffer.
- a trait method call whose name matches an imported free function resolves to
  the free function and reports diagnostic 58. With
  `import std.fs { File, open, read }` and a local `file: File(Blocking)`,
  `file.read(buffer)` fails even though `File` implements `Reader`; the same
  program works after dropping the `read` import. The `std.fs` fixtures keep
  method calls and free-function imports in separate programs until method
  lookup prefers the receiver's trait method.

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
