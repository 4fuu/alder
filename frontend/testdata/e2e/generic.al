fn identity(T: type, x: T) -> T {
    return x
}

fn swap2(A: type, B: type, a: A, b: B) -> B {
    return b
}

fn first2(A: type, B: type, a: A, b: B) -> A {
    return a
}

fn main() -> I32 {
    if identity(7) != 7 {
        return 1
    }
    let s = identity("abc")
    if identity(I64, 8) != 8 {
        return 3
    }
    if swap2(1, 2) != 2 {
        return 4
    }
    let f = first2("x", 9)
    // Explicit leading type arguments with the rest inferred.
    if swap2(I64, U8, 1, 2) != 2 {
        return 6
    }
    return 0
}
