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
    return 0
}

fn identity(T: type, x: T) -> T {
    return x
}
