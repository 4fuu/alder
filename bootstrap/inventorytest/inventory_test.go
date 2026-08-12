package inventorytest

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

var inventoryStrictFlags = []string{
	"-std=c11",
	"-Wall", "-Wextra", "-Werror", "-pedantic",
	"-Wshadow", "-Wconversion",
}

type inventoryResult struct {
	status int
	stdout string
	stderr string
}

func compileInventoryVerifier(t *testing.T) string {
	t.Helper()
	var names []string
	if runtime.GOOS == "windows" {
		names = []string{"gcc", "clang", "cc"}
	} else {
		names = []string{"gcc", "cc", "clang"}
	}
	var cc string
	for _, name := range names {
		if path, err := exec.LookPath(name); err == nil {
			cc = path
			break
		}
	}
	if cc == "" {
		t.Skip("no C compiler found (gcc, cc, or clang); inventory tests skipped")
	}
	exe := filepath.Join(t.TempDir(), "alder-inventory-verify")
	if runtime.GOOS == "windows" {
		exe += ".exe"
	}
	args := append([]string{}, inventoryStrictFlags...)
	args = append(args, filepath.Join("..", "inventory_verify.c"), "-o", exe)
	if output, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("strict C11 compile failed: %v\n%s", err, output)
	}
	return exe
}

func inventoryEntry(path string, data []byte) string {
	digest := sha256.Sum256(data)
	return fmt.Sprintf("%d %x %s\n", len(data), digest, path)
}

func sealInventory(body string) string {
	digest := sha256.Sum256([]byte(body))
	return fmt.Sprintf("%ssha256 %x\n", body, digest)
}

func writeInventoryFixture(t *testing.T, root string, files map[string][]byte) {
	t.Helper()
	for path, data := range files {
		full := filepath.Join(root, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func runInventory(t *testing.T, exe, manifest, root string) inventoryResult {
	t.Helper()
	command := exec.Command(exe, manifest, root)
	var stdout strings.Builder
	var stderr strings.Builder
	command.Stdout = &stdout
	command.Stderr = &stderr
	err := command.Run()
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("run verifier: %v", err)
		}
		status = exit.ExitCode()
	}
	return inventoryResult{status: status, stdout: stdout.String(), stderr: stderr.String()}
}

func writeManifest(t *testing.T, dir, text string) string {
	t.Helper()
	path := filepath.Join(dir, "compiler-sources.manifest")
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestInventoryVerifierSHA256Vectors(t *testing.T) {
	exe := compileInventoryVerifier(t)
	output, err := exec.Command(exe, "--self-test").CombinedOutput()
	if err != nil {
		t.Fatalf("SHA-256 self-test failed: %v\n%s", err, output)
	}
	if got, want := string(output), "alder inventory: SHA-256 self-test ok\n"; got != want {
		t.Fatalf("SHA-256 self-test output = %q, want %q", got, want)
	}
}

func TestInventoryVerifierValidAndPathIndependent(t *testing.T) {
	exe := compileInventoryVerifier(t)
	files := map[string][]byte{
		"compiler/src/empty.al": nil,
		"compiler/src/main.al":  []byte("fn main() -> I32 { return 0 }\n"),
		"compiler/src/raw.al":   {0x00, 0xff, 0x0a, 0x7f},
	}
	body := "ALDER-COMPILER-SOURCES 1\n" +
		inventoryEntry("compiler/src/empty.al", files["compiler/src/empty.al"]) +
		inventoryEntry("compiler/src/main.al", files["compiler/src/main.al"]) +
		inventoryEntry("compiler/src/raw.al", files["compiler/src/raw.al"])
	manifestText := sealInventory(body)
	var results []inventoryResult
	for _, name := range []string{"short", "a-much-longer-checkout-name"} {
		base := filepath.Join(t.TempDir(), name)
		root := filepath.Join(base, "source-root")
		if err := os.MkdirAll(root, 0o755); err != nil {
			t.Fatal(err)
		}
		writeInventoryFixture(t, root, files)
		// Unlisted files prove verification does not reject or inventory a tree walk.
		writeInventoryFixture(t, root, map[string][]byte{"compiler/src/unlisted.al": []byte("ignored")})
		manifest := writeManifest(t, base, manifestText)
		results = append(results, runInventory(t, exe, manifest, root))
	}
	want := inventoryResult{status: 0, stdout: "alder inventory: ok\n"}
	for i, result := range results {
		if result != want {
			t.Fatalf("valid result %d = %+v, want %+v", i, result, want)
		}
	}
	if results[0] != results[1] {
		t.Fatalf("result depends on host paths: %+v vs %+v", results[0], results[1])
	}
}

func TestInventoryVerifierRejectsInvalidInventories(t *testing.T) {
	exe := compileInventoryVerifier(t)
	dataA := []byte("alpha\n")
	dataB := []byte("beta\n")
	digestA := sha256.Sum256(dataA)
	digestB := sha256.Sum256(dataB)
	validBody := "ALDER-COMPILER-SOURCES 1\n" + inventoryEntry("a.al", dataA)
	tests := []struct {
		name     string
		manifest func() string
		files    map[string][]byte
		want     string
	}{
		{"header", func() string { return sealInventory("ALDER-COMPILER-SOURCES 2\n") }, nil, "alder inventory: line 1: invalid header\n"},
		{"malformed", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n6  " + fmt.Sprintf("%x a.al\n", digestA))
		}, nil, "alder inventory: line 2: invalid entry\n"},
		{"noncanonical-length", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n06 " + fmt.Sprintf("%x a.al\n", digestA))
		}, nil, "alder inventory: line 2: invalid entry\n"},
		{"uppercase-digest", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n6 " + strings.ToUpper(fmt.Sprintf("%x", digestA)) + " a.al\n")
		}, nil, "alder inventory: line 2: invalid entry\n"},
		{"order", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n" + inventoryEntry("b.al", dataB) + inventoryEntry("a.al", dataA))
		}, map[string][]byte{"a.al": dataA, "b.al": dataB}, "alder inventory: line 3: paths not in lexicographic order\n"},
		{"duplicate", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n" + inventoryEntry("a.al", dataA) + inventoryEntry("a.al", dataA))
		}, map[string][]byte{"a.al": dataA}, "alder inventory: line 3: duplicate path\n"},
		{"escape", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n6 " + fmt.Sprintf("%x ../a.al\n", digestA))
		}, nil, "alder inventory: line 2: noncanonical path\n"},
		{"absolute", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n6 " + fmt.Sprintf("%x /a.al\n", digestA))
		}, nil, "alder inventory: line 2: noncanonical path\n"},
		{"backslash", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n6 " + fmt.Sprintf("%x dir\\a.al\n", digestA))
		}, nil, "alder inventory: line 2: noncanonical path\n"},
		{"missing", func() string { return sealInventory(validBody) }, nil, "alder inventory: missing source: a.al\n"},
		{"length", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n7 " + fmt.Sprintf("%x a.al\n", digestA))
		}, map[string][]byte{"a.al": dataA}, "alder inventory: length mismatch: a.al\n"},
		{"digest", func() string {
			return sealInventory("ALDER-COMPILER-SOURCES 1\n6 " + fmt.Sprintf("%x a.al\n", digestB))
		}, map[string][]byte{"a.al": dataA}, "alder inventory: digest mismatch: a.al\n"},
		{"manifest-digest", func() string { return validBody + "sha256 " + strings.Repeat("0", 64) + "\n" }, map[string][]byte{"a.al": dataA}, "alder inventory: manifest digest mismatch\n"},
		{"missing-digest", func() string { return validBody }, map[string][]byte{"a.al": dataA}, "alder inventory: line 3: missing manifest digest\n"},
		{"missing-final-lf", func() string { return strings.TrimSuffix(sealInventory(validBody), "\n") }, map[string][]byte{"a.al": dataA}, "alder inventory: line 3: missing final line feed\n"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			root := filepath.Join(dir, "root")
			if err := os.MkdirAll(root, 0o755); err != nil {
				t.Fatal(err)
			}
			writeInventoryFixture(t, root, tc.files)
			manifest := writeManifest(t, dir, tc.manifest())
			result := runInventory(t, exe, manifest, root)
			if result.status != 1 || result.stdout != "" || result.stderr != tc.want {
				t.Fatalf("result = %+v, want status 1, empty stdout, stderr %q", result, tc.want)
			}
		})
	}
}

func TestInventoryVerifierFailureDiagnosticIsPathIndependent(t *testing.T) {
	exe := compileInventoryVerifier(t)
	body := "ALDER-COMPILER-SOURCES 1\n" + inventoryEntry("compiler/src/missing.al", []byte("absent"))
	want := inventoryResult{status: 1, stderr: "alder inventory: missing source: compiler/src/missing.al\n"}
	var first inventoryResult
	for i, name := range []string{"one", "different/long/root"} {
		dir := filepath.Join(t.TempDir(), name)
		root := filepath.Join(dir, "root")
		if err := os.MkdirAll(root, 0o755); err != nil {
			t.Fatal(err)
		}
		result := runInventory(t, exe, writeManifest(t, dir, sealInventory(body)), root)
		if result != want {
			t.Fatalf("result = %+v, want %+v", result, want)
		}
		if i == 0 {
			first = result
		} else if result != first {
			t.Fatalf("failure depends on host paths: %+v vs %+v", first, result)
		}
	}
}

func TestInventoryVerifierUsageStatus(t *testing.T) {
	exe := compileInventoryVerifier(t)
	command := exec.Command(exe)
	output, err := command.CombinedOutput()
	exit, ok := err.(*exec.ExitError)
	if !ok || exit.ExitCode() != 2 {
		t.Fatalf("usage status = %v, want 2; output: %s", err, output)
	}
	if got, want := string(output), "usage: alder-inventory-verify MANIFEST ROOT\n"; got != want {
		t.Fatalf("usage output = %q, want %q", got, want)
	}
}
