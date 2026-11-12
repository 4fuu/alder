// Final conservative C11/backend checks. Earlier phases own structural, type,
// function, instruction, and terminator validity; this phase refuses the
// remaining forms which those valid records cannot lower safely.
fn mir_v10_name_prefix(store: MirStore, start: U64, end: U64, word: __s0_String) -> Bool {
    if end - start < len(word) { return false }
    var at: U64 = 0
    while at < len(word) { if __s0_buffer_get(U8, store.names, start + at) != word[at] { return false }
at = at + 1 }
    return true
}
fn mir_v10_name_suffix(store: MirStore, start: U64, end: U64, word: __s0_String) -> Bool {
    if end - start < len(word) { return false }
    return mir_vname_word(store, end - len(word), end, word)
}
fn mir_v10_name_list(store: MirStore, start: U64, end: U64, words: __s0_String) -> Bool {
    var first: U64 = 0
var at: U64 = 0
    while at <= len(words) {
        if at == len(words) || words[at] == 44 { if at - first == end - start { var same = true
var byte: U64 = 0
while same && byte < at - first { if words[first + byte] != __s0_buffer_get(U8, store.names, start + byte) { same = false }
byte = byte + 1 }
if same { return true } }
first = at + 1 }
        at = at + 1
    }
    return false
}
fn mir_v10_header_name(store: MirStore, start: U64, end: U64) -> Bool {
    if mir_v10_name_suffix(store, start, end, "_t") { return true }
    if mir_v10_name_list(store, start, end, "main,bool,true,false,NULL,offsetof,memchr,memcmp,memcpy,memmove,memset,strcat,strchr,strcmp,strcoll,strcpy,strcspn,strerror,strlen,strncat,strncmp,strncpy,strpbrk,strrchr,strspn,strstr,strtok,strxfrm") { return true }
    var macro = __s0_buffer_get(U8, store.names, start) >= 65 && __s0_buffer_get(U8, store.names, start) <= 90
var at = start + 1
    while macro && at < end { let byte = __s0_buffer_get(U8, store.names, at)
macro = byte == 95 || byte >= 65 && byte <= 90 || byte >= 48 && byte <= 57
at = at + 1 }
    return macro
}
fn mir_v10_external_name(store: MirStore, start: U64, end: U64) -> Bool {
    if !mir_vname_valid(store, start, end, false) || __s0_buffer_get(U8, store.names, start) == 95 { return false }
    if mir_v10_name_prefix(store, start, end, "alder_") || mir_v10_name_prefix(store, start, end, "ALDER_") || mir_v10_name_prefix(store, start, end, "Alder") { return false }
    if mir_v10_name_list(store, start, end, "_Alignas,_Alignof,_Atomic,_Bool,_Complex,_Generic,_Imaginary,_Noreturn,_Static_assert,_Thread_local,auto,break,case,char,const,continue,default,do,double,else,enum,extern,float,for,goto,if,inline,int,long,register,restrict,return,short,signed,sizeof,static,struct,switch,typedef,union,unsigned,void,volatile,while") { return false }
    return !mir_v10_header_name(store, start, end)
}
// Binding spellings reference C names rather than declare them, so header
// families like time_t and macro-style constants such as CLOCKS_PER_SEC are
// legal; a wrong spelling is caught by the generated probes. Still rejected:
// leading underscores, C keywords, and the runtime namespace.
fn mir_v10_binding_name(store: MirStore, start: U64, end: U64) -> Bool {
    if !mir_vname_valid(store, start, end, false) || __s0_buffer_get(U8, store.names, start) == 95 { return false }
    if mir_v10_name_prefix(store, start, end, "alder_") || mir_v10_name_prefix(store, start, end, "ALDER_") || mir_v10_name_prefix(store, start, end, "Alder") { return false }
    return !mir_v10_name_list(store, start, end, "_Alignas,_Alignof,_Atomic,_Bool,_Complex,_Generic,_Imaginary,_Noreturn,_Static_assert,_Thread_local,auto,break,case,char,const,continue,default,do,double,else,enum,extern,float,for,goto,if,inline,int,long,register,restrict,return,short,signed,sizeof,static,struct,switch,typedef,union,unsigned,void,volatile,while")
}

// A named C binding type's spelling may carry a struct/union/enum tag, which
// the member's own identifier follows; a scalar member binds a typedef or
// enum name, so its tag form is rejected like the Go verifier's
// checkCSpelling.
fn mir_v10_c_member_spelling_ok(store: MirStore, t: MirTypeRec) -> Bool {
    var start = t.c_name_start
    var tagged = false
    if mir_v10_name_prefix(store, start, t.c_name_end, "struct ") { tagged = true
        start = start + 7 }
    if !tagged && mir_v10_name_prefix(store, start, t.c_name_end, "union ") { tagged = true
        start = start + 6 }
    if !tagged && mir_v10_name_prefix(store, start, t.c_name_end, "enum ") { tagged = true
        start = start + 5 }
    if tagged && t.c_class == mir_c_class_scalar() { return false }
    return mir_v10_binding_name(store, start, t.c_name_end)
}

fn mir_v10_bindings(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
    var fn_at: U64 = 0
    while fn_at < __s0_buffer_len(MirBindingFnRec, store.binding_funcs) {
        let item = __s0_buffer_get(MirBindingFnRec, store.binding_funcs, fn_at)
        if !mir_v10_binding_name(store, item.c_name_start, item.c_name_end) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_c_external_name(), 0, 0, 0, 0, 0, item.block, fn_at + 1, 0, 0, fn_at + 1)) }
        fn_at = fn_at + 1
    }
    var const_at: U64 = 0
    while const_at < __s0_buffer_len(MirBindingConstRec, store.binding_consts) {
        let item = __s0_buffer_get(MirBindingConstRec, store.binding_consts, const_at)
        if !mir_v10_binding_name(store, item.c_name_start, item.c_name_end) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_c_external_name(), 0, 0, 0, 0, 0, item.block, const_at + 1, 0, 0, const_at + 1)) }
        const_at = const_at + 1
    }
    var at: U64 = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let t = __s0_buffer_get(MirTypeRec, store.types, at)
        if t.kind == mir_type_kind_c_named() {
            if !mir_v10_c_member_spelling_ok(store, t) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_c_external_name(), 0, 0, 0, 0, 0, at + 1, at + 1, 0, 0, at + 1)) }
            var field_at: U64 = 0
            while field_at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
                let part = __s0_buffer_get(MirTypePartRec, store.type_parts, field_at)
                if part.owner == at + 1 && part.kind == mir_type_part_c_field() && !mir_v10_binding_name(store, part.c_name_start, part.c_name_end) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_c_external_name(), 0, 0, 0, 0, 0, at + 1, field_at + 1, 0, 0, field_at + 1)) }
                field_at = field_at + 1
            }
        }
        at = at + 1
    }
    return Ok(out)
}

fn mir_v10_forbidden_element(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(U64, __s0_Error) {
    // A closure environment record records the domain that owns it; the
    // retain hook rewrites that field when the record moves domains.
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_handle()) && !mir_v6_env_record(store, indexes, type_id) { return Ok(mir_type_kind_domain_handle()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_mark()) { return Ok(mir_type_kind_domain_mark()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_cleanup_scope()) { return Ok(mir_type_kind_cleanup_scope()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_cleanup_id()) { return Ok(mir_type_kind_cleanup_id()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table_view()) { return Ok(mir_type_kind_table_view()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table_mut_view()) { return Ok(mir_type_kind_table_mut_view()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_raw_ptr()) { return Ok(mir_type_kind_raw_ptr()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_raw()) { return Ok(mir_type_kind_c_raw()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_ptr()) { return Ok(mir_type_kind_c_ptr()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_const_ptr()) { return Ok(mir_type_kind_c_const_ptr()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_named()) { return Ok(mir_type_kind_c_named()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_string()) { return Ok(mir_type_kind_c_string()) }
    return Ok(0)
}
fn mir_v10_forbidden_copy(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(U64, __s0_Error) {
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_handle()) { return Ok(mir_type_kind_domain_handle()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_mark()) { return Ok(mir_type_kind_domain_mark()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_cleanup_scope()) { return Ok(mir_type_kind_cleanup_scope()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_cleanup_id()) { return Ok(mir_type_kind_cleanup_id()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) { return Ok(mir_type_kind_table()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table_view()) { return Ok(mir_type_kind_table_view()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table_mut_view()) { return Ok(mir_type_kind_table_mut_view()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_raw_ptr()) { return Ok(mir_type_kind_raw_ptr()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_raw()) { return Ok(mir_type_kind_c_raw()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_ptr()) { return Ok(mir_type_kind_c_ptr()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_const_ptr()) { return Ok(mir_type_kind_c_const_ptr()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_named()) { return Ok(mir_type_kind_c_named()) }
    if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_c_string()) { return Ok(mir_type_kind_c_string()) }
    return Ok(0)
}
fn mir_vphase10(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
    var out = initial
var import_id: U64 = 1
    while import_id <= __s0_buffer_len(MirImportRec, store.imports) { let item = __s0_buffer_get(MirImportRec, store.imports, import_id - 1)
if !mir_v10_external_name(store, item.name_start, item.name_end) { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_c_external_name(), 0, 0, 0, 0, 0, 0, import_id, 0, 0, import_id)) }
import_id = import_id + 1 }
    var iid: U64 = 1
    while iid <= __s0_buffer_len(MirInstrRec, store.instructions) { let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_table_create() { let forbidden = try mir_v10_forbidden_element(d, store, indexes, x.type_op)
if forbidden != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_backend_element_type(), x.function, x.block, iid, 0, 0, x.type_op, 0, 0, forbidden, x.type_op)) } }
if x.op == mir_op_copy_to_domain() { let copied_type = mir_v5_value_type(store, indexes, x.function, x.b)
let forbidden = try mir_v10_forbidden_copy(d, store, indexes, copied_type)
if forbidden != 0 { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_copy_source_type(), x.function, x.block, iid, 0, 0, copied_type, 0, 0, forbidden, copied_type)) } }
iid = iid + 1 }
    return mir_v10_bindings(d, store, out)
}

fn mir_v10_param_count(store: MirStore, function: U64) -> U64 {
    var want: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let item = __s0_buffer_get(MirParamRec, store.params, at)
        if item.kind == mir_param_function() && item.function == function { want = want + 1 }
        at = at + 1
    }
    return want
}

fn mir_v10_param_type(store: MirStore, function: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirParamRec, store.params) {
        let item = __s0_buffer_get(MirParamRec, store.params, at)
        if item.kind == mir_param_function() && item.function == function && item.ordinal == ordinal { return item.param_type }
        at = at + 1
    }
    return 0
}

// True when the module defines at least one intentional C export, which
// makes a main-less source set a library build rather than a hosted program.
fn mir_v10_has_export(store: MirStore) -> Bool {
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        if __s0_buffer_get(MirFunctionRec, store.functions, function - 1).c_export { return true }
        function = function + 1
    }
    return false
}

fn mir_v10_entry(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(MirVerifyCompleteOutput, __s0_Error) {
    var out = initial
var entry: U64 = 0
var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) { let item = __s0_buffer_get(MirFunctionRec, store.functions, function - 1)
if mir_vname_word(store, item.name_start, item.name_end, "main") { entry = function }
function = function + 1 }
    if entry == 0 {
        // A library build has no hosted entry. Only this entry phase is
        // skipped: every earlier V1-V9 check has already run, and a source set
        // with neither main nor an export keeps the missing-entry diagnostic.
        if mir_v10_has_export(store) { return Ok(MirVerifyCompleteOutput(diagnostics: out, complete: true, hosted: false, entry: 0)) }
        out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_missing_entry(), 0, 0, 0, 0, 0, 0, 0, 1, 0, 0))
        return Ok(MirVerifyCompleteOutput(diagnostics: out, complete: false, hosted: true, entry: 0))
    }
    let item = __s0_buffer_get(MirFunctionRec, store.functions, entry - 1)
    if item.result_type != mir_type_i32() { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_entry_result(), entry, 0, 0, 0, 0, item.result_type, entry, mir_type_i32(), item.result_type, entry)) }
    let count = mir_v10_param_count(store, entry)
    var signature = count == 0
    if count == 1 { signature = mir_vtype_kind(store, mir_v10_param_type(store, entry, 0)) == mir_type_kind_domain_handle() }
    if !signature { out = try mir_vadd(d, out, mir_vdiag(mir_verify_phase_backend(), mir_vdiag_entry_signature(), entry, 0, 0, 0, 0, 0, entry, 1, count, entry)) }
    let complete = __s0_buffer_len(MirVerifyDiagRec, out) == 0
    if !complete { entry = 0 }
    return Ok(MirVerifyCompleteOutput(diagnostics: out, complete: complete, hosted: true, entry: entry))
}

fn mir_verify_complete(d: Domain, store: MirStore, version: U64, hosted: Bool) -> Result(MirVerifyCompleteOutput, __s0_Error) {
    let verified = try mir_verify_module(d, store, version)
    if __s0_buffer_len(MirVerifyDiagRec, verified.diagnostics) != 0 { return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: false, hosted: hosted, entry: 0)) }
    if hosted { return mir_v10_entry(d, store, verified.diagnostics) }
    return Ok(MirVerifyCompleteOutput(diagnostics: verified.diagnostics, complete: true, hosted: false, entry: 0))
}
