# `std.collection` Public Signature Snapshot v1

Status: **Milestone 8 frozen snapshot**

This is the versioned public snapshot for stable sorting over the Order
domain. It is normative together with the executable example
[`examples/std.collection-v1.al`](examples/std.collection-v1.al), which lands
in the module's implementation commit: the docs example runner resolves
sysroot modules, so the example file cannot precede the module it imports.
The module lives at `<sysroot>/std/collection.al`.

Snapshot v1 covers the stable sorting entry point only. The re-exports of
the core collections, `Deque(T)`, binary heaps, and the collection builders
join later amendments as their prerequisites land. The module is pure
computation: it never observes the host, so no function takes a capability.
It depends on no other std module, so it sits at the bottom of the std
module graph.

## Signatures

```alder
module std.collection

/// Sorts `values` ascending with the Order domain's `less`, returning a
/// new owned vector and leaving the input slice untouched. The sort is
/// stable: values that compare equal keep their input order.
pub fn sort(T: type(Order), values: [T]) -> Vec(T)
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
- Every function is total against its input: no function panics, terminates,
  or reads anything but its arguments.

## Example

The example below is the complete content that lands as
`examples/std.collection-v1.al` with the implementation commit. It sorts
unsigned integers with ties, strings with prefix ordering and equal
values, and booleans, checks the empty and single-element cases, and
returns a deterministic checksum.

```alder
module hello.std_collection_example

import std.collection { sort }

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
