module hello.std_collection_example

import std.collection { BinaryHeap, Deque, sort }

// The executable std.collection v1 snapshot example. Fixed inputs only;
// every stage contributes a deterministic share of the returned checksum.

pub fn std_collection_example() -> U64 {
    var total: U64 = 0

    // Unsigned integers sort ascending, ties included.
    let numbers: Array(U64, 7) = [5, 1, 4, 1, 3, 1, 9]
    let sorted_numbers = sort(U64, numbers.slice(0, 7))
    if sorted_numbers.len() == 7 { total = total + 1 }
    let expect_numbers: Array(U64, 7) = [1, 1, 1, 3, 4, 5, 9]
    var number_bad: Bool = false
    var at: U64 = 0
    while at < 7 {
        match sorted_numbers.get(at) {
            Some(value) => {
                match expect_numbers.get(at) {
                    Some(expected) => {
                        if value != expected { number_bad = true }
                    }
                    None => { number_bad = true }
                }
            }
            None => { number_bad = true }
        }
        at = at + 1
    }
    if number_bad { total = total - 1000000 }

    // The input slice stays untouched; the result is a new vector.
    var untouched: Bool = true
    match numbers.get(0) {
        Some(first) => { if first != 5 { untouched = false } }
        None => { untouched = false }
    }
    if untouched { total = total + 2 }

    // Strings order byte-lexicographically, so prefixes sort first and
    // equal values keep their input order.
    let words: Array(String, 5) = ["pear", "apple", "banana", "app", "apple"]
    let sorted_words = sort(String, words.slice(0, 5))
    let expect_words: Array(String, 5) = ["app", "apple", "apple", "banana", "pear"]
    var word_bad: Bool = false
    var word_at: U64 = 0
    while word_at < 5 {
        match sorted_words.get(word_at) {
            Some(value) => {
                match expect_words.get(word_at) {
                    Some(expected) => {
                        if value != expected { word_bad = true }
                    }
                    None => { word_bad = true }
                }
            }
            None => { word_bad = true }
        }
        word_at = word_at + 1
    }
    if word_bad { total = total - 1000000 }
    if sorted_words.len() == 5 { total = total + 4 }

    // Booleans sort false before true.
    let flags: Array(Bool, 3) = [true, false, true]
    let sorted_flags = sort(Bool, flags.slice(0, 3))
    var flags_bad: Bool = false
    if sorted_flags.len() != 3 { flags_bad = true }
    match sorted_flags.get(0) {
        Some(value) => { if value { flags_bad = true } }
        None => { flags_bad = true }
    }
    match sorted_flags.get(1) {
        Some(value) => { if !value { flags_bad = true } }
        None => { flags_bad = true }
    }
    match sorted_flags.get(2) {
        Some(value) => { if !value { flags_bad = true } }
        None => { flags_bad = true }
    }
    if flags_bad { total = total - 1000000 }
    if !flags_bad { total = total + 8 }

    // Empty and single-element inputs come back unchanged.
    let none: Array(U64, 0) = []
    let sorted_none = sort(U64, none.slice(0, 0))
    if sorted_none.len() == 0 { total = total + 16 }
    let one: Array(U64, 1) = [42]
    let sorted_one = sort(U64, one.slice(0, 1))
    if sorted_one.len() == 1 { total = total + 32 }

    // Deque preserves queue order while moving values between its two halves.
    var queue: Deque(U64) = Deque.new()
    queue.push_back(2)
    queue.push_back(3)
    queue.push_front(1)
    var deque_bad: Bool = false
    match queue.pop_front() {
        Some(value) => { if value != 1 { deque_bad = true } }
        None => { deque_bad = true }
    }
    match queue.pop_back() {
        Some(value) => { if value != 3 { deque_bad = true } }
        None => { deque_bad = true }
    }
    match queue.pop_front() {
        Some(value) => { if value != 2 { deque_bad = true } }
        None => { deque_bad = true }
    }
    match queue.pop_back() {
        Some(_) => { deque_bad = true }
        None => {}
    }
    if deque_bad { total = total - 1000000 } else { total = total + 64 }

    // A min-heap yields ascending roots; BinaryHeap.max yields descending
    // roots. Duplicate values remain valid children.
    var heap: BinaryHeap(U64) = BinaryHeap.new()
    heap.push(3)
    heap.push(1)
    heap.push(2)
    var heap_bad: Bool = false
    match heap.pop() {
        Some(value) => { if value != 1 { heap_bad = true } }
        None => { heap_bad = true }
    }
    match heap.pop() {
        Some(value) => { if value != 2 { heap_bad = true } }
        None => { heap_bad = true }
    }
    match heap.pop() {
        Some(value) => { if value != 3 { heap_bad = true } }
        None => { heap_bad = true }
    }
    match heap.pop() {
        Some(_) => { heap_bad = true }
        None => {}
    }
    var max_heap: BinaryHeap(U64) = BinaryHeap.max()
    max_heap.push(1)
    max_heap.push(3)
    max_heap.push(2)
    match max_heap.pop() {
        Some(value) => { if value != 3 { heap_bad = true } }
        None => { heap_bad = true }
    }
    match max_heap.pop() {
        Some(value) => { if value != 2 { heap_bad = true } }
        None => { heap_bad = true }
    }
    match max_heap.pop() {
        Some(value) => { if value != 1 { heap_bad = true } }
        None => { heap_bad = true }
    }
    if heap_bad { total = total - 1000000 } else { total = total + 128 }

    return total
}
