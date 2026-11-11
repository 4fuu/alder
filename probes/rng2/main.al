module hello.main

type Box {
    n: U64
}

impl Box {
    fn pack_view(mut self, buffer: MutSlice(U8)) -> Unit {
        buffer[0] = self.n.to_u8_wrapping()
        return
    }
}

pub fn main() -> I32 {
    let b2 = Box(n: 9)
    let data2: Array(U8, 2) = [0, 0]
    let view2 = data2.slice_mut(0, 2)
    b2.pack_view(view2)
    if view2[0] != 9 { return 2 }
    return 0
}
