package frontend

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/aster/mir"
	"github.com/4fuu/aster/mir/verify"
)

// acceptFixtures compile to verified MIR whose printed form is pinned.
var acceptFixtures = []string{
	"basic",
	"generics",
	"match",
	"try",
	"cleanup",
	"ffi",
}

// rejectFixtures must fail with the pinned diagnostic.
var rejectFixtures = []string{
	"syntax-unterminated-comment",
	"syntax-bad-escape",
	"syntax-missing-semicolon",
	"unknown-name",
	"unknown-type",
	"type-mismatch",
	"immutable-assign",
	"map-key-signed",
	"map-value-string",
	"nested-slice",
	"type-cycle",
	"match-nonexhaustive",
	"match-unknown-variant",
	"try-not-result",
	"try-error-mismatch",
	"using-in-loop",
	"using-callback-type",
	"literal-out-of-range",
	"fall-off-end",
	"reserved-name",
	"duplicate-decl",
	"alloc-as-slice-param",
	"bind-mark",
	"bind-unit",
	"ffi-unsupported-type",
	"float-arithmetic",
	"index-not-u64",
	"shadowing",
	"unreachable-statement",
	"function-value",
	"type-parameter-after-runtime",
}

func acceptSource(t *testing.T, name string) string {
	t.Helper()
	return readFixture(t, filepath.Join("testdata", "accept", name+".ast"))
}

// TestAccept pins the printed MIR of every accept fixture. Set
// ASTER_UPDATE_GOLDEN=1 to regenerate.
func TestAccept(t *testing.T) {
	update := os.Getenv("ASTER_UPDATE_GOLDEN") == "1"
	for _, name := range acceptFixtures {
		name := name
		t.Run(name, func(t *testing.T) {
			m, err := Compile(acceptSource(t, name))
			if err != nil {
				t.Fatalf("compile: %v", err)
			}
			if errs := verify.Module(m); len(errs) > 0 {
				t.Fatalf("lowered MIR failed verification:\n%s", verify.Errors(errs).String())
			}
			got := mir.Print(m)
			path := filepath.Join("testdata", "accept", name+".mir")
			if update {
				if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("missing golden %s (run with ASTER_UPDATE_GOLDEN=1): %v", path, err)
			}
			if got != string(want) {
				t.Errorf("printed MIR differs from %s\n--- got ---\n%s\n--- want ---\n%s", path, got, want)
			}
		})
	}
}

// TestReject pins the deterministic diagnostics of every reject fixture.
func TestReject(t *testing.T) {
	for _, name := range rejectFixtures {
		name := name
		t.Run(name, func(t *testing.T) {
			src := readFixture(t, filepath.Join("testdata", "reject", name+".ast"))
			_, err := Compile(src)
			if err == nil {
				t.Fatalf("fixture %s compiled unexpectedly", name)
			}
			got := err.Error()
			want, err := os.ReadFile(filepath.Join("testdata", "reject", name+".err"))
			if err != nil {
				t.Fatalf("missing expected diagnostic %s: %v", name, err)
			}
			wantStr := strings.TrimSpace(string(want))
			if got != wantStr {
				t.Errorf("diagnostic differs\n--- got ---\n%s\n--- want ---\n%s", got, wantStr)
			}
		})
	}
}

// TestParseErrorsAreDeterministic compiles every accept fixture twice and
// requires identical printed MIR.
func TestParseErrorsAreDeterministic(t *testing.T) {
	for _, name := range acceptFixtures {
		name := name
		t.Run(name, func(t *testing.T) {
			src := acceptSource(t, name)
			m1, err := Compile(src)
			if err != nil {
				t.Fatal(err)
			}
			m2, err := Compile(src)
			if err != nil {
				t.Fatal(err)
			}
			if mir.Print(m1) != mir.Print(m2) {
				t.Fatalf("compilation of %s is not deterministic", name)
			}
		})
	}
}
