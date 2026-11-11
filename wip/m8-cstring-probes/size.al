import c "cstr.h" as cstr {
    raw fn length = "cstr_length"(text: c.ConstPtr(c.Char)) -> c.Size
}

fn qualify() -> I32 {
    using mode = c.CString("rb")
    let n = unsafe c { cstr.length(mode.ptr()) }
    if n.to_u64() != 2 { return 1 }
    return 0
}

fn main() -> I32 { return qualify() }
