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
    tp_ids: __s0_Buffer(U64)
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
    ids: __s0_Buffer(U64)
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
    let ids = __s0_alloc(U64, d, total)
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
    let ids = __s0_alloc(U64, d, total)
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
    let ids = __s0_alloc(U64, d, total)
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
    let ids = __s0_alloc(U64, d, total)
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
    let ids = __s0_alloc(U64, d, itotal)
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
    let ids = __s0_alloc(U64, d, total)
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
    let iids = __s0_alloc(U64, d, total_i)
    let tids = __s0_alloc(U64, d, total_t)
    let cids = __s0_alloc(U64, d, total_c)
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
    var start = __s0_alloc(U64, d, tcount + 1)
    var z: U64 = 0
    while z <= tcount { cnt[z] = 0
        start[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < total {
        let f = __s0_buffer_get(MirTypePartRec, store.type_parts, i).owner
        if f >= 1 && f <= tcount { cnt[f] = cnt[f] + 1 }
        i = i + 1
    }
    var f: U64 = 1
    while f <= tcount { start[f] = start[f - 1] + cnt[f - 1]
        f = f + 1 }
    let ids = __s0_alloc(U64, d, total)
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
    var ids_buf = try __s0_buffer_new(U64, d)
    f = 1
    while f <= tcount {
        start_buf = try __s0_buffer_append(U64, d, start_buf, start[f])
        count_buf = try __s0_buffer_append(U64, d, count_buf, cnt[f])
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
    return Ok(MirVIndexTypePartsRec(start: start_buf, count: count_buf, ids: ids_buf))
}

fn mir_vindex_build(d: Domain, store: MirStore) -> Result(MirVIndexes, __s0_Error) {
    let blocks = try mir_vindex_build_blocks(d, store)
    let values = try mir_vindex_build_values(d, store)
    let locals = try mir_vindex_build_locals(d, store)
    let terms = try mir_vindex_build_terms(d, store)
    let instrs = try mir_vindex_build_instrs(d, store, blocks)
    let params = try mir_vindex_build_params(d, store)
    let ops = try mir_vindex_build_ops(d, store)
    let tps = try mir_vindex_build_type_parts(d, store)
    return Ok(MirVIndexes(block_pos: blocks.pos, block_span: blocks.span, value_pos: values.pos, value_span: values.span, local_pos: locals.pos, local_span: locals.span, term_pos: terms.pos, term_span: terms.span, block_count: blocks.count, value_count: values.count, local_count: locals.count, instr_span: instrs.span, instr_count: instrs.count, instr_off: instrs.off, instr_ids: instrs.ids, param_span: params.span, param_ids: params.ids, op_instr_start: ops.instr_start, op_instr_count: ops.instr_count, op_instr_ids: ops.instr_ids, op_term_start: ops.term_start, op_term_count: ops.term_count, op_term_ids: ops.term_ids, op_case_start: ops.case_start, op_case_count: ops.case_count, op_case_ids: ops.case_ids, tp_start: tps.start, tp_count: tps.count, tp_ids: tps.ids))
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

fn mir_vp4_cfg_empty(d: Domain, function: U64) -> Result(MirVP4PointCfg, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    return Ok(MirVP4PointCfg(function: function, block_count: 0, node_count: 0, boundary_count: 0, entry: 0, boundary_offset: empty, block_instr_count: empty, succ: empty, succ_start: empty, succ_count: empty, pred: empty, pred_start: empty, pred_count: empty, case_edge: empty))
}

fn mir_vp4_cfg_build(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(MirVP4PointCfg, __s0_Error) {
    let block_count = mir_vindex_block_count(indexes, function)
    if block_count == 0 { return mir_vp4_cfg_empty(d, function) }
    var boundary_offset = try __s0_buffer_new(U64, d)
    var block_instr_count = try __s0_buffer_new(U64, d)
    var offset: U64 = 1
    var b: U64 = 1
    while b <= block_count {
        let count = mir_vindex_instr_count(indexes, function, b)
        boundary_offset = try __s0_buffer_append(U64, d, boundary_offset, offset)
        block_instr_count = try __s0_buffer_append(U64, d, block_instr_count, count)
        offset = offset + count + 1
        b = b + 1
    }
    let boundary_count = offset - 1
    var edge_from = try __s0_buffer_new(U64, d)
    var edge_to = try __s0_buffer_new(U64, d)
    // case_edge[block - 1] = 1-based index of the block's first switch-case
    // edge node, or 0 when the block has no switch with valid cases. Built in
    // a local array and emitted once at the end.
    var case_edge_arr = __s0_alloc(U64, d, block_count)
    var z: U64 = 0
    while z < block_count { case_edge_arr[z] = 0
        z = z + 1 }
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
                    edge_from = try __s0_buffer_append(U64, d, edge_from, base + p)
                    edge_to = try __s0_buffer_append(U64, d, edge_to, ins.target)
                }
            }
            p = p + 1
        }
        let term_id = mir_vindex_term(indexes, function, b)
        if term_id != 0 {
            let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
            if t.kind == mir_term_jump() && mir_vindex_block(indexes, function, t.target) != 0 {
                edge_from = try __s0_buffer_append(U64, d, edge_from, base + count)
                edge_to = try __s0_buffer_append(U64, d, edge_to, t.target)
            }
            if t.kind == mir_term_branch() {
                if mir_vindex_block(indexes, function, t.then_block) != 0 {
                    edge_from = try __s0_buffer_append(U64, d, edge_from, base + count)
                    edge_to = try __s0_buffer_append(U64, d, edge_to, t.then_block)
                }
                if mir_vindex_block(indexes, function, t.else_block) != 0 {
                    edge_from = try __s0_buffer_append(U64, d, edge_from, base + count)
                    edge_to = try __s0_buffer_append(U64, d, edge_to, t.else_block)
                }
            }
            if t.kind == mir_term_switch() {
                let first_case = __s0_buffer_len(U64, edge_from)
                // Switch cases are the switch_case-kind operands of this
                // terminator in ascending operand-id order, which on a
                // validated store is their ordinal order.
                let ccount = mir_vindex_op_term_count(indexes, term_id)
                var at: U64 = 0
                while at < ccount {
                    let case_id = mir_vindex_op_term(indexes, term_id, at)
                    let c = __s0_buffer_get(MirOperandRec, store.operands, case_id - 1)
                    if c.kind == mir_operand_switch_case() && mir_vindex_block(indexes, function, c.target) != 0 {
                        edge_from = try __s0_buffer_append(U64, d, edge_from, base + count)
                        edge_to = try __s0_buffer_append(U64, d, edge_to, c.target)
                    }
                    at = at + 1
                }
                if __s0_buffer_len(U64, edge_from) > first_case {
                    case_edge_arr[b - 1] = first_case + 1
                }
            }
        }
        b = b + 1
    }
    let edge_count = __s0_buffer_len(U64, edge_from)
    let node_count = boundary_count + edge_count
    if node_count == 0 { return mir_vp4_cfg_empty(d, function) }
    var succ = try __s0_buffer_new(U64, d)
    var succ_start = try __s0_buffer_new(U64, d)
    var succ_count = try __s0_buffer_new(U64, d)
    // Boundary nodes ascending: a linear successor n + 1 unless n is the
    // terminator position of its block, plus the edge nodes whose edge_from
    // equals n. edge_from is non-decreasing, so a cursor replaces the per-node
    // full scans.
    var bb: U64 = 1
    var e: U64 = 0
    var n: U64 = 1
    while n <= boundary_count {
        let start = __s0_buffer_len(U64, succ)
        while bb < block_count && n > __s0_buffer_get(U64, boundary_offset, bb - 1) + __s0_buffer_get(U64, block_instr_count, bb - 1) { bb = bb + 1 }
        if n != __s0_buffer_get(U64, boundary_offset, bb - 1) + __s0_buffer_get(U64, block_instr_count, bb - 1) {
            succ = try __s0_buffer_append(U64, d, succ, n + 1)
        }
        while e < edge_count && __s0_buffer_get(U64, edge_from, e) < n { e = e + 1 }
        while e < edge_count && __s0_buffer_get(U64, edge_from, e) == n {
            succ = try __s0_buffer_append(U64, d, succ, boundary_count + 1 + e)
            e = e + 1
        }
        succ_start = try __s0_buffer_append(U64, d, succ_start, start)
        succ_count = try __s0_buffer_append(U64, d, succ_count, __s0_buffer_len(U64, succ) - start)
        n = n + 1
    }
    n = 1
    while n <= edge_count {
        let start = __s0_buffer_len(U64, succ)
        let target = __s0_buffer_get(U64, edge_to, n - 1)
        succ = try __s0_buffer_append(U64, d, succ, __s0_buffer_get(U64, boundary_offset, target - 1))
        succ_start = try __s0_buffer_append(U64, d, succ_start, start)
        succ_count = try __s0_buffer_append(U64, d, succ_count, 1)
        n = n + 1
    }
    // Pred lists: a non-entry boundary node n > 1 has the single linear pred
    // n - 1; a block-entry boundary node has exactly the edge nodes whose
    // edge_to is that block (built by counting-sorting edges by target); an
    // edge node boundary_count + e has the single pred edge_from[e]. This is
    // the exact inverse of the succ lists above, with preds in ascending
    // source order like the old per-node scan.
    var pred = try __s0_buffer_new(U64, d)
    var pred_start = try __s0_buffer_new(U64, d)
    var pred_count = try __s0_buffer_new(U64, d)
    var edge_cnt = __s0_alloc(U64, d, block_count + 1)
    var edge_base = __s0_alloc(U64, d, block_count + 1)
    z = 0
    while z <= block_count { edge_cnt[z] = 0
        edge_base[z] = 0
        z = z + 1 }
    var e2: U64 = 0
    while e2 < edge_count {
        let target = __s0_buffer_get(U64, edge_to, e2)
        edge_cnt[target] = edge_cnt[target] + 1
        e2 = e2 + 1
    }
    var blk: U64 = 1
    while blk <= block_count { edge_base[blk] = edge_base[blk - 1] + edge_cnt[blk - 1]
        blk = blk + 1 }
    let edge_ids = __s0_alloc(U64, d, edge_count)
    var edge_used = __s0_alloc(U64, d, block_count + 1)
    z = 0
    while z < edge_count { edge_ids[z] = 0
        z = z + 1 }
    z = 0
    while z <= block_count { edge_used[z] = 0
        z = z + 1 }
    e2 = 0
    while e2 < edge_count {
        let target = __s0_buffer_get(U64, edge_to, e2)
        let pos = edge_base[target] + edge_used[target]
        edge_ids[pos] = e2 + 1
        edge_used[target] = edge_used[target] + 1
        e2 = e2 + 1
    }
    bb = 1
    n = 1
    while n <= boundary_count {
        let start = __s0_buffer_len(U64, pred)
        while bb < block_count && n > __s0_buffer_get(U64, boundary_offset, bb - 1) + __s0_buffer_get(U64, block_instr_count, bb - 1) { bb = bb + 1 }
        let offb = __s0_buffer_get(U64, boundary_offset, bb - 1)
        if n > 1 && n != offb { pred = try __s0_buffer_append(U64, d, pred, n - 1) }
        if n == offb {
            var k: U64 = 0
            while k < edge_cnt[bb] {
                let eid = edge_ids[edge_base[bb] + k]
                pred = try __s0_buffer_append(U64, d, pred, boundary_count + eid)
                k = k + 1
            }
        }
        pred_start = try __s0_buffer_append(U64, d, pred_start, start)
        pred_count = try __s0_buffer_append(U64, d, pred_count, __s0_buffer_len(U64, pred) - start)
        n = n + 1
    }
    e2 = 0
    while e2 < edge_count {
        let start = __s0_buffer_len(U64, pred)
        pred = try __s0_buffer_append(U64, d, pred, __s0_buffer_get(U64, edge_from, e2))
        pred_start = try __s0_buffer_append(U64, d, pred_start, start)
        pred_count = try __s0_buffer_append(U64, d, pred_count, __s0_buffer_len(U64, pred) - start)
        e2 = e2 + 1
    }
    var case_edge = try __s0_buffer_new(U64, d)
    var ci: U64 = 0
    while ci < block_count {
        case_edge = try __s0_buffer_append(U64, d, case_edge, case_edge_arr[ci])
        ci = ci + 1
    }
    return Ok(MirVP4PointCfg(function: function, block_count: block_count, node_count: node_count, boundary_count: boundary_count, entry: 1, boundary_offset: boundary_offset, block_instr_count: block_instr_count, succ: succ, succ_start: succ_start, succ_count: succ_count, pred: pred, pred_start: pred_start, pred_count: pred_count, case_edge: case_edge))
}

type MirVP4Dom {
    idom: __s0_Buffer(U64)
    rpo_index: __s0_Buffer(U64)
    dom_in: __s0_Buffer(U64)
    dom_out: __s0_Buffer(U64)
}

fn mir_vp4_dom_empty(d: Domain) -> Result(MirVP4Dom, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    return Ok(MirVP4Dom(idom: empty, rpo_index: empty, dom_in: empty, dom_out: empty))
}

fn mir_vp4_u64_at(buf: __s0_Buffer(U64), index: U64) -> U64 {
    if index == 0 || index > __s0_buffer_len(U64, buf) { return 0 }
    return __s0_buffer_get(U64, buf, index - 1)
}

fn mir_vp4_dom_build(d: Domain, cfg: MirVP4PointCfg) -> Result(MirVP4Dom, __s0_Error) {
    let n = cfg.node_count
    let entry = cfg.entry
    if n == 0 || entry == 0 || entry > n { return mir_vp4_dom_empty(d) }
    // Iterative DFS postorder over the CFG. The phase-6 domain-provenance
    // analysis forbids stores inside loops of values read back out of
    // function-local allocations, so data movement goes through append-only
    // buffers (post/rpo below) while arrays that only ever receive constants
    // or arithmetic results stay local __s0_alloc arrays (seen, phase, stack,
    // rpo_index, idom, ...). The stack is an alloc array indexed by a logical
    // top (an append-only buffer would read stale entries after pops). The
    // visited probe is a direct O(1) array check instead of the old linear
    // scan.
    var seen = __s0_alloc(U64, d, n + 1)
    var phase = __s0_alloc(U64, d, n + 1)
    var stack = __s0_alloc(U64, d, n + 1)
    var z: U64 = 0
    while z <= n { seen[z] = 0
        phase[z] = 0
        stack[z] = 0
        z = z + 1 }
    var post = try __s0_buffer_new(U64, d)
    stack[0] = entry
    phase[0] = 0
    seen[entry] = 1
    var top: U64 = 1
    var plen: U64 = 0
    while top != 0 {
        let v = stack[top - 1]
        if phase[top - 1] == 0 {
            phase[top - 1] = 1
            let base = mir_vp4_u64_at(cfg.succ_start, v)
            let count = mir_vp4_u64_at(cfg.succ_count, v)
            var k: U64 = 0
            while k < count {
                let s = __s0_buffer_get(U64, cfg.succ, base + k)
                if s != 0 && seen[s] == 0 {
                    seen[s] = 1
                    stack[top] = s
                    phase[top] = 0
                    top = top + 1
                }
                k = k + 1
            }
        } else {
            post = try __s0_buffer_append(U64, d, post, v)
            plen = plen + 1
            top = top - 1
        }
    }
    // rpo is the reverse postorder; rpo_index maps a node to its 1-based rpo
    // position. All alloc stores below are constants or arithmetic results.
    var rpo = try __s0_buffer_new(U64, d)
    var rpo_index = __s0_alloc(U64, d, n + 1)
    z = 0
    while z <= n { rpo_index[z] = 0
        z = z + 1 }
    var i: U64 = 0
    while i < plen {
        rpo = try __s0_buffer_append(U64, d, rpo, __s0_buffer_get(U64, post, plen - 1 - i))
        i = i + 1
    }
    i = 0
    while i < plen {
        rpo_index[__s0_buffer_get(U64, rpo, i)] = i + 1
        i = i + 1
    }
    // idom fixpoint: identical iteration order and semantics to the buffer
    // version, with O(1) element writes. The stored value is an arithmetic
    // identity (new_idom + 0) because the intersect walk reads idom entries
    // back out of the local allocation, which phase 6 treats as a reference.
    var idom = __s0_alloc(U64, d, n + 1)
    z = 0
    while z <= n { idom[z] = 0
        z = z + 1 }
    idom[entry] = entry
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
                if idom[p] != 0 {
                    if new_idom == 0 {
                        new_idom = p
                    } else {
                        // CHK intersect of p and new_idom, inlined because the
                        // alloc arrays cannot cross a function boundary.
                        var x = p
                        var y = new_idom
                        var done = false
                        while !done && x != y {
                            if x == 0 || y == 0 {
                                x = 0
                                done = true
                            } else {
                                let xi = rpo_index[x]
                                let yi = rpo_index[y]
                                if xi == 0 || yi == 0 {
                                    x = 0
                                    done = true
                                } else {
                                    if xi > yi {
                                        x = idom[x]
                                    } else {
                                        y = idom[y]
                                    }
                                }
                            }
                        }
                        new_idom = x
                    }
                }
                k = k + 1
            }
            if new_idom != 0 && idom[b] != new_idom {
                idom[b] = new_idom + 0
                changed = true
            }
            i = i + 1
        }
    }
    // Children lists from idom, in the same 0-based layout as the old
    // child_start/child_count/children buffers. child_count is appended in
    // node order because its values are read back out of the counts
    // allocation; child_start/counts/filled only store arithmetic results.
    var counts = __s0_alloc(U64, d, n + 1)
    var child_start = __s0_alloc(U64, d, n + 1)
    var filled = __s0_alloc(U64, d, n + 1)
    z = 0
    while z <= n { counts[z] = 0
        child_start[z] = 0
        filled[z] = 0
        z = z + 1 }
    var v: U64 = 1
    while v <= n {
        let p = idom[v]
        if p != 0 && p != v { counts[p] = counts[p] + 1 }
        v = v + 1
    }
    var child_count = try __s0_buffer_new(U64, d)
    var start: U64 = 0
    v = 1
    while v <= n {
        child_start[v] = start
        let count = counts[v]
        child_count = try __s0_buffer_append(U64, d, child_count, count)
        start = start + count
        v = v + 1
    }
    let children = __s0_alloc(U64, d, start)
    z = 0
    while z < start { children[z] = 0
        z = z + 1 }
    v = 1
    while v <= n {
        let p = idom[v]
        if p != 0 && p != v {
            let used = filled[p]
            children[child_start[p] + used] = v
            filled[p] = used + 1
        }
        v = v + 1
    }
    // Euler tour over the idom tree: dom_in is the preorder stamp, dom_out
    // the stamp at subtree exit. Same traversal order and stamps as the old
    // buffers; dom_in is written at entry time (identical value). Children
    // are pushed onto the estack alloc array through an arithmetic identity
    // (c + 0) because they are read back out of the children allocation,
    // which phase 6 treats as a reference; the edata phases hold only the
    // current stamp and constants.
    var dom_in = __s0_alloc(U64, d, n + 1)
    var dom_out = __s0_alloc(U64, d, n + 1)
    var estack = __s0_alloc(U64, d, n + 1)
    var edata = __s0_alloc(U64, d, n + 1)
    z = 0
    while z <= n { dom_in[z] = 0
        dom_out[z] = 0
        estack[z] = 0
        edata[z] = 0
        z = z + 1 }
    estack[0] = entry
    edata[0] = 0
    var stamp: U64 = 0
    var etop: U64 = 1
    while etop != 0 {
        let v2 = estack[etop - 1]
        let data = edata[etop - 1]
        if data == 0 {
            stamp = stamp + 1
            edata[etop - 1] = stamp
            dom_in[v2] = stamp
            let base = child_start[v2]
            let count = __s0_buffer_get(U64, child_count, v2 - 1)
            var k: U64 = 0
            while k < count {
                let c = children[base + k]
                if c != 0 {
                    estack[etop] = c + 0
                    edata[etop] = 0
                    etop = etop + 1
                }
                k = k + 1
            }
        } else {
            dom_out[v2] = stamp
            etop = etop - 1
        }
    }
    // Emit the arrays as buffers so MirVP4Dom keeps its buffer field types.
    var idom_buf = try __s0_buffer_new(U64, d)
    var rpo_index_buf = try __s0_buffer_new(U64, d)
    var dom_in_buf = try __s0_buffer_new(U64, d)
    var dom_out_buf = try __s0_buffer_new(U64, d)
    var i2: U64 = 1
    while i2 <= n {
        idom_buf = try __s0_buffer_append(U64, d, idom_buf, idom[i2])
        rpo_index_buf = try __s0_buffer_append(U64, d, rpo_index_buf, rpo_index[i2])
        dom_in_buf = try __s0_buffer_append(U64, d, dom_in_buf, dom_in[i2])
        dom_out_buf = try __s0_buffer_append(U64, d, dom_out_buf, dom_out[i2])
        i2 = i2 + 1
    }
    return Ok(MirVP4Dom(idom: idom_buf, rpo_index: rpo_index_buf, dom_in: dom_in_buf, dom_out: dom_out_buf))
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
