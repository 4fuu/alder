fn returned_array_view() -> [U64] {
    let values: Array(U64, 3) = [3, 5, 7]
    return values.slice(0, 3)
}

fn returned_vec_view() -> [U64] {
    var values: Vec(U64) = Vec.from_array(U64, [11, 13])
    values.push(17)
    return values.slice(0, 3)
}

fn nested_returned_view() -> [U64] {
    return returned_vec_view()
}

fn returned_parameter_view(values: [U64]) -> [U64] {
    return values
}

fn make_values() -> Vec(U64) {
    var values: Vec(U64) = Vec.from_array(U64, [19, 23])
    values.push(29)
    return values
}

fn scalar_from_local_collection() -> U64 {
    var values: Vec(U64) = Vec.from_array(U64, [31])
    values.push(37)
    return values[1]
}

fn main() -> I32 {
    let array_view = returned_array_view()
    if array_view[0] != 3 || array_view[2] != 7 { return 1 }

    let vec_view = nested_returned_view()
    if vec_view[0] != 11 || vec_view[2] != 17 { return 2 }

    let parameter_view = returned_parameter_view(vec_view)
    if parameter_view[1] != 13 { return 3 }

    var original = make_values()
    var copied = original
    copied[0] = 41
    copied.push(43)
    if original[0] != 19 || original.len() != 3 { return 4 }
    if copied[0] != 41 || copied.len() != 4 || copied[3] != 43 { return 5 }

    if scalar_from_local_collection() != 37 { return 6 }
    return 0
}
