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
