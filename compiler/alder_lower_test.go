package compiler

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

func runLowerConformance(t *testing.T, exe string) {
	t.Helper()
	files := map[string]string{
		"scalar.al": `fn calculate(value: U64) -> U64 {
    return value + 1
}
`,
	}
	first := runLowerCompiler(t, exe, files, []string{"scalar.al"})
	second := runLowerCompiler(t, exe, files, []string{"scalar.al"})
	if !bytes.Equal(first, second) {
		t.Fatal("lowered MIR changed across processes")
	}
	module, err := mir.Parse(string(first))
	if err != nil {
		t.Fatalf("parse lowered MIR: %v\n%s", err, first)
	}
	if diagnostics := verify.Module(module); len(diagnostics) != 0 {
		t.Fatalf("verify lowered MIR: %s\n%s", verify.Errors(diagnostics), first)
	}
	for _, name := range []string{"calculate"} {
		if _, ok := module.Function(name); !ok {
			t.Fatalf("lowered MIR has no function %q\n%s", name, first)
		}
	}
}

func runLowerCompiler(t *testing.T, exe string, files map[string]string, order []string) []byte {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "!alder-core-lower"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	args := append([]string{"!alder-core-lower"}, order...)
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("run lower compiler: %v\nstdout:\n%s\nstderr:\n%s", err, stdout.Bytes(), stderr.Bytes())
	}
	if stderr.Len() != 0 {
		t.Fatalf("lower compiler wrote stderr: %s", stderr.Bytes())
	}
	return stdout.Bytes()
}
