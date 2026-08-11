// Package compiler provides the pure, filesystem-independent Alder compiler service.
package compiler

import (
	"fmt"
	"path"
	"strings"

	"github.com/4fuu/alder/cgen"
	"github.com/4fuu/alder/frontend"
	"github.com/4fuu/alder/mir"
	"github.com/4fuu/alder/mir/verify"
)

// EmitKind selects the requested output. EmitNone performs checking only.
type EmitKind string

const (
	EmitNone EmitKind = "none"
	EmitMIR  EmitKind = "mir"
	EmitC    EmitKind = "c"
)

type Request struct {
	Sources []frontend.Source
	Emit    EmitKind
}

type Artifact struct {
	Kind EmitKind
	Text string
}

type Result struct {
	Diagnostics []frontend.Diagnostic
	Artifact    *Artifact
}

// ErrorKind classifies service failures that are not source diagnostics.
type ErrorKind string

const (
	ErrorInvalidRequest ErrorKind = "invalid_request"
	ErrorInternal       ErrorKind = "internal"
)

// ServiceError is returned for invalid requests and compiler invariant failures.
type ServiceError struct {
	Kind    ErrorKind
	Message string
	Cause   error
}

func (e *ServiceError) Error() string {
	if e.Cause != nil {
		return e.Message + ": " + e.Cause.Error()
	}
	return e.Message
}

func (e *ServiceError) Unwrap() error { return e.Cause }

// Compile compiles exactly one explicitly identified source.
func Compile(req Request) (Result, error) {
	if len(req.Sources) == 0 {
		return Result{}, requestError("exactly one source is required")
	}
	if len(req.Sources) != 1 {
		return Result{}, requestError("multiple sources are not supported until M5.2")
	}
	if req.Emit != EmitNone && req.Emit != EmitMIR && req.Emit != EmitC {
		return Result{}, requestError("invalid emit kind")
	}
	source := req.Sources[0]
	if !ValidLogicalPath(source.Path) {
		return Result{}, requestError("source path must be a non-empty canonical relative slash path")
	}
	m, diagnostics, err := frontend.CompileSource(source)
	if err != nil {
		return Result{}, internalError("frontend failure", err)
	}
	if len(diagnostics) != 0 {
		return Result{Diagnostics: frontend.SortDiagnostics(diagnostics)}, nil
	}
	if errs := verify.Module(m); len(errs) != 0 {
		return Result{}, internalError("frontend emitted invalid MIR", fmt.Errorf("%s", verify.Errors(errs).String()))
	}
	result := Result{Diagnostics: []frontend.Diagnostic{}}
	switch req.Emit {
	case EmitNone:
		return result, nil
	case EmitMIR:
		result.Artifact = &Artifact{Kind: EmitMIR, Text: mir.Print(m)}
	case EmitC:
		text, err := cgen.Generate(m)
		if err != nil {
			return Result{}, internalError("C backend failure", err)
		}
		result.Artifact = &Artifact{Kind: EmitC, Text: text}
	}
	return result, nil
}

// ValidLogicalPath reports whether name is a clean, non-empty, relative slash
// path. Logical paths are platform independent and cannot contain colons or
// backslashes, be absolute, or escape their logical root.
func ValidLogicalPath(name string) bool {
	return name != "" && !strings.ContainsAny(name, "\\:\x00") && !strings.HasPrefix(name, "/") && path.Clean(name) == name && name != "." && name != ".." && !strings.HasPrefix(name, "../")
}

func requestError(message string) error {
	return &ServiceError{Kind: ErrorInvalidRequest, Message: message}
}

func internalError(message string, cause error) error {
	return &ServiceError{Kind: ErrorInternal, Message: fmt.Sprintf("internal compiler error: %s", message), Cause: cause}
}
