package compiler

import (
	"testing"
)

// D018 match guards: an `if` guard runs after its pattern matches, a false
// guard continues with the next arm, a guarded arm never counts toward
// exhaustiveness, and a guard only borrows the arm's bindings. Same-variant
// arms form one contiguous run so a false guard falls through a straight
// edge. The Go oracle has no guard surface, so these programs stay out of the
// shared Go-comparison corpora.

func runAlderM75GuardCheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"guard-chain.al": `fn classify(v: U64) -> U64 {
 let wrapped: Option(U64) = Some(v)
 return match wrapped {
  Some(n) if n > 100 => 1
  Some(n) if n > 10 => 2
  _ => 3
 }
}
fn main() -> I32 {
 if classify(500) != 1 { return 1 }
 if classify(50) != 2 { return 2 }
 if classify(5) != 3 { return 3 }
 return 0
}
`,
		"guard-variant-runs.al": `fn pick(o: Option(U64)) -> U64 {
 return match o {
  Some(v) if v == 0 => 10
  Some(v) if v < 10 => 20
  Some(v) => 30
  None => 40
 }
}
fn main() -> I32 {
 if pick(Some(0)) != 10 { return 1 }
 if pick(Some(5)) != 20 { return 2 }
 if pick(Some(99)) != 30 { return 3 }
 if pick(None) != 40 { return 4 }
 return 0
}
`,
		"guard-wildcard-fallback.al": `fn drop_guard(o: Option(U64), flag: Bool) -> U64 {
 return match o {
  Some(v) if flag => v
  _ => 0
 }
}
fn main() -> I32 {
 if drop_guard(Some(7), true) != 7 { return 1 }
 if drop_guard(Some(7), false) != 0 { return 2 }
 return 0
}
`,
		"guard-statement-arm.al": `fn f(o: Option(U64)) -> I32 {
 match o {
  Some(v) if v > 3 => { let doubled = v + v }
  _ => {}
 }
 return 0
}
fn main() -> I32 { return 0 }
`,
		"guard-short-circuit.al": `fn f(p: Bool) -> U64 {
 let o: Option(U64) = Some(4)
 return match o {
  Some(v) if p && v > 3 => 1
  Some(v) if !p => 2
  Some(v) => 3
  None => 4
 }
}
fn main() -> I32 {
 if f(true) != 1 { return 1 }
 if f(false) != 2 { return 2 }
 return 0
}
`,
		"guard-result.al": `fn label(r: Result(U64, U64)) -> U64 {
 return match r {
  Ok(v) if v == 0 => 1
  Ok(v) => 2
  Err(e) if e > 5 => 3
  Err(e) => 4
 }
}
fn main() -> I32 {
 if label(Ok(0)) != 1 { return 1 }
 if label(Ok(9)) != 2 { return 2 }
 if label(Err(9)) != 3 { return 3 }
 if label(Err(1)) != 4 { return 4 }
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
		// A guard must be a Bool expression (arm mismatch kind 77).
		{"guard-not-bool", "fn f(o: Option(U64)) -> U64 {\n return match o {\n  Some(v) if v => 1\n  _ => 2\n }\n}\nfn main() -> I32 { return 0 }\n", 77},
		// A guard only borrows: transferring the affine payload out of the
		// binding inside the guard is rejected.
		{"guard-consumes-binding", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn drain_ok(take v: Res) -> Bool {\n using held = v\n return true\n}\nfn f(o: Option(Res)) -> U64 {\n return match o {\n  Some(v) if drain_ok(v) => 1\n  _ => 2\n }\n}\nfn main() -> I32 { return 0 }\n", 148},
		// A table-view arm's region is one straight-line fail-free block, so
		// its arm cannot carry a guard.
		{"guard-view-arm", "fn f(t: Table(U64), id: U64.Id) -> U64 {\n return match t.get(id) {\n  Some(v) if v.n > 1 => 1\n  None => 2\n }\n}\nfn main() -> I32 { return 0 }\n", 149},
		// A guarded arm never counts toward exhaustiveness.
		{"guard-not-exhaustive", "fn f(o: Option(U64), p: Bool) -> U64 {\n return match o {\n  Some(v) if p => 1\n }\n}\nfn main() -> I32 { return 0 }\n", 79},
		// An unguarded arm for a variant makes later same-variant arms
		// unreachable.
		{"guard-duplicate-after-unguarded", "fn f(o: Option(U64), p: Bool) -> U64 {\n return match o {\n  Some(v) if p => 1\n  Some(w) => 2\n  Some(x) => 3\n }\n}\nfn main() -> I32 { return 0 }\n", 72},
		// Same-variant arms must stay contiguous so a false guard falls
		// through one straight edge chain.
		{"guard-non-contiguous", "fn f(o: Option(U64), p: Bool) -> U64 {\n return match o {\n  Some(v) if p => 1\n  None => 9\n  Some(w) => 2\n }\n}\nfn main() -> I32 { return 0 }\n", 72},
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
