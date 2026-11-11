# WIP M8 std.io language/checker repros

Two verified minimal repros for std.io blockers, reported by the standard-library
thread against origin/main at `1e66654` (verified independently in this thread's
orb). This branch parks them so the repros survive the orb; it is not meant to
merge as-is. Nothing here is referenced by the build or tests.

## G3: conditional Cleanup impl + `using` refuses to lower (bug, take first)

Directory: `g3-conditional-cleanup-using/` (project: `alder.toml`, `src/main.al`).

Behavior on `1e66654`:

    $ alder1 run
    alder: internal compiler failure: lowering model refused
    exit 4

Scope correction to the earlier report: the copy-out/copy-back idiom
(`var local = self.inner; ...; self.inner = local`) is NOT the trigger. A
generic conditional impl with copy-out/copy-back lowers fine on current main.
The actual trigger is a conditional (parameterized) Cleanup impl on a generic
type plus a `using` registration of an instance. Verified variants: the same
shape with a non-generic type and a plain `impl Cleanup for Boxed` passes
(exit 0); the generic conditional Cleanup alone with `using` refuses — no
Reader impl, no delegation, no second impl needed. Any generic type with a
conditional Cleanup impl registered via `using` refuses to lower;
BufReader/BufWriter need exactly that shape.

Investigation state (this orb, unreached by the eventual fixer):

- The failure site is `lower_checked` -> `lower_model_valid` in
  `compiler/src/lower.al` (`LowerModelBad` is turned into the exit-4 message by
  `finish_lower` in `compiler/src/main.al`, `LowerModelBad` enumerated at
  `compiler/src/lower.al` ~line 184).
- `lower_model_valid` (~line 7063) is a large structural invariant walk with
  ~254 early `return false` sites; which invariant the generic-conditional
  Cleanup case breaks was not yet identified. The interrupted approach was
  temporary instrumentation: wrap each `return false` in the function with a
  numbered fail helper that prints the site (via `out_string`/`out_u64` from
  `compiler/src/output.al`), rebuild the probe, rerun the repro, read the
  number. Never commit that instrumentation.
- The Go `frontend` mirror (`frontend/lower.go`) has no model-validity gate, so
  it cannot localize the failure; the gate exists only in the self-hosted
  pipeline.
- Cleanup-registration invariants the gate checks near its end: exactly one
  cleanup-owning statement (kind 10) per block, `activation_count == 1`, and
  exactly one `CheckedCleanupRec` per (owner, environment, binding) triple.
  Duplicate registration for one binding under a conditional impl is a
  plausible first suspect, unverified.

Planned fix: make the lowering model accept the generic conditional Cleanup
registration (or, if the model is right, turn the case into a designed checker
rejection), per `docs/memory-and-resources.md`. Fixture: the repro as a
compile-and-run acceptance test once fixed.

## G2: field-projection mut-self receiver argument rejects with diagnostic 92

Directory: `g2-field-mut-receiver/` (project: `alder.toml`, `src/main.al`).

Behavior on `1e66654`:

    $ alder1 run
    src/main.al:39:20: error[SEM0001]: argument does not provide the parameter's required exclusive or owning access
    exit 1

Line 39 col 20 is the `self.inner` argument of the delegated call
`return self.inner.read(buffer)` inside `impl Reader for Wrapper`: a mut-self
receiver argument must currently be a whole local binding; a field projection
of `mut self` is rejected.

The docs support the qualified form: `docs/memory-and-resources.md` (~line 103)
says views form from places including field paths of a binding, and
`docs/s0-language.md` (~line 622) notes mutating collection operations already
work through fields of a `mut self` receiver. So this is a fix, not a
rejection: extend the mut-argument gate to accept field/index projections over
a mutable root, lowering to the field's storage address (no copy, no
write-back for plain `mut`).

Investigation state:

- The gate is `check_call_argument_mode` in `compiler/src/checker.al`
  (~line 5665): parameter node kind 47 = mut, 48 = take; the argument
  expression must be `CheckedExprRec` kind 1 (local read) or 5 (parameter
  read); forwarding a whole mut/take parameter works; a field read of `self`
  is rejected at the kind check. Diagnostic 92 also fires at lexical-access
  conflict sites ~7302/~8174/~9165 (different paths).
- `check_place_level` (~line 9625) already accepts field projections over a
  mutable root (`self` in a mut self method is the mutable root), producing
  `CheckedPlaceRec` chains; `expression_root_binding` resolves the root for
  view liveness.
- The lowerer already handles field receiver paths: `lower_receiver_place`
  (`compiler/src/lower.al` ~line 5018, "a `mut self` receiver and a field of a
  local both store") and read_receiver logic ~5535. How a mut argument lowers
  when the checked form is a field place was NOT yet determined; that is the
  next investigation step after extending the checker gate.
- Fixture: the repro as a compile-and-run acceptance test (BufReader-style
  delegation must produce exit 0; the included main asserts the three copied
  bytes).

## Probe mechanics

The manifest file is `alder.toml` (the std-library thread's message said
`manifest.toml`; that name is wrong for the driver). Both projects use:

    manifest = 1
    edition = "1"
    [package]
    name = "hello"
    version = "0.1.0"
    [targets.hello]
    kind = "bin"
    root = "src/main.al"

Rebuild a probe binary from a modified tree and run a project:

    go test ./compiler -run TestProductionSysrootNamespaceRuns -count=1
    NEWEST=$(ls -t "$HOME/.cache/alder/go-test/"*/*/alder1 | head -1)
    cd probes/wip-m8-io/g3-conditional-cleanup-using
    ALDER_SYSROOT=<repo>/sysroot TMPDIR=$PWD/tmp "$NEWEST" run
