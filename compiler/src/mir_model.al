// Independent MIR 4 storage model. Every external identity is a 1-based U64;
// zero means absent. A nonzero module-table ID converts to a Go MIR ID by
// subtracting one. Function-local block, value, and local IDs similarly store
// ordinal + 1 and are resolved by scanning the flat buffer for the owning
// function and zero-based ordinal. Flat record owners (instruction,
// terminator, operand, and type-part IDs) are global buffer index + 1.
// Builders append but do not validate or normalize records, so rejection tests
// may construct malformed raw stores.

fn mir_format_version() -> U64 { return 6 }

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
fn mir_type_kind_array() -> U64 { return 18 }
fn mir_type_kind_string() -> U64 { return 19 }
fn mir_type_kind_bytes() -> U64 { return 20 }
fn mir_type_kind_vec() -> U64 { return 21 }
fn mir_type_kind_c_raw() -> U64 { return 22 }
fn mir_type_kind_c_ptr() -> U64 { return 23 }
fn mir_type_kind_c_const_ptr() -> U64 { return 24 }
fn mir_type_kind_c_named() -> U64 { return 25 }
fn mir_type_kind_c_string() -> U64 { return 26 }
fn mir_type_kind_c_callback_owner() -> U64 { return 27 }
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
// The fn.value domain marker value: type_op on fn.value carries this flag
// when the environment operand supplies the callee's hidden leading domain
// parameter. The value is deliberately far outside any real type id range
// so it can never collide with an op that reads type_op as a type.
fn mir_fn_value_domain_marker() -> U64 { return 2147483647 }

fn mir_primitive_type_count() -> U64 { return 12 }

fn mir_type_part_field() -> U64 { return 1 }
fn mir_type_part_variant() -> U64 { return 2 }
fn mir_type_part_function_param() -> U64 { return 3 }
fn mir_type_part_function_env() -> U64 { return 4 }
fn mir_type_part_c_field() -> U64 { return 5 }

// CClass values match mir/types.go: scalar, opaque, record.
fn mir_c_class_scalar() -> U64 { return 0 }
fn mir_c_class_opaque() -> U64 { return 1 }
fn mir_c_class_record() -> U64 { return 2 }
fn mir_c_class_callback() -> U64 { return 3 }

// C scalar ids for TypeCRaw payloads, matching mir/types.go order.
fn mir_c_scalar_count() -> U64 { return 15 }

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
fn mir_op_borrow() -> U64 { return 53 }
fn mir_op_borrow_mut() -> U64 { return 54 }
fn mir_op_array_index_checked() -> U64 { return 55 }
fn mir_op_vec_new() -> U64 { return 56 }
fn mir_op_vec_construct_checked() -> U64 { return 57 }
fn mir_op_vec_grow_checked() -> U64 { return 58 }
fn mir_op_vec_len() -> U64 { return 59 }
fn mir_op_vec_capacity() -> U64 { return 60 }
fn mir_op_vec_storage() -> U64 { return 61 }
fn mir_op_vec_as_slice() -> U64 { return 62 }
fn mir_op_vec_as_mut_slice() -> U64 { return 63 }
fn mir_op_array_as_slice() -> U64 { return 64 }
fn mir_op_call_value() -> U64 { return 65 }
fn mir_op_str_eq() -> U64 { return 66 }
fn mir_op_fn_value() -> U64 { return 67 }
fn mir_op_table_insert_try() -> U64 { return 68 }
fn mir_op_c_binding_call() -> U64 { return 69 }
fn mir_op_c_is_null() -> U64 { return 70 }
fn mir_op_int_add_try() -> U64 { return 71 }
fn mir_op_int_sub_try() -> U64 { return 72 }
fn mir_op_int_mul_try() -> U64 { return 73 }
fn mir_op_int_add_saturating() -> U64 { return 74 }
fn mir_op_int_sub_saturating() -> U64 { return 75 }
fn mir_op_int_mul_saturating() -> U64 { return 76 }
fn mir_op_int_add_wrapping() -> U64 { return 77 }
fn mir_op_int_sub_wrapping() -> U64 { return 78 }
fn mir_op_int_mul_wrapping() -> U64 { return 79 }
fn mir_op_str_len() -> U64 { return 80 }
fn mir_op_str_byte_checked() -> U64 { return 81 }
fn mir_op_str_concat() -> U64 { return 82 }
fn mir_op_str_slice_checked() -> U64 { return 83 }
fn mir_op_str_to_bytes() -> U64 { return 84 }
fn mir_op_str_from_bytes() -> U64 { return 85 }
fn mir_op_int_convert_checked() -> U64 { return 86 }
fn mir_op_int_convert_wrap() -> U64 { return 87 }
fn mir_op_c_num_try() -> U64 { return 88 }
fn mir_op_c_num_wrap() -> U64 { return 89 }
fn mir_op_c_num_cast() -> U64 { return 90 }
fn mir_op_float_add() -> U64 { return 91 }
fn mir_op_float_sub() -> U64 { return 92 }
fn mir_op_float_mul() -> U64 { return 93 }
fn mir_op_float_div() -> U64 { return 94 }
fn mir_op_str_order_lt() -> U64 { return 95 }
fn mir_op_c_field_get() -> U64 { return 96 }
fn mir_op_c_field_set() -> U64 { return 97 }
fn mir_op_c_string_make_lit() -> U64 { return 98 }
fn mir_op_c_string_make() -> U64 { return 99 }
fn mir_op_c_string_ptr() -> U64 { return 100 }
fn mir_op_c_string_release() -> U64 { return 101 }
fn mir_op_str_display() -> U64 { return 102 }
// Total bitwise operations over the fixed-width two's-complement
// representation. 111 and up stay unassigned.
fn mir_op_int_and() -> U64 { return 103 }
fn mir_op_int_or() -> U64 { return 104 }
fn mir_op_int_xor() -> U64 { return 105 }
fn mir_op_int_not() -> U64 { return 106 }
// One call-scoped borrow of an Alder buffer as a C pointer. The operand is
// bytes, slice(u8), or safe_mut(u8); type_op is the declared c pointer type.
fn mir_op_c_buffer_ptr() -> U64 { return 107 }
// [U8].to_bytes copies a byte view into fresh bytes storage in the domain
// operand a; operand b is the slice. Allocation failure takes the edge.
fn mir_op_slice_to_bytes() -> U64 { return 120 }
// A zero-initialized by-value C boundary value; type_op names a c_raw or a
// by-value c_named scalar or record.
fn mir_op_c_zero() -> U64 { return 109 }
// The address of a local place as a declared C pointer type for one raw call
// argument; type_op names c_ptr or c_const_ptr over the place's own type.
fn mir_op_c_addr() -> U64 { return 110 }

// c.callback.make pairs one noncapturing Alder function with a bound C
// function-pointer type. Its result is the callback type operand.
fn mir_op_c_callback_make() -> U64 { return 111 }

// c.callback.owner.register creates the retained owner value; its metadata
// fields are documented in docs/mir.md.
fn mir_op_c_callback_owner_register() -> U64 { return 112 }
fn mir_op_c_callback_owner_release() -> U64 { return 114 }

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
fn mir_operand_binding_param() -> U64 { return 9 }
fn mir_operand_binding_type() -> U64 { return 10 }

fn mir_edge_jump() -> U64 { return 0 }
fn mir_edge_then() -> U64 { return 1 }
fn mir_edge_else() -> U64 { return 2 }

// Type kinds mirror mir/types.go: primitive, aggregate, enum, option, result,
// slice, safe_ref, safe_mut, raw_ptr, function, domain_handle, domain_mark,
// cleanup_scope, cleanup_id, table, id, table_view, table_mut_view, array,
// string, bytes, vec, c_raw, c_ptr, c_const_ptr, and c_named. c_name carries
// the C spelling of a c_named member (empty elsewhere), c_class its binding
// class, and length the c_raw C-scalar id.
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
    length: U64
    c_name_start: U64
    c_name_end: U64
    c_class: U64
}

// owner is an external Type ID and ordinal is contiguous and zero-based within
// that owner and kind. Named aggregate/enum membership is defined by this
// reciprocal owner scan. first_part/part_count is used only by anonymous
// function types and must describe the same contiguous function-parameter
// records; named types deliberately remain append-only while parts are added.
// c_name carries the C field spelling of a c_field part (empty elsewhere).
type MirTypePartRec {
    kind: U64
    owner: U64
    ordinal: U64
    name_start: U64
    name_end: U64
    part_type: U64
    c_name_start: U64
    c_name_end: U64
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
    // A C export keeps its source-level symbol name here even when the MIR
    // function name carries a module-uniqueness suffix.
    c_export: Bool
    export_name_start: U64
    export_name_end: U64
    // A call to this function cannot return, so a reachable block ending in
    // `unreachable` after the call is valid. Lowering marks core.panic.panic.
    noreturn: Bool
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

// One C binding block: the Alder-visible name, the quoted header, and the
// members. Types are ordered operand records (kind binding_type, owner =
// external block ID) whose operand_type is the c_named Type ID. Functions and
// constants are dedicated records below; a function's parameters are ordered
// operand records (kind binding_param, owner = external flat function ID).
// Buffer order is block-major and matches the Go flat BindingFunc indices.
type MirBindingRec {
    name_start: U64
    name_end: U64
    header_start: U64
    header_end: U64
}

type MirBindingFnRec {
    block: U64
    name_start: U64
    name_end: U64
    c_name_start: U64
    c_name_end: U64
    result_type: U64
}

type MirBindingConstRec {
    block: U64
    name_start: U64
    name_end: U64
    c_name_start: U64
    c_name_end: U64
    const_type: U64
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
    bindings: __s0_Buffer(MirBindingRec)
    binding_funcs: __s0_Buffer(MirBindingFnRec)
    binding_consts: __s0_Buffer(MirBindingConstRec)
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
