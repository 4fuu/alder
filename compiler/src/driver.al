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

fn driver_out_source_text(state: State, source: U64, start: U64, end: U64, json: Bool) -> Bool {
    let rec = __s0_buffer_get(SourceRec, state.sources, source)
    var at = start
    while at < end {
        let byte = text_byte(state, rec, at)
        if json { if !driver_out_json_byte(byte) { return false } }
        else { if !out(byte) { return false } }
        at = at + 1
    }
    return true
}

fn driver_node_at(state: State, parse: ParseStore, source: U64, start: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(SyntaxRec, parse.nodes) {
        let node = __s0_buffer_get(SyntaxRec, parse.nodes, at)
        if node.source == source && node.token != 0 {
            let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
            if token.start == start && node.name_end > node.name_start { return at + 1 }
        }
        at = at + 1
    }
    return 0
}

fn driver_out_node_name(state: State, parse: ParseStore, source: U64, start: U64, fallback_end: U64, json: Bool) -> Bool {
    let found = driver_node_at(state, parse, source, start)
    if found != 0 {
        let node = __s0_buffer_get(SyntaxRec, parse.nodes, found - 1)
        return driver_out_source_text(state, node.source, node.name_start, node.name_end, json)
    }
    return driver_out_source_text(state, source, start, fallback_end, json)
}

fn driver_out_function_for_body(state: State, parse: ParseStore, source: U64, start: U64, json: Bool) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(SyntaxRec, parse.nodes) {
        let node = __s0_buffer_get(SyntaxRec, parse.nodes, at)
        if node.kind == 12 && node.source == source && node.children != 0 {
            let body_link = __s0_buffer_get(SyntaxLinkRec, parse.links, node.children - 1)
            let body = __s0_buffer_get(SyntaxRec, parse.nodes, body_link.node - 1)
            let token = __s0_buffer_get(TokenRec, state.tokens, body.token - 1)
            if token.start == start { return driver_out_source_text(state, source, node.name_start, node.name_end, json) }
        }
        at = at + 1
    }
    return out_string("<unknown>")
}

fn driver_out_lex_message(state: State, kind: U64, source: U64, start: U64, json: Bool) -> Bool {
    if kind == 1 { return out_string("semicolons are not supported") }
    if kind == 2 { return out_string("unexpected character") }
    if kind == 3 { return out_string("invalid exponent") }
    if kind == 4 {
        if !out_string("invalid escape ") { return false }
        let rec = __s0_buffer_get(SourceRec, state.sources, source)
        var at = start + 1
        while at + 1 < rec.text_end - rec.text_start {
            if text_byte(state, rec, at) == 92 { return driver_out_source_text(state, source, at, at + 2, json) }
            at = at + 1
        }
        return false
    }
    if kind == 5 { return out_string("unterminated string") }
    return out_string("unterminated block comment")
}

fn driver_out_parse_message(kind: U64) -> Bool {
    if kind == 1 { return out_string("expected declaration") }
    if kind == 3 { return out_string("expected identifier") }
    if kind == 5 { return out_string("expected type") }
    if kind == 10 { return out_string("compile-time type parameters must precede runtime parameters") }
    if kind == 11 { return out_string("statements must be separated by a physical line break") }
    if kind == 12 { return out_string("expected expression") }
    if kind == 14 { return out_string("invalid assignment target") }
    return out_string("invalid source syntax")
}

fn driver_out_diagnostic_type(kind: U64, target: U64) -> Bool {
    if kind == 8 {
        if !out(91) || !driver_out_diagnostic_type(1, target) { return false }
        return out(93)
    }
    if kind != 1 { return out_string("<unknown>") }
    if target == 1 { return out_string("Bool") }
    if target == 2 { return out_string("I8") }
    if target == 3 { return out_string("I16") }
    if target == 4 { return out_string("I32") }
    if target == 5 { return out_string("I64") }
    if target == 6 { return out_string("U8") }
    if target == 7 { return out_string("U16") }
    if target == 8 { return out_string("U32") }
    if target == 9 { return out_string("U64") }
    if target == 10 { return out_string("F32") }
    if target == 11 { return out_string("F64") }
    return out_string("Unit")
}

fn driver_out_message_quote(json: Bool) -> Bool {
    if json { return out_string("\\\"") }
    return out(34)
}

fn driver_out_declaration_kind(kind: U64) -> Bool {
    if kind == 1 { return out_string("import") }
    if kind == 12 { return out_string("function") }
    return out_string("type")
}

fn driver_same_declaration_kind(left: U64, right: U64) -> Bool {
    if left == right { return true }
    return (left == 2 || left == 3) && (right == 2 || right == 3)
}

fn driver_out_check_message(state: State, parse: ParseStore, kind: U64, source: U64, start: U64, end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64, json: Bool) -> Bool {
    if kind == 1 {
        if driver_same_declaration_kind(detail_a, detail_b) {
            if detail_a == 1 { if !out_string("duplicate import name ") { return false } }
            else { if !out_string("duplicate or reserved ") || !driver_out_declaration_kind(detail_a) || !out_string(" name ") { return false } }
            if !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) { return false }
            return driver_out_message_quote(json)
        }
        if !out_string("top-level ") || !driver_out_declaration_kind(detail_a) || !out_string(" name ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) || !out_string(" conflicts with earlier ") || !driver_out_declaration_kind(detail_b) { return false }
        return out_string(" declaration")
    }
    if kind == 2 {
        if !out_string("duplicate or reserved type name ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) { return false }
        return driver_out_message_quote(json)
    }
    if kind == 3 { return out_string("duplicate type parameter") }
    if kind == 4 { if !out_string("unknown type ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 9 { if !out_string("type ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" participates in a value-type cycle") }
    if kind == 10 { if !out_string("slice element type ") || !driver_out_diagnostic_type(detail_a, detail_b) { return false }
        return out_string(" contains a slice or reference (M4 restriction)") }
    if kind == 12 { if !out_string("Map key type ") || !driver_out_diagnostic_type(detail_a, detail_b) { return false }
        return out_string(" is not supported (unsigned integers, Bool, and structs/enums of those only)") }
    if kind == 13 { if !out_string("Map value type ") || !driver_out_diagnostic_type(detail_a, detail_b) { return false }
        return out_string(" must be copy-trivial (no slices, references, maps, or domain handles)") }
    if kind == 15 { if !out_string("import ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(": parameter type must be a primitive or Ptr(primitive)") }
    if kind == 18 { if !out_string("unknown name ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 19 { if !out_string("return: type mismatch: expected ") || !driver_out_diagnostic_type(detail_a, detail_b) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(detail_c, detail_d) }
    if kind == 21 { if !out_string("literal ") || !driver_out_source_text(state, source, start, end, json) { return false }
        if !out_string(" is out of range for ") { return false }
        return driver_out_diagnostic_type(detail_a, detail_b) }
    if kind == 22 { if !out_string("binding name ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is reserved") }
    if kind == 23 { if !out_string("binding: type mismatch: expected ") || !driver_out_diagnostic_type(detail_a, detail_b) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(detail_c, detail_d) }
    if kind == 25 { if !driver_out_message_quote(json) || !out_string("Unit") || !driver_out_message_quote(json) { return false }
        return out_string(" is a type, not a value") }
    if kind == 26 { return out_string("domain marks cannot be bound; use them directly (the current MIR profile requires the reset mark to be the direct domain.mark result)") }
    if kind == 27 { if !out_string("name ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is already bound in this function") }
    if kind == 28 { if !out_string("cannot assign to immutable binding ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 37 { if !out_string("operator ") || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return out_string(" requires integer operands (float arithmetic is not available in the current MIR profile)") }
    if kind == 39 { if !out_string("function ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" must be called") }
    if kind == 40 { if !out_string("unknown name ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 65 { return out_string("condition must have type Bool") }
    if kind == 67 { if !out_string("function ") || !driver_out_message_quote(json) || !driver_out_function_for_body(state, parse, source, start, json) || !driver_out_message_quote(json) { return false }
        return out_string(" may fall off the end without returning a value") }
    if kind == 68 { return out_string("unreachable statement") }
    if kind == 69 { return out_string("using inside a loop is rejected (a cleanup scope cannot re-begin while active)") }
    if kind == 76 { if !out_string("name ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, detail_a, detail_b, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is already bound in this function") }
    if kind == 79 { if !out_string("match is not exhaustive: variant ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, detail_a, detail_b, json) || !driver_out_message_quote(json) || !out_string(" of ") || !driver_out_source_text(state, source, detail_c, detail_d, json) { return false }
        return out_string(" is not covered") }
    if kind == 80 { return out_string("try requires a function returning Result") }
    if kind == 82 { if !out_string("try error type ") || !driver_out_diagnostic_type(detail_a, detail_b) || !out_string(" does not match function error type ") { return false }
        return driver_out_diagnostic_type(detail_c, detail_d) }
    if kind == 84 { if !out_string("index: type mismatch: expected ") || !driver_out_diagnostic_type(detail_a, detail_b) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(detail_c, detail_d) }
    if kind == 85 { if !out_string("cleanup function parameter: type mismatch: expected ") || !driver_out_diagnostic_type(detail_a, detail_b) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(detail_c, detail_d) }
    if kind == 87 { return out_string("source form is outside the supported S0 contract") }
    if !out_string("semantic error (checker diagnostic ") || !out_u64(kind) { return false }
    return out(41)
}

fn driver_out_message(state: State, parse: ParseStore, phase: U64, kind: U64, source: U64, start: U64, end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64, json: Bool) -> Bool {
    if phase == 1 { return driver_out_lex_message(state, kind, source, start, json) }
    if phase == 2 { return driver_out_parse_message(kind) }
    return driver_out_check_message(state, parse, kind, source, start, end, detail_a, detail_b, detail_c, detail_d, json)
}

fn driver_out_code(phase: U64) -> Bool {
    if phase == 1 { return out_string("LEX0001") }
    if phase == 2 { return out_string("SYN0001") }
    return out_string("SEM0001")
}

fn driver_emit_human_diagnostic(state: State, parse: ParseStore, phase: U64, kind: U64, source: U64, start: U64, end: U64, related_source: U64, related_start: U64, related_end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> Bool {
    if !driver_select(1) || !driver_out_human_range(state, source, start) || !out_string(": error[") || !driver_out_code(phase) || !out_string("]: ") || !driver_out_message(state, parse, phase, kind, source, start, end, detail_a, detail_b, detail_c, detail_d, false) || !out(10) { return false }
    if related_start != 0 || related_end != 0 {
        if !driver_out_human_range(state, related_source, related_start) || !out_string(": related: first ") || !driver_out_declaration_kind(detail_b) || !out_string(" declaration of \"") || !driver_out_node_name(state, parse, source, start, end, false) || !out_string("\" is here\n") { return false }
    }
    return true
}

fn driver_emit_json_diagnostic(state: State, parse: ParseStore, phase: U64, kind: U64, source: U64, start: U64, end: U64, related_source: U64, related_start: U64, related_end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> Bool {
    if !driver_select(0) || !out_string("{\"version\":1,\"command\":\"") { return false }
    if driver_command() == 1 { if !out_string("check") { return false } } else { if !out_string("compile") { return false } }
    if !out_string("\",\"success\":false,\"diagnostics\":[{\"code\":\"") || !driver_out_code(phase) || !out_string("\",\"severity\":\"error\",\"message\":\"") || !driver_out_message(state, parse, phase, kind, source, start, end, detail_a, detail_b, detail_c, detail_d, true) || !out_string("\",\"range\":") || !driver_out_range(state, source, start, end) || !out_string(",\"related\":[") { return false }
    if related_start != 0 || related_end != 0 {
        if !out_string("{\"message\":\"first ") || !driver_out_declaration_kind(detail_b) || !out_string(" declaration of ") || !driver_out_message_quote(true) || !driver_out_node_name(state, parse, source, start, end, true) || !driver_out_message_quote(true) || !out_string(" is here\",\"range\":") || !driver_out_range(state, related_source, related_start, related_end) || !out(125) { return false }
    }
    return out_string("],\"notes\":[]}]}\n")
}

fn driver_diagnostic(state: State, parse: ParseStore, phase: U64, kind: U64, source: U64, start: U64, end: U64, related_source: U64, related_start: U64, related_end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> I32 {
    var wrote = false
    if driver_json() { wrote = driver_emit_json_diagnostic(state, parse, phase, kind, source, start, end, related_source, related_start, related_end, detail_a, detail_b, detail_c, detail_d) }
    else { wrote = driver_emit_human_diagnostic(state, parse, phase, kind, source, start, end, related_source, related_start, related_end, detail_a, detail_b, detail_c, detail_d) }
    if !wrote { return 3 }
    return 1
}

fn driver_lex_diagnostic(state: State, parse: ParseStore) -> I32 {
    let rec = __s0_buffer_get(LexDiagRec, state.diagnostics, 0)
    return driver_diagnostic(state, parse, 1, rec.kind, rec.source, rec.start, rec.end, 0, 0, 0, 0, 0, 0, 0)
}

fn driver_parse_diagnostic(state: State, store: ParseStore) -> I32 {
    let rec = __s0_buffer_get(ParseDiagRec, store.diagnostics, 0)
    return driver_diagnostic(state, store, 2, rec.kind, rec.source, rec.start, rec.end, 0, 0, 0, 0, 0, 0, 0)
}

fn driver_check_diagnostic(state: State, parse: ParseStore, store: CheckStore) -> I32 {
    let rec = __s0_buffer_get(CheckDiagRec, store.diagnostics, 0)
    return driver_diagnostic(state, parse, 3, rec.kind, rec.source, rec.start, rec.end, rec.related_source, rec.related_start, rec.related_end, rec.detail_a, rec.detail_b, rec.detail_c, rec.detail_d)
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
