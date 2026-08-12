# Compiler Source Inventory v1

This document defines the canonical compiler-source inventory prepared for the
M5.5 source-bootstrap handoff. The inventory verifier is available now as
`bootstrap/inventory_verify.c`; this preparation does not activate or complete
M5.5 and makes no self-hosting claim.

No production `bootstrap/compiler-sources.manifest` is committed yet. The M5.4
handoff generates that file and its digests only when the production compiler
source set is frozen. Until then, the explicit source lists in the M5.4
conformance harnesses remain authoritative.

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
to be invoked directly by the later M5.5 regeneration harness.
