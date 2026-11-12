package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// core.format is pure Alder: specs, scalar-width padding, and integer
// rendering. The program exercises decimal signs and widths, alternate bases,
// Unicode scalar padding, I64 min, and rejected specs, then repeats under
// ASan/UBSan.
func TestProductionCoreFormatRuns(t *testing.T) {
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

import core.format
import core.num

pub fn main() -> I32 {
    let plain = format.FormatSpec.plain()
    match format.format_i64(-42, plain) {
        Ok(text) => { if text != "-42" { return 1 } }
        Err(_) => { return 2 }
    }
    var hex = format.FormatSpec.plain()
    hex.kind = format.FormatKind.HexLower
    hex.alternate = true
    match format.format_u64(255, hex) {
        Ok(text) => { if text != "0xff" { return 3 } }
        Err(_) => { return 4 }
    }
    var octal = format.FormatSpec.plain()
    octal.kind = format.FormatKind.Octal
    octal.alternate = true
    match format.format_u64(8, octal) {
        Ok(text) => { if text != "0o10" { return 5 } }
        Err(_) => { return 6 }
    }
    var plus = format.FormatSpec.plain()
    plus.width = 5
    plus.zero_pad = true
    plus.sign = format.Sign.Plus
    match format.format_i64(42, plus) {
        Ok(text) => { if text != "+0042" { return 7 } }
        Err(_) => { return 8 }
    }
    var centered = format.FormatSpec.plain()
    centered.width = 3
    centered.fill = 46
    centered.align = format.Align.Center
    match format.pad("é", centered) {
        Ok(text) => { if text != ".é." { return 9 } }
        Err(_) => { return 10 }
    }
    var bad = format.FormatSpec.plain()
    bad.fill = 0
    match format.pad("x", bad) {
        Ok(_) => { return 11 }
        Err(_) => {}
    }
    var precise = format.FormatSpec.plain()
    precise.precision = Some(2)
    match format.format_u64(10, precise) {
        Ok(_) => { return 12 }
        Err(_) => {}
    }
    var unsupported = format.FormatSpec.plain()
    unsupported.kind = format.FormatKind.General
    match format.format_u64(10, unsupported) {
        Ok(_) => { return 13 }
        Err(_) => {}
    }
    match format.format_i64(num.i64_min(), plain) {
        Ok(text) => { if text != "-9223372036854775808" { return 14 } }
        Err(_) => { return 15 }
    }
    return 0
}
`,
	}
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, env, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("core.format behavior failed: %+v", result)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
