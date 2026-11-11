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

    var total: U64 = values.len() + copied[1] + first(values)

    // Insertion-ordered Map: replacing a key keeps its position, removal
    // compacts in order, and reinsertion moves the key to the end.
    var counts = Map.new(U64, U64)
    if !counts.insert(7, 70) { total = total - 1000000 }
    if !counts.insert(9, 90) { total = total - 1000000 }
    if !counts.insert(11, 110) { total = total - 1000000 }
    if counts.insert(9, 95) { total = total - 1000000 }
    let replaced = counts.get(9)
    let replaced_value = match replaced {
        Some(v) => v
        None => 0
    }
    total = total + replaced_value
    if !counts.remove(7) { total = total - 1000000 }
    if !counts.insert(7, 700) { total = total - 1000000 }
    let order = counts.keys()
    let first_key = order.get(0)
    let first_value = match first_key {
        Some(k) => k
        None => 0
    }
    if first_value == 9 { total = total + 1 }
    let last_key = order.get(2)
    let last_value = match last_key {
        Some(k) => k
        None => 0
    }
    if last_value == 7 { total = total + 2 }

    // Insertion-ordered Set: duplicates collapse, membership is exact.
    var tags = Set.new(U64)
    if !tags.insert(3) { total = total - 1000000 }
    if !tags.insert(5) { total = total - 1000000 }
    if tags.insert(3) { total = total - 1000000 }
    if tags.len() == 2 { total = total + 8 }
    if tags.contains(5) { total = total + 16 }
    if !tags.contains(9) { total = total + 32 }
    if !tags.remove(5) { total = total - 1000000 }
    if tags.contains(5) { total = total - 1000000 }
    let items = tags.items()
    if items.len() == 1 { total = total + 128 }

    return total
}
