package compiler

import (
	"testing"
)

// M7.5 table identity: the source Table(T)/T.Id surface is exercised through
// the Alder-written checker only. The Go oracle has no table surface, so these
// programs stay out of the shared Go-comparison corpora.

func runAlderM75TableCheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"tables.al": `type Player {
 name: String
 age: U64
}
fn age_of(players: Table(Player), id: Player.Id) -> U64 {
 return match players.get(id) {
  Some(player) => player.age
  None => 0
 }
}
fn rename(mut players: Table(Player), id: Player.Id) -> Unit {
 match players.get_mut(id) {
  Some(player) => { player.age = 5 }
  None => {}
 }
 return
}
fn main() -> I32 {
 using players = Table.new(Player)
 let first = players.insert(Player(name: "a", age: 1))
 let second = players.insert(Player(name: "b", age: 2))
 if age_of(players, first) != 1 { return 1 }
 rename(players, second)
 if age_of(players, second) != 5 { return 2 }
 if players.remove(first) { } else { return 3 }
 if age_of(players, first) != 0 { return 4 }
 let third = players.insert(Player(name: "c", age: 3))
 if age_of(players, first) != 0 { return 5 }
 if age_of(players, third) != 3 { return 6 }
 return 0
}
`,
		"table-generic.al": `fn with_row(T: type, take players: Table(T), value: T) -> Table(T) {
 let id = players.insert(value)
 return players
}
type Row {
 n: U64
}
fn main() -> I32 {
 using rows = Table.new(Row)
 using cycled = with_row(Row, rows, Row(n: 1))
 return 0
}
`,
		"cleanup-trait.al": `import c counter: fn(U64) -> Unit
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
fn relay(take r: Res) -> Res { return r }
fn main() -> I32 {
 using r = make(7)
 relay(r)
 using late = make(9)
 if late.n != 9 { return 1 }
 return 0
}
`,
		"cleanup-affine-record.al": `type Guard {
 table: Table(U64)
}
impl Cleanup for Guard {
 fn cleanup(take self) -> Unit { return }
}
fn main() -> I32 {
 using t = Table.new(U64)
 using g = Guard(table: t)
 return 0
}
`,
		"table-compose.al": `type Holder {
 table: Table(U64)
 n: U64
}
fn relay(take h: Holder) -> Holder { return h }
fn pass(take t: Table(U64)) -> Table(U64) { return t }
fn main() -> I32 {
 using t = Table.new(U64)
 let holder = Holder(table: t, n: 1)
 relay(holder)
 let u = Table.new(U64)
 let o: Option(Table(U64)) = Some(u)
 match o {
  Some(inside) => { pass(inside) }
  None => {}
 }
 return 0
}
`,
		"table-try-insert.al": `fn main() -> I32 {
 using players = Table.new(Vec(U64))
 var seeded: Vec(U64) = Vec.new(U64)
 seeded.push(7)
 let first = players.try_insert(seeded)
 var answer: U64 = 0
 match first {
  Ok(id) => { answer = 1 }
  Err(back) => {
   if back.len() != 1 { return 1 }
   answer = 2
  }
 }
 let spare = Vec.new(U64)
 let second = players.try_insert(spare)
 match second {
  Ok(id) => { answer = answer + 1 }
  Err(back) => {
   if back.len() != 0 { return 2 }
   answer = answer + 2
  }
 }
 if answer != 4 { return 3 }
 return 0
}
`,
		"table-transfer.al": `fn move_out() -> Table(U64) {
 using fresh = Table.new(U64)
 return fresh
}
fn main() -> I32 {
 using owned = move_out()
 using players = Table.new(U64)
 let id = players.insert(4)
 if owned.remove(id) { return 1 }
 if players.remove(id) { } else { return 2 }
 if players.remove(id) { return 3 }
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
		{"table-element-scoped", "type Box { view: [U64] }\nfn f() -> Unit { using t = Table.new(Box) }\n", 130},
		// M7.5 affine aggregate composition: construction transfers parts,
		// whole aggregates transfer, and affine scrutinees are consumed.
		{"aggregate-untransferred", "type Box {\n table: Table(U64)\n}\nfn main() -> I32 {\n using t = Table.new(U64)\n let box = Box(table: t)\n return 0\n}\n", 93},
		{"use-after-construction-transfer", "type Box {\n table: Table(U64)\n}\nfn main() -> I32 {\n using t = Table.new(U64)\n let box = Box(table: t)\n let id = t.insert(5)\n return 0\n}\n", 91},
		{"use-after-scrutinee-consumption", "fn pass(take t: Table(U64)) -> Table(U64) { return t }\nfn main() -> I32 {\n using t = Table.new(U64)\n let o: Option(Table(U64)) = Some(t)\n match o {\n  Some(inside) => { pass(inside) }\n  None => {}\n }\n let id = t.insert(5)\n return 0\n}\n", 91},
		{"table-insert-read-param", "fn f(t: Table(U64)) -> Unit { let id = t.insert(1) }\n", 131},
		{"table-getmut-read-param", "fn f(t: Table(U64), id: U64.Id) -> Unit {\n match t.get_mut(id) {\n  Some(v) => {}\n  None => {}\n }\n}\n", 131},
		{"table-lookup-binding", "fn f(t: Table(U64), id: U64.Id) -> Unit { let option = t.get(id) }\n", 104},
		{"table-lookup-discarded", "fn f(t: Table(U64), id: U64.Id) -> Unit { t.get(id) }\n", 132},
		{"table-lookup-wildcard", "fn f(t: Table(U64), id: U64.Id) -> U64 {\n return match t.get(id) { _ => 1 }\n}\n", 132},
		{"table-view-fallible-arm", "fn f(t: Table(U64), id: U64.Id) -> Unit {\n match t.get(id) {\n  Some(value) => { let doubled = 1 + 1 }\n  None => {}\n }\n}\n", 133},
		{"table-view-control-arm", "fn f(t: Table(U64), id: U64.Id, flag: Bool) -> Unit {\n match t.get(id) {\n  Some(value) => { if flag { let x = 1 } }\n  None => {}\n }\n}\n", 133},
		{"table-mixed-arms", "fn f(t: Table(U64), id: U64.Id) -> U64 {\n return match t.get(id) {\n  Some(value) => 1\n  None => {}\n }\n}\n", 135},
		{"table-mutation-under-view", "fn f(mut t: Table(U64), id: U64.Id) -> Unit {\n match t.get(id) {\n  Some(value) => { let fresh = t.insert(2) }\n  None => {}\n }\n}\n", 134},
		{"table-tryinsert-under-view", "fn f(mut t: Table(U64), id: U64.Id) -> Unit {\n match t.get(id) {\n  Some(value) => { let outcome = t.try_insert(2) }\n  None => {}\n }\n}\n", 134},
		// A nested lookup inside a view arm is structurally excluded by the
		// arm region rule (no nested match), so the exclusive-view overlap is
		// pinned through remove under a live view instead.
		{"table-remove-under-view", "fn f(mut t: Table(U64), id: U64.Id) -> Unit {\n match t.get(id) {\n  Some(value) => { let gone = t.remove(id) }\n  None => {}\n }\n}\n", 134},
		{"using-non-table", "fn f() -> Unit { using value = 5 }\n", 136},
		{"table-untransferred-let", "fn f() -> Unit { let t = Table.new(U64) }\n", 93},
		// The gated `with` clause is not rejected here: the corpus detector
		// runs any callback-form program under the private profile, where it
		// is legal again. The production qualification pins rejection 137.
		// The builtin AsyncCleanup trait is removed (D012): the name is
		// reserved, so implementing it is rejected as an unknown trait.
		{"async-cleanup-removed", "type Res {\n n: U64\n}\nimpl AsyncCleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn main() -> I32 { return 0 }\n", 108},
		{"cleanup-copyable-owner", "fn main() -> I32 {\n using value = 5\n return 0\n}\n", 136},
		{"cleanup-impl-affine-exit", "type Res {\n n: U64\n}\nimpl Cleanup for Res {\n fn cleanup(take self) -> Unit { return }\n}\nfn main() -> I32 {\n let r = Res(n: 1)\n return 0\n}\n", 93},
		{"table-using-partial-transfer", "fn relay(take t: Table(U64)) -> Table(U64) { return t }\nfn f(flag: Bool) -> Unit {\n using t = Table.new(U64)\n if flag { relay(t) }\n return\n}\n", 94},
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
