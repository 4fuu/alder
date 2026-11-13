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
