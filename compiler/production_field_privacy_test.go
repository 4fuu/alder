package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Record fields default to module-private: a public record is constructible
// from another module only when every field is marked `pub`. The accepted
// project constructs the all-pub record and reaches the sealed record only
// through its module's functions; the rejected project tries to construct the
// sealed record itself and fails with diagnostic 309.
func fieldPrivacyFiles() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/util.al": `module hello.util

pub type Open {
    pub value: U64
}

pub type Sealed {
    hidden: U64
}

pub fn make() -> Sealed {
    return Sealed(hidden: 3)
}

pub fn read(sealed: Sealed) -> U64 {
    return sealed.hidden
}
`,
	}
}

func TestFieldConstructionPrivacy(t *testing.T) {
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

	t.Run("all-pub-and-local-construction", func(t *testing.T) {
		t.Parallel()
		files := fieldPrivacyFiles()
		files["src/main.al"] = `module hello.main

import hello.util { Open, make, read }

fn main() -> I32 {
    let open = Open(value: 4)
    let sealed = make()
    if open.value + read(sealed) != 7 { return 1 }
    return 0
}
`
		run := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
		if run != (productionResult{}) {
			t.Fatalf("privacy acceptance run failed: %+v", run)
		}
	})

	t.Run("private-field-construction-rejected", func(t *testing.T) {
		t.Parallel()
		files := fieldPrivacyFiles()
		files["src/main.al"] = `module hello.main

import hello.util { Sealed }

fn main() -> I32 {
    let sealed = Sealed(hidden: 3)
    return 0
}
`
		result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "check")
		if result.status == 0 || !strings.Contains(result.stderr, "cannot construct this record outside its module") {
			t.Fatalf("private construction accepted: %+v", result)
		}
	})
}
