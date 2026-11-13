package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// core.iter's first slice: the checker materializes the builtin
// IntoIterator surface for slices and Vec as the installed module's
// SliceIter/VecIter snapshot, and the source Iterator impls advance it.
// Adapter inference is the next slice and is not exercised here.
func TestProductionCoreIterRuns(t *testing.T) {
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

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    values.push(3)

    let view = values.slice(0, 3)
    var slice_cursor = view.into_iterator()
    let first = slice_cursor.next()
    if first != Some(1) { return 1 }
    let second = slice_cursor.next()
    if second != Some(2) { return 2 }
    let rest = slice_cursor.to_vec()
    if rest.len() != 1 || rest[0] != 3 { return 3 }

    let whole = values.into_iterator().to_vec()
    if whole.len() != 3 { return 4 }
    if whole[0] != 1 || whole[1] != 2 || whole[2] != 3 { return 5 }
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("core.iter behavior: %+v stderr=%s", result, result.stderr)
	}
}

func TestProductionCoreIterRejections(t *testing.T) {
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
	cases := []struct {
		name, source, want string
	}{
		{
			name: "missing-module",
			source: `module hello.main

pub fn main() -> I32 {
    var values = Vec.new(U64)
    let it = values.slice(0, 0).into_iterator()
    return 0
}
`,
			want: "into_iterator could not find the imported core.iter module",
		},
		{
			name: "wrong-arity",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    let it = values.slice(0, 0).into_iterator(1)
    return 0
}
`,
			want: "into_iterator takes no arguments",
		},
		{
			name: "unsupported-receiver",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    let text = "abc"
    let it = text.into_iterator()
    return 0
}
`,
			want: "into_iterator is available on slices and Vec",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
				"src/main.al": tc.source,
			}, "check")
			if result.status == 0 {
				t.Fatalf("%s accepted: %+v", tc.name, result)
			}
			if !strings.Contains(result.stderr, tc.want) {
				t.Fatalf("%s diagnostic = %q, want %q", tc.name, result.stderr, tc.want)
			}
		})
	}
}
