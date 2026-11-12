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

fn driver_out_lex_message(state: State, kind: U64, source: U64, detail_start: U64, json: Bool) -> Bool {
    if kind == 1 { return out_string("semicolons are not supported") }
    if kind == 2 { return out_string("unexpected character") }
    if kind == 3 { return out_string("invalid exponent") }
    if kind == 4 {
        if !out_string("invalid escape ") { return false }
        return driver_out_source_text(state, source, detail_start, detail_start + 2, json)
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
    if kind == 20 { return out_string("expected a C spelling string") }
    if kind == 21 { return out_string("expected a C binding member declaration") }
    if kind == 22 { return out_string("public C binding blocks are not supported; bind through a private binding block") }
    if kind == 23 { return out_string("C binding record fields must be separated by a physical line break") }
    if kind == 24 { return out_string("trait constraints are written on the type parameter: `Name: type(Trait, ...)`; there is no `where` clause") }
    if kind == 30 { return out_string("unsafe c block must contain a direct call or field access") }
    if kind == 35 { return out_string("an export declaration is `export c fn name(...) -> type { ... }` at module scope") }
    return out_string("invalid source syntax")
}

fn driver_out_diagnostic_type(state: State, parse: ParseStore, kind: U64, target: U64, json: Bool) -> Bool {
    if kind == 2 { return out_string("String") }
    if kind == 14 { return out_string("Bytes") }
    if kind == 7 { return driver_out_declared_type_name(state, parse, target, json) }
    if kind == 8 {
        if !out(91) || !driver_out_diagnostic_type(state, parse, 1, target, json) { return false }
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

// A declared type renders as its declaration node's name span; the checker
// records that node id in the diagnostic payload because the driver has no
// symbol table.
fn driver_out_declared_type_name(state: State, parse: ParseStore, node: U64, json: Bool) -> Bool {
    let rec = __s0_buffer_get(SyntaxRec, parse.nodes, node - 1)
    return driver_out_source_text(state, rec.source, rec.name_start, rec.name_end, json)
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

// Checker diagnostic kinds 107 through 129 are reserved for the Milestone
// 7.5 static-abstraction half (traits, constraints, closures, function
// values, Map/Set); 130 and above are reserved for the resource half;
// 155 and above also carry C binding block diagnostics (156-167);
// 300 through 349 are this thread's checker block (generic implementations
// and Eq operator dispatch).
fn driver_out_check_message(state: State, parse: ParseStore, kind: U64, source: U64, start: U64, end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64, json: Bool) -> Bool {
    if kind == 156 { return out_string("a module binds the same C header twice") }
    if kind == 57 { return out_string("type argument inference failed: every type parameter and implementation parameter of the callee must be known at the call site") }
    if kind == 157 { return out_string("C spelling must be a non-reserved C identifier") }
    if kind == 158 { return out_string("scalar binding spelling may not use a struct, union, or enum tag form") }
    if kind == 160 { return out_string("a binding block declares the same member name twice") }
    if kind == 161 { return out_string("a binding block maps two members to the same C spelling") }
    if kind == 162 { return out_string("unknown C type in the c namespace") }
    if kind == 163 { return out_string("unknown binding type name in a C binding block") }
    if kind == 164 { return out_string("c.Ptr and c.ConstPtr take exactly one type argument") }
    if kind == 165 { return out_string("invalid type in a C binding block") }
    if kind == 166 { return out_string("non-scalar C binding types are only valid behind c.Ptr or c.ConstPtr") }
    if kind == 167 { return out_string("a C binding constant must have an integral c.* type") }
    if kind == 200 { return out_string("a C binding call argument does not match its declared C parameter") }
    if kind == 201 {
        if detail_b != 0 && detail_a != detail_b {
            if !out_string("a C binding call takes ") || !out_u64(detail_b) || !out_string(" argument(s), got ") || !out_u64(detail_a) { return false }
            return true
        }
        return out_string("a C binding call takes a different number of arguments")
    }
    if kind == 202 { return out_string("c.is_null takes one raw C pointer") }
    if kind == 203 { return out_string("a C binding call's non-unit result must be used") }
    if kind == 204 { return out_string("unsafe c does not name a raw fn of a C binding block") }
    if kind == 205 { return out_string("no such C conversion method on this receiver") }
    if kind == 206 { return out_string("unsafe c field access requires a local binding holding a C record value") }
    if kind == 207 { return out_string("no such field on the bound C record") }
    if kind == 208 { return out_string("a C field assignment value does not match the field's declared binding type") }
    if kind == 209 { return out_string("a C field assignment requires a var binding") }
    if kind == 210 { return out_string("a c.CString literal may not contain an interior NUL byte") }
    if kind == 211 { return out_string("c.CString takes exactly one string argument") }
    if kind == 212 { return out_string("c.CString argument must be a String or Bytes value") }
    if kind == 213 { return out_string("a buffer argument requires a byte-addressable C pointee (c.Char, c.SChar, c.UChar, or an opaque bound type)") }
    if kind == 214 { return out_string("a mutable C pointer parameter requires a MutSlice(U8) argument") }
    if kind == 215 { return out_string("the same buffer is borrowed more than once in one unsafe C call") }
    if kind == 216 { return out_string("c.Zero argument must name a by-value C scalar or record type") }
    if kind == 217 { return out_string("c.addr requires a local place of the parameter's pointee type, mutable for c.Ptr, with no live view") }
    if kind == 218 { return out_string("c.load and c.store require a C pointer to a by-value C type") }
    if kind == 219 { return out_string("a write through a c.ConstPtr is not allowed") }
    if kind == 220 { return out_string("c.store value does not match the C pointer pointee") }
    if kind == 221 { return out_string("an export signature type is not a C ABI type") }
    if kind == 222 { return out_string("an export must be a non-generic, receiver-free function with a C-safe symbol name other than main") }
    if kind == 223 { return out_string("an export symbol collides with a raw fn C spelling") }
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
    if kind == 10 { if !out_string("slice element type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) { return false }
        return out_string(" contains a slice or reference (M4 restriction)") }
    if kind == 12 { if !out_string("Map key type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) { return false }
        return out_string(" is not supported (unsigned integers, Bool, and structs/enums of those only)") }
    if kind == 13 { if !out_string("Map value type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) { return false }
        return out_string(" must be copy-trivial (no slices, references, maps, or domain handles)") }
    if kind == 15 { if !out_string("import ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(": parameter type must be a primitive or Ptr(primitive)") }
    if kind == 18 { if !out_string("unknown name ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 19 { if !out_string("return: type mismatch: expected ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_c, detail_d, json) }
    if kind == 21 { if !out_string("literal ") || !driver_out_source_text(state, source, start, end, json) { return false }
        if !out_string(" is out of range for ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) }
    if kind == 22 { if !out_string("binding name ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is reserved") }
    if kind == 23 { if !out_string("binding: type mismatch: expected ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_c, detail_d, json) }
    if kind == 25 { if !driver_out_message_quote(json) || !out_string("Unit") || !driver_out_message_quote(json) { return false }
        return out_string(" is a type, not a value") }
    if kind == 26 { return out_string("domain marks cannot be bound; use them directly (the current MIR profile requires the reset mark to be the direct domain.mark result)") }
    if kind == 27 { if !out_string("name ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is already bound in this function") }
    if kind == 28 { if !out_string("cannot assign to immutable binding ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 37 { if !out_string("operator ") || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return out_string(" requires integer operands") }
    if kind == 303 { if !out_string("operator ") || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return out_string(" requires a type that implements Eq (integers, Bool, String, Bytes, or records and enums of Eq components)") }
    if kind == 305 { return out_string("match needs a value-producing arm: every arm returns, so the match has no value") }
    if kind == 39 { if !out_string("function ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" must be called") }
    if kind == 331 { return out_string("unit value statement has no effect; only a Unit-result call may stand alone") }
    if kind == 333 { return out_string("cannot grow or replace relocatable storage through a borrowed field: the new storage is owned by this call; use the functional builder convention (`value = value.method(...)`) or mutate a local owner") }
    if kind == 330 {
        if !out_string("operator ") || !driver_out_node_name(state, parse, source, start, end, json) || !out_string(" requires same-type integer operands: expected ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_c, detail_d, json)
    }
    if kind == 40 { if !out_string("unknown name ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) { return false }
        return driver_out_message_quote(json) }
    if kind == 59 {
        if !out_string("generic instantiation does not terminate: ") || !driver_out_node_name(state, parse, source, start, end, json) || !out_string(" is instantiated again with type arguments that do not strictly shrink") { return false }
        return out_string("")
    }
    if kind == 65 { return out_string("condition must have type Bool") }
    if kind == 67 { if !out_string("function ") || !driver_out_message_quote(json) || !driver_out_function_for_body(state, parse, source, start, json) || !driver_out_message_quote(json) { return false }
        return out_string(" may fall off the end without returning a value") }
    if kind == 68 { return out_string("unreachable statement") }
    if kind == 79 { if !out_string("match is not exhaustive: variant ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, detail_a, detail_b, json) || !driver_out_message_quote(json) || !out_string(" of ") || !driver_out_source_text(state, source, detail_c, detail_d, json) { return false }
        return out_string(" is not covered") }
    if kind == 80 { return out_string("try requires a function returning Result") }
    if kind == 82 { if !out_string("try error type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(" does not match function error type ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_c, detail_d, json) }
    if kind == 84 { if !out_string("index: type mismatch: expected ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_c, detail_d, json) }
    if kind == 85 { if !out_string("cleanup function parameter: type mismatch: expected ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(", got ") { return false }
        return driver_out_diagnostic_type(state, parse, detail_c, detail_d, json) }
    if kind == 87 { return out_string("source form is outside the supported S0 contract") }
    if kind == 88 { return out_string("public declaration signature exposes a private type") }
    if kind == 89 { return out_string("mut parameter requires an affine owner, scoped capability, or a type parameter constrained by a mut-self trait") }
    if kind == 90 { return out_string("take parameter requires an affine owner") }
    if kind == 91 { return out_string("owner was already transferred") }
    if kind == 92 { return out_string("argument does not provide the parameter's required exclusive or owning access") }
    if kind == 146 { return out_string("mut cursor argument must be a mutable place: pass a var binding so the callee advances the caller's cursor") }
    if kind == 93 { return out_string("affine owner reaches function exit without an ownership transfer") }
    if kind == 94 { return out_string("affine owner must be transferred on every reachable path or on none") }
    if kind == 95 { return out_string("affine owner cannot be mutable or overwritten; transfer or clean it up first") }
    if kind == 99 { return out_string("String literal is not valid UTF-8") }
    if kind == 105 {
        if !out_string("bootstrap type ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is private to the compiler's bootstrap sources (--bootstrap-private)")
    }
    if kind == 106 {
        if !out_string("bootstrap operation ") || !driver_out_message_quote(json) || !driver_out_source_text(state, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is private to the compiler's bootstrap sources (--bootstrap-private)")
    }
    if kind == 107 {
        if !out_string("conflicting implementations of trait ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(": exactly one implementation may exist for a trait application")
    }
    if kind == 108 { if !out_string("unknown trait ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string("") }
    if kind == 109 { if !out_string("trait ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" expects a different number of type arguments") }
    if kind == 110 { return out_string("trait implementations target a declared record or enum type") }
    if kind == 111 {
        if !out_string("type does not implement a trait required here") { return false }
        return out_string("")
    }
    if kind == 114 { if !out_string("trait ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is a trait, not a type") }
    if kind == 116 { return out_string("trait implementation arguments must be concrete types") }
    if kind == 117 { return out_string("Self is only available inside a trait or trait implementation") }
    if kind == 119 {
        if !out_string("trait method ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" is provided by multiple implementations for this receiver type")
    }
    if kind == 121 {
        if !out_string("trait implementation is missing a required method; expected ") { return false }
        return out_string("")
    }
    if kind == 122 {
        if !out_string("trait implementation method ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" matches no trait requirement")
    }
    if kind == 123 { return out_string("trait implementation method does not match the trait requirement signature") }
    if kind == 250 {
        if !out_string("builtin method ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) || !out_string(" applies only to its builtin receiver types, and this type provides no such impl method") { return false }
        return out_string("")
    }
    if kind == 251 {
        if !out_string("integer conversion method ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) || !out_string(" is not total because some receiver values do not fit the target; use the checked form ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !out_string("_checked") || !driver_out_message_quote(json) { return false }
        return out_string("")
    }
    if kind == 252 {
        if !out_string("integer conversion method ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) || !out_string(" converts a type to itself and has no effect") { return false }
        return out_string("")
    }
    if kind == 253 {
        if !out_string("integer conversion method ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) || !out_string(" is not needed because every receiver value fits the target, so the total form exists and neither the checked nor the wrapping form can fail") { return false }
        return out_string("")
    }
    if kind == 254 {
        if !out_string("type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(" does not implement Order; the Order domain is Bool, unsigned integers, String, and Bytes") { return false }
        return out_string("")
    }
    if kind == 257 {
        if !out_string("type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) || !out_string(" does not implement Display; the builtin Display domain is Bool, signed and unsigned integers, and String, and a declared type can implement Display itself") { return false }
        return out_string("")
    }
    if kind == 255 { return out_string("float literal is out of range for F32") }
    if kind == 256 { return out_string("float literal is not exactly representable as F32; write the nearest F32 value's exact decimal digits") }
    if kind == 125 { return out_string("structural Eq, Hash, and Order implementations are language-provided and cannot be declared") }
    if kind == 126 {
        if !out_string("structural ") || !driver_out_node_name(state, parse, source, start, end, json) || !out_string(" methods become callable with the ordered collections") { return false }
        return out_string("")
    }
    if kind == 127 { if !out_string("ordered collection key type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) { return false }
        return out_string(" does not support structural Eq and Hash (unsigned integers, Bool, String, Bytes, and structs/enums of those)") }
    if kind == 128 { if !out_string("ordered collection element type ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) { return false }
        return out_string(" must be a copyable value") }
    if kind == 129 {
        if !out_string("ordered collection operation cannot move values with storage-backed parts yet: ") || !driver_out_diagnostic_type(state, parse, detail_a, detail_b, json) { return false }
        return out_string("")
    }
    // Diagnostic kinds 300 through 349 belong to this thread's work block.
    if kind == 300 {
        if !out_string("implementation parameter ") || !driver_out_message_quote(json) || !driver_out_node_name(state, parse, source, start, end, json) || !driver_out_message_quote(json) { return false }
        return out_string(" does not appear in the implementing type")
    }
    if kind == 301 { return out_string("an implementation cannot target a bare type parameter; write a parameterized implementing type instead") }
    if kind == 306 { return out_string("to_bytes requires a [U8] view: this view's element type is not U8") }
    if kind == 307 { return out_string("a mutable view must be formed from a binding: copy the field or element into a var local, take the view, then store the local back") }
    if kind == 308 { return out_string("cannot move an affine field out of a borrowed owner: only a take-self method may move its fields") }
    if kind == 309 { return out_string("cannot construct this record outside its module: a required field is not pub") }
    if kind == 302 { return out_string("implementations must restate every constraint the implementing type declares on the matching type argument") }
    if kind == 144 { if !out_string("ordered collection operation ") || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return out_string(" is used with the wrong argument shape") }
    if kind == 145 { if !out_string("closure capture ") || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return out_string(" is not an ordinary snapshot value; affine owners and scoped capabilities cannot be captured, while strings, bytes, vectors, collections, records over them, and function values can") }
    if kind == 147 { if !out_string("closure ") || !driver_out_node_name(state, parse, source, start, end, json) { return false }
        return out_string(" has an unsupported shape; annotate parameter types and give a body") }
    if kind == 152 { return out_string("closure captures a scoped capability and escapes; a closure that captures a slice or view may only be called within the scope that owns it") }
    if kind == 153 { return out_string("a closure that captures a slice or view cannot be created inside a loop body yet") }
    if kind == 154 { return out_string("a view cannot be assigned inside a loop body; bind the view in the iteration that creates it") }
    if kind == 130 { return out_string("table element type is not concrete copyable data") }
    if kind == 131 { return out_string("table operation requires a named owning or exclusive table receiver") }
    if kind == 132 { return out_string("table lookup must be the scrutinee of a match with an explicit Some binding") }
    if kind == 133 { return out_string("table-view match arm may contain only straight-line copy statements without fallible operations") }
    if kind == 134 { return out_string("overlapping table access: a live table view excludes this operation") }
    if kind == 135 { return out_string("match arms must be all expression bodies or all statement blocks") }
    if kind == 136 { return out_string("using requires an affine owner implementing Cleanup") }
    if kind == 137 { return out_string("the with-cleanup clause is private to the compiler's bootstrap sources; use Cleanup selection") }
    if kind == 140 { return out_string("Cleanup selection requires a nongeneric cleanup(take self) -> Unit method") }
    if kind == 141 { return out_string("a Vec of affine elements supports push and len only; element access would duplicate an owner") }
    if kind == 142 { return out_string("a registered vector owner is immutable; grow a plain binding first, then register it with using") }
    if kind == 143 { return out_string("a Table cannot be a Vec element yet: heap-storing a table handle awaits storage rules; register the table with using directly") }
    if kind == 148 { return out_string("a match guard only borrows the arm's bindings; it cannot consume an owner") }
    if kind == 149 { return out_string("a table-view match arm cannot carry a guard; the view region is one straight-line fail-free block") }
    if kind == 150 { return out_string("break is only allowed inside a loop") }
    if kind == 151 { return out_string("continue is only allowed inside a loop") }
    if !out_string("semantic error (checker diagnostic ") || !out_u64(kind) { return false }
    return out(41)
}

fn driver_out_message(state: State, parse: ParseStore, phase: U64, kind: U64, source: U64, start: U64, end: U64, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64, json: Bool) -> Bool {
    if phase == 1 { return driver_out_lex_message(state, kind, source, detail_a, json) }
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
    return driver_diagnostic(state, parse, 1, rec.kind, rec.source, rec.start, rec.end, 0, 0, 0, rec.detail_start, 0, 0, 0)
}

fn driver_parse_diagnostic(state: State, store: ParseStore) -> I32 {
    let rec = __s0_buffer_get(ParseDiagRec, store.diagnostics, 0)
    return driver_diagnostic(state, store, 2, rec.kind, rec.source, rec.start, rec.end, 0, 0, 0, 0, 0, 0, 0)
}

fn driver_check_diagnostic(state: State, parse: ParseStore, store: CheckStore) -> I32 {
    let rec = __s0_buffer_get(CheckDiagRec, store.diagnostics, 0)
    return driver_diagnostic(state, parse, 3, rec.kind, rec.source, rec.start, rec.end, rec.related_source, rec.related_start, rec.related_end, rec.detail_a, rec.detail_b, rec.detail_c, rec.detail_d)
}

fn driver_failure(status: U64, kind: __s0_String, message: __s0_String) -> I32 {
    if driver_json() {
        if !driver_reset_response() || !driver_select(0) || !out_string("{\"version\":1,\"command\":\"") { return 3 }
        if driver_command() == 1 { if !out_string("check") { return 3 } } else { if !out_string("compile") { return 3 } }
        if !out_string("\",\"success\":false,\"diagnostics\":[],\"failure\":{\"kind\":\"") || !out_string(kind) || !out_string("\",\"message\":\"") || !out_string(message) || !out_string("\"}}\n") { return 3 }
    } else {
        if !driver_select(1) || !out_string("alder: ") || !out_string(message) || !out(10) { return 3 }
    }
    if status == 1 { return 1 }
    if status == 2 { return 2 }
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

fn driver_artifact_start(kind: __s0_String) -> Bool {
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
