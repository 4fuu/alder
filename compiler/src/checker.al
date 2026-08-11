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
        return Ok(CheckGood(try append_checked_type(d, recorded, 8, node_id, 0, start + 1, 1)))
    }
    if node.kind == 4 {
        let builtin = builtin_type_kind(state, node)
        if builtin != 0 { return Ok(CheckGood(try append_checked_type(d, store, builtin, node_id, 0, 0, 0))) }
        let param = find_type_param(state, store, owner, node)
        if param != 0 { return Ok(CheckGood(try append_checked_type(d, store, 6, node_id, param, 0, 0))) }
        let symbol = find_declared_type(state, store, node)
        if symbol == 0 { return check_fail(d, store, 4, node, 0, 0, 0) }
        if __s0_buffer_get(SymbolRec, store.symbols, symbol - 1).type_arity != 0 { return check_fail(d, store, 5, node, 0, 0, 0) }
        return Ok(CheckGood(try append_checked_type(d, store, 7, node_id, symbol, 0, 0)))
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
    return Ok(CheckGood(try append_checked_type(d, recorded, kind, node_id, target, first, count)))
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
    let uses = try __s0_buffer_append(DeclTypeUseRec, d, next.uses, DeclTypeUseRec(owner: owner, role: 4, ordinal: 0, node: result_link.node, source: signature.source, name_start: 0, name_end: 0, syntax: result_link.node, checked_type: __s0_buffer_len(CheckedTypeRec, next.types)))
    return Ok(CheckGood(CheckStore(symbols: next.symbols, type_params: next.type_params, types: next.types, type_args: next.type_args, uses: uses, diagnostics: next.diagnostics)))
}

// Materialize aggregate value edges without recursion. A declared application
// contributes only its declaration target; Option, Result, and Map expose their
// direct arguments; every other checked type cuts the value-layout walk.
fn collect_cycle_edges(d: Domain, store: CheckStore) -> Result(__s0_Buffer(CycleEdgeRec), __s0_Error) {
    let initial_work = try __s0_buffer_new(CycleWorkRec, d)
    var work = initial_work
    let initial_edges = try __s0_buffer_new(CycleEdgeRec, d)
    var edges = initial_edges
    var at: U64 = 0
    while at < __s0_buffer_len(DeclTypeUseRec, store.uses) {
        let item = __s0_buffer_get(DeclTypeUseRec, store.uses, at)
        if (item.role == 1 || item.role == 2) && item.checked_type != 0 {
            work = try __s0_buffer_append(CycleWorkRec, d, work, CycleWorkRec(owner: item.owner, checked_type: item.checked_type))
        }
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(CycleWorkRec, work) {
        let item = __s0_buffer_get(CycleWorkRec, work, at)
        let checked = __s0_buffer_get(CheckedTypeRec, store.types, item.checked_type - 1)
        if checked.kind == 7 {
            edges = try __s0_buffer_append(CycleEdgeRec, d, edges, CycleEdgeRec(owner: item.owner, target: checked.target))
        }
        if checked.kind == 9 || checked.kind == 10 || checked.kind == 11 {
            var arg_at: U64 = 0
            while arg_at < checked.arg_count {
                let arg = __s0_buffer_get(U64, store.type_args, checked.first_arg - 1 + arg_at)
                work = try __s0_buffer_append(CycleWorkRec, d, work, CycleWorkRec(owner: item.owner, checked_type: arg))
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
    let imports = try check_declaration_kind(d, state, parse, after_cycles, 1)
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
