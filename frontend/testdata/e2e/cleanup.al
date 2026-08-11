import c counter: fn(I64) -> Unit
import c read_counter: fn() -> I64

fn close(x: I64) -> Unit {
    unsafe c { counter(x) }
}

fn attempt(bad: Bool) -> I32 {
    using h = 5 with close
    if bad {
        return 7
    }
    return 0
}

fn main() -> I32 {
    if attempt(false) != 0 {
        return 1
    }
    if unsafe c { read_counter() } != 5 {
        return 2
    }
    if attempt(true) != 7 {
        return 3
    }
    if unsafe c { read_counter() } != 10 {
        return 4
    }
    return 0
}
