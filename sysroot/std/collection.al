module std.collection

// The Milestone 8 collection module, one increment at a time. Snapshot v1
// fixes the stable sorting entry point; the re-exports of the core
// collections, `Deque(T)`, binary heaps, and collection builders join later
// amendments as their prerequisites land.
//
// `sort` is stable: values that compare equal keep their input order. The
// merge passes rebuild one output vector per pass instead of writing in
// place, because the `Vec` v1 surface exposes no element assignment; the
// reallocation cost is a known v1 property, not a stability requirement.
// Every comparison goes through the language-provided `less` method of the
// Order domain, so signed integers and floats are rejected at the
// constraint until the language gives them ordering.

/// Sorts `values` ascending with the Order domain's `less`, returning a new
/// owned vector and leaving the input slice untouched. The sort is stable:
/// values that compare equal keep their input order.
pub fn sort(T: type(Order), values: [T]) -> Vec(T) {
    let count = values.len()
    var work: Vec(T) = Vec.new(T)
    var at: U64 = 0
    while at < count {
        match values.get(at) {
            Some(value) => { work.push(value) }
            None => {}
        }
        at = at + 1
    }
    if count < 2 { return work }
    var width: U64 = 1
    var current: Vec(T) = work
    while width < count {
        current = merge_sorted_runs(T, current, width)
        width = width * 2
    }
    return current
}

/// One bottom-up merge pass: every adjacent pair of runs of `width` values
/// merges into a single sorted run of the fresh output vector. Ties take
/// the left run's value first, which is what makes `sort` stable. Out-of
///-range reads cannot happen at any reachable index; the fallback arms
/// exhaust the run so the pass stays total regardless.
fn merge_sorted_runs(T: type(Order), source: Vec(T), width: U64) -> Vec(T) {
    let count = source.len()
    var out: Vec(T) = Vec.new(T)
    var base: U64 = 0
    while base < count {
        var mid = base + width
        if mid > count { mid = count }
        var end = base + width * 2
        if end > count { end = count }
        var left = base
        var right = mid
        while left < mid && right < end {
            match source.get(left) {
                Some(left_value) => {
                    match source.get(right) {
                        Some(right_value) => {
                            if right_value.less(left_value) {
                                out.push(right_value)
                                right = right + 1
                            } else {
                                out.push(left_value)
                                left = left + 1
                            }
                        }
                        None => { left = mid }
                    }
                }
                None => { left = mid }
            }
        }
        while left < mid {
            match source.get(left) {
                Some(value) => { out.push(value) }
                None => {}
            }
            left = left + 1
        }
        while right < end {
            match source.get(right) {
                Some(value) => { out.push(value) }
                None => {}
            }
            right = right + 1
        }
        base = base + width * 2
    }
    return out
}

// M8.1 deque: two Vec halves. The front half stores its elements in reverse
// order so pop_back/pop_front stay at the live end; elements move between the
// halves with pop+push, so storage is bounded by the queue's high-water mark.
// copyable T makes the whole deque copyable; an affine T makes it affine and
// its conditional Cleanup drains both halves through their Vec drains.
pub type Deque(T: type) {
    front: Vec(T)
    back: Vec(T)
}

impl(T: type) Deque(T) {
    /// Creates an empty deque; the element type comes from the binding or
    /// return type.
    fn new() -> Deque(T) {
        return Deque(front: Vec.new(T), back: Vec.new(T))
    }

    fn len(self) -> U64 {
        return self.front.len() + self.back.len()
    }

    fn is_empty(self) -> Bool {
        return self.len() == 0
    }

    /// Appends at the front. An affine value transfers into the deque.
    fn push_front(mut self, take value: T) -> Unit {
        self.front.push(value)
        return
    }

    /// Appends at the back. An affine value transfers into the deque.
    fn push_back(mut self, take value: T) -> Unit {
        self.back.push(value)
        return
    }

    /// Removes the front element, moving the back half into the front half
    /// when the front is empty. An affine value transfers to the caller.
    fn pop_front(mut self) -> Option(T) {
        if self.front.len() == 0 {
            if self.back.len() == 0 { return None }
            while self.back.len() > 0 {
                match self.back.pop() {
                    Some(value) => { self.front.push(value) }
                    None => {}
                }
            }
        }
        return self.front.pop()
    }

    /// Removes the back element, moving the front half into the back half
    /// when the back is empty. An affine value transfers to the caller.
    fn pop_back(mut self) -> Option(T) {
        if self.back.len() == 0 {
            if self.front.len() == 0 { return None }
            while self.front.len() > 0 {
                match self.front.pop() {
                    Some(value) => { self.back.push(value) }
                    None => {}
                }
            }
        }
        return self.back.pop()
    }

    /// Reads the front element when T is copyable. An affine T cannot be read
    /// by value; use pop_front and transfer the owner out.
    fn peek_front(self) -> Option(T) {
        if self.front.len() > 0 { return self.front.get(self.front.len() - 1) }
        if self.back.len() > 0 { return self.back.get(0) }
        return None
    }

    /// Reads the back element when T is copyable. An affine T cannot be read
    /// by value; use pop_back and transfer the owner out.
    fn peek_back(self) -> Option(T) {
        if self.back.len() > 0 { return self.back.get(self.back.len() - 1) }
        if self.front.len() > 0 { return self.front.get(0) }
        return None
    }
}

impl(T: type(Cleanup)) Cleanup for Deque(T) {
    fn cleanup(take self) -> Unit {
        using front = self.front
        using back = self.back
        return
    }
}

// M8.1 binary heap: a min-heap by default and a max-heap through
// BinaryHeap.max. The Vec holds the complete tree in index order; sift-up and
// sift-down use index assignment, so a mutation is O(log n). The element type
// is copyable in v1 because peek and the returned roots are value reads.
pub type BinaryHeap(T: type) {
    items: Vec(T)
    min_first: Bool
}

impl(T: type(Order)) BinaryHeap(T) {
    /// A heap whose root is the smallest value; the element type comes from
    /// the binding or return type.
    fn new() -> BinaryHeap(T) {
        return BinaryHeap(items: Vec.new(T), min_first: true)
    }

    /// A heap whose root is the largest value; the element type comes from
    /// the binding or return type.
    fn max() -> BinaryHeap(T) {
        return BinaryHeap(items: Vec.new(T), min_first: false)
    }

    fn len(self) -> U64 {
        return self.items.len()
    }

    fn is_empty(self) -> Bool {
        return self.items.len() == 0
    }

    /// The root value, or None when empty.
    fn peek(self) -> Option(T) {
        return self.items.get(0)
    }

    /// Inserts a value and restores the heap order.
    fn push(mut self, value: T) -> Unit {
        self.items.push(value)
        let at = self.items.len() - 1
        self.sift_up(at)
        return
    }

    /// Removes and returns the root, or None when empty.
    fn pop(mut self) -> Option(T) {
        let count = self.items.len()
        if count == 0 { return None }
        let root = match self.items.get(0) {
            Some(value) => value
            None => return None
        }
        let last = match self.items.get(count - 1) {
            Some(value) => value
            None => return None
        }
        match self.items.pop() {
            Some(_) => {}
            None => {}
        }
        if count > 1 {
            self.items[0] = last
            self.sift_down(0)
        }
        return Some(root)
    }

    // Whether left belongs above right for this heap's orientation.
    fn before(self, left: T, right: T) -> Bool {
        if self.min_first { return left.less(right) }
        return right.less(left)
    }

    fn sift_up(mut self, start: U64) -> Unit {
        var at = start
        while at > 0 {
            let parent = (at - 1) / 2
            // The parent and child indices are in range by the loop guard and
            // the heap length. Direct indexing reads the field place without
            // copying the whole vector into a loop-local temporary; Vec.get
            // would create an Option(T) block parameter in the loop body.
            let parent_value = self.items[parent]
            let child_value = self.items[at]
            if self.before(parent_value, child_value) { return }
            self.items[parent] = child_value
            self.items[at] = parent_value
            at = parent
        }
        return
    }

    fn sift_down(mut self, start: U64) -> Unit {
        var at = start
        var walking = true
        while walking {
            let count = self.items.len()
            let left = at * 2 + 1
            if left >= count { return }
            var best = left
            let right = left + 1
            if right < count {
                let left_value = self.items[left]
                let right_value = self.items[right]
                if self.before(right_value, left_value) { best = right }
            }
            let current = self.items[at]
            let candidate = self.items[best]
            if self.before(current, candidate) { return }
            self.items[at] = candidate
            self.items[best] = current
            at = best
        }
        return
    }
}
