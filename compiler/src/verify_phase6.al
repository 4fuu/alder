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
    facts: Vec(MirV6Fact)
    effects: Vec(MirV6Effect)
    // fact_key_base[function - 1] is the linearized key offset of the
    // function's first value, so key = fact_key_base[function - 1] + value
    // maps each (function, value) pair to a dense slot in fact_span/fact_pos.
    fact_key_base: Vec(U64)
    // fact_span[key] is the start position of key's bucket in fact_pos;
    // fact_span[key + 1] is its end (fact_span has a trailing sentinel).
    fact_span: Vec(U64)
    fact_pos: Vec(U64)
    // effect_span[function] / effect_span[function + 1] delimit the
    // function's effect bucket in effect_pos (trailing sentinel included).
    effect_span: Vec(U64)
    effect_pos: Vec(U64)
}
type MirV6Durable {
    facts: Vec(MirV6Fact)
    effects: Vec(MirV6Effect)
    fact_key_next: Vec(U64)
    fact_hash_next: Vec(U64)
    effect_next: Vec(U64)
    fact_key_head: Vec(U64)
    fact_key_tail: Vec(U64)
    fact_hash_head: Vec(U64)
    effect_head: Vec(U64)
    effect_tail: Vec(U64)
}
type MirV6FactRead {
    facts: [MirV6Fact]
    effects: [MirV6Effect]
    fact_key_next: [U64]
    fact_hash_next: [U64]
    effect_next: [U64]
    fact_key_base: [U64]
    fact_key_head: [U64]
    fact_key_tail: [U64]
    fact_hash_head: [U64]
    effect_head: [U64]
}
type MirV6MergeCursor {
    at: U64
    stop: U64
    candidate: U64
    candidate_limit: U64
}
type MirV6MergeStep {
    found: Bool
    item: MirV6Fact
    cursor: MirV6MergeCursor
}
type MirV6InputRead {
    names: [U8]
    types: [MirTypeRec]
    type_parts: [MirTypePartRec]
    functions: [MirFunctionRec]
    params: [MirParamRec]
    values: [MirValueRec]
    places: [MirPlaceRec]
    instructions: [MirInstrRec]
    terminators: [MirTermRec]
    operands: [MirOperandRec]
    value_pos: [U64]
    value_span: [U64]
    value_count: [U64]
    param_span: [U64]
    param_ids: [U64]
    term_pos: [U64]
    term_span: [U64]
    block_count: [U64]
    block_span: [U64]
    instr_span: [U64]
    instr_count: [U64]
    instr_off: [U64]
    instr_ids: [U64]
    op_instr_start: [U64]
    op_instr_count: [U64]
    op_instr_ids: [U64]
    tp_start: [U64]
    tp_count: [U64]
    tp_ids: [U64]
    place_root: [U64]
    place_depth: [U64]
    place_deref: [U64]
    incoming_start: [U64]
    incoming_count: [U64]
    incoming_sources: [U64]
    store_start: [U64]
    store_count: [U64]
    stores: [U64]
}
type MirV6RoundIndex {
    stable_fact_count: U64
    fact_key_base: Vec(U64)
    fact_span: Vec(U64)
    fact_pos: Vec(U64)
    fact_hash_span: Vec(U64)
    fact_hash_pos: Vec(U64)
    effect_span: Vec(U64)
    effect_pos: Vec(U64)
    fact_key_head: Vec(U64)
    fact_key_tail: Vec(U64)
    fact_hash_head: Vec(U64)
    effect_head: Vec(U64)
    effect_tail: Vec(U64)
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
    items: Vec(MirV6EntryFact)
    next: Vec(U64)
    head: Vec(U64)
    tail: Vec(U64)
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
    facts: Vec(MirV6ReachFact)
    span: Vec(U64)
}
type MirV6TransferIndex {
    incoming_start: Vec(U64)
    incoming_count: Vec(U64)
    incoming_sources: Vec(U64)
    store_start: Vec(U64)
    store_count: Vec(U64)
    stores: Vec(U64)
}
type MirV6ConsumerIndex {
    head: Vec(U64)
    tail: Vec(U64)
    target: Vec(U64)
    next: Vec(U64)
}

fn mir_v6_fact_start(analysis: MirV6Analysis, function: U64, value: U64) -> U64 { let kb = analysis.fact_key_base
if function == 0 || function > (kb).len() { return 0 }
let key = kb[function - 1] + value
let span = analysis.fact_span
if key >= (span).len() - 1 { return 0 }
return span[key] }
fn mir_v6_fact_end(analysis: MirV6Analysis, function: U64, value: U64) -> U64 { let kb = analysis.fact_key_base
if function == 0 || function > (kb).len() { return 0 }
let key = kb[function - 1] + value
let span = analysis.fact_span
if key >= (span).len() - 1 { return 0 }
return span[key + 1] }
fn mir_v6_effect_start(analysis: MirV6Analysis, function: U64) -> U64 { let span = analysis.effect_span
if function == 0 || function >= (span).len() { return 0 }
return span[function] }
fn mir_v6_effect_end(analysis: MirV6Analysis, function: U64) -> U64 { let span = analysis.effect_span
if function == 0 || function >= (span).len() { return 0 }
return span[function + 1] }
fn mir_v6_fact_at(analysis: MirV6Analysis, at: U64) -> MirV6Fact { return (analysis.facts)[(analysis.fact_pos)[at] - 1] }
fn mir_v6_effect_at(analysis: MirV6Analysis, at: U64) -> MirV6Effect { return (analysis.effects)[(analysis.effect_pos)[at] - 1] }

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
let fcount = (store.functions).len()
let total = (durable.facts).len()
var key_base = __s0_alloc(U64, d, fcount + 1)
var z: U64 = 0
while z <= fcount { key_base[z] = 0
z = z + 1 }
var f: U64 = 1
while f <= fcount { key_base[f] = key_base[f - 1] + (indexes.value_count)[f - 1]
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
    let fact = (durable.facts)[i]
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
var pos = __s0_alloc(U64, d, total)
i = 0
while i < total {
    let fact = (durable.facts)[i]
    if fact.function >= 1 && fact.function <= fcount {
        let key = key_base[fact.function - 1] + fact.value
        if key >= 1 && key <= total_keys { let slot = cursor[key]
pos[slot] = i + 1
cursor[key] = slot + 1 }
    }
    i = i + 1
}
var span = Vec.new(U64)
k = 0
while k <= total_keys + 1 { try span.try_push(base[k])
k = k + 1 }
var pos_buf = Vec.new(U64)
var p: U64 = 0
while p < total { try pos_buf.try_push(pos[p])
p = p + 1 }
var kb = Vec.new(U64)
var f2: U64 = 0
while f2 < fcount { try kb.try_push(key_base[f2])
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
while i < total { let fact = (durable.facts)[i]
let slot = mir_v6_fact_hash(fact, hash_buckets)
hcnt[slot] = hcnt[slot] + 1
i = i + 1 }
h = 0
while h < hash_buckets { hbase[h + 1] = hbase[h] + hcnt[h]
hcursor[h] = hbase[h] + 0
h = h + 1 }
var hpos = __s0_alloc(U64, d, total)
i = 0
while i < total { let fact = (durable.facts)[i]
let slot = mir_v6_fact_hash(fact, hash_buckets)
hpos[hcursor[slot]] = i + 1
hcursor[slot] = hcursor[slot] + 1
i = i + 1 }
var hspan_buf = Vec.new(U64)
h = 0
while h <= hash_buckets { try hspan_buf.try_push(hbase[h])
h = h + 1 }
var hpos_buf = Vec.new(U64)
i = 0
while i < total { try hpos_buf.try_push(hpos[i])
i = i + 1 }
let etotal = (durable.effects).len()
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
    let effect = (durable.effects)[i]
    if effect.function >= 1 && effect.function <= fcount { ecnt[effect.function] = ecnt[effect.function] + 1 }
    i = i + 1
}
f = 1
while f <= fcount + 1 { ebase[f] = ebase[f - 1] + ecnt[f - 1]
f = f + 1 }
e = 0
while e <= fcount + 1 { ecursor[e] = ebase[e] + 0
e = e + 1 }
var epos = __s0_alloc(U64, d, etotal)
i = 0
while i < etotal {
    let effect = (durable.effects)[i]
    if effect.function >= 1 && effect.function <= fcount { let slot = ecursor[effect.function]
epos[slot] = i + 1
ecursor[effect.function] = slot + 1 }
    i = i + 1
}
var espan = Vec.new(U64)
e = 0
while e <= fcount + 1 { try espan.try_push(ebase[e])
e = e + 1 }
var epos_buf = Vec.new(U64)
p = 0
while p < etotal { try epos_buf.try_push(epos[p])
p = p + 1 }
let empty_index = Vec.new(U64)
return Ok(MirV6RoundIndex(stable_fact_count: total, fact_key_base: kb, fact_span: span, fact_pos: pos_buf, fact_hash_span: hspan_buf, fact_hash_pos: hpos_buf, effect_span: espan, effect_pos: epos_buf, fact_key_head: empty_index, fact_key_tail: empty_index, fact_hash_head: empty_index, effect_head: empty_index, effect_tail: empty_index)) }

fn mir_v6_live_index_build(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirV6RoundIndex, __s0_Error) {
    let fcount = (store.functions).len()
    var key_base = Vec.new(U64)
    var total_keys: U64 = 0
    var function: U64 = 1
    while function <= fcount {
        try key_base.try_push(total_keys)
        total_keys = total_keys + (indexes.value_count)[function - 1]
        function = function + 1
    }
    var key_head = Vec.new(U64)
    var key_tail = Vec.new(U64)
    var key: U64 = 0
    while key <= total_keys {
        try key_head.try_push(0)
        try key_tail.try_push(0)
        key = key + 1
    }
    // Sixteen buckets per MIR value keeps the final compiler corpus below
    // one fact per bucket while retaining deterministic fixed storage.
    let hash_buckets = total_keys * 16 + 1
    var hash_head = Vec.new(U64)
    var bucket: U64 = 0
    while bucket < hash_buckets {
        try hash_head.try_push(0)
        bucket = bucket + 1
    }
    var effect_head = Vec.new(U64)
    var effect_tail = Vec.new(U64)
    function = 0
    while function <= fcount {
        try effect_head.try_push(0)
        try effect_tail.try_push(0)
        function = function + 1
    }
    let empty = Vec.new(U64)
    return Ok(MirV6RoundIndex(stable_fact_count: 0, fact_key_base: key_base, fact_span: empty, fact_pos: empty, fact_hash_span: empty, fact_hash_pos: empty, effect_span: empty, effect_pos: empty, fact_key_head: key_head, fact_key_tail: key_tail, fact_hash_head: hash_head, effect_head: effect_head, effect_tail: effect_tail))
}

fn mir_v6_finalize(d: Domain, store: MirStore, index: MirV6RoundIndex, durable: MirV6Durable) -> Result(MirV6Analysis, __s0_Error) {
    var fact_span = Vec.new(U64)
    var fact_pos = Vec.new(U64)
    var key: U64 = 0
    while key < (durable.fact_key_head).len() {
        try fact_span.try_push((fact_pos).len())
        var fact = (durable.fact_key_head)[key]
        while fact != 0 {
            try fact_pos.try_push(fact)
            fact = (durable.fact_key_next)[fact - 1]
        }
        key = key + 1
    }
    try fact_span.try_push((fact_pos).len())
    var effect_span = Vec.new(U64)
    var effect_pos = Vec.new(U64)
    var function: U64 = 0
    while function < (durable.effect_head).len() {
        try effect_span.try_push((effect_pos).len())
        var effect = (durable.effect_head)[function]
        while effect != 0 {
            try effect_pos.try_push(effect)
            effect = (durable.effect_next)[effect - 1]
        }
        function = function + 1
    }
    try effect_span.try_push((effect_pos).len())
    return Ok(MirV6Analysis(facts: durable.facts, effects: durable.effects, fact_key_base: index.fact_key_base, fact_span: fact_span, fact_pos: fact_pos, effect_span: effect_span, effect_pos: effect_pos))
}

fn mir_v6_round_fact_key(index: MirV6RoundIndex, function: U64, value: U64) -> U64 {
    if function == 0 || function > (index.fact_key_base).len() { return 0 }
    let base = (index.fact_key_base)[function - 1]
    var end = (index.fact_key_head).len() - 1
    if function < (index.fact_key_base).len() { end = (index.fact_key_base)[function] }
    if value == 0 || value > end - base { return 0 }
    return base + value
}
fn mir_v6_round_fact_start(index: MirV6RoundIndex, function: U64, value: U64, fact_key_head: [U64]) -> U64 {
    let key = mir_v6_round_fact_key(index, function, value)
    if key == 0 { return 0 }
    return fact_key_head[key]
}
fn mir_v6_round_fact_next(fact: U64, fact_key_next: [U64]) -> U64 {
    if fact == 0 || fact > len(fact_key_next) { return 0 }
    return fact_key_next[fact - 1]
}
fn mir_v6_round_fact_at(at: U64, facts: [MirV6Fact]) -> MirV6Fact { return facts[at - 1] }
fn mir_v6_round_effect_start(function: U64, effect_head: [U64]) -> U64 {
    if function == 0 || function >= len(effect_head) { return 0 }
    return effect_head[function]
}
fn mir_v6_round_effect_next(effect: U64, effect_next: [U64]) -> U64 {
    if effect == 0 || effect > len(effect_next) { return 0 }
    return effect_next[effect - 1]
}
fn mir_v6_round_effect_at(at: U64, effects: [MirV6Effect]) -> MirV6Effect { return effects[at - 1] }

fn mir_v6_input_value(input: MirV6InputRead, function: U64, value: U64) -> U64 {
    if function == 0 || function > len(input.value_count) { return 0 }
    let count = input.value_count[function - 1]
    if value == 0 || value > count { return 0 }
    return input.value_pos[input.value_span[function - 1] + value - 1]
}
fn mir_v6_input_param_count(input: MirV6InputRead, function: U64) -> U64 {
    if function == 0 || function > len(input.param_span) { return 0 }
    if function < len(input.param_span) { return input.param_span[function] - input.param_span[function - 1] }
    return len(input.param_ids) - input.param_span[function - 1]
}
fn mir_v6_input_param(input: MirV6InputRead, function: U64, at: U64) -> U64 {
    let count = mir_v6_input_param_count(input, function)
    if at >= count { return 0 }
    return input.param_ids[input.param_span[function - 1] + at]
}
fn mir_v6_input_term(input: MirV6InputRead, function: U64, block: U64) -> U64 {
    if function == 0 || function > len(input.block_count) { return 0 }
    if block == 0 || block > input.block_count[function - 1] { return 0 }
    return input.term_pos[input.term_span[function - 1] + block - 1]
}
fn mir_v6_input_instr(input: MirV6InputRead, function: U64, block: U64, ordinal: U64) -> U64 {
    if function == 0 || function > len(input.block_count) { return 0 }
    if block == 0 || block > input.block_count[function - 1] { return 0 }
    let slot = input.block_span[function - 1] + block - 1
    if ordinal >= input.instr_count[slot] { return 0 }
    return input.instr_ids[input.instr_span[function - 1] + input.instr_off[slot] + ordinal]
}
fn mir_v6_input_instruction_for_value(input: MirV6InputRead, value: MirValueRec) -> U64 {
    if value.def_kind != mir_value_def_instruction() { return 0 }
    return mir_v6_input_instr(input, value.function, value.block, value.item - 1)
}
fn mir_v6_input_type_kind(input: MirV6InputRead, id: U64) -> U64 {
    if id == 0 || id > len(input.types) { return 999 }
    return input.types[id - 1].kind
}
fn mir_v6_input_function_param(input: MirV6InputRead, function: U64, value: U64) -> U64 {
    let count = mir_v6_input_param_count(input, function)
    var at: U64 = 0
    while at < count { let p = input.params[mir_v6_input_param(input, function, at) - 1]
        if p.kind == mir_param_function() && p.value == value { return p.ordinal + 1 }
        at = at + 1 }
    return 0
}
fn mir_v6_input_block_param(input: MirV6InputRead, function: U64, block: U64, ordinal: U64) -> U64 {
    let count = mir_v6_input_param_count(input, function)
    var at: U64 = 0
    while at < count { let id = mir_v6_input_param(input, function, at)
        let p = input.params[id - 1]
        if p.kind == mir_param_block() && p.block == block && p.ordinal == ordinal { return id }
        at = at + 1 }
    return 0
}
fn mir_v6_input_operand_value(input: MirV6InputRead, owner: U64, ordinal: U64) -> U64 {
    if owner == 0 || owner > len(input.op_instr_count) { return 0 }
    let count = input.op_instr_count[owner - 1]
    var at: U64 = 0
    while at < count { let id = input.op_instr_ids[input.op_instr_start[owner - 1] + at]
        let operand = input.operands[id - 1]
        if operand.kind == mir_operand_instruction() && operand.edge == 0 && operand.ordinal == ordinal { return operand.value }
        at = at + 1 }
    return 0
}
fn mir_v6_input_type_contains(d: Domain, input: MirV6InputRead, root: U64, wanted: U64) -> Result(Bool, __s0_Error) {
    var work = Vec.new(U64)
    try work.try_push(root)
    let type_count = len(input.types)
    var seen = __s0_alloc(U64, d, type_count + 1)
    var z: U64 = 0
    while z <= type_count { seen[z] = 0
        z = z + 1 }
    var at: U64 = 0
    while at < (work).len() { let id = work[at]
        if id >= 1 && id <= type_count && seen[id] == 0 {
            let t = input.types[id - 1]
            if t.kind == wanted { return Ok(true) }
            seen[id] = 1
            if t.kind == mir_type_kind_option() || t.kind == mir_type_kind_slice() || t.kind == mir_type_kind_safe_ref() || t.kind == mir_type_kind_safe_mut() || t.kind == mir_type_kind_raw_ptr() || t.kind == mir_type_kind_table() || t.kind == mir_type_kind_id() || t.kind == mir_type_kind_table_view() || t.kind == mir_type_kind_table_mut_view() || t.kind == mir_type_kind_array() || t.kind == mir_type_kind_vec() { try work.try_push(t.elem) }
            if t.kind == mir_type_kind_result() { try work.try_push(t.ok_type)
                try work.try_push(t.err_type) }
            if t.kind == mir_type_kind_function() || t.kind == mir_type_kind_aggregate() || t.kind == mir_type_kind_enum() {
                let count = input.tp_count[id - 1]
                var part_at: U64 = 0
                while part_at < count { let part = input.type_parts[input.tp_ids[input.tp_start[id - 1] + part_at] - 1]
                    if t.kind != mir_type_kind_function() || part.kind == mir_type_part_function_param() { try work.try_push(part.part_type) }
                    part_at = part_at + 1 }
                if t.kind == mir_type_kind_function() { try work.try_push(t.result_type) }
            }
        }
        at = at + 1
    }
    return Ok(false)
}
fn mir_v6_input_type_reference(d: Domain, input: MirV6InputRead, type_id: U64) -> Result(Bool, __s0_Error) {
    if try mir_v6_input_type_contains(d, input, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
    if try mir_v6_input_type_contains(d, input, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
    if try mir_v6_input_type_contains(d, input, type_id, mir_type_kind_slice()) { return Ok(true) }
    if try mir_v6_input_type_contains(d, input, type_id, mir_type_kind_vec()) { return Ok(true) }
    return mir_v6_input_type_contains(d, input, type_id, mir_type_kind_table())
}
fn mir_v6_input_name_equal(input: MirV6InputRead, a_start: U64, a_end: U64, b_start: U64, b_end: U64) -> Bool {
    if a_start > a_end || a_end > len(input.names) || b_start > b_end || b_end > len(input.names) || a_end - a_start != b_end - b_start { return false }
    var at: U64 = 0
    while at < a_end - a_start { if input.names[a_start + at] != input.names[b_start + at] { return false }
        at = at + 1 }
    return true
}
fn mir_v6_input_place_component(input: MirV6InputRead, place0: U64, depth: U64, ordinal: U64) -> U64 {
    var place = place0
    var remaining = depth - ordinal - 1
    while remaining != 0 { place = input.places[place - 1].base
        remaining = remaining - 1 }
    return place
}
fn mir_v6_input_places_alias(input: MirV6InputRead, a: U64, ad: Bool, ar: U64, an: U64, b: U64) -> Bool {
    let bd = input.place_deref[b - 1] != 0
    if ad || bd { return ad && bd }
    if ar != input.place_root[b - 1] { return false }
    let bn = input.place_depth[b - 1]
    var limit = an
    if bn < limit { limit = bn }
    var n: U64 = 0
    while n < limit { let ap = input.places[mir_v6_input_place_component(input, a, an, n) - 1]
        let bp = input.places[mir_v6_input_place_component(input, b, bn, n) - 1]
        if !mir_v6_input_name_equal(input, ap.field_start, ap.field_end, bp.field_start, bp.field_end) { return false }
        n = n + 1 }
    return true
}

fn mir_v6_fact_candidate_present(item: MirV6Fact, read: MirV6FactRead, proposed: [MirV6Fact]) -> Bool {
    let slot = mir_v6_fact_hash(item, len(read.fact_hash_head))
    var existing = read.fact_hash_head[slot]
    while existing != 0 {
        let prior = read.facts[existing - 1]
        if prior.function == item.function && prior.value == item.value && prior.kind == item.kind && prior.a == item.a && prior.b == item.b && prior.c == item.c { return true }
        existing = read.fact_hash_next[existing - 1]
    }
    var at: U64 = 0
    while at < len(proposed) {
        let prior = proposed[at]
        if prior.function == item.function && prior.value == item.value && prior.kind == item.kind && prior.a == item.a && prior.b == item.b && prior.c == item.c { return true }
        at = at + 1
    }
    return false
}

fn mir_v6_read_fact_key(function: U64, value: U64, read: MirV6FactRead) -> U64 {
    if function == 0 || function > len(read.fact_key_base) { return 0 }
    let base = read.fact_key_base[function - 1]
    var end = len(read.fact_key_head) - 1
    if function < len(read.fact_key_base) { end = read.fact_key_base[function] }
    if value == 0 || value > end - base { return 0 }
    return base + value
}
fn mir_v6_merge_start(function: U64, source: U64, proposed_count: U64, read: MirV6FactRead) -> MirV6MergeCursor {
    let key = mir_v6_read_fact_key(function, source, read)
    if key == 0 { return MirV6MergeCursor(at: 0, stop: 0, candidate: proposed_count, candidate_limit: proposed_count) }
    return MirV6MergeCursor(at: read.fact_key_head[key], stop: read.fact_key_tail[key], candidate: 0, candidate_limit: proposed_count)
}
fn mir_v6_merge_next(cursor0: MirV6MergeCursor, function: U64, source: U64, read: MirV6FactRead, proposed: [MirV6Fact]) -> MirV6MergeStep {
    var cursor = cursor0
    if cursor.at != 0 {
        let item = read.facts[cursor.at - 1]
        if cursor.at == cursor.stop { cursor.at = 0 }
        else { cursor.at = read.fact_key_next[cursor.at - 1] }
        return MirV6MergeStep(found: true, item: item, cursor: cursor)
    }
    while cursor.candidate < cursor.candidate_limit {
        let item = proposed[cursor.candidate]
        cursor.candidate = cursor.candidate + 1
        if item.function == function && item.value == source { return MirV6MergeStep(found: true, item: item, cursor: cursor) }
    }
    return MirV6MergeStep(found: false, item: MirV6Fact(function: 0, value: 0, kind: 0, a: 0, b: 0, c: 0), cursor: cursor)
}

// Merge proposals are bounded to one value transfer. Passing this small
// overlay preserves source order without copying the compiler-scale durable
// store; the round owner performs the actual append commit.
fn mir_v6_merge_propose(items0: Vec(MirV6Fact), function: U64, target: U64, source: U64, read: MirV6FactRead) -> Result(Vec(MirV6Fact), __s0_Error) {
    var items = items0
    var cursor = mir_v6_merge_start(function, source, (items).len(), read)
    var step = mir_v6_merge_next(cursor, function, source, read, items.slice(0, (items).len()))
    while step.found {
        let x = step.item
        let item = MirV6Fact(function: function, value: target, kind: x.kind, a: x.a, b: x.b, c: x.c)
        if !mir_v6_fact_candidate_present(item, read, items.slice(0, (items).len())) { try items.try_push(item) }
        cursor = step.cursor
        step = mir_v6_merge_next(cursor, function, source, read, items.slice(0, (items).len()))
    }
    return Ok(items)
}

fn mir_v6_fact_add(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, item: MirV6Fact) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
let bucket_count = (durable.fact_hash_head).len()
let existing_slot = mir_v6_fact_hash(item, bucket_count)
var existing = (durable.fact_hash_head)[existing_slot]
while existing != 0 { let prior = (durable.facts)[existing - 1]
    if prior.function == item.function && prior.value == item.value && prior.kind == item.kind && prior.a == item.a && prior.b == item.b && prior.c == item.c { return Ok(durable) }
    existing = (durable.fact_hash_next)[existing - 1]
}
let key = mir_v6_round_fact_key(index, item.function, item.value)
if key == 0 { return Ok(durable) }
let slot = mir_v6_fact_hash(item, (durable.fact_hash_head).len())
let old_hash = (durable.fact_hash_head)[slot]
let old_tail = (durable.fact_key_tail)[key]
try durable.facts.try_push(item)
try durable.fact_key_next.try_push(0)
try durable.fact_hash_next.try_push(old_hash)
let fact = (durable.facts).len()
var key_head = durable.fact_key_head
var key_tail = durable.fact_key_tail
var hash_head = durable.fact_hash_head
var key_next = durable.fact_key_next
if old_tail == 0 { key_head[key] = fact }
else { key_next[old_tail - 1] = fact }
key_tail[key] = fact
hash_head[slot] = fact
durable.fact_key_head = key_head
durable.fact_key_tail = key_tail
durable.fact_hash_head = hash_head
durable.fact_key_next = key_next
return Ok(durable) }
fn mir_v6_effect_add(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, parameter: U64, kind: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var existing = (durable.effect_head)[function]
while existing != 0 { let prior = (durable.effects)[existing - 1]
    if prior.parameter == parameter && prior.kind == kind { return Ok(durable) }
    existing = (durable.effect_next)[existing - 1]
}
let old_tail = (durable.effect_tail)[function]
try durable.effects.try_push(MirV6Effect(function: function, parameter: parameter, kind: kind))
try durable.effect_next.try_push(0)
let effect = (durable.effects).len()
var effect_head = durable.effect_head
var effect_tail = durable.effect_tail
var effect_next = durable.effect_next
if old_tail == 0 { effect_head[function] = effect }
else { effect_next[old_tail - 1] = effect }
effect_tail[function] = effect
durable.effect_head = effect_head
durable.effect_tail = effect_tail
durable.effect_next = effect_next
return Ok(durable) }
fn mir_v6_merge_value(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, target: U64, source: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var at = mir_v6_round_fact_start(index, function, source, durable.fact_key_head)
let key = mir_v6_round_fact_key(index, function, source)
if key == 0 { return Ok(durable) }
let stop = (durable.fact_key_tail)[key]
while at != 0 {
    let x = mir_v6_round_fact_at(at, durable.facts)
    let next = mir_v6_round_fact_next(at, durable.fact_key_next)
    durable = try mir_v6_fact_add(d, durable, index, MirV6Fact(function: function, value: target, kind: x.kind, a: x.a, b: x.b, c: x.c))
    if at == stop { return Ok(durable) }
    at = next
}
return Ok(durable) }

fn mir_v6_type_contains(d: Domain, store: MirStore, indexes: MirVIndexes, root: U64, wanted: U64) -> Result(Bool, __s0_Error) { var work = Vec.new(U64)
try work.try_push(root)
// O(1) visited probe; the linear seen scan was quadratic on the dense type
// graph and ran once per value/use in phases 6, 9, and 10.
let tcount = (store.types).len()
var seen = __s0_alloc(U64, d, tcount + 1)
var z: U64 = 0
while z <= tcount { seen[z] = 0
z = z + 1 }
var at: U64 = 0
while at < (work).len() { let id = work[at]
if id >= 1 && id <= tcount && seen[id] == 0 { if mir_vtype_kind(store, id) == wanted { return Ok(true) }
seen[id] = 1
work = try mir_vappend_type_children(d, store, indexes, work, id) }
at = at + 1 }
return Ok(false) }
fn mir_v6_type_reference(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_slice()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_vec()) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) }
fn mir_v6_type_local_store(d: Domain, store: MirStore, indexes: MirVIndexes, type_id: U64) -> Result(Bool, __s0_Error) { if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_ref()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_safe_mut()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_slice()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_table()) { return Ok(true) }
if try mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_handle()) { return Ok(true) }
return mir_v6_type_contains(d, store, indexes, type_id, mir_type_kind_domain_mark()) }

// A recursive copy_to_domain result has independent storage in the selected
// domain, so it may be inserted into ordinary aggregate/collection storage.
// Unmaterialized views and identity-bearing values retain the conservative
// dereference-store rejection.
fn mir_v6_materialized_store(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> Bool {
    let value_id = mir_vindex_value(indexes, function, value)
    if value_id == 0 { return false }
    let rec = (store.values)[value_id - 1]
    let instruction = mir_v6_instruction_for_value(store, indexes, rec)
    if instruction != 0 { return (store.instructions)[instruction - 1].op == mir_op_copy_to_domain() || (store.instructions)[instruction - 1].op == mir_op_copy_to_domain_try() }
    if rec.def_kind != mir_value_def_switch_case() { return false }
    let term_id = mir_vindex_term(indexes, function, rec.block)
    if term_id == 0 { return false }
    var at: U64 = 0
    var case_ordinal: U64 = 0
    while at < mir_vindex_op_term_count(indexes, term_id) {
        let operand_id = mir_vindex_op_term(indexes, term_id, at)
        let operand = (store.operands)[operand_id - 1]
        if operand.kind == mir_operand_switch_case() {
            if case_ordinal + 1 == rec.item {
                if !mir_vname_word(store, operand.name_start, operand.name_end, "ok") { return false }
                let result = (store.terminators)[term_id - 1].value
                let result_id = mir_vindex_value(indexes, function, result)
                if result_id == 0 { return false }
                let copied = mir_v6_instruction_for_value(store, indexes, (store.values)[result_id - 1])
                return copied != 0 && (store.instructions)[copied - 1].op == mir_op_copy_to_domain_try()
            }
            case_ordinal = case_ordinal + 1
        }
        at = at + 1
    }
    return false
}

fn mir_v6_instruction_for_value(store: MirStore, indexes: MirVIndexes, value: MirValueRec) -> U64 { if value.def_kind != mir_value_def_instruction() { return 0 }
return mir_vindex_instr(indexes, value.function, value.block, value.item - 1) }
fn mir_v6_function_param_ordinal(store: MirStore, indexes: MirVIndexes, function: U64, value: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let p = (store.params)[mir_vindex_param(indexes, function, at) - 1]
        if p.kind == mir_param_function() && p.value == value { return p.ordinal + 1 }
        at = at + 1
    }
    return 0
}
fn mir_v6_operand_value(store: MirStore, indexes: MirVIndexes, kind: U64, owner: U64, edge: U64, ordinal: U64) -> U64 { let oi = mir_v5_operand(store, indexes, kind, owner, edge, ordinal)
if oi == 0 { return 0 }
return (store.operands)[oi - 1].value }
fn mir_v6_place_deref(store: MirStore, place: U64) -> Bool { var p = place
while p != 0 { let x = (store.places)[p - 1]
if x.kind == mir_place_deref() { return true }
if x.kind != mir_place_field() { return false }
p = x.base }
return false }
fn mir_v6_places_alias(store: MirStore, indexes: MirVIndexes, a: U64, ad: Bool, ar: U64, an: U64, b: U64) -> Bool { let bd = mir_vindex_place_deref(indexes, b)
if ad || bd { return ad && bd }
if ar != (indexes.place_root)[b - 1] { return false }
let bn = mir_vindex_place_depth(indexes, b)
var n: U64 = 0
var limit = an
if bn < limit { limit = bn }
while n < limit { let ap = (store.places)[mir_vp4_place_component(store, a, n) - 1]
let bp = (store.places)[mir_vp4_place_component(store, b, n) - 1]
if !mir_vname_equal(store, ap.field_start, ap.field_end, bp.field_start, bp.field_end) { return false }
n = n + 1 }
return true }

fn mir_v6_block_param_record(store: MirStore, indexes: MirVIndexes, function: U64, block: U64, ordinal: U64) -> U64 {
    let count = mir_vindex_param_count(indexes, function)
    var at: U64 = 0
    while at < count {
        let id = mir_vindex_param(indexes, function, at)
        let parameter = (store.params)[id - 1]
        if parameter.kind == mir_param_block() && parameter.block == block && parameter.ordinal == ordinal { return id }
        at = at + 1
    }
    return 0
}

fn mir_v6_incoming_parameter(store: MirStore, indexes: MirVIndexes, operand: MirOperandRec) -> U64 {
    var function: U64 = 0
    if operand.kind == mir_operand_checked_edge_arg() && operand.owner >= 1 && operand.owner <= (store.instructions).len() {
        function = (store.instructions)[operand.owner - 1].function
    }
    if operand.kind == mir_operand_terminator_arg() && operand.owner >= 1 && operand.owner <= (store.terminators).len() {
        function = (store.terminators)[operand.owner - 1].function
    }
    if operand.kind == mir_operand_switch_case_arg() && operand.owner >= 1 && operand.owner <= (store.operands).len() {
        let case = (store.operands)[operand.owner - 1]
        if case.kind == mir_operand_switch_case() && case.owner >= 1 && case.owner <= (store.terminators).len() {
            function = (store.terminators)[case.owner - 1].function
        }
    }
    if function == 0 { return 0 }
    return mir_v6_block_param_record(store, indexes, function, operand.target, operand.ordinal)
}

fn mir_v6_transfer_index_build(d: Domain, store: MirStore, indexes: MirVIndexes) -> Result(MirV6TransferIndex, __s0_Error) {
    var store_start = Vec.new(U64)
    var store_count = Vec.new(U64)
    var store_ids = Vec.new(U64)
    var incoming_ids = Vec.new(U64)
    var function: U64 = 1
    while function <= (store.functions).len() {
        let first = (store_ids).len()
        try store_start.try_push(first)
        let bcount = mir_vindex_block_count(indexes, function)
        var block: U64 = 1
        while block <= bcount {
            let icount = mir_vindex_instr_count(indexes, function, block)
            var ordinal: U64 = 0
            while ordinal < icount {
                let iid = mir_vindex_instr(indexes, function, block, ordinal)
                if (store.instructions)[iid - 1].op == mir_op_store() { try store_ids.try_push(iid) }
                let total = mir_vindex_op_instr_count(indexes, iid)
                var oi: U64 = 0
                while oi < total {
                    let operand_id = mir_vindex_op_instr(indexes, iid, oi)
                    if (store.operands)[operand_id - 1].kind == mir_operand_checked_edge_arg() { try incoming_ids.try_push(operand_id) }
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
                    let operand = (store.operands)[operand_id - 1]
                    if operand.kind == mir_operand_terminator_arg() { try incoming_ids.try_push(operand_id) }
                    oi = oi + 1
                }
                var ci: U64 = 0
                while ci < total {
                    let case_id = mir_vindex_op_term(indexes, term_id, ci)
                    let case = (store.operands)[case_id - 1]
                    if case.kind == mir_operand_switch_case() {
                        let arg_total = mir_vindex_op_case_count(indexes, case_id)
                        var ai: U64 = 0
                        while ai < arg_total {
                            try incoming_ids.try_push(mir_vindex_op_case(indexes, case_id, ai))
                            ai = ai + 1
                        }
                    }
                    ci = ci + 1
                }
            }
            block = block + 1
        }
        try store_count.try_push((store_ids).len() - first)
        function = function + 1
    }
    let param_total = (store.params).len()
    var counts = __s0_alloc(U64, d, param_total + 1)
    var starts = __s0_alloc(U64, d, param_total + 1)
    var cursor = __s0_alloc(U64, d, param_total + 1)
    var p: U64 = 0
    while p <= param_total { counts[p] = 0
        starts[p] = 0
        cursor[p] = 0
        p = p + 1 }
    var at: U64 = 0
    while at < (incoming_ids).len() {
        let parameter = mir_v6_incoming_parameter(store, indexes, (store.operands)[incoming_ids[at] - 1])
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
    while at < (incoming_ids).len() {
        let operand = (store.operands)[incoming_ids[at] - 1]
        let parameter = mir_v6_incoming_parameter(store, indexes, operand)
        if parameter != 0 { sources[cursor[parameter]] = operand.value
            cursor[parameter] = cursor[parameter] + 1 }
        at = at + 1
    }
    var incoming_start = Vec.new(U64)
    var incoming_count = Vec.new(U64)
    var incoming_sources = Vec.new(U64)
    p = 1
    while p <= param_total {
        try incoming_start.try_push(starts[p])
        try incoming_count.try_push(counts[p])
        var source: U64 = 0
        while source < counts[p] {
            try incoming_sources.try_push(sources[starts[p] + source])
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
    let old_tail = (consumers.tail)[key]
    try consumers.target.try_push(target)
    try consumers.next.try_push(0)
    let edge = (consumers.target).len()
    var head = consumers.head
    var tail = consumers.tail
    var next = consumers.next
    if old_tail == 0 { head[key] = edge }
    else { next[old_tail - 1] = edge }
    tail[key] = edge
    consumers.head = head
    consumers.tail = tail
    consumers.next = next
    return Ok(consumers)
}

fn mir_v6_consumer_index_build(d: Domain, store: MirStore, indexes: MirVIndexes, transfer: MirV6TransferIndex, round: MirV6RoundIndex) -> Result(MirV6ConsumerIndex, __s0_Error) {
    var head = Vec.new(U64)
    var tail = Vec.new(U64)
    var key: U64 = 0
    while key < (round.fact_key_head).len() {
        try head.try_push(0)
        try tail.try_push(0)
        key = key + 1
    }
    var consumers = MirV6ConsumerIndex(head: head, tail: tail, target: Vec.new(U64), next: Vec.new(U64))
    var function: U64 = 1
    while function <= (store.functions).len() {
        var value_id: U64 = 1
        var vi = mir_vindex_value(indexes, function, value_id)
        while vi != 0 {
            let value = (store.values)[vi - 1]
            if value.def_kind == mir_value_def_block_param() {
                let parameter = mir_v6_block_param_record(store, indexes, function, value.block, value.item - 1)
                if parameter != 0 {
                    let start = (transfer.incoming_start)[parameter - 1]
                    let count = (transfer.incoming_count)[parameter - 1]
                    var incoming: U64 = 0
                    while incoming < count {
                        consumers = try mir_v6_consumer_add(d, round, consumers, function, (transfer.incoming_sources)[start + incoming], value_id)
                        incoming = incoming + 1
                    }
                }
            }
            if value.def_kind == mir_value_def_switch_case() {
                let term_id = mir_vindex_term(indexes, function, value.block)
                if term_id != 0 { consumers = try mir_v6_consumer_add(d, round, consumers, function, (store.terminators)[term_id - 1].value, value_id) }
            }
            let iid = mir_v6_instruction_for_value(store, indexes, value)
            if iid != 0 {
                let x = (store.instructions)[iid - 1]
                if x.op == mir_op_domain_create() || x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_copy_to_domain_try() || x.op == mir_op_bytes_try_from_vec() || x.op == mir_op_table_create() || x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_array_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() || (x.op >= mir_op_vec_construct_checked() && x.op <= mir_op_vec_as_mut_slice()) || x.op == mir_op_array_as_slice() || x.op == mir_op_vec_try_grow() || x.op == mir_op_bytes_as_slice() || x.op == mir_op_string_as_bytes() {
                    consumers = try mir_v6_consumer_add(d, round, consumers, function, x.a, value_id)
                }
                if x.op == mir_op_copy_to_domain() || x.op == mir_op_copy_to_domain_try() || x.op == mir_op_bytes_try_from_vec() { consumers = try mir_v6_consumer_add(d, round, consumers, function, x.b, value_id) }
                if x.op == mir_op_load() {
                    let place = (store.places)[x.place - 1]
                    if place.kind == mir_place_deref() { consumers = try mir_v6_consumer_add(d, round, consumers, function, place.deref_value, value_id) }
                    let first_store = (transfer.store_start)[function - 1]
                    let store_count = (transfer.store_count)[function - 1]
                    let load_deref = mir_vindex_place_deref(indexes, x.place)
                    let load_root = (indexes.place_root)[x.place - 1]
                    let load_depth = mir_vindex_place_depth(indexes, x.place)
                    var store_at: U64 = 0
                    while store_at < store_count {
                        let store_id = (transfer.stores)[first_store + store_at]
                        let placed = (store.instructions)[store_id - 1]
                        if mir_v6_places_alias(store, indexes, x.place, load_deref, load_root, load_depth, placed.place) { consumers = try mir_v6_consumer_add(d, round, consumers, function, placed.a, value_id) }
                        store_at = store_at + 1
                    }
                }
                if x.op == mir_op_aggregate_construct() {
                    let total = mir_vindex_op_instr_count(indexes, iid)
                    var operand_at: U64 = 0
                    while operand_at < total {
                        let operand = (store.operands)[mir_vindex_op_instr(indexes, iid, operand_at) - 1]
                        if operand.kind == mir_operand_aggregate_field() { consumers = try mir_v6_consumer_add(d, round, consumers, function, operand.value, value_id) }
                        operand_at = operand_at + 1
                    }
                }
                if x.op == mir_op_call() {
                    let total = mir_vindex_op_instr_count(indexes, iid)
                    var operand_at: U64 = 0
                    while operand_at < total {
                        let operand = (store.operands)[mir_vindex_op_instr(indexes, iid, operand_at) - 1]
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

fn mir_v6_transfer_value(d: Domain, function: U64, value_id: U64, read: MirV6FactRead, input: MirV6InputRead) -> Result(Vec(MirV6Fact), __s0_Error) { var proposed = Vec.new(MirV6Fact)
let vi = mir_v6_input_value(input, function, value_id)
let value = input.values[vi - 1]
if value.def_kind == mir_value_def_function_param() { let parameter = mir_v6_input_function_param(input, function, value_id)
let param_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_param(), a: parameter, b: 0, c: 0)
if !mir_v6_fact_candidate_present(param_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(param_fact) }
if try mir_v6_input_type_reference(d, input, value.value_type) { let pcount = mir_v6_input_param_count(input, function)
var pi: U64 = 0
while pi < pcount { let p = input.params[mir_v6_input_param(input, function, pi) - 1]
if p.kind == mir_param_function() && mir_v6_input_type_kind(input, p.param_type) == mir_type_kind_domain_handle() { let dep_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: p.ordinal + 1, c: 0)
if !mir_v6_fact_candidate_present(dep_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(dep_fact) } }
pi = pi + 1 }
let root_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: value_id, b: 0, c: parameter)
if !mir_v6_fact_candidate_present(root_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(root_fact) } }
if mir_v6_input_type_kind(input, value.value_type) == mir_type_kind_domain_handle() { let domain_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: 0, b: parameter, c: 0)
if !mir_v6_fact_candidate_present(domain_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(domain_fact) } }
return Ok(proposed) }
if value.def_kind == mir_value_def_block_param() {
    let parameter = mir_v6_input_block_param(input, function, value.block, value.item - 1)
    if parameter != 0 {
        let start = input.incoming_start[parameter - 1]
        let count = input.incoming_count[parameter - 1]
        var incoming: U64 = 0
        while incoming < count {
            proposed = try mir_v6_merge_propose(proposed, function, value_id, input.incoming_sources[start + incoming], read)
            incoming = incoming + 1
        }
    }
    return Ok(proposed)
}
if value.def_kind == mir_value_def_switch_case() { let term_id = mir_v6_input_term(input, function, value.block)
if term_id != 0 { let t = input.terminators[term_id - 1]
proposed = try mir_v6_merge_propose(proposed, function, value_id, t.value, read) }
return Ok(proposed) }
let iid = mir_v6_input_instruction_for_value(input, value)
if iid == 0 { return Ok(proposed) }
let x = input.instructions[iid - 1]
if x.op == mir_op_domain_create() { let create_key = mir_v6_read_fact_key(function, x.a, read)
var at: U64 = 0
if create_key != 0 { at = read.fact_key_head[create_key] }
while at != 0 { let f = mir_v6_round_fact_at(at, read.facts)
if f.kind == mir_v6_fact_dep() || f.kind == mir_v6_fact_parent() { let parent_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_parent(), a: f.a, b: f.b, c: f.c)
if !mir_v6_fact_candidate_present(parent_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(parent_fact) } }
at = mir_v6_round_fact_next(at, read.fact_key_next) }
let create_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_dep(), a: x.block, b: x.ordinal + 1, c: 0)
if !mir_v6_fact_candidate_present(create_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(create_fact) } }
// A cross-domain copy has independent value/storage provenance. The source is
// intentionally not merged: destroying its inner domain cannot invalidate the
// copy rooted in the destination domain.
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_copy_to_domain_try() || x.op == mir_op_bytes_try_from_vec() || x.op == mir_op_table_create() { proposed = try mir_v6_merge_propose(proposed, function, value_id, x.a, read)
let alloc_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: x.a, b: x.block, c: x.ordinal + 1)
if !mir_v6_fact_candidate_present(alloc_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(alloc_fact) } }
if x.op == mir_op_load() { let p = input.places[x.place - 1]
if p.kind == mir_place_deref() { proposed = try mir_v6_merge_propose(proposed, function, value_id, p.deref_value, read) }
// Stores retain their original block/ordinal order without materializing the
// potentially quadratic load-by-aliasing-store cross product.
let first_store = input.store_start[function - 1]
let store_count = input.store_count[function - 1]
let load_deref = input.place_deref[x.place - 1] != 0
let load_root = input.place_root[x.place - 1]
let load_depth = input.place_depth[x.place - 1]
var store_at: U64 = 0
while store_at < store_count { let store_id = input.stores[first_store + store_at]
let placed = input.instructions[store_id - 1]
if mir_v6_input_places_alias(input, x.place, load_deref, load_root, load_depth, placed.place) { proposed = try mir_v6_merge_propose(proposed, function, value_id, placed.a, read) }
store_at = store_at + 1 } }
if x.op == mir_op_aggregate_construct() { let total = input.op_instr_count[iid - 1]
var oi: U64 = 0
while oi < total { let o = input.operands[input.op_instr_ids[input.op_instr_start[iid - 1] + oi] - 1]
if o.kind == mir_operand_aggregate_field() { proposed = try mir_v6_merge_propose(proposed, function, value_id, o.value, read) }
oi = oi + 1 } }
if x.op == mir_op_enum_construct() || x.op == mir_op_enum_payload_checked() || x.op == mir_op_slice_index_checked() || x.op == mir_op_array_index_checked() || x.op == mir_op_slice_range_checked() || x.op == mir_op_table_lookup() || x.op == mir_op_table_lookup_mut() || (x.op >= mir_op_vec_construct_checked() && x.op <= mir_op_vec_as_mut_slice()) || x.op == mir_op_array_as_slice() || x.op == mir_op_bytes_as_slice() || x.op == mir_op_string_as_bytes() { proposed = try mir_v6_merge_propose(proposed, function, value_id, x.a, read) }
if x.op == mir_op_vec_grow_checked() || x.op == mir_op_vec_try_grow() { proposed = try mir_v6_merge_propose(proposed, function, value_id, x.b, read) }
if x.op == mir_op_call() { var e = mir_v6_round_effect_start(x.target, read.effect_head)
while e != 0 { let effect = mir_v6_round_effect_at(e, read.effects)
if effect.kind == mir_v6_effect_result_from() || effect.kind == mir_v6_effect_result_alloc() { let arg = mir_v6_input_operand_value(input, iid, effect.parameter - 1)
proposed = try mir_v6_merge_propose(proposed, function, value_id, arg, read)
if effect.kind == mir_v6_effect_result_alloc() { let call_fact = MirV6Fact(function: function, value: value_id, kind: mir_v6_fact_root(), a: arg, b: x.block, c: x.ordinal + 1)
if !mir_v6_fact_candidate_present(call_fact, read, proposed.slice(0, (proposed).len())) { try proposed.try_push(call_fact) } } }
e = mir_v6_round_effect_next(e, read.effect_next) } }
return Ok(proposed) }

fn mir_v6_add_param_effects(d: Domain, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, value: U64, kind: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var at = mir_v6_round_fact_start(index, function, value, durable.fact_key_head)
while at != 0 { let f = mir_v6_round_fact_at(at, durable.facts)
if f.kind == mir_v6_fact_param() { durable = try mir_v6_effect_add(d, durable, index, function, f.a, kind) }
at = mir_v6_round_fact_next(at, durable.fact_key_next) }
return Ok(durable) }
fn mir_v6_add_cleanup_effects(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis, durable0: MirV6Durable, index: MirV6RoundIndex, function: U64, active0: U64) -> Result(MirV6Durable, __s0_Error) { var durable = durable0
var active = active0
while active != 0 { let node = (cleanup.nodes)[active - 1]
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, (store.values)[vi - 1])
if push_id != 0 { let push = (store.instructions)[push_id - 1]
var e = mir_v6_round_effect_start(push.target, durable.effect_head)
while e != 0 { let effect = mir_v6_round_effect_at(e, durable.effects)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
durable = try mir_v6_add_param_effects(d, durable, index, function, arg, effect.kind) }
e = mir_v6_round_effect_next(e, durable.effect_next) } } }
active = node.parent }
return Ok(durable) }

fn mir_v6_compute_round(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis, transfer: MirV6TransferIndex, consumers: MirV6ConsumerIndex, index: MirV6RoundIndex, durable0: MirV6Durable) -> Result(MirV6RoundResult, __s0_Error) {
var durable = durable0
// The source place surface intentionally excludes indexed method receivers.
// Keep the four mutable fact indexes as the round owner's local values so
// each is copied once, rather than reconstructing the whole durable store for
// every append.
var facts = durable.facts
var effects = durable.effects
var fact_key_next = durable.fact_key_next
var fact_hash_next = durable.fact_hash_next
var effect_next = durable.effect_next
var fact_key_base = index.fact_key_base
var fact_key_head = durable.fact_key_head
var fact_key_tail = durable.fact_key_tail
var fact_hash_head = durable.fact_hash_head
var effect_head = durable.effect_head
var effect_tail = durable.effect_tail
var input_names = store.names
var input_types = store.types
var input_type_parts = store.type_parts
var input_functions = store.functions
var input_params = store.params
var input_values = store.values
var input_places = store.places
var input_instructions = store.instructions
var input_terminators = store.terminators
var input_operands = store.operands
var input_value_pos = indexes.value_pos
var input_value_span = indexes.value_span
var input_value_count = indexes.value_count
var input_param_span = indexes.param_span
var input_param_ids = indexes.param_ids
var input_term_pos = indexes.term_pos
var input_term_span = indexes.term_span
var input_block_count = indexes.block_count
var input_block_span = indexes.block_span
var input_instr_span = indexes.instr_span
var input_instr_count = indexes.instr_count
var input_instr_off = indexes.instr_off
var input_instr_ids = indexes.instr_ids
var input_op_instr_start = indexes.op_instr_start
var input_op_instr_count = indexes.op_instr_count
var input_op_instr_ids = indexes.op_instr_ids
var input_tp_start = indexes.tp_start
var input_tp_count = indexes.tp_count
var input_tp_ids = indexes.tp_ids
var input_place_root = indexes.place_root
var input_place_depth = indexes.place_depth
var input_place_deref = indexes.place_deref
var input_incoming_start = transfer.incoming_start
var input_incoming_count = transfer.incoming_count
var input_incoming_sources = transfer.incoming_sources
var input_store_start = transfer.store_start
var input_store_count = transfer.store_count
var input_stores = transfer.stores
let before_facts = (facts).len()
let before_effects = (effects).len()
let function_count = (store.functions).len()
var queue = Vec.new(U64)
var queued = Vec.new(U64)
var initial: U64 = 0
while initial <= function_count {
    var mark: U64 = 1
    if initial == 0 { mark = 0 } else { try queue.try_push(function_count - initial + 1) }
    try queued.try_push(mark)
    initial = initial + 1
}
var queue_at: U64 = 0
while queue_at < (queue).len() {
let function = queue[queue_at]
queued[function] = 0
let initial_function_effects = (effects).len()
var processed = Vec.new(U64)
try processed.try_push(0)
var value: U64 = 1
while mir_vindex_value(indexes, function, value) != 0 {
    try processed.try_push(0)
    value = value + 1
}
var needs_pass = true
var generation: U64 = 0
while needs_pass {
    needs_pass = false
    generation = generation + 1
    value = 1
    while mir_vindex_value(indexes, function, value) != 0 {
    processed[value] = generation
    let function_facts = (facts).len()
    let proposed = try mir_v6_transfer_value(d, function, value, MirV6FactRead(facts: facts.slice(0, (facts).len()), effects: effects.slice(0, (effects).len()), fact_key_next: fact_key_next.slice(0, (fact_key_next).len()), fact_hash_next: fact_hash_next.slice(0, (fact_hash_next).len()), effect_next: effect_next.slice(0, (effect_next).len()), fact_key_base: fact_key_base.slice(0, (fact_key_base).len()), fact_key_head: fact_key_head.slice(0, (fact_key_head).len()), fact_key_tail: fact_key_tail.slice(0, (fact_key_tail).len()), fact_hash_head: fact_hash_head.slice(0, (fact_hash_head).len()), effect_head: effect_head.slice(0, (effect_head).len())), MirV6InputRead(names: input_names.slice(0, (input_names).len()), types: input_types.slice(0, (input_types).len()), type_parts: input_type_parts.slice(0, (input_type_parts).len()), functions: input_functions.slice(0, (input_functions).len()), params: input_params.slice(0, (input_params).len()), values: input_values.slice(0, (input_values).len()), places: input_places.slice(0, (input_places).len()), instructions: input_instructions.slice(0, (input_instructions).len()), terminators: input_terminators.slice(0, (input_terminators).len()), operands: input_operands.slice(0, (input_operands).len()), value_pos: input_value_pos.slice(0, (input_value_pos).len()), value_span: input_value_span.slice(0, (input_value_span).len()), value_count: input_value_count.slice(0, (input_value_count).len()), param_span: input_param_span.slice(0, (input_param_span).len()), param_ids: input_param_ids.slice(0, (input_param_ids).len()), term_pos: input_term_pos.slice(0, (input_term_pos).len()), term_span: input_term_span.slice(0, (input_term_span).len()), block_count: input_block_count.slice(0, (input_block_count).len()), block_span: input_block_span.slice(0, (input_block_span).len()), instr_span: input_instr_span.slice(0, (input_instr_span).len()), instr_count: input_instr_count.slice(0, (input_instr_count).len()), instr_off: input_instr_off.slice(0, (input_instr_off).len()), instr_ids: input_instr_ids.slice(0, (input_instr_ids).len()), op_instr_start: input_op_instr_start.slice(0, (input_op_instr_start).len()), op_instr_count: input_op_instr_count.slice(0, (input_op_instr_count).len()), op_instr_ids: input_op_instr_ids.slice(0, (input_op_instr_ids).len()), tp_start: input_tp_start.slice(0, (input_tp_start).len()), tp_count: input_tp_count.slice(0, (input_tp_count).len()), tp_ids: input_tp_ids.slice(0, (input_tp_ids).len()), place_root: input_place_root.slice(0, (input_place_root).len()), place_depth: input_place_depth.slice(0, (input_place_depth).len()), place_deref: input_place_deref.slice(0, (input_place_deref).len()), incoming_start: input_incoming_start.slice(0, (input_incoming_start).len()), incoming_count: input_incoming_count.slice(0, (input_incoming_count).len()), incoming_sources: input_incoming_sources.slice(0, (input_incoming_sources).len()), store_start: input_store_start.slice(0, (input_store_start).len()), store_count: input_store_count.slice(0, (input_store_count).len()), stores: input_stores.slice(0, (input_stores).len())))
    let append_count = (proposed).len()
    try facts.try_reserve(append_count)
    try fact_key_next.try_reserve(append_count)
    try fact_hash_next.try_reserve(append_count)
    var append_at: U64 = 0
    while append_at < append_count {
        let item = proposed[append_at]
        let key = fact_key_base[item.function - 1] + item.value
        if key != 0 {
            let slot = mir_v6_fact_hash(item, (fact_hash_head).len())
            let old_hash = fact_hash_head[slot]
            let old_tail = fact_key_tail[key]
            try facts.try_push(item)
            try fact_key_next.try_push(0)
            try fact_hash_next.try_push(old_hash)
            let fact = (facts).len()
            if old_tail == 0 { fact_key_head[key] = fact }
            else { fact_key_next[old_tail - 1] = fact }
            fact_key_tail[key] = fact
            fact_hash_head[slot] = fact
        }
        append_at = append_at + 1
    }
    if function_facts != (facts).len() {
        let key = mir_v6_round_fact_key(index, function, value)
        var edge = (consumers.head)[key]
        while edge != 0 {
            let target = (consumers.target)[edge - 1]
            if processed[target] == generation { needs_pass = true }
            edge = (consumers.next)[edge - 1]
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
        let x = (store.instructions)[iid - 1]
        if x.op == mir_op_domain_destroy() { durable = try mir_v6_add_param_effects(d, durable, index, function, x.a, mir_v6_effect_destroy()) }
        if x.op == mir_op_domain_reset() { durable = try mir_v6_add_param_effects(d, durable, index, function, x.a, mir_v6_effect_reset()) }
        if x.op == mir_op_call() { var e = mir_v6_round_effect_start(x.target, durable.effect_head)
while e != 0 { let effect = mir_v6_round_effect_at(e, durable.effects)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), iid, 0, effect.parameter - 1)
durable = try mir_v6_add_param_effects(d, durable, index, function, arg, effect.kind) }
e = mir_v6_round_effect_next(e, durable.effect_next) } }
        if x.op == mir_op_cleanup_scope_run() { var si: U64 = 0
while si < (cleanup.run_sets).len() { let set = (cleanup.run_sets)[si]
if set.function == function && set.instruction == iid { durable = try mir_v6_add_cleanup_effects(d, store, indexes, cleanup, durable, index, function, set.active) }
si = si + 1 } }
        ii = ii + 1
    }
    let term_id = mir_vindex_term(indexes, function, block)
    if term_id != 0 {
        let t = (store.terminators)[term_id - 1]
        if (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { var f = mir_v6_round_fact_start(index, function, t.value, durable.fact_key_head)
while f != 0 { let fact = mir_v6_round_fact_at(f, durable.facts)
if fact.kind == mir_v6_fact_param() { durable = try mir_v6_effect_add(d, durable, index, function, fact.a, mir_v6_effect_result_from()) }
if fact.kind == mir_v6_fact_root() && fact.b != 0 { var h = mir_v6_round_fact_start(index, function, fact.a, durable.fact_key_head)
while h != 0 { let owner = mir_v6_round_fact_at(h, durable.facts)
if owner.kind == mir_v6_fact_param() { durable = try mir_v6_effect_add(d, durable, index, function, owner.a, mir_v6_effect_result_alloc()) }
h = mir_v6_round_fact_next(h, durable.fact_key_next) } }
f = mir_v6_round_fact_next(f, durable.fact_key_next) } }
    }
    block = block + 1
}
if initial_function_effects != (durable.effects).len() {
    var instruction: U64 = 0
    while instruction < (store.instructions).len() {
        let caller = (store.instructions)[instruction]
        if (caller.op == mir_op_call() || caller.op == mir_op_cleanup_push()) && caller.target == function && queued[caller.function] == 0 {
            try queue.try_push(caller.function)
            queued[caller.function] = 1
        }
        instruction = instruction + 1
    }
}
queue_at = queue_at + 1 }
let changed = before_facts != (facts).len() || before_effects != (effects).len()
durable.facts = facts
durable.effects = effects
durable.fact_key_next = fact_key_next
durable.fact_hash_next = fact_hash_next
durable.effect_next = effect_next
durable.fact_key_head = fact_key_head
durable.fact_key_tail = fact_key_tail
durable.fact_hash_head = fact_hash_head
durable.effect_head = effect_head
durable.effect_tail = effect_tail
return Ok(MirV6RoundResult(durable: durable, changed: changed)) }

fn mir_v6_compute(d: Domain, store: MirStore, indexes: MirVIndexes, cleanup: MirV7Analysis) -> Result(MirV6Analysis, __s0_Error) {
var durable = MirV6Durable(facts: Vec.new(MirV6Fact), effects: Vec.new(MirV6Effect), fact_key_next: Vec.new(U64), fact_hash_next: Vec.new(U64), effect_next: Vec.new(U64), fact_key_head: Vec.new(U64), fact_key_tail: Vec.new(U64), fact_hash_head: Vec.new(U64), effect_head: Vec.new(U64), effect_tail: Vec.new(U64))
let index = try mir_v6_live_index_build(d, store, indexes)
durable.fact_key_head = index.fact_key_head
durable.fact_key_tail = index.fact_key_tail
durable.fact_hash_head = index.fact_hash_head
durable.effect_head = index.effect_head
durable.effect_tail = index.effect_tail
let transfer = try mir_v6_transfer_index_build(d, store, indexes)
let consumers = try mir_v6_consumer_index_build(d, store, indexes, transfer, index)
let step = try mir_v6_compute_round(d, store, indexes, cleanup, transfer, consumers, index, durable)
durable = step.durable
return mir_v6_finalize(d, store, index, durable) }

fn mir_v6_dep_alias(a: MirV6Fact, b: MirV6StateFact) -> Bool { return a.a == b.a && a.b == b.b || a.a == 0 && b.a == 0 }
fn mir_v6_state_has(state: Vec(MirV6StateFact), item: MirV6StateFact) -> Bool { var at: U64 = 0
while at < (state).len() { let x = state[at]
if x.kind == item.kind && x.a == item.a && x.b == item.b && x.c == item.c { return true }
at = at + 1 }
return false }
fn mir_v6_state_add(d: Domain, state: Vec(MirV6StateFact), item: MirV6StateFact) -> Result(Vec(MirV6StateFact), __s0_Error) { if mir_v6_state_has(state, item) { return Ok(state) }
return Ok(try vec_appended(MirV6StateFact, state, item)) }
fn mir_v6_value_invalid(analysis: MirV6Analysis, state: Vec(MirV6StateFact), function: U64, value: U64) -> Bool { var s: U64 = 0
while s < (state).len() { let dead = state[s]
if dead.kind == mir_v6_state_mark() && dead.a == value { return true }
var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if (fact.kind == mir_v6_fact_dep() || fact.kind == mir_v6_fact_parent()) && dead.kind == mir_v6_state_dead() && mir_v6_dep_alias(fact, dead) { return true }
if fact.kind == mir_v6_fact_root() && dead.kind == mir_v6_state_root() && fact.a == dead.a && fact.b == dead.b && fact.c == dead.c { return true }
f = f + 1 }
s = s + 1 }
return false }
fn mir_v6_domain_dead(analysis: MirV6Analysis, state: Vec(MirV6StateFact), function: U64, value: U64) -> Bool { var f = mir_v6_fact_start(analysis, function, value)
let fend = mir_v6_fact_end(analysis, function, value)
while f < fend { let fact = mir_v6_fact_at(analysis, f)
if fact.kind == mir_v6_fact_dep() { var s: U64 = 0
while s < (state).len() { let dead = state[s]
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
let iid = mir_v6_instruction_for_value(store, indexes, (store.values)[vi - 1])
if iid == 0 { return 0 }
let x = (store.instructions)[iid - 1]
if x.op != mir_op_domain_mark() { return 0 }
return x.a }
fn mir_v6_clear_produced(d: Domain, state: Vec(MirV6StateFact), block: U64, ordinal: U64) -> Result(Vec(MirV6StateFact), __s0_Error) { var out = Vec.new(MirV6StateFact)
var at: U64 = 0
while at < (state).len() { let x = state[at]
if !(x.kind == mir_v6_state_root() && x.b == block && x.c == ordinal + 1) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_clear_dead(d: Domain, state: Vec(MirV6StateFact), block: U64, ordinal: U64) -> Result(Vec(MirV6StateFact), __s0_Error) { var out = Vec.new(MirV6StateFact)
var at: U64 = 0
while at < (state).len() { let x = state[at]
if !(x.kind == mir_v6_state_dead() && x.a == block && x.b == ordinal + 1) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_clear_mark(d: Domain, state: Vec(MirV6StateFact), mark: U64) -> Result(Vec(MirV6StateFact), __s0_Error) { var out = Vec.new(MirV6StateFact)
var at: U64 = 0
while at < (state).len() { let x = state[at]
if !(x.kind == mir_v6_state_mark() && x.a == mark) { out = try mir_v6_state_add(d, out, x) }
at = at + 1 }
return Ok(out) }
fn mir_v6_root_after_mark(store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64, root: MirV6Fact, mark: U64) -> Bool {
    if root.b == 0 { return true }
    let mi = mir_vindex_value(indexes, function, mark)
    if mi == 0 { return true }
    let mv = (store.values)[mi - 1]
    // Availability dominance over the prebuilt point CFG replaces the old
    // per-call entry BFS.  A switch-case-defined mark is dominated at its own
    // case binding (phase 4's use-loop shortcut), matching the legacy point
    // walk that suppressed exactly that case edge.
    if mv.def_kind == mir_value_def_switch_case() && mv.block == root.b && mv.item == root.c { return true }
    return mir_vp4_avail_dominates(cfg, dom, mv.def_kind, mv.block, mv.item, root.b, root.c - 1)
}
fn mir_v6_invalidate(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, state0: Vec(MirV6StateFact), function: U64, domain: U64, reset: Bool, mark: U64) -> Result(Vec(MirV6StateFact), __s0_Error) {
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
fn mir_v6_apply_cleanup_entry(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, state0: Vec(MirV6StateFact), function: U64, entry: U64) -> Result(Vec(MirV6StateFact), __s0_Error) { var state = state0
let vi = mir_vindex_value(indexes, function, entry)
if vi == 0 { return Ok(state) }
let push_id = mir_v6_instruction_for_value(store, indexes, (store.values)[vi - 1])
if push_id == 0 { return Ok(state) }
let push = (store.instructions)[push_id - 1]
var e = mir_v6_effect_start(analysis, push.target)
let eend = mir_v6_effect_end(analysis, push.target)
while e < eend { let effect = mir_v6_effect_at(analysis, e)
if effect.kind == mir_v6_effect_destroy() || effect.kind == mir_v6_effect_reset() { let arg = mir_v6_operand_value(store, indexes, mir_operand_instruction(), push_id, 0, effect.parameter - 1)
state = try mir_v6_invalidate(d, store, indexes, cfg, dom, analysis, state, function, arg, effect.kind == mir_v6_effect_reset(), 0) }
e = e + 1 }
return Ok(state) }
fn mir_v6_apply_cleanup(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: Vec(MirV6StateFact), iid: U64, function: U64) -> Result(Vec(MirV6StateFact), __s0_Error) { var merged = Vec.new(MirV6StateFact)
var found = false
var si: U64 = 0
while si < (cleanup.run_sets).len() { let set = (cleanup.run_sets)[si]
if set.function == function && set.instruction == iid { found = true
var branch = state0
var active = set.active
while active != 0 { let node = (cleanup.nodes)[active - 1]
branch = try mir_v6_apply_cleanup_entry(d, store, indexes, cfg, dom, analysis, branch, function, node.entry)
active = node.parent }
var bi: U64 = 0
while bi < (branch).len() { merged = try mir_v6_state_add(d, merged, branch[bi])
bi = bi + 1 } }
si = si + 1 }
if found { return Ok(merged) }
return Ok(state0) }
fn mir_v6_apply(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: Vec(MirV6StateFact), iid: U64, x: MirInstrRec) -> Result(Vec(MirV6StateFact), __s0_Error) { var state = state0
if x.op == mir_op_domain_create() { state = try mir_v6_clear_dead(d, state, x.block, x.ordinal) }
if x.op == mir_op_domain_mark() { state = try mir_v6_clear_mark(d, state, x.result) }
if x.op == mir_op_alloc() || x.op == mir_op_alloc_checked() || x.op == mir_op_copy_to_domain() || x.op == mir_op_copy_to_domain_try() || x.op == mir_op_bytes_try_from_vec() || x.op == mir_op_table_create() || x.op == mir_op_call() || x.op == mir_op_vec_grow_checked() || x.op == mir_op_vec_try_grow() { state = try mir_v6_clear_produced(d, state, x.block, x.ordinal) }
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
    var head = Vec.new(U64)
    var tail = Vec.new(U64)
    var block: U64 = 0
    while block <= blocks {
        try head.try_push(0)
        try tail.try_push(0)
        block = block + 1
    }
    return Ok(MirV6Entries(items: Vec.new(MirV6EntryFact), next: Vec.new(U64), head: head, tail: tail))
}
fn mir_v6_entry_has(entries: MirV6Entries, block: U64, state: MirV6StateFact) -> Bool {
    if block == 0 || block >= (entries.head).len() { return false }
    var at = (entries.head)[block]
    while at != 0 {
        let x = (entries.items)[at - 1].state
        if x.kind == state.kind && x.a == state.a && x.b == state.b && x.c == state.c { return true }
        at = (entries.next)[at - 1]
    }
    return false
}
fn mir_v6_entry_merge(d: Domain, entries0: MirV6Entries, block: U64, state: Vec(MirV6StateFact)) -> Result(MirV6EntryMerge, __s0_Error) {
    var entries = entries0
    var changed = false
    if block == 0 || block >= (entries.head).len() { return Ok(MirV6EntryMerge(entries: entries, changed: changed)) }
    var at: U64 = 0
    while at < (state).len() {
        let x = state[at]
        if !mir_v6_entry_has(entries, block, x) {
            let old_tail = (entries.tail)[block]
            try entries.items.try_push(MirV6EntryFact(block: block, state: x))
            try entries.next.try_push(0)
            let entry = (entries.items).len()
            var head = entries.head
            var tail = entries.tail
            var next = entries.next
            if old_tail == 0 { head[block] = entry }
            else { next[old_tail - 1] = entry }
            tail[block] = entry
            entries.head = head
            entries.tail = tail
            entries.next = next
            changed = true
        }
        at = at + 1
    }
    return Ok(MirV6EntryMerge(entries: entries, changed: changed))
}
fn mir_v6_entry_state(d: Domain, entries: MirV6Entries, block: U64) -> Result(Vec(MirV6StateFact), __s0_Error) {
    var state = Vec.new(MirV6StateFact)
    if block == 0 || block >= (entries.head).len() { return Ok(state) }
    var at = (entries.head)[block]
    while at != 0 {
        try state.try_push((entries.items)[at - 1].state)
        at = (entries.next)[at - 1]
    }
    return Ok(state)
}
fn mir_v6_successors(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, block: U64, out0: Vec(U64)) -> Result(Vec(U64), __s0_Error) { var out = out0
let icount = mir_vindex_instr_count(indexes, function, block)
var ii: U64 = 0
while ii < icount {
    let iid = mir_vindex_instr(indexes, function, block, ii)
    let x = (store.instructions)[iid - 1]
    if mir_vop_checked(x.op) { try out.try_push(x.target) }
    ii = ii + 1
}
let term_id = mir_vindex_term(indexes, function, block)
if term_id != 0 {
    let t = (store.terminators)[term_id - 1]
    if t.kind == mir_term_jump() { try out.try_push(t.target) }
    if t.kind == mir_term_branch() { try out.try_push(t.then_block)
try out.try_push(t.else_block) }
    if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
var oi: U64 = 0
while oi < total { let c = (store.operands)[mir_vindex_op_term(indexes, term_id, oi) - 1]
if c.kind == mir_operand_switch_case() { try out.try_push(c.target) }
oi = oi + 1 } }
}
return Ok(out) }
fn mir_v6_solve_states(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, cleanup: MirV7Analysis, cfg: MirVP4PointCfg, dom: MirVP4Dom, function: U64) -> Result(MirV6Entries, __s0_Error) {
let reachable = try mir_vreachable(d, store, indexes, function)
let bcount = mir_vindex_block_count(indexes, function)
var entries = try mir_v6_entries_new(d, bcount)
var queue = Vec.new(U64)
var queued = Vec.new(U64)
try queued.try_push(0)
var block: U64 = 1
while block <= bcount {
    var mark: U64 = 0
    if mir_vseen_block(reachable, block) {
        try queue.try_push(block)
        mark = 1
    }
    try queued.try_push(mark)
    block = block + 1
}
var queue_at: U64 = 0
while queue_at < (queue).len() {
block = queue[queue_at]
queued[block] = 0
var state = try mir_v6_entry_state(d, entries, block)
let icount = mir_vindex_instr_count(indexes, function, block)
var ordinal: U64 = 0
while ordinal < icount {
    let iid = mir_vindex_instr(indexes, function, block, ordinal)
    let x = (store.instructions)[iid - 1]
    if mir_vop_checked(x.op) { let merged = try mir_v6_entry_merge(d, entries, x.target, state)
        entries = merged.entries
        if merged.changed && queued[x.target] == 0 { try queue.try_push(x.target)
            queued[x.target] = 1 }
    }
    state = try mir_v6_apply(d, store, indexes, cfg, dom, analysis, cleanup, state, iid, x)
    ordinal = ordinal + 1
}
let successors = try mir_v6_successors(d, store, indexes, function, block, Vec.new(U64))
var si: U64 = 0
while si < (successors).len() { let target = successors[si]
// Checked successors already received the pre-instruction state above.
var checked = false
var xi: U64 = 0
while xi < icount {
    let q = (store.instructions)[mir_vindex_instr(indexes, function, block, xi) - 1]
    if mir_vop_checked(q.op) && q.target == target { checked = true }
    xi = xi + 1
}
if !checked { let merged = try mir_v6_entry_merge(d, entries, target, state)
    entries = merged.entries
    if merged.changed && queued[target] == 0 { try queue.try_push(target)
        queued[target] = 1 }
}
si = si + 1 }
queue_at = queue_at + 1
}
return Ok(entries) }

fn mir_v6_reach_has(reach: MirV6Reachability, from: U64, to: U64) -> Bool {
    if from == 0 || from >= (reach.span).len() { return false }
    var at = (reach.span)[from - 1]
    let end = (reach.span)[from]
    while at < end {
        if (reach.facts)[at].to == to { return true }
        at = at + 1
    }
    return false
}
fn mir_v6_reachability(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64) -> Result(MirV6Reachability, __s0_Error) {
    var reach = Vec.new(MirV6ReachFact)
    var span = Vec.new(U64)
    let bcount = mir_vindex_block_count(indexes, function)
    var seen = Vec.new(U64)
    var block: U64 = 0
    while block <= bcount {
        try seen.try_push(0)
        block = block + 1
    }
    var from: U64 = 1
    while from <= bcount {
        try span.try_push((reach).len())
        var queue = try mir_v6_successors(d, store, indexes, function, from, Vec.new(U64))
        var q: U64 = 0
        while q < (queue).len() {
            let to = queue[q]
            if to >= 1 && to <= bcount && seen[to] != from {
                seen[to] = from
                try reach.try_push(MirV6ReachFact(from: from, to: to))
                queue = try mir_v6_successors(d, store, indexes, function, to, queue)
            }
            q = q + 1
        }
        from = from + 1
    }
    try span.try_push((reach).len())
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
if vi != 0 && mir_vtype_kind(store, (store.values)[vi - 1].value_type) == mir_type_kind_domain_handle() { parameter_domain = true } }
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
fn mir_v6_bad(d: Domain, out: Vec(MirVerifyDiagRec), kind: U64, function: U64, block: U64, instruction: U64, terminator: U64, operand: U64, reference: U64) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var type_id: U64 = 0
return mir_vadd(d, out, mir_vdiag(mir_verify_phase_domains(), kind, function, block, instruction, terminator, operand, type_id, 0, 0, 0, reference)) }
fn mir_v6_bad_has(out: Vec(MirVerifyDiagRec), kind: U64, function: U64, instruction: U64, reference: U64) -> Bool { var at: U64 = 0
while at < (out).len() { let x = out[at]
if x.phase == mir_verify_phase_domains() && x.kind == kind && x.function == function && x.instruction == instruction && x.reference == reference { return true }
at = at + 1 }
return false }
fn mir_v6_check_cleanup(d: Domain, store: MirStore, indexes: MirVIndexes, cfg: MirVP4PointCfg, dom: MirVP4Dom, analysis: MirV6Analysis, cleanup: MirV7Analysis, state0: Vec(MirV6StateFact), function: U64, block: U64, iid: U64, out0: Vec(MirVerifyDiagRec)) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var out = out0
var si: U64 = 0
while si < (cleanup.run_sets).len() { let set = (cleanup.run_sets)[si]
if set.function == function && set.instruction == iid { var branch = state0
var active = set.active
while active != 0 { let node = (cleanup.nodes)[active - 1]
let vi = mir_vindex_value(indexes, function, node.entry)
if vi != 0 { let push_id = mir_v6_instruction_for_value(store, indexes, (store.values)[vi - 1])
if push_id != 0 { let push = (store.instructions)[push_id - 1]
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
fn mir_v6_check_loops(d: Domain, store: MirStore, indexes: MirVIndexes, analysis: MirV6Analysis, function: U64, out0: Vec(MirVerifyDiagRec)) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var out = out0
let reach = try mir_v6_reachability(d, store, indexes, function)
let pcount = mir_vindex_param_count(indexes, function)
var pi: U64 = 0
while pi < pcount {
    let pid = mir_vindex_param(indexes, function, pi)
    let p = (store.params)[pid - 1]
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
                    let o = (store.operands)[oid - 1]
                    if o.kind == mir_operand_checked_edge_arg() && o.target == p.block && o.ordinal == p.ordinal { let source = (store.instructions)[iid - 1].block
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
                    let o = (store.operands)[oid - 1]
                    if o.kind == mir_operand_terminator_arg() && o.target == p.block && o.ordinal == p.ordinal { let source = (store.terminators)[term_id - 1].block
if mir_v6_reach_has(reach, p.block, source) && mir_v6_local_provenance(analysis, function, o.value) { out = try mir_v6_bad(d, out, mir_vdiag_loop_block_resource(), function, p.block, 0, 0, oid, p.value) } }
                    oi = oi + 1
                }
                var ci: U64 = 0
                while ci < total {
                    let cid = mir_vindex_op_term(indexes, term_id, ci)
                    let c = (store.operands)[cid - 1]
                    if c.kind == mir_operand_switch_case() {
                        let atotal = mir_vindex_op_case_count(indexes, cid)
                        var ai: U64 = 0
                        while ai < atotal {
                            let aid = mir_vindex_op_case(indexes, cid, ai)
                            let a = (store.operands)[aid - 1]
                            if a.target == p.block && a.ordinal == p.ordinal { let source = (store.terminators)[(store.operands)[cid - 1].owner - 1].block
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
        let x = (store.instructions)[iid - 1]
        if x.op == mir_op_store() && mir_v6_reach_has(reach, x.block, x.block) && mir_v6_local_provenance(analysis, function, x.a) && !mir_v6_stable_loop_store(store, indexes, analysis, function, x.a, x.place) { out = try mir_v6_bad(d, out, mir_vdiag_loop_store_resource(), function, x.block, iid, 0, x.place, x.a) }
        ii = ii + 1
    }
    b2 = b2 + 1
}
return Ok(out) }
fn mir_vphase6_with(d: Domain, store: MirStore, indexes: MirVIndexes, inventory: MirVP4UseInventory, initial: Vec(MirVerifyDiagRec), cleanup: MirV7Analysis, analysis: MirV6Analysis) -> Result(Vec(MirVerifyDiagRec), __s0_Error) { var out = initial
var function: U64 = 1
while function <= (store.functions).len() { out = try mir_v6_check_loops(d, store, indexes, analysis, function, out)
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
    let x = (store.instructions)[iid - 1]
    if x.op == mir_op_store() && mir_v6_place_deref(store, x.place) { let value_type = mir_v5_value_type(store, indexes, function, x.a)
if (try mir_v6_type_local_store(d, store, indexes, value_type)) && !mir_v6_materialized_store(store, indexes, function, x.a) { out = try mir_v6_bad(d, out, mir_vdiag_lifetime_deref_store(), function, block, iid, 0, x.place, x.a) } }
    if x.op == mir_op_cleanup_scope_run() { out = try mir_v6_check_cleanup(d, store, indexes, cfg, dom, analysis, cleanup, state, function, block, iid, out) }
    var invalid = false
    let use_start = (inventory.instruction_start)[iid - 1]
    let use_count = (inventory.instruction_count)[iid - 1]
    var ui: U64 = 0
    while ui < use_count { let use = (inventory.uses)[use_start + ui]
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
    let t = (store.terminators)[term_id - 1]
    if (t.kind == mir_term_return() || t.kind == mir_term_fail()) && t.value != 0 { if mir_v6_value_invalid(analysis, state, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_invalid_resource_exit(), function, block, 0, term_id, 0, t.value) }
if mir_v6_escapes_local(analysis, function, t.value) { out = try mir_v6_bad(d, out, mir_vdiag_local_domain_escape(), function, block, 0, term_id, 0, t.value) } }
} }
block = block + 1 }
function = function + 1 }
return Ok(out) }
fn mir_vphase6(d: Domain, store: MirStore, indexes: MirVIndexes, initial: Vec(MirVerifyDiagRec)) -> Result(Vec(MirVerifyDiagRec), __s0_Error) {
let cleanup = try mir_v7_analyze(d, store, indexes, Vec.new(MirVerifyDiagRec))
let analysis = try mir_v6_compute(d, store, indexes, cleanup)
let inventory = try mir_vp4_use_inventory_build(d, store, indexes)
return mir_vphase6_with(d, store, indexes, inventory, initial, cleanup, analysis) }
