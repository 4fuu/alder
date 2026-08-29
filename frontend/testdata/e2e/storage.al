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

fn returned_nested_vec_view() -> [Vec(U64)] {
    var first: Vec(U64) = Vec.from_array(U64, [47, 53])
    var second: Vec(U64) = Vec.from_array(U64, [59])
    let values: Array(Vec(U64), 2) = [first, second]
    return values.slice(0, 2)
}

fn returned_nested_vec_array() -> Array(Vec(U64), 2) {
    var first: Vec(U64) = Vec.from_array(U64, [71, 73])
    var second: Vec(U64) = Vec.from_array(U64, [79])
    return [first, second]
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

fn fail_vec() -> Result(U64, Vec(U64)) {
    var error: Vec(U64) = Vec.from_array(U64, [7, 11])
    return Err(error)
}

fn propagate_vec_error() -> Result(U64, Vec(U64)) {
    let value = try fail_vec()
    return Ok(value)
}

fn main() -> I32 {
    let array_view = returned_array_view()
    if array_view[0] != 3 || array_view[2] != 7 { return 1 }

    let vec_view = nested_returned_view()
    if vec_view[0] != 11 || vec_view[2] != 17 { return 2 }

    let parameter_view = returned_parameter_view(vec_view)
    if parameter_view[1] != 13 { return 3 }

    let nested_view = returned_nested_vec_view()
    var nested_original: Vec(U64) = nested_view[0]
    var nested_changed: Vec(U64) = nested_view[0]
    nested_changed[0] = 61
    nested_changed.push(67)
    if nested_original[0] != 47 || nested_original.len() != 2 { return 4 }
    if nested_changed[0] != 61 || nested_changed.len() != 3 { return 5 }

    let nested_array = returned_nested_vec_array()
    var array_original: Vec(U64) = nested_array[0]
    var array_changed: Vec(U64) = nested_array[0]
    array_changed[0] = 79
    array_changed.push(83)
    if array_original[0] != 71 || array_original.len() != 2 { return 6 }
    if array_changed[0] != 79 || array_changed.len() != 3 { return 7 }

    var original = make_values()
    var copied = original
    copied[0] = 41
    copied.push(43)
    if original[0] != 19 || original.len() != 3 { return 8 }
    if copied[0] != 41 || copied.len() != 4 || copied[3] != 43 { return 9 }

    if scalar_from_local_collection() != 37 { return 10 }
    let propagated = propagate_vec_error()
    if !match propagated {
        Ok(value) => false
        Err(error) => error[0] == 7 && error[1] == 11
    } { return 11 }
    return 0
}
