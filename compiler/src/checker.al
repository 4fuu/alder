type CheckStore {
    symbols: __s0_Buffer(SymbolRec)
    type_params: __s0_Buffer(TypeParamRec)
    types: __s0_Buffer(CheckedTypeRec)
    type_args: __s0_Buffer(U64)
    uses: __s0_Buffer(DeclTypeUseRec)
    diagnostics: __s0_Buffer(CheckDiagRec)
}

enum CheckResult {
    CheckGood(value: CheckStore)
    CheckBad(value: CheckStore)
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

fn env_lookup(bindings: __s0_Buffer(TypeBindingRec), env: U64, param: U64) -> TypeBindingRec {
    var at = env
    while at != 0 {
        let item = __s0_buffer_get(TypeBindingRec, bindings, at - 1)
        if item.param == param { return item }
        at = item.next
    }
    return TypeBindingRec(param: 0, checked_type: 0, caller_env: 0, next: 0)
}

fn normalize_interp(store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64) -> InterpWorkRec {
    var t = checked_type
    var e = env
    var done = false
    while !done {
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, t - 1)
        if checked.kind != 6 { done = true } else {
            let bound = env_lookup(bindings, e, checked.target)
            if bound.param == 0 { done = true } else { t = bound.checked_type
                e = bound.caller_env }
        }
    }
    return InterpWorkRec(checked_type: t, env: e, ancestry: 0)
}

fn primitive_same(state: State, parse: ParseStore, a: CheckedTypeRec, b: CheckedTypeRec) -> Bool {
    let an = __s0_buffer_get(SyntaxRec, parse.nodes, a.syntax - 1)
    let bn = __s0_buffer_get(SyntaxRec, parse.nodes, b.syntax - 1)
    return same_name(state, an.source, an.name_start, an.name_end, bn.source, bn.name_start, bn.name_end)
}

// Finite structural equality is iterative. Declared applications compare their
// target and direct arguments and never expand declaration bodies.
fn interpreted_type_equal(d: Domain, state: State, parse: ParseStore, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), left_type: U64, left_env: U64, right_type: U64, right_env: U64) -> Result(Bool, __s0_Error) {
    let initial = try __s0_buffer_new(PairWorkRec, d)
    var work = try __s0_buffer_append(PairWorkRec, d, initial, PairWorkRec(left_type: left_type, left_env: left_env, right_type: right_type, right_env: right_env))
    var at: U64 = 0
    while at < __s0_buffer_len(PairWorkRec, work) {
        let pair = __s0_buffer_get(PairWorkRec, work, at)
        let left = normalize_interp(store, bindings, pair.left_type, pair.left_env)
        let right = normalize_interp(store, bindings, pair.right_type, pair.right_env)
        let a = __s0_buffer_get(CheckedTypeRec, store.types, left.checked_type - 1)
        let b = __s0_buffer_get(CheckedTypeRec, store.types, right.checked_type - 1)
        if a.kind != b.kind || a.target != b.target || a.arg_count != b.arg_count { return Ok(false) }
        if a.kind == 1 && !primitive_same(state, parse, a, b) { return Ok(false) }
        if a.kind == 6 && a.target != b.target { return Ok(false) }
        var child: U64 = 0
        while child < a.arg_count {
            work = try __s0_buffer_append(PairWorkRec, d, work, PairWorkRec(left_type: __s0_buffer_get(U64, store.type_args, a.first_arg - 1 + child), left_env: left.env, right_type: __s0_buffer_get(U64, store.type_args, b.first_arg - 1 + child), right_env: right.env))
            child = child + 1
        }
        at = at + 1
    }
    return Ok(true)
}

fn direct_type_concrete(d: Domain, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64) -> Result(Bool, __s0_Error) {
    let initial = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, initial, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env)
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

fn build_target_env(d: Domain, store: CheckStore, bindings: __s0_Buffer(TypeBindingRec), target: U64, checked: CheckedTypeRec, caller_env: U64) -> Result(__s0_Buffer(TypeBindingRec), __s0_Error) {
    var result = bindings
    var head: U64 = 0
    var ordinal: U64 = 0
    var at: U64 = 0
    while at < __s0_buffer_len(TypeParamRec, store.type_params) {
        let param = __s0_buffer_get(TypeParamRec, store.type_params, at)
        if param.owner == target {
            result = try __s0_buffer_append(TypeBindingRec, d, result, TypeBindingRec(param: at + 1, checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + ordinal), caller_env: caller_env, next: head))
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

// This mirrors frontend/types.go containsSlice. Repeated declaration targets
// are cut per path, which makes probes safe even while aggregates are partial.
fn interpreted_contains_reference(d: Domain, store: CheckStore, initial_bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64, boundary: U64) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    let first_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    var ancestry = first_ancestry
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        if checked.kind == 2 || checked.kind == 3 || checked.kind == 4 || checked.kind == 8 || checked.kind == 11 || checked.kind == 12 || checked.kind == 13 { return Ok(true) }
        if checked.kind == 9 || checked.kind == 10 {
            var child: U64 = 0
            while child < checked.arg_count {
                work = try __s0_buffer_append(InterpWorkRec, d, work, InterpWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + child), env: norm.env, ancestry: item.ancestry))
                child = child + 1
            }
        }
        if checked.kind == 7 && declaration_available(boundary, checked.target) && !ancestry_has(ancestry, item.ancestry, checked.target) {
            let old_len = __s0_buffer_len(TypeBindingRec, bindings)
            bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env)
            let target_env = declaration_env_head(bindings, old_len)
            ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: item.ancestry))
            work = try push_decl_members(d, store, work, checked.target, target_env, __s0_buffer_len(DeclAncestryRec, ancestry))
        }
        at = at + 1
    }
    return Ok(false)
}

fn primitive_map_key(state: State, parse: ParseStore, checked: CheckedTypeRec) -> Bool {
    if checked.kind != 1 { return false }
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, checked.syntax - 1)
    return node_word(state, node, "Bool") || node_word(state, node, "U8") || node_word(state, node, "U16") || node_word(state, node, "U32") || node_word(state, node, "U64")
}

fn interpreted_map_key_ok(d: Domain, state: State, parse: ParseStore, store: CheckStore, initial_bindings: __s0_Buffer(TypeBindingRec), checked_type: U64, env: U64, boundary: U64) -> Result(Bool, __s0_Error) {
    var bindings = initial_bindings
    let first_work = try __s0_buffer_new(InterpWorkRec, d)
    var work = try __s0_buffer_append(InterpWorkRec, d, first_work, InterpWorkRec(checked_type: checked_type, env: env, ancestry: 0))
    let first_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    var ancestry = first_ancestry
    var at: U64 = 0
    while at < __s0_buffer_len(InterpWorkRec, work) {
        let item = __s0_buffer_get(InterpWorkRec, work, at)
        let norm = normalize_interp(store, bindings, item.checked_type, item.env)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        if checked.kind == 1 {
            if !primitive_map_key(state, parse, checked) { return Ok(false) }
        } else {
            if checked.kind == 7 && declaration_available(boundary, checked.target) {
                if !ancestry_has(ancestry, item.ancestry, checked.target) {
                    let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                    bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env)
                    let target_env = declaration_env_head(bindings, old_len)
                    ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: item.ancestry))
                    work = try push_decl_members(d, store, work, checked.target, target_env, __s0_buffer_len(DeclAncestryRec, ancestry))
                }
            } else {
                if checked.kind != 7 { return Ok(false) }
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

fn type_diag_node(state: State, parse: ParseStore, checked: CheckedTypeRec) -> SyntaxRec {
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, checked.syntax - 1)
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
    let empty_work = try __s0_buffer_new(ValidationWorkRec, d)
    var work = try __s0_buffer_append(ValidationWorkRec, d, empty_work, ValidationWorkRec(checked_type: root_type, env: root_env, ancestry: 0, next: 0))
    var head: U64 = 1
    while head != 0 {
        let item = __s0_buffer_get(ValidationWorkRec, work, head - 1)
        head = item.next
        let norm = normalize_interp(store, bindings, item.checked_type, item.env)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        if checked.kind == 8 {
            let child = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
            if try interpreted_contains_reference(d, store, bindings, child, norm.env, boundary) { return check_fail(d, store, 10, root_node, 0, 0, 0) }
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: child, env: norm.env, ancestry: item.ancestry, next: head))
            head = __s0_buffer_len(ValidationWorkRec, work)
        }
        if checked.kind == 9 || checked.kind == 12 {
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env: norm.env, ancestry: item.ancestry, next: head))
            head = __s0_buffer_len(ValidationWorkRec, work)
        }
        if checked.kind == 13 {
            let child = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
            if try interpreted_contains_reference(d, store, bindings, child, norm.env, boundary) { return check_fail(d, store, 11, root_node, 0, 0, 0) }
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: child, env: norm.env, ancestry: item.ancestry, next: head))
            head = __s0_buffer_len(ValidationWorkRec, work)
        }
        if checked.kind == 10 {
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg), env: norm.env, ancestry: item.ancestry, next: head))
            let err_head = __s0_buffer_len(ValidationWorkRec, work)
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: __s0_buffer_get(U64, store.type_args, checked.first_arg - 1), env: norm.env, ancestry: item.ancestry, next: err_head))
            head = __s0_buffer_len(ValidationWorkRec, work)
        }
        if checked.kind == 11 {
            let key = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1)
            let value = __s0_buffer_get(U64, store.type_args, checked.first_arg)
            if !(try interpreted_map_key_ok(d, state, parse, store, bindings, key, norm.env, boundary)) { return check_fail(d, store, 12, root_node, 0, 0, 0) }
            if try interpreted_contains_reference(d, store, bindings, value, norm.env, boundary) { return check_fail(d, store, 13, root_node, 0, 0, 0) }
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: value, env: norm.env, ancestry: item.ancestry, next: head))
            let value_head = __s0_buffer_len(ValidationWorkRec, work)
            work = try __s0_buffer_append(ValidationWorkRec, d, work, ValidationWorkRec(checked_type: key, env: norm.env, ancestry: item.ancestry, next: value_head))
            head = __s0_buffer_len(ValidationWorkRec, work)
        }
        if checked.kind == 7 && declaration_available(boundary, checked.target) {
            let active = active_target(ancestry, item.ancestry, checked.target)
            if active != 0 {
                let prior = __s0_buffer_get(DeclAncestryRec, ancestry, active - 1)
                if !(try specialization_equal(d, state, parse, store, bindings, checked, norm.env, prior.env)) { return check_fail(d, store, 14, root_node, 0, 0, 0) }
            } else {
                let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env)
                let target_env = declaration_env_head(bindings, old_len)
                ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: item.ancestry))
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

fn check_fail(d: Domain, store: CheckStore, kind: U64, node: SyntaxRec, related_source: U64, related_start: U64, related_end: U64) -> Result(CheckResult, __s0_Error) {
    let item = CheckDiagRec(kind: kind, source: node.source, start: node.name_start, end: node.name_end, related_source: related_source, related_start: related_start, related_end: related_end)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, uses: store.uses, diagnostics: diagnostics)))
}

fn check_decl_fail(d: Domain, state: State, parse: ParseStore, store: CheckStore, kind: U64, owner: U64) -> Result(CheckResult, __s0_Error) {
    let symbol = __s0_buffer_get(SymbolRec, store.symbols, owner - 1)
    let node = __s0_buffer_get(SyntaxRec, parse.nodes, symbol.node - 1)
    let token = __s0_buffer_get(TokenRec, state.tokens, node.token - 1)
    let item = CheckDiagRec(kind: kind, source: token.source, start: token.start, end: token.end, related_source: 0, related_start: 0, related_end: 0)
    let diagnostics = try __s0_buffer_append(CheckDiagRec, d, store.diagnostics, item)
    return Ok(CheckBad(CheckStore(symbols: store.symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, uses: store.uses, diagnostics: diagnostics)))
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
        let symbol = SymbolRec(kind: node.kind, node: node_id, source: node.source, name_start: node.name_start, name_end: node.name_end, type_arity: symbol_arity(parse, node))
        let symbols = try __s0_buffer_append(SymbolRec, d, store.symbols, symbol)
        store = CheckStore(symbols: symbols, type_params: store.type_params, types: store.types, type_args: store.type_args, uses: store.uses, diagnostics: store.diagnostics)
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
    return Ok(CheckGood(CheckStore(symbols: store.symbols, type_params: params, types: store.types, type_args: store.type_args, uses: store.uses, diagnostics: store.diagnostics)))
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

fn append_checked_type(d: Domain, store: CheckStore, kind: U64, syntax: U64, target: U64, first_arg: U64, arg_count: U64) -> Result(CheckStore, __s0_Error) {
    let types = try __s0_buffer_append(CheckedTypeRec, d, store.types, CheckedTypeRec(kind: kind, syntax: syntax, target: target, first_arg: first_arg, arg_count: arg_count))
    return Ok(CheckStore(symbols: store.symbols, type_params: store.type_params, types: types, type_args: store.type_args, uses: store.uses, diagnostics: store.diagnostics))
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
    while at < __s0_buffer_len(CheckedTypeRec, store.types) {
        if __s0_buffer_get(CheckedTypeRec, store.types, at).syntax == syntax { return at + 1 }
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
    return Ok(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: args, uses: current.uses, diagnostics: current.diagnostics))
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
        let start = __s0_buffer_len(U64, current.type_args)
        let recorded = try record_arg_links(d, parse, current, node.children)
        let appended = try append_checked_type(d, recorded, 8, node_id, 0, start + 1, 1)
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        let child = __s0_buffer_get(U64, appended.type_args, start)
        if try interpreted_contains_reference(d, appended, empty, child, 0, boundary) { return check_fail(d, appended, 10, type_diag_node(state, parse, __s0_buffer_get(CheckedTypeRec, appended.types, __s0_buffer_len(CheckedTypeRec, appended.types) - 1)), 0, 0, 0) }
        return Ok(CheckGood(appended))
    }
    if node.kind == 4 {
        let builtin = builtin_type_kind(state, node)
        if builtin != 0 { return Ok(CheckGood(try append_checked_type(d, store, builtin, node_id, 0, 0, 0))) }
        let param = find_type_param(state, store, owner, node)
        if param != 0 { return Ok(CheckGood(try append_checked_type(d, store, 6, node_id, param, 0, 0))) }
        let symbol = find_declared_type(state, store, node)
        if symbol == 0 { return check_fail(d, store, 4, node, 0, 0, 0) }
        if __s0_buffer_get(SymbolRec, store.symbols, symbol - 1).type_arity != 0 { return check_fail(d, store, 5, node, 0, 0, 0) }
        let appended = try append_checked_type(d, store, 7, node_id, symbol, 0, 0)
        let checked_id = __s0_buffer_len(CheckedTypeRec, appended.types)
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, type_diag_node(state, parse, __s0_buffer_get(CheckedTypeRec, appended.types, checked_id - 1)), boundary)
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
    let start = __s0_buffer_len(U64, current.type_args)
    let recorded = try record_arg_links(d, parse, current, node.children)
    var first: U64 = 0
    if count != 0 { first = start + 1 }
    let appended = try append_checked_type(d, recorded, kind, node_id, target, first, count)
    let checked_id = __s0_buffer_len(CheckedTypeRec, appended.types)
    let checked = __s0_buffer_get(CheckedTypeRec, appended.types, checked_id - 1)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    if kind == 13 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let child = __s0_buffer_get(U64, appended.type_args, first - 1)
        if try interpreted_contains_reference(d, appended, empty, child, 0, boundary) { return check_fail(d, appended, 11, type_diag_node(state, parse, checked), 0, 0, 0) }
    }
    if kind == 11 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        let key = __s0_buffer_get(U64, appended.type_args, first - 1)
        let value = __s0_buffer_get(U64, appended.type_args, first)
        if !(try interpreted_map_key_ok(d, state, parse, appended, empty, key, 0, boundary)) { return check_fail(d, appended, 12, type_diag_node(state, parse, checked), 0, 0, 0) }
        if try interpreted_contains_reference(d, appended, empty, value, 0, boundary) { return check_fail(d, appended, 13, type_diag_node(state, parse, checked), 0, 0, 0) }
    }
    if kind == 7 && try direct_type_concrete(d, appended, empty, checked_id, 0) {
        return validate_concrete_type(d, state, parse, appended, checked_id, 0, type_diag_node(state, parse, checked), boundary)
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
    var use_at: U64 = 0
    while use_at < __s0_buffer_len(DeclTypeUseRec, current.uses) {
        let prior = __s0_buffer_get(DeclTypeUseRec, current.uses, use_at)
        if prior.owner == owner && prior.role == actual_role {
            if (actual_role == 1 || actual_role == 2) && same_name(state, child.source, child.name_start, child.name_end, prior.source, prior.name_start, prior.name_end) {
                var duplicate_kind: U64 = 6
                if actual_role == 2 { duplicate_kind = 7 }
                return check_decl_fail(d, state, parse, current, duplicate_kind, owner)
            }
            actual_ordinal = actual_ordinal + 1
        }
        use_at = use_at + 1
    }
    if child.kind == 9 && child.children == 0 {
        let uses = try __s0_buffer_append(DeclTypeUseRec, d, current.uses, DeclTypeUseRec(owner: owner, role: 2, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: child.name_start, name_end: child.name_end, syntax: 0, checked_type: 0))
        return Ok(CheckGood(CheckStore(symbols: current.symbols, type_params: current.type_params, types: current.types, type_args: current.type_args, uses: uses, diagnostics: current.diagnostics)))
    }
    var syntax = link.node
    if child.kind == 8 || child.kind == 9 || child.kind == 10 || child.kind == 13 {
        let head = __s0_buffer_get(SyntaxLinkRec, parse.links, child.children - 1)
        syntax = head.node
    }
    let resolved = try resolve_type(d, state, parse, current, owner, syntax)
    let next = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    let owner_symbol = __s0_buffer_get(SymbolRec, next.symbols, owner - 1)
    if owner_symbol.kind == 1 || owner_symbol.kind == 12 {
        let checked_id = __s0_buffer_len(CheckedTypeRec, next.types)
        let empty = try __s0_buffer_new(TypeBindingRec, d)
        if try direct_type_concrete(d, next, empty, checked_id, 0) {
            let checked = __s0_buffer_get(CheckedTypeRec, next.types, checked_id - 1)
            let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, type_diag_node(state, parse, checked), 0)
            if match validated {
                CheckGood(value) => false
                CheckBad(value) => true
            } { return Ok(validated) }
        }
    }
    var name_start = child.name_start
    var name_end = child.name_end
    if actual_role == 3 || actual_role == 4 || actual_role == 6 { name_start = 0
        name_end = 0 }
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: actual_role, ordinal: actual_ordinal, node: link.node, source: child.source, name_start: name_start, name_end: name_end, syntax: syntax, checked_type: __s0_buffer_len(CheckedTypeRec, next.types)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, uses: uses, diagnostics: next.diagnostics)))
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
    let resolved = try resolve_type(d, state, parse, current, owner, result_link.node)
    let next = match resolved {
        CheckGood(value) => value
        CheckBad(value) => value
    }
    if match resolved {
        CheckGood(value) => false
        CheckBad(value) => true
    } { return Ok(resolved) }
    let checked_id = __s0_buffer_len(CheckedTypeRec, next.types)
    let empty = try __s0_buffer_new(TypeBindingRec, d)
    if try direct_type_concrete(d, next, empty, checked_id, 0) {
        let checked = __s0_buffer_get(CheckedTypeRec, next.types, checked_id - 1)
        let validated = try validate_concrete_type(d, state, parse, next, checked_id, 0, type_diag_node(state, parse, checked), 0)
        if match validated {
            CheckGood(value) => false
            CheckBad(value) => true
        } { return Ok(validated) }
    }
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: 4, ordinal: 0, node: result_link.node, source: signature.source, name_start: 0, name_end: 0, syntax: result_link.node, checked_type: __s0_buffer_len(CheckedTypeRec, next.types)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, uses: uses, diagnostics: next.diagnostics)))
}

// Materialize aggregate value edges without recursion. Declared applications
// contribute their target and expand that declaration's representation under
// positional bindings, so substitution-introduced cycles are visible. Option,
// Result, and Map expose their arguments; Slice, Ptr, and Buffer cut the walk.
fn collect_cycle_edges(d: Domain, store: CheckStore) -> Result(__s0_Buffer(CycleEdgeRec), __s0_Error) {
    let initial_work = try __s0_buffer_new(CycleWorkRec, d)
    var work = initial_work
    let initial_edges = try __s0_buffer_new(CycleEdgeRec, d)
    var edges = initial_edges
    let initial_bindings = try __s0_buffer_new(TypeBindingRec, d)
    var bindings = initial_bindings
    let initial_ancestry = try __s0_buffer_new(DeclAncestryRec, d)
    var ancestry = initial_ancestry
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
        let norm = normalize_interp(store, bindings, item.checked_type, item.env)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, norm.checked_type - 1)
        if checked.kind == 7 {
            edges = try __s0_buffer_append(CycleEdgeRec, d, edges, CycleEdgeRec(owner: item.owner, target: checked.target))
            if !ancestry_has(ancestry, item.ancestry, checked.target) {
                let old_len = __s0_buffer_len(TypeBindingRec, bindings)
                bindings = try build_target_env(d, store, bindings, checked.target, checked, norm.env)
                let target_env = declaration_env_head(bindings, old_len)
                ancestry = try __s0_buffer_append(DeclAncestryRec, d, ancestry, DeclAncestryRec(target: checked.target, env: target_env, parent: item.ancestry))
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
        if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 {
            var arg_at: U64 = 0
            while arg_at < checked.arg_count {
                let arg = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + arg_at)
                work = try __s0_buffer_append(CycleWorkRec, d, work, CycleWorkRec(owner: item.owner, checked_type: arg, env: norm.env, ancestry: item.ancestry))
                arg_at = arg_at + 1
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
    let edges = try collect_cycle_edges(d, store)
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
                let checked = __s0_buffer_get(CheckedTypeRec, store.types, use.checked_type - 1)
                let validated = try validate_concrete_type(d, state, parse, store, use.checked_type, 0, type_diag_node(state, parse, checked), 0)
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
    return check_declaration_kind(d, state, parse, after_imports, 12)
}

fn check_parsed(d: Domain, state: State, parse: ParseStore, initial: CheckStore) -> Result(CheckResult, __s0_Error) {
    // Orchestration callers invoke this only for ParseGood. Keep the guard so
    // malformed direct callers cannot run checking after either earlier phase.
    if __s0_buffer_len(LexDiagRec, state.diagnostics) != 0 || __s0_buffer_len(ParseDiagRec, parse.diagnostics) != 0 { return Ok(CheckBad(initial)) }
    let symbols = try collect_symbols(d, state, parse, initial)
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
    if !out_string("ALDER-CHECKER-MANIFEST 2\n") || !emit_check_sources(state) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(SymbolRec, store.symbols) {
        let rec = __s0_buffer_get(SymbolRec, store.symbols, at)
        if !out_string("Y ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.kind) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.type_arity) || !out(10) { return false }
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
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let rec = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if !out_string("U ") || !out_u64(at + 1) || !out(32) || !out_u64(rec.owner) || !out(32) || !out_u64(rec.role) || !out(32) || !out_u64(rec.ordinal) || !out(32) || !out_u64(rec.node) || !out(32) || !out_u64(rec.source) || !out(32) || !out_u64(rec.name_start) || !out(32) || !out_u64(rec.name_end) || !out(32) || !out_u64(rec.syntax) || !out(32) || !out_u64(rec.checked_type) || !out(10) { return false }
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
