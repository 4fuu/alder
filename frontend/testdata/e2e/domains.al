fn fill(d: Domain, n: U64) -> I64 {
    let buf = __s0_alloc(I64, d, n)
    var i: U64 = 0
    while i < n {
        buf[i] = 3
        i = i + 1
    }
    return buf[0]
}

fn roundtrip(d: Domain, n: U64) -> U64 {
    let buf = __s0_alloc(U64, d, n)
    var i: U64 = 0
    while i < n {
        buf[i] = i
        i = i + 1
    }
    // Reset releases the storage; a fresh allocation reuses the domain.
    // The mark must be the direct domain.mark result.
    __s0_domain_reset(d, __s0_domain_mark(d))
    let buf2 = __s0_alloc(U64, d, 2)
    buf2[0] = 42
    buf2[1] = 7
    return buf2[0] + buf2[1]
}

fn main(d: Domain) -> I32 {
    let child = __s0_domain_create(d)
    if fill(child, 4) != 3 {
        __s0_domain_destroy(child)
        return 1
    }
    if roundtrip(child, 5) != 49 {
        __s0_domain_destroy(child)
        return 2
    }
    __s0_domain_destroy(child)
    return 0
}
