package verify

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/4fuu/aster/mir"
)

// allFixtures returns every textual MIR fixture used by the test suite.
func allFixtures(t *testing.T) []string {
	t.Helper()
	var files []string
	for _, dir := range []string{
		filepath.Join("..", "testdata", "golden"),
		filepath.Join("testdata", "verify", "accept"),
		filepath.Join("testdata", "verify", "reject"),
	} {
		got, err := filepath.Glob(filepath.Join(dir, "*.mir"))
		if err != nil {
			t.Fatal(err)
		}
		files = append(files, got...)
	}
	if len(files) == 0 {
		t.Fatal("no fixtures found")
	}
	sort.Strings(files)
	return files
}

func runPipeline(text string) string {
	m, err := mir.Parse(text)
	if err != nil {
		return "parse: " + err.Error()
	}
	var b strings.Builder
	b.WriteString(mir.Print(m))
	b.WriteString("\n---\n")
	b.WriteString(Errors(Module(m)).String())
	return b.String()
}

// TestPipelineDeterminism runs parse -> print -> verify repeatedly over every
// fixture and requires byte-identical results, guarding against map iteration
// order and other host nondeterminism anywhere in the pipeline.
func TestPipelineDeterminism(t *testing.T) {
	for _, path := range allFixtures(t) {
		name := filepath.Base(path)
		text, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		base := runPipeline(string(text))
		for i := 0; i < 25; i++ {
			if got := runPipeline(string(text)); got != base {
				t.Fatalf("%s: pipeline output changed on iteration %d\n--- first ---\n%s\n--- later ---\n%s", name, i, base, got)
			}
		}
	}
}

const determinismHelperEnv = "ASTER_DETERMINISM_HELPER"

// TestPipelineDeterminismHelper is run only by TestPipelineCrossProcessDeterminism.
// The parent supplies the package directory because each helper has a distinct cwd.
func TestPipelineDeterminismHelper(t *testing.T) {
	packageDir := os.Getenv(determinismHelperEnv)
	if packageDir == "" {
		return
	}
	if err := writeCrossProcessResult(packageDir); err != nil {
		fmt.Fprintf(os.Stderr, "determinism helper: %v\n", err)
		os.Exit(2)
	}
}

func writeCrossProcessResult(packageDir string) error {
	dirs := []struct {
		label string
		path  string
	}{
		{"golden", filepath.Join(packageDir, "..", "testdata", "golden")},
		{"accept", filepath.Join(packageDir, "testdata", "verify", "accept")},
		{"reject", filepath.Join(packageDir, "testdata", "verify", "reject")},
	}
	type fixture struct {
		label string
		path  string
	}
	var fixtures []fixture
	for _, dir := range dirs {
		paths, err := filepath.Glob(filepath.Join(dir.path, "*.mir"))
		if err != nil {
			return fmt.Errorf("find %s fixtures: %w", dir.label, err)
		}
		for _, path := range paths {
			fixtures = append(fixtures, fixture{dir.label + "/" + filepath.Base(path), path})
		}
	}
	sort.Slice(fixtures, func(i, j int) bool { return fixtures[i].label < fixtures[j].label })
	if len(fixtures) == 0 {
		return fmt.Errorf("no fixtures found")
	}

	for _, fixture := range fixtures {
		text, err := os.ReadFile(fixture.path)
		if err != nil {
			return fmt.Errorf("read %s: %w", fixture.label, err)
		}
		result := runPipeline(string(text))
		// Length-prefix both stable fields so arbitrary MIR and diagnostics remain
		// unambiguous without exposing the absolute fixture path.
		if _, err := fmt.Fprintf(os.Stdout, "%d:%s%d:%s", len(fixture.label), fixture.label, len(result), result); err != nil {
			return fmt.Errorf("write %s result: %w", fixture.label, err)
		}
	}
	return nil
}

func TestPipelineCrossProcessDeterminism(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	packageDir, err := filepath.Abs(".")
	if err != nil {
		t.Fatal(err)
	}

	const processCount = 5
	var baseline []byte
	for i := 0; i < processCount; i++ {
		workDir := t.TempDir()
		cmd := exec.Command(executable, "-test.run=^TestPipelineDeterminismHelper$", "-test.count=1")
		cmd.Dir = workDir
		cmd.Env = append(os.Environ(),
			determinismHelperEnv+"="+packageDir,
			"TMP="+workDir,
			"TEMP="+workDir,
			"TMPDIR="+workDir,
		)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			t.Fatalf("helper process %d failed: %v\nstderr:\n%s\nstdout:\n%s", i, err, stderr.String(), stdout.String())
		}
		if i == 0 {
			baseline = append([]byte(nil), stdout.Bytes()...)
			continue
		}
		if !bytes.Equal(stdout.Bytes(), baseline) {
			t.Fatalf("helper process %d produced different output\n--- first ---\n%s\n--- process %d ---\n%s", i, baseline, i, stdout.Bytes())
		}
	}
}
