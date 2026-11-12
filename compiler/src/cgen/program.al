// Declaration and hosted-program skeleton over flat MIR 4 records. Instruction
// bodies and the production generator entry deliberately remain unavailable.

fn cgen_import_param(store: MirStore, owner: U64, ordinal: U64) -> MirOperandRec {
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let item = __s0_buffer_get(MirOperandRec, store.operands, at)
        if item.kind == mir_operand_import_param() && item.owner == owner && item.ordinal == ordinal { return item }
        at = at + 1
    }
    return __s0_buffer_get(MirOperandRec, store.operands, 0)
}

fn cgen_function_param(store: MirStore, indexes: MirVIndexes, owner: U64, ordinal: U64) -> MirParamRec {
    let count = mir_vindex_param_count(indexes, owner)
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, owner, at)
        if id != 0 {
            let item = __s0_buffer_get(MirParamRec, store.params, id - 1)
            if item.kind == mir_param_function() && item.ordinal == ordinal { return item }
        }
        at = at + 1
    }
    return __s0_buffer_get(MirParamRec, store.params, 0)
}

fn cgen_function_param_count(store: MirStore, indexes: MirVIndexes, function: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var total: U64 = 0
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, function, at)
        if id != 0 {
            let item = __s0_buffer_get(MirParamRec, store.params, id - 1)
            if item.kind == mir_param_function() { total = total + 1 }
        }
        at = at + 1
    }
    return total
}

fn cgen_emit_function_name(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    var out = try cgen_put(d, initial, "alder_fn_")
    out = try cgen_put_name_fragment(d, out, store, item.name_start, item.name_end)
    out = try cgen_put(d, out, "_")
    return cgen_put_u64(d, out, function - 1)
}

fn cgen_emit_function_params(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let count = cgen_function_param_count(store, indexes, function)
    var ordinal: U64 = 0
    var wrote = false
    while ordinal < count {
        let item = cgen_function_param(store, indexes, function, ordinal)
        if item.param_type != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            out = try cgen_put_type(d, out, store, item.param_type)
            out = try cgen_put(d, out, " alder_v")
            out = try cgen_put_u64(d, out, ordinal)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    if !wrote { out = try cgen_put(d, out, "void") }
    return Ok(out)
}

fn cgen_emit_constants(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirConstRec, store.constants) {
        let item = __s0_buffer_get(MirConstRec, store.constants, at)
        if item.kind == mir_const_unit() {
            out = try cgen_put(d, out, "/* unit constant alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " has no storage. */\n")
        }
        if item.kind == mir_const_bool() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const bool alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = ")
            if item.bool_value == 0 { out = try cgen_put(d, out, "false") } else { out = try cgen_put(d, out, "true") }
            out = try cgen_put(d, out, ";\n")
        }
        if item.kind == mir_const_int() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const ")
            out = try cgen_put_type(d, out, store, item.const_type)
            out = try cgen_put(d, out, " alder_const_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " = (")
            out = try cgen_put_type(d, out, store, item.const_type)
            out = try cgen_put(d, out, ")")
            if item.const_type == mir_type_u64() && item.int_value < 0 {
                // The signed field holds the 64-bit pattern of a value
                // above INT64_MAX; the emitted form is the pattern's
                // unsigned decimal with a ULL suffix, because an
                // unsuffixed decimal that large has no signed type.
                let bits = unsafe c { alderhost_u64_from_i64_bits(item.int_value) }
                out = try cgen_put_u64(d, out, bits)
                out = try cgen_put(d, out, "ULL")
            } else {
                out = try cgen_put_i64(d, out, item.int_value)
            }
            out = try cgen_put(d, out, ";\n")
        }
        if item.kind == mir_const_float() { out = try cgen_emit_const_float_decl(d, out, at, item.const_type, item.float_bits) }
        if item.kind == mir_const_string() {
            out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED ")
            if mir_vtype_kind(store, item.const_type) != mir_type_kind_slice() { out = try cgen_put(d, out, "const ") }
            out = try cgen_put(d, out, "uint8_t alder_str_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, "[] = {")
            var byte_at = item.string_start
            if byte_at == item.string_end { out = try cgen_put(d, out, "UINT8_C(0)") }
            while byte_at < item.string_end {
                if byte_at != item.string_start { out = try cgen_put(d, out, ", ") }
                out = try cgen_put(d, out, "UINT8_C(")
                out = try cgen_put_u64(d, out, cgen_u8_to_u64(__s0_buffer_get(U8, store.names, byte_at)))
                out = try cgen_put(d, out, ")")
                byte_at = byte_at + 1
            }
            out = try cgen_put(d, out, "};\n")
        }
        at = at + 1
    }
    if __s0_buffer_len(MirConstRec, store.constants) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

// A float constant's MIR pattern is always the f64 bit pattern of its
// value. f32 constants store the 32-bit float pattern in their table slot,
// so the emission narrows the verified-exact pattern through the host.
fn cgen_emit_const_float_decl(d: Domain, initial: CgenWriter, at: U64, const_type: U64, float_bits: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED const ")
    if const_type == mir_type_f32() { out = try cgen_put(d, out, "uint32_t") } else { out = try cgen_put(d, out, "uint64_t") }
    out = try cgen_put(d, out, " alder_const_")
    out = try cgen_put_u64(d, out, at)
    if const_type == mir_type_f32() { out = try cgen_put(d, out, "_bits = UINT32_C(") } else { out = try cgen_put(d, out, "_bits = UINT64_C(") }
    if const_type == mir_type_f32() {
        out = try cgen_put_u64(d, out, unsafe c { alderhost_f32_bits_from_f64_bits(float_bits) })
    } else {
        out = try cgen_put_u64(d, out, float_bits)
    }
    out = try cgen_put(d, out, ");\n")
    return Ok(out)
}

// One include per binding block followed by the C11 compile-time binding
// checks. The checks live in the generated program translation unit, so no
// build can compile a binding whose header disagrees with the declared
// spelling, record field, function signature, or constant. Assertion
// messages name the Alder binding member.
fn cgen_emit_bindings(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    if __s0_buffer_len(MirBindingRec, store.bindings) == 0 { return Ok(initial) }
    // Headers are included before any libc header the generated program or
    // the binding checks need: a header that selects feature-test macros must
    // do so before features.h is pulled in, and <stddef.h> is one such
    // header. The checks follow, once offsetof is available.
    var out = initial
    var block_at: U64 = 0
    while block_at < __s0_buffer_len(MirBindingRec, store.bindings) {
        let block = __s0_buffer_get(MirBindingRec, store.bindings, block_at)
        out = try cgen_put(d, out, "#include <")
        out = try cgen_put_name(d, out, store, block.header_start, block.header_end)
        out = try cgen_put(d, out, ">\n")
        block_at = block_at + 1
    }
    out = try cgen_put(d, out, "#include <stddef.h>\n")
    block_at = 0
    while block_at < __s0_buffer_len(MirBindingRec, store.bindings) {
        out = try cgen_emit_binding_checks(d, out, store, block_at)
        block_at = block_at + 1
    }
    return cgen_put(d, out, "\n")
}

// The message prefix naming the Alder binding member: binding <block>.<member>
// (<spelling>).
fn cgen_binding_what(d: Domain, initial: CgenWriter, store: MirStore, block: MirBindingRec, name_start: U64, name_end: U64, c_start: U64, c_end: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "binding ")
    out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
    out = try cgen_put(d, out, ".")
    out = try cgen_put_name(d, out, store, name_start, name_end)
    out = try cgen_put(d, out, " (")
    out = try cgen_put_name(d, out, store, c_start, c_end)
    return cgen_put(d, out, ")")
}

fn cgen_binding_type_count(store: MirStore, block: U64) -> U64 {
    var at: U64 = 0
    var count: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let operand = __s0_buffer_get(MirOperandRec, store.operands, at)
        if operand.kind == mir_operand_binding_type() && operand.owner == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn cgen_binding_type_operand(store: MirStore, block: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let operand = __s0_buffer_get(MirOperandRec, store.operands, at)
        if operand.kind == mir_operand_binding_type() && operand.owner == block && operand.ordinal == ordinal { return operand.operand_type }
        at = at + 1
    }
    return 0
}

fn cgen_binding_param_count(store: MirStore, fn_id: U64) -> U64 {
    var at: U64 = 0
    var count: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let operand = __s0_buffer_get(MirOperandRec, store.operands, at)
        if operand.kind == mir_operand_binding_param() && operand.owner == fn_id { count = count + 1 }
        at = at + 1
    }
    return count
}

fn cgen_binding_param_type(store: MirStore, fn_id: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirOperandRec, store.operands) {
        let operand = __s0_buffer_get(MirOperandRec, store.operands, at)
        if operand.kind == mir_operand_binding_param() && operand.owner == fn_id && operand.ordinal == ordinal { return operand.operand_type }
        at = at + 1
    }
    return 0
}

fn cgen_binding_field_count(store: MirStore, owner: U64) -> U64 {
    var at: U64 = 0
    var count: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if part.kind == mir_type_part_c_field() && part.owner == owner { count = count + 1 }
        at = at + 1
    }
    return count
}

fn cgen_binding_field(store: MirStore, owner: U64, ordinal: U64) -> MirTypePartRec {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, at)
        if part.kind == mir_type_part_c_field() && part.owner == owner && part.ordinal == ordinal { return part }
        at = at + 1
    }
    return __s0_buffer_get(MirTypePartRec, store.type_parts, 0)
}

fn cgen_emit_binding_checks(d: Domain, initial: CgenWriter, store: MirStore, block_at: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let block = __s0_buffer_get(MirBindingRec, store.bindings, block_at)
    let block_id = block_at + 1
    let type_total = cgen_binding_type_count(store, block_id)
    var ti: U64 = 0
    while ti < type_total {
        let type_id = cgen_binding_type_operand(store, block_id, ti)
        if type_id == 0 || type_id > __s0_buffer_len(MirTypeRec, store.types) { return cgen_put(d, out, "  /* unreachable binding type probe */\n") }
        let t = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
        out = try cgen_put(d, out, "typedef ")
        out = try cgen_put_name(d, out, store, t.c_name_start, t.c_name_end)
        out = try cgen_put(d, out, " alder_bind_")
        out = try cgen_put_u64(d, out, block_at)
        out = try cgen_put(d, out, "_t")
        out = try cgen_put_u64(d, out, ti)
        out = try cgen_put(d, out, ";\n")
        if t.c_class == mir_c_class_opaque() {
            out = try cgen_put(d, out, "_Static_assert(sizeof(alder_bind_")
            out = try cgen_put_u64(d, out, block_at)
            out = try cgen_put(d, out, "_t")
            out = try cgen_put_u64(d, out, ti)
            out = try cgen_put(d, out, " *) == sizeof(void *), \"")
            out = try cgen_binding_what(d, out, store, block, t.name_start, t.name_end, t.c_name_start, t.c_name_end)
            out = try cgen_put(d, out, ": opaque binding spelling must resolve to a pointer-representable type\");\n")
        }
        if t.c_class == mir_c_class_scalar() {
            out = try cgen_put(d, out, "_Static_assert(sizeof(alder_bind_")
            out = try cgen_put_u64(d, out, block_at)
            out = try cgen_put(d, out, "_t")
            out = try cgen_put_u64(d, out, ti)
            out = try cgen_put(d, out, ") >= 1, \"")
            out = try cgen_binding_what(d, out, store, block, t.name_start, t.name_end, t.c_name_start, t.c_name_end)
            out = try cgen_put(d, out, ": scalar binding spelling must resolve to a complete type\");\n")
        }
        if t.c_class == mir_c_class_callback() {
            out = try cgen_put(d, out, "_Static_assert(sizeof(alder_bind_")
            out = try cgen_put_u64(d, out, block_at)
            out = try cgen_put(d, out, "_t")
            out = try cgen_put_u64(d, out, ti)
            out = try cgen_put(d, out, ") == sizeof(void (*)(void)), \"")
            out = try cgen_binding_what(d, out, store, block, t.name_start, t.name_end, t.c_name_start, t.c_name_end)
            out = try cgen_put(d, out, ": callback binding spelling must resolve to a function-pointer type\");\n")
        }
        if t.c_class == mir_c_class_record() {
            out = try cgen_put(d, out, "_Static_assert(_Alignof(alder_bind_")
            out = try cgen_put_u64(d, out, block_at)
            out = try cgen_put(d, out, "_t")
            out = try cgen_put_u64(d, out, ti)
            out = try cgen_put(d, out, ") >= 1, \"")
            out = try cgen_binding_what(d, out, store, block, t.name_start, t.name_end, t.c_name_start, t.c_name_end)
            out = try cgen_put(d, out, ": record binding spelling must resolve to a complete type\");\n")
            let field_total = cgen_binding_field_count(store, type_id)
            var fi: U64 = 0
            while fi < field_total {
                let field = cgen_binding_field(store, type_id, fi)
                out = try cgen_put(d, out, "_Static_assert(offsetof(alder_bind_")
                out = try cgen_put_u64(d, out, block_at)
                out = try cgen_put(d, out, "_t")
                out = try cgen_put_u64(d, out, ti)
                out = try cgen_put(d, out, ", ")
                out = try cgen_put_name(d, out, store, field.c_name_start, field.c_name_end)
                out = try cgen_put(d, out, ") % _Alignof(")
                out = try cgen_put_type(d, out, store, field.part_type)
                out = try cgen_put(d, out, ") == 0, \"binding ")
                out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
                out = try cgen_put(d, out, ".")
                out = try cgen_put_name(d, out, store, t.name_start, t.name_end)
                out = try cgen_put(d, out, " (")
                out = try cgen_put_name(d, out, store, t.c_name_start, t.c_name_end)
                out = try cgen_put(d, out, ").")
                out = try cgen_put_name(d, out, store, field.name_start, field.name_end)
                out = try cgen_put(d, out, " (")
                out = try cgen_put_name(d, out, store, field.c_name_start, field.c_name_end)
                out = try cgen_put(d, out, "): field offset must respect the declared field alignment\");\n")
                out = try cgen_put(d, out, "_Static_assert(offsetof(alder_bind_")
                out = try cgen_put_u64(d, out, block_at)
                out = try cgen_put(d, out, "_t")
                out = try cgen_put_u64(d, out, ti)
                out = try cgen_put(d, out, ", ")
                out = try cgen_put_name(d, out, store, field.c_name_start, field.c_name_end)
                out = try cgen_put(d, out, ") + sizeof(")
                out = try cgen_put_type(d, out, store, field.part_type)
                out = try cgen_put(d, out, ") <= sizeof(alder_bind_")
                out = try cgen_put_u64(d, out, block_at)
                out = try cgen_put(d, out, "_t")
                out = try cgen_put_u64(d, out, ti)
                out = try cgen_put(d, out, "), \"binding ")
                out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
                out = try cgen_put(d, out, ".")
                out = try cgen_put_name(d, out, store, t.name_start, t.name_end)
                out = try cgen_put(d, out, " (")
                out = try cgen_put_name(d, out, store, t.c_name_start, t.c_name_end)
                out = try cgen_put(d, out, ").")
                out = try cgen_put_name(d, out, store, field.name_start, field.name_end)
                out = try cgen_put(d, out, " (")
                out = try cgen_put_name(d, out, store, field.c_name_start, field.c_name_end)
                out = try cgen_put(d, out, "): field does not fit inside the record\");\n")
                out = try cgen_put(d, out, "_Static_assert(_Generic(((alder_bind_")
                out = try cgen_put_u64(d, out, block_at)
                out = try cgen_put(d, out, "_t")
                out = try cgen_put_u64(d, out, ti)
                out = try cgen_put(d, out, " *)0)->")
                out = try cgen_put_name(d, out, store, field.c_name_start, field.c_name_end)
                out = try cgen_put(d, out, ", ")
                out = try cgen_put_type(d, out, store, field.part_type)
                out = try cgen_put(d, out, ": 1, default: 0), \"binding ")
                out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
                out = try cgen_put(d, out, ".")
                out = try cgen_put_name(d, out, store, t.name_start, t.name_end)
                out = try cgen_put(d, out, " (")
                out = try cgen_put_name(d, out, store, t.c_name_start, t.c_name_end)
                out = try cgen_put(d, out, ").")
                out = try cgen_put_name(d, out, store, field.name_start, field.name_end)
                out = try cgen_put(d, out, " (")
                out = try cgen_put_name(d, out, store, field.c_name_start, field.c_name_end)
                out = try cgen_put(d, out, "): field type does not match the declared binding type ")
                out = try cgen_put_type(d, out, store, field.part_type)
                out = try cgen_put(d, out, "\");\n")
                fi = fi + 1
            }
        }
        ti = ti + 1
    }
    var fn_at: U64 = 0
    while fn_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
        let fn_rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, fn_at)
        if fn_rec.block == block_id {
            out = try cgen_put(d, out, "_Static_assert(_Generic(&")
            out = try cgen_put_name(d, out, store, fn_rec.c_name_start, fn_rec.c_name_end)
            out = try cgen_put(d, out, ", ")
            if fn_rec.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, fn_rec.result_type) }
            out = try cgen_put(d, out, " (*)(")
            let param_total = cgen_binding_param_count(store, fn_at + 1)
            var pi: U64 = 0
            var wrote = false
            while pi < param_total {
                let param_type = cgen_binding_param_type(store, fn_at + 1, pi)
                if param_type != mir_type_unit() {
                    if wrote { out = try cgen_put(d, out, ", ") }
                    out = try cgen_put_type(d, out, store, param_type)
                    wrote = true
                }
                pi = pi + 1
            }
            if !wrote { out = try cgen_put(d, out, "void") }
            out = try cgen_put(d, out, "): 1, default: 0), \"binding ")
            out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
            out = try cgen_put(d, out, ".")
            out = try cgen_put_name(d, out, store, fn_rec.name_start, fn_rec.name_end)
            out = try cgen_put(d, out, " (")
            out = try cgen_put_name(d, out, store, fn_rec.c_name_start, fn_rec.c_name_end)
            out = try cgen_put(d, out, "): function type does not match the declared binding signature\");\n")
        }
        fn_at = fn_at + 1
    }
    var const_at: U64 = 0
    while const_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
        let const_rec = __s0_buffer_get(MirBindingConstRec, store.binding_consts, const_at)
        if const_rec.block == block_id {
            out = try cgen_put(d, out, "_Static_assert(_Generic(")
            out = try cgen_put_name(d, out, store, const_rec.c_name_start, const_rec.c_name_end)
            out = try cgen_put(d, out, " + 0, int: 1, unsigned int: 1, long: 1, unsigned long: 1, long long: 1, unsigned long long: 1, short: 1, unsigned short: 1, char: 1, signed char: 1, unsigned char: 1, _Bool: 1, default: 0), \"binding ")
            out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
            out = try cgen_put(d, out, ".")
            out = try cgen_put_name(d, out, store, const_rec.name_start, const_rec.name_end)
            out = try cgen_put(d, out, " (")
            out = try cgen_put_name(d, out, store, const_rec.c_name_start, const_rec.c_name_end)
            out = try cgen_put(d, out, "): constant must have an integral type\");\n")
            out = try cgen_put(d, out, "_Static_assert((")
            out = try cgen_put_name(d, out, store, const_rec.c_name_start, const_rec.c_name_end)
            out = try cgen_put(d, out, ") == (")
            out = try cgen_put_type(d, out, store, const_rec.const_type)
            out = try cgen_put(d, out, ")(")
            out = try cgen_put_name(d, out, store, const_rec.c_name_start, const_rec.c_name_end)
            out = try cgen_put(d, out, "), \"binding ")
            out = try cgen_put_name(d, out, store, block.name_start, block.name_end)
            out = try cgen_put(d, out, ".")
            out = try cgen_put_name(d, out, store, const_rec.name_start, const_rec.name_end)
            out = try cgen_put(d, out, " (")
            out = try cgen_put_name(d, out, store, const_rec.c_name_start, const_rec.c_name_end)
            out = try cgen_put(d, out, "): value must be representable as ")
            out = try cgen_put_type(d, out, store, const_rec.const_type)
            out = try cgen_put(d, out, "\");\n")
        }
        const_at = const_at + 1
    }
    return Ok(out)
}

// Forward declarations for every binding-block C function, so generated
// unsafe calls are always prototyped.
fn cgen_emit_binding_decls(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var fn_at: U64 = 0
    while fn_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
        let fn_rec = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, fn_at)
        if fn_rec.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, fn_rec.result_type) }
        out = try cgen_put(d, out, " ")
        out = try cgen_put_name(d, out, store, fn_rec.c_name_start, fn_rec.c_name_end)
        out = try cgen_put(d, out, "(")
        let param_total = cgen_binding_param_count(store, fn_at + 1)
        var pi: U64 = 0
        var wrote = false
        while pi < param_total {
            let param_type = cgen_binding_param_type(store, fn_at + 1, pi)
            if param_type != mir_type_unit() {
                if wrote { out = try cgen_put(d, out, ", ") }
                out = try cgen_put_type(d, out, store, param_type)
                wrote = true
            }
            pi = pi + 1
        }
        if !wrote { out = try cgen_put(d, out, "void") }
        out = try cgen_put(d, out, ");\n")
        fn_at = fn_at + 1
    }
    if __s0_buffer_len(MirBindingFnRec, store.binding_funcs) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_imports(d: Domain, initial: CgenWriter, store: MirStore) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirImportRec, store.imports) {
        let item = __s0_buffer_get(MirImportRec, store.imports, at)
        if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
        out = try cgen_put(d, out, " (")
        out = try cgen_put_name(d, out, store, item.name_start, item.name_end)
        out = try cgen_put(d, out, ")(")
        let count = mir_operand_count(store, mir_operand_import_param(), at + 1, 0)
        var ordinal: U64 = 0
        var wrote = false
        while ordinal < count {
            let param = cgen_import_param(store, at + 1, ordinal)
            if param.operand_type != mir_type_unit() {
                if wrote { out = try cgen_put(d, out, ", ") }
                out = try cgen_put_type(d, out, store, param.operand_type)
                wrote = true
            }
            ordinal = ordinal + 1
        }
        if !wrote { out = try cgen_put(d, out, "void") }
        out = try cgen_put(d, out, ");\n")
        at = at + 1
    }
    if __s0_buffer_len(MirImportRec, store.imports) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_name_has_prefix(store: MirStore, start: U64, end: U64, prefix: __s0_String) -> Bool {
    if start >= end || len(prefix) == 0 || len(prefix) > end - start { return false }
    if end > __s0_buffer_len(U8, store.names) { return false }
    var at: U64 = 0
    while at < len(prefix) {
        if __s0_buffer_get(U8, store.names, start + at) != prefix[at] { return false }
        at = at + 1
    }
    return true
}

// The buffer accessor monomorphisations are tiny, and a compiler-sized program
// calls them billions of times, so the out-of-line call and its argument copy
// were a large fraction of run time. Declaring them `static inline` lets GCC
// inline them; the body, every bounds check and every trap is unchanged, and a
// `static inline` definition that GCC declines to inline is emitted exactly as
// the plain `static` one was.
fn cgen_function_inlinable(store: MirStore, function: U64) -> Bool {
    if function == 0 || function > __s0_buffer_len(MirFunctionRec, store.functions) { return false }
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    return cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_get_") || cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_len_") || cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_set_") || cgen_name_has_prefix(store, item.name_start, item.name_end, "buffer_slice_")
}

fn cgen_put_function_linkage(d: Domain, initial: CgenWriter, store: MirStore, function: U64) -> Result(CgenWriter, __s0_Error) {
    if cgen_function_inlinable(store, function) { return cgen_put(d, initial, "static inline ALDER_MAYBE_UNUSED ") }
    return cgen_put(d, initial, "static ALDER_MAYBE_UNUSED ")
}

fn cgen_emit_functions(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
        out = try cgen_put_function_linkage(d, out, store, at + 1)
        if item.result_type == mir_type_unit() { out = try cgen_put(d, out, "void") } else { out = try cgen_put_type(d, out, store, item.result_type) }
        out = try cgen_put(d, out, " ")
        out = try cgen_emit_function_name(d, out, store, at + 1)
        out = try cgen_put(d, out, "(")
        out = try cgen_emit_function_params(d, out, store, indexes, at + 1)
        out = try cgen_put(d, out, ");\n")
        at = at + 1
    }
    if __s0_buffer_len(MirFunctionRec, store.functions) > 0 { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_host_entry(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, main: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "int32_t alder_program_entry(void *host_context) {\n  if (host_context == NULL) { return ALDER_PROGRAM_FAILURE_STATUS; }\n")
    let count = cgen_function_param_count(store, indexes, main)
    if count == 0 {
        out = try cgen_put(d, out, "  return ")
        out = try cgen_emit_function_name(d, out, store, main)
        out = try cgen_put(d, out, "();\n")
    } else {
        out = try cgen_put(d, out, "  AlderDomain alder_root = {0};\n  int32_t alder_status;\n  if (!alder_domain_init(&alder_root, NULL)) { return ALDER_PROGRAM_FAILURE_STATUS; }\n  alder_status = ")
        out = try cgen_emit_function_name(d, out, store, main)
        out = try cgen_put(d, out, "(&alder_root);\n  alder_domain_destroy(&alder_root);\n  return alder_status;\n")
    }
    return cgen_put(d, out, "}\n")
}

// The place-based cleanup records the owner local, not the hook's other
// arguments. A hook can also carry a hidden leading domain parameter, so the
// owner is the field whose type matches the local, not field zero.
fn cgen_cleanup_owner_field(store: MirStore, indexes: MirVIndexes, item: MirInstrRec, at: U64) -> U64 {
    if item.place == 0 { return 0 }
    let owner_type = cgen_place_type(store, indexes, item.function, item.place)
    if owner_type == 0 { return 0 }
    let count = cgen_operand_count(store, indexes, mir_operand_instruction(), at, 0)
    var ordinal: U64 = 0
    var field: U64 = 0
    while ordinal < count {
        let parameter = cgen_function_param(store, indexes, item.target, ordinal)
        if parameter.param_type != mir_type_unit() {
            if parameter.param_type == owner_type { return field + 1 }
            field = field + 1
        }
        ordinal = ordinal + 1
    }
    return 0
}

fn cgen_emit_cleanup_sites(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    var wrote = false
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_cleanup_push() {
            let count = cgen_operand_count(store, indexes, mir_operand_instruction(), at + 1, 0)
            let owner_field = cgen_cleanup_owner_field(store, indexes, item, at + 1)
            let place_based = item.place != 0 && owner_field != 0
            out = try cgen_put(d, out, "typedef struct AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " {\n")
            var ordinal: U64 = 0
            var field: U64 = 0
            while ordinal < count {
                let parameter = cgen_function_param(store, indexes, item.target, ordinal)
                if parameter.param_type != mir_type_unit() {
                    out = try cgen_put(d, out, "  ")
                    out = try cgen_put_type(d, out, store, parameter.param_type)
                    if place_based && field + 1 == owner_field { out = try cgen_put(d, out, " *") }
                    out = try cgen_put(d, out, " alder_f")
                    out = try cgen_put_u64(d, out, field)
                    out = try cgen_put(d, out, ";\n")
                    field = field + 1
                }
                ordinal = ordinal + 1
            }
            if field == 0 { out = try cgen_put(d, out, "  uint8_t alder_empty;\n") }
            out = try cgen_put(d, out, "} AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, ";\nstatic ALDER_MAYBE_UNUSED void alder_cleanup_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, "(void *alder_ctx) {\n")
            if field == 0 { out = try cgen_put(d, out, "  (void)alder_ctx;\n") } else { out = try cgen_put(d, out, "  AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " *alder_c = (AlderCtx_")
            out = try cgen_put_u64(d, out, at)
            out = try cgen_put(d, out, " *)alder_ctx;\n")
            if place_based {
                // The scope-exit run loads the registered local, so the hook
                // observes the owner's current value.
                out = try cgen_put(d, out, "  ")
                out = try cgen_put_type(d, out, store, cgen_place_type(store, indexes, item.function, item.place))
                out = try cgen_put(d, out, " alder_owner = *alder_c->alder_f")
                out = try cgen_put_u64(d, out, owner_field - 1)
                out = try cgen_put(d, out, ";\n")
            } }
            out = try cgen_put(d, out, "  ")
            out = try cgen_emit_function_name(d, out, store, item.target)
            out = try cgen_put(d, out, "(")
            ordinal = 0
            field = 0
            var first = true
            while ordinal < count {
                let parameter = cgen_function_param(store, indexes, item.target, ordinal)
                if parameter.param_type != mir_type_unit() {
                    if !first { out = try cgen_put(d, out, ", ") }
                    if place_based && field + 1 == owner_field { out = try cgen_put(d, out, "alder_owner") } else {
                    out = try cgen_put(d, out, "alder_c->alder_f")
                    out = try cgen_put_u64(d, out, field)
                    }
                    field = field + 1
                    first = false
                }
                ordinal = ordinal + 1
            }
            out = try cgen_put(d, out, ");\n}\n")
            wrote = true
        }
        at = at + 1
    }
    if wrote { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_emit_copy_helper_body(d: Domain, initial: CgenWriter, store: MirStore, type_id: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_string() || item.kind == mir_type_kind_bytes() {
        // The descriptor is {data, len}; the buffer moves into the
        // destination domain, keeping the slice-branch checks and style.
        out = try cgen_put(d, out, "  uint64_t alder_t;\n  if (!alder_u64_mul_checked(alder_v.len, (uint64_t)sizeof(uint8_t), &alder_t)) { alder_runtime_panic(\"copy_to_domain: size overflow\"); }\n  if (alder_t > (uint64_t)SIZE_MAX) { alder_runtime_panic(\"copy_to_domain: size exceeds size_t\"); }\n  if (alder_v.len > (uint64_t)0) {\n    if (alder_v.data == NULL) { alder_runtime_panic(\"copy_to_domain: null source\"); }\n    void *alder_p = alder_domain_alloc(alder_d, (size_t)alder_t, (size_t)1);\n    if (alder_p == NULL) { alder_runtime_panic(\"copy_to_domain: out of memory\"); }\n    memcpy(alder_p, alder_v.data, (size_t)alder_t);\n    alder_v.data = alder_p;\n  }\n")
    }
    if item.kind == mir_type_kind_function() {
        // A function value is {code, environment, retain}. A cross-domain
        // copy retains the environment through the hook so the copy owns a
        // complete environment in the destination domain; a same-domain copy
        // (a vector grow) passes zero and stays a plain bit copy.
        out = try cgen_put(d, out, "  if (alder_retain != 0 && alder_v.retain != NULL && alder_v.env != NULL) { alder_v.env = alder_v.retain(alder_d, alder_v.env); }\n")
    }
    if item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() || item.kind == mir_type_kind_vec() {
        out = try cgen_put(d, out, "  uint64_t alder_t;\n  if (!alder_u64_mul_checked(alder_v.len, (uint64_t)sizeof(")
        out = try cgen_put_type(d, out, store, item.elem)
        out = try cgen_put(d, out, "), &alder_t)) { alder_runtime_panic(\"copy_to_domain: size overflow\"); }\n  if (alder_t > (uint64_t)SIZE_MAX) { alder_runtime_panic(\"copy_to_domain: size exceeds size_t\"); }\n  if (alder_v.len > (uint64_t)0) {\n    if (alder_v.data == NULL) { alder_runtime_panic(\"copy_to_domain: null source\"); }\n    void *alder_p = alder_domain_alloc(alder_d, (size_t)alder_t, _Alignof(")
        out = try cgen_put_type(d, out, store, item.elem)
        out = try cgen_put(d, out, "));\n    if (alder_p == NULL) { alder_runtime_panic(\"copy_to_domain: out of memory\"); }\n")
        if cgen_copy_trivial(store, item.elem) { out = try cgen_put(d, out, "    memcpy(alder_p, alder_v.data, (size_t)alder_t);\n") } else { out = try cgen_put(d, out, "    for (uint64_t alder_i = (uint64_t)0; alder_i < alder_v.len; alder_i++) { ((")
            out = try cgen_put_type(d, out, store, item.elem)
            out = try cgen_put(d, out, " *)alder_p)[alder_i] = alder_copy_ty")
            out = try cgen_put_u64(d, out, item.elem - 1)
            out = try cgen_put(d, out, "(alder_d, ((")
            out = try cgen_put_type(d, out, store, item.elem)
            out = try cgen_put(d, out, " *)alder_v.data)[alder_i], alder_retain); }\n") }
        out = try cgen_put(d, out, "    alder_v.data = alder_p;\n  }\n")
        if item.kind == mir_type_kind_vec() { out = try cgen_put(d, out, "  alder_v.capacity = alder_v.len;\n") }
    }
    if item.kind == mir_type_kind_array() && !cgen_copy_trivial(store, item.elem) {
        out = try cgen_put(d, out, "  for (uint64_t alder_i = (uint64_t)0; alder_i < (uint64_t)")
        out = try cgen_put_u64(d, out, item.length)
        out = try cgen_put(d, out, "; alder_i++) {\n    alder_v.alder_e[alder_i] = alder_copy_ty")
        out = try cgen_put_u64(d, out, item.elem - 1)
        out = try cgen_put(d, out, "(alder_d, alder_v.alder_e[alder_i], alder_retain);\n  }\n")
    }
    if item.kind == mir_type_kind_aggregate() || item.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if item.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, type_id, kind) {
            let child = cgen_type_part(store, type_id, kind, ordinal).part_type
            if child != mir_type_unit() && !cgen_copy_trivial(store, child) {
                if item.kind == mir_type_kind_enum() { out = try cgen_put(d, out, "  if (alder_v.alder_tag == (uint32_t)")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ") {\n  ") }
                out = try cgen_put(d, out, "  alder_v.")
                if item.kind == mir_type_kind_aggregate() { out = try cgen_put(d, out, "alder_f") } else { out = try cgen_put(d, out, "alder_u.alder_p") }
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, " = alder_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_v.")
                if item.kind == mir_type_kind_aggregate() { out = try cgen_put(d, out, "alder_f") } else { out = try cgen_put(d, out, "alder_u.alder_p") }
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ", alder_retain);\n")
                if item.kind == mir_type_kind_enum() { out = try cgen_put(d, out, "  }\n") }
            }
            ordinal = ordinal + 1
        }
    }
    if item.kind == mir_type_kind_option() || item.kind == mir_type_kind_result() {
        var ordinal: U64 = 0
        while ordinal < 2 {
            let child = cgen_variant_payload(store, type_id, ordinal)
            if child != mir_type_unit() && !cgen_copy_trivial(store, child) {
                out = try cgen_put(d, out, "  if (alder_v.alder_tag == (uint32_t)")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ") {\n    alder_v.alder_u.alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, " = alder_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_v.alder_u.alder_p")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ", alder_retain);\n  }\n")
            }
            ordinal = ordinal + 1
        }
    }
    return cgen_put(d, out, "  return alder_v;\n}\n")
}

fn cgen_emit_copy_type(d: Domain, initial: CgenTypeState, store: MirStore, type_id: U64) -> Result(CgenTypeState, __s0_Error) {
    if cgen_copy_trivial(store, type_id) || cgen_emitted(initial.emitted, type_id) { return Ok(initial) }
    var state = initial
    let item = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if item.kind == mir_type_kind_aggregate() || item.kind == mir_type_kind_enum() {
        var ordinal: U64 = 0
        var kind = mir_type_part_variant()
        if item.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
        while ordinal < mir_type_part_count(store, type_id, kind) { state = try cgen_emit_copy_type(d, state, store, cgen_type_part(store, type_id, kind, ordinal).part_type)
        ordinal = ordinal + 1 }
    }
    if item.kind == mir_type_kind_option() || item.kind == mir_type_kind_slice() || item.kind == mir_type_kind_safe_ref() || item.kind == mir_type_kind_safe_mut() || item.kind == mir_type_kind_vec() || item.kind == mir_type_kind_array() { state = try cgen_emit_copy_type(d, state, store, item.elem) }
    if item.kind == mir_type_kind_result() { state = try cgen_emit_copy_type(d, state, store, item.ok_type)
    state = try cgen_emit_copy_type(d, state, store, item.err_type) }
    var out = try cgen_put(d, state.writer, "static ALDER_MAYBE_UNUSED ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_copy_ty")
    out = try cgen_put_u64(d, out, type_id - 1)
    out = try cgen_put(d, out, "(AlderDomain *alder_d, ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " alder_v, int alder_retain) {\n  (void)alder_retain;\n")
    out = try cgen_emit_copy_helper_body(d, out, store, type_id)
    let emitted = try __s0_buffer_append(U64, d, state.emitted, type_id)
    return Ok(CgenTypeState(writer: out, emitted: emitted))
}

fn cgen_emit_copy_helpers(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    let emitted = try __s0_buffer_new(U64, d)
    var state = CgenTypeState(writer: initial, emitted: emitted)
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_copy_to_domain() { state = try cgen_emit_copy_type(d, state, store, cgen_value_type(store, indexes, item.function, item.b)) }
        if item.op == mir_op_vec_grow_checked() { let vec_type = cgen_value_type(store, indexes, item.function, item.a)
            state = try cgen_emit_copy_type(d, state, store, __s0_buffer_get(MirTypeRec, store.types, vec_type - 1).elem) }
        if item.op == mir_op_table_insert() || item.op == mir_op_table_insert_try() {
            // A storage-bearing element is deep-copied into the table's own
            // domain at insert, so its copy helper must exist even when no
            // copy_to_domain instruction names the type.
            let elem_type = cgen_value_type(store, indexes, item.function, item.b)
            if !cgen_copy_trivial(store, elem_type) { state = try cgen_emit_copy_type(d, state, store, elem_type) }
        }
        if item.op == mir_op_fn_value() {
            // The environment retain hook deep-copies a storage-bearing
            // capture through its per-type copy helper, so those helpers must
            // exist even when no copy_to_domain instruction names the type.
            let env_type = cgen_fn_env_aggregate(store, indexes, item.function, item.a)
            if env_type != 0 {
                var part: U64 = 0
                while part < mir_type_part_count(store, env_type, mir_type_part_field()) {
                    let child = cgen_type_part(store, env_type, mir_type_part_field(), part).part_type
                    var skip_field = false
                    if child >= 1 && child <= __s0_buffer_len(MirTypeRec, store.types) {
                        let child_kind = __s0_buffer_get(MirTypeRec, store.types, child - 1).kind
                        if child_kind == mir_type_kind_domain_handle() || child_kind == mir_type_kind_slice() || child_kind == mir_type_kind_safe_ref() || child_kind == mir_type_kind_safe_mut() { skip_field = true }
                    }
                    if !skip_field { state = try cgen_emit_copy_type(d, state, store, child) }
                    part = part + 1
                }
            }
        }
        at = at + 1
    }
    if __s0_buffer_len(U64, state.emitted) > 0 { state.writer = try cgen_put(d, state.writer, "\n") }
    return Ok(state.writer)
}

// cgen_fn_env_aggregate returns the environment record type of a fn.value's
// environment operand when that operand is a reference to an aggregate, or 0
// when the function value has no owned closure environment.
fn cgen_fn_env_aggregate(store: MirStore, indexes: MirVIndexes, function: U64, env_value: U64) -> U64 {
    if env_value == 0 { return 0 }
    let env_type = cgen_value_type(store, indexes, function, env_value)
    if env_type < 1 || env_type > __s0_buffer_len(MirTypeRec, store.types) { return 0 }
    let item = __s0_buffer_get(MirTypeRec, store.types, env_type - 1)
    if item.kind != mir_type_kind_safe_ref() && item.kind != mir_type_kind_safe_mut() && item.kind != mir_type_kind_slice() { return 0 }
    if item.elem < 1 || item.elem > __s0_buffer_len(MirTypeRec, store.types) { return 0 }
    if __s0_buffer_get(MirTypeRec, store.types, item.elem - 1).kind != mir_type_kind_aggregate() { return 0 }
    return item.elem
}

// cgen_emit_env_retain emits the retain hook for one environment record type.
// It allocates a complete, independent environment in the destination domain:
// a shallow record copy is enough because captures are storage-free, a domain
// field is rewritten to the destination domain, and every function-valued
// capture is retained recursively through its own hook.
fn cgen_emit_env_retain(d: Domain, initial: CgenWriter, store: MirStore, type_id: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, "static ALDER_MAYBE_UNUSED void *alder_env_retain_ty")
    out = try cgen_put_u64(d, out, type_id - 1)
    out = try cgen_put(d, out, "(AlderDomain *alder_d, void *alder_env) {\n  ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " *alder_src = (")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " *)alder_env;\n  ")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " *alder_dst = (")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, " *)alder_domain_alloc(alder_d, sizeof(")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, "), _Alignof(")
    out = try cgen_put_type(d, out, store, type_id)
    out = try cgen_put(d, out, "));\n  if (alder_dst == NULL) { alder_runtime_panic(\"closure environment: out of memory\"); }\n  *alder_dst = *alder_src;\n")
    var ordinal: U64 = 0
    let count = mir_type_part_count(store, type_id, mir_type_part_field())
    while ordinal < count {
        let child = cgen_type_part(store, type_id, mir_type_part_field(), ordinal).part_type
        if child >= 1 && child <= __s0_buffer_len(MirTypeRec, store.types) {
            let child_item = __s0_buffer_get(MirTypeRec, store.types, child - 1)
            if child_item.kind == mir_type_kind_function() {
                out = try cgen_put(d, out, "  if (alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ".retain != NULL && alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ".env != NULL) { alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ".env = alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ".retain(alder_d, alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ".env); }\n")
            }
            if child_item.kind == mir_type_kind_domain_handle() {
                out = try cgen_put(d, out, "  alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, " = alder_d;\n")
            }
            // A captured view is a header, not owned storage: the closure
            // aliases the scope that owns it, so the hook copies the header.
            if child_item.kind != mir_type_kind_function() && child_item.kind != mir_type_kind_domain_handle() && child_item.kind != mir_type_kind_slice() && child_item.kind != mir_type_kind_safe_ref() && child_item.kind != mir_type_kind_safe_mut() && !cgen_copy_trivial(store, child) {
                // A storage-bearing capture is deep-copied into the
                // destination domain, and any function inside it is retained
                // by the recursive copy.
                out = try cgen_put(d, out, "  alder_dst->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, " = alder_copy_ty")
                out = try cgen_put_u64(d, out, child - 1)
                out = try cgen_put(d, out, "(alder_d, alder_src->alder_f")
                out = try cgen_put_u64(d, out, ordinal)
                out = try cgen_put(d, out, ", 1);\n")
            }
        }
        ordinal = ordinal + 1
    }
    return cgen_put(d, out, "  return alder_dst;\n}\n")
}

fn cgen_emit_env_retain_helpers(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var emitted = try __s0_buffer_new(U64, d)
    var domain_emitted = false
    var wrote = false
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_fn_value() {
            let env_type = cgen_fn_env_aggregate(store, indexes, item.function, item.a)
            if env_type != 0 && !cgen_emitted(emitted, env_type) {
                out = try cgen_emit_env_retain(d, out, store, env_type)
                emitted = try __s0_buffer_append(U64, d, emitted, env_type)
                wrote = true
            }
            if env_type == 0 && item.a != 0 && item.type_op == mir_fn_value_domain_marker() && !domain_emitted {
                // A named function value's environment is the domain its
                // frame will hang off, so retaining it into another domain
                // rewrites it to that domain.
                out = try cgen_put(d, out, "static ALDER_MAYBE_UNUSED void *alder_env_retain_domain(AlderDomain *alder_d, void *alder_env) {\n  (void)alder_env;\n  return alder_d;\n}\n")
                domain_emitted = true
                wrote = true
            }
        }
        at = at + 1
    }
    if wrote { out = try cgen_put(d, out, "\n") }
    return Ok(out)
}

fn cgen_build_declaration_skeleton(d: Domain, store: MirStore, verified: MirVerifyCompleteOutput) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder declaration-only C11 backend skeleton. */\n/* Production generation remains gated on MIR verifier V10. */\n#include \"alder.h\"\n")
    if verified.hosted { out = try cgen_put(d, out, "#include \"alder_host.h\"\n") }
    out = try cgen_put(d, out, "#include <float.h>\n#include <string.h>\n")
    out = try cgen_put(d, out, "#if defined(__GNUC__) && !defined(__clang__)\n#pragma GCC diagnostic ignored \"-Wunknown-pragmas\"\n#endif\n")
    out = try cgen_put(d, out, "#pragma STDC FP_CONTRACT OFF\n\n")
    let indexes = try mir_vindex_build(d, store)
    out = try cgen_emit_bindings(d, out, store)
    out = try cgen_emit_types(d, out, store)
    out = try cgen_emit_constants(d, out, store)
    out = try cgen_emit_functions(d, out, store, indexes)
    out = try cgen_emit_imports(d, out, store)
    out = try cgen_emit_binding_decls(d, out, store)
    if verified.hosted { out = try cgen_emit_host_entry(d, out, store, indexes, verified.entry) }
    return Ok(out)
}

// One wrapper per distinct (target, function type) fn.value site, in first
// occurrence order: the value's code pointer type takes the declared
// parameters plus an opaque environment pointer, which ordinary functions
// do not, so the forwarder adapts the signature.
fn cgen_fn_value_sites(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(__s0_Buffer(U64), __s0_Error) {
    var sites = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_fn_value() {
            let fn_type = cgen_value_type(store, indexes, item.function, item.result)
            var known = false
            var site_at: U64 = 0
            while site_at + 2 < __s0_buffer_len(U64, sites) {
                if __s0_buffer_get(U64, sites, site_at) == item.target && __s0_buffer_get(U64, sites, site_at + 1) == fn_type && __s0_buffer_get(U64, sites, site_at + 2) == item.type_op { known = true }
                site_at = site_at + 3
            }
            if !known {
                sites = try __s0_buffer_append(U64, d, sites, item.target)
                sites = try __s0_buffer_append(U64, d, sites, fn_type)
                sites = try __s0_buffer_append(U64, d, sites, item.type_op)
            }
        }
        at = at + 1
    }
    return Ok(sites)
}

// One wrapper per distinct (target, function type) fn.value site, in first
// occurrence order: the value's code pointer type takes the declared
// parameters plus an opaque environment pointer, which ordinary functions
// do not, so the forwarder adapts the signature.
fn cgen_fn_wrapper_result(d: Domain, initial: CgenWriter, store: MirStore, result_type: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    if result_type == mir_type_unit() { return cgen_put(d, out, "void") }
    return cgen_put_type(d, out, store, result_type)
}

fn cgen_fn_wrapper_params(d: Domain, initial: CgenWriter, store: MirStore, fn_type: U64, named: Bool, env: Bool) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    let param_total = mir_type_part_count(store, fn_type, mir_type_part_function_param())
    if env { out = try cgen_put(d, out, "(") }
    var wrote = false
    var ordinal: U64 = 0
    while ordinal < param_total {
        let part = cgen_type_part(store, fn_type, mir_type_part_function_param(), ordinal)
        if part.part_type != mir_type_unit() {
            if wrote { out = try cgen_put(d, out, ", ") }
            if named { out = try cgen_put_type(d, out, store, part.part_type)
            out = try cgen_put(d, out, " alder_p") }
            if !named { out = try cgen_put(d, out, "alder_p") }
            out = try cgen_put_u64(d, out, ordinal)
            wrote = true
        }
        ordinal = ordinal + 1
    }
    if env {
        if wrote { out = try cgen_put(d, out, ", ") }
        out = try cgen_put(d, out, "void *alder_env)")
    }
    return Ok(out)
}

fn cgen_emit_fn_value_wrappers(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, sites: __s0_Buffer(U64)) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at + 2 < __s0_buffer_len(U64, sites) {
        let target = __s0_buffer_get(U64, sites, at)
        let fn_type = __s0_buffer_get(U64, sites, at + 1)
        let domain_marked = __s0_buffer_get(U64, sites, at + 2)
        let t = __s0_buffer_get(MirTypeRec, store.types, fn_type - 1)
        
        // Forward declaration.
        out = try cgen_put(d, out, "static ")
        out = try cgen_fn_wrapper_result(d, out, store, t.result_type)
        out = try cgen_fn_wrapper_name(d, out, target, fn_type)
        out = try cgen_fn_wrapper_params(d, out, store, fn_type, true, true)
        out = try cgen_put(d, out, ";\n")
        // Definition.
        out = try cgen_put(d, out, "static ")
        out = try cgen_fn_wrapper_result(d, out, store, t.result_type)
        out = try cgen_fn_wrapper_name(d, out, target, fn_type)
        out = try cgen_fn_wrapper_params(d, out, store, fn_type, true, true)
        out = try cgen_put(d, out, " {\n  (void)alder_env;\n  ")
        if t.result_type != mir_type_unit() { out = try cgen_put(d, out, "return ") }
        out = try cgen_emit_function_name(d, out, store, target)
        out = try cgen_put(d, out, "(")
        // A storage-model target: the environment member carries the
        // AlderDomain * captured at the fn.value site, and it becomes the
        // target's leading domain argument.
        let thunk_params = mir_v5_function_param_count(store, indexes, target)
        let declared_params = mir_type_part_count(store, fn_type, mir_type_part_function_param())
        var wrote_argument = false
        if domain_marked != 0 {
            out = try cgen_put(d, out, "(AlderDomain *)alder_env")
            wrote_argument = true
        }
        if declared_params != 0 {
            if wrote_argument { out = try cgen_put(d, out, ", ") }
            out = try cgen_fn_wrapper_params(d, out, store, fn_type, false, false)
            wrote_argument = true
        }
        // A closure thunk takes one trailing environment parameter beyond
        // the function type's declared parameters: the wrapper adapts the
        // opaque void * environment to the thunk's reference parameter. A
        // domain-marked target also has one parameter beyond the declared
        // set, but that parameter is the leading domain, already supplied
        // above.
        if domain_marked == 0 && thunk_params == declared_params + 1 {
            let last = mir_v5_param_type(store, indexes, target, 0, mir_param_function(), thunk_params - 1)
            if wrote_argument { out = try cgen_put(d, out, ", ") }
            out = try cgen_put(d, out, "(")
            out = try cgen_put_type(d, out, store, last)
            out = try cgen_put(d, out, "){ alder_env, (uint64_t)1 }")
        }
        out = try cgen_put(d, out, ");\n}\n")
        at = at + 3
    }
    return Ok(out)
}

fn cgen_fn_wrapper_name(d: Domain, initial: CgenWriter, target: U64, fn_type: U64) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_put(d, initial, " alder_fnwrap_")
    out = try cgen_put_u64(d, out, target - 1)
    out = try cgen_put(d, out, "_")
    return cgen_put_u64(d, out, fn_type - 1)
}

// True when a signature type references one binding block: the type is one
// of the block's claimed members, or a pointee chain reaches one.
fn cgen_type_references_block(store: MirStore, block: U64, type_id: U64) -> Bool {
    if type_id == 0 || type_id > __s0_buffer_len(MirTypeRec, store.types) { return false }
    let total = cgen_binding_type_count(store, block)
    var at: U64 = 0
    while at < total {
        if cgen_binding_type_operand(store, block, at) == type_id { return true }
        at = at + 1
    }
    let rec = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if rec.kind == mir_type_kind_c_ptr() || rec.kind == mir_type_kind_c_const_ptr() { return cgen_type_references_block(store, block, rec.elem) }
    return false
}

fn cgen_export_references_block(store: MirStore, indexes: MirVIndexes, function: U64, block: U64) -> Bool {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    if cgen_type_references_block(store, block, item.result_type) { return true }
    let count = cgen_function_param_count(store, indexes, function)
    var at: U64 = 0
    while at < count {
        if cgen_type_references_block(store, block, cgen_function_param(store, indexes, function, at).param_type) { return true }
        at = at + 1
    }
    return false
}

// One export prototype: the C ABI signature with positional parameter names.
fn cgen_emit_export_prototype(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    let has_domain = cgen_function_has_domain(store, indexes, function)
    var first_param: U64 = 0
    if has_domain { first_param = 1 }
    let total = cgen_function_param_count(store, indexes, function)
    var out = initial
    if item.result_type == mir_type_unit() {
        out = try cgen_put(d, out, "void ")
    } else {
        out = try cgen_put_type(d, out, store, item.result_type)
        out = try cgen_put(d, out, " ")
    }
    out = try cgen_put_name(d, out, store, item.export_name_start, item.export_name_end)
    out = try cgen_put(d, out, "(")
    var ordinal = first_param
    var wrote = false
    while ordinal < total {
        let parameter = cgen_function_param(store, indexes, function, ordinal)
        if wrote { out = try cgen_put(d, out, ", ") }
        out = try cgen_put_type(d, out, store, parameter.param_type)
        out = try cgen_put(d, out, " alder_a")
        out = try cgen_put_u64(d, out, ordinal - first_param)
        wrote = true
        ordinal = ordinal + 1
    }
    if !wrote { out = try cgen_put(d, out, "void") }
    return cgen_put(d, out, ");\n")
}

// Lexicographic order of two export symbols by their stored bytes. Export
// names are unique, so equality is unreachable for two distinct functions.
fn cgen_export_name_order(store: MirStore, left: U64, right: U64) -> I64 {
    let left_item = __s0_buffer_get(MirFunctionRec, store.functions, left - 1)
    let right_item = __s0_buffer_get(MirFunctionRec, store.functions, right - 1)
    let left_len = left_item.export_name_end - left_item.export_name_start
    let right_len = right_item.export_name_end - right_item.export_name_start
    var at: U64 = 0
    while at < left_len && at < right_len {
        let left_byte = __s0_buffer_get(U8, store.names, left_item.export_name_start + at)
        let right_byte = __s0_buffer_get(U8, store.names, right_item.export_name_start + at)
        if left_byte < right_byte { return -1 }
        if left_byte > right_byte { return 1 }
        at = at + 1
    }
    if left_len < right_len { return -1 }
    if left_len > right_len { return 1 }
    return 0
}

// Exported function IDs sorted by symbol bytes. Insertion sort keeps the
// helper allocation-light and deterministic for the small export sets a
// module carries; the order never depends on declaration order.
fn cgen_sorted_export_ids(d: Domain, store: MirStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    var ids = try __s0_buffer_new(U64, d)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        if __s0_buffer_get(MirFunctionRec, store.functions, function - 1).c_export { ids = try __s0_buffer_append(U64, d, ids, function) }
        function = function + 1
    }
    var at: U64 = 1
    while at < __s0_buffer_len(U64, ids) {
        let key = __s0_buffer_get(U64, ids, at)
        var slot = at
        while slot > 0 && cgen_export_name_order(store, __s0_buffer_get(U64, ids, slot - 1), key) > 0 {
            __s0_buffer_set(U64, ids, slot, __s0_buffer_get(U64, ids, slot - 1))
            slot = slot - 1
        }
        __s0_buffer_set(U64, ids, slot, key)
        at = at + 1
    }
    return Ok(ids)
}

// Modular addition for the 64-bit guard hash, below the largest portable
// multiplication-free modulus used by the compiler's other stable hashes.
fn cgen_guard_hash_add(left: U64, right: U64) -> U64 {
    let modulus: U64 = 9223372036854775783
    if left >= modulus - right { return left - (modulus - right) }
    return left + right
}

// One polynomial-hash step: hash * 33 + byte, modulo the hash modulus.
fn cgen_guard_hash_byte(hash: U64, byte: U8) -> U64 {
    var doubled = hash
    var bit: U64 = 0
    while bit < 5 {
        doubled = cgen_guard_hash_add(doubled, doubled)
        bit = bit + 1
    }
    let shifted = cgen_guard_hash_add(doubled, hash)
    return cgen_guard_hash_add(shifted, cgen_u8_to_u64(byte))
}

// Digest of the full sorted export symbol list. Sorting before hashing makes
// the header guard independent of declaration order and of every case-only
// collision that a first-symbol guard allowed.
fn cgen_header_guard_hash(d: Domain, store: MirStore) -> Result(U64, __s0_Error) {
    let ids = try cgen_sorted_export_ids(d, store)
    var hash: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(U64, ids) {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, __s0_buffer_get(U64, ids, at) - 1)
        var name_at = item.export_name_start
        while name_at < item.export_name_end {
            hash = cgen_guard_hash_byte(hash, __s0_buffer_get(U8, store.names, name_at))
            name_at = name_at + 1
        }
        // A zero byte cannot occur inside a C identifier, so it separates
        // adjacent names without an extra length prefix.
        hash = cgen_guard_hash_byte(hash, 0)
        at = at + 1
    }
    return Ok(hash)
}

// One lowercase hexadecimal digit of the guard digest.
fn cgen_put_hex_digit(d: Domain, initial: CgenWriter, digit: U64) -> Result(CgenWriter, __s0_Error) {
    if digit == 0 { return cgen_put_byte(d, initial, 48) }
    if digit == 1 { return cgen_put_byte(d, initial, 49) }
    if digit == 2 { return cgen_put_byte(d, initial, 50) }
    if digit == 3 { return cgen_put_byte(d, initial, 51) }
    if digit == 4 { return cgen_put_byte(d, initial, 52) }
    if digit == 5 { return cgen_put_byte(d, initial, 53) }
    if digit == 6 { return cgen_put_byte(d, initial, 54) }
    if digit == 7 { return cgen_put_byte(d, initial, 55) }
    if digit == 8 { return cgen_put_byte(d, initial, 56) }
    if digit == 9 { return cgen_put_byte(d, initial, 57) }
    if digit == 10 { return cgen_put_byte(d, initial, 97) }
    if digit == 11 { return cgen_put_byte(d, initial, 98) }
    if digit == 12 { return cgen_put_byte(d, initial, 99) }
    if digit == 13 { return cgen_put_byte(d, initial, 100) }
    if digit == 14 { return cgen_put_byte(d, initial, 101) }
    return cgen_put_byte(d, initial, 102)
}

// The 16-digit lowercase hexadecimal guard digest.
fn cgen_emit_header_guard_hash(d: Domain, initial: CgenWriter, hash: U64) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var place: U64 = 1152921504606846976
    while place > 0 {
        out = try cgen_put_hex_digit(d, out, (hash / place) % 16)
        if place == 1 { return Ok(out) }
        place = place / 16
    }
    return Ok(out)
}

// The deterministic C header for one module's exports: referenced binding
// headers in declaration order, then the prototypes.
fn cgen_generate_header(d: Domain, store: MirStore) -> Result(Bool, __s0_Error) {
    let indexes = try mir_vindex_build(d, store)
    let guard_hash = try cgen_header_guard_hash(d, store)
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder C11 backend. Do not edit. */\n#ifndef ALDER_EXPORTS_")
    out = try cgen_emit_header_guard_hash(d, out, guard_hash)
    out = try cgen_put(d, out, "_H\n#define ALDER_EXPORTS_")
    out = try cgen_emit_header_guard_hash(d, out, guard_hash)
    out = try cgen_put(d, out, "_H\n\n#include <stddef.h>\n")
    var at: U64 = 0
    var block: U64 = 0
    while block < __s0_buffer_len(MirBindingRec, store.bindings) {
        var referenced = false
        at = 0
        while at < __s0_buffer_len(MirFunctionRec, store.functions) {
            let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
            if item.c_export && cgen_export_references_block(store, indexes, at + 1, block + 1) { referenced = true }
            at = at + 1
        }
        if referenced {
            let rec = __s0_buffer_get(MirBindingRec, store.bindings, block)
            out = try cgen_put(d, out, "#include \"")
            out = try cgen_put_name(d, out, store, rec.header_start, rec.header_end)
            out = try cgen_put(d, out, "\"\n")
        }
        block = block + 1
    }
    out = try cgen_put(d, out, "\n#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n")
    at = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        if __s0_buffer_get(MirFunctionRec, store.functions, at).c_export { out = try cgen_emit_export_prototype(d, out, store, indexes, at + 1) }
        at = at + 1
    }
    out = try cgen_put(d, out, "\n#ifdef __cplusplus\n}\n#endif\n\n#endif\n")
    return Ok(cgen_flush(out))
}

// True when the function carries the hidden leading domain parameter.
fn cgen_function_has_domain(store: MirStore, indexes: MirVIndexes, function: U64) -> Bool {
    let count = cgen_function_param_count(store, indexes, function)
    if count == 0 { return false }
    return mir_vtype_kind(store, cgen_function_param(store, indexes, function, 0).param_type) == mir_type_kind_domain_handle()
}

// One C export wrapper: the source signature is the C ABI signature, the
// internal function keeps its mangled name, and a hidden domain becomes a
// per-call root domain destroyed before the wrapper returns.
fn cgen_emit_one_export(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(CgenWriter, __s0_Error) {
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    let has_domain = cgen_function_has_domain(store, indexes, function)
    var first_param: U64 = 0
    if has_domain { first_param = 1 }
    let total = cgen_function_param_count(store, indexes, function)
    var out = try cgen_put(d, initial, "\n/* export ")
    out = try cgen_put_name(d, out, store, item.export_name_start, item.export_name_end)
    out = try cgen_put(d, out, " */\n")
    if item.result_type == mir_type_unit() {
        out = try cgen_put(d, out, "void ")
    } else {
        out = try cgen_put_type(d, out, store, item.result_type)
        out = try cgen_put(d, out, " ")
    }
    out = try cgen_put_name(d, out, store, item.export_name_start, item.export_name_end)
    out = try cgen_put(d, out, "(")
    var ordinal = first_param
    var wrote = false
    while ordinal < total {
        let parameter = cgen_function_param(store, indexes, function, ordinal)
        if wrote { out = try cgen_put(d, out, ", ") }
        out = try cgen_put_type(d, out, store, parameter.param_type)
        out = try cgen_put(d, out, " alder_a")
        out = try cgen_put_u64(d, out, ordinal - first_param)
        wrote = true
        ordinal = ordinal + 1
    }
    if !wrote { out = try cgen_put(d, out, "void") }
    out = try cgen_put(d, out, ") {\n")
    if has_domain {
        out = try cgen_put(d, out, "  AlderDomain alder_root = {0};\n  if (!alder_domain_init(&alder_root, NULL)) { alder_runtime_panic(\"export domain initialization failed\"); }\n")
    }
    if item.result_type == mir_type_unit() {
        out = try cgen_put(d, out, "  ")
    } else {
        out = try cgen_put(d, out, "  ")
        out = try cgen_put_type(d, out, store, item.result_type)
        out = try cgen_put(d, out, " alder_export_result = ")
    }
    out = try cgen_emit_function_name(d, out, store, function)
    out = try cgen_put(d, out, "(")
    var argument = first_param
    var first_argument = true
    if has_domain {
        out = try cgen_put(d, out, "&alder_root")
        first_argument = false
    }
    while argument < total {
        if !first_argument { out = try cgen_put(d, out, ", ") }
        out = try cgen_put(d, out, "alder_a")
        out = try cgen_put_u64(d, out, argument - first_param)
        first_argument = false
        argument = argument + 1
    }
    out = try cgen_put(d, out, ");\n")
    if has_domain { out = try cgen_put(d, out, "  alder_domain_destroy(&alder_root);\n") }
    if item.result_type == mir_type_unit() {
        out = try cgen_put(d, out, "}\n")
    } else {
        out = try cgen_put(d, out, "  return alder_export_result;\n}\n")
    }
    return Ok(out)
}

// All C export wrappers in function declaration order.
fn cgen_emit_exports(d: Domain, initial: CgenWriter, store: MirStore, indexes: MirVIndexes) -> Result(CgenWriter, __s0_Error) {
    var out = initial
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
        if item.c_export { out = try cgen_emit_one_export(d, out, store, indexes, at + 1) }
        at = at + 1
    }
    return Ok(out)
}

fn cgen_build(d: Domain, store: MirStore, indexes: MirVIndexes, verified: MirVerifyCompleteOutput) -> Result(CgenWriter, __s0_Error) {
    var out = try cgen_writer_new(d)
    out = try cgen_put(d, out, "/* Generated by the Alder C11 backend. Do not edit. */\n/* Source: complete-verifier-gated Alder MIR 6. */\n")
    // A binding block may include POSIX headers, and its own feature-test
    // macro can only take effect if no libc header was read first. Programs
    // with bindings therefore select the POSIX.1-2008 surface up front, and
    // binding headers are included before the program headers. Pure Alder
    // programs keep the narrower default surface and byte-identical output.
    if __s0_buffer_len(MirBindingRec, store.bindings) > 0 {
        out = try cgen_put(d, out, "#if defined(__linux__) && !defined(_DEFAULT_SOURCE)\n#define _DEFAULT_SOURCE 1\n#endif\n#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)\n#define _DARWIN_C_SOURCE 1\n#endif\n")
    }
    // Binding headers come first: a header may select POSIX or platform
    // feature-test macros, and those must be defined before any libc header
    // is included. The generated program headers follow and cannot change a
    // binding header's own feature selection.
    out = try cgen_emit_bindings(d, out, store)
    out = try cgen_put(d, out, "#include \"alder.h\"\n")
    if verified.hosted { out = try cgen_put(d, out, "#include \"alder_host.h\"\n") }
    out = try cgen_put(d, out, "#include <float.h>\n#include <string.h>\n")
    out = try cgen_put(d, out, "#if defined(__GNUC__) && !defined(__clang__)\n#pragma GCC diagnostic ignored \"-Wunknown-pragmas\"\n#endif\n")
    out = try cgen_put(d, out, "#pragma STDC FP_CONTRACT OFF\n\n")
    out = try cgen_emit_types(d, out, store)
    out = try cgen_emit_constants(d, out, store)
    out = try cgen_emit_functions(d, out, store, indexes)
    out = try cgen_emit_imports(d, out, store)
    out = try cgen_emit_binding_decls(d, out, store)
    out = try cgen_emit_cleanup_sites(d, out, store, indexes)
    out = try cgen_emit_copy_helpers(d, out, store, indexes)
    out = try cgen_emit_env_retain_helpers(d, out, store, indexes)
    let fn_value_sites = try cgen_fn_value_sites(d, store, indexes)
    out = try cgen_emit_fn_value_wrappers(d, out, store, indexes, fn_value_sites)
    out = try cgen_emit_callback_owner_releases(d, out, store)
    out = try cgen_emit_callback_trampolines(d, out, store, indexes)
    out = try cgen_emit_bodies(d, out, store)
    out = try cgen_emit_exports(d, out, store, indexes)
    if verified.hosted { out = try cgen_emit_host_entry(d, out, store, indexes, verified.entry) }
    return Ok(out)
}

// Internal production entry for an already verified module. The unsupported
// operation preflight still finishes before the output buffer is allocated.
fn cgen_generate_verified(d: Domain, store: MirStore, verified: MirVerifyCompleteOutput) -> Result(Bool, __s0_Error) {
    if !verified.complete { return Ok(false) }
    let indexes = try mir_vindex_build(d, store)
    if !cgen_supported(store, indexes) { return Ok(false) }
    let writer = try cgen_build(d, store, indexes, verified)
    return Ok(cgen_flush(writer))
}

// Direct callers retain the complete verification gate.
fn cgen_generate(d: Domain, store: MirStore, version: U64, hosted: Bool) -> Result(Bool, __s0_Error) {
    let verified = try mir_verify_complete(d, store, version, hosted)
    return cgen_generate_verified(d, store, verified)
}

// Retained declaration-only conformance API. Complete V1-V10 authorization
// happens before allocation of the output buffer; the verified hosted and
// entry fields alone select the program adapter.
fn cgen_write_declaration_skeleton(d: Domain, store: MirStore, version: U64, hosted: Bool) -> Result(Bool, __s0_Error) {
    let verified = try mir_verify_complete(d, store, version, hosted)
    if !verified.complete { return Ok(false) }
    let writer = try cgen_build_declaration_skeleton(d, store, verified)
    return Ok(cgen_flush(writer))
}
