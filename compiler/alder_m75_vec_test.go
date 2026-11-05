package compiler

import (
	"testing"
)

// M7.5 affine Vec elements: Vec(T) over a Cleanup owner is affine, grows only
// through push on a plain local binding, and registers a per-element drain
// with callback-free using. The Go oracle has neither trait implementations
// nor the drain surface, so these programs stay out of the shared
// Go-comparison corpora.

func runAlderM75VecCheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"vec-drain.al": `import c counter: fn(U64) -> Unit
type Res {
 n: U64
}
impl Cleanup for Res {
 fn cleanup(take self) -> Unit {
  unsafe c { counter(self.n) }
  return
 }
}
fn make(n: U64) -> Res { return Res(n: n) }
fn main() -> I32 {
 let v = Vec.new(Res)
 v.push(make(1))
 v.push(make(2))
 using w = v
 let n = w.len()
 if n != 2 { return 1 }
 return 0
}
`,
		"vec-drain-early-return.al": `type Res {
 n: U64
}
impl Cleanup for Res {
 fn cleanup(take self) -> Unit { return }
}
fn early(flag: Bool) -> I32 {
 let v = Vec.new(Res)
 v.push(Res(n: 1))
 using w = v
 if flag { return 5 }
 return 0
}
fn main() -> I32 {
 if early(true) != 5 { return 1 }
 if early(false) != 0 { return 2 }
 return 0
}
`,
		"vec-drain-take-param.al": `type Res {
 n: U64
}
impl Cleanup for Res {
 fn cleanup(take self) -> Unit { return }
}
fn recv(take v: Vec(Res)) -> I32 {
 using local = v
 let n = local.len()
 if n != 1 { return 7 }
 return 0
}
fn main() -> I32 {
 let v = Vec.new(Res)
 v.push(Res(n: 1))
 recv(v)
 return 0
}
`,
		"vec-drain-empty.al": `type Res {
 n: U64
}
impl Cleanup for Res {
 fn cleanup(take self) -> Unit { return }
}
fn main() -> I32 {
 let v = Vec.new(Res)
 using w = v
 if w.len() != 0 { return 1 }
 return 0
}
`,
		"vec-from-array.al": `type Res {
 n: U64
}
impl Cleanup for Res {
 fn cleanup(take self) -> Unit { return }
}
fn main() -> I32 {
 let a = [Res(n: 3), Res(n: 4)]
 let v = Vec.from_array(Res, a)
 using w = v
 if w.len() != 2 { return 1 }
 return 0
}
`,
	}
	for name, source := range accept {
		t.Run(name, func(t *testing.T) {
			files := map[string]string{name: source}
			first := runAlderChecker(t, exe, files, []string{name}, false)
			second := runAlderChecker(t, exe, files, []string{name}, false)
			if first != second {
				t.Fatalf("accept %s was not process deterministic", name)
			}
			m := parseCheckerManifest(t, first, files)
			if len(m.diagnostics) != 0 {
				t.Fatalf("accept %s diagnostics=%+v", name, m.diagnostics)
			}
		})
	}
	rejections := []struct {
		name, source string
		code         int
	}{
		{"vec-get-affine", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit {\n let v = Vec.new(Res)\n let one = v.get(0)\n return\n}\n", 141},
		{"vec-slice-affine", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit {\n let v = Vec.new(Res)\n let view = v.slice(0, 1)\n return\n}\n", 141},
		{"vec-push-after-registration", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit {\n let v = Vec.new(Res)\n v.push(Res(n: 1))\n using w = v\n w.push(Res(n: 2))\n return\n}\n", 142},
		{"vec-push-registered-binding", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit {\n using w = Vec.new(Res)\n w.push(Res(n: 1))\n return\n}\n", 142},
		{"vec-table-element", "fn f() -> Unit { let v = Vec.new(Table(U64)) }\n", 143},
		{"vec-copyable-using", "fn f() -> Unit { using w = Vec.new(U64) }\n", 136},
		{"vec-untransferred", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit { let v = Vec.new(Res) }\n", 93},
		{"vec-use-after-push", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f() -> Unit {\n let r = Res(n: 1)\n let v = Vec.new(Res)\n v.push(r)\n let gone = r.n\n return\n}\n", 91},
		{"vec-push-borrow-param", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn f(v: Vec(Res)) -> Unit {\n v.push(Res(n: 1))\n return\n}\n", 101},
		{"vec-scoped-element", "type Box { view: [U64] }\nfn f() -> Unit { let v = Vec.new(Box) }\n", 100},
	}
	for _, tc := range rejections {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{tc.name + ".al": tc.source}
			m := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true), files)
			if len(m.diagnostics) != 1 || m.diagnostics[0].kind != tc.code {
				t.Fatalf("diagnostics = %+v, want code %d", m.diagnostics, tc.code)
			}
		})
	}
}
