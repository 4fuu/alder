# Contributing and Project Standards

Alder is in the design and self-hosting bootstrap phase. Small, reviewable
changes that advance the active compiler slice through the verified MIR-to-C
path are preferred over implementing later Alder 1.0 milestones early.

## Language and Communication

- Repository documentation, code comments, diagnostics, and commit messages must be in English.
- Examples should distinguish proposed syntax from implemented behavior.
- Do not describe an unimplemented feature as supported.
- Safety and performance claims require executable evidence.

## Current Scope Boundary

Changes may advance:

- language-memory-model documentation;
- Alder MIR representation, verification, and tests;
- deterministic C11 generation;
- the minimal C runtime required by generated programs;
- source identity, structured diagnostics, compiler-service, and thin CLI work
  required by the active roadmap milestone;
- bootstrap and self-hosting infrastructure that directly serves those areas.

Do not add:

- LLVM dependencies or an LLVM backend;
- a second native backend;
- a JIT;
- package-manager, LSP, IDE, or macro infrastructure ahead of its roadmap gate;
- speculative runtime configurability without a current semantic need.

Proposals outside the active scope should update the roadmap or be recorded as a design question rather than partially implemented.

## Architecture Boundaries

The intended compiler layering is:

```text
source frontend -> typed HIR -> Alder MIR -> MIR verifier -> C11 backend
                                             |
                                             +-> C runtime ABI
```

Rules:

- MIR must not depend on C syntax, LLVM concepts, or source AST node shapes.
- Surface generic examples use compile-time `type` parameters and `Name(...)` type application; angle-bracket and square-bracket generic application are not Alder syntax.
- Generic source constructs must be inferred and monomorphized before backend MIR and C lowering.
- The C backend must consume only verified MIR.
- Runtime helpers must have explicit contracts and remain usable from ordinary C11.
- Source locations may be attached for diagnostics, but they must not change semantics or deterministic output.
- Compiler graph structures should prefer stable integer IDs and contiguous storage over pervasive host-language pointers.
- Semantic lowering and behavior changes should be separate from formatting or mechanical cleanup when practical.

## Diagnostic Standards

These rules apply to every new or changed diagnostic in the Go bootstrap and
the Alder-written compiler, and implement the CLI output contract in
`docs/modules-and-builds.md`.

- One rule, one stable code. Codes are a namespace prefix (`LEX`, `SYN`,
  `SEM`, `LOW`, ...) plus four digits and are never reused for a different
  rule. The existing catch-all codes `LEX0001`, `SYN0001`, and `SEM0001` are
  split by rule as diagnostics are added or touched; new code must not emit
  them for a rule that has its own code.
- The message states the direct cause in one sentence and names the involved
  binding, type, value, or construct. Related locations go in related ranges,
  not in prose.
- When the compiler knows a fix, the diagnostic carries it as a note and, when
  mechanical, as a text edit. A reader must not need `alder explain` to know
  what is wrong, where, or how to fix it.
- Every code has an explanation entry: a few lines of background, a minimal
  wrong/right example pair, and the governing specification section.
- Types are printed with the names visible at the diagnostic's location.
- Rejection tests pin the code and message.

## Go Bootstrap Standards

- Use the Go standard library unless a dependency removes substantial, demonstrated complexity.
- Format all Go code with `gofmt`.
- Keep packages small and aligned with compiler phases.
- Never depend on Go map iteration order; sort keys before emitting diagnostics, MIR, or C.
- Avoid reflection in semantic code.
- Include source spans in user-facing errors, but keep verifier errors usable for source-free MIR fixtures.
- Stage 0 exists to bootstrap Alder. Do not turn it into a permanent feature-complete compiler.

## Canonical Checks

Before submitting Go changes, run:

- `gofmt -l .` must print nothing;
- `go vet ./...` must pass;
- `go test ./...` must pass.

Before submitting C runtime changes, additionally run:

- `gcc -std=c11 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -ffp-contract=off -fsyntax-only runtime/c/alder.c` must pass;
- `go test ./runtime -count=1` must pass (strict-warning compile-and-run tests, plus ASan/UBSan runs when the host toolchain supports them);
- `go test ./cgen -count=1` must pass (golden generated-C fixtures, strict-warning compilation of every golden, compile-and-run behavior fixtures, verified-only gate, and cross-process determinism);
- `go test ./frontend -count=1` must pass (pinned printed-MIR goldens, pinned rejection diagnostics, end-to-end source-to-C11 compile-and-run programs, and in-process and cross-process determinism).

Before submitting a compiler-source or source-bootstrap change, additionally
run `bootstrap/regenerate.sh`. It verifies the committed compiler-source
digests and compilation order, builds the committed C bootstrap with the host
shim and runtime, regenerates the compiler without Go or network access, and
requires byte-identical C output. It also requires the common host utilities
listed in `bootstrap/compiler-source-inventory.md`. Use
`bootstrap/regenerate.sh --write` only for an intentional reviewed bootstrap
update; then update the pinned `bootstrap/alder.c` digest in the compiler test.
The measured Linux/GCC run requires about 2.5 GiB of memory. The default run is
cold and hermetic; `ALDER_BOOTSTRAP_CACHE=1` may reuse a previously built
stage-0 binary from the ignored `.alder-cache/` directory and removes no check.

These are the canonical build, format, and test commands; keep them synchronized with `AGENTS.md`.

The `compiler` package tests reuse identical build artifacts across `go test`
processes through a content-hash cache under the user cache directory. Set
`ALDER_TEST_CACHE=0` to disable reuse and rebuild everything. The cache is on
by default, is keyed on the test binary plus the Alder and C sources, the C
compiler and its version, and the exact build flags, and verifies a SHA-256
digest of every artifact before reusing it; any doubt rebuilds. Every assertion
in the affected tests runs on every invocation either way, so the cache changes
how long the gate takes, never what it checks. Entries unused for 14 days are
pruned.

`.github/workflows/ci.yml` runs these checks on pushes to `main` and on pull
requests as five independent jobs: the Go checks, the strict C syntax check,
two compile-only bind-probe lanes, and `bootstrap/regenerate.sh`. The lanes run
`ALDER_BIND_CC=aarch64-linux-gnu-gcc go test ./compiler -run
'^TestAlderBindProbeCrossTarget$' -count=1` and the same test with
`ALDER_BIND_CC=x86_64-w64-mingw32-gcc`; both compile the host-generated
`--emit=bind` unit with the target C compiler. The bootstrap job is gated on
the paths `regenerate.sh` consumes (`bootstrap/`, `compiler/src/`, `runtime/c/`)
because it takes about 3 minutes and up to 3.5 GiB, and it defaults to running
whenever the path comparison cannot be made. Keep the workflow in step with the
commands above.

`./check` runs the same commands in one shot for the inner loop. It is a thin
wrapper with no extra flags: `--bootstrap` adds `bootstrap/regenerate.sh` and
`--no-cache` sets `ALDER_TEST_CACHE=0`. The steps are independent and run
concurrently; each step's output is reported grouped under its own header, in
the fixed order above, after every step has finished, and the exit status
reflects every step. A full run therefore takes about as long as its slowest
step, which is `bootstrap/regenerate.sh` under `--bootstrap`.

## C Runtime and Backend Standards

- Generated and handwritten C must target portable C11.
- Compile cleanly with the project's strict warnings on supported Clang and GCC versions.
- Do not rely on signed overflow, unspecified evaluation order, strict-aliasing violations, invalid pointer arithmetic, or unaligned typed access.
- Use explicit temporaries to sequence side effects.
- Use checked helpers or unsigned operations when implementing defined integer semantics.
- Use `memcpy` for representation-preserving transfers that would otherwise violate aliasing or alignment rules.
- Keep unsafe C interoperability at explicit MIR operations and documented wrapper boundaries.
- Generated names and declaration order must be deterministic.

## Testing Standards

Every semantic change should add the narrowest test that demonstrates it.

Expected test categories:

- parser/printer golden tests for textual MIR;
- verifier acceptance tests;
- verifier rejection tests with stable diagnostics;
- MIR-to-C snapshots where generated structure matters;
- compile-and-run tests for observable behavior;
- sanitizer-backed runtime tests where the host supports them;
- bootstrap stage comparisons once self-hosting begins.

Tests must not depend on:

- host-language map iteration order (Alder 1.0's ordered `Map` contract is a
  separate user-visible guarantee);
- wall-clock timing without a documented tolerance;
- host absolute paths;
- memory addresses;
- network access;
- undeclared environment variables.

## Documentation Standards

- `docs/alder-1.0.md` owns the 1.0 product/release gate.
- `docs/language-design.md` is the user-facing design index.
- `docs/syntax.md` and `docs/language-semantics.md` own source behavior.
- `docs/memory-and-resources.md`, `docs/traits-and-closures.md`, and
  `docs/async.md` own their language safety and concurrency contracts.
- `docs/c-interop.md`, `docs/modules-and-builds.md`, and
  `docs/standard-library.md` own integration and distribution behavior.
- `docs/s0-language.md` owns only the implemented bootstrap subset.
- `docs/mir.md` owns MIR operations and verifier invariants.
- `docs/c-backend.md` owns C lowering and undefined-behavior policy.
- `ROADMAP.md` owns sequencing and scope status.
- `README.md` summarizes and links; it should not become a second full specification.

When documents disagree, treat the conflict as a bug. Do not silently choose whichever behavior is easiest to implement.

## Change Checklist

Before submitting a change:

1. Confirm it is inside the active scope.
2. Update the owning document if semantics changed.
3. Add focused tests when executable code is affected.
4. Run formatters and targeted checks.
5. Confirm generated output is deterministic.
6. Confirm no LLVM dependency or assumption was introduced.
7. State what remains unverified.

## Commit Style

Use short, imperative commit subjects, for example:

```text
Define MIR storage-domain operations
Reject escaping raw references
Lower checked addition to portable C
```

Keep commits reviewable and avoid unrelated refactors.
