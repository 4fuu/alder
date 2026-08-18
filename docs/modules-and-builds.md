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
code has no general textual preprocessor.

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

The same plan API is used by CLI, tests, documentation, LSP, and package cache.
There is no separate IDE resolver.

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

Generated C can be retained with `--emit=c` for inspection. Build output uses a
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
alder test [filter]
alder fmt [--check]
alder doc [--open]
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

## Entry points and tests

A binary target selects one module exporting `main`. Supported 1.0 forms are
synchronous or `async`, with zero parameters or one `[String]` or
`[std.env.OsString]` argument, and a result of `Unit`, `I32`,
`Result(Unit, E)`, or `Result(I32, E)`, where `E` implements `Display`.

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

async test "serves request" -> Result(Unit, TestError) {
    try await exercise_server()
    return Ok(())
}
```

A test is synchronous `test` or `async test` and returns `Unit` (omitted) or
`Result(Unit, E)` where `E: Display`. Fallthrough/`()`/`Ok(())` passes; `Err`
fails with its displayed value; assertion or invariant termination fails with
the captured process diagnostic. Expected-termination helpers execute the
subject in a child process because invariant panic is not catchable.

Enumeration is canonical by package, module path, source position, and name.
Tests are isolated processes by default. Async tests use a deterministic
single-worker executor by default; `--async-workers=auto` exercises the
production multithread executor without changing pass/fail semantics.

## Reproducibility limits

Alder guarantees deterministic semantic inputs, generated MIR/C, package
identity, and build plans. Bit-identical native binaries require a fully pinned
native toolchain and host environment. System libraries, timestamps, signing,
and platform linkers can otherwise vary and must be reported rather than
silently included in a reproducibility claim.
