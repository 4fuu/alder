package compiler

import (
	"path/filepath"
	"testing"
)

// Bytes.into_iterator resolves core.iter's bytes_iter, the only constructor
// with no type parameters. It therefore has no instance record: the checker
// must read the declaration's role-5 parameters, and lowering must accept the
// kind-12 declaration symbol. This is the public regression for that path.
func TestProductionBytesIntoIteratorDeclarationConstructor(t *testing.T) {
	t.Parallel()
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, "cc", root)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(root, "sysroot")), map[string]string{
		"alder.toml": snapshotProjectManifest,
		"src/main.al": `module hello.main

import core.iter

pub fn main() -> I32 {
    let bytes: Bytes = "\x00\x7f\xff"
    var cursor = bytes.into_iterator()
    let out = iter.to_vec(cursor)
    if out.len() != 3 { return 1 }
    if out[0] != 0 || out[1] != 127 || out[2] != 255 { return 2 }
    return 0
}
`,
	}, "run")
	if result.status != 0 || result.stderr != "" {
		t.Fatalf("Bytes.into_iterator: %+v", result)
	}
}
