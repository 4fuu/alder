import c "cstr.h" as cstr {
    raw fn length = "cstr_length"(text: c.ConstPtr(c.Char)) -> c.Size
    raw fn first = "cstr_first_byte"(text: c.ConstPtr(c.Char)) -> c.Size
}

fn open_owned(text: String) -> Option(c.CString) {
    using path = try c.CString(text)
    return Some(path)
}

fn qualify() -> I32 {
    let text = "hel".concat("lo")
    match open_owned(text) {
        Some(held0) => {
            using held = held0
            let n = unsafe c { cstr.length(held.ptr()) }
            let b = unsafe c { cstr.first(held.ptr()) }
            if n.to_u64() != 5 { return 1 }
            if b.to_u64() != 104 { return 2 }
        }
        None => { return 3 }
    }
    return 0
}

fn main() -> I32 { return qualify() }
