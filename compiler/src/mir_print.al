// Canonical textual MIR 4 printer for the independent flat store. Validation
// is deliberately separate from emission: malformed stores produce no partial
// MIR and are never repaired or normalized.

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

fn mir_value_count(store: MirStore, function: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        if __s0_buffer_get(MirValueRec, store.values, at).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_block_count(store: MirStore, function: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        if __s0_buffer_get(MirBlockRec, store.blocks, at).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_local_count(store: MirStore, function: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        if __s0_buffer_get(MirLocalRec, store.locals, at).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_value_valid(store: MirStore, function: U64, id: U64) -> Bool {
    if id == 0 { return false }
    var found: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let rec = __s0_buffer_get(MirValueRec, store.values, at)
        if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
        at = at + 1
    }
    return found == 1
}

fn mir_block_valid(store: MirStore, function: U64, id: U64) -> Bool {
    if id == 0 { return false }
    var found: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, at)
        if rec.function == function && rec.ordinal + 1 == id { found = found + 1 }
        at = at + 1
    }
    return found == 1
}

fn mir_local_valid(store: MirStore, function: U64, id: U64) -> Bool {
    if id == 0 { return false }
    var found: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, at)
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

fn mir_operand_ordinal_once(store: MirStore, kind: U64, owner: U64, edge: U64, ordinal: U64) -> Bool {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
        if rec.kind == kind && rec.owner == owner && rec.edge == edge && rec.ordinal == ordinal { count = count + 1 }
        at = at + 1
    }
    return count == 1
}

fn mir_operand_group_valid(store: MirStore, kind: U64, owner: U64, edge: U64) -> Bool {
    let count = mir_operand_count(store, kind, owner, edge)
    var ordinal: U64 = 0
    while ordinal < count {
        if !mir_operand_ordinal_once(store, kind, owner, edge, ordinal) { return false }
        ordinal = ordinal + 1
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

fn mir_type_part_ordinal_once(store: MirStore, owner: U64, kind: U64, ordinal: U64) -> Bool {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if rec.owner == owner && rec.kind == kind && rec.ordinal == ordinal { count = count + 1 }
        at = at + 1
    }
    return count == 1
}

fn mir_type_part_group_valid(store: MirStore, owner: U64, kind: U64) -> Bool {
    let count = mir_type_part_count(store, owner, kind)
    var ordinal: U64 = 0
    while ordinal < count {
        if !mir_type_part_ordinal_once(store, owner, kind, ordinal) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_validate_types(store: MirStore) -> Bool {
    let length = __s0_buffer_len(MirTypeRec, store.types)
    if length < mir_primitive_type_count() { return false }
    var at: U64 = 0
    while at < length {
        let rec = __s0_buffer_get(MirTypeRec, store.types, at)
        let id = at + 1
        if at < mir_primitive_type_count() {
            if rec.kind != mir_type_kind_primitive() || rec.name_start != 0 || rec.name_end != 0 || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 || rec.length != 0 { return false }
        } else {
            if rec.kind == mir_type_kind_primitive() || rec.kind > mir_type_kind_vec() { return false }
            if rec.kind == mir_type_kind_aggregate() || rec.kind == mir_type_kind_enum() {
                if !mir_name_valid(store, rec.name_start, rec.name_end, true) || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 || rec.length != 0 { return false }
                var part_kind = mir_type_part_variant()
                if rec.kind == mir_type_kind_aggregate() { part_kind = mir_type_part_field() }
                if !mir_type_part_group_valid(store, id, part_kind) { return false }
            } else {
                if rec.name_start != 0 || rec.name_end != 0 { return false }
                if rec.kind == mir_type_kind_result() {
                    if !mir_type_valid(store, rec.ok_type) || !mir_type_valid(store, rec.err_type) || rec.elem != 0 { return false }
                }
                if rec.kind == mir_type_kind_function() {
                    if !mir_type_valid(store, rec.result_type) || rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 { return false }
                    let param_count = mir_type_part_count(store, id, mir_type_part_function_param())
                    if mir_type_part_count(store, id, mir_type_part_function_env()) > 1 { return false }
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
                if rec.kind == mir_type_kind_domain_handle() || rec.kind == mir_type_kind_domain_mark() || rec.kind == mir_type_kind_cleanup_scope() || rec.kind == mir_type_kind_cleanup_id() || rec.kind == mir_type_kind_string() || rec.kind == mir_type_kind_bytes() {
                    if rec.elem != 0 || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 { return false }
                }
                if rec.kind != mir_type_kind_result() && rec.kind != mir_type_kind_function() && rec.kind != mir_type_kind_domain_handle() && rec.kind != mir_type_kind_domain_mark() && rec.kind != mir_type_kind_cleanup_scope() && rec.kind != mir_type_kind_cleanup_id() && rec.kind != mir_type_kind_string() && rec.kind != mir_type_kind_bytes() {
                    if !mir_type_valid(store, rec.elem) || rec.ok_type != 0 || rec.err_type != 0 || rec.first_part != 0 || rec.part_count != 0 || rec.result_type != 0 { return false }
                }
                if rec.kind != mir_type_kind_array() && rec.length != 0 { return false }
            }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
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
        if part.kind < mir_type_part_field() || part.kind > mir_type_part_function_env() { return false }
        at = at + 1
    }
    return true
}

fn mir_param_group_count(store: MirStore, kind: U64, function: U64, block: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let rec = __s0_buffer_get(MirParamRec, store.params, at)
        if rec.kind == kind && rec.function == function && rec.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_param_group_valid(store: MirStore, kind: U64, function: U64, block: U64) -> Bool {
    let count = mir_param_group_count(store, kind, function, block)
    var ordinal: U64 = 0
    while ordinal < count {
        var found: U64 = 0
        var at: U64 = 0
        while at < __s0_buffer_len(MirParamRec, store.params) {
            let rec = __s0_buffer_get(MirParamRec, store.params, at)
            if rec.kind == kind && rec.function == function && rec.block == block && rec.ordinal == ordinal { found = found + 1 }
            at = at + 1
        }
        if found != 1 { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_instr_group_count(store: MirStore, function: U64, block: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if rec.function == function && rec.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn mir_instr_group_valid(store: MirStore, function: U64, block: U64) -> Bool {
    let count = mir_instr_group_count(store, function, block)
    var ordinal: U64 = 0
    while ordinal < count {
        var found: U64 = 0
        var at: U64 = 0
        while at < __s0_buffer_len(MirInstrRec, store.instructions) {
            let rec = __s0_buffer_get(MirInstrRec, store.instructions, at)
            if rec.function == function && rec.block == block && rec.ordinal == ordinal { found = found + 1 }
            at = at + 1
        }
        if found != 1 { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_instr_produces(op: U64) -> Bool {
    return op != mir_op_store() && op != mir_op_domain_reset() && op != mir_op_domain_destroy() && op != mir_op_cleanup_disarm() && op != mir_op_cleanup_scope_run() && op != mir_op_cleanup_scope_end() && op != mir_op_table_view_end()
}

fn mir_instr_checked(op: U64) -> Bool {
    return op == mir_op_alloc_checked() || (op >= mir_op_int_add_checked() && op <= mir_op_int_shr_checked()) || op == mir_op_slice_index_checked() || op == mir_op_array_index_checked() || op == mir_op_slice_range_checked() || op == mir_op_enum_payload_checked() || op == mir_op_vec_construct_checked() || op == mir_op_vec_grow_checked()
}

fn mir_instruction_operands_valid(store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if rec.op == mir_op_load() || rec.op == mir_op_store() || rec.op == mir_op_borrow() || rec.op == mir_op_borrow_mut() {
        if !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) || __s0_buffer_get(MirPlaceRec, store.places, rec.place - 1).function != rec.function { return false }
        if rec.op == mir_op_store() && !mir_value_valid(store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_aggregate_construct() {
        if !mir_type_valid(store, rec.type_op) || !mir_operand_group_valid(store, mir_operand_aggregate_field(), id, 0) { return false }
    }
    if rec.op == mir_op_domain_create() || rec.op == mir_op_domain_mark() || rec.op == mir_op_domain_destroy() || rec.op == mir_op_slice_len() || rec.op == mir_op_cleanup_disarm() || rec.op == mir_op_cleanup_scope_run() || rec.op == mir_op_cleanup_scope_end() || rec.op == mir_op_table_view_end() || (rec.op >= mir_op_vec_len() && rec.op <= mir_op_vec_as_mut_slice()) || rec.op == mir_op_array_as_slice() {
        if !mir_value_valid(store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_domain_reset() || (rec.op >= mir_op_int_add_checked() && rec.op <= mir_op_int_shr_checked()) || (rec.op >= mir_op_int_eq() && rec.op <= mir_op_float_ge()) || rec.op == mir_op_table_insert() || rec.op == mir_op_table_lookup() || rec.op == mir_op_table_lookup_mut() || rec.op == mir_op_table_remove() || rec.op == mir_op_slice_index_checked() || rec.op == mir_op_array_index_checked() || rec.op == mir_op_copy_to_domain() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_value_valid(store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_alloc() || rec.op == mir_op_alloc_checked() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_type_valid(store, rec.type_op) || !mir_value_valid(store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_cleanup_push() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_function_valid(store, rec.target) || !mir_operand_group_valid(store, mir_operand_instruction(), id, 0) { return false }
    }
    if rec.op == mir_op_slice_range_checked() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_value_valid(store, rec.function, rec.b) || !mir_value_valid(store, rec.function, rec.c) { return false }
    }
    if rec.op == mir_op_vec_new() {
        if !mir_type_valid(store, rec.type_op) { return false }
    }
    if rec.op == mir_op_vec_construct_checked() || rec.op == mir_op_vec_grow_checked() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_value_valid(store, rec.function, rec.b) || !mir_value_valid(store, rec.function, rec.c) { return false }
    }
    if rec.op == mir_op_enum_payload_checked() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    }
    if rec.op == mir_op_enum_construct() {
        if !mir_type_valid(store, rec.type_op) || !mir_name_valid(store, rec.name_start, rec.name_end, true) || rec.a != 0 && !mir_value_valid(store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_table_create() {
        if !mir_type_valid(store, rec.type_op) || !mir_value_valid(store, rec.function, rec.a) { return false }
    }
    if rec.op >= mir_op_int_trunc() && rec.op <= mir_op_float_from_int() {
        if !mir_value_valid(store, rec.function, rec.a) || !mir_type_valid(store, rec.type_op) { return false }
    }
    if rec.op == mir_op_const_get() && !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    if (rec.op == mir_op_call() || rec.op == mir_op_ffi_call_unsafe() || rec.op == mir_op_call_value()) && !mir_operand_group_valid(store, mir_operand_instruction(), id, 0) { return false }
    return true
}

fn mir_validate_instruction_refs(store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if rec.op > mir_op_fn_value() || !mir_block_valid(store, rec.function, rec.block) || !mir_instruction_operands_valid(store, id, rec) { return false }
    var may_omit_result = false
    if rec.op == mir_op_call() && mir_function_valid(store, rec.target) && __s0_buffer_get(MirFunctionRec, store.functions, rec.target - 1).result_type == mir_type_unit() { may_omit_result = true }
    if rec.op == mir_op_ffi_call_unsafe() && mir_import_valid(store, rec.target) && __s0_buffer_get(MirImportRec, store.imports, rec.target - 1).result_type == mir_type_unit() { may_omit_result = true }
    if rec.op == mir_op_fn_value() && mir_value_valid(store, rec.function, rec.result) {
        let ft = __s0_buffer_get(MirValueRec, store.values, rec.result - 1).value_type
        if ft >= 1 && ft <= __s0_buffer_len(MirTypeRec, store.types) && __s0_buffer_get(MirTypeRec, store.types, ft - 1).kind == mir_type_kind_function() && __s0_buffer_get(MirTypeRec, store.types, ft - 1).result_type == mir_type_unit() { may_omit_result = true }
    }
    if rec.op == mir_op_call_value() && mir_value_valid(store, rec.function, rec.a) {
        let ft = __s0_buffer_get(MirValueRec, store.values, rec.a - 1).value_type
        if ft >= 1 && ft <= __s0_buffer_len(MirTypeRec, store.types) && __s0_buffer_get(MirTypeRec, store.types, ft - 1).kind == mir_type_kind_function() && __s0_buffer_get(MirTypeRec, store.types, ft - 1).result_type == mir_type_unit() { may_omit_result = true }
    }
    if mir_instr_produces(rec.op) && !may_omit_result {
        if !mir_value_valid(store, rec.function, rec.result) { return false }
    }
    if may_omit_result && rec.result != 0 { return false }
    if !mir_instr_produces(rec.op) && rec.result != 0 { return false }
    if rec.place != 0 && !mir_id_valid(rec.place, __s0_buffer_len(MirPlaceRec, store.places)) { return false }
    if rec.type_op != 0 && !mir_type_valid(store, rec.type_op) { return false }
    if rec.a != 0 && !mir_value_valid(store, rec.function, rec.a) { return false }
    if rec.b != 0 && !mir_value_valid(store, rec.function, rec.b) { return false }
    if rec.c != 0 && !mir_value_valid(store, rec.function, rec.c) { return false }
    if !mir_name_range_valid(store, rec.name_start, rec.name_end) { return false }
    if mir_instr_checked(rec.op) {
        if !mir_block_valid(store, rec.function, rec.target) || !mir_operand_group_valid(store, mir_operand_checked_edge_arg(), id, 0) { return false }
    }
    if !mir_instr_checked(rec.op) && mir_operand_count(store, mir_operand_checked_edge_arg(), id, 0) != 0 { return false }
    if rec.op == mir_op_call() || rec.op == mir_op_cleanup_push() || rec.op == mir_op_fn_value() {
        if !mir_function_valid(store, rec.target) { return false }
    }
    if rec.op == mir_op_ffi_call_unsafe() {
        if !mir_import_valid(store, rec.target) { return false }
    }
    if rec.op == mir_op_const_get() || rec.op == mir_op_enum_payload_checked() || rec.op == mir_op_enum_construct() {
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
    }
    if rec.op != mir_op_const_get() && rec.op != mir_op_enum_payload_checked() && rec.op != mir_op_enum_construct() && rec.name_start != rec.name_end { return false }
    if !mir_operand_group_valid(store, mir_operand_instruction(), id, 0) || !mir_operand_group_valid(store, mir_operand_aggregate_field(), id, 0) { return false }
    return true
}

fn mir_validate_functions(store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, at)
        let function = at + 1
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) || !mir_type_valid(store, rec.result_type) || !mir_param_group_valid(store, mir_param_function(), function, 0) { return false }
        let blocks = mir_block_count(store, function)
        if blocks == 0 || mir_value_count(store, function) == 0 && mir_param_group_count(store, mir_param_function(), function, 0) != 0 { return false }
        var ordinal: U64 = 0
        while ordinal < mir_local_count(store, function) {
            if !mir_local_valid(store, function, ordinal + 1) { return false }
            ordinal = ordinal + 1
        }
        ordinal = 0
        while ordinal < blocks {
            let block = ordinal + 1
            if !mir_block_valid(store, function, block) || !mir_param_group_valid(store, mir_param_block(), function, block) || !mir_instr_group_valid(store, function, block) { return false }
            var terms: U64 = 0
            var term_at: U64 = 0
            while term_at < __s0_buffer_len(MirTermRec, store.terminators) {
                let term = __s0_buffer_get(MirTermRec, store.terminators, term_at)
                if term.function == function && term.block == block { terms = terms + 1 }
                term_at = term_at + 1
            }
            if terms != 1 { return false }
            ordinal = ordinal + 1
        }
        ordinal = 0
        while ordinal < mir_value_count(store, function) {
            if !mir_value_valid(store, function, ordinal + 1) { return false }
            ordinal = ordinal + 1
        }
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
        if !mir_function_valid(store, rec.function) || !mir_name_valid(store, rec.name_start, rec.name_end, false) || !mir_type_valid(store, rec.param_type) || !mir_value_valid(store, rec.function, rec.value) { return false }
        if rec.kind == mir_param_function() {
            if rec.block != 0 { return false }
        }
        if rec.kind == mir_param_block() {
            if !mir_block_valid(store, rec.function, rec.block) { return false }
        }
        if rec.kind != mir_param_function() && rec.kind != mir_param_block() { return false }
        var links: U64 = 0
        var value_at: U64 = 0
        while value_at < __s0_buffer_len(MirValueRec, store.values) {
            let value = __s0_buffer_get(MirValueRec, store.values, value_at)
            var want_kind = mir_value_def_block_param()
            if rec.kind == mir_param_function() { want_kind = mir_value_def_function_param() }
            if value.function == rec.function && value.ordinal + 1 == rec.value && value.def_kind == want_kind && value.block == rec.block && value.item == rec.ordinal + 1 { links = links + 1 }
            value_at = value_at + 1
        }
        if links != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let rec = __s0_buffer_get(MirValueRec, store.values, at)
        if !mir_function_valid(store, rec.function) || !mir_name_valid(store, rec.name_start, rec.name_end, false) || !mir_type_valid(store, rec.value_type) || rec.def_kind > mir_value_def_switch_case() || rec.item == 0 { return false }
        if rec.def_kind != mir_value_def_function_param() && !mir_block_valid(store, rec.function, rec.block) { return false }
        if rec.def_kind == mir_value_def_instruction() {
            var links: U64 = 0
            var instruction_at: U64 = 0
            while instruction_at < __s0_buffer_len(MirInstrRec, store.instructions) {
                let instruction = __s0_buffer_get(MirInstrRec, store.instructions, instruction_at)
                if instruction.function == rec.function && instruction.block == rec.block && instruction.ordinal + 1 == rec.item && instruction.result == rec.ordinal + 1 { links = links + 1 }
                instruction_at = instruction_at + 1
            }
            if links != 1 { return false }
        }
        at = at + 1
    }
    return true
}

fn mir_validate_places(store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirPlaceRec, store.places) {
        let rec = __s0_buffer_get(MirPlaceRec, store.places, at)
        if !mir_function_valid(store, rec.function) { return false }
        if rec.kind == mir_place_local() {
            if !mir_local_valid(store, rec.function, rec.local) || rec.base != 0 || rec.field_start != 0 || rec.field_end != 0 || rec.deref_value != 0 { return false }
        }
        if rec.kind == mir_place_field() {
            if !mir_id_valid(rec.base, __s0_buffer_len(MirPlaceRec, store.places)) || rec.base >= at + 1 || __s0_buffer_get(MirPlaceRec, store.places, rec.base - 1).function != rec.function || !mir_name_valid(store, rec.field_start, rec.field_end, true) || rec.local != 0 || rec.deref_value != 0 { return false }
        }
        if rec.kind == mir_place_deref() {
            if !mir_value_valid(store, rec.function, rec.deref_value) || rec.local != 0 || rec.base != 0 || rec.field_start != 0 || rec.field_end != 0 { return false }
        }
        if rec.kind > mir_place_deref() { return false }
        at = at + 1
    }
    return true
}

fn mir_validate_declarations(store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let rec = __s0_buffer_get(MirImportRec, store.imports, at)
        if !mir_name_valid(store, rec.name_start, rec.name_end, true) || !mir_type_valid(store, rec.result_type) || !mir_operand_group_valid(store, mir_operand_import_param(), at + 1, 0) { return false }
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

fn mir_validate_terminators(store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTermRec, store.terminators) {
        let rec = __s0_buffer_get(MirTermRec, store.terminators, at)
        let id = at + 1
        if !mir_function_valid(store, rec.function) || !mir_block_valid(store, rec.function, rec.block) || rec.kind > mir_term_panic() { return false }
        if rec.kind == mir_term_jump() {
            if !mir_block_valid(store, rec.function, rec.target) || !mir_operand_group_valid(store, mir_operand_terminator_arg(), id, mir_edge_jump()) { return false }
        }
        if rec.kind == mir_term_branch() {
            if !mir_value_valid(store, rec.function, rec.value) || !mir_block_valid(store, rec.function, rec.then_block) || !mir_block_valid(store, rec.function, rec.else_block) || !mir_operand_group_valid(store, mir_operand_terminator_arg(), id, mir_edge_then()) || !mir_operand_group_valid(store, mir_operand_terminator_arg(), id, mir_edge_else()) { return false }
        }
        if rec.kind == mir_term_switch() {
            if !mir_value_valid(store, rec.function, rec.value) || !mir_operand_group_valid(store, mir_operand_switch_case(), id, 0) { return false }
        }
        if rec.kind == mir_term_return() {
            if rec.value != 0 && !mir_value_valid(store, rec.function, rec.value) { return false }
        }
        if rec.kind == mir_term_fail() {
            if !mir_value_valid(store, rec.function, rec.value) { return false }
        }
        at = at + 1
    }
    return true
}

fn mir_validate_operands(store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
        if rec.kind < mir_operand_type_part() || rec.kind > mir_operand_aggregate_field() { return false }
        if rec.kind == mir_operand_type_part() {
            if !mir_type_valid(store, rec.owner) || !mir_type_valid(store, rec.operand_type) { return false }
        }
        if rec.kind == mir_operand_import_param() {
            if !mir_import_valid(store, rec.owner) || !mir_type_valid(store, rec.operand_type) { return false }
        }
        if rec.kind == mir_operand_instruction() || rec.kind == mir_operand_checked_edge_arg() || rec.kind == mir_operand_aggregate_field() {
            if !mir_id_valid(rec.owner, __s0_buffer_len(MirInstrRec, store.instructions)) { return false }
            let instruction = __s0_buffer_get(MirInstrRec, store.instructions, rec.owner - 1)
            if rec.value != 0 && !mir_value_valid(store, instruction.function, rec.value) { return false }
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
            if rec.value != 0 && !mir_value_valid(store, term.function, rec.value) { return false }
            if !mir_block_valid(store, term.function, rec.target) { return false }
            if rec.kind == mir_operand_terminator_arg() {
                if rec.edge == mir_edge_jump() && (term.kind != mir_term_jump() || rec.target != term.target) { return false }
                if rec.edge == mir_edge_then() && (term.kind != mir_term_branch() || rec.target != term.then_block) { return false }
                if rec.edge == mir_edge_else() && (term.kind != mir_term_branch() || rec.target != term.else_block) { return false }
                if rec.edge > mir_edge_else() { return false }
            }
            if rec.kind == mir_operand_switch_case() {
                if term.kind != mir_term_switch() { return false }
                if rec.name_start != rec.name_end && !mir_name_valid(store, rec.name_start, rec.name_end, true) { return false }
                if !mir_operand_group_valid(store, mir_operand_switch_case_arg(), at + 1, 0) { return false }
                if rec.value != 0 {
                    var links: U64 = 0
                    var value_at: U64 = 0
                    while value_at < __s0_buffer_len(MirValueRec, store.values) {
                        let value = __s0_buffer_get(MirValueRec, store.values, value_at)
                        if value.function == term.function && value.ordinal + 1 == rec.value && value.def_kind == mir_value_def_switch_case() && value.block == term.block && value.item == rec.ordinal + 1 { links = links + 1 }
                        value_at = value_at + 1
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
            if !mir_value_valid(store, term.function, rec.value) { return false }
        }
        at = at + 1
    }
    return true
}

fn mir_store_valid(store: MirStore) -> Bool {
    if mir_format_version() != 5 || !mir_validate_types(store) || !mir_validate_declarations(store) || !mir_validate_functions(store) || !mir_validate_places(store) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let rec = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if !mir_validate_instruction_refs(store, at + 1, rec) { return false }
        at = at + 1
    }
    return mir_validate_terminators(store) && mir_validate_operands(store)
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

fn mir_out_type_part_type(store: MirStore, owner: U64, kind: U64, ordinal: U64, depth: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if rec.owner == owner && rec.kind == kind && rec.ordinal == ordinal { return mir_out_type(store, rec.part_type, depth) }
        at = at + 1
    }
    return false
}

fn mir_out_type(store: MirStore, id: U64, depth: U64) -> Bool {
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
    if rec.kind == mir_type_kind_option() { return out_string("option(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_result() { return out_string("result(") && mir_out_type(store, rec.ok_type, depth - 1) && out_string(", ") && mir_out_type(store, rec.err_type, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_slice() { return out_string("slice(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_safe_ref() { return out_string("safe_ref(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_safe_mut() { return out_string("safe_mut(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_raw_ptr() { return out_string("raw_ptr(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_domain_handle() { return out_string("domain_handle") }
    if rec.kind == mir_type_kind_domain_mark() { return out_string("domain_mark") }
    if rec.kind == mir_type_kind_cleanup_scope() { return out_string("cleanup_scope") }
    if rec.kind == mir_type_kind_cleanup_id() { return out_string("cleanup_id") }
    if rec.kind == mir_type_kind_table() { return out_string("table(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_id() { return out_string("id(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_table_view() { return out_string("table_view(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_table_mut_view() { return out_string("table_mut_view(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_array() { return out_string("array(") && mir_out_type(store, rec.elem, depth - 1) && out_string(", ") && out_u64(rec.length) && out(41) }
    if rec.kind == mir_type_kind_string() { return out_string("string") }
    if rec.kind == mir_type_kind_bytes() { return out_string("bytes") }
    if rec.kind == mir_type_kind_vec() { return out_string("vec(") && mir_out_type(store, rec.elem, depth - 1) && out(41) }
    if rec.kind == mir_type_kind_function() {
        if !out_string("function(fn(") { return false }
        let param_count = mir_type_part_count(store, id, mir_type_part_function_param())
        var ordinal: U64 = 0
        while ordinal < param_count {
            if ordinal > 0 && !out_string(", ") { return false }
            if !mir_out_type_part_type(store, id, mir_type_part_function_param(), ordinal, depth - 1) { return false }
            ordinal = ordinal + 1
        }
        if !out_string(") -> ") || !mir_out_type(store, rec.result_type, depth - 1) { return false }
        if mir_type_part_count(store, id, mir_type_part_function_env()) != 0 {
            if !out_string(", ") || !mir_out_type_part_type(store, id, mir_type_part_function_env(), 0, depth - 1) { return false }
        }
        return out(41)
    }
    return false
}

fn mir_out_value(store: MirStore, function: U64, id: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirValueRec, store.values) {
        let rec = __s0_buffer_get(MirValueRec, store.values, at)
        if rec.function == function && rec.ordinal + 1 == id { return out(37) && mir_out_name(store, rec.name_start, rec.name_end) }
        at = at + 1
    }
    return false
}

fn mir_out_block_name(store: MirStore, function: U64, id: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, store.blocks) {
        let rec = __s0_buffer_get(MirBlockRec, store.blocks, at)
        if rec.function == function && rec.ordinal + 1 == id { return mir_out_name(store, rec.name_start, rec.name_end) }
        at = at + 1
    }
    return false
}

fn mir_out_local_name(store: MirStore, function: U64, id: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirLocalRec, store.locals) {
        let rec = __s0_buffer_get(MirLocalRec, store.locals, at)
        if rec.function == function && rec.ordinal + 1 == id { return mir_out_name(store, rec.name_start, rec.name_end) }
        at = at + 1
    }
    return false
}

fn mir_out_place(store: MirStore, function: U64, id: U64) -> Bool {
    let rec = __s0_buffer_get(MirPlaceRec, store.places, id - 1)
    if rec.kind == mir_place_local() { return out_string("local %") && mir_out_local_name(store, function, rec.local) }
    if rec.kind == mir_place_field() { return out_string("field(") && mir_out_place(store, function, rec.base) && out_string(", ") && mir_out_name(store, rec.field_start, rec.field_end) && out(41) }
    return out_string("deref ") && mir_out_value(store, function, rec.deref_value)
}

fn mir_out_operand_values(store: MirStore, kind: U64, owner: U64, edge: U64, function: U64) -> Bool {
    let count = mir_operand_count(store, kind, owner, edge)
    var ordinal: U64 = 0
    while ordinal < count {
        var at: U64 = 0
        while at < __s0_buffer_len(MirOperandRec, store.operands) {
            let rec = __s0_buffer_get(MirOperandRec, store.operands, at)
            if rec.kind == kind && rec.owner == owner && rec.edge == edge && rec.ordinal == ordinal {
                if ordinal > 0 && !out_string(", ") { return false }
                if !mir_out_value(store, function, rec.value) { return false }
            }
            at = at + 1
        }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_out_block_ref(store: MirStore, function: U64, target: U64, kind: U64, owner: U64, edge: U64) -> Bool {
    if !mir_out_block_name(store, function, target) { return false }
    if mir_operand_count(store, kind, owner, edge) > 0 { return out(40) && mir_out_operand_values(store, kind, owner, edge, function) && out(41) }
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

fn mir_out_fail_edge(store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if !out_string(" else ") { return false }
    return mir_out_block_ref(store, rec.function, rec.target, mir_operand_checked_edge_arg(), id, 0)
}

fn mir_out_instruction(store: MirStore, id: U64, rec: MirInstrRec) -> Bool {
    if !out_string("  ") { return false }
    if rec.result != 0 && (!mir_out_value(store, rec.function, rec.result) || !out_string(" = ")) { return false }
    if !mir_out_op(rec.op) { return false }
    if rec.op == mir_op_load() || rec.op == mir_op_borrow() || rec.op == mir_op_borrow_mut() {
        if !out(32) || !mir_out_place(store, rec.function, rec.place) { return false }
    }
    if rec.op == mir_op_store() {
        if !out(32) || !mir_out_place(store, rec.function, rec.place) || !out_string(", ") || !mir_out_value(store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_aggregate_construct() {
        if !out(32) || !mir_out_type(store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(" { ") { return false }
        let count = mir_operand_count(store, mir_operand_aggregate_field(), id, 0)
        var ordinal: U64 = 0
        while ordinal < count {
            var at: U64 = 0
            while at < __s0_buffer_len(MirOperandRec, store.operands) {
                let field = __s0_buffer_get(MirOperandRec, store.operands, at)
                if field.kind == mir_operand_aggregate_field() && field.owner == id && field.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    let aggregate = __s0_buffer_get(MirTypeRec, store.types, rec.type_op - 1)
                    if aggregate.kind != mir_type_kind_array() && (!mir_out_name(store, field.name_start, field.name_end) || !out_string(": ")) { return false }
                    if !mir_out_value(store, rec.function, field.value) { return false }
                }
                at = at + 1
            }
            ordinal = ordinal + 1
        }
        if !out_string(" }") { return false }
    }
    if rec.op == mir_op_domain_create() || rec.op == mir_op_domain_mark() || rec.op == mir_op_domain_destroy() || rec.op == mir_op_slice_len() || rec.op == mir_op_cleanup_disarm() || rec.op == mir_op_cleanup_scope_run() || rec.op == mir_op_cleanup_scope_end() || rec.op == mir_op_table_view_end() || (rec.op >= mir_op_vec_len() && rec.op <= mir_op_vec_as_mut_slice()) || rec.op == mir_op_array_as_slice() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) { return false }
    }
    if rec.op == mir_op_domain_reset() || (rec.op >= mir_op_int_eq() && rec.op <= mir_op_float_ge()) || rec.op == mir_op_table_insert() || rec.op == mir_op_table_lookup() || rec.op == mir_op_table_lookup_mut() || rec.op == mir_op_table_remove() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_alloc() || rec.op == mir_op_alloc_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) { return false }
        if rec.op == mir_op_alloc_checked() && !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_copy_to_domain() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_cleanup_push() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", @") || !mir_out_function_name(store, rec.target) || !out_string(", (") || !mir_out_operand_values(store, mir_operand_instruction(), id, 0, rec.function) || !out(41) { return false }
    }
    if rec.op >= mir_op_int_add_checked() && rec.op <= mir_op_int_shr_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) || !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_slice_index_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) || !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_array_index_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) || !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_slice_range_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) || !out_string(", ") || !mir_out_value(store, rec.function, rec.c) || !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_vec_new() {
        if !out(32) || !mir_out_type(store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_vec_construct_checked() || rec.op == mir_op_vec_grow_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) || !out_string(", ") || !mir_out_value(store, rec.function, rec.c) || !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_enum_payload_checked() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_name(store, rec.name_start, rec.name_end) || !mir_out_fail_edge(store, id, rec) { return false }
    }
    if rec.op == mir_op_enum_construct() {
        if !out(32) || !mir_out_type(store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(", ") || !mir_out_name(store, rec.name_start, rec.name_end) { return false }
        if rec.a != 0 && (!out_string(", ") || !mir_out_value(store, rec.function, rec.a)) { return false }
    }
    if rec.op == mir_op_table_create() {
        if !out(32) || !mir_out_type(store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(", ") || !mir_out_value(store, rec.function, rec.a) { return false }
    }
    if rec.op >= mir_op_int_trunc() && rec.op <= mir_op_float_from_int() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_type(store, rec.type_op, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
    }
    if rec.op == mir_op_const_get() {
        if !out_string(" @") || !mir_out_name(store, rec.name_start, rec.name_end) { return false }
    }
    if rec.op == mir_op_call() || rec.op == mir_op_ffi_call_unsafe() {
        if !out_string(" @") { return false }
        if rec.op == mir_op_call() {
            if !mir_out_function_name(store, rec.target) { return false }
        }
        if rec.op == mir_op_ffi_call_unsafe() && !mir_out_import_name(store, rec.target) { return false }
        if !out(40) || !mir_out_operand_values(store, mir_operand_instruction(), id, 0, rec.function) || !out(41) { return false }
    }
    if rec.op == mir_op_call_value() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out(40) || !mir_out_operand_values(store, mir_operand_instruction(), id, 0, rec.function) || !out(41) { return false }
    }
    if rec.op == mir_op_str_eq() {
        if !out(32) || !mir_out_value(store, rec.function, rec.a) || !out_string(", ") || !mir_out_value(store, rec.function, rec.b) { return false }
    }
    if rec.op == mir_op_fn_value() {
        if !out_string(" @") || !mir_out_function_name(store, rec.target) { return false }
        if rec.a != 0 {
            if !out(40) || !mir_out_value(store, rec.function, rec.a) || !out(41) { return false }
        }
    }
    return out(10)
}

fn mir_out_terminator(store: MirStore, id: U64, rec: MirTermRec) -> Bool {
    if !out_string("  ") { return false }
    if rec.kind == mir_term_jump() {
        if !out_string("jump ") || !mir_out_block_ref(store, rec.function, rec.target, mir_operand_terminator_arg(), id, mir_edge_jump()) { return false }
    }
    if rec.kind == mir_term_branch() {
        if !out_string("branch ") || !mir_out_value(store, rec.function, rec.value) || !out_string(", ") || !mir_out_block_ref(store, rec.function, rec.then_block, mir_operand_terminator_arg(), id, mir_edge_then()) || !out_string(", ") || !mir_out_block_ref(store, rec.function, rec.else_block, mir_operand_terminator_arg(), id, mir_edge_else()) { return false }
    }
    if rec.kind == mir_term_switch() {
        if !out_string("switch ") || !mir_out_value(store, rec.function, rec.value) || !out_string(" {\n") { return false }
        let count = mir_operand_count(store, mir_operand_switch_case(), id, 0)
        var ordinal: U64 = 0
        while ordinal < count {
            var at: U64 = 0
            while at < __s0_buffer_len(MirOperandRec, store.operands) {
                let case = __s0_buffer_get(MirOperandRec, store.operands, at)
                if case.kind == mir_operand_switch_case() && case.owner == id && case.ordinal == ordinal {
                    if !out_string("    ") { return false }
                    if case.name_start == case.name_end {
                        if !out_string("default") { return false }
                    } else {
                        if !mir_out_name(store, case.name_start, case.name_end) { return false }
                        if case.value != 0 && (!out(40) || !mir_out_value(store, rec.function, case.value) || !out(41)) { return false }
                    }
                    if !out_string(" -> ") || !mir_out_block_ref(store, rec.function, case.target, mir_operand_switch_case_arg(), at + 1, 0) || !out(10) { return false }
                }
                at = at + 1
            }
            ordinal = ordinal + 1
        }
        if !out_string("  }") { return false }
    }
    if rec.kind == mir_term_return() {
        if !out_string("return") { return false }
        if rec.value != 0 && (!out(32) || !mir_out_value(store, rec.function, rec.value)) { return false }
    }
    if rec.kind == mir_term_fail() {
        if !out_string("fail ") || !mir_out_value(store, rec.function, rec.value) { return false }
    }
    if rec.kind == mir_term_panic() {
        if !out_string("panic") { return false }
    }
    if rec.kind == mir_term_unreachable() && !out_string("unreachable") { return false }
    return out(10)
}

fn mir_out_param_group(store: MirStore, kind: U64, function: U64, block: U64) -> Bool {
    let count = mir_param_group_count(store, kind, function, block)
    var ordinal: U64 = 0
    while ordinal < count {
        var at: U64 = 0
        while at < __s0_buffer_len(MirParamRec, store.params) {
            let rec = __s0_buffer_get(MirParamRec, store.params, at)
            if rec.kind == kind && rec.function == function && rec.block == block && rec.ordinal == ordinal {
                if ordinal > 0 && !out_string(", ") { return false }
                if !out(37) || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(": ") || !mir_out_type(store, rec.param_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
            }
            at = at + 1
        }
        ordinal = ordinal + 1
    }
    return true
}

fn mir_out_type_declarations(store: MirStore) -> Bool {
    var id = mir_primitive_type_count() + 1
    while id <= __s0_buffer_len(MirTypeRec, store.types) {
        let rec = __s0_buffer_get(MirTypeRec, store.types, id - 1)
        if rec.kind == mir_type_kind_aggregate() || rec.kind == mir_type_kind_enum() {
            if rec.kind == mir_type_kind_aggregate() && !out_string("\ntype @") { return false }
            if rec.kind == mir_type_kind_enum() && !out_string("\nenum @") { return false }
            if !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(" {\n") { return false }
            var kind = mir_type_part_variant()
            if rec.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
            let count = mir_type_part_count(store, id, kind)
            var ordinal: U64 = 0
            while ordinal < count {
                var at: U64 = 0
                while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
                    let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
                    if part.owner == id && part.kind == kind && part.ordinal == ordinal {
                        if !out_string("  ") || !mir_out_name(store, part.name_start, part.name_end) { return false }
                        if kind == mir_type_part_field() {
                            if !out_string(": ") || !mir_out_type(store, part.part_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                        }
                        if kind == mir_type_part_variant() && part.part_type != mir_type_unit() && (!out(40) || !mir_out_type(store, part.part_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(41)) { return false }
                        if !out(10) { return false }
                    }
                    at = at + 1
                }
                ordinal = ordinal + 1
            }
            if !out_string("}\n") { return false }
        }
        id = id + 1
    }
    return true
}

fn mir_out_declarations(store: MirStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let rec = __s0_buffer_get(MirConstRec, store.constants, at)
        if !out_string("\nconst @") || !mir_out_name(store, rec.name_start, rec.name_end) || !out_string(": ") || !mir_out_type(store, rec.const_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out_string(" = ") { return false }
        if rec.kind == mir_const_unit() {
            if !out_string("()") { return false }
        }
        if rec.kind == mir_const_bool() {
            if rec.bool_value == 0 && !out_string("false") { return false }
            if rec.bool_value == 1 && !out_string("true") { return false }
        }
        if rec.kind == mir_const_int() {
            if !mir_out_i64(rec.int_value) { return false }
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
        let count = mir_operand_count(store, mir_operand_import_param(), at + 1, 0)
        var ordinal: U64 = 0
        while ordinal < count {
            var operand_at: U64 = 0
            while operand_at < __s0_buffer_len(MirOperandRec, store.operands) {
                let operand = __s0_buffer_get(MirOperandRec, store.operands, operand_at)
                if operand.kind == mir_operand_import_param() && operand.owner == at + 1 && operand.ordinal == ordinal {
                    if ordinal > 0 && !out_string(", ") { return false }
                    if !mir_out_type(store, operand.operand_type, __s0_buffer_len(MirTypeRec, store.types) + 1) { return false }
                }
                operand_at = operand_at + 1
            }
            ordinal = ordinal + 1
        }
        if !out_string(") -> ") || !mir_out_type(store, rec.result_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn mir_out_functions(store: MirStore) -> Bool {
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let rec = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
        if !out_string("\nfn @") || !mir_out_name(store, rec.name_start, rec.name_end) || !out(40) || !mir_out_param_group(store, mir_param_function(), function, 0) || !out(41) { return false }
        if rec.result_type != mir_type_unit() && (!out_string(" -> ") || !mir_out_type(store, rec.result_type, __s0_buffer_len(MirTypeRec, store.types) + 1)) { return false }
        if !out_string(" {\n") { return false }
        let local_count = mir_local_count(store, function)
        var ordinal: U64 = 0
        while ordinal < local_count {
            var at: U64 = 0
            while at < __s0_buffer_len(MirLocalRec, store.locals) {
                let local = __s0_buffer_get(MirLocalRec, store.locals, at)
                if local.function == function && local.ordinal == ordinal {
                    if !out_string("  local %") || !mir_out_name(store, local.name_start, local.name_end) || !out_string(": ") || !mir_out_type(store, local.local_type, __s0_buffer_len(MirTypeRec, store.types) + 1) || !out(10) { return false }
                }
                at = at + 1
            }
            ordinal = ordinal + 1
        }
        if local_count > 0 && !out(10) { return false }
        let block_count = mir_block_count(store, function)
        var block_ordinal: U64 = 0
        while block_ordinal < block_count {
            let block = block_ordinal + 1
            if block_ordinal > 0 && !out(10) { return false }
            if !mir_out_block_name(store, function, block) { return false }
            if mir_param_group_count(store, mir_param_block(), function, block) > 0 && (!out(40) || !mir_out_param_group(store, mir_param_block(), function, block) || !out(41)) { return false }
            if !out_string(":\n") { return false }
            let instruction_count = mir_instr_group_count(store, function, block)
            var instruction_ordinal: U64 = 0
            while instruction_ordinal < instruction_count {
                var instruction_at: U64 = 0
                while instruction_at < __s0_buffer_len(MirInstrRec, store.instructions) {
                    let instruction = __s0_buffer_get(MirInstrRec, store.instructions, instruction_at)
                    if instruction.function == function && instruction.block == block && instruction.ordinal == instruction_ordinal && !mir_out_instruction(store, instruction_at + 1, instruction) { return false }
                    instruction_at = instruction_at + 1
                }
                instruction_ordinal = instruction_ordinal + 1
            }
            var term_at: U64 = 0
            while term_at < __s0_buffer_len(MirTermRec, store.terminators) {
                let term = __s0_buffer_get(MirTermRec, store.terminators, term_at)
                if term.function == function && term.block == block && !mir_out_terminator(store, term_at + 1, term) { return false }
                term_at = term_at + 1
            }
            block_ordinal = block_ordinal + 1
        }
        if !out_string("}\n") { return false }
        function = function + 1
    }
    return true
}

fn mir_print(store: MirStore) -> Bool {
    if !mir_store_valid(store) { return false }
    return out_string("mir 5\n") && mir_out_type_declarations(store) && mir_out_declarations(store) && mir_out_functions(store)
}
