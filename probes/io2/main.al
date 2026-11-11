module hello.main

import hello.io2 { Handle, Counter, consume, fill }

fn main() -> I32 {
    let h = Handle(id: 9)
    if consume(h) != 9 { return 1 }
    var c = Counter(total: 0)
    if c.bump() != 1 { return 2 }
    if c.bump() != 2 { return 3 }
    var data: Array(U8, 4) = [0, 0, 0, 0]
    var wrote: U64 = 0
    {
        var view: MutSlice(U8) = data.slice_mut(0, 4)
        wrote = fill(view)
    }
    if wrote != 4 { return 4 }
    if data[0] != 65 { return 5 }
    if data[3] != 65 { return 6 }
    return 0
}
