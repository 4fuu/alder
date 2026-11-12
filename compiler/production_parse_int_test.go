package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// core.num parse is exact decimal: signs are explicit, whitespace is not
// trimmed, boundaries are checked before the accumulation can overflow, and
// I64.min is represented without a positive overflow.
func TestProductionCoreNumParseRuns(t *testing.T) {
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

import core.num

pub fn main() -> I32 {
    match num.parse_u64("18446744073709551615") {
        Ok(value) => { if value != num.u64_max() { return 1 } }
        Err(_) => { return 2 }
    }
    match num.parse_u64("18446744073709551616") {
        Ok(_) => { return 3 }
        Err(_) => {}
    }
    match num.parse_i64("-9223372036854775808") {
        Ok(value) => { if value != num.i64_min() { return 4 } }
        Err(_) => { return 5 }
    }
    match num.parse_i64("9223372036854775807") {
        Ok(value) => { if value != num.i64_max() { return 6 } }
        Err(_) => { return 7 }
    }
    match num.parse_i64("9223372036854775808") {
        Ok(_) => { return 8 }
        Err(_) => {}
    }
    match num.parse_i64("+42") {
        Ok(value) => { if value != 42 { return 9 } }
        Err(_) => { return 10 }
    }
    match num.parse_i64("-0") {
        Ok(value) => { if value != 0 { return 11 } }
        Err(_) => { return 12 }
    }
    match num.parse_u64("00042") {
        Ok(value) => { if value != 42 { return 13 } }
        Err(_) => { return 14 }
    }
    match num.parse_u64("-1") {
        Ok(_) => { return 15 }
        Err(_) => {}
    }
    match num.parse_u64("+") {
        Ok(_) => { return 16 }
        Err(_) => {}
    }
    match num.parse_i64("-") {
        Ok(_) => { return 17 }
        Err(_) => {}
    }
    match num.parse_i64("") {
        Ok(_) => { return 18 }
        Err(_) => {}
    }
    match num.parse_i64("12x") {
        Ok(_) => { return 19 }
        Err(_) => {}
    }
    match num.parse_i64(" 12") {
        Ok(_) => { return 20 }
        Err(_) => {}
    }
    return 0
}
`,
	}
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, env, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("core.num parse behavior failed: %+v", result)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
