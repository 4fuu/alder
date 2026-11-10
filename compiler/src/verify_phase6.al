// Phase 6 ports the Go verifier's finite domain/provenance and resource
// lattices over flat MIR IDs. Facts are append-only sets; membership uses a
// full-fact hash and transfer uses dense per-(function, value) chains. Static
// transfer dependencies detect whether a pass added facts to a source whose
// consumer was already visited, avoiding the otherwise mandatory empty pass.
// Function effects use per-function chains and requeue callers when a callee's
// contract grows.
fn mir_v6_fact_dep() -> U64 { return 1 }
fn mir_v6_fact_parent() -> U64 { return 2 }
fn mir_v6_fact_root() -> U64 { return 3 }
fn mir_v6_fact_param() -> U64 { return 4 }
fn mir_v6_effect_destroy() -> U64 { return 1 }
fn mir_v6_effect_reset() -> U64 { return 2 }
fn mir_v6_effect_result_from() -> U64 { return 3 }
fn mir_v6_effect_result_alloc() -> U64 { return 4 }
fn mir_v6_state_dead() -> U64 { return 1 }
fn mir_v6_state_root() -> U64 { return 2 }
fn mir_v6_state_mark() -> U64 { return 3 }

// A durable domain-identity fact for one (function, value) key, stored
// dense: the key folds function and value into one slot index, so records
// carry `key` instead of both fields. `next` links the dedup slot chain of
// a uniform full-tuple hash. The slot must spread facts of one key widely:
// self-compile profiles show keys holding 500+ facts, so a per-key slot
// (key * constant + subbucket) walked 9 hops per probe on average while the
// uniform hash stays at the load factor regardless of key skew.
type MirV6Fact {
    key: U64
    kind: U64
    a: U64
    b: U64
    c: U64
    next: U64
}
type MirV6Effect {
    function: U64
    parameter: U64
    kind: U64
}
type MirV6Analysis {
    facts: __s0_Buffer(MirV6Fact)
    effects: __s0_Buffer(MirV6Effect)
    // fact_key_base[function - 1] is the linearized key offset of the
    // function's first value, so key = fact_key_base[function - 1] + value
    // maps each (function, value) pair to a dense slot in fact_span/fact_pos.
    fact_key_base: __s0_Buffer(U64)
    // fact_span[key] is the start position of key's bucket in fact_pos;
    // fact_span[key + 1] is its end (fact_span has a trailing sentinel).
    fact_span: __s0_Buffer(U64)
    fact_pos: __s0_Buffer(U64)
    // effect_span[function] / effect_span[function + 1] delimit the
    // function's effect bucket in effect_pos (trailing sentinel included).
    effect_span: __s0_Buffer(U64)
    effect_pos: __s0_Buffer(U64)
}
type MirV6Durable {
    facts: __s0_Buffer(MirV6Fact)
    effects: __s0_Buffer(MirV6Effect)
    fact_key_next: __s0_Buffer(U64)
    effect_next: __s0_Buffer(U64)
}
type MirV6RoundIndex {
    stable_fact_count: U64
    fact_key_base: __s0_Buffer(U64)
    fact_span: __s0_Buffer(U64)
    fact_pos: __s0_Buffer(U64)
    effect_span: __s0_Buffer(U64)
    effect_pos: __s0_Buffer(U64)
    fact_key_head: __s0_Buffer(U64)
    fact_key_tail: __s0_Buffer(U64)
    fact_hash_head: __s0_Buffer(U64)
    effect_head: __s0_Buffer(U64)
    effect_tail: __s0_Buffer(U64)
}
type MirV6RoundResult {
    durable: MirV6Durable
    changed: Bool
}
type MirV6StateFact {
    kind: U64
    a: U64
    b: U64
    c: U64
}
type MirV6EntryFact {
    block: U64
    state: MirV6StateFact
}
type MirV6Entries {
    items: __s0_Buffer(MirV6EntryFact)
    next: __s0_Buffer(U64)
    head: __s0_Buffer(U64)
    tail: __s0_Buffer(U64)
}
type MirV6EntryMerge {
    entries: MirV6Entries
    changed: Bool
}
type MirV6ReachFact {
    from: U64
    to: U64
}

// Per-function scratch for the loop-check reachability closure, carried by
// the caller across functions: the matrix words, the pair-list fallback, the
// per-source span, the seen stamps, and the successor BFS queue. Each buffer
// grows to its maximum over functions once and is rewritten in place after.
type MirV6ReachPlan {
    words: __s0_Buffer(U64)
    pairs: __s0_Buffer(MirV6ReachFact)
    span: __s0_Buffer(U64)
    seen: __s0_Buffer(U64)
    queue: __s0_Buffer(U64)
}

type MirV6ReachBuilt {
    reach: MirV6Reachability
    plan: MirV6ReachPlan
}

type MirV6LoopBuilt {
    out: __s0_Buffer(MirVerifyDiagRec)
    plan: MirV6ReachPlan
}

type MirV6Reachability {
    // Matrix representation: bit (from-1, to-1) is ((words[row] >> shift) % 2)
    // with row = (from-1)*row_words + (to-1)/64 and shift = (to-1)%64. Each
    // bit is written once per closure, so the checked add cannot overflow.
    words: __s0_Buffer(U64)
    row_words: U64
    // Pair-list representation: span[from-1] .. span[from] delimit
    // function-local pair indices into pairs, ordered by BFS discovery.
    facts: __s0_Buffer(MirV6ReachFact)
    span: __s0_Buffer(U64)
    use_matrix: Bool
    bcount: U64
}
type MirV6TransferIndex {
    incoming_start: __s0_Buffer(U64)
    incoming_count: __s0_Buffer(U64)
    incoming_sources: __s0_Buffer(U64)
    store_start: __s0_Buffer(U64)
    store_count: __s0_Buffer(U64)
    stores: __s0_Buffer(U64)
    type_free: __s0_Buffer(U64)
}
type MirV6ConsumerIndex {
    head: __s0_Buffer(U64)
    tail: __s0_Buffer(U64)
    target: __s0_Buffer(U64)
    next: __s0_Buffer(U64)
    merged: __s0_Buffer(U64)
    // Per edge: the source's per-key fact-list tail the last time this edge
    // merged. Facts are append-only per key, so an unchanged tail means the
    // merge would add nothing and can be skipped outright.
    source_len: __s0_Buffer(U64)
    // Per edge: the source's fact key, parallel to target. The bucket table
    // below compares it against a probe's key so an edge is only ever
    // returned for its own (key, target) pair.
    edge_key: __s0_Buffer(U64)
    // Open-addressed (key, target) -> first edge, probed by merge_edge so a
    // resume lookup does not walk the per-key chain. Slots hold edge ids or
    // zero; the chain in head/next stays the only iteration order, and the
    // table stores the earliest edge per pair, exactly the edge the former
    // chain walk returned.
    buckets: __s0_Buffer(U64)
    bucket_mask: U64
}

// Result of a merge: the updated durable state plus the last source fact
// position this merge reached, for the caller to record on its resume slot.
type MirV6MergeStep {
    durable: MirV6Durable
    merged: U64
}

fn mir_v6_fact_start(analysis: MirV6Analysis, function: U64, value: U64) -> U64 { let kb = analysis.fact_key_base
if function == 0 || function > __s0_buffer_len(U64, kb) { return 0 }
let key = __s0_buffer_get(U64, kb, function - 1) + value
let span = analysis.fact_span
if key >= __s0_buffer_len(U64, span) - 1 { return 0 }
return __s0_buffer_get(U64, span, key) }
fn mir_v6_fact_end(analysis: MirV6Analysis, function: U64, value: U64) -> U64 { let kb = analysis.fact_key_base
if function == 0 || function > __s0_buffer_len(U64, kb) { return 0 }
let key = __s0_buffer_get(U64, kb, function - 1) + value
let span = analysis.fact_span
if key >= __s0_buffer_len(U64, span) - 1 { return 0 }
return __s0_buffer_get(U64, span, key + 1) }
fn mir_v6_effect_start(analysis: MirV6Analysis, function: U64) -> U64 { let span = analysis.effect_span
if function == 0 || function >= __s0_buffer_len(U64, span) { return 0 }
return __s0_buffer_get(U64, span, function) }
fn mir_v6_effect_end(analysis: MirV6Analysis, function: U64) -> U64 { let span = analysis.effect_span
if function == 0 || function >= __s0_buffer_len(U64, span) { return 0 }
return __s0_buffer_get(U64, span, function + 1) }
fn mir_v6_fact_at(analysis: MirV6Analysis, at: U64) -> MirV6Fact { return __s0_buffer_get(MirV6Fact, analysis.facts, __s0_buffer_get(U64, analysis.fact_pos, at) - 1) }
fn mir_v6_effect_at(analysis: MirV6Analysis, at: U64) -> MirV6Effect { return __s0_buffer_get(MirV6Effect, analysis.effects, __s0_buffer_get(U64, analysis.effect_pos, at) - 1) }

// Rebuilds the fact and effect buckets by walking the durable key and effect
// chains, so the placement matches the chains the add sites maintain and no
// whole-buffer scan is needed.
fn mir_v6_fact_hash(key: U64, kind: U64, a: U64, b: U64, c: U64, buckets: U64) -> U64 {
    // Probes only: the slot picks a bucket, never an iteration order. Each
    // field is reduced by compare rather than division (fields at or above
    // the bucket count are rare), then folded at successive powers of four,
    // so a hash costs no division regardless of bucket count. Each input is
    // reduced before folding: mir_vindex_hash_add requires both operands
    // below the modulus.
    var k = key
    if k >= buckets { k = k % buckets }
    var f = kind
    if f >= buckets { f = f % buckets }
    var x = a
    if x >= buckets { x = x % buckets }
    var y = b
    if y >= buckets { y = y % buckets }
    var z = c
    if z >= buckets { z = z % buckets }
    var hash = mir_vindex_hash_add(k, f, buckets)
    hash = mir_vindex_hash_add(hash, hash, buckets)
    hash = mir_vindex_hash_add(hash, hash, buckets)
    hash = mir_vindex_hash_add(hash, x, buckets)
    hash = mir_vindex_hash_add(hash, hash, buckets)
    hash = mir_vindex_hash_add(hash, hash, buckets)
    hash = mir_vindex_hash_add(hash, y, buckets)
    hash = mir_vindex_hash_add(hash, hash, buckets)
    hash = mir_vindex_hash_add(hash, hash, buckets)
    hash = mir_vindex_hash_add(hash, z, buckets)
    return hash
}

fn mir_v6_live_index_build(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirV6RoundIndex, __s0_Error) {
    let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
    var key_base = try __s0_buffer_new(U64, d)
    var total_keys: U64 = 0
    var function: U64 = 1
    while function <= fcount {
        key_base = try __s0_buffer_append(U64, d, key_base, total_keys)
        total_keys = total_keys + __s0_buffer_get(U64, indexes.value_count, function - 1)
        function = function + 1
    }
    var key_head = try __s0_buffer_new(U64, d)
    var key_tail = try __s0_buffer_new(U64, d)
    var key: U64 = 0
    while key <= total_keys {
        key_head = try __s0_buffer_append(U64, d, key_head, 0)
        key_tail = try __s0_buffer_append(U64, d, key_tail, 0)
        key = key + 1
    }
    // Sixteen buckets per MIR value keeps the final compiler corpus at a
    // load factor near one. The slot comes from the uniform full-tuple
    // hash, so chain length tracks the load factor instead of the skew of
    // any one key's fact count.
    let hash_buckets = total_keys * 16 + 16
    var hash_head = try __s0_buffer_new(U64, d)
    var bucket: U64 = 0
    while bucket < hash_buckets {
        hash_head = try __s0_buffer_append(U64, d, hash_head, 0)
        bucket = bucket + 1
    }
    var effect_head = try __s0_buffer_new(U64, d)
    var effect_tail = try __s0_buffer_new(U64, d)
    function = 0
    while function <= fcount {
        effect_head = try __s0_buffer_append(U64, d, effect_head, 0)
        effect_tail = try __s0_buffer_append(U64, d, effect_tail, 0)
        function = function + 1
    }
    let empty = try __s0_buffer_new(U64, d)
    return Ok(MirV6RoundIndex(stable_fact_count: 0, fact_key_base: key_base, fact_span: empty, fact_pos: empty, effect_span: empty, effect_pos: empty, fact_key_head: key_head, fact_key_tail: key_tail, fact_hash_head: hash_head, effect_head: effect_head, effect_tail: effect_tail))
}

fn mir_v6_finalize(d: Domain, store: MirStore, index: MirV6RoundIndex, durable: MirV6Durable) -> Result(MirV6Analysis, __s0_Error) {
    var fact_span = try __s0_buffer_new(U64, d)
    var fact_pos = try __s0_buffer_new(U64, d)
    var key: U64 = 0
    while key < __s0_buffer_len(U64, index.fact_key_head) {
        fact_span = try __s0_buffer_append(U64, d, fact_span, __s0_buffer_len(U64, fact_pos))
        var fact = __s0_buffer_get(U64, index.fact_key_head, key)
        while fact != 0 {
            fact_pos = try __s0_buffer_append(U64, d, fact_pos, fact)
            fact = __s0_buffer_get(U64, durable.fact_key_next, fact - 1)
        }
        key = key + 1
    }
    fact_span = try __s0_buffer_append(U64, d, fact_span, __s0_buffer_len(U64, fact_pos))
    var effect_span = try __s0_buffer_new(U64, d)
    var effect_pos = try __s0_buffer_new(U64, d)
    var function: U64 = 0
    while function < __s0_buffer_len(U64, index.effect_head) {
        effect_span = try __s0_buffer_append(U64, d, effect_span, __s0_buffer_len(U64, effect_pos))
        var effect = __s0_buffer_get(U64, index.effect_head, function)
        while effect != 0 {
            effect_pos = try __s0_buffer_append(U64, d, effect_pos, effect)
            effect = __s0_buffer_get(U64, durable.effect_next, effect - 1)
        }
        function = function + 1
    }
    effect_span = try __s0_buffer_append(U64, d, effect_span, __s0_buffer_len(U64, effect_pos))
    return Ok(MirV6Analysis(facts: durable.facts, effects: durable.effects, fact_key_base: index.fact_key_base, fact_span: fact_span, fact_pos: fact_pos, effect_span: effect_span, effect_pos: effect_pos))
}

fn mir_v6_round_fact_key(index: MirV6RoundIndex, function: U64, value: U64) -> U64 {
    if function == 0 || function > __s0_buffer_len(U64, index.fact_key_base) { return 0 }
    let base = __s0_buffer_get(U64, index.fact_key_base, function - 1)
    var end = __s0_buffer_len(U64, index.fact_key_head) - 1
    if function < __s0_buffer_len(U64, index.fact_key_base) { end = __s0_buffer_get(U64, index.fact_key_base, function) }
    if value == 0 || value > end - base { return 0 }
    return base + value
}
fn mir_v6_round_fact_start(index: MirV6RoundIndex, function: U64, value: U64) -> U64 {
    let key = mir_v6_round_fact_key(index, function, value)
    if key == 0 { return 0 }
    return __s0_buffer_get(U64, index.fact_key_head, key)
}
fn mir_v6_round_fact_next(durable: MirV6Durable, fact: U64) -> U64 {
    if fact == 0 || fact > __s0_buffer_len(U64, durable.fact_key_next) { return 0 }
    return __s0_buffer_get(U64, durable.fact_key_next, fact - 1)
}
fn mir_v6_round_fact_at(durable: MirV6Durable, at: U64) -> MirV6Fact { return __s0_buffer_get(MirV6Fact, durable.facts, at - 1) }
fn mir_v6_round_effect_start(index: MirV6RoundIndex, function: U64) -> U64 {
    if function == 0 || function >= __s0_buffer_len(U64, index.effect_head) { return 0 }
    return __s0_buffer_get(U64, index.effect_head, function)
}
fn mir_v6_round_effect_next(durable: MirV6Durable, effect: U64) -> U64 {
    if effect == 0 || effect > __s0_buffer_len(U64, durable.effect_next) { return 0 }
    return __s0_buffer_get(U64, durable.effect_next, effect - 1)
}
fn mir_v6_round_effect_at(durable: MirV6Durable, at: U64) -> MirV6Effect { return __s0_buffer_get(MirV6Effect, durable.effects, at - 1) }

fn mir_v6_fact_add(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, value: U64, kind: U64, a: U64, b: U64, c: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
let key = mir_v6_round_fact_key(index, function, value)
if key == 0 { return Ok(durable) }
// Dedup probes a uniform full-tuple hash: the record carries the key, so
// the chain compare is exact, and the slot spreads hot keys' facts across
// the whole head array instead of grouping them by key.
let slot = mir_v6_fact_hash(key, kind, a, b, c, __s0_buffer_len(U64, index.fact_hash_head))
var at = __s0_buffer_get(U64, index.fact_hash_head, slot)
while at != 0 { let x = __s0_buffer_get(MirV6Fact, durable.facts, at - 1)
    if x.key == key && x.kind == kind && x.a == a && x.b == b && x.c == c { return Ok(durable) }
    at = x.next
}
let old_hash = __s0_buffer_get(U64, index.fact_hash_head, slot)
let old_tail = __s0_buffer_get(U64, index.fact_key_tail, key)
durable.facts = try __s0_buffer_append(MirV6Fact, d, durable.facts, MirV6Fact(key: key, kind: kind, a: a, b: b, c: c, next: old_hash))
durable.fact_key_next = try __s0_buffer_append(U64, d, durable.fact_key_next, 0)
let fact = __s0_buffer_len(MirV6Fact, durable.facts)
if old_tail == 0 { __s0_buffer_set(U64, index.fact_key_head, key, fact) }
else { __s0_buffer_set(U64, durable.fact_key_next, old_tail - 1, fact) }
__s0_buffer_set(U64, index.fact_key_tail, key, fact)
__s0_buffer_set(U64, index.fact_hash_head, slot, fact)
return Ok(durable) }
fn mir_v6_effect_has(durable: MirV6Durable, index: MirV6RoundIndex, function: U64, parameter: U64, kind: U64) -> Bool { var at = mir_v6_round_effect_start(index, function)
while at != 0 { let x = mir_v6_round_effect_at(durable, at)
if x.parameter == parameter && x.kind == kind { return true }
at = mir_v6_round_effect_next(durable, at)
}
return false }
fn mir_v6_effect_add(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, parameter: U64, kind: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
if mir_v6_effect_has(durable, index, function, parameter, kind) { return Ok(durable) }
let old_tail = __s0_buffer_get(U64, index.effect_tail, function)
durable.effects = try __s0_buffer_append(MirV6Effect, d, durable.effects, MirV6Effect(function: function, parameter: parameter, kind: kind))
durable.effect_next = try __s0_buffer_append(U64, d, durable.effect_next, 0)
let effect = __s0_buffer_len(MirV6Effect, durable.effects)
if old_tail == 0 { __s0_buffer_set(U64, index.effect_head, function, effect) }
else { __s0_buffer_set(U64, durable.effect_next, old_tail - 1, effect) }
__s0_buffer_set(U64, index.effect_tail, function, effect)
return Ok(durable) }
fn mir_v6_merge_value(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, target: U64, source: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var at = mir_v6_round_fact_start(index, function, source)
let key = mir_v6_round_fact_key(index, function, source)
if key == 0 { return Ok(durable) }
let stop = __s0_buffer_get(U64, index.fact_key_tail, key)
while at != 0 {
    let x = mir_v6_round_fact_at(durable, at)
    let next = mir_v6_round_fact_next(durable, at)
    durable = try mir_v6_fact_add(d, durable, index, function, target, x.kind, x.a, x.b, x.c)
    if at == stop { return Ok(durable) }
    at = next
}
return Ok(durable) }

// Merge `source` into `target`, resuming from the last position an earlier merge
// of the same (function, target, source) reached. The resume state lives on the
// consumer edge for that pair, found by probing the consumer bucket table.
//
// The consumer index is a superset of the merge sites, not an exact mirror:
// mir_v6_consumer_add records x.a for vec_grow_checked where transfer_value
// merges x.b, and an extra x.b edge for copy_to_domain. Both only cost resume
// coverage on those sites. Correctness never depends on coverage — an edge is
// only ever read by a merge with the same (target, source), and any merge of
// that pair is semantically identical.
fn mir_v6_merge_edge(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, consumers: MirV6ConsumerIndex, function: U64, target: U64, source: U64) -> Result(MirV6Durable, __s0_Error) {
    var edge: U64 = 0
    let key = mir_v6_round_fact_key(index, function, source)
    var source_tail: U64 = 0
    if key != 0 { source_tail = __s0_buffer_get(U64, index.fact_key_tail, key) }
    if key != 0 { edge = mir_v6_consumer_edge_find(consumers, key, target) }
    if edge != 0 && source_tail == __s0_buffer_get(U64, consumers.source_len, edge - 1) {
        // The source's fact list has not grown since this edge last merged,
        // so the merge would re-add only facts the target already has.
        return Ok(durable0)
    }
    var after: U64 = 0
    if edge != 0 { after = __s0_buffer_get(U64, consumers.merged, edge - 1) }
    let step = try mir_v6_merge_from(d, durable0, index, function, target, source, after)
    if edge != 0 {
        __s0_buffer_set(U64, consumers.merged, edge - 1, step.merged)
        __s0_buffer_set(U64, consumers.source_len, edge - 1, source_tail)
    }
    return Ok(step.durable)
}

fn mir_v6_merge_from(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, target: U64, source: U64, after: U64) -> Result(MirV6MergeStep, __s0_Error) {
    var durable = durable0
    let key = mir_v6_round_fact_key(index, function, source)
    if key == 0 { return Ok(MirV6MergeStep(durable: durable, merged: 0)) }
    let stop = __s0_buffer_get(U64, index.fact_key_tail, key)
    var at = mir_v6_round_fact_start(index, function, source)
    var merged: U64 = 0
    while at != 0 && at <= after {
        merged = at
        at = mir_v6_round_fact_next(durable, at)
    }
    while at != 0 {
        let x = mir_v6_round_fact_at(durable, at)
        let next = mir_v6_round_fact_next(durable, at)
        durable = try mir_v6_fact_add(d, durable, index, function, target, x.kind, x.a, x.b, x.c)
        merged = at
        if at == stop { return Ok(MirV6MergeStep(durable: durable, merged: merged)) }
        at = next
    }
    return Ok(MirV6MergeStep(durable: durable, merged: merged))
}

fn mir_v6_type_contains(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64, wanted: U64) -> Result(Bool, __s0_Error) {
    // The answer per (type id, kind) pair is a pure function of the frozen
    // type graph; the memo fills the dense per-kind columns on demand, so
    // results are unchanged while repeat walks and their per-call scratch
    // allocations disappear.
    return mir_vmemo_contains(d, store, indexes, root, wanted) }
fn mir_v6_type_reference(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_slice()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_vec()) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) }
// mir_v6_env_record reports whether the type is an aggregate used as a
// fn.value environment. Such a record records the domain that owns it, and
// the retain hook rewrites that field when the record moves domains, so its
// domain handle is safe behind the dereference store that installs it.
fn mir_v6_env_record(store: MirStore, indexes: MirVIndexes, type_id: U64) -> Bool {
    // Only an aggregate whose first field is a domain handle can be an
    // environment record, so every other type answers without a scan.
    if type_id < 1 || type_id > __s0_buffer_len(MirTypeRec, store.types) { return false }
    if __s0_buffer_get(MirTypeRec, store.types, type_id - 1).kind != mir_type_kind_aggregate() { return false }
    if mir_vindex_type_part_count(indexes, type_id) < 1 { return false }
    let first_id = mir_vindex_type_part(indexes, type_id, 0)
    if first_id == 0 || first_id > __s0_buffer_len(MirTypePartRec, store.type_parts) { return false }
    let first = __s0_buffer_get(MirTypePartRec, store.type_parts, first_id - 1)
    if first.part_type < 1 || first.part_type > __s0_buffer_len(MirTypeRec, store.types) { return false }
    if __s0_buffer_get(MirTypeRec, store.types, first.part_type - 1).kind != mir_type_kind_domain_handle() { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(MirInstrRec, store.instructions) {
        let item = __s0_buffer_get(MirInstrRec, store.instructions, at)
        if item.op == mir_op_fn_value() && item.a != 0 {
            let env_type = mir_v5_value_type(store, indexes, item.function, item.a)
            if env_type >= 1 && env_type <= __s0_buffer_len(MirTypeRec, store.types) {
                let env = __s0_buffer_get(MirTypeRec, store.types, env_type - 1)
                if env.kind == mir_type_kind_safe_ref() || env.kind == mir_type_kind_safe_mut() || env.kind == mir_type_kind_slice() {
                    if env.elem == type_id { return true }
                }
            }
        }
        at = at + 1
    }
    return false
}

fn mir_v6_type_local_store(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { let env_record = mir_v6_env_record(store, indexes, type_id)
if !env_record && try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if !env_record && try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if !env_record && try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_slice()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_handle()) && !mir_v6_env_record(store, indexes, type_id) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_mark()) }

fn mir_v6_instruction_for_value(store: MirStore, indexes: MirVIndexes, value: MirValueRec) -> U64 { if value.def_kind != mir_value_def_instruction() { return 0 }
return mir_vindex_instr(indexes, value.function, value.block, value.item - 1) }
fn mir_v6_function_param_ordinal(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, at) - 1)
        if p.kind == mir_param_function() && p.value == value { return p.ordinal + 1 }
        at = at + 1
    }
    return 0
}
fn mir_v6_operand_value(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 { let oi = mir_v5_operand(store, indexes, kind, owner, edge, ordinal)
if oi == 0 { return 0 }
return __s0_buffer_get(MirOperandRec, store.operands, oi - 1).value }
fn mir_v6_place_deref(store: MirStore, place: U64) -> Bool { var p = place
while p != 0 { let x = __s0_buffer_get(MirPlaceRec, store.places, p - 1)
if x.kind == mir_place_deref() { return true }
if x.kind != mir_place_field() { return false }
p = x.base }
return false }
fn mir_v6_places_alias(store: MirStore, indexes: MirVIndexes, a: U64, ad: Bool, ar: U64, an: U64, b: U64) -> Bool { let bd = mir_vindex_place_deref(indexes, b)
if ad || bd { return ad && bd }
if ar != __s0_buffer_get(U64, indexes.place_root, b - 1) { return false }
let bn = mir_vindex_place_depth(indexes, b)
var n: U64 = 0
var limit = an
if bn < limit { limit = bn }
while n < limit { let ap = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, a, n) - 1)
let bp = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, b, n) - 1)
if !mir_vname_equal(store, ap.field_start, ap.field_end, bp.field_start, bp.field_end) { return false }
n = n + 1 }
return true }

fn mir_v6_block_param_record(store: MirStore, indexes: MirVIndexes, function: U64, block: U64, ordinal: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, function, at)
        let parameter = __s0_buffer_get(MirParamRec, store.params, id - 1)
        if parameter.kind == mir_param_block() && parameter.block == block && parameter.ordinal == ordinal { return id }
        at = at + 1
    }
    return 0
}

fn mir_v6_incoming_parameter(store: MirStore, indexes: MirVIndexes, operand: MirOperandRec) -> U64 {
    var function: U64 = 0
    if operand.kind == mir_operand_checked_edge_arg() && operand.owner >= 1 && operand.owner <= __s0_buffer_len(MirInstrRec, store.instructions) {
        function = __s0_buffer_get(MirInstrRec, store.instructions, operand.owner - 1).function
    }
    if operand.kind == mir_operand_terminator_arg() && operand.owner >= 1 && operand.owner <= __s0_buffer_len(MirTermRec, store.terminators) {
        function = __s0_buffer_get(MirTermRec, store.terminators, operand.owner - 1).function
    }
    if operand.kind == mir_operand_switch_case_arg() && operand.owner >= 1 && operand.owner <= __s0_buffer_len(MirOperandRec, store.operands) {
        let case = __s0_buffer_get(MirOperandRec, store.operands, operand.owner - 1)
        if case.kind == mir_operand_switch_case() && case.owner >= 1 && case.owner <= __s0_buffer_len(MirTermRec, store.terminators) {
            function = __s0_buffer_get(MirTermRec, store.terminators, case.owner - 1).function
        }
    }
    if function == 0 { return 0 }
    return mir_v6_block_param_record(store, indexes, function, operand.target, operand.ordinal)
}

// Per-type provenance freedom: a value of such a type carries no storage-
// domain provenance at all, because it contains no slice, view, reference,
// pointer, handle, vec, table, string, bytes, or function part at any depth.
// Loading such a value copies plain bits with no lifetime tie to the storage
// it was read from, so the load transfer below skips the domain merges for
// it. Composite kinds start optimistic and the fixpoint propagates zeroes,
// which also converges on cyclic type graphs.
fn mir_v6_provenance_free_types(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(__s0_Buffer(U64), __s0_Error) {
    let total = __s0_buffer_len(MirTypeRec, store.types)
    var free = try __s0_buffer_new(U64, d)
    var t: U64 = 1
    while t <= total {
        let typ = __s0_buffer_get(MirTypeRec, store.types, t - 1)
        var seed: U64 = 1
        if typ.kind == mir_type_kind_slice() || typ.kind == mir_type_kind_vec() || typ.kind == mir_type_kind_safe_ref() || typ.kind == mir_type_kind_safe_mut() || typ.kind == mir_type_kind_raw_ptr() || typ.kind == mir_type_kind_table() || typ.kind == mir_type_kind_id() || typ.kind == mir_type_kind_table_view() || typ.kind == mir_type_kind_table_mut_view() || typ.kind == mir_type_kind_function() || typ.kind == mir_type_kind_string() || typ.kind == mir_type_kind_bytes() || typ.kind == mir_type_kind_domain_handle() || typ.kind == mir_type_kind_domain_mark() || typ.kind == mir_type_kind_cleanup_scope() || typ.kind == mir_type_kind_cleanup_id() { seed = 0 }
        free = try __s0_buffer_append(U64, d, free, seed)
        t = t + 1
    }
    var changed = true
    while changed {
        changed = false
        t = 1
        while t <= total {
            if __s0_buffer_get(U64, free, t - 1) != 0 {
                let typ = __s0_buffer_get(MirTypeRec, store.types, t - 1)
                var still = true
                if typ.kind == mir_type_kind_option() || typ.kind == mir_type_kind_array() {
                    if typ.elem != 0 && typ.elem <= total && __s0_buffer_get(U64, free, typ.elem - 1) == 0 { still = false }
                }
                if typ.kind == mir_type_kind_result() {
                    if typ.ok_type != 0 && typ.ok_type <= total && __s0_buffer_get(U64, free, typ.ok_type - 1) == 0 { still = false }
                    if typ.err_type != 0 && typ.err_type <= total && __s0_buffer_get(U64, free, typ.err_type - 1) == 0 { still = false }
                }
                if typ.kind == mir_type_kind_aggregate() || typ.kind == mir_type_kind_enum() {
                    var kind = mir_type_part_variant()
                    if typ.kind == mir_type_kind_aggregate() { kind = mir_type_part_field() }
                    let count = mir_vindex_type_part_count(indexes, t)
                    var at: U64 = 0
                    while at < count {
                        let pid = mir_vindex_type_part(indexes, t, at)
                        let part = __s0_buffer_get(MirTypePartRec, store.type_parts, pid - 1)
                        if part.kind == kind && part.part_type != 0 && part.part_type <= total && __s0_buffer_get(U64, free, part.part_type - 1) == 0 { still = false }
                        at = at + 1
                    }
                }
                if !still {
                    __s0_buffer_set(U64, free, t - 1, 0)
                    changed = true
                }
            }
            t = t + 1
        }
    }
    return Ok(free)
}

fn mir_v6_transfer_index_build(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirV6TransferIndex, __s0_Error) {
    var store_start = try __s0_buffer_new(U64, d)
    var store_count = try __s0_buffer_new(U64, d)
    var store_ids = try __s0_buffer_new(U64, d)
    var incoming_ids = try __s0_buffer_new(U64, d)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        let first = __s0_buffer_len(U64, store_ids)
        store_start = try __s0_buffer_append(U64, d, store_start, first)
        let bcount = mir_vindex_block_count(indexes, function)
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ordinal: U64 = 0
            while ordinal < icount {
                let iid = mir_vindex_instr(indexes, function, block, ordinal)
                if __s0_buffer_get(MirInstrRec, store.instructions, iid - 1).op == mir_op_store() { store_ids = try __s0_buffer_append(U64, d, store_ids, iid) }
                let total = mir_vindex_op_instr_count(indexes, iid)
                var oi: U64 = 0
                while oi < total {
                    let operand_id = mir_vindex_op_instr(indexes, iid, oi)
                    if __s0_buffer_get(MirOperandRec, store.operands, operand_id - 1).kind == mir_operand_checked_edge_arg() { incoming_ids = try __s0_buffer_append(U64, d, incoming_ids, operand_id) }
                    oi = oi + 1
                }
                ordinal = ordinal + 1
            }
            let term_id = mir_vindex_term(indexes, function, block)
            if term_id != 0 {
                let total = mir_vindex_op_term_count(indexes, term_id)
                var oi: U64 = 0
                while oi < total {
                    let operand_id = mir_vindex_op_term(indexes, term_id, oi)
                    let operand = __s0_buffer_get(MirOperandRec, store.operands, operand_id - 1)
                    if operand.kind == mir_operand_terminator_arg() { incoming_ids = try __s0_buffer_append(U64, d, incoming_ids, operand_id) }
                    oi = oi + 1
                }
                var ci: U64 = 0
                while ci < total {
                    let case_id = mir_vindex_op_term(indexes, term_id, ci)
                    let case = __s0_buffer_get(MirOperandRec, store.operands, case_id - 1)
                    if case.kind == mir_operand_switch_case() {
                        let arg_total = mir_vindex_op_case_count(indexes, case_id)
                        var ai: U64 = 0
                        while ai < arg_total {
                            incoming_ids = try __s0_buffer_append(U64, d, incoming_ids, mir_vindex_op_case(indexes, case_id, ai))
                            ai = ai + 1
                        }
                    }
                    ci = ci + 1
                }
            }
            block = block + 1
        }
        store_count = try __s0_buffer_append(U64, d, store_count, __s0_buffer_len(U64, store_ids) - first)
        function = function + 1
    }
    let param_total = __s0_buffer_len(MirParamRec, store.params)
    var counts = __s0_alloc(U64, d, param_total + 1)
    var starts = __s0_alloc(U64, d, param_total + 1)
    var cursor = __s0_alloc(U64, d, param_total + 1)
    var p: U64 = 0
    while p <= param_total { counts[p] = 0
        starts[p] = 0
        cursor[p] = 0
        p = p + 1 }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, incoming_ids) {
        let parameter = mir_v6_incoming_parameter(store, indexes, __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, incoming_ids, at) - 1))
        if parameter != 0 { counts[parameter] = counts[parameter] + 1 }
        at = at + 1
    }
    var running: U64 = 0
    p = 1
    while p <= param_total { starts[p] = running
        cursor[p] = running
        running = running + counts[p]
        p = p + 1 }
    var sources = __s0_alloc(U64, d, running)
    at = 0
    while at < __s0_buffer_len(U64, incoming_ids) {
        let operand = __s0_buffer_get(MirOperandRec, store.operands, __s0_buffer_get(U64, incoming_ids, at) - 1)
        let parameter = mir_v6_incoming_parameter(store, indexes, operand)
        if parameter != 0 { sources[cursor[parameter]] = operand.value
            cursor[parameter] = cursor[parameter] + 1 }
        at = at + 1
    }
    var incoming_start = try __s0_buffer_new(U64, d)
    var incoming_count = try __s0_buffer_new(U64, d)
    var incoming_sources = try __s0_buffer_new(U64, d)
    p = 1
    while p <= param_total {
        incoming_start = try __s0_buffer_append(U64, d, incoming_start, starts[p])
        incoming_count = try __s0_buffer_append(U64, d, incoming_count, counts[p])
        var source: U64 = 0
        while source < counts[p] {
            incoming_sources = try __s0_buffer_append(U64, d, incoming_sources, sources[starts[p] + source])
            source = source + 1
        }
        p = p + 1
    }
    var type_free = try mir_v6_provenance_free_types(d, store, indexes)
    return Ok(MirV6TransferIndex(incoming_start: incoming_start, incoming_count: incoming_count, incoming_sources: incoming_sources, store_start: store_start, store_count: store_count, stores: store_ids, type_free: type_free))
}

fn mir_v6_consumer_add(d: Domain, index: MirV6RoundIndex, consumers0: MirV6ConsumerIndex, function: U64, source: U64, target: U64) -> Result(MirV6ConsumerIndex, __s0_Error) {
    var consumers = consumers0
    let key = mir_v6_round_fact_key(index, function, source)
    if key == 0 || target == 0 { return Ok(consumers) }
    let old_tail = __s0_buffer_get(U64, consumers.tail, key)
    consumers.target = try __s0_buffer_append(U64, d, consumers.target, target)
    consumers.next = try __s0_buffer_append(U64, d, consumers.next, 0)
    consumers.merged = try __s0_buffer_append(U64, d, consumers.merged, 0)
    consumers.source_len = try __s0_buffer_append(U64, d, consumers.source_len, 0)
    consumers.edge_key = try __s0_buffer_append(U64, d, consumers.edge_key, key)
    let edge = __s0_buffer_len(U64, consumers.target)
    if old_tail == 0 { __s0_buffer_set(U64, consumers.head, key, edge) }
    else { __s0_buffer_set(U64, consumers.next, old_tail - 1, edge) }
    __s0_buffer_set(U64, consumers.tail, key, edge)
    consumers = try mir_v6_consumer_bucket_add(d, consumers, edge)
    return Ok(consumers)
}

// Slot hash for a (key, target) pair. Consecutive edges are inserted with
// nearly consecutive keys and targets, so a fold taken directly mod the power-
// of-two bucket count clusters their slots into long probe runs (multiplied by
// the rebuild at each resize). Each field is therefore multiplied by a fixed
// constant modulo the prime 2^32-5 first: the wide prime modulus spreads a
// consecutive-value step over the whole residue range, and reducing afterwards
// keeps the slots uniform. The multiply is a double-and-add over the constant's
// bits using only the wrapping modular add, since plain Alder multiplication
// is overflow-checked.
fn mir_v6_edge_scatter(value: U64, mult: U64, buckets: U64) -> U64 {
    var term = value % buckets
    var result: U64 = 0
    var m = mult
    while m != 0 {
        if m % 2 == 1 { result = mir_vindex_hash_add(result, term, buckets) }
        term = mir_vindex_hash_add(term, term, buckets)
        m = m / 2
    }
    return result
}

fn mir_v6_edge_pair_hash(key: U64, target: U64, buckets: U64) -> U64 {
    let prime: U64 = 4294967291
    let sk = mir_v6_edge_scatter(key, 2654435761, prime)
    let st = mir_v6_edge_scatter(target, 362437, prime)
    return (sk + st) % buckets
}

// Place one edge in the bucket table. The first edge for a pair wins, which is
// the earliest in the per-key chain and exactly the edge the former chain walk
// returned. The table always keeps at least one empty slot, so the probe stops.
fn mir_v6_consumer_bucket_place(consumers: MirV6ConsumerIndex, edge: U64) -> MirV6ConsumerIndex {
    let bucket_count = consumers.bucket_mask + 1
    let key = __s0_buffer_get(U64, consumers.edge_key, edge - 1)
    let target = __s0_buffer_get(U64, consumers.target, edge - 1)
    var slot = mir_v6_edge_pair_hash(key, target, bucket_count)
    var placed = false
    while !placed {
        let cur = __s0_buffer_get(U64, consumers.buckets, slot)
        if cur == 0 {
            __s0_buffer_set(U64, consumers.buckets, slot, edge)
            placed = true
        } else {
            if __s0_buffer_get(U64, consumers.edge_key, cur - 1) == key && __s0_buffer_get(U64, consumers.target, cur - 1) == target { placed = true }
            else { slot = mir_vindex_hash_add(slot, 1, bucket_count) }
        }
    }
    return consumers
}

// Grow the bucket table when the load would pass three quarters, then place
// the new edge. A rebuild re-places every edge in insertion order, so the
// first edge per pair stays the first.
fn mir_v6_consumer_bucket_add(d: Domain, consumers0: MirV6ConsumerIndex, edge: U64) -> Result(MirV6ConsumerIndex, __s0_Error) {
    var consumers = consumers0
    let count = __s0_buffer_len(U64, consumers.target)
    let bucket_count = consumers.bucket_mask + 1
    if bucket_count == 0 || count * 4 > bucket_count * 3 {
        var want: U64 = 64
        while want * 3 < count * 4 { want = want * 2 }
        let old_len = __s0_buffer_len(U64, consumers.buckets)
        var at = old_len
        while at < want { consumers.buckets = try __s0_buffer_append(U64, d, consumers.buckets, 0)
            at = at + 1 }
        var z: U64 = 0
        while z < want { __s0_buffer_set(U64, consumers.buckets, z, 0)
            z = z + 1 }
        consumers.bucket_mask = want - 1
        var e: U64 = 1
        while e <= count { consumers = mir_v6_consumer_bucket_place(consumers, e)
            e = e + 1 }
        return Ok(consumers)
    }
    return Ok(mir_v6_consumer_bucket_place(consumers, edge))
}

// The first edge whose (key, target) pair matches the probe, or zero. The
// answer equals the former chain walk's first match because the table keeps
// the earliest edge per pair.
fn mir_v6_consumer_edge_find(consumers: MirV6ConsumerIndex, key: U64, target: U64) -> U64 {
    if __s0_buffer_len(U64, consumers.buckets) == 0 { return 0 }
    let bucket_count = consumers.bucket_mask + 1
    var slot = mir_v6_edge_pair_hash(key, target, bucket_count)
    var result: U64 = 0
    var probing = true
    while probing {
        let cur = __s0_buffer_get(U64, consumers.buckets, slot)
        if cur == 0 { probing = false }
        else {
            if __s0_buffer_get(U64, consumers.edge_key, cur - 1) == key && __s0_buffer_get(U64, consumers.target, cur - 1) == target { result = cur
                probing = false }
            else { slot = mir_vindex_hash_add(slot, 1, bucket_count) }
        }
    }
    return result
}

fn mir_v6_consumer_index_build(d: Domain, store: MirStore, indexes: MirVIndexes, transfer: MirV6TransferIndex, round: MirV6RoundIndex) -> Result(MirV6ConsumerIndex, __s0_Error) {
    var head = try __s0_buffer_new(U64, d)
    var tail = try __s0_buffer_new(U64, d)
    var key: U64 = 0
    while key < __s0_buffer_len(U64, round.fact_key_head) {
        head = try __s0_buffer_append(U64, d, head, 0)
        tail = try __s0_buffer_append(U64, d, tail, 0)
        key = key + 1
    }
    var consumers = MirV6ConsumerIndex(head: head, tail: tail, target: try __s0_buffer_new(U64, d), next: try __s0_buffer_new(U64, d), merged: try __s0_buffer_new(U64, d), source_len: try __s0_buffer_new(U64, d), edge_key: try __s0_buffer_new(U64, d), buckets: try __s0_buffer_new(U64, d), bucket_mask: 0)
    var function: U64 = 1
    while function <= __s0_buffer_len(MirFunctionRec, store.functions) {
        var value_id: U64 = 1
        var vi = mir_vindex_value(indexes, function, value_id)
        while vi != 0 {
            let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
            if value.def_kind == mir_value_def_block_param() {
                let parameter = mir_v6_block_param_record(store, indexes, function, value.block, value.item - 1)
                if parameter != 0 {
                    let start = __s0_buffer_get(U64, transfer.incoming_start, parameter - 1)
                    let count = __s0_buffer_get(U64, transfer.incoming_count, parameter - 1)
                    var incoming: U64 = 0
                    while incoming < count {
                        consumers = try mir_v6_consumer_add(d, round, consumers, function, __s0_buffer_get(U64, transfer.incoming_sources, start + incoming), value_id)
                        incoming = incoming + 1
                    }
                }
            }
            if value.def_kind == mir_value_def_switch_case() {
                let term_id = mir_vindex_term(indexes, function, value.block)
                if term_id != 0 { consumers = try mir_v6_consumer_add(d, round, consumers, function, __s0_buffer_get(MirTermRec, store.terminators, term_id - 1).value, value_id) }
            }
            let iid = mir_v6_instruction_for_value(store, indexes, value)
            if iid != 0 {
                let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if x.op == mir_op_domain_create() || x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_array_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() || (x.op >= mir_op_vec_construct_checked() && x.op <= mir_op_vec_as_mut_slice()) || x.op == mir_op_array_as_slice() {
                    consumers = try mir_v6_consumer_add(d, round, consumers, function, x.a, value_id)
                }
                if x.op == mir_op_copy_to_domain() { consumers = try mir_v6_consumer_add(d, round, consumers, function, x.b, value_id) }
                if x.op == mir_op_table_insert_try() { consumers = try mir_v6_consumer_add(d, round, consumers, function, x.b, value_id) }
                if x.op == mir_op_load() {
                    let place = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
                    if place.kind == mir_place_deref() { consumers = try mir_v6_consumer_add(d, round, consumers, function, place.deref_value, value_id) }
                    let first_store = __s0_buffer_get(U64, transfer.store_start, function - 1)
                    let store_count = __s0_buffer_get(U64, transfer.store_count, function - 1)
                    let load_deref = mir_vindex_place_deref(indexes, x.place)
                    let load_root = __s0_buffer_get(U64, indexes.place_root, x.place - 1)
                    let load_depth = mir_vindex_place_depth(indexes, x.place)
                    var store_at: U64 = 0
                    while store_at < store_count {
                        let store_id = __s0_buffer_get(U64, transfer.stores, first_store + store_at)
                        let placed = __s0_buffer_get(MirInstrRec, store.instructions, store_id - 1)
                        if mir_v6_places_alias(store, indexes, x.place, load_deref, load_root, load_depth, placed.place) { consumers = try mir_v6_consumer_add(d, round, consumers, function, placed.a, value_id) }
                        store_at = store_at + 1
                    }
                }
                if x.op == mir_op_aggregate_construct() {
                    let total = mir_vindex_op_instr_count(indexes, iid)
                    var operand_at: U64 = 0
                    while operand_at < total {
                        let operand = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, operand_at) - 1)
                        if operand.kind == mir_operand_aggregate_field() { consumers = try mir_v6_consumer_add(d, round, consumers, function, operand.value, value_id) }
                        operand_at = operand_at + 1
                    }
                }
                if x.op == mir_op_call() {
                    let total = mir_vindex_op_instr_count(indexes, iid)
                    var operand_at: U64 = 0
                    while operand_at < total {
                        let operand = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, operand_at) - 1)
                        if operand.kind == mir_operand_instruction() { consumers = try mir_v6_consumer_add(d, round, consumers, function, operand.value, value_id) }
                        operand_at = operand_at + 1
                    }
                }
            }
            value_id = value_id + 1
            vi = mir_vindex_value(indexes, function, value_id)
        }
        function = function + 1
    }
    return Ok(consumers)
}

fn mir_v6_transfer_value(d: Domain, store: MirStore, indexes: MirVIndexes, transfer: MirV6TransferIndex, index: MirV6RoundIndex, consumers: MirV6ConsumerIndex, durable0: MirV6Durable, function: U64, value_id: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
let vi = mir_vindex_value(indexes, function, value_id)
let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if value.def_kind == mir_value_def_function_param() { let parameter = mir_v6_function_param_ordinal(store, indexes, function, value_id)
durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_param(), parameter, 0, 0)
if try mir_v6_type_reference(d, store, indexes, value.value_type) { let pcount = mir_vindex_param_count(indexes, function)
var pi: U64 = 0
while pi < pcount { let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, pi) - 1)
if p.kind == mir_param_function() && mir_vtype_kind(store, p.param_type) == mir_type_kind_domain_handle() { durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_dep(), 0, p.ordinal + 1, 0) }
pi = pi + 1 }
durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_root(), value_id, 0, parameter) }
if mir_vtype_kind(store, value.value_type) == mir_type_kind_domain_handle() { durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_dep(), 0, parameter, 0) }
return Ok(durable) }
if value.def_kind == mir_value_def_block_param() {
    let parameter = mir_v6_block_param_record(store, indexes, function, value.block, value.item - 1)
    if parameter != 0 {
        let start = __s0_buffer_get(U64, transfer.incoming_start, parameter - 1)
        let count = __s0_buffer_get(U64, transfer.incoming_count, parameter - 1)
        var incoming: U64 = 0
        while incoming < count {
            durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, __s0_buffer_get(U64, transfer.incoming_sources, start + incoming))
            incoming = incoming + 1
        }
    }
    return Ok(durable)
}
if value.def_kind == mir_value_def_switch_case() { let term_id = mir_vindex_term(indexes, function, value.block)
if term_id != 0 { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, t.value) }
return Ok(durable) }
let iid = mir_v6_instruction_for_value(store, indexes, value)
if iid == 0 { return Ok(durable) }
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_domain_create() { var at = mir_v6_round_fact_start(index, function, x.a)
while at != 0 { let f = mir_v6_round_fact_at(durable, at)
if f.kind == mir_v6_fact_dep() || f.kind == mir_v6_fact_parent() { durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_parent(), f.a, f.b, f.c) }
at = mir_v6_round_fact_next(durable, at) }
durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_dep(), x.block, x.ordinal + 1, 0) }
// A cross-domain copy has independent value/storage provenance. The source is
// intentionally not merged: destroying its inner domain cannot invalidate the
// copy rooted in the destination domain.
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, x.a)
durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_root(), x.a, x.block, x.ordinal + 1) }
if x.op == mir_op_load() {
// A load of a provenance-free type copies plain bits: the value has no
// lifetime tie to the storage domain it was read from, so a later reset or
// destroy of that domain cannot dangle it and the merges below are skipped.
if value.value_type != 0 && value.value_type <= __s0_buffer_len(U64, transfer.type_free) && __s0_buffer_get(U64, transfer.type_free, value.value_type - 1) != 0 { return Ok(durable) }
let p = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
if p.kind == mir_place_deref() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, p.deref_value) }
// Stores retain their original block/ordinal order without materializing the
// potentially quadratic load-by-aliasing-store cross product.
let first_store = __s0_buffer_get(U64, transfer.store_start, function - 1)
let store_count = __s0_buffer_get(U64, transfer.store_count, function - 1)
let load_deref = mir_vindex_place_deref(indexes, x.place)
let load_root = __s0_buffer_get(U64, indexes.place_root, x.place - 1)
let load_depth = mir_vindex_place_depth(indexes, x.place)
var store_at: U64 = 0
while store_at < store_count { let store_id = __s0_buffer_get(U64, transfer.stores, first_store + store_at)
let placed = __s0_buffer_get(MirInstrRec, store.instructions, store_id - 1)
if mir_v6_places_alias(store, indexes, x.place, load_deref, load_root, load_depth, placed.place) { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, placed.a) }
store_at = store_at + 1 } }
if x.op == mir_op_aggregate_construct() { let total = mir_vindex_op_instr_count(indexes, iid)
var oi: U64 = 0
while oi < total { let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, oi) - 1)
if o.kind == mir_operand_aggregate_field() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, o.value) }
oi = oi + 1 } }
if x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_array_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() || (x.op >= mir_op_vec_construct_checked() && x.op <= mir_op_vec_as_mut_slice()) || x.op == mir_op_array_as_slice() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, x.a) }
if x.op == mir_op_vec_grow_checked() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, x.b) }
if x.op == mir_op_table_insert_try() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, x.b) }
if x.op == mir_op_fn_value() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, x.a) }
if x.op == mir_op_call_value() { durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, x.a)
var av: U64 = 0
let atotal = mir_vindex_op_instr_count(indexes, iid)
while av < atotal { let ao = mir_vindex_op_instr(indexes, iid, av)
durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, __s0_buffer_get(MirOperandRec, store.operands, ao - 1).value)
av = av + 1 } }
if x.op == mir_op_call() { var e = mir_v6_round_effect_start(index, x.target)
while e != 0 { let effect = mir_v6_round_effect_at(durable, e)
if effect.kind == mir_v6_effect_result_from() || effect.kind == mir_v6_effect_result_alloc() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
durable = try mir_v6_merge_edge(d, durable, index, consumers, function, value_id, arg)
if effect.kind == mir_v6_effect_result_alloc() { durable = try mir_v6_fact_add(d, durable, index, function, value_id, mir_v6_fact_root(), arg, x.block, x.ordinal + 1) } }
e = mir_v6_round_effect_next(durable, e) } }
return Ok(durable) }

fn mir_v6_add_param_effects(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, value: U64, kind: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var at = mir_v6_round_fact_start(index, function, value)
while at != 0 { let f = mir_v6_round_fact_at(durable, at)
if f.kind == mir_v6_fact_param() { durable = try mir_v6_effect_add(d, durable, index, function, f.a, kind) }
at = mir_v6_round_fact_next(durable, at) }
return Ok(durable) }
fn mir_v6_add_cleanup_effects(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, active0: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var active = active0
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e = mir_v6_round_effect_start(index, push.target)
while e != 0 { let effect = mir_v6_round_effect_at(durable, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
durable = try mir_v6_add_param_effects(d, durable, index, function, arg, effect.kind) }
e = mir_v6_round_effect_next(durable, e) } } }
active = node.parent }
return Ok(durable) }

fn mir_v6_compute_round(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis, transfer: MirV6TransferIndex, consumers: MirV6ConsumerIndex, index: MirV6RoundIndex, durable0: MirV6Durable) -> Result(MirV6RoundResult, __s0_Error) {
var durable = durable0
let before_facts = __s0_buffer_len(MirV6Fact, durable.facts)
let before_effects = __s0_buffer_len(MirV6Effect, durable.effects)
let function_count = __s0_buffer_len(MirFunctionRec, store.functions)
var queue = try __s0_buffer_new(U64, d)
var queued = try __s0_buffer_new(U64, d)
var initial: U64 = 0
while initial <= function_count {
    var mark: U64 = 1
    if initial == 0 { mark = 0 } else { queue = try __s0_buffer_append(U64, d, queue, function_count - initial + 1) }
    queued = try __s0_buffer_append(U64, d, queued, mark)
    initial = initial + 1
}
var queue_at: U64 = 0
while queue_at < __s0_buffer_len(U64, queue) {
let function = __s0_buffer_get(U64, queue, queue_at)
__s0_buffer_set(U64, queued, function, 0)
let initial_function_effects = __s0_buffer_len(MirV6Effect, durable.effects)
var processed = try __s0_buffer_new(U64, d)
processed = try __s0_buffer_append(U64, d, processed, 0)
var value: U64 = 1
while mir_vindex_value(indexes, function, value) != 0 {
    processed = try __s0_buffer_append(U64, d, processed, 0)
    value = value + 1
}
var needs_pass = true
var generation: U64 = 0
while needs_pass {
    needs_pass = false
    generation = generation + 1
    value = 1
    while mir_vindex_value(indexes, function, value) != 0 {
    __s0_buffer_set(U64, processed, value, generation)
    let function_facts = __s0_buffer_len(MirV6Fact, durable.facts)
    durable = try mir_v6_transfer_value(d, store, indexes, transfer, index, consumers, durable, function, value)
    if function_facts != __s0_buffer_len(MirV6Fact, durable.facts) {
        let key = mir_v6_round_fact_key(index, function, value)
        var edge = __s0_buffer_get(U64, consumers.head, key)
        while edge != 0 {
            let target = __s0_buffer_get(U64, consumers.target, edge - 1)
            if __s0_buffer_get(U64, processed, target) == generation { needs_pass = true }
            edge = __s0_buffer_get(U64, consumers.next, edge - 1)
        }
    }
    value = value + 1
    }
}
let bcount = mir_vindex_block_count(indexes, function)
var block: U64 = 1
while block <= bcount {
    let icount = mir_vindex_instr_count(indexes, function, block)
    var ii: U64 = 0
    while ii < icount {
        let iid = mir_vindex_instr(indexes, function, block, ii)
        let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
        if x.op == mir_op_domain_destroy() { durable = try mir_v6_add_param_effects(d, durable, index, function, x.a, mir_v6_effect_destroy()) }
        if x.op == mir_op_domain_reset() { durable = try mir_v6_add_param_effects(d, durable, index, function, x.a, mir_v6_effect_reset()) }
        if x.op == mir_op_call() { var e = mir_v6_round_effect_start(index, x.target)
while e != 0 { let effect = mir_v6_round_effect_at(durable, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
durable = try mir_v6_add_param_effects(d, durable, index, function, arg, effect.kind) }
e = mir_v6_round_effect_next(durable, e) } }
        if x.op == mir_op_cleanup_scope_run() { var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { durable = try mir_v6_add_cleanup_effects(d, store, indexes, cleanup, durable, index, function, set.active) }
si = si + 1 } }
        ii = ii + 1
    }
    let term_id = mir_vindex_term(indexes, function, block)
    if term_id != 0 {
        let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
        if (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { var f = mir_v6_round_fact_start(index, function, t.value)
while f != 0 { let fact = mir_v6_round_fact_at(durable, f)
if fact.kind == mir_v6_fact_param() { durable = try mir_v6_effect_add(d, durable, index, function, fact.a, mir_v6_effect_result_from()) }
if fact.kind == mir_v6_fact_root() && fact.b != 0 { var h = mir_v6_round_fact_start(index, function, fact.a)
while h != 0 { let owner = mir_v6_round_fact_at(durable, h)
if owner.kind == mir_v6_fact_param() { durable = try mir_v6_effect_add(d, durable, index, function, owner.a, mir_v6_effect_result_alloc()) }
h = mir_v6_round_fact_next(durable, h) } }
f = mir_v6_round_fact_next(durable, f) } }
    }
    block = block + 1
}
if initial_function_effects != __s0_buffer_len(MirV6Effect, durable.effects) {
    var instruction: U64 = 0
    while instruction < __s0_buffer_len(MirInstrRec, store.instructions) {
        let caller = __s0_buffer_get(MirInstrRec, store.instructions, instruction)
        if (caller.op == mir_op_call() || caller.op == mir_op_cleanup_push()) && caller.target == function && __s0_buffer_get(U64, queued, caller.function) == 0 {
            queue = try __s0_buffer_append(U64, d, queue, caller.function)
            __s0_buffer_set(U64, queued, caller.function, 1)
        }
        instruction = instruction + 1
    }
}
queue_at = queue_at + 1 }
let changed = before_facts != __s0_buffer_len(MirV6Fact, durable.facts) || before_effects != __s0_buffer_len(MirV6Effect, durable.effects)
return Ok(MirV6RoundResult(durable: durable, changed: changed)) }

fn mir_v6_compute(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis) -> Result(MirV6Analysis, __s0_Error) {
var durable = MirV6Durable(facts: try __s0_buffer_new(MirV6Fact, d), effects: try __s0_buffer_new(MirV6Effect, d), fact_key_next: try __s0_buffer_new(U64, d), effect_next: try __s0_buffer_new(U64, d))
let index = try mir_v6_live_index_build(d, store, indexes)
let transfer = try mir_v6_transfer_index_build(d, store, indexes)
let consumers = try mir_v6_consumer_index_build(d, store, indexes, transfer, index)
let step = try mir_v6_compute_round(d, store, indexes, cleanup, transfer, consumers, index, durable)
durable = step.durable
return mir_v6_finalize(d, store, index, durable) }

fn mir_v6_dep_alias(a: MirV6Fact, b: MirV6StateFact) -> Bool { return a.a == b.a && a.b == b.b || a.a == 0 && b.a == 0 }
fn mir_v6_state_has(state: __s0_Buffer(MirV6StateFact), item: MirV6StateFact) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
at = at + 1 }
return false }
fn mir_v6_state_add(d: Domain, state: __s0_Buffer(MirV6StateFact), item: MirV6StateFact) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { if mir_v6_state_has(state, item) { return Ok(state) }
return __s0_buffer_append(MirV6StateFact, d, state, item) }
fn mir_v6_value_invalid(analysis: MirV6Analysis, state: __s0_Buffer(MirV6StateFact), function: U64, value: U64) -> Bool { var s: U64 = 0
while s < __s0_buffer_len(MirV6StateFact, state) { let dead = __s0_buffer_get(MirV6StateFact, state, s)
if dead.kind == mir_v6_state_mark() && dead.a == value { return true }
var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if (fact.kind == mir_v6_fact_dep() || fact.kind == mir_v6_fact_parent()) && dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
if fact.kind == mir_v6_fact_root() && dead.kind == mir_v6_state_root() && fact.a == dead.a && fact.b == dead.b && fact.c == dead.c { return true }
f = f + 1 }
s = s + 1 }
return false }
fn mir_v6_domain_dead(analysis: MirV6Analysis, state: __s0_Buffer(MirV6StateFact), function: U64, value: U64) -> Bool { var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() { var s: U64 = 0
while s < __s0_buffer_len(MirV6StateFact, state) { let dead = __s0_buffer_get(MirV6StateFact, state, s)
if dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
s = s + 1 } }
f = f + 1 }
return false }
fn mir_v6_domains_alias(analysis: MirV6Analysis, function: U64, a: U64, b: U64) -> Bool { var x = mir_v6_fact_start(analysis, function, a)
let xend = mir_v6_fact_end(analysis, function, a)
while x < xend { let left = mir_v6_fact_at(analysis, x)
if left.kind == mir_v6_fact_dep() { var y = mir_v6_fact_start(analysis, function, b)
let yend = mir_v6_fact_end(analysis, function, b)
while y < yend { let right = mir_v6_fact_at(analysis, y)
if right.kind == mir_v6_fact_dep() && (left.a == right.a && left.b == right.b || left.a == 0 && right.a == 0) { return true }
y = y + 1 } }
x = x + 1 }
return false }
fn mir_v6_root_in_domain(analysis: MirV6Analysis, function: U64, root: MirV6Fact, domain: U64) -> Bool { var h = mir_v6_fact_start(analysis, function, root.a)
let hend = mir_v6_fact_end(analysis, function, root.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() || owner.kind == mir_v6_fact_parent() { var d = mir_v6_fact_start(analysis, function, domain)
let dend = mir_v6_fact_end(analysis, function, domain)
while d < dend { let candidate = mir_v6_fact_at(analysis, d)
if candidate.kind == mir_v6_fact_dep() && (owner.a == candidate.a && owner.b == candidate.b || owner.a == 0 && candidate.a == 0) { return true }
d = d + 1 } }
h = h + 1 }
return false }
fn mir_v6_mark_domain(store: MirStore, indexes: MirVIndexes, function: U64, mark: U64) -> U64 { let vi = mir_vindex_value(indexes, function, mark)
if vi == 0 { return 0 }
let iid = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if iid == 0 { return 0 }
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op != mir_op_domain_mark() { return 0 }
return x.a }
fn mir_v6_clear_produced(d: Domain, state: __s0_Buffer(MirV6StateFact), block: U64, ordinal: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var out = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !(x.kind == mir_v6_state_root() && x.b == block && x.c == ordinal + 1) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_clear_dead(d: Domain, state: __s0_Buffer(MirV6StateFact), block: U64, ordinal: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var out = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !(x.kind == mir_v6_state_dead() && x.a == block && x.b == ordinal + 1) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_clear_mark(d: Domain, state: __s0_Buffer(MirV6StateFact), mark: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var out = try __s0_buffer_new(MirV6StateFact, d)
var at: U64 = 0
while at < __s0_buffer_len(MirV6StateFact, state) { let x = __s0_buffer_get(MirV6StateFact, state, at)
if !(x.kind == mir_v6_state_mark() && x.a == mark) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_root_after_mark(store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, root: MirV6Fact, mark: U64) -> Bool {
    if root.b == 0 { return true }
    let mi = mir_vindex_value(indexes, function, mark)
    if mi == 0 { return true }
    let mv = __s0_buffer_get(MirValueRec, store.values, mi - 1)
    // Availability dominance over the prebuilt point CFG replaces the old
    // per-call entry BFS.  A switch-case-defined mark is dominated at its own
    // case binding (phase 4's use-loop shortcut), matching the legacy point
    // walk that suppressed exactly that case edge.
    if mv.def_kind == mir_value_def_switch_case() && mv.block == root.b && mv.item == root.c { return true }
    return mir_vp4_avail_dominates(cfg, dom, mv.def_kind, mv.block, mv.item, root.b, root.c - 1)
}
fn mir_v6_invalidate(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, domain: U64, reset: Bool, mark: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) {
    var state = state0
    if !reset { var f = mir_v6_fact_start(analysis, function, domain)
let fend = mir_v6_fact_end(analysis, function, domain)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_dead(), a: fact.a, b: fact.b, c: 0)) }
f = f + 1 } }
    // Root facts of the function, enumerated through the per-value buckets.
    var v: U64 = 1
    while mir_vindex_value(indexes, function, v) != 0 {
        var r = mir_v6_fact_start(analysis, function, v)
        let rend = mir_v6_fact_end(analysis, function, v)
        while r < rend {
            let root = mir_v6_fact_at(analysis, r)
            if root.kind == mir_v6_fact_root() && mir_v6_root_in_domain(analysis, function, root, domain) {
                if !reset { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_root(), a: root.a, b: root.b, c: root.c)) }
                else { if mir_v6_root_after_mark(store, indexes, cfg, dom, function, root, mark) { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_root(), a: root.a, b: root.b, c: root.c)) } }
            }
            r = r + 1
        }
        v = v + 1
    }
    var vi: U64 = 1
    while mir_vindex_value(indexes, function, vi) != 0 { let md = mir_v6_mark_domain(store, indexes, function, vi)
if md != 0 && mir_v6_domains_alias(analysis, function, md, domain) { state = try mir_v6_state_add(d, state, MirV6StateFact(kind: mir_v6_state_mark(), a: vi, b: 0, c: 0)) }
vi = vi + 1 }
    return Ok(state)
}
fn mir_v6_apply_cleanup_entry(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, entry: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = state0
let vi = mir_vindex_value(indexes, function, entry)
if vi == 0 { return Ok(state) }
let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id == 0 { return Ok(state) }
let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var e = mir_v6_effect_start(analysis, push.target)
let eend = mir_v6_effect_end(analysis, push.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 }
return Ok(state) }
fn mir_v6_apply_cleanup(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), iid: U64, function: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var merged = try __s0_buffer_new(MirV6StateFact, d)
var found = false
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { found = true
var branch = state0
var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
branch = try mir_v6_apply_cleanup_entry(d, store, indexes, cfg, dom, analysis, branch, function, node.entry)
active = node.parent }
var bi: U64 = 0
while bi < __s0_buffer_len(MirV6StateFact, branch) { merged = try mir_v6_state_add(d, merged, __s0_buffer_get(MirV6StateFact, branch, bi))
bi = bi + 1 } }
si = si + 1 }
if found { return Ok(merged) }
return Ok(state0) }
fn mir_v6_apply(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), iid: U64, x: MirInstrRec) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) { var state = state0
if x.op == mir_op_domain_create() { state = try mir_v6_clear_dead(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_mark() { state = try mir_v6_clear_mark(d, state, x.result) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_call() || x.op == mir_op_vec_grow_checked() { state = try mir_v6_clear_produced(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_destroy() { state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, x.function, x.a, false, 0) }
if x.op == mir_op_domain_reset() { state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, x.function, x.a, true, x.b) }
if x.op == mir_op_call() { var e = mir_v6_effect_start(analysis, x.target)
let eend = mir_v6_effect_end(analysis, x.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, x.function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 } }
if x.op == mir_op_cleanup_scope_run() { state = try mir_v6_apply_cleanup(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x.function) }
return Ok(state) }

fn mir_v6_entries_new(d: Domain, blocks: U64) -> Result(MirV6Entries, __s0_Error) {
    var head = try __s0_buffer_new(U64, d)
    var tail = try __s0_buffer_new(U64, d)
    var block: U64 = 0
    while block <= blocks {
        head = try __s0_buffer_append(U64, d, head, 0)
        tail = try __s0_buffer_append(U64, d, tail, 0)
        block = block + 1
    }
    return Ok(MirV6Entries(items: try __s0_buffer_new(MirV6EntryFact, d), next: try __s0_buffer_new(U64, d), head: head, tail: tail))
}
fn mir_v6_entry_has(entries: MirV6Entries, block: U64, state: MirV6StateFact) -> Bool {
    if block == 0 || block >= __s0_buffer_len(U64, entries.head) { return false }
    var at = __s0_buffer_get(U64, entries.head, block)
    while at != 0 {
        let x = __s0_buffer_get(MirV6EntryFact, entries.items, at - 1).state
        if x.kind == state.kind && x.a == state.a && x.b == state.b && x.c == state.c { return true }
        at = __s0_buffer_get(U64, entries.next, at - 1)
    }
    return false
}
fn mir_v6_entry_merge(d: Domain, entries0: MirV6Entries, block: U64, state: __s0_Buffer(MirV6StateFact)) -> Result(MirV6EntryMerge, __s0_Error) {
    var entries = entries0
    var changed = false
    if block == 0 || block >= __s0_buffer_len(U64, entries.head) { return Ok(MirV6EntryMerge(entries: entries, changed: changed)) }
    var at: U64 = 0
    while at < __s0_buffer_len(MirV6StateFact, state) {
        let x = __s0_buffer_get(MirV6StateFact, state, at)
        if !mir_v6_entry_has(entries, block, x) {
            let old_tail = __s0_buffer_get(U64, entries.tail, block)
            entries.items = try __s0_buffer_append(MirV6EntryFact, d, entries.items, MirV6EntryFact(block: block, state: x))
            entries.next = try __s0_buffer_append(U64, d, entries.next, 0)
            let entry = __s0_buffer_len(MirV6EntryFact, entries.items)
            if old_tail == 0 { __s0_buffer_set(U64, entries.head, block, entry) }
            else { __s0_buffer_set(U64, entries.next, old_tail - 1, entry) }
            __s0_buffer_set(U64, entries.tail, block, entry)
            changed = true
        }
        at = at + 1
    }
    return Ok(MirV6EntryMerge(entries: entries, changed: changed))
}
fn mir_v6_entry_state(d: Domain, entries: MirV6Entries, block: U64) -> Result(__s0_Buffer(MirV6StateFact), __s0_Error) {
    var state = try __s0_buffer_new(MirV6StateFact, d)
    if block == 0 || block >= __s0_buffer_len(U64, entries.head) { return Ok(state) }
    var at = __s0_buffer_get(U64, entries.head, block)
    while at != 0 {
        state = try __s0_buffer_append(MirV6StateFact, d, state, __s0_buffer_get(MirV6EntryFact, entries.items, at - 1).state)
        at = __s0_buffer_get(U64, entries.next, at - 1)
    }
    return Ok(state)
}
// One successors batch: the shared scratch buffer plus the number of valid
// entries it wrote. The function overwrites [0, count) of the caller-held
// buffer in place instead of appending to a fresh buffer, so per-block and
// per-source loops reuse one buffer across a whole pass. Stale entries beyond
// count are never read.
type MirV6SuccSpan {
    buf: __s0_Buffer(U64)
    count: U64
}

fn mir_v6_successors_at(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, block: U64, out0: __s0_Buffer(U64), at: U64) -> Result(MirV6SuccSpan, __s0_Error) { var out = out0
var n: U64 = 0
let icount = mir_vindex_instr_count(indexes, function, block)
var ii: U64 = 0
while ii < icount {
    let iid = mir_vindex_instr(indexes, function, block, ii)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if mir_vop_checked(x.op) {
        if __s0_buffer_len(U64, out) <= at + n { out = try __s0_buffer_append(U64, d, out, 0) }
        __s0_buffer_set(U64, out, at + n, x.target)
        n = n + 1
    }
    ii = ii + 1
}
let term_id = mir_vindex_term(indexes, function, block)
if term_id != 0 {
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if t.kind == mir_term_jump() {
        if __s0_buffer_len(U64, out) <= at + n { out = try __s0_buffer_append(U64, d, out, 0) }
        __s0_buffer_set(U64, out, at + n, t.target)
        n = n + 1
    }
    if t.kind == mir_term_branch() {
        if __s0_buffer_len(U64, out) <= at + n { out = try __s0_buffer_append(U64, d, out, 0) }
        __s0_buffer_set(U64, out, at + n, t.then_block)
        n = n + 1
        if __s0_buffer_len(U64, out) <= at + n { out = try __s0_buffer_append(U64, d, out, 0) }
        __s0_buffer_set(U64, out, at + n, t.else_block)
        n = n + 1
    }
    if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
var oi: U64 = 0
while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
if c.kind == mir_operand_switch_case() {
        if __s0_buffer_len(U64, out) <= at + n { out = try __s0_buffer_append(U64, d, out, 0) }
        __s0_buffer_set(U64, out, at + n, c.target)
        n = n + 1
}
oi = oi + 1 } }
}
return Ok(MirV6SuccSpan(buf: out, count: n)) }
fn mir_v6_solve_states(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, cleanup: MirV7Analysis, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64) -> Result(MirV6Entries, __s0_Error) {
let reachable = try mir_vreachable(d, store, indexes, function)
let bcount = mir_vindex_block_count(indexes, function)
var entries = try mir_v6_entries_new(d, bcount)
var queue = try __s0_buffer_new(U64, d)
var queued = try __s0_buffer_new(U64, d)
queued = try __s0_buffer_append(U64, d, queued, 0)
var block: U64 = 1
while block <= bcount {
    var mark: U64 = 0
    if mir_vseen_block(reachable, block) {
        queue = try __s0_buffer_append(U64, d, queue, block)
        mark = 1
    }
    queued = try __s0_buffer_append(U64, d, queued, mark)
    block = block + 1
}
var queue_at: U64 = 0
var succ = try __s0_buffer_new(U64, d)
while queue_at < __s0_buffer_len(U64, queue) {
block = __s0_buffer_get(U64, queue, queue_at)
__s0_buffer_set(U64, queued, block, 0)
var state = try mir_v6_entry_state(d, entries, block)
let icount = mir_vindex_instr_count(indexes, function, block)
var ordinal: U64 = 0
while ordinal < icount {
    let iid = mir_vindex_instr(indexes, function, block, ordinal)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if mir_vop_checked(x.op) { let merged = try mir_v6_entry_merge(d, entries, x.target, state)
        entries = merged.entries
        if merged.changed && __s0_buffer_get(U64, queued, x.target) == 0 { queue = try __s0_buffer_append(U64, d, queue, x.target)
            __s0_buffer_set(U64, queued, x.target, 1) }
    }
    state = try mir_v6_apply(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x)
    ordinal = ordinal + 1
}
let span = try mir_v6_successors_at(d, store, indexes, function, block, succ, 0)
succ = span.buf
var si: U64 = 0
while si < span.count { let target = __s0_buffer_get(U64, succ, si)
// Checked successors already received the pre-instruction state above.
var checked = false
var xi: U64 = 0
while xi < icount {
    let q = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, block, xi) - 1)
    if mir_vop_checked(q.op) && q.target == target { checked = true }
    xi = xi + 1
}
if !checked { let merged = try mir_v6_entry_merge(d, entries, target, state)
    entries = merged.entries
    if merged.changed && __s0_buffer_get(U64, queued, target) == 0 { queue = try __s0_buffer_append(U64, d, queue, target)
        __s0_buffer_set(U64, queued, target, 1) }
}
si = si + 1 }
queue_at = queue_at + 1
}
return Ok(entries) }

fn mir_v6_reach_has(reach: MirV6Reachability, from: U64, to: U64) -> Bool {
    if from == 0 || from > reach.bcount { return false }
    if to == 0 || to > reach.bcount { return false }
    if reach.use_matrix {
        let row = (from - 1) * reach.row_words + (to - 1) / 64
        return (__s0_buffer_get(U64, reach.words, row) >> ((to - 1) % 64)) % 2 == 1
    }
    var at = __s0_buffer_get(U64, reach.span, from - 1)
    let end = __s0_buffer_get(U64, reach.span, from)
    while at < end {
        if __s0_buffer_get(MirV6ReachFact, reach.facts, at).to == to { return true }
        at = at + 1
    }
    return false
}

// One BFS layer write: successors of `block` overwrite queue[at .. at+count)
// in the plan-carried scratch and return the grown buffer with the count.
// Membership of the closure is decided twice over the same traversal, so the
// pre-pass below and the fill pass see exactly the same pairs.
fn mir_v6_reach_seen_grow(plan: MirV6ReachPlan, d: Domain, index: U64) -> Result(MirV6ReachPlan, __s0_Error) { var out = plan
if __s0_buffer_len(U64, out.seen) <= index { out.seen = try __s0_buffer_append(U64, d, out.seen, 0) }
return Ok(out) }
fn mir_v6_reach_span_grow(plan: MirV6ReachPlan, d: Domain, index: U64) -> Result(MirV6ReachPlan, __s0_Error) { var out = plan
if __s0_buffer_len(U64, out.span) <= index { out.span = try __s0_buffer_append(U64, d, out.span, 0) }
return Ok(out) }

fn mir_v6_reachability(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, plan0: MirV6ReachPlan) -> Result(MirV6ReachBuilt, __s0_Error) { var plan = plan0
    let bcount = mir_vindex_block_count(indexes, function)
    // Reset the function-local scratch in place: seen stamps and span bounds
    // are cleared, the queue's valid length is tracked by the walks.
    var si: U64 = 0
    while si <= bcount {
        plan = try mir_v6_reach_seen_grow(plan, d, si)
        plan = try mir_v6_reach_span_grow(plan, d, si)
        __s0_buffer_set(U64, plan.seen, si, 0)
        __s0_buffer_set(U64, plan.span, si, 0)
        si = si + 1
    }
    // Counting pass: membership-only BFS over the same traversal the fill
    // pass uses, to size the representation deterministically before any
    // closure storage is materialized.
    var count: U64 = 0
    var from: U64 = 1
    while from <= bcount {
        let seed = try mir_v6_successors_at(d, store, indexes, function, from, plan.queue, 0)
        plan.queue = seed.buf
        var qlen = seed.count
        var q: U64 = 0
        while q < qlen {
            let to = __s0_buffer_get(U64, plan.queue, q)
            if to >= 1 && to <= bcount && __s0_buffer_get(U64, plan.seen, to) != from {
                __s0_buffer_set(U64, plan.seen, to, from)
                count = count + 1
                let more = try mir_v6_successors_at(d, store, indexes, function, to, plan.queue, qlen)
                plan.queue = more.buf
                qlen = qlen + more.count
            }
            q = q + 1
        }
        from = from + 1
    }
    // Representation choice: the matrix wins only when it is strictly
    // cheaper than 16 bytes per closure pair for this function's own shape,
    // so a sparse giant never pays the quadratic matrix for a thin closure.
    let row_words = (bcount + 63) / 64
    let use_matrix = bcount * row_words * 8 < count * 16
    var one: U64 = 1
    var reach = MirV6Reachability(words: plan.words, row_words: row_words, facts: plan.pairs, span: plan.span, use_matrix: use_matrix, bcount: bcount)
    if use_matrix {
        // Clear exactly the rows this function owns; the carried buffer may
        // be longer from a larger earlier function.
        let need = bcount * row_words
        var wi: U64 = 0
        while wi < need {
            if __s0_buffer_len(U64, plan.words) <= wi { plan.words = try __s0_buffer_append(U64, d, plan.words, 0) }
            __s0_buffer_set(U64, plan.words, wi, 0)
            wi = wi + 1
        }
        reach.words = plan.words
    }
    // Fill pass: same traversal, same discovery order.
    var pos: U64 = 0
    from = 1
    while from <= bcount {
        if !use_matrix {
            __s0_buffer_set(U64, plan.span, from - 1, pos)
        }
        let seed = try mir_v6_successors_at(d, store, indexes, function, from, plan.queue, 0)
        plan.queue = seed.buf
        var qlen = seed.count
        var q: U64 = 0
        while q < qlen {
            let to = __s0_buffer_get(U64, plan.queue, q)
            if to >= 1 && to <= bcount && __s0_buffer_get(U64, plan.seen, to) != from {
                __s0_buffer_set(U64, plan.seen, to, from)
                if use_matrix {
                    let row = (from - 1) * row_words + (to - 1) / 64
                    let word = __s0_buffer_get(U64, plan.words, row)
                    __s0_buffer_set(U64, plan.words, row, word + (one << ((to - 1) % 64)))
                } else {
                    if __s0_buffer_len(MirV6ReachFact, plan.pairs) <= pos { plan.pairs = try __s0_buffer_append(MirV6ReachFact, d, plan.pairs, MirV6ReachFact(from: 0, to: 0)) }
                    __s0_buffer_set(MirV6ReachFact, plan.pairs, pos, MirV6ReachFact(from: from, to: to))
                    pos = pos + 1
                }
                let more = try mir_v6_successors_at(d, store, indexes, function, to, plan.queue, qlen)
                plan.queue = more.buf
                qlen = qlen + more.count
            }
            q = q + 1
        }
        from = from + 1
    }
    if !use_matrix {
        __s0_buffer_set(U64, plan.span, bcount, pos)
    }
    reach.words = plan.words
    reach.facts = plan.pairs
    reach.span = plan.span
    return Ok(MirV6ReachBuilt(reach: reach, plan: plan))
}
// mir_v6_loop_kills records one domain death site inside a loop: a direct
// destroy or reset, or a call argument a callee effect may destroy or reset.
// block is the killing block and value the domain that dies.
type MirV6LoopKill {
    block: U64
    value: U64
}

// mir_v6_loop_kills_collect gathers the per-function kill sites once, so each
// loop-carried store or parameter checks them without rescanning the module.
// mir_v6_loop_carry_owner reports whether a MIR type is an owning value
// whose loop-carried storage the survival rule may reason about: it contains
// an owning collection and no capability or handle kind. Capability-typed
// values keep the conservative loop rules: views alias memory owned
// elsewhere and are lexically scoped by design, and handles are the
// resource discipline itself.
fn mir_v6_loop_carry_owner_walk(store: MirStore, indexes: MirVIndexes, seen: __s0_Buffer(U64), stamp: U64, type_id: U64) -> Result(Bool, __s0_Error) {
    let checked = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    let kind = checked.kind
    if kind == mir_type_kind_slice() || kind == mir_type_kind_safe_ref() || kind == mir_type_kind_safe_mut() || kind == mir_type_kind_domain_handle() || kind == mir_type_kind_domain_mark() || kind == mir_type_kind_table() || kind == mir_type_kind_table_view() || kind == mir_type_kind_table_mut_view() || kind == mir_type_kind_raw_ptr() || kind == mir_type_kind_cleanup_scope() || kind == mir_type_kind_cleanup_id() { return Ok(false) }
    let env_record = mir_v6_env_record(store, indexes, type_id)
    if checked.elem != 0 {
        if !(try mir_v6_loop_carry_owner_seen(store, indexes, seen, stamp, checked.elem)) { return Ok(false) }
    }
    if checked.ok_type != 0 {
        if !(try mir_v6_loop_carry_owner_seen(store, indexes, seen, stamp, checked.ok_type)) { return Ok(false) }
    }
    if checked.err_type != 0 {
        if !(try mir_v6_loop_carry_owner_seen(store, indexes, seen, stamp, checked.err_type)) { return Ok(false) }
    }
    var part: U64 = 0
    let part_count = mir_vindex_type_part_count(indexes, type_id)
    while part < part_count {
        let part_id = mir_vindex_type_part(indexes, type_id, part)
        if part_id != 0 && part_id <= __s0_buffer_len(MirTypePartRec, store.type_parts) {
            let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, part_id - 1)
            if rec.part_type != 0 {
                // A closure environment record's domain field names the
                // domain that owns the record, not a borrowed capability.
                var domain_field = false
                if env_record && rec.part_type <= __s0_buffer_len(MirTypeRec, store.types) {
                    if __s0_buffer_get(MirTypeRec, store.types, rec.part_type - 1).kind == mir_type_kind_domain_handle() { domain_field = true }
                }
                if !domain_field {
                    if !(try mir_v6_loop_carry_owner_seen(store, indexes, seen, stamp, rec.part_type)) { return Ok(false) }
                }
            }
        }
        part = part + 1
    }
    return Ok(true)
}

// mir_v6_loop_carry_owner_seen memoizes one query. The module allocates the
// seen buffer once and stamps it per function, so the whole module needs one
// U64 per type instead of one buffer per function. A slot holds the current
// stamp exactly when the type is on the walk's own recursion path or is
// already proven an owning value, and a false verdict clears it again: a
// capability type must never come back as an owner on a later query, which
// would hand a view the death-precise rule instead of the conservative one.
fn mir_v6_loop_carry_owner_seen(store: MirStore, indexes: MirVIndexes, seen: __s0_Buffer(U64), stamp: U64, type_id: U64) -> Result(Bool, __s0_Error) {
    if type_id == 0 || type_id > __s0_buffer_len(MirTypeRec, store.types) { return Ok(true) }
    if __s0_buffer_get(U64, seen, type_id - 1) == stamp { return Ok(true) }
    __s0_buffer_set(U64, seen, type_id - 1, stamp)
    let owner = try mir_v6_loop_carry_owner_walk(store, indexes, seen, stamp, type_id)
    if !owner { __s0_buffer_set(U64, seen, type_id - 1, 0) }
    return Ok(owner)
}

fn mir_v6_loop_carry_owner(d: Domain, store: MirStore, indexes: MirVIndexes, seen: __s0_Buffer(U64), stamp: U64, type_id: U64) -> Result(Bool, __s0_Error) {
    return mir_v6_loop_carry_owner_seen(store, indexes, seen, stamp, type_id)
}

fn mir_v6_loop_kills_collect(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, function: U64) -> Result(__s0_Buffer(MirV6LoopKill), __s0_Error) {
    var kills = try __s0_buffer_new(MirV6LoopKill, d)
    // Walk only this function's blocks through the per-function index; a
    // whole-store instruction scan here is quadratic across the module.
    let bcount = mir_vindex_block_count(indexes, function)
    var b: U64 = 1
    while b <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, b)
        var ii: U64 = 0
        while ii < icount {
            let iid = mir_vindex_instr(indexes, function, b, ii)
            let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
            if x.op == mir_op_domain_destroy() || x.op == mir_op_domain_reset() {
                kills = try __s0_buffer_append(MirV6LoopKill, d, kills, MirV6LoopKill(block: x.block, value: x.a))
            }
            if x.op == mir_op_call() {
                var e = mir_v6_effect_start(analysis, x.target)
                let eend = mir_v6_effect_end(analysis, x.target)
                while e < eend {
                    let effect = mir_v6_effect_at(analysis, e)
                    if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() {
                        let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
                        if arg != 0 { kills = try __s0_buffer_append(MirV6LoopKill, d, kills, MirV6LoopKill(block: x.block, value: arg)) }
                    }
                    e = e + 1
                }
            }
            ii = ii + 1
        }
        b = b + 1
    }
    return Ok(kills)
}

// mir_v6_loop_fact_killed reports whether a domain identity fact (a dep or
// parent key) dies at a collected kill site in a loop block that the
// carrying site can reach.
fn mir_v6_loop_fact_killed(analysis: MirV6Analysis, reach: MirV6Reachability, kills: __s0_Buffer(MirV6LoopKill), function: U64, from_block: U64, fact: MirV6Fact) -> Bool {
    var k: U64 = 0
    while k < __s0_buffer_len(MirV6LoopKill, kills) {
        let kill = __s0_buffer_get(MirV6LoopKill, kills, k)
        if mir_v6_reach_has(reach, kill.block, kill.block) && mir_v6_reach_has(reach, from_block, kill.block) {
            var t = mir_v6_fact_start(analysis, function, kill.value)
            let tend = mir_v6_fact_end(analysis, function, kill.value)
            while t < tend {
                let td = mir_v6_fact_at(analysis, t)
                if td.kind == mir_v6_fact_dep() && (td.a == fact.a && td.b == fact.b || td.a == 0 && fact.a == 0) { return true }
                t = t + 1
            }
        }
        k = k + 1
    }
    return false
}

// mir_v6_loop_same_cycle reports whether a block lies in the same cycle as
// the loop block being checked. "On some cycle" is not enough: an allocation
// or a domain created inside a different, already finished loop is carried
// across this loop's backedge unchanged, and only an allocation produced
// inside THIS loop is per-iteration.
fn mir_v6_loop_same_cycle(reach: MirV6Reachability, anchor: U64, block: U64) -> Bool {
    if block == 0 { return false }
    if block == anchor { return true }
    return mir_v6_reach_has(reach, anchor, block) && mir_v6_reach_has(reach, block, anchor)
}

// mir_v6_loop_in_body reports whether the loop header dominates the block,
// which is what makes a definition re-execute once per iteration of that
// loop. A cycle test cannot answer this: a for loop nested inside a while
// body shares the while loop's cycle, yet a value the nested loop carries is
// defined once per outer iteration, not once per inner one.
fn mir_v6_loop_in_body(cfg: MirVP4PointCfg, dom: MirVP4Dom, header: U64, block: U64) -> Bool {
    if block == 0 { return false }
    if block == header { return true }
    return mir_vp4_dominates(cfg, dom, mir_vp4_boundary_node(cfg, block, 0), mir_vp4_boundary_node(cfg, header, 0))
}

// mir_v6_env_snapshot reports whether a type is a copyable snapshot that may
// contain function values and nothing that owns or aliases mutable storage.
// Such a value shares immutable environment records, so carrying it across a
// backedge transfers no ownership and cannot conflate iterations; a function
// value's environment still dies with its owning domain, which the death
// checks below keep enforcing.
type MirV6EnvSnapshotRec {
    has_env: Bool
    blocked: Bool
}
fn mir_v6_env_snapshot_scan(store: MirStore, indexes: MirVIndexes, type_id: U64, depth: U64) -> MirV6EnvSnapshotRec {
    if type_id == 0 || type_id > __s0_buffer_len(MirTypeRec, store.types) || depth > 8 { return MirV6EnvSnapshotRec(has_env: false, blocked: true) }
    let checked = __s0_buffer_get(MirTypeRec, store.types, type_id - 1)
    if checked.kind == mir_type_kind_function() { return MirV6EnvSnapshotRec(has_env: true, blocked: false) }
    if checked.kind == mir_type_kind_primitive() { return MirV6EnvSnapshotRec(has_env: false, blocked: false) }
    if checked.kind == mir_type_kind_aggregate() || checked.kind == mir_type_kind_enum() || checked.kind == mir_type_kind_option() || checked.kind == mir_type_kind_result() || checked.kind == mir_type_kind_array() {
        var has_env = false
        var blocked = false
        if checked.elem != 0 {
            let child = mir_v6_env_snapshot_scan(store, indexes, checked.elem, depth + 1)
            if child.has_env { has_env = true }
            if child.blocked { blocked = true }
        }
        if checked.ok_type != 0 {
            let child = mir_v6_env_snapshot_scan(store, indexes, checked.ok_type, depth + 1)
            if child.has_env { has_env = true }
            if child.blocked { blocked = true }
        }
        if checked.err_type != 0 {
            let child = mir_v6_env_snapshot_scan(store, indexes, checked.err_type, depth + 1)
            if child.has_env { has_env = true }
            if child.blocked { blocked = true }
        }
        var part: U64 = 0
        let part_count = mir_vindex_type_part_count(indexes, type_id)
        while part < part_count {
            let part_id = mir_vindex_type_part(indexes, type_id, part)
            if part_id != 0 && part_id <= __s0_buffer_len(MirTypePartRec, store.type_parts) {
                let rec = __s0_buffer_get(MirTypePartRec, store.type_parts, part_id - 1)
                if rec.part_type != 0 {
                    let child = mir_v6_env_snapshot_scan(store, indexes, rec.part_type, depth + 1)
                    if child.has_env { has_env = true }
                    if child.blocked { blocked = true }
                }
            }
            part = part + 1
        }
        return MirV6EnvSnapshotRec(has_env: has_env, blocked: blocked)
    }
    return MirV6EnvSnapshotRec(has_env: false, blocked: true)
}
fn mir_v6_env_snapshot(store: MirStore, indexes: MirVIndexes, type_id: U64) -> Bool {
    let scan = mir_v6_env_snapshot_scan(store, indexes, type_id, 0)
    return scan.has_env && !scan.blocked
}

// mir_v6_loop_value_dies is the precise half of the loop rules: a carried
// value dies inside its loop when it depends on a domain created in the
// loop, or when a destroy or reset inside the loop invalidates one of its
// domain identities (a reset also invalidates descendants, which parent
// facts record). Entry domains created before the loop and destroyed only
// after it survive, which is what makes loop-carried collection headers
// legal.
fn mir_v6_loop_value_dies(analysis: MirV6Analysis, reach: MirV6Reachability, kills: __s0_Buffer(MirV6LoopKill), cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, anchor: U64, from_block: U64, value: U64, shared: Bool) -> Bool {
    var f = mir_v6_fact_start(analysis, function, value)
    let fend = mir_v6_fact_end(analysis, function, value)
    while f < fend {
        let fact = mir_v6_fact_at(analysis, f)
        if fact.kind == mir_v6_fact_dep() && fact.a != 0 && mir_v6_loop_in_body(cfg, dom, anchor, fact.a) { return true }
        if fact.kind == mir_v6_fact_dep() || fact.kind == mir_v6_fact_parent() {
            if mir_v6_loop_fact_killed(analysis, reach, kills, function, from_block, fact) { return true }
        }
        if fact.kind == mir_v6_fact_root() && fact.b != 0 {
            // An allocation produced inside THIS loop is per-iteration for
            // an owning value: carrying it around the backedge conflates
            // iterations, so it stays forbidden. A shared function
            // environment is immutable and copyable, so the allocation site
            // alone does not condemn it; a domain death inside the loop still
            // does.
            if !shared && mir_v6_loop_in_body(cfg, dom, anchor, fact.b) { return true }
            var h = mir_v6_fact_start(analysis, function, fact.a)
            let hend = mir_v6_fact_end(analysis, function, fact.a)
            while h < hend {
                let owner = mir_v6_fact_at(analysis, h)
                if (owner.kind == mir_v6_fact_dep() || owner.kind == mir_v6_fact_parent()) && mir_v6_loop_fact_killed(analysis, reach, kills, function, from_block, owner) { return true }
                h = h + 1
            }
        }
        f = f + 1
    }
    return false
}

// mir_v6_loop_param_dies decides one backedge argument: capability-typed
// values keep the blanket rejection, owner-typed values die only when their
// storage dies inside the loop.
fn mir_v6_loop_param_dies(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, reach: MirV6Reachability, kills: __s0_Buffer(MirV6LoopKill), owner_seen: __s0_Buffer(U64), owner_stamp: U64, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, anchor: U64, source: U64, value: U64) -> Result(Bool, __s0_Error) {
    let vi = mir_vindex_value(indexes, function, value)
    if vi == 0 { return Ok(true) }
    let value_type = __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type
    // A copyable snapshot that may contain function values shares immutable
    // environment records, so the per-iteration allocation clause does not
    // apply; the death checks still reject an environment whose domain dies
    // inside the loop.
    if mir_v6_env_snapshot(store, indexes, value_type) { return Ok(mir_v6_loop_value_dies(analysis, reach, kills, cfg, dom, function, anchor, source, value, true)) }
    if try mir_v6_loop_carry_owner(d, store, indexes, owner_seen, owner_stamp, value_type) { return Ok(mir_v6_loop_value_dies(analysis, reach, kills, cfg, dom, function, anchor, source, value, false)) }
    return Ok(true)
}

fn mir_v6_local_provenance(analysis: MirV6Analysis, function: U64, value: U64) -> Bool { var at = mir_v6_fact_start(analysis, function, value)
let end = mir_v6_fact_end(analysis, function, value)
while at < end { let x = mir_v6_fact_at(analysis, at)
if (x.kind == mir_v6_fact_dep() && x.a != 0) || (x.kind == mir_v6_fact_root() && x.b != 0) { return true }
at = at + 1 }
return false }
// mir_v6_stable_loop_store permits a store inside a loop cycle whose value's
// domain provenance is local to the function when every domain it can name
// survives the loop: either the store writes a local place and every root is
// owned by a domain parameter, or the owning domain is created before the loop
// and no destroy or reset inside the loop's blocks invalidates it. A
// capability-typed value (a view) additionally has to be stored into a local
// place; its root is the domain that owns the viewed storage, and the view
// read rule below keeps a header from surviving into a later iteration.
fn mir_v6_stable_loop_store(store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, reach: MirV6Reachability, kills: __s0_Buffer(MirV6LoopKill), function: U64, value: U64, place: U64, block: U64, require_local_place: Bool) -> Bool {
if require_local_place && mir_v6_place_deref(store, place) { return false }
var e = mir_v6_effect_start(analysis, function)
let eend = mir_v6_effect_end(analysis, function)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { return false }
e = e + 1 }
var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() && fact.a != 0 && mir_v6_loop_fact_killed(analysis, reach, kills, function, block, fact) { return false }
if fact.kind == mir_v6_fact_dep() && fact.a != 0 && mir_v6_loop_same_cycle(reach, block, fact.a) { return false }
if fact.kind == mir_v6_fact_root() && fact.b != 0 {
// A local root is stable when its owning domain survives the whole loop:
// either the pre-existing parameter-domain path above found no destroying
// effect, or the domain is created before the loop and no destroy or reset
// inside the loop's blocks invalidates it.
var h = mir_v6_fact_start(analysis, function, fact.a)
let hend = mir_v6_fact_end(analysis, function, fact.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() && owner.a != 0 && mir_v6_loop_same_cycle(reach, block, owner.a) { return false }
if (owner.kind == mir_v6_fact_dep() || owner.kind == mir_v6_fact_parent()) && mir_v6_loop_fact_killed(analysis, reach, kills, function, block, owner) { return false }
h = h + 1 } }
f = f + 1 }
return true }

// mir_v6_view_storage_type reports whether a type is a scoped view whose header
// points into storage the frame does not own.
fn mir_v6_view_storage_type(store: MirStore, type_id: U64) -> Bool {
    if type_id == 0 || type_id > __s0_buffer_len(MirTypeRec, store.types) { return false }
    let kind = __s0_buffer_get(MirTypeRec, store.types, type_id - 1).kind
    return kind == mir_type_kind_slice() || kind == mir_type_kind_safe_ref() || kind == mir_type_kind_safe_mut()
}

// mir_v6_places_same reports whether two non-deref places name the same slot
// with the same projection path.
fn mir_v6_places_same(store: MirStore, indexes: MirVIndexes, a: U64, b: U64) -> Bool {
    if a == 0 || b == 0 { return false }
    if mir_vindex_place_deref(indexes, a) || mir_vindex_place_deref(indexes, b) { return false }
    if __s0_buffer_get(U64, indexes.place_root, a - 1) != __s0_buffer_get(U64, indexes.place_root, b - 1) { return false }
    let depth = mir_vindex_place_depth(indexes, a)
    if depth != mir_vindex_place_depth(indexes, b) { return false }
    var n: U64 = 0
    while n < depth {
        let ap = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, a, n) - 1)
        let bp = __s0_buffer_get(MirPlaceRec, store.places, mir_vp4_place_component(store, b, n) - 1)
        if !mir_vname_equal(store, ap.field_start, ap.field_end, bp.field_start, bp.field_end) { return false }
        n = n + 1
    }
    return true
}

// mir_v6_view_base walks a view value back to the storage it views. The
// result is 0 when the walk cannot name the storage, 1 when the storage is one
// this frame cannot relocate (a parameter, a constant, an allocation, or a call
// result), and local + 2 when a local slot of this frame holds it. A view is
// followed through as_slice, slice range and index, a switch payload through
// its scrutinee, and a load from a view slot through every value stored into
// that slot.
fn mir_v6_view_base(store: MirStore, indexes: MirVIndexes, function: U64, value: U64, depth: U64) -> U64 {
    if depth > 16 { return 0 }
    let vi = mir_vindex_value(indexes, function, value)
    if vi == 0 { return 0 }
    let rec = __s0_buffer_get(MirValueRec, store.values, vi - 1)
    if rec.def_kind == mir_value_def_function_param() || rec.def_kind == mir_value_def_block_param() { return 1 }
    if rec.def_kind == mir_value_def_switch_case() {
        let term_id = mir_vindex_term(indexes, function, rec.block)
        if term_id == 0 { return 0 }
        let term = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
        return mir_v6_view_base(store, indexes, function, term.value, depth + 1)
    }
    if rec.def_kind != mir_value_def_instruction() { return 0 }
    let iid = mir_v6_instruction_for_value(store, indexes, rec)
    if iid == 0 { return 0 }
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op == mir_op_load() {
        let place = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
        if place.kind != mir_place_local() { return 0 }
        if !mir_v6_view_storage_type(store, rec.value_type) { return place.local + 2 }
        var found: U64 = 0
        var any = false
        let slot_root = __s0_buffer_get(U64, indexes.place_root, x.place - 1)
        let bcount = mir_vindex_block_count(indexes, function)
        var b: U64 = 1
        while b <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, b)
            var ii: U64 = 0
            while ii < icount {
                let sid = mir_vindex_instr(indexes, function, b, ii)
                let st = __s0_buffer_get(MirInstrRec, store.instructions, sid - 1)
                if st.op == mir_op_store() && __s0_buffer_get(U64, indexes.place_root, st.place - 1) == slot_root && mir_v6_places_same(store, indexes, st.place, x.place) {
                    let base = mir_v6_view_base(store, indexes, function, st.a, depth + 1)
                    if base == 0 || (any && base != found) { return 0 }
                    found = base
                    any = true
                }
                ii = ii + 1
            }
            b = b + 1
        }
        if any { return found }
        return 0
    }
    if x.op == mir_op_vec_as_slice() || x.op == mir_op_vec_as_mut_slice() || x.op == mir_op_slice_range_checked() || x.op == mir_op_slice_index_checked() { return mir_v6_view_base(store, indexes, function, x.a, depth + 1) }
    if x.op == mir_op_array_as_slice() { return mir_v6_view_base(store, indexes, function, x.a, depth + 1) }
    if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_vec_new() || x.op == mir_op_vec_construct_checked() || x.op == mir_op_vec_grow_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_const_get() || x.op == mir_op_call() || x.op == mir_op_call_value() { return 1 }
    return 0
}

// mir_v6_loop_relocates_base reports whether a cycle that contains `block` can
// relocate or replace the storage local `base` names: a vector grow whose
// operand derives from it, a store into it, or a call that receives it (a
// callee may grow storage through an exclusive argument). Element writes do not
// move the storage and are not included.
fn mir_v6_loop_relocates_base(store: MirStore, indexes: MirVIndexes, reach: MirV6Reachability, function: U64, block: U64, base: U64) -> Bool {
    let bcount = mir_vindex_block_count(indexes, function)
    var b: U64 = 1
    while b <= bcount {
        if mir_v6_loop_same_cycle(reach, block, b) {
            let icount = mir_vindex_instr_count(indexes, function, b)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, b, ii)
                let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
                if x.op == mir_op_vec_grow_checked() {
                    if mir_v6_view_base(store, indexes, function, x.a, 0) == base + 2 { return true }
                }
                if x.op == mir_op_store() {
                    if __s0_buffer_get(U64, indexes.place_root, x.place - 1) == base { return true }
                }
                if x.op == mir_op_call() {
                    var oi: U64 = 0
                    var arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, oi)
                    while arg != 0 {
                        if mir_v6_view_base(store, indexes, function, arg, 0) == base + 2 { return true }
                        oi = oi + 1
                        arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, oi)
                    }
                }
                ii = ii + 1
            }
        }
        b = b + 1
    }
    return false
}

// mir_v6_loop_redefines_place reports whether a store to the same place
// dominates the load, which makes the read see a view created in the same
// iteration. A store in the load's own block has to precede it.
fn mir_v6_loop_redefines_place(store: MirStore, indexes: MirVIndexes, reach: MirV6Reachability, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, block: U64, ordinal: U64, place: U64) -> Bool {
    let bcount = mir_vindex_block_count(indexes, function)
    var b: U64 = 1
    while b <= bcount {
        if mir_v6_loop_same_cycle(reach, block, b) {
            let icount = mir_vindex_instr_count(indexes, function, b)
            var ii: U64 = 0
            while ii < icount {
                let sid = mir_vindex_instr(indexes, function, b, ii)
                let st = __s0_buffer_get(MirInstrRec, store.instructions, sid - 1)
                if st.op == mir_op_store() && mir_v6_places_same(store, indexes, st.place, place) {
                    if b == block {
                        if ii < ordinal { return true }
                    } else {
                        if mir_v6_loop_in_body(cfg, dom, b, block) { return true }
                    }
                }
                ii = ii + 1
            }
        }
        b = b + 1
    }
    return false
}

// mir_v6_value_parameter_rooted reports whether a value's provenance includes
// a root that arrives from outside the frame.
fn mir_v6_value_parameter_rooted(analysis: MirV6Analysis, function: U64, value: U64) -> Bool {
    var f = mir_v6_fact_start(analysis, function, value)
    let fend = mir_v6_fact_end(analysis, function, value)
    while f < fend { let fact = mir_v6_fact_at(analysis, f)
        if fact.kind == mir_v6_fact_root() && fact.a != 0 && fact.b == 0 { return true }
        f = f + 1 }
    return false
}

fn mir_v6_escapes_local(analysis: MirV6Analysis, function: U64, value: U64) -> Bool { var r = mir_v6_fact_start(analysis, function, value)
let rend = mir_v6_fact_end(analysis, function, value)
while r < rend { let root = mir_v6_fact_at(analysis, r)
if root.kind == mir_v6_fact_root() && root.b != 0 { var h = mir_v6_fact_start(analysis, function, root.a)
let hend = mir_v6_fact_end(analysis, function, root.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() && owner.a != 0 { return true }
h = h + 1 } }
r = r + 1 }
return false }
fn mir_v6_bad(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, block: U64, instruction: U64, terminator: U64, operand: U64, reference: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var type_id: U64 = 0
return mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), kind, function, block, instruction, terminator, operand, type_id, 0, 0, 0, reference)) }
fn mir_v6_bad_has(out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, instruction: U64, reference: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirVerifyDiagRec, out) { let x = __s0_buffer_get(MirVerifyDiagRec, out, at)
if x.phase == mir_verify_phase_domains() && x.kind == kind && x.function == function && x.instruction == instruction && x.reference == reference { return true }
at = at + 1 }
return false }
fn mir_v6_check_cleanup(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: __s0_Buffer(MirV6StateFact), function: U64, block: U64, iid: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
var si: U64 = 0
while si < __s0_buffer_len(MirV7RunSet, cleanup.run_sets) { let set = __s0_buffer_get(MirV7RunSet, cleanup.run_sets, si)
if set.function == function && set.instruction == iid { var branch = state0
var active = set.active
while active != 0 { let node = __s0_buffer_get(MirV7Node, cleanup.nodes, active - 1)
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, __s0_buffer_get(MirValueRec, store.values, vi - 1))
if push_id != 0 { let push = __s0_buffer_get(MirInstrRec, store.instructions, push_id - 1)
var oi: U64 = 0
var arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, oi)
var invalid = false
while arg != 0 { if !invalid && mir_v6_value_invalid(analysis, branch, function, arg) { invalid = true
if !mir_v6_bad_has(out, mir_vdiag_invalid_resource_use(), function, iid, arg) { let operand_id = mir_v5_operand(store, indexes, mir_operand_instruction(), push_id, 0, oi)
out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_use(), function, block, iid, 0, operand_id, arg) } }
oi = oi + 1
arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, oi) }
var e = mir_v6_effect_start(analysis, push.target)
let eend = mir_v6_effect_end(analysis, push.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() { let domain = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
if mir_v6_domain_dead(analysis, branch, function, domain) && !mir_v6_bad_has(out, mir_vdiag_dead_domain(), function, iid, domain) { out = try mir_v6_bad(d, out, mir_vdiag_dead_domain(), function, block, iid, 0, 0, domain) } }
e = e + 1 }
branch = try mir_v6_apply_cleanup_entry(d, store, indexes, cfg, dom, analysis, branch, function, node.entry) } }
active = node.parent } }
si = si + 1 }
return Ok(out) }
fn mir_v6_check_loops(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, owner_seen: __s0_Buffer(U64), owner_stamp: U64, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, reach_plan0: MirV6ReachPlan, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(MirV6LoopBuilt, __s0_Error) { var out = out0
let reach_built = try mir_v6_reachability(d, store, indexes, function, reach_plan0)
let reach = reach_built.reach
var reach_plan = reach_built.plan
let kills = try mir_v6_loop_kills_collect(d, store, indexes, analysis, function)
let pcount = mir_vindex_param_count(indexes, function)
var pi: U64 = 0
while pi < pcount {
    let pid = mir_vindex_param(indexes, function, pi)
    let p = __s0_buffer_get(MirParamRec, store.params, pid - 1)
    if p.kind == mir_param_block() {
        // Incoming edge operands of this block parameter, enumerated through
        // the per-owner operand indexes in storage order.
        let bcount = mir_vindex_block_count(indexes, function)
        var b: U64 = 1
        while b <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, b)
            var ii: U64 = 0
            while ii < icount {
                let iid = mir_vindex_instr(indexes, function, b, ii)
                let total = mir_vindex_op_instr_count(indexes, iid)
                var oi: U64 = 0
                while oi < total {
                    let oid = mir_vindex_op_instr(indexes, iid, oi)
                    let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
                    if o.kind == mir_operand_checked_edge_arg() && o.target == p.block && o.ordinal == p.ordinal { let source = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1).block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { var param_dies: Bool = true
let decided = try mir_v6_loop_param_dies(d, store, indexes, analysis, reach, kills, owner_seen, owner_stamp, cfg, dom, function, p.block, source, o.value)
param_dies = decided
if param_dies { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } } }
                    oi = oi + 1
                }
                ii = ii + 1
            }
            let term_id = mir_vindex_term(indexes, function, b)
            if term_id != 0 {
                let total = mir_vindex_op_term_count(indexes, term_id)
                var oi: U64 = 0
                while oi < total {
                    let oid = mir_vindex_op_term(indexes, term_id, oi)
                    let o = __s0_buffer_get(MirOperandRec, store.operands, oid - 1)
                    if o.kind == mir_operand_terminator_arg() && o.target == p.block && o.ordinal == p.ordinal { let source = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1).block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { var param_dies: Bool = true
let decided = try mir_v6_loop_param_dies(d, store, indexes, analysis, reach, kills, owner_seen, owner_stamp, cfg, dom, function, p.block, source, o.value)
param_dies = decided
if param_dies { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } } }
                    oi = oi + 1
                }
                var ci: U64 = 0
                while ci < total {
                    let cid = mir_vindex_op_term(indexes, term_id, ci)
                    let c = __s0_buffer_get(MirOperandRec, store.operands, cid - 1)
                    if c.kind == mir_operand_switch_case() {
                        let atotal = mir_vindex_op_case_count(indexes, cid)
                        var ai: U64 = 0
                        while ai < atotal {
                            let aid = mir_vindex_op_case(indexes, cid, ai)
                            let a = __s0_buffer_get(MirOperandRec, store.operands, aid - 1)
                            if a.target == p.block && a.ordinal == p.ordinal { let source = __s0_buffer_get(MirTermRec, store.terminators, __s0_buffer_get(MirOperandRec, store.operands, cid - 1).owner - 1).block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, a.value) { var param_dies: Bool = true
let decided = try mir_v6_loop_param_dies(d, store, indexes, analysis, reach, kills, owner_seen, owner_stamp, cfg, dom, function, p.block, source, a.value)
param_dies = decided
if param_dies { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, aid, p.value) } } }
                            ai = ai + 1
                        }
                    }
                    ci = ci + 1
                }
            }
            b = b + 1
        }
    }
    pi = pi + 1
}
// Loop-backedge stores, in instruction storage order.
let bcount = mir_vindex_block_count(indexes, function)
var b2: U64 = 1
while b2 <= bcount {
    let icount = mir_vindex_instr_count(indexes, function, b2)
    var ii: U64 = 0
    while ii < icount {
        let iid = mir_vindex_instr(indexes, function, b2, ii)
        let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
        if x.op == mir_op_store() && mir_v6_reach_has(reach, x.block, x.block) && mir_v6_local_provenance(analysis, function, x.a) {
            var stable = false
            let value_type = mir_vindex_value(indexes, function, x.a)
            if value_type != 0 {
                // A capability-typed value must be stored into a local place;
                // an owner may also be stored through a projection. The
                // stability test is the same for both.
                var require_local_place = true
                if try mir_v6_loop_carry_owner(d, store, indexes, owner_seen, owner_stamp, __s0_buffer_get(MirValueRec, store.values, value_type - 1).value_type) { require_local_place = false }
                stable = mir_v6_stable_loop_store(store, indexes, analysis, reach, kills, function, x.a, x.place, x.block, require_local_place)
            }

            if !stable { out = try mir_v6_bad(d, out, mir_vdiag_loop_store_resource(), function, x.block, iid, 0, x.place, x.a) } }
        ii = ii + 1
    }
    b2 = b2 + 1
}
// A view read inside a loop must be redefined in the same iteration, or the
// loop must not be able to move the storage it views. A view header is not an
// owning value: a later iteration that reads a header stored by an earlier one
// dangles as soon as the loop grows, removes from, or replaces the owner, and
// the domain surviving the loop does not prevent that.
var b3: U64 = 1
while b3 <= bcount {
    if mir_v6_reach_has(reach, b3, b3) {
        let icount3 = mir_vindex_instr_count(indexes, function, b3)
        var i3: U64 = 0
        while i3 < icount3 {
            let iid3 = mir_vindex_instr(indexes, function, b3, i3)
            let x3 = __s0_buffer_get(MirInstrRec, store.instructions, iid3 - 1)
            if x3.op == mir_op_load() && !mir_v6_place_deref(store, x3.place) {
                let vi3 = mir_vindex_value(indexes, function, x3.result)
                if vi3 != 0 {
                    let vt3 = __s0_buffer_get(MirValueRec, store.values, vi3 - 1).value_type
                    if mir_v6_view_storage_type(store, vt3) {
                        var accepted = mir_v6_value_parameter_rooted(analysis, function, x3.result)
                        if !accepted { accepted = mir_v6_loop_redefines_place(store, indexes, reach, cfg, dom, function, b3, i3, x3.place) }
                        if !accepted {
                            let base = mir_v6_view_base(store, indexes, function, x3.result, 0)
                            if base == 1 { accepted = true }
                            if base > 1 && !mir_v6_loop_relocates_base(store, indexes, reach, function, b3, base - 2) { accepted = true }
                        }
                        if !accepted { out = try mir_v6_bad(d, out, mir_vdiag_loop_view_read(), function, b3, iid3, 0, x3.place, x3.result) }
                    }
                }
            }
            i3 = i3 + 1
        }
    }
    b3 = b3 + 1
}
return Ok(MirV6LoopBuilt(out: out, plan: reach_plan)) }
fn mir_vphase6_with(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, initial: __s0_Buffer(MirVerifyDiagRec), cleanup: MirV7Analysis, analysis: MirV6Analysis) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = initial
// One owner-classifier buffer for the whole module: one U64 per interned type,
// stamped per function, instead of a fresh buffer of that size per function.
var owner_seen = try __s0_buffer_new(U64, d)
var owner_at: U64 = 0
while owner_at < __s0_buffer_len(MirTypeRec, store.types) {
    owner_seen = try __s0_buffer_append(U64, d, owner_seen, 0)
    owner_at = owner_at + 1
}
var owner_stamp: U64 = 0
// Plan-carried cfg and dominator storage, same shape as the phase-4 plans:
// the builders grow the buffers lazily, rewrite them in place per function,
// and return the grown handles with each result, so the per-function arrays
// stop accumulating in the root domain.
var p_boundary = try __s0_buffer_new(U64, d)
var p_bicount = try __s0_buffer_new(U64, d)
var p_succ = try __s0_buffer_new(U64, d)
var p_succ_start = try __s0_buffer_new(U64, d)
var p_succ_count = try __s0_buffer_new(U64, d)
var p_pred = try __s0_buffer_new(U64, d)
var p_pred_start = try __s0_buffer_new(U64, d)
var p_pred_count = try __s0_buffer_new(U64, d)
var p_case_edge = try __s0_buffer_new(U64, d)
var p_edge_from = try __s0_buffer_new(U64, d)
var p_edge_to = try __s0_buffer_new(U64, d)
var p_ecnt = try __s0_buffer_new(U64, d)
var p_ebase = try __s0_buffer_new(U64, d)
var p_eids = try __s0_buffer_new(U64, d)
var p_eused = try __s0_buffer_new(U64, d)
var cfg_plan = MirVP4CfgPlan(boundary_offset: p_boundary, block_instr_count: p_bicount, succ: p_succ, succ_start: p_succ_start, succ_count: p_succ_count, pred: p_pred, pred_start: p_pred_start, pred_count: p_pred_count, case_edge: p_case_edge, edge_from: p_edge_from, edge_to: p_edge_to, scratch_edge_cnt: p_ecnt, scratch_edge_base: p_ebase, scratch_edge_ids: p_eids, scratch_edge_used: p_eused)
var q_idom = try __s0_buffer_new(U64, d)
var q_rpo_index = try __s0_buffer_new(U64, d)
var q_dom_in = try __s0_buffer_new(U64, d)
var q_dom_out = try __s0_buffer_new(U64, d)
var q_seen = try __s0_buffer_new(U64, d)
var q_phase = try __s0_buffer_new(U64, d)
var q_stack = try __s0_buffer_new(U64, d)
var q_post = try __s0_buffer_new(U64, d)
var q_rpo = try __s0_buffer_new(U64, d)
var q_child_count = try __s0_buffer_new(U64, d)
var q_counts = try __s0_buffer_new(U64, d)
var q_child_start = try __s0_buffer_new(U64, d)
var q_filled = try __s0_buffer_new(U64, d)
var q_children = try __s0_buffer_new(U64, d)
var q_estack = try __s0_buffer_new(U64, d)
var q_edata = try __s0_buffer_new(U64, d)
var dom_plan = MirVP4DomPlan(idom: q_idom, rpo_index: q_rpo_index, dom_in: q_dom_in, dom_out: q_dom_out, scratch_seen: q_seen, scratch_phase: q_phase, scratch_stack: q_stack, scratch_post: q_post, scratch_rpo: q_rpo, scratch_child_count: q_child_count, scratch_counts: q_counts, scratch_child_start: q_child_start, scratch_filled: q_filled, scratch_children: q_children, scratch_estack: q_estack, scratch_edata: q_edata)
var r_words = try __s0_buffer_new(U64, d)
var r_pairs = try __s0_buffer_new(MirV6ReachFact, d)
var r_span = try __s0_buffer_new(U64, d)
var r_seen = try __s0_buffer_new(U64, d)
var r_queue = try __s0_buffer_new(U64, d)
var reach_plan = MirV6ReachPlan(words: r_words, pairs: r_pairs, span: r_span, seen: r_seen, queue: r_queue)
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { owner_stamp = owner_stamp + 1
// The point CFG and idom tree are built once per function; the loop rules use
// them for the "is this definition inside that loop" test, and reset
// invalidation consults them per mark instead of running an entry BFS per call.
let cfg_built = try mir_vp4_cfg_build(cfg_plan, d, store, indexes, function)
cfg_plan = cfg_built.plan
let cfg = cfg_built.cfg
let dom_built = try mir_vp4_dom_build(dom_plan, d, cfg)
dom_plan = dom_built.plan
let dom = dom_built.dom
let loops_built = try mir_v6_check_loops(d, store, indexes, analysis, owner_seen, owner_stamp, cfg, dom, function, reach_plan, out)
out = loops_built.out
reach_plan = loops_built.plan
let entries = try mir_v6_solve_states(d, store, indexes, analysis, cleanup, cfg, dom, function)
let reachable = try mir_vreachable(d, store, indexes, function)
let bcount = mir_vindex_block_count(indexes, function)
var block: U64 = 1
while block <= bcount { if mir_vseen_block(reachable, block) { var state = try mir_v6_entry_state(d, entries, block)
let icount = mir_vindex_instr_count(indexes, function, block)
var ordinal: U64 = 0
while ordinal < icount {
    let iid = mir_vindex_instr(indexes, function, block, ordinal)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if x.op == mir_op_store() && mir_v6_place_deref(store, x.place) { let value_type = mir_v5_value_type(store, indexes, function, x.a)
if try mir_v6_type_local_store(d, store, indexes, value_type) { out = try mir_v6_bad(d, out, mir_vdiag_lifetime_deref_store(), function, block, iid, 0, x.place, x.a) } }
    if x.op == mir_op_cleanup_scope_run() { out = try mir_v6_check_cleanup(d, store, indexes, cfg, dom, analysis, cleanup, state, function, block, iid, out) }
    var invalid = false
    let use_start = __s0_buffer_get(U64, inventory.instruction_start, iid - 1)
    let use_count = __s0_buffer_get(U64, inventory.instruction_count, iid - 1)
    var ui: U64 = 0
    while ui < use_count { let use = __s0_buffer_get(MirVP4Use, inventory.uses, use_start + ui)
if !invalid && use.instruction == iid && mir_v6_value_invalid(analysis, state, function, use.value) { invalid = true
out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_use(), function, block, iid, 0, use.operand, use.value) }
ui = ui + 1 }
    if (x.op == mir_op_domain_destroy() || x.op == mir_op_domain_reset()) && mir_v6_domain_dead(analysis, state, function, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_dead_domain(), function, block, iid, 0, 0, x.a) }
    if x.op == mir_op_domain_reset() { let marked = mir_v6_mark_domain(store, indexes, function, x.b)
if marked == 0 || !mir_v6_domains_alias(analysis, function, marked, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_mark_domain_mismatch(), function, block, iid, 0, 0, x.b) } }
    state = try mir_v6_apply(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x)
    ordinal = ordinal + 1
}
let term_id = mir_vindex_term(indexes, function, block)
if term_id != 0 {
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { if mir_v6_value_invalid(analysis, state, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_exit(), function, block, 0, term_id, 0, t.value) }
if mir_v6_escapes_local(analysis, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_local_domain_escape(), function, block, 0, term_id, 0, t.value) } }
} }
block = block + 1 }
function = function + 1 }
return Ok(out) }
fn mir_vphase6(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
let cleanup = try mir_v7_analyze(d, store, indexes, try __s0_buffer_new(MirVerifyDiagRec, d))
let analysis = try mir_v6_compute(d, store, indexes, cleanup)
let inventory = try mir_vp4_use_inventory_build(d, store, indexes)
return mir_vphase6_with(d, store, indexes, inventory, initial, cleanup, analysis) }
