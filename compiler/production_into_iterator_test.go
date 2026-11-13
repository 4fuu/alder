package compiler

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// intoIteratorFixture is a minimal core.iter module for the builtin
// IntoIterator regression. The real module lands with the rest of the M8.1
// iterator surface; this fixture supplies only the constructors and methods
// the checker and lowering must handle, so the builtin call representation is
// pinned without freezing the module itself.
const intoIteratorFixture = `module core.iter

pub type SliceIter(T: type) {
    values: Vec(T)
    at: U64
}

pub type VecIter(T: type) {
    values: Vec(T)
    at: U64
}

pub fn slice_iter(T: type, values: [T]) -> SliceIter(T) {
    var copied = Vec.new(T)
    var at: U64 = 0
    while at < values.len() {
        copied.push(values[at])
        at = at + 1
    }
    return SliceIter(values: copied, at: 0)
}

pub fn vec_iter(T: type, values: Vec(T)) -> VecIter(T) {
    return VecIter(values: values, at: 0)
}

impl(T: type) SliceIter(T) {
    fn to_vec(self) -> Vec(T) {
        var values = Vec.new(T)
        var index = self.at
        while index < self.values.len() {
            values.push(self.values[index])
            index = index + 1
        }
        return values
    }
}

impl(T: type) VecIter(T) {
    fn to_vec(self) -> Vec(T) {
        var values = Vec.new(T)
        var index = self.at
        while index < self.values.len() {
            values.push(self.values[index])
            index = index + 1
        }
        return values
    }
}

impl(T: type) Iterator(T) for SliceIter(T) {
    fn next(mut self) -> Option(T) {
        if self.at >= self.values.len() { return None }
        let index = self.at
        self.at = self.at + 1
        return self.values.get(index)
    }
}

impl(T: type) Iterator(T) for VecIter(T) {
    fn next(mut self) -> Option(T) {
        if self.at >= self.values.len() { return None }
        let index = self.at
        self.at = self.at + 1
        return self.values.get(index)
    }
}

pub type MapIter(I: type, T: type, U: type) {
    inner: I
    f: fn(T) -> U
}

pub fn map(I: type(Iterator(T)), T: type, U: type, f: fn(T) -> U, iterator: I) -> MapIter(I, T, U) {
    return MapIter(inner: iterator, f: f)
}

impl(I: type(Iterator(T)), T: type, U: type) Iterator(U) for MapIter(I, T, U) {
    fn next(mut self) -> Option(U) {
        match self.inner.next() {
            Some(value) => {
                let transform = self.f
                return Some(transform(value))
            }
            None => { return None }
        }
        return None
    }
}

pub fn count(I: type(Iterator(T)), T: type, mut iterator: I) -> U64 {
    var total: U64 = 0
    var running = true
    while running {
        match iterator.next() {
            Some(_) => { total = total + 1 }
            None => { running = false }
        }
    }
    return total
}

pub fn to_vec(I: type(Iterator(T)), T: type, mut iterator: I) -> Vec(T) {
    var values = Vec.new(T)
    var running = true
    while running {
        match iterator.next() {
            Some(value) => { values.push(value) }
            None => { running = false }
        }
    }
    return values
}
`

// intoIteratorSysroot copies the installed sysroot and adds the fixture
// module, so a test can exercise the builtin route while main still has no
// core.iter module.
func intoIteratorSysroot(t *testing.T, repoRoot string) string {
	t.Helper()
	target := t.TempDir()
	source := filepath.Join(repoRoot, "sysroot")
	err := filepath.Walk(source, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		destination := filepath.Join(target, relative)
		if info.IsDir() {
			return os.MkdirAll(destination, 0o755)
		}
		input, err := os.Open(path)
		if err != nil {
			return err
		}
		output, err := os.Create(destination)
		if err != nil {
			input.Close()
			return err
		}
		copied, copyErr := io.Copy(output, input)
		input.Close()
		closeErr := output.Close()
		if copyErr != nil {
			return copyErr
		}
		if copied != info.Size() {
			return io.ErrShortWrite
		}
		return closeErr
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "core", "iter.al"), []byte(intoIteratorFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	return target
}

func intoIteratorManifest() string {
	return "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
}

// A builtin into_iterator call is a real checked call expression: the
// constructor instance is its target, its result type is concrete, and a
// following method call sees the same type store. This was a production
// segfault and then a lowering-model refusal in earlier revisions.
func TestProductionIntoIteratorBuiltinRuns(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(intoIteratorSysroot(t, repoRoot))
	files := map[string]string{
		"alder.toml": intoIteratorManifest(),
		"src/main.al": `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    values.push(3)

    var cursor = values.slice(0, 3).into_iterator()
    if cursor.next() != Some(1) { return 1 }
    if cursor.next() != Some(2) { return 2 }
    let rest = cursor.to_vec()
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
		t.Fatalf("into_iterator behavior: %+v stderr=%s", result, result.stderr)
	}
}

func TestProductionIntoIteratorBuiltinRejections(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(intoIteratorSysroot(t, repoRoot))
	cases := []struct {
		name, source, want string
	}{
		{
			name: "missing-import",
			source: `module hello.main

pub fn main() -> I32 {
    var values = Vec.new(U64)
    let it = values.into_iterator()
    return 0
}
`,
			want: "into_iterator requires the core.iter module",
		},
		{
			name: "wrong-arity",
			source: `module hello.main

import core.iter

pub fn main() -> I32 {
    var values = Vec.new(U64)
    let it = values.into_iterator(1)
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
				"alder.toml":  intoIteratorManifest(),
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

// A constraint's parameters are seeded from the implementation that matches
// the receiver, so count(map(f, it)) infers the map item type from the
// iterator implementation alone. The impl's trait argument is a compound
// application (Iterator(Indexed(T))), which the same match has to accept.
func TestProductionIteratorConstraintInference(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(intoIteratorSysroot(t, repoRoot))
	files := map[string]string{
		"alder.toml": intoIteratorManifest(),
		"src/main.al": `module hello.main

import core.iter

type Indexed(T: type) {
    value: T
}

type IndexedIter(T: type) {
    value: T
    done: Bool
}

impl(T: type) Iterator(Indexed(T)) for IndexedIter(T) {
    fn next(mut self) -> Option(Indexed(T)) {
        if self.done { return None }
        self.done = true
        return Some(Indexed(value: self.value))
    }
}

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    values.push(2)
    var mapped = iter.map(fn(x: U64) => x + 1, values.into_iterator())
    if iter.count(mapped) != 2 { return 1 }

    var indexed = IndexedIter(U64)(value: 7, done: false)
    let items = iter.to_vec(indexed)
    if items.len() != 1 { return 2 }
    if items[0].value != 7 { return 3 }
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("iterator constraint inference: %+v stderr=%s", result, result.stderr)
	}
}

// A parameter or local named iter shadows the core.iter import namespace.
// Before the parser scoped bindings per source, an earlier source's bindings
// filled the visible prefix and the new binding was invisible, so iter.next()
// parsed as an associated module call and failed with the wrong arity. The
// same name must work in the entry module and in an imported module, while a
// receiver that does not implement Iterator(U64) is still rejected.
func TestProductionImportNamespaceShadowing(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(intoIteratorSysroot(t, repoRoot))
	files := map[string]string{
		"alder.toml": intoIteratorManifest(),
		"src/iteruser.al": `module hello.iteruser

import core.iter

pub fn first_of(I: type(Iterator(U64)), mut iter: I) -> Option(U64) {
    return iter.next()
}
`,
		"src/main.al": `module hello.main

import core.iter
import hello.iteruser

fn local_first(I: type(Iterator(U64)), mut iter: I) -> Option(U64) {
    return iter.next()
}

pub fn main() -> I32 {
    var values = Vec.new(U64)
    values.push(1)
    var local = values.into_iterator()
    if local_first(local) != Some(1) { return 1 }

    var remote_values = Vec.new(U64)
    remote_values.push(2)
    var remote = remote_values.into_iterator()
    if iteruser.first_of(remote) != Some(2) { return 2 }
    return 0
}
`,
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("import namespace shadowing: %+v stderr=%s", result, result.stderr)
	}

	rejected := map[string]string{
		"alder.toml": intoIteratorManifest(),
		"src/main.al": `module hello.main

fn first_of(I: type(Iterator(U64)), mut iter: I) -> Option(U64) {
    return iter.next()
}

pub fn main() -> I32 {
    var number: U64 = 5
    let value = first_of(number)
    return 0
}
`,
	}
	bad := runProductionCompilerEnv(t, exe, t.TempDir(), env, rejected, "check")
	if bad.status == 0 {
		t.Fatalf("non-iterator receiver accepted: %+v", bad)
	}
	if !strings.Contains(bad.stderr, "does not implement a trait required here") {
		t.Fatalf("non-iterator receiver diagnostic = %q", bad.stderr)
	}
}
