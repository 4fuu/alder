module hello.std_io_example

import std.io

// The executable std.io v1 snapshot example. Every stage contributes a
// deterministic share of the returned checksum, so a changed result flags
// changed behavior. The example stays in memory: no file, no host state.

pub fn std_io_example() -> U64 {
    var total: U64 = 0

    // Buffered reads over an in-memory cursor.
    let cursor = io.ByteCursor.new("alpha\nbeta\ngamma")
    var reader = io.BufReader.new(cursor)
    var index: U64 = 0
    var done = false
    while !done {
        match reader.read_until(10) {
            Ok(value) => {
                match value {
                    Some(line) => {
                        index = index + 1
                        var at: U64 = 0
                        while at < line.len() {
                            total = total + line[at].to_u64()
                            at = at + 1
                        }
                        total = total + line.len()
                    }
                    None => { done = true }
                }
            }
            Err(_) => { done = true }
        }
    }
    total = total + index * 100

    // Complete writes through the exact helper into an in-memory sink.
    var sink = io.ByteSink.new()
    let hello: Array(U8, 5) = [104, 101, 108, 108, 111]
    match io.write_all(sink, hello.slice(0, 5)) {
        Ok(count) => { total = total + count }
        Err(_) => {}
    }
    let world: Array(U8, 5) = [119, 111, 114, 108, 100]
    match io.write_all(sink, world.slice(0, 5)) {
        Ok(count) => { total = total + count }
        Err(_) => {}
    }
    let bytes = sink.into_bytes()
    var replay = io.ByteCursor.new(bytes)
    var verify: Array(U8, 10) = [104, 101, 108, 108, 111, 119, 111, 114, 108, 100]
    var at: U64 = 0
    var same = true
    while at < 10 {
        var one: Array(U8, 1) = [0]
        let chunk = io.read_exact(replay, one.slice_mut(0, 1))
        match chunk {
            Ok(_) => {}
            Err(_) => { same = false }
        }
        if one[0] != verify[at] { same = false }
        at = at + 1
    }
    if same { total = total + 10000 }

    return total
}
