type CheckStore {
    symbols: __s0_Buffer(SymbolRec)
    type_params: __s0_Buffer(TypeParamRec)
    types: __s0_Buffer(CheckedTypeRec)
    type_args: __s0_Buffer(U64)
    type_annotations: __s0_Buffer(CheckedTypeAnnotationRec)
    uses: __s0_Buffer(DeclTypeUseRec)
    locals: __s0_Buffer(LocalRec)
    environments: __s0_Buffer(EnvironmentRec)
    expressions: __s0_Buffer(CheckedExprRec)
    call_annotations: __s0_Buffer(CallAnnotationRec)
    expression_children: __s0_Buffer(CheckedExprChildRec)
    returns: __s0_Buffer(CheckedReturnRec)
    diagnostics: __s0_Buffer(CheckDiagRec)
}

// Concrete instance signatures reuse declaration-item shape while keeping
// declaration uses immutable. Roles 7 and 8 are instance runtime parameters
// and result respectively; owner is the concrete instance SymbolRec ID and
// node/source/name/syntax are copied from the declaration use.
type InferenceBindingRec {
    param: U64
    checked_type: U64
}

type TypeValueRec {
    store: CheckStore
    checked_type: U64
}

type SubstitutedChildrenRec {
    store: CheckStore
    children: __s0_Buffer(U64)
}

enum UnifyOutcome {
    UnifyGood(value: __s0_Buffer(InferenceBindingRec))
    UnifyConflict
}

type InstanceValueRec {
    store: CheckStore
    instance: U64
}

enum InstanceOutcome {
    InstanceGood(value: InstanceValueRec)
    InstanceBad(value: CheckStore)
}

type CallInferenceRec {
    store: CheckStore
    bindings: __s0_Buffer(InferenceBindingRec)
}

enum CallInferenceOutcome {
    CallInferenceGood(value: CallInferenceRec)
    CallInferenceBad(value: CheckStore)
    CallInferenceDefer
}

enum CheckResult {
    CheckGood(value: CheckStore)
    CheckBad(value: CheckStore)
}

// Body checking tri-state: an unsupported statement or expression defers the
// whole body so no partial records survive; the caller returns its own
// function-entry store. Diagnostics stay first-failure ordered.
enum BodyStep {
    BodyGood(value: CheckStore)
    BodyBad(value: CheckStore)
    BodyDefer
}

type ExprDraftRec {
    deferred: Bool
    checked_type: U64
    expression: U64
}

type ExprValueRec {
    store: CheckStore
    draft: ExprDraftRec
}

enum ExprOutcome {
    ExprGood(value: ExprValueRec)
    ExprBad(value: CheckStore)
}

type CycleColorRec {
    owner: U64
    color: U64
}

type CycleWorkRec {
    owner: U64
    checked_type: U64
    env: U64
    ancestry: U64
}

type CycleEdgeRec {
    owner: U64
    target: U64
}

// Cycle frames form a persistent stack. Replacing the top appends a new frame
// that points at the old parent, so cycle checking never depends on the C call
// stack or mutable Buffer elements.
type CycleFrameRec {
    owner: U64
    next_target: U64
    parent: U64
}

// These records are transient checker work. They deliberately do not belong to
// CheckStore: substitution interprets the immutable checked graph rather than
// materializing specialized copies of it.
type TypeBindingRec {
    param: U64
    checked_type: U64
    caller_env: U64
    caller_ancestry: U64
    next: U64
}

type InterpWorkRec {
    checked_type: U64
    env: U64
    ancestry: U64
}

type PairWorkRec {
    left_type: U64
    left_env: U64
    right_type: U64
    right_env: U64
}

type InterpStateRec {
    owner: U64
    checked_type: U64
    env: U64
    ancestry: U64
}

type ExpansionMemoRec {
    owner: U64
    target: U64
    checked_type: U64
    env: U64
}

type DeclAncestryRec {
    target: U64
    env: U64
    parent: U64
}

type ValidationWorkRec {
    checked_type: U64
    env: U64
    ancestry: U64
    next: U64
}

// Integer literal bounds never become host integers. positive is the type
// maximum; negative is the signed magnitude bound (2^7, 2^15, 2^31, 2^63).
// Decimal digit text preserves every U64 value and the I64 minimum, which
// Stage 0 signed host storage cannot represent.
type IntRangeRec {
    integer: Bool
    signed: Bool
    positive: String
    negative: String
}

fn env_lookup(bindings: __s0_Buffer(TypeBindingRec), env: U64, param: U64) -> TypeBindingRec {
    var at = env
    while at != 0 {
        let item = __s0_buffer_get(TypeBindingRec, bindings, at - 1)
        if item.param == param { return item }
        at = item.next
    }
    return TypeBindingRec(param: 0, checked_type: 0, caller_env: 0, caller_ancestry: 0, next: 0)
}

fn normalize_interp(store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64, ancestry: U64) -> InterpWorkRec {
    var t = checked_type
    var e = env
    var a = ancestry
    var done = false
    while !done {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, t - 1)
        if checked.kind != 6 { done = true } else {
            let bound = env_lookup(bindings, e, checked.target)
            if bound.param == 0 { done = true } else { t = bound.checked_type
                e = bound.caller_env
                a = bound.caller_ancestry }
        }
    }
    return InterpWorkRec(checked_type: t, env: e, ancestry: a)
}

fn primitive_same(state: State, parse: ParseStore, a: CheckedTypeRec, b: CheckedTypeRec) -> Bool {
    return a.target == b.target
}

fn interpreted_slice_u8(state: State, parse: ParseStore, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), checked: CheckedTypeRec, env: U64) -> Bool {
    if checked.kind != 8 || checked.arg_count != 1 { return false }
    let child = normalize_interp(store, bindings, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env, 0)
    let item = __s0_buffer_get(CheckedTypeRec, store.types, child.checked_type - 1)
    return item.kind == 1 && item.target == 6
}

// Finite structural equality is iterative. Declared applications compare their
// target and direct arguments and never expand declaration bodies. String is
// compared as its documented [U8] semantic form.
fn interpreted_type_equal(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), left_type: U64, left_env: U64, right_type: U64, right_env: U64) -> Result(Bool, __s0_Error) {
    let initial = try __s0_buffer_new(PairWorkRec, d)
    var work = try __s0_buffer_append(PairWorkRec, d, initial, PairWorkRec(left_type: left_type, left_env: left_env, right_type: right_type, right_env: right_env))
    let first_seen = try __s0_buffer_new(PairWorkRec, d)
    var seen = first_seen
    var at: U64 = 0
    while at < __s0_buffer_len(PairWorkRec, work) {
        let pair = __s0_buffer_get(PairWorkRec, work, at)
        let left = normalize_interp(store, bindings, pair.left_type, pair.left_env, 0)
        let right = normalize_interp(store, bindings, pair.right_type, pair.right_env, 0)
        if left.checked_type != right.checked_type || left.env != right.env {
            var known = false
            var seen_at: U64 = 0
            while seen_at < __s0_buffer_len(PairWorkRec, seen) {
                let prior = __s0_buffer_get(PairWorkRec, seen, seen_at)
                if prior.left_type == left.checked_type && prior.left_env == left.env && prior.right_type == right.checked_type && prior.right_env == right.env { known = true }
                seen_at = seen_at + 1
            }
            if !known {
                seen = try __s0_buffer_append(PairWorkRec, d, seen, PairWorkRec(left_type: left.checked_type, left_env: left.env, right_type: right.checked_type, right_env: right.env))
                let a = __s0_buffer_get(CheckedTypeRec, store.types, left.checked_type - 1)
                let b = __s0_buffer_get(CheckedTypeRec, store.types, right.checked_type - 1)
                if a.kind != b.kind {
                    if !((a.kind == 2 && interpreted_slice_u8(state, parse, store, bindings, b, right.env)) || (b.kind == 2 && interpreted_slice_u8(state, parse, store, bindings, a, left.env))) { return Ok(false) }
                } else {
                    if a.target != b.target || a.arg_count != b.arg_count { return Ok(false) }
                    if a.kind == 1 && !primitive_same(state, parse, a, b) { return Ok(false) }
                    if a.kind == 6 && a.target != b.target { return Ok(false) }
                    var child: U64 = 0
                    while child < a.arg_count {
                        work = try __s0_buffer_append(PairWorkRec, d, work, PairWorkRec(left_type: __s0_buffer_get(U64, store.type_args, a.first_arg - 1 + child), left_env: left.env, right_type: __s0_buffer_get(U64, store.type_args, b.first_arg - 1 + child), right_env: right.env))
                        child = child + 1
                    }
                }
            }
        }
        at = at + 1
    }
    return Ok(true)
}

fn expansion_seen(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), memo: __s0_Buffer(ExpansionMemoRec), owner: U64, checked_type: U64, env: U64) -> Result(Bool, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    var at: U64 = 0
    while at < __s0_buffer_len(ExpansionMemoRec, memo) {
        let prior = __s0_buffer_get(ExpansionMemoRec, memo, at)
        if prior.owner == owner && prior.target == checked.target {
            if try interpreted_type_equal(d, state, parse, store, bindings, checked_type, env, prior.checked_type, prior.env) { return Ok(true) }
        }
        at = at + 1
    }
    return Ok(false)
}

fn remember_expansion(d: Domain, memo: __s0_Buffer(ExpansionMemoRec), owner: U64, target: U64, checked_type: U64, env: U64) -> Result(__s0_Buffer(ExpansionMemoRec), __s0_Error) {
    return __s0_buffer_append(ExpansionMemoRec, d, memo, ExpansionMemoRec(owner: owner, target: target, checked_type: checked_type, env: env))
}

fn expansion_target_seen(memo: __s0_Buffer(ExpansionMemoRec), target: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(ExpansionMemoRec, memo) {
        if __s0_buffer_get(ExpansionMemoRec, memo, at).target == target { return true }
        at = at + 1
    }
    return false
}

fn interp_state_seen(seen: __s0_Buffer(InterpStateRec), owner: U64, checked_type: U64, env: U64, ancestry: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(InterpStateRec, seen) {
        let item = __s0_buffer_get(InterpStateRec, seen, at)
        if item.owner == owner && item.checked_type == checked_type && item.env == env && item.ancestry == ancestry { return true }
        at = at + 1
    }
    return false
}

fn direct_type_concrete(d: Domain, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64) -> Result(Bool, __s0_Error) {
    let initial = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, initial, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        if checked.kind == 6 { return Ok(false) }
        var child: U64 = 0
        while child < checked.arg_count {
            work = try __s0_buffer_append(InterpWorkRec, d, work, InterpWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), env: norm.env, ancestry: 0))
            child = child + 1
        }
        at = at + 1
    }
    return Ok(true)
}

fn ancestry_has(ancestry: __s0_Buffer(DeclAncestryRec), id: U64, target: U64) -> Bool {
    var at = id
    while at != 0 {
        let item = __s0_buffer_get(DeclAncestryRec, ancestry, at - 1)
        if item.target == target { return true }
        at = item.parent
    }
    return false
}

fn build_target_env(d: Domain, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), target: U64, checked: CheckedTypeRec, caller_env: U64, caller_ancestry: U64) -> Result(__s0_Buffer(TypeBindingRec), __s0_Error) {
    var result = bindings
    var head: U64 = 0
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let param = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if param.owner == target {
            result = try __s0_buffer_append(TypeBindingRec, d, result, TypeBindingRec(param: at + 1, checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal), caller_env: caller_env, caller_ancestry: caller_ancestry, next: head))
            head = __s0_buffer_len(TypeBindingRec, result)
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return Ok(result)
}

fn declaration_env_head(bindings: __s0_Buffer(TypeBindingRec), old_len: U64) -> U64 {
    if __s0_buffer_len(TypeBindingRec, bindings) == old_len { return 0 }
    return __s0_buffer_len(TypeBindingRec, bindings)
}

fn push_decl_members(d: Domain, store: CheckStore, work: __s0_Buffer(InterpWorkRec), target: U64, env: U64, ancestry: U64) -> Result(__s0_Buffer(InterpWorkRec), __s0_Error) {
    var result = work
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            result = try __s0_buffer_append(InterpWorkRec, d, result, InterpWorkRec(checked_type: use.checked_type, env: env, ancestry: ancestry))
        }
        at = at + 1
    }
    return Ok(result)
}

// During aggregate resolution only earlier aggregate declarations are
// complete enough to inspect. Zero means every aggregate is complete, as it is
// during final revalidation and import/function checking.
fn declaration_available(boundary: U64, target: U64) -> Bool {
    return boundary == 0 || target < boundary
}

fn declaration_boundary(store: CheckStore, owner: U64) -> U64 {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if symbol.kind == 2 || symbol.kind == 3 { return owner }
    return 0
}

// Reusing a specialization is context independent unless it can reach one of
// the current active declarations. Inspecting every supplied argument and each
// declaration body once by target is conservative without unfolding a finite
// declaration DAG once per path.
fn interpreted_may_reach_ancestry(d: Domain, store: CheckStore, initial_bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64, active: U64, ancestry: __s0_Buffer(DeclAncestryRec)) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    let first_seen = try __s0_buffer_new(InterpStateRec, d)
    var seen = first_seen
    let first_targets = try __s0_buffer_new(ExpansionMemoRec, d)
    var targets = first_targets
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, 0)
        if !interp_state_seen(seen, 0, norm.checked_type, norm.env, 0) {
            seen = try __s0_buffer_append(InterpStateRec, d, seen, InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: 0))
            let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
            if checked.kind == 6 { return Ok(true) }
            if checked.kind == 7 && ancestry_has(ancestry, active, checked.target) { return Ok(true) }
            var child: U64 = 0
            while child < checked.arg_count {
                work = try __s0_buffer_append(InterpWorkRec, d, work, InterpWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), env: norm.env, ancestry: 0))
                child = child + 1
            }
            if checked.kind == 7 && !expansion_target_seen(targets, checked.target) {
                targets = try remember_expansion(d, targets, 0, checked.target, norm.checked_type, norm.env)
                let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, 0)
                let target_env = declaration_env_head(bindings, old_len)
                work = try push_decl_members(d, store, work, checked.target, target_env, 0)
            }
        }
        at = at + 1
    }
    return Ok(false)
}

// This mirrors frontend/types.go containsSlice. Repeated declaration targets
// are cut per path, while equivalent interpreted specializations are expanded
// once per probe. Inherited ancestry keeps binding IDs in their owning buffer.
fn interpreted_contains_reference(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: __s0_Buffer(TypeBindingRec), initial_ancestry: __s0_Buffer(DeclAncestryRec), checked_type: U64, env: U64, ancestry_id: U64, boundary: U64) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: ancestry_id))
    var ancestry = initial_ancestry
    let first_memo = try __s0_buffer_new(ExpansionMemoRec, d)
    var memo = first_memo
    let first_seen = try __s0_buffer_new(InterpStateRec, d)
    var seen = first_seen
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { seen = try __s0_buffer_append(InterpStateRec, d, seen, InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 2 || checked.kind == 3 || checked.kind == 4 || checked.kind == 8 || checked.kind == 11 || checked.kind == 12 || checked.kind == 13 { return Ok(true) }
            if checked.kind == 9 || checked.kind == 10 {
                var child: U64 = 0
                while child < checked.arg_count {
                    work = try __s0_buffer_append(InterpWorkRec, d, work, InterpWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), env: norm.env, ancestry: norm.ancestry))
                    child = child + 1
                }
            }
            if checked.kind == 7 && declaration_available(boundary, checked.target) && !ancestry_has(ancestry, norm.ancestry, checked.target) {
                if !(try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)) {
                    memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                    let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                    bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                    let target_env = declaration_env_head(bindings, old_len)
                    ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                    work = try push_decl_members(d, store, work, checked.target, target_env, __s0_buffer_len(DeclAncestryRec, ancestry))
                }
            }
        }
        at = at + 1
    }
    return Ok(false)
}

fn primitive_map_key(state: State, parse: ParseStore, checked: CheckedTypeRec) -> Bool {
    return checked.kind == 1 && (checked.target == 1 || (checked.target >= 6 && checked.target <= 9))
}

fn interpreted_map_key_ok(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: __s0_Buffer(TypeBindingRec), initial_ancestry: __s0_Buffer(DeclAncestryRec), checked_type: U64, env: U64, ancestry_id: U64, boundary: U64) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: ancestry_id))
    var ancestry = initial_ancestry
    let first_memo = try __s0_buffer_new(ExpansionMemoRec, d)
    var memo = first_memo
    let first_seen = try __s0_buffer_new(InterpStateRec, d)
    var seen = first_seen
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { seen = try __s0_buffer_append(InterpStateRec, d, seen, InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 1 {
                if !primitive_map_key(state, parse, checked) { return Ok(false) }
            } else {
                if checked.kind == 7 && declaration_available(boundary, checked.target) {
                    if !ancestry_has(ancestry, norm.ancestry, checked.target) {
                        if !(try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)) {
                            memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                            let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                            bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                            let target_env = declaration_env_head(bindings, old_len)
                            ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                            work = try push_decl_members(d, store, work, checked.target, target_env, __s0_buffer_len(DeclAncestryRec, ancestry))
                        }
                    }
                } else {
                    if checked.kind != 7 { return Ok(false) }
                }
            }
        }
        at = at + 1
    }
    return Ok(true)
}

fn specialization_equal(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), checked: CheckedTypeRec, caller_env: U64, active_env: U64) -> Result(Bool, __s0_Error) {
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let param = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if param.owner == checked.target {
            let active = env_lookup(bindings, active_env, at + 1)
            if active.param == 0 || !(try interpreted_type_equal(d, state, parse, store, bindings, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal), caller_env, active.checked_type, active.caller_env)) { return Ok(false) }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return Ok(true)
}

fn active_target(ancestry: __s0_Buffer(DeclAncestryRec), id: U64, target: U64) -> U64 {
    var at = id
    while at != 0 {
        let item = __s0_buffer_get(DeclAncestryRec, ancestry, at - 1)
        if item.target == target { return at }
        at = item.parent
    }
    return 0
}

fn syntax_diag_node(state: State, parse: ParseStore, syntax: U64) -> SyntaxRec {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, syntax - 1)
    if node.name_end != 0 || node.name_start != 0 { return node }
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    return SyntaxRec(kind: node.kind, token: node.token, source: token.source, start: token.start, end: token.end, name_start: token.start, name_end: token.end, children: node.children)
}

// Complete concrete validation uses a persistent LIFO stack. Continuations and
// active declaration chains are immutable IDs, preserving recursive DFS error
// order without using the host call stack.
fn validate_concrete_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, root_type: U64, root_env: U64, root_node: SyntaxRec, boundary: U64) -> Result(CheckResult, __s0_Error) {
    let empty_bindings = try __s0_buffer_new(TypeBindingRec, d)
    var bindings = empty_bindings
    let empty_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    var ancestry = empty_ancestry
    let empty_memo = try __s0_buffer_new(ExpansionMemoRec, d)
    var memo = empty_memo
    let empty_seen = try __s0_buffer_new(InterpStateRec, d)
    var seen = empty_seen
    let empty_work = try __s0_buffer_new(ValidationWorkRec, d)
    var work = try __s0_buffer_append(ValidationWorkRec, d, empty_work, ValidationWorkRec(checked_type: root_type, env: root_env, ancestry: 0, next: 0))
    var head: U64 = 1
    while head != 0 {
        let item = __s0_buffer_get(ValidationWorkRec, work, head - 1)
        head = item.next
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { seen = try __s0_buffer_append(InterpStateRec, d, seen, InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 8 {
                let child = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, child, norm.env, norm.ancestry, boundary) { return check_fail(d, store, 10, root_node, 0, 0, 0) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: child, env: norm.env, ancestry: norm.ancestry, next: head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 9 || checked.kind == 12 {
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env: norm.env, ancestry: norm.ancestry, next: head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 13 {
                let child = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, child, norm.env, norm.ancestry, boundary) { return check_fail(d, store, 11, root_node, 0, 0, 0) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: child, env: norm.env, ancestry: norm.ancestry, next: head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 10 {
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg), env: norm.env, ancestry: norm.ancestry, next: head))
                let err_head = __s0_buffer_len(ValidationWorkRec, work)
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env: norm.env, ancestry: norm.ancestry, next: err_head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 11 {
                let key = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
                let value = __s0_buffer_get(U64, store.type_args, checked.first_arg)
                if !(try interpreted_map_key_ok(d, state, parse, store, bindings, ancestry, key, norm.env, norm.ancestry, boundary)) { return check_fail(d, store, 12, root_node, 0, 0, 0) }
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, value, norm.env, norm.ancestry, boundary) { return check_fail(d, store, 13, root_node, 0, 0, 0) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: value, env: norm.env, ancestry: norm.ancestry, next: head))
                let value_head = __s0_buffer_len(ValidationWorkRec, work)
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: key, env: norm.env, ancestry: norm.ancestry, next: value_head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 7 && declaration_available(boundary, checked.target) {
                let active = active_target(ancestry, norm.ancestry, checked.target)
                if active != 0 {
                    let prior = __s0_buffer_get(DeclAncestryRec, ancestry, active - 1)
                    if !(try specialization_equal(d, state, parse, store, bindings, checked, norm.env, prior.env)) { return check_fail(d, store, 14, root_node, 0, 0, 0) }
                } else {
                    var reuse = try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)
                    if reuse {
                        if try interpreted_may_reach_ancestry(d, store, bindings, norm.checked_type, norm.env, norm.ancestry, ancestry) { reuse = false }
                    }
                    if !reuse {
                        memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                        let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                        bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                        let target_env = declaration_env_head(bindings, old_len)
                        ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                        let chain = __s0_buffer_len(DeclAncestryRec, ancestry)
                        var use_at = __s0_buffer_len(DeclTypeUseRec, store.uses)
                        while use_at != 0 {
                            use_at = use_at - 1
                            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_at)
                            if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
                                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: use.checked_type, env: target_env, ancestry: chain, next: head))
                                head = __s0_buffer_len(ValidationWorkRec, work)
                            }
                        }
                    }
                }
            }
        }
    }
    return Ok(CheckGood(store))
}

fn same_name(state: State, a_source: U64, a_start: U64, a_end: U64, b_source: U64, b_start: U64, b_end: U64) -> Bool {
    if a_end - a_start != b_end - b_start { return false }
    let a = __s0_buffer_get(SourceRec, state.sources, a_source)
    let b = __s0_buffer_get(SourceRec, state.sources, b_source)
    var at: U64 = 0
    while at < a_end - a_start {
        if text_byte(state, a, a_start + at) != text_byte(state, b, b_start + at) { return false }
        at = at + 1
    }
    return true
}

fn node_word(state: State, node: SyntaxRec, word: String) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, node.source)
    return source_word(state, source, node.name_start, node.name_end, word)
}

fn reserved_symbol(state: State, node: SyntaxRec) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, node.source)
    if node.name_end - node.name_start >= 5 && source_word(state, source, node.name_start, node.name_start + 5, "__s0_") { return true }
    return node_word(state, node, "Bool") || node_word(state, node, "I8") || node_word(state, node, "I16") || node_word(state, node, "I32") || node_word(state, node, "I64") || node_word(state, node, "U8") || node_word(state, node, "U16") || node_word(state, node, "U32") || node_word(state, node, "U64") || node_word(state, node, "F32") || node_word(state, node, "F64") || node_word(state, node, "Unit") || node_word(state, node, "String") || node_word(state, node, "Option") || node_word(state, node, "Result") || node_word(state, node, "Map") || node_word(state, node, "Ptr") || node_word(state, node, "Domain") || node_word(state, node, "DomainMark") || node_word(state, node, "__s0_Buffer") || node_word(state, node, "__s0_Error") || node_word(state, node, "len") || node_word(state, node, "range") || node_word(state, node, "Get") || node_word(state, node, "Set") || node_word(state, node, "Remove") || node_word(state, node, "None") || node_word(state, node, "Some") || node_word(state, node, "Ok") || node_word(state, node, "Err")
}

fn reserved_value_name(state: State, store: CheckStore, node: SyntaxRec) -> Bool {
    if reserved_symbol(state, node) { return true }
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if (symbol.kind == 2 || symbol.kind == 3) && same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return true }
        at = at + 1
    }
    return false
}

fn check_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, related_source: U64, related_start: U64, related_end: U64) -> Result(CheckResult, __s0_Error) {
    let item = CheckDiagRec(kind: kind, source: node.source, start: node.name_start, end: node.name_end, related_source: related_source, related_start: related_start, related_end: related_end)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: diagnostics)))
}

fn check_decl_fail(d: Domain, state: State, parse: ParseStore, store: CheckStore, kind: U64, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.node - 1)
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: diagnostics)))
}

fn check_token_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: diagnostics)))
}

fn symbol_arity(parse: ParseStore, node: SyntaxRec) -> U64 {
    if node.kind == 1 { return 0 }
    var count: U64 = 0
    var link = node.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        if __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1).kind == 7 { count = count + 1 }
        link = item.next
    }
    return count
}

fn collect_symbols(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    var store = initial
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        let node_id = __s0_buffer_get(U64, parse.roots, root_at)
        let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
        var previous: U64 = 0
        while previous < __s0_buffer_len(SymbolRec, store.symbols) {
            let first = __s0_buffer_get(SymbolRec, store.symbols, previous)
            if same_name(state, node.source, node.name_start, node.name_end, first.source, first.name_start, first.name_end) {
                return check_fail(d, store, 1, node, first.source, first.name_start, first.name_end)
            }
            previous = previous + 1
        }
        if reserved_symbol(state, node) { return check_fail(d, store, 2, node, 0, 0, 0) }
        let symbol_id = __s0_buffer_len(SymbolRec, store.symbols) + 1
        var declaration: U64 = 0
        if node.kind == 12 && symbol_arity(parse, node) == 0 { declaration = symbol_id }
        let symbol = SymbolRec(kind: node.kind, node: node_id, source: node.source, name_start: node.name_start, name_end: node.name_end, type_arity: symbol_arity(parse, node), declaration: declaration, first_instance_arg: 0, instance_arg_count: 0, discovery_parent: 0)
        let symbols = try __s0_buffer_append(SymbolRec, d, store.symbols, symbol)
        store = CheckStore(symbols: symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)
        root_at = root_at + 1
    }
    return Ok(CheckGood(store))
}

fn append_type_param(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let first = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if first.owner == owner && same_name(state, node.source, node.name_start, node.name_end, first.source, first.name_start, first.name_end) {
            return check_fail(d, store, 3, node, first.source, first.name_start, first.name_end)
        }
        at = at + 1
    }
    let params = try __s0_buffer_append(TypeParamRec, d, store.type_params, TypeParamRec(owner: owner, node: node_id, source: node.source, name_start: node.name_start, name_end: node.name_end))
    return Ok(CheckGood(CheckStore(symbols: store.symbols, type_params: params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)))
}

fn collect_param_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(CheckResult, __s0_Error) {
    if link_id == 0 { return Ok(CheckGood(store)) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let earlier = try collect_param_links(d, state, parse, store, owner, link.next)
    let current = match earlier {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match earlier {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(earlier) }
    if __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1).kind != 7 { return Ok(CheckGood(current)) }
    return append_type_param(d, state, parse, current, owner, link.node)
}

fn find_type_param(state: State, store: CheckStore, owner: U64, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let p = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if p.owner == owner && same_name(state, node.source, node.name_start, node.name_end, p.source, p.name_start, p.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn find_declared_type(state: State, store: CheckStore, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if (symbol.kind == 2 || symbol.kind == 3) && same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn builtin_type_kind(state: State, node: SyntaxRec) -> U64 {
    if node_word(state, node, "String") { return 2 }
    if node_word(state, node, "Domain") { return 3 }
    if node_word(state, node, "DomainMark") { return 4 }
    if node_word(state, node, "__s0_Error") { return 5 }
    if node_word(state, node, "Bool") || node_word(state, node, "I8") || node_word(state, node, "I16") || node_word(state, node, "I32") || node_word(state, node, "I64") || node_word(state, node, "U8") || node_word(state, node, "U16") || node_word(state, node, "U32") || node_word(state, node, "U64") || node_word(state, node, "F32") || node_word(state, node, "F64") || node_word(state, node, "Unit") { return 1 }
    return 0
}

fn primitive_type_target(state: State, node: SyntaxRec) -> U64 {
    if node_word(state, node, "Bool") { return 1 }
    if node_word(state, node, "I8") { return 2 }
    if node_word(state, node, "I16") { return 3 }
    if node_word(state, node, "I32") { return 4 }
    if node_word(state, node, "I64") { return 5 }
    if node_word(state, node, "U8") { return 6 }
    if node_word(state, node, "U16") { return 7 }
    if node_word(state, node, "U32") { return 8 }
    if node_word(state, node, "U64") { return 9 }
    if node_word(state, node, "F32") { return 10 }
    if node_word(state, node, "F64") { return 11 }
    if node_word(state, node, "Unit") { return 12 }
    return 0
}

fn canonical_type_id(store: CheckStore, kind: U64, target: U64, first_arg: U64, arg_count: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if checked.kind == kind && checked.target == target && checked.arg_count == arg_count {
            var same = true
            var arg: U64 = 0
            while arg < arg_count {
                if __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + arg) != __s0_buffer_get(U64, store.type_args, first_arg - 1 + arg) { same = false }
                arg = arg + 1
            }
            if same { return at + 1 }
        }
        at = at + 1
    }
    return 0
}

fn canonical_single_arg(store: CheckStore, kind: U64, target: U64, arg: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if checked.kind == kind && checked.target == target && checked.arg_count == 1 && __s0_buffer_get(U64, store.type_args, checked.first_arg - 1) == arg { return at + 1 }
        at = at + 1
    }
    return 0
}

fn canonical_type_for_children(store: CheckStore, kind: U64, target: U64, children: __s0_Buffer(U64)) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if checked.kind == kind && checked.target == target && checked.arg_count == __s0_buffer_len(U64, children) {
            var same = true
            var ordinal: U64 = 0
            while ordinal < checked.arg_count {
                if __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal) != __s0_buffer_get(U64, children, ordinal) { same = false }
                ordinal = ordinal + 1
            }
            if same { return at + 1 }
        }
        at = at + 1
    }
    return 0
}

fn annotate_checked_type(d: Domain, store: CheckStore, owner: U64, syntax: U64, checked_type: U64) -> Result(CheckStore, __s0_Error) {
    if syntax == 0 { return Ok(store) }
    let annotations = try __s0_buffer_append(CheckedTypeAnnotationRec, d, store.type_annotations, CheckedTypeAnnotationRec(owner: owner, syntax: syntax, checked_type: checked_type))
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics))
}

fn append_checked_type(d: Domain, store: CheckStore, owner: U64, kind: U64, syntax: U64, target: U64, first_arg: U64, arg_count: U64) -> Result(CheckStore, __s0_Error) {
    let existing = canonical_type_id(store, kind, target, first_arg, arg_count)
    if existing != 0 { return annotate_checked_type(d, store, owner, syntax, existing) }
    let types = try __s0_buffer_append(CheckedTypeRec, d, store.types, CheckedTypeRec(kind: kind, syntax: 0, target: target, first_arg: first_arg, arg_count: arg_count))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)
    return annotate_checked_type(d, next, owner, syntax, __s0_buffer_len(CheckedTypeRec, types))
}

fn instance_declaration(store: CheckStore, owner: U64) -> U64 {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if symbol.kind == 13 { return symbol.declaration }
    return owner
}

fn type_param_ordinal(store: CheckStore, declaration: U64, param: U64) -> U64 {
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let item = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if item.owner == declaration {
            if at + 1 == param { return ordinal }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return ordinal
}

fn instance_type_arg(store: CheckStore, instance: U64, param: U64) -> U64 {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, instance - 1)
    if symbol.kind != 13 { return 0 }
    let ordinal = type_param_ordinal(store, symbol.declaration, param)
    if ordinal >= symbol.instance_arg_count { return 0 }
    return __s0_buffer_get(U64, store.type_args, symbol.first_instance_arg - 1 + ordinal)
}

fn inference_lookup(bindings: __s0_Buffer(InferenceBindingRec), param: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(InferenceBindingRec, bindings) {
        let binding = __s0_buffer_get(InferenceBindingRec, bindings, at)
        if binding.param == param { return binding.checked_type }
        at = at + 1
    }
    return 0
}

fn checked_type_concrete(store: CheckStore, checked_type: U64) -> Bool {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 6 { return false }
    var ordinal: U64 = 0
    while ordinal < checked.arg_count {
        if !checked_type_concrete(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal)) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn substitute_children(d: Domain, store: CheckStore, bindings: __s0_Buffer(InferenceBindingRec), original: CheckStore, checked: CheckedTypeRec, ordinal: U64, children: __s0_Buffer(U64)) -> Result(SubstitutedChildrenRec, __s0_Error) {
    if ordinal == checked.arg_count { return Ok(SubstitutedChildrenRec(store: store, children: children)) }
    let child = try substitute_type(d, store, bindings, __s0_buffer_get(U64, original.type_args, checked.first_arg - 1 + ordinal))
    let next = try __s0_buffer_append(U64, d, children, child.checked_type)
    return substitute_children(d, child.store, bindings, original, checked, ordinal + 1, next)
}

fn append_substituted_children(d: Domain, store: CheckStore, children: __s0_Buffer(U64), ordinal: U64) -> Result(CheckStore, __s0_Error) {
    if ordinal == __s0_buffer_len(U64, children) { return Ok(store) }
    let args = try __s0_buffer_append(U64, d, store.type_args, __s0_buffer_get(U64, children, ordinal))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)
    return append_substituted_children(d, next, children, ordinal + 1)
}

fn substitute_type(d: Domain, store: CheckStore, bindings: __s0_Buffer(InferenceBindingRec), checked_type: U64) -> Result(TypeValueRec, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 6 {
        let bound = inference_lookup(bindings, checked.target)
        return Ok(TypeValueRec(store: store, checked_type: bound))
    }
    if checked.arg_count == 0 { return Ok(TypeValueRec(store: store, checked_type: checked_type)) }
    let empty_children = try __s0_buffer_new(U64, d)
    let substituted = try substitute_children(d, store, bindings, store, checked, 0, empty_children)
    var current = substituted.store
    let prior = canonical_type_for_children(current, checked.kind, checked.target, substituted.children)
    if prior != 0 { return Ok(TypeValueRec(store: current, checked_type: prior)) }
    let first = __s0_buffer_len(U64, current.type_args) + 1
    current = try append_substituted_children(d, current, substituted.children, 0)
    current = try append_checked_type(d, current, 0, checked.kind, 0, checked.target, first, checked.arg_count)
    return Ok(TypeValueRec(store: current, checked_type: canonical_type_id(current, checked.kind, checked.target, first, checked.arg_count)))
}

fn unify_type_children(d: Domain, store: CheckStore, expected: CheckedTypeRec, actual: CheckedTypeRec, ordinal: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(UnifyOutcome, __s0_Error) {
    if ordinal == expected.arg_count { return Ok(UnifyGood(bindings)) }
    let step = try unify_types(d, store, __s0_buffer_get(U64, store.type_args, expected.first_arg - 1 + ordinal), __s0_buffer_get(U64, store.type_args, actual.first_arg - 1 + ordinal), bindings)
    return match step {
        UnifyGood(value) => unify_type_children(d, store, expected, actual, ordinal + 1, value)
        UnifyConflict => Ok(UnifyConflict)
    }
}

fn unify_types(d: Domain, store: CheckStore, pattern: U64, concrete: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(UnifyOutcome, __s0_Error) {
    let expected = __s0_buffer_get(CheckedTypeRec, store.types, pattern - 1)
    if expected.kind == 6 {
        let prior = inference_lookup(bindings, expected.target)
        if prior == 0 {
            let next = try __s0_buffer_append(InferenceBindingRec, d, bindings, InferenceBindingRec(param: expected.target, checked_type: concrete))
            return Ok(UnifyGood(next))
        }
        if prior == concrete { return Ok(UnifyGood(bindings)) }
        return Ok(UnifyConflict)
    }
    let actual = __s0_buffer_get(CheckedTypeRec, store.types, concrete - 1)
    if expected.kind != actual.kind || expected.target != actual.target || expected.arg_count != actual.arg_count { return Ok(UnifyConflict) }
    return unify_type_children(d, store, expected, actual, 0, bindings)
}

fn instance_matches(store: CheckStore, symbol: SymbolRec, declaration: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Bool {
    if symbol.kind != 13 || symbol.declaration != declaration || symbol.instance_arg_count != __s0_buffer_get(SymbolRec, store.symbols, declaration - 1).type_arity { return false }
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let param = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if param.owner == declaration {
            if __s0_buffer_get(U64, store.type_args, symbol.first_instance_arg - 1 + ordinal) != inference_lookup(bindings, at + 1) { return false }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return true
}

fn existing_instance(store: CheckStore, declaration: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> U64 {
    let declared = __s0_buffer_get(SymbolRec, store.symbols, declaration - 1)
    if declared.type_arity == 0 { return declaration }
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if instance_matches(store, symbol, declaration, bindings) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn expanding_ancestry(store: CheckStore, declaration: U64, bindings: __s0_Buffer(InferenceBindingRec), parent: U64) -> Bool {
    var at = parent
    while at != 0 {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at - 1)
        if symbol.declaration == declaration && !instance_matches(store, symbol, declaration, bindings) { return true }
        at = symbol.discovery_parent
    }
    return false
}

fn append_instance_args(d: Domain, store: CheckStore, declaration: U64, bindings: __s0_Buffer(InferenceBindingRec), param_at: U64) -> Result(CheckStore, __s0_Error) {
    if param_at == __s0_buffer_len(TypeParamRec, store.type_params) { return Ok(store) }
    let param = __s0_buffer_get(TypeParamRec, store.type_params, param_at)
    var next = store
    if param.owner == declaration {
        let args = try __s0_buffer_append(U64, d, store.type_args, inference_lookup(bindings, param_at + 1))
        next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)
    }
    return append_instance_args(d, next, declaration, bindings, param_at + 1)
}

fn append_instance_uses(d: Domain, store: CheckStore, declaration: U64, instance: U64, bindings: __s0_Buffer(InferenceBindingRec), use_at: U64) -> Result(CheckStore, __s0_Error) {
    if use_at == __s0_buffer_len(DeclTypeUseRec, store.uses) { return Ok(store) }
    let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_at)
    var next = store
    if use.owner == declaration && (use.role == 5 || use.role == 6) {
        let concrete = try substitute_type(d, store, bindings, use.checked_type)
        var role: U64 = 7
        if use.role == 6 { role = 8 }
        let uses = try __s0_buffer_append(DeclTypeUseRec, d, concrete.store.uses, DeclTypeUseRec(owner: instance, role: role, ordinal: use.ordinal, node: use.node, source: use.source, name_start: use.name_start, name_end: use.name_end, syntax: use.syntax, checked_type: concrete.checked_type))
        next = CheckStore(symbols: concrete.store.symbols, type_params: concrete.store.type_params, types: concrete.store.types, type_args: concrete.store.type_args, type_annotations: concrete.store.type_annotations, uses: uses, locals: concrete.store.locals, environments: concrete.store.environments, expressions: concrete.store.expressions, call_annotations: concrete.store.call_annotations, expression_children: concrete.store.expression_children, returns: concrete.store.returns, diagnostics: concrete.store.diagnostics)
    }
    return append_instance_uses(d, next, declaration, instance, bindings, use_at + 1)
}

fn instantiate_function(d: Domain, state: State, parse: ParseStore, store: CheckStore, declaration: U64, bindings: __s0_Buffer(InferenceBindingRec), parent: U64, site: SyntaxRec) -> Result(InstanceOutcome, __s0_Error) {
    let found = existing_instance(store, declaration, bindings)
    if found != 0 { return Ok(InstanceGood(InstanceValueRec(store: store, instance: found))) }
    if expanding_ancestry(store, declaration, bindings, parent) {
        let failed = try check_token_fail(d, state, store, 59, site)
        return Ok(InstanceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let declared = __s0_buffer_get(SymbolRec, store.symbols, declaration - 1)
    var param_at: U64 = 0
    while param_at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let param = __s0_buffer_get(TypeParamRec, store.type_params, param_at)
        if param.owner == declaration {
            let bound = inference_lookup(bindings, param_at + 1)
            if bound == 0 || !checked_type_concrete(store, bound) {
                let failed = try check_token_fail(d, state, store, 57, site)
                return Ok(InstanceBad(match failed {
                    CheckGood(value) => value
                    CheckBad(value) => value
                }))
            }
        }
        param_at = param_at + 1
    }
    let first = __s0_buffer_len(U64, store.type_args) + 1
    let with_args = try append_instance_args(d, store, declaration, bindings, 0)
    let instance = __s0_buffer_len(SymbolRec, with_args.symbols) + 1
    let symbols = try __s0_buffer_append(SymbolRec, d, with_args.symbols, SymbolRec(kind: 13, node: declared.node, source: declared.source, name_start: declared.name_start, name_end: declared.name_end, type_arity: 0, declaration: declaration, first_instance_arg: first, instance_arg_count: declared.type_arity, discovery_parent: parent))
    let registered = CheckStore(symbols: symbols, type_params: with_args.type_params, types: with_args.types, type_args: with_args.type_args, type_annotations: with_args.type_annotations, uses: with_args.uses, locals: with_args.locals, environments: with_args.environments, expressions: with_args.expressions, call_annotations: with_args.call_annotations, expression_children: with_args.expression_children, returns: with_args.returns, diagnostics: with_args.diagnostics)
    let signed = try append_instance_uses(d, registered, declaration, instance, bindings, 0)
    return Ok(InstanceGood(InstanceValueRec(store: signed, instance: instance)))
}

// Type children are reverse linked. Resolve every child (including its nested
// children) before recording this node's direct arguments.
fn resolve_arg_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(CheckResult, __s0_Error) {
    if link_id == 0 { return Ok(CheckGood(store)) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let before = try resolve_arg_links(d, state, parse, store, owner, link.next)
    let current = match before {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match before {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(before) }
    let resolved = try resolve_type(d, state, parse, current, owner, link.node)
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    return Ok(resolved)
}

fn checked_type_for_syntax(store: CheckStore, syntax: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeAnnotationRec, store.type_annotations) {
        let annotation = __s0_buffer_get(CheckedTypeAnnotationRec, store.type_annotations, at)
        if annotation.syntax == syntax { return annotation.checked_type }
        at = at + 1
    }
    return 0
}

// Append only the current node's direct children, in source order. Since all
// recursive resolution is already complete, this range remains contiguous.
fn record_arg_links(d: Domain, parse: ParseStore, store: CheckStore, link_id: U64) -> Result(CheckStore, __s0_Error) {
    if link_id == 0 { return Ok(store) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let current = try record_arg_links(d, parse, store, link.next)
    let checked = checked_type_for_syntax(current, link.node)
    let args = try __s0_buffer_append(U64, d, current.type_args, checked)
    return Ok(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, diagnostics: current.diagnostics))
}

fn type_arg_count(parse: ParseStore, link_id: U64) -> U64 {
    var count: U64 = 0
    var at = link_id
    while at != 0 {
        let link = __s0_buffer_get(SyntaxLinkRec, parse.links, at - 1)
        count = count + 1
        at = link.next
    }
    return count
}

fn canonical_type_for_links(parse: ParseStore, store: CheckStore, kind: U64, target: U64, link_id: U64) -> U64 {
    let count = type_arg_count(parse, link_id)
    var type_at: U64 = 0
    while type_at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, type_at)
        if checked.kind == kind && checked.target == target && checked.arg_count == count {
            var same = true
            var link_at = link_id
            var ordinal = count
            while link_at != 0 {
                ordinal = ordinal - 1
                let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
                if __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal) != checked_type_for_syntax(store, link.node) { same = false }
                link_at = link.next
            }
            if same { return type_at + 1 }
        }
        type_at = type_at + 1
    }
    return 0
}

// C imports deliberately use a smaller syntactic type surface than ordinary
// Alder declarations: primitives and exactly Ptr(primitive). Check this before
// general resolution so unsupported signatures receive the import diagnostic,
// not a nested representation or unknown-type diagnostic.
fn ffi_type_syntax_ok(state: State, parse: ParseStore, node_id: U64) -> Bool {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 4 { return builtin_type_kind(state, node) == 1 }
    if node.kind != 6 || !node_word(state, node, "Ptr") || type_arg_count(parse, node.children) != 1 { return false }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, node.children - 1)
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    return child.kind == 4 && builtin_type_kind(state, child) == 1
}

fn resolve_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    let boundary = declaration_boundary(store, owner)
    if node.kind == 5 {
        let args = try resolve_arg_links(d, state, parse, store, owner, node.children)
        let current = match args {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        if match args {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(args) }
        let existing = canonical_type_for_links(parse, current, 8, 0, node.children)
        var appended = current
        if existing != 0 { appended = try annotate_checked_type(d, current, owner, node_id, existing) } else {
            let start = __s0_buffer_len(U64, current.type_args)
            let recorded = try record_arg_links(d, parse, current, node.children)
            appended = try append_checked_type(d, recorded, owner, 8, node_id, 0, start + 1, 1)
        }
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
        let checked_id = checked_type_for_syntax(appended, node_id)
        let canonical = __s0_buffer_get(CheckedTypeRec, appended.types, checked_id - 1)
        let child = __s0_buffer_get(U64, appended.type_args, canonical.first_arg - 1)
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, child, 0, 0, boundary) { return check_fail(d, appended, 10, syntax_diag_node(state, parse, node_id), 0, 0, 0) }
        return Ok(CheckGood(appended))
    }
    if node.kind == 4 {
        let builtin = builtin_type_kind(state, node)
        if builtin == 1 { return Ok(CheckGood(try append_checked_type(d, store, owner, 1, node_id, primitive_type_target(state, node), 0, 0))) }
        if builtin == 2 {
            let with_u8 = try append_checked_type(d, store, owner, 1, 0, 6, 0, 0)
            let u8 = canonical_type_id(with_u8, 1, 6, 0, 0)
            let existing_string = canonical_single_arg(with_u8, 8, 0, u8)
            if existing_string != 0 { return Ok(CheckGood(try annotate_checked_type(d, with_u8, owner, node_id, existing_string))) }
            let args = try __s0_buffer_append(U64, d, with_u8.type_args, u8)
            let recorded = CheckStore(symbols: with_u8.symbols, type_params: with_u8.type_params, types: with_u8.types, type_args: args, type_annotations: with_u8.type_annotations, uses: with_u8.uses, locals: with_u8.locals, environments: with_u8.environments, expressions: with_u8.expressions, call_annotations: with_u8.call_annotations, expression_children: with_u8.expression_children, returns: with_u8.returns, diagnostics: with_u8.diagnostics)
            return Ok(CheckGood(try append_checked_type(d, recorded, owner, 8, node_id, 0, __s0_buffer_len(U64, args), 1)))
        }
        if builtin != 0 { return Ok(CheckGood(try append_checked_type(d, store, owner, builtin, node_id, 0, 0, 0))) }
        let declaration = instance_declaration(store, owner)
        let param = find_type_param(state, store, declaration, node)
        if param != 0 {
            let concrete = instance_type_arg(store, owner, param)
            if concrete != 0 { return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, concrete))) }
            return Ok(CheckGood(try append_checked_type(d, store, owner, 6, node_id, param, 0, 0)))
        }
        let symbol = find_declared_type(state, store, node)
        if symbol == 0 { return check_fail(d, store, 4, node, 0, 0, 0) }
        if __s0_buffer_get(SymbolRec, store.symbols, symbol - 1).type_arity != 0 { return check_fail(d, store, 5, node, 0, 0, 0) }
        let appended = try append_checked_type(d, store, owner, 7, node_id, symbol, 0, 0)
        let checked_id = checked_type_for_syntax(appended, node_id)
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, syntax_diag_node(state, parse, node_id), boundary)
    }
    let args = try resolve_arg_links(d, state, parse, store, owner, node.children)
    let current = match args {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match args {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(args) }
    let count = type_arg_count(parse, node.children)
    var kind: U64 = 0
    var arity: U64 = 0
    if node_word(state, node, "Option") { kind = 9
        arity = 1 }
    if node_word(state, node, "Result") { kind = 10
        arity = 2 }
    if node_word(state, node, "Map") { kind = 11
        arity = 2 }
    if node_word(state, node, "Ptr") { kind = 12
        arity = 1 }
    if node_word(state, node, "__s0_Buffer") { kind = 13
        arity = 1 }
    var target: U64 = 0
    if kind == 0 {
        target = find_declared_type(state, current, node)
        if target != 0 { kind = 7
            arity = __s0_buffer_get(SymbolRec, current.symbols, target - 1).type_arity }
    }
    // Do not commit a direct-argument range until the application itself is
    // valid. Failed heads and arities retain resolved child types but never
    // leave ownerless type-argument records in a CheckBad store.
    if kind == 0 { return check_fail(d, current, 4, node, 0, 0, 0) }
    if count != arity { return check_fail(d, current, 5, node, 0, 0, 0) }
    let existing = canonical_type_for_links(parse, current, kind, target, node.children)
    var appended = current
    if existing != 0 { appended = try annotate_checked_type(d, current, owner, node_id, existing) } else {
        let start = __s0_buffer_len(U64, current.type_args)
        let recorded = try record_arg_links(d, parse, current, node.children)
        var first: U64 = 0
        if count != 0 { first = start + 1 }
        appended = try append_checked_type(d, recorded, owner, kind, node_id, target, first, count)
    }
    let checked_id = checked_type_for_syntax(appended, node_id)
    let checked = __s0_buffer_get(CheckedTypeRec, appended.types, checked_id - 1)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    if kind == 13 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let child = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, child, 0, 0, boundary) { return check_fail(d, appended, 11, syntax_diag_node(state, parse, node_id), 0, 0, 0) }
    }
    if kind == 11 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let key = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
        let value = __s0_buffer_get(U64, appended.type_args, checked.first_arg)
        if !(try interpreted_map_key_ok(d, state, parse, appended, empty, no_ancestry, key, 0, 0, boundary)) { return check_fail(d, appended, 12, syntax_diag_node(state, parse, node_id), 0, 0, 0) }
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, value, 0, 0, boundary) { return check_fail(d, appended, 13, syntax_diag_node(state, parse, node_id), 0, 0, 0) }
    }
    if kind == 7 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, syntax_diag_node(state, parse, node_id), boundary)
    }
    return Ok(CheckGood(appended))
}

fn check_type_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64, role: U64, skip_kind: U64) -> Result(CheckResult, __s0_Error) {
    if link_id == 0 { return Ok(CheckGood(store)) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let before = try check_type_links(d, state, parse, store, owner, link.next, role, skip_kind)
    let current = match before {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match before {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(before) }
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    if child.kind == 7 || child.kind == 14 || child.kind == skip_kind { return Ok(CheckGood(current)) }
    var actual_role = role
    if role == 5 && child.kind != 13 { actual_role = 6 }
    var actual_ordinal: U64 = 0
    var duplicate_parameter = false
    var use_at: U64 = 0
    while use_at < __s0_buffer_len(DeclTypeUseRec, current.uses) {
        let prior = __s0_buffer_get(DeclTypeUseRec, current.uses, use_at)
        if prior.owner == owner && prior.role == actual_role {
            if (actual_role == 1 || actual_role == 2) && same_name(state, child.source, child.name_start, child.name_end, prior.source, prior.name_start, prior.name_end) {
                var duplicate_kind: U64 = 6
                if actual_role == 2 { duplicate_kind = 7 }
                return check_decl_fail(d, state, parse, current, duplicate_kind, owner)
            }
            if actual_role == 5 && same_name(state, child.source, child.name_start, child.name_end, prior.source, prior.name_start, prior.name_end) { duplicate_parameter = true }
            actual_ordinal = actual_ordinal + 1
        }
        use_at = use_at + 1
    }
    if child.kind == 9 && child.children == 0 {
        let uses = try __s0_buffer_append(DeclTypeUseRec, d, current.uses, DeclTypeUseRec(owner: owner, role: 2, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: child.name_start, name_end: child.name_end, syntax: 0, checked_type: 0))
        return Ok(CheckGood(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: uses, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, diagnostics: current.diagnostics)))
    }
    var syntax = link.node
    if child.kind == 8 || child.kind == 9 || child.kind == 10 || child.kind == 13 {
        let head = __s0_buffer_get(SyntaxLinkRec, parse.links, child.children - 1)
        syntax = head.node
    }
    let owner_symbol = __s0_buffer_get(SymbolRec, current.symbols, owner - 1)
    if owner_symbol.kind == 1 && !ffi_type_syntax_ok(state, parse, syntax) { return check_decl_fail(d, state, parse, current, 15, owner) }
    let resolved = try resolve_type(d, state, parse, current, owner, syntax)
    let next = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    if owner_symbol.kind == 1 || owner_symbol.kind == 12 {
        let checked_id = checked_type_for_syntax(next, syntax)
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        if try direct_type_concrete(d, next, empty, checked_id, 0) {
            let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, syntax_diag_node(state, parse, syntax), 0)
            if match validated {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(validated) }
        }
    }
    if actual_role == 5 {
        let checked = __s0_buffer_get(CheckedTypeRec, next.types, checked_type_for_syntax(next, syntax) - 1)
        let diag_node = __s0_buffer_get(SyntaxRec, parse.nodes, syntax - 1)
        if duplicate_parameter { return check_fail(d, next, 16, diag_node, 0, 0, 0) }
        if reserved_value_name(state, next, child) { return check_fail(d, next, 17, diag_node, 0, 0, 0) }
    }
    var name_start = child.name_start
    var name_end = child.name_end
    if actual_role == 3 || actual_role == 4 || actual_role == 6 { name_start = 0
        name_end = 0 }
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: actual_role, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: name_start, name_end: name_end, syntax: syntax, checked_type: checked_type_for_syntax(next, syntax)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: uses, locals: next.locals, environments: next.environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, diagnostics: next.diagnostics)))
}

fn check_import_types(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, signature: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let result_link = __s0_buffer_get(SyntaxLinkRec, parse.links, signature.children - 1)
    let params = try check_type_links(d, state, parse, store, owner, result_link.next, 3, 0)
    let current = match params {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match params {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(params) }
    if !ffi_type_syntax_ok(state, parse, result_link.node) { return check_decl_fail(d, state, parse, current, 15, owner) }
    let resolved = try resolve_type(d, state, parse, current, owner, result_link.node)
    let next = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    let checked_id = checked_type_for_syntax(next, result_link.node)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    if try direct_type_concrete(d, next, empty, checked_id, 0) {
        let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, syntax_diag_node(state, parse, result_link.node), 0)
        if match validated {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(validated) }
    }
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: 4, ordinal: 0, node: result_link.node, source: signature.source, name_start: 0, name_end: 0, syntax: result_link.node, checked_type: checked_type_for_syntax(next, result_link.node)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: uses, locals: next.locals, environments: next.environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, diagnostics: next.diagnostics)))
}

// Materialize aggregate value edges without recursion. Declared applications
// contribute their target and expand that declaration's representation under
// positional bindings, so substitution-introduced cycles are visible. Option,
// Result, and Map expose their arguments; Slice, Ptr, and Buffer cut the walk.
fn collect_cycle_edges(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(__s0_Buffer(CycleEdgeRec), __s0_Error) {
    let initial_work = try __s0_buffer_new(CycleWorkRec, d)
    var work = initial_work
    let initial_edges = try __s0_buffer_new(CycleEdgeRec, d)
    var edges = initial_edges
    let initial_bindings = try __s0_buffer_new(TypeBindingRec, d)
    var bindings = initial_bindings
    let initial_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    var ancestry = initial_ancestry
    let initial_memo = try __s0_buffer_new(ExpansionMemoRec, d)
    var memo = initial_memo
    let initial_seen = try __s0_buffer_new(InterpStateRec, d)
    var seen = initial_seen
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let item = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if (item.role == 1 || item.role == 2) && item.checked_type != 0 {
            work = try __s0_buffer_append(CycleWorkRec, d, work, CycleWorkRec(owner: item.owner, checked_type: item.checked_type, env: 0, ancestry: 0))
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CycleWorkRec, work) {
        let item = __s0_buffer_get(CycleWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, item.owner, norm.checked_type, norm.env, norm.ancestry)
            if inspect { seen = try __s0_buffer_append(InterpStateRec, d, seen, InterpStateRec(owner: item.owner, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 7 {
                edges = try __s0_buffer_append(CycleEdgeRec, d, edges, CycleEdgeRec(owner: item.owner, target: checked.target))
                if !ancestry_has(ancestry, norm.ancestry, checked.target) {
                    if !(try expansion_seen(d, state, parse, store, bindings, memo, item.owner, norm.checked_type, norm.env)) {
                        memo = try remember_expansion(d, memo, item.owner, checked.target, norm.checked_type, norm.env)
                        let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                        bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                        let target_env = declaration_env_head(bindings, old_len)
                        ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                        let chain = __s0_buffer_len(DeclAncestryRec, ancestry)
                        var use_at: U64 = 0
                        while use_at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
                            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_at)
                            if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
                                work = try __s0_buffer_append(CycleWorkRec, d, work, CycleWorkRec(owner: item.owner, checked_type: use.checked_type, env: target_env, ancestry: chain))
                            }
                            use_at = use_at + 1
                        }
                    }
                }
            }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 {
                var arg_at: U64 = 0
                while arg_at < checked.arg_count {
                    let arg = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + arg_at)
                    work = try __s0_buffer_append(CycleWorkRec, d, work, CycleWorkRec(owner: item.owner, checked_type: arg, env: norm.env, ancestry: norm.ancestry))
                    arg_at = arg_at + 1
                }
            }
        }
        at = at + 1
    }
    return Ok(edges)
}

fn owner_has_edge(edges: __s0_Buffer(CycleEdgeRec), owner: U64, target: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(CycleEdgeRec, edges) {
        let item = __s0_buffer_get(CycleEdgeRec, edges, at)
        if item.owner == owner && item.target == target { return true }
        at = at + 1
    }
    return false
}

fn cycle_color(colors: __s0_Buffer(CycleColorRec), owner: U64) -> U64 {
    var at = __s0_buffer_len(CycleColorRec, colors)
    while at != 0 {
        at = at - 1
        let item = __s0_buffer_get(CycleColorRec, colors, at)
        if item.owner == owner { return item.color }
    }
    return 0
}

fn reject_value_cycles(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    let edges = try collect_cycle_edges(d, state, parse, store)
    let initial_colors = try __s0_buffer_new(CycleColorRec, d)
    var colors = initial_colors
    let initial_frames = try __s0_buffer_new(CycleFrameRec, d)
    var frames = initial_frames
    var owner: U64 = 1
    while owner <= __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if (symbol.kind == 2 || symbol.kind == 3) && cycle_color(colors, owner) == 0 {
            colors = try __s0_buffer_append(CycleColorRec, d, colors, CycleColorRec(owner: owner, color: 1))
            frames = try __s0_buffer_append(CycleFrameRec, d, frames, CycleFrameRec(owner: owner, next_target: 1, parent: 0))
            var frame_id = __s0_buffer_len(CycleFrameRec, frames)
            while frame_id != 0 {
                let frame = __s0_buffer_get(CycleFrameRec, frames, frame_id - 1)
                var target = frame.next_target
                var found: U64 = 0
                while target <= __s0_buffer_len(SymbolRec, store.symbols) && found == 0 {
                    let candidate = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
                    if (candidate.kind == 2 || candidate.kind == 3) && owner_has_edge(edges, frame.owner, target) { found = target }
                    target = target + 1
                }
                if found == 0 {
                    colors = try __s0_buffer_append(CycleColorRec, d, colors, CycleColorRec(owner: frame.owner, color: 2))
                    frame_id = frame.parent
                } else {
                    frames = try __s0_buffer_append(CycleFrameRec, d, frames, CycleFrameRec(owner: frame.owner, next_target: found + 1, parent: frame.parent))
                    let continuation = __s0_buffer_len(CycleFrameRec, frames)
                    let color = cycle_color(colors, found)
                    if color == 1 { return check_decl_fail(d, state, parse, store, 9, found) }
                    if color == 2 { frame_id = continuation }
                    if color == 0 {
                        colors = try __s0_buffer_append(CycleColorRec, d, colors, CycleColorRec(owner: found, color: 1))
                        frames = try __s0_buffer_append(CycleFrameRec, d, frames, CycleFrameRec(owner: found, next_target: 1, parent: continuation))
                        frame_id = __s0_buffer_len(CycleFrameRec, frames)
                    }
                }
            }
        }
        owner = owner + 1
    }
    return Ok(CheckGood(store))
}

fn revalidate_aggregate_roots(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            let empty = try __s0_buffer_new(TypeBindingRec, d)
            if try direct_type_concrete(d, store, empty, use.checked_type, 0) {
                let validated = try validate_concrete_type(d, state, parse, store, use.checked_type, 0, syntax_diag_node(state, parse, use.syntax), 0)
                if match validated {
                    CheckGood(value) => false
                    CheckBad(value) => true
                } { return Ok(validated) }
            }
        }
        at = at + 1
    }
    return Ok(CheckGood(store))
}

// wanted 0 selects both aggregate kinds in their shared source order. Imports
// and functions use their syntax kind after aggregate checking and cycles.
fn check_declaration_at(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, wanted: U64) -> Result(CheckResult, __s0_Error) {
    if owner > __s0_buffer_len(SymbolRec, store.symbols) { return Ok(CheckGood(store)) }
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
        if symbol.kind == wanted || (wanted == 0 && (symbol.kind == 2 || symbol.kind == 3)) {
            let root = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.node - 1)
            let params = try collect_param_links(d, state, parse, store, owner, root.children)
            let with_params = match params {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            if match params {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(params) }
            var checked: CheckResult = CheckGood(with_params)
            if root.kind == 2 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 1, 0) }
            if root.kind == 3 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 2, 11) }
            if root.kind == 12 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 5, 0) }
            if root.kind == 1 {
                let signature = __s0_buffer_get(SyntaxLinkRec, parse.links, root.children - 1)
                let sig = __s0_buffer_get(SyntaxRec, parse.nodes, signature.node - 1)
                checked = try check_import_types(d, state, parse, with_params, owner, sig)
            }
            let complete = match checked {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            if match checked {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(checked) }
            if root.kind == 3 {
                var variants: U64 = 0
                var item_at: U64 = 0
                while item_at < __s0_buffer_len(DeclTypeUseRec, complete.uses) {
                    let item = __s0_buffer_get(DeclTypeUseRec, complete.uses, item_at)
                    if item.owner == owner && item.role == 2 { variants = variants + 1 }
                    item_at = item_at + 1
                }
                if variants == 0 { return check_decl_fail(d, state, parse, complete, 8, owner) }
            }
            return check_declaration_at(d, state, parse, complete, owner + 1, wanted)
        }
    return check_declaration_at(d, state, parse, store, owner + 1, wanted)
}

fn check_declaration_kind(d: Domain, state: State, parse: ParseStore, store: CheckStore, wanted: U64) -> Result(CheckResult, __s0_Error) {
    return check_declaration_at(d, state, parse, store, 1, wanted)
}

fn function_use(store: CheckStore, owner: U64, role: U64, node: SyntaxRec, state: State) -> U64 {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    var actual_role = role
    if symbol.kind == 13 {
        if role == 5 { actual_role = 7 }
        if role == 6 { actual_role = 8 }
    }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == actual_role {
            if actual_role == 6 || actual_role == 8 || same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        }
        at = at + 1
    }
    return 0
}

// A name that belongs to a later expression slice is deferred rather than
// misdiagnosed as unknown. This includes top-level declarations, reserved
// builtins/variants, and declared enum variants.
fn known_body_identifier(state: State, store: CheckStore, node: SyntaxRec) -> Bool {
    if reserved_symbol(state, node) { return true }
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return true }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.role == 2 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return true }
        at = at + 1
    }
    return false
}

fn int_result_range(state: State, parse: ParseStore, result_type: CheckedTypeRec) -> IntRangeRec {
    if result_type.kind != 1 { return IntRangeRec(integer: false, signed: false, positive: "", negative: "") }
    if result_type.target == 2 { return IntRangeRec(integer: true, signed: true, positive: "127", negative: "128") }
    if result_type.target == 3 { return IntRangeRec(integer: true, signed: true, positive: "32767", negative: "32768") }
    if result_type.target == 4 { return IntRangeRec(integer: true, signed: true, positive: "2147483647", negative: "2147483648") }
    if result_type.target == 5 { return IntRangeRec(integer: true, signed: true, positive: "9223372036854775807", negative: "9223372036854775808") }
    if result_type.target == 6 { return IntRangeRec(integer: true, signed: false, positive: "255", negative: "") }
    if result_type.target == 7 { return IntRangeRec(integer: true, signed: false, positive: "65535", negative: "") }
    if result_type.target == 8 { return IntRangeRec(integer: true, signed: false, positive: "4294967295", negative: "") }
    if result_type.target == 9 { return IntRangeRec(integer: true, signed: false, positive: "18446744073709551615", negative: "") }
    return IntRangeRec(integer: false, signed: false, positive: "", negative: "")
}

fn zero_magnitude(values: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if __s0_buffer_get(U8, values, at) != 48 { return false }
        at = at + 1
    }
    return true
}

// Canonical digit order compares by width, then by ASCII byte order. Leading
// zeros are skipped so 007 and 7 share one canonical form.
fn digits_at_most(values: __s0_Buffer(U8), start: U64, end: U64, limit: String) -> Bool {
    var first = start
    while first + 1 < end && __s0_buffer_get(U8, values, first) == 48 { first = first + 1 }
    let width = end - first
    if width != len(limit) { return width < len(limit) }
    var at: U64 = 0
    while at < width {
        let digit = __s0_buffer_get(U8, values, first + at)
        let bound = limit[at]
        if digit != bound { return digit < bound }
        at = at + 1
    }
    return true
}

fn local_lookup(store: CheckStore, owner: U64, node: SyntaxRec, state: State) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(LocalRec, store.locals) {
        let local = __s0_buffer_get(LocalRec, store.locals, at)
        if local.owner == owner && same_name(state, node.source, node.name_start, node.name_end, local.source, local.name_start, local.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn body_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(BodyStep, __s0_Error) {
    let failed = try check_fail(d, store, kind, node, 0, 0, 0)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(BodyBad(bad))
}

fn body_token_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(BodyStep, __s0_Error) {
    let failed = try check_token_fail(d, state, store, kind, node)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(BodyBad(bad))
}

// A failed body retains only its diagnostic. Every semantic buffer is restored
// to the function-entry snapshot, including types and type arguments appended
// while resolving local annotations.
fn rollback_body(base: CheckStore, failed: CheckStore) -> CheckStore {
    return CheckStore(symbols: base.symbols, type_params: base.type_params, types: base.types, type_args: base.type_args, type_annotations: base.type_annotations, uses: base.uses, locals: base.locals, environments: base.environments, expressions: base.expressions, call_annotations: base.call_annotations, expression_children: base.expression_children, returns: base.returns, diagnostics: failed.diagnostics)
}

fn expr_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(ExprOutcome, __s0_Error) {
    let failed = try check_fail(d, store, kind, node, 0, 0, 0)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(ExprBad(bad))
}

fn expr_token_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(ExprOutcome, __s0_Error) {
    let failed = try check_token_fail(d, state, store, kind, node)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(ExprBad(bad))
}

fn expr_deferred(store: CheckStore) -> Result(ExprOutcome, __s0_Error) {
    return Ok(ExprGood(ExprValueRec(store: store, draft: ExprDraftRec(deferred: true, checked_type: 0, expression: 0))))
}

fn expr_draft(store: CheckStore, checked_type: U64, expression: U64) -> Result(ExprOutcome, __s0_Error) {
    return Ok(ExprGood(ExprValueRec(store: store, draft: ExprDraftRec(deferred: false, checked_type: checked_type, expression: expression))))
}

fn primitive_type_id(state: State, parse: ParseStore, store: CheckStore, name: String) -> U64 {
    var target: U64 = 0
    if len(name) == 4 && name[0] == 66 { target = 1 }
    if len(name) == 3 && name[0] == 73 { target = 5 }
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if checked.kind == 1 && checked.target == target { return at + 1 }
        at = at + 1
    }
    return 0
}

fn primitive_type_named(state: State, parse: ParseStore, store: CheckStore, checked_type: U64, name: String) -> Bool {
    if checked_type == 0 { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    var target: U64 = 0
    if len(name) == 4 && name[0] == 66 { target = 1 }
    if len(name) == 3 && name[0] == 70 && name[1] == 51 { target = 10 }
    if len(name) == 3 && name[0] == 70 && name[1] == 54 { target = 11 }
    return checked.kind == 1 && checked.target == target
}

fn float_type(state: State, parse: ParseStore, store: CheckStore, checked_type: U64) -> Bool {
    return primitive_type_named(state, parse, store, checked_type, "F32") || primitive_type_named(state, parse, store, checked_type, "F64")
}

fn expression_type_equal(d: Domain, state: State, parse: ParseStore, store: CheckStore, left: U64, right: U64) -> Result(Bool, __s0_Error) {
    let bindings = try __s0_buffer_new(TypeBindingRec, d)
    return interpreted_type_equal(d, state, parse, store, bindings, left, 0, right, 0)
}

fn expression_operator(state: State, node: SyntaxRec) -> U64 {
    if node_word(state, node, "-") {
        if node.kind == 25 { return 1 }
        return 4
    }
    if node_word(state, node, "!") { return 2 }
    if node_word(state, node, "+") { return 3 }
    if node_word(state, node, "*") { return 5 }
    if node_word(state, node, "/") { return 6 }
    if node_word(state, node, "%") { return 7 }
    if node_word(state, node, "<<") { return 8 }
    if node_word(state, node, ">>") { return 9 }
    if node_word(state, node, "==") { return 10 }
    if node_word(state, node, "!=") { return 11 }
    if node_word(state, node, "<") { return 12 }
    if node_word(state, node, "<=") { return 13 }
    if node_word(state, node, ">") { return 14 }
    if node_word(state, node, ">=") { return 15 }
    if node_word(state, node, "&&") { return 16 }
    if node_word(state, node, "||") { return 17 }
    return 0
}

fn append_expression(d: Domain, store: CheckStore, owner: U64, syntax: U64, kind: U64, checked_type: U64, reference: U64, bool_value: U64, left: U64, right: U64, operator: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var children = store.expression_children
    var first_child: U64 = 0
    var child_count: U64 = 0
    if left != 0 {
        first_child = __s0_buffer_len(CheckedExprChildRec, children) + 1
        children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: left))
        child_count = child_count + 1
    }
    if right != 0 {
        children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: right))
        child_count = child_count + 1
    }
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, syntax: syntax, kind: kind, checked_type: checked_type, parameter_use: reference, bool_value: bool_value, left: 0, right: 0, annotation: 0, first_child: first_child, child_count: child_count, operator: operator, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: store.call_annotations, expression_children: children, returns: store.returns, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

fn symbol_named(state: State, store: CheckStore, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn call_link_count(parse: ParseStore, call: SyntaxRec) -> U64 {
    var count: U64 = 0
    var link = call.children
    while link != 0 {
        count = count + 1
        link = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1).next
    }
    return count
}

// Call links are reverse source ordered. Ordinal zero names the callee and
// later ordinals name arguments in source order.
fn call_link_at(parse: ParseStore, call: SyntaxRec, ordinal: U64) -> SyntaxLinkRec {
    let count = call_link_count(parse, call)
    var skip = count - ordinal - 1
    var link = call.children
    while skip != 0 {
        link = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1).next
        skip = skip - 1
    }
    return __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
}

fn expression_type_head(state: State, store: CheckStore, node: SyntaxRec) -> CheckedTypeRec {
    let builtin = builtin_type_kind(state, node)
    if builtin == 1 { return CheckedTypeRec(kind: 1, syntax: 0, target: primitive_type_target(state, node), first_arg: 0, arg_count: 0) }
    if builtin == 2 { return CheckedTypeRec(kind: 8, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if builtin != 0 { return CheckedTypeRec(kind: builtin, syntax: 0, target: 0, first_arg: 0, arg_count: 0) }
    if node_word(state, node, "Option") { return CheckedTypeRec(kind: 9, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "Result") { return CheckedTypeRec(kind: 10, syntax: 0, target: 0, first_arg: 0, arg_count: 2) }
    if node_word(state, node, "Map") { return CheckedTypeRec(kind: 11, syntax: 0, target: 0, first_arg: 0, arg_count: 2) }
    if node_word(state, node, "Ptr") { return CheckedTypeRec(kind: 12, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "__s0_Buffer") { return CheckedTypeRec(kind: 13, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    let declared = find_declared_type(state, store, node)
    if declared != 0 { return CheckedTypeRec(kind: 7, syntax: 0, target: declared, first_arg: 0, arg_count: __s0_buffer_get(SymbolRec, store.symbols, declared - 1).type_arity) }
    return CheckedTypeRec(kind: 0, syntax: 0, target: 0, first_arg: 0, arg_count: 0)
}

fn expression_type_candidate(state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Bool {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 24 {
        if find_type_param(state, store, instance_declaration(store, owner), node) != 0 { return true }
        return expression_type_head(state, store, node).kind != 0
    }
    if node.kind != 27 { return false }
    let callee_link = call_link_at(parse, node, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 { return false }
    let head = expression_type_head(state, store, callee)
    let count = call_link_count(parse, node) - 1
    if head.kind == 0 || count != head.arg_count { return false }
    var ordinal: U64 = 0
    while ordinal < count {
        let link = call_link_at(parse, node, ordinal + 1)
        if !expression_type_candidate(state, parse, store, owner, link.node) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn leading_type_arg_count(state: State, parse: ParseStore, store: CheckStore, owner: U64, call: SyntaxRec) -> U64 {
    var count: U64 = 0
    let total = call_link_count(parse, call) - 1
    while count < total {
        let link = call_link_at(parse, call, count + 1)
        if !expression_type_candidate(state, parse, store, owner, link.node) { return count }
        count = count + 1
    }
    return count
}

fn resolve_expression_type_args(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, call: SyntaxRec, ordinal: U64, count: U64, children: __s0_Buffer(U64)) -> Result(SubstitutedChildrenRec, __s0_Error) {
    if ordinal == count { return Ok(SubstitutedChildrenRec(store: store, children: children)) }
    let link = call_link_at(parse, call, ordinal + 1)
    let resolved = try resolve_expression_type(d, state, parse, store, owner, link.node)
    let next_store = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(SubstitutedChildrenRec(store: next_store, children: children)) }
    let next = try __s0_buffer_append(U64, d, children, checked_type_for_syntax(next_store, link.node))
    return resolve_expression_type_args(d, state, parse, next_store, owner, call, ordinal + 1, count, next)
}

fn resolve_expression_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 24 {
        let declaration = instance_declaration(store, owner)
        let param = find_type_param(state, store, declaration, node)
        if param != 0 {
            let concrete = instance_type_arg(store, owner, param)
            if concrete == 0 { return check_token_fail(d, state, store, 57, node) }
            return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, concrete)))
        }
        let head = expression_type_head(state, store, node)
        if head.kind == 8 && node_word(state, node, "String") {
            let u8 = canonical_type_id(store, 1, 6, 0, 0)
            let existing = canonical_single_arg(store, 8, 0, u8)
            if existing != 0 { return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, existing))) }
            let args = try __s0_buffer_append(U64, d, store.type_args, u8)
            let recorded = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)
            return Ok(CheckGood(try append_checked_type(d, recorded, owner, 8, node_id, 0, __s0_buffer_len(U64, args), 1)))
        }
        if head.kind == 0 || head.arg_count != 0 { return check_token_fail(d, state, store, 56, node) }
        return Ok(CheckGood(try append_checked_type(d, store, owner, head.kind, node_id, head.target, 0, 0)))
    }
    if node.kind != 27 { return check_token_fail(d, state, store, 56, node) }
    let callee_link = call_link_at(parse, node, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 { return check_token_fail(d, state, store, 56, node) }
    let head = expression_type_head(state, store, callee)
    let count = call_link_count(parse, node) - 1
    if head.kind == 0 || count != head.arg_count { return check_token_fail(d, state, store, 56, node) }
    let empty = try __s0_buffer_new(U64, d)
    let children = try resolve_expression_type_args(d, state, parse, store, owner, node, 0, count, empty)
    if __s0_buffer_len(U64, children.children) != count { return Ok(CheckBad(children.store)) }
    let existing = canonical_type_for_children(children.store, head.kind, head.target, children.children)
    if existing != 0 { return Ok(CheckGood(try annotate_checked_type(d, children.store, owner, node_id, existing))) }
    let first = __s0_buffer_len(U64, children.store.type_args) + 1
    let recorded = try append_substituted_children(d, children.store, children.children, 0)
    return Ok(CheckGood(try append_checked_type(d, recorded, owner, head.kind, node_id, head.target, first, count)))
}

fn use_by_ordinal(store: CheckStore, owner: U64, role: U64, ordinal: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role && use.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn use_count(store: CheckStore, owner: U64, role: U64) -> U64 {
    var count: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role { count = count + 1 }
        at = at + 1
    }
    return count
}

fn variant_named(state: State, store: CheckStore, enum_owner: U64, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == enum_owner && use.role == 2 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn any_variant_named(state: State, store: CheckStore, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.role == 2 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn syntax_contains_call(parse: ParseStore, node_id: U64) -> Bool {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 27 || node.kind == 36 { return true }
    var link = node.children
    while link != 0 {
        let child = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        if syntax_contains_call(parse, child.node) { return true }
        link = child.next
    }
    return false
}

fn expression_for_syntax(store: CheckStore, owner: U64, syntax: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if expression.owner == owner && expression.syntax == syntax { return at + 1 }
        at = at + 1
    }
    return 0
}

fn append_call_expression(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, syntax: U64, expression_kind: U64, checked_type: U64, annotation_kind: U64, target: U64, variant_use: U64, child_call: SyntaxRec, child_mode: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try __s0_buffer_append(CallAnnotationRec, d, store.call_annotations, CallAnnotationRec(owner: owner, kind: annotation_kind, target: target, checked_type: checked_type, variant_use: variant_use))
    let annotation = __s0_buffer_len(CallAnnotationRec, annotations)
    var children = store.expression_children
    var first_child: U64 = 0
    var child_count: U64 = 0
    if child_mode == 1 || child_mode == 3 {
        var ordinal: U64 = 1
        var limit = call_link_count(parse, child_call)
        if child_mode == 3 { limit = 2 }
        while ordinal < limit {
            let link = call_link_at(parse, child_call, ordinal)
            let expression = expression_for_syntax(store, owner, link.node)
            if expression != 0 {
                if child_count == 0 { first_child = __s0_buffer_len(CheckedExprChildRec, children) + 1 }
                children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: expression))
                child_count = child_count + 1
            }
            ordinal = ordinal + 1
        }
    }
    if child_mode == 2 {
        var ordinal: U64 = 0
        let field_count = use_count(store, target, 1)
        while ordinal < field_count {
            let field_id = use_by_ordinal(store, target, 1, ordinal)
            let field = __s0_buffer_get(DeclTypeUseRec, store.uses, field_id - 1)
            let named_id = record_source_arg(parse, child_call, field, state)
            let named = __s0_buffer_get(SyntaxRec, parse.nodes, named_id - 1)
            let value_link = __s0_buffer_get(SyntaxLinkRec, parse.links, named.children - 1)
            if child_count == 0 { first_child = __s0_buffer_len(CheckedExprChildRec, children) + 1 }
            children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: expression_for_syntax(store, owner, value_link.node)))
            child_count = child_count + 1
            ordinal = ordinal + 1
        }
    }
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, syntax: syntax, kind: expression_kind, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: annotation, first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

fn record_source_arg(parse: ParseStore, call: SyntaxRec, use: DeclTypeUseRec, state: State) -> U64 {
    var ordinal: U64 = 1
    let count = call_link_count(parse, call)
    while ordinal < count {
        let link = call_link_at(parse, call, ordinal)
        let arg = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
        if arg.kind == 28 && same_name(state, arg.source, arg.name_start, arg.name_end, use.source, use.name_start, use.name_end) { return link.node }
        ordinal = ordinal + 1
    }
    return 0
}

fn check_positional_call_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, role: U64, ordinal: U64, count: U64, mismatch: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    let arg_link = call_link_at(parse, call, ordinal + 1)
    let arg = __s0_buffer_get(SyntaxRec, parse.nodes, arg_link.node - 1)
    if arg.kind == 28 { return expr_token_fail(d, state, base, mismatch, arg) }
    let parameter_id = use_by_ordinal(store, target, role, ordinal)
    let parameter = __s0_buffer_get(DeclTypeUseRec, store.uses, parameter_id - 1)
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, arg, arg_link.node, parameter.checked_type, mismatch, arg, 0, 0)
    let current = match checked {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match checked {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked {
        ExprGood(item) => item.draft
        ExprBad(item) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    return check_positional_call_args(d, state, parse, base, current, owner, call, target, role, ordinal + 1, count, mismatch)
}

fn check_record_values(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, ordinal: U64, count: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    let field_id = use_by_ordinal(store, target, 1, ordinal)
    let field = __s0_buffer_get(DeclTypeUseRec, store.uses, field_id - 1)
    let named_id = record_source_arg(parse, call, field, state)
    let named = __s0_buffer_get(SyntaxRec, parse.nodes, named_id - 1)
    let value_link = __s0_buffer_get(SyntaxLinkRec, parse.links, named.children - 1)
    let value = __s0_buffer_get(SyntaxRec, parse.nodes, value_link.node - 1)
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, value, value_link.node, field.checked_type, 42, value, 0, 0)
    let current = match checked {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match checked {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked {
        ExprGood(item) => item.draft
        ExprBad(item) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    return check_record_values(d, state, parse, base, current, owner, call, target, ordinal + 1, count)
}

fn pattern_bound(store: CheckStore, pattern: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Bool {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, pattern - 1)
    if checked.kind == 6 { return inference_lookup(bindings, checked.target) != 0 }
    var ordinal: U64 = 0
    while ordinal < checked.arg_count {
        if !pattern_bound(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal), bindings) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn infer_unary_variant_argument(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, arg: SyntaxRec, arg_id: U64, pattern: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    let expected = __s0_buffer_get(CheckedTypeRec, store.types, pattern - 1)
    if expected.kind != 7 || __s0_buffer_get(SymbolRec, store.symbols, expected.target - 1).kind != 3 || arg.kind != 27 || call_link_count(parse, arg) != 2 { return Ok(CallInferenceDefer) }
    let callee_link = call_link_at(parse, arg, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 { return Ok(CallInferenceDefer) }
    let variant_id = variant_named(state, store, expected.target, callee)
    if variant_id == 0 { return Ok(CallInferenceDefer) }
    let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, variant_id - 1)
    if variant.checked_type == 0 { return Ok(CallInferenceDefer) }
    let payload_link = call_link_at(parse, arg, 1)
    let payload_node = __s0_buffer_get(SyntaxRec, parse.nodes, payload_link.node - 1)
    let payload = try check_value_expression_inner(d, state, parse, base, store, owner, payload_node, payload_link.node, 0, 50, payload_node, 0, 0)
    let current = match payload {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match payload {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(CallInferenceBad(current)) }
    let draft = match payload {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(CallInferenceDefer) }
    let unified = try unify_types(d, current, variant.checked_type, draft.checked_type, bindings)
    let inferred = match unified {
        UnifyGood(value) => value
        UnifyConflict => bindings
    }
    if match unified {
        UnifyGood(value) => false
        UnifyConflict => true
    } {
        let failed = try check_token_fail(d, state, base, 58, payload_node)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    if !pattern_bound(current, pattern, inferred) { return Ok(CallInferenceDefer) }
    let concrete = try substitute_type(d, current, inferred, pattern)
    let appended = try append_call_expression(d, state, parse, concrete.store, owner, arg_id, 10, concrete.checked_type, 4, expected.target, variant_id, arg, 3, 0, 0)
    let final_store = match appended {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match appended {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(CallInferenceBad(final_store)) }
    return Ok(CallInferenceGood(CallInferenceRec(store: final_store, bindings: inferred)))
}

fn infer_call_arguments(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, runtime_start: U64, ordinal: U64, count: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == count { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    let arg_link = call_link_at(parse, call, runtime_start + ordinal + 1)
    let arg = __s0_buffer_get(SyntaxRec, parse.nodes, arg_link.node - 1)
    if arg.kind == 28 {
        let failed = try check_token_fail(d, state, base, 42, arg)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let parameter_id = use_by_ordinal(store, target, 5, ordinal)
    let pattern = __s0_buffer_get(DeclTypeUseRec, store.uses, parameter_id - 1).checked_type
    if !pattern_bound(store, pattern, bindings) {
        let variant = try infer_unary_variant_argument(d, state, parse, base, store, owner, arg, arg_link.node, pattern, bindings)
        let variant_store = match variant {
            CallInferenceGood(value) => value.store
            CallInferenceBad(value) => value
            CallInferenceDefer => store
        }
        if match variant {
            CallInferenceGood(value) => true
            CallInferenceBad(value) => false
            CallInferenceDefer => false
        } {
            let inferred = match variant {
                CallInferenceGood(value) => value.bindings
                CallInferenceBad(value) => bindings
                CallInferenceDefer => bindings
            }
            return infer_call_arguments(d, state, parse, base, variant_store, owner, call, target, runtime_start, ordinal + 1, count, inferred)
        }
        if match variant {
            CallInferenceGood(value) => false
            CallInferenceBad(value) => true
            CallInferenceDefer => false
        } { return Ok(CallInferenceBad(variant_store)) }
    }
    var expected: U64 = 0
    var current = store
    if pattern_bound(store, pattern, bindings) {
        let concrete = try substitute_type(d, store, bindings, pattern)
        current = concrete.store
        expected = concrete.checked_type
    }
    let checked = try check_value_expression_inner(d, state, parse, base, current, owner, arg, arg_link.node, expected, 58, arg, 0, 0)
    let after = match checked {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(CallInferenceBad(after)) }
    let draft = match checked {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(CallInferenceDefer) }
    var inferred = bindings
    if expected == 0 {
        let unified = try unify_types(d, after, pattern, draft.checked_type, bindings)
        inferred = match unified {
            UnifyGood(value) => value
            UnifyConflict => bindings
        }
        if match unified {
            UnifyGood(value) => false
            UnifyConflict => true
        } {
            let failed = try check_token_fail(d, state, base, 58, arg)
            return Ok(CallInferenceBad(match failed {
                CheckGood(value) => value
                CheckBad(value) => value
            }))
        }
    }
    return infer_call_arguments(d, state, parse, base, after, owner, call, target, runtime_start, ordinal + 1, count, inferred)
}

fn explicit_function_bindings(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, declaration: U64, application: SyntaxRec, ordinal: U64, param_at: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == __s0_buffer_get(SymbolRec, store.symbols, declaration - 1).type_arity { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    var at = param_at
    while __s0_buffer_get(TypeParamRec, store.type_params, at).owner != declaration { at = at + 1 }
    let link = call_link_at(parse, application, ordinal + 1)
    let resolved = try resolve_expression_type(d, state, parse, store, owner, link.node)
    let current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(CallInferenceBad(current)) }
    let concrete = checked_type_for_syntax(current, link.node)
    if !checked_type_concrete(current, concrete) {
        let failed = try check_token_fail(d, state, store, 57, application)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let next = try __s0_buffer_append(InferenceBindingRec, d, bindings, InferenceBindingRec(param: at + 1, checked_type: concrete))
    return explicit_function_bindings(d, state, parse, current, owner, declaration, application, ordinal + 1, at + 1, next)
}

fn check_explicit_function_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, supplied: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
    if supplied != symbol.type_arity { return expr_token_fail(d, state, base, 56, call) }
    let argument_count = call_link_count(parse, call) - 1 - supplied
    let parameter_count = use_count(store, target, 5)
    if argument_count != parameter_count { return expr_token_fail(d, state, base, 41, call) }
    let empty = try __s0_buffer_new(InferenceBindingRec, d)
    let explicit = try explicit_function_bindings(d, state, parse, store, owner, target, call, 0, 0, empty)
    let with_types = match explicit {
        CallInferenceGood(value) => value.store
        CallInferenceBad(value) => value
        CallInferenceDefer => base
    }
    if match explicit {
        CallInferenceGood(value) => false
        CallInferenceBad(value) => true
        CallInferenceDefer => false
    } { return Ok(ExprBad(with_types)) }
    let bindings = match explicit {
        CallInferenceGood(value) => value.bindings
        CallInferenceBad(value) => empty
        CallInferenceDefer => empty
    }
    let arguments = try infer_call_arguments(d, state, parse, base, with_types, owner, call, target, supplied, 0, argument_count, bindings)
    let current = match arguments {
        CallInferenceGood(value) => value.store
        CallInferenceBad(value) => value
        CallInferenceDefer => base
    }
    if match arguments {
        CallInferenceGood(value) => false
        CallInferenceBad(value) => true
        CallInferenceDefer => false
    } { return Ok(ExprBad(current)) }
    if match arguments {
        CallInferenceGood(value) => false
        CallInferenceBad(value) => false
        CallInferenceDefer => true
    } { return expr_deferred(base) }
    let instance = try instantiate_function(d, state, parse, current, target, bindings, owner, call)
    let with_instance = match instance {
        InstanceGood(value) => value.store
        InstanceBad(value) => value
    }
    if match instance {
        InstanceGood(value) => false
        InstanceBad(value) => true
    } { return Ok(ExprBad(with_instance)) }
    let instance_id = match instance {
        InstanceGood(value) => value.instance
        InstanceBad(value) => 0
    }
    let result_id = use_by_ordinal(with_instance, instance_id, 8, 0)
    let result_type = __s0_buffer_get(DeclTypeUseRec, with_instance.uses, result_id - 1).checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, with_instance, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, with_instance, owner, call_id, 8, result_type, 1, instance_id, 0, call, 1, site_kind, site_syntax)
}

fn infer_record_values(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, ordinal: U64, count: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == count { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    let field_id = use_by_ordinal(store, target, 1, ordinal)
    let field = __s0_buffer_get(DeclTypeUseRec, store.uses, field_id - 1)
    let named_id = record_source_arg(parse, call, field, state)
    let named = __s0_buffer_get(SyntaxRec, parse.nodes, named_id - 1)
    let value_link = __s0_buffer_get(SyntaxLinkRec, parse.links, named.children - 1)
    let value = __s0_buffer_get(SyntaxRec, parse.nodes, value_link.node - 1)
    var expected: U64 = 0
    var current = store
    if pattern_bound(store, field.checked_type, bindings) {
        let concrete = try substitute_type(d, store, bindings, field.checked_type)
        current = concrete.store
        expected = concrete.checked_type
    }
    let checked = try check_value_expression_inner(d, state, parse, base, current, owner, value, value_link.node, expected, 42, value, 0, 0)
    let after = match checked {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match checked {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(CallInferenceBad(after)) }
    let draft = match checked {
        ExprGood(item) => item.draft
        ExprBad(item) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(CallInferenceDefer) }
    var inferred = bindings
    if expected == 0 {
        let unified = try unify_types(d, after, field.checked_type, draft.checked_type, bindings)
        inferred = match unified {
            UnifyGood(found) => found
            UnifyConflict => bindings
        }
        if match unified {
            UnifyGood(found) => false
            UnifyConflict => true
        } {
            let failed = try check_token_fail(d, state, base, 58, value)
            return Ok(CallInferenceBad(match failed {
                CheckGood(item) => item
                CheckBad(item) => item
            }))
        }
    }
    return infer_record_values(d, state, parse, base, after, owner, call, target, ordinal + 1, count, inferred)
}

fn declaration_binding_children(d: Domain, store: CheckStore, target: U64, bindings: __s0_Buffer(InferenceBindingRec), param_at: U64, children: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) {
    if param_at == __s0_buffer_len(TypeParamRec, store.type_params) { return Ok(children) }
    let param = __s0_buffer_get(TypeParamRec, store.type_params, param_at)
    var next = children
    if param.owner == target { next = try __s0_buffer_append(U64, d, children, inference_lookup(bindings, param_at + 1)) }
    return declaration_binding_children(d, store, target, bindings, param_at + 1, next)
}

fn concrete_decl_application(d: Domain, store: CheckStore, target: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(TypeValueRec, __s0_Error) {
    let arity = __s0_buffer_get(SymbolRec, store.symbols, target - 1).type_arity
    let empty = try __s0_buffer_new(U64, d)
    let children = try declaration_binding_children(d, store, target, bindings, 0, empty)
    let existing = canonical_type_for_children(store, 7, target, children)
    if existing != 0 { return Ok(TypeValueRec(store: store, checked_type: existing)) }
    let first = __s0_buffer_len(U64, store.type_args) + 1
    let with_args = try append_substituted_children(d, store, children, 0)
    let next = try append_checked_type(d, with_args, 0, 7, 0, target, first, arity)
    return Ok(TypeValueRec(store: next, checked_type: canonical_type_id(next, 7, target, first, arity)))
}

fn bind_expected_application(d: Domain, store: CheckStore, target: U64, expected: CheckedTypeRec, param_at: U64, arg_at: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(__s0_Buffer(InferenceBindingRec), __s0_Error) {
    if param_at == __s0_buffer_len(TypeParamRec, store.type_params) { return Ok(bindings) }
    let param = __s0_buffer_get(TypeParamRec, store.type_params, param_at)
    if param.owner == target {
        let next = try __s0_buffer_append(InferenceBindingRec, d, bindings, InferenceBindingRec(param: param_at + 1, checked_type: __s0_buffer_get(U64, store.type_args, expected.first_arg - 1 + arg_at)))
        return bind_expected_application(d, store, target, expected, param_at + 1, arg_at + 1, next)
    }
    return bind_expected_application(d, store, target, expected, param_at + 1, arg_at, bindings)
}

fn check_record_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
    var ordinal: U64 = 1
    let link_count = call_link_count(parse, call)
    while ordinal < link_count {
        let link = call_link_at(parse, call, ordinal)
        let arg = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
        if arg.kind != 28 { return expr_token_fail(d, state, base, 43, arg) }
        var field_use: U64 = 0
        var use_at: U64 = 0
        while use_at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_at)
            if use.owner == target && use.role == 1 && same_name(state, arg.source, arg.name_start, arg.name_end, use.source, use.name_start, use.name_end) { field_use = use_at + 1 }
            use_at = use_at + 1
        }
        if field_use == 0 { return expr_fail(d, base, 44, arg) }
        var prior_ordinal: U64 = 1
        while prior_ordinal < ordinal {
            let prior_link = call_link_at(parse, call, prior_ordinal)
            let prior = __s0_buffer_get(SyntaxRec, parse.nodes, prior_link.node - 1)
            if prior.kind == 28 && same_name(state, arg.source, arg.name_start, arg.name_end, prior.source, prior.name_start, prior.name_end) { return expr_fail(d, base, 45, arg) }
            prior_ordinal = prior_ordinal + 1
        }
        ordinal = ordinal + 1
    }
    let field_count = use_count(store, target, 1)
    ordinal = 0
    while ordinal < field_count {
        let field_id = use_by_ordinal(store, target, 1, ordinal)
        let field = __s0_buffer_get(DeclTypeUseRec, store.uses, field_id - 1)
        if record_source_arg(parse, call, field, state) == 0 { return expr_token_fail(d, state, base, 46, call) }
        ordinal = ordinal + 1
    }
    if symbol.type_arity != 0 {
        let empty = try __s0_buffer_new(InferenceBindingRec, d)
        var bindings = empty
        if expected != 0 {
            let expected_type = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
            if expected_type.kind == 7 && expected_type.target == target {
                bindings = try bind_expected_application(d, store, target, expected_type, 0, 0, bindings)
            }
        }
        let inferred = try infer_record_values(d, state, parse, base, store, owner, call, target, 0, field_count, bindings)
        let current = match inferred {
            CallInferenceGood(value) => value.store
            CallInferenceBad(value) => value
            CallInferenceDefer => base
        }
        if match inferred {
            CallInferenceGood(value) => false
            CallInferenceBad(value) => true
            CallInferenceDefer => false
        } { return Ok(ExprBad(current)) }
        if match inferred {
            CallInferenceGood(value) => false
            CallInferenceBad(value) => false
            CallInferenceDefer => true
        } { return expr_deferred(base) }
        bindings = match inferred {
            CallInferenceGood(value) => value.bindings
            CallInferenceBad(value) => bindings
            CallInferenceDefer => bindings
        }
        var param_at: U64 = 0
        while param_at < __s0_buffer_len(TypeParamRec, current.type_params) {
            let param = __s0_buffer_get(TypeParamRec, current.type_params, param_at)
            if param.owner == target && inference_lookup(bindings, param_at + 1) == 0 { return expr_token_fail(d, state, base, 57, call) }
            param_at = param_at + 1
        }
        let applied = try concrete_decl_application(d, current, target, bindings)
        if expected != 0 && !(try expression_type_equal(d, state, parse, applied.store, applied.checked_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_call_expression(d, state, parse, applied.store, owner, call_id, 9, applied.checked_type, 3, target, 0, call, 2, site_kind, site_syntax)
    }
    let values = try check_record_values(d, state, parse, base, store, owner, call, target, 0, field_count)
    var current = match values {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match values {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    if match values {
        ExprGood(item) => item.draft.deferred
        ExprBad(item) => false
    } { return expr_deferred(base) }
    var constructed = canonical_type_id(current, 7, target, 0, 0)
    if constructed == 0 {
        current = try append_checked_type(d, current, 0, 7, 0, target, 0, 0)
        constructed = canonical_type_id(current, 7, target, 0, 0)
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, constructed, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, call_id, 9, constructed, 3, target, 0, call, 2, site_kind, site_syntax)
}

fn check_function_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
    let explicit_count = leading_type_arg_count(state, parse, store, owner, call)
    if explicit_count != 0 {
        if symbol.type_arity == 0 { return expr_token_fail(d, state, base, 56, call) }
        return check_explicit_function_call(d, state, parse, base, store, owner, call, call_id, target, explicit_count, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
    }
    let argument_count = call_link_count(parse, call) - 1
    let parameter_count = use_count(store, target, 5)
    if argument_count != parameter_count { return expr_token_fail(d, state, base, 41, call) }
    if symbol.type_arity != 0 {
        let empty = try __s0_buffer_new(InferenceBindingRec, d)
        var bindings = empty
        if expected != 0 {
            let result_id = use_by_ordinal(store, target, 6, 0)
            let result_pattern = __s0_buffer_get(DeclTypeUseRec, store.uses, result_id - 1).checked_type
            let unified = try unify_types(d, store, result_pattern, expected, bindings)
            bindings = match unified {
                UnifyGood(value) => value
                UnifyConflict => bindings
            }
            if match unified {
                UnifyGood(value) => false
                UnifyConflict => true
            } { return expr_token_fail(d, state, base, 58, call) }
        }
        let inferred = try infer_call_arguments(d, state, parse, base, store, owner, call, target, 0, 0, argument_count, bindings)
        let current = match inferred {
            CallInferenceGood(value) => value.store
            CallInferenceBad(value) => value
            CallInferenceDefer => base
        }
        if match inferred {
            CallInferenceGood(value) => false
            CallInferenceBad(value) => true
            CallInferenceDefer => false
        } { return Ok(ExprBad(current)) }
        if match inferred {
            CallInferenceGood(value) => false
            CallInferenceBad(value) => false
            CallInferenceDefer => true
        } { return expr_deferred(base) }
        bindings = match inferred {
            CallInferenceGood(value) => value.bindings
            CallInferenceBad(value) => bindings
            CallInferenceDefer => bindings
        }
        let instance = try instantiate_function(d, state, parse, current, target, bindings, owner, call)
        let with_instance = match instance {
            InstanceGood(value) => value.store
            InstanceBad(value) => value
        }
        if match instance {
            InstanceGood(value) => false
            InstanceBad(value) => true
        } { return Ok(ExprBad(with_instance)) }
        let instance_id = match instance {
            InstanceGood(value) => value.instance
            InstanceBad(value) => 0
        }
        let concrete_result_id = use_by_ordinal(with_instance, instance_id, 8, 0)
        let concrete_result = __s0_buffer_get(DeclTypeUseRec, with_instance.uses, concrete_result_id - 1).checked_type
        return append_call_expression(d, state, parse, with_instance, owner, call_id, 8, concrete_result, 1, instance_id, 0, call, 1, site_kind, site_syntax)
    }
    let arguments = try check_positional_call_args(d, state, parse, base, store, owner, call, target, 5, 0, argument_count, 42)
    let current = match arguments {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match arguments {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    if match arguments {
        ExprGood(item) => item.draft.deferred
        ExprBad(item) => false
    } { return expr_deferred(base) }
    let result_id = use_by_ordinal(current, target, 6, 0)
    let result_type = __s0_buffer_get(DeclTypeUseRec, current.uses, result_id - 1).checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, call_id, 8, result_type, 1, target, 0, call, 1, site_kind, site_syntax)
}

fn check_variant_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if expected == 0 {
        let any = any_variant_named(state, store, callee)
        if any == 0 { return expr_fail(d, base, 40, callee) }
        let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, any - 1)
        if __s0_buffer_get(SymbolRec, store.symbols, variant.owner - 1).type_arity != 0 { return expr_deferred(base) }
        return expr_fail(d, base, 40, callee)
    }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
    if checked.kind != 7 { return expr_fail(d, base, 40, callee) }
    let enum_symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
    if enum_symbol.kind != 3 { return expr_fail(d, base, 40, callee) }
    let variant_id = variant_named(state, store, checked.target, callee)
    if variant_id == 0 { return expr_fail(d, base, 40, callee) }
    let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, variant_id - 1)
    if variant.checked_type == 0 { return expr_token_fail(d, state, base, 48, call) }
    if call_link_count(parse, call) != 2 { return expr_token_fail(d, state, base, 49, call) }
    let arg_link = call_link_at(parse, call, 1)
    let arg = __s0_buffer_get(SyntaxRec, parse.nodes, arg_link.node - 1)
    if arg.kind == 28 { return expr_token_fail(d, state, base, 50, arg) }
    var payload_store = store
    var payload_type = variant.checked_type
    if enum_symbol.type_arity != 0 {
        let empty = try __s0_buffer_new(InferenceBindingRec, d)
        let bindings = try bind_expected_application(d, store, checked.target, checked, 0, 0, empty)
        let concrete = try substitute_type(d, store, bindings, variant.checked_type)
        payload_store = concrete.store
        payload_type = concrete.checked_type
    }
    let payload = try check_value_expression_inner(d, state, parse, base, payload_store, owner, arg, arg_link.node, payload_type, 50, arg, 0, 0)
    let current = match payload {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match payload {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    let draft = match payload {
        ExprGood(item) => item.draft
        ExprBad(item) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    return append_call_expression(d, state, parse, current, owner, call_id, 10, expected, 4, checked.target, variant_id, call, 3, site_kind, site_syntax)
}

fn check_ordinary_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let callee_link = call_link_at(parse, call, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 {
        if callee.kind == 27 {
            let applied_callee_link = call_link_at(parse, callee, 0)
            let applied_callee = __s0_buffer_get(SyntaxRec, parse.nodes, applied_callee_link.node - 1)
            if applied_callee.kind != 24 { return expr_token_fail(d, state, base, 40, call) }
            let applied_target = symbol_named(state, store, applied_callee)
            if applied_target == 0 { return expr_token_fail(d, state, base, 40, call) }
            let applied_symbol = __s0_buffer_get(SymbolRec, store.symbols, applied_target - 1)
            if applied_symbol.kind == 2 && applied_symbol.type_arity != 0 {
                let resolved = try resolve_expression_type(d, state, parse, store, owner, callee_link.node)
                let current = match resolved {
                    CheckGood(value) => value
                    CheckBad(value) => value
                }
                if match resolved {
                    CheckGood(value) => false
                    CheckBad(value) => true
                } { return Ok(ExprBad(current)) }
                let applied_type = checked_type_for_syntax(current, callee_link.node)
                if expected != 0 && !(try expression_type_equal(d, state, parse, current, applied_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
                return check_record_call(d, state, parse, base, current, owner, call, call_id, applied_target, applied_type, mismatch_kind, mismatch_node, site_kind, site_syntax)
            }
            return expr_token_fail(d, state, base, 56, callee)
        }
        return expr_token_fail(d, state, base, 40, call)
    }
    let target = symbol_named(state, store, callee)
    if target != 0 {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
        if symbol.kind == 12 { return check_function_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if symbol.kind == 1 { return expr_fail(d, base, 51, callee) }
        if symbol.kind == 2 { return check_record_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if symbol.kind == 3 && symbol.type_arity != 0 { return expr_deferred(base) }
        return expr_fail(d, base, 40, callee)
    }
    if expected != 0 {
        let expected_type = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
        if expected_type.kind == 7 && __s0_buffer_get(SymbolRec, store.symbols, expected_type.target - 1).kind == 3 {
            return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
        }
    }
    if any_variant_named(state, store, callee) != 0 { return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if reserved_symbol(state, callee) { return expr_deferred(base) }
    return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_unsafe_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, unsafe_node: SyntaxRec, unsafe_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let root_link = __s0_buffer_get(SyntaxLinkRec, parse.links, unsafe_node.children - 1)
    let call = __s0_buffer_get(SyntaxRec, parse.nodes, root_link.node - 1)
    let callee_link = call_link_at(parse, call, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 { return expr_token_fail(d, state, base, 52, unsafe_node) }
    let target = symbol_named(state, store, callee)
    if target == 0 || __s0_buffer_get(SymbolRec, store.symbols, target - 1).kind != 1 { return expr_token_fail(d, state, base, 52, unsafe_node) }
    let argument_count = call_link_count(parse, call) - 1
    var ordinal: U64 = 0
    while ordinal < argument_count {
        let arg_link = call_link_at(parse, call, ordinal + 1)
        if syntax_contains_call(parse, arg_link.node) {
            let arg = __s0_buffer_get(SyntaxRec, parse.nodes, arg_link.node - 1)
            return expr_token_fail(d, state, base, 53, arg)
        }
        ordinal = ordinal + 1
    }
    let parameter_count = use_count(store, target, 3)
    if argument_count != parameter_count { return expr_token_fail(d, state, base, 54, call) }
    let arguments = try check_positional_call_args(d, state, parse, base, store, owner, call, target, 3, 0, argument_count, 55)
    let current = match arguments {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match arguments {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    if match arguments {
        ExprGood(item) => item.draft.deferred
        ExprBad(item) => false
    } { return expr_deferred(base) }
    let result_id = use_by_ordinal(current, target, 4, 0)
    let result_type = __s0_buffer_get(DeclTypeUseRec, current.uses, result_id - 1).checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, unsafe_id, 11, result_type, 2, target, 0, call, 1, site_kind, site_syntax)
}

// Shared recursive value-expression slice for returns, binding initializers,
// and assignment values. The base store is retained across the whole traversal
// so a deferred shape or semantic failure cannot expose a partial graph.
fn check_value_expression_inner(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, expression: SyntaxRec, expression_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if expression.kind == 27 { return check_ordinary_call(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 36 { return check_unsafe_call(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 20 {
        var literal_type = expected
        if literal_type == 0 { literal_type = primitive_type_id(state, parse, store, "I64") }
        if literal_type == 0 { return expr_deferred(base) }
        let limits = int_result_range(state, parse, __s0_buffer_get(CheckedTypeRec, store.types, literal_type - 1))
        if !limits.integer { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        let token = __s0_buffer_get(TokenRec, state.tokens, expression.token - 1)
        var negative = false
        var magnitude = token.value_start
        if token.value_end > token.value_start && __s0_buffer_get(U8, state.values, token.value_start) == 45 {
            negative = true
            magnitude = token.value_start + 1
        }
        if negative && zero_magnitude(state.values, magnitude, token.value_end) { negative = false }
        var limit = limits.positive
        if negative {
            if !limits.signed { return expr_token_fail(d, state, base, 21, expression) }
            limit = limits.negative
        }
        if !digits_at_most(state.values, magnitude, token.value_end, limit) { return expr_token_fail(d, state, base, 21, expression) }
        return append_expression(d, store, owner, expression_id, 3, literal_type, 0, 0, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 22 {
        var string_store = store
        var string_type = expected
        if string_type == 0 {
            let existing = canonical_single_arg(store, 8, 0, 6)
            if existing != 0 { string_type = existing } else {
                let args = try __s0_buffer_append(U64, d, store.type_args, 6)
                let recorded = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, diagnostics: store.diagnostics)
                string_store = try append_checked_type(d, recorded, owner, 8, 0, 0, __s0_buffer_len(U64, args), 1)
                string_type = canonical_single_arg(string_store, 8, 0, 6)
            }
        }
        let expected_type = __s0_buffer_get(CheckedTypeRec, string_store.types, string_type - 1)
        let empty_strings = try __s0_buffer_new(TypeBindingRec, d)
        if !interpreted_slice_u8(state, parse, string_store, empty_strings, expected_type, 0) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, string_store, owner, expression_id, 4, string_type, 0, 0, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 23 {
        var bool_type = expected
        if expected != 0 && !primitive_type_named(state, parse, store, expected, "Bool") { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        if bool_type == 0 { bool_type = primitive_type_id(state, parse, store, "Bool") }
        if bool_type == 0 { return expr_deferred(base) }
        let token = __s0_buffer_get(TokenRec, state.tokens, expression.token - 1)
        var bool_value: U64 = 0
        if token.keyword == 17 { bool_value = 1 }
        else { if token.keyword != 18 { return expr_deferred(base) } }
        return append_expression(d, store, owner, expression_id, 2, bool_type, 0, bool_value, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 24 {
        let local_id = local_lookup(store, owner, expression, state)
        if local_id == 0 && expected != 0 {
            let expected_type = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
            if expected_type.kind == 7 {
                let expected_symbol = __s0_buffer_get(SymbolRec, store.symbols, expected_type.target - 1)
                if expected_symbol.kind == 3 {
                    let variant_id = variant_named(state, store, expected_type.target, expression)
                    if variant_id == 0 { return expr_fail(d, base, 40, expression) }
                    let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, variant_id - 1)
                    if variant.checked_type != 0 { return expr_fail(d, base, 47, expression) }
                    return append_call_expression(d, state, parse, store, owner, expression_id, 10, expected, 4, expected_type.target, variant_id, expression, 0, site_kind, site_syntax)
                }
            }
        }
        var kind: U64 = 5
        var reference = local_id
        var binding_type: U64 = 0
        if local_id != 0 {
            let binding = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
            binding_type = binding.checked_type
            if binding.kind == 1 { kind = 1 }
        } else {
            let target = symbol_named(state, store, expression)
            if target != 0 && __s0_buffer_get(SymbolRec, store.symbols, target - 1).kind == 12 { return expr_fail(d, base, 39, expression) }
            let any_variant = any_variant_named(state, store, expression)
            if any_variant != 0 {
                let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, any_variant - 1)
                if __s0_buffer_get(SymbolRec, store.symbols, variant.owner - 1).type_arity != 0 { return expr_deferred(base) }
                return expr_fail(d, base, 40, expression)
            }
            if known_body_identifier(state, store, expression) { return expr_deferred(base) }
            return expr_fail(d, base, 18, expression)
        }
        if expected != 0 && !(try expression_type_equal(d, state, parse, store, binding_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, store, owner, expression_id, kind, binding_type, reference, 0, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 25 {
        let operator = expression_operator(state, expression)
        if operator == 0 { return expr_deferred(base) }
        let child_link = __s0_buffer_get(SyntaxLinkRec, parse.links, expression.children - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, child_link.node - 1)
        var child_expected: U64 = 0
        if operator == 1 {
            if (child.kind == 20 || child.kind == 25) && expected != 0 && int_result_range(state, parse, __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)).integer { child_expected = expected }
        }
        let checked_child = try check_value_expression_inner(d, state, parse, base, store, owner, child, child_link.node, child_expected, mismatch_kind, mismatch_node, 0, 0)
        let child_store = match checked_child {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_child {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(child_store)) }
        let child_draft = match checked_child {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if child_draft.deferred { return expr_deferred(base) }
        if operator == 2 && !primitive_type_named(state, parse, child_store, child_draft.checked_type, "Bool") { return expr_token_fail(d, state, base, 29, expression) }
        if operator == 1 {
            let limits = int_result_range(state, parse, __s0_buffer_get(CheckedTypeRec, child_store.types, child_draft.checked_type - 1))
            if limits.integer && !limits.signed { return expr_token_fail(d, state, base, 30, expression) }
            if !limits.integer { return expr_token_fail(d, state, base, 31, expression) }
        }
        if expected != 0 && !(try expression_type_equal(d, state, parse, child_store, child_draft.checked_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, child_store, owner, expression_id, 6, child_draft.checked_type, 0, 0, child_draft.expression, 0, operator, site_kind, site_syntax)
    }
    if expression.kind != 26 { return expr_deferred(base) }
    let operator = expression_operator(state, expression)
    if operator < 3 { return expr_deferred(base) }
    let right_link = __s0_buffer_get(SyntaxLinkRec, parse.links, expression.children - 1)
    let left_link = __s0_buffer_get(SyntaxLinkRec, parse.links, right_link.next - 1)
    let left = __s0_buffer_get(SyntaxRec, parse.nodes, left_link.node - 1)
    let right = __s0_buffer_get(SyntaxRec, parse.nodes, right_link.node - 1)
    if operator == 16 || operator == 17 {
        var bool_type = expected
        if !primitive_type_named(state, parse, store, bool_type, "Bool") { bool_type = primitive_type_id(state, parse, store, "Bool") }
        if bool_type == 0 { return expr_deferred(base) }
        let checked_left = try check_value_expression_inner(d, state, parse, base, store, owner, left, left_link.node, 0, 32, expression, 0, 0)
        let left_store = match checked_left {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_left {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(left_store)) }
        let left_draft = match checked_left {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if left_draft.deferred { return expr_deferred(base) }
        let checked_right = try check_value_expression_inner(d, state, parse, base, left_store, owner, right, right_link.node, 0, 32, expression, 0, 0)
        let right_store = match checked_right {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_right {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(right_store)) }
        let right_draft = match checked_right {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if right_draft.deferred { return expr_deferred(base) }
        if !primitive_type_named(state, parse, right_store, left_draft.checked_type, "Bool") || !primitive_type_named(state, parse, right_store, right_draft.checked_type, "Bool") { return expr_token_fail(d, state, base, 32, expression) }
        if expected != 0 && !(try expression_type_equal(d, state, parse, right_store, bool_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, right_store, owner, expression_id, 7, bool_type, 0, 0, left_draft.expression, right_draft.expression, operator, site_kind, site_syntax)
    }
    let checked_left = try check_value_expression_inner(d, state, parse, base, store, owner, left, left_link.node, 0, mismatch_kind, mismatch_node, 0, 0)
    let left_store = match checked_left {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked_left {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(left_store)) }
    let left_draft = match checked_left {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if left_draft.deferred { return expr_deferred(base) }
    let left_limits = int_result_range(state, parse, __s0_buffer_get(CheckedTypeRec, left_store.types, left_draft.checked_type - 1))
    if (operator == 8 || operator == 9) && !left_limits.integer { return expr_token_fail(d, state, base, 33, expression) }
    if operator >= 3 && operator <= 7 && !left_limits.integer { return expr_token_fail(d, state, base, 37, expression) }
    var operand_mismatch: U64 = 38
    if operator == 8 || operator == 9 { operand_mismatch = 34 }
    if operator >= 10 && operator <= 15 { operand_mismatch = 35 }
    let checked_right = try check_value_expression_inner(d, state, parse, base, left_store, owner, right, right_link.node, left_draft.checked_type, operand_mismatch, expression, 0, 0)
    let right_store = match checked_right {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked_right {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(right_store)) }
    let right_draft = match checked_right {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if right_draft.deferred { return expr_deferred(base) }
    if !(try expression_type_equal(d, state, parse, right_store, left_draft.checked_type, right_draft.checked_type)) {
        if operator == 8 || operator == 9 { return expr_token_fail(d, state, base, 34, expression) }
        if operator >= 10 && operator <= 15 { return expr_token_fail(d, state, base, 35, expression) }
        return expr_token_fail(d, state, base, 38, expression)
    }
    var result_type = left_draft.checked_type
    if operator >= 10 && operator <= 15 {
        if !left_limits.integer && !float_type(state, parse, right_store, left_draft.checked_type) { return expr_token_fail(d, state, base, 36, expression) }
        result_type = expected
        if !primitive_type_named(state, parse, right_store, result_type, "Bool") { result_type = primitive_type_id(state, parse, right_store, "Bool") }
        if result_type == 0 { return expr_deferred(base) }
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, right_store, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_expression(d, right_store, owner, expression_id, 7, result_type, 0, 0, left_draft.expression, right_draft.expression, operator, site_kind, site_syntax)
}

fn check_value_expression(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, expression: SyntaxRec, expression_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    return check_value_expression_inner(d, state, parse, store, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

// Binding order follows the Go checker: reserved name, annotation resolution,
// initializer and mismatch, Unit/DomainMark rejection, then duplicates.
// Unannotated scalar bindings infer from integer/Bool literals, identifiers,
// and supported unary/binary expressions.
fn check_binding(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64) -> Result(BodyStep, __s0_Error) {
    if reserved_value_name(state, store, statement) { return body_fail(d, store, 22, statement) }
    let head = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
    var next = store
    var annotated: U64 = 0
    var annotation_syntax: U64 = 0
    if head.next != 0 {
        let type_link = __s0_buffer_get(SyntaxLinkRec, parse.links, head.next - 1)
        annotation_syntax = type_link.node
        let resolved = try resolve_type(d, state, parse, store, owner, type_link.node)
        next = match resolved {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        if match resolved {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(BodyBad(next)) }
        annotated = checked_type_for_syntax(next, type_link.node)
    }
    let init = __s0_buffer_get(SyntaxRec, parse.nodes, head.node - 1)
    let outcome = try check_value_expression(d, state, parse, next, owner, init, head.node, annotated, 23, statement, 1, statement_id)
    let ostore = match outcome {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match outcome {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(BodyBad(ostore)) }
    let draft = match outcome {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(BodyDefer) }
    if annotated == 0 { annotated = draft.checked_type }
    let annotation = __s0_buffer_get(CheckedTypeRec, ostore.types, annotated - 1)
    var diag_node = statement
    if annotation_syntax != 0 { diag_node = __s0_buffer_get(SyntaxRec, parse.nodes, annotation_syntax - 1) }
    if annotation.kind == 1 && annotation.target == 12 { return body_fail(d, next, 25, diag_node) }
    if annotation.kind == 4 { return body_fail(d, next, 26, diag_node) }
    if local_lookup(ostore, owner, statement, state) != 0 || function_use(ostore, owner, 5, statement, state) != 0 { return body_fail(d, next, 27, statement) }
    var mutable: U64 = 0
    if statement.kind == 16 { mutable = 1 }
    let locals = try __s0_buffer_append(LocalRec, d, ostore.locals, LocalRec(owner: owner, kind: 2, syntax: statement_id, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: mutable, checked_type: annotated))
    let binding = __s0_buffer_len(LocalRec, locals)
    var parent: U64 = 0
    if __s0_buffer_len(EnvironmentRec, ostore.environments) != 0 {
        let candidate = __s0_buffer_len(EnvironmentRec, ostore.environments)
        if __s0_buffer_get(EnvironmentRec, ostore.environments, candidate - 1).owner == owner { parent = candidate }
    }
    let environments = try __s0_buffer_append(EnvironmentRec, d, ostore.environments, EnvironmentRec(owner: owner, parent: parent, binding: binding))
    return Ok(BodyGood(CheckStore(symbols: ostore.symbols, type_params: ostore.type_params, types: ostore.types, type_args: ostore.type_args, type_annotations: ostore.type_annotations, uses: ostore.uses, locals: locals, environments: environments, expressions: ostore.expressions, call_annotations: ostore.call_annotations, expression_children: ostore.expression_children, returns: ostore.returns, diagnostics: ostore.diagnostics)))
}

// Only plain identifier targets are in this slice; field and index targets
// defer. Parameters are immutable, matching the Go checker's bindParam.
fn check_assignment(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64) -> Result(BodyStep, __s0_Error) {
    let head = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
    let target_link = __s0_buffer_get(SyntaxLinkRec, parse.links, head.next - 1)
    let target = __s0_buffer_get(SyntaxRec, parse.nodes, target_link.node - 1)
    if target.kind != 24 { return Ok(BodyDefer) }
    var binding_type: U64 = 0
    let local_id = local_lookup(store, owner, target, state)
    if local_id != 0 {
        let local = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
        if local.mutable == 0 { return body_fail(d, store, 28, target) }
        binding_type = local.checked_type
    } else {
        if function_use(store, owner, 5, target, state) == 0 { return body_fail(d, store, 18, target) }
        return body_fail(d, store, 28, target)
    }
    let rhs = __s0_buffer_get(SyntaxRec, parse.nodes, head.node - 1)
    let outcome = try check_value_expression(d, state, parse, store, owner, rhs, head.node, binding_type, 24, statement, 2, statement_id)
    let ostore = match outcome {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match outcome {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(BodyBad(ostore)) }
    let draft = match outcome {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(BodyDefer) }
    return Ok(BodyGood(ostore))
}

fn check_expression_statement(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64) -> Result(BodyStep, __s0_Error) {
    let expression_link = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
    let expression = __s0_buffer_get(SyntaxRec, parse.nodes, expression_link.node - 1)
    let outcome = try check_value_expression(d, state, parse, store, owner, expression, expression_link.node, 0, 23, statement, 4, statement_id)
    let current = match outcome {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match outcome {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(BodyBad(current)) }
    let draft = match outcome {
        ExprGood(item) => item.draft
        ExprBad(item) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(BodyDefer) }
    return Ok(BodyGood(current))
}

fn check_body_statements(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(BodyStep, __s0_Error) {
    if link_id == 0 { return Ok(BodyGood(store)) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let before = try check_body_statements(d, state, parse, store, owner, link.next)
    let current = match before {
        BodyGood(value) => value
        BodyBad(value) => value
        BodyDefer => store
    }
    if match before {
        BodyGood(value) => false
        BodyBad(value) => true
        BodyDefer => true
    } { return Ok(before) }
    let statement = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    if statement.kind == 15 || statement.kind == 16 { return check_binding(d, state, parse, current, owner, statement, link.node) }
    if statement.kind == 17 { return check_assignment(d, state, parse, current, owner, statement, link.node) }
    if statement.kind == 19 { return check_expression_statement(d, state, parse, current, owner, statement, link.node) }
    return Ok(BodyDefer)
}

fn append_parameter_bindings(d: Domain, store: CheckStore, owner: U64) -> Result(CheckStore, __s0_Error) {
    var next = store
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    var role: U64 = 5
    if symbol.kind == 13 { role = 7 }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role {
            let locals = try __s0_buffer_append(LocalRec, d, next.locals, LocalRec(owner: owner, kind: 1, syntax: use.node, source: use.source, name_start: use.name_start, name_end: use.name_end, mutable: 0, checked_type: use.checked_type))
            let binding = __s0_buffer_len(LocalRec, locals)
            var parent: U64 = 0
            if __s0_buffer_len(EnvironmentRec, next.environments) != 0 {
                let candidate = __s0_buffer_len(EnvironmentRec, next.environments)
                if __s0_buffer_get(EnvironmentRec, next.environments, candidate - 1).owner == owner { parent = candidate }
            }
            let environments = try __s0_buffer_append(EnvironmentRec, d, next.environments, EnvironmentRec(owner: owner, parent: parent, binding: binding))
            next = CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: next.uses, locals: locals, environments: environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, diagnostics: next.diagnostics)
        }
        at = at + 1
    }
    return Ok(next)
}

// A body checks as zero or more leading let/var bindings and plain-identifier
// assignments followed by one top-level return. Any other statement or
// expression shape defers the whole body so later slices never consume
// partial records. Generic declarations are checked only through concrete
// instances discovered by calls.
fn check_body(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if !((symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13) { return Ok(CheckGood(store)) }
    let declaration = __s0_buffer_get(SymbolRec, store.symbols, instance_declaration(store, owner) - 1)
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, declaration.node - 1)
    let body_link = __s0_buffer_get(SyntaxLinkRec, parse.links, root.children - 1)
    let body = __s0_buffer_get(SyntaxRec, parse.nodes, body_link.node - 1)
    if body.children == 0 { return Ok(CheckGood(store)) }
    let statement_link = __s0_buffer_get(SyntaxLinkRec, parse.links, body.children - 1)
    let statement = __s0_buffer_get(SyntaxRec, parse.nodes, statement_link.node - 1)
    if statement.kind != 18 { return Ok(CheckGood(store)) }
    let with_parameters = try append_parameter_bindings(d, store, owner)
    let stepped = try check_body_statements(d, state, parse, with_parameters, owner, statement_link.next)
    let after = match stepped {
        BodyGood(value) => value
        BodyBad(value) => value
        BodyDefer => store
    }
    if match stepped {
        BodyGood(value) => false
        BodyBad(value) => true
        BodyDefer => false
    } { return Ok(CheckBad(rollback_body(store, after))) }
    if match stepped {
        BodyGood(value) => false
        BodyBad(value) => false
        BodyDefer => true
    } { return Ok(CheckGood(store)) }
    let result_use_id = function_use(after, owner, 6, statement, state)
    let result_use = __s0_buffer_get(DeclTypeUseRec, after.uses, result_use_id - 1)
    let result_type = __s0_buffer_get(CheckedTypeRec, after.types, result_use.checked_type - 1)
    if statement.children == 0 {
        if result_type.kind != 1 || result_type.target != 12 {
            let failed = try check_token_fail(d, state, after, 20, statement)
            let bad = match failed {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            return Ok(CheckBad(rollback_body(store, bad)))
        }
        let returns = try __s0_buffer_append(CheckedReturnRec, d, after.returns, CheckedReturnRec(owner: owner, syntax: statement_link.node, expression: 0, result_use: result_use_id))
        return Ok(CheckGood(CheckStore(symbols: after.symbols, type_params: after.type_params, types: after.types, type_args: after.type_args, type_annotations: after.type_annotations, uses: after.uses, locals: after.locals, environments: after.environments, expressions: after.expressions, call_annotations: after.call_annotations, expression_children: after.expression_children, returns: returns, diagnostics: after.diagnostics)))
    }
    let expression_link = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
    let expression = __s0_buffer_get(SyntaxRec, parse.nodes, expression_link.node - 1)
    if expression_link.next != 0 { return Ok(CheckGood(store)) }
    let outcome = try check_value_expression(d, state, parse, after, owner, expression, expression_link.node, result_use.checked_type, 19, statement, 3, statement_link.node)
    let ostore = match outcome {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match outcome {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(CheckBad(rollback_body(store, ostore))) }
    let draft = match outcome {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(CheckGood(store)) }
    let returns = try __s0_buffer_append(CheckedReturnRec, d, ostore.returns, CheckedReturnRec(owner: owner, syntax: statement_link.node, expression: draft.expression, result_use: result_use_id))
    return Ok(CheckGood(CheckStore(symbols: ostore.symbols, type_params: ostore.type_params, types: ostore.types, type_args: ostore.type_args, type_annotations: ostore.type_annotations, uses: ostore.uses, locals: ostore.locals, environments: ostore.environments, expressions: ostore.expressions, call_annotations: ostore.call_annotations, expression_children: ostore.expression_children, returns: returns, diagnostics: ostore.diagnostics)))
}

fn check_function_body_at(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckResult, __s0_Error) {
    if owner > __s0_buffer_len(SymbolRec, store.symbols) { return Ok(CheckGood(store)) }
    let checked = try check_body(d, state, parse, store, owner)
    let next = match checked {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match checked {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(checked) }
    return check_function_body_at(d, state, parse, next, owner + 1)
}

fn check_function_bodies(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    return check_function_body_at(d, state, parse, store, 1)
}

fn check_declarations(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    let aggregates = try check_declaration_kind(d, state, parse, initial, 0)
    let after_aggregates = match aggregates {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match aggregates {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(aggregates) }
    let cycles = try reject_value_cycles(d, state, parse, after_aggregates)
    let after_cycles = match cycles {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match cycles {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(cycles) }
    let restrictions = try revalidate_aggregate_roots(d, state, parse, after_cycles)
    let after_restrictions = match restrictions {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match restrictions {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(restrictions) }
    let imports = try check_declaration_kind(d, state, parse, after_restrictions, 1)
    let after_imports = match imports {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match imports {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(imports) }
    let functions = try check_declaration_kind(d, state, parse, after_imports, 12)
    let after_functions = match functions {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match functions {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(functions) }
    return check_function_bodies(d, state, parse, after_functions)
}

fn check_parsed(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    // Orchestration callers invoke this only for ParseGood. Keep the guard so
    // malformed direct callers cannot run checking after either earlier phase.
    if __s0_buffer_len(LexDiagRec, state.diagnostics) != 0 || __s0_buffer_len(ParseDiagRec, parse.diagnostics) != 0 { return Ok(CheckBad(initial)) }
    var seeded = initial
    var primitive: U64 = 1
    while primitive <= 12 {
        seeded = try append_checked_type(d, seeded, 0, 1, 0, primitive, 0, 0)
        primitive = primitive + 1
    }
    let symbols = try collect_symbols(d, state, parse, seeded)
    let store = match symbols {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match symbols {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(symbols) }
    return check_declarations(d, state, parse, store)
}

fn emit_check_sources(state: State) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(SourceRec, state.sources) {
        let rec = __s0_buffer_get(SourceRec, state.sources, at)
        if !out_string("S ") || !out_u64(at) || !out(32) || !out_hex(state.paths, rec.path_start, rec.path_end) || !out(32) || !out_u64(rec.text_end - rec.text_start) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_check_manifest(state: State, store: CheckStore) -> Bool {
    // Checker paths are hex encoded so every host path remains one unambiguous
    // whitespace-delimited field. All later records refer to numeric source IDs.
    if !out_string("ALDER-CHECKER-MANIFEST 9\n") || !emit_check_sources(state) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let rec = __s0_buffer_get(SymbolRec, store.symbols, at)
        if !out_string("Y ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.type_arity) || !out(32) || !out_u64(rec.declaration) || !out(32) || !out_u64(rec.first_instance_arg) || !out(32) || !out_u64(rec.instance_arg_count) || !out(32) || !out_u64(rec.discovery_parent) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let rec = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if !out_string("P ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let rec = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if !out_string("C ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.target) || !out(32) || !out_u64(rec.first_arg) || !out(32) || !out_u64(rec.arg_count) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(U64, store.type_args) {
        if !out_string("A ") || !out_u64(at + 1) || !out(32) || !out_u64(__s0_buffer_get(U64, store.type_args, at)) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTypeAnnotationRec, store.type_annotations) {
        let rec = __s0_buffer_get(CheckedTypeAnnotationRec, store.type_annotations, at)
        if !out_string("T ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let rec = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if !out_string("U ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.role) || !out(32) || !out_u64(rec.ordinal) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    var instance_order: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let rec = __s0_buffer_get(SymbolRec, store.symbols, at)
        if rec.declaration != 0 {
            instance_order = instance_order + 1
            if !out_string("I ") || !out_u64(instance_order) || !out(32) || !out_u64(at + 1) || !out(32) || !out_u64(rec.declaration) || !out(32) || !out_u64(rec.first_instance_arg) || !out(32) || !out_u64(rec.instance_arg_count) || !out(32) || !out_u64(rec.discovery_parent) || !out(10) { return false }
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(LocalRec, store.locals) {
        let rec = __s0_buffer_get(LocalRec, store.locals, at)
        if !out_string("L ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.mutable) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(EnvironmentRec, store.environments) {
        let rec = __s0_buffer_get(EnvironmentRec, store.environments, at)
        if !out_string("N ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.parent) || !out(32) || !out_u64(rec.binding) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CallAnnotationRec, store.call_annotations) {
        let rec = __s0_buffer_get(CallAnnotationRec, store.call_annotations, at)
        if !out_string("Q ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.target) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.variant_use) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprRec, store.expressions) {
        let rec = __s0_buffer_get(CheckedExprRec, store.expressions, at)
        if !out_string("E ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.parameter_use) || !out(32) || !out_u64(rec.bool_value) || !out(32) || !out_u64(rec.left) || !out(32) || !out_u64(rec.right) || !out(32) || !out_u64(rec.annotation) || !out(32) || !out_u64(rec.first_child) || !out(32) || !out_u64(rec.child_count) || !out(32) || !out_u64(rec.operator) || !out(32) || !out_u64(rec.site_kind) || !out(32) || !out_u64(rec.site_syntax) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedExprChildRec, store.expression_children) {
        let rec = __s0_buffer_get(CheckedExprChildRec, store.expression_children, at)
        if !out_string("H ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.expression) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedReturnRec, store.returns) {
        let rec = __s0_buffer_get(CheckedReturnRec, store.returns, at)
        if !out_string("R ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.expression) || !out(32) || !out_u64(rec.result_use) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckDiagRec, store.diagnostics) {
        let rec = __s0_buffer_get(CheckDiagRec, store.diagnostics, at)
        let related = rec.related_start != 0 || rec.related_end != 0
        if !out_string("D ") || !out_u64(rec.kind) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.start) || !out(32) || !out_u64(rec.end) || !out(32) { return false }
        if related {
            if !out_string("1 ") || !out_u64(rec.related_source) || !out(32) || !out_u64(rec.related_start) || !out(32) || !out_u64(rec.related_end) || !out(10) { return false }
        } else { if !out_string("0\n") { return false } }
        at = at + 1
    }
    return out_string("END\n")
}
