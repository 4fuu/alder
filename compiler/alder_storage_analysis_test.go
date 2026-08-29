package compiler

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

const storageAnalysisWrapper = `
fn storage_emit_plan(label: U64, plan: StoragePlan) -> Bool {
    if !out(80) || !out(32) || !out_u64(label) || !out(32) || !out_u64(plan.issue_kind) || !out(32) || !out_u64(plan.issue_index) || !out(32) || !out_u64(plan.promotions) || !out(32) || !out_u64(__s0_buffer_len(U64, plan.placements)) { return false }
    var at: U64 = 0
    while at < __s0_buffer_len(U64, plan.placements) {
        if !out(32) || !out_u64(__s0_buffer_get(U64, plan.placements, at)) { return false }
        at = at + 1
    }
    if !out(32) || !out_u64(__s0_buffer_len(Bool, plan.valid_views)) || !out(32) || !out_u64(__s0_buffer_len(U64, plan.retained)) { return false }
    at = 0
    while at < __s0_buffer_len(U64, plan.retained) {
        if !out(32) || !out_u64(__s0_buffer_get(U64, plan.retained, at)) { return false }
        at = at + 1
    }
    return out(10)
}

fn storage_emit_result(label: U64, result: Result(StoragePlan, __s0_Error)) -> Bool { return match result {
    Err(error) => false
    Ok(plan) => storage_emit_plan(label, plan)
} }

fn storage_nested_case(d: Domain, reversed: Bool) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 1))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 2))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 2))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 4))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    var at: U64 = 0
    while at < 4 {
        allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 5))
        at = at + 1
    }
    var constraints = try __s0_buffer_new(StorageConstraintRec, d)
    if reversed {
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 4, domain: 0, dependency: 1, fallback: false, source: 44))
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 3, domain: 0, dependency: 2, fallback: false, source: 33))
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 2, domain: 0, dependency: 0, fallback: true, source: 22))
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 1, domain: 4, dependency: 0, fallback: false, source: 11))
    } else {
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 1, domain: 4, dependency: 0, fallback: false, source: 11))
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 2, domain: 0, dependency: 0, fallback: true, source: 22))
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 3, domain: 0, dependency: 2, fallback: false, source: 33))
        constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 4, domain: 0, dependency: 1, fallback: false, source: 44))
    }
    var views = try __s0_buffer_new(StorageViewRec, d)
    views = try __s0_buffer_append(StorageViewRec, d, views, StorageViewRec(allocation: 1, parent_view: 0, use_domain: 3, invalidated: false, source: 55))
    views = try __s0_buffer_append(StorageViewRec, d, views, StorageViewRec(allocation: 0, parent_view: 1, use_domain: 5, invalidated: false, source: 56))
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_invalid_view_case(d: Domain) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 1))
    let constraints = try __s0_buffer_new(StorageConstraintRec, d)
    var views = try __s0_buffer_new(StorageViewRec, d)
    views = try __s0_buffer_append(StorageViewRec, d, views, StorageViewRec(allocation: 1, parent_view: 0, use_domain: 1, invalidated: true, source: 9))
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_bad_hierarchy_case(d: Domain) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 2))
    let allocations = try __s0_buffer_new(StorageAllocationRec, d)
    let constraints = try __s0_buffer_new(StorageConstraintRec, d)
    let views = try __s0_buffer_new(StorageViewRec, d)
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_bad_constraint_case(d: Domain) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 1))
    var constraints = try __s0_buffer_new(StorageConstraintRec, d)
    constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 1, domain: 1, dependency: 1, fallback: false, source: 7))
    let views = try __s0_buffer_new(StorageViewRec, d)
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_bad_allocation_case(d: Domain) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 2))
    let constraints = try __s0_buffer_new(StorageConstraintRec, d)
    let views = try __s0_buffer_new(StorageViewRec, d)
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_bad_view_case(d: Domain) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 1))
    let constraints = try __s0_buffer_new(StorageConstraintRec, d)
    var views = try __s0_buffer_new(StorageViewRec, d)
    views = try __s0_buffer_append(StorageViewRec, d, views, StorageViewRec(allocation: 0, parent_view: 0, use_domain: 1, invalidated: false, source: 8))
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_layered_case(d: Domain, count: U64) -> Result(StoragePlan, __s0_Error) {
    var domains = try __s0_buffer_new(StorageDomainRec, d)
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 0))
    domains = try __s0_buffer_append(StorageDomainRec, d, domains, StorageDomainRec(parent: 1))
    var allocations = try __s0_buffer_new(StorageAllocationRec, d)
    var constraints = try __s0_buffer_new(StorageConstraintRec, d)
    var at: U64 = 1
    while at <= count {
        allocations = try __s0_buffer_append(StorageAllocationRec, d, allocations, StorageAllocationRec(candidate: 2))
        if at == 1 {
            constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: 1, domain: 0, dependency: 0, fallback: true, source: 1001))
        } else {
            constraints = try __s0_buffer_append(StorageConstraintRec, d, constraints, StorageConstraintRec(allocation: at, domain: 0, dependency: at - 1, fallback: false, source: at + 1000))
        }
        at = at + 1
    }
    let views = try __s0_buffer_new(StorageViewRec, d)
    return storage_analyze(d, domains, allocations, constraints, views)
}

fn storage_mode(d: Domain) -> I32 {
    if !storage_emit_result(1, storage_nested_case(d, false)) { return 3 }
    if !storage_emit_result(2, storage_nested_case(d, true)) { return 3 }
    if !storage_emit_result(3, storage_invalid_view_case(d)) { return 3 }
    if !storage_emit_result(4, storage_bad_hierarchy_case(d)) { return 3 }
    if !storage_emit_result(5, storage_bad_constraint_case(d)) { return 3 }
    if !storage_emit_result(6, storage_bad_allocation_case(d)) { return 3 }
    if !storage_emit_result(7, storage_bad_view_case(d)) { return 3 }
    if !storage_emit_result(8, storage_layered_case(d, 2048)) { return 3 }
    return 0
}
`

func runStorageAnalysisConformance(t *testing.T, exe string) {
	t.Helper()
	const want = "P 1 0 0 5 4 2 1 1 2 2 1 22\n" +
		"P 2 0 0 5 4 2 1 1 2 2 1 22\n" +
		"P 3 5 1 0 0 0 0\n" +
		"P 4 1 2 0 0 0 0\n" +
		"P 5 3 1 0 0 0 0\n" +
		"P 6 2 1 0 0 0 0\n" +
		"P 7 4 1 0 0 0 0\n" +
		"P 8 0 0 2048 2048 "
	var baseline string
	for run := 0; run < 3; run++ {
		dir := t.TempDir()
		const sentinel = "!alder-core-storage"
		if err := os.WriteFile(filepath.Join(dir, sentinel), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		cmd := conformanceCommand(exe, sentinel)
		cmd.Dir = dir
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil || stderr.Len() != 0 {
			t.Fatalf("run storage analysis %d: %v stderr=%q stdout=%q", run, err, stderr.String(), stdout.String())
		}
		output := stdout.String()
		if len(output) < len(want)+10 || output[:len(want)] != want || output[len(output)-10:] != " 0 1 1001\n" {
			t.Fatalf("storage analysis output mismatch: %q", output)
		}
		if run == 0 {
			baseline = output
		} else if output != baseline {
			t.Fatal("storage analysis changed across fresh processes")
		}
	}
}
