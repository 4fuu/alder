# Alder 1.0 Product Contract

Design status: **Frozen target**

Availability: **Not implemented as a complete release**

This document defines what the project must deliver before it may call a
release **Alder 1.0**. Frozen means the default target for implementation and
tests. It does not mean immutable: a later explicit design decision may amend
the contract and must update every owning document, the decision register, and
the roadmap together.

The current Go bootstrap, Alder compiler slices, MIR toolkit, C backend, and C
runtime are evidence toward this target. They are not Alder 1.0.

## Product promise

Alder 1.0 is a native, statically typed language that is:

- memory-safe and data-race-free in safe code;
- predictably fast without a tracing garbage collector or universal hidden
  reference counting;
- small enough to learn from one coherent language guide;
- modern enough for algebraic data, generics, closures, structured concurrency,
  deterministic cleanup, modules, packages, testing, and editor tooling;
- practical for coding agents: every toolchain capability is a compact,
  noninteractive CLI command whose diagnostics state cause and fix directly;
- directly interoperable with C through a narrow, explicit trusted boundary;
- usable offline after installation, with a version-matched standard library
  and build tool;
- deterministic at compiler and package boundaries.

Safe Alder and correctly verified generated C must not invoke C undefined
behavior. That guarantee assumes the Alder runtime and every `unsafe c` block,
C binding description, native recipe, and linked native library uphold their
documented contracts. Alder cannot remove undefined behavior from arbitrary C
executing beyond that boundary.

## Required 1.0 language profile

| Area | Required contract | Owning document |
|---|---|---|
| Values | Independent value semantics for ordinary data; narrowly affine resource owners | [Language Semantics](language-semantics.md) |
| Numerics | Exact-width integers and IEEE binary floats; checked arithmetic; explicit conversion | [Language Semantics](language-semantics.md) |
| Data | Records, enums, `Option`, `Result`, exhaustive `match`, fixed arrays, slices, strings, bytes, vectors, maps, sets | [Syntax](syntax.md), [Standard Library](standard-library.md) |
| Generics | Compile-time `type` parameters, inference, `Name(...)` application, monomorphization | [Syntax](syntax.md) |
| Traits | Static constrained polymorphism with package coherence; no required runtime dispatch | [Traits and Closures](traits-and-closures.md) |
| Closures | Typed closures with safe value capture and no implicit shared mutable capture | [Traits and Closures](traits-and-closures.md) |
| Storage | Compiler-inferred hierarchical storage with safe outer-domain retention fallback | [Memory and Resources](memory-and-resources.md) |
| Identity | `Table(T)`, generational `T.Id`, and nonescaping table views | [Memory and Resources](memory-and-resources.md) |
| Resources | Affine owners, `using`, exactly-once normal cleanup, explicit transfer | [Memory and Resources](memory-and-resources.md) |
| Concurrency | I/O capabilities with per-instance suspension, task groups, `await` on task handles, cancellation cleanup, isolated task state | [Async and Structured Concurrency](async.md) |
| C | Verified ABI descriptions, raw C types, safe-wrapper rules, C exports and callbacks | [C Interoperability](c-interop.md) |
| Modules | Private-by-default modules, explicit public exports, deterministic acyclic package graph | [Modules and Builds](modules-and-builds.md) |

No required row may remain only illustrative at the 1.0 release gate. Each
must have executable acceptance and rejection tests through verified MIR and
strict C11.

## Required 1.0 distribution

One Alder installation includes, without a network fetch:

- the `alder` compiler and deterministic build driver;
- the version-matched C runtime, host support, target descriptions, and
  sysroot;
- the complete `core` and `std` libraries in
  [Standard Library](standard-library.md);
- the formatter, test runner, documentation generator, semantic query
  commands, offline language specification, package commands, and baseline
  language server;
- the managed pinned xmake/xrepo native provider and recipe snapshot, as a
  replaceable component not used by the compiler bootstrap or standard library;
- project templates and C binding templates;
- a source bootstrap artifact and regeneration instructions;
- licenses and source provenance for all bundled native components.

The normal workflow is deliberately conventional:

```text
alder new hello
alder check
alder run
alder test
alder fmt
alder build --release
```

The same driver owns Alder module resolution, lockfiles, generated C, native
provider plans, linking, and diagnostics. Users do not need to invoke xmake or
a C compiler directly for an ordinary project.

## Packages and native dependencies

Alder 1.0 includes local workspace dependencies and exact-revision Git
dependencies with an authoritative `alder.lock`. Locked and offline builds are
first-class. A public registry, publishing service, and general semantic-version
solver are not required for 1.0.

Managed, version-pinned xmake/xrepo is the default replaceable provider for
third-party C and C++ packages. It is below Alder's build-plan boundary:
xmake does not define Alder modules, package identity, or lockfile semantics.
The compiler bootstrap and standard library do not require xmake at build or
run time. See [Modules and Builds](modules-and-builds.md).

## Supported targets

The 1.0 release must qualify these hosted target families:

- Linux on x86-64 and AArch64 with a supported GCC or Clang C11 toolchain;
- macOS on x86-64 and Apple silicon with the supported Apple Clang toolchain;
- Windows on x86-64 with a documented supported C11 toolchain.

Every tier-1 combination must run the language, standard-library, concurrency,
generated-C, sanitizer where available, package, and bootstrap acceptance
suites. A target is not supported merely because generated C happens to
compile. Additional targets, including WASI, may be added without weakening
these gates.

## Safety and failure baseline

Safe 1.0 code prevents null dereference, out-of-bounds access, stale identity
reuse, use after invalidation, double cleanup, unsequenced C evaluation, signed
overflow, invalid shifts and conversions, and data races.

Recoverable operational failures use `Result`. Bounds errors, arithmetic
overflow in infallible operators, OOM in an infallible allocation operation,
identity exhaustion, and violated runtime invariants terminate the process.
They never continue through C undefined behavior. Process termination is not
catchable and does not promise caller-frame unwinding. Fallible collection and
allocation APIs are required wherever exhaustion is an expected control path.

## Release evidence

Alder 1.0 requires all of the following, not only implementation presence:

1. a fixed-point source bootstrap reproducible without Go or a prior Alder
   installation;
2. deterministic diagnostics, MIR, generated C, build plans, package locks,
   and test enumeration across source-order and process permutations;
3. strict-warning C11 compilation on every tier-1 toolchain;
4. sanitizer, static-analyzer, malformed-input, allocation-failure, and
   compiler-scale stress coverage appropriate to each supported host;
5. source-to-C-to-execution suites for every required language row above;
6. standard-library behavior, cancellation, cleanup, path, Unicode, I/O,
   network, and concurrency tests on every supported OS family;
7. C interop suites covering layouts, nullability, buffers, ownership,
   callbacks, blocking calls, and ABI rejection;
8. a documented compatibility policy, migration notes, and no bootstrap-only
   name or representation in public APIs;
9. representative benchmarks showing no known accidental exponential compiler
   behavior and no unbounded hidden ARC/GC cost;
10. a clean offline install-and-build acceptance from the published source and
    binary distributions;
11. an `alder fmt` stability guarantee: a newer edition-1 toolchain never
    reformats a file that an older edition-1 formatter left conforming;
12. CLI output-contract tests: one-line success, complete first-read
    diagnostics, head-and-tail truncation with a full-output file, and parity
    between text and JSON records.

## Compatibility after 1.0

The manifest declares `edition = "1"`. Patch and minor toolchain releases may
add APIs and diagnostics but must not silently change valid edition-1 program
semantics. Source-breaking language changes require an opt-in later edition;
the compiler keeps migration diagnostics for the preceding edition. MIR and
the native Alder ABI remain separately versioned and are not user-facing
stability promises. Intentional C ABI exports are stable according to their
declared C signatures.

## Deliberately outside 1.0

Alder 1.0 does not require:

- LLVM, another production backend, a JIT, or a REPL;
- a package registry, package publishing, or general semver solving;
- macros, arbitrary compile-time execution, or dependent types;
- dynamic trait objects, implementation specialization, or class inheritance;
- detached fire-and-forget tasks;
- a stable native Alder-to-Alder binary ABI;
- a graphical debugger or broad IDE refactoring suite;
- bit-identical native executables across different C toolchains.

These exclusions keep one understandable language and one auditable production
path without making Alder 1.0 a bootstrap-only product.
