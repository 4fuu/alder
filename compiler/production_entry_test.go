package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Binary entry results beyond the legacy I32 form use a generated source
// adapter. The adapter maps Unit and Result success to the documented status
// and routes Err through the prelude program-error renderer.
func TestProductionEntryResultAdapter(t *testing.T) {
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
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

	cases := []struct {
		name, source string
		wantStatus   int
		wantStderr   string
	}{
		{
			name: "unit",
			source: `module hello.main

pub fn main() -> Unit {
    return ()
}
`,
			wantStatus: 0,
		},
		{
			name: "result-ok",
			source: `module hello.main

pub fn main() -> Result(Unit, String) {
    return Ok(())
}
`,
			wantStatus: 0,
		},
		{
			name: "result-ok-i32",
			source: `module hello.main

pub fn main() -> Result(I32, String) {
    return Ok(5)
}
`,
			wantStatus: 5,
		},
		{
			name: "result-err",
			source: `module hello.main

pub fn main() -> Result(Unit, String) {
    return Err("bad")
}
`,
			wantStatus: 1,
			wantStderr: "program error: bad\n",
		},
		{
			name: "result-error-chain",
			source: `module hello.main

pub type Root {
    code: U64
}

impl Display for Root {
    fn display(self) -> String {
        return "root"
    }
}

impl Error for Root {}

pub type Wrapped {
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

pub fn main() -> Result(Unit, Wrapped) {
    return Err(Wrapped(inner: Root(code: 7)))
}
`,
			wantStatus: 1,
			wantStderr: "program error: wrapped\nroot\n",
		},
	}
	rejections := []struct {
		name, source, want string
	}{
		{
			"main-u64",
			`module hello.main

pub fn main() -> U64 {
    return 0
}
`,
			"checker diagnostic 332",
		},
		{
			"result-error-not-display",
			`module hello.main

pub type NoDisplay {
    value: U64
}

pub fn main() -> Result(Unit, NoDisplay) {
    return Ok(())
}
`,
			"checker diagnostic 332",
		},
	}
	for _, rejection := range rejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  manifest,
				"src/main.al": rejection.source,
			}, "run")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: status=%d stderr=%q, want status nonzero and %q", rejection.name, result.status, result.stderr, rejection.want)
			}
		})
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  manifest,
				"src/main.al": tc.source,
			}, "run")
			if result.status != tc.wantStatus || result.stderr != tc.wantStderr {
				t.Fatalf("%s: got status=%d stderr=%q, want status=%d stderr=%q", tc.name, result.status, result.stderr, tc.wantStatus, tc.wantStderr)
			}
			if tc.wantStatus != 1 && result.stdout != "" {
				t.Fatalf("%s: stdout=%q, want empty", tc.name, result.stdout)
			}
		})
	}
}
