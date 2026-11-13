module hello.core_iter_example

import core.iter

// The executable core.iter v1 snapshot example. It exercises the builtin
// IntoIterator constructors, every lazy adapter, and every terminal, and
// returns a deterministic checksum.
pub fn core_iter_example() -> U64 {
    var total: U64 = 0
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    values.push(3)
    values.push(4)
    values.push(5)

    var slice_cursor = values.slice(1, 4).into_iterator()
    match slice_cursor.next() {
        Some(value) => { total = total + value }
        None => { return 1 }
    }

    var array_values: Array(U64, 3) = [2, 4, 6]
    var array_cursor = array_values.into_iterator()
    let array_copy = iter.to_vec(array_cursor)
    if array_copy.len() != 3 { return 12 }
    total = total + array_copy[0] + array_copy[2]

    var mutable_values: Array(U64, 3) = [1, 3, 5]
    var mutable_view = mutable_values.slice_mut(0, 3)
    var mutable_cursor = mutable_view.into_iterator()
    let mutable_copy = iter.to_vec(mutable_cursor)
    if mutable_copy.len() != 3 { return 13 }
    total = total + mutable_copy[1]

    let byte_values: Bytes = "\x01\x02\x03"
    var byte_cursor = byte_values.into_iterator()
    let byte_copy = iter.to_vec(byte_cursor)
    if byte_copy.len() != 3 { return 14 }
    if byte_copy[0] != 1 || byte_copy[1] != 2 || byte_copy[2] != 3 { return 15 }
    total = total + 6

    var map = Map.new(U64, U64)
    if !map.insert(2, 20) { return 16 }
    if !map.insert(4, 40) { return 17 }
    var map_cursor = map.into_iterator()
    let entries = iter.to_vec(map_cursor)
    if entries.len() != 2 { return 18 }
    if entries[0].first != 2 || entries[0].second != 20 { return 19 }
    if entries[1].first != 4 || entries[1].second != 40 { return 20 }
    total = total + entries[0].first + entries[1].second

    var set = Set.new(U64)
    if !set.insert(8) { return 21 }
    if !set.insert(9) { return 22 }
    var set_cursor = set.into_iterator()
    let set_items = iter.to_vec(set_cursor)
    if set_items.len() != 2 { return 23 }
    if set_items[0] != 8 || set_items[1] != 9 { return 24 }
    total = total + set_items[0] + set_items[1]

    let offset: U64 = 10
    var mapped = iter.map(values.into_iterator(), fn(x: U64) => x + offset)
    let mapped_values = iter.to_vec(mapped)
    if mapped_values.len() != 5 { return 2 }
    total = total + mapped_values[0] + mapped_values[4]

    var filtered = iter.filter(values.into_iterator(), fn(x: U64) => x % 2 == 0)
    let evens = iter.to_vec(filtered)
    if evens.len() != 2 { return 3 }
    total = total + evens.len() * 2

    var filtered_map = iter.filter_map(values.into_iterator(), fn(x: U64) -> Option(U64) {
        if x > 3 { return Some(x) }
        return None
    })
    let high = iter.to_vec(filtered_map)
    if high.len() != 2 { return 4 }
    total = total + high[0] + high[1]

    var enumerated = iter.enumerate(values.into_iterator())
    match enumerated.next() {
        Some(item) => { total = total + item.index + item.value }
        None => { return 5 }
    }

    var taken = iter.take_count(values.into_iterator(), 2)
    let prefix = iter.to_vec(taken)
    if prefix.len() != 2 { return 6 }
    total = total + prefix[0] + prefix[1]

    var skipped = iter.skip(values.into_iterator(), 3)
    let suffix = iter.to_vec(skipped)
    if suffix.len() != 2 { return 7 }
    total = total + suffix[0] + suffix[1]

    var tail = Vec.new(U64)
    tail.push(6)
    var chained = iter.chain(values.into_iterator(), tail.into_iterator())
    let chained_values = iter.to_vec(chained)
    if chained_values.len() != 6 { return 8 }
    total = total + chained_values[5]

    var right = Vec.new(U64)
    right.push(7)
    right.push(8)
    var zipped = iter.zip(values.into_iterator(), right.into_iterator())
    match zipped.next() {
        Some(pair) => { total = total + pair.first + pair.second }
        None => { return 9 }
    }

    var folded_cursor = values.into_iterator()
    let zero: U64 = 0
    total = total + iter.fold(folded_cursor, zero, fn(acc: U64, x: U64) => acc + x)

    var count_cursor = values.into_iterator()
    total = total + iter.count(count_cursor)

    var any_cursor = values.into_iterator()
    if iter.any(any_cursor, fn(x: U64) => x == 4) { total = total + 1 }

    var all_cursor = values.into_iterator()
    if iter.all(all_cursor, fn(x: U64) => x < 6) { total = total + 2 }

    var find_cursor = values.into_iterator()
    match iter.find(find_cursor, fn(x: U64) => x > 3) {
        Some(value) => { total = total + value }
        None => { return 10 }
    }

    var position_cursor = values.into_iterator()
    match iter.position(position_cursor, fn(x: U64) => x == 5) {
        Some(position) => { total = total + position }
        None => { return 11 }
    }

    var each_cursor = values.into_iterator()
    iter.for_each(each_cursor, fn(x: U64) -> Unit { return })

    return total
}
