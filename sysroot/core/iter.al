module core.iter

// The Milestone 8.1 static iterator layer. `Iterator(Item)` and
// `IntoIterator(IteratorType, Item)` are builtin traits; this module installs
// the adapter values and the terminal helpers that consume them. Every
// operation resolves statically and monomorphizes before MIR: there are no
// trait objects, no associated types, and no runtime dispatch metadata.
//
// SliceIter and VecIter hold immutable `[T]` views rather than owned Vec
// values. The M7.3 aggregate-return rule materializes a returned view into
// caller-result storage: constructing one copies O(n) elements and allocates
// O(n) caller-result storage, and later source changes are not observed. An
// adapter constructor returns a view-bearing aggregate too, so it applies the
// same materialization to its inner iterator and can copy the remaining
// elements again. The library owns no Vec header or capacity and adds no copy
// beyond the installed return-materialization rule.
//
// Adapter values carry their item types as explicit parameters because
// `Iterator(Item)` has no associated type. Closures are stored in
// function-typed fields; a capturing closure is an ordinary function value
// with its compiler-generated environment.
//
// Method-syntax chaining (`values.into_iterator().map(...)`) waits for the
// frontend that replaces S0; this snapshot uses the free functions here.
// `for`-through-`IntoIterator` is likewise specified but not desugared yet.

/// An immutable view of a slice, advanced by `next`.
pub type SliceIter(T: type) {
    values: [T]
    at: U64
}

/// An immutable view of a Vec, advanced by `next`.
pub type VecIter(T: type) {
    values: [T]
    at: U64
}

/// Wraps a slice view in an iterator.
pub fn slice_iter(T: type, values: [T]) -> SliceIter(T) {
    return SliceIter(values: values, at: 0)
}

/// Wraps a Vec view in an iterator. The view is formed from the caller-owned
/// parameter and materialized by the aggregate return rule; the iterator does
/// not own a second vector.
pub fn vec_iter(T: type, values: Vec(T)) -> VecIter(T) {
    return VecIter(values: values.slice(0, values.len()), at: 0)
}


impl(T: type) SliceIter(T) {
    /// Collects the values not yet consumed into a fresh Vec.
    fn to_vec(self) -> Vec(T) {
        var values = Vec.new(T)
        var index = self.at
        while index < self.values.len() {
            values.push(self.values[index])
            index = index + 1
        }
        return values
    }
}

impl(T: type) VecIter(T) {
    /// Collects the values not yet consumed into a fresh Vec.
    fn to_vec(self) -> Vec(T) {
        var values = Vec.new(T)
        var index = self.at
        while index < self.values.len() {
            values.push(self.values[index])
            index = index + 1
        }
        return values
    }
}

impl(T: type) Iterator(T) for SliceIter(T) {
    fn next(mut self) -> Option(T) {
        if self.at >= self.values.len() { return None }
        let index = self.at
        self.at = self.at + 1
        return self.values.get(index)
    }
}

impl(T: type) Iterator(T) for VecIter(T) {
    fn next(mut self) -> Option(T) {
        if self.at >= self.values.len() { return None }
        let index = self.at
        self.at = self.at + 1
        return self.values.get(index)
    }
}

/// One value with its zero-based position in an enumeration.
pub type Indexed(T: type) {
    pub index: U64
    pub value: T
}

/// Two values yielded together by `zip`.
pub type Pair(A: type, B: type) {
    pub first: A
    pub second: B
}

/// A lazy transform.
pub type MapIter(I: type, T: type, U: type) {
    inner: I
    f: fn(T) -> U
}

pub fn map(I: type(Iterator(T)), T: type, U: type, iterator: I, f: fn(T) -> U) -> MapIter(I, T, U) {
    return MapIter(inner: iterator, f: f)
}

impl(I: type(Iterator(T)), T: type, U: type) Iterator(U) for MapIter(I, T, U) {
    fn next(mut self) -> Option(U) {
        match self.inner.next() {
            Some(value) => {
                let transform = self.f
                return Some(transform(value))
            }
            None => { return None }
        }
        return None
    }
}

/// A lazy predicate filter.
pub type FilterIter(I: type, T: type) {
    inner: I
    keep: fn(T) -> Bool
}

pub fn filter(I: type(Iterator(T)), T: type, iterator: I, keep: fn(T) -> Bool) -> FilterIter(I, T) {
    return FilterIter(inner: iterator, keep: keep)
}

impl(I: type(Iterator(T)), T: type) Iterator(T) for FilterIter(I, T) {
    fn next(mut self) -> Option(T) {
        var running = true
        while running {
            match self.inner.next() {
                Some(value) => {
                    let keep = self.keep
                    if keep(value) { return Some(value) }
                }
                None => { running = false }
            }
        }
        return None
    }
}

/// A lazy transform that also drops values mapped to `None`.
pub type FilterMapIter(I: type, T: type, U: type) {
    inner: I
    f: fn(T) -> Option(U)
}

pub fn filter_map(I: type(Iterator(T)), T: type, U: type, iterator: I, f: fn(T) -> Option(U)) -> FilterMapIter(I, T, U) {
    return FilterMapIter(inner: iterator, f: f)
}

impl(I: type(Iterator(T)), T: type, U: type) Iterator(U) for FilterMapIter(I, T, U) {
    fn next(mut self) -> Option(U) {
        var running = true
        while running {
            match self.inner.next() {
                Some(value) => {
                    let transform = self.f
                    match transform(value) {
                        Some(mapped) => { return Some(mapped) }
                        None => {}
                    }
                }
                None => { running = false }
            }
        }
        return None
    }
}

/// Attaches each value's zero-based position.
pub type EnumerateIter(I: type, T: type) {
    inner: I
    next_index: U64
}

pub fn enumerate(I: type(Iterator(T)), T: type, iterator: I) -> EnumerateIter(I, T) {
    return EnumerateIter(inner: iterator, next_index: 0)
}

impl(I: type(Iterator(T)), T: type) Iterator(Indexed(T)) for EnumerateIter(I, T) {
    fn next(mut self) -> Option(Indexed(T)) {
        match self.inner.next() {
            Some(value) => {
                let index = self.next_index
                self.next_index = self.next_index + 1
                return Some(Indexed(index: index, value: value))
            }
            None => { return None }
        }
        return None
    }
}

/// Stops after a fixed count.
pub type TakeIter(I: type, T: type) {
    inner: I
    remaining: U64
}

pub fn take_count(I: type(Iterator(T)), T: type, iterator: I, count: U64) -> TakeIter(I, T) {
    return TakeIter(inner: iterator, remaining: count)
}

impl(I: type(Iterator(T)), T: type) Iterator(T) for TakeIter(I, T) {
    fn next(mut self) -> Option(T) {
        if self.remaining == 0 { return None }
        self.remaining = self.remaining - 1
        return self.inner.next()
    }
}

/// Drops a fixed count before yielding.
pub type SkipIter(I: type, T: type) {
    inner: I
    remaining: U64
}

pub fn skip(I: type(Iterator(T)), T: type, iterator: I, count: U64) -> SkipIter(I, T) {
    return SkipIter(inner: iterator, remaining: count)
}

impl(I: type(Iterator(T)), T: type) Iterator(T) for SkipIter(I, T) {
    fn next(mut self) -> Option(T) {
        while self.remaining > 0 {
            match self.inner.next() {
                Some(_) => { self.remaining = self.remaining - 1 }
                None => {
                    self.remaining = 0
                    return None
                }
            }
        }
        return self.inner.next()
    }
}

/// Yields the first iterator's values, then the second's.
pub type ChainIter(A: type, B: type, T: type) {
    first: A
    second: B
    first_done: Bool
}

pub fn chain(A: type(Iterator(T)), B: type(Iterator(T)), T: type, first: A, second: B) -> ChainIter(A, B, T) {
    return ChainIter(first: first, second: second, first_done: false)
}

impl(A: type(Iterator(T)), B: type(Iterator(T)), T: type) Iterator(T) for ChainIter(A, B, T) {
    fn next(mut self) -> Option(T) {
        if !self.first_done {
            match self.first.next() {
                Some(value) => { return Some(value) }
                None => { self.first_done = true }
            }
        }
        return self.second.next()
    }
}

/// Yields one `Pair` for each position where both iterators have a value.
pub type ZipIter(A: type, B: type, T: type, U: type) {
    first: A
    second: B
}

pub fn zip(A: type(Iterator(T)), B: type(Iterator(U)), T: type, U: type, first: A, second: B) -> ZipIter(A, B, T, U) {
    return ZipIter(first: first, second: second)
}

impl(A: type(Iterator(T)), B: type(Iterator(U)), T: type, U: type) Iterator(Pair(T, U)) for ZipIter(A, B, T, U) {
    fn next(mut self) -> Option(Pair(T, U)) {
        match self.first.next() {
            Some(left) => {
                match self.second.next() {
                    Some(right) => { return Some(Pair(first: left, second: right)) }
                    None => { return None }
                }
            }
            None => { return None }
        }
        return None
    }
}

/// Collects every remaining value into a fresh Vec.
pub fn to_vec(I: type(Iterator(T)), T: type, mut iterator: I) -> Vec(T) {
    var values = Vec.new(T)
    var running = true
    while running {
        match iterator.next() {
            Some(value) => { values.push(value) }
            None => { running = false }
        }
    }
    return values
}

/// Folds every remaining value into an accumulator.
pub fn fold(I: type(Iterator(T)), T: type, A: type, mut iterator: I, initial: A, f: fn(A, T) -> A) -> A {
    var accumulator = initial
    var running = true
    while running {
        match iterator.next() {
            Some(value) => {
                let step = f
                accumulator = step(accumulator, value)
            }
            None => { running = false }
        }
    }
    return accumulator
}

/// Applies a function to every remaining value for its effects.
pub fn for_each(I: type(Iterator(T)), T: type, mut iterator: I, f: fn(T) -> Unit) -> Unit {
    var running = true
    while running {
        match iterator.next() {
            Some(value) => {
                let step = f
                step(value)
            }
            None => { running = false }
        }
    }
    return
}

/// Counts every remaining value.
pub fn count(I: type(Iterator(T)), T: type, mut iterator: I) -> U64 {
    var total: U64 = 0
    var running = true
    while running {
        match iterator.next() {
            Some(_) => { total = total + 1 }
            None => { running = false }
        }
    }
    return total
}

/// True when any remaining value satisfies the predicate.
pub fn any(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Bool {
    var running = true
    while running {
        match iterator.next() {
            Some(value) => {
                let test = predicate
                if test(value) { return true }
            }
            None => { running = false }
        }
    }
    return false
}

/// True when every remaining value satisfies the predicate.
pub fn all(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Bool {
    var running = true
    while running {
        match iterator.next() {
            Some(value) => {
                let test = predicate
                if !test(value) { return false }
            }
            None => { running = false }
        }
    }
    return true
}

/// The first remaining value that satisfies the predicate.
pub fn find(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Option(T) {
    var running = true
    while running {
        match iterator.next() {
            Some(value) => {
                let test = predicate
                if test(value) { return Some(value) }
            }
            None => { running = false }
        }
    }
    return None
}

/// The zero-based position of the first value that satisfies the predicate.
pub fn position(I: type(Iterator(T)), T: type, mut iterator: I, predicate: fn(T) -> Bool) -> Option(U64) {
    var index: U64 = 0
    var running = true
    while running {
        match iterator.next() {
            Some(value) => {
                let test = predicate
                if test(value) { return Some(index) }
                index = index + 1
            }
            None => { running = false }
        }
    }
    return None
}
