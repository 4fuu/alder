// Final S0 command/response protocol. The C host owns argv, source snapshots,
// and byte sinks; this layer owns compiler status, diagnostics, and artifacts.
import c alderhost_command: fn() -> U64
import c alderhost_format_json: fn() -> Bool
import c alderhost_output_path_len: fn() -> U64
import c alderhost_output_path_byte: fn(U64) -> U8
import c alderhost_output_mode: fn(U64) -> Bool
import c alderhost_output_failed: fn() -> Bool
import c alderhost_response_reset: fn() -> Bool

type DriverPosition {
    line: U64
    column: U64
}

fn driver_json() -> Bool { return unsafe c { alderhost_format_json() } }
fn driver_command() -> U64 { return unsafe c { alderhost_command() } }

fn driver_select(mode: U64) -> Bool {
    return unsafe c { alderhost_output_mode(mode) }
}

fn driver_reset_response() -> Bool {
    return unsafe c { alderhost_response_reset() }
}

fn driver_out_json_byte(byte: U8) -> Bool {
    if byte == 34 { return out_string("\\\"") }
    if byte == 92 { return out_string("\\\\") }
    if byte == 8 { return out_string("\\b") }
    if byte == 9 { return out_string("\\t") }
    if byte == 10 { return out_string("\\n") }
    if byte == 12 { return out_string("\\f") }
    if byte == 13 { return out_string("\\r") }
    if byte < 32 {
        if !out_string("\\u00") { return false }
        return out_hex_nibble(byte / 16) && out_hex_nibble(byte % 16)
    }
    return out(byte)
}

fn driver_out_json_bytes(bytes: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if !driver_out_json_byte(__s0_buffer_get(U8, bytes, at)) { return false }
        at = at + 1
    }
    return true
}

fn driver_out_json_path(state: State, source: U64) -> Bool {
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    return driver_out_json_bytes(state.paths, rec.path_start, rec.path_end)
}

fn driver_out_json_output_path() -> Bool {
    var at: U64 = 0
    let end = unsafe c { alderhost_output_path_len() }
    while at < end {
        if !driver_out_json_byte(unsafe c { alderhost_output_path_byte(at) }) { return false }
        at = at + 1
    }
    return true
}

fn driver_utf8_continuation(byte: U8) -> Bool { return byte >= 128 && byte < 192 }

fn driver_utf8_width(state: State, source: SourceRec, at: U64) -> U64 {
    let first = text_byte(state, source, at)
    let end = source.text_end - source.text_start
    if first < 128 { return 1 }
    if first >= 194 && first < 224 && at + 1 < end && driver_utf8_continuation(text_byte(state, source, at + 1)) { return 2 }
    if first >= 224 && first < 240 && at + 2 < end {
        let second = text_byte(state, source, at + 1)
        let third = text_byte(state, source, at + 2)
        if driver_utf8_continuation(second) && driver_utf8_continuation(third) && (first != 224 || second >= 160) && (first != 237 || second < 160) { return 3 }
    }
    if first >= 240 && first < 245 && at + 3 < end {
        let second = text_byte(state, source, at + 1)
        if driver_utf8_continuation(second) && driver_utf8_continuation(text_byte(state, source, at + 2)) && driver_utf8_continuation(text_byte(state, source, at + 3)) && (first != 240 || second >= 144) && (first != 244 || second < 144) { return 4 }
    }
    return 1
}

fn driver_position(state: State, source_id: U64, offset: U64) -> DriverPosition {
    let source = __s0_buffer_get(SourceRec, state.sources, source_id)
    var line: U64 = 1
    var column: U64 = 1
    var at: U64 = 0
    while at < offset {
        let byte = text_byte(state, source, at)
        if byte == 10 {
            line = line + 1
            column = 1
            at = at + 1
        } else {
            let width = driver_utf8_width(state, source, at)
            if at + width > offset { return DriverPosition(line: line, column: column) }
            column = column + 1
            at = at + width
        }
    }
    return DriverPosition(line: line, column: column)
}

fn driver_out_range(state: State, source: U64, start: U64, end: U64) -> Bool {
    let first = driver_position(state, source, start)
    let last = driver_position(state, source, end)
    if !out_string("{\"path\":\"") || !driver_out_json_path(state, source) || !out_string("\",\"startByte\":") || !out_u64(start) || !out_string(",\"endByte\":") || !out_u64(end) { return false }
    if !out_string(",\"start\":{\"line\":") || !out_u64(first.line) || !out_string(",\"column\":") || !out_u64(first.column) || !out_string("},\"end\":{\"line\":") || !out_u64(last.line) || !out_string(",\"column\":") || !out_u64(last.column) { return false }
    return out_string("}}")
}

fn driver_out_human_range(state: State, source: U64, start: U64) -> Bool {
    let position = driver_position(state, source, start)
    return out_path(state, source) && out(58) && out_u64(position.line) && out(58) && out_u64(position.column)
}

fn driver_out_lex_message(kind: U64) -> Bool {
    if kind == 1 { return out_string("semicolons are not supported") }
    if kind == 2 { return out_string("unexpected character") }
    if kind == 3 { return out_string("invalid exponent") }
    if kind == 4 { return out_string("invalid string escape") }
    if kind == 5 { return out_string("unterminated string") }
    return out_string("unterminated block comment")
}

fn driver_out_parse_message(kind: U64) -> Bool {
    if kind == 1 { return out_string("expected declaration") }
    if kind == 3 { return out_string("expected identifier") }
    if kind == 5 { return out_string("expected type") }
    if kind == 12 { return out_string("expected expression") }
    if kind == 14 { return out_string("invalid assignment target") }
    return out_string("invalid source syntax")
}

fn driver_out_check_message(kind: U64) -> Bool {
    if kind == 1 { return out_string("duplicate declaration") }
    if kind == 2 { return out_string("reserved declaration name") }
    if kind == 3 { return out_string("duplicate type parameter") }
    if kind == 4 { return out_string("unknown type") }
    if kind == 18 { return out_string("unknown identifier") }
    if kind == 19 { return out_string("return type mismatch") }
    if kind == 65 { return out_string("condition must have type Bool") }
    if kind == 67 { return out_string("valued function may fall through") }
    if kind == 68 { return out_string("unreachable statement") }
    if kind == 79 { return out_string("nonexhaustive match") }
    if kind == 87 { return out_string("source form is outside the supported S0 contract") }
    if !out_string("semantic error (checker diagnostic ") || !out_u64(kind) { return false }
    return out(41)
}

fn driver_out_message(phase: U64, kind: U64) -> Bool {
    if phase == 1 { return driver_out_lex_message(kind) }
    if phase == 2 { return driver_out_parse_message(kind) }
    return driver_out_check_message(kind)
}

fn driver_out_code(phase: U64) -> Bool {
    if phase == 1 { return out_string("LEX0001") }
    if phase == 2 { return out_string("SYN0001") }
    return out_string("SEM0001")
}

fn driver_emit_human_diagnostic(state: State, phase: U64, kind: U64, source: U64, start: U64, related_source: U64, related_start: U64, related_end: U64) -> Bool {
    if !driver_select(1) || !driver_out_human_range(state, source, start) || !out_string(": error[") || !driver_out_code(phase) || !out_string("]: ") || !driver_out_message(phase, kind) || !out(10) { return false }
    if related_start != 0 || related_end != 0 {
        if !driver_out_human_range(state, related_source, related_start) || !out_string(": related: first declaration is here\n") { return false }
    }
    if phase == 3 && kind == 1 { return out_string("note: top-level names share one global namespace\n") }
    if phase == 3 && kind == 3 { return out_string("note: type parameter names must be unique within their declaration\n") }
    return true
}

fn driver_emit_json_diagnostic(state: State, phase: U64, kind: U64, source: U64, start: U64, end: U64, related_source: U64, related_start: U64, related_end: U64) -> Bool {
    if !driver_select(0) || !out_string("{\"version\":1,\"command\":\"") { return false }
    if driver_command() == 1 { if !out_string("check") { return false } } else { if !out_string("compile") { return false } }
    if !out_string("\",\"success\":false,\"diagnostics\":[{\"code\":\"") || !driver_out_code(phase) || !out_string("\",\"severity\":\"error\",\"message\":\"") || !driver_out_message(phase, kind) || !out_string("\",\"range\":") || !driver_out_range(state, source, start, end) || !out_string(",\"related\":[") { return false }
    if related_start != 0 || related_end != 0 {
        if !out_string("{\"message\":\"first declaration is here\",\"range\":") || !driver_out_range(state, related_source, related_start, related_end) || !out(125) { return false }
    }
    if !out_string("],\"notes\":[") { return false }
    if phase == 3 && kind == 1 { if !out_string("\"top-level names share one global namespace\"") { return false } }
    if phase == 3 && kind == 3 { if !out_string("\"type parameter names must be unique within their declaration\"") { return false } }
    return out_string("]}]}\n")
}

fn driver_diagnostic(state: State, phase: U64, kind: U64, source: U64, start: U64, end: U64, related_source: U64, related_start: U64, related_end: U64) -> I32 {
    var wrote = false
    if driver_json() { wrote = driver_emit_json_diagnostic(state, phase, kind, source, start, end, related_source, related_start, related_end) }
    else { wrote = driver_emit_human_diagnostic(state, phase, kind, source, start, related_source, related_start, related_end) }
    if !wrote { return 3 }
    return 1
}

fn driver_lex_diagnostic(state: State) -> I32 {
    let rec = __s0_buffer_get(LexDiagRec, state.diagnostics, 0)
    return driver_diagnostic(state, 1, rec.kind, rec.source, rec.start, rec.end, 0, 0, 0)
}

fn driver_parse_diagnostic(state: State, store: ParseStore) -> I32 {
    let rec = __s0_buffer_get(ParseDiagRec, store.diagnostics, 0)
    return driver_diagnostic(state, 2, rec.kind, rec.source, rec.start, rec.end, 0, 0, 0)
}

fn driver_check_diagnostic(state: State, store: CheckStore) -> I32 {
    let rec = __s0_buffer_get(CheckDiagRec, store.diagnostics, 0)
    return driver_diagnostic(state, 3, rec.kind, rec.source, rec.start, rec.end, rec.related_source, rec.related_start, rec.related_end)
}

fn driver_failure(status: U64, kind: String, message: String) -> I32 {
    if driver_json() {
        if !driver_reset_response() || !driver_select(0) || !out_string("{\"version\":1,\"command\":\"") { return 3 }
        if driver_command() == 1 { if !out_string("check") { return 3 } } else { if !out_string("compile") { return 3 } }
        if !out_string("\",\"success\":false,\"diagnostics\":[],\"failure\":{\"kind\":\"") || !out_string(kind) || !out_string("\",\"message\":\"") || !out_string(message) || !out_string("\"}}\n") { return 3 }
    } else {
        if !driver_select(1) || !out_string("alder: ") || !out_string(message) || !out(10) { return 3 }
    }
    if status == 3 { return 3 }
    return 4
}

fn driver_storage_error() -> I32 { return driver_failure(3, "io", "compiler storage failure") }
fn driver_internal_error() -> I32 { return driver_failure(4, "internal", "internal compiler failure") }

fn driver_success_check() -> I32 {
    if driver_json() {
        if !driver_select(0) || !out_string("{\"version\":1,\"command\":\"check\",\"success\":true,\"diagnostics\":[]}\n") { return 3 }
    }
    return 0
}

fn driver_artifact_start(kind: String) -> Bool {
    if driver_json() {
        if !driver_select(0) || !out_string("{\"version\":1,\"command\":\"compile\",\"success\":true,\"diagnostics\":[],\"artifact\":{\"kind\":\"") || !out_string(kind) { return false }
        if unsafe c { alderhost_output_path_len() } != 0 {
            if !out_string("\",\"path\":\"") || !driver_out_json_output_path() || !out_string("\"}}\n") { return false }
        } else {
            if !out_string("\",\"content\":\"") { return false }
        }
    }
    return driver_select(2)
}

fn driver_artifact_finish() -> Bool {
    if !driver_json() || unsafe c { alderhost_output_path_len() } != 0 { return true }
    return driver_select(0) && out_string("\"}}\n")
}

fn driver_output_failed() -> Bool { return unsafe c { alderhost_output_failed() } }
