# Alder C Interoperability

Design status: **Frozen for Alder 1.0**

Availability: **S0 supports only direct primitive/pointer symbol imports; the 1.0 binding model is not implemented**

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

Raw pointers may be stored only in binding/wrapper records whose fields remain
module-private and whose construction from a raw pointer is itself an unsafe
root operation, as above. Implementing `Cleanup` makes an owned wrapper affine.
Such records cannot accidentally gain structural equality, hashing,
task-transfer safety, or ordinary dereference from a raw pointer field.

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

## Strings and buffers

C strings use `c.CString`, which validates absence of interior NUL and owns a
terminating byte. Pointer-plus-length APIs use a checked conversion from
`U64` to `c.Size`, reject nonrepresentable lengths, and preserve the backing
value for the complete call/retention lifetime.

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
  verified binding;
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

## Async and thread safety

A raw binding carries no inferred thread-safety or nonblocking promise. A safe
wrapper decides whether it:

- is short and callable on an executor worker;
- must use the bounded blocking pool;
- is restricted to the local executor/thread;
- may be transferred between tasks;
- invokes callbacks from foreign threads.

Arbitrary executing C cannot be safely interrupted. Cancellation keeps wrapper
state alive until C returns or the documented C cancellation/join protocol
completes. See [Async and Structured Concurrency](async.md).

## Native linking and tooling

Headers, defines, libraries, C shims, target, and toolchain come from the
versioned Alder build plan. `alder bind check` validates every binding against
that plan. The compiler never searches ambient include/library directories on
its own.

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

S0's `import c name: fn(...)` and single direct call are a narrow bootstrap
bridge and do not establish this complete contract.
