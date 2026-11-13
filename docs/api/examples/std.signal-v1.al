module hello.std_signal_example

import std.io { Blocking }
import std.signal

// The executable std.signal v1 example. The zero timeout is a deterministic
// poll with no signal pending, so the expected result is None.
pub fn std_signal_example() -> U64 {
    let io = Blocking()
    let result = match signal.wait(io, signal.Signal.Terminate, 0) {
        Ok(value) => value
        Err(_) => return 0
    }
    match result {
        None => { return 1 }
        Some(_) => { return 0 }
    }
    return 0
}
