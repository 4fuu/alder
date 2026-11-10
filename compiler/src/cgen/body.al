// Complete-verifier-gated MIR 4 body lowering for the M5.4 backend.

fn cgen_value_type(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let id = mir_vindex_value(indexes, function, value)
    if id == 0 { return 0 }
    return __s0_buffer_get(MirValueRec, store.values, id - 1).value_type
}

fn cgen_local_type(store: MirStore, indexes: MirVIndexes, function: U64, local: U64) -> U64 {
    let id = mir_vindex_local(indexes, function, local)
    if id == 0 { return 0 }
    return __s0_buffer_get(MirLocalRec, store.locals, id - 1).local_type
}

fn cgen_block_param(store: MirStore, indexes: MirVIndexes, function: U64, block: U64, ordinal: U64) -> MirParamRec {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, function, at)
        if id != 0 {
            let item = __s0_buffer_get(MirParamRec, store.params, id - 1)
            if item.kind == mir_param_block() && item.block == block && item.ordinal == ordinal { return item }
        }
        at = at + 1
    }
    return __s0_buffer_get(MirParamRec, store.params, 0)
}

fn cgen_op_list_count(indexes: MirVIndexes, kind: U64, owner: U64) -> U64 {
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() { return mir_vindex_op_instr_count(indexes, owner) }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() { return mir_vindex_op_term_count(indexes, owner) }
    return mir_vindex_op_case_count(indexes, owner)
}

fn cgen_op_list_id(indexes: MirVIndexes, kind: U64, owner: U64, at: U64) -> U64 {
    if kind == mir_operand_instruction() || kind == mir_operand_aggregate_field() || kind == mir_operand_checked_edge_arg() { return mir_vindex_op_instr(indexes, owner, at) }
    if kind == mir_operand_terminator_arg() || kind == mir_operand_switch_case() { return mir_vindex_op_term(indexes, owner, at) }
    return mir_vindex_op_case(indexes, owner, at)
}

fn cgen_operand_count(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64) -> U64 {
    if kind == mir_operand_import_param() { return mir_vcount_operands(store, kind, owner, edge) }
    let total = cgen_op_list_count(indexes, kind, owner)
    var count: U64 = 0
    var at: U64 = 0
    while at < total {
        let id = cgen_op_list_id(indexes, kind, owner, at)
        if id != 0 {
            let item = __s0_buffer_get(MirOperandRec, store.operands, id - 1)
            if item.kind == kind && item.edge == edge { count = count + 1 }
        }
        at = at + 1
    }
    return count
}

fn cgen_operand_id(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 {
    if kind == mir_operand_import_param() {
        var at: U64 = 0
        while at < __s0_buffer_len(MirOperandRec, store.operands) {
            let item = __s0_buffer_get(MirOperandRec, store.operands, at)
            if item.kind == kind && item.owner == owner && item.edge == edge && item.ordinal == ordinal { return at + 1 }
            at = at + 1
        }
        return 0
    }
    let total = cgen_op_list_count(indexes, kind, owner)
    var at: U64 = 0
    while at < total {
        let id = cgen_op_list_id(indexes, kind, owner, at)
        if id != 0 {
            let item = __s0_buffer_get(MirOperandRec, store.operands, id - 1)
            if item.kind == kind && item.edge == edge && item.ordinal == ordinal { return id }
        }
        at = at + 1
    }
    return 0
}

fn cgen_operand(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64, ordinal: U64) -> MirOperandRec {
    let id = cgen_operand_id(store, indexes, kind, owner, edge, ordinal)
    if id == 0 { return __s0_buffer_get(MirOperandRec, store.operands, 0) }
    return __s0_buffer_get(MirOperandRec, store.operands, id - 1)
}

fn cgen_term(store: MirStore, indexes: MirVIndexes, function: U64, block: U64) -> MirBuildStep {
    return MirBuildStep(store: store, id: mir_vindex_term(indexes, function, block))
}

fn cgen_put_value(d: Domain, writer: CgenWriter, value: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, writer, "alder_v")
    return cgen_put_u64(d, out, value - 1)
}

fn cgen_put_value_read(d: Domain, writer: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Result(CgenWriter, __s0_Error) {
    if cgen_value_type(store, indexes, function, value) == mir_type_unit() { return cgen_put(d, writer, "(uint8_t)0") }
    return cgen_put_value(d, writer, value)
}

fn cgen_put_local(d: Domain, writer: CgenWriter, local: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, writer, "alder_l")
    return cgen_put_u64(d, out, local - 1)
}

fn cgen_place_type(store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> U64 {
    let item = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if item.kind == mir_place_local() { return cgen_local_type(store, indexes, function, item.local) }
    if item.kind == mir_place_deref() { return __s0_buffer_get(MirTypeRec, store.types, cgen_value_type(store, indexes, function, item.deref_value) - 1).elem }
    let base_type = cgen_place_type(store, indexes, function, item.base)
    var at: U64 = 0
    while at < mir_vindex_type_part_count(indexes, base_type) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, base_type, at) - 1)
        if part.kind == mir_type_part_field() && mir_vname_equal(store, part.name_start, part.name_end, item.field_start, item.field_end) { return part.part_type }
        at = at + 1
    }
    return 0
}

fn cgen_field_ordinal(store: MirStore, indexes: MirVIndexes, owner: U64, start: U64, end: U64) -> U64 {
    var at: U64 = 0
    while at < mir_vindex_type_part_count(indexes, owner) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, owner, at) - 1)
        if part.kind == mir_type_part_field() && mir_vname_equal(store, part.name_start, part.name_end, start, end) { return part.ordinal }
        at = at + 1
    }
    return 0
}

fn cgen_put_place(d: Domain, writer: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64, place: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirPlaceRec, store.places, place - 1)
    if item.kind == mir_place_local() { return cgen_put_local(d, writer, item.local) }
    if item.kind == mir_place_field() {
        let base_type = cgen_place_type(store, indexes, function, item.base)
        var out = try cgen_put_place(d, writer, store, indexes, function, item.base)
        out = try cgen_put(d, out, ".alder_f")
        return cgen_put_u64(d, out, cgen_field_ordinal(store, indexes, base_type, item.field_start, item.field_end))
    }
    let reference_type = cgen_value_type(store, indexes, function, item.deref_value)
    let reference = __s0_buffer_get(MirTypeRec, store.types, reference_type - 1)
    var out = try cgen_put(d, writer, "(*(")
    out = try cgen_put_type(d, out, store, reference.elem)
    out = try cgen_put(d, out, " *)")
    out = try cgen_put_value_read(d, out, store, indexes, function, item.deref_value)
    if reference.kind == mir_type_kind_safe_ref() || reference.kind == mir_type_kind_safe_mut() { out = try cgen_put(d, out, ".data") }
    return cgen_put(d, out, ")")
}

fn cgen_variant_ordinal(store: MirStore, indexes: MirVIndexes, type_id: U64, start: U64, end: U64) -> U64 {
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_option() {
        if mir_vname_word(store, start, end, "some") { return 1 }
        return 0
    }
    if item.kind == mir_type_kind_result() {
        if mir_vname_word(store, start, end, "err") { return 1 }
        return 0
    }
    var at: U64 = 0
    while at < mir_vindex_type_part_count(indexes, type_id) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, mir_vindex_type_part(indexes, type_id, at) - 1)
        if part.kind == mir_type_part_variant() && mir_vname_equal(store, part.name_start, part.name_end, start, end) { return part.ordinal }
        at = at + 1
    }
    return 0
}

fn cgen_variant_payload(store: MirStore, type_id: U64, ordinal: U64) -> U64 {
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_option() {
        if ordinal == 1 { return item.elem }
        return mir_type_unit()
    }
    if item.kind == mir_type_kind_result() {
        if ordinal == 0 { return item.ok_type }
        return item.err_type
    }
    return cgen_type_part(store, type_id, mir_type_part_variant(), ordinal).part_type
}

fn cgen_copy_trivial(store: MirStore, type_id: U64) -> Bool {
    if type_id <= mir_primitive_type_count() { return true }
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_function() { return false }
    if item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_vec() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() { return false }
    if item.kind == mir_type_kind_domain_handle() || item.kind == mir_type_kind_domain_mark() || item.kind == mir_type_kind_cleanup_scope() || item.kind == mir_type_kind_cleanup_id() || item.kind == mir_type_kind_table() || item.kind == mir_type_kind_table_view() || item.kind == mir_type_kind_table_mut_view() || item.kind == mir_type_kind_raw_ptr() { return false }
    if item.kind == mir_type_kind_array() { return cgen_copy_trivial(store, item.elem) }
    if item.kind == mir_type_kind_option() { return cgen_copy_trivial(store, item.elem) }
    if item.kind == mir_type_kind_result() { return cgen_copy_trivial(store, item.ok_type) && cgen_copy_trivial(store, item.err_type) }
    if item.kind == mir_type_kind_aggregate() || item.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if item.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, type_id, kind) {
            let child = cgen_type_part(store, type_id, kind, ordinal).part_type
            if !cgen_copy_trivial(store, child) { return false }
            ordinal = ordinal + 1
        }
    }
    return true
}

fn cgen_copy_supported(store: MirStore, type_id: U64) -> Bool {
    if cgen_copy_trivial(store, type_id) || type_id <= mir_primitive_type_count() { return true }
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_domain_handle() || item.kind == mir_type_kind_domain_mark() || item.kind == mir_type_kind_cleanup_scope() || item.kind == mir_type_kind_cleanup_id() || item.kind == mir_type_kind_table() || item.kind == mir_type_kind_table_view() || item.kind == mir_type_kind_table_mut_view() || item.kind == mir_type_kind_raw_ptr() { return false }
    if item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() { return cgen_copy_supported(store, item.elem) }
    if item.kind == mir_type_kind_vec() { return cgen_copy_supported(store, item.elem) }
    if item.kind == mir_type_kind_array() { return cgen_copy_supported(store, item.elem) }
    if item.kind == mir_type_kind_option() { return cgen_copy_supported(store, item.elem) }
    if item.kind == mir_type_kind_result() { return cgen_copy_supported(store, item.ok_type) && cgen_copy_supported(store, item.err_type) }
    if item.kind == mir_type_kind_aggregate() || item.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if item.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, type_id, kind) {
            let child = cgen_type_part(store, type_id, kind, ordinal).part_type
            if !cgen_copy_supported(store, child) { return false }
            ordinal = ordinal + 1
        }
    }
    return true
}

fn cgen_supported(store: MirStore, indexes: MirVIndexes) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op > mir_op_str_from_bytes() { return false }
        if item.op == mir_op_copy_to_domain() && !cgen_copy_supported(store, cgen_value_type(store, indexes, item.function, item.b)) { return false }
        at = at + 1
    }
    return true
}

fn cgen_emit_edge(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64, kind: U64, owner: U64, edge: U64, target: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "{ ")
    let count = cgen_operand_count(store, indexes, kind, owner, edge)
    var ordinal: U64 = 0
    while ordinal < count {
        let argument = cgen_operand(store, indexes, kind, owner, edge, ordinal)
        let parameter = cgen_block_param(store, indexes, function, target, ordinal)
        if parameter.param_type != mir_type_unit() {
            out = try cgen_put_type(d, out, store, parameter.param_type)
            out = try cgen_put(d, out, " alder_edge_")
            out = try cgen_put_u64(d, out, kind)
            out = try cgen_put(d, out, "_")
            out = try cgen_put_u64(d, out, owner)
            out = try cgen_put(d, out, "_")
            out = try cgen_put_u64(d, out, edge)
            out = try cgen_put(d, out, "_")
            out = try cgen_put_u64(d, out, ordinal)
            out = try cgen_put(d, out, " = ")
            out = try cgen_put_value_read(d, out, store, indexes, function, argument.value)
            out = try cgen_put(d, out, "; ")
        }
        ordinal = ordinal + 1
    }
    ordinal = 0
    while ordinal < count {
        let parameter = cgen_block_param(store, indexes, function, target, ordinal)
        if parameter.param_type != mir_type_unit() {
            out = try cgen_put_value(d, out, parameter.value)
            out = try cgen_put(d, out, " = alder_edge_")
            out = try cgen_put_u64(d, out, kind)
            out = try cgen_put(d, out, "_")
            out = try cgen_put_u64(d, out, owner)
            out = try cgen_put(d, out, "_")
            out = try cgen_put_u64(d, out, edge)
            out = try cgen_put(d, out, "_")
            out = try cgen_put_u64(d, out, ordinal)
            out = try cgen_put(d, out, "; ")
        }
        ordinal = ordinal + 1
    }
    out = try cgen_put(d, out, "goto alder_b")
    out = try cgen_put_u64(d, out, target - 1)
    return cgen_put(d, out, "; }")
}

fn cgen_emit_checked_edge(d: Domain, writer: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    return cgen_emit_edge(d, writer, store, indexes, item.function, mir_operand_checked_edge_arg(), instruction, 0, item.target)
}

fn cgen_int_width(type_id: U64) -> U64 {
    if type_id == mir_type_i8() || type_id == mir_type_u8() { return 8 }
    if type_id == mir_type_i16() || type_id == mir_type_u16() { return 16 }
    if type_id == mir_type_i32() || type_id == mir_type_u32() { return 32 }
    return 64
}

fn cgen_int_signed(type_id: U64) -> Bool {
    return type_id >= mir_type_i8() && type_id <= mir_type_i64()
}

fn cgen_put_int_limit(d: Domain, writer: CgenWriter, signed: Bool, width: U64, minimum: Bool) -> Result(CgenWriter, __s0_Error) {
    if signed {
        if width == 8 { if minimum { return cgen_put(d, writer, "INT8_MIN") }
        return cgen_put(d, writer, "INT8_MAX") }
        if width == 16 { if minimum { return cgen_put(d, writer, "INT16_MIN") }
        return cgen_put(d, writer, "INT16_MAX") }
        if minimum { return cgen_put(d, writer, "INT32_MIN") }
        return cgen_put(d, writer, "INT32_MAX")
    }
    if width == 8 { return cgen_put(d, writer, "UINT8_MAX") }
    if width == 16 { return cgen_put(d, writer, "UINT16_MAX") }
    if width == 32 { return cgen_put(d, writer, "UINT32_MAX") }
    return cgen_put(d, writer, "UINT64_MAX")
}

fn cgen_put_tmp(d: Domain, writer: CgenWriter, value: U64, suffix: __s0_String) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, writer, "alder_t")
    out = try cgen_put_u64(d, out, value - 1)
    return cgen_put(d, out, suffix)
}

fn cgen_emit_int_checked(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    let type_id = cgen_value_type(store, indexes, item.function, item.a)
    let width = cgen_int_width(type_id)
    let signed = cgen_int_signed(type_id)
    var out = initial
    if item.op == mir_op_int_shl_checked() || item.op == mir_op_int_shr_checked() {
        if width == 64 {
            out = try cgen_put(d, out, "  if (!alder_")
            if signed { out = try cgen_put(d, out, "i64_sh") } else { out = try cgen_put(d, out, "u64_sh") }
            if item.op == mir_op_int_shl_checked() { out = try cgen_put(d, out, "l_checked(") } else { out = try cgen_put(d, out, "r_checked(") }
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ", ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            out = try cgen_put(d, out, ", &")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ")) ")
            out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
            return cgen_put(d, out, "\n")
        }
        out = try cgen_put(d, out, "  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        if signed { out = try cgen_put(d, out, " < 0 || ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b) }
        out = try cgen_put(d, out, " >= ")
        out = try cgen_put_u64(d, out, width)
        out = try cgen_put(d, out, ") ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n")
        if !signed {
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (uint")
            out = try cgen_put_u64(d, out, width)
            out = try cgen_put(d, out, "_t)(((uint64_t)(uint")
            out = try cgen_put_u64(d, out, width)
            out = try cgen_put(d, out, "_t)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            if item.op == mir_op_int_shl_checked() { out = try cgen_put(d, out, ") << (unsigned)") } else { out = try cgen_put(d, out, ") >> (unsigned)") }
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            return cgen_put(d, out, ");\n")
        }
        if item.op == mir_op_int_shl_checked() {
            out = try cgen_put(d, out, "  uint")
            out = try cgen_put_u64(d, out, width)
            out = try cgen_put(d, out, "_t ")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " = (uint")
            out = try cgen_put_u64(d, out, width)
            out = try cgen_put(d, out, "_t)(((uint64_t)(uint")
            out = try cgen_put_u64(d, out, width)
            out = try cgen_put(d, out, "_t)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ") << (unsigned)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            out = try cgen_put(d, out, ");\n  memcpy(&")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ", &")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, ", sizeof(")
            out = try cgen_put_tmp(d, out, item.result, "")
            return cgen_put(d, out, "));\n")
        }
        out = try cgen_put(d, out, "  uint64_t ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " = (uint64_t)(uint")
        out = try cgen_put_u64(d, out, width)
        out = try cgen_put(d, out, "_t)")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, " >> (unsigned)")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ";\n  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, " < 0 && ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, " > 0) { ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " |= (UINT64_MAX << (unsigned)(")
        out = try cgen_put_u64(d, out, width)
        out = try cgen_put(d, out, " - ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ")) & (uint64_t)")
        out = try cgen_put_int_limit(d, out, false, width, false)
        out = try cgen_put(d, out, "; }\n  uint")
        out = try cgen_put_u64(d, out, width)
        out = try cgen_put(d, out, "_t ")
        out = try cgen_put_tmp(d, out, item.result, "u")
        out = try cgen_put(d, out, " = (uint")
        out = try cgen_put_u64(d, out, width)
        out = try cgen_put(d, out, "_t)")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n  memcpy(&")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ", &")
        out = try cgen_put_tmp(d, out, item.result, "u")
        out = try cgen_put(d, out, ", sizeof(")
        out = try cgen_put_tmp(d, out, item.result, "u")
        return cgen_put(d, out, "));\n")
    }
    if width < 64 {
        out = try cgen_put(d, out, "  ")
        if signed { out = try cgen_put(d, out, "int64_t ") } else { out = try cgen_put(d, out, "uint64_t ") }
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n")
    }
    out = try cgen_put(d, out, "  if (!alder_")
    if signed { out = try cgen_put(d, out, "i64_") } else { out = try cgen_put(d, out, "u64_") }
    if item.op == mir_op_int_add_checked() { out = try cgen_put(d, out, "add_checked(") }
    if item.op == mir_op_int_sub_checked() { out = try cgen_put(d, out, "sub_checked(") }
    if item.op == mir_op_int_mul_checked() { out = try cgen_put(d, out, "mul_checked(") }
    if item.op == mir_op_int_div_checked() { out = try cgen_put(d, out, "div_checked(") }
    if width < 64 { out = try cgen_put(d, out, "(")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, ")") }
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ", ")
    if width < 64 { out = try cgen_put(d, out, "(")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, ")") }
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ", &")
    if width == 64 { out = try cgen_put_value(d, out, item.result) } else { out = try cgen_put_tmp(d, out, item.result, "") }
    out = try cgen_put(d, out, ")) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n")
    if width == 64 { return Ok(out) }
    out = try cgen_put(d, out, "  if (")
    out = try cgen_put_tmp(d, out, item.result, "")
    if signed {
        out = try cgen_put(d, out, " < (int64_t)")
        out = try cgen_put_int_limit(d, out, true, width, true)
        out = try cgen_put(d, out, " || ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " > (int64_t)")
        out = try cgen_put_int_limit(d, out, true, width, false)
    } else {
        out = try cgen_put(d, out, " > (uint64_t)")
        out = try cgen_put_int_limit(d, out, false, width, false)
    }
    out = try cgen_put(d, out, ") ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n  ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = (")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, ")")
    out = try cgen_put_tmp(d, out, item.result, "")
    return cgen_put(d, out, ";\n")
}

// Non-terminating integer arithmetic (M8): the try forms build an option
// (none on overflow), the saturating forms clamp at the type bounds, and the
// wrapping forms wrap modulo 2^width. All of them compute in 64 bits with the
// runtime helpers, so signed arithmetic stays defined; narrow widths then
// clamp or truncate against their own bounds, which matches saturating or
// wrapping at that width exactly: saturating at 64 bits keeps the value on
// the same side of the narrow bound, and truncation keeps the low bits the
// width-w wrap produces.
fn cgen_emit_int_mode(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    let type_id = cgen_value_type(store, indexes, item.function, item.a)
    let width = cgen_int_width(type_id)
    let signed = cgen_int_signed(type_id)
    var out = initial
    out = try cgen_put(d, out, "  ")
    if width < 64 {
        if signed { out = try cgen_put(d, out, "int64_t ") } else { out = try cgen_put(d, out, "uint64_t ") }
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " = ")
    } else {
        out = try cgen_put_value(d, out, item.result)
        if item.op >= mir_op_int_add_try() && item.op <= mir_op_int_mul_try() {
            out = try cgen_put(d, out, ".alder_tag = ")
        } else {
            out = try cgen_put(d, out, " = ")
        }
    }
    if width < 64 && item.op >= mir_op_int_add_try() && item.op <= mir_op_int_mul_try() {
        // Narrow try: the widened operands cannot overflow 64 bits, so
        // plain 64-bit arithmetic needs no checked helper; the width check
        // below alone decides none versus some. Each operand is widened to
        // 64 bits BEFORE the arithmetic: a narrow cast alone would let C
        // compute the operation in the operands' promoted 32-bit int
        // width, where i32 signed subtraction overflows (undefined) and
        // u32 wraparound silently corrupts the value.
        if signed { out = try cgen_put(d, out, "(int64_t)((") } else { out = try cgen_put(d, out, "(uint64_t)((") }
        out = try cgen_put_type(d, out, store, type_id)
        out = try cgen_put(d, out, ")")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ")")
        if item.op == mir_op_int_add_try() { out = try cgen_put(d, out, " + ") }
        if item.op == mir_op_int_sub_try() { out = try cgen_put(d, out, " - ") }
        if item.op == mir_op_int_mul_try() { out = try cgen_put(d, out, " * ") }
        if signed { out = try cgen_put(d, out, "(int64_t)((") } else { out = try cgen_put(d, out, "(uint64_t)((") }
        out = try cgen_put_type(d, out, store, type_id)
        out = try cgen_put(d, out, ")")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ");\n")
    } else {
    out = try cgen_put(d, out, "alder_")
    if signed { out = try cgen_put(d, out, "i64_") } else { out = try cgen_put(d, out, "u64_") }
    if item.op == mir_op_int_add_try() { out = try cgen_put(d, out, "add_checked(") }
    if item.op == mir_op_int_sub_try() { out = try cgen_put(d, out, "sub_checked(") }
    if item.op == mir_op_int_mul_try() { out = try cgen_put(d, out, "mul_checked(") }
    if item.op == mir_op_int_add_saturating() { out = try cgen_put(d, out, "add_saturating(") }
    if item.op == mir_op_int_sub_saturating() { out = try cgen_put(d, out, "sub_saturating(") }
    if item.op == mir_op_int_mul_saturating() { out = try cgen_put(d, out, "mul_saturating(") }
    if item.op == mir_op_int_add_wrapping() { out = try cgen_put(d, out, "add_wrapping(") }
    if item.op == mir_op_int_sub_wrapping() { out = try cgen_put(d, out, "sub_wrapping(") }
    if item.op == mir_op_int_mul_wrapping() { out = try cgen_put(d, out, "mul_wrapping(") }
    if width == 64 {
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        if item.op >= mir_op_int_add_try() && item.op <= mir_op_int_mul_try() {
            // option(T): none is tag 0 with no payload, some is tag 1
            // carrying the payload; the failed helper leaves the payload
            // slot untouched, which none never reads.
            out = try cgen_put(d, out, ", &")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ".alder_u.alder_p1) ? 1u : 0u;\n")
            return Ok(out)
        }
        return cgen_put(d, out, ");\n")
    }
    out = try cgen_put(d, out, "(")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, ")")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ", (")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, ")")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ");\n")
    }
    if item.op >= mir_op_int_add_try() && item.op <= mir_op_int_mul_try() {
        out = try cgen_put(d, out, "  if (")
        out = try cgen_put_tmp(d, out, item.result, "")
        if signed {
            out = try cgen_put(d, out, " < (int64_t)")
            out = try cgen_put_int_limit(d, out, true, width, true)
            out = try cgen_put(d, out, " || ")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " > (int64_t)")
            out = try cgen_put_int_limit(d, out, true, width, false)
        } else {
            out = try cgen_put(d, out, " > (uint64_t)")
            out = try cgen_put_int_limit(d, out, false, width, false)
        }
        out = try cgen_put(d, out, ") {\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_tag = (uint32_t)0;\n  } else {\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_tag = (uint32_t)1;\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_u.alder_p1 = (")
        out = try cgen_put_type(d, out, store, type_id)
        out = try cgen_put(d, out, ")")
        out = try cgen_put_tmp(d, out, item.result, "")
        return cgen_put(d, out, ";\n  }\n")
    }
    if item.op >= mir_op_int_add_saturating() && item.op <= mir_op_int_mul_saturating() {
        if signed {
            out = try cgen_put(d, out, "  if (")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " > (int64_t)")
            out = try cgen_put_int_limit(d, out, true, width, false)
            out = try cgen_put(d, out, ") ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, type_id)
            out = try cgen_put(d, out, ")")
            out = try cgen_put_int_limit(d, out, true, width, false)
            out = try cgen_put(d, out, ";\n  else if (")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " < (int64_t)")
            out = try cgen_put_int_limit(d, out, true, width, true)
            out = try cgen_put(d, out, ") ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, type_id)
            out = try cgen_put(d, out, ")")
            out = try cgen_put_int_limit(d, out, true, width, true)
            out = try cgen_put(d, out, ";\n  else ")
        } else {
            out = try cgen_put(d, out, "  if (")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " > (uint64_t)")
            out = try cgen_put_int_limit(d, out, false, width, false)
            out = try cgen_put(d, out, ") ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, type_id)
            out = try cgen_put(d, out, ")")
            out = try cgen_put_int_limit(d, out, false, width, false)
            out = try cgen_put(d, out, ";\n  else ")
        }
    }
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = (")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, ")")
    out = try cgen_put_tmp(d, out, item.result, "")
    return cgen_put(d, out, ";\n")
}

fn cgen_emit_call_args(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec, import_call: Bool) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let count = cgen_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
    var ordinal: U64 = 0
    var wrote = false
    while ordinal < count {
        var type_id: U64 = 0
        if import_call { type_id = cgen_operand(store, indexes, mir_operand_import_param(), item.target, 0, ordinal).operand_type } else { type_id = cgen_function_param(store, indexes, item.target, ordinal).param_type }
        if type_id != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            let argument = cgen_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal)
            out = try cgen_put_value_read(d, out, store, indexes, item.function, argument.value)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    return Ok(out)
}

fn cgen_const_id(store: MirStore, indexes: MirVIndexes, start: U64, end: U64) -> U64 {
    return mir_vindex_const(store, indexes, start, end)
}

// The byte-sequence op emitters, split out of cgen_emit_instruction: each of
// these bodies is a long straight-line writer chain, and keeping them inside
// the giant dispatch function dominated self-compile wall time through the
// per-function fact machinery. Behavior and emitted text are unchanged.

fn cgen_emit_str_len(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    out = try cgen_put(d, out, "  ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    return cgen_put(d, out, ".len;\n")
}

fn cgen_emit_str_byte_checked(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    out = try cgen_put(d, out, "  if (")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, " >= ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ".len) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n  ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ".data[")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    return cgen_put(d, out, "];\n")
}

fn cgen_emit_str_to_bytes(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    out = try cgen_put(d, out, "  ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = (")
    out = try cgen_put_type(d, out, store, cgen_value_type(store, indexes, item.function, item.result))
    out = try cgen_put(d, out, "){ ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ".data, ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    return cgen_put(d, out, ".len };\n")
}

fn cgen_emit_str_concat(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    out = try cgen_put(d, out, "  uint64_t ")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, ";\n  if (!alder_u64_add_checked(")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len, ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, ".len, &")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, ") || ")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, " > (uint64_t)SIZE_MAX) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n  void *")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " = alder_domain_alloc(")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ", (size_t)")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, ", (size_t)1);\n  if (")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " == NULL) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n  if (")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len != (uint64_t)0) { memcpy(")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, ", ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".data, (size_t)")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len); }\n  if (")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, ".len != (uint64_t)0) { memcpy((uint8_t *)")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " + ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len, ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, ".data, (size_t)")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, ".len); }\n  ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = (")
    out = try cgen_put_type(d, out, store, cgen_value_type(store, indexes, item.function, item.result))
    out = try cgen_put(d, out, "){ (const uint8_t *)")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, ", ")
    out = try cgen_put_tmp(d, out, item.result, "n")
    return cgen_put(d, out, " };\n")
}

fn cgen_emit_str_slice_checked(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let hi_operand = cgen_operand(store, indexes, mir_operand_instruction(), instruction, 0, 0)
    out = try cgen_put(d, out, "  if (")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, " > ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, hi_operand.value)
    out = try cgen_put(d, out, " || ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, hi_operand.value)
    out = try cgen_put(d, out, " > ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n  uint64_t ")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, " = ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, hi_operand.value)
    out = try cgen_put(d, out, " - ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, ";\n  void *")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " = alder_domain_alloc(")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ", (size_t)")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, ", (size_t)1);\n  if (")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " == NULL) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n  if (")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, " != (uint64_t)0) { memcpy(")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, ", ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".data + ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
    out = try cgen_put(d, out, ", (size_t)")
    out = try cgen_put_tmp(d, out, item.result, "n")
    out = try cgen_put(d, out, "); }\n  ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, " = (")
    out = try cgen_put_type(d, out, store, cgen_value_type(store, indexes, item.function, item.result))
    out = try cgen_put(d, out, "){ (const uint8_t *)")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, ", ")
    out = try cgen_put_tmp(d, out, item.result, "n")
    return cgen_put(d, out, " };\n")
}

fn cgen_emit_str_from_bytes(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    // The result value is option(string): none on invalid UTF-8, some
    // carrying the fresh string otherwise. Only allocation failure
    // takes the instruction's failure edge.
    var out = initial
    out = try cgen_put(d, out, "  if (!alder_string_utf8_valid(")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".data, ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len)) {\n    ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, ".alder_tag = (uint32_t)0;\n  } else {\n    void *")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " = alder_domain_alloc(")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
    out = try cgen_put(d, out, ", (size_t)")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len, (size_t)1);\n    if (")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, " == NULL) ")
    out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
    out = try cgen_put(d, out, "\n    if (")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len != (uint64_t)0) { memcpy(")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, ", ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".data, (size_t)")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len); }\n    ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, ".alder_u.alder_p1 = (AlderString){ (const uint8_t *)")
    out = try cgen_put_tmp(d, out, item.result, "p")
    out = try cgen_put(d, out, ", ")
    out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
    out = try cgen_put(d, out, ".len };\n    ")
    out = try cgen_put_value(d, out, item.result)
    out = try cgen_put(d, out, ".alder_tag = (uint32_t)1;\n  }\n")
    return Ok(out)
}

fn cgen_emit_instruction(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, instruction: U64, item: MirInstrRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    if item.op == mir_op_load() {
        if cgen_value_type(store, indexes, item.function, item.result) == mir_type_unit() { return Ok(out) }
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ")
        out = try cgen_put_place(d, out, store, indexes, item.function, item.place)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_borrow() || item.op == mir_op_borrow_mut() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderSlice){ (void *)&")
        out = try cgen_put_place(d, out, store, indexes, item.function, item.place)
        return cgen_put(d, out, ", (uint64_t)1 };\n")
    }
    if item.op == mir_op_store() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_place(d, out, store, indexes, item.function, item.place)
        out = try cgen_put(d, out, " = ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_aggregate_construct() {
        let count = cgen_operand_count(store, indexes, mir_operand_aggregate_field(), instruction, 0)
        if count == 0 {
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, item.type_op)
            return cgen_put(d, out, "){0};\n")
        }
        var ordinal: U64 = 0
        while ordinal < count {
            let field = cgen_operand(store, indexes, mir_operand_aggregate_field(), instruction, 0, ordinal)
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_value(d, out, item.result)
            if __s0_buffer_get(MirTypeRec, store.types, item.type_op - 1).kind == mir_type_kind_array() {
                out = try cgen_put(d, out, ".alder_e[")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, "]")
            } else {
                out = try cgen_put(d, out, ".alder_f")
                out = try cgen_put_u64(d, out, ordinal)
            }
            out = try cgen_put(d, out, " = ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, field.value)
            out = try cgen_put(d, out, ";\n")
            ordinal = ordinal + 1
        }
        return Ok(out)
    }
    if item.op == mir_op_domain_create() {
        out = try cgen_put(d, out, "  if (!alder_domain_init(&alder_domain_")
        out = try cgen_put_u64(d, out, instruction - 1)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ")) { alder_runtime_panic(\"domain.create failed\"); }\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = &alder_domain_")
        out = try cgen_put_u64(d, out, instruction - 1)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_domain_mark() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = alder_domain_mark(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ");\n")
    }
    if item.op == mir_op_domain_reset() {
        out = try cgen_put(d, out, "  if (!alder_domain_reset(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        return cgen_put(d, out, ")) { alder_runtime_panic(\"domain.reset failed\"); }\n")
    }
    if item.op == mir_op_domain_destroy() {
        out = try cgen_put(d, out, "  alder_domain_destroy(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ");\n")
    }
    if item.op == mir_op_alloc() || item.op == mir_op_alloc_checked() {
        out = try cgen_put(d, out, "  uint64_t ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n  if (!alder_u64_mul_checked(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ", (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, item.type_op)
        out = try cgen_put(d, out, "), &")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ")) ")
        if item.op == mir_op_alloc_checked() { out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item) } else { out = try cgen_put(d, out, "{ alder_runtime_panic(\"alloc: size overflow\"); }") }
        out = try cgen_put(d, out, "\n  if (")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " > (uint64_t)SIZE_MAX) ")
        if item.op == mir_op_alloc_checked() { out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item) } else { out = try cgen_put(d, out, "{ alder_runtime_panic(\"alloc: size exceeds size_t\"); }") }
        out = try cgen_put(d, out, "\n  void *")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " = alder_domain_alloc(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", (size_t)")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ", _Alignof(")
        out = try cgen_put_type(d, out, store, item.type_op)
        out = try cgen_put(d, out, "));\n  if (")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " == NULL) ")
        if item.op == mir_op_alloc_checked() { out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item) } else { out = try cgen_put(d, out, "{ alder_runtime_panic(\"alloc: out of memory\"); }") }
        out = try cgen_put(d, out, "\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderSlice){ ")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        return cgen_put(d, out, " };\n")
    }
    if item.op == mir_op_copy_to_domain() {
        let type_id = cgen_value_type(store, indexes, item.function, item.b)
        if type_id == mir_type_unit() { return Ok(out) }
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ")
        if !cgen_copy_trivial(store, type_id) { out = try cgen_put(d, out, "alder_copy_ty")
        out = try cgen_put_u64(d, out, type_id - 1)
        out = try cgen_put(d, out, "(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ") }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        if !cgen_copy_trivial(store, type_id) { out = try cgen_put(d, out, ", 1)") }
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_cleanup_scope_begin() {
        out = try cgen_put(d, out, "  if (!alder_cleanup_scope_begin(&alder_scope_")
        out = try cgen_put_u64(d, out, instruction - 1)
        out = try cgen_put(d, out, ")) { alder_runtime_panic(\"cleanup.scope.begin failed\"); }\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = &alder_scope_")
        out = try cgen_put_u64(d, out, instruction - 1)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_cleanup_push() {
        let count = cgen_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
        var ordinal: U64 = 0
        var field: U64 = 0
        while ordinal < count {
            let argument = cgen_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal)
            let parameter = cgen_function_param(store, indexes, item.target, ordinal)
            if parameter.param_type != mir_type_unit() {
                out = try cgen_put(d, out, "  alder_ctx_")
                out = try cgen_put_u64(d, out, instruction - 1)
                out = try cgen_put(d, out, ".alder_f")
                out = try cgen_put_u64(d, out, field)
                out = try cgen_put(d, out, " = ")
                out = try cgen_put_value_read(d, out, store, indexes, item.function, argument.value)
                out = try cgen_put(d, out, ";\n")
                field = field + 1
            }
            ordinal = ordinal + 1
        }
        out = try cgen_put(d, out, "  if (!alder_cleanup_push(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", alder_cleanup_")
        out = try cgen_put_u64(d, out, instruction - 1)
        out = try cgen_put(d, out, ", &alder_ctx_")
        out = try cgen_put_u64(d, out, instruction - 1)
        out = try cgen_put(d, out, ", &")
        out = try cgen_put_value(d, out, item.result)
        return cgen_put(d, out, ")) { alder_runtime_panic(\"cleanup.push failed\"); }\n")
    }
    if item.op >= mir_op_cleanup_disarm() && item.op <= mir_op_cleanup_scope_end() {
        out = try cgen_put(d, out, "  if (!alder_cleanup_")
        if item.op == mir_op_cleanup_disarm() { out = try cgen_put(d, out, "disarm(") }
        if item.op == mir_op_cleanup_scope_run() { out = try cgen_put(d, out, "run(") }
        if item.op == mir_op_cleanup_scope_end() { out = try cgen_put(d, out, "end(") }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ")) { alder_runtime_panic(\"cleanup contract violation\"); }\n")
        return Ok(out)
    }
    if item.op >= mir_op_int_add_checked() && item.op <= mir_op_int_shr_checked() { return cgen_emit_int_checked(d, out, store, indexes, instruction, item) }
    if item.op >= mir_op_int_add_try() && item.op <= mir_op_int_mul_wrapping() { return cgen_emit_int_mode(d, out, store, indexes, instruction, item) }
    if item.op == mir_op_slice_len() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ".len;\n")
    }
    if item.op == mir_op_slice_index_checked() || item.op == mir_op_slice_range_checked() {
        let source_type = cgen_value_type(store, indexes, item.function, item.a)
        let elem = __s0_buffer_get(MirTypeRec, store.types, source_type - 1).elem
        out = try cgen_put(d, out, "  if (!alder_slice_")
        if item.op == mir_op_slice_index_checked() { out = try cgen_put(d, out, "index_checked(") } else { out = try cgen_put(d, out, "range_checked(") }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        if item.op == mir_op_slice_range_checked() { out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c) }
        out = try cgen_put(d, out, ")) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  uint64_t ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n  if (!alder_u64_mul_checked(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ", (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, elem)
        out = try cgen_put(d, out, "), &")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ")) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  if (")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " > (uint64_t)SIZE_MAX) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  void *")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " = ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".data;\n  if (")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " != (uint64_t)0) { ")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " = (void *)((uint8_t *)")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " + (size_t)")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, "); }\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderSlice){ ")
        out = try cgen_put_tmp(d, out, item.result, "p")
        if item.op == mir_op_slice_index_checked() { out = try cgen_put(d, out, ", (uint64_t)1 };\n") } else {
            out = try cgen_put(d, out, ", (uint64_t)(")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
            out = try cgen_put(d, out, " - ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            out = try cgen_put(d, out, ") };\n")
        }
        return Ok(out)
    }
    if item.op == mir_op_array_index_checked() {
        let source_type = cgen_value_type(store, indexes, item.function, item.a)
        var array_type = source_type
        if __s0_buffer_get(MirTypeRec, store.types, source_type - 1).kind == mir_type_kind_safe_mut() { array_type = __s0_buffer_get(MirTypeRec, store.types, source_type - 1).elem }
        let array = __s0_buffer_get(MirTypeRec, store.types, array_type - 1)
        out = try cgen_put(d, out, "  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, " >= (uint64_t)")
        out = try cgen_put_u64(d, out, array.length)
        out = try cgen_put(d, out, ") ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderSlice){ (void *)&")
        if source_type == array_type {
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ".alder_e[")
        } else {
            out = try cgen_put(d, out, "((AlderTy")
            out = try cgen_put_u64(d, out, array_type - 1)
            out = try cgen_put(d, out, " *)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ".data)->alder_e[")
        }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        return cgen_put(d, out, "], (uint64_t)1 };\n")
    }
    if item.op == mir_op_array_as_slice() {
        let source_type = cgen_value_type(store, indexes, item.function, item.a)
        var array_type = source_type
        if __s0_buffer_get(MirTypeRec, store.types, source_type - 1).kind != mir_type_kind_array() { array_type = __s0_buffer_get(MirTypeRec, store.types, source_type - 1).elem }
        let array = __s0_buffer_get(MirTypeRec, store.types, array_type - 1)
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderSlice){ (void *)")
        if source_type == array_type {
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ".alder_e, (uint64_t)")
        } else {
            out = try cgen_put(d, out, "((AlderTy")
            out = try cgen_put_u64(d, out, array_type - 1)
            out = try cgen_put(d, out, " *)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ".data)->alder_e, (uint64_t)")
        }
        out = try cgen_put_u64(d, out, array.length)
        return cgen_put(d, out, " };\n")
    }
    if item.op == mir_op_vec_new() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        return cgen_put(d, out, " = (AlderVec){ NULL, (uint64_t)0, (uint64_t)0 };\n")
    }
    if item.op == mir_op_vec_construct_checked() {
        out = try cgen_put(d, out, "  if (!alder_vec_construct_checked(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
        out = try cgen_put(d, out, ", &")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ")) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        return cgen_put(d, out, "\n")
    }
    if item.op == mir_op_vec_grow_checked() {
        let vec_type = cgen_value_type(store, indexes, item.function, item.a)
        let elem = __s0_buffer_get(MirTypeRec, store.types, vec_type - 1).elem
        out = try cgen_put(d, out, "  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
        out = try cgen_put(d, out, " < ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".len) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  uint64_t ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n  if (!alder_u64_mul_checked(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
        out = try cgen_put(d, out, ", (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, elem)
        out = try cgen_put(d, out, "), &")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ") || ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, " > (uint64_t)SIZE_MAX) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".len != (uint64_t)0 && ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".data == NULL) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  void *")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " = alder_domain_alloc(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ", (size_t)")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ", _Alignof(")
        out = try cgen_put_type(d, out, store, elem)
        out = try cgen_put(d, out, "));\n  if (")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " == NULL) ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  for (uint64_t alder_i = (uint64_t)0; alder_i < ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".len; alder_i++) { ((")
        out = try cgen_put_type(d, out, store, elem)
        out = try cgen_put(d, out, " *)")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, ")[alder_i] = ")
        if !cgen_copy_trivial(store, elem) { out = try cgen_put(d, out, "alder_copy_ty")
            out = try cgen_put_u64(d, out, elem - 1)
            out = try cgen_put(d, out, "(")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            out = try cgen_put(d, out, ", ") }
        out = try cgen_put(d, out, "((")
        out = try cgen_put_type(d, out, store, elem)
        out = try cgen_put(d, out, " *)")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".data)[alder_i]")
        if !cgen_copy_trivial(store, elem) { out = try cgen_put(d, out, ", 0)") }
        out = try cgen_put(d, out, "; }\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderVec){ ")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".len, ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.c)
        return cgen_put(d, out, " };\n")
    }
    if item.op == mir_op_vec_len() || item.op == mir_op_vec_capacity() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        if item.op == mir_op_vec_len() { return cgen_put(d, out, ".len;\n") }
        return cgen_put(d, out, ".capacity;\n")
    }
    if item.op == mir_op_vec_storage() || item.op == mir_op_vec_as_slice() || item.op == mir_op_vec_as_mut_slice() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderSlice){ ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".data, ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        if item.op == mir_op_vec_storage() { return cgen_put(d, out, ".capacity };\n") }
        return cgen_put(d, out, ".len };\n")
    }
    if item.op == mir_op_enum_payload_checked() {
        let type_id = cgen_value_type(store, indexes, item.function, item.a)
        let ordinal = cgen_variant_ordinal(store, indexes, type_id, item.name_start, item.name_end)
        out = try cgen_put(d, out, "  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".alder_tag != (uint32_t)")
        out = try cgen_put_u64(d, out, ordinal)
        out = try cgen_put(d, out, ") ")
        out = try cgen_emit_checked_edge(d, out, store, indexes, instruction, item)
        out = try cgen_put(d, out, "\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".alder_u.alder_p")
        out = try cgen_put_u64(d, out, ordinal)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_enum_construct() {
        let ordinal = cgen_variant_ordinal(store, indexes, item.type_op, item.name_start, item.name_end)
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_tag = (uint32_t)")
        out = try cgen_put_u64(d, out, ordinal)
        out = try cgen_put(d, out, ";\n")
        if cgen_variant_payload(store, item.type_op, ordinal) != mir_type_unit() {
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ".alder_u.alder_p")
            out = try cgen_put_u64(d, out, ordinal)
            out = try cgen_put(d, out, " = ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ";\n")
        }
        return Ok(out)
    }
    if item.op == mir_op_table_create() {
        out = try cgen_put(d, out, "  void *")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " = alder_domain_alloc(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", sizeof(AlderTable), _Alignof(AlderTable));\n  if (")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, " == NULL) { alder_runtime_panic(\"table.create: out of memory\"); }\n  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderTable *)")
        out = try cgen_put_tmp(d, out, item.result, "p")
        out = try cgen_put(d, out, ";\n  *")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderTable){0};\n  if (!alder_table_init(")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, item.type_op)
        out = try cgen_put(d, out, "), (uint64_t)_Alignof(")
        out = try cgen_put_type(d, out, store, item.type_op)
        return cgen_put(d, out, "))) { alder_runtime_panic(\"table.create failed\"); }\n")
    }
    if item.op == mir_op_table_insert() {
        let elem_type = cgen_value_type(store, indexes, item.function, item.b)
        if elem_type == mir_type_unit() { out = try cgen_put(d, out, "  uint8_t ")
        out = try cgen_put_tmp(d, out, item.result, "u")
        out = try cgen_put(d, out, " = (uint8_t)0;\n") }
        // A storage-bearing element is deep-copied into the table's own
        // domain first: the slot memcpy only duplicates the element struct,
        // so internal storage must already live where the table does, or it
        // would die with this function's storage domain while the table
        // outlives it.
        if elem_type != mir_type_unit() && !cgen_copy_trivial(store, elem_type) {
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_type(d, out, store, elem_type)
            out = try cgen_put(d, out, " ")
            out = try cgen_put_tmp(d, out, item.result, "e")
            out = try cgen_put(d, out, " = alder_copy_ty")
            out = try cgen_put_u64(d, out, elem_type - 1)
            out = try cgen_put(d, out, "(")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, "->domain, ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            out = try cgen_put(d, out, ", 1);\n")
        }
        out = try cgen_put(d, out, "  if (!alder_table_insert(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", &")
        if elem_type == mir_type_unit() { out = try cgen_put_tmp(d, out, item.result, "u") } else { if !cgen_copy_trivial(store, elem_type) { out = try cgen_put_tmp(d, out, item.result, "e") } else { out = try cgen_put_value(d, out, item.b) } }
        out = try cgen_put(d, out, ", &")
        out = try cgen_put_value(d, out, item.result)
        return cgen_put(d, out, ")) { alder_runtime_panic(\"table.insert failed\"); }\n")
    }
    if item.op == mir_op_table_insert_try() {
        // table.insert.try <table>, <elem> -> result(id(elem), elem). No
        // failure edge: exhaustion or the slot-limit policy is the Err
        // payload, which carries the element value back to the caller.
        let elem_type = cgen_value_type(store, indexes, item.function, item.b)
        if elem_type == mir_type_unit() { out = try cgen_put(d, out, "  uint8_t ")
        out = try cgen_put_tmp(d, out, item.result, "u")
        out = try cgen_put(d, out, " = (uint8_t)0;\n") }
        // Storage-bearing elements are deep-copied into the table's own
        // domain before the insert, like the panicking insert; a failed
        // insert never uses the copy, because the Err payload carries the
        // caller-owned element operand instead.
        if elem_type != mir_type_unit() && !cgen_copy_trivial(store, elem_type) {
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_type(d, out, store, elem_type)
            out = try cgen_put(d, out, " ")
            out = try cgen_put_tmp(d, out, item.result, "e")
            out = try cgen_put(d, out, " = alder_copy_ty")
            out = try cgen_put_u64(d, out, elem_type - 1)
            out = try cgen_put(d, out, "(")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, "->domain, ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
            out = try cgen_put(d, out, ", 1);\n")
        }
        out = try cgen_put(d, out, "  AlderTableId ")
        out = try cgen_put_tmp(d, out, item.result, "id")
        out = try cgen_put(d, out, ";\n  if (alder_table_insert(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", &")
        if elem_type == mir_type_unit() { out = try cgen_put_tmp(d, out, item.result, "u") } else { if !cgen_copy_trivial(store, elem_type) { out = try cgen_put_tmp(d, out, item.result, "e") } else { out = try cgen_put_value(d, out, item.b) } }
        out = try cgen_put(d, out, ", &")
        out = try cgen_put_tmp(d, out, item.result, "id")
        out = try cgen_put(d, out, ")) {\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_tag = (uint32_t)0;\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_u.alder_p0 = ")
        out = try cgen_put_tmp(d, out, item.result, "id")
        out = try cgen_put(d, out, ";\n  } else {\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_tag = (uint32_t)1;\n")
        if elem_type != mir_type_unit() {
            out = try cgen_put(d, out, "    ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ".alder_u.alder_p1 = ")
            out = try cgen_put_value(d, out, item.b)
            out = try cgen_put(d, out, ";\n")
        }
        return cgen_put(d, out, "  }\n")
    }
    if item.op == mir_op_table_lookup() || item.op == mir_op_table_lookup_mut() {
        out = try cgen_put(d, out, "  void *")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n  if (alder_table_lookup")
        if item.op == mir_op_table_lookup_mut() { out = try cgen_put(d, out, "_mut") }
        out = try cgen_put(d, out, "(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        out = try cgen_put(d, out, ", &")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ")) {\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_tag = (uint32_t)1;\n    ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, ".alder_u.alder_p1 = ")
        out = try cgen_put_tmp(d, out, item.result, "")
        out = try cgen_put(d, out, ";\n  } else {\n    ")
        out = try cgen_put_value(d, out, item.result)
        return cgen_put(d, out, ".alder_tag = (uint32_t)0;\n  }\n")
    }
    if item.op == mir_op_table_remove() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = alder_table_remove(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        return cgen_put(d, out, ");\n")
    }
    if item.op == mir_op_table_view_end() {
        out = try cgen_put(d, out, "  (void)")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ";\n")
    }
    if item.op >= mir_op_int_eq() && item.op <= mir_op_float_ge() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (bool)(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        if item.op == mir_op_int_eq() || item.op == mir_op_float_eq() { out = try cgen_put(d, out, " == ") }
        if item.op == mir_op_int_ne() || item.op == mir_op_float_ne() { out = try cgen_put(d, out, " != ") }
        if item.op == mir_op_int_lt() || item.op == mir_op_float_lt() { out = try cgen_put(d, out, " < ") }
        if item.op == mir_op_int_le() || item.op == mir_op_float_le() { out = try cgen_put(d, out, " <= ") }
        if item.op == mir_op_int_gt() || item.op == mir_op_float_gt() { out = try cgen_put(d, out, " > ") }
        if item.op == mir_op_int_ge() || item.op == mir_op_float_ge() { out = try cgen_put(d, out, " >= ") }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        return cgen_put(d, out, ");\n")
    }
    if item.op >= mir_op_int_trunc() && item.op <= mir_op_float_from_int() {
        let source_type = cgen_value_type(store, indexes, item.function, item.a)
        let signed_trunc = item.op == mir_op_int_trunc() && cgen_int_signed(item.type_op)
        if signed_trunc {
            out = try cgen_put(d, out, "  uint")
            out = try cgen_put_u64(d, out, cgen_int_width(item.type_op))
            out = try cgen_put(d, out, "_t ")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " = (uint")
            out = try cgen_put_u64(d, out, cgen_int_width(item.type_op))
            out = try cgen_put(d, out, "_t)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ";\n  memcpy(&")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ", &")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, ", sizeof(")
            out = try cgen_put_tmp(d, out, item.result, "")
            return cgen_put(d, out, "));\n")
        }
        if item.op == mir_op_float_convert() && source_type == mir_type_f64() && item.type_op == mir_type_f32() {
            out = try cgen_put(d, out, "  if (")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, " != ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, " || ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, " > (double)FLT_MAX || ")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, " < -(double)FLT_MAX) { alder_runtime_panic(\"float.convert: out of range\"); }\n")
        }
        if item.op == mir_op_int_from_float() {
            let width = cgen_int_width(item.type_op)
            let signed = cgen_int_signed(item.type_op)
            if width < 64 {
                out = try cgen_put(d, out, "  ")
                if signed { out = try cgen_put(d, out, "int64_t ") } else { out = try cgen_put(d, out, "uint64_t ") }
                out = try cgen_put_tmp(d, out, item.result, "")
                out = try cgen_put(d, out, ";\n")
            }
            out = try cgen_put(d, out, "  if (!alder_")
            if signed { out = try cgen_put(d, out, "i64_from_f64(") } else { out = try cgen_put(d, out, "u64_from_f64(") }
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            out = try cgen_put(d, out, ", &")
            if width == 64 { out = try cgen_put_value(d, out, item.result) } else { out = try cgen_put_tmp(d, out, item.result, "") }
            out = try cgen_put(d, out, ")) { alder_runtime_panic(\"int.from_float: out of range\"); }\n")
            if width == 64 { return Ok(out) }
            out = try cgen_put(d, out, "  if (")
            out = try cgen_put_tmp(d, out, item.result, "")
            if signed { out = try cgen_put(d, out, " < (int64_t)")
            out = try cgen_put_int_limit(d, out, true, width, true)
            out = try cgen_put(d, out, " || ")
            out = try cgen_put_tmp(d, out, item.result, "")
            out = try cgen_put(d, out, " > (int64_t)")
            out = try cgen_put_int_limit(d, out, true, width, false) } else { out = try cgen_put(d, out, " > (uint64_t)")
            out = try cgen_put_int_limit(d, out, false, width, false) }
            out = try cgen_put(d, out, ") { alder_runtime_panic(\"int.from_float: out of range\"); }\n  ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, item.type_op)
            out = try cgen_put(d, out, ")")
            out = try cgen_put_tmp(d, out, item.result, "")
            return cgen_put(d, out, ";\n")
        }
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (")
        out = try cgen_put_type(d, out, store, item.type_op)
        out = try cgen_put(d, out, ")")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_const_get() {
        let constant_id = cgen_const_id(store, indexes, item.name_start, item.name_end)
        let constant = __s0_buffer_get(MirConstRec, store.constants, constant_id - 1)
        if constant.const_type == mir_type_unit() { return Ok(out) }
        if constant.kind == mir_const_string() {
            out = try cgen_put(d, out, "  ")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, constant.const_type)
            out = try cgen_put(d, out, "){ alder_str_")
            out = try cgen_put_u64(d, out, constant_id - 1)
            out = try cgen_put(d, out, ", (uint64_t)")
            out = try cgen_put_u64(d, out, constant.string_end - constant.string_start)
            return cgen_put(d, out, " };\n")
        }
        if constant.kind == mir_const_float() {
            out = try cgen_put(d, out, "  memcpy(&")
            out = try cgen_put_value(d, out, item.result)
            out = try cgen_put(d, out, ", &alder_const_")
            out = try cgen_put_u64(d, out, constant_id - 1)
            out = try cgen_put(d, out, "_bits, sizeof(")
            out = try cgen_put_value(d, out, item.result)
            return cgen_put(d, out, "));\n")
        }
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = alder_const_")
        out = try cgen_put_u64(d, out, constant_id - 1)
        return cgen_put(d, out, ";\n")
    }
    if item.op == mir_op_call() || item.op == mir_op_ffi_call_unsafe() {
        out = try cgen_put(d, out, "  ")
        var result_type: U64 = 0
        if item.op == mir_op_call() { result_type = __s0_buffer_get(MirFunctionRec, store.functions, item.target - 1).result_type }
        else { result_type = __s0_buffer_get(MirImportRec, store.imports, item.target - 1).result_type }
        if result_type != mir_type_unit() { out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ") }
        if item.op == mir_op_call() { out = try cgen_emit_function_name(d, out, store, item.target) } else { out = try cgen_put(d, out, "(")
        let imported = __s0_buffer_get(MirImportRec, store.imports, item.target - 1)
        out = try cgen_put_name(d, out, store, imported.name_start, imported.name_end)
        out = try cgen_put(d, out, ")") }
        out = try cgen_put(d, out, "(")
        out = try cgen_emit_call_args(d, out, store, indexes, instruction, item, item.op == mir_op_ffi_call_unsafe())
        return cgen_put(d, out, ");\n")
    }
    if item.op == mir_op_call_value() {
        let fn_type = cgen_value_type(store, indexes, item.function, item.a)
        var result_type: U64 = mir_type_unit()
        var param_count: U64 = 0
        if fn_type >= 1 && fn_type <= __s0_buffer_len(MirTypeRec, store.types) && __s0_buffer_get(MirTypeRec, store.types, fn_type - 1).kind == mir_type_kind_function() {
            result_type = __s0_buffer_get(MirTypeRec, store.types, fn_type - 1).result_type
            param_count = mir_type_part_count(store, fn_type, mir_type_part_function_param())
        }
        out = try cgen_put(d, out, "  ")
        if result_type != mir_type_unit() { out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ") }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ".code(")
        let count = cgen_operand_count(store, indexes, mir_operand_instruction(), instruction, 0)
        var ordinal: U64 = 0
        var wrote = false
        while ordinal < count {
            if ordinal < param_count {
                let part = cgen_type_part(store, fn_type, mir_type_part_function_param(), ordinal)
                if part.part_type != mir_type_unit() {
                    if wrote { out = try cgen_put(d, out, ", ") }
                    let argument = cgen_operand(store, indexes, mir_operand_instruction(), instruction, 0, ordinal)
                    out = try cgen_put_value_read(d, out, store, indexes, item.function, argument.value)
                    wrote = true
                }
            }
            ordinal = ordinal + 1
        }
        if wrote { out = try cgen_put(d, out, ", ") }
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        return cgen_put(d, out, ".env);\n")
    }
    if item.op == mir_op_fn_value() {
        let fn_type = cgen_value_type(store, indexes, item.function, item.result)
        if fn_type < 1 || fn_type > __s0_buffer_len(MirTypeRec, store.types) || __s0_buffer_get(MirTypeRec, store.types, fn_type - 1).kind != mir_type_kind_function() {
            out = try cgen_put(d, out, "  /* fn.value without a function type */\n")
            return Ok(out)
        }
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = (AlderFnTy")
        out = try cgen_put_u64(d, out, fn_type - 1)
        out = try cgen_put(d, out, "){alder_fnwrap_")
        out = try cgen_put_u64(d, out, item.target - 1)
        out = try cgen_put(d, out, "_")
        out = try cgen_put_u64(d, out, fn_type - 1)
        out = try cgen_put(d, out, ", ")
        if item.a == 0 { out = try cgen_put(d, out, "NULL") } else {
            // The environment member is an opaque pointer; a reference-typed
            // environment value (the closure's record reference) passes its
            // data pointer.
            let env_operand_type = cgen_value_type(store, indexes, item.function, item.a)
            var ref_env = false
            if env_operand_type >= 1 && env_operand_type <= __s0_buffer_len(MirTypeRec, store.types) {
                let env_kind = __s0_buffer_get(MirTypeRec, store.types, env_operand_type - 1).kind
                if env_kind == mir_type_kind_slice() || env_kind == mir_type_kind_safe_ref() || env_kind == mir_type_kind_safe_mut() { ref_env = true }
            }
            out = try cgen_put(d, out, "(void *)")
            out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
            if ref_env { out = try cgen_put(d, out, ".data") }
        }
        out = try cgen_put(d, out, ", ")
        let env_aggregate = cgen_fn_env_aggregate(store, indexes, item.function, item.a)
        if env_aggregate != 0 {
            out = try cgen_put(d, out, "alder_env_retain_ty")
            out = try cgen_put_u64(d, out, env_aggregate - 1)
        } else {
            if item.a != 0 && item.type_op == mir_fn_value_domain_marker() { out = try cgen_put(d, out, "alder_env_retain_domain") } else { out = try cgen_put(d, out, "NULL") }
        }
        return cgen_put(d, out, "};\n")
    }
    if item.op == mir_op_str_eq() {
        let operand_type = cgen_value_type(store, indexes, item.function, item.a)
        var helper: __s0_String = "alder_string_eq"
        if operand_type >= 1 && operand_type <= __s0_buffer_len(MirTypeRec, store.types) && __s0_buffer_get(MirTypeRec, store.types, operand_type - 1).kind == mir_type_kind_bytes() { helper = "alder_bytes_eq" }
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_value(d, out, item.result)
        out = try cgen_put(d, out, " = ")
        out = try cgen_put(d, out, helper)
        out = try cgen_put(d, out, "(")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.a)
        out = try cgen_put(d, out, ", ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.b)
        return cgen_put(d, out, ");\n")
    }
    if item.op == mir_op_str_len() { return cgen_emit_str_len(d, out, store, indexes, instruction, item) }
    if item.op == mir_op_str_byte_checked() { return cgen_emit_str_byte_checked(d, out, store, indexes, instruction, item) }
    if item.op == mir_op_str_to_bytes() { return cgen_emit_str_to_bytes(d, out, store, indexes, instruction, item) }
    if item.op == mir_op_str_concat() { return cgen_emit_str_concat(d, out, store, indexes, instruction, item) }
    if item.op == mir_op_str_slice_checked() { return cgen_emit_str_slice_checked(d, out, store, indexes, instruction, item) }
    if item.op == mir_op_str_from_bytes() { return cgen_emit_str_from_bytes(d, out, store, indexes, instruction, item) }
    return Ok(out)
}

fn cgen_emit_terminator(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, terminator: U64, item: MirTermRec) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    if item.kind == mir_term_jump() {
        out = try cgen_put(d, out, "  ")
        out = try cgen_emit_edge(d, out, store, indexes, item.function, mir_operand_terminator_arg(), terminator, mir_edge_jump(), item.target)
        return cgen_put(d, out, "\n")
    }
    if item.kind == mir_term_branch() {
        out = try cgen_put(d, out, "  if (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.value)
        out = try cgen_put(d, out, ") ")
        out = try cgen_emit_edge(d, out, store, indexes, item.function, mir_operand_terminator_arg(), terminator, mir_edge_then(), item.then_block)
        out = try cgen_put(d, out, " else ")
        out = try cgen_emit_edge(d, out, store, indexes, item.function, mir_operand_terminator_arg(), terminator, mir_edge_else(), item.else_block)
        return cgen_put(d, out, "\n")
    }
    if item.kind == mir_term_switch() {
        let type_id = cgen_value_type(store, indexes, item.function, item.value)
        out = try cgen_put(d, out, "  switch (")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.value)
        out = try cgen_put(d, out, ".alder_tag) {\n")
        let count = cgen_operand_count(store, indexes, mir_operand_switch_case(), terminator, 0)
        var ordinal: U64 = 0
        while ordinal < count {
            let case_id = cgen_operand_id(store, indexes, mir_operand_switch_case(), terminator, 0, ordinal)
            let case = __s0_buffer_get(MirOperandRec, store.operands, case_id - 1)
            var variant: U64 = 0
            if case.name_start == case.name_end { out = try cgen_put(d, out, "  default:\n") } else { variant = cgen_variant_ordinal(store, indexes, type_id, case.name_start, case.name_end)
            out = try cgen_put(d, out, "  case (uint32_t)")
            out = try cgen_put_u64(d, out, variant)
            out = try cgen_put(d, out, ":\n") }
            if case.value != 0 && cgen_value_type(store, indexes, item.function, case.value) != mir_type_unit() {
                out = try cgen_put(d, out, "    ")
                out = try cgen_put_value(d, out, case.value)
                out = try cgen_put(d, out, " = ")
                out = try cgen_put_value_read(d, out, store, indexes, item.function, item.value)
                out = try cgen_put(d, out, ".alder_u.alder_p")
                out = try cgen_put_u64(d, out, variant)
                out = try cgen_put(d, out, ";\n")
            }
            out = try cgen_put(d, out, "    ")
            out = try cgen_emit_edge(d, out, store, indexes, item.function, mir_operand_switch_case_arg(), case_id, 0, case.target)
            out = try cgen_put(d, out, "\n")
            ordinal = ordinal + 1
        }
        return cgen_put(d, out, "  }\n")
    }
    if item.kind == mir_term_return() || item.kind == mir_term_fail() {
        let result_type = __s0_buffer_get(MirFunctionRec, store.functions, item.function - 1).result_type
        if result_type == mir_type_unit() { return cgen_put(d, out, "  return;\n") }
        out = try cgen_put(d, out, "  return ")
        out = try cgen_put_value_read(d, out, store, indexes, item.function, item.value)
        return cgen_put(d, out, ";\n")
    }
    if item.kind == mir_term_panic() { return cgen_put(d, out, "  alder_runtime_panic(\"checked operation failed\");\n") }
    return cgen_put(d, out, "  alder_runtime_panic(\"unreachable\");\n")
}

fn cgen_emit_function_body(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    var out = try cgen_put_function_linkage(d, initial, store, function)
    if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
    out = try cgen_put(d, out, " ")
    out = try cgen_emit_function_name(d, out, store, function)
    out = try cgen_put(d, out, "(")
    out = try cgen_emit_function_params(d, out, store, indexes, function)
    out = try cgen_put(d, out, ") {\n")
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let instruction = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if instruction.function == function && instruction.op == mir_op_domain_create() {
            out = try cgen_put(d, out, "  AlderDomain alder_domain_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = {0};\n")
        }
        if instruction.function == function && instruction.op == mir_op_cleanup_scope_begin() {
            out = try cgen_put(d, out, "  AlderCleanupScope alder_scope_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = {0};\n")
        }
        if instruction.function == function && instruction.op == mir_op_cleanup_push() {
            out = try cgen_put(d, out, "  AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " alder_ctx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = {0};\n")
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let value = __s0_buffer_get(MirValueRec, store.values, at)
        if value.function == function && value.def_kind != mir_value_def_function_param() && value.value_type != mir_type_unit() {
            out = try cgen_put(d, out, "  ALDER_MAYBE_UNUSED ")
            out = try cgen_put_type(d, out, store, value.value_type)
            out = try cgen_put(d, out, " ")
            out = try cgen_put_value(d, out, value.ordinal + 1)
            out = try cgen_put(d, out, ";\n")
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let local = __s0_buffer_get(MirLocalRec, store.locals, at)
        if local.function == function {
            out = try cgen_put(d, out, "  ALDER_MAYBE_UNUSED ")
            out = try cgen_put_type(d, out, store, local.local_type)
            out = try cgen_put(d, out, " ")
            out = try cgen_put_local(d, out, local.ordinal + 1)
            out = try cgen_put(d, out, ";\n")
        }
        at = at + 1
    }
    let parameters = cgen_function_param_count(store, indexes, function)
    var ordinal: U64 = 0
    while ordinal < parameters {
        let parameter = cgen_function_param(store, indexes, function, ordinal)
        if parameter.param_type != mir_type_unit() { out = try cgen_put(d, out, "  (void)")
        out = try cgen_put_value(d, out, parameter.value)
        out = try cgen_put(d, out, ";\n") }
        ordinal = ordinal + 1
    }
    out = try cgen_put(d, out, "\n")
    let bcount = mir_vindex_block_count(indexes, function)
    var block: U64 = 1
    while block <= bcount {
        if block > 1 { out = try cgen_put(d, out, "alder_b")
        out = try cgen_put_u64(d, out, block - 1)
        out = try cgen_put(d, out, ": ALDER_MAYBE_UNUSED ;\n") }
        let icount = mir_vindex_instr_count(indexes, function, block)
        var instruction_ordinal: U64 = 0
        while instruction_ordinal < icount {
            let instruction = mir_vindex_instr(indexes, function, block, instruction_ordinal)
            out = try cgen_emit_instruction(d, out, store, indexes, instruction, __s0_buffer_get(MirInstrRec, store.instructions, instruction - 1))
            instruction_ordinal = instruction_ordinal + 1
        }
        let term = cgen_term(store, indexes, function, block)
        out = try cgen_emit_terminator(d, out, store, indexes, term.id, __s0_buffer_get(MirTermRec, store.terminators, term.id - 1))
        block = block + 1
    }
    return cgen_put(d, out, "}\n\n")
}

fn cgen_emit_bodies(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let indexes = try mir_vindex_build(d, store)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        out = try cgen_emit_function_body(d, out, store, indexes, function)
        function = function + 1
    }
    return Ok(out)
}
