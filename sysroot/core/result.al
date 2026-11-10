module core.result

// The Milestone 8 Result(T, E) helpers: predicates, transforms, projections,
// and total extraction over the builtin result type. Every operation is
// explicit about which side it touches: no helper terminates, fabricates a
// value, or inspects anything but the result itself. All type parameters must
// be recursively copyable values, matching the M7 value model.

/// Reports whether the result holds a success value.
pub fn is_ok(T: type, E: type, value: Result(T, E)) -> Bool {
    return match value {
        Ok(_) => true
        Err(_) => false
    }
}

/// Reports whether the result holds an error value.
pub fn is_err(T: type, E: type, value: Result(T, E)) -> Bool {
    return match value {
        Ok(_) => false
        Err(_) => true
    }
}

/// Applies f to a success value; passes an error through unchanged.
pub fn map(T: type, U: type, E: type, value: Result(T, E), f: fn(T) -> U) -> Result(U, E) {
    return match value {
        Ok(inner) => Ok(f(inner))
        Err(error) => Err(error)
    }
}

/// Applies f to an error value; passes a success through unchanged.
pub fn map_err(T: type, E: type, F: type, value: Result(T, E), f: fn(E) -> F) -> Result(T, F) {
    return match value {
        Ok(inner) => Ok(inner)
        Err(error) => Err(f(error))
    }
}

/// Chains f onto a success value; passes an error through unchanged.
pub fn and_then(T: type, U: type, E: type, value: Result(T, E), f: fn(T) -> Result(U, E)) -> Result(U, E) {
    return match value {
        Ok(inner) => f(inner)
        Err(error) => Err(error)
    }
}

/// Projects a success into Some; an error becomes None.
pub fn ok(T: type, E: type, value: Result(T, E)) -> Option(T) {
    return match value {
        Ok(inner) => Some(inner)
        Err(_) => None
    }
}

/// Projects an error into Some; a success becomes None.
pub fn err(T: type, E: type, value: Result(T, E)) -> Option(E) {
    return match value {
        Ok(_) => None
        Err(error) => Some(error)
    }
}

/// Returns the success value, else the fallback.
pub fn unwrap_or(T: type, E: type, value: Result(T, E), fallback: T) -> T {
    return match value {
        Ok(inner) => inner
        Err(_) => fallback
    }
}
