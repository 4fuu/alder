package compiler

import (
	"testing"
)

// M7.5 slice 1: trait declarations, `where` constraints, trait
// implementations, coherence, and constraint-gated instantiation. These
// fixtures are Alder-only: the Go oracle frontend does not implement the
// trait surface, so they stay out of the shared comparison corpora.
func runAlderM75CheckerBehavior(t *testing.T, exe string) {
	t.Helper()
	accept := map[string]string{
		"traits.al": `type UserCursor {
    row: U64
}

trait Walker(Item: type) {
    fn next(self) -> Option(Item)
    fn peek(self) -> Option(Item) {
        return None
    }
}

impl Walker(U64) for UserCursor {
    fn next(self) -> Option(U64) {
        if self.row == 0 { return None }
        return Some(self.row)
    }
}

fn drain(W: type, T: type, walker: W) -> U64
where W: Walker(T) {
    return 0
}

fn main() -> I32 {
    let cursor = UserCursor(row: 3)
    if drain(UserCursor, U64, cursor) != 0 { return 1 }
    return 0
}
`,
		"markers.al": `type Box {
    v: U64
}

trait Marker(A: type) {
}

impl Marker(U64) for Box {
}

fn use_mark(M: type, A: type, b: M) -> U64
where M: Marker(A) {
    return 0
}

fn main() -> I32 {
    let box = Box(v: 1)
    if use_mark(Box, U64, box) != 0 { return 1 }
    return 0
}
`,
		"trait-params.al": `trait IntoWalker(Iter: type, Item: type)
where Iter: Stepper(Item) {
    fn into_walker(self) -> Iter
}

trait Stepper(Item: type) {
    fn next(self) -> Option(Item)
}

fn main() -> I32 { return 0 }
`,
		"impl-body.al": `type Box {
    v: U64
}

trait Getter {
    fn get(self) -> U64
}

impl Getter for Box {
    fn get(self) -> U64 {
        return self.v
    }
}

fn main() -> I32 {
    let box = Box(v: 7)
    return 0
}
`,
	}
	for name, source := range accept {
		t.Run("accept-"+name, func(t *testing.T) {
			files := map[string]string{name: source}
			manifest := parseCheckerManifest(t, runAlderChecker(t, exe, files, []string{name}, false), files)
			if len(manifest.diagnostics) != 0 {
				t.Fatalf("M7.5 acceptance diagnostics: %+v", manifest.diagnostics)
			}
		})
	}

	rejections := []struct {
		name, source string
		code         int
	}{
		{"duplicate-impl", "type Box { v: U64 }\ntrait Mark { }\nimpl Mark for Box { }\nimpl Mark for Box { }\nfn main() -> I32 { return 0 }\n", 107},
		{"unknown-trait", "type Box { v: U64 }\nfn f(M: type, b: M) -> U64\nwhere M: Missing {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 108},
		{"trait-arity", "type Box { v: U64 }\ntrait Mark(A: type) { }\nfn f(M: type, b: M) -> U64\nwhere M: Mark {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 109},
		{"impl-target-application", "trait Mark { }\nimpl Mark for Vec(U64) { }\nfn main() -> I32 { return 0 }\n", 110},
		{"impl-target-unknown", "trait Mark { }\nimpl Mark for Missing { }\nfn main() -> I32 { return 0 }\n", 110},
		{"unsatisfied-constraint", "type Box { v: U64 }\ntrait Mark { }\nfn f(M: type, b: M) -> U64\nwhere M: Mark {\n    return 0\n}\nfn main() -> I32 {\n    if f(Box, Box(v: 1)) != 0 { return 1 }\n    return 0\n}\n", 111},
		{"constraint-unknown-param", "type Box { v: U64 }\ntrait Mark { }\nfn f(M: type, b: M) -> U64\nwhere X: Mark {\n    return 0\n}\nfn main() -> I32 { return 0 }\n", 112},
		{"impl-where", "type Box { v: U64 }\ntrait Mark { }\nimpl Mark for Box\nwhere Box: Mark {\n}\nfn main() -> I32 { return 0 }\n", 113},
		{"trait-as-type", "trait Mark { }\nfn f(m: Mark) -> U64 { return 0 }\nfn main() -> I32 { return 0 }\n", 114},
		{"self-outside-trait", "fn f(v: Self) -> U64 { return 0 }\nfn main() -> I32 { return 0 }\n", 117},
		{"trait-method-params", "trait Mark {\n    fn m(A: type, v: A) -> U64\n}\nfn main() -> I32 { return 0 }\n", 118},
	}
	for _, tc := range rejections {
		t.Run(tc.name, func(t *testing.T) {
			files := map[string]string{tc.name + ".al": tc.source}
			text := runAlderChecker(t, exe, files, []string{tc.name + ".al"}, true)
			manifest := parseCheckerManifest(t, text, files)
			if len(manifest.diagnostics) != 1 {
				t.Fatalf("expected exactly one rejection diagnostic, got %+v", manifest.diagnostics)
			}
			if manifest.diagnostics[0].kind != tc.code {
				t.Fatalf("expected diagnostic kind %d, got %d", tc.code, manifest.diagnostics[0].kind)
			}
		})
	}
}
