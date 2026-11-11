module hello.main

import hello.io4 { Box2, Leaf, take_val }

fn main() -> I32 {
    let b = Box2(v: Leaf(n: 5))
    let w = b.value()
    if w != 5 { return 1 }
    let leaf = Leaf(n: 7)
    let through_leaf = take_val(leaf)
    if through_leaf != 7 { return 2 }
    let through_box = take_val(b)
    if through_box != 5 { return 3 }
    return 0
}
