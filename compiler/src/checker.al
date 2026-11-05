// The private bootstrap profile keeps the explicit S0 storage, buffer, map,
// and __s0_String bridge names available. Ordinary programs construct values
// through inferred storage, so the checker rejects those names unless the
// request compiled the compiler's own bootstrap sources (the host reports the
// --bootstrap-private request flag).
import c alderhost_bootstrap_private: fn() -> Bool

fn check_bootstrap_private() -> Bool { return unsafe c { alderhost_bootstrap_private() } }

type CheckerUseIndexRec {
    first: U64
    count: U64
}

type CheckerIndexes {
    uses: __s0_Buffer(CheckerUseIndexRec)
    use_order: __s0_Buffer(U64)
    complete: Bool
}

type CheckStore {
    symbols: __s0_Buffer(SymbolRec)
    type_params: __s0_Buffer(TypeParamRec)
    types: __s0_Buffer(CheckedTypeRec)
    type_args: __s0_Buffer(U64)
    type_annotations: __s0_Buffer(CheckedTypeAnnotationRec)
    uses: __s0_Buffer(DeclTypeUseRec)
    indexes: CheckerIndexes
    locals: __s0_Buffer(LocalRec)
    environments: __s0_Buffer(EnvironmentRec)
    expressions: __s0_Buffer(CheckedExprRec)
    call_annotations: __s0_Buffer(CallAnnotationRec)
    expression_children: __s0_Buffer(CheckedExprChildRec)
    returns: __s0_Buffer(CheckedReturnRec)
    control: CheckedControlStore
    diagnostics: __s0_Buffer(CheckDiagRec)
    traits: TraitStoreRec
    closures: ClosureStoreRec
}

// One closure site per fn-literal: the synthetic thunk owner, the checked
// expression that creates the closure value, how many role-5 uses are
// declared parameters (the remaining ones are captures), and the capture
// list. The thunk body is checked like an ordinary function body owned by
// the synthetic symbol, so captures resolve as its trailing immutable
// parameters and writes to them fall out as parameter immutability.
type ClosureStoreRec {
    sites: __s0_Buffer(ClosureSiteRec)
    captures: __s0_Buffer(ClosureCaptureRec)
}

type ClosureSiteRec {
    owner: U64
    expression: U64
    declared_count: U64
    capture_count: U64
    first_capture: U64
}

type ClosureCaptureRec {
    local: U64
    checked_type: U64
}

fn empty_closure_store(d: Domain) -> Result(ClosureStoreRec, __s0_Error) {
    let sites = try __s0_buffer_new(ClosureSiteRec, d)
    let captures = try __s0_buffer_new(ClosureCaptureRec, d)
    return Ok(ClosureStoreRec(sites: sites, captures: captures))
}

// Resolved static-trait reference: builtin standard traits are identified by
// their stable ID, user-declared traits by symbol ID, and trait arguments
// are canonical checked types in the flat type_args buffer.
type TraitRefRec {
    builtin: U64
    symbol: U64
    first_arg: U64
    arg_count: U64
}

type TraitRefStoreRec {
    store: CheckStore
    reference: TraitRefRec
}

enum TraitRefResult {
    TraitRefGood(value: TraitRefStoreRec)
    TraitRefBad(value: CheckStore)
}

fn checked_spans(d: Domain, parse: ParseStore) -> Result(__s0_Buffer(CheckedSpanRec), __s0_Error) {
    var spans = try __s0_buffer_new(CheckedSpanRec, d)
    var at: U64 = 0
    while at < __s0_buffer_len(SyntaxRec, parse.nodes) {
        let node = __s0_buffer_get(SyntaxRec, parse.nodes, at)
        spans = try __s0_buffer_append(CheckedSpanRec, d, spans, CheckedSpanRec(source: node.source, start: node.start, end: node.end, name_start: node.name_start, name_end: node.name_end))
        at = at + 1
    }
    return Ok(spans)
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
    BodyGood(value: BodyValueRec)
    BodyBad(value: CheckStore)
}

type BodyValueRec {
    store: CheckStore
    environment: U64
    semantic: U64
    guaranteed_return: Bool
}

type MatchArmValueRec {
    store: CheckStore
    arm_type: U64
    first_arm: U64
    arm_count: U64
    wildcard: Bool
    block_arms: Bool
    expression_arms: Bool
    arms: __s0_Buffer(MatchArmDraftRec)
}

type MatchArmDraftRec {
    owner: U64
    syntax: U64
    variant_use: U64
    variant_kind: U64
    binding: U64
    environment: U64
    body: U64
    block: U64
}

enum MatchArmOutcome {
    MatchArmsGood(value: MatchArmValueRec)
    MatchArmsBad(value: CheckStore)
    MatchArmsDefer
}

// Transient body events separate parser-graph structure from semantic state.
// Kinds are 1 block, 2 ordered statement-list cell, 3 leaf statement,
// 4 nested block statement, 5 if, 6 while, and 7 for. Using remains a kind-3
// leaf because it introduces no child block. first/second/third name
// event IDs or parser syntax IDs according to kind. Events never enter the
// manifest and carry no CheckStore or domain-backed semantic buffer.
type BodyEventRec {
    kind: U64
    syntax: U64
    first: U64
    second: U64
    third: U64
}

type BodyEventBuildRec {
    events: __s0_Buffer(BodyEventRec)
    event: U64
}

type PlaceValueRec {
    store: CheckStore
    place: U64
    checked_type: U64
}

enum PlaceOutcome {
    PlaceGood(value: PlaceValueRec)
    PlaceBad(value: CheckStore)
    PlaceDefer
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

type ArrayElementsRec {
    store: CheckStore
    element_type: U64
    first_child: U64
    child_count: U64
}

enum ArrayElementsOutcome {
    ArrayElementsGood(value: ArrayElementsRec)
    ArrayElementsBad(value: CheckStore)
    ArrayElementsDefer
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
    positive: __s0_String
    negative: __s0_String
}

type ArrayLengthRec {
    valid: Bool
    value: U64
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
// target and direct arguments and never expand declaration bodies.
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
                    if !((a.kind == 16 && interpreted_slice_u8(state, parse, store, bindings, b, right.env)) || (b.kind == 16 && interpreted_slice_u8(state, parse, store, bindings, a, left.env))) { return Ok(false) }
                }
                else {
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
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
    var role: U64 = 0
    if symbol.kind == 2 { role = 1 }
    if symbol.kind == 3 { role = 2 }
    if role != 0 && checker_use_index_available(store, target, role) {
        let index = __s0_buffer_get(CheckerUseIndexRec, store.indexes.uses, checker_use_slot(target, role))
        var ordinal: U64 = 0
        while ordinal < index.count {
            let use_id = __s0_buffer_get(U64, store.indexes.use_order, index.first - 1 + ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            if use.checked_type != 0 {
                result = try __s0_buffer_append(InterpWorkRec, d, result, InterpWorkRec(checked_type: use.checked_type, env: env, ancestry: ancestry))
            }
            ordinal = ordinal + 1
        }
        return Ok(result)
    }
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
            if checked.kind == 3 || checked.kind == 4 || checked.kind == 8 || checked.kind == 11 || checked.kind == 12 || checked.kind == 13 || checked.kind == 16 || checked.kind == 18 { return Ok(true) }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 15 || checked.kind == 17 {
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

// Value-category interpretation follows concrete substitutions and nominal
// members without unfolding the same specialization twice. Affine ownership
// wins the primary category when an aggregate also contains a scoped
// capability; contains_scoped retains the independent escape restriction.
fn interpreted_type_category(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: __s0_Buffer(TypeBindingRec), initial_ancestry: __s0_Buffer(DeclAncestryRec), checked_type: U64, env: U64, ancestry_id: U64) -> Result(TypeCategoryRec, __s0_Error) {
    var bindings = initial_bindings
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: ancestry_id))
    var ancestry = initial_ancestry
    let first_memo = try __s0_buffer_new(ExpansionMemoRec, d)
    var memo = first_memo
    let first_seen = try __s0_buffer_new(InterpStateRec, d)
    var seen = first_seen
    var affine = false
    var scoped = false
    var unresolved = false
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
            if checked.kind == 3 || checked.kind == 19 { affine = true }
            // A nominal type that implements Cleanup is an
            // affine owner: cleanup selection consumes it on every exit. The
            // receiver index answers this in logarithmic time.
            if checked.kind == 7 && type_cleanup_impls(store, checked.target) != 0 { affine = true }
            if checked.kind == 4 || checked.kind == 8 || checked.kind == 12 || checked.kind == 18 || checked.kind == 21 || checked.kind == 22 { scoped = true }
            if checked.kind == 6 { unresolved = true }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 || checked.kind == 13 || checked.kind == 15 || checked.kind == 17 {
                var child: U64 = 0
                while child < checked.arg_count {
                    work = try __s0_buffer_append(InterpWorkRec, d, work, InterpWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), env: norm.env, ancestry: norm.ancestry))
                    child = child + 1
                }
            }
            if checked.kind == 7 {
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
    var category: U64 = 1
    if scoped { category = 3 }
    if affine { category = 2 }
    if unresolved { category = 0 }
    return Ok(TypeCategoryRec(category: category, contains_scoped: scoped))
}

fn checked_type_contains_scoped(d: Domain, state: State, parse: ParseStore, store: CheckStore, checked_type: U64) -> Result(Bool, __s0_Error) {
    let empty_bindings = try __s0_buffer_new(TypeBindingRec, d)
    let empty_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    let category = try interpreted_type_category(d, state, parse, store, empty_bindings, empty_ancestry, checked_type, 0, 0)
    return Ok(category.contains_scoped)
}

// M7.3 slice 3: true when every scoped capability reachable from
// checked_type is an immutable slice inside ordinary aggregate structure.
// Such a value can be constructed and returned, because lowering
// materializes its view parts into caller-result storage. Any Domain,
// DomainMark, raw pointer, or MutSlice leaf keeps the aggregate
// non-materializable, and an unresolved type parameter can never prove
// materializability at a lowering boundary.
fn checked_type_views_materializable(d: Domain, state: State, parse: ParseStore, store: CheckStore, checked_type: U64) -> Result(Bool, __s0_Error) {
    var bindings = try __s0_buffer_new(TypeBindingRec, d)
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: 0, ancestry: 0))
    var ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    var memo = try __s0_buffer_new(ExpansionMemoRec, d)
    var seen = try __s0_buffer_new(InterpStateRec, d)
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
            // Scoped capabilities cannot be materialized into caller
            // storage. An affine Table owner is not a scoped capability:
            // its storage already lives in the caller-result domain, so
            // aggregates carrying tables return as plain values.
            if checked.kind == 3 || checked.kind == 4 || checked.kind == 12 || checked.kind == 18 || checked.kind == 21 || checked.kind == 22 { return Ok(false) }
            if checked.kind == 6 { return Ok(false) }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 || checked.kind == 13 || checked.kind == 15 || checked.kind == 17 {
                var child: U64 = 0
                while child < checked.arg_count {
                    work = try __s0_buffer_append(InterpWorkRec, d, work, InterpWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), env: norm.env, ancestry: norm.ancestry))
                    child = child + 1
                }
            }
            if checked.kind == 7 {
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
    return Ok(true)
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
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, child, norm.env, norm.ancestry, boundary) { return check_type_detail_fail(d, store, 10, root_node, child) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: child, env: norm.env, ancestry: norm.ancestry, next: head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 9 || checked.kind == 12 || checked.kind == 15 {
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
                if !(try interpreted_map_key_ok(d, state, parse, store, bindings, ancestry, key, norm.env, norm.ancestry, boundary)) { return check_type_detail_fail(d, store, 12, root_node, key) }
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, value, norm.env, norm.ancestry, boundary) { return check_type_detail_fail(d, store, 13, root_node, value) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: value, env: norm.env, ancestry: norm.ancestry, next: head))
                let value_head = __s0_buffer_len(ValidationWorkRec, work)
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: key, env: norm.env, ancestry: norm.ancestry, next: value_head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 23 {
                let norm_key = normalize_interp(store, bindings, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), norm.env, norm.ancestry)
                if !ordered_key_supported(store, norm_key.checked_type, 0) { return check_type_detail_fail(d, store, 127, root_node, norm_key.checked_type) }
                let norm_value = normalize_interp(store, bindings, __s0_buffer_get(U64, store.type_args, checked.first_arg), norm.env, norm.ancestry)
                if !ordered_value_copyable(store, norm_value.checked_type, 0) { return check_type_detail_fail(d, store, 128, root_node, norm_value.checked_type) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg), env: norm.env, ancestry: norm.ancestry, next: head))
                let value_head = __s0_buffer_len(ValidationWorkRec, work)
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env: norm.env, ancestry: norm.ancestry, next: value_head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 24 {
                let norm_element = normalize_interp(store, bindings, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), norm.env, norm.ancestry)
                if !ordered_key_supported(store, norm_element.checked_type, 0) { return check_type_detail_fail(d, store, 127, root_node, norm_element.checked_type) }
                if !ordered_value_copyable(store, norm_element.checked_type, 0) { return check_type_detail_fail(d, store, 128, root_node, norm_element.checked_type) }
                work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env: norm.env, ancestry: norm.ancestry, next: head))
                head = __s0_buffer_len(ValidationWorkRec, work)
            }
            if checked.kind == 7 && declaration_available(boundary, checked.target) {
                if __s0_buffer_len(TraitConstraintRec, store.traits.constraints) != 0 {
                    var constraint_at: U64 = 0
                    while constraint_at < __s0_buffer_len(TraitConstraintRec, store.traits.constraints) {
                        let constraint = __s0_buffer_get(TraitConstraintRec, store.traits.constraints, constraint_at)
                        if constraint.owner == checked.target && !trait_constraint_application_satisfied(store, constraint, checked.target, checked) {
                            return check_fail(d, store, 111, root_node, 0, 0, 0)
                        }
                        constraint_at = constraint_at + 1
                    }
                }
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

fn node_word(state: State, node: SyntaxRec, word: __s0_String) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, node.source)
    return source_word(state, source, node.name_start, node.name_end, word)
}

fn reserved_symbol(state: State, node: SyntaxRec) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, node.source)
    if node.name_end - node.name_start >= 5 && source_word(state, source, node.name_start, node.name_start + 5, "__s0_") { return true }
    return node_word(state, node, "Bool") || node_word(state, node, "I8") || node_word(state, node, "I16") || node_word(state, node, "I32") || node_word(state, node, "I64") || node_word(state, node, "U8") || node_word(state, node, "U16") || node_word(state, node, "U32") || node_word(state, node, "U64") || node_word(state, node, "F32") || node_word(state, node, "F64") || node_word(state, node, "Unit") || node_word(state, node, "String") || node_word(state, node, "Bytes") || node_word(state, node, "Option") || node_word(state, node, "Result") || node_word(state, node, "Map") || node_word(state, node, "Ptr") || node_word(state, node, "Vec") || node_word(state, node, "MutSlice") || node_word(state, node, "Domain") || node_word(state, node, "DomainMark") || node_word(state, node, "__s0_String") || node_word(state, node, "__s0_Buffer") || node_word(state, node, "__s0_Error") || node_word(state, node, "len") || node_word(state, node, "range") || node_word(state, node, "__s0_alloc") || node_word(state, node, "__s0_domain_create") || node_word(state, node, "__s0_domain_mark") || node_word(state, node, "__s0_domain_reset") || node_word(state, node, "__s0_domain_destroy") || node_word(state, node, "__s0_map_create") || node_word(state, node, "__s0_buffer_new") || node_word(state, node, "__s0_buffer_len") || node_word(state, node, "__s0_buffer_append") || node_word(state, node, "__s0_buffer_get") || node_word(state, node, "__s0_buffer_set") || node_word(state, node, "__s0_buffer_slice") || node_word(state, node, "Get") || node_word(state, node, "Set") || node_word(state, node, "Remove") || node_word(state, node, "None") || node_word(state, node, "Some") || node_word(state, node, "Ok") || node_word(state, node, "Err") || node_word(state, node, "Eq") || node_word(state, node, "Hash") || node_word(state, node, "Iterator") || node_word(state, node, "IntoIterator") || node_word(state, node, "Cleanup") || node_word(state, node, "AsyncCleanup") || node_word(state, node, "Order") || node_word(state, node, "Display") || node_word(state, node, "Error") || node_word(state, node, "trait") || node_word(state, node, "where") || node_word(state, node, "Self")
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

// Fresh trait stores start empty; the initial compilation store and test
// harnesses use this helper. The impl index is built once after impl
// collection, so a fresh store carries no index entries.
fn empty_trait_store(d: Domain) -> Result(TraitStoreRec, __s0_Error) {
    let constraints = try __s0_buffer_new(TraitConstraintRec, d)
    let impls = try __s0_buffer_new(TraitImplRec, d)
    let index = try __s0_buffer_new(U64, d)
    let args = try __s0_buffer_new(U64, d)
    let receiver_index = try __s0_buffer_new(U64, d)
    return Ok(TraitStoreRec(constraints: constraints, impls: impls, impl_index: index, args: args, receiver_index: receiver_index))
}

fn check_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, related_source: U64, related_start: U64, related_end: U64) -> Result(CheckResult, __s0_Error) {
    let item = CheckDiagRec(kind: kind, source: node.source, start: node.name_start, end: node.name_end, related_source: related_source, related_start: related_start, related_end: related_end, detail_a: 0, detail_b: 0, detail_c: 0, detail_d: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics, traits: store.traits, closures: store.closures)))
}

fn check_detail_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> Result(CheckResult, __s0_Error) {
    let item = CheckDiagRec(kind: kind, source: node.source, start: node.name_start, end: node.name_end, related_source: 0, related_start: 0, related_end: 0, detail_a: detail_a, detail_b: detail_b, detail_c: detail_c, detail_d: detail_d)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics, traits: store.traits, closures: store.closures)))
}

fn check_decl_fail(d: Domain, state: State, parse: ParseStore, store: CheckStore, kind: U64, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.node - 1)
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0, detail_a: 0, detail_b: 0, detail_c: 0, detail_d: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics, traits: store.traits, closures: store.closures)))
}

fn check_token_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0, detail_a: 0, detail_b: 0, detail_c: 0, detail_d: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics, traits: store.traits, closures: store.closures)))
}

fn check_token_detail_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> Result(CheckResult, __s0_Error) {
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0, detail_a: detail_a, detail_b: detail_b, detail_c: detail_c, detail_d: detail_d)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics, traits: store.traits, closures: store.closures)))
}

fn check_type_detail_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, checked_type: U64) -> Result(CheckResult, __s0_Error) {
    let detail = diagnostic_type(store, checked_type)
    return check_detail_fail(d, store, kind, node, detail.kind, detail.target, 0, 0)
}

fn check_token_related_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, related: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let related_token = __s0_buffer_get(TokenRec, state.tokens, related.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: related_token.source, related_start: related_token.start, related_end: related_token.end, detail_a: node.kind, detail_b: related.kind, detail_c: 0, detail_d: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics, traits: store.traits, closures: store.closures)))
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

// Inherent functions remain ordinary static symbols after discovery. Their
// owning type is recovered from the parser root so the bootstrap model needs
// no parallel method table or runtime dispatch metadata.
fn inherent_owner_node(parse: ParseStore, function_node: U64) -> U64 {
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        let root_id = __s0_buffer_get(U64, parse.roots, root_at)
        let root = __s0_buffer_get(SyntaxRec, parse.nodes, root_id - 1)
        if root.kind == 53 {
            var trait_link = root.children
            while trait_link != 0 {
                let trait_item = __s0_buffer_get(SyntaxLinkRec, parse.links, trait_link - 1)
                if trait_item.node == function_node { return root_id }
                trait_link = trait_item.next
            }
        }
        if root.kind == 49 {
            var link = root.children
            var owner: U64 = 0
            while link != 0 {
                let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
                if item.next == 0 { owner = item.node }
                link = item.next
            }
            if owner != 0 {
                link = root.children
                while link != 0 {
                    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
                    if item.node == function_node && item.next != 0 { return owner }
                    link = item.next
                }
            }
        }
        root_at = root_at + 1
    }
    return 0
}

fn same_inherent_owner(state: State, parse: ParseStore, left: U64, right: U64) -> Bool {
    if left == 0 { return right == 0 }
    if right == 0 { return false }
    let a = __s0_buffer_get(SyntaxRec, parse.nodes, left - 1)
    let b = __s0_buffer_get(SyntaxRec, parse.nodes, right - 1)
    return same_name(state, a.source, a.start, a.end, b.source, b.start, b.end)
}

fn validate_inherent_owners(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        let root = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, root_at) - 1)
        if root.kind == 49 {
            var link = root.children
            while __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1).next != 0 {
                link = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1).next
            }
            let owner = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1).node - 1)
            if find_declared_type(state, parse, store, owner) == 0 { return check_token_fail(d, state, store, 4, owner) }
        }
        root_at = root_at + 1
    }
    return Ok(CheckGood(store))
}

// Builtin standard trait IDs. Order, Display, and Error are reserved names
// without declarations until their APIs are designed with the standard
// library; implementations of them are rejected as unknown traits.
fn builtin_trait_id(state: State, node: SyntaxRec) -> U64 {
    if node_word(state, node, "Eq") { return 1 }
    if node_word(state, node, "Hash") { return 2 }
    if node_word(state, node, "Iterator") { return 3 }
    if node_word(state, node, "IntoIterator") { return 4 }
    if node_word(state, node, "Cleanup") { return 5 }
    return 0
}

fn builtin_trait_arity(id: U64) -> U64 {
    if id == 3 { return 1 }
    if id == 4 { return 2 }
    return 0
}

// Trait references resolve against the builtin standard traits first, then
// declared trait symbols. Only where-clause and impl-head resolution calls
// this; expression checking never scans for traits.
fn trait_symbol_named(state: State, parse: ParseStore, store: CheckStore, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if symbol.kind == 50 && same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

// Traits carry one implicit trailing type parameter for `Self`. It is the
// parameter whose recorded node is the trait declaration itself, so it never
// collides with declared parameter nodes.
fn trait_self_param(store: CheckStore, owner: U64) -> U64 {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let p = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if p.owner == owner && p.node == symbol.node { return at + 1 }
        at = at + 1
    }
    return 0
}

fn append_trait_self_param(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckStore, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.node - 1)
    let params = try __s0_buffer_append(TypeParamRec, d, store.type_params, TypeParamRec(owner: owner, node: symbol.node, source: node.source, name_start: node.name_start, name_end: node.name_end))
    return Ok(CheckStore(symbols: store.symbols, type_params: params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures))
}

// `Self` resolves to the trait's implicit parameter inside a trait
// declaration and to the implementing type inside a trait implementation.
// Impl records are resolved before method signatures are checked, so the
// self type is always available here.
fn resolve_self_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node: SyntaxRec, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let declaration = instance_declaration(store, owner)
    if declaration != 0 {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, declaration - 1)
        if symbol.kind == 50 {
            let param = trait_self_param(store, declaration)
            if param != 0 { return Ok(CheckGood(try append_checked_type(d, store, owner, 6, node_id, param, 0, 0))) }
        }
        if symbol.kind == 12 && symbol.inherent_owner != 0 {
            let owner_node = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.inherent_owner - 1)
            if owner_node.kind == 53 {
                var at: U64 = 0
                while at < __s0_buffer_len(TraitImplRec, store.traits.impls) {
                    let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, at)
                    if rec.owner_node == symbol.inherent_owner && rec.self_type != 0 { return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, rec.self_type))) }
                    at = at + 1
                }
                // The trait implementation records are not built yet while
                // declarations are still resolving (a synthesized default
                // method's Self resolves before that pass); derive the
                // implementing type from the impl root's own type node.
                let self_node = trait_impl_self_node(parse, owner_node)
                if self_node != 0 { return resolve_type(d, state, parse, store, owner, self_node) }
            }
        }
    }
    return check_fail(d, store, 117, node, 0, 0, 0)
}

// Resolve one trait application: the builtin trait or declared trait symbol,
// its expected arity, and its argument types resolved in the owner's scope.
// Constraint arguments may stay abstract; impl-head arguments must be
// concrete and are verified by the caller.
fn resolve_trait_reference(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node: SyntaxRec) -> Result(TraitRefResult, __s0_Error) {
    let builtin = builtin_trait_id(state, node)
    let symbol = trait_symbol_named(state, parse, store, node)
    if builtin == 0 && symbol == 0 {
        let failed = try check_fail(d, store, 108, node, 0, 0, 0)
        return Ok(TraitRefBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    var arity: U64 = 0
    if builtin != 0 { arity = builtin_trait_arity(builtin) } else {
        let found = __s0_buffer_get(SymbolRec, store.symbols, symbol - 1)
        arity = found.type_arity
    }
    let supplied = type_arg_count(parse, node.children)
    if supplied != arity {
        let failed = try check_fail(d, store, 109, node, 0, 0, 0)
        return Ok(TraitRefBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    // Trait arguments resolve in source order through the same tail-first
    // child walk the signature checkers use.
    let walked = try resolve_trait_arg_links(d, state, parse, store, owner, node.children)
    let final = match walked {
        TraitRefGood(value) => value.store
        TraitRefBad(value) => value
    }
    if match walked {
        TraitRefGood(value) => false
        TraitRefBad(value) => true
    } { return Ok(TraitRefBad(final)) }
    let resolved_args = match walked {
        TraitRefGood(value) => value.reference
        TraitRefBad(value) => TraitRefRec(builtin: 0, symbol: 0, first_arg: 0, arg_count: 0)
    }
    return Ok(TraitRefGood(TraitRefStoreRec(store: final, reference: TraitRefRec(builtin: builtin, symbol: symbol, first_arg: resolved_args.first_arg, arg_count: resolved_args.arg_count))))
}

// Tail-first child resolution appends trait arguments in source order and
// keeps the store threaded through every resolution step.
fn resolve_trait_arg_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_at: U64) -> Result(TraitRefResult, __s0_Error) {
    if link_at == 0 { return Ok(TraitRefGood(TraitRefStoreRec(store: store, reference: TraitRefRec(builtin: 0, symbol: 0, first_arg: 0, arg_count: 0)))) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
    let earlier = try resolve_trait_arg_links(d, state, parse, store, owner, link.next)
    var current = match earlier {
        TraitRefGood(value) => value.store
        TraitRefBad(value) => value
    }
    if match earlier {
        TraitRefGood(value) => false
        TraitRefBad(value) => true
    } { return Ok(TraitRefBad(current)) }
    let prior = match earlier {
        TraitRefGood(value) => value.reference
        TraitRefBad(value) => TraitRefRec(builtin: 0, symbol: 0, first_arg: 0, arg_count: 0)
    }
    let resolved = try resolve_type(d, state, parse, current, owner, link.node)
    current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(TraitRefBad(current)) }
    let args = try __s0_buffer_append(U64, d, current.traits.args, checked_type_for_syntax(current, owner, link.node))
    let with_args = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: TraitStoreRec(constraints: current.traits.constraints, impls: current.traits.impls, impl_index: current.traits.impl_index, args: args, receiver_index: current.traits.receiver_index), closures: current.closures)
    if prior.arg_count == 0 {
        return Ok(TraitRefGood(TraitRefStoreRec(store: with_args, reference: TraitRefRec(builtin: 0, symbol: 0, first_arg: __s0_buffer_len(U64, args), arg_count: 1))))
    }
    return Ok(TraitRefGood(TraitRefStoreRec(store: with_args, reference: TraitRefRec(builtin: 0, symbol: 0, first_arg: prior.first_arg, arg_count: prior.arg_count + 1))))
}

fn collect_symbols(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    let imports = try validate_import_bindings(d, state, parse, initial)
    if match imports {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(imports) }
    var store = initial
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        var node_id = __s0_buffer_get(U64, parse.roots, root_at)
        var node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
        if node.kind == 40 || node.kind == 41 || node.kind == 42 || node.kind == 49 || node.kind == 53 {
            root_at = root_at + 1
        } else {
        if node.kind == 45 {
            let declaration = __s0_buffer_get(SyntaxLinkRec, parse.links, node.children - 1)
            node_id = declaration.node
            node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
        }
        var module_source: U64 = 0
        var public = false
        var scan: U64 = 0
        while scan < __s0_buffer_len(U64, parse.roots) {
            let root_id = __s0_buffer_get(U64, parse.roots, scan)
            let root = __s0_buffer_get(SyntaxRec, parse.nodes, root_id - 1)
            if root.source == node.source && root.kind == 40 { module_source = node.source + 1 }
            if root.source == node.source && root.kind == 45 {
                let wrapped = __s0_buffer_get(SyntaxLinkRec, parse.links, root.children - 1)
                if wrapped.node == node_id { public = true }
            }
            if root.source == node.source && (root.kind == 41 || root.kind == 42) {
                var binding_at: U64 = 0
                while binding_at < import_binding_count(parse, root) {
                    let imported_node = import_binding_at(state, parse, root, binding_at)
                    if same_name(state, node.source, node.name_start, node.name_end, imported_node.source, imported_node.name_start, imported_node.name_end) {
                        return check_token_related_fail(d, state, store, 1, node, imported_node)
                    }
                    binding_at = binding_at + 1
                }
            }
            scan = scan + 1
        }
        var previous: U64 = 0
        let inherent_owner = inherent_owner_node(parse, node_id)
        while previous < __s0_buffer_len(SymbolRec, store.symbols) {
            let first = __s0_buffer_get(SymbolRec, store.symbols, previous)
            let first_owner = first.inherent_owner
            if same_name(state, node.source, node.name_start, node.name_end, first.source, first.name_start, first.name_end) && same_inherent_owner(state, parse, inherent_owner, first_owner) && (module_source == 0 || first.module_source == module_source) {
                let related = __s0_buffer_get(SyntaxRec, parse.nodes, first.node - 1)
                return check_token_related_fail(d, state, store, 1, node, related)
            }
            previous = previous + 1
        }
        if reserved_symbol(state, node) { return check_fail(d, store, 2, node, 0, 0, 0) }
        let symbol_id = __s0_buffer_len(SymbolRec, store.symbols) + 1
        var declaration: U64 = 0
        if node.kind == 12 && symbol_arity(parse, node) == 0 { declaration = symbol_id }
        let symbol = SymbolRec(kind: node.kind, node: node_id, source: node.source, name_start: node.name_start, name_end: node.name_end, type_arity: symbol_arity(parse, node), declaration: declaration, first_instance_arg: 0, instance_arg_count: 0, discovery_parent: 0, inherent_owner: inherent_owner, module_source: module_source, public: public)
        let symbols = try __s0_buffer_append(SymbolRec, d, store.symbols, symbol)
        store = CheckStore(symbols: symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
        root_at = root_at + 1
        }
    }
    let defaults = try synthesize_default_methods(d, state, parse, store)
    if match defaults {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(defaults) }
    store = match defaults {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    let regrouped = try regroup_impl_method_symbols(d, state, parse, store)
    if match regrouped {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(regrouped) }
    store = match regrouped {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    let inherent = try validate_inherent_owners(d, state, parse, store)
    if match inherent {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(inherent) }
    return validate_import_targets(d, state, parse, store)
}

// Default-method dispatch: every trait requirement that carries a default
// body is materialized as an ordinary impl method for each implementation
// that does not override it, so the requirement's body is checked, lowered,
// and dispatched exactly like a written method. Synthesis is parse-driven
// and runs inside symbol collection, before any declaration or body
// checking, so the ordinary passes treat the materialized method as if it
// were written in the impl.
fn synthesize_default_method_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, impl_root: U64, trait_root: U64, link_at: U64) -> Result(CheckResult, __s0_Error) {
    if link_at == 0 { return Ok(CheckGood(store)) }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
    let requirement = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    var current = store
    if requirement.kind == 51 {
        var has_block = false
        var body_at = requirement.children
        while body_at != 0 {
            let body_item = __s0_buffer_get(SyntaxLinkRec, parse.links, body_at - 1)
            if __s0_buffer_get(SyntaxRec, parse.nodes, body_item.node - 1).kind == 14 { has_block = true }
            body_at = body_item.next
        }
        if has_block {
            var overridden = false
            var symbol_at: U64 = 0
            while symbol_at < __s0_buffer_len(SymbolRec, current.symbols) {
                let symbol = __s0_buffer_get(SymbolRec, current.symbols, symbol_at)
                if symbol.inherent_owner == impl_root && same_name(state, requirement.source, requirement.name_start, requirement.name_end, symbol.source, symbol.name_start, symbol.name_end) { overridden = true }
                symbol_at = symbol_at + 1
            }
            if !overridden {
                let symbol_id = __s0_buffer_len(SymbolRec, current.symbols) + 1
                var declaration: U64 = 0
                if symbol_arity(parse, requirement) == 0 { declaration = symbol_id }
                let symbols = try __s0_buffer_append(SymbolRec, d, current.symbols, SymbolRec(kind: 12, node: item.node, source: requirement.source, name_start: requirement.name_start, name_end: requirement.name_end, type_arity: symbol_arity(parse, requirement), declaration: declaration, first_instance_arg: 0, instance_arg_count: 0, discovery_parent: 0, inherent_owner: impl_root, module_source: 0, public: false))
                current = CheckStore(symbols: symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
            }
        }
    }
    return synthesize_default_method_links(d, state, parse, current, impl_root, trait_root, item.next)
}

// After synthesis the materialized default methods sit at the tail of the
// symbol table, but an implementation's method range must be contiguous for
// dispatch. Rebuild the symbol table once, moving each impl's synthesized
// methods directly behind that impl's written methods; symbol identifiers
// are not referenced by anything yet, and only the self-referencing
// declaration field needs renumbering. A synthesized record is a kind-12
// symbol whose parse node is the trait requirement (kind 51).
fn regroup_impl_method_symbols(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    if __s0_buffer_len(SymbolRec, store.symbols) == 0 { return Ok(CheckGood(store)) }
    var reordered = try __s0_buffer_new(SymbolRec, d)
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let item = __s0_buffer_get(SymbolRec, store.symbols, at)
        // Synthesized records whose impl has written methods were already
        // inserted behind them; skip those in the straight copy. An impl
        // with no written methods keeps its synthesized records here.
        var moved_synth = false
        if item.inherent_owner != 0 && __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1).kind == 51 {
            var earlier_at: U64 = 0
            while earlier_at < at {
                let earlier = __s0_buffer_get(SymbolRec, store.symbols, earlier_at)
                if earlier.inherent_owner == item.inherent_owner && __s0_buffer_get(SyntaxRec, parse.nodes, earlier.node - 1).kind != 51 { moved_synth = true }
                earlier_at = earlier_at + 1
            }
        }
        if moved_synth {
            at = at + 1
        } else {
        if item.inherent_owner != 0 && (at + 1 >= __s0_buffer_len(SymbolRec, store.symbols) || __s0_buffer_get(SymbolRec, store.symbols, at + 1).inherent_owner != item.inherent_owner) {
            var moved_at = __s0_buffer_len(SymbolRec, store.symbols) - 1
            while moved_at > at {
                let moved = __s0_buffer_get(SymbolRec, store.symbols, moved_at)
                if moved.inherent_owner == item.inherent_owner && __s0_buffer_get(SyntaxRec, parse.nodes, moved.node - 1).kind == 51 {
                    var moved_record = moved
                    if moved_record.declaration != 0 { moved_record = SymbolRec(kind: moved_record.kind, node: moved_record.node, source: moved_record.source, name_start: moved_record.name_start, name_end: moved_record.name_end, type_arity: moved_record.type_arity, declaration: __s0_buffer_len(SymbolRec, reordered) + 1, first_instance_arg: moved_record.first_instance_arg, instance_arg_count: moved_record.instance_arg_count, discovery_parent: moved_record.discovery_parent, inherent_owner: moved_record.inherent_owner, module_source: moved_record.module_source, public: moved_record.public) }
                    reordered = try __s0_buffer_append(SymbolRec, d, reordered, moved_record)
                }
                moved_at = moved_at - 1
            }
        }
        var record = item
        if record.declaration == at + 1 { record = SymbolRec(kind: record.kind, node: record.node, source: record.source, name_start: record.name_start, name_end: record.name_end, type_arity: record.type_arity, declaration: __s0_buffer_len(SymbolRec, reordered) + 1, first_instance_arg: record.first_instance_arg, instance_arg_count: record.instance_arg_count, discovery_parent: record.discovery_parent, inherent_owner: record.inherent_owner, module_source: record.module_source, public: record.public) }
        reordered = try __s0_buffer_append(SymbolRec, d, reordered, record)
        at = at + 1
        }
    }
    return Ok(CheckGood(CheckStore(symbols: reordered, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)))
}

// Materialize the default bodies of one trait implementation. The parser
// links the trait application as the impl root's chain tail; generic traits
// wait for instance checking and synthesize nothing.
fn synthesize_default_methods(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    return synthesize_default_methods_from(d, state, parse, store, 0)
}

// Root recursion over the impl roots: the store threads through every step
// and must not cross a loop backedge. The parser links the trait application
// as the impl root's chain tail. Only arity-zero traits synthesize defaults:
// a synthesized method resolves in its own scope, where a generic trait's
// parameters are not visible.
fn synthesize_default_methods_from(d: Domain, state: State, parse: ParseStore, store: CheckStore, root_at: U64) -> Result(CheckResult, __s0_Error) {
    if root_at >= __s0_buffer_len(U64, parse.roots) { return Ok(CheckGood(store)) }
    var current = store
    let root_id = __s0_buffer_get(U64, parse.roots, root_at)
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, root_id - 1)
    if root.kind == 53 {
        var link_at = root.children
        var tail: U64 = 0
        while link_at != 0 {
            let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
            if item.next == 0 { tail = item.node }
            link_at = item.next
        }
        if tail != 0 {
            let application = __s0_buffer_get(SyntaxRec, parse.nodes, tail - 1)
            let trait_symbol = symbol_named(state, parse, current, application)
            if trait_symbol != 0 {
                let trait_decl = __s0_buffer_get(SymbolRec, current.symbols, trait_symbol - 1)
                if trait_decl.kind == 50 && trait_decl.type_arity == 0 {
                    let stepped = try synthesize_default_method_links(d, state, parse, current, root_id, trait_symbol, trait_root_children(parse, trait_decl))
                    if match stepped {
                        CheckGood(value) => false
                        CheckBad(value) => true
                    } { return Ok(stepped) }
                    current = match stepped {
                        CheckGood(value) => value
                        CheckBad(value) => value
                    }
                }
            }
        }
    }
    return synthesize_default_methods_from(d, state, parse, current, root_at + 1)
}

fn trait_root_children(parse: ParseStore, trait_decl: SymbolRec) -> U64 {
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, trait_decl.node - 1)
    return root.children
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
    return Ok(CheckGood(CheckStore(symbols: store.symbols, type_params: params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)))
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

// A `mut` non-self parameter of copyable category is legal only in the
// iterator-cursor shape: its type is exactly a type parameter of the owner,
// and a where-constraint on that parameter names a trait with at least one
// `mut self` requirement. The where syntax is read directly because
// parameter types check before the owner's constraints are recorded; the
// constraint-recording pass still validates the clause itself afterwards.
fn mut_cursor_param_ok(state: State, parse: ParseStore, store: CheckStore, owner: U64, type_node: SyntaxRec) -> Bool {
    if type_node.kind != 4 { return false }
    if find_type_param(state, store, owner, type_node) == 0 { return false }
    let owner_symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, owner_symbol.node - 1)
    var clause_at = root.children
    while clause_at != 0 {
        let clause_link = __s0_buffer_get(SyntaxLinkRec, parse.links, clause_at - 1)
        let clause = __s0_buffer_get(SyntaxRec, parse.nodes, clause_link.node - 1)
        if clause.kind == 52 {
            var constraint_at = clause.children
            while constraint_at != 0 {
                let constraint_link = __s0_buffer_get(SyntaxLinkRec, parse.links, constraint_at - 1)
                let constraint = __s0_buffer_get(SyntaxRec, parse.nodes, constraint_link.node - 1)
                if constraint.kind == 55 && same_name(state, constraint.source, constraint.name_start, constraint.name_end, type_node.source, type_node.name_start, type_node.name_end) {
                    if mut_cursor_trait_named(state, parse, store, constraint.children) { return true }
                }
                constraint_at = constraint_link.next
            }
        }
        clause_at = clause_link.next
    }
    return false
}

// One constraint's trait applications: the builtin Iterator is the mut-self
// builtin; a user trait qualifies when any requirement declares `mut self`.
fn mut_cursor_trait_named(state: State, parse: ParseStore, store: CheckStore, trait_at: U64) -> Bool {
    var at = trait_at
    while at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, at - 1)
        let trait_node = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if trait_node.kind == 4 || trait_node.kind == 6 {
            if builtin_trait_id(state, trait_node) == 3 { return true }
            let symbol_id = trait_symbol_named(state, parse, store, trait_node)
            if symbol_id != 0 {
                let trait_symbol = __s0_buffer_get(SymbolRec, store.symbols, symbol_id - 1)
                let trait_root = __s0_buffer_get(SyntaxRec, parse.nodes, trait_symbol.node - 1)
                var requirement_at = trait_root.children
                while requirement_at != 0 {
                    let requirement_link = __s0_buffer_get(SyntaxLinkRec, parse.links, requirement_at - 1)
                    let requirement = __s0_buffer_get(SyntaxRec, parse.nodes, requirement_link.node - 1)
                    if requirement.kind == 51 {
                        var child_at = requirement.children
                        while child_at != 0 {
                            let child_link = __s0_buffer_get(SyntaxLinkRec, parse.links, child_at - 1)
                            let child = __s0_buffer_get(SyntaxRec, parse.nodes, child_link.node - 1)
                            if child.kind == 47 && node_word(state, child, "self") { return true }
                            child_at = child_link.next
                        }
                    }
                    requirement_at = requirement_link.next
                }
            }
        }
        at = item.next
    }
    return false
}

fn find_declared_type(state: State, parse: ParseStore, store: CheckStore, node: SyntaxRec) -> U64 {
    let resolved = symbol_named(state, parse, store, node)
    if resolved != 0 {
        let found = __s0_buffer_get(SymbolRec, store.symbols, resolved - 1)
        if found.kind == 2 || found.kind == 3 { return resolved }
    }
    return 0
}

fn module_source_named(state: State, parse: ParseStore, source: U64, start: U64, end: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(U64, parse.roots) {
        let root = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, at) - 1)
        if root.kind == 40 && same_name(state, source, start, end, root.source, root.name_start, root.name_end) { return root.source + 1 }
        at = at + 1
    }
    return 0
}

fn exported_symbol_named(state: State, parse: ParseStore, store: CheckStore, module_source: U64, source: U64, start: U64, end: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if symbol.module_source == module_source && symbol.public && same_name(state, source, start, end, symbol.source, symbol.name_start, symbol.name_end) { return at + 1 }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(U64, parse.roots) {
        let root = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, at) - 1)
        if root.kind == 42 && root.source + 1 == module_source {
            var link = root.children
            while link != 0 {
                let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
                let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
                if child.kind == 43 && same_name(state, source, start, end, child.source, child.name_start, child.name_end) {
                    let target = module_source_named(state, parse, root.source, root.name_start, root.name_end)
                    if target != 0 { return exported_symbol_named(state, parse, store, target, source, start, end) }
                }
                link = item.next
            }
        }
        at = at + 1
    }
    return 0
}

fn validate_import_targets(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var at: U64 = 0
    while at < __s0_buffer_len(U64, parse.roots) {
        let root = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, at) - 1)
        if root.kind == 41 || root.kind == 42 {
            if root.kind == 42 && !import_has_selected(parse, root) { return check_fail(d, store, 87, root, 0, 0, 0) }
            let target = module_source_named(state, parse, root.source, root.name_start, root.name_end)
            if target == 0 { return check_fail(d, store, 40, root, 0, 0, 0) }
            if import_has_selected(parse, root) {
                var binding_at: U64 = 0
                while binding_at < import_binding_count(parse, root) {
                    let binding = import_binding_at(state, parse, root, binding_at)
                    if exported_symbol_named(state, parse, store, target, binding.source, binding.name_start, binding.name_end) == 0 { return check_fail(d, store, 40, binding, 0, 0, 0) }
                    binding_at = binding_at + 1
                }
            }
        }
        at = at + 1
    }
    return Ok(CheckGood(store))
}

fn builtin_type_kind(state: State, node: SyntaxRec) -> U64 {
    if node_word(state, node, "String") { return 2 }
    if node_word(state, node, "Bytes") { return 14 }
    if node_word(state, node, "__s0_String") { return 16 }
    if node_word(state, node, "Domain") { return 3 }
    if node_word(state, node, "DomainMark") { return 4 }
    if node_word(state, node, "__s0_Error") { return 5 }
    if node_word(state, node, "Bool") || node_word(state, node, "I8") || node_word(state, node, "I16") || node_word(state, node, "I32") || node_word(state, node, "I64") || node_word(state, node, "U8") || node_word(state, node, "U16") || node_word(state, node, "U32") || node_word(state, node, "U64") || node_word(state, node, "F32") || node_word(state, node, "F64") || node_word(state, node, "Unit") { return 1 }
    return 0
}

// dotted_name_split returns the offset of the first '.' inside a syntax
// node's name range, or zero when the name is a single identifier. Offsets
// are relative to the source text start, matching name_start/name_end.
fn dotted_name_split(state: State, node: SyntaxRec) -> U64 {
    if node.name_start >= node.name_end { return 0 }
    let source = __s0_buffer_get(SourceRec, state.sources, node.source)
    var at: U64 = node.name_start
    while at < node.name_end {
        if text_byte(state, source, at) == 46 { return at }
        at = at + 1
    }
    return 0
}

// node_word_between compares one byte sub-range of a syntax node's name with
// a literal word.
fn node_word_between(state: State, node: SyntaxRec, start: U64, end: U64, word: __s0_String) -> Bool {
    if end <= start || end > node.name_end { return false }
    let source = __s0_buffer_get(SourceRec, state.sources, node.source)
    return source_word(state, source, start, end, word)
}

// resolve_table_id_type resolves the `T.Id` checked type from the dotted type
// name node and its narrowed prefix. The element resolves exactly like a bare
// type name: a type parameter (substituted when its instance is concrete), a
// builtin value type, or an arity-zero declared type.
fn resolve_table_id_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node: SyntaxRec, node_id: U64, prefix: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let declaration = instance_declaration(store, owner)
    let param = find_type_param(state, store, declaration, prefix)
    var current = store
    var element: U64 = 0
    // Intermediate element records carry no syntax annotation; only the
    // final identity application owns the dotted name node, and a deduplicated
    // append must not be identified by the buffer length.
    if param != 0 {
        let concrete = instance_type_arg(store, owner, param)
        if concrete != 0 { element = concrete } else {
            element = canonical_type_id(current, 6, param, 0, 0)
            if element == 0 {
                let appended = try append_checked_type(d, current, owner, 6, 0, param, 0, 0)
                current = appended
                element = __s0_buffer_len(CheckedTypeRec, appended.types)
            }
        }
    }
    if element == 0 {
        let builtin = builtin_type_kind(state, prefix)
        if builtin == 1 {
            element = canonical_type_id(current, 1, primitive_type_target(state, prefix), 0, 0)
            if element == 0 {
                let appended = try append_checked_type(d, current, owner, 1, 0, primitive_type_target(state, prefix), 0, 0)
                current = appended
                element = __s0_buffer_len(CheckedTypeRec, appended.types)
            }
        } else {
            if builtin == 2 || builtin == 14 {
                element = canonical_type_id(current, builtin, 0, 0, 0)
                if element == 0 {
                    let appended = try append_checked_type(d, current, owner, builtin, 0, 0, 0, 0)
                    current = appended
                    element = __s0_buffer_len(CheckedTypeRec, appended.types)
                }
            }
        }
    }
    if element == 0 {
        let symbol = find_declared_type(state, parse, current, prefix)
        if symbol == 0 { return check_fail(d, current, 4, node, 0, 0, 0) }
        if __s0_buffer_get(SymbolRec, current.symbols, symbol - 1).type_arity != 0 { return check_fail(d, current, 5, node, 0, 0, 0) }
        let boundary = declaration_boundary(current, owner)
        element = canonical_type_id(current, 7, symbol, 0, 0)
        if element == 0 {
            let appended = try append_checked_type(d, current, owner, 7, 0, symbol, 0, 0)
            current = appended
            element = __s0_buffer_len(CheckedTypeRec, appended.types)
        }
        let validated = try validate_concrete_type(d, state, parse, current, element, 0, syntax_diag_node(state, parse, node_id), boundary)
        if check_result_bad(validated) { return Ok(validated) }
        current = check_result_store(validated)
    }
    let made = try canonical_application(d, current, owner, 20, element, 0, 1)
    let annotated = try annotate_checked_type(d, made.store, owner, node_id, made.checked_type)
    return Ok(CheckGood(annotated))
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
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures))
}

fn append_checked_type(d: Domain, store: CheckStore, owner: U64, kind: U64, syntax: U64, target: U64, first_arg: U64, arg_count: U64) -> Result(CheckStore, __s0_Error) {
    let existing = canonical_type_id(store, kind, target, first_arg, arg_count)
    if existing != 0 { return annotate_checked_type(d, store, owner, syntax, existing) }
    let types = try __s0_buffer_append(CheckedTypeRec, d, store.types, CheckedTypeRec(kind: kind, syntax: 0, target: target, first_arg: first_arg, arg_count: arg_count))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
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
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
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
    // A source slice parameter is a non-retaining borrow pattern. Infer its
    // element from any sequence representation without making those concrete
    // types equal elsewhere in the checker.
    if expected.kind == 8 && expected.arg_count == 1 && (actual.kind == 15 || actual.kind == 17 || actual.kind == 18) && actual.arg_count == 1 {
        return unify_types(d, store, __s0_buffer_get(U64, store.type_args, expected.first_arg - 1), __s0_buffer_get(U64, store.type_args, actual.first_arg - 1), bindings)
    }
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
        next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    }
    return append_instance_args(d, next, declaration, bindings, param_at + 1)
}

fn append_instance_role_uses(d: Domain, store: CheckStore, declaration: U64, instance: U64, bindings: __s0_Buffer(InferenceBindingRec), declaration_role: U64, instance_role: U64, ordinal: U64, indexed: Bool) -> Result(CheckStore, __s0_Error) {
    if ordinal == use_count(store, declaration, declaration_role) { return Ok(store) }
    let use_id = use_by_ordinal(store, declaration, declaration_role, ordinal)
    let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
    let concrete = try substitute_type(d, store, bindings, use.checked_type)
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, concrete.store.uses, DeclTypeUseRec(owner: instance, role: instance_role, ordinal: use.ordinal, node: use.node, source: use.source, name_start: use.name_start, name_end: use.name_end, syntax: use.syntax, checked_type: concrete.checked_type))
    var use_order = concrete.store.indexes.use_order
    if indexed { use_order = try __s0_buffer_append(U64, d, use_order, __s0_buffer_len(DeclTypeUseRec, uses)) }
    let indexes = CheckerIndexes(uses: concrete.store.indexes.uses, use_order: use_order, complete: concrete.store.indexes.complete)
    let next = CheckStore(symbols: concrete.store.symbols, type_params: concrete.store.type_params, types: concrete.store.types, type_args: concrete.store.type_args, type_annotations: concrete.store.type_annotations, uses: uses, indexes: indexes, locals: concrete.store.locals, environments: concrete.store.environments, expressions: concrete.store.expressions, call_annotations: concrete.store.call_annotations, expression_children: concrete.store.expression_children, returns: concrete.store.returns, control: concrete.store.control, diagnostics: concrete.store.diagnostics, traits: concrete.store.traits, closures: concrete.store.closures)
    return append_instance_role_uses(d, next, declaration, instance, bindings, declaration_role, instance_role, ordinal + 1, indexed)
}

fn append_instance_use_index_slots(d: Domain, store: CheckStore, role: U64, parameter_first: U64, parameter_count: U64, result_first: U64, result_count: U64) -> Result(CheckStore, __s0_Error) {
    if role > 8 { return Ok(store) }
    var first: U64 = 0
    var count: U64 = 0
    if role == 7 { first = parameter_first
        count = parameter_count }
    if role == 8 { first = result_first
        count = result_count }
    let use_indexes = try __s0_buffer_append(CheckerUseIndexRec, d, store.indexes.uses, CheckerUseIndexRec(first: first, count: count))
    let indexes = CheckerIndexes(uses: use_indexes, use_order: store.indexes.use_order, complete: store.indexes.complete)
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    return append_instance_use_index_slots(d, next, role + 1, parameter_first, parameter_count, result_first, result_count)
}

fn append_instance_uses(d: Domain, store: CheckStore, declaration: U64, instance: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CheckStore, __s0_Error) {
    let indexed = __s0_buffer_len(CheckerUseIndexRec, store.indexes.uses) == (instance - 1) * 8
    let parameter_count = use_count(store, declaration, 5)
    let result_count = use_count(store, declaration, 6)
    let first = __s0_buffer_len(U64, store.indexes.use_order) + 1
    let parameters = try append_instance_role_uses(d, store, declaration, instance, bindings, 5, 7, 0, indexed)
    let results = try append_instance_role_uses(d, parameters, declaration, instance, bindings, 6, 8, 0, indexed)
    if !indexed { return Ok(results) }
    var parameter_first: U64 = 0
    var result_first: U64 = 0
    if parameter_count != 0 { parameter_first = first }
    if result_count != 0 { result_first = first + parameter_count }
    return append_instance_use_index_slots(d, results, 1, parameter_first, parameter_count, result_first, result_count)
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
    // Every declared constraint must hold for the concrete arguments. The
    // lookup only reads the once-built impl index.
    if __s0_buffer_len(TraitConstraintRec, store.traits.constraints) != 0 {
        var constraint_at: U64 = 0
        while constraint_at < __s0_buffer_len(TraitConstraintRec, store.traits.constraints) {
            let constraint = __s0_buffer_get(TraitConstraintRec, store.traits.constraints, constraint_at)
            if constraint.owner == declaration && !trait_constraint_satisfied(store, constraint, bindings) {
                let syntax = __s0_buffer_get(SyntaxRec, parse.nodes, constraint.syntax - 1)
                let failed = try check_token_related_fail(d, state, store, 111, site, syntax)
                return Ok(InstanceBad(match failed {
                    CheckGood(value) => value
                    CheckBad(value) => value
                }))
            }
            constraint_at = constraint_at + 1
        }
    }
    let first = __s0_buffer_len(U64, store.type_args) + 1
    let with_args = try append_instance_args(d, store, declaration, bindings, 0)
    let instance = __s0_buffer_len(SymbolRec, with_args.symbols) + 1
    let symbols = try __s0_buffer_append(SymbolRec, d, with_args.symbols, SymbolRec(kind: 13, node: declared.node, source: declared.source, name_start: declared.name_start, name_end: declared.name_end, type_arity: 0, declaration: declaration, first_instance_arg: first, instance_arg_count: declared.type_arity, discovery_parent: parent, inherent_owner: declared.inherent_owner, module_source: declared.module_source, public: declared.public))
    let registered = CheckStore(symbols: symbols, type_params: with_args.type_params, types: with_args.types, type_args: with_args.type_args, type_annotations: with_args.type_annotations, uses: with_args.uses, indexes: with_args.indexes, locals: with_args.locals, environments: with_args.environments, expressions: with_args.expressions, call_annotations: with_args.call_annotations, expression_children: with_args.expression_children, returns: with_args.returns, control: with_args.control, diagnostics: with_args.diagnostics, traits: with_args.traits, closures: with_args.closures)
    let signed = try append_instance_uses(d, registered, declaration, instance, bindings)
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

// The owner is required: a generic declaration's explicit syntax can be
// replayed under several concrete instances, so the same syntax ID may carry a
// different checked type per owner.
fn checked_type_for_syntax(store: CheckStore, owner: U64, syntax: U64) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeAnnotationRec, store.type_annotations) {
        let annotation = __s0_buffer_get(CheckedTypeAnnotationRec, store.type_annotations, at)
        if annotation.owner == owner && annotation.syntax == syntax { return annotation.checked_type }
        at = at + 1
    }
    return 0
}

// Append only the current node's direct children, in source order. Since all
// recursive resolution is already complete, this range remains contiguous.
fn record_arg_links(d: Domain, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(CheckStore, __s0_Error) {
    if link_id == 0 { return Ok(store) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let current = try record_arg_links(d, parse, store, owner, link.next)
    let checked = checked_type_for_syntax(current, owner, link.node)
    let args = try __s0_buffer_append(U64, d, current.type_args, checked)
    return Ok(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures))
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

fn canonical_type_for_links(parse: ParseStore, store: CheckStore, owner: U64, kind: U64, target: U64, link_id: U64) -> U64 {
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
                if __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal) != checked_type_for_syntax(store, owner, link.node) { same = false }
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
    if node.kind == 57 {
        // Function type: children are the parameter types followed by the
        // result type. The checked application carries those plus a trailing
        // environment argument (unit for source-written function types).
        let resolved = try resolve_arg_links(d, state, parse, store, owner, node.children)
        var current = match resolved {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        if match resolved {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(resolved) }
        if node.children == 0 { return check_fail(d, current, 5, node, 0, 0, 0) }
        let unit = try canonical_leaf(d, current, 1, 12)
        current = unit.store
        // The arguments are the declared parameter types in source order
        // followed by the result type and the unit environment. The child
        // chain is linked in reverse, so it is collected and flipped.
        var chain = try __s0_buffer_new(U64, d)
        var child_link = node.children
        while child_link != 0 {
            let link = __s0_buffer_get(SyntaxLinkRec, parse.links, child_link - 1)
            let child_type = checked_type_for_syntax(current, owner, link.node)
            if child_type == 0 { return check_fail(d, current, 4, __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1), 0, 0, 0) }
            chain = try __s0_buffer_append(U64, d, chain, child_type)
            child_link = link.next
        }
        var args = try __s0_buffer_new(U64, d)
        var chain_at = __s0_buffer_len(U64, chain)
        while chain_at > 0 {
            args = try __s0_buffer_append(U64, d, args, __s0_buffer_get(U64, chain, chain_at - 1))
            chain_at = chain_at - 1
        }
        args = try __s0_buffer_append(U64, d, args, unit.checked_type)
        let existing = canonical_type_for_children(current, 25, 0, args)
        if existing != 0 { return Ok(CheckGood(try annotate_checked_type(d, current, owner, node_id, existing))) }
        let start = __s0_buffer_len(U64, current.type_args) + 1
        let recorded = try append_substituted_children(d, current, args, 0)
        let count = __s0_buffer_len(U64, args)
        let appended = try append_checked_type(d, recorded, owner, 25, node_id, 0, start, count)
        return Ok(CheckGood(appended))
    }
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
        let existing = canonical_type_for_links(parse, current, owner, 8, 0, node.children)
        var appended = current
        if existing != 0 { appended = try annotate_checked_type(d, current, owner, node_id, existing) } else {
            let start = __s0_buffer_len(U64, current.type_args)
            let recorded = try record_arg_links(d, parse, current, owner, node.children)
            appended = try append_checked_type(d, recorded, owner, 8, node_id, 0, start + 1, 1)
        }
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
        let checked_id = checked_type_for_syntax(appended, owner, node_id)
        let canonical = __s0_buffer_get(CheckedTypeRec, appended.types, checked_id - 1)
        let child = __s0_buffer_get(U64, appended.type_args, canonical.first_arg - 1)
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, child, 0, 0, boundary) { return check_type_detail_fail(d, appended, 10, syntax_diag_node(state, parse, node_id), child) }
        return Ok(CheckGood(appended))
    }
    if node.kind == 56 { return resolve_self_type(d, state, parse, store, owner, node, node_id) }
    if node.kind == 4 {
        let builtin = builtin_type_kind(state, node)
        if builtin == 1 { return Ok(CheckGood(try append_checked_type(d, store, owner, 1, node_id, primitive_type_target(state, node), 0, 0))) }
        if builtin == 2 || builtin == 14 { return Ok(CheckGood(try append_checked_type(d, store, owner, builtin, node_id, 0, 0, 0))) }
        if builtin != 0 && !check_bootstrap_private() { return check_fail(d, store, 105, node, 0, 0, 0) }
        if builtin != 0 { return Ok(CheckGood(try append_checked_type(d, store, owner, builtin, node_id, 0, 0, 0))) }
        // `T.Id` names the copyable generational identity of table element T.
        // Only the dotted bare-name form with an Id suffix and a prefix that
        // resolves as a type is intercepted; module-qualified names such as
        // alias.Type keep their original resolution.
        let dot_at = dotted_name_split(state, node)
        if dot_at != 0 && node_word_between(state, node, dot_at + 1, node.name_end, "Id") {
            let prefix = SyntaxRec(kind: node.kind, token: node.token, source: node.source, start: node.start, end: node.end, name_start: node.name_start, name_end: dot_at, children: 0)
            let prefix_declaration = instance_declaration(store, owner)
            let prefix_param = find_type_param(state, store, prefix_declaration, prefix)
            let prefix_builtin = builtin_type_kind(state, prefix)
            let prefix_symbol = find_declared_type(state, parse, store, prefix)
            if prefix_param != 0 || prefix_builtin != 0 || prefix_symbol != 0 {
                return resolve_table_id_type(d, state, parse, store, owner, node, node_id, prefix)
            }
        }
        let declaration = instance_declaration(store, owner)
        let param = find_type_param(state, store, declaration, node)
        if param != 0 {
            let concrete = instance_type_arg(store, owner, param)
            if concrete != 0 { return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, concrete))) }
            return Ok(CheckGood(try append_checked_type(d, store, owner, 6, node_id, param, 0, 0)))
        }
        let symbol = find_declared_type(state, parse, store, node)
        if symbol == 0 {
            if trait_symbol_named(state, parse, store, node) != 0 { return check_fail(d, store, 114, node, 0, 0, 0) }
            return check_fail(d, store, 4, node, 0, 0, 0)
        }
        if __s0_buffer_get(SymbolRec, store.symbols, symbol - 1).type_arity != 0 { return check_fail(d, store, 5, node, 0, 0, 0) }
        let appended = try append_checked_type(d, store, owner, 7, node_id, symbol, 0, 0)
        let checked_id = checked_type_for_syntax(appended, owner, node_id)
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, syntax_diag_node(state, parse, node_id), boundary)
    }
    if node.kind == 6 && node_word(state, node, "Array") {
        if type_arg_count(parse, node.children) != 2 { return check_fail(d, store, 5, node, 0, 0, 0) }
        let length_link = __s0_buffer_get(SyntaxLinkRec, parse.links, node.children - 1)
        let element_link = __s0_buffer_get(SyntaxLinkRec, parse.links, length_link.next - 1)
        let length_node = __s0_buffer_get(SyntaxRec, parse.nodes, length_link.node - 1)
        let length = array_type_length(state, length_node)
        if !length.valid { return check_token_fail(d, state, store, 96, length_node) }
        let resolved = try resolve_type(d, state, parse, store, owner, element_link.node)
        let current = match resolved {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        if match resolved {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(resolved) }
        let element = checked_type_for_syntax(current, owner, element_link.node)
        let existing = canonical_single_arg(current, 15, length.value, element)
        if existing != 0 { return Ok(CheckGood(try annotate_checked_type(d, current, owner, node_id, existing))) }
        let first = __s0_buffer_len(U64, current.type_args) + 1
        let args = try __s0_buffer_append(U64, d, current.type_args, element)
        let recorded = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
        return Ok(CheckGood(try append_checked_type(d, recorded, owner, 15, node_id, length.value, first, 1)))
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
    // The public insertion-ordered Map is kind 23; the bootstrap-private
    // profile keeps Map meaning the fixed S0 map (kind 11) so the compiler's
    // own sources lower byte-for-byte as before.
    if node_word(state, node, "Map") {
        arity = 2
        if check_bootstrap_private() { kind = 11 } else { kind = 23 }
    }
    if node_word(state, node, "Set") { kind = 24
        arity = 1 }
    if node_word(state, node, "Ptr") { kind = 12
        arity = 1 }
    if node_word(state, node, "__s0_Buffer") { kind = 13
        arity = 1 }
    if node_word(state, node, "Vec") { kind = 17
        arity = 1 }
    if node_word(state, node, "MutSlice") { kind = 18
        arity = 1 }
    if node_word(state, node, "Table") { kind = 19
        arity = 1 }
    if (kind == 11 || kind == 13) && !check_bootstrap_private() { return check_fail(d, store, 105, node, 0, 0, 0) }
    var target: U64 = 0
    if kind == 0 {
        target = find_declared_type(state, parse, current, node)
        if target != 0 { kind = 7
            arity = __s0_buffer_get(SymbolRec, current.symbols, target - 1).type_arity }
    }
    // Do not commit a direct-argument range until the application itself is
    // valid. Failed heads and arities retain resolved child types but never
    // leave ownerless type-argument records in a CheckBad store.
    if kind == 0 { return check_fail(d, current, 4, node, 0, 0, 0) }
    if count != arity { return check_fail(d, current, 5, node, 0, 0, 0) }
    let existing = canonical_type_for_links(parse, current, owner, kind, target, node.children)
    var appended = current
    if existing != 0 { appended = try annotate_checked_type(d, current, owner, node_id, existing) } else {
        let start = __s0_buffer_len(U64, current.type_args)
        let recorded = try record_arg_links(d, parse, current, owner, node.children)
        var first: U64 = 0
        if count != 0 { first = start + 1 }
        appended = try append_checked_type(d, recorded, owner, kind, node_id, target, first, count)
    }
    let checked_id = checked_type_for_syntax(appended, owner, node_id)
    let checked = __s0_buffer_get(CheckedTypeRec, appended.types, checked_id - 1)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    if kind == 13 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let child = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, child, 0, 0, boundary) { return check_type_detail_fail(d, appended, 11, syntax_diag_node(state, parse, node_id), child) }
    }
    if kind == 17 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let child = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
        let category = try interpreted_type_category(d, state, parse, appended, empty, no_ancestry, child, 0, 0)
        if category.category != 1 && !vec_element_allows_affine(state, appended, child) {
            if __s0_buffer_get(CheckedTypeRec, store.types, child - 1).kind == 19 { return check_type_detail_fail(d, appended, 143, syntax_diag_node(state, parse, node_id), child) }
            return check_type_detail_fail(d, appended, 100, syntax_diag_node(state, parse, node_id), child)
        }
    }
    if kind == 19 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        // A table is always affine even when its element is copyable. M7.5
        // admits concrete copyable elements only; affine element composition
        // arrives with resource composition, and a scoped element can never
        // be owned by a table.
        let child = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
        let category = try interpreted_type_category(d, state, parse, appended, empty, no_ancestry, child, 0, 0)
        if category.category != 1 { return check_type_detail_fail(d, appended, 130, syntax_diag_node(state, parse, node_id), child) }
    }
    if kind == 11 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let key = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
        let value = __s0_buffer_get(U64, appended.type_args, checked.first_arg)
        if !(try interpreted_map_key_ok(d, state, parse, appended, empty, no_ancestry, key, 0, 0, boundary)) { return check_type_detail_fail(d, appended, 12, syntax_diag_node(state, parse, node_id), key) }
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, value, 0, 0, boundary) { return check_type_detail_fail(d, appended, 13, syntax_diag_node(state, parse, node_id), value) }
    }
    if (kind == 23 || kind == 24) && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        if kind == 23 {
            let key = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
            let value = __s0_buffer_get(U64, appended.type_args, checked.first_arg)
            if !ordered_key_supported(appended, key, 0) { return check_type_detail_fail(d, appended, 127, syntax_diag_node(state, parse, node_id), key) }
            if !ordered_value_copyable(appended, value, 0) { return check_type_detail_fail(d, appended, 128, syntax_diag_node(state, parse, node_id), value) }
        }
        if kind == 24 {
            let element = __s0_buffer_get(U64, appended.type_args, checked.first_arg - 1)
            if !ordered_key_supported(appended, element, 0) { return check_type_detail_fail(d, appended, 127, syntax_diag_node(state, parse, node_id), element) }
            if !ordered_value_copyable(appended, element, 0) { return check_type_detail_fail(d, appended, 128, syntax_diag_node(state, parse, node_id), element) }
        }
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
    if child.kind == 7 || child.kind == 14 || child.kind == 16 || child.kind == 52 || child.kind == 55 || child.kind == skip_kind { return Ok(CheckGood(current)) }
    var actual_role = role
    if role == 5 && child.kind != 13 && child.kind != 47 && child.kind != 48 { actual_role = 6 }
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
        return Ok(CheckGood(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)))
    }
    var syntax = link.node
    if child.kind == 8 || child.kind == 9 || child.kind == 10 || child.kind == 13 || child.kind == 47 || child.kind == 48 {
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
        let checked_id = checked_type_for_syntax(next, owner, syntax)
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
        let checked = __s0_buffer_get(CheckedTypeRec, next.types, checked_type_for_syntax(next, owner, syntax) - 1)
        let diag_node = __s0_buffer_get(SyntaxRec, parse.nodes, syntax - 1)
        if duplicate_parameter { return check_fail(d, next, 16, diag_node, 0, 0, 0) }
        if reserved_value_name(state, next, child) { return check_fail(d, next, 17, diag_node, 0, 0, 0) }
        if child.kind == 47 || child.kind == 48 {
            let empty = try __s0_buffer_new(TypeBindingRec, d)
            let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
            let category = try interpreted_type_category(d, state, parse, next, empty, no_ancestry, checked_type_for_syntax(next, owner, syntax), 0, 0)
            if category.category != 0 {
                if child.kind == 48 && category.category != 2 { return check_token_fail(d, state, next, 90, diag_node) }
            }
            // `mut` stays an exclusive call borrow: an affine value, a scoped
            // capability, or a copyable cursor reached through a type
            // parameter constrained by a mut-self trait. Copyable and
            // unconstrained types are rejected; type-parameter types have
            // category 0 and are gated here so the cursor case stays the only
            // exception.
            if child.kind == 47 && !node_word(state, child, "self") && category.category != 2 && category.category != 3 {
                if !mut_cursor_param_ok(state, parse, next, owner, __s0_buffer_get(SyntaxRec, parse.nodes, syntax - 1)) { return check_token_fail(d, state, next, 89, diag_node) }
            }
        }
    }
    var name_start = child.name_start
    var name_end = child.name_end
    if actual_role == 3 || actual_role == 4 || actual_role == 6 { name_start = 0
        name_end = 0 }
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: actual_role, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: name_start, name_end: name_end, syntax: syntax, checked_type: checked_type_for_syntax(next, owner, syntax)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: uses, indexes: next.indexes, locals: next.locals, environments: next.environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, control: next.control, diagnostics: next.diagnostics, traits: next.traits, closures: next.closures)))
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
    let checked_id = checked_type_for_syntax(next, owner, result_link.node)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    if try direct_type_concrete(d, next, empty, checked_id, 0) {
        let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, syntax_diag_node(state, parse, result_link.node), 0)
        if match validated {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(validated) }
    }
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: 4, ordinal: 0, node: result_link.node, source: signature.source, name_start: 0, name_end: 0, syntax: result_link.node, checked_type: checked_type_for_syntax(next, owner, result_link.node)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: uses, indexes: next.indexes, locals: next.locals, environments: next.environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, control: next.control, diagnostics: next.diagnostics, traits: next.traits, closures: next.closures)))
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
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 || checked.kind == 15 {
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

fn check_result_store(result: CheckResult) -> CheckStore {
    return match result {
        CheckGood(value) => value
        CheckBad(value) => value
    }
}

fn check_result_bad(result: CheckResult) -> Bool {
    return match result {
        CheckGood(value) => false
        CheckBad(value) => true
    }
}

// One declaration. Kind mismatch returns the incoming store unchanged so the
// owner walk can assign this result unconditionally.
fn check_one_declaration(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, wanted: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if !(symbol.kind == wanted || (wanted == 0 && (symbol.kind == 2 || symbol.kind == 3))) { return Ok(CheckGood(store)) }
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.node - 1)
    let params = try collect_param_links(d, state, parse, store, owner, root.children)
    let with_params = check_result_store(params)
    if check_result_bad(params) { return Ok(params) }
    var checked: CheckResult = CheckGood(with_params)
    if root.kind == 2 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 1, 0) }
    if root.kind == 3 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 2, 11) }
    // A synthesized default method is a kind-12 symbol whose node is the
    // trait requirement (kind 51): its receiver, parameters, result, and
    // default body block resolve exactly like a written function's.
    if root.kind == 12 || root.kind == 51 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 5, 0) }
    if root.kind == 1 {
        let signature = __s0_buffer_get(SyntaxLinkRec, parse.links, root.children - 1)
        let sig = __s0_buffer_get(SyntaxRec, parse.nodes, signature.node - 1)
        checked = try check_import_types(d, state, parse, with_params, owner, sig)
    }
    if root.kind == 50 { checked = try check_trait_declaration(d, state, parse, with_params, owner, root) }
    let complete = check_result_store(checked)
    if check_result_bad(checked) { return Ok(checked) }
    if root.kind == 2 || root.kind == 3 || root.kind == 12 || root.kind == 51 { checked = try check_owner_constraints(d, state, parse, complete, owner, root) }
    let finished = check_result_store(checked)
    if check_result_bad(checked) { return Ok(checked) }
    if root.kind == 3 {
        var variants: U64 = 0
        var item_at: U64 = 0
        while item_at < __s0_buffer_len(DeclTypeUseRec, finished.uses) {
            let item = __s0_buffer_get(DeclTypeUseRec, finished.uses, item_at)
            if item.owner == owner && item.role == 2 { variants = variants + 1 }
            item_at = item_at + 1
        }
        if variants == 0 { return check_decl_fail(d, state, parse, finished, 8, owner) }
    }
    return Ok(CheckGood(finished))
}

// wanted 0 selects both aggregate kinds in their shared source order. Imports
// and functions use their syntax kind after aggregate checking and cycles.
// The walk is iterative and assigns only helper results: an if-join of
// CheckStore on a while backedge is rejected by MIR Phase 6.
fn check_declaration_at(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, wanted: U64) -> Result(CheckResult, __s0_Error) {
    var at = owner
    var current = store
    var failed: U64 = 0
    var last: CheckResult = CheckGood(store)
    while at <= __s0_buffer_len(SymbolRec, current.symbols) {
        let result = try check_one_declaration(d, state, parse, current, at, wanted)
        current = check_result_store(result)
        last = result
        if check_result_bad(result) { failed = 1 }
        if failed == 0 { at = at + 1 }
        if failed != 0 { at = __s0_buffer_len(SymbolRec, current.symbols) + 1 }
    }
    return Ok(last)
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
fn digits_at_most(values: __s0_Buffer(U8), start: U64, end: U64, limit: __s0_String) -> Bool {
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

fn array_type_length(state: State, node: SyntaxRec) -> ArrayLengthRec {
    if node.kind != 20 || node.token == 0 || node.token > __s0_buffer_len(TokenRec, state.tokens) { return ArrayLengthRec(valid: false, value: 0) }
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    if token.kind != 2 || token.value_start >= token.value_end || __s0_buffer_get(U8, state.values, token.value_start) == 45 { return ArrayLengthRec(valid: false, value: 0) }
    if !digits_at_most(state.values, token.value_start, token.value_end, "18446744073709551615") { return ArrayLengthRec(valid: false, value: 0) }
    var value: U64 = 0
    var at = token.value_start
    while at < token.value_end {
        let byte = __s0_buffer_get(U8, state.values, at)
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
    return ArrayLengthRec(valid: true, value: value)
}

fn current_environment(store: CheckStore, owner: U64) -> U64 {
    var at = __s0_buffer_len(EnvironmentRec, store.environments)
    while at != 0 {
        let environment = __s0_buffer_get(EnvironmentRec, store.environments, at - 1)
        if environment.owner == owner { return at }
        at = at - 1
    }
    return 0
}

fn local_lookup(store: CheckStore, owner: U64, node: SyntaxRec, state: State) -> U64 {
    var environment = current_environment(store, owner)
    while environment != 0 {
        let item = __s0_buffer_get(EnvironmentRec, store.environments, environment - 1)
        if item.binding != 0 {
            let local = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
            if same_name(state, node.source, node.name_start, node.name_end, local.source, local.name_start, local.name_end) { return item.binding }
        }
        environment = item.parent
    }
    return 0
}

// Return the view builtin that introduced an active lexical binding over
// receiver, or zero. View bindings are identified from their checked binding
// initializer rather than reconstructed from source syntax.
fn active_view_over(store: CheckStore, owner: U64, receiver: U64, environment: U64) -> U64 {
    var at = environment
    while at != 0 {
        let item = __s0_buffer_get(EnvironmentRec, store.environments, at - 1)
        if item.binding != 0 {
            let local = __s0_buffer_get(LocalRec, store.locals, item.binding - 1)
            let local_type = __s0_buffer_get(CheckedTypeRec, store.types, local.checked_type - 1)
            if local_type.kind == 8 || local_type.kind == 18 {
                var expression_id = previous_expression_for_owner(store, owner)
                while expression_id != 0 {
                    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
                    if expression.site_kind == 1 && expression.site_syntax == local.syntax && expression.kind == 18 && expression.annotation != 0 {
                        let annotation = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
                        if annotation.builtin >= 23 && annotation.builtin <= 25 && expression.child_count != 0 {
                            let child = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1).expression
                            let source = __s0_buffer_get(CheckedExprRec, store.expressions, child - 1)
                            if (source.kind == 1 || source.kind == 5) && source.parameter_use == receiver { return annotation.builtin }
                        }
                    }
                    expression_id = expression.owner_previous
                }
            }
        }
        at = item.parent
    }
    return 0
}

// Modes are 1 read, 2 mutation, 3 immutable view, and 4 mutable view.
// Slice views and table views follow the same overlap rule: a live exclusive
// view excludes every other access, and a live immutable view excludes
// mutation and exclusive views.
fn lexical_access_conflict(store: CheckStore, owner: U64, local: U64, mode: U64) -> Bool {
    let view = active_view_over(store, owner, local, current_environment(store, owner))
    if view == 24 || view == 25 { return true }
    if view == 23 && (mode == 2 || mode == 4) { return true }
    let table_view = live_table_view_over(store, owner, local, current_environment(store, owner))
    if table_view == 2 { return true }
    if table_view == 1 && (mode == 2 || mode == 4) { return true }
    return false
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

fn body_token_type_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, expected: U64, actual: U64) -> Result(BodyStep, __s0_Error) {
    let want = diagnostic_type(store, expected)
    let got = diagnostic_type(store, actual)
    let failed = try check_token_detail_fail(d, state, store, kind, node, want.kind, want.target, got.kind, got.target)
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
    return CheckStore(symbols: base.symbols, type_params: base.type_params, types: base.types, type_args: base.type_args, type_annotations: base.type_annotations, uses: base.uses, indexes: base.indexes, locals: base.locals, environments: base.environments, expressions: base.expressions, call_annotations: base.call_annotations, expression_children: base.expression_children, returns: base.returns, control: base.control, diagnostics: failed.diagnostics, traits: failed.traits, closures: base.closures)
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

fn diagnostic_type(store: CheckStore, checked_type: U64) -> DiagnosticTypeRec {
    let rec = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if rec.kind == 1 { return DiagnosticTypeRec(kind: 1, target: rec.target) }
    if rec.kind == 2 || rec.kind == 14 || rec.kind == 16 { return DiagnosticTypeRec(kind: rec.kind, target: 0) }
    if (rec.kind == 8 || rec.kind == 15 || rec.kind == 17 || rec.kind == 18) && rec.arg_count == 1 {
        let child = __s0_buffer_get(CheckedTypeRec, store.types, __s0_buffer_get(U64, store.type_args, rec.first_arg - 1) - 1)
        if child.kind == 1 { return DiagnosticTypeRec(kind: rec.kind, target: child.target) }
    }
    if rec.kind == 7 { return DiagnosticTypeRec(kind: 7, target: rec.target) }
    return DiagnosticTypeRec(kind: rec.kind, target: 0)
}

fn sequence_element_type(state: State, parse: ParseStore, store: CheckStore, checked_type: U64) -> U64 {
    let sequence = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if (sequence.kind == 8 || sequence.kind == 15 || sequence.kind == 17 || sequence.kind == 18) && sequence.arg_count == 1 { return __s0_buffer_get(U64, store.type_args, sequence.first_arg - 1) }
    if sequence.kind == 16 { return primitive_type_id(state, parse, store, "U8") }
    return 0
}

fn checker_utf8_continuation(value: U8) -> Bool { return value >= 128 && value <= 191 }

fn checker_utf8_valid(values: __s0_Buffer(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        let first = __s0_buffer_get(U8, values, at)
        if first < 128 { at = at + 1 }
        else { if first >= 194 && first <= 223 && at + 1 < end && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 1)) { at = at + 2 }
        else { if first == 224 && at + 2 < end && __s0_buffer_get(U8, values, at + 1) >= 160 && __s0_buffer_get(U8, values, at + 1) <= 191 && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 2)) { at = at + 3 }
        else { if ((first >= 225 && first <= 236) || (first >= 238 && first <= 239)) && at + 2 < end && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 1)) && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 2)) { at = at + 3 }
        else { if first == 237 && at + 2 < end && __s0_buffer_get(U8, values, at + 1) >= 128 && __s0_buffer_get(U8, values, at + 1) <= 159 && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 2)) { at = at + 3 }
        else { if first == 240 && at + 3 < end && __s0_buffer_get(U8, values, at + 1) >= 144 && __s0_buffer_get(U8, values, at + 1) <= 191 && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 2)) && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 3)) { at = at + 4 }
        else { if first >= 241 && first <= 243 && at + 3 < end && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 1)) && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 2)) && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 3)) { at = at + 4 }
        else { if first == 244 && at + 3 < end && __s0_buffer_get(U8, values, at + 1) >= 128 && __s0_buffer_get(U8, values, at + 1) <= 143 && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 2)) && checker_utf8_continuation(__s0_buffer_get(U8, values, at + 3)) { at = at + 4 }
        else { return false } } } } } } } }
    }
    return true
}

fn expr_token_type_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, expected: U64, actual: U64) -> Result(ExprOutcome, __s0_Error) {
    let want = diagnostic_type(store, expected)
    let got = diagnostic_type(store, actual)
    let failed = try check_token_detail_fail(d, state, store, kind, node, want.kind, want.target, got.kind, got.target)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(ExprBad(bad))
}

fn expr_token_single_type_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, checked_type: U64) -> Result(ExprOutcome, __s0_Error) {
    let detail = diagnostic_type(store, checked_type)
    let failed = try check_token_detail_fail(d, state, store, kind, node, detail.kind, detail.target, 0, 0)
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

fn primitive_type_id(state: State, parse: ParseStore, store: CheckStore, name: __s0_String) -> U64 {
    var target: U64 = 0
    if len(name) == 4 && name[0] == 66 { target = 1 }
    if len(name) == 3 && name[0] == 73 { target = 5 }
    if len(name) == 2 && name[0] == 85 && name[1] == 56 { target = 6 }
    if len(name) == 3 && name[0] == 85 { target = 9 }
    if len(name) == 3 && name[0] == 70 && name[1] == 54 { target = 11 }
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, at)
        if checked.kind == 1 && checked.target == target { return at + 1 }
        at = at + 1
    }
    return 0
}

fn primitive_type_named(state: State, parse: ParseStore, store: CheckStore, checked_type: U64, name: __s0_String) -> Bool {
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

fn parameter_type_compatible(d: Domain, state: State, parse: ParseStore, store: CheckStore, parameter: U64, argument: U64) -> Result(Bool, __s0_Error) {
    if try expression_type_equal(d, state, parse, store, parameter, argument) { return Ok(true) }
    let wanted = __s0_buffer_get(CheckedTypeRec, store.types, parameter - 1)
    let actual = __s0_buffer_get(CheckedTypeRec, store.types, argument - 1)
    if wanted.kind != 8 || wanted.arg_count != 1 || (actual.kind != 15 && actual.kind != 17 && actual.kind != 18) || actual.arg_count != 1 { return Ok(false) }
    return expression_type_equal(d, state, parse, store, __s0_buffer_get(U64, store.type_args, wanted.first_arg - 1), __s0_buffer_get(U64, store.type_args, actual.first_arg - 1))
}

fn call_argument_requires_final(store: CheckStore, parameter: U64, expression_id: U64) -> Bool {
    let wanted = __s0_buffer_get(CheckedTypeRec, store.types, parameter - 1)
    if wanted.kind == 18 { return true }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    let actual = __s0_buffer_get(CheckedTypeRec, store.types, expression.checked_type - 1)
    if wanted.kind == 8 && (actual.kind == 15 || actual.kind == 17 || actual.kind == 18) { return true }
    if expression.kind != 18 || expression.annotation == 0 { return false }
    let call = __s0_buffer_get(CallAnnotationRec, store.call_annotations, expression.annotation - 1)
    return call.builtin >= 23 && call.builtin <= 25
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

fn match_variant_seen(arms: __s0_Buffer(MatchArmDraftRec), first: U64, count: U64, variant_use: U64, variant_kind: U64) -> Bool {
    var at: U64 = 0
    while at < count {
        let arm = __s0_buffer_get(MatchArmDraftRec, arms, first - 1 + at)
        if arm.variant_use == variant_use && arm.variant_kind == variant_kind { return true }
        at = at + 1
    }
    return false
}

fn match_arms_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(MatchArmOutcome, __s0_Error) {
    let failed = try check_token_fail(d, state, store, kind, node)
    return Ok(MatchArmsBad(match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }))
}

// view_block_statement_ok validates one statement syntax node of a table-view
// arm block. The MIR access region of a view is one basic block, so a view
// block admits only straight-line copy statements: let bindings, including
// field reads through the view, and assignments. Control flow, returns, try,
// using, and expression statements are rejected; nested blocks of allowed
// statement kinds are admitted.
fn view_block_statement_ok(parse: ParseStore, link_id: U64) -> Bool {
    if link_id == 0 { return true }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    if !view_block_statement_ok(parse, link.next) { return false }
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    if node.kind == 15 || node.kind == 17 { return true }
    if node.kind == 14 { return view_block_statement_ok(parse, node.children) }
    return false
}

// view_expression_ok is the checked-expression half of the view region rule:
// no operation with a checked failure edge and no control flow may run
// between the lookup and the implicit view end. Reads, literals, field
// projections, comparisons, and non-view calls are safe; checked arithmetic,
// indexing, match, try, short-circuit operators, and affine transfers are
// not.
fn view_expression_ok(store: CheckStore, expression_id: U64) -> Bool {
    if expression_id == 0 { return true }
    if expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return false }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.kind == 12 || expression.kind == 13 || expression.kind == 19 || expression.kind == 22 { return false }
    if expression.kind == 6 && expression.operator != 2 { return false }
    if expression.kind == 7 && (expression.operator < 10 || expression.operator > 15) { return false }
    var child: U64 = 0
    while child < expression.child_count {
        if !view_expression_ok(store, __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + child).expression) { return false }
        child = child + 1
    }
    return true
}

// view_block_ok validates a checked block of a table-view arm after checking:
// every statement is a let or assignment whose initializer, index, and value
// expressions satisfy view_expression_ok.
fn view_block_ok(store: CheckStore, block_id: U64) -> Bool {
    if block_id == 0 || block_id > __s0_buffer_len(CheckedBlockRec, store.control.blocks) { return false }
    let block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, block_id - 1)
    var link_id = block.statements
    while link_id != 0 {
        let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link_id - 1)
        if link.statement == 0 || link.statement > __s0_buffer_len(CheckedStatementRec, store.control.statements) { return false }
        let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, link.statement - 1)
        if statement.kind != 1 && statement.kind != 3 && statement.kind != 6 { return false }
        if !view_expression_ok(store, statement.expression) { return false }
        if statement.place != 0 {
            if statement.place > __s0_buffer_len(CheckedPlaceRec, store.control.places) { return false }
            let place = __s0_buffer_get(CheckedPlaceRec, store.control.places, statement.place - 1)
            if place.index != 0 && !view_expression_ok(store, place.index) { return false }
        }
        if statement.body != 0 && !view_block_ok(store, statement.body) { return false }
        link_id = link.next
    }
    return true
}

fn check_match_arm_links(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, link_id: U64, scrutinee_type: U64, expected: U64, drafts: __s0_Buffer(MatchArmDraftRec), match_node: SyntaxRec, view_root: U64, view_mut: U64) -> Result(MatchArmOutcome, __s0_Error) {
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    if link.next == 0 { return Ok(MatchArmsGood(MatchArmValueRec(store: store, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, block_arms: false, expression_arms: false, arms: drafts))) }
    let prior_outcome = try check_match_arm_links(d, state, parse, base, store, owner, link.next, scrutinee_type, expected, drafts, match_node, view_root, view_mut)
    let prior = match prior_outcome {
        MatchArmsGood(value) => value
        MatchArmsBad(value) => MatchArmValueRec(store: value, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, block_arms: false, expression_arms: false, arms: drafts)
        MatchArmsDefer => MatchArmValueRec(store: store, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, block_arms: false, expression_arms: false, arms: drafts)
    }
    if match prior_outcome {
        MatchArmsGood(value) => false
        MatchArmsBad(value) => true
        MatchArmsDefer => false
    } { return Ok(MatchArmsBad(prior.store)) }
    if match prior_outcome {
        MatchArmsGood(value) => false
        MatchArmsBad(value) => false
        MatchArmsDefer => true
    } { return Ok(MatchArmsDefer) }
    let arm = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    let concrete = __s0_buffer_get(CheckedTypeRec, prior.store.types, scrutinee_type - 1)
    var variant_use: U64 = 0
    var variant_kind: U64 = 0
    var payload_type: U64 = 0
    if arm.name_start == 0 { variant_kind = 7 } else {
        if concrete.kind == 7 {
            variant_use = variant_named(state, prior.store, concrete.target, arm)
            if variant_use == 0 { return match_arms_fail(d, state, prior.store, 71, match_node) }
            let variant = __s0_buffer_get(DeclTypeUseRec, prior.store.uses, variant_use - 1)
            if variant.checked_type != 0 {
                let payload = try concrete_field_type(d, prior.store, scrutinee_type, variant_use)
                payload_type = payload.checked_type
            }
        } else {
            if concrete.kind == 9 && node_word(state, arm, "None") { variant_kind = 1 }
            if concrete.kind == 9 && node_word(state, arm, "Some") {
                variant_kind = 2
                payload_type = __s0_buffer_get(U64, prior.store.type_args, concrete.first_arg - 1)
            }
            if concrete.kind == 10 && node_word(state, arm, "Ok") {
                variant_kind = 3
                payload_type = __s0_buffer_get(U64, prior.store.type_args, concrete.first_arg - 1)
            }
            if concrete.kind == 10 && node_word(state, arm, "Err") {
                variant_kind = 4
                payload_type = __s0_buffer_get(U64, prior.store.type_args, concrete.first_arg)
            }
            if concrete.kind == 5 && node_word(state, arm, "OutOfMemory") { variant_kind = 5 }
            if concrete.kind == 5 && node_word(state, arm, "Limit") { variant_kind = 6 }
            if variant_kind == 0 { return match_arms_fail(d, state, prior.store, 71, match_node) }
        }
        if match_variant_seen(prior.arms, prior.first_arm, prior.arm_count, variant_use, variant_kind) { return match_arms_fail(d, state, prior.store, 72, match_node) }
    }
    let body_link = __s0_buffer_get(SyntaxLinkRec, parse.links, arm.children - 1)
    var current = prior.store
    let entry = current_environment(current, owner)
    var binding: U64 = 0
    var binding_link: U64 = 0
    if body_link.next != 0 { binding_link = body_link.next }
    if payload_type != 0 && binding_link == 0 { return match_arms_fail(d, state, current, 73, match_node) }
    if payload_type == 0 && binding_link != 0 { return match_arms_fail(d, state, current, 74, match_node) }
    if binding_link != 0 {
        let binding_node_id = __s0_buffer_get(SyntaxLinkRec, parse.links, binding_link - 1).node
        let binding_node = __s0_buffer_get(SyntaxRec, parse.nodes, binding_node_id - 1)
        if reserved_value_name(state, current, binding_node) { return match_arms_fail(d, state, current, 75, match_node) }
        if local_lookup(current, owner, binding_node, state) != 0 { return match_arms_fail(d, state, current, 76, match_node) }
        let locals = try __s0_buffer_append(LocalRec, d, current.locals, LocalRec(owner: owner, kind: 2, syntax: binding_node_id, source: binding_node.source, name_start: binding_node.name_start, name_end: binding_node.name_end, mutable: 0, checked_type: payload_type))
        binding = __s0_buffer_len(LocalRec, locals)
        let environments = try __s0_buffer_append(EnvironmentRec, d, current.environments, EnvironmentRec(owner: owner, parent: entry, binding: binding))
        var with_views = current.control.table_views
        if view_root != 0 {
            // Register the live view before the arm body is checked, so the
            // access-conflict rules observe it for the whole arm scope.
            with_views = try __s0_buffer_append(CheckedTableViewRec, d, with_views, CheckedTableViewRec(owner: owner, binding: binding, root: view_root, mutable_view: view_mut))
        }
        let view_control = CheckedControlStore(blocks: current.control.blocks, statement_links: current.control.statement_links, statements: current.control.statements, places: current.control.places, matches: current.control.matches, match_arms: current.control.match_arms, tries: current.control.tries, cleanups: current.control.cleanups, table_views: with_views)
        current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: locals, environments: environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: view_control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
    }
    var arm_expected = expected
    if prior.arm_type != 0 { arm_expected = prior.arm_type }
    let body_node = __s0_buffer_get(SyntaxRec, parse.nodes, body_link.node - 1)
    var arm_body: U64 = 0
    var arm_block: U64 = 0
    var arm_value_type: U64 = 0
    var block_arm = false
    if body_node.kind == 14 {
        // A block arm is the statement form: every arm of one match must use
        // it, the arm produces Unit, and a table-view arm restricts its
        // statements to the straight-line fail-free region rules.
        if binding != 0 && view_root != 0 {
            if !view_block_statement_ok(parse, body_node.children) { return match_arms_fail(d, state, current, 133, body_node) }
        }
        let first_events = try __s0_buffer_new(BodyEventRec, d)
        let built = try build_body_event(d, parse, first_events, 1, body_link.node)
        let stepped = try check_body_event(d, state, parse, built.events, current, owner, built.event, false, true)
        if body_event_stopped(stepped) { return Ok(MatchArmsBad(body_event_store(stepped, current))) }
        let value = body_event_value(stepped, current)
        current = value.store
        arm_block = value.semantic
        // The twelve canonical primitives are pre-seeded, so the Unit result
        // of a statement arm is always the canonical record for target 12.
        let unit_type = canonical_type_id(current, 1, 12, 0, 0)
        if unit_type == 0 { return Ok(MatchArmsDefer) }
        arm_value_type = unit_type
        block_arm = true
        if binding != 0 && view_root != 0 {
            if !view_block_ok(current, arm_block) { return match_arms_fail(d, state, current, 133, body_node) }
        }
    } else {
        let checked_body = try check_value_expression_inner(d, state, parse, base, current, owner, body_node, body_link.node, arm_expected, 77, body_node, 0, 0)
        current = match checked_body {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_body {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(MatchArmsBad(current)) }
        let draft = match checked_body {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return Ok(MatchArmsDefer) }
        if binding != 0 && view_root != 0 && !view_expression_ok(current, draft.expression) { return match_arms_fail(d, state, current, 133, body_node) }
        arm_body = draft.expression
        arm_value_type = draft.checked_type
    }
    if block_arm && prior.expression_arms { return match_arms_fail(d, state, current, 135, body_node) }
    if !block_arm && prior.block_arms { return match_arms_fail(d, state, current, 135, body_node) }
    if prior.arm_type != 0 && !(try expression_type_equal(d, state, parse, current, prior.arm_type, arm_value_type)) { return match_arms_fail(d, state, current, 77, body_node) }
    let arm_environment = current_environment(current, owner)
    let next_drafts = try __s0_buffer_append(MatchArmDraftRec, d, prior.arms, MatchArmDraftRec(owner: owner, syntax: link.node, variant_use: variant_use, variant_kind: variant_kind, binding: binding, environment: arm_environment, body: arm_body, block: arm_block))
    if binding != 0 { current = try restore_environment(d, current, owner, entry) }
    var arm_type = prior.arm_type
    if arm_type == 0 { arm_type = arm_value_type }
    var first = prior.first_arm
    if first == 0 { first = __s0_buffer_len(MatchArmDraftRec, next_drafts) }
    return Ok(MatchArmsGood(MatchArmValueRec(store: current, arm_type: arm_type, first_arm: first, arm_count: prior.arm_count + 1, wildcard: prior.wildcard || variant_kind == 7, block_arms: prior.block_arms || block_arm, expression_arms: prior.expression_arms || !block_arm, arms: next_drafts)))
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
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: kind, checked_type: checked_type, parameter_use: reference, bool_value: bool_value, left: 0, right: 0, annotation: 0, first_child: first_child, child_count: child_count, operator: operator, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: store.call_annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

fn import_target_source(state: State, parse: ParseStore, imp: SyntaxRec) -> U64 {
    return module_source_named(state, parse, imp.source, imp.name_start, imp.name_end)
}

fn import_has_selected(parse: ParseStore, imp: SyntaxRec) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        if __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1).kind == 43 { return true }
        link = item.next
    }
    return false
}

fn import_binding_count(parse: ParseStore, imp: SyntaxRec) -> U64 {
    var count: U64 = 0
    var link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        if __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1).kind == 43 { count = count + 1 }
        link = item.next
    }
    if count == 0 { return 1 }
    return count
}

fn import_binding_at(state: State, parse: ParseStore, imp: SyntaxRec, ordinal: U64) -> SyntaxRec {
    var selected: U64 = 0
    var link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 43 {
            if selected == ordinal { return child }
            selected = selected + 1
        }
        link = item.next
    }
    link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 44 { return child }
        link = item.next
    }
    var last = imp.name_start
    var at = imp.name_start
    let source = __s0_buffer_get(SourceRec, state.sources, imp.source)
    while at < imp.name_end {
        if text_byte(state, source, at) == 46 { last = at + 1 }
        at = at + 1
    }
    return SyntaxRec(kind: 44, token: imp.token, source: imp.source, start: last, end: imp.name_end, name_start: last, name_end: imp.name_end, children: 0)
}

fn validate_import_bindings(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        let imp = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, root_at) - 1)
        if imp.kind == 41 || imp.kind == 42 {
            var binding_at: U64 = 0
            while binding_at < import_binding_count(parse, imp) {
                let binding = import_binding_at(state, parse, imp, binding_at)
                var same_at = binding_at + 1
                while same_at < import_binding_count(parse, imp) {
                    let same = import_binding_at(state, parse, imp, same_at)
                    if same_name(state, binding.source, binding.name_start, binding.name_end, same.source, same.name_start, same.name_end) { return check_token_related_fail(d, state, store, 1, same, binding) }
                    same_at = same_at + 1
                }
                var prior_root: U64 = 0
                while prior_root < root_at {
                    let prior = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, prior_root) - 1)
                    if prior.source == imp.source && (prior.kind == 41 || prior.kind == 42) {
                        var prior_at: U64 = 0
                        while prior_at < import_binding_count(parse, prior) {
                            let prior_binding = import_binding_at(state, parse, prior, prior_at)
                            if same_name(state, binding.source, binding.name_start, binding.name_end, prior_binding.source, prior_binding.name_start, prior_binding.name_end) { return check_token_related_fail(d, state, store, 1, binding, prior_binding) }
                            prior_at = prior_at + 1
                        }
                    }
                    prior_root = prior_root + 1
                }
                binding_at = binding_at + 1
            }
        }
        root_at = root_at + 1
    }
    return Ok(CheckGood(store))
}

fn import_selects(state: State, parse: ParseStore, imp: SyntaxRec, node: SyntaxRec) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 43 && same_name(state, node.source, node.name_start, node.name_end, child.source, child.name_start, child.name_end) { return true }
        link = item.next
    }
    return false
}

fn import_namespace_matches(state: State, parse: ParseStore, imp: SyntaxRec, node: SyntaxRec) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 44 { return same_name(state, node.source, node.name_start, node.name_end, child.source, child.name_start, child.name_end) }
        link = item.next
    }
    var last = imp.name_start
    var at = imp.name_start
    let source = __s0_buffer_get(SourceRec, state.sources, imp.source)
    while at < imp.name_end {
        if text_byte(state, source, at) == 46 { last = at + 1 }
        at = at + 1
    }
    return same_name(state, node.source, node.name_start, node.name_end, imp.source, last, imp.name_end)
}

fn import_namespace_range_matches(state: State, parse: ParseStore, imp: SyntaxRec, source_id: U64, start: U64, end: U64) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 44 { return same_name(state, source_id, start, end, child.source, child.name_start, child.name_end) }
        link = item.next
    }
    var last = imp.name_start
    var at = imp.name_start
    let source = __s0_buffer_get(SourceRec, state.sources, imp.source)
    while at < imp.name_end {
        if text_byte(state, source, at) == 46 { last = at + 1 }
        at = at + 1
    }
    return same_name(state, source_id, start, end, imp.source, last, imp.name_end)
}

fn symbol_named(state: State, parse: ParseStore, store: CheckStore, node: SyntaxRec) -> U64 {
    var module_source: U64 = 0
    var root_at: U64 = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        let root = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, root_at) - 1)
        if root.source == node.source && root.kind == 40 { module_source = node.source + 1 }
        root_at = root_at + 1
    }
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        if symbol.inherent_owner == 0 && same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) && (module_source == 0 || symbol.module_source == module_source) { return at + 1 }
        at = at + 1
    }
    if module_source == 0 { return 0 }
    var qualifier_end: U64 = 0
    var member_start: U64 = 0
    let occurrence_source = __s0_buffer_get(SourceRec, state.sources, node.source)
    var name_at = node.name_start
    while name_at < node.name_end {
        if text_byte(state, occurrence_source, name_at) == 46 && qualifier_end == 0 {
            qualifier_end = name_at
            member_start = name_at + 1
        }
        name_at = name_at + 1
    }
    if node.kind == 29 && node.children != 0 {
        let base_link = __s0_buffer_get(SyntaxLinkRec, parse.links, node.children - 1)
        let base = __s0_buffer_get(SyntaxRec, parse.nodes, base_link.node - 1)
        if base.kind == 24 {
            qualifier_end = base.name_end
            member_start = node.name_start
            name_at = base.name_start
        }
    } else { name_at = node.name_start }
    root_at = 0
    while root_at < __s0_buffer_len(U64, parse.roots) {
        let imp = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, root_at) - 1)
        if imp.source == node.source && (imp.kind == 41 || imp.kind == 42) && import_has_selected(parse, imp) && import_selects(state, parse, imp, node) {
            let target = import_target_source(state, parse, imp)
            if target != 0 { return exported_symbol_named(state, parse, store, target, node.source, node.name_start, node.name_end) }
        }
        if qualifier_end != 0 && imp.source == node.source && (imp.kind == 41 || imp.kind == 42) && !import_has_selected(parse, imp) && import_namespace_range_matches(state, parse, imp, node.source, name_at, qualifier_end) {
            let target = import_target_source(state, parse, imp)
            if target != 0 { return exported_symbol_named(state, parse, store, target, node.source, member_start, node.name_end) }
        }
        root_at = root_at + 1
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

fn inherent_symbol_named(state: State, parse: ParseStore, store: CheckStore, name: SyntaxRec, owner_target: U64, receiver: Bool) -> U64 {
    let owner_symbol = __s0_buffer_get(SymbolRec, store.symbols, owner_target - 1)
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at)
        let owner_id = symbol.inherent_owner
        if owner_id != 0 && same_name(state, name.source, name.name_start, name.name_end, symbol.source, symbol.name_start, symbol.name_end) {
            let owner = __s0_buffer_get(SyntaxRec, parse.nodes, owner_id - 1)
            // Inherent owners record the implementing type node; trait-impl
            // owners record the impl block itself and never resolve by name.
            if owner.kind != 53 && same_name(state, owner.source, owner.name_start, owner.name_end, owner_symbol.source, owner_symbol.name_start, owner_symbol.name_end) {
                var has_receiver = false
                if use_count(store, at + 1, 5) != 0 {
                    let first = __s0_buffer_get(DeclTypeUseRec, store.uses, use_by_ordinal(store, at + 1, 5, 0) - 1)
                    let parameter = __s0_buffer_get(SyntaxRec, parse.nodes, first.node - 1)
                    has_receiver = node_word(state, parameter, "self")
                }
                if (has_receiver && receiver) || (!has_receiver && !receiver) { return at + 1 }
            }
        }
        at = at + 1
    }
    return 0
}

fn expression_type_head(state: State, parse: ParseStore, store: CheckStore, node: SyntaxRec) -> CheckedTypeRec {
    let builtin = builtin_type_kind(state, node)
    if builtin == 1 { return CheckedTypeRec(kind: 1, syntax: 0, target: primitive_type_target(state, node), first_arg: 0, arg_count: 0) }
    if builtin != 0 { return CheckedTypeRec(kind: builtin, syntax: 0, target: 0, first_arg: 0, arg_count: 0) }
    if node_word(state, node, "Option") { return CheckedTypeRec(kind: 9, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "Result") { return CheckedTypeRec(kind: 10, syntax: 0, target: 0, first_arg: 0, arg_count: 2) }
    if node_word(state, node, "Map") {
        if check_bootstrap_private() { return CheckedTypeRec(kind: 11, syntax: 0, target: 0, first_arg: 0, arg_count: 2) }
        return CheckedTypeRec(kind: 23, syntax: 0, target: 0, first_arg: 0, arg_count: 2)
    }
    if node_word(state, node, "Set") { return CheckedTypeRec(kind: 24, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "Ptr") { return CheckedTypeRec(kind: 12, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "__s0_Buffer") { return CheckedTypeRec(kind: 13, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "Vec") { return CheckedTypeRec(kind: 17, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "MutSlice") { return CheckedTypeRec(kind: 18, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "Table") { return CheckedTypeRec(kind: 19, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    let declared = find_declared_type(state, parse, store, node)
    if declared != 0 { return CheckedTypeRec(kind: 7, syntax: 0, target: declared, first_arg: 0, arg_count: __s0_buffer_get(SymbolRec, store.symbols, declared - 1).type_arity) }
    return CheckedTypeRec(kind: 0, syntax: 0, target: 0, first_arg: 0, arg_count: 0)
}

fn expression_type_candidate_57(node: SyntaxRec) -> Bool { return node.kind == 57 }

fn expression_type_candidate(state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Bool {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 24 {
        if find_type_param(state, store, instance_declaration(store, owner), node) != 0 { return true }
        return expression_type_head(state, parse, store, node).kind != 0
    }
    if node.kind != 27 { return false }
    let callee_link = call_link_at(parse, node, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 { return false }
    let head = expression_type_head(state, parse, store, callee)
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

// The first argument link of a method call is the receiver, so its
// explicit type arguments start one link later than a free call's. The
// parser links the receiver only for non-associated dot callees: a callee
// that resolves as one qualified name, or whose base word starts
// uppercase (a type's associated function), keeps its base inside the
// callee node instead.
fn call_receiver_links(state: State, parse: ParseStore, store: CheckStore, call: SyntaxRec) -> U64 {
    let callee_link = call_link_at(parse, call, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 29 { return 0 }
    if symbol_named(state, parse, store, callee) != 0 { return 0 }
    if callee.children != 0 {
        let base_link = __s0_buffer_get(SyntaxLinkRec, parse.links, callee.children - 1)
        let base = __s0_buffer_get(SyntaxRec, parse.nodes, base_link.node - 1)
        if base.kind == 24 && base.name_end > base.name_start {
            let source = __s0_buffer_get(SourceRec, state.sources, base.source)
            let first = text_byte(state, source, base.name_start)
            if first >= 65 && first <= 90 { return 0 }
        }
    }
    return 1
}

fn leading_type_arg_count(state: State, parse: ParseStore, store: CheckStore, owner: U64, call: SyntaxRec) -> U64 {
    var count: U64 = 0
    let receivers = call_receiver_links(state, parse, store, call)
    let total = call_link_count(parse, call) - 1 - receivers
    while count < total {
        let link = call_link_at(parse, call, receivers + count + 1)
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
    let next = try __s0_buffer_append(U64, d, children, checked_type_for_syntax(next_store, owner, link.node))
    return resolve_expression_type_args(d, state, parse, next_store, owner, call, ordinal + 1, count, next)
}

fn resolve_expression_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 57 { return resolve_type(d, state, parse, store, owner, node_id) }
    if node.kind == 24 {
        let declaration = instance_declaration(store, owner)
        let param = find_type_param(state, store, declaration, node)
        if param != 0 {
            let concrete = instance_type_arg(store, owner, param)
            if concrete == 0 { return check_token_fail(d, state, store, 57, node) }
            return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, concrete)))
        }
        let head = expression_type_head(state, parse, store, node)
        if head.kind == 0 || head.arg_count != 0 { return check_token_fail(d, state, store, 56, node) }
        return Ok(CheckGood(try append_checked_type(d, store, owner, head.kind, node_id, head.target, 0, 0)))
    }
    if node.kind != 27 { return check_token_fail(d, state, store, 56, node) }
    let callee_link = call_link_at(parse, node, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    if callee.kind != 24 { return check_token_fail(d, state, store, 56, node) }
    let head = expression_type_head(state, parse, store, callee)
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

fn checker_use_slot(owner: U64, role: U64) -> U64 {
    return (owner - 1) * 8 + role - 1
}

fn checker_use_index_available(store: CheckStore, owner: U64, role: U64) -> Bool {
    if owner == 0 || role == 0 || role > 8 { return false }
    if !store.indexes.complete {
        if owner > __s0_buffer_len(SymbolRec, store.symbols) { return false }
        let kind = __s0_buffer_get(SymbolRec, store.symbols, owner - 1).kind
        if kind != 2 && kind != 3 { return false }
    }
    return checker_use_slot(owner, role) < __s0_buffer_len(CheckerUseIndexRec, store.indexes.uses)
}

fn build_use_indexes(d: Domain, store: CheckStore, complete: Bool) -> Result(CheckStore, __s0_Error) {
    let symbol_count = __s0_buffer_len(SymbolRec, store.symbols)
    let use_count = __s0_buffer_len(DeclTypeUseRec, store.uses)
    let slot_count = symbol_count * 8
    var counts = __s0_alloc(U64, d, slot_count + 1)
    var starts = __s0_alloc(U64, d, slot_count + 1)
    var seen = __s0_alloc(U64, d, slot_count + 1)
    var slot: U64 = 0
    while slot < slot_count {
        counts[slot] = 0
        starts[slot] = 0
        seen[slot] = 0
        slot = slot + 1
    }
    var at: U64 = 0
    while at < use_count {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner >= 1 && use.owner <= symbol_count && use.role >= 1 && use.role <= 8 {
            let use_slot = checker_use_slot(use.owner, use.role)
            counts[use_slot] = counts[use_slot] + 1
        }
        at = at + 1
    }
    var total: U64 = 0
    slot = 0
    while slot < slot_count {
        starts[slot] = total
        total = total + counts[slot]
        slot = slot + 1
    }
    var ordered = __s0_alloc(U64, d, use_count + 1)
    at = 0
    while at < use_count {
        ordered[at] = 0
        at = at + 1
    }
    at = 0
    while at < use_count {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner >= 1 && use.owner <= symbol_count && use.role >= 1 && use.role <= 8 {
            let use_slot = checker_use_slot(use.owner, use.role)
            ordered[starts[use_slot] + seen[use_slot]] = at + 1
            seen[use_slot] = seen[use_slot] + 1
        }
        at = at + 1
    }
    var use_indexes = try __s0_buffer_new(CheckerUseIndexRec, d)
    slot = 0
    while slot < slot_count {
        var first: U64 = 0
        if counts[slot] != 0 { first = starts[slot] + 1 }
        use_indexes = try __s0_buffer_append(CheckerUseIndexRec, d, use_indexes, CheckerUseIndexRec(first: first, count: counts[slot]))
        slot = slot + 1
    }
    var use_order = try __s0_buffer_new(U64, d)
    at = 0
    while at < use_count {
        use_order = try __s0_buffer_append(U64, d, use_order, ordered[at])
        at = at + 1
    }
    let indexes = CheckerIndexes(uses: use_indexes, use_order: use_order, complete: complete)
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures))
}

fn use_by_ordinal(store: CheckStore, owner: U64, role: U64, ordinal: U64) -> U64 {
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

fn use_count(store: CheckStore, owner: U64, role: U64) -> U64 {
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

fn variant_named(state: State, store: CheckStore, enum_owner: U64, node: SyntaxRec) -> U64 {
    if checker_use_index_available(store, enum_owner, 2) {
        let index = __s0_buffer_get(CheckerUseIndexRec, store.indexes.uses, checker_use_slot(enum_owner, 2))
        var ordinal: U64 = 0
        while ordinal < index.count {
            let use_id = __s0_buffer_get(U64, store.indexes.use_order, index.first - 1 + ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            if same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return use_id }
            ordinal = ordinal + 1
        }
        return 0
    }
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

fn previous_expression_for_owner(store: CheckStore, owner: U64) -> U64 {
    var at = __s0_buffer_len(CheckedExprRec, store.expressions)
    while at != 0 {
        if __s0_buffer_get(CheckedExprRec, store.expressions, at - 1).owner == owner { return at }
        at = at - 1
    }
    return 0
}

fn expression_for_syntax(store: CheckStore, owner: U64, syntax: U64) -> U64 {
    var at = previous_expression_for_owner(store, owner)
    var found: U64 = 0
    while at != 0 {
        let expression = __s0_buffer_get(CheckedExprRec, store.expressions, at - 1)
        if expression.syntax == syntax { found = at }
        at = expression.owner_previous
    }
    return found
}

fn append_call_expression(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, syntax: U64, expression_kind: U64, checked_type: U64, annotation_kind: U64, target: U64, variant_use: U64, child_call: SyntaxRec, child_mode: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try __s0_buffer_append(CallAnnotationRec, d, store.call_annotations, CallAnnotationRec(owner: owner, kind: annotation_kind, target: target, checked_type: checked_type, variant_use: variant_use, builtin: 0))
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
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: expression_kind, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: annotation, first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

fn canonical_application(d: Domain, store: CheckStore, owner: U64, kind: U64, first_arg: U64, second_arg: U64, count: U64) -> Result(TypeValueRec, __s0_Error) {
    let empty = try __s0_buffer_new(U64, d)
    var children = try __s0_buffer_append(U64, d, empty, first_arg)
    if count == 2 { children = try __s0_buffer_append(U64, d, children, second_arg) }
    let existing = canonical_type_for_children(store, kind, 0, children)
    if existing != 0 { return Ok(TypeValueRec(store: store, checked_type: existing)) }
    let first = __s0_buffer_len(U64, store.type_args) + 1
    let recorded = try append_substituted_children(d, store, children, 0)
    let next = try append_checked_type(d, recorded, owner, kind, 0, 0, first, count)
    return Ok(TypeValueRec(store: next, checked_type: __s0_buffer_len(CheckedTypeRec, next.types)))
}

fn canonical_leaf(d: Domain, store: CheckStore, kind: U64, target: U64) -> Result(TypeValueRec, __s0_Error) {
    let existing = canonical_type_id(store, kind, target, 0, 0)
    if existing != 0 { return Ok(TypeValueRec(store: store, checked_type: existing)) }
    let next = try append_checked_type(d, store, 0, kind, 0, target, 0, 0)
    return Ok(TypeValueRec(store: next, checked_type: canonical_type_id(next, kind, target, 0, 0)))
}

// append_builtin_expression records only runtime operands as ordered children;
// explicit type operands remain canonical type annotations on their syntax.
fn append_builtin_expression(d: Domain, parse: ParseStore, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, builtin: U64, call: SyntaxRec, first_runtime: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try __s0_buffer_append(CallAnnotationRec, d, store.call_annotations, CallAnnotationRec(owner: owner, kind: 5, target: 0, checked_type: checked_type, variant_use: 0, builtin: builtin))
    var children = store.expression_children
    var first_child: U64 = 0
    var child_count: U64 = 0
    var ordinal = first_runtime
    while ordinal < call_link_count(parse, call) - 1 {
        let link = call_link_at(parse, call, ordinal + 1)
        let child = expression_for_syntax(store, owner, link.node)
        if child != 0 {
            if first_child == 0 { first_child = __s0_buffer_len(CheckedExprChildRec, children) + 1 }
            children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: child))
            child_count = child_count + 1
        }
        ordinal = ordinal + 1
    }
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 18, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: __s0_buffer_len(CallAnnotationRec, annotations), first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

// append_s0_error_expression records a payload-free S0 error constructor
// (OutOfMemory or Limit) as a kind-6 annotation with a kind-10 expression and
// no children. builtin is 5 for OutOfMemory and 6 for Limit.
fn append_s0_error_expression(d: Domain, parse: ParseStore, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, builtin: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try __s0_buffer_append(CallAnnotationRec, d, store.call_annotations, CallAnnotationRec(owner: owner, kind: 6, target: 0, checked_type: checked_type, variant_use: 0, builtin: builtin))
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 10, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: __s0_buffer_len(CallAnnotationRec, annotations), first_child: 0, child_count: 0, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
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

fn check_call_argument_mode(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, arg: SyntaxRec, parameter: DeclTypeUseRec, expression_id: U64) -> Result(ExprOutcome, __s0_Error) {
    let parameter_node = __s0_buffer_get(SyntaxRec, parse.nodes, parameter.node - 1)
    if parameter_node.kind != 47 && parameter_node.kind != 48 { return expr_draft(store, 0, 0) }
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    let category = try interpreted_type_category(d, state, parse, store, empty, no_ancestry, parameter.checked_type, 0, 0)
    if parameter_node.kind == 48 && category.category != 2 { return expr_token_fail(d, state, base, 90, arg) }
    // A mut cursor parameter borrows the caller's binding exclusively, so
    // the argument must be a mutable place: a var binding, an owner, or
    // another mut parameter forwarding the cursor. A let-bound copyable
    // argument would silently advance a copy and gets its own diagnostic.
    var place_fail: U64 = 92
    if parameter_node.kind == 47 && category.category == 1 && !node_word(state, parameter_node, "self") { place_fail = 146 }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.kind != 1 && expression.kind != 5 { return expr_token_fail(d, state, base, place_fail, arg) }
    let binding = __s0_buffer_get(LocalRec, store.locals, expression.parameter_use - 1)
    var access = false
    if binding.kind == 2 {
        // Ordinary let bindings own affine values outright, so they satisfy
        // mut and take parameters. A copyable cursor argument is different:
        // only a var binding (or a forwarding mut parameter) lets the callee
        // advance the caller's cursor instead of a discarded copy.
        if place_fail != 146 { access = true } else {
            if binding.mutable == 1 { access = true }
        }
    } else {
        let declaration = __s0_buffer_get(SyntaxRec, parse.nodes, binding.syntax - 1)
        if parameter_node.kind == 47 && (declaration.kind == 47 || declaration.kind == 48) { access = true }
        if parameter_node.kind == 48 && declaration.kind == 48 { access = true }
    }
    if !access { return expr_token_fail(d, state, base, place_fail, arg) }
    if parameter_node.kind == 48 {
        __s0_buffer_set(CheckedExprRec, store.expressions, expression_id - 1, CheckedExprRec(owner: expression.owner, owner_previous: expression.owner_previous, syntax: expression.syntax, kind: 22, checked_type: expression.checked_type, parameter_use: expression.parameter_use, bool_value: expression.bool_value, left: expression.left, right: expression.right, annotation: expression.annotation, first_child: expression.first_child, child_count: expression.child_count, operator: expression.operator, site_kind: expression.site_kind, site_syntax: expression.site_syntax))
    }
    return expr_draft(store, 0, 0)
}

fn check_existing_call_modes(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, supplied: U64, receiver_at: U64, ordinal: U64, count: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    var link_ordinal = supplied + ordinal + 1
    if receiver_at != 0 {
        if ordinal == 0 { link_ordinal = receiver_at } else { link_ordinal = supplied + ordinal }
    }
    let link = call_link_at(parse, call, link_ordinal)
    let arg = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    let expression = expression_for_syntax(store, owner, link.node)
    if expression == 0 { return expr_deferred(base) }
    let parameter_id = use_by_ordinal(store, target, 7, ordinal)
    let parameter = __s0_buffer_get(DeclTypeUseRec, store.uses, parameter_id - 1)
    if ordinal + 1 < count && call_argument_requires_final(store, parameter.checked_type, expression) { return expr_token_fail(d, state, base, 104, arg) }
    let checked = try check_call_argument_mode(d, state, parse, base, store, owner, arg, parameter, expression)
    let current = match checked {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match checked {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    return check_existing_call_modes(d, state, parse, base, current, owner, call, target, supplied, receiver_at, ordinal + 1, count)
}

fn check_positional_call_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, role: U64, ordinal: U64, count: U64, mismatch: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    let arg_link = call_link_at(parse, call, ordinal + 1)
    let arg = __s0_buffer_get(SyntaxRec, parse.nodes, arg_link.node - 1)
    if arg.kind == 28 { return expr_token_fail(d, state, base, mismatch, arg) }
    let parameter_id = use_by_ordinal(store, target, role, ordinal)
    let parameter = __s0_buffer_get(DeclTypeUseRec, store.uses, parameter_id - 1)
    var argument_expected = parameter.checked_type
    if __s0_buffer_get(CheckedTypeRec, store.types, parameter.checked_type - 1).kind == 8 { argument_expected = 0 }
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, arg, arg_link.node, argument_expected, mismatch, arg, 0, 0)
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
    if !(try parameter_type_compatible(d, state, parse, current, parameter.checked_type, draft.checked_type)) { return expr_token_fail(d, state, base, mismatch, arg) }
    // An aggregate parameter that contains a scoped view is a capability the
    // callee could retain, so it stays non-escaping. Exact slice, MutSlice,
    // and bootstrap capability parameters are not aggregates and keep their
    // own call-borrow rules.
    let parameter_kind = __s0_buffer_get(CheckedTypeRec, current.types, parameter.checked_type - 1).kind
    if (parameter_kind == 7 || parameter_kind == 9 || parameter_kind == 10 || parameter_kind == 11 || parameter_kind == 13 || parameter_kind == 15 || parameter_kind == 17) && (try checked_type_contains_scoped(d, state, parse, current, parameter.checked_type)) { return expr_token_fail(d, state, base, 104, arg) }
    if ordinal + 1 < count && call_argument_requires_final(current, parameter.checked_type, draft.expression) { return expr_token_fail(d, state, base, 104, arg) }
    let mode = try check_call_argument_mode(d, state, parse, base, current, owner, arg, parameter, draft.expression)
    let mode_store = match mode {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match mode {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(mode_store)) }
    return check_positional_call_args(d, state, parse, base, mode_store, owner, call, target, role, ordinal + 1, count, mismatch)
}

// transfer_owned_argument rewrites a construction argument that reads an
// owned affine binding into a kind-22 transfer, mirroring take parameters and
// returns: constructing a record, enum variant, Option/Result wrapper, or
// array moves the part into the aggregate. Only whole aggregates transfer;
// there is no field-extraction syntax, so parts leave an aggregate only by
// transferring the aggregate itself.
fn transfer_owned_argument(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, expression_id: U64) -> Result(CheckStore, __s0_Error) {
    if expression_id == 0 || expression_id > __s0_buffer_len(CheckedExprRec, store.expressions) { return Ok(store) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    if expression.kind != 1 && expression.kind != 5 { return Ok(store) }
    if expression.owner != owner { return Ok(store) }
    if expression.parameter_use == 0 || expression.parameter_use > __s0_buffer_len(LocalRec, store.locals) { return Ok(store) }
    let binding = __s0_buffer_get(LocalRec, store.locals, expression.parameter_use - 1)
    var owned = binding.kind == 2
    if binding.kind == 1 && __s0_buffer_get(SyntaxRec, parse.nodes, binding.syntax - 1).kind == 48 { owned = true }
    if !owned { return Ok(store) }
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    let category = try interpreted_type_category(d, state, parse, store, empty, no_ancestry, expression.checked_type, 0, 0)
    if category.category != 2 { return Ok(store) }
    __s0_buffer_set(CheckedExprRec, store.expressions, expression_id - 1, CheckedExprRec(owner: expression.owner, owner_previous: expression.owner_previous, syntax: expression.syntax, kind: 22, checked_type: expression.checked_type, parameter_use: expression.parameter_use, bool_value: expression.bool_value, left: expression.left, right: expression.right, annotation: expression.annotation, first_child: expression.first_child, child_count: expression.child_count, operator: expression.operator, site_kind: expression.site_kind, site_syntax: expression.site_syntax))
    return Ok(store)
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
    let transferred = try transfer_owned_argument(d, state, parse, current, owner, draft.expression)
    return check_record_values(d, state, parse, base, transferred, owner, call, target, ordinal + 1, count)
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
    if !(try checked_type_views_materializable(d, state, parse, current, draft.checked_type)) {
        let failed = try check_token_fail(d, state, base, 104, payload_node)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
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

fn infer_call_arguments(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, runtime_start: U64, receiver_at: U64, ordinal: U64, count: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == count { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    var arg_ordinal = runtime_start + ordinal + 1
    if receiver_at != 0 {
        if ordinal == 0 { arg_ordinal = receiver_at } else { arg_ordinal = runtime_start + ordinal }
    }
    let arg_link = call_link_at(parse, call, arg_ordinal)
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
            return infer_call_arguments(d, state, parse, base, variant_store, owner, call, target, runtime_start, receiver_at, ordinal + 1, count, inferred)
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
    return infer_call_arguments(d, state, parse, base, after, owner, call, target, runtime_start, receiver_at, ordinal + 1, count, inferred)
}

fn explicit_function_bindings(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, declaration: U64, application: SyntaxRec, ordinal: U64, param_at: U64, first_link: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == __s0_buffer_get(SymbolRec, store.symbols, declaration - 1).type_arity { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    var at = param_at
    while __s0_buffer_get(TypeParamRec, store.type_params, at).owner != declaration { at = at + 1 }
    let link = call_link_at(parse, application, first_link + ordinal + 1)
    let resolved = try resolve_expression_type(d, state, parse, store, owner, link.node)
    let current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(CallInferenceBad(current)) }
    let concrete = checked_type_for_syntax(current, owner, link.node)
    if !checked_type_concrete(current, concrete) {
        let failed = try check_token_fail(d, state, store, 57, application)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let next = try __s0_buffer_append(InferenceBindingRec, d, bindings, InferenceBindingRec(param: at + 1, checked_type: concrete))
    return explicit_function_bindings(d, state, parse, current, owner, declaration, application, ordinal + 1, at + 1, first_link, next)
}

fn check_explicit_function_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, supplied: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
    if supplied != symbol.type_arity { return expr_token_fail(d, state, base, 56, call) }
    let receivers = call_receiver_links(state, parse, store, call)
    let argument_count = call_link_count(parse, call) - 1 - supplied - receivers
    let parameter_count = use_count(store, target, 5)
    if argument_count + receivers != parameter_count { return expr_token_fail(d, state, base, 41, call) }
    let empty = try __s0_buffer_new(InferenceBindingRec, d)
    let explicit = try explicit_function_bindings(d, state, parse, store, owner, target, call, 0, 0, receivers, empty)
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
    let arguments = try infer_call_arguments(d, state, parse, base, with_types, owner, call, target, supplied + receivers, receivers, 0, argument_count + receivers, bindings)
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
    let modes = try check_existing_call_modes(d, state, parse, base, with_instance, owner, call, instance_id, supplied + receivers, receivers, 0, argument_count + receivers)
    let checked_instance = match modes {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match modes {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(checked_instance)) }
    let result_id = use_by_ordinal(checked_instance, instance_id, 8, 0)
    let result_type = __s0_buffer_get(DeclTypeUseRec, checked_instance.uses, result_id - 1).checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, checked_instance, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, checked_instance, owner, call_id, 8, result_type, 1, instance_id, 0, call, 1, site_kind, site_syntax)
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
    let after_transfer = try transfer_owned_argument(d, state, parse, after, owner, draft.expression)
    var inferred = bindings
    if expected == 0 {
        let unified = try unify_types(d, after_transfer, field.checked_type, draft.checked_type, bindings)
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
    return infer_record_values(d, state, parse, base, after_transfer, owner, call, target, ordinal + 1, count, inferred)
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
        if !(try checked_type_views_materializable(d, state, parse, applied.store, applied.checked_type)) { return expr_token_fail(d, state, base, 104, call) }
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
    if !(try checked_type_views_materializable(d, state, parse, current, constructed)) { return expr_token_fail(d, state, base, 104, call) }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, constructed, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, call_id, 9, constructed, 3, target, 0, call, 2, site_kind, site_syntax)
}

// Build the checked function-value type fn(params) -> result, env unit for a
// concrete non-generic function symbol from its role-5 parameter uses and
// role-6 result use, interning the kind-25 application canonically.
fn checked_function_value_type(d: Domain, store: CheckStore, owner: U64, target: U64) -> Result(TypeValueRec, __s0_Error) {
    var current = store
    let unit_made = try canonical_leaf(d, current, 1, 12)
    current = unit_made.store
    let param_total = use_count(current, target, 5)
    var args = try __s0_buffer_new(U64, d)
    var ordinal: U64 = 0
    while ordinal < param_total {
        let use_id = use_by_ordinal(current, target, 5, ordinal)
        args = try __s0_buffer_append(U64, d, args, __s0_buffer_get(DeclTypeUseRec, current.uses, use_id - 1).checked_type)
        ordinal = ordinal + 1
    }
    let result_id = use_by_ordinal(current, target, 6, 0)
    args = try __s0_buffer_append(U64, d, args, __s0_buffer_get(DeclTypeUseRec, current.uses, result_id - 1).checked_type)
    args = try __s0_buffer_append(U64, d, args, unit_made.checked_type)
    let existing = canonical_type_for_children(current, 25, 0, args)
    if existing != 0 { return Ok(TypeValueRec(store: current, checked_type: existing)) }
    let start = __s0_buffer_len(U64, current.type_args) + 1
    let recorded = try append_substituted_children(d, current, args, 0)
    let next = try append_checked_type(d, recorded, owner, 25, 0, 0, start, __s0_buffer_len(U64, args))
    return Ok(TypeValueRec(store: next, checked_type: __s0_buffer_len(CheckedTypeRec, next.types)))
}

// Indirect call through a function-typed binding. The checked kind-25 type
// carries [params..., result, env]; arguments check against the leading
// parameters and the call produces the result type. Arguments walk
// recursively: their checked stores are storage-carrying call results that
// must not cross a loop backedge.
fn check_indirect_call_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, fn_checked: CheckedTypeRec, callee_expression: U64, ordinal: U64, prior_first: U64, prior_second: U64, result: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let want_total = fn_checked.arg_count - 2
    if ordinal == want_total {
        if expected != 0 && !(try expression_type_equal(d, state, parse, store, result, expected)) { return expr_token_type_fail(d, state, store, mismatch_kind, mismatch_node, expected, result) }
        return append_sequence_method(d, store, owner, call_id, result, 44, callee_expression, prior_first, prior_second, site_kind, site_syntax)
    }
    let link = call_link_at(parse, call, ordinal + 1)
    let argument = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    let want = __s0_buffer_get(U64, store.type_args, fn_checked.first_arg - 1 + ordinal)
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, argument, link.node, want, 42, argument, 0, 0)
    let current = match checked {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    var first = prior_first
    var second = prior_second
    if ordinal == 0 { first = draft.expression } else { second = draft.expression }
    return check_indirect_call_args(d, state, parse, base, current, owner, call, call_id, fn_checked, callee_expression, ordinal + 1, first, second, result, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_indirect_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, fn_type: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let fn_checked = __s0_buffer_get(CheckedTypeRec, store.types, fn_type - 1)
    let param_total = fn_checked.arg_count - 2
    let argument_count = call_link_count(parse, call) - 1
    if argument_count != param_total { return expr_token_fail(d, state, base, 41, call) }
    if argument_count > 2 { return expr_token_fail(d, state, base, 144, call) }
    let result_type = __s0_buffer_get(U64, store.type_args, fn_checked.first_arg - 1 + param_total)
    let checked_callee = try check_value_expression_inner(d, state, parse, base, store, owner, callee, callee_link_id(parse, call), 0, 60, callee, 0, 0)
    let current = match checked_callee {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked_callee {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(current)) }
    let callee_draft = match checked_callee {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if callee_draft.deferred { return expr_deferred(base) }
    return check_indirect_call_args(d, state, parse, base, current, owner, call, call_id, fn_checked, callee_draft.expression, 0, 0, 0, result_type, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn callee_link_id(parse: ParseStore, call: SyntaxRec) -> U64 { return call_link_at(parse, call, 0).node }

// A captured binding must be a storage-free snapshot in this slice: plain
// values (primitives and records/enums/options over them) copy into the
// environment record without carrying storage provenance across the
// function-value boundary. Storage-backed captures (Vec, String, Bytes,
// function values) wait for the runtime-backed environment work.
fn closure_capture_copyable(store: CheckStore, checked_type: U64, depth: U64) -> Bool {
    return ordered_value_storage_free(store, checked_type, depth)
}

// Collected captures: enclosing-owner locals in first-reference order, with
// one referencing node each for diagnostics.
type ClosureScanRec {
    found: __s0_Buffer(U64)
    nodes: __s0_Buffer(U64)
    ok: Bool
}

// Collect the closure's captures: word nodes under the body that resolve to
// locals of the enclosing owner and are not this closure's own parameters.
// Type positions never produce kind-24 nodes, so every hit is a value
// reference.
fn closure_scan_captures(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64, params: __s0_Buffer(U64), found_in: __s0_Buffer(U64), nodes_in: __s0_Buffer(U64)) -> Result(ClosureScanRec, __s0_Error) {
    var found = found_in
    var nodes = nodes_in
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_id - 1)
    if node.kind == 24 {
        var skip = false
        var param_at: U64 = 0
        while param_at < __s0_buffer_len(U64, params) {
            if __s0_buffer_get(U64, params, param_at) == node_id { skip = true }
            param_at = param_at + 1
        }
        if !skip {
            let binding = local_lookup(store, owner, node, state)
            if binding != 0 {
                var seen = false
                var prior: U64 = 0
                while prior < __s0_buffer_len(U64, found) {
                    if __s0_buffer_get(U64, found, prior) == binding { seen = true }
                    prior = prior + 1
                }
                if !seen {
                    found = try __s0_buffer_append(U64, d, found, binding)
                    nodes = try __s0_buffer_append(U64, d, nodes, node_id)
                }
            }
        }
        return Ok(ClosureScanRec(found: found, nodes: nodes, ok: true))
    }
    if node.kind == 58 {
        // Nested closure literals are outside this slice: their transitive
        // capture threading through the outer thunk's frame is not lowered
        // yet, and the nested site check during arrow inference needs its
        // own store threading. Skip the subtree.
        return Ok(ClosureScanRec(found: found, nodes: nodes, ok: true))
    }
    var link = node.children
    while link != 0 {
        let child = __s0_buffer_get(SyntaxLinkRec, parse.links, link - 1)
        let stepped = try closure_scan_captures(d, state, parse, store, owner, child.node, params, found, nodes)
        if !stepped.ok { return Ok(stepped) }
        found = stepped.found
        nodes = stepped.nodes
        link = child.next
    }
    return Ok(ClosureScanRec(found: found, nodes: nodes, ok: true))
}

// Resolve the arrow form's result type by checking its body expression once
// on a throwaway store with the parameters bound. Only the inferred type
// survives; the temporary records are discarded.
fn closure_infer_result(d: Domain, state: State, parse: ParseStore, store: CheckStore, symbol: U64, body: SyntaxRec) -> Result(ExprOutcome, __s0_Error) {
    var current = store
    let statement_link = call_link_at(parse, body, 0)
    let statement = __s0_buffer_get(SyntaxRec, parse.nodes, statement_link.node - 1)
    let expression_link = call_link_at(parse, statement, 0)
    let expression = __s0_buffer_get(SyntaxRec, parse.nodes, expression_link.node - 1)
    let bound = try append_parameter_bindings(d, parse, current, symbol)
    current = bound
    let checked = try check_value_expression_inner(d, state, parse, current, current, symbol, expression, expression_link.node, 0, 60, expression, 0, 0)
    let after = match checked {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(after)) }
    let draft = match checked {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred || draft.checked_type == 0 { return expr_token_fail(d, state, after, 147, expression) }
    return Ok(ExprGood(ExprValueRec(store: after, draft: draft)))
}

// A closure literal (kind 58) creates a synthetic thunk symbol whose body is
// checked later by the ordinary deferred function-body pass. Declared
// parameters and captures are that symbol's role-5 uses in order, so the
// body resolves captures as trailing immutable parameters: reads are
// snapshots and writes fall out as parameter immutability. The expression
// itself has the erased fn(params) -> result type (kind 25, unit
// environment); the capture record exists only in lowering.
// The syntax node id of this closure literal. The expression entry point
// receives the caller's link node id, which is not always the fn-literal
// node itself, so resolve it by identity: the parser creates exactly one
// kind-58 node at these source bounds.
fn closure_syntax_id(parse: ParseStore, node: SyntaxRec) -> U64 {
    var at: U64 = __s0_buffer_len(SyntaxRec, parse.nodes)
    var found: U64 = 0
    while at != 0 {
        let candidate = __s0_buffer_get(SyntaxRec, parse.nodes, at - 1)
        if candidate.kind == 58 && candidate.source == node.source && candidate.start == node.start && candidate.end == node.end { found = at }
        at = at - 1
    }
    return found
}

// Re-anchor a type produced on a throwaway inference store into the real
// store. Types at or below the real store's count already exist there; only
// types the inference appended (closure function types) are rebuilt with
// their arguments, which are themselves re-anchored first.
fn closure_real_type(d: Domain, real: CheckStore, temp: CheckStore, type_id: U64, depth: U64) -> Result(TypeValueRec, __s0_Error) {
    if type_id == 0 || type_id <= __s0_buffer_len(CheckedTypeRec, real.types) { return Ok(TypeValueRec(store: real, checked_type: type_id)) }
    if depth > 16 { return Ok(TypeValueRec(store: real, checked_type: 0)) }
    var current = real
    if type_id > __s0_buffer_len(CheckedTypeRec, temp.types) { return Ok(TypeValueRec(store: real, checked_type: 0)) }
    let rec = __s0_buffer_get(CheckedTypeRec, temp.types, type_id - 1)
    if rec.arg_count != 0 && rec.first_arg == 0 { return Ok(TypeValueRec(store: real, checked_type: 0)) }
    var args = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < rec.arg_count {
        let anchored = try closure_real_type(d, current, temp, __s0_buffer_get(U64, temp.type_args, rec.first_arg - 1 + at), depth + 1)
        if anchored.checked_type == 0 { return Ok(TypeValueRec(store: current, checked_type: 0)) }
        current = anchored.store
        args = try __s0_buffer_append(U64, d, args, anchored.checked_type)
        at = at + 1
    }
    let existing = canonical_type_for_children(current, rec.kind, rec.target, args)
    if existing != 0 { return Ok(TypeValueRec(store: current, checked_type: existing)) }
    let first = __s0_buffer_len(U64, current.type_args) + 1
    let recorded = try append_substituted_children(d, current, args, 0)
    current = recorded
    let appended = try append_checked_type(d, current, 0, rec.kind, 0, rec.target, first, __s0_buffer_len(U64, args))
    return Ok(TypeValueRec(store: appended, checked_type: __s0_buffer_len(CheckedTypeRec, appended.types)))
}

fn check_closure_expression(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, node: SyntaxRec, expression_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    // Nested closure literals wait for transitive capture threading.
    if lower_closure_site_for(store, owner) != 0 { return expr_token_fail(d, state, base, 147, node) }
    let total = call_link_count(parse, node)
    if total < 1 { return expr_token_fail(d, state, base, 147, node) }
    var declared: U64 = 0
    var counting = true
    var at: U64 = 0
    while at < total {
        let link = call_link_at(parse, node, at)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
        if child.kind == 13 && counting { declared = declared + 1 } else { counting = false }
        at = at + 1
    }
    let rest = total - declared
    if rest != 1 && rest != 2 { return expr_token_fail(d, state, base, 147, node) }
    let body_link = call_link_at(parse, node, total - 1)
    let body = __s0_buffer_get(SyntaxRec, parse.nodes, body_link.node - 1)
    if body.kind != 14 { return expr_token_fail(d, state, base, 147, node) }
    // Resolve declared parameter types recursively: the store threads through
    // every step and must not cross a loop backedge.
    let empty_args = try __s0_buffer_new(U64, d)
    let empty_nodes = try __s0_buffer_new(U64, d)
    let params = try closure_resolve_params(d, state, parse, store, owner, node, declared, 0, empty_nodes, empty_args)
    if closure_params_bad(params) { return Ok(ExprBad(closure_params_store(params))) }
    var current = closure_params_store(params)
    var args = match params {
        ClosureParamsGood(value) => value.args
        ClosureParamsFailed(value) => empty_args
    }
    var param_nodes = match params {
        ClosureParamsGood(value) => value.nodes
        ClosureParamsFailed(value) => empty_nodes
    }
    // Collect captures over the whole subtree.
    let empty_found = try __s0_buffer_new(U64, d)
    let empty_refs = try __s0_buffer_new(U64, d)
    let scan = try closure_scan_children(d, state, parse, current, owner, node.children, param_nodes, empty_found, empty_refs)
    if !scan.ok { return expr_token_fail(d, state, base, 147, node) }
    let found = scan.found
    let found_nodes = scan.nodes
    // Every capture must be snapshot-copyable.
    var capture_at: U64 = 0
    while capture_at < __s0_buffer_len(U64, found) {
        let binding = __s0_buffer_get(LocalRec, store.locals, __s0_buffer_get(U64, found, capture_at) - 1)
        if !closure_capture_copyable(current, binding.checked_type, 0) {
            let failed_node = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, found_nodes, capture_at) - 1)
            return expr_token_fail(d, state, current, 145, failed_node)
        }
        capture_at = capture_at + 1
    }
    // The reserved thunk symbol and site from the pre-body reserve pass. The
    // site's expression field still holds the closure syntax node id.
    let closure_syntax = closure_syntax_id(parse, node)
    if closure_syntax == 0 { return expr_token_fail(d, state, base, 147, node) }
    var reserved_at: U64 = 0
    var site_at: U64 = 0
    while site_at < __s0_buffer_len(ClosureSiteRec, current.closures.sites) {
        let candidate = __s0_buffer_get(ClosureSiteRec, current.closures.sites, site_at)
        if candidate.owner == __s0_buffer_len(SymbolRec, current.symbols) + 1 || candidate.owner != 0 && __s0_buffer_get(SymbolRec, current.symbols, candidate.owner - 1).node == closure_syntax { reserved_at = site_at + 1 }
        site_at = site_at + 1
    }
    if reserved_at == 0 { return expr_token_fail(d, state, base, 147, node) }
    let symbol_id = __s0_buffer_get(ClosureSiteRec, current.closures.sites, reserved_at - 1).owner
    // Parameter uses: declared parameters, then captures in first-reference
    // order. Capture uses carry the captured binding's node and spans.
    let with_uses = try closure_append_uses(d, parse, current, symbol_id, param_nodes, args, found, 0)
    if closure_uses_bad(with_uses) { return Ok(ExprBad(closure_uses_store(with_uses))) }
    current = closure_uses_store(with_uses)
    // Result type: annotated, or inferred from the arrow body on a
    // throwaway store with the parameters bound.
    var result_type: U64 = 0
    if rest == 2 {
        let result_link = call_link_at(parse, node, total - 2)
        let resolved = try resolve_type(d, state, parse, current, owner, result_link.node)
        let after = match resolved {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        if match resolved {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(ExprBad(after)) }
        current = after
        result_type = checked_type_for_syntax(current, owner, result_link.node)
    } else {
        let inferred = try closure_infer_result(d, state, parse, current, symbol_id, body)
        let after = match inferred {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match inferred {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(after)) }
        let draft = match inferred {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        let after_infer = match inferred {
            ExprGood(value) => value.store
            ExprBad(value) => current
        }
        let anchored = try closure_real_type(d, current, after_infer, draft.checked_type, 0)
        if anchored.checked_type == 0 { return expr_token_fail(d, state, current, 147, node) }
        current = anchored.store
        result_type = anchored.checked_type
    }
    if result_type == 0 { return expr_token_fail(d, state, current, 147, node) }
    // The result use and its annotation sit on the body block node: the
    // closure node already backs the thunk symbol, and a node can carry only
    // one declaration-side use.
    let result_use = try __s0_buffer_append(DeclTypeUseRec, d, current.uses, DeclTypeUseRec(owner: symbol_id, role: 6, ordinal: 0, node: body_link.node, source: node.source, name_start: 0, name_end: 0, syntax: body_link.node, checked_type: result_type))
    current = try annotate_checked_type(d, current, symbol_id, body_link.node, result_type)
    current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: result_use, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
    // The erased function type: declared parameters, result, unit
    // environment.
    let unit_made = try canonical_leaf(d, current, 1, 12)
    current = unit_made.store
    args = try __s0_buffer_append(U64, d, args, result_type)
    args = try __s0_buffer_append(U64, d, args, unit_made.checked_type)
    // The function type annotates the body block node: the closure node
    // already carries the thunk symbol and the closure expression.
    let existing = canonical_type_for_children(current, 25, 0, args)
    var fn_type: U64 = 0
    if existing != 0 {
        fn_type = existing
        current = try annotate_checked_type(d, current, owner, body_link.node, existing)
    } else {
        let first = __s0_buffer_len(U64, current.type_args) + 1
        let recorded = try append_substituted_children(d, current, args, 0)
        current = recorded
        current = try append_checked_type(d, current, owner, 25, body_link.node, 0, first, __s0_buffer_len(U64, args))
        fn_type = checked_type_for_syntax(current, owner, body_link.node)
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, fn_type, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, fn_type) }
    // The closure expression record (kind 51) and the site.
    // Append the expression with its final site index and rebuild the site
    // record functionally: the arrow inference pass runs the whole site
    // check on a throwaway store, and in-place buffer sets would leak its
    // results into the shared backing.
    let closure_prior = previous_expression_for_owner(current, owner)
    let expressions = try __s0_buffer_append(CheckedExprRec, d, current.expressions, CheckedExprRec(owner: owner, owner_previous: closure_prior, syntax: closure_syntax, kind: 24, checked_type: fn_type, parameter_use: reserved_at, bool_value: 0, left: 0, right: 0, annotation: 0, first_child: 0, child_count: 0, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let expression_record = __s0_buffer_len(CheckedExprRec, expressions)
    let captures = try closure_append_captures(d, current.closures.captures, current.locals, found, 0)
    var sites = try __s0_buffer_new(ClosureSiteRec, d)
    var rebuild_at: U64 = 0
    while rebuild_at < __s0_buffer_len(ClosureSiteRec, current.closures.sites) {
        var record = __s0_buffer_get(ClosureSiteRec, current.closures.sites, rebuild_at)
        if rebuild_at + 1 == reserved_at { record = ClosureSiteRec(owner: symbol_id, expression: expression_record, declared_count: declared, capture_count: __s0_buffer_len(U64, found), first_capture: __s0_buffer_len(ClosureCaptureRec, current.closures.captures) + 1) }
        sites = try __s0_buffer_append(ClosureSiteRec, d, sites, record)
        rebuild_at = rebuild_at + 1
    }
    let with_closures = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: ClosureStoreRec(sites: sites, captures: captures))
    return expr_draft(with_closures, fn_type, expression_record)
}

type ClosureParamsRec {
    store: CheckStore
    nodes: __s0_Buffer(U64)
    args: __s0_Buffer(U64)
}

enum ClosureParamsOutcome {
    ClosureParamsGood(value: ClosureParamsRec)
    ClosureParamsFailed(value: CheckStore)
}

fn closure_params_bad(outcome: ClosureParamsOutcome) -> Bool { return match outcome {
    ClosureParamsGood(value) => false
    ClosureParamsFailed(value) => true
} }

fn closure_params_store(outcome: ClosureParamsOutcome) -> CheckStore { return match outcome {
    ClosureParamsGood(value) => value.store
    ClosureParamsFailed(value) => value
} }



// Resolve the declared parameter types in order, threading the store
// recursively so no buffer handle crosses a loop backedge.
fn closure_resolve_params(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node: SyntaxRec, declared: U64, ordinal: U64, nodes: __s0_Buffer(U64), args: __s0_Buffer(U64)) -> Result(ClosureParamsOutcome, __s0_Error) {
    if ordinal >= declared { return Ok(ClosureParamsGood(ClosureParamsRec(store: store, nodes: nodes, args: args))) }
    let link = call_link_at(parse, node, ordinal)
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    let type_link = call_link_at(parse, child, 0)
    let resolved = try resolve_type(d, state, parse, store, owner, type_link.node)
    var current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(ClosureParamsFailed(current)) }
    let with_arg = try __s0_buffer_append(U64, d, args, checked_type_for_syntax(current, owner, type_link.node))
    let with_node = try __s0_buffer_append(U64, d, nodes, link.node)
    return closure_resolve_params(d, state, parse, current, owner, node, declared, ordinal + 1, with_node, with_arg)
}

enum ClosureUsesOutcome {
    ClosureUsesGood(value: CheckStore)
    ClosureUsesFailed(value: CheckStore)
}

fn closure_uses_bad(outcome: ClosureUsesOutcome) -> Bool { return match outcome {
    ClosureUsesGood(value) => false
    ClosureUsesFailed(value) => true
} }

fn closure_uses_store(outcome: ClosureUsesOutcome) -> CheckStore { return match outcome {
    ClosureUsesGood(value) => value
    ClosureUsesFailed(value) => value
} }

// Append the thunk's role-5 uses: declared parameters first, then captures
// in first-reference order.
fn closure_append_uses(d: Domain, parse: ParseStore, store: CheckStore, symbol: U64, param_nodes: __s0_Buffer(U64), args: __s0_Buffer(U64), found: __s0_Buffer(U64), stage: U64) -> Result(ClosureUsesOutcome, __s0_Error) {
    let declared = __s0_buffer_len(U64, param_nodes)
    let captures = __s0_buffer_len(U64, found)
    var current = store
    var uses = current.uses
    var annotated = current
    if stage < declared {
        let param_node = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, param_nodes, stage) - 1)
        uses = try __s0_buffer_append(DeclTypeUseRec, d, uses, DeclTypeUseRec(owner: symbol, role: 5, ordinal: stage, node: __s0_buffer_get(U64, param_nodes, stage), source: param_node.source, name_start: param_node.name_start, name_end: param_node.name_end, syntax: __s0_buffer_get(U64, param_nodes, stage), checked_type: __s0_buffer_get(U64, args, stage)))
        annotated = try annotate_checked_type(d, current, symbol, __s0_buffer_get(U64, param_nodes, stage), __s0_buffer_get(U64, args, stage))
    } else {
        if stage < declared + captures {
            let binding = __s0_buffer_get(LocalRec, current.locals, __s0_buffer_get(U64, found, stage - declared) - 1)
            uses = try __s0_buffer_append(DeclTypeUseRec, d, uses, DeclTypeUseRec(owner: symbol, role: 5, ordinal: stage, node: binding.syntax, source: binding.source, name_start: binding.name_start, name_end: binding.name_end, syntax: binding.syntax, checked_type: binding.checked_type))
            annotated = try annotate_checked_type(d, current, symbol, binding.syntax, binding.checked_type)
        } else { return Ok(ClosureUsesGood(current)) }
    }
    current = CheckStore(symbols: annotated.symbols, type_params: annotated.type_params, types: annotated.types, type_args: annotated.type_args, type_annotations: annotated.type_annotations, uses: uses, indexes: annotated.indexes, locals: annotated.locals, environments: annotated.environments, expressions: annotated.expressions, call_annotations: annotated.call_annotations, expression_children: annotated.expression_children, returns: annotated.returns, control: annotated.control, diagnostics: annotated.diagnostics, traits: annotated.traits, closures: annotated.closures)
    return closure_append_uses(d, parse, current, symbol, param_nodes, args, found, stage + 1)
}

fn closure_append_captures(d: Domain, captures: __s0_Buffer(ClosureCaptureRec), locals: __s0_Buffer(LocalRec), found: __s0_Buffer(U64), at: U64) -> Result(__s0_Buffer(ClosureCaptureRec), __s0_Error) {
    if at >= __s0_buffer_len(U64, found) { return Ok(captures) }
    let binding = __s0_buffer_get(LocalRec, locals, __s0_buffer_get(U64, found, at) - 1)
    let appended = try __s0_buffer_append(ClosureCaptureRec, d, captures, ClosureCaptureRec(local: __s0_buffer_get(U64, found, at), checked_type: binding.checked_type))
    return closure_append_captures(d, appended, locals, found, at + 1)
}

// Walk the closure node's child chain, scanning each child subtree for
// capture references.
fn closure_scan_children(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64, params: __s0_Buffer(U64), found: __s0_Buffer(U64), nodes: __s0_Buffer(U64)) -> Result(ClosureScanRec, __s0_Error) {
    if link_id == 0 { return Ok(ClosureScanRec(found: found, nodes: nodes, ok: true)) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let stepped = try closure_scan_captures(d, state, parse, store, owner, link.node, params, found, nodes)
    if !stepped.ok { return Ok(stepped) }
    return closure_scan_children(d, state, parse, store, owner, link.next, params, stepped.found, stepped.nodes)
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
        let inferred = try infer_call_arguments(d, state, parse, base, store, owner, call, target, 0, 0, 0, argument_count, bindings)
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
        let modes = try check_existing_call_modes(d, state, parse, base, with_instance, owner, call, instance_id, 0, 0, 0, argument_count)
        let checked_instance = match modes {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match modes {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(checked_instance)) }
        let concrete_result_id = use_by_ordinal(checked_instance, instance_id, 8, 0)
        let concrete_result = __s0_buffer_get(DeclTypeUseRec, checked_instance.uses, concrete_result_id - 1).checked_type
        return append_call_expression(d, state, parse, checked_instance, owner, call_id, 8, concrete_result, 1, instance_id, 0, call, 1, site_kind, site_syntax)
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
    if !(try checked_type_views_materializable(d, state, parse, payload_store, payload_type)) { return expr_token_fail(d, state, base, 104, arg) }
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
    let transferred = try transfer_owned_argument(d, state, parse, current, owner, draft.expression)
    return append_call_expression(d, state, parse, transferred, owner, call_id, 10, expected, 4, checked.target, variant_id, call, 3, site_kind, site_syntax)
}

fn check_slice_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 1
    var arity: U64 = 1
    if node_word(state, callee, "range") { identity = 2
        arity = 3 }
    if call_link_count(parse, call) != arity + 1 { return expr_token_fail(d, state, base, 41, call) }
    let sequence_link = call_link_at(parse, call, 1)
    let sequence_node = __s0_buffer_get(SyntaxRec, parse.nodes, sequence_link.node - 1)
    let sequence = try check_value_expression_inner(d, state, parse, base, store, owner, sequence_node, sequence_link.node, 0, 42, sequence_node, 0, 0)
    let current = match sequence {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match sequence {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(current)) }
    let sequence_type = match sequence {
        ExprGood(value) => value.draft.checked_type
        ExprBad(value) => 0
    }
    let element = sequence_element_type(state, parse, current, sequence_type)
    if element == 0 { return expr_token_fail(d, state, base, 42, sequence_node) }
    let u64_type = primitive_type_id(state, parse, current, "U64")
    var next = current
    if arity == 3 {
        let first_link = call_link_at(parse, call, 2)
        let first_node = __s0_buffer_get(SyntaxRec, parse.nodes, first_link.node - 1)
        let checked_first = try check_value_expression_inner(d, state, parse, base, next, owner, first_node, first_link.node, u64_type, 42, first_node, 0, 0)
        next = match checked_first {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_first {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(next)) }
        let second_link = call_link_at(parse, call, 3)
        let second_node = __s0_buffer_get(SyntaxRec, parse.nodes, second_link.node - 1)
        let checked_second = try check_value_expression_inner(d, state, parse, base, next, owner, second_node, second_link.node, u64_type, 42, second_node, 0, 0)
        next = match checked_second {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_second {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(next)) }
    }
    var result = u64_type
    if identity == 2 { result = sequence_type }
    if expected != 0 && !(try expression_type_equal(d, state, parse, next, result, expected)) { return expr_token_type_fail(d, state, next, mismatch_kind, mismatch_node, expected, result) }
    return append_builtin_expression(d, parse, next, owner, call_id, result, identity, call, 0, site_kind, site_syntax)
}

fn check_vec_static_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 18
    var arity: U64 = 1
    if node_word(state, callee, "from_array") { identity = 19
        arity = 2 }
    if call_link_count(parse, call) != arity + 1 { return expr_token_fail(d, state, base, 41, call) }
    let type_link = call_link_at(parse, call, 1)
    let resolved = try resolve_expression_type(d, state, parse, store, owner, type_link.node)
    var current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(ExprBad(current)) }
    let element = checked_type_for_syntax(current, owner, type_link.node)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, element, 0, 0)
    if category.category != 1 && !vec_element_allows_affine(state, current, element) {
        if __s0_buffer_get(CheckedTypeRec, current.types, element - 1).kind == 19 { return expr_token_single_type_fail(d, state, current, 143, __s0_buffer_get(SyntaxRec, parse.nodes, type_link.node - 1), element) }
        return expr_token_single_type_fail(d, state, current, 100, __s0_buffer_get(SyntaxRec, parse.nodes, type_link.node - 1), element)
    }
    let vector = try canonical_application(d, current, owner, 17, element, 0, 1)
    current = vector.store
    if identity == 19 {
        let value_link = call_link_at(parse, call, 2)
        let value_node = __s0_buffer_get(SyntaxRec, parse.nodes, value_link.node - 1)
        var wanted_array: U64 = 0
        if value_node.kind == 50 {
            let count = type_arg_count(parse, value_node.children)
            wanted_array = canonical_single_arg(current, 15, count, element)
            if wanted_array == 0 {
                let first = __s0_buffer_len(U64, current.type_args) + 1
                let args = try __s0_buffer_append(U64, d, current.type_args, element)
                current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
                current = try append_checked_type(d, current, 0, 15, 0, count, first, 1)
                wanted_array = canonical_single_arg(current, 15, count, element)
            }
        }
        let checked = try check_value_expression_inner(d, state, parse, base, current, owner, value_node, value_link.node, wanted_array, 42, value_node, 0, 0)
        current = match checked {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let actual = match checked {
            ExprGood(value) => value.draft.checked_type
            ExprBad(value) => 0
        }
        let array = __s0_buffer_get(CheckedTypeRec, current.types, actual - 1)
        if array.kind != 15 || array.arg_count != 1 || !(try expression_type_equal(d, state, parse, current, element, __s0_buffer_get(U64, current.type_args, array.first_arg - 1))) { return expr_token_fail(d, state, base, 42, value_node) }
        if vec_element_allows_affine(state, current, element) {
            // The array of affine owners transfers into the vector, exactly
            // like an aggregate construction part.
            current = try transfer_owned_argument(d, state, parse, current, owner, match checked {
                ExprGood(value) => value.draft.expression
                ExprBad(value) => 0
            })
        }
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, vector.checked_type, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, vector.checked_type) }
    return append_builtin_expression(d, parse, current, owner, call_id, vector.checked_type, identity, call, 1, site_kind, site_syntax)
}

// live_table_view_over returns 0, 1, or 2 when the lexical environment holds
// a live immutable or mutable table view over the owner local, and 0 when no
// view is live. View bindings are arm bindings recorded in the table-view
// buffer; liveness follows the persistent environment chain, so a view stops
// being visible when its arm scope ends.
fn live_table_view_over(store: CheckStore, owner: U64, local: U64, environment: U64) -> U64 {
    var at = environment
    while at != 0 {
        let item = __s0_buffer_get(EnvironmentRec, store.environments, at - 1)
        if item.binding != 0 {
            var scan: U64 = 0
            while scan < __s0_buffer_len(CheckedTableViewRec, store.control.table_views) {
                let view = __s0_buffer_get(CheckedTableViewRec, store.control.table_views, scan)
                if view.owner == owner && view.binding == item.binding && view.root == local {
                    if view.mutable_view != 0 { return 2 }
                    return 1
                }
                scan = scan + 1
            }
        }
        at = item.parent
    }
    return 0
}

// check_table_static_builtin checks `Table.new(T)`. The element type argument
// is resolved as a type expression and must satisfy the same concrete
// copyable rule as the Table type itself.
fn check_table_static_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if call_link_count(parse, call) != 2 { return expr_token_fail(d, state, base, 41, call) }
    let type_link = call_link_at(parse, call, 1)
    let type_node = __s0_buffer_get(SyntaxRec, parse.nodes, type_link.node - 1)
    let resolved = try resolve_expression_type(d, state, parse, store, owner, type_link.node)
    var current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(ExprBad(current)) }
    let element = checked_type_for_syntax(current, owner, type_link.node)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    if try direct_type_concrete(d, current, empty, element, 0) {
        let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, element, 0, 0)
        if category.category != 1 { return expr_token_single_type_fail(d, state, current, 130, type_node, element) }
    }
    let table = try canonical_application(d, current, owner, 19, element, 0, 1)
    current = table.store
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, table.checked_type, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, table.checked_type) }
    return append_builtin_expression(d, parse, current, owner, call_id, table.checked_type, 26, call, 1, site_kind, site_syntax)
}

// check_table_method checks insert, get, get_mut, and remove on a named table
// owner. Mutations require an owning local or exclusive parameter; lookups
// produce the Option view payload that only a match scrutinee may consume,
// and every access mode excludes the overlapping views tracked by
// table_access_conflict.
fn check_table_method(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, receiver_node: SyntaxRec, receiver_type_id: U64, receiver_expression: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 0
    if node_word(state, callee, "insert") { identity = 27 }
    if node_word(state, callee, "get") { identity = 28 }
    if node_word(state, callee, "get_mut") { identity = 29 }
    if node_word(state, callee, "remove") { identity = 45 }
    if identity == 0 { return expr_token_fail(d, state, base, 61, callee) }
    if call_link_count(parse, call) != 3 { return expr_token_fail(d, state, base, 41, call) }
    if receiver_node.kind != 24 { return expr_token_fail(d, state, base, 131, receiver_node) }
    let local_id = local_lookup(store, owner, receiver_node, state)
    if local_id == 0 { return expr_token_fail(d, state, base, 131, receiver_node) }
    let local = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
    var owning_receiver = local.kind == 2 || local.mutable == 1
    if local.kind == 1 && __s0_buffer_get(SyntaxRec, parse.nodes, local.syntax - 1).kind == 48 { owning_receiver = true }
    if identity == 27 || identity == 29 || identity == 45 {
        // A structural mutation or exclusive view needs the owning binding,
        // an exclusive receiver, or a consuming parameter; a read-borrowed
        // table parameter stays immutable.
        if !owning_receiver { return expr_token_fail(d, state, base, 131, receiver_node) }
    }
    var mode: U64 = 1
    if identity == 27 || identity == 45 { mode = 2 }
    if identity == 28 { mode = 3 }
    if identity == 29 { mode = 4 }
    if lexical_access_conflict(store, owner, local_id, mode) { return expr_token_fail(d, state, base, 134, receiver_node) }
    let receiver_checked = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type_id - 1)
    let element = __s0_buffer_get(U64, store.type_args, receiver_checked.first_arg - 1)
    let id_made = try canonical_application(d, store, owner, 20, element, 0, 1)
    var current = id_made.store
    var wanted = id_made.checked_type
    if identity == 27 { wanted = element }
    let argument_link = call_link_at(parse, call, 2)
    let argument = __s0_buffer_get(SyntaxRec, parse.nodes, argument_link.node - 1)
    let checked_argument = try check_value_expression_inner(d, state, parse, base, current, owner, argument, argument_link.node, wanted, 42, argument, 0, 0)
    current = match checked_argument {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked_argument {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked_argument {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    let id_result = id_made.checked_type
    var result = id_result
    if identity == 28 {
        let view_made = try canonical_application(d, current, owner, 21, element, 0, 1)
        current = view_made.store
        let option_made = try canonical_application(d, current, owner, 9, view_made.checked_type, 0, 1)
        current = option_made.store
        result = option_made.checked_type
    }
    if identity == 29 {
        let view_made = try canonical_application(d, current, owner, 22, element, 0, 1)
        current = view_made.store
        let option_made = try canonical_application(d, current, owner, 9, view_made.checked_type, 0, 1)
        current = option_made.store
        result = option_made.checked_type
    }
    if identity == 45 {
        let bool_type = primitive_type_id(state, parse, current, "Bool")
        if bool_type == 0 { return expr_deferred(base) }
        result = bool_type
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, result) }
    return append_sequence_method(d, current, owner, call_id, result, identity, receiver_expression, draft.expression, 0, site_kind, site_syntax)
}

fn append_sequence_method(d: Domain, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, builtin: U64, receiver: U64, first_arg: U64, second_arg: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try __s0_buffer_append(CallAnnotationRec, d, store.call_annotations, CallAnnotationRec(owner: owner, kind: 5, target: 0, checked_type: checked_type, variant_use: 0, builtin: builtin))
    var children = store.expression_children
    let first = __s0_buffer_len(CheckedExprChildRec, children) + 1
    children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: receiver))
    var count: U64 = 1
    if first_arg != 0 { children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: first_arg))
        count = count + 1 }
    if second_arg != 0 { children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: second_arg))
        count = count + 1 }
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 18, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: __s0_buffer_len(CallAnnotationRec, annotations), first_child: first, child_count: count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

fn check_sequence_method(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, receiver_node: SyntaxRec, receiver_type_id: U64, receiver_expression: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let sequence = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type_id - 1)
    if sequence.kind != 8 && sequence.kind != 15 && sequence.kind != 17 && sequence.kind != 18 { return expr_token_fail(d, state, base, 61, callee) }
    var builtin: U64 = 0
    var arity: U64 = 0
    if node_word(state, callee, "len") { builtin = 20 }
    if node_word(state, callee, "push") { builtin = 21
        arity = 1 }
    if node_word(state, callee, "get") { builtin = 22
        arity = 1 }
    if node_word(state, callee, "slice") { builtin = 23
        arity = 2 }
    if node_word(state, callee, "slice_mut") { builtin = 24
        arity = 2 }
    if node_word(state, callee, "subview") { builtin = 25
        arity = 2 }
    // Method-call links include both the selected callee and its receiver.
    if builtin == 0 || call_link_count(parse, call) != arity + 2 { return expr_token_fail(d, state, base, 41, call) }
    if builtin == 21 && sequence.kind != 17 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 23 && sequence.kind == 18 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 24 && sequence.kind != 15 && sequence.kind != 17 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 25 && sequence.kind != 18 { return expr_token_fail(d, state, base, 61, callee) }
    let element = sequence_element_type(state, parse, store, receiver_type_id)
    // Affine-element vectors transfer elements in and drain them at scope
    // exit: per-element reads and views would duplicate an owner, so only
    // push, len, and whole-vector transfer exist for them.
    var affine_elements = false
    if sequence.kind == 17 && element != 0 && element <= __s0_buffer_len(CheckedTypeRec, store.types) {
        let empty_vec = try __s0_buffer_new(TypeBindingRec, d)
        let no_ancestry_vec = try __s0_buffer_new(DeclAncestryRec, d)
        let element_category = try interpreted_type_category(d, state, parse, store, empty_vec, no_ancestry_vec, element, 0, 0)
        if element_category.category == 2 && vec_element_allows_affine(state, store, element) { affine_elements = true }
    }
    if affine_elements && (builtin == 22 || builtin == 23 || builtin == 24 || builtin == 25) { return expr_token_fail(d, state, base, 141, callee) }
    if builtin == 21 || builtin == 24 {
        if receiver_node.kind != 24 { return expr_token_fail(d, state, base, 101, receiver_node) }
        let local_id = local_lookup(store, owner, receiver_node, state)
        if local_id == 0 { return expr_token_fail(d, state, base, 101, receiver_node) }
        let local = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
        var may_mutate = local.mutable == 1
        // An affine-element vector has no mutable binding form (rule 95), so
        // push targets its owning local binding. A registration captures the
        // vector header at `using` time and a parameter binding has no slot
        // to write a grown header back to, so both stay immutable: grow a
        // plain binding first, then register or transfer the whole vector.
        if affine_elements && builtin == 21 {
            may_mutate = local.kind == 2
            if may_mutate && cleanup_binding_registered(store, owner, local_id) { return expr_token_fail(d, state, base, 142, receiver_node) }
        }
        if !may_mutate { return expr_token_fail(d, state, base, 101, receiver_node) }
    }
    if receiver_node.kind == 24 {
        let local_id = local_lookup(store, owner, receiver_node, state)
        var mode: U64 = 1
        if builtin == 21 { mode = 2 }
        if builtin == 23 { mode = 3 }
        if builtin == 24 || builtin == 25 { mode = 4 }
        if local_id != 0 && lexical_access_conflict(store, owner, local_id, mode) { return expr_token_fail(d, state, base, 92, receiver_node) }
    }
    let u64_type = primitive_type_id(state, parse, store, "U64")
    var current = store
    var first_expression: U64 = 0
    var second_expression: U64 = 0
    if arity != 0 {
        let link = call_link_at(parse, call, 2)
        let argument = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
        var wanted = u64_type
        if builtin == 21 { wanted = element }
        let checked = try check_value_expression_inner(d, state, parse, base, current, owner, argument, link.node, wanted, 42, argument, 0, 0)
        current = match checked {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let draft = match checked {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return expr_deferred(base) }
        first_expression = draft.expression
        if affine_elements && builtin == 21 {
            // The pushed element transfers into the vector, exactly like an
            // aggregate construction part.
            current = try transfer_owned_argument(d, state, parse, current, owner, first_expression)
        }
    }
    if arity == 2 {
        let link = call_link_at(parse, call, 3)
        let argument = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
        let checked = try check_value_expression_inner(d, state, parse, base, current, owner, argument, link.node, u64_type, 42, argument, 0, 0)
        current = match checked {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let draft = match checked {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return expr_deferred(base) }
        second_expression = draft.expression
    }
    var result = u64_type
    if builtin == 21 { result = canonical_type_id(current, 1, 12, 0, 0) }
    if builtin == 22 { let made = try canonical_application(d, current, owner, 9, element, 0, 1)
        current = made.store
        result = made.checked_type }
    if builtin == 23 { let made = try canonical_application(d, current, owner, 8, element, 0, 1)
        current = made.store
        result = made.checked_type }
    if builtin == 24 || builtin == 25 { let made = try canonical_application(d, current, owner, 18, element, 0, 1)
        current = made.store
        result = made.checked_type }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, result) }
    return append_sequence_method(d, current, owner, call_id, result, builtin, receiver_expression, first_expression, second_expression, site_kind, site_syntax)
}

// Ordered-collection key domain (M7.5): the domain the inline structural
// compare lowers. Unsigned integers and Bool compare directly; String and
// Bytes compare through str.eq; records and enums compare through place
// chains, so enum variant payloads, which materialize as values inside the
// scan loop, must be primitives, String, or Bytes.
fn ordered_key_supported(store: CheckStore, checked_type: U64, depth: U64) -> Bool {
    if checked_type == 0 || depth > 16 { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 { return checked.target == 1 || (checked.target >= 6 && checked.target <= 9) }
    if checked.kind == 2 || checked.kind == 14 { return true }
    if checked.kind != 7 { return false }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
    if symbol.type_arity != 0 { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            if use.role == 2 {
                let payload = __s0_buffer_get(CheckedTypeRec, store.types, use.checked_type - 1)
                if payload.kind == 2 || payload.kind == 14 { } else {
                    if payload.kind != 1 { return false }
                    if !(payload.target == 1 || (payload.target >= 6 && payload.target <= 9)) { return false }
                }
            } else {
                if !ordered_key_supported(store, use.checked_type, depth + 1) { return false }
            }
        }
        at = at + 1
    }
    return true
}

// Ordered-collection value domain: recursively copyable ordinary values.
// Slices, mutable views, pointers, bootstrap buffers, and the ordered
// collections themselves stay out until affine composition lands; declared
// types must be non-generic so members are already concrete.
fn ordered_value_copyable(store: CheckStore, checked_type: U64, depth: U64) -> Bool {
    if checked_type == 0 || depth > 16 { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 || checked.kind == 2 || checked.kind == 14 { return true }
    if checked.kind == 9 || checked.kind == 10 || checked.kind == 15 || checked.kind == 17 {
        var child: U64 = 0
        while child < checked.arg_count {
            if !ordered_value_copyable(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), depth + 1) { return false }
            child = child + 1
        }
        return true
    }
    if checked.kind != 7 { return false }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
    if symbol.type_arity != 0 { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            if !ordered_value_copyable(store, use.checked_type, depth + 1) { return false }
        }
        at = at + 1
    }
    return true
}

// Provenance-free value domain for operations that move stored entries
// inside a loop: remove shifts entries in place and values copies them out.
// Mirrors the MIR phase-6 rule that decides whether a loop-carried load
// keeps storage-domain provenance, so nothing accepted here can be refused
// by the verifier later.
fn ordered_value_storage_free(store: CheckStore, checked_type: U64, depth: U64) -> Bool {
    if checked_type == 0 || depth > 16 { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 { return true }
    if checked.kind == 9 || checked.kind == 10 || checked.kind == 15 {
        var child: U64 = 0
        while child < checked.arg_count {
            if !ordered_value_storage_free(store, __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), depth + 1) { return false }
            child = child + 1
        }
        return true
    }
    if checked.kind != 7 { return false }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
    if symbol.type_arity != 0 { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            if !ordered_value_storage_free(store, use.checked_type, depth + 1) { return false }
        }
        at = at + 1
    }
    return true
}

// Map.new(K, V) and Set.new(T) create empty ordered collections. The static
// receiver link (Map/Set) is associated, so the call links are the callee
// followed by the type operands alone, the Vec.new convention.
fn check_ordered_static_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 30
    var want_args: U64 = 2
    let static_link = __s0_buffer_get(SyntaxLinkRec, parse.links, callee.children - 1)
    let static_node = __s0_buffer_get(SyntaxRec, parse.nodes, static_link.node - 1)
    if static_node.kind == 24 && node_word(state, static_node, "Set") { identity = 37
        want_args = 1 }
    if call_link_count(parse, call) != want_args + 1 { return expr_token_fail(d, state, base, 144, call) }
    let key_link = call_link_at(parse, call, 1)
    let resolved_key = try resolve_expression_type(d, state, parse, store, owner, key_link.node)
    var current = match resolved_key {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved_key {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(ExprBad(current)) }
    let key = checked_type_for_syntax(current, owner, key_link.node)
    var value: U64 = 0
    if identity == 30 {
        let value_link = call_link_at(parse, call, 2)
        let resolved_value = try resolve_expression_type(d, state, parse, current, owner, value_link.node)
        current = match resolved_value {
            CheckGood(value2) => value2
            CheckBad(value2) => value2
        }
        if match resolved_value {
            CheckGood(value2) => false
            CheckBad(value2) => true
        } { return Ok(ExprBad(current)) }
        value = checked_type_for_syntax(current, owner, value_link.node)
    }
    if !ordered_key_supported(current, key, 0) { return expr_token_single_type_fail(d, state, current, 127, __s0_buffer_get(SyntaxRec, parse.nodes, key_link.node - 1), key) }
    if identity == 30 && !ordered_value_copyable(current, value, 0) { return expr_token_single_type_fail(d, state, current, 128, __s0_buffer_get(SyntaxRec, parse.nodes, call_link_at(parse, call, 2).node - 1), value) }
    if identity == 37 && !ordered_value_copyable(current, key, 0) { return expr_token_single_type_fail(d, state, current, 128, __s0_buffer_get(SyntaxRec, parse.nodes, key_link.node - 1), key) }
    var kind: U64 = 23
    if identity == 37 { kind = 24 }
    let made = try canonical_application(d, current, owner, kind, key, value, want_args)
    current = made.store
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, made.checked_type, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, made.checked_type) }
    return append_builtin_expression(d, parse, current, owner, call_id, made.checked_type, identity, call, want_args + 1, site_kind, site_syntax)
}

fn check_ordered_method_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, receiver_expression: U64, builtin: U64, key: U64, value: U64, ordinal: U64, prior_first: U64, prior_second: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var want_arity: U64 = 0
    if builtin == 32 || builtin == 38 || builtin == 39 || builtin == 33 || builtin == 40 { want_arity = 1 }
    if builtin == 31 { want_arity = 2 }
    if ordinal == want_arity {
        var current = store
        var result = primitive_type_id(state, parse, current, "Bool")
        if builtin == 34 || builtin == 41 { result = primitive_type_id(state, parse, current, "U64") }
        if builtin == 32 {
            let made = try canonical_application(d, current, owner, 9, value, 0, 1)
            current = made.store
            result = made.checked_type
        }
        if builtin == 35 || builtin == 36 || builtin == 42 {
            var element = key
            if builtin == 36 { element = value }
            let made = try canonical_application(d, current, owner, 17, element, 0, 1)
            current = made.store
            result = made.checked_type
        }
        if expected != 0 && !(try expression_type_equal(d, state, parse, current, result, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, result) }
        return append_sequence_method(d, current, owner, call_id, result, builtin, receiver_expression, prior_first, prior_second, site_kind, site_syntax)
    }
    // Method-call links include the callee and the receiver before the
    // runtime operands.
    let link = call_link_at(parse, call, ordinal + 2)
    let argument = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    var wanted = key
    if builtin == 31 && ordinal == 1 { wanted = value }
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, argument, link.node, wanted, 42, argument, 0, 0)
    let current = match checked {
        ExprGood(value2) => value2.store
        ExprBad(value2) => value2
    }
    if match checked {
        ExprGood(value2) => false
        ExprBad(value2) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked {
        ExprGood(value2) => value2.draft
        ExprBad(value2) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    var first = prior_first
    var second = prior_second
    if ordinal == 0 { first = draft.expression } else { second = draft.expression }
    return check_ordered_method_args(d, state, parse, base, current, owner, call, call_id, callee, receiver_expression, builtin, key, value, ordinal + 1, first, second, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_ordered_method(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, receiver_node: SyntaxRec, receiver_type_id: U64, receiver_expression: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let receiver = __s0_buffer_get(CheckedTypeRec, store.types, receiver_type_id - 1)
    if receiver.kind != 23 && receiver.kind != 24 { return expr_token_fail(d, state, base, 61, callee) }
    var builtin: U64 = 0
    var arity: U64 = 0
    if receiver.kind == 23 {
        if node_word(state, callee, "insert") { builtin = 31
            arity = 2 }
        if node_word(state, callee, "get") { builtin = 32
            arity = 1 }
        if node_word(state, callee, "remove") { builtin = 33
            arity = 1 }
        if node_word(state, callee, "len") { builtin = 34 }
        if node_word(state, callee, "keys") { builtin = 35 }
        if node_word(state, callee, "values") { builtin = 36 }
    }
    if receiver.kind == 24 {
        if node_word(state, callee, "insert") { builtin = 38
            arity = 1 }
        if node_word(state, callee, "contains") { builtin = 39
            arity = 1 }
        if node_word(state, callee, "remove") { builtin = 40
            arity = 1 }
        if node_word(state, callee, "len") { builtin = 41 }
        if node_word(state, callee, "items") { builtin = 42 }
    }
    if builtin == 0 { return expr_token_fail(d, state, base, 61, callee) }
    if call_link_count(parse, call) != arity + 2 { return expr_token_fail(d, state, base, 144, call) }
    if builtin == 31 || builtin == 38 || builtin == 33 || builtin == 40 {
        if receiver_node.kind != 24 { return expr_token_fail(d, state, base, 101, receiver_node) }
        let local_id = local_lookup(store, owner, receiver_node, state)
        if local_id == 0 || __s0_buffer_get(LocalRec, store.locals, local_id - 1).mutable == 0 { return expr_token_fail(d, state, base, 101, receiver_node) }
    }
    if receiver_node.kind == 24 {
        let local_id = local_lookup(store, owner, receiver_node, state)
        var mode: U64 = 1
        if builtin == 31 || builtin == 38 || builtin == 33 || builtin == 40 { mode = 2 }
        if local_id != 0 && lexical_access_conflict(store, owner, local_id, mode) { return expr_token_fail(d, state, base, 92, receiver_node) }
    }
    let key = __s0_buffer_get(U64, store.type_args, receiver.first_arg - 1)
    var value: U64 = 0
    if receiver.kind == 23 { value = __s0_buffer_get(U64, store.type_args, receiver.first_arg) }
    // remove, keys, values, and items move stored values through a lowering
    // loop; only provenance-free types can cross that loop's backedge today.
    // Map remove moves whole entries, so both halves must be free.
    if builtin == 33 {
        if !ordered_value_storage_free(store, value, 0) { return expr_token_single_type_fail(d, state, store, 129, callee, value) }
        if !ordered_value_storage_free(store, key, 0) { return expr_token_single_type_fail(d, state, store, 129, callee, key) }
    }
    if builtin == 40 && !ordered_value_storage_free(store, key, 0) { return expr_token_single_type_fail(d, state, store, 129, callee, key) }
    if (builtin == 35 || builtin == 42) && !ordered_value_storage_free(store, key, 0) { return expr_token_single_type_fail(d, state, store, 129, callee, key) }
    if builtin == 36 && !ordered_value_storage_free(store, value, 0) { return expr_token_single_type_fail(d, state, store, 129, callee, value) }
    return check_ordered_method_args(d, state, parse, base, store, owner, call, call_id, callee, receiver_expression, builtin, key, value, 0, 0, 0, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_map_runtime_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, identity: U64, ordinal: U64, first_runtime: U64, runtime_count: U64, map_type: U64, key: U64, value: U64, result: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == runtime_count {
        if expected != 0 && !(try expression_type_equal(d, state, parse, store, result, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_builtin_expression(d, parse, store, owner, call_id, result, identity, call, first_runtime, site_kind, site_syntax)
    }
    let link = call_link_at(parse, call, first_runtime + ordinal + 1)
    let argument = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    var wanted = map_type
    if ordinal == 1 { wanted = key }
    if identity == 15 && ordinal == 2 { wanted = value }
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, argument, link.node, wanted, 42, argument, 0, 0)
    let current = match checked {
        ExprGood(v) => v.store
        ExprBad(v) => v
    }
    if match checked {
        ExprGood(v) => false
        ExprBad(v) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked {
        ExprGood(v) => v.draft
        ExprBad(v) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    if !(try expression_type_equal(d, state, parse, current, draft.checked_type, wanted)) { return expr_token_fail(d, state, base, 42, argument) }
    return check_map_runtime_args(d, state, parse, base, current, owner, call, call_id, identity, ordinal + 1, first_runtime, runtime_count, map_type, key, value, result, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_map_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 14
    var runtime_count: U64 = 2
    if node_word(state, callee, "Set") { identity = 15
        runtime_count = 3 }
    if node_word(state, callee, "Remove") { identity = 16 }
    let total = call_link_count(parse, call) - 1
    var type_operands: U64 = 0
    if total > 0 {
        let first = call_link_at(parse, call, 1)
        if expression_type_candidate(state, parse, store, owner, first.node) { type_operands = 2 }
    }
    if total != runtime_count + type_operands { return expr_token_fail(d, state, base, 41, call) }
    var current = store
    var key: U64 = 0
    var value: U64 = 0
    if type_operands == 2 {
        let key_link = call_link_at(parse, call, 1)
        let resolved_key = try resolve_expression_type(d, state, parse, current, owner, key_link.node)
        current = match resolved_key {
            CheckGood(v) => v
            CheckBad(v) => v
        }
        if match resolved_key {
            CheckGood(v) => false
            CheckBad(v) => true
        } { return Ok(ExprBad(current)) }
        key = checked_type_for_syntax(current, owner, key_link.node)
        let value_link = call_link_at(parse, call, 2)
        let resolved_value = try resolve_expression_type(d, state, parse, current, owner, value_link.node)
        current = match resolved_value {
            CheckGood(v) => v
            CheckBad(v) => v
        }
        if match resolved_value {
            CheckGood(v) => false
            CheckBad(v) => true
        } { return Ok(ExprBad(current)) }
        value = checked_type_for_syntax(current, owner, value_link.node)
    }
    let map_link = call_link_at(parse, call, type_operands + 1)
    let map_node = __s0_buffer_get(SyntaxRec, parse.nodes, map_link.node - 1)
    let checked_map = try check_value_expression_inner(d, state, parse, base, current, owner, map_node, map_link.node, 0, 42, map_node, 0, 0)
    current = match checked_map {
        ExprGood(v) => v.store
        ExprBad(v) => v
    }
    if match checked_map {
        ExprGood(v) => false
        ExprBad(v) => true
    } { return Ok(ExprBad(current)) }
    let map_draft = match checked_map {
        ExprGood(v) => v.draft
        ExprBad(v) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if map_draft.deferred { return expr_deferred(base) }
    let map_checked = __s0_buffer_get(CheckedTypeRec, current.types, map_draft.checked_type - 1)
    if map_checked.kind != 11 { return expr_token_fail(d, state, base, 42, map_node) }
    let inferred_key = __s0_buffer_get(U64, current.type_args, map_checked.first_arg - 1)
    let inferred_value = __s0_buffer_get(U64, current.type_args, map_checked.first_arg)
    if type_operands == 0 { key = inferred_key
        value = inferred_value
    } else {
        if !(try expression_type_equal(d, state, parse, current, key, inferred_key)) || !(try expression_type_equal(d, state, parse, current, value, inferred_value)) { return expr_token_fail(d, state, base, 42, map_node) }
    }
    var result = canonical_type_id(current, 1, 12, 0, 0)
    if identity == 14 {
        let made = try canonical_application(d, current, owner, 9, value, 0, 1)
        current = made.store
        result = made.checked_type
    }
    if identity == 16 { result = primitive_type_id(state, parse, current, "Bool") }
    // The map expression was checked first for inference; continue with the
    // remaining runtime operands without checking or recording it twice.
    return check_map_runtime_args(d, state, parse, base, current, owner, call, call_id, identity, 1, type_operands, runtime_count, map_draft.checked_type, key, value, result, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_s0_runtime_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, identity: U64, ordinal: U64, arity: U64, type_operands: U64, domain_type: U64, mark_type: U64, buffer_type: U64, element: U64, u64_type: U64, result: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == arity {
        if expected != 0 && !(try expression_type_equal(d, state, parse, store, result, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_builtin_expression(d, parse, store, owner, call_id, result, identity, call, type_operands, site_kind, site_syntax)
    }
    let link = call_link_at(parse, call, ordinal + 1)
    let argument = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    var wanted = domain_type
    if identity == 3 && ordinal == 2 { wanted = u64_type }
    if identity == 6 && ordinal == 1 { wanted = mark_type }
    if (identity == 10 || identity == 12 || identity == 13 || identity == 17) && ordinal == 1 { wanted = buffer_type }
    if identity == 11 && ordinal == 2 { wanted = buffer_type }
    if identity == 11 && ordinal == 3 { wanted = element }
    if (identity == 12 || identity == 17) && ordinal == 2 { wanted = u64_type }
    if identity == 17 && ordinal == 3 { wanted = element }
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, argument, link.node, wanted, 42, argument, 0, 0)
    let current = match checked {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(current)) }
    let draft = match checked {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return expr_deferred(base) }
    if !(try expression_type_equal(d, state, parse, current, draft.checked_type, wanted)) { return expr_token_fail(d, state, base, 42, argument) }
    if identity == 7 && ordinal == 0 {
        let consumed = __s0_buffer_get(CheckedExprRec, current.expressions, draft.expression - 1)
        if consumed.kind != 1 && consumed.kind != 5 { return expr_token_fail(d, state, base, 92, argument) }
        let binding = __s0_buffer_get(LocalRec, current.locals, consumed.parameter_use - 1)
        var owned = binding.kind == 2
        if binding.kind == 1 && __s0_buffer_get(SyntaxRec, parse.nodes, binding.syntax - 1).kind == 48 { owned = true }
        if !owned { return expr_token_fail(d, state, base, 92, argument) }
        __s0_buffer_set(CheckedExprRec, current.expressions, draft.expression - 1, CheckedExprRec(owner: consumed.owner, owner_previous: consumed.owner_previous, syntax: consumed.syntax, kind: 22, checked_type: consumed.checked_type, parameter_use: consumed.parameter_use, bool_value: consumed.bool_value, left: consumed.left, right: consumed.right, annotation: consumed.annotation, first_child: consumed.first_child, child_count: consumed.child_count, operator: consumed.operator, site_kind: consumed.site_kind, site_syntax: consumed.site_syntax))
    }
    return check_s0_runtime_args(d, state, parse, base, current, owner, call, call_id, identity, ordinal + 1, arity, type_operands, domain_type, mark_type, buffer_type, element, u64_type, result, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_s0_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 0
    var arity: U64 = 0
    var type_operands: U64 = 0
    if node_word(state, callee, "__s0_alloc") { identity = 3
        arity = 3
        type_operands = 1 }
    if node_word(state, callee, "__s0_domain_create") { identity = 4
        arity = 1 }
    if node_word(state, callee, "__s0_domain_mark") { identity = 5
        arity = 1 }
    if node_word(state, callee, "__s0_domain_reset") { identity = 6
        arity = 2 }
    if node_word(state, callee, "__s0_domain_destroy") { identity = 7
        arity = 1 }
    if node_word(state, callee, "__s0_map_create") { identity = 8
        arity = 2
        type_operands = 1 }
    if node_word(state, callee, "__s0_buffer_new") { identity = 9
        arity = 2
        type_operands = 1 }
    if node_word(state, callee, "__s0_buffer_len") { identity = 10
        arity = 2
        type_operands = 1 }
    if node_word(state, callee, "__s0_buffer_append") { identity = 11
        arity = 4
        type_operands = 1 }
    if node_word(state, callee, "__s0_buffer_get") { identity = 12
        arity = 3
        type_operands = 1 }
    if node_word(state, callee, "__s0_buffer_slice") { identity = 13
        arity = 2
        type_operands = 1 }
    if node_word(state, callee, "__s0_buffer_set") { identity = 17
        arity = 4
        type_operands = 1 }
    if identity == 0 { return expr_token_fail(d, state, base, 40, call) }
    if call_link_count(parse, call) != arity + 1 { return expr_token_fail(d, state, base, 41, call) }

    var current = store
    var element: U64 = 0
    if type_operands == 1 {
        let type_link = call_link_at(parse, call, 1)
        let resolved = try resolve_expression_type(d, state, parse, current, owner, type_link.node)
        current = match resolved {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        if match resolved {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(ExprBad(current)) }
        element = checked_type_for_syntax(current, owner, type_link.node)
        if identity == 8 && __s0_buffer_get(CheckedTypeRec, current.types, element - 1).kind != 11 {
            let type_node = __s0_buffer_get(SyntaxRec, parse.nodes, type_link.node - 1)
            return expr_token_fail(d, state, base, 42, type_node)
        }
        let empty_bindings = try __s0_buffer_new(TypeBindingRec, d)
        let empty_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
        if identity == 8 {
            let map_type = __s0_buffer_get(CheckedTypeRec, current.types, element - 1)
            let key = __s0_buffer_get(U64, current.type_args, map_type.first_arg - 1)
            let value = __s0_buffer_get(U64, current.type_args, map_type.first_arg)
            let type_node = __s0_buffer_get(SyntaxRec, parse.nodes, type_link.node - 1)
            if !(try interpreted_map_key_ok(d, state, parse, current, empty_bindings, empty_ancestry, key, 0, 0, __s0_buffer_len(SymbolRec, current.symbols))) { return expr_token_single_type_fail(d, state, current, 12, type_node, key) }
            if try interpreted_contains_reference(d, state, parse, current, empty_bindings, empty_ancestry, value, 0, 0, __s0_buffer_len(SymbolRec, current.symbols)) { return expr_token_single_type_fail(d, state, current, 13, type_node, value) }
        }
        if identity != 8 && try interpreted_contains_reference(d, state, parse, current, empty_bindings, empty_ancestry, element, 0, 0, 0) {
            let type_node = __s0_buffer_get(SyntaxRec, parse.nodes, type_link.node - 1)
            return expr_token_fail(d, state, base, 11, type_node)
        }
    }

    let domain_leaf = try canonical_leaf(d, current, 3, 0)
    current = domain_leaf.store
    let domain_type = domain_leaf.checked_type
    let mark_leaf = try canonical_leaf(d, current, 4, 0)
    current = mark_leaf.store
    let mark_type = mark_leaf.checked_type
    let error_leaf = try canonical_leaf(d, current, 5, 0)
    current = error_leaf.store
    let error_type = error_leaf.checked_type
    let u64_type = primitive_type_id(state, parse, current, "U64")
    let unit_leaf = try canonical_leaf(d, current, 1, 12)
    current = unit_leaf.store
    let unit_type = unit_leaf.checked_type
    var buffer_type: U64 = 0
    if type_operands == 1 {
        let made = try canonical_application(d, current, owner, 13, element, 0, 1)
        current = made.store
        buffer_type = made.checked_type
    }
    var result = unit_type
    if identity == 3 {
        let made = try canonical_application(d, current, owner, 8, element, 0, 1)
        current = made.store
        result = made.checked_type
    }
    if identity == 4 { result = domain_type }
    if identity == 5 { result = mark_type }
    if identity == 8 { result = element }
    if identity == 9 || identity == 11 {
        let made = try canonical_application(d, current, owner, 10, buffer_type, error_type, 2)
        current = made.store
        result = made.checked_type
    }
    if identity == 10 { result = u64_type }
    if identity == 12 { result = element }
    if identity == 13 {
        let made = try canonical_application(d, current, owner, 8, element, 0, 1)
        current = made.store
        result = made.checked_type
    }

    return check_s0_runtime_args(d, state, parse, base, current, owner, call, call_id, identity, type_operands, arity, type_operands, domain_type, mark_type, buffer_type, element, u64_type, result, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_ordinary_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let callee_link = call_link_at(parse, call, 0)
    let callee = __s0_buffer_get(SyntaxRec, parse.nodes, callee_link.node - 1)
    // Indirect call: a plain word callee that names a local binding of
    // function type. Children are the callee value followed by the runtime
    // arguments; builtin 44 lowers through call.value.
    if callee.kind == 24 {
        let local_id = local_lookup(store, owner, callee, state)
        if local_id != 0 {
            let binding = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
            let binding_type = __s0_buffer_get(CheckedTypeRec, store.types, binding.checked_type - 1)
            if binding_type.kind == 25 { return check_indirect_call(d, state, parse, base, store, owner, call, call_id, callee, binding.checked_type, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        }
    }
    if callee.kind != 24 && callee.kind != 29 {
        if callee.kind == 27 {
            let applied_callee_link = call_link_at(parse, callee, 0)
            let applied_callee = __s0_buffer_get(SyntaxRec, parse.nodes, applied_callee_link.node - 1)
            if applied_callee.kind != 24 { return expr_token_fail(d, state, base, 40, call) }
            let applied_target = symbol_named(state, parse, store, applied_callee)
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
                let applied_type = checked_type_for_syntax(current, owner, callee_link.node)
                if expected != 0 && !(try expression_type_equal(d, state, parse, current, applied_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
                return check_record_call(d, state, parse, base, current, owner, call, call_id, applied_target, applied_type, mismatch_kind, mismatch_node, site_kind, site_syntax)
            }
            return expr_token_fail(d, state, base, 56, callee)
        }
        return expr_token_fail(d, state, base, 40, call)
    }
    if callee.kind == 29 && (node_word(state, callee, "new") || node_word(state, callee, "from_array")) {
        let static_link = __s0_buffer_get(SyntaxLinkRec, parse.links, callee.children - 1)
        let static_node = __s0_buffer_get(SyntaxRec, parse.nodes, static_link.node - 1)
        if static_node.kind == 24 && node_word(state, static_node, "Vec") { return check_vec_static_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if node_word(state, callee, "new") && static_node.kind == 24 && (node_word(state, static_node, "Set") || (node_word(state, static_node, "Map") && !check_bootstrap_private())) { return check_ordered_static_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if static_node.kind == 24 && node_word(state, static_node, "Table") && node_word(state, callee, "new") { return check_table_static_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    }
    if callee.kind == 29 && symbol_named(state, parse, store, callee) == 0 {
        let receiver_link = __s0_buffer_get(SyntaxLinkRec, parse.links, callee.children - 1)
        let receiver_node = __s0_buffer_get(SyntaxRec, parse.nodes, receiver_link.node - 1)
        let static_owner = symbol_named(state, parse, store, receiver_node)
        if static_owner != 0 {
            let static_symbol = __s0_buffer_get(SymbolRec, store.symbols, static_owner - 1)
            if static_symbol.kind == 2 || static_symbol.kind == 3 {
                let target = inherent_symbol_named(state, parse, store, callee, static_owner, false)
                if target == 0 { return expr_token_fail(d, state, base, 61, callee) }
                return check_function_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
            }
        }
        let checked_receiver = try check_value_expression_inner(d, state, parse, base, store, owner, receiver_node, receiver_link.node, 0, 60, callee, 0, 0)
        let current = match checked_receiver {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_receiver {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let receiver_draft = match checked_receiver {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if receiver_draft.deferred { return expr_deferred(base) }
        let receiver_type = __s0_buffer_get(CheckedTypeRec, current.types, receiver_draft.checked_type - 1)
        if receiver_type.kind == 19 { return check_table_method(d, state, parse, base, current, owner, call, call_id, callee, receiver_node, receiver_draft.checked_type, receiver_draft.expression, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if receiver_type.kind == 23 || receiver_type.kind == 24 { return check_ordered_method(d, state, parse, base, current, owner, call, call_id, callee, receiver_node, receiver_draft.checked_type, receiver_draft.expression, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if node_word(state, callee, "len") || node_word(state, callee, "push") || node_word(state, callee, "get") || node_word(state, callee, "slice") || node_word(state, callee, "slice_mut") || node_word(state, callee, "subview") {
            return check_sequence_method(d, state, parse, base, current, owner, call, call_id, callee, receiver_node, receiver_draft.checked_type, receiver_draft.expression, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
        }
        if receiver_type.kind != 7 { return expr_token_fail(d, state, base, 61, callee) }
        let target = inherent_symbol_named(state, parse, current, callee, receiver_type.target, true)
        if target == 0 {
            // Static trait dispatch: inherent methods win, then the unique
            // trait implementation providing this method name resolves.
            let trait_method = trait_receiver_method(state, parse, current, receiver_type, callee)
            if trait_method.ambiguous { return expr_token_fail(d, state, base, 119, callee) }
            if trait_method.target != 0 { return check_function_call(d, state, parse, base, store, owner, call, call_id, trait_method.target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
            if trait_method.defaulted { return expr_token_fail(d, state, base, 120, callee) }
            if trait_impl_for_builtin_type(current, 1, receiver_draft.checked_type) != 0 || trait_impl_for_builtin_type(current, 2, receiver_draft.checked_type) != 0 {
                if node_word(state, callee, "eq") || node_word(state, callee, "hash") { return expr_token_fail(d, state, base, 126, callee) }
            }
            return expr_token_fail(d, state, base, 61, callee)
        }
        return check_function_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
    }
    if callee.kind == 24 && (node_word(state, callee, "len") || node_word(state, callee, "range")) { return check_slice_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if node_word(state, callee, "Get") || node_word(state, callee, "Set") || node_word(state, callee, "Remove") {
        if !check_bootstrap_private() { return expr_token_fail(d, state, base, 106, callee) }
        return check_map_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
    }
    if node_word(state, callee, "__s0_alloc") || node_word(state, callee, "__s0_domain_create") || node_word(state, callee, "__s0_domain_mark") || node_word(state, callee, "__s0_domain_reset") || node_word(state, callee, "__s0_domain_destroy") || node_word(state, callee, "__s0_map_create") || node_word(state, callee, "__s0_buffer_new") || node_word(state, callee, "__s0_buffer_len") || node_word(state, callee, "__s0_buffer_append") || node_word(state, callee, "__s0_buffer_get") || node_word(state, callee, "__s0_buffer_set") || node_word(state, callee, "__s0_buffer_slice") {
        if !check_bootstrap_private() { return expr_token_fail(d, state, base, 106, callee) }
        return check_s0_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
    }
    if node_word(state, callee, "Some") || node_word(state, callee, "Ok") || node_word(state, callee, "Err") {
        if expected == 0 { return expr_token_fail(d, state, base, 40, call) }
        let concrete = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
        if concrete.kind != 9 && concrete.kind != 10 { return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if call_link_count(parse, call) != 2 { return expr_token_fail(d, state, base, 49, call) }
        var kind: U64 = 0
        var payload_type: U64 = 0
        if concrete.kind == 9 && node_word(state, callee, "Some") {
            kind = 15
            payload_type = __s0_buffer_get(U64, store.type_args, concrete.first_arg - 1)
        }
        if concrete.kind == 10 && node_word(state, callee, "Ok") {
            kind = 16
            payload_type = __s0_buffer_get(U64, store.type_args, concrete.first_arg - 1)
        }
        if concrete.kind == 10 && node_word(state, callee, "Err") {
            kind = 17
            payload_type = __s0_buffer_get(U64, store.type_args, concrete.first_arg)
        }
        if kind == 0 { return expr_token_fail(d, state, base, 40, call) }
        if !(try checked_type_views_materializable(d, state, parse, store, payload_type)) { return expr_token_fail(d, state, base, 104, call) }
        let argument_link = call_link_at(parse, call, 1)
        let argument = __s0_buffer_get(SyntaxRec, parse.nodes, argument_link.node - 1)
        let checked_argument = try check_value_expression_inner(d, state, parse, base, store, owner, argument, argument_link.node, payload_type, mismatch_kind, mismatch_node, 0, 0)
        let current = match checked_argument {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_argument {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let draft = match checked_argument {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return expr_deferred(base) }
        let transferred = try transfer_owned_argument(d, state, parse, current, owner, draft.expression)
        return append_expression(d, transferred, owner, call_id, kind, expected, 0, 0, draft.expression, 0, 0, site_kind, site_syntax)
    }
    let target = symbol_named(state, parse, store, callee)
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
    let target = symbol_named(state, parse, store, callee)
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

fn check_array_elements(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, link_id: U64, element_type: U64, array_node: SyntaxRec) -> Result(ArrayElementsOutcome, __s0_Error) {
    if link_id == 0 { return Ok(ArrayElementsGood(ArrayElementsRec(store: store, element_type: element_type, first_child: 0, child_count: 0))) }
    let link = __s0_buffer_get(SyntaxLinkRec, parse.links, link_id - 1)
    let before = try check_array_elements(d, state, parse, base, store, owner, link.next, element_type, array_node)
    let prior = match before {
        ArrayElementsGood(value) => value
        ArrayElementsBad(value) => ArrayElementsRec(store: value, element_type: 0, first_child: 0, child_count: 0)
        ArrayElementsDefer => ArrayElementsRec(store: base, element_type: 0, first_child: 0, child_count: 0)
    }
    if match before {
        ArrayElementsGood(value) => false
        ArrayElementsBad(value) => true
        ArrayElementsDefer => false
    } { return Ok(ArrayElementsBad(prior.store)) }
    if match before {
        ArrayElementsGood(value) => false
        ArrayElementsBad(value) => false
        ArrayElementsDefer => true
    } { return Ok(ArrayElementsDefer) }
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, link.node - 1)
    let checked = try check_value_expression_inner(d, state, parse, base, prior.store, owner, node, link.node, prior.element_type, 98, array_node, 0, 0)
    let current = match checked {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ArrayElementsBad(current)) }
    let draft = match checked {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if draft.deferred { return Ok(ArrayElementsDefer) }
    let transferred = try transfer_owned_argument(d, state, parse, current, owner, draft.expression)
    var actual_element = prior.element_type
    if actual_element == 0 { actual_element = draft.checked_type }
    // Element child records are appended by the array-literal branch after
    // every element is checked, so the literal's child window stays
    // contiguous and in source order even when elements have their own
    // child records.
    return Ok(ArrayElementsGood(ArrayElementsRec(store: transferred, element_type: actual_element, first_child: 0, child_count: prior.child_count + 1)))
}

fn append_array_expression(d: Domain, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, first_child: U64, child_count: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let expressions = try __s0_buffer_append(CheckedExprRec, d, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 23, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: 0, first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
    return expr_draft(next, checked_type, __s0_buffer_len(CheckedExprRec, expressions))
}

// Shared recursive value-expression slice for returns, binding initializers,
// and assignment values. The base store is retained across the whole traversal
// so a deferred shape or semantic failure cannot expose a partial graph.
fn check_value_expression_inner(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, expression: SyntaxRec, expression_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if expression.kind == 58 { return check_closure_expression(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 27 { return check_ordinary_call(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 36 { return check_unsafe_call(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 50 {
        let count = type_arg_count(parse, expression.children)
        var array_type = expected
        var element_type: U64 = 0
        if expected != 0 {
            let checked = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
            if checked.kind != 15 || checked.arg_count != 1 { return expr_token_fail(d, state, base, 97, expression) }
            if checked.target != count { return expr_token_fail(d, state, base, 98, expression) }
            element_type = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
        } else { if count == 0 { return expr_token_fail(d, state, base, 97, expression) } }
        let elements = try check_array_elements(d, state, parse, base, store, owner, expression.children, element_type, expression)
        let values = match elements {
            ArrayElementsGood(value) => value
            ArrayElementsBad(value) => ArrayElementsRec(store: value, element_type: 0, first_child: 0, child_count: 0)
            ArrayElementsDefer => ArrayElementsRec(store: base, element_type: 0, first_child: 0, child_count: 0)
        }
        if match elements {
            ArrayElementsGood(value) => false
            ArrayElementsBad(value) => true
            ArrayElementsDefer => false
        } { return Ok(ExprBad(values.store)) }
        if match elements {
            ArrayElementsGood(value) => false
            ArrayElementsBad(value) => false
            ArrayElementsDefer => true
        } { return expr_deferred(base) }
        if !(try checked_type_views_materializable(d, state, parse, values.store, values.element_type)) { return expr_token_fail(d, state, base, 104, expression) }
        var current = values.store
        if array_type == 0 {
            array_type = canonical_single_arg(current, 15, count, values.element_type)
            if array_type == 0 {
                let first = __s0_buffer_len(U64, current.type_args) + 1
                let args = try __s0_buffer_append(U64, d, current.type_args, values.element_type)
                current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
                current = try append_checked_type(d, current, 0, 15, 0, count, first, 1)
                array_type = canonical_single_arg(current, 15, count, values.element_type)
            }
        }
        var children = current.expression_children
        var first_child: U64 = 0
        var child_count: U64 = 0
        var ordinal: U64 = 0
        let link_count = call_link_count(parse, expression)
        while ordinal < link_count {
            let link = call_link_at(parse, expression, ordinal)
            let element = expression_for_syntax(current, owner, link.node)
            if element != 0 {
                if child_count == 0 { first_child = __s0_buffer_len(CheckedExprChildRec, children) + 1 }
                children = try __s0_buffer_append(CheckedExprChildRec, d, children, CheckedExprChildRec(expression: element))
                child_count = child_count + 1
            }
            ordinal = ordinal + 1
        }
        let with_children = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
        return append_array_expression(d, with_children, owner, expression_id, array_type, first_child, child_count, site_kind, site_syntax)
    }
    if expression.kind == 29 {
        let base_link = __s0_buffer_get(SyntaxLinkRec, parse.links, expression.children - 1)
        let base_node = __s0_buffer_get(SyntaxRec, parse.nodes, base_link.node - 1)
        let checked_base = try check_value_expression_inner(d, state, parse, base, store, owner, base_node, base_link.node, 0, 60, expression, 0, 0)
        let current = match checked_base {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_base {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let base_draft = match checked_base {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if base_draft.deferred { return expr_deferred(base) }
        let base_type = __s0_buffer_get(CheckedTypeRec, current.types, base_draft.checked_type - 1)
        // A table view reads the fields of its element; the element of a
        // concrete table is a declared struct.
        var aggregate_root = base_draft.checked_type
        if base_type.kind == 21 || base_type.kind == 22 { aggregate_root = __s0_buffer_get(U64, current.type_args, base_type.first_arg - 1) }
        let aggregate = __s0_buffer_get(CheckedTypeRec, current.types, aggregate_root - 1)
        if aggregate.kind != 7 || __s0_buffer_get(SymbolRec, current.symbols, aggregate.target - 1).kind != 2 { return expr_fail(d, base, 60, expression) }
        let field = field_use_named(state, current, aggregate.target, expression)
        if field == 0 { return expr_fail(d, base, 61, expression) }
        let concrete = try concrete_field_type(d, current, aggregate_root, field)
        if expected != 0 && !(try expression_type_equal(d, state, parse, concrete.store, concrete.checked_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, concrete.store, owner, expression_id, 21, concrete.checked_type, field, 0, base_draft.expression, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 30 {
        let index_link = __s0_buffer_get(SyntaxLinkRec, parse.links, expression.children - 1)
        let base_link = __s0_buffer_get(SyntaxLinkRec, parse.links, index_link.next - 1)
        let base_node = __s0_buffer_get(SyntaxRec, parse.nodes, base_link.node - 1)
        let checked_base = try check_value_expression_inner(d, state, parse, base, store, owner, base_node, base_link.node, 0, 83, expression, 0, 0)
        let current = match checked_base {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_base {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let base_draft = match checked_base {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if base_draft.deferred { return expr_deferred(base) }
        var element = sequence_element_type(state, parse, current, base_draft.checked_type)
        if element == 0 { return expr_token_fail(d, state, base, 83, expression) }
        let u64_type = primitive_type_id(state, parse, current, "U64")
        let index_node = __s0_buffer_get(SyntaxRec, parse.nodes, index_link.node - 1)
        let checked_index = try check_value_expression_inner(d, state, parse, base, current, owner, index_node, index_link.node, u64_type, 84, expression, 0, 0)
        let next = match checked_index {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_index {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(next)) }
        let index_draft = match checked_index {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if index_draft.deferred { return expr_deferred(base) }
        if expected != 0 && !(try expression_type_equal(d, state, parse, next, element, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, next, owner, expression_id, 19, element, 0, 0, base_draft.expression, index_draft.expression, 0, site_kind, site_syntax)
    }
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
            if !limits.signed {
                let detail = diagnostic_type(store, literal_type)
                let failed = try check_token_detail_fail(d, state, base, 21, expression, detail.kind, detail.target, 0, 0)
                let bad = match failed {
                    CheckGood(value) => value
                    CheckBad(value) => value
                }
                return Ok(ExprBad(bad))
            }
            limit = limits.negative
        }
        if !digits_at_most(state.values, magnitude, token.value_end, limit) {
            let detail = diagnostic_type(store, literal_type)
            let failed = try check_token_detail_fail(d, state, base, 21, expression, detail.kind, detail.target, 0, 0)
            let bad = match failed {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            return Ok(ExprBad(bad))
        }
        return append_expression(d, store, owner, expression_id, 3, literal_type, 0, 0, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 21 {
        var literal_type = expected
        if literal_type == 0 { literal_type = primitive_type_id(state, parse, store, "F64") }
        if literal_type == 0 { return expr_deferred(base) }
        if !float_type(state, parse, store, literal_type) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, store, owner, expression_id, 20, literal_type, 0, 0, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 22 {
        var string_store = store
        var string_type = expected
        if string_type == 0 {
            string_type = canonical_type_id(store, 2, 0, 0, 0)
            if string_type == 0 {
                string_store = try append_checked_type(d, store, owner, 2, 0, 0, 0, 0)
                string_type = canonical_type_id(string_store, 2, 0, 0, 0)
            }
        }
        let expected_type = __s0_buffer_get(CheckedTypeRec, string_store.types, string_type - 1)
        if expected_type.kind != 2 && expected_type.kind != 14 && expected_type.kind != 16 {
            let want = diagnostic_type(string_store, expected)
            let failed = try check_token_detail_fail(d, state, base, mismatch_kind, mismatch_node, want.kind, want.target, 2, 0)
            let bad = match failed {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            return Ok(ExprBad(bad))
        }
        let token = __s0_buffer_get(TokenRec, state.tokens, expression.token - 1)
        if expected_type.kind == 2 && !checker_utf8_valid(state.values, token.value_start, token.value_end) { return expr_token_fail(d, state, base, 99, expression) }
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
        if local_id == 0 && expected != 0 && node_word(state, expression, "None") {
            let concrete = __s0_buffer_get(CheckedTypeRec, store.types, expected - 1)
            if concrete.kind != 9 { return expr_fail(d, base, 40, expression) }
            return append_expression(d, store, owner, expression_id, 14, expected, 0, 0, 0, 0, 0, site_kind, site_syntax)
        }
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
        if local_id == 0 && expected != 0 && (node_word(state, expression, "OutOfMemory") || node_word(state, expression, "Limit")) && __s0_buffer_get(CheckedTypeRec, store.types, expected - 1).kind == 5 {
            var builtin: U64 = 5
            if node_word(state, expression, "Limit") { builtin = 6 }
            return append_s0_error_expression(d, parse, store, owner, expression_id, expected, builtin, site_kind, site_syntax)
        }
        var kind: U64 = 5
        var reference = local_id
        var binding_type: U64 = 0
        if local_id != 0 {
            let binding = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
            binding_type = binding.checked_type
            if binding.kind == 1 { kind = 1 }
        } else {
            let target = symbol_named(state, parse, store, expression)
            if target != 0 && __s0_buffer_get(SymbolRec, store.symbols, target - 1).kind == 12 {
                // A non-generic function name in value position is a
                // function reference: its value type is fn(params) -> result
                // with a unit environment.
                let symbol = __s0_buffer_get(SymbolRec, store.symbols, target - 1)
                if symbol.type_arity != 0 { return expr_fail(d, base, 39, expression) }
                let made = try checked_function_value_type(d, store, owner, target)
                var with_type = made.store
                if expected != 0 && !(try expression_type_equal(d, state, parse, with_type, made.checked_type, expected)) { return expr_token_type_fail(d, state, with_type, mismatch_kind, mismatch_node, expected, made.checked_type) }
                let annotations = try __s0_buffer_append(CallAnnotationRec, d, with_type.call_annotations, CallAnnotationRec(owner: owner, kind: 5, target: target, checked_type: made.checked_type, variant_use: 0, builtin: 43))
                let expressions = try __s0_buffer_append(CheckedExprRec, d, with_type.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(with_type, owner), syntax: expression_id, kind: 18, checked_type: made.checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: __s0_buffer_len(CallAnnotationRec, annotations), first_child: 0, child_count: 0, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
                with_type = CheckStore(symbols: with_type.symbols, type_params: with_type.type_params, types: with_type.types, type_args: with_type.type_args, type_annotations: with_type.type_annotations, uses: with_type.uses, indexes: with_type.indexes, locals: with_type.locals, environments: with_type.environments, expressions: expressions, call_annotations: annotations, expression_children: with_type.expression_children, returns: with_type.returns, control: with_type.control, diagnostics: with_type.diagnostics, traits: with_type.traits, closures: with_type.closures)
                return expr_draft(with_type, made.checked_type, __s0_buffer_len(CheckedExprRec, expressions))
            }
            let any_variant = any_variant_named(state, store, expression)
            if any_variant != 0 {
                let variant = __s0_buffer_get(DeclTypeUseRec, store.uses, any_variant - 1)
                if __s0_buffer_get(SymbolRec, store.symbols, variant.owner - 1).type_arity != 0 { return expr_deferred(base) }
                return expr_fail(d, base, 40, expression)
            }
            if known_body_identifier(state, store, expression) { return expr_deferred(base) }
            return expr_fail(d, base, 18, expression)
        }
        if expected != 0 && !(try expression_type_equal(d, state, parse, store, binding_type, expected)) { return expr_token_type_fail(d, state, store, mismatch_kind, mismatch_node, expected, binding_type) }
        if lexical_access_conflict(store, owner, reference, 1) { return expr_token_fail(d, state, base, 92, expression) }
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
    if expression.kind == 37 {
        let arm_head = __s0_buffer_get(SyntaxLinkRec, parse.links, expression.children - 1)
        var scrutinee_link = arm_head
        while scrutinee_link.next != 0 { scrutinee_link = __s0_buffer_get(SyntaxLinkRec, parse.links, scrutinee_link.next - 1) }
        let scrutinee_node = __s0_buffer_get(SyntaxRec, parse.nodes, scrutinee_link.node - 1)
        let checked_scrutinee = try check_value_expression_inner(d, state, parse, base, store, owner, scrutinee_node, scrutinee_link.node, 0, mismatch_kind, mismatch_node, 0, 0)
        let current = match checked_scrutinee {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_scrutinee {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let scrutinee = match checked_scrutinee {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if scrutinee.deferred { return expr_deferred(base) }
        // An affine scrutinee is consumed as a whole: its payload arms bind
        // by transfer, and the scrutinee binding itself transfers into the
        // match. Reads of it after the match are use-after-transfer.
        let scrutinee_consumed = try transfer_owned_argument(d, state, parse, current, owner, scrutinee.expression)
        let scrutinee_type = __s0_buffer_get(CheckedTypeRec, scrutinee_consumed.types, scrutinee.checked_type - 1)
        if scrutinee_type.kind != 5 && scrutinee_type.kind != 7 && scrutinee_type.kind != 9 && scrutinee_type.kind != 10 { return expr_token_fail(d, state, base, 70, expression) }
        // A table lookup scrutinee is the one scoped-view match admitted by
        // M7.5: the get/get_mut call is consumed exactly once by the switch,
        // its Some arm binding is the scoped view, and the arms carry the
        // straight-line region rules. Every other scrutinee containing a
        // scoped view stays rejected.
        var view_root: U64 = 0
        var view_mut: U64 = 0
        var table_lookup = false
        if scrutinee_type.kind == 9 {
            let payload = __s0_buffer_get(CheckedTypeRec, current.types, __s0_buffer_get(U64, current.type_args, scrutinee_type.first_arg - 1) - 1)
            if payload.kind == 21 || payload.kind == 22 {
                table_lookup = true
                let scrutinee_expression = __s0_buffer_get(CheckedExprRec, current.expressions, scrutinee.expression - 1)
                if scrutinee_expression.kind != 18 || scrutinee_expression.annotation == 0 || scrutinee_expression.child_count != 2 { return expr_token_fail(d, state, base, 132, expression) }
                let annotation = __s0_buffer_get(CallAnnotationRec, current.call_annotations, scrutinee_expression.annotation - 1)
                if annotation.builtin != 28 && annotation.builtin != 29 { return expr_token_fail(d, state, base, 132, expression) }
                let receiver = __s0_buffer_get(CheckedExprRec, current.expressions, __s0_buffer_get(CheckedExprChildRec, current.expression_children, scrutinee_expression.first_child - 1).expression - 1)
                if (receiver.kind != 1 && receiver.kind != 5) || receiver.parameter_use == 0 { return expr_token_fail(d, state, base, 132, expression) }
                view_root = receiver.parameter_use
                if annotation.builtin == 29 { view_mut = 1 }
                if payload.kind == 22 && view_mut == 0 { return expr_token_fail(d, state, base, 132, expression) }
            }
        }
        if !table_lookup {
            // Match arm payload bindings are not tracked as active views, so a
            // scrutinee type containing a scoped view can never be matched, even
            // when every view is immutable.
            if try checked_type_contains_scoped(d, state, parse, current, scrutinee.checked_type) { return expr_token_fail(d, state, base, 104, expression) }
        }
        if arm_head.next == 0 { return expr_token_fail(d, state, base, 78, expression) }
        let drafts = try __s0_buffer_new(MatchArmDraftRec, d)
        let checked_arms = try check_match_arm_links(d, state, parse, base, scrutinee_consumed, owner, expression.children, scrutinee.checked_type, expected, drafts, expression, view_root, view_mut)
        let arms = match checked_arms {
            MatchArmsGood(value) => value
            MatchArmsBad(value) => MatchArmValueRec(store: value, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, block_arms: false, expression_arms: false, arms: drafts)
            MatchArmsDefer => MatchArmValueRec(store: current, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, block_arms: false, expression_arms: false, arms: drafts)
        }
        if match checked_arms {
            MatchArmsGood(value) => false
            MatchArmsBad(value) => true
            MatchArmsDefer => false
        } { return Ok(ExprBad(arms.store)) }
        if match checked_arms {
            MatchArmsGood(value) => false
            MatchArmsBad(value) => false
            MatchArmsDefer => true
        } { return expr_deferred(base) }
        if arms.arm_count == 0 { return expr_token_fail(d, state, base, 78, expression) }
        if !arms.wildcard {
            var variant_count: U64 = 2
            if scrutinee_type.kind == 7 {
                variant_count = 0
                var use_at: U64 = 0
                while use_at < __s0_buffer_len(DeclTypeUseRec, arms.store.uses) {
                    let use = __s0_buffer_get(DeclTypeUseRec, arms.store.uses, use_at)
                    if use.owner == scrutinee_type.target && use.role == 2 { variant_count = variant_count + 1 }
                    use_at = use_at + 1
                }
            }
            var covered = arms.arm_count == variant_count
            if scrutinee_type.kind == 7 {
                covered = true
                var missing: U64 = 0
                var variant_at: U64 = 0
                while variant_at < __s0_buffer_len(DeclTypeUseRec, arms.store.uses) {
                    let declared = __s0_buffer_get(DeclTypeUseRec, arms.store.uses, variant_at)
                    if declared.owner == scrutinee_type.target && declared.role == 2 && !match_variant_seen(arms.arms, arms.first_arm, arms.arm_count, variant_at + 1, 0) { covered = false
                        if missing == 0 { missing = variant_at + 1 } }
                    variant_at = variant_at + 1
                }
                if !covered {
                    let missing_use = __s0_buffer_get(DeclTypeUseRec, arms.store.uses, missing - 1)
                    let enum_symbol = __s0_buffer_get(SymbolRec, arms.store.symbols, scrutinee_type.target - 1)
                    let failed = try check_token_detail_fail(d, state, base, 79, expression, missing_use.name_start, missing_use.name_end, enum_symbol.name_start, enum_symbol.name_end)
                    let bad = match failed {
                        CheckGood(value) => value
                        CheckBad(value) => value
                    }
                    return Ok(ExprBad(bad))
                }
            }
            if !covered { return expr_token_fail(d, state, base, 79, expression) }
        }
        if table_lookup && arms.wildcard { return expr_token_fail(d, state, arms.store, 132, expression) }
        let match_id = __s0_buffer_len(CheckedMatchRec, arms.store.control.matches) + 1
        let first_arm = __s0_buffer_len(CheckedMatchArmRec, arms.store.control.match_arms) + 1
        var persisted_arms = arms.store.control.match_arms
        var arm_at: U64 = 0
        while arm_at < arms.arm_count {
            let arm = __s0_buffer_get(MatchArmDraftRec, arms.arms, arms.first_arm - 1 + arm_at)
            persisted_arms = try __s0_buffer_append(CheckedMatchArmRec, d, persisted_arms, CheckedMatchArmRec(owner: arm.owner, syntax: arm.syntax, checked_match: match_id, variant_use: arm.variant_use, variant_kind: arm.variant_kind, binding: arm.binding, environment: arm.environment, body: arm.body, block: arm.block))
            arm_at = arm_at + 1
        }
        let matches = try __s0_buffer_append(CheckedMatchRec, d, arms.store.control.matches, CheckedMatchRec(owner: owner, syntax: expression_id, scrutinee: scrutinee.expression, scrutinee_type: scrutinee.checked_type, checked_type: arms.arm_type, first_arm: first_arm, arm_count: arms.arm_count))
        let control = CheckedControlStore(blocks: arms.store.control.blocks, statement_links: arms.store.control.statement_links, statements: arms.store.control.statements, places: arms.store.control.places, matches: matches, match_arms: persisted_arms, tries: arms.store.control.tries, cleanups: arms.store.control.cleanups, table_views: arms.store.control.table_views)
        return append_expression(d, with_control(arms.store, control), owner, expression_id, 12, arms.arm_type, match_id, 0, scrutinee.expression, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 31 {
        let result_use = function_use(store, owner, 6, expression, state)
        let function_result_id = __s0_buffer_get(DeclTypeUseRec, store.uses, result_use - 1).checked_type
        let function_result = __s0_buffer_get(CheckedTypeRec, store.types, function_result_id - 1)
        if function_result.kind != 10 { return expr_token_fail(d, state, base, 80, expression) }
        let child_link = __s0_buffer_get(SyntaxLinkRec, parse.links, expression.children - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, child_link.node - 1)
        let checked_child = try check_value_expression_inner(d, state, parse, base, store, owner, child, child_link.node, 0, mismatch_kind, mismatch_node, 0, 0)
        let current = match checked_child {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_child {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(current)) }
        let draft = match checked_child {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return expr_deferred(base) }
        let operand = __s0_buffer_get(CheckedTypeRec, current.types, draft.checked_type - 1)
        if operand.kind != 10 { return expr_token_fail(d, state, base, 81, expression) }
        let operand_error = __s0_buffer_get(U64, current.type_args, operand.first_arg)
        let function_error = __s0_buffer_get(U64, current.type_args, function_result.first_arg)
        if !(try expression_type_equal(d, state, parse, current, operand_error, function_error)) { return expr_token_type_fail(d, state, current, 82, expression, operand_error, function_error) }
        let ok_type = __s0_buffer_get(U64, current.type_args, operand.first_arg - 1)
        if expected != 0 && !(try expression_type_equal(d, state, parse, current, ok_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        let tries = try __s0_buffer_append(CheckedTryRec, d, current.control.tries, CheckedTryRec(owner: owner, syntax: expression_id, expression: draft.expression, result_type: draft.checked_type, ok_type: ok_type, error_type: operand_error))
        let control = CheckedControlStore(blocks: current.control.blocks, statement_links: current.control.statement_links, statements: current.control.statements, places: current.control.places, matches: current.control.matches, match_arms: current.control.match_arms, tries: tries, cleanups: current.control.cleanups, table_views: current.control.table_views)
        return append_expression(d, with_control(current, control), owner, expression_id, 13, ok_type, __s0_buffer_len(CheckedTryRec, tries), 0, draft.expression, 0, 0, site_kind, site_syntax)
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

fn with_control(store: CheckStore, control: CheckedControlStore) -> CheckStore {
    return CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures)
}

fn append_checked_statement(d: Domain, store: CheckStore, owner: U64, syntax: U64, kind: U64, environment: U64, expression: U64, place: U64, binding: U64, body: U64, alternative: U64, guaranteed: Bool) -> Result(BodyStep, __s0_Error) {
    let statements = try __s0_buffer_append(CheckedStatementRec, d, store.control.statements, CheckedStatementRec(owner: owner, syntax: syntax, kind: kind, environment: environment, expression: expression, place: place, binding: binding, body: body, alternative: alternative))
    let control = CheckedControlStore(blocks: store.control.blocks, statement_links: store.control.statement_links, statements: statements, places: store.control.places, matches: store.control.matches, match_arms: store.control.match_arms, tries: store.control.tries, cleanups: store.control.cleanups, table_views: store.control.table_views)
    return Ok(BodyGood(BodyValueRec(store: with_control(store, control), environment: current_environment(store, owner), semantic: __s0_buffer_len(CheckedStatementRec, statements), guaranteed_return: guaranteed)))
}

fn restore_environment(d: Domain, store: CheckStore, owner: U64, parent: U64) -> Result(CheckStore, __s0_Error) {
    let environments = try __s0_buffer_append(EnvironmentRec, d, store.environments, EnvironmentRec(owner: owner, parent: parent, binding: 0))
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: store.traits, closures: store.closures))
}

fn field_use_named(state: State, store: CheckStore, target: U64, node: SyntaxRec) -> U64 {
    if checker_use_index_available(store, target, 1) {
        let index = __s0_buffer_get(CheckerUseIndexRec, store.indexes.uses, checker_use_slot(target, 1))
        var ordinal: U64 = 0
        while ordinal < index.count {
            let use_id = __s0_buffer_get(U64, store.indexes.use_order, index.first - 1 + ordinal)
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_id - 1)
            if same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return use_id }
            ordinal = ordinal + 1
        }
        return 0
    }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == target && use.role == 1 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn concrete_field_type(d: Domain, store: CheckStore, aggregate: U64, field: U64) -> Result(TypeValueRec, __s0_Error) {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, aggregate - 1)
    let empty = try __s0_buffer_new(InferenceBindingRec, d)
    let bindings = try bind_expected_application(d, store, checked.target, checked, 0, 0, empty)
    return substitute_type(d, store, bindings, __s0_buffer_get(DeclTypeUseRec, store.uses, field - 1).checked_type)
}

fn place_bad(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(PlaceOutcome, __s0_Error) {
    let failed = try check_fail(d, store, kind, node, 0, 0, 0)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(PlaceBad(bad))
}

fn place_token_bad(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(PlaceOutcome, __s0_Error) {
    let failed = try check_token_fail(d, state, store, kind, node)
    let bad = match failed {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return Ok(PlaceBad(bad))
}

fn append_place(d: Domain, store: CheckStore, owner: U64, syntax: U64, kind: U64, root: U64, field: U64, index: U64, checked_type: U64) -> Result(PlaceOutcome, __s0_Error) {
    let places = try __s0_buffer_append(CheckedPlaceRec, d, store.control.places, CheckedPlaceRec(owner: owner, syntax: syntax, kind: kind, root: root, field: field, index: index, checked_type: checked_type))
    let control = CheckedControlStore(blocks: store.control.blocks, statement_links: store.control.statement_links, statements: store.control.statements, places: places, matches: store.control.matches, match_arms: store.control.match_arms, tries: store.control.tries, cleanups: store.control.cleanups, table_views: store.control.table_views)
    return Ok(PlaceGood(PlaceValueRec(store: with_control(store, control), place: __s0_buffer_len(CheckedPlaceRec, places), checked_type: checked_type)))
}

// Place components are checked before the assignment value. Indexing is the
// one reference-style mutation permitted through an immutable slice binding;
// direct and direct-field stores require a mutable root.
fn check_assignment_place(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, target: SyntaxRec, target_id: U64, statement: SyntaxRec, statement_id: U64) -> Result(PlaceOutcome, __s0_Error) {
    var root = target
    var root_id = target_id
    var field_node = target
    var field: U64 = 0
    var index_node = target
    var index_id: U64 = 0
    var kind: U64 = 1
    if target.kind == 29 {
        let base_link = __s0_buffer_get(SyntaxLinkRec, parse.links, target.children - 1)
        let base = __s0_buffer_get(SyntaxRec, parse.nodes, base_link.node - 1)
        field_node = target
        if base.kind == 30 {
            kind = 4
            index_node = base
            let index_link = __s0_buffer_get(SyntaxLinkRec, parse.links, base.children - 1)
            index_id = index_link.node
            let root_link = __s0_buffer_get(SyntaxLinkRec, parse.links, index_link.next - 1)
            root_id = root_link.node
            root = __s0_buffer_get(SyntaxRec, parse.nodes, root_id - 1)
        } else {
            kind = 2
            root_id = base_link.node
            root = base
        }
    }
    if target.kind == 30 {
        kind = 3
        index_node = target
        let index_link = __s0_buffer_get(SyntaxLinkRec, parse.links, target.children - 1)
        index_id = index_link.node
        let root_link = __s0_buffer_get(SyntaxLinkRec, parse.links, index_link.next - 1)
        root_id = root_link.node
        root = __s0_buffer_get(SyntaxRec, parse.nodes, root_id - 1)
    }
    if root.kind != 24 { return Ok(PlaceDefer) }
    let local_id = local_lookup(store, owner, root, state)
    if local_id == 0 { return place_bad(d, store, 18, root) }
    let local = __s0_buffer_get(LocalRec, store.locals, local_id - 1)
    if kind == 1 {
        let root_empty = try __s0_buffer_new(TypeBindingRec, d)
        let root_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
        let root_category = try interpreted_type_category(d, state, parse, store, root_empty, root_ancestry, local.checked_type, 0, 0)
        if root_category.category == 2 { return place_token_bad(d, state, store, 95, statement) }
    }
    var current = store
    var value_type = local.checked_type
    // An exclusive table view grants field mutation through its element; an
    // immutable view, and any other use of a view binding as a place, stays
    // read-only.
    let root_checked = __s0_buffer_get(CheckedTypeRec, current.types, local.checked_type - 1)
    if root_checked.kind == 21 || root_checked.kind == 22 {
        if kind != 2 || root_checked.kind != 22 { return place_bad(d, store, 28, root) }
        value_type = __s0_buffer_get(U64, current.type_args, root_checked.first_arg - 1)
    } else {
        if local.mutable == 0 && kind <= 2 { return place_bad(d, store, 28, root) }
    }
    var index_expression: U64 = 0
    if kind == 3 || kind == 4 {
        let sequence = __s0_buffer_get(CheckedTypeRec, current.types, value_type - 1)
        if sequence.kind != 8 && sequence.kind != 15 && sequence.kind != 17 && sequence.kind != 18 { return place_token_bad(d, state, store, 62, index_node) }
        value_type = __s0_buffer_get(U64, current.type_args, sequence.first_arg - 1)
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
        if try interpreted_contains_reference(d, state, parse, current, empty, no_ancestry, value_type, 0, 0, 0) { return place_token_bad(d, state, store, 64, index_node) }
        let index_syntax = __s0_buffer_get(SyntaxRec, parse.nodes, index_id - 1)
        let index_type = primitive_type_id(state, parse, current, "U64")
        let checked_index = try check_value_expression(d, state, parse, current, owner, index_syntax, index_id, index_type, 63, index_node, 7, statement_id)
        current = match checked_index {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_index {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(PlaceBad(current)) }
        let draft = match checked_index {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return Ok(PlaceDefer) }
        index_expression = draft.expression
        if lexical_access_conflict(store, owner, local_id, 2) { return place_token_bad(d, state, store, 92, statement) }
        // Only explicitly mutable slice parameters retain the bootstrap
        // compatibility path; ordinary source slice values are immutable.
        if sequence.kind == 8 && local.mutable == 0 { return place_token_bad(d, state, store, 103, statement) }
        if sequence.kind == 18 && local.mutable == 0 { return place_token_bad(d, state, store, 103, statement) }
        if (sequence.kind == 15 || sequence.kind == 17) && local.mutable == 0 { return place_bad(d, store, 28, root) }
    }
    if kind == 2 || kind == 4 {
        let aggregate = __s0_buffer_get(CheckedTypeRec, current.types, value_type - 1)
        if aggregate.kind != 7 || __s0_buffer_get(SymbolRec, current.symbols, aggregate.target - 1).kind != 2 { return place_bad(d, store, 60, field_node) }
        field = field_use_named(state, current, aggregate.target, field_node)
        if field == 0 { return place_bad(d, store, 61, field_node) }
        let concrete = try concrete_field_type(d, current, value_type, field)
        current = concrete.store
        value_type = concrete.checked_type
    }
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, value_type, 0, 0)
    if category.category == 2 { return place_token_bad(d, state, current, 95, statement) }
    return append_place(d, current, owner, target_id, kind, local_id, field, index_expression, value_type)
}

// Binding order follows the Go checker: reserved name, annotation resolution,
// initializer and mismatch, Unit/DomainMark rejection, then duplicates.
fn check_binding(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    if reserved_value_name(state, store, statement) { return body_token_fail(d, state, store, 22, statement) }
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
        annotated = checked_type_for_syntax(next, owner, type_link.node)
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
    if draft.deferred && init.kind == 24 && node_word(state, init, "Unit") { return body_token_fail(d, state, ostore, 25, init) }
    if draft.deferred { return body_token_fail(d, state, ostore, 87, init) }
    if annotated == 0 { annotated = draft.checked_type }
    let annotation = __s0_buffer_get(CheckedTypeRec, ostore.types, annotated - 1)
    var diag_node = statement
    if annotation_syntax != 0 { diag_node = __s0_buffer_get(SyntaxRec, parse.nodes, annotation_syntax - 1) }
    if annotation.kind == 1 && annotation.target == 12 {
        if annotation_syntax == 0 { return body_token_fail(d, state, next, 25, statement) }
        return body_fail(d, next, 25, diag_node)
    }
    if annotation.kind == 4 {
        if annotation_syntax == 0 { return body_token_fail(d, state, next, 26, statement) }
        return body_fail(d, next, 26, diag_node)
    }
    let empty_bindings = try __s0_buffer_new(TypeBindingRec, d)
    let empty_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    let category = try interpreted_type_category(d, state, parse, ostore, empty_bindings, empty_ancestry, annotated, 0, 0)
    if annotation.kind == 18 && statement.kind == 15 { return body_token_fail(d, state, ostore, 102, statement) }
    if annotation.kind == 18 {
        let initializer = __s0_buffer_get(CheckedExprRec, ostore.expressions, draft.expression - 1)
        if initializer.kind != 18 || initializer.annotation == 0 { return body_token_fail(d, state, ostore, 104, statement) }
        let call = __s0_buffer_get(CallAnnotationRec, ostore.call_annotations, initializer.annotation - 1)
        if call.builtin != 24 && call.builtin != 25 { return body_token_fail(d, state, ostore, 104, statement) }
    }
    if category.contains_scoped && annotation.kind != 8 && annotation.kind != 18 { return body_token_fail(d, state, ostore, 104, statement) }
    if category.category == 2 {
        if statement.kind == 16 { return body_token_fail(d, state, ostore, 95, statement) }
        let initializer = __s0_buffer_get(CheckedExprRec, ostore.expressions, draft.expression - 1)
        if initializer.kind == 1 || initializer.kind == 5 {
            let source = __s0_buffer_get(LocalRec, ostore.locals, initializer.parameter_use - 1)
            var owned = source.kind == 2
            if source.kind == 1 && __s0_buffer_get(SyntaxRec, parse.nodes, source.syntax - 1).kind == 48 { owned = true }
            if !owned { return body_token_fail(d, state, ostore, 92, init) }
            __s0_buffer_set(CheckedExprRec, ostore.expressions, draft.expression - 1, CheckedExprRec(owner: initializer.owner, owner_previous: initializer.owner_previous, syntax: initializer.syntax, kind: 22, checked_type: initializer.checked_type, parameter_use: initializer.parameter_use, bool_value: initializer.bool_value, left: initializer.left, right: initializer.right, annotation: initializer.annotation, first_child: initializer.first_child, child_count: initializer.child_count, operator: initializer.operator, site_kind: initializer.site_kind, site_syntax: initializer.site_syntax))
        }
    }
    if local_lookup(ostore, owner, statement, state) != 0 || function_use(ostore, owner, 5, statement, state) != 0 { return body_token_fail(d, state, next, 27, statement) }
    var mutable: U64 = 0
    var statement_kind: U64 = 1
    if statement.kind == 16 {
        mutable = 1
        statement_kind = 2
    }
    let locals = try __s0_buffer_append(LocalRec, d, ostore.locals, LocalRec(owner: owner, kind: 2, syntax: statement_id, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: mutable, checked_type: annotated))
    let binding = __s0_buffer_len(LocalRec, locals)
    let environments = try __s0_buffer_append(EnvironmentRec, d, ostore.environments, EnvironmentRec(owner: owner, parent: environment, binding: binding))
    let recorded = CheckStore(symbols: ostore.symbols, type_params: ostore.type_params, types: ostore.types, type_args: ostore.type_args, type_annotations: ostore.type_annotations, uses: ostore.uses, indexes: ostore.indexes, locals: locals, environments: environments, expressions: ostore.expressions, call_annotations: ostore.call_annotations, expression_children: ostore.expression_children, returns: ostore.returns, control: ostore.control, diagnostics: ostore.diagnostics, traits: ostore.traits, closures: ostore.closures)
    return append_checked_statement(d, recorded, owner, statement_id, statement_kind, environment, draft.expression, 0, binding, 0, 0, false)
}

fn check_assignment(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    let head = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
    let target_link = __s0_buffer_get(SyntaxLinkRec, parse.links, head.next - 1)
    let target = __s0_buffer_get(SyntaxRec, parse.nodes, target_link.node - 1)
    let checked_place = try check_assignment_place(d, state, parse, store, owner, target, target_link.node, statement, statement_id)
    let current = match checked_place {
        PlaceGood(value) => value.store
        PlaceBad(value) => value
        PlaceDefer => store
    }
    if match checked_place {
        PlaceGood(value) => false
        PlaceBad(value) => true
        PlaceDefer => false
    } { return Ok(BodyBad(current)) }
    if match checked_place {
        PlaceGood(value) => false
        PlaceBad(value) => false
        PlaceDefer => true
    } { return body_token_fail(d, state, store, 87, target) }
    let place = match checked_place {
        PlaceGood(value) => value
        PlaceBad(value) => PlaceValueRec(store: value, place: 0, checked_type: 0)
        PlaceDefer => PlaceValueRec(store: store, place: 0, checked_type: 0)
    }
    let rhs = __s0_buffer_get(SyntaxRec, parse.nodes, head.node - 1)
    let outcome = try check_value_expression(d, state, parse, place.store, owner, rhs, head.node, place.checked_type, 24, statement, 2, statement_id)
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
    if draft.deferred { return body_token_fail(d, state, ostore, 87, rhs) }
    if __s0_buffer_get(CheckedTypeRec, ostore.types, place.checked_type - 1).kind == 18 { return body_token_fail(d, state, ostore, 104, statement) }
    return append_checked_statement(d, ostore, owner, statement_id, 3, environment, draft.expression, place.place, 0, 0, 0, false)
}

fn check_return_statement(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    let result_use_id = function_use(store, owner, 6, statement, state)
    let result_use = __s0_buffer_get(DeclTypeUseRec, store.uses, result_use_id - 1)
    let result_type = __s0_buffer_get(CheckedTypeRec, store.types, result_use.checked_type - 1)
    var current = store
    var expression: U64 = 0
    if statement.children == 0 {
        if result_type.kind != 1 || result_type.target != 12 { return body_token_fail(d, state, store, 20, statement) }
    } else {
        let expression_link = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
        let syntax = __s0_buffer_get(SyntaxRec, parse.nodes, expression_link.node - 1)
        let outcome = try check_value_expression(d, state, parse, store, owner, syntax, expression_link.node, result_use.checked_type, 19, statement, 3, statement_id)
        current = match outcome {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match outcome {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(BodyBad(current)) }
        let draft = match outcome {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if draft.deferred { return body_token_fail(d, state, current, 87, syntax) }
        expression = draft.expression
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
        let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, result_use.checked_type, 0, 0)
        // M7.3 slice 2 admitted a direct immutable slice result; slice 3
        // generalizes that to ordinary aggregates whose scoped parts are all
        // immutable views, materialized into caller-result storage. Mutable
        // views and aggregates with unprovable capability leaves stay
        // rejected.
        if category.contains_scoped && !(try checked_type_views_materializable(d, state, parse, current, result_use.checked_type)) { return body_token_fail(d, state, current, 104, statement) }
        let returned = __s0_buffer_get(CheckedExprRec, current.expressions, expression - 1)
        if returned.kind == 1 || returned.kind == 5 {
            let binding = __s0_buffer_get(LocalRec, current.locals, returned.parameter_use - 1)
            var take_binding = false
            if binding.kind == 1 && __s0_buffer_get(SyntaxRec, parse.nodes, binding.syntax - 1).kind == 48 { take_binding = true }
            let owned = binding.kind == 2 || take_binding
            if category.category == 2 || (category.category == 0 && take_binding) {
                if !owned { return body_token_fail(d, state, current, 92, syntax) }
                __s0_buffer_set(CheckedExprRec, current.expressions, expression - 1, CheckedExprRec(owner: returned.owner, owner_previous: returned.owner_previous, syntax: returned.syntax, kind: 22, checked_type: returned.checked_type, parameter_use: returned.parameter_use, bool_value: returned.bool_value, left: returned.left, right: returned.right, annotation: returned.annotation, first_child: returned.first_child, child_count: returned.child_count, operator: returned.operator, site_kind: returned.site_kind, site_syntax: returned.site_syntax))
            }
        }
    }
    let returns = try __s0_buffer_append(CheckedReturnRec, d, current.returns, CheckedReturnRec(owner: owner, syntax: statement_id, expression: expression, result_use: result_use_id))
    let recorded = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
    return append_checked_statement(d, recorded, owner, statement_id, 4, environment, expression, 0, 0, 0, 0, true)
}

fn check_expression_statement(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    var expression_id = statement_id
    var expression = statement
    if statement.kind == 19 {
        let expression_link = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
        expression_id = expression_link.node
        expression = __s0_buffer_get(SyntaxRec, parse.nodes, expression_id - 1)
    }
    let outcome = try check_value_expression(d, state, parse, store, owner, expression, expression_id, 0, 23, statement, 4, statement_id)
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
    if draft.deferred { return body_token_fail(d, state, current, 87, expression) }
    // A table lookup must be consumed by a match scrutinee; discarding its
    // option would strand the view extraction.
    let outcome_type = __s0_buffer_get(CheckedTypeRec, current.types, draft.checked_type - 1)
    if outcome_type.kind == 9 {
        let payload = __s0_buffer_get(CheckedTypeRec, current.types, __s0_buffer_get(U64, current.type_args, outcome_type.first_arg - 1) - 1)
        if payload.kind == 21 || payload.kind == 22 { return body_token_fail(d, state, current, 132, expression) }
    }
    return append_checked_statement(d, current, owner, statement_id, 5, environment, draft.expression, 0, 0, 0, 0, false)
}

// vec_element_cleanup_story reports whether a Vec element type may join an
// affine vector: 0 no (the copyable-only rule stays), or the element's
// concrete Cleanup method symbol id. Table elements stay out until the MIR
// storage rules
// admit heap-stored table handles (the phase-6 verifier rejects the deref
// store today); a Table owner registers with using directly instead.
fn vec_element_cleanup_story(state: State, store: CheckStore, element: U64) -> U64 {
    if element == 0 || element > __s0_buffer_len(CheckedTypeRec, store.types) { return 0 }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, element - 1)
    if checked.kind == 7 {
        let bits = type_cleanup_impls(store, checked.target)
        if bits == 1 { return type_cleanup_method_symbol(state, store, checked.target) }
    }
    return 0
}

// vec_element_allows_affine admits an affine Vec element with a cleanup
// story; copyable elements stay admitted and scoped ones never are.
fn vec_element_allows_affine(state: State, store: CheckStore, element: U64) -> Bool {
    return vec_element_cleanup_story(state, store, element) != 0
}

// cleanup_binding_registered reports whether a local binding is the binding
// of a using registration. Cleanups are one per using statement, so this walk
// stays bounded by the program's registration count.
fn cleanup_binding_registered(store: CheckStore, owner: U64, binding: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let item = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, at)
        if item.owner == owner && item.binding == binding { return true }
        at = at + 1
    }
    return false
}

// symbol_is_cleanup_hook reports whether a function symbol is the cleanup
// method of a Cleanup implementation. Such a hook consumes
// its receiver by value as the disposal itself, so its take-self parameter
// is exempt from the must-transfer exit rule, exactly like a using binding.
fn symbol_is_cleanup_hook(state: State, store: CheckStore, owner: U64) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(U64, store.traits.receiver_index) {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, at) - 1)
        if rec.trait_builtin == 5 {
            if owner >= rec.first_method && owner < rec.first_method + rec.method_count {
                let method = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
                return symbol_name_matches_word(state, method, "cleanup")
            }
        }
        at = at + 1
    }
    return false
}

// type_cleanup_impls reports whether a nominal type symbol implements the
// Cleanup trait (builtin trait 5). Lookup binary-searches the receiver index (sorted by implementing type
// symbol, then trait) and scans only the adjacent window of that symbol, so
// affinity queries never walk the whole impl table.
fn type_cleanup_impls(store: CheckStore, type_symbol: U64) -> U64 {
    let count = __s0_buffer_len(U64, store.traits.receiver_index)
    if count == 0 { return 0 }
    var low: U64 = 0
    var high: U64 = count
    while low < high {
        let mid = low + (high - low) / 2
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, mid) - 1)
        if trait_impl_receiver_type_symbol(store, rec) < type_symbol { low = mid + 1 } else { high = mid }
    }
    var bits: U64 = 0
    var at = low
    while at < count {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, at) - 1)
        let symbol = trait_impl_receiver_type_symbol(store, rec)
        if symbol > type_symbol { return bits }
        if symbol == type_symbol && rec.trait_builtin == 5 { bits = bits + 1 }
        at = at + 1
    }
    return bits
}

// type_cleanup_method_symbol resolves the single `cleanup` method of the
// Cleanup implementation for a nominal type symbol, or zero when the type has
// no Cleanup implementation or no such method.
fn type_cleanup_method_symbol(state: State, store: CheckStore, type_symbol: U64) -> U64 {
    let count = __s0_buffer_len(U64, store.traits.receiver_index)
    if count == 0 { return 0 }
    var low: U64 = 0
    var high: U64 = count
    while low < high {
        let mid = low + (high - low) / 2
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, mid) - 1)
        if trait_impl_receiver_type_symbol(store, rec) < type_symbol { low = mid + 1 } else { high = mid }
    }
    var at = low
    while at < count {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, at) - 1)
        let symbol = trait_impl_receiver_type_symbol(store, rec)
        if symbol > type_symbol { return 0 }
        if symbol == type_symbol && rec.trait_builtin == 5 {
            var method_at = rec.first_method
            while method_at < rec.first_method + rec.method_count {
                let method = __s0_buffer_get(SymbolRec, store.symbols, method_at - 1)
                if symbol_name_matches_word(state, method, "cleanup") { return method_at }
                method_at = method_at + 1
            }
        }
        at = at + 1
    }
    return 0
}

// Cleanup checking intentionally follows frontend/check.go precedence: name,
// loop, initializer, callback resolution/shape/type/result, then duplicates.
fn check_using(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64, in_loop: Bool) -> Result(BodyStep, __s0_Error) {
    if reserved_value_name(state, store, statement) { return body_token_fail(d, state, store, 22, statement) }
    if in_loop { return body_token_fail(d, state, store, 69, statement) }
    let cleanup_link = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
    // The callback clause is optional: a single child names the M7.5 public
    // form whose builtin owner cleanup has no source callback.
    var child_count: U64 = 1
    var count_walk = cleanup_link
    while count_walk.next != 0 {
        count_walk = __s0_buffer_get(SyntaxLinkRec, parse.links, count_walk.next - 1)
        child_count = child_count + 1
    }
    var initializer_link_id = statement.children
    if child_count == 2 { initializer_link_id = cleanup_link.next }
    let initializer_link = __s0_buffer_get(SyntaxLinkRec, parse.links, initializer_link_id - 1)
    let initializer_node = __s0_buffer_get(SyntaxRec, parse.nodes, initializer_link.node - 1)
    let checked_initializer = try check_value_expression(d, state, parse, store, owner, initializer_node, initializer_link.node, 0, 23, statement, 8, statement_id)
    var current = match checked_initializer {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked_initializer {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(BodyBad(current)) }
    let initializer = match checked_initializer {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if initializer.deferred { return body_token_fail(d, state, current, 87, initializer_node) }
    // A using binding keeps its value for the whole scope, so an aggregate
    // containing a scoped view cannot be registered there; its views are not
    // tracked for invalidation.
    let using_kind = __s0_buffer_get(CheckedTypeRec, current.types, initializer.checked_type - 1).kind
    if (using_kind == 7 || using_kind == 9 || using_kind == 10 || using_kind == 11 || using_kind == 13 || using_kind == 15 || using_kind == 17) && (try checked_type_contains_scoped(d, state, parse, current, initializer.checked_type)) { return body_token_fail(d, state, current, 104, statement) }
    var callback: U64 = 0
    var drain: U64 = 0
    if child_count == 2 {
        // The `with cleanup_function` clause is the bootstrap-private MIR
        // callback bridge; ordinary programs select cleanup through the
        // Cleanup trait or the builtin Table owner.
        if !check_bootstrap_private() { return body_token_fail(d, state, current, 137, statement) }
        let cleanup_node = __s0_buffer_get(SyntaxRec, parse.nodes, cleanup_link.node - 1)
        let found = symbol_named(state, parse, current, cleanup_node)
        if found == 0 || __s0_buffer_get(SymbolRec, current.symbols, found - 1).kind != 12 { return body_fail(d, current, 83, cleanup_node) }
        callback = found
        let callback_symbol = __s0_buffer_get(SymbolRec, current.symbols, callback - 1)
        var parameter: U64 = 0
        var parameter_count: U64 = 0
        var result: U64 = 0
        var use_at: U64 = 0
        while use_at < __s0_buffer_len(DeclTypeUseRec, current.uses) {
            let use = __s0_buffer_get(DeclTypeUseRec, current.uses, use_at)
            if use.owner == callback && use.role == 5 { parameter = use.checked_type
                parameter_count = parameter_count + 1 }
            if use.owner == callback && use.role == 6 { result = use.checked_type }
            use_at = use_at + 1
        }
        // No explicit arguments are available at a using site. A generic callback
        // therefore cannot provide one concrete runtime parameter instance.
        if callback_symbol.type_arity != 0 || parameter_count != 1 { return body_fail(d, current, 84, cleanup_node) }
        if !(try expression_type_equal(d, state, parse, current, initializer.checked_type, parameter)) { return body_token_type_fail(d, state, current, 85, statement, initializer.checked_type, parameter) }
        let result_type = __s0_buffer_get(CheckedTypeRec, current.types, result - 1)
        if result_type.kind != 1 || result_type.target != 12 { return body_fail(d, current, 86, cleanup_node) }
    } else {
        // The public form: the builtin Table owner registers the synthesized
        // release callback (callback stays zero), and an affine nominal type
        // implementing Cleanup registers its trait method. Registration
        // exempts the owner from the must-transfer exit rule; a transfer
        // disarms the entry.
        // A whole-aggregate read of an owning local is consumed here exactly
        // like an argument pass, so a received owner can be registered.
        current = try transfer_owned_argument(d, state, parse, current, owner, initializer.expression)
        let using_checked = __s0_buffer_get(CheckedTypeRec, current.types, initializer.checked_type - 1)
        var builtin_table = false
        if using_kind == 19 { builtin_table = true }
        var vec_drain: U64 = 0
        if using_kind == 17 {
            // An affine-element vector registers a per-element drain: the
            // callback names the compiler-synthesized drain function and
            // drain records the element Cleanup method symbol.
            let vec_element = __s0_buffer_get(U64, current.type_args, using_checked.first_arg - 1)
            let story = vec_element_cleanup_story(state, current, vec_element)
            if story != 0 {
                vec_drain = 1
                drain = story
            }
        }
        if !builtin_table && vec_drain == 0 {
            if using_kind != 7 { return body_token_fail(d, state, current, 136, statement) }
            if type_cleanup_impls(current, using_checked.target) != 1 { return body_token_fail(d, state, current, 136, statement) }
            let method = type_cleanup_method_symbol(state, current, using_checked.target)
            if method == 0 { return body_token_fail(d, state, current, 140, statement) }
            let method_symbol = __s0_buffer_get(SymbolRec, current.symbols, method - 1)
            if method_symbol.type_arity != 0 { return body_token_fail(d, state, current, 140, statement) }
            // The cleanup hook takes exactly the owner by value and returns
            // Unit.
            if use_count(current, method, 5) != 1 { return body_token_fail(d, state, current, 140, statement) }
            let result_id = use_by_ordinal(current, method, 6, 0)
            if result_id == 0 { return body_token_fail(d, state, current, 140, statement) }
            let result_type = __s0_buffer_get(CheckedTypeRec, current.types, __s0_buffer_get(DeclTypeUseRec, current.uses, result_id - 1).checked_type - 1)
            if result_type.kind != 1 || result_type.target != 12 { return body_token_fail(d, state, current, 140, statement) }
            callback = method
        }
    }
    if local_lookup(current, owner, statement, state) != 0 || function_use(current, owner, 5, statement, state) != 0 { return body_token_fail(d, state, current, 27, statement) }
    let locals = try __s0_buffer_append(LocalRec, d, current.locals, LocalRec(owner: owner, kind: 2, syntax: statement_id, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: 0, checked_type: initializer.checked_type))
    let binding = __s0_buffer_len(LocalRec, locals)
    let environments = try __s0_buffer_append(EnvironmentRec, d, current.environments, EnvironmentRec(owner: owner, parent: environment, binding: binding))
    current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: locals, environments: environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
    let cleanups = try __s0_buffer_append(CheckedCleanupRec, d, current.control.cleanups, CheckedCleanupRec(owner: owner, syntax: statement_id, environment: environment, binding: binding, initializer: initializer.expression, callback: callback, drain: drain, normal_exit: 1, return_exit: 1, try_exit: 1))
    current = with_control(current, CheckedControlStore(blocks: current.control.blocks, statement_links: current.control.statement_links, statements: current.control.statements, places: current.control.places, matches: current.control.matches, match_arms: current.control.match_arms, tries: current.control.tries, cleanups: cleanups, table_views: current.control.table_views))
    return append_checked_statement(d, current, owner, statement_id, 10, environment, initializer.expression, 0, binding, __s0_buffer_len(CheckedCleanupRec, cleanups), 0, false)
}

// Structural flattening is self-recursive and carries only parser IDs. role is
// 1 for a block syntax node, 2 for a reverse SyntaxLinkRec chain, and 3 for a
// statement syntax node.
fn build_body_event(d: Domain, parse: ParseStore, events: __s0_Buffer(BodyEventRec), role: U64, item: U64) -> Result(BodyEventBuildRec, __s0_Error) {
    if role == 2 && item == 0 { return Ok(BodyEventBuildRec(events: events, event: 0)) }
    if role == 1 {
        let block = __s0_buffer_get(SyntaxRec, parse.nodes, item - 1)
        let children = try build_body_event(d, parse, events, 2, block.children)
        let appended = try __s0_buffer_append(BodyEventRec, d, children.events, BodyEventRec(kind: 1, syntax: item, first: children.event, second: 0, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: __s0_buffer_len(BodyEventRec, appended)))
    }
    if role == 2 {
        let link = __s0_buffer_get(SyntaxLinkRec, parse.links, item - 1)
        let prior = try build_body_event(d, parse, events, 2, link.next)
        let statement = try build_body_event(d, parse, prior.events, 3, link.node)
        let appended = try __s0_buffer_append(BodyEventRec, d, statement.events, BodyEventRec(kind: 2, syntax: link.node, first: prior.event, second: statement.event, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: __s0_buffer_len(BodyEventRec, appended)))
    }
    let statement = __s0_buffer_get(SyntaxRec, parse.nodes, item - 1)
    if statement.kind == 14 {
        let body = try build_body_event(d, parse, events, 1, item)
        let appended = try __s0_buffer_append(BodyEventRec, d, body.events, BodyEventRec(kind: 4, syntax: item, first: body.event, second: 0, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: __s0_buffer_len(BodyEventRec, appended)))
    }
    if statement.kind == 32 || statement.kind == 33 {
        let head = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
        var body_link = head
        var condition_link = __s0_buffer_get(SyntaxLinkRec, parse.links, head.next - 1)
        var alternative_node: U64 = 0
        if statement.kind == 32 && condition_link.next != 0 {
            alternative_node = head.node
            body_link = condition_link
            condition_link = __s0_buffer_get(SyntaxLinkRec, parse.links, condition_link.next - 1)
        }
        let body = try build_body_event(d, parse, events, 1, body_link.node)
        var current = body
        var alternative: U64 = 0
        if alternative_node != 0 {
            current = try build_body_event(d, parse, body.events, 1, alternative_node)
            alternative = current.event
        }
        var kind: U64 = 5
        if statement.kind == 33 { kind = 6 }
        let appended = try __s0_buffer_append(BodyEventRec, d, current.events, BodyEventRec(kind: kind, syntax: item, first: condition_link.node, second: body.event, third: alternative))
        return Ok(BodyEventBuildRec(events: appended, event: __s0_buffer_len(BodyEventRec, appended)))
    }
    if statement.kind == 34 {
        let head = __s0_buffer_get(SyntaxLinkRec, parse.links, statement.children - 1)
        let sequence_link = __s0_buffer_get(SyntaxLinkRec, parse.links, head.next - 1)
        let body = try build_body_event(d, parse, events, 1, head.node)
        let appended = try __s0_buffer_append(BodyEventRec, d, body.events, BodyEventRec(kind: 7, syntax: item, first: sequence_link.node, second: body.event, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: __s0_buffer_len(BodyEventRec, appended)))
    }
    let appended = try __s0_buffer_append(BodyEventRec, d, events, BodyEventRec(kind: 3, syntax: item, first: 0, second: 0, third: 0))
    return Ok(BodyEventBuildRec(events: appended, event: __s0_buffer_len(BodyEventRec, appended)))
}

fn body_event_value(step: BodyStep, fallback: CheckStore) -> BodyValueRec {
    return match step {
        BodyGood(value) => value
        BodyBad(value) => BodyValueRec(store: value, environment: 0, semantic: 0, guaranteed_return: false)
    }
}

fn body_event_store(step: BodyStep, fallback: CheckStore) -> CheckStore {
    return match step {
        BodyGood(value) => value.store
        BodyBad(value) => value
    }
}

fn body_event_stopped(step: BodyStep) -> Bool {
    return match step {
        BodyGood(value) => false
        BodyBad(value) => true
    }
}

// The sole semantic control traversal is directly self-recursive. It never
// carries CheckStore across a loop backedge and no helper calls back into it.
fn check_body_event(d: Domain, state: State, parse: ParseStore, events: __s0_Buffer(BodyEventRec), store: CheckStore, owner: U64, event_id: U64, in_loop: Bool, restore: Bool) -> Result(BodyStep, __s0_Error) {
    if event_id == 0 { return Ok(BodyGood(BodyValueRec(store: store, environment: current_environment(store, owner), semantic: 0, guaranteed_return: false))) }
    let event = __s0_buffer_get(BodyEventRec, events, event_id - 1)
    let statement = __s0_buffer_get(SyntaxRec, parse.nodes, event.syntax - 1)
    if event.kind == 1 {
        let entry = current_environment(store, owner)
        let checked = try check_body_event(d, state, parse, events, store, owner, event.first, in_loop, false)
        if body_event_stopped(checked) { return Ok(checked) }
        let value = body_event_value(checked, store)
        var guaranteed: U64 = 0
        if value.guaranteed_return { guaranteed = 1 }
        let blocks = try __s0_buffer_append(CheckedBlockRec, d, value.store.control.blocks, CheckedBlockRec(owner: owner, syntax: event.syntax, environment: entry, statements: value.semantic, guaranteed_return: guaranteed))
        var current = with_control(value.store, CheckedControlStore(blocks: blocks, statement_links: value.store.control.statement_links, statements: value.store.control.statements, places: value.store.control.places, matches: value.store.control.matches, match_arms: value.store.control.match_arms, tries: value.store.control.tries, cleanups: value.store.control.cleanups, table_views: value.store.control.table_views))
        if restore { current = try restore_environment(d, current, owner, entry) }
        return Ok(BodyGood(BodyValueRec(store: current, environment: current_environment(current, owner), semantic: __s0_buffer_len(CheckedBlockRec, blocks), guaranteed_return: value.guaranteed_return)))
    }
    if event.kind == 2 {
        let before = try check_body_event(d, state, parse, events, store, owner, event.first, in_loop, false)
        if body_event_stopped(before) { return Ok(before) }
        let prior = body_event_value(before, store)
        if prior.guaranteed_return { return body_token_fail(d, state, prior.store, 68, statement) }
        let checked = try check_body_event(d, state, parse, events, prior.store, owner, event.second, in_loop, false)
        if body_event_stopped(checked) { return Ok(checked) }
        let value = body_event_value(checked, prior.store)
        let links = try __s0_buffer_append(CheckedStatementLinkRec, d, value.store.control.statement_links, CheckedStatementLinkRec(statement: value.semantic, next: prior.semantic))
        let current = with_control(value.store, CheckedControlStore(blocks: value.store.control.blocks, statement_links: links, statements: value.store.control.statements, places: value.store.control.places, matches: value.store.control.matches, match_arms: value.store.control.match_arms, tries: value.store.control.tries, cleanups: value.store.control.cleanups, table_views: value.store.control.table_views))
        return Ok(BodyGood(BodyValueRec(store: current, environment: current_environment(current, owner), semantic: __s0_buffer_len(CheckedStatementLinkRec, links), guaranteed_return: value.guaranteed_return)))
    }
    let environment = current_environment(store, owner)
    if event.kind == 3 {
        if statement.kind == 15 || statement.kind == 16 { return check_binding(d, state, parse, store, owner, statement, event.syntax, environment) }
        if statement.kind == 17 { return check_assignment(d, state, parse, store, owner, statement, event.syntax, environment) }
        if statement.kind == 18 { return check_return_statement(d, state, parse, store, owner, statement, event.syntax, environment) }
        if statement.kind == 19 { return check_expression_statement(d, state, parse, store, owner, statement, event.syntax, environment) }
        if statement.kind == 37 { return check_expression_statement(d, state, parse, store, owner, statement, event.syntax, environment) }
        if statement.kind == 35 { return check_using(d, state, parse, store, owner, statement, event.syntax, environment, in_loop) }
        return body_token_fail(d, state, store, 87, statement)
    }
    if event.kind == 4 {
        let checked = try check_body_event(d, state, parse, events, store, owner, event.first, in_loop, true)
        if body_event_stopped(checked) { return Ok(checked) }
        let value = body_event_value(checked, store)
        return append_checked_statement(d, value.store, owner, event.syntax, 6, environment, 0, 0, 0, value.semantic, 0, value.guaranteed_return)
    }
    if event.kind == 5 || event.kind == 6 {
        let condition = __s0_buffer_get(SyntaxRec, parse.nodes, event.first - 1)
        let bool_type = primitive_type_id(state, parse, store, "Bool")
        let checked_condition = try check_value_expression(d, state, parse, store, owner, condition, event.first, bool_type, 65, statement, 5, event.syntax)
        var current = match checked_condition {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match checked_condition {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(BodyBad(current)) }
        let condition_draft = match checked_condition {
            ExprGood(value) => value.draft
            ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
        }
        if condition_draft.deferred { return body_token_fail(d, state, current, 87, condition) }
        let checked_body = try check_body_event(d, state, parse, events, current, owner, event.second, in_loop || event.kind == 6, true)
        if body_event_stopped(checked_body) { return Ok(checked_body) }
        let body = body_event_value(checked_body, current)
        current = body.store
        var alternative: U64 = 0
        var alternative_returns = false
        if event.third != 0 {
            let checked_alternative = try check_body_event(d, state, parse, events, current, owner, event.third, in_loop, true)
            if body_event_stopped(checked_alternative) { return Ok(checked_alternative) }
            let alternative_value = body_event_value(checked_alternative, current)
            current = alternative_value.store
            alternative = alternative_value.semantic
            alternative_returns = alternative_value.guaranteed_return
        }
        var guaranteed = false
        var statement_kind: U64 = 7
        if event.kind == 5 && alternative != 0 && body.guaranteed_return && alternative_returns { guaranteed = true }
        if event.kind == 6 { statement_kind = 8 }
        return append_checked_statement(d, current, owner, event.syntax, statement_kind, environment, condition_draft.expression, 0, 0, body.semantic, alternative, guaranteed)
    }
    if reserved_value_name(state, store, statement) { return body_token_fail(d, state, store, 22, statement) }
    let sequence = __s0_buffer_get(SyntaxRec, parse.nodes, event.first - 1)
    let checked_sequence = try check_value_expression(d, state, parse, store, owner, sequence, event.first, 0, 66, statement, 6, event.syntax)
    var current = match checked_sequence {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked_sequence {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(BodyBad(current)) }
    let sequence_draft = match checked_sequence {
        ExprGood(value) => value.draft
        ExprBad(value) => ExprDraftRec(deferred: true, checked_type: 0, expression: 0)
    }
    if sequence_draft.deferred { return body_token_fail(d, state, current, 87, sequence) }
    let element = sequence_element_type(state, parse, current, sequence_draft.checked_type)
    if element == 0 { return body_token_fail(d, state, store, 66, statement) }
    if local_lookup(current, owner, statement, state) != 0 || function_use(current, owner, 5, statement, state) != 0 { return body_token_fail(d, state, store, 27, statement) }
    let locals = try __s0_buffer_append(LocalRec, d, current.locals, LocalRec(owner: owner, kind: 2, syntax: event.syntax, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: 0, checked_type: element))
    let binding = __s0_buffer_len(LocalRec, locals)
    let environments = try __s0_buffer_append(EnvironmentRec, d, current.environments, EnvironmentRec(owner: owner, parent: environment, binding: binding))
    current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: locals, environments: environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: current.closures)
    let checked_body = try check_body_event(d, state, parse, events, current, owner, event.second, true, true)
    if body_event_stopped(checked_body) { return Ok(checked_body) }
    let body = body_event_value(checked_body, current)
    current = try restore_environment(d, body.store, owner, environment)
    return append_checked_statement(d, current, owner, event.syntax, 9, environment, sequence_draft.expression, 0, binding, body.semantic, 0, false)
}

fn append_parameter_bindings(d: Domain, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckStore, __s0_Error) {
    var next = store
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    var role: U64 = 5
    if symbol.kind == 13 { role = 7 }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == owner && use.role == role {
            let parameter = __s0_buffer_get(SyntaxRec, parse.nodes, use.node - 1)
            var mutable: U64 = 0
            if parameter.kind == 47 { mutable = 1 }
            if parameter.kind == 48 { mutable = 2 }
            let locals = try __s0_buffer_append(LocalRec, d, next.locals, LocalRec(owner: owner, kind: 1, syntax: use.node, source: use.source, name_start: use.name_start, name_end: use.name_end, mutable: mutable, checked_type: use.checked_type))
            let binding = __s0_buffer_len(LocalRec, locals)
            var parent: U64 = 0
            if __s0_buffer_len(EnvironmentRec, next.environments) != 0 {
                let candidate = __s0_buffer_len(EnvironmentRec, next.environments)
                if __s0_buffer_get(EnvironmentRec, next.environments, candidate - 1).owner == owner { parent = candidate }
            }
            let environments = try __s0_buffer_append(EnvironmentRec, d, next.environments, EnvironmentRec(owner: owner, parent: parent, binding: binding))
            next = CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: next.uses, indexes: next.indexes, locals: locals, environments: environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, control: next.control, diagnostics: next.diagnostics, traits: next.traits, closures: next.closures)
        }
        at = at + 1
    }
    return Ok(next)
}

fn owner_flow_expression(store: CheckStore, binding: U64, expression_id: U64, state: U64) -> OwnerFlowRec {
    if expression_id == 0 { return OwnerFlowRec(state: state, terminated: false, error_kind: 0, syntax: 0) }
    let expression = __s0_buffer_get(CheckedExprRec, store.expressions, expression_id - 1)
    var current = state
    var child: U64 = 0
    while child < expression.child_count {
        let child_id = __s0_buffer_get(CheckedExprChildRec, store.expression_children, expression.first_child - 1 + child).expression
        let checked = owner_flow_expression(store, binding, child_id, current)
        if checked.error_kind != 0 { return checked }
        if expression.kind == 7 && (expression.operator == 16 || expression.operator == 17) && child == 1 && checked.state != current {
            return OwnerFlowRec(state: current, terminated: false, error_kind: 94, syntax: expression.syntax)
        }
        current = checked.state
        child = child + 1
    }
    if expression.kind == 12 {
        let checked_match = __s0_buffer_get(CheckedMatchRec, store.control.matches, expression.parameter_use - 1)
        var arm: U64 = 0
        var arm_state: U64 = 2
        while arm < checked_match.arm_count {
            let body = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, checked_match.first_arm - 1 + arm).body
            let checked = owner_flow_expression(store, binding, body, current)
            if checked.error_kind != 0 { return checked }
            if arm_state == 2 { arm_state = checked.state } else {
                if arm_state != checked.state { return OwnerFlowRec(state: current, terminated: false, error_kind: 94, syntax: expression.syntax) }
            }
            arm = arm + 1
        }
        if arm_state != 2 { current = arm_state }
    }
    if (expression.kind == 1 || expression.kind == 5 || expression.kind == 22) && expression.parameter_use == binding {
        if current == 1 { return OwnerFlowRec(state: current, terminated: false, error_kind: 91, syntax: expression.syntax) }
        if expression.kind == 22 { current = 1 }
    }
    return OwnerFlowRec(state: current, terminated: false, error_kind: 0, syntax: 0)
}

fn owner_flow_block(store: CheckStore, binding: U64, block_id: U64, state: U64) -> OwnerFlowRec {
    if block_id == 0 { return OwnerFlowRec(state: state, terminated: false, error_kind: 0, syntax: 0) }
    let block = __s0_buffer_get(CheckedBlockRec, store.control.blocks, block_id - 1)
    return owner_flow_links(store, binding, block.statements, state)
}

fn owner_flow_statement(store: CheckStore, binding: U64, statement_id: U64, state: U64) -> OwnerFlowRec {
    let statement = __s0_buffer_get(CheckedStatementRec, store.control.statements, statement_id - 1)
    let expression = owner_flow_expression(store, binding, statement.expression, state)
    if expression.error_kind != 0 { return expression }
    let current = expression.state
    if statement.kind == 4 {
        if current == 0 { return OwnerFlowRec(state: current, terminated: true, error_kind: 93, syntax: statement.syntax) }
        return OwnerFlowRec(state: current, terminated: true, error_kind: 0, syntax: 0)
    }
    if statement.kind == 6 { return owner_flow_block(store, binding, statement.body, current) }
    if statement.kind == 7 {
        let yes = owner_flow_block(store, binding, statement.body, current)
        if yes.error_kind != 0 { return yes }
        var no = OwnerFlowRec(state: current, terminated: false, error_kind: 0, syntax: 0)
        if statement.alternative != 0 { no = owner_flow_block(store, binding, statement.alternative, current) }
        if no.error_kind != 0 { return no }
        if yes.terminated && no.terminated { return OwnerFlowRec(state: current, terminated: true, error_kind: 0, syntax: 0) }
        if yes.terminated { return no }
        if no.terminated { return yes }
        if yes.state != no.state { return OwnerFlowRec(state: current, terminated: false, error_kind: 94, syntax: statement.syntax) }
        return yes
    }
    if statement.kind == 8 || statement.kind == 9 {
        let body = owner_flow_block(store, binding, statement.body, current)
        if body.error_kind != 0 { return body }
        if !body.terminated && body.state != current { return OwnerFlowRec(state: current, terminated: false, error_kind: 94, syntax: statement.syntax) }
    }
    if (statement.kind == 1 || statement.kind == 2) && statement.binding == binding {
        return OwnerFlowRec(state: 0, terminated: false, error_kind: 0, syntax: 0)
    }
    return OwnerFlowRec(state: current, terminated: false, error_kind: 0, syntax: 0)
}

fn owner_flow_links(store: CheckStore, binding: U64, link_id: U64, state: U64) -> OwnerFlowRec {
    if link_id == 0 { return OwnerFlowRec(state: state, terminated: false, error_kind: 0, syntax: 0) }
    let link = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, link_id - 1)
    let before = owner_flow_links(store, binding, link.next, state)
    if before.error_kind != 0 || before.terminated { return before }
    return owner_flow_statement(store, binding, link.statement, before.state)
}

// Bodies are checked compositionally in source order. Every concrete body is
// complete or produces one source diagnostic; control-flow and every nested
// block retain concrete-instance ownership and persistent environments.
fn check_body(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    if !((symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13) { return Ok(CheckGood(store)) }
    let declaration = __s0_buffer_get(SymbolRec, store.symbols, instance_declaration(store, owner) - 1)
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, declaration.node - 1)
    let body_link = __s0_buffer_get(SyntaxLinkRec, parse.links, root.children - 1)
    let body = __s0_buffer_get(SyntaxRec, parse.nodes, body_link.node - 1)
    let with_parameters = try append_parameter_bindings(d, parse, store, owner)
    let events = try __s0_buffer_new(BodyEventRec, d)
    let built = try build_body_event(d, parse, events, 1, body_link.node)
    let stepped = try check_body_event(d, state, parse, built.events, with_parameters, owner, built.event, false, false)
    let after = match stepped {
        BodyGood(value) => value.store
        BodyBad(value) => value
    }
    if match stepped {
        BodyGood(value) => false
        BodyBad(value) => true
    } { return Ok(CheckBad(rollback_body(store, after))) }
    let checked_block = match stepped {
        BodyGood(value) => value
        BodyBad(value) => BodyValueRec(store: value, environment: 0, semantic: 0, guaranteed_return: false)
    }
    let result_use_id = function_use(after, owner, 6, body, state)
    let result_use = __s0_buffer_get(DeclTypeUseRec, after.uses, result_use_id - 1)
    let result_type = __s0_buffer_get(CheckedTypeRec, after.types, result_use.checked_type - 1)
    if (result_type.kind != 1 || result_type.target != 12) && !checked_block.guaranteed_return {
        let failed = try check_token_fail(d, state, after, 67, body)
        let bad = match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        return Ok(CheckBad(rollback_body(store, bad)))
    }
    var local_at: U64 = 0
    while local_at < __s0_buffer_len(LocalRec, after.locals) {
        let local = __s0_buffer_get(LocalRec, after.locals, local_at)
        var owned = false
        var initial_state: U64 = 0
        if local.owner == owner && local.kind == 1 && __s0_buffer_get(SyntaxRec, parse.nodes, local.syntax - 1).kind == 48 { owned = true }
        var cleanup_registered = false
        if local.owner == owner {
            // A registered owner stays in owner flow: use after transfer and
            // partial-path transfers remain invalid. Only the must-transfer
            // exit rule is suppressed, because an exit in the available state
            // runs the registered cleanup instead.
            var cleanup_at: U64 = 0
            while cleanup_at < __s0_buffer_len(CheckedCleanupRec, after.control.cleanups) {
                if __s0_buffer_get(CheckedCleanupRec, after.control.cleanups, cleanup_at).binding == local_at + 1 { cleanup_registered = true }
                cleanup_at = cleanup_at + 1
            }
        }
        var owner_is_cleanup_hook = false
        if local.owner == owner && local.kind == 1 {
            let hook_self = __s0_buffer_get(SyntaxRec, parse.nodes, local.syntax - 1)
            if hook_self.kind == 48 {
                if symbol_is_cleanup_hook(state, after, owner) { owner_is_cleanup_hook = true }
            }
        }
        if local.owner == owner && local.kind == 2 {
            let empty = try __s0_buffer_new(TypeBindingRec, d)
            let no_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
            let category = try interpreted_type_category(d, state, parse, after, empty, no_ancestry, local.checked_type, 0, 0)
            if category.category == 2 {
                owned = true
                initial_state = 2
            }
        }
        if owned {
            var flow = owner_flow_block(after, local_at + 1, checked_block.semantic, initial_state)
            // A cleanup hook's take-self parameter is the disposal itself:
            // returning without a further transfer is the normal shape, so
            // the inline return-exit rule is cleared for it.
            if flow.error_kind == 93 && owner_is_cleanup_hook && flow.syntax != 0 { flow = OwnerFlowRec(state: flow.state, terminated: flow.terminated, error_kind: 0, syntax: 0) }
            if flow.error_kind != 0 || (!cleanup_registered && !owner_is_cleanup_hook && !flow.terminated && flow.state == 0) {
                var diagnostic_kind: U64 = 93
                var diagnostic_node = __s0_buffer_get(SyntaxRec, parse.nodes, local.syntax - 1)
                if flow.error_kind != 0 {
                    diagnostic_kind = flow.error_kind
                    diagnostic_node = __s0_buffer_get(SyntaxRec, parse.nodes, flow.syntax - 1)
                }
                let failed = try check_token_fail(d, state, after, diagnostic_kind, diagnostic_node)
                let bad = match failed {
                    CheckGood(value) => value
                    CheckBad(value) => value
                }
                return Ok(CheckBad(rollback_body(store, bad)))
            }
        }
        local_at = local_at + 1
    }
    return Ok(CheckGood(after))
}

fn check_function_body_at(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckResult, __s0_Error) {
    var at = owner
    var current = store
    var failed: U64 = 0
    var last: CheckResult = CheckGood(store)
    while at <= __s0_buffer_len(SymbolRec, current.symbols) {
        let result = try check_body(d, state, parse, current, at)
        current = check_result_store(result)
        last = result
        if check_result_bad(result) { failed = 1 }
        if failed == 0 { at = at + 1 }
        if failed != 0 { at = __s0_buffer_len(SymbolRec, current.symbols) + 1 }
    }
    return Ok(last)
}

fn check_function_bodies(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    return check_function_body_at(d, state, parse, store, 1)
}

fn private_signature_type(store: CheckStore, checked_type: U64) -> U64 {
    if checked_type == 0 { return 0 }
    let item = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if item.kind == 7 {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, item.target - 1)
        if symbol.module_source != 0 && !symbol.public { return item.target }
    }
    var at: U64 = 0
    while at < item.arg_count {
        let hidden = private_signature_type(store, __s0_buffer_get(U64, store.type_args, item.first_arg - 1 + at))
        if hidden != 0 { return hidden }
        at = at + 1
    }
    return 0
}

fn check_public_signatures(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        let owner = __s0_buffer_get(SymbolRec, store.symbols, use.owner - 1)
        if owner.public {
            let hidden = private_signature_type(store, use.checked_type)
            if hidden != 0 {
                let symbol = __s0_buffer_get(SymbolRec, store.symbols, hidden - 1)
                let node = __s0_buffer_get(SyntaxRec, parse.nodes, use.syntax - 1)
                return check_fail(d, store, 88, node, symbol.source, symbol.name_start, symbol.name_end)
            }
        }
        at = at + 1
    }
    return Ok(CheckGood(store))
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
    let indexed_aggregates = try build_use_indexes(d, after_aggregates, false)
    let cycles = try reject_value_cycles(d, state, parse, indexed_aggregates)
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
    let structural = try synthesize_structural_impls(d, state, parse, after_restrictions)
    let after_structural = match structural {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match structural {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(structural) }
    let imports = try check_declaration_kind(d, state, parse, after_structural, 1)
    let after_imports = match imports {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match imports {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(imports) }
    let traits = try check_declaration_kind(d, state, parse, after_imports, 50)
    let after_traits = match traits {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match traits {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(traits) }
    let functions = try check_declaration_kind(d, state, parse, after_traits, 12)
    let after_functions = match functions {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match functions {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(functions) }
    let trait_impls_valid = try validate_trait_impls(d, state, parse, after_functions)
    let after_trait_impls = match trait_impls_valid {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match trait_impls_valid {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(trait_impls_valid) }
    let public_signatures = try check_public_signatures(d, state, parse, after_trait_impls)
    let after_public_signatures = match public_signatures {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match public_signatures {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(public_signatures) }
    // The reserve pass runs after the complete use index is built: thunk
    // symbols exist before any body is checked, while their site-time uses
    // stay outside the index and resolve through the scan fallbacks.
    let indexed = try build_use_indexes(d, after_public_signatures, true)
    let reserved = try reserve_closure_symbols(d, state, parse, indexed)
    let after_reserved = match reserved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match reserved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(reserved) }
    return check_function_bodies(d, state, parse, after_reserved)
}

// Reserve the synthetic thunk symbol and site record for every closure
// literal before any function body is checked, in source order. Appending
// symbols while a body is mid-check destabilizes the deferred body loop and
// the record-constructor scans, so the symbol exists up front and the site
// check only fills in types, uses, and captures. The site's expression field
// holds the closure syntax node id until the site check links the checked
// expression.
fn reserve_closure_symbols(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var current = store
    var node_at: U64 = 1
    while node_at <= __s0_buffer_len(SyntaxRec, parse.nodes) {
        let node = __s0_buffer_get(SyntaxRec, parse.nodes, node_at - 1)
        if node.kind == 58 {
            let symbol_id = __s0_buffer_len(SymbolRec, current.symbols) + 1
            let symbols = try __s0_buffer_append(SymbolRec, d, current.symbols, SymbolRec(kind: 12, node: node_at, source: node.source, name_start: node.name_start, name_end: node.name_end, type_arity: 0, declaration: symbol_id, first_instance_arg: 0, instance_arg_count: 0, discovery_parent: 0, inherent_owner: 0, module_source: 0, public: false))
            var sites = current.closures.sites
            sites = try __s0_buffer_append(ClosureSiteRec, d, sites, ClosureSiteRec(owner: symbol_id, expression: node_at, declared_count: 0, capture_count: 0, first_capture: 0))
            current = CheckStore(symbols: symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: current.traits, closures: ClosureStoreRec(sites: sites, captures: current.closures.captures))
        }
        node_at = node_at + 1
    }
    return Ok(CheckGood(current))
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
    // String and Bytes singletons exist from the start so structural Eq and
    // Hash synthesis can target them without a prior source reference.
    if canonical_type_id(seeded, 2, 0, 0, 0) == 0 { seeded = try append_checked_type(d, seeded, 0, 2, 0, 0, 0, 0) }
    if canonical_type_id(seeded, 14, 0, 0, 0) == 0 { seeded = try append_checked_type(d, seeded, 0, 14, 0, 0, 0, 0) }
    let symbols = try collect_symbols(d, state, parse, seeded)
    let store = match symbols {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match symbols {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(symbols) }
    let impls = try resolve_trait_impls(d, state, parse, store)
    let with_impls = match impls {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match impls {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(impls) }
    return check_declarations(d, state, parse, with_impls)
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

fn emit_checked_symbols(store: CheckStore) -> Bool {
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
    return true
}

fn emit_checked_types(store: CheckStore) -> Bool {
    var at: U64 = 0
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
    return true
}

fn emit_checked_control(store: CheckStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(CheckedMatchRec, store.control.matches) {
        let rec = __s0_buffer_get(CheckedMatchRec, store.control.matches, at)
        if !out_string("M ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.scrutinee) || !out(32) || !out_u64(rec.scrutinee_type) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.first_arm) || !out(32) || !out_u64(rec.arm_count) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedMatchArmRec, store.control.match_arms) {
        let rec = __s0_buffer_get(CheckedMatchArmRec, store.control.match_arms, at)
        if !out_string("W ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_match) || !out(32) || !out_u64(rec.variant_use) || !out(32) || !out_u64(rec.variant_kind) || !out(32) || !out_u64(rec.binding) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.body) || !out(32) || !out_u64(rec.block) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedTryRec, store.control.tries) {
        let rec = __s0_buffer_get(CheckedTryRec, store.control.tries, at)
        if !out_string("X ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.expression) || !out(32) || !out_u64(rec.result_type) || !out(32) || !out_u64(rec.ok_type) || !out(32) || !out_u64(rec.error_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedCleanupRec, store.control.cleanups) {
        let rec = __s0_buffer_get(CheckedCleanupRec, store.control.cleanups, at)
        if !out_string("G ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.binding) || !out(32) || !out_u64(rec.initializer) || !out(32) || !out_u64(rec.callback) || !out(32) || !out_u64(rec.drain) || !out(32) || !out_u64(rec.normal_exit) || !out(32) || !out_u64(rec.return_exit) || !out(32) || !out_u64(rec.try_exit) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedPlaceRec, store.control.places) {
        let rec = __s0_buffer_get(CheckedPlaceRec, store.control.places, at)
        if !out_string("V ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.root) || !out(32) || !out_u64(rec.field) || !out(32) || !out_u64(rec.index) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementRec, store.control.statements) {
        let rec = __s0_buffer_get(CheckedStatementRec, store.control.statements, at)
        if !out_string("J ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.expression) || !out(32) || !out_u64(rec.place) || !out(32) || !out_u64(rec.binding) || !out(32) || !out_u64(rec.body) || !out(32) || !out_u64(rec.alternative) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedStatementLinkRec, store.control.statement_links) {
        let rec = __s0_buffer_get(CheckedStatementLinkRec, store.control.statement_links, at)
        if !out_string("K ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.statement) || !out(32) || !out_u64(rec.next) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CheckedBlockRec, store.control.blocks) {
        let rec = __s0_buffer_get(CheckedBlockRec, store.control.blocks, at)
        if !out_string("B ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.statements) || !out(32) || !out_u64(rec.guaranteed_return) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_checked_expressions(store: CheckStore) -> Bool {
    var at: U64 = 0
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
    return true
}

fn emit_checked_bindings(store: CheckStore) -> Bool {
    var at: U64 = 0
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
        if !out_string("Q ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.target) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.variant_use) || !out(32) || !out_u64(rec.builtin) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_check_spans(parse: ParseStore) -> Bool {
    var at: U64 = 0
    while at < __s0_buffer_len(SyntaxRec, parse.nodes) {
        let rec = __s0_buffer_get(SyntaxRec, parse.nodes, at)
        if !out_string("Z ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.start) || !out(32) || !out_u64(rec.end) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn diagnostic_note(kind: U64) -> U64 {
    if kind == 1 { return 1 }
    if kind == 3 { return 2 }
    return 0
}

fn emit_check_diagnostic(rec: CheckDiagRec) -> Bool {
    let related = rec.related_start != 0 || rec.related_end != 0
    if !out_string("D ") || !out_u64(rec.kind) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.start) || !out(32) || !out_u64(rec.end) || !out(32) { return false }
    if related {
        if !out_string("1 ") || !out_u64(rec.related_source) || !out(32) || !out_u64(rec.related_start) || !out(32) || !out_u64(rec.related_end) || !out(32) || !out_u64(diagnostic_note(rec.kind)) || !out(10) { return false }
    } else { if !out_string("0 ") || !out_u64(diagnostic_note(rec.kind)) || !out(10) { return false } }
    return true
}

fn emit_check_manifest(state: State, parse: ParseStore, store: CheckStore) -> Bool {
    // Checker paths are hex encoded so every host path remains one unambiguous
    // whitespace-delimited field. All later records refer to numeric source IDs.
    if !out_string("ALDER-CHECKER-MANIFEST 16\n") || !emit_check_sources(state) || !emit_check_spans(parse) { return false }
    if !emit_checked_symbols(store) { return false }
    if !emit_checked_types(store) { return false }
    if !emit_checked_bindings(store) { return false }
    if !emit_checked_expressions(store) { return false }
    if !emit_checked_control(store) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(CheckDiagRec, store.diagnostics) {
        let rec = __s0_buffer_get(CheckDiagRec, store.diagnostics, at)
        if !emit_check_diagnostic(rec) { return false }
        at = at + 1
    }
    return out_string("END\n")
}

// Where-clause checking walks declaration children recursively: resolved
// trait references carry storage (the checked store), and storage-bearing
// call results must not cross loop backedges.
fn check_owner_constraints(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, root: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    return check_constraint_children(d, state, parse, store, owner, root.children)
}

fn check_constraint_children(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_at: U64) -> Result(CheckResult, __s0_Error) {
    if link_at == 0 { return Ok(CheckGood(store)) }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    if child.kind != 52 { return check_constraint_children(d, state, parse, store, owner, item.next) }
    return check_constraint_items(d, state, parse, store, owner, child.children, item.next, store.traits.constraints)
}

// After one where clause completes, resume the outer declaration walk.
fn check_constraint_items(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, constraint_at: U64, continue_at: U64, initial: __s0_Buffer(TraitConstraintRec)) -> Result(CheckResult, __s0_Error) {
    if constraint_at == 0 {
        if __s0_buffer_len(TraitConstraintRec, store.traits.constraints) == __s0_buffer_len(TraitConstraintRec, initial) { return check_constraint_children(d, state, parse, store, owner, continue_at) }
        return check_constraint_children(d, state, parse, store, owner, continue_at)
    }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, constraint_at - 1)
    let constraint = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    let param = find_type_param(state, store, owner, constraint)
    if param == 0 { return check_token_fail(d, state, store, 112, constraint) }
    return check_constraint_traits(d, state, parse, store, owner, param, item.node, constraint.children, constraint_at, continue_at, initial)
}

fn check_constraint_traits(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, param: U64, constraint_node: U64, trait_at: U64, constraint_at: U64, continue_at: U64, initial: __s0_Buffer(TraitConstraintRec)) -> Result(CheckResult, __s0_Error) {
    if trait_at == 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, constraint_at - 1)
        return check_constraint_items(d, state, parse, store, owner, item.next, continue_at, initial)
    }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, trait_at - 1)
    let trait_node = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    let reference = try resolve_trait_reference(d, state, parse, store, owner, trait_node)
    let current = match reference {
        TraitRefGood(value) => value.store
        TraitRefBad(value) => value
    }
    if match reference {
        TraitRefGood(value) => false
        TraitRefBad(value) => true
    } { return Ok(CheckBad(current)) }
    let resolved = match reference {
        TraitRefGood(value) => value.reference
        TraitRefBad(value) => TraitRefRec(builtin: 0, symbol: 0, first_arg: 0, arg_count: 0)
    }
    let constraints = try __s0_buffer_append(TraitConstraintRec, d, current.traits.constraints, TraitConstraintRec(owner: owner, param: param, trait_builtin: resolved.builtin, trait_symbol: resolved.symbol, first_arg: resolved.first_arg, arg_count: resolved.arg_count, syntax: constraint_node))
    let recorded = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics, traits: TraitStoreRec(constraints: constraints, impls: current.traits.impls, impl_index: current.traits.impl_index, args: current.traits.args, receiver_index: current.traits.receiver_index), closures: current.closures)
    return check_constraint_traits(d, state, parse, recorded, owner, param, constraint_node, item.next, constraint_at, continue_at, initial)
}

// Trait method requirements: resolve parameter and result types in the
// trait's scope, where `Self` is the implicit trailing parameter. A
// requirement may declare its own leading type parameters; they are
// recorded in the trait's scope after the trait's parameters (collect
// tail-first like a function's parameters, keeping the store out of loop
// backedges), so their names must be unique across the whole trait.
fn check_trait_method(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let collected = try collect_param_links(d, state, parse, store, owner, node.children)
    let current = match collected {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if check_result_bad(collected) { return Ok(collected) }
    return check_trait_method_links(d, state, parse, current, owner, node.children)
}

fn check_trait_method_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_at: U64) -> Result(CheckResult, __s0_Error) {
    if link_at == 0 { return Ok(CheckGood(store)) }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    if child.kind == 7 { return check_trait_method_links(d, state, parse, store, owner, item.next) }
    if child.kind == 13 || child.kind == 47 || child.kind == 48 {
        if child.children != 0 {
            let head = __s0_buffer_get(SyntaxLinkRec, parse.links, child.children - 1)
            let resolved = try resolve_type(d, state, parse, store, owner, head.node)
            if match resolved {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(resolved) }
            let current = match resolved {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            return check_trait_method_links(d, state, parse, current, owner, item.next)
        }
    }
    if child.kind == 4 || child.kind == 5 || child.kind == 6 || child.kind == 56 {
        let resolved = try resolve_type(d, state, parse, store, owner, item.node)
        if match resolved {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(resolved) }
        let current = match resolved {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        return check_trait_method_links(d, state, parse, current, owner, item.next)
    }
    return check_trait_method_links(d, state, parse, store, owner, item.next)
}

fn check_trait_declaration(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, root: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let with_self = try append_trait_self_param(d, state, parse, store, owner)
    let constrained = try check_owner_constraints(d, state, parse, with_self, owner, root)
    if match constrained {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(constrained) }
    let current = match constrained {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return check_trait_method_decls(d, state, parse, current, owner, root.children)
}

fn check_trait_method_decls(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_at: U64) -> Result(CheckResult, __s0_Error) {
    if link_at == 0 { return Ok(CheckGood(store)) }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    if child.kind != 51 { return check_trait_method_decls(d, state, parse, store, owner, item.next) }
    let checked = try check_trait_method(d, state, parse, store, owner, child)
    if match checked {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(checked) }
    let current = match checked {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return check_trait_method_decls(d, state, parse, current, owner, item.next)
}

// The parser links the trait application first and the implemented type
// second, so the application is the chain tail and the type is the link
// that points at it.
fn trait_impl_self_node(parse: ParseStore, root: SyntaxRec) -> U64 {
    var link_at = root.children
    var tail: U64 = 0
    var tail_link: U64 = 0
    while link_at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
        if item.next == 0 { tail = item.node
        tail_link = link_at }
        link_at = item.next
    }
    if tail == 0 { return 0 }
    link_at = root.children
    while link_at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
        if item.next == tail_link { return item.node }
        link_at = item.next
    }
    return 0
}

// Coherence keys are (trait reference, implementing type, trait
// arguments): exactly one implementation per concrete combination.
fn trait_impl_key_less(store: CheckStore, left: TraitImplRec, right: TraitImplRec) -> Bool {
    if left.trait_builtin != right.trait_builtin { return left.trait_builtin < right.trait_builtin }
    if left.trait_symbol != right.trait_symbol { return left.trait_symbol < right.trait_symbol }
    if left.self_type != right.self_type { return left.self_type < right.self_type }
    var at: U64 = 0
    while at < left.arg_count && at < right.arg_count {
        let left_type = __s0_buffer_get(U64, store.traits.args, left.first_arg - 1 + at)
        let right_type = __s0_buffer_get(U64, store.traits.args, right.first_arg - 1 + at)
        if left_type != right_type { return left_type < right_type }
        at = at + 1
    }
    return left.arg_count < right.arg_count
}

fn trait_impl_key_equal(store: CheckStore, left: TraitImplRec, right: TraitImplRec) -> Bool {
    if left.trait_builtin != right.trait_builtin || left.trait_symbol != right.trait_symbol || left.self_type != right.self_type || left.arg_count != right.arg_count { return false }
    var at: U64 = 0
    while at < left.arg_count {
        if __s0_buffer_get(U64, store.traits.args, left.first_arg - 1 + at) != __s0_buffer_get(U64, store.traits.args, right.first_arg - 1 + at) { return false }
        at = at + 1
    }
    return true
}

fn trait_impl_receiver_type_symbol(store: CheckStore, rec: TraitImplRec) -> U64 {
    if rec.self_type == 0 { return 0 }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, rec.self_type - 1)
    if checked.kind != 7 { return 0 }
    return checked.target
}

fn trait_impl_receiver_less(store: CheckStore, left: TraitImplRec, right: TraitImplRec) -> Bool {
    let left_target = trait_impl_receiver_type_symbol(store, left)
    let right_target = trait_impl_receiver_type_symbol(store, right)
    if left_target != right_target { return left_target < right_target }
    if left.trait_builtin != right.trait_builtin { return left.trait_builtin < right.trait_builtin }
    return left.trait_symbol < right.trait_symbol
}

// Resolve one method name for a concrete nominal receiver: inherent methods
// win, then the unique trait implementation providing that method name.
// Returns the resolved method symbol; ambiguous marks two impls providing
// the same name for one receiver type.
type TraitMethodRec {
    target: U64
    ambiguous: Bool
    defaulted: Bool
}

fn trait_impl_method_symbol(state: State, parse: ParseStore, store: CheckStore, rec: TraitImplRec, name: SyntaxRec) -> U64 {
    var at = rec.first_method
    while at < rec.first_method + rec.method_count {
        let symbol = __s0_buffer_get(SymbolRec, store.symbols, at - 1)
        if same_name(state, name.source, name.name_start, name.name_end, symbol.source, symbol.name_start, symbol.name_end) { return at }
        at = at + 1
    }
    return 0
}

fn trait_method_has_default(state: State, parse: ParseStore, store: CheckStore, rec: TraitImplRec, name: SyntaxRec) -> Bool {
    if rec.trait_symbol == 0 { return false }
    let trait_symbol = __s0_buffer_get(SymbolRec, store.symbols, rec.trait_symbol - 1)
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, trait_symbol.node - 1)
    var link_at = root.children
    while link_at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 51 && same_name(state, name.source, name.name_start, name.name_end, child.source, child.name_start, child.name_end) {
            // A requirement with a block carries the default body.
            var body_at = child.children
            var has_block = false
            while body_at != 0 {
                let body_item = __s0_buffer_get(SyntaxLinkRec, parse.links, body_at - 1)
                if __s0_buffer_get(SyntaxRec, parse.nodes, body_item.node - 1).kind == 14 { has_block = true }
                body_at = body_item.next
            }
            return has_block
        }
        link_at = item.next
    }
    return false
}

fn trait_receiver_method(state: State, parse: ParseStore, store: CheckStore, receiver: CheckedTypeRec, name: SyntaxRec) -> TraitMethodRec {
    var found: U64 = 0
    var ambiguous = false
    var defaulted = false
    var structural = false
    if receiver.kind != 7 || __s0_buffer_len(U64, store.traits.receiver_index) == 0 { return TraitMethodRec(target: 0, ambiguous: false, defaulted: false) }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, store.traits.receiver_index) {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, at) - 1)
        if trait_impl_receiver_type_symbol(store, rec) == receiver.target {
            let method = trait_impl_method_symbol(state, parse, store, rec, name)
            if method != 0 {
                if found != 0 { ambiguous = true } else { found = method }
            } else {
                if trait_method_has_default(state, parse, store, rec, name) { defaulted = true }
                // Structural Eq/Hash impls satisfy constraints but expose no
                // callable method symbols until the ordered collections
                // land; they only shadow their own method names.
                if rec.synthesized != 0 && ((rec.trait_builtin == 1 && node_word(state, name, "eq")) || (rec.trait_builtin == 2 && node_word(state, name, "hash"))) { structural = true }
            }
        }
        at = at + 1
    }
    if structural { return TraitMethodRec(target: 0, ambiguous: false, defaulted: false) }
    return TraitMethodRec(target: found, ambiguous: ambiguous, defaulted: defaulted)
}

fn trait_store_with(store: CheckStore, impls: __s0_Buffer(TraitImplRec), index: __s0_Buffer(U64)) -> CheckStore {
    return CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics, traits: TraitStoreRec(constraints: store.traits.constraints, impls: impls, impl_index: index, args: store.traits.args, receiver_index: store.traits.receiver_index), closures: store.closures)
}

// Compare one requirement-side type with one impl-method-side type.
// Trait parameters substitute positionally from the impl's trait arguments
// and `Self` substitutes to the implementing type. A requirement method's
// own type parameters (the contiguous method_first..method_first+
// method_count records, owned by the trait) match only the impl method's
// type parameter at the same position (impl_symbol's records).
fn trait_impl_type_matches(store: CheckStore, trait_symbol_id: U64, requirement: U64, impl_type: U64, first_arg: U64, arg_count: U64, self_type: U64, method_first: U64, method_count: U64, impl_symbol: U64, depth: U64) -> Bool {
    if requirement == 0 || impl_type == 0 || depth > 16 { return false }
    let req = __s0_buffer_get(CheckedTypeRec, store.types, requirement - 1)
    let got = __s0_buffer_get(CheckedTypeRec, store.types, impl_type - 1)
    if req.kind == 6 {
        if method_count != 0 && req.target >= method_first && req.target < method_first + method_count {
            if got.kind != 6 || impl_symbol == 0 { return false }
            return type_param_ordinal(store, impl_symbol, got.target) == req.target - method_first
        }
        // type_param_ordinal counts from zero and the requirement's
        // parameters always belong to the trait.
        var substituted: U64 = 0
        let ordinal = type_param_ordinal(store, trait_symbol_id, req.target)
        if ordinal < arg_count { substituted = __s0_buffer_get(U64, store.traits.args, first_arg - 1 + ordinal) } else {
            let self_param = trait_self_param(store, trait_symbol_id)
            if self_param != 0 && req.target == self_param { substituted = self_type }
        }
        if substituted == 0 { return false }
        let sub = __s0_buffer_get(CheckedTypeRec, store.types, substituted - 1)
        return got.kind == sub.kind && got.target == sub.target && got.arg_count == sub.arg_count
    }
    if req.kind != got.kind || req.target != got.target || req.arg_count != got.arg_count { return false }
    var at: U64 = 0
    while at < req.arg_count {
        if !trait_impl_type_matches(store, trait_symbol_id, __s0_buffer_get(U64, store.type_args, req.first_arg - 1 + at), __s0_buffer_get(U64, store.type_args, got.first_arg - 1 + at), first_arg, arg_count, self_type, method_first, method_count, impl_symbol, depth + 1) { return false }
        at = at + 1
    }
    return true
}

fn symbol_name_matches_word(state: State, symbol: SymbolRec, word: __s0_String) -> Bool {
    let source = __s0_buffer_get(SourceRec, state.sources, symbol.source)
    return source_word(state, source, symbol.name_start, symbol.name_end, word)
}

// The receiver parameter kind one method declares: 13 for a plain `self`,
// 47 for `mut self`, 48 for `take self`, and 0 when the first runtime
// parameter is not a receiver.
fn method_receiver_kind(state: State, parse: ParseStore, store: CheckStore, owner: U64) -> U64 {
    let first = use_by_ordinal(store, owner, 5, 0)
    if first == 0 { return 0 }
    let use = __s0_buffer_get(DeclTypeUseRec, store.uses, first - 1)
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, use.node - 1)
    if !node_word(state, node, "self") { return 0 }
    return node.kind
}

// Validate one impl method against one builtin or user-trait requirement.
// Receiver mode, runtime arity, and every resolved type must agree after
// trait-parameter substitution.
fn trait_requirement_node(state: State, parse: ParseStore, requirement_node: U64) -> SyntaxRec {
    return __s0_buffer_get(SyntaxRec, parse.nodes, requirement_node - 1)
}

fn validate_one_trait_impl(d: Domain, state: State, parse: ParseStore, initial: CheckStore, rec: TraitImplRec) -> Result(CheckResult, __s0_Error) {
    var store = initial
    let impl_node = __s0_buffer_get(SyntaxRec, parse.nodes, rec.owner_node - 1)
    // Builtin traits have exactly one fixed requirement each.
    if rec.trait_builtin != 0 {
        var word: __s0_String = "cleanup"
        var receiver_kind: U64 = 13
        var runtime_params: U64 = 0
        var first_param_type: U64 = 0
        var result_type = canonical_type_id(store, 1, 12, 0, 0)
        if rec.trait_builtin == 1 {
            word = "eq"
            runtime_params = 1
            first_param_type = rec.self_type
            result_type = canonical_type_id(store, 1, 1, 0, 0)
        }
        if rec.trait_builtin == 2 {
            word = "hash"
            result_type = canonical_type_id(store, 1, 9, 0, 0)
        }
        if rec.trait_builtin == 3 {
            word = "next"
            receiver_kind = 47
            result_type = canonical_single_arg(store, 9, 0, __s0_buffer_get(U64, store.traits.args, rec.first_arg - 1))
        }
        if rec.trait_builtin == 4 {
            word = "into_iterator"
            result_type = __s0_buffer_get(U64, store.traits.args, rec.first_arg - 1)
        }
        if rec.trait_builtin == 5 {
            receiver_kind = 48
        }
        var found: U64 = 0
        var method_at = rec.first_method
        while method_at < rec.first_method + rec.method_count {
            let method = __s0_buffer_get(SymbolRec, store.symbols, method_at - 1)
            if symbol_name_matches_word(state, method, word) { found = method_at }
            method_at = method_at + 1
        }
        if found == 0 { return check_token_fail(d, state, store, 121, impl_node) }
        let method = __s0_buffer_get(SymbolRec, store.symbols, found - 1)
        // A builtin requirement is never generic, so a generic impl method
        // cannot match its signature.
        if method.type_arity != 0 { return check_token_fail(d, state, store, 123, __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)) }
        if method_receiver_kind(state, parse, store, found) != receiver_kind { return check_token_fail(d, state, store, 123, __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)) }
        if use_count(store, found, 5) != runtime_params + 1 { return check_token_fail(d, state, store, 123, __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)) }
        if runtime_params != 0 {
            let use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_by_ordinal(store, found, 5, 1) - 1)
            if !trait_impl_type_matches(store, 0, first_param_type, use.checked_type, rec.first_arg, rec.arg_count, rec.self_type, 0, 0, 0, 0) { return check_token_fail(d, state, store, 123, __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)) }
        }
        let result_use = __s0_buffer_get(DeclTypeUseRec, store.uses, use_by_ordinal(store, found, 6, 0) - 1)
        if !trait_impl_type_matches(store, 0, result_type, result_use.checked_type, rec.first_arg, rec.arg_count, rec.self_type, 0, 0, 0, 0) { return check_token_fail(d, state, store, 123, __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)) }
        return Ok(CheckGood(store))
    }
    // User traits: every kind-51 requirement must be provided or defaulted,
    // and every impl method must match some requirement.
    let trait_symbol = __s0_buffer_get(SymbolRec, store.symbols, rec.trait_symbol - 1)
    let trait_node = __s0_buffer_get(SyntaxRec, parse.nodes, trait_symbol.node - 1)
    let user_validated = try validate_user_requirements(d, state, parse, store, rec, trait_node.children)
    if match user_validated {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(user_validated) }
    var current = match user_validated {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    // Every impl method must match some requirement name (no calls).
    var extra_at = rec.first_method
    while extra_at < rec.first_method + rec.method_count {
        let method = __s0_buffer_get(SymbolRec, current.symbols, extra_at - 1)
        var matched = false
        var link_at = trait_node.children
        while link_at != 0 {
            let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
            let requirement = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
            if requirement.kind == 51 && same_name(state, requirement.source, requirement.name_start, requirement.name_end, method.source, method.name_start, method.name_end) { matched = true }
            link_at = item.next
        }
        if !matched { return check_token_fail(d, state, current, 122, __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)) }
        extra_at = extra_at + 1
    }
    return Ok(CheckGood(current))
}

// Walk the trait's requirements recursively: resolved requirement types
// carry storage, so they must not cross loop backedges.
// A requirement's own type parameters are recorded in the trait's scope as
// one contiguous run after the trait's parameters; they are identified by
// their parameter nodes, which are direct kind-7 children of the
// requirement node.
fn requirement_method_param_first(parse: ParseStore, store: CheckStore, trait_symbol: U64, requirement: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let p = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if p.owner == trait_symbol {
            var link_at = requirement.children
            while link_at != 0 {
                let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
                if item.node == p.node { return at + 1 }
                link_at = item.next
            }
        }
        at = at + 1
    }
    return 0
}

fn requirement_method_param_count(parse: ParseStore, requirement: SyntaxRec) -> U64 {
    var total: U64 = 0
    var link_at = requirement.children
    while link_at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
        if __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1).kind == 7 { total = total + 1 }
        link_at = item.next
    }
    return total
}

fn validate_user_requirements(d: Domain, state: State, parse: ParseStore, store: CheckStore, rec: TraitImplRec, link_at: U64) -> Result(CheckResult, __s0_Error) {
    if link_at == 0 { return Ok(CheckGood(store)) }
    let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
    let requirement = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
    if requirement.kind != 51 { return validate_user_requirements(d, state, parse, store, rec, item.next) }
    var found: U64 = 0
    var method_at = rec.first_method
    while method_at < rec.first_method + rec.method_count {
        let method = __s0_buffer_get(SymbolRec, store.symbols, method_at - 1)
        if same_name(state, requirement.source, requirement.name_start, requirement.name_end, method.source, method.name_start, method.name_end) { found = method_at }
        method_at = method_at + 1
    }
    if found == 0 {
        // A requirement with a block may fall back to its default body.
        var has_default = false
        var body_at = requirement.children
        while body_at != 0 {
            let body_item = __s0_buffer_get(SyntaxLinkRec, parse.links, body_at - 1)
            if __s0_buffer_get(SyntaxRec, parse.nodes, body_item.node - 1).kind == 14 { has_default = true }
            body_at = body_item.next
        }
        if !has_default { return check_token_fail(d, state, store, 121, __s0_buffer_get(SyntaxRec, parse.nodes, rec.owner_node - 1)) }
        return validate_user_requirements(d, state, parse, store, rec, item.next)
    }
    // Receiver mode and runtime arity (no calls).
    var want_receiver: U64 = 13
    var want_params: U64 = 0
    var req_at = requirement.children
    while req_at != 0 {
        let req_item = __s0_buffer_get(SyntaxLinkRec, parse.links, req_at - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, req_item.node - 1)
        if child.kind == 13 || child.kind == 47 || child.kind == 48 {
            if node_word(state, child, "self") { want_receiver = child.kind } else { want_params = want_params + 1 }
        }
        req_at = req_item.next
    }
    let method = __s0_buffer_get(SymbolRec, store.symbols, found - 1)
    let method_node = __s0_buffer_get(SyntaxRec, parse.nodes, method.node - 1)
    if method_receiver_kind(state, parse, store, found) != want_receiver { return check_token_fail(d, state, store, 123, method_node) }
    if use_count(store, found, 5) != want_params + 1 { return check_token_fail(d, state, store, 123, method_node) }
    // The impl method declares exactly as many type parameters as the
    // requirement; they match positionally through the impl substitution.
    let want_type_arity = requirement_method_param_count(parse, requirement)
    if method.type_arity != want_type_arity { return check_token_fail(d, state, store, 123, method_node) }
    let method_first = requirement_method_param_first(parse, store, rec.trait_symbol, requirement)
    // Runtime parameter and result types resolve recursively in the trait's
    // scope and compare through the impl substitution.
    let compared = try validate_requirement_params(d, state, parse, store, rec, found, requirement, requirement.children, 1, method_first, want_type_arity)
    if match compared {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(compared) }
    let with_params = match compared {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    var result_at = requirement.children
    while result_at != 0 {
        let result_item = __s0_buffer_get(SyntaxLinkRec, parse.links, result_at - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, result_item.node - 1)
        if child.kind == 4 || child.kind == 5 || child.kind == 6 || child.kind == 56 {
            // Result types were annotated during trait checking; reuse first.
            var want = checked_type_for_syntax(with_params, rec.trait_symbol, result_item.node)
            var current = with_params
            if want == 0 {
                let resolved = try resolve_type(d, state, parse, with_params, rec.trait_symbol, result_item.node)
                if match resolved {
                    CheckGood(value) => false
                    CheckBad(value) => true
                } { return Ok(resolved) }
                current = match resolved {
                    CheckGood(value) => value
                    CheckBad(value) => value
                }
                want = checked_type_for_syntax(current, rec.trait_symbol, result_item.node)
            }
            let result_use = __s0_buffer_get(DeclTypeUseRec, current.uses, use_by_ordinal(current, found, 6, 0) - 1)
            if !trait_impl_type_matches(current, rec.trait_symbol, want, result_use.checked_type, rec.first_arg, rec.arg_count, rec.self_type, method_first, want_type_arity, found, 0) { return check_token_fail(d, state, current, 123, method_node) }
            return validate_user_requirements(d, state, parse, current, rec, item.next)
        }
        result_at = result_item.next
    }
    return validate_user_requirements(d, state, parse, with_params, rec, item.next)
}

fn validate_requirement_params(d: Domain, state: State, parse: ParseStore, store: CheckStore, rec: TraitImplRec, found: U64, requirement: SyntaxRec, req_at: U64, param_ordinal: U64, method_first: U64, method_count: U64) -> Result(CheckResult, __s0_Error) {
    if req_at == 0 { return Ok(CheckGood(store)) }
    let req_item = __s0_buffer_get(SyntaxLinkRec, parse.links, req_at - 1)
    let child = __s0_buffer_get(SyntaxRec, parse.nodes, req_item.node - 1)
    if !((child.kind == 13 || child.kind == 47 || child.kind == 48) && !node_word(state, child, "self")) {
        return validate_requirement_params(d, state, parse, store, rec, found, requirement, req_item.next, param_ordinal, method_first, method_count)
    }
    if child.children != 0 {
        let head = __s0_buffer_get(SyntaxLinkRec, parse.links, child.children - 1)
        // Trait checking already annotated requirement types; reuse before
        // resolving so annotations stay unique per (owner, syntax).
        var want = checked_type_for_syntax(store, rec.trait_symbol, head.node)
        var current = store
        if want == 0 {
            let resolved = try resolve_type(d, state, parse, store, rec.trait_symbol, head.node)
            if match resolved {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(resolved) }
            current = match resolved {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            want = checked_type_for_syntax(current, rec.trait_symbol, head.node)
        }
        let use = __s0_buffer_get(DeclTypeUseRec, current.uses, use_by_ordinal(current, found, 5, param_ordinal) - 1)
        if !trait_impl_type_matches(current, rec.trait_symbol, want, use.checked_type, rec.first_arg, rec.arg_count, rec.self_type, method_first, method_count, found, 0) {
            return check_token_fail(d, state, current, 123, __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(SymbolRec, current.symbols, found - 1).node - 1))
        }
        return validate_requirement_params(d, state, parse, current, rec, found, requirement, req_item.next, param_ordinal + 1, method_first, method_count)
    }
    return validate_requirement_params(d, state, parse, store, rec, found, requirement, req_item.next, param_ordinal + 1, method_first, method_count)
}

// Validate every trait implementation once method signatures are resolved.
// Recursion is bounded by the impl count.
fn validate_trait_impls_at(d: Domain, state: State, parse: ParseStore, store: CheckStore, at: U64) -> Result(CheckResult, __s0_Error) {
    if at >= __s0_buffer_len(TraitImplRec, store.traits.impls) { return Ok(CheckGood(store)) }
    let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, at)
    if rec.synthesized != 0 { return validate_trait_impls_at(d, state, parse, store, at + 1) }
    let validated = try validate_one_trait_impl(d, state, parse, store, rec)
    if match validated {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(validated) }
    let current = match validated {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return validate_trait_impls_at(d, state, parse, current, at + 1)
}

fn validate_trait_impls(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    return validate_trait_impls_at(d, state, parse, store, 0)
}

// Resolve one trait-implementation head and record it. The implementing// Resolve one trait-implementation head and record it. The implementing// Resolve one trait-implementation head and record it. The implementing// Resolve one trait-implementation head and record it. The implementing
// type must be a non-generic declared nominal type; its symbol gives trait
// arguments a parameter-free resolution scope.
fn resolve_trait_impl_at(d: Domain, state: State, parse: ParseStore, store: CheckStore, root_at: U64) -> Result(CheckResult, __s0_Error) {
    let root_id = __s0_buffer_get(U64, parse.roots, root_at)
    let root = __s0_buffer_get(SyntaxRec, parse.nodes, root_id - 1)
    // Where clauses on impls are not supported yet: impl arguments and
    // implementing types are concrete, so nothing could bind.
    var link_at = root.children
    while link_at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
        let child = __s0_buffer_get(SyntaxRec, parse.nodes, item.node - 1)
        if child.kind == 52 { return check_token_fail(d, state, store, 113, child) }
        link_at = item.next
    }
    // The trait application is the chain tail.
    var tail: U64 = 0
    link_at = root.children
    while link_at != 0 {
        let item = __s0_buffer_get(SyntaxLinkRec, parse.links, link_at - 1)
        if item.next == 0 { tail = item.node }
        link_at = item.next
    }
    if tail == 0 { return check_fail(d, store, 110, root, 0, 0, 0) }
    let trait_node = __s0_buffer_get(SyntaxRec, parse.nodes, tail - 1)
    // Structural equality and hashing are language-provided; a user
    // implementation cannot override them.
    if builtin_trait_id(state, trait_node) == 1 || builtin_trait_id(state, trait_node) == 2 { return check_token_fail(d, state, store, 125, trait_node) }
    let self_node_id = trait_impl_self_node(parse, root)
    if self_node_id == 0 { return check_fail(d, store, 110, root, 0, 0, 0) }
    let self_node = __s0_buffer_get(SyntaxRec, parse.nodes, self_node_id - 1)
    if self_node.kind != 4 { return check_token_fail(d, state, store, 110, self_node) }
    let self_symbol = find_declared_type(state, parse, store, self_node)
    if self_symbol == 0 { return check_token_fail(d, state, store, 110, self_node) }
    let self_declared = __s0_buffer_get(SymbolRec, store.symbols, self_symbol - 1)
    if self_declared.type_arity != 0 { return check_token_fail(d, state, store, 110, self_node) }
    let appended = try append_checked_type(d, store, self_symbol, 7, self_node_id, self_symbol, 0, 0)
    let self_checked = checked_type_for_syntax(appended, self_symbol, self_node_id)
    let reference = try resolve_trait_reference(d, state, parse, appended, self_symbol, trait_node)
    let current = match reference {
        TraitRefGood(value) => value.store
        TraitRefBad(value) => value
    }
    if match reference {
        TraitRefGood(value) => false
        TraitRefBad(value) => true
    } { return Ok(CheckBad(current)) }
    let resolved = match reference {
        TraitRefGood(value) => value.reference
        TraitRefBad(value) => TraitRefRec(builtin: 0, symbol: 0, first_arg: 0, arg_count: 0)
    }
    var arg_at: U64 = 0
    var concrete = true
    while arg_at < resolved.arg_count {
        if !checked_type_concrete(current, __s0_buffer_get(U64, current.traits.args, resolved.first_arg - 1 + arg_at)) { concrete = false }
        arg_at = arg_at + 1
    }
    if !concrete { return check_token_fail(d, state, current, 116, trait_node) }
    // Impl methods are consecutive symbols collected under this impl node;
    // record their range for trait-method resolution.
    var first_method: U64 = 0
    var method_count: U64 = 0
    var symbol_at: U64 = 0
    while symbol_at < __s0_buffer_len(SymbolRec, current.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, current.symbols, symbol_at)
        if symbol.inherent_owner == root_id {
            if first_method == 0 { first_method = symbol_at + 1 }
            method_count = method_count + 1
        }
        symbol_at = symbol_at + 1
    }
    let impls = try __s0_buffer_append(TraitImplRec, d, current.traits.impls, TraitImplRec(trait_builtin: resolved.builtin, trait_symbol: resolved.symbol, first_arg: resolved.first_arg, arg_count: resolved.arg_count, self_type: self_checked, owner_node: root_id, first_method: first_method, method_count: method_count, synthesized: 0))
    return Ok(CheckGood(trait_store_with(current, impls, current.traits.impl_index)))
}

// Resolve trait implementations with bounded recursion: scanning roots is a
// call-free loop, and recursion happens only once per actual impl, so
// storage-carrying call results never cross loop backedges and recursion
// depth equals the impl count rather than the root count.
fn resolve_trait_impls_from(d: Domain, state: State, parse: ParseStore, store: CheckStore, search_at: U64) -> Result(CheckResult, __s0_Error) {
    var found: U64 = 0
    var scan = search_at
    var scanning = true
    while scanning {
        if scan >= __s0_buffer_len(U64, parse.roots) { scanning = false } else {
            let root = __s0_buffer_get(SyntaxRec, parse.nodes, __s0_buffer_get(U64, parse.roots, scan) - 1)
            if root.kind == 53 { found = scan + 1
            scanning = false } else { scan = scan + 1 }
        }
    }
    if found == 0 { return Ok(CheckGood(store)) }
    let resolved = try resolve_trait_impl_at(d, state, parse, store, found - 1)
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    let current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return resolve_trait_impls_from(d, state, parse, current, found)
}

fn resolve_trait_impls(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    let resolved = try resolve_trait_impls_from(d, state, parse, store, 0)
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    var current = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    return build_trait_indexes(d, state, parse, current)
}

// Build both impl indexes once and enforce coherence: exactly one
// implementation per concrete (trait, implementing type, arguments)
// combination. Synthesized structural impls participate in the indexes but
// never collide with user impls because user Eq/Hash impls are rejected.
fn build_trait_indexes(d: Domain, state: State, parse: ParseStore, current: CheckStore) -> Result(CheckResult, __s0_Error) {
    let impls = current.traits.impls
    // Merge each record into fresh sorted indexes; comparisons only read
    // canonical IDs, so the merge never carries storage across backedges.
    var index = try __s0_buffer_new(U64, d)
    var at: U64 = 0
    while at < __s0_buffer_len(TraitImplRec, impls) {
        let record_id = at + 1
        let record = __s0_buffer_get(TraitImplRec, impls, at)
        var merged = try __s0_buffer_new(U64, d)
        var placed = false
        var walk: U64 = 0
        while walk < __s0_buffer_len(U64, index) {
            let other_id = __s0_buffer_get(U64, index, walk)
            if !placed {
                let other = __s0_buffer_get(TraitImplRec, impls, other_id - 1)
                if trait_impl_key_less(current, record, other) {
                    merged = try __s0_buffer_append(U64, d, merged, record_id)
                    placed = true
                }
            }
            merged = try __s0_buffer_append(U64, d, merged, other_id)
            walk = walk + 1
        }
        if !placed { merged = try __s0_buffer_append(U64, d, merged, record_id) }
        index = merged
        at = at + 1
    }
    let indexed = trait_store_with(current, impls, index)
    // Receiver-side index: the same records sorted by implementing type
    // symbol, then trait, for method resolution.
    var receiver_index = try __s0_buffer_new(U64, d)
    at = 0
    while at < __s0_buffer_len(TraitImplRec, impls) {
        let record_id = at + 1
        let record = __s0_buffer_get(TraitImplRec, impls, at)
        var merged = try __s0_buffer_new(U64, d)
        var placed = false
        var walk: U64 = 0
        while walk < __s0_buffer_len(U64, receiver_index) {
            let other_id = __s0_buffer_get(U64, receiver_index, walk)
            if !placed {
                let other = __s0_buffer_get(TraitImplRec, impls, other_id - 1)
                if trait_impl_receiver_less(indexed, record, other) {
                    merged = try __s0_buffer_append(U64, d, merged, record_id)
                    placed = true
                }
            }
            merged = try __s0_buffer_append(U64, d, merged, other_id)
            walk = walk + 1
        }
        if !placed { merged = try __s0_buffer_append(U64, d, merged, record_id) }
        receiver_index = merged
        at = at + 1
    }
    var with_receiver = CheckStore(symbols: indexed.symbols, type_params: indexed.type_params, types: indexed.types, type_args: indexed.type_args, type_annotations: indexed.type_annotations, uses: indexed.uses, indexes: indexed.indexes, locals: indexed.locals, environments: indexed.environments, expressions: indexed.expressions, call_annotations: indexed.call_annotations, expression_children: indexed.expression_children, returns: indexed.returns, control: indexed.control, diagnostics: indexed.diagnostics, traits: TraitStoreRec(constraints: indexed.traits.constraints, impls: indexed.traits.impls, impl_index: indexed.traits.impl_index, args: indexed.traits.args, receiver_index: receiver_index), closures: indexed.closures)
    // Coherence: exactly one implementation per concrete trait application.
    var order: U64 = 1
    while order < __s0_buffer_len(U64, index) {
        let left = __s0_buffer_get(TraitImplRec, impls, __s0_buffer_get(U64, index, order - 1) - 1)
        let right = __s0_buffer_get(TraitImplRec, impls, __s0_buffer_get(U64, index, order) - 1)
        if trait_impl_key_equal(with_receiver, left, right) {
            let related = __s0_buffer_get(SyntaxRec, parse.nodes, right.owner_node - 1)
            return check_token_related_fail(d, state, with_receiver, 107, __s0_buffer_get(SyntaxRec, parse.nodes, left.owner_node - 1), related)
        }
        order = order + 1
    }
    return Ok(CheckGood(with_receiver))
}

// Concrete trait-argument lookup for one constraint whose parameterized
// arguments are substituted through instance bindings.
fn trait_constraint_binding_arg(store: CheckStore, constraint: TraitConstraintRec, ordinal: U64, bindings: __s0_Buffer(InferenceBindingRec)) -> U64 {
    let id = __s0_buffer_get(U64, store.traits.args, constraint.first_arg - 1 + ordinal)
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, id - 1)
    if checked.kind == 6 { return inference_lookup(bindings, checked.target) }
    return id
}

// Concrete trait-argument lookup substituting a declaration's parameters
// through a concrete application of that declaration.
fn trait_constraint_application_arg(store: CheckStore, constraint: TraitConstraintRec, ordinal: U64, declaration: U64, application: CheckedTypeRec) -> U64 {
    let id = __s0_buffer_get(U64, store.traits.args, constraint.first_arg - 1 + ordinal)
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, id - 1)
    if checked.kind == 6 {
        let param_ordinal = type_param_ordinal(store, declaration, checked.target)
        if param_ordinal < application.arg_count { return __s0_buffer_get(U64, store.type_args, application.first_arg - 1 + param_ordinal) }
        return 0
    }
    return id
}

fn trait_key_less_binding(store: CheckStore, rec: TraitImplRec, constraint: TraitConstraintRec, bindings: __s0_Buffer(InferenceBindingRec)) -> Bool {
    if rec.trait_builtin != constraint.trait_builtin { return rec.trait_builtin < constraint.trait_builtin }
    if rec.trait_symbol != constraint.trait_symbol { return rec.trait_symbol < constraint.trait_symbol }
    let receiver = inference_lookup(bindings, constraint.param)
    if rec.self_type != receiver { return rec.self_type < receiver }
    var at: U64 = 0
    while at < rec.arg_count && at < constraint.arg_count {
        let left = __s0_buffer_get(U64, store.traits.args, rec.first_arg - 1 + at)
        let right = trait_constraint_binding_arg(store, constraint, at, bindings)
        if left != right { return left < right }
        at = at + 1
    }
    return rec.arg_count < constraint.arg_count
}

fn trait_key_equal_binding(store: CheckStore, rec: TraitImplRec, constraint: TraitConstraintRec, bindings: __s0_Buffer(InferenceBindingRec)) -> Bool {
    if rec.trait_builtin != constraint.trait_builtin || rec.trait_symbol != constraint.trait_symbol || rec.arg_count != constraint.arg_count { return false }
    if rec.self_type != inference_lookup(bindings, constraint.param) { return false }
    var at: U64 = 0
    while at < rec.arg_count {
        if __s0_buffer_get(U64, store.traits.args, rec.first_arg - 1 + at) != trait_constraint_binding_arg(store, constraint, at, bindings) { return false }
        at = at + 1
    }
    return true
}

fn trait_key_less_application(store: CheckStore, rec: TraitImplRec, constraint: TraitConstraintRec, declaration: U64, application: CheckedTypeRec) -> Bool {
    if rec.trait_builtin != constraint.trait_builtin { return rec.trait_builtin < constraint.trait_builtin }
    if rec.trait_symbol != constraint.trait_symbol { return rec.trait_symbol < constraint.trait_symbol }
    let receiver_ordinal = type_param_ordinal(store, declaration, constraint.param)
    var receiver: U64 = 0
    if receiver_ordinal < application.arg_count { receiver = __s0_buffer_get(U64, store.type_args, application.first_arg - 1 + receiver_ordinal) }
    if rec.self_type != receiver { return rec.self_type < receiver }
    var at: U64 = 0
    while at < rec.arg_count && at < constraint.arg_count {
        let left = __s0_buffer_get(U64, store.traits.args, rec.first_arg - 1 + at)
        let right = trait_constraint_application_arg(store, constraint, at, declaration, application)
        if left != right { return left < right }
        at = at + 1
    }
    return rec.arg_count < constraint.arg_count
}

fn trait_key_equal_application(store: CheckStore, rec: TraitImplRec, constraint: TraitConstraintRec, declaration: U64, application: CheckedTypeRec) -> Bool {
    if rec.trait_builtin != constraint.trait_builtin || rec.trait_symbol != constraint.trait_symbol || rec.arg_count != constraint.arg_count { return false }
    let receiver_ordinal = type_param_ordinal(store, declaration, constraint.param)
    if receiver_ordinal >= application.arg_count { return false }
    if rec.self_type != __s0_buffer_get(U64, store.type_args, application.first_arg - 1 + receiver_ordinal) { return false }
    var at: U64 = 0
    while at < rec.arg_count {
        if __s0_buffer_get(U64, store.traits.args, rec.first_arg - 1 + at) != trait_constraint_application_arg(store, constraint, at, declaration, application) { return false }
        at = at + 1
    }
    return true
}

// Binary-search the once-built impl index; zero means no implementation.
fn trait_constraint_satisfied(store: CheckStore, constraint: TraitConstraintRec, bindings: __s0_Buffer(InferenceBindingRec)) -> Bool {
    var low: U64 = 0
    var high = __s0_buffer_len(U64, store.traits.impl_index)
    while low < high {
        let mid = (low + high) / 2
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.impl_index, mid) - 1)
        if trait_key_less_binding(store, rec, constraint, bindings) { low = mid + 1 } else { high = mid }
    }
    if low < __s0_buffer_len(U64, store.traits.impl_index) {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.impl_index, low) - 1)
        if trait_key_equal_binding(store, rec, constraint, bindings) { return true }
    }
    return false
}

fn trait_constraint_application_satisfied(store: CheckStore, constraint: TraitConstraintRec, declaration: U64, application: CheckedTypeRec) -> Bool {
    var low: U64 = 0
    var high = __s0_buffer_len(U64, store.traits.impl_index)
    while low < high {
        let mid = (low + high) / 2
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.impl_index, mid) - 1)
        if trait_key_less_application(store, rec, constraint, declaration, application) { low = mid + 1 } else { high = mid }
    }
    if low < __s0_buffer_len(U64, store.traits.impl_index) {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.impl_index, low) - 1)
        if trait_key_equal_application(store, rec, constraint, declaration, application) { return true }
    }
    return false
}

// Sibling-facing lookup helpers (stable interface): find the impl record
// for a concrete type and builtin trait, and query Cleanup coverage.
fn trait_impl_for_builtin_type(store: CheckStore, builtin: U64, checked_type: U64) -> U64 {
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind != 7 { return 0 }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, store.traits.receiver_index) {
        let rec = __s0_buffer_get(TraitImplRec, store.traits.impls, __s0_buffer_get(U64, store.traits.receiver_index, at) - 1)
        if rec.trait_builtin == builtin && trait_impl_receiver_type_symbol(store, rec) == checked.target { return __s0_buffer_get(U64, store.traits.receiver_index, at) }
        at = at + 1
    }
    return 0
}

fn type_implements_cleanup(store: CheckStore, checked_type: U64) -> Bool {
    if trait_impl_for_builtin_type(store, 5, checked_type) != 0 { return true }
    return trait_impl_for_builtin_type(store, 6, checked_type) != 0
}

// Structural Eq/Hash support: unsigned integers, Bool, String, Bytes, and
// non-generic records or enums whose every component supports them.
fn structural_key_supported(store: CheckStore, checked_type: U64, depth: U64) -> Bool {
    if checked_type == 0 || depth > 16 { return false }
    let checked = __s0_buffer_get(CheckedTypeRec, store.types, checked_type - 1)
    if checked.kind == 1 { return checked.target == 1 || checked.target == 6 || checked.target == 7 || checked.target == 8 || checked.target == 9 }
    if checked.kind == 2 || checked.kind == 14 { return true }
    if checked.kind != 7 { return false }
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, checked.target - 1)
    if symbol.type_arity != 0 { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let use = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            if !structural_key_supported(store, use.checked_type, depth + 1) { return false }
        }
        at = at + 1
    }
    return true
}

// One structural Eq and Hash impl record for a supported concrete type.
fn append_structural_impls_for(d: Domain, store: CheckStore, checked_type: U64) -> Result(CheckStore, __s0_Error) {
    var impls = store.traits.impls
    impls = try __s0_buffer_append(TraitImplRec, d, impls, TraitImplRec(trait_builtin: 1, trait_symbol: 0, first_arg: 0, arg_count: 0, self_type: checked_type, owner_node: 0, first_method: 0, method_count: 0, synthesized: 1))
    impls = try __s0_buffer_append(TraitImplRec, d, impls, TraitImplRec(trait_builtin: 2, trait_symbol: 0, first_arg: 0, arg_count: 0, self_type: checked_type, owner_node: 0, first_method: 0, method_count: 0, synthesized: 1))
    return Ok(trait_store_with(store, impls, store.traits.impl_index))
}

// Synthesize structural Eq/Hash implementations once, after aggregate
// fields are resolved and before any constraint gate or body runs. The
// synthesis itself is a per-symbol loop over a worklist of checked types
// and never runs per expression site.
fn synthesize_structural_impls(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var current = store
    var seeded: U64 = 1
    while seeded <= 12 {
        let checked = __s0_buffer_get(CheckedTypeRec, current.types, seeded - 1)
        if structural_key_supported(current, seeded, 0) {
            let with_impls = try append_structural_impls_for(d, current, seeded)
            current = with_impls
        }
        seeded = seeded + 1
    }
    // String and Bytes are interned singletons; synthesize for them only
    // when the program already mentions them.
    var builtin_kind: U64 = 2
    while builtin_kind <= 14 {
        if builtin_kind == 2 || builtin_kind == 14 {
            let existing = canonical_type_id(current, builtin_kind, 0, 0, 0)
            if existing != 0 {
                let with_impls = try append_structural_impls_for(d, current, existing)
                current = with_impls
            }
        }
        builtin_kind = builtin_kind + 1
    }
    var symbol_at: U64 = 0
    while symbol_at < __s0_buffer_len(SymbolRec, current.symbols) {
        let symbol = __s0_buffer_get(SymbolRec, current.symbols, symbol_at)
        if (symbol.kind == 2 || symbol.kind == 3) && symbol.type_arity == 0 {
            let appended = try append_checked_type(d, current, symbol_at + 1, 7, symbol.node, symbol_at + 1, 0, 0)
            let checked_type = checked_type_for_syntax(appended, symbol_at + 1, symbol.node)
            if checked_type != 0 && structural_key_supported(appended, checked_type, 0) {
                let with_impls = try append_structural_impls_for(d, appended, checked_type)
                current = with_impls
            } else {
                current = appended
            }
        }
        symbol_at = symbol_at + 1
    }
    return build_trait_indexes(d, state, parse, current)
}
