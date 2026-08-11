package cgen

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/4fuu/aster/mir"
)

// TestSmoke generates C for the arithmetic golden and prints it, for review.
func TestSmoke(t *testing.T) {
	text, err := os.ReadFile(filepath.Join("..", "mir", "testdata", "golden", "arithmetic.mir"))
	if err != nil {
		t.Fatal(err)
	}
	m, err := mir.Parse(string(text))
	if err != nil {
		t.Fatal(err)
	}
	out, err := Generate(m)
	if err != nil {
		t.Fatal(err)
	}
	fmt.Println(out)
}
