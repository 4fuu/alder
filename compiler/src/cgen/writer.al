// Deterministic byte writer for the declaration-only C11 backend lane. Bytes
// are retained until the complete skeleton has passed validation and allocation;
// callers can therefore reject malformed MIR without partial output.

type CgenWriter {
    bytes: __s0_Buffer(U8)
}

fn cgen_writer_new(d: Domain) -> Result(CgenWriter, __s0_Error) {
    let bytes = try __s0_buffer_new(U8, d)
    return Ok(CgenWriter(bytes: bytes))
}

fn cgen_put_byte(d: Domain, writer: CgenWriter, byte: U8) -> Result(CgenWriter, __s0_Error) {
    let bytes = try __s0_buffer_append(U8, d, writer.bytes, byte)
    return Ok(CgenWriter(bytes: bytes))
}

fn cgen_put(d: Domain, writer: CgenWriter, text: String) -> Result(CgenWriter, __s0_Error) {
    var out = writer
    var at: U64 = 0
    while at < len(text) {
        out = try cgen_put_byte(d, out, text[at])
        at = at + 1
    }
    return Ok(out)
}

fn cgen_put_name(d: Domain, writer: CgenWriter, store: MirStore, start: U64, end: U64) -> Result(CgenWriter, __s0_Error) {
    var out = writer
    var at = start
    while at < end {
        out = try cgen_put_byte(d, out, __s0_buffer_get(U8, store.names, at))
        at = at + 1
    }
    return Ok(out)
}

fn cgen_put_name_fragment(d: Domain, writer: CgenWriter, store: MirStore, start: U64, end: U64) -> Result(CgenWriter, __s0_Error) {
    var out = writer
    var at = start
    while at < end {
        let byte = __s0_buffer_get(U8, store.names, at)
        if mir_ident_continue(byte) { out = try cgen_put_byte(d, out, byte) } else { out = try cgen_put_byte(d, out, 95) }
        at = at + 1
    }
    return Ok(out)
}

fn cgen_put_digit(d: Domain, writer: CgenWriter, value: U64) -> Result(CgenWriter, __s0_Error) {
    if value == 0 { return cgen_put_byte(d, writer, 48) }
    if value == 1 { return cgen_put_byte(d, writer, 49) }
    if value == 2 { return cgen_put_byte(d, writer, 50) }
    if value == 3 { return cgen_put_byte(d, writer, 51) }
    if value == 4 { return cgen_put_byte(d, writer, 52) }
    if value == 5 { return cgen_put_byte(d, writer, 53) }
    if value == 6 { return cgen_put_byte(d, writer, 54) }
    if value == 7 { return cgen_put_byte(d, writer, 55) }
    if value == 8 { return cgen_put_byte(d, writer, 56) }
    return cgen_put_byte(d, writer, 57)
}

fn cgen_put_u64(d: Domain, writer: CgenWriter, value: U64) -> Result(CgenWriter, __s0_Error) {
    var out = writer
    if value >= 10 { out = try cgen_put_u64(d, out, value / 10) }
    return cgen_put_digit(d, out, value % 10)
}

fn cgen_put_i64_digits(d: Domain, writer: CgenWriter, value: I64) -> Result(CgenWriter, __s0_Error) {
    var out = writer
    if value >= 10 { out = try cgen_put_i64_digits(d, out, value / 10) }
    let digit = value % 10
    if digit == 0 { return cgen_put_byte(d, out, 48) }
    if digit == 1 { return cgen_put_byte(d, out, 49) }
    if digit == 2 { return cgen_put_byte(d, out, 50) }
    if digit == 3 { return cgen_put_byte(d, out, 51) }
    if digit == 4 { return cgen_put_byte(d, out, 52) }
    if digit == 5 { return cgen_put_byte(d, out, 53) }
    if digit == 6 { return cgen_put_byte(d, out, 54) }
    if digit == 7 { return cgen_put_byte(d, out, 55) }
    if digit == 8 { return cgen_put_byte(d, out, 56) }
    return cgen_put_byte(d, out, 57)
}

fn cgen_put_i64(d: Domain, writer: CgenWriter, value: I64) -> Result(CgenWriter, __s0_Error) {
    if value == -9223372036854775808 { return cgen_put(d, writer, "(-9223372036854775807LL - 1)") }
    var out = writer
    var magnitude = value
    if value < 0 {
        out = try cgen_put_byte(d, out, 45)
        magnitude = -value
    }
    return cgen_put_i64_digits(d, out, magnitude)
}

fn cgen_put_octal_digit(d: Domain, writer: CgenWriter, value: U8) -> Result(CgenWriter, __s0_Error) {
    if value == 0 { return cgen_put_byte(d, writer, 48) }
    if value == 1 { return cgen_put_byte(d, writer, 49) }
    if value == 2 { return cgen_put_byte(d, writer, 50) }
    if value == 3 { return cgen_put_byte(d, writer, 51) }
    if value == 4 { return cgen_put_byte(d, writer, 52) }
    if value == 5 { return cgen_put_byte(d, writer, 53) }
    if value == 6 { return cgen_put_byte(d, writer, 54) }
    return cgen_put_byte(d, writer, 55)
}

fn cgen_put_c_bytes(d: Domain, writer: CgenWriter, bytes: __s0_Buffer(U8), start: U64, end: U64) -> Result(CgenWriter, __s0_Error) {
    var out = writer
    var at = start
    while at < end {
        let byte = __s0_buffer_get(U8, bytes, at)
        var escaped = false
        if byte == 34 { out = try cgen_put(d, out, "\\\"")
        escaped = true }
        if byte == 92 { out = try cgen_put(d, out, "\\\\")
        escaped = true }
        if byte == 10 { out = try cgen_put(d, out, "\\n")
        escaped = true }
        if byte == 9 { out = try cgen_put(d, out, "\\t")
        escaped = true }
        if byte == 13 { out = try cgen_put(d, out, "\\r")
        escaped = true }
        if !escaped && byte >= 32 && byte < 127 { out = try cgen_put_byte(d, out, byte)
        escaped = true }
        if !escaped {
            out = try cgen_put_byte(d, out, 92)
            out = try cgen_put_octal_digit(d, out, byte / 64)
            out = try cgen_put_octal_digit(d, out, byte / 8 % 8)
            out = try cgen_put_octal_digit(d, out, byte % 8)
        }
        at = at + 1
    }
    return Ok(out)
}

fn cgen_flush(writer: CgenWriter) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(U8, writer.bytes) {
        if !out(__s0_buffer_get(U8, writer.bytes, at)) { return false }
        at = at + 1
    }
    return true
}
