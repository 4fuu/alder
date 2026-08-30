package compiler

import (
	"os"
	"strings"
	"testing"
)

// This focused contract test guards the stable checked-graph identities that
// the separately landed M7.1 lowerer consumes. Behavioral compilation remains
// covered by the production checker conformance harness.
func TestAlderM71CheckerModelContract(t *testing.T) {
	model, err := os.ReadFile("src/model.al")
	if err != nil {
		t.Fatal(err)
	}
	checker, err := os.ReadFile("src/checker.al")
	if err != nil {
		t.Fatal(err)
	}
	for _, fact := range []string{
		"16 [U8], 17 Vec, 18 MutSlice, and 19 CapacityError",
		"18 Vec.new, 19 Vec.from_array, 20 len, 21 Vec.push, 22 get",
		"26 Vec.try_reserve, 27 Vec.try_push, 28 Bytes.try_from_vec",
	} {
		if !strings.Contains(string(model), fact) {
			t.Fatalf("model is missing M7.1 contract %q", fact)
		}
	}
	for _, fact := range []string{
		`node_word(state, node, "Vec") { kind = 17`,
		`node_word(state, node, "MutSlice") { kind = 18`,
		`canonical_application(d, current, owner, 17, element, 0, 1)`,
		`identity: U64 = 18`,
		`identity = 19`,
		`builtin = 20`,
		`builtin = 21`,
		`builtin = 22`,
		`builtin = 23`,
		`builtin = 24`,
		`builtin = 25`,
		`fn parameter_type_compatible`,
		`category.contains_nonimmutable_scoped`,
	} {
		if !strings.Contains(string(checker), fact) {
			t.Fatalf("checker is missing M7.1 graph fact %q", fact)
		}
	}
}

func runAlderM71CheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"collections.al": `type ViewBox { view: [U64] }
enum ViewChoice {
 Empty
 Values(value: ViewBox)
}

fn boxed(values: [U64]) -> ViewBox { return ViewBox(view: values) }
fn chosen(values: [U64]) -> ViewChoice { return Values(ViewBox(view: values)) }
fn listed(values: [U64]) -> Array([U64], 1) { return [values] }
fn collected(values: [U64]) -> Vec(ViewBox) {
 var result = Vec.new(ViewBox)
 result.push(ViewBox(view: values))
 return result
}

fn accepted() -> U64 {
 let seed: Array(U64, 2) = [1, 2]
 var values: Vec(U64) = Vec.from_array(U64, seed)
 { let first = values.slice(0, 1)
   let second = values.slice(0, 2)
   let owner_read = values[0]
   let view_read = first[0]
 }
 values.push(3)
 { var writable = values.slice_mut(0, 2)
   writable[0] = 4
   { var nested = writable.subview(0, 1)
     nested[0] = 5
   }
   writable[1] = 6
 }
 values.push(7)
 return values[0]
}
`,
	}
	manifest := parseCheckerManifest(t, runAlderChecker(t, exe, accept, []string{"collections.al"}, false), accept)
	if len(manifest.diagnostics) != 0 {
		t.Fatalf("M7.1 acceptance diagnostics: %+v", manifest.diagnostics)
	}

	rejections := []struct {
		name, source string
		code         int
	}{
		{"immutable-slice-store", "fn f(values: [U64]) -> Unit { values[0] = 1 }\n", 103},
		{"immutable-view-owner-store", "fn f() -> Unit { let a: Array(U64, 1) = [1]\n var v = Vec.from_array(U64, a)\n { let s = v.slice(0, 1)\n v[0] = 2 } }\n", 92},
		{"immutable-view-owner-push", "fn f() -> Unit { let a: Array(U64, 1) = [1]\n var v = Vec.from_array(U64, a)\n { let s = v.slice(0, 1)\n v.push(2) } }\n", 92},
		{"immutable-then-mutable", "fn f() -> Unit { let a: Array(U64, 1) = [1]\n var v = Vec.from_array(U64, a)\n let s = v.slice(0, 1)\n var m = v.slice_mut(0, 1) }\n", 92},
		{"mutable-owner-read", "fn f() -> Unit { let a: Array(U64, 1) = [1]\n var v = Vec.from_array(U64, a)\n var m = v.slice_mut(0, 1)\n let x = v[0] }\n", 92},
		{"mutable-second-view", "fn f() -> Unit { let a: Array(U64, 1) = [1]\n var v = Vec.from_array(U64, a)\n var m = v.slice_mut(0, 1)\n let s = v.slice(0, 1) }\n", 92},
		{"nested-parent-read", "fn f() -> Unit { let a: Array(U64, 1) = [1]\n var v = Vec.from_array(U64, a)\n var m = v.slice_mut(0, 1)\n { var n = m.subview(0, 1)\n let x = m[0] } }\n", 92},
		{"mutable-alias", "fn f() -> Unit { var a: Array(U64, 1) = [1]\n var first = a.slice_mut(0, 1)\n var second: MutSlice(U64) = first }\n", 104},
		{"mutable-reassign", "fn f() -> Unit { var a: Array(U64, 1) = [1]\n var b: Array(U64, 1) = [2]\n var first = a.slice_mut(0, 1)\n var second = b.slice_mut(0, 1)\n second = first }\n", 104},
		{"temporary-view-not-final", "fn use(view: MutSlice(U64), value: U64) -> Unit {}\nfn f() -> Unit { var a: Array(U64, 1) = [1]\n use(a.slice_mut(0, 1), a[0]) }\n", 104},
		{"temporary-borrow-not-final", "fn use(view: [U64], mutation: Unit) -> Unit {}\nfn f() -> Unit { var a = Vec.from_array(U64, [1])\n use(a, a.push(2)) }\n", 104},
		{"aggregate-mutable-scoped", "type Box { view: MutSlice(U64) }\nfn f(values: MutSlice(U64)) -> Unit { let box = Box(view: values) }\n", 104},
		{"array-mutable-scoped", "fn f(values: MutSlice(U64)) -> Unit { let stored = [values] }\n", 104},
		{"variant-mutable-scoped", "fn f(values: MutSlice(U64)) -> Unit { let stored: Option(MutSlice(U64)) = Some(values) }\n", 104},
	}
	for _, tc := range rejections {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name + ".al": tc.source}
			m := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true), files)
			if len(m.diagnostics) != 1 || m.diagnostics[0].kind != tc.code {
				t.Fatalf("diagnostics = %+v, want code %d", m.diagnostics, tc.code)
			}
		})
	}
}
