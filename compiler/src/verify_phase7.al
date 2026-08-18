// Phase 7 tracks each cleanup scope independently.  A configuration is a
// status plus a canonical persistent stack node; nodes preserve registration
// identity and runtime push order without maps or recursive traversal.
// Each function's nodes and run sets occupy a contiguous suffix of their
// global append-only buffers (mir_v7_analyze processes functions in order and
// only appends records for the current function), so interner and run-set
// lookups scan just the current function's range instead of every function.
fn mir_v7_absent() -> U64 { return 0 }
fn mir_v7_open() -> U64 { return 1 }
fn mir_v7_running() -> U64 { return 2 }
fn mir_v7_ended() -> U64 { return 3 }

type MirV7Node {
    function: U64
    parent: U64
    entry: U64
}
type MirV7RunSet {
    function: U64
    instruction: U64
    active: U64
}
type MirV7Analysis {
    nodes: __s0_Buffer(MirV7Node)
    run_sets: __s0_Buffer(MirV7RunSet)
    diagnostics: __s0_Buffer(MirVerifyDiagRec)
}
type MirV7Config {
    block: U64
    status: U64
    active: U64
}
type MirV7Bad {
    block: U64
    instruction: U64
}
type MirV7Exit {
    block: U64
    terminator: U64
}

fn mir_v7_config_has(xs: __s0_Buffer(MirV7Config), x: MirV7Config) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV7Config, xs) { let y = __s0_buffer_get(MirV7Config, xs, at)
if y.block == x.block && y.status == x.status && y.active == x.active { return true }
at = at + 1 }
return false }
fn mir_v7_bad_has(xs: __s0_Buffer(MirV7Bad), block: U64, instruction: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV7Bad, xs) { let x = __s0_buffer_get(MirV7Bad, xs, at)
if x.block == block && x.instruction == instruction { return true }
at = at + 1 }
return false }
fn mir_v7_exit_has(xs: __s0_Buffer(MirV7Exit), block: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirV7Exit, xs) { if __s0_buffer_get(MirV7Exit, xs, at).block == block { return true }
at = at + 1 }
return false }
fn mir_v7_node(d: Domain, nodes0: __s0_Buffer(MirV7Node), node_base: U64, function: U64, parent: U64, entry: U64) -> Result(__s0_Buffer(MirV7Node), __s0_Error) { var at = node_base
while at < __s0_buffer_len(MirV7Node, nodes0) { let n = __s0_buffer_get(MirV7Node, nodes0, at)
if n.function == function && n.parent == parent && n.entry == entry { return Ok(nodes0) }
at = at + 1 }
return __s0_buffer_append(MirV7Node, d, nodes0, MirV7Node(function: function, parent: parent, entry: entry)) }
fn mir_v7_node_id(nodes: __s0_Buffer(MirV7Node), node_base: U64, function: U64, parent: U64, entry: U64) -> U64 { var at = node_base
while at < __s0_buffer_len(MirV7Node, nodes) { let n = __s0_buffer_get(MirV7Node, nodes, at)
if n.function == function && n.parent == parent && n.entry == entry { return at + 1 }
at = at + 1 }
return 0 }
fn mir_v7_active_has(nodes: __s0_Buffer(MirV7Node), active0: U64, entry: U64) -> Bool { var active = active0
while active != 0 { let n = __s0_buffer_get(MirV7Node, nodes, active - 1)
if n.entry == entry { return true }
active = n.parent }
return false }
fn mir_v7_entry_belongs(store: MirStore, indexes: MirVIndexes, function: U64, scope: U64, entry: U64) -> Bool {
    let bcount = mir_vindex_block_count(indexes, function)
    var b: U64 = 1
    while b <= bcount {
        let icount = mir_vindex_instr_count(indexes, function, b)
        var ii: U64 = 0
        while ii < icount {
            let x = __s0_buffer_get(MirInstrRec, store.instructions, mir_vindex_instr(indexes, function, b, ii) - 1)
            if x.function == function && x.op == mir_op_cleanup_push() && x.a == scope && x.result == entry { return true }
            ii = ii + 1
        }
        b = b + 1
    }
    return false
}

// Removal collects newest-to-oldest IDs, then rebuilds oldest-to-newest.  The
// canonical node interner ensures equal ordered active sets have equal IDs.
fn mir_v7_remove(d: Domain, nodes0: __s0_Buffer(MirV7Node), node_base: U64, function: U64, active0: U64, entry: U64) -> Result(MirV7Remove, __s0_Error) { var nodes = nodes0
var ids = try __s0_buffer_new(U64, d)
var active = active0
var found = false
while active != 0 { let n = __s0_buffer_get(MirV7Node, nodes, active - 1)
if n.entry == entry { found = true } else { ids = try __s0_buffer_append(U64, d, ids, n.entry) }
active = n.parent }
if !found { return Ok(MirV7Remove(nodes: nodes, active: active0, found: false)) }
var rebuilt: U64 = 0
var at = __s0_buffer_len(U64, ids)
while at > 0 { let id = __s0_buffer_get(U64, ids, at - 1)
nodes = try mir_v7_node(d, nodes, node_base, function, rebuilt, id)
rebuilt = mir_v7_node_id(nodes, node_base, function, rebuilt, id)
at = at - 1 }
return Ok(MirV7Remove(nodes: nodes, active: rebuilt, found: true)) }
type MirV7Remove {
    nodes: __s0_Buffer(MirV7Node)
    active: U64
    found: Bool
}

fn mir_v7_add_config(d: Domain, seen0: __s0_Buffer(MirV7Config), queue0: __s0_Buffer(MirV7Config), block: U64, status: U64, active: U64) -> Result(MirV7Add, __s0_Error) { var seen = seen0
var queue = queue0
let x = MirV7Config(block: block, status: status, active: active)
if !mir_v7_config_has(seen, x) { seen = try __s0_buffer_append(MirV7Config, d, seen, x)
queue = try __s0_buffer_append(MirV7Config, d, queue, x) }
return Ok(MirV7Add(seen: seen, queue: queue)) }
type MirV7Add {
    seen: __s0_Buffer(MirV7Config)
    queue: __s0_Buffer(MirV7Config)
}

fn mir_v7_diag(d: Domain, out: __s0_Buffer(MirVerifyDiagRec), kind: U64, function: U64, block: U64, instruction: U64, terminator: U64, scope: U64) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
return mir_vadd(d, out, mir_vdiag(mir_verify_phase_cleanup(), kind, function, block, instruction, terminator, 0, 0, 0, 0, 0, scope)) }

fn mir_v7_run_set_has(sets: __s0_Buffer(MirV7RunSet), run_base: U64, function: U64, instruction: U64, active: U64) -> Bool { var at = run_base
while at < __s0_buffer_len(MirV7RunSet, sets) { let x = __s0_buffer_get(MirV7RunSet, sets, at)
if x.function == function && x.instruction == instruction && x.active == active { return true }
at = at + 1 }
return false }

fn mir_v7_one(d: Domain, store: MirStore, indexes: MirVIndexes, function: U64, scope: U64, node_base: U64, run_base: U64, analysis0: MirV7Analysis) -> Result(MirV7Analysis, __s0_Error) { var analysis = analysis0
var out = analysis.diagnostics
var nodes = analysis.nodes
var run_sets = analysis.run_sets
var seen = try __s0_buffer_new(MirV7Config, d)
var queue = try __s0_buffer_new(MirV7Config, d)
var bad = try __s0_buffer_new(MirV7Bad, d)
var exits = try __s0_buffer_new(MirV7Exit, d)
let first = try mir_v7_add_config(d, seen, queue, 1, mir_v7_absent(), 0)
seen = first.seen
queue = first.queue
var q: U64 = 0
while q < __s0_buffer_len(MirV7Config, queue) { let work = __s0_buffer_get(MirV7Config, queue, q)
var status = work.status
var active = work.active
var live = true
let icount = mir_vindex_instr_count(indexes, function, work.block)
var ordinal: U64 = 0
while live && ordinal < icount { let iid = mir_vindex_instr(indexes, function, work.block, ordinal)
let x = __s0_buffer_get(MirInstrRec, store.instructions, iid - 1)
// Checked failures observe the configuration before this instruction.
if mir_vop_checked(x.op) { let add = try mir_v7_add_config(d, seen, queue, x.target, status, active)
seen = add.seen
queue = add.queue }
var relevant = false
var valid = true
if x.op == mir_op_cleanup_scope_begin() && x.result == scope { relevant = true
valid = status == mir_v7_absent() || status == mir_v7_ended()
if valid { status = mir_v7_open()
active = 0 } }
if x.op == mir_op_cleanup_push() && x.a == scope { relevant = true
valid = status == mir_v7_open() && !mir_v7_active_has(nodes, active, x.result)
if valid { nodes = try mir_v7_node(d, nodes, node_base, function, active, x.result)
active = mir_v7_node_id(nodes, node_base, function, active, x.result) } }
if x.op == mir_op_cleanup_disarm() && mir_v7_entry_belongs(store, indexes, function, scope, x.a) { relevant = true
let removed = try mir_v7_remove(d, nodes, node_base, function, active, x.a)
nodes = removed.nodes
valid = status == mir_v7_open()
if valid { valid = removed.found }
if valid { active = removed.active } }
if x.op == mir_op_cleanup_scope_run() && x.a == scope { relevant = true
valid = status == mir_v7_open()
if valid { if !mir_v7_run_set_has(run_sets, run_base, function, iid, active) { run_sets = try __s0_buffer_append(MirV7RunSet, d, run_sets, MirV7RunSet(function: function, instruction: iid, active: active)) }
status = mir_v7_running() } }
if x.op == mir_op_cleanup_scope_end() && x.a == scope { relevant = true
valid = status == mir_v7_running()
if valid { status = mir_v7_ended()
active = 0 } }
if relevant && !valid { if !mir_v7_bad_has(bad, work.block, iid) { bad = try __s0_buffer_append(MirV7Bad, d, bad, MirV7Bad(block: work.block, instruction: iid)) }
live = false }
ordinal = ordinal + 1 }
if live { let term_id = mir_vindex_term(indexes, function, work.block)
if term_id != 0 {
    let t = __s0_buffer_get(MirTermRec, store.terminators, term_id - 1)
    if (t.kind == mir_term_return() || t.kind == mir_term_fail() || t.kind == mir_term_panic()) && (status == mir_v7_open() || status == mir_v7_running()) { if !mir_v7_exit_has(exits, work.block) { exits = try __s0_buffer_append(MirV7Exit, d, exits, MirV7Exit(block: work.block, terminator: term_id)) } }
    if t.kind == mir_term_jump() { let add = try mir_v7_add_config(d, seen, queue, t.target, status, active)
seen = add.seen
queue = add.queue }
    if t.kind == mir_term_branch() { let left = try mir_v7_add_config(d, seen, queue, t.then_block, status, active)
seen = left.seen
queue = left.queue
let right = try mir_v7_add_config(d, seen, queue, t.else_block, status, active)
seen = right.seen
queue = right.queue }
    if t.kind == mir_term_switch() { let total = mir_vindex_op_term_count(indexes, term_id)
var oi: U64 = 0
while oi < total { let c = __s0_buffer_get(MirOperandRec, store.operands, mir_vindex_op_term(indexes, term_id, oi) - 1)
if c.kind == mir_operand_switch_case() { let add = try mir_v7_add_config(d, seen, queue, c.target, status, active)
seen = add.seen
queue = add.queue }
oi = oi + 1 } }
} }
q = q + 1 }
// Emit in stable block/instruction order, independent of worklist discovery.
let bcount = mir_vindex_block_count(indexes, function)
var block: U64 = 1
while block <= bcount { let icount2 = mir_vindex_instr_count(indexes, function, block)
var ordinal2: U64 = 0
while ordinal2 < icount2 { let iid = mir_vindex_instr(indexes, function, block, ordinal2)
if mir_v7_bad_has(bad, block, iid) { out = try mir_v7_diag(d, out, mir_vdiag_cleanup_state(), function, block, iid, 0, scope) }
ordinal2 = ordinal2 + 1 }
var ei: U64 = 0
while ei < __s0_buffer_len(MirV7Exit, exits) { let e = __s0_buffer_get(MirV7Exit, exits, ei)
if e.block == block { out = try mir_v7_diag(d, out, mir_vdiag_cleanup_exit(), function, block, 0, e.terminator, scope) }
ei = ei + 1 }
block = block + 1 }
analysis.nodes = nodes
analysis.run_sets = run_sets
analysis.diagnostics = out
return Ok(analysis) }

fn mir_v7_analyze(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(MirV7Analysis, __s0_Error) {
var analysis = MirV7Analysis(nodes: try __s0_buffer_new(MirV7Node, d), run_sets: try __s0_buffer_new(MirV7RunSet, d), diagnostics: initial)
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { let node_base = __s0_buffer_len(MirV7Node, analysis.nodes)
let run_base = __s0_buffer_len(MirV7RunSet, analysis.run_sets)
var value: U64 = 1
while mir_vindex_value(indexes, function, value) != 0 { let vi = mir_vindex_value(indexes, function, value)
let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if mir_vtype_kind(store, v.value_type) == mir_type_kind_cleanup_scope() && v.def_kind == mir_value_def_instruction() { let iid = mir_v6_instruction_for_value(store, indexes, v)
if iid != 0 && __s0_buffer_get(MirInstrRec, store.instructions, iid - 1).op == mir_op_cleanup_scope_begin() { analysis = try mir_v7_one(d, store, indexes, function, value, node_base, run_base, analysis) } }
value = value + 1 }
function = function + 1 }
return Ok(analysis) }

fn mir_vphase7(d: Domain, store: MirStore, indexes: MirVIndexes, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) {
return Ok((try mir_v7_analyze(d, store, indexes, initial)).diagnostics) }
