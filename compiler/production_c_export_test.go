package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M8 C exports through the production driver: top-level `export c fn`
// declarations emit externally visible C definitions with the C ABI
// signature, the generated header carries only the binding headers the
// signatures reference, and a C driver calls every form (scalar, pointer plus
// length, by-value verified record, Unit result). Rejections pin the C ABI
// type rule (221), the declaration and symbol rules (222), and the raw fn
// spelling collision (223).
const cExportProgram = `import c "cexport.h" as ex {
    record type Pair = "struct cexport_pair" {
        first: c.Long = "first"
        second: c.Long = "second"
    }
}

import c "cextra.h" as extra {
    record type Token = "struct cexport_token" {
        code: c.Long = "code"
    }
}

import c "cunused.h" as unused {
    record type Ignored = "struct cexport_ignored" {
        value: c.Long = "value"
    }
}

export c fn add(a: c.Long, b: c.Long) -> c.Long {
    let sum = a.to_i64() + b.to_i64()
    return sum.to_c_long()
}

export c fn pair_sum(p: Pair) -> c.Long {
    let first = unsafe c { p.first }
    let second = unsafe c { p.second }
    let total = first.to_i64() + second.to_i64()
    return total.to_c_long()
}

export c fn first_byte(data: c.ConstPtr(c.UChar), length: c.Size) -> c.UChar {
    let zero = c.Zero(c.UChar)
    if length.to_u64() == 0 { return zero }
    return unsafe c { c.load(data) }
}

export c fn store_five(out: c.Ptr(c.Long)) -> Unit {
    let five: I64 = 5
    unsafe c { c.store(out, five.to_c_long()) }
    return
}

export c fn token_code(token: Token) -> c.Long {
    return unsafe c { token.code }
}

export c fn ping() -> Unit {
    return
}

fn main() -> I32 {
    return 0
}
`

const cExportFixtureHeader = `#ifndef CEXPORT_H
#define CEXPORT_H
struct cexport_pair {
    long first;
    long second;
};
#endif
`

const cExportExtraHeader = `#ifndef CEXTRA_H
#define CEXTRA_H
struct cexport_token {
    long code;
};
#endif
`

const cExportUnusedHeader = `#ifndef CUNUSED_H
#define CUNUSED_H
struct cexport_ignored {
    long value;
};
#endif
`

const cExportDriver = `#include "exports.h"
#include <stddef.h>

int main(void) {
    struct cexport_pair pair;
    long slot = 0;
    pair.first = 3;
    pair.second = 4;
    if (add(5, 7) != 12) { return 1; }
    if (pair_sum(pair) != 7) { return 2; }
    if (first_byte((const unsigned char *)"A", 1) != (unsigned char)'A') { return 3; }
    if (first_byte((const unsigned char *)"A", 0) != 0) { return 4; }
    store_five(&slot);
    if (slot != 5) { return 5; }
    {
        struct cexport_token token;
        token.code = 9;
        if (token_code(token) != 9) { return 6; }
    }
    ping();
    return 0;
}
`

const cExportRejectPrelude = `import c "cexport.h" as ex {
    record type Pair = "struct cexport_pair" {
        first: c.Long = "first"
        second: c.Long = "second"
    }
    opaque type Handle = "struct cexport_handle"
    raw fn add = "add"(a: c.Long, b: c.Long) -> c.Long
}

`

var cExportRejections = []struct {
	name, source, want string
}{
	{
		"result-not-c-abi",
		cExportRejectPrelude + `export c fn bad(value: c.Long) -> I64 { return value.to_i64() }
`,
		"an export signature type is not a C ABI type",
	},
	{
		"parameter-not-c-abi",
		cExportRejectPrelude + `export c fn bad(text: String) -> c.Long { return c.Zero(c.Long) }
`,
		"an export signature type is not a C ABI type",
	},
	{
		"opaque-by-value",
		cExportRejectPrelude + `export c fn bad(value: Handle) -> Unit { return }
`,
		"an export signature type is not a C ABI type",
	},
	{
		"generic-export",
		cExportRejectPrelude + `export c fn bad(T: type, value: T) -> T { return value }
`,
		"an export must be a non-generic, receiver-free function with a C-safe symbol name other than main",
	},
	{
		"reserved-prefix",
		cExportRejectPrelude + `export c fn alder_export(value: c.Long) -> Unit { return }
`,
		"an export must be a non-generic, receiver-free function with a C-safe symbol name other than main",
	},
	{
		"named-main",
		cExportRejectPrelude + `export c fn main() -> Unit { return }
`,
		"an export must be a non-generic, receiver-free function with a C-safe symbol name other than main",
	},
	{
		"raw-spelling-collision",
		cExportRejectPrelude + `export c fn add(a: c.Long, b: c.Long) -> c.Long { return a }
`,
		"an export symbol collides with a raw fn C spelling",
	},
	{
		"parse-export-shape",
		`export c name(a: c.Long) -> c.Long { return a }
`,
		"an export declaration is `export c fn name(...) -> type { ... }` at module scope",
	},
}

func TestM8CExportProductionQualification(t *testing.T) {
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
	runtimeObject := buildRuntimeObject(t, cc, root)

	dir := t.TempDir()
	files := map[string]string{
		"export.al": cExportProgram,
		"cexport.h": cExportFixtureHeader,
		"cextra.h":  cExportExtraHeader,
		"cunused.h": cExportUnusedHeader,
	}
	emitted := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "export.al")
	if emitted.status != 0 || emitted.stderr != "" || !strings.HasPrefix(emitted.stdout, "/* Generated by the Alder C11 backend.") {
		t.Fatalf("emit=c result: %+v stderr=%s", emitted, emitted.stderr)
	}
	repeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=c", "export.al")
	if repeat.status != 0 || repeat.stdout != emitted.stdout {
		t.Fatalf("emit=c changed across processes")
	}
	if !strings.Contains(emitted.stdout, "long add(long alder_a0, long alder_a1)") {
		t.Fatalf("generated C carries no export wrapper:\n%s", emitted.stdout)
	}
	header := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=header", "export.al")
	if header.status != 0 || header.stderr != "" {
		t.Fatalf("emit=header result: %+v stderr=%s", header, header.stderr)
	}
	headerRepeat := runProductionCompilerAtRoot(t, exe, dir, files, "compile", "--emit=header", "export.al")
	if headerRepeat.status != 0 || headerRepeat.stdout != header.stdout {
		t.Fatalf("emit=header changed across processes")
	}
	for _, want := range []string{
		"#include \"cexport.h\"",
		"#include \"cextra.h\"",
		"long add(long alder_a0, long alder_a1);",
		"long pair_sum(struct cexport_pair alder_a0);",
		"unsigned char first_byte(const unsigned char * alder_a0, size_t alder_a1);",
		"void store_five(long * alder_a0);",
		"long token_code(struct cexport_token alder_a0);",
		"void ping(void);",
	} {
		if !strings.Contains(header.stdout, want) {
			t.Fatalf("generated header misses %q:\n%s", want, header.stdout)
		}
	}
	if strings.Count(header.stdout, "#include \"cexport.h\"") != 1 {
		t.Fatalf("generated header repeats a referenced include:\n%s", header.stdout)
	}
	if strings.Contains(header.stdout, "cunused.h") {
		t.Fatalf("generated header includes an unreferenced binding header:\n%s", header.stdout)
	}
	if strings.Index(header.stdout, "#include \"cexport.h\"") > strings.Index(header.stdout, "#include \"cextra.h\"") {
		t.Fatalf("generated header does not follow binding declaration order:\n%s", header.stdout)
	}
	if strings.Contains(header.stdout, "alder_process") {
		t.Fatalf("generated header keeps the reserved example symbol:\n%s", header.stdout)
	}
	if err := os.WriteFile(filepath.Join(dir, "exports.h"), []byte(header.stdout), 0o644); err != nil {
		t.Fatal(err)
	}
	compileAndRunProductionArtifactWithDriver(t, cc, root, runtimeObject, emitted.stdout, cExportDriver, 0,
		"-I", dir)

	for _, rejection := range cExportRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			rejectFiles := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, rejectFiles, "check", "reject.al")
			if result.status == 0 {
				t.Fatalf("reject %s accepted: %+v", rejection.name, result)
			}
			if !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s diagnostic: got %q, want %q", rejection.name, result.stderr, rejection.want)
			}
		})
	}
}
