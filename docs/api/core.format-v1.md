# `core.format` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; core.format implemented**

This snapshot is the pure-Alder formatting contract. `core.format` never
observes the host and never allocates outside the ordinary `String`/`Vec`
value domain. It owns format specifications, scalar-width padding, and integer
rendering. Hosted float rendering and the `StringBuilder`-backed convenience
layer are in [`std.format`](std.format-v1.md).

String interpolation is specified in the language documentation (an
interpolated string evaluates each `{...}` expression through `Display` in
source order) but is not implemented in this series. This module is the
explicit-call foundation it will use later.

## Signatures

```alder
module core.format

pub enum Align {
    Left
    Right
    Center
}

pub enum Sign {
    Auto
    Plus
    Space
}

pub enum FormatKind {
    Default
    Decimal
    HexLower
    HexUpper
    Binary
    Octal
    General
    Fixed
    Scientific
}

pub type FormatSpec {
    pub width: U64
    pub fill: U8
    pub align: Align
    pub sign: Sign
    pub alternate: Bool
    pub zero_pad: Bool
    pub precision: Option(U64)
    pub kind: FormatKind
}

pub enum FormatError {
    InvalidFill
    InvalidKind
    Unsupported
}

impl FormatSpec {
    fn plain() -> FormatSpec
}

pub fn pad(text: String, spec: FormatSpec) -> Result(String, FormatError)
pub fn format_i64(value: I64, spec: FormatSpec) -> Result(String, FormatError)
pub fn format_u64(value: U64, spec: FormatSpec) -> Result(String, FormatError)
```

## Contracts

- `FormatSpec.plain()` is width 0, fill `0x20`, right alignment, `Sign.Auto`,
  no alternate form, no zero padding, no precision, and `FormatKind.Default`.
- `width` counts Unicode scalar values, not bytes. A UTF-8 sequence contributes
  one unit for its leading byte and zero for continuation bytes
  (`0b10xxxxxx`). Padding therefore aligns non-ASCII text without importing
  `std.text`.
- `fill` is exactly one ASCII graphic byte, `0x20` through `0x7e`. Any other
  value returns `FormatError.InvalidFill`. The odd column of a centered gap
  goes on the right.
- Integer renderers accept `Default`, `Decimal`, `HexLower`, `HexUpper`,
  `Binary`, and `Octal`. `alternate` adds `0x`, `0X`, `0b`, or `0o` for the
  non-decimal bases. `Sign.Plus` and `Sign.Space` affect nonnegative values;
  negative values always keep `-`. Zero padding is inserted after the sign and
  alternate prefix.
- `FormatKind.General`, `Fixed`, and `Scientific` return
  `FormatError.InvalidKind` from the integer renderers. A present `precision`
  returns `FormatError.Unsupported` there. Float kinds are consumed by
  `std.format`, never by this module.
- `format_i64(I64.min, spec)` renders `-9223372036854775808` without signed
  overflow. The magnitude is computed in the two's-complement `U64` domain.
- `pad` pads any already-formatted text to `spec.width` scalar values and does
  not inspect `spec.kind`. `format_*` uses `pad` after assembling the sign and
  body unless zero padding applies.
- Every function is total over its type except for the three explicit error
  variants. No capability is taken and no host locale, environment, or OS API
  is observed.

## Integer examples

With the plain spec, `format_i64(-42, spec)` is `-42`. With `kind =
HexLower`, `alternate = true`, `format_u64(255, spec)` is `0xff`. With `width
= 5`, `zero_pad = true`, `sign = Plus`, `format_i64(42, spec)` is `+0042`.
`pad("é", spec)` with width 3, fill `.`, and center alignment is `.é.`.

## Dependencies

- Uses only builtin `String`, `Bytes`, `Vec`, `Option`, and primitive integer
  operations. No sysroot module dependency and no C binding.
- Integer parsing foundations live in [`core.num`](core.num-v1.md); float
  shortest-round-trip formatting lives in [`std.format`](std.format-v1.md).
