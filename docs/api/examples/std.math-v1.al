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
    // The tolerance constant spells the exact decimal digits of its `F32`
    // value, as every F32 literal must.
    let diff = math.abs_f32(x - y)
    return diff < 9.9999997473787516e-05
}
