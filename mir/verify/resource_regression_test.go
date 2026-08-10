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
