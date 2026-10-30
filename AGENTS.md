# Alder Repository Guidance

## Repository Identity

The repository is currently named `4fuu/alder` and was formerly named
`4fuu/aster`. Existing remotes, links, or metadata that use `4fuu/aster` are
valid historical references to the same project and must not be mistaken for a
different repository. Prefer `4fuu/alder` for new references.

## Project Status

Alder is in the design and bootstrap phase. Do not claim that a compiler, runtime, or language feature is usable unless executable code and tests demonstrate it.

## Active Scope

Current implementation work is limited to:

- Alder MIR representation, textual format, verification, and tests;
- deterministic lowering from verified MIR to conservative C11;
- the minimal C runtime required by that lowering;
- the Alder-written compiler core and fixed-point bootstrap work required by
  active Roadmap Milestones 5.4 and 5.5;
- design and bootstrap infrastructure directly supporting those goals.

The full Alder 1.0 product is a frozen documentation target. Do not implement
later modules, async, package, standard-library, xmake-provider, or tooling
milestones ahead of their roadmap gate unless an explicit scope decision
changes the sequence.

LLVM is explicitly out of scope. Do not add LLVM dependencies, bindings, build flags, IR concepts, or a placeholder backend without a new approved project decision.

## Documentation Ownership

- `docs/alder-1.0.md`: Alder 1.0 product and release requirements.
- `docs/language-design.md`: user-facing design index and support matrix.
- `docs/syntax.md` and `docs/language-semantics.md`: source syntax and semantics.
- `docs/memory-and-resources.md`, `docs/traits-and-closures.md`, and
  `docs/async.md`: storage, ownership, abstraction, closure, and concurrency
  contracts.
- `docs/c-interop.md`, `docs/modules-and-builds.md`, and
  `docs/standard-library.md`: C, project/toolchain, and distribution contracts.
- `docs/s0-language.md`: implemented bootstrap-only source contract.
- `docs/design-decisions.md` and `docs/open-questions.md`: accepted decisions
  and genuinely unresolved nonblocking choices.
- `docs/mir.md`: MIR operations and verifier invariants.
- `docs/c-backend.md`: C lowering and undefined-behavior policy.
- `ROADMAP.md`: implementation sequence, status, evidence, and deferred work.
- `CONTRIBUTING.md`: engineering and contribution standards.

Keep all repository documentation, code comments, diagnostics, and commit messages in English. Update the owning document whenever semantics change.

## Engineering Standards

- Prefer the smallest change that advances the active milestone.
- Use Go only as the temporary Stage 0 bootstrap implementation.
- Prefer Go standard-library packages and stable numeric IDs for compiler graphs.
- Never depend on Go map iteration order in diagnostics or generated output.
- Use compile-time `type` parameters and `Name(...)` application in generic language examples; do not introduce angle-bracket or square-bracket generic syntax.
- Keep generic inference and monomorphization ahead of backend MIR and C lowering.
- Target portable C11 for handwritten runtime and generated code.
- Preserve explicit sequencing and avoid C undefined behavior.
- Do not add speculative abstractions, optimizations, or configuration.
- Keep generated output deterministic and inspectable.
- Add focused acceptance and rejection tests for semantic changes.

## Expected Checks

Before executable code exists, validate documentation links and lifecycle scripts manually. Once the Go module and C runtime are introduced, keep the canonical build, format, and test commands in this file and `CONTRIBUTING.md` synchronized.

Canonical Go checks (run before committing MIR toolkit changes):

- `gofmt -l .` must print nothing;
- `go vet ./...` must pass;
- `go test ./...` must pass.

Canonical C checks (run before committing runtime changes; keep the flag set synchronized with `CONTRIBUTING.md`):

- `gcc -std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -fsyntax-only runtime/c/alder.c` must pass;
- `go test ./runtime -count=1` compiles and runs every runtime behavior test under the strict warning set and reruns them under ASan/UBSan when the host toolchain supports it;
- `go test ./cgen -count=1` pins the generated-C goldens, compiles every golden under the strict warning set, runs the compile-and-run behavior fixtures, and checks generation determinism across processes;
- `go test ./frontend -count=1` pins the printed-MIR goldens and rejection diagnostics, runs the end-to-end source-to-C11 programs, and checks compilation determinism across processes.

Canonical source-bootstrap check (run before committing compiler-source or bootstrap-artifact changes; keep synchronized with `CONTRIBUTING.md`):

- `bootstrap/regenerate.sh` must validate the source inventory and reproduce `bootstrap/alder.c` byte-for-byte using only the committed source bootstrap, runtime, host shim, system C11 compiler, and common POSIX-host utilities. Its default run is cold and hermetic; `ALDER_BOOTSTRAP_CACHE=1` may reuse a keyed stage-0 binary from the ignored `.alder-cache/` directory and removes no check.

The `compiler` package tests reuse identical build artifacts across `go test` processes through a content-hash cache under the user cache directory. `ALDER_TEST_CACHE=0` disables reuse and rebuilds everything. The cache is on by default, is keyed on the test binary plus the Alder and C sources, the C compiler and its version, and the exact build flags, and verifies a SHA-256 digest of every artifact before reusing it; any doubt rebuilds. Every assertion in the affected tests runs on every invocation either way, so the cache changes how long the gate takes, never what it checks.

Orb lifecycle scripts (`.agents/setup`, `.agents/resume`) are used only in the Amp environment and are not part of the normal build process. They must remain non-interactive and idempotent. `.agents/setup` installs missing prerequisites; `.agents/resume` only performs fast checks and must not install dependencies.
