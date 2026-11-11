module hello.std_text_example

import std.bytes { of_byte }
import std.text { StringBuilder, validate, from_utf8, scalar_at, scalar_count, find, split, replace }

// The executable std.text v1 snapshot example. Fixed inputs only; every
// stage contributes a deterministic share of the returned checksum.

pub fn std_text_example() -> U64 {
    var total: U64 = 0

    // Validation counts scalars, with the offset on rejection.
    let value: Bytes = "h\xc3\xa9llo".to_bytes()
    var bad: Bool = false
    match validate(value) {
        Ok(count) => {
            if count == 5 { total = total + 1 }
        }
        Err(failure) => {
            match failure {
                InvalidUtf8(_) => { bad = true }
                InvalidScalar(_) => { bad = true }
            }
        }
    }
    if bad { total = total - 1000000 }

    // The offset in the error is the first offending byte.
    let cut: Bytes = "\xc3"
    var cut_at: U64 = 0
    var cut_bad: Bool = false
    match validate(cut) {
        Ok(_) => { cut_bad = true }
        Err(failure) => {
            match failure {
                InvalidUtf8(at) => { cut_at = at }
                InvalidScalar(_) => { cut_bad = true }
            }
        }
    }
    if cut_bad { total = total - 1000000 }
    if cut_at == 0 { total = total + 2 }

    // Scalars: the two-byte sequence decodes as one value of size two.
    var scalar_bad: Bool = false
    match scalar_at("h\xc3\xa9llo", 1) {
        Some(one) => {
            if one.value == 233 { total = total + 4 }
            if one.size == 2 { total = total + 8 }
        }
        None => { scalar_bad = true }
    }
    if scalar_bad { total = total - 1000000 }
    if scalar_count("h\xc3\xa9llo") == 5 { total = total + 16 }

    // Exact search, split, and replace.
    var found: U64 = 0
    var find_bad: Bool = false
    match find("hello world hello", "world") {
        Some(at) => { found = at }
        None => { find_bad = true }
    }
    if find_bad { total = total - 1000000 }
    if found == 6 { total = total + 32 }
    let pieces = split("a:b::c", ":")
    if pieces.len() == 4 { total = total + 64 }
    if replace("abcabc", "abc", "x") == "xx" { total = total + 128 }

    // The checked conversion round-trips text through bytes.
    var round_bad: Bool = false
    match from_utf8(value) {
        Ok(text) => {
            if text == "h\xc3\xa9llo" { total = total + 256 }
        }
        Err(_) => { round_bad = true }
    }
    if round_bad { total = total - 1000000 }

    // The builder appends text and one scalar; a surrogate is rejected.
    var built = StringBuilder.new()
    built = built.push_text("a")
    var push_bad: Bool = false
    match built.push_scalar(233) {
        Ok(next) => { built = next }
        Err(_) => { push_bad = true }
    }
    if push_bad { total = total - 1000000 }
    if built.finish() == "a\xc3\xa9" { total = total + 512 }
    var reject_value: U32 = 0
    var reject_bad: Bool = false
    match built.push_scalar(55296) {
        Ok(_) => { reject_bad = true }
        Err(failure) => {
            match failure {
                InvalidScalar(surrogate) => { reject_value = surrogate }
                InvalidUtf8(_) => { reject_bad = true }
            }
        }
    }
    if reject_bad { total = total - 1000000 }
    if reject_value == 55296 { total = total + 1024 }

    // Bytes stay available through std.bytes when needed.
    if of_byte(65) == "A".to_bytes() { total = total + 2048 }

    return total
}
