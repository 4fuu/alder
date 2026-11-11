fn main() -> I32 {
    let a: U32 = 12
    let b: U32 = 10
    if a & b != 8 { return 1 }
    if a | b != 14 { return 2 }
    if a ^ b != 6 { return 3 }
    let zero: U32 = 0
    if ~zero != 4294967295 { return 4 }
    if ~a != 4294967283 { return 5 }

    let s: I8 = -2
    if ~s != 1 { return 6 }
    let m: I8 = -1
    if m & 15 != 15 { return 7 }
    if m | 0 != -1 { return 8 }
    if m ^ m != 0 { return 9 }

    let big: U64 = 1099511627776
    let one64: U64 = 1
    if big & 255 != 0 { return 10 }
    if (big >> 40) != one64 { return 11 }
    if (one64 << 40) != big { return 12 }

    // Precedence, tightest first: shift, bitwise-and, xor, or.
    let one: U32 = 1
    let two: U32 = 2
    let three: U32 = 3
    let four: U32 = 4
    let precedence = one | two ^ three & four << 1
    if precedence != 3 { return 13 }

    // Binary operators associate left: (1 | 2) | 4.
    let low: U8 = 1
    let pair = low | 2
    let triple = pair | 4
    if triple != 7 { return 14 }

    let truth: Bool = a > b && (a & 4) == 4
    if !truth { return 15 }
    return 0
}
