fn text_byte(state: State, source: SourceRec, at: U64) -> U8 {
    return __s0_buffer_get(U8, state.texts, source.text_start + at)
}

fn alpha(byte: U8) -> Bool {
    return byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

fn digit(byte: U8) -> Bool { return byte >= 48 && byte <= 57 }
fn ident_continue(byte: U8) -> Bool { return alpha(byte) || digit(byte) }
fn whitespace(byte: U8) -> Bool { return byte == 32 || byte == 9 || byte == 13 || byte == 10 }

fn source_word(state: State, source: SourceRec, start: U64, end: U64, word: __s0_String) -> Bool {
    if end - start != len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if text_byte(state, source, start + at) != word[at] { return false }
        at = at + 1
    }
    return true
}

fn keyword_id(state: State, source: SourceRec, start: U64, end: U64) -> U64 {
    if source_word(state, source, start, end, "import") { return 1 }
    if source_word(state, source, start, end, "type") { return 2 }
    if source_word(state, source, start, end, "enum") { return 3 }
    if source_word(state, source, start, end, "fn") { return 4 }
    if source_word(state, source, start, end, "let") { return 5 }
    if source_word(state, source, start, end, "var") { return 6 }
    if source_word(state, source, start, end, "if") { return 7 }
    if source_word(state, source, start, end, "else") { return 8 }
    if source_word(state, source, start, end, "while") { return 9 }
    if source_word(state, source, start, end, "for") { return 10 }
    if source_word(state, source, start, end, "in") { return 11 }
    if source_word(state, source, start, end, "return") { return 12 }
    if source_word(state, source, start, end, "match") { return 13 }
    if source_word(state, source, start, end, "using") { return 14 }
    if source_word(state, source, start, end, "with") { return 15 }
    if source_word(state, source, start, end, "try") { return 16 }
    if source_word(state, source, start, end, "true") { return 17 }
    if source_word(state, source, start, end, "false") { return 18 }
    if source_word(state, source, start, end, "unsafe") { return 19 }
    if source_word(state, source, start, end, "module") { return 20 }
    if source_word(state, source, start, end, "pub") { return 21 }
    if source_word(state, source, start, end, "as") { return 22 }
    if source_word(state, source, start, end, "mut") { return 23 }
    if source_word(state, source, start, end, "take") { return 24 }
    if source_word(state, source, start, end, "impl") { return 25 }
    if source_word(state, source, start, end, "self") { return 26 }
    if source_word(state, source, start, end, "trait") { return 27 }
    if source_word(state, source, start, end, "where") { return 28 }
    if source_word(state, source, start, end, "Self") { return 29 }
    if source_word(state, source, start, end, "break") { return 30 }
    if source_word(state, source, start, end, "continue") { return 31 }
    if source_word(state, source, start, end, "export") { return 32 }
    return 0
}

fn copy_value(d: Domain, values: __s0_Buffer(U8), state: State, source: SourceRec, start: U64, end: U64) -> Result(__s0_Buffer(U8), __s0_Error) {
    var result = values
    var at = start
    while at < end {
        result = try __s0_buffer_append(U8, d, result, text_byte(state, source, at))
        at = at + 1
    }
    return Ok(result)
}

fn add_token(d: Domain, state: State, source_id: U64, kind: U64, keyword: U64, start: U64, end: U64, leading: U64, values: __s0_Buffer(U8), value_start: U64) -> Result(State, __s0_Error) {
    let item = TokenRec(source: source_id, kind: kind, keyword: keyword, start: start, end: end, leading_start: leading, leading_end: start, value_start: value_start, value_end: __s0_buffer_len(U8, values))
    let tokens = try __s0_buffer_append(TokenRec, d, state.tokens, item)
    return Ok(State(paths: state.paths, texts: state.texts, values: values, sources: state.sources, tokens: tokens, diagnostics: state.diagnostics))
}

fn fail_lex(d: Domain, state: State, kind: U64, source: U64, start: U64, end: U64, detail_start: U64) -> Result(LexResult, __s0_Error) {
    let diag = LexDiagRec(kind: kind, source: source, start: start, end: end, detail_start: detail_start)
    let diagnostics = try __s0_buffer_append(LexDiagRec, d, state.diagnostics, diag)
    return Ok(Bad(State(paths: state.paths, texts: state.texts, values: state.values, sources: state.sources, tokens: state.tokens, diagnostics: diagnostics)))
}

fn punctuation(byte: U8) -> Bool {
    return byte == 40 || byte == 41 || byte == 123 || byte == 125 || byte == 91 || byte == 93 || byte == 44 || byte == 58 || byte == 59 || byte == 61 || byte == 46 || byte == 60 || byte == 62 || byte == 33 || byte == 38 || byte == 124 || byte == 94 || byte == 126 || byte == 43 || byte == 45 || byte == 42 || byte == 47 || byte == 37
}

fn pair_operator(a: U8, b: U8) -> Bool {
    return (a == 45 && b == 62) || (a == 60 && b == 60) || (a == 62 && b == 62) || (a == 61 && b == 61) || (a == 33 && b == 61) || (a == 60 && b == 61) || (a == 62 && b == 61) || (a == 38 && b == 38) || (a == 124 && b == 124) || (a == 61 && b == 62)
}

fn utf8_continuation(byte: U8) -> Bool { return byte >= 128 && byte <= 191 }

fn hex_digit(byte: U8) -> Bool { return (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102) }

fn hex_value(byte: U8) -> U8 {
    if byte >= 48 && byte <= 57 { return byte - 48 }
    if byte >= 65 && byte <= 70 { return byte - 55 }
    return byte - 87
}

fn unexpected_end(state: State, source: SourceRec, start: U64, length: U64) -> U64 {
    let first = text_byte(state, source, start)
    if first >= 194 && first <= 223 && start + 1 < length && utf8_continuation(text_byte(state, source, start + 1)) {
        return start + 2
    }
    if first == 224 && start + 2 < length && text_byte(state, source, start + 1) >= 160 && text_byte(state, source, start + 1) <= 191 && utf8_continuation(text_byte(state, source, start + 2)) {
        return start + 3
    }
    if ((first >= 225 && first <= 236) || (first >= 238 && first <= 239)) && start + 2 < length && utf8_continuation(text_byte(state, source, start + 1)) && utf8_continuation(text_byte(state, source, start + 2)) {
        return start + 3
    }
    if first == 237 && start + 2 < length && text_byte(state, source, start + 1) >= 128 && text_byte(state, source, start + 1) <= 159 && utf8_continuation(text_byte(state, source, start + 2)) {
        return start + 3
    }
    if first == 240 && start + 3 < length && text_byte(state, source, start + 1) >= 144 && text_byte(state, source, start + 1) <= 191 && utf8_continuation(text_byte(state, source, start + 2)) && utf8_continuation(text_byte(state, source, start + 3)) {
        return start + 4
    }
    if first >= 241 && first <= 243 && start + 3 < length && utf8_continuation(text_byte(state, source, start + 1)) && utf8_continuation(text_byte(state, source, start + 2)) && utf8_continuation(text_byte(state, source, start + 3)) {
        return start + 4
    }
    if first == 244 && start + 3 < length && text_byte(state, source, start + 1) >= 128 && text_byte(state, source, start + 1) <= 143 && utf8_continuation(text_byte(state, source, start + 2)) && utf8_continuation(text_byte(state, source, start + 3)) {
        return start + 4
    }
    return start + 1
}

fn lex_source(d: Domain, initial: State, source_id: U64) -> Result(LexResult, __s0_Error) {
    let source = __s0_buffer_get(SourceRec, initial.sources, source_id)
    let length = source.text_end - source.text_start
    var state = initial
    var pos: U64 = 0
    var done = false
    while !done {
        let leading = pos
        var skipping = true
        while skipping && pos < length {
            let c = text_byte(state, source, pos)
            if whitespace(c) {
                pos = pos + 1
            } else {
                if c == 47 && pos + 1 < length && text_byte(state, source, pos + 1) == 47 {
                    pos = pos + 2
                    while pos < length && text_byte(state, source, pos) != 10 { pos = pos + 1 }
                } else {
                    if c == 47 && pos + 1 < length && text_byte(state, source, pos + 1) == 42 {
                        let comment_start = pos
                        pos = pos + 2
                        var closed = false
                        while pos < length && !closed {
                            if text_byte(state, source, pos) == 42 && pos + 1 < length && text_byte(state, source, pos + 1) == 47 {
                                pos = pos + 2
                                closed = true
                            } else {
                                pos = pos + 1
                            }
                        }
                        if !closed { return fail_lex(d, state, 6, source_id, comment_start, comment_start + 1, 0) }
                    } else {
                        skipping = false
                    }
                }
            }
        }
        if pos == length {
            let value_start = __s0_buffer_len(U8, state.values)
            state = try add_token(d, state, source_id, 0, 0, length, length, leading, state.values, value_start)
            done = true
        } else {
            let start = pos
            let c = text_byte(state, source, pos)
            if alpha(c) {
                pos = pos + 1
                while pos < length && ident_continue(text_byte(state, source, pos)) { pos = pos + 1 }
                let value_start = __s0_buffer_len(U8, state.values)
                let values = try copy_value(d, state.values, state, source, start, pos)
                state = try add_token(d, state, source_id, 1, keyword_id(state, source, start, pos), start, pos, leading, values, value_start)
            } else {
                if digit(c) || (c == 45 && pos + 1 < length && digit(text_byte(state, source, pos + 1))) {
                    if c == 45 { pos = pos + 1 }
                    while pos < length && digit(text_byte(state, source, pos)) { pos = pos + 1 }
                    var kind: U64 = 2
                    if pos < length && text_byte(state, source, pos) == 46 {
                        kind = 3
                        pos = pos + 1
                        while pos < length && digit(text_byte(state, source, pos)) { pos = pos + 1 }
                    }
                    if pos < length && (text_byte(state, source, pos) == 101 || text_byte(state, source, pos) == 69) {
                        kind = 3
                        pos = pos + 1
                        if pos < length && (text_byte(state, source, pos) == 43 || text_byte(state, source, pos) == 45) { pos = pos + 1 }
                        let exponent_start = pos
                        while pos < length && digit(text_byte(state, source, pos)) { pos = pos + 1 }
                        if exponent_start == pos { return fail_lex(d, state, 3, source_id, start, start + 1, 0) }
                    }
                    let value_start = __s0_buffer_len(U8, state.values)
                    let values = try copy_value(d, state.values, state, source, start, pos)
                    state = try add_token(d, state, source_id, kind, 0, start, pos, leading, values, value_start)
                } else {
                    if c == 34 {
                        pos = pos + 1
                        var values = state.values
                        let value_start = __s0_buffer_len(U8, values)
                        var closed = false
                        while pos < length && !closed {
                            let item = text_byte(state, source, pos)
                            if item == 10 { return fail_lex(d, state, 5, source_id, start, start + 1, 0) }
                            if item == 34 {
                                pos = pos + 1
                                closed = true
                            } else {
                                if item == 92 {
                                    pos = pos + 1
                                    if pos == length || text_byte(state, source, pos) == 10 { return fail_lex(d, state, 5, source_id, start, start + 1, 0) }
                                    let escape = text_byte(state, source, pos)
                                    var decoded: U8 = 0
                                    let valid = escape == 110 || escape == 116 || escape == 114 || escape == 92 || escape == 34 || escape == 48 || escape == 120
                                    if escape == 110 { decoded = 10 }
                                    if escape == 116 { decoded = 9 }
                                    if escape == 114 { decoded = 13 }
                                    if escape == 92 { decoded = 92 }
                                    if escape == 34 { decoded = 34 }
                                    if escape == 48 { decoded = 0 }
                                    if !valid { return fail_lex(d, state, 4, source_id, start, start + 1, pos - 1) }
                                    if escape == 120 {
                                        if pos + 2 >= length || !hex_digit(text_byte(state, source, pos + 1)) || !hex_digit(text_byte(state, source, pos + 2)) { return fail_lex(d, state, 4, source_id, start, start + 1, pos - 1) }
                                        decoded = hex_value(text_byte(state, source, pos + 1)) * 16 + hex_value(text_byte(state, source, pos + 2))
                                        pos = pos + 2
                                    }
                                    values = try __s0_buffer_append(U8, d, values, decoded)
                                    pos = pos + 1
                                } else {
                                    values = try __s0_buffer_append(U8, d, values, item)
                                    pos = pos + 1
                                }
                            }
                        }
                        if !closed { return fail_lex(d, state, 5, source_id, start, start + 1, 0) }
                        state = try add_token(d, state, source_id, 4, 0, start, pos, leading, values, value_start)
                    } else {
                        if c == 59 {
                            return fail_lex(d, state, 1, source_id, start, start + 1, 0)
                        } else {
                            if punctuation(c) {
                                pos = pos + 1
                                if pos < length && pair_operator(c, text_byte(state, source, pos)) { pos = pos + 1 }
                                let value_start = __s0_buffer_len(U8, state.values)
                                let values = try copy_value(d, state.values, state, source, start, pos)
                                state = try add_token(d, state, source_id, 5, 0, start, pos, leading, values, value_start)
                            } else {
                                return fail_lex(d, state, 2, source_id, start, unexpected_end(state, source, start, length), 0)
                            }
                        }
                    }
                }
            }
        }
    }
    return Ok(Good(state))
}

fn lex_sources(d: Domain, state: State, source: U64) -> Result(LexResult, __s0_Error) {
    var current = state
    var at = source
    while at < __s0_buffer_len(SourceRec, current.sources) {
        let result = try lex_source(d, current, at)
        if lex_result_failed(result) { return Ok(Bad(lex_result_state(result))) }
        current = lex_result_state(result)
        at = at + 1
    }
    return Ok(Good(current))
}

fn lex_result_failed(result: LexResult) -> Bool {
    return match result {
        Bad(failed) => true
        Good(done) => false
    }
}

fn lex_result_state(result: LexResult) -> State {
    return match result {
        Bad(failed) => failed
        Good(done) => done
    }
}
