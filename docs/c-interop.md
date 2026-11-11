# Alder C Interoperability

Design status: **Frozen for Alder 1.0**

Availability: **S0 supports only direct primitive/pointer symbol imports; Milestone 8 is installing the binding model: binding blocks, raw types, raw fn, unsafe calls, `c.is_null`, probe emission, the errno/strerror shims, the checked scalar conversions, by-value verified records, `unsafe c` field access, `c.CString` ownership, and call-scoped buffer borrows are checked end to end, while exports, general ownership/retention wrappers, callbacks, and explicit shims are not implemented yet**

Alder treats C as an explicit trusted boundary. C headers remain authoritative
for spelling and ABI. Alder binding descriptions provide the exact type names
and declarations needed for checking and deterministic code generation. Safe
wrappers provide nullability, bounds, ownership, initialization, callback, and
threading semantics that a C header cannot express.

## Safety claim

Verified safe Alder and generated C must not themselves execute C undefined
behavior. This includes sequencing, integer operations, shifts, conversions,
bounds, null checks, alignment, aliasing, initialization, and lifetime.

The guarantee is conditional on trusted components:

- an `unsafe c` block obeys every foreign precondition;
- its binding description matches the selected header and ABI;
- retained-pointer, ownership, callback, and threading claims are true;
- linked C/C++ code does not violate the safe wrapper's assumptions;
- native build recipes and toolchains produce the declared artifacts.

An incorrect unsafe wrapper can invalidate safety. Its callers remain ordinary
safe code; unsafety is localized to the wrapper implementation and binding,
not inferred onto every caller.

## Binding blocks

C declarations live in a module-level header binding:

```alder
import c "stdio.h" as stdio {
    opaque type File = "FILE"

    raw fn open = "fopen"(
        path: c.ConstPtr(c.Char),
        mode: c.ConstPtr(c.Char),
    ) -> c.Ptr(File)

    raw fn close = "fclose"(file: c.Ptr(File)) -> c.Int
}
```

The header path is logical and resolved only through target sysroot and locked
native include roots. It cannot be an arbitrary ambient absolute path in a
frozen build.

An Alder name maps to an explicit C spelling string. If the string is omitted,
the names must match. The binding can describe:

- C scalar typedefs and enums with verified underlying representation;
- opaque typedef, `struct`, and `union` names used behind pointers;
- non-bitfield records with named fields and C spelling mappings;
- fixed-size arrays and function-pointer callback types;
- functions and object-like constants;
- calling convention and link-library identity from the build plan.

Example record description:

```alder
import c "time.h" as ctime {
    scalar type Time = "time_t"

    record type Timespec = "struct timespec" {
        seconds: Time = "tv_sec"
        nanos: c.Long = "tv_nsec"
    }

    raw fn get = "timespec_get"(
        value: c.Ptr(Timespec),
        base: c.Int,
    ) -> c.Int
}
```

The generated binding-check translation unit includes the real header and
uses C11 compile-time checks or typed probes for size, alignment, field offset,
field type, function type, and constants. A mismatch is a binding diagnostic,
not a warning or silently generated alternate declaration.

Binding blocks do not themselves claim a function is safe, nonblocking,
thread-safe, nonnull, borrowing, retaining, or ownership-transferring. Those
are semantic properties of the ordinary Alder wrapper and any explicit
foreign-owner/callback helper it uses.

## C types

`std.c` supplies target-ABI types distinct from Alder numerics:

```text
c.Char, c.SChar, c.UChar
c.Short, c.UShort, c.Int, c.UInt
c.Long, c.ULong, c.LongLong, c.ULongLong
c.Float, c.Double, c.Size, c.Ptrdiff
c.Ptr(T), c.ConstPtr(T)
```

`c.Char` preserves target C char behavior and is not Alder `U8`. `c.Long` and
`c.Size` are target-dependent foreign types and are not permitted as ordinary
portable collection indices. Conversion to an Alder exact-width type is
explicit and checked.

`c.Ptr(T)` and `c.ConstPtr(T)` are nullable raw pointer tokens. Their mere
existence does not prove alignment, initialization, provenance, length,
uniqueness, lifetime, or ownership. Raw pointer arithmetic, dereference,
pointer-to-pointer comparison, conversion, and C calls require `unsafe c`.
`c.is_null(pointer) -> Bool` is the sole safe observation because it neither
dereferences the pointer nor asserts a foreign lifetime.

Safe wrappers convert validated foreign data into:

- `Option` for nullability;
- `[T]`/`MutSlice(T)` for checked call-scoped buffers;
- `String` after UTF-8 validation;
- `Bytes` for arbitrary owned bytes;
- an affine owner for a handle requiring one release;
- a scoped capability for a foreign borrow.

## Unsafe calls

```alder
fn open(path: Path) -> Result(File, IoError) {
    using path_text = try c.CString(path.to_string())
    using mode = c.CString("rb")

    let raw = unsafe c {
        stdio.open(path_text.ptr(), mode.ptr())
    }

    if c.is_null(raw) {
        return Err(IoError.last())
    }

    return Ok(unsafe c { File(raw: raw) })
}
```

An `unsafe c` expression contains one root foreign call or raw operation;
ordinary argument expressions are evaluated first in Alder's left-to-right
order. Complex wrappers use several small unsafe expressions rather than one
unbounded unsafe region. Alder still checks syntax, ordinary types, control
flow, and the declared ABI.

The callee names a `raw fn` member either bare, when exactly one block in the
module declares that member name, or qualified as `alias.member`, when the
block alias disambiguates. Arguments must have exactly the declared raw C
type; ordinary Alder values and literals are rejected until the explicit
checked conversions exist. A call whose result type is `Unit` may appear in
statement position; any other binding call result must be used, because
dropping it would silently discard the C value. `c.is_null(pointer)` is
checked outside `unsafe c` as well: it is a pure observation, not a raw
operation.

Raw pointers may be stored only in binding/wrapper records whose fields remain
module-private and whose construction from a raw pointer is itself an unsafe
root operation, as above. Implementing `Cleanup` makes an owned wrapper affine.
Such records cannot accidentally gain structural equality, hashing,
task-transfer safety, or ordinary dereference from a raw pointer field.

## Scalar conversions

Crossing between `c.*` scalars and Alder numerics is explicit and named. Each
direction offers up to three forms per pair:

- `to_T()` is total: the pair is lossless on every target, so bare calls are
  accepted and cannot fail;
- `to_T_checked() -> Option(T)` yields `some` when the receiver value fits
  `T` and `none` otherwise;
- `to_T_wrapping()` truncates on the two's-complement pattern, keeping the
  low bits of the receiver; offered for integer pairs only, never floats.

On `c.Char`, `c.SChar`, `c.UChar`, `c.Short`, `c.UShort`, `c.Int`, `c.UInt`,
`c.Long`, `c.ULong`, `c.LongLong`, `c.ULongLong`, `c.Size`, and `c.Ptrdiff`
receivers, the integer targets are Alder `I8` through `I64` and `U8` through
`U64`: `to_i8` .. `to_u64` in all three forms, with the total form accepted
only where the pair is lossless on every target. `c.Size` and `c.Ptrdiff`
participate at their target widths; `c.Char` participates at the target's
`char` width and signedness, so its checked forms decide per target and a
program must not assume `c.Char` behaves like `U8` or `I8`.

Reading floats from C is by value-preserving total forms: `c.Float.to_f32()`,
`c.Double.to_f64()`, and the widening `c.Float.to_f64()`. Narrowing `F64`
into `c.Float` exists as `to_c_float_checked() -> Option(c.Float)`, which
yields `none` for NaN, infinities, and magnitudes beyond `float`'s range by
comparing in `double` against `float`'s limits before any value conversion.
In-range values convert with C11 `double`-to-`float` rounding. `F32` has no
checked narrowing into `c.Float` because the widths are equal; `to_c_float()`
is total both ways. `F64.to_c_double()` is total. Float comparison and float
arithmetic are outside the S0/MIR profile while their NaN, division-by-zero,
and signed-zero semantics await a design decision, so wrappers currently
observe float values through the checked narrowing's `some`/`none` or through
integer projections, not through `==`.

Writing Alder integers into C integer scalars is the mirror surface:
`to_c_char`, `to_c_schar`, `to_c_uchar`, `to_c_short`, `to_c_ushort`,
`to_c_int`, `to_c_uint`, `to_c_long`, `to_c_ulong`, `to_c_longlong`,
`to_c_ulonglong`, `to_c_size`, `to_c_ptrdiff`, each in the same three forms
subject to the same totality rule at the target's width and signedness.
`c.Float`/`c.Double` receivers also expose the float targets above.

These calls lower to MIR's C-boundary conversion operations (`c.num.try`,
`c.num.wrap`, `c.num.cast`), which verify endpoint worlds and classes; the C
backend widens integers with their own signedness before comparing and emits
no comparison where the pair is total. A call naming none of these methods on
a `c.*` or numeric receiver is rejected with diagnostic 205 ("no such C
conversion method on this receiver"). Rust-style `as` casts do not exist; the
checked and wrapping forms are the only lossy spellings.

## Ownership and retention

Every safe wrapper must classify pointer lifetime as one of:

- borrowed only for the call;
- scoped borrow tied to an affine foreign owner;
- C-retained borrow with an explicit registration owner;
- returned owned allocation with exactly one release operation;
- shared immutable foreign storage with an explicit audited owner;
- copied into an Alder value before the call or owner ends.

Passing a slice or string to a C function that may retain its pointer is never
safe by default. The wrapper copies to foreign-owned storage, pins it with an
explicit affine owner, or remains unsafe. Releasing foreign memory consumes its
owner; cleanup cannot run twice.

C aliasing declarations do not automatically create safe Alder mutable views.
At most one mutable view may be active, and unknown foreign mutation ends or
invalidates any incompatible safe capability.

## C strings

`c.CString` builds a NUL-terminated foreign buffer from Alder text and returns
an affine owner with exactly one release:

```alder
fn mode_length() -> U64 {
    using mode = c.CString("rb")
    let n = unsafe c { cstr.length(mode.ptr()) }
    return n.to_u64()
}

fn open_owned(text: String) -> Option(c.CString) {
    using path = try c.CString(text)
    return Some(path)
}
```

The constructor has two forms. A string literal is copied infallibly: the
checker decodes the literal, rejects an interior NUL byte at compile time
(diagnostic 210), and the runtime copy can fail only when allocation fails,
which takes the checked edge. Any other `String` or `Bytes` value produces
`Option(c.CString)`: an interior NUL yields `none`, allocation failure takes
the checked edge, and `try`/`match` consume the option. The `Bytes` form
copies exact bytes without a UTF-8 requirement, which paths, environment
strings, and argv need; a `Bytes` literal may therefore carry non-UTF-8
bytes. A wrong argument count or an argument that is neither `String` nor
`Bytes` is rejected with diagnostics 211 and 212.

The owner is affine and never a copyable value. A `using` registration
releases it exactly once at scope exit, and `owner.ptr()` borrows the buffer
as `c.ConstPtr(c.Char)` without consuming the owner, so several foreign calls
may borrow the same buffer in sequence. Transferring the owner out of its
scope — a plain return, an `Option`/`Result`/record/array construction, a
`take` parameter, or a match scrutinee — disarms that registration before the
owner leaves, and the receiving scope or aggregate owns the single release.
No path releases a transferred buffer, and a program cannot spell the release
operation directly.

The permanent `String`/`Bytes` lifetimes are unchanged: conversion into a
CString is a copy, and the CString does not borrow the source text.

## Strings and buffers

Inside `unsafe c`, a `Bytes`, `[U8]`, or `MutSlice(U8)` argument may be passed
for a raw fn parameter declared `c.ConstPtr(T)` or `c.Ptr(T)`, where `T` is
`c.Char`, `c.SChar`, `c.UChar`, or an opaque bound type:

```alder
let n = unsafe c { posix.read(fd, buffer, buffer.len().to_c_size()) }
```

The argument is a call-scoped borrow: the pointer is valid only for that one
call, the buffer is not moved or copied, and no pointer value can be stored in
an Alder binding. `Bytes` and `[U8]` satisfy only `c.ConstPtr(T)`;
`MutSlice(U8)` satisfies either form. The same buffer may not be borrowed
mutably more than once in one call. Passing an empty buffer still passes a
valid address: when the data pointer is null, the generated code substitutes
the runtime's writable one-byte dummy, because C library entry points such as
`memcpy` and `read` reject or misuse a null pointer even at length zero.

The length argument is the caller's responsibility inside the `unsafe c`
block; the compiler does not infer it from the borrowed buffer. A callee that
retains the pointer is never safe with this form: the wrapper must copy to
foreign-owned storage, pin the buffer with an explicit affine owner, or use
`c.CString`. Slices and strings have no implicit C representation outside this
borrow.

Pointer-plus-length APIs use a checked conversion from `U64` to `c.Size`,
reject nonrepresentable lengths, and preserve the backing value for the
complete call/retention lifetime.

A returned pointer/length pair is validated for null/zero consistency,
representable length, alignment, readable initialization, and ownership before
becoming a slice or value. UTF-8 conversion is separately fallible.

No safe API computes an out-of-object C pointer, dereferences one-past-end,
forms an invalid typed lvalue, or relies on unaligned typed access. Wrappers use
byte operations or generated `memcpy` shims where C alias/alignment rules
require them.

## C records, unions, bitfields, and variadics

By-value C records are supported only through a verified record binding. The
system C compiler remains the layout authority. Alder does not reproduce ABI
packing algorithms independently.

- ordinary non-bitfield fields may be read/written in `unsafe c` through the
  verified binding. A read `unsafe c { rec.field }` requires a local binding
  holding that record's value and yields the field's declared binding type; a
  write `unsafe c { rec.field = value }` additionally requires a `var`
  binding and a value whose type matches the field's declared binding type
  exactly, and yields `Unit`. The receiver must be a single-word local name:
  parameters and nested selectors are rejected because the write targets that
  local's place. A scalar or opaque member binding is not a field receiver;
- raw fn signatures move complete records by value in both directions, and
  the generated C uses the declared record spelling directly, so a C callee
  that returns or takes `struct S` round-trips through Alder locals;
- unions are opaque in safe code; a wrapper selects and validates the active
  member;
- bitfields and flexible array members require a C shim with ordinary getter,
  setter, or buffer functions;
- packed or unusually aligned records require shim access and cannot become an
  ordinary Alder record;
- C complex, vector extensions, compiler attributes, and target-specific
  calling conventions require explicit target support or a shim.

Variadic C calls are not directly expressible as safe Alder calls. A fixed C
shim is required, except for toolchain-owned audited wrappers of a closed set
of promotable scalar arguments. `printf`-style formatting is provided by
`std.format`, not exposed as a safe variadic import.

Alder 1.0 has no C++ ABI binding. xmake may build C++ dependencies, but Alder
consumes them only through a project or package-owned `extern "C"` shim with the
same checked C binding contract. Exceptions, templates, overloads, member
pointers, and C++ object lifetime never cross that shim directly.

Function-like macros and inline functions are imported through an explicit C
shim because they have no stable link symbol. Object-like constants may be
checked by the binding probe when their value and type are representable.

## Callbacks and C calling Alder

Nonretained callbacks use a verified C function-pointer type plus explicit
context pointer. A generated static trampoline checks/decodes the context and
enters the Alder runtime. The callback cannot retain a scoped Alder value or
propagate an Alder `Result` through an incompatible C signature.

A callback retained after the initiating call requires an affine
`c.CallbackOwner` containing the registration, context storage, target
function, thread/cancellation contract, and unregister/release operation. Its
cleanup unregisters and waits for in-flight callbacks when the C API promises a
usable synchronization mechanism. Without such a promise the wrapper remains
unsafe.

Intentional C exports use explicit syntax:

```alder
export c fn alder_process(
    data: c.ConstPtr(c.UChar),
    length: c.Size,
) -> c.Int {
    // validate, convert, and call safe Alder code
}
```

Only C ABI types and verified bound records appear in an export signature.
An export catches no invariant panic; process termination is the only portable
panic behavior across C. The generated header and symbol name are deterministic.
Thread entry and runtime initialization are supplied by the host bridge.

## Concurrency and thread safety

A raw binding carries no inferred thread-safety or nonblocking promise. A safe
wrapper decides whether it:

- is short and callable on an executor worker;
- takes an I/O capability, so it is potentially suspending;
- must use the bounded blocking pool;
- is restricted to the local executor/thread;
- may be transferred between tasks;
- invokes callbacks from foreign threads.

Arbitrary executing C cannot be safely interrupted. Cancellation keeps wrapper
state alive until C returns or the documented C cancellation/join protocol
completes. See [Async and Structured Concurrency](async.md).

## Toolchain-owned shims

A few hosted operations cannot be spelled as a `raw fn` binding against real
headers. `errno` is a thread-local modifiable lvalue (usually a macro), so no
binding block can read it; `strerror` belongs to the same hosted-OS surface.
The runtime ships an audited shim header for exactly these operations:

```c
/* runtime/c/alder_errno.h */
static inline int c_errno(void) { return errno; }
static inline const char *c_strerror(int number) { return strerror(number); }
```

Wrapper modules bind the shim like any other header, e.g.
`import c "alder_errno.h" as cerrno { raw fn last = "c_errno"() -> c.Int }`,
and the generated probe unit pins the shim signatures through the same
`_Static_assert` evidence as user bindings. The shims are the whole surface of
that header. Both definitions are `static inline`: including the header never
adds an exported symbol to a program, so a user C library cannot collide with
them at link time, and every including translation unit gets its own copy.
Their C names stay outside the `alder_` runtime prefix because the binding
spelling policy reserves that prefix, and the policy has no exceptions.
Reading the errno value's integer into Alder requires the explicit checked
conversions between `c.*` scalars and Alder numerics.

The `core.panic` module uses a second toolchain-owned shim,
`runtime/c/alder_panic.h`. Its `c_panic(const char *)` flushes every C output
stream, writes the user panic diagnostic to standard error, and aborts. Like
the errno shim it is a fixed audited header, not a general user shim surface;
`core.panic` binds it through an ordinary `import c` block and never exposes
the runtime's reserved `alder_` names to source.

## Native linking and tooling

Headers, defines, libraries, C shims, target, and toolchain come from the
versioned Alder build plan. The include roots for a binding are exactly the
build plan's explicit `-I` roots (fixture roots in tests, locked native or
sysroot roots in production) plus the target toolchain's own C11 and libc
headers, such as `stddef.h`, `time.h`, and `stdio.h` from the target sysroot.
The compiler never adds a search path of its own and never reads an ambient
include or library directory.

Binding verification is not a separate step that a build could skip: the
generated program translation unit itself carries the binding evidence.
Every binding block emits its header `#include` inside the program TU,
followed by C11 `_Static_assert` checks that pin each declared member to the
header's real declaration: record size with `_Static_assert(sizeof(...) == ...,
"binding member: ...")`, alignment with `_Alignof`, field offsets with
`offsetof`, field and function types with `_Generic` selection on the field
or function-pointer type, and constant values with `_Static_assert(NAME ==
...)`. Every assertion message names the Alder binding member, so a mismatch
against the real header is a compile error of the generated program, never a
warning and never a silently generated alternate declaration. `alder bind
check` may later expose the same probes as a standalone emit=bind translation
unit, but it is tooling around the same evidence, not the gate itself.

xmake/xrepo may supply a locked native package but does not alter the binding
semantics. A system native dependency is explicitly nonreproducible unless its
artifacts are pinned. See [Modules and Builds](modules-and-builds.md).

## Required rejection and runtime evidence

The 1.0 C gate includes:

- scalar width/signedness and function signature mismatch rejection;
- record size/alignment/offset and calling-convention checks per target;
- null, zero/nonzero length, alignment, and integer-conversion boundaries;
- borrowed versus retained buffers and exactly-once foreign release;
- callback unregister, in-flight callback, foreign-thread, and cancellation
  races;
- shim coverage for macros, bitfields, unions, flexible arrays, and variadics;
- C-to-Alder export reentry and malformed inputs;
- strict warnings, sanitizers, static analysis, and deterministic generated
  binding code.

Wrappers over C libraries may additionally be tested with a memory-safe C
implementation such as Fil-C as an optional lane; it is a debugging aid, not a
supported toolchain.

S0's `import c name: fn(...)` and single direct call are a narrow bootstrap
bridge and do not establish this complete contract. Since M8 that bridge is
private to the compiler's bootstrap sources: ordinary modules reject it with
the stable bootstrap-private diagnostic and declare C surface through header
binding blocks.
