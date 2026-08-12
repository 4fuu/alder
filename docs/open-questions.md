# Alder Open Questions

This file contains only choices that do not determine whether a required Alder
1.0 capability exists. The 1.0 product contract, async, modules/builds, C
boundary, and standard-library minimum are already selected. Open items choose
an implementation or narrow spelling and must not be used to silently defer a
required feature.

## Before the corresponding implementation milestone

### Storage inference algorithm

Required result: implement the semantics in
[Memory and Resources](memory-and-resources.md).

Choose and test the smallest constraint/fixed-point algorithm that places
storage, proves scoped views, and reports retention/copy costs at compiler
scale. The safe outer-domain fallback is not open.

### Exact MIR representation for async suspension

Required result: implement [Async and Structured Concurrency](async.md).

Decide whether suspension, cancellation cleanup, and executor wakeups belong in
a new explicit MIR version or are lowered to existing CFG plus narrowly
verified runtime operations. The representation must remain backend-neutral
and iteratively verifiable.

### Windows tier-1 C toolchain

Required result: qualify Windows x86-64 for Alder 1.0.

Select the exact supported MSVC/clang-cl/MinGW profile from executable C11,
sanitizer where available, ABI, async, and bootstrap evidence. The decision may
support more than one family but must name one release baseline.

### Vendored TLS backend

Required result: ship `std.net.tls` offline with secure defaults.

Select and pin the backend(s), update/security process, platform trust-store
integration, license/provenance handling, and source-bootstrap path. The TLS
module itself is not optional for 1.0.

### C binding probe mechanism

Required result: validate [C Interoperability](c-interop.md) against the real
header/toolchain.

Choose the portable combination of `_Static_assert`, typed assignments,
`offsetof`, generated access shims, and compile/run probes. Do not introduce a
second C parser unless measured bindings require it.

### Standard-library final API snapshots

Required result: implement every module family in
[Standard Library](standard-library.md).

Before implementation of a module begins, add a versioned public signature
snapshot and executable examples to its owning standard-library specification.
Review and freeze exact method names and error payloads one coherent module at
a time; implementation may not invent a public surface absent from that
snapshot. Keep the selected owned/view/resource categories and module scope.
Pre-1.0 spelling may change only by updating the snapshot, examples, and
callers together.

### Performance budgets

Required result: meet the 1.0 release evidence without changing safe semantics.

Set quantitative compiler memory/time, generated-C compile time, runtime,
async scheduling, collection-copy, and binary-size budgets from representative
program baselines. Include layered DAGs and malformed/adversarial inputs, not
only linear happy paths.

## Candidates after 1.0

These may receive separate design proposals after 1.0:

- Unicode identifiers and normalization rules;
- dynamic trait objects and stable plugin boundaries;
- macros or restricted compile-time evaluation;
- a public package registry and semver solver;
- detached service supervisors with explicit process-level ownership;
- WASI and embedded/freestanding support beyond `core`;
- a stable native Alder ABI;
- a second backend after measured C-path limitations;
- richer pattern syntax, destructuring bindings, and user const generics;
- debugger protocol and broad semantic refactoring.

## Resolved questions removed from this file

When an item is resolved, move the result to its owning contract and summarize
it in [Design Decisions](design-decisions.md). Do not preserve stale alternatives
here as if they remain equally valid.
