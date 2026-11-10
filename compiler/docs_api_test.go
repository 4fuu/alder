package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Every snapshot example under docs/api/examples must compile and run against
// the production compiler. The table below carries the verifying entry point
// and its independently derived checksum for each committed example file, and
// the test fails when the directory gains an example without a table entry,
// so every future snapshot example is covered automatically.
//
// Two example styles exist:
//
//   - "single": a module-less fragment compiled alongside the case's main.al
//     in one single-file compile; the driver emits the generated C on stdout
//     and the test links and runs it under the strict warning set.
//   - "project": a file that declares its module and imports sysroot modules;
//     the test copies it verbatim into a project's src tree and runs the
//     project through the driver, which resolves the sysroot.

type snapshotExampleCase struct {
	style    string // "single" or "project"
	srcName  string // project style: destination file name below src/
	mainText string
}

const snapshotExamplesDir = "docs/api/examples"

const snapshotProjectManifest = "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

func snapshotExampleCases() map[string]snapshotExampleCase {
	return map[string]snapshotExampleCase{
		"core.collection-v1.al": {
			style: "single",
			mainText: `pub fn main() -> I32 {
    if collection_example() == 42 { return 0 }
    return 1
}
`,
		},
		"core.slice-v1.al": {
			style: "single",
			mainText: `pub fn main() -> I32 {
    if slice_example() == 32 { return 0 }
    return 1
}
`,
		},
		"core.option-v1.al": {
			style:   "project",
			srcName: "option_example.al",
			mainText: `module hello.main

import hello.option_example { option_example }

pub fn main() -> I32 {
    if option_example() == 270 { return 0 }
    return 1
}
`,
		},
		"core.result-v1.al": {
			style:   "project",
			srcName: "result_example.al",
			mainText: `module hello.main

import hello.result_example { result_example }

pub fn main() -> I32 {
    if result_example() == 226 { return 0 }
    return 1
}
`,
		},
	}
}

func TestDocsApiSnapshotExamplesRun(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	runtimeObject := buildRuntimeObject(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	cases := snapshotExampleCases()
	entries, err := os.ReadDir(filepath.Join(repoRoot, snapshotExamplesDir))
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".al") {
			continue
		}
		if _, ok := cases[entry.Name()]; !ok {
			t.Fatalf("docs example %s has no runner entry in docs_api_test.go", entry.Name())
		}
	}
	for name, testCase := range cases {
		t.Run(name, func(t *testing.T) {
			text, readErr := os.ReadFile(filepath.Join(repoRoot, snapshotExamplesDir, name))
			if readErr != nil {
				t.Fatalf("snapshot example %s is missing: %v", name, readErr)
			}
			exampleText := string(text)
			switch testCase.style {
			case "single":
				files := map[string]string{"main.al": testCase.mainText, name: exampleText}
				compile := runProductionCompiler(t, exe, files, "compile", "main.al", name)
				if compile.status != 0 || compile.stderr != "" || compile.stdout == "" {
					t.Fatalf("single-file compile of %s: %+v", name, compile)
				}
				compileAndRunProductionArtifact(t, cc, repoRoot, runtimeObject, compile.stdout, 0)
			case "project":
				if testCase.srcName == "" {
					t.Fatalf("project example %s needs a src file name", name)
				}
				files := map[string]string{
					"alder.toml":              snapshotProjectManifest,
					"src/" + testCase.srcName: exampleText,
					"src/main.al":             testCase.mainText,
				}
				run := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
				if run.status != 0 || run.stderr != "" {
					t.Fatalf("project run of %s: %+v", name, run)
				}
			default:
				t.Fatalf("unknown snapshot example style %q", testCase.style)
			}
		})
	}
}
