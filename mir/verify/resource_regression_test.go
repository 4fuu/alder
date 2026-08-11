package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/aster/mir"
)

func verifyText(t *testing.T, text string) Errors {
	t.Helper()
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v", err)
	}
	return Module(m)
}

func requireRejectedWith(t *testing.T, text, want string) {
	t.Helper()
	errs := verifyText(t, text)
	if !strings.Contains(errs.String(), want) {
		t.Fatalf("missing diagnostic %q\n--- got ---\n%s", want, errs.String())
	}
}

func requireAccepted(t *testing.T, text string) {
	t.Helper()
	if errs := verifyText(t, text); len(errs) != 0 {
		t.Fatalf("unexpected diagnostics:\n%s", errs.String())
	}
}

func TestDefiniteLocalInitialization(t *testing.T) {
	const diagnostic = "load from local place that is not definitely initialized"

	t.Run("straight-line load before store", func(t *testing.T) {
		errs := verifyText(t, `mir 1
fn @f() -> i64 {
  local %x: i64
entry:
  %v = load local %x
  return %v
}
`)
		want := "fn @f: block entry: op load #0: " + diagnostic
		if errs.String() != want {
			t.Fatalf("diagnostic mismatch\n--- got ---\n%s\n--- want ---\n%s", errs.String(), want)
		}
	})

	t.Run("one branch missing store", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%value: i64, %cond: bool) -> i64 {
  local %x: i64
entry:
  branch %cond, set, skip
set:
  store local %x, %value
  jump join
skip:
  jump join
join:
  %v = load local %x
  return %v
}
`, diagnostic)
	})

	t.Run("both branches store", func(t *testing.T) {
		requireAccepted(t, `mir 1
fn @f(%a: i64, %b: i64, %cond: bool) -> i64 {
  local %x: i64
entry:
  branch %cond, left, right
left:
  store local %x, %a
  jump join
right:
  store local %x, %b
  jump join
join:
  %v = load local %x
  return %v
}
`)
	})

	t.Run("field-sensitive partial and complete", func(t *testing.T) {
		const header = `mir 1
type @Pair {
  first: i64
  second: i64
}
`
		requireRejectedWith(t, header+`fn @partial(%a: i64) -> @Pair {
  local %pair: @Pair
entry:
  store field(local %pair, first), %a
  %v = load local %pair
  return %v
}
`, diagnostic)
		requireAccepted(t, header+`fn @complete(%a: i64, %b: i64) -> @Pair {
  local %pair: @Pair
entry:
  store field(local %pair, first), %a
  store field(local %pair, second), %b
  %v = load local %pair
  return %v
}
`)
	})

	t.Run("whole aggregate and fields merge canonically", func(t *testing.T) {
		requireAccepted(t, `mir 1
type @Pair {
  first: i64
  second: i64
}
fn @f(%whole: @Pair, %a: i64, %b: i64, %cond: bool) -> @Pair {
  local %pair: @Pair
entry:
  branch %cond, whole, fields
whole:
  store local %pair, %whole
  jump join
fields:
  store field(local %pair, first), %a
  store field(local %pair, second), %b
  jump join
join:
  %v = load local %pair
  return %v
}
`)
	})

	t.Run("nested aggregate subtrees merge canonically", func(t *testing.T) {
		requireAccepted(t, `mir 1
type @Inner {
  x: i64
  y: i64
}
type @Outer {
  inner: @Inner
}
fn @f(%whole: @Inner, %x: i64, %y: i64, %cond: bool) -> @Outer {
  local %outer: @Outer
entry:
  branch %cond, whole, leaves
whole:
  store field(local %outer, inner), %whole
  jump join
leaves:
  store field(field(local %outer, inner), x), %x
  store field(field(local %outer, inner), y), %y
  jump join
join:
  %inner = load field(local %outer, inner)
  %result = load local %outer
  return %result
}
`)
	})

	t.Run("empty aggregate requires explicit store", func(t *testing.T) {
		const header = `mir 1
type @Empty {
}
`
		requireRejectedWith(t, header+`fn @unset() -> @Empty {
  local %empty: @Empty
entry:
  %value = load local %empty
  return %value
}
`, diagnostic)
		requireAccepted(t, header+`fn @set(%input: @Empty) -> @Empty {
  local %empty: @Empty
entry:
  store local %empty, %input
  %value = load local %empty
  return %value
}
`)
	})

	t.Run("loop backedge only store", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%value: i64, %again: bool) -> i64 {
  local %x: i64
entry:
  jump loop
loop:
  %v = load local %x
  store local %x, %value
  branch %again, loop, done
done:
  return %v
}
`, diagnostic)
	})

	t.Run("store before loop initializes every iteration", func(t *testing.T) {
		requireAccepted(t, `mir 1
fn @f(%value: i64, %again: bool) -> i64 {
  local %x: i64
entry:
  store local %x, %value
  jump loop
loop:
  %v = load local %x
  branch %again, loop, done
done:
  return %v
}
`)
	})
}

func TestDomainPathSensitiveRegressions(t *testing.T) {
	t.Run("branch reset then join use", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%root: domain_handle, %n: u64, %c: bool) {
entry:
  %d = domain.create %root
  %m = domain.mark %d
  %p = alloc %d, u8, %n
  branch %c, reset, keep
reset:
  domain.reset %d, %m
  jump join
keep:
  jump join
join:
  %x = load deref %p
  domain.destroy %d
  return
}
`, "use of %p after reset or destruction")
	})

	t.Run("branch destroy then join destroy", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%root: domain_handle, %c: bool) {
entry:
  %d = domain.create %root
  branch %c, kill, keep
kill:
  domain.destroy %d
  jump join
keep:
  jump join
join:
  domain.destroy %d
  return
}
`, "domain may already be destroyed on an incoming path")
	})

	t.Run("loop double destroy", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%root: domain_handle, %again: bool) {
entry:
  %d = domain.create %root
  jump loop
loop:
  domain.destroy %d
  branch %again, loop, done
done:
  return
}
`, "domain may already be destroyed on an incoming path")
	})

	t.Run("parameter domain", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%d: domain_handle, %n: u64) {
entry:
  %p = alloc %d, u8, %n
  domain.destroy %d
  %x = load deref %p
  return
}
`, "use of %p after reset or destruction")
	})
}

func TestInterproceduralDomainRegressions(t *testing.T) {
	t.Run("callee destroys caller domain", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @kill(%d: domain_handle) {
entry:
  domain.destroy %d
  return
}
fn @f(%root: domain_handle, %n: u64) {
entry:
  %d = domain.create %root
  %p = alloc %d, u8, %n
  call @kill(%d)
  %x = load deref %p
  return
}
`, "use of %p after reset or destruction")
	})

	t.Run("callee allocates return", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @make(%d: domain_handle, %n: u64) -> safe_mut(u8) {
entry:
  %p = alloc %d, u8, %n
  return %p
}
fn @f(%root: domain_handle, %n: u64) {
entry:
  %d = domain.create %root
  %p = call @make(%d, %n)
  domain.destroy %d
  %x = load deref %p
  return
}
`, "use of %p after reset or destruction")
	})

	pass := `mir 1
fn @pass(%tag: i64, %r: safe_mut(u8)) -> safe_mut(u8) {
entry:
  return %r
}
fn @f(%root: domain_handle, %n: u64, %tag: i64) {
entry:
  %d = domain.create %root
  %p = alloc %d, u8, %n
  %q = call @pass(%tag, %p)
  %x = load deref %q
  domain.destroy %d
  return
}
`
	t.Run("passthrough live", func(t *testing.T) { requireAccepted(t, pass) })
	t.Run("passthrough invalidated", func(t *testing.T) {
		invalid := strings.Replace(pass, "  %x = load deref %q\n  domain.destroy %d", "  domain.destroy %d\n  %x = load deref %q", 1)
		requireRejectedWith(t, invalid, "use of %q after reset or destruction")
	})

	t.Run("recursive summary", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @kill_recursive(%d: domain_handle, %stop: bool) {
entry:
  branch %stop, base, recur
base:
  domain.destroy %d
  return
recur:
  call @kill_recursive(%d, %stop)
  return
}
fn @f(%root: domain_handle, %n: u64, %stop: bool) {
entry:
  %d = domain.create %root
  %p = alloc %d, u8, %n
  call @kill_recursive(%d, %stop)
  %x = load deref %p
  return
}
`, "use of %p after reset or destruction")
	})
}

func TestCleanupCallbackLifetimeRegressions(t *testing.T) {
	const callbackPrefix = `mir 1
fn @read(%p: safe_mut(u8)) {
entry:
  %x = load deref %p
  return
}
`
	t.Run("callback argument invalid", func(t *testing.T) {
		requireRejectedWith(t, callbackPrefix+`fn @f(%root: domain_handle, %n: u64) {
entry:
  %s = cleanup.scope.begin
  %d = domain.create %root
  %p = alloc %d, u8, %n
  %e = cleanup.push %s, @read, (%p)
  domain.destroy %d
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`, "cleanup callback uses %p after reset or destruction")
	})

	t.Run("disarmed callback", func(t *testing.T) {
		requireAccepted(t, callbackPrefix+`fn @f(%root: domain_handle, %n: u64) {
entry:
  %s = cleanup.scope.begin
  %d = domain.create %root
  %p = alloc %d, u8, %n
  %e = cleanup.push %s, @read, (%p)
  cleanup.disarm %e
  domain.destroy %d
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`)
	})

	t.Run("callback effect reaches caller", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @destroy(%d: domain_handle) {
entry:
  domain.destroy %d
  return
}
fn @wrapped(%d: domain_handle) {
entry:
  %s = cleanup.scope.begin
  %e = cleanup.push %s, @destroy, (%d)
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
fn @f(%root: domain_handle, %n: u64) {
entry:
  %d = domain.create %root
  %p = alloc %d, u8, %n
  call @wrapped(%d)
  %x = load deref %p
  return
}
`, "use of %p after reset or destruction")
	})
}

func TestDomainAliasAndMemoryProvenance(t *testing.T) {
	t.Run("mark accepts block parameter alias", func(t *testing.T) {
		requireAccepted(t, `mir 1
fn @f(%root: domain_handle) {
entry:
  %d = domain.create %root
  %m = domain.mark %d
  jump reset(%d)
reset(%alias: domain_handle):
  domain.reset %alias, %m
  domain.destroy %alias
  return
}
`)
	})

	t.Run("local fields stay distinct", func(t *testing.T) {
		requireAccepted(t, `mir 1
type @Box {
  local: safe_mut(u8)
  caller: safe_mut(u8)
}
fn @f(%caller_domain: domain_handle, %n: u64) -> safe_mut(u8) {
  local %box: @Box
entry:
  %d = domain.create %caller_domain
  %local = alloc %d, u8, %n
  %caller = alloc %caller_domain, u8, %n
  store field(local %box, local), %local
  store field(local %box, caller), %caller
  %result = load field(local %box, caller)
  domain.destroy %d
  return %result
}
`)
	})

	t.Run("deref store retains nested provenance", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
type @Box {
  r: safe_mut(u8)
}
fn @f(%root: domain_handle, %n: u64) {
entry:
  %outer = domain.create %root
  %inner = domain.create %root
  %boxp = alloc %outer, @Box, %n
  %r = alloc %inner, u8, %n
  %box = aggregate.construct @Box { r: %r }
  store deref %boxp, %box
  domain.destroy %inner
  %loaded = load field(deref %boxp, r)
  %x = load deref %loaded
  domain.destroy %outer
  return
}
`, "use of %loaded after reset or destruction")
	})

	t.Run("parallel edges retain every argument", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%root: domain_handle, %n: u64, %a: i64) {
entry:
  %d1 = domain.create %root
  %d2 = domain.create %root
  %p1 = alloc %d1, u8, %n
  %sum = int.add.checked %a, %a else join(%p1)
  %p2 = alloc %d2, u8, %n
  domain.destroy %d2
  jump join(%p2)
join(%r: safe_mut(u8)):
  %x = load deref %r
  return
}
`, "use of %r after reset or destruction")
	})
}

func TestDomainLoopInstancePolicy(t *testing.T) {
	t.Run("per iteration domain", func(t *testing.T) {
		requireAccepted(t, `mir 1
const @zero: u8 = 0
fn @f(%root: domain_handle, %n: u64, %again: bool) {
entry:
  jump loop
loop:
  %d = domain.create %root
  %p = alloc %d, u8, %n
  %z = const.get @zero
  store deref %p, %z
  domain.destroy %d
  branch %again, loop, done
done:
  return
}
`)
	})

	t.Run("local handle across backedge", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%root: domain_handle, %again: bool) {
entry:
  jump loop(%root)
loop(%parent: domain_handle):
  %child = domain.create %parent
  branch %again, loop(%child), done
done:
  return
}
`, "carries a function-local domain handle or reference across a backedge")
	})
}

func TestDomainFunctionBoundaryConservatism(t *testing.T) {
	t.Run("deref write of reference is rejected", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
type @Box {
  r: safe_mut(u8)
}
fn @stash(%out: safe_mut(@Box), %root: domain_handle, %n: u64) {
entry:
  %d = domain.create %root
  %p = alloc %d, u8, %n
  %box = aggregate.construct @Box { r: %p }
  store deref %out, %box
  domain.destroy %d
  return
}
`, "lifetime-bearing values may not be stored through dereference places")
	})

	t.Run("external domain parameters may alias", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%a: domain_handle, %b: domain_handle, %n: u64) {
entry:
  %p = alloc %b, u8, %n
  domain.destroy %a
  %x = load deref %p
  return
}
`, "use of %p after reset or destruction")
	})

	t.Run("aggregate handle and reference stay related", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
type @Bundle {
  d: domain_handle
  r: safe_mut(u8)
}
fn @f(%bundle: @Bundle) {
  local %slot: @Bundle

entry:
  store local %slot, %bundle
  %d = load field(local %slot, d)
  %r = load field(local %slot, r)
  domain.destroy %d
  %x = load deref %r
  return
}
`, "use of %r after reset or destruction")
	})

	t.Run("table depends on possible domain parameter", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
type @P {
  x: i64
}
fn @f(%t: table(@P), %d: domain_handle, %p: @P) {
entry:
  domain.destroy %d
  %id = table.insert %t, %p
  return
}
`, "use of %t after reset or destruction")
	})
}

func TestCleanupPathSensitiveRegressions(t *testing.T) {
	t.Run("branch local scope leaks", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @close() {
entry:
  return
}
fn @f(%choose: bool) {
entry:
  branch %choose, open, skip
open:
  %s = cleanup.scope.begin
  %e = cleanup.push %s, @close, ()
  jump join
skip:
  jump join
join:
  return
}
`, "exit leaves cleanup scope %s open or running")
	})

	t.Run("checked failure leaves before push", func(t *testing.T) {
		requireAccepted(t, `mir 1
fn @close() {
entry:
  return
}
fn @f(%a: i64) {
entry:
  %s = cleanup.scope.begin
  %sum = int.add.checked %a, %a else failed
  %e = cleanup.push %s, @close, ()
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
failed:
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`)
	})
}

func TestResetConsumesMarksAndTables(t *testing.T) {
	t.Run("empty-domain mark resets later allocations", func(t *testing.T) {
		requireAccepted(t, `mir 1
fn @f(%root: domain_handle, %n: u64) {
entry:
  %d = domain.create %root
  %m = domain.mark %d
  %p = alloc %d, u8, %n
  domain.reset %d, %m
  domain.destroy %d
  return
}
`)
	})

	t.Run("reset consumes later mark", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%root: domain_handle, %n: u64) {
entry:
  %d = domain.create %root
  %p0 = alloc %d, u8, %n
  %m1 = domain.mark %d
  %p1 = alloc %d, u8, %n
  %m2 = domain.mark %d
  domain.reset %d, %m1
  %p2 = alloc %d, u8, %n
  domain.reset %d, %m2
  domain.destroy %d
  return
}
`, "use of %m2 after reset or destruction")
	})

	t.Run("reset invalidates table with hidden post-mark storage", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
type @P {
  x: i64
}
fn @f(%root: domain_handle, %p: @P) {
entry:
  %d = domain.create %root
  %t = table.create @P, %d
  %m = domain.mark %d
  %id = table.insert %t, %p
  domain.reset %d, %m
  %opt = table.lookup %t, %id
  switch %opt {
    some(%view) -> found
    none -> absent
  }
found:
  %x = load field(deref %view, x)
  table.view.end %view
  domain.destroy %d
  return
absent:
  domain.destroy %d
  return
}
`, "use of %t after reset or destruction")
	})

	t.Run("reset consumes marks of aliasing external domains", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @f(%a: domain_handle, %b: domain_handle) {
entry:
  %ma = domain.mark %a
  %mb = domain.mark %b
  domain.reset %a, %ma
  domain.reset %b, %mb
  return
}
`, "use of %mb after reset or destruction")
	})

	t.Run("summarized reset consumes caller mark aliases", func(t *testing.T) {
		requireRejectedWith(t, `mir 1
fn @reset(%d: domain_handle) {
entry:
  %m = domain.mark %d
  domain.reset %d, %m
  return
}
fn @f(%a: domain_handle, %b: domain_handle) {
entry:
  %mb = domain.mark %b
  %u = call @reset(%a)
  domain.reset %b, %mb
  return
}
`, "use of %mb after reset or destruction")
	})
}
