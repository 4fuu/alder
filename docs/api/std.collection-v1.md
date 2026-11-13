# `std.collection` Public Signature Snapshot v1

Status: **Milestone 8.1 v1 amendment**

This is the versioned public snapshot for stable sorting over the Order
domain plus the Milestone 8.1 deque and binary-heap additions. It is
normative together with the executable example
[`examples/std.collection-v1.al`](examples/std.collection-v1.al), which lands
in the module's implementation commit: the docs example runner resolves
sysroot modules, so the example file cannot precede the module it imports.
The module lives at `<sysroot>/std/collection.al`.

Snapshot v1 now covers the stable sorting entry point, `Deque(T)`, and
`BinaryHeap(T)`. The re-exports of the core collections and the collection
builders join later amendments as their prerequisites land. The module is
pure computation: it never observes the host, so no function takes a
capability. It depends on no other std module, so it sits at the bottom of
the std module graph.

## Signatures

```alder
module std.collection

/// Sorts `values` ascending with the Order domain's `less`, returning a
/// new owned vector and leaving the input slice untouched. The sort is
/// stable: values that compare equal keep their input order.
pub fn sort(T: type(Order), values: [T]) -> Vec(T)

pub type Deque(T: type)

impl(T: type) Deque(T) {
    pub fn new() -> Deque(T)
    pub fn len(self) -> U64
    pub fn is_empty(self) -> Bool
    pub fn push_front(mut self, take value: T) -> Unit
    pub fn push_back(mut self, take value: T) -> Unit
    pub fn pop_front(mut self) -> Option(T)
    pub fn pop_back(mut self) -> Option(T)
    pub fn peek_front(self) -> Option(T)
    pub fn peek_back(self) -> Option(T)
}

impl(T: type(Cleanup)) Cleanup for Deque(T)

pub type BinaryHeap(T: type(Order))

impl(T: type(Order)) BinaryHeap(T) {
    pub fn new() -> BinaryHeap(T)
    pub fn max() -> BinaryHeap(T)
    pub fn len(self) -> U64
    pub fn is_empty(self) -> Bool
    pub fn peek(self) -> Option(T)
    pub fn push(mut self, value: T) -> Unit
    pub fn pop(mut self) -> Option(T)
}
```

## Contracts

- The Order domain is the language-provided builtin trait with the single
  requirement `fn less(self, other: Self) -> Bool`. Its implementations are
  language-provided for the closed scalar domain: `Bool` (false sorts below
  true), the unsigned integers `U8`, `U16`, `U32`, and `U64`, `String`
  (byte-lexicographic), and `Bytes` (byte-lexicographic). Signed integers,
  floats, and composites are outside the domain and reject instantiation
  with the trait-required diagnostic.
- Byte-lexicographic comparison orders shorter prefixes before their
  extensions: `"app"` sorts before `"apple"`. Comparison is bytewise; no
  collation, case folding, or normalization applies.
- The sort is stable: values that compare equal keep their input order.
  Over the v1 scalar domain equal values are indistinguishable, so the
  guarantee becomes observable when the domain widens; the implementation
  already keeps it.
- `sort` is total and pure: it allocates a fresh result vector per merge
  pass and never mutates the input slice. The per-pass rebuild is a known
  v1 cost, documented until a `Vec` element-assignment surface replaces it;
  the algorithm stays bottom-up merge sort with left-run-first ties.
- `Deque` stores values in two `Vec` halves: the front half keeps its live
  element at the vector end, and the back half keeps it at index zero of the
  queue. Moving a half drains it with `pop` and pushes into the other half,
  so steady queue traffic does not grow storage without bound; capacity is
  bounded by the queue's high-water mark. Pushes and pops are amortized O(1).
- `Deque(T)` is copyable when `T` is copyable, and affine when `T` implements
  `Cleanup`; the conditional `Cleanup` implementation drains both halves.
  `push_*` and `pop_*` transfer affine elements, while `peek_*` copies and is
  therefore available only when `T` is copyable. An affine value must be named
  by an owning local before a push, and a popped affine owner must be
  registered or transferred before exit. A registered deque is immutable;
  pop before registering it.
- `BinaryHeap(T)` is a min-heap by default and a max-heap through
  `BinaryHeap.max()`. It stores a complete tree over `Vec(T)`, with O(log n)
  sift-up and sift-down on push and pop and O(1) `peek`. `pop` returns `None`
  when the heap is empty. `T` must be in the copyable `Order` domain: `Bool`,
  the unsigned integers, `String`, or `Bytes` in v1. Equal values may be
  popped in any order; the heap does not promise stable ordering.
- Every function is total against its input: it rejects no valid value and
  reads nothing but its arguments. Memory allocation and checked arithmetic
  follow the ordinary invariant-failure termination path.

## Example

The example below is the complete content that lands as
`examples/std.collection-v1.al` with the implementation commit. It sorts
unsigned integers with ties, strings with prefix ordering and equal
values, and booleans, checks the empty and single-element cases, exercises
deque order across both halves and min/max heap order, and returns the
deterministic checksum 255.

```alder
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
```

## Dependencies and sequencing

- Builds on the language-provided Order implementations; the module itself
  has no std dependencies, so the module graph stays acyclic with
  `std.collection` at the bottom next to `std.bytes`.
- Sorting keys beyond the scalar domain (records keyed by one field,
  user-provided comparators) wait for the domain to widen and land as a v2
  amendment; the stability guarantee carries over unchanged.
