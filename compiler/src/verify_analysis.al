fn mir_vadd(d: Domain, diagnostics: __s0_Buffer(MirVerifyDiagRec), item: MirVerifyDiagRec) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    return __s0_buffer_append(MirVerifyDiagRec, d, diagnostics, item)
}
fn mir_vid_valid(id: U64, count: U64) -> Bool { return id > 0 && id <= count }
fn mir_vrange_valid(start: U64, end: U64, count: U64) -> Bool { return start <= end && end <= count }
fn mir_vname_equal(store: MirStore, a_start: U64, a_end: U64, b_start: U64, b_end: U64) -> Bool {
    if !mir_vrange_valid(a_start, a_end, __s0_buffer_len(U8, store.names)) || !mir_vrange_valid(b_start, b_end, __s0_buffer_len(U8, store.names)) { return false }
    if a_end - a_start != b_end - b_start { return false }
    var at: U64 = 0
    while at < a_end - a_start {
        if __s0_buffer_get(U8, store.names, a_start + at) != __s0_buffer_get(U8, store.names, b_start + at) { return false }
        at = at + 1
    }
    return true
}
fn mir_vname_word(store: MirStore, start: U64, end: U64, word: String) -> Bool {
    if !mir_vrange_valid(start, end, __s0_buffer_len(U8, store.names)) || end - start != len(word) { return false }
    var at: U64 = 0
    while at < len(word) {
        if __s0_buffer_get(U8, store.names, start + at) != word[at] { return false }
        at = at + 1
    }
    return true
}
fn mir_vname_valid(store: MirStore, start: U64, end: U64, dotted: Bool) -> Bool {
    if !mir_vrange_valid(start, end, __s0_buffer_len(U8, store.names)) || start == end { return false }
    var at = start
    var segment_start = true
    while at < end {
        let c = __s0_buffer_get(U8, store.names, at)
        if dotted && c == 46 {
            if segment_start || at + 1 == end { return false }
            segment_start = true
        } else {
            let letter = c == 95 || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            if segment_start {
                if !letter { return false }
                segment_start = false
            } else { if !letter && !(c >= 48 && c <= 57) { return false } }
        }
        at = at + 1
    }
    return !segment_start
}
fn mir_vfunction_exists(store: MirStore, id: U64) -> Bool { return mir_vid_valid(id, __s0_buffer_len(MirFunctionRec, store.functions)) }
fn mir_vtype_exists(store: MirStore, id: U64) -> Bool { return mir_vid_valid(id, __s0_buffer_len(MirTypeRec, store.types)) }
fn mir_vblock_index(store: MirStore, function: U64, block: U64) -> U64 {
    if block == 0 { return 0 }
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let item = __s0_buffer_get(MirBlockRec, store.blocks, at)
        if item.function == function && item.ordinal + 1 == block { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_vvalue_index(store: MirStore, function: U64, value: U64) -> U64 {
    if value == 0 { return 0 }
    var at: U64 = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let item = __s0_buffer_get(MirValueRec, store.values, at)
        if item.function == function && item.ordinal + 1 == value { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_vlocal_index(store: MirStore, function: U64, local: U64) -> U64 {
    if local == 0 { return 0 }
    var at: U64 = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let item = __s0_buffer_get(MirLocalRec, store.locals, at)
        if item.function == function && item.ordinal + 1 == local { return at + 1 }
        at = at + 1
    }
    return 0
}
fn mir_vcount_params(store: MirStore, function: U64, block: U64, kind: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let item = __s0_buffer_get(MirParamRec, store.params, at)
        if item.function == function && item.block == block && item.kind == kind { count = count + 1 }
        at = at + 1
    }
    return count
}
fn mir_vcount_operands(store: MirStore, kind: U64, owner: U64, edge: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let item = __s0_buffer_get(MirOperandRec, store.operands, at)
        if item.kind == kind && item.owner == owner && item.edge == edge { count = count + 1 }
        at = at + 1
    }
    return count
}
fn mir_vcount_type_parts(store: MirStore, owner: U64, kind: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let item = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if item.owner == owner && item.kind == kind { count = count + 1 }
        at = at + 1
    }
    return count
}
fn mir_vtype_kind(store: MirStore, id: U64) -> U64 {
    if !mir_vtype_exists(store, id) { return 999 }
    return __s0_buffer_get(MirTypeRec, store.types, id - 1).kind
}
