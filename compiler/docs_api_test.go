package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"sort"
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
    if collection_example() == 324 { return 0 }
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
		"core.num-v1.al": {
			style:   "project",
			srcName: "num_example.al",
			mainText: `module hello.main

import hello.num_example { num_example }

pub fn main() -> I32 {
    if num_example() == 34359738367 { return 0 }
    return 1
}
`,
		},
		"std.text-v1.al": {
			style:   "project",
			srcName: "std_text_example.al",
			mainText: `module hello.main

import hello.std_text_example { std_text_example }

pub fn main() -> I32 {
    if std_text_example() == 4095 { return 0 }
    return 1
}
`,
		},
		"std.collection-v1.al": {
			style:   "project",
			srcName: "std_collection_example.al",
			mainText: `module hello.main

import hello.std_collection_example { std_collection_example }

pub fn main() -> I32 {
    if std_collection_example() == 63 { return 0 }
    return 1
}
`,
		},
		"std.bytes-v1.al": {
			style:   "project",
			srcName: "std_bytes_example.al",
			mainText: `module hello.main

import hello.std_bytes_example { std_bytes_example }

pub fn main() -> I32 {
    if std_bytes_example() == 8388607 { return 0 }
    return 1
}
`,
		},
	}
}

// The frozen snapshot import lines form the hosted std module graph. The
// graph must stay acyclic — a cycle between modules can never build, since
// the driver rejects one with a canonical cycle path — so the snapshot docs
// reject a cycle the moment an import line introduces it. A missing
// docs/api directory or no std.*-v1.md files fails loudly rather than
// silently passing.
func TestDocsApiSnapshotImportsAcyclic(t *testing.T) {
	t.Parallel()
	apiDir := filepath.Join("..", "docs", "api")
	entries, err := os.ReadDir(apiDir)
	if err != nil {
		t.Fatal(err)
	}
	importLine := func(text string) (string, string, bool) {
		if !strings.HasPrefix(text, "import std.") {
			return "", "", false
		}
		rest := strings.TrimPrefix(text, "import std.")
		end := strings.IndexAny(rest, " \t{")
		if end < 0 {
			end = len(rest)
		}
		name := rest[:end]
		if name == "" {
			return "", "", false
		}
		return name, rest, true
	}
	edges := map[string][]string{}
	found := 0
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), "std.") || !strings.HasSuffix(entry.Name(), "-v1.md") {
			continue
		}
		module := strings.TrimSuffix(entry.Name(), "-v1.md")
		text, readErr := os.ReadFile(filepath.Join(apiDir, entry.Name()))
		if readErr != nil {
			t.Fatal(readErr)
		}
		found++
		seen := map[string]bool{}
		for _, line := range strings.Split(string(text), "\n") {
			line = strings.TrimSpace(line)
			name, _, ok := importLine(line)
			// The example block imports the module the snapshot documents;
			// that self-reference is not a dependency edge.
			if !ok || "std."+name == module || seen[name] {
				continue
			}
			seen[name] = true
			edges[module] = append(edges[module], "std."+name)
		}
	}
	if found == 0 {
		t.Fatal("no std.*-v1.md snapshots found under docs/api")
	}
	// Depth-first cycle detection with a sorted, deterministic visit order.
	var visit func(node string, path []string, onPath map[string]bool) []string
	visited := map[string]bool{}
	visit = func(node string, path []string, onPath map[string]bool) []string {
		if onPath[node] {
			return append(path, node)
		}
		if visited[node] {
			return nil
		}
		visited[node] = true
		onPath[node] = true
		successors := append([]string(nil), edges[node]...)
		sort.Strings(successors)
		for _, next := range successors {
			if cycle := visit(next, append(path, node), onPath); cycle != nil {
				return cycle
			}
		}
		delete(onPath, node)
		return nil
	}
	var roots []string
	for node := range edges {
		roots = append(roots, node)
	}
	sort.Strings(roots)
	for _, root := range roots {
		var onPath map[string]bool = map[string]bool{}
		if cycle := visit(root, nil, onPath); cycle != nil {
			t.Fatalf("snapshot import cycle: %s", strings.Join(cycle, " -> "))
		}
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
