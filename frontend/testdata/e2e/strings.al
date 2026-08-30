fn string_identity(s: String) -> String {
    return s
}

fn bytes_identity(b: Bytes) -> Bytes {
    return b
}

fn main() -> I32 {
    let text: String = "hello"
    let raw: Bytes = "\x00\x80\xff"
    let empty_text: String = ""
    let empty_raw: Bytes = ""
    let text_copy = string_identity(text)
    let raw_copy = bytes_identity(raw)
    let generic_text = identity(text_copy)
    let generic_raw = identity(raw_copy)
    let generic_empty_text = identity(empty_text)
    let generic_empty_raw = identity(empty_raw)

    let text_view = text.as_bytes()
    let raw_view = raw.as_slice()
    if text_view[1] != 101 || raw_view[2] != 255 { return 1 }

    var values: Vec(U8) = Vec.new(U8)
    let pushed = values.try_push(65)
    let built: Bytes = match Bytes.try_from_vec(values) {
        Ok(value) => value
        Err(error) => ""
    }
    values[0] = 66
    let built_view = built.as_slice()
    if built_view[0] != 65 || values[0] != 66 { return 2 }
    return 0
}

fn identity(T: type, x: T) -> T {
    return x
}
