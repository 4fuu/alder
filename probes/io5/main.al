module hello.main

import hello.io5 { Reader, Writer, Source, Sink, Buffered, relay, outer_len }

fn main() -> I32 {
    var s = Source(data: [1, 2, 3], at: 0)
    var sink = Sink(kept: Vec.new(U8))
    let total = match s.count_two() {
        Ok(n) => n
        Err(_) => 99
    }
    if total != 0 { return 1 }
    let b = Buffered(inner: Source(data: [4, 5, 6], at: 0), filled: 9)
    let via_b = match b.count_two() {
        Ok(n) => n
        Err(_) => 99
    }
    if via_b != 0 { return 2 }
    var data: Array(U8, 2) = [8, 9]
    var view: MutSlice(U8) = data.slice_mut(0, 2)
    let relayed = relay(view)
    if relayed != 2 { return 3 }
    let outer = outer_len(view)
    if outer != 2 { return 4 }
    return 0
}
