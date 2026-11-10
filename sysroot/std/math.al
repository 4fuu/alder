module std.math

// The Milestone 8 portable scalar float surface (docs/api/std.math-v1.md).
// Math is pure computation: no capability, no host observation, no error
// channel; exceptional inputs follow IEEE semantics per the snapshot.
//
// The libm-backed functions bind the C math functions through the binding
// block below. Classification, magnitude, and sign derive from IEEE
// comparisons and bound copysign, so no C classification macro is bound:
// `is_nan(x)` is `x != x`; `is_infinite(x)` is `x != 0.0 && x * 2.0 == x`;
// `is_finite` is the negation of both; `is_sign_negative(x)` is
// `copysign(1.0, x) < 0.0`, which is signbit-exact including `-0.0`.
// The constants are the nearest literals, not libm calls.
//
// Wrapper bodies land with the checked raw-scalar conversions between
// `F64` and `c.Double` and between `F32` and `c.Float` (C-binding thread,
// C6): binding arguments must have exactly the declared raw type, and
// until the conversions exist this file carries the binding block and the
// pure derived helpers only.

/// The nearest `F64` values to the mathematical constants.
pub fn pi() -> F64 { return 3.141592653589793 }
pub fn e() -> F64 { return 2.718281828459045 }
pub fn sqrt2() -> F64 { return 1.4142135623730951 }

/// The nearest `F32` values to the mathematical constants.
pub fn pi_f32() -> F32 { return 3.14159265 }
pub fn e_f32() -> F32 { return 2.7182818 }
pub fn sqrt2_f32() -> F32 { return 1.4142135 }

import c "math.h" as cmath {
    raw fn sqrt = "sqrt"(x: c.Double) -> c.Double
    raw fn cbrt = "cbrt"(x: c.Double) -> c.Double
    raw fn pow = "pow"(x: c.Double, y: c.Double) -> c.Double
    raw fn exp = "exp"(x: c.Double) -> c.Double
    raw fn log = "log"(x: c.Double) -> c.Double
    raw fn log2 = "log2"(x: c.Double) -> c.Double
    raw fn log10 = "log10"(x: c.Double) -> c.Double
    raw fn hypot = "hypot"(x: c.Double, y: c.Double) -> c.Double
    /// IEEE remainder-style modulo: `x - n*y` with `n` the nearest
    /// integer to `x/y`; `NaN` when `y` is zero.
    raw fn remainder = "remainder"(x: c.Double, y: c.Double) -> c.Double
    raw fn floor = "floor"(x: c.Double) -> c.Double
    raw fn ceil = "ceil"(x: c.Double) -> c.Double
    raw fn trunc = "trunc"(x: c.Double) -> c.Double
    /// Round to nearest, ties away from zero
    /// (IEEE `roundToIntegralTiesToAway`).
    raw fn round = "round"(x: c.Double) -> c.Double
    raw fn fabs = "fabs"(x: c.Double) -> c.Double
    /// IEEE `maxNum`-style: the larger value, `NaN` if either input is
    /// `NaN`.
    raw fn fmax = "fmax"(x: c.Double, y: c.Double) -> c.Double
    /// IEEE `minNum`-style: the smaller value, `NaN` if either input is
    /// `NaN`.
    raw fn fmin = "fmin"(x: c.Double, y: c.Double) -> c.Double
    /// `|x|` with the sign of `y`.
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
