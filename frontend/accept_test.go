package frontend

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// acceptFixtures compile to verified MIR whose printed form is pinned.
var acceptFixtures = []string{
	"basic",
	"generics",
	"match",
	"try",
	"cleanup",
	"ffi",
	"buffer",
}

// privateBootstrapFixtures still use the S0 bootstrap bridges as runtime
// implementation evidence; they compile under the private bootstrap profile
// only.
var privateBootstrapAccept = map[string]bool{"buffer": true}

// privateBootstrapReject keeps testing its original diagnostic under the
// private bootstrap profile; ordinary compilation stops earlier at the
// bootstrap-surface gate.
var privateBootstrapReject = map[string]bool{
	"alloc-as-slice-param": true,
	"bind-mark":            true,
	"bind-unit":            true,
	"map-key-signed":       true,
	"map-value-string":     true,
}

func compileReject(name, src string) (*mir.Module, error) {
	if privateBootstrapReject[name] {
		return CompilePrivate(src)
	}
	return Compile(src)
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
	"bootstrap-type-domain",
	"bootstrap-type-domainmark",
	"bootstrap-type-s0error",
	"bootstrap-type-s0string",
	"bootstrap-type-map",
	"bootstrap-type-s0buffer",
	"bootstrap-op-alloc",
	"bootstrap-op-buffer-new",
	"bootstrap-op-map-create",
	"bootstrap-op-get",
	"bootstrap-entry-domain-main",
}

func acceptSource(t *testing.T, name string) string {
	t.Helper()
	return readFixture(t, filepath.Join("testdata", "accept", name+".al"))
}

// TestAccept pins the printed MIR of every accept fixture. Set
// ALDER_UPDATE_GOLDEN=1 to regenerate.
func TestAccept(t *testing.T) {
	update := os.Getenv("ALDER_UPDATE_GOLDEN") == "1"
	for _, name := range acceptFixtures {
		name := name
		t.Run(name, func(t *testing.T) {
			var m *mir.Module
			var err error
			if privateBootstrapAccept[name] {
				m, err = CompilePrivate(acceptSource(t, name))
			} else {
				m, err = Compile(acceptSource(t, name))
			}
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
				t.Fatalf("missing golden %s (run with ALDER_UPDATE_GOLDEN=1): %v", path, err)
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
			src := readFixture(t, filepath.Join("testdata", "reject", name+".al"))
			_, err := compileReject(name, src)
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
			compile := Compile
			if privateBootstrapAccept[name] {
				compile = CompilePrivate
			}
			m1, err := compile(src)
			if err != nil {
				t.Fatal(err)
			}
			m2, err := compile(src)
			if err != nil {
				t.Fatal(err)
			}
			if mir.Print(m1) != mir.Print(m2) {
				t.Fatalf("compilation of %s is not deterministic", name)
			}
		})
	}
}

// TestBootstrapPrivateSurfaceIsGated rejects every private bootstrap name in
// an ordinary program and confirms the private bootstrap profile lifts the
// gate far enough to reach the ordinary name-specific diagnostics.
func TestBootstrapPrivateSurfaceIsGated(t *testing.T) {
	var cases []struct{ name, src, want string }
	for _, name := range bootstrapPrivatePrimTypes {
		cases = append(cases, struct{ name, src, want string }{
			"type " + name,
			"fn keep(x: " + name + ") -> Unit { }\nfn main() -> I32 { return 0 }\n",
			fmt.Sprintf(bootstrapTypeDiag, name),
		})
	}
	for _, name := range bootstrapPrivateAppTypes {
		args := "(U64)"
		if name == "Map" {
			args = "(U64, I64)"
		}
		cases = append(cases, struct{ name, src, want string }{
			"type " + name,
			"fn keep(x: " + name + args + ") -> Unit { }\nfn main() -> I32 { return 0 }\n",
			fmt.Sprintf(bootstrapTypeDiag, name),
		})
	}
	for _, name := range bootstrapPrivateOps {
		cases = append(cases, struct{ name, src, want string }{
			"operation " + name,
			"fn main() -> I32 {\n    let v = " + name + "()\n    return 0\n}\n",
			fmt.Sprintf(bootstrapOpDiag, name),
		})
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := Compile(tc.src); err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Errorf("ordinary compile: got %v, want %q", err, tc.want)
			}
			_, err := CompilePrivate(tc.src)
			if err != nil && strings.Contains(err.Error(), "bootstrap type") || err != nil && strings.Contains(err.Error(), "bootstrap operation") {
				t.Errorf("private profile still gates: %v", err)
			}
		})
	}
}
