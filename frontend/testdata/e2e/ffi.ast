import c magic: fn(U64) -> U64
import c store: fn(I64) -> Unit
import c load: fn() -> I64

fn main() -> I32 {
    let v = unsafe c { magic(40) }
    if v != 42 {
        return 1
    }
    unsafe c { store(123) }
    if unsafe c { load() } != 123 {
        return 2
    }
    return 0
}
