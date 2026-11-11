module hello.main

type Boxed(T: type) {
    v: T
}

impl(T: type) Cleanup for Boxed(T) {
    fn cleanup(take self) -> Unit {
        return
    }
}

fn main() -> I32 {
    let b = Boxed(v: 5)
    using held = b
    if held.v != 5 { return 1 }
    return 0
}
