package frontend

import (
	"fmt"
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
	m, sourceErr, err := compileSource(Source{Text: src})
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
	m, sourceErr, err := compileSource(source)
	if err != nil {
		return nil, nil, err
	}
	if sourceErr != nil {
		return sourceFailure(source, sourceErr)
	}
	return m, nil, nil
}

func compileSource(source Source) (*mir.Module, *astError, error) {
	decls, err := parseModuleSource(source)
	if err != nil {
		return splitSourceError(err)
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

func sourceFailure(source Source, ae *astError) (*mir.Module, []Diagnostic, error) {
	span := ae.span
	if span.Source != source.ID || span.Start < 0 || span.Start > len(source.Text) {
		span = Span{}
	}
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
	span = NewSpan(source, span.Start, span.End)
	code := ae.code
	if code == "" {
		code = CodeSemantic
	}
	d := Diagnostic{Code: code, Severity: SeverityError, Message: ae.msg, Primary: span}
	return nil, []Diagnostic{d}, nil
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
