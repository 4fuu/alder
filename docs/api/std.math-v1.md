# `std.math` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for scalar math. It is normative
together with the executable example
[`examples/std.math-v1.al`](examples/std.math-v1.al), which lands in the
module's implementation commit: the docs example runner resolves sysroot
modules, so the example file cannot precede the module it imports. The module
lives at `<sysroot>/std/math.al`.

Snapshot v1 covers the portable scalar float surface: constants,
classification, magnitude and sign, rounding, and the libm-backed
transcendental and root functions, in `F64` and `F32`. Math is pure
computation: it never observes the host, so no function takes a capability.
Exceptional inputs follow IEEE semantics and are documented per function;
there is no error channel.

## Signatures

### Constants

```alder
module std.math

pub fn pi() -> F64
pub fn e() -> F64
pub fn sqrt2() -> F64
pub fn pi_f32() -> F32
pub fn e_f32() -> F32
pub fn sqrt2_f32() -> F32
```

Constants are nullary functions returning fixed values (the nearest `F64`/
`F32` to the mathematical constants) rather than global values, so they stay
inside the ordinary function-call evaluation model of this milestone.

### Classification, magnitude, and sign

```alder
pub fn is_nan(x: F64) -> Bool
pub fn is_infinite(x: F64) -> Bool
pub fn is_finite(x: F64) -> Bool
pub fn is_sign_negative(x: F64) -> Bool
pub fn is_sign_positive(x: F64) -> Bool

pub fn abs(x: F64) -> F64
/// The larger value; `NaN` if either input is `NaN`.
pub fn max(x: F64, y: F64) -> F64
/// The smaller value; `NaN` if either input is `NaN`.
pub fn min(x: F64, y: F64) -> F64
/// `|x|` with the sign of `y`.
pub fn copysign(x: F64, y: F64) -> F64

pub fn is_nan_f32(x: F32) -> Bool
pub fn is_infinite_f32(x: F32) -> Bool
pub fn is_finite_f32(x: F32) -> Bool
pub fn is_sign_negative_f32(x: F32) -> Bool
pub fn is_sign_positive_f32(x: F32) -> Bool
pub fn abs_f32(x: F32) -> F32
pub fn max_f32(x: F32, y: F32) -> F32
pub fn min_f32(x: F32, y: F32) -> F32
pub fn copysign_f32(x: F32, y: F32) -> F32
```

### Rounding

```alder
/// Round toward negative infinity.
pub fn floor(x: F64) -> F64
/// Round toward positive infinity.
pub fn ceil(x: F64) -> F64
/// Round toward zero.
pub fn trunc(x: F64) -> F64
/// Round to nearest, ties away from zero (IEEE `roundToIntegralTiesToAway`).
pub fn round(x: F64) -> F64

pub fn floor_f32(x: F32) -> F32
pub fn ceil_f32(x: F32) -> F32
pub fn trunc_f32(x: F32) -> F32
pub fn round_f32(x: F32) -> F32
```

### Roots, powers, and exponentials (libm-backed)

```alder
/// Square root; `NaN` for negative inputs (including negative zero).
pub fn sqrt(x: F64) -> F64
/// Cube root; defined for all finite inputs, sign-preserving.
pub fn cbrt(x: F64) -> F64
/// `x` raised to `y`, IEEE `pow` exceptional results (for example
/// `pow(0.0, -1.0)` is infinity, `pow(-1.0, infinity)` is 1.0).
pub fn pow(x: F64, y: F64) -> F64
/// Natural exponential.
pub fn exp(x: F64) -> F64
/// Natural logarithm; `NaN` for negative inputs, negative infinity at
/// positive zero.
pub fn ln(x: F64) -> F64
/// Base-2 logarithm, same exceptional shape as `ln`.
pub fn log2(x: F64) -> F64
/// Base-10 logarithm, same exceptional shape as `ln`.
pub fn log10(x: F64) -> F64
/// `sqrt(x*x + y*y)` without spurious overflow or underflow.
pub fn hypot(x: F64, y: F64) -> F64
/// IEEE remainder-style modulo: `x - n*y` with `n` the nearest integer
/// to `x/y`; `NaN` when `y` is zero.
pub fn modulo(x: F64, y: F64) -> F64

pub fn sqrt_f32(x: F32) -> F32
pub fn cbrt_f32(x: F32) -> F32
pub fn pow_f32(x: F32, y: F32) -> F32
pub fn exp_f32(x: F32) -> F32
pub fn ln_f32(x: F32) -> F32
pub fn log2_f32(x: F32) -> F32
pub fn log10_f32(x: F32) -> F32
pub fn hypot_f32(x: F32, y: F32) -> F32
pub fn modulo_f32(x: F32, y: F32) -> F32
```

### Trigonometry (libm-backed)

```alder
pub fn sin(x: F64) -> F64
pub fn cos(x: F64) -> F64
pub fn tan(x: F64) -> F64
/// Arc sine of `x`; `NaN` outside `-1.0 .. 1.0`.
pub fn asin(x: F64) -> F64
/// Arc cosine of `x`; `NaN` outside `-1.0 .. 1.0`.
pub fn acos(x: F64) -> F64
/// Arc tangent in `-pi/2 .. pi/2`.
pub fn atan(x: F64) -> F64
/// Arc tangent of `y/x` using the signs to pick the quadrant; zero when
/// both inputs are zero.
pub fn atan2(y: F64, x: F64) -> F64
/// Hyperbolic sine and friends with IEEE exceptional results.
pub fn sinh(x: F64) -> F64
pub fn cosh(x: F64) -> F64
pub fn tanh(x: F64) -> F64

pub fn sin_f32(x: F32) -> F32
pub fn cos_f32(x: F32) -> F32
pub fn tan_f32(x: F32) -> F32
pub fn asin_f32(x: F32) -> F32
pub fn acos_f32(x: F32) -> F32
pub fn atan_f32(x: F32) -> F32
pub fn atan2_f32(y: F32, x: F32) -> F32
pub fn sinh_f32(x: F32) -> F32
pub fn cosh_f32(x: F32) -> F32
pub fn tanh_f32(x: F32) -> F32
```

## Contracts

- Every function is pure: no capability, no host observation, no global
  state, same result for the same inputs on the same target build.
- All functions follow IEEE 754 with round-to-nearest-even. The wrappers
  never change the C rounding mode; an ambient foreign change to the
  rounding environment is outside this contract and cannot redefine Alder
  numeric semantics. Documented exceptional inputs return the documented
  IEEE values (`NaN`, infinities) and never trap.
- The `F64` names are the primary surface; `F32` mirrors carry the `_f32`
  suffix. A generic float-width layer waits for a float trait and is out of
  v1 (recorded in the gap audit).
- `max`/`min` propagate `NaN` (IEEE `maxNum`-style is deliberately not used:
  a silent fallback would hide a failed computation). `abs`, `copysign`,
  `floor`, `ceil`, `trunc`, and `round` preserve `NaN` and infinities.
- Results are deterministic per build; the libm implementation is part of
  the sysroot build, so cross-version drift is a build change, not hidden
  behavior.
- Tests compare exact values only where IEEE and libm make them exact
  (`sqrt(4.0)`, rounding, `abs`), and compare transcendentals within fixed
  tolerances, never by bit pattern across libm versions.

## Example

The example below is the complete content that lands as
`examples/std.math-v1.al` with the implementation commit. Exact IEEE cases
and fixed tolerances make the checksum deterministic.

```alder
module hello.std_math_example

import std.math

// The executable std.math v1 snapshot example. Exact IEEE cases and fixed
// tolerances only; no host observation anywhere.

fn near(x: F64, y: F64) -> Bool {
    let diff = math.abs(x - y)
    return diff < 0.000000001
}

pub fn std_math_example() -> I64 {
    var total: I64 = 0

    // Exact rounding and magnitude cases.
    let four: F64 = 4.0
    if math.sqrt(four) == 2.0 { total = total + 1 }
    if math.floor(2.5) == 2.0 { total = total + 1 }
    if math.ceil(2.5) == 3.0 { total = total + 1 }
    if math.trunc(-2.5) == -2.0 { total = total + 1 }
    if math.round(2.5) == 3.0 { total = total + 1 }
    if math.abs(-7.25) == 7.25 { total = total + 10 }
    if math.max(1.5, 2.5) == 2.5 { total = total + 1 }
    if math.min(1.5, 2.5) == 1.5 { total = total + 1 }
    if math.copysign(3.0, -1.0) == -3.0 { total = total + 1 }

    // Classification.
    let broken = math.sqrt(-1.0)
    if math.is_nan(broken) { total = total + 100 }
    if math.is_finite(1.0) { total = total + 1 }
    if math.is_sign_negative(-0.0) { total = total + 1 }

    // Transcendentals within fixed tolerances.
    if math.hypot(3.0, 4.0) == 5.0 { total = total + 1000 }
    if near(math.pow(2.0, 10.0), 1024.0) { total = total + 1 }
    if near(math.exp(0.0), 1.0) { total = total + 1 }
    if near(math.ln(math.e()), 1.0) { total = total + 1 }
    if near(math.atan2(1.0, 1.0), math.pi() / 4.0) { total = total + 1 }
    if near(math.sin(0.0), 0.0) { total = total + 1 }
    if near(math.cos(0.0), 1.0) { total = total + 1 }
    if near(math.tanh(0.0), 0.0) { total = total + 1 }

    // F32 mirror.
    let wide: F32 = 4.0
    if math.sqrt_f32(wide) == 2.0 { total = total + 10000 }
    if near_f32(math.abs_f32(-1.5), 1.5) { total = total + 1 }

    return total
}

fn near_f32(x: F32, y: F32) -> Bool {
    let diff = math.abs_f32(x - y)
    return diff < 0.0001
}
```

## Dependencies and sequencing

- Needs the C-binding thread's binding blocks and `unsafe c` calls for the
  libm functions (`sqrt`, `pow`, `exp`, `log`, `sin`, and siblings) plus the
  checked raw-integer conversions used inside float classification.
- Needs no sysroot text or numeric-conversion surface: the example compares
  floats and adds integers only.
- A generic float-width trait (`T: type(Float)`) waits for that trait's
  design; v1 ships the two spelled widths.
