type CheckerUseIndexRec {
    first: U64
    count: U64
}

type CheckerIndexes {
    uses: Vec(CheckerUseIndexRec)
    use_order: Vec(U64)
    complete: Bool
}

type CheckStore {
    symbols: Vec(SymbolRec)
    type_params: Vec(TypeParamRec)
    types: Vec(CheckedTypeRec)
    type_args: Vec(U64)
    type_annotations: Vec(CheckedTypeAnnotationRec)
    uses: Vec(DeclTypeUseRec)
    indexes: CheckerIndexes
    locals: Vec(LocalRec)
    environments: Vec(EnvironmentRec)
    expressions: Vec(CheckedExprRec)
    call_annotations: Vec(CallAnnotationRec)
    expression_children: Vec(CheckedExprChildRec)
    returns: Vec(CheckedReturnRec)
    control: CheckedControlStore
    diagnostics: Vec(CheckDiagRec)
}

fn checked_spans(d: Domain, parse: ParseStore) -> Result(Vec(CheckedSpanRec), __s0_Error) {
    var spans = Vec.new(CheckedSpanRec)
    var at: U64 = 0
    while at < (parse.nodes).len() {
        let node = (parse.nodes)[at]
        try spans.try_push(CheckedSpanRec(source: node.source, start: node.start, end: node.end, name_start: node.name_start, name_end: node.name_end))
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
    children: Vec(U64)
}

enum UnifyOutcome {
    UnifyGood(value: Vec(InferenceBindingRec))
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
    bindings: Vec(InferenceBindingRec)
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
    arms: Vec(MatchArmDraftRec)
}

type MatchArmDraftRec {
    owner: U64
    syntax: U64
    variant_use: U64
    variant_kind: U64
    binding: U64
    environment: U64
    body: U64
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
    events: Vec(BodyEventRec)
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
    positive: [U8]
    negative: [U8]
}

type ArrayLengthRec {
    valid: Bool
    value: U64
}

fn env_lookup(bindings: Vec(TypeBindingRec), env: U64, param: U64) -> TypeBindingRec {
    var at = env
    while at != 0 {
        let item = bindings[at - 1]
        if item.param == param { return item }
        at = item.next
    }
    return TypeBindingRec(param: 0, checked_type: 0, caller_env: 0, caller_ancestry: 0, next: 0)
}

fn normalize_interp(store: CheckStore, bindings: Vec(TypeBindingRec), checked_type: U64, env: U64, ancestry: U64) -> InterpWorkRec {
    var t = checked_type
    var e = env
    var a = ancestry
    var done = false
    while !done {
        let checked = (store.types)[t - 1]
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

fn interpreted_slice_u8(state: State, parse: ParseStore, store: CheckStore, bindings: Vec(TypeBindingRec), checked: CheckedTypeRec, env: U64) -> Bool {
    if checked.kind != 8 || checked.arg_count != 1 { return false }
    let child = normalize_interp(store, bindings, (store.type_args)[checked.first_arg - 1], env, 0)
    let item = (store.types)[child.checked_type - 1]
    return item.kind == 1 && item.target == 6
}

// Finite structural equality is iterative. Declared applications compare their
// target and direct arguments and never expand declaration bodies.
fn interpreted_type_equal(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: Vec(TypeBindingRec), left_type: U64, left_env: U64, right_type: U64, right_env: U64) -> Result(Bool, __s0_Error) {
    let initial = Vec.new(PairWorkRec)
    var work = try vec_appended(PairWorkRec, initial, PairWorkRec(left_type: left_type, left_env: left_env, right_type: right_type, right_env: right_env))
    let first_seen = Vec.new(PairWorkRec)
    var seen = first_seen
    var at: U64 = 0
    while at < (work).len() {
        let pair = work[at]
        let left = normalize_interp(store, bindings, pair.left_type, pair.left_env, 0)
        let right = normalize_interp(store, bindings, pair.right_type, pair.right_env, 0)
        if left.checked_type != right.checked_type || left.env != right.env {
            var known = false
            var seen_at: U64 = 0
            while seen_at < (seen).len() {
                let prior = seen[seen_at]
                if prior.left_type == left.checked_type && prior.left_env == left.env && prior.right_type == right.checked_type && prior.right_env == right.env { known = true }
                seen_at = seen_at + 1
            }
            if !known {
                try seen.try_push(PairWorkRec(left_type: left.checked_type, left_env: left.env, right_type: right.checked_type, right_env: right.env))
                let a = (store.types)[left.checked_type - 1]
                let b = (store.types)[right.checked_type - 1]
                if a.kind != b.kind {
                    if !((a.kind == 16 && interpreted_slice_u8(state, parse, store, bindings, b, right.env)) || (b.kind == 16 && interpreted_slice_u8(state, parse, store, bindings, a, left.env))) { return Ok(false) }
                }
                else {
                    if a.target != b.target || a.arg_count != b.arg_count { return Ok(false) }
                    if a.kind == 1 && !primitive_same(state, parse, a, b) { return Ok(false) }
                    if a.kind == 6 && a.target != b.target { return Ok(false) }
                    var child: U64 = 0
                    while child < a.arg_count {
                        try work.try_push(PairWorkRec(left_type: (store.type_args)[a.first_arg - 1 + child], left_env: left.env, right_type: (store.type_args)[b.first_arg - 1 + child], right_env: right.env))
                        child = child + 1
                    }
                }
            }
        }
        at = at + 1
    }
    return Ok(true)
}

fn expansion_seen(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: Vec(TypeBindingRec), memo: Vec(ExpansionMemoRec), owner: U64, checked_type: U64, env: U64) -> Result(Bool, __s0_Error) {
    let checked = (store.types)[checked_type - 1]
    var at: U64 = 0
    while at < (memo).len() {
        let prior = memo[at]
        if prior.owner == owner && prior.target == checked.target {
            if try interpreted_type_equal(d, state, parse, store, bindings, checked_type, env, prior.checked_type, prior.env) { return Ok(true) }
        }
        at = at + 1
    }
    return Ok(false)
}

fn remember_expansion(d: Domain, memo: Vec(ExpansionMemoRec), owner: U64, target: U64, checked_type: U64, env: U64) -> Result(Vec(ExpansionMemoRec), __s0_Error) {
    return Ok(try vec_appended(ExpansionMemoRec, memo, ExpansionMemoRec(owner: owner, target: target, checked_type: checked_type, env: env)))
}

fn expansion_target_seen(memo: Vec(ExpansionMemoRec), target: U64) -> Bool {
    var at: U64 = 0
    while at < (memo).len() {
        if memo[at].target == target { return true }
        at = at + 1
    }
    return false
}

fn interp_state_seen(seen: Vec(InterpStateRec), owner: U64, checked_type: U64, env: U64, ancestry: U64) -> Bool {
    var at: U64 = 0
    while at < (seen).len() {
        let item = seen[at]
        if item.owner == owner && item.checked_type == checked_type && item.env == env && item.ancestry == ancestry { return true }
        at = at + 1
    }
    return false
}

fn direct_type_concrete(d: Domain, store: CheckStore, bindings: Vec(TypeBindingRec), checked_type: U64, env: U64) -> Result(Bool, __s0_Error) {
    let initial = Vec.new(InterpWorkRec)
    var work = try vec_appended(InterpWorkRec, initial, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    var at: U64 = 0
    while at < (work).len() {
        let item = work[at]
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = (store.types)[norm.checked_type - 1]
        if checked.kind == 6 { return Ok(false) }
        var child: U64 = 0
        while child < checked.arg_count {
            try work.try_push(InterpWorkRec(checked_type: (store.type_args)[checked.first_arg - 1 + child], env: norm.env, ancestry: 0))
            child = child + 1
        }
        at = at + 1
    }
    return Ok(true)
}

fn ancestry_has(ancestry: Vec(DeclAncestryRec), id: U64, target: U64) -> Bool {
    var at = id
    while at != 0 {
        let item = ancestry[at - 1]
        if item.target == target { return true }
        at = item.parent
    }
    return false
}

fn build_target_env(d: Domain, store: CheckStore, bindings: Vec(TypeBindingRec), target: U64, checked: CheckedTypeRec, caller_env: U64, caller_ancestry: U64) -> Result(Vec(TypeBindingRec), __s0_Error) {
    var result = bindings
    var head: U64 = 0
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < (store.type_params).len() {
        let param = (store.type_params)[at]
        if param.owner == target {
            try result.try_push(TypeBindingRec(param: at + 1, checked_type: (store.type_args)[checked.first_arg - 1 + ordinal], caller_env: caller_env, caller_ancestry: caller_ancestry, next: head))
            head = (result).len()
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return Ok(result)
}

fn declaration_env_head(bindings: Vec(TypeBindingRec), old_len: U64) -> U64 {
    if (bindings).len() == old_len { return 0 }
    return (bindings).len()
}

fn push_decl_members(d: Domain, store: CheckStore, work: Vec(InterpWorkRec), target: U64, env: U64, ancestry: U64) -> Result(Vec(InterpWorkRec), __s0_Error) {
    var result = work
    let symbol = (store.symbols)[target - 1]
    var role: U64 = 0
    if symbol.kind == 2 { role = 1 }
    if symbol.kind == 3 { role = 2 }
    if role != 0 && checker_use_index_available(store, target, role) {
        let index = (store.indexes.uses)[checker_use_slot(target, role)]
        var ordinal: U64 = 0
        while ordinal < index.count {
            let use_id = (store.indexes.use_order)[index.first - 1 + ordinal]
            let use = (store.uses)[use_id - 1]
            if use.checked_type != 0 {
                try result.try_push(InterpWorkRec(checked_type: use.checked_type, env: env, ancestry: ancestry))
            }
            ordinal = ordinal + 1
        }
        return Ok(result)
    }
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.owner == target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            try result.try_push(InterpWorkRec(checked_type: use.checked_type, env: env, ancestry: ancestry))
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
    let symbol = (store.symbols)[owner - 1]
    if symbol.kind == 2 || symbol.kind == 3 { return owner }
    return 0
}

// Reusing a specialization is context independent unless it can reach one of
// the current active declarations. Inspecting every supplied argument and each
// declaration body once by target is conservative without unfolding a finite
// declaration DAG once per path.
fn interpreted_may_reach_ancestry(d: Domain, store: CheckStore, initial_bindings: Vec(TypeBindingRec), checked_type: U64, env: U64, active: U64, ancestry: Vec(DeclAncestryRec)) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = Vec.new(InterpWorkRec)
    var work = try vec_appended(InterpWorkRec, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    let first_seen = Vec.new(InterpStateRec)
    var seen = first_seen
    let first_targets = Vec.new(ExpansionMemoRec)
    var targets = first_targets
    var at: U64 = 0
    while at < (work).len() {
        let item = work[at]
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, 0)
        if !interp_state_seen(seen, 0, norm.checked_type, norm.env, 0) {
            try seen.try_push(InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: 0))
            let checked = (store.types)[norm.checked_type - 1]
            if checked.kind == 6 { return Ok(true) }
            if checked.kind == 7 && ancestry_has(ancestry, active, checked.target) { return Ok(true) }
            var child: U64 = 0
            while child < checked.arg_count {
                try work.try_push(InterpWorkRec(checked_type: (store.type_args)[checked.first_arg - 1 + child], env: norm.env, ancestry: 0))
                child = child + 1
            }
            if checked.kind == 7 && !expansion_target_seen(targets, checked.target) {
                targets = try remember_expansion(d, targets, 0, checked.target, norm.checked_type, norm.env)
                let old_len = (bindings).len()
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
fn interpreted_contains_reference(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: Vec(TypeBindingRec), initial_ancestry: Vec(DeclAncestryRec), checked_type: U64, env: U64, ancestry_id: U64, boundary: U64) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = Vec.new(InterpWorkRec)
    var work = try vec_appended(InterpWorkRec, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: ancestry_id))
    var ancestry = initial_ancestry
    let first_memo = Vec.new(ExpansionMemoRec)
    var memo = first_memo
    let first_seen = Vec.new(InterpStateRec)
    var seen = first_seen
    var at: U64 = 0
    while at < (work).len() {
        let item = work[at]
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = (store.types)[norm.checked_type - 1]
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { try seen.try_push(InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 3 || checked.kind == 4 || checked.kind == 8 || checked.kind == 11 || checked.kind == 12 || checked.kind == 13 || checked.kind == 16 || checked.kind == 18 { return Ok(true) }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 15 || checked.kind == 17 {
                var child: U64 = 0
                while child < checked.arg_count {
                    try work.try_push(InterpWorkRec(checked_type: (store.type_args)[checked.first_arg - 1 + child], env: norm.env, ancestry: norm.ancestry))
                    child = child + 1
                }
            }
            if checked.kind == 7 && declaration_available(boundary, checked.target) && !ancestry_has(ancestry, norm.ancestry, checked.target) {
                if !(try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)) {
                    memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                    let old_len = (bindings).len()
                    bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                    let target_env = declaration_env_head(bindings, old_len)
                    try ancestry.try_push(DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                    work = try push_decl_members(d, store, work, checked.target, target_env, (ancestry).len())
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
fn interpreted_type_category(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: Vec(TypeBindingRec), initial_ancestry: Vec(DeclAncestryRec), checked_type: U64, env: U64, ancestry_id: U64) -> Result(TypeCategoryRec, __s0_Error) {
    var bindings = initial_bindings
    let first_work = Vec.new(InterpWorkRec)
    var work = try vec_appended(InterpWorkRec, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: ancestry_id))
    var ancestry = initial_ancestry
    let first_memo = Vec.new(ExpansionMemoRec)
    var memo = first_memo
    let first_seen = Vec.new(InterpStateRec)
    var seen = first_seen
    var affine = false
    var scoped = false
    var nonimmutable_scoped = false
    var unresolved = false
    var at: U64 = 0
    while at < (work).len() {
        let item = work[at]
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = (store.types)[norm.checked_type - 1]
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { try seen.try_push(InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 3 { affine = true }
            if checked.kind == 4 || checked.kind == 8 || checked.kind == 12 || checked.kind == 18 { scoped = true }
            if checked.kind == 4 || checked.kind == 12 || checked.kind == 18 { nonimmutable_scoped = true }
            if checked.kind == 6 { unresolved = true }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 || checked.kind == 13 || checked.kind == 15 || checked.kind == 17 {
                var child: U64 = 0
                while child < checked.arg_count {
                    try work.try_push(InterpWorkRec(checked_type: (store.type_args)[checked.first_arg - 1 + child], env: norm.env, ancestry: norm.ancestry))
                    child = child + 1
                }
            }
            if checked.kind == 7 {
                if !(try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)) {
                    memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                    let old_len = (bindings).len()
                    bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                    let target_env = declaration_env_head(bindings, old_len)
                    try ancestry.try_push(DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                    work = try push_decl_members(d, store, work, checked.target, target_env, (ancestry).len())
                }
            }
        }
        at = at + 1
    }
    var category: U64 = 1
    if scoped { category = 3 }
    if affine { category = 2 }
    if unresolved { category = 0 }
    return Ok(TypeCategoryRec(category: category, contains_scoped: scoped, contains_nonimmutable_scoped: nonimmutable_scoped))
}

fn primitive_map_key(state: State, parse: ParseStore, checked: CheckedTypeRec) -> Bool {
    return checked.kind == 1 && (checked.target == 1 || (checked.target >= 6 && checked.target <= 9))
}

fn interpreted_map_key_ok(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: Vec(TypeBindingRec), initial_ancestry: Vec(DeclAncestryRec), checked_type: U64, env: U64, ancestry_id: U64, boundary: U64) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = Vec.new(InterpWorkRec)
    var work = try vec_appended(InterpWorkRec, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: ancestry_id))
    var ancestry = initial_ancestry
    let first_memo = Vec.new(ExpansionMemoRec)
    var memo = first_memo
    let first_seen = Vec.new(InterpStateRec)
    var seen = first_seen
    var at: U64 = 0
    while at < (work).len() {
        let item = work[at]
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = (store.types)[norm.checked_type - 1]
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { try seen.try_push(InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 1 {
                if !primitive_map_key(state, parse, checked) { return Ok(false) }
            } else {
                if checked.kind == 7 && declaration_available(boundary, checked.target) {
                    if !ancestry_has(ancestry, norm.ancestry, checked.target) {
                        if !(try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)) {
                            memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                            let old_len = (bindings).len()
                            bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                            let target_env = declaration_env_head(bindings, old_len)
                            try ancestry.try_push(DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                            work = try push_decl_members(d, store, work, checked.target, target_env, (ancestry).len())
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

fn specialization_equal(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: Vec(TypeBindingRec), checked: CheckedTypeRec, caller_env: U64, active_env: U64) -> Result(Bool, __s0_Error) {
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < (store.type_params).len() {
        let param = (store.type_params)[at]
        if param.owner == checked.target {
            let active = env_lookup(bindings, active_env, at + 1)
            if active.param == 0 || !(try interpreted_type_equal(d, state, parse, store, bindings, (store.type_args)[checked.first_arg - 1 + ordinal], caller_env, active.checked_type, active.caller_env)) { return Ok(false) }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return Ok(true)
}

fn active_target(ancestry: Vec(DeclAncestryRec), id: U64, target: U64) -> U64 {
    var at = id
    while at != 0 {
        let item = ancestry[at - 1]
        if item.target == target { return at }
        at = item.parent
    }
    return 0
}

fn syntax_diag_node(state: State, parse: ParseStore, syntax: U64) -> SyntaxRec {
    let node = (parse.nodes)[syntax - 1]
    if node.name_end != 0 || node.name_start != 0 { return node }
    let token = (state.tokens)[node.token - 1]
    return SyntaxRec(kind: node.kind, token: node.token, source: token.source, start: token.start, end: token.end, name_start: token.start, name_end: token.end, children: node.children)
}

// Complete concrete validation uses a persistent LIFO stack. Continuations and
// active declaration chains are immutable IDs, preserving recursive DFS error
// order without using the host call stack.
fn validate_concrete_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, root_type: U64, root_env: U64, root_node: SyntaxRec, boundary: U64) -> Result(CheckResult, __s0_Error) {
    let empty_bindings = Vec.new(TypeBindingRec)
    var bindings = empty_bindings
    let empty_ancestry = Vec.new(DeclAncestryRec)
    var ancestry = empty_ancestry
    let empty_memo = Vec.new(ExpansionMemoRec)
    var memo = empty_memo
    let empty_seen = Vec.new(InterpStateRec)
    var seen = empty_seen
    let empty_work = Vec.new(ValidationWorkRec)
    var work = try vec_appended(ValidationWorkRec, empty_work, ValidationWorkRec(checked_type: root_type, env: root_env, ancestry: 0, next: 0))
    var head: U64 = 1
    while head != 0 {
        let item = work[head - 1]
        head = item.next
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = (store.types)[norm.checked_type - 1]
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, 0, norm.checked_type, norm.env, norm.ancestry)
            if inspect { try seen.try_push(InterpStateRec(owner: 0, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 8 {
                let child = (store.type_args)[checked.first_arg - 1]
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, child, norm.env, norm.ancestry, boundary) { return check_type_detail_fail(d, store, 10, root_node, child) }
                try work.try_push(ValidationWorkRec(checked_type: child, env: norm.env, ancestry: norm.ancestry, next: head))
                head = (work).len()
            }
            if checked.kind == 9 || checked.kind == 12 || checked.kind == 15 {
                try work.try_push(ValidationWorkRec(checked_type: (store.type_args)[checked.first_arg - 1], env: norm.env, ancestry: norm.ancestry, next: head))
                head = (work).len()
            }
            if checked.kind == 13 {
                let child = (store.type_args)[checked.first_arg - 1]
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, child, norm.env, norm.ancestry, boundary) { return check_fail(d, store, 11, root_node, 0, 0, 0) }
                try work.try_push(ValidationWorkRec(checked_type: child, env: norm.env, ancestry: norm.ancestry, next: head))
                head = (work).len()
            }
            if checked.kind == 10 {
                try work.try_push(ValidationWorkRec(checked_type: (store.type_args)[checked.first_arg], env: norm.env, ancestry: norm.ancestry, next: head))
                let err_head = (work).len()
                try work.try_push(ValidationWorkRec(checked_type: (store.type_args)[checked.first_arg - 1], env: norm.env, ancestry: norm.ancestry, next: err_head))
                head = (work).len()
            }
            if checked.kind == 11 {
                let key = (store.type_args)[checked.first_arg - 1]
                let value = (store.type_args)[checked.first_arg]
                if !(try interpreted_map_key_ok(d, state, parse, store, bindings, ancestry, key, norm.env, norm.ancestry, boundary)) { return check_type_detail_fail(d, store, 12, root_node, key) }
                if try interpreted_contains_reference(d, state, parse, store, bindings, ancestry, value, norm.env, norm.ancestry, boundary) { return check_type_detail_fail(d, store, 13, root_node, value) }
                try work.try_push(ValidationWorkRec(checked_type: value, env: norm.env, ancestry: norm.ancestry, next: head))
                let value_head = (work).len()
                try work.try_push(ValidationWorkRec(checked_type: key, env: norm.env, ancestry: norm.ancestry, next: value_head))
                head = (work).len()
            }
            if checked.kind == 7 && declaration_available(boundary, checked.target) {
                let active = active_target(ancestry, norm.ancestry, checked.target)
                if active != 0 {
                    let prior = ancestry[active - 1]
                    if !(try specialization_equal(d, state, parse, store, bindings, checked, norm.env, prior.env)) { return check_fail(d, store, 14, root_node, 0, 0, 0) }
                } else {
                    var reuse = try expansion_seen(d, state, parse, store, bindings, memo, 0, norm.checked_type, norm.env)
                    if reuse {
                        if try interpreted_may_reach_ancestry(d, store, bindings, norm.checked_type, norm.env, norm.ancestry, ancestry) { reuse = false }
                    }
                    if !reuse {
                        memo = try remember_expansion(d, memo, 0, checked.target, norm.checked_type, norm.env)
                        let old_len = (bindings).len()
                        bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                        let target_env = declaration_env_head(bindings, old_len)
                        try ancestry.try_push(DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                        let chain = (ancestry).len()
                        var use_at = (store.uses).len()
                        while use_at != 0 {
                            use_at = use_at - 1
                            let use = (store.uses)[use_at]
                            if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
                                try work.try_push(ValidationWorkRec(checked_type: use.checked_type, env: target_env, ancestry: chain, next: head))
                                head = (work).len()
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
    let a = (state.sources)[a_source]
    let b = (state.sources)[b_source]
    var at: U64 = 0
    while at < a_end - a_start {
        if text_byte(state, a, a_start + at) != text_byte(state, b, b_start + at) { return false }
        at = at + 1
    }
    return true
}

fn node_word(state: State, node: SyntaxRec, word: [U8]) -> Bool {
    let source = (state.sources)[node.source]
    return source_word(state, source, node.name_start, node.name_end, word)
}

fn reserved_symbol(state: State, node: SyntaxRec) -> Bool {
    let source = (state.sources)[node.source]
    if node.name_end - node.name_start >= 5 && source_word(state, source, node.name_start, node.name_start + 5, "__s0_") { return true }
    return node_word(state, node, "Bool") || node_word(state, node, "I8") || node_word(state, node, "I16") || node_word(state, node, "I32") || node_word(state, node, "I64") || node_word(state, node, "U8") || node_word(state, node, "U16") || node_word(state, node, "U32") || node_word(state, node, "U64") || node_word(state, node, "F32") || node_word(state, node, "F64") || node_word(state, node, "Unit") || node_word(state, node, "String") || node_word(state, node, "Bytes") || node_word(state, node, "Option") || node_word(state, node, "Result") || node_word(state, node, "Map") || node_word(state, node, "Ptr") || node_word(state, node, "Vec") || node_word(state, node, "MutSlice") || node_word(state, node, "CapacityError") || node_word(state, node, "Domain") || node_word(state, node, "DomainMark") || node_word(state, node, "[U8]") || node_word(state, node, "__s0_Buffer") || node_word(state, node, "__s0_Error") || node_word(state, node, "len") || node_word(state, node, "range") || node_word(state, node, "__s0_alloc") || node_word(state, node, "__s0_domain_create") || node_word(state, node, "__s0_domain_mark") || node_word(state, node, "__s0_domain_reset") || node_word(state, node, "__s0_domain_destroy") || node_word(state, node, "__s0_map_create") || node_word(state, node, "__s0_buffer_new") || node_word(state, node, "__s0_buffer_len") || node_word(state, node, "__s0_buffer_append") || node_word(state, node, "__s0_buffer_get") || node_word(state, node, "__s0_buffer_set") || node_word(state, node, "__s0_buffer_slice") || node_word(state, node, "Get") || node_word(state, node, "Set") || node_word(state, node, "Remove") || node_word(state, node, "None") || node_word(state, node, "Some") || node_word(state, node, "Ok") || node_word(state, node, "Err")
}

fn reserved_value_name(state: State, store: CheckStore, node: SyntaxRec) -> Bool {
    if reserved_symbol(state, node) { return true }
    var at: U64 = 0
    while at < (store.symbols).len() {
        let symbol = (store.symbols)[at]
        if (symbol.kind == 2 || symbol.kind == 3) && same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return true }
        at = at + 1
    }
    return false
}

fn check_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, related_source: U64, related_start: U64, related_end: U64) -> Result(CheckResult, __s0_Error) {
    let item = CheckDiagRec(kind: kind, source: node.source, start: node.name_start, end: node.name_end, related_source: related_source, related_start: related_start, related_end: related_end, detail_a: 0, detail_b: 0, detail_c: 0, detail_d: 0)
    let diagnostics = try vec_appended(CheckDiagRec, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics)))
}

fn check_detail_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> Result(CheckResult, __s0_Error) {
    let item = CheckDiagRec(kind: kind, source: node.source, start: node.name_start, end: node.name_end, related_source: 0, related_start: 0, related_end: 0, detail_a: detail_a, detail_b: detail_b, detail_c: detail_c, detail_d: detail_d)
    let diagnostics = try vec_appended(CheckDiagRec, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics)))
}

fn check_decl_fail(d: Domain, state: State, parse: ParseStore, store: CheckStore, kind: U64, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = (store.symbols)[owner - 1]
    let node = (parse.nodes)[symbol.node - 1]
    let token = (state.tokens)[node.token - 1]
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0, detail_a: 0, detail_b: 0, detail_c: 0, detail_d: 0)
    let diagnostics = try vec_appended(CheckDiagRec, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics)))
}

fn check_token_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let token = (state.tokens)[node.token - 1]
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0, detail_a: 0, detail_b: 0, detail_c: 0, detail_d: 0)
    let diagnostics = try vec_appended(CheckDiagRec, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics)))
}

fn check_token_detail_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, detail_a: U64, detail_b: U64, detail_c: U64, detail_d: U64) -> Result(CheckResult, __s0_Error) {
    let token = (state.tokens)[node.token - 1]
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0, detail_a: detail_a, detail_b: detail_b, detail_c: detail_c, detail_d: detail_d)
    let diagnostics = try vec_appended(CheckDiagRec, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics)))
}

fn check_type_detail_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, checked_type: U64) -> Result(CheckResult, __s0_Error) {
    let detail = diagnostic_type(store, checked_type)
    return check_detail_fail(d, store, kind, node, detail.kind, detail.target, 0, 0)
}

fn check_token_related_fail(d: Domain, state: State, store: CheckStore, kind: U64, node: SyntaxRec, related: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let token = (state.tokens)[node.token - 1]
    let related_token = (state.tokens)[related.token - 1]
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: related_token.source, related_start: related_token.start, related_end: related_token.end, detail_a: node.kind, detail_b: related.kind, detail_c: 0, detail_d: 0)
    let diagnostics = try vec_appended(CheckDiagRec, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: diagnostics)))
}

fn symbol_arity(parse: ParseStore, node: SyntaxRec) -> U64 {
    if node.kind == 1 { return 0 }
    var count: U64 = 0
    var link = node.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        if (parse.nodes)[item.node - 1].kind == 7 { count = count + 1 }
        link = item.next
    }
    return count
}

// Inherent functions remain ordinary static symbols after discovery. Their
// owning type is recovered from the parser root so the bootstrap model needs
// no parallel method table or runtime dispatch metadata.
fn inherent_owner_node(parse: ParseStore, function_node: U64) -> U64 {
    var root_at: U64 = 0
    while root_at < (parse.roots).len() {
        let root = (parse.nodes)[(parse.roots)[root_at] - 1]
        if root.kind == 49 {
            var link = root.children
            var owner: U64 = 0
            while link != 0 {
                let item = (parse.links)[link - 1]
                if item.next == 0 { owner = item.node }
                link = item.next
            }
            if owner != 0 {
                link = root.children
                while link != 0 {
                    let item = (parse.links)[link - 1]
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
    let a = (parse.nodes)[left - 1]
    let b = (parse.nodes)[right - 1]
    return same_name(state, a.source, a.start, a.end, b.source, b.start, b.end)
}

fn validate_inherent_owners(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var root_at: U64 = 0
    while root_at < (parse.roots).len() {
        let root = (parse.nodes)[(parse.roots)[root_at] - 1]
        if root.kind == 49 {
            var link = root.children
            while (parse.links)[link - 1].next != 0 {
                link = (parse.links)[link - 1].next
            }
            let owner = (parse.nodes)[(parse.links)[link - 1].node - 1]
            if find_declared_type(state, parse, store, owner) == 0 { return check_token_fail(d, state, store, 4, owner) }
        }
        root_at = root_at + 1
    }
    return Ok(CheckGood(store))
}

fn collect_symbols(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    let imports = try validate_import_bindings(d, state, parse, initial)
    if match imports {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(imports) }
    var store = initial
    var root_at: U64 = 0
    while root_at < (parse.roots).len() {
        var node_id = (parse.roots)[root_at]
        var node = (parse.nodes)[node_id - 1]
        if node.kind == 40 || node.kind == 41 || node.kind == 42 || node.kind == 49 {
            root_at = root_at + 1
        } else {
        if node.kind == 45 {
            let declaration = (parse.links)[node.children - 1]
            node_id = declaration.node
            node = (parse.nodes)[node_id - 1]
        }
        var module_source: U64 = 0
        var public = false
        var scan: U64 = 0
        while scan < (parse.roots).len() {
            let root_id = (parse.roots)[scan]
            let root = (parse.nodes)[root_id - 1]
            if root.source == node.source && root.kind == 40 { module_source = node.source + 1 }
            if root.source == node.source && root.kind == 45 {
                let wrapped = (parse.links)[root.children - 1]
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
        while previous < (store.symbols).len() {
            let first = (store.symbols)[previous]
            let first_owner = inherent_owner_node(parse, first.node)
            if same_name(state, node.source, node.name_start, node.name_end, first.source, first.name_start, first.name_end) && same_inherent_owner(state, parse, inherent_owner, first_owner) && (module_source == 0 || first.module_source == module_source) {
                let related = (parse.nodes)[first.node - 1]
                return check_token_related_fail(d, state, store, 1, node, related)
            }
            previous = previous + 1
        }
        if reserved_symbol(state, node) { return check_fail(d, store, 2, node, 0, 0, 0) }
        let symbol_id = (store.symbols).len() + 1
        var declaration: U64 = 0
        if node.kind == 12 && symbol_arity(parse, node) == 0 { declaration = symbol_id }
        let symbol = SymbolRec(kind: node.kind, node: node_id, source: node.source, name_start: node.name_start, name_end: node.name_end, type_arity: symbol_arity(parse, node), declaration: declaration, first_instance_arg: 0, instance_arg_count: 0, discovery_parent: 0, inherent_owner: inherent_owner, module_source: module_source, public: public)
        let symbols = try vec_appended(SymbolRec, store.symbols, symbol)
        store = CheckStore(symbols: symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
        root_at = root_at + 1
        }
    }
    let inherent = try validate_inherent_owners(d, state, parse, store)
    if match inherent {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(inherent) }
    return validate_import_targets(d, state, parse, store)
}

fn append_type_param(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = (parse.nodes)[node_id - 1]
    var at: U64 = 0
    while at < (store.type_params).len() {
        let first = (store.type_params)[at]
        if first.owner == owner && same_name(state, node.source, node.name_start, node.name_end, first.source, first.name_start, first.name_end) {
            return check_fail(d, store, 3, node, first.source, first.name_start, first.name_end)
        }
        at = at + 1
    }
    let params = try vec_appended(TypeParamRec, store.type_params, TypeParamRec(owner: owner, node: node_id, source: node.source, name_start: node.name_start, name_end: node.name_end))
    return Ok(CheckGood(CheckStore(symbols: store.symbols, type_params: params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)))
}

fn collect_param_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(CheckResult, __s0_Error) {
    if link_id == 0 { return Ok(CheckGood(store)) }
    let link = (parse.links)[link_id - 1]
    let earlier = try collect_param_links(d, state, parse, store, owner, link.next)
    let current = match earlier {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match earlier {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(earlier) }
    if (parse.nodes)[link.node - 1].kind != 7 { return Ok(CheckGood(current)) }
    return append_type_param(d, state, parse, current, owner, link.node)
}

fn find_type_param(state: State, store: CheckStore, owner: U64, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < (store.type_params).len() {
        let p = (store.type_params)[at]
        if p.owner == owner && same_name(state, node.source, node.name_start, node.name_end, p.source, p.name_start, p.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn find_declared_type(state: State, parse: ParseStore, store: CheckStore, node: SyntaxRec) -> U64 {
    let resolved = symbol_named(state, parse, store, node)
    if resolved != 0 {
        let found = (store.symbols)[resolved - 1]
        if found.kind == 2 || found.kind == 3 { return resolved }
    }
    return 0
}

fn module_source_named(state: State, parse: ParseStore, source: U64, start: U64, end: U64) -> U64 {
    var at: U64 = 0
    while at < (parse.roots).len() {
        let root = (parse.nodes)[(parse.roots)[at] - 1]
        if root.kind == 40 && same_name(state, source, start, end, root.source, root.name_start, root.name_end) { return root.source + 1 }
        at = at + 1
    }
    return 0
}

fn exported_symbol_named(state: State, parse: ParseStore, store: CheckStore, module_source: U64, source: U64, start: U64, end: U64) -> U64 {
    var at: U64 = 0
    while at < (store.symbols).len() {
        let symbol = (store.symbols)[at]
        if symbol.module_source == module_source && symbol.public && same_name(state, source, start, end, symbol.source, symbol.name_start, symbol.name_end) { return at + 1 }
        at = at + 1
    }
    at = 0
    while at < (parse.roots).len() {
        let root = (parse.nodes)[(parse.roots)[at] - 1]
        if root.kind == 42 && root.source + 1 == module_source {
            var link = root.children
            while link != 0 {
                let item = (parse.links)[link - 1]
                let child = (parse.nodes)[item.node - 1]
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
    while at < (parse.roots).len() {
        let root = (parse.nodes)[(parse.roots)[at] - 1]
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
    if node_word(state, node, "[U8]") { return 16 }
    if node_word(state, node, "Domain") { return 3 }
    if node_word(state, node, "DomainMark") { return 4 }
    if node_word(state, node, "__s0_Error") { return 5 }
    if node_word(state, node, "CapacityError") { return 19 }
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
    while at < (store.types).len() {
        let checked = (store.types)[at]
        if checked.kind == kind && checked.target == target && checked.arg_count == arg_count {
            var same = true
            var arg: U64 = 0
            while arg < arg_count {
                if (store.type_args)[checked.first_arg - 1 + arg] != (store.type_args)[first_arg - 1 + arg] { same = false }
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
    while at < (store.types).len() {
        let checked = (store.types)[at]
        if checked.kind == kind && checked.target == target && checked.arg_count == 1 && (store.type_args)[checked.first_arg - 1] == arg { return at + 1 }
        at = at + 1
    }
    return 0
}

fn canonical_type_for_children(store: CheckStore, kind: U64, target: U64, children: Vec(U64)) -> U64 {
    var at: U64 = 0
    while at < (store.types).len() {
        let checked = (store.types)[at]
        if checked.kind == kind && checked.target == target && checked.arg_count == (children).len() {
            var same = true
            var ordinal: U64 = 0
            while ordinal < checked.arg_count {
                if (store.type_args)[checked.first_arg - 1 + ordinal] != children[ordinal] { same = false }
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
    let annotations = try vec_appended(CheckedTypeAnnotationRec, store.type_annotations, CheckedTypeAnnotationRec(owner: owner, syntax: syntax, checked_type: checked_type))
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics))
}

fn append_checked_type(d: Domain, store: CheckStore, owner: U64, kind: U64, syntax: U64, target: U64, first_arg: U64, arg_count: U64) -> Result(CheckStore, __s0_Error) {
    let existing = canonical_type_id(store, kind, target, first_arg, arg_count)
    if existing != 0 { return annotate_checked_type(d, store, owner, syntax, existing) }
    let types = try vec_appended(CheckedTypeRec, store.types, CheckedTypeRec(kind: kind, syntax: 0, target: target, first_arg: first_arg, arg_count: arg_count))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return annotate_checked_type(d, next, owner, syntax, (types).len())
}

fn instance_declaration(store: CheckStore, owner: U64) -> U64 {
    let symbol = (store.symbols)[owner - 1]
    if symbol.kind == 13 { return symbol.declaration }
    return owner
}

fn type_param_ordinal(store: CheckStore, declaration: U64, param: U64) -> U64 {
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < (store.type_params).len() {
        let item = (store.type_params)[at]
        if item.owner == declaration {
            if at + 1 == param { return ordinal }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return ordinal
}

fn instance_type_arg(store: CheckStore, instance: U64, param: U64) -> U64 {
    let symbol = (store.symbols)[instance - 1]
    if symbol.kind != 13 { return 0 }
    let ordinal = type_param_ordinal(store, symbol.declaration, param)
    if ordinal >= symbol.instance_arg_count { return 0 }
    return (store.type_args)[symbol.first_instance_arg - 1 + ordinal]
}

fn inference_lookup(bindings: Vec(InferenceBindingRec), param: U64) -> U64 {
    var at: U64 = 0
    while at < (bindings).len() {
        let binding = bindings[at]
        if binding.param == param { return binding.checked_type }
        at = at + 1
    }
    return 0
}

fn checked_type_concrete(store: CheckStore, checked_type: U64) -> Bool {
    let checked = (store.types)[checked_type - 1]
    if checked.kind == 6 { return false }
    var ordinal: U64 = 0
    while ordinal < checked.arg_count {
        if !checked_type_concrete(store, (store.type_args)[checked.first_arg - 1 + ordinal]) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn substitute_children(d: Domain, store: CheckStore, bindings: Vec(InferenceBindingRec), original: CheckStore, checked: CheckedTypeRec, ordinal: U64, children: Vec(U64)) -> Result(SubstitutedChildrenRec, __s0_Error) {
    if ordinal == checked.arg_count { return Ok(SubstitutedChildrenRec(store: store, children: children)) }
    let child = try substitute_type(d, store, bindings, (original.type_args)[checked.first_arg - 1 + ordinal])
    let next = try vec_appended(U64, children, child.checked_type)
    return substitute_children(d, child.store, bindings, original, checked, ordinal + 1, next)
}

fn append_substituted_children(d: Domain, store: CheckStore, children: Vec(U64), ordinal: U64) -> Result(CheckStore, __s0_Error) {
    if ordinal == (children).len() { return Ok(store) }
    let args = try vec_appended(U64, store.type_args, children[ordinal])
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return append_substituted_children(d, next, children, ordinal + 1)
}

fn substitute_type(d: Domain, store: CheckStore, bindings: Vec(InferenceBindingRec), checked_type: U64) -> Result(TypeValueRec, __s0_Error) {
    let checked = (store.types)[checked_type - 1]
    if checked.kind == 6 {
        let bound = inference_lookup(bindings, checked.target)
        return Ok(TypeValueRec(store: store, checked_type: bound))
    }
    if checked.arg_count == 0 { return Ok(TypeValueRec(store: store, checked_type: checked_type)) }
    let empty_children = Vec.new(U64)
    let substituted = try substitute_children(d, store, bindings, store, checked, 0, empty_children)
    var current = substituted.store
    let prior = canonical_type_for_children(current, checked.kind, checked.target, substituted.children)
    if prior != 0 { return Ok(TypeValueRec(store: current, checked_type: prior)) }
    let first = (current.type_args).len() + 1
    current = try append_substituted_children(d, current, substituted.children, 0)
    current = try append_checked_type(d, current, 0, checked.kind, 0, checked.target, first, checked.arg_count)
    return Ok(TypeValueRec(store: current, checked_type: canonical_type_id(current, checked.kind, checked.target, first, checked.arg_count)))
}

fn unify_type_children(d: Domain, store: CheckStore, expected: CheckedTypeRec, actual: CheckedTypeRec, ordinal: U64, bindings: Vec(InferenceBindingRec)) -> Result(UnifyOutcome, __s0_Error) {
    if ordinal == expected.arg_count { return Ok(UnifyGood(bindings)) }
    let step = try unify_types(d, store, (store.type_args)[expected.first_arg - 1 + ordinal], (store.type_args)[actual.first_arg - 1 + ordinal], bindings)
    return match step {
        UnifyGood(value) => unify_type_children(d, store, expected, actual, ordinal + 1, value)
        UnifyConflict => Ok(UnifyConflict)
    }
}

fn unify_types(d: Domain, store: CheckStore, pattern: U64, concrete: U64, bindings: Vec(InferenceBindingRec)) -> Result(UnifyOutcome, __s0_Error) {
    let expected = (store.types)[pattern - 1]
    if expected.kind == 6 {
        let prior = inference_lookup(bindings, expected.target)
        if prior == 0 {
            let next = try vec_appended(InferenceBindingRec, bindings, InferenceBindingRec(param: expected.target, checked_type: concrete))
            return Ok(UnifyGood(next))
        }
        if prior == concrete { return Ok(UnifyGood(bindings)) }
        return Ok(UnifyConflict)
    }
    let actual = (store.types)[concrete - 1]
    // A source slice parameter is a non-retaining borrow pattern. Infer its
    // element from any sequence representation without making those concrete
    // types equal elsewhere in the checker.
    if expected.kind == 8 && expected.arg_count == 1 && (actual.kind == 15 || actual.kind == 17 || actual.kind == 18) && actual.arg_count == 1 {
        return unify_types(d, store, (store.type_args)[expected.first_arg - 1], (store.type_args)[actual.first_arg - 1], bindings)
    }
    if expected.kind != actual.kind || expected.target != actual.target || expected.arg_count != actual.arg_count { return Ok(UnifyConflict) }
    return unify_type_children(d, store, expected, actual, 0, bindings)
}

fn instance_matches(store: CheckStore, symbol: SymbolRec, declaration: U64, bindings: Vec(InferenceBindingRec)) -> Bool {
    if symbol.kind != 13 || symbol.declaration != declaration || symbol.instance_arg_count != (store.symbols)[declaration - 1].type_arity { return false }
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < (store.type_params).len() {
        let param = (store.type_params)[at]
        if param.owner == declaration {
            if (store.type_args)[symbol.first_instance_arg - 1 + ordinal] != inference_lookup(bindings, at + 1) { return false }
            ordinal = ordinal + 1
        }
        at = at + 1
    }
    return true
}

fn existing_instance(store: CheckStore, declaration: U64, bindings: Vec(InferenceBindingRec)) -> U64 {
    let declared = (store.symbols)[declaration - 1]
    if declared.type_arity == 0 { return declaration }
    var at: U64 = 0
    while at < (store.symbols).len() {
        let symbol = (store.symbols)[at]
        if instance_matches(store, symbol, declaration, bindings) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn expanding_ancestry(store: CheckStore, declaration: U64, bindings: Vec(InferenceBindingRec), parent: U64) -> Bool {
    var at = parent
    while at != 0 {
        let symbol = (store.symbols)[at - 1]
        if symbol.declaration == declaration && !instance_matches(store, symbol, declaration, bindings) { return true }
        at = symbol.discovery_parent
    }
    return false
}

fn append_instance_args(d: Domain, store: CheckStore, declaration: U64, bindings: Vec(InferenceBindingRec), param_at: U64) -> Result(CheckStore, __s0_Error) {
    if param_at == (store.type_params).len() { return Ok(store) }
    let param = (store.type_params)[param_at]
    var next = store
    if param.owner == declaration {
        let args = try vec_appended(U64, store.type_args, inference_lookup(bindings, param_at + 1))
        next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    }
    return append_instance_args(d, next, declaration, bindings, param_at + 1)
}

fn append_instance_role_uses(d: Domain, store: CheckStore, declaration: U64, instance: U64, bindings: Vec(InferenceBindingRec), declaration_role: U64, instance_role: U64, ordinal: U64, indexed: Bool) -> Result(CheckStore, __s0_Error) {
    if ordinal == use_count(store, declaration, declaration_role) { return Ok(store) }
    let use_id = use_by_ordinal(store, declaration, declaration_role, ordinal)
    let use = (store.uses)[use_id - 1]
    let concrete = try substitute_type(d, store, bindings, use.checked_type)
    let uses = try vec_appended(DeclTypeUseRec, concrete.store.uses, DeclTypeUseRec(owner: instance, role: instance_role, ordinal: use.ordinal, node: use.node, source: use.source, name_start: use.name_start, name_end: use.name_end, syntax: use.syntax, checked_type: concrete.checked_type))
    var use_order = concrete.store.indexes.use_order
    if indexed { try use_order.try_push((uses).len()) }
    let indexes = CheckerIndexes(uses: concrete.store.indexes.uses, use_order: use_order, complete: concrete.store.indexes.complete)
    let next = CheckStore(symbols: concrete.store.symbols, type_params: concrete.store.type_params, types: concrete.store.types, type_args: concrete.store.type_args, type_annotations: concrete.store.type_annotations, uses: uses, indexes: indexes, locals: concrete.store.locals, environments: concrete.store.environments, expressions: concrete.store.expressions, call_annotations: concrete.store.call_annotations, expression_children: concrete.store.expression_children, returns: concrete.store.returns, control: concrete.store.control, diagnostics: concrete.store.diagnostics)
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
    let use_indexes = try vec_appended(CheckerUseIndexRec, store.indexes.uses, CheckerUseIndexRec(first: first, count: count))
    let indexes = CheckerIndexes(uses: use_indexes, use_order: store.indexes.use_order, complete: store.indexes.complete)
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return append_instance_use_index_slots(d, next, role + 1, parameter_first, parameter_count, result_first, result_count)
}

fn append_instance_uses(d: Domain, store: CheckStore, declaration: U64, instance: U64, bindings: Vec(InferenceBindingRec)) -> Result(CheckStore, __s0_Error) {
    let indexed = (store.indexes.uses).len() == (instance - 1) * 8
    let parameter_count = use_count(store, declaration, 5)
    let result_count = use_count(store, declaration, 6)
    let first = (store.indexes.use_order).len() + 1
    let parameters = try append_instance_role_uses(d, store, declaration, instance, bindings, 5, 7, 0, indexed)
    let results = try append_instance_role_uses(d, parameters, declaration, instance, bindings, 6, 8, 0, indexed)
    if !indexed { return Ok(results) }
    var parameter_first: U64 = 0
    var result_first: U64 = 0
    if parameter_count != 0 { parameter_first = first }
    if result_count != 0 { result_first = first + parameter_count }
    return append_instance_use_index_slots(d, results, 1, parameter_first, parameter_count, result_first, result_count)
}

fn instantiate_function(d: Domain, state: State, parse: ParseStore, store: CheckStore, declaration: U64, bindings: Vec(InferenceBindingRec), parent: U64, site: SyntaxRec) -> Result(InstanceOutcome, __s0_Error) {
    let found = existing_instance(store, declaration, bindings)
    if found != 0 { return Ok(InstanceGood(InstanceValueRec(store: store, instance: found))) }
    if expanding_ancestry(store, declaration, bindings, parent) {
        let failed = try check_token_fail(d, state, store, 59, site)
        return Ok(InstanceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let declared = (store.symbols)[declaration - 1]
    var param_at: U64 = 0
    while param_at < (store.type_params).len() {
        let param = (store.type_params)[param_at]
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
    let first = (store.type_args).len() + 1
    let with_args = try append_instance_args(d, store, declaration, bindings, 0)
    let instance = (with_args.symbols).len() + 1
    let symbols = try vec_appended(SymbolRec, with_args.symbols, SymbolRec(kind: 13, node: declared.node, source: declared.source, name_start: declared.name_start, name_end: declared.name_end, type_arity: 0, declaration: declaration, first_instance_arg: first, instance_arg_count: declared.type_arity, discovery_parent: parent, inherent_owner: declared.inherent_owner, module_source: declared.module_source, public: declared.public))
    let registered = CheckStore(symbols: symbols, type_params: with_args.type_params, types: with_args.types, type_args: with_args.type_args, type_annotations: with_args.type_annotations, uses: with_args.uses, indexes: with_args.indexes, locals: with_args.locals, environments: with_args.environments, expressions: with_args.expressions, call_annotations: with_args.call_annotations, expression_children: with_args.expression_children, returns: with_args.returns, control: with_args.control, diagnostics: with_args.diagnostics)
    let signed = try append_instance_uses(d, registered, declaration, instance, bindings)
    return Ok(InstanceGood(InstanceValueRec(store: signed, instance: instance)))
}

// Type children are reverse linked. Resolve every child (including its nested
// children) before recording this node's direct arguments.
fn resolve_arg_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(CheckResult, __s0_Error) {
    if link_id == 0 { return Ok(CheckGood(store)) }
    let link = (parse.links)[link_id - 1]
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
    while at < (store.type_annotations).len() {
        let annotation = (store.type_annotations)[at]
        if annotation.owner == owner && annotation.syntax == syntax { return annotation.checked_type }
        at = at + 1
    }
    return 0
}

// Append only the current node's direct children, in source order. Since all
// recursive resolution is already complete, this range remains contiguous.
fn record_arg_links(d: Domain, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64) -> Result(CheckStore, __s0_Error) {
    if link_id == 0 { return Ok(store) }
    let link = (parse.links)[link_id - 1]
    let current = try record_arg_links(d, parse, store, owner, link.next)
    let checked = checked_type_for_syntax(current, owner, link.node)
    let args = try vec_appended(U64, current.type_args, checked)
    return Ok(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics))
}

fn type_arg_count(parse: ParseStore, link_id: U64) -> U64 {
    var count: U64 = 0
    var at = link_id
    while at != 0 {
        let link = (parse.links)[at - 1]
        count = count + 1
        at = link.next
    }
    return count
}

fn canonical_type_for_links(parse: ParseStore, store: CheckStore, owner: U64, kind: U64, target: U64, link_id: U64) -> U64 {
    let count = type_arg_count(parse, link_id)
    var type_at: U64 = 0
    while type_at < (store.types).len() {
        let checked = (store.types)[type_at]
        if checked.kind == kind && checked.target == target && checked.arg_count == count {
            var same = true
            var link_at = link_id
            var ordinal = count
            while link_at != 0 {
                ordinal = ordinal - 1
                let link = (parse.links)[link_at - 1]
                if (store.type_args)[checked.first_arg - 1 + ordinal] != checked_type_for_syntax(store, owner, link.node) { same = false }
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
    let node = (parse.nodes)[node_id - 1]
    if node.kind == 4 { return builtin_type_kind(state, node) == 1 }
    if node.kind != 6 || !node_word(state, node, "Ptr") || type_arg_count(parse, node.children) != 1 { return false }
    let link = (parse.links)[node.children - 1]
    let child = (parse.nodes)[link.node - 1]
    return child.kind == 4 && builtin_type_kind(state, child) == 1
}

fn resolve_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = (parse.nodes)[node_id - 1]
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
        let existing = canonical_type_for_links(parse, current, owner, 8, 0, node.children)
        var appended = current
        if existing != 0 { appended = try annotate_checked_type(d, current, owner, node_id, existing) } else {
            let start = (current.type_args).len()
            let recorded = try record_arg_links(d, parse, current, owner, node.children)
            appended = try append_checked_type(d, recorded, owner, 8, node_id, 0, start + 1, 1)
        }
        let empty = Vec.new(TypeBindingRec)
        let no_ancestry = Vec.new(DeclAncestryRec)
        let checked_id = checked_type_for_syntax(appended, owner, node_id)
        let canonical = (appended.types)[checked_id - 1]
        let child = (appended.type_args)[canonical.first_arg - 1]
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, child, 0, 0, boundary) { return check_type_detail_fail(d, appended, 10, syntax_diag_node(state, parse, node_id), child) }
        return Ok(CheckGood(appended))
    }
    if node.kind == 4 {
        let builtin = builtin_type_kind(state, node)
        if builtin == 1 { return Ok(CheckGood(try append_checked_type(d, store, owner, 1, node_id, primitive_type_target(state, node), 0, 0))) }
        if builtin == 2 || builtin == 14 { return Ok(CheckGood(try append_checked_type(d, store, owner, builtin, node_id, 0, 0, 0))) }
        if builtin != 0 { return Ok(CheckGood(try append_checked_type(d, store, owner, builtin, node_id, 0, 0, 0))) }
        let declaration = instance_declaration(store, owner)
        let param = find_type_param(state, store, declaration, node)
        if param != 0 {
            let concrete = instance_type_arg(store, owner, param)
            if concrete != 0 { return Ok(CheckGood(try annotate_checked_type(d, store, owner, node_id, concrete))) }
            return Ok(CheckGood(try append_checked_type(d, store, owner, 6, node_id, param, 0, 0)))
        }
        let symbol = find_declared_type(state, parse, store, node)
        if symbol == 0 { return check_fail(d, store, 4, node, 0, 0, 0) }
        if (store.symbols)[symbol - 1].type_arity != 0 { return check_fail(d, store, 5, node, 0, 0, 0) }
        let appended = try append_checked_type(d, store, owner, 7, node_id, symbol, 0, 0)
        let checked_id = checked_type_for_syntax(appended, owner, node_id)
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, syntax_diag_node(state, parse, node_id), boundary)
    }
    if node.kind == 6 && node_word(state, node, "Array") {
        if type_arg_count(parse, node.children) != 2 { return check_fail(d, store, 5, node, 0, 0, 0) }
        let length_link = (parse.links)[node.children - 1]
        let element_link = (parse.links)[length_link.next - 1]
        let length_node = (parse.nodes)[length_link.node - 1]
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
        let first = (current.type_args).len() + 1
        let args = try vec_appended(U64, current.type_args, element)
        let recorded = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
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
    if node_word(state, node, "Map") { kind = 11
        arity = 2 }
    if node_word(state, node, "Ptr") { kind = 12
        arity = 1 }
    if node_word(state, node, "__s0_Buffer") { kind = 13
        arity = 1 }
    if node_word(state, node, "Vec") { kind = 17
        arity = 1 }
    if node_word(state, node, "MutSlice") { kind = 18
        arity = 1 }
    var target: U64 = 0
    if kind == 0 {
        target = find_declared_type(state, parse, current, node)
        if target != 0 { kind = 7
            arity = (current.symbols)[target - 1].type_arity }
    }
    // Do not commit a direct-argument range until the application itself is
    // valid. Failed heads and arities retain resolved child types but never
    // leave ownerless type-argument records in a CheckBad store.
    if kind == 0 { return check_fail(d, current, 4, node, 0, 0, 0) }
    if count != arity { return check_fail(d, current, 5, node, 0, 0, 0) }
    let existing = canonical_type_for_links(parse, current, owner, kind, target, node.children)
    var appended = current
    if existing != 0 { appended = try annotate_checked_type(d, current, owner, node_id, existing) } else {
        let start = (current.type_args).len()
        let recorded = try record_arg_links(d, parse, current, owner, node.children)
        var first: U64 = 0
        if count != 0 { first = start + 1 }
        appended = try append_checked_type(d, recorded, owner, kind, node_id, target, first, count)
    }
    let checked_id = checked_type_for_syntax(appended, owner, node_id)
    let checked = (appended.types)[checked_id - 1]
    let empty = Vec.new(TypeBindingRec)
    let no_ancestry = Vec.new(DeclAncestryRec)
    if kind == 13 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let child = (appended.type_args)[checked.first_arg - 1]
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, child, 0, 0, boundary) { return check_type_detail_fail(d, appended, 11, syntax_diag_node(state, parse, node_id), child) }
    }
    if kind == 17 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let child = (appended.type_args)[checked.first_arg - 1]
        let category = try interpreted_type_category(d, state, parse, appended, empty, no_ancestry, child, 0, 0)
        if category.category != 1 && !(category.category == 3 && !category.contains_nonimmutable_scoped) { return check_type_detail_fail(d, appended, 100, syntax_diag_node(state, parse, node_id), child) }
    }
    if kind == 11 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let key = (appended.type_args)[checked.first_arg - 1]
        let value = (appended.type_args)[checked.first_arg]
        if !(try interpreted_map_key_ok(d, state, parse, appended, empty, no_ancestry, key, 0, 0, boundary)) { return check_type_detail_fail(d, appended, 12, syntax_diag_node(state, parse, node_id), key) }
        if try interpreted_contains_reference(d, state, parse, appended, empty, no_ancestry, value, 0, 0, boundary) { return check_type_detail_fail(d, appended, 13, syntax_diag_node(state, parse, node_id), value) }
    }
    if kind == 7 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, syntax_diag_node(state, parse, node_id), boundary)
    }
    return Ok(CheckGood(appended))
}

fn check_type_links(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, link_id: U64, role: U64, skip_kind: U64) -> Result(CheckResult, __s0_Error) {
    if link_id == 0 { return Ok(CheckGood(store)) }
    let link = (parse.links)[link_id - 1]
    let before = try check_type_links(d, state, parse, store, owner, link.next, role, skip_kind)
    let current = match before {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match before {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(before) }
    let child = (parse.nodes)[link.node - 1]
    if child.kind == 7 || child.kind == 14 || child.kind == 16 || child.kind == skip_kind { return Ok(CheckGood(current)) }
    var actual_role = role
    if role == 5 && child.kind != 13 && child.kind != 47 && child.kind != 48 { actual_role = 6 }
    var actual_ordinal: U64 = 0
    var duplicate_parameter = false
    var use_at: U64 = 0
    while use_at < (current.uses).len() {
        let prior = (current.uses)[use_at]
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
        let uses = try vec_appended(DeclTypeUseRec, current.uses, DeclTypeUseRec(owner: owner, role: 2, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: child.name_start, name_end: child.name_end, syntax: 0, checked_type: 0))
        return Ok(CheckGood(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)))
    }
    var syntax = link.node
    if child.kind == 8 || child.kind == 9 || child.kind == 10 || child.kind == 13 || child.kind == 47 || child.kind == 48 {
        let head = (parse.links)[child.children - 1]
        syntax = head.node
    }
    let owner_symbol = (current.symbols)[owner - 1]
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
        let empty = Vec.new(TypeBindingRec)
        if try direct_type_concrete(d, next, empty, checked_id, 0) {
            let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, syntax_diag_node(state, parse, syntax), 0)
            if match validated {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(validated) }
        }
    }
    if actual_role == 5 {
        let checked = (next.types)[checked_type_for_syntax(next, owner, syntax) - 1]
        let diag_node = (parse.nodes)[syntax - 1]
        if duplicate_parameter { return check_fail(d, next, 16, diag_node, 0, 0, 0) }
        if reserved_value_name(state, next, child) { return check_fail(d, next, 17, diag_node, 0, 0, 0) }
        if child.kind == 47 || child.kind == 48 {
            let empty = Vec.new(TypeBindingRec)
            let no_ancestry = Vec.new(DeclAncestryRec)
            let category = try interpreted_type_category(d, state, parse, next, empty, no_ancestry, checked_type_for_syntax(next, owner, syntax), 0, 0)
            if category.category != 0 {
                if child.kind == 47 && category.category == 1 && !node_word(state, child, "self") { return check_token_fail(d, state, next, 89, diag_node) }
                if child.kind == 48 && category.category != 2 { return check_token_fail(d, state, next, 90, diag_node) }
            }
        }
    }
    var name_start = child.name_start
    var name_end = child.name_end
    if actual_role == 3 || actual_role == 4 || actual_role == 6 { name_start = 0
        name_end = 0 }
    let uses = try vec_appended(DeclTypeUseRec, next.uses, DeclTypeUseRec(owner: owner, role: actual_role, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: name_start, name_end: name_end, syntax: syntax, checked_type: checked_type_for_syntax(next, owner, syntax)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: uses, indexes: next.indexes, locals: next.locals, environments: next.environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, control: next.control, diagnostics: next.diagnostics)))
}

fn check_import_types(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, signature: SyntaxRec) -> Result(CheckResult, __s0_Error) {
    let result_link = (parse.links)[signature.children - 1]
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
    let empty = Vec.new(TypeBindingRec)
    if try direct_type_concrete(d, next, empty, checked_id, 0) {
        let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, syntax_diag_node(state, parse, result_link.node), 0)
        if match validated {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(validated) }
    }
    let uses = try vec_appended(DeclTypeUseRec, next.uses, DeclTypeUseRec(owner: owner, role: 4, ordinal: 0, node: result_link.node, source: signature.source, name_start: 0, name_end: 0, syntax: result_link.node, checked_type: checked_type_for_syntax(next, owner, result_link.node)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: uses, indexes: next.indexes, locals: next.locals, environments: next.environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, control: next.control, diagnostics: next.diagnostics)))
}

// Materialize aggregate value edges without recursion. Declared applications
// contribute their target and expand that declaration's representation under
// positional bindings, so substitution-introduced cycles are visible. Option,
// Result, and Map expose their arguments; Slice, Ptr, and Buffer cut the walk.
fn collect_cycle_edges(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(Vec(CycleEdgeRec), __s0_Error) {
    let initial_work = Vec.new(CycleWorkRec)
    var work = initial_work
    let initial_edges = Vec.new(CycleEdgeRec)
    var edges = initial_edges
    let initial_bindings = Vec.new(TypeBindingRec)
    var bindings = initial_bindings
    let initial_ancestry = Vec.new(DeclAncestryRec)
    var ancestry = initial_ancestry
    let initial_memo = Vec.new(ExpansionMemoRec)
    var memo = initial_memo
    let initial_seen = Vec.new(InterpStateRec)
    var seen = initial_seen
    var at: U64 = 0
    while at < (store.uses).len() {
        let item = (store.uses)[at]
        if (item.role == 1 || item.role == 2) && item.checked_type != 0 {
            try work.try_push(CycleWorkRec(owner: item.owner, checked_type: item.checked_type, env: 0, ancestry: 0))
        }
        at = at + 1
    }
    at = 0
    while at < (work).len() {
        let item = work[at]
        let norm = normalize_interp(store, bindings, item.checked_type, item.env, item.ancestry)
        let checked = (store.types)[norm.checked_type - 1]
        var inspect = true
        if checked.kind != 7 {
            inspect = !interp_state_seen(seen, item.owner, norm.checked_type, norm.env, norm.ancestry)
            if inspect { try seen.try_push(InterpStateRec(owner: item.owner, checked_type: norm.checked_type, env: norm.env, ancestry: norm.ancestry)) }
        }
        if inspect {
            if checked.kind == 7 {
                try edges.try_push(CycleEdgeRec(owner: item.owner, target: checked.target))
                if !ancestry_has(ancestry, norm.ancestry, checked.target) {
                    if !(try expansion_seen(d, state, parse, store, bindings, memo, item.owner, norm.checked_type, norm.env)) {
                        memo = try remember_expansion(d, memo, item.owner, checked.target, norm.checked_type, norm.env)
                        let old_len = (bindings).len()
                        bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env, norm.ancestry)
                        let target_env = declaration_env_head(bindings, old_len)
                        try ancestry.try_push(DeclAncestryRec(target: checked.target, env: target_env, parent: norm.ancestry))
                        let chain = (ancestry).len()
                        var use_at: U64 = 0
                        while use_at < (store.uses).len() {
                            let use = (store.uses)[use_at]
                            if use.owner == checked.target && (use.role == 1 || use.role == 2) && use.checked_type != 0 {
                                try work.try_push(CycleWorkRec(owner: item.owner, checked_type: use.checked_type, env: target_env, ancestry: chain))
                            }
                            use_at = use_at + 1
                        }
                    }
                }
            }
            if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 || checked.kind == 15 {
                var arg_at: U64 = 0
                while arg_at < checked.arg_count {
                    let arg = (store.type_args)[checked.first_arg - 1 + arg_at]
                    try work.try_push(CycleWorkRec(owner: item.owner, checked_type: arg, env: norm.env, ancestry: norm.ancestry))
                    arg_at = arg_at + 1
                }
            }
        }
        at = at + 1
    }
    return Ok(edges)
}

fn owner_has_edge(edges: Vec(CycleEdgeRec), owner: U64, target: U64) -> Bool {
    var at: U64 = 0
    while at < (edges).len() {
        let item = edges[at]
        if item.owner == owner && item.target == target { return true }
        at = at + 1
    }
    return false
}

fn cycle_color(colors: Vec(CycleColorRec), owner: U64) -> U64 {
    var at = (colors).len()
    while at != 0 {
        at = at - 1
        let item = colors[at]
        if item.owner == owner { return item.color }
    }
    return 0
}

fn reject_value_cycles(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    let edges = try collect_cycle_edges(d, state, parse, store)
    let initial_colors = Vec.new(CycleColorRec)
    var colors = initial_colors
    let initial_frames = Vec.new(CycleFrameRec)
    var frames = initial_frames
    var owner: U64 = 1
    while owner <= (store.symbols).len() {
        let symbol = (store.symbols)[owner - 1]
        if (symbol.kind == 2 || symbol.kind == 3) && cycle_color(colors, owner) == 0 {
            try colors.try_push(CycleColorRec(owner: owner, color: 1))
            try frames.try_push(CycleFrameRec(owner: owner, next_target: 1, parent: 0))
            var frame_id = (frames).len()
            while frame_id != 0 {
                let frame = frames[frame_id - 1]
                var target = frame.next_target
                var found: U64 = 0
                while target <= (store.symbols).len() && found == 0 {
                    let candidate = (store.symbols)[target - 1]
                    if (candidate.kind == 2 || candidate.kind == 3) && owner_has_edge(edges, frame.owner, target) { found = target }
                    target = target + 1
                }
                if found == 0 {
                    try colors.try_push(CycleColorRec(owner: frame.owner, color: 2))
                    frame_id = frame.parent
                } else {
                    try frames.try_push(CycleFrameRec(owner: frame.owner, next_target: found + 1, parent: frame.parent))
                    let continuation = (frames).len()
                    let color = cycle_color(colors, found)
                    if color == 1 { return check_decl_fail(d, state, parse, store, 9, found) }
                    if color == 2 { frame_id = continuation }
                    if color == 0 {
                        try colors.try_push(CycleColorRec(owner: found, color: 1))
                        try frames.try_push(CycleFrameRec(owner: found, next_target: 1, parent: continuation))
                        frame_id = (frames).len()
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
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if (use.role == 1 || use.role == 2) && use.checked_type != 0 {
            let empty = Vec.new(TypeBindingRec)
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
    let symbol = (store.symbols)[owner - 1]
    if !(symbol.kind == wanted || (wanted == 0 && (symbol.kind == 2 || symbol.kind == 3))) { return Ok(CheckGood(store)) }
    let root = (parse.nodes)[symbol.node - 1]
    let params = try collect_param_links(d, state, parse, store, owner, root.children)
    let with_params = check_result_store(params)
    if check_result_bad(params) { return Ok(params) }
    var checked: CheckResult = CheckGood(with_params)
    if root.kind == 2 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 1, 0) }
    if root.kind == 3 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 2, 11) }
    if root.kind == 12 { checked = try check_type_links(d, state, parse, with_params, owner, root.children, 5, 0) }
    if root.kind == 1 {
        let signature = (parse.links)[root.children - 1]
        let sig = (parse.nodes)[signature.node - 1]
        checked = try check_import_types(d, state, parse, with_params, owner, sig)
    }
    let complete = check_result_store(checked)
    if check_result_bad(checked) { return Ok(checked) }
    if root.kind == 3 {
        var variants: U64 = 0
        var item_at: U64 = 0
        while item_at < (complete.uses).len() {
            let item = (complete.uses)[item_at]
            if item.owner == owner && item.role == 2 { variants = variants + 1 }
            item_at = item_at + 1
        }
        if variants == 0 { return check_decl_fail(d, state, parse, complete, 8, owner) }
    }
    return Ok(CheckGood(complete))
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
    while at <= (current.symbols).len() {
        let result = try check_one_declaration(d, state, parse, current, at, wanted)
        current = check_result_store(result)
        last = result
        if check_result_bad(result) { failed = 1 }
        if failed == 0 { at = at + 1 }
        if failed != 0 { at = (current.symbols).len() + 1 }
    }
    return Ok(last)
}

fn check_declaration_kind(d: Domain, state: State, parse: ParseStore, store: CheckStore, wanted: U64) -> Result(CheckResult, __s0_Error) {
    return check_declaration_at(d, state, parse, store, 1, wanted)
}

fn function_use(store: CheckStore, owner: U64, role: U64, node: SyntaxRec, state: State) -> U64 {
    let symbol = (store.symbols)[owner - 1]
    var actual_role = role
    if symbol.kind == 13 {
        if role == 5 { actual_role = 7 }
        if role == 6 { actual_role = 8 }
    }
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
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
    while at < (store.symbols).len() {
        let symbol = (store.symbols)[at]
        if same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) { return true }
        at = at + 1
    }
    at = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
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

fn zero_magnitude(values: Vec(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        if values[at] != 48 { return false }
        at = at + 1
    }
    return true
}

// Canonical digit order compares by width, then by ASCII byte order. Leading
// zeros are skipped so 007 and 7 share one canonical form.
fn digits_at_most(values: Vec(U8), start: U64, end: U64, limit: [U8]) -> Bool {
    var first = start
    while first + 1 < end && values[first] == 48 { first = first + 1 }
    let width = end - first
    if width != len(limit) { return width < len(limit) }
    var at: U64 = 0
    while at < width {
        let digit = values[first + at]
        let bound = limit[at]
        if digit != bound { return digit < bound }
        at = at + 1
    }
    return true
}

fn array_type_length(state: State, node: SyntaxRec) -> ArrayLengthRec {
    if node.kind != 20 || node.token == 0 || node.token > (state.tokens).len() { return ArrayLengthRec(valid: false, value: 0) }
    let token = (state.tokens)[node.token - 1]
    if token.kind != 2 || token.value_start >= token.value_end || (state.values)[token.value_start] == 45 { return ArrayLengthRec(valid: false, value: 0) }
    if !digits_at_most(state.values, token.value_start, token.value_end, "18446744073709551615") { return ArrayLengthRec(valid: false, value: 0) }
    var value: U64 = 0
    var at = token.value_start
    while at < token.value_end {
        let byte = (state.values)[at]
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
    var at = (store.environments).len()
    while at != 0 {
        let environment = (store.environments)[at - 1]
        if environment.owner == owner { return at }
        at = at - 1
    }
    return 0
}

fn local_lookup(store: CheckStore, owner: U64, node: SyntaxRec, state: State) -> U64 {
    var environment = current_environment(store, owner)
    while environment != 0 {
        let item = (store.environments)[environment - 1]
        if item.binding != 0 {
            let local = (store.locals)[item.binding - 1]
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
        let item = (store.environments)[at - 1]
        if item.binding != 0 {
            let local = (store.locals)[item.binding - 1]
            let local_type = (store.types)[local.checked_type - 1]
            if local_type.kind == 8 || local_type.kind == 18 {
                var expression_id = previous_expression_for_owner(store, owner)
                while expression_id != 0 {
                    let expression = (store.expressions)[expression_id - 1]
                    if expression.site_kind == 1 && expression.site_syntax == local.syntax && expression.kind == 18 && expression.annotation != 0 {
                        let annotation = (store.call_annotations)[expression.annotation - 1]
                        if annotation.builtin >= 23 && annotation.builtin <= 25 && expression.child_count != 0 {
                            let child = (store.expression_children)[expression.first_child - 1].expression
                            let source = (store.expressions)[child - 1]
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
fn lexical_access_conflict(store: CheckStore, owner: U64, local: U64, mode: U64) -> Bool {
    let view = active_view_over(store, owner, local, current_environment(store, owner))
    if view == 24 || view == 25 { return true }
    if view == 23 && (mode == 2 || mode == 4) { return true }
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
    return CheckStore(symbols: base.symbols, type_params: base.type_params, types: base.types, type_args: base.type_args, type_annotations: base.type_annotations, uses: base.uses, indexes: base.indexes, locals: base.locals, environments: base.environments, expressions: base.expressions, call_annotations: base.call_annotations, expression_children: base.expression_children, returns: base.returns, control: base.control, diagnostics: failed.diagnostics)
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
    let rec = (store.types)[checked_type - 1]
    if rec.kind == 1 { return DiagnosticTypeRec(kind: 1, target: rec.target) }
    if rec.kind == 2 || rec.kind == 14 || rec.kind == 16 { return DiagnosticTypeRec(kind: rec.kind, target: 0) }
    if (rec.kind == 8 || rec.kind == 15 || rec.kind == 17 || rec.kind == 18) && rec.arg_count == 1 {
        let child = (store.types)[(store.type_args)[rec.first_arg - 1] - 1]
        if child.kind == 1 { return DiagnosticTypeRec(kind: rec.kind, target: child.target) }
    }
    if rec.kind == 7 { return DiagnosticTypeRec(kind: 7, target: rec.target) }
    return DiagnosticTypeRec(kind: rec.kind, target: 0)
}

fn sequence_element_type(state: State, parse: ParseStore, store: CheckStore, checked_type: U64) -> U64 {
    let sequence = (store.types)[checked_type - 1]
    if (sequence.kind == 8 || sequence.kind == 15 || sequence.kind == 17 || sequence.kind == 18) && sequence.arg_count == 1 { return (store.type_args)[sequence.first_arg - 1] }
    if sequence.kind == 16 { return primitive_type_id(state, parse, store, "U8") }
    return 0
}

fn checker_utf8_continuation(value: U8) -> Bool { return value >= 128 && value <= 191 }

fn checker_utf8_valid(values: Vec(U8), start: U64, end: U64) -> Bool {
    var at = start
    while at < end {
        let first = values[at]
        if first < 128 { at = at + 1 }
        else { if first >= 194 && first <= 223 && at + 1 < end && checker_utf8_continuation(values[at + 1]) { at = at + 2 }
        else { if first == 224 && at + 2 < end && values[at + 1] >= 160 && values[at + 1] <= 191 && checker_utf8_continuation(values[at + 2]) { at = at + 3 }
        else { if ((first >= 225 && first <= 236) || (first >= 238 && first <= 239)) && at + 2 < end && checker_utf8_continuation(values[at + 1]) && checker_utf8_continuation(values[at + 2]) { at = at + 3 }
        else { if first == 237 && at + 2 < end && values[at + 1] >= 128 && values[at + 1] <= 159 && checker_utf8_continuation(values[at + 2]) { at = at + 3 }
        else { if first == 240 && at + 3 < end && values[at + 1] >= 144 && values[at + 1] <= 191 && checker_utf8_continuation(values[at + 2]) && checker_utf8_continuation(values[at + 3]) { at = at + 4 }
        else { if first >= 241 && first <= 243 && at + 3 < end && checker_utf8_continuation(values[at + 1]) && checker_utf8_continuation(values[at + 2]) && checker_utf8_continuation(values[at + 3]) { at = at + 4 }
        else { if first == 244 && at + 3 < end && values[at + 1] >= 128 && values[at + 1] <= 143 && checker_utf8_continuation(values[at + 2]) && checker_utf8_continuation(values[at + 3]) { at = at + 4 }
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

fn check_with_expressions(store: CheckStore, expressions: Vec(CheckedExprRec)) -> CheckStore {
    return CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
}

fn primitive_type_id(state: State, parse: ParseStore, store: CheckStore, name: [U8]) -> U64 {
    var target: U64 = 0
    if len(name) == 4 && name[0] == 66 { target = 1 }
    if len(name) == 3 && name[0] == 73 { target = 5 }
    if len(name) == 2 && name[0] == 85 && name[1] == 56 { target = 6 }
    if len(name) == 3 && name[0] == 85 { target = 9 }
    if len(name) == 3 && name[0] == 70 && name[1] == 54 { target = 11 }
    var at: U64 = 0
    while at < (store.types).len() {
        let checked = (store.types)[at]
        if checked.kind == 1 && checked.target == target { return at + 1 }
        at = at + 1
    }
    return 0
}

fn primitive_type_named(state: State, parse: ParseStore, store: CheckStore, checked_type: U64, name: [U8]) -> Bool {
    if checked_type == 0 { return false }
    let checked = (store.types)[checked_type - 1]
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
    let bindings = Vec.new(TypeBindingRec)
    return interpreted_type_equal(d, state, parse, store, bindings, left, 0, right, 0)
}

fn parameter_type_compatible(d: Domain, state: State, parse: ParseStore, store: CheckStore, parameter: U64, argument: U64) -> Result(Bool, __s0_Error) {
    if try expression_type_equal(d, state, parse, store, parameter, argument) { return Ok(true) }
    let wanted = (store.types)[parameter - 1]
    let actual = (store.types)[argument - 1]
    if wanted.kind != 8 || wanted.arg_count != 1 || (actual.kind != 15 && actual.kind != 17 && actual.kind != 18) || actual.arg_count != 1 { return Ok(false) }
    return expression_type_equal(d, state, parse, store, (store.type_args)[wanted.first_arg - 1], (store.type_args)[actual.first_arg - 1])
}

fn call_argument_requires_final(store: CheckStore, parameter: U64, expression_id: U64) -> Bool {
    let wanted = (store.types)[parameter - 1]
    if wanted.kind == 18 { return true }
    let expression = (store.expressions)[expression_id - 1]
    let actual = (store.types)[expression.checked_type - 1]
    if wanted.kind == 8 && (actual.kind == 15 || actual.kind == 17 || actual.kind == 18) { return true }
    if expression.kind != 18 || expression.annotation == 0 { return false }
    let call = (store.call_annotations)[expression.annotation - 1]
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

fn match_variant_seen(arms: Vec(MatchArmDraftRec), first: U64, count: U64, variant_use: U64, variant_kind: U64) -> Bool {
    var at: U64 = 0
    while at < count {
        let arm = arms[first - 1 + at]
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

fn check_match_arm_links(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, link_id: U64, scrutinee_type: U64, expected: U64, drafts: Vec(MatchArmDraftRec), match_node: SyntaxRec) -> Result(MatchArmOutcome, __s0_Error) {
    let link = (parse.links)[link_id - 1]
    if link.next == 0 { return Ok(MatchArmsGood(MatchArmValueRec(store: store, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, arms: drafts))) }
    let prior_outcome = try check_match_arm_links(d, state, parse, base, store, owner, link.next, scrutinee_type, expected, drafts, match_node)
    let prior = match prior_outcome {
        MatchArmsGood(value) => value
        MatchArmsBad(value) => MatchArmValueRec(store: value, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, arms: drafts)
        MatchArmsDefer => MatchArmValueRec(store: store, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, arms: drafts)
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
    let arm = (parse.nodes)[link.node - 1]
    let concrete = (prior.store.types)[scrutinee_type - 1]
    var variant_use: U64 = 0
    var variant_kind: U64 = 0
    var payload_type: U64 = 0
    if arm.name_start == 0 { variant_kind = 7 } else {
        if concrete.kind == 7 {
            variant_use = variant_named(state, prior.store, concrete.target, arm)
            if variant_use == 0 { return match_arms_fail(d, state, prior.store, 71, match_node) }
            let variant = (prior.store.uses)[variant_use - 1]
            if variant.checked_type != 0 {
                let payload = try concrete_field_type(d, prior.store, scrutinee_type, variant_use)
                payload_type = payload.checked_type
            }
        } else {
            if concrete.kind == 9 && node_word(state, arm, "None") { variant_kind = 1 }
            if concrete.kind == 9 && node_word(state, arm, "Some") {
                variant_kind = 2
                payload_type = (prior.store.type_args)[concrete.first_arg - 1]
            }
            if concrete.kind == 10 && node_word(state, arm, "Ok") {
                variant_kind = 3
                payload_type = (prior.store.type_args)[concrete.first_arg - 1]
            }
            if concrete.kind == 10 && node_word(state, arm, "Err") {
                variant_kind = 4
                payload_type = (prior.store.type_args)[concrete.first_arg]
            }
            if payload_type != 0 {
                let payload = (prior.store.types)[payload_type - 1]
                if payload.kind == 1 && payload.target == 12 { payload_type = 0 }
            }
            if (concrete.kind == 5 || concrete.kind == 19) && node_word(state, arm, "OutOfMemory") { variant_kind = 5 }
            if (concrete.kind == 5 || concrete.kind == 19) && node_word(state, arm, "Limit") { variant_kind = 6 }
            if variant_kind == 0 { return match_arms_fail(d, state, prior.store, 71, match_node) }
        }
        if match_variant_seen(prior.arms, prior.first_arm, prior.arm_count, variant_use, variant_kind) { return match_arms_fail(d, state, prior.store, 72, match_node) }
    }
    let body_link = (parse.links)[arm.children - 1]
    var current = prior.store
    let entry = current_environment(current, owner)
    var binding: U64 = 0
    var binding_link: U64 = 0
    if body_link.next != 0 { binding_link = body_link.next }
    if payload_type != 0 && binding_link == 0 { return match_arms_fail(d, state, current, 73, match_node) }
    if payload_type == 0 && binding_link != 0 { return match_arms_fail(d, state, current, 74, match_node) }
    if binding_link != 0 {
        let binding_node_id = (parse.links)[binding_link - 1].node
        let binding_node = (parse.nodes)[binding_node_id - 1]
        if reserved_value_name(state, current, binding_node) { return match_arms_fail(d, state, current, 75, match_node) }
        if local_lookup(current, owner, binding_node, state) != 0 { return match_arms_fail(d, state, current, 76, match_node) }
        let locals = try vec_appended(LocalRec, current.locals, LocalRec(owner: owner, kind: 2, syntax: binding_node_id, source: binding_node.source, name_start: binding_node.name_start, name_end: binding_node.name_end, mutable: 0, checked_type: payload_type))
        binding = (locals).len()
        let environments = try vec_appended(EnvironmentRec, current.environments, EnvironmentRec(owner: owner, parent: entry, binding: binding))
        current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: locals, environments: environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
    }
    var arm_expected = expected
    if prior.arm_type != 0 { arm_expected = prior.arm_type }
    let body_node = (parse.nodes)[body_link.node - 1]
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
    if prior.arm_type != 0 && !(try expression_type_equal(d, state, parse, current, prior.arm_type, draft.checked_type)) { return match_arms_fail(d, state, current, 77, body_node) }
    let arm_environment = current_environment(current, owner)
    let next_drafts = try vec_appended(MatchArmDraftRec, prior.arms, MatchArmDraftRec(owner: owner, syntax: link.node, variant_use: variant_use, variant_kind: variant_kind, binding: binding, environment: arm_environment, body: draft.expression))
    if binding != 0 { current = try restore_environment(d, current, owner, entry) }
    var arm_type = prior.arm_type
    if arm_type == 0 { arm_type = draft.checked_type }
    var first = prior.first_arm
    if first == 0 { first = (next_drafts).len() }
    return Ok(MatchArmsGood(MatchArmValueRec(store: current, arm_type: arm_type, first_arm: first, arm_count: prior.arm_count + 1, wildcard: prior.wildcard || variant_kind == 7, arms: next_drafts)))
}

fn append_expression(d: Domain, store: CheckStore, owner: U64, syntax: U64, kind: U64, checked_type: U64, reference: U64, bool_value: U64, left: U64, right: U64, operator: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var children = store.expression_children
    var first_child: U64 = 0
    var child_count: U64 = 0
    if left != 0 {
        first_child = (children).len() + 1
        try children.try_push(CheckedExprChildRec(expression: left))
        child_count = child_count + 1
    }
    if right != 0 {
        try children.try_push(CheckedExprChildRec(expression: right))
        child_count = child_count + 1
    }
    let expressions = try vec_appended(CheckedExprRec, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: kind, checked_type: checked_type, parameter_use: reference, bool_value: bool_value, left: 0, right: 0, annotation: 0, first_child: first_child, child_count: child_count, operator: operator, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: store.call_annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, (expressions).len())
}

fn import_target_source(state: State, parse: ParseStore, imp: SyntaxRec) -> U64 {
    return module_source_named(state, parse, imp.source, imp.name_start, imp.name_end)
}

fn import_has_selected(parse: ParseStore, imp: SyntaxRec) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        if (parse.nodes)[item.node - 1].kind == 43 { return true }
        link = item.next
    }
    return false
}

fn import_binding_count(parse: ParseStore, imp: SyntaxRec) -> U64 {
    var count: U64 = 0
    var link = imp.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        if (parse.nodes)[item.node - 1].kind == 43 { count = count + 1 }
        link = item.next
    }
    if count == 0 { return 1 }
    return count
}

fn import_binding_at(state: State, parse: ParseStore, imp: SyntaxRec, ordinal: U64) -> SyntaxRec {
    var selected: U64 = 0
    var link = imp.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        let child = (parse.nodes)[item.node - 1]
        if child.kind == 43 {
            if selected == ordinal { return child }
            selected = selected + 1
        }
        link = item.next
    }
    link = imp.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        let child = (parse.nodes)[item.node - 1]
        if child.kind == 44 { return child }
        link = item.next
    }
    var last = imp.name_start
    var at = imp.name_start
    let source = (state.sources)[imp.source]
    while at < imp.name_end {
        if text_byte(state, source, at) == 46 { last = at + 1 }
        at = at + 1
    }
    return SyntaxRec(kind: 44, token: imp.token, source: imp.source, start: last, end: imp.name_end, name_start: last, name_end: imp.name_end, children: 0)
}

fn validate_import_bindings(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var root_at: U64 = 0
    while root_at < (parse.roots).len() {
        let imp = (parse.nodes)[(parse.roots)[root_at] - 1]
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
                    let prior = (parse.nodes)[(parse.roots)[prior_root] - 1]
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
        let item = (parse.links)[link - 1]
        let child = (parse.nodes)[item.node - 1]
        if child.kind == 43 && same_name(state, node.source, node.name_start, node.name_end, child.source, child.name_start, child.name_end) { return true }
        link = item.next
    }
    return false
}

fn import_namespace_matches(state: State, parse: ParseStore, imp: SyntaxRec, node: SyntaxRec) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        let child = (parse.nodes)[item.node - 1]
        if child.kind == 44 { return same_name(state, node.source, node.name_start, node.name_end, child.source, child.name_start, child.name_end) }
        link = item.next
    }
    var last = imp.name_start
    var at = imp.name_start
    let source = (state.sources)[imp.source]
    while at < imp.name_end {
        if text_byte(state, source, at) == 46 { last = at + 1 }
        at = at + 1
    }
    return same_name(state, node.source, node.name_start, node.name_end, imp.source, last, imp.name_end)
}

fn import_namespace_range_matches(state: State, parse: ParseStore, imp: SyntaxRec, source_id: U64, start: U64, end: U64) -> Bool {
    var link = imp.children
    while link != 0 {
        let item = (parse.links)[link - 1]
        let child = (parse.nodes)[item.node - 1]
        if child.kind == 44 { return same_name(state, source_id, start, end, child.source, child.name_start, child.name_end) }
        link = item.next
    }
    var last = imp.name_start
    var at = imp.name_start
    let source = (state.sources)[imp.source]
    while at < imp.name_end {
        if text_byte(state, source, at) == 46 { last = at + 1 }
        at = at + 1
    }
    return same_name(state, source_id, start, end, imp.source, last, imp.name_end)
}

fn symbol_named(state: State, parse: ParseStore, store: CheckStore, node: SyntaxRec) -> U64 {
    var module_source: U64 = 0
    var root_at: U64 = 0
    while root_at < (parse.roots).len() {
        let root = (parse.nodes)[(parse.roots)[root_at] - 1]
        if root.source == node.source && root.kind == 40 { module_source = node.source + 1 }
        root_at = root_at + 1
    }
    var at: U64 = 0
    while at < (store.symbols).len() {
        let symbol = (store.symbols)[at]
        if inherent_owner_node(parse, symbol.node) == 0 && same_name(state, node.source, node.name_start, node.name_end, symbol.source, symbol.name_start, symbol.name_end) && (module_source == 0 || symbol.module_source == module_source) { return at + 1 }
        at = at + 1
    }
    if module_source == 0 { return 0 }
    var qualifier_end: U64 = 0
    var member_start: U64 = 0
    let occurrence_source = (state.sources)[node.source]
    var name_at = node.name_start
    while name_at < node.name_end {
        if text_byte(state, occurrence_source, name_at) == 46 && qualifier_end == 0 {
            qualifier_end = name_at
            member_start = name_at + 1
        }
        name_at = name_at + 1
    }
    if node.kind == 29 && node.children != 0 {
        let base_link = (parse.links)[node.children - 1]
        let base = (parse.nodes)[base_link.node - 1]
        if base.kind == 24 {
            qualifier_end = base.name_end
            member_start = node.name_start
            name_at = base.name_start
        }
    } else { name_at = node.name_start }
    root_at = 0
    while root_at < (parse.roots).len() {
        let imp = (parse.nodes)[(parse.roots)[root_at] - 1]
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
        link = (parse.links)[link - 1].next
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
        link = (parse.links)[link - 1].next
        skip = skip - 1
    }
    return (parse.links)[link - 1]
}

fn inherent_symbol_named(state: State, parse: ParseStore, store: CheckStore, name: SyntaxRec, owner_target: U64, receiver: Bool) -> U64 {
    let owner_symbol = (store.symbols)[owner_target - 1]
    var at: U64 = 0
    while at < (store.symbols).len() {
        let symbol = (store.symbols)[at]
        let owner_id = inherent_owner_node(parse, symbol.node)
        if owner_id != 0 && same_name(state, name.source, name.name_start, name.name_end, symbol.source, symbol.name_start, symbol.name_end) {
            let owner = (parse.nodes)[owner_id - 1]
            if same_name(state, owner.source, owner.name_start, owner.name_end, owner_symbol.source, owner_symbol.name_start, owner_symbol.name_end) {
                var has_receiver = false
                if use_count(store, at + 1, 5) != 0 {
                    let first = (store.uses)[use_by_ordinal(store, at + 1, 5, 0) - 1]
                    let parameter = (parse.nodes)[first.node - 1]
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
    if node_word(state, node, "Map") { return CheckedTypeRec(kind: 11, syntax: 0, target: 0, first_arg: 0, arg_count: 2) }
    if node_word(state, node, "Ptr") { return CheckedTypeRec(kind: 12, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "__s0_Buffer") { return CheckedTypeRec(kind: 13, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "Vec") { return CheckedTypeRec(kind: 17, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    if node_word(state, node, "MutSlice") { return CheckedTypeRec(kind: 18, syntax: 0, target: 0, first_arg: 0, arg_count: 1) }
    let declared = find_declared_type(state, parse, store, node)
    if declared != 0 { return CheckedTypeRec(kind: 7, syntax: 0, target: declared, first_arg: 0, arg_count: (store.symbols)[declared - 1].type_arity) }
    return CheckedTypeRec(kind: 0, syntax: 0, target: 0, first_arg: 0, arg_count: 0)
}

fn expression_type_candidate(state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Bool {
    let node = (parse.nodes)[node_id - 1]
    if node.kind == 24 {
        if find_type_param(state, store, instance_declaration(store, owner), node) != 0 { return true }
        return expression_type_head(state, parse, store, node).kind != 0
    }
    if node.kind != 27 { return false }
    let callee_link = call_link_at(parse, node, 0)
    let callee = (parse.nodes)[callee_link.node - 1]
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

fn resolve_expression_type_args(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, call: SyntaxRec, ordinal: U64, count: U64, children: Vec(U64)) -> Result(SubstitutedChildrenRec, __s0_Error) {
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
    let next = try vec_appended(U64, children, checked_type_for_syntax(next_store, owner, link.node))
    return resolve_expression_type_args(d, state, parse, next_store, owner, call, ordinal + 1, count, next)
}

fn resolve_expression_type(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, node_id: U64) -> Result(CheckResult, __s0_Error) {
    let node = (parse.nodes)[node_id - 1]
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
    let callee = (parse.nodes)[callee_link.node - 1]
    if callee.kind != 24 { return check_token_fail(d, state, store, 56, node) }
    let head = expression_type_head(state, parse, store, callee)
    let count = call_link_count(parse, node) - 1
    if head.kind == 0 || count != head.arg_count { return check_token_fail(d, state, store, 56, node) }
    let empty = Vec.new(U64)
    let children = try resolve_expression_type_args(d, state, parse, store, owner, node, 0, count, empty)
    if (children.children).len() != count { return Ok(CheckBad(children.store)) }
    let existing = canonical_type_for_children(children.store, head.kind, head.target, children.children)
    if existing != 0 { return Ok(CheckGood(try annotate_checked_type(d, children.store, owner, node_id, existing))) }
    let first = (children.store.type_args).len() + 1
    let recorded = try append_substituted_children(d, children.store, children.children, 0)
    return Ok(CheckGood(try append_checked_type(d, recorded, owner, head.kind, node_id, head.target, first, count)))
}

fn checker_use_slot(owner: U64, role: U64) -> U64 {
    return (owner - 1) * 8 + role - 1
}

fn checker_use_index_available(store: CheckStore, owner: U64, role: U64) -> Bool {
    if owner == 0 || role == 0 || role > 8 { return false }
    if !store.indexes.complete {
        if owner > (store.symbols).len() { return false }
        let kind = (store.symbols)[owner - 1].kind
        if kind != 2 && kind != 3 { return false }
    }
    return checker_use_slot(owner, role) < (store.indexes.uses).len()
}

fn build_use_indexes(d: Domain, store: CheckStore, complete: Bool) -> Result(CheckStore, __s0_Error) {
    let symbol_count = (store.symbols).len()
    let use_count = (store.uses).len()
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
        let use = (store.uses)[at]
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
        let use = (store.uses)[at]
        if use.owner >= 1 && use.owner <= symbol_count && use.role >= 1 && use.role <= 8 {
            let use_slot = checker_use_slot(use.owner, use.role)
            ordered[starts[use_slot] + seen[use_slot]] = at + 1
            seen[use_slot] = seen[use_slot] + 1
        }
        at = at + 1
    }
    var use_indexes = Vec.new(CheckerUseIndexRec)
    slot = 0
    while slot < slot_count {
        var first: U64 = 0
        if counts[slot] != 0 { first = starts[slot] + 1 }
        try use_indexes.try_push(CheckerUseIndexRec(first: first, count: counts[slot]))
        slot = slot + 1
    }
    var use_order = Vec.new(U64)
    at = 0
    while at < use_count {
        try use_order.try_push(ordered[at])
        at = at + 1
    }
    let indexes = CheckerIndexes(uses: use_indexes, use_order: use_order, complete: complete)
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics))
}

fn use_by_ordinal(store: CheckStore, owner: U64, role: U64, ordinal: U64) -> U64 {
    if checker_use_index_available(store, owner, role) {
        let index = (store.indexes.uses)[checker_use_slot(owner, role)]
        if ordinal >= index.count { return 0 }
        return (store.indexes.use_order)[index.first - 1 + ordinal]
    }
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.owner == owner && use.role == role && use.ordinal == ordinal { return at + 1 }
        at = at + 1
    }
    return 0
}

fn use_count(store: CheckStore, owner: U64, role: U64) -> U64 {
    if checker_use_index_available(store, owner, role) {
        return (store.indexes.uses)[checker_use_slot(owner, role)].count
    }
    var count: U64 = 0
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.owner == owner && use.role == role { count = count + 1 }
        at = at + 1
    }
    return count
}

fn variant_named(state: State, store: CheckStore, enum_owner: U64, node: SyntaxRec) -> U64 {
    if checker_use_index_available(store, enum_owner, 2) {
        let index = (store.indexes.uses)[checker_use_slot(enum_owner, 2)]
        var ordinal: U64 = 0
        while ordinal < index.count {
            let use_id = (store.indexes.use_order)[index.first - 1 + ordinal]
            let use = (store.uses)[use_id - 1]
            if same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return use_id }
            ordinal = ordinal + 1
        }
        return 0
    }
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.owner == enum_owner && use.role == 2 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn any_variant_named(state: State, store: CheckStore, node: SyntaxRec) -> U64 {
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.role == 2 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn syntax_contains_call(parse: ParseStore, node_id: U64) -> Bool {
    let node = (parse.nodes)[node_id - 1]
    if node.kind == 27 || node.kind == 36 { return true }
    var link = node.children
    while link != 0 {
        let child = (parse.links)[link - 1]
        if syntax_contains_call(parse, child.node) { return true }
        link = child.next
    }
    return false
}

fn previous_expression_for_owner(store: CheckStore, owner: U64) -> U64 {
    var at = (store.expressions).len()
    while at != 0 {
        if (store.expressions)[at - 1].owner == owner { return at }
        at = at - 1
    }
    return 0
}

fn expression_for_syntax(store: CheckStore, owner: U64, syntax: U64) -> U64 {
    var at = previous_expression_for_owner(store, owner)
    var found: U64 = 0
    while at != 0 {
        let expression = (store.expressions)[at - 1]
        if expression.syntax == syntax { found = at }
        at = expression.owner_previous
    }
    return found
}

fn append_call_expression(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, syntax: U64, expression_kind: U64, checked_type: U64, annotation_kind: U64, target: U64, variant_use: U64, child_call: SyntaxRec, child_mode: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try vec_appended(CallAnnotationRec, store.call_annotations, CallAnnotationRec(owner: owner, kind: annotation_kind, target: target, checked_type: checked_type, variant_use: variant_use, builtin: 0))
    let annotation = (annotations).len()
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
                if child_count == 0 { first_child = (children).len() + 1 }
                try children.try_push(CheckedExprChildRec(expression: expression))
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
            let field = (store.uses)[field_id - 1]
            let named_id = record_source_arg(parse, child_call, field, state)
            let named = (parse.nodes)[named_id - 1]
            let value_link = (parse.links)[named.children - 1]
            if child_count == 0 { first_child = (children).len() + 1 }
            try children.try_push(CheckedExprChildRec(expression: expression_for_syntax(store, owner, value_link.node)))
            child_count = child_count + 1
            ordinal = ordinal + 1
        }
    }
    let expressions = try vec_appended(CheckedExprRec, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: expression_kind, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: annotation, first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, (expressions).len())
}

fn canonical_application(d: Domain, store: CheckStore, owner: U64, kind: U64, first_arg: U64, second_arg: U64, count: U64) -> Result(TypeValueRec, __s0_Error) {
    let empty = Vec.new(U64)
    var children = try vec_appended(U64, empty, first_arg)
    if count == 2 { try children.try_push(second_arg) }
    let existing = canonical_type_for_children(store, kind, 0, children)
    if existing != 0 { return Ok(TypeValueRec(store: store, checked_type: existing)) }
    let first = (store.type_args).len() + 1
    let recorded = try append_substituted_children(d, store, children, 0)
    let next = try append_checked_type(d, recorded, owner, kind, 0, 0, first, count)
    return Ok(TypeValueRec(store: next, checked_type: (next.types).len()))
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
    let annotations = try vec_appended(CallAnnotationRec, store.call_annotations, CallAnnotationRec(owner: owner, kind: 5, target: 0, checked_type: checked_type, variant_use: 0, builtin: builtin))
    var children = store.expression_children
    var first_child: U64 = 0
    var child_count: U64 = 0
    var ordinal = first_runtime
    while ordinal < call_link_count(parse, call) - 1 {
        let link = call_link_at(parse, call, ordinal + 1)
        let child = expression_for_syntax(store, owner, link.node)
        if child != 0 {
            if first_child == 0 { first_child = (children).len() + 1 }
            try children.try_push(CheckedExprChildRec(expression: child))
            child_count = child_count + 1
        }
        ordinal = ordinal + 1
    }
    let expressions = try vec_appended(CheckedExprRec, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 18, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: (annotations).len(), first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, (expressions).len())
}

// append_s0_error_expression records a payload-free S0 error constructor
// (OutOfMemory or Limit) as a kind-6 annotation with a kind-10 expression and
// no children. builtin is 5 for OutOfMemory and 6 for Limit.
fn append_s0_error_expression(d: Domain, parse: ParseStore, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, builtin: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try vec_appended(CallAnnotationRec, store.call_annotations, CallAnnotationRec(owner: owner, kind: 6, target: 0, checked_type: checked_type, variant_use: 0, builtin: builtin))
    let expressions = try vec_appended(CheckedExprRec, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 10, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: (annotations).len(), first_child: 0, child_count: 0, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, (expressions).len())
}

fn record_source_arg(parse: ParseStore, call: SyntaxRec, use: DeclTypeUseRec, state: State) -> U64 {
    var ordinal: U64 = 1
    let count = call_link_count(parse, call)
    while ordinal < count {
        let link = call_link_at(parse, call, ordinal)
        let arg = (parse.nodes)[link.node - 1]
        if arg.kind == 28 && same_name(state, arg.source, arg.name_start, arg.name_end, use.source, use.name_start, use.name_end) { return link.node }
        ordinal = ordinal + 1
    }
    return 0
}

fn check_call_argument_mode(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, arg: SyntaxRec, parameter: DeclTypeUseRec, expression_id: U64) -> Result(ExprOutcome, __s0_Error) {
    let parameter_node = (parse.nodes)[parameter.node - 1]
    if parameter_node.kind != 47 && parameter_node.kind != 48 { return expr_draft(store, 0, 0) }
    let empty = Vec.new(TypeBindingRec)
    let no_ancestry = Vec.new(DeclAncestryRec)
    let category = try interpreted_type_category(d, state, parse, store, empty, no_ancestry, parameter.checked_type, 0, 0)
    if parameter_node.kind == 47 && category.category == 1 && !node_word(state, parameter_node, "self") { return expr_token_fail(d, state, base, 89, arg) }
    if parameter_node.kind == 48 && category.category != 2 { return expr_token_fail(d, state, base, 90, arg) }
    let expression = (store.expressions)[expression_id - 1]
    if expression.kind != 1 && expression.kind != 5 { return expr_token_fail(d, state, base, 92, arg) }
    let binding = (store.locals)[expression.parameter_use - 1]
    var access = false
    if binding.kind == 2 { access = true } else {
        let declaration = (parse.nodes)[binding.syntax - 1]
        if parameter_node.kind == 47 && (declaration.kind == 47 || declaration.kind == 48) { access = true }
        if parameter_node.kind == 48 && declaration.kind == 48 { access = true }
    }
    if !access { return expr_token_fail(d, state, base, 92, arg) }
    var current = store
    if parameter_node.kind == 48 {
        var expressions = current.expressions
        expressions[expression_id - 1] = CheckedExprRec(owner: expression.owner, owner_previous: expression.owner_previous, syntax: expression.syntax, kind: 22, checked_type: expression.checked_type, parameter_use: expression.parameter_use, bool_value: expression.bool_value, left: expression.left, right: expression.right, annotation: expression.annotation, first_child: expression.first_child, child_count: expression.child_count, operator: expression.operator, site_kind: expression.site_kind, site_syntax: expression.site_syntax)
        current = check_with_expressions(current, expressions)
    }
    return expr_draft(current, 0, 0)
}

fn check_existing_call_modes(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, supplied: U64, ordinal: U64, count: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    let link = call_link_at(parse, call, supplied + ordinal + 1)
    let arg = (parse.nodes)[link.node - 1]
    let expression = expression_for_syntax(store, owner, link.node)
    if expression == 0 { return expr_deferred(base) }
    let parameter_id = use_by_ordinal(store, target, 7, ordinal)
    let parameter = (store.uses)[parameter_id - 1]
    if ordinal + 1 < count && call_argument_requires_final(store, parameter.checked_type, expression) { return expr_token_fail(d, state, base, 104, arg) }
    let checked = try check_call_argument_mode(d, state, parse, base, store, owner, arg, parameter, expression)
    var current = match checked {
        ExprGood(item) => item.store
        ExprBad(item) => item
    }
    if match checked {
        ExprGood(item) => false
        ExprBad(item) => true
    } { return Ok(ExprBad(current)) }
    return check_existing_call_modes(d, state, parse, base, current, owner, call, target, supplied, ordinal + 1, count)
}

fn check_positional_call_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, role: U64, ordinal: U64, count: U64, mismatch: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    let arg_link = call_link_at(parse, call, ordinal + 1)
    let arg = (parse.nodes)[arg_link.node - 1]
    if arg.kind == 28 { return expr_token_fail(d, state, base, mismatch, arg) }
    let parameter_id = use_by_ordinal(store, target, role, ordinal)
    let parameter = (store.uses)[parameter_id - 1]
    var argument_expected = parameter.checked_type
    if (store.types)[parameter.checked_type - 1].kind == 8 { argument_expected = 0 }
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

fn check_record_values(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, ordinal: U64, count: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == count { return expr_draft(store, 0, 0) }
    let field_id = use_by_ordinal(store, target, 1, ordinal)
    let field = (store.uses)[field_id - 1]
    let named_id = record_source_arg(parse, call, field, state)
    let named = (parse.nodes)[named_id - 1]
    let value_link = (parse.links)[named.children - 1]
    let value = (parse.nodes)[value_link.node - 1]
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

fn pattern_bound(store: CheckStore, pattern: U64, bindings: Vec(InferenceBindingRec)) -> Bool {
    let checked = (store.types)[pattern - 1]
    if checked.kind == 6 { return inference_lookup(bindings, checked.target) != 0 }
    var ordinal: U64 = 0
    while ordinal < checked.arg_count {
        if !pattern_bound(store, (store.type_args)[checked.first_arg - 1 + ordinal], bindings) { return false }
        ordinal = ordinal + 1
    }
    return true
}

fn infer_unary_variant_argument(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, arg: SyntaxRec, arg_id: U64, pattern: U64, bindings: Vec(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    let expected = (store.types)[pattern - 1]
    if expected.kind != 7 || (store.symbols)[expected.target - 1].kind != 3 || arg.kind != 27 || call_link_count(parse, arg) != 2 { return Ok(CallInferenceDefer) }
    let callee_link = call_link_at(parse, arg, 0)
    let callee = (parse.nodes)[callee_link.node - 1]
    if callee.kind != 24 { return Ok(CallInferenceDefer) }
    let variant_id = variant_named(state, store, expected.target, callee)
    if variant_id == 0 { return Ok(CallInferenceDefer) }
    let variant = (store.uses)[variant_id - 1]
    if variant.checked_type == 0 { return Ok(CallInferenceDefer) }
    let payload_link = call_link_at(parse, arg, 1)
    let payload_node = (parse.nodes)[payload_link.node - 1]
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
    let payload_category = try interpreted_type_category(d, state, parse, current, Vec.new(TypeBindingRec), Vec.new(DeclAncestryRec), draft.checked_type, 0, 0)
    if payload_category.contains_nonimmutable_scoped {
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

fn infer_call_arguments(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, runtime_start: U64, ordinal: U64, count: U64, bindings: Vec(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == count { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    let arg_link = call_link_at(parse, call, runtime_start + ordinal + 1)
    let arg = (parse.nodes)[arg_link.node - 1]
    if arg.kind == 28 {
        let failed = try check_token_fail(d, state, base, 42, arg)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let parameter_id = use_by_ordinal(store, target, 5, ordinal)
    let pattern = (store.uses)[parameter_id - 1].checked_type
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

fn explicit_function_bindings(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, declaration: U64, application: SyntaxRec, ordinal: U64, param_at: U64, bindings: Vec(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == (store.symbols)[declaration - 1].type_arity { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    var at = param_at
    while (store.type_params)[at].owner != declaration { at = at + 1 }
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
    let concrete = checked_type_for_syntax(current, owner, link.node)
    if !checked_type_concrete(current, concrete) {
        let failed = try check_token_fail(d, state, store, 57, application)
        return Ok(CallInferenceBad(match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }))
    }
    let next = try vec_appended(InferenceBindingRec, bindings, InferenceBindingRec(param: at + 1, checked_type: concrete))
    return explicit_function_bindings(d, state, parse, current, owner, declaration, application, ordinal + 1, at + 1, next)
}

fn check_explicit_function_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, supplied: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = (store.symbols)[target - 1]
    if supplied != symbol.type_arity { return expr_token_fail(d, state, base, 56, call) }
    let argument_count = call_link_count(parse, call) - 1 - supplied
    let parameter_count = use_count(store, target, 5)
    if argument_count != parameter_count { return expr_token_fail(d, state, base, 41, call) }
    let empty = Vec.new(InferenceBindingRec)
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
    let modes = try check_existing_call_modes(d, state, parse, base, with_instance, owner, call, instance_id, supplied, 0, argument_count)
    let checked_instance = match modes {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match modes {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(checked_instance)) }
    let result_id = use_by_ordinal(checked_instance, instance_id, 8, 0)
    let result_type = (checked_instance.uses)[result_id - 1].checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, checked_instance, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, checked_instance, owner, call_id, 8, result_type, 1, instance_id, 0, call, 1, site_kind, site_syntax)
}

fn infer_record_values(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, target: U64, ordinal: U64, count: U64, bindings: Vec(InferenceBindingRec)) -> Result(CallInferenceOutcome, __s0_Error) {
    if ordinal == count { return Ok(CallInferenceGood(CallInferenceRec(store: store, bindings: bindings))) }
    let field_id = use_by_ordinal(store, target, 1, ordinal)
    let field = (store.uses)[field_id - 1]
    let named_id = record_source_arg(parse, call, field, state)
    let named = (parse.nodes)[named_id - 1]
    let value_link = (parse.links)[named.children - 1]
    let value = (parse.nodes)[value_link.node - 1]
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

fn declaration_binding_children(d: Domain, store: CheckStore, target: U64, bindings: Vec(InferenceBindingRec), param_at: U64, children: Vec(U64)) -> Result(Vec(U64), __s0_Error) {
    if param_at == (store.type_params).len() { return Ok(children) }
    let param = (store.type_params)[param_at]
    var next = children
    if param.owner == target { next = try vec_appended(U64, children, inference_lookup(bindings, param_at + 1)) }
    return declaration_binding_children(d, store, target, bindings, param_at + 1, next)
}

fn concrete_decl_application(d: Domain, store: CheckStore, target: U64, bindings: Vec(InferenceBindingRec)) -> Result(TypeValueRec, __s0_Error) {
    let arity = (store.symbols)[target - 1].type_arity
    let empty = Vec.new(U64)
    let children = try declaration_binding_children(d, store, target, bindings, 0, empty)
    let existing = canonical_type_for_children(store, 7, target, children)
    if existing != 0 { return Ok(TypeValueRec(store: store, checked_type: existing)) }
    let first = (store.type_args).len() + 1
    let with_args = try append_substituted_children(d, store, children, 0)
    let next = try append_checked_type(d, with_args, 0, 7, 0, target, first, arity)
    return Ok(TypeValueRec(store: next, checked_type: canonical_type_id(next, 7, target, first, arity)))
}

fn bind_expected_application(d: Domain, store: CheckStore, target: U64, expected: CheckedTypeRec, param_at: U64, arg_at: U64, bindings: Vec(InferenceBindingRec)) -> Result(Vec(InferenceBindingRec), __s0_Error) {
    if param_at == (store.type_params).len() { return Ok(bindings) }
    let param = (store.type_params)[param_at]
    if param.owner == target {
        let next = try vec_appended(InferenceBindingRec, bindings, InferenceBindingRec(param: param_at + 1, checked_type: (store.type_args)[expected.first_arg - 1 + arg_at]))
        return bind_expected_application(d, store, target, expected, param_at + 1, arg_at + 1, next)
    }
    return bind_expected_application(d, store, target, expected, param_at + 1, arg_at, bindings)
}

fn check_record_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = (store.symbols)[target - 1]
    var ordinal: U64 = 1
    let link_count = call_link_count(parse, call)
    while ordinal < link_count {
        let link = call_link_at(parse, call, ordinal)
        let arg = (parse.nodes)[link.node - 1]
        if arg.kind != 28 { return expr_token_fail(d, state, base, 43, arg) }
        var field_use: U64 = 0
        var use_at: U64 = 0
        while use_at < (store.uses).len() {
            let use = (store.uses)[use_at]
            if use.owner == target && use.role == 1 && same_name(state, arg.source, arg.name_start, arg.name_end, use.source, use.name_start, use.name_end) { field_use = use_at + 1 }
            use_at = use_at + 1
        }
        if field_use == 0 { return expr_fail(d, base, 44, arg) }
        var prior_ordinal: U64 = 1
        while prior_ordinal < ordinal {
            let prior_link = call_link_at(parse, call, prior_ordinal)
            let prior = (parse.nodes)[prior_link.node - 1]
            if prior.kind == 28 && same_name(state, arg.source, arg.name_start, arg.name_end, prior.source, prior.name_start, prior.name_end) { return expr_fail(d, base, 45, arg) }
            prior_ordinal = prior_ordinal + 1
        }
        ordinal = ordinal + 1
    }
    let field_count = use_count(store, target, 1)
    ordinal = 0
    while ordinal < field_count {
        let field_id = use_by_ordinal(store, target, 1, ordinal)
        let field = (store.uses)[field_id - 1]
        if record_source_arg(parse, call, field, state) == 0 { return expr_token_fail(d, state, base, 46, call) }
        ordinal = ordinal + 1
    }
    if symbol.type_arity != 0 {
        let empty = Vec.new(InferenceBindingRec)
        var bindings = empty
        if expected != 0 {
            let expected_type = (store.types)[expected - 1]
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
        while param_at < (current.type_params).len() {
            let param = (current.type_params)[param_at]
            if param.owner == target && inference_lookup(bindings, param_at + 1) == 0 { return expr_token_fail(d, state, base, 57, call) }
            param_at = param_at + 1
        }
        let applied = try concrete_decl_application(d, current, target, bindings)
        let category = try interpreted_type_category(d, state, parse, applied.store, Vec.new(TypeBindingRec), Vec.new(DeclAncestryRec), applied.checked_type, 0, 0)
        if category.contains_nonimmutable_scoped { return expr_token_fail(d, state, base, 104, call) }
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
    let category = try interpreted_type_category(d, state, parse, current, Vec.new(TypeBindingRec), Vec.new(DeclAncestryRec), constructed, 0, 0)
    if category.contains_nonimmutable_scoped { return expr_token_fail(d, state, base, 104, call) }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, constructed, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, call_id, 9, constructed, 3, target, 0, call, 2, site_kind, site_syntax)
}

fn check_function_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, target: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let symbol = (store.symbols)[target - 1]
    let explicit_count = leading_type_arg_count(state, parse, store, owner, call)
    if explicit_count != 0 {
        if symbol.type_arity == 0 { return expr_token_fail(d, state, base, 56, call) }
        return check_explicit_function_call(d, state, parse, base, store, owner, call, call_id, target, explicit_count, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
    }
    let argument_count = call_link_count(parse, call) - 1
    let parameter_count = use_count(store, target, 5)
    if argument_count != parameter_count { return expr_token_fail(d, state, base, 41, call) }
    if symbol.type_arity != 0 {
        let empty = Vec.new(InferenceBindingRec)
        var bindings = empty
        if expected != 0 {
            let result_id = use_by_ordinal(store, target, 6, 0)
            let result_pattern = (store.uses)[result_id - 1].checked_type
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
        let modes = try check_existing_call_modes(d, state, parse, base, with_instance, owner, call, instance_id, 0, 0, argument_count)
        let checked_instance = match modes {
            ExprGood(value) => value.store
            ExprBad(value) => value
        }
        if match modes {
            ExprGood(value) => false
            ExprBad(value) => true
        } { return Ok(ExprBad(checked_instance)) }
        let concrete_result_id = use_by_ordinal(checked_instance, instance_id, 8, 0)
        let concrete_result = (checked_instance.uses)[concrete_result_id - 1].checked_type
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
    let result_type = (current.uses)[result_id - 1].checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, call_id, 8, result_type, 1, target, 0, call, 1, site_kind, site_syntax)
}

fn check_variant_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if expected == 0 {
        let any = any_variant_named(state, store, callee)
        if any == 0 { return expr_fail(d, base, 40, callee) }
        let variant = (store.uses)[any - 1]
        if (store.symbols)[variant.owner - 1].type_arity != 0 { return expr_deferred(base) }
        return expr_fail(d, base, 40, callee)
    }
    let checked = (store.types)[expected - 1]
    if checked.kind != 7 { return expr_fail(d, base, 40, callee) }
    let enum_symbol = (store.symbols)[checked.target - 1]
    if enum_symbol.kind != 3 { return expr_fail(d, base, 40, callee) }
    let variant_id = variant_named(state, store, checked.target, callee)
    if variant_id == 0 { return expr_fail(d, base, 40, callee) }
    let variant = (store.uses)[variant_id - 1]
    if variant.checked_type == 0 { return expr_token_fail(d, state, base, 48, call) }
    if call_link_count(parse, call) != 2 { return expr_token_fail(d, state, base, 49, call) }
    let arg_link = call_link_at(parse, call, 1)
    let arg = (parse.nodes)[arg_link.node - 1]
    if arg.kind == 28 { return expr_token_fail(d, state, base, 50, arg) }
    var payload_store = store
    var payload_type = variant.checked_type
    if enum_symbol.type_arity != 0 {
        let empty = Vec.new(InferenceBindingRec)
        let bindings = try bind_expected_application(d, store, checked.target, checked, 0, 0, empty)
        let concrete = try substitute_type(d, store, bindings, variant.checked_type)
        payload_store = concrete.store
        payload_type = concrete.checked_type
    }
    let payload_category = try interpreted_type_category(d, state, parse, payload_store, Vec.new(TypeBindingRec), Vec.new(DeclAncestryRec), payload_type, 0, 0)
    if payload_category.contains_nonimmutable_scoped { return expr_token_fail(d, state, base, 104, arg) }
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

fn check_slice_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    var identity: U64 = 1
    var arity: U64 = 1
    if node_word(state, callee, "range") { identity = 2
        arity = 3 }
    if call_link_count(parse, call) != arity + 1 { return expr_token_fail(d, state, base, 41, call) }
    let sequence_link = call_link_at(parse, call, 1)
    let sequence_node = (parse.nodes)[sequence_link.node - 1]
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
        let first_node = (parse.nodes)[first_link.node - 1]
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
        let second_node = (parse.nodes)[second_link.node - 1]
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
    let empty = Vec.new(TypeBindingRec)
    let no_ancestry = Vec.new(DeclAncestryRec)
    let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, element, 0, 0)
    if category.category != 1 && !(category.category == 3 && !category.contains_nonimmutable_scoped) { return expr_token_single_type_fail(d, state, current, 100, (parse.nodes)[type_link.node - 1], element) }
    let vector = try canonical_application(d, current, owner, 17, element, 0, 1)
    current = vector.store
    if identity == 19 {
        let value_link = call_link_at(parse, call, 2)
        let value_node = (parse.nodes)[value_link.node - 1]
        var wanted_array: U64 = 0
        if value_node.kind == 50 {
            let count = type_arg_count(parse, value_node.children)
            wanted_array = canonical_single_arg(current, 15, count, element)
            if wanted_array == 0 {
                let first = (current.type_args).len() + 1
                let args = try vec_appended(U64, current.type_args, element)
                current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
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
        let array = (current.types)[actual - 1]
        if array.kind != 15 || array.arg_count != 1 || !(try expression_type_equal(d, state, parse, current, element, (current.type_args)[array.first_arg - 1])) { return expr_token_fail(d, state, base, 42, value_node) }
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, vector.checked_type, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, vector.checked_type) }
    return append_builtin_expression(d, parse, current, owner, call_id, vector.checked_type, identity, call, 1, site_kind, site_syntax)
}

fn check_bytes_static_builtin(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if call_link_count(parse, call) != 2 { return expr_token_fail(d, state, base, 41, call) }
    let u8_type = primitive_type_id(state, parse, store, "U8")
    let vector = try canonical_application(d, store, owner, 17, u8_type, 0, 1)
    let value_link = call_link_at(parse, call, 1)
    let value_node = (parse.nodes)[value_link.node - 1]
    let checked = try check_value_expression_inner(d, state, parse, base, vector.store, owner, value_node, value_link.node, vector.checked_type, 42, value_node, 0, 0)
    var current = match checked {
        ExprGood(value) => value.store
        ExprBad(value) => value
    }
    if match checked {
        ExprGood(value) => false
        ExprBad(value) => true
    } { return Ok(ExprBad(current)) }
    let bytes = try canonical_leaf(d, current, 14, 0)
    let capacity = try canonical_leaf(d, bytes.store, 19, 0)
    let result = try canonical_application(d, capacity.store, owner, 10, bytes.checked_type, capacity.checked_type, 2)
    current = result.store
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result.checked_type, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, result.checked_type) }
    return append_builtin_expression(d, parse, current, owner, call_id, result.checked_type, 28, call, 0, site_kind, site_syntax)
}

fn append_sequence_method(d: Domain, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, builtin: U64, receiver: U64, first_arg: U64, second_arg: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let annotations = try vec_appended(CallAnnotationRec, store.call_annotations, CallAnnotationRec(owner: owner, kind: 5, target: 0, checked_type: checked_type, variant_use: 0, builtin: builtin))
    var children = store.expression_children
    let first = (children).len() + 1
    try children.try_push(CheckedExprChildRec(expression: receiver))
    var count: U64 = 1
    if first_arg != 0 { try children.try_push(CheckedExprChildRec(expression: first_arg))
        count = count + 1 }
    if second_arg != 0 { try children.try_push(CheckedExprChildRec(expression: second_arg))
        count = count + 1 }
    let expressions = try vec_appended(CheckedExprRec, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 18, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: (annotations).len(), first_child: first, child_count: count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: annotations, expression_children: children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, (expressions).len())
}

// Return the mutable local root of an identifier or static field-projection
// chain. Indexed, dereferenced, temporary, and parameter roots are excluded.
fn sequence_mutable_root(state: State, parse: ParseStore, store: CheckStore, owner: U64, receiver0: SyntaxRec) -> U64 {
    var receiver = receiver0
    while receiver.kind == 29 && receiver.children != 0 {
        let base_link = (parse.links)[receiver.children - 1]
        receiver = (parse.nodes)[base_link.node - 1]
    }
    if receiver.kind != 24 { return 0 }
    let local_id = local_lookup(store, owner, receiver, state)
    if local_id == 0 { return 0 }
    let local = (store.locals)[local_id - 1]
    if local.kind != 2 || local.mutable == 0 { return 0 }
    return local_id
}

fn check_sequence_method(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, callee: SyntaxRec, receiver_node: SyntaxRec, receiver_type_id: U64, receiver_expression: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let sequence = (store.types)[receiver_type_id - 1]
    if sequence.kind != 2 && sequence.kind != 8 && sequence.kind != 14 && sequence.kind != 15 && sequence.kind != 17 && sequence.kind != 18 { return expr_token_fail(d, state, base, 61, callee) }
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
    if node_word(state, callee, "try_reserve") { builtin = 26
        arity = 1 }
    if node_word(state, callee, "try_push") { builtin = 27
        arity = 1 }
    if node_word(state, callee, "as_slice") { builtin = 29 }
    if node_word(state, callee, "as_bytes") { builtin = 30 }
    // Method-call links include both the selected callee and its receiver.
    if builtin == 0 || call_link_count(parse, call) != arity + 2 { return expr_token_fail(d, state, base, 41, call) }
    if (builtin == 21 || builtin == 26 || builtin == 27) && sequence.kind != 17 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 23 && sequence.kind == 18 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 24 && sequence.kind != 15 && sequence.kind != 17 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 25 && sequence.kind != 18 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 29 && sequence.kind != 14 { return expr_token_fail(d, state, base, 61, callee) }
    if builtin == 30 && sequence.kind != 2 { return expr_token_fail(d, state, base, 61, callee) }
    if (sequence.kind == 2 || sequence.kind == 14) && builtin != 29 && builtin != 30 { return expr_token_fail(d, state, base, 61, callee) }
    let mutable_root = sequence_mutable_root(state, parse, store, owner, receiver_node)
    if builtin == 21 || builtin == 24 || builtin == 26 || builtin == 27 {
        if mutable_root == 0 { return expr_token_fail(d, state, base, 101, receiver_node) }
    }
    if mutable_root != 0 {
        var mode: U64 = 1
        if builtin == 21 || builtin == 26 || builtin == 27 { mode = 2 }
        if builtin == 23 { mode = 3 }
        if builtin == 24 || builtin == 25 { mode = 4 }
        if builtin == 29 || builtin == 30 { mode = 3 }
        if lexical_access_conflict(store, owner, mutable_root, mode) { return expr_token_fail(d, state, base, 92, receiver_node) }
    }
    var element = sequence_element_type(state, parse, store, receiver_type_id)
    if sequence.kind == 2 || sequence.kind == 14 { element = primitive_type_id(state, parse, store, "U8") }
    let u64_type = primitive_type_id(state, parse, store, "U64")
    var current = store
    var first_expression: U64 = 0
    var second_expression: U64 = 0
    if arity != 0 {
        let link = call_link_at(parse, call, 2)
        let argument = (parse.nodes)[link.node - 1]
        var wanted = u64_type
        if builtin == 21 || builtin == 27 { wanted = element }
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
    }
    if arity == 2 {
        let link = call_link_at(parse, call, 3)
        let argument = (parse.nodes)[link.node - 1]
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
    if builtin == 29 || builtin == 30 { let made = try canonical_application(d, current, owner, 8, element, 0, 1)
        current = made.store
        result = made.checked_type }
    if builtin == 26 || builtin == 27 {
        let capacity = try canonical_leaf(d, current, 19, 0)
        let unit = try canonical_leaf(d, capacity.store, 1, 12)
        let made = try canonical_application(d, unit.store, owner, 10, unit.checked_type, capacity.checked_type, 2)
        current = made.store
        result = made.checked_type
    }
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result, expected)) { return expr_token_type_fail(d, state, current, mismatch_kind, mismatch_node, expected, result) }
    return append_sequence_method(d, current, owner, call_id, result, builtin, receiver_expression, first_expression, second_expression, site_kind, site_syntax)
}

fn check_map_runtime_args(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, call: SyntaxRec, call_id: U64, identity: U64, ordinal: U64, first_runtime: U64, runtime_count: U64, map_type: U64, key: U64, value: U64, result: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if ordinal == runtime_count {
        if expected != 0 && !(try expression_type_equal(d, state, parse, store, result, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_builtin_expression(d, parse, store, owner, call_id, result, identity, call, first_runtime, site_kind, site_syntax)
    }
    let link = call_link_at(parse, call, first_runtime + ordinal + 1)
    let argument = (parse.nodes)[link.node - 1]
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
    let map_node = (parse.nodes)[map_link.node - 1]
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
    let map_checked = (current.types)[map_draft.checked_type - 1]
    if map_checked.kind != 11 { return expr_token_fail(d, state, base, 42, map_node) }
    let inferred_key = (current.type_args)[map_checked.first_arg - 1]
    let inferred_value = (current.type_args)[map_checked.first_arg]
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
    let argument = (parse.nodes)[link.node - 1]
    var wanted = domain_type
    if identity == 3 && ordinal == 2 { wanted = u64_type }
    if identity == 6 && ordinal == 1 { wanted = mark_type }
    if (identity == 10 || identity == 12 || identity == 13 || identity == 17) && ordinal == 1 { wanted = buffer_type }
    if identity == 11 && ordinal == 2 { wanted = buffer_type }
    if identity == 11 && ordinal == 3 { wanted = element }
    if (identity == 12 || identity == 17) && ordinal == 2 { wanted = u64_type }
    if identity == 17 && ordinal == 3 { wanted = element }
    let checked = try check_value_expression_inner(d, state, parse, base, store, owner, argument, link.node, wanted, 42, argument, 0, 0)
    var current = match checked {
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
        let consumed = (current.expressions)[draft.expression - 1]
        if consumed.kind != 1 && consumed.kind != 5 { return expr_token_fail(d, state, base, 92, argument) }
        let binding = (current.locals)[consumed.parameter_use - 1]
        var owned = binding.kind == 2
        if binding.kind == 1 && (parse.nodes)[binding.syntax - 1].kind == 48 { owned = true }
        if !owned { return expr_token_fail(d, state, base, 92, argument) }
        var expressions = current.expressions
        expressions[draft.expression - 1] = CheckedExprRec(owner: consumed.owner, owner_previous: consumed.owner_previous, syntax: consumed.syntax, kind: 22, checked_type: consumed.checked_type, parameter_use: consumed.parameter_use, bool_value: consumed.bool_value, left: consumed.left, right: consumed.right, annotation: consumed.annotation, first_child: consumed.first_child, child_count: consumed.child_count, operator: consumed.operator, site_kind: consumed.site_kind, site_syntax: consumed.site_syntax)
        current = check_with_expressions(current, expressions)
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
        if identity == 8 && (current.types)[element - 1].kind != 11 {
            let type_node = (parse.nodes)[type_link.node - 1]
            return expr_token_fail(d, state, base, 42, type_node)
        }
        let empty_bindings = Vec.new(TypeBindingRec)
        let empty_ancestry = Vec.new(DeclAncestryRec)
        if identity == 8 {
            let map_type = (current.types)[element - 1]
            let key = (current.type_args)[map_type.first_arg - 1]
            let value = (current.type_args)[map_type.first_arg]
            let type_node = (parse.nodes)[type_link.node - 1]
            if !(try interpreted_map_key_ok(d, state, parse, current, empty_bindings, empty_ancestry, key, 0, 0, (current.symbols).len())) { return expr_token_single_type_fail(d, state, current, 12, type_node, key) }
            if try interpreted_contains_reference(d, state, parse, current, empty_bindings, empty_ancestry, value, 0, 0, (current.symbols).len()) { return expr_token_single_type_fail(d, state, current, 13, type_node, value) }
        }
        if identity != 8 && try interpreted_contains_reference(d, state, parse, current, empty_bindings, empty_ancestry, element, 0, 0, 0) {
            let type_node = (parse.nodes)[type_link.node - 1]
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
    let callee = (parse.nodes)[callee_link.node - 1]
    if callee.kind != 24 && callee.kind != 29 {
        if callee.kind == 27 {
            let applied_callee_link = call_link_at(parse, callee, 0)
            let applied_callee = (parse.nodes)[applied_callee_link.node - 1]
            if applied_callee.kind != 24 { return expr_token_fail(d, state, base, 40, call) }
            let applied_target = symbol_named(state, parse, store, applied_callee)
            if applied_target == 0 { return expr_token_fail(d, state, base, 40, call) }
            let applied_symbol = (store.symbols)[applied_target - 1]
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
        let static_link = (parse.links)[callee.children - 1]
        let static_node = (parse.nodes)[static_link.node - 1]
        if static_node.kind == 24 && node_word(state, static_node, "Vec") { return check_vec_static_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    }
    if callee.kind == 29 && node_word(state, callee, "try_from_vec") {
        let static_link = (parse.links)[callee.children - 1]
        let static_node = (parse.nodes)[static_link.node - 1]
        if static_node.kind == 24 && node_word(state, static_node, "Bytes") { return check_bytes_static_builtin(d, state, parse, base, store, owner, call, call_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    }
    if callee.kind == 29 && symbol_named(state, parse, store, callee) == 0 {
        let receiver_link = (parse.links)[callee.children - 1]
        let receiver_node = (parse.nodes)[receiver_link.node - 1]
        let static_owner = symbol_named(state, parse, store, receiver_node)
        if static_owner != 0 {
            let static_symbol = (store.symbols)[static_owner - 1]
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
        let receiver_type = (current.types)[receiver_draft.checked_type - 1]
        if node_word(state, callee, "len") || node_word(state, callee, "push") || node_word(state, callee, "get") || node_word(state, callee, "slice") || node_word(state, callee, "slice_mut") || node_word(state, callee, "subview") || node_word(state, callee, "try_reserve") || node_word(state, callee, "try_push") || node_word(state, callee, "as_slice") || node_word(state, callee, "as_bytes") {
            return check_sequence_method(d, state, parse, base, current, owner, call, call_id, callee, receiver_node, receiver_draft.checked_type, receiver_draft.expression, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
        }
        if receiver_type.kind != 7 { return expr_token_fail(d, state, base, 61, callee) }
        let target = inherent_symbol_named(state, parse, current, callee, receiver_type.target, true)
        if target == 0 { return expr_token_fail(d, state, base, 61, callee) }
        return check_function_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
    }
    if callee.kind == 24 && (node_word(state, callee, "len") || node_word(state, callee, "range")) { return check_slice_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if node_word(state, callee, "Get") || node_word(state, callee, "Set") || node_word(state, callee, "Remove") { return check_map_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if node_word(state, callee, "__s0_alloc") || node_word(state, callee, "__s0_domain_create") || node_word(state, callee, "__s0_domain_mark") || node_word(state, callee, "__s0_domain_reset") || node_word(state, callee, "__s0_domain_destroy") || node_word(state, callee, "__s0_map_create") || node_word(state, callee, "__s0_buffer_new") || node_word(state, callee, "__s0_buffer_len") || node_word(state, callee, "__s0_buffer_append") || node_word(state, callee, "__s0_buffer_get") || node_word(state, callee, "__s0_buffer_set") || node_word(state, callee, "__s0_buffer_slice") { return check_s0_builtin(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if node_word(state, callee, "Some") || node_word(state, callee, "Ok") || node_word(state, callee, "Err") {
        if expected == 0 { return expr_token_fail(d, state, base, 40, call) }
        let concrete = (store.types)[expected - 1]
        if concrete.kind != 9 && concrete.kind != 10 { return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if call_link_count(parse, call) != 2 { return expr_token_fail(d, state, base, 49, call) }
        var kind: U64 = 0
        var payload_type: U64 = 0
        if concrete.kind == 9 && node_word(state, callee, "Some") {
            kind = 15
            payload_type = (store.type_args)[concrete.first_arg - 1]
        }
        if concrete.kind == 10 && node_word(state, callee, "Ok") {
            kind = 16
            payload_type = (store.type_args)[concrete.first_arg - 1]
        }
        if concrete.kind == 10 && node_word(state, callee, "Err") {
            kind = 17
            payload_type = (store.type_args)[concrete.first_arg]
        }
        if kind == 0 { return expr_token_fail(d, state, base, 40, call) }
        let payload_category = try interpreted_type_category(d, state, parse, store, Vec.new(TypeBindingRec), Vec.new(DeclAncestryRec), payload_type, 0, 0)
        if payload_category.contains_nonimmutable_scoped { return expr_token_fail(d, state, base, 104, call) }
        let argument_link = call_link_at(parse, call, 1)
        let argument = (parse.nodes)[argument_link.node - 1]
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
        return append_expression(d, current, owner, call_id, kind, expected, 0, 0, draft.expression, 0, 0, site_kind, site_syntax)
    }
    let target = symbol_named(state, parse, store, callee)
    if target != 0 {
        let symbol = (store.symbols)[target - 1]
        if symbol.kind == 12 { return check_function_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if symbol.kind == 1 { return expr_fail(d, base, 51, callee) }
        if symbol.kind == 2 { return check_record_call(d, state, parse, base, store, owner, call, call_id, target, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
        if symbol.kind == 3 && symbol.type_arity != 0 { return expr_deferred(base) }
        return expr_fail(d, base, 40, callee)
    }
    if expected != 0 {
        let expected_type = (store.types)[expected - 1]
        if expected_type.kind == 7 && (store.symbols)[expected_type.target - 1].kind == 3 {
            return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
        }
    }
    if any_variant_named(state, store, callee) != 0 { return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if reserved_symbol(state, callee) { return expr_deferred(base) }
    return check_variant_call(d, state, parse, base, store, owner, call, call_id, callee, expected, mismatch_kind, mismatch_node, site_kind, site_syntax)
}

fn check_unsafe_call(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, unsafe_node: SyntaxRec, unsafe_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let root_link = (parse.links)[unsafe_node.children - 1]
    let call = (parse.nodes)[root_link.node - 1]
    let callee_link = call_link_at(parse, call, 0)
    let callee = (parse.nodes)[callee_link.node - 1]
    if callee.kind != 24 { return expr_token_fail(d, state, base, 52, unsafe_node) }
    let target = symbol_named(state, parse, store, callee)
    if target == 0 || (store.symbols)[target - 1].kind != 1 { return expr_token_fail(d, state, base, 52, unsafe_node) }
    let argument_count = call_link_count(parse, call) - 1
    var ordinal: U64 = 0
    while ordinal < argument_count {
        let arg_link = call_link_at(parse, call, ordinal + 1)
        if syntax_contains_call(parse, arg_link.node) {
            let arg = (parse.nodes)[arg_link.node - 1]
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
    let result_type = (current.uses)[result_id - 1].checked_type
    if expected != 0 && !(try expression_type_equal(d, state, parse, current, result_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
    return append_call_expression(d, state, parse, current, owner, unsafe_id, 11, result_type, 2, target, 0, call, 1, site_kind, site_syntax)
}

fn check_array_elements(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, link_id: U64, element_type: U64, array_node: SyntaxRec) -> Result(ArrayElementsOutcome, __s0_Error) {
    if link_id == 0 { return Ok(ArrayElementsGood(ArrayElementsRec(store: store, element_type: element_type, first_child: 0, child_count: 0))) }
    let link = (parse.links)[link_id - 1]
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
    let node = (parse.nodes)[link.node - 1]
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
    var actual_element = prior.element_type
    if actual_element == 0 { actual_element = draft.checked_type }
    var first = prior.first_child
    if prior.child_count == 0 { first = (current.expression_children).len() + 1 }
    let children = try vec_appended(CheckedExprChildRec, current.expression_children, CheckedExprChildRec(expression: draft.expression))
    let next = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
    return Ok(ArrayElementsGood(ArrayElementsRec(store: next, element_type: actual_element, first_child: first, child_count: prior.child_count + 1)))
}

fn append_array_expression(d: Domain, store: CheckStore, owner: U64, syntax: U64, checked_type: U64, first_child: U64, child_count: U64, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    let expressions = try vec_appended(CheckedExprRec, store.expressions, CheckedExprRec(owner: owner, owner_previous: previous_expression_for_owner(store, owner), syntax: syntax, kind: 23, checked_type: checked_type, parameter_use: 0, bool_value: 0, left: 0, right: 0, annotation: 0, first_child: first_child, child_count: child_count, operator: 0, site_kind: site_kind, site_syntax: site_syntax))
    let next = CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics)
    return expr_draft(next, checked_type, (expressions).len())
}

// Shared recursive value-expression slice for returns, binding initializers,
// and assignment values. The base store is retained across the whole traversal
// so a deferred shape or semantic failure cannot expose a partial graph.
fn check_value_expression_inner(d: Domain, state: State, parse: ParseStore, base: CheckStore, store: CheckStore, owner: U64, expression: SyntaxRec, expression_id: U64, expected: U64, mismatch_kind: U64, mismatch_node: SyntaxRec, site_kind: U64, site_syntax: U64) -> Result(ExprOutcome, __s0_Error) {
    if expression.kind == 27 { return check_ordinary_call(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 36 { return check_unsafe_call(d, state, parse, base, store, owner, expression, expression_id, expected, mismatch_kind, mismatch_node, site_kind, site_syntax) }
    if expression.kind == 50 {
        let count = type_arg_count(parse, expression.children)
        var array_type = expected
        var element_type: U64 = 0
        if expected != 0 {
            let checked = (store.types)[expected - 1]
            if checked.kind != 15 || checked.arg_count != 1 { return expr_token_fail(d, state, base, 97, expression) }
            if checked.target != count { return expr_token_fail(d, state, base, 98, expression) }
            element_type = (store.type_args)[checked.first_arg - 1]
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
        let element_category = try interpreted_type_category(d, state, parse, values.store, Vec.new(TypeBindingRec), Vec.new(DeclAncestryRec), values.element_type, 0, 0)
        if element_category.contains_nonimmutable_scoped { return expr_token_fail(d, state, base, 104, expression) }
        var current = values.store
        if array_type == 0 {
            array_type = canonical_single_arg(current, 15, count, values.element_type)
            if array_type == 0 {
                let first = (current.type_args).len() + 1
                let args = try vec_appended(U64, current.type_args, values.element_type)
                current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
                current = try append_checked_type(d, current, 0, 15, 0, count, first, 1)
                array_type = canonical_single_arg(current, 15, count, values.element_type)
            }
        }
        return append_array_expression(d, current, owner, expression_id, array_type, values.first_child, values.child_count, site_kind, site_syntax)
    }
    if expression.kind == 29 {
        let base_link = (parse.links)[expression.children - 1]
        let base_node = (parse.nodes)[base_link.node - 1]
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
        let aggregate = (current.types)[base_draft.checked_type - 1]
        if aggregate.kind != 7 || (current.symbols)[aggregate.target - 1].kind != 2 { return expr_fail(d, base, 60, expression) }
        let field = field_use_named(state, current, aggregate.target, expression)
        if field == 0 { return expr_fail(d, base, 61, expression) }
        let concrete = try concrete_field_type(d, current, base_draft.checked_type, field)
        if expected != 0 && !(try expression_type_equal(d, state, parse, concrete.store, concrete.checked_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, concrete.store, owner, expression_id, 21, concrete.checked_type, field, 0, base_draft.expression, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 30 {
        let index_link = (parse.links)[expression.children - 1]
        let base_link = (parse.links)[index_link.next - 1]
        let base_node = (parse.nodes)[base_link.node - 1]
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
        let index_node = (parse.nodes)[index_link.node - 1]
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
        let limits = int_result_range(state, parse, (store.types)[literal_type - 1])
        if !limits.integer { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        let token = (state.tokens)[expression.token - 1]
        var negative = false
        var magnitude = token.value_start
        if token.value_end > token.value_start && (state.values)[token.value_start] == 45 {
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
        let expected_type = (string_store.types)[string_type - 1]
        if expected_type.kind != 2 && expected_type.kind != 14 && expected_type.kind != 16 {
            let want = diagnostic_type(string_store, expected)
            let failed = try check_token_detail_fail(d, state, base, mismatch_kind, mismatch_node, want.kind, want.target, 2, 0)
            let bad = match failed {
                CheckGood(value) => value
                CheckBad(value) => value
            }
            return Ok(ExprBad(bad))
        }
        let token = (state.tokens)[expression.token - 1]
        if expected_type.kind == 2 && !checker_utf8_valid(state.values, token.value_start, token.value_end) { return expr_token_fail(d, state, base, 99, expression) }
        return append_expression(d, string_store, owner, expression_id, 4, string_type, 0, 0, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 23 {
        var bool_type = expected
        if expected != 0 && !primitive_type_named(state, parse, store, expected, "Bool") { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        if bool_type == 0 { bool_type = primitive_type_id(state, parse, store, "Bool") }
        if bool_type == 0 { return expr_deferred(base) }
        let token = (state.tokens)[expression.token - 1]
        var bool_value: U64 = 0
        if token.keyword == 17 { bool_value = 1 }
        else { if token.keyword != 18 { return expr_deferred(base) } }
        return append_expression(d, store, owner, expression_id, 2, bool_type, 0, bool_value, 0, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 24 {
        let local_id = local_lookup(store, owner, expression, state)
        if local_id == 0 && expected != 0 && node_word(state, expression, "None") {
            let concrete = (store.types)[expected - 1]
            if concrete.kind != 9 { return expr_fail(d, base, 40, expression) }
            return append_expression(d, store, owner, expression_id, 14, expected, 0, 0, 0, 0, 0, site_kind, site_syntax)
        }
        if local_id == 0 && expected != 0 {
            let expected_type = (store.types)[expected - 1]
            if expected_type.kind == 7 {
                let expected_symbol = (store.symbols)[expected_type.target - 1]
                if expected_symbol.kind == 3 {
                    let variant_id = variant_named(state, store, expected_type.target, expression)
                    if variant_id == 0 { return expr_fail(d, base, 40, expression) }
                    let variant = (store.uses)[variant_id - 1]
                    if variant.checked_type != 0 { return expr_fail(d, base, 47, expression) }
                    return append_call_expression(d, state, parse, store, owner, expression_id, 10, expected, 4, expected_type.target, variant_id, expression, 0, site_kind, site_syntax)
                }
            }
        }
        if local_id == 0 && expected != 0 && (node_word(state, expression, "OutOfMemory") || node_word(state, expression, "Limit")) && ((store.types)[expected - 1].kind == 5 || (store.types)[expected - 1].kind == 19) {
            var builtin: U64 = 5
            if node_word(state, expression, "Limit") { builtin = 6 }
            return append_s0_error_expression(d, parse, store, owner, expression_id, expected, builtin, site_kind, site_syntax)
        }
        var kind: U64 = 5
        var reference = local_id
        var binding_type: U64 = 0
        if local_id != 0 {
            let binding = (store.locals)[local_id - 1]
            binding_type = binding.checked_type
            if binding.kind == 1 { kind = 1 }
        } else {
            let target = symbol_named(state, parse, store, expression)
            if target != 0 && (store.symbols)[target - 1].kind == 12 { return expr_fail(d, base, 39, expression) }
            let any_variant = any_variant_named(state, store, expression)
            if any_variant != 0 {
                let variant = (store.uses)[any_variant - 1]
                if (store.symbols)[variant.owner - 1].type_arity != 0 { return expr_deferred(base) }
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
        let child_link = (parse.links)[expression.children - 1]
        let child = (parse.nodes)[child_link.node - 1]
        var child_expected: U64 = 0
        if operator == 1 {
            if (child.kind == 20 || child.kind == 25) && expected != 0 && int_result_range(state, parse, (store.types)[expected - 1]).integer { child_expected = expected }
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
            let limits = int_result_range(state, parse, (child_store.types)[child_draft.checked_type - 1])
            if limits.integer && !limits.signed { return expr_token_fail(d, state, base, 30, expression) }
            if !limits.integer { return expr_token_fail(d, state, base, 31, expression) }
        }
        if expected != 0 && !(try expression_type_equal(d, state, parse, child_store, child_draft.checked_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        return append_expression(d, child_store, owner, expression_id, 6, child_draft.checked_type, 0, 0, child_draft.expression, 0, operator, site_kind, site_syntax)
    }
    if expression.kind == 37 {
        let arm_head = (parse.links)[expression.children - 1]
        var scrutinee_link = arm_head
        while scrutinee_link.next != 0 { scrutinee_link = (parse.links)[scrutinee_link.next - 1] }
        let scrutinee_node = (parse.nodes)[scrutinee_link.node - 1]
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
        let scrutinee_type = (current.types)[scrutinee.checked_type - 1]
        if scrutinee_type.kind != 5 && scrutinee_type.kind != 7 && scrutinee_type.kind != 9 && scrutinee_type.kind != 10 && scrutinee_type.kind != 19 { return expr_token_fail(d, state, base, 70, expression) }
        if arm_head.next == 0 { return expr_token_fail(d, state, base, 78, expression) }
        let drafts = Vec.new(MatchArmDraftRec)
        let checked_arms = try check_match_arm_links(d, state, parse, base, current, owner, expression.children, scrutinee.checked_type, expected, drafts, expression)
        let arms = match checked_arms {
            MatchArmsGood(value) => value
            MatchArmsBad(value) => MatchArmValueRec(store: value, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, arms: drafts)
            MatchArmsDefer => MatchArmValueRec(store: current, arm_type: 0, first_arm: 0, arm_count: 0, wildcard: false, arms: drafts)
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
                while use_at < (arms.store.uses).len() {
                    let use = (arms.store.uses)[use_at]
                    if use.owner == scrutinee_type.target && use.role == 2 { variant_count = variant_count + 1 }
                    use_at = use_at + 1
                }
            }
            var covered = arms.arm_count == variant_count
            if scrutinee_type.kind == 7 {
                covered = true
                var missing: U64 = 0
                var variant_at: U64 = 0
                while variant_at < (arms.store.uses).len() {
                    let declared = (arms.store.uses)[variant_at]
                    if declared.owner == scrutinee_type.target && declared.role == 2 && !match_variant_seen(arms.arms, arms.first_arm, arms.arm_count, variant_at + 1, 0) { covered = false
                        if missing == 0 { missing = variant_at + 1 } }
                    variant_at = variant_at + 1
                }
                if !covered {
                    let missing_use = (arms.store.uses)[missing - 1]
                    let enum_symbol = (arms.store.symbols)[scrutinee_type.target - 1]
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
        let match_id = (arms.store.control.matches).len() + 1
        let first_arm = (arms.store.control.match_arms).len() + 1
        var persisted_arms = arms.store.control.match_arms
        var arm_at: U64 = 0
        while arm_at < arms.arm_count {
            let arm = (arms.arms)[arms.first_arm - 1 + arm_at]
            try persisted_arms.try_push(CheckedMatchArmRec(owner: arm.owner, syntax: arm.syntax, checked_match: match_id, variant_use: arm.variant_use, variant_kind: arm.variant_kind, binding: arm.binding, environment: arm.environment, body: arm.body))
            arm_at = arm_at + 1
        }
        let matches = try vec_appended(CheckedMatchRec, arms.store.control.matches, CheckedMatchRec(owner: owner, syntax: expression_id, scrutinee: scrutinee.expression, scrutinee_type: scrutinee.checked_type, checked_type: arms.arm_type, first_arm: first_arm, arm_count: arms.arm_count))
        let control = CheckedControlStore(blocks: arms.store.control.blocks, statement_links: arms.store.control.statement_links, statements: arms.store.control.statements, places: arms.store.control.places, matches: matches, match_arms: persisted_arms, tries: arms.store.control.tries, cleanups: arms.store.control.cleanups)
        return append_expression(d, with_control(arms.store, control), owner, expression_id, 12, arms.arm_type, match_id, 0, scrutinee.expression, 0, 0, site_kind, site_syntax)
    }
    if expression.kind == 31 {
        let result_use = function_use(store, owner, 6, expression, state)
        let function_result_id = (store.uses)[result_use - 1].checked_type
        let function_result = (store.types)[function_result_id - 1]
        if function_result.kind != 10 { return expr_token_fail(d, state, base, 80, expression) }
        let child_link = (parse.links)[expression.children - 1]
        let child = (parse.nodes)[child_link.node - 1]
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
        let operand = (current.types)[draft.checked_type - 1]
        if operand.kind != 10 { return expr_token_fail(d, state, base, 81, expression) }
        let operand_error = (current.type_args)[operand.first_arg]
        let function_error = (current.type_args)[function_result.first_arg]
        let operand_error_type = (current.types)[operand_error - 1]
        let function_error_type = (current.types)[function_error - 1]
        if !(try expression_type_equal(d, state, parse, current, operand_error, function_error)) && !(operand_error_type.kind == 19 && function_error_type.kind == 5) { return expr_token_type_fail(d, state, current, 82, expression, operand_error, function_error) }
        let ok_type = (current.type_args)[operand.first_arg - 1]
        if expected != 0 && !(try expression_type_equal(d, state, parse, current, ok_type, expected)) { return expr_token_fail(d, state, base, mismatch_kind, mismatch_node) }
        let tries = try vec_appended(CheckedTryRec, current.control.tries, CheckedTryRec(owner: owner, syntax: expression_id, expression: draft.expression, result_type: draft.checked_type, ok_type: ok_type, error_type: operand_error))
        let control = CheckedControlStore(blocks: current.control.blocks, statement_links: current.control.statement_links, statements: current.control.statements, places: current.control.places, matches: current.control.matches, match_arms: current.control.match_arms, tries: tries, cleanups: current.control.cleanups)
        return append_expression(d, with_control(current, control), owner, expression_id, 13, ok_type, (tries).len(), 0, draft.expression, 0, 0, site_kind, site_syntax)
    }
    if expression.kind != 26 { return expr_deferred(base) }
    let operator = expression_operator(state, expression)
    if operator < 3 { return expr_deferred(base) }
    let right_link = (parse.links)[expression.children - 1]
    let left_link = (parse.links)[right_link.next - 1]
    let left = (parse.nodes)[left_link.node - 1]
    let right = (parse.nodes)[right_link.node - 1]
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
    let left_limits = int_result_range(state, parse, (left_store.types)[left_draft.checked_type - 1])
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
    return CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: store.environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: control, diagnostics: store.diagnostics)
}

fn append_checked_statement(d: Domain, store: CheckStore, owner: U64, syntax: U64, kind: U64, environment: U64, expression: U64, place: U64, binding: U64, body: U64, alternative: U64, guaranteed: Bool) -> Result(BodyStep, __s0_Error) {
    let statements = try vec_appended(CheckedStatementRec, store.control.statements, CheckedStatementRec(owner: owner, syntax: syntax, kind: kind, environment: environment, expression: expression, place: place, binding: binding, body: body, alternative: alternative))
    let control = CheckedControlStore(blocks: store.control.blocks, statement_links: store.control.statement_links, statements: statements, places: store.control.places, matches: store.control.matches, match_arms: store.control.match_arms, tries: store.control.tries, cleanups: store.control.cleanups)
    return Ok(BodyGood(BodyValueRec(store: with_control(store, control), environment: current_environment(store, owner), semantic: (statements).len(), guaranteed_return: guaranteed)))
}

fn restore_environment(d: Domain, store: CheckStore, owner: U64, parent: U64) -> Result(CheckStore, __s0_Error) {
    let environments = try vec_appended(EnvironmentRec, store.environments, EnvironmentRec(owner: owner, parent: parent, binding: 0))
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, type_annotations: store.type_annotations, uses: store.uses, indexes: store.indexes, locals: store.locals, environments: environments, expressions: store.expressions, call_annotations: store.call_annotations, expression_children: store.expression_children, returns: store.returns, control: store.control, diagnostics: store.diagnostics))
}

fn field_use_named(state: State, store: CheckStore, target: U64, node: SyntaxRec) -> U64 {
    if checker_use_index_available(store, target, 1) {
        let index = (store.indexes.uses)[checker_use_slot(target, 1)]
        var ordinal: U64 = 0
        while ordinal < index.count {
            let use_id = (store.indexes.use_order)[index.first - 1 + ordinal]
            let use = (store.uses)[use_id - 1]
            if same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return use_id }
            ordinal = ordinal + 1
        }
        return 0
    }
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.owner == target && use.role == 1 && same_name(state, node.source, node.name_start, node.name_end, use.source, use.name_start, use.name_end) { return at + 1 }
        at = at + 1
    }
    return 0
}

fn concrete_field_type(d: Domain, store: CheckStore, aggregate: U64, field: U64) -> Result(TypeValueRec, __s0_Error) {
    let checked = (store.types)[aggregate - 1]
    let empty = Vec.new(InferenceBindingRec)
    let bindings = try bind_expected_application(d, store, checked.target, checked, 0, 0, empty)
    return substitute_type(d, store, bindings, (store.uses)[field - 1].checked_type)
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
    let places = try vec_appended(CheckedPlaceRec, store.control.places, CheckedPlaceRec(owner: owner, syntax: syntax, kind: kind, root: root, field: field, index: index, checked_type: checked_type))
    let control = CheckedControlStore(blocks: store.control.blocks, statement_links: store.control.statement_links, statements: store.control.statements, places: places, matches: store.control.matches, match_arms: store.control.match_arms, tries: store.control.tries, cleanups: store.control.cleanups)
    return Ok(PlaceGood(PlaceValueRec(store: with_control(store, control), place: (places).len(), checked_type: checked_type)))
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
        let base_link = (parse.links)[target.children - 1]
        let base = (parse.nodes)[base_link.node - 1]
        field_node = target
        if base.kind == 30 {
            kind = 4
            index_node = base
            let index_link = (parse.links)[base.children - 1]
            index_id = index_link.node
            let root_link = (parse.links)[index_link.next - 1]
            root_id = root_link.node
            root = (parse.nodes)[root_id - 1]
        } else {
            kind = 2
            root_id = base_link.node
            root = base
        }
    }
    if target.kind == 30 {
        kind = 3
        index_node = target
        let index_link = (parse.links)[target.children - 1]
        index_id = index_link.node
        let root_link = (parse.links)[index_link.next - 1]
        root_id = root_link.node
        root = (parse.nodes)[root_id - 1]
    }
    if root.kind != 24 { return Ok(PlaceDefer) }
    let local_id = local_lookup(store, owner, root, state)
    if local_id == 0 { return place_bad(d, store, 18, root) }
    let local = (store.locals)[local_id - 1]
    if kind == 1 {
        let root_empty = Vec.new(TypeBindingRec)
        let root_ancestry = Vec.new(DeclAncestryRec)
        let root_category = try interpreted_type_category(d, state, parse, store, root_empty, root_ancestry, local.checked_type, 0, 0)
        if root_category.category == 2 { return place_token_bad(d, state, store, 95, statement) }
    }
    if local.mutable == 0 && kind <= 2 { return place_bad(d, store, 28, root) }
    var current = store
    var value_type = local.checked_type
    var index_expression: U64 = 0
    if kind == 3 || kind == 4 {
        let sequence = (current.types)[value_type - 1]
        if sequence.kind != 8 && sequence.kind != 15 && sequence.kind != 17 && sequence.kind != 18 { return place_token_bad(d, state, store, 62, index_node) }
        value_type = (current.type_args)[sequence.first_arg - 1]
        let empty = Vec.new(TypeBindingRec)
        let no_ancestry = Vec.new(DeclAncestryRec)
        if try interpreted_contains_reference(d, state, parse, current, empty, no_ancestry, value_type, 0, 0, 0) { return place_token_bad(d, state, store, 64, index_node) }
        let index_syntax = (parse.nodes)[index_id - 1]
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
        let aggregate = (current.types)[value_type - 1]
        if aggregate.kind != 7 || (current.symbols)[aggregate.target - 1].kind != 2 { return place_bad(d, store, 60, field_node) }
        field = field_use_named(state, current, aggregate.target, field_node)
        if field == 0 { return place_bad(d, store, 61, field_node) }
        let concrete = try concrete_field_type(d, current, value_type, field)
        current = concrete.store
        value_type = concrete.checked_type
    }
    let empty = Vec.new(TypeBindingRec)
    let no_ancestry = Vec.new(DeclAncestryRec)
    let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, value_type, 0, 0)
    if category.category == 2 { return place_token_bad(d, state, current, 95, statement) }
    return append_place(d, current, owner, target_id, kind, local_id, field, index_expression, value_type)
}

// Binding order follows the Go checker: reserved name, annotation resolution,
// initializer and mismatch, Unit/DomainMark rejection, then duplicates.
fn check_binding(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    if reserved_value_name(state, store, statement) { return body_token_fail(d, state, store, 22, statement) }
    let head = (parse.links)[statement.children - 1]
    var next = store
    var annotated: U64 = 0
    var annotation_syntax: U64 = 0
    if head.next != 0 {
        let type_link = (parse.links)[head.next - 1]
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
    let init = (parse.nodes)[head.node - 1]
    let outcome = try check_value_expression(d, state, parse, next, owner, init, head.node, annotated, 23, statement, 1, statement_id)
    var ostore = match outcome {
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
    let annotation = (ostore.types)[annotated - 1]
    var diag_node = statement
    if annotation_syntax != 0 { diag_node = (parse.nodes)[annotation_syntax - 1] }
    if annotation.kind == 1 && annotation.target == 12 {
        if annotation_syntax == 0 { return body_token_fail(d, state, next, 25, statement) }
        return body_fail(d, next, 25, diag_node)
    }
    if annotation.kind == 4 {
        if annotation_syntax == 0 { return body_token_fail(d, state, next, 26, statement) }
        return body_fail(d, next, 26, diag_node)
    }
    let empty_bindings = Vec.new(TypeBindingRec)
    let empty_ancestry = Vec.new(DeclAncestryRec)
    let category = try interpreted_type_category(d, state, parse, ostore, empty_bindings, empty_ancestry, annotated, 0, 0)
    if annotation.kind == 18 && statement.kind == 15 { return body_token_fail(d, state, ostore, 102, statement) }
    if annotation.kind == 18 {
        let initializer = (ostore.expressions)[draft.expression - 1]
        if initializer.kind != 18 || initializer.annotation == 0 { return body_token_fail(d, state, ostore, 104, statement) }
        let call = (ostore.call_annotations)[initializer.annotation - 1]
        if call.builtin != 24 && call.builtin != 25 { return body_token_fail(d, state, ostore, 104, statement) }
    }
    if category.contains_nonimmutable_scoped && annotation.kind != 18 { return body_token_fail(d, state, ostore, 104, statement) }
    if category.category == 2 {
        if statement.kind == 16 { return body_token_fail(d, state, ostore, 95, statement) }
        let initializer = (ostore.expressions)[draft.expression - 1]
        if initializer.kind == 1 || initializer.kind == 5 {
            let source = (ostore.locals)[initializer.parameter_use - 1]
            var owned = source.kind == 2
            if source.kind == 1 && (parse.nodes)[source.syntax - 1].kind == 48 { owned = true }
            if !owned { return body_token_fail(d, state, ostore, 92, init) }
            var expressions = ostore.expressions
            expressions[draft.expression - 1] = CheckedExprRec(owner: initializer.owner, owner_previous: initializer.owner_previous, syntax: initializer.syntax, kind: 22, checked_type: initializer.checked_type, parameter_use: initializer.parameter_use, bool_value: initializer.bool_value, left: initializer.left, right: initializer.right, annotation: initializer.annotation, first_child: initializer.first_child, child_count: initializer.child_count, operator: initializer.operator, site_kind: initializer.site_kind, site_syntax: initializer.site_syntax)
            ostore = check_with_expressions(ostore, expressions)
        }
    }
    if local_lookup(ostore, owner, statement, state) != 0 || function_use(ostore, owner, 5, statement, state) != 0 { return body_token_fail(d, state, next, 27, statement) }
    var mutable: U64 = 0
    var statement_kind: U64 = 1
    if statement.kind == 16 {
        mutable = 1
        statement_kind = 2
    }
    let locals = try vec_appended(LocalRec, ostore.locals, LocalRec(owner: owner, kind: 2, syntax: statement_id, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: mutable, checked_type: annotated))
    let binding = (locals).len()
    let environments = try vec_appended(EnvironmentRec, ostore.environments, EnvironmentRec(owner: owner, parent: environment, binding: binding))
    let recorded = CheckStore(symbols: ostore.symbols, type_params: ostore.type_params, types: ostore.types, type_args: ostore.type_args, type_annotations: ostore.type_annotations, uses: ostore.uses, indexes: ostore.indexes, locals: locals, environments: environments, expressions: ostore.expressions, call_annotations: ostore.call_annotations, expression_children: ostore.expression_children, returns: ostore.returns, control: ostore.control, diagnostics: ostore.diagnostics)
    return append_checked_statement(d, recorded, owner, statement_id, statement_kind, environment, draft.expression, 0, binding, 0, 0, false)
}

fn check_assignment(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    let head = (parse.links)[statement.children - 1]
    let target_link = (parse.links)[head.next - 1]
    let target = (parse.nodes)[target_link.node - 1]
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
    let rhs = (parse.nodes)[head.node - 1]
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
    if (ostore.types)[place.checked_type - 1].kind == 18 { return body_token_fail(d, state, ostore, 104, statement) }
    return append_checked_statement(d, ostore, owner, statement_id, 3, environment, draft.expression, place.place, 0, 0, 0, false)
}

fn check_return_statement(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    let result_use_id = function_use(store, owner, 6, statement, state)
    let result_use = (store.uses)[result_use_id - 1]
    let result_type = (store.types)[result_use.checked_type - 1]
    var current = store
    var expression: U64 = 0
    if statement.children == 0 {
        if result_type.kind != 1 || result_type.target != 12 { return body_token_fail(d, state, store, 20, statement) }
    } else {
        let expression_link = (parse.links)[statement.children - 1]
        let syntax = (parse.nodes)[expression_link.node - 1]
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
        let empty = Vec.new(TypeBindingRec)
        let no_ancestry = Vec.new(DeclAncestryRec)
        let category = try interpreted_type_category(d, state, parse, current, empty, no_ancestry, result_use.checked_type, 0, 0)
        // Immutable views are recursively materialized when nested in an
        // ordinary result. Mutable and non-relocatable scoped capabilities
        // remain lexical and cannot escape directly or through aggregates.
        if category.contains_nonimmutable_scoped { return body_token_fail(d, state, current, 104, statement) }
        let returned = (current.expressions)[expression - 1]
        if returned.kind == 1 || returned.kind == 5 {
            let binding = (current.locals)[returned.parameter_use - 1]
            var take_binding = false
            if binding.kind == 1 && (parse.nodes)[binding.syntax - 1].kind == 48 { take_binding = true }
            let owned = binding.kind == 2 || take_binding
            if category.category == 2 || (category.category == 0 && take_binding) {
                if !owned { return body_token_fail(d, state, current, 92, syntax) }
                var expressions = current.expressions
                expressions[expression - 1] = CheckedExprRec(owner: returned.owner, owner_previous: returned.owner_previous, syntax: returned.syntax, kind: 22, checked_type: returned.checked_type, parameter_use: returned.parameter_use, bool_value: returned.bool_value, left: returned.left, right: returned.right, annotation: returned.annotation, first_child: returned.first_child, child_count: returned.child_count, operator: returned.operator, site_kind: returned.site_kind, site_syntax: returned.site_syntax)
                current = check_with_expressions(current, expressions)
            }
        }
    }
    let returns = try vec_appended(CheckedReturnRec, current.returns, CheckedReturnRec(owner: owner, syntax: statement_id, expression: expression, result_use: result_use_id))
    let recorded = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: current.locals, environments: current.environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: returns, control: current.control, diagnostics: current.diagnostics)
    return append_checked_statement(d, recorded, owner, statement_id, 4, environment, expression, 0, 0, 0, 0, true)
}

fn check_expression_statement(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64) -> Result(BodyStep, __s0_Error) {
    var expression_id = statement_id
    var expression = statement
    if statement.kind == 19 {
        let expression_link = (parse.links)[statement.children - 1]
        expression_id = expression_link.node
        expression = (parse.nodes)[expression_id - 1]
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
    return append_checked_statement(d, current, owner, statement_id, 5, environment, draft.expression, 0, 0, 0, 0, false)
}

// Cleanup checking intentionally follows frontend/check.go precedence: name,
// loop, initializer, callback resolution/shape/type/result, then duplicates.
fn check_using(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64, statement: SyntaxRec, statement_id: U64, environment: U64, in_loop: Bool) -> Result(BodyStep, __s0_Error) {
    if reserved_value_name(state, store, statement) { return body_token_fail(d, state, store, 22, statement) }
    if in_loop { return body_token_fail(d, state, store, 69, statement) }
    let cleanup_link = (parse.links)[statement.children - 1]
    let initializer_link = (parse.links)[cleanup_link.next - 1]
    let initializer_node = (parse.nodes)[initializer_link.node - 1]
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
    let cleanup_node = (parse.nodes)[cleanup_link.node - 1]
    let callback = symbol_named(state, parse, current, cleanup_node)
    if callback == 0 || (current.symbols)[callback - 1].kind != 12 { return body_fail(d, current, 83, cleanup_node) }
    let callback_symbol = (current.symbols)[callback - 1]
    var parameter: U64 = 0
    var parameter_count: U64 = 0
    var result: U64 = 0
    var use_at: U64 = 0
    while use_at < (current.uses).len() {
        let use = (current.uses)[use_at]
        if use.owner == callback && use.role == 5 { parameter = use.checked_type
            parameter_count = parameter_count + 1 }
        if use.owner == callback && use.role == 6 { result = use.checked_type }
        use_at = use_at + 1
    }
    // No explicit arguments are available at a using site. A generic callback
    // therefore cannot provide one concrete runtime parameter instance.
    if callback_symbol.type_arity != 0 || parameter_count != 1 { return body_fail(d, current, 84, cleanup_node) }
    if !(try expression_type_equal(d, state, parse, current, initializer.checked_type, parameter)) { return body_token_type_fail(d, state, current, 85, statement, initializer.checked_type, parameter) }
    let result_type = (current.types)[result - 1]
    if result_type.kind != 1 || result_type.target != 12 { return body_fail(d, current, 86, cleanup_node) }
    if local_lookup(current, owner, statement, state) != 0 || function_use(current, owner, 5, statement, state) != 0 { return body_token_fail(d, state, current, 27, statement) }
    let locals = try vec_appended(LocalRec, current.locals, LocalRec(owner: owner, kind: 2, syntax: statement_id, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: 0, checked_type: initializer.checked_type))
    let binding = (locals).len()
    let environments = try vec_appended(EnvironmentRec, current.environments, EnvironmentRec(owner: owner, parent: environment, binding: binding))
    current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: locals, environments: environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
    let cleanups = try vec_appended(CheckedCleanupRec, current.control.cleanups, CheckedCleanupRec(owner: owner, syntax: statement_id, environment: environment, binding: binding, initializer: initializer.expression, callback: callback, normal_exit: 1, return_exit: 1, try_exit: 1))
    current = with_control(current, CheckedControlStore(blocks: current.control.blocks, statement_links: current.control.statement_links, statements: current.control.statements, places: current.control.places, matches: current.control.matches, match_arms: current.control.match_arms, tries: current.control.tries, cleanups: cleanups))
    return append_checked_statement(d, current, owner, statement_id, 10, environment, initializer.expression, 0, binding, (cleanups).len(), 0, false)
}

// Structural flattening is self-recursive and carries only parser IDs. role is
// 1 for a block syntax node, 2 for a reverse SyntaxLinkRec chain, and 3 for a
// statement syntax node.
fn build_body_event(d: Domain, parse: ParseStore, events: Vec(BodyEventRec), role: U64, item: U64) -> Result(BodyEventBuildRec, __s0_Error) {
    if role == 2 && item == 0 { return Ok(BodyEventBuildRec(events: events, event: 0)) }
    if role == 1 {
        let block = (parse.nodes)[item - 1]
        let children = try build_body_event(d, parse, events, 2, block.children)
        let appended = try vec_appended(BodyEventRec, children.events, BodyEventRec(kind: 1, syntax: item, first: children.event, second: 0, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: (appended).len()))
    }
    if role == 2 {
        let link = (parse.links)[item - 1]
        let prior = try build_body_event(d, parse, events, 2, link.next)
        let statement = try build_body_event(d, parse, prior.events, 3, link.node)
        let appended = try vec_appended(BodyEventRec, statement.events, BodyEventRec(kind: 2, syntax: link.node, first: prior.event, second: statement.event, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: (appended).len()))
    }
    let statement = (parse.nodes)[item - 1]
    if statement.kind == 14 {
        let body = try build_body_event(d, parse, events, 1, item)
        let appended = try vec_appended(BodyEventRec, body.events, BodyEventRec(kind: 4, syntax: item, first: body.event, second: 0, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: (appended).len()))
    }
    if statement.kind == 32 || statement.kind == 33 {
        let head = (parse.links)[statement.children - 1]
        var body_link = head
        var condition_link = (parse.links)[head.next - 1]
        var alternative_node: U64 = 0
        if statement.kind == 32 && condition_link.next != 0 {
            alternative_node = head.node
            body_link = condition_link
            condition_link = (parse.links)[condition_link.next - 1]
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
        let appended = try vec_appended(BodyEventRec, current.events, BodyEventRec(kind: kind, syntax: item, first: condition_link.node, second: body.event, third: alternative))
        return Ok(BodyEventBuildRec(events: appended, event: (appended).len()))
    }
    if statement.kind == 34 {
        let head = (parse.links)[statement.children - 1]
        let sequence_link = (parse.links)[head.next - 1]
        let body = try build_body_event(d, parse, events, 1, head.node)
        let appended = try vec_appended(BodyEventRec, body.events, BodyEventRec(kind: 7, syntax: item, first: sequence_link.node, second: body.event, third: 0))
        return Ok(BodyEventBuildRec(events: appended, event: (appended).len()))
    }
    let appended = try vec_appended(BodyEventRec, events, BodyEventRec(kind: 3, syntax: item, first: 0, second: 0, third: 0))
    return Ok(BodyEventBuildRec(events: appended, event: (appended).len()))
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
fn check_body_event(d: Domain, state: State, parse: ParseStore, events: Vec(BodyEventRec), store: CheckStore, owner: U64, event_id: U64, in_loop: Bool, restore: Bool) -> Result(BodyStep, __s0_Error) {
    if event_id == 0 { return Ok(BodyGood(BodyValueRec(store: store, environment: current_environment(store, owner), semantic: 0, guaranteed_return: false))) }
    let event = events[event_id - 1]
    let statement = (parse.nodes)[event.syntax - 1]
    if event.kind == 1 {
        let entry = current_environment(store, owner)
        let checked = try check_body_event(d, state, parse, events, store, owner, event.first, in_loop, false)
        if body_event_stopped(checked) { return Ok(checked) }
        let value = body_event_value(checked, store)
        var guaranteed: U64 = 0
        if value.guaranteed_return { guaranteed = 1 }
        let blocks = try vec_appended(CheckedBlockRec, value.store.control.blocks, CheckedBlockRec(owner: owner, syntax: event.syntax, environment: entry, statements: value.semantic, guaranteed_return: guaranteed))
        var current = with_control(value.store, CheckedControlStore(blocks: blocks, statement_links: value.store.control.statement_links, statements: value.store.control.statements, places: value.store.control.places, matches: value.store.control.matches, match_arms: value.store.control.match_arms, tries: value.store.control.tries, cleanups: value.store.control.cleanups))
        if restore { current = try restore_environment(d, current, owner, entry) }
        return Ok(BodyGood(BodyValueRec(store: current, environment: current_environment(current, owner), semantic: (blocks).len(), guaranteed_return: value.guaranteed_return)))
    }
    if event.kind == 2 {
        let before = try check_body_event(d, state, parse, events, store, owner, event.first, in_loop, false)
        if body_event_stopped(before) { return Ok(before) }
        let prior = body_event_value(before, store)
        if prior.guaranteed_return { return body_token_fail(d, state, prior.store, 68, statement) }
        let checked = try check_body_event(d, state, parse, events, prior.store, owner, event.second, in_loop, false)
        if body_event_stopped(checked) { return Ok(checked) }
        let value = body_event_value(checked, prior.store)
        let links = try vec_appended(CheckedStatementLinkRec, value.store.control.statement_links, CheckedStatementLinkRec(statement: value.semantic, next: prior.semantic))
        let current = with_control(value.store, CheckedControlStore(blocks: value.store.control.blocks, statement_links: links, statements: value.store.control.statements, places: value.store.control.places, matches: value.store.control.matches, match_arms: value.store.control.match_arms, tries: value.store.control.tries, cleanups: value.store.control.cleanups))
        return Ok(BodyGood(BodyValueRec(store: current, environment: current_environment(current, owner), semantic: (links).len(), guaranteed_return: value.guaranteed_return)))
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
        let condition = (parse.nodes)[event.first - 1]
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
    let sequence = (parse.nodes)[event.first - 1]
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
    let locals = try vec_appended(LocalRec, current.locals, LocalRec(owner: owner, kind: 2, syntax: event.syntax, source: statement.source, name_start: statement.name_start, name_end: statement.name_end, mutable: 0, checked_type: element))
    let binding = (locals).len()
    let environments = try vec_appended(EnvironmentRec, current.environments, EnvironmentRec(owner: owner, parent: environment, binding: binding))
    current = CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, type_annotations: current.type_annotations, uses: current.uses, indexes: current.indexes, locals: locals, environments: environments, expressions: current.expressions, call_annotations: current.call_annotations, expression_children: current.expression_children, returns: current.returns, control: current.control, diagnostics: current.diagnostics)
    let checked_body = try check_body_event(d, state, parse, events, current, owner, event.second, true, true)
    if body_event_stopped(checked_body) { return Ok(checked_body) }
    let body = body_event_value(checked_body, current)
    current = try restore_environment(d, body.store, owner, environment)
    return append_checked_statement(d, current, owner, event.syntax, 9, environment, sequence_draft.expression, 0, binding, body.semantic, 0, false)
}

fn append_parameter_bindings(d: Domain, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckStore, __s0_Error) {
    var next = store
    let symbol = (store.symbols)[owner - 1]
    var role: U64 = 5
    if symbol.kind == 13 { role = 7 }
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        if use.owner == owner && use.role == role {
            let parameter = (parse.nodes)[use.node - 1]
            var mutable: U64 = 0
            if parameter.kind == 47 { mutable = 1 }
            if parameter.kind == 48 { mutable = 2 }
            let locals = try vec_appended(LocalRec, next.locals, LocalRec(owner: owner, kind: 1, syntax: use.node, source: use.source, name_start: use.name_start, name_end: use.name_end, mutable: mutable, checked_type: use.checked_type))
            let binding = (locals).len()
            var parent: U64 = 0
            if (next.environments).len() != 0 {
                let candidate = (next.environments).len()
                if (next.environments)[candidate - 1].owner == owner { parent = candidate }
            }
            let environments = try vec_appended(EnvironmentRec, next.environments, EnvironmentRec(owner: owner, parent: parent, binding: binding))
            next = CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, type_annotations: next.type_annotations, uses: next.uses, indexes: next.indexes, locals: locals, environments: environments, expressions: next.expressions, call_annotations: next.call_annotations, expression_children: next.expression_children, returns: next.returns, control: next.control, diagnostics: next.diagnostics)
        }
        at = at + 1
    }
    return Ok(next)
}

fn owner_flow_expression(store: CheckStore, binding: U64, expression_id: U64, state: U64) -> OwnerFlowRec {
    if expression_id == 0 { return OwnerFlowRec(state: state, terminated: false, error_kind: 0, syntax: 0) }
    let expression = (store.expressions)[expression_id - 1]
    var current = state
    var child: U64 = 0
    while child < expression.child_count {
        let child_id = (store.expression_children)[expression.first_child - 1 + child].expression
        let checked = owner_flow_expression(store, binding, child_id, current)
        if checked.error_kind != 0 { return checked }
        if expression.kind == 7 && (expression.operator == 16 || expression.operator == 17) && child == 1 && checked.state != current {
            return OwnerFlowRec(state: current, terminated: false, error_kind: 94, syntax: expression.syntax)
        }
        current = checked.state
        child = child + 1
    }
    if expression.kind == 12 {
        let checked_match = (store.control.matches)[expression.parameter_use - 1]
        var arm: U64 = 0
        var arm_state: U64 = 2
        while arm < checked_match.arm_count {
            let body = (store.control.match_arms)[checked_match.first_arm - 1 + arm].body
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
    let block = (store.control.blocks)[block_id - 1]
    return owner_flow_links(store, binding, block.statements, state)
}

fn owner_flow_statement(store: CheckStore, binding: U64, statement_id: U64, state: U64) -> OwnerFlowRec {
    let statement = (store.control.statements)[statement_id - 1]
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
    let link = (store.control.statement_links)[link_id - 1]
    let before = owner_flow_links(store, binding, link.next, state)
    if before.error_kind != 0 || before.terminated { return before }
    return owner_flow_statement(store, binding, link.statement, before.state)
}

// Bodies are checked compositionally in source order. Every concrete body is
// complete or produces one source diagnostic; control-flow and every nested
// block retain concrete-instance ownership and persistent environments.
fn check_body(d: Domain, state: State, parse: ParseStore, store: CheckStore, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = (store.symbols)[owner - 1]
    if !((symbol.kind == 12 && symbol.type_arity == 0) || symbol.kind == 13) { return Ok(CheckGood(store)) }
    let declaration = (store.symbols)[instance_declaration(store, owner) - 1]
    let root = (parse.nodes)[declaration.node - 1]
    let body_link = (parse.links)[root.children - 1]
    let body = (parse.nodes)[body_link.node - 1]
    let with_parameters = try append_parameter_bindings(d, parse, store, owner)
    let events = Vec.new(BodyEventRec)
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
    let result_use = (after.uses)[result_use_id - 1]
    let result_type = (after.types)[result_use.checked_type - 1]
    if (result_type.kind != 1 || result_type.target != 12) && !checked_block.guaranteed_return {
        let failed = try check_token_fail(d, state, after, 67, body)
        let bad = match failed {
            CheckGood(value) => value
            CheckBad(value) => value
        }
        return Ok(CheckBad(rollback_body(store, bad)))
    }
    var local_at: U64 = 0
    while local_at < (after.locals).len() {
        let local = (after.locals)[local_at]
        var owned = false
        var initial_state: U64 = 0
        if local.owner == owner && local.kind == 1 && (parse.nodes)[local.syntax - 1].kind == 48 { owned = true }
        if local.owner == owner && local.kind == 2 {
            let empty = Vec.new(TypeBindingRec)
            let no_ancestry = Vec.new(DeclAncestryRec)
            let category = try interpreted_type_category(d, state, parse, after, empty, no_ancestry, local.checked_type, 0, 0)
            if category.category == 2 {
                owned = true
                initial_state = 2
            }
        }
        if owned {
            let flow = owner_flow_block(after, local_at + 1, checked_block.semantic, initial_state)
            if flow.error_kind != 0 || (!flow.terminated && flow.state == 0) {
                var diagnostic_kind: U64 = 93
                var diagnostic_node = (parse.nodes)[local.syntax - 1]
                if flow.error_kind != 0 {
                    diagnostic_kind = flow.error_kind
                    diagnostic_node = (parse.nodes)[flow.syntax - 1]
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
    while at <= (current.symbols).len() {
        let result = try check_body(d, state, parse, current, at)
        current = check_result_store(result)
        last = result
        if check_result_bad(result) { failed = 1 }
        if failed == 0 { at = at + 1 }
        if failed != 0 { at = (current.symbols).len() + 1 }
    }
    return Ok(last)
}

fn check_function_bodies(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    return check_function_body_at(d, state, parse, store, 1)
}

fn private_signature_type(store: CheckStore, checked_type: U64) -> U64 {
    if checked_type == 0 { return 0 }
    let item = (store.types)[checked_type - 1]
    if item.kind == 7 {
        let symbol = (store.symbols)[item.target - 1]
        if symbol.module_source != 0 && !symbol.public { return item.target }
    }
    var at: U64 = 0
    while at < item.arg_count {
        let hidden = private_signature_type(store, (store.type_args)[item.first_arg - 1 + at])
        if hidden != 0 { return hidden }
        at = at + 1
    }
    return 0
}

fn check_public_signatures(d: Domain, state: State, parse: ParseStore, store: CheckStore) -> Result(CheckResult, __s0_Error) {
    var at: U64 = 0
    while at < (store.uses).len() {
        let use = (store.uses)[at]
        let owner = (store.symbols)[use.owner - 1]
        if owner.public {
            let hidden = private_signature_type(store, use.checked_type)
            if hidden != 0 {
                let symbol = (store.symbols)[hidden - 1]
                let node = (parse.nodes)[use.syntax - 1]
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
    let public_signatures = try check_public_signatures(d, state, parse, after_functions)
    let after_public_signatures = match public_signatures {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match public_signatures {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(public_signatures) }
    let indexed = try build_use_indexes(d, after_public_signatures, true)
    return check_function_bodies(d, state, parse, indexed)
}

fn check_parsed(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    // Orchestration callers invoke this only for ParseGood. Keep the guard so
    // malformed direct callers cannot run checking after either earlier phase.
    if (state.diagnostics).len() != 0 || (parse.diagnostics).len() != 0 { return Ok(CheckBad(initial)) }
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
    while at < (state.sources).len() {
        let rec = (state.sources)[at]
        if !out_string("S ") || !out_u64(at) || !out(32) || !out_hex(state.paths, rec.path_start, rec.path_end) || !out(32) || !out_u64(rec.text_end - rec.text_start) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_checked_symbols(store: CheckStore) -> Bool {
    var at: U64 = 0
    while at < (store.symbols).len() {
        let rec = (store.symbols)[at]
        if !out_string("Y ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.type_arity) || !out(32) || !out_u64(rec.declaration) || !out(32) || !out_u64(rec.first_instance_arg) || !out(32) || !out_u64(rec.instance_arg_count) || !out(32) || !out_u64(rec.discovery_parent) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.type_params).len() {
        let rec = (store.type_params)[at]
        if !out_string("P ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_checked_types(store: CheckStore) -> Bool {
    var at: U64 = 0
    while at < (store.types).len() {
        let rec = (store.types)[at]
        if !out_string("C ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.target) || !out(32) || !out_u64(rec.first_arg) || !out(32) || !out_u64(rec.arg_count) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.type_args).len() {
        if !out_string("A ") || !out_u64(at + 1) || !out(32) || !out_u64((store.type_args)[at]) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.type_annotations).len() {
        let rec = (store.type_annotations)[at]
        if !out_string("T ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.uses).len() {
        let rec = (store.uses)[at]
        if !out_string("U ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.role) || !out(32) || !out_u64(rec.ordinal) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_checked_control(store: CheckStore) -> Bool {
    var at: U64 = 0
    while at < (store.control.matches).len() {
        let rec = (store.control.matches)[at]
        if !out_string("M ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.scrutinee) || !out(32) || !out_u64(rec.scrutinee_type) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.first_arm) || !out(32) || !out_u64(rec.arm_count) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.match_arms).len() {
        let rec = (store.control.match_arms)[at]
        if !out_string("W ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_match) || !out(32) || !out_u64(rec.variant_use) || !out(32) || !out_u64(rec.variant_kind) || !out(32) || !out_u64(rec.binding) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.body) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.tries).len() {
        let rec = (store.control.tries)[at]
        if !out_string("X ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.expression) || !out(32) || !out_u64(rec.result_type) || !out(32) || !out_u64(rec.ok_type) || !out(32) || !out_u64(rec.error_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.cleanups).len() {
        let rec = (store.control.cleanups)[at]
        if !out_string("G ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.binding) || !out(32) || !out_u64(rec.initializer) || !out(32) || !out_u64(rec.callback) || !out(32) || !out_u64(rec.normal_exit) || !out(32) || !out_u64(rec.return_exit) || !out(32) || !out_u64(rec.try_exit) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.places).len() {
        let rec = (store.control.places)[at]
        if !out_string("V ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.root) || !out(32) || !out_u64(rec.field) || !out(32) || !out_u64(rec.index) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.statements).len() {
        let rec = (store.control.statements)[at]
        if !out_string("J ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.expression) || !out(32) || !out_u64(rec.place) || !out(32) || !out_u64(rec.binding) || !out(32) || !out_u64(rec.body) || !out(32) || !out_u64(rec.alternative) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.statement_links).len() {
        let rec = (store.control.statement_links)[at]
        if !out_string("K ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.statement) || !out(32) || !out_u64(rec.next) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.control.blocks).len() {
        let rec = (store.control.blocks)[at]
        if !out_string("B ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.environment) || !out(32) || !out_u64(rec.statements) || !out(32) || !out_u64(rec.guaranteed_return) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_checked_expressions(store: CheckStore) -> Bool {
    var at: U64 = 0
    while at < (store.expressions).len() {
        let rec = (store.expressions)[at]
        if !out_string("E ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.parameter_use) || !out(32) || !out_u64(rec.bool_value) || !out(32) || !out_u64(rec.left) || !out(32) || !out_u64(rec.right) || !out(32) || !out_u64(rec.annotation) || !out(32) || !out_u64(rec.first_child) || !out(32) || !out_u64(rec.child_count) || !out(32) || !out_u64(rec.operator) || !out(32) || !out_u64(rec.site_kind) || !out(32) || !out_u64(rec.site_syntax) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.expression_children).len() {
        let rec = (store.expression_children)[at]
        if !out_string("H ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.expression) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.returns).len() {
        let rec = (store.returns)[at]
        if !out_string("R ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.expression) || !out(32) || !out_u64(rec.result_use) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_checked_bindings(store: CheckStore) -> Bool {
    var at: U64 = 0
    var instance_order: U64 = 0
    while at < (store.symbols).len() {
        let rec = (store.symbols)[at]
        if rec.declaration != 0 {
            instance_order = instance_order + 1
            if !out_string("I ") || !out_u64(instance_order) || !out(32) || !out_u64(at + 1) || !out(32) || !out_u64(rec.declaration) || !out(32) || !out_u64(rec.first_instance_arg) || !out(32) || !out_u64(rec.instance_arg_count) || !out(32) || !out_u64(rec.discovery_parent) || !out(10) { return false }
        }
        at = at + 1
    }
    at = 0
    while at < (store.locals).len() {
        let rec = (store.locals)[at]
        if !out_string("L ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.mutable) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.environments).len() {
        let rec = (store.environments)[at]
        if !out_string("N ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.parent) || !out(32) || !out_u64(rec.binding) || !out(10) { return false }
        at = at + 1
    }
    at = 0
    while at < (store.call_annotations).len() {
        let rec = (store.call_annotations)[at]
        if !out_string("Q ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.target) || !out(32) || !out_u64(rec.checked_type) || !out(32) || !out_u64(rec.variant_use) || !out(32) || !out_u64(rec.builtin) || !out(10) { return false }
        at = at + 1
    }
    return true
}

fn emit_check_spans(parse: ParseStore) -> Bool {
    var at: U64 = 0
    while at < (parse.nodes).len() {
        let rec = (parse.nodes)[at]
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
    if !out_string("ALDER-CHECKER-MANIFEST 14\n") || !emit_check_sources(state) || !emit_check_spans(parse) { return false }
    if !emit_checked_symbols(store) { return false }
    if !emit_checked_types(store) { return false }
    if !emit_checked_bindings(store) { return false }
    if !emit_checked_expressions(store) { return false }
    if !emit_checked_control(store) { return false }
    var at: U64 = 0
    while at < (store.diagnostics).len() {
        let rec = (store.diagnostics)[at]
        if !emit_check_diagnostic(rec) { return false }
        at = at + 1
    }
    return out_string("END\n")
}
