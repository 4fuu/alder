// Append-only deterministic construction for the independent MIR 3 model.

fn mir_with_names(store: MirStore, names: __s0_Buffer(U8)) -> MirStore {
    return MirStore(names: names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_types(store: MirStore, types: __s0_Buffer(MirTypeRec)) -> MirStore {
    return MirStore(names: store.names, types: types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_type_parts(store: MirStore, parts: __s0_Buffer(MirTypePartRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_imports(store: MirStore, imports: __s0_Buffer(MirImportRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_constants(store: MirStore, constants: __s0_Buffer(MirConstRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_functions(store: MirStore, functions: __s0_Buffer(MirFunctionRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_params(store: MirStore, params: __s0_Buffer(MirParamRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_locals(store: MirStore, locals: __s0_Buffer(MirLocalRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_blocks(store: MirStore, blocks: __s0_Buffer(MirBlockRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_values(store: MirStore, values: __s0_Buffer(MirValueRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_places(store: MirStore, places: __s0_Buffer(MirPlaceRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_instructions(store: MirStore, instructions: __s0_Buffer(MirInstrRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_terminators(store: MirStore, terminators: __s0_Buffer(MirTermRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: terminators, operands: store.operands)
}

fn mir_with_operands(store: MirStore, operands: __s0_Buffer(MirOperandRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: operands)
}

fn mir_new_operands(d: Domain, names: __s0_Buffer(U8), types: __s0_Buffer(MirTypeRec), parts: __s0_Buffer(MirTypePartRec), imports: __s0_Buffer(MirImportRec), constants: __s0_Buffer(MirConstRec), functions: __s0_Buffer(MirFunctionRec), params: __s0_Buffer(MirParamRec), locals: __s0_Buffer(MirLocalRec), blocks: __s0_Buffer(MirBlockRec), values: __s0_Buffer(MirValueRec), places: __s0_Buffer(MirPlaceRec), instructions: __s0_Buffer(MirInstrRec), terminators: __s0_Buffer(MirTermRec)) -> Result(MirStore, __s0_Error) {
    let operands = try __s0_buffer_new(MirOperandRec, d)
    return Ok(MirStore(names: names, types: types, type_parts: parts, imports: imports, constants: constants, functions: functions, params: params, locals: locals, blocks: blocks, values: values, places: places, instructions: instructions, terminators: terminators, operands: operands))
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
    return __s0_buffer_append(MirTypeRec, d, types, MirTypeRec(kind: mir_type_kind_primitive(), name_start: 0, name_end: 0, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0))
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

fn mir_append_name(d: Domain, store: MirStore, name: String) -> Result(MirNameStep, __s0_Error) {
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

// Structural type kinds option..table_mut_view are interned by deterministic
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
        type_parts = try __s0_buffer_append(MirTypePartRec, d, type_parts, MirTypePartRec(kind: mir_type_part_function_param(), owner: type_id, ordinal: part_at, name_start: 0, name_end: 0, part_type: __s0_buffer_get(U64, parts, part_at)))
        part_at = part_at + 1
    }
    let rec = MirTypeRec(kind: kind, name_start: 0, name_end: 0, elem: elem, ok_type: ok_type, err_type: err_type, first_part: first, part_count: part_at, result_type: result_type)
    let types = try __s0_buffer_append(MirTypeRec, d, store.types, rec)
    return Ok(MirTypeStep(store: mir_with_types(mir_with_type_parts(store, type_parts), types), type_id: type_id))
}

fn mir_add_named_type(d: Domain, store: MirStore, kind: U64, name: String) -> Result(MirTypeStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let types = try __s0_buffer_append(MirTypeRec, d, named.store.types, MirTypeRec(kind: kind, name_start: named.start, name_end: named.end, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0))
    return Ok(MirTypeStep(store: mir_with_types(named.store, types), type_id: __s0_buffer_len(MirTypeRec, types)))
}

fn mir_add_type_part(d: Domain, store: MirStore, kind: U64, owner: U64, ordinal: U64, name: String, part_type: U64) -> Result(MirStore, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let part = MirTypePartRec(kind: kind, owner: owner, ordinal: ordinal, name_start: named.start, name_end: named.end, part_type: part_type)
    let parts = try __s0_buffer_append(MirTypePartRec, d, named.store.type_parts, part)
    return Ok(mir_with_type_parts(named.store, parts))
}

fn mir_add_import(d: Domain, store: MirStore, name: String, result_type: U64) -> Result(MirBuildStep, __s0_Error) {
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

fn mir_add_const(d: Domain, store: MirStore, name: String, const_type: U64, kind: U64, bool_value: U64, int_value: I64, float_bits: U64, text: String) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let value = try mir_append_name(d, named.store, text)
    let rec = MirConstRec(name_start: named.start, name_end: named.end, const_type: const_type, kind: kind, bool_value: bool_value, int_value: int_value, float_bits: float_bits, string_start: value.start, string_end: value.end)
    let items = try __s0_buffer_append(MirConstRec, d, value.store.constants, rec)
    return Ok(MirBuildStep(store: mir_with_constants(value.store, items), id: __s0_buffer_len(MirConstRec, items)))
}

fn mir_add_function(d: Domain, store: MirStore, name: String, result_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirFunctionRec, d, named.store.functions, MirFunctionRec(name_start: named.start, name_end: named.end, result_type: result_type))
    return Ok(MirBuildStep(store: mir_with_functions(named.store, items), id: __s0_buffer_len(MirFunctionRec, items)))
}

fn mir_add_value(d: Domain, store: MirStore, function: U64, name: String, value_type: U64, def_kind: U64, block: U64, item: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirValueRec, named.store.values) {
        if __s0_buffer_get(MirValueRec, named.store.values, at).function == function { ordinal = ordinal + 1 }
        at = at + 1
    }
    let rec = MirValueRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end, value_type: value_type, def_kind: def_kind, block: block, item: item)
    let values = try __s0_buffer_append(MirValueRec, d, named.store.values, rec)
    return Ok(MirBuildStep(store: mir_with_values(named.store, values), id: ordinal + 1))
}

fn mir_add_function_param(d: Domain, store: MirStore, function: U64, ordinal: U64, name: String, param_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let value = try mir_add_value(d, store, function, name, param_type, mir_value_def_function_param(), 0, ordinal + 1)
    let named = try mir_append_name(d, value.store, name)
    let rec = MirParamRec(kind: mir_param_function(), function: function, block: 0, ordinal: ordinal, name_start: named.start, name_end: named.end, param_type: param_type, value: value.id)
    let params = try __s0_buffer_append(MirParamRec, d, named.store.params, rec)
    return Ok(MirBuildStep(store: mir_with_params(named.store, params), id: value.id))
}

fn mir_add_local(d: Domain, store: MirStore, function: U64, ordinal: U64, name: String, local_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirLocalRec, d, named.store.locals, MirLocalRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end, local_type: local_type))
    return Ok(MirBuildStep(store: mir_with_locals(named.store, items), id: ordinal + 1))
}

fn mir_add_block(d: Domain, store: MirStore, function: U64, ordinal: U64, name: String) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try __s0_buffer_append(MirBlockRec, d, named.store.blocks, MirBlockRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end))
    return Ok(MirBuildStep(store: mir_with_blocks(named.store, items), id: ordinal + 1))
}

fn mir_add_block_param(d: Domain, store: MirStore, function: U64, block: U64, ordinal: U64, name: String, param_type: U64) -> Result(MirBuildStep, __s0_Error) {
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
