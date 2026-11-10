module core.option

// The first `core` sysroot module: the Option(T) helpers that need no OS
// access. The Milestone 8 foundation lands the resolution machinery and these
// two predicates; the remaining documented transforms arrive with the
// core.option public snapshot.

/// Reports whether the option holds a value.
pub fn is_some(T: type, value: Option(T)) -> Bool {
    return match value {
        Some(_) => true
        None => false
    }
}

/// Reports whether the option is empty.
pub fn is_none(T: type, value: Option(T)) -> Bool {
    return match value {
        Some(_) => false
        None => true
    }
}
