package frontend

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/4fuu/alder/mir"
)

// allCompileSources returns every source fixture the frontend consumes.
func allCompileSources(t *testing.T) []string {
	t.Helper()
	var files []string
	for _, name := range acceptFixtures {
		files = append(files, filepath.Join("testdata", "accept", name+".al"))
	}
	for _, e2e := range e2eFixtures {
		files = append(files, filepath.Join("testdata", "e2e", e2e.src+".al"))
	}
	return files
}

// privateProfilePath reports whether the fixture at path needs the private
// bootstrap profile (see privateBootstrapAccept and e2eFixtures).
func privateProfilePath(path string) bool {
	name := strings.TrimSuffix(filepath.Base(path), ".al")
	switch name {
	case "domains", "maps":
		return filepath.Base(filepath.Dir(path)) == "e2e"
	case "buffer":
		if filepath.Base(filepath.Dir(path)) == "accept" {
			return privateBootstrapAccept[name]
		}
		return filepath.Base(filepath.Dir(path)) == "e2e"
	}
	return false
}

func compileDigest(t *testing.T, path string) string {
	t.Helper()
	src := readFixture(t, path)
	compile := Compile
	if privateProfilePath(path) {
		compile = CompilePrivate
	}
	m, err := compile(src)
	if err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	// Deterministic printed MIR plus the C backend output.
	out := mir.Print(m)
	c, err := generateC(m)
	if err != nil {
		t.Fatalf("%s: cgen: %v", path, err)
	}
	out += c
	sum := sha256.Sum256([]byte(out))
	return fmt.Sprintf("%x", sum)
}

// TestCompilationDeterminism recompiles every fixture repeatedly and
// requires identical printed MIR and generated C.
func TestCompilationDeterminism(t *testing.T) {
	for _, path := range allCompileSources(t) {
		name := filepath.Base(path)
		base := compileDigest(t, path)
		for i := 0; i < 10; i++ {
			if got := compileDigest(t, path); got != base {
				t.Fatalf("%s: digest changed on iteration %d", name, i)
			}
		}
	}
}

const compileHelperEnv = "ALDER_FRONTEND_DETERMINISM_HELPER"

// TestCompileHelper is run only by TestCrossProcessCompilationDeterminism.
func TestCompileHelper(t *testing.T) {
	outDir := os.Getenv(compileHelperEnv)
	if outDir == "" {
		return
	}
	var b []byte
	for _, path := range allCompileSources(t) {
		src := readFixture(t, path)
		compile := Compile
		if privateProfilePath(path) {
			compile = CompilePrivate
		}
		m, err := compile(src)
		if err != nil {
			fmt.Fprintf(os.Stderr, "helper: %s: %v\n", path, err)
			os.Exit(2)
		}
		c, err := generateC(m)
		if err != nil {
			fmt.Fprintf(os.Stderr, "helper: %s: cgen: %v\n", path, err)
			os.Exit(2)
		}
		b = append(b, []byte(path+"\n")...)
		b = append(b, []byte(mir.Print(m))...)
		b = append(b, []byte(c)...)
	}
	sum := sha256.Sum256(b)
	if err := os.WriteFile(filepath.Join(outDir, "manifest.txt"), []byte(fmt.Sprintf("%x\n", sum)), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "helper: %v\n", err)
		os.Exit(2)
	}
}

// TestCrossProcessCompilationDeterminism runs the whole pipeline in isolated
// processes with different working and temporary directories.
func TestCrossProcessCompilationDeterminism(t *testing.T) {
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	var manifests []string
	for i := 0; i < 2; i++ {
		dir := t.TempDir()
		cmd := exec.Command(exe, "-test.run", "^TestCompileHelper$")
		cmd.Env = append(os.Environ(),
			compileHelperEnv+"="+dir,
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
		t.Fatalf("cross-process manifests differ: %s vs %s", manifests[0], manifests[1])
	}
}
