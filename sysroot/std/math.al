module std.math

// The Milestone 8 portable scalar float surface (docs/api/std.math-v1.md).
// Math is pure computation: no capability, no host observation, no error
// channel; exceptional inputs follow IEEE semantics per the snapshot.
//
// The libm-backed functions bind the C math functions through the binding
// block below and wrap each call with the checked raw-scalar conversions
// between `F64` and `c.Double` and between `F32` and `c.Float`. Every
// wrapper observes its result only through the value-preserving total
// conversions; classification (`is_nan`, `is_infinite`, `is_finite`, and
// the sign tests) derives from IEEE comparisons and arithmetic on the
// converted values. The constants are the nearest literals; the `F32`
// spellings carry their exact decimal digits, which F32 literals require.

/// The nearest `F64` values to the mathematical constants.
pub fn pi() -> F64 { return 3.141592653589793 }
pub fn e() -> F64 { return 2.718281828459045 }
pub fn sqrt2() -> F64 { return 1.4142135623730951 }

/// The exact `F32` values nearest the mathematical constants, spelled with
/// their exact decimal digits: an F32 literal must be exactly representable in
/// binary32, so the decimal text names the stored value directly.
pub fn pi_f32() -> F32 { return 3.1415927410125732 }
pub fn e_f32() -> F32 { return 2.7182817459106445 }
pub fn sqrt2_f32() -> F32 { return 1.4142135381698608 }

/// `true` exactly when `x` is a NaN of either sign.
pub fn is_nan(x: F64) -> Bool { return x != x }

/// `true` for either infinity; `false` for NaN and every finite value.
/// An infinite `x` is the only nonzero value whose self-difference differs
/// from zero, and the final comparison excludes NaN.
pub fn is_infinite(x: F64) -> Bool {
    return x != 0.0 && x - x != 0.0 && x == x
}

/// `true` for every finite value, including zero; `false` for NaN and
/// infinities. NaN fails the self-comparison and an infinity fails the
/// self-difference.
pub fn is_finite(x: F64) -> Bool {
    return x == x && x - x == 0.0
}

/// `true` when `x` carries the negative sign bit, including negative zero
/// and a NaN with a negative sign bit.
pub fn is_sign_negative(x: F64) -> Bool {
    let probe = copysign(1.0, x)
    return probe < 0.0
}

/// `true` when `x` carries the positive sign bit, including positive zero
/// and a NaN with a positive sign bit.
pub fn is_sign_positive(x: F64) -> Bool {
    let probe = copysign(1.0, x)
    return probe > 0.0
}

/// `true` exactly when `x` is a NaN of either sign.
pub fn is_nan_f32(x: F32) -> Bool { return x != x }

/// `true` for either infinity; `false` for NaN and every finite value.
pub fn is_infinite_f32(x: F32) -> Bool {
    return x != 0.0 && x - x != 0.0 && x == x
}

/// `true` for every finite value, including zero; `false` for NaN and
/// infinities.
pub fn is_finite_f32(x: F32) -> Bool {
    return x == x && x - x == 0.0
}

/// `true` when `x` carries the negative sign bit, including negative zero
/// and a NaN with a negative sign bit.
pub fn is_sign_negative_f32(x: F32) -> Bool {
    let probe = copysign_f32(1.0, x)
    return probe < 0.0
}

/// `true` when `x` carries the positive sign bit, including positive zero
/// and a NaN with a positive sign bit.
pub fn is_sign_positive_f32(x: F32) -> Bool {
    let probe = copysign_f32(1.0, x)
    return probe > 0.0
}

pub fn sqrt(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.sqrt(raw) }
    return done.to_f64()
}

pub fn cbrt(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.cbrt(raw) }
    return done.to_f64()
}

pub fn pow(x: F64, y: F64) -> F64 {
    let left = x.to_c_double()
    let right = y.to_c_double()
    let done = unsafe c { cmath.pow(left, right) }
    return done.to_f64()
}

pub fn exp(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.exp(raw) }
    return done.to_f64()
}

pub fn ln(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.log(raw) }
    return done.to_f64()
}

pub fn log2(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.log2(raw) }
    return done.to_f64()
}

pub fn log10(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.log10(raw) }
    return done.to_f64()
}

pub fn hypot(x: F64, y: F64) -> F64 {
    let left = x.to_c_double()
    let right = y.to_c_double()
    let done = unsafe c { cmath.hypot(left, right) }
    return done.to_f64()
}

/// IEEE remainder-style modulo: `x - n*y` with `n` the nearest
/// integer to `x/y`; `NaN` when `y` is zero.
pub fn modulo(x: F64, y: F64) -> F64 {
    let left = x.to_c_double()
    let right = y.to_c_double()
    let done = unsafe c { cmath.remainder(left, right) }
    return done.to_f64()
}

pub fn floor(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.floor(raw) }
    return done.to_f64()
}

pub fn ceil(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.ceil(raw) }
    return done.to_f64()
}

pub fn trunc(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.trunc(raw) }
    return done.to_f64()
}

/// Round to nearest, ties away from zero
/// (IEEE `roundToIntegralTiesToAway`).
pub fn round(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.round(raw) }
    return done.to_f64()
}

pub fn abs(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.fabs(raw) }
    return done.to_f64()
}

/// The larger value; `NaN` if either input is `NaN`.
pub fn max(x: F64, y: F64) -> F64 {
    let left = x.to_c_double()
    let right = y.to_c_double()
    let done = unsafe c { cmath.fmax(left, right) }
    return done.to_f64()
}

/// The smaller value; `NaN` if either input is `NaN`.
pub fn min(x: F64, y: F64) -> F64 {
    let left = x.to_c_double()
    let right = y.to_c_double()
    let done = unsafe c { cmath.fmin(left, right) }
    return done.to_f64()
}

/// `|x|` with the sign of `y`.
pub fn copysign(x: F64, y: F64) -> F64 {
    let magnitude = x.to_c_double()
    let sign = y.to_c_double()
    let done = unsafe c { cmath.copysign(magnitude, sign) }
    return done.to_f64()
}

pub fn sin(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.sin(raw) }
    return done.to_f64()
}

pub fn cos(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.cos(raw) }
    return done.to_f64()
}

pub fn tan(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.tan(raw) }
    return done.to_f64()
}

pub fn asin(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.asin(raw) }
    return done.to_f64()
}

pub fn acos(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.acos(raw) }
    return done.to_f64()
}

pub fn atan(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.atan(raw) }
    return done.to_f64()
}

/// Arc tangent of `y/x` using the signs to pick the quadrant; zero when
/// both inputs are zero.
pub fn atan2(y: F64, x: F64) -> F64 {
    let rise = y.to_c_double()
    let run = x.to_c_double()
    let done = unsafe c { cmath.atan2(rise, run) }
    return done.to_f64()
}

pub fn sinh(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.sinh(raw) }
    return done.to_f64()
}

pub fn cosh(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.cosh(raw) }
    return done.to_f64()
}

pub fn tanh(x: F64) -> F64 {
    let raw = x.to_c_double()
    let done = unsafe c { cmath.tanh(raw) }
    return done.to_f64()
}

pub fn sqrt_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.sqrt_f32(raw) }
    return done.to_f32()
}

pub fn cbrt_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.cbrt_f32(raw) }
    return done.to_f32()
}

pub fn pow_f32(x: F32, y: F32) -> F32 {
    let left = x.to_c_float()
    let right = y.to_c_float()
    let done = unsafe c { cmath.pow_f32(left, right) }
    return done.to_f32()
}

pub fn exp_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.exp_f32(raw) }
    return done.to_f32()
}

pub fn ln_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.log_f32(raw) }
    return done.to_f32()
}

pub fn log2_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.log2_f32(raw) }
    return done.to_f32()
}

pub fn log10_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.log10_f32(raw) }
    return done.to_f32()
}

pub fn hypot_f32(x: F32, y: F32) -> F32 {
    let left = x.to_c_float()
    let right = y.to_c_float()
    let done = unsafe c { cmath.hypot_f32(left, right) }
    return done.to_f32()
}

pub fn modulo_f32(x: F32, y: F32) -> F32 {
    let left = x.to_c_float()
    let right = y.to_c_float()
    let done = unsafe c { cmath.remainder_f32(left, right) }
    return done.to_f32()
}

pub fn floor_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.floor_f32(raw) }
    return done.to_f32()
}

pub fn ceil_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.ceil_f32(raw) }
    return done.to_f32()
}

pub fn trunc_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.trunc_f32(raw) }
    return done.to_f32()
}

pub fn round_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.round_f32(raw) }
    return done.to_f32()
}

pub fn abs_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.fabs_f32(raw) }
    return done.to_f32()
}

pub fn max_f32(x: F32, y: F32) -> F32 {
    let left = x.to_c_float()
    let right = y.to_c_float()
    let done = unsafe c { cmath.fmax_f32(left, right) }
    return done.to_f32()
}

pub fn min_f32(x: F32, y: F32) -> F32 {
    let left = x.to_c_float()
    let right = y.to_c_float()
    let done = unsafe c { cmath.fmin_f32(left, right) }
    return done.to_f32()
}

pub fn copysign_f32(x: F32, y: F32) -> F32 {
    let magnitude = x.to_c_float()
    let sign = y.to_c_float()
    let done = unsafe c { cmath.copysign_f32(magnitude, sign) }
    return done.to_f32()
}

pub fn sin_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.sin_f32(raw) }
    return done.to_f32()
}

pub fn cos_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.cos_f32(raw) }
    return done.to_f32()
}

pub fn tan_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.tan_f32(raw) }
    return done.to_f32()
}

pub fn asin_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.asin_f32(raw) }
    return done.to_f32()
}

pub fn acos_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.acos_f32(raw) }
    return done.to_f32()
}

pub fn atan_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.atan_f32(raw) }
    return done.to_f32()
}

pub fn atan2_f32(y: F32, x: F32) -> F32 {
    let rise = y.to_c_float()
    let run = x.to_c_float()
    let done = unsafe c { cmath.atan2_f32(rise, run) }
    return done.to_f32()
}

pub fn sinh_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.sinh_f32(raw) }
    return done.to_f32()
}

pub fn cosh_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.cosh_f32(raw) }
    return done.to_f32()
}

pub fn tanh_f32(x: F32) -> F32 {
    let raw = x.to_c_float()
    let done = unsafe c { cmath.tanh_f32(raw) }
    return done.to_f32()
}

import c "math.h" as cmath {
    raw fn sqrt = "sqrt"(x: c.Double) -> c.Double
    raw fn cbrt = "cbrt"(x: c.Double) -> c.Double
    raw fn pow = "pow"(x: c.Double, y: c.Double) -> c.Double
    raw fn exp = "exp"(x: c.Double) -> c.Double
    raw fn log = "log"(x: c.Double) -> c.Double
    raw fn log2 = "log2"(x: c.Double) -> c.Double
    raw fn log10 = "log10"(x: c.Double) -> c.Double
    raw fn hypot = "hypot"(x: c.Double, y: c.Double) -> c.Double
    raw fn remainder = "remainder"(x: c.Double, y: c.Double) -> c.Double
    raw fn floor = "floor"(x: c.Double) -> c.Double
    raw fn ceil = "ceil"(x: c.Double) -> c.Double
    raw fn trunc = "trunc"(x: c.Double) -> c.Double
    raw fn round = "round"(x: c.Double) -> c.Double
    raw fn fabs = "fabs"(x: c.Double) -> c.Double
    raw fn fmax = "fmax"(x: c.Double, y: c.Double) -> c.Double
    raw fn fmin = "fmin"(x: c.Double, y: c.Double) -> c.Double
    raw fn copysign = "copysign"(x: c.Double, y: c.Double) -> c.Double
    raw fn sin = "sin"(x: c.Double) -> c.Double
    raw fn cos = "cos"(x: c.Double) -> c.Double
    raw fn tan = "tan"(x: c.Double) -> c.Double
    raw fn asin = "asin"(x: c.Double) -> c.Double
    raw fn acos = "acos"(x: c.Double) -> c.Double
    raw fn atan = "atan"(x: c.Double) -> c.Double
    raw fn atan2 = "atan2"(y: c.Double, x: c.Double) -> c.Double
    raw fn sinh = "sinh"(x: c.Double) -> c.Double
    raw fn cosh = "cosh"(x: c.Double) -> c.Double
    raw fn tanh = "tanh"(x: c.Double) -> c.Double

    raw fn sqrt_f32 = "sqrtf"(x: c.Float) -> c.Float
    raw fn cbrt_f32 = "cbrtf"(x: c.Float) -> c.Float
    raw fn pow_f32 = "powf"(x: c.Float, y: c.Float) -> c.Float
    raw fn exp_f32 = "expf"(x: c.Float) -> c.Float
    raw fn log_f32 = "logf"(x: c.Float) -> c.Float
    raw fn log2_f32 = "log2f"(x: c.Float) -> c.Float
    raw fn log10_f32 = "log10f"(x: c.Float) -> c.Float
    raw fn hypot_f32 = "hypotf"(x: c.Float, y: c.Float) -> c.Float
    raw fn remainder_f32 = "remainderf"(x: c.Float, y: c.Float) -> c.Float
    raw fn floor_f32 = "floorf"(x: c.Float) -> c.Float
    raw fn ceil_f32 = "ceilf"(x: c.Float) -> c.Float
    raw fn trunc_f32 = "truncf"(x: c.Float) -> c.Float
    raw fn round_f32 = "roundf"(x: c.Float) -> c.Float
    raw fn fabs_f32 = "fabsf"(x: c.Float) -> c.Float
    raw fn fmax_f32 = "fmaxf"(x: c.Float, y: c.Float) -> c.Float
    raw fn fmin_f32 = "fminf"(x: c.Float, y: c.Float) -> c.Float
    raw fn copysign_f32 = "copysignf"(x: c.Float, y: c.Float) -> c.Float
    raw fn sin_f32 = "sinf"(x: c.Float) -> c.Float
    raw fn cos_f32 = "cosf"(x: c.Float) -> c.Float
    raw fn tan_f32 = "tanf"(x: c.Float) -> c.Float
    raw fn asin_f32 = "asinf"(x: c.Float) -> c.Float
    raw fn acos_f32 = "acosf"(x: c.Float) -> c.Float
    raw fn atan_f32 = "atanf"(x: c.Float) -> c.Float
    raw fn atan2_f32 = "atan2f"(y: c.Float, x: c.Float) -> c.Float
    raw fn sinh_f32 = "sinhf"(x: c.Float) -> c.Float
    raw fn cosh_f32 = "coshf"(x: c.Float) -> c.Float
    raw fn tanh_f32 = "tanhf"(x: c.Float) -> c.Float
}
