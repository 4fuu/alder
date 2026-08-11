package verify

import (
	"testing"

	"github.com/4fuu/alder/mir"
)

func TestCleanupActiveEntriesAtRun(t *testing.T) {
	text := `mir 1
fn @drop(%x: i64) {
bb0:
  return
}
fn @f(%x: i64, %choose: bool) {
entry:
  %s = cleanup.scope.begin
  %always = cleanup.push %s, @drop, (%x)
  %gone = cleanup.push %s, @drop, (%x)
  cleanup.disarm %gone
  branch %choose, optional, join
optional:
  %maybe = cleanup.push %s, @drop, (%x)
  jump join
join:
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatal(err)
	}
	a, errs := analyzeCleanupFunction(m, m.Functions[1])
	if len(errs) != 0 {
		t.Fatalf("analysis errors: %s", Errors(errs).String())
	}
	got := a.activeEntriesAtRun(cleanupSite{blk: 2, in: 0})
	if len(got) != 2 {
		t.Fatalf("active entries = %d, want always and may-active", len(got))
	}
	if got[0].ID == got[1].ID || len(got[0].Args) != 1 || len(got[1].Args) != 1 {
		t.Fatalf("bad active entries: %#v", got)
	}
}

func TestCleanupRunPreservesPathAlternatives(t *testing.T) {
	requireAccepted(t, `mir 1
fn @destroy(%d: domain_handle) {
entry:
  domain.destroy %d
  return
}
fn @f(%d: domain_handle, %choose: bool) {
entry:
  %s = cleanup.scope.begin
  branch %choose, left, right
left:
  %l = cleanup.push %s, @destroy, (%d)
  jump join
right:
  %r = cleanup.push %s, @destroy, (%d)
  jump join
join:
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`)
}

func TestCleanupRunUsesRuntimeRegistrationOrder(t *testing.T) {
	requireAccepted(t, `mir 1
fn @destroy(%d: domain_handle) {
entry:
  domain.destroy %d
  return
}
fn @f(%parent: domain_handle) {
entry:
  %child = domain.create %parent
  %s = cleanup.scope.begin
  jump push_parent
push_child:
  %c = cleanup.push %s, @destroy, (%child)
  jump run
push_parent:
  %p = cleanup.push %s, @destroy, (%parent)
  jump push_child
run:
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`)
}

func TestCleanupPushCannotRepeatWhileActive(t *testing.T) {
	requireRejectedWith(t, `mir 1
fn @drop(%x: i64) {
entry:
  return
}
fn @f(%x: i64, %again: bool) {
entry:
  %s = cleanup.scope.begin
  jump loop
loop:
  %id = cleanup.push %s, @drop, (%x)
  branch %again, loop, run
run:
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`, "cleanup.push cannot execute again while its previous registration is active")
}
