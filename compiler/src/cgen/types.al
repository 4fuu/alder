// Stable C names, declaration safety checks, and MIR type layout emission.

type CgenTypeState {
    writer: CgenWriter
    emitted: __s0_Buffer(U64)
}

fn cgen_name_is(store: MirStore, start: U64, end: U64, word: String) -> Bool {
    if end - start != len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if __s0_buffer_get(U8, store.names, start + at) != word[at] { return false }
        at = at + 1
    }
    return true
}

fn cgen_name_has_prefix(store: MirStore, start: U64, end: U64, word: String) -> Bool {
    if end - start < len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if __s0_buffer_get(U8, store.names, start + at) != word[at] { return false }
        at = at + 1
    }
    return true
}

fn cgen_name_has_suffix(store: MirStore, start: U64, end: U64, word: String) -> Bool {
    if end - start < len(word) { return false }
    return cgen_name_is(store, end - len(word), end, word)
}

fn cgen_name_in_list(store: MirStore, start: U64, end: U64, words: String) -> Bool {
    var first: U64 = 0
    var at: U64 = 0
    while at <= len(words) {
        if at == len(words) || words[at] == 44 {
            if at - first == end - start {
                var same = true
                var byte: U64 = 0
                while same && byte < at - first {
                    if words[first + byte] != __s0_buffer_get(U8, store.names, start + byte) { same = false }
                    byte = byte + 1
                }
                if same { return true }
            }
            first = at + 1
        }
        at = at + 1
    }
    return false
}

fn cgen_header_name(store: MirStore, start: U64, end: U64) -> Bool {
    if cgen_name_has_suffix(store, start, end, "_t") { return true }
    if cgen_name_in_list(store, start, end, "main,bool,true,false,NULL,offsetof,memchr,memcmp,memcpy,memmove,memset,strcat,strchr,strcmp,strcoll,strcpy,strcspn,strerror,strlen,strncat,strncmp,strncpy,strpbrk,strrchr,strspn,strstr,strtok,strxfrm") { return true }
    var macro = __s0_buffer_get(U8, store.names, start) >= 65 && __s0_buffer_get(U8, store.names, start) <= 90
    var at = start + 1
    while macro && at < end {
        let byte = __s0_buffer_get(U8, store.names, at)
        macro = byte == 95 || byte >= 65 && byte <= 90 || byte >= 48 && byte <= 57
        at = at + 1
    }
    return macro
}

fn cgen_external_name_safe(store: MirStore, start: U64, end: U64) -> Bool {
    if !mir_name_valid(store, start, end, false) || __s0_buffer_get(U8, store.names, start) == 95 { return false }
    if cgen_name_has_prefix(store, start, end, "alder_") || cgen_name_has_prefix(store, start, end, "ALDER_") || cgen_name_has_prefix(store, start, end, "Alder") { return false }
    if cgen_name_in_list(store, start, end, "_Alignas,_Alignof,_Atomic,_Bool,_Complex,_Generic,_Imaginary,_Noreturn,_Static_assert,_Thread_local,auto,break,case,char,const,continue,default,do,double,else,enum,extern,float,for,goto,if,inline,int,long,register,restrict,return,short,signed,sizeof,static,struct,switch,typedef,union,unsigned,void,volatile,while") { return false }
    return !cgen_header_name(store, start, end)
}

fn cgen_backend_declarations_safe(d: Domain, store: MirStore) -> Result(Bool, __s0_Error) {
    if !mir_store_valid(store) { return Ok(false) }
    var at: U64 = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        if try mir_vtype_cycles(d, store, at + 1) { return Ok(false) }
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        if t.kind == mir_type_kind_enum() && mir_type_part_count(store, at + 1, mir_type_part_variant()) == 0 { return Ok(false) }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let item = __s0_buffer_get(MirImportRec, store.imports, at)
        if !cgen_external_name_safe(store, item.name_start, item.name_end) { return Ok(false) }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let item = __s0_buffer_get(MirConstRec, store.constants, at)
        var valid = false
        if item.kind == mir_const_unit() { valid = item.const_type == mir_type_unit() }
        if item.kind == mir_const_bool() { valid = item.const_type == mir_type_bool() && item.bool_value <= 1 }
        if item.kind == mir_const_int() { valid = mir_vint_fits(item.const_type, item.int_value) }
        if item.kind == mir_const_float() { valid = (item.const_type == mir_type_f32() || item.const_type == mir_type_f64()) && mir_vfloat_finite(item.float_bits)
        if item.const_type == mir_type_f32() { valid = valid && mir_vfloat_exact_f32(item.float_bits) } }
        if item.kind == mir_const_string() { let t = __s0_buffer_get(MirTypeRec, store.types, item.const_type - 1)
        valid = t.kind == mir_type_kind_slice() && t.elem == mir_type_u8() }
        if !valid { return Ok(false) }
        at = at + 1
    }
    return Ok(true)
}

fn cgen_put_type(d: Domain, writer: CgenWriter, store: MirStore, id: U64) -> Result(CgenWriter, __s0_Error) {
    if id == mir_type_unit() || id == mir_type_u8() { return cgen_put(d, writer, "uint8_t") }
    if id == mir_type_bool() { return cgen_put(d, writer, "bool") }
    if id == mir_type_i8() { return cgen_put(d, writer, "int8_t") }
    if id == mir_type_i16() { return cgen_put(d, writer, "int16_t") }
    if id == mir_type_i32() { return cgen_put(d, writer, "int32_t") }
    if id == mir_type_i64() { return cgen_put(d, writer, "int64_t") }
    if id == mir_type_u16() { return cgen_put(d, writer, "uint16_t") }
    if id == mir_type_u32() { return cgen_put(d, writer, "uint32_t") }
    if id == mir_type_u64() { return cgen_put(d, writer, "uint64_t") }
    if id == mir_type_f32() { return cgen_put(d, writer, "float") }
    if id == mir_type_f64() { return cgen_put(d, writer, "double") }
    let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() || t.kind == mir_type_kind_option() || t.kind == mir_type_kind_result() { let out = try cgen_put(d, writer, "AlderTy")
    return cgen_put_u64(d, out, id - 1) }
    if t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() { return cgen_put(d, writer, "AlderSlice") }
    if t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() { return cgen_put(d, writer, "void *") }
    if t.kind == mir_type_kind_function() { let out = try cgen_put(d, writer, "AlderFnTy")
    return cgen_put_u64(d, out, id - 1) }
    if t.kind == mir_type_kind_domain_handle() { return cgen_put(d, writer, "AlderDomain *") }
    if t.kind == mir_type_kind_domain_mark() { return cgen_put(d, writer, "AlderDomainMark") }
    if t.kind == mir_type_kind_cleanup_scope() { return cgen_put(d, writer, "AlderCleanupScope *") }
    if t.kind == mir_type_kind_cleanup_id() { return cgen_put(d, writer, "AlderCleanupId") }
    if t.kind == mir_type_kind_table() { return cgen_put(d, writer, "AlderTable *") }
    return cgen_put(d, writer, "AlderTableId")
}

fn cgen_emitted(ids: __s0_Buffer(U64), id: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(U64, ids) {
        if __s0_buffer_get(U64, ids, at) == id { return true }
        at = at + 1
    }
    return false
}

fn cgen_type_part(store: MirStore, owner: U64, kind: U64, ordinal: U64) -> MirTypePartRec {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if part.owner == owner && part.kind == kind && part.ordinal == ordinal { return part }
        at = at + 1
    }
    return __s0_buffer_get(MirTypePartRec, store.type_parts, 0)
}

fn cgen_emit_type(d: Domain, initial: CgenTypeState, store: MirStore, id: U64) -> Result(CgenTypeState, __s0_Error) {
    if id <= mir_primitive_type_count() || cgen_emitted(initial.emitted, id) { return Ok(initial) }
    var state = initial
    let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if t.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, id, kind) {
            state = try cgen_emit_type(d, state, store, cgen_type_part(store, id, kind, ordinal).part_type)
            ordinal = ordinal + 1
        }
    }
    if t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() { state = try cgen_emit_type(d, state, store, t.elem) }
    if t.kind == mir_type_kind_result() { state = try cgen_emit_type(d, state, store, t.ok_type)
    state = try cgen_emit_type(d, state, store, t.err_type) }
    if t.kind == mir_type_kind_function() {
        var ordinal: U64 = 0
        while ordinal < t.part_count { state = try cgen_emit_type(d, state, store, cgen_type_part(store, id, mir_type_part_function_param(), ordinal).part_type)
        ordinal = ordinal + 1 }
        state = try cgen_emit_type(d, state, store, t.result_type)
    }
    var writer = state.writer
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() || t.kind == mir_type_kind_option() || t.kind == mir_type_kind_result() { writer = try cgen_emit_struct(d, writer, store, id, t) }
    if t.kind == mir_type_kind_function() { writer = try cgen_emit_function_type(d, writer, store, id, t) }
    let emitted = try __s0_buffer_append(U64, d, state.emitted, id)
    return Ok(CgenTypeState(writer: writer, emitted: emitted))
}

fn cgen_emit_function_type(d: Domain, initial: CgenWriter, store: MirStore, id: U64, t: MirTypeRec) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "typedef ")
    if t.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, t.result_type) }
    out = try cgen_put(d, out, " (*AlderFnTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, ")(")
    var ordinal: U64 = 0
    var wrote = false
    while ordinal < t.part_count {
        let part = cgen_type_part(store, id, mir_type_part_function_param(), ordinal)
        if part.part_type != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            out = try cgen_put_type(d, out, store, part.part_type)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    if !wrote { out = try cgen_put(d, out, "void") }
    return cgen_put(d, out, ");\n")
}

fn cgen_emit_struct(d: Domain, initial: CgenWriter, store: MirStore, id: U64, t: MirTypeRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() { out = try cgen_put(d, out, "/* @")
    out = try cgen_put_name(d, out, store, t.name_start, t.name_end)
    out = try cgen_put(d, out, " */\n") }
    out = try cgen_put(d, out, "struct AlderTy")
    out = try cgen_put_u64(d, out, id - 1)
    out = try cgen_put(d, out, " {\n")
    if t.kind == mir_type_kind_aggregate() {
        let count = mir_type_part_count(store, id, mir_type_part_field())
        if count == 0 { out = try cgen_put(d, out, "  uint8_t alder_empty;\n") }
        var ordinal: U64 = 0
        while ordinal < count {
            let part = cgen_type_part(store, id, mir_type_part_field(), ordinal)
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_type(d, out, store, part.part_type)
            out = try cgen_put(d, out, " alder_f")
            out = try cgen_put_u64(d, out, ordinal)
            out = try cgen_put(d, out, ";\n")
            ordinal = ordinal + 1
        }
    } else {
        var payloads: U64 = 0
        var count: U64 = 2
        var kind = mir_type_part_variant()
        if t.kind == mir_type_kind_enum() { count = mir_type_part_count(store, id, kind) }
        var ordinal: U64 = 0
        while ordinal < count {
            var payload = mir_type_unit()
            if t.kind == mir_type_kind_enum() { payload = cgen_type_part(store, id, kind, ordinal).part_type }
            if t.kind == mir_type_kind_option() && ordinal == 1 { payload = t.elem }
            if t.kind == mir_type_kind_result() && ordinal == 0 { payload = t.ok_type }
            if t.kind == mir_type_kind_result() && ordinal == 1 { payload = t.err_type }
            if payload != mir_type_unit() { payloads = payloads + 1 }
            ordinal = ordinal + 1
        }
        if payloads > 0 {
            out = try cgen_put(d, out, "  union {\n")
            ordinal = 0
            while ordinal < count {
                var payload = mir_type_unit()
                if t.kind == mir_type_kind_enum() { payload = cgen_type_part(store, id, kind, ordinal).part_type }
                if t.kind == mir_type_kind_option() && ordinal == 1 { payload = t.elem }
                if t.kind == mir_type_kind_result() && ordinal == 0 { payload = t.ok_type }
                if t.kind == mir_type_kind_result() && ordinal == 1 { payload = t.err_type }
                if payload != mir_type_unit() { out = try cgen_put(d, out, "    ")
                out = try cgen_put_type(d, out, store, payload)
                out = try cgen_put(d, out, " alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ";\n") }
                ordinal = ordinal + 1
            }
            out = try cgen_put(d, out, "  } alder_u;\n")
        }
        out = try cgen_put(d, out, "  uint32_t alder_tag;\n")
    }
    return cgen_put(d, out, "};\n")
}

fn cgen_emit_types(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = mir_primitive_type_count()
    var records = false
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        if t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() || t.kind == mir_type_kind_option() || t.kind == mir_type_kind_result() { out = try cgen_put(d, out, "typedef struct AlderTy")
        out = try cgen_put_u64(d, out, at)
        out = try cgen_put(d, out, " AlderTy")
        out = try cgen_put_u64(d, out, at)
        out = try cgen_put(d, out, ";\n")
        records = true }
        at = at + 1
    }
    if records { out = try cgen_put(d, out, "\n") }
    let emitted = try __s0_buffer_new(U64, d)
    var state = CgenTypeState(writer: out, emitted: emitted)
    at = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        state = try cgen_emit_type(d, state, store, at + 1)
        at = at + 1
    }
    return Ok(state.writer)
}
