type Key {
    a: U64
    b: Bool
}

enum Flag {
    Empty
    Tagged(value: U64)
}

fn main(d: Domain) -> I32 {
    var m = __s0_map_create(Map(U64, I64), d)
    Set(m, 1, 100)
    Set(m, 17, 200)
    Set(m, 33, 300)
    if match Get(m, 1) {
        Some(v) => v
        None => 0
    } != 100 {
        return 1
    }
    if match Get(m, 33) {
        Some(v) => v
        None => 0
    } != 300 {
        return 2
    }
    if match Get(m, 9) {
        Some(v) => v
        None => 1
    } != 1 {
        return 3
    }
    // Overwrite an existing key.
    Set(m, 17, 250)
    if match Get(m, 17) {
        Some(v) => v
        None => 0
    } != 250 {
        return 4
    }
    // Remove and re-insert.
    if !Remove(m, 1) {
        return 5
    }
    if match Get(m, 1) {
        Some(v) => v
        None => 1
    } != 1 {
        return 6
    }
    if Remove(m, 1) {
        return 7
    }
    if match Get(m, 33) {
        Some(v) => v
        None => 0
    } != 300 {
        return 8
    }
    Set(m, 1, 111)
    if match Get(m, 1) {
        Some(v) => v
        None => 0
    } != 111 {
        return 9
    }
    // Struct keys with a Bool field.
    var mk = __s0_map_create(Map(Key, I64), d)
    let k1 = Key(a: 7, b: true)
    let k2 = Key(a: 7, b: false)
    let k3 = Key(a: 8, b: true)
    Set(mk, k1, 1)
    Set(mk, k2, 2)
    Set(mk, k3, 3)
    if match Get(mk, k2) {
        Some(v) => v
        None => 0
    } != 2 {
        return 10
    }
    if match Get(mk, k3) {
        Some(v) => v
        None => 0
    } != 3 {
        return 11
    }
    if match Get(mk, Key(a: 9, b: true)) {
        Some(v) => v
        None => 1
    } != 1 {
        return 12
    }
    // Enum keys exercise tag and payload hashing and equality.
    var me = __s0_map_create(Map(Flag, I64), d)
    let empty: Flag = Empty
    let tagged: Flag = Tagged(7)
    Set(me, empty, 40)
    Set(me, tagged, 41)
    if match Get(me, tagged) {
        Some(v) => v
        None => 0
    } != 41 {
        return 13
    }
    // Near-capacity insertions exercise the complete probe loop.
    var mc = __s0_map_create(Map(U64, U64), d)
    var i: U64 = 0
    while i < 14 {
        Set(mc, i, i)
        i = i + 1
    }
    if match Get(mc, 13) {
        Some(v) => v
        None => 0
    } != 13 {
        return 14
    }
    return 0
}
