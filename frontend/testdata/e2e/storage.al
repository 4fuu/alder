type ViewBox {
    values: [U64]
}

type GenericViewBox(T: type) {
    value: T
}

enum ViewChoice {
    Missing
    Present(value: ViewBox)
}

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

fn returned_record_view() -> ViewBox {
    var values: Vec(U64) = Vec.from_array(U64, [89, 97])
    return ViewBox(values: values.slice(0, 2))
}

fn returned_variant_view() -> ViewChoice {
    let values: Array(U64, 2) = [101, 103]
    return Present(ViewBox(values: values.slice(0, 2)))
}

fn returned_array_views() -> Array([U64], 2) {
    let left: Array(U64, 2) = [107, 109]
    var right: Vec(U64) = Vec.from_array(U64, [113, 127])
    return [left.slice(0, 2), right.slice(0, 2)]
}

fn returned_vec_views() -> Vec(ViewBox) {
    let left: Array(U64, 1) = [131]
    let right: Array(U64, 1) = [137]
    var values: Vec(ViewBox) = Vec.from_array(ViewBox, [ViewBox(values: left.slice(0, 1))])
    values.push(ViewBox(values: right.slice(0, 1)))
    return values
}

fn returned_generic_view() -> GenericViewBox([U64]) {
    let values: Array(U64, 2) = [139, 149]
    return GenericViewBox(value: values.slice(0, 2))
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

    let record = returned_record_view()
    if record.values[0] != 89 || record.values[1] != 97 { return 12 }

    let choice = returned_variant_view()
    if !match choice {
        Missing => false
        Present(box) => box.values[0] == 101 && box.values[1] == 103
    } { return 13 }

    let array_views = returned_array_views()
    if array_views[0][0] != 107 || array_views[1][1] != 127 { return 14 }

    let vec_views = returned_vec_views()
    if vec_views[0].values[0] != 131 || vec_views[1].values[0] != 137 { return 15 }

    let generic = returned_generic_view()
    if generic.value[0] != 139 || generic.value[1] != 149 { return 16 }
    return 0
}
