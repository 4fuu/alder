module hello.std_parse_example

import std.parse as parse

// The executable std.parse v1 snapshot example. Each successful observation
// contributes one bit to the checksum; any mismatch leaves the checksum short.
pub fn std_parse_example() -> U64 {
    var total: U64 = 0
    let first = match parse.Cursor.text(" +12,rest").skip_whitespace().parse_u64() {
        Ok(step) => step
        Err(_) => return 0
    }
    if first.value == 12 { total = total + 1 }
    if first.span.start == 1 && first.span.end == 4 { total = total + 2 }
    if first.cursor.peek() == Some(44) { total = total + 4 }
    let comma = match first.cursor.take_bytes(1) {
        Ok(step) => step
        Err(_) => return 0
    }
    if comma.value == "," { total = total + 8 }
    let unsigned = match parse.parse_u64("42") {
        Ok(value) => value
        Err(_) => return 0
    }
    if unsigned == 42 { total = total + 16 }
    let signed = match parse.parse_i64("-7") {
        Ok(value) => value
        Err(_) => return 0
    }
    if signed == -7 { total = total + 32 }
    let no = match parse.parse_bool("false") {
        Ok(value) => value
        Err(_) => return 0
    }
    if !no { total = total + 64 }
    let word = match parse.parse_word("abc_12") {
        Ok(value) => value
        Err(_) => return 0
    }
    if word == "abc_12" { total = total + 128 }
    let trailing = parse.parse_u64("12x")
    match trailing {
        Ok(_) => { return 0 }
        Err(error) => {
            if error.at.offset == 2 {
                match error.kind {
                    TrailingInput => { total = total + 256 }
                    _ => { return 0 }
                }
            } else {
                return 0
            }
        }
    }
    let advanced = match parse.Cursor.text("a\nb").advance(2) {
        Ok(cursor) => cursor
        Err(_) => return 0
    }
    let place = advanced.position()
    if place.offset == 2 && place.line == 2 && place.column == 1 { total = total + 512 }
    let expected = parse.parse_u64("x")
    match expected {
        Ok(_) => { return 0 }
        Err(error) => {
            match error.kind {
                ExpectedDigit => { total = total + 1024 }
                _ => { return 0 }
            }
        }
    }
    return total
}
