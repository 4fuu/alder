package frontend

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

func TestM71VecLoweringCarriesPlacementAndDeepCopy(t *testing.T) {
	m := compileStr(t, `
fn first(T: type, values: [T]) -> T { return values[0] }
fn main() -> I32 {
    var values: Vec(U64) = Vec.from_array(U64, [1, 2])
    var copied: Vec(U64) = values
    copied.push(3)
    if first(values) != 1 { return 1 }
    return 0
}
`)
	mainID, ok := m.Function("main")
	if !ok || len(m.Functions[mainID].Params) != 1 || m.Functions[mainID].Params[0].Type != m.DomainHandle() {
		t.Fatalf("main does not carry exactly one hidden placement domain")
	}
	printed := mir.Print(m)
	for _, want := range []string{"vec.construct.checked", "copy_to_domain", "vec.grow.checked", "vec.as_slice"} {
		if !strings.Contains(printed, want) {
			t.Fatalf("lowered MIR does not contain %q:\n%s", want, printed)
		}
	}
}

func TestM73MutableVecFieldReceiver(t *testing.T) {
	m := compileStr(t, `
type Inner { values: Vec(U64) }
type Outer { inner: Inner }
fn main() -> I32 {
    var state = Outer(inner: Inner(values: Vec.new(U64)))
    let pushed = match state.inner.values.try_push(7) {
        Ok => true
        Err(error) => false
    }
    let reserved = match state.inner.values.try_reserve(3) {
        Ok => true
        Err(error) => false
    }
    if !pushed || !reserved { return 2 }
    if state.inner.values.len() != 1 || state.inner.values[0] != 7 { return 1 }
    return 0
}
`)
	printed := mir.Print(m)
	if !strings.Contains(printed, "store field(field(local %state, inner), values)") {
		t.Fatalf("field mutation did not store directly through the nested place:\n%s", printed)
	}

	for _, tc := range []struct {
		name string
		src  string
	}{
		{"immutable root", `type Box { values: Vec(U64) }
fn bad() -> Result(Unit, CapacityError) {
    let box = Box(values: Vec.new(U64))
    return box.values.try_push(1)
}`},
		{"parameter root", `type Box { values: Vec(U64) }
fn bad(box: Box) -> Result(Unit, CapacityError) { return box.values.try_push(1) }`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Compile(tc.src)
			if err == nil || !strings.Contains(err.Error(), "requires a mutable Vec binding") {
				t.Fatalf("Compile error = %v", err)
			}
		})
	}
}

func TestM73FieldProjectionMaterializesOnlySelectedField(t *testing.T) {
	m := compileStr(t, `
type Leaf { values: Vec(U64) }
type Outer {
    leaf: Leaf
    sibling: Vec(U64)
}
fn make() -> Outer {
    return Outer(leaf: Leaf(values: Vec.new(U64)), sibling: Vec.new(U64))
}
fn selected(input: Outer) -> Vec(U64) { return input.leaf.values }
fn temporary() -> Vec(U64) { return make().leaf.values }
`)
	printed := mir.Print(m)
	selectedID, ok := m.Function("selected")
	if !ok {
		t.Fatal("missing selected function")
	}
	selectedText := mir.Print(&mir.Module{FormatVersion: m.FormatVersion, Types: m.Types, Constants: m.Constants, Functions: []*mir.Function{m.Functions[selectedID]}})
	if got := strings.Count(selectedText, "copy_to_domain"); got != 2 {
		t.Fatalf("nested field projection materialized %d values, want only the selected Vec's local and return copies:\n%s", got, selectedText)
	}
	if got := strings.Count(printed, "call @make"); got != 1 {
		t.Fatalf("temporary field base evaluated %d times, want once:\n%s", got, printed)
	}
}

func TestM71LexicalViewRejections(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want string
	}{
		{
			name: "immutable view blocks owner mutation",
			src: `fn main() -> I32 {
    var values: Array(U64, 2) = [1, 2]
    let view: [U64] = values.slice(0, 1)
    values[0] = 3
    return 0
}`,
			want: `cannot mutate "values" while an immutable view is active`,
		},
		{
			name: "mutable view blocks owner read",
			src: `fn main() -> I32 {
    var values: Array(U64, 2) = [1, 2]
    var view: MutSlice(U64) = values.slice_mut(0, 1)
    let value = values[0]
    return 0
}`,
			want: `cannot access "values" while its mutable view is active`,
		},
		{
			name: "overlapping mutable views",
			src: `fn main() -> I32 {
    var values: Array(U64, 3) = [1, 2, 3]
    var left: MutSlice(U64) = values.slice_mut(0, 2)
    var right: MutSlice(U64) = values.slice_mut(1, 3)
    return 0
}`,
			want: `cannot access "values" while its mutable view is active`,
		},
		{
			name: "structural mutation invalidates view",
			src: `fn main() -> I32 {
    var values: Vec(U64) = Vec.from_array(U64, [1, 2])
    let view: [U64] = values.slice(0, 1)
    values.push(3)
    return 0
}`,
			want: `cannot mutate "values" while an immutable view is active`,
		},
		{
			name: "fallible push potentially invalidates view",
			src: `fn main() -> I32 {
    var values: Vec(U64) = Vec.from_array(U64, [1, 2])
    let view: [U64] = values.slice(0, 1)
    let result = values.try_push(3)
    return 0
}`,
			want: `cannot mutate "values" while an immutable view is active`,
		},
		{
			name: "fallible reserve potentially invalidates view",
			src: `fn main() -> I32 {
    var values: Vec(U64) = Vec.from_array(U64, [1, 2])
    let view: [U64] = values.slice(0, 1)
    let result = values.try_reserve(3)
    return 0
}`,
			want: `cannot mutate "values" while an immutable view is active`,
		},
		{
			name: "subview blocks parent",
			src: `fn main() -> I32 {
    var values: Array(U64, 2) = [1, 2]
    var view: MutSlice(U64) = values.slice_mut(0, 2)
    var child: MutSlice(U64) = view.subview(0, 1)
    view[0] = 3
    return 0
}`,
			want: `cannot mutate "view" while its mutable view is active`,
		},
		{
			name: "mutable view alias",
			src: `fn main() -> I32 {
    var values: Array(U64, 2) = [1, 2]
    var first: MutSlice(U64) = values.slice_mut(0, 2)
    var second: MutSlice(U64) = first
    return 0
}`,
			want: "must be formed directly by slice_mut or subview",
		},
		{
			name: "mutable view reassignment",
			src: `fn main() -> I32 {
    var left: Array(U64, 1) = [1]
    var right: Array(U64, 1) = [2]
    var first: MutSlice(U64) = left.slice_mut(0, 1)
    var second: MutSlice(U64) = right.slice_mut(0, 1)
    second = first
    return 0
}`,
			want: "cannot be reassigned or copied",
		},
		{
			name: "temporary mutable view before another argument",
			src: `fn consume(view: MutSlice(U64), value: U64) -> Unit {}
fn main() -> I32 {
    var values: Array(U64, 2) = [1, 2]
    consume(values.slice_mut(0, 1), values[1])
    return 0
}`,
			want: "mutable or temporary scoped-view argument must be last",
		},
		{
			name: "temporary immutable borrow before owner mutation",
			src: `fn consume(view: [U64], mutation: Unit) -> Unit {}
fn main() -> I32 {
    var values: Vec(U64) = Vec.from_array(U64, [1, 2])
    consume(values, values.push(3))
    return 0
}`,
			want: "mutable or temporary scoped-view argument must be last",
		},
		{
			name: "mutable view return",
			src:  `fn bad(values: MutSlice(U64)) -> MutSlice(U64) { return values }`,
			want: "scoped view MutSlice(U64) cannot be returned",
		},
		{
			name: "mutable view stored in record",
			src: `type Box { values: MutSlice(U64) }
fn main() -> I32 {
    var values: Array(U64, 1) = [1]
	var view = values.slice_mut(0, 1)
	let box = Box(values: view)
    return 0
}`,
			want: `scoped view MutSlice(U64) cannot be stored in field "values"`,
		},
		{
			name: "nested mutable view stored in record",
			src: `type Inner { values: MutSlice(U64) }
type Outer { inner: Inner }
fn bad(inner: Inner) -> I32 {
    let outer = Outer(inner: inner)
    return 0
}`,
			want: `scoped view Inner cannot be stored in field "inner"`,
		},
		{
			name: "nested mutable view return",
			src: `type Box { values: MutSlice(U64) }
fn bad(box: Box) -> Box { return box }`,
			want: "scoped view Box cannot be returned",
		},
		{
			name: "mutable view stored in array",
			src: `fn bad() -> I32 {
    var values: Array(U64, 1) = [1]
	var view = values.slice_mut(0, 1)
	let stored = [view]
    return 0
}`,
			want: "scoped view MutSlice(U64) cannot be stored in an array",
		},
		{
			name: "mutable view stored in variant",
			src: `fn bad() -> I32 {
    var values: Array(U64, 1) = [1]
	var view = values.slice_mut(0, 1)
	let stored: Option(MutSlice(U64)) = Some(view)
    return 0
}`,
			want: `scoped view MutSlice(U64) cannot be stored in variant "Some"`,
		},
		{
			name: "affine Vec element",
			src:  `fn bad(values: Vec(Domain)) -> I32 { return 0 }`,
			want: "Vec element type Domain is affine or scoped",
		},
		{
			name: "immutable indexed assignment",
			src: `fn bad(values: [U64]) -> I32 {
    values[0] = 1
    return 0
}`,
			want: `cannot assign through immutable binding "values"`,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Compile(tc.src)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Compile error = %v, want substring %q", err, tc.want)
			}
			_, again := Compile(tc.src)
			if again == nil || again.Error() != err.Error() {
				t.Fatalf("diagnostic is not deterministic: %v then %v", err, again)
			}
		})
	}
}
