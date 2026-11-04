package compiler

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// M7.5 slice 2: static trait dispatch through generic monomorphization. The
// program implements one user trait for two record types and calls the trait
// method both through a constrained generic function (resolved per concrete
// instance) and directly on a concrete receiver. The generated C must run
// with the expected dispatch results. Alder-only: the Go oracle frontend
// does not implement the trait surface.
func runAlderM75LowerBehavior(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{"traits.al": `type UserCursor {
    row: U64
}

type AdminCursor {
    row: U64
}

trait Walker(Item: type) {
    fn next(self) -> Option(Item)
}

impl Walker(U64) for UserCursor {
    fn next(self) -> Option(U64) {
        if self.row == 0 { return None }
        return Some(self.row)
    }
}

impl Walker(U64) for AdminCursor {
    fn next(self) -> Option(U64) {
        return Some(self.row + 100)
    }
}

fn take_first(W: type, walker: W) -> U64
where W: Walker(U64) {
    let value = walker.next()
    return match value {
        Some(v) => v
        None => 0
    }
}

fn main() -> I32 {
    let user = UserCursor(row: 3)
    let admin = AdminCursor(row: 4)
    if take_first(UserCursor, user) != 3 { return 1 }
    if take_first(AdminCursor, admin) != 104 { return 2 }
    let value = admin.next()
    return match value {
        Some(v) => 0
        None => 3
    }
}
`}
	first := runLowerCompiler(t, exe, files, []string{"traits.al"})
	second := runLowerCompiler(t, exe, files, []string{"traits.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("lowered trait dispatch MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify lowered trait MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	mainID, ok := module.Function("main")
	if !ok {
		t.Fatal("trait dispatch MIR has no main function")
	}
	// Generic instances lower as the declaration name plus the owning symbol
	// id, e.g. take_first8; both receiver types must produce one instance.
	foundInstances := 0
	for id := range module.Functions {
		name := module.Functions[id].Name
		if len(name) > len("take_first") && name[:len("take_first")] == "take_first" {
			foundInstances++
		}
	}
	if foundInstances != 2 {
		t.Fatalf("trait dispatch MIR has %d take_first instances, want 2", foundInstances)
	}
	generated := runResourceCgenCompiler(t, exe, files, []string{"traits.al"})
	if repeat := runResourceCgenCompiler(t, exe, files, []string{"traits.al"}); !bytes.Equal(generated, repeat) {
		t.Fatal("Alder-written trait dispatch C changed across processes")
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	file := filepath.Join(dir, "traits.c")
	program := filepath.Join(dir, "traits.exe")
	// The parameterless hosted entry takes no domain argument.
	driver := fmt.Sprintf("\nint main(void) { int32_t status = alder_fn_main_%d(); return status; }\n", mainID)
	if err := os.WriteFile(file, append(append([]byte(nil), generated...), []byte(driver)...), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-Wshadow", "-Wconversion", "-I", filepath.Join(root, "runtime", "c"), file, filepath.Join(root, "runtime", "c", "alder.c"), "-o", program}
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile of trait dispatch: %v\n%s", err, output)
	}
	if output, err := conformanceCommand(program).CombinedOutput(); err != nil {
		t.Fatalf("run trait dispatch behavior: %v\n%s", err, output)
	}
	t.Logf("trait dispatch program exited cleanly under strict C11")
}
