# Contributing and Project Standards

Aster is in an early semantic-validation phase. Small, reviewable changes that strengthen the current MIR-to-C path are preferred over broad feature work.

## Language and Communication

- Repository documentation, code comments, diagnostics, and commit messages must be in English.
- Examples should distinguish proposed syntax from implemented behavior.
- Do not describe an unimplemented feature as supported.
- Safety and performance claims require executable evidence.

## Current Scope Boundary

Changes may advance:

- language-memory-model documentation;
- Aster MIR representation, verification, and tests;
- deterministic C11 generation;
- the minimal C runtime required by generated programs;
- bootstrap and self-hosting infrastructure that directly serves those areas.

Do not add:

- LLVM dependencies or an LLVM backend;
- a second native backend;
- a JIT;
- unrelated package-manager, IDE, or macro infrastructure;
- speculative runtime configurability without a current semantic need.

Proposals outside the active scope should update the roadmap or be recorded as a design question rather than partially implemented.

## Architecture Boundaries

The intended compiler layering is:

```text
source frontend -> typed HIR -> Aster MIR -> MIR verifier -> C11 backend
                                             |
                                             +-> C runtime ABI
```

Rules:

- MIR must not depend on C syntax, LLVM concepts, or source AST node shapes.
- Surface generic examples use compile-time `type` parameters and `Name(...)` type application; angle-bracket and square-bracket generic application are not Aster syntax.
- Generic source constructs must be inferred and monomorphized before backend MIR and C lowering.
- The C backend must consume only verified MIR.
- Runtime helpers must have explicit contracts and remain usable from ordinary C11.
- Source locations may be attached for diagnostics, but they must not change semantics or deterministic output.
- Compiler graph structures should prefer stable integer IDs and contiguous storage over pervasive host-language pointers.
- Semantic lowering and behavior changes should be separate from formatting or mechanical cleanup when practical.

## Go Bootstrap Standards

- Use the Go standard library unless a dependency removes substantial, demonstrated complexity.
- Format all Go code with `gofmt`.
- Keep packages small and aligned with compiler phases.
- Never depend on Go map iteration order; sort keys before emitting diagnostics, MIR, or C.
- Avoid reflection in semantic code.
- Include source spans in user-facing errors, but keep verifier errors usable for source-free MIR fixtures.
- Stage 0 exists to bootstrap Aster. Do not turn it into a permanent feature-complete compiler.

## Canonical Checks

Before submitting Go changes, run:

- `gofmt -l .` must print nothing;
- `go vet ./...` must pass;
- `go test ./...` must pass.

These are the canonical build, format, and test commands; keep them synchronized with `AGENTS.md`.

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

- map iteration order;
- wall-clock timing without a documented tolerance;
- host absolute paths;
- memory addresses;
- network access;
- undeclared environment variables.

## Documentation Standards

- `docs/language-design.md` owns user-facing semantic direction.
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
