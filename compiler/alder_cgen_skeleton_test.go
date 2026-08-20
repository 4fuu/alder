package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The fixture constructs flat MIR records directly. Rejection cases run as
// separate processes so the Go harness observes their exact stdout byte count.
const cgenSkeletonWrapper = `
fn cgen_fixture(d: Domain, initial: MirStore) -> Result(MirStore, __s0_Error) {
    var store = initial
    let helper = try mir_add_function(d, store, "ns.helper", mir_type_unit())
    store = helper.store
    let helper_block = try mir_add_block(d, store, helper.id, 0, "entry")
    store = helper_block.store
    let helper_term = try mir_add_terminator(d, store, MirTermRec(function: helper.id, block: helper_block.id, kind: mir_term_return(), value: 0, target: 0, then_block: 0, else_block: 0))
    store = helper_term.store
    let pair = try mir_add_named_type(d, store, mir_type_kind_aggregate(), "pkg.Pair")
    store = pair.store
    let no_parts = try __s0_buffer_new(U64, d)
    let maybe = try mir_intern_type(d, store, mir_type_kind_option(), mir_type_u64(), 0, 0, no_parts, 0)
    store = maybe.store
    store = try mir_add_type_part(d, store, mir_type_part_field(), pair.type_id, 0, "value", maybe.type_id)
    let choice = try mir_add_named_type(d, store, mir_type_kind_enum(), "pkg.Choice")
    store = choice.store
    store = try mir_add_type_part(d, store, mir_type_part_variant(), choice.type_id, 0, "none", mir_type_unit())
    store = try mir_add_type_part(d, store, mir_type_part_variant(), choice.type_id, 1, "pair", pair.type_id)
    var signature = try __s0_buffer_append(U64, d, no_parts, pair.type_id)
    signature = try __s0_buffer_append(U64, d, signature, mir_type_unit())
    let callback = try mir_intern_type(d, store, mir_type_kind_function(), 0, 0, 0, signature, mir_type_bool())
    store = callback.store
    let string_type = try mir_intern_type(d, store, mir_type_kind_slice(), mir_type_u8(), 0, 0, no_parts, 0)
    store = string_type.store
    let domain = try mir_intern_type(d, store, mir_type_kind_domain_handle(), 0, 0, 0, no_parts, 0)
    store = domain.store
    let imported = try mir_add_import(d, store, "foreign_call", pair.type_id)
    store = try mir_add_import_param(d, imported.store, imported.id, 0, callback.type_id)
    store = try mir_add_import_param(d, store, imported.id, 1, mir_type_unit())
    let unit = try mir_add_const(d, store, "unit", mir_type_unit(), mir_const_unit(), 0, 0, 0, "")
    store = unit.store
    let truth = try mir_add_const(d, store, "truth", mir_type_bool(), mir_const_bool(), 1, 0, 0, "")
    store = truth.store
    let minimum = try mir_add_const(d, store, "minimum", mir_type_i64(), mir_const_int(), 0, -9223372036854775807 - 1, 0, "")
    store = minimum.store
    let one = try mir_add_const(d, store, "one", mir_type_f64(), mir_const_float(), 0, 0, 4607182418800017408, "")
    store = one.store
    let escaped = try mir_add_const(d, store, "escaped", string_type.type_id, mir_const_string(), 0, 0, 0, "a\0\"\\9")
    store = escaped.store
    let main = try mir_add_function(d, store, "main", mir_type_i32())
    store = main.store
    let root = try mir_add_function_param(d, store, main.id, 0, "root", domain.type_id)
    store = root.store
    let main_block = try mir_add_block(d, store, main.id, 0, "entry")
    store = main_block.store
    let main_term = try mir_add_terminator(d, store, MirTermRec(function: main.id, block: main_block.id, kind: mir_term_panic(), value: 0, target: 0, then_block: 0, else_block: 0))
    return Ok(main_term.store)
}

fn cgen_rejected(result: Bool) -> I32 {
    if result { return 8 }
    return 0
}

fn cgen_run(d: Domain, store: MirStore) -> Result(I32, __s0_Error) {
    if unsafe c { alderhost_source_count() } > 1 {
        if host_path_is(1, "!cgen-body-verify") { if emit_verification(99, try mir_verify_module(d, try cgen_body_fixture(d, store), 3)) { return Ok(0) }
        return Ok(7) }
        if host_path_is(1, "!cgen-body") { if try cgen_generate(d, try cgen_body_fixture(d, store), 3, true) { return Ok(0) }
        return Ok(7) }
        if host_path_is(1, "!cgen-ffi-result-verify") { if emit_verification(97, try mir_verify_module(d, try cgen_ffi_result_fixture(d, store), 3)) { return Ok(0) }
        return Ok(7) }
        if host_path_is(1, "!cgen-ffi-result") { if try cgen_generate(d, try cgen_ffi_result_fixture(d, store), 3, true) { return Ok(0) }
        return Ok(7) }
        if host_path_is(1, "!cgen-body-invalid") { let malformed = try mir_add_const(d, try cgen_body_fixture(d, store), "bad", 999, mir_const_int(), 0, 1, 0, "")
        return Ok(cgen_rejected(try cgen_generate(d, malformed.store, 3, true))) }
        if host_path_is(1, "!cgen-body-unsupported-verify") { if emit_verification(98, try mir_verify_module(d, try cgen_unsupported_fixture(d, store), 3)) { return Ok(0) }
        return Ok(7) }
        if host_path_is(1, "!cgen-body-unsupported") { return Ok(cgen_rejected(try cgen_generate(d, try cgen_unsupported_fixture(d, store), 3, false))) }
        if host_path_is(1, "!cgen-bad-version") { return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, try cgen_fixture(d, store), 99, true))) }
        if host_path_is(1, "!cgen-earlier-v1-v9") { let malformed = try mir_add_const(d, try cgen_fixture(d, store), "bad", 999, mir_const_int(), 0, 1, 0, "")
        return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, malformed.store, 3, true))) }
        if host_path_is(1, "!cgen-missing-entry") { return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, try minimal(d, store, mir_type_unit(), false), 3, true))) }
        if host_path_is(1, "!cgen-invalid-entry") { let invalid = try mir_add_function(d, store, "main", 999)
        return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, invalid.store, 3, true))) }
        if host_path_is(1, "!cgen-duplicate-entry") { let first = try hosted_fixture(d, store, "main", mir_type_i32(), 0)
        return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, try hosted_fixture(d, first, "main", mir_type_i32(), 0), 3, true))) }
        if host_path_is(1, "!cgen-bad-entry-result") { return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, try hosted_fixture(d, store, "main", mir_type_unit(), 0), 3, true))) }
        if host_path_is(1, "!cgen-bad-entry-params") { return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, try hosted_fixture(d, store, "main", mir_type_i32(), 2), 3, true))) }
        if host_path_is(1, "!cgen-v10-backend") { return Ok(cgen_rejected(try cgen_write_declaration_skeleton(d, try backend_names_fixture(d, store, true), 3, false))) }
        if host_path_is(1, "!cgen-unhosted") { if try cgen_write_declaration_skeleton(d, try cgen_fixture(d, store), 3, false) { return Ok(0) }
        return Ok(7) }
        return Ok(9)
    }
    if try cgen_write_declaration_skeleton(d, try cgen_fixture(d, store), 3, true) { return Ok(0) }
    return Ok(7)
}

fn cgen_mode(d: Domain) -> I32 { return match mir_store_new(d) {
    Err(error) => 3
    Ok(store) => match cgen_run(d, store) {
        Err(error) => 4
        Ok(code) => code
    }
} }
`

const cgenSkeletonGolden = `/* Generated by the Alder declaration-only C11 backend skeleton. */
/* Production generation remains gated on MIR verifier V10. */
#include "alder.h"
#include "alder_host.h"
#include <float.h>
#include <string.h>

typedef struct AlderTy12 AlderTy12;
typedef struct AlderTy13 AlderTy13;
typedef struct AlderTy14 AlderTy14;

struct AlderTy13 {
  union {
    uint64_t alder_p1;
  } alder_u;
  uint32_t alder_tag;
};
/* @pkg.Pair */
struct AlderTy12 {
  AlderTy13 alder_f0;
};
/* @pkg.Choice */
struct AlderTy14 {
  union {
    AlderTy12 alder_p1;
  } alder_u;
  uint32_t alder_tag;
};
typedef bool (*AlderFnTy15)(AlderTy12);
/* unit constant alder_const_0 has no storage. */
static ALDER_MAYBE_UNUSED const bool alder_const_1 = true;
static ALDER_MAYBE_UNUSED const int64_t alder_const_2 = (int64_t)(-9223372036854775807LL - 1);
static ALDER_MAYBE_UNUSED const uint64_t alder_const_3_bits = UINT64_C(4607182418800017408);
static ALDER_MAYBE_UNUSED uint8_t alder_str_4[] = {UINT8_C(97), UINT8_C(0), UINT8_C(34), UINT8_C(92), UINT8_C(57)};

static ALDER_MAYBE_UNUSED void alder_fn_ns_helper_0(void);
static ALDER_MAYBE_UNUSED int32_t alder_fn_main_1(AlderDomain * alder_v0);

AlderTy12 (foreign_call)(AlderFnTy15);

int32_t alder_program_entry(void *host_context) {
  if (host_context == NULL) { return ALDER_PROGRAM_FAILURE_STATUS; }
  AlderDomain alder_root = {0};
  int32_t alder_status;
  if (!alder_domain_init(&alder_root, NULL)) { return ALDER_PROGRAM_FAILURE_STATUS; }
  alder_status = alder_fn_main_1(&alder_root);
  alder_domain_destroy(&alder_root);
  return alder_status;
}
`

const cgenSkeletonUnhostedGolden = `/* Generated by the Alder declaration-only C11 backend skeleton. */
/* Production generation remains gated on MIR verifier V10. */
#include "alder.h"
#include <float.h>
#include <string.h>

typedef struct AlderTy12 AlderTy12;
typedef struct AlderTy13 AlderTy13;
typedef struct AlderTy14 AlderTy14;

struct AlderTy13 {
  union {
    uint64_t alder_p1;
  } alder_u;
  uint32_t alder_tag;
};
/* @pkg.Pair */
struct AlderTy12 {
  AlderTy13 alder_f0;
};
/* @pkg.Choice */
struct AlderTy14 {
  union {
    AlderTy12 alder_p1;
  } alder_u;
  uint32_t alder_tag;
};
typedef bool (*AlderFnTy15)(AlderTy12);
/* unit constant alder_const_0 has no storage. */
static ALDER_MAYBE_UNUSED const bool alder_const_1 = true;
static ALDER_MAYBE_UNUSED const int64_t alder_const_2 = (int64_t)(-9223372036854775807LL - 1);
static ALDER_MAYBE_UNUSED const uint64_t alder_const_3_bits = UINT64_C(4607182418800017408);
static ALDER_MAYBE_UNUSED uint8_t alder_str_4[] = {UINT8_C(97), UINT8_C(0), UINT8_C(34), UINT8_C(92), UINT8_C(57)};

static ALDER_MAYBE_UNUSED void alder_fn_ns_helper_0(void);
static ALDER_MAYBE_UNUSED int32_t alder_fn_main_1(AlderDomain * alder_v0);

AlderTy12 (foreign_call)(AlderFnTy15);

`

func runCgenSkeletonConformance(t *testing.T, cc, root, exe string) {
	t.Helper()
	run := func(t *testing.T, testCase string) string {
		t.Helper()
		dir := t.TempDir()
		const sentinel = "!alder-core-cgen"
		if err := os.WriteFile(filepath.Join(dir, sentinel), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		args := []string{sentinel}
		if testCase != "" {
			if err := os.WriteFile(filepath.Join(dir, testCase), nil, 0o644); err != nil {
				t.Fatal(err)
			}
			args = append(args, testCase)
		}
		cmd := conformanceCommand(exe, args...)
		cmd.Dir = dir
		output, err := cmd.Output()
		if err != nil {
			t.Fatalf("run C skeleton %q: %v", testCase, err)
		}
		got := string(output)
		if strings.Contains(got, root) || strings.Contains(got, dir) {
			t.Fatal("C skeleton contains an absolute host path")
		}
		return got
	}
	for attempt := 0; attempt < 2; attempt++ {
		if got := run(t, ""); got != cgenSkeletonGolden {
			t.Fatalf("hosted C skeleton mismatch on run %d\nwant:\n%s\ngot:\n%s", attempt, cgenSkeletonGolden, got)
		}
		if got := run(t, "!cgen-unhosted"); got != cgenSkeletonUnhostedGolden {
			t.Fatalf("unhosted C skeleton mismatch on run %d\nwant:\n%s\ngot:\n%s", attempt, cgenSkeletonUnhostedGolden, got)
		}
	}
	for _, testCase := range []string{
		"!cgen-bad-version",
		"!cgen-earlier-v1-v9",
		"!cgen-missing-entry",
		"!cgen-invalid-entry",
		"!cgen-duplicate-entry",
		"!cgen-bad-entry-result",
		"!cgen-bad-entry-params",
		"!cgen-v10-backend",
	} {
		if got := run(t, testCase); got != "" {
			t.Fatalf("rejected C skeleton %q wrote %d stdout bytes: %q", testCase, len(got), got)
		}
	}
	for _, fragment := range []string{
		"Production generation remains gated on MIR verifier V10.",
		"typedef struct AlderTy12 AlderTy12;",
		"struct AlderTy13 {",
		"struct AlderTy12 {",
		"typedef bool (*AlderFnTy15)(AlderTy12);",
		"alder_fn_ns_helper_0(void);",
		"AlderTy12 (foreign_call)(AlderFnTy15);",
		"alder_const_2 = (int64_t)(-9223372036854775807LL - 1);",
		"alder_const_3_bits = UINT64_C(4607182418800017408);",
		`alder_str_4[] = {UINT8_C(97), UINT8_C(0), UINT8_C(34), UINT8_C(92), UINT8_C(57)};`,
		"int32_t alder_program_entry(void *host_context)",
	} {
		if !strings.Contains(cgenSkeletonGolden, fragment) {
			t.Fatalf("C skeleton missing %q\n%s", fragment, cgenSkeletonGolden)
		}
	}

	// The skeleton intentionally contains declarations rather than instruction
	// bodies. Complete those declarations only in this strict-syntax fixture.
	strict := cgenSkeletonGolden + `
static void alder_fn_ns_helper_0(void) {}
static int32_t alder_fn_main_1(AlderDomain *alder_v0) { (void)alder_v0; return (int32_t)0; }
`
	cfile := filepath.Join(t.TempDir(), "skeleton.c")
	if err := os.WriteFile(cfile, []byte(strict), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), "-I", filepath.Join(root, "bootstrap"), "-fsyntax-only", cfile}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C skeleton syntax: %v\n%s\n%s", err, output, cgenSkeletonGolden)
	}
}
