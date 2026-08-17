# Compiler Source Inventory v1

This document defines the canonical compiler-source inventory used by the M5.5
source bootstrap. `bootstrap/compiler-sources.manifest` commits the byte length
and SHA-256 digest of every compiler input, while
`bootstrap/compiler-sources.order` commits their compilation order. The
standalone verifier is `bootstrap/inventory_verify.c`.

## Byte format

An inventory is an ASCII, line-oriented byte sequence:

```text
ALDER-COMPILER-SOURCES 1
<length> <source-sha256> <path>
...
sha256 <manifest-sha256>
```

Every line, including the final line, ends with one LF byte. CRLF is not
canonical. Fields have exactly one ASCII space between them and no leading or
trailing whitespace.

- `length` is the source's byte length in canonical unsigned decimal: `0`, or
  a nonzero digit followed by zero or more digits. It must fit in `uint64_t`.
- `source-sha256` is exactly 64 lowercase hexadecimal digits: the SHA-256 of
  the source's unmodified bytes. Source contents may contain arbitrary bytes.
- `path` is relative to the supplied source root and uses `/` separators. Each
  nonempty component contains only ASCII letters, digits, `.`, `_`, or `-` and
  is neither `.` nor `..`. Thus absolute paths, empty components, backslashes,
  drive prefixes, whitespace, and traversal components are noncanonical.
- Entry lines are in strictly increasing lexicographic order by path bytes.
  Every path therefore occurs exactly once.
- `manifest-sha256` is exactly 64 lowercase hexadecimal digits: the SHA-256 of
  every manifest byte before the final `sha256` line, including the LF after
  the header and after each entry. This rule also covers an empty inventory.

SHA-256 supplies deterministic integrity and provenance evidence here; it is
not a claim of cryptographic authenticity. Authenticity depends on how the
source archive and expected inventory are distributed and trusted.

## Verifier contract

Build the verifier as strict portable C11 and invoke it with an explicitly
selected manifest and root:

```text
alder-inventory-verify MANIFEST ROOT
```

The verifier reads only paths listed in the manifest and never walks the root.
It validates the canonical manifest, its whole-manifest digest, and each listed
file's presence, byte length, and digest. Diagnostics name only canonical
inventory paths, not host-dependent manifest or root paths. Exit status is `0`
for a valid inventory, `1` for invalid or unreadable input, and `2` for invalid
command usage.

`alder-inventory-verify --self-test` checks the embedded byte-oriented SHA-256
against the published empty-string, `abc`, and 448-bit multi-block FIPS 180
test vectors. The implementation has no third-party dependency and is intended
to be invoked directly by the M5.5 regeneration harness.

## Source-bootstrap regeneration

From the repository root, verify that the committed compiler is its own
regeneration result with:

```sh
bootstrap/regenerate.sh
```

The script validates the source inventory, checks that the order file names
every inventoried source exactly once, builds `bootstrap/alder.c` with the host
shim and C runtime, and asks that compiler to regenerate itself. It exits
successfully only when the regenerated C is byte-identical to the committed
artifact. `bootstrap/regenerate.sh --write` replaces the artifact and is
reserved for an intentional bootstrap update after reviewing the resulting
diff and updating its pinned test digest.

Regeneration requires a POSIX shell, a C11 compiler, and common host utilities
(`awk`, `cmp`, `dirname`, `mktemp`, `mv`, `rm`, and `uname`). It does not invoke
Go, access the network, scan for source files, or require an installed Alder
compiler. `CC` must name one executable; set it, `BOOTSTRAP_CFLAGS`, or
`BOOTSTRAP_LDFLAGS` only when the host toolchain requires an override. The
measured Linux/GCC fixed-point run peaks near 2.5 GiB of memory; the Linux host
shim raises the compiler process's stack soft limit to 64 MiB when the
committed compiler is built by this harness.
