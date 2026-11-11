package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 field-path mut arguments: a `mut` parameter borrows the caller's storage,
// so a field path of a mutable place is that storage, not a copy. The reader
// program delegates through `self.inner.read(buffer)` and checks that the
// bytes and the consumed count reached the receiver; the cursor program proves
// a copyable cursor field advances in place. The rejections keep the mutable
// place requirement and the live-view exclusion intact.

const m8MutFieldArgumentProgram = `enum IoError {
    NotFound
}

trait Reader {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError)
}

type Source {
    data: Array(U8, 3)
    at: U64
}

impl Reader for Source {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        if self.at >= self.data.len() { return Ok(0) }
        let rest = self.data.len() - self.at
        let want = buffer.len()
        var n: U64 = want
        if n > rest { n = rest }
        var at: U64 = 0
        while at < n {
            buffer[at] = self.data[self.at + at]
            at = at + 1
        }
        self.at = self.at + n
        return Ok(n)
    }
}

type Wrapper {
    inner: Source
}

impl Reader for Wrapper {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.inner.read(buffer)
    }
}

type Deep {
    wrapper: Wrapper
}

impl Reader for Deep {
    fn read(mut self, mut buffer: MutSlice(U8)) -> Result(U64, IoError) {
        return self.wrapper.inner.read(buffer)
    }
}

fn main() -> I32 {
    var deep = Deep(wrapper: Wrapper(inner: Source(data: [1, 2, 3], at: 0)))
    var data: Array(U8, 4) = [0, 0, 0, 0]
    var view: MutSlice(U8) = data.slice_mut(0, 4)
    let got = match deep.read(view) {
        Ok(n) => n
        Err(_) => 99
    }
    if got != 3 { return 1 }
    if view[0] != 1 { return 2 }
    if view[1] != 2 { return 3 }
    if view[2] != 3 { return 4 }
    if view[3] != 0 { return 5 }
    if deep.wrapper.inner.at != 3 { return 6 }
    return 0
}
`

const m8MutCursorFieldProgram = `trait Cursor {
    fn step(mut self) -> Unit
}

type Counter {
    n: U64
}

impl Cursor for Counter {
    fn step(mut self) -> Unit {
        self.n = self.n + 1
        return
    }
}

type Wrap {
    c: Counter
}

fn advance(C: type(Cursor), mut c: C) -> Unit {
    c.step()
    return
}

fn main() -> I32 {
    var w = Wrap(c: Counter(n: 0))
    advance(w.c)
    advance(w.c)
    if w.c.n != 2 { return 1 }
    return 0
}
`

var m8MutFieldArgumentRejections = []struct {
	name, source, want string
}{
	{
		// A field of a let-bound root is not a mutable place: the callee would
		// advance a copy the caller never sees.
		"immutable-root-field",
		`trait Cursor {
    fn step(mut self) -> Unit
}
type Counter {
    n: U64
}
impl Cursor for Counter {
    fn step(mut self) -> Unit {
        self.n = self.n + 1
        return
    }
}
type Wrap {
    c: Counter
}
fn advance(C: type(Cursor), mut c: C) -> Unit {
    c.step()
    return
}
fn main() -> I32 {
    let w = Wrap(c: Counter(n: 0))
    advance(w.c)
    return 0
}
`,
		"mut cursor argument must be a mutable place",
	},
	{
		// A live view of the root excludes the exclusive borrow of its field.
		"live-view-of-root",
		`trait Cursor {
    fn step(mut self) -> Unit
}
type Counter {
    n: U64
}
impl Cursor for Counter {
    fn step(mut self) -> Unit {
        self.n = self.n + 1
        return
    }
}
type Wrap {
    items: Vec(U64)
    c: Counter
}
fn advance(C: type(Cursor), mut c: C) -> Unit {
    c.step()
    return
}
fn main() -> I32 {
    var w = Wrap(items: Vec.new(U64), c: Counter(n: 0))
    w.items.push(3)
    let view = w.items.slice(0, 1)
    advance(w.c)
    if view.len() != 1 { return 1 }
    return 0
}
`,
		"argument does not provide the parameter's required exclusive or owning access",
	},
}

func TestM8MutFieldArgumentQualification(t *testing.T) {
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
	runtimeObject := buildRuntimeObject(t, cc, root)

	for _, program := range []struct {
		name, text string
	}{
		{"m8-mut-field-reader.al", m8MutFieldArgumentProgram},
		{"m8-mut-cursor-field.al", m8MutCursorFieldProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			if !strings.Contains(mirText.stdout, "borrow_mut field(") {
				t.Fatalf("%s passes no field place by exclusive borrow:\n%s", program.name, mirText.stdout)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
		})
	}

	for _, rejection := range m8MutFieldArgumentRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "reject.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: status=%d stderr=%q", rejection.name, result.status, result.stderr)
			}
		})
	}
}
