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
  `75c952372441e13769facf40c546ed768a64523b9eb0daa978b655f4e2c904dd`
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
  `75c952372441e13769facf40c546ed768a64523b9eb0daa978b655f4e2c904dd`

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

Status: **in progress (both implementation halves are integrated; the items under "Remaining before exit" below, including those added by the 2026-11 design amendment, are still ahead)**

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

Exit-criteria evidence (in progress):

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
- structural `Eq`/`Hash` implementations are synthesized for unsigned
  integers, `Bool`, `String`, `Bytes`, and non-generic records/enums over
  that domain, satisfying `Eq + Hash` constraints while user `impl Eq`/
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
  immutability and capture types are gated to storage-free ordinary
  values, diagnostic 145; malformed shapes are rejected with 147). The
  environment is one domain-allocated record per closure built through
  `aggregate.construct` plus `copy_to_domain`, so creation stays inside the
  verifier loop-store rule's domain-provenance discipline; thunks take no
  hidden domain parameter and the wrapper adapts the opaque environment
  pointer to the thunk's reference parameter. A literal inside a generic
  function body materializes one thunk per checked instance, so its
  parameters, captures, and result take that instance's concrete types;
  the linear body walk skips thunks and a post-body pass checks each one
  after every ordinary body has run, which is also when an instance's
  site check has recorded the thunk signature. Nested literals and
  creation inside a `while` loop are rejected (147) or refused by the
  phase-6 loop-store rule until runtime-backed environments land, and
  closure sites, thunks, and erased `fn(params) -> result` value types are
  pinned through generated strict C11 programs with captures.
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
  compiler-synthesized no-op release;
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

Deferred from this half, with reasons:

- `Table.try_insert`: needs a non-panicking MIR insert edge (fallible
  capacity policy) that the current table operations do not expose;
- `Vec(Table(T))`: the phase-6 MIR verifier lifetime rule
  (`lifetime_deref_store`) rejects storing a table handle through a deref
  place, so heap-stored table elements await a storage decision; diagnostic
  143 keeps the surface honest in the meantime;
- suspending cleanup behavior: deferred to Milestone 9 as planned.

Compile-time guardrails (cold `bootstrap/regenerate.sh`, 8-core host):
2a96d07 2:08 / 3.78 GiB; sibling trait commits through `77437ec`
2:18 / 4.10 GiB; resource-half tip `90dce35` 2:27 / 4.30 GiB. The peak is
the stage-0 self-compile process itself (gcc on the emitted C peaks at
0.85 GiB), and its growth is proportional to the compiler's own source
(+11.5% across both halves), matching the pre-milestone record density
(2.5-3.4 KB RSS per added source byte against a 2.5 KB baseline). No
whole-store scan or copy amplification is present: the regenerator stays in
its 2.5-minute class, far inside the 15-minute CI budget.

Remaining before exit (as of the integration of both halves; the items below
were added to or reshaped by the 2026-11 design amendment, which landed after
both halves were written):

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
- remaining closure limits: nested closure literals (147) and closure
  creation inside a `while` loop (the phase-6 loop-store rule) still
  reject; runtime-backed environments are the follow-up. Literals inside
  generic function bodies now materialize one thunk per instance and are
  no longer rejected.

Integrated tip timing (cold `bootstrap/regenerate.sh`): 2:40 / 4.89 GiB,
against the 2:07 / 3.78 GiB pre-milestone baseline. Each commit's growth
stayed proportional to the compiler's own source size; profiling the
self-compile memory density is tracked separately.

## Milestone 8: Verified C Bindings and Hosted Standard-Library Foundation

Status: **planned after Milestone 7.5 completes the 1.0 resource/type model**

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
- generators, `gen` blocks, and callback sugar such as Gleam's `use`.

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
