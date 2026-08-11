type Point {
    x: I64
    y: I64
}

type Pair(A: type, B: type) {
    first: A
    second: B
}

fn swap(p: Pair(I64, I64)) -> Pair(I64, I64) {
    return Pair(first: p.second, second: p.first)
}

fn main() -> I32 {
    let p = Point(x: 3, y: 4)
    if p.x + p.y != 7 {
        return 1
    }
    var q = p
    q.x = 10
    if q.x != 10 || p.x != 3 {
        return 2
    }
    let pr = Pair(first: 1, second: "a")
    if pr.first != 1 {
        return 3
    }
    if len(pr.second) != 1 {
        return 4
    }
    let sw = swap(Pair(first: 5, second: 6))
    if sw.first != 6 || sw.second != 5 {
        return 5
    }
    // Generic construction with inferred type arguments.
    let inf = Pair(first: 7, second: 8)
    if inf.second != 8 {
        return 6
    }
    return 0
}
