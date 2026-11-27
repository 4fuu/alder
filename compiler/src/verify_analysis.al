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
    let kind_count = mir_type_kind_c_callback_owner() + 1
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
    let kind_count = mir_type_kind_c_callback_owner() + 1
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


// ---------------------------------------------------------------------------
// Step frames. Step frames are ordinary MIR 6 aggregates with reserved names;
// these helpers are the single recognition point for the acceptance rules in
// docs/mir.md "Frame access and verification". The scan validates declarations
// for Phase 2; later phases reuse it for access, state, cleanup, and backend
// checks. The layout mirrors mir/verify/frame.go and frame_state.go.

fn mir_vframe_reserved() -> __s0_String { return "__alder_step." }
fn mir_vframe_status_name() -> __s0_String { return "__alder_step.status" }
fn mir_vframe_run_prefix() -> __s0_String { return "__alder_step.run." }
fn mir_vframe_type_prefix() -> __s0_String { return "__alder_step.frame." }
fn mir_vframe_state_prefix() -> __s0_String { return "__alder_step.state." }

fn mir_vframe_field_state() -> U64 { return 1 }
fn mir_vframe_field_param() -> U64 { return 2 }
fn mir_vframe_field_owner() -> U64 { return 3 }
fn mir_vframe_field_callee() -> U64 { return 4 }
fn mir_vframe_field_callee_owner() -> U64 { return 5 }
fn mir_vframe_field_domain() -> U64 { return 6 }
fn mir_vframe_field_local() -> U64 { return 7 }
fn mir_vframe_field_temp() -> U64 { return 8 }
fn mir_vframe_field_cleanup() -> U64 { return 9 }
fn mir_vframe_field_scope() -> U64 { return 10 }
fn mir_vframe_field_out() -> U64 { return 11 }

fn mir_vframe_prefix(store: MirStore, start: U64, end: U64, prefix: __s0_String) -> Bool {
    if !mir_vrange_valid(start, end, __s0_buffer_len(U8, store.names)) { return false }
    if end - start < len(prefix) { return false }
    var at: U64 = 0
    while at < len(prefix) { if __s0_buffer_get(U8, store.names, start + at) != prefix[at] { return false }
        at = at + 1 }
    return true
}

fn mir_vframe_number(store: MirStore, start: U64, end: U64) -> U64 {
    if !mir_vrange_valid(start, end, __s0_buffer_len(U8, store.names)) || start >= end { return 0 }
    var value: U64 = 0
    var at = start
    while at < end { let c = __s0_buffer_get(U8, store.names, at)
        if c < 48 || c > 57 { return 0 }
        value = value * 10 + (mir_vindex_hash_byte(c) - 48)
        at = at + 1 }
    return value + 1
}

fn mir_vframe_indexed(store: MirStore, start: U64, end: U64, prefix: __s0_String) -> U64 {
    if !mir_vframe_prefix(store, start, end, prefix) || end - start == len(prefix) { return 0 }
    return mir_vframe_number(store, start + len(prefix), end)
}

fn mir_vframe_type_kind_is(store: MirStore, type_id: U64, kind: U64) -> Bool {
    return mir_vtype_exists(store, type_id) && mir_vtype_kind(store, type_id) == kind
}

type MirVFrameField {
    ordinal: U64
    type_id: U64
    kind: U64
    index: U64
}
type MirVFrameRec {
    type_id: U64
    instance_start: U64
    instance_end: U64
    state_type: U64
    step: U64
    field_start: U64
    field_count: U64
}
type MirVFrameStep {
    function: U64
    frame_type: U64
    state_type: U64
    frame_param: U64
    owner_param: U64
}
type MirVFrameState {
    type_id: U64
    instance_start: U64
    instance_end: U64
    variant_count: U64
}
type MirVFrameScan {
    status_type: U64
    status_found: Bool
    reserved: Bool
    frames: __s0_Buffer(MirVFrameRec)
    steps: __s0_Buffer(MirVFrameStep)
    states: __s0_Buffer(MirVFrameState)
    fields: __s0_Buffer(MirVFrameField)
}
type MirVFrameScanResult {
    scan: MirVFrameScan
    diagnostics: __s0_Buffer(MirVerifyDiagRec)
}

fn mir_vframe_diag(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, block: U64, instruction: U64, type_id: U64, declaration: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    return mir_vadd(d, out, mir_vdiag(mir_verify_phase_types(), kind, function, block, instruction, 0, 0, type_id, declaration, 0, 0, 0))
}

fn mir_vframe_frame_index(scan: MirVFrameScan, type_id: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirVFrameRec, scan.frames) {
        if __s0_buffer_get(MirVFrameRec, scan.frames, at).type_id == type_id { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_state_index(scan: MirVFrameScan, type_id: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirVFrameState, scan.states) {
        if __s0_buffer_get(MirVFrameState, scan.states, at).type_id == type_id { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_step_for(scan: MirVFrameScan, function: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirVFrameStep, scan.steps) {
        if __s0_buffer_get(MirVFrameStep, scan.steps, at).function == function { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_field_index(scan: MirVFrameScan, frame_index: U64, store: MirStore, start: U64, end: U64) -> U64 {
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    var at: U64 = 0
    while at < frame.field_count {
        let field = __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + at)
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, field.ordinal - 1)
        if mir_vname_equal(store, part.name_start, part.name_end, start, end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_field_kind(scan: MirVFrameScan, frame_index: U64, store: MirStore, start: U64, end: U64) -> U64 {
    let f = mir_vframe_field_index(scan, frame_index, store, start, end)
    if f == 0 { return 0 }
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    return __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + f - 1).kind
}

fn mir_vframe_field_by_word(scan: MirVFrameScan, frame_index: U64, store: MirStore, word: __s0_String) -> U64 {
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    var at: U64 = 0
    while at < frame.field_count {
        let field = __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + at)
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, field.ordinal - 1)
        if mir_vname_word(store, part.name_start, part.name_end, word) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_is_frame(scan: MirVFrameScan, type_id: U64) -> Bool { return mir_vframe_frame_index(scan, type_id) != 0 }

fn mir_vframe_is_frame_view(scan: MirVFrameScan, store: MirStore, type_id: U64) -> Bool {
    if !mir_vframe_type_kind_is(store, type_id, mir_type_kind_safe_mut()) { return false }
    return mir_vframe_is_frame(scan, __s0_buffer_get(MirTypeRec, store.types, type_id - 1).elem)
}

fn mir_vframe_type_contains(d: Domain, scan: MirVFrameScan, store: MirStore, indexes: MirVIndexes, root: U64) -> Result(Bool, __s0_Error) {
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        at = at + 1
        if id >= 1 && id <= __s0_buffer_len(MirTypeRec, store.types) {
            if mir_vframe_is_frame(scan, id) { return Ok(true) }
            let before = __s0_buffer_len(U64, work)
            work = try mir_vappend_type_children(d, store, indexes, work, id)
            // Deduplicate by scanning the prefix; frame modules are small.
            var added = before
            while added < __s0_buffer_len(U64, work) {
                let child = __s0_buffer_get(U64, work, added)
                var prior: U64 = 0
                var seen = false
                while prior < added { if __s0_buffer_get(U64, work, prior) == child { seen = true }
                    prior = prior + 1 }
                if seen { __s0_buffer_set(U64, work, added, 0) }
                added = added + 1
            }
        }
    }
    return Ok(false)
}

fn mir_vframe_variant(store: MirStore, indexes: MirVIndexes, type_id: U64, ordinal: U64) -> U64 {
    let total = mir_vindex_type_part_count(indexes, type_id)
    var at: U64 = 0
    while at < total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if part.kind == mir_type_part_variant() && part.ordinal == ordinal { return mir_vindex_type_part(indexes, type_id, at) }
        at = at + 1
    }
    return 0
}

fn mir_vframe_field_part(store: MirStore, indexes: MirVIndexes, type_id: U64, ordinal: U64) -> U64 {
    let total = mir_vindex_type_part_count(indexes, type_id)
    var at: U64 = 0
    while at < total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if part.kind == mir_type_part_field() && part.ordinal == ordinal { return mir_vindex_type_part(indexes, type_id, at) }
        at = at + 1
    }
    return 0
}

fn mir_vframe_state_variant_count(store: MirStore, indexes: MirVIndexes, type_id: U64) -> U64 {
    let total = mir_vindex_type_part_count(indexes, type_id)
    var count: U64 = 0
    var at: U64 = 0
    while at < total {
        if __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1).kind == mir_type_part_variant() { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_vframe_param_value(store: MirStore, indexes: MirVIndexes, function: U64, ordinal: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if p.block == 0 && p.kind == mir_param_function() && p.ordinal == ordinal { return p.value }
        at = at + 1
    }
    return 0
}

fn mir_vtype_contains_frame_name(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64) -> Result(Bool, __s0_Error) {
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        at = at + 1
        if id >= 1 && id <= __s0_buffer_len(MirTypeRec, store.types) {
            let t = __s0_buffer_get(MirTypeRec, store.types, id - 1)
            if t.kind == mir_type_kind_aggregate() && mir_vframe_prefix(store, t.name_start, t.name_end, mir_vframe_type_prefix()) { return Ok(true) }
            let before = __s0_buffer_len(U64, work)
            work = try mir_vappend_type_children(d, store, indexes, work, id)
            var added = before
            while added < __s0_buffer_len(U64, work) {
                let child = __s0_buffer_get(U64, work, added)
                var prior: U64 = 0
                var seen = false
                while prior < added { if __s0_buffer_get(U64, work, prior) == child { seen = true }
                    prior = prior + 1 }
                if seen { __s0_buffer_set(U64, work, added, 0) }
                added = added + 1
            }
        }
    }
    return Ok(false)
}

fn mir_vframe_scan(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirVFrameScanResult, __s0_Error) {
    var frames = try __s0_buffer_new(MirVFrameRec, d)
    var steps = try __s0_buffer_new(MirVFrameStep, d)
    var states = try __s0_buffer_new(MirVFrameState, d)
    var fields = try __s0_buffer_new(MirVFrameField, d)
    var out = try __s0_buffer_new(MirVerifyDiagRec, d)
    var reserved = false
    var status_type: U64 = 0
    var status_found = false
    var type_total = __s0_buffer_len(MirTypeRec, store.types)
    var tid: U64 = 1
    while tid <= type_total {
        let t = __s0_buffer_get(MirTypeRec, store.types, tid - 1)
        if mir_vframe_prefix(store, t.name_start, t.name_end, mir_vframe_reserved()) {
            reserved = true
            if mir_vname_word(store, t.name_start, t.name_end, mir_vframe_status_name()) {
                if t.kind == mir_type_kind_enum() { status_type = tid
                    status_found = true
                } else { out = try mir_vframe_diag(d, out, mir_vdiag_frame_status_shape(), 0, 0, 0, tid, tid) }
            } else {
                if mir_vframe_prefix(store, t.name_start, t.name_end, mir_vframe_type_prefix()) {
                    if t.kind == mir_type_kind_aggregate() {
                        frames = try __s0_buffer_append(MirVFrameRec, d, frames, MirVFrameRec(type_id: tid, instance_start: t.name_start + len(mir_vframe_type_prefix()), instance_end: t.name_end, state_type: 0, step: 0, field_start: 0, field_count: 0))
                    } else { out = try mir_vframe_diag(d, out, mir_vdiag_frame_record_shape(), 0, 0, 0, tid, tid) }
                } else {
                    if mir_vframe_prefix(store, t.name_start, t.name_end, mir_vframe_state_prefix()) {
                        if t.kind == mir_type_kind_enum() {
                            states = try __s0_buffer_append(MirVFrameState, d, states, MirVFrameState(type_id: tid, instance_start: t.name_start + len(mir_vframe_state_prefix()), instance_end: t.name_end, variant_count: 0))
                        } else { out = try mir_vframe_diag(d, out, mir_vdiag_frame_state_shape(), 0, 0, 0, tid, tid) }
                    } else { out = try mir_vframe_diag(d, out, mir_vdiag_frame_reserved_name(), 0, 0, 0, tid, tid) }
                }
            }
        }
        tid = tid + 1
    }
    // Reserved names are compiler-owned on every declaration form.
    var cid: U64 = 1
    while cid <= __s0_buffer_len(MirConstRec, store.constants) {
        let c = __s0_buffer_get(MirConstRec, store.constants, cid - 1)
        if mir_vframe_prefix(store, c.name_start, c.name_end, mir_vframe_reserved()) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_reserved_name(), 0, 0, 0, 0, cid) }
        cid = cid + 1
    }
    var iid: U64 = 1
    while iid <= __s0_buffer_len(MirImportRec, store.imports) {
        let item = __s0_buffer_get(MirImportRec, store.imports, iid - 1)
        if mir_vframe_prefix(store, item.name_start, item.name_end, mir_vframe_reserved()) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_reserved_name(), 0, 0, 0, 0, iid) }
        iid = iid + 1
    }
    var bid: U64 = 1
    while bid <= __s0_buffer_len(MirBindingRec, store.bindings) {
        let b = __s0_buffer_get(MirBindingRec, store.bindings, bid - 1)
        if mir_vframe_prefix(store, b.name_start, b.name_end, mir_vframe_reserved()) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_reserved_name(), 0, 0, 0, 0, bid) }
        bid = bid + 1
    }
    var bfid: U64 = 1
    while bfid <= __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
        let bf = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, bfid - 1)
        if mir_vframe_prefix(store, bf.name_start, bf.name_end, mir_vframe_reserved()) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_reserved_name(), 0, 0, 0, 0, bfid) }
        bfid = bfid + 1
    }
    // Parse frame fields in declaration order. Signature-level field checks
    // only need the frame type-id set, so the partially built scan is enough.
    let scan_so_far = MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields)
    var fi: U64 = 1
    while fi <= __s0_buffer_len(MirVFrameRec, frames) {
        var frame = __s0_buffer_get(MirVFrameRec, frames, fi - 1)
        var fparts = try __s0_buffer_new(U64, d)
        let total = mir_vindex_type_part_count(indexes, frame.type_id)
        var at: U64 = 0
        while at < total {
            let pid = mir_vindex_type_part(indexes, frame.type_id, at)
            if __s0_buffer_get(MirTypePartRec, store.type_parts, pid - 1).kind == mir_type_part_field() { fparts = try __s0_buffer_append(U64, d, fparts, pid) }
            at = at + 1
        }
        let field_start = __s0_buffer_len(MirVFrameField, fields)
        var good = true
        var pi: U64 = 0
        var pcount: U64 = 0
        var xcount: U64 = 0
        var dcount: U64 = 0
        var lcount: U64 = 0
        var vcount: U64 = 0
        var ccount: U64 = 0
        var scount: U64 = 0
        if __s0_buffer_len(U64, fparts) == 0 { good = false } else {
            let p0 = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, fparts, 0) - 1)
            if !mir_vname_word(store, p0.name_start, p0.name_end, "state") { good = false } else {
                frame.state_type = p0.part_type
                fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p0.ordinal + 1, type_id: p0.part_type, kind: mir_vframe_field_state(), index: 0))
                pi = 1
            }
        }
        if !good { out = try mir_vframe_diag(d, out, mir_vdiag_frame_record_shape(), 0, 0, 0, frame.type_id, frame.type_id) }
        while good && pi < __s0_buffer_len(U64, fparts) {
            let pid = __s0_buffer_get(U64, fparts, pi)
            let p = __s0_buffer_get(MirTypePartRec, store.type_parts, pid - 1)
            let pidx = mir_vframe_indexed(store, p.name_start, p.name_end, "p")
            if pidx != 0 {
                if pidx != pcount + 1 { good = false } else {
                    pcount = pcount + 1
                    fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_param(), index: pidx - 1))
                    pi = pi + 1
                    var borrowed = mir_vframe_type_kind_is(store, p.part_type, mir_type_kind_safe_mut())
                    if pi < __s0_buffer_len(U64, fparts) {
                        let q = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, fparts, pi) - 1)
                        let oidx = mir_vframe_indexed(store, q.name_start, q.name_end, "o")
                        if oidx != 0 {
                            if oidx != pidx || !borrowed { good = false } else {
                                if !mir_vframe_type_kind_is(store, q.part_type, mir_type_kind_domain_handle()) { good = false }
                                fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: q.ordinal + 1, type_id: q.part_type, kind: mir_vframe_field_owner(), index: pidx - 1))
                                pi = pi + 1
                            }
                        } else { if borrowed { good = false } }
                    } else { if borrowed { good = false } }
                }
            } else {
                let xidx = mir_vframe_indexed(store, p.name_start, p.name_end, "x")
                if xidx != 0 {
                    if xidx != xcount + 1 || pi + 1 >= __s0_buffer_len(U64, fparts) { good = false } else {
                        let q = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, fparts, pi + 1) - 1)
                        let yidx = mir_vframe_indexed(store, q.name_start, q.name_end, "y")
                        if yidx != xidx { good = false } else {
                            if !mir_vframe_type_kind_is(store, p.part_type, mir_type_kind_safe_mut()) { good = false } else {
                                if !mir_vframe_is_frame(scan_so_far, __s0_buffer_get(MirTypeRec, store.types, p.part_type - 1).elem) { good = false } }
                            if !mir_vframe_type_kind_is(store, q.part_type, mir_type_kind_domain_handle()) { good = false }
                            xcount = xcount + 1
                            fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_callee(), index: xidx - 1))
                            fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: q.ordinal + 1, type_id: q.part_type, kind: mir_vframe_field_callee_owner(), index: xidx - 1))
                            pi = pi + 2
                        }
                    }
                } else {
                    let didx = mir_vframe_indexed(store, p.name_start, p.name_end, "d")
                    let lidx = mir_vframe_indexed(store, p.name_start, p.name_end, "l")
                    let vidx = mir_vframe_indexed(store, p.name_start, p.name_end, "v")
                    let cidx = mir_vframe_indexed(store, p.name_start, p.name_end, "c")
                    if didx != 0 {
                        if didx != dcount + 1 || lcount != 0 || vcount != 0 || ccount != 0 || scount != 0 || !mir_vframe_type_kind_is(store, p.part_type, mir_type_kind_domain_handle()) { good = false } else {
                            dcount = dcount + 1
                            fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_domain(), index: didx - 1))
                            pi = pi + 1
                        }
                    } else {
                        if lidx != 0 {
                            if lidx != lcount + 1 || vcount != 0 || ccount != 0 || scount != 0 { good = false } else {
                                lcount = lcount + 1
                                fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_local(), index: lidx - 1))
                                pi = pi + 1
                            }
                        } else {
                            if vidx != 0 {
                                if vidx != vcount + 1 || ccount != 0 || scount != 0 { good = false } else {
                                    vcount = vcount + 1
                                    fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_temp(), index: vidx - 1))
                                    pi = pi + 1
                                }
                            } else {
                                if cidx != 0 {
                                    if cidx != ccount + 1 || scount != 0 || !mir_vframe_type_kind_is(store, p.part_type, mir_type_kind_cleanup_id()) { good = false } else {
                                        ccount = ccount + 1
                                        fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_cleanup(), index: cidx - 1))
                                        pi = pi + 1
                                    }
                                } else {
                                    let sidx = mir_vframe_indexed(store, p.name_start, p.name_end, "s")
                                    if sidx != 0 {
                                        if sidx != scount + 1 || !mir_vframe_type_kind_is(store, p.part_type, mir_type_kind_cleanup_scope()) { good = false } else {
                                            scount = scount + 1
                                            fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_scope(), index: sidx - 1))
                                            pi = pi + 1
                                        }
                                    } else {
                                        // The only remaining legal field is the final out.
                                        if mir_vname_word(store, p.name_start, p.name_end, "out") && pi + 1 == __s0_buffer_len(U64, fparts) {
                                            fields = try __s0_buffer_append(MirVFrameField, d, fields, MirVFrameField(ordinal: p.ordinal + 1, type_id: p.part_type, kind: mir_vframe_field_out(), index: 0))
                                            pi = pi + 1
                                        } else { good = false }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // A frame with fields but no parsed out is malformed.
        if good {
            var has_out = false
            var at2: U64 = 0
            while at2 < __s0_buffer_len(MirVFrameField, fields) - field_start {
                if __s0_buffer_get(MirVFrameField, fields, field_start + at2).kind == mir_vframe_field_out() { has_out = true }
                at2 = at2 + 1
            }
            if !has_out { good = false }
        }
        if !good { out = try mir_vframe_diag(d, out, mir_vdiag_frame_record_shape(), 0, 0, 0, frame.type_id, frame.type_id) }
        // Field kind restrictions that the shape parser does not cover.
        let partial = MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields)
        var at3: U64 = 0
        while at3 < __s0_buffer_len(MirVFrameField, fields) - field_start {
            let field = __s0_buffer_get(MirVFrameField, fields, field_start + at3)
            let bad_table = try mir_vmemo_contains(d, store, indexes, field.type_id, mir_type_kind_table_view())
            let bad_mut_table = try mir_vmemo_contains(d, store, indexes, field.type_id, mir_type_kind_table_mut_view())
            let bad_scope = try mir_vmemo_contains(d, store, indexes, field.type_id, mir_type_kind_cleanup_scope())
            if bad_table || bad_mut_table || (bad_scope && field.kind != mir_vframe_field_scope() && field.kind != mir_vframe_field_callee()) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_field_kind(), 0, 0, 0, frame.type_id, field.ordinal) }
            if field.kind != mir_vframe_field_callee() && field.kind != mir_vframe_field_state() && field.kind != mir_vframe_field_out() {
                if try mir_vframe_type_contains(d, partial, store, indexes, field.type_id) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_field_kind(), 0, 0, 0, frame.type_id, field.ordinal) }
            }
            at3 = at3 + 1
        }
        frame.field_start = field_start
        frame.field_count = __s0_buffer_len(MirVFrameField, fields) - field_start
        __s0_buffer_set(MirVFrameRec, frames, fi - 1, frame)
        fi = fi + 1
    }
    // Recognize step functions by the reserved run name and the pinned
    // three-parameter signature.
    var fnid: U64 = 1
    while fnid <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, fnid - 1)
        if mir_vframe_prefix(store, rec.name_start, rec.name_end, mir_vframe_reserved()) {
            reserved = true
            if !mir_vframe_prefix(store, rec.name_start, rec.name_end, mir_vframe_run_prefix()) {
                out = try mir_vframe_diag(d, out, mir_vdiag_frame_reserved_name(), fnid, 0, 0, 0, fnid)
            } else {
                var ok = true
                if mir_v5_function_param_count(store, indexes, fnid) != 3 { ok = false }
                var frame_elem: U64 = 0
                if ok {
                    let t0 = mir_v5_param_type(store, indexes, fnid, 0, mir_param_function(), 0)
                    let t1 = mir_v5_param_type(store, indexes, fnid, 0, mir_param_function(), 1)
                    let t2 = mir_v5_param_type(store, indexes, fnid, 0, mir_param_function(), 2)
                    if !mir_vframe_type_kind_is(store, t0, mir_type_kind_domain_handle()) { ok = false }
                    if !mir_vframe_type_kind_is(store, t1, mir_type_kind_safe_mut()) { ok = false } else {
                        frame_elem = __s0_buffer_get(MirTypeRec, store.types, t1 - 1).elem
                        if !mir_vframe_is_frame(MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields), frame_elem) { ok = false }
                    }
                    if !mir_vframe_type_kind_is(store, t2, mir_type_kind_domain_handle()) { ok = false }
                }
                if !status_found || rec.result_type != status_type { ok = false }
                if ok {
                    let f = mir_vframe_frame_index(MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields), frame_elem)
                    let fr = __s0_buffer_get(MirVFrameRec, frames, f - 1)
                    if !mir_vname_equal(store, rec.name_start + len(mir_vframe_run_prefix()), rec.name_end, fr.instance_start, fr.instance_end) { ok = false }
                }
                if !ok { out = try mir_vframe_diag(d, out, mir_vdiag_frame_step_signature(), fnid, 0, 0, 0, fnid) }
                if ok {
                    steps = try __s0_buffer_append(MirVFrameStep, d, steps, MirVFrameStep(function: fnid, frame_type: frame_elem, state_type: __s0_buffer_get(MirVFrameRec, frames, mir_vframe_frame_index(MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields), frame_elem) - 1).state_type, frame_param: mir_vframe_param_value(store, indexes, fnid, 1), owner_param: mir_vframe_param_value(store, indexes, fnid, 2)))
                    let f = mir_vframe_frame_index(MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields), frame_elem)
                    var fr = __s0_buffer_get(MirVFrameRec, frames, f - 1)
                    fr.step = fnid
                    __s0_buffer_set(MirVFrameRec, frames, f - 1, fr)
                }
            }
        }
        fnid = fnid + 1
    }
    // A frame type belongs to exactly one step function, and its state field
    // names the state enum with the same instance.
    var fx: U64 = 1
    while fx <= __s0_buffer_len(MirVFrameRec, frames) {
        let frame = __s0_buffer_get(MirVFrameRec, frames, fx - 1)
        var owners: U64 = 0
        var owner_fn: U64 = 0
        var sx: U64 = 1
        while sx <= __s0_buffer_len(MirVFrameStep, steps) {
            let step = __s0_buffer_get(MirVFrameStep, steps, sx - 1)
            if step.frame_type == frame.type_id { owners = owners + 1
                owner_fn = step.function }
            sx = sx + 1
        }
        if owners != 1 { out = try mir_vframe_diag(d, out, mir_vdiag_frame_ownership(), owner_fn, 0, 0, frame.type_id, frame.type_id) }
        let si = mir_vframe_state_index(MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields), frame.state_type)
        if si == 0 { out = try mir_vframe_diag(d, out, mir_vdiag_frame_record_shape(), owner_fn, 0, 0, frame.type_id, frame.type_id) } else {
            let st = __s0_buffer_get(MirVFrameState, states, si - 1)
            if !mir_vname_equal(store, frame.instance_start, frame.instance_end, st.instance_start, st.instance_end) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_state_shape(), owner_fn, 0, 0, st.type_id, st.type_id) }
        }
        fx = fx + 1
    }
    // Every state enum belongs to exactly one frame.
    var sti: U64 = 1
    while sti <= __s0_buffer_len(MirVFrameState, states) {
        let st = __s0_buffer_get(MirVFrameState, states, sti - 1)
        var users: U64 = 0
        var fj: U64 = 1
        while fj <= __s0_buffer_len(MirVFrameRec, frames) {
            if __s0_buffer_get(MirVFrameRec, frames, fj - 1).state_type == st.type_id { users = users + 1 }
            fj = fj + 1
        }
        if users != 1 { out = try mir_vframe_diag(d, out, mir_vdiag_frame_state_shape(), 0, 0, 0, st.type_id, st.type_id) }
        sti = sti + 1
    }
    // The status enum exists exactly when the module has step functions.
    if __s0_buffer_len(MirVFrameStep, steps) > 0 && !status_found { out = try mir_vframe_diag(d, out, mir_vdiag_frame_step_signature(), 0, 0, 0, 0, 0) }
    if status_found && __s0_buffer_len(MirVFrameStep, steps) == 0 { out = try mir_vframe_diag(d, out, mir_vdiag_frame_status_shape(), 0, 0, 0, status_type, status_type) }
    if status_found {
        var good_status = true
        if mir_vframe_state_variant_count(store, indexes, status_type) != 4 { good_status = false } else {
            let v0 = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, status_type, 0) - 1)
            let v1 = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, status_type, 1) - 1)
            let v2 = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, status_type, 2) - 1)
            let v3 = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, status_type, 3) - 1)
            if !mir_vname_word(store, v0.name_start, v0.name_end, "done") || v0.part_type != mir_type_unit() { good_status = false }
            if !mir_vname_word(store, v1.name_start, v1.name_end, "call") || v1.part_type != mir_type_unit() { good_status = false }
            if !mir_vname_word(store, v2.name_start, v2.name_end, "park") || v2.part_type != mir_type_unit() { good_status = false }
            if !mir_vname_word(store, v3.name_start, v3.name_end, "cancelled") || v3.part_type != mir_type_unit() { good_status = false }
        }
        if !good_status { out = try mir_vframe_diag(d, out, mir_vdiag_frame_status_shape(), 0, 0, 0, status_type, status_type) }
    }
    // State variants: entry, then contiguous resume<i>, then contiguous
    // cleanup<i>, all unit-payload.
    var sv: U64 = 1
    while sv <= __s0_buffer_len(MirVFrameState, states) {
        let st = __s0_buffer_get(MirVFrameState, states, sv - 1)
        var good_state = mir_vframe_state_variant_count(store, indexes, st.type_id) > 0
        var next_resume: U64 = 1
        var next_cleanup: U64 = 1
        var cleanup_seen = false
        var vi: U64 = 0
        while vi < mir_vframe_state_variant_count(store, indexes, st.type_id) {
            let v = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, st.type_id, vi) - 1)
            if v.part_type != mir_type_unit() { good_state = false }
            if vi == 0 {
                if !mir_vname_word(store, v.name_start, v.name_end, "entry") { good_state = false }
            } else {
                let r = mir_vframe_indexed(store, v.name_start, v.name_end, "resume")
                let c = mir_vframe_indexed(store, v.name_start, v.name_end, "cleanup")
                if r != 0 && !cleanup_seen {
                    if r != next_resume { good_state = false }
                    next_resume = next_resume + 1
                } else {
                    if c != 0 {
                        cleanup_seen = true
                        if c != next_cleanup { good_state = false }
                        next_cleanup = next_cleanup + 1
                    } else { good_state = false }
                }
            }
            vi = vi + 1
        }
        if !good_state { out = try mir_vframe_diag(d, out, mir_vdiag_frame_state_shape(), 0, 0, 0, st.type_id, st.type_id) }
        sv = sv + 1
    }
    // Frame types appear only in the owning step's borrowed frame parameter,
    // its x<i> fields, and allocation element operands. Every other
    // declaration position rejects them.
    let decl_scan = MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields)
    var dt: U64 = 1
    while dt <= __s0_buffer_len(MirTypeRec, store.types) {
        let t = __s0_buffer_get(MirTypeRec, store.types, dt - 1)
        if (t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum()) && !mir_vframe_is_frame(decl_scan, dt) {
            if try mir_vframe_type_contains(d, decl_scan, store, indexes, dt) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_type_use(), 0, 0, 0, dt, dt) }
        }
        dt = dt + 1
    }
    var lt: U64 = 1
    while lt <= __s0_buffer_len(MirLocalRec, store.locals) {
        let l = __s0_buffer_get(MirLocalRec, store.locals, lt - 1)
        if try mir_vframe_type_contains(d, decl_scan, store, indexes, l.local_type) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_type_use(), l.function, 0, 0, l.local_type, lt) }
        lt = lt + 1
    }
    var pt: U64 = 1
    while pt <= __s0_buffer_len(MirParamRec, store.params) {
        let p = __s0_buffer_get(MirParamRec, store.params, pt - 1)
        var allowed = false
        if p.kind == mir_param_function() { let step_at = mir_vframe_step_for(decl_scan, p.function)
            if step_at != 0 { let st = __s0_buffer_get(MirVFrameStep, steps, step_at - 1)
                if p.ordinal == 1 && mir_vframe_is_frame_view(decl_scan, store, p.param_type) { allowed = true } } }
        if !allowed && try mir_vframe_type_contains(d, decl_scan, store, indexes, p.param_type) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_type_use(), p.function, p.block, 0, p.param_type, pt) }
        pt = pt + 1
    }
    var ft: U64 = 1
    while ft <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let f = __s0_buffer_get(MirFunctionRec, store.functions, ft - 1)
        if try mir_vframe_type_contains(d, decl_scan, store, indexes, f.result_type) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_type_use(), ft, 0, 0, f.result_type, ft) }
        ft = ft + 1
    }
    var ct: U64 = 1
    while ct <= __s0_buffer_len(MirConstRec, store.constants) {
        let c = __s0_buffer_get(MirConstRec, store.constants, ct - 1)
        if try mir_vframe_type_contains(d, decl_scan, store, indexes, c.const_type) { out = try mir_vframe_diag(d, out, mir_vdiag_frame_type_use(), 0, 0, 0, c.const_type, ct) }
        ct = ct + 1
    }
    return Ok(MirVFrameScanResult(scan: MirVFrameScan(status_type: status_type, status_found: status_found, reserved: reserved, frames: frames, steps: steps, states: states, fields: fields), diagnostics: out))
}

// A field place is field(deref %v, name); report whether the deref base is v.
fn mir_vframe_field_place(store: MirStore, place: U64, deref: U64) -> Bool {
    if place == 0 { return false }
    var p = place
    var direct = false
    var steps: U64 = 0
    while p != 0 && steps <= __s0_buffer_len(MirPlaceRec, store.places) {
        let rec = __s0_buffer_get(MirPlaceRec, store.places, p - 1)
        if rec.kind == mir_place_deref() { return direct && rec.deref_value == deref }
        if rec.kind == mir_place_field() { direct = true
            p = rec.base
        } else { return false }
        steps = steps + 1
    }
    return false
}

// Return the field name range of a direct field place, or 0/0 when the place
// is not a direct field on a deref. Start is stored in the sign bit? No: use
// a companion that returns the field part id instead.
fn mir_vframe_field_part_of(store: MirStore, indexes: MirVIndexes, function: U64, place: U64, deref: U64) -> U64 {
    if place == 0 { return 0 }
    let rec = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if rec.kind != mir_place_field() { return 0 }
    if !mir_vframe_field_place(store, place, deref) { return 0 }
    // Resolve the field against the base type of the deref view.
    let view_type = mir_v5_value_type(store, indexes, function, deref)
    if !mir_vframe_type_kind_is(store, view_type, mir_type_kind_safe_mut()) { return 0 }
    let base = __s0_buffer_get(MirTypeRec, store.types, view_type - 1).elem
    let total = mir_vindex_type_part_count(indexes, base)
    var at: U64 = 0
    while at < total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, base, at) - 1)
        if part.kind == mir_type_part_field() && mir_vname_equal(store, rec.field_start, rec.field_end, part.name_start, part.name_end) { return mir_vindex_type_part(indexes, base, at) }
        at = at + 1
    }
    return 0
}

fn mir_vframe_field_part_word(store: MirStore, part_id: U64, word: __s0_String) -> Bool {
    if part_id == 0 { return false }
    let part = __s0_buffer_get(MirTypePartRec, store.type_parts, part_id - 1)
    return mir_vname_word(store, part.name_start, part.name_end, word)
}

fn mir_vframe_value_is_alloc(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Bool {
    let vi = mir_vindex_value(indexes, function, value)
    if vi == 0 { return false }
    let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
    if v.def_kind != mir_value_def_instruction() { return false }
    let iid = mir_vindex_instr(indexes, function, v.block, v.item - 1)
    if iid == 0 { return false }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    return x.op == mir_op_alloc() || x.op == mir_op_alloc_checked()
}

fn mir_vframe_value_is_view(scan: MirVFrameScan, store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Bool {
    let t = mir_v5_value_type(store, indexes, function, value)
    return mir_vframe_is_frame_view(scan, store, t)
}

// Phase 5 frame checks: the borrowed step frame is a deref field base only, a
// frame field place is never borrowed out, a frame view never escapes, and a
// frame record is never a value. Uses come from the shared V4 inventory.
fn mir_vframe_phase5(d: Domain, store: MirStore, indexes: MirVIndexes, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = out0
    let scanned = try mir_vframe_scan(d, store, indexes)
    let scan = scanned.scan
    if !scan.reserved { return Ok(out) }
    let inventory = try mir_vp4_use_inventory_build(d, store, indexes)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let step_index = mir_vframe_step_for(scan, function)
        var frame_param: U64 = 0
        if step_index != 0 { frame_param = __s0_buffer_get(MirVFrameStep, scan.steps, step_index - 1).frame_param }
        // Value-level rules.
        var value: U64 = 1
        while mir_vindex_value(indexes, function, value) != 0 {
            let vi = mir_vindex_value(indexes, function, value)
            let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
            let view = mir_vframe_is_frame_view(scan, store, v.value_type)
            // A frame record is never an ordinary value. safe_mut(frame) views
            // are handled as views below.
            var contains_value = false
            if !view {
                contains_value = try mir_vframe_type_contains(d, scan, store, indexes, v.value_type)
            }
            if contains_value { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_type_use(), function, 0, 0, 0, 0, v.value_type, vi, 0, 0, value)) }
            if view && value != frame_param {
                let start = __s0_buffer_get(U64, inventory.value_start, vi - 1)
                let count = __s0_buffer_get(U64, inventory.value_count, vi - 1)
                var ui: U64 = 0
                while ui < count {
                    let use = __s0_buffer_get(MirVP4Use, inventory.uses, __s0_buffer_get(U64, inventory.value_use_ids, start + ui) - 1)
                    if use.terminator != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_escape(), function, use.block, 0, use.terminator, 0, v.value_type, vi, 0, 0, value)) } else {
                        if use.operand != 0 {
                            // The fresh allocation stored into the allocating
                            // step's own x<i> is the one legal value use.
                            var allowed = false
                            if use.instruction != 0 {
                                let x = __s0_buffer_get(MirInstrRec, store.instructions, use.instruction - 1)
                                if x.op == mir_op_store() && x.a == value && mir_vframe_value_is_alloc(store, indexes, function, value) {
                                    let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
                                    if part != 0 { let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, part - 1)
                                        if mir_vframe_indexed(store, rec.name_start, rec.name_end, "x") != 0 { allowed = true } }
                                }
                                if x.op == mir_op_task_spawn() && x.b == value { allowed = true }
                            }
                            if !allowed { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_escape(), function, use.block, use.instruction, 0, use.operand, v.value_type, vi, 0, 0, value)) }
                        }
                    }
                    ui = ui + 1
                }
            }
            value = value + 1
        }
        // Instruction-level rules.
        var block: U64 = 1
        let bcount = mir_vindex_block_count(indexes, function)
        while block <= bcount {
            let block_count = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < block_count {
                let iid = mir_vindex_instr(indexes, function, block, ii)
                let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if x.op == mir_op_call() || x.op == mir_op_fn_value() {
                    if mir_vframe_step_for(scan, x.target) != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_step_call(), function, block, iid, 0, 0, 0, x.target, 0, 0, x.target)) }
                }
                if x.op == mir_op_aggregate_construct() && mir_vframe_is_frame(scan, x.type_op) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_type_use(), function, block, iid, 0, 0, x.type_op, iid, 0, 0, 0)) }
                // The borrowed step frame is never a value operand.
                if frame_param != 0 {
                    var param_bad = x.a == frame_param || x.b == frame_param || x.c == frame_param
                    let ototal = mir_vindex_op_instr_count(indexes, iid)
                    var oi: U64 = 0
                    while oi < ototal { let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, oi) - 1)
                        if o.value == frame_param && o.kind != mir_operand_switch_case() { param_bad = true }
                        oi = oi + 1 }
                    if param_bad { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_param_use(), function, block, iid, 0, x.place, 0, 0, 0, 0, 0)) }
                }
                if x.op == mir_op_borrow() || x.op == mir_op_borrow_mut() || x.op == mir_op_c_addr() {
                    let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
                    if part != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_alias_out(), function, block, iid, 0, x.place, 0, part, 0, 0, 0)) }
                }
                // The borrowed step frame is only a deref field base.
                if x.place != 0 {
                    let rec = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
                    let uses_place = x.op == mir_op_load() || x.op == mir_op_store() || x.op == mir_op_borrow() || x.op == mir_op_borrow_mut() || x.op == mir_op_c_addr() || x.op == mir_op_c_field_set() || (x.op == mir_op_cleanup_push() && rec.kind != mir_place_local())
                    if uses_place {
                        var current = x.place
                        var direct = false
                        var bad = false
                        var steps: U64 = 0
                        while current != 0 && steps <= __s0_buffer_len(MirPlaceRec, store.places) {
                            let pr = __s0_buffer_get(MirPlaceRec, store.places, current - 1)
                            if pr.kind == mir_place_deref() { if pr.deref_value == frame_param && !direct { bad = true }
                                current = 0
                            } else { if pr.kind == mir_place_field() { direct = true
                                current = pr.base
                            } else { current = 0 } }
                            steps = steps + 1
                        }
                        if bad { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_param_use(), function, block, iid, 0, x.place, 0, 0, 0, 0, 0)) }
                    }
                }
                ii = ii + 1
            }
            block = block + 1
        }
        // Terminators carry ordinary values only.
        block = 1
        while block <= bcount {
            let term_id = mir_vindex_term(indexes, function, block)
            if term_id != 0 {
                let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
                var bad = false
                if mir_vframe_is_frame_view(scan, store, mir_v5_value_type(store, indexes, function, t.value)) && t.value != 0 { bad = true }
                let total = mir_vindex_op_term_count(indexes, term_id)
                var oi: U64 = 0
                while oi < total {
                    let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                    if c.kind == mir_operand_terminator_arg() || c.kind == mir_operand_switch_case_arg() { if mir_vframe_is_frame_view(scan, store, mir_v5_value_type(store, indexes, function, c.value)) { bad = true } }
                    oi = oi + 1
                }
                if bad { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_typing(), mir_vdiag_frame_escape(), function, block, 0, term_id, 0, 0, 0, 0, 0, 0)) }
            }
            block = block + 1
        }
        function = function + 1
    }
    return Ok(out)
}

fn mir_vframe_field_pos(scan: MirVFrameScan, frame_index: U64, kind: U64, index: U64) -> U64 {
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    var at: U64 = 0
    while at < frame.field_count {
        let field = __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + at)
        if field.kind == kind && (kind == mir_vframe_field_state() || kind == mir_vframe_field_out() || field.index == index) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_field_pos_part(scan: MirVFrameScan, store: MirStore, frame_index: U64, part_id: U64) -> U64 {
    let part = __s0_buffer_get(MirTypePartRec, store.type_parts, part_id - 1)
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    var at: U64 = 0
    while at < frame.field_count {
        let field = __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + at)
        if field.ordinal == part.ordinal + 1 { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_field_kind_pos(scan: MirVFrameScan, frame_index: U64, pos: U64) -> U64 {
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    if pos == 0 || pos > frame.field_count { return 0 }
    return __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + pos - 1).kind
}

fn mir_vframe_field_ordinal_pos(scan: MirVFrameScan, store: MirStore, frame_index: U64, pos: U64) -> U64 {
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    if pos == 0 || pos > frame.field_count { return 0 }
    let field = __s0_buffer_get(MirVFrameField, scan.fields, frame.field_start + pos - 1)
    return field.ordinal
}

fn mir_vframe_saved_pair_exists(scan: MirVFrameScan, frame_index: U64, run: MirVFrameRun, save_pos: __s0_Buffer(U64)) -> Bool {
    let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
    var index: U64 = 0
    while index < frame.field_count {
        let cpos = mir_vframe_field_pos(scan, frame_index, mir_vframe_field_callee(), index)
        if cpos != 0 { let ypos = mir_vframe_field_pos(scan, frame_index, mir_vframe_field_callee_owner(), index)
            if mir_vframe_save_has(run, save_pos, cpos) && mir_vframe_save_has(run, save_pos, ypos) { return true } }
        index = index + 1
    }
    return false
}

fn mir_vframe_sort_save_pos(scan: MirVFrameScan, store: MirStore, frame_index: U64, save_pos: __s0_Buffer(U64), start: U64, count: U64) -> Unit {
    var i: U64 = 1
    while i < count {
        let value = __s0_buffer_get(U64, save_pos, start + i)
        let ordinal = mir_vframe_field_ordinal_pos(scan, store, frame_index, value)
        var j = i
        var shifted = false
        while j > 0 && !shifted {
            let prior = __s0_buffer_get(U64, save_pos, start + j - 1)
            if mir_vframe_field_ordinal_pos(scan, store, frame_index, prior) <= ordinal { shifted = true } else {
                __s0_buffer_set(U64, save_pos, start + j, prior)
                j = j - 1
            }
        }
        __s0_buffer_set(U64, save_pos, start + j, value)
        i = i + 1
    }
}

fn mir_vframe_save_has(run: MirVFrameRun, save_pos: __s0_Buffer(U64), pos: U64) -> Bool {
    var at = run.save_start
    while at < run.save_start + run.save_count { if __s0_buffer_get(U64, save_pos, at) == pos { return true }
        at = at + 1 }
    return false
}

fn mir_vframe_state_ordinal(store: MirStore, indexes: MirVIndexes, state_type: U64, start: U64, end: U64) -> U64 {
    let count = mir_vframe_state_variant_count(store, indexes, state_type)
    var at: U64 = 0
    while at < count {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, state_type, at) - 1)
        if mir_vname_equal(store, part.name_start, part.name_end, start, end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn mir_vframe_resume_index(store: MirStore, indexes: MirVIndexes, state_type: U64, ordinal: U64) -> U64 {
    if ordinal == 0 { return 0 }
    let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, state_type, ordinal - 1) - 1)
    return mir_vframe_indexed(store, part.name_start, part.name_end, "resume")
}

fn mir_vframe_cleanup_index(store: MirStore, indexes: MirVIndexes, state_type: U64, ordinal: U64) -> U64 {
    if ordinal == 0 { return 0 }
    let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vframe_variant(store, indexes, state_type, ordinal - 1) - 1)
    return mir_vframe_indexed(store, part.name_start, part.name_end, "cleanup")
}

fn mir_vframe_def_instr(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let vi = mir_vindex_value(indexes, function, value)
    if vi == 0 { return 0 }
    let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
    return mir_v6_instruction_for_value(store, indexes, v)
}

fn mir_vframe_status_ordinal(store: MirStore, indexes: MirVIndexes, function: U64, status_type: U64, value: U64) -> U64 {
    let iid = mir_vframe_def_instr(store, indexes, function, value)
    if iid == 0 { return 0 }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op != mir_op_enum_construct() || x.type_op != status_type { return 0 }
    return mir_vframe_state_ordinal(store, indexes, status_type, x.name_start, x.name_end)
}

fn mir_vframe_state_store_variant(store: MirStore, indexes: MirVIndexes, function: U64, state_type: U64, value: U64) -> U64 {
    let iid = mir_vframe_def_instr(store, indexes, function, value)
    if iid == 0 { return 0 }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op != mir_op_enum_construct() || x.type_op != state_type { return 0 }
    return mir_vframe_state_ordinal(store, indexes, state_type, x.name_start, x.name_end)
}

// Cancellation observation is the binding call resolved to the runtime's
// alder_task_cancelled entry, never a user spelling.
fn mir_vframe_cancel_cond(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Bool {
    let iid = mir_vframe_def_instr(store, indexes, function, value)
    if iid == 0 { return false }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op != mir_op_c_binding_call() || !mir_vid_valid(x.target, __s0_buffer_len(MirBindingFnRec, store.binding_funcs)) { return false }
    let b = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, x.target - 1)
    return mir_vname_word(store, b.c_name_start, b.c_name_end, "alder_task_cancelled")
}

fn mir_vframe_pred_count(store: MirStore, indexes: MirVIndexes, function: U64, target: U64) -> U64 {
    if target == 0 { return 0 }
    var count: U64 = 0
    let bcount = mir_vindex_block_count(indexes, function)
    var block: U64 = 1
    while block <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, block)
        var ii: U64 = 0
        while ii < icount { let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, block, ii) - 1)
            if mir_vop_checked(x.op) && x.target == target { count = count + 1 }
            ii = ii + 1 }
        let term_id = mir_vindex_term(indexes, function, block)
        if term_id != 0 { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            if t.kind == mir_term_jump() && t.target == target { count = count + 1 }
            if t.kind == mir_term_branch() { if t.then_block == target { count = count + 1 }
                if t.else_block == target { count = count + 1 } }
            if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
                var oi: U64 = 0
                while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                    if c.kind == mir_operand_switch_case() && c.target == target { count = count + 1 }
                    oi = oi + 1 } } }
        block = block + 1
    }
    return count
}

fn mir_vframe_edge(store: MirStore, indexes: MirVIndexes, function: U64, from: U64, to: U64) -> U64 {
    // 0 none, 1 normal edge, 2 cancellation-true edge.
    var cancel: U64 = 0
    var normal: U64 = 0
    let icount = mir_vindex_instr_count(indexes, function, from)
    var ii: U64 = 0
    while ii < icount { let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, from, ii) - 1)
        if mir_vop_checked(x.op) && x.target == to { normal = 1 }
        ii = ii + 1 }
    let term_id = mir_vindex_term(indexes, function, from)
    if term_id != 0 { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
        if t.kind == mir_term_jump() && t.target == to { normal = 1 }
        if t.kind == mir_term_branch() { if t.then_block == to { if mir_vframe_cancel_cond(store, indexes, function, t.value) { cancel = 1 } else { normal = 1 } }
            if t.else_block == to { normal = 1 } }
        if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                if c.kind == mir_operand_switch_case() && c.target == to { normal = 1 }
                oi = oi + 1 } } }
    if cancel != 0 { return 2 }
    if normal != 0 { return 1 }
    return 0
}

type MirVFrameRun {
    suspend_block: U64
    save_start: U64
    save_count: U64
}

fn mir_vframe_state_target(store: MirStore, indexes: MirVIndexes, function: U64, state_type: U64, term_id: U64, variant: U64) -> U64 {
    if term_id == 0 { return 0 }
    let total = mir_vindex_op_term_count(indexes, term_id)
    var oi: U64 = 0
    while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
        if c.kind == mir_operand_switch_case() && mir_vframe_state_ordinal(store, indexes, state_type, c.name_start, c.name_end) == variant { return c.target }
        oi = oi + 1 }
    return 0
}

fn mir_vframe_reach_has(reach: __s0_Buffer(U64), block: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(U64, reach) { if __s0_buffer_get(U64, reach, at) == block { return true }
        at = at + 1 }
    return false
}

fn mir_vframe_bit(value: U64, bit: U64) -> Bool { return (value / mir_vframe_pow2(bit)) % 2 == 1 }

fn mir_vframe_set_bit(value: U64, bit: U64) -> U64 { if mir_vframe_bit(value, bit) { return value }
    return value + mir_vframe_pow2(bit) }

fn mir_vframe_and(a: U64, b: U64) -> U64 {
    var result: U64 = 0
    var bit: U64 = 0
    while bit < 64 { if mir_vframe_bit(a, bit) && mir_vframe_bit(b, bit) { result = mir_vframe_set_bit(result, bit) }
        bit = bit + 1 }
    return result
}

fn mir_vframe_or(a: U64, b: U64) -> U64 {
    var result = a
    var bit: U64 = 0
    while bit < 64 { if mir_vframe_bit(b, bit) { result = mir_vframe_set_bit(result, bit) }
        bit = bit + 1 }
    return result
}

fn mir_vframe_pow2(bit: U64) -> U64 { var v: U64 = 1
var at: U64 = 0
while at < bit { v = v * 2
at = at + 1 }
return v }

// Phase 6 frame checks: canonical dispatch, one suspend block per state,
// ordered save lists, exact resume load lists, and the status contract.
fn mir_vframe_phase6(d: Domain, store: MirStore, indexes: MirVIndexes, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = out0
    let scanned = try mir_vframe_scan(d, store, indexes)
    let scan = scanned.scan
    if !scan.reserved { return Ok(out) }
    var si: U64 = 1
    while si <= __s0_buffer_len(MirVFrameStep, scan.steps) {
        let step = __s0_buffer_get(MirVFrameStep, scan.steps, si - 1)
        let function = step.function
        let frame_index = mir_vframe_frame_index(scan, step.frame_type)
        let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
        let bcount = mir_vindex_block_count(indexes, function)
        let vc = mir_vframe_state_variant_count(store, indexes, step.state_type)
        // Dispatch block.
        var dispatch_ok = true
        if bcount < 1 || mir_vindex_instr_count(indexes, function, 1) != 1 { dispatch_ok = false }
        var state_load: U64 = 0
        if dispatch_ok { let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, 1, 0) - 1)
            if x.op != mir_op_load() { dispatch_ok = false } else {
                let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                if !mir_vframe_field_part_word(store, part, "state") { dispatch_ok = false }
                state_load = x.result } }
        var term_id: U64 = 0
        if dispatch_ok { term_id = mir_vindex_term(indexes, function, 1)
            if term_id == 0 { dispatch_ok = false } else { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
                if t.kind != mir_term_switch() || t.value != state_load { dispatch_ok = false } } }
        // Dispatch case targets, one per state variant, no default.
        var target_count: U64 = 0
        if dispatch_ok { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            let total = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                if c.kind == mir_operand_switch_case() { target_count = target_count + 1
                    if mir_vframe_state_ordinal(store, indexes, step.state_type, c.name_start, c.name_end) == 0 { dispatch_ok = false }
                    if c.target < 1 || c.target > bcount { dispatch_ok = false }
                }
                oi = oi + 1 }
            if target_count != vc { dispatch_ok = false }
        }
        if !dispatch_ok { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_dispatch(), function, 1, 0, 0, 0, 0, function, 0, 0, 0)) }
        // Each state target has exactly one predecessor: the dispatch block.
        if dispatch_ok { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            let total = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                if c.kind == mir_operand_switch_case() { if mir_vframe_pred_count(store, indexes, function, c.target) != 1 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_dispatch(), function, c.target, 0, 0, 0, 0, function, 0, 0, 0)) } else { if mir_vframe_edge(store, indexes, function, 1, c.target) == 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_dispatch(), function, c.target, 0, 0, 0, 0, function, 0, 0, 0)) } } }
                oi = oi + 1 } }
        // Save lists.
        var runs = try __s0_buffer_new(MirVFrameRun, d)
        var r: U64 = 0
        while r < vc { runs = try __s0_buffer_append(MirVFrameRun, d, runs, MirVFrameRun(suspend_block: 0, save_start: 0, save_count: 0))
            r = r + 1 }
        var save_pos = try __s0_buffer_new(U64, d)
        var block: U64 = 2
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var state_iid: U64 = 0
            var state_ordinal: U64 = 0
            var state_variant: U64 = 0
            var ii: U64 = 0
            while ii < icount { let iid = mir_vindex_instr(indexes, function, block, ii)
                let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if x.op == mir_op_store() && mir_vframe_field_part_word(store, mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param), "state") {
                    if state_iid != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_save_order(), function, block, iid, 0, x.place, 0, function, 0, 0, 0)) } else {
                        state_iid = iid
                        state_ordinal = ii + 1
                        state_variant = mir_vframe_state_store_variant(store, indexes, function, step.state_type, x.a)
                    }
                }
                ii = ii + 1 }
            if state_iid != 0 {
                if state_variant == 0 || state_variant == 1 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_save_order(), function, block, state_iid, 0, 0, 0, function, 0, 0, state_variant)) } else {
                    var run = __s0_buffer_get(MirVFrameRun, runs, state_variant - 1)
                    if run.suspend_block != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_suspend_dup(), function, block, state_iid, 0, 0, 0, function, 0, 0, state_variant)) } else {
                        run.suspend_block = block
                        run.save_start = __s0_buffer_len(U64, save_pos)
                        var last_ordinal: U64 = 0
                        var bad = false
                        var ord: U64 = state_ordinal
                        while ord < icount { let oiid = mir_vindex_instr(indexes, function, block, ord)
                            let o = __s0_buffer_get(MirInstrRec, store.instructions, oiid - 1)
                            if o.op == mir_op_store() { let part = mir_vframe_field_part_of(store, indexes, function, o.place, step.frame_param)
                                if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                                    let kind = mir_vframe_field_kind_pos(scan, frame_index, pos)
                                    let savable = kind == mir_vframe_field_callee() || kind == mir_vframe_field_callee_owner() || kind == mir_vframe_field_domain() || kind == mir_vframe_field_local() || kind == mir_vframe_field_temp() || kind == mir_vframe_field_cleanup() || kind == mir_vframe_field_scope()
                                    if !savable { bad = true } else { let part_rec = __s0_buffer_get(MirTypePartRec, store.type_parts, part - 1)
                                        if kind != mir_vframe_field_scope() { if part_rec.ordinal <= last_ordinal { bad = true }
                                            last_ordinal = part_rec.ordinal }
                                        save_pos = try __s0_buffer_append(U64, d, save_pos, pos) } } }
                            ord = ord + 1 }
                        mir_vframe_sort_save_pos(scan, store, frame_index, save_pos, run.save_start, __s0_buffer_len(U64, save_pos) - run.save_start)
                        if bad { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_save_order(), function, block, state_iid, 0, 0, 0, function, 0, 0, state_variant)) }
                        run.save_count = __s0_buffer_len(U64, save_pos) - run.save_start
                        __s0_buffer_set(MirVFrameRun, runs, state_variant - 1, run)
                        // A suspend block returns call or park.
                        let sterm = mir_vindex_term(indexes, function, block)
                        var suspend_ok = false
                        if sterm != 0 { let t = __s0_buffer_get(MirTermRec, store.terminators, sterm - 1)
                            if t.kind == mir_term_return() { let status = mir_vframe_status_ordinal(store, indexes, function, scan.status_type, t.value)
                                if status == 2 || status == 3 { suspend_ok = true } } }
                        if !suspend_ok { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_save_order(), function, block, 0, sterm, 0, 0, function, 0, 0, state_variant)) }
                    }
                }
            }
            block = block + 1
        }
        // Every non-entry state has one suspend block, and its resume block
        // loads exactly the saved fields in frame order.
        var variant: U64 = 2
        while variant <= vc {
            let run = __s0_buffer_get(MirVFrameRun, runs, variant - 1)
            if run.suspend_block == 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_suspend_dup(), function, 1, 0, 0, 0, 0, function, 0, 0, variant)) } else {
                // Find the dispatch target for this variant.
                var target: U64 = 0
                if dispatch_ok { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
                    let total = mir_vindex_op_term_count(indexes, term_id)
                    var oi: U64 = 0
                    while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                        if c.kind == mir_operand_switch_case() && mir_vframe_state_ordinal(store, indexes, step.state_type, c.name_start, c.name_end) == variant { target = c.target }
                        oi = oi + 1 } }
                if target != 0 {
                    var loads = try __s0_buffer_new(U64, d)
                    var visited = try __s0_buffer_new(U64, d)
                    var vi: U64 = 0
                    while vi <= bcount { visited = try __s0_buffer_append(U64, d, visited, 0)
                        vi = vi + 1 }
                    var current = target
                    var steps: U64 = 0
                    while current != 0 && current <= bcount && steps <= bcount {
                        __s0_buffer_set(U64, visited, current, 1)
                        let lcount = mir_vindex_instr_count(indexes, function, current)
                        var li: U64 = 0
                        while li < lcount { let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, current, li) - 1)
                            if x.op == mir_op_load() { let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                                if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                                    let kind = mir_vframe_field_kind_pos(scan, frame_index, pos)
                                    if kind == mir_vframe_field_callee() || kind == mir_vframe_field_callee_owner() || kind == mir_vframe_field_domain() || kind == mir_vframe_field_local() || kind == mir_vframe_field_temp() || kind == mir_vframe_field_cleanup() || kind == mir_vframe_field_scope() { loads = try __s0_buffer_append(U64, d, loads, pos) } } }
                            li = li + 1 }
                        let t = mir_vindex_term(indexes, function, current)
                        var next: U64 = 0
                        if t != 0 { let term = __s0_buffer_get(MirTermRec, store.terminators, t - 1)
                            if term.kind == mir_term_jump() { next = term.target } else { if term.kind == mir_term_branch() && mir_vframe_cancel_cond(store, indexes, function, term.value) { next = term.else_block } } }
                        if next == 0 || __s0_buffer_get(U64, visited, next) != 0 || mir_vframe_pred_count(store, indexes, function, next) != 1 { current = 0 } else { current = next }
                        steps = steps + 1
                    }
                    var same = __s0_buffer_len(U64, loads) == run.save_count
                    if same { var li2: U64 = 0
                        while li2 < run.save_count { if __s0_buffer_get(U64, loads, li2) != __s0_buffer_get(U64, save_pos, run.save_start + li2) { same = false }
                            li2 = li2 + 1 } }
                    if !same { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_load_set(), function, target, 0, 0, 0, 0, function, 0, 0, variant)) }
                }
            }
            variant = variant + 1
        }
        // State and out dataflow, then one diagnostic per failing return.
        let fc = frame.field_count
        let words = (fc + 63) / 64
        var must = try __s0_buffer_new(U64, d)
        var out_must = try __s0_buffer_new(U64, d)
        var out_may = try __s0_buffer_new(U64, d)
        var cur_state = try __s0_buffer_new(U64, d)
        var seeded = try __s0_buffer_new(U64, d)
        var queued = try __s0_buffer_new(U64, d)
        var slot: U64 = 0
        while slot < (bcount + 1) * words { must = try __s0_buffer_append(U64, d, must, 0)
            slot = slot + 1 }
        slot = 0
        while slot <= bcount { out_must = try __s0_buffer_append(U64, d, out_must, 0)
            out_may = try __s0_buffer_append(U64, d, out_may, 0)
            cur_state = try __s0_buffer_append(U64, d, cur_state, 0)
            seeded = try __s0_buffer_append(U64, d, seeded, 0)
            queued = try __s0_buffer_append(U64, d, queued, 0)
            slot = slot + 1 }
        var queue = try __s0_buffer_new(U64, d)
        // Seed the dispatch block with the caller-initialized p/o/state fields.
        let out_pos = mir_vframe_field_pos(scan, frame_index, mir_vframe_field_out(), 0)
        // Every caller-initialized p/o/state field seeds the dispatch block,
        // not just the first field of each group.
        let frame_rec = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
        var seed_field: U64 = 0
        while seed_field < frame_rec.field_count {
            let field = __s0_buffer_get(MirVFrameField, scan.fields, frame_rec.field_start + seed_field)
            if field.kind == mir_vframe_field_param() || field.kind == mir_vframe_field_owner() || field.kind == mir_vframe_field_state() {
                let pos = seed_field + 1
                let word = (pos - 1) / 64
                if word < words { __s0_buffer_set(U64, must, words + word, mir_vframe_set_bit(__s0_buffer_get(U64, must, words + word), (pos - 1) % 64)) }
            }
            seed_field = seed_field + 1
        }
        let base_word = __s0_buffer_get(U64, must, words)
        __s0_buffer_set(U64, seeded, 0, 1)
        __s0_buffer_set(U64, queued, 0, 1)
        queue = try __s0_buffer_append(U64, d, queue, 1)
        // Seed the entry target and every resume target.
        if dispatch_ok { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            let total = mir_vindex_op_term_count(indexes, term_id)
            var oi: U64 = 0
            while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
                if c.kind == mir_operand_switch_case() { let ord = mir_vframe_state_ordinal(store, indexes, step.state_type, c.name_start, c.name_end)
                    if ord == 1 && c.target >= 1 && c.target <= bcount { __s0_buffer_set(U64, must, c.target * words, base_word)
                        __s0_buffer_set(U64, cur_state, c.target, ord)
                        __s0_buffer_set(U64, seeded, c.target, 1)
                        if __s0_buffer_get(U64, queued, c.target) == 0 { __s0_buffer_set(U64, queued, c.target, 1)
                            queue = try __s0_buffer_append(U64, d, queue, c.target) } } }
                oi = oi + 1 } }
        // Seed every resume root with its saved fields before the worklist.
        var sv2: U64 = 2
        while sv2 <= vc {
            let run = __s0_buffer_get(MirVFrameRun, runs, sv2 - 1)
            let target = mir_vframe_state_target(store, indexes, function, step.state_type, term_id, sv2)
            if target != 0 && run.suspend_block != 0 {
                var sw2: U64 = 0
                while sw2 < words { var value: U64 = 0
                    if sw2 == 0 { value = base_word }
                    var sc2: U64 = 0
                    while sc2 < run.save_count { let pos3 = __s0_buffer_get(U64, save_pos, run.save_start + sc2)
                        if (pos3 - 1) / 64 == sw2 { value = mir_vframe_set_bit(value, (pos3 - 1) % 64) }
                        sc2 = sc2 + 1 }
                    __s0_buffer_set(U64, must, target * words + sw2, value)
                    sw2 = sw2 + 1 }
                __s0_buffer_set(U64, cur_state, target, sv2)
                __s0_buffer_set(U64, seeded, target, 1)
                if __s0_buffer_get(U64, queued, target) == 0 { __s0_buffer_set(U64, queued, target, 1)
                    queue = try __s0_buffer_append(U64, d, queue, target) }
            }
            sv2 = sv2 + 1
        }
        var q: U64 = 0
        while q < __s0_buffer_len(U64, queue) {
            let bi = __s0_buffer_get(U64, queue, q)
            __s0_buffer_set(U64, queued, bi, 0)
            q = q + 1
            if bi >= 1 && bi <= bcount {
                // Copy the block's facts.
                var tmp = try __s0_buffer_new(U64, d)
                var w: U64 = 0
                while w < words { tmp = try __s0_buffer_append(U64, d, tmp, __s0_buffer_get(U64, must, bi * words + w))
                    w = w + 1 }
                var st = __s0_buffer_get(U64, cur_state, bi)
                var omust = __s0_buffer_get(U64, out_must, bi)
                var omay = __s0_buffer_get(U64, out_may, bi)
                let icount = mir_vindex_instr_count(indexes, function, bi)
                var ii: U64 = 0
                while ii < icount { let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, bi, ii) - 1)
                    if x.op == mir_op_store() { let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                        if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                            if pos != 0 { let word = (pos - 1) / 64
                                let bit = (pos - 1) % 64
                                __s0_buffer_set(U64, tmp, word, mir_vframe_set_bit(__s0_buffer_get(U64, tmp, word), bit)) }
                            if pos == out_pos { omust = 1
                                omay = 1 }
                            let sv = mir_vframe_state_store_variant(store, indexes, function, step.state_type, x.a)
                            if sv != 0 { st = sv } } }
                    ii = ii + 1 }
                // Refresh the resume root from this suspend block.
                var variant2: U64 = 2
                while variant2 <= vc {
                    let run = __s0_buffer_get(MirVFrameRun, runs, variant2 - 1)
                    if run.suspend_block == bi { let target = mir_vframe_state_target(store, indexes, function, step.state_type, term_id, variant2)
                        if target != 0 {
                            var sw: U64 = 0
                            while sw < words { var value = base_word
                                if sw == 0 { value = base_word } else { value = 0 }
                                // Save fields are spread across words.
                                var sc: U64 = 0
                                while sc < run.save_count { let pos2 = __s0_buffer_get(U64, save_pos, run.save_start + sc)
                                    if (pos2 - 1) / 64 == sw { value = mir_vframe_set_bit(value, (pos2 - 1) % 64) }
                                    sc = sc + 1 }
                                if sw == (out_pos - 1) / 64 { if omust != 0 { value = mir_vframe_set_bit(value, (out_pos - 1) % 64) } }
                                __s0_buffer_set(U64, must, target * words + sw, value)
                                sw = sw + 1 }
                            __s0_buffer_set(U64, cur_state, target, variant2)
                            __s0_buffer_set(U64, out_must, target, omust)
                            __s0_buffer_set(U64, out_may, target, omay)
                            if __s0_buffer_get(U64, queued, target) == 0 { __s0_buffer_set(U64, queued, target, 1)
                                queue = try __s0_buffer_append(U64, d, queue, target) }
                        }
                    }
                    variant2 = variant2 + 1
                }
                // Propagate to successors.
                let t = mir_vindex_term(indexes, function, bi)
                var targets = try __s0_buffer_new(U64, d)
                if t != 0 { let term = __s0_buffer_get(MirTermRec, store.terminators, t - 1)
                    if term.kind == mir_term_jump() { targets = try __s0_buffer_append(U64, d, targets, term.target) }
                    if term.kind == mir_term_branch() { targets = try __s0_buffer_append(U64, d, targets, term.then_block)
                        targets = try __s0_buffer_append(U64, d, targets, term.else_block) }
                    if term.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, t)
                        var oi: U64 = 0
                        while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, t, oi) - 1)
                            if c.kind == mir_operand_switch_case() && (bi != 1 || mir_vframe_state_ordinal(store, indexes, step.state_type, c.name_start, c.name_end) == 1) { targets = try __s0_buffer_append(U64, d, targets, c.target) }
                            oi = oi + 1 } } }
                var ti: U64 = 0
                while ti < __s0_buffer_len(U64, targets) { let target = __s0_buffer_get(U64, targets, ti)
                    ti = ti + 1
                    if target >= 1 && target <= bcount && target != 1 {
                        var changed = false
                        if __s0_buffer_get(U64, seeded, target) == 0 { __s0_buffer_set(U64, seeded, target, 1)
                            var w2: U64 = 0
                            while w2 < words { __s0_buffer_set(U64, must, target * words + w2, __s0_buffer_get(U64, tmp, w2))
                                w2 = w2 + 1 }
                            __s0_buffer_set(U64, cur_state, target, st)
                            __s0_buffer_set(U64, out_must, target, omust)
                            __s0_buffer_set(U64, out_may, target, omay)
                            changed = true
                        } else {
                            if __s0_buffer_get(U64, cur_state, target) != st && __s0_buffer_get(U64, cur_state, target) != 0 { __s0_buffer_set(U64, cur_state, target, 0)
                                changed = true }
                            var w2: U64 = 0
                            while w2 < words { let old = __s0_buffer_get(U64, must, target * words + w2)
                                let incoming = __s0_buffer_get(U64, tmp, w2)
                                let merged = mir_vframe_and(old, incoming)
                                if merged != old { __s0_buffer_set(U64, must, target * words + w2, merged)
                                    changed = true }
                                w2 = w2 + 1 }
                            let old_must = __s0_buffer_get(U64, out_must, target)
                            let new_must = mir_vframe_and(old_must, omust)
                            if new_must != old_must { __s0_buffer_set(U64, out_must, target, new_must)
                                changed = true }
                            let old_may = __s0_buffer_get(U64, out_may, target)
                            let new_may = mir_vframe_or(old_may, omay)
                            if new_may != old_may { __s0_buffer_set(U64, out_may, target, new_may)
                                changed = true }
                        }
                        if changed { if __s0_buffer_get(U64, queued, target) == 0 { __s0_buffer_set(U64, queued, target, 1)
                                queue = try __s0_buffer_append(U64, d, queue, target) } }
                    }
                }
            }
        }
        // Frame allocations: child of the activation domain, stored once in
        // the allocating step's own x<i>.
        var ab: U64 = 1
        while ab <= bcount {
            let acount = mir_vindex_instr_count(indexes, function, ab)
            var ai: U64 = 0
            while ai < acount { let aid = mir_vindex_instr(indexes, function, ab, ai)
                let alloc = __s0_buffer_get(MirInstrRec, store.instructions, aid - 1)
                if (alloc.op == mir_op_alloc() || alloc.op == mir_op_alloc_checked()) && mir_vframe_is_frame(scan, alloc.type_op) {
                    let dom_id = mir_vframe_def_instr(store, indexes, function, alloc.a)
                    var dom_ok = false
                    if dom_id != 0 { let dom = __s0_buffer_get(MirInstrRec, store.instructions, dom_id - 1)
                        if dom.op == mir_op_domain_create() && dom.a == step.owner_param { dom_ok = true } }
                    if !dom_ok { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_alloc_site(), function, ab, aid, 0, 0, alloc.type_op, function, 0, 0, alloc.type_op)) }
                    var stores: U64 = 0
                    var valid_target = false
                    var sb: U64 = 1
                    while sb <= bcount { let scount = mir_vindex_instr_count(indexes, function, sb)
                        var sj: U64 = 0
                        while sj < scount { let st = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, sb, sj) - 1)
                            if st.op == mir_op_store() && st.a == alloc.result { stores = stores + 1
                                let part = mir_vframe_field_part_of(store, indexes, function, st.place, step.frame_param)
                                if part != 0 { let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, part - 1)
                                    if mir_vframe_indexed(store, rec.name_start, rec.name_end, "x") != 0 { valid_target = true } } }
                            sj = sj + 1 }
                        sb = sb + 1 }
                    // A spawn site consumes the fresh frame as the task.spawn
                    // frame operand instead of storing it into x<i>.
                    var spawned = false
                    sb = 1
                    while sb <= bcount { let scount = mir_vindex_instr_count(indexes, function, sb)
                        var sj: U64 = 0
                        while sj < scount { let st = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, sb, sj) - 1)
                            if st.op == mir_op_task_spawn() && st.b == alloc.result { spawned = true }
                            sj = sj + 1 }
                        sb = sb + 1 }
                    if !spawned && (stores != 1 || !valid_target) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_alloc_use(), function, ab, aid, 0, 0, alloc.type_op, function, 0, 0, alloc.result)) }
                }
                ai = ai + 1 }
            ab = ab + 1
        }
        // Emit return and uninitialized-load diagnostics in block order.
        var reach = try mir_vreachable(d, store, indexes, function)
        var teardown = try __s0_buffer_new(U64, d)
        var bi: U64 = 0
        while bi <= bcount { teardown = try __s0_buffer_append(U64, d, teardown, 1)
            bi = bi + 1 }
        __s0_buffer_set(U64, teardown, 0, 0)
        var changed2 = true
        while changed2 { changed2 = false
            bi = 2
            while bi <= bcount { var val: U64 = 0
                var pred: U64 = 1
                while pred <= bcount { let edge = mir_vframe_edge(store, indexes, function, pred, bi)
                    if edge == 2 { val = 1 } else { if edge == 1 && __s0_buffer_get(U64, teardown, pred) != 0 { val = 1 } }
                    pred = pred + 1 }
                if __s0_buffer_get(U64, teardown, bi) != val { __s0_buffer_set(U64, teardown, bi, val)
                    changed2 = true }
                bi = bi + 1 }
        }
        bi = 1
        while bi <= bcount {
            if mir_vframe_reach_has(reach, bi) {
                // Replay the block's stores for the check pass.
                var st = __s0_buffer_get(U64, cur_state, bi)
                var omust = __s0_buffer_get(U64, out_must, bi)
                var omay = __s0_buffer_get(U64, out_may, bi)
                let icount = mir_vindex_instr_count(indexes, function, bi)
                var ii: U64 = 0
                while ii < icount { let iid = mir_vindex_instr(indexes, function, bi, ii)
                    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                    if x.op == mir_op_load() { let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                        if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                            let field_kind = mir_vframe_field_kind_pos(scan, frame_index, pos)
                            var initialized = field_kind == mir_vframe_field_param() || field_kind == mir_vframe_field_owner() || field_kind == mir_vframe_field_state()
                            if !initialized && pos >= 1 && (pos - 1) / 64 < words { if mir_vframe_bit(__s0_buffer_get(U64, must, bi * words + (pos - 1) / 64), (pos - 1) % 64) { initialized = true } }
                            if !initialized { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_uninit_load(), function, bi, iid, 0, x.place, 0, function, 0, 0, pos)) } } }
                    if x.op == mir_op_store() { let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                        if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                            if pos == out_pos { omust = 1
                                omay = 1 }
                            let sv = mir_vframe_state_store_variant(store, indexes, function, step.state_type, x.a)
                            if sv != 0 { st = sv } } }
                    ii = ii + 1 }
                let t = mir_vindex_term(indexes, function, bi)
                if t != 0 { let term = __s0_buffer_get(MirTermRec, store.terminators, t - 1)
                    if term.kind == mir_term_return() && term.value != 0 { let status = mir_vframe_status_ordinal(store, indexes, function, scan.status_type, term.value)
                        if status == 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_done(), function, bi, 0, t, 0, 0, function, 0, 0, 0)) } else {
                            if status == 1 { if out_pos == 0 || omust == 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_done(), function, bi, 0, t, 0, 0, function, 0, 0, 0)) } }
                            if status == 2 || status == 3 {
                                let idx = mir_vframe_resume_index(store, indexes, step.state_type, st)
                                let run = __s0_buffer_get(MirVFrameRun, runs, st - 1)
                                if idx != 0 {
                                    let has_callee = mir_vframe_field_pos(scan, frame_index, mir_vframe_field_callee(), idx - 1) != 0
                                    let cpos = mir_vframe_field_pos(scan, frame_index, mir_vframe_field_callee(), idx - 1)
                                    let ypos = mir_vframe_field_pos(scan, frame_index, mir_vframe_field_callee_owner(), idx - 1)
                                    let saved = mir_vframe_save_has(run, save_pos, cpos) && mir_vframe_save_has(run, save_pos, ypos)
                                    if status == 2 { if !has_callee || !saved { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_call(), function, bi, 0, t, 0, 0, function, 0, 0, idx)) } }
                                    if status == 3 { if has_callee { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_park(), function, bi, 0, t, 0, 0, function, 0, 0, idx)) } }
                                } else {
                                    let cidx = mir_vframe_cleanup_index(store, indexes, step.state_type, st)
                                    if cidx == 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_call(), function, bi, 0, t, 0, 0, function, 0, 0, 0)) } else {
                                        let pair = mir_vframe_saved_pair_exists(scan, frame_index, run, save_pos)
                                        if status == 2 { if !pair { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_call(), function, bi, 0, t, 0, 0, function, 0, 0, cidx)) } }
                                        if status == 3 { if pair { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_park(), function, bi, 0, t, 0, 0, function, 0, 0, cidx)) } }
                                    }
                                }
                            }
                            if status == 4 { if omay != 0 || __s0_buffer_get(U64, teardown, bi) == 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), mir_vdiag_frame_status_cancelled(), function, bi, 0, t, 0, 0, function, 0, 0, 0)) } }
                        }
                    } }
            }
            bi = bi + 1
        }
        si = si + 1
    }
    return Ok(out)
}

// A frame field place is a direct field on a safe_mut view of a reserved frame
// aggregate. Phase 1 and the Phase 6 store exemption use this name-only form.
fn mir_vframe_place_frame_field(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> Bool {
    if place == 0 { return false }
    let rec = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if rec.kind != mir_place_field() { return false }
    let base = __s0_buffer_get(MirPlaceRec, store.places, rec.base - 1)
    if base.kind != mir_place_deref() { return false }
    let view_type = mir_v5_value_type(store, indexes, function, base.deref_value)
    if !mir_vframe_type_kind_is(store, view_type, mir_type_kind_safe_mut()) { return false }
    let elem = __s0_buffer_get(MirTypeRec, store.types, view_type - 1).elem
    if !mir_vframe_type_kind_is(store, elem, mir_type_kind_aggregate()) { return false }
    let t = __s0_buffer_get(MirTypeRec, store.types, elem - 1)
    return mir_vframe_prefix(store, t.name_start, t.name_end, mir_vframe_type_prefix())
}

fn mir_vframe_status_type(store: MirStore) -> U64 {
    var at: U64 = 1
    while at <= __s0_buffer_len(MirTypeRec, store.types) { let t = __s0_buffer_get(MirTypeRec, store.types, at - 1)
        if t.kind == mir_type_kind_enum() && mir_vname_word(store, t.name_start, t.name_end, mir_vframe_status_name()) { return at }
        at = at + 1 }
    return 0
}

fn mir_vframe_function_is_step(store: MirStore, function: U64) -> Bool {
    if !mir_vid_valid(function, __s0_buffer_len(MirFunctionRec, store.functions)) { return false }
    let f = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    return mir_vframe_prefix(store, f.name_start, f.name_end, mir_vframe_run_prefix())
}

type MirVFrameAnchor {
    pos: U64
    block: U64
    instruction: U64
}

fn mir_vframe_zero_anchor() -> MirVFrameAnchor {
    return MirVFrameAnchor(pos: 0, block: 0, instruction: 0)
}

// The adopting begin anchors the frame s<i> field it stores into. All
// emissions storing the same field are one dynamic scope; a suspend block may
// store the same begin value again as part of its save list.
fn mir_vframe_begin_anchor(store: MirStore, indexes: MirVIndexes, function: U64, scan: MirVFrameScan, frame_index: U64, frame_param: U64, begin: U64) -> MirVFrameAnchor {
    var result = mir_vframe_zero_anchor()
    let def = mir_vframe_def_instr(store, indexes, function, begin)
    if def == 0 { return result }
    let begin_block = __s0_buffer_get(MirInstrRec, store.instructions, def - 1).block
    let bcount = mir_vindex_block_count(indexes, function)
    var block: U64 = 1
    while block <= bcount {
        if block == begin_block {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, block, ii)
                if iid > def {
                    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                    if x.op == mir_op_store() && x.a == begin {
                        let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
                        if part != 0 {
                            let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                            if mir_vframe_field_kind_pos(scan, frame_index, pos) == mir_vframe_field_scope() {
                                return MirVFrameAnchor(pos: pos, block: block, instruction: iid)
                            }
                        }
                    }
                }
                ii = ii + 1
            }
        }
        block = block + 1
    }
    return result
}

fn mir_vframe_begin_has_scope_store(store: MirStore, indexes: MirVIndexes, function: U64, scan: MirVFrameScan, frame_index: U64, frame_param: U64, begin: U64) -> Bool {
    let bcount = mir_vindex_block_count(indexes, function)
    var block: U64 = 1
    while block <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, block)
        var ii: U64 = 0
        while ii < icount {
            let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, block, ii) - 1)
            if x.op == mir_op_store() && x.a == begin {
                let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
                if part != 0 {
                    let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                    if mir_vframe_field_kind_pos(scan, frame_index, pos) == mir_vframe_field_scope() { return true }
                }
            }
            ii = ii + 1
        }
        block = block + 1
    }
    return false
}

// A cleanup scope operand is either an anchored begin or a load from s<i>.
fn mir_vframe_scope_value_anchor(store: MirStore, indexes: MirVIndexes, function: U64, scan: MirVFrameScan, frame_index: U64, frame_param: U64, value: U64) -> U64 {
    let iid = mir_vframe_def_instr(store, indexes, function, value)
    if iid == 0 { return 0 }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op == mir_op_cleanup_scope_begin() {
        return mir_vframe_begin_anchor(store, indexes, function, scan, frame_index, frame_param, x.result).pos
    }
    if x.op == mir_op_load() {
        let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
        if part != 0 {
            let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
            if mir_vframe_field_kind_pos(scan, frame_index, pos) == mir_vframe_field_scope() { return pos }
        }
    }
    return 0
}

// True when every path from entry to b crosses a. The anchor block may not be
// skipped on the way to a use of the scope handle.
fn mir_vframe_block_dominates(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, a: U64, b: U64) -> Result(Bool, __s0_Error) {
    if a == 0 || b == 0 { return Ok(false) }
    if a == b { return Ok(true) }
    let bcount = mir_vindex_block_count(indexes, function)
    var visited = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at <= bcount { visited = try __s0_buffer_append(U64, d, visited, 0)
        at = at + 1 }
    var queue = try __s0_buffer_new(U64, d)
    queue = try __s0_buffer_append(U64, d, queue, 1)
    __s0_buffer_set(U64, visited, 1, 1)
    var q: U64 = 0
    while q < __s0_buffer_len(U64, queue) {
        let block = __s0_buffer_get(U64, queue, q)
        q = q + 1
        var target: U64 = 1
        while target <= bcount {
            if target != a && __s0_buffer_get(U64, visited, target) == 0 && mir_vframe_edge(store, indexes, function, block, target) != 0 {
                if target == b { return Ok(false) }
                __s0_buffer_set(U64, visited, target, 1)
                queue = try __s0_buffer_append(U64, d, queue, target)
            }
            target = target + 1
        }
    }
    return Ok(true)
}

fn mir_vframe_anchor_precedes(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, anchor: MirVFrameAnchor, use_block: U64, use_iid: U64) -> Result(Bool, __s0_Error) {
    if anchor.pos == 0 { return Ok(false) }
    if anchor.block == use_block { return Ok(anchor.instruction < use_iid) }
    return mir_vframe_block_dominates(d, store, indexes, function, anchor.block, use_block)
}

// The first begin on the canonical resume path. A resume check follows its
// non-cancellation edge; other dispatch targets stop the walk.
fn mir_vframe_first_begin(store: MirStore, indexes: MirVIndexes, function: U64, target: U64) -> U64 {
    var current = target
    var steps: U64 = 0
    let bcount = mir_vindex_block_count(indexes, function)
    while current != 0 && current <= bcount && steps <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, current)
        var ii: U64 = 0
        while ii < icount {
            let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, current, ii) - 1)
            if x.op == mir_op_cleanup_scope_begin() && x.result != 0 { return x.result }
            ii = ii + 1
        }
        let term_id = mir_vindex_term(indexes, function, current)
        if term_id == 0 { return 0 }
        let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
        if t.kind == mir_term_jump() && mir_vframe_pred_count(store, indexes, function, t.target) == 1 { current = t.target } else {
            if t.kind == mir_term_branch() && mir_vframe_cancel_cond(store, indexes, function, t.value) && mir_vframe_pred_count(store, indexes, function, t.else_block) == 1 && t.else_block != 1 { current = t.else_block } else { current = 0 }
        }
        steps = steps + 1
    }
    return 0
}

fn mir_vframe_state_suspend_block(store: MirStore, indexes: MirVIndexes, function: U64, state_type: U64, frame_param: U64, variant: U64) -> U64 {
    let bcount = mir_vindex_block_count(indexes, function)
    var block: U64 = 2
    while block <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, block)
        var ii: U64 = 0
        while ii < icount {
            let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, block, ii) - 1)
            if x.op == mir_op_store() {
                let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
                if part != 0 && mir_vframe_field_part_word(store, part, "state") && mir_vframe_state_store_variant(store, indexes, function, state_type, x.a) == variant { return block }
            }
            ii = ii + 1
        }
        block = block + 1
    }
    return 0
}

fn mir_vframe_state_saves_scope(store: MirStore, indexes: MirVIndexes, function: U64, frame_param: U64, block: U64, scope_pos: U64, scan: MirVFrameScan, frame_index: U64) -> Bool {
    let icount = mir_vindex_instr_count(indexes, function, block)
    var state_iid: U64 = 0
    var ii: U64 = 0
    while ii < icount {
        let iid = mir_vindex_instr(indexes, function, block, ii)
        let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
        let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
        if x.op == mir_op_store() && part != 0 && mir_vframe_field_part_word(store, part, "state") { state_iid = iid }
        ii = ii + 1
    }
    if state_iid == 0 { return false }
    ii = 0
    while ii < icount {
        let iid = mir_vindex_instr(indexes, function, block, ii)
        if iid > state_iid {
            let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
            if x.op == mir_op_store() {
                let part = mir_vframe_field_part_of(store, indexes, function, x.place, frame_param)
                if part != 0 && mir_vframe_field_pos_part(scan, store, frame_index, part) == scope_pos { return true }
            }
        }
        ii = ii + 1
    }
    return false
}

fn mir_vframe_phase7_anchors(d: Domain, store: MirStore, indexes: MirVIndexes, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = out0
    let scanned = try mir_vframe_scan(d, store, indexes)
    let scan = scanned.scan
    if !scan.reserved { return Ok(out) }
    var si: U64 = 1
    while si <= __s0_buffer_len(MirVFrameStep, scan.steps) {
        let step = __s0_buffer_get(MirVFrameStep, scan.steps, si - 1)
        let function = step.function
        let frame_index = mir_vframe_frame_index(scan, step.frame_type)
        let frame = __s0_buffer_get(MirVFrameRec, scan.frames, frame_index - 1)
        let bcount = mir_vindex_block_count(indexes, function)
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, block, ii)
                let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if x.op == mir_op_cleanup_scope_begin() {
                    let anchor = mir_vframe_begin_anchor(store, indexes, function, scan, frame_index, step.frame_param, x.result)
                    if anchor.pos == 0 {
                        if mir_vframe_begin_has_scope_store(store, indexes, function, scan, frame_index, step.frame_param, x.result) {
                            out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), mir_vdiag_frame_scope_anchor(), function, block, iid, 0, 0, 0, function, 0, 0, 0))
                        }
                    } else {
                        var ub: U64 = 1
                        while ub <= bcount {
                            let ucount = mir_vindex_instr_count(indexes, function, ub)
                            var ui: U64 = 0
                            while ui < ucount {
                                let uid = mir_vindex_instr(indexes, function, ub, ui)
                                let use = __s0_buffer_get(MirInstrRec, store.instructions, uid - 1)
                                if (use.op == mir_op_cleanup_push() || use.op == mir_op_cleanup_scope_run() || use.op == mir_op_cleanup_scope_end()) && use.a == x.result {
                                    if !try mir_vframe_anchor_precedes(d, store, indexes, function, anchor, ub, uid) {
                                        out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), mir_vdiag_frame_scope_anchor(), function, ub, uid, 0, 0, 0, function, 0, 0, 0))
                                    }
                                }
                                ui = ui + 1
                            }
                            ub = ub + 1
                        }
                    }
                }
                if x.op == mir_op_cleanup_push() || x.op == mir_op_cleanup_scope_run() || x.op == mir_op_cleanup_scope_end() {
                    if mir_vframe_scope_value_anchor(store, indexes, function, scan, frame_index, step.frame_param, x.a) == 0 {
                        let def = mir_vframe_def_instr(store, indexes, function, x.a)
                        var local_begin = false
                        if def != 0 { let dref = __s0_buffer_get(MirInstrRec, store.instructions, def - 1)
                            if dref.op == mir_op_cleanup_scope_begin() { local_begin = true } }
                        if !local_begin { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), mir_vdiag_frame_scope_anchor(), function, block, iid, 0, 0, 0, function, 0, 0, 0)) }
                    }
                }
                ii = ii + 1
            }
            block = block + 1
        }
        let vc = mir_vframe_state_variant_count(store, indexes, step.state_type)
        let term_id = mir_vindex_term(indexes, function, 1)
        var variant: U64 = 2
        while variant <= vc {
            let suspend = mir_vframe_state_suspend_block(store, indexes, function, step.state_type, step.frame_param, variant)
            if suspend != 0 {
                var saved_scope = false
                var pos: U64 = 1
                while pos <= frame.field_count {
                    if mir_vframe_field_kind_pos(scan, frame_index, pos) == mir_vframe_field_scope() && mir_vframe_state_saves_scope(store, indexes, function, step.frame_param, suspend, pos, scan, frame_index) { saved_scope = true }
                    pos = pos + 1
                }
                if saved_scope {
                    let target = mir_vframe_state_target(store, indexes, function, step.state_type, term_id, variant)
                    if target != 0 {
                        let first = mir_vframe_first_begin(store, indexes, function, target)
                        var ok = false
                        if first != 0 {
                            let anchor = mir_vframe_begin_anchor(store, indexes, function, scan, frame_index, step.frame_param, first)
                            if anchor.pos != 0 && mir_vframe_state_saves_scope(store, indexes, function, step.frame_param, suspend, anchor.pos, scan, frame_index) { ok = true }
                        }
                        if !ok { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), mir_vdiag_frame_scope_anchor(), function, target, 0, 0, 0, 0, function, 0, 0, variant)) }
                    }
                }
            }
            variant = variant + 1
        }
        si = si + 1
    }
    return Ok(out)
}

fn mir_vframe_cleanup_scope_resident(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, scope: U64) -> Result(Bool, __s0_Error) {
    let scanned = try mir_vframe_scan(d, store, indexes)
    let scan = scanned.scan
    let step_index = mir_vframe_step_for(scan, function)
    if step_index == 0 { return Ok(false) }
    let step = __s0_buffer_get(MirVFrameStep, scan.steps, step_index - 1)
    let frame_index = mir_vframe_frame_index(scan, step.frame_type)
    return Ok(mir_vframe_scope_value_anchor(store, indexes, function, scan, frame_index, step.frame_param, scope) != 0)
}

fn mir_vframe_suspend_return(store: MirStore, indexes: MirVIndexes, function: U64, block: U64) -> Bool {
    if !mir_vframe_function_is_step(store, function) { return false }
    let status = mir_vframe_status_type(store)
    if status == 0 { return false }
    let term_id = mir_vindex_term(indexes, function, block)
    if term_id == 0 { return false }
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if t.kind != mir_term_return() || t.value == 0 { return false }
    let ordinal = mir_vframe_status_ordinal(store, indexes, function, status, t.value)
    return ordinal == 2 || ordinal == 3
}

fn mir_vframe_reaches(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, from: U64, to: U64) -> Result(Bool, __s0_Error) {
    if from == to { return Ok(true) }
    let bcount = mir_vindex_block_count(indexes, function)
    var visited = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at <= bcount { visited = try __s0_buffer_append(U64, d, visited, 0)
        at = at + 1 }
    var queue = try __s0_buffer_new(U64, d)
    queue = try __s0_buffer_append(U64, d, queue, from)
    __s0_buffer_set(U64, visited, from, 1)
    var q: U64 = 0
    while q < __s0_buffer_len(U64, queue) { let block = __s0_buffer_get(U64, queue, q)
        q = q + 1
        var target: U64 = 1
        while target <= bcount { if __s0_buffer_get(U64, visited, target) == 0 && mir_vframe_edge(store, indexes, function, block, target) != 0 { if target == to { return Ok(true) }
                __s0_buffer_set(U64, visited, target, 1)
                queue = try __s0_buffer_append(U64, d, queue, target) }
            target = target + 1 } }
    return Ok(false)
}

// Phase 7 frame cleanup rules: a registration saved into c<i> must name a
// frame field as its push place, and a frame cleanup id is disarmed at most
// once on any path.
fn mir_vframe_phase7(d: Domain, store: MirStore, indexes: MirVIndexes, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = out0
    let scanned = try mir_vframe_scan(d, store, indexes)
    let scan = scanned.scan
    if !scan.reserved { return Ok(out) }
    out = try mir_vframe_phase7_anchors(d, store, indexes, out)
    var si: U64 = 1
    while si <= __s0_buffer_len(MirVFrameStep, scan.steps) {
        let step = __s0_buffer_get(MirVFrameStep, scan.steps, si - 1)
        let function = step.function
        let frame_index = mir_vframe_frame_index(scan, step.frame_type)
        var block: U64 = 1
        let bcount = mir_vindex_block_count(indexes, function)
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ii: U64 = 0
            while ii < icount { let iid = mir_vindex_instr(indexes, function, block, ii)
                let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                // A push result stored into c<i> spans a state.
                if x.op == mir_op_store() { let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                    if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                        if mir_vframe_field_kind_pos(scan, frame_index, pos) == mir_vframe_field_cleanup() { let push_id = mir_vframe_def_instr(store, indexes, function, x.a)
                            var ok = false
                            if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
                                if push.op == mir_op_cleanup_push() && mir_vframe_place_frame_field(store, indexes, function, push.place) { ok = true } }
                            if !ok { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), mir_vdiag_frame_cleanup_place(), function, block, iid, 0, x.place, 0, function, 0, 0, 0)) } } } }
                // A frame cleanup id is disarmed at most once per path.
                if x.op == mir_op_load() { let part = mir_vframe_field_part_of(store, indexes, function, x.place, step.frame_param)
                    if part != 0 { let pos = mir_vframe_field_pos_part(scan, store, frame_index, part)
                        if mir_vframe_field_kind_pos(scan, frame_index, pos) == mir_vframe_field_cleanup() {
                            var sites = try __s0_buffer_new(U64, d)
                            var b2: U64 = 1
                            while b2 <= bcount { let c2 = mir_vindex_instr_count(indexes, function, b2)
                                var j2: U64 = 0
                                while j2 < c2 { let y = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, b2, j2) - 1)
                                    if y.op == mir_op_cleanup_disarm() && y.a == x.result { sites = try __s0_buffer_append(U64, d, sites, b2) }
                                    j2 = j2 + 1 }
                                b2 = b2 + 1 }
                            var a2: U64 = 0
                            var bad = false
                            while a2 < __s0_buffer_len(U64, sites) { var c3 = a2 + 1
                                while c3 < __s0_buffer_len(U64, sites) { if try mir_vframe_reaches(d, store, indexes, function, __s0_buffer_get(U64, sites, a2), __s0_buffer_get(U64, sites, c3)) || try mir_vframe_reaches(d, store, indexes, function, __s0_buffer_get(U64, sites, c3), __s0_buffer_get(U64, sites, a2)) { bad = true }
                                    c3 = c3 + 1 }
                                a2 = a2 + 1 }
                            if bad { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), mir_vdiag_frame_cleanup_disarm(), function, block, iid, 0, x.place, 0, function, 0, 0, 0)) }
                        } } }
                ii = ii + 1
            }
            block = block + 1
        }
        si = si + 1
    }
    return Ok(out)
}

fn mir_vframe_const_one(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Bool {
    let iid = mir_vframe_def_instr(store, indexes, function, value)
    if iid == 0 { return false }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op != mir_op_const_get() { return false }
    var at: U64 = 1
    while at <= __s0_buffer_len(MirConstRec, store.constants) { let c = __s0_buffer_get(MirConstRec, store.constants, at - 1)
        if mir_vname_equal(store, c.name_start, c.name_end, x.name_start, x.name_end) { return c.const_type == mir_type_u64() && c.kind == mir_const_int() && c.int_value == 1 }
        at = at + 1 }
    return false
}

fn mir_vframe_place_frame_field_noidx(store: MirStore, function: U64, place: U64) -> Bool {
    if place == 0 { return false }
    let rec = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if rec.kind != mir_place_field() { return false }
    let base = __s0_buffer_get(MirPlaceRec, store.places, rec.base - 1)
    if base.kind != mir_place_deref() { return false }
    let vi = mir_vvalue_index(store, function, base.deref_value)
    if vi == 0 { return false }
    let view_type = __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type
    if !mir_vframe_type_kind_is(store, view_type, mir_type_kind_safe_mut()) { return false }
    let elem = __s0_buffer_get(MirTypeRec, store.types, view_type - 1).elem
    if !mir_vframe_type_kind_is(store, elem, mir_type_kind_aggregate()) { return false }
    let t = __s0_buffer_get(MirTypeRec, store.types, elem - 1)
    return mir_vframe_prefix(store, t.name_start, t.name_end, mir_vframe_type_prefix())
}
