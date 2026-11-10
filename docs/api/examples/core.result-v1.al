module hello.result_example

import core.result

// The executable core.result v1 snapshot example. Every helper in the
// snapshot contributes a deterministic share of the returned checksum, so a
// changed result flags changed behavior.

pub fn result_example() -> I64 {
    var total: I64 = 0

    let good: Result(I64, String) = Ok(30)
    let bad: Result(I64, String) = Err("rejected")

    if result.is_ok(good) { total = total + 1 }
    if result.is_err(bad) { total = total + 2 }

    let mapped: Result(I64, String) = result.map(I64, I64, String, good, fn(v: I64) => v + 12)
    match mapped {
        Ok(v) => { if v == 42 { total = total + 4 } }
        Err(_) => { total = total + 1000 }
    }

    let mapped_bad: Result(I64, String) = result.map(I64, I64, String, bad, fn(v: I64) => v + 12)
    if result.is_err(mapped_bad) { total = total + 8 }

    let explain: fn(String) -> I64 = fn(code: String) -> I64 { return 7 }
    let explained: Result(I64, I64) = result.map_err(I64, String, I64, bad, explain)
    match explained {
        Ok(v) => { total = total + v }
        Err(code) => { total = total + code }
    }

    let keep_large: fn(I64) -> Result(I64, String) = fn(v: I64) -> Result(I64, String) {
        if v > 40 { return Ok(v) }
        return Err("too small")
    }
    let chained: Result(I64, String) = result.and_then(I64, I64, String, mapped, keep_large)
    match chained {
        Ok(v) => { total = total + v }
        Err(_) => { total = total + 1000 }
    }

    match result.ok(I64, String, mapped) {
        Some(v) => { if v == 42 { total = total + 16 } }
        None => { total = total + 1000 }
    }
    match result.err(I64, String, good) {
        Some(_) => { total = total + 1000 }
        None => { total = total + 32 }
    }
    match result.err(I64, String, bad) {
        Some(_) => { total = total + 64 }
        None => { total = total + 1000 }
    }

    total = total + result.unwrap_or(I64, String, bad, 50)

    return total
}
