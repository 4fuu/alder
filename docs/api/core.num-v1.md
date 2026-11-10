# `core.num` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for the integer foundation helpers in
the installed sysroot. It is normative together with the executable example in
[`examples/core.num-v1.al`](examples/core.num-v1.al). The module lives at
`<sysroot>/core/num.al`; how the driver finds the sysroot and records it in
the build plan is defined in
[Modules and Builds](../modules-and-builds.md#installed-sysroot).

## Signatures

```alder
module core.num

pub fn i8_min() -> I8
pub fn i8_max() -> I8
pub fn i16_min() -> I16
pub fn i16_max() -> I16
pub fn i32_min() -> I32
pub fn i32_max() -> I32
pub fn i64_min() -> I64
pub fn i64_max() -> I64

pub fn u8_max() -> U8
pub fn u16_max() -> U16
pub fn u32_max() -> U32
pub fn u64_max() -> U64

pub fn i8_abs_checked(value: I8) -> Option(I8)
pub fn i16_abs_checked(value: I16) -> Option(I16)
pub fn i32_abs_checked(value: I32) -> Option(I32)
pub fn i64_abs_checked(value: I64) -> Option(I64)

pub fn i8_abs_wrapping(value: I8) -> I8
pub fn i16_abs_wrapping(value: I16) -> I16
pub fn i32_abs_wrapping(value: I32) -> I32
pub fn i64_abs_wrapping(value: I64) -> I64
```

## Contracts

- Every limit function returns the exact boundary of its type. The unsigned
  minima are the literal `0` and have no function.
- Overflow behavior is explicit in the name, matching the builtin method
  surface: `*_checked` yields `None` instead of overflowing, `*_wrapping`
  wraps on the two's-complement pattern. No helper terminates.
- `i64_abs_checked` yields `None` exactly for `i64_min()`, whose negation has
  no positive representative; `i64_abs_wrapping` of `i64_min()` is
  `i64_min()` itself. The same holds per width for the other signed types.
- Helpers are deterministic pure functions of their arguments: same argument
  values, same result, no hidden state, no OS access.
- These are plain leading-type-parameter-free functions; the integer types are
  concrete prelude names.

## Integer conversion methods (builtin surface)

Version 1 of this module ships together with the builtin integer conversion
methods on every integer type receiver. They are prelude method names, not
library functions, and are normative for `core.num` consumers:

- `value.to_T()` exists exactly for widening pairs — every receiver value
  fits `T` — and is total. Widening pairs are pairs where `T` is wider and
  either the receiver is unsigned or both types are signed.
- `value.to_T_checked()` and `value.to_T_wrapping()` exist for every other
  pair. The checked form yields `Some` when the receiver value fits `T` and
  `None` otherwise; the wrapping form truncates to the target width on the
  two's-complement pattern.
- A call whose pair is neither of these shapes is rejected at compile time:
  the lossy bare form names the `_checked` form, identity conversions are
  rejected as having no effect, and the checked or wrapping form on a
  widening pair is rejected as unnecessary (checker diagnostics 251, 252,
  and 253).

The executable example pins representative boundaries: `255.to_i64()`, the
`128.to_i8_checked()`/`to_i8_wrapping()` split at the `I8` edge, the `-1`
wrapping round trips from signed to unsigned, `2^63` at the
`U64`/`I64` edge, and the `I64`/`I32` boundary in both forms.

## Later snapshots

- Checked division and remainder pairs, saturating division, and the
  min/max/clamp family arrive with the `Order`-constrained generic snapshot.
- The parse and format foundations need the `String` and `Bytes` byte
  surface; they land with the text modules.

The checked, saturating, and wrapping arithmetic methods themselves
(`add_checked`, `sub_checked`, `mul_checked`, and friends) are builtin
prelude names, not library functions; this module only adds what the
builtins cannot spell.
