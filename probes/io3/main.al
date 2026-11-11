module hello.main

import hello.io3 { Reader, Source, Wrapper, drain_bytes, IoError }

fn main() -> I32 {
    var s = Source(data: [7, 8, 9], at: 0)
    var buf: Array(U8, 4) = [0, 0, 0, 0]
    var wrote: U64 = 0
    {
        var view: MutSlice(U8) = buf.slice_mut(0, 4)
        wrote = drain_bytes(Source, s, view)
    }
    if wrote != 3 { return 1 }
    if buf[0] != 7 { return 2 }
    if buf[2] != 9 { return 3 }
    let counted = match s.count(2) {
        Ok(n) => n
        Err(_) => 99
    }
    if counted != 0 { return 4 }
    var w = Wrapper(inner: Source(data: [1, 2, 3], at: 0))
    var wrote2: U64 = 0
    {
        var view: MutSlice(U8) = buf.slice_mut(0, 4)
        wrote2 = drain_bytes(Wrapper(Source), w, view)
    }
    if wrote2 != 3 { return 5 }
    if buf[0] != 1 { return 6 }
    let none: IoError = IoError.NotFound
    if none != IoError.NotFound { return 7 }
    return 0
}
