fn classify(x: U64) -> U64 {
    if x == 0 {
        return 10
    } else if x == 1 {
        return 11
    } else if x == 2 {
        return 12
    } else {
        return 13
    }
}

fn bucket(x: U64) -> U64 {
    if x < 10 { return 1 } else if x < 20 { return 2 } else if x < 30 { return 3 } else { return 4 }
}

fn sum(n: U64) -> U64 {
    var total: U64 = 0
    var i: U64 = 0
    while i < n {
        if i == 0 {
            total = total + 1
        } else if i == 1 {
            total = total + 2
        } else {
            total = total + 3
        }
        i = i + 1
    }
    return total
}

fn main() -> I32 {
    if classify(0) != 10 { return 1 }
    if classify(2) != 12 { return 2 }
    if classify(9) != 13 { return 3 }
    if bucket(5) != 1 { return 4 }
    if bucket(15) != 2 { return 5 }
    if bucket(25) != 3 { return 6 }
    if bucket(35) != 4 { return 7 }
    if sum(4) != 9 { return 8 }
    return 0
}
