fn sum_ends(values: [U64]) -> U64 {
    return values[0] + values[values.len() - 1]
}

fn slice_example() -> U64 {
    var values: Array(U64, 4) = [2, 3, 5, 7]
    var before: U64 = 0

    if true {
        let middle: [U64] = values.slice(1, 3)
        before = sum_ends(middle)
    }

    if true {
        var tail: MutSlice(U64) = values.slice_mut(2, 4)
        tail[0] = 11
        var last: MutSlice(U64) = tail.subview(1, 2)
        last[0] = 13
    }

    return before + values[2] + values[3]
}
