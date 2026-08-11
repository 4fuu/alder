type Pair {
    left: U64
    right: U64
}

enum Mark {
    Number(value: U64)
    End
}

fn first(T: type, b: __s0_Buffer(T)) -> T {
    return __s0_buffer_get(T, b, 0)
}

fn check_shared_aliases(second: __s0_Buffer(U64), third: __s0_Buffer(U64)) -> I32 {
    if __s0_buffer_get(U64, second, 1) != 30 { return 19 }
    if __s0_buffer_get(U64, third, 1) != 30 { return 20 }
    return 0
}

fn fork_third(d: Domain, first: __s0_Buffer(U64), second: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_append(U64, d, first, 30) {
        Err(error) => 18
        Ok(third) => check_shared_aliases(second, third)
    }
}

fn fork_second(d: Domain, first: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_append(U64, d, first, 20) {
        Err(error) => 17
        Ok(second) => fork_third(d, first, second)
    }
}

fn start_alias_check(d: Domain, empty: __s0_Buffer(U64)) -> I32 {
    return match __s0_buffer_append(U64, d, empty, 10) {
        Err(error) => 16
        Ok(first) => fork_second(d, first)
    }
}

fn check_alias_contract(d: Domain) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => 15
        Ok(empty) => start_alias_check(d, empty)
    }
}

fn check_number(d: Domain, value: U64) -> I32 {
    if value != 23 { return 13 }
    return check_alias_contract(d)
}

fn check_mark(d: Domain, b: __s0_Buffer(Mark)) -> I32 {
    let got = first(b)
    return match got {
        Number(value) => check_number(d, value)
        End => 14
    }
}

fn append_mark(d: Domain, empty: __s0_Buffer(Mark)) -> I32 {
    return match __s0_buffer_append(Mark, d, empty, Number(23)) {
        Err(error) => 12
        Ok(one) => check_mark(d, one)
    }
}

fn check_pair_and_mark(d: Domain, b: __s0_Buffer(Pair)) -> I32 {
    let got = first(b)
    if got.left != 21 { return 8 }
    if got.right != 22 { return 9 }
    let s = __s0_buffer_slice(Pair, b)
    if len(s) != 1 { return 10 }
    return match __s0_buffer_new(Mark, d) {
        Err(error) => 11
        Ok(empty) => append_mark(d, empty)
    }
}

fn append_pair(d: Domain, empty: __s0_Buffer(Pair)) -> I32 {
    let value = Pair(left: 21, right: 22)
    return match __s0_buffer_append(Pair, d, empty, value) {
        Err(error) => 7
        Ok(one) => check_pair_and_mark(d, one)
    }
}

fn check_composites(d: Domain) -> I32 {
    return match __s0_buffer_new(Pair, d) {
        Err(error) => 6
        Ok(empty) => append_pair(d, empty)
    }
}

fn check(d: Domain, b: __s0_Buffer(U64), i: U64) -> I32 {
    if __s0_buffer_len(U64, b) != 65 { return 1 }
    let s = __s0_buffer_slice(U64, b)
    if len(s) != 65 { return 2 }
    if i == 65 { return check_composites(d) }
    if __s0_buffer_get(U64, b, i) != i { return 3 }
    if s[i] != i { return 4 }
    return check(d, b, i + 1)
}

fn main(d: Domain) -> I32 {
    return match __s0_buffer_new(U64, d) {
        Err(error) => 90
        Ok(initial) => match fill(d, initial) {
            Err(error) => 91
            Ok(grown) => check(d, grown, 0)
        }
    }
}

fn fill(d: Domain, initial: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) {
    if __s0_buffer_len(U64, initial) != 0 { return Err(Limit) }
    return fill_at(d, initial, 0)
}

fn fill_at(d: Domain, b: __s0_Buffer(U64), i: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    if i == 65 { return Ok(b) }
    let next = try __s0_buffer_append(U64, d, b, i)
    if __s0_buffer_len(U64, next) != i + 1 { return Err(Limit) }
    if i == 8 {
        if __s0_buffer_len(U64, b) != 8 { return Err(Limit) }
        if __s0_buffer_get(U64, b, 7) != 7 { return Err(Limit) }
        if __s0_buffer_len(U64, next) != 9 { return Err(Limit) }
        if __s0_buffer_get(U64, next, 8) != 8 { return Err(Limit) }
    }
    return fill_at(d, next, i + 1)
}
