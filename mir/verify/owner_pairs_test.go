package verify

import (
	"strings"
	"testing"
)

// A storage-model signature pairs every safe_mut parameter with the owner
// domain that follows it. The same rule applies to function types used by
// fn.value and call.value; signatures without domain handles are outside the
// storage model and need no owner.
func TestOwnerDomainPairing(t *testing.T) {
	t.Parallel()
	valid := `mir 6

const @zero: u64 = 0

fn @bump(%__domain: domain_handle, %self: safe_mut(u64), %__owner_0: domain_handle) {
bb0:
  return
}

fn @thunk(%x: u64, %alder_env: safe_mut(u64)) -> u64 {
bb0:
  return %x
}

fn @indirect(%f: function(fn(safe_mut(u64), domain_handle) -> u64)) -> u64 {
bb0:
  %zero = const.get @zero
  return %zero
}
`
	if errs := Module(mustParse(t, valid)); len(errs) != 0 {
		t.Fatalf("valid owner pair rejected: %s", Errors(errs).String())
	}

	invalid := `mir 6

const @zero: u64 = 0

fn @bump(%__domain: domain_handle, %self: safe_mut(u64)) {
bb0:
  return
}
`
	errs := Module(mustParse(t, invalid))
	if len(errs) == 0 || !strings.Contains(Errors(errs).String(), "safe_mut parameter requires an owner domain parameter") {
		t.Fatalf("missing owner pair was not rejected: %s", Errors(errs).String())
	}

	invalidType := `mir 6

const @zero: u64 = 0

fn @indirect(%f: function(fn(domain_handle, safe_mut(u64)) -> u64)) -> u64 {
bb0:
  %zero = const.get @zero
  return %zero
}
`
	errs = Module(mustParse(t, invalidType))
	if len(errs) == 0 || !strings.Contains(Errors(errs).String(), "safe_mut parameter requires an owner domain parameter") {
		t.Fatalf("missing function-type owner pair was not rejected: %s", Errors(errs).String())
	}
}
