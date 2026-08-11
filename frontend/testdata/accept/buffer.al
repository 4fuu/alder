fn build(d: Domain) -> Result(__s0_Buffer(U64), __s0_Error) {
    var b = try __s0_buffer_new(U64, d)
    b = try __s0_buffer_append(U64, d, b, 10)
    b = try __s0_buffer_append(U64, d, b, 20)
    return Ok(b)
}

fn inspect(b: __s0_Buffer(U64)) -> U64 {
    return __s0_buffer_len(U64, b) + __s0_buffer_get(U64, b, 0) + len(__s0_buffer_slice(U64, b))
}

fn main(d: Domain) -> I32 {
    return 0
}
