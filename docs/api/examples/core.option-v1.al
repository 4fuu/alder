module hello.option_example

import core.option

// The executable core.option v1 snapshot example. Every helper in the
// snapshot contributes a deterministic share of the returned checksum, so a
// changed result flags changed behavior.

pub fn option_example() -> I64 {
    var total: I64 = 0

    let present: Option(I64) = Some(21)
    let empty: Option(I64) = None

    if option.is_some(present) { total = total + 1 }
    if option.is_none(empty) { total = total + 2 }

    let doubled: Option(I64) = option.map(I64, I64, present, fn(v: I64) => v * 2)
    let mapped_empty: Option(I64) = option.map(I64, I64, empty, fn(v: I64) => v * 2)
    if option.is_none(mapped_empty) { total = total + 4 }

    let chain_step: fn(I64) -> Option(I64) = fn(v: I64) -> Option(I64) {
        return Some(v / 4)
    }
    let chained: Option(I64) = option.and_then(I64, I64, doubled, chain_step)
    total = total + option.unwrap_or(I64, chained, 1000)

    let rescued: Option(I64) = option.or(I64, empty, Some(7))
    total = total + option.unwrap_or(I64, rescued, 1000)

    total = total + option.unwrap_or(I64, present, 1000)
    total = total + option.unwrap_or(I64, empty, 100)
    let late: fn() -> I64 = fn() -> I64 { return 5 }
    total = total + option.unwrap_or_else(I64, empty, late)

    match option.ok_or(I64, I64, empty, 99) {
        Ok(v) => { total = total + v }
        Err(code) => { total = total + code }
    }
    match option.ok_or(I64, I64, present, 99) {
        Ok(v) => { total = total + v }
        Err(code) => { total = total + code }
    }

    return total
}
