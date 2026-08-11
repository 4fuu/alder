package compiler

import (
	"errors"
	"os"
	"path/filepath"
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

func TestSourceFailureHasNoArtifact(t *testing.T) {
	r, err := Compile(Request{Sources: []frontend.Source{{ID: 1, Path: "main.al", Text: "fn main() -> I32 { return nope }"}}, Emit: EmitC})
	if err != nil || len(r.Diagnostics) == 0 || r.Artifact != nil {
		t.Fatalf("result=%+v err=%v", r, err)
	}
}

func TestInvalidRequests(t *testing.T) {
	badPaths := []string{"", ".", "../x.al", "a/../x.al", "/x.al", `a\x.al`, "C:/x.al", "a//x.al"}
	requests := []Request{{}, {Sources: []frontend.Source{{Path: "a.al"}, {Path: "b.al"}}}, {Sources: []frontend.Source{{Path: "a.al"}}, Emit: "wat"}}
	for _, p := range badPaths {
		requests = append(requests, Request{Sources: []frontend.Source{{Path: p}}})
	}
	for _, req := range requests {
		_, err := Compile(req)
		var service *ServiceError
		if !errors.As(err, &service) || service.Kind != ErrorInvalidRequest {
			t.Fatalf("%+v: %v", req, err)
		}
	}
	_, err := Compile(requests[1])
	if !strings.Contains(err.Error(), "M5.2") {
		t.Fatalf("multiple source error does not mention M5.2: %v", err)
	}
}
