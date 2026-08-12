// Independent MIR 3 storage model. Every public identity is a 1-based U64;
// zero means absent. Records contain only semantic MIR data and stable IDs.

// Type kinds mirror mir/types.go: primitive, aggregate, enum, option, result,
// slice, safe_ref, safe_mut, raw_ptr, function, domain_handle, domain_mark,
// cleanup_scope, cleanup_id, table, id, table_view, table_mut_view.
type MirTypeRec {
    kind: U64
    name_start: U64
    name_end: U64
    elem: U64
    ok_type: U64
    err_type: U64
    first_part: U64
    part_count: U64
    result_type: U64
}

// Part kinds are 1 aggregate field, 2 enum variant, and 3 function parameter.
// owner is a Type ID and ordinal is zero-based within that type.
type MirTypePartRec {
    kind: U64
    owner: U64
    ordinal: U64
    name_start: U64
    name_end: U64
    part_type: U64
}

type MirImportRec {
    name_start: U64
    name_end: U64
    result_type: U64
}

// Constant kinds mirror mir/mir.go: unit, bool, integer, float, string.
type MirConstRec {
    name_start: U64
    name_end: U64
    const_type: U64
    kind: U64
    bool_value: U64
    int_value: I64
    // IEEE-754 bits avoid host float formatting in this storage-only layer.
    float_bits: U64
    string_start: U64
    string_end: U64
}

type MirFunctionRec {
    name_start: U64
    name_end: U64
    result_type: U64
}

// Parameter kinds are 1 function parameter and 2 block parameter. value is
// the Value ID allocated with the parameter.
type MirParamRec {
    kind: U64
    function: U64
    block: U64
    ordinal: U64
    name_start: U64
    name_end: U64
    param_type: U64
    value: U64
}

type MirLocalRec {
    function: U64
    ordinal: U64
    name_start: U64
    name_end: U64
    local_type: U64
}

type MirBlockRec {
    function: U64
    ordinal: U64
    name_start: U64
    name_end: U64
}

// Definition kinds mirror mir/mir.go: function parameter, block parameter,
// instruction result, and switch case payload.
type MirValueRec {
    function: U64
    ordinal: U64
    name_start: U64
    name_end: U64
    value_type: U64
    def_kind: U64
    block: U64
    item: U64
}

// Place kinds mirror mir/mir.go: local, field, and checked-reference deref.
type MirPlaceRec {
    function: U64
    kind: U64
    local: U64
    base: U64
    field_start: U64
    field_end: U64
    deref_value: U64
}

// Instructions retain the documented operation kind plus fixed semantic
// operands. Additional ordered operands and checked-edge arguments use
// MirOperandRec records, avoiding nested buffers and pointer-linked graphs.
type MirInstrRec {
    function: U64
    block: U64
    ordinal: U64
    op: U64
    result: U64
    place: U64
    type_op: U64
    a: U64
    b: U64
    c: U64
    target: U64
    name_start: U64
    name_end: U64
}

// Terminator kinds mirror mir/mir.go: jump, branch, switch, return, fail,
// unreachable, panic. Cases and edge arguments are ordered operands.
type MirTermRec {
    function: U64
    block: U64
    kind: U64
    value: U64
    target: U64
    then_block: U64
    else_block: U64
}

// Operand kinds are 1 type part, 2 import parameter, 3 instruction operand,
// 4 checked-edge argument, 5 terminator argument, 6 switch case, 7 switch-case
// argument, and 8 aggregate field. owner is the corresponding stable ID.
type MirOperandRec {
    kind: U64
    owner: U64
    ordinal: U64
    value: U64
    target: U64
    name_start: U64
    name_end: U64
}

type MirStore {
    names: __s0_Buffer(U8)
    types: __s0_Buffer(MirTypeRec)
    type_parts: __s0_Buffer(MirTypePartRec)
    imports: __s0_Buffer(MirImportRec)
    constants: __s0_Buffer(MirConstRec)
    functions: __s0_Buffer(MirFunctionRec)
    params: __s0_Buffer(MirParamRec)
    locals: __s0_Buffer(MirLocalRec)
    blocks: __s0_Buffer(MirBlockRec)
    values: __s0_Buffer(MirValueRec)
    places: __s0_Buffer(MirPlaceRec)
    instructions: __s0_Buffer(MirInstrRec)
    terminators: __s0_Buffer(MirTermRec)
    operands: __s0_Buffer(MirOperandRec)
}

type MirTypeStep {
    store: MirStore
    type_id: U64
}

type MirNameStep {
    store: MirStore
    start: U64
    end: U64
}

type MirBuildStep {
    store: MirStore
    id: U64
}
