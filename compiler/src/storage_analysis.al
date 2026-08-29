// Milestone 7.3 slice 1 storage analysis. This layer owns only the finite
// placement/view constraint solution. Lowering starts consuming StoragePlan in
// slice 2; keeping the boundary explicit prevents analysis from silently
// changing generated MIR before returned-view and copy semantics are complete.

type StorageDomainRec {
    parent: U64
}

type StorageAllocationRec {
    candidate: U64
}

// Exactly one of domain and dependency is nonzero. fallback requests the root
// domain when a precise required lifetime could not be proved; in that case
// both IDs are zero. source is a stable caller-owned identity for diagnostics
// and retention reporting.
type StorageConstraintRec {
    allocation: U64
    domain: U64
    dependency: U64
    fallback: Bool
    source: U64
}

// A view requires its backing allocation to outlive use_domain. invalidated is
// set only when the capability analysis proves an incompatible mutation/reset
// before the use; such a view is rejected rather than repaired by retention.
type StorageViewRec {
    allocation: U64
    parent_view: U64
    use_domain: U64
    invalidated: Bool
    source: U64
}

// issue kinds: 0 valid, 1 malformed domain hierarchy, 2 malformed allocation,
// 3 malformed constraint, 4 malformed view, and 5 invalidated view. issue_index
// is the stable 1-based record ID in the corresponding input table.
type StoragePlan {
    placements: __s0_Buffer(U64)
    valid_views: __s0_Buffer(Bool)
    retained: __s0_Buffer(U64)
    issue_kind: U64
    issue_index: U64
    promotions: U64
}

fn storage_bad(d: Domain, kind: U64, index: U64) -> Result(StoragePlan, __s0_Error) {
    let placements = try __s0_buffer_new(U64, d)
    let views = try __s0_buffer_new(Bool, d)
    let retained = try __s0_buffer_new(U64, d)
    return Ok(StoragePlan(placements: placements, valid_views: views, retained: retained, issue_kind: kind, issue_index: index, promotions: 0))
}

fn storage_domain_ancestor(domains: __s0_Buffer(StorageDomainRec), ancestor: U64, domain: U64) -> Bool {
    var at = domain
    while at != 0 {
        if at == ancestor { return true }
        at = __s0_buffer_get(StorageDomainRec, domains, at - 1).parent
    }
    return false
}

// Return the nearest common ancestor. Validated parent-before-child IDs make
// depth construction linear and exclude cyclic walks.
fn storage_join(domains: __s0_Buffer(StorageDomainRec), depths: __s0_Buffer(U64), left: U64, right: U64) -> U64 {
    var a = left
    var b = right
    while __s0_buffer_get(U64, depths, a) > __s0_buffer_get(U64, depths, b) { a = __s0_buffer_get(StorageDomainRec, domains, a - 1).parent }
    while __s0_buffer_get(U64, depths, b) > __s0_buffer_get(U64, depths, a) { b = __s0_buffer_get(StorageDomainRec, domains, b - 1).parent }
    while a != b {
        a = __s0_buffer_get(StorageDomainRec, domains, a - 1).parent
        b = __s0_buffer_get(StorageDomainRec, domains, b - 1).parent
    }
    return a
}

fn storage_analyze(d: Domain, domains: __s0_Buffer(StorageDomainRec), allocations: __s0_Buffer(StorageAllocationRec), constraints: __s0_Buffer(StorageConstraintRec), views: __s0_Buffer(StorageViewRec)) -> Result(StoragePlan, __s0_Error) {
    let domain_count = __s0_buffer_len(StorageDomainRec, domains)
    let allocation_count = __s0_buffer_len(StorageAllocationRec, allocations)
    if domain_count == 0 { return storage_bad(d, 1, 1) }

    var depths = try __s0_buffer_new(U64, d)
    depths = try __s0_buffer_append(U64, d, depths, 0)
    var at: U64 = 0
    while at < domain_count {
        let item = __s0_buffer_get(StorageDomainRec, domains, at)
        let id = at + 1
        if (id == 1 && item.parent != 0) || (id != 1 && (item.parent == 0 || item.parent >= id)) { return storage_bad(d, 1, id) }
        depths = try __s0_buffer_append(U64, d, depths, __s0_buffer_get(U64, depths, item.parent) + 1)
        at = at + 1
    }

    var placements = try __s0_buffer_new(U64, d)
    at = 0
    while at < allocation_count {
        let item = __s0_buffer_get(StorageAllocationRec, allocations, at)
        if item.candidate == 0 || item.candidate > domain_count { return storage_bad(d, 2, at + 1) }
        placements = try __s0_buffer_append(U64, d, placements, item.candidate)
        at = at + 1
    }

    // Direct lifetime requirements and conservative fallback are applied
    // before dependency propagation, so every worklist edge observes a safe
    // lower bound even when constraints are not topologically ordered.
    var retained = try __s0_buffer_new(U64, d)
    var promotions: U64 = 0
    at = 0
    while at < __s0_buffer_len(StorageConstraintRec, constraints) {
        let item = __s0_buffer_get(StorageConstraintRec, constraints, at)
        let direct = item.domain != 0
        let dependent = item.dependency != 0
        if item.allocation == 0 || item.allocation > allocation_count || (direct && dependent) || (item.fallback && (direct || dependent)) || (!item.fallback && !direct && !dependent) || (direct && item.domain > domain_count) || (dependent && item.dependency > allocation_count) {
            return storage_bad(d, 3, at + 1)
        }
        if direct || item.fallback {
            var required = item.domain
            if item.fallback { required = 1 }
            let old = __s0_buffer_get(U64, placements, item.allocation - 1)
            let joined = storage_join(domains, depths, old, required)
            if joined != old {
                __s0_buffer_set(U64, placements, item.allocation - 1, joined)
                promotions = promotions + 1
            }
            if item.fallback { retained = try __s0_buffer_append(U64, d, retained, item.source) }
        }
        at = at + 1
    }

    var valid_views = try __s0_buffer_new(Bool, d)
    var view_roots = try __s0_buffer_new(U64, d)
    at = 0
    while at < __s0_buffer_len(StorageViewRec, views) {
        let item = __s0_buffer_get(StorageViewRec, views, at)
        let direct = item.allocation != 0
        let derived = item.parent_view != 0
        if (direct && derived) || (!direct && !derived) || (direct && item.allocation > allocation_count) || (derived && item.parent_view >= at + 1) || item.use_domain == 0 || item.use_domain > domain_count { return storage_bad(d, 4, at + 1) }
        if item.invalidated { return storage_bad(d, 5, at + 1) }
        var root = item.allocation
        if derived {
            if !__s0_buffer_get(Bool, valid_views, item.parent_view - 1) { return storage_bad(d, 5, at + 1) }
            root = __s0_buffer_get(U64, view_roots, item.parent_view - 1)
        }
        let old = __s0_buffer_get(U64, placements, root - 1)
        let joined = storage_join(domains, depths, old, item.use_domain)
        if joined != old {
            __s0_buffer_set(U64, placements, root - 1, joined)
            promotions = promotions + 1
        }
        view_roots = try __s0_buffer_append(U64, d, view_roots, root)
        valid_views = try __s0_buffer_append(Bool, d, valid_views, true)
        at = at + 1
    }

    // Index dependency edges by the allocation they observe. Stable counting
    // placement preserves constraint order and avoids rescanning all edges for
    // every worklist item on compiler-scale graphs.
    var edge_count = __s0_alloc(U64, d, allocation_count + 1)
    var edge_start = __s0_alloc(U64, d, allocation_count + 1)
    var edge_cursor = __s0_alloc(U64, d, allocation_count + 1)
    at = 0
    while at <= allocation_count {
        edge_count[at] = 0
        edge_start[at] = 0
        edge_cursor[at] = 0
        at = at + 1
    }
    at = 0
    while at < __s0_buffer_len(StorageConstraintRec, constraints) {
        let edge = __s0_buffer_get(StorageConstraintRec, constraints, at)
        if edge.dependency != 0 { edge_count[edge.dependency] = edge_count[edge.dependency] + 1 }
        at = at + 1
    }
    var edge_total: U64 = 0
    at = 1
    while at <= allocation_count {
        edge_start[at] = edge_total
        edge_cursor[at] = edge_total
        edge_total = edge_total + edge_count[at]
        at = at + 1
    }
    var edge_ids = __s0_alloc(U64, d, edge_total + 1)
    at = 0
    while at < __s0_buffer_len(StorageConstraintRec, constraints) {
        let edge = __s0_buffer_get(StorageConstraintRec, constraints, at)
        if edge.dependency != 0 {
            edge_ids[edge_cursor[edge.dependency]] = at
            edge_cursor[edge.dependency] = edge_cursor[edge.dependency] + 1
        }
        at = at + 1
    }

    // Seed every allocation once. Thereafter a dependency is revisited only
    // when its placement moves outward. in_queue bounds duplicate work while
    // the finite parent lattice bounds successful promotions.
    var queue = try __s0_buffer_new(U64, d)
    var in_queue = __s0_alloc(U64, d, allocation_count + 1)
    in_queue[0] = 0
    at = 1
    while at <= allocation_count {
        queue = try __s0_buffer_append(U64, d, queue, at)
        in_queue[at] = 1
        at = at + 1
    }
    var head: U64 = 0
    while head < __s0_buffer_len(U64, queue) {
        let dependency = __s0_buffer_get(U64, queue, head)
        head = head + 1
        in_queue[dependency] = 0
        var edge_at: U64 = 0
        while edge_at < edge_count[dependency] {
            let edge_id = edge_ids[edge_start[dependency] + edge_at]
            let edge = __s0_buffer_get(StorageConstraintRec, constraints, edge_id)
            let old = __s0_buffer_get(U64, placements, edge.allocation - 1)
            let required = __s0_buffer_get(U64, placements, dependency - 1)
            let joined = storage_join(domains, depths, old, required)
            if joined != old {
                __s0_buffer_set(U64, placements, edge.allocation - 1, joined)
                promotions = promotions + 1
                if in_queue[edge.allocation] == 0 {
                    queue = try __s0_buffer_append(U64, d, queue, edge.allocation)
                    in_queue[edge.allocation] = 1
                }
            }
            edge_at = edge_at + 1
        }
    }

    // View validity is checked against final placements, not an intermediate
    // worklist state. A failure here is an analyzer invariant violation rather
    // than a request for unsafe lowering repair.
    at = 0
    while at < __s0_buffer_len(StorageViewRec, views) {
        let item = __s0_buffer_get(StorageViewRec, views, at)
        let root = __s0_buffer_get(U64, view_roots, at)
        let placement = __s0_buffer_get(U64, placements, root - 1)
        if !storage_domain_ancestor(domains, placement, item.use_domain) { return storage_bad(d, 4, at + 1) }
        at = at + 1
    }
    return Ok(StoragePlan(placements: placements, valid_views: valid_views, retained: retained, issue_kind: 0, issue_index: 0, promotions: promotions))
}
