package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M9 gate 9.1 slice 1: signature-local suspension checking. A call is
// potentially suspending when the callee's declared signature, including its
// receiver, has a parameter of a suspending capability type: an Io-bounded
// type parameter without BlockingIo, a concrete AsyncIo implementor, or a
// record, enum, or applied generic containing one. Function values never
// suspend, so a closure body and a non-generic function used as a function
// value reject such a call with diagnostic 348.

const suspensionManifest = "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

func suspensionProject(body string) map[string]string {
	return map[string]string{
		"alder.toml":  suspensionManifest,
		"src/main.al": "module hello.main\n\n" + body,
	}
}

// The accepted program keeps every non-suspending shape reachable at run
// time: direct Io-bounded and concrete AsyncIo calls outside function values,
// Io+BlockingIo parameters, concrete Blocking parameters and methods, and
// containment through a record, an Option, and an enum when the contained
// capability is Blocking. Benign function values and ordinary non-Io
// generics also stay accepted.
const suspensionAcceptedProgram = `import std.io { AsyncIo, Blocking, BlockingIo, Io }

type Evented {
    pub id: U64
}

impl AsyncIo for Evented {
}

type Holder(T: type) {
    pub value: T
}

enum PlainPayload {
    Has(value: Blocking)
    Empty
}

fn io_ping(I: type(Io), cap: I) -> U64 {
    return 1
}

fn blocking_ping(I: type(BlockingIo), cap: I) -> U64 {
    return 2
}

fn both_ping(I: type(Io, BlockingIo), cap: I) -> U64 {
    return 3
}

fn concrete_ping(cap: Blocking) -> U64 {
    return 4
}

fn holder_ping(h: Holder(Blocking)) -> U64 {
    return 5
}

fn option_ping(o: Option(Blocking)) -> U64 {
    return 6
}

fn plain_enum_ping(p: PlainPayload) -> U64 {
    return 7
}

fn evented_ping(e: Evented) -> U64 {
    return e.id
}

fn identity(T: type, value: T) -> T {
    return value
}

fn benign(seed: U64) -> U64 {
    return seed + 1
}

pub fn main() -> I32 {
    let cap = Blocking()
    if io_ping(cap) != 1 { return 1 }
    let e = Evented(id: 3)
    if evented_ping(e) != 3 { return 2 }
    let a = fn() -> U64 { return blocking_ping(cap) }
    if a() != 2 { return 3 }
    let b = fn() -> U64 { return both_ping(cap) }
    if b() != 3 { return 4 }
    let c = fn() -> U64 { return concrete_ping(cap) }
    if c() != 4 { return 5 }
    let d = fn() -> U64 {
        let h = Holder(value: cap)
        return holder_ping(h)
    }
    if d() != 5 { return 6 }
    let f = fn() -> U64 {
        let o: Option(Blocking) = Some(cap)
        return option_ping(o)
    }
    if f() != 6 { return 7 }
    let g = fn() -> U64 {
        let p: PlainPayload = Has(cap)
        return plain_enum_ping(p)
    }
    if g() != 7 { return 8 }
    let h = fn() -> U64 { return identity(9) }
    if h() != 9 { return 9 }
    let k = fn() -> I64 { return cap.monotonic().seconds }
    if k() < 0 { return 10 }
    let value = benign
    if value(1) != 2 { return 11 }
    let plain = concrete_ping
    if plain(cap) != 4 { return 12 }
    return 0
}
`

func TestSuspensionCheckerAcceptsNonSuspendingValues(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	files := suspensionProject(suspensionAcceptedProgram)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(root, "sysroot")), files, "run")
	if result.status != 0 || result.stdout != "" || result.stderr != "" {
		t.Fatalf("accepted suspension shapes did not run: %+v", result)
	}
}

func TestSuspensionCheckerRejectsFunctionValueBoundaries(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))

	rejections := []struct {
		name string
		body string
		want string
	}{
		{
			"closure-io-generic",
			`import std.io { Blocking, Io }

fn io_ping(I: type(Io), cap: I) -> U64 {
    return 1
}

pub fn main() -> I32 {
    let cap = Blocking()
    let g = fn() -> U64 { return io_ping(cap) }
    let n = g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: io_ping",
		},
		{
			"closure-standard-print",
			`import std.io { Blocking, println }

pub fn main() -> I32 {
    let cap = Blocking()
    let g = fn() -> Unit { println(cap, "x") }
    g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: println",
		},
		{
			"closure-concrete-async",
			`import std.io { AsyncIo }

type Evented {
    pub id: U64
}

impl AsyncIo for Evented {
}

fn evented_ping(e: Evented) -> U64 {
    return e.id
}

pub fn main() -> I32 {
    let g = fn() -> U64 {
        let e = Evented(id: 1)
        return evented_ping(e)
    }
    let n = g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: evented_ping",
		},
		{
			"closure-record-containment",
			`import std.io { AsyncIo }

type Evented {
    pub id: U64
}

impl AsyncIo for Evented {
}

type Outer {
    pub inner: Evented
}

fn takes_outer(o: Outer) -> U64 {
    return 1
}

pub fn main() -> I32 {
    let g = fn() -> U64 {
        let e = Evented(id: 1)
        let o = Outer(inner: e)
        return takes_outer(o)
    }
    let n = g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: takes_outer",
		},
		{
			"closure-enum-containment",
			`import std.io { AsyncIo }

type Evented {
    pub id: U64
}

impl AsyncIo for Evented {
}

enum Payload {
    Has(value: Evented)
    Empty
}

fn takes_payload(p: Payload) -> U64 {
    return 1
}

pub fn main() -> I32 {
    let g = fn() -> U64 {
        let e = Evented(id: 1)
        let p: Payload = Has(e)
        return takes_payload(p)
    }
    let n = g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: takes_payload",
		},
		{
			"closure-applied-generic-containment",
			`import std.io { Blocking, Io }

fn option_ping(I: type(Io), o: Option(I)) -> U64 {
    return 1
}

pub fn main() -> I32 {
    let g = fn() -> U64 {
        let cap = Blocking()
        let o: Option(Blocking) = Some(cap)
        return option_ping(o)
    }
    let n = g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: option_ping",
		},
		{
			"closure-record-generic-containment",
			`import std.io { Blocking, Io }

type Holder(T: type) {
    pub value: T
}

fn holder_ping(I: type(Io), h: Holder(I)) -> U64 {
    return 1
}

pub fn main() -> I32 {
    let g = fn() -> U64 {
        let cap = Blocking()
        let h = Holder(value: cap)
        return holder_ping(h)
    }
    let n = g()
    return 0
}
`,
			"error[SEM0001]: closure body contains a potentially suspending call: holder_ping",
		},
		{
			"function-value-io-generic",
			`import std.io { Blocking, Io }

fn io_ping(I: type(Io), cap: I) -> U64 {
    return 1
}

fn helper(cap: Blocking) -> U64 {
    return io_ping(cap)
}

pub fn main() -> I32 {
    let cap = Blocking()
    let f = helper
    let n = f(cap)
    return 0
}
`,
			"error[SEM0001]: function used as a function value contains a potentially suspending call: io_ping",
		},
		{
			"function-value-concrete-async",
			`import std.io { AsyncIo }

type Evented {
    pub id: U64
}

impl AsyncIo for Evented {
}

fn evented_ping(e: Evented) -> U64 {
    return e.id
}

fn helper(e: Evented) -> U64 {
    return evented_ping(e)
}

pub fn main() -> I32 {
    let e = Evented(id: 1)
    let f = helper
    let n = f(e)
    return 0
}
`,
			"error[SEM0001]: function used as a function value contains a potentially suspending call: evented_ping",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run(rejection.name, func(t *testing.T) {
			files := suspensionProject(rejection.body)
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "check")
			if result.status != 1 || result.stdout != "" {
				t.Fatalf("expected a source rejection, got %+v", result)
			}
			if strings.Count(result.stderr, "error[") != 1 {
				t.Fatalf("expected exactly one diagnostic, got %q", result.stderr)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("diagnostic = %q, want %q", result.stderr, rejection.want)
			}
		})
	}
}
