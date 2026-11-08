package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M7.5 closure literals: the production driver pins the shapes the checker
// accepts and rejects. A literal inside a generic function body needs a thunk
// signature per instantiation, which this slice does not materialize yet, so
// the driver rejects it with a clean diagnostic instead of crashing.

var m75ClosureRejections = []struct {
	name, source, want string
}{
	{
		"closure-in-generic-body",
		"fn layer(T: type, seed: U64) -> U64 {\n    let rebased = fn(x: U64) => x + seed\n    return rebased(seed)\n}\nfn main() -> I32 {\n    if layer(U64, 3) != 6 { return 1 }\n    return 0\n}\n",
		"a closure literal inside a generic function body is not supported yet",
	},
}

func TestM75ClosureProductionQualification(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)

	for _, rejection := range m75ClosureRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "reject.al")
			if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: status=%d stdout=%q stderr=%q", rejection.name, result.status, result.stdout, result.stderr)
			}
		})
	}
}
