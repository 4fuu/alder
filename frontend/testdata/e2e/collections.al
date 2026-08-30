fn first(T: type, values: [T]) -> T {
    return values[0]
}

fn main() -> I32 {
    var values: Vec(U64) = Vec.new(U64)
    values.push(3)
    values.push(5)
    values.push(8)
    values.push(13)
    values.push(21)

    var copied: Vec(U64) = values
    copied[1] = 34
    if values.len() != 5 { return 1 }
    if values[1] != 5 { return 2 }
    if copied[1] != 34 { return 3 }
    if first(values) != 3 { return 4 }

    let maybe = values.get(2)
    let got = match maybe {
        Some(value) => value
        None => 0
    }
    if got != 8 { return 5 }

    var from: Vec(U64) = Vec.from_array(U64, [2, 3, 5, 7])
    from.push(11)
    if from.len() != 5 || from[4] != 11 { return 6 }

    var array: Array(U64, 4) = [2, 3, 5, 7]
    var before: U64 = 0
    if true {
        let middle: [U64] = array.slice(1, 3)
        before = first(middle)
    }
    if true {
        var tail: MutSlice(U64) = array.slice_mut(2, 4)
        tail[0] = 11
        var last: MutSlice(U64) = tail.subview(1, 2)
        last[0] = 13
    }
    if before != 3 || array[2] != 11 || array[3] != 13 { return 7 }
    if first(array) != 2 { return 8 }

    let reserved = match values.try_reserve(12) {
        Ok => true
        Err(error) => false
    }
    if !reserved || values.len() != 5 || values[1] != 5 { return 9 }
    let pushed = match values.try_push(34) {
        Ok => true
        Err(error) => false
    }
    if !pushed || values.len() != 6 || values[5] != 34 { return 10 }

    var nested: Vec(Vec(U64)) = Vec.new(Vec(U64))
    let nested_pushed = match nested.try_push(values) {
        Ok => true
        Err(error) => false
    }
    values[0] = 55
    if !nested_pushed || nested[0][0] != 3 || values[0] != 55 { return 11 }
    return 0
}
