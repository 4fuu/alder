package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// File methods and the free whole-file helpers live in separate fixtures:
// importing `read` from std.fs and then calling `file.read(...)` currently
// resolves the dotted call against the imported free function, so the method
// fixture imports no colliding free function. Both fixtures share the same
// on-disk probe file, which the Go harness resets between runs.
const fsFileProgram = `module hello.main

import std.fs { File, Permissions }
import std.io { Blocking, IoError, Reader, Seek, SeekFrom, Writer }
import std.path { Path }

fn io_path(value: String) -> Result(Path, IoError) {
    match Path.parse(value) {
        Ok(parsed) => { return Ok(parsed) }
        Err(_) => { return Err(IoError.InvalidInput) }
    }
    return Err(IoError.InvalidInput)
}

fn close_through_using(cap: Blocking, path: Path) -> Result(Unit, IoError) {
    using file = try File.open(cap, path)
    return Ok(())
}

fn probe_main(cap: Blocking) -> Result(I32, IoError) {
    let path = try io_path("/tmp/alder-fs-probe.txt")
    try close_through_using(cap, path)
    let file: File(Blocking) = try File.open(cap, path)
    let info = try file.metadata()
    var code: I32 = 0
    if info.length != 2 || info.modified.unix_seconds() != -1 { code = 3 }
    if !info.permissions.readable || info.permissions.executable { code = 4 }
    try file.seek(SeekFrom.Start(1))
    var one: Array(U8, 1) = [0]
    let count = try file.read(one.slice_mut(0, 1))
    if count != 1 || one[0] != 105 { code = 5 }
    try file.finish()
    if code != 0 { return Ok(code) }
    let made: File(Blocking) = try File.create(cap, path)
    let data: Array(U8, 2) = [111, 107]
    let written = try made.write(data.slice(0, 2))
    if written != 2 { code = 6 }
    try made.set_permissions(Permissions(readable: true, writable: false, executable: true))
    try made.finish()
    if code != 0 { return Ok(code) }
    let tuned: File(Blocking) = try File.open(cap, path)
    let tuned_info = try tuned.metadata()
    if !tuned_info.permissions.executable || tuned_info.permissions.writable { code = 7 }
    try tuned.finish()
    return Ok(code)
}

fn main() -> I32 {
    let cap = Blocking()
    match probe_main(cap) {
        Ok(code) => { return code }
        Err(_) => { return 90 }
    }
    return 91
}
`

const fsFreeProgram = `module hello.main

import std.fs { make_dir, metadata, read, read_text, remove_dir, remove_file, rename, write_text }
import std.io { Blocking, IoError }
import std.path { Path }

fn io_path(value: String) -> Result(Path, IoError) {
    match Path.parse(value) {
        Ok(parsed) => { return Ok(parsed) }
        Err(_) => { return Err(IoError.InvalidInput) }
    }
    return Err(IoError.InvalidInput)
}

fn probe_main(cap: Blocking) -> Result(I32, IoError) {
    let path = try io_path("/tmp/alder-fs-probe.txt")
    let info = try metadata(cap, path)
    if info.length != 2 { return Ok(1) }
    if info.modified.unix_seconds() != -1 { return Ok(2) }
    let data = try read(cap, path)
    if data.len() != 2 || data[0] != 104 || data[1] != 105 { return Ok(3) }
    try write_text(cap, path, "text")
    let content = try read_text(cap, path)
    if content != "text" { return Ok(4) }
    let moved = try io_path("/tmp/alder-fs-probe-moved.txt")
    try rename(cap, path, moved)
    let after = try read_text(cap, moved)
    if after != "text" { return Ok(5) }
    let dir = try io_path("/tmp/alder-fs-probe-dir")
    try make_dir(cap, dir)
    try remove_dir(cap, dir)
    try remove_file(cap, moved)
    return Ok(0)
}

fn main() -> I32 {
    let cap = Blocking()
    match probe_main(cap) {
        Ok(code) => { return code }
        Err(_) => { return 90 }
    }
    return 91
}
`

const fsDirectoryProgram = `module hello.main

import std.fs { metadata, read_dir, read_dir_sorted, remove_dir_all }
import std.io { Blocking, EntryKind, IoError }
import std.path { Path }

fn io_path(value: String) -> Result(Path, IoError) {
    match Path.parse(value) {
        Ok(parsed) => { return Ok(parsed) }
        Err(_) => { return Err(IoError.InvalidInput) }
    }
    return Err(IoError.InvalidInput)
}

fn probe_main(cap: Blocking) -> Result(I32, IoError) {
    let dir = try io_path("/tmp/alder-fs-tree")
    let sorted = try read_dir_sorted(cap, dir)
    if sorted.len() != 5 { return Ok(1) }
    if sorted[0].name.to_bytes() != "a".to_bytes() { return Ok(2) }
    if sorted[1].name.to_bytes() != "b".to_bytes() { return Ok(3) }
    if sorted[2].name.to_bytes() != "c".to_bytes() { return Ok(4) }
    if sorted[3].name.to_bytes() != "link".to_bytes() { return Ok(5) }
    if sorted[4].name.to_bytes() != "sub".to_bytes() { return Ok(6) }
    if sorted[3].kind != EntryKind.Symlink { return Ok(7) }
    using listing = try read_dir(cap, dir)
    var count: U64 = 0
    var reading = true
    while reading {
        let item = try listing.next()
        match item {
            Some(value) => {
                let name = value.name.to_bytes()
                if name.len() == 1 && name.byte(0) == 46 { return Ok(8) }
                if name.len() == 2 && name.byte(0) == 46 && name.byte(1) == 46 { return Ok(9) }
                count = count + 1
            }
            None => { reading = false }
        }
    }
    try listing.close()
    if count != 5 { return Ok(10) }
    try remove_dir_all(cap, dir)
    match metadata(cap, dir) {
        Ok(_) => { return Ok(11) }
        Err(_) => {}
    }
    return Ok(0)
}

fn main() -> I32 {
    let cap = Blocking()
    match probe_main(cap) {
        Ok(code) => { return code }
        Err(_) => { return 90 }
    }
    return 91
}
`

const fsTempProgram = `module hello.main

import std.env
import std.fs { TempDir, TempFile, metadata, temp_root, write }
import std.io { Blocking, IoError }
import std.path { OsString, Path }

fn env_key(value: String) -> Result(OsString, IoError) {
    match OsString.parse(value) {
        Ok(parsed) => { return Ok(parsed) }
        Err(_) => { return Err(IoError.InvalidInput) }
    }
    return Err(IoError.InvalidInput)
}

fn make_temp_file(cap: Blocking) -> Result(Path, IoError) {
    using file = try TempFile.new(cap, "probe")
    return Ok(file.path())
}

fn make_temp_dir(cap: Blocking) -> Result(Path, IoError) {
    using directory = try TempDir.new(cap, "dir")
    let path = directory.path()
    let inner_name = try env_key("inner")
    let inner = path.join(Path.from_os(inner_name))
    let payload: Array(U8, 1) = [120]
    try write(cap, inner, payload.slice(0, 1))
    return Ok(path)
}

fn probe_main(cap: Blocking) -> Result(I32, IoError) {
    let root = try temp_root(cap)
    let key = try env_key("TMPDIR")
    match env.get(key) {
        Some(value) => {
            if root.to_os().to_bytes() != value.to_bytes() { return Ok(1) }
        }
        None => { return Ok(2) }
    }
    let file_path = try make_temp_file(cap)
    match metadata(cap, file_path) {
        Ok(_) => { return Ok(3) }
        Err(_) => {}
    }
    let dir_path = try make_temp_dir(cap)
    match metadata(cap, dir_path) {
        Ok(_) => { return Ok(4) }
        Err(_) => {}
    }
    return Ok(0)
}

fn main() -> I32 {
    let cap = Blocking()
    match probe_main(cap) {
        Ok(code) => { return code }
        Err(_) => { return 90 }
    }
    return 91
}
`

func resetFsProbeFile(t *testing.T) {
	t.Helper()
	path := "/tmp/alder-fs-probe.txt"
	_ = os.Chmod(path, 0o644)
	if err := os.WriteFile(path, []byte("hi"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0o644); err != nil {
		t.Fatal(err)
	}
	stamp := time.Unix(-1, 0)
	if err := os.Chtimes(path, stamp, stamp); err != nil {
		t.Fatal(err)
	}
}

// TestFsBorrowedOwnerParametersRejected pins the ownership boundary for the
// installed std.fs owners. A borrowed File or TempDir is not the caller's
// owner, so registering it with using inside the callee is rejected.
func TestFsBorrowedOwnerParametersRejected(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	cases := []struct{ name, source string }{
		{
			"file",
			`module hello.main

import std.fs { File }
import std.io { Blocking }

fn consume(file: File(Blocking)) -> Unit {
    using held = file
    return
}

pub fn main() -> I32 { return 0 }
`,
		},
		{
			"temp-dir",
			`module hello.main

import std.fs { TempDir }
import std.io { Blocking }

fn consume(directory: TempDir(Blocking)) -> Unit {
    using held = directory
    return
}

pub fn main() -> I32 { return 0 }
`,
		},
	}
	for _, item := range cases {
		item := item
		t.Run(item.name, func(t *testing.T) {
			check := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
				"alder.toml":  manifest,
				"src/main.al": item.source,
			}, "check")
			if check.status == 0 {
				t.Fatalf("%s borrowed owner was accepted:\n%s", item.name, check.stdout)
			}
			if !strings.Contains(check.stderr, "a borrowed parameter cannot be used as an owner") {
				t.Fatalf("%s diagnostic: status=%d stderr=%s", item.name, check.status, check.stderr)
			}
		})
	}
}

// TestFsBorrowedOwnerReadsAllowed keeps field reads through self methods and
// forwarding to another ordinary parameter available on borrowed File and
// TempDir values. The program releases both owners once through using, and the
// sanitizer rerun checks that no second release occurred.
func TestFsBorrowedOwnerReadsAllowed(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	source := `module hello.main

import std.fs { File, TempDir }
import std.io { Blocking, IoError }
import std.path { Path }

fn forward_file(file: File(Blocking)) -> Unit {
    return
}

fn dir_path(directory: TempDir(Blocking)) -> Path {
    return directory.path()
}

fn probe(cap: Blocking, path: Path) -> Result(I32, IoError) {
    using file = try File.open(cap, path)
    forward_file(file)
    using directory = try TempDir.new(cap, "borrow")
    let forwarded_dir = dir_path(directory)
    let direct_dir = directory.path()
    if forwarded_dir.to_os().to_bytes().len() != direct_dir.to_os().to_bytes().len() { return Ok(2) }
    return Ok(0)
}

pub fn main() -> I32 {
    let cap = Blocking()
    match Path.parse("/tmp/alder-fs-probe.txt") {
        Ok(path) => {
            match probe(cap, path) {
                Ok(code) => { return code }
                Err(_) => { return 90 }
            }
        }
        Err(_) => { return 91 }
    }
    return 92
}
`
	resetFsProbeFile(t)
	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": source,
	}, "run")
	if run != (productionResult{}) {
		t.Fatalf("borrowed owner reads: %+v stderr=%s", run, run.stderr)
	}
	runSanitizedProject(t, cc, root, dir, "hello")
}

// TestFsBufReaderAffineSource pins take semantics for a generic constructor
// instantiated with an affine owner: BufReader takes the File, reads through
// it, and returns the source through into_source so exactly one File cleanup
// runs. The sanitizer rerun checks that no second close occurs.
func TestFsBufReaderAffineSource(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Parallel()
	}
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	source := `module hello.main

import std.fs { File }
import std.io { Blocking, BufReader, IoError, Reader }
import std.path { Path }

fn probe(cap: Blocking, path: Path) -> Result(I32, IoError) {
    let file: File(Blocking) = try File.open(cap, path)
    let reader = BufReader.with_capacity(2, file)
    var one: Array(U8, 1) = [0]
    var code: I32 = 0
    match reader.read(one.slice_mut(0, 1)) {
        Ok(n) => { if n != 1 || one[0] != 104 { code = 1 } }
        Err(_) => { code = 2 }
    }
    let source = reader.into_source()
    using kept = source
    return Ok(code)
}

pub fn main() -> I32 {
    let cap = Blocking()
    match Path.parse("/tmp/alder-fs-probe.txt") {
        Ok(path) => {
            match probe(cap, path) {
                Ok(code) => { return code }
                Err(_) => { return 90 }
            }
        }
        Err(_) => { return 91 }
    }
    return 92
}
`
	resetFsProbeFile(t)
	dir := t.TempDir()
	run := runProductionCompilerEnv(t, exe, dir, env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": source,
	}, "run")
	if run != (productionResult{}) {
		t.Fatalf("BufReader affine source: %+v stderr=%s", run, run.stderr)
	}
	runSanitizedProject(t, cc, root, dir, "hello")
}

func TestFsProductionFileAndValues(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

	resetFsProbeFile(t)
	fileRun := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": fsFileProgram,
	}, "run")
	if fileRun.status != 0 {
		t.Fatalf("fs file probe: %+v stderr=%s", fileRun, fileRun.stderr)
	}

	resetFsProbeFile(t)
	freeRun := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": fsFreeProgram,
	}, "run")
	if freeRun.status != 0 {
		t.Fatalf("fs free-function probe: %+v stderr=%s", freeRun, freeRun.stderr)
	}
	_ = os.Remove("/tmp/alder-fs-probe.txt")
	_ = os.Remove("/tmp/alder-fs-probe-moved.txt")
}
func TestFsProductionDirectoryWalk(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

	tree := "/tmp/alder-fs-tree"
	target := "/tmp/alder-fs-target.txt"
	_ = os.RemoveAll(tree)
	_ = os.Remove(target)
	if err := os.WriteFile(target, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(tree, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, data := range map[string]string{"a": "a", "b": "b", "c": "c"} {
		if err := os.WriteFile(filepath.Join(tree, name), []byte(data), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(tree, "sub", "d"), []byte("d"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(tree, "link")); err != nil {
		t.Fatal(err)
	}
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": fsDirectoryProgram,
	}, "run")
	if result.status != 0 {
		t.Fatalf("fs directory probe: %+v stderr=%s", result, result.stderr)
	}
	if _, err := os.Stat(tree); !os.IsNotExist(err) {
		t.Fatalf("remove_dir_all left %s: %v", tree, err)
	}
	if _, err := os.Stat(target); err != nil {
		t.Fatalf("remove_dir_all followed the symlink: %v", err)
	}
	_ = os.Remove(target)
}
func TestFsProductionTemporaryOwners(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, root)
	env := sysrootEnv(filepath.Join(root, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, env, map[string]string{
		"alder.toml":  manifest,
		"src/main.al": fsTempProgram,
	}, "run")
	if result.status != 0 {
		t.Fatalf("fs temp probe: %+v stderr=%s", result, result.stderr)
	}
}
