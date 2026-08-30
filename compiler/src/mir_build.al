// Append-only deterministic construction for the independent MIR 4 model.

fn mir_with_names(store: MirStore, names: Vec(U8)) -> MirStore {
    return MirStore(names: names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_types(store: MirStore, types: Vec(MirTypeRec)) -> MirStore {
    return MirStore(names: store.names, types: types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_type_parts(store: MirStore, parts: Vec(MirTypePartRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_imports(store: MirStore, imports: Vec(MirImportRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_constants(store: MirStore, constants: Vec(MirConstRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_functions(store: MirStore, functions: Vec(MirFunctionRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_params(store: MirStore, params: Vec(MirParamRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_locals(store: MirStore, locals: Vec(MirLocalRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_blocks(store: MirStore, blocks: Vec(MirBlockRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_values(store: MirStore, values: Vec(MirValueRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_places(store: MirStore, places: Vec(MirPlaceRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: places, instructions: store.instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_instructions(store: MirStore, instructions: Vec(MirInstrRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: instructions, terminators: store.terminators, operands: store.operands)
}

fn mir_with_terminators(store: MirStore, terminators: Vec(MirTermRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: terminators, operands: store.operands)
}

fn mir_with_operands(store: MirStore, operands: Vec(MirOperandRec)) -> MirStore {
    return MirStore(names: store.names, types: store.types, type_parts: store.type_parts, imports: store.imports, constants: store.constants, functions: store.functions, params: store.params, locals: store.locals, blocks: store.blocks, values: store.values, places: store.places, instructions: store.instructions, terminators: store.terminators, operands: operands)
}

fn mir_new_operands(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec), locals: Vec(MirLocalRec), blocks: Vec(MirBlockRec), values: Vec(MirValueRec), places: Vec(MirPlaceRec), instructions: Vec(MirInstrRec), terminators: Vec(MirTermRec)) -> Result(MirStore, __s0_Error) {
    let operands = Vec.new(MirOperandRec)
    return Ok(MirStore(names: names, types: types, type_parts: parts, imports: imports, constants: constants, functions: functions, params: params, locals: locals, blocks: blocks, values: values, places: places, instructions: instructions, terminators: terminators, operands: operands))
}

fn mir_new_terminators(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec), locals: Vec(MirLocalRec), blocks: Vec(MirBlockRec), values: Vec(MirValueRec), places: Vec(MirPlaceRec), instructions: Vec(MirInstrRec)) -> Result(MirStore, __s0_Error) {
    let terms = Vec.new(MirTermRec)
    return mir_new_operands(d, names, types, parts, imports, constants, functions, params, locals, blocks, values, places, instructions, terms)
}

fn mir_new_instructions(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec), locals: Vec(MirLocalRec), blocks: Vec(MirBlockRec), values: Vec(MirValueRec), places: Vec(MirPlaceRec)) -> Result(MirStore, __s0_Error) {
    let instructions = Vec.new(MirInstrRec)
    return mir_new_terminators(d, names, types, parts, imports, constants, functions, params, locals, blocks, values, places, instructions)
}

fn mir_new_places(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec), locals: Vec(MirLocalRec), blocks: Vec(MirBlockRec), values: Vec(MirValueRec)) -> Result(MirStore, __s0_Error) {
    let places = Vec.new(MirPlaceRec)
    return mir_new_instructions(d, names, types, parts, imports, constants, functions, params, locals, blocks, values, places)
}

fn mir_new_values(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec), locals: Vec(MirLocalRec), blocks: Vec(MirBlockRec)) -> Result(MirStore, __s0_Error) {
    let values = Vec.new(MirValueRec)
    return mir_new_places(d, names, types, parts, imports, constants, functions, params, locals, blocks, values)
}

fn mir_new_blocks(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec), locals: Vec(MirLocalRec)) -> Result(MirStore, __s0_Error) {
    let blocks = Vec.new(MirBlockRec)
    return mir_new_values(d, names, types, parts, imports, constants, functions, params, locals, blocks)
}

fn mir_new_locals(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec), params: Vec(MirParamRec)) -> Result(MirStore, __s0_Error) {
    let locals = Vec.new(MirLocalRec)
    return mir_new_blocks(d, names, types, parts, imports, constants, functions, params, locals)
}

fn mir_new_params(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec), functions: Vec(MirFunctionRec)) -> Result(MirStore, __s0_Error) {
    let params = Vec.new(MirParamRec)
    return mir_new_locals(d, names, types, parts, imports, constants, functions, params)
}

fn mir_new_functions(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec), constants: Vec(MirConstRec)) -> Result(MirStore, __s0_Error) {
    let functions = Vec.new(MirFunctionRec)
    return mir_new_params(d, names, types, parts, imports, constants, functions)
}

fn mir_new_constants(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec), imports: Vec(MirImportRec)) -> Result(MirStore, __s0_Error) {
    let constants = Vec.new(MirConstRec)
    return mir_new_functions(d, names, types, parts, imports, constants)
}

fn mir_new_imports(d: Domain, names: Vec(U8), types: Vec(MirTypeRec), parts: Vec(MirTypePartRec)) -> Result(MirStore, __s0_Error) {
    let imports = Vec.new(MirImportRec)
    return mir_new_constants(d, names, types, parts, imports)
}

fn mir_new_parts(d: Domain, names: Vec(U8), types: Vec(MirTypeRec)) -> Result(MirStore, __s0_Error) {
    let parts = Vec.new(MirTypePartRec)
    return mir_new_imports(d, names, types, parts)
}

fn mir_append_primitive(d: Domain, types: Vec(MirTypeRec)) -> Result(Vec(MirTypeRec), __s0_Error) {
    return Ok(try vec_appended(MirTypeRec, types, MirTypeRec(kind: mir_type_kind_primitive(), name_start: 0, name_end: 0, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: 0)))
}

fn mir_new_types(d: Domain, names: Vec(U8)) -> Result(MirStore, __s0_Error) {
    var types = Vec.new(MirTypeRec)
    var at: U64 = 0
    while at < mir_primitive_type_count() {
        types = try mir_append_primitive(d, types)
        at = at + 1
    }
    return mir_new_parts(d, names, types)
}

fn mir_store_new(d: Domain) -> Result(MirStore, __s0_Error) {
    let names = Vec.new(U8)
    return mir_new_types(d, names)
}

fn mir_append_name(d: Domain, store: MirStore, name: [U8]) -> Result(MirNameStep, __s0_Error) {
    var names = store.names
    let start = (names).len()
    var at: U64 = 0
    while at < len(name) {
        try names.try_push(name[at])
        at = at + 1
    }
    return Ok(MirNameStep(store: mir_with_names(store, names), start: start, end: (names).len()))
}

fn mir_type_parts_equal(store: MirStore, first: U64, count: U64, parts: Vec(U64)) -> Bool {
    if count != (parts).len() { return false }
    var at: U64 = 0
    while at < count {
        let prior = (store.type_parts)[first - 1 + at]
        if prior.part_type != parts[at] { return false }
        at = at + 1
    }
    return true
}

// Structural type kinds option..vec are interned by deterministic
// ascending scans.
// For unary and singleton types parts is empty; function types use ordered
// parameter Type IDs and result_type. Named aggregate/enum kinds are appended
// separately and are never structurally merged.
fn mir_intern_type(d: Domain, store: MirStore, kind: U64, elem: U64, ok_type: U64, err_type: U64, parts: Vec(U64), result_type: U64) -> Result(MirTypeStep, __s0_Error) {
    var at: U64 = mir_primitive_type_count()
    while at < (store.types).len() {
        let prior = (store.types)[at]
        if prior.kind == kind && prior.elem == elem && prior.ok_type == ok_type && prior.err_type == err_type && prior.result_type == result_type && mir_type_parts_equal(store, prior.first_part, prior.part_count, parts) {
            return Ok(MirTypeStep(store: store, type_id: at + 1))
        }
        at = at + 1
    }
    let type_id = (store.types).len() + 1
    var type_parts = store.type_parts
    var first: U64 = 0
    var part_at: U64 = 0
    while part_at < (parts).len() {
        if first == 0 { first = (type_parts).len() + 1 }
        try type_parts.try_push(MirTypePartRec(kind: mir_type_part_function_param(), owner: type_id, ordinal: part_at, name_start: 0, name_end: 0, part_type: parts[part_at]))
        part_at = part_at + 1
    }
    let rec = MirTypeRec(kind: kind, name_start: 0, name_end: 0, elem: elem, ok_type: ok_type, err_type: err_type, first_part: first, part_count: part_at, result_type: result_type, length: 0)
    let types = try vec_appended(MirTypeRec, store.types, rec)
    return Ok(MirTypeStep(store: mir_with_types(mir_with_type_parts(store, type_parts), types), type_id: type_id))
}

fn mir_intern_array(d: Domain, store: MirStore, elem: U64, length: U64) -> Result(MirTypeStep, __s0_Error) {
    var at: U64 = mir_primitive_type_count()
    while at < (store.types).len() {
        let prior = (store.types)[at]
        if prior.kind == mir_type_kind_array() && prior.elem == elem && prior.length == length { return Ok(MirTypeStep(store: store, type_id: at + 1)) }
        at = at + 1
    }
    let types = try vec_appended(MirTypeRec, store.types, MirTypeRec(kind: mir_type_kind_array(), name_start: 0, name_end: 0, elem: elem, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: length))
    return Ok(MirTypeStep(store: mir_with_types(store, types), type_id: (types).len()))
}

fn mir_add_named_type(d: Domain, store: MirStore, kind: U64, name: [U8]) -> Result(MirTypeStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let types = try vec_appended(MirTypeRec, named.store.types, MirTypeRec(kind: kind, name_start: named.start, name_end: named.end, elem: 0, ok_type: 0, err_type: 0, first_part: 0, part_count: 0, result_type: 0, length: 0))
    return Ok(MirTypeStep(store: mir_with_types(named.store, types), type_id: (types).len()))
}

fn mir_add_type_part(d: Domain, store: MirStore, kind: U64, owner: U64, ordinal: U64, name: [U8], part_type: U64) -> Result(MirStore, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let part = MirTypePartRec(kind: kind, owner: owner, ordinal: ordinal, name_start: named.start, name_end: named.end, part_type: part_type)
    let parts = try vec_appended(MirTypePartRec, named.store.type_parts, part)
    return Ok(mir_with_type_parts(named.store, parts))
}

fn mir_add_import(d: Domain, store: MirStore, name: [U8], result_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try vec_appended(MirImportRec, named.store.imports, MirImportRec(name_start: named.start, name_end: named.end, result_type: result_type))
    return Ok(MirBuildStep(store: mir_with_imports(named.store, items), id: (items).len()))
}

// Import signatures use append-only operand records so malformed owner and
// ordinal combinations remain directly constructible for verifier fixtures.
fn mir_add_import_param(d: Domain, store: MirStore, import_id: U64, ordinal: U64, param_type: U64) -> Result(MirStore, __s0_Error) {
    let rec = MirOperandRec(kind: mir_operand_import_param(), owner: import_id, ordinal: ordinal, edge: 0, value: 0, target: 0, operand_type: param_type, name_start: 0, name_end: 0)
    let step = try mir_add_operand(d, store, rec)
    return Ok(step.store)
}

fn mir_add_const(d: Domain, store: MirStore, name: [U8], const_type: U64, kind: U64, bool_value: U64, int_value: I64, float_bits: U64, text: [U8]) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let value = try mir_append_name(d, named.store, text)
    let rec = MirConstRec(name_start: named.start, name_end: named.end, const_type: const_type, kind: kind, bool_value: bool_value, int_value: int_value, float_bits: float_bits, string_start: value.start, string_end: value.end)
    let items = try vec_appended(MirConstRec, value.store.constants, rec)
    return Ok(MirBuildStep(store: mir_with_constants(value.store, items), id: (items).len()))
}

fn mir_add_function(d: Domain, store: MirStore, name: [U8], result_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try vec_appended(MirFunctionRec, named.store.functions, MirFunctionRec(name_start: named.start, name_end: named.end, result_type: result_type))
    return Ok(MirBuildStep(store: mir_with_functions(named.store, items), id: (items).len()))
}

fn mir_add_value(d: Domain, store: MirStore, function: U64, name: [U8], value_type: U64, def_kind: U64, block: U64, item: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    var ordinal: U64 = 0
    let total = (named.store.values).len()
    var grouped = false
    if total != 0 {
        let previous = (named.store.values)[total - 1]
        if previous.function == function { ordinal = previous.ordinal + 1
            grouped = true }
    }
    if !grouped { var at: U64 = 0
        while at < total {
            if (named.store.values)[at].function == function { ordinal = ordinal + 1 }
            at = at + 1
        }
    }
    let rec = MirValueRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end, value_type: value_type, def_kind: def_kind, block: block, item: item)
    let values = try vec_appended(MirValueRec, named.store.values, rec)
    return Ok(MirBuildStep(store: mir_with_values(named.store, values), id: ordinal + 1))
}

fn mir_add_function_param(d: Domain, store: MirStore, function: U64, ordinal: U64, name: [U8], param_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let value = try mir_add_value(d, store, function, name, param_type, mir_value_def_function_param(), 0, ordinal + 1)
    let named = try mir_append_name(d, value.store, name)
    let rec = MirParamRec(kind: mir_param_function(), function: function, block: 0, ordinal: ordinal, name_start: named.start, name_end: named.end, param_type: param_type, value: value.id)
    let params = try vec_appended(MirParamRec, named.store.params, rec)
    return Ok(MirBuildStep(store: mir_with_params(named.store, params), id: value.id))
}

fn mir_add_local(d: Domain, store: MirStore, function: U64, ordinal: U64, name: [U8], local_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try vec_appended(MirLocalRec, named.store.locals, MirLocalRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end, local_type: local_type))
    return Ok(MirBuildStep(store: mir_with_locals(named.store, items), id: ordinal + 1))
}

fn mir_add_block(d: Domain, store: MirStore, function: U64, ordinal: U64, name: [U8]) -> Result(MirBuildStep, __s0_Error) {
    let named = try mir_append_name(d, store, name)
    let items = try vec_appended(MirBlockRec, named.store.blocks, MirBlockRec(function: function, ordinal: ordinal, name_start: named.start, name_end: named.end))
    return Ok(MirBuildStep(store: mir_with_blocks(named.store, items), id: ordinal + 1))
}

fn mir_add_block_param(d: Domain, store: MirStore, function: U64, block: U64, ordinal: U64, name: [U8], param_type: U64) -> Result(MirBuildStep, __s0_Error) {
    let value = try mir_add_value(d, store, function, name, param_type, mir_value_def_block_param(), block, ordinal + 1)
    let named = try mir_append_name(d, value.store, name)
    let rec = MirParamRec(kind: mir_param_block(), function: function, block: block, ordinal: ordinal, name_start: named.start, name_end: named.end, param_type: param_type, value: value.id)
    let params = try vec_appended(MirParamRec, named.store.params, rec)
    return Ok(MirBuildStep(store: mir_with_params(named.store, params), id: value.id))
}

fn mir_add_place(d: Domain, store: MirStore, rec: MirPlaceRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try vec_appended(MirPlaceRec, store.places, rec)
    return Ok(MirBuildStep(store: mir_with_places(store, items), id: (items).len()))
}

fn mir_add_instruction(d: Domain, store: MirStore, rec: MirInstrRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try vec_appended(MirInstrRec, store.instructions, rec)
    return Ok(MirBuildStep(store: mir_with_instructions(store, items), id: (items).len()))
}

fn mir_add_terminator(d: Domain, store: MirStore, rec: MirTermRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try vec_appended(MirTermRec, store.terminators, rec)
    return Ok(MirBuildStep(store: mir_with_terminators(store, items), id: (items).len()))
}

fn mir_add_operand(d: Domain, store: MirStore, rec: MirOperandRec) -> Result(MirBuildStep, __s0_Error) {
    let items = try vec_appended(MirOperandRec, store.operands, rec)
    return Ok(MirBuildStep(store: mir_with_operands(store, items), id: (items).len()))
}
