package compiler

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

// The compiler package's heaviest tests rebuild the Alder compiler from
// compiler/src in every go test process: one Go-side compile of the source
// root (about 24 s) plus a strict C compile and link of the resulting 16 MB
// of generated C (about 14 s), and the core conformance test repeats that
// work for a different source set. Both artifacts are pure functions of
// their inputs, so identical inputs can reuse an identical artifact.

// artifactCacheEnv disables reuse across go test processes. Setting it to 0
// rebuilds everything; the assertions in both tests still run either way.
const artifactCacheEnv = "ALDER_TEST_CACHE"

// artifactCacheSchema is part of every cache key. Bump it whenever the
// meaning of a cached entry changes, so an old layout is never reused.
// "-2" moved the two heavy builds from one strict C object to the four
// strict-compiled parts of the shared bootstrap/split-c.awk splitter.
const artifactCacheSchema = "alder-go-test-artifact-2"

// cacheEnabled reports whether an identical artifact may be reused from a
// previous go test process.
func cacheEnabled() bool {
	return os.Getenv(artifactCacheEnv) != "0"
}

// cacheRoot returns the directory holding cached artifacts.
func cacheRoot() (string, error) {
	base, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "alder", "go-test"), nil
}

// artifactKey digests every input that can change an artifact: the test
// binary (so any change to the Go compiler code invalidates the entry), the
// named inputs, and the cache schema.
func artifactKey(t *testing.T, kind string, inputs ...string) string {
	t.Helper()
	digest := sha256.New()
	fmt.Fprintln(digest, artifactCacheSchema)
	fmt.Fprintln(digest, kind)
	exe, err := os.Executable()
	if err != nil {
		t.Fatalf("locate test binary: %v", err)
	}
	if err := hashFile(digest, exe); err != nil {
		t.Fatalf("digest test binary: %v", err)
	}
	for _, input := range inputs {
		fmt.Fprintln(digest, input)
	}
	return hex.EncodeToString(digest.Sum(nil))
}

// hashFile appends a file's bytes to digest.
func hashFile(digest io.Writer, path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = io.Copy(digest, file)
	return err
}

// compilerVersion reports the C compiler's identity, so a toolchain change
// invalidates every cached entry.
func compilerVersion(t *testing.T, cc string) string {
	t.Helper()
	out, err := exec.Command(cc, "--version").CombinedOutput()
	if err != nil {
		t.Logf("artifact cache: %s --version failed (%v); keying on the path only", cc, err)
		return cc
	}
	return cc + "\n" + string(out)
}

// loadOrBuild returns the directory holding the artifact named by key,
// running build to create it when no usable copy is cached. build writes
// its artifacts into the directory it is given and returns their names.
// Every failure to read, verify, or publish a cached copy falls back to a
// rebuild, so the cache can only cost time, never correctness.
func loadOrBuild(t *testing.T, key string, build func(dir string) ([]string, error)) string {
	t.Helper()
	if !cacheEnabled() {
		dir := scratchDir(t)
		if _, err := build(dir); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	root, err := cacheRoot()
	if err != nil {
		t.Logf("artifact cache: unavailable (%v); rebuilding", err)
		dir := scratchDir(t)
		if _, err := build(dir); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	entry := filepath.Join(root, key[:2], key)
	if dir, ok := reuse(key, entry); ok {
		t.Logf("artifact cache: reused %s", key[:12])
		return dir
	}
	if err := os.MkdirAll(filepath.Dir(entry), 0o755); err != nil {
		t.Logf("artifact cache: entry directory failed (%v); rebuilding", err)
		dir := scratchDir(t)
		if _, err := build(dir); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	prune(root)
	staging, err := os.MkdirTemp(filepath.Dir(entry), "staging-")
	if err != nil {
		t.Logf("artifact cache: staging directory failed (%v); rebuilding", err)
		dir := scratchDir(t)
		if _, err := build(dir); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	names, buildErr := build(staging)
	if buildErr != nil {
		_ = os.RemoveAll(staging)
		t.Fatal(buildErr)
	}
	if err := writeManifest(key, staging, names); err != nil {
		t.Logf("artifact cache: manifest failed (%v); rebuilding", err)
		_ = os.RemoveAll(staging)
		dir := scratchDir(t)
		if _, err := build(dir); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	if err := os.Rename(staging, entry); err != nil {
		// A concurrent process published the same key first, or the
		// filesystem refuses the rename. Retry once over an entry that is
		// present but unusable, so a damaged entry repairs itself instead of
		// forcing a rebuild on every later run.
		if _, ok := reuse(key, entry); !ok {
			if removeErr := os.RemoveAll(entry); removeErr == nil {
				err = os.Rename(staging, entry)
			}
		}
		if err != nil {
			_ = os.RemoveAll(staging)
			if dir, ok := reuse(key, entry); ok {
				t.Logf("artifact cache: reused %s", key[:12])
				return dir
			}
			dir := scratchDir(t)
			if _, err := build(dir); err != nil {
				t.Fatal(err)
			}
			return dir
		}
	}
	return entry
}

// scratchDirs holds directories built outside the cache. They outlive the
// test that triggered the build because parallel tests share the artifacts,
// so TestMain removes them once every test has finished.
var (
	scratchMu   sync.Mutex
	scratchDirs []string
)

// scratchDir creates a directory for an artifact built outside the cache.
// An empty directory would direct every build and host stub into the test
// binary's working directory (the package itself), so a failed allocation
// fails the test instead of returning "".
func scratchDir(t *testing.T) string {
	dir, err := os.MkdirTemp("", "alder-artifact-test-")
	if err != nil {
		t.Fatalf("scratch directory: %v", err)
	}
	scratchMu.Lock()
	scratchDirs = append(scratchDirs, dir)
	scratchMu.Unlock()
	return dir
}

// manifestName is the file recording an entry's artifact digests.
const manifestName = "artifacts.sha256"

// maxEntryAge bounds how long an unused cache entry is kept, so a cache
// warmed by many revisions does not grow without limit.
const maxEntryAge = 14 * 24 * time.Hour

// writeManifest records the entry's key and the digest of every artifact.
// The key is pinned so a manifest copied from another entry cannot
// validate this one's artifacts.
func writeManifest(key, dir string, names []string) error {
	artifacts := make([]string, 0, len(names))
	for _, name := range names {
		sum, err := fileDigest(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		artifacts = append(artifacts, sum+"  "+name)
	}
	sort.Strings(artifacts)
	lines := append([]string{"key " + key}, artifacts...)
	return os.WriteFile(filepath.Join(dir, manifestName), []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

// reuse verifies a cached entry and returns it when the manifest names this
// key and every recorded artifact is present with the recorded digest.
func reuse(key, entry string) (string, bool) {
	recorded, err := os.ReadFile(filepath.Join(entry, manifestName))
	if err != nil {
		return "", false
	}
	lines := strings.Split(strings.TrimSpace(string(recorded)), "\n")
	if len(lines) == 0 || lines[0] != "key "+key {
		return "", false
	}
	for _, line := range lines[1:] {
		if line == "" {
			continue
		}
		fields := strings.SplitN(line, "  ", 2)
		if len(fields) != 2 {
			return "", false
		}
		sum, err := fileDigest(filepath.Join(entry, fields[1]))
		if err != nil || sum != fields[0] {
			return "", false
		}
	}
	return entry, true
}

// prune removes cache entries that have not been touched recently. It is
// best effort: a failure only leaves the cache larger than intended.
func prune(root string) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-maxEntryAge)
	for _, shard := range entries {
		if !shard.IsDir() || len(shard.Name()) != 2 {
			continue
		}
		children, err := os.ReadDir(filepath.Join(root, shard.Name()))
		if err != nil {
			continue
		}
		for _, child := range children {
			if !child.IsDir() {
				continue
			}
			info, err := child.Info()
			if err != nil || info.ModTime().After(cutoff) {
				continue
			}
			_ = os.RemoveAll(filepath.Join(root, shard.Name(), child.Name()))
		}
	}
}

// fileDigest returns the hex SHA-256 of a file's contents.
func fileDigest(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}
