fn first(values: [U64]) -> U64 {
    return values[0]
}

fn collection_example() -> U64 {
    var values: Vec(U64) = Vec.new(U64)
    values.push(3)
    values.push(5)
    values.push(8)
    values.push(13)
    values.push(21)

    var copied: Vec(U64) = values
    copied[1] = 34

    return values.len() + copied[1] + first(values)
}
