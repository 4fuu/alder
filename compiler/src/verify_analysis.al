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
fn mir_vname_word(store: MirStore, start: U64, end: U64, word: __s0_String) -> Bool {
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

// Per-function dense indexes built in O(F + T) by counting records per
// function (or per function/block slot) with function-local __s0_alloc
// arrays, then placing each record id once. On stores validated by phase 1
// every key is unique, so placement order never matters; new placements write
// only empty slots (first match wins), matching the legacy scan helpers
// (mir_vblock_index/mir_vvalue_index/mir_vlocal_index) on every input.
type MirVIndexes {
    block_pos: __s0_Buffer(U64)
    block_span: __s0_Buffer(U64)
    value_pos: __s0_Buffer(U64)
    value_span: __s0_Buffer(U64)
    local_pos: __s0_Buffer(U64)
    local_span: __s0_Buffer(U64)
    term_pos: __s0_Buffer(U64)
    term_span: __s0_Buffer(U64)
    block_count: __s0_Buffer(U64)
    value_count: __s0_Buffer(U64)
    local_count: __s0_Buffer(U64)
    instr_span: __s0_Buffer(U64)
    instr_count: __s0_Buffer(U64)
    instr_off: __s0_Buffer(U64)
    instr_ids: __s0_Buffer(U64)
    param_span: __s0_Buffer(U64)
    param_ids: __s0_Buffer(U64)
    op_instr_start: __s0_Buffer(U64)
    op_instr_count: __s0_Buffer(U64)
    op_instr_ids: __s0_Buffer(U64)
    op_term_start: __s0_Buffer(U64)
    op_term_count: __s0_Buffer(U64)
    op_term_ids: __s0_Buffer(U64)
    op_case_start: __s0_Buffer(U64)
    op_case_count: __s0_Buffer(U64)
    op_case_ids: __s0_Buffer(U64)
    tp_start: __s0_Buffer(U64)
    tp_count: __s0_Buffer(U64)
    tp_field_count: __s0_Buffer(U64)
    tp_ids: __s0_Buffer(U64)
    const_slot: __s0_Buffer(U64)
    type_first: __s0_Buffer(U64)
    type_unary: __s0_Buffer(U64)
    type_result_ok: __s0_Buffer(U64)
    type_result_err: __s0_Buffer(U64)
    type_result_id: __s0_Buffer(U64)
    place_root: __s0_Buffer(U64)
    place_depth: __s0_Buffer(U64)
    place_deref: __s0_Buffer(U64)
    // Memo tables over the MIR type graph, filled on demand by the
    // mir_vmemo_* helpers below. Verification never adds or patches types, so
    // a computed entry stays valid for the whole run. Writes go through
    // __s0_buffer_set, which mutates the shared backing allocation, so every
    // copy of the indexes sees the memo grow without rethreading the struct.
    contains_flag: __s0_Buffer(U64)
    contains_ans: __s0_Buffer(U64)
    forbidden_val: __s0_Buffer(U64)
    memo_seen: __s0_Buffer(U64)
    memo_gen: __s0_Buffer(U64)
}

// Intermediate results of a per-table index build. Buffers are assembled here
// and copied into MirVIndexes by mir_vindex_build.
type MirVIndexTableRec {
    pos: __s0_Buffer(U64)
    span: __s0_Buffer(U64)
    count: __s0_Buffer(U64)
}

type MirVIndexInstrRec {
    span: __s0_Buffer(U64)
    count: __s0_Buffer(U64)
    off: __s0_Buffer(U64)
    ids: __s0_Buffer(U64)
}

type MirVIndexParamRec {
    span: __s0_Buffer(U64)
    ids: __s0_Buffer(U64)
}

type MirVIndexOpsRec {
    instr_start: __s0_Buffer(U64)
    instr_count: __s0_Buffer(U64)
    instr_ids: __s0_Buffer(U64)
    term_start: __s0_Buffer(U64)
    term_count: __s0_Buffer(U64)
    term_ids: __s0_Buffer(U64)
    case_start: __s0_Buffer(U64)
    case_count: __s0_Buffer(U64)
    case_ids: __s0_Buffer(U64)
}

type MirVIndexTypePartsRec {
    start: __s0_Buffer(U64)
    count: __s0_Buffer(U64)
    field_count: __s0_Buffer(U64)
    ids: __s0_Buffer(U64)
}

type MirVIndexConstRec {
    slots: __s0_Buffer(U64)
}

type MirVIndexPlaceRec {
    root: __s0_Buffer(U64)
    depth: __s0_Buffer(U64)
    deref: __s0_Buffer(U64)
}

type MirVIndexTypeResultRec {
    ok: __s0_Buffer(U64)
    err: __s0_Buffer(U64)
    id: __s0_Buffer(U64)
}

fn mir_vindex_build_blocks(d: Domain, store: MirStore) -> Result(MirVIndexTableRec, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    let total = __s0_buffer_len(MirBlockRec, store.blocks)
    var pos = try __s0_buffer_new(U64, d)
    var span = try __s0_buffer_new(U64, d)
    var count = try __s0_buffer_new(U64, d)
    var cnt = __s0_alloc(U64, d, fcount + 1)
    var base = __s0_alloc(U64, d, fcount + 1)
    var z: U64 = 0
    while z <= fcount { cnt[z] = 0
        base[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirBlockRec, store.blocks, i).function
        if f >= 1 && f <= fcount { cnt[f] = cnt[f] + 1 }
        i = i + 1
    }
    var f: U64 = 1
    while f <= fcount { base[f] = base[f - 1] + cnt[f - 1]
        f = f + 1 }
    var ids = __s0_alloc(U64, d, total)
    var w: U64 = 0
    while w < total { ids[w] = 0
        w = w + 1 }
    i = 0
    while i < total {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, i)
        let f2 = rec.function
        if f2 >= 1 && f2 <= fcount {
            let key = rec.ordinal
            if key < cnt[f2] {
                let slot = base[f2] + key
                if ids[slot] == 0 { ids[slot] = i + 1 }
            }
        }
        i = i + 1
    }
    f = 1
    while f <= fcount {
        span = try __s0_buffer_append(U64, d, span, __s0_buffer_len(U64, pos))
        var k: U64 = 0
        while k < cnt[f] {
            pos = try __s0_buffer_append(U64, d, pos, ids[base[f] + k])
            k = k + 1
        }
        count = try __s0_buffer_append(U64, d, count, cnt[f])
        f = f + 1
    }
    return Ok(MirVIndexTableRec(pos: pos, span: span, count: count))
}

fn mir_vindex_build_values(d: Domain, store: MirStore) -> Result(MirVIndexTableRec, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    let total = __s0_buffer_len(MirValueRec, store.values)
    var pos = try __s0_buffer_new(U64, d)
    var span = try __s0_buffer_new(U64, d)
    var count = try __s0_buffer_new(U64, d)
    var cnt = __s0_alloc(U64, d, fcount + 1)
    var base = __s0_alloc(U64, d, fcount + 1)
    var z: U64 = 0
    while z <= fcount { cnt[z] = 0
        base[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirValueRec, store.values, i).function
        if f >= 1 && f <= fcount { cnt[f] = cnt[f] + 1 }
        i = i + 1
    }
    var f: U64 = 1
    while f <= fcount { base[f] = base[f - 1] + cnt[f - 1]
        f = f + 1 }
    var ids = __s0_alloc(U64, d, total)
    var w: U64 = 0
    while w < total { ids[w] = 0
        w = w + 1 }
    i = 0
    while i < total {
        let rec = __s0_buffer_get(MirValueRec, store.values, i)
        let f2 = rec.function
        if f2 >= 1 && f2 <= fcount {
            let key = rec.ordinal
            if key < cnt[f2] {
                let slot = base[f2] + key
                if ids[slot] == 0 { ids[slot] = i + 1 }
            }
        }
        i = i + 1
    }
    f = 1
    while f <= fcount {
        span = try __s0_buffer_append(U64, d, span, __s0_buffer_len(U64, pos))
        var k: U64 = 0
        while k < cnt[f] {
            pos = try __s0_buffer_append(U64, d, pos, ids[base[f] + k])
            k = k + 1
        }
        count = try __s0_buffer_append(U64, d, count, cnt[f])
        f = f + 1
    }
    return Ok(MirVIndexTableRec(pos: pos, span: span, count: count))
}

fn mir_vindex_build_locals(d: Domain, store: MirStore) -> Result(MirVIndexTableRec, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    let total = __s0_buffer_len(MirLocalRec, store.locals)
    var pos = try __s0_buffer_new(U64, d)
    var span = try __s0_buffer_new(U64, d)
    var count = try __s0_buffer_new(U64, d)
    var cnt = __s0_alloc(U64, d, fcount + 1)
    var base = __s0_alloc(U64, d, fcount + 1)
    var z: U64 = 0
    while z <= fcount { cnt[z] = 0
        base[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirLocalRec, store.locals, i).function
        if f >= 1 && f <= fcount { cnt[f] = cnt[f] + 1 }
        i = i + 1
    }
    var f: U64 = 1
    while f <= fcount { base[f] = base[f - 1] + cnt[f - 1]
        f = f + 1 }
    var ids = __s0_alloc(U64, d, total)
    var w: U64 = 0
    while w < total { ids[w] = 0
        w = w + 1 }
    i = 0
    while i < total {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, i)
        let f2 = rec.function
        if f2 >= 1 && f2 <= fcount {
            let key = rec.ordinal
            if key < cnt[f2] {
                let slot = base[f2] + key
                if ids[slot] == 0 { ids[slot] = i + 1 }
            }
        }
        i = i + 1
    }
    f = 1
    while f <= fcount {
        span = try __s0_buffer_append(U64, d, span, __s0_buffer_len(U64, pos))
        var k: U64 = 0
        while k < cnt[f] {
            pos = try __s0_buffer_append(U64, d, pos, ids[base[f] + k])
            k = k + 1
        }
        count = try __s0_buffer_append(U64, d, count, cnt[f])
        f = f + 1
    }
    return Ok(MirVIndexTableRec(pos: pos, span: span, count: count))
}

fn mir_vindex_build_terms(d: Domain, store: MirStore) -> Result(MirVIndexTableRec, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    let total = __s0_buffer_len(MirTermRec, store.terminators)
    var pos = try __s0_buffer_new(U64, d)
    var span = try __s0_buffer_new(U64, d)
    var count = try __s0_buffer_new(U64, d)
    var cnt = __s0_alloc(U64, d, fcount + 1)
    var base = __s0_alloc(U64, d, fcount + 1)
    var z: U64 = 0
    while z <= fcount { cnt[z] = 0
        base[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirTermRec, store.terminators, i).function
        if f >= 1 && f <= fcount { cnt[f] = cnt[f] + 1 }
        i = i + 1
    }
    var f: U64 = 1
    while f <= fcount { base[f] = base[f - 1] + cnt[f - 1]
        f = f + 1 }
    var ids = __s0_alloc(U64, d, total)
    var w: U64 = 0
    while w < total { ids[w] = 0
        w = w + 1 }
    i = 0
    while i < total {
        let rec = __s0_buffer_get(MirTermRec, store.terminators, i)
        let f2 = rec.function
        if f2 >= 1 && f2 <= fcount && rec.block >= 1 {
            let key = rec.block - 1
            if key < cnt[f2] {
                let slot = base[f2] + key
                if ids[slot] == 0 { ids[slot] = i + 1 }
            }
        }
        i = i + 1
    }
    f = 1
    while f <= fcount {
        span = try __s0_buffer_append(U64, d, span, __s0_buffer_len(U64, pos))
        var k: U64 = 0
        while k < cnt[f] {
            pos = try __s0_buffer_append(U64, d, pos, ids[base[f] + k])
            k = k + 1
        }
        count = try __s0_buffer_append(U64, d, count, cnt[f])
        f = f + 1
    }
    return Ok(MirVIndexTableRec(pos: pos, span: span, count: count))
}

// Instructions are keyed by the dense per-function block slot
// (block_span[function - 1] + block - 1); instr_count/instr_off are indexed
// by that slot, instr_ids is flat per function (blocks ascending, ordinals
// ascending), and instr_span[function - 1] is the function's base offset.
fn mir_vindex_build_instrs(d: Domain, store: MirStore, blocks: MirVIndexTableRec) -> Result(MirVIndexInstrRec, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    let btotal = __s0_buffer_len(U64, blocks.pos)
    let itotal = __s0_buffer_len(MirInstrRec, store.instructions)
    var icnt = __s0_alloc(U64, d, btotal)
    var ioff = __s0_alloc(U64, d, btotal + 1)
    var z: U64 = 0
    while z < btotal { icnt[z] = 0
        z = z + 1 }
    z = 0
    while z <= btotal { ioff[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < itotal {
        let ins = __s0_buffer_get(MirInstrRec, store.instructions, i)
        let f = ins.function
        if f >= 1 && f <= fcount && ins.block >= 1 && ins.block <= __s0_buffer_get(U64, blocks.count, f - 1) {
            let slot = __s0_buffer_get(U64, blocks.span, f - 1) + ins.block - 1
            if slot < btotal { icnt[slot] = icnt[slot] + 1 }
        }
        i = i + 1
    }
    var s: U64 = 0
    while s < btotal { ioff[s + 1] = ioff[s] + icnt[s]
        s = s + 1 }
    var ids = __s0_alloc(U64, d, itotal)
    var w: U64 = 0
    while w < itotal { ids[w] = 0
        w = w + 1 }
    i = 0
    while i < itotal {
        let ins = __s0_buffer_get(MirInstrRec, store.instructions, i)
        let f2 = ins.function
        if f2 >= 1 && f2 <= fcount && ins.block >= 1 && ins.block <= __s0_buffer_get(U64, blocks.count, f2 - 1) {
            let slot = __s0_buffer_get(U64, blocks.span, f2 - 1) + ins.block - 1
            if slot < btotal && ins.ordinal < icnt[slot] {
                let pos = ioff[slot] + ins.ordinal
                if ids[pos] == 0 { ids[pos] = i + 1 }
            }
        }
        i = i + 1
    }
    var span = try __s0_buffer_new(U64, d)
    var count = try __s0_buffer_new(U64, d)
    var off = try __s0_buffer_new(U64, d)
    var ids_buf = try __s0_buffer_new(U64, d)
    var f: U64 = 1
    while f <= fcount {
        span = try __s0_buffer_append(U64, d, span, ioff[__s0_buffer_get(U64, blocks.span, f - 1)])
        f = f + 1
    }
    var fb: U64 = 1
    s = 0
    while s < btotal {
        while fb < fcount && s >= __s0_buffer_get(U64, blocks.span, fb - 1) + __s0_buffer_get(U64, blocks.count, fb - 1) { fb = fb + 1 }
        count = try __s0_buffer_append(U64, d, count, icnt[s])
        off = try __s0_buffer_append(U64, d, off, ioff[s] - ioff[__s0_buffer_get(U64, blocks.span, fb - 1)])
        s = s + 1
    }
    s = 0
    while s < btotal {
        var k: U64 = 0
        while k < icnt[s] {
            ids_buf = try __s0_buffer_append(U64, d, ids_buf, ids[ioff[s] + k])
            k = k + 1
        }
        s = s + 1
    }
    return Ok(MirVIndexInstrRec(span: span, count: count, off: off, ids: ids_buf))
}

// Params per function, store order preserved within each function.
fn mir_vindex_build_params(d: Domain, store: MirStore) -> Result(MirVIndexParamRec, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    let total = __s0_buffer_len(MirParamRec, store.params)
    var cnt = __s0_alloc(U64, d, fcount + 1)
    var start = __s0_alloc(U64, d, fcount + 1)
    var z: U64 = 0
    while z <= fcount { cnt[z] = 0
        start[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirParamRec, store.params, i).function
        if f >= 1 && f <= fcount { cnt[f] = cnt[f] + 1 }
        i = i + 1
    }
    var f: U64 = 1
    while f <= fcount { start[f] = start[f - 1] + cnt[f - 1]
        f = f + 1 }
    var ids = __s0_alloc(U64, d, total)
    var used = __s0_alloc(U64, d, fcount + 1)
    var w: U64 = 0
    while w < total { ids[w] = 0
        w = w + 1 }
    w = 0
    while w <= fcount { used[w] = 0
        w = w + 1 }
    i = 0
    while i < total {
        let rec = __s0_buffer_get(MirParamRec, store.params, i)
        let f2 = rec.function
        if f2 >= 1 && f2 <= fcount {
            let pos = start[f2] + used[f2]
            ids[pos] = i + 1
            used[f2] = used[f2] + 1
        }
        i = i + 1
    }
    var span = try __s0_buffer_new(U64, d)
    var ids_buf = try __s0_buffer_new(U64, d)
    f = 1
    while f <= fcount {
        span = try __s0_buffer_append(U64, d, span, start[f])
        var k: U64 = 0
        while k < cnt[f] {
            ids_buf = try __s0_buffer_append(U64, d, ids_buf, ids[start[f] + k])
            k = k + 1
        }
        f = f + 1
    }
    return Ok(MirVIndexParamRec(span: span, ids: ids_buf))
}

// Operand owner lists: op_instr (owners are instruction ids, kinds
// instruction/aggregate_field/checked_edge_arg), op_term (owners are
// terminator ids, kinds terminator_arg/switch_case), op_case (owners are
// switch-case operand ids, kind switch_case_arg). Within each owner list the
// operand ids stay in store (ascending id) order. Operands whose owner is 0
// or exceeds the owner space are skipped; no query can ever address them.
fn mir_vindex_build_ops(d: Domain, store: MirStore) -> Result(MirVIndexOpsRec, __s0_Error) {
    let icount = __s0_buffer_len(MirInstrRec, store.instructions)
    let tcount = __s0_buffer_len(MirTermRec, store.terminators)
    let ocount = __s0_buffer_len(MirOperandRec, store.operands)
    var icnt = __s0_alloc(U64, d, icount + 1)
    var tcnt = __s0_alloc(U64, d, tcount + 1)
    var ccnt = __s0_alloc(U64, d, ocount + 1)
    var z: U64 = 0
    while z <= icount { icnt[z] = 0
        z = z + 1 }
    z = 0
    while z <= tcount { tcnt[z] = 0
        z = z + 1 }
    z = 0
    while z <= ocount { ccnt[z] = 0
        z = z + 1 }
    var total_i: U64 = 0
    var total_t: U64 = 0
    var total_c: U64 = 0
    var i: U64 = 0
    while i < ocount {
        let o = __s0_buffer_get(MirOperandRec, store.operands, i)
        if o.kind == mir_operand_instruction() || o.kind == mir_operand_aggregate_field() || o.kind == mir_operand_checked_edge_arg() {
            if o.owner >= 1 && o.owner <= icount { icnt[o.owner] = icnt[o.owner] + 1
                total_i = total_i + 1 }
        }
        if o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case() {
            if o.owner >= 1 && o.owner <= tcount { tcnt[o.owner] = tcnt[o.owner] + 1
                total_t = total_t + 1 }
        }
        if o.kind == mir_operand_switch_case_arg() {
            if o.owner >= 1 && o.owner <= ocount { ccnt[o.owner] = ccnt[o.owner] + 1
                total_c = total_c + 1 }
        }
        i = i + 1
    }
    var istart = __s0_alloc(U64, d, icount + 1)
    var tstart = __s0_alloc(U64, d, tcount + 1)
    var cstart = __s0_alloc(U64, d, ocount + 1)
    z = 0
    while z <= icount { istart[z] = 0
        z = z + 1 }
    z = 0
    while z <= tcount { tstart[z] = 0
        z = z + 1 }
    z = 0
    while z <= ocount { cstart[z] = 0
        z = z + 1 }
    var owner: U64 = 1
    while owner <= icount { istart[owner] = istart[owner - 1] + icnt[owner - 1]
        owner = owner + 1 }
    owner = 1
    while owner <= tcount { tstart[owner] = tstart[owner - 1] + tcnt[owner - 1]
        owner = owner + 1 }
    owner = 1
    while owner <= ocount { cstart[owner] = cstart[owner - 1] + ccnt[owner - 1]
        owner = owner + 1 }
    var iids = __s0_alloc(U64, d, total_i)
    var tids = __s0_alloc(U64, d, total_t)
    var cids = __s0_alloc(U64, d, total_c)
    var iused = __s0_alloc(U64, d, icount + 1)
    var tused = __s0_alloc(U64, d, tcount + 1)
    var cused = __s0_alloc(U64, d, ocount + 1)
    var w: U64 = 0
    while w < total_i { iids[w] = 0
        w = w + 1 }
    w = 0
    while w < total_t { tids[w] = 0
        w = w + 1 }
    w = 0
    while w < total_c { cids[w] = 0
        w = w + 1 }
    w = 0
    while w <= icount { iused[w] = 0
        w = w + 1 }
    w = 0
    while w <= tcount { tused[w] = 0
        w = w + 1 }
    w = 0
    while w <= ocount { cused[w] = 0
        w = w + 1 }
    i = 0
    while i < ocount {
        let o = __s0_buffer_get(MirOperandRec, store.operands, i)
        if o.kind == mir_operand_instruction() || o.kind == mir_operand_aggregate_field() || o.kind == mir_operand_checked_edge_arg() {
            if o.owner >= 1 && o.owner <= icount {
                let pos = istart[o.owner] + iused[o.owner]
                iids[pos] = i + 1
                iused[o.owner] = iused[o.owner] + 1
            }
        }
        if o.kind == mir_operand_terminator_arg() || o.kind == mir_operand_switch_case() {
            if o.owner >= 1 && o.owner <= tcount {
                let pos = tstart[o.owner] + tused[o.owner]
                tids[pos] = i + 1
                tused[o.owner] = tused[o.owner] + 1
            }
        }
        if o.kind == mir_operand_switch_case_arg() {
            if o.owner >= 1 && o.owner <= ocount {
                let pos = cstart[o.owner] + cused[o.owner]
                cids[pos] = i + 1
                cused[o.owner] = cused[o.owner] + 1
            }
        }
        i = i + 1
    }
    var instr_start = try __s0_buffer_new(U64, d)
    var instr_count = try __s0_buffer_new(U64, d)
    var instr_ids = try __s0_buffer_new(U64, d)
    var term_start = try __s0_buffer_new(U64, d)
    var term_count = try __s0_buffer_new(U64, d)
    var term_ids = try __s0_buffer_new(U64, d)
    var case_start = try __s0_buffer_new(U64, d)
    var case_count = try __s0_buffer_new(U64, d)
    var case_ids = try __s0_buffer_new(U64, d)
    owner = 1
    while owner <= icount {
        instr_start = try __s0_buffer_append(U64, d, instr_start, istart[owner])
        instr_count = try __s0_buffer_append(U64, d, instr_count, icnt[owner])
        owner = owner + 1
    }
    owner = 1
    while owner <= icount {
        var k: U64 = 0
        while k < icnt[owner] {
            instr_ids = try __s0_buffer_append(U64, d, instr_ids, iids[istart[owner] + k])
            k = k + 1
        }
        owner = owner + 1
    }
    owner = 1
    while owner <= tcount {
        term_start = try __s0_buffer_append(U64, d, term_start, tstart[owner])
        term_count = try __s0_buffer_append(U64, d, term_count, tcnt[owner])
        owner = owner + 1
    }
    owner = 1
    while owner <= tcount {
        var k: U64 = 0
        while k < tcnt[owner] {
            term_ids = try __s0_buffer_append(U64, d, term_ids, tids[tstart[owner] + k])
            k = k + 1
        }
        owner = owner + 1
    }
    owner = 1
    while owner <= ocount {
        case_start = try __s0_buffer_append(U64, d, case_start, cstart[owner])
        case_count = try __s0_buffer_append(U64, d, case_count, ccnt[owner])
        owner = owner + 1
    }
    owner = 1
    while owner <= ocount {
        var k: U64 = 0
        while k < ccnt[owner] {
            case_ids = try __s0_buffer_append(U64, d, case_ids, cids[cstart[owner] + k])
            k = k + 1
        }
        owner = owner + 1
    }
    return Ok(MirVIndexOpsRec(instr_start: instr_start, instr_count: instr_count, instr_ids: instr_ids, term_start: term_start, term_count: term_count, term_ids: term_ids, case_start: case_start, case_count: case_count, case_ids: case_ids))
}

// Type parts per owner type id, ascending id order.
fn mir_vindex_build_type_parts(d: Domain, store: MirStore) -> Result(MirVIndexTypePartsRec, __s0_Error) {
    let tcount = __s0_buffer_len(MirTypeRec, store.types)
    let total = __s0_buffer_len(MirTypePartRec, store.type_parts)
    var cnt = __s0_alloc(U64, d, tcount + 1)
    var field_cnt = __s0_alloc(U64, d, tcount + 1)
    var start = __s0_alloc(U64, d, tcount + 1)
    var z: U64 = 0
    while z <= tcount { cnt[z] = 0
        field_cnt[z] = 0
        start[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirTypePartRec, store.type_parts, i).owner
        if f >= 1 && f <= tcount { cnt[f] = cnt[f] + 1
            if __s0_buffer_get(MirTypePartRec, store.type_parts, i).kind == mir_type_part_field() { field_cnt[f] = field_cnt[f] + 1 } }
        i = i + 1
    }
    var f: U64 = 1
    while f <= tcount { start[f] = start[f - 1] + cnt[f - 1]
        f = f + 1 }
    var ids = __s0_alloc(U64, d, total)
    var used = __s0_alloc(U64, d, tcount + 1)
    var w: U64 = 0
    while w < total { ids[w] = 0
        w = w + 1 }
    w = 0
    while w <= tcount { used[w] = 0
        w = w + 1 }
    i = 0
    while i < total {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, i)
        let f2 = rec.owner
        if f2 >= 1 && f2 <= tcount {
            let pos = start[f2] + used[f2]
            ids[pos] = i + 1
            used[f2] = used[f2] + 1
        }
        i = i + 1
    }
    var start_buf = try __s0_buffer_new(U64, d)
    var count_buf = try __s0_buffer_new(U64, d)
    var field_count_buf = try __s0_buffer_new(U64, d)
    var ids_buf = try __s0_buffer_new(U64, d)
    f = 1
    while f <= tcount {
        start_buf = try __s0_buffer_append(U64, d, start_buf, start[f])
        count_buf = try __s0_buffer_append(U64, d, count_buf, cnt[f])
        field_count_buf = try __s0_buffer_append(U64, d, field_count_buf, field_cnt[f])
        f = f + 1
    }
    f = 1
    while f <= tcount {
        var k: U64 = 0
        while k < cnt[f] {
            ids_buf = try __s0_buffer_append(U64, d, ids_buf, ids[start[f] + k])
            k = k + 1
        }
        f = f + 1
    }
    return Ok(MirVIndexTypePartsRec(start: start_buf, count: count_buf, field_count: field_count_buf, ids: ids_buf))
}

fn mir_vindex_hash_byte(byte: U8) -> U64 {
    var rest = byte
    var value: U64 = 0
    if rest >= 128 { rest = rest - 128
        value = value + 128 }
    if rest >= 64 { rest = rest - 64
        value = value + 64 }
    if rest >= 32 { rest = rest - 32
        value = value + 32 }
    if rest >= 16 { rest = rest - 16
        value = value + 16 }
    if rest >= 8 { rest = rest - 8
        value = value + 8 }
    if rest >= 4 { rest = rest - 4
        value = value + 4 }
    if rest >= 2 { rest = rest - 2
        value = value + 2 }
    if rest >= 1 { value = value + 1 }
    return value
}

fn mir_vindex_hash_add(left: U64, right: U64, modulus: U64) -> U64 {
    if left >= modulus - right { return left - (modulus - right) }
    return left + right
}

fn mir_vindex_name_hash(store: MirStore, start: U64, end: U64, buckets: U64) -> U64 {
    if buckets == 0 { return 0 }
    if !mir_vrange_valid(start, end, __s0_buffer_len(U8, store.names)) { return 0 }
    var hash: U64 = 0
    var at = start
    while at < end { let original = hash
        var shifted = hash
        var bit: U64 = 0
        while bit < 8 { shifted = mir_vindex_hash_add(shifted, shifted, buckets)
            bit = bit + 1 }
        hash = mir_vindex_hash_add(shifted, original, buckets)
        let byte = mir_vindex_hash_byte(__s0_buffer_get(U8, store.names, at)) % buckets
        hash = mir_vindex_hash_add(hash, byte, buckets)
        at = at + 1
    }
    return hash
}

fn mir_vindex_build_constants(d: Domain, store: MirStore) -> Result(MirVIndexConstRec, __s0_Error) {
    let count = __s0_buffer_len(MirConstRec, store.constants)
    let bucket_count = count * 2 + 1
    var hashes = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < count { let item = __s0_buffer_get(MirConstRec, store.constants, at)
        hashes = try __s0_buffer_append(U64, d, hashes, mir_vindex_name_hash(store, item.name_start, item.name_end, bucket_count))
        at = at + 1
    }
    var slots = __s0_alloc(U64, d, bucket_count)
    at = 0
    while at < bucket_count { slots[at] = 0
        at = at + 1
    }
    at = 1
    while at <= count {
        var slot = __s0_buffer_get(U64, hashes, at - 1)
        var placed = false
        while !placed {
            if slots[slot] == 0 { slots[slot] = at
                placed = true } else {
                let existing = __s0_buffer_get(MirConstRec, store.constants, slots[slot] - 1)
                let current = __s0_buffer_get(MirConstRec, store.constants, at - 1)
                if mir_vname_equal(store, current.name_start, current.name_end, existing.name_start, existing.name_end) { placed = true } else { slot = (slot + 1) % bucket_count }
            }
        }
        at = at + 1
    }
    var slot_buf = try __s0_buffer_new(U64, d)
    at = 0
    while at < bucket_count { slot_buf = try __s0_buffer_append(U64, d, slot_buf, slots[at])
        at = at + 1
    }
    return Ok(MirVIndexConstRec(slots: slot_buf))
}

fn mir_vindex_build_value_names(d: Domain, store: MirStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    let count = __s0_buffer_len(MirValueRec, store.values)
    let bucket_count = count * 2 + 1
    var hashes = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < count { let item = __s0_buffer_get(MirValueRec, store.values, at)
        let name_hash = mir_vindex_name_hash(store, item.name_start, item.name_end, bucket_count)
        hashes = try __s0_buffer_append(U64, d, hashes, mir_vindex_hash_add(name_hash, item.function % bucket_count, bucket_count))
        at = at + 1
    }
    var slots = __s0_alloc(U64, d, bucket_count)
    at = 0
    while at < bucket_count { slots[at] = 0
        at = at + 1
    }
    at = 1
    while at <= count {
        var slot = __s0_buffer_get(U64, hashes, at - 1)
        var placed = false
        while !placed {
            if slots[slot] == 0 { slots[slot] = at
                placed = true } else {
                let existing = __s0_buffer_get(MirValueRec, store.values, slots[slot] - 1)
                let current = __s0_buffer_get(MirValueRec, store.values, at - 1)
                if current.function == existing.function && mir_vname_equal(store, current.name_start, current.name_end, existing.name_start, existing.name_end) { placed = true } else { slot = (slot + 1) % bucket_count }
            }
        }
        at = at + 1
    }
    var out = try __s0_buffer_new(U64, d)
    at = 0
    while at < bucket_count { out = try __s0_buffer_append(U64, d, out, slots[at])
        at = at + 1
    }
    return Ok(out)
}

fn mir_vindex_build_local_names(d: Domain, store: MirStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    let count = __s0_buffer_len(MirLocalRec, store.locals)
    let bucket_count = count * 2 + 1
    var hashes = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < count { let item = __s0_buffer_get(MirLocalRec, store.locals, at)
        let name_hash = mir_vindex_name_hash(store, item.name_start, item.name_end, bucket_count)
        hashes = try __s0_buffer_append(U64, d, hashes, mir_vindex_hash_add(name_hash, item.function % bucket_count, bucket_count))
        at = at + 1
    }
    var slots = __s0_alloc(U64, d, bucket_count)
    at = 0
    while at < bucket_count { slots[at] = 0
        at = at + 1
    }
    at = 1
    while at <= count {
        var slot = __s0_buffer_get(U64, hashes, at - 1)
        var placed = false
        while !placed {
            if slots[slot] == 0 { slots[slot] = at
                placed = true } else {
                let existing = __s0_buffer_get(MirLocalRec, store.locals, slots[slot] - 1)
                let current = __s0_buffer_get(MirLocalRec, store.locals, at - 1)
                if current.function == existing.function && mir_vname_equal(store, current.name_start, current.name_end, existing.name_start, existing.name_end) { placed = true } else { slot = (slot + 1) % bucket_count }
            }
        }
        at = at + 1
    }
    var out = try __s0_buffer_new(U64, d)
    at = 0
    while at < bucket_count { out = try __s0_buffer_append(U64, d, out, slots[at])
        at = at + 1
    }
    return Ok(out)
}

fn mir_vindex_build_type_first(d: Domain, store: MirStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    let kind_count = mir_type_kind_c_string() + 1
    var first = __s0_alloc(U64, d, kind_count)
    var at: U64 = 0
    while at < kind_count { first[at] = 0
        at = at + 1
    }
    at = 1
    while at <= __s0_buffer_len(MirTypeRec, store.types) { let item = __s0_buffer_get(MirTypeRec, store.types, at - 1)
        if item.kind < kind_count && first[item.kind] == 0 { first[item.kind] = at }
        at = at + 1
    }
    var out = try __s0_buffer_new(U64, d)
    at = 0
    while at < kind_count { out = try __s0_buffer_append(U64, d, out, first[at])
        at = at + 1
    }
    return Ok(out)
}

fn mir_vindex_build_type_unary(d: Domain, store: MirStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    let kind_count = mir_type_kind_c_string() + 1
    let type_count = __s0_buffer_len(MirTypeRec, store.types)
    let slot_count = kind_count * type_count
    var first = __s0_alloc(U64, d, slot_count)
    var at: U64 = 0
    while at < slot_count { first[at] = 0
        at = at + 1
    }
    at = 1
    while at <= type_count { let item = __s0_buffer_get(MirTypeRec, store.types, at - 1)
        if item.kind < kind_count && item.elem >= 1 && item.elem <= type_count { let slot = item.kind * type_count + item.elem - 1
            if first[slot] == 0 { first[slot] = at } }
        at = at + 1
    }
    var out = try __s0_buffer_new(U64, d)
    at = 0
    while at < slot_count { out = try __s0_buffer_append(U64, d, out, first[at])
        at = at + 1
    }
    return Ok(out)
}

fn mir_vindex_build_type_results(d: Domain, store: MirStore) -> Result(MirVIndexTypeResultRec, __s0_Error) {
    // One compact entry per interned result type: ok payload, err payload,
    // and the type id itself. The list stays small because only Result-using
    // programs intern result types, and lookups scan it linearly.
    var oks = try __s0_buffer_new(U64, d)
    var errs = try __s0_buffer_new(U64, d)
    var ids = try __s0_buffer_new(U64, d)
    var at: U64 = 1
    while at <= __s0_buffer_len(MirTypeRec, store.types) { let item = __s0_buffer_get(MirTypeRec, store.types, at - 1)
        if item.kind == mir_type_kind_result() {
            oks = try __s0_buffer_append(U64, d, oks, item.ok_type)
            errs = try __s0_buffer_append(U64, d, errs, item.err_type)
            ids = try __s0_buffer_append(U64, d, ids, at)
        }
        at = at + 1
    }
    return Ok(MirVIndexTypeResultRec(ok: oks, err: errs, id: ids))
}

fn mir_vindex_build_places(d: Domain, store: MirStore) -> Result(MirVIndexPlaceRec, __s0_Error) {
    let total = __s0_buffer_len(MirPlaceRec, store.places)
    var roots = try __s0_buffer_new(U64, d)
    var depths = try __s0_buffer_new(U64, d)
    var derefs = try __s0_buffer_new(U64, d)
    var at: U64 = 1
    while at <= total {
        var current = at
        var root: U64 = 0
        var depth: U64 = 0
        var deref: U64 = 0
        var steps: U64 = 0
        while current != 0 && current <= total && steps <= total {
            let place = __s0_buffer_get(MirPlaceRec, store.places, current - 1)
            if place.kind == mir_place_local() { root = place.local
                current = 0 } else { if place.kind == mir_place_field() { depth = depth + 1
                    current = place.base } else { if place.kind == mir_place_deref() { deref = 1 }
                    current = 0 } }
            steps = steps + 1
        }
        roots = try __s0_buffer_append(U64, d, roots, root)
        depths = try __s0_buffer_append(U64, d, depths, depth)
        derefs = try __s0_buffer_append(U64, d, derefs, deref)
        at = at + 1
    }
    return Ok(MirVIndexPlaceRec(root: roots, depth: depths, deref: derefs))
}

fn mir_vindex_build(d: Domain, store: MirStore) -> Result(MirVIndexes, __s0_Error) {
    let count_types = __s0_buffer_len(MirTypeRec, store.types)
    let blocks = try mir_vindex_build_blocks(d, store)
    let values = try mir_vindex_build_values(d, store)
    let locals = try mir_vindex_build_locals(d, store)
    let terms = try mir_vindex_build_terms(d, store)
    let instrs = try mir_vindex_build_instrs(d, store, blocks)
    let params = try mir_vindex_build_params(d, store)
    let ops = try mir_vindex_build_ops(d, store)
    let tps = try mir_vindex_build_type_parts(d, store)
    let constants = try mir_vindex_build_constants(d, store)
    let type_first = try mir_vindex_build_type_first(d, store)
    let type_unary = try mir_vindex_build_type_unary(d, store)
    let type_results = try mir_vindex_build_type_results(d, store)
    let places = try mir_vindex_build_places(d, store)
    // Zeroed memo tables sized once here: verification freezes the type list,
    // so (count+1)*22 kind answers and (count+1) verdicts and generations
    // never need to grow. Filling them is a few append loops at build time.
    var memo_at: U64 = 0
    let memo_cells = (count_types + 1) * mir_vmemo_kind_columns()
    var contains_flag = try __s0_buffer_new(U64, d)
    var contains_ans = try __s0_buffer_new(U64, d)
    while memo_at < memo_cells {
        contains_flag = try __s0_buffer_append(U64, d, contains_flag, 0)
        contains_ans = try __s0_buffer_append(U64, d, contains_ans, 0)
        memo_at = memo_at + 1
    }
    memo_at = 0
    var forbidden_val = try __s0_buffer_new(U64, d)
    var memo_seen = try __s0_buffer_new(U64, d)
    while memo_at <= count_types {
        forbidden_val = try __s0_buffer_append(U64, d, forbidden_val, 0)
        memo_seen = try __s0_buffer_append(U64, d, memo_seen, 0)
        memo_at = memo_at + 1
    }
    var memo_gen = try __s0_buffer_new(U64, d)
    memo_gen = try __s0_buffer_append(U64, d, memo_gen, 0)
    return Ok(MirVIndexes(block_pos: blocks.pos, block_span: blocks.span, value_pos: values.pos, value_span: values.span, local_pos: locals.pos, local_span: locals.span, term_pos: terms.pos, term_span: terms.span, block_count: blocks.count, value_count: values.count, local_count: locals.count, instr_span: instrs.span, instr_count: instrs.count, instr_off: instrs.off, instr_ids: instrs.ids, param_span: params.span, param_ids: params.ids, op_instr_start: ops.instr_start, op_instr_count: ops.instr_count, op_instr_ids: ops.instr_ids, op_term_start: ops.term_start, op_term_count: ops.term_count, op_term_ids: ops.term_ids, op_case_start: ops.case_start, op_case_count: ops.case_count, op_case_ids: ops.case_ids, tp_start: tps.start, tp_count: tps.count, tp_field_count: tps.field_count, tp_ids: tps.ids, const_slot: constants.slots, type_first: type_first, type_unary: type_unary, type_result_ok: type_results.ok, type_result_err: type_results.err, type_result_id: type_results.id, place_root: places.root, place_depth: places.depth, place_deref: places.deref, contains_flag: contains_flag, contains_ans: contains_ans, forbidden_val: forbidden_val, memo_seen: memo_seen, memo_gen: memo_gen))
}

fn mir_vindex_block(indexes: MirVIndexes, function: U64, block: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.block_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.block_count, function - 1)
    if block == 0 || block > count { return 0 }
    return __s0_buffer_get(U64, indexes.block_pos, __s0_buffer_get(U64, indexes.block_span, function - 1) + block - 1)
}

fn mir_vindex_value(indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.value_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.value_count, function - 1)
    if value == 0 || value > count { return 0 }
    return __s0_buffer_get(U64, indexes.value_pos, __s0_buffer_get(U64, indexes.value_span, function - 1) + value - 1)
}

fn mir_vindex_const_slots(store: MirStore, slots: __s0_Buffer(U64), start: U64, end: U64) -> U64 {
    let buckets = __s0_buffer_len(U64, slots)
    if buckets == 0 { return 0 }
    var slot = mir_vindex_name_hash(store, start, end, buckets)
    var probes: U64 = 0
    while probes < buckets { let id = __s0_buffer_get(U64, slots, slot)
        if id == 0 { return 0 }
        let item = __s0_buffer_get(MirConstRec, store.constants, id - 1)
        if mir_vname_equal(store, start, end, item.name_start, item.name_end) { return id }
        slot = (slot + 1) % buckets
        probes = probes + 1
    }
    return 0
}

fn mir_vindex_const(store: MirStore, indexes: MirVIndexes, start: U64, end: U64) -> U64 {
    return mir_vindex_const_slots(store, indexes.const_slot, start, end)
}

fn mir_vindex_value_name(store: MirStore, slots: __s0_Buffer(U64), function: U64, start: U64, end: U64) -> U64 {
    let buckets = __s0_buffer_len(U64, slots)
    if buckets == 0 { return 0 }
    let name_hash = mir_vindex_name_hash(store, start, end, buckets)
    var slot = mir_vindex_hash_add(name_hash, function % buckets, buckets)
    var probes: U64 = 0
    while probes < buckets { let id = __s0_buffer_get(U64, slots, slot)
        if id == 0 { return 0 }
        let item = __s0_buffer_get(MirValueRec, store.values, id - 1)
        if item.function == function && mir_vname_equal(store, start, end, item.name_start, item.name_end) { return id }
        slot = (slot + 1) % buckets
        probes = probes + 1
    }
    return 0
}

fn mir_vindex_local_name(store: MirStore, slots: __s0_Buffer(U64), function: U64, start: U64, end: U64) -> U64 {
    let buckets = __s0_buffer_len(U64, slots)
    if buckets == 0 { return 0 }
    let name_hash = mir_vindex_name_hash(store, start, end, buckets)
    var slot = mir_vindex_hash_add(name_hash, function % buckets, buckets)
    var probes: U64 = 0
    while probes < buckets { let id = __s0_buffer_get(U64, slots, slot)
        if id == 0 { return 0 }
        let item = __s0_buffer_get(MirLocalRec, store.locals, id - 1)
        if item.function == function && mir_vname_equal(store, start, end, item.name_start, item.name_end) { return id }
        slot = (slot + 1) % buckets
        probes = probes + 1
    }
    return 0
}

fn mir_vindex_type_kind(indexes: MirVIndexes, kind: U64) -> U64 {
    if kind >= __s0_buffer_len(U64, indexes.type_first) { return 0 }
    return __s0_buffer_get(U64, indexes.type_first, kind)
}

fn mir_vindex_type_unary(indexes: MirVIndexes, kind: U64, elem: U64) -> U64 {
    let kind_count = __s0_buffer_len(U64, indexes.type_first)
    let type_count = __s0_buffer_len(U64, indexes.type_unary) / kind_count
    if kind >= kind_count || elem == 0 || elem > type_count { return 0 }
    return __s0_buffer_get(U64, indexes.type_unary, kind * type_count + elem - 1)
}

fn mir_vindex_type_result(indexes: MirVIndexes, ok: U64, err: U64) -> U64 {
    let count = __s0_buffer_len(U64, indexes.type_result_id)
    var at: U64 = 0
    while at < count {
        if __s0_buffer_get(U64, indexes.type_result_ok, at) == ok && __s0_buffer_get(U64, indexes.type_result_err, at) == err { return __s0_buffer_get(U64, indexes.type_result_id, at) }
        at = at + 1
    }
    return 0
}

fn mir_vindex_place_root(indexes: MirVIndexes, place: U64) -> U64 {
    if place == 0 || place > __s0_buffer_len(U64, indexes.place_root) { return 0 }
    return __s0_buffer_get(U64, indexes.place_root, place - 1)
}

fn mir_vindex_place_depth(indexes: MirVIndexes, place: U64) -> U64 {
    if place == 0 || place > __s0_buffer_len(U64, indexes.place_depth) { return 0 }
    return __s0_buffer_get(U64, indexes.place_depth, place - 1)
}

fn mir_vindex_place_deref(indexes: MirVIndexes, place: U64) -> Bool {
    if place == 0 || place > __s0_buffer_len(U64, indexes.place_deref) { return false }
    return __s0_buffer_get(U64, indexes.place_deref, place - 1) != 0
}

fn mir_vindex_local(indexes: MirVIndexes, function: U64, local: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.local_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.local_count, function - 1)
    if local == 0 || local > count { return 0 }
    return __s0_buffer_get(U64, indexes.local_pos, __s0_buffer_get(U64, indexes.local_span, function - 1) + local - 1)
}

fn mir_vindex_term(indexes: MirVIndexes, function: U64, block: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.block_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.block_count, function - 1)
    if block == 0 || block > count { return 0 }
    return __s0_buffer_get(U64, indexes.term_pos, __s0_buffer_get(U64, indexes.term_span, function - 1) + block - 1)
}

fn mir_vindex_block_count(indexes: MirVIndexes, function: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.block_count) { return 0 }
    return __s0_buffer_get(U64, indexes.block_count, function - 1)
}

// 1-based instruction record id for (function, block, ordinal); 0 when the
// key is out of range. ordinal is 0-based.
fn mir_vindex_instr(indexes: MirVIndexes, function: U64, block: U64, ordinal: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.block_count) { return 0 }
    let bcount = __s0_buffer_get(U64, indexes.block_count, function - 1)
    if block == 0 || block > bcount { return 0 }
    let slot = __s0_buffer_get(U64, indexes.block_span, function - 1) + block - 1
    let icount = __s0_buffer_get(U64, indexes.instr_count, slot)
    if ordinal >= icount { return 0 }
    return __s0_buffer_get(U64, indexes.instr_ids, __s0_buffer_get(U64, indexes.instr_span, function - 1) + __s0_buffer_get(U64, indexes.instr_off, slot) + ordinal)
}

fn mir_vindex_instr_count(indexes: MirVIndexes, function: U64, block: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.block_count) { return 0 }
    let bcount = __s0_buffer_get(U64, indexes.block_count, function - 1)
    if block == 0 || block > bcount { return 0 }
    let slot = __s0_buffer_get(U64, indexes.block_span, function - 1) + block - 1
    return __s0_buffer_get(U64, indexes.instr_count, slot)
}

fn mir_vindex_param_count(indexes: MirVIndexes, function: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.param_span) { return 0 }
    if function < __s0_buffer_len(U64, indexes.param_span) {
        return __s0_buffer_get(U64, indexes.param_span, function) - __s0_buffer_get(U64, indexes.param_span, function - 1)
    }
    return __s0_buffer_len(U64, indexes.param_ids) - __s0_buffer_get(U64, indexes.param_span, function - 1)
}

// at is 0-based; params are returned in ascending store order.
fn mir_vindex_param(indexes: MirVIndexes, function: U64, at: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, indexes.param_span) { return 0 }
    let base = __s0_buffer_get(U64, indexes.param_span, function - 1)
    var count: U64 = 0
    if function < __s0_buffer_len(U64, indexes.param_span) {
        count = __s0_buffer_get(U64, indexes.param_span, function) - base
    } else {
        count = __s0_buffer_len(U64, indexes.param_ids) - base
    }
    if at >= count { return 0 }
    return __s0_buffer_get(U64, indexes.param_ids, base + at)
}

fn mir_vindex_op_instr_count(indexes: MirVIndexes, instr_id: U64) -> U64 {
    if instr_id == 0 || instr_id > __s0_buffer_len(U64, indexes.op_instr_count) { return 0 }
    return __s0_buffer_get(U64, indexes.op_instr_count, instr_id - 1)
}

// Operand ids owned by instruction instr_id with kind in
// {instruction, aggregate_field, checked_edge_arg}, ascending operand-id
// order; at is 0-based.
fn mir_vindex_op_instr(indexes: MirVIndexes, instr_id: U64, at: U64) -> U64 {
    if instr_id == 0 || instr_id > __s0_buffer_len(U64, indexes.op_instr_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.op_instr_count, instr_id - 1)
    if at >= count { return 0 }
    return __s0_buffer_get(U64, indexes.op_instr_ids, __s0_buffer_get(U64, indexes.op_instr_start, instr_id - 1) + at)
}

fn mir_vindex_op_term_count(indexes: MirVIndexes, term_id: U64) -> U64 {
    if term_id == 0 || term_id > __s0_buffer_len(U64, indexes.op_term_count) { return 0 }
    return __s0_buffer_get(U64, indexes.op_term_count, term_id - 1)
}

// Operand ids owned by terminator term_id with kind in
// {terminator_arg, switch_case}, ascending operand-id order; at is 0-based.
fn mir_vindex_op_term(indexes: MirVIndexes, term_id: U64, at: U64) -> U64 {
    if term_id == 0 || term_id > __s0_buffer_len(U64, indexes.op_term_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.op_term_count, term_id - 1)
    if at >= count { return 0 }
    return __s0_buffer_get(U64, indexes.op_term_ids, __s0_buffer_get(U64, indexes.op_term_start, term_id - 1) + at)
}

fn mir_vindex_op_case_count(indexes: MirVIndexes, case_operand_id: U64) -> U64 {
    if case_operand_id == 0 || case_operand_id > __s0_buffer_len(U64, indexes.op_case_count) { return 0 }
    return __s0_buffer_get(U64, indexes.op_case_count, case_operand_id - 1)
}

// Operand ids of kind switch_case_arg owned by the switch-case operand
// case_operand_id, ascending operand-id order; at is 0-based.
fn mir_vindex_op_case(indexes: MirVIndexes, case_operand_id: U64, at: U64) -> U64 {
    if case_operand_id == 0 || case_operand_id > __s0_buffer_len(U64, indexes.op_case_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.op_case_count, case_operand_id - 1)
    if at >= count { return 0 }
    return __s0_buffer_get(U64, indexes.op_case_ids, __s0_buffer_get(U64, indexes.op_case_start, case_operand_id - 1) + at)
}

fn mir_vindex_type_part_count(indexes: MirVIndexes, owner_type_id: U64) -> U64 {
    if owner_type_id == 0 || owner_type_id > __s0_buffer_len(U64, indexes.tp_count) { return 0 }
    return __s0_buffer_get(U64, indexes.tp_count, owner_type_id - 1)
}

fn mir_vindex_type_field_count(indexes: MirVIndexes, owner_type_id: U64) -> U64 {
    if owner_type_id == 0 || owner_type_id > __s0_buffer_len(U64, indexes.tp_field_count) { return 0 }
    return __s0_buffer_get(U64, indexes.tp_field_count, owner_type_id - 1)
}

// MirTypePartRec ids owned by owner_type_id, ascending id order; at is 0-based.
fn mir_vindex_type_part(indexes: MirVIndexes, owner_type_id: U64, at: U64) -> U64 {
    if owner_type_id == 0 || owner_type_id > __s0_buffer_len(U64, indexes.tp_count) { return 0 }
    let count = __s0_buffer_get(U64, indexes.tp_count, owner_type_id - 1)
    if at >= count { return 0 }
    return __s0_buffer_get(U64, indexes.tp_ids, __s0_buffer_get(U64, indexes.tp_start, owner_type_id - 1) + at)
}

type MirVP4PointCfg {
    function: U64
    block_count: U64
    node_count: U64
    boundary_count: U64
    entry: U64
    boundary_offset: __s0_Buffer(U64)
    block_instr_count: __s0_Buffer(U64)
    succ: __s0_Buffer(U64)
    succ_start: __s0_Buffer(U64)
    succ_count: __s0_Buffer(U64)
    pred: __s0_Buffer(U64)
    pred_start: __s0_Buffer(U64)
    pred_count: __s0_Buffer(U64)
    case_edge: __s0_Buffer(U64)
}

type MirVP4CfgPlan {
    boundary_offset: __s0_Buffer(U64)
    block_instr_count: __s0_Buffer(U64)
    succ: __s0_Buffer(U64)
    succ_start: __s0_Buffer(U64)
    succ_count: __s0_Buffer(U64)
    pred: __s0_Buffer(U64)
    pred_start: __s0_Buffer(U64)
    pred_count: __s0_Buffer(U64)
    case_edge: __s0_Buffer(U64)
    edge_from: __s0_Buffer(U64)
    edge_to: __s0_Buffer(U64)
    scratch_edge_cnt: __s0_Buffer(U64)
    scratch_edge_base: __s0_Buffer(U64)
    scratch_edge_ids: __s0_Buffer(U64)
    scratch_edge_used: __s0_Buffer(U64)
}

type MirVP4CfgBuilt {
    plan: MirVP4CfgPlan
    cfg: MirVP4PointCfg
}

type MirVP4Dom {
    idom: __s0_Buffer(U64)
    rpo_index: __s0_Buffer(U64)
    dom_in: __s0_Buffer(U64)
    dom_out: __s0_Buffer(U64)
}

type MirVP4DomPlan {
    idom: __s0_Buffer(U64)
    rpo_index: __s0_Buffer(U64)
    dom_in: __s0_Buffer(U64)
    dom_out: __s0_Buffer(U64)
    scratch_seen: __s0_Buffer(U64)
    scratch_phase: __s0_Buffer(U64)
    scratch_stack: __s0_Buffer(U64)
    scratch_post: __s0_Buffer(U64)
    scratch_rpo: __s0_Buffer(U64)
    scratch_child_count: __s0_Buffer(U64)
    scratch_counts: __s0_Buffer(U64)
    scratch_child_start: __s0_Buffer(U64)
    scratch_filled: __s0_Buffer(U64)
    scratch_children: __s0_Buffer(U64)
    scratch_estack: __s0_Buffer(U64)
    scratch_edata: __s0_Buffer(U64)
}

type MirVP4DomBuilt {
    plan: MirVP4DomPlan
    dom: MirVP4Dom
}

// The point cfg and dominator analysis are rebuilt for every function, and
// without reuse every function's arrays stayed in the root domain, which is
// never reset, so the peak footprint held the sum over all functions. The
// plans own every buffer the two builders need; the builders grow them once
// to the largest function's bounds and rewrite the used range in place per
// function. The returned MirVP4PointCfg and MirVP4Dom alias the plan's
// buffers, and every consumer reads only slots covered by the current
// function's counts or guards on the counts first, so stale slots from a
// larger previous function are never observable. Growth (buffer_append)
// returns a new handle, so the builders return the updated plan alongside
// the analysis and the caller carries it to the next function.

fn mir_vp4_plan_grow(d: Domain, buf: __s0_Buffer(U64), need: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    var out = buf
    var grow = __s0_buffer_len(U64, out)
    while grow < need { out = try __s0_buffer_append(U64, d, out, 0)
        grow = grow + 1 }
    return Ok(out)
}

fn mir_vp4_u64_at(buf: __s0_Buffer(U64), index: U64) -> U64 {
    if index == 0 || index > __s0_buffer_len(U64, buf) { return 0 }
    return __s0_buffer_get(U64, buf, index - 1)
}

fn mir_vp4_cfg_build(plan: MirVP4CfgPlan, d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(MirVP4CfgBuilt, __s0_Error) {
    let block_count = mir_vindex_block_count(indexes, function)
    if block_count == 0 {
        return Ok(MirVP4CfgBuilt(plan: plan, cfg: MirVP4PointCfg(function: function, block_count: 0, node_count: 0, boundary_count: 0, entry: 0, boundary_offset: plan.boundary_offset, block_instr_count: plan.block_instr_count, succ: plan.succ, succ_start: plan.succ_start, succ_count: plan.succ_count, pred: plan.pred, pred_start: plan.pred_start, pred_count: plan.pred_count, case_edge: plan.case_edge)))
    }
    var boundary_offset = plan.boundary_offset
    var block_instr_count = plan.block_instr_count
    var succ = plan.succ
    var succ_start = plan.succ_start
    var succ_count = plan.succ_count
    var pred = plan.pred
    var pred_start = plan.pred_start
    var pred_count = plan.pred_count
    var case_edge = plan.case_edge
    var edge_from = plan.edge_from
    var edge_to = plan.edge_to
    var edge_cnt = plan.scratch_edge_cnt
    var edge_base = plan.scratch_edge_base
    var edge_ids = plan.scratch_edge_ids
    var edge_used = plan.scratch_edge_used
    // Capacity first: every buffer this function writes is grown to its
    // per-function need before the first store. boundary_offset,
    // block_instr_count, and case_edge hold block_count slots, the edge
    // bookkeeping arrays hold block_count + 1; the edge scan output bound is
    // derived below and grown before the scan.
    boundary_offset = try mir_vp4_plan_grow(d, boundary_offset, block_count)
    block_instr_count = try mir_vp4_plan_grow(d, block_instr_count, block_count)
    case_edge = try mir_vp4_plan_grow(d, case_edge, block_count)
    edge_cnt = try mir_vp4_plan_grow(d, edge_cnt, block_count + 1)
    edge_base = try mir_vp4_plan_grow(d, edge_base, block_count + 1)
    edge_used = try mir_vp4_plan_grow(d, edge_used, block_count + 1)
    var offset: U64 = 1
    var b: U64 = 1
    while b <= block_count {
        let count = mir_vindex_instr_count(indexes, function, b)
        __s0_buffer_set(U64, boundary_offset, b - 1, offset)
        __s0_buffer_set(U64, block_instr_count, b - 1, count)
        offset = offset + count + 1
        b = b + 1
    }
    let boundary_count = offset - 1
    // Upper bound on the edge count, from the same per-block data the edge
    // scan reads: every instruction can add a checked edge, and a terminator
    // adds at most one jump edge, two branch edges, or one edge per switch
    // operand. The scan never exceeds this bound, so the edge arrays are
    // grown once here and then written in place.
    var edge_bound: U64 = 0
    b = 1
    while b <= block_count {
        let count = __s0_buffer_get(U64, block_instr_count, b - 1)
        var term_edges: U64 = 0
        let term_id = mir_vindex_term(indexes, function, b)
        if term_id != 0 {
            let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            if t.kind == mir_term_jump() { term_edges = 1 }
            if t.kind == mir_term_branch() { term_edges = 2 }
            if t.kind == mir_term_switch() { term_edges = mir_vindex_op_term_count(indexes, term_id) }
        }
        edge_bound = edge_bound + count + term_edges
        b = b + 1
    }
    edge_from = try mir_vp4_plan_grow(d, edge_from, edge_bound)
    edge_to = try mir_vp4_plan_grow(d, edge_to, edge_bound)
    edge_ids = try mir_vp4_plan_grow(d, edge_ids, edge_bound)
    var z: U64 = 0
    while z < block_count { __s0_buffer_set(U64, case_edge, z, 0)
        z = z + 1 }
    z = 0
    while z <= block_count { __s0_buffer_set(U64, edge_cnt, z, 0)
        __s0_buffer_set(U64, edge_base, z, 0)
        __s0_buffer_set(U64, edge_used, z, 0)
        z = z + 1 }
    var edge_len: U64 = 0
    b = 1
    while b <= block_count {
        let count = __s0_buffer_get(U64, block_instr_count, b - 1)
        let base = __s0_buffer_get(U64, boundary_offset, b - 1)
        var p: U64 = 0
        while p < count {
            let ins_id = mir_vindex_instr(indexes, function, b, p)
            if ins_id != 0 {
                let ins = __s0_buffer_get(MirInstrRec, store.instructions, ins_id - 1)
                if mir_vop_checked(ins.op) && mir_vindex_block(indexes, function, ins.target) != 0 {
                    __s0_buffer_set(U64, edge_from, edge_len, base + p)
                    __s0_buffer_set(U64, edge_to, edge_len, ins.target)
                    edge_len = edge_len + 1
                }
            }
            p = p + 1
        }
        let term_id = mir_vindex_term(indexes, function, b)
        if term_id != 0 {
            let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            if t.kind == mir_term_jump() && mir_vindex_block(indexes, function, t.target) != 0 {
                __s0_buffer_set(U64, edge_from, edge_len, base + count)
                __s0_buffer_set(U64, edge_to, edge_len, t.target)
                edge_len = edge_len + 1
            }
            if t.kind == mir_term_branch() {
                if mir_vindex_block(indexes, function, t.then_block) != 0 {
                    __s0_buffer_set(U64, edge_from, edge_len, base + count)
                    __s0_buffer_set(U64, edge_to, edge_len, t.then_block)
                    edge_len = edge_len + 1
                }
                if mir_vindex_block(indexes, function, t.else_block) != 0 {
                    __s0_buffer_set(U64, edge_from, edge_len, base + count)
                    __s0_buffer_set(U64, edge_to, edge_len, t.else_block)
                    edge_len = edge_len + 1
                }
            }
            if t.kind == mir_term_switch() {
                let first_case = edge_len
                // Switch cases are the switch_case-kind operands of this
                // terminator in ascending operand-id order, which on a
                // validated store is their ordinal order.
                let ccount = mir_vindex_op_term_count(indexes, term_id)
                var at: U64 = 0
                while at < ccount {
                    let case_id = mir_vindex_op_term(indexes, term_id, at)
                    let c = __s0_buffer_get(MirOperandRec, store.operands, case_id - 1)
                    if c.kind == mir_operand_switch_case() && mir_vindex_block(indexes, function, c.target) != 0 {
                        __s0_buffer_set(U64, edge_from, edge_len, base + count)
                        __s0_buffer_set(U64, edge_to, edge_len, c.target)
                        edge_len = edge_len + 1
                    }
                    at = at + 1
                }
                if edge_len > first_case {
                    __s0_buffer_set(U64, case_edge, b - 1, first_case + 1)
                }
            }
        }
        b = b + 1
    }
    let edge_count = edge_len
    let node_count = boundary_count + edge_count
    if node_count == 0 {
        let empty_plan = MirVP4CfgPlan(boundary_offset: boundary_offset, block_instr_count: block_instr_count, succ: succ, succ_start: succ_start, succ_count: succ_count, pred: pred, pred_start: pred_start, pred_count: pred_count, case_edge: case_edge, edge_from: edge_from, edge_to: edge_to, scratch_edge_cnt: edge_cnt, scratch_edge_base: edge_base, scratch_edge_ids: edge_ids, scratch_edge_used: edge_used)
        return Ok(MirVP4CfgBuilt(plan: empty_plan, cfg: MirVP4PointCfg(function: function, block_count: block_count, node_count: 0, boundary_count: boundary_count, entry: 0, boundary_offset: boundary_offset, block_instr_count: block_instr_count, succ: succ, succ_start: succ_start, succ_count: succ_count, pred: pred, pred_start: pred_start, pred_count: pred_count, case_edge: case_edge)))
    }
    succ = try mir_vp4_plan_grow(d, succ, boundary_count + edge_count + edge_count)
    succ_start = try mir_vp4_plan_grow(d, succ_start, node_count)
    succ_count = try mir_vp4_plan_grow(d, succ_count, node_count)
    pred = try mir_vp4_plan_grow(d, pred, boundary_count + edge_count + edge_count)
    pred_start = try mir_vp4_plan_grow(d, pred_start, node_count)
    pred_count = try mir_vp4_plan_grow(d, pred_count, node_count)
    // Boundary nodes ascending: a linear successor n + 1 unless n is the
    // terminator position of its block, plus the edge nodes whose edge_from
    // equals n. edge_from is non-decreasing, so a cursor replaces the per-node
    // full scans.
    var succ_len: U64 = 0
    var bb: U64 = 1
    var e: U64 = 0
    var n: U64 = 1
    while n <= boundary_count {
        let start = succ_len
        while bb < block_count && n > __s0_buffer_get(U64, boundary_offset, bb - 1) + __s0_buffer_get(U64, block_instr_count, bb - 1) { bb = bb + 1 }
        if n != __s0_buffer_get(U64, boundary_offset, bb - 1) + __s0_buffer_get(U64, block_instr_count, bb - 1) {
            __s0_buffer_set(U64, succ, succ_len, n + 1)
            succ_len = succ_len + 1
        }
        while e < edge_count && __s0_buffer_get(U64, edge_from, e) < n { e = e + 1 }
        while e < edge_count && __s0_buffer_get(U64, edge_from, e) == n {
            __s0_buffer_set(U64, succ, succ_len, boundary_count + 1 + e)
            succ_len = succ_len + 1
            e = e + 1
        }
        __s0_buffer_set(U64, succ_start, n - 1, start)
        __s0_buffer_set(U64, succ_count, n - 1, succ_len - start)
        n = n + 1
    }
    n = 1
    while n <= edge_count {
        let start = succ_len
        let target = __s0_buffer_get(U64, edge_to, n - 1)
        __s0_buffer_set(U64, succ, succ_len, __s0_buffer_get(U64, boundary_offset, target - 1))
        succ_len = succ_len + 1
        __s0_buffer_set(U64, succ_start, boundary_count + n - 1, start)
        __s0_buffer_set(U64, succ_count, boundary_count + n - 1, 1)
        n = n + 1
    }
    // Pred lists: a non-entry boundary node n > 1 has the single linear pred
    // n - 1; a block-entry boundary node has exactly the edge nodes whose
    // edge_to is that block (built by counting-sorting edges by target); an
    // edge node boundary_count + e has the single pred edge_from[e]. This is
    // the exact inverse of the succ lists above, with preds in ascending
    // source order like the old per-node scan.
    var pred_len: U64 = 0
    var e2: U64 = 0
    while e2 < edge_count {
        let target = __s0_buffer_get(U64, edge_to, e2)
        __s0_buffer_set(U64, edge_cnt, target, __s0_buffer_get(U64, edge_cnt, target) + 1)
        e2 = e2 + 1
    }
    var blk: U64 = 1
    while blk <= block_count { __s0_buffer_set(U64, edge_base, blk, __s0_buffer_get(U64, edge_base, blk - 1) + __s0_buffer_get(U64, edge_cnt, blk - 1))
        blk = blk + 1 }
    e2 = 0
    while e2 < edge_count { __s0_buffer_set(U64, edge_ids, e2, 0)
        e2 = e2 + 1 }
    e2 = 0
    while e2 < edge_count {
        let target = __s0_buffer_get(U64, edge_to, e2)
        let pos = __s0_buffer_get(U64, edge_base, target) + __s0_buffer_get(U64, edge_used, target)
        __s0_buffer_set(U64, edge_ids, pos, e2 + 1)
        __s0_buffer_set(U64, edge_used, target, __s0_buffer_get(U64, edge_used, target) + 1)
        e2 = e2 + 1
    }
    bb = 1
    n = 1
    while n <= boundary_count {
        let start = pred_len
        while bb < block_count && n > __s0_buffer_get(U64, boundary_offset, bb - 1) + __s0_buffer_get(U64, block_instr_count, bb - 1) { bb = bb + 1 }
        let offb = __s0_buffer_get(U64, boundary_offset, bb - 1)
        if n > 1 && n != offb {
            __s0_buffer_set(U64, pred, pred_len, n - 1)
            pred_len = pred_len + 1
        }
        if n == offb {
            var k: U64 = 0
            while k < __s0_buffer_get(U64, edge_cnt, bb) {
                let eid = __s0_buffer_get(U64, edge_ids, __s0_buffer_get(U64, edge_base, bb) + k)
                __s0_buffer_set(U64, pred, pred_len, boundary_count + eid)
                pred_len = pred_len + 1
                k = k + 1
            }
        }
        __s0_buffer_set(U64, pred_start, n - 1, start)
        __s0_buffer_set(U64, pred_count, n - 1, pred_len - start)
        n = n + 1
    }
    e2 = 0
    while e2 < edge_count {
        let start = pred_len
        __s0_buffer_set(U64, pred, pred_len, __s0_buffer_get(U64, edge_from, e2))
        pred_len = pred_len + 1
        __s0_buffer_set(U64, pred_start, boundary_count + e2, start)
        __s0_buffer_set(U64, pred_count, boundary_count + e2, 1)
        e2 = e2 + 1
    }
    let out_plan = MirVP4CfgPlan(boundary_offset: boundary_offset, block_instr_count: block_instr_count, succ: succ, succ_start: succ_start, succ_count: succ_count, pred: pred, pred_start: pred_start, pred_count: pred_count, case_edge: case_edge, edge_from: edge_from, edge_to: edge_to, scratch_edge_cnt: edge_cnt, scratch_edge_base: edge_base, scratch_edge_ids: edge_ids, scratch_edge_used: edge_used)
    return Ok(MirVP4CfgBuilt(plan: out_plan, cfg: MirVP4PointCfg(function: function, block_count: block_count, node_count: node_count, boundary_count: boundary_count, entry: 1, boundary_offset: boundary_offset, block_instr_count: block_instr_count, succ: succ, succ_start: succ_start, succ_count: succ_count, pred: pred, pred_start: pred_start, pred_count: pred_count, case_edge: case_edge)))
}

fn mir_vp4_dom_build(plan: MirVP4DomPlan, d: Domain, cfg: MirVP4PointCfg) -> Result(MirVP4DomBuilt, __s0_Error) {
    let n = cfg.node_count
    let entry = cfg.entry
    if n == 0 || entry == 0 || entry > n {
        return Ok(MirVP4DomBuilt(plan: plan, dom: MirVP4Dom(idom: plan.idom, rpo_index: plan.rpo_index, dom_in: plan.dom_in, dom_out: plan.dom_out)))
    }
    var idom = plan.idom
    var rpo_index = plan.rpo_index
    var dom_in = plan.dom_in
    var dom_out = plan.dom_out
    var seen = plan.scratch_seen
    var phase = plan.scratch_phase
    var stack = plan.scratch_stack
    var post = plan.scratch_post
    var rpo = plan.scratch_rpo
    var child_count = plan.scratch_child_count
    var counts = plan.scratch_counts
    var child_start = plan.scratch_child_start
    var filled = plan.scratch_filled
    var children = plan.scratch_children
    var estack = plan.scratch_estack
    var edata = plan.scratch_edata
    idom = try mir_vp4_plan_grow(d, idom, n + 1)
    rpo_index = try mir_vp4_plan_grow(d, rpo_index, n + 1)
    dom_in = try mir_vp4_plan_grow(d, dom_in, n + 1)
    dom_out = try mir_vp4_plan_grow(d, dom_out, n + 1)
    seen = try mir_vp4_plan_grow(d, seen, n + 1)
    phase = try mir_vp4_plan_grow(d, phase, n + 1)
    stack = try mir_vp4_plan_grow(d, stack, n + 1)
    post = try mir_vp4_plan_grow(d, post, n + 1)
    rpo = try mir_vp4_plan_grow(d, rpo, n + 1)
    child_count = try mir_vp4_plan_grow(d, child_count, n + 1)
    counts = try mir_vp4_plan_grow(d, counts, n + 1)
    child_start = try mir_vp4_plan_grow(d, child_start, n + 1)
    filled = try mir_vp4_plan_grow(d, filled, n + 1)
    children = try mir_vp4_plan_grow(d, children, n + 1)
    estack = try mir_vp4_plan_grow(d, estack, n + 1)
    edata = try mir_vp4_plan_grow(d, edata, n + 1)
    // Iterative DFS postorder over the CFG. All scratch lives in the plan's
    // reusable buffers: the stack is a buffer written and read by explicit
    // slot index with a logical top, so pops leave only stale slots that the
    // walk never reads, and the visited probe stays a direct O(1) slot check.
    var z: U64 = 0
    while z <= n {
        __s0_buffer_set(U64, seen, z, 0)
        __s0_buffer_set(U64, phase, z, 0)
        __s0_buffer_set(U64, stack, z, 0)
        z = z + 1
    }
    __s0_buffer_set(U64, stack, 0, entry)
    __s0_buffer_set(U64, phase, 0, 0)
    __s0_buffer_set(U64, seen, entry - 1, 1)
    var top: U64 = 1
    var plen: U64 = 0
    while top != 0 {
        let v = __s0_buffer_get(U64, stack, top - 1)
        if __s0_buffer_get(U64, phase, top - 1) == 0 {
            __s0_buffer_set(U64, phase, top - 1, 1)
            let base = mir_vp4_u64_at(cfg.succ_start, v)
            let count = mir_vp4_u64_at(cfg.succ_count, v)
            var k: U64 = 0
            while k < count {
                let s = __s0_buffer_get(U64, cfg.succ, base + k)
                if s != 0 && __s0_buffer_get(U64, seen, s - 1) == 0 {
                    __s0_buffer_set(U64, seen, s - 1, 1)
                    __s0_buffer_set(U64, stack, top, s)
                    __s0_buffer_set(U64, phase, top, 0)
                    top = top + 1
                }
                k = k + 1
            }
        } else {
            __s0_buffer_set(U64, post, plen, v)
            plen = plen + 1
            top = top - 1
        }
    }
    // rpo is the reverse postorder; rpo_index maps a node to its 1-based rpo
    // position. All stores below are constants or arithmetic results.
    z = 0
    while z <= n { __s0_buffer_set(U64, rpo_index, z, 0)
        z = z + 1 }
    var i: U64 = 0
    while i < plen {
        __s0_buffer_set(U64, rpo, i, __s0_buffer_get(U64, post, plen - 1 - i))
        i = i + 1
    }
    i = 0
    while i < plen {
        __s0_buffer_set(U64, rpo_index, __s0_buffer_get(U64, rpo, i) - 1, i + 1)
        i = i + 1
    }
    // idom fixpoint: identical iteration order and semantics to the original
    // walk, with O(1) slot reads and writes through the shared plan buffer.
    z = 0
    while z <= n { __s0_buffer_set(U64, idom, z, 0)
        z = z + 1 }
    __s0_buffer_set(U64, idom, entry - 1, entry)
    var changed = true
    while changed {
        changed = false
        i = 1
        while i < plen {
            let b = __s0_buffer_get(U64, rpo, i)
            var new_idom: U64 = 0
            let base = mir_vp4_u64_at(cfg.pred_start, b)
            let count = mir_vp4_u64_at(cfg.pred_count, b)
            var k: U64 = 0
            while k < count {
                let p = __s0_buffer_get(U64, cfg.pred, base + k)
                if __s0_buffer_get(U64, idom, p - 1) != 0 {
                    if new_idom == 0 {
                        new_idom = p
                    } else {
                        // CHK intersect of p and new_idom, inlined because the
                        // plan scratch cannot cross a function boundary.
                        var x = p
                        var y = new_idom
                        var done = false
                        while !done && x != y {
                            if x == 0 || y == 0 {
                                x = 0
                                done = true
                            } else {
                                let xi = __s0_buffer_get(U64, rpo_index, x - 1)
                                let yi = __s0_buffer_get(U64, rpo_index, y - 1)
                                if xi == 0 || yi == 0 {
                                    x = 0
                                    done = true
                                } else {
                                    if xi > yi {
                                        x = __s0_buffer_get(U64, idom, x - 1)
                                    } else {
                                        y = __s0_buffer_get(U64, idom, y - 1)
                                    }
                                }
                            }
                        }
                        new_idom = x
                    }
                }
                k = k + 1
            }
            if new_idom != 0 && __s0_buffer_get(U64, idom, b - 1) != new_idom {
                __s0_buffer_set(U64, idom, b - 1, new_idom)
                changed = true
            }
            i = i + 1
        }
    }
    // Children lists from idom, in the same 0-based layout as before.
    // child_count is written in node order because its values are read back
    // through the shared plan buffer during the Euler tour.
    z = 0
    while z <= n {
        __s0_buffer_set(U64, counts, z, 0)
        __s0_buffer_set(U64, child_start, z, 0)
        __s0_buffer_set(U64, filled, z, 0)
        z = z + 1
    }
    var v: U64 = 1
    while v <= n {
        let p = __s0_buffer_get(U64, idom, v - 1)
        if p != 0 && p != v { __s0_buffer_set(U64, counts, p - 1, __s0_buffer_get(U64, counts, p - 1) + 1) }
        v = v + 1
    }
    var start: U64 = 0
    v = 1
    while v <= n {
        __s0_buffer_set(U64, child_start, v - 1, start)
        let count = __s0_buffer_get(U64, counts, v - 1)
        __s0_buffer_set(U64, child_count, v - 1, count)
        start = start + count
        v = v + 1
    }
    z = 0
    while z < start { __s0_buffer_set(U64, children, z, 0)
        z = z + 1 }
    v = 1
    while v <= n {
        let p = __s0_buffer_get(U64, idom, v - 1)
        if p != 0 && p != v {
            let used = __s0_buffer_get(U64, filled, p - 1)
            __s0_buffer_set(U64, children, __s0_buffer_get(U64, child_start, p - 1) + used, v)
            __s0_buffer_set(U64, filled, p - 1, used + 1)
        }
        v = v + 1
    }
    // Euler tour over the idom tree: dom_in is the preorder stamp, dom_out
    // the stamp at subtree exit. Same traversal order and stamps as the
    // original walk; children are pushed onto the plan's estack buffer and
    // read back through the same shared buffer.
    z = 0
    while z <= n {
        __s0_buffer_set(U64, dom_in, z, 0)
        __s0_buffer_set(U64, dom_out, z, 0)
        __s0_buffer_set(U64, estack, z, 0)
        __s0_buffer_set(U64, edata, z, 0)
        z = z + 1
    }
    __s0_buffer_set(U64, estack, 0, entry)
    __s0_buffer_set(U64, edata, 0, 0)
    var stamp: U64 = 0
    var etop: U64 = 1
    while etop != 0 {
        let v2 = __s0_buffer_get(U64, estack, etop - 1)
        let data = __s0_buffer_get(U64, edata, etop - 1)
        if data == 0 {
            stamp = stamp + 1
            __s0_buffer_set(U64, edata, etop - 1, stamp)
            __s0_buffer_set(U64, dom_in, v2 - 1, stamp)
            let base = __s0_buffer_get(U64, child_start, v2 - 1)
            let count = __s0_buffer_get(U64, child_count, v2 - 1)
            var k: U64 = 0
            while k < count {
                let c = __s0_buffer_get(U64, children, base + k)
                if c != 0 {
                    __s0_buffer_set(U64, estack, etop, c)
                    __s0_buffer_set(U64, edata, etop, 0)
                    etop = etop + 1
                }
                k = k + 1
            }
        } else {
            __s0_buffer_set(U64, dom_out, v2 - 1, stamp)
            etop = etop - 1
        }
    }
    let out_plan = MirVP4DomPlan(idom: idom, rpo_index: rpo_index, dom_in: dom_in, dom_out: dom_out, scratch_seen: seen, scratch_phase: phase, scratch_stack: stack, scratch_post: post, scratch_rpo: rpo, scratch_child_count: child_count, scratch_counts: counts, scratch_child_start: child_start, scratch_filled: filled, scratch_children: children, scratch_estack: estack, scratch_edata: edata)
    return Ok(MirVP4DomBuilt(plan: out_plan, dom: MirVP4Dom(idom: idom, rpo_index: rpo_index, dom_in: dom_in, dom_out: dom_out)))
}

fn mir_vp4_boundary_node(cfg: MirVP4PointCfg, block: U64, position: U64) -> U64 {
    if block == 0 || block > cfg.block_count { return 0 }
    let count = __s0_buffer_get(U64, cfg.block_instr_count, block - 1)
    if position > count { return 0 }
    return __s0_buffer_get(U64, cfg.boundary_offset, block - 1) + position
}

fn mir_vp4_case_edge_node(cfg: MirVP4PointCfg, block: U64, case_ordinal: U64) -> U64 {
    if block == 0 || block > cfg.block_count { return 0 }
    let first = __s0_buffer_get(U64, cfg.case_edge, block - 1)
    if first == 0 { return 0 }
    let node = cfg.boundary_count + first + case_ordinal
    if node == 0 || node > cfg.node_count { return 0 }
    return node
}

fn mir_vp4_dominates(cfg: MirVP4PointCfg, dom: MirVP4Dom, use: U64, def: U64) -> Bool {
    if use == def { return true }
    if use == 0 || def == 0 || use > cfg.node_count || def > cfg.node_count { return false }
    let use_in = mir_vp4_u64_at(dom.dom_in, use)
    let def_in = mir_vp4_u64_at(dom.dom_in, def)
    if use_in == 0 || def_in == 0 { return false }
    return def_in <= use_in && mir_vp4_u64_at(dom.dom_out, use) <= mir_vp4_u64_at(dom.dom_out, def)
}

fn mir_vp4_avail_dominates(cfg: MirVP4PointCfg, dom: MirVP4Dom, def_kind: U64, def_block: U64, def_item: U64, use_block: U64, use_position: U64) -> Bool {
    var def_node: U64 = 0
    if def_kind == mir_value_def_block_param() { def_node = mir_vp4_boundary_node(cfg, def_block, 0) }
    if def_kind == mir_value_def_instruction() { def_node = mir_vp4_boundary_node(cfg, def_block, def_item) }
    if def_kind == mir_value_def_switch_case() { def_node = mir_vp4_case_edge_node(cfg, def_block, def_item - 1) }
    if def_node == 0 { return false }
    let use_node = mir_vp4_boundary_node(cfg, use_block, use_position)
    if use_node == 0 { return false }
    return mir_vp4_dominates(cfg, dom, use_node, def_node)
}

// --- type-graph memo tables ---
//
// mir_v6_type_contains and mir_vtype_has_forbidden used to allocate a fresh
// visited array and work list per query; on the self-compile corpus they ran
// hundreds of thousands of times and dominated the bootstrap's peak memory.
// The answers are pure functions of the type graph, which mir_build finishes
// building before verification starts and which verification never extends or
// patches, so each (type id, kind) answer and each phase-2 verdict is computed
// once and recorded in dense arrays indexed by the stable numeric type id.
// Every recorded value comes from running the original walk, so results -
// including which forbidden kind a walk reports first - are unchanged; only
// repeat walks are avoided. There is no ordering-sensitive structure here:
// array indexes are type ids and kind numbers.
//
// The walk marks visited ids in memo_seen by generation stamping (the entry
// equals the current generation while the walk is live), so no walk allocates
// its own visited array, and a fresh work list is the only per-query scratch.
// memo_gen lives in a one-entry buffer because __s0_buffer_set writes through
// the shared allocation, while a scalar field would be private to the copy.

fn mir_vmemo_kind_columns() -> U64 { return 22 }

fn mir_vmemo_contains(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64, wanted: U64) -> Result(Bool, __s0_Error) {
    let count = __s0_buffer_len(MirTypeRec, store.types)
    if root < 1 || root > count || wanted >= mir_vmemo_kind_columns() { return mir_vmemo_contains_walk(d, store, indexes, root, wanted) }
    let cell = root * mir_vmemo_kind_columns() + wanted
    if __s0_buffer_get(U64, indexes.contains_flag, cell) != 0 { return Ok(__s0_buffer_get(U64, indexes.contains_ans, cell) != 0) }
    let gen = __s0_buffer_get(U64, indexes.memo_gen, 0) + 1
    __s0_buffer_set(U64, indexes.memo_gen, 0, gen)
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var found = false
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        at = at + 1
        if id >= 1 && id <= count && __s0_buffer_get(U64, indexes.memo_seen, id) != gen {
            __s0_buffer_set(U64, indexes.memo_seen, id, gen)
            if mir_vtype_kind(store, id) == wanted { found = true }
            work = try mir_vappend_type_children(d, store, indexes, work, id)
        }
    }
    __s0_buffer_set(U64, indexes.contains_flag, cell, 1)
    if found { __s0_buffer_set(U64, indexes.contains_ans, cell, 1) }
    return Ok(found)
}

// Direct walk for queries the memo does not cover: out-of-range roots and
// kinds beyond the fixed column count. Same traversal and visited discipline
// as the memo fill, generation-stamped so cyclic type graphs still terminate.
fn mir_vmemo_contains_walk(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64, wanted: U64) -> Result(Bool, __s0_Error) {
    let count = __s0_buffer_len(MirTypeRec, store.types)
    let gen = __s0_buffer_get(U64, indexes.memo_gen, 0) + 1
    __s0_buffer_set(U64, indexes.memo_gen, 0, gen)
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var found = false
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        at = at + 1
        if id >= 1 && id <= count && __s0_buffer_get(U64, indexes.memo_seen, id) != gen {
            __s0_buffer_set(U64, indexes.memo_seen, id, gen)
            if mir_vtype_kind(store, id) == wanted { found = true }
            work = try mir_vappend_type_children(d, store, indexes, work, id)
        }
    }
    return Ok(found)
}

// Per-root phase-2 verdict memo. The verdict encodes which forbidden kind the
// walk reports first (kind + 1, zero when clean), so the recorded value is
// exactly what the unmemoized walk returned for this root. Storage: zero
// means not computed, one means clean, and k + 2 means the walk reported k.
fn mir_vmemo_forbidden(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64) -> Result(U64, __s0_Error) {
    let count = __s0_buffer_len(MirTypeRec, store.types)
    if root < 1 || root > count { return Ok(0) }
    let recorded = __s0_buffer_get(U64, indexes.forbidden_val, root)
    if recorded != 0 {
        if recorded == 1 { return Ok(0) }
        return Ok(recorded - 1)
    }
    let gen = __s0_buffer_get(U64, indexes.memo_gen, 0) + 1
    __s0_buffer_set(U64, indexes.memo_gen, 0, gen)
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var found: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) && found == 0 {
        let id = __s0_buffer_get(U64, work, at)
        at = at + 1
        if id >= 1 && id <= count && __s0_buffer_get(U64, indexes.memo_seen, id) != gen {
            __s0_buffer_set(U64, indexes.memo_seen, id, gen)
            let kind = mir_vtype_kind(store, id)
            if kind == mir_type_kind_table_view() || kind == mir_type_kind_table_mut_view() || kind == mir_type_kind_cleanup_scope() || kind == mir_type_kind_cleanup_id() { found = kind + 1 }
            else { work = try mir_vappend_type_children(d, store, indexes, work, id) }
        }
    }
    if found == 0 {
        __s0_buffer_set(U64, indexes.forbidden_val, root, 1)
        return Ok(0)
    }
    __s0_buffer_set(U64, indexes.forbidden_val, root, found + 1)
    return Ok(found)
}

