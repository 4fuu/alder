# Alder Modules, Packages, and Builds

Design status: **Frozen for Alder 1.0**

Availability: **Milestone 6 local modules and deterministic local builds are implemented; package fetching, native providers, and later 1.0 tooling remain gated**

The implemented Milestone 6 slice covers one local package, `bin` and `lib`
targets, `debug` and `release` profiles, the current host triple, exact-import
source closure, and project `check`, `build`, `run`, and versioned `test-plan`
construction. It deliberately rejects workspace/dependency/lockfile and native
provider sections, custom profiles, cross compilation, and later CLI surfaces;
those remain owned by Milestones 7–13. Explicit `.al` arguments retain the S0
global-source compatibility mode.

This document defines one deterministic project model from source import to
native link. Language modules, Alder packages, and native C/C++ providers are
separate layers.

## Files and modules

Each `.al` source file defines exactly one module and begins with its required
module declaration:

```alder
module acme.compiler.parser

import acme.compiler.token
import acme.compiler.syntax as syntax
import std.collection { Deque }
```

A package owns one root namespace equal to its manifest package name. File
paths below `src` map canonically:

| File | Module in package `acme` |
|---|---|
| `src/lib.al` | `acme` |
| `src/parser.al` | `acme.parser` |
| `src/compiler/parser.al` | `acme.compiler.parser` |
| `src/main.al` | `acme.main` |

The declared name must match this mapping. Source files do not merge into one
module, and one file cannot declare nested modules. A large component is split
into explicit submodules rather than relying on implicit directory aggregation.

Module paths and package names use lowercase ASCII identifiers separated by
dots. `core`, `std`, and implementation-prefixed roots are reserved. The exact
case-sensitive path gives a single file on every supported host, avoiding
case-folding ambiguity.

## Imports and visibility

Declarations are module-private unless marked `pub`. `pub` makes a declaration
visible to other modules in the same package and to dependents when its complete
signature is public. There is no separate package-only visibility in 1.0.

```alder
import acme.compiler.token
import acme.compiler.syntax as tree
import acme.compiler.diagnostic { Diagnostic, Range }
pub import acme.api { Request, Response }
```

- `import path` binds the final path component as a namespace.
- `as` changes that namespace binding.
- `{ Name, Other }` imports exactly those public names.
- `pub import ... { ... }` explicitly re-exports selected names.
- wildcard imports and implicit preludes other than the documented `core`
  prelude are absent.
- selected imported names cannot silently shadow a local declaration.

Dependencies expose their declared package root. The dependency name in the
manifest must match that root, so an import has one meaning without a hidden
alias table. Forks may retain the original package name; two packages with the
same root cannot coexist in one graph in Alder 1.0.

Imports form an acyclic module graph. A cycle is rejected with the canonical
lexicographically smallest cycle path. Declaration order inside a module does
not affect cross-declaration name resolution, except where a specific local
scope rule says otherwise.

C header imports use the separate `import c` form and never create an Alder
package dependency. See [C Interoperability](c-interop.md).

## Project manifest

An Alder project has one UTF-8 `alder.toml` at its root. Manifest format 1 uses
a deliberately restricted TOML profile: strings, booleans, integers, arrays,
and tables; duplicate keys and implementation-specific extensions are rejected.

```toml
manifest = 1
edition = "1"

[package]
name = "hello"
version = "0.1.0"

[targets.hello]
kind = "bin"
root = "src/main.al"

[targets.hello_lib]
kind = "lib"
root = "src/lib.al"

[dependencies]
json_tools = { git = "https://example.com/json-tools.git", rev = "9d40..." }

[native.zlib]
provider = "xmake"
package = "zlib"
version = "1.3.1"
shared = false
```

Required top-level fields are `manifest`, `edition`, `package`, and at least one
target. A binary target's root must export a supported `main` signature. A
library target defines a package API but does not imply a stable native Alder
ABI.

Profiles are selected by the driver, not source conditionals:

- `debug` keeps full checks, source mapping, and low optimization;
- `release` keeps the same language safety semantics and enables validated
  optimization;
- custom profiles may select diagnostics, debug information, C optimization,
  and link policy but cannot disable required safety checks by spelling.

Target-specific source selection is explicit in manifest target tables. Source
code has no general textual preprocessor. A target root may import a
platform module that owns the target's C binding block while the other modules
share one public wrapper API; this is the supported way to express
target-specific binding members.

## Workspace and source discovery

A workspace manifest lists member project roots explicitly. The build driver:

1. reads the selected target root;
2. follows exact module imports to exact mapped files;
3. resolves package roots from the locked dependency graph;
4. produces an immutable, canonical source snapshot;
5. passes the compiler core an explicit source list and build context.

The compiler core never walks directories, reads ambient project files, or
fetches dependencies. Unimported files do not affect a build. Test discovery
uses the same module graph plus explicit test roots and sorted in-module `test`
declarations.

Logical paths are slash-relative UTF-8 paths with no `..`, absolute prefix,
backslash, duplicate separator, NUL, or case collision. Canonical ordering uses
package identity then path bytes, never host directory enumeration order.

## Canonical package identity

A package source identity is `(package name, canonical-tree hash)`. Its
canonical package-instance identity additionally includes the sorted mapping
from each declared dependency name to that dependency's package-instance
identity. Because module imports are acyclic and package dependency cycles are
rejected, this recursively identifies one content-and-dependency DAG without
host paths, checkout locations, transport credentials, or directory order.
The manifest is part of the canonical tree, so its edition, targets, and
dependency declarations participate automatically. Two locators that produce
identical canonical trees and identical dependency mappings have the same
semantic package identity; provenance still records how each was obtained.

Workspace/path dependencies must resolve below an explicitly listed workspace
root. Their slash-relative workspace member path selects the source but is not
part of semantic identity. Dependencies outside that snapshot are rejected
rather than incorporating an absolute host path.

A Git locator is stored separately as fetch provenance. Manifest URLs use a
canonical `https://` or `ssh://` URI: scheme and DNS host are lowercase,
default ports and path dot-segments are removed, and userinfo passwords, query,
fragment, and implicit scp-like syntax are rejected. Repository path case and
an explicit username and nondefault port are preserved; `.git` is not guessed
or stripped. Authentication secrets are supplied out of band and never enter a
manifest, lock, diagnostic, or cache key. A dependency `rev` is a full
lowercase commit object ID, not a branch or tag. Redirects and mirrors may fetch
bytes but do not silently rewrite recorded provenance.

## Git packages and lockfile

Alder 1.0 supports:

- workspace/path dependencies for local development;
- Git dependencies identified by URL plus exact commit;
- transitive dependencies through each package manifest;
- an authoritative, versioned `alder.lock`;
- an immutable content-addressed source cache;
- `--locked`, `--offline`, and `--frozen` operation.

The lockfile records the canonical URL, exact commit, canonical-tree hash,
manifest hash, dependency edges, package name, and relevant native-provider
identity. Git commit identity alone is insufficient because filters, case
collisions, submodules, and mutable transport can change a checkout.

The canonical package tree contains regular files only. Symlinks, Git links/
submodules, devices, sockets, and other special file kinds are rejected. A
hard-linked path is read and hashed as an independent regular-file path; inode
identity is not semantic. Directories are implied by sorted slash-relative file
paths and have no hashed host mode. Every accepted file has one canonical
regular-file kind byte; POSIX executable/read/write bits, Windows attributes,
ownership, and timestamps are not semantic and are not hashed. Alder package
builds never execute a source file merely because its checkout mode is
executable. The hash covers the canonical path bytes, kind, length, and file
bytes, and rejects case collisions before hashing. Git dependencies derive
bytes from the committed
tree rather than a filtered worktree; workspace/path dependencies use the same
normalization over their explicit package roots.

Network access occurs only in explicit `add`, `fetch`, or `update` operations.
`check`, `build`, `run`, `test`, formatter, documentation, and LSP commands
never fetch implicitly.

- `--locked` rejects a manifest/lock mismatch.
- `--offline` uses only installed sysroots and local caches.
- `--frozen` implies both and also forbids lock/cache/native-plan mutation.

A public registry, publishing, and semver solving are outside 1.0. The package
`version` is API/release metadata; Git `rev` and the lockfile select code.

## Build-plan boundary

The driver resolves project semantics into a versioned build plan containing:

- toolchain, edition, target triple, and profile;
- package identities and canonical source hashes;
- exact module graph and public roots;
- sysroot identity;
- C binding headers and generated shim identities;
- native include, define, archive, and link inputs;
- output kinds and canonical logical paths;
- environment values explicitly admitted by the manifest.

Compilation consumes this plan without consulting ambient state. Absolute host
paths may appear in process invocation but never in semantic identities,
diagnostics, MIR, generated C, lockfiles, or cache keys.

The plan is serialized once per input state as a canonical, versioned artifact
keyed by its inputs. CLI commands, tests, documentation, queries, the LSP, and
the package cache all read that artifact instead of re-resolving the project,
so every tool sees the same module graph. There is no separate IDE resolver.

## Installed sysroot

The installed sysroot carries the platform-neutral `core` library and the
hosted `std` library as ordinary Alder sources distributed with the toolchain
and used offline; nothing fetches or scans for them at build time. Module
`core.option` lives at `<sysroot>/core/option.al`, `std.text` at
`<sysroot>/std/text.al`, and a bare root import would live at
`<sysroot>/core.al` or `<sysroot>/std.al`. Each file declares the module its
path spells, and every path below a root follows the same one-file/one-module
mapping as a package. `core` is implicitly available through the documented
prelude of builtin types and traits; its helper modules are imported
explicitly like any module, and `std` is imported explicitly.

The driver locates the sysroot once per build, before resolving the first
rooted import:

1. `ALDER_SYSROOT` when set to a nonempty path;
2. `<driver directory>/../lib/alder` for an installed layout;
3. otherwise a `core` or `std` import fails with a deterministic package
   error.

The project directory, its `src/` tree, and the working directory never
satisfy a `core` or `std` import, and `core` and `std` are reserved package
names, so a rooted import has exactly one meaning. Package imports continue
to resolve only below the package root.

The build plan's `sysroot v1:<16 hex>` line identifies the sysroot content a
build depends on: the same `poly64-v1` fold as the snapshot hash, applied in
canonical source order to one `path bytes, zero byte, text bytes` group per
sysroot source in the import closure. Sysroot sources appear in the plan like
package sources under their sysroot-relative logical paths. Importing a
module the installed sysroot does not contain, or building with no sysroot
installed, are deterministic package errors; the line changes only when the
sysroot content in the closure changes, so plans stay reproducible offline
across hosts and working directories.

## xmake/xrepo native provider

Managed xmake/xrepo is the default provider for third-party C and C++
dependencies, but it is not Alder's build system of record.

For every locked native package, Alder records:

- xmake binary version and digest;
- xrepo recipe repository commit, recipe path, and digest;
- upstream source URLs and content digests;
- package version, target, configs, patches, and toolchain identity;
- produced headers/libraries and their content digests;
- license/provenance metadata.

`alder fetch` may invoke the provider with network access to populate immutable
sources. `alder build --offline` invokes only an already-pinned provider and
cached inputs. Reproducible/frozen mode disables implicit system-package
fallback. Recipes are executable native build code and are therefore an
explicit trusted dependency, not declarative safe Alder.

A native package may instead use:

- `provider = "source"` for project-owned C/C++ sources and a restricted
  explicit compile/link description;
- `provider = "system"` for an intentionally non-reproducible host library,
  rejected by `--frozen` unless exact discovered artifacts are pinned;
- another future provider implementing the same locked build-plan contract.

Users normally run `alder build`; direct xmake knowledge is optional. The
Alder compiler bootstrap, runtime, and standard library have provider-free
source build descriptions and do not require xmake.

## C toolchain and outputs

The production pipeline remains verified MIR to conservative C11 to a
supported system or managed C toolchain. The plan pins the compiler family,
version constraints, target, flags, runtime, and linker inputs. The driver
rejects unknown flag injection in frozen builds.

Generated C can be retained with `--emit=c` for inspection. A source set with
`export c fn` declarations and no `main` is a library build: C emission skips
only the hosted-entry phase of verification, emits no `alder_program_entry`,
and leaves the export wrappers for an ordinary C caller. A source set with
neither `main` nor an export is rejected at verification. Build output uses a
target/profile/package layout below `build/`; atomic replacement prevents a
failed build from corrupting a previous output. C object and native executable
bytes need not match across different C toolchains, while generated C and the
semantic build plan must.

## 1.0 CLI

The installed driver provides:

```text
alder new <name>
alder check [--target <name>]
alder build [--target <name>] [--release] [--emit mir|c]
alder run [--target <name>] [-- <args>...]
alder test [filter] [--fuzz]
alder fmt [--check]
alder fix [--dry-run]
alder doc [<module-or-symbol>] [--full] [-s <words>] [--type <signature>]
alder ide def|refs|outline|hover|rename ...
alder explain <code>
alder spec [<section>] [-s <words>]
alder help [agent]
alder add <git-url> --rev <commit>
alder update [package] --rev <commit>
alder fetch
alder clean
alder lsp
alder bind check
```

All commands have stable human diagnostics and versioned JSON mode. Source
diagnostics, usage errors, I/O errors, package errors, native-provider errors,
and internal failures remain distinct. Noninteractive commands never prompt;
destructive or trust-changing operations require explicit flags.

The CLI is the primary interface to the toolchain. Every capability an editor
offers, including navigation, rename, hover, and API lookup, is a
noninteractive command over the serialized build plan, and `alder lsp` wraps
the same queries. A coding agent or script never needs an editor, a running
server, or text search to answer a semantic question.

### CLI output contract

Default output is compact plain text designed to be acted on in one round trip:

- **Success is one line.** `alder check` prints `ok` plus counts; `alder test`
  prints one summary line and expands only failures.
- **A diagnostic is complete on first read.** It has a stable code, the
  location, the direct cause in one sentence that names the involved values,
  types, or bindings, each related location, and a concrete fix when the
  compiler knows one. A model must not need a second command to learn what is
  wrong or where; `alder explain <code>` only adds background, a minimal
  wrong/right example pair, and the governing `alder spec` section.

  ```text
  src/app.al:12:9 error SEM0142 view `line` of `buffer` is used after `buffer.clear()` at 11:5
    11:5 `buffer.clear()` invalidates every view of `buffer`
    fix: copy the text first: `let text = String.from(line)`
  ```

- **Machine-applicable fixes.** When a fix is a mechanical edit, the JSON
  diagnostic carries it as text edits and `alder fix` applies every such edit.
- **A failed test is reproducible from its output.** The report shows the
  assertion's expression, both operand values, captured output, and the exact
  command that reruns only that case.
- **Long output is truncated at both ends.** When output exceeds the size limit
  (default 200 lines, `--max-lines` to change, `0` for none), the command
  prints the first and last part, one line stating how many lines were
  omitted, and the path of a file under `build/logs/` that holds the complete
  output. Nothing is lost and the full text is read only when needed.
- **No decoration off a terminal.** Color, progress bars, and spinners appear
  only on an interactive terminal; output never depends on terminal width.
- **Stable and deterministic.** Ordering follows canonical source order, and
  paths are workspace-relative.

`--json` selects the versioned machine form of the same records.

### Queries

`alder doc` answers API questions in layers, so a query returns only what was
asked:

- `alder doc std.fs` lists the module's public items, one line each: the
  signature and the doc comment's summary line;
- `alder doc std.fs.File.open` prints one item: signature, summary, documented
  errors, and its first example;
- `--full` prints the complete doc comment;
- `-s <words>` searches names and summaries across the sysroot and
  dependencies; `--type "Bytes -> Result(Json, _)"` searches by signature,
  with `_` matching any type.

Every listing ends with the item count; a listing that hits the output limit
follows the truncation rule above. `alder ide def|refs|outline|hover|rename`
performs semantic navigation by symbol path or `file:line:column`. `hover`
shows the inferred type, the doc summary, and whether a call is potentially
suspending. `alder spec` prints a section of the language specification, which
ships offline with the toolchain.

`alder help agent` prints a reference of at most 40 lines covering these
commands and the output contract. `alder new` writes an `AGENTS.md` that points
to it.

### Documentation requirements

Every public declaration, including public fields, enum variants, and trait
methods, needs a `///` doc comment, and so does each module. `alder check`
reports a missing one as an error. The first line must be a single sentence
summarizing the item; `alder doc` listings show only that line. A public
function returning `Result` documents its error cases under `# Errors`.
Examples in doc comments are compiled and run by `alder test`.

## Entry points and tests

A binary target selects one module exporting `main`. `main` may first take one
I/O capability: `std.io.Blocking` runs it without an executor, and
`std.io.Evented` starts the hosted executor and runs `main` as its root task.
It may then take zero parameters or one `[String]` or `[std.env.OsString]`
argument, and it returns `Unit`, `I32`, `Result(Unit, E)`, or `Result(I32, E)`,
where `E` implements `Display`.

The argument slice includes the host's element 0 when supplied; user arguments
therefore begin at index 1. `OsString` preserves the host bytes/Unicode units.
Selecting `[String]` performs strict conversion of every argument to Unicode/
UTF-8 before entering Alder. Invalid host text writes a fixed startup diagnostic
and exits with status 125; applications needing arbitrary arguments select
`OsString`.

`Unit`/`Ok(())` maps to status 0. An `I32`/`Ok(I32)` maps to its low eight bits
on every supported host, giving one portable 0..255 process status. An
unhandled `Err` writes `program error: {Display(error)}` plus one newline to
standard error and exits with status 1. Failure to write that diagnostic does
not change the status. Runtime invariant termination uses the separately fixed
runtime status 101.

Top-level tests are compiled only by `alder test`:

```alder
test "parses input" {
    assert(parse("ok").is_ok())
}

test "serves request" (io: SimIo) -> Result(Unit, TestError) {
    try exercise_server(io)
    return Ok(())
}
```

A test may take one I/O capability (`Blocking`, `SimIo`, or `Evented`) and
returns `Unit` (omitted) or `Result(Unit, E)` where `E: Display`. Fallthrough/`()`/`Ok(())` passes; `Err`
fails with its displayed value; assertion or invariant termination fails with
the captured process diagnostic. Expected-termination helpers execute the
subject in a child process because invariant panic is not catchable.

Enumeration is canonical by package, module path, source position, and name.
Tests are isolated processes by default. A test taking `SimIo` runs on the
deterministic single-worker executor with virtual time; a test taking `Evented`
exercises the production multithread executor without changing pass/fail
semantics.

## Reproducibility limits

Alder guarantees deterministic semantic inputs, generated MIR/C, package
identity, and build plans. Bit-identical native binaries require a fully pinned
native toolchain and host environment. System libraries, timestamps, signing,
and platform linkers can otherwise vary and must be reported rather than
silently included in a reproducibility claim.
