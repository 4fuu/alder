// Deterministic lowering from the sealed checked model to independent MIR 3.
// This layer consumes semantic IDs and source spans only. Syntax records are
// used solely to recover literal spans; their kinds and child graph are never
// inspected. A malformed or unresolved checked model is an internal failure.

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
    var at: U64 = 0
    while at < __s0_buffer_len(LowerBindingMapRec, state.bindings) {
        let item = __s0_buffer_get(LowerBindingMapRec, state.bindings, at)
        if item.binding == binding { return item }
        at = at + 1
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

fn lower_add_result(d: Domain, state: LowerState, function: U64, block: U64, checked_type: U64, source_state: State, store: CheckStore) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    if !typ.state.valid { return Ok(typ) }
    let name = try lower_decimal_name(d, "v", __s0_buffer_len(MirValueRec, typ.state.mir.values) + 1)
    let value = try mir_add_value(d, typ.state.mir, function, name, typ.id, mir_value_def_instruction(), block, lower_instruction_ordinal(typ.state.mir, function, block) + 1)
    return Ok(LowerStep(state: lower_with_mir(typ.state, value.store), id: value.id))
}

fn lower_add_instr(d: Domain, state: LowerState, function: U64, block: U64, op: U64, result: U64, place: U64, type_op: U64, a: U64, b: U64, target: U64, name: String) -> Result(LowerStep, __s0_Error) {
    var named = MirNameStep(store: state.mir, start: 0, end: 0)
    if len(name) != 0 { named = try mir_append_name(d, state.mir, name) }
    let rec = MirInstrRec(function: function, block: block, ordinal: lower_instruction_ordinal(named.store, function, block), op: op, result: result, place: place, type_op: type_op, a: a, b: b, c: 0, target: target, name_start: named.start, name_end: named.end)
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

fn lower_parse_i64(source_state: State, parse: ParseStore, expression: CheckedExprRec) -> I64 {
    if expression.syntax == 0 || expression.syntax > __s0_buffer_len(SyntaxRec, parse.nodes) { return 0 }
    let span = __s0_buffer_get(SyntaxRec, parse.nodes, expression.syntax - 1)
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

fn lower_expression(d: Domain, source_state: State, parse: ParseStore, store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
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
            int_value = lower_parse_i64(source_state, parse, expression)
        }
        if expression.kind == 4 {
            kind = mir_const_string()
            if expression.syntax == 0 || expression.syntax > __s0_buffer_len(SyntaxRec, parse.nodes) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
            let span = __s0_buffer_get(SyntaxRec, parse.nodes, expression.syntax - 1)
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
    if expression.kind == 6 || expression.kind == 7 {
        if expression.child_count == 0 || expression.first_child == 0 || expression.first_child - 1 + expression.child_count > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let left_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let left = try lower_expression(d, source_state, parse, store, state, owner, function, block, left_id, panic_block)
        var right = LowerStep(state: left.state, id: 0)
        if expression.kind == 7 {
            if expression.child_count != 2 { return Ok(LowerStep(state: lower_invalid(left.state), id: 0)) }
            let right_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
            right = try lower_expression(d, source_state, parse, store, left.state, owner, function, block, right_id, panic_block)
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
            let child = try lower_expression(d, source_state, parse, store, current, owner, function, block, child_id, panic_block)
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
            let child = try lower_expression(d, source_state, parse, store, current, owner, function, block, child_id, panic_block)
            current = child.state
            payload = child.id
        }
        let typ = try lower_type(d, source_state, store, current, expression.checked_type)
        let result = try lower_add_result(d, typ.state, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_enum_construct(), result.id, 0, typ.id, payload, 0, 0, name)
        return Ok(LowerStep(state: instr.state, id: result.id))
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

fn lower_statement_chain(d: Domain, source_state: State, parse: ParseStore, store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, link_id: U64, panic_block: U64) -> Result(LowerState, __s0_Error) {
    if link_id == 0 { return Ok(state) }
    if link_id > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return Ok(lower_invalid(state)) }
    let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link_id - 1)
    var current = try lower_statement_chain(d, source_state, parse, store, state, owner, function, block, link.next, panic_block)
    if !current.valid || link.statement == 0 || link.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) { return Ok(lower_invalid(current)) }
    let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, link.statement - 1)
    if statement.owner != owner { return Ok(lower_invalid(current)) }
    if statement.kind == 1 || statement.kind == 2 {
        let value = try lower_expression(d, source_state, parse, store, current, owner, function, block, statement.expression, panic_block)
        return lower_store_binding(d, value.state, function, block, statement.binding, value.id)
    }
    if statement.kind == 4 {
        var value: U64 = 0
        if statement.expression != 0 {
            let lowered = try lower_expression(d, source_state, parse, store, current, owner, function, block, statement.expression, panic_block)
            current = lowered.state
            value = lowered.id
        }
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: block, kind: mir_term_return(), value: value, target: 0, then_block: 0, else_block: 0))
        return Ok(lower_with_mir(current, term.store))
    }
    if statement.kind == 5 {
        let lowered = try lower_expression(d, source_state, parse, store, current, owner, function, block, statement.expression, panic_block)
        return Ok(lowered.state)
    }
    return Ok(lower_invalid(current))
}

fn lower_function(d: Domain, source_state: State, parse: ParseStore, store: CheckStore, state: LowerState, owner: U64) -> Result(LowerState, __s0_Error) {
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
            if root != 0 { return Ok(lower_invalid(current)) }
            root = at + 1
        }
        at = at + 1
    }
    if root == 0 { return Ok(lower_invalid(current)) }
    let root_block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, root - 1)
    current = try lower_statement_chain(d, source_state, parse, store, current, owner, function, entry.id, root_block.statements, panic.id)
    if !current.valid { return Ok(current) }
    var has_entry_term = false
    at = 0
    while at < __s0_buffer_len(MirTermRec, current.mir.terminators) {
        let term = __s0_buffer_get(MirTermRec, current.mir.terminators, at)
        if term.function == function && term.block == entry.id { has_entry_term = true }
        at = at + 1
    }
    if !has_entry_term {
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, term.store)
    }
    let panic_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: panic.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(current, panic_term.store))
}

fn lower_functions(d: Domain, source_state: State, parse: ParseStore, store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var owner: U64 = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if (symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13 {
            current = try lower_function(d, source_state, parse, store, current, owner)
            if !current.valid { return Ok(current) }
        }
        owner = owner + 1
    }
    return Ok(current)
}

fn lower_checked(d: Domain, source_state: State, parse: ParseStore, store: CheckStore) -> Result(LowerResult, __s0_Error) {
    if __s0_buffer_len(CheckDiagRec, store.diagnostics) != 0 { return Ok(LowerBad) }
    let mir = try mir_store_new(d)
    let types = try __s0_buffer_new(LowerTypeMapRec, d)
    let owners = try __s0_buffer_new(LowerOwnerMapRec, d)
    let imports = try __s0_buffer_new(LowerOwnerMapRec, d)
    let bindings = try __s0_buffer_new(LowerBindingMapRec, d)
    let values = try __s0_buffer_new(LowerValueMapRec, d)
    var state = LowerState(mir: mir, types: types, owners: owners, imports: imports, bindings: bindings, values: values, valid: true)
    state = try lower_declarations(d, source_state, store, state)
    if !state.valid { return Ok(LowerBad) }
    state = try lower_functions(d, source_state, parse, store, state)
    if !state.valid { return Ok(LowerBad) }
    return Ok(LowerGood(state.mir))
}
