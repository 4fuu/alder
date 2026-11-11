package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// D025's Error trait and ErrorReport are a prelude surface: a project that
// names Error or ErrorReport gets core.error from the installed sysroot
// without an import. Root errors inherit the default None cause; a wrapper
// error supplies the typed payload it wraps.
func TestProductionErrorReportPrelude(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

type Root {
    code: U64
}

impl Display for Root {
    fn display(self) -> String {
        return "root"
    }
}

impl Error for Root {}

type Wrapped {
    inner: Root
}

impl Display for Wrapped {
    fn display(self) -> String {
        return "wrapped"
    }
}

impl Error for Wrapped {
    fn cause(self) -> Option(ErrorReport) {
        return Some(ErrorReport.of(self.inner))
    }
}

type Plain {
    value: Bool
}

impl Display for Plain {
    fn display(self) -> String {
        return "plain"
    }
}

impl Error for Plain {}

pub fn main() -> I32 {
    let root = ErrorReport.of(Root(code: 7))
    if root.message != "root" { return 1 }
    if root.causes.len() != 0 { return 2 }

    let wrapped = ErrorReport.of(Wrapped(inner: Root(code: 7)))
    if wrapped.message != "wrapped" { return 3 }
    if wrapped.causes.len() != 1 { return 4 }
    if wrapped.causes[0] != "root" { return 5 }

    let plain = Plain(value: true)
    match plain.cause() {
        None => {}
        Some(_) => { return 6 }
    }
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("ErrorReport prelude behavior failed: %+v", result)
	}

	imported := map[string]string{
		"alder.toml": files["alder.toml"],
		"src/main.al": `module hello.main

import core.error { ErrorReport }

type Root {
    code: U64
}

impl Display for Root {
    fn display(self) -> String {
        return "root"
    }
}

impl Error for Root {}

pub fn main() -> I32 {
    let report = ErrorReport.of(Root(code: 7))
    if report.message != "root" { return 1 }
    if report.causes.len() != 0 { return 2 }
    return 0
}
`,
	}
	importedResult := runProductionCompilerEnv(t, exe, t.TempDir(), env, imported, "run")
	if importedResult != (productionResult{}) {
		t.Fatalf("explicit core.error import behavior failed: %+v", importedResult)
	}

	rejections := []struct {
		name, source, want string
	}{
		{
			"cause-result",
			`module hello.main

type Bad {
    value: Bool
}

impl Display for Bad {
    fn display(self) -> String {
        return "bad"
    }
}

impl Error for Bad {
    fn cause(self) -> Option(String) {
        return None
    }
}

pub fn main() -> I32 {
    return 0
}
`,
			"trait implementation method does not match the trait requirement signature",
		},
		{
			"report-needs-error",
			`module hello.main

type Bare {
    value: Bool
}

impl Display for Bare {
    fn display(self) -> String {
        return "bare"
    }
}

pub fn main() -> I32 {
    let report = ErrorReport.of(Bare(value: true))
    return 0
}
`,
			"does not implement a trait required here",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			rejectFiles := map[string]string{
				"alder.toml":  files["alder.toml"],
				"src/main.al": rejection.source,
			}
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, rejectFiles, "run")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
