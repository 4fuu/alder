// Deterministic lowering from the sealed checked model to independent MIR 3.
// This layer consumes semantic IDs and canonical source spans only. Parser
// records, kinds, links, and child graphs are not part of its input. A
// malformed or unresolved checked model is an internal failure.

type LowerTypeMapRec {
    checked_type: U64
    mir_type: U64
}

type LowerOwnerMapRec {
    owner: U64
    mir_id: U64
}

type LowerBindingMapRec {
    binding: U64
    mir_id: U64
    parameter: U64
}

type LowerValueMapRec {
    expression: U64
    value: U64
}

type LowerState {
    mir: MirStore
    types: __s0_Buffer(LowerTypeMapRec)
    owners: __s0_Buffer(LowerOwnerMapRec)
    imports: __s0_Buffer(LowerOwnerMapRec)
    bindings: __s0_Buffer(LowerBindingMapRec)
    values: __s0_Buffer(LowerValueMapRec)
    valid: Bool
}

type LowerStep {
    state: LowerState
    id: U64
}

type LowerFlowStep {
    state: LowerState
    block: U64
    terminated: Bool
}

enum LowerResult {
    LowerGood(value: MirStore)
    LowerBad
}

fn lower_with_mir(state: LowerState, mir: MirStore) -> LowerState {
    return LowerState(mir: mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, valid: state.valid)
}

fn lower_invalid(state: LowerState) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, valid: false)
}

fn lower_with_types(state: LowerState, types: __s0_Buffer(LowerTypeMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, valid: state.valid)
}

fn lower_with_owners(state: LowerState, owners: __s0_Buffer(LowerOwnerMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: owners, imports: state.imports, bindings: state.bindings, values: state.values, valid: state.valid)
}

fn lower_with_imports(state: LowerState, imports: __s0_Buffer(LowerOwnerMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: imports, bindings: state.bindings, values: state.values, valid: state.valid)
}

fn lower_with_bindings(state: LowerState, bindings: __s0_Buffer(LowerBindingMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: bindings, values: state.values, valid: state.valid)
}

fn lower_with_values(state: LowerState, values: __s0_Buffer(LowerValueMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: values, valid: state.valid)
}

fn lower_word(d: Domain, bytes: __s0_Buffer(U8), start: U64, end: U64) -> Result(String, __s0_Error) {
    var out = try __s0_buffer_new(U8, d)
    var at = start
    while at < end {
        out = try __s0_buffer_append(U8, d, out, __s0_buffer_get(U8, bytes, at))
        at = at + 1
    }
    return Ok(__s0_buffer_slice(U8, out))
}

fn lower_source_word(d: Domain, source_state: State, source: U64, start: U64, end: U64) -> Result(String, __s0_Error) {
    if source >= __s0_buffer_len(SourceRec, source_state.sources) { return lower_word(d, source_state.texts, 0, 0) }
    let rec = __s0_buffer_get(SourceRec, source_state.sources, source)
    return lower_word(d, source_state.texts, rec.text_start + start, rec.text_start + end)
}

fn lower_decimal_name(d: Domain, prefix: String, value: U64) -> Result(String, __s0_Error) {
    var bytes = try __s0_buffer_new(U8, d)
    var at: U64 = 0
    while at < len(prefix) {
        bytes = try __s0_buffer_append(U8, d, bytes, prefix[at])
        at = at + 1
    }
    var divisor: U64 = 1
    while value / divisor >= 10 { divisor = divisor * 10 }
    while divisor > 0 {
        let digit = (value / divisor) % 10
        if digit == 0 { bytes = try __s0_buffer_append(U8, d, bytes, 48) }
        if digit == 1 { bytes = try __s0_buffer_append(U8, d, bytes, 49) }
        if digit == 2 { bytes = try __s0_buffer_append(U8, d, bytes, 50) }
        if digit == 3 { bytes = try __s0_buffer_append(U8, d, bytes, 51) }
        if digit == 4 { bytes = try __s0_buffer_append(U8, d, bytes, 52) }
        if digit == 5 { bytes = try __s0_buffer_append(U8, d, bytes, 53) }
        if digit == 6 { bytes = try __s0_buffer_append(U8, d, bytes, 54) }
        if digit == 7 { bytes = try __s0_buffer_append(U8, d, bytes, 55) }
        if digit == 8 { bytes = try __s0_buffer_append(U8, d, bytes, 56) }
        if digit == 9 { bytes = try __s0_buffer_append(U8, d, bytes, 57) }
        divisor = divisor / 10
    }
    return Ok(__s0_buffer_slice(U8, bytes))
}

fn lower_type_lookup(state: LowerState, checked_type: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(LowerTypeMapRec, state.types) {
        let item = __s0_buffer_get(LowerTypeMapRec, state.types, at)
        if item.checked_type == checked_type { return item.mir_type }
        at = at + 1
    }
    return 0
}

fn lower_owner_lookup(items: __s0_Buffer(LowerOwnerMapRec), owner: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(LowerOwnerMapRec, items) {
        let item = __s0_buffer_get(LowerOwnerMapRec, items, at)
        if item.owner == owner { return item.mir_id }
        at = at + 1
    }
    return 0
}

fn lower_binding_lookup(state: LowerState, binding: U64) -> LowerBindingMapRec {
    var at = __s0_buffer_len(LowerBindingMapRec, state.bindings)
    while at > 0 {
        let item = __s0_buffer_get(LowerBindingMapRec, state.bindings, at - 1)
        if item.binding == binding { return item }
        at = at - 1
    }
    return LowerBindingMapRec(binding: 0, mir_id: 0, parameter: 0)
}

fn lower_primitive(target: U64) -> U64 {
    if target == 1 { return mir_type_bool() }
    if target == 2 { return mir_type_i8() }
    if target == 3 { return mir_type_i16() }
    if target == 4 { return mir_type_i32() }
    if target == 5 { return mir_type_i64() }
    if target == 6 { return mir_type_u8() }
    if target == 7 { return mir_type_u16() }
    if target == 8 { return mir_type_u32() }
    if target == 9 { return mir_type_u64() }
    if target == 10 { return mir_type_f32() }
    if target == 11 { return mir_type_f64() }
    if target == 12 { return mir_type_unit() }
    return 0
}

fn lower_type_concrete(store: CheckStore, checked_type: U64) -> Bool {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 6 { return false }
    if checked.arg_count > 0 && (checked.first_arg == 0 || checked.first_arg - 1 + checked.arg_count > __s0_buffer_len(U64, store.type_args)) { return false }
    var ordinal: U64 = 0
    while ordinal < checked.arg_count {
        if !lower_type_concrete(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal)) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn lower_type(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64) -> Result(LowerStep, __s0_Error) {
    let prior = lower_type_lookup(state, checked_type)
    if prior != 0 { return Ok(LowerStep(state: state, id: prior)) }
    if !lower_type_concrete(store, checked_type) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 {
        let primitive = lower_primitive(checked.target)
        if primitive == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: primitive))
        return Ok(LowerStep(state: lower_with_types(state, mapped), id: primitive))
    }
    if checked.kind == 3 || checked.kind == 4 {
        var id = mir_type_kind_domain_handle()
        if checked.kind == 4 { id = mir_type_kind_domain_mark() }
        let empty = try __s0_buffer_new(U64, d)
        let built = try mir_intern_type(d, state.mir, id, 0, 0, 0, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 7 {
        if checked.target == 0 || checked.target > __s0_buffer_len(SymbolRec, store.symbols) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
        if symbol.kind != 2 && symbol.kind != 3 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let base = try lower_source_word(d, source_state, symbol.source, symbol.name_start, symbol.name_end)
        var name = base
        if checked.arg_count != 0 { name = try lower_decimal_name(d, base, checked_type) }
        var kind = mir_type_kind_aggregate()
        if symbol.kind == 3 { kind = mir_type_kind_enum() }
        let built = try mir_add_named_type(d, state.mir, kind, name)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 5 {
        let built = try mir_add_named_type(d, state.mir, mir_type_kind_enum(), "__s0_Error")
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        var next = lower_with_types(lower_with_mir(state, built.store), mapped)
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_variant(), built.type_id, 0, "OutOfMemory", mir_type_unit()))
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_variant(), built.type_id, 1, "Limit", mir_type_unit()))
        return Ok(LowerStep(state: next, id: built.type_id))
    }
    if checked.kind == 8 || checked.kind == 9 || checked.kind == 12 {
        if checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let elem = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        if !elem.state.valid { return Ok(elem) }
        var kind = mir_type_kind_slice()
        if checked.kind == 9 { kind = mir_type_kind_option() }
        if checked.kind == 12 { kind = mir_type_kind_raw_ptr() }
        let empty = try __s0_buffer_new(U64, d)
        let built = try mir_intern_type(d, elem.state.mir, kind, elem.id, 0, 0, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, elem.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(elem.state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 10 {
        if checked.arg_count != 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let ok_type = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        let err_type = try lower_type(d, source_state, store, ok_type.state, __s0_buffer_get(U64, store.type_args, checked.first_arg))
        if !err_type.state.valid { return Ok(err_type) }
        let empty = try __s0_buffer_new(U64, d)
        let built = try mir_intern_type(d, err_type.state.mir, mir_type_kind_result(), 0, ok_type.id, err_type.id, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, err_type.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(err_type.state, built.store), mapped), id: built.type_id))
    }
    // Map, Buffer, and all remaining storage/resource forms belong to #11.
    return Ok(LowerStep(state: lower_invalid(state), id: 0))
}

fn lower_type_bound(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, declaration: U64, application: U64) -> Result(LowerStep, __s0_Error) {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind != 6 { return lower_type(d, source_state, store, state, checked_type) }
    if application == 0 || application > __s0_buffer_len(CheckedTypeRec, store.types) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let applied = __s0_buffer_get(CheckedTypeRec, store.types, application - 1)
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let param = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if param.owner == declaration {
            if at + 1 == checked.target {
                if ordinal >= applied.arg_count { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
                return lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, applied.first_arg - 1 + ordinal))
            }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return Ok(LowerStep(state: lower_invalid(state), id: 0))
}

fn lower_named_parts(d: Domain, source_state: State, store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var checked_id: U64 = 1
    while checked_id <= __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_id - 1)
        if checked.kind == 7 && lower_type_concrete(store, checked_id) {
            let skeleton = try lower_type(d, source_state, store, current, checked_id)
            current = skeleton.state
            if !current.valid { return Ok(current) }
            var ordinal: U64 = 0
            var use_at: U64 = 0
            while use_at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
                let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_at)
                if use.owner == checked.target && (use.role == 1 || use.role == 2) {
                    var part_type = mir_type_unit()
                    if use.checked_type != 0 {
                        let lowered = try lower_type_bound(d, source_state, store, current, use.checked_type, checked.target, checked_id)
                        current = lowered.state
                        part_type = lowered.id
                    }
                    if !current.valid { return Ok(current) }
                    let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
                    var part_kind = mir_type_part_field()
                    if use.role == 2 { part_kind = mir_type_part_variant() }
                    current = lower_with_mir(current, try mir_add_type_part(d, current.mir, part_kind, skeleton.id, ordinal, name, part_type))
                    ordinal = ordinal + 1
                }
                use_at = use_at + 1
            }
        }
        checked_id = checked_id + 1
    }
    return Ok(current)
}

fn lower_use_by_role(store: CheckStore, owner: U64, role: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role && use.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn lower_use_count(store: CheckStore, owner: U64, role: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role { count = count + 1 }
        at = at + 1
    }
    return count
}

fn lower_declarations(d: Domain, source_state: State, store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    // Materialize every canonical concrete named type before adding parts.
    var checked: U64 = 1
    while checked <= __s0_buffer_len(CheckedTypeRec, store.types) {
        let rec = __s0_buffer_get(CheckedTypeRec, store.types, checked - 1)
        if (rec.kind == 5 || rec.kind == 7) && lower_type_concrete(store, checked) {
            let step = try lower_type(d, source_state, store, current, checked)
            current = step.state
        }
        checked = checked + 1
    }
    current = try lower_named_parts(d, source_state, store, current)
    if !current.valid { return Ok(current) }
    // Imports retain canonical symbol order and concrete signature uses.
    var owner: U64 = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if symbol.kind == 1 {
            let result_use = lower_use_by_role(store, owner, 4, 0)
            if result_use == 0 { return Ok(lower_invalid(current)) }
            let result_rec = __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1)
            let result_type = try lower_type(d, source_state, store, current, result_rec.checked_type)
            current = result_type.state
            let name = try lower_source_word(d, source_state, symbol.source, symbol.name_start, symbol.name_end)
            let imported = try mir_add_import(d, current.mir, name, result_type.id)
            current = lower_with_mir(current, imported.store)
            var ordinal: U64 = 0
            while ordinal < lower_use_count(store, owner, 3) {
                let use_id = lower_use_by_role(store, owner, 3, ordinal)
                if use_id == 0 { return Ok(lower_invalid(current)) }
                let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
                let parameter = try lower_type(d, source_state, store, current, use.checked_type)
                current = lower_with_mir(parameter.state, try mir_add_import_param(d, parameter.state.mir, imported.id, ordinal, parameter.id))
                ordinal = ordinal + 1
            }
            let imports = try __s0_buffer_append(LowerOwnerMapRec, d, current.imports, LowerOwnerMapRec(owner: owner, mir_id: imported.id))
            current = lower_with_imports(current, imports)
        }
        owner = owner + 1
    }
    // Function skeletons are fixed before any call body is emitted.
    owner = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        let concrete = (symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13
        if concrete {
            var result_role: U64 = 8
            if symbol.kind == 12 { result_role = 6 }
            let result_use = lower_use_by_role(store, owner, result_role, 0)
            if result_use == 0 { return Ok(lower_invalid(current)) }
            let result_rec = __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1)
            let result_type = try lower_type(d, source_state, store, current, result_rec.checked_type)
            current = result_type.state
            let base = try lower_source_word(d, source_state, symbol.source, symbol.name_start, symbol.name_end)
            var name = base
            if symbol.kind == 13 { name = try lower_decimal_name(d, base, owner) }
            let function = try mir_add_function(d, current.mir, name, result_type.id)
            current = lower_with_mir(current, function.store)
            let owners = try __s0_buffer_append(LowerOwnerMapRec, d, current.owners, LowerOwnerMapRec(owner: owner, mir_id: function.id))
            current = lower_with_owners(current, owners)
        }
        owner = owner + 1
    }
    return Ok(current)
}

fn lower_instruction_ordinal(mir: MirStore, function: U64, block: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, mir.instructions) {
        let item = __s0_buffer_get(MirInstrRec, mir.instructions, at)
        if item.function == function && item.block == block { count = count + 1 }
        at = at + 1
    }
    return count
}

fn lower_block_terminated(mir: MirStore, function: U64, block: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTermRec, mir.terminators) {
        let term = __s0_buffer_get(MirTermRec, mir.terminators, at)
        if term.function == function && term.block == block { return true }
        at = at + 1
    }
    return false
}

fn lower_open_block(mir: MirStore, function: U64, requested: U64) -> U64 {
    if !lower_block_terminated(mir, function, requested) { return requested }
    var block = requested
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, mir.blocks) {
        let candidate = __s0_buffer_get(MirBlockRec, mir.blocks, at)
        if candidate.function == function && candidate.ordinal >= ordinal && !lower_block_terminated(mir, function, candidate.ordinal + 1) {
            block = candidate.ordinal + 1
            ordinal = candidate.ordinal
        }
        at = at + 1
    }
    return block
}

fn lower_block_count(mir: MirStore, function: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirBlockRec, mir.blocks) {
        if __s0_buffer_get(MirBlockRec, mir.blocks, at).function == function { count = count + 1 }
        at = at + 1
    }
    return count
}

fn lower_add_block(d: Domain, state: LowerState, function: U64, prefix: String) -> Result(LowerStep, __s0_Error) {
    let ordinal = lower_block_count(state.mir, function)
    let name = try lower_decimal_name(d, prefix, ordinal)
    let block = try mir_add_block(d, state.mir, function, ordinal, name)
    return Ok(LowerStep(state: lower_with_mir(state, block.store), id: block.id))
}

fn lower_add_term_operand(d: Domain, state: LowerState, term: U64, ordinal: U64, edge: U64, value: U64, target: U64) -> Result(LowerState, __s0_Error) {
    let operand = MirOperandRec(kind: mir_operand_terminator_arg(), owner: term, ordinal: ordinal, edge: edge, value: value, target: target, operand_type: 0, name_start: 0, name_end: 0)
    let step = try mir_add_operand(d, state.mir, operand)
    return Ok(lower_with_mir(state, step.store))
}

fn lower_jump(d: Domain, state: LowerState, function: U64, block: U64, target: U64) -> Result(LowerState, __s0_Error) {
    let term = try mir_add_terminator(d, state.mir, MirTermRec(function: function, block: block, kind: mir_term_jump(), value: 0, target: target, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(state, term.store))
}

fn lower_jump_value(d: Domain, state: LowerState, function: U64, block: U64, target: U64, value: U64) -> Result(LowerState, __s0_Error) {
    let term = try mir_add_terminator(d, state.mir, MirTermRec(function: function, block: block, kind: mir_term_jump(), value: 0, target: target, then_block: 0, else_block: 0))
    return lower_add_term_operand(d, lower_with_mir(state, term.store), term.id, 0, mir_edge_jump(), value, target)
}

fn lower_jump_two(d: Domain, state: LowerState, function: U64, block: U64, target: U64, first: U64, second: U64) -> Result(LowerState, __s0_Error) {
    let term = try mir_add_terminator(d, state.mir, MirTermRec(function: function, block: block, kind: mir_term_jump(), value: 0, target: target, then_block: 0, else_block: 0))
    let one = try lower_add_term_operand(d, lower_with_mir(state, term.store), term.id, 0, mir_edge_jump(), first, target)
    return lower_add_term_operand(d, one, term.id, 1, mir_edge_jump(), second, target)
}

fn lower_branch(d: Domain, state: LowerState, function: U64, block: U64, value: U64, then_block: U64, else_block: U64) -> Result(LowerState, __s0_Error) {
    let term = try mir_add_terminator(d, state.mir, MirTermRec(function: function, block: block, kind: mir_term_branch(), value: value, target: 0, then_block: then_block, else_block: else_block))
    return Ok(lower_with_mir(state, term.store))
}

fn lower_add_result(d: Domain, state: LowerState, function: U64, block: U64, checked_type: U64, source_state: State, store: CheckStore) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    if !typ.state.valid { return Ok(typ) }
    let active = lower_open_block(typ.state.mir, function, block)
    let name = try lower_decimal_name(d, "v", __s0_buffer_len(MirValueRec, typ.state.mir.values) + 1)
    let value = try mir_add_value(d, typ.state.mir, function, name, typ.id, mir_value_def_instruction(), active, lower_instruction_ordinal(typ.state.mir, function, active) + 1)
    return Ok(LowerStep(state: lower_with_mir(typ.state, value.store), id: value.id))
}

fn lower_add_instr(d: Domain, state: LowerState, function: U64, block: U64, op: U64, result: U64, place: U64, type_op: U64, a: U64, b: U64, target: U64, name: String) -> Result(LowerStep, __s0_Error) {
    let active = lower_open_block(state.mir, function, block)
    var named = MirNameStep(store: state.mir, start: 0, end: 0)
    if len(name) != 0 { named = try mir_append_name(d, state.mir, name) }
    let rec = MirInstrRec(function: function, block: active, ordinal: lower_instruction_ordinal(named.store, function, active), op: op, result: result, place: place, type_op: type_op, a: a, b: b, c: 0, target: target, name_start: named.start, name_end: named.end)
    let step = try mir_add_instruction(d, named.store, rec)
    return Ok(LowerStep(state: lower_with_mir(state, step.store), id: step.id))
}

fn lower_add_instr_operand(d: Domain, state: LowerState, instruction: U64, ordinal: U64, value: U64, kind: U64, name: String) -> Result(LowerState, __s0_Error) {
    var named = MirNameStep(store: state.mir, start: 0, end: 0)
    if len(name) != 0 { named = try mir_append_name(d, state.mir, name) }
    let rec = MirOperandRec(kind: kind, owner: instruction, ordinal: ordinal, edge: 0, value: value, target: 0, operand_type: 0, name_start: named.start, name_end: named.end)
    let step = try mir_add_operand(d, named.store, rec)
    return Ok(lower_with_mir(state, step.store))
}

fn lower_variant_name(d: Domain, source_state: State, store: CheckStore, variant_kind: U64, variant_use: U64) -> Result(String, __s0_Error) {
    if variant_kind == 1 { return Ok("none") }
    if variant_kind == 2 { return Ok("some") }
    if variant_kind == 3 { return Ok("ok") }
    if variant_kind == 4 { return Ok("err") }
    if variant_kind == 5 { return Ok("OutOfMemory") }
    if variant_kind == 6 { return Ok("Limit") }
    if variant_kind == 7 { return Ok("") }
    if variant_use == 0 || variant_use > __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok("") }
    let use = __s0_buffer_get(DeclTypeUseRec, store.uses, variant_use - 1)
    return lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
}

fn lower_add_switch_case(d: Domain, state: LowerState, term: U64, ordinal: U64, name: String, binding: U64, target: U64) -> Result(LowerStep, __s0_Error) {
    var named = MirNameStep(store: state.mir, start: 0, end: 0)
    if len(name) != 0 { named = try mir_append_name(d, state.mir, name) }
    let operand = MirOperandRec(kind: mir_operand_switch_case(), owner: term, ordinal: ordinal, edge: 0, value: binding, target: target, operand_type: 0, name_start: named.start, name_end: named.end)
    let step = try mir_add_operand(d, named.store, operand)
    return Ok(LowerStep(state: lower_with_mir(state, step.store), id: step.id))
}

fn lower_parse_i64(source_state: State, spans: __s0_Buffer(CheckedSpanRec), expression: CheckedExprRec) -> I64 {
    if expression.syntax == 0 || expression.syntax > __s0_buffer_len(CheckedSpanRec, spans) { return 0 }
    let span = __s0_buffer_get(CheckedSpanRec, spans, expression.syntax - 1)
    let source = __s0_buffer_get(SourceRec, source_state.sources, span.source)
    var value: I64 = 0
    var negative = false
    var at = source.text_start + span.start
    let end = source.text_start + span.end
    if at < end && __s0_buffer_get(U8, source_state.texts, at) == 45 {
        negative = true
        at = at + 1
    }
    while at < end {
        let byte = __s0_buffer_get(U8, source_state.texts, at)
        value = value * 10
        if byte == 49 { value = value + 1 }
        if byte == 50 { value = value + 2 }
        if byte == 51 { value = value + 3 }
        if byte == 52 { value = value + 4 }
        if byte == 53 { value = value + 5 }
        if byte == 54 { value = value + 6 }
        if byte == 55 { value = value + 7 }
        if byte == 56 { value = value + 8 }
        if byte == 57 { value = value + 9 }
        at = at + 1
    }
    if negative { return 0 - value }
    return value
}

fn lower_float_bits(source_state: State, spans: __s0_Buffer(CheckedSpanRec), expression: CheckedExprRec) -> U64 {
    let span = __s0_buffer_get(CheckedSpanRec, spans, expression.syntax - 1)
    let source = __s0_buffer_get(SourceRec, source_state.sources, span.source)
    var at = source.text_start + span.start
    let end = source.text_start + span.end
    var negative: U64 = 0
    if at < end && __s0_buffer_get(U8, source_state.texts, at) == 45 {
        negative = 1
        at = at + 1
    }
    var significand: U64 = 0
    var fraction: I64 = 0
    var exponent: I64 = 0
    var exponent_negative = false
    var after_point = false
    var after_exponent = false
    while at < end {
        let byte = __s0_buffer_get(U8, source_state.texts, at)
        if byte == 46 { after_point = true } else {
            if byte == 101 || byte == 69 { after_exponent = true } else {
                if after_exponent && byte == 45 { exponent_negative = true } else {
                    if after_exponent && byte == 43 { exponent_negative = false } else {
                        var digit: U64 = 0
                        var signed_digit: I64 = 0
                        if byte == 49 { digit = 1 }
                        if byte == 50 { digit = 2 }
                        if byte == 51 { digit = 3 }
                        if byte == 52 { digit = 4 }
                        if byte == 53 { digit = 5 }
                        if byte == 54 { digit = 6 }
                        if byte == 55 { digit = 7 }
                        if byte == 56 { digit = 8 }
                        if byte == 57 { digit = 9 }
                        if byte == 49 { signed_digit = 1 }
                        if byte == 50 { signed_digit = 2 }
                        if byte == 51 { signed_digit = 3 }
                        if byte == 52 { signed_digit = 4 }
                        if byte == 53 { signed_digit = 5 }
                        if byte == 54 { signed_digit = 6 }
                        if byte == 55 { signed_digit = 7 }
                        if byte == 56 { signed_digit = 8 }
                        if byte == 57 { signed_digit = 9 }
                        if after_exponent { exponent = exponent * 10 + signed_digit } else {
                            significand = significand * 10 + digit
                            if after_point { fraction = fraction + 1 }
                        }
                    }
                }
            }
        }
        at = at + 1
    }
    if exponent_negative { exponent = 0 - exponent }
    return unsafe c { alderhost_decimal_f64_bits(negative, significand, exponent - fraction) }
}

fn lower_bool_value(d: Domain, source_state: State, store: CheckStore, state: LowerState, function: U64, block: U64, checked_type: U64, value: U64, suffix: U64) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    let name = try lower_decimal_name(d, "lit.bool", suffix)
    let constant = try mir_add_const(d, typ.state.mir, name, typ.id, mir_const_bool(), value, 0, 0, "")
    let result = try lower_add_result(d, lower_with_mir(typ.state, constant.store), function, block, checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
    return Ok(LowerStep(state: instr.state, id: result.id))
}

fn lower_int_value(d: Domain, source_state: State, store: CheckStore, state: LowerState, function: U64, block: U64, value: I64, suffix: U64) -> Result(LowerStep, __s0_Error) {
    let name = try lower_decimal_name(d, "lit.int", suffix)
    let constant = try mir_add_const(d, state.mir, name, mir_type_u64(), mir_const_int(), 0, value, 0, "")
    let result = try lower_add_result(d, lower_with_mir(state, constant.store), function, block, 9, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
    return Ok(LowerStep(state: instr.state, id: result.id))
}

fn lower_expression(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.owner != owner || !lower_type_concrete(store, expression.checked_type) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if expression.kind == 1 || expression.kind == 5 {
        let binding = lower_binding_lookup(state, expression.parameter_use)
        if binding.binding == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        if binding.parameter != 0 { return Ok(LowerStep(state: state, id: binding.mir_id)) }
        let place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        let result = try lower_add_result(d, lower_with_mir(state, place.store), function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_load(), result.id, place.id, 0, 0, 0, 0, "")
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind >= 2 && expression.kind <= 4 {
        let typ = try lower_type(d, source_state, store, state, expression.checked_type)
        var kind = mir_const_bool()
        var bool_value = expression.bool_value
        var int_value: I64 = 0
        var text = ""
        if expression.kind == 3 {
            kind = mir_const_int()
            int_value = lower_parse_i64(source_state, spans, expression)
        }
        if expression.kind == 4 {
            kind = mir_const_string()
            if expression.syntax == 0 || expression.syntax > __s0_buffer_len(CheckedSpanRec, spans) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
            let span = __s0_buffer_get(CheckedSpanRec, spans, expression.syntax - 1)
            var token_at: U64 = 0
            var found = false
            while token_at < __s0_buffer_len(TokenRec, source_state.tokens) {
                let token = __s0_buffer_get(TokenRec, source_state.tokens, token_at)
                if token.source == span.source && token.start == span.start && token.end == span.end {
                    text = try lower_word(d, source_state.values, token.value_start, token.value_end)
                    found = true
                }
                token_at = token_at + 1
            }
            if !found { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        }
        let name = try lower_decimal_name(d, "lit", expression_id)
        let constant = try mir_add_const(d, typ.state.mir, name, typ.id, kind, bool_value, int_value, 0, text)
        let result = try lower_add_result(d, lower_with_mir(typ.state, constant.store), function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind == 20 {
        if expression.syntax == 0 || expression.syntax > __s0_buffer_len(CheckedSpanRec, spans) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let span = __s0_buffer_get(CheckedSpanRec, spans, expression.syntax - 1)
        if span.source >= __s0_buffer_len(SourceRec, source_state.sources) || span.start >= span.end { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let typ = try lower_type(d, source_state, store, state, expression.checked_type)
        let bits = lower_float_bits(source_state, spans, expression)
        let name = try lower_decimal_name(d, "lit.float", expression_id)
        let constant = try mir_add_const(d, typ.state.mir, name, typ.id, mir_const_float(), 0, 0, bits, "")
        let result = try lower_add_result(d, lower_with_mir(typ.state, constant.store), function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind == 19 {
        if expression.child_count != 2 || expression.first_child == 0 || expression.first_child >= __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let index_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
        let base = try lower_expression(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block)
        let base_block = lower_open_block(base.state.mir, function, block)
        let index = try lower_expression(d, source_state, spans, store, base.state, owner, function, base_block, index_id, environment, panic_block)
        let active = lower_open_block(index.state.mir, function, base_block)
        let element = try lower_type(d, source_state, store, index.state, expression.checked_type)
        let empty = try __s0_buffer_new(U64, d)
        let reference = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
        let ref_value = try mir_add_value(d, reference.store, function, try lower_decimal_name(d, "v", __s0_buffer_len(MirValueRec, reference.store.values) + 1), reference.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(reference.store, function, active) + 1)
        let indexed = try lower_add_instr(d, lower_with_mir(element.state, ref_value.store), function, active, mir_op_slice_index_checked(), ref_value.id, 0, 0, base.id, index.id, panic_block, "")
        let place = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: ref_value.id))
        let result = try lower_add_result(d, lower_with_mir(indexed.state, place.store), function, active, expression.checked_type, source_state, store)
        let loaded = try lower_add_instr(d, result.state, function, active, mir_op_load(), result.id, place.id, 0, 0, 0, 0, "")
        return Ok(LowerStep(state: loaded.state, id: result.id))
    }
    if expression.kind == 21 {
        if expression.child_count != 1 || expression.first_child == 0 || expression.first_child > __s0_buffer_len(CheckedExprChildRec, store.expression_children) || expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let field = __s0_buffer_get(DeclTypeUseRec, store.uses, expression.parameter_use - 1)
        if field.role != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let base = try lower_expression(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block)
        let active = lower_open_block(base.state.mir, function, block)
        let base_expression = __s0_buffer_get(CheckedExprRec, store.expressions, base_id - 1)
        let base_type = try lower_type(d, source_state, store, base.state, base_expression.checked_type)
        var ordinal: U64 = 0
        var local_at: U64 = 0
        while local_at < __s0_buffer_len(MirLocalRec, base_type.state.mir.locals) {
            if __s0_buffer_get(MirLocalRec, base_type.state.mir.locals, local_at).function == function { ordinal = ordinal + 1 }
            local_at = local_at + 1
        }
        let temporary = try mir_add_local(d, base_type.state.mir, function, ordinal, try lower_decimal_name(d, "field_tmp", expression_id), base_type.id)
        let local_place = try mir_add_place(d, temporary.store, MirPlaceRec(function: function, kind: mir_place_local(), local: temporary.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        let stored = try lower_add_instr(d, lower_with_mir(base_type.state, local_place.store), function, active, mir_op_store(), 0, local_place.id, 0, base.id, 0, 0, "")
        let named = try mir_append_name(d, stored.state.mir, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
        let field_place = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: local_place.id, field_start: named.start, field_end: named.end, deref_value: 0))
        let result = try lower_add_result(d, lower_with_mir(stored.state, field_place.store), function, active, expression.checked_type, source_state, store)
        let loaded = try lower_add_instr(d, result.state, function, active, mir_op_load(), result.id, field_place.id, 0, 0, 0, 0, "")
        return Ok(LowerStep(state: loaded.state, id: result.id))
    }
    if expression.kind == 6 || expression.kind == 7 {
        if expression.child_count == 0 || expression.first_child == 0 || expression.first_child - 1 + expression.child_count > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let left_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let left = try lower_expression(d, source_state, spans, store, state, owner, function, block, left_id, environment, panic_block)
        if expression.kind == 6 && expression.operator == 2 {
            let true_block = try lower_add_block(d, left.state, function, "bb_not_true")
            let false_block = try lower_add_block(d, true_block.state, function, "bb_not_false")
            let join = try lower_add_block(d, false_block.state, function, "bb_not_join")
            let typ = try lower_type(d, source_state, store, join.state, expression.checked_type)
            let param = try mir_add_block_param(d, typ.state.mir, function, join.id, 0, "not", typ.id)
            var current = lower_with_mir(typ.state, param.store)
            current = try lower_branch(d, current, function, block, left.id, false_block.id, true_block.id)
            let truth = try lower_bool_value(d, source_state, store, current, function, true_block.id, expression.checked_type, 1, expression_id)
            current = try lower_jump_value(d, truth.state, function, true_block.id, join.id, truth.id)
            let falsity = try lower_bool_value(d, source_state, store, current, function, false_block.id, expression.checked_type, 0, expression_id + 1)
            current = try lower_jump_value(d, falsity.state, function, false_block.id, join.id, falsity.id)
            return Ok(LowerStep(state: current, id: param.id))
        }
        if expression.kind == 7 && (expression.operator == 16 || expression.operator == 17) {
            if expression.child_count != 2 { return Ok(LowerStep(state: lower_invalid(left.state), id: 0)) }
            let right_block = try lower_add_block(d, left.state, function, "bb_short")
            let constant_block = try lower_add_block(d, right_block.state, function, "bb_short_const")
            let join = try lower_add_block(d, constant_block.state, function, "bb_short_join")
            let result_type = try lower_type(d, source_state, store, join.state, expression.checked_type)
            let param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, "short", result_type.id)
            var current = lower_with_mir(result_type.state, param.store)
            let source_block = lower_open_block(current.mir, function, block)
            if expression.operator == 16 { current = try lower_branch(d, current, function, source_block, left.id, right_block.id, constant_block.id) }
            if expression.operator == 17 { current = try lower_branch(d, current, function, source_block, left.id, constant_block.id, right_block.id) }
            let right_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
            let right = try lower_expression(d, source_state, spans, store, current, owner, function, right_block.id, right_id, environment, panic_block)
            current = try lower_jump_value(d, right.state, function, lower_open_block(right.state.mir, function, right_block.id), join.id, right.id)
            var constant_value: U64 = 0
            if expression.operator == 17 { constant_value = 1 }
            let constant = try lower_bool_value(d, source_state, store, current, function, constant_block.id, expression.checked_type, constant_value, expression_id)
            current = try lower_jump_value(d, constant.state, function, constant_block.id, join.id, constant.id)
            return Ok(LowerStep(state: current, id: param.id))
        }
        var right = LowerStep(state: left.state, id: 0)
        if expression.kind == 7 {
            if expression.child_count != 2 { return Ok(LowerStep(state: lower_invalid(left.state), id: 0)) }
            let right_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
            right = try lower_expression(d, source_state, spans, store, left.state, owner, function, block, right_id, environment, panic_block)
        }
        var op: U64 = 0
        if expression.operator == 3 { op = mir_op_int_add_checked() }
        if expression.operator == 4 || expression.operator == 1 { op = mir_op_int_sub_checked() }
        if expression.operator == 5 { op = mir_op_int_mul_checked() }
        if expression.operator == 6 { op = mir_op_int_div_checked() }
        if expression.operator == 8 { op = mir_op_int_shl_checked() }
        if expression.operator == 9 { op = mir_op_int_shr_checked() }
        if expression.operator == 10 { op = mir_op_int_eq() }
        if expression.operator == 11 { op = mir_op_int_ne() }
        if expression.operator == 12 { op = mir_op_int_lt() }
        if expression.operator == 13 { op = mir_op_int_le() }
        if expression.operator == 14 { op = mir_op_int_gt() }
        if expression.operator == 15 { op = mir_op_int_ge() }
        if expression.operator == 7 {
            let quotient = try lower_add_result(d, right.state, function, block, expression.checked_type, source_state, store)
            let divided = try lower_add_instr(d, quotient.state, function, block, mir_op_int_div_checked(), quotient.id, 0, 0, left.id, right.id, panic_block, "")
            let product = try lower_add_result(d, divided.state, function, block, expression.checked_type, source_state, store)
            let multiplied = try lower_add_instr(d, product.state, function, block, mir_op_int_mul_checked(), product.id, 0, 0, quotient.id, right.id, panic_block, "")
            let remainder = try lower_add_result(d, multiplied.state, function, block, expression.checked_type, source_state, store)
            let subtracted = try lower_add_instr(d, remainder.state, function, block, mir_op_int_sub_checked(), remainder.id, 0, 0, left.id, product.id, panic_block, "")
            return Ok(LowerStep(state: subtracted.state, id: remainder.id))
        }
        if expression.operator == 2 || expression.operator == 16 || expression.operator == 17 || op == 0 { return Ok(LowerStep(state: lower_invalid(right.state), id: 0)) }
        var a = left.id
        var b = right.id
        var working = right.state
        if expression.kind == 6 {
            let zero_name = try lower_decimal_name(d, "lit.neg", expression_id)
            let typ = try lower_type(d, source_state, store, working, expression.checked_type)
            let zero = try mir_add_const(d, typ.state.mir, zero_name, typ.id, mir_const_int(), 0, 0, 0, "")
            let zero_value = try lower_add_result(d, lower_with_mir(typ.state, zero.store), function, block, expression.checked_type, source_state, store)
            let zero_instr = try lower_add_instr(d, zero_value.state, function, block, mir_op_const_get(), zero_value.id, 0, 0, 0, 0, 0, zero_name)
            working = zero_instr.state
            a = zero_value.id
            b = left.id
        }
        let result = try lower_add_result(d, working, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, a, b, panic_block, "")
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind >= 8 && expression.kind <= 11 {
        if expression.annotation == 0 || expression.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
        if annotation.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        var current = state
        var args = try __s0_buffer_new(U64, d)
        var ordinal: U64 = 0
        while ordinal < expression.child_count {
            if expression.first_child == 0 || expression.first_child - 1 + ordinal >= __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
            let child = try lower_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block)
            current = child.state
            args = try __s0_buffer_append(U64, d, args, child.id)
            ordinal = ordinal + 1
        }
        let result_type = try lower_type(d, source_state, store, current, expression.checked_type)
        current = result_type.state
        var result: U64 = 0
        if result_type.id != mir_type_unit() {
            let value = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
            current = value.state
            result = value.id
        }
        if annotation.kind == 1 || annotation.kind == 2 {
            var op = mir_op_call()
            var target = lower_owner_lookup(current.owners, annotation.target)
            if annotation.kind == 2 {
                op = mir_op_ffi_call_unsafe()
                target = lower_owner_lookup(current.imports, annotation.target)
            }
            if target == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let instr = try lower_add_instr(d, current, function, block, op, result, 0, 0, 0, 0, target, "")
            current = instr.state
            ordinal = 0
            while ordinal < __s0_buffer_len(U64, args) {
                current = try lower_add_instr_operand(d, current, instr.id, ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
                ordinal = ordinal + 1
            }
            return Ok(LowerStep(state: current, id: result))
        }
        if annotation.kind == 3 {
            let instr = try lower_add_instr(d, current, function, block, mir_op_aggregate_construct(), result, 0, result_type.id, 0, 0, 0, "")
            current = instr.state
            ordinal = 0
            while ordinal < __s0_buffer_len(U64, args) {
                let field_id = lower_use_by_role(store, annotation.target, 1, ordinal)
                if field_id == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                let field = __s0_buffer_get(DeclTypeUseRec, store.uses, field_id - 1)
                let name = try lower_source_word(d, source_state, field.source, field.name_start, field.name_end)
                current = try lower_add_instr_operand(d, current, instr.id, ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_aggregate_field(), name)
                ordinal = ordinal + 1
            }
            return Ok(LowerStep(state: current, id: result))
        }
        if annotation.kind == 4 {
            if annotation.variant_use == 0 || annotation.variant_use > __s0_buffer_len(DeclTypeUseRec, store.uses) || expression.child_count > 1 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, annotation.variant_use - 1)
            let name = try lower_source_word(d, source_state, variant.source, variant.name_start, variant.name_end)
            var payload: U64 = 0
            if expression.child_count == 1 { payload = __s0_buffer_get(U64, args, 0) }
            let instr = try lower_add_instr(d, current, function, block, mir_op_enum_construct(), result, 0, result_type.id, payload, 0, 0, name)
            return Ok(LowerStep(state: instr.state, id: result))
        }
        return Ok(LowerStep(state: lower_invalid(current), id: 0))
    }
    if expression.kind >= 14 && expression.kind <= 17 {
        var name = "none"
        if expression.kind == 15 { name = "some" }
        if expression.kind == 16 { name = "ok" }
        if expression.kind == 17 { name = "err" }
        var current = state
        var payload: U64 = 0
        if expression.child_count == 1 {
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
            let child = try lower_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block)
            current = child.state
            payload = child.id
        }
        let typ = try lower_type(d, source_state, store, current, expression.checked_type)
        let result = try lower_add_result(d, typ.state, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_enum_construct(), result.id, 0, typ.id, payload, 0, 0, name)
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind == 12 {
        if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(CheckedMatchRec, store.control.matches) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let checked = __s0_buffer_get(CheckedMatchRec, store.control.matches, expression.parameter_use - 1)
        if checked.owner != owner || checked.first_arm == 0 || checked.first_arm - 1 + checked.arm_count > __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let scrutinee = try lower_expression(d, source_state, spans, store, state, owner, function, block, checked.scrutinee, environment, panic_block)
        let join = try lower_add_block(d, scrutinee.state, function, "bb_match_join")
        let result_type = try lower_type(d, source_state, store, join.state, checked.checked_type)
        let join_param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, "match", result_type.id)
        var current = lower_with_mir(result_type.state, join_param.store)
        var arm_blocks = try __s0_buffer_new(U64, d)
        var ordinal: U64 = 0
        while ordinal < checked.arm_count {
            let arm_block = try lower_add_block(d, current, function, "bb_match_arm")
            current = arm_block.state
            arm_blocks = try __s0_buffer_append(U64, d, arm_blocks, arm_block.id)
            ordinal = ordinal + 1
        }
        let source_block = lower_open_block(current.mir, function, block)
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: scrutinee.id, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, term.store)
        ordinal = 0
        while ordinal < checked.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal)
            if arm.owner != owner || arm.checked_match != expression.parameter_use { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let name = try lower_variant_name(d, source_state, store, arm.variant_kind, arm.variant_use)
            var binding_value: U64 = 0
            if arm.binding != 0 {
                let local = __s0_buffer_get(LocalRec, store.locals, arm.binding - 1)
                let payload_type = try lower_type(d, source_state, store, current, local.checked_type)
                let value = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "match_payload", ordinal), payload_type.id, mir_value_def_switch_case(), source_block, ordinal + 1)
                current = lower_with_mir(payload_type.state, value.store)
                binding_value = value.id
                let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: arm.binding, mir_id: value.id, parameter: 1))
                current = lower_with_bindings(current, bindings)
            }
            let case = try lower_add_switch_case(d, current, term.id, ordinal, name, binding_value, __s0_buffer_get(U64, arm_blocks, ordinal))
            current = case.state
            ordinal = ordinal + 1
        }
        ordinal = 0
        while ordinal < checked.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal)
            let arm_block = __s0_buffer_get(U64, arm_blocks, ordinal)
            let value = try lower_expression(d, source_state, spans, store, current, owner, function, arm_block, arm.body, arm.environment, panic_block)
            current = try lower_jump_value(d, value.state, function, lower_open_block(value.state.mir, function, arm_block), join.id, value.id)
            ordinal = ordinal + 1
        }
        return Ok(LowerStep(state: current, id: join_param.id))
    }
    if expression.kind == 13 {
        if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(CheckedTryRec, store.control.tries) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let checked = __s0_buffer_get(CheckedTryRec, store.control.tries, expression.parameter_use - 1)
        if checked.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let value = try lower_expression(d, source_state, spans, store, state, owner, function, block, checked.expression, environment, panic_block)
        let ok_block = try lower_add_block(d, value.state, function, "bb_try_ok")
        let err_block = try lower_add_block(d, ok_block.state, function, "bb_try_err")
        let ok_type = try lower_type(d, source_state, store, err_block.state, checked.ok_type)
        let err_type = try lower_type(d, source_state, store, ok_type.state, checked.error_type)
        let source_block = lower_open_block(err_type.state.mir, function, block)
        let ok_value = try mir_add_value(d, err_type.state.mir, function, try lower_decimal_name(d, "try_ok", expression_id), ok_type.id, mir_value_def_switch_case(), source_block, 1)
        let err_value = try mir_add_value(d, ok_value.store, function, try lower_decimal_name(d, "try_err", expression_id), err_type.id, mir_value_def_switch_case(), source_block, 2)
        let term = try mir_add_terminator(d, err_value.store, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: value.id, target: 0, then_block: 0, else_block: 0))
        var current = lower_with_mir(err_type.state, term.store)
        let ok_case = try lower_add_switch_case(d, current, term.id, 0, "ok", ok_value.id, ok_block.id)
        let err_case = try lower_add_switch_case(d, ok_case.state, term.id, 1, "err", err_value.id, err_block.id)
        current = err_case.state
        let result_use = lower_use_by_role(store, owner, 8, 0)
        var actual_result_use = result_use
        let owner_symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if owner_symbol.kind == 12 { actual_result_use = lower_use_by_role(store, owner, 6, 0) }
        if actual_result_use == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let owner_result = __s0_buffer_get(DeclTypeUseRec, store.uses, actual_result_use - 1)
        let fn_type = try lower_type(d, source_state, store, current, owner_result.checked_type)
        let wrapped = try lower_add_result(d, fn_type.state, function, err_block.id, owner_result.checked_type, source_state, store)
        let constructed = try lower_add_instr(d, wrapped.state, function, err_block.id, mir_op_enum_construct(), wrapped.id, 0, fn_type.id, err_value.id, 0, 0, "err")
        current = try lower_cleanup_exits(d, source_state, store, constructed.state, owner, function, err_block.id, environment, 0, 3)
        let failed = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: err_block.id, kind: mir_term_fail(), value: wrapped.id, target: 0, then_block: 0, else_block: 0))
        return Ok(LowerStep(state: lower_with_mir(current, failed.store), id: ok_value.id))
    }
    return Ok(LowerStep(state: lower_invalid(state), id: 0))
}

fn lower_store_binding(d: Domain, state: LowerState, function: U64, block: U64, binding: U64, value: U64) -> Result(LowerState, __s0_Error) {
    let mapped = lower_binding_lookup(state, binding)
    if mapped.binding == 0 || mapped.parameter != 0 { return Ok(lower_invalid(state)) }
    let place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: mapped.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    let instr = try lower_add_instr(d, lower_with_mir(state, place.store), function, block, mir_op_store(), 0, place.id, 0, value, 0, 0, "")
    return Ok(instr.state)
}

fn lower_cleanup_exits(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, site_environment: U64, boundary_environment: U64, exit_kind: U64) -> Result(LowerState, __s0_Error) {
    var current = state
    var environment = site_environment
    while environment != boundary_environment {
        if environment == 0 || environment > __s0_buffer_len(EnvironmentRec, store.environments) { return Ok(lower_invalid(current)) }
        let active = __s0_buffer_get(EnvironmentRec, store.environments, environment - 1)
        if active.owner != owner { return Ok(lower_invalid(current)) }
        var cleanup_id: U64 = 0
        var cleanup_at: U64 = 0
        while cleanup_at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
            let candidate = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, cleanup_at)
            if candidate.owner == owner && candidate.binding == active.binding && candidate.environment == active.parent {
                if cleanup_id != 0 { return Ok(lower_invalid(current)) }
                cleanup_id = cleanup_at + 1
            }
            cleanup_at = cleanup_at + 1
        }
        if cleanup_id != 0 {
            let cleanup = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, cleanup_id - 1)
            var applies = cleanup.normal_exit != 0
            if exit_kind == 2 { applies = cleanup.return_exit != 0 }
            if exit_kind == 3 { applies = cleanup.try_exit != 0 }
            if !applies { return Ok(lower_invalid(current)) }
            let callback = lower_owner_lookup(current.owners, cleanup.callback)
            let binding = lower_binding_lookup(current, cleanup.binding)
            if callback == 0 || binding.binding == 0 { return Ok(lower_invalid(current)) }
            var value = binding.mir_id
            if binding.parameter == 0 {
                let local = __s0_buffer_get(LocalRec, store.locals, cleanup.binding - 1)
                let place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
                let loaded = try lower_add_result(d, lower_with_mir(current, place.store), function, block, local.checked_type, source_state, store)
                let instruction = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, place.id, 0, 0, 0, 0, "")
                current = instruction.state
                value = loaded.id
            }
            let call = try lower_add_instr(d, current, function, block, mir_op_call(), 0, 0, 0, 0, 0, callback, "")
            current = try lower_add_instr_operand(d, call.state, call.id, 0, value, mir_operand_instruction(), "")
        }
        environment = active.parent
    }
    return Ok(current)
}

fn lower_chain_environment(store: CheckStore, owner: U64, link_id: U64, initial: U64) -> U64 {
    if link_id == 0 || link_id > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return initial }
    let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link_id - 1)
    var environment = lower_chain_environment(store, owner, link.next, initial)
    if link.statement == 0 || link.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) { return environment }
    let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, link.statement - 1)
    if statement.owner != owner || statement.environment != environment { return environment }
    if statement.kind == 1 || statement.kind == 2 || statement.kind == 10 {
        var at: U64 = 0
        while at < __s0_buffer_len(EnvironmentRec, store.environments) {
            let candidate = __s0_buffer_get(EnvironmentRec, store.environments, at)
            if candidate.owner == owner && candidate.parent == environment && candidate.binding == statement.binding { return at + 1 }
            at = at + 1
        }
    }
    return environment
}

fn lower_checked_place(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, place_id: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if place_id == 0 || place_id > __s0_buffer_len(CheckedPlaceRec, store.control.places) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let checked = __s0_buffer_get(CheckedPlaceRec, store.control.places, place_id - 1)
    if checked.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let binding = lower_binding_lookup(state, checked.root)
    if binding.binding == 0 || binding.parameter != 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let root = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    var current = lower_with_mir(state, root.store)
    if checked.kind == 1 { return Ok(LowerStep(state: current, id: root.id)) }
    if checked.kind == 2 {
        if checked.field == 0 || checked.field > __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let field = __s0_buffer_get(DeclTypeUseRec, store.uses, checked.field - 1)
        let named = try mir_append_name(d, current.mir, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
        let result = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: root.id, field_start: named.start, field_end: named.end, deref_value: 0))
        return Ok(LowerStep(state: lower_with_mir(current, result.store), id: result.id))
    }
    if checked.kind == 3 || checked.kind == 4 {
        let root_local = __s0_buffer_get(LocalRec, store.locals, checked.root - 1)
        let root_type = __s0_buffer_get(CheckedTypeRec, store.types, root_local.checked_type - 1)
        if root_type.kind != 8 || root_type.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let loaded = try lower_add_result(d, current, function, block, root_local.checked_type, source_state, store)
        let load = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, root.id, 0, 0, 0, 0, "")
        let index = try lower_expression(d, source_state, spans, store, load.state, owner, function, block, checked.index, environment, panic_block)
        let elem_checked = __s0_buffer_get(U64, store.type_args, root_type.first_arg - 1)
        let elem = try lower_type(d, source_state, store, index.state, elem_checked)
        let empty = try __s0_buffer_new(U64, d)
        let ref_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty, 0)
        let result = try mir_add_value(d, ref_type.store, function, try lower_decimal_name(d, "v", __s0_buffer_len(MirValueRec, ref_type.store.values) + 1), ref_type.type_id, mir_value_def_instruction(), block, lower_instruction_ordinal(ref_type.store, function, block) + 1)
        let indexed = try lower_add_instr(d, lower_with_mir(elem.state, result.store), function, block, mir_op_slice_index_checked(), result.id, 0, 0, loaded.id, index.id, panic_block, "")
        let deref = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: result.id))
        current = lower_with_mir(indexed.state, deref.store)
        if checked.kind == 3 { return Ok(LowerStep(state: current, id: deref.id)) }
        if checked.field == 0 || checked.field > __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let field = __s0_buffer_get(DeclTypeUseRec, store.uses, checked.field - 1)
        let named = try mir_append_name(d, current.mir, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
        let projected = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: deref.id, field_start: named.start, field_end: named.end, deref_value: 0))
        return Ok(LowerStep(state: lower_with_mir(current, projected.store), id: projected.id))
    }
    return Ok(LowerStep(state: lower_invalid(current), id: 0))
}

fn lower_block_statements(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, checked_block: U64, panic_block: U64) -> Result(LowerFlowStep, __s0_Error) {
    if checked_block == 0 || checked_block > __s0_buffer_len(CheckedBlockRec, store.control.blocks) { return Ok(LowerFlowStep(state: lower_invalid(state), block: block, terminated: true)) }
    let body = __s0_buffer_get(CheckedBlockRec, store.control.blocks, checked_block - 1)
    if body.owner != owner { return Ok(LowerFlowStep(state: lower_invalid(state), block: block, terminated: true)) }
    let flow = try lower_statement_chain(d, source_state, spans, store, state, owner, function, block, body.statements, panic_block)
    if flow.terminated { return Ok(flow) }
    let exit_environment = lower_chain_environment(store, owner, body.statements, body.environment)
    let cleaned = try lower_cleanup_exits(d, source_state, store, flow.state, owner, function, flow.block, exit_environment, body.environment, 1)
    return Ok(LowerFlowStep(state: cleaned, block: flow.block, terminated: false))
}

fn lower_statement_chain(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, link_id: U64, panic_block: U64) -> Result(LowerFlowStep, __s0_Error) {
    if link_id == 0 { return Ok(LowerFlowStep(state: state, block: block, terminated: false)) }
    if link_id > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return Ok(LowerFlowStep(state: lower_invalid(state), block: block, terminated: true)) }
    let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link_id - 1)
    let prior = try lower_statement_chain(d, source_state, spans, store, state, owner, function, block, link.next, panic_block)
    var current = prior.state
    var active = prior.block
    if prior.terminated { return Ok(prior) }
    if !current.valid || link.statement == 0 || link.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
    let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, link.statement - 1)
    if statement.owner != owner { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
    if statement.kind == 1 || statement.kind == 2 {
        let value = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_block)
        active = lower_open_block(value.state.mir, function, active)
        current = try lower_store_binding(d, value.state, function, active, statement.binding, value.id)
        return Ok(LowerFlowStep(state: current, block: active, terminated: false))
    }
    if statement.kind == 3 {
        let place = try lower_checked_place(d, source_state, spans, store, current, owner, function, active, statement.place, statement.environment, panic_block)
        let value = try lower_expression(d, source_state, spans, store, place.state, owner, function, active, statement.expression, statement.environment, panic_block)
        let instr = try lower_add_instr(d, value.state, function, active, mir_op_store(), 0, place.id, 0, value.id, 0, 0, "")
        return Ok(LowerFlowStep(state: instr.state, block: active, terminated: false))
    }
    if statement.kind == 4 {
        var value: U64 = 0
        if statement.expression != 0 {
            let lowered = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_block)
            current = lowered.state
            value = lowered.id
            active = lower_open_block(current.mir, function, active)
        }
        current = try lower_cleanup_exits(d, source_state, store, current, owner, function, active, statement.environment, 0, 2)
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: active, kind: mir_term_return(), value: value, target: 0, then_block: 0, else_block: 0))
        return Ok(LowerFlowStep(state: lower_with_mir(current, term.store), block: active, terminated: true))
    }
    if statement.kind == 5 {
        let lowered = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_block)
        active = lower_open_block(lowered.state.mir, function, active)
        return Ok(LowerFlowStep(state: lowered.state, block: active, terminated: false))
    }
    if statement.kind == 6 {
        return lower_block_statements(d, source_state, spans, store, current, owner, function, active, statement.body, panic_block)
    }
    if statement.kind == 7 {
        let condition = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_block)
        active = lower_open_block(condition.state.mir, function, active)
        let then_block = try lower_add_block(d, condition.state, function, "bb_then")
        let else_block = try lower_add_block(d, then_block.state, function, "bb_else")
        let join = try lower_add_block(d, else_block.state, function, "bb_join")
        current = try lower_branch(d, join.state, function, active, condition.id, then_block.id, else_block.id)
        let then_flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, then_block.id, statement.body, panic_block)
        current = then_flow.state
        if !then_flow.terminated { current = try lower_jump(d, current, function, then_flow.block, join.id) }
        var else_flow = LowerFlowStep(state: current, block: else_block.id, terminated: false)
        if statement.alternative != 0 { else_flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, else_block.id, statement.alternative, panic_block) }
        current = else_flow.state
        if !else_flow.terminated { current = try lower_jump(d, current, function, else_flow.block, join.id) }
        if then_flow.terminated && else_flow.terminated {
            let unreachable = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: join.id, kind: mir_term_unreachable(), value: 0, target: 0, then_block: 0, else_block: 0))
            return Ok(LowerFlowStep(state: lower_with_mir(current, unreachable.store), block: join.id, terminated: true))
        }
        return Ok(LowerFlowStep(state: current, block: join.id, terminated: false))
    }
    if statement.kind == 8 {
        let head = try lower_add_block(d, current, function, "bb_head")
        let body = try lower_add_block(d, head.state, function, "bb_body")
        let join = try lower_add_block(d, body.state, function, "bb_join")
        current = try lower_jump(d, join.state, function, active, head.id)
        let condition = try lower_expression(d, source_state, spans, store, current, owner, function, head.id, statement.expression, statement.environment, panic_block)
        let condition_block = lower_open_block(condition.state.mir, function, head.id)
        current = try lower_branch(d, condition.state, function, condition_block, condition.id, body.id, join.id)
        let body_flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, body.id, statement.body, panic_block)
        current = body_flow.state
        if !body_flow.terminated { current = try lower_jump(d, current, function, body_flow.block, head.id) }
        return Ok(LowerFlowStep(state: current, block: join.id, terminated: false))
    }
    if statement.kind == 9 {
        let sequence = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_block)
        let sequence_expression = __s0_buffer_get(CheckedExprRec, store.expressions, statement.expression - 1)
        let sequence_type = __s0_buffer_get(CheckedTypeRec, store.types, sequence_expression.checked_type - 1)
        if sequence_type.kind != 8 || sequence_type.arg_count != 1 { return Ok(LowerFlowStep(state: lower_invalid(sequence.state), block: active, terminated: true)) }
        // slice.len always returns canonical U64 (checked type 9 in the sealed primitive prefix).
        let length_value = try lower_add_result(d, sequence.state, function, active, 9, source_state, store)
        let length_instr = try lower_add_instr(d, length_value.state, function, active, mir_op_slice_len(), length_value.id, 0, 0, sequence.id, 0, 0, "")
        let zero_value = try lower_int_value(d, source_state, store, length_instr.state, function, active, 0, link.statement)
        let head = try lower_add_block(d, zero_value.state, function, "bb_for_head")
        let body = try lower_add_block(d, head.state, function, "bb_for_body")
        let join = try lower_add_block(d, body.state, function, "bb_for_join")
        let index_param = try mir_add_block_param(d, join.state.mir, function, head.id, 0, "index", mir_type_u64())
        let lowered_sequence_type = try lower_type(d, source_state, store, lower_with_mir(join.state, index_param.store), sequence_expression.checked_type)
        let sequence_param = try mir_add_block_param(d, lowered_sequence_type.state.mir, function, head.id, 1, "sequence", lowered_sequence_type.id)
        current = try lower_jump_two(d, lower_with_mir(lowered_sequence_type.state, sequence_param.store), function, active, head.id, zero_value.id, sequence.id)
        let compared = try lower_add_result(d, current, function, head.id, 1, source_state, store)
        let compare = try lower_add_instr(d, compared.state, function, head.id, mir_op_int_lt(), compared.id, 0, 0, index_param.id, length_value.id, 0, "")
        current = try lower_branch(d, compare.state, function, head.id, compared.id, body.id, join.id)
        let elem_checked = __s0_buffer_get(U64, store.type_args, sequence_type.first_arg - 1)
        let elem = try lower_type(d, source_state, store, current, elem_checked)
        let empty = try __s0_buffer_new(U64, d)
        let ref_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty, 0)
        let ref_value = try mir_add_value(d, ref_type.store, function, "for_ref", ref_type.type_id, mir_value_def_instruction(), body.id, lower_instruction_ordinal(ref_type.store, function, body.id) + 1)
        let indexed = try lower_add_instr(d, lower_with_mir(elem.state, ref_value.store), function, body.id, mir_op_slice_index_checked(), ref_value.id, 0, 0, sequence_param.id, index_param.id, panic_block, "")
        let deref = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: ref_value.id))
        let element_value = try lower_add_result(d, lower_with_mir(indexed.state, deref.store), function, body.id, elem_checked, source_state, store)
        let loaded = try lower_add_instr(d, element_value.state, function, body.id, mir_op_load(), element_value.id, deref.id, 0, 0, 0, 0, "")
        current = try lower_store_binding(d, loaded.state, function, body.id, statement.binding, element_value.id)
        let body_flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, body.id, statement.body, panic_block)
        current = body_flow.state
        if !body_flow.terminated {
            let one = try lower_int_value(d, source_state, store, current, function, body_flow.block, 1, link.statement + 1)
            let next = try lower_add_result(d, one.state, function, body_flow.block, 9, source_state, store)
            let added = try lower_add_instr(d, next.state, function, body_flow.block, mir_op_int_add_checked(), next.id, 0, 0, index_param.id, one.id, panic_block, "")
            current = try lower_jump_two(d, added.state, function, lower_open_block(added.state.mir, function, body_flow.block), head.id, next.id, sequence_param.id)
        }
        return Ok(LowerFlowStep(state: current, block: join.id, terminated: false))
    }
    if statement.kind == 10 {
        let value = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_block)
        current = try lower_store_binding(d, value.state, function, active, statement.binding, value.id)
        return Ok(LowerFlowStep(state: current, block: active, terminated: false))
    }
    return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true))
}

fn lower_function(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64) -> Result(LowerState, __s0_Error) {
    let function = lower_owner_lookup(state.owners, owner)
    if function == 0 { return Ok(lower_invalid(state)) }
    var current = state
    var param_ordinal: U64 = 0
    var local_ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(LocalRec, store.locals) {
        let local = __s0_buffer_get(LocalRec, store.locals, at)
        if local.owner == owner {
            let typ = try lower_type(d, source_state, store, current, local.checked_type)
            current = typ.state
            let name = try lower_source_word(d, source_state, local.source, local.name_start, local.name_end)
            if local.kind == 1 {
                let parameter = try mir_add_function_param(d, current.mir, function, param_ordinal, name, typ.id)
                current = lower_with_mir(current, parameter.store)
                let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: at + 1, mir_id: parameter.id, parameter: 1))
                current = lower_with_bindings(current, bindings)
                param_ordinal = param_ordinal + 1
            } else {
                let slot = try mir_add_local(d, current.mir, function, local_ordinal, name, typ.id)
                current = lower_with_mir(current, slot.store)
                let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: at + 1, mir_id: slot.id, parameter: 0))
                current = lower_with_bindings(current, bindings)
                local_ordinal = local_ordinal + 1
            }
        }
        at = at + 1
    }
    let entry = try mir_add_block(d, current.mir, function, 0, "bb0")
    current = lower_with_mir(current, entry.store)
    let panic = try mir_add_block(d, current.mir, function, 1, "bb_panic")
    current = lower_with_mir(current, panic.store)
    var root: U64 = 0
    at = 0
    while at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
        let candidate = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if candidate.owner == owner {
            var referenced = false
            var statement_at: U64 = 0
            while statement_at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_at)
                if statement.owner == owner && (statement.body == at + 1 || statement.alternative == at + 1) { referenced = true }
                statement_at = statement_at + 1
            }
            if !referenced {
                if root != 0 { return Ok(lower_invalid(current)) }
                root = at + 1
            }
        }
        at = at + 1
    }
    if root == 0 { return Ok(lower_invalid(current)) }
    let flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, entry.id, root, panic.id)
    current = flow.state
    if !current.valid { return Ok(current) }
    if !flow.terminated {
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: flow.block, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, term.store)
    }
    let panic_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: panic.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(current, panic_term.store))
}

fn lower_functions(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var owner: U64 = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if (symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13 {
            current = try lower_function(d, source_state, spans, store, current, owner)
            if !current.valid { return Ok(current) }
        }
        owner = owner + 1
    }
    return Ok(current)
}

fn lower_environment_valid(store: CheckStore, owner: U64, environment: U64) -> Bool {
    var remaining = __s0_buffer_len(EnvironmentRec, store.environments) + 1
    var current = environment
    while current != 0 {
        if remaining == 0 || current > __s0_buffer_len(EnvironmentRec, store.environments) { return false }
        let item = __s0_buffer_get(EnvironmentRec, store.environments, current - 1)
        if item.owner != owner || item.parent >= current { return false }
        if item.binding != 0 {
            if item.binding > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.binding - 1).owner != owner { return false }
        }
        current = item.parent
        remaining = remaining - 1
    }
    return true
}

fn lower_model_valid(store: CheckStore, spans: __s0_Buffer(CheckedSpanRec)) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let item = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_type_concrete(store, item.checked_type) { return false }
        if item.kind == 18 || item.kind == 0 || item.kind > 21 { return false }
        if item.left > at || item.right > at { return false }
        if item.child_count != 0 && (item.first_child == 0 || item.first_child - 1 + item.child_count > __s0_buffer_len(CheckedExprChildRec, store.expression_children)) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
        let item = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at)
        if item.statement == 0 || item.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) || item.next > at { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let item = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || !lower_environment_valid(store, item.owner, item.environment) { return false }
        if item.expression > __s0_buffer_len(CheckedExprRec, store.expressions) || item.place > __s0_buffer_len(CheckedPlaceRec, store.control.places) || item.body > __s0_buffer_len(CheckedBlockRec, store.control.blocks) || item.alternative > __s0_buffer_len(CheckedBlockRec, store.control.blocks) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
        let item = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || !lower_environment_valid(store, item.owner, item.environment) || item.statements > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchRec, store.control.matches) {
        let item = __s0_buffer_get(CheckedMatchRec, store.control.matches, at)
        if item.owner == 0 || item.scrutinee == 0 || item.scrutinee > __s0_buffer_len(CheckedExprRec, store.expressions) || item.first_arm == 0 || item.first_arm - 1 + item.arm_count > __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) { return false }
        var ordinal: U64 = 0
        while ordinal < item.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, item.first_arm - 1 + ordinal)
            if arm.owner != item.owner || arm.checked_match != at + 1 { return false }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) {
        let item = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, at)
        if item.owner == 0 || item.checked_match == 0 || item.checked_match > __s0_buffer_len(CheckedMatchRec, store.control.matches) || !lower_environment_valid(store, item.owner, item.environment) || item.body == 0 || item.body > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
        if item.binding != 0 && (item.binding > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.binding - 1).owner != item.owner) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTryRec, store.control.tries) {
        let item = __s0_buffer_get(CheckedTryRec, store.control.tries, at)
        if item.owner == 0 || item.expression == 0 || item.expression > __s0_buffer_len(CheckedExprRec, store.expressions) || !lower_type_concrete(store, item.result_type) || !lower_type_concrete(store, item.ok_type) || !lower_type_concrete(store, item.error_type) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let item = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, at)
        if item.owner == 0 || !lower_environment_valid(store, item.owner, item.environment) || item.binding == 0 || item.binding > __s0_buffer_len(LocalRec, store.locals) || item.callback == 0 || item.callback > __s0_buffer_len(SymbolRec, store.symbols) { return false }
        let binding = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
        if binding.owner != item.owner || item.initializer == 0 || item.initializer > __s0_buffer_len(CheckedExprRec, store.expressions) || item.normal_exit != 1 || item.return_exit != 1 || item.try_exit != 1 { return false }
        var environment_at: U64 = 0
        var found = false
        while environment_at < __s0_buffer_len(EnvironmentRec, store.environments) {
            let environment = __s0_buffer_get(EnvironmentRec, store.environments, environment_at)
            if environment.owner == item.owner && environment.parent == item.environment && environment.binding == item.binding { found = true }
            environment_at = environment_at + 1
        }
        if !found { return false }
        at = at + 1
    }
    return true
}

fn lower_checked(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore) -> Result(LowerResult, __s0_Error) {
    if __s0_buffer_len(CheckDiagRec, store.diagnostics) != 0 { return Ok(LowerBad) }
    if !lower_model_valid(store, spans) { return Ok(LowerBad) }
    let mir = try mir_store_new(d)
    let types = try __s0_buffer_new(LowerTypeMapRec, d)
    let owners = try __s0_buffer_new(LowerOwnerMapRec, d)
    let imports = try __s0_buffer_new(LowerOwnerMapRec, d)
    let bindings = try __s0_buffer_new(LowerBindingMapRec, d)
    let values = try __s0_buffer_new(LowerValueMapRec, d)
    var state = LowerState(mir: mir, types: types, owners: owners, imports: imports, bindings: bindings, values: values, valid: true)
    state = try lower_declarations(d, source_state, store, state)
    if !state.valid { return Ok(LowerBad) }
    state = try lower_functions(d, source_state, spans, store, state)
    if !state.valid { return Ok(LowerBad) }
    return Ok(LowerGood(state.mir))
}
