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

type MirV6Fact {
    function: U64
    value: U64
    kind: U64
    a: U64
    b: U64
    c: U64
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
    fact_hash_next: __s0_Buffer(U64)
    effect_next: __s0_Buffer(U64)
}
type MirV6RoundIndex {
    stable_fact_count: U64
    fact_key_base: __s0_Buffer(U64)
    fact_span: __s0_Buffer(U64)
    fact_pos: __s0_Buffer(U64)
    fact_hash_span: __s0_Buffer(U64)
    fact_hash_pos: __s0_Buffer(U64)
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
type MirV6Reachability {
    facts: __s0_Buffer(MirV6ReachFact)
    span: __s0_Buffer(U64)
}
type MirV6TransferIndex {
    incoming_start: __s0_Buffer(U64)
    incoming_count: __s0_Buffer(U64)
    incoming_sources: __s0_Buffer(U64)
    store_start: __s0_Buffer(U64)
    store_count: __s0_Buffer(U64)
    stores: __s0_Buffer(U64)
}
type MirV6ConsumerIndex {
    head: __s0_Buffer(U64)
    tail: __s0_Buffer(U64)
    target: __s0_Buffer(U64)
    next: __s0_Buffer(U64)
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

// Rebuilds the fact and effect buckets from the current buffers. One pass
// counts records per bucket into function-local arrays, a prefix pass fixes
// the start positions, and a placement pass writes each record id once; the
// results are copied into buffers for storage in the analysis record. The
// index is exact for the buffer contents at build time. Appends made later in
// the same fixpoint iteration are found in the ordered tail. Once an iteration
// adds no new fact or effect, the loop terminates with an exact index that the
// per-function query passes can rely on.
fn mir_v6_fact_hash(item: MirV6Fact, buckets: U64) -> U64 {
    var hash: U64 = 0
    var mixed: U64 = 0
    hash = mir_vindex_hash_add(hash, item.function % buckets, buckets)
    mixed = mir_vindex_hash_add(hash, hash, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    hash = mir_vindex_hash_add(mir_vindex_hash_add(mixed, hash, buckets), item.value % buckets, buckets)
    mixed = mir_vindex_hash_add(hash, hash, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    hash = mir_vindex_hash_add(mir_vindex_hash_add(mixed, hash, buckets), item.kind % buckets, buckets)
    mixed = mir_vindex_hash_add(hash, hash, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    hash = mir_vindex_hash_add(mir_vindex_hash_add(mixed, hash, buckets), item.a % buckets, buckets)
    mixed = mir_vindex_hash_add(hash, hash, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    hash = mir_vindex_hash_add(mir_vindex_hash_add(mixed, hash, buckets), item.b % buckets, buckets)
    mixed = mir_vindex_hash_add(hash, hash, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    mixed = mir_vindex_hash_add(mixed, mixed, buckets)
    return mir_vindex_hash_add(mir_vindex_hash_add(mixed, hash, buckets), item.c % buckets, buckets)
}

fn mir_v6_round_index_build(d: Domain, store: MirStore, indexes: MirVIndexes, durable: MirV6Durable) -> Result(MirV6RoundIndex, __s0_Error) {
let fcount = __s0_buffer_len(MirFunctionRec, store.functions)
let total = __s0_buffer_len(MirV6Fact, durable.facts)
var key_base = __s0_alloc(U64, d, fcount + 1)
var z: U64 = 0
while z <= fcount { key_base[z] = 0
z = z + 1 }
var f: U64 = 1
while f <= fcount { key_base[f] = key_base[f - 1] + __s0_buffer_get(U64, indexes.value_count, f - 1)
f = f + 1 }
let total_keys = key_base[fcount]
var cnt = __s0_alloc(U64, d, total_keys + 2)
var base = __s0_alloc(U64, d, total_keys + 2)
var cursor = __s0_alloc(U64, d, total_keys + 2)
var k: U64 = 0
while k <= total_keys + 1 { cnt[k] = 0
base[k] = 0
cursor[k] = 0
k = k + 1 }
var i: U64 = 0
while i < total {
    let fact = __s0_buffer_get(MirV6Fact, durable.facts, i)
    if fact.function >= 1 && fact.function <= fcount {
        let key = key_base[fact.function - 1] + fact.value
        if key >= 1 && key <= total_keys { cnt[key] = cnt[key] + 1 }
    }
    i = i + 1
}
k = 0
while k <= total_keys { base[k + 1] = base[k] + cnt[k]
k = k + 1 }
k = 0
while k <= total_keys + 1 { cursor[k] = base[k] + 0
k = k + 1 }
let pos = __s0_alloc(U64, d, total)
i = 0
while i < total {
    let fact = __s0_buffer_get(MirV6Fact, durable.facts, i)
    if fact.function >= 1 && fact.function <= fcount {
        let key = key_base[fact.function - 1] + fact.value
        if key >= 1 && key <= total_keys { let slot = cursor[key]
pos[slot] = i + 1
cursor[key] = slot + 1 }
    }
    i = i + 1
}
var span = try __s0_buffer_new(U64, d)
k = 0
while k <= total_keys + 1 { span = try __s0_buffer_append(U64, d, span, base[k])
k = k + 1 }
var pos_buf = try __s0_buffer_new(U64, d)
var p: U64 = 0
while p < total { pos_buf = try __s0_buffer_append(U64, d, pos_buf, pos[p])
p = p + 1 }
var kb = try __s0_buffer_new(U64, d)
var f2: U64 = 0
while f2 < fcount { kb = try __s0_buffer_append(U64, d, kb, key_base[f2])
f2 = f2 + 1 }
// Membership uses a separate full-fact hash. Dense key buckets above retain
// insertion order for transfer and diagnostics; hash buckets are probes only.
let hash_buckets = total + 1
var hcnt = __s0_alloc(U64, d, hash_buckets)
var hbase = __s0_alloc(U64, d, hash_buckets + 1)
var hcursor = __s0_alloc(U64, d, hash_buckets)
var h: U64 = 0
while h < hash_buckets { hcnt[h] = 0
hbase[h] = 0
hcursor[h] = 0
h = h + 1 }
hbase[hash_buckets] = 0
i = 0
while i < total { let fact = __s0_buffer_get(MirV6Fact, durable.facts, i)
let slot = mir_v6_fact_hash(fact, hash_buckets)
hcnt[slot] = hcnt[slot] + 1
i = i + 1 }
h = 0
while h < hash_buckets { hbase[h + 1] = hbase[h] + hcnt[h]
hcursor[h] = hbase[h] + 0
h = h + 1 }
let hpos = __s0_alloc(U64, d, total)
i = 0
while i < total { let fact = __s0_buffer_get(MirV6Fact, durable.facts, i)
let slot = mir_v6_fact_hash(fact, hash_buckets)
hpos[hcursor[slot]] = i + 1
hcursor[slot] = hcursor[slot] + 1
i = i + 1 }
var hspan_buf = try __s0_buffer_new(U64, d)
h = 0
while h <= hash_buckets { hspan_buf = try __s0_buffer_append(U64, d, hspan_buf, hbase[h])
h = h + 1 }
var hpos_buf = try __s0_buffer_new(U64, d)
i = 0
while i < total { hpos_buf = try __s0_buffer_append(U64, d, hpos_buf, hpos[i])
i = i + 1 }
let etotal = __s0_buffer_len(MirV6Effect, durable.effects)
var ecnt = __s0_alloc(U64, d, fcount + 1)
var ebase = __s0_alloc(U64, d, fcount + 2)
var ecursor = __s0_alloc(U64, d, fcount + 2)
var e: U64 = 0
while e <= fcount + 1 { if e <= fcount { ecnt[e] = 0 }
ebase[e] = 0
ecursor[e] = 0
e = e + 1 }
i = 0
while i < etotal {
    let effect = __s0_buffer_get(MirV6Effect, durable.effects, i)
    if effect.function >= 1 && effect.function <= fcount { ecnt[effect.function] = ecnt[effect.function] + 1 }
    i = i + 1
}
f = 1
while f <= fcount + 1 { ebase[f] = ebase[f - 1] + ecnt[f - 1]
f = f + 1 }
e = 0
while e <= fcount + 1 { ecursor[e] = ebase[e] + 0
e = e + 1 }
let epos = __s0_alloc(U64, d, etotal)
i = 0
while i < etotal {
    let effect = __s0_buffer_get(MirV6Effect, durable.effects, i)
    if effect.function >= 1 && effect.function <= fcount { let slot = ecursor[effect.function]
epos[slot] = i + 1
ecursor[effect.function] = slot + 1 }
    i = i + 1
}
var espan = try __s0_buffer_new(U64, d)
e = 0
while e <= fcount + 1 { espan = try __s0_buffer_append(U64, d, espan, ebase[e])
e = e + 1 }
var epos_buf = try __s0_buffer_new(U64, d)
p = 0
while p < etotal { epos_buf = try __s0_buffer_append(U64, d, epos_buf, epos[p])
p = p + 1 }
let empty_index = try __s0_buffer_new(U64, d)
return Ok(MirV6RoundIndex(stable_fact_count: total, fact_key_base: kb, fact_span: span, fact_pos: pos_buf, fact_hash_span: hspan_buf, fact_hash_pos: hpos_buf, effect_span: espan, effect_pos: epos_buf, fact_key_head: empty_index, fact_key_tail: empty_index, fact_hash_head: empty_index, effect_head: empty_index, effect_tail: empty_index)) }

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
    // Sixteen buckets per MIR value keeps the final compiler corpus below
    // one fact per bucket while retaining deterministic fixed storage.
    let hash_buckets = total_keys * 16 + 1
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
    return Ok(MirV6RoundIndex(stable_fact_count: 0, fact_key_base: key_base, fact_span: empty, fact_pos: empty, fact_hash_span: empty, fact_hash_pos: empty, effect_span: empty, effect_pos: empty, fact_key_head: key_head, fact_key_tail: key_tail, fact_hash_head: hash_head, effect_head: effect_head, effect_tail: effect_tail))
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

fn mir_v6_fact_has(durable: MirV6Durable, index: MirV6RoundIndex, item: MirV6Fact) -> Bool {
let buckets = __s0_buffer_len(U64, index.fact_hash_head)
let slot = mir_v6_fact_hash(item, buckets)
var at = __s0_buffer_get(U64, index.fact_hash_head, slot)
while at != 0 { let x = __s0_buffer_get(MirV6Fact, durable.facts, at - 1)
    if x.function == item.function && x.value == item.value && x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
    at = __s0_buffer_get(U64, durable.fact_hash_next, at - 1)
}
return false }
fn mir_v6_fact_add(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, item: MirV6Fact) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
if mir_v6_fact_has(durable, index, item) { return Ok(durable) }
let key = mir_v6_round_fact_key(index, item.function, item.value)
if key == 0 { return Ok(durable) }
let slot = mir_v6_fact_hash(item, __s0_buffer_len(U64, index.fact_hash_head))
let old_hash = __s0_buffer_get(U64, index.fact_hash_head, slot)
let old_tail = __s0_buffer_get(U64, index.fact_key_tail, key)
durable.facts = try __s0_buffer_append(MirV6Fact, d, durable.facts, item)
durable.fact_key_next = try __s0_buffer_append(U64, d, durable.fact_key_next, 0)
durable.fact_hash_next = try __s0_buffer_append(U64, d, durable.fact_hash_next, old_hash)
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
    durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: target, kind: x.kind, a: x.a, b: x.b, c: x.c))
    if at == stop { return Ok(durable) }
    at = next
}
return Ok(durable) }

fn mir_v6_type_contains(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64, wanted: U64) -> Result(Bool, __s0_Error) { var work = try __s0_buffer_new(U64, d)
work = try __s0_buffer_append(U64, d, work, root)
// O(1) visited probe; the linear seen scan was quadratic on the dense type
// graph and ran once per value/use in phases 6, 9, and 10.
let tcount = __s0_buffer_len(MirTypeRec, store.types)
var seen = __s0_alloc(U64, d, tcount + 1)
var z: U64 = 0
while z <= tcount { seen[z] = 0
z = z + 1 }
var at: U64 = 0
while at < __s0_buffer_len(U64, work) { let id = __s0_buffer_get(U64, work, at)
if id >= 1 && id <= tcount && seen[id] == 0 { if mir_vtype_kind(store, id) == wanted { return Ok(true) }
seen[id] = 1
work = try mir_vappend_type_children(d, store, indexes, work, id) }
at = at + 1 }
return Ok(false) }
fn mir_v6_type_reference(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_slice()) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) }
fn mir_v6_type_local_store(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_reference(d, store, indexes, type_id) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_handle()) { return Ok(true) }
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
    let sources = __s0_alloc(U64, d, running)
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
    return Ok(MirV6TransferIndex(incoming_start: incoming_start, incoming_count: incoming_count, incoming_sources: incoming_sources, store_start: store_start, store_count: store_count, stores: store_ids))
}

fn mir_v6_consumer_add(d: Domain, index: MirV6RoundIndex, consumers0: MirV6ConsumerIndex, function: U64, source: U64, target: U64) -> Result(MirV6ConsumerIndex, __s0_Error) {
    var consumers = consumers0
    let key = mir_v6_round_fact_key(index, function, source)
    if key == 0 || target == 0 { return Ok(consumers) }
    let old_tail = __s0_buffer_get(U64, consumers.tail, key)
    consumers.target = try __s0_buffer_append(U64, d, consumers.target, target)
    consumers.next = try __s0_buffer_append(U64, d, consumers.next, 0)
    let edge = __s0_buffer_len(U64, consumers.target)
    if old_tail == 0 { __s0_buffer_set(U64, consumers.head, key, edge) }
    else { __s0_buffer_set(U64, consumers.next, old_tail - 1, edge) }
    __s0_buffer_set(U64, consumers.tail, key, edge)
    return Ok(consumers)
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
    var consumers = MirV6ConsumerIndex(head: head, tail: tail, target: try __s0_buffer_new(U64, d), next: try __s0_buffer_new(U64, d))
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
                if x.op == mir_op_domain_create() || x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() {
                    consumers = try mir_v6_consumer_add(d, round, consumers, function, x.a, value_id)
                }
                if x.op == mir_op_copy_to_domain() { consumers = try mir_v6_consumer_add(d, round, consumers, function, x.b, value_id) }
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

fn mir_v6_transfer_value(d: Domain, store: MirStore, indexes: MirVIndexes, transfer: MirV6TransferIndex, index: MirV6RoundIndex, durable0: MirV6Durable, function: U64, value_id: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
let vi = mir_vindex_value(indexes, function, value_id)
let value = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if value.def_kind == mir_value_def_function_param() { let parameter = mir_v6_function_param_ordinal(store, indexes, function, value_id)
durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_param(), a: parameter, b: 0, c: 0))
if try mir_v6_type_reference(d, store, indexes, value.value_type) { let pcount = mir_vindex_param_count(indexes, function)
var pi: U64 = 0
while pi < pcount { let p = __s0_buffer_get(MirParamRec, store.params, mir_vindex_param(indexes, function, pi) - 1)
if p.kind == mir_param_function() && mir_vtype_kind(store, p.param_type) == mir_type_kind_domain_handle() { durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: p.ordinal + 1, c: 0)) }
pi = pi + 1 }
durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: value_id, b: 0, c: parameter)) }
if mir_vtype_kind(store, value.value_type) == mir_type_kind_domain_handle() { durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: parameter, c: 0)) }
return Ok(durable) }
if value.def_kind == mir_value_def_block_param() {
    let parameter = mir_v6_block_param_record(store, indexes, function, value.block, value.item - 1)
    if parameter != 0 {
        let start = __s0_buffer_get(U64, transfer.incoming_start, parameter - 1)
        let count = __s0_buffer_get(U64, transfer.incoming_count, parameter - 1)
        var incoming: U64 = 0
        while incoming < count {
            durable = try mir_v6_merge_value(d, durable, index, function, value_id, __s0_buffer_get(U64, transfer.incoming_sources, start + incoming))
            incoming = incoming + 1
        }
    }
    return Ok(durable)
}
if value.def_kind == mir_value_def_switch_case() { let term_id = mir_vindex_term(indexes, function, value.block)
if term_id != 0 { let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
durable = try mir_v6_merge_value(d, durable, index, function, value_id, t.value) }
return Ok(durable) }
let iid = mir_v6_instruction_for_value(store, indexes, value)
if iid == 0 { return Ok(durable) }
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
if x.op == mir_op_domain_create() { var at = mir_v6_round_fact_start(index, function, x.a)
while at != 0 { let f = mir_v6_round_fact_at(durable, at)
if f.kind == mir_v6_fact_dep() || f.kind == mir_v6_fact_parent() { durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_parent(), a: f.a, b: f.b, c: f.c)) }
at = mir_v6_round_fact_next(durable, at) }
durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: x.block, b: x.ordinal + 1, c: 0)) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() { durable = try mir_v6_merge_value(d, durable, index, function, value_id, x.a)
if x.op == mir_op_copy_to_domain() { durable = try mir_v6_merge_value(d, durable, index, function, value_id, x.b) }
durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: x.a, b: x.block, c: x.ordinal + 1)) }
if x.op == mir_op_load() { let p = __s0_buffer_get(MirPlaceRec, store.places, x.place - 1)
if p.kind == mir_place_deref() { durable = try mir_v6_merge_value(d, durable, index, function, value_id, p.deref_value) }
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
if mir_v6_places_alias(store, indexes, x.place, load_deref, load_root, load_depth, placed.place) { durable = try mir_v6_merge_value(d, durable, index, function, value_id, placed.a) }
store_at = store_at + 1 } }
if x.op == mir_op_aggregate_construct() { let total = mir_vindex_op_instr_count(indexes, iid)
var oi: U64 = 0
while oi < total { let o = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_instr(indexes, iid, oi) - 1)
if o.kind == mir_operand_aggregate_field() { durable = try mir_v6_merge_value(d, durable, index, function, value_id, o.value) }
oi = oi + 1 } }
if x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() { durable = try mir_v6_merge_value(d, durable, index, function, value_id, x.a) }
if x.op == mir_op_call() { var e = mir_v6_round_effect_start(index, x.target)
while e != 0 { let effect = mir_v6_round_effect_at(durable, e)
if effect.kind == mir_v6_effect_result_from() || effect.kind == mir_v6_effect_result_alloc() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
durable = try mir_v6_merge_value(d, durable, index, function, value_id, arg)
if effect.kind == mir_v6_effect_result_alloc() { durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: arg, b: x.block, c: x.ordinal + 1)) } }
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
    durable = try mir_v6_transfer_value(d, store, indexes, transfer, index, durable, function, value)
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
var durable = MirV6Durable(facts: try __s0_buffer_new(MirV6Fact, d), effects: try __s0_buffer_new(MirV6Effect, d), fact_key_next: try __s0_buffer_new(U64, d), fact_hash_next: try __s0_buffer_new(U64, d), effect_next: try __s0_buffer_new(U64, d))
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
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_table_create() || x.op == mir_op_call() { state = try mir_v6_clear_produced(d, state, x.block, x.ordinal) }
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
fn mir_v6_successors(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, block: U64, out0: __s0_Buffer(U64)) -> Result(__s0_Buffer(U64), __s0_Error) { var out = out0
let icount = mir_vindex_instr_count(indexes, function, block)
var ii: U64 = 0
while ii < icount {
    let iid = mir_vindex_instr(indexes, function, block, ii)
    let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
    if mir_vop_checked(x.op) { out = try __s0_buffer_append(U64, d, out, x.target) }
    ii = ii + 1
}
let term_id = mir_vindex_term(indexes, function, block)
if term_id != 0 {
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if t.kind == mir_term_jump() { out = try __s0_buffer_append(U64, d, out, t.target) }
    if t.kind == mir_term_branch() { out = try __s0_buffer_append(U64, d, out, t.then_block)
out = try __s0_buffer_append(U64, d, out, t.else_block) }
    if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
var oi: U64 = 0
while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
if c.kind == mir_operand_switch_case() { out = try __s0_buffer_append(U64, d, out, c.target) }
oi = oi + 1 } }
}
return Ok(out) }
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
let successors = try mir_v6_successors(d, store, indexes, function, block, try __s0_buffer_new(U64, d))
var si: U64 = 0
while si < __s0_buffer_len(U64, successors) { let target = __s0_buffer_get(U64, successors, si)
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
    if from == 0 || from >= __s0_buffer_len(U64, reach.span) { return false }
    var at = __s0_buffer_get(U64, reach.span, from - 1)
    let end = __s0_buffer_get(U64, reach.span, from)
    while at < end {
        if __s0_buffer_get(MirV6ReachFact, reach.facts, at).to == to { return true }
        at = at + 1
    }
    return false
}
fn mir_v6_reachability(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(MirV6Reachability, __s0_Error) {
    var reach = try __s0_buffer_new(MirV6ReachFact, d)
    var span = try __s0_buffer_new(U64, d)
    let bcount = mir_vindex_block_count(indexes, function)
    var seen = try __s0_buffer_new(U64, d)
    var block: U64 = 0
    while block <= bcount {
        seen = try __s0_buffer_append(U64, d, seen, 0)
        block = block + 1
    }
    var from: U64 = 1
    while from <= bcount {
        span = try __s0_buffer_append(U64, d, span, __s0_buffer_len(MirV6ReachFact, reach))
        var queue = try mir_v6_successors(d, store, indexes, function, from, try __s0_buffer_new(U64, d))
        var q: U64 = 0
        while q < __s0_buffer_len(U64, queue) {
            let to = __s0_buffer_get(U64, queue, q)
            if to >= 1 && to <= bcount && __s0_buffer_get(U64, seen, to) != from {
                __s0_buffer_set(U64, seen, to, from)
                reach = try __s0_buffer_append(MirV6ReachFact, d, reach, MirV6ReachFact(from: from, to: to))
                queue = try mir_v6_successors(d, store, indexes, function, to, queue)
            }
            q = q + 1
        }
        from = from + 1
    }
    span = try __s0_buffer_append(U64, d, span, __s0_buffer_len(MirV6ReachFact, reach))
    return Ok(MirV6Reachability(facts: reach, span: span))
}
fn mir_v6_local_provenance(analysis: MirV6Analysis, function: U64, value: U64) -> Bool { var at = mir_v6_fact_start(analysis, function, value)
let end = mir_v6_fact_end(analysis, function, value)
while at < end { let x = mir_v6_fact_at(analysis, at)
if (x.kind == mir_v6_fact_dep() && x.a != 0) || (x.kind == mir_v6_fact_root() && x.b != 0) { return true }
at = at + 1 }
return false }
fn mir_v6_stable_loop_store(store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, function: U64, value: U64, place: U64) -> Bool { if mir_v6_place_deref(store, place) { return false }
var e = mir_v6_effect_start(analysis, function)
let eend = mir_v6_effect_end(analysis, function)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { return false }
e = e + 1 }
var local_root = false
var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() && fact.a != 0 { return false }
if fact.kind == mir_v6_fact_root() && fact.b != 0 { local_root = true
var parameter_domain = false
var h = mir_v6_fact_start(analysis, function, fact.a)
let hend = mir_v6_fact_end(analysis, function, fact.a)
while h < hend { let owner = mir_v6_fact_at(analysis, h)
if owner.kind == mir_v6_fact_dep() && owner.a != 0 { return false }
if owner.kind == mir_v6_fact_param() { let vi = mir_vindex_value(indexes, function, fact.a)
if vi != 0 && mir_vtype_kind(store, __s0_buffer_get(MirValueRec, store.values, vi - 1).value_type) == mir_type_kind_domain_handle() { parameter_domain = true } }
h = h + 1 }
if !parameter_domain { return false } }
f = f + 1 }
return local_root }
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
fn mir_v6_check_loops(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, function: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
let reach = try mir_v6_reachability(d, store, indexes, function)
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
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } }
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
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } }
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
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, a.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, aid, p.value) } }
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
        if x.op == mir_op_store() && mir_v6_reach_has(reach, x.block, x.block) && mir_v6_local_provenance(analysis, function, x.a) && !mir_v6_stable_loop_store(store, indexes, analysis, function, x.a, x.place) { out = try mir_v6_bad(d, out, mir_vdiag_loop_store_resource(), function, x.block, iid, 0, x.place, x.a) }
        ii = ii + 1
    }
    b2 = b2 + 1
}
return Ok(out) }
fn mir_vphase6_with(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, initial: __s0_Buffer(MirVerifyDiagRec), cleanup: MirV7Analysis, analysis: MirV6Analysis) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = initial
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { out = try mir_v6_check_loops(d, store, indexes, analysis, function, out)
// The point CFG and idom tree are built once per function; reset invalidation
// consults them per mark instead of running an entry BFS per call.
let cfg = try mir_vp4_cfg_build(d, store, indexes, function)
let dom = try mir_vp4_dom_build(d, cfg)
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
