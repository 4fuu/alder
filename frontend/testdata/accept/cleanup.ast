import c counter: fn(I64) -> Unit

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
    return attempt(false)
}
