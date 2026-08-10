# Aster Repository Guidance

## Project Status

Aster is in the design and bootstrap phase. Do not claim that a compiler, runtime, or language feature is usable unless executable code and tests demonstrate it.

## Active Scope

Current implementation work is limited to:

- Aster MIR representation, textual format, verification, and tests;
- deterministic lowering from verified MIR to conservative C11;
- the minimal C runtime required by that lowering;
- design and bootstrap infrastructure directly supporting those goals.

LLVM is explicitly out of scope. Do not add LLVM dependencies, bindings, build flags, IR concepts, or a placeholder backend without a new approved project decision.

## Documentation Ownership

- `docs/language-design.md`: user-facing language semantics and open questions.
- `docs/mir.md`: MIR operations and verifier invariants.
- `docs/c-backend.md`: C lowering and undefined-behavior policy.
- `ROADMAP.md`: current milestones and deferred work.
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

Orb lifecycle scripts (`.agents/setup`, `.agents/resume`) are used only in the Amp environment and are not part of the normal build process. They must remain non-interactive and idempotent. `.agents/setup` installs missing prerequisites; `.agents/resume` only performs fast checks and must not install dependencies.
