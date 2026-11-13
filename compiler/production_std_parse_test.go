package compiler

import (
	"path/filepath"
	"testing"
)

// std.parse v1 is a byte cursor over owned input. These checks pin the public
// spans, on-demand positions, exact token boundaries, and positioned error
// categories through the production compiler.
const stdParseProgram = `module hello.main

import std.parse as parse

fn error_offset(result: Result(U64, parse.ParseError)) -> U64 {
    return match result {
        Ok(_) => 0
        Err(error) => error.at.offset
    }
}

fn step_value(step: parse.Step(U64)) -> U64 {
    return step.value
}

fn span_end(span: parse.Span) -> U64 {
    return span.end
}

fn place_line(place: parse.Position) -> U64 {
    return place.line
}

fn check_first() -> Bool {
    let first = match parse.Cursor.text("+12x").parse_u64() {
        Ok(step) => step
        Err(_) => return false
    }
    if step_value(first) != 12 { return false }
    if first.span.start != 0 || span_end(first.span) != 3 { return false }
    if first.cursor.offset() != 3 { return false }
    if first.cursor.peek() != Some(120) { return false }
    if first.cursor.peek_at(1) != None { return false }
    if first.cursor.rest() != "x" { return false }
    let taken = match first.cursor.take_bytes(1) {
        Ok(step) => step
        Err(_) => return false
    }
    if taken.value != "x" { return false }
    if taken.span.start != 3 || taken.span.end != 4 { return false }
    if !taken.cursor.at_end() { return false }
    return true
}

fn check_whitespace() -> Bool {
    let cursor = parse.Cursor.text(" \t\r\n12").skip_whitespace()
    if cursor.offset() != 4 { return false }
    let step = match cursor.parse_u64() {
        Ok(value) => value
        Err(_) => return false
    }
    if step.value != 12 { return false }
    if step.span.start != 4 || step.span.end != 6 { return false }
    if !step.cursor.at_end() { return false }
    return true
}

fn check_signed() -> Bool {
    let step = match parse.Cursor.text("-9223372036854775808").parse_i64() {
        Ok(value) => value
        Err(_) => return false
    }
    if step.value != -9223372036854775808 { return false }
    if step.span.start != 0 || step.span.end != 20 { return false }
    return true
}

fn check_position() -> Bool {
    let advanced = match parse.Cursor.text("a\nbc").advance(3) {
        Ok(value) => value
        Err(_) => return false
    }
    let place = advanced.position()
    if place.offset != 3 || place_line(place) != 2 || place.column != 2 { return false }
    let crlf = match parse.Cursor.text("a\r\nb").advance(3) {
        Ok(value) => value
        Err(_) => return false
    }
    let after_crlf = crlf.position()
    if after_crlf.offset != 3 || after_crlf.line != 2 || after_crlf.column != 1 { return false }
    return true
}

fn check_advance_failure() -> Bool {
    let result = parse.Cursor.text("a").advance(2)
    match result {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 || error.at.line != 1 || error.at.column != 1 { return false }
            match error.kind {
                UnexpectedEnd => { return true }
                _ => { return false }
            }
        }
    }
    return false
}

fn check_expected_byte() -> Bool {
    let result = parse.Cursor.text("x").expect_byte(44)
    match result {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 || error.at.line != 1 || error.at.column != 1 { return false }
            match error.kind {
                UnexpectedByte(expected) => { return expected == 44 }
                _ => { return false }
            }
        }
    }
    return false
}

fn check_integer_errors() -> Bool {
    let overflow = parse.parse_u64("18446744073709551616")
    match overflow {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 || error.at.line != 1 || error.at.column != 1 { return false }
            match error.kind {
                InvalidInteger(_) => {}
                _ => { return false }
            }
        }
    }
    let minus = parse.parse_u64("-1")
    match minus {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 || error.at.line != 1 || error.at.column != 1 { return false }
            match error.kind {
                InvalidInteger(_) => {}
                _ => { return false }
            }
        }
    }
    return true
}

fn check_trailing() -> Bool {
    let result = parse.parse_u64("12x")
    match result {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 2 || error.at.line != 1 || error.at.column != 3 { return false }
            match error.kind {
                TrailingInput => { return true }
                _ => { return false }
            }
        }
    }
    return false
}

fn check_expected_digit() -> Bool {
    let result = parse.Cursor.text("x").parse_u64()
    match result {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 || error.at.line != 1 || error.at.column != 1 { return false }
            match error.kind {
                ExpectedDigit => { return true }
                _ => { return false }
            }
        }
    }
    return false
}

fn check_words() -> Bool {
    let word = match parse.parse_word("abc_12") {
        Ok(value) => value
        Err(_) => return false
    }
    if word != "abc_12" { return false }
    let yes = match parse.parse_bool("true") {
        Ok(value) => value
        Err(_) => return false
    }
    if !yes { return false }
    let no = match parse.parse_bool("false") {
        Ok(value) => value
        Err(_) => return false
    }
    if no { return false }
    let bad_bool = parse.parse_bool("truex")
    match bad_bool {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 || error.at.line != 1 || error.at.column != 1 { return false }
            match error.kind {
                InvalidLiteral => {}
                _ => { return false }
            }
        }
    }
    let bad_word = parse.parse_word("9abc")
    match bad_word {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 { return false }
            match error.kind {
                ExpectedWord => { return true }
                _ => { return false }
            }
        }
    }
    return false
}

fn check_whole() -> Bool {
    let number = match parse.parse_u64("12") {
        Ok(value) => value
        Err(_) => return false
    }
    if number != 12 { return false }
    let signed = match parse.parse_i64("-7") {
        Ok(value) => value
        Err(_) => return false
    }
    if signed != -7 { return false }
    let empty = parse.parse_u64("")
    match empty {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 { return false }
            match error.kind {
                UnexpectedEnd => {}
                _ => { return false }
            }
        }
    }
    let spaced = parse.parse_u64(" 1")
    match spaced {
        Ok(_) => { return false }
        Err(error) => {
            if error.at.offset != 0 { return false }
            match error.kind {
                ExpectedDigit => {}
                _ => { return false }
            }
        }
    }
    if error_offset(parse.parse_u64("x")) != 0 { return false }
    return true
}

pub fn main() -> I32 {
    if !check_first() { return 1 }
    if !check_whitespace() { return 2 }
    if !check_signed() { return 3 }
    if !check_position() { return 4 }
    if !check_advance_failure() { return 5 }
    if !check_expected_byte() { return 6 }
    if !check_integer_errors() { return 7 }
    if !check_trailing() { return 8 }
    if !check_expected_digit() { return 9 }
    if !check_words() { return 10 }
    if !check_whole() { return 11 }
    return 0
}
`

func TestStdParseProductionQualification(t *testing.T) {
	t.Parallel()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, "cc", root)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(root, "sysroot")), map[string]string{
		"alder.toml":  snapshotProjectManifest,
		"src/main.al": stdParseProgram,
	}, "run")
	if result.status != 0 {
		t.Fatalf("std.parse program failed: %+v", result)
	}
}
