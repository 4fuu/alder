package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// std.env v1 reads the hosted argument vector, updates the process
// environment, resolves the working directory and executable, and reports
// compile-time target information. The test passes two run arguments so the
// entry bridge is exercised end to end; the key is set before it is read and
// removed before the absence check, so no ambient environment value is used.
func TestProductionStdEnvRuns(t *testing.T) {
	t.Parallel()
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
	files := map[string]string{
		"alder.toml": "manifest = 1\nedition = \"1\"\n[package]\nname = \"hello\"\nversion = \"0.1.0\"\n[targets.hello]\nkind = \"bin\"\nroot = \"src/main.al\"\n",
		"src/main.al": `module hello.main

import std.env
import std.path { OsString }

fn set_named(key: String, value: String) -> I32 {
    match OsString.parse(key) {
        Ok(name) => {
            match OsString.parse(value) {
                Ok(text) => {
                    match env.set_var(name, text) {
                        Ok(_) => { return 0 }
                        Err(_) => { return 1 }
                    }
                }
                Err(_) => { return 2 }
            }
        }
        Err(_) => { return 3 }
    }
    return 99
}

fn get_named(key: String) -> I32 {
    match OsString.parse(key) {
        Ok(name) => {
            match env.get(name) {
                Some(value) => {
                    match value.to_string() {
                        Some(text) => {
                            if text == "expected" { return 0 }
                            return 1
                        }
                        None => { return 2 }
                    }
                }
                None => { return 3 }
            }
        }
        Err(_) => { return 4 }
    }
    return 99
}

fn absent_named(key: String) -> I32 {
    match OsString.parse(key) {
        Ok(name) => {
            match env.get(name) {
                Some(_) => { return 1 }
                None => { return 0 }
            }
        }
        Err(_) => { return 2 }
    }
    return 99
}

fn remove_named(key: String) -> I32 {
    match OsString.parse(key) {
        Ok(name) => {
            match env.remove_var(name) {
                Ok(_) => { return 0 }
                Err(_) => { return 1 }
            }
        }
        Err(_) => { return 2 }
    }
    return 99
}

pub fn main() -> I32 {
    let args = env.arguments()
    if args.len() > 0 {
        if args.len() != 3 { return 1 }
        let first = args[1]
        match first.to_string() {
            Some(text) => { if text != "alpha" { return 2 } }
            None => { return 3 }
        }
        let second = args[2]
        match second.to_string() {
            Some(text) => { if text != "beta" { return 4 } }
            None => { return 5 }
        }
    }
    let set_code = set_named("ALDER_M8_ENV", "expected")
    if set_code != 0 { return set_code }
    let get_code = get_named("ALDER_M8_ENV")
    if get_code != 0 { return get_code }
    let invalid = set_named("A=B", "value")
    if invalid != 1 { return 6 }
    match env.current_dir() {
        Ok(path) => { if path.to_os().len() == 0 { return 7 } }
        Err(_) => { return 8 }
    }
    match env.current_exe() {
        Ok(path) => { if path.to_os().len() == 0 { return 9 } }
        Err(_) => { return 10 }
    }
    let remove_code = remove_named("ALDER_M8_ENV")
    if remove_code != 0 { return remove_code }
    let absent_code = absent_named("ALDER_M8_ENV")
    if absent_code != 0 { return absent_code }
    let info = env.target()
    match info.os {
        Linux => {}
        MacOS => {}
        Windows => {}
    }
    match info.arch {
        X64 => {}
        AArch64 => {}
    }
    return 0
}
`,
	}
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, env, files, "run", "--", "alpha", "beta")
	if result != (productionResult{}) {
		t.Fatalf("std.env behavior failed: %+v", result)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
