package verify

import (
	"testing"
)

// A place-based cleanup registration names the owner local, and the hook's
// owner parameter is the last argument: a hook emitted for a function with
// storage carries a hidden leading domain parameter.
func TestCleanupPlaceOwnerParameterIsLast(t *testing.T) {
	requireAccepted(t, `mir 1
fn @cleanup(%d: domain_handle, %x: i64) {
entry:
  domain.destroy %d
  return
}
fn @f(%d: domain_handle, %x: i64) {
  local %slot: i64
entry:
  store local %slot, %x
  %s = cleanup.scope.begin
  %id = cleanup.push %s, @cleanup, (%d, %x) place local %slot
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`)
}

func TestCleanupPlaceTypeMustMatchOwner(t *testing.T) {
	requireRejectedWith(t, `mir 1
fn @cleanup(%x: i64) {
entry:
  return
}
fn @f(%x: i64, %b: bool) {
  local %slot: bool
entry:
  store local %slot, %b
  %s = cleanup.scope.begin
  %id = cleanup.push %s, @cleanup, (%x) place local %slot
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`, "cleanup.push place type differs from the owner parameter")
}

// The hook loads the registered local when the scope exits, so a whole-local
// store while that registration is armed would replace the owner behind the
// hook's back. Field stores through a borrow remain legal (they are how a
// `mut self` method updates the owner).
func TestCleanupPlaceCannotBeReassignedWhileArmed(t *testing.T) {
	requireRejectedWith(t, `mir 1
fn @cleanup(%x: i64) {
entry:
  return
}
fn @f(%x: i64, %y: i64) {
  local %slot: i64
entry:
  store local %slot, %x
  %s = cleanup.scope.begin
  %id = cleanup.push %s, @cleanup, (%x) place local %slot
  store local %slot, %y
  cleanup.scope.run %s
  cleanup.scope.end %s
  return
}
`, "cleanup registration's owner local cannot be reassigned while registered")
}
