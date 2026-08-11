package frontend

import (
	"fmt"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// Compile compiles a source module to a MIR module. Type inference and
// monomorphization complete before any backend MIR exists. The result is
// deterministic and must pass mir/verify unchanged; the cgen package enforces
// that gate on its own.
func Compile(src string) (*mir.Module, error) {
	m, sourceErr, err := compileSources([]Source{{Text: src}})
	if err != nil {
		return nil, err
	}
	if sourceErr != nil {
		return nil, sourceErr
	}
	return m, nil
}

// CompileSource compiles one explicitly identified source. User source
// failures are returned as diagnostics; invariant and internal failures remain
// Go errors.
func CompileSource(source Source) (*mir.Module, []Diagnostic, error) {
	return CompileSources([]Source{source})
}

// CompileSources compiles an explicit source set as one global compilation
// unit. Sources are ordered by canonical logical path and declarations retain
// their lexical order within each source. User source failures are returned as
// diagnostics; invariant and internal failures remain Go errors.
func CompileSources(sources []Source) (*mir.Module, []Diagnostic, error) {
	ordered := append([]Source(nil), sources...)
	sort.SliceStable(ordered, func(i, j int) bool {
		if ordered[i].Path != ordered[j].Path {
			return ordered[i].Path < ordered[j].Path
		}
		return ordered[i].ID < ordered[j].ID
	})
	m, sourceErr, err := compileSources(ordered)
	if err != nil {
		return nil, nil, err
	}
	if sourceErr != nil {
		return sourceFailure(ordered, sourceErr)
	}
	return m, nil, nil
}

func compileSources(sources []Source) (*mir.Module, *astError, error) {
	if len(sources) == 0 {
		return nil, nil, fmt.Errorf("frontend: no sources")
	}
	var decls []Decl
	for _, source := range sources {
		parsed, err := parseModuleSource(source)
		if err != nil {
			return splitSourceError(err)
		}
		decls = append(decls, parsed...)
	}
	cm, err := checkModule(decls)
	if err != nil {
		return splitSourceError(err)
	}
	m, err := lowerModule(decls, cm)
	if err != nil {
		return splitSourceError(err)
	}
	if errs := verify.Module(m); len(errs) != 0 {
		return nil, nil, fmt.Errorf("internal frontend error: emitted invalid MIR: %s", verify.Errors(errs).String())
	}
	return m, nil, nil
}

func splitSourceError(err error) (*mir.Module, *astError, error) {
	ae, ok := err.(*astError)
	if !ok || strings.HasPrefix(ae.msg, "internal:") {
		return nil, nil, err
	}
	return nil, ae, nil
}

func sourceFailure(sources []Source, ae *astError) (*mir.Module, []Diagnostic, error) {
	byID := make(map[SourceID]Source, len(sources))
	for _, source := range sources {
		byID[source.ID] = source
	}
	source, ok := byID[ae.span.Source]
	if !ok {
		return nil, nil, fmt.Errorf("internal frontend error: diagnostic refers to unknown source ID %d", ae.span.Source)
	}
	span := ae.span
	if span.Start == 0 && span.End == 0 {
		span.Start = offsetForLegacyPosition(source.Text, ae.line, ae.col)
		span.End = span.Start
		if span.Start < len(source.Text) {
			_, n := utf8.DecodeRuneInString(source.Text[span.Start:])
			if n < 1 {
				n = 1
			}
			span.End += n
		}
	}
	if err := validDiagnosticSpan(source, span); err != nil {
		return nil, nil, err
	}
	code := ae.code
	if code == "" {
		code = CodeSemantic
	}
	d := Diagnostic{
		Code:     code,
		Severity: SeverityError,
		Message:  ae.msg,
		Primary:  span,
		Related:  append([]RelatedDiagnostic(nil), ae.related...),
		Notes:    append([]string(nil), ae.notes...),
	}
	for _, related := range d.Related {
		relatedSource, ok := byID[related.Span.Source]
		if !ok {
			return nil, nil, fmt.Errorf("internal frontend error: related diagnostic refers to unknown source ID %d", related.Span.Source)
		}
		if err := validDiagnosticSpan(relatedSource, related.Span); err != nil {
			return nil, nil, err
		}
	}
	return nil, SortDiagnosticsBySource([]Diagnostic{d}, sources), nil
}

func validDiagnosticSpan(source Source, span Span) error {
	if span.Source != source.ID || span.Start < 0 || span.End < span.Start || span.End > len(source.Text) {
		return fmt.Errorf("internal frontend error: invalid diagnostic range [%d,%d) for source ID %d", span.Start, span.End, span.Source)
	}
	return nil
}

// offsetForLegacyPosition converts the lexer's historical byte-counted column
// to a byte offset. It exists solely to preserve exact legacy Error rendering.
func offsetForLegacyPosition(text string, line, column int) int {
	offset, currentLine := 0, 1
	for offset < len(text) && currentLine < line {
		if text[offset] == '\n' {
			currentLine++
		}
		offset++
	}
	offset += column - 1
	if offset < 0 {
		return 0
	}
	if offset > len(text) {
		return len(text)
	}
	return offset
}
