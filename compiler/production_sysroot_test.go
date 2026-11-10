package compiler

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// C1 installed sysroot: discovery, rooted-import resolution, plan identity,
// and deterministic rejections. Every case forces ALDER_SYSROOT explicitly so
// no assertion depends on the ambient environment, and one case proves the
// plan does not depend on how the sysroot was found.

// sysrootEnv strips ALDER_SYSROOT from the test process environment and
// re-adds it only when value is nonempty.
func sysrootEnv(value string) []string {
	env := make([]string, 0, len(os.Environ())+1)
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "ALDER_SYSROOT=") {
			continue
		}
		env = append(env, entry)
	}
	if value != "" {
		env = append(env, "ALDER_SYSROOT="+value)
	}
	return env
}

func runProductionCompilerEnv(t *testing.T, exe, dir string, env []string, files map[string]string, args ...string) productionResult {
	t.Helper()
	for name, text := range files {
		path := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	tmp := filepath.Join(dir, "tmp")
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		t.Fatal(err)
	}
	cmd.Env = append(env, "TMPDIR="+tmp)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("run production compiler: %v", err)
		}
		status = exit.ExitCode()
	}
	return productionResult{status: status, stdout: stdout.String(), stderr: stderr.String()}
}

// copySysrootTree copies the committed sysroot library sources into dst so a
// test can exercise the installed `<exe dir>/../lib/alder` discovery order.
func copySysrootTree(t *testing.T, repoRoot, dst string) {
	t.Helper()
	for _, root := range []string{"core", "std"} {
		entries, err := os.ReadDir(filepath.Join(repoRoot, "sysroot", root))
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Join(dst, root), 0o755); err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			text, err := os.ReadFile(filepath.Join(repoRoot, "sysroot", root, entry.Name()))
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dst, root, entry.Name()), text, 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func sysrootOptionMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import core.option

pub fn main() -> I32 {
    let value: Option(U64) = Some(3)
    if option.is_none(value) { return 1 }
    let empty: Option(U64) = None
    if !option.is_none(empty) { return 2 }
    if !option.is_some(value) { return 3 }
    return 0
}
`,
	}
}

func sysrootPathEnvMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.env { EnvError, PlatformInfo, Target, TargetArch, TargetOs }
import std.path { OsString, Path }

pub fn main() -> I32 {
    let first = check_os_parse()
    if first != 0 { return first }
    let second = check_os_reject()
    if second != 0 { return second }
    let third = check_os_from_bytes()
    if third != 0 { return third }
    let fourth = check_os_non_text()
    if fourth != 0 { return fourth }
    let fifth = check_path_queries()
    if fifth != 0 { return fifth }
    let sixth = check_path_join()
    if sixth != 0 { return sixth }
    let seventh = check_path_normalize()
    if seventh != 0 { return seventh }
    let eighth = check_path_names()
    if eighth != 0 { return eighth }
    let ninth = check_path_parent()
    if ninth != 0 { return ninth }
    let tenth = check_env_types()
    if tenth != 0 { return tenth }
    return 0
}

fn text_same(left: String, right: String) -> Bool {
    if left.len() != right.len() { return false }
    var at: U64 = 0
    while at < left.len() {
        if left.byte(at) != right.byte(at) { return false }
        at = at + 1
    }
    return true
}

fn host_text_is(left: Option(OsString), right: String) -> Bool {
    var same: Bool = false
    match left {
        Some(host) => {
            match host.to_string() {
                Some(text) => { same = text_same(text, right) }
                None => {}
            }
        }
        None => {}
    }
    return same
}

fn path_text_is(left: Option(Path), right: String) -> Bool {
    var same: Bool = false
    match left {
        Some(value) => {
            let host = value.to_os()
            match host.to_string() {
                Some(text) => { same = text_same(text, right) }
                None => {}
            }
        }
        None => {}
    }
    return same
}

fn check_os_parse() -> I32 {
    var code: I32 = 0
    match OsString.parse("hello") {
        Ok(value) => {
            if !host_text_is(Some(value), "hello") { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    return code
}

fn check_os_reject() -> I32 {
    var code: I32 = 0
    match OsString.parse("bad\0name") {
        Ok(_) => { code = 1 }
        Err(_) => {}
    }
    match Path.parse("bad\0name") {
        Ok(_) => { code = 2 }
        Err(_) => {}
    }
    return code
}

fn check_os_from_bytes() -> I32 {
    var code: I32 = 0
    let raw = "ready"
    match OsString.from_bytes(raw.to_bytes()) {
        Ok(value) => {
            if !host_text_is(Some(value), "ready") { code = 1 }
            let again = raw.to_bytes()
            match OsString.from_bytes(again) {
                Ok(twin) => {
                    let one = value.to_string()
                    let two = twin.to_string()
                    var equal: Bool = false
                    match one {
                        Some(first) => {
                            match two {
                                Some(second) => { equal = text_same(first, second) }
                                None => {}
                            }
                        }
                        None => {}
                    }
                    if !equal { code = 2 }
                }
                Err(_) => { code = 3 }
            }
        }
        Err(_) => { code = 4 }
    }
    return code
}

fn check_os_non_text() -> I32 {
    var code: I32 = 0
    let raw: Bytes = "\xff\xfe"
    match OsString.from_bytes(raw) {
        Ok(value) => {
            match value.to_string() {
                Some(_) => { code = 1 }
                None => {}
            }
        }
        Err(_) => { code = 2 }
    }
    return code
}

fn check_path_queries() -> I32 {
    var code: I32 = 0
    match Path.parse("/usr/local/app.conf") {
        Ok(entry) => {
            let parts = entry.components()
            if parts.len() != 4 { code = 1 }
            if code == 0 {
                match parts[0] {
                    RootDir => {}
                    CurDir => { code = 2 }
                    ParentDir => { code = 2 }
                    Normal(_) => { code = 2 }
                }
            }
            if code == 0 {
                match parts[1] {
                    Normal(name) => {
                        if !host_text_is(Some(name), "usr") { code = 3 }
                    }
                    RootDir => { code = 3 }
                    CurDir => { code = 3 }
                    ParentDir => { code = 3 }
                }
            }
            if code == 0 {
                if !host_text_is(entry.file_name(), "app.conf") { code = 4 }
            }
            if code == 0 {
                if !host_text_is(entry.file_stem(), "app") { code = 5 }
            }
            if code == 0 {
                if !host_text_is(entry.extension(), "conf") { code = 6 }
            }
            if code == 0 {
                if !path_text_is(entry.parent(), "/usr/local") { code = 7 }
            }
            if code == 0 {
                if !entry.is_absolute() { code = 8 }
            }
        }
        Err(_) => { code = 9 }
    }
    return code
}

fn check_path_join() -> I32 {
    var code: I32 = 0
    match Path.parse("a/b/./c") {
        Ok(base) => {
            match Path.parse("d/../../e") {
                Ok(suffix) => {
                    let joined = base.join(suffix)
                    let norm = joined.normalize()
                    if !path_text_is(Some(norm), "a/b/e") { code = 1 }
                }
                Err(_) => { code = 2 }
            }
            if code == 0 {
                match Path.parse("/absolute") {
                    Ok(absolute) => {
                        let replaced = base.join(absolute)
                        if !path_text_is(Some(replaced), "/absolute") { code = 3 }
                    }
                    Err(_) => { code = 4 }
                }
            }
        }
        Err(_) => { code = 5 }
    }
    if code == 0 {
        match Path.parse("") {
            Ok(empty) => {
                match Path.parse("b") {
                    Ok(other) => {
                        let grown = empty.join(other)
                        if !path_text_is(Some(grown), "b") { code = 6 }
                        let kept = other.join(empty)
                        if !path_text_is(Some(kept), "b") { code = 7 }
                    }
                    Err(_) => { code = 8 }
                }
            }
            Err(_) => { code = 9 }
        }
    }
    return code
}

fn check_path_normalize() -> I32 {
    var code: I32 = 0
    match Path.parse("a/../../..") {
        Ok(base) => {
            let up = base.normalize()
            if !path_text_is(Some(up), "../..") { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    if code == 0 {
        match Path.parse("/a/../../b") {
            Ok(deep) => {
                let norm = deep.normalize()
                if !path_text_is(Some(norm), "/../b") { code = 3 }
            }
            Err(_) => { code = 4 }
        }
    }
    if code == 0 {
        match Path.parse(".") {
            Ok(dot) => {
                let plain = dot.normalize()
                if !path_text_is(Some(plain), "") { code = 5 }
            }
            Err(_) => { code = 6 }
        }
    }
    if code == 0 {
        match Path.parse("/..") {
            Ok(over) => {
                let kept = over.normalize()
                if !path_text_is(Some(kept), "/..") { code = 7 }
            }
            Err(_) => { code = 8 }
        }
    }
    if code == 0 {
        match Path.parse("a/./b/..") {
            Ok(mixed) => {
                let clean = mixed.normalize()
                if !path_text_is(Some(clean), "a") { code = 9 }
            }
            Err(_) => { code = 10 }
        }
    }
    if code == 0 {
        match Path.parse("") {
            Ok(empty) => {
                let flat = empty.normalize()
                if !path_text_is(Some(flat), "") { code = 11 }
                if empty.is_absolute() { code = 12 }
            }
            Err(_) => { code = 13 }
        }
    }
    if code == 0 {
        match Path.parse("/") {
            Ok(root) => {
                let same = root.normalize()
                if !path_text_is(Some(same), "/") { code = 14 }
                if !root.is_absolute() { code = 15 }
            }
            Err(_) => { code = 16 }
        }
    }
    return code
}

fn check_path_names() -> I32 {
    var code: I32 = 0
    match Path.parse("a/b/") {
        Ok(slash) => {
            if !host_text_is(slash.file_name(), "b") { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    if code == 0 {
        match Path.parse("a/.") {
            Ok(dot_end) => {
                var absent: Bool = true
                match dot_end.file_name() {
                    Some(_) => { absent = false }
                    None => {}
                }
                if !absent { code = 3 }
            }
            Err(_) => { code = 4 }
        }
    }
    if code == 0 {
        match Path.parse("a/..") {
            Ok(up_end) => {
                var absent: Bool = true
                match up_end.file_name() {
                    Some(_) => { absent = false }
                    None => {}
                }
                if !absent { code = 5 }
            }
            Err(_) => { code = 6 }
        }
    }
    if code == 0 {
        match Path.parse("foo.tar.gz") {
            Ok(archive) => {
                if !host_text_is(archive.file_stem(), "foo.tar") { code = 7 }
                if !host_text_is(archive.extension(), "gz") { code = 8 }
            }
            Err(_) => { code = 9 }
        }
    }
    if code == 0 {
        match Path.parse(".gitignore") {
            Ok(dotfile) => {
                if !host_text_is(dotfile.file_stem(), ".gitignore") { code = 10 }
                var none: Bool = true
                match dotfile.extension() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 11 }
            }
            Err(_) => { code = 12 }
        }
    }
    if code == 0 {
        match Path.parse(".foo.tar.gz") {
            Ok(hidden) => {
                if !host_text_is(hidden.file_stem(), ".foo.tar") { code = 13 }
                if !host_text_is(hidden.extension(), "gz") { code = 14 }
            }
            Err(_) => { code = 15 }
        }
    }
    if code == 0 {
        match Path.parse("a.") {
            Ok(trailing) => {
                var empty: Bool = false
                match trailing.extension() {
                    Some(ext) => {
                        match ext.to_string() {
                            Some(text) => {
                                if text.len() == 0 { empty = true }
                            }
                            None => {}
                        }
                    }
                    None => { code = 16 }
                }
                if !empty { code = 17 }
            }
            Err(_) => { code = 18 }
        }
    }
    if code == 0 {
        match Path.parse("foo") {
            Ok(plain) => {
                var none: Bool = true
                match plain.extension() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 19 }
            }
            Err(_) => { code = 20 }
        }
    }
    return code
}

fn check_path_parent() -> I32 {
    var code: I32 = 0
    match Path.parse("foo") {
        Ok(plain) => {
            let up = plain.parent()
            var found: Bool = false
            match up {
                Some(remainder) => {
                    let host = remainder.to_os()
                    match host.to_string() {
                        Some(text) => {
                            if text.len() == 0 { found = true }
                        }
                        None => {}
                    }
                }
                None => {}
            }
            if !found { code = 1 }
        }
        Err(_) => { code = 2 }
    }
    if code == 0 {
        match Path.parse("/") {
            Ok(root) => {
                var none: Bool = true
                match root.parent() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 3 }
            }
            Err(_) => { code = 4 }
        }
    }
    if code == 0 {
        match Path.parse("") {
            Ok(empty) => {
                var none: Bool = true
                match empty.parent() {
                    Some(_) => { none = false }
                    None => {}
                }
                if !none { code = 5 }
            }
            Err(_) => { code = 6 }
        }
    }
    if code == 0 {
        match Path.parse("a/.") {
            Ok(dot_end) => {
                if !path_text_is(dot_end.parent(), "a") { code = 7 }
            }
            Err(_) => { code = 8 }
        }
    }
    if code == 0 {
        match Path.parse("a/..") {
            Ok(up_end) => {
                if !path_text_is(up_end.parent(), "a") { code = 9 }
            }
            Err(_) => { code = 10 }
        }
    }
    return code
}

fn check_env_types() -> I32 {
    var code: I32 = 0
    let info: PlatformInfo = PlatformInfo(code: 2, message: "no entry")
    if info.code != 2 { code = 1 }
    if info.message.len() != 8 { code = 2 }
    if code == 0 {
        let failure: EnvError = Platform(info)
        match failure {
            Platform(carried) => {
                if carried.code != 2 { code = 3 }
                if !text_same(carried.message, "no entry") { code = 4 }
            }
            InvalidEncoding => { code = 5 }
            InvalidName => { code = 5 }
            Unsupported => { code = 5 }
        }
    }
    if code == 0 {
        let target: Target = Target(os: Linux, arch: X64)
        match target.os {
            Linux => {}
            MacOS => { code = 6 }
            Windows => { code = 6 }
        }
        match target.arch {
            X64 => {}
            AArch64 => { code = 7 }
        }
    }
    return code
}
`,
	}
}

func sysrootEnvMain() map[string]string {
	return map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.env { EnvError, PlatformInfo, Target, TargetArch, TargetOs }

pub fn main() -> I32 {
    return check_env_types()
}

fn text_same(left: String, right: String) -> Bool {
    if left.len() != right.len() { return false }
    var at: U64 = 0
    while at < left.len() {
        if left.byte(at) != right.byte(at) { return false }
        at = at + 1
    }
    return true
}

fn check_env_types() -> I32 {
    var code: I32 = 0
    let info: PlatformInfo = PlatformInfo(code: 2, message: "no entry")
    if info.code != 2 { code = 1 }
    if info.message.len() != 8 { code = 2 }
    if code == 0 {
        let failure: EnvError = Platform(info)
        match failure {
            Platform(carried) => {
                if carried.code != 2 { code = 3 }
                if !text_same(carried.message, "no entry") { code = 4 }
            }
            InvalidEncoding => { code = 5 }
            InvalidName => { code = 5 }
            Unsupported => { code = 5 }
        }
    }
    if code == 0 {
        let target: Target = Target(os: Linux, arch: X64)
        match target.os {
            Linux => {}
            MacOS => { code = 6 }
            Windows => { code = 6 }
        }
        match target.arch {
            X64 => {}
            AArch64 => { code = 7 }
        }
    }
    return code
}
`,
	}
}

func sysrootSeedLength(t *testing.T, repoRoot string) string {
	t.Helper()
	info, err := os.Stat(filepath.Join(repoRoot, "sysroot", "core", "option.al"))
	if err != nil {
		t.Fatal(err)
	}
	return strconv.FormatUint(uint64(info.Size()), 10)
}

func TestProductionSysrootCoreResolves(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "test-plan")
	seedBytes := sysrootSeedLength(t, repoRoot)
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("sysroot plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") || strings.Contains(plan.stdout, "compiler-coupled-v1") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source core/option.al bytes "+seedBytes+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module core.option\n") {
		t.Fatalf("plan does not list the sysroot source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> core.option\n") {
		t.Fatalf("plan does not record the sysroot edge: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("sysroot plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootOptionMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("sysroot project run failed: %+v", run)
	}
}

func TestProductionSysrootPathEnvRuns(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootPathEnvMain(), "test-plan")
	pathSeed := sysrootModuleSeed(t, repoRoot, "path.al")
	envSeed := sysrootModuleSeed(t, repoRoot, "env.al")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.path/std.env plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/path.al bytes "+pathSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.path\n") {
		t.Fatalf("plan does not list the std.path source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/env.al bytes "+envSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.env\n") {
		t.Fatalf("plan does not list the std.env source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> std.path\n") ||
		!strings.Contains(plan.stdout, "edge hello.main -> std.env\n") {
		t.Fatalf("plan does not record the std edges: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootPathEnvMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("std.path/std.env plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootPathEnvMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.path/std.env behavior run failed: %+v", run)
	}
}

func TestProductionSysrootEnvRuns(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))

	plan := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootEnvMain(), "test-plan")
	envSeed := sysrootModuleSeed(t, repoRoot, "env.al")
	if plan.status != 0 || plan.stderr != "" {
		t.Fatalf("std.env plan failed: %+v", plan)
	}
	if !strings.Contains(plan.stdout, "\nsysroot v1:") {
		t.Fatalf("plan lost the sysroot identity line: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "source std/env.al bytes "+envSeed+" poly64-v1:") ||
		!strings.Contains(plan.stdout, " module std.env\n") {
		t.Fatalf("plan does not list the std.env source: %q", plan.stdout)
	}
	if !strings.Contains(plan.stdout, "edge hello.main -> std.env\n") {
		t.Fatalf("plan does not record the std.env edge: %q", plan.stdout)
	}
	repeat := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootEnvMain(), "test-plan")
	if repeat != plan {
		t.Fatalf("std.env plan changed across processes: first=%q repeat=%q", plan.stdout, repeat.stdout)
	}

	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, sysrootEnvMain(), "run")
	if run != (productionResult{}) {
		t.Fatalf("std.env behavior run failed: %+v", run)
	}
}

func sysrootModuleSeed(t *testing.T, repoRoot, name string) string {
	t.Helper()
	info, err := os.Stat(filepath.Join(repoRoot, "sysroot", "std", name))
	if err != nil {
		t.Fatal(err)
	}
	return strconv.FormatUint(uint64(info.Size()), 10)
}

func TestProductionSysrootPlanStableAcrossDiscovery(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)

	envRoot := t.TempDir()
	viaEnv := runProductionCompilerEnv(t, exe, envRoot, sysrootEnv(filepath.Join(repoRoot, "sysroot")), sysrootOptionMain(), "test-plan")
	if viaEnv.status != 0 || viaEnv.stderr != "" {
		t.Fatalf("ALDER_SYSROOT discovery plan failed: %+v", viaEnv)
	}

	// The same sysroot content found through <exe dir>/../lib/alder with no
	// ALDER_SYSROOT must produce a byte-identical plan.
	layout := t.TempDir()
	if err := os.MkdirAll(filepath.Join(layout, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	copySysrootTree(t, repoRoot, filepath.Join(layout, "lib", "alder"))
	copied := filepath.Join(layout, "bin", "alder-driver")
	text, err := os.ReadFile(exe)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(copied, text, 0o755); err != nil {
		t.Fatal(err)
	}
	viaLayout := runProductionCompilerEnv(t, copied, t.TempDir(), sysrootEnv(""), sysrootOptionMain(), "test-plan")
	if viaLayout != viaEnv {
		t.Fatalf("plan depends on sysroot discovery order: env=%q layout=%q", viaEnv.stdout, viaLayout.stdout)
	}
}

func TestProductionSysrootUnavailable(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(""), sysrootOptionMain(), "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "no installed Alder sysroot is available") {
		t.Fatalf("missing sysroot rejection: %+v", result)
	}
}

func TestProductionSysrootMissingModule(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	files["src/main.al"] = strings.Replace(files["src/main.al"], "import core.option", "import core.missing", 1)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "a required sysroot module is unavailable") {
		t.Fatalf("missing sysroot module rejection: %+v", result)
	}
}

func TestProductionSysrootStdResolves(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	// A fixture sysroot proves the `std` root resolves through the same
	// machinery before the first hosted std module lands.
	fixture := t.TempDir()
	if err := os.MkdirAll(filepath.Join(fixture, "std"), 0o755); err != nil {
		t.Fatal(err)
	}
	echo := "module std.echo\n\n/// Echoes one fixed byte.\npub fn first_byte() -> U8 {\n    return 7\n}\n"
	if err := os.WriteFile(filepath.Join(fixture, "std", "echo.al"), []byte(echo), 0o644); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.echo

pub fn main() -> I32 {
    if echo.first_byte() != 7 { return 1 }
    return 0
}
`,
	}
	run := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(fixture), files, "run")
	if run != (productionResult{}) {
		t.Fatalf("std fixture project run failed: %+v", run)
	}
}

func TestProductionSysrootCannotShadow(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	// Both decoys must be ignored: a project-local sysroot tree and a
	// project source at the sysroot path.
	files["sysroot/core/option.al"] = "module core.option\npub fn is_none(T: type, value: Option(T)) -> Bool {\n    return true\n}\n"
	files["src/core/option.al"] = "module hello.core.option\npub fn decoy() -> I32 { return 0 }\n"
	dir := t.TempDir()
	plan := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "test-plan")
	seedBytes := sysrootSeedLength(t, repoRoot)
	if plan.status != 0 || !strings.Contains(plan.stdout, "source core/option.al bytes "+seedBytes+" poly64-v1:") {
		t.Fatalf("project tree shadowed the sysroot: %+v", plan)
	}
	run := runProductionCompilerEnv(t, exe, dir, sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "run")
	if run != (productionResult{}) {
		t.Fatalf("shadowed project run failed: %+v", run)
	}
}

func TestProductionSysrootReservedPackageName(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	files := sysrootOptionMain()
	files["alder.toml"] = strings.Replace(files["alder.toml"], "name = \"hello\"", "name = \"core\"", 1)
	result := runProductionCompilerEnv(t, exe, t.TempDir(), sysrootEnv(filepath.Join(repoRoot, "sysroot")), files, "check")
	if result.status != 2 || result.stdout != "" || !strings.Contains(result.stderr, "the package name core or std is reserved") {
		t.Fatalf("reserved package name rejection: %+v", result)
	}
}

// The qualified-call sequence programs pin that imported generic calls
// compose across let, var, and argument position under every import
// spelling. Before the qualified-name fix, a follow-up qualified call after
// a let-position generic call could be misdiagnosed through receiver
// dispatch, so these programs guard resolution state across a whole body.
func sysrootSequenceProjects() map[string]map[string]string {
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	qualified := `module hello.main

import core.option
import core.result

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let held: Option(I64) = Some(5)
    let bad: Result(I64, String) = Err("rejected")
    let good: Result(I64, String) = Ok(30)
    let projected = result.ok(I64, String, good)
    let error_side = result.err(I64, String, bad)
    var total: I64 = option.unwrap_or(I64, projected, 0)
    total = total + option.unwrap_or(I64, option.map(I64, I64, held, double), 0)
    if result.is_err(bad) { total = total + 1 }
    if option.is_none(error_side) { total = total + 2 }
    if option.is_some(option.and_then(I64, I64, held, half)) { total = total + 4 }
    if option.is_none(empty) { total = total + 8 }
    if total == 53 { return 0 }
    return 1
}

fn double(v: I64) -> I64 { return v * 2 }

fn half(v: I64) -> Option(I64) {
    return Some(v / 2)
}
`
	aliased := `module hello.main

import core.option as opt
import core.result as res

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let held: Option(I64) = Some(5)
    let bad: Result(I64, String) = Err("rejected")
    let good: Result(I64, String) = Ok(30)
    let projected = res.ok(I64, String, good)
    let error_side = res.err(I64, String, bad)
    var total: I64 = opt.unwrap_or(I64, projected, 0)
    total = total + opt.unwrap_or(I64, opt.map(I64, I64, held, double), 0)
    if res.is_err(bad) { total = total + 1 }
    if opt.is_none(error_side) { total = total + 2 }
    if opt.is_some(opt.and_then(I64, I64, held, half)) { total = total + 4 }
    if opt.is_none(empty) { total = total + 8 }
    if total == 53 { return 0 }
    return 1
}

fn double(v: I64) -> I64 { return v * 2 }

fn half(v: I64) -> Option(I64) {
    return Some(v / 2)
}
`
	braced := `module hello.main

import core.option { is_none, is_some, map, and_then, unwrap_or }
import core.result { is_err, ok, err }

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let held: Option(I64) = Some(5)
    let bad: Result(I64, String) = Err("rejected")
    let good: Result(I64, String) = Ok(30)
    let projected = ok(I64, String, good)
    let error_side = err(I64, String, bad)
    var total: I64 = unwrap_or(I64, projected, 0)
    total = total + unwrap_or(I64, map(I64, I64, held, double), 0)
    if is_err(bad) { total = total + 1 }
    if is_none(error_side) { total = total + 2 }
    if is_some(and_then(I64, I64, held, half)) { total = total + 4 }
    if is_none(empty) { total = total + 8 }
    if total == 53 { return 0 }
    return 1
}

fn double(v: I64) -> I64 { return v * 2 }

fn half(v: I64) -> Option(I64) {
    return Some(v / 2)
}
`
	files := func(mainText string) map[string]string {
		return map[string]string{"alder.toml": manifest, "src/main.al": mainText}
	}
	return map[string]map[string]string{
		"qualified": files(qualified),
		"aliased":   files(aliased),
		"braced":    files(braced),
	}
}

func TestProductionSysrootImportedCallsCompose(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))
	// Expected checksum: 30 (projected) + 10 (doubled) + 1 (bad is_err)
	// (error_side is Some so is_none adds 0) + 4 (and_then is_some)
	// + 8 (empty is_none).
	for name, files := range sysrootSequenceProjects() {
		run := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
		if run != (productionResult{}) {
			t.Fatalf("%s sequence run failed: %+v", name, run)
		}
	}
}

// The core.num snapshot runtime test pins the limits and the explicit
// overflow-mode absolute value against the installed sysroot, including the
// minimum-boundary None of the checked form and the wrapping identity at
// every width.
func TestProductionSysrootNumHelpers(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"
	main := `module hello.main

import core.num

pub fn main() -> I32 {
    var total: I64 = 0
    if num.i32_max() == 2147483647 { total = total + 1 }
    if num.u32_max() == 4294967295 { total = total + 2 }
    match num.i64_abs_checked(num.i64_min()) {
        None => { total = total + 4 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    match num.i32_abs_checked(num.i32_min()) {
        None => { total = total + 8 }
        Some(v) => {
            if v == 0 { total = total + 0 }
        }
    }
    if num.i64_abs_wrapping(num.i64_min()) == num.i64_min() { total = total + 16 }
    match num.i64_abs_checked(-42) {
        Some(v) => {
            if v == 42 { total = total + 32 }
        }
        None => { total = total + 0 }
    }
    if total == 63 { return 0 }
    return 1
}
`
	files := map[string]string{"alder.toml": manifest, "src/main.al": main}
	run := runProductionCompilerEnv(t, exe, t.TempDir(), env, files, "run")
	if run != (productionResult{}) {
		t.Fatalf("core.num helpers run failed: %+v", run)
	}
}

func TestProductionSysrootQualifiedNameDiagnostics(t *testing.T) {
	cc, err := exec.LookPath("gcc")
	if err != nil {
		t.Skip("gcc not available")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	_, exe, _ := getSharedProductionBuild(t, cc, repoRoot)
	env := sysrootEnv(filepath.Join(repoRoot, "sysroot"))
	manifest := "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n"

	// A typo'd member under a real sysroot namespace is reported against the
	// full dotted name at its qualified span, never as the bare qualifier.
	typo := `module hello.main

import core.option

pub fn main() -> I32 {
    let empty: Option(I64) = None
    return option.typo(empty)
}
`
	result := runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": typo}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, `unknown name "option.typo"`) {
		t.Fatalf("typo member rejection: %+v", result)
	}

	// A qualifier the program never imports under is the same dotted-name
	// miss, not a receiver dispatch on the unknown word.
	wrongQualifier := `module hello.main

import core.option as opt

pub fn main() -> I32 {
    let empty: Option(I64) = None
    return opt.unwrap_or(I64, option.map(I64, I64, empty, double), 0)
}

fn double(v: I64) -> I64 { return v * 2 }
`
	result = runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": wrongQualifier}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, `unknown name "option.map"`) {
		t.Fatalf("wrong qualifier rejection: %+v", result)
	}

	// The same rule holds for the result namespace.
	resultTypo := `module hello.main

import core.result

pub fn main() -> I32 {
    let good: Result(I64, String) = Ok(30)
    return result.typo(I64, String, good)
}
`
	result = runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": resultTypo}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, `unknown name "result.typo"`) {
		t.Fatalf("result typo rejection: %+v", result)
	}

	// A dotted callee that resolves but fails to type check keeps the type
	// diagnostic; the old defect turned this shape into an unknown-name
	// report against the qualifier.
	mismatch := `module hello.main

import core.option

pub fn main() -> I32 {
    let empty: Option(I64) = None
    let verdict = option.ok_or(I64, I64, empty, 9)
    if option.is_some(verdict) { return 1 }
    return 0
}
`
	result = runProductionCompilerEnv(t, exe, t.TempDir(), env, map[string]string{"alder.toml": manifest, "src/main.al": mismatch}, "check")
	if result.status != 1 || result.stdout != "" || !strings.Contains(result.stderr, "semantic error") || strings.Contains(result.stderr, `unknown name "option`) {
		t.Fatalf("type mismatch diagnostic: %+v", result)
	}
}
