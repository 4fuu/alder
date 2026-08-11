package compiler

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/4fuu/alder/frontend"
)

const valid = "fn main() -> I32 { return 0 }\n"

func TestValidLogicalPath(t *testing.T) {
	for _, name := range []string{"main.al", "src/main.al", "a/b/c"} {
		if !ValidLogicalPath(name) {
			t.Errorf("ValidLogicalPath(%q) = false", name)
		}
	}
	invalid := []string{"", ".", "..", "../x", "a/../x", "/x", `a\x`, "C:/x", "a//x", "a/./x"}
	invalid = append(invalid, string([]byte{'a', 0, 'b'}))
	for _, name := range invalid {
		if ValidLogicalPath(name) {
			t.Errorf("ValidLogicalPath(%q) = true", name)
		}
	}
}

func TestCompileEmits(t *testing.T) {
	for _, kind := range []EmitKind{EmitNone, EmitMIR, EmitC} {
		r, err := Compile(Request{Sources: []frontend.Source{{ID: 1, Path: "src/main.al", Text: valid}}, Emit: kind})
		if err != nil || len(r.Diagnostics) != 0 {
			t.Fatalf("%s: result=%+v err=%v", kind, r, err)
		}
		if (kind == EmitNone) != (r.Artifact == nil) {
			t.Fatalf("%s: unexpected artifact %+v", kind, r.Artifact)
		}
	}
}

func TestExistingE2ECorpusIsDeterministicThroughService(t *testing.T) {
	files, err := filepath.Glob(filepath.Join("..", "frontend", "testdata", "e2e", "*.al"))
	if err != nil || len(files) == 0 {
		t.Fatalf("find E2E sources: files=%v err=%v", files, err)
	}
	for _, file := range files {
		file := file
		t.Run(filepath.Base(file), func(t *testing.T) {
			text, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			for _, kind := range []EmitKind{EmitMIR, EmitC} {
				req := Request{Sources: []frontend.Source{{ID: 9, Path: "fixture.al", Text: string(text)}}, Emit: kind}
				first, err := Compile(req)
				if err != nil || len(first.Diagnostics) != 0 || first.Artifact == nil {
					t.Fatalf("first %s compile: result=%+v err=%v", kind, first, err)
				}
				second, err := Compile(req)
				if err != nil || len(second.Diagnostics) != 0 || second.Artifact == nil {
					t.Fatalf("second %s compile: result=%+v err=%v", kind, second, err)
				}
				if first.Artifact.Kind != second.Artifact.Kind || first.Artifact.Text != second.Artifact.Text {
					t.Fatalf("%s output is not deterministic", kind)
				}
			}
		})
	}
}

func TestMultiSourcePermutationsProduceIdenticalMIRAndC(t *testing.T) {
	sources := []frontend.Source{
		{ID: 31, Path: "a/types.al", Text: "type Box { value: I64 }\nimport c native: fn(I64) -> I64\n"},
		{ID: 19, Path: "b/helpers.al", Text: "fn make(x: I64) -> Box { return Box(value: x) }\nfn identity(T: type, x: T) -> T { return x }\n"},
		{ID: 27, Path: "c/main.al", Text: "fn main() -> I32 {\n    let box = make(identity(41))\n    let value = unsafe c { native(box.value) }\n    if value != 41 { return 1 }\n    return 0\n}\n"},
	}
	orders := [][]int{{0, 1, 2}, {0, 2, 1}, {1, 0, 2}, {1, 2, 0}, {2, 0, 1}, {2, 1, 0}}
	var wantMIR, wantC string
	for orderIndex, order := range orders {
		ordered := []frontend.Source{sources[order[0]], sources[order[1]], sources[order[2]]}
		before := append([]frontend.Source(nil), ordered...)
		for _, emit := range []EmitKind{EmitMIR, EmitC} {
			result, err := Compile(Request{Sources: ordered, Emit: emit})
			if err != nil || len(result.Diagnostics) != 0 || result.Artifact == nil {
				t.Fatalf("order %v emit %s: result=%+v err=%v", order, emit, result, err)
			}
			if emit == EmitMIR {
				if orderIndex == 0 {
					wantMIR = result.Artifact.Text
				} else if result.Artifact.Text != wantMIR {
					t.Fatalf("order %v produced different MIR", order)
				}
			} else if orderIndex == 0 {
				wantC = result.Artifact.Text
			} else if result.Artifact.Text != wantC {
				t.Fatalf("order %v produced different C", order)
			}
		}
		if !reflect.DeepEqual(ordered, before) {
			t.Fatalf("Compile mutated caller sources: got=%+v want=%+v", ordered, before)
		}
	}
}

func TestDuplicateDeclarationsCarryCanonicalRelatedLocation(t *testing.T) {
	tests := []struct {
		name   string
		first  string
		second string
	}{
		{"same kind", "fn clash() -> Unit { }\n", "fn clash() -> Unit { }\n"},
		{"cross kind", "type clash { value: I64 }\n", "fn clash() -> Unit { }\n"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			sources := []frontend.Source{
				{ID: 8, Path: "z/later.al", Text: test.second},
				{ID: 3, Path: "a/first.al", Text: test.first},
			}
			result, err := Compile(Request{Sources: sources, Emit: EmitNone})
			if err != nil || len(result.Diagnostics) != 1 {
				t.Fatalf("result=%+v err=%v", result, err)
			}
			diagnostic := result.Diagnostics[0]
			if diagnostic.Primary.Source != 8 || len(diagnostic.Related) != 1 || diagnostic.Related[0].Span.Source != 3 || !strings.Contains(diagnostic.Related[0].Message, "first") {
				t.Fatalf("unexpected duplicate diagnostic: %+v", diagnostic)
			}
		})
	}
}

func TestMalformedSourceSelectionUsesCanonicalPathOrder(t *testing.T) {
	sources := []frontend.Source{
		{ID: 9, Path: "z.al", Text: "@"},
		{ID: 4, Path: "a.al", Text: ";"},
	}
	for _, ordered := range [][]frontend.Source{sources, {sources[1], sources[0]}} {
		result, err := Compile(Request{Sources: ordered, Emit: EmitNone})
		if err != nil || len(result.Diagnostics) != 1 || result.Diagnostics[0].Primary.Source != 4 {
			t.Fatalf("sources=%+v result=%+v err=%v", ordered, result, err)
		}
	}
}

func TestSourceFailureHasNoArtifact(t *testing.T) {
	r, err := Compile(Request{Sources: []frontend.Source{{ID: 1, Path: "main.al", Text: "fn main() -> I32 { return nope }"}}, Emit: EmitC})
	if err != nil || len(r.Diagnostics) == 0 || r.Artifact != nil {
		t.Fatalf("result=%+v err=%v", r, err)
	}
}

func TestInvalidRequests(t *testing.T) {
	badPaths := []string{"", ".", "../x.al", "a/../x.al", "/x.al", `a\x.al`, "C:/x.al", "a//x.al"}
	requests := []Request{
		{},
		{Sources: []frontend.Source{{ID: 1, Path: "a.al"}}, Emit: "wat"},
		{Sources: []frontend.Source{{Path: "a.al"}}},
		{Sources: []frontend.Source{{ID: 1, Path: "a.al"}, {ID: 1, Path: "b.al"}}},
		{Sources: []frontend.Source{{ID: 1, Path: "a.al"}, {ID: 2, Path: "a.al"}}},
	}
	for _, p := range badPaths {
		requests = append(requests, Request{Sources: []frontend.Source{{ID: 1, Path: p}}})
	}
	for _, req := range requests {
		_, err := Compile(req)
		var service *ServiceError
		if !errors.As(err, &service) || service.Kind != ErrorInvalidRequest {
			t.Fatalf("%+v: %v", req, err)
		}
	}
	_, err := Compile(Request{Sources: []frontend.Source{{ID: 1, Path: "library.al", Text: "fn helper() -> Unit { }\n"}}, Emit: EmitC})
	var service *ServiceError
	if !errors.As(err, &service) || service.Kind != ErrorInvalidRequest || !strings.Contains(err.Error(), "program entry") {
		t.Fatalf("entry mismatch was not a request error: %v", err)
	}
}
