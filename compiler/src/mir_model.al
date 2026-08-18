// Independent MIR 3 storage model. Every external identity is a 1-based U64;
// zero means absent. A nonzero module-table ID converts to a Go MIR ID by
// subtracting one. Function-local block, value, and local IDs similarly store
// ordinal + 1 and are resolved by scanning the flat buffer for the owning
// function and zero-based ordinal. Flat record owners (instruction,
// terminator, operand, and type-part IDs) are global buffer index + 1.
// Builders append but do not validate or normalize records, so rejection tests
// may construct malformed raw stores.

fn mir_format_version() -> U64 { return 3 }

// TypeKind values match mir/types.go exactly. Primitive Type IDs are external
// IDs 1..12 in the fixed Go order unit, bool, i8, i16, i32, i64, u8, u16,
// u32, u64, f32, f64.
fn mir_type_kind_primitive() -> U64 { return 0 }
fn mir_type_kind_aggregate() -> U64 { return 1 }
fn mir_type_kind_enum() -> U64 { return 2 }
fn mir_type_kind_option() -> U64 { return 3 }
fn mir_type_kind_result() -> U64 { return 4 }
fn mir_type_kind_slice() -> U64 { return 5 }
fn mir_type_kind_safe_ref() -> U64 { return 6 }
fn mir_type_kind_safe_mut() -> U64 { return 7 }
fn mir_type_kind_raw_ptr() -> U64 { return 8 }
fn mir_type_kind_function() -> U64 { return 9 }
fn mir_type_kind_domain_handle() -> U64 { return 10 }
fn mir_type_kind_domain_mark() -> U64 { return 11 }
fn mir_type_kind_cleanup_scope() -> U64 { return 12 }
fn mir_type_kind_cleanup_id() -> U64 { return 13 }
fn mir_type_kind_table() -> U64 { return 14 }
fn mir_type_kind_id() -> U64 { return 15 }
fn mir_type_kind_table_view() -> U64 { return 16 }
fn mir_type_kind_table_mut_view() -> U64 { return 17 }
fn mir_type_unit() -> U64 { return 1 }
fn mir_type_bool() -> U64 { return 2 }
fn mir_type_i8() -> U64 { return 3 }
fn mir_type_i16() -> U64 { return 4 }
fn mir_type_i32() -> U64 { return 5 }
fn mir_type_i64() -> U64 { return 6 }
fn mir_type_u8() -> U64 { return 7 }
fn mir_type_u16() -> U64 { return 8 }
fn mir_type_u32() -> U64 { return 9 }
fn mir_type_u64() -> U64 { return 10 }
fn mir_type_f32() -> U64 { return 11 }
fn mir_type_f64() -> U64 { return 12 }
fn mir_primitive_type_count() -> U64 { return 12 }

fn mir_type_part_field() -> U64 { return 1 }
fn mir_type_part_variant() -> U64 { return 2 }
fn mir_type_part_function_param() -> U64 { return 3 }

fn mir_const_unit() -> U64 { return 0 }
fn mir_const_bool() -> U64 { return 1 }
fn mir_const_int() -> U64 { return 2 }
fn mir_const_float() -> U64 { return 3 }
fn mir_const_string() -> U64 { return 4 }

fn mir_param_function() -> U64 { return 1 }
fn mir_param_block() -> U64 { return 2 }

fn mir_value_def_function_param() -> U64 { return 0 }
fn mir_value_def_block_param() -> U64 { return 1 }
fn mir_value_def_instruction() -> U64 { return 2 }
fn mir_value_def_switch_case() -> U64 { return 3 }

fn mir_place_local() -> U64 { return 0 }
fn mir_place_field() -> U64 { return 1 }
fn mir_place_deref() -> U64 { return 2 }

// OpKind values match mir/op.go exactly.
fn mir_op_load() -> U64 { return 0 }
fn mir_op_store() -> U64 { return 1 }
fn mir_op_aggregate_construct() -> U64 { return 2 }
fn mir_op_domain_create() -> U64 { return 3 }
fn mir_op_domain_mark() -> U64 { return 4 }
fn mir_op_domain_reset() -> U64 { return 5 }
fn mir_op_domain_destroy() -> U64 { return 6 }
fn mir_op_alloc() -> U64 { return 7 }
fn mir_op_alloc_checked() -> U64 { return 8 }
fn mir_op_copy_to_domain() -> U64 { return 9 }
fn mir_op_cleanup_scope_begin() -> U64 { return 10 }
fn mir_op_cleanup_push() -> U64 { return 11 }
fn mir_op_cleanup_disarm() -> U64 { return 12 }
fn mir_op_cleanup_scope_run() -> U64 { return 13 }
fn mir_op_cleanup_scope_end() -> U64 { return 14 }
fn mir_op_int_add_checked() -> U64 { return 15 }
fn mir_op_int_sub_checked() -> U64 { return 16 }
fn mir_op_int_mul_checked() -> U64 { return 17 }
fn mir_op_int_div_checked() -> U64 { return 18 }
fn mir_op_int_shl_checked() -> U64 { return 19 }
fn mir_op_int_shr_checked() -> U64 { return 20 }
fn mir_op_slice_len() -> U64 { return 21 }
fn mir_op_slice_index_checked() -> U64 { return 22 }
fn mir_op_slice_range_checked() -> U64 { return 23 }
fn mir_op_enum_payload_checked() -> U64 { return 24 }
fn mir_op_enum_construct() -> U64 { return 25 }
fn mir_op_table_create() -> U64 { return 26 }
fn mir_op_table_insert() -> U64 { return 27 }
fn mir_op_table_lookup() -> U64 { return 28 }
fn mir_op_table_lookup_mut() -> U64 { return 29 }
fn mir_op_table_remove() -> U64 { return 30 }
fn mir_op_table_view_end() -> U64 { return 31 }
fn mir_op_int_eq() -> U64 { return 32 }
fn mir_op_int_ne() -> U64 { return 33 }
fn mir_op_int_lt() -> U64 { return 34 }
fn mir_op_int_le() -> U64 { return 35 }
fn mir_op_int_gt() -> U64 { return 36 }
fn mir_op_int_ge() -> U64 { return 37 }
fn mir_op_float_eq() -> U64 { return 38 }
fn mir_op_float_ne() -> U64 { return 39 }
fn mir_op_float_lt() -> U64 { return 40 }
fn mir_op_float_le() -> U64 { return 41 }
fn mir_op_float_gt() -> U64 { return 42 }
fn mir_op_float_ge() -> U64 { return 43 }
fn mir_op_int_trunc() -> U64 { return 44 }
fn mir_op_int_zext() -> U64 { return 45 }
fn mir_op_int_sext() -> U64 { return 46 }
fn mir_op_float_convert() -> U64 { return 47 }
fn mir_op_int_from_float() -> U64 { return 48 }
fn mir_op_float_from_int() -> U64 { return 49 }
fn mir_op_const_get() -> U64 { return 50 }
fn mir_op_call() -> U64 { return 51 }
fn mir_op_ffi_call_unsafe() -> U64 { return 52 }

fn mir_term_jump() -> U64 { return 0 }
fn mir_term_branch() -> U64 { return 1 }
fn mir_term_switch() -> U64 { return 2 }
fn mir_term_return() -> U64 { return 3 }
fn mir_term_fail() -> U64 { return 4 }
fn mir_term_unreachable() -> U64 { return 5 }
fn mir_term_panic() -> U64 { return 6 }

fn mir_operand_type_part() -> U64 { return 1 }
fn mir_operand_import_param() -> U64 { return 2 }
fn mir_operand_instruction() -> U64 { return 3 }
fn mir_operand_checked_edge_arg() -> U64 { return 4 }
fn mir_operand_terminator_arg() -> U64 { return 5 }
fn mir_operand_switch_case() -> U64 { return 6 }
fn mir_operand_switch_case_arg() -> U64 { return 7 }
fn mir_operand_aggregate_field() -> U64 { return 8 }

fn mir_edge_jump() -> U64 { return 0 }
fn mir_edge_then() -> U64 { return 1 }
fn mir_edge_else() -> U64 { return 2 }

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

// owner is an external Type ID and ordinal is contiguous and zero-based within
// that owner and kind. Named aggregate/enum membership is defined by this
// reciprocal owner scan. first_part/part_count is used only by anonymous
// function types and must describe the same contiguous function-parameter
// records; named types deliberately remain append-only while parts are added.
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

// Import parameters are MirOperandRec records of kind import_param: owner is
// the external Import ID, ordinal is contiguous from zero, and operand_type is
// the parameter Type ID. The import record supplies the result Type ID.

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

// value is the owning function's external logical Value ID. Function
// parameters use block zero; block parameters use the owning external logical
// Block ID. Both have contiguous zero-based ordinals and reciprocal ValueRec
// definitions whose item is ordinal + 1.
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

// ordinal is the function-local Go ValueId encoded as ordinal + 1 when stored
// in another record. item is the defining parameter/instruction/case ordinal
// encoded as ordinal + 1 because zero means absent; block is the external
// logical Block ID. Definitions and sites must link to each other exactly once.
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

// instruction records are globally identified by buffer index + 1. Within each
// block ordinal is contiguous from zero. function must match block ownership;
// a result ValueRec points back with item = ordinal + 1. Ordered operands and
// checked failure arguments are owned by the global instruction ID.
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

// terminators are globally identified by buffer index + 1. Every block owns
// exactly one reciprocal function/block record. Cases and edge arguments are
// ordered operands owned by that global terminator ID.
type MirTermRec {
    function: U64
    block: U64
    kind: U64
    value: U64
    target: U64
    then_block: U64
    else_block: U64
}

// Every owner is an external ID: type ID for type parts, import ID for import
// parameters, global instruction ID for instruction operands/checked arguments
// and aggregate fields, global terminator ID for terminator arguments/switch
// cases, and global switch-case operand ID for switch-case arguments. Ordinals
// are contiguous from zero within (kind, owner, edge). edge disambiguates jump,
// branch-then, and branch-else arguments even when targets are equal. A switch
// case's value is its optional payload-binding Value ID, target is its Block
// ID, and empty name denotes default. Switch-case args inherit the case target.
type MirOperandRec {
    kind: U64
    owner: U64
    ordinal: U64
    edge: U64
    value: U64
    target: U64
    operand_type: U64
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
