# wip/m8-cstring-probes

Repro and probe sources for the unfinished `c.CString` slice (branch
`wip/m8-cstring`). These live in the repository only because the working
orb is not handed over; they are not part of the build or test gates.

## What works (verified on this branch)

`size.al` — the literal form `using mode = c.CString("rb")`, `.ptr()`
borrow, exactly-once release, end to end:

    # Build a probe compiler from the resealed bootstrap:
    gcc -O2 -std=c11 -I runtime/c -o /tmp/alderc \
      bootstrap/alder.c bootstrap/alder_host.c runtime/c/alder.c -lm
    /tmp/alderc compile -o /tmp/size.c wip/m8-cstring-probes/size.al
    gcc -O2 -std=c11 -I runtime/c -I bootstrap -I wip/m8-cstring-probes \
      -o /tmp/size-run /tmp/size.c wip/m8-cstring-probes/cstr.c \
      wip/m8-cstring-probes/driver.c runtime/c/alder.c -lm
    /tmp/size-run
    # expect: rc=0 live_before=0 live_after=0

`try1.al` — the `try`/`Option` form now passes the checker and all ten
MIR verification phases (three lowering bugs were fixed on this branch:
stale block metadata in the kind-10 using statement after a
block-switching init expression, a unit-payload binding on the Option
`none` switch case, and `lower_mir_type_copy_relocatable` not rejecting
the five C kinds the way the phase-10 forbidden-copy list does). Note:
the merge onto main renumbered `str.display` from op 98 to 102; the
c-string ops are 98-101.

## Known defect (blocks landing on main)

Transferring a using-scoped `c.CString` out of its scope does not
disarm the cleanup registration. In `try1.al`, `open_owned` ends with
`return Some(path)` inside `using path = try c.CString(text)`; the
lowered ok-path builds `Some`, then runs `alder_cleanup_run`, which
frees the buffer before the caller receives it. ASan on the generated
program reports heap-use-after-free in `cstr_length` (freed by
`alder_cleanup_run`), and `qualify()` later releases the same buffer a
second time. Root cause direction: the disarm is emitted by
`lower_binding_expression` only when the checker spells the read as a
kind-22 move; the rewrite to kind 22 fires for `let` bindings and
`__s0` builtin calls (checker.al `check_s0_runtime_args`, identity 7)
but apparently not for a using-scoped binding read inside a
user-spelled enum variant constructor, so the disarm never fires.
Expected behavior: the move out of a using scope emits
`cleanup_disarm` on every transfer path (a plain `return path` probe
should be checked too).

Reproduce:

    # debug build with VERIFY-FAIL/table dumps (patches compiler copies in
    # .alder-dbg/, self-compiles, then runs the probe):
    bash wip/m8-cstring-probes/mkdbg.sh   # edit WORKTREE path at top first
    cd /tmp/alderc/cstr
    /tmp/alderc/alderc-dbg2 check try1.al          # verifies today
    /tmp/alderc/alderc-dbg2 compile -o try1.c try1.al
    gcc -O2 -std=c11 -fsanitize=address -I runtime/c -I bootstrap \
      -I . -o try1-asan try1.c cstr.c driver.c runtime/c/alder.c -lm
    ./try1-asan                                     # ASan UAF as above

`mkdbg.sh` is the debug harness: it copies `compiler/src` into
`.alder-dbg/`, patches in a lower model dump, a verify-failure dump of
the full MIR store (functions, params, types, instructions with
block/ordinal, values with block/item), and a MIR print on refusal,
then self-compiles with the newest cached stage-0. The absolute worktree
path and the probe directory paths inside are orb-specific; adjust
before running.

## Still needed before this can land

1. Fix the disarm defect above; add a compiler run-fixture test that
   transfers a using-scoped c_string through `Some` and through a plain
   return (exactly-once release asserted via
   `alder_runtime_live_allocations`, pattern:
   `compiler/production_c_record_test.go`).
2. Checker rejection tests: literal with interior NUL (checker 210),
   wrong argument count (211), non-String argument (212).
3. Production test for the `try` form including the runtime
   interior-NUL `String` -> `None` path (build the String via concat
   with an embedded NUL byte).
4. Docs: `docs/c-interop.md` (CString section),
   `docs/mir.md` (ops 98-101 and the str.display renumber to 102),
   `docs/c-backend.md` (cstring runtime helpers),
   `docs/s0-language.md` (try-over-Option in using), `ROADMAP.md` M8.
5. Cold `bootstrap/regenerate.sh` cost measurement vs the parent commit
   (parent 9c941f8 baseline: 116.4 s wall, ~2.00 GB peak RSS).
