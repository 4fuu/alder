package compiler

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// D0xx M8 binding blocks through the production driver: module-level
// `import c "header.h" as name { ... }` blocks parse, check, lower, and
// verify end to end, while every binding mismatch the contract names is a
// hard rejection. C4 adds the MIR binding lowering and the generated
// _Static_assert probe unit; the checks here pin the checker surface that
// decides the rejections before any C is produced.

const m8BindingProgram = `import c "time.h" as ctime {
    scalar type Time = "time_t"

    opaque type File = "FILE"

    record type Timespec = "struct timespec" {
        seconds: Time = "tv_sec"
        nanos: c.Long = "tv_nsec"
    }

    const ClockRealtime = "CLOCK_REALTIME": c.Int

    raw fn get = "timespec_get"(
        value: c.Ptr(Timespec),
        base: c.Int,
    ) -> c.Int

    raw fn open = "fopen"(
        path: c.ConstPtr(c.Char),
        mode: c.ConstPtr(c.Char),
    ) -> c.Ptr(File)
}

fn main() -> I32 {
    return 0
}
`

var m8BindingRejections = []struct {
	name, source, want string
}{
	{
		"public-block",
		"pub import c \"time.h\" as ctime {\n    opaque type File = \"FILE\"\n}\nfn main() -> I32 { return 0 }\n",
		"public C binding blocks are not supported",
	},
	{
		"missing-spelling",
		"import c \"time.h\" as ctime {\n    opaque type File =\n}\nfn main() -> I32 { return 0 }\n",
		"expected a C spelling string",
	},
	{
		"malformed-member",
		"import c \"time.h\" as ctime {\n    fn f() -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"expected a C binding member declaration",
	},
	{
		"member-separator",
		"import c \"time.h\" as ctime {\n    opaque type A = \"A\"    opaque type B = \"B\"\n}\nfn main() -> I32 { return 0 }\n",
		"expected a C binding member declaration",
	},
	{
		"field-separator",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int    b: c.Int\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"C binding record fields must be separated by a physical line break",
	},
	{
		"duplicate-header",
		"import c \"time.h\" as ctime {\n    opaque type A = \"A\"\n}\n\nimport c \"time.h\" as wall {\n    opaque type B = \"B\"\n}\nfn main() -> I32 { return 0 }\n",
		"a module binds the same C header twice",
	},
	{
		"duplicate-member-name",
		"import c \"time.h\" as ctime {\n    opaque type A = \"A\"\n    raw fn A = \"a_fn\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block declares the same member name twice",
	},
	{
		"duplicate-field-name",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int\n        a: c.Int = \"y\"\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block declares the same member name twice",
	},
	{
		"duplicate-member-spelling",
		"import c \"time.h\" as ctime {\n    opaque type A = \"same\"\n    raw fn f = \"same\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block maps two members to the same C spelling",
	},
	{
		"duplicate-field-spelling",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int = \"x\"\n        b: c.Int = \"x\"\n    }\n}\nfn main() -> I32 { return 0 }\n",
		"a binding block maps two members to the same C spelling",
	},
	{
		"underscore-spelling",
		"import c \"time.h\" as ctime {\n    raw fn f = \"_f\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"C spelling must be a non-reserved C identifier",
	},
	{
		"keyword-spelling",
		"import c \"time.h\" as ctime {\n    raw fn f = \"int\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"C spelling must be a non-reserved C identifier",
	},
	{
		"runtime-prefix-spelling",
		"import c \"time.h\" as ctime {\n    raw fn f = \"alder_f\"(v: c.Int) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"C spelling must be a non-reserved C identifier",
	},
	{
		"scalar-tag-form",
		"import c \"time.h\" as ctime {\n    scalar type T = \"struct timespec\"\n}\nfn main() -> I32 { return 0 }\n",
		"scalar binding spelling may not use a struct, union, or enum tag form",
	},
	{
		"unknown-c-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: c.Longlong) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"unknown C type in the c namespace",
	},
	{
		"unknown-member-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: Missing) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"unknown binding type name in a C binding block",
	},
	{
		"bare-pointer-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: c.Ptr) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"c.Ptr and c.ConstPtr take exactly one type argument",
	},
	{
		"foreign-namespace-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: elsewhere.Thing) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"invalid type in a C binding block",
	},
	{
		"ordinary-applied-type",
		"import c \"time.h\" as ctime {\n    raw fn f = \"f\"(v: Vec(I32)) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"invalid type in a C binding block",
	},
	{
		"opaque-by-value",
		"import c \"time.h\" as ctime {\n    opaque type File = \"FILE\"\n    raw fn f = \"f\"(v: File) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"non-scalar C binding types are only valid behind c.Ptr or c.ConstPtr",
	},
	{
		"record-by-value",
		"import c \"time.h\" as ctime {\n    record type T = \"t_t\" {\n        a: c.Int\n    }\n    raw fn f = \"f\"(v: T) -> c.Int\n}\nfn main() -> I32 { return 0 }\n",
		"non-scalar C binding types are only valid behind c.Ptr or c.ConstPtr",
	},
	{
		"non-integral-const",
		"import c \"time.h\" as ctime {\n    const Epsilon = \"EPSILON\": c.Double\n}\nfn main() -> I32 { return 0 }\n",
		"a C binding constant must have an integral c.* type",
	},
}

func TestM8BindingProductionQualification(t *testing.T) {
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

	files := map[string]string{"m8-bindings.al": m8BindingProgram}
	check := runProductionCompiler(t, exe, files, "check", "m8-bindings.al")
	if check.status != 0 || check.stderr != "" {
		t.Fatalf("binding check result: %+v stderr=%s", check, check.stderr)
	}
	mirText := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "m8-bindings.al")
	if mirText.status != 0 || mirText.stderr != "" || !strings.HasPrefix(mirText.stdout, "mir 6\n") {
		t.Fatalf("binding MIR result: %+v stderr=%s", mirText, mirText.stderr)
	}
	repeat := runProductionCompiler(t, exe, files, "compile", "--emit=mir", "m8-bindings.al")
	if repeat != mirText {
		t.Fatal("binding MIR changed across processes")
	}

	for _, rejection := range m8BindingRejections {
		rejection := rejection
		t.Run("reject-"+rejection.name, func(t *testing.T) {
			t.Parallel()
			files := map[string]string{"reject.al": rejection.source}
			result := runProductionCompiler(t, exe, files, "check", "reject.al")
			if result.status == 0 || !strings.Contains(result.stderr, rejection.want) {
				t.Fatalf("reject %s: status=%d stderr=%q", rejection.name, result.status, result.stderr)
			}
		})
	}
}
