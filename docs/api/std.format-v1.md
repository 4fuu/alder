# `std.format` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot; std.format implemented**

This snapshot is the hosted formatting builder. It composes
[`core.format`](core.format-v1.md) integer/text rules with
[`std.text`](std.text-v1.md) `StringBuilder` and the audited shortest-round-trip
float shim `sysroot/std/c/format_shim.h`. String interpolation is specified in
the language documentation but is not implemented; this module is the explicit
call foundation it will use later.

## Signatures

```alder
module std.format

import core.format as core_format
import std.text { StringBuilder }

pub type Formatter {
    // private: StringBuilder builder
    // private: Option(core_format.FormatError) error
}

impl Formatter {
    fn new() -> Formatter
    fn text(mut self, value: String) -> Unit
    fn display(T: type(Display), mut self, value: T, spec: core_format.FormatSpec) -> Unit
    fn i64(mut self, value: I64, spec: core_format.FormatSpec) -> Unit
    fn u64(mut self, value: U64, spec: core_format.FormatSpec) -> Unit
    fn f32(mut self, value: F32, spec: core_format.FormatSpec) -> Unit
    fn f64(mut self, value: F64, spec: core_format.FormatSpec) -> Unit
    fn finish(self) -> Result(String, core_format.FormatError)
}
```

`Formatter.new()` is empty. Push methods append in call order. The first
formatting error is retained; later pushes do not clear it. `finish` consumes
the builder, discards its text when an error is retained, and otherwise returns
the accumulated `String`. `display` appends `value.display()` and applies the
spec's width, fill, and alignment. Numeric formatting is concrete; user types
extend behavior through their existing `Display` implementation, not a second
formatting trait.

## Float spelling

`f64` and `f32` take the same `FormatSpec`. `Default` and `General` select the
shortest decimal that round-trips: F64 searches precisions 1 through 17, F32
searches 1 through 9, and the shim verifies the candidate by parsing it back
and comparing the bit pattern.

The frozen spelling is C `%.*g`/`%.*e` output under a per-thread C numeric
locale:

- the exponent marker is lowercase `e`, followed by `+` or `-` and at least
  two decimal digits (`1e-300`, `1e+20`, `1.50e+00`);
- the decimal point is `.`, and it appears only when needed (`1`, `0.1`,
  `1.5`);
- `General` never carries an explicit precision; `FormatSpec.precision =
  Some(n)` with `General` is `Unsupported`;
- `Fixed` uses `%.*f` and `Scientific` uses `%.*e`; an absent precision means
  6, and a precision above 64 is `Unsupported`;
- NaN is `nan` for both widths, infinities are `inf` and `-inf`, and negative
  zero keeps its sign (`-0`);
- the shortest candidate must fit the 256-byte shim buffer; overflow is
  `Unsupported`.

The shim temporarily installs a C numeric locale on the calling thread (POSIX
`uselocale`; Windows `_create_locale`/`_snprintf_l`), so an ambient comma
locale cannot change the text. It never calls `setlocale` and never retains
locale state after return.

`alternate` is unsupported for floats. `zero_pad` inserts zeros after the sign
when alignment is right; otherwise `core.format.pad` applies the fill and
width. `Sign.Plus` and `Sign.Space` prefix nonnegative values, including NaN.
The behavior test changes the process to `de_DE.UTF-8` and skips only when the
host cannot create it; CI and `.agents/setup` generate that locale.
Integer kinds (`Decimal`, `HexLower`, `HexUpper`, `Binary`, `Octal`) are
`InvalidKind`; `Default`/`General`/`Fixed`/`Scientific` are the float kinds.

## Contracts

- Every function is total over its type except for the explicit
  `core.format.FormatError` result. Push methods never terminate.
- Width and fill are exactly `core.format`'s: width counts Unicode scalar
  values and fill is one ASCII graphic byte. Hosted float text is ASCII, so
  its width is its byte count.
- The builder is a value type backed by `std.text.StringBuilder`; pushing a
  text value is a value-semantic append. `finish` is ordinary by-value
  consumption, matching `StringBuilder.finish`.
- No public API exposes a host pointer, locale object, or mutable global.
  The audited C shim is the only host boundary.
- Display remains the single user-extensibility point for custom records and
  enums. Floats stay outside the core `Display` domain in v1; `f32`/`f64` are
  the supported float path.

## Example

The complete executable example is
[`examples/std.format-v1.al`](examples/std.format-v1.al), and it returns 1
when its single expected string matches:

```alder
module hello.std_format_example

import core.format as core_format
import std.format as fmt

pub fn std_format_example() -> U64 {
    let plain = core_format.FormatSpec.plain()
    var fixed = core_format.FormatSpec.plain()
    fixed.precision = Some(2)
    fixed.kind = core_format.FormatKind.Fixed

    var f = fmt.Formatter.new()
    f.text("n=")
    f.i64(-7, plain)
    f.text(" f=")
    f.f64(0.1, plain)
    f.text(" g=")
    f.f64(1.5, fixed)
    f.text(" h=")
    f.f32(0.5, plain)

    var result: U64 = 0
    match f.finish() {
        Ok(text) => {
            if text == "n=-7 f=0.1 g=1.50 h=0.5" { result = 1 }
        }
        Err(_) => {}
    }
    return result
}
```

## Dependencies

- `core.format` owns specs, scalar-width padding, and integer rendering.
- `std.text.StringBuilder` owns append storage and final string construction.
- `std/c/format_shim.h` owns float spelling, shortest-round-trip search, and
  per-thread C locale isolation.
