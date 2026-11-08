package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M7.5 field-place receivers: a mutating collection operation resolves its
// receiver as a place, so `b.items.push(x)`, `b.items[i] = x`, a Map or Set
// insert, and a Table operation work through a field of a local, a field of a
// `mut self` receiver, a nested field path, and an element of a field. The
// grown header is written back through that place, and the access rules still
// refuse a live view of the same field.
//
// These programs stay out of the Go-frontend oracle corpora: the Go checker
// has no Vec, Map, Set, or Table surface.

const m75FieldReceiverProgram = `type Inner {
    items: Vec(U64)
}
type Outer {
    inner: Inner
    rows: Vec(Vec(U64))
    names: Set(U64)
    counts: Map(U64, U64)
}
impl Outer {
    fn push_inner(mut self, x: U64) -> Unit {
        self.inner.items.push(x)
        return
    }
    fn count(self) -> U64 {
        return self.inner.items.len()
    }
}
fn main() -> I32 {
    var o = Outer(inner: Inner(items: Vec.new(U64)), rows: Vec.new(Vec(U64)), names: Set.new(U64), counts: Map.new(U64, U64))
    o.inner.items.push(3)
    o.inner.items.push(5)
    if o.inner.items.len() != 2 { return 1 }
    o.inner.items[1] = 7
    if o.inner.items[1] != 7 { return 2 }
    o.push_inner(11)
    if o.count() != 3 { return 3 }
    if o.inner.items[2] != 11 { return 4 }
    var inner = Vec.new(U64)
    inner.push(1)
    o.rows.push(inner)
    o.rows[0].push(2)
    if o.rows[0].len() != 2 { return 5 }
    if o.rows[0][1] != 2 { return 6 }
    o.names.insert(4)
    if !o.names.contains(4) { return 7 }
    o.names.remove(4)
    if o.names.contains(4) { return 8 }
    o.counts.insert(1, 100)
    if o.counts.len() != 1 { return 9 }
    o.counts.remove(1)
    if o.counts.len() != 0 { return 10 }
    var total: U64 = 0
    for x in o.inner.items {
        total = total + x
    }
    if total != 21 { return 11 }
    return 0
}
`

// m75FieldTableProgram reaches a Table through a field of a record the program
// owns with `using`, and runs every table operation through that field.
const m75FieldTableProgram = `type Player {
    age: U64
}
type Db {
    t: Table(Player)
}
impl Cleanup for Db {
    fn cleanup(take self) -> Unit {
        return
    }
}
fn build() -> Db {
    using fresh = Table.new(Player)
    return Db(t: fresh)
}
fn age_of(db: Db, id: Player.Id) -> U64 {
    return match db.t.get(id) {
        Some(p) => p.age
        None => 0
    }
}
fn bump(mut db: Db, id: Player.Id) -> Unit {
    match db.t.get_mut(id) {
        Some(p) => { p.age = 50 }
        None => {}
    }
    return
}
fn main() -> I32 {
    using db = build()
    let first = db.t.insert(Player(age: 7))
    if age_of(db, first) != 7 { return 1 }
    bump(db, first)
    if age_of(db, first) != 50 { return 2 }
    let second = db.t.insert(Player(age: 3))
    if age_of(db, second) != 3 { return 3 }
    if !db.t.remove(first) { return 4 }
    if age_of(db, first) != 0 { return 5 }
    if db.t.remove(first) { return 6 }
    return 0
}
`

// m75FieldReceiverRejections pins the rules a field receiver must keep: the
// root binding has to be mutable, a live view of the same field still excludes
// the mutation, and a table lookup is still only a match scrutinee.
var m75FieldReceiverRejections = []struct {
	name, source, want string
}{
	{
		"immutable-root-push",
		"type Bag {\n    items: Vec(U64)\n}\nfn main() -> I32 {\n    let b = Bag(items: Vec.new(U64))\n    b.items.push(1)\n    return 0\n}\n",
		"cannot assign to immutable binding \"b\"",
	},
	{
		"immutable-root-index-store",
		"type Bag {\n    items: Vec(U64)\n}\nfn main() -> I32 {\n    let b = Bag(items: Vec.new(U64))\n    b.items[0] = 1\n    return 0\n}\n",
		"cannot assign to immutable binding \"b\"",
	},
	{
		"read-parameter-root-push",
		"type Bag {\n    items: Vec(U64)\n}\nfn f(b: Bag) -> I32 {\n    b.items.push(1)\n    return 0\n}\nfn main() -> I32 { return 0 }\n",
		"cannot assign to immutable binding \"b\"",
	},
	{
		"live-view-of-field-blocks-push",
		"type Bag {\n    items: Vec(U64)\n}\nfn main() -> I32 {\n    var b = Bag(items: Vec.new(U64))\n    b.items.push(1)\n    let view = b.items.slice(0, 1)\n    b.items.push(2)\n    return 0\n}\n",
		"argument does not provide the parameter's required exclusive or owning access",
	},
	{
		"live-view-of-field-blocks-index-store",
		"type Bag {\n    items: Vec(U64)\n}\nfn main() -> I32 {\n    var b = Bag(items: Vec.new(U64))\n    b.items.push(1)\n    let view = b.items.slice(0, 1)\n    b.items[0] = 5\n    return 0\n}\n",
		"argument does not provide the parameter's required exclusive or owning access",
	},
	{
		"live-table-view-of-field-blocks-insert",
		"type Player {\n    age: U64\n}\ntype Db {\n    t: Table(Player)\n}\nimpl Cleanup for Db {\n    fn cleanup(take self) -> Unit { return }\n}\nfn build() -> Db {\n    using fresh = Table.new(Player)\n    return Db(t: fresh)\n}\nfn main() -> I32 {\n    using db = build()\n    let id = db.t.insert(Player(age: 7))\n    match db.t.get(id) {\n        Some(p) => { let other = db.t.insert(Player(age: 8)) }\n        None => {}\n    }\n    return 0\n}\n",
		"overlapping table access",
	},
	{
		"field-lookup-bound",
		"type Db {\n    t: Table(U64)\n}\nimpl Cleanup for Db {\n    fn cleanup(take self) -> Unit { return }\n}\nfn build() -> Db {\n    using fresh = Table.new(U64)\n    return Db(t: fresh)\n}\nfn main() -> I32 {\n    using db = build()\n    let id = db.t.insert(1)\n    let option = db.t.get(id)\n    return 0\n}\n",
		"semantic error (checker diagnostic 104)",
	},
}

func TestM75FieldReceiverQualification(t *testing.T) {
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
		{"m75-field-receiver.al", m75FieldReceiverProgram},
		{"m75-field-table.al", m75FieldTableProgram},
	} {
		program := program
		t.Run(program.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{program.name: program.text}
			mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 5\n") {
				t.Fatalf("%s MIR result: %+v stderr=%s", program.name, mirText, mirText.stderr)
			}
			repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", program.name)
			if repeat != mirText {
				t.Fatalf("%s MIR changed across processes", program.name)
			}
			cResult := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cResult.status != 0 || cResult.stderr != "" || !strings.HasPrefix(cResult.stdout, "/* Generated by the Alder C11 backend.") {
				t.Fatalf("%s C result: %+v stderr=%s", program.name, cResult, cResult.stderr)
			}
			cRepeat := runProductionCompiler(t, exe, files, "compile", "--emit=c", program.name)
			if cRepeat != cResult {
				t.Fatalf("%s C changed across processes", program.name)
			}
			if strings.Contains(cResult.stdout, "__s0_") {
				t.Fatalf("%s generated C exposes bootstrap names", program.name)
			}
			compileAndRunProductionArtifact(t, cc, root, runtimeObject, cResult.stdout, 0)
		})
	}

	for _, rejection := range m75FieldReceiverRejections {
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
