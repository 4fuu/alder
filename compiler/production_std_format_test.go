package compiler

import (
	"os/exec"
	"path/filepath"
	"testing"
)

// std.format composes core.format's integer/text rules with a
// StringBuilder and the shortest-round-trip float shim. The program pins
// general, fixed, scientific, sign, zero-padding, NaN/inf, -0, f32, deferred
// error, and Display composition, then reruns under ASan/UBSan. It attempts a
// comma-decimal locale before formatting; when the host lacks that locale the
// process stays in C and the same assertions still run.
func TestProductionStdFormatRuns(t *testing.T) {
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

import core.format as core_format
import std.format as fmt

import c "locale.h" as cloc {
    raw fn setlocale = "setlocale"(category: c.Int, locale: c.ConstPtr(c.Char)) -> c.Ptr(c.Char)
}

pub fn main() -> I32 {
    using locale_name = c.CString("de_DE.UTF-8")
    let category_one: I32 = 1
    let numeric = category_one.to_c_int()
    let ignored = unsafe c { cloc.setlocale(numeric, locale_name.ptr()) }

    let plain = core_format.FormatSpec.plain()
    var f = fmt.Formatter.new()
    f.text("value=")
    f.i64(-42, plain)
    f.text(" ")
    f.f64(0.1, plain)
    f.text(" ")
    f.f32(0.5, plain)
    f.display(7, plain)
    match f.finish() {
        Ok(text) => { if text != "value=-42 0.1 0.57" { return 1 } }
        Err(_) => { return 2 }
    }

    let third: F64 = 1.0 / 3.0
    var f2 = fmt.Formatter.new()
    f2.f64(third, plain)
    match f2.finish() {
        Ok(text) => { if text != "0.3333333333333333" { return 3 } }
        Err(_) => { return 4 }
    }

    var f3 = fmt.Formatter.new()
    f3.f64(1e-300, plain)
    f3.text(" ")
    f3.f64(-0.0, plain)
    match f3.finish() {
        Ok(text) => { if text != "1e-300 -0" { return 5 } }
        Err(_) => { return 6 }
    }

    var fixed = core_format.FormatSpec.plain()
    fixed.kind = core_format.FormatKind.Fixed
    fixed.precision = Some(2)
    var f4 = fmt.Formatter.new()
    f4.f64(1.5, fixed)
    match f4.finish() {
        Ok(text) => { if text != "1.50" { return 7 } }
        Err(_) => { return 8 }
    }

    var scientific = core_format.FormatSpec.plain()
    scientific.kind = core_format.FormatKind.Scientific
    scientific.precision = Some(2)
    var f5 = fmt.Formatter.new()
    f5.f64(1.5, scientific)
    match f5.finish() {
        Ok(text) => { if text != "1.50e+00" { return 9 } }
        Err(_) => { return 10 }
    }

    let zero: F64 = 0.0
    let one: F64 = 1.0
    var f6 = fmt.Formatter.new()
    f6.f64(one / zero, plain)
    f6.text(" ")
    f6.f64(zero / zero, plain)
    match f6.finish() {
        Ok(text) => { if text != "inf nan" { return 11 } }
        Err(_) => { return 12 }
    }

    var plus = core_format.FormatSpec.plain()
    plus.width = 6
    plus.zero_pad = true
    plus.sign = core_format.Sign.Plus
    var f7 = fmt.Formatter.new()
    f7.f64(1.5, plus)
    match f7.finish() {
        Ok(text) => { if text != "+001.5" { return 13 } }
        Err(_) => { return 14 }
    }

    var bad = core_format.FormatSpec.plain()
    bad.fill = 0
    var f8 = fmt.Formatter.new()
    f8.display(7, bad)
    f8.text("still")
    match f8.finish() {
        Ok(_) => { return 15 }
        Err(_) => {}
    }
    return 0
}
`,
	}
	dir := t.TempDir()
	result := runProductionCompilerEnv(t, exe, dir, env, files, "run")
	if result != (productionResult{}) {
		t.Fatalf("std.format behavior failed: %+v", result)
	}
	runSanitizedProject(t, cc, repoRoot, dir, "hello")
}
