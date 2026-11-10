module hello.num_example

import core.num

// The executable core.num v1 snapshot example. Every helper in the snapshot
// contributes a deterministic power-of-two share of the returned checksum,
// so a changed result flags changed behavior. The full checksum is
// 2^26 - 1: twenty-six checks, one per helper behavior.

pub fn num_example() -> I64 {
    var total: I64 = 0

    // Integer limits: each contributes when it equals its exact boundary.
    if num.i8_min() == -128 { total = total + 1 }
    if num.i8_max() == 127 { total = total + 2 }
    if num.i16_min() == -32768 { total = total + 4 }
    if num.i16_max() == 32767 { total = total + 8 }
    if num.i32_min() == -2147483648 { total = total + 16 }
    if num.i32_max() == 2147483647 { total = total + 32 }
    if num.i64_min() == -9223372036854775808 { total = total + 64 }
    if num.i64_max() == 9223372036854775807 { total = total + 128 }
    if num.u8_max() == 255 { total = total + 256 }
    if num.u16_max() == 65535 { total = total + 512 }
    if num.u32_max() == 4294967295 { total = total + 1024 }
    if num.u64_max() == 18446744073709551615 { total = total + 2048 }

    // Checked absolute value: a magnitude becomes Some, the minimum's
    // impossible negation becomes None.
    match num.i8_abs_checked(-100) {
        Some(v) => {
            if v == 100 { total = total + 4096 }
        }
        None => { total = total + 0 }
    }
    match num.i8_abs_checked(num.i8_min()) {
        None => { total = total + 8192 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    match num.i16_abs_checked(-300) {
        Some(v) => {
            if v == 300 { total = total + 32768 }
        }
        None => { total = total + 0 }
    }
    match num.i16_abs_checked(num.i16_min()) {
        None => { total = total + 65536 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    match num.i32_abs_checked(-70000) {
        Some(v) => {
            if v == 70000 { total = total + 262144 }
        }
        None => { total = total + 0 }
    }
    match num.i32_abs_checked(num.i32_min()) {
        None => { total = total + 524288 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    match num.i64_abs_checked(-100) {
        Some(v) => {
            if v == 100 { total = total + 2097152 }
        }
        None => { total = total + 0 }
    }
    match num.i64_abs_checked(num.i64_min()) {
        None => { total = total + 4194304 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    match num.i64_abs_checked(42) {
        Some(v) => {
            if v == 42 { total = total + 16777216 }
        }
        None => { total = total + 0 }
    }

    // Wrapping absolute value: the minimum's negation wraps back to the
    // minimum itself.
    if num.i8_abs_wrapping(num.i8_min()) == num.i8_min() { total = total + 16384 }
    if num.i8_abs_wrapping(-42) == 42 { total = total + 0 }
    if num.i16_abs_wrapping(num.i16_min()) == num.i16_min() { total = total + 131072 }
    if num.i32_abs_wrapping(num.i32_min()) == num.i32_min() { total = total + 1048576 }
    if num.i64_abs_wrapping(num.i64_min()) == num.i64_min() { total = total + 8388608 }
    if num.i64_abs_wrapping(-42) == 42 { total = total + 33554432 }

    return total
}
