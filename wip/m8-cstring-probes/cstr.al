import c "cstr.h" as cstr {
    raw fn length = "cstr_length"(text: c.ConstPtr(c.Char)) -> c.Size
    raw fn first_byte = "cstr_first_byte"(text: c.ConstPtr(c.Char)) -> c.Size
}

fn lit_qualify() -> I32 {
    using mode = c.CString("rb")
    let n = unsafe c { cstr.length(mode.ptr()) }
    let b = unsafe c { cstr.first_byte(mode.ptr()) }
    match n.to_i64_checked() {
        Some(v) => {
            if v != 2 { return 1 }
            match b.to_i64_checked() {
                Some(w) => {
                    if w != 114 { return 2 }
                    return 0
                }
                None => { return 3 }
            }
        }
        None => { return 4 }
    }
}

fn probe(s: String) -> Option(c.CString) {
    let owner = try c.CString(s)
    return Some(owner)
}

fn probe_none() -> I32 {
    let interior = "a".concat("\0b")
    match probe(interior) {
        Some(owner) => { return 1 }
        None => { return 0 }
    }
}

fn try_some() -> I32 {
    using owner = try c.CString("hello")
    let n = unsafe c { cstr.length(owner.ptr()) }
    let b = unsafe c { cstr.first_byte(owner.ptr()) }
    match n.to_i64_checked() {
        Some(v) => {
            if v != 5 { return 1 }
            match b.to_i64_checked() {
                Some(w) => {
                    if w != 104 { return 2 }
                    return 0
                }
                None => { return 3 }
            }
        }
        None => { return 4 }
    }
}

fn main() -> I32 {
    let a = lit_qualify()
    if a != 0 { return a }
    let b = probe_none()
    if b != 0 { return 10 + b }
    let c = try_some()
    if c != 0 { return 20 + c }
    return 0
}
