package cgen

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// allGenerateInputs returns every MIR fixture the backend consumes.
func allGenerateInputs(t *testing.T) []string {
	t.Helper()
	var files []string
	for _, name := range goldenSources {
		files = append(files, goldenMirPath(name))
	}
	run, err := filepath.Glob(filepath.Join("testdata", "run", "*.mir"))
	if err != nil {
		t.Fatal(err)
	}
	files = append(files, run...)
	return files
}

// generateDigest returns a stable digest of the generated C for one fixture.
func generateDigest(t *testing.T, path string) string {
	t.Helper()
	out := generatePath(t, path)
	sum := sha256.Sum256([]byte(out))
	return fmt.Sprintf("%x", sum)
}

// TestGenerationDeterminism regenerates every fixture repeatedly and requires
// byte-identical output.
func TestGenerationDeterminism(t *testing.T) {
	for _, path := range allGenerateInputs(t) {
		name := filepath.Base(path)
		base := generateDigest(t, path)
		for i := 0; i < 25; i++ {
			if got := generateDigest(t, path); got != base {
				t.Fatalf("%s: digest changed on iteration %d: %s vs %s", name, i, got, base)
			}
		}
	}
}

const determinismHelperEnv = "ASTER_CGEN_DETERMINISM_HELPER"

// TestDeterminismHelper is run only by TestCrossProcessDeterminism. The
// parent supplies the output directory; each helper runs with a distinct
// working directory and temp directory.
func TestDeterminismHelper(t *testing.T) {
	outDir := os.Getenv(determinismHelperEnv)
	if outDir == "" {
		return
	}
	var b strings.Builder
	for _, path := range allGenerateInputs(t) {
		out := generatePath(t, path)
		sum := sha256.Sum256([]byte(out))
		fmt.Fprintf(&b, "%s %x\n", filepath.Base(path), sum)
	}
	if err := os.WriteFile(filepath.Join(outDir, "manifest.txt"), []byte(b.String()), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "determinism helper: %v\n", err)
		os.Exit(2)
	}
}

// TestCrossProcessDeterminism runs the generator in isolated processes with
// different working and temporary directories and requires identical
// manifests. The helper re-executes this test binary, which keeps the check
// self-contained and free of host absolute paths.
func TestCrossProcessDeterminism(t *testing.T) {
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	var manifests []string
	for i := 0; i < 2; i++ {
		dir := t.TempDir()
		cmd := exec.Command(exe, "-test.run", "^TestDeterminismHelper$")
		cmd.Env = append(os.Environ(),
			determinismHelperEnv+"="+dir,
			"TMP="+t.TempDir(),
			"TEMP="+t.TempDir(),
			"TMPDIR="+t.TempDir(),
		)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("helper %d failed: %v\n%s", i, err, out)
		}
		manifest, err := os.ReadFile(filepath.Join(dir, "manifest.txt"))
		if err != nil {
			t.Fatal(err)
		}
		manifests = append(manifests, string(manifest))
	}
	if manifests[0] != manifests[1] {
		t.Fatalf("cross-process manifests differ:\n--- first ---\n%s\n--- second ---\n%s", manifests[0], manifests[1])
	}
}
