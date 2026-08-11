package frontend

import "sort"

// DiagnosticCode is a stable machine-readable diagnostic identifier.
// Initial namespaces are LEX (lexical), SYN (syntax), SEM (semantic), and
// LOW/INT (lowering and internal failures, which are returned as Go errors).
type DiagnosticCode string

const (
	CodeLexical  DiagnosticCode = "LEX0001"
	CodeSyntax   DiagnosticCode = "SYN0001"
	CodeSemantic DiagnosticCode = "SEM0001"
)

// Severity is a diagnostic's importance. Additional severities may be added.
type Severity string

const SeverityError Severity = "error"

// RelatedDiagnostic points to supporting source information.
type RelatedDiagnostic struct {
	Span    Span
	Message string
}

// Diagnostic is a source-facing, structured compiler diagnostic.
type Diagnostic struct {
	Code     DiagnosticCode
	Severity Severity
	Message  string
	Primary  Span
	Related  []RelatedDiagnostic
	Notes    []string
}

// SortDiagnostics orders diagnostics deterministically by source range, code,
// and message. It does not mutate the caller's slice.
func SortDiagnostics(in []Diagnostic) []Diagnostic {
	out := append([]Diagnostic(nil), in...)
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if a.Primary.Source != b.Primary.Source {
			return a.Primary.Source < b.Primary.Source
		}
		if a.Primary.Start != b.Primary.Start {
			return a.Primary.Start < b.Primary.Start
		}
		if a.Primary.End != b.Primary.End {
			return a.Primary.End < b.Primary.End
		}
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		return a.Message < b.Message
	})
	return out
}

// SortDiagnosticsBySource orders diagnostics by canonical logical source path,
// then range, code, and message. Source IDs break otherwise identical paths so
// malformed caller input cannot make the comparison partial.
func SortDiagnosticsBySource(in []Diagnostic, sources []Source) []Diagnostic {
	paths := make(map[SourceID]string, len(sources))
	for _, source := range sources {
		paths[source.ID] = source.Path
	}
	out := append([]Diagnostic(nil), in...)
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		ap, bp := paths[a.Primary.Source], paths[b.Primary.Source]
		if ap != bp {
			return ap < bp
		}
		if a.Primary.Source != b.Primary.Source {
			return a.Primary.Source < b.Primary.Source
		}
		if a.Primary.Start != b.Primary.Start {
			return a.Primary.Start < b.Primary.Start
		}
		if a.Primary.End != b.Primary.End {
			return a.Primary.End < b.Primary.End
		}
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		return a.Message < b.Message
	})
	return out
}
