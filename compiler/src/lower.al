// Deterministic lowering from the sealed checked model to independent MIR 4.
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
    initial: U64
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

type LowerLocalIndex {
    starts: __s0_Buffer(U64)
    ids: __s0_Buffer(U64)
}

// Owner-keyed index over MirStore.type_parts. The MIR type table only grows
// during lowering, so the index is extended lazily instead of being rebuilt:
// head[owner] is the 1-based position of that owner's most recently linked
// part and next[p - 1] chains to the previous one, which visits an owner's
// parts in reverse table order. mir_add_type_part and mir_intern_type only
// ever append a part whose owner is a type id that already exists, so an
// owner is always within range when its part is linked.
type LowerPartIndex {
    head: __s0_Buffer(U64)
    next: __s0_Buffer(U64)
    indexed: U64
}

type LowerState {
    mir: MirStore
    types: __s0_Buffer(LowerTypeMapRec)
    owners: __s0_Buffer(LowerOwnerMapRec)
    roots: __s0_Buffer(LowerOwnerMapRec)
    binding_statements: __s0_Buffer(U64)
    imports: __s0_Buffer(LowerOwnerMapRec)
    bindings: __s0_Buffer(LowerBindingMapRec)
    values: __s0_Buffer(LowerValueMapRec)
    releases: __s0_Buffer(LowerValueMapRec)
    bridges: __s0_Buffer(LowerBridgeRec)
    storage: __s0_Buffer(U64)
    part_index: LowerPartIndex
    // lower_has_storage(store), computed once: the checked store is fixed
    // while lowering, and the walk is too costly to repeat per site.
    has_storage: Bool
    // D023 move plan of the function being lowered: per-expression move
    // verdicts and per-site copy reasons, computed once per owner.
    moves: LowerMovePlan
    // Owner-keyed CSR over store.locals (lower_local_indexes), built once
    // per compile: the checked store is fixed while lowering, and the
    // call-argument borrow scan below must not walk the whole locals table
    // per argument.
    local_index: LowerLocalIndex
    // Copy-site report records (D023), collected as copies are emitted.
    reports: __s0_Buffer(CopySiteRec)
    // Innermost enclosing loop: the block `break` jumps to and the block
    // `continue` jumps to, both zero outside every loop. They ride in the
    // state so a match arm's statement block inherits them without threading
    // a loop context through every expression call.
    loop_exit: U64
    loop_step: U64
    // The environment enclosing the innermost loop body. `break` and
    // `continue` run the registrations they cross by walking up to it.
    loop_environment: U64
    // Vec-membership memo over MIR type ids, filled on demand by
    // lower_mir_type_contains_vec. MIR types are append-only while lowering,
    // so recorded entries stay valid as the arrays grow; every entry comes
    // from running the original walk, so answers are unchanged.
    vec_memo_flag: __s0_Buffer(U64)
    vec_memo_ans: __s0_Buffer(U64)
    vec_memo_seen: __s0_Buffer(U64)
    vec_memo_gen: U64
    valid: Bool
}

// The D023 move plan of one concrete function instance, indexed by checked
// expression ID on both axes: movable marks the binding reads that may
// transfer their source storage instead of copying it, and reasons carries
// the report reason of that read's own copy site (zero when nothing blocks
// it). Per site, not per binding: one binding can have a read that copies for
// one reason and a later read that moves.
type LowerMovePlan {
    movable: __s0_Buffer(U64)
    reasons: __s0_Buffer(U64)
    // Reusable exclusion flags for lower_move_analyze: one buffer sized to
    // the global local count at plan creation and cleared in place per
    // function, so per-function analysis stops leaving a dead doubling chain
    // in the compile domain.
    excluded_scratch: __s0_Buffer(U64)
}

// One binding access in lowering order: a read of expression, or a
// definition of binding (expression zero).
type LowerMoveEventRec {
    binding: U64
    expression: U64
    is_definition: U64
}

// One loop's event range [first_event, end_event) plus the enclosing loop;
// ranges nest because the event list follows the statement tree.
type LowerMoveLoopRec {
    first_event: U64
    end_event: U64
    parent: U64
    // Set when the body contains a construct that may skip a later statement
    // (an if, a match or try expression, or a nested loop). The loop-rebuild
    // move needs a straight-line body, so the flag gates it.
    conditional: U64
}

fn lower_with_plan(state: LowerState, moves: LowerMovePlan) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_loop(state: LowerState, loop_exit: U64, loop_step: U64, loop_environment: U64) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, loop_exit: loop_exit, loop_step: loop_step, loop_environment: loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen, valid: state.valid)
}

fn lower_with_reports(state: LowerState, reports: __s0_Buffer(CopySiteRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_vec_memo(state: LowerState, flag: __s0_Buffer(U64), ans: __s0_Buffer(U64), seen: __s0_Buffer(U64), gen: U64) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: flag, vec_memo_ans: ans, vec_memo_seen: seen, vec_memo_gen: gen)
}

fn lower_add_copy_report(d: Domain, state: LowerState, owner: U64, source: U64, start: U64, end: U64, binding: U64, reason: U64) -> Result(LowerState, __s0_Error) {
    let reports = try __s0_buffer_append(CopySiteRec, d, state.reports, CopySiteRec(owner: owner, source: source, start: start, end: end, binding: binding, reason: reason))
    return Ok(lower_with_reports(state, reports))
}

type LowerStep {
    state: LowerState
    id: U64
}

type LowerVecStep {
    state: LowerState
    value: Bool
}

type LowerFlowStep {
    state: LowerState
    block: U64
    terminated: Bool
}

type LowerGoodRec {
    mir: MirStore
    reports: __s0_Buffer(CopySiteRec)
}

enum LowerResult {
    LowerGood(value: LowerGoodRec)
    LowerBad
    LowerModelBad
}

fn lower_with_mir(state: LowerState, mir: MirStore) -> LowerState {
    return LowerState(mir: mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

// Intern an anonymous function type: contiguous parameter parts, an
// optional trailing environment part, and the result type. Unlike
// mir_intern_type, the environment part is part of the interned shape.
fn mir_intern_function_type(d: Domain, store: MirStore, params: __s0_Buffer(U64), result_type: U64, env_type: U64) -> Result(MirTypeStep, __s0_Error) {
    var at: U64 = mir_primitive_type_count()
    while at < __s0_buffer_len(MirTypeRec, store.types) {
        let prior = __s0_buffer_get(MirTypeRec, store.types, at)
        if prior.kind == mir_type_kind_function() && prior.result_type == result_type {
            var param_at: U64 = 0
            var want_parts = __s0_buffer_len(U64, params) + 1
            if env_type == 0 { want_parts = __s0_buffer_len(U64, params) }
            var same = prior.part_count == want_parts
            while same && param_at < __s0_buffer_len(U64, params) {
                let part = __s0_buffer_get(MirTypePartRec, store.type_parts, prior.first_part - 1 + param_at)
                if part.kind != mir_type_part_function_param() || part.part_type != __s0_buffer_get(U64, params, param_at) { same = false }
                param_at = param_at + 1
            }
            if same && env_type != 0 {
                let part = __s0_buffer_get(MirTypePartRec, store.type_parts, prior.first_part - 1 + param_at)
                if part.kind != mir_type_part_function_env() || part.part_type != env_type { same = false }
            }
            if same { return Ok(MirTypeStep(store: store, type_id: at + 1)) }
        }
        at = at + 1
    }
    let type_id = __s0_buffer_len(MirTypeRec, store.types) + 1
    var type_parts = store.type_parts
    var first: U64 = 0
    var part_at: U64 = 0
    while part_at < __s0_buffer_len(U64, params) {
        if first == 0 { first = __s0_buffer_len(MirTypePartRec, type_parts) + 1 }
        type_parts = try __s0_buffer_append(MirTypePartRec, d, type_parts, MirTypePartRec(kind: mir_type_part_function_param(), owner: type_id, ordinal: part_at, name_start: 0, name_end: 0, part_type: __s0_buffer_get(U64, params, part_at), c_name_start: 0, c_name_end: 0))
        part_at = part_at + 1
    }
    if env_type != 0 {
        if first == 0 { first = __s0_buffer_len(MirTypePartRec, type_parts) + 1 }
        type_parts = try __s0_buffer_append(MirTypePartRec, d, type_parts, MirTypePartRec(kind: mir_type_part_function_env(), owner: type_id, ordinal: 0, name_start: 0, name_end: 0, part_type: env_type, c_name_start: 0, c_name_end: 0))
        part_at = part_at + 1
    }
    let rec = MirTypeRec(kind: mir_type_kind_function(), name_start: 0, name_end: 0, elem: 0, ok_type: 0, err_type: 0, first_part: first, part_count: part_at, result_type: result_type, length: 0, c_name_start: 0, c_name_end: 0, c_class: mir_c_class_scalar())
    let types = try __s0_buffer_append(MirTypeRec, d, store.types, rec)
    return Ok(MirTypeStep(store: mir_with_types(mir_with_type_parts(store, type_parts), types), type_id: type_id))
}

fn lower_with_type_parts(state: LowerState, parts: __s0_Buffer(MirTypePartRec)) -> LowerState {
    return lower_with_mir(state, mir_with_type_parts(state.mir, parts))
}

fn lower_invalid(state: LowerState) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: false, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_types(state: LowerState, types: __s0_Buffer(LowerTypeMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_owners(state: LowerState, owners: __s0_Buffer(LowerOwnerMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_imports(state: LowerState, imports: __s0_Buffer(LowerOwnerMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_bindings(state: LowerState, bindings: __s0_Buffer(LowerBindingMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_values(state: LowerState, values: __s0_Buffer(LowerValueMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_releases(state: LowerState, releases: __s0_Buffer(LowerValueMapRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: releases, bridges: state.bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_bridges(state: LowerState, bridges: __s0_Buffer(LowerBridgeRec)) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: bridges, storage: state.storage, part_index: state.part_index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
}

fn lower_with_part_index(state: LowerState, index: LowerPartIndex) -> LowerState {
    return LowerState(mir: state.mir, types: state.types, owners: state.owners, roots: state.roots, binding_statements: state.binding_statements, imports: state.imports, bindings: state.bindings, values: state.values, releases: state.releases, bridges: state.bridges, storage: state.storage, part_index: index, has_storage: state.has_storage, moves: state.moves, local_index: state.local_index, reports: state.reports, valid: state.valid, loop_exit: state.loop_exit, loop_step: state.loop_step, loop_environment: state.loop_environment, vec_memo_flag: state.vec_memo_flag, vec_memo_ans: state.vec_memo_ans, vec_memo_seen: state.vec_memo_seen, vec_memo_gen: state.vec_memo_gen)
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

// lower_release_lookup returns the cleanup-id MIR value registered for a
// using binding, or zero when the binding has no cleanup registration.
fn lower_release_lookup(state: LowerState, binding: U64) -> U64 {
    var at = __s0_buffer_len(LowerValueMapRec, state.releases)
    while at > 0 {
        let item = __s0_buffer_get(LowerValueMapRec, state.releases, at - 1)
        if item.expression == binding { return item.value }
        at = at - 1
    }
    return 0
}

fn lower_word(d: Domain, bytes: __s0_Buffer(U8), start: U64, end: U64) -> Result(__s0_String, __s0_Error) {
    var out = try __s0_buffer_new(U8, d)
    var at = start
    while at < end {
        out = try __s0_buffer_append(U8, d, out, __s0_buffer_get(U8, bytes, at))
        at = at + 1
    }
    return Ok(__s0_buffer_slice(U8, out))
}

fn lower_source_word(d: Domain, source_state: State, source: U64, start: U64, end: U64) -> Result(__s0_String, __s0_Error) {
    if source >= __s0_buffer_len(SourceRec, source_state.sources) { return lower_word(d, source_state.texts, 0, 0) }
    let rec = __s0_buffer_get(SourceRec, source_state.sources, source)
    return lower_word(d, source_state.texts, rec.text_start + start, rec.text_start + end)
}

fn lower_decimal_name(d: Domain, prefix: __s0_String, value: U64) -> Result(__s0_String, __s0_Error) {
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
    return LowerBindingMapRec(binding: 0, mir_id: 0, parameter: 0, initial: 0)
}

// Index of the closure site owned by symbol `owner`, or zero. Closure sites
// are few; the scan runs once per function skeleton and once per closure
// expression, never per expression.
fn lower_closure_site_for(store: CheckStore, owner: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(ClosureSiteRec, store.closures.sites) {
        if __s0_buffer_get(ClosureSiteRec, store.closures.sites, at).owner == owner { return at + 1 }
        at = at + 1
    }
    return 0
}

// The checked local id of the owner's ordinal-th kind-1 (parameter-kind)
// local. Closure captures are the thunk's trailing parameter-kind locals in
// the same order as the site's capture list.
fn lower_closure_param_local(store: CheckStore, locals: LowerLocalIndex, owner: U64, ordinal: U64) -> U64 {
    var start = __s0_buffer_get(U64, locals.starts, owner - 1)
    let end = __s0_buffer_get(U64, locals.starts, owner)
    var seen: U64 = 0
    while start < end {
        let binding = __s0_buffer_get(U64, locals.ids, start)
        let local = __s0_buffer_get(LocalRec, store.locals, binding - 1)
        if local.kind == 1 {
            if seen == ordinal { return binding }
            seen = seen + 1
        }
        start = start + 1
    }
    return 0
}

// The closure environment record type: one field per capture, named after
// the captured binding. Built once per closure site and memoized in the
// value map under a key far above any expression id.
fn lower_closure_env_key(owner: U64) -> U64 { return owner + 4000000000 }

// The referencing function's own domain PARAMETER — the caller-provided
// ancestor domain, not the function's ephemeral child — is what a marked
// fn.value captures, so the value never outlives the domain it holds.
fn lower_env_domain_key(owner: U64) -> U64 { return owner + 4100000000 }

fn lower_closure_env_type(d: Domain, source_state: State, store: CheckStore, state: LowerState, site: ClosureSiteRec) -> Result(LowerStep, __s0_Error) {
    let prior = lower_keyed_domain_value(state, lower_closure_env_key(site.owner))
    if prior != 0 { return Ok(LowerStep(state: state, id: prior)) }
    let named = try mir_add_named_type(d, state.mir, mir_type_kind_aggregate(), try lower_decimal_name(d, "AlderClosureEnv_", site.owner))
    var current = lower_with_mir(state, named.store)
    // One field per capture, named after the captured binding. The domain
    // that owns the record comes first: the thunk uses it as its active and
    // result domain, so a body that copies or allocates storage has somewhere
    // to put it, and the retain hook rewrites the field when the record moves
    // to another domain.
    let domain_type = try lower_domain_mir_type(d, current)
    current = domain_type.state
    current = lower_with_mir(current, try mir_add_type_part(d, current.mir, mir_type_part_field(), named.type_id, 0, "alder_env_domain", domain_type.id))
    var field_ordinal: U64 = 1
    var ordinal: U64 = 0
    while ordinal < site.capture_count {
        let capture = __s0_buffer_get(ClosureCaptureRec, store.closures.captures, site.first_capture - 1 + ordinal)
        let local = __s0_buffer_get(LocalRec, store.locals, capture.local - 1)
        let typ = try lower_type(d, source_state, store, current, capture.checked_type)
        if !typ.state.valid { return Ok(typ) }
        current = typ.state
        let name = try lower_source_word(d, source_state, local.source, local.name_start, local.name_end)
        current = lower_with_mir(current, try mir_add_type_part(d, current.mir, mir_type_part_field(), named.type_id, field_ordinal + ordinal, name, typ.id))
        ordinal = ordinal + 1
    }
    let memo = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: lower_closure_env_key(site.owner), value: named.type_id))
    return Ok(LowerStep(state: lower_with_values(current, memo), id: named.type_id))
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

fn lower_checked_unit(store: CheckStore, checked_type: U64) -> Bool {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    return checked.kind == 1 && checked.target == 12
}

fn lower_slice_u8(store: CheckStore, checked_type: U64) -> Bool {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind != 8 || checked.arg_count != 1 { return false }
    let element = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1) - 1)
    return element.kind == 1 && element.target == 6
}

fn lower_checked_abi_equal(store: CheckStore, left: U64, right: U64) -> Bool {
    if left == right { return true }
    let a = __s0_buffer_get(CheckedTypeRec, store.types, left - 1)
    let b = __s0_buffer_get(CheckedTypeRec, store.types, right - 1)
    return (a.kind == 16 && lower_slice_u8(store, right)) || (b.kind == 16 && lower_slice_u8(store, left))
}

fn lower_call_borrow_compatible(store: CheckStore, expected: U64, actual: U64) -> Bool {
    if lower_checked_abi_equal(store, expected, actual) { return true }
    let want = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
    let got = __s0_buffer_get(CheckedTypeRec, store.types, actual - 1)
    if want.kind != 8 || want.arg_count != 1 || (got.kind != 15 && got.kind != 17) || got.arg_count != 1 { return false }
    return lower_checked_abi_equal(store, __s0_buffer_get(U64, store.type_args, want.first_arg - 1), __s0_buffer_get(U64, store.type_args, got.first_arg - 1))
}

fn lower_has_storage(store: CheckStore) -> Bool {
    // Closure environments are domain-allocated records, so any closure with
    // captures forces the storage model on for the whole program.
    var site_at: U64 = 0
    while site_at < __s0_buffer_len(ClosureSiteRec, store.closures.sites) {
        if __s0_buffer_get(ClosureSiteRec, store.closures.sites, site_at).capture_count != 0 { return true }
        site_at = site_at + 1
    }
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let kind = __s0_buffer_get(CheckedTypeRec, store.types, at).kind
        if kind == 17 || kind == 23 || kind == 24 { return true }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if (use.role == 6 || use.role == 8) && __s0_buffer_get(CheckedTypeRec, store.types, use.checked_type - 1).kind == 8 { return true }
        at = at + 1
    }
    // A result type that reaches a slice through ordinary aggregate structure
    // also needs inferred storage: its views must be materialized into
    // caller-result storage before the function domain is destroyed. The
    // private __s0_String bridge keeps explicit storage management and stays
    // outside this gate. Depth exhaustion conservatively enables storage.
    at = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.role == 6 || use.role == 8 {
            if lower_type_reaches_storage(store, use.checked_type, 0, 0, 0) { return true }
        }
        at = at + 1
    }
    // A Table owner allocates its element storage in the function's hidden
    // domain, so any table type in the module enables the storage machinery
    // even with no vector or slice anywhere.
    at = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        if __s0_buffer_get(CheckedTypeRec, store.types, at).kind == 19 { return true }
        at = at + 1
    }
    // The M8 byte-sequence surface allocates its fresh String and Bytes
    // results in the function's hidden domain, so any concat, slice, or
    // from-bytes call enables the storage machinery for the module. Length,
    // byte reads, and to_bytes reinterprets never allocate and stay outside
    // this gate. The M8 Display builtin allocates the same way through
    // str.display, so it forces the model on too.
    at = 0
    while at < __s0_buffer_len(CallAnnotationRec, store.call_annotations) {
        let builtin = __s0_buffer_get(CallAnnotationRec, store.call_annotations, at).builtin
        if builtin == 58 || builtin == 59 || builtin == 61 || builtin == 1001 { return true }
        at = at + 1
    }
    return false
}

// True when a slice or vector is reachable from checked_type through ordinary
// aggregate structure. Fields are substituted through the concrete
// application, so generic records resolve their members without a separate
// environment. The bound on depth keeps a malformed cyclic store from
// hanging the lowerer; valid stores reject value recursion earlier.
fn lower_type_reaches_storage(store: CheckStore, checked_type: U64, declaration: U64, application: U64, depth: U64) -> Bool {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    if depth >= 64 { return true }
    // A bare type parameter appears only in generic declaration signatures,
    // which never lower; concrete instances carry their own result uses.
    if application == 0 && __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1).kind == 6 { return false }
    let bound = lower_bound_checked_type(store, checked_type, declaration, application)
    if bound == 0 { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, bound - 1)
    if checked.kind == 8 || checked.kind == 17 || checked.kind == 23 || checked.kind == 24 { return true }
    if checked.kind == 9 || checked.kind == 13 || checked.kind == 15 || checked.kind == 18 {
        if checked.arg_count != 1 { return false }
        return lower_type_reaches_storage(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), 0, 0, depth + 1)
    }
    if checked.kind == 10 || checked.kind == 11 {
        var child: U64 = 0
        while child < checked.arg_count {
            if lower_type_reaches_storage(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), 0, 0, depth + 1) { return true }
            child = child + 1
        }
        return false
    }
    if checked.kind == 7 {
        var at: U64 = 0
        while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
            if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
                if lower_type_reaches_storage(store, use.checked_type, checked.target, bound, depth + 1) { return true }
            }
            at = at + 1
        }
    }
    return false
}

// Build stable ordinary-source storage facts before MIR exists. Expression IDs
// are also allocation-site IDs: lowering consumes a placement only when that
// expression materializes Vec storage or a cross-domain result copy. This
// keeps one deterministic identity through checking, analysis, and lowering
// without duplicating the slice-1 fixed-point solver.
fn lower_storage_plan(d: Domain, store: CheckStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 1))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    var constraints = try __s0_buffer_new(StorageConstraintRec, d)
    var views = try __s0_buffer_new(StorageViewRec, d)
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 2))
        if expression.site_kind == 3 {
            var fallback = false
            if expression.kind == 8 && expression.annotation != 0 {
                fallback = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1).kind == 1
            }
            var required: U64 = 1
            if fallback { required = 0 }
            constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: at + 1, domain: required, dependency: 0, fallback: fallback, source: expression.site_syntax))
        }
        if expression.kind == 18 && expression.annotation != 0 {
            let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
            if annotation.builtin == 23 {
                var use_domain: U64 = 2
                if expression.site_kind == 3 { use_domain = 1 }
                views = try __s0_buffer_append(StorageViewRec, d, views, StorageViewRec(allocation: at + 1, parent_view: 0, use_domain: use_domain, invalidated: false, source: expression.syntax))
            }
        }
        at = at + 1
    }
    let plan = try storage_analyze(d, domains, allocations, constraints, views)
    if plan.issue_kind != 0 || __s0_buffer_len(U64, plan.placements) != __s0_buffer_len(CheckedExprRec, store.expressions) {
        return Ok(try __s0_buffer_new(U64, d))
    }
    return Ok(plan.placements)
}

fn lower_owner_aliases_domain(source_state: State, store: CheckStore, owner: U64) -> Bool {
    if owner == 0 || owner > __s0_buffer_len(SymbolRec, store.symbols) { return false }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    let source = __s0_buffer_get(SourceRec, source_state.sources, symbol.source)
    if !source_word(source_state, source, symbol.name_start, symbol.name_end, "main") { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(LocalRec, store.locals) {
        let local = __s0_buffer_get(LocalRec, store.locals, at)
        if local.owner == owner && local.kind == 1 {
            return __s0_buffer_get(CheckedTypeRec, store.types, local.checked_type - 1).kind == 3
        }
        at = at + 1
    }
    return false
}

fn lower_domain_key(store: CheckStore, owner: U64) -> U64 {
    return __s0_buffer_len(LocalRec, store.locals) + owner
}

fn lower_active_domain_key(store: CheckStore, owner: U64) -> U64 {
    return __s0_buffer_len(LocalRec, store.locals) + __s0_buffer_len(SymbolRec, store.symbols) + owner
}

fn lower_keyed_domain_value(state: LowerState, key: U64) -> U64 {
    var at = __s0_buffer_len(LowerValueMapRec, state.values)
    while at > 0 {
        let item = __s0_buffer_get(LowerValueMapRec, state.values, at - 1)
        if item.expression == key { return item.value }
        at = at - 1
    }
    return 0
}

fn lower_result_domain_value(state: LowerState, store: CheckStore, owner: U64) -> U64 {
    return lower_keyed_domain_value(state, lower_domain_key(store, owner))
}

fn lower_domain_value(state: LowerState, store: CheckStore, owner: U64) -> U64 {
    return lower_keyed_domain_value(state, lower_active_domain_key(store, owner))
}

// lower_release_function_named returns the module function whose name is the
// given byte range, or zero. Synthesized release functions are keyed by name
// so repeated using sites of one table type share one function.
fn lower_release_function_named(store: MirStore, name: __s0_String) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(MirFunctionRec, store.functions) {
        let item = __s0_buffer_get(MirFunctionRec, store.functions, at)
        if item.name_end - item.name_start == len(name) {
            var same = true
            var byte_at: U64 = 0
            while byte_at < len(name) {
                if __s0_buffer_get(U8, store.names, item.name_start + byte_at) != name[byte_at] { same = false }
                byte_at = byte_at + 1
            }
            if same { return at + 1 }
        }
        at = at + 1
    }
    return 0
}

// lower_cstring_release_function synthesizes (once) the using release for a
// c_string owner: fn __alder_cstring_release_N(cstring: c_string) -> Unit
// whose body consumes the owner through c.string.release, so the runtime
// free runs exactly once at the using scope boundary. Unlike the table
// release shell the body needs no deferred fill: the owner has no nested
// cleanup to resolve.
fn lower_cstring_release_function(d: Domain, source_state: State, store: CheckStore, state: LowerState, cstring_checked_type: U64) -> Result(LowerStep, __s0_Error) {
    let cstring_type = try lower_type(d, source_state, store, state, cstring_checked_type)
    if !cstring_type.state.valid { return Ok(cstring_type) }
    let name = try lower_decimal_name(d, "__alder_cstring_release_", cstring_type.id)
    let existing = lower_release_function_named(cstring_type.state.mir, name)
    if existing != 0 { return Ok(LowerStep(state: cstring_type.state, id: existing)) }
    let made = try mir_add_function(d, cstring_type.state.mir, name, mir_type_unit())
    let parameter = try mir_add_function_param(d, made.store, made.id, 0, "cstring", cstring_type.id)
    let entry = try mir_add_block(d, parameter.store, made.id, 0, "entry")
    let instr_state = lower_with_mir(cstring_type.state, entry.store)
    let released = try lower_add_instr(d, instr_state, made.id, entry.id, mir_op_c_string_release(), 0, 0, 0, parameter.id, 0, 0, "")
    let term = try mir_add_terminator(d, released.state.mir, MirTermRec(function: made.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(LowerStep(state: lower_with_mir(cstring_type.state, term.store), id: made.id))
}

// The retained callback owner's using release: fn
// __alder_callback_owner_release_N(owner: owner) -> Unit calls the recorded
// clear, then wait, then frees the context/owner allocation. A nonzero clear
// panics because freed context must never remain registered.
fn lower_callback_owner_release_function(d: Domain, source_state: State, store: CheckStore, state: LowerState, initializer: U64) -> Result(LowerStep, __s0_Error) {
    let site = lower_callback_owner_site(store, initializer)
    if site == 0 {
        // A moved owner registered with `using held = owner` reuses the
        // release helper already synthesized for its original registration.
        if initializer == 0 || initializer > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let reuse_expr = __s0_buffer_get(CheckedExprRec, store.expressions, initializer - 1)
        if reuse_expr.checked_type == 0 || reuse_expr.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        if __s0_buffer_get(CheckedTypeRec, store.types, reuse_expr.checked_type - 1).kind != 33 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let reuse_type = try lower_type(d, source_state, store, state, reuse_expr.checked_type)
        if !reuse_type.state.valid { return Ok(reuse_type) }
        let reuse_name = try lower_decimal_name(d, "__alder_callback_owner_release_", reuse_type.id)
        let existing = lower_release_function_named(reuse_type.state.mir, reuse_name)
        if existing == 0 { return Ok(LowerStep(state: lower_invalid(reuse_type.state), id: 0)) }
        return Ok(LowerStep(state: reuse_type.state, id: existing))
    }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, site - 1)
    if expression.annotation == 0 || expression.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
    if checked.kind != 9 || checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let owner_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let owner_type = try lower_type(d, source_state, store, state, owner_checked)
    if !owner_type.state.valid { return Ok(owner_type) }
    let name = try lower_decimal_name(d, "__alder_callback_owner_release_", owner_type.id)
    let existing = lower_release_function_named(owner_type.state.mir, name)
    if existing != 0 { return Ok(LowerStep(state: owner_type.state, id: existing)) }
    let made = try mir_add_function(d, owner_type.state.mir, name, mir_type_unit())
    let parameter = try mir_add_function_param(d, made.store, made.id, 0, "owner", owner_type.id)
    let entry = try mir_add_block(d, parameter.store, made.id, 0, "entry")
    let instr_state = lower_with_mir(owner_type.state, entry.store)
    let clear_id = lower_binding_fn_flat_index(store, annotation.target)
    let wait_id = lower_binding_fn_flat_index(store, annotation.variant_use)
    if clear_id == 0 || wait_id == 0 { return Ok(LowerStep(state: lower_invalid(owner_type.state), id: 0)) }
    // place carries the wait binding function for the release helper.
    let released = try lower_add_instr(d, instr_state, made.id, entry.id, mir_op_c_callback_owner_release(), 0, 0, owner_type.id, parameter.id, clear_id, 0, "")
    let released_rec = __s0_buffer_get(MirInstrRec, released.state.mir.instructions, released.id - 1)
    __s0_buffer_set(MirInstrRec, released.state.mir.instructions, released.id - 1, MirInstrRec(function: released_rec.function, block: released_rec.block, ordinal: released_rec.ordinal, op: released_rec.op, result: released_rec.result, place: 0, type_op: released_rec.type_op, a: released_rec.a, b: released_rec.b, c: wait_id, target: released_rec.target, name_start: released_rec.name_start, name_end: released_rec.name_end))
    let term = try mir_add_terminator(d, released.state.mir, MirTermRec(function: made.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(LowerStep(state: lower_with_mir(owner_type.state, term.store), id: made.id))
}

// lower_table_release_function synthesizes (once per table type per module)
// the builtin release callback used by a callback-free using registration:
// fn __alder_table_release_N(table: table(T)) -> Unit { return }. Releasing a
// table performs no runtime work beyond the exactly-once registration; the
// table's storage is owned by its domain and freed when the domain dies.
fn lower_table_release_function(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, expression_id: U64) -> Result(LowerStep, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let table_type = try lower_type(d, source_state, store, state, expression.checked_type)
    if !table_type.state.valid { return Ok(table_type) }
    let name = try lower_decimal_name(d, "__alder_table_release_", table_type.id)
    let existing = lower_release_function_named(table_type.state.mir, name)
    if existing != 0 { return Ok(LowerStep(state: table_type.state, id: existing)) }
    let made = try mir_add_function(d, table_type.state.mir, name, mir_type_unit())
    let parameter = try mir_add_function_param(d, made.store, made.id, 0, "table", table_type.id)
    let entry = try mir_add_block(d, parameter.store, made.id, 0, "entry")
    let term = try mir_add_terminator(d, entry.store, MirTermRec(function: made.id, block: entry.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(LowerStep(state: lower_with_mir(table_type.state, term.store), id: made.id))
}

// lower_vec_drain_function synthesizes (once per affine-element vector type
// per module) the callback-free using drain shell:
// fn __alder_vec_drain_N(domain, vector: vec(T)) -> Unit. Only the function
// and its parameters exist here; the body is filled after every source
// function lowers, when the element cleanup target is resolvable, mirroring
// the buffer and map helper bodies.
fn lower_vec_drain_function(d: Domain, source_state: State, store: CheckStore, state: LowerState, vec_checked_type: U64) -> Result(LowerStep, __s0_Error) {
    let vec_type = try lower_type(d, source_state, store, state, vec_checked_type)
    if !vec_type.state.valid { return Ok(vec_type) }
    let name = try lower_decimal_name(d, "__alder_vec_drain_", vec_type.id)
    let existing = lower_release_function_named(vec_type.state.mir, name)
    if existing != 0 { return Ok(LowerStep(state: vec_type.state, id: existing)) }
    let made = try mir_add_function(d, vec_type.state.mir, name, mir_type_unit())
    var current = lower_with_mir(vec_type.state, made.store)
    var ordinal: U64 = 0
    if current.has_storage {
        let domain_type = try lower_domain_mir_type(d, current)
        let domain_param = try mir_add_function_param(d, domain_type.state.mir, made.id, 0, "__domain", domain_type.id)
        current = lower_with_mir(domain_type.state, domain_param.store)
        ordinal = 1
    }
    let parameter = try mir_add_function_param(d, current.mir, made.id, ordinal, "vector", vec_type.id)
    return Ok(LowerStep(state: lower_with_mir(current, parameter.store), id: made.id))
}

// lower_vec_drain_body fills one drain: walk the captured vector front to
// back and hand every element to its cleanup, then return. A Table element
// drains through its synthesized release; a Cleanup element through its
// trait method. Later registrations of the same vector type find the body
// already filled. The vector storage itself follows the domain lifecycle,
// exactly like the builtin table release.
fn lower_vec_drain_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, cleanup: CheckedCleanupRec) -> Result(LowerState, __s0_Error) {
    if cleanup.initializer == 0 || cleanup.initializer > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(lower_invalid(state)) }
    let initializer = __s0_buffer_get(CheckedExprRec, store.expressions, cleanup.initializer - 1)
    let owner_type = __s0_buffer_get(CheckedTypeRec, store.types, initializer.checked_type - 1)
    if owner_type.kind != 17 || owner_type.arg_count != 1 { return Ok(state) }
    let vec_type = try lower_type(d, source_state, store, state, initializer.checked_type)
    if !vec_type.state.valid { return Ok(vec_type.state) }
    var current = vec_type.state
    let drain_name = try lower_decimal_name(d, "__alder_vec_drain_", vec_type.id)
    let function = lower_release_function_named(current.mir, drain_name)
    if function == 0 { return Ok(lower_invalid(current)) }
    var filled: U64 = 0
    var block_at: U64 = 0
    while block_at < __s0_buffer_len(MirBlockRec, current.mir.blocks) {
        if __s0_buffer_get(MirBlockRec, current.mir.blocks, block_at).function == function { filled = 1 }
        block_at = block_at + 1
    }
    if filled != 0 { return Ok(current) }
    let element_checked = __s0_buffer_get(U64, store.type_args, owner_type.first_arg - 1)
    let element_type = try lower_type(d, source_state, store, current, element_checked)
    if !element_type.state.valid { return Ok(element_type.state) }
    current = element_type.state
    if cleanup.drain == 0 || cleanup.drain > __s0_buffer_len(SymbolRec, store.symbols) { return Ok(lower_invalid(current)) }
    var element_fn: U64 = 0
    var element_domain: U64 = 0
    element_fn = lower_owner_lookup(current.owners, cleanup.drain)
    if element_fn == 0 { return Ok(lower_invalid(current)) }
    if current.has_storage && !lower_owner_aliases_domain(source_state, store, cleanup.drain) { element_domain = 1 }
    // The drain shell's own parameters: the hidden domain first when storage
    // exists, then the captured vector. The storage flag is read into a plain
    // integer before the loop: a short-circuit join inside a loop may not
    // carry a value loaded from function-local state across the backedge.
    var first_is_domain: U64 = 0
    if current.has_storage { first_is_domain = 1 }
    var domain_value: U64 = 0
    var vector_value: U64 = 0
    var param_at: U64 = 0
    while param_at < __s0_buffer_len(MirParamRec, current.mir.params) {
        let parameter = __s0_buffer_get(MirParamRec, current.mir.params, param_at)
        if parameter.function == function {
            if parameter.kind == mir_param_function() {
                if parameter.ordinal == 0 && first_is_domain == 1 && domain_value == 0 { domain_value = parameter.value } else {
                    if vector_value == 0 { vector_value = parameter.value }
                }
            }
        }
        param_at = param_at + 1
    }
    if vector_value == 0 { return Ok(lower_invalid(current)) }
    let entry = try mir_add_block(d, current.mir, function, 0, "bb_entry")
    let head = try mir_add_block(d, entry.store, function, 1, "bb_head")
    let body = try mir_add_block(d, head.store, function, 2, "bb_body")
    let done = try mir_add_block(d, body.store, function, 3, "bb_done")
    let fail = try mir_add_block(d, done.store, function, 4, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: function, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    current = lower_with_mir(current, fail_term.store)
    let index_param = try mir_add_block_param(d, current.mir, function, head.id, 0, "index", mir_type_u64())
    current = lower_with_mir(current, index_param.store)
    let zero_name = try lower_decimal_name(d, "vec_drain_const_", vec_type.id * 100)
    let zero_const = try mir_add_const(d, current.mir, zero_name, mir_type_u64(), mir_const_int(), 0, 0, 0, "")
    let zero_value = try lower_add_typed_result(d, lower_with_mir(current, zero_const.store), function, entry.id, mir_type_u64())
    let zero_instr = try lower_add_instr(d, zero_value.state, function, entry.id, mir_op_const_get(), zero_value.id, 0, 0, 0, 0, 0, zero_name)
    current = try lower_jump_value(d, zero_instr.state, function, entry.id, head.id, zero_value.id)
    let length_value = try lower_add_typed_result(d, current, function, head.id, mir_type_u64())
    let length_instr = try lower_add_instr(d, length_value.state, function, head.id, mir_op_vec_len(), length_value.id, 0, 0, vector_value, 0, 0, "")
    let keep_going = try lower_add_typed_result(d, length_instr.state, function, head.id, mir_type_bool())
    let compare = try lower_add_instr(d, keep_going.state, function, head.id, mir_op_int_lt(), keep_going.id, 0, 0, index_param.id, length_value.id, 0, "")
    current = try lower_branch(d, compare.state, function, head.id, keep_going.id, body.id, done.id)
    let empty = try __s0_buffer_new(U64, d)
    let slice_type = try mir_intern_type(d, current.mir, mir_type_kind_slice(), element_type.id, 0, 0, empty, 0)
    current = lower_with_mir(current, slice_type.store)
    let ref_type = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), element_type.id, 0, 0, empty, 0)
    current = lower_with_mir(current, ref_type.store)
    let slice_value = try lower_add_typed_result(d, current, function, body.id, slice_type.type_id)
    let slice_instr = try lower_add_instr(d, slice_value.state, function, body.id, mir_op_vec_as_slice(), slice_value.id, 0, 0, vector_value, 0, 0, "")
    let ref_value = try lower_add_typed_result(d, slice_instr.state, function, body.id, ref_type.type_id)
    let indexed = try lower_add_instr(d, ref_value.state, function, body.id, mir_op_slice_index_checked(), ref_value.id, 0, 0, slice_value.id, index_param.id, fail.id, "")
    let element_place = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: ref_value.id))
    current = lower_with_mir(indexed.state, element_place.store)
    let element_value = try lower_add_typed_result(d, current, function, body.id, element_type.id)
    let loaded = try lower_add_instr(d, element_value.state, function, body.id, mir_op_load(), element_value.id, element_place.id, 0, 0, 0, 0, "")
    let cleaned = try lower_add_instr(d, loaded.state, function, body.id, mir_op_call(), 0, 0, 0, 0, 0, element_fn, "")
    current = cleaned.state
    var argument_ordinal: U64 = 0
    if element_domain != 0 {
        current = try lower_add_instr_operand(d, current, cleaned.id, 0, domain_value, mir_operand_instruction(), "")
        argument_ordinal = 1
    }
    current = try lower_add_instr_operand(d, current, cleaned.id, argument_ordinal, element_value.id, mir_operand_instruction(), "")
    let one_name = try lower_decimal_name(d, "vec_drain_const_", vec_type.id * 100 + 1)
    let one_const = try mir_add_const(d, current.mir, one_name, mir_type_u64(), mir_const_int(), 0, 1, 0, "")
    let one_value = try lower_add_typed_result(d, lower_with_mir(current, one_const.store), function, body.id, mir_type_u64())
    let one_instr = try lower_add_instr(d, one_value.state, function, body.id, mir_op_const_get(), one_value.id, 0, 0, 0, 0, 0, one_name)
    let next_index = try lower_add_typed_result(d, one_instr.state, function, body.id, mir_type_u64())
    let added = try lower_add_instr(d, next_index.state, function, body.id, mir_op_int_add_checked(), next_index.id, 0, 0, index_param.id, one_value.id, fail.id, "")
    current = try lower_jump_value(d, added.state, function, body.id, head.id, next_index.id)
    let done_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: done.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(current, done_term.store))
}

fn lower_storage_domain_value(state: LowerState, store: CheckStore, owner: U64, expression: U64) -> U64 {
    if expression >= 1 && expression <= __s0_buffer_len(U64, state.storage) && __s0_buffer_get(U64, state.storage, expression - 1) == 1 {
        return lower_result_domain_value(state, store, owner)
    }
    return lower_domain_value(state, store, owner)
}

// The local owner map travels in `values` under a key space above every
// expression, domain, and closure key. An entry stores 0 for the frame domain,
// 1 for the caller-result domain, and a fixed owner-domain value plus two.
// Locals without an entry use the frame domain.
fn lower_local_owner_key(binding: U64) -> U64 { return binding + 4200000000 }

fn lower_local_owner_lookup(state: LowerState, binding: U64) -> U64 {
    if binding == 0 { return 0 }
    return lower_keyed_domain_value(state, lower_local_owner_key(binding))
}

fn lower_with_local_owner(d: Domain, state: LowerState, binding: U64, encoded: U64) -> Result(LowerState, __s0_Error) {
    let owners = try __s0_buffer_append(LowerValueMapRec, d, state.values, LowerValueMapRec(expression: lower_local_owner_key(binding), value: encoded))
    return Ok(lower_with_values(state, owners))
}

fn lower_binding_owner_domain(state: LowerState, store: CheckStore, owner: U64, binding: U64) -> U64 {
    let encoded = lower_local_owner_lookup(state, binding)
    if encoded == 0 { return lower_domain_value(state, store, owner) }
    if encoded == 1 { return lower_result_domain_value(state, store, owner) }
    return encoded - 2
}

fn lower_place_owner_domain(state: LowerState, store: CheckStore, owner: U64, place: U64) -> U64 {
    if place == 0 || place > __s0_buffer_len(CheckedPlaceRec, store.control.places) { return 0 }
    let checked = __s0_buffer_get(CheckedPlaceRec, store.control.places, place - 1)
    return lower_binding_owner_domain(state, store, owner, checked.root)
}

// The explicit owner of a borrowed place, or zero when the place is rooted in
// an ordinary local or `take` parameter that already owns its frame storage.
fn lower_borrowed_place_owner_domain(state: LowerState, store: CheckStore, place: U64) -> U64 {
    if place == 0 || place > __s0_buffer_len(CheckedPlaceRec, store.control.places) { return 0 }
    let checked = __s0_buffer_get(CheckedPlaceRec, store.control.places, place - 1)
    let encoded = lower_local_owner_lookup(state, checked.root)
    if encoded >= 2 { return encoded - 2 }
    return 0
}

// The checked root binding of a name, field, or index expression, or zero
// when the expression does not read a place.
fn lower_checked_expression_root(store: CheckStore, expression: U64) -> U64 {
    var current = expression
    var depth: U64 = 0
    while depth < 32 && current != 0 && current <= __s0_buffer_len(CheckedExprRec, store.expressions) {
        let item = __s0_buffer_get(CheckedExprRec, store.expressions, current - 1)
        if item.kind == 1 || item.kind == 5 { return item.parameter_use }
        if item.kind == 21 && item.child_count == 1 { current = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
        } else { if item.kind == 19 && item.child_count == 2 { current = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
        } else { return 0 } }
        depth = depth + 1
    }
    return 0
}

// A binding spelling byte range to a string: explicit "..." spellings live
// in state.values (source zero), name spellings in a source file.
fn lower_binding_word(d: Domain, source_state: State, from_values: Bool, source: U64, start: U64, end: U64) -> Result(__s0_String, __s0_Error) {
    if from_values { return lower_word(d, source_state.values, start, end) }
    return lower_source_word(d, source_state, source, start, end)
}

// One binding type entry to its MIR shape. Records come from the binding
// store's member and field records, so lowering stays parse-store free.
// The Unit result marker lowers to the MIR unit type; every other shape
// mirrors the checked-side interning so equal shapes share one MIR type.
fn lower_binding_type(d: Domain, source_state: State, store: CheckStore, state: LowerState, binding_index: U64) -> Result(LowerStep, __s0_Error) {
    if binding_index == 0 || binding_index > __s0_buffer_len(BindingTypeRec, store.bindings.types) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let rec = __s0_buffer_get(BindingTypeRec, store.bindings.types, binding_index - 1)
    if rec.kind == 30 { return Ok(LowerStep(state: state, id: mir_type_unit())) }
    if rec.kind == 26 {
        let built = try mir_intern_c_raw(d, state.mir, rec.target)
        return Ok(LowerStep(state: lower_with_mir(state, built.store), id: built.type_id))
    }
    if rec.kind == 27 || rec.kind == 28 {
        let elem = try lower_binding_type(d, source_state, store, state, rec.first_arg)
        if !elem.state.valid { return Ok(elem) }
        if rec.kind == 27 {
            let built = try mir_intern_c_ptr(d, elem.state.mir, elem.id)
            return Ok(LowerStep(state: lower_with_mir(elem.state, built.store), id: built.type_id))
        }
        let built = try mir_intern_c_const_ptr(d, elem.state.mir, elem.id)
        return Ok(LowerStep(state: lower_with_mir(elem.state, built.store), id: built.type_id))
    }
    if rec.kind == 29 { return lower_binding_type_member(d, source_state, store, state, rec.target) }
    return Ok(LowerStep(state: lower_invalid(state), id: 0))
}

// The binding store member (1-based) of a named binding type node, or zero.
fn lower_binding_member_for_node(store: CheckStore, member_node: U64) -> U64 {
    var member_at: U64 = 0
    while member_at < __s0_buffer_len(BindingMemberRec, store.bindings.members) {
        let item = __s0_buffer_get(BindingMemberRec, store.bindings.members, member_at)
        if item.member_kind == 1 && item.member_node == member_node { return member_at + 1 }
        member_at = member_at + 1
    }
    return 0
}

// The MIR type id claimed for a named binding type member by its
// binding_type operand, or zero before that claim exists. The member's
// block and per-block type ordinal select the operand. References reuse
// the claimed type instead of adding a second c_named, because every
// c_named type must stay claimed by exactly one operand.
fn lower_binding_claimed_type(store: CheckStore, mir: MirStore, member_index: U64) -> U64 {
    if member_index == 0 || member_index > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return 0 }
    let member = __s0_buffer_get(BindingMemberRec, store.bindings.members, member_index - 1)
    var block_at: U64 = 0
    var block_id: U64 = 0
    while block_at < __s0_buffer_len(BindingBlockRec, store.bindings.blocks) {
        let block = __s0_buffer_get(BindingBlockRec, store.bindings.blocks, block_at)
        if block.node == member.block_node { block_id = block_at + 1 }
        block_at = block_at + 1
    }
    if block_id == 0 { return 0 }
    var at: U64 = 0
    var ordinal: U64 = 0
    while at + 1 < member_index {
        let item = __s0_buffer_get(BindingMemberRec, store.bindings.members, at)
        if item.block_node == member.block_node && item.member_kind == 1 { ordinal = ordinal + 1 }
        at = at + 1
    }
    var scan: U64 = 0
    while scan < __s0_buffer_len(MirOperandRec, mir.operands) {
        let o = __s0_buffer_get(MirOperandRec, mir.operands, scan)
        if o.kind == mir_operand_binding_type() && o.owner == block_id && o.ordinal == ordinal { return o.operand_type }
        scan = scan + 1
    }
    return 0
}

// One reference to a named binding type member: the MIR type its claim
// operand already created. A zero claim is an internal failure, because
// the claim pass runs before any reference can lower.
fn lower_binding_type_member(d: Domain, source_state: State, store: CheckStore, state: LowerState, member_node: U64) -> Result(LowerStep, __s0_Error) {
    let found = lower_binding_member_for_node(store, member_node)
    if found == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let type_id = lower_binding_claimed_type(store, state.mir, found)
    if type_id == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    return Ok(LowerStep(state: state, id: type_id))
}

// One named C binding type member to its fresh MIR c_named shape, without
// record fields. Claims run in a pass before fields, raw fns, constants,
// and function signatures, so every reference resolves to this type
// through its claim operand instead of adding a second unclaimed type.
fn lower_binding_named(d: Domain, source_state: State, store: CheckStore, state: LowerState, member_node: U64) -> Result(LowerStep, __s0_Error) {
    let found = lower_binding_member_for_node(store, member_node)
    if found == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let member = __s0_buffer_get(BindingMemberRec, store.bindings.members, found - 1)
    let name = try lower_source_word(d, source_state, member.name_source, member.name_start, member.name_end)
    let c_name = try lower_binding_word(d, source_state, member.spelling_values, member.spelling_source, member.spelling_start, member.spelling_end)
    let built = try mir_add_c_named_type(d, state.mir, name, c_name, member.class)
    return Ok(LowerStep(state: lower_with_mir(state, built.store), id: built.type_id))
}

// Record fields of one claimed c_named type member. The type was created
// and claimed in the claim pass, so field types lower against the same
// table and every nested c_named reference resolves to its claim.
fn lower_binding_fields(d: Domain, source_state: State, store: CheckStore, state: LowerState, member_index: U64, type_id: U64) -> Result(LowerState, __s0_Error) {
    var current = state
    var field_at: U64 = 0
    var ordinal: U64 = 0
    while field_at < __s0_buffer_len(BindingFieldRec, store.bindings.fields) {
        let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, field_at)
        if field.owner == member_index {
            let field_name = try lower_source_word(d, source_state, field.name_source, field.name_start, field.name_end)
            let field_c_name = try lower_binding_word(d, source_state, field.spelling_values, field.spelling_source, field.spelling_start, field.spelling_end)
            let field_type = try lower_binding_type(d, source_state, store, current, field.type_index)
            if !field_type.state.valid { return Ok(field_type.state) }
            current = lower_with_mir(field_type.state, try mir_add_c_field_part(d, field_type.state.mir, type_id, ordinal, field_name, field_c_name, field_type.id))
            ordinal = ordinal + 1
        }
        field_at = field_at + 1
    }
    return Ok(current)
}

// lower_c_string_type interns the singleton c_string MIR type for the
// checked c_string owner. One owner per module keeps the release function
// and the option payload identity unique.
fn lower_c_string_type(d: Domain, state: LowerState, checked_type: U64) -> Result(LowerStep, __s0_Error) {
    let built = try mir_intern_c_string(d, state.mir)
    let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
    return Ok(LowerStep(state: lower_with_types(lower_with_mir(state, built.store), mapped), id: built.type_id))
}

// One callback-owner checked type interns a unique MIR owner type: the
// context type is stored in elem and the callback function-pointer type in
// result_type. Every registration site has its own checked owner type, so a
// release helper's clear/wait imports cannot be shared accidentally.
fn lower_callback_owner_type(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64) -> Result(LowerStep, __s0_Error) {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind != 33 || checked.arg_count != 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let context_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let handler_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg)
    let context = try lower_type(d, source_state, store, state, context_checked)
    if !context.state.valid { return Ok(context) }
    let handler = try lower_type(d, source_state, store, context.state, handler_checked)
    if !handler.state.valid { return Ok(handler) }
    let empty = try __s0_buffer_new(U64, d)
    let built = try mir_intern_type(d, handler.state.mir, mir_type_kind_c_callback_owner(), context.id, 0, 0, empty, handler.id)
    let mapped = try __s0_buffer_append(LowerTypeMapRec, d, handler.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
    return Ok(LowerStep(state: lower_with_types(lower_with_mir(handler.state, built.store), mapped), id: built.type_id))
}

// The registration expression inside a using initializer: `try` wraps the
// c.CallbackOwner.register expression, and the cleanup pre-pass needs its
// annotation metadata.
fn lower_callback_owner_site(store: CheckStore, initializer: U64) -> U64 {
    var current = initializer
    var depth: U64 = 0
    while depth < 8 && current != 0 && current <= __s0_buffer_len(CheckedExprRec, store.expressions) {
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, current - 1)
        if expression.kind == 39 { return current }
        if expression.kind == 13 && expression.child_count == 1 && expression.first_child != 0 {
            // try's payload expression
            current = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        } else { if expression.kind == 12 && expression.parameter_use != 0 && expression.parameter_use <= __s0_buffer_len(CheckedMatchRec, store.control.matches) {
            // The match scrutinee carries the registration.
            current = __s0_buffer_get(CheckedMatchRec, store.control.matches, expression.parameter_use - 1).scrutinee
        } else { if (expression.kind == 1 || expression.kind == 5 || expression.kind == 22) && expression.parameter_use != 0 {
            // A local read whose let initializer is the registration.
            var found: U64 = 0
            var at: U64 = 0
            while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
                if (statement.kind == 1 || statement.kind == 2) && statement.binding == expression.parameter_use { found = statement.expression }
                at = at + 1
            }
            if found == 0 { return 0 }
            current = found
        } else { return 0 } } }
        depth = depth + 1
    }
    return 0
}

// M8 c.CallbackOwner lowering. The context is copied into heap-owned storage;
// set receives the trampoline and the stable context address. The result is
// Option(owner), none when allocation or set fails. Clear/wait are recorded
// for the synthesized release helper.
fn lower_callback_owner_register(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 || expression.checked_type == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if expression.annotation == 0 || expression.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
    if checked.kind != 9 || checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let owner_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let owner_type = try lower_type(d, source_state, store, state, owner_checked)
    if !owner_type.state.valid { return Ok(owner_type) }
    let option_type = try lower_type(d, source_state, store, owner_type.state, expression.checked_type)
    if !option_type.state.valid { return Ok(option_type) }
    let context_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let context = try lower_expression(d, source_state, spans, store, option_type.state, owner, function, block, context_id, environment, panic_block)
    if !context.state.valid { return Ok(context) }
    let target = lower_owner_lookup(context.state.owners, expression.parameter_use)
    if target == 0 { return Ok(LowerStep(state: lower_invalid(context.state), id: 0)) }
    let set_id = lower_binding_fn_flat_index(store, annotation.owner)
    let clear_id = lower_binding_fn_flat_index(store, annotation.target)
    let wait_id = lower_binding_fn_flat_index(store, annotation.variant_use)
    if set_id == 0 || clear_id == 0 || wait_id == 0 { return Ok(LowerStep(state: lower_invalid(context.state), id: 0)) }
    let result = try lower_add_result(d, context.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_c_callback_owner_register(), result.id, wait_id, owner_type.id, context.id, set_id, target, "")
    let made = __s0_buffer_get(MirInstrRec, instr.state.mir.instructions, instr.id - 1)
    __s0_buffer_set(MirInstrRec, instr.state.mir.instructions, instr.id - 1, MirInstrRec(function: made.function, block: made.block, ordinal: made.ordinal, op: made.op, result: made.result, place: made.place, type_op: made.type_op, a: made.a, b: made.b, c: clear_id, target: made.target, name_start: made.name_start, name_end: made.name_end))
    return Ok(LowerStep(state: instr.state, id: result.id))
}

// M8 c.CString lowering. make_lit consumes the literal's String value
// (child 0) and produces the bare owner, taking the checked edge only when
// the runtime copy cannot allocate; make produces option(c_string) where an
// interior NUL yields none and only allocation failure takes the checked
// edge; ptr borrows the owner as c.ConstPtr(c.Char) with no runtime work,
// so reads compose freely while the single release stays at the using
// scope boundary.
fn lower_c_string_make_lit(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let arg_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let arg = try lower_expression(d, source_state, spans, store, state, owner, function, block, arg_syntax, environment, panic_block)
    let result = try lower_add_result(d, arg.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_c_string_make_lit(), result.id, 0, 0, arg.id, 0, panic_block, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

fn lower_c_string_make(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let arg_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let arg = try lower_expression(d, source_state, spans, store, state, owner, function, block, arg_syntax, environment, panic_block)
    let result = try lower_add_result(d, arg.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_c_string_make(), result.id, 0, 0, arg.id, 0, panic_block, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

fn lower_c_string_ptr(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    let result = try lower_add_result(d, receiver.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_c_string_ptr(), result.id, 0, 0, receiver.id, 0, 0, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

// lower_option_take lowers the Option.take builtin as a place load (which
// moves the current payload out), a none construction of the same option
// type, and a plain store back into the receiver place. It allocates nothing
// and carries no owner-domain operand; the caller-owned cleanup registration
// observes the stored None at scope exit, while the loaded payload is the
// expression value.
fn lower_option_take(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || annotation.place == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_id, environment, panic_block)
    let place = try lower_receiver_place(d, source_state, spans, store, receiver.state, owner, function, block, annotation.place, environment, panic_block)
    if place.id == 0 { return Ok(LowerStep(state: lower_invalid(place.state), id: 0)) }
    let option_type = try lower_type(d, source_state, store, place.state, expression.checked_type)
    if option_type.id == 0 { return Ok(LowerStep(state: lower_invalid(option_type.state), id: 0)) }
    let loaded = try lower_add_typed_result(d, option_type.state, function, block, option_type.id)
    let load = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, place.id, 0, 0, 0, 0, "")
    let none = try lower_add_typed_result(d, load.state, function, block, option_type.id)
    let constructed = try lower_add_instr(d, none.state, function, block, mir_op_enum_construct(), none.id, 0, option_type.id, 0, 0, 0, "none")
    let stored = try lower_add_instr(d, constructed.state, function, block, mir_op_store(), 0, place.id, 0, none.id, 0, 0, "")
    return Ok(LowerStep(state: stored.state, id: loaded.id))
}

// lower_try_option lowers `try option_value` in a function returning
// Option(S): the some payload becomes the expression value and the none arm
// early-returns a freshly constructed None through the owner's result
// storage, running every active cleanup registration first. The CheckedTryRec
// error_type is zero for this shape, so the wrapped result type comes from
// the owner's declared return rather than the try record.
fn lower_try_option(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, environment: U64, panic_block: U64, expression_id: U64, checked: CheckedTryRec) -> Result(LowerStep, __s0_Error) {
    let value = try lower_expression(d, source_state, spans, store, state, owner, function, block, checked.expression, environment, panic_block)
    let source_block = lower_open_block(value.state.mir, function, block)
    let ok_block = try lower_add_block(d, value.state, function, "bb_try_ok")
    let err_block = try lower_add_block(d, ok_block.state, function, "bb_try_err")
    let ok_type = try lower_type(d, source_state, store, err_block.state, checked.ok_type)
    // A unit payload has no value to bind: a switch case binding of unit type
    // is invalid in MIR, so the some case carries no payload value and the
    // try expression itself is the unit value 0.
    let unit_ok = lower_checked_unit(store, checked.ok_type)
    var ok_id: U64 = 0
    var ok_mir = ok_type.state.mir
    if !unit_ok {
        let ok_value = try mir_add_value(d, ok_mir, function, try lower_decimal_name(d, "try_ok", expression_id), ok_type.id, mir_value_def_switch_case(), source_block, 1)
        ok_id = ok_value.id
        ok_mir = ok_value.store
    }
    let term = try mir_add_terminator(d, ok_mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: value.id, target: 0, then_block: 0, else_block: 0))
    var current = lower_with_mir(ok_type.state, term.store)
    let ok_case = try lower_add_switch_case(d, current, term.id, 0, "some", ok_id, ok_block.id)
    let none_case = try lower_add_switch_case(d, ok_case.state, term.id, 1, "none", 0, err_block.id)
    current = none_case.state
    let result_use = lower_use_by_role(store, owner, 8, 0)
    var actual_result_use = result_use
    let owner_symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if owner_symbol.kind == 12 { actual_result_use = lower_use_by_role(store, owner, 6, 0) }
    if actual_result_use == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    let owner_result = __s0_buffer_get(DeclTypeUseRec, store.uses, actual_result_use - 1)
    let fn_type = try lower_type(d, source_state, store, current, owner_result.checked_type)
    let wrapped = try lower_add_result(d, fn_type.state, function, err_block.id, owner_result.checked_type, source_state, store)
    let constructed = try lower_add_instr(d, wrapped.state, function, err_block.id, mir_op_enum_construct(), wrapped.id, 0, fn_type.id, 0, 0, 0, "none")
    let retained = try lower_retain_exit_value(d, source_state, store, constructed.state, owner, function, err_block.id, owner_result.checked_type, wrapped.id)
    current = try lower_cleanup_exits(d, source_state, store, retained.state, owner, function, err_block.id, environment, 0, 3)
    let failed = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: err_block.id, kind: mir_term_fail(), value: retained.id, target: 0, then_block: 0, else_block: 0))
    return Ok(LowerStep(state: lower_with_mir(current, failed.store), id: ok_id))
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
    if checked.kind == 2 || checked.kind == 14 || checked.kind == 16 {
        let empty = try __s0_buffer_new(U64, d)
        if checked.kind == 16 {
            let built = try mir_intern_type(d, state.mir, mir_type_kind_slice(), mir_type_u8(), 0, 0, empty, 0)
            let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
            return Ok(LowerStep(state: lower_with_types(lower_with_mir(state, built.store), mapped), id: built.type_id))
        }
        var kind = mir_type_kind_string()
        if checked.kind == 14 { kind = mir_type_kind_bytes() }
        let built = try mir_intern_type(d, state.mir, kind, 0, 0, 0, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 31 { return lower_c_string_type(d, state, checked_type) }
    if checked.kind == 33 { return lower_callback_owner_type(d, source_state, store, state, checked_type) }
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
        if symbol.module_source != 0 || checked.arg_count != 0 { name = try lower_decimal_name(d, base, checked_type) }
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
    if checked.kind == 8 || checked.kind == 9 || checked.kind == 12 || checked.kind == 17 || checked.kind == 18 || checked.kind == 24 {
        if checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let elem = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        if !elem.state.valid { return Ok(elem) }
        var kind = mir_type_kind_slice()
        if checked.kind == 9 { kind = mir_type_kind_option() }
        if checked.kind == 12 { kind = mir_type_kind_raw_ptr() }
        if checked.kind == 17 || checked.kind == 24 { kind = mir_type_kind_vec() }
        let empty = try __s0_buffer_new(U64, d)
        let built = try mir_intern_type(d, elem.state.mir, kind, elem.id, 0, 0, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, elem.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(elem.state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 26 {
        let built = try mir_intern_c_raw(d, state.mir, checked.target)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 27 || checked.kind == 28 {
        if checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let elem = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        if !elem.state.valid { return Ok(elem) }
        if checked.kind == 27 {
            let built = try mir_intern_c_ptr(d, elem.state.mir, elem.id)
            let mapped = try __s0_buffer_append(LowerTypeMapRec, d, elem.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
            return Ok(LowerStep(state: lower_with_types(lower_with_mir(elem.state, built.store), mapped), id: built.type_id))
        }
        let built = try mir_intern_c_const_ptr(d, elem.state.mir, elem.id)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, elem.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(elem.state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 29 {
        let named = try lower_binding_type_member(d, source_state, store, state, checked.target)
        if !named.state.valid { return Ok(named) }
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, named.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: named.id))
        return Ok(LowerStep(state: lower_with_types(named.state, mapped), id: named.id))
    }
    if checked.kind == 19 || checked.kind == 20 || checked.kind == 21 || checked.kind == 22 {
        // M7.5 identity types: Table owners, T.Id handles, and the scoped
        // get/get_mut view payloads of table lookups.
        if checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let elem = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        if !elem.state.valid { return Ok(elem) }
        var kind = mir_type_kind_table()
        if checked.kind == 20 { kind = mir_type_kind_id() }
        if checked.kind == 21 { kind = mir_type_kind_table_view() }
        if checked.kind == 22 { kind = mir_type_kind_table_mut_view() }
        let empty = try __s0_buffer_new(U64, d)
        let built = try mir_intern_type(d, elem.state.mir, kind, elem.id, 0, 0, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, elem.state.types, LowerTypeMapRec(checked_type: checked_type, mir_type: built.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(elem.state, built.store), mapped), id: built.type_id))
    }
    if checked.kind == 15 {
        if checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let elem = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        if !elem.state.valid { return Ok(elem) }
        let built = try mir_intern_array(d, elem.state.mir, elem.id, checked.target)
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
    if checked.kind == 25 {
        if checked.arg_count < 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let param_total = checked.arg_count - 2
        var next = state
        var params_only = try __s0_buffer_new(U64, d)
        var domain_type: U64 = 0
        var mut_bit: U64 = 1
        var ordinal: U64 = 0
        while ordinal < param_total {
            let part = try lower_type(d, source_state, store, next, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal))
            if !part.state.valid { return Ok(part) }
            next = part.state
            if (checked.target / mut_bit) % 2 == 1 {
                // A borrowed function-type parameter carries its owner domain
                // immediately after the safe_mut parameter, exactly like a
                // function definition and a direct call.
                let empty = try __s0_buffer_new(U64, d)
                let reference = try mir_intern_type(d, next.mir, mir_type_kind_safe_mut(), part.id, 0, 0, empty, 0)
                next = lower_with_mir(next, reference.store)
                params_only = try __s0_buffer_append(U64, d, params_only, reference.type_id)
                if next.has_storage {
                    if domain_type == 0 {
                        let domain = try lower_domain_mir_type(d, next)
                        if !domain.state.valid { return Ok(domain) }
                        next = domain.state
                        domain_type = domain.id
                    }
                    params_only = try __s0_buffer_append(U64, d, params_only, domain_type)
                }
            } else {
                params_only = try __s0_buffer_append(U64, d, params_only, part.id)
            }
            mut_bit = mut_bit * 2
            ordinal = ordinal + 1
        }
        let result = try lower_type(d, source_state, store, next, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + param_total))
        if !result.state.valid { return Ok(result) }
        next = result.state
        let result_type = result.id
        let env_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + param_total + 1)
        let env_rec = __s0_buffer_get(CheckedTypeRec, store.types, env_checked - 1)
        var env_type: U64 = 0
        if !(env_rec.kind == 1 && env_rec.target == 12) {
            let env_part = try lower_type(d, source_state, store, next, env_checked)
            if !env_part.state.valid { return Ok(env_part) }
            next = env_part.state
            env_type = env_part.id
        }
        let interned = try mir_intern_function_type(d, next.mir, params_only, result_type, env_type)
        next = lower_with_mir(next, interned.store)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, next.types, LowerTypeMapRec(checked_type: checked_type, mir_type: interned.type_id))
        return Ok(LowerStep(state: lower_with_types(next, mapped), id: interned.type_id))
    }
    if checked.kind == 23 {
        if checked.arg_count != 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let key = try lower_type(d, source_state, store, state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
        if !key.state.valid { return Ok(key) }
        let value = try lower_type(d, source_state, store, key.state, __s0_buffer_get(U64, store.type_args, checked.first_arg))
        if !value.state.valid { return Ok(value) }
        // The public Map is an insertion-ordered association list over a
        // vector of {key, value} entries; no wrapper record is needed.
        let entry = try mir_add_named_type(d, value.state.mir, mir_type_kind_aggregate(), try lower_decimal_name(d, "OrderedMapEntry_", checked_type))
        var next = lower_with_mir(value.state, entry.store)
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), entry.type_id, 0, "key", key.id))
        next = lower_with_mir(next, try mir_add_type_part(d, next.mir, mir_type_part_field(), entry.type_id, 1, "value", value.id))
        let empty = try __s0_buffer_new(U64, d)
        let vec_type = try mir_intern_type(d, next.mir, mir_type_kind_vec(), entry.type_id, 0, 0, empty, 0)
        let mapped = try __s0_buffer_append(LowerTypeMapRec, d, next.types, LowerTypeMapRec(checked_type: checked_type, mir_type: vec_type.type_id))
        return Ok(LowerStep(state: lower_with_types(lower_with_mir(next, vec_type.store), mapped), id: vec_type.type_id))
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

// Resolve a declared member type through the concrete application,
// substituting type-parameter references at any depth. The substituted
// shape must already exist as a canonical checked type: constructing the
// aggregate required a value of that shape, so the checker interned it. Zero
// marks an unresolvable reference and refuses the model.
fn lower_bound_checked_deep(store: CheckStore, checked_type: U64, declaration: U64, application: U64, depth: U64) -> U64 {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return 0 }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 6 {
        if application == 0 || application > __s0_buffer_len(CheckedTypeRec, store.types) { return 0 }
        let applied = __s0_buffer_get(CheckedTypeRec, store.types, application - 1)
        var ordinal: U64 = 0
        var at: U64 = 0
        while at < __s0_buffer_len(TypeParamRec, store.type_params) {
            let param = __s0_buffer_get(TypeParamRec, store.type_params, at)
            if param.owner == declaration {
                if at + 1 == checked.target {
                    if ordinal >= applied.arg_count { return 0 }
                    return __s0_buffer_get(U64, store.type_args, applied.first_arg - 1 + ordinal)
                }
                ordinal = ordinal + 1
            }
            at = at + 1
        }
        return 0
    }
    if checked.arg_count == 0 || depth >= 64 { return checked_type }
    var first = checked.first_arg
    var child: U64 = 0
    var same = true
    while child < checked.arg_count {
        let resolved = lower_bound_checked_deep(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), declaration, application, depth + 1)
        if resolved == 0 { return 0 }
        if resolved != __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child) {
            same = false
            if child == 0 { first = __s0_buffer_len(U64, store.type_args) + 1 }
        }
        child = child + 1
    }
    if same { return checked_type }
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let candidate = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if candidate.kind == checked.kind && candidate.target == checked.target && candidate.arg_count == checked.arg_count {
            var matched = true
            child = 0
            while child < checked.arg_count {
                let resolved = lower_bound_checked_deep(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), declaration, application, depth + 1)
                if resolved != __s0_buffer_get(U64, store.type_args, candidate.first_arg - 1 + child) { matched = false }
                child = child + 1
            }
            if matched { return at + 1 }
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
                        let substituted = lower_bound_checked_deep(store, use.checked_type, checked.target, checked_id, 0)
                        if substituted == 0 { return Ok(lower_invalid(current)) }
                        let lowered = try lower_type(d, source_state, store, current, substituted)
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
    if checker_use_index_available(store, owner, role) {
        let index = __s0_buffer_get(CheckerUseIndexRec, store.indexes.uses, checker_use_slot(owner, role))
        if ordinal >= index.count { return 0 }
        return __s0_buffer_get(U64, store.indexes.use_order, index.first - 1 + ordinal)
    }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role && use.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn lower_use_count(store: CheckStore, owner: U64, role: U64) -> U64 {
    if checker_use_index_available(store, owner, role) {
        return __s0_buffer_get(CheckerUseIndexRec, store.indexes.uses, checker_use_slot(owner, role)).count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role { count = count + 1 }
        at = at + 1
    }
    return count
}

fn lower_add_helper_function(d: Domain, state: LowerState, name: __s0_String, result_type: U64, first_type: U64, second_type: U64, third_type: U64) -> Result(LowerStep, __s0_Error) {
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
                var result_id = annotation.checked_type
                if expression.checked_type != 0 { result_id = expression.checked_type }
                if result_id != 0 && result_id <= __s0_buffer_len(CheckedTypeRec, store.types) {
                    let result = __s0_buffer_get(CheckedTypeRec, store.types, result_id - 1)
                    if result.kind == 10 && result.arg_count == 2 { candidate = __s0_buffer_get(U64, store.type_args, result.first_arg - 1) }
                }
            }
            if annotation.builtin == 10 || annotation.builtin == 12 || annotation.builtin == 13 || annotation.builtin == 14 || annotation.builtin == 15 || annotation.builtin == 16 || annotation.builtin == 17 { candidate = lower_builtin_child_type(store, expression, 0) }
            if annotation.builtin == 11 { candidate = lower_builtin_child_type(store, expression, 1) }
            if candidate == checked_type { return true }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTryRec, store.control.tries) {
        if __s0_buffer_get(CheckedTryRec, store.control.tries, at).ok_type == checked_type { return true }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchRec, store.control.matches) {
        let checked = __s0_buffer_get(CheckedMatchRec, store.control.matches, at)
        if checked.scrutinee_type != 0 && checked.scrutinee_type <= __s0_buffer_len(CheckedTypeRec, store.types) {
            let scrutinee = __s0_buffer_get(CheckedTypeRec, store.types, checked.scrutinee_type - 1)
            if scrutinee.kind == 10 && scrutinee.arg_count == 2 && __s0_buffer_get(U64, store.type_args, scrutinee.first_arg - 1) == checked_type { return true }
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
                var result_type_id: U64 = 0
                let result_checked = lower_result_type_for(store, checked_id, error_checked)
                if result_checked != 0 {
                    let result_type = try lower_type(d, source_state, store, current, result_checked)
                    current = result_type.state
                    result_type_id = result_type.id
                } else {
                    let empty_result_args = try __s0_buffer_new(U64, d)
                    let result_type = try mir_intern_type(d, current.mir, mir_type_kind_result(), 0, lowered.id, error_type.id, empty_result_args, 0)
                    current = lower_with_mir(current, result_type.store)
                    result_type_id = result_type.type_id
                }
                var slice_type_id: U64 = 0
                let slice_checked = lower_slice_type_for(store, element_checked)
                if slice_checked != 0 {
                    let slice_type = try lower_type(d, source_state, store, current, slice_checked)
                    current = slice_type.state
                    slice_type_id = slice_type.id
                } else {
                    let empty_slice_args = try __s0_buffer_new(U64, d)
                    let slice_type = try mir_intern_type(d, current.mir, mir_type_kind_slice(), element.id, 0, 0, empty_slice_args, 0)
                    current = lower_with_mir(current, slice_type.store)
                    slice_type_id = slice_type.type_id
                }
                let domain_type = try lower_domain_mir_type(d, current)
                current = domain_type.state
                let suffix = try lower_decimal_name(d, "buffer_new_", checked_id)
                let make = try lower_add_helper_function(d, current, suffix, result_type_id, domain_type.id, 0, 0)
                let length = try lower_add_helper_function(d, make.state, try lower_decimal_name(d, "buffer_len_", checked_id), mir_type_u64(), lowered.id, 0, 0)
                let append = try lower_add_helper_function(d, length.state, try lower_decimal_name(d, "buffer_append_", checked_id), result_type_id, domain_type.id, lowered.id, element.id)
                let get = try lower_add_helper_function(d, append.state, try lower_decimal_name(d, "buffer_get_", checked_id), element.id, lowered.id, mir_type_u64(), 0)
                let set = try lower_add_helper_function(d, get.state, try lower_decimal_name(d, "buffer_set_", checked_id), mir_type_unit(), lowered.id, mir_type_u64(), element.id)
                let sliced = try lower_add_helper_function(d, set.state, try lower_decimal_name(d, "buffer_slice_", checked_id), slice_type_id, lowered.id, 0, 0)
                current = sliced.state
                bridge = LowerBridgeRec(checked_type: checked_id, make_id: make.id, len_id: length.id, append_id: append.id, get_id: get.id, slice_id: sliced.id, set_id: set.id, remove_id: 0)
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
    // Binding block claims emit before the function skeletons: a signature
    // may name a binding type member, and every c_named type must exist and
    // carry its one claim before any reference lowers. Blocks emit in store
    // order, so the mir block id equals the check-store block position.
    let claimed = try lower_binding_claims(d, source_state, store, current)
    current = claimed
    // Function skeletons are fixed before any call body is emitted.
    owner = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        let concrete = lower_owner_concrete(store, owner)
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
            var entry = false
            if symbol.module_source != 0 && symbol.source + 1 == host_project_entry_source() {
                let rec = __s0_buffer_get(SourceRec, source_state.sources, symbol.source)
                entry = source_word(source_state, rec, symbol.name_start, symbol.name_end, "main")
            }
            if symbol.kind == 13 || symbol.inherent_owner != 0 || (symbol.module_source != 0 && !entry) { name = try lower_decimal_name(d, base, owner) }
            if lower_closure_site_for(store, owner) != 0 { name = try lower_decimal_name(d, "closure", owner) }
            var function = try mir_add_function(d, current.mir, name, result_type.id)
            current = lower_with_mir(current, function.store)
            if lower_symbol_is_core_panic(source_state, store, owner) { current = lower_with_mir(current, mir_mark_function_noreturn(current.mir, function.id)) }
            if symbol.c_export && symbol.kind == 12 {
                let exported = try mir_mark_function_exported(d, current.mir, function.id, base)
                function = MirBuildStep(store: exported.store, id: function.id)
                current = lower_with_mir(current, function.store)
            }
            // A capturing closure's thunk receives its domain inside the
            // environment record; a bare thunk takes the caller's domain as
            // its leading parameter, like a named function value.
            let closure_site = lower_closure_site_for(store, owner)
            var wants_domain = false
            if closure_site == 0 {
                wants_domain = !lower_owner_aliases_domain(source_state, store, owner)
            } else {
                let site = __s0_buffer_get(ClosureSiteRec, store.closures.sites, closure_site - 1)
                if site.capture_count == 0 { wants_domain = true }
            }
            if current.has_storage && wants_domain {
                let domain = try lower_domain_mir_type(d, current)
                let hidden = try mir_add_function_param(d, domain.state.mir, function.id, 0, "__domain", domain.id)
                current = lower_with_mir(domain.state, hidden.store)
            }
            let owners = try __s0_buffer_append(LowerOwnerMapRec, d, current.owners, LowerOwnerMapRec(owner: owner, mir_id: function.id))
            current = lower_with_owners(current, owners)
        }
        owner = owner + 1
    }
    // Binding fields, raw fns, and constants emit before the S0 import
    // bridge; the block claims themselves emitted before the function
    // skeletons, so unsafe calls in function bodies resolve against the
    // same flat binding-function sequence.
    let bound = try lower_binding_declarations(d, source_state, store, current)
    return lower_bridge_declarations(d, source_state, store, bound)
}

// The flat binding-function index (1-based) of a binding fn member: the
// count of raw fn members before it in the binding store plus one, matching
// the declaration emission order.
fn lower_binding_fn_flat_index(store: CheckStore, member_index: U64) -> U64 {
    if member_index == 0 || member_index > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return 0 }
    var at: U64 = 0
    var count: U64 = 0
    while at + 1 < member_index {
        if __s0_buffer_get(BindingMemberRec, store.bindings.members, at).member_kind == 2 { count = count + 1 }
        at = at + 1
    }
    return count + 1
}


// ---- Call-scoped buffer borrows ------------------------------------------
// A raw-call argument whose declared parameter is c.Ptr/c.ConstPtr and whose
// checked type is Bytes, [U8], or MutSlice(U8) borrows the buffer for the
// call: one c.buffer.ptr instruction reads the data pointer through the
// declared C pointer type. The buffer is never moved and the pointer never
// becomes an ordinary value.
type LowerCBufferRec {
    matched: Bool
    state: LowerState
    id: U64
}

fn lower_binding_field_for_ordinal(store: CheckStore, owner: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(BindingFieldRec, store.bindings.fields) {
        let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, at)
        if field.owner == owner && field.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn lower_c_buffer_argument(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, annotation: CallAnnotationRec, ordinal: U64, child_id: U64, checked_type: U64, environment: U64, panic_block: U64) -> Result(LowerCBufferRec, __s0_Error) {
    if annotation.kind != 7 { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    let field_index = lower_binding_field_for_ordinal(store, annotation.target, ordinal)
    if field_index == 0 { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, field_index - 1)
    if field.type_index == 0 || field.type_index > __s0_buffer_len(BindingTypeRec, store.bindings.types) { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    let declared = __s0_buffer_get(BindingTypeRec, store.bindings.types, field.type_index - 1)
    if declared.kind != 27 && declared.kind != 28 { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    let actual = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    var buffer_kind: U64 = 0
    if actual.kind == 14 { buffer_kind = 1 }
    if (actual.kind == 8 || actual.kind == 18) && actual.arg_count == 1 {
        let elem = __s0_buffer_get(U64, store.type_args, actual.first_arg - 1)
        if elem != 0 && elem <= __s0_buffer_len(CheckedTypeRec, store.types) {
            let element = __s0_buffer_get(CheckedTypeRec, store.types, elem - 1)
            if element.kind == 1 && element.target == 6 { buffer_kind = 1
                if actual.kind == 18 { buffer_kind = 2 }
            }
        }
    }
    if buffer_kind == 0 { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    if declared.kind == 27 && buffer_kind != 2 { return Ok(LowerCBufferRec(matched: false, state: state, id: 0)) }
    let buffer = try lower_direct_expression(d, source_state, spans, store, state, owner, function, block, child_id, environment, panic_block)
    if !buffer.state.valid { return Ok(LowerCBufferRec(matched: true, state: buffer.state, id: 0)) }
    let pointer_type = try lower_binding_type(d, source_state, store, buffer.state, field.type_index)
    if !pointer_type.state.valid { return Ok(LowerCBufferRec(matched: true, state: pointer_type.state, id: 0)) }
    let name = try lower_result_name(d, pointer_type.state.mir, function, "")
    let value = try mir_add_value(d, pointer_type.state.mir, function, name, pointer_type.id, mir_value_def_instruction(), block, lower_instruction_ordinal(pointer_type.state.mir, function, block) + 1)
    let instr = try lower_add_instr(d, lower_with_mir(pointer_type.state, value.store), function, block, mir_op_c_buffer_ptr(), value.id, 0, pointer_type.id, buffer.id, 0, 0, "")
    return Ok(LowerCBufferRec(matched: true, state: instr.state, id: value.id))
}

// ---- Zero-initialized C values and local addresses ----------------------
// c.Zero(T) emits one c.zero over the boundary type. c.addr lowers its place
// and emits one c.addr through the declared pointer type; the pointer never
// becomes an Alder value.
fn lower_c_zero(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression: CheckedExprRec) -> Result(LowerStep, __s0_Error) {
    let built = try lower_type(d, source_state, store, state, expression.checked_type)
    if !built.state.valid { return Ok(LowerStep(state: built.state, id: 0)) }
    let name = try lower_result_name(d, built.state.mir, function, "")
    let value = try mir_add_value(d, built.state.mir, function, name, built.id, mir_value_def_instruction(), block, lower_instruction_ordinal(built.state.mir, function, block) + 1)
    let instr = try lower_add_instr(d, lower_with_mir(built.state, value.store), function, block, mir_op_c_zero(), value.id, 0, built.id, 0, 0, 0, "")
    return Ok(LowerStep(state: instr.state, id: value.id))
}

// `unsafe c { ptr.field }` and its write form lower through a deref place of
// the pointer value and a verified record field place, then load or store.
fn lower_c_pointer_field(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(BindingFieldRec, store.bindings.fields) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if expression.child_count != 1 && expression.child_count != 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, expression.parameter_use - 1)
    let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let base = try lower_direct_expression(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block)
    if !base.state.valid { return Ok(base) }
    let deref = try mir_add_place(d, base.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: base.id))
    let name = try lower_source_word(d, source_state, field.name_source, field.name_start, field.name_end)
    let named = try mir_append_name(d, deref.store, name)
    let field_place = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: deref.id, field_start: named.start, field_end: named.end, deref_value: 0))
    let current = lower_with_mir(base.state, field_place.store)
    if expression.kind == 34 {
        let value = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, value.state, function, block, mir_op_load(), value.id, field_place.id, 0, 0, 0, 0, "")
        return Ok(LowerStep(state: instr.state, id: value.id))
    }
    let value_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let value = try lower_direct_expression(d, source_state, spans, store, current, owner, function, block, value_id, environment, panic_block)
    if !value.state.valid { return Ok(value) }
    let instr = try lower_add_instr(d, value.state, function, block, mir_op_store(), 0, field_place.id, 0, value.id, 0, 0, "")
    return Ok(LowerStep(state: instr.state, id: 0))
}

// c.load and c.store read or write the whole value behind one C pointer
// through a deref place.
fn lower_c_memory(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 && expression.child_count != 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let pointer_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let pointer = try lower_direct_expression(d, source_state, spans, store, state, owner, function, block, pointer_id, environment, panic_block)
    if !pointer.state.valid { return Ok(pointer) }
    let deref = try mir_add_place(d, pointer.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: pointer.id))
    let current = lower_with_mir(pointer.state, deref.store)
    if expression.kind == 36 {
        let value = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, value.state, function, block, mir_op_load(), value.id, deref.id, 0, 0, 0, 0, "")
        return Ok(LowerStep(state: instr.state, id: value.id))
    }
    let value_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let value = try lower_direct_expression(d, source_state, spans, store, current, owner, function, block, value_id, environment, panic_block)
    if !value.state.valid { return Ok(value) }
    let instr = try lower_add_instr(d, value.state, function, block, mir_op_store(), 0, deref.id, 0, value.id, 0, 0, "")
    return Ok(LowerStep(state: instr.state, id: 0))
}

type LowerCAddrRec {
    matched: Bool
    state: LowerState
    id: U64
}

fn lower_c_addr_argument(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, child_id: U64, environment: U64, panic_block: U64) -> Result(LowerCAddrRec, __s0_Error) {
    if child_id == 0 || child_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerCAddrRec(matched: false, state: state, id: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
    if expression.kind != 33 || expression.child_count != 1 { return Ok(LowerCAddrRec(matched: false, state: state, id: 0)) }
    var borrow_kind: U64 = 1
    if expression.checked_type != 0 && expression.checked_type <= __s0_buffer_len(CheckedTypeRec, store.types) {
        if __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1).kind == 27 { borrow_kind = 2 }
    }
    let place_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let place = try lower_argument_place(d, source_state, spans, store, state, owner, function, block, place_id, environment, panic_block, borrow_kind)
    if !place.state.valid { return Ok(LowerCAddrRec(matched: true, state: place.state, id: 0)) }
    let pointer = try lower_type(d, source_state, store, place.state, expression.checked_type)
    if !pointer.state.valid { return Ok(LowerCAddrRec(matched: true, state: pointer.state, id: 0)) }
    let name = try lower_result_name(d, pointer.state.mir, function, "")
    let value = try mir_add_value(d, pointer.state.mir, function, name, pointer.id, mir_value_def_instruction(), block, lower_instruction_ordinal(pointer.state.mir, function, block) + 1)
    let instr = try lower_add_instr(d, lower_with_mir(pointer.state, value.store), function, block, mir_op_c_addr(), value.id, place.place, pointer.id, 0, 0, 0, "")
    return Ok(LowerCAddrRec(matched: true, state: instr.state, id: value.id))
}

type LowerCCallbackRec {
    matched: Bool
    state: LowerState
    id: U64
}

// c.callback(name) is a direct raw-call argument: the target function's MIR
// ID and the declared callback type ride on one c.callback.make instruction,
// whose C value is the generated trampoline address.
fn lower_c_callback_argument(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, child_id: U64, environment: U64, panic_block: U64) -> Result(LowerCCallbackRec, __s0_Error) {
    if child_id == 0 || child_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerCCallbackRec(matched: false, state: state, id: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
    if expression.kind != 38 || expression.parameter_use == 0 { return Ok(LowerCCallbackRec(matched: false, state: state, id: 0)) }
    let target = lower_owner_lookup(state.owners, expression.parameter_use)
    if target == 0 { return Ok(LowerCCallbackRec(matched: true, state: lower_invalid(state), id: 0)) }
    let callback_type = try lower_type(d, source_state, store, state, expression.checked_type)
    if !callback_type.state.valid { return Ok(LowerCCallbackRec(matched: true, state: callback_type.state, id: 0)) }
    let value = try lower_add_result(d, callback_type.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, value.state, function, block, mir_op_c_callback_make(), value.id, 0, callback_type.id, 0, 0, target, "")
    return Ok(LowerCCallbackRec(matched: true, state: instr.state, id: value.id))
}

// An unsafe binding call expression is valid when the call carries no extra
// flags and its argument count equals the member's parameter field count;
// per-argument types ride on the checker and the MIR verifier's signature
// check.
fn lower_model_binding_call_ok(store: CheckStore, annotation: CallAnnotationRec, item: CheckedExprRec) -> Bool {
    if item.parameter_use != 0 || item.bool_value != 0 || item.operator != 0 { return false }
    var binding_params: U64 = 0
    var binding_field_at: U64 = 0
    while binding_field_at < __s0_buffer_len(BindingFieldRec, store.bindings.fields) {
        if __s0_buffer_get(BindingFieldRec, store.bindings.fields, binding_field_at).owner == annotation.target { binding_params = binding_params + 1 }
        binding_field_at = binding_field_at + 1
    }
    return item.child_count == binding_params
}

// Lowers an unsafe binding call: the target is the flat binding-function
// index (1-based); the result carries the declared C result type, unit for
// void functions.
fn lower_binding_call_step(d: Domain, store: CheckStore, state: LowerState, function: U64, block: U64, result: U64, annotation: CallAnnotationRec, args: __s0_Buffer(U64)) -> Result(LowerStep, __s0_Error) {
    let flat = lower_binding_fn_flat_index(store, annotation.target)
    if flat == 0 || flat > __s0_buffer_len(MirBindingFnRec, state.mir.binding_funcs) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let instr = try lower_add_instr(d, state, function, block, mir_op_c_binding_call(), result, 0, 0, 0, 0, flat, "")
    var current = instr.state
    var ordinal: U64 = 0
    while ordinal < __s0_buffer_len(U64, args) {
        current = try lower_add_instr_operand(d, current, instr.id, ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
        ordinal = ordinal + 1
    }
    return Ok(LowerStep(state: current, id: result))
}

// The claim pass of the binding blocks: one block and one claimed c_named
// type per declared type member. Claims run before function signatures,
// fields, raw fns, and constants, so every reference resolves to its claim
// operand and each c_named type stays claimed by exactly one operand.
fn lower_binding_claims(d: Domain, source_state: State, store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var block_at: U64 = 0
    while block_at < __s0_buffer_len(BindingBlockRec, store.bindings.blocks) {
        let block = __s0_buffer_get(BindingBlockRec, store.bindings.blocks, block_at)
        let name = try lower_source_word(d, source_state, block.name_source, block.name_start, block.name_end)
        let header = try lower_binding_word(d, source_state, true, block.header_source, block.header_start, block.header_end)
        let made = try mir_add_binding(d, current.mir, name, header)
        current = lower_with_mir(current, made.store)
        var member_at: U64 = 0
        var type_ordinal: U64 = 0
        while member_at < __s0_buffer_len(BindingMemberRec, store.bindings.members) {
            let member = __s0_buffer_get(BindingMemberRec, store.bindings.members, member_at)
            if member.block_node == block.node && member.member_kind == 1 {
                let named = try lower_binding_named(d, source_state, store, current, member.member_node)
                if !named.state.valid { return Ok(named.state) }
                current = named.state
                current = lower_with_mir(current, try mir_add_binding_type(d, current.mir, made.id, type_ordinal, named.id))
                type_ordinal = type_ordinal + 1
            }
            member_at = member_at + 1
        }
        block_at = block_at + 1
    }
    return Ok(current)
}

// After the claim pass: record fields attach to their claimed types, then
// raw fn signatures, then constants, per block in store order. The flat
// binding-function index follows the binding store order, so unsafe calls
// in function bodies resolve against the same sequence.
fn lower_binding_declarations(d: Domain, source_state: State, store: CheckStore, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var block_at: U64 = 0
    while block_at < __s0_buffer_len(BindingBlockRec, store.bindings.blocks) {
        let block = __s0_buffer_get(BindingBlockRec, store.bindings.blocks, block_at)
        var member_at: U64 = 0
        while member_at < __s0_buffer_len(BindingMemberRec, store.bindings.members) {
            let member = __s0_buffer_get(BindingMemberRec, store.bindings.members, member_at)
            if member.block_node == block.node && member.member_kind == 1 && member.class == 2 {
                let type_id = lower_binding_claimed_type(store, current.mir, member_at + 1)
                if type_id == 0 { return Ok(lower_invalid(current)) }
                current = try lower_binding_fields(d, source_state, store, current, member_at + 1, type_id)
            }
            member_at = member_at + 1
        }
        member_at = 0
        while member_at < __s0_buffer_len(BindingMemberRec, store.bindings.members) {
            let member = __s0_buffer_get(BindingMemberRec, store.bindings.members, member_at)
            if member.block_node == block.node && member.member_kind == 2 {
                let fn_name = try lower_source_word(d, source_state, member.name_source, member.name_start, member.name_end)
                let fn_c_name = try lower_binding_word(d, source_state, member.spelling_values, member.spelling_source, member.spelling_start, member.spelling_end)
                let result_type = try lower_binding_type(d, source_state, store, current, member.checked_type)
                if !result_type.state.valid { return Ok(result_type.state) }
                let made_fn = try mir_add_binding_fn(d, result_type.state.mir, block_at + 1, fn_name, fn_c_name, result_type.id)
                current = lower_with_mir(current, made_fn.store)
                var param_at: U64 = 0
                var param_ordinal: U64 = 0
                while param_at < __s0_buffer_len(BindingFieldRec, store.bindings.fields) {
                    let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, param_at)
                    if field.owner == member_at + 1 {
                        let param_type = try lower_binding_type(d, source_state, store, current, field.type_index)
                        if !param_type.state.valid { return Ok(param_type.state) }
                        current = param_type.state
                        current = lower_with_mir(current, try mir_add_binding_fn_param(d, current.mir, made_fn.id, param_ordinal, param_type.id))
                        param_ordinal = param_ordinal + 1
                    }
                    param_at = param_at + 1
                }
            }
            member_at = member_at + 1
        }
        member_at = 0
        while member_at < __s0_buffer_len(BindingMemberRec, store.bindings.members) {
            let member = __s0_buffer_get(BindingMemberRec, store.bindings.members, member_at)
            if member.block_node == block.node && member.member_kind == 3 {
                let const_name = try lower_source_word(d, source_state, member.name_source, member.name_start, member.name_end)
                let const_c_name = try lower_binding_word(d, source_state, member.spelling_values, member.spelling_source, member.spelling_start, member.spelling_end)
                let const_type = try lower_binding_type(d, source_state, store, current, member.checked_type)
                if !const_type.state.valid { return Ok(const_type.state) }
                current = const_type.state
                current = lower_with_mir(current, (try mir_add_binding_const(d, current.mir, block_at + 1, const_name, const_c_name, const_type.id)).store)
            }
            member_at = member_at + 1
        }
        block_at = block_at + 1
    }
    return Ok(current)
}

fn lower_instruction_ordinal(mir: MirStore, function: U64, block: U64) -> U64 {
    var at = __s0_buffer_len(MirInstrRec, mir.instructions)
    while at != 0 {
        at = at - 1
        let item = __s0_buffer_get(MirInstrRec, mir.instructions, at)
        if item.function != function { return 0 }
        if item.block == block { return item.ordinal + 1 }
    }
    return 0
}

fn lower_block_terminated(mir: MirStore, function: U64, block: U64) -> Bool {
    var at = __s0_buffer_len(MirTermRec, mir.terminators)
    while at != 0 {
        at = at - 1
        let term = __s0_buffer_get(MirTermRec, mir.terminators, at)
        if term.function != function { return false }
        if term.function == function && term.block == block { return true }
    }
    return false
}

fn lower_open_block(mir: MirStore, function: U64, requested: U64) -> U64 {
    if !lower_block_terminated(mir, function, requested) { return requested }
    // Blocks are appended in ordinal order per function. The legacy forward
    // scan selected the highest open ordinal, so the first open block in this
    // reverse walk is the same result without probing every older block.
    var at = __s0_buffer_len(MirBlockRec, mir.blocks)
    while at != 0 {
        at = at - 1
        let candidate = __s0_buffer_get(MirBlockRec, mir.blocks, at)
        if candidate.function != function { return requested }
        if candidate.function == function && !lower_block_terminated(mir, function, candidate.ordinal + 1) { return candidate.ordinal + 1 }
    }
    return requested
}

fn lower_block_count(mir: MirStore, function: U64) -> U64 {
    let count = __s0_buffer_len(MirBlockRec, mir.blocks)
    if count == 0 { return 0 }
    let block = __s0_buffer_get(MirBlockRec, mir.blocks, count - 1)
    if block.function != function { return 0 }
    return block.ordinal + 1
}

fn lower_local_count(mir: MirStore, function: U64) -> U64 {
    let count = __s0_buffer_len(MirLocalRec, mir.locals)
    if count == 0 { return 0 }
    let local = __s0_buffer_get(MirLocalRec, mir.locals, count - 1)
    if local.function != function { return 0 }
    return local.ordinal + 1
}

fn lower_add_block(d: Domain, state: LowerState, function: U64, prefix: __s0_String) -> Result(LowerStep, __s0_Error) {
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

fn lower_result_name_taken(mir: MirStore, function: U64, name: __s0_String) -> Bool {
    var at = __s0_buffer_len(MirValueRec, mir.values)
    while at != 0 {
        at = at - 1
        let value = __s0_buffer_get(MirValueRec, mir.values, at)
        if value.function != function { return false }
        if value.function == function && value.name_end - value.name_start == len(name) {
            var byte: U64 = 0
            var equal = true
            while byte < len(name) {
                if __s0_buffer_get(U8, mir.names, value.name_start + byte) != name[byte] { equal = false }
                byte = byte + 1
            }
            if equal { return true }
        }
    }
    return false
}

fn lower_parameter_name_taken(mir: MirStore, function: U64, name: __s0_String) -> Bool {
    var at = __s0_buffer_len(MirParamRec, mir.params)
    while at != 0 {
        at = at - 1
        let parameter = __s0_buffer_get(MirParamRec, mir.params, at)
        if parameter.function != function { return false }
        if parameter.value != 0 && parameter.value <= __s0_buffer_len(MirValueRec, mir.values) {
            let value = __s0_buffer_get(MirValueRec, mir.values, parameter.value - 1)
            if value.name_end - value.name_start == len(name) {
                var byte: U64 = 0
                var equal = true
                while byte < len(name) {
                    if __s0_buffer_get(U8, mir.names, value.name_start + byte) != name[byte] { equal = false }
                    byte = byte + 1
                }
                if equal { return true }
            }
        }
    }
    return false
}

fn lower_result_name(d: Domain, mir: MirStore, function: U64, preferred: __s0_String) -> Result(__s0_String, __s0_Error) {
    if len(preferred) != 0 && !lower_result_name_taken(mir, function, preferred) { return Ok(preferred) }
    var suffix = __s0_buffer_len(MirValueRec, mir.values) + 1
    var name = try lower_decimal_name(d, "v", suffix)
    if len(preferred) == 0 && !lower_parameter_name_taken(mir, function, name) { return Ok(name) }
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

fn lower_add_instr(d: Domain, state: LowerState, function: U64, block: U64, op: U64, result: U64, place: U64, type_op: U64, a: U64, b: U64, target: U64, name: __s0_String) -> Result(LowerStep, __s0_Error) {
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

fn lower_helper_local_place(d: Domain, state: LowerState, function: U64, ordinal: U64, name: __s0_String, type_id: U64) -> Result(LowerStep, __s0_Error) {
    let local = try mir_add_local(d, state.mir, function, ordinal, name, type_id)
    let place = try mir_add_place(d, local.store, MirPlaceRec(function: function, kind: mir_place_local(), local: local.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    return Ok(LowerStep(state: lower_with_mir(state, place.store), id: place.id))
}

fn lower_helper_field_place(d: Domain, state: LowerState, function: U64, base: U64, name: __s0_String) -> Result(LowerStep, __s0_Error) {
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

fn lower_helper_construct_two(d: Domain, state: LowerState, function: U64, block: U64, type_id: U64, first_name: __s0_String, first: U64, second_name: __s0_String, second: U64) -> Result(LowerStep, __s0_Error) {
    let result = try lower_add_typed_result(d, state, function, block, type_id)
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_aggregate_construct(), result.id, 0, type_id, 0, 0, 0, "")
    let first_operand = try lower_add_instr_operand(d, instruction.state, instruction.id, 0, first, mir_operand_aggregate_field(), first_name)
    let second_operand = try lower_add_instr_operand(d, first_operand, instruction.id, 1, second, mir_operand_aggregate_field(), second_name)
    return Ok(LowerStep(state: second_operand, id: result.id))
}

fn lower_helper_variant(d: Domain, state: LowerState, function: U64, block: U64, type_id: U64, name: __s0_String, payload: U64) -> Result(LowerStep, __s0_Error) {
    let result = try lower_add_typed_result(d, state, function, block, type_id)
    let instruction = try lower_add_instr(d, result.state, function, block, mir_op_enum_construct(), result.id, 0, type_id, payload, 0, 0, name)
    return Ok(LowerStep(state: instruction.state, id: result.id))
}

fn lower_helper_return(d: Domain, state: LowerState, function: U64, block: U64, value: U64) -> Result(LowerState, __s0_Error) {
    let term = try mir_add_terminator(d, state.mir, MirTermRec(function: function, block: block, kind: mir_term_return(), value: value, target: 0, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(state, term.store))
}

fn lower_add_instr_operand(d: Domain, state: LowerState, instruction: U64, ordinal: U64, value: U64, kind: U64, name: __s0_String) -> Result(LowerState, __s0_Error) {
    var named = MirNameStep(store: state.mir, start: 0, end: 0)
    if len(name) != 0 { named = try mir_append_name(d, state.mir, name) }
    let rec = MirOperandRec(kind: kind, owner: instruction, ordinal: ordinal, edge: 0, value: value, target: 0, operand_type: 0, name_start: named.start, name_end: named.end)
    let step = try mir_add_operand(d, named.store, rec)
    return Ok(lower_with_mir(state, step.store))
}

fn lower_variant_name(d: Domain, source_state: State, store: CheckStore, variant_kind: U64, variant_use: U64) -> Result(__s0_String, __s0_Error) {
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

fn lower_add_switch_case(d: Domain, state: LowerState, term: U64, ordinal: U64, name: __s0_String, binding: U64, target: U64) -> Result(LowerStep, __s0_Error) {
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
    var value: U64 = 0
    var negative = false
    var at = source.text_start + span.start
    let end = source.text_start + span.end
    if at < end && __s0_buffer_get(U8, source_state.texts, at) == 45 {
        negative = true
        at = at + 1
    }
    // Digits accumulate in U64 so a U64-range literal whose magnitude
    // exceeds the positive I64 range parses without an intermediate
    // overflow; the checker has already bounded the literal by its
    // declared type. The accumulated value is then reinterpreted as the
    // I64 with the same 64-bit pattern.
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
    let bits = unsafe c { alderhost_i64_from_u64_bits(value) }
    if negative && bits > 0 { return 0 - bits }
    return bits
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

fn lower_bool_value(d: Domain, source_state: State, store: CheckStore, state: LowerState, function: U64, block: U64, checked_type: U64, value: U64, prefix: __s0_String, suffix: U64) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    let name = try lower_decimal_name(d, prefix, suffix)
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

// lower_int_value_seq creates an integer constant in the sequence-lowering
// name space: its suffix comes from the per-module constant counter, which
// statement-keyed literal names never use, so the two spaces cannot collide.
fn lower_int_value_seq(d: Domain, source_state: State, store: CheckStore, state: LowerState, function: U64, block: U64, value: I64) -> Result(LowerStep, __s0_Error) {
    let suffix = __s0_buffer_len(MirConstRec, state.mir.constants) + __s0_buffer_len(MirFunctionRec, state.mir.functions) * 4194304 + 1
    let name = try lower_decimal_name(d, "lit.seq", suffix)
    let constant = try mir_add_const(d, state.mir, name, mir_type_u64(), mir_const_int(), 0, value, 0, "")
    let result = try lower_add_result(d, lower_with_mir(state, constant.store), function, block, 9, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, mir_op_const_get(), result.id, 0, 0, 0, 0, 0, name)
    return Ok(LowerStep(state: instr.state, id: result.id))
}

fn lower_token_for_span(state: State, span: CheckedSpanRec) -> U64 {
    var first: U64 = 0
    var end = __s0_buffer_len(TokenRec, state.tokens)
    while first < end {
        let middle = first + (end - first) / 2
        let token = __s0_buffer_get(TokenRec, state.tokens, middle)
        if token.source < span.source || (token.source == span.source && token.start < span.start) { first = middle + 1 } else { end = middle }
    }
    if first >= __s0_buffer_len(TokenRec, state.tokens) { return 0 }
    let token = __s0_buffer_get(TokenRec, state.tokens, first)
    if token.source == span.source && token.start == span.start && token.end == span.end { return first + 1 }
    return 0
}

// Extend the owner-keyed type-part index to cover every part currently in the
// MIR store. Only the parts appended since the last call are linked, so the
// total work over a whole lowering run is proportional to the table.
fn lower_part_index_sync(d: Domain, state0: LowerState) -> Result(LowerState, __s0_Error) {
    var state = state0
    var index = state.part_index
    let total = __s0_buffer_len(MirTypeRec, state.mir.types)
    var head_len = __s0_buffer_len(U64, index.head)
    while head_len <= total {
        index.head = try __s0_buffer_append(U64, d, index.head, 0)
        head_len = head_len + 1
    }
    let parts = __s0_buffer_len(MirTypePartRec, state.mir.type_parts)
    while index.indexed < parts {
        let at = index.indexed
        let part = __s0_buffer_get(MirTypePartRec, state.mir.type_parts, at)
        var link: U64 = 0
        if part.owner >= 1 && part.owner <= total { link = __s0_buffer_get(U64, index.head, part.owner) }
        index.next = try __s0_buffer_append(U64, d, index.next, link)
        if part.owner >= 1 && part.owner <= total { __s0_buffer_set(U64, index.head, part.owner, at + 1) }
        index.indexed = at + 1
    }
    return Ok(lower_with_part_index(state, index))
}

// Does the type rooted at `root` reach a Vec? The walk is a closure over the
// elem / ok / err / result edges plus every type part of each visited type.
// The part edges come from the owner-keyed index, so a visited type costs its
// own part count rather than a scan of the whole part table.
fn lower_mir_type_contains_vec(d: Domain, state0: LowerState, root: U64) -> Result(LowerVecStep, __s0_Error) {
    var state = try lower_part_index_sync(d, state0)
    let count = __s0_buffer_len(MirTypeRec, state.mir.types)
    if root < 1 || root > count { return Ok(LowerVecStep(state: state, value: false)) }
    // Extend the memo to the current type list first; MIR type records are
    // append-only while lowering, so every recorded entry stays valid and the
    // answer for each id is computed by the original walk at most once.
    // Part edges are the exception: mir_add_type_part can attach new parts to
    // an existing type, so flag cell 0 stores the part-table length at fill
    // time; when it grew, cached "no vec" answers may have flipped and are
    // dropped, while cached "vec" answers stay valid because adding edges can
    // only add vec reachability, never remove it.
    var flag = state.vec_memo_flag
    var ans = state.vec_memo_ans
    var seen = state.vec_memo_seen
    let parts_len = __s0_buffer_len(MirTypePartRec, state.mir.type_parts)
    while __s0_buffer_len(U64, flag) <= count {
        flag = try __s0_buffer_append(U64, d, flag, 0)
        ans = try __s0_buffer_append(U64, d, ans, 0)
        seen = try __s0_buffer_append(U64, d, seen, 0)
    }
    if __s0_buffer_len(U64, state.vec_memo_flag) == 0 {
        __s0_buffer_set(U64, flag, 0, parts_len)
    } else {
        if __s0_buffer_get(U64, flag, 0) != parts_len {
            var clear_at: U64 = 1
            while clear_at < __s0_buffer_len(U64, flag) {
                if __s0_buffer_get(U64, ans, clear_at) == 0 { __s0_buffer_set(U64, flag, clear_at, 0) }
                clear_at = clear_at + 1
            }
            __s0_buffer_set(U64, flag, 0, parts_len)
        }
    }
    if __s0_buffer_get(U64, flag, root) != 0 {
        return Ok(LowerVecStep(state: lower_with_vec_memo(state, flag, ans, seen, state.vec_memo_gen), value: __s0_buffer_get(U64, ans, root) != 0))
    }
    let gen = state.vec_memo_gen + 1
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var at: U64 = 0
    var found = false
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        at = at + 1
        if id >= 1 && id <= count && __s0_buffer_get(U64, seen, id) != gen {
            __s0_buffer_set(U64, seen, id, gen)
            let typ = __s0_buffer_get(MirTypeRec, state.mir.types, id - 1)
            if typ.kind == mir_type_kind_vec() {
                found = true
            }
            if typ.elem != 0 { work = try __s0_buffer_append(U64, d, work, typ.elem) }
            if typ.ok_type != 0 { work = try __s0_buffer_append(U64, d, work, typ.ok_type) }
            if typ.err_type != 0 { work = try __s0_buffer_append(U64, d, work, typ.err_type) }
            if typ.result_type != 0 { work = try __s0_buffer_append(U64, d, work, typ.result_type) }
            var part_at = __s0_buffer_get(U64, state.part_index.head, id)
            while part_at != 0 {
                let part = __s0_buffer_get(MirTypePartRec, state.mir.type_parts, part_at - 1)
                if part.part_type != 0 { work = try __s0_buffer_append(U64, d, work, part.part_type) }
                part_at = __s0_buffer_get(U64, state.part_index.next, part_at - 1)
            }
        }
    }
    __s0_buffer_set(U64, flag, 0, parts_len)
    __s0_buffer_set(U64, flag, root, 1)
    if found { __s0_buffer_set(U64, ans, root, 1) }
    return Ok(LowerVecStep(state: lower_with_vec_memo(state, flag, ans, seen, gen), value: found))
}

fn lower_mir_type_copy_relocatable(d: Domain, store: MirStore, root: U64) -> Result(Bool, __s0_Error) {
    let count = __s0_buffer_len(MirTypeRec, store.types)
    var seen = __s0_alloc(U64, d, count + 1)
    var zero: U64 = 0
    while zero <= count { seen[zero] = 0
        zero = zero + 1 }
    var work = try __s0_buffer_new(U64, d)
    work = try __s0_buffer_append(U64, d, work, root)
    var at: U64 = 0
    while at < __s0_buffer_len(U64, work) {
        let id = __s0_buffer_get(U64, work, at)
        if id >= 1 && id <= count && seen[id] == 0 {
            seen[id] = 1
            let typ = __s0_buffer_get(MirTypeRec, store.types, id - 1)
            if typ.kind == mir_type_kind_domain_handle() || typ.kind == mir_type_kind_domain_mark() || typ.kind == mir_type_kind_cleanup_scope() || typ.kind == mir_type_kind_cleanup_id() || typ.kind == mir_type_kind_table() || typ.kind == mir_type_kind_table_view() || typ.kind == mir_type_kind_table_mut_view() || typ.kind == mir_type_kind_raw_ptr() || typ.kind == mir_type_kind_c_raw() || typ.kind == mir_type_kind_c_ptr() || typ.kind == mir_type_kind_c_const_ptr() || typ.kind == mir_type_kind_c_named() || typ.kind == mir_type_kind_c_string() { return Ok(false) }
            if typ.elem != 0 { work = try __s0_buffer_append(U64, d, work, typ.elem) }
            if typ.ok_type != 0 { work = try __s0_buffer_append(U64, d, work, typ.ok_type) }
            if typ.err_type != 0 { work = try __s0_buffer_append(U64, d, work, typ.err_type) }
            if typ.result_type != 0 { work = try __s0_buffer_append(U64, d, work, typ.result_type) }
            var part_at: U64 = 0
            while part_at < __s0_buffer_len(MirTypePartRec, store.type_parts) {
                let part = __s0_buffer_get(MirTypePartRec, store.type_parts, part_at)
                if part.owner == id && part.part_type != 0 { work = try __s0_buffer_append(U64, d, work, part.part_type) }
                part_at = part_at + 1
            }
        }
        at = at + 1
    }
    return Ok(true)
}

// lower_mir_type_has_reference reports whether a value of this type holds
// storage through a reference, slice, vector, string, bytes, or table
// anywhere. String and Bytes count because their buffers may be
// domain-allocated, so a capture must copy the value, not alias the frame.
fn lower_mir_type_has_reference(d: Domain, store: MirStore, root: U64) -> Bool {
    let count = __s0_buffer_len(MirTypeRec, store.types)
    if root < 1 || root > count { return false }
    var seen = __s0_alloc(U64, d, count + 1)
    var zero: U64 = 0
    while zero <= count { seen[zero] = 0
        zero = zero + 1 }
    var work = __s0_alloc(U64, d, count + 1)
    var total: U64 = 1
    work[0] = root
    var at: U64 = 0
    while at < total {
        let id = work[at]
        if id >= 1 && id <= count && seen[id] == 0 {
            seen[id] = 1
            let typ = __s0_buffer_get(MirTypeRec, store.types, id - 1)
            if typ.kind == mir_type_kind_slice() || typ.kind == mir_type_kind_vec() || typ.kind == mir_type_kind_string() || typ.kind == mir_type_kind_bytes() || typ.kind == mir_type_kind_safe_ref() || typ.kind == mir_type_kind_safe_mut() || typ.kind == mir_type_kind_table() { return true }
            if typ.elem != 0 && total < count { work[total] = typ.elem
                total = total + 1 }
            if typ.ok_type != 0 && total < count { work[total] = typ.ok_type
                total = total + 1 }
            if typ.err_type != 0 && total < count { work[total] = typ.err_type
                total = total + 1 }
            if typ.result_type != 0 && total < count { work[total] = typ.result_type
                total = total + 1 }
            var part_at: U64 = 0
            while part_at < __s0_buffer_len(MirTypePartRec, store.type_parts) && total < count {
                let part = __s0_buffer_get(MirTypePartRec, store.type_parts, part_at)
                if part.owner == id && part.part_type != 0 { work[total] = part.part_type
                    total = total + 1 }
                part_at = part_at + 1
            }
        }
        at = at + 1
    }
    return false
}

// lower_capture_storage_copy materializes a storage-bearing capture in the
// environment's domain when the capture path did not already copy it: the
// vector copy handles vector-based types, and the bootstrap map and buffer
// records carry references instead.
fn lower_capture_storage_copy(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, checked_type: U64, value: U64) -> Result(LowerStep, __s0_Error) {
    // A captured scoped capability is a view, not owned storage: the closure
    // aliases the scope that owns it, which the escape rule keeps alive.
    if checked_type >= 1 && checked_type <= __s0_buffer_len(CheckedTypeRec, store.types) {
        let capture = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
        if capture.kind == 8 || capture.kind == 18 { return Ok(LowerStep(state: state, id: value)) }
    }
    let typ = try lower_type(d, source_state, store, state, checked_type)
    if !typ.state.valid { return Ok(typ) }
    let vec = try lower_mir_type_contains_vec(d, typ.state, typ.id)
    if !vec.state.valid { return Ok(LowerStep(state: vec.state, id: 0)) }
    if vec.value { return Ok(LowerStep(state: vec.state, id: value)) }
    if !lower_mir_type_has_reference(d, vec.state.mir, typ.id) { return Ok(LowerStep(state: vec.state, id: value)) }
    let domain = lower_storage_domain_value(vec.state, store, owner, expression_id)
    if domain == 0 { return Ok(LowerStep(state: lower_invalid(vec.state), id: 0)) }
    let result = try lower_add_typed_result(d, vec.state, function, block, typ.id)
    let copied = try lower_add_instr(d, result.state, function, block, mir_op_copy_to_domain(), result.id, 0, 0, domain, value, 0, "")
    var current = copied.state
    if expression_id != 0 && expression_id <= __s0_buffer_len(CheckedExprRec, store.expressions) {
        let site = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
        if site.syntax != 0 && site.syntax <= __s0_buffer_len(CheckedSpanRec, spans) {
            let span = __s0_buffer_get(CheckedSpanRec, spans, site.syntax - 1)
            current = try lower_add_copy_report(d, current, owner, span.source, span.start, span.end, 0, 2)
        }
    }
    return Ok(LowerStep(state: current, id: result.id))
}

fn lower_copy_if_vec(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, checked_type: U64, value: U64) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    let vec = try lower_mir_type_contains_vec(d, typ.state, typ.id)
    if !vec.value { return Ok(LowerStep(state: vec.state, id: value)) }
    let domain = lower_storage_domain_value(vec.state, store, owner, expression_id)
    if domain == 0 { return Ok(LowerStep(state: lower_invalid(vec.state), id: 0)) }
    let result = try lower_add_typed_result(d, vec.state, function, block, typ.id)
    let copied = try lower_add_instr(d, result.state, function, block, mir_op_copy_to_domain(), result.id, 0, 0, domain, value, 0, "")
    return Ok(LowerStep(state: copied.state, id: result.id))
}

// ---------------------------------------------------------------------------
// D023: in-place update of uniquely owned values.
//
// lower_move_analyze computes, for one concrete function instance, which
// binding-read expressions may transfer their source storage instead of
// copying it. A read outside every loop moves when no later access to that
// binding in program order is a read. A read inside a loop body moves when
// the body re-establishes the binding before the read repeats, which
// lower_move_loop_reason decides. Parameters never move: their storage
// belongs to the caller, and the dead-argument case is decided at the
// caller's copy site. Bindings captured by closures and bindings that ever
// form a view are excluded conservatively. Verdicts write into the shared
// movable buffer and reasons into the shared reason buffer, both indexed by
// expression ID and allocated once per compilation.

type LowerMoveWalkRec {
    events: __s0_Buffer(LowerMoveEventRec)
    excluded: __s0_Buffer(U64)
    loops: __s0_Buffer(LowerMoveLoopRec)
    // Number of skipping constructs entered so far. Each loop records the
    // delta across its own body, so the counter answers "is this body
    // straight-line code" without a second walk.
    conditionals: U64
}

fn lower_move_walk_expression(d: Domain, store: CheckStore, walk: LowerMoveWalkRec, loop_at: U64, expression_id: U64) -> Result(LowerMoveWalkRec, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(walk) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    var events = walk.events
    var excluded = walk.excluded
    if (expression.kind == 1 || expression.kind == 5 || expression.kind == 22) && expression.parameter_use != 0 && expression.parameter_use <= __s0_buffer_len(LocalRec, store.locals) {
        events = try __s0_buffer_append(LowerMoveEventRec, d, events, LowerMoveEventRec(binding: expression.parameter_use, expression: expression_id, is_definition: 0))
    }
    if expression.kind == 18 && expression.annotation != 0 {
        // A slice or mutable-slice view of a binding keeps an implicit later
        // reference to its storage, so that binding never moves.
        let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
        if annotation.builtin == 23 || annotation.builtin == 24 {
            if expression.child_count != 0 && expression.first_child != 0 && expression.first_child <= __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
                let receiver_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
                if receiver_id != 0 && receiver_id <= __s0_buffer_len(CheckedExprRec, store.expressions) {
                    let receiver = __s0_buffer_get(CheckedExprRec, store.expressions, receiver_id - 1)
                    if (receiver.kind == 1 || receiver.kind == 5) && receiver.parameter_use != 0 && receiver.parameter_use <= __s0_buffer_len(U64, excluded) {
                        if __s0_buffer_get(U64, excluded, receiver.parameter_use - 1) == 0 { __s0_buffer_set(U64, excluded, receiver.parameter_use - 1, 3) }
                    }
                }
            }
        }
    }
    var child: U64 = 0
    var inner = LowerMoveWalkRec(events: events, excluded: excluded, loops: walk.loops, conditionals: walk.conditionals)
    while child < expression.child_count {
        if expression.first_child != 0 && expression.first_child - 1 + child < __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
            inner = try lower_move_walk_expression(d, store, inner, loop_at, __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + child).expression)
        }
        child = child + 1
    }
    if expression.kind == 12 && expression.parameter_use != 0 && expression.parameter_use <= __s0_buffer_len(CheckedMatchRec, store.control.matches) {
        let checked = __s0_buffer_get(CheckedMatchRec, store.control.matches, expression.parameter_use - 1)
        inner = LowerMoveWalkRec(events: inner.events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals + 1)
        var arm: U64 = 0
        while arm < checked.arm_count {
            let arm_rec = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + arm)
            if arm_rec.body != 0 { inner = try lower_move_walk_expression(d, store, inner, loop_at, arm_rec.body) }
            if arm_rec.block != 0 { inner = try lower_move_walk_block(d, store, inner, loop_at, arm_rec.block) }
            if arm_rec.statement != 0 { inner = try lower_move_walk_one(d, store, inner, loop_at, arm_rec.statement) }
            arm = arm + 1
        }
    }
    if expression.kind == 13 && expression.parameter_use != 0 && expression.parameter_use <= __s0_buffer_len(CheckedTryRec, store.control.tries) {
        inner = LowerMoveWalkRec(events: inner.events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals + 1)
        inner = try lower_move_walk_expression(d, store, inner, loop_at, __s0_buffer_get(CheckedTryRec, store.control.tries, expression.parameter_use - 1).expression)
    }
    return Ok(inner)
}

fn lower_move_walk_block(d: Domain, store: CheckStore, walk: LowerMoveWalkRec, loop_at: U64, block_id: U64) -> Result(LowerMoveWalkRec, __s0_Error) {
    if block_id == 0 || block_id > __s0_buffer_len(CheckedBlockRec, store.control.blocks) { return Ok(walk) }
    let block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, block_id - 1)
    // The statement chain is reverse source ordered: collect it, then walk
    // the statements front to back so events follow lowering order.
    var chain = try __s0_buffer_new(U64, d)
    var at = block.statements
    var walking = true
    while at != 0 && walking {
        if at > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
            walking = false
        } else {
            let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at - 1)
            if link.statement != 0 && link.statement <= __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                chain = try __s0_buffer_append(U64, d, chain, link.statement)
            }
            at = link.next
        }
    }
    var inner = walk
    var index = __s0_buffer_len(U64, chain)
    while index > 0 {
        inner = try lower_move_walk_one(d, store, inner, loop_at, __s0_buffer_get(U64, chain, index - 1))
        index = index - 1
    }
    return Ok(inner)
}

fn lower_move_walk_one(d: Domain, store: CheckStore, walk: LowerMoveWalkRec, loop_at: U64, statement_id: U64) -> Result(LowerMoveWalkRec, __s0_Error) {
    if statement_id == 0 || statement_id > __s0_buffer_len(CheckedStatementRec, store.control.statements) { return Ok(walk) }
    let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_id - 1)
    var inner = try lower_move_walk_expression(d, store, walk, loop_at, statement.expression)
    var events = inner.events
    if statement.kind == 1 || statement.kind == 2 || statement.kind == 10 {
        if statement.binding != 0 && statement.binding <= __s0_buffer_len(LocalRec, store.locals) {
            events = try __s0_buffer_append(LowerMoveEventRec, d, events, LowerMoveEventRec(binding: statement.binding, expression: 0, is_definition: 1))
        }
    }
    if statement.kind == 3 && statement.place != 0 && statement.place <= __s0_buffer_len(CheckedPlaceRec, store.control.places) {
        let place = __s0_buffer_get(CheckedPlaceRec, store.control.places, statement.place - 1)
        if place.index != 0 { inner = try lower_move_walk_expression(d, store, LowerMoveWalkRec(events: events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals), loop_at, place.index)
            events = inner.events }
        if place.root != 0 && place.root <= __s0_buffer_len(LocalRec, store.locals) {
            events = try __s0_buffer_append(LowerMoveEventRec, d, events, LowerMoveEventRec(binding: place.root, expression: 0, is_definition: 1))
        }
    }
    if statement.kind == 11 || statement.kind == 12 {
        // break and continue leave the body before any statement after them,
        // so a rebuilding definition may not run on every pass.
        return Ok(LowerMoveWalkRec(events: events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals + 1))
    }
    if statement.kind == 6 { return lower_move_walk_block(d, store, LowerMoveWalkRec(events: events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals), loop_at, statement.body) }
    if statement.kind == 7 {
        // Either arm may run, so a definition inside one cannot be relied on.
        var walked = LowerMoveWalkRec(events: events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals + 1)
        walked = try lower_move_walk_block(d, store, walked, loop_at, statement.body)
        walked = try lower_move_walk_block(d, store, walked, loop_at, statement.alternative)
        return Ok(walked)
    }
    if statement.kind == 8 || statement.kind == 9 {
        let opened = try __s0_buffer_append(LowerMoveLoopRec, d, inner.loops, LowerMoveLoopRec(first_event: __s0_buffer_len(LowerMoveEventRec, events), end_event: 0, parent: loop_at, conditional: 0))
        var loops_now = opened
        let loop_now = __s0_buffer_len(LowerMoveLoopRec, loops_now)
        // A nested loop runs zero or more times, so the enclosing loop counts
        // it as a skipping construct; the counter starts one above the base so
        // the loop's own body is measured without it.
        let base_conditionals = inner.conditionals
        var walked = LowerMoveWalkRec(events: events, excluded: inner.excluded, loops: loops_now, conditionals: base_conditionals + 1)
        walked = try lower_move_walk_block(d, store, walked, loop_now, statement.body)
        let rec = __s0_buffer_get(LowerMoveLoopRec, loops_now, loop_now - 1)
        var conditional: U64 = 0
        if walked.conditionals != base_conditionals + 1 { conditional = 1 }
        __s0_buffer_set(LowerMoveLoopRec, loops_now, loop_now - 1, LowerMoveLoopRec(first_event: rec.first_event, end_event: __s0_buffer_len(LowerMoveEventRec, walked.events), parent: rec.parent, conditional: conditional))
        if statement.kind == 9 && statement.binding != 0 && statement.binding <= __s0_buffer_len(LocalRec, store.locals) {
            // The loop binding is defined fresh each iteration after the
            // sequence read; the sequence read precedes the loop range, so
            // a dead sequence still moves into the element copies.
            walked = LowerMoveWalkRec(events: try __s0_buffer_append(LowerMoveEventRec, d, walked.events, LowerMoveEventRec(binding: statement.binding, expression: 0, is_definition: 1)), excluded: walked.excluded, loops: walked.loops, conditionals: walked.conditionals)
        }
        return Ok(walked)
    }
    return Ok(LowerMoveWalkRec(events: events, excluded: inner.excluded, loops: inner.loops, conditionals: inner.conditionals))
}

// lower_move_innermost_loop returns one plus the index of the innermost loop
// span containing the event, or zero when the event is outside every loop.
// Loops are recorded on entry, so the last containing span is the innermost.
fn lower_move_innermost_loop(loops: __s0_Buffer(LowerMoveLoopRec), index: U64) -> U64 {
    var found: U64 = 0
    var loop_at: U64 = 0
    while loop_at < __s0_buffer_len(LowerMoveLoopRec, loops) {
        let span_loop = __s0_buffer_get(LowerMoveLoopRec, loops, loop_at)
        if span_loop.first_event <= index && index < span_loop.end_event { found = loop_at + 1 }
        loop_at = loop_at + 1
    }
    return found
}

// lower_move_loop_reason decides one read inside a loop body. The body repeats,
// so a moved read must be re-established by a definition before it runs again:
// the next access to the binding inside the body has to be a definition, and
// the body has to be straight-line code, because a conditional, a match or try
// expression, or a nested loop could skip that definition and leave the next
// iteration reading storage the callee owns. `a = rebuild(a)` is that shape; a
// body that only reads the binding, or that reads it again after the rebuild,
// keeps copying.
fn lower_move_loop_reason(events: __s0_Buffer(LowerMoveEventRec), loops: __s0_Buffer(LowerMoveLoopRec), loop_span: U64, index: U64, binding: U64) -> U64 {
    let span_loop = __s0_buffer_get(LowerMoveLoopRec, loops, loop_span - 1)
    if span_loop.conditional != 0 { return 4 }
    var later = index + 1
    while later < span_loop.end_event {
        let next_event = __s0_buffer_get(LowerMoveEventRec, events, later)
        if next_event.binding == binding {
            if next_event.is_definition != 0 { return 0 }
            return 1
        }
        later = later + 1
    }
    return 4
}

// lower_move_analyze fills the shared move plan for one concrete function
// instance: parameters and captured bindings are excluded up front, the
// statement tree is walked once in lowering order, and each read event is
// decided against the binding's later accesses and enclosing loops.
fn lower_move_analyze(d: Domain, store: CheckStore, owner: U64, root_block: U64, plan: LowerMovePlan) -> Result(LowerMovePlan, __s0_Error) {
    let locals_count = __s0_buffer_len(LocalRec, store.locals)
    // Exclusions are per binding and permanent: parameters (7) share the
    // caller's storage, captured bindings (2) are snapshot by closures, and
    // view receivers (3) keep an implicit later reference. The flags live in
    // the plan's reusable buffer, cleared here in place for this function;
    // entries beyond the local count hold stale flags that no guard reads.
    var excluded = plan.excluded_scratch
    var clear_at: U64 = 0
    while clear_at < locals_count {
        __s0_buffer_set(U64, excluded, clear_at, 0)
        clear_at = clear_at + 1
    }
    var at: U64 = 0
    while at < locals_count {
        let local = __s0_buffer_get(LocalRec, store.locals, at)
        if local.owner == owner && local.kind == 1 { __s0_buffer_set(U64, excluded, at, 7) }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(ClosureCaptureRec, store.closures.captures) {
        let capture = __s0_buffer_get(ClosureCaptureRec, store.closures.captures, at)
        if capture.local != 0 && capture.local <= locals_count && __s0_buffer_get(U64, excluded, capture.local - 1) == 0 {
            __s0_buffer_set(U64, excluded, capture.local - 1, 2)
        }
        at = at + 1
    }
    let events = try __s0_buffer_new(LowerMoveEventRec, d)
    let loops = try __s0_buffer_new(LowerMoveLoopRec, d)
    let walked = try lower_move_walk_block(d, store, LowerMoveWalkRec(events: events, excluded: excluded, loops: loops, conditionals: 0), 0, root_block)
    var movable = plan.movable
    var reasons = plan.reasons
    var index: U64 = 0
    while index < __s0_buffer_len(LowerMoveEventRec, walked.events) {
        let event = __s0_buffer_get(LowerMoveEventRec, walked.events, index)
        if event.is_definition == 0 && event.binding != 0 && event.binding <= locals_count {
            var reason = __s0_buffer_get(U64, walked.excluded, event.binding - 1)
            if reason == 0 {
                // A read inside a loop body is decided against that body
                // alone: the definition that re-establishes the binding also
                // makes every access after the loop a read of the new value.
                // Reads outside every loop keep the plain later-use rule.
                let loop_span = lower_move_innermost_loop(walked.loops, index)
                if loop_span != 0 {
                    reason = lower_move_loop_reason(walked.events, walked.loops, loop_span, index, event.binding)
                } else {
                    var blocked: U64 = 0
                    var later: U64 = index + 1
                    while later < __s0_buffer_len(LowerMoveEventRec, walked.events) {
                        let next_event = __s0_buffer_get(LowerMoveEventRec, walked.events, later)
                        if next_event.binding == event.binding && next_event.is_definition == 0 { blocked = 1 }
                        later = later + 1
                    }
                    if blocked != 0 { reason = 1 }
                }
                if reason != 0 || event.expression == 0 || event.expression > __s0_buffer_len(U64, movable) {
                    if reason == 0 { reason = 1 }
                    if event.expression != 0 && event.expression <= __s0_buffer_len(U64, reasons) { __s0_buffer_set(U64, reasons, event.expression - 1, reason) }
                } else {
                    __s0_buffer_set(U64, movable, event.expression - 1, 1)
                }
            } else {
                if event.expression != 0 && event.expression <= __s0_buffer_len(U64, reasons) { __s0_buffer_set(U64, reasons, event.expression - 1, reason) }
            }
        }
        index = index + 1
    }
    return Ok(LowerMovePlan(movable: movable, reasons: reasons, excluded_scratch: excluded))
}

// lower_move_or_copy applies the D023 rule at one value-semantics copy
// site. When the copied value comes from a binding read that the move plan
// marks movable, and the site's placement domain equals the source's (the
// target never outlives the source storage), the value transfers instead
// of copying; every other site copies and appends a report record.
// receiver_source_expression returns the receiver child expression of a
// builtin call, which copy sites use as their potential move source.
fn receiver_source_expression(expression: CheckedExprRec, store: CheckStore) -> U64 {
    if expression.child_count == 0 || expression.first_child == 0 || expression.first_child > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return 0 }
    return __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
}

fn lower_move_or_copy(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, checked_type: U64, value: U64, source_expression: U64, reason_override: U64) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    let vec = try lower_mir_type_contains_vec(d, typ.state, typ.id)
    if !vec.value { return Ok(LowerStep(state: vec.state, id: value)) }
    // A value-semantics read copies only storage that copy_to_domain can
    // carry. An affine owner nested inside a vec-bearing type (for example
    // Table(Vec(T))) is borrowed, never copied or moved by a plain read:
    // copying it would forge a second generational-identity handle, which
    // backend verification refuses. Such reads pass through unchanged, the
    // same way a plain Table(T) read already does.
    if !(try lower_mir_type_copy_relocatable(d, vec.state.mir, typ.id)) { return Ok(LowerStep(state: vec.state, id: value)) }
    var current = vec.state
    var binding: U64 = 0
    if source_expression != 0 && source_expression <= __s0_buffer_len(CheckedExprRec, store.expressions) {
        let read = __s0_buffer_get(CheckedExprRec, store.expressions, source_expression - 1)
        if (read.kind == 1 || read.kind == 5 || read.kind == 22) && read.parameter_use != 0 && read.parameter_use <= __s0_buffer_len(LocalRec, store.locals) { binding = read.parameter_use }
    }
    var movable = false
    if binding != 0 && source_expression <= __s0_buffer_len(U64, current.moves.movable) && __s0_buffer_get(U64, current.moves.movable, source_expression - 1) == 1 { movable = true }
    if movable {
        let source_domain = lower_storage_domain_value(current, store, owner, source_expression)
        let target_domain = lower_storage_domain_value(current, store, owner, expression_id)
        if source_domain != 0 && target_domain != 0 && source_domain == target_domain {
            return Ok(LowerStep(state: current, id: value))
        }
    }
    var reason: U64 = reason_override
    if reason == 0 {
        if binding == 0 {
            reason = 5
        } else {
            if movable { reason = 6 } else {
                reason = 1
                if source_expression != 0 && source_expression <= __s0_buffer_len(U64, current.moves.reasons) { reason = __s0_buffer_get(U64, current.moves.reasons, source_expression - 1) }
                if reason == 0 { reason = 1 }
            }
        }
    }
    if expression_id != 0 && expression_id <= __s0_buffer_len(CheckedExprRec, store.expressions) {
        let site = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
        if site.syntax != 0 && site.syntax <= __s0_buffer_len(CheckedSpanRec, spans) {
            let span = __s0_buffer_get(CheckedSpanRec, spans, site.syntax - 1)
            current = try lower_add_copy_report(d, current, owner, span.source, span.start, span.end, binding, reason)
        }
    }
    return lower_copy_if_vec(d, source_state, store, current, owner, function, block, expression_id, checked_type, value)
}

fn lower_copy_result_storage(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, checked_type: U64, value: U64) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    if !typ.state.has_storage || !(try lower_mir_type_copy_relocatable(d, typ.state.mir, typ.id)) { return Ok(LowerStep(state: typ.state, id: value)) }
    let domain = lower_storage_domain_value(typ.state, store, owner, expression_id)
    if domain == 0 || domain != lower_result_domain_value(typ.state, store, owner) { return Ok(LowerStep(state: lower_invalid(typ.state), id: 0)) }
    let result = try lower_add_typed_result(d, typ.state, function, block, typ.id)
    let copied = try lower_add_instr(d, result.state, function, block, mir_op_copy_to_domain(), result.id, 0, 0, domain, value, 0, "")
    return Ok(LowerStep(state: copied.state, id: result.id))
}

fn lower_retain_exit_value(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, checked_type: U64, value: U64) -> Result(LowerStep, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, checked_type)
    if !typ.state.has_storage || !(try lower_mir_type_copy_relocatable(d, typ.state.mir, typ.id)) { return Ok(LowerStep(state: typ.state, id: value)) }
    let domain = lower_result_domain_value(typ.state, store, owner)
    if domain == 0 { return Ok(LowerStep(state: lower_invalid(typ.state), id: 0)) }
    let result = try lower_add_typed_result(d, typ.state, function, block, typ.id)
    let copied = try lower_add_instr(d, result.state, function, block, mir_op_copy_to_domain(), result.id, 0, 0, domain, value, 0, "")
    return Ok(LowerStep(state: copied.state, id: result.id))
}

fn lower_binding_expression(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, copy: Bool) -> Result(LowerStep, __s0_Error) {
    let binding = lower_binding_lookup(state, expression.parameter_use)
    if binding.binding == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    var current = state
    // A kind-22 read transfers an affine owner out of its binding. When the
    // binding carries a cleanup registration, the entry must disarm on every
    // transfer path so scope exit cannot release a moved owner.
    if expression.kind == 22 {
        let release = lower_release_lookup(state, expression.parameter_use)
        if release != 0 {
            let disarmed = try lower_add_instr(d, current, function, block, mir_op_cleanup_disarm(), 0, 0, 0, release, 0, 0, "")
            current = disarmed.state
        }
    }
    var value = binding.mir_id
    if binding.parameter != 1 {
        // The place, its type, and the load all extend `current`, not the
        // entry `state`: a transfer above has already appended the disarm to
        // this function's MIR, and rebuilding from the entry state would
        // silently drop it and free a moved owner at scope exit.
        var place: MirBuildStep = MirBuildStep(store: current.mir, id: 0)
        if binding.parameter == 2 || binding.parameter == 3 { place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: binding.mir_id)) } else {
            place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        }
        let local = __s0_buffer_get(LocalRec, store.locals, expression.parameter_use - 1)
        let local_type = try lower_local_type(d, source_state, store, lower_with_mir(current, place.store), owner, expression.parameter_use, local)
        let result = try lower_add_typed_result(d, local_type.state, function, block, local_type.id)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_load(), result.id, place.id, 0, 0, 0, 0, "")
        current = instr.state
        value = result.id
    }
    if copy { return lower_move_or_copy(d, source_state, spans, store, current, owner, function, block, expression_id, expression.checked_type, value, expression_id, 0) }
    return Ok(LowerStep(state: current, id: value))
}

// The storage a borrowed call argument names. An immutable receiver whose
// argument is not a plain binding stages the value into a temporary, so the
// callee observes an ordinary value. A mut argument must name the caller's
// storage instead: a binding, or a chain of field projections over one, since
// the callee's writes have to reach the value the caller keeps.
type LowerArgumentPlaceRec {
    state: LowerState
    place: U64
    root: U64
}

// A field or index place chain for a mut argument. Each level projects from
// the place below it, and the root names the caller's binding, so `self.inner`
// passes the field of the receiver and `rows[i]` passes the element rather
// than a temporary copy of either.
fn lower_mut_argument_place(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, environment: U64, panic_block: U64) -> Result(LowerArgumentPlaceRec, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.kind == 1 || expression.kind == 5 {
        let mapped = lower_binding_lookup(state, expression.parameter_use)
        if mapped.binding == 0 || mapped.parameter == 1 { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
        var place: MirBuildStep = MirBuildStep(store: state.mir, id: 0)
        if mapped.parameter == 0 { place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: mapped.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0)) } else {
            place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: mapped.mir_id))
        }
        return Ok(LowerArgumentPlaceRec(state: lower_with_mir(state, place.store), place: place.id, root: expression.parameter_use))
    }
    if expression.kind == 21 {
        if expression.child_count != 1 || expression.first_child == 0 || expression.first_child > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
        if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
        let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let base = try lower_mut_argument_place(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block)
        if !base.state.valid { return Ok(base) }
        let field = __s0_buffer_get(DeclTypeUseRec, store.uses, expression.parameter_use - 1)
        if field.role != 1 { return Ok(LowerArgumentPlaceRec(state: lower_invalid(base.state), place: 0, root: 0)) }
        let named = try mir_append_name(d, base.state.mir, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
        let field_place = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: base.place, field_start: named.start, field_end: named.end, deref_value: 0))
        return Ok(LowerArgumentPlaceRec(state: lower_with_mir(base.state, field_place.store), place: field_place.id, root: base.root))
    }
    if expression.kind != 19 { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
    if expression.child_count != 2 || expression.first_child == 0 || expression.first_child + 1 > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
    let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let index_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let base_expression = __s0_buffer_get(CheckedExprRec, store.expressions, base_id - 1)
    let base = try lower_mut_argument_place(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block)
    if !base.state.valid { return Ok(base) }
    let base_is_root = base_expression.kind == 1 || base_expression.kind == 5
    let indexed = try lower_index_place(d, source_state, spans, store, base.state, owner, function, block, MirBuildStep(store: base.state.mir, id: base.place), base_expression.checked_type, index_id, base.root, base_is_root, environment, panic_block)
    return Ok(LowerArgumentPlaceRec(state: indexed.state, place: indexed.id, root: base.root))
}

// A by-value binding is an SSA value with no place: a function parameter or
// a match-case payload. A `mut` argument needs a mutable place, so
// materialize a local once and rebind the name to it. Rebinding keeps later
// reads and writes on the same storage the callee borrows; a deref of the SSA
// value would point at the value, not a reference.
fn lower_mut_binding_place(d: Domain, source_state: State, store: CheckStore, state: LowerState, function: U64, block: U64, expression: CheckedExprRec, mapped: LowerBindingMapRec) -> Result(LowerArgumentPlaceRec, __s0_Error) {
    let typ = try lower_type(d, source_state, store, state, expression.checked_type)
    if typ.id == 0 { return Ok(LowerArgumentPlaceRec(state: lower_invalid(typ.state), place: 0, root: 0)) }
    let slot_name = try lower_decimal_name(d, "__alder_mut_binding_", lower_local_count(typ.state.mir, function))
    let slot = try mir_add_local(d, typ.state.mir, function, lower_local_count(typ.state.mir, function), slot_name, typ.id)
    let place = try mir_add_place(d, slot.store, MirPlaceRec(function: function, kind: mir_place_local(), local: slot.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
    let stored = try lower_add_instr(d, lower_with_mir(typ.state, place.store), function, block, mir_op_store(), 0, place.id, 0, mapped.mir_id, 0, 0, "")
    let rebind = try __s0_buffer_append(LowerBindingMapRec, d, stored.state.bindings, LowerBindingMapRec(binding: mapped.binding, mir_id: slot.id, parameter: 0, initial: 0))
    return Ok(LowerArgumentPlaceRec(state: lower_with_bindings(stored.state, rebind), place: place.id, root: expression.parameter_use))
}

fn lower_argument_place(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, environment: U64, panic_block: U64, borrow_kind: U64) -> Result(LowerArgumentPlaceRec, __s0_Error) {
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if borrow_kind == 2 && (expression.kind == 21 || expression.kind == 19) { return lower_mut_argument_place(d, source_state, spans, store, state, owner, function, block, expression_id, environment, panic_block) }
    let mapped = lower_binding_lookup(state, expression.parameter_use)
    let named = expression.kind == 1 || expression.kind == 5
    if borrow_kind == 2 && named && mapped.binding != 0 && mapped.parameter == 1 {
        return lower_mut_binding_place(d, source_state, store, state, function, block, expression, mapped)
    }
    let plain = named && mapped.binding != 0 && mapped.parameter != 1
    // A mut parameter may borrow a whole local, a field place (handled
    // above), or a forwarded mut parameter's deref; a newly formed view is
    // staged into a local first. An immutable parameter only stages.
    let stage = (borrow_kind == 1 && !plain) || (borrow_kind == 2 && !named)
    if stage {
        let staged = try lower_expression(d, source_state, spans, store, state, owner, function, block, expression_id, environment, panic_block)
        let ordinary = try lower_type(d, source_state, store, staged.state, expression.checked_type)
        let slot_name = try lower_decimal_name(d, "__alder_borrow_temp_", lower_local_count(ordinary.state.mir, function))
        let slot = try mir_add_local(d, ordinary.state.mir, function, lower_local_count(ordinary.state.mir, function), slot_name, ordinary.id)
        let place = try mir_add_place(d, slot.store, MirPlaceRec(function: function, kind: mir_place_local(), local: slot.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        let stored = try lower_add_instr(d, lower_with_mir(ordinary.state, place.store), function, block, mir_op_store(), 0, place.id, 0, staged.id, 0, 0, "")
        return Ok(LowerArgumentPlaceRec(state: stored.state, place: place.id, root: 0))
    }
    if !named || mapped.binding == 0 { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
    if borrow_kind == 1 && mapped.parameter == 1 { return Ok(LowerArgumentPlaceRec(state: lower_invalid(state), place: 0, root: 0)) }
    var place: MirBuildStep = MirBuildStep(store: state.mir, id: 0)
    if mapped.parameter == 0 { place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: mapped.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0)) } else {
        place = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: mapped.mir_id))
    }
    return Ok(LowerArgumentPlaceRec(state: lower_with_mir(state, place.store), place: place.id, root: expression.parameter_use))
}

fn lower_direct_expression(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.kind == 1 || expression.kind == 5 || expression.kind == 22 { return lower_binding_expression(d, source_state, spans, store, state, owner, function, block, expression_id, expression, false) }
    return lower_expression(d, source_state, spans, store, state, owner, function, block, expression_id, environment, panic_block)
}

// A mutable view of a field or element place reads the collection header from
// that place instead of copying the enclosing value. Lowering the receiver as
// an ordinary expression would spill and copy the whole record, and a Vec
// copy would clone its storage, so the view would write into a detached copy.
fn lower_place_view_receiver(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, place_id: U64, checked_type: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    let placed = try lower_receiver_place(d, source_state, spans, store, state, owner, function, block, place_id, environment, panic_block)
    if !placed.state.valid || placed.id == 0 { return Ok(LowerStep(state: lower_invalid(placed.state), id: 0)) }
    let lowered = try lower_type(d, source_state, store, placed.state, checked_type)
    if !lowered.state.valid { return Ok(LowerStep(state: lower_invalid(lowered.state), id: 0)) }
    let loaded = try lower_add_typed_result(d, lowered.state, function, block, lowered.id)
    let load = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, placed.id, 0, 0, 0, 0, "")
    return Ok(LowerStep(state: load.state, id: loaded.id))
}

// Model shapes for the ordered-collection builtins: statics take no runtime
// children, methods take the receiver plus their runtime operands, and the
// result types must match the receiver's key/value element types.
fn lower_ordered_model_valid(store: CheckStore, annotation: CallAnnotationRec, expression: CheckedExprRec) -> Bool {
    let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
    var expected_count: U64 = 1
    if annotation.builtin == 30 || annotation.builtin == 37 { expected_count = 0 }
    if annotation.builtin == 31 { expected_count = 3 }
    if annotation.builtin == 32 || annotation.builtin == 33 || annotation.builtin == 38 || annotation.builtin == 39 || annotation.builtin == 40 { expected_count = 2 }
    if annotation.builtin == 43 { expected_count = 0 }
    // Builtin 44 (indirect call) children are the callee value plus one child
    // per function parameter; the count is pinned to the function type's
    // arg_count inside the 44 branch below, so the fixed table above does not
    // apply.
    if annotation.builtin != 44 && expression.child_count != expected_count { return false }
    if annotation.builtin == 43 { return annotation.target != 0 && __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1).kind == 25 }
    if annotation.builtin == 44 {
        // The callee child carries the function type; the annotation's own
        // type is the call result.
        let callee_type = lower_builtin_child_type(store, expression, 0)
        if callee_type == 0 { return false }
        let fn_checked = __s0_buffer_get(CheckedTypeRec, store.types, callee_type - 1)
        if fn_checked.kind != 25 || fn_checked.arg_count < 2 { return false }
        if expression.child_count != fn_checked.arg_count - 1 { return false }
        let param_total = fn_checked.arg_count - 2
        return annotation.checked_type == __s0_buffer_get(U64, store.type_args, fn_checked.first_arg - 1 + param_total)
    }
    if annotation.builtin == 30 { return result.kind == 23 && result.arg_count == 2 }
    if annotation.builtin == 37 { return result.kind == 24 && result.arg_count == 1 }
    let receiver_type = lower_builtin_child_type(store, expression, 0)
    if receiver_type == 0 { return false }
    let receiver = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
    if receiver.kind == 23 {
        let key = __s0_buffer_get(U64, store.type_args, receiver.first_arg - 1)
        let value = __s0_buffer_get(U64, store.type_args, receiver.first_arg)
        if annotation.builtin == 31 { return lower_builtin_child_type(store, expression, 1) == key && lower_builtin_child_type(store, expression, 2) == value && result.kind == 1 && result.target == 1 }
        if annotation.builtin == 32 { return lower_builtin_child_type(store, expression, 1) == key && result.kind == 9 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == value }
        if annotation.builtin == 33 { return lower_builtin_child_type(store, expression, 1) == key && result.kind == 1 && result.target == 1 }
        if annotation.builtin == 34 { return result.kind == 1 && result.target == 9 }
        if annotation.builtin == 35 { return result.kind == 17 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == key }
        if annotation.builtin == 36 { return result.kind == 17 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == value }
        return false
    }
    if receiver.kind == 24 {
        let element = __s0_buffer_get(U64, store.type_args, receiver.first_arg - 1)
        if annotation.builtin == 38 { return lower_builtin_child_type(store, expression, 1) == element && result.kind == 1 && result.target == 1 }
        if annotation.builtin == 39 { return lower_builtin_child_type(store, expression, 1) == element && result.kind == 1 && result.target == 1 }
        if annotation.builtin == 40 { return lower_builtin_child_type(store, expression, 1) == element && result.kind == 1 && result.target == 1 }
        if annotation.builtin == 41 { return result.kind == 1 && result.target == 9 }
        if annotation.builtin == 42 { return result.kind == 17 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == element }
    }
    return false
}

// Leaf comparison of two values: Bool through paired branches, unsigned
// integers through int.eq, String/Bytes through str.eq over the two values,
// and aggregate payloads spilled into fresh locals so the structural walk
// recurses field-wise or by tag and payload.
fn lower_m75_leaf_equal(d: Domain, source_state: State, store: CheckStore, state: LowerState, function: U64, block: U64, checked_type: U64, left: U64, right: U64, equal_block: U64, different_block: U64) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 7 || checked.kind == 9 || checked.kind == 10 {
        // Aggregate or builtin-variant payload: spill both values into
        // fresh locals and continue the structural walk on the spilled
        // places.
        let agg_type = try lower_type(d, source_state, store, state, checked_type)
        let left_ordinal = lower_local_count(agg_type.state.mir, function)
        let left_place = try lower_helper_local_place(d, agg_type.state, function, left_ordinal, try lower_decimal_name(d, "m75_key_nested_left", left_ordinal), agg_type.id)
        let left_store = try lower_add_instr(d, left_place.state, function, block, mir_op_store(), 0, left_place.id, 0, left, 0, 0, "")
        let right_place = try lower_helper_local_place(d, left_store.state, function, left_ordinal + 1, try lower_decimal_name(d, "m75_key_nested_right", left_ordinal), agg_type.id)
        let right_store = try lower_add_instr(d, right_place.state, function, block, mir_op_store(), 0, right_place.id, 0, right, 0, 0, "")
        return lower_m75_key_equal(d, source_state, store, right_store.state, checked_type, function, block, left_place.id, right_place.id, equal_block, different_block)
    }
    if checked.target == 1 {
        let left_true = try lower_add_block(d, state, function, "bb_m75_key_left_true")
        let left_false = try lower_add_block(d, left_true.state, function, "bb_m75_key_left_false")
        var current = try lower_branch(d, left_false.state, function, block, left, left_true.id, left_false.id)
        current = try lower_branch(d, current, function, left_true.id, right, equal_block, different_block)
        return lower_branch(d, current, function, left_false.id, right, different_block, equal_block)
    }
    let result = try lower_add_typed_result(d, state, function, block, mir_type_bool())
    var op = mir_op_int_eq()
    if checked.kind == 2 || checked.kind == 14 { op = mir_op_str_eq() }
    let compared = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, left, right, 0, "")
    return lower_branch(d, compared.state, function, block, result.id, equal_block, different_block)
}

// Builtin Option and Result equality: the implicit none/some or ok/err
// variants compare tag-first through two switches, exactly like the
// declared-enum walk, but the variant table comes from the builtin kind
// instead of a variant use list; payload variants continue through the
// leaf comparison.
fn lower_m75_builtin_variant_equal(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, function: U64, block: U64, left_place: U64, right_place: U64, equal_block: U64, different_block: U64) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.first_arg == 0 || checked.arg_count == 0 { return Ok(lower_invalid(state)) }
    var current = state
    var left_blocks = try __s0_buffer_new(U64, d)
    var ordinal: U64 = 0
    while ordinal < 2 {
        let variant_block = try lower_add_block(d, current, function, "bb_m75_key_variant")
        current = variant_block.state
        left_blocks = try __s0_buffer_append(U64, d, left_blocks, variant_block.id)
        ordinal = ordinal + 1
    }
    let key_type = try lower_type(d, source_state, store, current, checked_type)
    if !key_type.state.valid { return Ok(key_type.state) }
    let left_loaded = try lower_helper_load(d, key_type.state, function, block, left_place, key_type.id)
    let right_loaded = try lower_helper_load(d, left_loaded.state, function, block, right_place, key_type.id)
    current = right_loaded.state
    let source_block = lower_open_block(current.mir, function, block)
    let left_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: left_loaded.id, target: 0, then_block: 0, else_block: 0))
    current = lower_with_mir(current, left_term.store)
    var left_payloads = try __s0_buffer_new(U64, d)
    ordinal = 0
    while ordinal < 2 {
        let name = try lower_builtin_variant_name(d, checked.kind, ordinal)
        let payload_checked = lower_builtin_variant_payload(store, checked, ordinal)
        var payload: U64 = 0
        if payload_checked != 0 {
            let payload_type = try lower_type(d, source_state, store, current, payload_checked)
            if !payload_type.state.valid { return Ok(payload_type.state) }
            let left_payload = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "m75_key_left_payload", source_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), source_block, ordinal + 1)
            current = lower_with_mir(payload_type.state, left_payload.store)
            payload = left_payload.id
        }
        left_payloads = try __s0_buffer_append(U64, d, left_payloads, payload)
        let case = try lower_add_switch_case(d, current, left_term.id, ordinal, name, payload, __s0_buffer_get(U64, left_blocks, ordinal))
        current = case.state
        ordinal = ordinal + 1
    }
    ordinal = 0
    while ordinal < 2 {
        let name = try lower_builtin_variant_name(d, checked.kind, ordinal)
        let left_block = __s0_buffer_get(U64, left_blocks, ordinal)
        let compare = try lower_add_block(d, current, function, "bb_m75_key_payload")
        current = compare.state
        let right_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: left_block, kind: mir_term_switch(), value: right_loaded.id, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, right_term.store)
        let payload_checked = lower_builtin_variant_payload(store, checked, ordinal)
        if payload_checked == 0 {
            let matching = try lower_add_switch_case(d, current, right_term.id, 0, name, 0, compare.id)
            let fallback = try lower_add_switch_case(d, matching.state, right_term.id, 1, "", 0, different_block)
            current = fallback.state
            current = try lower_jump(d, current, function, compare.id, equal_block)
        } else {
            let payload_type = try lower_type(d, source_state, store, current, payload_checked)
            if !payload_type.state.valid { return Ok(payload_type.state) }
            let right_payload = try mir_add_value(d, current.mir, function, try lower_decimal_name(d, "m75_key_right_payload", left_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), left_block, 1)
            current = lower_with_mir(current, right_payload.store)
            let matching = try lower_add_switch_case(d, current, right_term.id, 0, name, right_payload.id, compare.id)
            let fallback = try lower_add_switch_case(d, matching.state, right_term.id, 1, "", 0, different_block)
            current = fallback.state
            current = try lower_m75_leaf_equal(d, source_state, store, current, function, compare.id, payload_checked, __s0_buffer_get(U64, left_payloads, ordinal), right_payload.id, equal_block, different_block)
        }
        ordinal = ordinal + 1
    }
    return Ok(current)
}

// Implicit variant tag order: none then some for option, ok then err for
// result, matching the MIR verifier's case names.
fn lower_builtin_variant_name(d: Domain, kind: U64, ordinal: U64) -> Result(__s0_String, __s0_Error) {
    if kind == 9 {
        if ordinal == 0 { return Ok("none") }
        return Ok("some")
    }
    if ordinal == 0 { return Ok("ok") }
    return Ok("err")
}

// The checked payload type of one implicit variant, or zero when the
// variant carries none.
fn lower_builtin_variant_payload(store: CheckStore, checked: CheckedTypeRec, ordinal: U64) -> U64 {
    if checked.kind == 9 {
        if ordinal == 0 { return 0 }
        return __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    }
    if ordinal == 0 { return __s0_buffer_get(U64, store.type_args, checked.first_arg - 1) }
    return __s0_buffer_get(U64, store.type_args, checked.first_arg)
}

// Structural key comparison over parallel place chains. The left place is a
// local stored once before the scan loop; the right place is the entry's key
// field or the element itself. Everything stays place-based so the scan loop
// body never stores a reference-provenance value into a local across the
// backedge; enum payload compares use the switch-case payload values, and
// aggregate payloads spill into fresh locals so the walk recurses.
fn lower_m75_key_equal(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, function: U64, block: U64, left_place: U64, right_place: U64, equal_block: U64, different_block: U64) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 || checked.kind == 2 || checked.kind == 14 {
        let left_type = try lower_type(d, source_state, store, state, checked_type)
        let left_loaded = try lower_helper_load(d, left_type.state, function, block, left_place, left_type.id)
        let right_type = try lower_type(d, source_state, store, left_loaded.state, checked_type)
        let right_loaded = try lower_helper_load(d, right_type.state, function, block, right_place, right_type.id)
        return lower_m75_leaf_equal(d, source_state, store, right_loaded.state, function, block, checked_type, left_loaded.id, right_loaded.id, equal_block, different_block)
    }
    if checked.kind == 9 || checked.kind == 10 {
        return lower_m75_builtin_variant_equal(d, source_state, store, state, checked_type, function, block, left_place, right_place, equal_block, different_block)
    }
    if checked.kind != 7 { return Ok(lower_invalid(state)) }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
    if symbol.kind == 2 {
        var current = state
        var active = block
        var next_block = equal_block
        let field_count = lower_use_count(store, checked.target, 1)
        var ordinal: U64 = 0
        while ordinal < field_count {
            let use_id = lower_use_by_role(store, checked.target, 1, ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            let field_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
            let field_type = try lower_type(d, source_state, store, current, field_checked)
            let name = try lower_source_word(d, source_state, use.source, use.name_start, use.name_end)
            let left_field = try lower_helper_field_place(d, field_type.state, function, left_place, name)
            let right_field = try lower_helper_field_place(d, left_field.state, function, right_place, name)
            current = right_field.state
            if ordinal + 1 < field_count {
                let next = try lower_add_block(d, current, function, "bb_m75_key_field")
                next_block = next.id
                current = next.state
            } else { next_block = equal_block }
            current = try lower_m75_key_equal(d, source_state, store, current, field_checked, function, active, left_field.id, right_field.id, next_block, different_block)
            active = next_block
            ordinal = ordinal + 1
        }
        if field_count == 0 { return lower_jump(d, current, function, active, equal_block) }
        return Ok(current)
    }
    if symbol.kind == 3 {
        var current = state
        var left_blocks = try __s0_buffer_new(U64, d)
        let variant_count = lower_use_count(store, checked.target, 2)
        var ordinal: U64 = 0
        while ordinal < variant_count {
            let variant_block = try lower_add_block(d, current, function, "bb_m75_key_variant")
            current = variant_block.state
            left_blocks = try __s0_buffer_append(U64, d, left_blocks, variant_block.id)
            ordinal = ordinal + 1
        }
        let key_type = try lower_type(d, source_state, store, current, checked_type)
        current = key_type.state
        let left_loaded = try lower_helper_load(d, current, function, block, left_place, key_type.id)
        let right_loaded = try lower_helper_load(d, left_loaded.state, function, block, right_place, key_type.id)
        current = right_loaded.state
        let source_block = lower_open_block(current.mir, function, block)
        let left_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: left_loaded.id, target: 0, then_block: 0, else_block: 0))
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
                let left_payload = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "m75_key_left_payload", source_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), source_block, ordinal + 1)
                current = lower_with_mir(payload_type.state, left_payload.store)
                payload = left_payload.id
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
            let compare = try lower_add_block(d, current, function, "bb_m75_key_payload")
            current = compare.state
            let right_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: left_block, kind: mir_term_switch(), value: right_loaded.id, target: 0, then_block: 0, else_block: 0))
            current = lower_with_mir(current, right_term.store)
            if use.checked_type == 0 {
                let matching = try lower_add_switch_case(d, current, right_term.id, 0, name, 0, compare.id)
                let fallback = try lower_add_switch_case(d, matching.state, right_term.id, 1, "", 0, different_block)
                current = fallback.state
                current = try lower_jump(d, current, function, compare.id, equal_block)
            } else {
                let payload_checked = lower_bound_checked_type(store, use.checked_type, checked.target, checked_type)
                let payload_type = try lower_type(d, source_state, store, current, payload_checked)
                let right_payload = try mir_add_value(d, current.mir, function, try lower_decimal_name(d, "m75_key_right_payload", left_block * 100 + ordinal), payload_type.id, mir_value_def_switch_case(), left_block, 1)
                current = lower_with_mir(current, right_payload.store)
                let matching = try lower_add_switch_case(d, current, right_term.id, 0, name, right_payload.id, compare.id)
                let fallback = try lower_add_switch_case(d, matching.state, right_term.id, 1, "", 0, different_block)
                current = fallback.state
                current = try lower_m75_leaf_equal(d, source_state, store, current, function, compare.id, payload_checked, __s0_buffer_get(U64, left_payloads, ordinal), right_payload.id, equal_block, different_block)
            }
            ordinal = ordinal + 1
        }
        return Ok(current)
    }
    return Ok(lower_invalid(state))
}

// Linear scan over the receiver's entry vector. entry_block enters the scan;
// found_block receives the matching index as its block parameter.
// missing_block takes no parameter (callers recompute the length when they
// need it), so the exhausting branch edge carries no value. Only the U64
// index crosses the backedge, and structural key compares stay place-based.
fn lower_m75_scan(d: Domain, source_state: State, store: CheckStore, state: LowerState, key_checked: U64, map_entries: U64, entry_type: U64, storage_type: U64, receiver_value: U64, function: U64, entry_block: U64, key_value: U64, key_place: U64, found_block: U64, missing_block: U64, panic_block: U64) -> Result(LowerState, __s0_Error) {
    let head = try lower_add_block(d, state, function, "bb_m75_scan")
    let index = try mir_add_block_param(d, head.state.mir, function, head.id, 0, try lower_decimal_name(d, "__m75_scan_", head.id), mir_type_u64())
    var current = lower_with_mir(head.state, index.store)
    let zero = try lower_int_value_seq(d, source_state, store, current, function, entry_block, 0)
    current = try lower_jump_value(d, zero.state, function, entry_block, head.id, zero.id)
    let length = try lower_add_typed_result(d, current, function, head.id, mir_type_u64())
    let length_instr = try lower_add_instr(d, length.state, function, head.id, mir_op_vec_len(), length.id, 0, 0, receiver_value, 0, 0, "")
    current = length_instr.state
    let more = try lower_add_typed_result(d, current, function, head.id, mir_type_bool())
    let compared = try lower_add_instr(d, more.state, function, head.id, mir_op_int_lt(), more.id, 0, 0, index.id, length.id, 0, "")
    current = compared.state
    let body = try lower_add_block(d, current, function, "bb_m75_scan_body")
    current = try lower_branch(d, body.state, function, head.id, more.id, body.id, missing_block)
    let storage = try lower_add_typed_result(d, current, function, body.id, storage_type)
    let storage_instr = try lower_add_instr(d, storage.state, function, body.id, mir_op_vec_storage(), storage.id, 0, 0, receiver_value, 0, 0, "")
    current = storage_instr.state
    let entry_ref = try lower_add_typed_result(d, current, function, body.id, storage_type)
    let entry_index = try lower_add_instr(d, entry_ref.state, function, body.id, mir_op_slice_index_checked(), entry_ref.id, 0, 0, storage.id, index.id, panic_block, "")
    current = entry_index.state
    let entry_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: entry_ref.id))
    current = lower_with_mir(current, entry_place.store)
    let equal_block = try lower_add_block(d, current, function, "bb_m75_scan_hit")
    let different_block = try lower_add_block(d, equal_block.state, function, "bb_m75_scan_next")
    if key_place != 0 {
        // Structural key: compare through parallel place chains. The searched
        // key sits in a local stored once before the loop; the entry side
        // walks the key field of the deref'd entry (or the element itself).
        var right_place = entry_place.id
        if map_entries != 0 {
            let key_type = try lower_type(d, source_state, store, different_block.state, key_checked)
            let key_field = try lower_helper_field_place(d, key_type.state, function, entry_place.id, "key")
            right_place = key_field.id
            current = key_field.state
        } else { current = different_block.state }
        current = try lower_m75_key_equal(d, source_state, store, current, key_checked, function, body.id, key_place, right_place, equal_block.id, different_block.id)
    } else {
        let key_type = try lower_type(d, source_state, store, different_block.state, key_checked)
        var scan_key: U64 = 0
        if map_entries != 0 {
            let key_field = try lower_helper_field_place(d, key_type.state, function, entry_place.id, "key")
            current = key_field.state
            let key_loaded = try lower_helper_load(d, current, function, body.id, key_field.id, key_type.id)
            current = key_loaded.state
            scan_key = key_loaded.id
        } else {
            let element = try lower_add_typed_result(d, key_type.state, function, body.id, entry_type)
            let element_instr = try lower_add_instr(d, element.state, function, body.id, mir_op_load(), element.id, entry_place.id, 0, 0, 0, 0, "")
            current = element_instr.state
            scan_key = element.id
        }
        current = try lower_m75_leaf_equal(d, source_state, store, current, function, body.id, key_checked, key_value, scan_key, equal_block.id, different_block.id)
    }
    current = try lower_jump_value(d, current, function, equal_block.id, found_block, index.id)
    let one = try lower_int_value_seq(d, source_state, store, current, function, different_block.id, 1)
    let next = try lower_add_typed_result(d, one.state, function, different_block.id, mir_type_u64())
    let added = try lower_add_instr(d, next.state, function, different_block.id, mir_op_int_add_checked(), next.id, 0, 0, index.id, one.id, panic_block, "")
    return lower_jump_value(d, added.state, function, different_block.id, head.id, next.id)
}

// Float operands are the kind-1 checked primitives with the F32 or F64
// target; lowering reads the operand expression's checked type directly.
fn lower_float_operand(store: CheckStore, checked_type: U64) -> Bool {
    if checked_type == 0 || checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let operand = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    return operand.kind == 1 && (operand.target == 10 || operand.target == 11)
}

// Float binary expressions lower to the plain IEEE-754 arithmetic and
// comparison operations: the result carries the operand type and none of
// them can fail, so the dispatch ignores the panic edge exactly like the
// plain integer comparisons do.
fn lower_float_binary_op(store: CheckStore, operand_checked: U64, operator: U64) -> U64 {
    if !lower_float_operand(store, operand_checked) { return 0 }
    if operator == 3 { return mir_op_float_add() }
    if operator == 4 { return mir_op_float_sub() }
    if operator == 5 { return mir_op_float_mul() }
    if operator == 6 { return mir_op_float_div() }
    if operator == 10 { return mir_op_float_eq() }
    if operator == 11 { return mir_op_float_ne() }
    if operator == 12 { return mir_op_float_lt() }
    if operator == 13 { return mir_op_float_le() }
    if operator == 14 { return mir_op_float_gt() }
    if operator == 15 { return mir_op_float_ge() }
    return 0
}

// Reports whether an Eq operand lowers through the structural walk instead
// of a primitive comparison: String, Bytes, Bool, records, enums, generic
// applications over Eq components, and builtin Option and Result do, while
// plain integers and floats keep their dedicated lowering.
fn lower_structural_operand(store: CheckStore, operand_checked: U64) -> Bool {
    if operand_checked == 0 || operand_checked > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let operand = __s0_buffer_get(CheckedTypeRec, store.types, operand_checked - 1)
    if operand.kind == 2 || operand.kind == 14 { return true }
    if operand.kind == 7 { return true }
    if operand.kind == 1 && operand.target == 1 { return true }
    return lower_structural_builtin_variant_operand(operand)
}

// Builtin Option and Result operands walk the implicit variant comparison;
// the checker only accepts the operators when every component is in the
// structural domain.
fn lower_structural_builtin_variant_operand(operand: CheckedTypeRec) -> Bool {
    return operand.kind == 9 || operand.kind == 10
}

// `==` and `!=` over the structural Eq operands that do not already lower to
// one primitive comparison: String and Bytes compare byte-wise and records
// and enums decompose into their Eq components. Each operand expression
// lowers first and spills into a fresh local in the block where its value is
// defined, so operands whose result is a join parameter (ordered-collection
// builtins and matches produce them) still dominate the comparison;
// lower_m75_key_equal then selects between the two join constants. Operator
// 11 swaps which arm produces true.
fn lower_structural_equal_exprs(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression: CheckedExprRec, left_id: U64, right_id: U64, operand_checked: U64, expression_id: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    let equal_block = try lower_add_block(d, state, function, "bb_eq_equal")
    let different_block = try lower_add_block(d, equal_block.state, function, "bb_eq_different")
    let join = try lower_add_block(d, different_block.state, function, "bb_eq_join")
    let result_type = try lower_type(d, source_state, store, join.state, expression.checked_type)
    let param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, try lower_decimal_name(d, "__alder_eq_join", join.id), result_type.id)
    let operand = try lower_type(d, source_state, store, lower_with_mir(result_type.state, param.store), operand_checked)
    let left_ordinal = lower_local_count(operand.state.mir, function)
    let left_place = try lower_helper_local_place(d, operand.state, function, left_ordinal, try lower_decimal_name(d, "eq_left", expression_id), operand.id)
    let right_place = try lower_helper_local_place(d, left_place.state, function, left_ordinal + 1, try lower_decimal_name(d, "eq_right", expression_id), operand.id)
    let left = try lower_expression(d, source_state, spans, store, right_place.state, owner, function, block, left_id, environment, panic_block)
    let left_block = lower_open_block(left.state.mir, function, block)
    let left_store = try lower_add_instr(d, left.state, function, left_block, mir_op_store(), 0, left_place.id, 0, left.id, 0, 0, "")
    let right = try lower_expression(d, source_state, spans, store, left_store.state, owner, function, left_block, right_id, environment, panic_block)
    let right_block = lower_open_block(right.state.mir, function, left_block)
    let right_store = try lower_add_instr(d, right.state, function, right_block, mir_op_store(), 0, right_place.id, 0, right.id, 0, 0, "")
    let walked = try lower_m75_key_equal(d, source_state, store, right_store.state, operand_checked, function, right_block, left_place.id, right_place.id, equal_block.id, different_block.id)
    let bool_suffix = __s0_buffer_len(MirConstRec, walked.mir.constants) + 1
    var equal_truth: U64 = 1
    var different_truth: U64 = 0
    if expression.operator == 11 { equal_truth = 0
        different_truth = 1 }
    let equal_const = try lower_bool_value(d, source_state, store, walked, function, equal_block.id, expression.checked_type, equal_truth, "lit.eq_arm_a_", bool_suffix)
    let equal_jump = try lower_jump_value(d, equal_const.state, function, equal_block.id, join.id, equal_const.id)
    let different_const = try lower_bool_value(d, source_state, store, equal_jump, function, different_block.id, expression.checked_type, different_truth, "lit.eq_arm_b_", bool_suffix)
    let different_jump = try lower_jump_value(d, different_const.state, function, different_block.id, join.id, different_const.id)
    return Ok(LowerStep(state: different_jump, id: param.id))
}

// Append one entry to the receiver vector with geometric growth, the M7.1
// push convention, store the rebuilt record back into the receiver binding
// so the collection keeps value semantics, and jump to join_block with
// result_value from the final block.
fn lower_m75_append(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, active: U64, expression_id: U64, place: U64, receiver_value: U64, vector_type: U64, storage_type: U64, pushed_value: U64, result_value: U64, join_block: U64, environment: U64, panic_block: U64) -> Result(LowerState, __s0_Error) {
    var current = state
    let length = try lower_add_typed_result(d, current, function, active, mir_type_u64())
    let length_instr = try lower_add_instr(d, length.state, function, active, mir_op_vec_len(), length.id, 0, 0, receiver_value, 0, 0, "")
    current = length_instr.state
    let capacity = try lower_add_typed_result(d, current, function, active, mir_type_u64())
    let capacity_instr = try lower_add_instr(d, capacity.state, function, active, mir_op_vec_capacity(), capacity.id, 0, 0, receiver_value, 0, 0, "")
    current = capacity_instr.state
    let full = try lower_add_typed_result(d, current, function, active, mir_type_bool())
    let compared = try lower_add_instr(d, full.state, function, active, mir_op_int_eq(), full.id, 0, 0, length.id, capacity.id, 0, "")
    current = compared.state
    let grow = try lower_add_block(d, current, function, "bb_m75_grow")
    let keep = try lower_add_block(d, grow.state, function, "bb_m75_keep")
    let ready = try lower_add_block(d, keep.state, function, "bb_m75_ready")
    let ready_value = try mir_add_block_param(d, ready.state.mir, function, ready.id, 0, try lower_decimal_name(d, "__m75_vec_", ready.id), vector_type)
    current = try lower_branch(d, lower_with_mir(ready.state, ready_value.store), function, active, full.id, grow.id, keep.id)
    let zero = try lower_int_value_seq(d, source_state, store, current, function, grow.id, 0)
    let is_zero = try lower_add_typed_result(d, zero.state, function, grow.id, mir_type_bool())
    let zero_cmp = try lower_add_instr(d, is_zero.state, function, grow.id, mir_op_int_eq(), is_zero.id, 0, 0, capacity.id, zero.id, 0, "")
    current = zero_cmp.state
    let initial = try lower_add_block(d, current, function, "bb_m75_initial_capacity")
    let doubled_block = try lower_add_block(d, initial.state, function, "bb_m75_double_capacity")
    let capacity_join = try lower_add_block(d, doubled_block.state, function, "bb_m75_capacity")
    let capacity_value = try mir_add_block_param(d, capacity_join.state.mir, function, capacity_join.id, 0, try lower_decimal_name(d, "__m75_capacity_", capacity_join.id), mir_type_u64())
    current = try lower_branch(d, lower_with_mir(capacity_join.state, capacity_value.store), function, grow.id, is_zero.id, initial.id, doubled_block.id)
    let four = try lower_int_value_seq(d, source_state, store, current, function, initial.id, 4)
    current = try lower_jump_value(d, four.state, function, initial.id, capacity_join.id, four.id)
    let two = try lower_int_value_seq(d, source_state, store, current, function, doubled_block.id, 2)
    let doubled = try lower_add_typed_result(d, two.state, function, doubled_block.id, mir_type_u64())
    let multiplied = try lower_add_instr(d, doubled.state, function, doubled_block.id, mir_op_int_mul_checked(), doubled.id, 0, 0, capacity.id, two.id, panic_block, "")
    current = try lower_jump_value(d, multiplied.state, function, doubled_block.id, capacity_join.id, doubled.id)
    var domain = lower_place_owner_domain(current, store, owner, place)
    if domain == 0 { domain = lower_storage_domain_value(current, store, owner, expression_id) }
    if domain == 0 { return Ok(lower_invalid(current)) }
    let grown = try lower_add_typed_result(d, current, function, capacity_join.id, vector_type)
    let grown_instr = try lower_add_instr_three(d, grown.state, function, capacity_join.id, mir_op_vec_grow_checked(), grown.id, 0, receiver_value, domain, capacity_value.id, panic_block)
    current = try lower_jump_value(d, grown_instr.state, function, capacity_join.id, ready.id, grown.id)
    current = try lower_jump_value(d, current, function, keep.id, ready.id, receiver_value)
    let storage = try lower_add_typed_result(d, current, function, ready.id, storage_type)
    let storage_instr = try lower_add_instr(d, storage.state, function, ready.id, mir_op_vec_storage(), storage.id, 0, 0, ready_value.id, 0, 0, "")
    current = storage_instr.state
    let target = try lower_add_typed_result(d, current, function, ready.id, storage_type)
    let indexed = try lower_add_instr(d, target.state, function, ready.id, mir_op_slice_index_checked(), target.id, 0, 0, storage.id, length.id, panic_block, "")
    current = indexed.state
    let target_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: target.id))
    let stored = try lower_add_instr(d, lower_with_mir(current, target_place.store), function, ready.id, mir_op_store(), 0, target_place.id, 0, pushed_value, 0, 0, "")
    current = stored.state
    let one = try lower_int_value_seq(d, source_state, store, current, function, ready.id, 1)
    let next_length = try lower_add_typed_result(d, one.state, function, ready.id, mir_type_u64())
    let added = try lower_add_instr(d, next_length.state, function, ready.id, mir_op_int_add_checked(), next_length.id, 0, 0, length.id, one.id, panic_block, "")
    current = added.state
    let next_capacity = try lower_add_typed_result(d, current, function, ready.id, mir_type_u64())
    let next_capacity_instr = try lower_add_instr(d, next_capacity.state, function, ready.id, mir_op_vec_capacity(), next_capacity.id, 0, 0, ready_value.id, 0, 0, "")
    current = next_capacity_instr.state
    let updated = try lower_add_typed_result(d, current, function, ready.id, vector_type)
    let built = try lower_add_instr_three(d, updated.state, function, ready.id, mir_op_vec_construct_checked(), updated.id, 0, storage.id, next_length.id, next_capacity.id, panic_block)
    current = built.state
    let write_place = try lower_receiver_place(d, source_state, spans, store, current, owner, function, ready.id, place, environment, panic_block)
    if write_place.id == 0 { return Ok(lower_invalid(write_place.state)) }
    let saved = try lower_add_instr(d, lower_with_mir(current, write_place.state.mir), function, ready.id, mir_op_store(), 0, write_place.id, 0, updated.id, 0, 0, "")
    return lower_jump_value(d, saved.state, function, ready.id, join_block, result_value)
}

fn callee_checked_type(store: CheckStore, expression: CheckedExprRec) -> U64 {
    if expression.first_child == 0 || expression.child_count == 0 { return 0 }
    let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    return __s0_buffer_get(CheckedExprRec, store.expressions, child - 1).checked_type
}

fn lower_m75_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if annotation.builtin == 43 {
        // Function reference. In the storage model the target carries a
        // hidden leading domain parameter, exactly like a direct call: the
        // value's environment carries the current function's domain, and
        // the marker records that the callee's leading parameter is that
        // hidden domain so the erased function type covers only the
        // declared parameters.
        let target = lower_owner_lookup(state.owners, annotation.target)
        if target == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        var env_value: U64 = 0
        var marker: U64 = 0
        if state.has_storage && lower_closure_site_for(store, annotation.target) == 0 && !lower_owner_aliases_domain(source_state, store, annotation.target) {
            // Capture this function's own domain parameter — the ancestor
            // domain the caller provided — so the value cannot outlive its
            // environment. A main that aliases the domain has no hidden
            // parameter; its first parameter is the domain itself.
            env_value = lower_keyed_domain_value(state, lower_env_domain_key(owner))
            if env_value == 0 { env_value = lower_domain_value(state, store, owner) }
            if env_value == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
            marker = mir_fn_value_domain_marker()
        }
        let fn_type = try lower_type(d, source_state, store, state, expression.checked_type)
        let result = try lower_add_typed_result(d, fn_type.state, function, block, fn_type.id)
        let made = try lower_add_instr(d, result.state, function, block, mir_op_fn_value(), result.id, 0, marker, env_value, 0, target, "")
        return Ok(LowerStep(state: made.state, id: result.id))
    }
    if annotation.builtin == 44 {
        // Indirect call: call.value through the callee's function value. The
        // checked function type marks borrowed parameters; each one lowers
        // as a safe_mut borrow plus its owner-domain operand, the same pair a
        // direct call passes.
        let fn_checked_id = callee_checked_type(store, expression)
        if fn_checked_id == 0 || fn_checked_id > __s0_buffer_len(CheckedTypeRec, store.types) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let fn_checked = __s0_buffer_get(CheckedTypeRec, store.types, fn_checked_id - 1)
        if fn_checked.kind != 25 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let callee_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let callee = try lower_expression(d, source_state, spans, store, state, owner, function, block, callee_id, environment, panic_block)
        var current = callee.state
        var active = lower_open_block(current.mir, function, block)
        var args = try __s0_buffer_new(U64, d)
        var owners = try __s0_buffer_new(U64, d)
        var param_bit: U64 = 1
        var ordinal: U64 = 1
        while ordinal < expression.child_count {
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
            if child_id == 0 || child_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let checked_child = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
            var arg_value: U64 = 0
            var arg_owner: U64 = 0
            if (fn_checked.target / param_bit) % 2 == 1 {
                let placed = try lower_argument_place(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block, 2)
                if !placed.state.valid { return Ok(LowerStep(state: placed.state, id: 0)) }
                current = placed.state
                active = lower_open_block(current.mir, function, active)
                let ordinary = try lower_type(d, source_state, store, current, checked_child.checked_type)
                if !ordinary.state.valid { return Ok(LowerStep(state: ordinary.state, id: 0)) }
                current = ordinary.state
                let empty = try __s0_buffer_new(U64, d)
                let reference = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), ordinary.id, 0, 0, empty, 0)
                current = lower_with_mir(current, reference.store)
                let value = try mir_add_value(d, current.mir, function, try lower_result_name(d, current.mir, function, ""), reference.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(current.mir, function, active) + 1)
                current = lower_with_mir(current, value.store)
                let borrowed = try lower_add_instr(d, current, function, active, mir_op_borrow_mut(), value.id, placed.place, 0, 0, 0, 0, "")
                current = borrowed.state
                arg_value = value.id
                if current.has_storage {
                    arg_owner = lower_binding_owner_domain(current, store, owner, placed.root)
                    if arg_owner == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                }
            } else {
                let child = try lower_expression(d, source_state, spans, store, current, owner, function, active, child_id, environment, panic_block)
                current = child.state
                arg_value = child.id
            }
            active = lower_open_block(current.mir, function, active)
            args = try __s0_buffer_append(U64, d, args, arg_value)
            owners = try __s0_buffer_append(U64, d, owners, arg_owner)
            param_bit = param_bit * 2
            ordinal = ordinal + 1
        }
        let fn_type = try lower_type(d, source_state, store, current, fn_checked_id)
        current = fn_type.state
        let result_type = try lower_type(d, source_state, store, current, expression.checked_type)
        current = result_type.state
        var result: U64 = 0
        var current2 = current
        if result_type.id != mir_type_unit() {
            let value = try lower_add_result(d, current, function, active, expression.checked_type, source_state, store)
            current2 = value.state
            result = value.id
        }
        let call = try lower_add_instr(d, current2, function, active, mir_op_call_value(), result, 0, 0, callee.id, 0, 0, "")
        var wired = call.state
        var argument_ordinal: U64 = 0
        ordinal = 0
        while ordinal < __s0_buffer_len(U64, args) {
            wired = try lower_add_instr_operand(d, wired, call.id, argument_ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
            argument_ordinal = argument_ordinal + 1
            let owner_arg = __s0_buffer_get(U64, owners, ordinal)
            if owner_arg != 0 {
                wired = try lower_add_instr_operand(d, wired, call.id, argument_ordinal, owner_arg, mir_operand_instruction(), "")
                argument_ordinal = argument_ordinal + 1
            }
            ordinal = ordinal + 1
        }
        return Ok(LowerStep(state: wired, id: result))
    }
    if annotation.builtin == 30 || annotation.builtin == 37 {
        let vector = try lower_type(d, source_state, store, state, expression.checked_type)
        let result = try lower_add_typed_result(d, vector.state, function, block, vector.id)
        let created = try lower_add_instr(d, result.state, function, block, mir_op_vec_new(), result.id, 0, vector.id, 0, 0, 0, "")
        return Ok(LowerStep(state: created.state, id: result.id))
    }
    let receiver_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver_expression = __s0_buffer_get(CheckedExprRec, store.expressions, receiver_id - 1)
    let receiver_checked = __s0_buffer_get(CheckedTypeRec, store.types, receiver_expression.checked_type - 1)
    // The receiver loads directly (no deep copy): mutation happens through
    // its storage in place and the rebuilt record is stored back, the push
    // convention.
    var active = block
    let receiver = try lower_direct_expression(d, source_state, spans, store, state, owner, function, active, receiver_id, environment, panic_block)
    var current = receiver.state
    active = lower_open_block(current.mir, function, active)
    var first_arg: U64 = 0
    var second_arg: U64 = 0
    var ordinal: U64 = 1
    while ordinal < expression.child_count {
        let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
        let child = try lower_expression(d, source_state, spans, store, current, owner, function, active, child_id, environment, panic_block)
        current = child.state
        active = lower_open_block(current.mir, function, active)
        if ordinal == 1 { first_arg = child.id }
        if ordinal == 2 { second_arg = child.id }
        ordinal = ordinal + 1
    }
    if annotation.builtin == 34 || annotation.builtin == 41 {
        let result = try lower_add_typed_result(d, current, function, active, mir_type_u64())
        let length = try lower_add_instr(d, result.state, function, active, mir_op_vec_len(), result.id, 0, 0, receiver.id, 0, 0, "")
        return Ok(LowerStep(state: length.state, id: result.id))
    }
    // Shared representation facts: the entry element type (the synthesized
    // {key, value} aggregate for maps, the element itself for sets) and its
    // storage reference type.
    let vector = try lower_type(d, source_state, store, current, receiver_expression.checked_type)
    var entry_type = __s0_buffer_get(MirTypeRec, vector.state.mir.types, vector.id - 1).elem
    var key_checked: U64 = 0
    var value_checked: U64 = 0
    var map_entries: U64 = 0
    if receiver_checked.kind == 23 {
        map_entries = 1
        key_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
        value_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg)
    } else {
        key_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
        value_checked = key_checked
    }
    if map_entries == 0 {
        let element = try lower_type(d, source_state, store, vector.state, key_checked)
        entry_type = element.id
        current = element.state
    } else { current = vector.state }
    let empty = try __s0_buffer_new(U64, d)
    let storage_type = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), entry_type, 0, 0, empty, 0)
    current = lower_with_mir(current, storage_type.store)
    // Structural keys compare through place chains: park the searched key in
    // a local once, before any loop, so the scan body never stores into a
    // local inside the cycle. keys/values/items build fresh vectors and do
    // not scan.
    var key_place: U64 = 0
    var scanning: U64 = 1
    if annotation.builtin == 35 || annotation.builtin == 36 || annotation.builtin == 42 { scanning = 0 }
    let key_head = __s0_buffer_get(CheckedTypeRec, store.types, key_checked - 1)
    if scanning != 0 && key_head.kind == 7 {
        let key_type = try lower_type(d, source_state, store, current, key_checked)
        let local_ordinal = lower_local_count(key_type.state.mir, function)
        let key_local = try lower_helper_local_place(d, key_type.state, function, local_ordinal, try lower_decimal_name(d, "m75_key_", local_ordinal), key_type.id)
        let key_stored = try lower_add_instr(d, key_local.state, function, active, mir_op_store(), 0, key_local.id, 0, first_arg, 0, 0, "")
        current = key_stored.state
        key_place = key_local.id
    }
    if annotation.builtin == 31 || annotation.builtin == 38 {
        let join = try lower_add_block(d, current, function, "bb_m75_insert_join")
        let result_value = try mir_add_block_param(d, join.state.mir, function, join.id, 0, try lower_decimal_name(d, "__m75_insert_", join.id), mir_type_bool())
        current = lower_with_mir(join.state, result_value.store)
        let found = try lower_add_block(d, current, function, "bb_m75_insert_hit")
        let found_index = try mir_add_block_param(d, found.state.mir, function, found.id, 0, try lower_decimal_name(d, "__m75_hit_", found.id), mir_type_u64())
        current = lower_with_mir(found.state, found_index.store)
        let missing = try lower_add_block(d, current, function, "bb_m75_insert_miss")
        current = missing.state
        var pushed = second_arg
        if map_entries != 0 {
            let entry = try lower_helper_construct_two(d, current, function, active, entry_type, "key", first_arg, "value", second_arg)
            current = entry.state
            pushed = entry.id
        } else { pushed = first_arg }
        current = try lower_m75_scan(d, source_state, store, current, key_checked, map_entries, entry_type, storage_type.type_id, receiver.id, function, active, first_arg, key_place, found.id, missing.id, panic_block)
        if map_entries != 0 {
            // Replace the value in place; the entry keeps its position.
            let storage = try lower_add_typed_result(d, current, function, found.id, storage_type.type_id)
            let storage_instr = try lower_add_instr(d, storage.state, function, found.id, mir_op_vec_storage(), storage.id, 0, 0, receiver.id, 0, 0, "")
            current = storage_instr.state
            let entry_ref = try lower_add_typed_result(d, current, function, found.id, storage_type.type_id)
            let entry_index = try lower_add_instr(d, entry_ref.state, function, found.id, mir_op_slice_index_checked(), entry_ref.id, 0, 0, storage.id, found_index.id, panic_block, "")
            current = entry_index.state
            let entry_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: entry_ref.id))
            current = lower_with_mir(current, entry_place.store)
            let value_type = try lower_type(d, source_state, store, current, value_checked)
            let value_place = try lower_helper_field_place(d, value_type.state, function, entry_place.id, "value")
            current = value_place.state
            let stored = try lower_add_instr(d, current, function, found.id, mir_op_store(), 0, value_place.id, 0, second_arg, 0, 0, "")
            current = stored.state
        }
        let replaced = try lower_helper_bool(d, current, function, found.id, 0, expression_id * 16)
        current = try lower_jump_value(d, replaced.state, function, found.id, join.id, replaced.id)
        let inserted = try lower_helper_bool(d, current, function, missing.id, 1, expression_id * 16 + 1)
        current = try lower_m75_append(d, source_state, spans, store, inserted.state, owner, function, missing.id, expression_id, annotation.place, receiver.id, vector.id, storage_type.type_id, pushed, inserted.id, join.id, environment, panic_block)
        return Ok(LowerStep(state: current, id: result_value.id))
    }
    if annotation.builtin == 32 {
        let join = try lower_add_block(d, current, function, "bb_m75_get_join")
        let option = try lower_type(d, source_state, store, join.state, expression.checked_type)
        let result_value = try mir_add_block_param(d, option.state.mir, function, join.id, 0, try lower_decimal_name(d, "__m75_get_", join.id), option.id)
        current = lower_with_mir(option.state, result_value.store)
        let found = try lower_add_block(d, current, function, "bb_m75_get_hit")
        let found_index = try mir_add_block_param(d, found.state.mir, function, found.id, 0, try lower_decimal_name(d, "__m75_hit_", found.id), mir_type_u64())
        current = lower_with_mir(found.state, found_index.store)
        let missing = try lower_add_block(d, current, function, "bb_m75_get_miss")
        current = missing.state
        current = try lower_m75_scan(d, source_state, store, current, key_checked, map_entries, entry_type, storage_type.type_id, receiver.id, function, active, first_arg, key_place, found.id, missing.id, panic_block)
        let storage = try lower_add_typed_result(d, current, function, found.id, storage_type.type_id)
        let storage_instr = try lower_add_instr(d, storage.state, function, found.id, mir_op_vec_storage(), storage.id, 0, 0, receiver.id, 0, 0, "")
        current = storage_instr.state
        let entry_ref = try lower_add_typed_result(d, current, function, found.id, storage_type.type_id)
        let entry_index = try lower_add_instr(d, entry_ref.state, function, found.id, mir_op_slice_index_checked(), entry_ref.id, 0, 0, storage.id, found_index.id, panic_block, "")
        current = entry_index.state
        let entry_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: entry_ref.id))
        current = lower_with_mir(current, entry_place.store)
        let value_type = try lower_type(d, source_state, store, current, value_checked)
        let value_place = try lower_helper_field_place(d, value_type.state, function, entry_place.id, "value")
        current = value_place.state
        let value_loaded = try lower_helper_load(d, current, function, found.id, value_place.id, value_type.id)
        current = value_loaded.state
        let copied = try lower_move_or_copy(d, source_state, spans, store, current, owner, function, found.id, expression_id, value_checked, value_loaded.id, receiver_source_expression(expression, store), 0)
        current = copied.state
        let some = try lower_add_typed_result(d, current, function, found.id, option.id)
        let made_some = try lower_add_instr(d, some.state, function, found.id, mir_op_enum_construct(), some.id, 0, option.id, copied.id, 0, 0, "some")
        current = try lower_jump_value(d, made_some.state, function, found.id, join.id, some.id)
        let none = try lower_add_typed_result(d, current, function, missing.id, option.id)
        let made_none = try lower_add_instr(d, none.state, function, missing.id, mir_op_enum_construct(), none.id, 0, option.id, 0, 0, 0, "none")
        current = try lower_jump_value(d, made_none.state, function, missing.id, join.id, none.id)
        return Ok(LowerStep(state: current, id: result_value.id))
    }
    if annotation.builtin == 39 {
        let join = try lower_add_block(d, current, function, "bb_m75_contains_join")
        let result_value = try mir_add_block_param(d, join.state.mir, function, join.id, 0, try lower_decimal_name(d, "__m75_contains_", join.id), mir_type_bool())
        current = lower_with_mir(join.state, result_value.store)
        let found = try lower_add_block(d, current, function, "bb_m75_contains_hit")
        let found_index = try mir_add_block_param(d, found.state.mir, function, found.id, 0, try lower_decimal_name(d, "__m75_hit_", found.id), mir_type_u64())
        current = lower_with_mir(found.state, found_index.store)
        let missing = try lower_add_block(d, current, function, "bb_m75_contains_miss")
        current = missing.state
        current = try lower_m75_scan(d, source_state, store, current, key_checked, map_entries, entry_type, storage_type.type_id, receiver.id, function, active, first_arg, key_place, found.id, missing.id, panic_block)
        let truth = try lower_helper_bool(d, current, function, found.id, 1, expression_id * 16 + 2)
        current = try lower_jump_value(d, truth.state, function, found.id, join.id, truth.id)
        let falsity = try lower_helper_bool(d, current, function, missing.id, 0, expression_id * 16 + 3)
        current = try lower_jump_value(d, falsity.state, function, missing.id, join.id, falsity.id)
        return Ok(LowerStep(state: current, id: result_value.id))
    }
    if annotation.builtin == 33 || annotation.builtin == 40 {
        let join = try lower_add_block(d, current, function, "bb_m75_remove_join")
        let result_value = try mir_add_block_param(d, join.state.mir, function, join.id, 0, try lower_decimal_name(d, "__m75_remove_", join.id), mir_type_bool())
        current = lower_with_mir(join.state, result_value.store)
        let found = try lower_add_block(d, current, function, "bb_m75_remove_hit")
        let found_index = try mir_add_block_param(d, found.state.mir, function, found.id, 0, try lower_decimal_name(d, "__m75_hit_", found.id), mir_type_u64())
        current = lower_with_mir(found.state, found_index.store)
        let missing = try lower_add_block(d, current, function, "bb_m75_remove_miss")
        current = missing.state
        current = try lower_m75_scan(d, source_state, store, current, key_checked, map_entries, entry_type, storage_type.type_id, receiver.id, function, active, first_arg, key_place, found.id, missing.id, panic_block)
        // Missing: nothing to remove.
        let falsity = try lower_helper_bool(d, current, function, missing.id, 0, expression_id * 16 + 4)
        current = try lower_jump_value(d, falsity.state, function, missing.id, join.id, falsity.id)
        // Found: compact the entries in place, preserving order, then store
        // the shortened vector back into the receiver binding. Whole entries
        // move, and the value type is provenance-free, so the loop-carried
        // load is plain bits under the phase-6 rule.
        let length = try lower_add_typed_result(d, current, function, found.id, mir_type_u64())
        let length_instr = try lower_add_instr(d, length.state, function, found.id, mir_op_vec_len(), length.id, 0, 0, receiver.id, 0, 0, "")
        current = length_instr.state
        let one = try lower_int_value_seq(d, source_state, store, current, function, found.id, 1)
        let last = try lower_add_typed_result(d, one.state, function, found.id, mir_type_u64())
        let last_instr = try lower_add_instr(d, last.state, function, found.id, mir_op_int_sub_checked(), last.id, 0, 0, length.id, one.id, panic_block, "")
        current = last_instr.state
        let shift = try lower_add_block(d, current, function, "bb_m75_shift")
        let at = try mir_add_block_param(d, shift.state.mir, function, shift.id, 0, try lower_decimal_name(d, "__m75_shift_", shift.id), mir_type_u64())
        current = lower_with_mir(shift.state, at.store)
        current = try lower_jump_value(d, current, function, found.id, shift.id, found_index.id)
        let more = try lower_add_typed_result(d, current, function, shift.id, mir_type_bool())
        let compared = try lower_add_instr(d, more.state, function, shift.id, mir_op_int_lt(), more.id, 0, 0, at.id, last.id, 0, "")
        current = compared.state
        let body = try lower_add_block(d, current, function, "bb_m75_shift_body")
        let compacted = try lower_add_block(d, body.state, function, "bb_m75_shift_done")
        current = try lower_branch(d, compacted.state, function, shift.id, more.id, body.id, compacted.id)
        let storage = try lower_add_typed_result(d, current, function, body.id, storage_type.type_id)
        let storage_instr = try lower_add_instr(d, storage.state, function, body.id, mir_op_vec_storage(), storage.id, 0, 0, receiver.id, 0, 0, "")
        current = storage_instr.state
        let next_one = try lower_int_value_seq(d, source_state, store, current, function, body.id, 1)
        let next_at = try lower_add_typed_result(d, next_one.state, function, body.id, mir_type_u64())
        let next_added = try lower_add_instr(d, next_at.state, function, body.id, mir_op_int_add_checked(), next_at.id, 0, 0, at.id, next_one.id, panic_block, "")
        current = next_added.state
        let source_ref = try lower_add_typed_result(d, current, function, body.id, storage_type.type_id)
        let source_index = try lower_add_instr(d, source_ref.state, function, body.id, mir_op_slice_index_checked(), source_ref.id, 0, 0, storage.id, next_at.id, panic_block, "")
        current = source_index.state
        let source_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: source_ref.id))
        current = lower_with_mir(current, source_place.store)
        let moved = try lower_helper_load(d, current, function, body.id, source_place.id, entry_type)
        current = moved.state
        let target_ref = try lower_add_typed_result(d, current, function, body.id, storage_type.type_id)
        let target_index = try lower_add_instr(d, target_ref.state, function, body.id, mir_op_slice_index_checked(), target_ref.id, 0, 0, storage.id, at.id, panic_block, "")
        current = target_index.state
        let target_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: target_ref.id))
        let stored = try lower_add_instr(d, lower_with_mir(current, target_place.store), function, body.id, mir_op_store(), 0, target_place.id, 0, moved.id, 0, 0, "")
        current = stored.state
        let step = try lower_add_typed_result(d, current, function, body.id, mir_type_u64())
        let step_added = try lower_add_instr(d, step.state, function, body.id, mir_op_int_add_checked(), step.id, 0, 0, at.id, next_one.id, panic_block, "")
        current = try lower_jump_value(d, step_added.state, function, body.id, shift.id, step.id)
        let capacity = try lower_add_typed_result(d, current, function, compacted.id, mir_type_u64())
        let capacity_instr = try lower_add_instr(d, capacity.state, function, compacted.id, mir_op_vec_capacity(), capacity.id, 0, 0, receiver.id, 0, 0, "")
        current = capacity_instr.state
        let storage2 = try lower_add_typed_result(d, current, function, compacted.id, storage_type.type_id)
        let storage2_instr = try lower_add_instr(d, storage2.state, function, compacted.id, mir_op_vec_storage(), storage2.id, 0, 0, receiver.id, 0, 0, "")
        current = storage2_instr.state
        let updated = try lower_add_typed_result(d, current, function, compacted.id, vector.id)
        let built = try lower_add_instr_three(d, updated.state, function, compacted.id, mir_op_vec_construct_checked(), updated.id, 0, storage2.id, last.id, capacity.id, panic_block)
        current = built.state
        let write_place = try lower_receiver_place(d, source_state, spans, store, current, owner, function, compacted.id, annotation.place, environment, panic_block)
        if write_place.id == 0 { return Ok(LowerStep(state: lower_invalid(write_place.state), id: 0)) }
        let saved = try lower_add_instr(d, lower_with_mir(current, write_place.state.mir), function, compacted.id, mir_op_store(), 0, write_place.id, 0, updated.id, 0, 0, "")
        current = saved.state
        let truth = try lower_helper_bool(d, current, function, compacted.id, 1, expression_id * 16 + 5)
        current = try lower_jump_value(d, truth.state, function, compacted.id, join.id, truth.id)
        return Ok(LowerStep(state: current, id: result_value.id))
    }
    if annotation.builtin == 35 || annotation.builtin == 36 || annotation.builtin == 42 {
        // Build a fresh vector of the key/value/element projections in the
        // expression's inferred storage domain. Projected entries are
        // provenance-free under the phase-6 rule, so loading them inside
        // the copy loop is plain bits.
        var projected_checked = key_checked
        if annotation.builtin == 36 { projected_checked = value_checked }
        let projected = try lower_type(d, source_state, store, current, projected_checked)
        current = projected.state
        let projected_empty = try __s0_buffer_new(U64, d)
        let projected_storage = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), projected.id, 0, 0, projected_empty, 0)
        current = lower_with_mir(current, projected_storage.store)
        let length = try lower_add_typed_result(d, current, function, active, mir_type_u64())
        let length_instr = try lower_add_instr(d, length.state, function, active, mir_op_vec_len(), length.id, 0, 0, receiver.id, 0, 0, "")
        current = length_instr.state
        let domain = lower_storage_domain_value(current, store, owner, expression_id)
        if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let target_storage = try lower_add_typed_result(d, current, function, active, projected_storage.type_id)
        let allocated = try lower_add_instr(d, target_storage.state, function, active, mir_op_alloc_checked(), target_storage.id, 0, projected.id, domain, length.id, panic_block, "")
        current = allocated.state
        let head = try lower_add_block(d, current, function, "bb_m75_project")
        let at = try mir_add_block_param(d, head.state.mir, function, head.id, 0, try lower_decimal_name(d, "__m75_project_", head.id), mir_type_u64())
        current = lower_with_mir(head.state, at.store)
        let zero = try lower_int_value_seq(d, source_state, store, current, function, active, 0)
        current = try lower_jump_value(d, zero.state, function, active, head.id, zero.id)
        let more = try lower_add_typed_result(d, current, function, head.id, mir_type_bool())
        let compared = try lower_add_instr(d, more.state, function, head.id, mir_op_int_lt(), more.id, 0, 0, at.id, length.id, 0, "")
        current = compared.state
        let body = try lower_add_block(d, current, function, "bb_m75_project_body")
        let done = try lower_add_block(d, body.state, function, "bb_m75_project_done")
        current = try lower_branch(d, done.state, function, head.id, more.id, body.id, done.id)
        let storage = try lower_add_typed_result(d, current, function, body.id, storage_type.type_id)
        let storage_instr = try lower_add_instr(d, storage.state, function, body.id, mir_op_vec_storage(), storage.id, 0, 0, receiver.id, 0, 0, "")
        current = storage_instr.state
        let entry_ref = try lower_add_typed_result(d, current, function, body.id, storage_type.type_id)
        let entry_index = try lower_add_instr(d, entry_ref.state, function, body.id, mir_op_slice_index_checked(), entry_ref.id, 0, 0, storage.id, at.id, panic_block, "")
        current = entry_index.state
        let entry_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: entry_ref.id))
        current = lower_with_mir(current, entry_place.store)
        var loaded_place = entry_place.id
        if map_entries != 0 {
            var field_name: __s0_String = "key"
            if annotation.builtin == 36 { field_name = "value" }
            let field = try lower_helper_field_place(d, current, function, entry_place.id, field_name)
            loaded_place = field.id
            current = field.state
        }
        let loaded = try lower_helper_load(d, current, function, body.id, loaded_place, projected.id)
        current = loaded.state
        let target_ref = try lower_add_typed_result(d, current, function, body.id, projected_storage.type_id)
        let target_index = try lower_add_instr(d, target_ref.state, function, body.id, mir_op_slice_index_checked(), target_ref.id, 0, 0, target_storage.id, at.id, panic_block, "")
        current = target_index.state
        let target_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: target_ref.id))
        let stored = try lower_add_instr(d, lower_with_mir(current, target_place.store), function, body.id, mir_op_store(), 0, target_place.id, 0, loaded.id, 0, 0, "")
        current = stored.state
        let one = try lower_int_value_seq(d, source_state, store, current, function, body.id, 1)
        let next = try lower_add_typed_result(d, one.state, function, body.id, mir_type_u64())
        let added = try lower_add_instr(d, next.state, function, body.id, mir_op_int_add_checked(), next.id, 0, 0, at.id, one.id, panic_block, "")
        current = try lower_jump_value(d, added.state, function, body.id, head.id, next.id)
        let result_vector = try lower_type(d, source_state, store, current, expression.checked_type)
        let result = try lower_add_typed_result(d, result_vector.state, function, done.id, result_vector.id)
        let built = try lower_add_instr_three(d, result.state, function, done.id, mir_op_vec_construct_checked(), result.id, 0, target_storage.id, length.id, length.id, panic_block)
        return Ok(LowerStep(state: built.state, id: result.id))
    }
    return Ok(LowerStep(state: lower_invalid(current), id: 0))
}

fn lower_array_view(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, environment: U64, panic_block: U64, mutable: Bool) -> Result(LowerStep, __s0_Error) {
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
    if checked.kind != 15 || checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let array_type = try lower_type(d, source_state, store, state, expression.checked_type)
    var current = array_type.state
    var place: MirBuildStep = MirBuildStep(store: current.mir, id: 0)
    var direct_place = false
    if expression.kind == 1 || expression.kind == 5 {
        let mapped = lower_binding_lookup(current, expression.parameter_use)
        if mapped.binding != 0 && mapped.parameter != 1 {
            if mapped.parameter == 0 { place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: mapped.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0)) } else {
                place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: mapped.mir_id))
            }
            current = lower_with_mir(current, place.store)
            direct_place = true
        }
    }
    if !direct_place {
        if mutable { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let value = try lower_direct_expression(d, source_state, spans, store, current, owner, function, block, expression_id, environment, panic_block)
        let ordinal = lower_local_count(value.state.mir, function)
        let slot = try mir_add_local(d, value.state.mir, function, ordinal, try lower_decimal_name(d, "array_view", ordinal), array_type.id)
        place = try mir_add_place(d, slot.store, MirPlaceRec(function: function, kind: mir_place_local(), local: slot.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        let stored = try lower_add_instr(d, lower_with_mir(value.state, place.store), function, block, mir_op_store(), 0, place.id, 0, value.id, 0, 0, "")
        current = stored.state
    }
    let empty = try __s0_buffer_new(U64, d)
    var reference_kind = mir_type_kind_safe_ref()
    var borrow_op = mir_op_borrow()
    if mutable { reference_kind = mir_type_kind_safe_mut()
        borrow_op = mir_op_borrow_mut() }
    let reference = try mir_intern_type(d, current.mir, reference_kind, array_type.id, 0, 0, empty, 0)
    let borrowed = try lower_add_typed_result(d, lower_with_mir(current, reference.store), function, block, reference.type_id)
    let borrow = try lower_add_instr(d, borrowed.state, function, block, borrow_op, borrowed.id, place.id, 0, 0, 0, 0, "")
    let element = try lower_type(d, source_state, store, borrow.state, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1))
    let view_type = try mir_intern_type(d, element.state.mir, mir_type_kind_slice(), element.id, 0, 0, empty, 0)
    let view = try lower_add_typed_result(d, lower_with_mir(element.state, view_type.store), function, block, view_type.type_id)
    let converted = try lower_add_instr(d, view.state, function, block, mir_op_array_as_slice(), view.id, 0, 0, borrowed.id, 0, 0, "")
    return Ok(LowerStep(state: converted.state, id: view.id))
}

fn lower_m71_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if annotation.builtin == 18 {
        let vector = try lower_type(d, source_state, store, state, expression.checked_type)
        let result = try lower_add_typed_result(d, vector.state, function, block, vector.id)
        let created = try lower_add_instr(d, result.state, function, block, mir_op_vec_new(), result.id, 0, vector.id, 0, 0, 0, "")
        return Ok(LowerStep(state: created.state, id: result.id))
    }
    if annotation.builtin == 19 {
        let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let array = try lower_expression(d, source_state, spans, store, state, owner, function, block, child_id, environment, panic_block)
        let array_expression = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
        let array_checked = __s0_buffer_get(CheckedTypeRec, store.types, array_expression.checked_type - 1)
        let vector_checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
        let element_checked = __s0_buffer_get(U64, store.type_args, vector_checked.first_arg - 1)
        let element = try lower_type(d, source_state, store, array.state, element_checked)
        let empty = try __s0_buffer_new(U64, d)
        let storage_type = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
        var current = lower_with_mir(element.state, storage_type.store)
        let zero = try lower_int_value_seq(d, source_state, store, current, function, block, 0)
        let one = try lower_int_value_seq(d, source_state, store, zero.state, function, block, 1)
        current = one.state
        var length = zero.id
        var count_at: U64 = 0
        while count_at < array_checked.target {
            let next = try lower_add_typed_result(d, current, function, block, mir_type_u64())
            let added = try lower_add_instr(d, next.state, function, block, mir_op_int_add_checked(), next.id, 0, 0, length, one.id, panic_block, "")
            current = added.state
            length = next.id
            count_at = count_at + 1
        }
        let domain = lower_storage_domain_value(current, store, owner, expression_id)
        if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let storage = try lower_add_typed_result(d, current, function, block, storage_type.type_id)
        let allocated = try lower_add_instr(d, storage.state, function, block, mir_op_alloc_checked(), storage.id, 0, element.id, domain, length, panic_block, "")
        current = allocated.state
        var index = zero.id
        count_at = 0
        while count_at < array_checked.target {
            let source_ref = try lower_add_typed_result(d, current, function, block, storage_type.type_id)
            let source_index = try lower_add_instr(d, source_ref.state, function, block, mir_op_array_index_checked(), source_ref.id, 0, 0, array.id, index, panic_block, "")
            let source_place = try mir_add_place(d, source_index.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: source_ref.id))
            let loaded = try lower_add_typed_result(d, lower_with_mir(source_index.state, source_place.store), function, block, element.id)
            let load = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, source_place.id, 0, 0, 0, 0, "")
            let copied = try lower_move_or_copy(d, source_state, spans, store, load.state, owner, function, block, expression_id, element_checked, loaded.id, __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + count_at).expression, 0)
            let target_ref = try lower_add_typed_result(d, copied.state, function, block, storage_type.type_id)
            let target_index = try lower_add_instr(d, target_ref.state, function, block, mir_op_slice_index_checked(), target_ref.id, 0, 0, storage.id, index, panic_block, "")
            let target_place = try mir_add_place(d, target_index.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: target_ref.id))
            let stored = try lower_add_instr(d, lower_with_mir(target_index.state, target_place.store), function, block, mir_op_store(), 0, target_place.id, 0, copied.id, 0, 0, "")
            let next = try lower_add_typed_result(d, stored.state, function, block, mir_type_u64())
            let added = try lower_add_instr(d, next.state, function, block, mir_op_int_add_checked(), next.id, 0, 0, index, one.id, panic_block, "")
            current = added.state
            index = next.id
            count_at = count_at + 1
        }
        let vector = try lower_type(d, source_state, store, current, expression.checked_type)
        let result = try lower_add_typed_result(d, vector.state, function, block, vector.id)
        let constructed = try lower_add_instr_three(d, result.state, function, block, mir_op_vec_construct_checked(), result.id, 0, storage.id, length, length, panic_block)
        return Ok(LowerStep(state: constructed.state, id: result.id))
    }

    let receiver_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver_expression = __s0_buffer_get(CheckedExprRec, store.expressions, receiver_id - 1)
    let receiver_checked = __s0_buffer_get(CheckedTypeRec, store.types, receiver_expression.checked_type - 1)
    var active = block
    var receiver = LowerStep(state: state, id: 0)
    if receiver_checked.kind == 15 {
        receiver = try lower_array_view(d, source_state, spans, store, state, owner, function, active, receiver_id, environment, panic_block, annotation.builtin == 24)
    } else if annotation.builtin == 24 && (receiver_expression.kind == 21 || receiver_expression.kind == 19) && annotation.place != 0 {
        receiver = try lower_place_view_receiver(d, source_state, spans, store, state, owner, function, active, annotation.place, receiver_expression.checked_type, environment, panic_block)
    } else {
        receiver = try lower_direct_expression(d, source_state, spans, store, state, owner, function, active, receiver_id, environment, panic_block)
    }
    var current = receiver.state
    active = lower_open_block(current.mir, function, active)
    var first_arg: U64 = 0
    var second_arg: U64 = 0
    var ordinal: U64 = 1
    while ordinal < expression.child_count {
        let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
        let child = try lower_expression(d, source_state, spans, store, current, owner, function, active, child_id, environment, panic_block)
        current = child.state
        active = lower_open_block(current.mir, function, active)
        if ordinal == 1 { first_arg = child.id }
        if ordinal == 2 { second_arg = child.id }
        ordinal = ordinal + 1
    }
    if annotation.builtin == 20 {
        let result = try lower_add_result(d, current, function, active, expression.checked_type, source_state, store)
        var op = mir_op_slice_len()
        if receiver_checked.kind == 17 { op = mir_op_vec_len() }
        let length = try lower_add_instr(d, result.state, function, active, op, result.id, 0, 0, receiver.id, 0, 0, "")
        return Ok(LowerStep(state: length.state, id: result.id))
    }
    if annotation.builtin == 21 {
        let length = try lower_add_typed_result(d, current, function, active, mir_type_u64())
        let length_instr = try lower_add_instr(d, length.state, function, active, mir_op_vec_len(), length.id, 0, 0, receiver.id, 0, 0, "")
        let capacity = try lower_add_typed_result(d, length_instr.state, function, active, mir_type_u64())
        let capacity_instr = try lower_add_instr(d, capacity.state, function, active, mir_op_vec_capacity(), capacity.id, 0, 0, receiver.id, 0, 0, "")
        let full = try lower_add_typed_result(d, capacity_instr.state, function, active, mir_type_bool())
        let compared = try lower_add_instr(d, full.state, function, active, mir_op_int_eq(), full.id, 0, 0, length.id, capacity.id, 0, "")
        let grow = try lower_add_block(d, compared.state, function, "bb_vec_grow")
        let keep = try lower_add_block(d, grow.state, function, "bb_vec_keep")
        let ready = try lower_add_block(d, keep.state, function, "bb_vec_ready")
        let vector = try lower_type(d, source_state, store, ready.state, receiver_expression.checked_type)
        let ready_value = try mir_add_block_param(d, vector.state.mir, function, ready.id, 0, try lower_decimal_name(d, "__m71_vec_", ready.id), vector.id)
        current = try lower_branch(d, lower_with_mir(vector.state, ready_value.store), function, active, full.id, grow.id, keep.id)

        let zero = try lower_int_value_seq(d, source_state, store, current, function, grow.id, 0)
        let is_zero = try lower_add_typed_result(d, zero.state, function, grow.id, mir_type_bool())
        let zero_cmp = try lower_add_instr(d, is_zero.state, function, grow.id, mir_op_int_eq(), is_zero.id, 0, 0, capacity.id, zero.id, 0, "")
        let initial = try lower_add_block(d, zero_cmp.state, function, "bb_vec_initial_capacity")
        let doubled_block = try lower_add_block(d, initial.state, function, "bb_vec_double_capacity")
        let capacity_join = try lower_add_block(d, doubled_block.state, function, "bb_vec_capacity")
        let capacity_value = try mir_add_block_param(d, capacity_join.state.mir, function, capacity_join.id, 0, try lower_decimal_name(d, "__m71_capacity_", capacity_join.id), mir_type_u64())
        current = try lower_branch(d, lower_with_mir(capacity_join.state, capacity_value.store), function, grow.id, is_zero.id, initial.id, doubled_block.id)
        let four = try lower_int_value_seq(d, source_state, store, current, function, initial.id, 4)
        current = try lower_jump_value(d, four.state, function, initial.id, capacity_join.id, four.id)
        let two = try lower_int_value_seq(d, source_state, store, current, function, doubled_block.id, 2)
        let doubled = try lower_add_typed_result(d, two.state, function, doubled_block.id, mir_type_u64())
        let multiplied = try lower_add_instr(d, doubled.state, function, doubled_block.id, mir_op_int_mul_checked(), doubled.id, 0, 0, capacity.id, two.id, panic_block, "")
        current = try lower_jump_value(d, multiplied.state, function, doubled_block.id, capacity_join.id, doubled.id)
        var domain = lower_place_owner_domain(current, store, owner, annotation.place)
        if domain == 0 { domain = lower_storage_domain_value(current, store, owner, expression_id) }
        if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let grown = try lower_add_typed_result(d, current, function, capacity_join.id, vector.id)
        let grown_instr = try lower_add_instr_three(d, grown.state, function, capacity_join.id, mir_op_vec_grow_checked(), grown.id, 0, receiver.id, domain, capacity_value.id, panic_block)
        current = try lower_jump_value(d, grown_instr.state, function, capacity_join.id, ready.id, grown.id)
        current = try lower_jump_value(d, current, function, keep.id, ready.id, receiver.id)

        let element_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
        let element = try lower_type(d, source_state, store, current, element_checked)
        let empty = try __s0_buffer_new(U64, d)
        let storage_type = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
        let storage = try lower_add_typed_result(d, lower_with_mir(element.state, storage_type.store), function, ready.id, storage_type.type_id)
        let storage_instr = try lower_add_instr(d, storage.state, function, ready.id, mir_op_vec_storage(), storage.id, 0, 0, ready_value.id, 0, 0, "")
        let target = try lower_add_typed_result(d, storage_instr.state, function, ready.id, storage_type.type_id)
        let indexed = try lower_add_instr(d, target.state, function, ready.id, mir_op_slice_index_checked(), target.id, 0, 0, storage.id, length.id, panic_block, "")
        let target_place = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: target.id))
        let stored = try lower_add_instr(d, lower_with_mir(indexed.state, target_place.store), function, ready.id, mir_op_store(), 0, target_place.id, 0, first_arg, 0, 0, "")
        let one = try lower_int_value_seq(d, source_state, store, stored.state, function, ready.id, 1)
        let next_length = try lower_add_typed_result(d, one.state, function, ready.id, mir_type_u64())
        let added = try lower_add_instr(d, next_length.state, function, ready.id, mir_op_int_add_checked(), next_length.id, 0, 0, length.id, one.id, panic_block, "")
        let next_capacity = try lower_add_typed_result(d, added.state, function, ready.id, mir_type_u64())
        let next_capacity_instr = try lower_add_instr(d, next_capacity.state, function, ready.id, mir_op_vec_capacity(), next_capacity.id, 0, 0, ready_value.id, 0, 0, "")
        let updated = try lower_add_typed_result(d, next_capacity_instr.state, function, ready.id, vector.id)
        let built = try lower_add_instr_three(d, updated.state, function, ready.id, mir_op_vec_construct_checked(), updated.id, 0, storage.id, next_length.id, next_capacity.id, panic_block)
        let write_place = try lower_receiver_place(d, source_state, spans, store, built.state, owner, function, ready.id, annotation.place, environment, panic_block)
        if write_place.id == 0 { return Ok(LowerStep(state: lower_invalid(write_place.state), id: 0)) }
        let saved = try lower_add_instr(d, lower_with_mir(built.state, write_place.state.mir), function, ready.id, mir_op_store(), 0, write_place.id, 0, updated.id, 0, 0, "")
        return Ok(LowerStep(state: saved.state, id: 0))
    }
    if annotation.builtin == 22 {
        let length = try lower_add_typed_result(d, current, function, active, mir_type_u64())
        var length_op = mir_op_slice_len()
        if receiver_checked.kind == 17 { length_op = mir_op_vec_len() }
        let length_instr = try lower_add_instr(d, length.state, function, active, length_op, length.id, 0, 0, receiver.id, 0, 0, "")
        let in_bounds = try lower_add_typed_result(d, length_instr.state, function, active, mir_type_bool())
        let compared = try lower_add_instr(d, in_bounds.state, function, active, mir_op_int_lt(), in_bounds.id, 0, 0, first_arg, length.id, 0, "")
        let some_block = try lower_add_block(d, compared.state, function, "bb_get_some")
        let none_block = try lower_add_block(d, some_block.state, function, "bb_get_none")
        let join = try lower_add_block(d, none_block.state, function, "bb_get_result")
        let option = try lower_type(d, source_state, store, join.state, expression.checked_type)
        let result = try mir_add_block_param(d, option.state.mir, function, join.id, 0, try lower_decimal_name(d, "__m71_get_", join.id), option.id)
        current = try lower_branch(d, lower_with_mir(option.state, result.store), function, active, in_bounds.id, some_block.id, none_block.id)
        var view = receiver
        if receiver_checked.kind == 17 {
            let element_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
            let element = try lower_type(d, source_state, store, current, element_checked)
            let empty = try __s0_buffer_new(U64, d)
            let view_type = try mir_intern_type(d, element.state.mir, mir_type_kind_slice(), element.id, 0, 0, empty, 0)
            let view_value = try lower_add_typed_result(d, lower_with_mir(element.state, view_type.store), function, some_block.id, view_type.type_id)
            let converted = try lower_add_instr(d, view_value.state, function, some_block.id, mir_op_vec_as_slice(), view_value.id, 0, 0, receiver.id, 0, 0, "")
            view = LowerStep(state: converted.state, id: view_value.id)
        } else { view = LowerStep(state: current, id: receiver.id) }
        let element_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
        let element = try lower_type(d, source_state, store, view.state, element_checked)
        let empty = try __s0_buffer_new(U64, d)
        let reference_type = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
        let reference = try lower_add_typed_result(d, lower_with_mir(element.state, reference_type.store), function, some_block.id, reference_type.type_id)
        let indexed = try lower_add_instr(d, reference.state, function, some_block.id, mir_op_slice_index_checked(), reference.id, 0, 0, view.id, first_arg, panic_block, "")
        let place = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: reference.id))
        let loaded = try lower_add_typed_result(d, lower_with_mir(indexed.state, place.store), function, some_block.id, element.id)
        let load = try lower_add_instr(d, loaded.state, function, some_block.id, mir_op_load(), loaded.id, place.id, 0, 0, 0, 0, "")
        let copied = try lower_move_or_copy(d, source_state, spans, store, load.state, owner, function, some_block.id, expression_id, element_checked, loaded.id, receiver_source_expression(expression, store), 0)
        let some = try lower_add_typed_result(d, copied.state, function, some_block.id, option.id)
        let made_some = try lower_add_instr(d, some.state, function, some_block.id, mir_op_enum_construct(), some.id, 0, option.id, copied.id, 0, 0, "some")
        current = try lower_jump_value(d, made_some.state, function, some_block.id, join.id, some.id)
        let none = try lower_add_typed_result(d, current, function, none_block.id, option.id)
        let made_none = try lower_add_instr(d, none.state, function, none_block.id, mir_op_enum_construct(), none.id, 0, option.id, 0, 0, 0, "none")
        current = try lower_jump_value(d, made_none.state, function, none_block.id, join.id, none.id)
        return Ok(LowerStep(state: current, id: result.id))
    }
    if annotation.builtin == 23 || annotation.builtin == 24 || annotation.builtin == 25 {
        var base = receiver
        if receiver_checked.kind == 17 {
            let element_checked = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
            let element = try lower_type(d, source_state, store, current, element_checked)
            let empty = try __s0_buffer_new(U64, d)
            var view_kind = mir_type_kind_slice()
            var op = mir_op_vec_as_slice()
            if annotation.builtin == 24 { view_kind = mir_type_kind_safe_mut()
                op = mir_op_vec_as_mut_slice() }
            let view_type = try mir_intern_type(d, element.state.mir, view_kind, element.id, 0, 0, empty, 0)
            let view = try lower_add_typed_result(d, lower_with_mir(element.state, view_type.store), function, active, view_type.type_id)
            let converted = try lower_add_instr(d, view.state, function, active, op, view.id, 0, 0, receiver.id, 0, 0, "")
            base = LowerStep(state: converted.state, id: view.id)
            current = converted.state
        }
        let result_type = try lower_type(d, source_state, store, current, expression.checked_type)
        let result = try lower_add_typed_result(d, result_type.state, function, active, result_type.id)
        let ranged = try lower_add_instr_three(d, result.state, function, active, mir_op_slice_range_checked(), result.id, 0, base.id, first_arg, second_arg, panic_block)
        return Ok(LowerStep(state: ranged.state, id: result.id))
    }
    if annotation.builtin == 968 {
        // [U8].to_bytes copies the view into fresh bytes storage. The domain
        // operand is the allocation site's storage domain, exactly as for
        // the string concat and slice forms.
        let domain = lower_storage_domain_value(current, store, owner, expression_id)
        if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let result = try lower_add_result(d, current, function, active, expression.checked_type, source_state, store)
        let converted = try lower_add_instr_three(d, result.state, function, active, mir_op_slice_to_bytes(), result.id, 0, domain, receiver.id, 0, panic_block)
        return Ok(LowerStep(state: converted.state, id: result.id))
    }
    return Ok(LowerStep(state: lower_invalid(current), id: 0))
}

// M7.5 table builtins: 26 Table.new, 27 insert, 28 get, 29 get_mut, 45
// remove, and 46 try_insert. Table.new materializes the owner in the hidden
// storage domain; method children are the receiver read and the single
// runtime argument in checked order.
fn lower_m75_table_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    // Table.new carries no runtime children; every method carries exactly the
    // receiver read and one runtime argument.
    if annotation.builtin != 26 && (expression.child_count == 0 || expression.first_child == 0 || expression.first_child > __s0_buffer_len(CheckedExprChildRec, store.expression_children)) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let result_type = try lower_type(d, source_state, store, state, expression.checked_type)
    if !result_type.state.valid { return Ok(result_type) }
    if annotation.builtin == 26 {
        let table_checked = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
        if table_checked.kind != 19 || table_checked.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(result_type.state), id: 0)) }
        let element = try lower_type(d, source_state, store, result_type.state, __s0_buffer_get(U64, store.type_args, table_checked.first_arg - 1))
        if !element.state.valid { return Ok(element) }
        // A table's element storage allocates in the caller-result domain,
        // which outlives this function: tables are not relocatable, so an
        // escaping owner must not carry a handle into a domain the function
        // destroys on return. Table storage therefore dies with the caller's
        // domain, never with the creating scope.
        let domain = lower_result_domain_value(element.state, store, owner)
        if domain == 0 { return Ok(LowerStep(state: lower_invalid(element.state), id: 0)) }
        let result = try lower_add_result(d, element.state, function, block, expression.checked_type, source_state, store)
        if !result.state.valid { return Ok(result) }
        let created = try lower_add_instr(d, result.state, function, block, mir_op_table_create(), result.id, 0, element.id, domain, 0, 0, "")
        return Ok(LowerStep(state: created.state, id: result.id))
    }
    let receiver_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, result_type.state, owner, function, block, receiver_id, environment, panic_block)
    if expression.child_count != 2 || expression.first_child > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
    let argument_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let argument = try lower_expression(d, source_state, spans, store, receiver.state, owner, function, block, argument_id, environment, panic_block)
    if !argument.state.valid { return Ok(argument) }
    var op = mir_op_table_insert()
    if annotation.builtin == 28 { op = mir_op_table_lookup() }
    if annotation.builtin == 29 { op = mir_op_table_lookup_mut() }
    if annotation.builtin == 45 { op = mir_op_table_remove() }
    if annotation.builtin == 46 { op = mir_op_table_insert_try() }
    let result = try lower_add_result(d, argument.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, receiver.id, argument.id, 0, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

fn lower_expression(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.owner != owner || !lower_type_concrete(store, expression.checked_type) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if expression.kind == 1 || expression.kind == 5 || expression.kind == 22 {
        return lower_binding_expression(d, source_state, spans, store, state, owner, function, block, expression_id, expression, expression.kind != 22)
    }
    if expression.kind == 40 { return lower_interpolation_expression(d, source_state, spans, store, state, owner, function, block, expression_id, expression, environment, panic_block) }
    if expression.kind >= 2 && expression.kind <= 4 {
        let typ = try lower_type(d, source_state, store, state, expression.checked_type)
        var kind = mir_const_bool()
        var bool_value = expression.bool_value
        if lower_checked_unit(store, expression.checked_type) { kind = mir_const_unit() }
        var int_value: I64 = 0
        var text: __s0_String = ""
        if expression.kind == 3 {
            kind = mir_const_int()
            int_value = lower_parse_i64(source_state, spans, expression)
        }
        if expression.kind == 4 {
            kind = mir_const_string()
            if expression.syntax == 0 || expression.syntax > __s0_buffer_len(CheckedSpanRec, spans) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
            let span = __s0_buffer_get(CheckedSpanRec, spans, expression.syntax - 1)
            let token_id = lower_token_for_span(source_state, span)
            if token_id == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
            let token = __s0_buffer_get(TokenRec, source_state.tokens, token_id - 1)
            text = try lower_word(d, source_state.values, token.value_start, token.value_end)
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
    if expression.kind == 26 {
        // The safe binding observation c.is_null: one raw-pointer child,
        // Bool result.
        if expression.child_count != 1 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let child = try lower_expression(d, source_state, spans, store, state, owner, function, block, child_id, environment, panic_block)
        if !child.state.valid { return Ok(child) }
        let typ = try lower_type(d, source_state, store, child.state, expression.checked_type)
        let result = try lower_add_result(d, typ.state, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_c_is_null(), result.id, 0, 0, child.id, 0, 0, "")
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind == 27 || expression.kind == 28 {
        return lower_c_field_access(d, source_state, spans, store, state, owner, function, block, expression_id, expression, environment, panic_block)
    }
    if expression.kind == 23 {
        let typ = try lower_type(d, source_state, store, state, expression.checked_type)
        var current = typ.state
        var active = block
        var values = try __s0_buffer_new(U64, d)
        var ordinal: U64 = 0
        while ordinal < expression.child_count {
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
            let child = try lower_expression(d, source_state, spans, store, current, owner, function, active, child_id, environment, panic_block)
            current = child.state
            active = lower_open_block(current.mir, function, active)
            values = try __s0_buffer_append(U64, d, values, child.id)
            ordinal = ordinal + 1
        }
        let result = try lower_add_typed_result(d, current, function, active, typ.id)
        let constructed = try lower_add_instr(d, result.state, function, active, mir_op_aggregate_construct(), result.id, 0, typ.id, 0, 0, 0, "")
        current = constructed.state
        ordinal = 0
        while ordinal < __s0_buffer_len(U64, values) {
            current = try lower_add_instr_operand(d, current, constructed.id, ordinal, __s0_buffer_get(U64, values, ordinal), mir_operand_aggregate_field(), "")
            ordinal = ordinal + 1
        }
        return Ok(LowerStep(state: current, id: result.id))
    }
    if expression.kind == 24 {
        // Closure creation. Capture-free closures are plain function values;
        // capturing closures allocate the environment record, copy each
        // captured value into it (snapshot semantics, vec copies included),
        // and pair it with the thunk through fn.value.
        if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(ClosureSiteRec, store.closures.sites) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let site = __s0_buffer_get(ClosureSiteRec, store.closures.sites, expression.parameter_use - 1)
        if site.expression != expression_id { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let thunk = lower_owner_lookup(state.owners, site.owner)
        if thunk == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let fn_type = try lower_type(d, source_state, store, state, expression.checked_type)
        if !fn_type.state.valid { return Ok(fn_type) }
        var current = fn_type.state
        var env_value: U64 = 0
        var marker: U64 = 0
        if site.capture_count != 0 {
            let env_type = try lower_closure_env_type(d, source_state, store, current, site)
            if !env_type.state.valid { return Ok(env_type) }
            current = env_type.state
            let empty = try __s0_buffer_new(U64, d)
            let reference = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), env_type.id, 0, 0, empty, 0)
            current = lower_with_mir(current, reference.store)
            let domain = lower_storage_domain_value(current, store, owner, expression_id)
            if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            // Build the environment record value from the captured values,
            // copy it into the creation domain, and store it into the
            // allocated slot. The copy gives the stored value domain
            // provenance, which keeps closure creation inside loops within
            // the loop-store rule. A closure that escapes is retained into
            // its destination domain by copy_to_domain of the function value,
            // which allocates a complete environment there.
            var field_values = try __s0_buffer_new(U64, d)
            var ordinal: U64 = 0
            while ordinal < site.capture_count {
                let capture = __s0_buffer_get(ClosureCaptureRec, store.closures.captures, site.first_capture - 1 + ordinal)
                let local = __s0_buffer_get(LocalRec, store.locals, capture.local - 1)
                let typ = try lower_local_type(d, source_state, store, current, owner, capture.local, local)
                if !typ.state.valid { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                current = typ.state
                var captured: U64 = 0
                let binding = lower_binding_lookup(current, capture.local)
                if binding.binding == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                if binding.parameter == 1 {
                    captured = binding.mir_id
                } else {
                    let capture_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
                    current = lower_with_mir(current, capture_place.store)
                    let loaded = try lower_helper_load(d, current, function, block, capture_place.id, typ.id)
                    current = loaded.state
                    captured = loaded.id
                }
                let copied = try lower_move_or_copy(d, source_state, spans, store, current, owner, function, block, expression_id, capture.checked_type, captured, 0, 2)
                if !copied.state.valid { return Ok(copied) }
                let stored = try lower_capture_storage_copy(d, source_state, spans, store, copied.state, owner, function, block, expression_id, capture.checked_type, copied.id)
                if !stored.state.valid { return Ok(stored) }
                current = stored.state
                field_values = try __s0_buffer_append(U64, d, field_values, stored.id)
                ordinal = ordinal + 1
            }
            let record_result = try lower_add_typed_result(d, current, function, block, env_type.id)
            let constructed = try lower_add_instr(d, record_result.state, function, block, mir_op_aggregate_construct(), record_result.id, 0, env_type.id, 0, 0, 0, "")
            current = constructed.state
            // The record carries the domain it lives in, so the thunk can
            // copy or allocate storage, and the stored value needs no
            // cross-domain copy: its domain field gives it provenance.
            current = try lower_add_instr_operand(d, current, constructed.id, 0, domain, mir_operand_aggregate_field(), "alder_env_domain")
            var field_ordinal: U64 = 1
            ordinal = 0
            while ordinal < site.capture_count {
                let capture_local = __s0_buffer_get(LocalRec, store.locals, __s0_buffer_get(ClosureCaptureRec, store.closures.captures, site.first_capture - 1 + ordinal).local - 1)
                let field_name = try lower_source_word(d, source_state, capture_local.source, capture_local.name_start, capture_local.name_end)
                current = try lower_add_instr_operand(d, current, constructed.id, field_ordinal + ordinal, __s0_buffer_get(U64, field_values, ordinal), mir_operand_aggregate_field(), field_name)
                ordinal = ordinal + 1
            }
            let stored_value = record_result.id
            let one = try lower_helper_const(d, current, function, block, mir_type_u64(), 1, expression_id * 100 + 71)
            current = one.state
            let env_result = try lower_add_typed_result(d, current, function, block, reference.type_id)
            current = env_result.state
            let allocated = try lower_add_instr(d, current, function, block, mir_op_alloc_checked(), env_result.id, 0, env_type.id, domain, one.id, panic_block, "")
            current = allocated.state
            env_value = env_result.id
            let env_deref = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: env_value))
            current = lower_with_mir(current, env_deref.store)
            let env_stored = try lower_add_instr(d, current, function, block, mir_op_store(), 0, env_deref.id, 0, stored_value, 0, 0, "")
            current = env_stored.state
        } else {
            // A bare thunk carries the caller's domain in the environment
            // member and takes it as its leading parameter, the way a named
            // function value does.
            if state.has_storage {
                env_value = lower_keyed_domain_value(current, lower_env_domain_key(owner))
                if env_value == 0 { env_value = lower_domain_value(current, store, owner) }
                if env_value == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                marker = mir_fn_value_domain_marker()
            }
        }
        let result = try lower_add_typed_result(d, current, function, block, fn_type.id)
        let made = try lower_add_instr(d, result.state, function, block, mir_op_fn_value(), result.id, 0, marker, env_value, 0, thunk, "")
        return Ok(LowerStep(state: made.state, id: result.id))
    }
    if expression.kind == 19 {
        let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        let index_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
        let base_expression = __s0_buffer_get(CheckedExprRec, store.expressions, base_id - 1)
        let checked_base_type = __s0_buffer_get(CheckedTypeRec, store.types, base_expression.checked_type - 1)
        var base = LowerStep(state: state, id: 0)
        if checked_base_type.kind == 17 { base = try lower_direct_expression(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block) } else {
            base = try lower_expression(d, source_state, spans, store, state, owner, function, block, base_id, environment, panic_block)
        }
        let base_block = lower_open_block(base.state.mir, function, block)
        var sequence = base
        if checked_base_type.kind == 17 {
            let element_checked = __s0_buffer_get(U64, store.type_args, checked_base_type.first_arg - 1)
            let element_type = try lower_type(d, source_state, store, base.state, element_checked)
            let empty_view = try __s0_buffer_new(U64, d)
            let view_type = try mir_intern_type(d, element_type.state.mir, mir_type_kind_slice(), element_type.id, 0, 0, empty_view, 0)
            let view = try lower_add_typed_result(d, lower_with_mir(element_type.state, view_type.store), function, base_block, view_type.type_id)
            let converted = try lower_add_instr(d, view.state, function, base_block, mir_op_vec_as_slice(), view.id, 0, 0, base.id, 0, 0, "")
            sequence = LowerStep(state: converted.state, id: view.id)
        }
        let index = try lower_expression(d, source_state, spans, store, sequence.state, owner, function, base_block, index_id, environment, panic_block)
        let active = lower_open_block(index.state.mir, function, base_block)
        let element = try lower_type(d, source_state, store, index.state, expression.checked_type)
        let empty = try __s0_buffer_new(U64, d)
        let reference = try mir_intern_type(d, element.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty, 0)
        let ref_value = try mir_add_value(d, reference.store, function, try lower_result_name(d, reference.store, function, ""), reference.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(reference.store, function, active) + 1)
        var index_op = mir_op_slice_index_checked()
        if __s0_buffer_get(CheckedTypeRec, store.types, base_expression.checked_type - 1).kind == 15 { index_op = mir_op_array_index_checked() }
        let indexed = try lower_add_instr(d, lower_with_mir(element.state, ref_value.store), function, active, index_op, ref_value.id, 0, 0, sequence.id, index.id, panic_block, "")
        let place = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: ref_value.id))
        let result = try lower_add_result(d, lower_with_mir(indexed.state, place.store), function, active, expression.checked_type, source_state, store)
        let loaded = try lower_add_instr(d, result.state, function, active, mir_op_load(), result.id, place.id, 0, 0, 0, 0, "")
        return lower_move_or_copy(d, source_state, spans, store, loaded.state, owner, function, active, expression_id, expression.checked_type, result.id, base_id, 0)
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
        // A table view reads its element in place: the base value is the view
        // itself, so the field place derefs it directly. Spilling a view to a
        // temporary would leave its single-block access region.
        let base_type_checked = __s0_buffer_get(CheckedTypeRec, store.types, base_expression.checked_type - 1)
        if base_type_checked.kind == 21 || base_type_checked.kind == 22 {
            let deref = try mir_add_place(d, base_type.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: base.id))
            let named = try mir_append_name(d, deref.store, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
            let field_place = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: deref.id, field_start: named.start, field_end: named.end, deref_value: 0))
            let result = try lower_add_result(d, lower_with_mir(base_type.state, field_place.store), function, active, expression.checked_type, source_state, store)
            let loaded = try lower_add_instr(d, result.state, function, active, mir_op_load(), result.id, field_place.id, 0, 0, 0, 0, "")
            return lower_move_or_copy(d, source_state, spans, store, loaded.state, owner, function, active, expression_id, expression.checked_type, result.id, base_id, 0)
        }
        let ordinal = lower_local_count(base_type.state.mir, function)
        let temporary = try mir_add_local(d, base_type.state.mir, function, ordinal, try lower_decimal_name(d, "field_tmp", expression_id), base_type.id)
        let local_place = try mir_add_place(d, temporary.store, MirPlaceRec(function: function, kind: mir_place_local(), local: temporary.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
        let stored = try lower_add_instr(d, lower_with_mir(base_type.state, local_place.store), function, active, mir_op_store(), 0, local_place.id, 0, base.id, 0, 0, "")
        let named = try mir_append_name(d, stored.state.mir, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
        let field_place = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: local_place.id, field_start: named.start, field_end: named.end, deref_value: 0))
        let result = try lower_add_result(d, lower_with_mir(stored.state, field_place.store), function, active, expression.checked_type, source_state, store)
        let loaded = try lower_add_instr(d, result.state, function, active, mir_op_load(), result.id, field_place.id, 0, 0, 0, 0, "")
        return lower_move_or_copy(d, source_state, spans, store, loaded.state, owner, function, active, expression_id, expression.checked_type, result.id, base_id, 0)
    }
    if expression.kind == 6 || expression.kind == 7 {
        if expression.child_count == 0 || expression.first_child == 0 || expression.first_child - 1 + expression.child_count > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let left_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
        // Eq operands outside the primitive kinds route through the structural
        // walk before any operand lowers: String, Bytes, records, enums, and
        // generic applications over them share the Map-key lowering instead of
        // the int comparisons, and the walk lowers and spills its own operand
        // expressions where their values are defined.
        var structural_operand: U64 = 0
        if expression.kind == 7 && (expression.operator == 10 || expression.operator == 11) {
            let operand_checked = __s0_buffer_get(CheckedExprRec, store.expressions, left_id - 1).checked_type
            if lower_structural_operand(store, operand_checked) { structural_operand = operand_checked }
        }
        if structural_operand != 0 {
            let eq_right_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
            return lower_structural_equal_exprs(d, source_state, spans, store, state, owner, function, block, expression, left_id, eq_right_id, structural_operand, expression_id, environment, panic_block)
        }
        let left = try lower_expression(d, source_state, spans, store, state, owner, function, block, left_id, environment, panic_block)
        if expression.kind == 6 && expression.operator == 2 {
            let source_block = lower_open_block(left.state.mir, function, block)
            let true_block = try lower_add_block(d, left.state, function, "bb_not_true")
            let false_block = try lower_add_block(d, true_block.state, function, "bb_not_false")
            let join = try lower_add_block(d, false_block.state, function, "bb_not_join")
            let typ = try lower_type(d, source_state, store, join.state, expression.checked_type)
            let param = try mir_add_block_param(d, typ.state.mir, function, join.id, 0, try lower_decimal_name(d, "__alder_not_join", join.id), typ.id)
            var current = lower_with_mir(typ.state, param.store)
            current = try lower_branch(d, current, function, source_block, left.id, false_block.id, true_block.id)
            // Constants are module-scoped, so key unary Boolean constants by the
            // store-const count rather than expression ids: nested or adjacent
            // unaries reuse the same expression_id offsets and would collide.
            let bool_suffix = __s0_buffer_len(MirConstRec, current.mir.constants) + 1
            let truth = try lower_bool_value(d, source_state, store, current, function, true_block.id, expression.checked_type, 1, "__alder_not_true_", bool_suffix)
            current = try lower_jump_value(d, truth.state, function, true_block.id, join.id, truth.id)
            let falsity = try lower_bool_value(d, source_state, store, current, function, false_block.id, expression.checked_type, 0, "__alder_not_false_", bool_suffix)
            current = try lower_jump_value(d, falsity.state, function, false_block.id, join.id, falsity.id)
            return Ok(LowerStep(state: current, id: param.id))
        }
        if expression.kind == 6 && expression.operator == 21 {
            let result = try lower_add_result(d, left.state, function, block, expression.checked_type, source_state, store)
            let instr = try lower_add_instr(d, result.state, function, block, mir_op_int_not(), result.id, 0, 0, left.id, 0, 0, "")
            return Ok(LowerStep(state: instr.state, id: result.id))
        }
        if expression.kind == 7 && (expression.operator == 16 || expression.operator == 17) {
            if expression.child_count != 2 { return Ok(LowerStep(state: lower_invalid(left.state), id: 0)) }
            let source_block = lower_open_block(left.state.mir, function, block)
            let right_block = try lower_add_block(d, left.state, function, "bb_short")
            let constant_block = try lower_add_block(d, right_block.state, function, "bb_short_const")
            let join = try lower_add_block(d, constant_block.state, function, "bb_short_join")
            let result_type = try lower_type(d, source_state, store, join.state, expression.checked_type)
            let param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, try lower_decimal_name(d, "__alder_short_", join.id), result_type.id)
            var current = lower_with_mir(result_type.state, param.store)
            if expression.operator == 16 { current = try lower_branch(d, current, function, source_block, left.id, right_block.id, constant_block.id) }
            if expression.operator == 17 { current = try lower_branch(d, current, function, source_block, left.id, constant_block.id, right_block.id) }
            let right_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
            let right = try lower_expression(d, source_state, spans, store, current, owner, function, right_block.id, right_id, environment, panic_block)
            current = try lower_jump_value(d, right.state, function, lower_open_block(right.state.mir, function, right_block.id), join.id, right.id)
            var constant_value: U64 = 0
            if expression.operator == 17 { constant_value = 1 }
            let constant = try lower_bool_value(d, source_state, store, current, function, constant_block.id, expression.checked_type, constant_value, "lit.bool", expression_id)
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
        if expression.operator == 18 { op = mir_op_int_and() }
        if expression.operator == 19 { op = mir_op_int_xor() }
        if expression.operator == 20 { op = mir_op_int_or() }
        // Float operands override the int table: the table maps every
        // comparison operator unconditionally, so a fill-in dispatch after
        // it would never fire for float == and !=.
        let float_op = lower_float_binary_op(store, __s0_buffer_get(CheckedExprRec, store.expressions, left_id - 1).checked_type, expression.operator)
        if float_op != 0 { op = float_op }
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
        var fail: U64 = panic_block
        if expression.operator >= 18 && expression.operator <= 20 { fail = 0 }
        let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, a, b, fail, "")
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    if expression.kind >= 8 && expression.kind <= 11 {
        if expression.annotation == 0 || expression.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
        if annotation.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        var current = state
        var args = try __s0_buffer_new(U64, d)
        var owners = try __s0_buffer_new(U64, d)
        var ordinal: U64 = 0
        while ordinal < expression.child_count {
            if expression.first_child == 0 || expression.first_child - 1 + ordinal >= __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
            let checked_child = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
            var child = LowerStep(state: current, id: 0)
            var borrow_kind: U64 = 0
            var sequence_borrow = false
            if annotation.kind == 1 {
                let target_symbol = __s0_buffer_get(SymbolRec, store.symbols, annotation.target - 1)
                var parameter_role: U64 = 5
                if target_symbol.kind == 13 { parameter_role = 7 }
                let parameter_use = lower_use_by_role(store, annotation.target, parameter_role, ordinal)
                if parameter_use != 0 {
                    let parameter_type = __s0_buffer_get(DeclTypeUseRec, store.uses, parameter_use - 1).checked_type
                    let expected = __s0_buffer_get(CheckedTypeRec, store.types, parameter_type - 1)
                    let actual = __s0_buffer_get(CheckedTypeRec, store.types, checked_child.checked_type - 1)
                    sequence_borrow = expected.kind == 8 && (actual.kind == 15 || actual.kind == 17)
                }
                // The ordinal-th declared parameter of the callee: the
                // owner-keyed local index visits exactly the locals the
                // full-table walk used to visit, in the same order, without
                // rescanning every local of every function per argument.
                let parameter_binding = lower_closure_param_local(store, current.local_index, annotation.target, ordinal)
                if parameter_binding != 0 {
                    let parameter = __s0_buffer_get(LocalRec, store.locals, parameter_binding - 1)
                    if parameter.mutable == 1 { borrow_kind = 2 }
                    if parameter.mutable == 0 && target_symbol.inherent_owner != 0 {
                        // A receiver the checker marked as a transfer is a
                        // `take self` value; only a borrowed receiver becomes
                        // a reference argument.
                        if checked_child.kind != 22 && checked_child.field_move == 0 {
                            let parameter_source = __s0_buffer_get(SourceRec, source_state.sources, parameter.source)
                            if source_word(source_state, parameter_source, parameter.name_start, parameter.name_end, "self") { borrow_kind = 1 }
                        }
                    }
                }
            }
            var arg_owner: U64 = 0
            var callback_argument = LowerCCallbackRec(matched: false, state: current, id: 0)
            if annotation.kind == 7 && child_id != 0 { callback_argument = try lower_c_callback_argument(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block) }
            var addr_argument = LowerCAddrRec(matched: false, state: current, id: 0)
            if !callback_argument.matched && annotation.kind == 7 && child_id != 0 { addr_argument = try lower_c_addr_argument(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block) }
            var buffer_argument = LowerCBufferRec(matched: false, state: current, id: 0)
            if !callback_argument.matched && !addr_argument.matched && annotation.kind == 7 && child_id != 0 { buffer_argument = try lower_c_buffer_argument(d, source_state, spans, store, current, owner, function, block, annotation, ordinal, child_id, checked_child.checked_type, environment, panic_block) }
            if callback_argument.matched {
                child = LowerStep(state: callback_argument.state, id: callback_argument.id)
            } else { if addr_argument.matched {
                child = LowerStep(state: addr_argument.state, id: addr_argument.id)
            } else { if buffer_argument.matched {
                child = LowerStep(state: buffer_argument.state, id: buffer_argument.id)
            } else { if sequence_borrow {
                let actual = __s0_buffer_get(CheckedTypeRec, store.types, checked_child.checked_type - 1)
                if actual.kind == 15 { child = try lower_array_view(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block, false) }
                if actual.kind == 17 {
                    let vector = try lower_direct_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block)
                    let element = try lower_type(d, source_state, store, vector.state, __s0_buffer_get(U64, store.type_args, actual.first_arg - 1))
                    let empty = try __s0_buffer_new(U64, d)
                    let view_type = try mir_intern_type(d, element.state.mir, mir_type_kind_slice(), element.id, 0, 0, empty, 0)
                    let view = try lower_add_typed_result(d, lower_with_mir(element.state, view_type.store), function, block, view_type.type_id)
                    let converted = try lower_add_instr(d, view.state, function, block, mir_op_vec_as_slice(), view.id, 0, 0, vector.id, 0, 0, "")
                    child = LowerStep(state: converted.state, id: view.id)
                }
            } else { if borrow_kind != 0 {
                let borrowed_place = try lower_argument_place(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block, borrow_kind)
                if !borrowed_place.state.valid { return Ok(LowerStep(state: borrowed_place.state, id: 0)) }
                let borrow_state = borrowed_place.state
                if borrow_kind == 2 && current.has_storage {
                    arg_owner = lower_binding_owner_domain(borrow_state, store, owner, borrowed_place.root)
                    if arg_owner == 0 { return Ok(LowerStep(state: lower_invalid(borrow_state), id: 0)) }
                }
                let ordinary = try lower_type(d, source_state, store, borrow_state, checked_child.checked_type)
                let empty = try __s0_buffer_new(U64, d)
                var reference_kind = mir_type_kind_safe_ref()
                var borrow_op = mir_op_borrow()
                if borrow_kind == 2 {
                    reference_kind = mir_type_kind_safe_mut()
                    borrow_op = mir_op_borrow_mut()
                }
                let reference = try mir_intern_type(d, ordinary.state.mir, reference_kind, ordinary.id, 0, 0, empty, 0)
                let value = try mir_add_value(d, reference.store, function, try lower_result_name(d, reference.store, function, ""), reference.type_id, mir_value_def_instruction(), block, lower_instruction_ordinal(reference.store, function, block) + 1)
                let borrowed = try lower_add_instr(d, lower_with_mir(ordinary.state, value.store), function, block, borrow_op, value.id, borrowed_place.place, 0, 0, 0, 0, "")
                child = LowerStep(state: borrowed.state, id: value.id)
            } else { child = try lower_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block) } } } } }
            current = child.state
            if borrow_kind == 2 && current.has_storage && arg_owner == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            args = try __s0_buffer_append(U64, d, args, child.id)
            owners = try __s0_buffer_append(U64, d, owners, arg_owner)
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
            var argument_ordinal: U64 = 0
            if annotation.kind == 1 && current.has_storage && !lower_owner_aliases_domain(source_state, store, annotation.target) {
                let domain = lower_domain_value(current, store, owner)
                if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                current = try lower_add_instr_operand(d, current, instr.id, 0, domain, mir_operand_instruction(), "")
                argument_ordinal = 1
            }
            while ordinal < __s0_buffer_len(U64, args) {
                current = try lower_add_instr_operand(d, current, instr.id, argument_ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
                argument_ordinal = argument_ordinal + 1
                let owner_arg_value = __s0_buffer_get(U64, owners, ordinal)
                if owner_arg_value != 0 {
                    current = try lower_add_instr_operand(d, current, instr.id, argument_ordinal, owner_arg_value, mir_operand_instruction(), "")
                    argument_ordinal = argument_ordinal + 1
                }
                ordinal = ordinal + 1
            }
            return Ok(LowerStep(state: current, id: result))
        }
        if annotation.kind == 7 { return lower_binding_call_step(d, store, current, function, block, result, annotation, args) }
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
            if expression.child_count == 1 {
                // A unit payload carries no MIR operand; the variant tag
                // alone identifies it, matching the verifier's rule.
                let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
                if !lower_checked_unit(store, __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1).checked_type) { payload = __s0_buffer_get(U64, args, 0) }
            }
            let instr = try lower_add_instr(d, current, function, block, mir_op_enum_construct(), result, 0, result_type.id, payload, 0, 0, name)
            return Ok(LowerStep(state: instr.state, id: result))
        }
        if annotation.kind == 6 {
            if expression.child_count != 0 || annotation.target != 0 || annotation.variant_use != 0 || (annotation.builtin != 5 && annotation.builtin != 6) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            var name: __s0_String = "OutOfMemory"
            if annotation.builtin == 6 { name = "Limit" }
            let instr = try lower_add_instr(d, current, function, block, mir_op_enum_construct(), result, 0, result_type.id, 0, 0, 0, name)
            return Ok(LowerStep(state: instr.state, id: result))
        }
        return Ok(LowerStep(state: lower_invalid(current), id: 0))
    }
    if expression.kind == 18 {
        if expression.annotation == 0 || expression.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
        if annotation.kind != 5 || annotation.builtin == 0 || annotation.builtin > 1001 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        if annotation.builtin == 1000 { return lower_order_less_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin == 1001 { return lower_display_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        // 968 is the sequence-surface [U8].to_bytes, numbered clear of the
        // dense families above; it shares the M7.1 sequence lowering.
        if annotation.builtin == 968 { return lower_m71_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin == 969 { return lower_option_take(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin >= 65 { return lower_c_convert_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin >= 62 { return lower_int_convert_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin >= 56 { return lower_str_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin >= 47 { return lower_int_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin >= 26 && annotation.builtin <= 29 || annotation.builtin == 45 || annotation.builtin == 46 {
            return lower_m75_table_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block)
        }
        if annotation.builtin >= 30 { return lower_m75_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
        if annotation.builtin >= 18 { return lower_m71_builtin(d, source_state, spans, store, state, owner, function, block, expression_id, expression, annotation, environment, panic_block) }
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
        if annotation.builtin >= 9 && annotation.builtin <= 13 || annotation.builtin == 17 {
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
            if annotation.builtin == 17 { target = bridge.set_id }
            if annotation.builtin == 17 {
                let call = try lower_add_instr(d, current, function, block, mir_op_call(), 0, 0, 0, 0, 0, target, "")
                current = call.state
                ordinal = 0
                while ordinal < __s0_buffer_len(U64, args) {
                    current = try lower_add_instr_operand(d, current, call.id, ordinal, __s0_buffer_get(U64, args, ordinal), mir_operand_instruction(), "")
                    ordinal = ordinal + 1
                }
                return Ok(LowerStep(state: current, id: 0))
            }
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
        var name: __s0_String = "none"
        if expression.kind == 15 { name = "some" }
        if expression.kind == 16 { name = "ok" }
        if expression.kind == 17 { name = "err" }
        var current = state
        var payload: U64 = 0
        if expression.child_count == 1 {
            let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
            let child = try lower_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block)
            current = child.state
            if !lower_checked_unit(store, __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1).checked_type) { payload = child.id }
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
        let join_param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, try lower_decimal_name(d, "__alder_match_join", join.id), result_type.id)
        var current = lower_with_mir(result_type.state, join_param.store)
        // A guarded arm enters through its own test block; an unguarded arm
        // enters its body block directly. Arms of one variant form a
        // contiguous run that shares one switch case: the case jumps to the
        // run's first arm entry, and a false guard branches to the next
        // entry of the same run, or to the wildcard arm's entry when the run
        // ends.
        var arm_blocks = try __s0_buffer_new(U64, d)
        var arm_entries = try __s0_buffer_new(U64, d)
        var wildcard_entry: U64 = 0
        var ordinal: U64 = 0
        while ordinal < checked.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal)
            let arm_block = try lower_add_block(d, current, function, "bb_match_arm")
            current = arm_block.state
            arm_blocks = try __s0_buffer_append(U64, d, arm_blocks, arm_block.id)
            if arm.guard != 0 {
                let test_block = try lower_add_block(d, current, function, "bb_match_guard")
                current = test_block.state
                arm_entries = try __s0_buffer_append(U64, d, arm_entries, test_block.id)
            } else {
                arm_entries = try __s0_buffer_append(U64, d, arm_entries, arm_block.id)
            }
            if arm.variant_kind == 7 && wildcard_entry == 0 { wildcard_entry = __s0_buffer_get(U64, arm_entries, ordinal) }
            ordinal = ordinal + 1
        }
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: scrutinee.id, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, term.store)
        ordinal = 0
        var case_ordinal: U64 = 0
        var run_binding_value: U64 = 0
        while ordinal < checked.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal)
            if arm.owner != owner || arm.checked_match != expression.parameter_use { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            var first_of_run = true
            if ordinal != 0 {
                let previous = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal - 1)
                first_of_run = !(previous.variant_kind == arm.variant_kind && previous.variant_use == arm.variant_use)
            }
            if first_of_run {
                let name = try lower_variant_name(d, source_state, store, arm.variant_kind, arm.variant_use)
                var binding_value: U64 = 0
                if arm.binding != 0 {
                    let local = __s0_buffer_get(LocalRec, store.locals, arm.binding - 1)
                    // A unit payload has no MIR switch-case binding; the
                    // variant tag alone identifies it.
                    if !lower_checked_unit(store, local.checked_type) {
                        let payload_type = try lower_type(d, source_state, store, current, local.checked_type)
                        let value = try mir_add_value(d, payload_type.state.mir, function, try lower_decimal_name(d, "__alder_match_payload", checked.first_arm + case_ordinal), payload_type.id, mir_value_def_switch_case(), source_block, case_ordinal + 1)
                        current = lower_with_mir(payload_type.state, value.store)
                        binding_value = value.id
                        let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: arm.binding, mir_id: value.id, parameter: 1, initial: 0))
                        current = lower_with_bindings(current, bindings)
                    }
                }
                let case = try lower_add_switch_case(d, current, term.id, case_ordinal, name, binding_value, __s0_buffer_get(U64, arm_entries, ordinal))
                current = case.state
                run_binding_value = binding_value
                case_ordinal = case_ordinal + 1
            } else {
                // A later arm of the same run binds the run's case payload.
                if arm.binding != 0 {
                    let local = __s0_buffer_get(LocalRec, store.locals, arm.binding - 1)
                    if !lower_checked_unit(store, local.checked_type) {
                        if run_binding_value == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                        let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: arm.binding, mir_id: run_binding_value, parameter: 1, initial: 0))
                        current = lower_with_bindings(current, bindings)
                    }
                }
            }
            ordinal = ordinal + 1
        }

        // Guard tests: a true guard enters the arm body; a false guard
        // continues with the next entry of the same run, or with the
        // wildcard arm's entry when the run ends.
        ordinal = 0
        while ordinal < checked.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal)
            if arm.guard != 0 {
                let entry = __s0_buffer_get(U64, arm_entries, ordinal)
                let guard_value = try lower_expression(d, source_state, spans, store, current, owner, function, entry, arm.guard, arm.environment, panic_block)
                current = guard_value.state
                if !current.valid { return Ok(LowerStep(state: current, id: 0)) }
                let active = lower_open_block(current.mir, function, entry)
                var fall_entry: U64 = 0
                if ordinal + 1 < checked.arm_count {
                    let next_arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal + 1)
                    if next_arm.variant_kind == arm.variant_kind && next_arm.variant_use == arm.variant_use { fall_entry = __s0_buffer_get(U64, arm_entries, ordinal + 1) }
                }
                if fall_entry == 0 { fall_entry = wildcard_entry }
                if fall_entry == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                current = try lower_branch(d, current, function, active, guard_value.id, __s0_buffer_get(U64, arm_blocks, ordinal), fall_entry)
            }
            ordinal = ordinal + 1
        }
        ordinal = 0
        var joined = false
        while ordinal < checked.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked.first_arm - 1 + ordinal)
            let arm_block = __s0_buffer_get(U64, arm_blocks, ordinal)
            if arm.block != 0 {
                // Statement arm: lower its block chain, end a bound table view
                // before leaving the arm, and join with a Unit constant. View
                // arms are straight-line by construction, so the view ends in
                // the arm's own region block on every fallthrough path.
                let arm_body = __s0_buffer_get(CheckedBlockRec, store.control.blocks, arm.block - 1)
                let arm_panic = try lower_panic_site(d, source_state, store, current, owner, function, arm_body.environment, environment, panic_block)
                let flow = try lower_block_statements(d, source_state, spans, store, arm_panic.state, owner, function, arm_block, arm.block, arm_panic.id, arm_body.environment)
                current = flow.state
                if !current.valid { return Ok(LowerStep(state: current, id: 0)) }
                if arm.binding != 0 {
                    let binding_local = __s0_buffer_get(LocalRec, store.locals, arm.binding - 1)
                    let binding_checked = __s0_buffer_get(CheckedTypeRec, store.types, binding_local.checked_type - 1)
                    if binding_checked.kind == 21 || binding_checked.kind == 22 {
                        let mapped = lower_binding_lookup(current, arm.binding)
                        if mapped.binding == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                        let ended = try lower_add_instr(d, current, function, flow.block, mir_op_table_view_end(), 0, 0, 0, mapped.mir_id, 0, 0, "")
                        current = ended.state
                    }
                }
                if !flow.terminated {
                    let unit_suffix = __s0_buffer_len(MirConstRec, current.mir.constants) + 1
                    let unit_name = try lower_decimal_name(d, "__alder_match_unit", unit_suffix)
                    let unit_const = try mir_add_const(d, current.mir, unit_name, mir_type_unit(), mir_const_unit(), 0, 0, 0, "")
                    let unit_result = try lower_add_typed_result(d, lower_with_mir(current, unit_const.store), function, flow.block, mir_type_unit())
                    let unit_instr = try lower_add_instr(d, unit_result.state, function, flow.block, mir_op_const_get(), unit_result.id, 0, 0, 0, 0, 0, unit_name)
                    current = try lower_jump_value(d, unit_instr.state, function, lower_open_block(unit_instr.state.mir, function, flow.block), join.id, unit_result.id)
                    joined = true
                }
            } else if arm.statement != 0 {
                // Diverging arm: the return statement lowers inside the arm
                // region and terminates every path, so nothing jumps to the
                // match join and the join parameter receives no value here.
                current = try lower_diverging_match_arm(d, source_state, spans, store, current, owner, function, arm_block, arm, environment, panic_block)
                if !current.valid { return Ok(LowerStep(state: current, id: 0)) }
            } else {
                let value = try lower_expression(d, source_state, spans, store, current, owner, function, arm_block, arm.body, arm.environment, panic_block)
                current = value.state
                if !current.valid { return Ok(LowerStep(state: current, id: 0)) }
                // An expression arm that binds a table view ends the view
                // after its body reads, before the join jump.
                if arm.binding != 0 {
                    let binding_local = __s0_buffer_get(LocalRec, store.locals, arm.binding - 1)
                    let binding_checked = __s0_buffer_get(CheckedTypeRec, store.types, binding_local.checked_type - 1)
                    if binding_checked.kind == 21 || binding_checked.kind == 22 {
                        let mapped = lower_binding_lookup(current, arm.binding)
                        if mapped.binding == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                        let active_arm = lower_open_block(current.mir, function, arm_block)
                        let ended = try lower_add_instr(d, current, function, active_arm, mir_op_table_view_end(), 0, 0, 0, mapped.mir_id, 0, 0, "")
                        current = ended.state
                    }
                }
                current = try lower_jump_value(d, current, function, lower_open_block(current.mir, function, arm_block), join.id, value.id)
                joined = true
            }
            ordinal = ordinal + 1
        }
        if !joined && checked_match_statement_diverges(source_state, store, expression_id) {
            let unreachable = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: join.id, kind: mir_term_unreachable(), value: 0, target: 0, then_block: 0, else_block: 0))
            current = lower_with_mir(current, unreachable.store)
        }
        return Ok(LowerStep(state: current, id: join_param.id))
    }
    if expression.kind == 29 { return lower_c_string_make_lit(d, source_state, spans, store, state, owner, function, block, expression_id, expression, environment, panic_block) }
    if expression.kind == 30 { return lower_c_string_make(d, source_state, spans, store, state, owner, function, block, expression_id, expression, environment, panic_block) }
    if expression.kind == 31 { return lower_c_string_ptr(d, source_state, spans, store, state, owner, function, block, expression_id, expression, environment, panic_block) }
    if expression.kind == 32 { return lower_c_zero(d, source_state, spans, store, state, owner, function, block, expression) }
    if expression.kind == 39 { return lower_callback_owner_register(d, source_state, spans, store, state, owner, function, block, expression, environment, panic_block) }
    if expression.kind == 38 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if expression.kind == 34 || expression.kind == 35 { return lower_c_pointer_field(d, source_state, spans, store, state, owner, function, block, expression, environment, panic_block) }
    if expression.kind == 36 || expression.kind == 37 { return lower_c_memory(d, source_state, spans, store, state, owner, function, block, expression, environment, panic_block) }
    if expression.kind == 13 {
        if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(CheckedTryRec, store.control.tries) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        let checked = __s0_buffer_get(CheckedTryRec, store.control.tries, expression.parameter_use - 1)
        if checked.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
        if checked.error_type == 0 { return lower_try_option(d, source_state, spans, store, state, owner, function, block, environment, panic_block, expression_id, checked) }
        let value = try lower_expression(d, source_state, spans, store, state, owner, function, block, checked.expression, environment, panic_block)
        let source_block = lower_open_block(value.state.mir, function, block)
        let ok_block = try lower_add_block(d, value.state, function, "bb_try_ok")
        let err_block = try lower_add_block(d, ok_block.state, function, "bb_try_err")
        let ok_type = try lower_type(d, source_state, store, err_block.state, checked.ok_type)
        let err_type = try lower_type(d, source_state, store, ok_type.state, checked.error_type)
        // `try` on a Result(Unit, E) has no ok payload to bind. A switch
        // case binding of unit type is invalid in MIR, so the ok case omits
        // its payload and the try expression is the unit value 0.
        let unit_ok = lower_checked_unit(store, checked.ok_type)
        var ok_id: U64 = 0
        var ok_mir = err_type.state.mir
        if !unit_ok {
            let ok_value = try mir_add_value(d, ok_mir, function, try lower_decimal_name(d, "try_ok", expression_id), ok_type.id, mir_value_def_switch_case(), source_block, 1)
            ok_id = ok_value.id
            ok_mir = ok_value.store
        }
        let err_value = try mir_add_value(d, ok_mir, function, try lower_decimal_name(d, "try_err", expression_id), err_type.id, mir_value_def_switch_case(), source_block, 2)
        let term = try mir_add_terminator(d, err_value.store, MirTermRec(function: function, block: source_block, kind: mir_term_switch(), value: value.id, target: 0, then_block: 0, else_block: 0))
        var current = lower_with_mir(err_type.state, term.store)
        let ok_case = try lower_add_switch_case(d, current, term.id, 0, "ok", ok_id, ok_block.id)
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
        let retained = try lower_retain_exit_value(d, source_state, store, constructed.state, owner, function, err_block.id, owner_result.checked_type, wrapped.id)
        current = try lower_cleanup_exits(d, source_state, store, retained.state, owner, function, err_block.id, environment, 0, 3)
        let failed = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: err_block.id, kind: mir_term_fail(), value: retained.id, target: 0, then_block: 0, else_block: 0))
        return Ok(LowerStep(state: lower_with_mir(current, failed.store), id: ok_id))
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

// Whether any registration is active between `environment` and `boundary`,
// that is, whether the exit walk from the one reaches a using record before
// the other.
fn lower_cleanup_active(store: CheckStore, owner: U64, environment: U64, boundary: U64) -> Bool {
    var at = environment
    while at != 0 && at != boundary {
        if at > __s0_buffer_len(EnvironmentRec, store.environments) { return false }
        let active = __s0_buffer_get(EnvironmentRec, store.environments, at - 1)
        if active.owner != owner { return false }
        var cleanup_at: U64 = 0
        while cleanup_at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
            let candidate = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, cleanup_at)
            if candidate.owner == owner && candidate.binding == active.binding && candidate.environment == active.parent { return true }
            cleanup_at = cleanup_at + 1
        }
        at = active.parent
    }
    return false
}

// The panic target for one statement. A checked failure inside a registration
// has to run the registrations it crosses before the shared handler, because a
// panic leaves every enclosing scope; without an active registration the shared
// handler is used unchanged, so programs without a using in scope keep their
// existing shape.
// `shared` already runs the registrations active at `boundary`, so a nested
// statement only has to run the ones registered between the two, innermost
// first. A statement at the same environment as its enclosing one reuses the
// enclosing site unchanged.
fn lower_panic_site(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, function: U64, environment: U64, boundary: U64, shared: U64) -> Result(LowerStep, __s0_Error) {
    if shared == 0 || environment == 0 || environment == boundary { return Ok(LowerStep(state: state, id: shared)) }
    if !lower_cleanup_active(store, owner, environment, boundary) { return Ok(LowerStep(state: state, id: shared)) }
    let site = try lower_add_block(d, state, function, "bb_cleanup_panic")
    let cleaned = try lower_cleanup_exits(d, source_state, store, lower_with_mir(state, site.state.mir), owner, function, site.id, environment, boundary, 1)
    let jumped = try lower_jump(d, cleaned, function, site.id, shared)
    return Ok(LowerStep(state: jumped, id: site.id))
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
    if boundary_environment == 0 && exit_kind != 1 && state.has_storage && lower_closure_site_for(store, owner) == 0 {
        let domain = lower_domain_value(current, store, owner)
        if domain == 0 { return Ok(lower_invalid(current)) }
        let destroyed = try lower_add_instr(d, current, function, block, mir_op_domain_destroy(), 0, 0, 0, domain, 0, 0, "")
        current = destroyed.state
    }
    return Ok(current)
}

// Statement chains are reverse-stored: .next points at the prior source
// statement, so the chain head is the last statement in source order.
// Integer walks replace both recursion and a loop-carried collect buffer:
// `__s0_buffer_new` is a function-local domain allocation, and carrying that
// handle across a while backedge is rejected by MIR Phase 6.
fn lower_chain_len(store: CheckStore, link_id: U64) -> U64 {
    var count: U64 = 0
    var current_id = link_id
    while current_id != 0 {
        if current_id > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return 0 }
        count = count + 1
        current_id = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, current_id - 1).next
    }
    return count
}

fn lower_chain_nth(store: CheckStore, link_id: U64, skip: U64) -> U64 {
    var current_id = link_id
    var at: U64 = 0
    while at < skip {
        if current_id == 0 || current_id > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) { return 0 }
        current_id = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, current_id - 1).next
        at = at + 1
    }
    return current_id
}

fn lower_chain_environment(d: Domain, store: CheckStore, owner: U64, link_id: U64, initial: U64) -> Result(U64, __s0_Error) {
    var environment = initial
    var at = lower_chain_len(store, link_id)
    while at > 0 {
        let walked_id = lower_chain_nth(store, link_id, at - 1)
        if walked_id != 0 && walked_id <= __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
            let walked_link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, walked_id - 1)
            if walked_link.statement != 0 && walked_link.statement <= __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, walked_link.statement - 1)
                if statement.owner == owner && statement.environment == environment {
                    if statement.kind == 1 || statement.kind == 2 || statement.kind == 10 {
                        var found: U64 = 0
                        var search_at: U64 = 0
                        while search_at < __s0_buffer_len(EnvironmentRec, store.environments) {
                            if found == 0 {
                                let candidate = __s0_buffer_get(EnvironmentRec, store.environments, search_at)
                                if candidate.owner == owner && candidate.parent == environment && candidate.binding == statement.binding { found = search_at + 1 }
                            }
                            search_at = search_at + 1
                        }
                        if found != 0 { environment = found }
                    }
                }
            }
        }
        at = at - 1
    }
    return Ok(environment)
}

// The element place of `base[index_expression]`. The checker rejects a
// non-place base before this runs; `base_is_root` says the base place is the
// root binding itself, whose MIR storage type comes from the local (a
// reference for a mut parameter) rather than from the checked type.
fn lower_index_place(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, base: MirBuildStep, base_type: U64, index_expression: U64, root_local: U64, base_is_root: Bool, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    var current = state
    var container_mir: U64 = 0
    if root_local == 0 || root_local > __s0_buffer_len(LocalRec, store.locals) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    let place_root_local = __s0_buffer_get(LocalRec, store.locals, root_local - 1)
    let container = __s0_buffer_get(CheckedTypeRec, store.types, base_type - 1)
    if (container.kind != 8 && container.kind != 15 && container.kind != 17 && container.kind != 18) || container.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    // A local base keeps the local's storage type, which for a
    // reference-initialized binding is a mutable reference rather than the
    // value type. A projected base stores its own checked type.
    if base_is_root {
        let lowered_root = try lower_local_type(d, source_state, store, current, owner, root_local, place_root_local)
        current = lowered_root.state
        container_mir = lowered_root.id
    } else {
        let lowered_base = try lower_type(d, source_state, store, current, base_type)
        current = lowered_base.state
        container_mir = lowered_base.id
    }
    if container_mir == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    var sequence_value: U64 = 0
    if container.kind == 8 || container.kind == 18 || container.kind == 17 {
        let loaded = try lower_add_typed_result(d, current, function, block, container_mir)
        let load = try lower_add_instr(d, loaded.state, function, block, mir_op_load(), loaded.id, base.id, 0, 0, 0, 0, "")
        current = load.state
        sequence_value = loaded.id
        if container.kind == 17 {
            let elem_checked = __s0_buffer_get(U64, store.type_args, container.first_arg - 1)
            let elem = try lower_type(d, source_state, store, current, elem_checked)
            let empty_view = try __s0_buffer_new(U64, d)
            let view_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty_view, 0)
            let view = try lower_add_typed_result(d, lower_with_mir(elem.state, view_type.store), function, block, view_type.type_id)
            let converted = try lower_add_instr(d, view.state, function, block, mir_op_vec_as_mut_slice(), view.id, 0, 0, loaded.id, 0, 0, "")
            current = converted.state
            sequence_value = view.id
        }
    } else {
        let empty_ref = try __s0_buffer_new(U64, d)
        let ref_type = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), container_mir, 0, 0, empty_ref, 0)
        let borrowed = try lower_add_typed_result(d, lower_with_mir(current, ref_type.store), function, block, ref_type.type_id)
        let borrow = try lower_add_instr(d, borrowed.state, function, block, mir_op_borrow_mut(), borrowed.id, base.id, 0, 0, 0, 0, "")
        current = borrow.state
        sequence_value = borrowed.id
    }
    let index = try lower_expression(d, source_state, spans, store, current, owner, function, block, index_expression, environment, panic_block)
    let active = lower_open_block(index.state.mir, function, block)
    let elem_checked = __s0_buffer_get(U64, store.type_args, container.first_arg - 1)
    let elem = try lower_type(d, source_state, store, index.state, elem_checked)
    let empty = try __s0_buffer_new(U64, d)
    let ref_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty, 0)
    let result = try mir_add_value(d, ref_type.store, function, try lower_result_name(d, ref_type.store, function, ""), ref_type.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(ref_type.store, function, active) + 1)
    var index_op = mir_op_slice_index_checked()
    if container.kind == 15 { index_op = mir_op_array_index_checked() }
    let indexed = try lower_add_instr(d, lower_with_mir(elem.state, result.store), function, active, index_op, result.id, 0, 0, sequence_value, index.id, panic_block, "")
    let deref = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: result.id))
    return Ok(LowerStep(state: lower_with_mir(indexed.state, deref.store), id: deref.id))
}

fn lower_checked_place(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, place_id: U64, nested: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if place_id == 0 || place_id > __s0_buffer_len(CheckedPlaceRec, store.control.places) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let checked = __s0_buffer_get(CheckedPlaceRec, store.control.places, place_id - 1)
    if checked.owner != owner { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let binding = lower_binding_lookup(state, checked.root)
    if binding.binding == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let place_root_local = __s0_buffer_get(LocalRec, store.locals, checked.root - 1)
    let root_type_checked = __s0_buffer_get(CheckedTypeRec, store.types, place_root_local.checked_type - 1)
    // A by-value parameter has no slot to store into, so it is a place only
    // as the root of a table-view field projection. As the base of a longer
    // chain it is legal: the enclosing projection is the one being checked.
    if binding.parameter == 1 && nested == 0 && (checked.kind != 2 || (root_type_checked.kind != 21 && root_type_checked.kind != 22)) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    // A place is a chain: the projection base is the enclosing place, or the
    // root binding itself when the chain starts here.
    var base: MirBuildStep = MirBuildStep(store: state.mir, id: 0)
    var base_type: U64 = place_root_local.checked_type
    var current = state
    if checked.base == 0 {
        if binding.parameter == 0 { base = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0)) } else {
            base = try mir_add_place(d, state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: binding.mir_id))
        }
        current = lower_with_mir(state, base.store)
    } else {
        let inner = try lower_checked_place(d, source_state, spans, store, state, owner, function, block, checked.base, 1, environment, panic_block)
        if inner.id == 0 { return Ok(LowerStep(state: lower_invalid(inner.state), id: 0)) }
        base = MirBuildStep(store: inner.state.mir, id: inner.id)
        base_type = __s0_buffer_get(CheckedPlaceRec, store.control.places, checked.base - 1).checked_type
        current = inner.state
    }
    if checked.kind == 1 { return Ok(LowerStep(state: current, id: base.id)) }
    if checked.kind == 2 {
        if checked.field == 0 || checked.field > __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
        let field = __s0_buffer_get(DeclTypeUseRec, store.uses, checked.field - 1)
        let named = try mir_append_name(d, current.mir, try lower_source_word(d, source_state, field.source, field.name_start, field.name_end))
        let result = try mir_add_place(d, named.store, MirPlaceRec(function: function, kind: mir_place_field(), local: 0, base: base.id, field_start: named.start, field_end: named.end, deref_value: 0))
        return Ok(LowerStep(state: lower_with_mir(current, result.store), id: result.id))
    }
    if checked.kind != 3 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    var base_is_local = checked.base == 0
    if checked.base != 0 { base_is_local = __s0_buffer_get(CheckedPlaceRec, store.control.places, checked.base - 1).kind == 1 }
    return lower_index_place(d, source_state, spans, store, current, owner, function, block, base, base_type, checked.index, checked.root, base_is_local, environment, panic_block)
}

// The place a mutating collection operation writes its rebuilt header back
// through. The checker records the receiver binding or the field or element
// path into it, so a `mut self` receiver and a field of a local both store
// back into the storage the caller owns.
fn lower_receiver_place(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, place_id: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if place_id == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    return lower_checked_place(d, source_state, spans, store, state, owner, function, block, place_id, 0, environment, panic_block)
}

fn lower_block_statements(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, checked_block: U64, panic_block: U64, panic_environment: U64) -> Result(LowerFlowStep, __s0_Error) {
    if checked_block == 0 || checked_block > __s0_buffer_len(CheckedBlockRec, store.control.blocks) { return Ok(LowerFlowStep(state: lower_invalid(state), block: block, terminated: true)) }
    let body = __s0_buffer_get(CheckedBlockRec, store.control.blocks, checked_block - 1)
    if body.owner != owner { return Ok(LowerFlowStep(state: lower_invalid(state), block: block, terminated: true)) }
    let flow = try lower_statement_chain(d, source_state, spans, store, state, owner, function, block, body.statements, panic_block, panic_environment)
    if flow.terminated { return Ok(flow) }
    let exit_environment = try lower_chain_environment(d, store, owner, body.statements, body.environment)
    let cleaned = try lower_cleanup_exits(d, source_state, store, flow.state, owner, function, flow.block, exit_environment, body.environment, 1)
    return Ok(LowerFlowStep(state: cleaned, block: flow.block, terminated: false))
}

fn lower_one_statement(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, statement: CheckedStatementRec, link: CheckedStatementLinkRec, panic_block: U64, panic_environment: U64) -> Result(LowerFlowStep, __s0_Error) {
    var current = state
    var active = block
    if statement.owner != owner { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
    // A checked failure anywhere in this statement leaves every enclosing
    // registration, so the panic target runs the crossed ones first.
    let panic_site = try lower_panic_site(d, source_state, store, current, owner, function, statement.environment, panic_environment, panic_block)
    current = panic_site.state
    let panic_here = panic_site.id
    let panic_env_here = statement.environment
    if statement.kind == 1 || statement.kind == 2 {
        let value = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_here)
        active = lower_open_block(value.state.mir, function, active)
        current = try lower_store_binding(d, value.state, function, active, statement.binding, value.id)
        return Ok(LowerFlowStep(state: current, block: active, terminated: false))
    }
    if statement.kind == 3 {
        let place = try lower_checked_place(d, source_state, spans, store, current, owner, function, active, statement.place, 0, statement.environment, panic_here)
        let value = try lower_expression(d, source_state, spans, store, place.state, owner, function, active, statement.expression, statement.environment, panic_here)
        active = lower_open_block(value.state.mir, function, active)
        current = value.state
        var stored_value = value.id
        // Replacing storage through a borrowed place materializes the value
        // in the domain that owns the place. A value already read from the
        // same place needs no second copy.
        let target_owner = lower_borrowed_place_owner_domain(value.state, store, statement.place)
        if target_owner != 0 {
            let rhs_root = lower_checked_expression_root(store, statement.expression)
            let place_root = __s0_buffer_get(CheckedPlaceRec, store.control.places, statement.place - 1).root
            if rhs_root == 0 || rhs_root != place_root {
                let rhs_expression = __s0_buffer_get(CheckedExprRec, store.expressions, statement.expression - 1)
                let typ = try lower_type(d, source_state, store, value.state, rhs_expression.checked_type)
                if typ.state.valid && typ.state.has_storage && (try lower_mir_type_copy_relocatable(d, typ.state.mir, typ.id)) {
                    let result = try lower_add_typed_result(d, typ.state, function, active, typ.id)
                    let copied = try lower_add_instr(d, result.state, function, active, mir_op_copy_to_domain(), result.id, 0, 0, target_owner, value.id, 0, "")
                    stored_value = result.id
                    active = lower_open_block(copied.state.mir, function, active)
                    current = copied.state
                }
            }
        }
        let instr = try lower_add_instr(d, current, function, active, mir_op_store(), 0, place.id, 0, stored_value, 0, 0, "")
        return Ok(LowerFlowStep(state: instr.state, block: active, terminated: false))
    }
    if statement.kind == 11 {
        // break: run every registration this jump crosses, innermost first,
        // then leave the innermost enclosing loop.
        if current.loop_exit == 0 { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
        let cleaned = try lower_cleanup_exits(d, source_state, store, current, owner, function, active, statement.environment, current.loop_environment, 1)
        if !cleaned.valid { return Ok(LowerFlowStep(state: cleaned, block: active, terminated: true)) }
        let jumped = try lower_jump(d, cleaned, function, active, cleaned.loop_exit)
        return Ok(LowerFlowStep(state: jumped, block: active, terminated: true))
    }
    if statement.kind == 12 {
        // continue: run every registration this jump crosses, innermost first,
        // then start the next iteration of the innermost enclosing loop.
        if current.loop_step == 0 { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
        let cleaned = try lower_cleanup_exits(d, source_state, store, current, owner, function, active, statement.environment, current.loop_environment, 1)
        if !cleaned.valid { return Ok(LowerFlowStep(state: cleaned, block: active, terminated: true)) }
        let jumped = try lower_jump(d, cleaned, function, active, cleaned.loop_step)
        return Ok(LowerFlowStep(state: jumped, block: active, terminated: true))
    }
    if statement.kind == 4 {
        var value: U64 = 0
        if statement.expression != 0 {
            let lowered = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_here)
            let expression = __s0_buffer_get(CheckedExprRec, store.expressions, statement.expression - 1)
            let retained = try lower_copy_result_storage(d, source_state, store, lowered.state, owner, function, active, statement.expression, expression.checked_type, lowered.id)
            current = retained.state
            value = retained.id
            active = lower_open_block(current.mir, function, active)
        }
        current = try lower_cleanup_exits(d, source_state, store, current, owner, function, active, statement.environment, 0, 2)
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: active, kind: mir_term_return(), value: value, target: 0, then_block: 0, else_block: 0))
        return Ok(LowerFlowStep(state: lower_with_mir(current, term.store), block: active, terminated: true))
    }
    if statement.kind == 5 {
        let lowered = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_here)
        current = lowered.state
        active = lower_open_block(current.mir, function, active)
        // A resolved core.panic.panic call terminates the process inside the
        // callee. The end of this block is unreachable and no cleanup runs on
        // the panic path, matching the core.panic contract.
        if checked_panic_statement(source_state, store, statement.expression) {
            let unreachable = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: active, kind: mir_term_unreachable(), value: 0, target: 0, then_block: 0, else_block: 0))
            return Ok(LowerFlowStep(state: lower_with_mir(current, unreachable.store), block: active, terminated: true))
        }
        if checked_match_statement_diverges(source_state, store, statement.expression) {
            return Ok(LowerFlowStep(state: current, block: active, terminated: true))
        }
        return Ok(LowerFlowStep(state: current, block: active, terminated: false))
    }
    if statement.kind == 6 {
        return lower_block_statements(d, source_state, spans, store, current, owner, function, active, statement.body, panic_here, panic_env_here)
    }
    if statement.kind == 7 {
        let condition = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_here)
        active = lower_open_block(condition.state.mir, function, active)
        let then_block = try lower_add_block(d, condition.state, function, "bb_then")
        let else_block = try lower_add_block(d, then_block.state, function, "bb_else")
        let join = try lower_add_block(d, else_block.state, function, "bb_join")
        current = try lower_branch(d, join.state, function, active, condition.id, then_block.id, else_block.id)
        let then_flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, then_block.id, statement.body, panic_here, panic_env_here)
        current = then_flow.state
        if !then_flow.terminated { current = try lower_jump(d, current, function, then_flow.block, join.id) }
        var else_flow = LowerFlowStep(state: current, block: else_block.id, terminated: false)
        if statement.alternative != 0 { else_flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, else_block.id, statement.alternative, panic_here, panic_env_here) }
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
        let condition = try lower_expression(d, source_state, spans, store, current, owner, function, head.id, statement.expression, statement.environment, panic_here)
        let condition_block = lower_open_block(condition.state.mir, function, head.id)
        current = try lower_branch(d, condition.state, function, condition_block, condition.id, body.id, join.id)
        let body_flow = try lower_block_statements(d, source_state, spans, store, lower_with_loop(current, join.id, head.id, statement.environment), owner, function, body.id, statement.body, panic_here, panic_env_here)
        current = body_flow.state
        if !body_flow.terminated { current = try lower_jump(d, current, function, body_flow.block, head.id) }
        return Ok(LowerFlowStep(state: lower_with_loop(current, state.loop_exit, state.loop_step, state.loop_environment), block: join.id, terminated: false))
    }
    if statement.kind == 9 {
        let sequence = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_here)
        let sequence_expression = __s0_buffer_get(CheckedExprRec, store.expressions, statement.expression - 1)
        let sequence_type = __s0_buffer_get(CheckedTypeRec, store.types, sequence_expression.checked_type - 1)
        if sequence_type.kind != 8 && sequence_type.kind != 15 && sequence_type.kind != 16 && sequence_type.kind != 17 && sequence_type.kind != 18 { return Ok(LowerFlowStep(state: lower_invalid(sequence.state), block: active, terminated: true)) }
        if sequence_type.kind != 16 && sequence_type.arg_count != 1 { return Ok(LowerFlowStep(state: lower_invalid(sequence.state), block: active, terminated: true)) }
        // The loop parameter carries the sequence value itself. An array or
        // vector converts to its slice view once before the loop for the
        // length bound, and the body re-derives the view from the carried
        // owner each iteration, so the loop-carried parameter is an owning
        // value rather than a view.
        let sequence_param_base = try lower_type(d, source_state, store, sequence.state, sequence_expression.checked_type)
        let sequence_param_type_id = sequence_param_base.id
        var length_operand = sequence.id
        var length_state = sequence.state
        if sequence_type.kind == 15 || sequence_type.kind == 17 {
            let elem_checked = __s0_buffer_get(U64, store.type_args, sequence_type.first_arg - 1)
            let elem = try lower_type(d, source_state, store, sequence.state, elem_checked)
            let empty_view = try __s0_buffer_new(U64, d)
            let view_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_slice(), elem.id, 0, 0, empty_view, 0)
            let view = try lower_add_typed_result(d, lower_with_mir(elem.state, view_type.store), function, active, view_type.type_id)
            var op = mir_op_array_as_slice()
            if sequence_type.kind == 17 { op = mir_op_vec_as_slice() }
            let converted = try lower_add_instr(d, view.state, function, active, op, view.id, 0, 0, sequence.id, 0, 0, "")
            length_operand = view.id
            length_state = converted.state
        }
        // slice.len always returns canonical U64 (checked type 9 in the sealed primitive prefix).
        let length_value = try lower_add_result(d, length_state, function, active, 9, source_state, store)
        let length_instr = try lower_add_instr(d, length_value.state, function, active, mir_op_slice_len(), length_value.id, 0, 0, length_operand, 0, 0, "")
        // The sequence-lowering constant name space cannot collide with a
        // statement-keyed literal name, and two for statements in one function
        // must not share either.
        let zero_value = try lower_int_value_seq(d, source_state, store, length_instr.state, function, active, 0)
        // Capture the loop entry block before the head/body/step/join blocks
        // exist: a sequence expression that lowered control flow (ordered
        // projections and calls) has already terminated the entry block, and
        // the last open block at this point is where the sequence value and
        // its length live, so the head jump must leave exactly that block.
        // With a sequence that lowered in place this is the entry block.
        let sequence_block = lower_open_block(zero_value.state.mir, function, active)
        let head = try lower_add_block(d, zero_value.state, function, "bb_for_head")
        let body = try lower_add_block(d, head.state, function, "bb_for_body")
        // `continue` jumps to the step block, which advances the index and
        // returns to the head; the body's own tail jumps there too, so a
        // continue never skips the increment.
        let step = try lower_add_block(d, body.state, function, "bb_for_step")
        let join = try lower_add_block(d, step.state, function, "bb_for_join")
        // Parameter names carry the head block so two for statements in one
        // function do not produce duplicate value names.
        let index_param = try mir_add_block_param(d, join.state.mir, function, head.id, 0, try lower_decimal_name(d, "__for_index_", head.id), mir_type_u64())
        let sequence_param = try mir_add_block_param(d, index_param.store, function, head.id, 1, try lower_decimal_name(d, "__for_sequence_", head.id), sequence_param_type_id)
        current = try lower_jump_two(d, lower_with_mir(current, sequence_param.store), function, sequence_block, head.id, zero_value.id, sequence.id)
        let compared = try lower_add_result(d, current, function, head.id, 1, source_state, store)
        let compare = try lower_add_instr(d, compared.state, function, head.id, mir_op_int_lt(), compared.id, 0, 0, index_param.id, length_value.id, 0, "")
        current = try lower_branch(d, compare.state, function, head.id, compared.id, body.id, join.id)
        var elem_checked: U64 = 6
        if sequence_type.kind == 8 || sequence_type.kind == 15 || sequence_type.kind == 17 || sequence_type.kind == 18 { elem_checked = __s0_buffer_get(U64, store.type_args, sequence_type.first_arg - 1) }
        let elem = try lower_type(d, source_state, store, current, elem_checked)
        let empty = try __s0_buffer_new(U64, d)
        let view_type = try mir_intern_type(d, elem.state.mir, mir_type_kind_slice(), elem.id, 0, 0, empty, 0)
        var index_sequence = sequence_param.id
        if sequence_type.kind == 15 || sequence_type.kind == 17 {
            // Re-derive the immutable view from the carried owner each
            // iteration; the loop parameter stays an owning value.
            let view_value = try lower_add_typed_result(d, lower_with_mir(elem.state, view_type.store), function, body.id, view_type.type_id)
            var view_op = mir_op_array_as_slice()
            if sequence_type.kind == 17 { view_op = mir_op_vec_as_slice() }
            let view_made = try lower_add_instr(d, view_value.state, function, body.id, view_op, view_value.id, 0, 0, sequence_param.id, 0, 0, "")
            index_sequence = view_value.id
            current = view_made.state
        }
        let ref_type = try mir_intern_type(d, current.mir, mir_type_kind_safe_mut(), elem.id, 0, 0, empty, 0)
        let ref_value = try mir_add_value(d, ref_type.store, function, try lower_result_name(d, ref_type.store, function, "for_ref"), ref_type.type_id, mir_value_def_instruction(), body.id, lower_instruction_ordinal(ref_type.store, function, body.id) + 1)
        let indexed = try lower_add_instr(d, lower_with_mir(elem.state, ref_value.store), function, body.id, mir_op_slice_index_checked(), ref_value.id, 0, 0, index_sequence, index_param.id, panic_here, "")
        let deref = try mir_add_place(d, indexed.state.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: ref_value.id))
        let element_value = try lower_add_result(d, lower_with_mir(indexed.state, deref.store), function, body.id, elem_checked, source_state, store)
        let loaded = try lower_add_instr(d, element_value.state, function, body.id, mir_op_load(), element_value.id, deref.id, 0, 0, 0, 0, "")
        let copied = try lower_move_or_copy(d, source_state, spans, store, loaded.state, owner, function, body.id, statement.expression, elem_checked, element_value.id, statement.expression, 0)
        current = try lower_store_binding(d, copied.state, function, body.id, statement.binding, copied.id)
        let body_flow = try lower_block_statements(d, source_state, spans, store, lower_with_loop(current, join.id, step.id, statement.environment), owner, function, body.id, statement.body, panic_here, panic_env_here)
        current = body_flow.state
        if !body_flow.terminated { current = try lower_jump(d, current, function, body_flow.block, step.id) }
        let one = try lower_int_value_seq(d, source_state, store, current, function, step.id, 1)
        let next = try lower_add_result(d, one.state, function, step.id, 9, source_state, store)
        let added = try lower_add_instr(d, next.state, function, step.id, mir_op_int_add_checked(), next.id, 0, 0, index_param.id, one.id, panic_here, "")
        current = try lower_jump_two(d, added.state, function, lower_open_block(added.state.mir, function, step.id), head.id, next.id, sequence_param.id)
        return Ok(LowerFlowStep(state: lower_with_loop(current, state.loop_exit, state.loop_step, state.loop_environment), block: join.id, terminated: false))
    }
    if statement.kind == 10 {
        let value = try lower_expression(d, source_state, spans, store, current, owner, function, active, statement.expression, statement.environment, panic_here)
        active = lower_open_block(value.state.mir, function, active)
        current = try lower_store_binding(d, value.state, function, active, statement.binding, value.id)
        let cleanup = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, statement.body - 1)
        // A nominal Cleanup hook takes the owner by `take self`; register the
        // owner's local place so the scope-exit run loads the current value,
        // not the registration-time copy. Builtin releases (table, c_string)
        // and the Vec element drain keep their capture semantics.
        var owner_place: U64 = 0
        if cleanup.callback != 0 {
            let initializer = __s0_buffer_get(CheckedExprRec, store.expressions, cleanup.initializer - 1)
            let owner_type = __s0_buffer_get(CheckedTypeRec, store.types, initializer.checked_type - 1)
            if owner_type.kind == 7 {
                let mapped = lower_binding_lookup(current, statement.binding)
                if mapped.binding != 0 && mapped.parameter == 0 {
                    let placed = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: mapped.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
                    owner_place = placed.id
                    current = lower_with_mir(current, placed.store)
                }
            }
        }
        let empty = try __s0_buffer_new(U64, d)
        let scope_type = try mir_intern_type(d, current.mir, mir_type_kind_cleanup_scope(), 0, 0, 0, empty, 0)
        let scope_value = try mir_add_value(d, scope_type.store, function, try lower_result_name(d, scope_type.store, function, try lower_decimal_name(d, "cleanup_scope", statement.binding)), scope_type.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(scope_type.store, function, active) + 1)
        let begun = try lower_add_instr(d, lower_with_mir(current, scope_value.store), function, active, mir_op_cleanup_scope_begin(), scope_value.id, 0, 0, 0, 0, 0, "")
        let cleanup_type = try mir_intern_type(d, begun.state.mir, mir_type_kind_cleanup_id(), 0, 0, 0, empty, 0)
        let cleanup_value = try mir_add_value(d, cleanup_type.store, function, try lower_result_name(d, cleanup_type.store, function, try lower_decimal_name(d, "cleanup_id", statement.binding)), cleanup_type.type_id, mir_value_def_instruction(), active, lower_instruction_ordinal(cleanup_type.store, function, active) + 1)
        var callback = lower_owner_lookup(current.owners, cleanup.callback)
        var vec_drain = false
        if cleanup.callback == 0 {
            // Builtin owner cleanup: a Table registration pushes the
            // pre-synthesized release function for its table type, and an
            // affine-element Vec registration pushes the pre-synthesized
            // per-element drain for its vector type. Both are created once,
            // before body lowering, so per-record ordinals stay append-only
            // per function.
            let initializer = __s0_buffer_get(CheckedExprRec, store.expressions, cleanup.initializer - 1)
            let owner_type = __s0_buffer_get(CheckedTypeRec, store.types, initializer.checked_type - 1)
            let owner_step = try lower_type(d, source_state, store, current, initializer.checked_type)
            if !owner_step.state.valid { return Ok(LowerFlowStep(state: owner_step.state, block: active, terminated: true)) }
            if owner_type.kind == 17 {
                vec_drain = true
                let drain_name = try lower_decimal_name(d, "__alder_vec_drain_", owner_step.id)
                callback = lower_release_function_named(current.mir, drain_name)
            } else {
                if owner_type.kind == 31 {
                    // The c_string shell is pre-synthesized in the shell
                    // pre-pass, so the registration only looks it up here.
                    let release_name = try lower_decimal_name(d, "__alder_cstring_release_", owner_step.id)
                    callback = lower_release_function_named(current.mir, release_name)
                } else { if owner_type.kind == 33 {
                    let release_name = try lower_decimal_name(d, "__alder_callback_owner_release_", owner_step.id)
                    callback = lower_release_function_named(current.mir, release_name)
                } else {
                let release_name = try lower_decimal_name(d, "__alder_table_release_", owner_step.id)
                callback = lower_release_function_named(current.mir, release_name)
                } }
            }
        }
        if callback == 0 { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
        let pushed = try lower_add_instr(d, lower_with_mir(begun.state, cleanup_value.store), function, active, mir_op_cleanup_push(), cleanup_value.id, owner_place, 0, scope_value.id, 0, callback, "")
        current = pushed.state
        var cleanup_ordinal: U64 = 0
        if (cleanup.callback != 0 || vec_drain) && state.has_storage && !lower_owner_aliases_domain(source_state, store, cleanup.callback) {
            let domain = lower_domain_value(current, store, owner)
            if domain == 0 { return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)) }
            current = try lower_add_instr_operand(d, current, pushed.id, 0, domain, mir_operand_instruction(), "")
            cleanup_ordinal = 1
        }
        current = try lower_add_instr_operand(d, current, pushed.id, cleanup_ordinal, value.id, mir_operand_instruction(), "")
        let scopes = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: statement.binding, value: scope_value.id))
        let releases = try __s0_buffer_append(LowerValueMapRec, d, current.releases, LowerValueMapRec(expression: statement.binding, value: cleanup_value.id))
        current = lower_with_releases(lower_with_values(current, scopes), releases)
        return Ok(LowerFlowStep(state: current, block: active, terminated: false))
    }
    return Ok(LowerFlowStep(state: lower_invalid(current), block: active, terminated: true))
}

// lower_diverging_match_arm lowers one `=> return ...` arm of a match: the
// checked return statement executes inside the arm region, running every
// cleanup registration it crosses, and terminates the arm block. Nothing
// reaches the match join from here, so the join parameter is fed only by the
// match's value-producing arms.
fn lower_diverging_match_arm(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, arm: CheckedMatchArmRec, environment: U64, panic_block: U64) -> Result(LowerState, __s0_Error) {
    if arm.statement == 0 || arm.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) { return Ok(lower_invalid(state)) }
    let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, arm.statement - 1)
    if statement.owner != owner { return Ok(lower_invalid(state)) }
    let link = CheckedStatementLinkRec(statement: 0, next: 0)
    let flow = try lower_one_statement(d, source_state, spans, store, state, owner, function, block, statement, link, panic_block, environment)
    if !flow.state.valid || !flow.terminated { return Ok(lower_invalid(flow.state)) }
    return Ok(flow.state)
}

fn lower_statement_chain(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, link_id: U64, panic_block: U64, panic_environment: U64) -> Result(LowerFlowStep, __s0_Error) {
    var current = state
    var active = block
    var at = lower_chain_len(store, link_id)
    var stopped: U64 = 0
    var last: LowerFlowStep = LowerFlowStep(state: state, block: block, terminated: false)
    while at > 0 {
        let walked_id = lower_chain_nth(store, link_id, at - 1)
        var next = last
        if walked_id == 0 || walked_id > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
            next = LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)
        }
        if walked_id != 0 && walked_id <= __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
            let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, walked_id - 1)
            if !current.valid || link.statement == 0 || link.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                next = LowerFlowStep(state: lower_invalid(current), block: active, terminated: true)
            }
            if current.valid && link.statement != 0 && link.statement <= __s0_buffer_len(CheckedStatementRec, store.control.statements) {
                let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, link.statement - 1)
                next = try lower_one_statement(d, source_state, spans, store, current, owner, function, active, statement, link, panic_block, panic_environment)
            }
        }
        last = next
        current = next.state
        active = next.block
        if next.terminated { stopped = 1 }
        if stopped == 0 { at = at - 1 }
        if stopped != 0 { at = 0 }
    }
    return Ok(last)
}

fn lower_binding_statement_indexes(d: Domain, store: CheckStore) -> Result(__s0_Buffer(U64), __s0_Error) {
    let local_count = __s0_buffer_len(LocalRec, store.locals)
    var first = __s0_alloc(U64, d, local_count + 1)
    var at: U64 = 0
    while at <= local_count { first[at] = 0
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if (statement.kind == 1 || statement.kind == 2) && statement.binding >= 1 && statement.binding <= local_count && first[statement.binding] == 0 { first[statement.binding] = at + 1 }
        at = at + 1
    }
    var indexes = try __s0_buffer_new(U64, d)
    at = 1
    while at <= local_count { indexes = try __s0_buffer_append(U64, d, indexes, first[at])
        at = at + 1
    }
    return Ok(indexes)
}

fn lower_local_type(d: Domain, source_state: State, store: CheckStore, state: LowerState, owner: U64, binding: U64, local: LocalRec) -> Result(LowerStep, __s0_Error) {
    let ordinary = try lower_type(d, source_state, store, state, local.checked_type)
    if local.kind != 2 { return Ok(ordinary) }
    if binding >= 1 && binding <= __s0_buffer_len(U64, state.binding_statements) { let statement_id = __s0_buffer_get(U64, state.binding_statements, binding - 1)
        if statement_id != 0 { let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_id - 1)
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
        }
    }
    return Ok(ordinary)
}

fn lower_local_name_seen(source_state: State, store: CheckStore, locals: LowerLocalIndex, start: U64, ordinal: U64, local: LocalRec) -> Bool {
    var at: U64 = 0
    while at < ordinal {
        let prior = __s0_buffer_get(LocalRec, store.locals, __s0_buffer_get(U64, locals.ids, start + at) - 1)
        if prior.kind != 1 && same_name(source_state, local.source, local.name_start, local.name_end, prior.source, prior.name_start, prior.name_end) { return true }
        at = at + 1
    }
    return false
}

fn lower_local_indexes(d: Domain, store: CheckStore) -> Result(LowerLocalIndex, __s0_Error) {
    let owner_count = __s0_buffer_len(SymbolRec, store.symbols)
    let local_count = __s0_buffer_len(LocalRec, store.locals)
    var counts = __s0_alloc(U64, d, owner_count + 1)
    var starts = __s0_alloc(U64, d, owner_count + 1)
    var cursor = __s0_alloc(U64, d, owner_count + 1)
    var owner: U64 = 0
    while owner <= owner_count { counts[owner] = 0
        starts[owner] = 0
        cursor[owner] = 0
        owner = owner + 1 }
    var at: U64 = 0
    while at < local_count {
        let item_owner = __s0_buffer_get(LocalRec, store.locals, at).owner
        if item_owner >= 1 && item_owner <= owner_count { counts[item_owner] = counts[item_owner] + 1 }
        at = at + 1
    }
    var running: U64 = 0
    owner = 1
    while owner <= owner_count { starts[owner - 1] = running
        cursor[owner] = running
        running = running + counts[owner]
        owner = owner + 1 }
    starts[owner_count] = running
    var ids = __s0_alloc(U64, d, running)
    at = 0
    while at < local_count {
        let item_owner = __s0_buffer_get(LocalRec, store.locals, at).owner
        if item_owner >= 1 && item_owner <= owner_count { ids[cursor[item_owner]] = at + 1
            cursor[item_owner] = cursor[item_owner] + 1 }
        at = at + 1
    }
    var start_buf = try __s0_buffer_new(U64, d)
    owner = 0
    while owner <= owner_count { start_buf = try __s0_buffer_append(U64, d, start_buf, starts[owner])
        owner = owner + 1 }
    var id_buf = try __s0_buffer_new(U64, d)
    at = 0
    while at < running { id_buf = try __s0_buffer_append(U64, d, id_buf, ids[at])
        at = at + 1 }
    return Ok(LowerLocalIndex(starts: start_buf, ids: id_buf))
}

fn lower_root_indexes(d: Domain, store: CheckStore) -> Result(__s0_Buffer(LowerOwnerMapRec), __s0_Error) {
    let block_count = __s0_buffer_len(CheckedBlockRec, store.control.blocks)
    var parents = __s0_alloc(U64, d, block_count + 1)
    var at: U64 = 0
    while at <= block_count { parents[at] = 0
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if statement.kind != 10 && statement.body >= 1 && statement.body <= block_count { parents[statement.body] = parents[statement.body] + 1 }
        if statement.alternative >= 1 && statement.alternative <= block_count { parents[statement.alternative] = parents[statement.alternative] + 1 }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) {
        // A statement-arm block is parented by its match arm and is lowered
        // from the arm, never as a function root.
        let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, at)
        if arm.block >= 1 && arm.block <= block_count { parents[arm.block] = parents[arm.block] + 1 }
        at = at + 1
    }
    var roots = try __s0_buffer_new(LowerOwnerMapRec, d)
    at = 0
    while at < block_count {
        let block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if parents[at + 1] == 0 { roots = try __s0_buffer_append(LowerOwnerMapRec, d, roots, LowerOwnerMapRec(owner: block.owner, mir_id: at + 1)) }
        at = at + 1
    }
    return Ok(roots)
}

fn lower_function(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, locals: LowerLocalIndex, state: LowerState, owner: U64) -> Result(LowerState, __s0_Error) {
    let function = lower_owner_lookup(state.owners, owner)
    if function == 0 { return Ok(lower_invalid(state)) }
    let root_block = lower_owner_lookup(state.roots, owner)
    if root_block == 0 { return Ok(lower_invalid(state)) }
    // D023: decide this function's movable reads once, before any body
    // lowering; copy sites then consult the flat verdict buffer.
    let analyzed = try lower_move_analyze(d, store, owner, root_block, state.moves)
    let planned = lower_with_plan(state, analyzed)
    // Closure thunks: captures are checked as trailing parameters but lower
    // as locals unpacked from the environment parameter, so the thunk's C
    // ABI stays (declared parameters..., opaque environment pointer).
    let closure_site = lower_closure_site_for(store, owner)
    var declared_params: U64 = 0
    var bare_thunk = false
    if closure_site != 0 {
        let site = __s0_buffer_get(ClosureSiteRec, store.closures.sites, closure_site - 1)
        declared_params = site.declared_count
        // A thunk with no environment record has nowhere to carry a domain,
        // so it takes the caller's domain as its leading parameter, exactly
        // as a named function value does.
        if site.capture_count == 0 { bare_thunk = true }
    }
    var current = planned
    var param_ordinal: U64 = 0
    // A capturing closure's thunk receives its domain inside the environment
    // record; a bare thunk receives it as the leading parameter.
    let hidden_domain = state.has_storage && (closure_site == 0 || bare_thunk)
    let aliases_domain = hidden_domain && closure_site == 0 && lower_owner_aliases_domain(source_state, store, owner)
    if hidden_domain && !aliases_domain {
        var parameter = __s0_buffer_get(MirParamRec, current.mir.params, 0)
        var parameter_at: U64 = 0
        while parameter_at < __s0_buffer_len(MirParamRec, current.mir.params) {
            let candidate = __s0_buffer_get(MirParamRec, current.mir.params, parameter_at)
            if candidate.function == function && candidate.kind == mir_param_function() && candidate.ordinal == 0 { parameter = candidate }
            parameter_at = parameter_at + 1
        }
        if parameter.function != function || parameter.kind != mir_param_function() || parameter.ordinal != 0 { return Ok(lower_invalid(current)) }
        let domains = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: lower_domain_key(store, owner), value: parameter.value))
        let env_domains = try __s0_buffer_append(LowerValueMapRec, d, domains, LowerValueMapRec(expression: lower_env_domain_key(owner), value: parameter.value))
        current = lower_with_values(current, env_domains)
        if bare_thunk {
            // A bare thunk allocates in the caller's domain directly instead
            // of creating a child domain for a call that may not allocate at
            // all; the returned value is copied into that same domain.
            let active = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: lower_active_domain_key(store, owner), value: parameter.value))
            current = lower_with_values(current, active)
        }
        param_ordinal = 1
    }
    var local_ordinal: U64 = 0
    var checked_params_seen: U64 = 0
    let start = __s0_buffer_get(U64, locals.starts, owner - 1)
    let end = __s0_buffer_get(U64, locals.starts, owner)
    var at: U64 = 0
    while start + at < end {
        let binding = __s0_buffer_get(U64, locals.ids, start + at)
        let local = __s0_buffer_get(LocalRec, store.locals, binding - 1)
        // A table-view arm binding is a switch-case value with no storage
        // slot; view types are ephemeral and may not appear as MIR locals.
        // The match case loop registers the arm's switch-case value later,
        // and later registrations win in lower_binding_lookup.
        let local_checked_type = __s0_buffer_get(CheckedTypeRec, store.types, local.checked_type - 1)
        if local.kind == 2 && (local_checked_type.kind == 21 || local_checked_type.kind == 22) {
            let view_skipped = 1
            if view_skipped != 1 { return Ok(lower_invalid(current)) }
        } else {
        let typ = try lower_local_type(d, source_state, store, current, owner, binding, local)
        current = typ.state
        var name = try lower_source_word(d, source_state, local.source, local.name_start, local.name_end)
        if local.kind != 1 && lower_local_name_seen(source_state, store, locals, start, at, local) { name = try lower_decimal_name(d, "__alder_local_", local_ordinal) }
        var is_capture = false
        if closure_site != 0 && local.kind == 1 && checked_params_seen >= declared_params { is_capture = true }
        if is_capture {
            // A capture: unpacked from the environment record in the prologue
            // below, not a real parameter.
            let slot = try mir_add_local(d, current.mir, function, local_ordinal, name, typ.id)
            current = lower_with_mir(current, slot.store)
            let capture_bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: binding, mir_id: slot.id, parameter: 0, initial: 0))
            current = lower_with_bindings(current, capture_bindings)
            local_ordinal = local_ordinal + 1
        } else {
        if local.kind == 1 {
            var parameter_type = typ
            let owner_symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
            let source = __s0_buffer_get(SourceRec, source_state.sources, local.source)
            let read_receiver = owner_symbol.inherent_owner != 0 && local.mutable == 0 && source_word(source_state, source, local.name_start, local.name_end, "self")
            if local.mutable == 1 || read_receiver {
                let empty = try __s0_buffer_new(U64, d)
                var reference_kind = mir_type_kind_safe_ref()
                if local.mutable == 1 { reference_kind = mir_type_kind_safe_mut() }
                let reference = try mir_intern_type(d, typ.state.mir, reference_kind, typ.id, 0, 0, empty, 0)
                parameter_type = LowerStep(state: lower_with_mir(typ.state, reference.store), id: reference.type_id)
            }
            let parameter = try mir_add_function_param(d, parameter_type.state.mir, function, param_ordinal, name, parameter_type.id)
            current = lower_with_mir(current, parameter.store)
            // Every borrowed runtime parameter carries the domain that owns
            // the caller's place. A by-value parameter's storage lives in the
            // caller's active domain, so both kinds are recorded in the local
            // owner map; a `take` parameter owns its value in this frame and
            // keeps the default frame owner.
            var owner_encoded: U64 = 0
            if local.mutable == 0 { owner_encoded = 1 }
            if local.mutable == 1 && current.has_storage {
                let owner_name = try lower_decimal_name(d, "__owner_", checked_params_seen)
                let domain_type = try lower_domain_mir_type(d, current)
                let owner_parameter = try mir_add_function_param(d, domain_type.state.mir, function, param_ordinal + 1, owner_name, domain_type.id)
                current = lower_with_mir(domain_type.state, owner_parameter.store)
                owner_encoded = owner_parameter.id + 2
                param_ordinal = param_ordinal + 1
            }
            if local.mutable == 2 {
                // A `take` parameter owns the incoming value, so it needs a
                // real local place: field receivers inside the method mutate
                // it with borrow_mut, and a later field read must observe
                // those writes.
                let slot = try mir_add_local(d, current.mir, function, local_ordinal, name, typ.id)
                current = lower_with_mir(current, slot.store)
                let place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: slot.id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
                current = lower_with_mir(current, place.store)
                let stored = try lower_add_instr(d, current, function, 1, mir_op_store(), 0, place.id, 0, parameter.id, 0, 0, "")
                current = stored.state
                let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: binding, mir_id: slot.id, parameter: 0, initial: 0))
                current = lower_with_bindings(current, bindings)
                local_ordinal = local_ordinal + 1
            } else { if (local.mutable == 0 && !read_receiver) {
                let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: binding, mir_id: parameter.id, parameter: 1, initial: 0))
                current = lower_with_bindings(current, bindings)
            } else {
                var parameter_kind: U64 = 3
                if local.mutable == 1 { parameter_kind = 2 }
                let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: binding, mir_id: parameter.id, parameter: parameter_kind, initial: 0))
                current = lower_with_bindings(current, bindings)
            } }
            if aliases_domain && param_ordinal == 0 {
                let domains = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: lower_domain_key(store, owner), value: parameter.id))
                current = lower_with_values(current, domains)
            }
            current = try lower_with_local_owner(d, current, binding, owner_encoded)
            param_ordinal = param_ordinal + 1
            checked_params_seen = checked_params_seen + 1
        } else {
            let slot = try mir_add_local(d, current.mir, function, local_ordinal, name, typ.id)
            current = lower_with_mir(current, slot.store)
            let bindings = try __s0_buffer_append(LowerBindingMapRec, d, current.bindings, LowerBindingMapRec(binding: binding, mir_id: slot.id, parameter: 0, initial: 0))
            current = lower_with_bindings(current, bindings)
            local_ordinal = local_ordinal + 1
        }
        }
        }
        at = at + 1
    }
    // The closure environment parameter: a reference to the capture record.
    var env_param: U64 = 0
    if closure_site != 0 {
        let site = __s0_buffer_get(ClosureSiteRec, store.closures.sites, closure_site - 1)
        if site.capture_count != 0 {
            let env_type = try lower_closure_env_type(d, source_state, store, current, site)
            if !env_type.state.valid { return Ok(env_type.state) }
            let empty = try __s0_buffer_new(U64, d)
            let reference = try mir_intern_type(d, env_type.state.mir, mir_type_kind_safe_mut(), env_type.id, 0, 0, empty, 0)
            let parameter = try mir_add_function_param(d, reference.store, function, param_ordinal, "alder_env", reference.type_id)
            // Thread the memoized state: the environment type is built once
            // per site across every function that references it, so the
            // thunk's own prologue and the enclosing creation site share one
            // record type instead of interning two same-named aggregates.
            current = lower_with_mir(env_type.state, parameter.store)
            env_param = parameter.id
        }
    }
    let entry = try mir_add_block(d, current.mir, function, 0, "bb0")
    current = lower_with_mir(current, entry.store)
    let panic = try mir_add_block(d, current.mir, function, 1, "bb_panic")
    current = lower_with_mir(current, panic.store)
    // Closure prologue: unpack each capture from the environment record into
    // its local. The captures are the site's trailing role-5 uses; their
    // mir locals were created above in the same order.
    if closure_site != 0 {
        let site = __s0_buffer_get(ClosureSiteRec, store.closures.sites, closure_site - 1)
        if site.capture_count != 0 {
            let deref = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: env_param))
            current = lower_with_mir(current, deref.store)
            var ordinal: U64 = 0
            while ordinal < site.capture_count {
                let capture = __s0_buffer_get(ClosureCaptureRec, store.closures.captures, site.first_capture - 1 + ordinal)
                let capture_local = lower_closure_param_local(store, locals, owner, site.declared_count + ordinal)
                if capture_local == 0 { return Ok(lower_invalid(current)) }
                let local = __s0_buffer_get(LocalRec, store.locals, capture_local - 1)
                let typ = try lower_local_type(d, source_state, store, current, owner, capture_local, local)
                if !typ.state.valid { return Ok(lower_invalid(current)) }
                current = typ.state
                let field_name = try lower_source_word(d, source_state, local.source, local.name_start, local.name_end)
                let field = try lower_helper_field_place(d, current, function, deref.id, field_name)
                current = field.state
                let loaded = try lower_helper_load(d, current, function, entry.id, field.id, typ.id)
                current = loaded.state
                let binding = lower_binding_lookup(current, capture_local)
                if binding.binding == 0 { return Ok(lower_invalid(current)) }
                let local_place = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_local(), local: binding.mir_id, base: 0, field_start: 0, field_end: 0, deref_value: 0))
                current = lower_with_mir(current, local_place.store)
                let stored = try lower_add_instr(d, current, function, entry.id, mir_op_store(), 0, local_place.id, 0, loaded.id, 0, 0, "")
                current = stored.state
                ordinal = ordinal + 1
            }
        }
        if site.capture_count != 0 {
            // The environment record records the domain it lives in.
            // Register that domain as this thunk's active and result domain
            // so a body that copies or allocates storage works and a nested
            // environment is allocated beside the outer record.
            let deref = try mir_add_place(d, current.mir, MirPlaceRec(function: function, kind: mir_place_deref(), local: 0, base: 0, field_start: 0, field_end: 0, deref_value: env_param))
            current = lower_with_mir(current, deref.store)
            let field = try lower_helper_field_place(d, current, function, deref.id, "alder_env_domain")
            current = field.state
            let domain_type = try lower_domain_mir_type(d, current)
            current = domain_type.state
            let loaded = try lower_helper_load(d, current, function, entry.id, field.id, domain_type.id)
            current = loaded.state
            let active = try __s0_buffer_append(LowerValueMapRec, d, current.values, LowerValueMapRec(expression: lower_active_domain_key(store, owner), value: loaded.id))
            let result_domain = try __s0_buffer_append(LowerValueMapRec, d, active, LowerValueMapRec(expression: lower_domain_key(store, owner), value: loaded.id))
            current = lower_with_values(current, result_domain)
        }
    }
    if hidden_domain && !bare_thunk {
        let parent = lower_result_domain_value(current, store, owner)
        if parent == 0 { return Ok(lower_invalid(current)) }
        let domain_type = try lower_domain_mir_type(d, current)
        let local_domain = try lower_add_typed_result(d, domain_type.state, function, entry.id, domain_type.id)
        let created = try lower_add_instr(d, local_domain.state, function, entry.id, mir_op_domain_create(), local_domain.id, 0, 0, parent, 0, 0, "")
        let domains = try __s0_buffer_append(LowerValueMapRec, d, created.state.values, LowerValueMapRec(expression: lower_active_domain_key(store, owner), value: local_domain.id))
        current = lower_with_values(created.state, domains)
    }
    let root = lower_owner_lookup(state.roots, owner)
    if root == 0 { return Ok(lower_invalid(current)) }
    let flow = try lower_block_statements(d, source_state, spans, store, current, owner, function, entry.id, root, panic.id, 0)
    current = flow.state
    if !current.valid { return Ok(current) }
    if !flow.terminated {
        if hidden_domain && !bare_thunk {
            let destroyed = try lower_add_instr(d, current, function, flow.block, mir_op_domain_destroy(), 0, 0, 0, lower_domain_value(current, store, owner), 0, 0, "")
            current = destroyed.state
        }
        let term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: flow.block, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
        current = lower_with_mir(current, term.store)
    }
    if hidden_domain && !bare_thunk {
        let destroyed = try lower_add_instr(d, current, function, panic.id, mir_op_domain_destroy(), 0, 0, 0, lower_domain_value(current, store, owner), 0, 0, "")
        current = destroyed.state
    }
    let panic_term = try mir_add_terminator(d, current.mir, MirTermRec(function: function, block: panic.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(lower_with_mir(current, panic_term.store))
}

// True when the owner symbol is the resolved core.panic.panic function.
fn lower_symbol_is_core_panic(source_state: State, store: CheckStore, owner: U64) -> Bool {
    if owner == 0 || owner > __s0_buffer_len(SymbolRec, store.symbols) { return false }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if symbol.kind != 12 && symbol.kind != 13 { return false }
    if !source_path_is(source_state, symbol.source, "core/panic.al") { return false }
    let source = __s0_buffer_get(SourceRec, source_state.sources, symbol.source)
    return source_word(source_state, source, symbol.name_start, symbol.name_end, "panic")
}

fn lower_functions(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, locals: LowerLocalIndex, state: LowerState) -> Result(LowerState, __s0_Error) {
    var current = state
    var owner: U64 = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if lower_owner_concrete(store, owner) {
            current = try lower_function(d, source_state, spans, store, locals, current, owner)
                if !current.valid {
                return Ok(current) }
        }
        owner = owner + 1
    }
    var drain_at: U64 = 0
    while drain_at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let cleanup = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, drain_at)
        if cleanup.callback == 0 {
            current = try lower_vec_drain_body(d, source_state, store, current, cleanup)
            if !current.valid { return Ok(current) }
        }
        drain_at = drain_at + 1
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
    let error_checked = lower_checked_type_kind(store, 5, 0)
    if error_checked == 0 { return Ok(lower_invalid(current)) }
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

fn lower_buffer_set_body(d: Domain, source_state: State, store: CheckStore, state: LowerState, checked_type: U64, bridge: LowerBridgeRec) -> Result(LowerState, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    let element_checked = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
    let element = try lower_type(d, source_state, store, state, element_checked)
    let buffer = try lower_type(d, source_state, store, element.state, checked_type)
    let empty_types = try __s0_buffer_new(U64, d)
    let data_type = try mir_intern_type(d, buffer.state.mir, mir_type_kind_safe_mut(), element.id, 0, 0, empty_types, 0)
    let entry = try mir_add_block(d, data_type.store, bridge.set_id, 0, "bb0")
    let valid = try mir_add_block(d, entry.store, bridge.set_id, 1, "bb_valid")
    let fail = try mir_add_block(d, valid.store, bridge.set_id, 2, "bb_fail")
    let fail_term = try mir_add_terminator(d, fail.store, MirTermRec(function: bridge.set_id, block: fail.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    let local = try lower_helper_local_place(d, lower_with_mir(buffer.state, fail_term.store), bridge.set_id, 0, "buffer", buffer.id)
    let stored = try lower_add_instr(d, local.state, bridge.set_id, entry.id, mir_op_store(), 0, local.id, 0, 1, 0, 0, "")
    let len_place = try lower_helper_field_place(d, stored.state, bridge.set_id, local.id, "len")
    let length = try lower_helper_load(d, len_place.state, bridge.set_id, entry.id, len_place.id, mir_type_u64())
    let inside = try lower_add_typed_result(d, length.state, bridge.set_id, entry.id, mir_type_bool())
    let compared = try lower_add_instr(d, inside.state, bridge.set_id, entry.id, mir_op_int_lt(), inside.id, 0, 0, 2, length.id, 0, "")
    let branched = try lower_branch(d, compared.state, bridge.set_id, entry.id, inside.id, valid.id, fail.id)
    let data_place = try lower_helper_field_place(d, branched, bridge.set_id, local.id, "data")
    let data = try lower_helper_load(d, data_place.state, bridge.set_id, valid.id, data_place.id, data_type.type_id)
    let reference = try lower_add_typed_result(d, data.state, bridge.set_id, valid.id, data_type.type_id)
    let indexed = try lower_add_instr(d, reference.state, bridge.set_id, valid.id, mir_op_slice_index_checked(), reference.id, 0, 0, data.id, 2, fail.id, "")
    let deref = try lower_helper_deref_place(d, indexed.state, bridge.set_id, reference.id)
    let written = try lower_add_instr(d, deref.state, bridge.set_id, valid.id, mir_op_store(), 0, deref.id, 0, 3, 0, 0, "")
    return lower_helper_return(d, written.state, bridge.set_id, valid.id, 0)
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
    let error_checked = lower_checked_type_kind(store, 5, 0)
    if error_checked == 0 { return Ok(lower_invalid(current)) }
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
    let set = try lower_buffer_set_body(d, source_state, store, appended, checked_type, bridge)
    return lower_buffer_get_slice_body(d, source_state, store, set, checked_type, bridge)
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

// M8 integer overflow surface: lower the checked/saturating/wrapping
// arithmetic methods to their non-terminating MIR operations. The try forms
// produce option(T) (none on overflow); the saturating and wrapping forms
// produce T. None of them carries a failure edge.
fn lower_int_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 2 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let argument_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    let argument = try lower_expression(d, source_state, spans, store, receiver.state, owner, function, block, argument_syntax, environment, panic_block)
    let receiver_type = lower_builtin_child_type(store, expression, 0)
    let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
    var op: U64 = 0
    if annotation.builtin == 47 { op = mir_op_int_add_try() }
    if annotation.builtin == 48 { op = mir_op_int_sub_try() }
    if annotation.builtin == 49 { op = mir_op_int_mul_try() }
    if annotation.builtin == 50 { op = mir_op_int_add_saturating() }
    if annotation.builtin == 51 { op = mir_op_int_sub_saturating() }
    if annotation.builtin == 52 { op = mir_op_int_mul_saturating() }
    if annotation.builtin == 53 { op = mir_op_int_add_wrapping() }
    if annotation.builtin == 54 { op = mir_op_int_sub_wrapping() }
    if annotation.builtin == 55 { op = mir_op_int_mul_wrapping() }
    if op == 0 || first.kind != 1 || first.target < 2 || first.target > 9 { return Ok(LowerStep(state: lower_invalid(argument.state), id: 0)) }
    let result_type = try lower_type(d, source_state, store, argument.state, expression.checked_type)
    let result = try lower_add_result(d, result_type.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, receiver.id, argument.id, 0, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

// M8 integer conversion surface: lower the to_T, to_T_checked, and
// to_T_wrapping methods. Every lossless to_T pair is a widening, so the
// total form reuses the existing zext (unsigned receiver) and sext (signed
// receiver) operations; the checked and wrapping forms lower to their
// dedicated operations, which carry no failure edge. The checked target is
// the payload of the call's Option(result).
fn lower_int_convert_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    let receiver_type = lower_builtin_child_type(store, expression, 0)
    let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
    if first.kind != 1 || first.target < 2 || first.target > 9 { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
    var target_checked: U64 = expression.checked_type
    if annotation.builtin == 63 {
        let option = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
        if option.kind != 9 || option.arg_count != 1 { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
        target_checked = __s0_buffer_get(U64, store.type_args, option.first_arg - 1)
    }
    let target = __s0_buffer_get(CheckedTypeRec, store.types, target_checked - 1)
    if target.kind != 1 || target.target < 2 || target.target > 9 { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
    let target_type = try lower_type(d, source_state, store, receiver.state, target_checked)
    var op: U64 = 0
    if annotation.builtin == 62 {
        if first.target >= 6 { op = mir_op_int_zext() } else { op = mir_op_int_sext() }
    }
    if annotation.builtin == 63 { op = mir_op_int_convert_checked() }
    if annotation.builtin == 64 { op = mir_op_int_convert_wrap() }
    let result = try lower_add_result(d, target_type.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, target_type.id, receiver.id, 0, 0, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

// M8 byte-sequence surface: lower the String and Bytes methods to their MIR
// operations. Slot mapping follows the MirInstrRec layout the mirrors print:
// len and to_bytes read slot a; byte.checked reads a (receiver) and b
// (index); concat and from_bytes take the storage domain in a and their
// sequence values in b and c; slice.checked takes domain, receiver, and lo in
// a, b, and c with hi attached as an instruction operand. Every allocating or
// bounds-checked form carries the panic block as its failure edge; len and
// to_bytes cannot fail.
fn lower_str_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    var expected_count: U64 = 1
    if annotation.builtin == 57 || annotation.builtin == 58 { expected_count = 2 }
    if annotation.builtin == 59 { expected_count = 3 }
    if expression.child_count != expected_count || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    var current = receiver.state
    var first: U64 = 0
    var second: U64 = 0
    if expected_count >= 2 {
        let argument_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
        let argument = try lower_expression(d, source_state, spans, store, current, owner, function, block, argument_syntax, environment, panic_block)
        current = argument.state
        first = argument.id
    }
    if expected_count == 3 {
        let argument_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child + 1).expression
        let argument = try lower_expression(d, source_state, spans, store, current, owner, function, block, argument_syntax, environment, panic_block)
        current = argument.state
        second = argument.id
    }
    var op: U64 = 0
    if annotation.builtin == 56 { op = mir_op_str_len() }
    if annotation.builtin == 57 { op = mir_op_str_byte_checked() }
    if annotation.builtin == 58 { op = mir_op_str_concat() }
    if annotation.builtin == 59 { op = mir_op_str_slice_checked() }
    if annotation.builtin == 60 { op = mir_op_str_to_bytes() }
    if annotation.builtin == 61 { op = mir_op_str_from_bytes() }
    if op == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    let domain = lower_storage_domain_value(current, store, owner, expression_id)
    let result = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
    var instr = LowerStep(state: result.state, id: 0)
    if annotation.builtin == 56 || annotation.builtin == 60 {
        let added = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, receiver.id, 0, 0, "")
        instr = added
    } else {
        if annotation.builtin == 57 {
            let added = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, receiver.id, first, panic_block, "")
            instr = added
        } else {
            if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let added = try lower_add_instr_three(d, result.state, function, block, op, result.id, 0, domain, receiver.id, first, panic_block)
            instr = added
        }
    }
    if annotation.builtin == 59 {
        let wired = try lower_add_instr_operand(d, instr.state, instr.id, 0, second, mir_operand_instruction(), "")
        return Ok(LowerStep(state: wired, id: result.id))
    }
    return Ok(LowerStep(state: instr.state, id: result.id))
}

// Order surface (M8): the builtin less method. Unsigned integers compare
// through int.lt; String and Bytes compare through str.order_lt; Bool
// orders through branches because int.lt does not accept Bool operands.
fn lower_order_less_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 2 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    let receiver_type = lower_builtin_child_type(store, expression, 0)
    if receiver_type == 0 { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
    if checked.kind == 1 && checked.target == 1 { return lower_order_bool_less(d, source_state, spans, store, receiver.state, owner, function, block, expression_id, expression, receiver.id, environment, panic_block) }
    let argument_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let argument = try lower_expression(d, source_state, spans, store, receiver.state, owner, function, block, argument_syntax, environment, panic_block)
    var op: U64 = 0
    if checked.kind == 1 { op = mir_op_int_lt() }
    if checked.kind == 2 || checked.kind == 14 { op = mir_op_str_order_lt() }
    if op == 0 { return Ok(LowerStep(state: lower_invalid(argument.state), id: 0)) }
    let result = try lower_add_result(d, argument.state, function, block, expression.checked_type, source_state, store)
    let added = try lower_add_instr(d, result.state, function, block, op, result.id, 0, 0, receiver.id, argument.id, panic_block, "")
    return Ok(LowerStep(state: added.state, id: result.id))
}

fn lower_order_bool_less(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, receiver: U64, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    // Bool ordering lowers through branches: false orders before true, so
    // a.less(b) holds exactly when a is false and b is true. The shape
    // mirrors the short-circuit Boolean operators.
    if expression.child_count != 2 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let source_block = lower_open_block(state.mir, function, block)
    let truthy_block = try lower_add_block(d, state, function, "bb_order_true")
    let falsy_block = try lower_add_block(d, truthy_block.state, function, "bb_order_false")
    let join = try lower_add_block(d, falsy_block.state, function, "bb_order_join")
    let result_type = try lower_type(d, source_state, store, join.state, expression.checked_type)
    let param = try mir_add_block_param(d, result_type.state.mir, function, join.id, 0, try lower_decimal_name(d, "__alder_order_", join.id), result_type.id)
    var current = lower_with_mir(result_type.state, param.store)
    current = try lower_branch(d, current, function, source_block, receiver, truthy_block.id, falsy_block.id)
    let argument_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let argument = try lower_expression(d, source_state, spans, store, current, owner, function, falsy_block.id, argument_syntax, environment, panic_block)
    current = try lower_jump_value(d, argument.state, function, lower_open_block(argument.state.mir, function, falsy_block.id), join.id, argument.id)
    let bool_suffix = __s0_buffer_len(MirConstRec, current.mir.constants) + 1
    let falsity = try lower_bool_value(d, source_state, store, current, function, truthy_block.id, expression.checked_type, 0, "__alder_order_false_", bool_suffix)
    current = try lower_jump_value(d, falsity.state, function, truthy_block.id, join.id, falsity.id)
    return Ok(LowerStep(state: current, id: param.id))
}

// M8 C-boundary record fields. The read lowers to c.field.get over the
// base local's record value; the write lowers to c.field.set through the
// base local's MIR place with the checked value in slot a and yields no
// value. The checker pins the base to a single-word local read (kind 5),
// whose parameter_use names the local, and stores the 1-based field record
// index in the field expression's own parameter_use.
fn lower_c_field_access(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(BindingFieldRec, store.bindings.fields) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if expression.child_count == 0 || expression.first_child == 0 || expression.child_count > 2 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let base_child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    if base_child == 0 || base_child > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let base_expr = __s0_buffer_get(CheckedExprRec, store.expressions, base_child - 1)
    if base_expr.kind != 1 && base_expr.kind != 5 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    if base_expr.parameter_use == 0 || base_expr.parameter_use > __s0_buffer_len(LocalRec, store.locals) { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, expression.parameter_use - 1)
    let name = try lower_source_word(d, source_state, field.name_source, field.name_start, field.name_end)
    if expression.kind == 27 {
        let base = try lower_expression(d, source_state, spans, store, state, owner, function, block, base_child, environment, panic_block)
        if !base.state.valid { return Ok(base) }
        let result = try lower_add_result(d, base.state, function, block, expression.checked_type, source_state, store)
        let instr = try lower_add_instr(d, result.state, function, block, mir_op_c_field_get(), result.id, 0, 0, base.id, 0, 0, name)
        return Ok(LowerStep(state: instr.state, id: result.id))
    }
    let lookup = lower_binding_lookup(state, base_expr.parameter_use)
    if lookup.parameter != 0 || lookup.mir_id == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let value_child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child).expression
    let value = try lower_expression(d, source_state, spans, store, state, owner, function, block, value_child, environment, panic_block)
    if !value.state.valid { return Ok(value) }
    let instr = try lower_add_instr(d, value.state, function, block, mir_op_c_field_set(), 0, lookup.mir_id, 0, value.id, 0, 0, name)
    return Ok(LowerStep(state: instr.state, id: 0))
}

// Interpolation lowers as a left-to-right concat chain over its checked
// children. Literal segments are string constants; display parts are ordinary
// checked calls (builtin str.display or a user Display method), so this helper
// needs no separate Display resolution. Empty literal segments are omitted.
fn lower_interpolation_expression(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count == 0 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    var current = state
    var result: U64 = 0
    var ordinal: U64 = 0
    while ordinal < expression.child_count {
        let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + ordinal).expression
        let child = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
        var skip = false
        if child.kind == 4 {
            if child.syntax == 0 || child.syntax > __s0_buffer_len(CheckedSpanRec, spans) { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let span = __s0_buffer_get(CheckedSpanRec, spans, child.syntax - 1)
            let token_id = lower_token_for_span(source_state, span)
            if token_id == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
            let token = __s0_buffer_get(TokenRec, source_state.tokens, token_id - 1)
            if token.value_end == token.value_start { skip = true }
        }
        if !skip {
            let part = try lower_expression(d, source_state, spans, store, current, owner, function, block, child_id, environment, panic_block)
            if !part.state.valid { return Ok(part) }
            current = part.state
            if result == 0 {
                result = part.id
            } else {
                let domain = lower_storage_domain_value(current, store, owner, expression_id)
                if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
                let added = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
                let instr = try lower_add_instr_three(d, added.state, function, block, mir_op_str_concat(), added.id, 0, domain, result, part.id, panic_block)
                current = instr.state
                result = added.id
            }
        }
        ordinal = ordinal + 1
    }
    if result == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    return Ok(LowerStep(state: current, id: result))
}

// Display surface (M8): the builtin display method. A String receiver is
// its own text, so the call lowers to the receiver value itself. Every
// other builtin-domain receiver widens to I64 (signed) or U64 (unsigned
// integers; Bool stays raw) and formats through the checked str.display
// instruction: domain in slot a, the value in slot b, with the allocation
// failure edge to the panic block.
fn lower_display_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    let receiver_type = lower_builtin_child_type(store, expression, 0)
    if receiver_type == 0 { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
    if checked.kind == 2 { return Ok(LowerStep(state: receiver.state, id: receiver.id)) }
    if checked.kind != 1 || checked.target < 1 || checked.target > 9 { return Ok(LowerStep(state: lower_invalid(receiver.state), id: 0)) }
    var value = receiver.id
    var current = receiver.state
    // Targets 5 (I64) and 9 (U64) are already the str.display operand
    // widths, so widening them would be a same-width extension the
    // verifier rejects; Bool stays raw.
    if checked.target != 1 && checked.target != 5 && checked.target != 9 {
        var op: U64 = mir_op_int_sext()
        var wide_type: U64 = mir_type_i64()
        if checked.target >= 6 {
            op = mir_op_int_zext()
            wide_type = mir_type_u64()
        }
        let widened = try lower_add_typed_result(d, current, function, block, wide_type)
        let instr = try lower_add_instr(d, widened.state, function, block, op, widened.id, 0, wide_type, receiver.id, 0, 0, "")
        value = widened.id
        current = instr.state
    }
    let domain = lower_storage_domain_value(current, store, owner, expression_id)
    if domain == 0 { return Ok(LowerStep(state: lower_invalid(current), id: 0)) }
    let result = try lower_add_result(d, current, function, block, expression.checked_type, source_state, store)
    let added = try lower_add_instr_three(d, result.state, function, block, mir_op_str_display(), result.id, 0, domain, value, 0, panic_block)
    return Ok(LowerStep(state: added.state, id: result.id))
}

// M8 C-boundary conversions: lower to c.num.try, c.num.wrap, or c.num.cast
// with the receiver value in slot a and the target type in type_op (the
// option(E) type for the try form, where E is the target scalar). The
// target always equals the result type, so the lowering needs no annotation
// data beyond the builtin id, and conversions cannot fail at runtime: the
// try form produces none/some and the wrapping form truncates.
fn lower_c_convert_builtin(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore, state: LowerState, owner: U64, function: U64, block: U64, expression_id: U64, expression: CheckedExprRec, annotation: CallAnnotationRec, environment: U64, panic_block: U64) -> Result(LowerStep, __s0_Error) {
    if expression.child_count != 1 || expression.first_child == 0 { return Ok(LowerStep(state: lower_invalid(state), id: 0)) }
    let receiver_syntax = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
    let receiver = try lower_expression(d, source_state, spans, store, state, owner, function, block, receiver_syntax, environment, panic_block)
    let result_type = try lower_type(d, source_state, store, receiver.state, expression.checked_type)
    var op: U64 = mir_op_c_num_cast()
    let form = c_convert_form(annotation.builtin)
    if form == 1 { op = mir_op_c_num_try() }
    if form == 2 { op = mir_op_c_num_wrap() }
    let result = try lower_add_result(d, result_type.state, function, block, expression.checked_type, source_state, store)
    let instr = try lower_add_instr(d, result.state, function, block, op, result.id, 0, result_type.id, receiver.id, 0, 0, "")
    return Ok(LowerStep(state: instr.state, id: result.id))
}

// Model check for a lowered C-boundary conversion: one receiver child, no
// annotation target or place, and the endpoints decoded from the builtin id
// must match the receiver's checked type and the result type (the option
// payload for checked forms). Mirrors the checker's c_convert_builtin
// encoding.
fn lower_model_c_convert_ok(store: CheckStore, annotation: CallAnnotationRec, expression: CheckedExprRec) -> Bool {
    if expression.child_count != 1 || annotation.target != 0 || annotation.variant_use != 0 || annotation.place != 0 { return false }
    let receiver_type = lower_builtin_child_type(store, expression, 0)
    if receiver_type == 0 || receiver_type > __s0_buffer_len(CheckedTypeRec, store.types) || annotation.checked_type == 0 || annotation.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let source = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
    let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
    var target = result
    if c_convert_form(annotation.builtin) == 1 {
        if result.kind != 9 || result.arg_count != 1 || result.first_arg == 0 { return false }
        let payload = __s0_buffer_get(U64, store.type_args, result.first_arg - 1)
        if payload == 0 || payload > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
        target = __s0_buffer_get(CheckedTypeRec, store.types, payload - 1)
    }
    if annotation.builtin >= 962 {
        var source_ok = false
        if annotation.builtin == 965 { source_ok = source.kind == 1 && source.target == 10 }
        if annotation.builtin == 966 || annotation.builtin == 967 { source_ok = source.kind == 1 && source.target == 11 }
        var target_ok = false
        if annotation.builtin == 965 { target_ok = target.kind == 26 && target.target == 11 }
        if annotation.builtin == 966 { target_ok = target.kind == 26 && target.target == 12 }
        if annotation.builtin == 967 { target_ok = target.kind == 26 && target.target == 11 }
        return source_ok && target_ok
    }
    if annotation.builtin >= 520 {
        let rest = annotation.builtin - 520
        let alder_index = rest / 45
        let scalar = (rest % 45) / 3
        if !(source.kind == 1 && source.target == alder_index + 2) { return false }
        return target.kind == 26 && target.target == scalar
    }
    let rest = annotation.builtin - 65
    let scalar = rest / 30
    let alder_index = (rest % 30) / 3
    if !(source.kind == 26 && source.target == scalar) { return false }
    return target.kind == 1 && target.target == alder_index + 2
}

fn lower_builtin_model_valid(store: CheckStore, annotation: CallAnnotationRec, expression: CheckedExprRec) -> Bool {
    if annotation.kind != 5 || annotation.variant_use != 0 || annotation.builtin == 0 || annotation.builtin > 1001 { return false }
    if annotation.builtin == 1000 {
        // M8 Order surface: a scalar Order receiver, a same-type argument,
        // and a Bool result.
        if expression.child_count != 2 || annotation.target != 0 { return false }
        let receiver_type = lower_builtin_child_type(store, expression, 0)
        if receiver_type == 0 || lower_builtin_child_type(store, expression, 1) != receiver_type { return false }
        let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
        if first.kind == 1 { return first.target == 1 || (first.target >= 6 && first.target <= 9) }
        if first.kind == 2 || first.kind == 14 {
            let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
            return result.kind == 1 && result.target == 1
        }
        return false
    }
    if annotation.builtin == 1001 {
        // M8 Display surface: a builtin-domain receiver, no argument, and
        // a String result. The domain check is inlined because the lower
        // layer never imports checker helpers.
        if expression.child_count != 1 || annotation.target != 0 { return false }
        let receiver_type = lower_builtin_child_type(store, expression, 0)
        if receiver_type == 0 { return false }
        let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
        let receiver_ok = (first.kind == 1 && first.target >= 1 && first.target <= 9) || first.kind == 2
        if !receiver_ok { return false }
        let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
        return result.kind == 2
    }
    if annotation.builtin == 969 {
        // Option.take: one Option receiver and the same Option result.
        if expression.child_count != 1 || annotation.target != 0 { return false }
        let receiver_type = lower_builtin_child_type(store, expression, 0)
        if receiver_type == 0 || annotation.checked_type != receiver_type { return false }
        let option = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
        return option.kind == 9 && option.arg_count == 1
    }
    if annotation.builtin == 968 {
        // [U8].to_bytes: one byte-view receiver child, bytes result.
        if expression.child_count != 1 || annotation.target != 0 { return false }
        let view_type = lower_builtin_child_type(store, expression, 0)
        if view_type == 0 { return false }
        let view = __s0_buffer_get(CheckedTypeRec, store.types, view_type - 1)
        if view.kind != 8 || view.arg_count != 1 { return false }
        let element = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, view.first_arg - 1) - 1)
        let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
        return element.kind == 1 && element.target == 6 && result.kind == 14
    }
    if annotation.builtin >= 65 { return lower_model_c_convert_ok(store, annotation, expression) }
    if annotation.builtin >= 62 {
        // M8 integer conversion surface: an integer receiver and a target
        // primitive carried by the method name. The total and wrapping
        // forms produce the target itself; the checked form produces
        // Option(target).
        if expression.child_count != 1 || annotation.target != 0 { return false }
        let receiver_type = lower_builtin_child_type(store, expression, 0)
        if receiver_type == 0 { return false }
        let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
        if first.kind != 1 || first.target < 2 || first.target > 9 { return false }
        let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
        if annotation.builtin == 62 || annotation.builtin == 64 { return result.kind == 1 && result.target >= 2 && result.target <= 9 }
        if result.kind != 9 || result.arg_count != 1 { return false }
        let payload = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, result.first_arg - 1) - 1)
        return payload.kind == 1 && payload.target >= 2 && payload.target <= 9
    }
    if annotation.builtin >= 56 {
        // M8 byte-sequence surface: String and Bytes receivers, U64 index
        // and bounds arguments, same-type concat and slice results, and
        // Option(String) from bytes.
        var expected_count: U64 = 1
        if annotation.builtin == 57 || annotation.builtin == 58 { expected_count = 2 }
        if annotation.builtin == 59 { expected_count = 3 }
        if expression.child_count != expected_count { return false }
        let receiver_type = lower_builtin_child_type(store, expression, 0)
        if receiver_type == 0 { return false }
        let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
        if first.kind != 2 && first.kind != 14 { return false }
        let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
        if annotation.builtin == 56 { return result.kind == 1 && result.target == 9 }
        if annotation.builtin == 57 {
            let index = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1)
            return index.kind == 1 && index.target == 9 && result.kind == 1 && result.target == 6
        }
        if annotation.builtin == 58 { return lower_builtin_child_type(store, expression, 1) == receiver_type && annotation.checked_type == receiver_type }
        if annotation.builtin == 59 {
            let lo = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1)
            let hi = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 2) - 1)
            return lo.kind == 1 && lo.target == 9 && hi.kind == 1 && hi.target == 9 && annotation.checked_type == receiver_type
        }
        if annotation.builtin == 60 { return first.kind == 2 && result.kind == 14 }
        if result.kind != 9 || result.arg_count != 1 { return false }
        let payload = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, result.first_arg - 1) - 1)
        return first.kind == 14 && payload.kind == 2
    }
    if annotation.builtin >= 47 {
        // M8 integer overflow surface: receiver and right operand share the
        // exact integer primitive type; checked methods produce Option(T),
        // saturating and wrapping methods produce T.
        if expression.child_count != 2 || annotation.target != 0 { return false }
        let receiver_type = lower_builtin_child_type(store, expression, 0)
        let argument_type = lower_builtin_child_type(store, expression, 1)
        if receiver_type == 0 || argument_type != receiver_type { return false }
        let first = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type - 1)
        if first.kind != 1 || first.target < 2 || first.target > 9 { return false }
        let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
        if annotation.builtin <= 49 { return result.kind == 9 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == receiver_type }
        return annotation.checked_type == receiver_type
    }
    if annotation.builtin >= 30 && annotation.builtin <= 44 { return lower_ordered_model_valid(store, annotation, expression) }
    if annotation.target != 0 { return false }
    var expected_count: U64 = 1
    if annotation.builtin == 18 { expected_count = 0 }
    if annotation.builtin == 2 || annotation.builtin == 11 || annotation.builtin == 15 { expected_count = 3 }
    if annotation.builtin == 3 || annotation.builtin == 6 || annotation.builtin == 12 || annotation.builtin == 14 || annotation.builtin == 16 { expected_count = 2 }
    if annotation.builtin == 17 { expected_count = 3 }
    if annotation.builtin == 19 || annotation.builtin == 20 { expected_count = 1 }
    if annotation.builtin == 21 || annotation.builtin == 22 { expected_count = 2 }
    if annotation.builtin >= 23 { expected_count = 3 }
    if annotation.builtin >= 26 {
        // M7.5 table builtins: Table.new takes no runtime children; every
        // method takes the receiver read and one runtime argument.
        expected_count = 2
        if annotation.builtin == 26 { expected_count = 0 }
    }
    if expression.child_count != expected_count { return false }
    let result = __s0_buffer_get(CheckedTypeRec, store.types, annotation.checked_type - 1)
    if annotation.builtin == 18 { return result.kind == 17 && result.arg_count == 1 }
    if annotation.builtin >= 26 {
        if annotation.builtin == 26 { return result.kind == 19 && result.arg_count == 1 }
        let first_type = lower_builtin_child_type(store, expression, 0)
        let second_type = lower_builtin_child_type(store, expression, 1)
        if first_type == 0 || second_type == 0 { return false }
        let first = __s0_buffer_get(CheckedTypeRec, store.types, first_type - 1)
        let second = __s0_buffer_get(CheckedTypeRec, store.types, second_type - 1)
        if first.kind != 19 || first.arg_count != 1 { return false }
        let element = __s0_buffer_get(U64, store.type_args, first.first_arg - 1)
        if annotation.builtin == 27 { return second_type == element && result.kind == 20 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == element }
        if annotation.builtin == 46 {
            // try_insert: same argument model as insert, but the result is
            // Result(T.Id, T) so the Err edge can hand the element back.
            if second_type != element { return false }
            if result.kind != 10 || result.arg_count != 2 { return false }
            let ok_id = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, result.first_arg - 1) - 1)
            return ok_id.kind == 20 && ok_id.arg_count == 1 && __s0_buffer_get(U64, store.type_args, ok_id.first_arg - 1) == element && __s0_buffer_get(U64, store.type_args, result.first_arg) == element
        }
        if second.kind != 20 || second.arg_count != 1 || __s0_buffer_get(U64, store.type_args, second.first_arg - 1) != element { return false }
        if annotation.builtin == 45 { return result.kind == 1 && result.target == 1 }
        if result.kind != 9 || result.arg_count != 1 { return false }
        let payload = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, result.first_arg - 1) - 1)
        if payload.kind != 21 && payload.kind != 22 { return false }
        if payload.arg_count != 1 || __s0_buffer_get(U64, store.type_args, payload.first_arg - 1) != element { return false }
        if annotation.builtin == 28 { return payload.kind == 21 }
        return payload.kind == 22
    }
    let first_type = lower_builtin_child_type(store, expression, 0)
    if first_type == 0 { return false }
    let first = __s0_buffer_get(CheckedTypeRec, store.types, first_type - 1)
    if annotation.builtin >= 19 {
        if first.arg_count != 1 { return false }
        let element = __s0_buffer_get(U64, store.type_args, first.first_arg - 1)
        if annotation.builtin == 19 { return first.kind == 15 && result.kind == 17 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == element }
        if annotation.builtin == 20 { return (first.kind == 8 || first.kind == 15 || first.kind == 17 || first.kind == 18) && result.kind == 1 && result.target == 9 }
        if annotation.builtin == 21 { return first.kind == 17 && lower_builtin_child_type(store, expression, 1) == element && result.kind == 1 && result.target == 12 }
        let index = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1)
        if index.kind != 1 || index.target != 9 { return false }
        if annotation.builtin == 22 { return (first.kind == 8 || first.kind == 15 || first.kind == 17 || first.kind == 18) && result.kind == 9 && result.arg_count == 1 && __s0_buffer_get(U64, store.type_args, result.first_arg - 1) == element }
        let hi = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 2) - 1)
        if hi.kind != 1 || hi.target != 9 || result.arg_count != 1 || __s0_buffer_get(U64, store.type_args, result.first_arg - 1) != element { return false }
        if annotation.builtin == 23 { return (first.kind == 8 || first.kind == 15 || first.kind == 17) && result.kind == 8 }
        if annotation.builtin == 24 { return (first.kind == 15 || first.kind == 17) && result.kind == 18 }
        return first.kind == 18 && result.kind == 18
    }
    if annotation.builtin == 1 { return (first.kind == 8 || first.kind == 16) && result.kind == 1 && result.target == 9 }
    if annotation.builtin == 2 {
        let lo = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1)
        let hi = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 2) - 1)
        return (first.kind == 8 || first.kind == 16) && annotation.checked_type == first_type && lo.kind == 1 && lo.target == 9 && hi.kind == 1 && hi.target == 9
    }
    if annotation.builtin == 3 { return first.kind == 3 && result.kind == 8 && __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1).target == 9 }
    if annotation.builtin == 4 { return first.kind == 3 && result.kind == 3 }
    if annotation.builtin == 5 { return first.kind == 3 && result.kind == 4 }
    if annotation.builtin == 6 { return first.kind == 3 && __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1).kind == 4 && result.kind == 1 && result.target == 12 }
    if annotation.builtin == 7 { return first.kind == 3 && result.kind == 1 && result.target == 12 }
    if annotation.builtin == 8 { return first.kind == 3 && result.kind == 11 }
    if annotation.builtin >= 9 && annotation.builtin <= 13 || annotation.builtin == 17 {
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
        if annotation.builtin == 17 {
            let index = __s0_buffer_get(CheckedTypeRec, store.types, lower_builtin_child_type(store, expression, 1) - 1)
            return index.kind == 1 && index.target == 9 && lower_builtin_child_type(store, expression, 2) == element && result.kind == 1 && result.target == 12
        }
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

// A method of a generic implementation owns no declaration body: only its
// concrete instances are checked and lowered. The implementation's
// parameters are the records its first method owns with the implementation
// root as their recorded node.
fn lower_impl_method_generic(store: CheckStore, method: U64) -> Bool {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, method - 1)
    if symbol.kind != 12 || symbol.inherent_owner == 0 { return false }
    var head: U64 = 0
    var at: U64 = 0
    var scanning = true
    while scanning {
        if at >= __s0_buffer_len(SymbolRec, store.symbols) { scanning = false } else {
            let candidate = __s0_buffer_get(SymbolRec, store.symbols, at)
            if candidate.kind == 12 && candidate.inherent_owner == symbol.inherent_owner { head = at + 1
            scanning = false } else { at = at + 1 }
        }
    }
    if head == 0 { return false }
    return impl_param_count_for(store, head) != 0
}

// A lowered body owner: a non-generic function or method that is not a
// method of a generic implementation, or an instance.
fn lower_owner_concrete(store: CheckStore, owner: U64) -> Bool {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if symbol.kind == 13 { return true }
    if symbol.kind != 12 || symbol.type_arity != 0 { return false }
    return !lower_impl_method_generic(store, owner)
}

// A cleanup hook is either a nongeneric function that declares itself or the
// concrete instance of a generic Cleanup implementation's method. Both are
// called through their lowered owner, so the hook must be a concrete owner;
// an instance carries its substituted signature in the instance use roles.
fn lower_cleanup_callback_valid(store: CheckStore, item: CheckedCleanupRec, binding: LocalRec) -> Bool {
    if !lower_owner_concrete(store, item.callback) { return false }
    let callback = __s0_buffer_get(SymbolRec, store.symbols, item.callback - 1)
    var parameter_role: U64 = 5
    var result_role: U64 = 6
    if callback.kind == 13 { parameter_role = 7
        result_role = 8 }
    let callback_parameter = lower_use_by_role(store, item.callback, parameter_role, 0)
    let callback_result = lower_use_by_role(store, item.callback, result_role, 0)
    if callback_parameter == 0 || callback_result == 0 || !lower_checked_abi_equal(store, __s0_buffer_get(DeclTypeUseRec, store.uses, callback_parameter - 1).checked_type, binding.checked_type) { return false }
    if lower_use_by_role(store, item.callback, parameter_role, 1) != 0 { return false }
    let callback_result_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(DeclTypeUseRec, store.uses, callback_result - 1).checked_type - 1)
    return callback_result_type.kind == 1 && callback_result_type.target == 12
}

// The c.Zero and c.addr expression shapes: a zero value carries no child and
// an address carries exactly the place expression its pointee types.
fn lower_model_c_zero_addr_ok(store: CheckStore, item: CheckedExprRec, annotation: CallAnnotationRec) -> Bool {
    if item.operator != 0 || item.parameter_use != 0 || item.left != 0 || item.right != 0 || item.bool_value != 0 { return false }
    if item.checked_type == 0 || item.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let result_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
    if item.kind == 32 {
        if annotation.builtin != 903 || item.child_count != 0 || item.first_child != 0 { return false }
        if result_type.kind == 26 { return true }
        return result_type.kind == 29
    }
    if annotation.builtin != 904 || item.child_count != 1 || item.first_child == 0 || item.first_child > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return false }
    if result_type.kind != 27 && result_type.kind != 28 { return false }
    if result_type.arg_count != 1 || result_type.first_arg == 0 { return false }
    let pointee = __s0_buffer_get(U64, store.type_args, result_type.first_arg - 1)
    let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
    if child_id == 0 || child_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
    let child = __s0_buffer_get(CheckedExprRec, store.expressions, child_id - 1)
    if child.checked_type != pointee { return false }
    return child.kind == 1 || child.kind == 5 || child.kind == 21
}

// The pointer member and whole-value memory shapes: a deref place over a
// c.Ptr or c.ConstPtr value, with a verified record field for the member
// forms and a c.Ptr-only write for the store forms.
fn lower_model_c_ptr_memory_ok(store: CheckStore, item: CheckedExprRec) -> Bool {
    if item.annotation != 0 || item.operator != 0 || item.bool_value != 0 { return false }
    if item.kind == 34 || item.kind == 35 {
        if item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(BindingFieldRec, store.bindings.fields) { return false }
        let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, item.parameter_use - 1)
        if field.owner == 0 || field.owner > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return false }
        if __s0_buffer_get(BindingMemberRec, store.bindings.members, field.owner - 1).member_kind != 1 { return false }
        if item.kind == 34 {
            if item.child_count != 1 { return false }
        } else {
            if item.child_count != 2 { return false }
            if item.checked_type == 0 || item.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
            let result = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if result.kind != 1 || result.target != 12 { return false }
        }
        let base_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
        if base_id == 0 || base_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
        let base = __s0_buffer_get(CheckedExprRec, store.expressions, base_id - 1)
        if base.kind != 1 && base.kind != 5 && base.kind != 22 { return false }
        if base.parameter_use == 0 || base.parameter_use > __s0_buffer_len(LocalRec, store.locals) { return false }
        let base_local = __s0_buffer_get(LocalRec, store.locals, base.parameter_use - 1)
        if base_local.owner != item.owner { return false }
        if base_local.checked_type == 0 || base_local.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
        let pointer = __s0_buffer_get(CheckedTypeRec, store.types, base_local.checked_type - 1)
        return pointer.kind == 27 || pointer.kind == 28
    }
    if item.parameter_use != 0 { return false }
    if item.kind == 36 {
        if item.child_count != 1 { return false }
    } else {
        if item.child_count != 2 { return false }
        if item.checked_type == 0 || item.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
        let result = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
        if result.kind != 1 || result.target != 12 { return false }
    }
    let pointer_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression
    if pointer_id == 0 || pointer_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
    let pointer_expr = __s0_buffer_get(CheckedExprRec, store.expressions, pointer_id - 1)
    if pointer_expr.checked_type == 0 || pointer_expr.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    let pointer = __s0_buffer_get(CheckedTypeRec, store.types, pointer_expr.checked_type - 1)
    if pointer.kind != 27 && pointer.kind != 28 { return false }
    if item.kind == 37 && pointer.kind != 27 { return false }
    if pointer.arg_count != 1 || pointer.first_arg == 0 { return false }
    let pointee = __s0_buffer_get(U64, store.type_args, pointer.first_arg - 1)
    if item.kind == 36 && item.checked_type != pointee { return false }
    return true
}

// Checked interpolation shape: a String-valued parent with no call
// annotation or operator, and one or more String-valued parts. Literal parts
// and display calls both have the parent's checked type.
fn lower_model_interpolation_ok(store: CheckStore, item: CheckedExprRec) -> Bool {
    if item.annotation != 0 || item.operator != 0 || item.parameter_use != 0 || item.bool_value != 0 { return false }
    if item.checked_type == 0 || item.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
    if __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1).kind != 2 { return false }
    if item.child_count == 0 || item.first_child == 0 { return false }
    var child_at: U64 = 0
    while child_at < item.child_count {
        let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1 + child_at).expression
        if child == 0 || child > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
        if __s0_buffer_get(CheckedExprRec, store.expressions, child - 1).checked_type != item.checked_type { return false }
        child_at = child_at + 1
    }
    return true
}

fn lower_model_valid(d: Domain, source_state: State, store: CheckStore, spans: __s0_Buffer(CheckedSpanRec)) -> Bool {
    // Ownership is validated below in stable record order. Build dense counts
    // once instead of rediscovering each owner with nested whole-table scans.
    let expression_count = __s0_buffer_len(CheckedExprRec, store.expressions)
    let child_count = __s0_buffer_len(CheckedExprChildRec, store.expression_children)
    let annotation_count = __s0_buffer_len(CallAnnotationRec, store.call_annotations)
    let place_count = __s0_buffer_len(CheckedPlaceRec, store.control.places)
    let statement_count = __s0_buffer_len(CheckedStatementRec, store.control.statements)
    let link_count = __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links)
    let block_count = __s0_buffer_len(CheckedBlockRec, store.control.blocks)
    let symbol_count = __s0_buffer_len(SymbolRec, store.symbols)
    let local_count = __s0_buffer_len(LocalRec, store.locals)
    let match_count = __s0_buffer_len(CheckedMatchRec, store.control.matches)
    let arm_count = __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms)
    let try_count = __s0_buffer_len(CheckedTryRec, store.control.tries)
    var expression_owners = __s0_alloc(U64, d, expression_count + 1)
    var child_starts = __s0_alloc(U64, d, child_count + 1)
    var child_ends = __s0_alloc(U64, d, child_count + 1)
    var annotation_owners = __s0_alloc(U64, d, annotation_count + 1)
    var place_owners = __s0_alloc(U64, d, place_count + 1)
    var statement_owners = __s0_alloc(U64, d, statement_count + 1)
    var link_owners = __s0_alloc(U64, d, link_count + 1)
    var block_parents = __s0_alloc(U64, d, block_count + 1)
    var owner_roots = __s0_alloc(U64, d, symbol_count + 1)
    var match_owners = __s0_alloc(U64, d, match_count + 1)
    var arm_starts = __s0_alloc(U64, d, arm_count + 1)
    var arm_ends = __s0_alloc(U64, d, arm_count + 1)
    var try_owners = __s0_alloc(U64, d, try_count + 1)
    var type_param_counts = __s0_alloc(U64, d, symbol_count + 1)
    var binding_environment_counts = __s0_alloc(U64, d, local_count + 1)
    let use_slot_count = (symbol_count + 1) * 9
    var use_seen = __s0_alloc(U64, d, use_slot_count)
    var count_at: U64 = 0
    while count_at <= expression_count { expression_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= child_count { child_starts[count_at] = 0
    child_ends[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= annotation_count { annotation_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= place_count { place_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= statement_count { statement_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= link_count { link_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= block_count { block_parents[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= symbol_count { owner_roots[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= match_count { match_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= arm_count { arm_starts[count_at] = 0
    arm_ends[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= try_count { try_owners[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= symbol_count { type_param_counts[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at <= local_count { binding_environment_counts[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at < use_slot_count { use_seen[count_at] = 0
    count_at = count_at + 1 }
    count_at = 0
    while count_at < expression_count {
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, count_at)
        if expression.site_kind != 0 { expression_owners[count_at + 1] = expression_owners[count_at + 1] + 1 }
        if expression.annotation >= 1 && expression.annotation <= annotation_count { annotation_owners[expression.annotation] = annotation_owners[expression.annotation] + 1 }
        if expression.kind == 12 && expression.parameter_use >= 1 && expression.parameter_use <= match_count { match_owners[expression.parameter_use] = match_owners[expression.parameter_use] + 1 }
        if expression.kind == 13 && expression.parameter_use >= 1 && expression.parameter_use <= try_count { try_owners[expression.parameter_use] = try_owners[expression.parameter_use] + 1 }
        if expression.child_count != 0 && expression.first_child != 0 && expression.child_count <= child_count && expression.first_child - 1 <= child_count - expression.child_count {
            let first = expression.first_child - 1
            child_starts[first] = child_starts[first] + 1
            child_ends[first + expression.child_count] = child_ends[first + expression.child_count] + 1
        }
        count_at = count_at + 1
    }
    count_at = 0
    while count_at < child_count {
        let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, count_at).expression
        if child >= 1 && child <= expression_count { expression_owners[child] = expression_owners[child] + 1 }
        count_at = count_at + 1
    }
    count_at = 0
    while count_at < arm_count {
        let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, count_at)
        if arm.body >= 1 && arm.body <= expression_count { expression_owners[arm.body] = expression_owners[arm.body] + 1 }
        if arm.guard >= 1 && arm.guard <= expression_count { expression_owners[arm.guard] = expression_owners[arm.guard] + 1 }
        if arm.statement >= 1 && arm.statement <= statement_count { statement_owners[arm.statement] = statement_owners[arm.statement] + 1 }
        count_at = count_at + 1
    }
    count_at = 0
    while count_at < match_count {
        let checked_match = __s0_buffer_get(CheckedMatchRec, store.control.matches, count_at)
        if checked_match.arm_count != 0 && checked_match.first_arm != 0 && checked_match.arm_count <= arm_count && checked_match.first_arm - 1 <= arm_count - checked_match.arm_count {
            let first = checked_match.first_arm - 1
            arm_starts[first] = arm_starts[first] + 1
            arm_ends[first + checked_match.arm_count] = arm_ends[first + checked_match.arm_count] + 1
        }
        count_at = count_at + 1
    }
    count_at = 0
    while count_at < statement_count {
        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, count_at)
        if statement.place >= 1 && statement.place <= place_count { place_owners[statement.place] = place_owners[statement.place] + 1 }
        if statement.body >= 1 && statement.body <= block_count && statement.kind != 10 { block_parents[statement.body] = block_parents[statement.body] + 1 }
        if statement.alternative >= 1 && statement.alternative <= block_count { block_parents[statement.alternative] = block_parents[statement.alternative] + 1 }
        count_at = count_at + 1
    }
    count_at = 0
    while count_at < arm_count {
        // A statement-arm block is parented by its match arm, not by a
        // statement body, so it must not count as an owner root.
        let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, count_at)
        if arm.block >= 1 && arm.block <= block_count { block_parents[arm.block] = block_parents[arm.block] + 1 }
        count_at = count_at + 1
    }
    count_at = 0
    while count_at < link_count {
        let statement = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, count_at).statement
        if statement >= 1 && statement <= statement_count { statement_owners[statement] = statement_owners[statement] + 1 }
        count_at = count_at + 1
    }
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
        // Binding blocks (61) are fully validated in the checker; their MIR
        // declarations lower from the checked binding model in a later
        // milestone, so they carry no ordinary parts here.
        if item.kind != 1 && item.kind != 2 && item.kind != 3 && item.kind != 12 && item.kind != 13 && item.kind != 50 && item.kind != 61 { return false }
        if item.node == 0 || item.node > __s0_buffer_len(CheckedSpanRec, spans) { return false }
        if !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        if item.kind == 13 {
            if item.declaration == 0 || item.declaration > __s0_buffer_len(SymbolRec, store.symbols) || item.declaration > at || __s0_buffer_get(SymbolRec, store.symbols, item.declaration - 1).kind != 12 { return false }
            if item.instance_arg_count == 0 || item.first_instance_arg == 0 || item.first_instance_arg - 1 + item.instance_arg_count > __s0_buffer_len(U64, store.type_args) { return false }
            if item.instance_arg_count != instance_arg_total(store, item.declaration) { return false }
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
        if item.kind != 1 && item.kind != 2 && item.kind != 3 && item.kind != 4 && item.kind != 5 && item.kind != 6 && item.kind != 7 && item.kind != 8 && item.kind != 9 && item.kind != 10 && item.kind != 11 && item.kind != 12 && item.kind != 13 && item.kind != 14 && item.kind != 15 && item.kind != 16 && item.kind != 17 && item.kind != 18 && item.kind != 19 && item.kind != 20 && item.kind != 21 && item.kind != 22 && item.kind != 23 && item.kind != 24 && item.kind != 25 && item.kind != 26 && item.kind != 27 && item.kind != 28 && item.kind != 29 && item.kind != 31 && item.kind != 33 { return false }
        if item.syntax != 0 { return false }
        if item.kind == 1 && (item.target == 0 || item.target > 12 || item.arg_count != 0) { return false }
        if item.kind == 26 && (item.target > 14 || item.arg_count != 0) { return false }
        if (item.kind == 27 || item.kind == 28) && (item.target != 0 || item.arg_count != 1) { return false }
        if item.kind == 29 && (item.target == 0 || item.arg_count != 0) { return false }
        if item.kind == 31 && (item.target != 0 || item.arg_count != 0) { return false }
        if item.kind == 33 && item.arg_count != 2 { return false }
        if (item.kind == 2 || item.kind == 3 || item.kind == 4 || item.kind == 5 || item.kind == 14 || item.kind == 16) && (item.target != 0 || item.arg_count != 0) { return false }
        if item.kind == 6 && (item.target == 0 || item.target > __s0_buffer_len(TypeParamRec, store.type_params) || item.arg_count != 0) { return false }
        if item.kind == 7 && (item.target == 0 || item.target > __s0_buffer_len(SymbolRec, store.symbols) || (__s0_buffer_get(SymbolRec, store.symbols, item.target - 1).kind != 2 && __s0_buffer_get(SymbolRec, store.symbols, item.target - 1).kind != 3)) { return false }
        // A function type stores its borrowed-parameter positions in `target`;
        // every other parameterized kind keeps target zero.
        if ((item.kind >= 8 && item.kind <= 14) || item.kind == 16 || item.kind == 17 || item.kind == 18 || item.kind == 19 || item.kind == 20 || item.kind == 21 || item.kind == 22 || item.kind == 23 || item.kind == 24) && item.target != 0 { return false }
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
        if (item.kind == 8 || item.kind == 9 || item.kind == 12 || item.kind == 13 || item.kind == 15 || item.kind == 17 || item.kind == 18 || item.kind == 19 || item.kind == 20 || item.kind == 21 || item.kind == 22 || item.kind == 24) && item.arg_count != 1 { return false }
        if (item.kind == 10 || item.kind == 11 || item.kind == 23) && item.arg_count != 2 { return false }
        if item.kind == 25 && item.arg_count < 2 { return false }
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
        type_param_counts[item.owner] = type_param_counts[item.owner] + 1
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if symbol.kind == 50 {
            // Traits add one implicit trailing `Self` parameter beyond their
            // declared arity, and each requirement with its own type
            // parameters records them in the trait's scope as well.
            var trait_params = type_param_counts[at + 1]
            if trait_self_param(store, at + 1) != 0 { trait_params = trait_params - 1 }
            if trait_params < symbol.type_arity { return false }
        } else {
            if symbol.kind != 13 {
                // The first method of a generic implementation owns the
                // implementation's parameters in addition to its own; no
                // other symbol may own more parameters than its arity.
                let owned = type_param_counts[at + 1]
                if owned < symbol.type_arity { return false }
                if owned != symbol.type_arity {
                    if symbol.inherent_owner == 0 { return false }
                    let head = first_impl_method_symbol(store, symbol.inherent_owner)
                    if head != at + 1 { return false }
                    if owned != symbol.type_arity + impl_param_count_for(store, head) { return false }
                }
            }
            if symbol.kind == 13 && type_param_counts[at + 1] != 0 { return false }
        }
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
        let use_slot = item.owner * 9 + item.role
        if item.ordinal != use_seen[use_slot] { return false }
        use_seen[use_slot] = use_seen[use_slot] + 1
        if item.role == 2 && item.syntax == 0 {
            if item.checked_type != 0 { return false }
        } else {
            if item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.checked_type == 0 || item.checked_type > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
            if (item.role == 3 || item.role == 4 || item.role == 7 || item.role == 8 || ((item.role == 1 || item.role == 2 || item.role == 5 || item.role == 6) && symbol.type_arity == 0 && !lower_impl_method_generic(store, item.owner))) && !lower_type_concrete(store, item.checked_type) { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(EnvironmentRec, store.environments) {
        let binding = __s0_buffer_get(EnvironmentRec, store.environments, at).binding
        if binding >= 1 && binding <= local_count { binding_environment_counts[binding] = binding_environment_counts[binding] + 1 }
        at = at + 1
    }
    at = 0
    while at < local_count {
        let item = __s0_buffer_get(LocalRec, store.locals, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.kind == 0 || item.kind > 2 || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.mutable > 2 || (item.kind == 2 && item.mutable > 1) || !lower_type_concrete(store, item.checked_type) || !lower_source_range_valid(source_state, item.source, item.name_start, item.name_end, true) { return false }
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
        if binding_environment_counts[at + 1] != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(EnvironmentRec, store.environments) {
        let item = __s0_buffer_get(EnvironmentRec, store.environments, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.parent > at { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
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
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.kind == 0 || item.kind > 8 || !lower_type_concrete(store, item.checked_type) { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
        if item.kind == 6 {
            if item.target != 0 || item.variant_use != 0 || (item.builtin != 5 && item.builtin != 6) { return false }
            let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if checked_type.kind != 5 { return false }
            at = at + 1
        } else {
        if item.kind == 5 {
            if item.builtin == 43 && item.target != 0 { }
            else { if item.target != 0 || item.variant_use != 0 || item.builtin == 0 || item.builtin > 1001 { return false } }
            at = at + 1
        } else {
        if item.kind == 8 {
            if item.owner == 0 || item.owner > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return false }
            if item.target == 0 || item.target > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return false }
            if item.variant_use == 0 || item.variant_use > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return false }
            if item.builtin == 0 || item.builtin > __s0_buffer_len(CheckedTypeRec, store.types) { return false }
            if item.place != 0 { return false }
            at = at + 1
        } else {
        if item.kind == 7 {
            // Unsafe binding call: the target is the 1-based binding
            // member index, not a symbol; the member's parameter fields own
            // the signature the checker and the MIR verifier enforce.
            if item.target == 0 || item.target > __s0_buffer_len(BindingMemberRec, store.bindings.members) || item.builtin != 0 || item.variant_use != 0 || item.place != 0 { return false }
            at = at + 1
        } else {
        if item.target == 0 || item.target > __s0_buffer_len(SymbolRec, store.symbols) || item.builtin != 0 { return false }
        let target = __s0_buffer_get(SymbolRec, store.symbols, item.target - 1)
        if item.kind == 1 {
            if !lower_owner_concrete(store, item.target) { return false }
            var result_role: U64 = 6
            if target.kind == 13 { result_role = 8 }
            let result_use = lower_use_by_role(store, item.target, result_role, 0)
            if result_use == 0 || !lower_checked_abi_equal(store, __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1).checked_type, item.checked_type) { return false }
        }
        if item.kind == 2 {
            if target.kind != 1 { return false }
            let result_use = lower_use_by_role(store, item.target, 4, 0)
            if result_use == 0 || !lower_checked_abi_equal(store, __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1).checked_type, item.checked_type) { return false }
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
        }
        }
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let item = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_type_concrete(store, item.checked_type) { return false }
        if item.kind == 0 || item.kind == 25 || item.kind > 40 { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
        if item.left != 0 || item.right != 0 { return false }
        if item.field_move != 0 && (item.kind != 21 || item.field_move > __s0_buffer_len(LocalRec, store.locals)) { return false }
        if (item.child_count == 0 && item.first_child != 0) || (item.child_count != 0 && item.first_child == 0) { return false }
        if item.child_count != 0 && item.first_child - 1 + item.child_count > __s0_buffer_len(CheckedExprChildRec, store.expression_children) { return false }
        var child_at: U64 = 0
        while child_at < item.child_count {
            let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1 + child_at).expression
            if child == 0 || child > at || __s0_buffer_get(CheckedExprRec, store.expressions, child - 1).owner != item.owner { return false }
            child_at = child_at + 1
        }
        if item.site_kind > 8 || (item.site_kind == 0 && item.site_syntax != 0) || (item.site_kind != 0 && item.site_syntax == 0) || item.site_syntax > __s0_buffer_len(CheckedSpanRec, spans) { return false }
        if item.kind == 40 && !lower_model_interpolation_ok(store, item) { return false }
        if item.kind == 24 {
            // Closure creation: parameter_use names the closure site, whose
            // expression points back here; the value has the erased function
            // type and no runtime children.
            if item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(ClosureSiteRec, store.closures.sites) { return false }
            let site = __s0_buffer_get(ClosureSiteRec, store.closures.sites, item.parameter_use - 1)
            if site.expression != at + 1 || site.owner == 0 || site.owner > __s0_buffer_len(SymbolRec, store.symbols) { return false }
            let thunk_symbol = __s0_buffer_get(SymbolRec, store.symbols, site.owner - 1)
            if thunk_symbol.kind != 12 || thunk_symbol.type_arity != 0 || thunk_symbol.declaration != site.owner { return false }
            if __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1).kind != 25 { return false }
            if item.child_count != 0 || item.annotation != 0 || item.first_child != 0 { return false }
        }
        if item.kind == 1 || item.kind == 5 || item.kind == 22 {
            if item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).owner != item.owner { return false }
        }
        if item.kind == 27 || item.kind == 28 {
            // C-boundary field access: the field record lives under a
            // record type member, and the base child is the owner's local
            // read. The value child's type identity stays checker-enforced.
            if item.parameter_use == 0 || item.parameter_use > __s0_buffer_len(BindingFieldRec, store.bindings.fields) { return false }
            let field = __s0_buffer_get(BindingFieldRec, store.bindings.fields, item.parameter_use - 1)
            if field.owner == 0 || field.owner > __s0_buffer_len(BindingMemberRec, store.bindings.members) { return false }
            if __s0_buffer_get(BindingMemberRec, store.bindings.members, field.owner - 1).member_kind != 1 { return false }
            if item.annotation != 0 || item.operator != 0 { return false }
            if item.child_count != 1 && item.child_count != 2 { return false }
            if item.kind == 27 && item.child_count != 1 { return false }
            let base = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            if base.kind != 1 && base.kind != 5 { return false }
            if base.parameter_use == 0 || base.parameter_use > __s0_buffer_len(LocalRec, store.locals) { return false }
            if __s0_buffer_get(LocalRec, store.locals, base.parameter_use - 1).owner != item.owner { return false }
        }
        if item.kind >= 34 && item.kind <= 37 {
            if !lower_model_c_ptr_memory_ok(store, item) { return false }
        }
        if item.kind == 1 && (__s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).kind != 1 || __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).checked_type != item.checked_type) { return false }
        if item.kind == 5 && (__s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).kind != 2 || __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).checked_type != item.checked_type) { return false }
        if item.kind == 22 && __s0_buffer_get(LocalRec, store.locals, item.parameter_use - 1).checked_type != item.checked_type { return false }
        if (item.kind >= 1 && item.kind <= 5 || item.kind == 22) && item.child_count != 0 { return false }
        if item.kind == 2 && item.bool_value > 1 { return false }
        if item.kind != 2 && item.bool_value != 0 { return false }
        if item.kind == 2 {
            let literal_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if literal_type.kind != 1 || (literal_type.target != 1 && literal_type.target != 12) { return false }
        }
        if item.kind == 3 {
            let literal_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if literal_type.kind != 1 || literal_type.target < 2 || literal_type.target > 9 { return false }
        }
        if item.kind == 4 {
            let literal_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if literal_type.kind != 2 && literal_type.kind != 8 && literal_type.kind != 14 && literal_type.kind != 16 { return false }
            if literal_type.kind == 8 {
                let element_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, literal_type.first_arg - 1) - 1)
                if element_type.kind != 1 || element_type.target != 6 { return false }
            }
        }
        if item.kind == 6 && (item.child_count != 1 || (item.operator != 1 && item.operator != 2 && item.operator != 21)) { return false }
        if item.kind == 7 && (item.child_count != 2 || item.operator < 3 || item.operator > 20) { return false }
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
            if item.operator >= 18 && item.operator <= 20 && item.checked_type != left.checked_type { return false }
            if item.operator >= 10 && item.operator <= 17 {
                let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
                if checked_type.kind != 1 || checked_type.target != 1 { return false }
            }
            if item.operator >= 16 && left.checked_type != item.checked_type { return false }
        }
        if item.kind >= 8 && item.kind <= 11 || item.kind >= 29 && item.kind <= 33 {
            if item.annotation == 0 || item.annotation > __s0_buffer_len(CallAnnotationRec, store.call_annotations) { return false }
            let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, item.annotation - 1)
            var annotation_kind: U64 = 1
            if item.kind == 9 { annotation_kind = 3 }
            if item.kind == 10 { annotation_kind = 4 }
            if item.kind == 11 { annotation_kind = 2 }
            if item.kind >= 29 && item.kind <= 33 { annotation_kind = 5 }
            if item.kind == 10 && annotation.kind == 6 {
                annotation_kind = 6
            }
            if item.kind == 11 && annotation.kind == 7 {
                annotation_kind = 7
            }
            if annotation.owner != item.owner || annotation.checked_type != item.checked_type || annotation.kind != annotation_kind { return false }
            if annotation.kind == 7 { return lower_model_binding_call_ok(store, annotation, item) } else {
            if annotation.kind == 5 {
                if item.kind == 32 || item.kind == 33 { return lower_model_c_zero_addr_ok(store, item, annotation) }
                // The c_string construction and borrow vocabulary: one
                // child plus the call annotation. The constructors take a
                // String argument and produce the bare owner (kind 29) or
                // Option of it (kind 30); the borrow reads a local owner
                // and yields the raw const pointer.
                if item.child_count != 1 || item.operator != 0 || item.parameter_use != 0 || item.left != 0 || item.right != 0 || item.bool_value != 0 { return false }
                if item.kind == 29 && annotation.builtin != 900 { return false }
                if item.kind == 30 && annotation.builtin != 901 { return false }
                if item.kind == 31 && annotation.builtin != 902 { return false }
                let child = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
                let child_type = __s0_buffer_get(CheckedTypeRec, store.types, child.checked_type - 1)
                let result_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
                if item.kind == 29 {
                    if child_type.kind != 2 || result_type.kind != 31 || result_type.target != 0 { return false }
                }
                if item.kind == 30 {
                    if child_type.kind != 2 { return false }
                    if result_type.kind != 9 || result_type.first_arg == 0 || result_type.first_arg > __s0_buffer_len(U64, store.type_args) { return false }
                    let payload = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, result_type.first_arg - 1) - 1)
                    if payload.kind != 31 || payload.target != 0 { return false }
                }
                if item.kind == 31 {
                    if child.kind != 1 && child.kind != 5 && child.kind != 22 { return false }
                    if child_type.kind != 31 || child_type.target != 0 { return false }
                    if result_type.kind != 28 { return false }
                }
            } else {
            if annotation.kind == 6 {
                if item.child_count != 0 || (annotation.builtin != 5 && annotation.builtin != 6) { return false }
                let error_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
                if error_type.kind != 5 { return false }
            } else {
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
                argument_count = use_seen[annotation.target * 9 + argument_role]
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
                if lower_type_concrete(store, expected_type) {
                    var compatible = lower_checked_abi_equal(store, argument.checked_type, expected_type)
                    if annotation.kind == 1 { compatible = lower_call_borrow_compatible(store, expected_type, argument.checked_type) }
                    if !compatible { return false }
                }
                argument_at = argument_at + 1
            }
            }
            }
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
                if !lower_checked_abi_equal(store, child.checked_type, expected_type) { return false }
            }
        }
        if item.kind == 26 {
            // The safe binding observation c.is_null: one raw-pointer
            // child, a Bool result, and no annotation of any kind.
            if item.child_count != 1 || item.annotation != 0 || item.parameter_use != 0 || item.bool_value != 0 || item.operator != 0 { return false }
            let checked_type = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if checked_type.kind != 1 || checked_type.target != 1 { return false }
            let child = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            let child_type = __s0_buffer_get(CheckedTypeRec, store.types, child.checked_type - 1)
            if child_type.kind != 27 && child_type.kind != 28 { return false }
        }
        if item.kind == 19 {
            if item.child_count != 2 { return false }
            let base = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1).expression - 1)
            let index = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child).expression - 1)
            let base_type = __s0_buffer_get(CheckedTypeRec, store.types, base.checked_type - 1)
            let index_type = __s0_buffer_get(CheckedTypeRec, store.types, index.checked_type - 1)
            var element_type: U64 = 0
            if base_type.kind == 8 || base_type.kind == 15 || base_type.kind == 17 || base_type.kind == 18 { element_type = __s0_buffer_get(U64, store.type_args, base_type.first_arg - 1) }
            if base_type.kind == 16 {
                let element = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
                if element.kind == 1 && element.target == 6 { element_type = item.checked_type }
            }
            if element_type != item.checked_type || index_type.kind != 1 || index_type.target != 9 { return false }
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
            // A table-view base projects the element type's fields.
            var aggregate_root = base.checked_type
            if base_type.kind == 21 || base_type.kind == 22 { aggregate_root = __s0_buffer_get(U64, store.type_args, base_type.first_arg - 1) }
            let aggregate_type = __s0_buffer_get(CheckedTypeRec, store.types, aggregate_root - 1)
            if aggregate_type.kind != 7 || aggregate_type.target != field.owner { return false }
            if lower_type_concrete(store, field.checked_type) && !lower_checked_abi_equal(store, field.checked_type, item.checked_type) { return false }
        }
        if item.kind == 23 {
            let array = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
            if array.kind != 15 || array.arg_count != 1 || item.child_count != array.target { return false }
            let element = __s0_buffer_get(U64, store.type_args, array.first_arg - 1)
            var element_at: U64 = 0
            while element_at < item.child_count {
                let child = __s0_buffer_get(CheckedExprRec, store.expressions, __s0_buffer_get(CheckedExprChildRec, store.expression_children, item.first_child - 1 + element_at).expression - 1)
                if !lower_checked_abi_equal(store, child.checked_type, element) { return false }
                element_at = element_at + 1
            }
        }
        if item.kind != 1 && item.kind != 5 && item.kind != 12 && item.kind != 13 && item.kind != 21 && item.kind != 22 && item.kind != 24 && item.kind != 27 && item.kind != 28 && item.parameter_use != 0 { return false }
        at = at + 1
    }
    at = 0
    var active_child_owners: U64 = 0
    while at < __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
        active_child_owners = active_child_owners + child_starts[at]
        active_child_owners = active_child_owners - child_ends[at]
        if active_child_owners != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CallAnnotationRec, store.call_annotations) {
        let item = __s0_buffer_get(CallAnnotationRec, store.call_annotations, at)
        if annotation_owners[at + 1] != 1 { return false }
        if item.place != 0 {
            if item.place > place_count { return false }
            if __s0_buffer_get(CheckedPlaceRec, store.control.places, item.place - 1).owner != item.owner { return false }
            place_owners[item.place] = place_owners[item.place] + 1
        }
        at = at + 1
    }
    // A projection owns the place it projects from, so every record is
    // referenced exactly once: by the statement or call that uses the
    // outermost place, or by the projection that extends it. Count the
    // projections first, because a chain is built base first.
    at = 0
    while at < __s0_buffer_len(CheckedPlaceRec, store.control.places) {
        let item = __s0_buffer_get(CheckedPlaceRec, store.control.places, at)
        if item.base >= 1 && item.base <= place_count { place_owners[item.base] = place_owners[item.base] + 1 }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedPlaceRec, store.control.places) {
        let item = __s0_buffer_get(CheckedPlaceRec, store.control.places, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.kind == 0 || item.kind > 3 || item.root == 0 || item.root > __s0_buffer_len(LocalRec, store.locals) || __s0_buffer_get(LocalRec, store.locals, item.root - 1).owner != item.owner || !lower_type_concrete(store, item.checked_type) { return false }
        let root = __s0_buffer_get(LocalRec, store.locals, item.root - 1)
        // A chain is built bottom-up, so a projection base is always an
        // earlier record of the same owner and root.
        if item.base > at { return false }
        var source_type = root.checked_type
        if item.base != 0 {
            let parent = __s0_buffer_get(CheckedPlaceRec, store.control.places, item.base - 1)
            if parent.owner != item.owner || parent.root != item.root { return false }
            source_type = parent.checked_type
        }
        if item.kind == 1 && (item.base != 0 || item.field != 0 || item.index != 0) { return false }
        if item.kind == 1 && item.checked_type != root.checked_type { return false }
        if item.kind == 2 && (item.field == 0 || item.field > __s0_buffer_len(DeclTypeUseRec, store.uses) || __s0_buffer_get(DeclTypeUseRec, store.uses, item.field - 1).role != 1) { return false }
        var source_checked = __s0_buffer_get(CheckedTypeRec, store.types, source_type - 1)
        // A field of a table view is a field of the view's element type.
        if (item.kind == 2 || item.kind == 3) && (source_checked.kind == 21 || source_checked.kind == 22) {
            source_checked = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, source_checked.first_arg - 1) - 1)
        }
        if item.kind == 3 {
            if item.index == 0 || item.index > __s0_buffer_len(CheckedExprRec, store.expressions) || __s0_buffer_get(CheckedExprRec, store.expressions, item.index - 1).owner != item.owner { return false }
            if source_checked.kind != 8 && source_checked.kind != 15 && source_checked.kind != 17 && source_checked.kind != 18 { return false }
            let element_type = __s0_buffer_get(U64, store.type_args, source_checked.first_arg - 1)
            if item.checked_type != element_type { return false }
            if __s0_buffer_get(CheckedExprRec, store.expressions, item.index - 1).site_kind != 7 { return false }
            let index_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(CheckedExprRec, store.expressions, item.index - 1).checked_type - 1)
            if index_type.kind != 1 || index_type.target != 9 { return false }
        } else { if item.index != 0 { return false } }
        if item.kind == 2 {
            let field = __s0_buffer_get(DeclTypeUseRec, store.uses, item.field - 1)
            if source_checked.kind != 7 || source_checked.target != field.owner { return false }
            if lower_type_concrete(store, field.checked_type) && !lower_checked_abi_equal(store, field.checked_type, item.checked_type) { return false }
        }
        if item.kind != 2 && item.field != 0 { return false }
        if place_owners[at + 1] != 1 { return false }
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
    while at < block_count {
        let link = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at).statements
        if link != 0 { link_owners[link] = link_owners[link] + 1 }
        at = at + 1
    }
    at = link_count
    while at != 0 {
        let item = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at - 1)
        if item.next != 0 { link_owners[item.next] = link_owners[item.next] + link_owners[at] }
        at = at - 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
        let item = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at)
        if item.statement == 0 || item.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) || item.next > at { return false }
        if link_owners[at + 1] != 1 { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let item = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.kind == 0 || item.kind > 12 || !lower_environment_valid(store, item.owner, item.environment) { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
        if statement_owners[at + 1] != 1 { return false }
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
            if place.owner != item.owner || !lower_checked_abi_equal(store, place.checked_type, __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type) { return false }
        } else { if item.place != 0 { return false } }
        if needs_binding {
            if item.binding == 0 || item.binding > __s0_buffer_len(LocalRec, store.locals) { return false }
            let binding = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
            if binding.owner != item.owner || binding.kind != 2 || binding.syntax != item.syntax { return false }
            if item.kind == 1 && binding.mutable != 0 { return false }
            if item.kind == 2 && binding.mutable != 1 { return false }
            if item.kind == 10 && !lower_checked_abi_equal(store, binding.checked_type, __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type) { return false }
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
            let binding_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(LocalRec, store.locals, item.binding - 1).checked_type - 1)
            if sequence.kind == 8 || sequence.kind == 15 || sequence.kind == 17 || sequence.kind == 18 {
                if __s0_buffer_get(LocalRec, store.locals, item.binding - 1).checked_type != __s0_buffer_get(U64, store.type_args, sequence.first_arg - 1) { return false }
            } else { if sequence.kind != 16 || binding_type.kind != 1 || binding_type.target != 6 { return false } }
        }
        if item.kind == 1 || item.kind == 2 {
            if !lower_checked_abi_equal(store, __s0_buffer_get(LocalRec, store.locals, item.binding - 1).checked_type, __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type) { return false }
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
            } else { if !lower_checked_abi_equal(store, __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1).checked_type, result_type) { return false } }
        }
        at = at + 1
    }
    at = 0
    while at < block_count {
        let block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if block.owner >= 1 && block.owner <= symbol_count && block_parents[at + 1] == 0 { owner_roots[block.owner] = owner_roots[block.owner] + 1 }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
        let item = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_environment_valid(store, item.owner, item.environment) || item.statements > __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) || item.guaranteed_return > 1 { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
        let parent_count = block_parents[at + 1]
        if parent_count > 1 { return false }
        if parent_count == 0 && owner_roots[item.owner] != 1 { return false }
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
        if lower_owner_concrete(store, at + 1) {
            if owner_roots[at + 1] != 1 { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchRec, store.control.matches) {
        let item = __s0_buffer_get(CheckedMatchRec, store.control.matches, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.scrutinee == 0 || item.scrutinee > __s0_buffer_len(CheckedExprRec, store.expressions) || !lower_type_concrete(store, item.scrutinee_type) || !lower_type_concrete(store, item.checked_type) || item.arm_count == 0 || item.first_arm == 0 || item.first_arm - 1 + item.arm_count > __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        if !lower_owner_concrete(store, item.owner) { return false }
        let scrutinee = __s0_buffer_get(CheckedExprRec, store.expressions, item.scrutinee - 1)
        if scrutinee.owner != item.owner || !lower_checked_abi_equal(store, scrutinee.checked_type, item.scrutinee_type) { return false }
        if match_owners[at + 1] != 1 { return false }
        var ordinal: U64 = 0
        while ordinal < item.arm_count {
            let arm = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, item.first_arm - 1 + ordinal)
            if arm.owner != item.owner || arm.checked_match != at + 1 { return false }
            // Arms of one variant form one contiguous run: every earlier
            // same-variant arm must be guarded, and it must be the
            // immediately preceding arm, so a false guard falls through a
            // straight edge chain.
            var prior_ordinal: U64 = 0
            var seen_same_variant = false
            while prior_ordinal < ordinal {
                let prior = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, item.first_arm - 1 + prior_ordinal)
                if arm.variant_kind == prior.variant_kind && arm.variant_use == prior.variant_use {
                    if prior.guard == 0 { return false }
                    seen_same_variant = true
                }
                prior_ordinal = prior_ordinal + 1
            }
            if seen_same_variant && ordinal != 0 {
                let back = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, item.first_arm - 1 + ordinal - 1)
                if back.variant_kind != arm.variant_kind || back.variant_use != arm.variant_use { return false }
            }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    at = 0
    var active_arm_owners: U64 = 0
    while at < __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) {
        let item = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.checked_match == 0 || item.checked_match > __s0_buffer_len(CheckedMatchRec, store.control.matches) || item.variant_kind > 7 || !lower_environment_valid(store, item.owner, item.environment) || (item.body == 0 && item.block == 0 && item.statement == 0) || item.body > __s0_buffer_len(CheckedExprRec, store.expressions) || (item.block != 0 && item.block > __s0_buffer_len(CheckedBlockRec, store.control.blocks)) || (item.statement != 0 && (item.statement > statement_count || __s0_buffer_get(CheckedStatementRec, store.control.statements, item.statement - 1).kind != 4)) { return false }
        let checked_match = __s0_buffer_get(CheckedMatchRec, store.control.matches, item.checked_match - 1)
        if item.guard != 0 {
            if item.guard > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
            let guard = __s0_buffer_get(CheckedExprRec, store.expressions, item.guard - 1)
            let guard_type = __s0_buffer_get(CheckedTypeRec, store.types, guard.checked_type - 1)
            if guard.owner != item.owner || guard_type.kind != 1 || guard_type.target != 1 { return false }
        }
        if item.body != 0 {
            let body = __s0_buffer_get(CheckedExprRec, store.expressions, item.body - 1)
            if checked_match.owner != item.owner || body.owner != item.owner || !lower_checked_abi_equal(store, body.checked_type, checked_match.checked_type) { return false }
        } else { if item.statement != 0 {
            // A diverging arm's return belongs to the same concrete
            // instance; it produces no value and never constrains the
            // match's type.
            let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, item.statement - 1)
            if checked_match.owner != item.owner || statement.owner != item.owner { return false }
        } else {
            // A block arm produces Unit, and its statement block belongs to
            // the same concrete instance as the match.
            let arm_block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, item.block - 1)
            let unit_checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_match.checked_type - 1)
            if checked_match.owner != item.owner || arm_block.owner != item.owner || unit_checked.kind != 1 || unit_checked.target != 12 { return false }
        } }
        active_arm_owners = active_arm_owners + arm_starts[at]
        active_arm_owners = active_arm_owners - arm_ends[at]
        if active_arm_owners != 1 { return false }
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
            if lower_type_concrete(store, payload_type) && !lower_checked_abi_equal(store, binding.checked_type, payload_type) { return false }
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
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || item.expression == 0 || item.expression > __s0_buffer_len(CheckedExprRec, store.expressions) || !lower_type_concrete(store, item.result_type) || !lower_type_concrete(store, item.ok_type) { return false }
        if item.error_type != 0 && !lower_type_concrete(store, item.error_type) { return false }
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, item.expression - 1)
        let result = __s0_buffer_get(CheckedTypeRec, store.types, item.result_type - 1)
        if expression.owner != item.owner || !lower_checked_abi_equal(store, expression.checked_type, item.result_type) { return false }
        if item.error_type == 0 {
            // Option propagation: the sentinel error_type stays zero, the
            // wrapped type is Option(ok_type), and the try expression's
            // own type is the payload.
            if result.kind != 9 || result.first_arg == 0 || __s0_buffer_get(U64, store.type_args, result.first_arg - 1) != item.ok_type { return false }
        } else {
            if result.kind != 10 || !lower_checked_abi_equal(store, __s0_buffer_get(U64, store.type_args, result.first_arg - 1), item.ok_type) || !lower_checked_abi_equal(store, __s0_buffer_get(U64, store.type_args, result.first_arg), item.error_type) { return false }
        }
        if try_owners[at + 1] != 1 { return false }
        let owner = __s0_buffer_get(SymbolRec, store.symbols, item.owner - 1)
        var result_role: U64 = 6
        if owner.kind == 13 { result_role = 8 }
        let owner_result_use = lower_use_by_role(store, item.owner, result_role, 0)
        if owner_result_use == 0 { return false }
        let owner_result = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(DeclTypeUseRec, store.uses, owner_result_use - 1).checked_type - 1)
        if item.error_type == 0 {
            if owner_result.kind != 9 || owner_result.first_arg == 0 || __s0_buffer_get(U64, store.type_args, owner_result.first_arg - 1) != item.ok_type { return false }
        } else {
            if owner_result.kind != 10 || __s0_buffer_get(U64, store.type_args, owner_result.first_arg) != item.error_type { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let item = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, at)
        if item.owner == 0 || item.owner > __s0_buffer_len(SymbolRec, store.symbols) || item.syntax == 0 || item.syntax > __s0_buffer_len(CheckedSpanRec, spans) || !lower_environment_valid(store, item.owner, item.environment) || item.binding == 0 || item.binding > __s0_buffer_len(LocalRec, store.locals) || (item.callback != 0 && item.callback > __s0_buffer_len(SymbolRec, store.symbols)) { return false }
        let binding = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
        if binding.owner != item.owner || binding.kind != 2 || binding.syntax != item.syntax || item.initializer == 0 || item.initializer > __s0_buffer_len(CheckedExprRec, store.expressions) || item.normal_exit != 1 || item.return_exit != 1 || item.try_exit != 1 { return false }
        let initializer = __s0_buffer_get(CheckedExprRec, store.expressions, item.initializer - 1)
        if initializer.owner != item.owner || !lower_checked_abi_equal(store, initializer.checked_type, binding.checked_type) || initializer.site_kind != 8 || initializer.site_syntax != item.syntax { return false }
        if item.callback == 0 {
            // The M7.5 builtin owner form: the initializer type is exactly a
            // concrete Table (drain stays zero; lowering registers the
            // synthesized release callback) or an affine-element Vec of a
            // Cleanup owner (drain is its concrete cleanup method). The
            // activation and single-owner invariants below apply unchanged.
            let owner_type = __s0_buffer_get(CheckedTypeRec, store.types, binding.checked_type - 1)
            if owner_type.kind == 31 {
                // The c_string owner registers the builtin exactly-once
                // free shell: no callback and no drain, like the Table.
                if owner_type.arg_count != 0 || item.drain != 0 { return false }
            } else {
            if owner_type.kind == 19 && owner_type.arg_count == 1 {
                if item.drain != 0 { return false }
            } else {
                if owner_type.kind != 17 || owner_type.arg_count != 1 { return false }
                let element = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, owner_type.first_arg - 1) - 1)
                if element.kind != 7 || type_cleanup_impls(store, element.target) != 1 { return false }
                if item.drain == 0 || item.drain > __s0_buffer_len(SymbolRec, store.symbols) || __s0_buffer_get(SymbolRec, store.symbols, item.drain - 1).kind != 12 { return false }
            }
            }
        } else {
        if !lower_cleanup_callback_valid(store, item, binding) { return false }
        }
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
        if expression_owners[at + 1] != 1 { return false }
        at = at + 1
    }
    return true
}

fn lower_checked(d: Domain, source_state: State, spans: __s0_Buffer(CheckedSpanRec), store: CheckStore) -> Result(LowerResult, __s0_Error) {
    if __s0_buffer_len(CheckDiagRec, store.diagnostics) != 0 { return Ok(LowerBad) }
    if !lower_model_valid(d, source_state, store, spans) {
        return Ok(LowerModelBad)
    }
    let mir = try mir_store_new(d)
    let types = try __s0_buffer_new(LowerTypeMapRec, d)
    let owners = try __s0_buffer_new(LowerOwnerMapRec, d)
    let imports = try __s0_buffer_new(LowerOwnerMapRec, d)
    let bindings = try __s0_buffer_new(LowerBindingMapRec, d)
    let values = try __s0_buffer_new(LowerValueMapRec, d)
    let releases = try __s0_buffer_new(LowerValueMapRec, d)
    let bridges = try __s0_buffer_new(LowerBridgeRec, d)
    let storage = try lower_storage_plan(d, store)
    if __s0_buffer_len(U64, storage) != __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(LowerModelBad) }
    let roots = try lower_root_indexes(d, store)
    let binding_statements = try lower_binding_statement_indexes(d, store)
    let locals = try lower_local_indexes(d, store)
    let copy_reports = try __s0_buffer_new(CopySiteRec, d)
    let part_head = try __s0_buffer_new(U64, d)
    let part_next = try __s0_buffer_new(U64, d)
    let vec_memo_flag = try __s0_buffer_new(U64, d)
    let vec_memo_ans = try __s0_buffer_new(U64, d)
    let vec_memo_seen = try __s0_buffer_new(U64, d)
    // The D023 move plan is indexed by expression ID on both axes - the
    // verdict and the reason belong to the copy site, not to the binding, so
    // one binding can report a copying read and a moving read side by side.
    // One zeroed allocation per compilation, filled per function by
    // lower_move_analyze.
    var plan_movable = try __s0_buffer_new(U64, d)
    var plan_reasons = try __s0_buffer_new(U64, d)
    var plan_excluded = try __s0_buffer_new(U64, d)
    var zero_at: U64 = 0
    while zero_at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        plan_movable = try __s0_buffer_append(U64, d, plan_movable, 0)
        plan_reasons = try __s0_buffer_append(U64, d, plan_reasons, 0)
        zero_at = zero_at + 1
    }
    zero_at = 0
    while zero_at < __s0_buffer_len(LocalRec, store.locals) {
        plan_excluded = try __s0_buffer_append(U64, d, plan_excluded, 0)
        zero_at = zero_at + 1
    }
    var state = LowerState(mir: mir, types: types, owners: owners, roots: roots, binding_statements: binding_statements, imports: imports, bindings: bindings, values: values, releases: releases, bridges: bridges, storage: storage, part_index: LowerPartIndex(head: part_head, next: part_next, indexed: 0), has_storage: lower_has_storage(store), moves: LowerMovePlan(movable: plan_movable, reasons: plan_reasons, excluded_scratch: plan_excluded), local_index: locals, reports: copy_reports, valid: true, loop_exit: 0, loop_step: 0, loop_environment: 0, vec_memo_flag: vec_memo_flag, vec_memo_ans: vec_memo_ans, vec_memo_seen: vec_memo_seen, vec_memo_gen: 0)
    state = try lower_declarations(d, source_state, store, state)
    if !state.valid {
        return Ok(LowerBad)
    }
    // Synthesize every builtin table-release callback up front, in stable
    // cleanup order, so body lowering never appends records for one function
    // between the records of another.
    var release_at: U64 = 0
    while release_at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let cleanup = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, release_at)
        if cleanup.callback == 0 && cleanup.initializer >= 1 && cleanup.initializer <= __s0_buffer_len(CheckedExprRec, store.expressions) {
            let owner_type = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(CheckedExprRec, store.expressions, cleanup.initializer - 1).checked_type - 1)
            if owner_type.kind == 17 {
                let drain = try lower_vec_drain_function(d, source_state, store, state, __s0_buffer_get(CheckedExprRec, store.expressions, cleanup.initializer - 1).checked_type)
                if !drain.state.valid { return Ok(LowerBad) }
                state = drain.state
            } else {
                if owner_type.kind == 31 {
                    let made = try lower_cstring_release_function(d, source_state, store, state, __s0_buffer_get(CheckedExprRec, store.expressions, cleanup.initializer - 1).checked_type)
                    if !made.state.valid { return Ok(LowerBad) }
                    state = made.state
                } else { if owner_type.kind == 33 {
                    let made = try lower_callback_owner_release_function(d, source_state, store, state, cleanup.initializer)
                    if !made.state.valid { return Ok(LowerBad) }
                    state = made.state
                } else {
                let release = try lower_table_release_function(d, source_state, store, state, cleanup.owner, cleanup.initializer)
                if !release.state.valid { return Ok(LowerBad) }
                state = release.state
                } }
            }
        }
        release_at = release_at + 1
    }
    state = try lower_functions(d, source_state, spans, store, locals, state)
    if !state.valid {
        return Ok(LowerBad)
    }
    return Ok(LowerGood(LowerGoodRec(mir: state.mir, reports: state.reports)))
}
