// Canonical textual MIR 5 printer for the independent flat store. Validation
// is deliberately separate from emission: malformed stores produce no partial
// MIR and are never repaired or normalized.
//
// Lookups are indexed. mir_print builds per-key group indexes once per print
// (the counting-sort pattern from checker build_use_indexes) and every scan
// helper works on its group instead of rescanning the whole table, which made
// --emit=mir quadratic in the module. A record is filed into its group
// exactly when its key has a slot, so a lookup scans the group for an
// in-range key and the table's trailing extra list for an out-of-range key;
// both reproduce the original whole-table scans exactly, including malformed
// stores with duplicate or out-of-range keys. Group coverage checks (every
// ordinal in 1..count exactly once) are equivalent to the original
// per-ordinal found==1 rescans: the group holds exactly the matching
// records, so the ordinals cover 1..count once precisely when every original
// scan found exactly one match.

type MirPrintGroup {
    first: U64
    count: U64
}

type MirPrintGrouped {
    groups: __s0_Buffer(MirPrintGroup)
    order: __s0_Buffer(U64)
    extra: __s0_Buffer(U64)
}

type MirPrintIndex {
    values: __s0_Buffer(MirPrintGroup)
    values_order: __s0_Buffer(U64)
    values_extra: __s0_Buffer(U64)
    blocks: __s0_Buffer(MirPrintGroup)
    blocks_order: __s0_Buffer(U64)
    blocks_extra: __s0_Buffer(U64)
    locals: __s0_Buffer(MirPrintGroup)
    locals_order: __s0_Buffer(U64)
    locals_extra: __s0_Buffer(U64)
    params: __s0_Buffer(MirPrintGroup)
    params_order: __s0_Buffer(U64)
    params_extra: __s0_Buffer(U64)
    block_starts: __s0_Buffer(U64)
    instr: __s0_Buffer(MirPrintGroup)
    instr_order: __s0_Buffer(U64)
    instr_extra: __s0_Buffer(U64)
    term: __s0_Buffer(MirPrintGroup)
    term_order: __s0_Buffer(U64)
    term_extra: __s0_Buffer(U64)
    operand: __s0_Buffer(MirPrintGroup)
    operand_order: __s0_Buffer(U64)
    operand_extra: __s0_Buffer(U64)
    parts: __s0_Buffer(MirPrintGroup)
    parts_order: __s0_Buffer(U64)
    parts_extra: __s0_Buffer(U64)
    seen: __s0_Buffer(U64)
}

fn mir_index_zeros(d: Domain, n: U64) -> Result(__s0_Buffer(U64), __s0_Error) {
    var buf = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < n {
        buf = try __s0_buffer_append(U64, d, buf, 0)
        at = at + 1
    }
    return Ok(buf)
}

// mir_print_group_by_slot files one table's records into groups: slots[at]
// holds the 1-based group slot of record at+1, or 0 when the record's key has
// no slot. Records land in table order inside each group, so group scans see
// the same relative order as the original whole-table scans.
fn mir_print_group_by_slot(d: Domain, slot_count: U64, slots: __s0_Buffer(U64)) -> Result(MirPrintGrouped, __s0_Error) {
    let total = __s0_buffer_len(U64, slots)
    var counts = try mir_index_zeros(d, slot_count)
    var extra_total: U64 = 0
    var at: U64 = 0
    while at < total {
        let slot = __s0_buffer_get(U64, slots, at)
        if slot >= 1 && slot <= slot_count {
            __s0_buffer_set(U64, counts, slot - 1, __s0_buffer_get(U64, counts, slot - 1) + 1)
        } else {
            extra_total = extra_total + 1
        }
        at = at + 1
    }
    var starts = try mir_index_zeros(d, slot_count + 1)
    var slot_at: U64 = 0
    while slot_at < slot_count {
        __s0_buffer_set(U64, starts, slot_at + 1, __s0_buffer_get(U64, starts, slot_at) + __s0_buffer_get(U64, counts, slot_at))
        slot_at = slot_at + 1
    }
    let in_range = __s0_buffer_get(U64, starts, slot_count)
    var order = try mir_index_zeros(d, in_range)
    var extra = try mir_index_zeros(d, extra_total)
    var cursor = try mir_index_zeros(d, slot_count)
    var extra_at: U64 = 0
    at = 0
    while at < total {
        let slot = __s0_buffer_get(U64, slots, at)
        if slot >= 1 && slot <= slot_count {
            let base = __s0_buffer_get(U64, starts, slot - 1)
            let cur = __s0_buffer_get(U64, cursor, slot - 1)
            __s0_buffer_set(U64, order, base + cur, at + 1)
            __s0_buffer_set(U64, cursor, slot - 1, cur + 1)
        } else {
            __s0_buffer_set(U64, extra, extra_at, at + 1)
            extra_at = extra_at + 1
        }
        at = at + 1
    }
    var groups = try __s0_buffer_new(MirPrintGroup, d)
    slot_at = 0
    while slot_at < slot_count {
        let base = __s0_buffer_get(U64, starts, slot_at)
        let end = __s0_buffer_get(U64, starts, slot_at + 1)
        var first: U64 = 0
        if end > base { first = base + 1 }
        groups = try __s0_buffer_append(MirPrintGroup, d, groups, MirPrintGroup(first: first, count: end - base))
        slot_at = slot_at + 1
    }
    return Ok(MirPrintGrouped(groups: groups, order: order, extra: extra))
}

// Slot helpers. Each returns the 1-based slot for an in-range key and 0 when
// the record must be filed into the extra list instead.
fn mir_print_param_slot(store: MirStore, function: U64, kind: U64) -> U64 {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        if kind == mir_param_function() { return (function - 1) * 2 + 1 }
        if kind == mir_param_block() { return (function - 1) * 2 + 2 }
    }
    return 0
}

fn mir_print_operand_slot(store: MirStore, kind: U64, owner: U64) -> U64 {
    let types = __s0_buffer_len(MirTypeRec, store.types)
    let imports = __s0_buffer_len(MirImportRec, store.imports)
    let instrs = __s0_buffer_len(MirInstrRec, store.instructions)
    let terms = __s0_buffer_len(MirTermRec, store.terminators)
    let ops = __s0_buffer_len(MirOperandRec, store.operands)
    if kind == mir_operand_type_part() {
        if owner >= 1 && owner <= types { return owner }
        return 0
    }
    if kind == mir_operand_import_param() {
        if owner >= 1 && owner <= imports { return types + owner }
        return 0
    }
    if kind == mir_operand_instruction() || kind == mir_operand_checked_edge_arg() || kind == mir_operand_aggregate_field() {
        var offset: U64 = 0
        if kind == mir_operand_checked_edge_arg() { offset = 1 }
        if kind == mir_operand_aggregate_field() { offset = 2 }
        if owner >= 1 && owner <= instrs { return types + imports + offset * instrs + owner }
        return 0
    }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() {
        var offset: U64 = 0
        if kind == mir_operand_switch_case() { offset = 1 }
        if owner >= 1 && owner <= terms { return types + imports + instrs * 3 + offset * terms + owner }
        return 0
    }
    if kind == mir_operand_switch_case_arg() {
        if owner >= 1 && owner <= ops { return types + imports + instrs * 3 + terms * 2 + owner }
        return 0
    }
    let base = types + imports + instrs * 3 + terms * 2 + ops
    if kind == mir_operand_binding_param() {
        let bf = __s0_buffer_len(MirBindingFnRec, store.binding_funcs)
        if owner >= 1 && owner <= bf { return base + owner }
        return 0
    }
    if kind == mir_operand_binding_type() {
        let bc = __s0_buffer_len(MirBindingRec, store.bindings)
        if owner >= 1 && owner <= bc { return base + __s0_buffer_len(MirBindingFnRec, store.binding_funcs) + owner }
        return 0
    }
    return 0
}

// Two-level index for instructions and terminators: a per-function prefix
// over the block table reserves one slot range per function's blocks, so a
// (function, block) key addresses its slot directly. block_starts has fc+1
// entries; block_starts[function] - block_starts[function - 1] is the number
// of block records the function owns.
fn mir_print_block_slot_total(d: Domain, fc: U64, store: MirStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    var counts = try mir_index_zeros(d, fc)
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let owner = __s0_buffer_get(MirBlockRec, store.blocks, at).function
        if owner >= 1 && owner <= fc {
            __s0_buffer_set(U64, counts, owner - 1, __s0_buffer_get(U64, counts, owner - 1) + 1)
        }
        at = at + 1
    }
    var starts = try mir_index_zeros(d, fc + 1)
    var fn_at: U64 = 0
    while fn_at < fc {
        __s0_buffer_set(U64, starts, fn_at + 1, __s0_buffer_get(U64, starts, fn_at) + __s0_buffer_get(U64, counts, fn_at))
        fn_at = fn_at + 1
    }
    return Ok(starts)
}

fn mir_print_block_span(idx: MirPrintIndex, function: U64) -> U64 {
    return __s0_buffer_get(U64, idx.block_starts, function) - __s0_buffer_get(U64, idx.block_starts, function - 1)
}

fn mir_print_index_build(d: Domain, store: MirStore) -> Result(MirPrintIndex, __s0_Error) {
    let fc = __s0_buffer_len(MirFunctionRec, store.functions)
    let value_total = __s0_buffer_len(MirValueRec, store.values)
    let block_total = __s0_buffer_len(MirBlockRec, store.blocks)
    let local_total = __s0_buffer_len(MirLocalRec, store.locals)
    let param_total = __s0_buffer_len(MirParamRec, store.params)
    let instr_total = __s0_buffer_len(MirInstrRec, store.instructions)
    let term_total = __s0_buffer_len(MirTermRec, store.terminators)
    let operand_total = __s0_buffer_len(MirOperandRec, store.operands)
    let part_total = __s0_buffer_len(MirTypePartRec, store.type_parts)
    var slots = try mir_index_zeros(d, value_total)
    var at: U64 = 0
    while at < value_total {
        __s0_buffer_set(U64, slots, at, __s0_buffer_get(MirValueRec, store.values, at).function)
        at = at + 1
    }
    let values = try mir_print_group_by_slot(d, fc, slots)
    slots = try mir_index_zeros(d, block_total)
    at = 0
    while at < block_total {
        __s0_buffer_set(U64, slots, at, __s0_buffer_get(MirBlockRec, store.blocks, at).function)
        at = at + 1
    }
    let blocks = try mir_print_group_by_slot(d, fc, slots)
    slots = try mir_index_zeros(d, local_total)
    at = 0
    while at < local_total {
        __s0_buffer_set(U64, slots, at, __s0_buffer_get(MirLocalRec, store.locals, at).function)
        at = at + 1
    }
    let locals = try mir_print_group_by_slot(d, fc, slots)
    slots = try mir_index_zeros(d, param_total)
    at = 0
    while at < param_total {
        let rec = __s0_buffer_get(MirParamRec, store.params, at)
        __s0_buffer_set(U64, slots, at, mir_print_param_slot(store, rec.function, rec.kind))
        at = at + 1
    }
    let params = try mir_print_group_by_slot(d, fc * 2, slots)
    let block_starts = try mir_print_block_slot_total(d, fc, store)
    slots = try mir_index_zeros(d, instr_total)
    at = 0
    while at < instr_total {
        var slot: U64 = 0
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if rec.function >= 1 && rec.function <= fc {
            let span = __s0_buffer_get(U64, block_starts, rec.function) - __s0_buffer_get(U64, block_starts, rec.function - 1)
            if rec.block >= 1 && rec.block <= span {
                slot = __s0_buffer_get(U64, block_starts, rec.function - 1) + rec.block
            }
        }
        __s0_buffer_set(U64, slots, at, slot)
        at = at + 1
    }
    let instrs = try mir_print_group_by_slot(d, __s0_buffer_get(U64, block_starts, fc), slots)
    slots = try mir_index_zeros(d, term_total)
    at = 0
    while at < term_total {
        var slot: U64 = 0
        let rec = __s0_buffer_get(MirTermRec, store.terminators, at)
        if rec.function >= 1 && rec.function <= fc {
            let span = __s0_buffer_get(U64, block_starts, rec.function) - __s0_buffer_get(U64, block_starts, rec.function - 1)
            if rec.block >= 1 && rec.block <= span {
                slot = __s0_buffer_get(U64, block_starts, rec.function - 1) + rec.block
            }
        }
        __s0_buffer_set(U64, slots, at, slot)
        at = at + 1
    }
    let terms = try mir_print_group_by_slot(d, __s0_buffer_get(U64, block_starts, fc), slots)
    slots = try mir_index_zeros(d, operand_total)
    at = 0
    while at < operand_total {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
        __s0_buffer_set(U64, slots, at, mir_print_operand_slot(store, rec.kind, rec.owner))
        at = at + 1
    }
    let operands = try mir_print_group_by_slot(d, mir_print_operand_slot_total(store), slots)
    slots = try mir_index_zeros(d, part_total)
    at = 0
    while at < part_total {
        __s0_buffer_set(U64, slots, at, __s0_buffer_get(MirTypePartRec, store.type_parts, at).owner)
        at = at + 1
    }
    let parts = try mir_print_group_by_slot(d, __s0_buffer_len(MirTypeRec, store.types), slots)
    var max_len = value_total
    if block_total > max_len { max_len = block_total }
    if local_total > max_len { max_len = local_total }
    if param_total > max_len { max_len = param_total }
    if instr_total > max_len { max_len = instr_total }
    if term_total > max_len { max_len = term_total }
    if operand_total > max_len { max_len = operand_total }
    if part_total > max_len { max_len = part_total }
    let seen = try mir_index_zeros(d, max_len + 1)
    return Ok(MirPrintIndex(values: values.groups, values_order: values.order, values_extra: values.extra, blocks: blocks.groups, blocks_order: blocks.order, blocks_extra: blocks.extra, locals: locals.groups, locals_order: locals.order, locals_extra: locals.extra, params: params.groups, params_order: params.order, params_extra: params.extra, block_starts: block_starts, instr: instrs.groups, instr_order: instrs.order, instr_extra: instrs.extra, term: terms.groups, term_order: terms.order, term_extra: terms.extra, operand: operands.groups, operand_order: operands.order, operand_extra: operands.extra, parts: parts.groups, parts_order: parts.order, parts_extra: parts.extra, seen: seen))
}

fn mir_print_operand_slot_total(store: MirStore) -> U64 {
    return __s0_buffer_len(MirTypeRec, store.types) + __s0_buffer_len(MirImportRec, store.imports) + __s0_buffer_len(MirInstrRec, store.instructions) * 3 + __s0_buffer_len(MirTermRec, store.terminators) * 2 + __s0_buffer_len(MirOperandRec, store.operands) + __s0_buffer_len(MirBindingFnRec, store.binding_funcs) + __s0_buffer_len(MirBindingRec, store.bindings)
}

fn mir_id_valid(id: U64, length: U64) -> Bool { return id > 0 && id <= length }

fn mir_name_range_valid(store: MirStore, start: U64, end: U64) -> Bool {
    return start <= end && end <= __s0_buffer_len(U8, store.names)
}

fn mir_ident_start(byte: U8) -> Bool {
    return byte == 95 || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

fn mir_ident_continue(byte: U8) -> Bool { return mir_ident_start(byte) || (byte >= 48 && byte <= 57) }

fn mir_name_valid(store: MirStore, start: U64, end: U64, dotted: Bool) -> Bool {
    if !mir_name_range_valid(store, start, end) || start == end { return false }
    var at = start
    var segment_start = true
    while at < end {
        let byte = __s0_buffer_get(U8, store.names, at)
        if segment_start {
            if !mir_ident_start(byte) { return false }
            segment_start = false
        }
        if !segment_start && byte == 46 && dotted {
            segment_start = true
        }
        if !segment_start && byte != 46 && !mir_ident_continue(byte) { return false }
        at = at + 1
    }
    return !segment_start
}

fn mir_type_valid(store: MirStore, id: U64) -> Bool { return mir_id_valid(id, __s0_buffer_len(MirTypeRec, store.types)) }
fn mir_function_valid(store: MirStore, id: U64) -> Bool { return mir_id_valid(id, __s0_buffer_len(MirFunctionRec, store.functions)) }
fn mir_import_valid(store: MirStore, id: U64) -> Bool { return mir_id_valid(id, __s0_buffer_len(MirImportRec, store.imports)) }

fn mir_value_count(idx: MirPrintIndex, store: MirStore, function: U64) -> U64 {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        return __s0_buffer_get(MirPrintGroup, idx.values, function - 1).count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.values_extra) {
        if __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, at) - 1).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_block_count(idx: MirPrintIndex, store: MirStore, function: U64) -> U64 {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        return __s0_buffer_get(MirPrintGroup, idx.blocks, function - 1).count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.blocks_extra) {
        if __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_extra, at) - 1).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_local_count(idx: MirPrintIndex, store: MirStore, function: U64) -> U64 {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        return __s0_buffer_get(MirPrintGroup, idx.locals, function - 1).count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.locals_extra) {
        if __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_extra, at) - 1).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_value_valid(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    if id == 0 { return false }
    var found: U64 = 0
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.values, function - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_order, group.first - 1 + k) - 1)
            if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
            k = k + 1
        }
        return found == 1
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.values_extra) {
        let rec = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, at) - 1)
        if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
        at = at + 1
    }
    return found == 1
}

fn mir_block_valid(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    if id == 0 { return false }
    var found: U64 = 0
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.blocks, function - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_order, group.first - 1 + k) - 1)
            if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
            k = k + 1
        }
        return found == 1
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.blocks_extra) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_extra, at) - 1)
        if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
        at = at + 1
    }
    return found == 1
}

fn mir_local_valid(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    if id == 0 { return false }
    var found: U64 = 0
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.locals, function - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_order, group.first - 1 + k) - 1)
            if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
            k = k + 1
        }
        return found == 1
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.locals_extra) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_extra, at) - 1)
        if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
        at = at + 1
    }
    return found == 1
}

fn mir_operand_count(store: MirStore, kind: U64, owner: U64, edge: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
        if rec.kind == kind && rec.owner == owner && rec.edge == edge { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_print_operand_count(idx: MirPrintIndex, store: MirStore, kind: U64, owner: U64, edge: U64) -> U64 {
    let slot = mir_print_operand_slot(store, kind, owner)
    var count: U64 = 0
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
            if rec.kind == kind && rec.owner == owner && rec.edge == edge { count = count + 1 }
            k = k + 1
        }
        return count
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.operand_extra) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, at) - 1)
        if rec.kind == kind && rec.owner == owner && rec.edge == edge { count = count + 1 }
        at = at + 1
    }
    return count
}

// Group coverage: with count equal to the group's record total, the original
// per-ordinal found==1 loop over 0..count-1 accepts exactly the stores whose
// matching ordinals are distinct and inside 1..count. Each table gets a
// concrete cover because the record types differ.
fn mir_value_group_cover(idx: MirPrintIndex, store: MirStore, function: U64) -> Bool {
    var count: U64 = 0
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        count = __s0_buffer_get(MirPrintGroup, idx.values, function - 1).count
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.values_extra) {
            if __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, at) - 1).function == function { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.values, function - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_order, group.first - 1 + k) - 1)
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.values_extra) {
        let rec = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, at) - 1)
        if rec.function == function {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

fn mir_block_group_cover(idx: MirPrintIndex, store: MirStore, function: U64) -> Bool {
    var count: U64 = 0
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        count = __s0_buffer_get(MirPrintGroup, idx.blocks, function - 1).count
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.blocks_extra) {
            if __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_extra, at) - 1).function == function { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.blocks, function - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_order, group.first - 1 + k) - 1)
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.blocks_extra) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_extra, at) - 1)
        if rec.function == function {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

fn mir_local_group_cover(idx: MirPrintIndex, store: MirStore, function: U64) -> Bool {
    var count: U64 = 0
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        count = __s0_buffer_get(MirPrintGroup, idx.locals, function - 1).count
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.locals_extra) {
            if __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_extra, at) - 1).function == function { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.locals, function - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_order, group.first - 1 + k) - 1)
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.locals_extra) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_extra, at) - 1)
        if rec.function == function {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

fn mir_operand_group_valid(idx: MirPrintIndex, store: MirStore, kind: U64, owner: U64, edge: U64) -> Bool {
    let slot = mir_print_operand_slot(store, kind, owner)
    var count: U64 = 0
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
            if rec.kind == kind && rec.owner == owner && rec.edge == edge { count = count + 1 }
            k = k + 1
        }
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.operand_extra) {
            let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, at) - 1)
            if rec.kind == kind && rec.owner == owner && rec.edge == edge { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
            if rec.kind == kind && rec.owner == owner && rec.edge == edge {
                let ordinal = rec.ordinal + 1
                if ordinal == 0 || ordinal > count { return false }
                if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
                __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            }
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.operand_extra) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, at) - 1)
        if rec.kind == kind && rec.owner == owner && rec.edge == edge {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

fn mir_type_part_count(store: MirStore, owner: U64, kind: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if rec.owner == owner && rec.kind == kind { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_type_part_count_at(idx: MirPrintIndex, store: MirStore, owner: U64, kind: U64) -> U64 {
    let slot = owner
    if slot >= 1 && slot <= __s0_buffer_len(MirTypeRec, store.types) {
        let group = __s0_buffer_get(MirPrintGroup, idx.parts, slot - 1)
        var count: U64 = 0
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_order, group.first - 1 + k) - 1)
            if rec.owner == owner && rec.kind == kind { count = count + 1 }
            k = k + 1
        }
        return count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.parts_extra) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_extra, at) - 1)
        if rec.owner == owner && rec.kind == kind { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_type_part_group_valid(idx: MirPrintIndex, store: MirStore, owner: U64, kind: U64) -> Bool {
    let slot = owner
    var count: U64 = 0
    if slot >= 1 && slot <= __s0_buffer_len(MirTypeRec, store.types) {
        let group = __s0_buffer_get(MirPrintGroup, idx.parts, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_order, group.first - 1 + k) - 1)
            if rec.owner == owner && rec.kind == kind { count = count + 1 }
            k = k + 1
        }
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.parts_extra) {
            let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_extra, at) - 1)
            if rec.owner == owner && rec.kind == kind { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if slot >= 1 && slot <= __s0_buffer_len(MirTypeRec, store.types) {
        let group = __s0_buffer_get(MirPrintGroup, idx.parts, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_order, group.first - 1 + k) - 1)
            if rec.owner == owner && rec.kind == kind {
                let ordinal = rec.ordinal + 1
                if ordinal == 0 || ordinal > count { return false }
                if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
                __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            }
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.parts_extra) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_extra, at) - 1)
        if rec.owner == owner && rec.kind == kind {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

// Structural rules for the raw C type vocabulary: c_raw carries a scalar id
// in length, c_ptr/c_const_ptr carry one valid element, and c_named carries a
// dotted Alder name, a non-empty C spelling, a class, and (for records) a
// contiguous c_field group.
fn mir_validate_c_type(idx: MirPrintIndex, store: MirStore, id: U64, rec: MirTypeRec) -> Bool {
    if rec.kind == mir_type_kind_c_raw() {
        return rec.length < mir_c_scalar_count() && rec.elem == 0 && rec.ok_type == 0 && rec.err_type == 0 && rec.first_part == 0 && rec.part_count == 0 && rec.result_type == 0 && rec.name_start == 0 && rec.name_end == 0 && rec.c_name_start == 0 && rec.c_name_end == 0 && rec.c_class == mir_c_class_scalar()
    }
    if rec.kind == mir_type_kind_c_ptr() || rec.kind == mir_type_kind_c_const_ptr() {
        return mir_type_valid(store, rec.elem) && rec.ok_type == 0 && rec.err_type == 0 && rec.first_part == 0 && rec.part_count == 0 && rec.result_type == 0 && rec.length == 0 && rec.name_start == 0 && rec.name_end == 0 && rec.c_name_start == 0 && rec.c_name_end == 0 && rec.c_class == mir_c_class_scalar()
    }
    if !mir_name_valid(store, rec.name_start, rec.name_end, true) || !mir_name_range_valid(store, rec.c_name_start, rec.c_name_end) || rec.c_name_start == rec.c_name_end || rec.c_class > mir_c_class_callback() || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 || rec.length != 0 { return false }
    if rec.c_class == mir_c_class_scalar() && mir_type_part_count_at(idx, store, id, mir_type_part_c_field()) != 0 { return false }
    if rec.c_class == mir_c_class_record() && !mir_type_part_group_valid(idx, store, id, mir_type_part_c_field()) { return false }
    return true
}

// Binding blocks: names and headers non-empty, member names unique per block,
// member owners valid, and every c_named type claimed by exactly one block.
fn mir_validate_bindings(idx: MirPrintIndex, store: MirStore) -> Bool {
    var block_at: U64 = 0
    while block_at < __s0_buffer_len(MirBindingRec, store.bindings) {
        let block = __s0_buffer_get(MirBindingRec, store.bindings, block_at)
        let block_id = block_at + 1
        if !mir_name_valid(store, block.name_start, block.name_end, false) || block.header_start >= block.header_end || block.header_end > __s0_buffer_len(U8, store.names) { return false }
        var fn_at: U64 = 0
        while fn_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
            let fn_rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, fn_at)
            if fn_rec.block == block_id {
                if !mir_name_valid(store, fn_rec.name_start, fn_rec.name_end, false) || !mir_name_range_valid(store, fn_rec.c_name_start, fn_rec.c_name_end) || fn_rec.c_name_start == fn_rec.c_name_end || !mir_type_valid(store, fn_rec.result_type) { return false }
                let params = mir_print_operand_count(idx, store, mir_operand_binding_param(), fn_at + 1, 0)
                if !mir_operand_group_valid(idx, store, mir_operand_binding_param(), fn_at + 1, 0) { return false }
                var ordinal: U64 = 0
                while ordinal < params {
                    if !mir_binding_param_ordinal_ok(idx, store, fn_at + 1, ordinal) { return false }
                    ordinal = ordinal + 1
                }
            }
            fn_at = fn_at + 1
        }
        var const_at: U64 = 0
        while const_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
            let const_rec = __s0_buffer_get(MirBindingConstRec, store.binding_consts, const_at)
            if const_rec.block == block_id {
                if !mir_name_valid(store, const_rec.name_start, const_rec.name_end, false) || !mir_name_range_valid(store, const_rec.c_name_start, const_rec.c_name_end) || const_rec.c_name_start == const_rec.c_name_end || !mir_type_valid(store, const_rec.const_type) { return false }
            }
            const_at = const_at + 1
        }
        block_at = block_at + 1
    }
    return mir_validate_binding_uniqueness(idx, store)
}

fn mir_binding_param_ordinal_ok(idx: MirPrintIndex, store: MirStore, fn_id: U64, ordinal: U64) -> Bool {
    let slot = mir_print_operand_slot(store, mir_operand_binding_param(), fn_id)
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
            if operand.kind == mir_operand_binding_param() && operand.owner == fn_id && operand.ordinal == ordinal { return mir_type_valid(store, operand.operand_type) }
            k = k + 1
        }
        return false
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.operand_extra) {
        let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, at) - 1)
        if operand.kind == mir_operand_binding_param() && operand.owner == fn_id && operand.ordinal == ordinal { return mir_type_valid(store, operand.operand_type) }
        at = at + 1
    }
    return false
}

fn mir_validate_binding_uniqueness(idx: MirPrintIndex, store: MirStore) -> Bool {
    var block_at: U64 = 0
    while block_at < __s0_buffer_len(MirBindingRec, store.bindings) {
        let block_id = block_at + 1
        var name_at: U64 = 0
        while name_at < block_at {
            let other = __s0_buffer_get(MirBindingRec, store.bindings, name_at)
            let block = __s0_buffer_get(MirBindingRec, store.bindings, block_at)
            if other.name_start == block.name_start && other.name_end == block.name_end { return false }
            name_at = name_at + 1
        }
        var fn_at: U64 = 0
        while fn_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
            let fn_rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, fn_at)
            if fn_rec.block == block_id {
                var other_at: U64 = fn_at + 1
                while other_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
                    let other = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, other_at)
                    if other.block == block_id && other.name_start == fn_rec.name_start && other.name_end == fn_rec.name_end { return false }
                    other_at = other_at + 1
                }
                var const_at: U64 = 0
                while const_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
                    let other = __s0_buffer_get(MirBindingConstRec, store.binding_consts, const_at)
                    if other.block == block_id && other.name_start == fn_rec.name_start && other.name_end == fn_rec.name_end { return false }
                    const_at = const_at + 1
                }
            }
            fn_at = fn_at + 1
        }
        var const_at: U64 = 0
        while const_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
            let const_rec = __s0_buffer_get(MirBindingConstRec, store.binding_consts, const_at)
            if const_rec.block == block_id {
                var other_at: U64 = const_at + 1
                while other_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
                    let other = __s0_buffer_get(MirBindingConstRec, store.binding_consts, other_at)
                    if other.block == block_id && other.name_start == const_rec.name_start && other.name_end == const_rec.name_end { return false }
                    other_at = other_at + 1
                }
            }
            const_at = const_at + 1
        }
        block_at = block_at + 1
    }
    // Each c_named type is claimed by exactly one binding_type operand.
    var id: U64 = mir_primitive_type_count() + 1
    while id <= __s0_buffer_len(MirTypeRec, store.types) {
        let rec = __s0_buffer_get(MirTypeRec, store.types, id - 1)
        if rec.kind == mir_type_kind_c_named() {
            var claims: U64 = 0
            var at: U64 = 0
            while at < __s0_buffer_len(MirOperandRec, store.operands) {
                let operand = __s0_buffer_get(MirOperandRec, store.operands, at)
                if operand.kind == mir_operand_binding_type() && operand.operand_type == id { claims = claims + 1 }
                at = at + 1
            }
            if claims != 1 { return false }
        }
        id = id + 1
    }
    return true
}

fn mir_validate_types(idx: MirPrintIndex, store: MirStore) -> Bool {
    let length = __s0_buffer_len(MirTypeRec, store.types)
    if length < mir_primitive_type_count() { return false }
    var at: U64 = 0
    while at < length {
        let rec = __s0_buffer_get(MirTypeRec, store.types, at)
        let id = at + 1
        if at < mir_primitive_type_count() {
            if rec.kind != mir_type_kind_primitive() || rec.name_start != 0 || rec.name_end != 0 || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 || rec.length != 0 { return false }
        } else {
            if rec.kind == mir_type_kind_primitive() || rec.kind > mir_type_kind_c_callback_owner() { return false }
            if rec.kind == mir_type_kind_aggregate() || rec.kind == mir_type_kind_enum() {
                if !mir_name_valid(store, rec.name_start, rec.name_end, true) || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 || rec.length != 0 { return false }
                var part_kind = mir_type_part_variant()
                if rec.kind == mir_type_kind_aggregate() { part_kind = mir_type_part_field() }
                if !mir_type_part_group_valid(idx, store, id, part_kind) { return false }
            } else {
                if rec.kind != mir_type_kind_c_raw() && rec.kind != mir_type_kind_c_ptr() && rec.kind != mir_type_kind_c_const_ptr() && rec.kind != mir_type_kind_c_named() && (rec.name_start != 0 || rec.name_end != 0) { return false }
                if rec.kind == mir_type_kind_result() {
                    if !mir_type_valid(store, rec.ok_type) || !mir_type_valid(store, rec.err_type) || rec.elem != 0 { return false }
                }
                if rec.kind == mir_type_kind_function() {
                    if !mir_type_valid(store, rec.result_type) || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 { return false }
                    let param_count = mir_type_part_count_at(idx, store, id, mir_type_part_function_param())
                    if mir_type_part_count_at(idx, store, id, mir_type_part_function_env()) > 1 { return false }
                    if rec.part_count == 0 {
                        if rec.first_part != 0 { return false }
                    } else {
                        if !mir_id_valid(rec.first_part, __s0_buffer_len(MirTypePartRec, store.type_parts)) || rec.part_count > __s0_buffer_len(MirTypePartRec, store.type_parts) - rec.first_part + 1 { return false }
                        var part_at: U64 = 0
                        while part_at < rec.part_count {
                            let part = __s0_buffer_get(MirTypePartRec, store.type_parts, rec.first_part - 1 + part_at)
                            if part.owner != id { return false }
                            if part.kind == mir_type_part_function_env() {
                                if part_at != param_count || part.ordinal != 0 { return false }
                            } else {
                                if part.kind != mir_type_part_function_param() || part.ordinal != part_at { return false }
                            }
                            part_at = part_at + 1
                        }
                    }
                    if param_count > rec.part_count { return false }
                }
                if rec.kind == mir_type_kind_c_callback_owner() {
                    if !mir_type_valid(store, rec.elem) || !mir_type_valid(store, rec.result_type) || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.length != 0 || rec.name_start != 0 || rec.name_end != 0 || rec.c_name_start != 0 || rec.c_name_end != 0 { return false }
                }
                if rec.kind == mir_type_kind_domain_handle() || rec.kind == mir_type_kind_domain_mark() || rec.kind == mir_type_kind_cleanup_scope() || rec.kind == mir_type_kind_cleanup_id() || rec.kind == mir_type_kind_string() || rec.kind == mir_type_kind_bytes() || rec.kind == mir_type_kind_c_string() {
                    if rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 { return false }
                }
                if rec.kind != mir_type_kind_result() && rec.kind != mir_type_kind_function() && rec.kind != mir_type_kind_domain_handle() && rec.kind != mir_type_kind_domain_mark() && rec.kind != mir_type_kind_cleanup_scope() && rec.kind != mir_type_kind_cleanup_id() && rec.kind != mir_type_kind_string() && rec.kind != mir_type_kind_bytes() && rec.kind != mir_type_kind_c_raw() && rec.kind != mir_type_kind_c_ptr() && rec.kind != mir_type_kind_c_const_ptr() && rec.kind != mir_type_kind_c_named() && rec.kind != mir_type_kind_c_string() && rec.kind != mir_type_kind_c_callback_owner() {
                    if !mir_type_valid(store, rec.elem) || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 { return false }
                }
                if rec.kind != mir_type_kind_array() && rec.kind != mir_type_kind_c_raw() && rec.length != 0 { return false }
            }
        }
        at = at + 1
    }
    at = 0
    let part_total = __s0_buffer_len(MirTypePartRec, store.type_parts)
    while at < part_total {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if !mir_type_valid(store, part.owner) || !mir_type_valid(store, part.part_type) { return false }
        let owner = __s0_buffer_get(MirTypeRec, store.types, part.owner - 1)
        if part.kind == mir_type_part_field() {
            if owner.kind != mir_type_kind_aggregate() || !mir_name_valid(store, part.name_start, part.name_end, true) { return false }
        }
        if part.kind == mir_type_part_variant() {
            if owner.kind != mir_type_kind_enum() || !mir_name_valid(store, part.name_start, part.name_end, true) { return false }
        }
        if part.kind == mir_type_part_function_param() {
            if owner.kind != mir_type_kind_function() || part.name_start != 0 || part.name_end != 0 { return false }
        }
        if part.kind == mir_type_part_function_env() {
            if owner.kind != mir_type_kind_function() || part.name_start != 0 || part.name_end != 0 { return false }
        }
        if part.kind == mir_type_part_c_field() {
            if !mir_name_valid(store, part.name_start, part.name_end, true) || !mir_name_range_valid(store, part.c_name_start, part.c_name_end) || part.c_name_start == part.c_name_end || !mir_id_valid(part.ordinal + 1, part_total) { return false }
            if owner.kind != mir_type_kind_c_named() || owner.c_class != mir_c_class_record() { return false }
        }
        if part.kind < mir_type_part_field() || part.kind > mir_type_part_c_field() { return false }
        at = at + 1
    }
    return true
}

fn mir_param_group_count(idx: MirPrintIndex, store: MirStore, kind: U64, function: U64, block: U64) -> U64 {
    let slot = mir_print_param_slot(store, function, kind)
    var count: U64 = 0
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.params, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_order, group.first - 1 + k) - 1)
            if rec.kind == kind && rec.function == function && rec.block == block { count = count + 1 }
            k = k + 1
        }
        return count
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.params_extra) {
        let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_extra, at) - 1)
        if rec.kind == kind && rec.function == function && rec.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_param_group_valid(idx: MirPrintIndex, store: MirStore, kind: U64, function: U64, block: U64) -> Bool {
    let slot = mir_print_param_slot(store, function, kind)
    var count: U64 = 0
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.params, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_order, group.first - 1 + k) - 1)
            if rec.kind == kind && rec.function == function && rec.block == block { count = count + 1 }
            k = k + 1
        }
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.params_extra) {
            let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_extra, at) - 1)
            if rec.kind == kind && rec.function == function && rec.block == block { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.params, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_order, group.first - 1 + k) - 1)
            if rec.kind == kind && rec.function == function && rec.block == block {
                let ordinal = rec.ordinal + 1
                if ordinal == 0 || ordinal > count { return false }
                if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
                __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            }
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.params_extra) {
        let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_extra, at) - 1)
        if rec.kind == kind && rec.function == function && rec.block == block {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

fn mir_instr_group_count(idx: MirPrintIndex, store: MirStore, function: U64, block: U64) -> U64 {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let span = mir_print_block_span(idx, function)
        if block >= 1 && block <= span {
            let slot = __s0_buffer_get(U64, idx.block_starts, function - 1) + block
            return __s0_buffer_get(MirPrintGroup, idx.instr, slot - 1).count
        }
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.instr_extra) {
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_extra, at) - 1)
        if rec.function == function && rec.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_instr_group_valid(idx: MirPrintIndex, store: MirStore, function: U64, block: U64) -> Bool {
    let slot = mir_print_instr_slot(idx, store, function, block)
    var count: U64 = 0
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.instr, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_order, group.first - 1 + k) - 1)
            if rec.function == function && rec.block == block { count = count + 1 }
            k = k + 1
        }
    } else {
        var at: U64 = 0
        while at < __s0_buffer_len(U64, idx.instr_extra) {
            let rec = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_extra, at) - 1)
            if rec.function == function && rec.block == block { count = count + 1 }
            at = at + 1
        }
    }
    var at: U64 = 0
    while at < count {
        __s0_buffer_set(U64, idx.seen, at, 0)
        at = at + 1
    }
    if slot != 0 {
        let group = __s0_buffer_get(MirPrintGroup, idx.instr, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let rec = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_order, group.first - 1 + k) - 1)
            if rec.function == function && rec.block == block {
                let ordinal = rec.ordinal + 1
                if ordinal == 0 || ordinal > count { return false }
                if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
                __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
            }
            k = k + 1
        }
        return true
    }
    at = 0
    while at < __s0_buffer_len(U64, idx.instr_extra) {
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_extra, at) - 1)
        if rec.function == function && rec.block == block {
            let ordinal = rec.ordinal + 1
            if ordinal == 0 || ordinal > count { return false }
            if __s0_buffer_get(U64, idx.seen, ordinal - 1) != 0 { return false }
            __s0_buffer_set(U64, idx.seen, ordinal - 1, 1)
        }
        at = at + 1
    }
    return true
}

fn mir_print_instr_slot(idx: MirPrintIndex, store: MirStore, function: U64, block: U64) -> U64 {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let span = mir_print_block_span(idx, function)
        if block >= 1 && block <= span {
            return __s0_buffer_get(U64, idx.block_starts, function - 1) + block
        }
    }
    return 0
}

fn mir_print_term_count(idx: MirPrintIndex, store: MirStore, function: U64, block: U64) -> U64 {
    let slot = mir_print_instr_slot(idx, store, function, block)
    if slot != 0 {
        return __s0_buffer_get(MirPrintGroup, idx.term, slot - 1).count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.term_extra) {
        let rec = __s0_buffer_get(MirTermRec, store.terminators, __s0_buffer_get(U64, idx.term_extra, at) - 1)
        if rec.function == function && rec.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_instr_produces(op: U64) -> Bool {
    return op != mir_op_store() && op != mir_op_domain_reset() && op != mir_op_domain_destroy() && op != mir_op_cleanup_disarm() && op != mir_op_cleanup_scope_run() && op != mir_op_cleanup_scope_end() && op != mir_op_table_view_end() && op != mir_op_c_field_set() && op != mir_op_c_string_release() && op != mir_op_c_callback_owner_release()
}

fn mir_instr_checked(op: U64) -> Bool {
    return op == mir_op_slice_to_bytes() || op == mir_op_alloc_checked() || (op >= mir_op_int_add_checked() && op <= mir_op_int_shr_checked()) || op == mir_op_slice_index_checked() || op == mir_op_array_index_checked() || op == mir_op_slice_range_checked() || op == mir_op_enum_payload_checked() || op == mir_op_vec_construct_checked() || op == mir_op_vec_grow_checked() || op == mir_op_str_byte_checked() || op == mir_op_str_concat() || op == mir_op_str_slice_checked() || op == mir_op_str_from_bytes() || op == mir_op_str_display()
}

fn mir_instruction_operands_valid(idx: MirPrintIndex, store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if rec.op == mir_op_load() || rec.op == mir_op_store() || rec.op == mir_op_borrow() || rec.op == mir_op_borrow_mut() {
        if !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) || __s0_buffer_get(MirPlaceRec, store.places, rec.place - 1).function != rec.function { return false }
        if rec.op == mir_op_store() && !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_aggregate_construct() {
        if !mir_type_valid(store, rec.type_op) || !mir_operand_group_valid(idx, store, mir_operand_aggregate_field(), id, 0) { return false }
    }
    if rec.op == mir_op_domain_create() || rec.op == mir_op_domain_mark() || rec.op == mir_op_domain_destroy() || rec.op == mir_op_slice_len() || rec.op == mir_op_cleanup_disarm() || rec.op == mir_op_cleanup_scope_run() || rec.op == mir_op_cleanup_scope_end() || rec.op == mir_op_table_view_end() || (rec.op >= mir_op_vec_len() && rec.op <= mir_op_vec_as_mut_slice()) || rec.op == mir_op_array_as_slice() || rec.op == mir_op_str_len() || rec.op == mir_op_str_to_bytes() || rec.op == mir_op_int_not() {
        if !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_domain_reset() || (rec.op >= mir_op_int_add_checked() && rec.op <= mir_op_int_shr_checked()) || (rec.op >= mir_op_int_add_try() && rec.op <= mir_op_int_mul_wrapping()) || (rec.op >= mir_op_int_eq() && rec.op <= mir_op_float_ge()) || (rec.op >= mir_op_float_add() && rec.op <= mir_op_float_div()) || rec.op == mir_op_table_insert() || rec.op == mir_op_table_insert_try() || rec.op == mir_op_table_lookup() || rec.op == mir_op_table_lookup_mut() || rec.op == mir_op_table_remove() || rec.op == mir_op_slice_index_checked() || rec.op == mir_op_array_index_checked() || rec.op == mir_op_copy_to_domain() || rec.op == mir_op_str_byte_checked() || rec.op == mir_op_str_from_bytes() || rec.op == mir_op_str_display() || (rec.op >= mir_op_int_and() && rec.op <= mir_op_int_xor()) {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_value_valid(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_alloc() || rec.op == mir_op_alloc_checked() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_type_valid(store, rec.type_op) || !mir_value_valid(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_cleanup_push() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_function_valid(store, rec.target) || !mir_operand_group_valid(idx, store, mir_operand_instruction(), id, 0) { return false }
        if rec.place != 0 {
            if !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) { return false }
            if __s0_buffer_get(MirPlaceRec, store.places, rec.place - 1).function != rec.function { return false }
            if __s0_buffer_get(MirPlaceRec, store.places, rec.place - 1).kind != mir_place_local() { return false }
        }
    }
    if rec.op == mir_op_slice_range_checked() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_value_valid(idx, store, rec.function, rec.b) || !mir_value_valid(idx, store, rec.function, rec.c) { return false }
    }
    if rec.op == mir_op_vec_new() {
        if !mir_type_valid(store, rec.type_op) { return false }
    }
    if rec.op == mir_op_vec_construct_checked() || rec.op == mir_op_vec_grow_checked() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_value_valid(idx, store, rec.function, rec.b) || !mir_value_valid(idx, store, rec.function, rec.c) { return false }
    }
    if rec.op == mir_op_str_concat() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_value_valid(idx, store, rec.function, rec.b) || !mir_value_valid(idx, store, rec.function, rec.c) { return false }
    }
    if rec.op == mir_op_slice_to_bytes() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_value_valid(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_str_slice_checked() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_value_valid(idx, store, rec.function, rec.b) || !mir_value_valid(idx, store, rec.function, rec.c) || !mir_operand_group_valid(idx, store, mir_operand_instruction(), id, 0) { return false }
    }
    if rec.op == mir_op_enum_payload_checked() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    }
    if rec.op == mir_op_enum_construct() {
        if !mir_type_valid(store, rec.type_op) || !mir_name_valid(store, rec.name_start, rec.name_end, true) || rec.a != 0 && !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_table_create() {
        if !mir_type_valid(store, rec.type_op) || !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op >= mir_op_int_trunc() && rec.op <= mir_op_float_from_int() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_type_valid(store, rec.type_op) { return false }
    }
    if rec.op == mir_op_int_convert_checked() || rec.op == mir_op_int_convert_wrap() || (rec.op >= mir_op_c_num_try() && rec.op <= mir_op_c_num_cast()) {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_type_valid(store, rec.type_op) { return false }
    }
    if rec.op == mir_op_c_field_get() {
        if !mir_value_valid(idx, store, rec.function, rec.a) || !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    }
    if rec.op == mir_op_c_field_set() {
        if !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) || __s0_buffer_get(MirPlaceRec, store.places, rec.place - 1).function != rec.function || !mir_value_valid(idx, store, rec.function, rec.a) || !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    }
    if rec.op == mir_op_const_get() && !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    if (rec.op == mir_op_call() || rec.op == mir_op_ffi_call_unsafe() || rec.op == mir_op_call_value() || rec.op == mir_op_c_binding_call() || rec.op == mir_op_str_slice_checked()) && !mir_operand_group_valid(idx, store, mir_operand_instruction(), id, 0) { return false }
    if rec.op == mir_op_c_is_null() && !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    // The c.string vocabulary reads exactly one value operand: the source
    // String for the constructors, the borrowed owner for ptr, and the
    // released buffer for release.
    if rec.op >= mir_op_c_string_make_lit() && rec.op <= mir_op_c_string_release() && !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    if rec.op == mir_op_c_buffer_ptr() && (!mir_value_valid(idx, store, rec.function, rec.a) || !mir_type_valid(store, rec.type_op)) { return false }
    if rec.op == mir_op_c_zero() && !mir_type_valid(store, rec.type_op) { return false }
    if rec.op == mir_op_c_addr() {
        if !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) || __s0_buffer_get(MirPlaceRec, store.places, rec.place - 1).function != rec.function || !mir_type_valid(store, rec.type_op) { return false }
    }
    return true
}

fn mir_validate_instruction_refs(idx: MirPrintIndex, store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if rec.op > mir_op_slice_to_bytes() || !mir_block_valid(idx, store, rec.function, rec.block) || !mir_instruction_operands_valid(idx, store, id, rec) { return false }
    var may_omit_result = false
    if rec.op == mir_op_call() && mir_function_valid(store, rec.target) && __s0_buffer_get(MirFunctionRec, store.functions, rec.target - 1).result_type == mir_type_unit() { may_omit_result = true }
    if rec.op == mir_op_ffi_call_unsafe() && mir_import_valid(store, rec.target) && __s0_buffer_get(MirImportRec, store.imports, rec.target - 1).result_type == mir_type_unit() { may_omit_result = true }
    if rec.op == mir_op_c_binding_call() && mir_binding_fn_valid(store, rec.target) && __s0_buffer_get(MirBindingFnRec, store.binding_funcs, rec.target - 1).result_type == mir_type_unit() { may_omit_result = true }
    if rec.op == mir_op_fn_value() && mir_value_valid(idx, store, rec.function, rec.result) {
        let ft = __s0_buffer_get(MirValueRec, store.values, rec.result - 1).value_type
        if ft >= 1 && ft <= __s0_buffer_len(MirTypeRec, store.types) && __s0_buffer_get(MirTypeRec, store.types, ft - 1).kind == mir_type_kind_function() && __s0_buffer_get(MirTypeRec, store.types, ft - 1).result_type == mir_type_unit() { may_omit_result = true }
    }
    if rec.op == mir_op_call_value() && mir_value_valid(idx, store, rec.function, rec.a) {
        let ft = __s0_buffer_get(MirValueRec, store.values, rec.a - 1).value_type
        if ft >= 1 && ft <= __s0_buffer_len(MirTypeRec, store.types) && __s0_buffer_get(MirTypeRec, store.types, ft - 1).kind == mir_type_kind_function() && __s0_buffer_get(MirTypeRec, store.types, ft - 1).result_type == mir_type_unit() { may_omit_result = true }
    }
    if mir_instr_produces(rec.op) && !may_omit_result {
        if !mir_value_valid(idx, store, rec.function, rec.result) { return false }
    }
    if may_omit_result && rec.result != 0 { return false }
    if !mir_instr_produces(rec.op) && rec.result != 0 { return false }
    if rec.place != 0 && rec.op != mir_op_c_callback_owner_register() && rec.op != mir_op_c_callback_owner_release() && !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) { return false }
    if rec.type_op != 0 && rec.type_op != mir_fn_value_domain_marker() && !mir_type_valid(store, rec.type_op) { return false }
    if rec.type_op == mir_fn_value_domain_marker() && rec.op != mir_op_fn_value() { return false }
    if rec.a != 0 && !mir_value_valid(idx, store, rec.function, rec.a) { return false }
    if rec.b != 0 && rec.op != mir_op_c_callback_owner_register() && rec.op != mir_op_c_callback_owner_release() && !mir_value_valid(idx, store, rec.function, rec.b) { return false }
    if rec.c != 0 && rec.op != mir_op_c_callback_owner_register() && rec.op != mir_op_c_callback_owner_release() && !mir_value_valid(idx, store, rec.function, rec.c) { return false }
    if !mir_name_range_valid(store, rec.name_start, rec.name_end) { return false }
    if mir_instr_checked(rec.op) {
        if !mir_block_valid(idx, store, rec.function, rec.target) || !mir_operand_group_valid(idx, store, mir_operand_checked_edge_arg(), id, 0) { return false }
    }
    if !mir_instr_checked(rec.op) && mir_print_operand_count(idx, store, mir_operand_checked_edge_arg(), id, 0) != 0 { return false }
    if rec.op == mir_op_call() || rec.op == mir_op_cleanup_push() || rec.op == mir_op_fn_value() {
        if !mir_function_valid(store, rec.target) { return false }
    }
    if rec.op == mir_op_ffi_call_unsafe() {
        if !mir_import_valid(store, rec.target) { return false }
    }
    if rec.op == mir_op_c_binding_call() && !mir_binding_fn_valid(store, rec.target) { return false }
    if rec.op == mir_op_c_callback_make() && !mir_function_valid(store, rec.target) { return false }
    if rec.op == mir_op_c_callback_owner_register() && (!mir_function_valid(store, rec.target) || !mir_binding_fn_valid(store, rec.b) || !mir_binding_fn_valid(store, rec.c) || !mir_binding_fn_valid(store, rec.place)) { return false }
    if rec.op == mir_op_c_callback_owner_release() && (!mir_binding_fn_valid(store, rec.b) || !mir_binding_fn_valid(store, rec.c)) { return false }
    if rec.op == mir_op_c_is_null() && rec.target != 0 { return false }
    if rec.op == mir_op_const_get() || rec.op == mir_op_enum_payload_checked() || rec.op == mir_op_enum_construct() {
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    }
    if rec.op != mir_op_const_get() && rec.op != mir_op_enum_payload_checked() && rec.op != mir_op_enum_construct() && rec.op != mir_op_c_field_get() && rec.op != mir_op_c_field_set() && rec.name_start != rec.name_end { return false }
    if !mir_operand_group_valid(idx, store, mir_operand_instruction(), id, 0) || !mir_operand_group_valid(idx, store, mir_operand_aggregate_field(), id, 0) { return false }
    return true
}

fn mir_validate_functions(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, at)
        let function = at + 1
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) || !mir_type_valid(store, rec.result_type) || !mir_param_group_valid(idx, store, mir_param_function(), function, 0) { return false }
        let blocks = mir_block_count(idx, store, function)
        if blocks == 0 || mir_value_count(idx, store, function) == 0 && mir_param_group_count(idx, store, mir_param_function(), function, 0) != 0 { return false }
        if !mir_local_group_cover(idx, store, function) { return false }
        var ordinal: U64 = 0
        while ordinal < blocks {
            let block = ordinal + 1
            if !mir_block_valid(idx, store, function, block) || !mir_param_group_valid(idx, store, mir_param_block(), function, block) || !mir_instr_group_valid(idx, store, function, block) { return false }
            if mir_print_term_count(idx, store, function, block) != 1 { return false }
            ordinal = ordinal + 1
        }
        if !mir_value_group_cover(idx, store, function) { return false }
        if !mir_block_group_cover(idx, store, function) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, at)
        if !mir_function_valid(store, rec.function) || !mir_name_valid(store, rec.name_start, rec.name_end, false) || !mir_type_valid(store, rec.local_type) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, at)
        if !mir_function_valid(store, rec.function) || !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let rec = __s0_buffer_get(MirParamRec, store.params, at)
        if !mir_function_valid(store, rec.function) || !mir_name_valid(store, rec.name_start, rec.name_end, false) || !mir_type_valid(store, rec.param_type) || !mir_value_valid(idx, store, rec.function, rec.value) { return false }
        if rec.kind == mir_param_function() {
            if rec.block != 0 { return false }
        }
        if rec.kind == mir_param_block() {
            if !mir_block_valid(idx, store, rec.function, rec.block) { return false }
        }
        if rec.kind != mir_param_function() && rec.kind != mir_param_block() { return false }
        var want_kind = mir_value_def_block_param()
        if rec.kind == mir_param_function() { want_kind = mir_value_def_function_param() }
        var links: U64 = 0
        if rec.function >= 1 && rec.function <= __s0_buffer_len(MirFunctionRec, store.functions) {
            let group = __s0_buffer_get(MirPrintGroup, idx.values, rec.function - 1)
            var k: U64 = 0
            while k < group.count {
                let value = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_order, group.first - 1 + k) - 1)
                if value.function == rec.function && value.ordinal + 1 == rec.value && value.def_kind == want_kind && value.block == rec.block && value.item == rec.ordinal + 1 { links = links + 1 }
                k = k + 1
            }
        } else {
            var value_at: U64 = 0
            while value_at < __s0_buffer_len(U64, idx.values_extra) {
                let value = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, value_at) - 1)
                if value.function == rec.function && value.ordinal + 1 == rec.value && value.def_kind == want_kind && value.block == rec.block && value.item == rec.ordinal + 1 { links = links + 1 }
                value_at = value_at + 1
            }
        }
        if links != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let rec = __s0_buffer_get(MirValueRec, store.values, at)
        if !mir_function_valid(store, rec.function) || !mir_name_valid(store, rec.name_start, rec.name_end, false) || !mir_type_valid(store, rec.value_type) || rec.def_kind > mir_value_def_switch_case() || rec.item == 0 { return false }
        if rec.def_kind != mir_value_def_function_param() && !mir_block_valid(idx, store, rec.function, rec.block) { return false }
        if rec.def_kind == mir_value_def_instruction() {
            var links: U64 = 0
            let slot = mir_print_instr_slot(idx, store, rec.function, rec.block)
            if slot != 0 {
                let group = __s0_buffer_get(MirPrintGroup, idx.instr, slot - 1)
                var k: U64 = 0
                while k < group.count {
                    let instruction = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_order, group.first - 1 + k) - 1)
                    if instruction.function == rec.function && instruction.block == rec.block && instruction.ordinal + 1 == rec.item && instruction.result == rec.ordinal + 1 { links = links + 1 }
                    k = k + 1
                }
            } else {
                var instruction_at: U64 = 0
                while instruction_at < __s0_buffer_len(U64, idx.instr_extra) {
                    let instruction = __s0_buffer_get(MirInstrRec, store.instructions, __s0_buffer_get(U64, idx.instr_extra, instruction_at) - 1)
                    if instruction.function == rec.function && instruction.block == rec.block && instruction.ordinal + 1 == rec.item && instruction.result == rec.ordinal + 1 { links = links + 1 }
                    instruction_at = instruction_at + 1
                }
            }
            if links != 1 { return false }
        }
        at = at + 1
    }
    return true
}

fn mir_validate_places(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirPlaceRec, store.places) {
        let rec = __s0_buffer_get(MirPlaceRec, store.places, at)
        if !mir_function_valid(store, rec.function) { return false }
        if rec.kind == mir_place_local() {
            if !mir_local_valid(idx, store, rec.function, rec.local) || rec.base != 0 || rec.field_start != 0 || rec.field_end != 0 || rec.deref_value != 0 { return false }
        }
        if rec.kind == mir_place_field() {
            if !mir_id_valid(rec.base, __s0_buffer_len(MirPlaceRec, store.places)) || rec.base >= at + 1 || __s0_buffer_get(MirPlaceRec, store.places, rec.base - 1).function != rec.function || !mir_name_valid(store, rec.field_start, rec.field_end, true) || rec.local != 0 || rec.deref_value != 0 { return false }
        }
        if rec.kind == mir_place_deref() {
            if !mir_value_valid(idx, store, rec.function, rec.deref_value) || rec.local != 0 || rec.base != 0 || rec.field_start != 0 || rec.field_end != 0 { return false }
        }
        if rec.kind > mir_place_deref() { return false }
        at = at + 1
    }
    return true
}

fn mir_validate_declarations(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let rec = __s0_buffer_get(MirImportRec, store.imports, at)
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) || !mir_type_valid(store, rec.result_type) || !mir_operand_group_valid(idx, store, mir_operand_import_param(), at + 1, 0) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let rec = __s0_buffer_get(MirConstRec, store.constants, at)
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) || !mir_type_valid(store, rec.const_type) || rec.kind > mir_const_string() || !mir_name_range_valid(store, rec.string_start, rec.string_end) { return false }
        if rec.kind != mir_const_string() && rec.string_start != rec.string_end { return false }
        if rec.kind == mir_const_bool() && rec.bool_value > 1 { return false }
        if rec.kind == mir_const_float() && ((rec.float_bits / 4503599627370496) % 2048) == 2047 { return false }
        at = at + 1
    }
    return true
}

fn mir_validate_terminators(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTermRec, store.terminators) {
        let rec = __s0_buffer_get(MirTermRec, store.terminators, at)
        let id = at + 1
        if !mir_function_valid(store, rec.function) || !mir_block_valid(idx, store, rec.function, rec.block) || rec.kind > mir_term_panic() { return false }
        if rec.kind == mir_term_jump() {
            if !mir_block_valid(idx, store, rec.function, rec.target) || !mir_operand_group_valid(idx, store, mir_operand_terminator_arg(), id, mir_edge_jump()) { return false }
        }
        if rec.kind == mir_term_branch() {
            if !mir_value_valid(idx, store, rec.function, rec.value) || !mir_block_valid(idx, store, rec.function, rec.then_block) || !mir_block_valid(idx, store, rec.function, rec.else_block) || !mir_operand_group_valid(idx, store, mir_operand_terminator_arg(), id, mir_edge_then()) || !mir_operand_group_valid(idx, store, mir_operand_terminator_arg(), id, mir_edge_else()) { return false }
        }
        if rec.kind == mir_term_switch() {
            if !mir_value_valid(idx, store, rec.function, rec.value) || !mir_operand_group_valid(idx, store, mir_operand_switch_case(), id, 0) { return false }
        }
        if rec.kind == mir_term_return() {
            if rec.value != 0 && !mir_value_valid(idx, store, rec.function, rec.value) { return false }
        }
        if rec.kind == mir_term_fail() {
            if !mir_value_valid(idx, store, rec.function, rec.value) { return false }
        }
        at = at + 1
    }
    return true
}

fn mir_validate_operands(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
        if rec.kind < mir_operand_type_part() || rec.kind > mir_operand_binding_type() { return false }
        if rec.kind == mir_operand_binding_param() {
            if !mir_binding_fn_valid(store, rec.owner) || !mir_type_valid(store, rec.operand_type) { return false }
        }
        if rec.kind == mir_operand_binding_type() {
            if !mir_id_valid(rec.owner, __s0_buffer_len(MirBindingRec, store.bindings)) || !mir_type_valid(store, rec.operand_type) { return false }
            let ty = __s0_buffer_get(MirTypeRec, store.types, rec.operand_type - 1)
            if ty.kind != mir_type_kind_c_named() { return false }
        }
        if rec.kind == mir_operand_type_part() {
            if !mir_type_valid(store, rec.owner) || !mir_type_valid(store, rec.operand_type) { return false }
        }
        if rec.kind == mir_operand_import_param() {
            if !mir_import_valid(store, rec.owner) || !mir_type_valid(store, rec.operand_type) { return false }
        }
        if rec.kind == mir_operand_instruction() || rec.kind == mir_operand_checked_edge_arg() || rec.kind == mir_operand_aggregate_field() {
            if !mir_id_valid(rec.owner, __s0_buffer_len(MirInstrRec, store.instructions)) { return false }
            let instruction = __s0_buffer_get(MirInstrRec, store.instructions, rec.owner - 1)
            if rec.value != 0 && !mir_value_valid(idx, store, instruction.function, rec.value) { return false }
            if rec.kind == mir_operand_checked_edge_arg() && rec.target != instruction.target { return false }
            if rec.kind == mir_operand_aggregate_field() {
                if instruction.op != mir_op_aggregate_construct() || !mir_type_valid(store, instruction.type_op) { return false }
                let aggregate = __s0_buffer_get(MirTypeRec, store.types, instruction.type_op - 1)
                if aggregate.kind == mir_type_kind_array() {
                    if rec.name_start != 0 || rec.name_end != 0 { return false }
                } else { if !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false } }
            }
        }
        if rec.kind == mir_operand_terminator_arg() || rec.kind == mir_operand_switch_case() {
            if !mir_id_valid(rec.owner, __s0_buffer_len(MirTermRec, store.terminators)) { return false }
            let term = __s0_buffer_get(MirTermRec, store.terminators, rec.owner - 1)
            if rec.value != 0 && !mir_value_valid(idx, store, term.function, rec.value) { return false }
            if !mir_block_valid(idx, store, term.function, rec.target) { return false }
            if rec.kind == mir_operand_terminator_arg() {
                if rec.edge == mir_edge_jump() && (term.kind != mir_term_jump() || rec.target != term.target) { return false }
                if rec.edge == mir_edge_then() && (term.kind != mir_term_branch() || rec.target != term.then_block) { return false }
                if rec.edge == mir_edge_else() && (term.kind != mir_term_branch() || rec.target != term.else_block) { return false }
                if rec.edge > mir_edge_else() { return false }
            }
            if rec.kind == mir_operand_switch_case() {
                if term.kind != mir_term_switch() { return false }
                if rec.name_start != rec.name_end && !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
                if !mir_operand_group_valid(idx, store, mir_operand_switch_case_arg(), at + 1, 0) { return false }
                if rec.value != 0 {
                    var links: U64 = 0
                    if term.function >= 1 && term.function <= __s0_buffer_len(MirFunctionRec, store.functions) {
                        let group = __s0_buffer_get(MirPrintGroup, idx.values, term.function - 1)
                        var k: U64 = 0
                        while k < group.count {
                            let value = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_order, group.first - 1 + k) - 1)
                            if value.function == term.function && value.ordinal + 1 == rec.value && value.def_kind == mir_value_def_switch_case() && value.block == term.block && value.item == rec.ordinal + 1 { links = links + 1 }
                            k = k + 1
                        }
                    } else {
                        var value_at: U64 = 0
                        while value_at < __s0_buffer_len(U64, idx.values_extra) {
                            let value = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, value_at) - 1)
                            if value.function == term.function && value.ordinal + 1 == rec.value && value.def_kind == mir_value_def_switch_case() && value.block == term.block && value.item == rec.ordinal + 1 { links = links + 1 }
                            value_at = value_at + 1
                        }
                    }
                    if links != 1 { return false }
                }
            }
        }
        if rec.kind == mir_operand_switch_case_arg() {
            if !mir_id_valid(rec.owner, __s0_buffer_len(MirOperandRec, store.operands)) { return false }
            let case = __s0_buffer_get(MirOperandRec, store.operands, rec.owner - 1)
            if case.kind != mir_operand_switch_case() || rec.target != case.target { return false }
            let term = __s0_buffer_get(MirTermRec, store.terminators, case.owner - 1)
            if !mir_value_valid(idx, store, term.function, rec.value) { return false }
        }
        at = at + 1
    }
    return true
}

fn mir_store_valid(idx: MirPrintIndex, store: MirStore) -> Bool {
    if mir_format_version() != 6 || !mir_validate_types(idx, store) || !mir_validate_declarations(idx, store) || !mir_validate_functions(idx, store) || !mir_validate_places(idx, store) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if !mir_validate_instruction_refs(idx, store, at + 1, rec) { return false }
        at = at + 1
    }
    return mir_validate_terminators(idx, store) && mir_validate_operands(idx, store) && mir_validate_bindings(idx, store)
}

fn mir_out_name(store: MirStore, start: U64, end: U64) -> Bool { return out_bytes(store.names, start, end) }

fn mir_out_i64_digits(value: I64) -> Bool {
    if value >= 10 { if !mir_out_i64_digits(value / 10) { return false } }
    let digit = value % 10
    if digit == 0 { return out(48) }
    if digit == 1 { return out(49) }
    if digit == 2 { return out(50) }
    if digit == 3 { return out(51) }
    if digit == 4 { return out(52) }
    if digit == 5 { return out(53) }
    if digit == 6 { return out(54) }
    if digit == 7 { return out(55) }
    if digit == 8 { return out(56) }
    return out(57)
}

fn mir_out_u64_digits(value: U64) -> Bool {
    if value >= 10 { if !mir_out_u64_digits(value / 10) { return false } }
    let digit = value % 10
    if digit == 0 { return out(48) }
    if digit == 1 { return out(49) }
    if digit == 2 { return out(50) }
    if digit == 3 { return out(51) }
    if digit == 4 { return out(52) }
    if digit == 5 { return out(53) }
    if digit == 6 { return out(54) }
    if digit == 7 { return out(55) }
    if digit == 8 { return out(56) }
    return out(57)
}

fn mir_out_u64(value: U64) -> Bool {
    return mir_out_u64_digits(value)
}

fn mir_out_i64(value: I64) -> Bool {
    if value == -9223372036854775808 { return out_string("-9223372036854775808") }
    if value < 0 { return out(45) && mir_out_i64_digits(-value) }
    return mir_out_i64_digits(value)
}

fn mir_out_hex_byte(byte: U8) -> Bool {
    return out_hex_nibble(byte / 16) && out_hex_nibble(byte % 16)
}

fn mir_utf8_width(store: MirStore, at: U64, end: U64) -> U64 {
    let first = __s0_buffer_get(U8, store.names, at)
    if first < 128 { return 1 }
    if first >= 194 && first <= 223 && at + 1 < end && __s0_buffer_get(U8, store.names, at + 1) >= 128 && __s0_buffer_get(U8, store.names, at + 1) <= 191 { return 2 }
    if first >= 224 && first <= 239 && at + 2 < end {
        let b1 = __s0_buffer_get(U8, store.names, at + 1)
        let b2 = __s0_buffer_get(U8, store.names, at + 2)
        if b2 >= 128 && b2 <= 191 && ((first == 224 && b1 >= 160 && b1 <= 191) || (first == 237 && b1 >= 128 && b1 <= 159) || ((first >= 225 && first <= 236 || first >= 238) && b1 >= 128 && b1 <= 191)) { return 3 }
    }
    if first >= 240 && first <= 244 && at + 3 < end {
        let b1 = __s0_buffer_get(U8, store.names, at + 1)
        let b2 = __s0_buffer_get(U8, store.names, at + 2)
        let b3 = __s0_buffer_get(U8, store.names, at + 3)
        if b2 >= 128 && b2 <= 191 && b3 >= 128 && b3 <= 191 && ((first == 240 && b1 >= 144 && b1 <= 191) || (first >= 241 && first <= 243 && b1 >= 128 && b1 <= 191) || (first == 244 && b1 >= 128 && b1 <= 143)) { return 4 }
    }
    return 0
}

fn mir_out_quoted(store: MirStore, start: U64, end: U64) -> Bool {
    if !out(34) { return false }
    var at = start
    while at < end {
        let byte = __s0_buffer_get(U8, store.names, at)
        var handled = false
        if byte == 34 || byte == 92 {
            if !out(92) || !out(byte) { return false }
            at = at + 1
            handled = true
        }
        if !handled && byte == 9 {
            if !out_string("\\t") { return false }
            at = at + 1
            handled = true
        }
        if !handled && byte == 10 {
            if !out_string("\\n") { return false }
            at = at + 1
            handled = true
        }
        if !handled && byte == 13 {
            if !out_string("\\r") { return false }
            at = at + 1
            handled = true
        }
        if !handled && byte == 8 {
            if !out_string("\\b") { return false }
            at = at + 1
            handled = true
        }
        if !handled && byte == 12 {
            if !out_string("\\f") { return false }
            at = at + 1
            handled = true
        }
        if !handled && (byte < 32 || byte == 127) {
            if !out_string("\\x") || !mir_out_hex_byte(byte) { return false }
            at = at + 1
            handled = true
        }
        if !handled && byte < 128 {
            if !out(byte) { return false }
            at = at + 1
            handled = true
        }
        if !handled {
            let width = mir_utf8_width(store, at, end)
            if width == 0 {
                if !out_string("\\x") || !mir_out_hex_byte(byte) { return false }
                at = at + 1
            } else {
                if !out_bytes(store.names, at, at + width) { return false }
                at = at + width
            }
        }
    }
    return out(34)
}

fn mir_out_type_part_type(idx: MirPrintIndex, store: MirStore, owner: U64, kind: U64, ordinal: U64, depth: U64) -> Bool {
    let slot = owner
    if slot >= 1 && slot <= __s0_buffer_len(MirTypeRec, store.types) {
        let group = __s0_buffer_get(MirPrintGroup, idx.parts, slot - 1)
        var k: U64 = 0
        while k < group.count {
            let at = __s0_buffer_get(U64, idx.parts_order, group.first - 1 + k)
            let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, at - 1)
            if rec.owner == owner && rec.kind == kind && rec.ordinal == ordinal { return mir_out_type(idx, store, rec.part_type, depth) }
            k = k + 1
        }
        return false
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.parts_extra) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_extra, at) - 1)
        if rec.owner == owner && rec.kind == kind && rec.ordinal == ordinal { return mir_out_type(idx, store, rec.part_type, depth) }
        at = at + 1
    }
    return false
}

fn mir_out_type(idx: MirPrintIndex, store: MirStore, id: U64, depth: U64) -> Bool {
    if depth == 0 { return false }
    if id == mir_type_unit() { return out_string("unit") }
    if id == mir_type_bool() { return out_string("bool") }
    if id == mir_type_i8() { return out_string("i8") }
    if id == mir_type_i16() { return out_string("i16") }
    if id == mir_type_i32() { return out_string("i32") }
    if id == mir_type_i64() { return out_string("i64") }
    if id == mir_type_u8() { return out_string("u8") }
    if id == mir_type_u16() { return out_string("u16") }
    if id == mir_type_u32() { return out_string("u32") }
    if id == mir_type_u64() { return out_string("u64") }
    if id == mir_type_f32() { return out_string("f32") }
    if id == mir_type_f64() { return out_string("f64") }
    let rec = __s0_buffer_get(MirTypeRec, store.types, id - 1)
    if rec.kind == mir_type_kind_aggregate() || rec.kind == mir_type_kind_enum() { return out(64) && mir_out_name(store, rec.name_start, rec.name_end) }
    if rec.kind == mir_type_kind_option() { return out_string("option(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_result() { return out_string("result(") && mir_out_type(idx, store, rec.ok_type, depth - 1) && out_string(", ") && mir_out_type(idx, store, rec.err_type, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_slice() { return out_string("slice(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_safe_ref() { return out_string("safe_ref(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_safe_mut() { return out_string("safe_mut(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_raw_ptr() { return out_string("raw_ptr(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_domain_handle() { return out_string("domain_handle") }
    if rec.kind == mir_type_kind_domain_mark() { return out_string("domain_mark") }
    if rec.kind == mir_type_kind_cleanup_scope() { return out_string("cleanup_scope") }
    if rec.kind == mir_type_kind_cleanup_id() { return out_string("cleanup_id") }
    if rec.kind == mir_type_kind_table() { return out_string("table(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_id() { return out_string("id(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_table_view() { return out_string("table_view(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_table_mut_view() { return out_string("table_mut_view(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_array() { return out_string("array(") && mir_out_type(idx, store, rec.elem, depth - 1) && out_string(", ") && out_u64(rec.length) && out(41) }
    if rec.kind == mir_type_kind_string() { return out_string("string") }
    if rec.kind == mir_type_kind_bytes() { return out_string("bytes") }
    if rec.kind == mir_type_kind_vec() { return out_string("vec(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_c_raw() { return mir_out_c_scalar(rec.length) }
    if rec.kind == mir_type_kind_c_ptr() { return out_string("c_ptr(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_c_const_ptr() { return out_string("c_const_ptr(") && mir_out_type(idx, store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_c_named() { return out(64) && mir_out_name(store, rec.name_start, rec.name_end) }
    if rec.kind == mir_type_kind_c_string() { return out_string("c_string") }
    if rec.kind == mir_type_kind_c_callback_owner() {
        if !out_string("c_callback_owner(") || !mir_out_type(idx, store, rec.elem, depth - 1) || !out_string(", ") || !mir_out_type(idx, store, rec.result_type, depth - 1) { return false }
        return out(41)
    }
    if rec.kind == mir_type_kind_function() {
        if !out_string("function(fn(") { return false }
        let param_count = mir_type_part_count_at(idx, store, id, mir_type_part_function_param())
        var ordinal: U64 = 0
        while ordinal < param_count {
            if ordinal > 0 && !out_string(", ") { return false }
            if !mir_out_type_part_type(idx, store, id, mir_type_part_function_param(), ordinal, depth - 1) { return false }
            ordinal = ordinal + 1
        }
        if !out_string(") -> ") || !mir_out_type(idx, store, rec.result_type, depth - 1) { return false }
        if mir_type_part_count_at(idx, store, id, mir_type_part_function_env()) != 0 {
            if !out_string(", ") || !mir_out_type_part_type(idx, store, id, mir_type_part_function_env(), 0, depth - 1) { return false }
        }
        return out(41)
    }
    return false
}

fn mir_out_value(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.values, function - 1)
        var k: U64 = 0
        while k < group.count {
            let at = __s0_buffer_get(U64, idx.values_order, group.first - 1 + k)
            let rec = __s0_buffer_get(MirValueRec, store.values, at - 1)
            if rec.function == function && rec.ordinal + 1 == id { return out(37) && mir_out_name(store, rec.name_start, rec.name_end) }
            k = k + 1
        }
        return false
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.values_extra) {
        let rec = __s0_buffer_get(MirValueRec, store.values, __s0_buffer_get(U64, idx.values_extra, at) - 1)
        if rec.function == function && rec.ordinal + 1 == id { return out(37) && mir_out_name(store, rec.name_start, rec.name_end) }
        at = at + 1
    }
    return false
}

fn mir_out_block_name(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.blocks, function - 1)
        var k: U64 = 0
        while k < group.count {
            let at = __s0_buffer_get(U64, idx.blocks_order, group.first - 1 + k)
            let rec = __s0_buffer_get(MirBlockRec, store.blocks, at - 1)
            if rec.function == function && rec.ordinal + 1 == id { return mir_out_name(store, rec.name_start, rec.name_end) }
            k = k + 1
        }
        return false
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.blocks_extra) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, __s0_buffer_get(U64, idx.blocks_extra, at) - 1)
        if rec.function == function && rec.ordinal + 1 == id { return mir_out_name(store, rec.name_start, rec.name_end) }
        at = at + 1
    }
    return false
}

fn mir_out_local_name(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    if function >= 1 && function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let group = __s0_buffer_get(MirPrintGroup, idx.locals, function - 1)
        var k: U64 = 0
        while k < group.count {
            let at = __s0_buffer_get(U64, idx.locals_order, group.first - 1 + k)
            let rec = __s0_buffer_get(MirLocalRec, store.locals, at - 1)
            if rec.function == function && rec.ordinal + 1 == id { return mir_out_name(store, rec.name_start, rec.name_end) }
            k = k + 1
        }
        return false
    }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, idx.locals_extra) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, __s0_buffer_get(U64, idx.locals_extra, at) - 1)
        if rec.function == function && rec.ordinal + 1 == id { return mir_out_name(store, rec.name_start, rec.name_end) }
        at = at + 1
    }
    return false
}

fn mir_out_place(idx: MirPrintIndex, store: MirStore, function: U64, id: U64) -> Bool {
    let rec = __s0_buffer_get(MirPlaceRec, store.places, id - 1)
    if rec.kind == mir_place_local() { return out_string("local %") && mir_out_local_name(idx, store, function, rec.local) }
    if rec.kind == mir_place_field() { return out_string("field(") && mir_out_place(idx, store, function, rec.base) && out_string(", ") && mir_out_name(store, rec.field_start, rec.field_end) && out(41) }
    return out_string("deref ") && mir_out_value(idx, store, function, rec.deref_value)
}

fn mir_out_operand_values(idx: MirPrintIndex, store: MirStore, kind: U64, owner: U64, edge: U64, function: U64) -> Bool {
    let count = mir_print_operand_count(idx, store, kind, owner, edge)
    let slot = mir_print_operand_slot(store, kind, owner)
    var ordinal: U64 = 0
    while ordinal < count {
        if slot != 0 {
            let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
            var k: U64 = 0
            while k < group.count {
                let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
                if rec.kind == kind && rec.owner == owner && rec.edge == edge && rec.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !mir_out_value(idx, store, function, rec.value) { return false }
                }
                k = k + 1
            }
        } else {
            var at: U64 = 0
            while at < __s0_buffer_len(U64, idx.operand_extra) {
                let rec = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, at) - 1)
                if rec.kind == kind && rec.owner == owner && rec.edge == edge && rec.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !mir_out_value(idx, store, function, rec.value) { return false }
                }
                at = at + 1
            }
        }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_out_block_ref(idx: MirPrintIndex, store: MirStore, function: U64, target: U64, kind: U64, owner: U64, edge: U64) -> Bool {
    if !mir_out_block_name(idx, store, function, target) { return false }
    if mir_print_operand_count(idx, store, kind, owner, edge) > 0 { return out(40) && mir_out_operand_values(idx, store, kind, owner, edge, function) && out(41) }
    return true
}

fn mir_out_function_name(store: MirStore, id: U64) -> Bool {
    let rec = __s0_buffer_get(MirFunctionRec, store.functions, id - 1)
    return mir_out_name(store, rec.name_start, rec.name_end)
}

fn mir_out_import_name(store: MirStore, id: U64) -> Bool {
    let rec = __s0_buffer_get(MirImportRec, store.imports, id - 1)
    return mir_out_name(store, rec.name_start, rec.name_end)
}

fn mir_out_op(op: U64) -> Bool {
    if op == 0 { return out_string("load") }
    if op == 1 { return out_string("store") }
    if op == 2 { return out_string("aggregate.construct") }
    if op == 3 { return out_string("domain.create") }
    if op == 4 { return out_string("domain.mark") }
    if op == 5 { return out_string("domain.reset") }
    if op == 6 { return out_string("domain.destroy") }
    if op == 7 { return out_string("alloc") }
    if op == 8 { return out_string("alloc.checked") }
    if op == 9 { return out_string("copy_to_domain") }
    if op == 10 { return out_string("cleanup.scope.begin") }
    if op == 11 { return out_string("cleanup.push") }
    if op == 12 { return out_string("cleanup.disarm") }
    if op == 13 { return out_string("cleanup.scope.run") }
    if op == 14 { return out_string("cleanup.scope.end") }
    if op == 15 { return out_string("int.add.checked") }
    if op == 16 { return out_string("int.sub.checked") }
    if op == 17 { return out_string("int.mul.checked") }
    if op == 18 { return out_string("int.div.checked") }
    if op == 19 { return out_string("int.shl.checked") }
    if op == 20 { return out_string("int.shr.checked") }
    if op == 21 { return out_string("slice.len") }
    if op == 22 { return out_string("slice.index.checked") }
    if op == 23 { return out_string("slice.range.checked") }
    if op == 24 { return out_string("enum.payload.checked") }
    if op == 25 { return out_string("enum.construct") }
    if op == 26 { return out_string("table.create") }
    if op == 27 { return out_string("table.insert") }
    if op == 28 { return out_string("table.lookup") }
    if op == 29 { return out_string("table.lookup_mut") }
    if op == 30 { return out_string("table.remove") }
    if op == 31 { return out_string("table.view.end") }
    if op == 32 { return out_string("int.eq") }
    if op == 33 { return out_string("int.ne") }
    if op == 34 { return out_string("int.lt") }
    if op == 35 { return out_string("int.le") }
    if op == 36 { return out_string("int.gt") }
    if op == 37 { return out_string("int.ge") }
    if op == 38 { return out_string("float.eq") }
    if op == 39 { return out_string("float.ne") }
    if op == 40 { return out_string("float.lt") }
    if op == 41 { return out_string("float.le") }
    if op == 42 { return out_string("float.gt") }
    if op == 43 { return out_string("float.ge") }
    if op == 44 { return out_string("int.trunc") }
    if op == 45 { return out_string("int.zext") }
    if op == 46 { return out_string("int.sext") }
    if op == 47 { return out_string("float.convert") }
    if op == 48 { return out_string("int.from_float") }
    if op == 49 { return out_string("float.from_int") }
    if op == 50 { return out_string("const.get") }
    if op == 51 { return out_string("call") }
    if op == 65 { return out_string("call.value") }
    if op == 66 { return out_string("str.eq") }
    if op == 67 { return out_string("fn.value") }
    if op == 68 { return out_string("table.insert.try") }
    if op == 69 { return out_string("c.call.unsafe") }
    if op == 70 { return out_string("c.is_null") }
    if op == 71 { return out_string("int.add.try") }
    if op == 72 { return out_string("int.sub.try") }
    if op == 73 { return out_string("int.mul.try") }
    if op == 74 { return out_string("int.add.saturating") }
    if op == 75 { return out_string("int.sub.saturating") }
    if op == 76 { return out_string("int.mul.saturating") }
    if op == 77 { return out_string("int.add.wrapping") }
    if op == 78 { return out_string("int.sub.wrapping") }
    if op == 79 { return out_string("int.mul.wrapping") }
    if op == 80 { return out_string("str.len") }
    if op == 81 { return out_string("str.byte.checked") }
    if op == 82 { return out_string("str.concat") }
    if op == 83 { return out_string("str.slice.checked") }
    if op == 84 { return out_string("str.to_bytes") }
    if op == 85 { return out_string("str.from_bytes") }
    if op == 86 { return out_string("int.convert.checked") }
    if op == 87 { return out_string("int.convert.wrap") }
    if op == 88 { return out_string("c.num.try") }
    if op == 89 { return out_string("c.num.wrap") }
    if op == 90 { return out_string("c.num.cast") }
    if op == 91 { return out_string("float.add") }
    if op == 92 { return out_string("float.sub") }
    if op == 93 { return out_string("float.mul") }
    if op == 94 { return out_string("float.div") }
    if op == 95 { return out_string("str.order_lt") }
    if op == 96 { return out_string("c.field.get") }
    if op == 97 { return out_string("c.field.set") }
    if op == 98 { return out_string("c.string.make_lit") }
    if op == 99 { return out_string("c.string.make") }
    if op == 100 { return out_string("c.string.ptr") }
    if op == 101 { return out_string("c.string.release") }
    if op == 102 { return out_string("str.display") }
    if op == 103 { return out_string("int.and") }
    if op == 104 { return out_string("int.or") }
    if op == 105 { return out_string("int.xor") }
    if op == 106 { return out_string("int.not") }
    if op == 107 { return out_string("c.buffer.ptr") }
    if op == 108 { return out_string("slice.to_bytes") }
    if op == 109 { return out_string("c.zero") }
    if op == 110 { return out_string("c.addr") }
    if op == 111 { return out_string("c.callback.make") }
    if op == 112 { return out_string("c.callback.owner.register") }
    if op == 114 { return out_string("c.callback.owner.release") }
    if op == 52 { return out_string("ffi.call.unsafe") }
    if op == 53 { return out_string("borrow") }
    if op == 54 { return out_string("borrow_mut") }
    if op == 55 { return out_string("array.index.checked") }
    if op == 56 { return out_string("vec.new") }
    if op == 57 { return out_string("vec.construct.checked") }
    if op == 58 { return out_string("vec.grow.checked") }
    if op == 59 { return out_string("vec.len") }
    if op == 60 { return out_string("vec.capacity") }
    if op == 61 { return out_string("vec.storage") }
    if op == 62 { return out_string("vec.as_slice") }
    if op == 63 { return out_string("vec.as_mut_slice") }
    return out_string("array.as_slice")
}

fn mir_out_c_scalar(id: U64) -> Bool {
    if id == 0 { return out_string("c_char") }
    if id == 1 { return out_string("c_schar") }
    if id == 2 { return out_string("c_uchar") }
    if id == 3 { return out_string("c_short") }
    if id == 4 { return out_string("c_ushort") }
    if id == 5 { return out_string("c_int") }
    if id == 6 { return out_string("c_uint") }
    if id == 7 { return out_string("c_long") }
    if id == 8 { return out_string("c_ulong") }
    if id == 9 { return out_string("c_llong") }
    if id == 10 { return out_string("c_ullong") }
    if id == 11 { return out_string("c_float") }
    if id == 12 { return out_string("c_double") }
    if id == 13 { return out_string("c_size") }
    return out_string("c_ptrdiff")
}

fn mir_out_binding_name(store: MirStore, id: U64) -> Bool {
    if !mir_id_valid(id, __s0_buffer_len(MirBindingRec, store.bindings)) { return false }
    let rec = __s0_buffer_get(MirBindingRec, store.bindings, id - 1)
    return mir_out_name(store, rec.name_start, rec.name_end)
}

// The external flat binding-function index resolves block-major: walk the
// blocks subtracting each block's function count until the index lands.
fn mir_out_binding_fn_name(store: MirStore, id: U64) -> Bool {
    if !mir_id_valid(id, __s0_buffer_len(MirBindingFnRec, store.binding_funcs)) { return false }
    let rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, id - 1)
    if !mir_out_binding_name(store, rec.block) { return false }
    if !out_string(".") { return false }
    return mir_out_name(store, rec.name_start, rec.name_end)
}

fn mir_binding_fn_valid(store: MirStore, id: U64) -> Bool {
    if !mir_id_valid(id, __s0_buffer_len(MirBindingFnRec, store.binding_funcs)) { return false }
    let rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, id - 1)
    return mir_id_valid(rec.block, __s0_buffer_len(MirBindingRec, store.bindings)) && mir_type_valid(store, rec.result_type)
}

fn mir_out_fail_edge(idx: MirPrintIndex, store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if !out_string(" else ") { return false }
    return mir_out_block_ref(idx, store, rec.function, rec.target, mir_operand_checked_edge_arg(), id, 0)
}

fn mir_out_instruction(idx: MirPrintIndex, store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if !out_string("  ") { return false }
    if rec.result != 0 && (!mir_out_value(idx, store, rec.function, rec.result) || !out_string(" = ")) { return false }
    if !mir_out_op(rec.op) { return false }
    if rec.op == mir_op_load() || rec.op == mir_op_borrow() || rec.op == mir_op_borrow_mut() {
        if !out(32) || !mir_out_place(idx, store, rec.function, rec.place) { return false }
    }
    if rec.op == mir_op_store() {
        if !out(32) || !mir_out_place(idx, store, rec.function, rec.place) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_aggregate_construct() {
        if !out(32) || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(" { ") { return false }
        let count = mir_print_operand_count(idx, store, mir_operand_aggregate_field(), id, 0)
        let slot = mir_print_operand_slot(store, mir_operand_aggregate_field(), id)
        var ordinal: U64 = 0
        while ordinal < count {
            if slot != 0 {
                let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
                var k: U64 = 0
                while k < group.count {
                    let field = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
                    if field.kind == mir_operand_aggregate_field() && field.owner == id && field.ordinal == ordinal {
                        if ordinal > 0 && !out_string(", ") { return false }
                        let aggregate = __s0_buffer_get(MirTypeRec, store.types, rec.type_op - 1)
                        if aggregate.kind != mir_type_kind_array() && (!mir_out_name(store, field.name_start, field.name_end) || !out_string(": ")) { return false }
                        if !mir_out_value(idx, store, rec.function, field.value) { return false }
                    }
                    k = k + 1
                }
            } else {
                var at: U64 = 0
                while at < __s0_buffer_len(U64, idx.operand_extra) {
                    let field = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, at) - 1)
                    if field.kind == mir_operand_aggregate_field() && field.owner == id && field.ordinal == ordinal {
                        if ordinal > 0 && !out_string(", ") { return false }
                        let aggregate = __s0_buffer_get(MirTypeRec, store.types, rec.type_op - 1)
                        if aggregate.kind != mir_type_kind_array() && (!mir_out_name(store, field.name_start, field.name_end) || !out_string(": ")) { return false }
                        if !mir_out_value(idx, store, rec.function, field.value) { return false }
                    }
                    at = at + 1
                }
            }
            ordinal = ordinal + 1
        }
        if !out_string(" }") { return false }
    }
    if rec.op == mir_op_domain_create() || rec.op == mir_op_domain_mark() || rec.op == mir_op_domain_destroy() || rec.op == mir_op_slice_len() || rec.op == mir_op_cleanup_disarm() || rec.op == mir_op_cleanup_scope_run() || rec.op == mir_op_cleanup_scope_end() || rec.op == mir_op_table_view_end() || (rec.op >= mir_op_vec_len() && rec.op <= mir_op_vec_as_mut_slice()) || rec.op == mir_op_array_as_slice() || rec.op == mir_op_str_len() || rec.op == mir_op_str_to_bytes() || rec.op == mir_op_int_not() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_domain_reset() || (rec.op >= mir_op_int_eq() && rec.op <= mir_op_float_ge()) || rec.op == mir_op_table_insert() || rec.op == mir_op_table_insert_try() || rec.op == mir_op_table_lookup() || rec.op == mir_op_table_lookup_mut() || rec.op == mir_op_table_remove() || (rec.op >= mir_op_int_and() && rec.op <= mir_op_int_xor()) {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_alloc() || rec.op == mir_op_alloc_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
        if rec.op == mir_op_alloc_checked() && !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_copy_to_domain() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_cleanup_push() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", @") || !mir_out_function_name(store, rec.target) || !out_string(", (") || !mir_out_operand_values(idx, store, mir_operand_instruction(), id, 0, rec.function) || !out(41) { return false }
        if rec.place != 0 && rec.op != mir_op_c_callback_owner_register() && rec.op != mir_op_c_callback_owner_release() {
            if !out_string(" place ") || !mir_out_place(idx, store, rec.function, rec.place) { return false }
        }
    }
    if rec.op >= mir_op_int_add_checked() && rec.op <= mir_op_int_shr_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op >= mir_op_int_add_try() && rec.op <= mir_op_int_mul_wrapping() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op >= mir_op_float_add() && rec.op <= mir_op_float_div() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_slice_index_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_array_index_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_slice_range_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.c) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_vec_new() {
        if !out(32) || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_vec_construct_checked() || rec.op == mir_op_vec_grow_checked() || rec.op == mir_op_str_concat() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.c) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_str_byte_checked() || rec.op == mir_op_str_from_bytes() || rec.op == mir_op_str_display() || rec.op == mir_op_slice_to_bytes() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_str_slice_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.c) || !out_string(", ") || !mir_out_operand_values(idx, store, mir_operand_instruction(), id, 0, rec.function) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_enum_payload_checked() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_name(store, rec.name_start, rec.name_end) || !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_enum_construct() {
        if !out(32) || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(", ") || !mir_out_name(store, rec.name_start, rec.name_end) { return false }
        if rec.a != 0 && (!out_string(", ") || !mir_out_value(idx, store, rec.function, rec.a)) { return false }
    }
    if rec.op == mir_op_table_create() {
        if !out(32) || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op >= mir_op_int_trunc() && rec.op <= mir_op_float_from_int() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_int_convert_checked() || rec.op == mir_op_int_convert_wrap() || (rec.op >= mir_op_c_num_try() && rec.op <= mir_op_c_num_cast()) {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_field_get() {
        if !out(32) || !mir_out_name(store, rec.name_start, rec.name_end) || !out(40) || !mir_out_value(idx, store, rec.function, rec.a) || !out(41) { return false }
    }
    if rec.op == mir_op_c_field_set() {
        if !out(32) || !mir_out_name(store, rec.name_start, rec.name_end) || !out(32) || !mir_out_place(idx, store, rec.function, rec.place) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op >= mir_op_c_string_make_lit() && rec.op <= mir_op_c_string_release() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_c_buffer_ptr() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_zero() {
        if !out(32) || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_addr() {
        if !out(32) || !mir_out_place(idx, store, rec.function, rec.place) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_callback_make() {
        if !out_string(" @") || !mir_out_function_name(store, rec.target) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_callback_owner_register() {
        if !out_string(" @") || !mir_out_function_name(store, rec.target) || !out_string(", ") || !mir_out_binding_fn_name(store, rec.b) || !out_string(", ") || !mir_out_binding_fn_name(store, rec.c) || !out_string(", ") || !mir_out_binding_fn_name(store, rec.place) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_callback_owner_release() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_binding_fn_name(store, rec.b) || !out_string(", ") || !mir_out_binding_fn_name(store, rec.c) || !out_string(", ") || !mir_out_type(idx, store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_c_string_make_lit() || rec.op == mir_op_c_string_make() {
        if !mir_out_fail_edge(idx, store, id, rec) { return false }
    }
    if rec.op == mir_op_const_get() {
        if !out_string(" @") || !mir_out_name(store, rec.name_start, rec.name_end) { return false }
    }
    if rec.op == mir_op_call() || rec.op == mir_op_ffi_call_unsafe() || rec.op == mir_op_c_binding_call() {
        if !out_string(" @") { return false }
        if rec.op == mir_op_call() {
            if !mir_out_function_name(store, rec.target) { return false }
        }
        if rec.op == mir_op_ffi_call_unsafe() && !mir_out_import_name(store, rec.target) { return false }
        if rec.op == mir_op_c_binding_call() && !mir_out_binding_fn_name(store, rec.target) { return false }
        if !out(40) || !mir_out_operand_values(idx, store, mir_operand_instruction(), id, 0, rec.function) || !out(41) { return false }
    }
    if rec.op == mir_op_call_value() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out(40) || !mir_out_operand_values(idx, store, mir_operand_instruction(), id, 0, rec.function) || !out(41) { return false }
    }
    if rec.op == mir_op_str_eq() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_str_order_lt() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(idx, store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_c_is_null() {
        if !out(32) || !mir_out_value(idx, store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_fn_value() {
        if !out_string(" @") || !mir_out_function_name(store, rec.target) { return false }
        if rec.a != 0 {
            if !out(40) || !mir_out_value(idx, store, rec.function, rec.a) || !out(41) { return false }
        }
        if rec.type_op == mir_fn_value_domain_marker() {
            if !out_string(" domain") { return false }
        }
    }
    return out(10)
}

fn mir_out_terminator(idx: MirPrintIndex, store: MirStore, id: U64, rec: MirTermRec) -> Bool {
    if !out_string("  ") { return false }
    if rec.kind == mir_term_jump() {
        if !out_string("jump ") || !mir_out_block_ref(idx, store, rec.function, rec.target, mir_operand_terminator_arg(), id, mir_edge_jump()) { return false }
    }
    if rec.kind == mir_term_branch() {
        if !out_string("branch ") || !mir_out_value(idx, store, rec.function, rec.value) || !out_string(", ") || !mir_out_block_ref(idx, store, rec.function, rec.then_block, mir_operand_terminator_arg(), id, mir_edge_then()) || !out_string(", ") || !mir_out_block_ref(idx, store, rec.function, rec.else_block, mir_operand_terminator_arg(), id, mir_edge_else()) { return false }
    }
    if rec.kind == mir_term_switch() {
        if !out_string("switch ") || !mir_out_value(idx, store, rec.function, rec.value) || !out_string(" {\n") { return false }
        let count = mir_print_operand_count(idx, store, mir_operand_switch_case(), id, 0)
        let slot = mir_print_operand_slot(store, mir_operand_switch_case(), id)
        var ordinal: U64 = 0
        while ordinal < count {
            if slot != 0 {
                let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
                var k: U64 = 0
                while k < group.count {
                    let case_at = __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k)
                    let case = __s0_buffer_get(MirOperandRec, store.operands, case_at - 1)
                    if case.kind == mir_operand_switch_case() && case.owner == id && case.ordinal == ordinal {
                        if !out_string("    ") { return false }
                        if case.name_start == case.name_end {
                            if !out_string("default") { return false }
                        } else {
                            if !mir_out_name(store, case.name_start, case.name_end) { return false }
                            if case.value != 0 && (!out(40) || !mir_out_value(idx, store, rec.function, case.value) || !out(41)) { return false }
                        }
                        if !out_string(" -> ") || !mir_out_block_ref(idx, store, rec.function, case.target, mir_operand_switch_case_arg(), case_at, 0) || !out(10) { return false }
                    }
                    k = k + 1
                }
            } else {
                var at: U64 = 0
                while at < __s0_buffer_len(U64, idx.operand_extra) {
                    let case_at = __s0_buffer_get(U64, idx.operand_extra, at)
                    let case = __s0_buffer_get(MirOperandRec, store.operands, case_at - 1)
                    if case.kind == mir_operand_switch_case() && case.owner == id && case.ordinal == ordinal {
                        if !out_string("    ") { return false }
                        if case.name_start == case.name_end {
                            if !out_string("default") { return false }
                        } else {
                            if !mir_out_name(store, case.name_start, case.name_end) { return false }
                            if case.value != 0 && (!out(40) || !mir_out_value(idx, store, rec.function, case.value) || !out(41)) { return false }
                        }
                        if !out_string(" -> ") || !mir_out_block_ref(idx, store, rec.function, case.target, mir_operand_switch_case_arg(), case_at, 0) || !out(10) { return false }
                    }
                    at = at + 1
                }
            }
            ordinal = ordinal + 1
        }
        if !out_string("  }") { return false }
    }
    if rec.kind == mir_term_return() {
        if !out_string("return") { return false }
        if rec.value != 0 && (!out(32) || !mir_out_value(idx, store, rec.function, rec.value)) { return false }
    }
    if rec.kind == mir_term_fail() {
        if !out_string("fail ") || !mir_out_value(idx, store, rec.function, rec.value) { return false }
    }
    if rec.kind == mir_term_panic() {
        if !out_string("panic") { return false }
    }
    if rec.kind == mir_term_unreachable() && !out_string("unreachable") { return false }
    return out(10)
}

fn mir_out_param_group(idx: MirPrintIndex, store: MirStore, kind: U64, function: U64, block: U64) -> Bool {
    let count = mir_param_group_count(idx, store, kind, function, block)
    let slot = mir_print_param_slot(store, function, kind)
    var ordinal: U64 = 0
    while ordinal < count {
        if slot != 0 {
            let group = __s0_buffer_get(MirPrintGroup, idx.params, slot - 1)
            var k: U64 = 0
            while k < group.count {
                let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_order, group.first - 1 + k) - 1)
                if rec.kind == kind && rec.function == function && rec.block == block && rec.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !out(37) || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(": ") || !mir_out_type(idx, store, rec.param_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                }
                k = k + 1
            }
        } else {
            var at: U64 = 0
            while at < __s0_buffer_len(U64, idx.params_extra) {
                let rec = __s0_buffer_get(MirParamRec, store.params, __s0_buffer_get(U64, idx.params_extra, at) - 1)
                if rec.kind == kind && rec.function == function && rec.block == block && rec.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !out(37) || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(": ") || !mir_out_type(idx, store, rec.param_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                }
                at = at + 1
            }
        }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_out_type_declarations(idx: MirPrintIndex, store: MirStore) -> Bool {
    var id = mir_primitive_type_count() + 1
    while id <= __s0_buffer_len(MirTypeRec, store.types) {
        let rec = __s0_buffer_get(MirTypeRec, store.types, id - 1)
        if rec.kind == mir_type_kind_aggregate() || rec.kind == mir_type_kind_enum() {
            if rec.kind == mir_type_kind_aggregate() && !out_string("\ntype @") { return false }
            if rec.kind == mir_type_kind_enum() && !out_string("\nenum @") { return false }
            if !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(" {\n") { return false }
            var kind = mir_type_part_variant()
            if rec.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
            let count = mir_type_part_count_at(idx, store, id, kind)
            let slot = id
            var ordinal: U64 = 0
            while ordinal < count {
                let group = __s0_buffer_get(MirPrintGroup, idx.parts, slot - 1)
                var k: U64 = 0
                while k < group.count {
                    let at = __s0_buffer_get(U64, idx.parts_order, group.first - 1 + k)
                    let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at - 1)
                    if part.owner == id && part.kind == kind && part.ordinal == ordinal {
                        if !out_string("  ") || !mir_out_name(store, part.name_start, part.name_end) { return false }
                        if kind == mir_type_part_field() {
                            if !out_string(": ") || !mir_out_type(idx, store, part.part_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                        }
                        if kind == mir_type_part_variant() && part.part_type != mir_type_unit() && (!out(40) || !mir_out_type(idx, store, part.part_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(41)) { return false }
                        if !out(10) { return false }
                    }
                    k = k + 1
                }
                ordinal = ordinal + 1
            }
            if !out_string("}\n") { return false }
        }
        id = id + 1
    }
    return true
}

fn mir_out_declarations(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let rec = __s0_buffer_get(MirConstRec, store.constants, at)
        if !out_string("\nconst @") || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(": ") || !mir_out_type(idx, store, rec.const_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(" = ") { return false }
        if rec.kind == mir_const_unit() {
            if !out_string("()") { return false }
        }
        if rec.kind == mir_const_bool() {
            if rec.bool_value == 0 && !out_string("false") { return false }
            if rec.bool_value == 1 && !out_string("true") { return false }
        }
        if rec.kind == mir_const_int() {
            if rec.const_type == mir_type_u64() && rec.int_value < 0 {
                // The signed field holds the 64-bit pattern of a value
                // above INT64_MAX; the printed form is the pattern's
                // unsigned decimal.
                let bits = unsafe c { alderhost_u64_from_i64_bits(rec.int_value) }
                if !mir_out_u64(bits) { return false }
            } else {
                if !mir_out_i64(rec.int_value) { return false }
            }
        }
        if rec.kind == mir_const_float() {
            if !unsafe c { alderhost_stdout_f64_bits(rec.float_bits) } { return false }
        }
        if rec.kind == mir_const_string() && !mir_out_quoted(store, rec.string_start, rec.string_end) { return false }
        if !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let rec = __s0_buffer_get(MirImportRec, store.imports, at)
        if !out_string("\nimport @") || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(": fn(") { return false }
        let count = mir_print_operand_count(idx, store, mir_operand_import_param(), at + 1, 0)
        let slot = mir_print_operand_slot(store, mir_operand_import_param(), at + 1)
        var ordinal: U64 = 0
        while ordinal < count {
            if slot != 0 {
                let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
                var k: U64 = 0
                while k < group.count {
                    let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
                    if operand.kind == mir_operand_import_param() && operand.owner == at + 1 && operand.ordinal == ordinal {
                        if ordinal > 0 && !out_string(", ") { return false }
                        if !mir_out_type(idx, store, operand.operand_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                    }
                    k = k + 1
                }
            } else {
                var operand_at: U64 = 0
                while operand_at < __s0_buffer_len(U64, idx.operand_extra) {
                    let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, operand_at) - 1)
                    if operand.kind == mir_operand_import_param() && operand.owner == at + 1 && operand.ordinal == ordinal {
                        if ordinal > 0 && !out_string(", ") { return false }
                        if !mir_out_type(idx, store, operand.operand_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                    }
                    operand_at = operand_at + 1
                }
            }
            ordinal = ordinal + 1
        }
        if !out_string(") -> ") || !mir_out_type(idx, store, rec.result_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(10) { return false }
        at = at + 1
    }
    return true
}

// One C binding-function signature's parameter list, in ordinal order.
fn mir_out_binding_params(idx: MirPrintIndex, store: MirStore, fn_id: U64) -> Bool {
    let count = mir_print_operand_count(idx, store, mir_operand_binding_param(), fn_id, 0)
    let slot = mir_print_operand_slot(store, mir_operand_binding_param(), fn_id)
    var ordinal: U64 = 0
    while ordinal < count {
        if slot != 0 {
            let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
            var k: U64 = 0
            while k < group.count {
                let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
                if operand.kind == mir_operand_binding_param() && operand.owner == fn_id && operand.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !mir_out_type(idx, store, operand.operand_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                }
                k = k + 1
            }
        } else {
            var operand_at: U64 = 0
            while operand_at < __s0_buffer_len(U64, idx.operand_extra) {
                let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, operand_at) - 1)
                if operand.kind == mir_operand_binding_param() && operand.owner == fn_id && operand.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !mir_out_type(idx, store, operand.operand_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                }
                operand_at = operand_at + 1
            }
        }
        ordinal = ordinal + 1
    }
    return true
}

// The spelling after "= " is omitted when it duplicates the Alder member
// name, matching the Go printer exactly.
fn mir_out_binding_spelling(store: MirStore, name_start: U64, name_end: U64, c_name_start: U64, c_name_end: U64) -> Bool {
    if name_start == c_name_start && name_end == c_name_end { return true }
    if !out_string(" = ") { return false }
    return mir_out_quoted(store, c_name_start, c_name_end)
}

fn mir_out_binding_types(idx: MirPrintIndex, store: MirStore, block_id: U64) -> Bool {
    let count = mir_print_operand_count(idx, store, mir_operand_binding_type(), block_id, 0)
    let slot = mir_print_operand_slot(store, mir_operand_binding_type(), block_id)
    var ordinal: U64 = 0
    while ordinal < count {
        var found = false
        if slot != 0 {
            let group = __s0_buffer_get(MirPrintGroup, idx.operand, slot - 1)
            var k: U64 = 0
            while k < group.count {
                let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_order, group.first - 1 + k) - 1)
                if operand.kind == mir_operand_binding_type() && operand.owner == block_id && operand.ordinal == ordinal {
                    found = true
                    if !mir_out_binding_type_member(idx, store, operand.operand_type) { return false }
                }
                k = k + 1
            }
        }
        if !found {
            var operand_at: U64 = 0
            while operand_at < __s0_buffer_len(U64, idx.operand_extra) {
                let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, idx.operand_extra, operand_at) - 1)
                if operand.kind == mir_operand_binding_type() && operand.owner == block_id && operand.ordinal == ordinal {
                    found = true
                    if !mir_out_binding_type_member(idx, store, operand.operand_type) { return false }
                }
                operand_at = operand_at + 1
            }
        }
        if !found { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_out_binding_type_member(idx: MirPrintIndex, store: MirStore, type_id: U64) -> Bool {
    if !mir_type_valid(store, type_id) { return false }
    let rec = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if rec.kind != mir_type_kind_c_named() { return false }
    if !out_string("  c_type ") { return false }
    if rec.c_class == mir_c_class_scalar() && !out_string("scalar ") { return false }
    if rec.c_class == mir_c_class_opaque() && !out_string("opaque ") { return false }
    if rec.c_class == mir_c_class_record() && !out_string("record ") { return false }
    if rec.c_class == mir_c_class_callback() && !out_string("callback ") { return false }
    if !out_string("@") || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(" = ") || !mir_out_quoted(store, rec.c_name_start, rec.c_name_end) { return false }
    if rec.c_class != mir_c_class_record() { return out(10) }
    if !out_string(" {") { return false }
    let field_count = mir_type_part_count_at(idx, store, type_id, mir_type_part_c_field())
    var ordinal: U64 = 0
    while ordinal < field_count {
        if !mir_out_c_field(idx, store, type_id, ordinal) { return false }
        ordinal = ordinal + 1
    }
    if field_count > 0 && !out_string(" ") { return false }
    return out_string("}") && out(10)
}

fn mir_out_c_field(idx: MirPrintIndex, store: MirStore, type_id: U64, ordinal: U64) -> Bool {
    let slot = type_id
    var k: U64 = 0
    if slot >= 1 && slot <= __s0_buffer_len(MirTypeRec, store.types) {
        let group = __s0_buffer_get(MirPrintGroup, idx.parts, slot - 1)
        while k < group.count {
            let at = __s0_buffer_get(U64, idx.parts_order, group.first - 1 + k)
            let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at - 1)
            if part.owner == type_id && part.kind == mir_type_part_c_field() && part.ordinal == ordinal {
                if ordinal > 0 && !out_string(",") { return false }
                if !out_string(" ") || !mir_out_name(store, part.name_start, part.name_end) || !out_string(": ") || !mir_out_type(idx, store, part.part_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                if part.name_start != part.c_name_start || part.name_end != part.c_name_end {
                    if !out_string(" = ") || !mir_out_quoted(store, part.c_name_start, part.c_name_end) { return false }
                }
                return true
            }
            k = k + 1
        }
        return false
    }
    var at2: U64 = 0
    while at2 < __s0_buffer_len(U64, idx.parts_extra) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, __s0_buffer_get(U64, idx.parts_extra, at2) - 1)
        if part.owner == type_id && part.kind == mir_type_part_c_field() && part.ordinal == ordinal {
            if ordinal > 0 && !out_string(",") { return false }
            if !out_string(" ") || !mir_out_name(store, part.name_start, part.name_end) || !out_string(": ") || !mir_out_type(idx, store, part.part_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
            if part.name_start != part.c_name_start || part.name_end != part.c_name_end {
                if !out_string(" = ") || !mir_out_quoted(store, part.c_name_start, part.c_name_end) { return false }
            }
            return true
        }
        at2 = at2 + 1
    }
    return false
}

fn mir_out_bindings(idx: MirPrintIndex, store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirBindingRec, store.bindings) {
        let block_id = at + 1
        let rec = __s0_buffer_get(MirBindingRec, store.bindings, at)
        if !out_string("\nbinding @") || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(" ") || !mir_out_quoted(store, rec.header_start, rec.header_end) || !out_string(" {\n") { return false }
        if !mir_out_binding_types(idx, store, block_id) { return false }
        var fn_at: U64 = 0
        while fn_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
            let fn_rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, fn_at)
            if fn_rec.block == block_id {
                if !out_string("  c_fn @") || !mir_out_name(store, fn_rec.name_start, fn_rec.name_end) || !mir_out_binding_spelling(store, fn_rec.name_start, fn_rec.name_end, fn_rec.c_name_start, fn_rec.c_name_end) || !out(40) { return false }
                if !mir_out_binding_params(idx, store, fn_at + 1) { return false }
                if !out_string(") -> ") || !mir_out_type(idx, store, fn_rec.result_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(10) { return false }
            }
            fn_at = fn_at + 1
        }
        var const_at: U64 = 0
        while const_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
            let const_rec = __s0_buffer_get(MirBindingConstRec, store.binding_consts, const_at)
            if const_rec.block == block_id {
                if !out_string("  c_const @") || !mir_out_name(store, const_rec.name_start, const_rec.name_end) || !mir_out_binding_spelling(store, const_rec.name_start, const_rec.name_end, const_rec.c_name_start, const_rec.c_name_end) || !out_string(": ") { return false }
                if !mir_out_type(idx, store, const_rec.const_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(10) { return false }
            }
            const_at = const_at + 1
        }
        if !out_string("}\n") { return false }
        at = at + 1
    }
    return true
}

fn mir_out_functions(idx: MirPrintIndex, store: MirStore) -> Bool {
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
        if !out_string("\nfn @") || !mir_out_name(store, rec.name_start, rec.name_end) || !out(40) || !mir_out_param_group(idx, store, mir_param_function(), function, 0) || !out(41) { return false }
        if rec.result_type != mir_type_unit() && (!out_string(" -> ") || !mir_out_type(idx, store, rec.result_type, __s0_buffer_len(MirTypeRec, store.types) + 1)) { return false }
        if !out_string(" {\n") { return false }
        let local_count = mir_local_count(idx, store, function)
        let local_group = __s0_buffer_get(MirPrintGroup, idx.locals, function - 1)
        var ordinal: U64 = 0
        while ordinal < local_count {
            var k: U64 = 0
            while k < local_group.count {
                let at = __s0_buffer_get(U64, idx.locals_order, local_group.first - 1 + k)
                let local = __s0_buffer_get(MirLocalRec, store.locals, at - 1)
                if local.function == function && local.ordinal == ordinal {
                    if !out_string("  local %") || !mir_out_name(store, local.name_start, local.name_end) || !out_string(": ") || !mir_out_type(idx, store, local.local_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(10) { return false }
                }
                k = k + 1
            }
            ordinal = ordinal + 1
        }
        if local_count > 0 && !out(10) { return false }
        let block_count = mir_block_count(idx, store, function)
        var block_ordinal: U64 = 0
        while block_ordinal < block_count {
            let block = block_ordinal + 1
            if block_ordinal > 0 && !out(10) { return false }
            if !mir_out_block_name(idx, store, function, block) { return false }
            if mir_param_group_count(idx, store, mir_param_block(), function, block) > 0 && (!out(40) || !mir_out_param_group(idx, store, mir_param_block(), function, block) || !out(41)) { return false }
            if !out_string(":\n") { return false }
            let instruction_count = mir_instr_group_count(idx, store, function, block)
            let instr_slot = mir_print_instr_slot(idx, store, function, block)
            var instruction_ordinal: U64 = 0
            while instruction_ordinal < instruction_count {
                if instr_slot != 0 {
                    let group = __s0_buffer_get(MirPrintGroup, idx.instr, instr_slot - 1)
                    var k: U64 = 0
                    while k < group.count {
                        let instruction_at = __s0_buffer_get(U64, idx.instr_order, group.first - 1 + k)
                        let instruction = __s0_buffer_get(MirInstrRec, store.instructions, instruction_at - 1)
                        if instruction.function == function && instruction.block == block && instruction.ordinal == instruction_ordinal && !mir_out_instruction(idx, store, instruction_at, instruction) { return false }
                        k = k + 1
                    }
                } else {
                    var instruction_at: U64 = 0
                    while instruction_at < __s0_buffer_len(U64, idx.instr_extra) {
                        let table_at = __s0_buffer_get(U64, idx.instr_extra, instruction_at)
                        let instruction = __s0_buffer_get(MirInstrRec, store.instructions, table_at - 1)
                        if instruction.function == function && instruction.block == block && instruction.ordinal == instruction_ordinal && !mir_out_instruction(idx, store, table_at, instruction) { return false }
                        instruction_at = instruction_at + 1
                    }
                }
                instruction_ordinal = instruction_ordinal + 1
            }
            let term_slot = mir_print_instr_slot(idx, store, function, block)
            if term_slot != 0 {
                let term_group = __s0_buffer_get(MirPrintGroup, idx.term, term_slot - 1)
                var k: U64 = 0
                while k < term_group.count {
                    let term_at = __s0_buffer_get(U64, idx.term_order, term_group.first - 1 + k)
                    let term = __s0_buffer_get(MirTermRec, store.terminators, term_at - 1)
                    if term.function == function && term.block == block && !mir_out_terminator(idx, store, term_at, term) { return false }
                    k = k + 1
                }
            } else {
                var term_at: U64 = 0
                while term_at < __s0_buffer_len(U64, idx.term_extra) {
                    let table_at = __s0_buffer_get(U64, idx.term_extra, term_at)
                    let term = __s0_buffer_get(MirTermRec, store.terminators, table_at - 1)
                    if term.function == function && term.block == block && !mir_out_terminator(idx, store, table_at, term) { return false }
                    term_at = term_at + 1
                }
            }
            block_ordinal = block_ordinal + 1
        }
        if !out_string("}\n") { return false }
        function = function + 1
    }
    return true
}

fn mir_print(d: Domain, store: MirStore) -> Bool {
    return match mir_print_index_build(d, store) {
        Err(_) => false
        Ok(idx) => mir_print_indexed(idx, store)
    }
}

fn mir_print_indexed(idx: MirPrintIndex, store: MirStore) -> Bool {
    if !mir_store_valid(idx, store) { return false }
    return out_string("mir 6\n") && mir_out_type_declarations(idx, store) && mir_out_declarations(idx, store) && mir_out_bindings(idx, store) && mir_out_functions(idx, store)
}
