fn count_bytes(s: String) -> U64 {
    var n: U64 = 0
    for c in s {
        if c == 0 {
            return n
        }
        n = n + 1
    }
    return n
}

fn main() -> I32 {
    let s = "hello"
    if len(s) != 5 {
        return 1
    }
    if s[1] != 101 {
        return 2
    }
    var sum: U64 = 0
    for c in s {
        sum = sum + 1
        if c < 97 {
            return 3
        }
    }
    if sum != 5 {
        return 4
    }
    let tail = range(s, 1, 3)
    if len(tail) != 2 {
        return 5
    }
    if tail[0] != 101 {
        return 6
    }
    let nul = "a\0b"
    if len(nul) != 3 {
        return 7
    }
    if count_bytes(nul) != 1 {
        return 8
    }
    let empty = ""
    if len(empty) != 0 {
        return 9
    }
    // String values flow through generic functions.
    let e2 = identity(empty)
    if len(e2) != 0 {
        return 10
    }
    return 0
}

fn identity(T: type, x: T) -> T {
    return x
}
