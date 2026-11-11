# Milestone 8 std.io probe projects

Minimal Alder projects that reproduce the bootstrap limitations blocking the
`std.io` v1 pure core and the `std.random` seeded generator, verified against
the bootstrap at `origin/main` 1e66654 (probe binary built from that tree).
Each directory holds a four-line `alder.toml` (`manifest = 1`,
`edition = "1"`, package `hello`, binary target rooted at `src/main.al`) and
the `src/main.al` source, copied here as `main.al`. Rebuild a probe by
restoring `main.al` to `src/main.al` and running the bootstrap `run` command
with `ALDER_SYSROOT` pointing at the sysroot.

## std.io blockers (routed to the language-gaps thread)

- `g2` — field-projection mut-self receiver. `self.inner.read(buffer)` inside
  a concrete impl rejects at the `self.inner` argument:
  `error[SEM0001]: argument does not provide the parameter's required
  exclusive or owning access` (checker 92), exit 1. A whole local binding as
  the receiver argument passes. Full source already delivered to the
  language-gaps thread.
- `g3` — conditional Cleanup impl on a generic type plus a `using`
  registration: `alder: internal compiler failure: lowering model refused`,
  exit 4, with no other content. The non-generic equivalent passes. Note the
  corrected scope: copy-out/copy-back delegation in a generic conditional
  impl lowers fine; this is broader than the original io5 finding and blocks
  every generic type with a conditional Cleanup impl used via `using`
  (BufReader/BufWriter shapes). Full source already delivered to the
  language-gaps thread.
- `io4` — G1: a constrained generic call cannot resolve its constraint
  through a conditional (parameterized) impl; dot-call dispatch and concrete
  impls through generic calls work, and an explicit type argument
  (`Wrapper(Source)` in call type-argument position) also fails.
- `io5` — the original discovery probe combining a conditional Cleanup impl,
  a conditional Reader impl, and a `using` registration; kept for context,
  superseded by `g2`/`g3`.
- `io1`, `io2`, `io3` — positive-control probes for the working shapes the
  std.io design relies on: cross-module traits (io1), `take`/Cleanup/MutSlice
  and indexed writes (io2), Reader shapes with a generic conditional impl
  (io3, compiles and runs).

## std.random blockers (staged on wip/m8-std-random)

- `bitop` — the bitwise operator family is specified but unimplemented: `^`
  and `~` fail in the lexer (`error[LEX0001]: unexpected character`), `&` and
  `|` do not parse as binary operators (`error[SYN0001]: statements must be
  separated by a physical line break` at the operator).
- `rng2` — the std.random Rng module validated with a per-bit arithmetic XOR
  stand-in: seeded draws, unbiased ranges, fill bytes, and value semantics
  all match independently computed SplitMix64 vectors (seeds 42, 5, 7, 99,
  1234).
- `rng3` — a namespace-qualified associated call with an argument
  (`random.Rng.seeded(42)`) rejects with checker diagnostic 41 (argument
  count) even with a fully compiled module; the zero-argument form
  (`bytes.BytesBuilder.new()`) works and braced imports with arguments work
  (`import std.random { Rng }` then `Rng.seeded(42)`).
- `rng1` — the full assertion suite for the staged module (fill assertions
  included), written against the braced-import form.

## S0 surface notes found while writing the module (not defects)

Untyped integer literals default to `I64`, so a leading literal operand
needs reordering (`x + y - x * 2 * y`, not `x + y - 2 * x * y`); hex integer
literals are not implemented (decimal spellings only); `pub` is not accepted
on impl methods (plain `fn`, like every sysroot module); Unit-returning
functions need an explicit `-> Unit`; `while true { ... return ... }` does
not satisfy the must-return exit rule (the `var spinning` pattern does);
MutSlice parameters must be declared `mut` in trait and impl methods.
