# Alder 1.0 Examples

Design status: **Examples of the frozen 1.0 target**

Availability: **Most examples do not compile in Alder S0 yet**

These examples use one coherent 1.0 syntax. They are design fixtures until the
corresponding implementation milestone turns them into executable tests.

## Small command-line program

```alder
module hello.main

import std.io { Blocking, println }

pub fn main(io: Blocking, arguments: [String]) {
    let name = arguments.get(1).unwrap_or("world")
    println(io, "Hello, {name}!")
}
```

Values are immutable by default, indexing uses the safe `get`, and string
interpolation uses `Display`. Standard output is I/O, so `main` asks the host
for a blocking capability; no executor starts.

## Values, errors, and tests

```alder
module inventory.price

/// Why a price list has no valid total.
pub enum PriceError {
    /// A price was below zero.
    Negative
    /// The sum does not fit in `I64`.
    Overflow
}

/// Adds a list of non-negative prices.
///
/// # Errors
///
/// `Negative` for any price below zero; `Overflow` when the sum exceeds `I64`.
pub fn total(prices: [I64]) -> Result(I64, PriceError) {
    var value: I64 = 0

    for price in prices {
        if price < 0 {
            return Err(Negative)
        }
        value = try value.try_add(price).map_error(fn(_) => Overflow)
    }

    return Ok(value)
}

test "adds positive prices" {
    assert_eq(total([10, 20]), Ok(30))
}
```

Ordinary checked `+` terminates on a programmer invariant failure;
`try_add` exposes expected overflow as `Result`. Every public declaration
carries a doc comment whose first line is its summary.

## Inferred temporary storage

```alder
module documents.summary

import std.json { Json, JsonError }

/// Title and length of a JSON document.
pub type Summary {
    title: String
    word_count: U64
}

/// Reads the `title` and `content` fields of a JSON document.
///
/// # Errors
///
/// A `JsonError` when the bytes are not JSON or a field is missing.
pub fn summarize(data: Bytes) -> Result(Summary, JsonError) {
    let document = try Json.parse(data)
    let title = try document.string("title")
    let content = try document.string("content")

    return Ok(Summary(
        title: title,
        word_count: content.split_whitespace().count(),
    ))
}
```

The JSON tree and parsing scratch live in inferred temporary storage. The
returned summary is constructed or retained in caller-result storage. No
source domain, allocator, lifetime, or move annotation is required.

## Static traits and iterators

```alder
module report.collect

fn labels(I: type, iterator: I) -> Vec(String)
where I: Iterator(User) {
    return (
        iterator
            .filter(fn(user) => user.active)
            .map(fn(user) => user.name)
            .collect()
    )
}
```

Trait calls are statically resolved and monomorphized. Closures capture only
ordinary read values by independent value snapshot.

## Stable identity without graph ownership

```alder
module game.world

/// A named node with an optional parent.
pub type Entity {
    name: String
    parent: Entity.Id?
}

/// Owns every entity.
pub type World {
    entities: Table(Entity)
}

/// Inserts a child of `parent`, or returns `None` when `parent` is gone.
pub fn add_child(mut world: World, parent: Entity.Id, name: String)
    -> Option(Entity.Id) {
    if world.entities.get(parent).is_none() {
        return None
    }
    return Some(world.entities.insert(Entity(name: name, parent: Some(parent))))
}
```

Removing `parent` later makes its old ID fail to resolve; slot reuse cannot
retarget the ID. Graph edges do not control reclamation.

## Deterministic resources

```alder
module files.copy

import std.fs { File }
import std.path { Path }
import std.io { Io, IoError }

/// Copies the file at `from` to a new file at `to`.
///
/// # Errors
///
/// An `IoError` from opening, reading, writing, or closing either file.
pub fn copy(I: type, io: I, from: Path, to: Path) -> Result(Unit, IoError)
where I: Io {
    using input = try File.open(io, from)
    using output = try File.create(io, to)
    try input.copy_to(output)
    return output.finish()
}
```

`output.finish` reports final write/close errors and disarms fallback cleanup.
On earlier error, resources clean in reverse order. The same function copies
with blocking calls under `std.io.Blocking` and suspends under
`std.io.Evented`.

## Structured concurrency

```alder
module client.profile

import std.io { AsyncIo }
import std.net.http { get, HttpError }
import std.task { TaskGroup }

/// Fetches a user and their posts concurrently.
///
/// # Errors
///
/// The first `HttpError` from either request or from decoding its body.
pub fn load_profile(I: type, io: I, id: User.Id) -> Result(Profile, HttpError)
where I: AsyncIo {
    using tasks = TaskGroup.new(io)
    let user = tasks.spawn(get(io, "/users/{id}"))
    let posts = tasks.spawn(get(io, "/users/{id}/posts"))

    let user_response = try await user
    let posts_response = try await posts

    return Ok(Profile(
        user: try user_response.json(User),
        posts: try posts_response.json(Vec(Post)),
    ))
}
```

The group cannot finish before both children finish or are canceled and
cleaned. The two response values are independent; no mutable local is shared.

## Server lifetime

```alder
module server.main

import std.io { AsyncIo, Evented }
import std.net { TcpListener, TcpStream }
import std.task { TaskGroup }

fn serve(I: type, io: I, take socket: TcpStream(I))
where I: AsyncIo {
    // ...
}

pub fn main(io: Evented) -> Result(Unit, ServerError) {
    using listener = try TcpListener.bind(io, "127.0.0.1:8080")
    using connections = TaskGroup.new(io)

    while true {
        let socket = try listener.accept()
        connections.start(serve(io, socket))
    }
}
```

The service group may be long-lived, but it is still explicitly owned and
joined during shutdown. The visible `take socket` parameter on `serve` transfers
socket ownership into each child.

## Safe wrapper over C

```alder
module counter_app.counter

import std.c

import c "counter.h" as raw {
    opaque type Counter = "counter_t"
    raw fn create = "counter_create"() -> c.Ptr(Counter)
    raw fn value = "counter_value"(counter: c.ConstPtr(Counter)) -> c.LongLong
    raw fn destroy = "counter_destroy"(counter: c.Ptr(Counter))
}

/// A counter owned by the C library.
pub type Counter {
    raw: c.Ptr(raw.Counter)
}

impl Cleanup for Counter {
    fn cleanup(take self) {
        unsafe c { raw.destroy(self.raw) }
    }
}

/// Creates a counter.
///
/// # Errors
///
/// `CreateFailed` when the C library returns a null counter.
pub fn create() -> Result(Counter, CounterError) {
    let pointer = unsafe c { raw.create() }
    if c.is_null(pointer) {
        return Err(CreateFailed)
    }
    return Ok(unsafe c { Counter(raw: pointer) })
}

/// Reads the counter's current value.
///
/// # Errors
///
/// `OutOfRange` when the C value does not fit in `I64`.
pub fn value(counter: Counter) -> Result(I64, CounterError) {
    let raw_value = unsafe c { raw.value(counter.raw) }
    return I64.try_from(raw_value).map_error(fn(_) => OutOfRange)
}
```

The C pointer is never dereferenced in safe code. The wrapper validates null,
owns exactly one release, and checks target-dependent conversion.

## Project and native dependency

```toml
manifest = 1
edition = "1"

[package]
name = "counter_app"
version = "1.0.0"

[targets.counter]
kind = "bin"
root = "src/main.al"

[native.counter]
provider = "xmake"
package = "counter"
version = "2.1.0"
shared = false
```

`alder fetch` resolves the pinned provider/source into `alder.lock`;
`alder build --frozen` performs no network access and rejects drift.
