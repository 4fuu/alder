# C11 Backend

Status: Milestone 3 lowering contract with working Go and Alder-written M5.4
implementations

The Alder backend (`cgen` package) emits conservative, portable, inspectable C11 from verified Alder MIR. Its purpose is to validate Alder MIR semantics and provide a bootstrap path, not to make C the semantic definition of Alder.

LLVM and other native backends are outside the current scope.

## Pipeline

```text
verified Alder MIR
        |
        v
backend-specific naming and layout
        |
        v
deterministic C11 translation unit
        |
        +---- minimal Alder C runtime
        |
        v
Clang or GCC
```

Only verified MIR may reach code generation: `cgen.Generate` runs the full verifier and refuses invalid modules with the verifier diagnostics. The backend must not silently repair invalid domain, cleanup, type, or table-view behavior.

The Alder-written flat-MIR verifier exposes
`mir_verify_complete(d, store, version, hosted)`. Its `complete == true` result
is the required gate for any Alder-written C generator before it writes bytes;
hosted success also carries the verified 1-based entry function ID. Every
failure and every unhosted result carries entry ID zero; duplicate `main`
declarations are rejected earlier by V1's duplicate function-name rule.

The Alder-written `cgen_generate(d, store, version, hosted)` entry implements
the current production body path directly over flat MIR 4. It lowers loads,
stores, field and checked-reference places, aggregate and enum-like values,
scalar comparisons and conversions, checked integer and slice operations,
direct and unsafe-import calls, block edges with staged parallel copies,
branches, loops, switches, returns, typed failures, panic, unreachable, domains,
allocation, supported domain copies, cleanup scopes, generational tables, vectors,
and scoped array/vector views.
Every operand is read from an already materialized value in an explicitly
ordered statement; generated calls never embed another call or checked
operation in a C argument expression. Verification and the supported-operation
preflight both complete before the output buffer is allocated. Invalid or
unsupported MIR therefore returns false with zero output and is never repaired
or rewritten.

The final M5.4 Alder compiler driver exposes this generator through
`compile --emit=c`; the source-to-C path remains complete-verifier-gated and
zero-output on verifier or preflight rejection. The shared-core resource fixture independently
lowers the existing Stage 0 domain, lexical-cleanup, fixed-map, and private-
buffer bridge corpus, emits it through this path, and compiles and runs the
result against the existing runtime ABI. The Go `cgen` package remains the
host implementation used outside this internal compiler-core path.

The earlier declaration-only Alder backend lane remains as the focused
`cgen_write_declaration_skeleton` conformance API. It exposes
`cgen_write_declaration_skeleton(d, store, version, hosted)`. Before allocating
its output buffer it calls `mir_verify_complete`; only `complete == true`
proceeds. Emission consumes the returned `hosted` and external 1-based `entry`
fields rather than independently authorizing the caller's request. The complete
skeleton is buffered before stdout and contains headers, stable type layouts,
constant storage, import prototypes, internal function declarations, and the
optional verified hosted entry adapter. It still does not emit function bodies
and is not itself a production generator. Every rejection is zero-output and
never sanitizes or repairs an invalid store.

## Generated program entry

`cgen.GenerateProgram` is the explicit hosted-program path and the
verified-only gate for untrusted MIR. `cgen.GenerateProgramTrusted` is the
same lowering for a module the caller already verified. Generic
`cgen.Generate` remains a translation-unit generator and requires no `main`.
For Stage 0 only, a program has exactly one MIR function named `main`, returning
`i32`, with either no parameters or one `domain_handle` parameter. Hosted
projects may write the documented source entry results `Unit`, `I32`,
`Result(Unit, E)`, and `Result(I32, E)` where `E` implements `Display`; the
compiler lowers the source entry under an internal name and synthesizes an
`I32` adapter. The adapter maps `Unit`/`Ok(())` to status 0, `I32`/`Ok(I32)` to
the low eight bits, and `Err(E)` to status 1 after writing the `program error:`
diagnostic. Entry parameters remain the existing forms; argument-slice support
is outside this adapter. The generated MIR entry contract stays `I32`.

Program output exports exactly `int32_t alder_program_entry(void
*host_context)` in addition to any `export c fn` definitions; all other Alder
functions remain static and ID-named under the reserved `alder_` prefix. The
opaque, invocation-scoped context must be non-null. A domain-taking entry receives a
fresh root domain, which the wrapper destroys exactly once after normal return.
Null context or failed root initialization returns
`ALDER_PROGRAM_FAILURE_STATUS` deterministically.

The hosted driver installs the process vector with
`alder_host_set_args(argc, argv)` before calling `alder_program_entry`. The
runtime stores it read-only for the rest of the process; `std.env.arguments`
copies it into Alder-owned values. A custom C driver that does not call the
setter exposes an empty argument list, not host pointers.

## Binding and target-ABI probes

`compile --emit=bind` emits only the binding translation unit: each binding
header, `_Generic`/`_Static_assert` field and function checks, scalar spelling
checks, and target data-model assertions (`CHAR_BIT == 8`, pointer width,
`size_t`/`ptrdiff_t` width and alignment). It has no generated program entry,
runtime link, or Alder function bodies, so it runs before the hosted-entry
verification phase and is usable for a binding-only source set. The C compiler
that consumes it is the target ABI authority; no Alder layout engine is added.
The host x86-64 fixture compiles and runs the probe; Linux AArch64 and Windows
LLP64 compile-only lanes run the same deterministic unit through their target
C compilers. macOS targets are deferred to a macOS runner.

## Exported functions

An `export c fn` declaration emits a non-static C definition whose symbol is
the Alder name and whose signature is the C ABI signature printed by
`cgen_put_type`: `c.*` scalars, `c_ptr`/`c_const_ptr` values, and verified
bound records by value; a `Unit` result emits `void`. Parameters are named
`alder_a<N>` positionally. When the lowered function takes the hidden domain
parameter, the export wrapper creates a root `AlderDomain`, calls the internal
static function, destroys the domain, and returns the result; failed domain
initialization terminates through `alder_runtime_panic`. A function without
storage is called directly. Every call is self-contained: there is no global
initializer, no retained host context, and a foreign thread may call an export
without entering `alder_program_entry`. The runtime serial counters and live
allocation count are C11 atomics so independent root domains may enter
concurrently; `__STDC_NO_ATOMICS__` is a build error.

`compile --emit=header` prints the matching header from the verified MIR: the
guard word is a digest of the full sorted export-symbol list, each binding
block header referenced by an export signature is included once in declaration
order, and the prototypes follow the same C ABI spellings. Export wrappers are
a codegen feature only; they add no MIR operation, and the printed MIR carries
no export marker because export intent is internal compiler metadata. Panics
are never caught at the boundary, so process termination with the invariant
status remains the only portable panic behavior across C.

A source set with exports and no `main` is a library build: C emission skips
only the hosted-entry phase of verification (every other V1-V9 check still
runs), emits no `alder_program_entry`, and produces export wrappers callable
from an ordinary C `main`. A source set with neither `main` nor an export
keeps the missing-entry failure.

## Callback trampolines

Each `c.callback.make` site emits one static C trampoline named from its
target function and callback type IDs. The trampoline has the target's C ABI
signature, creates a fresh root domain when the target carries the hidden
domain parameter, calls the internal static function, destroys the domain,
and returns the C result. A failed domain initialization panics. A generated
`_Static_assert(_Generic(...))` pins the trampoline against the binding's
function-pointer typedef. The trampoline is storage for one raw-call argument:
no function-pointer value is stored in Alder locals, records, or collections.

A retained `c.CallbackOwner` is one `AlderCallbackOwner *` heap value from the
runtime. Registration allocates the owner and a context block separately,
copies the context into that block, calls the named setter with the trampoline
and the stable context address, and builds `Option(owner)`. The generated
release helper calls the recorded clear function, panics with status 101 when it returns nonzero, calls the wait function, and frees the owner.
Moving the owner value never moves the context block. A callback may run on a
foreign thread after registration: the trampoline enters a per-invocation
root domain, and the owner's `wait` must be a real barrier that returns only
after every C thread has stopped using the callback and context. Host-shim
services with their own threads remain excluded until the hosted entry bridge
exists.

The separate `bootstrap/alder_host.c` hosted shim owns the private context
layout and calls the stable prototype in `bootstrap/alder_host.h`; generated C
is linked as a separate translation unit and does not depend on the Go runtime.
The compiler host preserves the S0 status classes: 0 success, 1 source
diagnostics, 2 usage/request, 3 I/O/storage, and 4 internal/backend.

The Alder declaration skeleton renders this adapter only for syntax
conformance. `cgen_generate` emits the corresponding function bodies and its
hosted output is linked and run by the scalar/CFG acceptance fixture.

The narrow Stage 0 hosted ABI parses the documented `check`/`compile` request,
then exposes its sorted explicit source snapshot
through `alderhost_source_count`, `alderhost_source_path_len`/`_byte`, and
`alderhost_source_text_len`/`_byte`. The host sorts exact argument strings with
`strcmp`, rejects duplicates, and loads every file in binary mode before entry;
it performs no directory scanning, path normalization, or pointer exposure.
Source counts, paths, and file contents that are not representable as `U64`
are rejected before entry.
Length and byte accessors require an active invocation and valid indices, and a
contract violation terminates with a fixed host diagnostic. `alderhost_stdout_byte`
and `alderhost_stderr_byte` write exactly one byte without a newline and return
false outside an active invocation or on write failure. The invocation context
layout remains private, is active only during `alder_program_entry`, and is
valid under the single-threaded Stage 0 runtime contract. Inputs are freed and
both output streams are flushed after entry. Artifact files use same-directory
replacement and are committed only after compiler and flush success. This host
ABI is distinct from the
generated entry ABI; `alder_program_entry(NULL)` remains wrapper-owned.

## Step Trampolines and the Task Runtime

This section pins the C side of the suspension representation defined in
[Alder MIR](mir.md#suspending-instances-and-step-frames). Step functions are
generated statics; the executor never sees Alder source and never allocates or
interprets a typed frame. The ABI below is the complete boundary between
generated code and `runtime/c`.

### Pinned step ABI

```c
typedef struct AlderTask AlderTask;

typedef enum AlderStepStatus {
    ALDER_STEP_DONE = 0,      /* finished; result is in frame->out */
    ALDER_STEP_CALL = 1,      /* published a callee and yielded */
    ALDER_STEP_PARK = 2,      /* waits for an external wakeup */
    ALDER_STEP_CANCELLED = 3  /* teardown done; no result */
} AlderStepStatus;

typedef AlderStepStatus (*AlderStepFn)(AlderTask *task,
                                       AlderDomain *results,
                                       void *frame,
                                       AlderDomain *frame_domain);
```

- `task` is the opaque task record; it is also available through the
  thread-local current-task accessor, but it is passed explicitly so the
  trampoline needs no lookup.
- `results` and `frame_domain` are the same `AlderDomain *` for a step
  activation: the activation's own storage domain, which owns the frame.
- `frame` is the opaque frame record allocated in `frame_domain`.
- `ALDER_STEP_DONE` requires `frame->out` to be initialized; the executor
  does not inspect it. `ALDER_STEP_CANCELLED` requires no result and leaves
  the task's cancel flag set.
- `ALDER_STEP_CALL` requires that the step call
  `alder_task_call(task, callee, frame, domain)` before returning. The
  executor pushes one activation built from that publication.
- `ALDER_STEP_PARK` parks the task unless its wakeup latch is already set.
- `ALDER_STEP_CANCELLED` pops the activation; the caller is resumed only on
  its cancellation edge.

`AlderStepFn` is an internal ABI: no step thunk is exported, no Alder
function type names it, and no foreign header declares it. It reuses the
callback trampoline machinery in the narrow sense that generated code passes a
static function address and an opaque frame/context pointer to a C runtime
entry with a fixed typedef. It differs from `c.callback.make` and export
wrappers in one decisive way: a step thunk **does not create a root domain**.
The activation domain is supplied by the caller or by the task record, so
frames and their storage survive the return to the executor and are reclaimed
by the activation that owns them.

### Generated thunk

For each step function `<function-id>` whose MIR body lowers to
`alder_fn_<name-fragment>_<id>`, the backend emits one static thunk with the
same name convention and the `alder_step` prefix:

```c
static AlderStepStatus alder_step_<name-fragment>_<id>(
    AlderTask *alder_task, AlderDomain *alder_results,
    void *alder_frame_ptr, AlderDomain *alder_frame_domain) {
    AlderTy<frame-type> *alder_frame = (AlderTy<frame-type> *)alder_frame_ptr;
    AlderStepStatus alder_status = alder_map_status(
        alder_fn_<name-fragment>_<id>(alder_results,
            (AlderSlice){alder_frame_ptr, UINT64_C(1)},
            alder_frame_domain));
    if (alder_status == ALDER_STEP_CALL) {
        switch (alder_frame->alder_f<state-ordinal>.alder_tag) {
        case <resume0-ordinal>:
            alder_task_call(alder_task, alder_step_<callee-fragment>_<callee-id>,
                            alder_frame->alder_f<x0-ordinal>.data,
                            alder_frame->alder_f<y0-ordinal>);
            break;
        /* one case per call-type resume state, in state order */
        default:
            alder_runtime_panic("step.call from a non-call state");
        }
    }
    return alder_status;
}
```

Every element is determined by stable MIR data: the body function's ID gives
the symbol, the frame type gives the C struct, field ordinals come from the
frame field order, and each `resume<i>` case comes from the `x<i>`/`y<i>`
fields and the state enum. The callee step FunctionId for each call-type
resume state is recorded in the step function's lowering metadata, like the
export intent metadata, so the thunk uses a stable ID rather than re-deriving
a name; the printed `x<i>` type makes the callee instance inspectable. There
is no name matching and no dependence on source spelling. The status mapping is a four-way switch on the enum tag;
`done`/`call`/`park`/`cancelled` map to 0/1/2/3. A frame field of type `safe_mut(T)` lowers
to `AlderSlice`; the thunk passes its `.data` pointer as the opaque callee
frame. The frame parameter itself is passed to the body as the one-element
`AlderSlice`.

The thunk is an address-taken static; the compiler verifies its type by
initializing a static `AlderStepFn` object with it, so a signature drift is a
C constraint violation under the strict warning set. The generated file never
declares the runtime task functions as ordinary C bindings: they are emitted
by the backend exactly like `alder_domain_alloc` and `alder_cleanup_run`.

### Frame lowering

- `alloc %d, @__alder_step.frame.<instance>, %one` lowers to the ordinary
  checked size/alignment preparation and `alder_domain_alloc`, then builds
  the one-element `AlderSlice`. No new allocation path exists.
- Hidden frame slots keep their existing names (`alder_domain_<site>`,
  `alder_scope_<site>`) but move from C locals of the body function into the
  frame struct, after the MIR-visible fields. A `domain.create` site
  initializes its hidden `AlderDomain` in place on first execution; a
  `cleanup.scope.begin` site calls
  [`alder_cleanup_scope_begin_adopting`](#frame-resident-cleanup-cursors),
  which returns the existing frame-resident scope on a re-entry and
  initializes it on the first entry. Both objects are zero-initialized with
  the frame.
- `field(deref %frame, name)` lowers to a member access on the typed frame
  struct. Field names never become C members: the existing ordinal-based
  member spelling (`alder_f<N>`) applies to frame fields like any other
  aggregate.
- The frame's `state` field is the first MIR-visible field and therefore the
  first generated member. The thunk reads it for the call table; no other
  component interprets it.
- A call-type suspension point lowers to ordinary MIR stores of `state`,
  `x<i>`, `y<i>`, and the saved fields, then `return <status>`. The body does
  not emit a C call to the callee; the thunk publishes it from the state
  table. This is what keeps worker stack depth independent of logical call
  depth.
- A park-type point lowers to the same stores without `x<i>`/`y<i>` and
  `return park`. The operation's wakeup registration is emitted by the
  capability wrapper's own lowering, before the return.
- The program entry for an async instance creates the root activation domain
  (`alder_domain_init(&root, NULL)`), allocates the root frame in it, sets
  `state` to `entry` and the entry parameters, creates a root task with
  `alder_task_create(group, root_step, root_frame, &root)` assigned to
  `task`, records its id with `alder_task_handle(task)` as `task_id`, starts
  it with `alder_task_start(task)`, and runs
  [`alder_executor_run`](#executor-entry-and-hooks). A true result
  means every task completed; the entry then reads the root frame's `out`,
  calls `alder_task_release(task_id)`, destroys the root domain, and returns
  the program status. A false result is the blocked-program report and the
  entry does not read `out`. The root activation is a task like any other;
  the runtime has no task-less root activation. A synchronous `main` keeps
  the existing direct entry.

### Task runtime ABI

The runtime provides these entries to generated code and to the Alder
standard-library bindings. Unless stated otherwise they observe the current
task through a thread-local set by the executor around each step call; they
are contract violations outside a step. `alder_task_create`,
`alder_task_create_on_lane`, `alder_task_start`, `alder_task_handle`,
`alder_task_wake_id`, `alder_wakeup_signal`, `alder_timer_at`,
`alder_task_cancel`, `alder_task_release`, `alder_executor_configure`, and
`alder_executor_run` (pinned in [Executor entry and
hooks](#executor-entry-and-hooks)) are callable outside a step.
`alder_task_blocking` observes the current task and is callable only inside a
step. The remaining entries observe the current task.

```c
typedef struct AlderWakeup AlderWakeup; /* one per task, stable address */

typedef enum AlderTaskLane {
    ALDER_LANE_POOL = 0,
    ALDER_LANE_LOCAL = 1
} AlderTaskLane;

typedef struct AlderExecutorConfig {
    uint32_t workers;
    uint32_t blocking_workers;
    bool local_lane;
} AlderExecutorConfig;

typedef void (*AlderBlockingFn)(void *context);

AlderTask *alder_task_create(uint64_t group, AlderStepFn step,
                             void *frame, AlderDomain *domain);
AlderTask *alder_task_create_on_lane(uint64_t group, AlderTaskLane lane,
                                     AlderStepFn step, void *frame,
                                     AlderDomain *domain);
void alder_task_start(AlderTask *task);
void alder_task_call(AlderTask *task, AlderStepFn callee,
                     void *frame, AlderDomain *domain);
AlderWakeup *alder_task_wakeup(void);
void alder_wakeup_signal(AlderWakeup *wakeup);
void alder_task_wake_id(uint64_t task);
void alder_task_yield(void);
void alder_task_wait_reason(uint32_t reason);
bool alder_task_cancelled(void);
void alder_task_shield_push(void);
void alder_task_shield_pop(void);
bool alder_timer_at(AlderWakeup *wakeup, uint64_t deadline);
bool alder_task_await(uint64_t child);
bool alder_task_blocking(AlderBlockingFn fn, void *context);
void alder_task_cancel(uint64_t task);
void alder_task_release(uint64_t task);
uint64_t alder_task_id(void);
uint64_t alder_task_handle(AlderTask *task);
bool alder_executor_configure(const AlderExecutorConfig *config);
```

Failure contracts:

- `alder_task_create` allocates the task record, initializes its activation
  stack with one root activation, allocates the wakeup token, and returns a
  task in the `created` state. It fails only through process termination on
  allocation or identity exhaustion. It creates the task on
  `ALDER_LANE_POOL`.
- `alder_task_create_on_lane` is the lane-taking form. The lane is fixed at
  creation: pool tasks may resume on any pool worker, while local tasks
  resume only on the single local-lane thread, including across executor
  runs. A task created on `ALDER_LANE_LOCAL` requires the active
  configuration to enable the local lane; creating one otherwise is a
  contract violation. `alder_task_create` is
  `alder_task_create_on_lane(..., ALDER_LANE_POOL, ...)`.
- `alder_executor_configure` selects the executor for the next runs. It may
  only be called while no executor run is active, no task is live, no
  blocking entry is in flight, and the timer heap is empty; otherwise it
  returns false and changes nothing. A NULL configuration restores the
  default single-worker inline executor pinned by gate 9.2. A non-NULL
  configuration selects the threaded executor: `workers` pool workers
  (1 through 64), `blocking_workers` blocking-pool threads (0 through 32,
  zero disabling blocking submission), and the persistent local lane when
  `local_lane` is true. An out-of-range field returns false. Thread creation
  failure terminates the process.
- `alder_task_start` commits a created task to its executor. A task is not
  runnable before start, which is the spawn synchronization point: the
  spawner initializes the frame and its arguments with no concurrent reader.
- `alder_task_call` stores the callee publication used by the next
  `ALDER_STEP_CALL`. Calling it without a following `call` return, or
  returning `call` without it, is a contract violation.
- `alder_wakeup_signal` is idempotent and thread-safe. It sets the task's
  latch and, when the task is parked, makes it runnable through its fixed
  lane. A signal after the task is runnable only sets the latch. In the
  threaded executor a winning signal pushes the wakeup token on the MPSC
  token list; a worker drains the list and enqueues the task on the lane
  recorded in the task.
- `alder_task_wake_id` resolves a generational task id and signals that
  task's wakeup. It is the binding-safe form used by channel and
  synchronization wait lists, which store ids rather than wakeup pointers. A
  released or foreign id is a contract violation.
- `alder_task_yield` makes the current task runnable at the back of the run
  queue; the step still returns `park`, and the already-set latch keeps it
  runnable.
- `alder_task_wait_reason` records the diagnostic wait category used by
  `SimIo`'s blocked-task report: `ALDER_WAIT_NONE` (0), `ALDER_WAIT_IO` (1),
  `ALDER_WAIT_TIMER` (2), `ALDER_WAIT_TASK` (3), `ALDER_WAIT_CHANNEL` (4),
  `ALDER_WAIT_GROUP` (5), or `ALDER_WAIT_BLOCKING` (6). It is metadata only
  and never affects scheduling. The executor clears the field when it
  dequeues the task.
- `alder_task_cancelled` reports false while the shield depth is positive.
- `alder_timer_at` registers an absolute deadline in the monotonically
  increasing executor clock. A deadline at or before the current clock
  signals immediately. `UINT64_MAX` is the no-deadline sentinel: it returns
  false without signalling or registering anything, and every other
  `uint64_t` deadline is in range. Timers are ordered by `(deadline,
  task-id)` so equal deadlines are deterministic. In the threaded executor
  the calling step posts the registration to the timer thread, which owns
  the heap; completion removes a task's remaining registrations before the
  task becomes `done`, so release still observes a drained record.
- `alder_task_await` registers the current task as a waiter on the child and
  returns true when the child is already complete; false means the caller must
  park. A child may be awaited once; a released or foreign task id is a
  contract violation.
- `alder_task_blocking` submits `fn(context)` to the configured blocking pool,
  registers the current task's wakeup token, and returns true; the step must
  then return `park`. The entry holds one retain on the task record and the
  wakeup token until `fn` returns, so cancellation that completes and
  releases the task first stays safe. A queued entry whose task is canceled
  before a blocking worker claims it is withdrawn: the worker skips `fn`,
  signals the retained wakeup, and drops the retain. An entry a worker has
  already claimed runs to completion; cancellation never interrupts it. A
  submission made while the task's shield depth is positive is never
  withdrawn. At most one entry may be pending for a task at a time.
  `context` is borrowed and must stay valid until `fn` returns; the runtime
  does not retain caller frame storage. A local-lane task may submit an
  entry; the call itself runs on a blocking worker, so it must not depend on
  the local lane's thread affinity. It returns false without queueing when no
  blocking workers are configured. A null `fn`, a second pending entry, or a
  call outside a step is a contract violation.
- `alder_task_release` requires that the task's activation stack is empty,
  every wakeup/timer registration is already removed or drained, and the
  caller has copied any result it needs; it then unlinks the task from its
  group and drops the spawner's reference. The only registration that may
  still be live is a blocking entry, which holds its own retain: the record
  is freed when C returns instead of here. Releasing with any other live
  registration is a contract violation. The spawner still owns the root
  activation domain and destroys it after release, so the result copy must
  happen before that destroy. A wakeup token is never retained past the
  final free.
- `alder_task_cancel` sets the target's cancel flag, withdraws its queued
  blocking entry when one exists and was not submitted under a positive
  shield, and signals its wakeup. A claimed entry is not interrupted. It does
  not run user code on the caller's thread.
- `alder_task_id` returns the current step's generational task id.
  `alder_task_handle` returns the id assigned to a specific task record. The
  spawn lowering and the root program entry use
  `alder_task_handle(task)` after create; `alder_task_id` would return the
  spawner's id instead. The task pointer is valid until `alder_task_release`,
  and the returned id is the value used by every id-taking entry.

`alder_task_create` plus `alder_task_start` is the two-phase form used by the
spawn lowering; the `task.spawn` MIR operation of MIR 7 is their typed front
end. The lowering obtains the child id with `alder_task_handle(task)`, not
`alder_task_id`. The task record, activation stack, latch, shield, timer
links, and cancel flag are runtime state; none is visible to MIR as a value.

The `group` argument is an opaque 64-bit runtime group id supplied by the
`std.task` group binding. In the gate 9.2 foundation the runtime keeps a
lazily created internal group list only to unlink a task at
`alder_task_release`; the record is freed when its last task is released and
carries no cancellation or join policy. Gate 9.4 owns the group record, its
lifetime, and the create/cancel/join surface.

### Frame-resident cleanup cursors

The frame-resident cleanup scope adds one resumable path without a new MIR
operation. The scope layout is part of the generated ABI because step frames
embed it:

```c
typedef struct AlderCleanupScope {
    AlderCleanupEntry *armed_head;
    AlderCleanupEntry *spent_head;
    bool ran;
    bool active;
    bool cursor;
} AlderCleanupScope;

bool alder_cleanup_scope_begin_adopting(AlderCleanupScope *scope);
bool alder_cleanup_push_step(AlderCleanupScope *scope, AlderStepFn driver,
                             void *context, AlderCleanupId *out_id);
bool alder_cleanup_scope_next(AlderCleanupScope *scope,
                              AlderCleanupFn *fn, void **context);
bool alder_cleanup_scope_next_step(AlderCleanupScope *scope,
                                   AlderStepFn *driver, void **context);
```

- `alder_cleanup_scope_begin_adopting` is the frame-resident begin. On the
  first entry it initializes the zero-initialized slot and returns true; on a
  re-entry after a suspended run it returns true with the active scope and
  its entries unchanged. A NULL scope returns false.
  `alder_cleanup_scope_begin` keeps its non-adopting behaviour for ordinary
  scopes and returns false when the scope is already active.
- `cleanup.push` records a synchronous hook through `alder_cleanup_push` as
  today, or a step hook through `alder_cleanup_push_step` as a generated
  driver thunk plus its context. Both use the same allocation, reverse
  registration order, disarm, and at-most-once rules. `alder_cleanup_push_step`
  returns false on an inactive scope, a NULL driver or out_id, or out of
  memory, like `alder_cleanup_push`. `alder_cleanup_end` frees either kind of
  entry.
- `cursor` is zero in a newly begun or adopted scope and is set by any cursor
  call. It records that the scope is running through the resumable protocol,
  so a later `alder_cleanup_run` on that scope is a contract violation, and a
  resumable run never mixes in `alder_cleanup_run`. A run with no suspending
  entries keeps `alder_cleanup_run`; `alder_cleanup_run` with an armed step
  entry is a contract violation.
- Each successful cursor call consumes exactly one armed entry in reverse
  registration order and returns its hook and context. Disarmed entries are
  skipped without being returned. If the next armed entry is of the other
  kind, the cursor returns false without advancing, so the caller tries the
  matching cursor for that entry. The mixed-run loop is:

```c
for (;;) {
    AlderCleanupFn fn;
    void *context;
    if (alder_cleanup_scope_next(&scope, &fn, &context)) {
        fn(context);
        continue;
    }
    AlderStepFn driver;
    if (alder_cleanup_scope_next_step(&scope, &driver, &context)) {
        /* publish the driver as a call or park activation, then resume here */
        break;
    }
    break; /* no entries remain */
}
```

- A step driver is published as a call or park activation, never called
  directly by the cursor. When it returns `done`, the splitter re-enters the
  loop at the next entry; a `cancelled` driver follows its cancellation edge.
- The cursor position is the scope's armed-list head plus the `cursor`
  marker, so it is stored in the frame-resident `AlderCleanupScope` and a
  suspended run resumes at the next entry. When a cursor reports false
  because no armed entries remain, the scope is marked run and
  `alder_cleanup_end` accepts it.

### Executor architecture

The default configuration is the gate 9.2 executor: one worker in one OS
thread, selected when `alder_executor_configure` has not been called or was
reset with NULL. It provides:

- a FIFO run queue of runnable tasks;
- a timer min-heap ordered by `(deadline, task-id)` so equal deadlines are
  deterministic;
- a wakeup latch and a FIFO run queue guarded by an atomic spin lock, so
  signals from foreign threads or host shims may enter it safely;
- the activation stack per task, grown on the heap with a stable base pointer
  so a `safe_mut` frame reference is never invalidated;
- a loop that pops a runnable task, clears its latch, calls its top
  activation's thunk, and applies the status: `done` pops an activation and
  resumes the new top (or completes the task), `call` pushes the published
  activation, `park` parks the task unless the latch is set. When no task is
  runnable and a timer exists, the monotonically increasing clock advances
  to the earliest deadline and the timer signals its token. When no task is
  runnable, no timer exists, and tasks remain, the executor reports the
  quiescent set through `on_idle` when present and `alder_executor_run`
  returns false.

The threaded executor below is selected for any non-NULL configuration; its
observable scheduling follows the same rules, with the explicitly documented
multi-worker ordering freedom.

### Executor entry and hooks

The executor has one entry and one optional hooks record:

```c
enum {
    ALDER_WAIT_NONE = 0,
    ALDER_WAIT_IO = 1,
    ALDER_WAIT_TIMER = 2,
    ALDER_WAIT_TASK = 3,
    ALDER_WAIT_CHANNEL = 4,
    ALDER_WAIT_GROUP = 5,
    ALDER_WAIT_BLOCKING = 6
};

typedef struct AlderBlockedTask {
    uint64_t task_id;
    uint32_t wait_reason;
} AlderBlockedTask;

typedef uint64_t (*AlderExecutorNowFn)(void *context);
typedef bool (*AlderExecutorStartOpFn)(void *context, uint64_t task_id,
                                       uint64_t operation);
typedef void (*AlderExecutorCancelOpFn)(void *context, uint64_t task_id,
                                        uint64_t operation);
typedef void (*AlderExecutorIdleFn)(void *context,
                                    const AlderBlockedTask *blocked,
                                    size_t count);

typedef struct AlderExecutorHooks {
    AlderExecutorNowFn now;
    AlderExecutorStartOpFn start_op;
    AlderExecutorCancelOpFn cancel_op;
    AlderExecutorIdleFn on_idle;
    void *context;
} AlderExecutorHooks;

bool alder_executor_run(const AlderExecutorHooks *hooks);
```

- `alder_executor_run` runs the configured executor until every live task has
  completed or no task can make progress without an external wakeup. It
  returns true when no incomplete task remains and false when the program is
  quiescent with at least one blocked task. In the false case `on_idle`, when
  present, has already received the blocked set. A true result does not
  release records: completed tasks remain until their spawners call
  `alder_task_release`. `hooks` may be NULL, and the record is read only for
  the duration of the call. Re-entering the executor from a step is a
  contract violation. A host loop re-runs `alder_executor_run` after an
  external wakeup that left the program quiescent; a signal delivered while a
  run is active is serviced by that run, and timers advance inside it.
- `now` seeds and refreshes the monotonically increasing executor clock: the
  clock is the greater of its current value and `now(context)`, and the idle
  loop advances it to the earliest timer deadline. The clock never moves
  backwards. The executor never writes through `now`, and has no other clock
  source; when `now` is NULL the clock advances only to timer deadlines. The
  9.2 ABI has no step-visible clock read, so `alder_timer_at` takes only an
  absolute deadline; gate 9.7 adds the read, or a duration-taking sleep
  binding, that relative sleeps need.
- `start_op` and `cancel_op` are the capability-operation hooks. They are
  stored in the hooks record for the gate 9.7 capability surface; the 9.2
  foundation has no capability-operation entry and never invokes them.
  `task_id` is the generational task id and `operation` is an opaque binding
  handle.
  `start_op` returns true when the test runtime accepts the operation and
  false when it refuses it; `cancel_op` asks the runtime to cancel or
  complete it.
- `on_idle` receives the blocked task set ordered by ascending task id. The
  array is runtime-owned and valid only for the duration of the call.
  `context` is passed to every hook unchanged.
- Wait reasons are the stable values above. `alder_task_wait_reason` records
  one of them; the value is metadata only and never affects scheduling.

### Threaded executor (gate 9.6 slice A)

`alder_executor_configure` with a non-NULL record selects the threaded
executor for subsequent runs. It extends the records above; no MIR value or
generated thunk changes.

- **Pool.** `workers` pool workers share one FIFO pool lane. The latch, the
  run-queue and wakeup-token links, and the timer links are C11 atomics; the
  lane and queue structure are serialized by an executor mutex. A worker
  dequeues a task, owns its frame and activation stack until the task
  suspends or completes, and then returns it to the lane through the same
  state protocol as the inline loop.
- **Local lane.** A task created on `ALDER_LANE_LOCAL` is enqueued on a
  separate single-consumer lane. One persistent local thread runs only while
  `alder_executor_run` is active, so every resumption of a local task uses
  the same OS thread, including across runs. Pool tasks never enter the
  local lane. Cross-lane wakeups use the same wakeup token and MPSC token
  list; the drain routes by the task's fixed lane.
- **Timer thread.** One timer thread per run owns the heap. Steps post
  registrations; completion posts a cancellation and waits until the timer
  thread has removed the task's registrations, so a completed task is
  drained before it can be released. When all workers are idle the
  coordinator asks the timer thread to advance the clock to the earliest
  deadline and fire every due token in `(deadline, task-id)` order. Virtual
  time therefore advances exactly as in the inline loop.
- **Blocking pool.** `blocking_workers` fixed threads persist across runs.
  A submission queues `fn(context)`, takes a retain on the task record, and
  the step parks. Cancellation withdraws a queued entry before a worker
  claims it; a claimed entry runs to completion without interruption. A
  withdrawn or completed entry signals the retained wakeup token and drops
  the retain, so the record is freed by whichever holder releases last.
  Cancellation therefore stops waiting for a queued operation when it is
  still possible to do so. `context` must outlive the call.
- **Thread shim.** The threaded executor uses POSIX threads. The inline
  default performs no thread creation, but `runtime/c/alder.c` is built
  against a POSIX host (it already requires `<execinfo.h>` for panics).
  Link commands include the host thread library; `-pthread` is required on
  glibc hosts older than 2.34, while current glibc and macOS link the same
  symbols without an extra flag.
- **Determinism.** With one pool worker the threaded executor preserves the
  inline queue and timer order; the runtime fixtures pin the gate 9.2
  ordering scenarios in that mode. With several workers, independent
  results and program-ordered observations remain deterministic, while the
  completion order of independent tasks is scheduler-dependent, as
  [Async and Structured Concurrency](async.md#executors) documents for
  `Evented`.

### Remaining executor extensions

Gate 9.6 slice A implements the worker pool, local lane, bounded blocking
pool, and the timer/wakeup ownership described above. Later gates extend the
same records and ABI, never the MIR representation:

- **Thread-safe C callback bridge.** Provider-owned threads and the
  blocking-bridge completion path beyond `alder_task_blocking` remain a
  later gate 9.6 slice; the foreign-thread export trampoline of gate 8 is
  unchanged.
- **SimIo capability operations.** `start_op` and `cancel_op` are stored for
  the gate 9.7 capability surface, which adds their call sites. `now` supplies
  the clock for timers and measurements; `on_idle` reports quiescence with the
  blocked task list and the wait reasons.


### Handwritten C and Alder sysroot modules

Handwritten C in `runtime/c` owns only the mechanism that cannot be expressed
through verified C bindings or would have to be duplicated per host:

- the `AlderStepFn` typedef, task/activation records, run queue, timer heap,
  wakeup latch/queue, shield depth, cancellation flags, and executor loop;
- frame-domain and activation-stack management, task id allocation, and
  release;
- the blocking-pool and platform thread/clock shims;
- the thread-safe wakeup bridge and its atomic state.

Alder sysroot modules over verified C bindings own policy and data
structures that safe Alder can express:

- `std.task`: `TaskGroup`, `Task(T)`, `start`, await/join policy, timeout and
  race composition, `CancellationToken`, `check_cancel`, and yield;
- `std.channel`, `std.sync`, `std.atomic`: channel FIFO, buffering, and
  waiter nodes holding generational task ids, shared ownership and guards,
  and explicit memory orders, using `alder_task_wake_id` and the atomic
  bindings;
- `std.io` `Evented`: the capability value and the read/write/sleep wrappers
  that start an operation, park, and finish it;
- `std.test` `SimIo`: the deterministic `AsyncIo` implementation over the
  executor hooks.

The step splitter that produces frames and step functions lives in the
Alder-written lowering (`compiler/src/lower.al`), not in the runtime and not
in the C backend. The C backend only emits the frame struct, the thunk, and
the ordinary lowering of the step body.

### Lifetime and determinism rules

- A task record is freed only after its activation stack is empty, every
  wakeup/timer registration is removed or drained, its parent has released
  it, and every blocking entry that retains it has returned. A wakeup token
  is never retained past that point. A `cancelled` activation counts as
  popped: its frame is dead, and any shim it used has already reached a
  terminal state or the activation parked in shielded teardown until it did.
  A blocking entry is the one registration that may outlive release: its
  retain keeps the record and its wakeup token alive until C returns, and
  the last reference frees it.
- A task is owned by exactly one worker from dequeue to its next suspension
  or completion, so its frame, activation stack, shield depth, and await
  links need no per-access locking. Creation, release, id resolution, and
  await registration are serialized by the runtime registry lock; state
  transitions, the wakeup latch, lane links, and timer links are C11
  atomics. The local lane's single persistent thread owns every local
  activation of a local task.
- A callee activation domain is destroyed by its caller only after the callee
  activation has been popped and its `out` copied. A task's root activation
  domain is borrowed by the task record and destroyed by the spawner after
  `alder_task_release`; the result copy happens before the destroy.
- The shield depth is task state, so a teardown that suspends on a group join
  resumes still shielded. A task that reaches its root `done` with nonzero
  shield depth is a contract violation.
- Generation is deterministic: function and type IDs are stable, frame fields
  follow the pinned order, thunk names use the existing name-fragment plus ID
  convention, the state table is emitted in state order, and no output
  depends on map iteration, pointer values, host paths, or thread scheduling.
  Printed MIR is byte-identical across processes for the same input, and the
  generated C differs only where host toolchain data legitimately differs.
  Runtime results are deterministic whenever the program orders its own
  observations; with one pool worker, queue and timer order match the inline
  executor. The completion order of independent tasks on multiple workers is
  scheduler-dependent and is not program-visible by contract.

## Milestone 3 Lowering Contract

### Naming and layout

- generated identifiers derive from stable numeric IDs: `alder_v<N>` for values, `alder_l<N>` for locals, `alder_b<N>` for block labels, `AlderTy<N>` for struct types, `AlderFnTy<N>` for function-pointer typedefs, `alder_fn_<name>_<id>` for functions, `alder_copy_ty<N>` for copy helpers, `alder_str_<N>` for string constants, and `alder_domain_<N>`, `alder_scope_<N>`, `AlderCtx_<N>`, `alder_ctx_<N>`, `alder_cleanup_<N>` for hidden slots, contexts, and cleanup adapters;
- source aggregate field names never become C members: fields use declaration ordinals (`alder_f<N>`), preventing sanitized-name collisions. Types and copy helpers are emitted in stable dependency-first order, with forward typedefs for record-like types;
- all generated statics carry `ALDER_MAYBE_UNUSED` so drivers and dead MIR code compile under `-Werror`.

### Type mapping

- `unit` is represented by `(uint8_t)0` only where storage or an expression is required; unit SSA declarations and assignments are erased. It is `void` as a function result, while unit parameters and call arguments are omitted, which is exact because unit has exactly one value;
- `bool` maps to `bool`; integers to the exact-width `intN_t`/`uintN_t` (which C11 requires to be two's complement); floats to `float`/`double`;
- aggregates and enum-like types (declared enums, `option`, `result`) map to structs: fields in declaration order; enums are tagged unions with `uint32_t alder_tag` (variant index) and a union of non-unit payloads named `alder_p<index>`. An empty aggregate has one private byte because portable C11 has no empty structs;
- `string` maps to `AlderString { const uint8_t *data; uint64_t len; }` and `bytes` maps to the layout-identical but distinct `AlderBytes`; ordinary assignment, argument passing, and return copy the value while sharing immutable constant backing;
- `slice`, `safe_ref`, and `safe_mut` share the runtime `AlderSlice { void *data; uint64_t len; }`; `vec(T)` is exactly `AlderVec { void *data; uint64_t len; uint64_t capacity; }`, with no domain, allocator, reference-count, or ownership field; `table_view`/`table_mut_view` are `void *` pointers to element storage; `raw_ptr(T)` is `void *`; `domain_handle` is `AlderDomain *`; `domain_mark`, `cleanup_id`, and `id(T)` map to their runtime structs; `table(T)` is `AlderTable *`, preserving one mutable table identity through calls, locals, aggregates, and block parameters; `cleanup_scope` is `AlderCleanupScope *` pointing at a per-create-site slot;
- `function(Signature)` maps to an `AlderFnTy<N>` function-pointer typedef; an empty C parameter list is written as `(void)`.

### Values and control flow

- every non-unit MIR value becomes one C variable; block parameters are C variables assigned at every edge before the `goto`. Edge arguments are first captured in typed temporaries and then assigned to parameters, preserving MIR's parallel-copy semantics for swaps and cycles;
- blocks lower to labels (`alder_b<N>`); the entry block needs no label because it has no predecessors; dead blocks keep their code and `unreachable` lowers to `alder_runtime_panic("unreachable")`;
- `return` and typed `fail` both lower to `return <result>;` (the distinction is semantic, for diagnostics); valueless `panic` lowers exactly to `alder_runtime_panic("checked operation failed");`;
- switch dispatches on the tag with `case (uint32_t)<variant index>`; case payload bindings are assigned from the union before the edge assignments.

### Sequencing and side effects

- every MIR instruction lowers to one or more explicit C statements in order; instruction-local temporaries are declared at their use site;
- call arguments are reads of already-computed variables, so the unspecified C evaluation order of function arguments is unobservable;
- every value use is a simple lvalue read; there are no side-effecting expressions.

### Checked operations and failure edges

- 64-bit checked operations call the runtime helper and branch to the MIR failure edge on false;
- narrow non-shift operations promote operands to 64 bits, compute with the helper, range-check the result against the narrow limits, and cast; the narrow operation fails exactly when the promoted computation or the range check fails;
- the total integer overflow method operations never branch to a failure edge. 64-bit `try` forms reuse the existing checked helpers (`alder_i64_add_checked` and siblings returning `Bool` through an out-parameter) to fill the option payload and pick the tag from the helper result. Narrow `try` forms run plain 64-bit arithmetic, which cannot overflow for widened operands, and the range check against the narrow type alone selects between `none` and `some`; each operand is cast to its narrow C type and then to 64 bits before the operation, so the computation itself always runs in 64 bits (a bare narrow cast would let C evaluate i32 subtraction in the operands' promoted 32-bit int width, where `0 - INT32_MIN` is undefined and u32 wraparound silently corrupts the value). 64-bit `sat`/`wrap` forms call the saturating or wrapping runtime helpers directly, and narrow `sat`/`wrap` forms call them on the widened operands before clamping or truncating to the source width;
- narrow shifts check the count against the source width first (unsigned counts only against the width), then compute at that width: unsigned targets wrap by casting, signed left shifts transfer the width-bit two's-complement pattern with `memcpy`, and signed right shifts use unsigned shifting plus explicit sign-bit fill rather than C's implementation-defined signed `>>`;
- failure edges use the same parallel-copy temporaries as ordinary edges before the `goto`;
- a checked failure edge may reach `panic` after all current-function cleanup scopes on that path have been explicitly run and ended; the runtime call does not unwind caller frames;
- `slice.index.checked` lowers to the runtime bounds check, a checked byte-offset multiply, a `SIZE_MAX` representability check, and a one-element `AlderSlice`; `slice.range.checked` lowers to the same checks and `hi - lo` length. `{NULL, 0}` accepts only `[0, 0)` and performs no pointer arithmetic; `{NULL, len>0}` is rejected as malformed;
- the byte-sequence method operations follow the slice shape: `str.byte.checked` is a direct bounds comparison; `str.slice.checked` checks `lo > hi` and `hi > len` before a `memcpy` of the byte range; `str.concat` length-checks the sum with `alder_u64_add_checked` before copying both operands;
- `int.trunc` to an unsigned target wraps by casting; to a signed target it transfers the two's-complement bit pattern with `memcpy`;
- `int.convert.checked` widens the receiver to 64 bits with its own signedness (always a defined conversion), range-checks against the target bounds, and fills the option payload with a defined cast only in range. A signed source into an unsigned target rejects negatives through an explicit `uint64_t` comparison, and for `u64` into `i64` the limit comparison itself stays in `uint64_t` so no limit is narrowed;
- `int.convert.wrap` casts to an unsigned target type; to a signed target it transfers the width-bit two's-complement pattern with `memcpy`;
- `float.convert` from `f64` to `f32` checks NaN, infinity, and `FLT_MAX` bounds before casting; rejected values terminate rather than reaching C11 undefined behavior. `int.from_float` uses the defined runtime conversions; out-of-range or NaN values also terminate because both MIR operations are unchecked.
- the C-boundary conversion operations widen integer crossings to 64 bits with the source's own signedness (always a defined conversion) and then either cast directly (`c.num.wrap`, `c.num.cast`, and total pairs) or range-check into the option (`c.num.try`). A signed source compares `INT64_C(min)` and `INT64_C(max)` in `int64_t` so no negative value wraps before the maximum check; an unsigned target rejects negatives first and compares `UINT64_C(max)` in `uint64_t`; a `uint64_t` source compares the target maximum alone, and an unsigned 64-bit target needs no comparison at all. Static total pairs set the `some` tag and cast without a comparison, because a comparison would be tautological under `-Wtype-limits`;
- float `c.num` pairs cast directly, except `c.num.try` narrowing `f64` to `c_float`: the value is first held in a `double` temporary and compared against `-(double)FLT_MAX` and `(double)FLT_MAX`, so NaN and out-of-range magnitudes yield `none` before any value conversion, and in-range values convert with C11 `double`-to-`float` rounding;
- `c.field.get` and `c.field.set` lower to ordinary C member access through the field's declared C spelling: a read is `value.spelling` and a write is `place.spelling = value;`. The record's C spelling is used unchanged for locals, parameters, results, and members, so a by-value record moves in and out of C calls as the declared `struct S`/`union U` type with no Alder-side copy of the layout;
- `type.size` and `type.align` lower to `(uint64_t)sizeof(T)` and `(uint64_t)_Alignof(T)` over the lowered C spelling of the type operand. `unit` is the one fixed exception: size `0` and alignment `1`, independent of its `uint8_t` storage spelling. No Alder layout engine is added; the target C compiler remains the layout authority;
- `hash.value` lowers to one caller-owned `AlderHashState` initialized from the two key words, a recursive canonical write of the structural value through `alder_hash_write_uint`/`_u64`/`_bytes`, and `alder_hash_finish`. Records write fields in declaration order, enums write a `uint64_t` tag before the selected payload, `Option`/`Result` write a one-byte tag before the payload, and `String`/`Bytes` write a `uint64_t` length before the exact bytes. The runtime implements SipHash-1-3 with unsigned wrapping arithmetic; no padding or pointer value is read;

The C-string ownership operations (98-101) add three runtime helpers in
`runtime/c/alder.h`. `c.string.make_lit` calls `alder_cstring_make_lit`, which
allocates `len + 1` bytes, copies the checker-verified NUL-free text, and
terminates it; `NULL` takes the checked edge. `c.string.make` calls
`alder_cstring_make`, whose status distinguishes an interior NUL (`1`, a
`none` result that is not a failure) from allocation failure (negative, the
checked edge). `c.string.ptr` emits the owner pointer directly and performs no
runtime call, so the borrow adds no allocation or lifetime. `c.string.release`
calls `alder_cstring_release`, which frees the buffer and accepts `NULL`.

A callback-free `using` registration of a `c_string` owner pushes a
compiler-synthesized per-module shell, `__alder_cstring_release_<N>(cstring)`,
whose body is one `c.string.release`; the registration context stores the owner
value and the scope's `run` invokes the shell once. A transfer emits
`cleanup.disarm` on the moved owner's cleanup id before the owner leaves, so the
scope's later `run` skips that single entry while still running the others in
reverse registration order.

The call-scoped buffer borrow (`c.buffer.ptr`, op 107) reads the buffer's
data pointer through the declared C pointer type, so `Bytes`, `AlderBytes`,
and `AlderSlice` values all cross as one pointer for one call. The emitted
statement assigns `<result> = (<P>)<buffer>.data;` and then substitutes
`alder_c_buffer_dummy` when the data pointer is null, because an empty Alder
buffer may be null-backed while C library entry points reject a null pointer
even at zero length. `alder_c_buffer_dummy` is one writable byte exported by
`runtime/c/alder.h`; it is not owned by any Alder value and a callee must not
retain it. The borrow adds no allocation and no cleanup registration.

### Domains, cleanup, and tables

- `domain.create` initializes a hidden per-site `AlderDomain` slot and the handle value points to it; re-creating after destroy re-initializes the same slot, which is sound because the current MIR profile forbids carrying local-domain handles across backedges. Loop-carried local descriptors may name allocations in an external parameter domain only when the function cannot reset or destroy any parameter domain through verified MIR effects; those allocations remain live for the call and do not reuse a hidden domain slot. Unsafe foreign code remains responsible for honoring its wrapper's domain-lifetime contract;
- `domain.mark`/`reset`/`destroy` call the runtime directly; reset and destroy failures are contract violations and terminate;
- `alloc` lowers to a checked count-times-size multiply, a `SIZE_MAX` representability check, `alder_domain_alloc`, and a slice with the count; overflow, non-representability, invalid domains, and out-of-memory terminate;
- `alloc.checked` performs the same preparation and runtime call, but every failure branches through its explicit failure edge with normal parallel edge copies; success constructs the slice;
- `copy_to_domain` is identity only for relocatable copy-trivial values and calls a generated per-type copy helper for storage-bearing values. Helpers recursively deep-copy slice, vector, array, aggregate, and enum children into the destination domain after checking `SIZE_MAX` and rejecting a non-empty null source; Vec capacity normalizes to length. The verifier rejects domain, table, cleanup, raw-pointer, and other identity-bearing resource/capability inputs because C identity assignment cannot establish independent destination provenance;
- `cleanup.scope.begin` initializes a hidden per-site scope slot; `cleanup.push` fills a per-site context struct and registers a generated adapter; `disarm`, `run`, and `end` call the runtime and terminate on contract violations;
- `table.create` allocates a zeroed `AlderTable` header in the owning domain and returns its pointer. The header therefore survives an ordinary callee return, all aliases observe growth, and repeated execution of one create site receives fresh storage; `table.insert`/`lookup`/`lookup_mut`/`remove` call the runtime; lookups build the option view (`tag 1`/`0`) with explicit sequencing; `table.view.end` lowers to a no-op because M2 tables never compact and the verifier enforces view discipline.

### Function values

A function value is a three-word struct `{ code, env, retain }`. `code` takes
the erased parameters plus the trailing opaque `env` pointer. `env` is a
closure environment record for a capturing closure, or the domain the callee's
frame will hang off for a named function value that carries the hidden
storage-model domain. `retain` is the environment's retain hook for a closure
and `NULL` for a named function value.

`copy_to_domain` of a function type is complete: the per-type copy helper
passes `retain = 1` and calls `v.retain(d, v.env)` when both are non-null. The
hook allocates a fresh environment record in the destination domain with
`alder_domain_alloc`, copies the record, rewrites a captured domain handle to
the destination domain, and retains every function-valued capture through its
own hook. Closure captures are storage-free, so the shallow record copy is
complete. Same-domain copies, such as a vector grow, pass `retain = 0` and stay
plain bit copies. A named function value's hook returns the destination
domain, so a value that moves between domains points its future frame at the
domain that owns it.

### Calls and C ABI

- ordinary calls lower to direct calls of the generated static functions, with unit arguments omitted;
- `ffi.call.unsafe` lowers to the import symbol unchanged and parenthesizes it at declaration and call sites so a function-like macro cannot expand; the generated file declares every import prototype so calls are never implicit;
- import names double as C symbols and must be backend-safe C identifiers. The verifier rejects C keywords, leading underscores, generated/runtime prefixes, names ending `_t`, macro-style uppercase names, `main`, and identifiers declared by always-included headers. These are name rules only: retention and cleanup semantics come from an explicit wrapper's audited contract, not from the import name.

### Constants and strings

- scalar constants inline as typed literals (`INT64_MIN` uses the portable `(-9223372036854775807LL - 1)` form; negative zero prints as `-0.0`). Float constants in the static table store the `f64` bit pattern of the value; an `f32` slot narrows that verified-exact pattern to the 32-bit `float` pattern through the host shim at emission, so the generated `UINT32_C` constant always fits and bit-copies to the right value;
- string and bytes constants reference immutable, possibly-unused static numeric byte arrays named by their module constant IDs. Every element is an exact `UINT8_C(N)` value; empty values retain a non-null one-byte backing while exposing length zero. Private bootstrap `slice(u8)` constants retain their legacy mutable backing until M7.3.

### Unchecked failure policy

Unchecked runtime failures (allocation failure, identity exhaustion, rejected float narrowing or float-to-int conversion, `unreachable` execution, and runtime contract violations the verifier already rejects) terminate the process with a fixed message via `alder_runtime_panic`. Checked MIR operations always branch to their explicit failure edge; that edge may return, use typed `fail`, or explicitly clean up and use valueless `panic`.

### Panic hooks

Generated code has two terminating diagnostics. `alder_runtime_panic` is the
runtime's unchecked-failure hook. `c_panic`, declared by the toolchain-owned
`runtime/c/alder_panic.h` shim and used by `core.panic`, flushes all C output,
writes the user-facing `panic: ...` or `panic: assertion failed: ...` line to
standard error, and terminates immediately with status 101. Both hooks use
status 101 and differ in the message they write; `c_panic` additionally flushes
C output first. Neither unwinds caller frames or runs Alder cleanup.

### Documented M3 limitations

- unit-typed function parameters are dropped from the C ABI (semantically exact);
- `fail` and `return` lower identically;
- MIR modules containing unused functions compile because generated statics are marked possibly-unused;
- a MIR interpreter for differential testing is not implemented; the compile-and-run fixtures provide the behavioral evidence.

## Monomorphized Input

The C backend never implements source generics directly. Compile-time `type` parameters are inferred and monomorphized before backend MIR, so every input function, aggregate, table element, and calling convention has a concrete `TypeId` and layout.

Generated C does not receive hidden runtime type arguments merely because the source used generics. Runtime metadata is emitted only for a separate, explicit reflection feature if one is introduced later. Specialized declaration names and ordering must derive from canonical type and function IDs so repeated builds remain deterministic.

## Priorities

In order:

1. preserve defined Alder behavior;
2. avoid C undefined behavior for all safe MIR;
3. generate deterministic output;
4. remain inspectable during semantic debugging;
5. compile on common C11 compilers;
6. optimize only after measurements and semantic tests exist.

## C Dialect

Generated and handwritten runtime code targets C11. Platform-specific extensions may be isolated behind runtime configuration headers, but portable generated code must not require GNU statement expressions, nested functions, or compiler-specific object models.

The initial supported compilers are expected to be recent Clang and GCC. Exact minimum versions will be pinned when executable code exists.

## Evaluation Order

C leaves the order of many subexpressions unspecified. MIR operations with side effects must lower through explicit temporaries and statements.

Alder MIR:

```text
%a = call @left()
%b = call @right()
%sum = int.add.checked %a, %b
```

Generated C must preserve the sequence:

```c
int64_t alder_tmp_a = alder_left();
int64_t alder_tmp_b = alder_right();
int64_t alder_tmp_sum;
if (!alder_i64_add_checked(alder_tmp_a, alder_tmp_b, &alder_tmp_sum)) {
    goto alder_overflow;
}
```

It must not combine these into a C expression whose evaluation order differs from MIR.

## Integer Semantics

Generated C must not use undefined signed overflow to implement Alder arithmetic. The Milestone 2 runtime provides checked 64-bit helpers (`alder_i64_*` and `alder_u64_*` in `runtime/c/alder.h`) for add, sub, mul, div, and the distinct `int.shl.checked` and `int.shr.checked` operations, plus defined float-to-integer conversions. Narrow non-shift MIR integer operations lower by promoting operands to 64 bits, computing with the checked helpers, and range-checking the result against the narrow type; the narrow operation fails exactly when the promoted computation or the range check fails.

Narrow shifts are width-aware and must not be implemented by blindly calling a 64-bit helper followed by a range check. The backend first rejects a count greater than or equal to the source width. Left shift masks the result to that width and reconstructs the signed value from the width-bit two's-complement pattern; unsigned right shift is logical, while signed right shift sign-extends from the source width. For example, `i8(127) shl i8(1)` produces `i8(-2)`, while either `i8` or `u8` shifted by eight takes its checked failure edge.

Shift semantics are defined on the two's-complement bit pattern: left shifts wrap, right shifts are arithmetic for signed values and logical for unsigned. The 64-bit helpers fail on shift counts below zero or at or above 64; narrow lowering applies the source-width check described above. Division fails on division by zero and on `INT64_MIN / -1`.

The total bitwise operations (103-106, `int.and`, `int.or`, `int.xor`, and `int.not`) apply the C operators to the unsigned type of the operand width, `uintN_t`, where every bit pattern is defined. An unsigned result is cast back to its type; a signed result receives the same-width unsigned bit pattern with `memcpy`, so lowering never applies a bitwise operator to a signed C value or relies on an implementation-defined unsigned-to-signed conversion. No runtime helper is needed.

Depending on the final language rule, checked operations lower to:

- the runtime helpers above;
- explicit range checks;
- carefully specified unsigned arithmetic followed by conversion.

The integer overflow method operations (71-79) need no new runtime surface beyond `runtime/c/alder.h`: 64-bit `try` forms reuse the `alder_i64_*_checked`/`alder_u64_*_checked` boolean helpers, 64-bit and narrow `sat`/`wrap` forms call the twelve `alder_i64_*_saturating`/`alder_i64_*_wrapping` and `alder_u64_*_saturating`/`alder_u64_*_wrapping` helpers, and narrow `try` forms compute with plain 64-bit arithmetic plus a range check. The wrapping helpers compute directly on `int64_t`/`uint64_t`, whose overflow behavior is defined, so no undefined signed arithmetic is introduced.

The byte-sequence method operations (80-85) need one new runtime helper, the strict `alder_string_utf8_valid` validator in `runtime/c/alder.h`; everything else reuses the existing surface: `str.len`, `str.byte.checked`, and `str.to_bytes` read the sequence record directly with no runtime call; `str.concat` length-checks with `alder_u64_add_checked`; `str.concat`, `str.slice.checked`, and `str.from_bytes` allocate the fresh bytes with `alder_domain_alloc` and fail only when that returns `NULL`; and `str.from_bytes` validates UTF-8 with the new helper, reporting invalid input as a `none` value instead of taking the failure edge. The owning forms produce `AlderString`/`AlderBytes` records whose data pointer is non-NULL even for an empty result, because a zero-size request allocates one byte.

The byte-view conversion (108, `slice.to_bytes`) likewise needs no runtime helper: the generated code reads the view's length, allocates that many bytes with `alder_domain_alloc`, fails through the checked edge only when the allocation returns `NULL`, copies the view's data with `memcpy` when the length is nonzero, and builds the `AlderBytes` record. The empty view therefore yields the same non-NULL one-byte allocation as every other empty owning sequence.

The ordering comparison operation (95, `str.order_lt`) needs no runtime surface: the generator emits `alder_string_lt`/`alder_bytes_lt` as static helpers next to the existing `alder_string_eq`/`alder_bytes_eq` when a program uses them, walking the common prefix bytewise and breaking ties by length, so the shorter prefix orders first and an empty operand orders before every non-empty one.

The display operation (98, `str.display`) likewise needs no runtime surface: the generator emits `alder_string_from_i64`/`alder_string_from_u64`/`alder_string_from_bool` as static helpers when a program uses it, rendering decimal text into a domain-allocated string; the integer forms return a `NULL`-data string on allocation failure so the instruction's checked edge fires, and the `Bool` form returns static text and cannot fail.

The backend must also define lowering for:

- division by zero;
- minimum signed value divided by `-1`;
- shifts greater than or equal to bit width;
- narrowing conversions;
- float-to-integer conversions outside the destination range.

No optimization may assume a checked failure is impossible unless a MIR proof or canonical optimization removed the check first.

## Float Semantics

`F32` and `F64` follow IEEE 754 binary32 and binary64 in the default non-stop
mode (decision D026). Comparisons lower to C's IEEE operators, so NaN is
unordered with every operand, the two zeros compare equal, and no failure
edge exists. Arithmetic never traps: overflow produces the signed infinity,
underflow is gradual, and division by zero is defined at the language and MIR
level.

ISO C11 leaves float division by zero undefined; Annex F defines it only
where `__STDC_IEC_559__` is defined, and tier-1 toolchains such as Apple
clang do not reliably define that macro. Generated code therefore never emits
a bare float division: `float.div` calls the runtime helpers
`alder_f64_div`/`alder_f32_div`, which branch on the divisor and return the
IEEE quotient — the signed infinity carrying the XOR of the operand signs, or
NaN when the dividend is zero or NaN — and perform the plain, defined
division only for a nonzero divisor. No signal is raised and no failure edge
is taken; `float.add`, `float.sub`, and `float.mul` lower to plain C
arithmetic, which is defined for every operand pair.

Floating-point contraction is disabled in every generated program. The
prelude emits `#pragma STDC FP_CONTRACT OFF`; because GCC does not implement
that pragma and rejects it under `-Wunknown-pragmas` (an error in the strict
warning set) even when `-ffp-contract=off` is passed, the pragma is preceded
by a GCC-only block that ignores `-Wunknown-pragmas`. Clang implements the
pragma. The compiler's own strict build flags additionally keep
`-ffp-contract=off`, so GCC builds get the no-contraction guarantee from the
flag while user builds get it from the pragma. The backend makes no
flush-to-zero assumption and does not change the rounding mode.

## Pointers, Aliasing, and Alignment

Safe MIR references are not arbitrary C pointers. Their lowering must preserve:

- valid lifetime;
- required bounds;
- alignment;
- mutability and view constraints;
- provenance assumptions required by the selected C compilers.

Rules:

- do not perform out-of-object pointer arithmetic merely to compare or cache an address;
- do not cast and dereference a pointer at a stricter alignment than the source guarantees;
- do not type-pun through incompatible lvalues;
- use `memcpy` for unaligned or representation-preserving transfers where necessary;
- do not emit `restrict` until MIR proves the required non-aliasing contract;
- keep raw foreign pointers distinct from safe references in generated helper APIs.

These rules are written to stay valid under the provenance model of ISO/IEC
TS 6010 and on capability hardware such as CHERI, where a pointer cannot be
recreated from an integer or moved outside its object. Future C exports of
slices may add Clang `__counted_by` annotations as an option; generated code
does not depend on `-fbounds-safety`, which is not yet available in upstream
Clang.

## Bounds Checks

Slice indexing lowers to an explicit check before address calculation:

```c
if (index >= slice.len) {
    goto alder_bounds_failure;
}
value = slice.data[index];
```

The backend must avoid performing invalid pointer arithmetic before the check. A check may disappear only when an earlier MIR pass has proved and removed it.

## Storage Domains

The Milestone 2 runtime ABI is pinned in `runtime/c/alder.h`; the detailed
contracts below are the canonical reference.

```c
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct AlderDomain AlderDomain;   /* layout is ABI, fields internal */
typedef struct {
    uint64_t domain_serial;
    uint64_t reset_epoch;
    uint64_t segment_serial;
    size_t offset;
} AlderDomainMark;

bool alder_domain_init(AlderDomain *domain, AlderDomain *parent);
void *alder_domain_alloc(AlderDomain *domain, size_t size, size_t align);
AlderDomainMark alder_domain_mark(AlderDomain *domain);
bool alder_domain_reset(AlderDomain *domain, AlderDomainMark mark);
void alder_domain_destroy(AlderDomain *domain);
size_t alder_runtime_live_allocations(void);
```

Failure contracts:

- `alder_domain_init` returns false for a double init, an uninitialized or
destroyed parent, or exhausted process-wide domain identities; the struct must
be zero-initialized or freshly destroyed;
- `alder_domain_alloc` returns NULL when the domain is not initialized, the
alignment is not a power of two (or zero), size plus alignment slack
overflows `size_t`, memory is exhausted, or stable segment identities are
exhausted. A zero size allocates one byte;
- `alder_domain_reset` returns false for a destroyed domain, an exhausted reset
epoch, a mark from another domain or an earlier reset epoch, a segment identity
that is no longer active, or an offset past the segment frontier;
- `alder_domain_destroy` is a no-op on uninitialized or already-destroyed
domains; destroying a parent recursively destroys its children.

Lifetime contracts:

- domain structs are caller-owned; the runtime never frees them;
- a child domain cannot outlive its parent: destroying the parent destroys
children first, so any later child destroy is a no-op;
- allocations stay valid until the domain is reset past them or destroyed;
- a mark made before the first allocation can reset a non-empty domain back to
empty;
- reset releases every segment after the marked one; pointers into released
storage become invalid, and the MIR verifier prevents their use;
- every successful reset consumes every mark from the previous domain epoch;
marks use stable integer identities rather than pointers into segment storage,
so released storage is never retained or compared through a stale pointer.

Implementation policy: domains and segments receive non-reusing process-wide
identities; namespace exhaustion is a permanent allocation failure rather than
wraparound. Segments are single heap blocks (header plus a 16-aligned data
area); allocations bump with per-allocation alignment; regular segments double
up to 1 MiB; larger requests receive a dedicated exact-size segment. The
runtime tracks its live heap blocks in one counter so tests can prove leak-free
create/reset/destroy cycles without a leak sanitizer.

Runtime test builds may define `ALDER_RUNTIME_TESTING` to expose deterministic
domain-allocation failure and segment-identity exhaustion injection. The
allocation hook counts otherwise eligible `alder_domain_alloc` calls and fails
before mutating domain state; identity exhaustion is irreversible within its
isolated test process. Production builds contain neither the hook symbols nor
their mutable state.

## Cleanup Lowering

MIR cleanup scopes lower to explicit, visible control flow. The runtime side
(`AlderCleanupScope`, `alder_cleanup_scope_begin/push/disarm/run/end` in
`runtime/c/alder.h`) owns the entry list: pushes register a function pointer
and context, `run` executes armed entries in reverse registration order,
each exactly once, and `end` frees every entry. `end` returns false (and
still releases entries) when the scope was not run or still has armed
entries; the MIR verifier requires run before end on every exit path, so
that state is a contract violation.

The resumable frame-resident variant also provides
`alder_cleanup_scope_begin_adopting`, `alder_cleanup_push_step`, and
`alder_cleanup_scope_next`/`_next_step`; it keeps the same entry list,
reverse order, and `alder_cleanup_end` rules. A step entry stores a generated
driver thunk instead of a synchronous function pointer and is run through the
cursor protocol in
[Frame-resident cleanup cursors](#frame-resident-cleanup-cursors).

Generated C must guarantee reverse order and at-most-once cleanup. C `goto`
is a backend mechanism and does not appear in MIR semantics.

## Generational Tables

The Milestone 2 ABI is `AlderTable` plus `AlderTableId { table_serial, slot,
generation }` and `alder_table_init/insert/lookup/lookup_mut/remove` in
`runtime/c/alder.h`. The table serial comes from a non-wrapping global counter,
so an id never resolves against an unrelated table even when a fresh table
reuses the same address; exhaustion permanently fails later initialization.
Slot generations likewise fail before wraparound, so a removed slot never
reuses a generation and stale ids cannot resolve to a replacement object.
Initialization validates `size_t` representability and publishes the caller's
table struct only after all fallible work succeeds.

Lookup performs, in order:

1. table identity validation (serial match, live domain);
2. slot bounds validation;
3. occupancy validation;
4. generation comparison;
5. creation of a scoped view (a pointer to the element storage).

`table.insert.try` calls the same `alder_table_insert` but turns its `false`
return into the `err` payload of the MIR `result(id(T), T)` value instead of a
panic; the `ok` payload receives the fresh id. The element value is written
into the result unchanged, so the caller keeps the value it passed.

Under `ALDER_RUNTIME_TESTING`, the runtime additionally exposes
`alder_runtime_test_set_table_slot_limit(uint64_t slots)`: a process-wide
test/diagnostic hook that refuses table growth past `slots` slot-array
entries, so insertion into a full table fails deterministically (and
`try_insert` returns its error payload). The default of zero means unlimited
shipped behavior. The hook is not part of the language surface: Alder source
cannot reach it, generated code never calls it, and production builds expose
neither the symbol nor its state.

Element storage and the slot array are allocated from the table's domain;
removal marks the slot empty but leaves element storage in the domain until
reset or destroy. Inserting a storage-bearing element deep-copies it into
the table's domain (`alder_copy_tyN(table->domain, elem, 1)`) before its
slot bytes are stored: the element may have been built in the inserting
function's hidden caller-result domain, which is released at return, so the
slot must own storage tied to the table's domain rather than alias the
caller's. A source that is dead after the insert transfers its storage
instead (the copy-site elision D023 already applies to the element read).
The copy follows the `copy_to_domain` termination contract on allocation
exhaustion; only the insert's own slot-storage allocation reports failure
back to the caller (`false`, the `try_insert` `Err` payload).
Every successful domain reset changes the domain epoch and
invalidates all of its existing tables; the current MIR profile enforces this conservatively
because inserts and slot growth contain hidden runtime allocations. M2 tables
never compact, so a view stays valid memory until the domain releases it.
`table.view.end` lowers to nothing in M2; the verifier enforces view discipline.
Compaction may update slot-to-storage mappings while preserving IDs; it must
not run while an incompatible view is active, and it is deferred.

## C Interoperability

Generated C that has at least one binding block selects the hosted C library surface before any include: `_DEFAULT_SOURCE` on Linux and `_DARWIN_C_SOURCE` on Darwin, when the build has not already selected them. These are the platform macros that expose the POSIX.1-2008 declarations plus the non-strict extensions (`realpath`, `getrandom`, `getentropy`, `st_mtim`) that binding shims rely on; `_POSIX_C_SOURCE` alone would hide them. The hosted binding surface (`std.io`, `std.env`, and the runtime shims) depends on the POSIX.1-2008 C library declarations, and a feature-test macro must precede every libc header. A program with no binding blocks is pure Alder code and keeps the default C11 surface with byte-identical output. Binding headers are included before the program headers (`alder.h`, `<float.h>`, `<string.h>`) so a binding header may select its own feature-test macros; the generated binding checks follow the headers with `<stddef.h>` available. The interim define moves into the versioned build plan once the build driver owns native defines.

Imported headers may be included directly in generated C or accessed through generated C shims. The chosen strategy must preserve target ABI without allowing C declarations to leak into MIR semantics.

The backend must distinguish:

- a pointer valid only for the duration of the call;
- a pointer that C may retain;
- memory returned by C with a required release function;
- nullable C pointers;
- C strings and pointer-plus-length buffers;
- callbacks whose lifetime extends beyond the initiating call.

Only explicit `ffi.call.unsafe` MIR operations may invoke arbitrary imported functions.

## Deterministic Output

Generated C must be independent of:

- host memory addresses;
- Go map iteration order;
- absolute checkout paths;
- thread scheduling;
- temporary filenames;
- nondeterministic hash seeds.

Declarations should use stable ID or source order, with deterministic tie-breaking. Generated names should be based on stable module, symbol, and numeric IDs.

An `--emit-c` mode should produce readable output suitable for review. Readability is secondary to correctness but is an important bootstrap diagnostic tool.

## Testing Strategy

The backend requires:

- generated-C golden tests;
- compile-only tests under strict warnings;
- compile-and-run behavior tests;
- ASan and UBSan runs where available;
- boundary tests for every checked arithmetic operation;
- stale-ID and table-compaction tests;
- cleanup tests for success and each failure edge;
- C FFI fixtures covering temporary, retained, nullable, and externally freed pointers;
- deterministic-output tests across repeated processes.

When a MIR interpreter exists, generated C should be differentially tested against it. The interpreter is optional until evidence shows that it materially improves semantic validation.

The source-bootstrap build compiles the four split stage-0 translation units of `bootstrap/alder.c` with plain `-Wno-uninitialized` on GCC: jump threading reports the tag-guarded payload reads of one aggregate local (through `offsetof`) as definitely uninitialized, although MIR phase verification already proves definite initialization of the generated code, so the warning duplicates a check the verifier owns; the host shim and the runtime stay under the full strict set.

## Explicitly Deferred

- LLVM IR generation;
- target-specific vector intrinsics beyond isolated runtime helpers;
- exception unwinding integration;
- link-time optimization orchestration;
- direct object-file emission;
- debug metadata beyond practical `#line` support;
- aggressive C source optimization.
