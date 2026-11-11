fn accept(flag: Bool, value: Unit) -> I32 {
    if flag { return 0 }
    return 1
}

fn nothing() -> Unit {
    return ()
}

fn is_ok(value: Result(Unit, I32)) -> Bool {
    return match value {
        Ok(_) => true
        Err(_) => false
    }
}

fn is_some(value: Option(Unit)) -> Bool {
    return match value {
        Some(_) => true
        None => false
    }
}

fn main() -> I32 {
    let ok: Result(Unit, I32) = Ok(())
    if !is_ok(ok) { return 1 }
    let some: Option(Unit) = Some(())
    if !is_some(some) { return 2 }
    if accept(true, ()) != 0 { return 3 }
    nothing()
    return 0
}
