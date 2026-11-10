module core.option

// The Milestone 8 Option(T) helpers: predicates, transforms, and total
// extraction over the builtin option type. Every operation is explicit about
// emptiness: no helper terminates, fabricates a value, or inspects anything
// but the option itself. All type parameters must be recursively copyable
// values, matching the M7 value model. The fallback argument of `or` and
// `unwrap_or` is evaluated eagerly; pass a closure to `unwrap_or_else` when
// the fallback is expensive to build.

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

/// Applies f to a held value; passes emptiness through unchanged.
pub fn map(T: type, U: type, value: Option(T), f: fn(T) -> U) -> Option(U) {
    return match value {
        Some(inner) => Some(f(inner))
        None => None
    }
}

/// Chains f onto a held value; passes emptiness through unchanged.
pub fn and_then(T: type, U: type, value: Option(T), f: fn(T) -> Option(U)) -> Option(U) {
    return match value {
        Some(inner) => f(inner)
        None => None
    }
}

/// Returns the held option when it holds a value, else the fallback. The
/// fallback argument is evaluated eagerly either way.
pub fn or(T: type, value: Option(T), fallback: Option(T)) -> Option(T) {
    return match value {
        Some(inner) => Some(inner)
        None => fallback
    }
}

/// Returns the held value, else the fallback.
pub fn unwrap_or(T: type, value: Option(T), fallback: T) -> T {
    return match value {
        Some(inner) => inner
        None => fallback
    }
}

/// Returns the held value, else the closure's value.
pub fn unwrap_or_else(T: type, value: Option(T), fallback: fn() -> T) -> T {
    return match value {
        Some(inner) => inner
        None => fallback()
    }
}

/// Converts to Result: a held value becomes Ok, emptiness becomes Err(error).
pub fn ok_or(T: type, E: type, value: Option(T), error: E) -> Result(T, E) {
    return match value {
        Some(inner) => Ok(inner)
        None => Err(error)
    }
}
