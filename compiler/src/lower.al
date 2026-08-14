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

type LowerBridgeRec {
    checked_type: U64
    make_id: U64
    len_id: U64
    append_id: U64
    get_id: U64
    slice_id: U64
    set_id: U64
    remove_id: U64
}

type LowerState {
    mir: MirStore
    types: __s0_Buffer(LowerTypeMapRec)
    owners: __s0_Buffer(LowerOwnerMapRec)
    imports: __s0_Buffer(LowerOwnerMapRec)
    bindings: __s0_Buffer(LowerBindingMapRec)
    values: __s0_Buffer(LowerValueMapRec)
    bridges: __s0_Buffer(LowerBridgeRec)
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
    return LowerState(mir: mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, bridges: state.bridges, valid: state.valid)
}

fn lower_invalid(state: LowerState) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, bridges: state.bridges, valid: false)
}

fn lower_with_types(state: LowerState, types: __s0_Buffer(LowerTypeMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, bridges: state.bridges, valid: state.valid)
}

fn lower_with_owners(state: LowerState, owners: __s0_Buffer(LowerOwnerMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: owners, imports: state.imports, bindings: state.bindings, values: state.values, bridges: state.bridges, valid: state.valid)
}

fn lower_with_imports(state: LowerState, imports: __s0_Buffer(LowerOwnerMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: imports, bindings: state.bindings, values: state.values, bridges: state.bridges, valid: state.valid)
}

fn lower_with_bindings(state: LowerState, bindings: __s0_Buffer(LowerBindingMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: bindings, values: state.values, bridges: state.bridges, valid: state.valid)
}

fn lower_with_values(state: LowerState, values: __s0_Buffer(LowerValueMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: values, bridges: state.bridges, valid: state.valid)
}

fn lower_with_bridges(state: LowerState, bridges: __s0_Buffer(LowerBridgeRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, imports: state.imports, bindings: state.bindings, values: state.values, bridges: bridges, valid: state.valid)
}

fn lower_bridge_lookup(state: LowerState, checked_type: U64) -> LowerBridgeRec {
    var at: U64 = 0
    while at < __s0_buffer_len(LowerBridgeRec, state.bridges) {
        let item = __s0_buffer_get(LowerBridgeRec, state.bridges, at)
        if item.checked_type == checked_type { return item }
        at = at + 1
    }
    return LowerBridgeRec(checked_type: 0, make_id: 0, len_id: 0, append_id: 0, get_id: 0, slice_id: 0, set_id: 0, remove_id: 0)
}

fn lower_cleanup_scope_lookup(state: LowerState, binding: U64) -> U64 {
    var at = __s0_buffer_len(LowerValueMapRec, state.values)
    while at > 0 {
        let item = __s0_buffer_get(LowerValueMapRec, state.values, at - 1)
        if item.expression == binding { return item.value }
        at = at - 1
    }
    return 0
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
    if checked.kind == 13 {
        if checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let elem = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        let empty = try __s0_buffer_new(U64, d)
        let data = try mir_intern_type(d, elem.state.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty, 0)
        let named = try mir_add_named_type(d, data.store, mir_type_kind_aggregate(), try lower_decimal_name(d, "__s0_Buffer_", checked_type))
        var next = lower_with_mir(elem.state, named.store)
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), named.type_id, 0, "data", data.type_id))
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), named.type_id, 1, "len", mir_type_u64()))
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, next.types, LowerTypeMapRec(checked_type: checked_type, mir_type: named.type_id))
        return Ok(LowerStep(state: lower_with_types(next, mapped), id: named.type_id))
    }
    if checked.kind == 11 {
        if checked.arg_count != 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let key = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        let value = try lower_type(d, source_state, store, key.state, __s0_buffer_get(U64, store.type_args, checked.first_arg))
        let entry = try mir_add_named_type(d, value.state.mir, mir_type_kind_aggregate(), try lower_decimal_name(d, "MapEntry_", checked_type))
        var next = lower_with_mir(value.state, entry.store)
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), entry.type_id, 0, "state", mir_type_u8()))
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), entry.type_id, 1, "hash", mir_type_u64()))
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), entry.type_id, 2, "key", key.id))
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), entry.type_id, 3, "value", value.id))
        let empty = try __s0_buffer_new(U64, d)
        let slots = try mir_intern_type(d, next.mir, mir_type_kind_safe_mut(), entry.type_id, 0, 0, empty, 0)
        let named = try mir_add_named_type(d, slots.store, mir_type_kind_aggregate(), try lower_decimal_name(d, "Map_", checked_type))
        next = lower_with_mir(next, named.store)
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), named.type_id, 0, "slots", slots.type_id))
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, next.types, LowerTypeMapRec(checked_type: checked_type, mir_type: named.type_id))
        return Ok(LowerStep(state: lower_with_types(next, mapped), id: named.type_id))
    }
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

fn lower_bound_checked_type(store: CheckStore, checked_type: U64, declaration: U64, application: U64) -> U64 {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind != 6 { return checked_type }
    let applied = __s0_buffer_get(CheckedTypeRec, store.types, application - 1)
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let parameter = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if parameter.owner == declaration {
            if at + 1 == checked.target { return __s0_buffer_get(U64, store.type_args, applied.first_arg - 1 + ordinal) }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return 0
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

fn lower_add_helper_function(d: Domain, state: LowerState, name: String, result_type: U64, first_type: U64, second_type: U64, third_type: U64) -> Result(LowerStep, __s0_Error) {
    let function = try mir_add_function(d, state.mir, name, result_type)
    var current = lower_with_mir(state, function.store)
    if first_type != 0 { current = lower_with_mir(current, (try mir_add_function_param(d, current.mir, function.id, 0, "a", first_type)).store) }
    if second_type != 0 { current = lower_with_mir(current, (try mir_add_function_param(d, current.mir, function.id, 1, "b", second_type)).store) }
    if third_type != 0 { current = lower_with_mir(current, (try mir_add_function_param(d, current.mir, function.id, 2, "c", third_type)).store) }
    return Ok(LowerStep(state: current, id: function.id))
}

fn lower_bridge_type_used(store: CheckStore, checked_type: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if expression.kind == 18 && expression.annotation != 0 {
            let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
            var candidate: U64 = 0
            if annotation.builtin == 8 { candidate = expression.checked_type }
            if annotation.builtin == 9 {
                let result = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
                candidate = __s0_buffer_get(U64, store.type_args, result.first_arg - 1)
            }
            if annotation.builtin == 10 || annotation.builtin == 12 || annotation.builtin == 13 || annotation.builtin == 14 || annotation.builtin == 15 || annotation.builtin == 16 { candidate = lower_builtin_child_type(store, expression, 0) }
            if annotation.builtin == 11 { candidate = lower_builtin_child_type(store, expression, 1) }
            if candidate == checked_type { return true }
        }
        at = at + 1
    }
    return false
}

fn lower_bridge_declarations(d: Domain, source_state: State, store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var checked_id: U64 = 1
    while checked_id <= __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_id - 1)
        if (checked.kind == 11 || checked.kind == 13) && lower_bridge_type_used(store, checked_id) && lower_bridge_lookup(current, checked_id).checked_type == 0 {
            let lowered = try lower_type(d, source_state, store, current, checked_id)
            current = lowered.state
            var bridge = LowerBridgeRec(checked_type: checked_id, make_id: 0, len_id: 0, append_id: 0, get_id: 0, slice_id: 0, set_id: 0, remove_id: 0)
            if checked.kind == 13 {
                let element_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
                let element = try lower_type(d, source_state, store, current, element_checked)
                current = element.state
                let error_checked = lower_checked_type_kind(store, 5, 0)
                if error_checked == 0 { return Ok(lower_invalid(current)) }
                let error_type = try lower_type(d, source_state, store, current, error_checked)
                current = error_type.state
                let result_checked = lower_result_type_for(store, checked_id, error_checked)
                let slice_checked = lower_slice_type_for(store, element_checked)
                if result_checked == 0 || slice_checked == 0 { return Ok(lower_invalid(current)) }
                let result_type = try lower_type(d, source_state, store, current, result_checked)
                let slice_type = try lower_type(d, source_state, store, result_type.state, slice_checked)
                current = slice_type.state
                let domain_type = try lower_domain_mir_type(d, current)
                current = domain_type.state
                let suffix = try lower_decimal_name(d, "buffer_new_", checked_id)
                let make = try lower_add_helper_function(d, current, suffix, result_type.id, domain_type.id, 0, 0)
                let length = try lower_add_helper_function(d, make.state, try lower_decimal_name(d, "buffer_len_", checked_id), mir_type_u64(), lowered.id, 0, 0)
                let append = try lower_add_helper_function(d, length.state, try lower_decimal_name(d, "buffer_append_", checked_id), result_type.id, domain_type.id, lowered.id, element.id)
                let get = try lower_add_helper_function(d, append.state, try lower_decimal_name(d, "buffer_get_", checked_id), element.id, lowered.id, mir_type_u64(), 0)
                let sliced = try lower_add_helper_function(d, get.state, try lower_decimal_name(d, "buffer_slice_", checked_id), slice_type.id, lowered.id, 0, 0)
                current = sliced.state
                bridge = LowerBridgeRec(checked_type: checked_id, make_id: make.id, len_id: length.id, append_id: append.id, get_id: get.id, slice_id: sliced.id, set_id: 0, remove_id: 0)
            }
            if checked.kind == 11 {
                let key_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
                let value_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg)
                let key = try lower_type(d, source_state, store, current, key_checked)
                let value = try lower_type(d, source_state, store, key.state, value_checked)
                current = value.state
                let empty = try __s0_buffer_new(U64, d)
                let option = try mir_intern_type(d, current.mir, mir_type_kind_option(), value.id, 0, 0, empty, 0)
                let domain = try lower_domain_mir_type(d, lower_with_mir(current, option.store))
                let hash = try lower_add_helper_function(d, domain.state, try lower_decimal_name(d, "map_hash_", checked_id), mir_type_u64(), key.id, 0, 0)
                let equal = try lower_add_helper_function(d, hash.state, try lower_decimal_name(d, "map_eq_", checked_id), mir_type_bool(), key.id, key.id, 0)
                let make = try lower_add_helper_function(d, equal.state, try lower_decimal_name(d, "map_make_", checked_id), lowered.id, domain.id, 0, 0)
                let get = try lower_add_helper_function(d, make.state, try lower_decimal_name(d, "map_get_", checked_id), option.type_id, lowered.id, key.id, 0)
                let set = try lower_add_helper_function(d, get.state, try lower_decimal_name(d, "map_set_", checked_id), mir_type_bool(), lowered.id, key.id, value.id)
                let removed = try lower_add_helper_function(d, set.state, try lower_decimal_name(d, "map_remove_", checked_id), mir_type_bool(), lowered.id, key.id, 0)
                current = removed.state
                bridge = LowerBridgeRec(checked_type: checked_id, make_id: make.id, len_id: hash.id, append_id: equal.id, get_id: get.id, slice_id: 0, set_id: set.id, remove_id: removed.id)
            }
            let bridges = try __s0_buffer_append(LowerBridgeRec, d, current.bridges, bridge)
            current = lower_with_bridges(current, bridges)
        }
        checked_id = checked_id + 1
    }
    return Ok(current)
}

fn lower_checked_type_kind(store: CheckStore, kind: U64, target: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let item = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if item.kind == kind && item.target == target && item.arg_count == 0 { return at + 1 }
        at = at + 1
    }
    return 0
}

fn lower_result_type_for(store: CheckStore, ok_type: U64, error_type: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let item = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if item.kind == 10 && item.arg_count == 2 && __s0_buffer_get(U64, store.type_args, item.first_arg - 1) == ok_type && __s0_buffer_get(U64, store.type_args, item.first_arg) == error_type { return at + 1 }
        at = at + 1
    }
    return 0
}

fn lower_slice_type_for(store: CheckStore, element_type: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let item = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if item.kind == 8 && item.arg_count == 1 && __s0_buffer_get(U64, store.type_args, item.first_arg - 1) == element_type { return at + 1 }
        at = at + 1
    }
    return 0
}

fn lower_domain_mir_type(d: Domain, state: LowerState) -> Result(LowerStep, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    let typ = try mir_intern_type(d, state.mir, mir_type_kind_domain_handle(), 0, 0, 0, empty, 0)
    return Ok(LowerStep(state: lower_with_mir(state, typ.store), id: typ.type_id))
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
    return lower_bridge_declarations(d, source_state, store, current)
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

fn lower_local_count(mir: MirStore, function: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirLocalRec, mir.locals) {
        if __s0_buffer_get(MirLocalRec, mir.locals, at).function == function { count = count + 1 }
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

fn lower_result_name_taken(mir: MirStore, function: U64, name: String) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(MirValueRec, mir.values) {
        let value = __s0_buffer_get(MirValueRec, mir.values, at)
        if value.function == function && value.name_end - value.name_start == len(name) {
            var byte: U64 = 0
            var equal = true
            while byte < len(name) {
                if __s0_buffer_get(U8, mir.names, value.name_start + byte) != name[byte] { equal = false }
                byte = byte + 1
            }
            if equal { return true }
        }
        at = at + 1
    }
    return false
}

fn lower_result_name(d: Domain, mir: MirStore, function: U64, preferred: String) -> Result(String, __s0_Error) {
    if len(preferred) != 0 && !lower_result_name_taken(mir, function, preferred) { return Ok(preferred) }
    var suffix = __s0_buffer_len(MirValueRec, mir.values) + 1
    var name = try lower_decimal_name(d, "v", suffix)
    while lower_result_name_taken(mir, function, name) {
        suffix = suffix + 1
        name = try lower_decimal_name(d, "v", suffix)
    }
    return Ok(name)
}

fn lower_add_result(d: Domain, state: LowerState, function: U64, block: U64, checked_type: U64, source_state: State, store: CheckStore) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    if !typ.state.valid { return Ok(typ) }
    let active = lower_open_block(typ.state.mir, function, block)
    let name = try lower_result_name(d, typ.state.mir, function, "")
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

fn lower_add_instr_three(d: Domain, state: LowerState, function: U64, block: U64, op: U64, result: U64, type_op: U64, a: U64, b: U64, c: U64, target: U64) -> Result(LowerStep, __s0_Error) {
    let active = lower_open_block(state.mir, function, block)
    let rec = MirInstrRec(function: function, block: active, ordinal: lower_instruction_ordinal(state.mir, function, active), op: op, result: result, place: 0, type_op: type_op, a: a, b: b, c: c, target: target, name_start: 0, name_end: 0)
    let step = try mir_add_instruction(d, state.mir, rec)
    return Ok(LowerStep(state: lower_with_mir(state, step.store), id: step.id))
}

fn lower_add_typed_result(d: Domain, state: LowerState, function: U64, block: U64, type_id: U64) -> Result(LowerStep, __s0_Error) {
    let active = lower_open_block(state.mir, function, block)
    let value = try mir_add_value(d, state.mir, function, try lower_result_name(d, state.mir, function, ""), type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(state.mir, function, active) + 1)
    return Ok(LowerStep(state: lower_with_mir(state, value.store), id: value.id))
}

fn lower_helper_const(d: Domain, state: LowerState, function: U64, block: U64, type_id: U64, value: I64, suffix: U64) -> Result(LowerStep, __s0_Error) {
    let name = try lower_decimal_name(d, "bridge_const_", suffix)
    let constant = try mir_add_const(d, state.mir, name, type_id, mir_const_int(), 0, value, 0, "")
    let result = try lower_add_typed_result(d, lower_with_mir(state, constant.store), function, block, type_id)
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
    return Ok(LowerStep(state: instruction.state, id: result.id))
}

fn lower_helper_bool(d: Domain, state: LowerState, function: U64, block: U64, value: U64, suffix: U64) -> Result(LowerStep, __s0_Error) {
    let name = try lower_decimal_name(d, "bridge_bool_", suffix)
    let constant = try mir_add_const(d, state.mir, name, mir_type_bool(), mir_const_bool(), value, 0, 0, "")
    let result = try lower_add_typed_result(d, lower_with_mir(state, constant.store), function, block, mir_type_bool())
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
    return Ok(LowerStep(state: instruction.state, id: result.id))
}

fn lower_helper_local_place(d: Domain, state: LowerState, function: U64, ordinal: U64, name: String, type_id: U64) -> Result(LowerStep, __s0_Error) {
    let local = try mir_add_local(d, state.mir, function, ordinal, name, type_id)
    let place = try mir_add_place(d, local.store, MirPlaceRec(function: function, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    return Ok(LowerStep(state: lower_with_mir(state, place.store), id: place.id))
}

fn lower_helper_field_place(d: Domain, state: LowerState, function: U64, base: U64, name: String) -> Result(LowerStep, __s0_Error) {
    let named = try mir_append_name(d, state.mir, name)
    let place = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: base, field_start: named.start, field_end: named.end, deref_value: 0))
    return Ok(LowerStep(state: lower_with_mir(state, place.store), id: place.id))
}

fn lower_helper_deref_place(d: Domain, state: LowerState, function: U64, value: U64) -> Result(LowerStep, __s0_Error) {
    let place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: value))
    return Ok(LowerStep(state: lower_with_mir(state, place.store), id: place.id))
}

fn lower_helper_load(d: Domain, state: LowerState, function: U64, block: U64, place: U64, type_id: U64) -> Result(LowerStep, __s0_Error) {
    let result = try lower_add_typed_result(d, state, function, block, type_id)
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_load(), result.id, place, 0, 0, 0, 0, "")
    return Ok(LowerStep(state: instruction.state, id: result.id))
}

fn lower_helper_construct_two(d: Domain, state: LowerState, function: U64, block: U64, type_id: U64, first_name: String, first: U64, second_name: String, second: U64) -> Result(LowerStep, __s0_Error) {
    let result = try lower_add_typed_result(d, state, function, block, type_id)
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_aggregate_construct(), result.id, 0, type_id, 0, 0, 0, "")
    let first_operand = try lower_add_instr_operand(d, instruction.state, instruction.id, 0, first, mir_operand_aggregate_field(), first_name)
    let second_operand = try lower_add_instr_operand(d, first_operand, instruction.id, 1, second, mir_operand_aggregate_field(), second_name)
    return Ok(LowerStep(state: second_operand, id: result.id))
}

fn lower_helper_variant(d: Domain, state: LowerState, function: U64, block: U64, type_id: U64, name: String, payload: U64) -> Result(LowerStep, __s0_Error) {
    let result = try lower_add_typed_result(d, state, function, block, type_id)
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_enum_construct(), result.id, 0, type_id, payload, 0, 0, name)
    return Ok(LowerStep(state: instruction.state, id: result.id))
}

fn lower_helper_return(d: Domain, state: LowerState, function: U64, block: U64, value: U64) -> Result(LowerState, __s0_Error) {
    let term = try mir_add_terminator(d, state.mir, MirTermRec(function: function, block: block, kind: mir_term_return(), value: value, target: 0, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(state, term.store))
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
        let local = __s0_buffer_get(LocalRec, store.locals, expression.parameter_use - 1)
        let local_type = try lower_local_type(d, source_state, store, lower_with_mir(state, place.store), owner, expression.parameter_use, local)
        let result = try lower_add_typed_result(d, local_type.state, function, block, local_type.id)
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
        let ref_value = try mir_add_value(d, reference.store, function, try lower_result_name(d, reference.store, function, ""), reference.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(reference.store, function, active) + 1)
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
            let source_block = lower_open_block(left.state.mir, function, block)
            let right_block = try lower_add_block(d, left.state, function, "bb_short")
            let constant_block = try lower_add_block(d, right_block.state, function, "bb_short_const")
            let join = try lower_add_block(d, constant_block.state, function, "bb_short_join")
            let result_type = try lower_type(d, source_state, store, join.state, expression.checked_type)
            let param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, try lower_decimal_name(d, "__s0_short_", join.id), result_type.id)
            var current = lower_with_mir(result_type.state, param.store)
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
    if expression.kind == 18 {
        if expression.annotation == 0 || expression.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
        if annotation.kind != 5 || annotation.builtin == 0 || annotation.builtin > 16 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        var current = state
        var args = try __s0_buffer_new(U64, d)
        var ordinal: U64 = 0
        while ordinal < expression.child_count {
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
            let child = try lower_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block)
            current = child.state
            args = try __s0_buffer_append(U64, d, args, child.id)
            ordinal = ordinal + 1
        }
        if annotation.builtin == 1 {
            let result = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
            let instr = try lower_add_instr(d, result.state, function, block, mir_op_slice_len(), result.id, 0, 0, __s0_buffer_get(U64, args, 0), 0, 0, "")
            return Ok(LowerStep(state: instr.state, id: result.id))
        }
        if annotation.builtin == 2 {
            let result = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
            let instr = try lower_add_instr_three(d, result.state, function, block, mir_op_slice_range_checked(), result.id, 0, __s0_buffer_get(U64, args, 0), __s0_buffer_get(U64, args, 1), __s0_buffer_get(U64, args, 2), panic_block)
            return Ok(LowerStep(state: instr.state, id: result.id))
        }
        if annotation.builtin == 3 {
            let checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
            let element = try lower_type(d, source_state, store, current, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
            let empty = try __s0_buffer_new(U64, d)
            let reference = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
            let result = try lower_add_typed_result(d, lower_with_mir(element.state, reference.store), function, block, reference.type_id)
            let instr = try lower_add_instr(d, result.state, function, block, mir_op_alloc(), result.id, 0, element.id, __s0_buffer_get(U64, args, 0), __s0_buffer_get(U64, args, 1), 0, "")
            return Ok(LowerStep(state: instr.state, id: result.id))
        }
        if annotation.builtin == 4 || annotation.builtin == 5 {
            let typ = try lower_type(d, source_state, store, current, expression.checked_type)
            let result = try lower_add_typed_result(d, typ.state, function, block, typ.id)
            var op = mir_op_domain_create()
            if annotation.builtin == 5 { op = mir_op_domain_mark() }
            let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, __s0_buffer_get(U64, args, 0), 0, 0, "")
            return Ok(LowerStep(state: instr.state, id: result.id))
        }
        if annotation.builtin == 6 || annotation.builtin == 7 {
            var op = mir_op_domain_reset()
            var second: U64 = 0
            if annotation.builtin == 6 { second = __s0_buffer_get(U64, args, 1) }
            if annotation.builtin == 7 { op = mir_op_domain_destroy() }
            let instr = try lower_add_instr(d, current, function, block, op, 0, 0, 0, __s0_buffer_get(U64, args, 0), second, 0, "")
            return Ok(LowerStep(state: instr.state, id: 0))
        }
        if annotation.builtin == 8 || (annotation.builtin >= 14 && annotation.builtin <= 16) {
            var map_checked = lower_builtin_child_type(store, expression, 0)
            if annotation.builtin == 8 { map_checked = expression.checked_type }
            let bridge = lower_bridge_lookup(current, map_checked)
            if bridge.checked_type == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            var target = bridge.make_id
            if annotation.builtin == 14 { target = bridge.get_id }
            if annotation.builtin == 15 { target = bridge.set_id }
            if annotation.builtin == 16 { target = bridge.remove_id }
            let result_type = __s0_buffer_get(MirFunctionRec, current.mir.functions, target - 1).result_type
            let result = try lower_add_typed_result(d, current, function, block, result_type)
            let call = try lower_add_instr(d, result.state, function, block, mir_op_call(), result.id, 0, 0, 0, 0, target, "")
            current = call.state
            ordinal = 0
            while ordinal < __s0_buffer_len(U64, args) {
                current = try lower_add_instr_operand(d, current, call.id, ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
                ordinal = ordinal + 1
            }
            if annotation.builtin == 15 {
                let active = lower_open_block(current.mir, function, block)
                let ok = try lower_add_block(d, current, function, "bb_map_set_ok")
                current = try lower_branch(d, ok.state, function, active, result.id, ok.id, panic_block)
                return Ok(LowerStep(state: current, id: 0))
            }
            return Ok(LowerStep(state: current, id: result.id))
        }
        if annotation.builtin >= 9 && annotation.builtin <= 13 {
            var buffer_checked = lower_builtin_child_type(store, expression, 0)
            if annotation.builtin == 9 {
                let result_checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
                buffer_checked = __s0_buffer_get(U64, store.type_args, result_checked.first_arg - 1)
            }
            if annotation.builtin == 11 { buffer_checked = lower_builtin_child_type(store, expression, 1) }
            let bridge = lower_bridge_lookup(current, buffer_checked)
            if bridge.checked_type == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            var target = bridge.make_id
            if annotation.builtin == 10 { target = bridge.len_id }
            if annotation.builtin == 11 { target = bridge.append_id }
            if annotation.builtin == 12 { target = bridge.get_id }
            if annotation.builtin == 13 { target = bridge.slice_id }
            let result_type = __s0_buffer_get(MirFunctionRec, current.mir.functions, target - 1).result_type
            let result = try lower_add_typed_result(d, current, function, block, result_type)
            let call = try lower_add_instr(d, result.state, function, block, mir_op_call(), result.id, 0, 0, 0, 0, target, "")
            current = call.state
            ordinal = 0
            while ordinal < __s0_buffer_len(U64, args) {
                current = try lower_add_instr_operand(d, current, call.id, ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
                ordinal = ordinal + 1
            }
            return Ok(LowerStep(state: current, id: result.id))
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
        let source_block = lower_open_block(scrutinee.state.mir, function, block)
        let join = try lower_add_block(d, scrutinee.state, function, "bb_match_join")
        let result_type = try lower_type(d, source_state, store, join.state, checked.checked_type)
        let join_param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, try lower_decimal_name(d, "__s0_match_join", join.id), result_type.id)
        var current = lower_with_mir(result_type.state, join_param.store)
        var arm_blocks = try __s0_buffer_new(U64, d)
        var ordinal: U64 = 0
        while ordinal < checked.arm_count {
            let arm_block = try lower_add_block(d, current, function, "bb_match_arm")
            current = arm_block.state
            arm_blocks = try __s0_buffer_append(U64, d, arm_blocks, arm_block.id)
            ordinal = ordinal + 1
        }
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
                let value = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "__s0_match_payload", checked.first_arm + ordinal), payload_type.id, mir_value_def_switch_case(), source_block, ordinal + 1)
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
            let scope = lower_cleanup_scope_lookup(current, cleanup.binding)
            if scope == 0 { return Ok(lower_invalid(current)) }
            let run = try lower_add_instr(d, current, function, block, mir_op_cleanup_scope_run(), 0, 0, 0, scope, 0, 0, "")
            let ended = try lower_add_instr(d, run.state, function, block, mir_op_cleanup_scope_end(), 0, 0, 0, scope, 0, 0, "")
            current = ended.state
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
        var root_mir_type: U64 = 0
        var local_at: U64 = 0
        while local_at < __s0_buffer_len(MirLocalRec, current.mir.locals) {
            let candidate = __s0_buffer_get(MirLocalRec, current.mir.locals, local_at)
            if candidate.function == function && candidate.ordinal + 1 == binding.mir_id { root_mir_type = candidate.local_type }
            local_at = local_at + 1
        }
        if root_mir_type == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let loaded = try lower_add_typed_result(d, current, function, block, root_mir_type)
        let load = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, root.id, 0, 0, 0, 0, "")
        let index = try lower_expression(d, source_state, spans, store, load.state, owner, function, block, checked.index, environment, panic_block)
        let elem_checked = __s0_buffer_get(U64, store.type_args, root_type.first_arg - 1)
        let elem = try lower_type(d, source_state, store, index.state, elem_checked)
        let empty = try __s0_buffer_new(U64, d)
        let ref_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty, 0)
        let result = try mir_add_value(d, ref_type.store, function, try lower_result_name(d, ref_type.store, function, ""), ref_type.type_id, mir_value_def_instruction(), block, lower_instruction_ordinal(ref_type.store, function, block) + 1)
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
        let ref_value = try mir_add_value(d, ref_type.store, function, try lower_result_name(d, ref_type.store, function, "for_ref"), ref_type.type_id, mir_value_def_instruction(), body.id, lower_instruction_ordinal(ref_type.store, function, body.id) + 1)
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
        let empty = try __s0_buffer_new(U64, d)
        let scope_type = try mir_intern_type(d, current.mir, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
        let scope_value = try mir_add_value(d, scope_type.store, function, try lower_result_name(d, scope_type.store, function, try lower_decimal_name(d, "cleanup_scope", statement.binding)), scope_type.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(scope_type.store, function, active) + 1)
        let begun = try lower_add_instr(d, lower_with_mir(current, scope_value.store), function, active, mir_op_cleanup_scope_begin(), scope_value.id, 0, 0, 0, 0, 0, "")
        let cleanup_type = try mir_intern_type(d, begun.state.mir, mir_type_kind_cleanup_id(), 0, 0, 0, empty, 0)
        let cleanup_value = try mir_add_value(d, cleanup_type.store, function, try lower_result_name(d, cleanup_type.store, function, try lower_decimal_name(d, "cleanup_id", statement.binding)), cleanup_type.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(cleanup_type.store, function, active) + 1)
        let cleanup = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, statement.body - 1)
        let callback = lower_owner_lookup(current.owners, cleanup.callback)
        if callback == 0 { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
        let pushed = try lower_add_instr(d, lower_with_mir(begun.state, cleanup_value.store), function, active, mir_op_cleanup_push(), cleanup_value.id, 0, 0, scope_value.id, 0, callback, "")
        current = try lower_add_instr_operand(d, pushed.state, pushed.id, 0, value.id, mir_operand_instruction(), "")
        let scopes = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: statement.binding, value: scope_value.id))
        current = lower_with_values(current, scopes)
        return Ok(LowerFlowStep(state: current, block: active, terminated: false))
    }
    return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true))
}

fn lower_local_type(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, binding: U64, local: LocalRec) -> Result(LowerStep, __s0_Error) {
    let ordinary = try lower_type(d, source_state, store, state, local.checked_type)
    if local.kind != 2 { return Ok(ordinary) }
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if statement.owner == owner && statement.binding == binding && (statement.kind == 1 || statement.kind == 2) {
            let expression = __s0_buffer_get(CheckedExprRec, store.expressions, statement.expression - 1)
            if expression.kind == 18 && expression.annotation != 0 {
                let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
                if annotation.kind == 5 && annotation.builtin == 3 {
                    let checked = __s0_buffer_get(CheckedTypeRec, store.types, local.checked_type - 1)
                    let element = try lower_type(d, source_state, store, ordinary.state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
                    let empty = try __s0_buffer_new(U64, d)
                    let reference = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
                    return Ok(LowerStep(state: lower_with_mir(element.state, reference.store), id: reference.type_id))
                }
            }
        }
        at = at + 1
    }
    return Ok(ordinary)
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
            let typ = try lower_local_type(d, source_state, store, current, owner, at + 1, local)
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
    var bridge_at: U64 = 0
    while bridge_at < __s0_buffer_len(LowerBridgeRec, current.bridges) {
        let bridge = __s0_buffer_get(LowerBridgeRec, current.bridges, bridge_at)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, bridge.checked_type - 1)
        if checked.kind == 13 { current = try lower_buffer_helpers(d, source_state, store, current, bridge.checked_type, bridge) }
        if checked.kind == 11 {
            current = try lower_map_hash_eq_bodies(d, source_state, store, current, bridge.checked_type, bridge)
            current = try lower_map_make_body(d, source_state, store, current, bridge.checked_type, bridge)
            current = try lower_map_get_body(d, source_state, store, current, bridge.checked_type, bridge)
            current = try lower_map_set_body(d, source_state, store, current, bridge.checked_type, bridge)
            current = try lower_map_remove_body(d, source_state, store, current, bridge.checked_type, bridge)
        }
        bridge_at = bridge_at + 1
    }
    return Ok(current)
}

fn lower_map_set_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let key = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
    let map_type = try lower_type(d, source_state, store, key.state, checked_type)
    let slots_type = lower_map_slots_type(map_type.state.mir, map_type.id)
    var current = map_type.state
    let entry = try mir_add_block(d, current.mir, bridge.set_id, 0, "bb0")
    let loop = try mir_add_block(d, entry.store, bridge.set_id, 1, "bb_loop")
    let probe = try mir_add_block(d, loop.store, bridge.set_id, 2, "bb_probe")
    let occupied = try mir_add_block(d, probe.store, bridge.set_id, 3, "bb_occupied")
    let nonoccupied = try mir_add_block(d, occupied.store, bridge.set_id, 4, "bb_nonoccupied")
    let empty = try mir_add_block(d, nonoccupied.store, bridge.set_id, 5, "bb_empty")
    let deleted = try mir_add_block(d, empty.store, bridge.set_id, 6, "bb_deleted")
    let check = try mir_add_block(d, deleted.store, bridge.set_id, 7, "bb_check")
    let write = try mir_add_block(d, check.store, bridge.set_id, 8, "bb_write")
    let next = try mir_add_block(d, write.store, bridge.set_id, 9, "bb_next")
    let insert_current = try mir_add_block(d, next.store, bridge.set_id, 10, "bb_insert_current")
    let insert_deleted = try mir_add_block(d, insert_current.store, bridge.set_id, 11, "bb_insert_deleted")
    let insert = try mir_add_block(d, insert_deleted.store, bridge.set_id, 12, "bb_insert")
    let full = try mir_add_block(d, insert.store, bridge.set_id, 13, "bb_full")
    let done = try mir_add_block(d, full.store, bridge.set_id, 14, "bb_done")
    let failed = try mir_add_block(d, done.store, bridge.set_id, 15, "bb_failed")
    let fail = try mir_add_block(d, failed.store, bridge.set_id, 16, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: bridge.set_id, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    let index_param = try mir_add_block_param(d, fail_term.store, bridge.set_id, loop.id, 0, "index", mir_type_u64())
    let probes_param = try mir_add_block_param(d, index_param.store, bridge.set_id, loop.id, 1, "probes", mir_type_u64())
    let insert_param = try mir_add_block_param(d, probes_param.store, bridge.set_id, insert.id, 0, "insert_index", mir_type_u64())
    current = lower_with_mir(current, insert_param.store)
    let map_local = try lower_helper_local_place(d, current, bridge.set_id, 0, "map", map_type.id)
    let map_stored = try lower_add_instr(d, map_local.state, bridge.set_id, entry.id, mir_op_store(), 0, map_local.id, 0, 1, 0, 0, "")
    let deleted_local = try lower_helper_local_place(d, map_stored.state, bridge.set_id, 1, "first_deleted", mir_type_u64())
    let slots_place = try lower_helper_field_place(d, deleted_local.state, bridge.set_id, map_local.id, "slots")
    let slots = try lower_helper_load(d, slots_place.state, bridge.set_id, entry.id, slots_place.id, slots_type)
    let hash = try lower_helper_call(d, slots.state, bridge.set_id, entry.id, bridge.len_id, mir_type_u64(), 2, 0, 0)
    let cap = try lower_helper_const(d, hash.state, bridge.set_id, entry.id, mir_type_u64(), 16, checked_type * 100 + 60)
    let zero = try lower_helper_const(d, cap.state, bridge.set_id, entry.id, mir_type_u64(), 0, checked_type * 100 + 61)
    let one = try lower_helper_const(d, zero.state, bridge.set_id, entry.id, mir_type_u64(), 1, checked_type * 100 + 62)
    let init_deleted = try lower_add_instr(d, one.state, bridge.set_id, entry.id, mir_op_store(), 0, deleted_local.id, 0, cap.id, 0, 0, "")
    let quotient = try lower_add_typed_result(d, init_deleted.state, bridge.set_id, entry.id, mir_type_u64())
    let divided = try lower_add_instr(d, quotient.state, bridge.set_id, entry.id, mir_op_int_div_checked(), quotient.id, 0, 0, hash.id, cap.id, fail.id, "")
    let product = try lower_add_typed_result(d, divided.state, bridge.set_id, entry.id, mir_type_u64())
    let multiplied = try lower_add_instr(d, product.state, bridge.set_id, entry.id, mir_op_int_mul_checked(), product.id, 0, 0, quotient.id, cap.id, fail.id, "")
    let initial = try lower_add_typed_result(d, multiplied.state, bridge.set_id, entry.id, mir_type_u64())
    let subtracted = try lower_add_instr(d, initial.state, bridge.set_id, entry.id, mir_op_int_sub_checked(), initial.id, 0, 0, hash.id, product.id, fail.id, "")
    current = try lower_jump_two(d, subtracted.state, bridge.set_id, entry.id, loop.id, initial.id, zero.id)
    let exhausted = try lower_add_typed_result(d, current, bridge.set_id, loop.id, mir_type_bool())
    let exhausted_cmp = try lower_add_instr(d, exhausted.state, bridge.set_id, loop.id, mir_op_int_ge(), exhausted.id, 0, 0, probes_param.id, cap.id, 0, "")
    current = try lower_branch(d, exhausted_cmp.state, bridge.set_id, loop.id, exhausted.id, full.id, probe.id)
    let reference = try lower_add_typed_result(d, current, bridge.set_id, probe.id, slots_type)
    let indexed = try lower_add_instr(d, reference.state, bridge.set_id, probe.id, mir_op_slice_index_checked(), reference.id, 0, 0, slots.id, index_param.id, fail.id, "")
    let deref = try lower_helper_deref_place(d, indexed.state, bridge.set_id, reference.id)
    let state_place = try lower_helper_field_place(d, deref.state, bridge.set_id, deref.id, "state")
    let slot_state = try lower_helper_load(d, state_place.state, bridge.set_id, probe.id, state_place.id, mir_type_u8())
    let occupied_const = try lower_helper_const(d, slot_state.state, bridge.set_id, probe.id, mir_type_u8(), 1, checked_type * 100 + 63)
    let is_occupied = try lower_add_typed_result(d, occupied_const.state, bridge.set_id, probe.id, mir_type_bool())
    let occupied_cmp = try lower_add_instr(d, is_occupied.state, bridge.set_id, probe.id, mir_op_int_eq(), is_occupied.id, 0, 0, slot_state.id, occupied_const.id, 0, "")
    current = try lower_branch(d, occupied_cmp.state, bridge.set_id, probe.id, is_occupied.id, occupied.id, nonoccupied.id)
    let empty_const = try lower_helper_const(d, current, bridge.set_id, nonoccupied.id, mir_type_u8(), 0, checked_type * 100 + 64)
    let is_empty = try lower_add_typed_result(d, empty_const.state, bridge.set_id, nonoccupied.id, mir_type_bool())
    let empty_cmp = try lower_add_instr(d, is_empty.state, bridge.set_id, nonoccupied.id, mir_op_int_eq(), is_empty.id, 0, 0, slot_state.id, empty_const.id, 0, "")
    current = try lower_branch(d, empty_cmp.state, bridge.set_id, nonoccupied.id, is_empty.id, empty.id, deleted.id)
    let first_deleted = try lower_helper_load(d, current, bridge.set_id, empty.id, deleted_local.id, mir_type_u64())
    let no_deleted = try lower_add_typed_result(d, first_deleted.state, bridge.set_id, empty.id, mir_type_bool())
    let no_deleted_cmp = try lower_add_instr(d, no_deleted.state, bridge.set_id, empty.id, mir_op_int_eq(), no_deleted.id, 0, 0, first_deleted.id, cap.id, 0, "")
    current = try lower_branch(d, no_deleted_cmp.state, bridge.set_id, empty.id, no_deleted.id, insert_current.id, insert_deleted.id)
    current = try lower_jump_value(d, current, bridge.set_id, insert_current.id, insert.id, index_param.id)
    let selected_deleted = try lower_helper_load(d, current, bridge.set_id, insert_deleted.id, deleted_local.id, mir_type_u64())
    current = try lower_jump_value(d, selected_deleted.state, bridge.set_id, insert_deleted.id, insert.id, selected_deleted.id)
    let deleted_value = try lower_helper_load(d, current, bridge.set_id, deleted.id, deleted_local.id, mir_type_u64())
    let deleted_unset = try lower_add_typed_result(d, deleted_value.state, bridge.set_id, deleted.id, mir_type_bool())
    let deleted_cmp = try lower_add_instr(d, deleted_unset.state, bridge.set_id, deleted.id, mir_op_int_eq(), deleted_unset.id, 0, 0, deleted_value.id, cap.id, 0, "")
    let record = try mir_add_block(d, deleted_cmp.state.mir, bridge.set_id, 17, "bb_record_deleted")
    current = try lower_branch(d, lower_with_mir(deleted_cmp.state, record.store), bridge.set_id, deleted.id, deleted_unset.id, record.id, next.id)
    let recorded = try lower_add_instr(d, current, bridge.set_id, record.id, mir_op_store(), 0, deleted_local.id, 0, index_param.id, 0, 0, "")
    current = try lower_jump(d, recorded.state, bridge.set_id, record.id, next.id)
    let hash_place = try lower_helper_field_place(d, current, bridge.set_id, deref.id, "hash")
    let entry_hash = try lower_helper_load(d, hash_place.state, bridge.set_id, occupied.id, hash_place.id, mir_type_u64())
    let same_hash = try lower_add_typed_result(d, entry_hash.state, bridge.set_id, occupied.id, mir_type_bool())
    let hash_cmp = try lower_add_instr(d, same_hash.state, bridge.set_id, occupied.id, mir_op_int_eq(), same_hash.id, 0, 0, entry_hash.id, hash.id, 0, "")
    current = try lower_branch(d, hash_cmp.state, bridge.set_id, occupied.id, same_hash.id, check.id, next.id)
    let key_place = try lower_helper_field_place(d, current, bridge.set_id, deref.id, "key")
    let entry_key = try lower_helper_load(d, key_place.state, bridge.set_id, check.id, key_place.id, key.id)
    let same_key = try lower_helper_call(d, entry_key.state, bridge.set_id, check.id, bridge.append_id, mir_type_bool(), 2, entry_key.id, 0)
    current = try lower_branch(d, same_key.state, bridge.set_id, check.id, same_key.id, write.id, next.id)
    let value_place = try lower_helper_field_place(d, current, bridge.set_id, deref.id, "value")
    let value_stored = try lower_add_instr(d, value_place.state, bridge.set_id, write.id, mir_op_store(), 0, value_place.id, 0, 3, 0, 0, "")
    current = try lower_jump(d, value_stored.state, bridge.set_id, write.id, done.id)
    let next_index = try lower_add_typed_result(d, current, bridge.set_id, next.id, mir_type_u64())
    let index_added = try lower_add_instr(d, next_index.state, bridge.set_id, next.id, mir_op_int_add_checked(), next_index.id, 0, 0, index_param.id, one.id, fail.id, "")
    let next_q = try lower_add_typed_result(d, index_added.state, bridge.set_id, next.id, mir_type_u64())
    let next_div = try lower_add_instr(d, next_q.state, bridge.set_id, next.id, mir_op_int_div_checked(), next_q.id, 0, 0, next_index.id, cap.id, fail.id, "")
    let next_p = try lower_add_typed_result(d, next_div.state, bridge.set_id, next.id, mir_type_u64())
    let next_mul = try lower_add_instr(d, next_p.state, bridge.set_id, next.id, mir_op_int_mul_checked(), next_p.id, 0, 0, next_q.id, cap.id, fail.id, "")
    let wrapped = try lower_add_typed_result(d, next_mul.state, bridge.set_id, next.id, mir_type_u64())
    let wrapped_sub = try lower_add_instr(d, wrapped.state, bridge.set_id, next.id, mir_op_int_sub_checked(), wrapped.id, 0, 0, next_index.id, next_p.id, fail.id, "")
    let next_probes = try lower_add_typed_result(d, wrapped_sub.state, bridge.set_id, next.id, mir_type_u64())
    let probes_added = try lower_add_instr(d, next_probes.state, bridge.set_id, next.id, mir_op_int_add_checked(), next_probes.id, 0, 0, probes_param.id, one.id, fail.id, "")
    current = try lower_jump_two(d, probes_added.state, bridge.set_id, next.id, loop.id, wrapped.id, next_probes.id)
    let full_deleted = try lower_helper_load(d, current, bridge.set_id, full.id, deleted_local.id, mir_type_u64())
    let no_full_deleted = try lower_add_typed_result(d, full_deleted.state, bridge.set_id, full.id, mir_type_bool())
    let full_cmp = try lower_add_instr(d, no_full_deleted.state, bridge.set_id, full.id, mir_op_int_eq(), no_full_deleted.id, 0, 0, full_deleted.id, cap.id, 0, "")
    current = try lower_branch(d, full_cmp.state, bridge.set_id, full.id, no_full_deleted.id, failed.id, insert_deleted.id)
    let insert_ref = try lower_add_typed_result(d, current, bridge.set_id, insert.id, slots_type)
    let insert_indexed = try lower_add_instr(d, insert_ref.state, bridge.set_id, insert.id, mir_op_slice_index_checked(), insert_ref.id, 0, 0, slots.id, insert_param.id, fail.id, "")
    let insert_deref = try lower_helper_deref_place(d, insert_indexed.state, bridge.set_id, insert_ref.id)
    let insert_state = try lower_helper_field_place(d, insert_deref.state, bridge.set_id, insert_deref.id, "state")
    let inserted_occupied = try lower_helper_const(d, insert_state.state, bridge.set_id, insert.id, mir_type_u8(), 1, checked_type * 100 + 65)
    let store_state = try lower_add_instr(d, inserted_occupied.state, bridge.set_id, insert.id, mir_op_store(), 0, insert_state.id, 0, inserted_occupied.id, 0, 0, "")
    let insert_hash = try lower_helper_field_place(d, store_state.state, bridge.set_id, insert_deref.id, "hash")
    let store_hash = try lower_add_instr(d, insert_hash.state, bridge.set_id, insert.id, mir_op_store(), 0, insert_hash.id, 0, hash.id, 0, 0, "")
    let insert_key = try lower_helper_field_place(d, store_hash.state, bridge.set_id, insert_deref.id, "key")
    let store_key = try lower_add_instr(d, insert_key.state, bridge.set_id, insert.id, mir_op_store(), 0, insert_key.id, 0, 2, 0, 0, "")
    let insert_value = try lower_helper_field_place(d, store_key.state, bridge.set_id, insert_deref.id, "value")
    let store_value = try lower_add_instr(d, insert_value.state, bridge.set_id, insert.id, mir_op_store(), 0, insert_value.id, 0, 3, 0, 0, "")
    current = try lower_jump(d, store_value.state, bridge.set_id, insert.id, done.id)
    let yes = try lower_helper_bool(d, current, bridge.set_id, done.id, 1, checked_type * 100 + 66)
    current = try lower_helper_return(d, yes.state, bridge.set_id, done.id, yes.id)
    let no = try lower_helper_bool(d, current, bridge.set_id, failed.id, 0, checked_type * 100 + 67)
    return lower_helper_return(d, no.state, bridge.set_id, failed.id, no.id)
}

fn lower_buffer_new_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let element = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
    let buffer = try lower_type(d, source_state, store, element.state, checked_type)
    let empty_types = try __s0_buffer_new(U64, d)
    let data_type = try mir_intern_type(d, buffer.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty_types, 0)
    var current = lower_with_mir(buffer.state, data_type.store)
    let entry = try mir_add_block(d, current.mir, bridge.make_id, 0, "bb0")
    let ok = try mir_add_block(d, entry.store, bridge.make_id, 1, "bb_ok")
    let oom = try mir_add_block(d, ok.store, bridge.make_id, 2, "bb_oom")
    current = lower_with_mir(current, oom.store)
    let cap = try lower_helper_const(d, current, bridge.make_id, entry.id, mir_type_u64(), 8, checked_type * 100 + 1)
    let data = try lower_add_typed_result(d, cap.state, bridge.make_id, entry.id, data_type.type_id)
    let allocated = try lower_add_instr(d, data.state, bridge.make_id, entry.id, mir_op_alloc_checked(), data.id, 0, element.id, 1, cap.id, oom.id, "")
    current = try lower_jump(d, allocated.state, bridge.make_id, entry.id, ok.id)
    let result_type = __s0_buffer_get(MirFunctionRec, current.mir.functions, bridge.make_id - 1).result_type
    let result_rec = __s0_buffer_get(CheckedTypeRec, store.types, lower_result_type_for(store, checked_type, lower_checked_type_kind(store, 5, 0)) - 1)
    let error_checked = __s0_buffer_get(U64, store.type_args, result_rec.first_arg)
    let error_type = try lower_type(d, source_state, store, current, error_checked)
    let error = try lower_helper_variant(d, error_type.state, bridge.make_id, oom.id, error_type.id, "OutOfMemory", 0)
    let failed = try lower_helper_variant(d, error.state, bridge.make_id, oom.id, result_type, "err", error.id)
    current = try lower_helper_return(d, failed.state, bridge.make_id, oom.id, failed.id)
    let zero = try lower_helper_const(d, current, bridge.make_id, ok.id, mir_type_u64(), 0, checked_type * 100 + 2)
    let aggregate = try lower_helper_construct_two(d, zero.state, bridge.make_id, ok.id, buffer.id, "data", data.id, "len", zero.id)
    let success = try lower_helper_variant(d, aggregate.state, bridge.make_id, ok.id, result_type, "ok", aggregate.id)
    return lower_helper_return(d, success.state, bridge.make_id, ok.id, success.id)
}

fn lower_buffer_len_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let buffer = try lower_type(d, source_state, store, state, checked_type)
    let entry = try mir_add_block(d, buffer.state.mir, bridge.len_id, 0, "bb0")
    let local = try lower_helper_local_place(d, lower_with_mir(buffer.state, entry.store), bridge.len_id, 0, "buffer", buffer.id)
    let stored = try lower_add_instr(d, local.state, bridge.len_id, entry.id, mir_op_store(), 0, local.id, 0, 1, 0, 0, "")
    let field = try lower_helper_field_place(d, stored.state, bridge.len_id, local.id, "len")
    let length = try lower_helper_load(d, field.state, bridge.len_id, entry.id, field.id, mir_type_u64())
    return lower_helper_return(d, length.state, bridge.len_id, entry.id, length.id)
}

fn lower_buffer_get_slice_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let element_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let element = try lower_type(d, source_state, store, state, element_checked)
    let buffer = try lower_type(d, source_state, store, element.state, checked_type)
    let empty_types = try __s0_buffer_new(U64, d)
    let data_type = try mir_intern_type(d, buffer.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty_types, 0)
    var current = lower_with_mir(buffer.state, data_type.store)
    // get
    let get_entry = try mir_add_block(d, current.mir, bridge.get_id, 0, "bb0")
    let get_valid = try mir_add_block(d, get_entry.store, bridge.get_id, 1, "bb_valid")
    let get_fail = try mir_add_block(d, get_valid.store, bridge.get_id, 2, "bb_fail")
    let fail_term = try mir_add_terminator(d, get_fail.store, MirTermRec(function: bridge.get_id, block: get_fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    current = lower_with_mir(current, fail_term.store)
    let get_local = try lower_helper_local_place(d, current, bridge.get_id, 0, "buffer", buffer.id)
    let get_store = try lower_add_instr(d, get_local.state, bridge.get_id, get_entry.id, mir_op_store(), 0, get_local.id, 0, 1, 0, 0, "")
    let get_len_place = try lower_helper_field_place(d, get_store.state, bridge.get_id, get_local.id, "len")
    let get_len = try lower_helper_load(d, get_len_place.state, bridge.get_id, get_entry.id, get_len_place.id, mir_type_u64())
    let inside = try lower_add_typed_result(d, get_len.state, bridge.get_id, get_entry.id, mir_type_bool())
    let compared = try lower_add_instr(d, inside.state, bridge.get_id, get_entry.id, mir_op_int_lt(), inside.id, 0, 0, 2, get_len.id, 0, "")
    current = try lower_branch(d, compared.state, bridge.get_id, get_entry.id, inside.id, get_valid.id, get_fail.id)
    let get_data_place = try lower_helper_field_place(d, current, bridge.get_id, get_local.id, "data")
    let get_data = try lower_helper_load(d, get_data_place.state, bridge.get_id, get_valid.id, get_data_place.id, data_type.type_id)
    let get_ref = try lower_add_typed_result(d, get_data.state, bridge.get_id, get_valid.id, data_type.type_id)
    let indexed = try lower_add_instr(d, get_ref.state, bridge.get_id, get_valid.id, mir_op_slice_index_checked(), get_ref.id, 0, 0, get_data.id, 2, get_fail.id, "")
    let deref = try lower_helper_deref_place(d, indexed.state, bridge.get_id, get_ref.id)
    let item = try lower_helper_load(d, deref.state, bridge.get_id, get_valid.id, deref.id, element.id)
    current = try lower_helper_return(d, item.state, bridge.get_id, get_valid.id, item.id)
    // slice
    let slice_entry = try mir_add_block(d, current.mir, bridge.slice_id, 0, "bb0")
    let slice_fail = try mir_add_block(d, slice_entry.store, bridge.slice_id, 1, "bb_fail")
    let slice_fail_term = try mir_add_terminator(d, slice_fail.store, MirTermRec(function: bridge.slice_id, block: slice_fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    current = lower_with_mir(current, slice_fail_term.store)
    let slice_local = try lower_helper_local_place(d, current, bridge.slice_id, 0, "buffer", buffer.id)
    let slice_store = try lower_add_instr(d, slice_local.state, bridge.slice_id, slice_entry.id, mir_op_store(), 0, slice_local.id, 0, 1, 0, 0, "")
    let slice_data_place = try lower_helper_field_place(d, slice_store.state, bridge.slice_id, slice_local.id, "data")
    let slice_data = try lower_helper_load(d, slice_data_place.state, bridge.slice_id, slice_entry.id, slice_data_place.id, data_type.type_id)
    let slice_len_place = try lower_helper_field_place(d, slice_data.state, bridge.slice_id, slice_local.id, "len")
    let slice_len = try lower_helper_load(d, slice_len_place.state, bridge.slice_id, slice_entry.id, slice_len_place.id, mir_type_u64())
    let zero = try lower_helper_const(d, slice_len.state, bridge.slice_id, slice_entry.id, mir_type_u64(), 0, checked_type * 100 + 3)
    let slice_type = __s0_buffer_get(MirFunctionRec, zero.state.mir.functions, bridge.slice_id - 1).result_type
    let slice_result = try lower_add_typed_result(d, zero.state, bridge.slice_id, slice_entry.id, slice_type)
    let ranged = try lower_add_instr_three(d, slice_result.state, bridge.slice_id, slice_entry.id, mir_op_slice_range_checked(), slice_result.id, 0, slice_data.id, zero.id, slice_len.id, slice_fail.id)
    return lower_helper_return(d, ranged.state, bridge.slice_id, slice_entry.id, slice_result.id)
}

fn lower_buffer_append_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let element_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let element = try lower_type(d, source_state, store, state, element_checked)
    let buffer = try lower_type(d, source_state, store, element.state, checked_type)
    let empty_types = try __s0_buffer_new(U64, d)
    let data_type = try mir_intern_type(d, buffer.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty_types, 0)
    var current = lower_with_mir(buffer.state, data_type.store)
    let entry = try mir_add_block(d, current.mir, bridge.append_id, 0, "bb0")
    let spare = try mir_add_block(d, entry.store, bridge.append_id, 1, "bb_spare")
    let grow = try mir_add_block(d, spare.store, bridge.append_id, 2, "bb_grow")
    let limit = try mir_add_block(d, grow.store, bridge.append_id, 3, "bb_limit")
    let allocate = try mir_add_block(d, limit.store, bridge.append_id, 4, "bb_alloc")
    let oom = try mir_add_block(d, allocate.store, bridge.append_id, 5, "bb_oom")
    let copy = try mir_add_block(d, oom.store, bridge.append_id, 6, "bb_copy")
    let copy_one = try mir_add_block(d, copy.store, bridge.append_id, 7, "bb_copy_one")
    let finish = try mir_add_block(d, copy_one.store, bridge.append_id, 8, "bb_finish")
    let fail = try mir_add_block(d, finish.store, bridge.append_id, 9, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: bridge.append_id, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    current = lower_with_mir(current, fail_term.store)
    let copy_param = try mir_add_block_param(d, current.mir, bridge.append_id, copy.id, 0, "i", mir_type_u64())
    current = lower_with_mir(current, copy_param.store)
    let local = try lower_helper_local_place(d, current, bridge.append_id, 0, "buffer", buffer.id)
    let stored = try lower_add_instr(d, local.state, bridge.append_id, entry.id, mir_op_store(), 0, local.id, 0, 2, 0, 0, "")
    let data_place = try lower_helper_field_place(d, stored.state, bridge.append_id, local.id, "data")
    let data = try lower_helper_load(d, data_place.state, bridge.append_id, entry.id, data_place.id, data_type.type_id)
    let len_place = try lower_helper_field_place(d, data.state, bridge.append_id, local.id, "len")
    let length = try lower_helper_load(d, len_place.state, bridge.append_id, entry.id, len_place.id, mir_type_u64())
    let capacity = try lower_add_typed_result(d, length.state, bridge.append_id, entry.id, mir_type_u64())
    let capacity_instr = try lower_add_instr(d, capacity.state, bridge.append_id, entry.id, mir_op_slice_len(), capacity.id, 0, 0, data.id, 0, 0, "")
    let full = try lower_add_typed_result(d, capacity_instr.state, bridge.append_id, entry.id, mir_type_bool())
    let full_instr = try lower_add_instr(d, full.state, bridge.append_id, entry.id, mir_op_int_eq(), full.id, 0, 0, length.id, capacity.id, 0, "")
    let one = try lower_helper_const(d, full_instr.state, bridge.append_id, entry.id, mir_type_u64(), 1, checked_type * 100 + 4)
    current = try lower_branch(d, one.state, bridge.append_id, entry.id, full.id, grow.id, spare.id)
    let spare_ref = try lower_add_typed_result(d, current, bridge.append_id, spare.id, data_type.type_id)
    let spare_index = try lower_add_instr(d, spare_ref.state, bridge.append_id, spare.id, mir_op_slice_index_checked(), spare_ref.id, 0, 0, data.id, length.id, fail.id, "")
    let spare_deref = try lower_helper_deref_place(d, spare_index.state, bridge.append_id, spare_ref.id)
    let spare_store = try lower_add_instr(d, spare_deref.state, bridge.append_id, spare.id, mir_op_store(), 0, spare_deref.id, 0, 3, 0, 0, "")
    let spare_len = try lower_add_typed_result(d, spare_store.state, bridge.append_id, spare.id, mir_type_u64())
    let spare_added = try lower_add_instr(d, spare_len.state, bridge.append_id, spare.id, mir_op_int_add_checked(), spare_len.id, 0, 0, length.id, one.id, fail.id, "")
    let spare_buffer = try lower_helper_construct_two(d, spare_added.state, bridge.append_id, spare.id, buffer.id, "data", data.id, "len", spare_len.id)
    let result_type = __s0_buffer_get(MirFunctionRec, current.mir.functions, bridge.append_id - 1).result_type
    let spare_ok = try lower_helper_variant(d, spare_buffer.state, bridge.append_id, spare.id, result_type, "ok", spare_buffer.id)
    current = try lower_helper_return(d, spare_ok.state, bridge.append_id, spare.id, spare_ok.id)
    let two = try lower_helper_const(d, current, bridge.append_id, grow.id, mir_type_u64(), 2, checked_type * 100 + 5)
    let next_capacity = try lower_add_typed_result(d, two.state, bridge.append_id, grow.id, mir_type_u64())
    let multiplied = try lower_add_instr(d, next_capacity.state, bridge.append_id, grow.id, mir_op_int_mul_checked(), next_capacity.id, 0, 0, capacity.id, two.id, limit.id, "")
    current = try lower_jump(d, multiplied.state, bridge.append_id, grow.id, allocate.id)
    let result_rec = __s0_buffer_get(CheckedTypeRec, store.types, lower_result_type_for(store, checked_type, lower_checked_type_kind(store, 5, 0)) - 1)
    let error_checked = __s0_buffer_get(U64, store.type_args, result_rec.first_arg)
    let error_type = try lower_type(d, source_state, store, current, error_checked)
    let limit_error = try lower_helper_variant(d, error_type.state, bridge.append_id, limit.id, error_type.id, "Limit", 0)
    let limit_result = try lower_helper_variant(d, limit_error.state, bridge.append_id, limit.id, result_type, "err", limit_error.id)
    current = try lower_helper_return(d, limit_result.state, bridge.append_id, limit.id, limit_result.id)
    let new_data = try lower_add_typed_result(d, current, bridge.append_id, allocate.id, data_type.type_id)
    let new_alloc = try lower_add_instr(d, new_data.state, bridge.append_id, allocate.id, mir_op_alloc_checked(), new_data.id, 0, element.id, 1, next_capacity.id, oom.id, "")
    let zero = try lower_helper_const(d, new_alloc.state, bridge.append_id, allocate.id, mir_type_u64(), 0, checked_type * 100 + 6)
    current = try lower_jump_value(d, zero.state, bridge.append_id, allocate.id, copy.id, zero.id)
    let oom_error = try lower_helper_variant(d, current, bridge.append_id, oom.id, error_type.id, "OutOfMemory", 0)
    let oom_result = try lower_helper_variant(d, oom_error.state, bridge.append_id, oom.id, result_type, "err", oom_error.id)
    current = try lower_helper_return(d, oom_result.state, bridge.append_id, oom.id, oom_result.id)
    let copied = try lower_add_typed_result(d, current, bridge.append_id, copy.id, mir_type_bool())
    let copy_done = try lower_add_instr(d, copied.state, bridge.append_id, copy.id, mir_op_int_ge(), copied.id, 0, 0, copy_param.id, length.id, 0, "")
    current = try lower_branch(d, copy_done.state, bridge.append_id, copy.id, copied.id, finish.id, copy_one.id)
    let old_ref = try lower_add_typed_result(d, current, bridge.append_id, copy_one.id, data_type.type_id)
    let old_index = try lower_add_instr(d, old_ref.state, bridge.append_id, copy_one.id, mir_op_slice_index_checked(), old_ref.id, 0, 0, data.id, copy_param.id, fail.id, "")
    let old_deref = try lower_helper_deref_place(d, old_index.state, bridge.append_id, old_ref.id)
    let old_value = try lower_helper_load(d, old_deref.state, bridge.append_id, copy_one.id, old_deref.id, element.id)
    let new_ref = try lower_add_typed_result(d, old_value.state, bridge.append_id, copy_one.id, data_type.type_id)
    let new_index = try lower_add_instr(d, new_ref.state, bridge.append_id, copy_one.id, mir_op_slice_index_checked(), new_ref.id, 0, 0, new_data.id, copy_param.id, fail.id, "")
    let new_deref = try lower_helper_deref_place(d, new_index.state, bridge.append_id, new_ref.id)
    let copied_store = try lower_add_instr(d, new_deref.state, bridge.append_id, copy_one.id, mir_op_store(), 0, new_deref.id, 0, old_value.id, 0, 0, "")
    let next_index = try lower_add_typed_result(d, copied_store.state, bridge.append_id, copy_one.id, mir_type_u64())
    let next_added = try lower_add_instr(d, next_index.state, bridge.append_id, copy_one.id, mir_op_int_add_checked(), next_index.id, 0, 0, copy_param.id, one.id, fail.id, "")
    current = try lower_jump_value(d, next_added.state, bridge.append_id, copy_one.id, copy.id, next_index.id)
    let append_ref = try lower_add_typed_result(d, current, bridge.append_id, finish.id, data_type.type_id)
    let append_index = try lower_add_instr(d, append_ref.state, bridge.append_id, finish.id, mir_op_slice_index_checked(), append_ref.id, 0, 0, new_data.id, length.id, fail.id, "")
    let append_deref = try lower_helper_deref_place(d, append_index.state, bridge.append_id, append_ref.id)
    let append_store = try lower_add_instr(d, append_deref.state, bridge.append_id, finish.id, mir_op_store(), 0, append_deref.id, 0, 3, 0, 0, "")
    let final_len = try lower_add_typed_result(d, append_store.state, bridge.append_id, finish.id, mir_type_u64())
    let final_added = try lower_add_instr(d, final_len.state, bridge.append_id, finish.id, mir_op_int_add_checked(), final_len.id, 0, 0, length.id, one.id, fail.id, "")
    let final_buffer = try lower_helper_construct_two(d, final_added.state, bridge.append_id, finish.id, buffer.id, "data", new_data.id, "len", final_len.id)
    let final_result = try lower_helper_variant(d, final_buffer.state, bridge.append_id, finish.id, result_type, "ok", final_buffer.id)
    return lower_helper_return(d, final_result.state, bridge.append_id, finish.id, final_result.id)
}

fn lower_buffer_helpers(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let made = try lower_buffer_new_body(d, source_state, store, state, checked_type, bridge)
    let length = try lower_buffer_len_body(d, source_state, store, made, checked_type, bridge)
    let appended = try lower_buffer_append_body(d, source_state, store, length, checked_type, bridge)
    return lower_buffer_get_slice_body(d, source_state, store, appended, checked_type, bridge)
}

fn lower_map_slots_type(mir: MirStore, map_type: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirTypePartRec, mir.type_parts) {
        let part = __s0_buffer_get(MirTypePartRec, mir.type_parts, at)
        if part.owner == map_type && part.kind == mir_type_part_field() && part.ordinal == 0 { return part.part_type }
        at = at + 1
    }
    return 0
}

fn lower_map_hash_value(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, function: U64, block: U64, value: U64, fail_block: U64) -> Result(LowerStep, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 {
        if checked.target == 9 { return Ok(LowerStep(state: state, id: value)) }
        if checked.target == 6 || checked.target == 7 || checked.target == 8 {
            let converted = try lower_add_typed_result(d, state, function, block, mir_type_u64())
            let instruction = try lower_add_instr(d, converted.state, function, block, mir_op_int_zext(), converted.id, 0, mir_type_u64(), value, 0, 0, "")
            return Ok(LowerStep(state: instruction.state, id: converted.id))
        }
        if checked.target == 1 {
            let join = try lower_add_block(d, state, function, "bb_hash_join")
            let one_block = try lower_add_block(d, join.state, function, "bb_hash_one")
            let zero_block = try lower_add_block(d, one_block.state, function, "bb_hash_zero")
            let parameter = try mir_add_block_param(d, zero_block.state.mir, function, join.id, 0, try lower_decimal_name(d, "hash_", join.id), mir_type_u64())
            var current = try lower_branch(d, lower_with_mir(zero_block.state, parameter.store), function, block, value, one_block.id, zero_block.id)
            let one = try lower_helper_const(d, current, function, one_block.id, mir_type_u64(), 1, function * 10000 + checked_type * 100 + 900000070)
            current = try lower_jump_value(d, one.state, function, one_block.id, join.id, one.id)
            let zero = try lower_helper_const(d, current, function, zero_block.id, mir_type_u64(), 0, function * 10000 + checked_type * 100 + 900000071)
            current = try lower_jump_value(d, zero.state, function, zero_block.id, join.id, zero.id)
            return Ok(LowerStep(state: current, id: parameter.id))
        }
        return Ok(LowerStep(state: lower_invalid(state), id: 0))
    }
    if checked.kind == 7 && __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1).kind == 2 {
        let lowered = try lower_type(d, source_state, store, state, checked_type)
        let local = try lower_helper_local_place(d, lowered.state, function, lower_local_count(lowered.state.mir, function), "hash_key", lowered.id)
        let stored = try lower_add_instr(d, local.state, function, block, mir_op_store(), 0, local.id, 0, value, 0, 0, "")
        var current = stored.state
        var accumulator: U64 = 0
        var ordinal: U64 = 0
        while ordinal < lower_use_count(store, checked.target, 1) {
            let use_id = lower_use_by_role(store, checked.target, 1, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let field_type = try lower_type_bound(d, source_state, store, current, use.checked_type, checked.target, checked_type)
            let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
            let place = try lower_helper_field_place(d, field_type.state, function, local.id, name)
            let field = try lower_helper_load(d, place.state, function, block, place.id, field_type.id)
            let hashed = try lower_map_hash_value(d, source_state, store, field.state, lower_bound_checked_type(store, use.checked_type, checked.target, checked_type), function, lower_open_block(field.state.mir, function, block), field.id, fail_block)
            current = hashed.state
            if accumulator == 0 { accumulator = hashed.id } else {
                let added = try lower_add_typed_result(d, current, function, lower_open_block(current.mir, function, block), mir_type_u64())
                let instruction = try lower_add_instr(d, added.state, function, block, mir_op_int_add_checked(), added.id, 0, 0, accumulator, hashed.id, fail_block, "")
                current = instruction.state
                accumulator = added.id
            }
            ordinal = ordinal + 1
        }
        if accumulator != 0 { return Ok(LowerStep(state: current, id: accumulator)) }
        return lower_helper_const(d, current, function, block, mir_type_u64(), 0, function * 10000 + checked_type * 100 + 900000072)
    }
    if checked.kind == 7 && __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1).kind == 3 {
        let join = try lower_add_block(d, state, function, "bb_hash_join")
        let parameter = try mir_add_block_param(d, join.state.mir, function, join.id, 0, try lower_decimal_name(d, "hash_", join.id), mir_type_u64())
        var current = lower_with_mir(join.state, parameter.store)
        var variant_blocks = try __s0_buffer_new(U64, d)
        let variant_count = lower_use_count(store, checked.target, 2)
        var ordinal: U64 = 0
        while ordinal < variant_count {
            let variant_block = try lower_add_block(d, current, function, "bb_hash_variant")
            current = variant_block.state
            variant_blocks = try __s0_buffer_append(U64, d, variant_blocks, variant_block.id)
            ordinal = ordinal + 1
        }
        let source_block = lower_open_block(current.mir, function, block)
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: value, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, term.store)
        var payloads = try __s0_buffer_new(U64, d)
        ordinal = 0
        while ordinal < variant_count {
            let use_id = lower_use_by_role(store, checked.target, 2, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
            var payload: U64 = 0
            if use.checked_type != 0 {
                let payload_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
                let payload_type = try lower_type(d, source_state, store, current, payload_checked)
                let payload_value = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "hash_payload", source_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), source_block, ordinal + 1)
                current = lower_with_mir(payload_type.state, payload_value.store)
                payload = payload_value.id
            }
            payloads = try __s0_buffer_append(U64, d, payloads, payload)
            let case = try lower_add_switch_case(d, current, term.id, ordinal, name, payload, __s0_buffer_get(U64, variant_blocks, ordinal))
            current = case.state
            ordinal = ordinal + 1
        }
        ordinal = 0
        var tag_value: I64 = 0
        while ordinal < variant_count {
            let use_id = lower_use_by_role(store, checked.target, 2, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let variant_block = __s0_buffer_get(U64, variant_blocks, ordinal)
            let tag = try lower_helper_const(d, current, function, variant_block, mir_type_u64(), tag_value, function * 10000 + checked_type * 100 + ordinal + 900000000)
            current = tag.state
            var hash = tag.id
            if use.checked_type != 0 {
                let payload_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
                let payload_hash = try lower_map_hash_value(d, source_state, store, current, payload_checked, function, variant_block, __s0_buffer_get(U64, payloads, ordinal), fail_block)
                current = payload_hash.state
                let active = lower_open_block(current.mir, function, variant_block)
                let combined = try lower_add_typed_result(d, current, function, active, mir_type_u64())
                let added = try lower_add_instr(d, combined.state, function, active, mir_op_int_add_checked(), combined.id, 0, 0, tag.id, payload_hash.id, fail_block, "")
                current = added.state
                hash = combined.id
            }
            current = try lower_jump_value(d, current, function, lower_open_block(current.mir, function, variant_block), join.id, hash)
            ordinal = ordinal + 1
            tag_value = tag_value + 1
        }
        return Ok(LowerStep(state: current, id: parameter.id))
    }
    return Ok(LowerStep(state: lower_invalid(state), id: 0))
}

fn lower_map_eq_value(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, function: U64, block: U64, left: U64, right: U64, equal_block: U64, different_block: U64) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 {
        if checked.target == 1 {
            let left_true = try lower_add_block(d, state, function, "bb_eq_left_true")
            let left_false = try lower_add_block(d, left_true.state, function, "bb_eq_left_false")
            var current = try lower_branch(d, left_false.state, function, block, left, left_true.id, left_false.id)
            current = try lower_branch(d, current, function, left_true.id, right, equal_block, different_block)
            return lower_branch(d, current, function, left_false.id, right, different_block, equal_block)
        }
        if checked.target >= 6 && checked.target <= 9 {
            let result = try lower_add_typed_result(d, state, function, block, mir_type_bool())
            let compared = try lower_add_instr(d, result.state, function, block, mir_op_int_eq(), result.id, 0, 0, left, right, 0, "")
            return lower_branch(d, compared.state, function, block, result.id, equal_block, different_block)
        }
        return Ok(lower_invalid(state))
    }
    if checked.kind == 7 && __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1).kind == 2 {
        let lowered = try lower_type(d, source_state, store, state, checked_type)
        let left_ordinal = lower_local_count(lowered.state.mir, function)
        let left_local = try lower_helper_local_place(d, lowered.state, function, left_ordinal, try lower_decimal_name(d, "eq_left_", left_ordinal), lowered.id)
        let left_stored = try lower_add_instr(d, left_local.state, function, block, mir_op_store(), 0, left_local.id, 0, left, 0, 0, "")
        let right_ordinal = lower_local_count(left_stored.state.mir, function)
        let right_local = try lower_helper_local_place(d, left_stored.state, function, right_ordinal, try lower_decimal_name(d, "eq_right_", right_ordinal), lowered.id)
        let right_stored = try lower_add_instr(d, right_local.state, function, block, mir_op_store(), 0, right_local.id, 0, right, 0, 0, "")
        var current = right_stored.state
        var active = block
        var ordinal: U64 = 0
        let field_count = lower_use_count(store, checked.target, 1)
        while ordinal < field_count {
            let use_id = lower_use_by_role(store, checked.target, 1, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let field_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
            let field_type = try lower_type(d, source_state, store, current, field_checked)
            let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
            let left_place = try lower_helper_field_place(d, field_type.state, function, left_local.id, name)
            let left_field = try lower_helper_load(d, left_place.state, function, active, left_place.id, field_type.id)
            let right_place = try lower_helper_field_place(d, left_field.state, function, right_local.id, name)
            let right_field = try lower_helper_load(d, right_place.state, function, active, right_place.id, field_type.id)
            var next_block = equal_block
            if ordinal + 1 < field_count {
                let next = try lower_add_block(d, right_field.state, function, "bb_eq_field")
                current = next.state
                next_block = next.id
            } else { current = right_field.state }
            current = try lower_map_eq_value(d, source_state, store, current, field_checked, function, active, left_field.id, right_field.id, next_block, different_block)
            active = next_block
            ordinal = ordinal + 1
        }
        if field_count == 0 { return lower_jump(d, current, function, active, equal_block) }
        return Ok(current)
    }
    if checked.kind == 7 && __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1).kind == 3 {
        var current = state
        var left_blocks = try __s0_buffer_new(U64, d)
        let variant_count = lower_use_count(store, checked.target, 2)
        var ordinal: U64 = 0
        while ordinal < variant_count {
            let variant_block = try lower_add_block(d, current, function, "bb_eq_variant")
            current = variant_block.state
            left_blocks = try __s0_buffer_append(U64, d, left_blocks, variant_block.id)
            ordinal = ordinal + 1
        }
        let source_block = lower_open_block(current.mir, function, block)
        let left_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: left, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, left_term.store)
        var left_payloads = try __s0_buffer_new(U64, d)
        ordinal = 0
        while ordinal < variant_count {
            let use_id = lower_use_by_role(store, checked.target, 2, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
            var payload: U64 = 0
            if use.checked_type != 0 {
                let payload_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
                let payload_type = try lower_type(d, source_state, store, current, payload_checked)
                let payload_value = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "eq_left_payload", source_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), source_block, ordinal + 1)
                current = lower_with_mir(payload_type.state, payload_value.store)
                payload = payload_value.id
            }
            left_payloads = try __s0_buffer_append(U64, d, left_payloads, payload)
            let case = try lower_add_switch_case(d, current, left_term.id, ordinal, name, payload, __s0_buffer_get(U64, left_blocks, ordinal))
            current = case.state
            ordinal = ordinal + 1
        }
        ordinal = 0
        while ordinal < variant_count {
            let use_id = lower_use_by_role(store, checked.target, 2, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
            let left_block = __s0_buffer_get(U64, left_blocks, ordinal)
            let compare = try lower_add_block(d, current, function, "bb_eq_payload")
            current = compare.state
            let right_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: left_block, kind: mir_term_switch(), value: right, target: 0, then_block: 0, else_block: 0))
            current = lower_with_mir(current, right_term.store)
            var right_payload: U64 = 0
            if use.checked_type != 0 {
                let payload_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
                let payload_type = try lower_type(d, source_state, store, current, payload_checked)
                let payload_value = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "eq_right_payload", left_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), left_block, 1)
                current = lower_with_mir(payload_type.state, payload_value.store)
                right_payload = payload_value.id
            }
            let matching = try lower_add_switch_case(d, current, right_term.id, 0, name, right_payload, compare.id)
            let fallback = try lower_add_switch_case(d, matching.state, right_term.id, 1, "", 0, different_block)
            current = fallback.state
            if use.checked_type == 0 {
                current = try lower_jump(d, current, function, compare.id, equal_block)
            } else {
                let payload_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
                current = try lower_map_eq_value(d, source_state, store, current, payload_checked, function, compare.id, __s0_buffer_get(U64, left_payloads, ordinal), right_payload, equal_block, different_block)
            }
            ordinal = ordinal + 1
        }
        return Ok(current)
    }
    return Ok(lower_invalid(state))
}

fn lower_map_hash_eq_bodies(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let key_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let key = try lower_type(d, source_state, store, state, key_checked)
    var current = key.state
    let hash_entry = try mir_add_block(d, current.mir, bridge.len_id, 0, "bb0")
    let hash_fail = try mir_add_block(d, hash_entry.store, bridge.len_id, 1, "bb_fail")
    let hash_fail_term = try mir_add_terminator(d, hash_fail.store, MirTermRec(function: bridge.len_id, block: hash_fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    let hashed = try lower_map_hash_value(d, source_state, store, lower_with_mir(current, hash_fail_term.store), key_checked, bridge.len_id, hash_entry.id, 1, hash_fail.id)
    current = try lower_helper_return(d, hashed.state, bridge.len_id, lower_open_block(hashed.state.mir, bridge.len_id, hash_entry.id), hashed.id)
    let eq_entry = try mir_add_block(d, current.mir, bridge.append_id, 0, "bb0")
    let eq_true = try mir_add_block(d, eq_entry.store, bridge.append_id, 1, "bb_true")
    let eq_false = try mir_add_block(d, eq_true.store, bridge.append_id, 2, "bb_false")
    current = lower_with_mir(current, eq_false.store)
    current = try lower_map_eq_value(d, source_state, store, current, key_checked, bridge.append_id, eq_entry.id, 1, 2, eq_true.id, eq_false.id)
    let truth = try lower_helper_bool(d, current, bridge.append_id, eq_true.id, 1, checked_type * 100 + 22)
    current = try lower_helper_return(d, truth.state, bridge.append_id, eq_true.id, truth.id)
    let falsity = try lower_helper_bool(d, current, bridge.append_id, eq_false.id, 0, checked_type * 100 + 23)
    return lower_helper_return(d, falsity.state, bridge.append_id, eq_false.id, falsity.id)
}

fn lower_map_make_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let map_type = try lower_type(d, source_state, store, state, checked_type)
    let slots_type = lower_map_slots_type(map_type.state.mir, map_type.id)
    if slots_type == 0 { return Ok(lower_invalid(map_type.state)) }
    let entry_type = __s0_buffer_get(MirTypeRec, map_type.state.mir.types, slots_type - 1).elem
    var current = map_type.state
    let entry = try mir_add_block(d, current.mir, bridge.make_id, 0, "bb0")
    let loop = try mir_add_block(d, entry.store, bridge.make_id, 1, "bb_init")
    let body = try mir_add_block(d, loop.store, bridge.make_id, 2, "bb_slot")
    let done = try mir_add_block(d, body.store, bridge.make_id, 3, "bb_done")
    let fail = try mir_add_block(d, done.store, bridge.make_id, 4, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: bridge.make_id, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    let loop_param = try mir_add_block_param(d, fail_term.store, bridge.make_id, loop.id, 0, "i", mir_type_u64())
    current = lower_with_mir(current, loop_param.store)
    let cap = try lower_helper_const(d, current, bridge.make_id, entry.id, mir_type_u64(), 16, checked_type * 100 + 24)
    let zero = try lower_helper_const(d, cap.state, bridge.make_id, entry.id, mir_type_u64(), 0, checked_type * 100 + 25)
    let one = try lower_helper_const(d, zero.state, bridge.make_id, entry.id, mir_type_u64(), 1, checked_type * 100 + 26)
    let slots = try lower_add_typed_result(d, one.state, bridge.make_id, entry.id, slots_type)
    let allocated = try lower_add_instr(d, slots.state, bridge.make_id, entry.id, mir_op_alloc(), slots.id, 0, entry_type, 1, cap.id, 0, "")
    let map_value = try lower_add_typed_result(d, allocated.state, bridge.make_id, entry.id, map_type.id)
    let constructed = try lower_add_instr(d, map_value.state, bridge.make_id, entry.id, mir_op_aggregate_construct(), map_value.id, 0, map_type.id, 0, 0, 0, "")
    current = try lower_add_instr_operand(d, constructed.state, constructed.id, 0, slots.id, mir_operand_aggregate_field(), "slots")
    current = try lower_jump_value(d, current, bridge.make_id, entry.id, loop.id, zero.id)
    let finished = try lower_add_typed_result(d, current, bridge.make_id, loop.id, mir_type_bool())
    let compared = try lower_add_instr(d, finished.state, bridge.make_id, loop.id, mir_op_int_ge(), finished.id, 0, 0, loop_param.id, cap.id, 0, "")
    current = try lower_branch(d, compared.state, bridge.make_id, loop.id, finished.id, done.id, body.id)
    let reference = try lower_add_typed_result(d, current, bridge.make_id, body.id, slots_type)
    let indexed = try lower_add_instr(d, reference.state, bridge.make_id, body.id, mir_op_slice_index_checked(), reference.id, 0, 0, slots.id, loop_param.id, fail.id, "")
    let deref = try lower_helper_deref_place(d, indexed.state, bridge.make_id, reference.id)
    let state_place = try lower_helper_field_place(d, deref.state, bridge.make_id, deref.id, "state")
    let empty_state = try lower_helper_const(d, state_place.state, bridge.make_id, body.id, mir_type_u8(), 0, checked_type * 100 + 27)
    let stored = try lower_add_instr(d, empty_state.state, bridge.make_id, body.id, mir_op_store(), 0, state_place.id, 0, empty_state.id, 0, 0, "")
    let next = try lower_add_typed_result(d, stored.state, bridge.make_id, body.id, mir_type_u64())
    let added = try lower_add_instr(d, next.state, bridge.make_id, body.id, mir_op_int_add_checked(), next.id, 0, 0, loop_param.id, one.id, fail.id, "")
    current = try lower_jump_value(d, added.state, bridge.make_id, body.id, loop.id, next.id)
    return lower_helper_return(d, current, bridge.make_id, done.id, map_value.id)
}

fn lower_helper_call(d: Domain, state: LowerState, function: U64, block: U64, target: U64, result_type: U64, first: U64, second: U64, third: U64) -> Result(LowerStep, __s0_Error) {
    var result = LowerStep(state: state, id: 0)
    if result_type != mir_type_unit() { result = try lower_add_typed_result(d, state, function, block, result_type) }
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_call(), result.id, 0, 0, 0, 0, target, "")
    var current = instruction.state
    current = try lower_add_instr_operand(d, current, instruction.id, 0, first, mir_operand_instruction(), "")
    if second != 0 { current = try lower_add_instr_operand(d, current, instruction.id, 1, second, mir_operand_instruction(), "") }
    if third != 0 { current = try lower_add_instr_operand(d, current, instruction.id, 2, third, mir_operand_instruction(), "") }
    return Ok(LowerStep(state: current, id: result.id))
}

fn lower_map_get_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let key = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
    let value = try lower_type(d, source_state, store, key.state, __s0_buffer_get(U64, store.type_args, checked.first_arg))
    let map_type = try lower_type(d, source_state, store, value.state, checked_type)
    let slots_type = lower_map_slots_type(map_type.state.mir, map_type.id)
    var current = map_type.state
    let entry = try mir_add_block(d, current.mir, bridge.get_id, 0, "bb0")
    let loop = try mir_add_block(d, entry.store, bridge.get_id, 1, "bb_loop")
    let probe = try mir_add_block(d, loop.store, bridge.get_id, 2, "bb_probe")
    let occupied = try mir_add_block(d, probe.store, bridge.get_id, 3, "bb_occupied")
    let nonoccupied = try mir_add_block(d, occupied.store, bridge.get_id, 4, "bb_nonoccupied")
    let check = try mir_add_block(d, nonoccupied.store, bridge.get_id, 5, "bb_check")
    let found = try mir_add_block(d, check.store, bridge.get_id, 6, "bb_found")
    let next = try mir_add_block(d, found.store, bridge.get_id, 7, "bb_next")
    let none = try mir_add_block(d, next.store, bridge.get_id, 8, "bb_none")
    let fail = try mir_add_block(d, none.store, bridge.get_id, 9, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: bridge.get_id, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    let index_param = try mir_add_block_param(d, fail_term.store, bridge.get_id, loop.id, 0, "index", mir_type_u64())
    let probes_param = try mir_add_block_param(d, index_param.store, bridge.get_id, loop.id, 1, "probes", mir_type_u64())
    current = lower_with_mir(current, probes_param.store)
    let local = try lower_helper_local_place(d, current, bridge.get_id, 0, "map", map_type.id)
    let stored = try lower_add_instr(d, local.state, bridge.get_id, entry.id, mir_op_store(), 0, local.id, 0, 1, 0, 0, "")
    let slots_place = try lower_helper_field_place(d, stored.state, bridge.get_id, local.id, "slots")
    let slots = try lower_helper_load(d, slots_place.state, bridge.get_id, entry.id, slots_place.id, slots_type)
    let hash = try lower_helper_call(d, slots.state, bridge.get_id, entry.id, bridge.len_id, mir_type_u64(), 2, 0, 0)
    let cap = try lower_helper_const(d, hash.state, bridge.get_id, entry.id, mir_type_u64(), 16, checked_type * 100 + 30)
    let zero = try lower_helper_const(d, cap.state, bridge.get_id, entry.id, mir_type_u64(), 0, checked_type * 100 + 31)
    let one = try lower_helper_const(d, zero.state, bridge.get_id, entry.id, mir_type_u64(), 1, checked_type * 100 + 32)
    let quotient = try lower_add_typed_result(d, one.state, bridge.get_id, entry.id, mir_type_u64())
    let divided = try lower_add_instr(d, quotient.state, bridge.get_id, entry.id, mir_op_int_div_checked(), quotient.id, 0, 0, hash.id, cap.id, fail.id, "")
    let product = try lower_add_typed_result(d, divided.state, bridge.get_id, entry.id, mir_type_u64())
    let multiplied = try lower_add_instr(d, product.state, bridge.get_id, entry.id, mir_op_int_mul_checked(), product.id, 0, 0, quotient.id, cap.id, fail.id, "")
    let initial = try lower_add_typed_result(d, multiplied.state, bridge.get_id, entry.id, mir_type_u64())
    let subtracted = try lower_add_instr(d, initial.state, bridge.get_id, entry.id, mir_op_int_sub_checked(), initial.id, 0, 0, hash.id, product.id, fail.id, "")
    current = try lower_jump_two(d, subtracted.state, bridge.get_id, entry.id, loop.id, initial.id, zero.id)
    let exhausted = try lower_add_typed_result(d, current, bridge.get_id, loop.id, mir_type_bool())
    let exhausted_cmp = try lower_add_instr(d, exhausted.state, bridge.get_id, loop.id, mir_op_int_ge(), exhausted.id, 0, 0, probes_param.id, cap.id, 0, "")
    current = try lower_branch(d, exhausted_cmp.state, bridge.get_id, loop.id, exhausted.id, none.id, probe.id)
    let reference = try lower_add_typed_result(d, current, bridge.get_id, probe.id, slots_type)
    let indexed = try lower_add_instr(d, reference.state, bridge.get_id, probe.id, mir_op_slice_index_checked(), reference.id, 0, 0, slots.id, index_param.id, fail.id, "")
    let deref = try lower_helper_deref_place(d, indexed.state, bridge.get_id, reference.id)
    let state_place = try lower_helper_field_place(d, deref.state, bridge.get_id, deref.id, "state")
    let slot_state = try lower_helper_load(d, state_place.state, bridge.get_id, probe.id, state_place.id, mir_type_u8())
    let occupied_const = try lower_helper_const(d, slot_state.state, bridge.get_id, probe.id, mir_type_u8(), 1, checked_type * 100 + 33)
    let is_occupied = try lower_add_typed_result(d, occupied_const.state, bridge.get_id, probe.id, mir_type_bool())
    let occupied_cmp = try lower_add_instr(d, is_occupied.state, bridge.get_id, probe.id, mir_op_int_eq(), is_occupied.id, 0, 0, slot_state.id, occupied_const.id, 0, "")
    current = try lower_branch(d, occupied_cmp.state, bridge.get_id, probe.id, is_occupied.id, occupied.id, nonoccupied.id)
    let empty_const = try lower_helper_const(d, current, bridge.get_id, nonoccupied.id, mir_type_u8(), 0, checked_type * 100 + 34)
    let is_empty = try lower_add_typed_result(d, empty_const.state, bridge.get_id, nonoccupied.id, mir_type_bool())
    let empty_cmp = try lower_add_instr(d, is_empty.state, bridge.get_id, nonoccupied.id, mir_op_int_eq(), is_empty.id, 0, 0, slot_state.id, empty_const.id, 0, "")
    current = try lower_branch(d, empty_cmp.state, bridge.get_id, nonoccupied.id, is_empty.id, none.id, next.id)
    let hash_place = try lower_helper_field_place(d, current, bridge.get_id, deref.id, "hash")
    let entry_hash = try lower_helper_load(d, hash_place.state, bridge.get_id, occupied.id, hash_place.id, mir_type_u64())
    let same_hash = try lower_add_typed_result(d, entry_hash.state, bridge.get_id, occupied.id, mir_type_bool())
    let hash_cmp = try lower_add_instr(d, same_hash.state, bridge.get_id, occupied.id, mir_op_int_eq(), same_hash.id, 0, 0, entry_hash.id, hash.id, 0, "")
    current = try lower_branch(d, hash_cmp.state, bridge.get_id, occupied.id, same_hash.id, check.id, next.id)
    let key_place = try lower_helper_field_place(d, current, bridge.get_id, deref.id, "key")
    let entry_key = try lower_helper_load(d, key_place.state, bridge.get_id, check.id, key_place.id, key.id)
    let same_key = try lower_helper_call(d, entry_key.state, bridge.get_id, check.id, bridge.append_id, mir_type_bool(), 2, entry_key.id, 0)
    current = try lower_branch(d, same_key.state, bridge.get_id, check.id, same_key.id, found.id, next.id)
    let value_place = try lower_helper_field_place(d, current, bridge.get_id, deref.id, "value")
    let entry_value = try lower_helper_load(d, value_place.state, bridge.get_id, found.id, value_place.id, value.id)
    let option_type = __s0_buffer_get(MirFunctionRec, current.mir.functions, bridge.get_id - 1).result_type
    let some = try lower_helper_variant(d, entry_value.state, bridge.get_id, found.id, option_type, "some", entry_value.id)
    current = try lower_helper_return(d, some.state, bridge.get_id, found.id, some.id)
    let next_index = try lower_add_typed_result(d, current, bridge.get_id, next.id, mir_type_u64())
    let index_added = try lower_add_instr(d, next_index.state, bridge.get_id, next.id, mir_op_int_add_checked(), next_index.id, 0, 0, index_param.id, one.id, fail.id, "")
    let next_q = try lower_add_typed_result(d, index_added.state, bridge.get_id, next.id, mir_type_u64())
    let next_div = try lower_add_instr(d, next_q.state, bridge.get_id, next.id, mir_op_int_div_checked(), next_q.id, 0, 0, next_index.id, cap.id, fail.id, "")
    let next_p = try lower_add_typed_result(d, next_div.state, bridge.get_id, next.id, mir_type_u64())
    let next_mul = try lower_add_instr(d, next_p.state, bridge.get_id, next.id, mir_op_int_mul_checked(), next_p.id, 0, 0, next_q.id, cap.id, fail.id, "")
    let wrapped = try lower_add_typed_result(d, next_mul.state, bridge.get_id, next.id, mir_type_u64())
    let wrapped_sub = try lower_add_instr(d, wrapped.state, bridge.get_id, next.id, mir_op_int_sub_checked(), wrapped.id, 0, 0, next_index.id, next_p.id, fail.id, "")
    let next_probes = try lower_add_typed_result(d, wrapped_sub.state, bridge.get_id, next.id, mir_type_u64())
    let probes_added = try lower_add_instr(d, next_probes.state, bridge.get_id, next.id, mir_op_int_add_checked(), next_probes.id, 0, 0, probes_param.id, one.id, fail.id, "")
    current = try lower_jump_two(d, probes_added.state, bridge.get_id, next.id, loop.id, wrapped.id, next_probes.id)
    let none_value = try lower_helper_variant(d, current, bridge.get_id, none.id, option_type, "none", 0)
    return lower_helper_return(d, none_value.state, bridge.get_id, none.id, none_value.id)
}

fn lower_map_remove_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let key = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
    let map_type = try lower_type(d, source_state, store, key.state, checked_type)
    let slots_type = lower_map_slots_type(map_type.state.mir, map_type.id)
    var current = map_type.state
    let entry = try mir_add_block(d, current.mir, bridge.remove_id, 0, "bb0")
    let loop = try mir_add_block(d, entry.store, bridge.remove_id, 1, "bb_loop")
    let probe = try mir_add_block(d, loop.store, bridge.remove_id, 2, "bb_probe")
    let occupied = try mir_add_block(d, probe.store, bridge.remove_id, 3, "bb_occupied")
    let nonoccupied = try mir_add_block(d, occupied.store, bridge.remove_id, 4, "bb_nonoccupied")
    let check = try mir_add_block(d, nonoccupied.store, bridge.remove_id, 5, "bb_check")
    let found = try mir_add_block(d, check.store, bridge.remove_id, 6, "bb_found")
    let next = try mir_add_block(d, found.store, bridge.remove_id, 7, "bb_next")
    let absent = try mir_add_block(d, next.store, bridge.remove_id, 8, "bb_absent")
    let fail = try mir_add_block(d, absent.store, bridge.remove_id, 9, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: bridge.remove_id, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    let index_param = try mir_add_block_param(d, fail_term.store, bridge.remove_id, loop.id, 0, "index", mir_type_u64())
    let probes_param = try mir_add_block_param(d, index_param.store, bridge.remove_id, loop.id, 1, "probes", mir_type_u64())
    current = lower_with_mir(current, probes_param.store)
    let local = try lower_helper_local_place(d, current, bridge.remove_id, 0, "map", map_type.id)
    let stored = try lower_add_instr(d, local.state, bridge.remove_id, entry.id, mir_op_store(), 0, local.id, 0, 1, 0, 0, "")
    let slots_place = try lower_helper_field_place(d, stored.state, bridge.remove_id, local.id, "slots")
    let slots = try lower_helper_load(d, slots_place.state, bridge.remove_id, entry.id, slots_place.id, slots_type)
    let hash = try lower_helper_call(d, slots.state, bridge.remove_id, entry.id, bridge.len_id, mir_type_u64(), 2, 0, 0)
    let cap = try lower_helper_const(d, hash.state, bridge.remove_id, entry.id, mir_type_u64(), 16, checked_type * 100 + 50)
    let zero = try lower_helper_const(d, cap.state, bridge.remove_id, entry.id, mir_type_u64(), 0, checked_type * 100 + 51)
    let one = try lower_helper_const(d, zero.state, bridge.remove_id, entry.id, mir_type_u64(), 1, checked_type * 100 + 52)
    let quotient = try lower_add_typed_result(d, one.state, bridge.remove_id, entry.id, mir_type_u64())
    let divided = try lower_add_instr(d, quotient.state, bridge.remove_id, entry.id, mir_op_int_div_checked(), quotient.id, 0, 0, hash.id, cap.id, fail.id, "")
    let product = try lower_add_typed_result(d, divided.state, bridge.remove_id, entry.id, mir_type_u64())
    let multiplied = try lower_add_instr(d, product.state, bridge.remove_id, entry.id, mir_op_int_mul_checked(), product.id, 0, 0, quotient.id, cap.id, fail.id, "")
    let initial = try lower_add_typed_result(d, multiplied.state, bridge.remove_id, entry.id, mir_type_u64())
    let subtracted = try lower_add_instr(d, initial.state, bridge.remove_id, entry.id, mir_op_int_sub_checked(), initial.id, 0, 0, hash.id, product.id, fail.id, "")
    current = try lower_jump_two(d, subtracted.state, bridge.remove_id, entry.id, loop.id, initial.id, zero.id)
    let exhausted = try lower_add_typed_result(d, current, bridge.remove_id, loop.id, mir_type_bool())
    let exhausted_cmp = try lower_add_instr(d, exhausted.state, bridge.remove_id, loop.id, mir_op_int_ge(), exhausted.id, 0, 0, probes_param.id, cap.id, 0, "")
    current = try lower_branch(d, exhausted_cmp.state, bridge.remove_id, loop.id, exhausted.id, absent.id, probe.id)
    let reference = try lower_add_typed_result(d, current, bridge.remove_id, probe.id, slots_type)
    let indexed = try lower_add_instr(d, reference.state, bridge.remove_id, probe.id, mir_op_slice_index_checked(), reference.id, 0, 0, slots.id, index_param.id, fail.id, "")
    let deref = try lower_helper_deref_place(d, indexed.state, bridge.remove_id, reference.id)
    let state_place = try lower_helper_field_place(d, deref.state, bridge.remove_id, deref.id, "state")
    let slot_state = try lower_helper_load(d, state_place.state, bridge.remove_id, probe.id, state_place.id, mir_type_u8())
    let occupied_const = try lower_helper_const(d, slot_state.state, bridge.remove_id, probe.id, mir_type_u8(), 1, checked_type * 100 + 53)
    let is_occupied = try lower_add_typed_result(d, occupied_const.state, bridge.remove_id, probe.id, mir_type_bool())
    let occupied_cmp = try lower_add_instr(d, is_occupied.state, bridge.remove_id, probe.id, mir_op_int_eq(), is_occupied.id, 0, 0, slot_state.id, occupied_const.id, 0, "")
    current = try lower_branch(d, occupied_cmp.state, bridge.remove_id, probe.id, is_occupied.id, occupied.id, nonoccupied.id)
    let empty_const = try lower_helper_const(d, current, bridge.remove_id, nonoccupied.id, mir_type_u8(), 0, checked_type * 100 + 54)
    let is_empty = try lower_add_typed_result(d, empty_const.state, bridge.remove_id, nonoccupied.id, mir_type_bool())
    let empty_cmp = try lower_add_instr(d, is_empty.state, bridge.remove_id, nonoccupied.id, mir_op_int_eq(), is_empty.id, 0, 0, slot_state.id, empty_const.id, 0, "")
    current = try lower_branch(d, empty_cmp.state, bridge.remove_id, nonoccupied.id, is_empty.id, absent.id, next.id)
    let hash_place = try lower_helper_field_place(d, current, bridge.remove_id, deref.id, "hash")
    let entry_hash = try lower_helper_load(d, hash_place.state, bridge.remove_id, occupied.id, hash_place.id, mir_type_u64())
    let same_hash = try lower_add_typed_result(d, entry_hash.state, bridge.remove_id, occupied.id, mir_type_bool())
    let hash_cmp = try lower_add_instr(d, same_hash.state, bridge.remove_id, occupied.id, mir_op_int_eq(), same_hash.id, 0, 0, entry_hash.id, hash.id, 0, "")
    current = try lower_branch(d, hash_cmp.state, bridge.remove_id, occupied.id, same_hash.id, check.id, next.id)
    let key_place = try lower_helper_field_place(d, current, bridge.remove_id, deref.id, "key")
    let entry_key = try lower_helper_load(d, key_place.state, bridge.remove_id, check.id, key_place.id, key.id)
    let same_key = try lower_helper_call(d, entry_key.state, bridge.remove_id, check.id, bridge.append_id, mir_type_bool(), 2, entry_key.id, 0)
    current = try lower_branch(d, same_key.state, bridge.remove_id, check.id, same_key.id, found.id, next.id)
    let deleted = try lower_helper_const(d, current, bridge.remove_id, found.id, mir_type_u8(), 2, checked_type * 100 + 55)
    let marked = try lower_add_instr(d, deleted.state, bridge.remove_id, found.id, mir_op_store(), 0, state_place.id, 0, deleted.id, 0, 0, "")
    let yes = try lower_helper_bool(d, marked.state, bridge.remove_id, found.id, 1, checked_type * 100 + 56)
    current = try lower_helper_return(d, yes.state, bridge.remove_id, found.id, yes.id)
    let next_index = try lower_add_typed_result(d, current, bridge.remove_id, next.id, mir_type_u64())
    let index_added = try lower_add_instr(d, next_index.state, bridge.remove_id, next.id, mir_op_int_add_checked(), next_index.id, 0, 0, index_param.id, one.id, fail.id, "")
    let next_q = try lower_add_typed_result(d, index_added.state, bridge.remove_id, next.id, mir_type_u64())
    let next_div = try lower_add_instr(d, next_q.state, bridge.remove_id, next.id, mir_op_int_div_checked(), next_q.id, 0, 0, next_index.id, cap.id, fail.id, "")
    let next_p = try lower_add_typed_result(d, next_div.state, bridge.remove_id, next.id, mir_type_u64())
    let next_mul = try lower_add_instr(d, next_p.state, bridge.remove_id, next.id, mir_op_int_mul_checked(), next_p.id, 0, 0, next_q.id, cap.id, fail.id, "")
    let wrapped = try lower_add_typed_result(d, next_mul.state, bridge.remove_id, next.id, mir_type_u64())
    let wrapped_sub = try lower_add_instr(d, wrapped.state, bridge.remove_id, next.id, mir_op_int_sub_checked(), wrapped.id, 0, 0, next_index.id, next_p.id, fail.id, "")
    let next_probes = try lower_add_typed_result(d, wrapped_sub.state, bridge.remove_id, next.id, mir_type_u64())
    let probes_added = try lower_add_instr(d, next_probes.state, bridge.remove_id, next.id, mir_op_int_add_checked(), next_probes.id, 0, 0, probes_param.id, one.id, fail.id, "")
    current = try lower_jump_two(d, probes_added.state, bridge.remove_id, next.id, loop.id, wrapped.id, next_probes.id)
    let no = try lower_helper_bool(d, current, bridge.remove_id, absent.id, 0, checked_type * 100 + 57)
    return lower_helper_return(d, no.state, bridge.remove_id, absent.id, no.id)
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

fn lower_source_range_valid(source_state: State, source: U64, start: U64, end: U64, nonempty: Bool) -> Bool {
    if source >= __s0_buffer_len(SourceRec, source_state.sources) || start > end { return false }
    let source_rec = __s0_buffer_get(SourceRec, source_state.sources, source)
    if end > source_rec.text_end - source_rec.text_start || (nonempty && start == end) { return false }
    return true
}

fn lower_builtin_model_valid(store: CheckStore, annotation: CallAnnotationRec, expression: CheckedExprRec) -> Bool {
    if annotation.kind != 5 || annotation.target != 0 || annotation.variant_use != 0 || annotation.builtin == 0 || annotation.builtin > 16 { return false }
    var expected_count: U64 = 1
    if annotation.builtin == 2 || annotation.builtin == 11 || annotation.builtin == 15 { expected_count = 3 }
    if annotation.builtin == 3 || annotation.builtin == 6 || annotation.builtin == 12 || annotation.builtin == 14 || annotation.builtin == 16 { expected_count = 2 }
    if expression.child_count != expected_count { return false }
    let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
    let first_type = lower_builtin_child_type(store, expression, 0)
    if first_type == 0 { return false }
    let first = __s0_buffer_get(CheckedTypeRec, store.types, first_type - 1)
    if annotation.builtin == 1 { return first.kind == 8 && result.kind == 1 && result.target == 9 }
    if annotation.builtin == 2 {
        let lo = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1)
        let hi = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 2) - 1)
        return first.kind == 8 && annotation.checked_type == first_type && lo.kind == 1 && lo.target == 9 && hi.kind == 1 && hi.target == 9
    }
    if annotation.builtin == 3 { return first.kind == 3 && result.kind == 8 && __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1).target == 9 }
    if annotation.builtin == 4 { return first.kind == 3 && result.kind == 3 }
    if annotation.builtin == 5 { return first.kind == 3 && result.kind == 4 }
    if annotation.builtin == 6 { return first.kind == 3 && __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1).kind == 4 && result.kind == 1 && result.target == 12 }
    if annotation.builtin == 7 { return first.kind == 3 && result.kind == 1 && result.target == 12 }
    if annotation.builtin == 8 { return first.kind == 3 && result.kind == 11 }
    if annotation.builtin >= 9 && annotation.builtin <= 13 {
        var buffer_ordinal: U64 = 0
        if annotation.builtin == 9 { buffer_ordinal = 99 }
        if annotation.builtin == 11 { buffer_ordinal = 1 }
        var buffer_type = result
        if buffer_ordinal != 99 { buffer_type = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, buffer_ordinal) - 1) }
        if annotation.builtin == 9 {
            if first.kind != 3 || result.kind != 10 { return false }
            buffer_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, result.first_arg - 1) - 1)
        }
        if buffer_type.kind != 13 { return false }
        let element = __s0_buffer_get(U64, store.type_args, buffer_type.first_arg - 1)
        if annotation.builtin == 10 { return result.kind == 1 && result.target == 9 }
        if annotation.builtin == 11 { return lower_builtin_child_type(store, expression, 2) == element && result.kind == 10 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == lower_builtin_child_type(store, expression, 1) }
        if annotation.builtin == 12 { return annotation.checked_type == element }
        if annotation.builtin == 13 { return result.kind == 8 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == element }
        return true
    }
    if first.kind != 11 { return false }
    let key = __s0_buffer_get(U64, store.type_args, first.first_arg - 1)
    let value = __s0_buffer_get(U64, store.type_args, first.first_arg)
    if lower_builtin_child_type(store, expression, 1) != key { return false }
    if annotation.builtin == 14 { return result.kind == 9 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == value }
    if annotation.builtin == 15 { return lower_builtin_child_type(store, expression, 2) == value && result.kind == 1 && result.target == 12 }
    return result.kind == 1 && result.target == 1
}

fn lower_builtin_child_type(store: CheckStore, expression: CheckedExprRec, ordinal: U64) -> U64 {
    if ordinal >= expression.child_count || expression.first_child == 0 || expression.first_child - 1 + ordinal >= __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return 0 }
    let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
    if child == 0 || child > __s0_buffer_len(CheckedExprRec, store.expressions) { return 0 }
    return __s0_buffer_get(CheckedExprRec, store.expressions, child - 1).checked_type
}

fn lower_model_valid(source_state: State, store: CheckStore, spans: __s0_Buffer(CheckedSpanRec)) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedSpanRec, spans) {
        let item = __s0_buffer_get(CheckedSpanRec, spans, at)
        if !lower_source_range_valid(source_state, item.source, item.start, item.end, true) { return false }
        if item.name_end == 0 { if item.name_start != 0 { return false } } else {
            if !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) || item.name_start < item.start || item.name_end > item.end { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let item = __s0_buffer_get(SymbolRec, store.symbols, at)
        if item.kind != 1 && item.kind != 2 && item.kind != 3 && item.kind != 12 && item.kind != 13 { return false }
        if item.node == 0 || item.node > __s0_buffer_len(CheckedSpanRec, spans) { return false }
        if !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        if item.kind == 13 {
            if item.declaration == 0 || item.declaration > __s0_buffer_len(SymbolRec, store.symbols) || item.declaration > at || __s0_buffer_get(SymbolRec, store.symbols, item.declaration - 1).kind != 12 { return false }
            if item.instance_arg_count == 0 || item.first_instance_arg == 0 || item.first_instance_arg - 1 + item.instance_arg_count > __s0_buffer_len(U64, store.type_args) { return false }
            if item.instance_arg_count != __s0_buffer_get(SymbolRec, store.symbols, item.declaration - 1).type_arity { return false }
            if item.discovery_parent != 0 && (item.discovery_parent > at || __s0_buffer_get(SymbolRec, store.symbols, item.discovery_parent - 1).declaration == 0) { return false }
        } else {
            if item.kind == 12 && item.type_arity == 0 {
                if item.declaration != at + 1 { return false }
            } else { if item.declaration != 0 { return false } }
            if item.first_instance_arg != 0 || item.instance_arg_count != 0 { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let item = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if item.kind != 1 && item.kind != 3 && item.kind != 4 && item.kind != 5 && item.kind != 6 && item.kind != 7 && item.kind != 8 && item.kind != 9 && item.kind != 10 && item.kind != 11 && item.kind != 12 && item.kind != 13 { return false }
        if item.syntax != 0 { return false }
        if item.kind == 1 && (item.target == 0 || item.target > 12 || item.arg_count != 0) { return false }
        if (item.kind == 3 || item.kind == 4 || item.kind == 5) && (item.target != 0 || item.arg_count != 0) { return false }
        if item.kind == 6 && (item.target == 0 || item.target > __s0_buffer_len(TypeParamRec, store.type_params) || item.arg_count != 0) { return false }
        if item.kind == 7 && (item.target == 0 || item.target > __s0_buffer_len(SymbolRec, store.symbols) || (__s0_buffer_get(SymbolRec, store.symbols, item.target - 1).kind != 2 && __s0_buffer_get(SymbolRec, store.symbols, item.target - 1).kind != 3)) { return false }
        if item.kind >= 8 && item.kind <= 13 && item.target != 0 { return false }
        if item.arg_count == 0 && item.first_arg != 0 { return false }
        if item.arg_count != 0 {
            if item.first_arg == 0 || item.first_arg - 1 + item.arg_count > __s0_buffer_len(U64, store.type_args) { return false }
            var ordinal: U64 = 0
            while ordinal < item.arg_count {
                let argument = __s0_buffer_get(U64, store.type_args, item.first_arg - 1 + ordinal)
                if argument == 0 || argument > at { return false }
                ordinal = ordinal + 1
            }
        }
        if item.kind == 7 && item.arg_count != __s0_buffer_get(SymbolRec, store.symbols, item.target - 1).type_arity { return false }
        if (item.kind == 8 || item.kind == 9 || item.kind == 12 || item.kind == 13) && item.arg_count != 1 { return false }
        if (item.kind == 10 || item.kind == 11) && item.arg_count != 2 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let item = __s0_buffer_get(SymbolRec, store.symbols, at)
        if item.kind == 13 {
            var instance_ordinal: U64 = 0
            while instance_ordinal < item.instance_arg_count {
                if !lower_type_concrete(store, __s0_buffer_get(U64, store.type_args, item.first_instance_arg - 1 + instance_ordinal)) { return false }
                instance_ordinal = instance_ordinal + 1
            }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let item = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1).kind == 13 || item.node == 0 || item.node > __s0_buffer_len(CheckedSpanRec, spans) || !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        var parameter_count: U64 = 0
        var parameter_at: U64 = 0
        while parameter_at < __s0_buffer_len(TypeParamRec, store.type_params) {
            if __s0_buffer_get(TypeParamRec, store.type_params, parameter_at).owner == at + 1 { parameter_count = parameter_count + 1 }
            parameter_at = parameter_at + 1
        }
        if symbol.kind != 13 && parameter_count != symbol.type_arity { return false }
        if symbol.kind == 13 && parameter_count != 0 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let item = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.role == 0 || item.role > 8 || item.node == 0 || item.node > __s0_buffer_len(CheckedSpanRec, spans) { return false }
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        let named = item.role == 1 || item.role == 2 || item.role == 5 || item.role == 7
        if named && !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        if !named && item.name_end == 0 && item.name_start != 0 { return false }
        if !named && item.name_end != 0 && !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        if item.role == 1 && symbol.kind != 2 { return false }
        if item.role == 2 && symbol.kind != 3 { return false }
        if (item.role == 3 || item.role == 4) && symbol.kind != 1 { return false }
        if (item.role == 5 || item.role == 6) && symbol.kind != 12 { return false }
        if (item.role == 7 || item.role == 8) && symbol.kind != 13 { return false }
        var prior_uses: U64 = 0
        var prior_at: U64 = 0
        while prior_at < at {
            let prior = __s0_buffer_get(DeclTypeUseRec, store.uses, prior_at)
            if prior.owner == item.owner && prior.role == item.role { prior_uses = prior_uses + 1 }
            prior_at = prior_at + 1
        }
        if item.ordinal != prior_uses { return false }
        if item.role == 2 && item.syntax == 0 {
            if item.checked_type != 0 { return false }
        } else {
            if item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.checked_type == 0 || item.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
            if (item.role == 3 || item.role == 4 || item.role == 7 || item.role == 8 || ((item.role == 1 || item.role == 2 || item.role == 5 || item.role == 6) && symbol.type_arity == 0)) && !lower_type_concrete(store, item.checked_type) { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(LocalRec, store.locals) {
        let item = __s0_buffer_get(LocalRec, store.locals, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.kind == 0 || item.kind > 2 || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.mutable > 1 || !lower_type_concrete(store, item.checked_type) || !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13) { return false }
        if item.kind == 1 && item.mutable != 0 { return false }
        var environment_count: U64 = 0
        var environment_at: U64 = 0
        while environment_at < __s0_buffer_len(EnvironmentRec, store.environments) {
            if __s0_buffer_get(EnvironmentRec, store.environments, environment_at).binding == at + 1 { environment_count = environment_count + 1 }
            environment_at = environment_at + 1
        }
        if environment_count != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(EnvironmentRec, store.environments) {
        let item = __s0_buffer_get(EnvironmentRec, store.environments, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.parent > at { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13) { return false }
        if item.parent != 0 && __s0_buffer_get(EnvironmentRec, store.environments, item.parent - 1).owner != item.owner { return false }
        if item.binding != 0 && (item.binding > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.binding - 1).owner != item.owner) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
        let item = __s0_buffer_get(CheckedExprChildRec, store.expression_children, at)
        if item.expression == 0 || item.expression > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CallAnnotationRec, store.call_annotations) {
        let item = __s0_buffer_get(CallAnnotationRec, store.call_annotations, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.kind == 0 || item.kind > 5 || !lower_type_concrete(store, item.checked_type) { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13) { return false }
        if item.kind == 5 {
            if item.target != 0 || item.variant_use != 0 || item.builtin == 0 || item.builtin > 16 { return false }
            at = at + 1
        } else {
        if item.target == 0 || item.target > __s0_buffer_len(SymbolRec, store.symbols) || item.builtin != 0 { return false }
        let target = __s0_buffer_get(SymbolRec, store.symbols, item.target - 1)
        if item.kind == 1 {
            if !((target.kind == 12 && target.type_arity == 0) || target.kind == 13) { return false }
            var result_role: U64 = 6
            if target.kind == 13 { result_role = 8 }
            let result_use = lower_use_by_role(store, item.target, result_role, 0)
            if result_use == 0 || __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1).checked_type != item.checked_type { return false }
        }
        if item.kind == 2 {
            if target.kind != 1 { return false }
            let result_use = lower_use_by_role(store, item.target, 4, 0)
            if result_use == 0 || __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1).checked_type != item.checked_type { return false }
        }
        if item.kind == 3 {
            if target.kind != 2 { return false }
            let result_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if result_type.kind != 7 || result_type.target != item.target { return false }
        }
        if item.kind == 4 {
            if target.kind != 3 || item.variant_use == 0 || item.variant_use > __s0_buffer_len(DeclTypeUseRec, store.uses) { return false }
            let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, item.variant_use - 1)
            if variant.owner != item.target || variant.role != 2 { return false }
            let result_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if result_type.kind != 7 || result_type.target != item.target { return false }
        } else { if item.variant_use != 0 { return false } }
        at = at + 1
        }
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let item = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_type_concrete(store, item.checked_type) { return false }
        if item.kind == 0 || item.kind > 21 { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13) { return false }
        if item.left != 0 || item.right != 0 { return false }
        if (item.child_count == 0 && item.first_child != 0) || (item.child_count != 0 && item.first_child == 0) { return false }
        if item.child_count != 0 && item.first_child - 1 + item.child_count > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return false }
        var child_at: U64 = 0
        while child_at < item.child_count {
            let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1 + child_at).expression
            if child == 0 || child > at || __s0_buffer_get(CheckedExprRec, store.expressions, child - 1).owner != item.owner { return false }
            child_at = child_at + 1
        }
        if item.site_kind > 8 || (item.site_kind == 0 && item.site_syntax != 0) || (item.site_kind != 0 && item.site_syntax == 0) || item.site_syntax > __s0_buffer_len(CheckedSpanRec, spans) { return false }
        if item.kind == 1 || item.kind == 5 {
            if item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).owner != item.owner { return false }
        }
        if item.kind == 1 && (__s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).kind != 1 || __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).checked_type != item.checked_type) { return false }
        if item.kind == 5 && (__s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).kind != 2 || __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).checked_type != item.checked_type) { return false }
        if item.kind >= 1 && item.kind <= 5 && item.child_count != 0 { return false }
        if item.kind == 2 && item.bool_value > 1 { return false }
        if item.kind != 2 && item.bool_value != 0 { return false }
        if item.kind == 2 {
            let literal_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if literal_type.kind != 1 || literal_type.target != 1 { return false }
        }
        if item.kind == 3 {
            let literal_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if literal_type.kind != 1 || literal_type.target < 2 || literal_type.target > 9 { return false }
        }
        if item.kind == 4 {
            let literal_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if literal_type.kind != 8 { return false }
            let element_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, literal_type.first_arg - 1) - 1)
            if element_type.kind != 1 || element_type.target != 6 { return false }
        }
        if item.kind == 6 && (item.child_count != 1 || (item.operator != 1 && item.operator != 2)) { return false }
        if item.kind == 7 && (item.child_count != 2 || item.operator < 3 || item.operator > 17) { return false }
        if item.kind != 6 && item.kind != 7 && item.operator != 0 { return false }
        if item.kind == 6 {
            let child = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            if child.checked_type != item.checked_type { return false }
            if item.operator == 2 {
                let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
                if checked_type.kind != 1 || checked_type.target != 1 { return false }
            }
        }
        if item.kind == 7 {
            let left = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            let right = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child).expression - 1)
            if left.checked_type != right.checked_type { return false }
            if item.operator >= 3 && item.operator <= 9 && item.checked_type != left.checked_type { return false }
            if item.operator >= 10 {
                let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
                if checked_type.kind != 1 || checked_type.target != 1 { return false }
            }
            if item.operator >= 16 && left.checked_type != item.checked_type { return false }
        }
        if item.kind >= 8 && item.kind <= 11 {
            if item.annotation == 0 || item.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return false }
            let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, item.annotation - 1)
            var annotation_kind: U64 = 1
            if item.kind == 9 { annotation_kind = 3 }
            if item.kind == 10 { annotation_kind = 4 }
            if item.kind == 11 { annotation_kind = 2 }
            if annotation.owner != item.owner || annotation.checked_type != item.checked_type || annotation.kind != annotation_kind { return false }
            var argument_role: U64 = 0
            if annotation.kind == 1 {
                argument_role = 5
                if __s0_buffer_get(SymbolRec, store.symbols, annotation.target - 1).kind == 13 { argument_role = 7 }
            }
            if annotation.kind == 2 { argument_role = 3 }
            if annotation.kind == 3 { argument_role = 1 }
            var argument_count: U64 = 0
            if annotation.kind == 4 {
                if __s0_buffer_get(DeclTypeUseRec, store.uses, annotation.variant_use - 1).checked_type != 0 { argument_count = 1 }
            } else {
                var use_at: U64 = 0
                while use_at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
                    let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_at)
                    if use.owner == annotation.target && use.role == argument_role { argument_count = argument_count + 1 }
                    use_at = use_at + 1
                }
            }
            if item.child_count != argument_count { return false }
            var argument_at: U64 = 0
            while argument_at < argument_count {
                var expected_type: U64 = 0
                if annotation.kind == 4 { expected_type = __s0_buffer_get(DeclTypeUseRec, store.uses, annotation.variant_use - 1).checked_type } else {
                    let argument_use = lower_use_by_role(store, annotation.target, argument_role, argument_at)
                    if argument_use == 0 { return false }
                    expected_type = __s0_buffer_get(DeclTypeUseRec, store.uses, argument_use - 1).checked_type
                }
                let argument = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1 + argument_at).expression - 1)
                if lower_type_concrete(store, expected_type) && argument.checked_type != expected_type { return false }
                argument_at = argument_at + 1
            }
        } else {
            if item.kind == 18 {
                if item.annotation == 0 || item.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return false }
                let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, item.annotation - 1)
                if annotation.owner != item.owner || annotation.checked_type != item.checked_type || !lower_builtin_model_valid(store, annotation, item) { return false }
            } else { if item.annotation != 0 { return false } }
        }
        if item.kind == 12 {
            if item.child_count != 1 || item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(CheckedMatchRec, store.control.matches) { return false }
            let checked = __s0_buffer_get(CheckedMatchRec, store.control.matches, item.parameter_use - 1)
            let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
            if checked.owner != item.owner || checked.syntax != item.syntax || checked.scrutinee != child || checked.checked_type != item.checked_type { return false }
        }
        if item.kind == 13 {
            if item.child_count != 1 || item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(CheckedTryRec, store.control.tries) { return false }
            let checked = __s0_buffer_get(CheckedTryRec, store.control.tries, item.parameter_use - 1)
            let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
            if checked.owner != item.owner || checked.syntax != item.syntax || checked.expression != child || checked.ok_type != item.checked_type { return false }
        }
        if item.kind == 14 && item.child_count != 0 { return false }
        if item.kind >= 15 && item.kind <= 17 && item.child_count != 1 { return false }
        if item.kind >= 14 && item.kind <= 17 {
            let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if (item.kind == 14 || item.kind == 15) && checked_type.kind != 9 { return false }
            if (item.kind == 16 || item.kind == 17) && checked_type.kind != 10 { return false }
            if item.kind >= 15 {
                var type_ordinal: U64 = 0
                if item.kind == 17 { type_ordinal = 1 }
                let expected_type = __s0_buffer_get(U64, store.type_args, checked_type.first_arg - 1 + type_ordinal)
                let child = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
                if child.checked_type != expected_type { return false }
            }
        }
        if item.kind == 19 {
            if item.child_count != 2 { return false }
            let base = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            let index = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child).expression - 1)
            let base_type = __s0_buffer_get(CheckedTypeRec, store.types, base.checked_type - 1)
            let index_type = __s0_buffer_get(CheckedTypeRec, store.types, index.checked_type - 1)
            if base_type.kind != 8 || __s0_buffer_get(U64, store.type_args, base_type.first_arg - 1) != item.checked_type || index_type.kind != 1 || index_type.target != 9 { return false }
        }
        if item.kind == 20 {
            if item.child_count != 0 { return false }
            let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if checked_type.kind != 1 || (checked_type.target != 10 && checked_type.target != 11) { return false }
        }
        if item.kind == 21 {
            if item.child_count != 1 || item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(DeclTypeUseRec, store.uses) || __s0_buffer_get(DeclTypeUseRec, store.uses, item.parameter_use - 1).role != 1 { return false }
            let field = __s0_buffer_get(DeclTypeUseRec, store.uses, item.parameter_use - 1)
            let base = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            let base_type = __s0_buffer_get(CheckedTypeRec, store.types, base.checked_type - 1)
            if base_type.kind != 7 || base_type.target != field.owner { return false }
            if lower_type_concrete(store, field.checked_type) && field.checked_type != item.checked_type { return false }
        }
        if item.kind != 1 && item.kind != 5 && item.kind != 12 && item.kind != 13 && item.kind != 21 && item.parameter_use != 0 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
        var child_owners: U64 = 0
        var expression_at: U64 = 0
        while expression_at < __s0_buffer_len(CheckedExprRec, store.expressions) {
            let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_at)
            if expression.child_count != 0 && at + 1 >= expression.first_child && at + 1 < expression.first_child + expression.child_count { child_owners = child_owners + 1 }
            expression_at = expression_at + 1
        }
        if child_owners != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CallAnnotationRec, store.call_annotations) {
        var annotation_owners: U64 = 0
        var expression_at: U64 = 0
        while expression_at < __s0_buffer_len(CheckedExprRec, store.expressions) {
            if __s0_buffer_get(CheckedExprRec, store.expressions, expression_at).annotation == at + 1 { annotation_owners = annotation_owners + 1 }
            expression_at = expression_at + 1
        }
        if annotation_owners != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedPlaceRec, store.control.places) {
        let item = __s0_buffer_get(CheckedPlaceRec, store.control.places, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.kind == 0 || item.kind > 4 || item.root == 0 || item.root > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.root - 1).owner != item.owner || !lower_type_concrete(store, item.checked_type) { return false }
        let root = __s0_buffer_get(LocalRec, store.locals, item.root - 1)
        if item.kind == 1 && (item.field != 0 || item.index != 0) { return false }
        if item.kind == 1 && item.checked_type != root.checked_type { return false }
        if (item.kind == 2 || item.kind == 4) && (item.field == 0 || item.field > __s0_buffer_len(DeclTypeUseRec, store.uses) || __s0_buffer_get(DeclTypeUseRec, store.uses, item.field - 1).role != 1) { return false }
        var base_type = __s0_buffer_get(CheckedTypeRec, store.types, root.checked_type - 1)
        if (item.kind == 3 || item.kind == 4) {
            if item.index == 0 || item.index > __s0_buffer_len(CheckedExprRec, store.expressions) || __s0_buffer_get(CheckedExprRec, store.expressions, item.index - 1).owner != item.owner { return false }
            if base_type.kind != 8 { return false }
            let element_type = __s0_buffer_get(U64, store.type_args, base_type.first_arg - 1)
            if item.kind == 3 && item.checked_type != element_type { return false }
            base_type = __s0_buffer_get(CheckedTypeRec, store.types, element_type - 1)
            if __s0_buffer_get(CheckedExprRec, store.expressions, item.index - 1).site_kind != 7 { return false }
            let index_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(CheckedExprRec, store.expressions, item.index - 1).checked_type - 1)
            if index_type.kind != 1 || index_type.target != 9 { return false }
        } else { if item.index != 0 { return false } }
        if item.kind == 2 || item.kind == 4 {
            let field = __s0_buffer_get(DeclTypeUseRec, store.uses, item.field - 1)
            if base_type.kind != 7 || base_type.target != field.owner { return false }
            if lower_type_concrete(store, field.checked_type) && field.checked_type != item.checked_type { return false }
        }
        if (item.kind == 1 || item.kind == 3) && item.field != 0 { return false }
        var place_owners: U64 = 0
        var statement_at: U64 = 0
        while statement_at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
            if __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_at).place == at + 1 { place_owners = place_owners + 1 }
            statement_at = statement_at + 1
        }
        if place_owners != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
        let item = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at)
        if item.statement == 0 || item.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) || item.next > at { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
        if __s0_buffer_get(CheckedBlockRec, store.control.blocks, at).statements > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
        let item = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at)
        if item.statement == 0 || item.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) || item.next > at { return false }
        var link_owners: U64 = 0
        var block_at: U64 = 0
        while block_at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
            var link = __s0_buffer_get(CheckedBlockRec, store.control.blocks, block_at).statements
            while link != 0 {
                if link == at + 1 { link_owners = link_owners + 1 }
                link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link - 1).next
            }
            block_at = block_at + 1
        }
        if link_owners != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let item = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.kind == 0 || item.kind > 10 || !lower_environment_valid(store, item.owner, item.environment) { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13) { return false }
        var statement_owners: U64 = 0
        var link_at: U64 = 0
        while link_at < __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
            if __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link_at).statement == at + 1 { statement_owners = statement_owners + 1 }
            link_at = link_at + 1
        }
        if statement_owners != 1 { return false }
        var expression_site: U64 = 0
        var needs_expression = false
        var needs_binding = false
        var needs_block = false
        if item.kind == 1 || item.kind == 2 {
            expression_site = 1
            needs_expression = true
            needs_binding = true
        }
        if item.kind == 3 {
            expression_site = 2
            needs_expression = true
        }
        if item.kind == 4 { expression_site = 3 }
        if item.kind == 5 {
            expression_site = 4
            needs_expression = true
        }
        if item.kind == 6 { needs_block = true }
        if item.kind == 7 || item.kind == 8 {
            expression_site = 5
            needs_expression = true
            needs_block = true
        }
        if item.kind == 9 {
            expression_site = 6
            needs_expression = true
            needs_binding = true
            needs_block = true
        }
        if item.kind == 10 {
            expression_site = 8
            needs_expression = true
            needs_binding = true
        }
        if needs_expression && (item.expression == 0 || item.expression > __s0_buffer_len(CheckedExprRec, store.expressions)) { return false }
        if !needs_expression && item.kind != 4 && item.expression != 0 { return false }
        if item.expression != 0 {
            if item.expression > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
            let expression = __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1)
            if expression.owner != item.owner || expression.site_kind != expression_site || expression.site_syntax != item.syntax { return false }
        }
        if item.kind == 3 {
            if item.place == 0 || item.place > __s0_buffer_len(CheckedPlaceRec, store.control.places) { return false }
            let place = __s0_buffer_get(CheckedPlaceRec, store.control.places, item.place - 1)
            if place.owner != item.owner || place.checked_type != __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type { return false }
        } else { if item.place != 0 { return false } }
        if needs_binding {
            if item.binding == 0 || item.binding > __s0_buffer_len(LocalRec, store.locals) { return false }
            let binding = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
            if binding.owner != item.owner || binding.kind != 2 || binding.syntax != item.syntax { return false }
            if item.kind == 1 && binding.mutable != 0 { return false }
            if item.kind == 2 && binding.mutable != 1 { return false }
            if item.kind == 10 && binding.checked_type != __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type { return false }
        } else { if item.binding != 0 { return false } }
        if needs_block {
            if item.body == 0 || item.body > __s0_buffer_len(CheckedBlockRec, store.control.blocks) || __s0_buffer_get(CheckedBlockRec, store.control.blocks, item.body - 1).owner != item.owner { return false }
        }
        if item.kind == 10 {
            if item.body == 0 || item.body > __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) { return false }
            let cleanup = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, item.body - 1)
            if cleanup.owner != item.owner || cleanup.syntax != item.syntax || cleanup.environment != item.environment || cleanup.binding != item.binding || cleanup.initializer != item.expression { return false }
        }
        if !needs_block && item.kind != 10 && item.body != 0 { return false }
        if item.kind == 7 {
            if item.alternative != 0 && (item.alternative > __s0_buffer_len(CheckedBlockRec, store.control.blocks) || __s0_buffer_get(CheckedBlockRec, store.control.blocks, item.alternative - 1).owner != item.owner) { return false }
        } else { if item.alternative != 0 { return false } }
        if item.kind == 7 || item.kind == 8 {
            let condition_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type - 1)
            if condition_type.kind != 1 || condition_type.target != 1 { return false }
        }
        if item.kind == 9 {
            let sequence = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type - 1)
            if sequence.kind != 8 || __s0_buffer_get(LocalRec, store.locals, item.binding - 1).checked_type != __s0_buffer_get(U64, store.type_args, sequence.first_arg - 1) { return false }
        }
        if item.kind == 1 || item.kind == 2 {
            if __s0_buffer_get(LocalRec, store.locals, item.binding - 1).checked_type != __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type { return false }
        }
        if item.kind == 4 {
            var result_role: U64 = 6
            if owner.kind == 13 { result_role = 8 }
            let result_use = lower_use_by_role(store, item.owner, result_role, 0)
            if result_use == 0 { return false }
            let result_type = __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1).checked_type
            if item.expression == 0 {
                let checked_result = __s0_buffer_get(CheckedTypeRec, store.types, result_type - 1)
                if checked_result.kind != 1 || checked_result.target != 12 { return false }
            } else { if __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type != result_type { return false } }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
        let item = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_environment_valid(store, item.owner, item.environment) || item.statements > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) || item.guaranteed_return > 1 { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13) { return false }
        var parent_count: U64 = 0
        var statement_at: U64 = 0
        while statement_at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
            let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_at)
            if statement.body == at + 1 && statement.kind != 10 { parent_count = parent_count + 1 }
            if statement.alternative == at + 1 { parent_count = parent_count + 1 }
            statement_at = statement_at + 1
        }
        if parent_count > 1 { return false }
        if parent_count == 0 {
            var owner_roots: U64 = 0
            var root_at: U64 = 0
            while root_at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
                let candidate = __s0_buffer_get(CheckedBlockRec, store.control.blocks, root_at)
                if candidate.owner == item.owner {
                    var candidate_parents: U64 = 0
                    statement_at = 0
                    while statement_at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_at)
                        if (statement.body == root_at + 1 && statement.kind != 10) || statement.alternative == root_at + 1 { candidate_parents = candidate_parents + 1 }
                        statement_at = statement_at + 1
                    }
                    if candidate_parents == 0 { owner_roots = owner_roots + 1 }
                }
                root_at = root_at + 1
            }
            if owner_roots != 1 { return false }
        }
        var link = item.statements
        while link != 0 {
            let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link - 1).statement - 1)
            if statement.owner != item.owner { return false }
            link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link - 1).next
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let owner = __s0_buffer_get(SymbolRec, store.symbols, at)
        if (owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13 {
            var root_count: U64 = 0
            var block_at: U64 = 0
            while block_at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
                let block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, block_at)
                if block.owner == at + 1 {
                    var parent_count: U64 = 0
                    var statement_at: U64 = 0
                    while statement_at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_at)
                        if (statement.body == block_at + 1 && statement.kind != 10) || statement.alternative == block_at + 1 { parent_count = parent_count + 1 }
                        statement_at = statement_at + 1
                    }
                    if parent_count == 0 { root_count = root_count + 1 }
                }
                block_at = block_at + 1
            }
            if root_count != 1 { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchRec, store.control.matches) {
        let item = __s0_buffer_get(CheckedMatchRec, store.control.matches, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.scrutinee == 0 || item.scrutinee > __s0_buffer_len(CheckedExprRec, store.expressions) || !lower_type_concrete(store, item.scrutinee_type) || !lower_type_concrete(store, item.checked_type) || item.arm_count == 0 || item.first_arm == 0 || item.first_arm - 1 + item.arm_count > __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !((owner.kind == 12 && owner.type_arity == 0) || owner.kind == 13) { return false }
        let scrutinee = __s0_buffer_get(CheckedExprRec, store.expressions, item.scrutinee - 1)
        if scrutinee.owner != item.owner || scrutinee.checked_type != item.scrutinee_type { return false }
        var match_owners: U64 = 0
        var expression_at: U64 = 0
        while expression_at < __s0_buffer_len(CheckedExprRec, store.expressions) {
            let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_at)
            if expression.kind == 12 && expression.parameter_use == at + 1 { match_owners = match_owners + 1 }
            expression_at = expression_at + 1
        }
        if match_owners != 1 { return false }
        var ordinal: U64 = 0
        while ordinal < item.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, item.first_arm - 1 + ordinal)
            if arm.owner != item.owner || arm.checked_match != at + 1 { return false }
            var prior_ordinal: U64 = 0
            while prior_ordinal < ordinal {
                let prior = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, item.first_arm - 1 + prior_ordinal)
                if arm.variant_kind == prior.variant_kind && arm.variant_use == prior.variant_use { return false }
                prior_ordinal = prior_ordinal + 1
            }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) {
        let item = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.checked_match == 0 || item.checked_match > __s0_buffer_len(CheckedMatchRec, store.control.matches) || item.variant_kind > 7 || !lower_environment_valid(store, item.owner, item.environment) || item.body == 0 || item.body > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
        let checked_match = __s0_buffer_get(CheckedMatchRec, store.control.matches, item.checked_match - 1)
        let body = __s0_buffer_get(CheckedExprRec, store.expressions, item.body - 1)
        if checked_match.owner != item.owner || body.owner != item.owner || body.checked_type != checked_match.checked_type { return false }
        var arm_owners: U64 = 0
        var match_at: U64 = 0
        while match_at < __s0_buffer_len(CheckedMatchRec, store.control.matches) {
            let candidate = __s0_buffer_get(CheckedMatchRec, store.control.matches, match_at)
            if candidate.arm_count != 0 && at + 1 >= candidate.first_arm && at + 1 < candidate.first_arm + candidate.arm_count { arm_owners = arm_owners + 1 }
            match_at = match_at + 1
        }
        if arm_owners != 1 { return false }
        let scrutinee_type = __s0_buffer_get(CheckedTypeRec, store.types, checked_match.scrutinee_type - 1)
        var payload_type: U64 = 0
        if item.variant_kind == 0 {
            if scrutinee_type.kind != 7 || item.variant_use == 0 || item.variant_use > __s0_buffer_len(DeclTypeUseRec, store.uses) { return false }
            let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, item.variant_use - 1)
            if variant.owner != scrutinee_type.target || variant.role != 2 { return false }
            payload_type = variant.checked_type
        } else {
            if item.variant_use != 0 { return false }
            if item.variant_kind == 1 || item.variant_kind == 2 {
                if scrutinee_type.kind != 9 { return false }
                if item.variant_kind == 2 { payload_type = __s0_buffer_get(U64, store.type_args, scrutinee_type.first_arg - 1) }
            }
            if item.variant_kind == 3 || item.variant_kind == 4 {
                if scrutinee_type.kind != 10 { return false }
                var payload_ordinal: U64 = 0
                if item.variant_kind == 4 { payload_ordinal = 1 }
                payload_type = __s0_buffer_get(U64, store.type_args, scrutinee_type.first_arg - 1 + payload_ordinal)
            }
            if (item.variant_kind == 5 || item.variant_kind == 6) && scrutinee_type.kind != 5 { return false }
        }
        if payload_type == 0 {
            if item.binding != 0 { return false }
        } else {
            if item.binding == 0 || item.binding > __s0_buffer_len(LocalRec, store.locals) { return false }
            let binding = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
            if binding.owner != item.owner || binding.kind != 2 { return false }
            if lower_type_concrete(store, payload_type) && binding.checked_type != payload_type { return false }
            var binding_active = false
            var environment = item.environment
            while environment != 0 {
                let active = __s0_buffer_get(EnvironmentRec, store.environments, environment - 1)
                if active.binding == item.binding { binding_active = true }
                environment = active.parent
            }
            if !binding_active { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTryRec, store.control.tries) {
        let item = __s0_buffer_get(CheckedTryRec, store.control.tries, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.expression == 0 || item.expression > __s0_buffer_len(CheckedExprRec, store.expressions) || !lower_type_concrete(store, item.result_type) || !lower_type_concrete(store, item.ok_type) || !lower_type_concrete(store, item.error_type) { return false }
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1)
        let result = __s0_buffer_get(CheckedTypeRec, store.types, item.result_type - 1)
        if expression.owner != item.owner || expression.checked_type != item.result_type || result.kind != 10 || __s0_buffer_get(U64, store.type_args, result.first_arg - 1) != item.ok_type || __s0_buffer_get(U64, store.type_args, result.first_arg) != item.error_type { return false }
        var try_owners: U64 = 0
        var expression_at: U64 = 0
        while expression_at < __s0_buffer_len(CheckedExprRec, store.expressions) {
            let candidate = __s0_buffer_get(CheckedExprRec, store.expressions, expression_at)
            if candidate.kind == 13 && candidate.parameter_use == at + 1 { try_owners = try_owners + 1 }
            expression_at = expression_at + 1
        }
        if try_owners != 1 { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        var result_role: U64 = 6
        if owner.kind == 13 { result_role = 8 }
        let owner_result_use = lower_use_by_role(store, item.owner, result_role, 0)
        if owner_result_use == 0 { return false }
        let owner_result = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(DeclTypeUseRec, store.uses, owner_result_use - 1).checked_type - 1)
        if owner_result.kind != 10 || __s0_buffer_get(U64, store.type_args, owner_result.first_arg) != item.error_type { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let item = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_environment_valid(store, item.owner, item.environment) || item.binding == 0 || item.binding > __s0_buffer_len(LocalRec, store.locals) || item.callback == 0 || item.callback > __s0_buffer_len(SymbolRec, store.symbols) { return false }
        let binding = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
        if binding.owner != item.owner || binding.kind != 2 || binding.syntax != item.syntax || item.initializer == 0 || item.initializer > __s0_buffer_len(CheckedExprRec, store.expressions) || item.normal_exit != 1 || item.return_exit != 1 || item.try_exit != 1 { return false }
        let initializer = __s0_buffer_get(CheckedExprRec, store.expressions, item.initializer - 1)
        if initializer.owner != item.owner || initializer.checked_type != binding.checked_type || initializer.site_kind != 8 || initializer.site_syntax != item.syntax { return false }
        let callback = __s0_buffer_get(SymbolRec, store.symbols, item.callback - 1)
        if callback.kind != 12 || callback.type_arity != 0 || callback.declaration != item.callback { return false }
        let callback_parameter = lower_use_by_role(store, item.callback, 5, 0)
        let callback_result = lower_use_by_role(store, item.callback, 6, 0)
        if callback_parameter == 0 || callback_result == 0 || __s0_buffer_get(DeclTypeUseRec, store.uses, callback_parameter - 1).checked_type != binding.checked_type { return false }
        if lower_use_by_role(store, item.callback, 5, 1) != 0 { return false }
        let callback_result_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(DeclTypeUseRec, store.uses, callback_result - 1).checked_type - 1)
        if callback_result_type.kind != 1 || callback_result_type.target != 12 { return false }
        var environment_at: U64 = 0
        var activation_count: U64 = 0
        while environment_at < __s0_buffer_len(EnvironmentRec, store.environments) {
            let environment = __s0_buffer_get(EnvironmentRec, store.environments, environment_at)
            if environment.owner == item.owner && environment.parent == item.environment && environment.binding == item.binding { activation_count = activation_count + 1 }
            environment_at = environment_at + 1
        }
        if activation_count != 1 { return false }
        var cleanup_owners: U64 = 0
        var statement_at: U64 = 0
        while statement_at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
            let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_at)
            if statement.kind == 10 && statement.body == at + 1 { cleanup_owners = cleanup_owners + 1 }
            statement_at = statement_at + 1
        }
        if cleanup_owners != 1 { return false }
        var duplicate_count: U64 = 0
        var cleanup_at: U64 = 0
        while cleanup_at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
            let candidate = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, cleanup_at)
            if candidate.owner == item.owner && candidate.environment == item.environment && candidate.binding == item.binding { duplicate_count = duplicate_count + 1 }
            cleanup_at = cleanup_at + 1
        }
        if duplicate_count != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        var expression_owners: U64 = 0
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if expression.site_kind != 0 { expression_owners = expression_owners + 1 }
        var child_at: U64 = 0
        while child_at < __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
            if __s0_buffer_get(CheckedExprChildRec, store.expression_children, child_at).expression == at + 1 { expression_owners = expression_owners + 1 }
            child_at = child_at + 1
        }
        var arm_at: U64 = 0
        while arm_at < __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) {
            if __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, arm_at).body == at + 1 { expression_owners = expression_owners + 1 }
            arm_at = arm_at + 1
        }
        if expression_owners != 1 { return false }
        at = at + 1
    }
    return true
}

fn lower_checked(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore) -> Result(LowerResult, __s0_Error) {
    if __s0_buffer_len(CheckDiagRec, store.diagnostics) != 0 { return Ok(LowerBad) }
    if !lower_model_valid(source_state, store, spans) {
        return Ok(LowerBad)
    }
    let mir = try mir_store_new(d)
    let types = try __s0_buffer_new(LowerTypeMapRec, d)
    let owners = try __s0_buffer_new(LowerOwnerMapRec, d)
    let imports = try __s0_buffer_new(LowerOwnerMapRec, d)
    let bindings = try __s0_buffer_new(LowerBindingMapRec, d)
    let values = try __s0_buffer_new(LowerValueMapRec, d)
    let bridges = try __s0_buffer_new(LowerBridgeRec, d)
    var state = LowerState(mir: mir, types: types, owners: owners, imports: imports, bindings: bindings, values: values, bridges: bridges, valid: true)
    state = try lower_declarations(d, source_state, store, state)
    if !state.valid {
        return Ok(LowerBad)
    }
    state = try lower_functions(d, source_state, spans, store, state)
    if !state.valid {
        return Ok(LowerBad)
    }
    return Ok(LowerGood(state.mir))
}
