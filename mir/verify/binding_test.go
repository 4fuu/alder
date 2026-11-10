package verify

import (
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// mustReject parses text (which must succeed) and verifies it; it fails
// unless verification rejects the module with an error containing want.
func mustReject(t *testing.T, text, want string) {
	t.Helper()
	m, err := mir.Parse(text)
	if err != nil {
		t.Fatalf("parse fixture: %v\n%s", err, text)
	}
	errs := Module(m)
	if len(errs) == 0 {
		t.Fatalf("module accepted, want rejection containing %q:\n%s", want, text)
	}
	if !containsMsg(errs, want) {
		t.Fatalf("rejection %q does not mention %q:\n%s", Errors(errs).String(), want, text)
	}
}

// mustFailParse expects text to be rejected at parse time with an error
// containing want.
func mustFailParse(t *testing.T, text, want string) {
	t.Helper()
	if _, err := mir.Parse(text); err == nil {
		t.Fatalf("fixture parsed, want parse error containing %q:\n%s", want, text)
	} else if !strings.Contains(err.Error(), want) {
		t.Fatalf("parse error %q does not mention %q:\n%s", err.Error(), want, text)
	}
}

func TestBindingBlocksAccepted(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type opaque @clockid = "clockid_t"
  c_type scalar @sec = "time_t"
  c_fn @ticks = "clock"() -> @clockid
  c_const @cps = "CLOCKS_PER_SEC": c_size
}

const @n0: u64 = 0

fn @main() -> u64 {
bb0:
  %r = c.call.unsafe @sys.ticks()
  %u = const.get @n0
  return %u
}
`
	if errs := Module(mustParse(t, text)); len(errs) != 0 {
		t.Fatalf("binding block accepted module rejected: %s", Errors(errs).String())
	}
}

func TestBindingScalarPtrAndConstPtr(t *testing.T) {
	const text = `mir 6

binding @libc "stdlib.h" {
  c_type scalar @len = "size_t"
  c_fn @alloc = "malloc"(@len) -> c_ptr(u8)
  c_fn @cmp = "memcmp"(c_const_ptr(u8), c_const_ptr(u8), @len) -> @len
  c_fn @release = "free"(c_ptr(u8)) -> unit
}

fn @main(%n: @len) -> @len {
bb0:
  %p = c.call.unsafe @libc.alloc(%n)
  %m = c.call.unsafe @libc.cmp(%p, %p, %n)
  %b = c.is_null %p
  c.call.unsafe @libc.release(%p)
  return %m
}
`
	if errs := Module(mustParse(t, text)); len(errs) != 0 {
		t.Fatalf("raw pointer binding module rejected: %s", Errors(errs).String())
	}
}

func TestBindingConstPtrWideningAccepted(t *testing.T) {
	const text = `mir 6

binding @libc "string.h" {
  c_fn @len = "strlen"(c_const_ptr(u8)) -> c_size
}

fn @probe(%p: c_ptr(u8), %q: c_const_ptr(u8)) -> c_size {
bb0:
  %a = c.call.unsafe @libc.len(%p)
  %b = c.call.unsafe @libc.len(%q)
  return %b
}
`
	if errs := Module(mustParse(t, text)); len(errs) != 0 {
		t.Fatalf("c_ptr to c_const_ptr widening rejected: %s", Errors(errs).String())
	}
}

func TestRawTypeRejectedInAlloc(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type scalar @sec = "time_t"
}

fn @main(%d: domain_handle, %n: u64) -> u64 {
bb0:
  %s = alloc %d, c_size, %n
  return %n
}
`
	mustReject(t, text, "element type")

}

func TestRawTypeRejectedInTable(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type scalar @sec = "time_t"
}

type @Rec {
  at: c_size
}

fn @main(%d: domain_handle) -> u64 {
bb0:
  %t = table.create @Rec, %d
  return %d
}
`
	mustReject(t, text, "element type")

}

func TestRawTypeRejectedInCopyToDomain(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type scalar @sec = "time_t"
}

binding @libc "stdlib.h" {
  c_fn @alloc = "malloc"(c_size) -> c_ptr(u8)
}

const @k0: u64 = 0

fn @main(%d: domain_handle, %n: c_size) -> u64 {
bb0:
  %p = c.call.unsafe @libc.alloc(%n)
  %m = copy_to_domain %d, %p
  %k = const.get @k0
  return %k
}
`
	mustReject(t, text, "copy_to_domain source type")

}

func TestRawTypeRejectedInSlice(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type scalar @sec = "time_t"
}

fn @main(%d: domain_handle, %n: u64) -> u64 {
bb0:
  %s = alloc %d, slice(c_size), %n
  return %n
}
`
	mustReject(t, text, "element type")

}

func TestBindingNamedTypeOutsideBlockRejected(t *testing.T) {
	const text = `mir 6

fn @main() -> u64 {
bb0:
  return 0
}

fn @f(%c: @missing) -> u64 {
bb0:
  return 0
}
`
	mustFailParse(t, text, "unknown type @missing")

}

func TestDuplicateBindingBlockRejected(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_fn @now = "clock"() -> u64
}

binding @sys "stdio.h" {
  c_fn @say = "puts"(c_const_ptr(u8)) -> @len
}
`
	mustFailParse(t, text, "duplicate binding @sys")

}

func TestDuplicateBindingMemberRejected(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_fn @now = "clock"() -> u64
  c_fn @now = "time"() -> u64
}
`
	mustFailParse(t, text, "duplicate binding function @now")

}

func TestBindingSpellingRejectedAsKeyword(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_fn @now = "return"() -> u64
}
`
	mustReject(t, text, "C spelling must be a non-reserved C identifier")

}

func TestBindingSpellingRejectedAsUnderscore(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_fn @now = "_private"() -> u64
}
`
	mustReject(t, text, "C spelling must be a non-reserved C identifier")

}

func TestBindingUnitResultUnbound(t *testing.T) {
	const text = `mir 6

binding @sys "stdlib.h" {
  c_fn @release = "free"(c_ptr(u8)) -> unit
}

const @k0: u64 = 0

fn @main(%p: c_ptr(u8)) -> u64 {
bb0:
  c.call.unsafe @sys.release(%p)
  %k = const.get @k0
  return %k
}
`
	if errs := Module(mustParse(t, text)); len(errs) != 0 {
		t.Fatalf("dropped unit-result c.call.unsafe rejected: %s", Errors(errs).String())
	}
}

func TestBindingCallArgumentTypeRejected(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type opaque @clockid = "clockid_t"
  c_fn @start = "clock"(@clockid) -> @clockid
}

const @k0: u64 = 0

fn @main() -> u64 {
bb0:
  %v = const.get @k0
  %r = c.call.unsafe @sys.start(%v)
  return %r
}
`
	mustReject(t, text, "c argument 0")

}

func TestBindingCallConstPtrNotWidenedBackRejected(t *testing.T) {
	const text = `mir 6

binding @libc "stdlib.h" {
  c_fn @grow = "realloc"(c_ptr(u8), c_size) -> c_ptr(u8)
}

fn @probe(%q: c_const_ptr(u8)) -> c_ptr(u8) {
bb0:
  %r = c.call.unsafe @libc.grow(%q, %q)
  return %r
}
`
	mustReject(t, text, "c argument 0")

}

func TestBindingCallUnknownMemberRejected(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_fn @now = "clock"() -> u64
}

fn @main() -> u64 {
bb0:
  %r = c.call.unsafe @sys.later()
  return %r
}
`
	mustFailParse(t, text, "unknown binding function @sys.later")
}

func TestIsNullOnNonPointerRejected(t *testing.T) {
	const text = `mir 6

binding @sys "time.h" {
  c_type scalar @sec = "time_t"
  c_fn @now = "clock"() -> @sec
}

fn @main() -> u64 {
bb0:
  %t = c.call.unsafe @sys.now()
  %b = c.is_null %t
  return %b
}
`
	mustReject(t, text, "c.is_null")

}

func TestIsNullOnRawPointerAccepted(t *testing.T) {
	const text = `mir 6

binding @libc "stdlib.h" {
  c_type scalar @len = "size_t"
  c_fn @alloc = "malloc"(@len) -> c_ptr(u8)
}

const @n0: u64 = 0

fn @probe(%r: raw_ptr(u64), %q: c_const_ptr(u8), %nlen: @len, %d: domain_handle) -> u64 {
bb0:
  %v = const.get @n0
  %p = c.call.unsafe @libc.alloc(%nlen)
  %b2 = c.is_null %p
  %b3 = c.is_null %q
  %b4 = c.is_null %r
  return %v
}
`
	if errs := Module(mustParse(t, text)); len(errs) != 0 {
		t.Fatalf("c.is_null on raw/legacy pointers rejected:\n%s", Errors(errs).String())
	}
}
