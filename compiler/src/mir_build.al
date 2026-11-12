// Append-only deterministic construction for the independent MIR 4 model.

fn mir_with_names(store: MirStore, names: __s0_Buffer(U8)) -> MirStore {
    return MirStore(names: names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_types(store: MirStore, types: __s0_Buffer(MirTypeRec)) -> MirStore {
    return MirStore(names: store.names, types: types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_type_parts(store: MirStore, parts: __s0_Buffer(MirTypePartRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_imports(store: MirStore, imports: __s0_Buffer(MirImportRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_constants(store: MirStore, constants: __s0_Buffer(MirConstRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_functions(store: MirStore, functions: __s0_Buffer(MirFunctionRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_params(store: MirStore, params: __s0_Buffer(MirParamRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_locals(store: MirStore, locals: __s0_Buffer(MirLocalRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_blocks(store: MirStore, blocks: __s0_Buffer(MirBlockRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_values(store: MirStore, values: __s0_Buffer(MirValueRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_places(store: MirStore, places: __s0_Buffer(MirPlaceRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_instructions(store: MirStore, instructions: __s0_Buffer(MirInstrRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_terminators(store: MirStore, terminators: __s0_Buffer(MirTermRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_operands(store: MirStore, operands: __s0_Buffer(MirOperandRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_bindings(store: MirStore, bindings: __s0_Buffer(MirBindingRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: bindings, binding_funcs: store.binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_binding_funcs(store: MirStore, binding_funcs: __s0_Buffer(MirBindingFnRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: binding_funcs, binding_consts: store.binding_consts)
}

fn mir_with_binding_consts(store: MirStore, binding_consts: __s0_Buffer(MirBindingConstRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands, bindings: store.bindings, binding_funcs: store.binding_funcs, binding_consts: binding_consts)
}

fn mir_new_operands(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec), blocks: __s0_Buffer(MirBlockRec), values: __s0_Buffer(MirValueRec), places: __s0_Buffer(MirPlaceRec), instructions: __s0_Buffer(MirInstrRec), terminators: __s0_Buffer(MirTermRec)) -> Result(MirStore, __s0_Error) {
    let operands = try __s0_buffer_new(MirOperandRec, d)
    let bindings = try __s0_buffer_new(MirBindingRec, d)
    let binding_funcs = try __s0_buffer_new(MirBindingFnRec, d)
    let binding_consts = try __s0_buffer_new(MirBindingConstRec, d)
    return Ok(MirStore(names: names, types: types, type_parts: parts, imports: imports, constants: constants, functions: functions, params: params, locals: locals, blocks: blocks, values: values, places: places, instructions: instructions, terminators: terminators, operands: operands, bindings: bindings, binding_funcs: binding_funcs, binding_consts: binding_consts))
}

fn mir_new_terminators(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec), blocks: __s0_Buffer(MirBlockRec), values: __s0_Buffer(MirValueRec), places: __s0_Buffer(MirPlaceRec), instructions: __s0_Buffer(MirInstrRec)) -> Result(MirStore, __s0_Error) {
    let terms = try __s0_buffer_new(MirTermRec, d)
    return mir_new_operands(d, names, types, parts, imports, constants, functions, params, locals, blocks, values, places, instructions, terms)
}

fn mir_new_instructions(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec), blocks: __s0_Buffer(MirBlockRec), values: __s0_Buffer(MirValueRec), places: __s0_Buffer(MirPlaceRec)) -> Result(MirStore, __s0_Error) {
    let instructions = try __s0_buffer_new(MirInstrRec, d)
    return mir_new_terminators(d, names, types, parts, imports, constants, functions, params, locals, blocks, values, places, instructions)
}

fn mir_new_places(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec), blocks: __s0_Buffer(MirBlockRec), values: __s0_Buffer(MirValueRec)) -> Result(MirStore, __s0_Error) {
    let places = try __s0_buffer_new(MirPlaceRec, d)
    return mir_new_instructions(d, names, types, parts, imports, constants, functions, params, locals, blocks, values, places)
}

fn mir_new_values(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec), blocks: __s0_Buffer(MirBlockRec)) -> Result(MirStore, __s0_Error) {
    let values = try __s0_buffer_new(MirValueRec, d)
    return mir_new_places(d, names, types, parts, imports, constants, functions, params, locals, blocks, values)
}

fn mir_new_blocks(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec)) -> Result(MirStore, __s0_Error) {
    let blocks = try __s0_buffer_new(MirBlockRec, d)
    return mir_new_values(d, names, types, parts, imports, constants, functions, params, locals, blocks)
}

fn mir_new_locals(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec)) -> Result(MirStore, __s0_Error) {
    let locals = try __s0_buffer_new(MirLocalRec, d)
    return mir_new_blocks(d, names, types, parts, imports, constants, functions, params, locals)
}

fn mir_new_params(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec)) -> Result(MirStore, __s0_Error) {
    let params = try __s0_buffer_new(MirParamRec, d)
    return mir_new_locals(d, names, types, parts, imports, constants, functions, params)
}

fn mir_new_functions(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec)) -> Result(MirStore, __s0_Error) {
    let functions = try __s0_buffer_new(MirFunctionRec, d)
    return mir_new_params(d, names, types, parts, imports, constants, functions)
}

fn mir_new_constants(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec)) -> Result(MirStore, __s0_Error) {
    let constants = try __s0_buffer_new(MirConstRec, d)
    return mir_new_functions(d, names, types, parts, imports, constants)
}

fn mir_new_imports(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec)) -> Result(MirStore, __s0_Error) {
    let imports = try __s0_buffer_new(MirImportRec, d)
    return mir_new_constants(d, names, types, parts, imports)
}

fn mir_new_parts(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec)) -> Result(MirStore, __s0_Error) {
    let parts = try __s0_buffer_new(MirTypePartRec, d)
    return mir_new_imports(d, names, types, parts)
}

fn mir_append_primitive(d: Domain, types: __s0_Buffer(MirTypeRec)) -> Result(__s0_Buffer(MirTypeRec), __s0_Error) {
    return __s0_buffer_append(MirTypeRec, d, types, MirTypeRec(kind: mir_type_kind_primitive(), name_start: 0, name_end: 0, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: 0, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar()))
}

fn mir_new_types(d: Domain, names: __s0_Buffer(U8)) -> Result(MirStore, __s0_Error) {
    var types = try __s0_buffer_new(MirTypeRec, d)
    var at: U64 = 0
    while at < mir_primitive_type_count() {
        types = try mir_append_primitive(d, types)
        at = at + 1
    }
    return mir_new_parts(d, names, types)
}

fn mir_store_new(d: Domain) -> Result(MirStore, __s0_Error) {
    let names = try __s0_buffer_new(U8, d)
    return mir_new_types(d, names)
}

fn mir_append_name(d: Domain, store: MirStore, name: __s0_String) -> Result(MirNameStep, __s0_Error) {
    var names = store.names
    let start = __s0_buffer_len(U8, names)
    var at: U64 = 0
    while at < len(name) {
        names = try __s0_buffer_append(U8, d, names, name[at])
        at = at + 1
    }
    return Ok(MirNameStep(store: mir_with_names(store, names), start: start, end: __s0_buffer_len(U8, names)))
}

fn mir_type_parts_equal(store: MirStore, first: U64, count: U64, parts: __s0_Buffer(U64)) -> Bool {
    if count != __s0_buffer_len(U64, parts) { return false }
    var at: U64 = 0
    while at < count {
        let prior = __s0_buffer_get(MirTypePartRec, store.type_parts, first - 1 + at)
        if prior.part_type != __s0_buffer_get(U64, parts, at) { return false }
        at = at + 1
    }
    return true
}

// Structural type kinds option..vec are interned by deterministic
// ascending scans.
// For unary and singleton types parts is empty; function types use ordered
// parameter Type IDs and result_type. Named aggregate/enum kinds are appended
// separately and are never structurally merged.
fn mir_intern_type(d: Domain, store: MirStore, kind: U64, elem: U64, ok_type: U64, err_type: U64, parts: __s0_Buffer(U64), result_type: U64) -> Result(MirTypeStep, __s0_Error) {
    var at: U64 = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let prior = __s0_buffer_get(MirTypeRec, store.types, at)
        if prior.kind == kind && prior.elem == elem && prior.ok_type == ok_type && prior.err_type == err_type && prior.result_type == result_type && mir_type_parts_equal(store, prior.first_part, prior.part_count, parts) {
            return Ok(MirTypeStep(store: store, type_id: at + 1))
        }
        at = at + 1
    }
    let type_id = __s0_buffer_len(MirTypeRec, store.types) + 1
    var type_parts = store.type_parts
    var first: U64 = 0
    var part_at: U64 = 0
    while part_at < __s0_buffer_len(U64, parts) {
        if first == 0 { first = __s0_buffer_len(MirTypePartRec, type_parts) + 1 }
        type_parts = try __s0_buffer_append(MirTypePartRec, d, type_parts, MirTypePartRec(kind: mir_type_part_function_param(), owner: type_id, ordinal: part_at, name_start: 0, name_end: 0, part_type: __s0_buffer_get(U64, parts, part_at), c_name_start: 0, c_name_end: 0))
        part_at = part_at + 1
    }
    let rec = MirTypeRec(kind: kind, name_start: 0, name_end: 0, elem: elem, ok_type: ok_type, err_type: err_type, first_part: first, part_count: part_at, result_type: result_type, length: 0, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar())
    let types = try __s0_buffer_append(MirTypeRec, d, store.types, rec)
    return Ok(MirTypeStep(store: mir_with_types(mir_with_type_parts(store, type_parts), types), type_id: type_id))
}

fn mir_intern_array(d: Domain, store: MirStore, elem: U64, length: U64) -> Result(MirTypeStep, __s0_Error) {
    var at: U64 = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let prior = __s0_buffer_get(MirTypeRec, store.types, at)
        if prior.kind == mir_type_kind_array() && prior.elem == elem && prior.length == length { return Ok(MirTypeStep(store: store, type_id: at + 1)) }
        at = at + 1
    }
    let types = try __s0_buffer_append(MirTypeRec, d, store.types, MirTypeRec(kind: mir_type_kind_array(), name_start: 0, name_end: 0, elem: elem, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: length, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar()))
    return Ok(MirTypeStep(store: mir_with_types(store, types), type_id: __s0_buffer_len(MirTypeRec, types)))
}

fn mir_add_named_type(d: Domain, store: MirStore, kind: U64, name: __s0_String) -> Result(MirTypeStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let types = try __s0_buffer_append(MirTypeRec, d, named.store.types, MirTypeRec(kind: kind, name_start: named.start, name_end: named.end, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: 0, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar()))
    return Ok(MirTypeStep(store: mir_with_types(named.store, types), type_id: __s0_buffer_len(MirTypeRec, types)))
}

fn mir_add_type_part(d: Domain, store: MirStore, kind: U64, owner: U64, ordinal: U64, name: __s0_String, part_type: U64) -> Result(MirStore, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let part = MirTypePartRec(kind: kind, owner: owner, ordinal: ordinal, name_start: named.start, name_end: named.end, part_type: part_type, c_name_start: 0, c_name_end: 0)
    let parts = try __s0_buffer_append(MirTypePartRec, d, named.store.type_parts, part)
    return Ok(mir_with_type_parts(named.store, parts))
}

fn mir_add_import(d: Domain, store: MirStore, name: __s0_String, result_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirImportRec, d, named.store.imports, MirImportRec(name_start: named.start, name_end: named.end, result_type: result_type))
    return Ok(MirBuildStep(store: mir_with_imports(named.store, items), id: __s0_buffer_len(MirImportRec, items)))
}

// Import signatures use append-only operand records so malformed owner and
// ordinal combinations remain directly constructible for verifier fixtures.
fn mir_add_import_param(d: Domain, store: MirStore, import_id: U64, ordinal: U64, param_type: U64) -> Result(MirStore, __s0_Error) {
    let rec = MirOperandRec(kind: mir_operand_import_param(), owner: import_id, ordinal: ordinal, edge: 0, value: 0, target: 0, operand_type: param_type, name_start: 0, name_end: 0)
    let step = try mir_add_operand(d, store, rec)
    return Ok(step.store)
}

// Mark one function as a C export and append its source-level symbol name.
fn mir_mark_function_exported(d: Domain, store: MirStore, function: U64, name: __s0_String) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    var current = named.store
    if function == 0 || function > __s0_buffer_len(MirFunctionRec, current.functions) { return Ok(MirBuildStep(store: current, id: 0)) }
    let item = __s0_buffer_get(MirFunctionRec, current.functions, function - 1)
    let rec = MirFunctionRec(name_start: item.name_start, name_end: item.name_end, result_type: item.result_type, c_export: true, export_name_start: named.start, export_name_end: named.end, noreturn: item.noreturn)
    __s0_buffer_set(MirFunctionRec, current.functions, function - 1, rec)
    return Ok(MirBuildStep(store: current, id: function))
}

fn mir_add_const(d: Domain, store: MirStore, name: __s0_String, const_type: U64, kind: U64, bool_value: U64, int_value: I64, float_bits: U64, text: __s0_String) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let value = try mir_append_name(d, named.store, text)
    let rec = MirConstRec(name_start: named.start, name_end: named.end, const_type: const_type, kind: kind, bool_value: bool_value, int_value: int_value, float_bits: float_bits, string_start: value.start, string_end: value.end)
    let items = try __s0_buffer_append(MirConstRec, d, value.store.constants, rec)
    return Ok(MirBuildStep(store: mir_with_constants(value.store, items), id: __s0_buffer_len(MirConstRec, items)))
}

fn mir_add_function(d: Domain, store: MirStore, name: __s0_String, result_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirFunctionRec, d, named.store.functions, MirFunctionRec(name_start: named.start, name_end: named.end, result_type: result_type, c_export: false, export_name_start: 0, export_name_end: 0, noreturn: false))
    return Ok(MirBuildStep(store: mir_with_functions(named.store, items), id: __s0_buffer_len(MirFunctionRec, items)))
}

// Marks a function whose callers never observe a return. Lowering uses this
// for core.panic.panic so a reachable block may end in `unreachable` after
// the call.
fn mir_mark_function_noreturn(store: MirStore, function: U64) -> MirStore {
    if function == 0 || function > __s0_buffer_len(MirFunctionRec, store.functions) { return store }
    let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
    if item.noreturn { return store }
    __s0_buffer_set(MirFunctionRec, store.functions, function - 1, MirFunctionRec(name_start: item.name_start, name_end: item.name_end, result_type: item.result_type, c_export: item.c_export, export_name_start: item.export_name_start, export_name_end: item.export_name_end, noreturn: true))
    return store
}

fn mir_add_value(d: Domain, store: MirStore, function: U64, name: __s0_String, value_type: U64, def_kind: U64, block: U64, item: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    var ordinal: U64 = 0
    let total = __s0_buffer_len(MirValueRec, named.store.values)
    var grouped = false
    if total != 0 {
        let previous = __s0_buffer_get(MirValueRec, named.store.values, total - 1)
        if previous.function == function { ordinal = previous.ordinal + 1
            grouped = true }
    }
    if !grouped { var at: U64 = 0
        while at < total {
            if __s0_buffer_get(MirValueRec, named.store.values, at).function == function { ordinal = ordinal + 1 }
            at = at + 1
        }
    }
    let rec = MirValueRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end, value_type: value_type, def_kind: def_kind, block: block, item: item)
    let values = try __s0_buffer_append(MirValueRec, d, named.store.values, rec)
    return Ok(MirBuildStep(store: mir_with_values(named.store, values), id: ordinal + 1))
}

fn mir_add_function_param(d: Domain, store: MirStore, function: U64, ordinal: U64, name: __s0_String, param_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let value = try mir_add_value(d, store, function, name, param_type, mir_value_def_function_param(), 0, ordinal + 1)
    let named = try mir_append_name(d, value.store, name)
    let rec = MirParamRec(kind: mir_param_function(), function: function, block: 0, ordinal: ordinal, name_start: named.start, name_end: named.end, param_type: param_type, value: value.id)
    let params = try __s0_buffer_append(MirParamRec, d, named.store.params, rec)
    return Ok(MirBuildStep(store: mir_with_params(named.store, params), id: value.id))
}

fn mir_add_local(d: Domain, store: MirStore, function: U64, ordinal: U64, name: __s0_String, local_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirLocalRec, d, named.store.locals, MirLocalRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end, local_type: local_type))
    return Ok(MirBuildStep(store: mir_with_locals(named.store, items), id: ordinal + 1))
}

fn mir_add_block(d: Domain, store: MirStore, function: U64, ordinal: U64, name: __s0_String) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirBlockRec, d, named.store.blocks, MirBlockRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end))
    return Ok(MirBuildStep(store: mir_with_blocks(named.store, items), id: ordinal + 1))
}

fn mir_add_block_param(d: Domain, store: MirStore, function: U64, block: U64, ordinal: U64, name: __s0_String, param_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let value = try mir_add_value(d, store, function, name, param_type, mir_value_def_block_param(), block, ordinal + 1)
    let named = try mir_append_name(d, value.store, name)
    let rec = MirParamRec(kind: mir_param_block(), function: function, block: block, ordinal: ordinal, name_start: named.start, name_end: named.end, param_type: param_type, value: value.id)
    let params = try __s0_buffer_append(MirParamRec, d, named.store.params, rec)
    return Ok(MirBuildStep(store: mir_with_params(named.store, params), id: value.id))
}

fn mir_add_place(d: Domain, store: MirStore, rec: MirPlaceRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try __s0_buffer_append(MirPlaceRec, d, store.places, rec)
    return Ok(MirBuildStep(store: mir_with_places(store, items), id: __s0_buffer_len(MirPlaceRec, items)))
}

fn mir_add_instruction(d: Domain, store: MirStore, rec: MirInstrRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try __s0_buffer_append(MirInstrRec, d, store.instructions, rec)
    return Ok(MirBuildStep(store: mir_with_instructions(store, items), id: __s0_buffer_len(MirInstrRec, items)))
}

fn mir_add_terminator(d: Domain, store: MirStore, rec: MirTermRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try __s0_buffer_append(MirTermRec, d, store.terminators, rec)
    return Ok(MirBuildStep(store: mir_with_terminators(store, items), id: __s0_buffer_len(MirTermRec, items)))
}

fn mir_add_operand(d: Domain, store: MirStore, rec: MirOperandRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try __s0_buffer_append(MirOperandRec, d, store.operands, rec)
    return Ok(MirBuildStep(store: mir_with_operands(store, items), id: __s0_buffer_len(MirOperandRec, items)))
}

// C binding blocks append in declaration order; the flat binding-function
// index is the buffer position of its MirBindingFnRec.
fn mir_add_binding(d: Domain, store: MirStore, name: __s0_String, header: __s0_String) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let headed = try mir_append_name(d, named.store, header)
    let rec = MirBindingRec(name_start: named.start, name_end: named.end, header_start: headed.start, header_end: headed.end)
    let items = try __s0_buffer_append(MirBindingRec, d, headed.store.bindings, rec)
    return Ok(MirBuildStep(store: mir_with_bindings(headed.store, items), id: __s0_buffer_len(MirBindingRec, items)))
}

fn mir_add_binding_type(d: Domain, store: MirStore, block: U64, ordinal: U64, type_id: U64) -> Result(MirStore, __s0_Error) {
    let rec = MirOperandRec(kind: mir_operand_binding_type(), owner: block, ordinal: ordinal, edge: 0, value: 0, target: 0, operand_type: type_id, name_start: 0, name_end: 0)
    let step = try mir_add_operand(d, store, rec)
    return Ok(step.store)
}

// The returned id is the flattened block-major binding-function index (1-based
// external form) used by c.call.unsafe target fields.
fn mir_add_binding_fn(d: Domain, store: MirStore, block: U64, name: __s0_String, c_name: __s0_String, result_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let spelled = try mir_append_name(d, named.store, c_name)
    let rec = MirBindingFnRec(block: block, name_start: named.start, name_end: named.end, c_name_start: spelled.start, c_name_end: spelled.end, result_type: result_type)
    let items = try __s0_buffer_append(MirBindingFnRec, d, spelled.store.binding_funcs, rec)
    return Ok(MirBuildStep(store: mir_with_binding_funcs(spelled.store, items), id: __s0_buffer_len(MirBindingFnRec, items)))
}

fn mir_add_binding_fn_param(d: Domain, store: MirStore, fn_id: U64, ordinal: U64, param_type: U64) -> Result(MirStore, __s0_Error) {
    let rec = MirOperandRec(kind: mir_operand_binding_param(), owner: fn_id, ordinal: ordinal, edge: 0, value: 0, target: 0, operand_type: param_type, name_start: 0, name_end: 0)
    let step = try mir_add_operand(d, store, rec)
    return Ok(step.store)
}

fn mir_add_binding_const(d: Domain, store: MirStore, block: U64, name: __s0_String, c_name: __s0_String, const_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let spelled = try mir_append_name(d, named.store, c_name)
    let rec = MirBindingConstRec(block: block, name_start: named.start, name_end: named.end, c_name_start: spelled.start, c_name_end: spelled.end, const_type: const_type)
    let items = try __s0_buffer_append(MirBindingConstRec, d, spelled.store.binding_consts, rec)
    return Ok(MirBuildStep(store: mir_with_binding_consts(spelled.store, items), id: __s0_buffer_len(MirBindingConstRec, items)))
}

// c_named binding types are named and never structurally interned; c_class
// selects scalar, opaque, or record, and c_name spells the C declaration.
fn mir_add_c_named_type(d: Domain, store: MirStore, name: __s0_String, c_name: __s0_String, c_class: U64) -> Result(MirTypeStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let spelled = try mir_append_name(d, named.store, c_name)
    let types = try __s0_buffer_append(MirTypeRec, d, spelled.store.types, MirTypeRec(kind: mir_type_kind_c_named(), name_start: named.start, name_end: named.end, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: 0, c_name_start: spelled.start, c_name_end: spelled.end, c_class: c_class))
    return Ok(MirTypeStep(store: mir_with_types(spelled.store, types), type_id: __s0_buffer_len(MirTypeRec, types)))
}

fn mir_add_c_field_part(d: Domain, store: MirStore, owner: U64, ordinal: U64, name: __s0_String, c_name: __s0_String, part_type: U64) -> Result(MirStore, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let spelled = try mir_append_name(d, named.store, c_name)
    let part = MirTypePartRec(kind: mir_type_part_c_field(), owner: owner, ordinal: ordinal, name_start: named.start, name_end: named.end, part_type: part_type, c_name_start: spelled.start, c_name_end: spelled.end)
    let parts = try __s0_buffer_append(MirTypePartRec, d, spelled.store.type_parts, part)
    return Ok(mir_with_type_parts(spelled.store, parts))
}

fn mir_intern_c_raw(d: Domain, store: MirStore, scalar: U64) -> Result(MirTypeStep, __s0_Error) {
    var at: U64 = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let prior = __s0_buffer_get(MirTypeRec, store.types, at)
        if prior.kind == mir_type_kind_c_raw() && prior.length == scalar { return Ok(MirTypeStep(store: store, type_id: at + 1)) }
        at = at + 1
    }
    let types = try __s0_buffer_append(MirTypeRec, d, store.types, MirTypeRec(kind: mir_type_kind_c_raw(), name_start: 0, name_end: 0, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: scalar, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar()))
    return Ok(MirTypeStep(store: mir_with_types(store, types), type_id: __s0_buffer_len(MirTypeRec, types)))
}

fn mir_intern_c_ptr(d: Domain, store: MirStore, elem: U64) -> Result(MirTypeStep, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    return mir_intern_type(d, store, mir_type_kind_c_ptr(), elem, 0, 0, empty, 0)
}

fn mir_intern_c_const_ptr(d: Domain, store: MirStore, elem: U64) -> Result(MirTypeStep, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    return mir_intern_type(d, store, mir_type_kind_c_const_ptr(), elem, 0, 0, empty, 0)
}

fn mir_intern_c_string(d: Domain, store: MirStore) -> Result(MirTypeStep, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    return mir_intern_type(d, store, mir_type_kind_c_string(), 0, 0, 0, empty, 0)
}
