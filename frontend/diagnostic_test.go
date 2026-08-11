package frontend

import "testing"

func TestDiagnosticsSortByLogicalPathNotSourceID(t *testing.T) {
	sources := []Source{{ID: 2, Path: "z.al"}, {ID: 99, Path: "a.al"}}
	diagnostics := []Diagnostic{
		{Code: CodeSemantic, Primary: Span{Source: 2}},
		{Code: CodeSemantic, Primary: Span{Source: 99}},
	}
	sorted := SortDiagnosticsBySource(diagnostics, sources)
	if sorted[0].Primary.Source != 99 || diagnostics[0].Primary.Source != 2 {
		t.Fatalf("sort order=%v, input=%v", sorted, diagnostics)
	}
}

func TestRelatedDiagnosticMustReferenceKnownValidSource(t *testing.T) {
	source := Source{ID: 1, Path: "a.al", Text: "x"}
	ae := &astError{
		line: 1,
		col:  1,
		msg:  "failure",
		span: Span{Source: 1, Start: 0, End: 1},
		related: []RelatedDiagnostic{{
			Span: Span{Source: 2, Start: 0, End: 1},
		}},
	}
	if _, _, err := sourceFailure([]Source{source}, ae); err == nil {
		t.Fatal("unknown related source was not treated as an internal error")
	}
}

func TestCompileSourceDiagnosticKindsAndLegacyParity(t *testing.T) {
	tests := []struct {
		name string
		text string
		code DiagnosticCode
	}{
		{"lexical", "fn main() -> I32 { return 0; }", CodeLexical},
		{"syntax", "fn main() -> I32 { return 0", CodeSyntax},
		{"semantic", "fn main() -> I32 { return missing }", CodeSemantic},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			source := Source{ID: 42, Path: "input.al", Text: tt.text}
			m, diagnostics, err := CompileSource(source)
			if err != nil || m != nil || len(diagnostics) != 1 {
				t.Fatalf("got module=%v diagnostics=%v error=%v", m, diagnostics, err)
			}
			d := diagnostics[0]
			if d.Code != tt.code || d.Severity != SeverityError || d.Primary.Source != source.ID {
				t.Fatalf("unexpected diagnostic: %#v", d)
			}
			if d.Primary.Start < 0 || d.Primary.End < d.Primary.Start || d.Primary.End > len(tt.text) {
				t.Fatalf("invalid span: %#v", d.Primary)
			}
			_, legacy := Compile(tt.text)
			if legacy == nil {
				t.Fatal("legacy Compile unexpectedly succeeded")
			}
			line, column := source.LineColumn(d.Primary.Start)
			if got := formatDiag(line, column, d.Message); got != legacy.Error() {
				t.Fatalf("structured/legacy mismatch: %q != %q", got, legacy)
			}
		})
	}
}

func TestUTF8ByteSpanAndLineColumn(t *testing.T) {
	text := "// é\nfn main() -> I32 { return missing }"
	source := Source{ID: 7, Text: text}
	_, diagnostics, err := CompileSource(source)
	if err != nil || len(diagnostics) != 1 {
		t.Fatalf("diagnostics=%v error=%v", diagnostics, err)
	}
	d := diagnostics[0]
	want := len("// é\nfn main() -> I32 { return ")
	if d.Primary.Start != want {
		t.Fatalf("start=%d, want UTF-8 byte offset %d", d.Primary.Start, want)
	}
	line, column := source.LineColumn(d.Primary.Start)
	if line != 2 || column != 27 {
		t.Fatalf("line/column=(%d,%d), want (2,27)", line, column)
	}
}

func TestLegacyByteColumnAndStructuredUnicodeColumn(t *testing.T) {
	text := "/* é */ fn main() -> I32 { return missing }"
	source := Source{ID: 8, Text: text}

	_, legacy := Compile(text)
	if legacy == nil {
		t.Fatal("legacy Compile unexpectedly succeeded")
	}
	if want := "line 1, column 36: unknown name \"missing\""; legacy.Error() != want {
		t.Fatalf("legacy error = %q, want %q", legacy, want)
	}

	_, diagnostics, err := CompileSource(source)
	if err != nil || len(diagnostics) != 1 {
		t.Fatalf("diagnostics=%v error=%v", diagnostics, err)
	}
	d := diagnostics[0]
	wantStart := len("/* é */ fn main() -> I32 { return ")
	wantEnd := wantStart + len("missing")
	if d.Primary != (Span{Source: source.ID, Start: wantStart, End: wantEnd}) {
		t.Fatalf("semantic span = %#v, want [%d,%d)", d.Primary, wantStart, wantEnd)
	}
	line, column := source.LineColumn(d.Primary.Start)
	if line != 1 || column != 35 {
		t.Fatalf("structured line/column = (%d,%d), want (1,35)", line, column)
	}
}

func TestLexingRetainsLosslessTriviaAndSpelling(t *testing.T) {
	text := " /* é */ fn\tmain() -> I32 {\r\n// note\r\n return 001\r\n}\r\n"
	source := Source{ID: 9, Text: text}
	tokens, err := lexSource(source)
	if err != nil {
		t.Fatal(err)
	}
	var reconstructed string
	for _, token := range tokens {
		reconstructed += text[token.leading.Start:token.leading.End]
		reconstructed += text[token.span.Start:token.span.End]
		if token.span.Source != source.ID || token.leading.Source != source.ID {
			t.Fatalf("token lost source identity: %#v", token)
		}
	}
	if reconstructed != text {
		t.Fatalf("lossy tokenization:\n got %q\nwant %q", reconstructed, text)
	}
	eof := tokens[len(tokens)-1]
	if eof.kind != tokEOF || eof.span.Start != len(text) || eof.span.End != len(text) {
		t.Fatalf("bad EOF span: %#v", eof.span)
	}
}
