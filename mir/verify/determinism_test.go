package verify

import (
	"os"
	"path/filepath"
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
