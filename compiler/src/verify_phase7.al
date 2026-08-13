// Phase 7 tracks each cleanup scope independently.  A configuration is a
// status plus a canonical persistent stack node; nodes preserve registration
// identity and runtime push order without maps or recursive traversal.
fn mir_v7_absent() -> U64 { return 0 }
fn mir_v7_open() -> U64 { return 1 }
fn mir_v7_running() -> U64 { return 2 }
fn mir_v7_ended() -> U64 { return 3 }

type MirV7Node {
    parent: U64
    entry: U64
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
fn mir_v7_node(d: Domain, nodes0: __s0_Buffer(MirV7Node), parent: U64, entry: U64) -> Result(__s0_Buffer(MirV7Node), __s0_Error) { var at: U64 = 0
while at < __s0_buffer_len(MirV7Node, nodes0) { let n = __s0_buffer_get(MirV7Node, nodes0, at)
if n.parent == parent && n.entry == entry { return Ok(nodes0) }
at = at + 1 }
return __s0_buffer_append(MirV7Node, d, nodes0, MirV7Node(parent: parent, entry: entry)) }
fn mir_v7_node_id(nodes: __s0_Buffer(MirV7Node), parent: U64, entry: U64) -> U64 { var at: U64 = 0
while at < __s0_buffer_len(MirV7Node, nodes) { let n = __s0_buffer_get(MirV7Node, nodes, at)
if n.parent == parent && n.entry == entry { return at + 1 }
at = at + 1 }
return 0 }
fn mir_v7_active_has(nodes: __s0_Buffer(MirV7Node), active0: U64, entry: U64) -> Bool { var active = active0
while active != 0 { let n = __s0_buffer_get(MirV7Node, nodes, active - 1)
if n.entry == entry { return true }
active = n.parent }
return false }
fn mir_v7_entry_belongs(store: MirStore, function: U64, scope: U64, entry: U64) -> Bool { var at: U64 = 0
while at < __s0_buffer_len(MirInstrRec, store.instructions) { let x = __s0_buffer_get(MirInstrRec, store.instructions, at)
if x.function == function && x.op == mir_op_cleanup_push() && x.a == scope && x.result == entry { return true }
at = at + 1 }
return false }

// Removal collects newest-to-oldest IDs, then rebuilds oldest-to-newest.  The
// canonical node interner ensures equal ordered active sets have equal IDs.
fn mir_v7_remove(d: Domain, nodes0: __s0_Buffer(MirV7Node), active0: U64, entry: U64) -> Result(MirV7Remove, __s0_Error) { var nodes = nodes0
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
nodes = try mir_v7_node(d, nodes, rebuilt, id)
rebuilt = mir_v7_node_id(nodes, rebuilt, id)
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

fn mir_v7_one(d: Domain, store: MirStore, function: U64, scope: U64, out0: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = out0
var nodes = try __s0_buffer_new(MirV7Node, d)
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
var ordinal: U64 = 0
while live && ordinal < mir_vp4_instruction_count(store, function, work.block) { let iid = mir_vp4_instruction_at(store, function, work.block, ordinal)
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
if valid { nodes = try mir_v7_node(d, nodes, active, x.result)
active = mir_v7_node_id(nodes, active, x.result) } }
if x.op == mir_op_cleanup_disarm() && mir_v7_entry_belongs(store, function, scope, x.a) { relevant = true
let removed = try mir_v7_remove(d, nodes, active, x.a)
nodes = removed.nodes
valid = status == mir_v7_open()
if valid { valid = removed.found }
if valid { active = removed.active } }
if x.op == mir_op_cleanup_scope_run() && x.a == scope { relevant = true
valid = status == mir_v7_open()
if valid { status = mir_v7_running() } }
if x.op == mir_op_cleanup_scope_end() && x.a == scope { relevant = true
valid = status == mir_v7_running()
if valid { status = mir_v7_ended()
active = 0 } }
if relevant && !valid { if !mir_v7_bad_has(bad, work.block, iid) { bad = try __s0_buffer_append(MirV7Bad, d, bad, MirV7Bad(block: work.block, instruction: iid)) }
live = false }
ordinal = ordinal + 1 }
if live { var ti: U64 = 0
while ti < __s0_buffer_len(MirTermRec, store.terminators) { let t = __s0_buffer_get(MirTermRec, store.terminators, ti)
if t.function == function && t.block == work.block { if (t.kind == mir_term_return() || t.kind == mir_term_fail() || t.kind == mir_term_panic()) && (status == mir_v7_open() || status == mir_v7_running()) { if !mir_v7_exit_has(exits, work.block) { exits = try __s0_buffer_append(MirV7Exit, d, exits, MirV7Exit(block: work.block, terminator: ti + 1)) } }
if t.kind == mir_term_jump() { let add = try mir_v7_add_config(d, seen, queue, t.target, status, active)
seen = add.seen
queue = add.queue }
if t.kind == mir_term_branch() { let left = try mir_v7_add_config(d, seen, queue, t.then_block, status, active)
seen = left.seen
queue = left.queue
let right = try mir_v7_add_config(d, seen, queue, t.else_block, status, active)
seen = right.seen
queue = right.queue }
if t.kind == mir_term_switch() { var oi: U64 = 0
while oi < __s0_buffer_len(MirOperandRec, store.operands) { let c = __s0_buffer_get(MirOperandRec, store.operands, oi)
if c.kind == mir_operand_switch_case() && c.owner == ti + 1 { let add = try mir_v7_add_config(d, seen, queue, c.target, status, active)
seen = add.seen
queue = add.queue }
oi = oi + 1 } } }
ti = ti + 1 } }
q = q + 1 }
// Emit in stable block/instruction order, independent of worklist discovery.
var block: U64 = 1
while mir_vblock_index(store, function, block) != 0 { var ordinal2: U64 = 0
while ordinal2 < mir_vp4_instruction_count(store, function, block) { let iid = mir_vp4_instruction_at(store, function, block, ordinal2)
if mir_v7_bad_has(bad, block, iid) { out = try mir_v7_diag(d, out, mir_vdiag_cleanup_state(), function, block, iid, 0, scope) }
ordinal2 = ordinal2 + 1 }
var ei: U64 = 0
while ei < __s0_buffer_len(MirV7Exit, exits) { let e = __s0_buffer_get(MirV7Exit, exits, ei)
if e.block == block { out = try mir_v7_diag(d, out, mir_vdiag_cleanup_exit(), function, block, 0, e.terminator, scope) }
ei = ei + 1 }
block = block + 1 }
return Ok(out) }

fn mir_vphase7(d: Domain, store: MirStore, initial: __s0_Buffer(MirVerifyDiagRec)) -> Result(__s0_Buffer(MirVerifyDiagRec), __s0_Error) { var out = initial
var function: U64 = 1
while function <= __s0_buffer_len(MirFunctionRec, store.functions) { var value: U64 = 1
while mir_vvalue_index(store, function, value) != 0 { let vi = mir_vvalue_index(store, function, value)
let v = __s0_buffer_get(MirValueRec, store.values, vi - 1)
if mir_vtype_kind(store, v.value_type) == mir_type_kind_cleanup_scope() && v.def_kind == mir_value_def_instruction() { let iid = mir_v6_instruction_for_value(store, v)
if iid != 0 && __s0_buffer_get(MirInstrRec, store.instructions, iid - 1).op == mir_op_cleanup_scope_begin() { out = try mir_v7_one(d, store, function, value, out) } }
value = value + 1 }
function = function + 1 }
return Ok(out) }
